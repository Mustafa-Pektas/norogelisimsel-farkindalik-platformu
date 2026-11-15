"""Isme tepki araci: mevcut olcum ve filtreleri tek raporda birlestirir."""
import argparse
import copy
import csv
import hashlib
import json
import math
import os
import re
from pathlib import Path
import sys
from datetime import datetime

import numpy as np
from scipy.spatial.transform import Rotation

from konusmaci import SOURCE as AUDIO_VISUAL_SOURCE, align_calls


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def write(path, value):
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2,
                                   allow_nan=False) + '\n', encoding='utf-8')


def digest(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def project_paths(root):
    research = list(root.glob('norogelisimsel*/norogelisimsel*/research/d01'))
    if len(research) != 1 or not (root / 'ses_yonelme/sesyon').is_dir():
        raise ValueError('Proje koku bulunamadi; --project-root ile belirtin.')
    sys.path.insert(0, str(research[0]))
    sys.path.insert(0, str(root / 'ses_yonelme'))
    return research[0]


def path_at(base, value):
    p = Path(value)
    return (p if p.is_absolute() else base / p).resolve()


def number(value):
    return type(value) in (int, float) and math.isfinite(value) and value >= 0


def validate_calls(calls):
    ids = set()
    for call in calls:
        if (not isinstance(call.get('id'), str) or
                not re.fullmatch(r'[A-Za-z0-9_-]+', call['id']) or call['id'] in ids):
            raise ValueError('Seslenme id benzersiz olmali; yalniz harf/rakam/_/- kullanin.')
        ids.add(call['id'])
        if not all(number(call.get(k)) for k in ('start_s', 'end_s')) or call['end_s'] < call['start_s']:
            raise ValueError('Seslenme baslangic/bitis zamanlari gecersiz.')
        if not call.get('timing_source'):
            raise ValueError('Seslenmede timing_source belirtilmeli: manual veya asr_estimate gibi.')
        manual = call.get('manual_movement', {})
        for key in ('start_s', 'end_s'):
            if manual.get(key) is not None and not number(manual[key]):
                raise ValueError('Manuel hareket zamani gecersiz.')
        if (manual.get('start_s') is not None and manual.get('end_s') is not None
                and manual['end_s'] < manual['start_s']):
            raise ValueError('Manuel hareket bitisi baslangictan once olamaz.')


def audio_calls(video, options, root, out):
    """Istege bagli; mevcut ses aracinin kelime/isim taslagini kullanir."""
    from types import SimpleNamespace
    sys.path.insert(0, str(root / 'audio_label_tool'))
    from audio_labels import make_draft
    from faster_whisper import WhisperModel
    model_name = options.get('model', 'small')
    args = SimpleNamespace(name=options['name'], model=model_name, no_vad=False)
    model = WhisperModel(model_name, device='cpu', compute_type='int8')
    segments, info = model.transcribe(str(video), language=options.get('language', 'tr'),
                                     word_timestamps=True, vad_filter=True,
                                     condition_on_previous_text=False)
    draft = make_draft(video, segments, info, args)
    write(out / 'ses_taslagi.json', draft)
    return [dict(id='ses_%03d' % (i + 1), name=options['name'], start_s=w['start_s'],
                 end_s=w['end_s'], timing_source='asr_estimate_unreviewed',
                 speaker_target_id=None, speaker_source='unresolved')
            for i, w in enumerate(draft['automatic_proposals']['name_call_candidates'])]


def normalize_rows(original):
    """FaceMesh JSON ve D01 JSONL; zaman/kayip olcum uydurulmaz."""
    from motion_candidates import rotation
    rows = []
    previous_index = -1
    previous_time = -1.0
    for r in original:
        index = r.get('frame_index', r.get('frame'))
        t = r.get('decoder_time_s') if 'decoder_time_s' in r else r.get('time_s')
        if type(index) is not int or index <= previous_index:
            raise ValueError('Kare numaralari artan ve benzersiz olmali.')
        if t is not None and (not number(t) or t <= previous_time):
            raise ValueError('Olcum zamanlari artan olmali; bozuk zamanlar duzeltilmez.')
        m = r.get('rotation_matrix')
        if m is None and r.get('rotation_vector') is not None:
            v = np.asarray(r['rotation_vector'], dtype=float)
            if v.shape == (3,) and np.isfinite(v).all():
                m = Rotation.from_rotvec(v).as_matrix()
        m = rotation(m) if r.get('valid', True) else None
        valid = m is not None and t is not None
        rows.append(dict(frame_index=index, time_s=t, valid=valid,
                         rotation_matrix=m.tolist() if valid else None))
        previous_index = index
        if t is not None:
            previous_time = t
    if not rows:
        raise ValueError('Olcum dosyasi bos.')
    return rows


def filtered(rows, alpha, fps):
    from rotation_processing import causal_ema_matrices
    breaks = set()
    for i in range(1, len(rows)):
        a, b = rows[i - 1], rows[i]
        if (a['time_s'] is None or b['time_s'] is None or
                b['frame_index'] != a['frame_index'] + 1 or
                b['time_s'] - a['time_s'] > 1.5 / fps):
            breaks.add(i)
    matrices = [np.array(r['rotation_matrix']) if r['valid'] else None for r in rows]
    smoothed = causal_ema_matrices(matrices, alpha, break_before=breaks)
    return [dict(r, rotation_matrix=None if m is None else m.tolist(), valid=m is not None)
            for r, m in zip(rows, smoothed)]


def direction(call, gaze, start, finish, fps=6):
    """Hedef tahminini çağıran kişiyle kaynak bilgisini koruyarak karşılaştırır."""
    from sesyon.events import sustained
    target = call.get('speaker_target_id')
    if not target or call.get('speaker_source') not in ('manual_user_verified', AUDIO_VISUAL_SOURCE):
        label = call.get('speaker_alignment', {}).get('label', 'Çağıran kişi doğrulanmadı')
        return dict(status='unknown_caller', label=label, correct=None)
    if not gaze:
        return dict(status='no_target_data', label='Hedef ölçümü yok', correct=None)
    before = [r for r in gaze if call['start_s'] - .8 <= r['time_s'] < call['start_s']]
    on_target = lambda r: r.get('target') == target
    if sustained(before, on_target, .33, 1.6 / fps):
        return dict(status='already_oriented', label='Çağrı öncesinde hedefe yönelmiş', correct=None)
    if start is None:
        return dict(status='unknown_onset', label='Hareket başlangıcı bilinmiyor', correct=None)
    post = [r for r in gaze if start <= r['time_s'] <= finish]
    def other_run(samples):
        ids = {r.get('target') for r in samples} - {None, 'ambiguous', 'unavailable', 'offscreen', target}
        for identity in sorted(ids):
            found = sustained(samples, lambda r: r.get('target') == identity, .33, 1.6 / fps)
            if found:
                return dict(found, target=identity)
        return None
    if not other_run(before):
        return dict(status='unknown_baseline', label='Çağrı öncesi hedef belirsiz', correct=None)
    target_run = sustained(post, on_target, .33, 1.6 / fps)
    if target_run:
        return dict(status='toward_caller_candidate', label='Çağıran kişinin yönüyle uyumlu aday',
                    correct=True, **target_run)
    other = other_run(post)
    if other:
        return dict(status='other_target_candidate', label='Başka hedefe yönelme adayı',
                    correct=False, **other)
    return dict(status='uncertain', label='Yön belirsiz', correct=None)


def call_results(calls, detections, gaze, last_time, observation_s, gaze_fps):
    results = []
    for call in calls:
        stop = min(last_time, call['start_s'] + observation_s)
        manual = call.get('manual_movement', {})
        manual_start = manual.get('start_s')
        manual_end = manual.get('end_s')
        variants = {}
        for method, detected in detections.items():
            candidates = []
            for c in detected['candidates']:
                # Cagri oncesinde baslamis/devam eden adaylar da korunur.
                first = c['start_s'] if c['start_s'] is not None else c['first_high_evidence_s']
                last = c['end_s'] if c['end_s'] is not None else c.get('last_supported_time_s', last_time)
                if first > stop or last < call['start_s']:
                    continue
                after = c['start_s'] is not None and c['start_s'] >= call['start_s']
                candidate_end = c['end_confirmed_s'] if c['end_s'] is not None else last
                bounded_end = min(stop, candidate_end)
                d = direction(call, gaze, c['start_s'] if after else None, bounded_end, gaze_fps)
                candidates.append(dict(c,
                    relation='after_call_candidate' if after else 'preexisting_or_unknown_start',
                    latency_from_start_s=c['start_s'] - call['start_s'] if after else None,
                    latency_from_end_s=c['start_s'] - call['end_s'] if after else None,
                    movement_duration_s=c['end_s'] - c['start_s']
                        if c['end_s'] is not None and c['start_s'] is not None else None,
                    start_minus_manual_s=c['start_s'] - manual_start
                        if c['start_s'] is not None and manual_start is not None else None,
                    end_minus_manual_s=c['end_s'] - manual_end
                        if c['end_s'] is not None and manual_end is not None else None,
                    direction=d))
            variants[method] = candidates
        results.append(dict(call=call, manual_latency_from_start_s=manual_start - call['start_s']
                            if manual_start is not None else None, observation_end_s=stop,
                            observation_complete=last_time >= call['start_s'] + observation_s,
                            methods=variants))
    return results


def load_gaze(path):
    gaze = read(path) if path else []
    previous = -1
    for r in gaze:
        if not number(r.get('time_s')) or r['time_s'] <= previous:
            raise ValueError('Hedef zamanlari artan olmali.')
        previous = r['time_s']
    return gaze


def look_at_caller(call, gaze, finish, fps):
    start = call['start_s']
    assessment = direction(call, gaze, start, finish, fps)
    status, label = assessment['status'], assessment['label']
    if status != 'toward_caller_candidate':
        return dict(status=status, label=label)
    observed = assessment['start_s']
    prior = next((r for r in reversed(gaze) if r['time_s'] < observed), None)
    if (prior and prior['time_s'] < start and observed - prior['time_s'] <= 1.6 / fps and
            prior.get('target') == call['speaker_target_id']):
        return dict(status='already_oriented', label='Doğrulanan hedef dizisi çağrıdan önce başladı')
    return dict(status='observed', label=label, event='bakti', time_s=observed,
                confirmed_s=assessment['confirmed_s'], target=call['speaker_target_id'])


def add_optical_flow(out, result, video, original, methods, gaze, scene, gaze_fps, options,
                     pose_tracks=None, include_late_return=False):
    from optik_akis import export_samples, measure, motion_stops, pose_events

    fps = result['video']['fps']
    samples = measure(video, original, methods['raw'], scene, fps)
    stops = motion_stops(samples, options)
    export_samples(out / 'optik_akis.csv', samples)
    result['optical_flow'] = dict(parameters=options, speed_unit='head_diagonals_per_second',
                                  usable_pairs=sum(s['speed'] is not None for s in samples), stops=stops)
    return_series = {'recorded': methods['ema_050']}
    if pose_tracks:
        return_series.update({name: filtered(track, .5, fps) for name, track in pose_tracks.items()})
    primary_pose = 'directmhp' if pose_tracks else 'recorded'
    last_time = max(row['time_s'] for row in return_series[primary_pose] if row['time_s'] is not None)
    for event in result['calls']:
        call, finish = event['call'], event['observation_end_s']
        start = call['start_s']
        measured = sum(s['speed'] is not None and start <= s['time_s'] <= finish for s in samples)
        in_window = []
        for stop in stops:
            if start <= stop['time_s'] and stop['confirmed_s'] <= finish:
                onset = stop['movement_start_s']
                relation = 'after_call' if onset is not None and onset >= start else 'preexisting_or_unknown_start'
                in_window.append(dict(stop, relation=relation))
        returns = {name: pose_events(track, start, finish, fps, options)
                   for name, track in return_series.items()}
        event['optical_flow'] = dict(look=look_at_caller(call, gaze, finish, gaze_fps),
            stop=dict(status='observed' if in_window else 'unconfirmed' if measured else 'no_flow_data',
                      usable_pairs=measured, events=in_window),
            return_to_baseline=returns[primary_pose])
        if pose_tracks:
            event['optical_flow'].update(return_pose_method=primary_pose, return_comparison=returns)
        if include_late_return and finish < last_time:
            later_calls = [item['call']['start_s'] for item in result['calls'] if item['call']['start_s'] > start]
            extended_end = min([last_time] + [t - 1e-6 for t in later_calls])
            if extended_end > finish:
                extended = pose_events(return_series[primary_pose], start, extended_end, fps, options)
                late = [item for item in extended['events'] if item['confirmed_s'] > finish]
                if late:
                    event['optical_flow']['return_after_window'] = late
    return samples


def pose_model_paths(cfg, base):
    if 'head_pose' not in cfg:
        return {}
    settings = cfg['head_pose']
    if (not isinstance(settings, dict) or settings.keys() - {'directmhp', 'repnet360'} or
            not settings.get('directmhp') or not all(isinstance(value, str) and value for value in settings.values())):
        raise ValueError('head_pose içinde directmhp model yolu ve isteğe bağlı repnet360 ağırlık yolu bekleniyor.')
    paths = {name: path_at(base, value) for name, value in settings.items()}
    for path in paths.values():
        if not path.is_file():
            raise ValueError(f'Baş pozu modeli bulunamadı: {path}')
    return paths


def add_head_pose(out, result, video, rows, original, scene, root, paths, requested_device):
    import torch
    from bas_pozu import LABELS, export, measure, resolve_device

    device = resolve_device(torch, requested_device)
    device_name = torch.cuda.get_device_name(0) if device == 'cuda' else 'CPU'
    print(f'Baş pozu modelleri çalışıyor: {device.upper()} ({device_name})', flush=True)
    tracks, metadata = measure(video, rows, original, scene, root, paths, device=device)
    summary = {}
    for name, track in {'recorded': rows, **tracks}.items():
        summary[name] = dict(label=LABELS[name], valid_frames=sum(row['valid'] for row in track),
                             recovered_frames=sum(r['valid'] and not old['valid'] for r, old in zip(track, rows)))
        if name in paths:
            summary[name]['model_sha256'] = digest(paths[name])
    result['head_pose'] = dict(primary='directmhp', methods=summary, directmhp_model=metadata,
                              device=device, device_name=device_name)
    export(out / 'bas_pozu.csv', {'recorded': rows, **tracks})
    return tracks


def run(config_path, output, root, head_pose_device='auto'):
    research = project_paths(root)
    from motion_candidates import detect
    from rapor import render
    from karsilastir import evaluate, export_csv
    cfg = read(config_path)
    flow_options = None
    if 'optical_flow' in cfg:
        from optik_akis import parameters
        flow_options = parameters(cfg['optical_flow'])
    speaker_alignment = cfg.get('speaker_alignment', flow_options is not None)
    if type(speaker_alignment) is not bool:
        raise ValueError('speaker_alignment true veya false olmali.')
    annotated_video = cfg.get('annotated_video', False)
    if type(annotated_video) is not bool:
        raise ValueError('annotated_video true veya false olmali.')
    base = config_path.parent
    pose_paths = pose_model_paths(cfg, base)
    video = path_at(base, cfg['video'])
    if not video.is_file():
        raise ValueError('Video bulunamadi: ' + str(video))
    video_hash = digest(video)
    scene = read(path_at(base, cfg['scene_config'])) if cfg.get('scene_config') else {}
    calls = copy.deepcopy(cfg.get('calls', scene.get('calls', [])))
    validate_calls(calls)
    output.mkdir(parents=True, exist_ok=False)
    write(output / 'durum.json', {'status': 'running'})
    try:
        if not calls and cfg.get('audio'):
            calls = audio_calls(video, cfg['audio'], root, output)
            validate_calls(calls)
        if cfg.get('frames'):
            frame_path = path_at(base, cfg['frames'])
            metadata = read(path_at(base, cfg['recorded_metadata']))
            identity = metadata.get('video', {})
            if identity.get('sha256', metadata.get('video_sha256')) != video_hash:
                raise ValueError('Kayitli olcum ve video SHA256 eslesmiyor.')
            fps = identity.get('fps', metadata.get('fps'))
            if frame_path.suffix.lower() == '.jsonl':
                original = [json.loads(line) for line in frame_path.read_text(encoding='utf-8-sig').splitlines() if line.strip()]
            else:
                original = read(frame_path)
            gaze_path = path_at(base, cfg['gaze']) if cfg.get('gaze') else None
            gaze = load_gaze(gaze_path)
            provenance = dict(mode='recorded', frames=str(frame_path), frames_sha256=digest(frame_path),
                              metadata_sha256=digest(path_at(base, cfg['recorded_metadata'])),
                              gaze_sha256=digest(gaze_path) if gaze_path else None)
        else:
            if not scene:
                raise ValueError('Yeni video icin scene_config, kayit icin frames ve recorded_metadata gerekir.')
            from sesyon.pipeline import run as measure_video
            scene['calls'] = calls
            measurement = output / 'olcum'
            measurement.mkdir()
            measure_video(scene, video, measurement, gaze_enabled=True)
            frame_path = measurement / 'frames.json'
            original = read(frame_path)
            metadata = read(measurement / 'result.json')
            fps = metadata['video']['fps']
            gaze = load_gaze(measurement / 'gaze.json')
            provenance = dict(mode='video', frames=str(frame_path), frames_sha256=digest(frame_path))
        if not number(fps) or abs(fps - 24) > 1e-6:
            raise ValueError('Mevcut hareket protokolu 24 FPS ister; otomatik uyarlama yapilmaz.')
        rows = normalize_rows(original)
        times = [r['time_s'] for r in rows if r['time_s'] is not None]
        if not times:
            raise ValueError('Gecerli olcum zamani yok.')
        last_time = max(times)
        if any(max(c['end_s'], c.get('manual_movement', {}).get('end_s') or 0,
                   c.get('manual_movement', {}).get('start_s') or 0) > last_time + 1 / fps for c in calls):
            raise ValueError('Seslenme video zaman araliginin disinda.')
        for r in gaze:
            if r['time_s'] > last_time + 1 / fps:
                raise ValueError('Hedef kaydi video zaman araliginin disinda.')
        motion = read(research / 'parameters/motion_candidates_v1.json')
        # Var olan protokol aynen kullanilir; manuel zamanlar dedektore verilmez.
        methods = {'raw': rows, 'ema_050': filtered(rows, .5, fps),
                   'ema_025': filtered(rows, .25, fps)}
        setting = next(s for s in motion['settings'] if s['id'] == 'base')
        detections = {name: detect(rs, motion, setting) for name, rs in methods.items()}
        observation = cfg.get('observation_s', 4.0)
        if not number(observation) or observation <= 0:
            raise ValueError('observation_s pozitif olmali.')
        gaze_fps = cfg.get('gaze_fps', metadata.get('configuration', scene).get('settings', {}).get('gaze_fps', 6))
        if not number(gaze_fps) or gaze_fps <= 0:
            raise ValueError('gaze_fps pozitif olmali.')
        scene_for_analysis = scene or metadata.get('configuration') or {}
        if speaker_alignment:
            align_calls(video, calls, rows, scene_for_analysis, fps)
        result = dict(schema_version=1, video=dict(path=str(video), sha256=video_hash, fps=fps),
            provenance=provenance, parameters=motion, selected_method='ema_050',
            method_roles={'raw': 'ham karsilastirma', 'ema_050': 'ana aday', 'ema_025': 'daha guclu yumusatma deneyi'},
            frame_count=len(rows), valid_frames=sum(r['valid'] for r in rows),
            calls=call_results(calls, detections, gaze, last_time, observation, gaze_fps),
            limitations=[
                'Sonuçlar isme tepki kanıtı değil, zaman ve yön uyumu adaylarıdır.',
                'Hareket sınırları fiziksel ilk/son hareket değil, filtre ve eşik sınırlarıdır.',
                'EMA hareketi ve sınırları geciktirebilir; ana yöntem doğrulanmış en iyi yöntem değildir.',
                'Seslenme kaynağı her olayda korunur. ASR zamanları dinlenerek doğrulanmalıdır.',
                'Yön uyumu için çağıran kişi eşleşmesi gerekir. Otomatik eşleşme ses ve ağız hareketine dayalı bir adaydır.',
                'Hedef tahmini göz teması veya nedensellik göstermez; güven yüzdesi üretilmez.',
                'Eksik ölçümler doldurulmaz. Aday bulunmaması tepki yok anlamına gelmez.',
                'Ses/video senkronu ve model doğruluğu bağımsız olarak doğrulanmamıştır.'])
        pose_tracks = None
        if pose_paths:
            pose_tracks = add_head_pose(output, result, video, rows, original, scene_for_analysis, root,
                                        pose_paths, head_pose_device)
        flow_samples = None
        if flow_options is not None:
            flow_samples = add_optical_flow(output, result, video, original, methods, gaze,
                                            scene_for_analysis, gaze_fps, flow_options, pose_tracks,
                                            include_late_return=annotated_video)
        # Insan etiketleri ancak dedektor sonuclari sabitlendikten sonra okunur.
        video_meta = metadata.get('video', {})
        declared_frames = video_meta.get('frame_count', video_meta.get('declared_frame_count'))
        duration = video_meta.get('duration_s', declared_frames / fps if declared_frames else last_time + 1 / fps)
        if not number(duration) or duration < last_time:
            raise ValueError('Video suresi olcum zamanlariyla uyusmuyor.')
        labels = None
        if cfg.get('manual_labels'):
            labels_path = path_at(base, cfg['manual_labels'])
            labels = read(labels_path)
            result['provenance']['manual_labels_sha256'] = digest(labels_path)
            write(output / 'etiketler_kullanilan.json', labels)
        else:
            write(output / 'etiketler_sablon.json', dict(video_sha256=video_hash, reviewed=False,
                reviewer='', intervals=[dict(start_s=0, end_s=duration, complete=False, movements=[])]))
        comparison = evaluate(labels, result, detections, rows, duration, cfg.get('comparison_rules'))
        result['comparison'] = comparison
        if annotated_video:
            from isaretli_video import write_video
            print('İşaretli video hazırlanıyor...', flush=True)
            result['annotated_video'] = write_video(output, result, original, gaze, gaze_fps,
                                                    pose_tracks, flow_samples)
        write(output / 'karsilastirma.json', comparison)
        export_csv(output / 'hatalar.csv', comparison)
        write(output / 'ayarlar.json', cfg)
        write(output / 'adaylar.json', detections)
        write(output / 'sonuc.json', result)
        with (output / 'hareketler.csv').open('w', encoding='utf-8-sig', newline='') as f:
            fields = ['call_id', 'method', 'candidate_id', 'relation', 'start_s', 'end_s',
                      'start_confirmed_s', 'end_confirmed_s', 'latency_from_start_s',
                      'latency_from_end_s', 'movement_duration_s', 'start_minus_manual_s',
                      'end_minus_manual_s', 'direction', 'correct']
            writer = csv.DictWriter(f, fieldnames=fields)
            writer.writeheader()
            for event in result['calls']:
                for method, candidates in event['methods'].items():
                    for c in candidates:
                        row = {k: c.get(k) for k in fields}
                        row.update(call_id=event['call']['id'], method=method,
                                   direction=c['direction']['status'], correct=c['direction']['correct'])
                        writer.writerow(row)
        os.environ['MPLCONFIGDIR'] = str(output / '.matplotlib')
        render(output, result, methods, detections, gaze, flow_samples=flow_samples)
        write(output / 'durum.json', {'status': 'completed'})
        return result
    except BaseException as exc:
        write(output / 'durum.json', {'status': 'failed', 'error': str(exc)})
        raise


def main():
    parser = argparse.ArgumentParser(description='Isme tepki: olcum, hareket, sure ve yon raporu.')
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--out', type=Path)
    parser.add_argument('--project-root', type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument('--head-pose-device', choices=('auto', 'cpu', 'cuda'), default='auto',
                        help='DirectMHP ve 6DRepNet360 için aygıt')
    args = parser.parse_args()
    output = (args.out or Path(__file__).parent / 'outputs' /
              datetime.now().strftime('%Y%m%d_%H%M%S_%f')).resolve()
    try:
        run(args.config.resolve(), output, args.project_root.resolve(), args.head_pose_device)
    except (ValueError, KeyError, OSError, ImportError) as exc:
        parser.exit(1, 'Analiz tamamlanamadi: %s\n' % exc)
    print('Rapor: ' + str(output / 'rapor.html'))


if __name__ == '__main__':
    main()
