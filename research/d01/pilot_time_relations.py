"""Report arithmetic time relations from saved records; no detection or inference."""
from pathlib import Path
from datetime import datetime, timezone
import argparse
import collections
import copy
import hashlib
import json
import math

MARKS = ('call_start_s', 'call_end_s', 'response_start_s', 'response_end_s')

def sha(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as f:
        for b in iter(lambda: f.read(1024*1024), b''):
            h.update(b)
    return h.hexdigest()

def optional_time(value, name):
    if value is None:
        return None
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or value < 0:
        raise ValueError(f'Invalid recorded time: {name}')
    return value

def difference(a, b):
    return None if a is None or b is None else a-b

def manual_mark(annotation, name):
    mark = annotation.get('marks', {}).get(name)
    if mark is None:
        return dict(time_s=None, time_source=None, record_status='missing', original_record=None)
    if not isinstance(mark, dict):
        raise ValueError('Invalid manual mark record')
    ms = optional_time(mark.get('media_time_ms'), name)
    return dict(time_s=None if ms is None else ms/1000, time_source=mark.get('time_source'),
        record_status='missing_time' if ms is None else 'recorded_manual_candidate', original_record=copy.deepcopy(mark))

def build_report(video_id, video_sha256, annotation, detection, settling, user_reviews=()):
    manual = {name: manual_mark(annotation, name) for name in MARKS}
    for start, end in (('call_start_s', 'call_end_s'), ('response_start_s', 'response_end_s')):
        a, b = manual[start]['time_s'], manual[end]['time_s']
        if a is not None and b is not None and b < a:
            raise ValueError('Invalid manual time order')
    limitations = [
        'Call times are MANUAL inputs, not automatic audio detection.',
        'Manual annotations are candidates; no ground-truth approval is granted by this report.',
        'Manual movement end is approximate; no exact physical endpoint is asserted.',
        'LibVLC-to-decoder and independent audio/video alignment are not verified.',
        'Frame/FPS nominal times, decoder times and LibVLC marks are not interchangeable precise timestamps.',
        'Differences are arithmetic only; no causal link or response class is assigned.',
        'Every subsequent movement is retained; sharing a call reference does not make it a response to that call.',
        'Settling intervals, their later confirmation, and later region exits are not movement endpoints.',
        'No closest/best candidate selection; missing times remain null, never zero-filled.',
    ]
    missing = [name for name, mark in manual.items() if mark['time_s'] is None]
    if missing:
        limitations.append('Missing manual times: '+', '.join(missing)+'; affected differences are null.')
    movement = {}
    for method in ('raw', 'ema_050'):
        saved_settings = detection.get('results', {}).get(method)
        if saved_settings is None:
            movement[method] = dict(status='not_recorded', settings={})
            continue
        settings = {}
        for setting, saved in saved_settings.items():
            candidates = []
            for original in saved.get('candidates', []):
                times = {k: optional_time(original.get(k), k) for k in ('start_s', 'end_s', 'start_confirmed_s', 'end_confirmed_s')}
                if times['start_s'] is not None and times['end_s'] is not None and times['end_s'] < times['start_s']:
                    raise ValueError('Invalid recorded algorithmic time order')
                for boundary, confirmation in (('start_s', 'start_confirmed_s'), ('end_s', 'end_confirmed_s')):
                    if times[boundary] is not None and times[confirmation] is not None and times[confirmation] < times[boundary]:
                        raise ValueError('Algorithmic confirmation precedes boundary')
                candidates.append(dict(candidate_id=original.get('candidate_id'),
                    time_source='saved_detector_decoder_time_s', clock_alignment_verified=False,
                    movement_start_s=times['start_s'], movement_end_s=times['end_s'],
                    start_status=original.get('start_status', 'not_recorded'), end_status=original.get('end_status', 'not_recorded'),
                    start_confirmation_time_s=times['start_confirmed_s'], end_confirmation_time_s=times['end_confirmed_s'],
                    start_confirmation_delay_s=difference(times['start_confirmed_s'], times['start_s']),
                    end_confirmation_delay_s=difference(times['end_confirmed_s'], times['end_s']),
                    boundary_span_s=difference(times['end_s'], times['start_s']),
                    start_minus_manual_call_start_s=difference(times['start_s'], manual['call_start_s']['time_s']),
                    start_minus_manual_call_end_s=difference(times['start_s'], manual['call_end_s']['time_s']),
                    start_minus_manual_movement_start_s=difference(times['start_s'], manual['response_start_s']['time_s']),
                    end_minus_approx_manual_movement_end_s=difference(times['end_s'], manual['response_end_s']['time_s']),
                    end_is_confirmed_physical_endpoint=False,
                    reference_call_association='arithmetic_reference_only_not_a_response_assignment',
                    algorithmic_target=dict(status='not_determined', label='belirlenmedi'),
                    original_algorithm_record=copy.deepcopy(original)))
            settings[setting] = dict(role='primary_fixed_protocol' if setting == 'base' else 'previously_recorded_sensitivity_only',
                setting_parameters=copy.deepcopy(saved.get('setting')), candidates=candidates,
                no_candidates_means_no_response=False,
                uncertain_intervals=copy.deepcopy(saved.get('uncertain_intervals', [])))
        movement[method] = dict(status='recorded', settings=settings)
    regions = []
    for method, conditions in settling.get('results', {}).items():
        for radius, condition in conditions.items():
            # Accept the two existing archive layouts without changing either.
            scans = condition.get('scans') if 'scans' in condition else [condition]
            for scan in scans:
                regions.append(dict(method=method, radius_deg=scan.get('radius_deg', int(radius)),
                    source_candidate_id=scan.get('source_candidate_id'), fixed_v1_start_frame=scan.get('fixed_v1_start_frame'),
                    interpretation='predicted_orientation_region_only_not_movement_end',
                    initial_reference=copy.deepcopy(scan.get('initial_reference')),
                    initial_reference_error=scan.get('initial_reference_error'),
                    window_status_counts=dict(collections.Counter(w['status'] for w in scan.get('windows', []))),
                    windows=copy.deepcopy(scan.get('windows', [])),
                    overlapping_groups=copy.deepcopy(scan.get('overlapping_groups', []))))
    return dict(report_version='d01-pilot-time-relations-1.0',video_id=video_id,
        video=dict(path=annotation.get('video_path'),sha256=video_sha256),
        scope='saved_results_only_no_inference_no_parameter_changes',
        manual=dict(input_kind='human_marked_call_and_movement_candidates',marks=manual,
            annotation_status=annotation.get('annotation_status', annotation.get('candidate_status', 'not_recorded')),
            original_candidate_status=annotation.get('candidate_status'),
            approval_field_in_source=annotation.get('ground_truth_approved'),
            report_grants_approval=False, movement_end_is_approximate=True,
            observation_window_start_s=annotation.get('observation_start_s'),
            observation_window_end_s=annotation.get('observation_end_s'),
            window_complete=annotation.get('window_complete'),
            target_and_direction=dict(source='user_observation_only',details=copy.deepcopy(annotation.get('manual_details', {}))),
            nominal_candidate_metadata={k:annotation.get(k) for k in ('response_start_frame','response_start_nominal_s','nominal_time_source')}),
        algorithmic_target=dict(status='not_determined',label='belirlenmedi'),
        movement_results=movement,settling=dict(is_movement_end=False,regions=regions,
            protocol=settling.get('protocol'),parameters=copy.deepcopy(settling.get('parameters')),
            condition_status_records=[dict(method=m,radius=r,unassessable_starts=copy.deepcopy(c.get('unassessable_starts',[])),
                no_v1_candidates=c.get('no_v1_candidates')) for m,cs in settling.get('results',{}).items() for r,c in cs.items()]),
        separate_user_reviews=copy.deepcopy(list(user_reviews)),
        time_relationship_does_not_establish_causality=True,limitations=limitations)

def readable(report):
    def fmt(v): return 'bilinmiyor' if v is None else f'{v:.6f}'
    marks = report['manual']['marks']
    lines = [f"# {report['video_id']} — pilot zaman ilişkisi", '',
        f"Video: `{report['video']['path']}`", f"SHA256: `{report['video']['sha256']}`", '',
        f"Manuel çağrı: {fmt(marks['call_start_s']['time_s'])}–{fmt(marks['call_end_s']['time_s'])} sn; otomatik ses tespiti yapılmadı.",
        f"Manuel hareket adayı: {fmt(marks['response_start_s']['time_s'])}–yaklaşık {fmt(marks['response_end_s']['time_s'])} sn.",
        f"Kaynak aday durumu: {report['manual']['annotation_status']}; onay verilmedi.",
        'Algoritmik hedef: **belirlenmedi**. Hedef/yön bilgisi yalnız kullanıcı gözlemidir.', '',
        '| Seri / ayar / aday | Başlangıç–bitiş sn | Başlangıç / bitiş doğrulama sn | Başlangıç−çağrı başlangıcı sn | Başlangıç−çağrı bitişi sn |',
        '|---|---|---|---:|---:|']
    for method, saved in report['movement_results'].items():
        if saved['status'] == 'not_recorded': lines.append(f'| {method} | Kayıt bulunamadı | bilinmiyor | bilinmiyor | bilinmiyor |')
        for setting, result in saved['settings'].items():
            for c in result['candidates']:
                lines.append(f"| {method} / {setting} / {c['candidate_id']} | {fmt(c['movement_start_s'])}–{fmt(c['movement_end_s'])} | {fmt(c['start_confirmation_time_s'])} / {fmt(c['end_confirmation_time_s'])} | {fmt(c['start_minus_manual_call_start_s'])} | {fmt(c['start_minus_manual_call_end_s'])} |")
            if not result['candidates']: lines.append(f'| {method} / {setting} | Aday bulunmadı; tepki sınıfı değildir | — | — | — |')
    lines += ['', 'base sabit ana ayardır. Diğer ayarlar yalnız geçmişte kayıtlı duyarlılık sonuçlarıdır; yeniden çalıştırılmadı. Bitiş ve doğrulama ayrı sınırlardır; uzun aralıklar kırpılmadı.', '',
        '## Ayrı yerleşme kayıtları', '', '| Seri / yarıçap / V1 başlangıç karesi | Kabul / ret / doğrulanamadı |', '|---|---|']
    for r in report['settling']['regions']:
        c = r['window_status_counts']
        lines.append(f"| {r['method']} / {r['radius_deg']}° / {r['fixed_v1_start_frame']} | {c.get('accepted_settling_window',0)} / {c.get('rejected_conditions',0)} / {c.get('unconfirmed_incomplete_data',0)} |")
    details = report['manual']['target_and_direction']['details']
    lines += ['', 'Bütün yerleşme aralıkları, daha geç doğrulamalar, sonraki çıkışlar ve ret nedenleri JSON içinde ayrı korunur; hareket bitişi sayılmaz.', '',
        'Kullanıcı hedef gözlemi: '+details.get('observed_target','Kaydedilmedi.'),
        'Kullanıcı belirsizlik notu: '+details.get('uncertainty','Kaydedilmedi.'),
        'Ayrı son-bölüm kullanıcı incelemesi sayısı: '+str(len(report['separate_user_reviews'])), '',
        '**Sınırlar:** etiketler aday; bitiş yaklaşık; LibVLC–decoder/ses–görüntü eşlemesi bağımsız doğrulanmadı. Sonraki bütün hareketlerin aynı çağrıya tepki olduğu varsayılmaz. Rapor yalnız aritmetik ilişkidir; sınıflandırma, güven yüzdesi, renk veya yöntem seçimi içermez.']
    return '\n'.join(lines)+'\n'

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest',type=Path,required=True)
    parser.add_argument('--output-dir',type=Path,required=True)
    args=parser.parse_args();out=args.output_dir.resolve();repo=Path(__file__).resolve().parents[2]
    if out==repo or repo in out.parents: raise ValueError('Reports must be outside checkout')
    if out.exists(): raise ValueError('No report overwrite')
    entries=json.loads(args.manifest.read_text(encoding='utf-8'))['videos']
    ids=[e['video_id'] for e in entries]
    if len(set(ids))!=len(ids) or any(not i or any(c not in 'abcdefghijklmnopqrstuvwxyz0123456789_-' for c in i) for i in ids):
        raise ValueError('Unique safe video identifiers required')
    protected={str(args.manifest.resolve()):sha(args.manifest)};reports=[]
    for e in entries:
        paths={k:Path(e[k]).resolve() for k in ('manual_json','detection_json','settling_json','inference_report_json')}
        reviews=[Path(p).resolve() for p in e.get('user_review_jsons',[])]
        for p in [*paths.values(),*reviews]: protected[str(p)]=sha(p)
        data={k:json.loads(p.read_text(encoding='utf-8-sig')) for k,p in paths.items()}
        annotation=data['manual_json'];video=Path(annotation['video_path']).resolve()
        protected[str(video)]=sha(video);inference=data['inference_report_json']
        if protected[str(video)]!=inference['video_sha256'] or (annotation.get('video_sha256') is not None and annotation['video_sha256']!=protected[str(video)]):
            raise ValueError('Source video/annotation/inference hash mismatch')
        report=build_report(e['video_id'],protected[str(video)],annotation,data['detection_json'],data['settling_json'],
            [json.loads(p.read_text(encoding='utf-8')) for p in reviews])
        report['created_utc']=datetime.now(timezone.utc).isoformat()
        report['provenance']={k:dict(path=str(p),sha256=protected[str(p)]) for k,p in paths.items()}
        report['provenance']['user_reviews']=[dict(path=str(p),sha256=protected[str(p)]) for p in reviews]
        report['recorded_video_condition']={k:inference.get(k) for k in ('roi','padding_ltrb','padding_effect_validated','time_limits','convention')}
        reports.append(report)
    assert all(sha(p)==h for p,h in protected.items())
    out.mkdir(parents=True,exist_ok=False)
    for report in reports:
        with (out/(report['video_id']+'.json')).open('x',encoding='utf-8') as f:
            json.dump(report,f,ensure_ascii=False,indent=2,allow_nan=False);f.write('\n')
        (out/(report['video_id']+'.md')).write_text(readable(report),encoding='utf-8')
    assert all(sha(p)==h for p,h in protected.items())
    (out/'source_preservation.json').write_text(json.dumps(dict(source_files_sha256=protected,all_unchanged=True,
        model_inference_performed=False,detection_recomputed=False,parameters_changed=False),indent=2)+'\n',encoding='utf-8')
    print(f'Created {len(reports)} separate JSON reports and readable summaries; all inputs unchanged.')

if __name__=='__main__':main()
