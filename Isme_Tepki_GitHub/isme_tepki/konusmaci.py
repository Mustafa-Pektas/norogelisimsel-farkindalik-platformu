"""Bilinen çağrı aralığındaki sesi sahnedeki yüzlerle karşılaştırır."""
from contextlib import ExitStack
import os
import re
import subprocess

import numpy as np


AUDIO_RATE = 16000
SOURCE = 'audio_visual_candidate'
STATUS_LABELS = {
    'matched': 'Ses ve ağız hareketi eşleşmesi · otomatik aday',
    'missing_face_regions': 'Eşleştirme için sahnede kayıtlı yüz bölgesi gerekli',
    'audio_unavailable': 'Ses akışı veya görüntü zaman damgası okunamadı',
    'video_unavailable': 'Yüz hareketini ölçmek için görüntü okunamadı',
    'insufficient_audio': 'Çağrı aralığında yeterli ses farkı ölçülemedi',
    'insufficient_face_data': 'Çağrı aralığında yeterli yüz ölçümü yok',
    'uncertain': 'Ses ve ağız hareketi arasında yeterli eşleşme bulunamadı',
    'ambiguous': 'Sesle uyumlu birden fazla yüz izi bulundu',
    'untargeted_face': 'En güçlü eşleşen yüzün sahnede bir hedef kimliği yok',
}


def read_audio(video):
    from sesyon.pipeline import ffmpeg_executable

    # PCM ve ilk video karesi aynı FFmpeg zaman tabanından gelir.
    command = [ffmpeg_executable(), '-hide_banner', '-nostdin', '-nostats',
               '-copyts', '-start_at_zero', '-i', str(video),
               '-map', '0:v:0', '-an', '-vf', 'showinfo', '-frames:v', '1', '-f', 'null', os.devnull,
               '-map', '0:a:0', '-vn', '-af', f'aresample={AUDIO_RATE}:async=1:first_pts=0',
               '-ac', '1', '-c:a', 'pcm_f32le', '-f', 'f32le', 'pipe:1']
    result = subprocess.run(command, capture_output=True, check=True)
    first = re.search(rb'\bn:\s*0\s+pts:\s*-?\d+\s+pts_time:\s*([-+\d.eE]+)', result.stderr)
    if not result.stdout or first is None:
        raise ValueError('Audio or first video timestamp unavailable')
    return np.frombuffer(result.stdout, dtype='<f4'), float(first[1])


def face_regions(scene):
    faces = [target for target in scene.get('targets', []) if target.get('type') == 'person_face']
    regions = []
    for role in ('adult', 'child'):
        box, region = scene.get(role + '_head'), scene.get(role + '_search_region')
        if box and region:
            ids = [target['id'] for target in faces if target.get('track') == role]
            regions.append((role, ids[0] if len(ids) == 1 else None, box, region))
    for face in faces:
        if face.get('track') or not face.get('bbox'):
            continue
        x1, y1, x2, y2 = face['bbox']
        dx, dy = .2 * (x2 - x1), .2 * (y2 - y1)
        region = [max(0, x1 - dx), max(0, y1 - dy), min(1, x2 + dx), min(1, y2 + dy)]
        regions.append((face['id'], face['id'], face['bbox'], region))
    return regions


def mouth_opening(points):
    if points is None:
        return np.nan
    scale = np.linalg.norm(points[33] - points[263])
    if not np.isfinite(scale) or scale < 12:
        return np.nan
    # İç dudak açıklığı, dış göz köşeleri arası mesafe ile ölçeklenir.
    gaps = np.linalg.norm(points[[13, 82, 312]] - points[[14, 87, 317]], axis=1)
    return np.median(gaps) / scale


def measure_faces(video, rows, regions):
    import cv2
    from sesyon.vision import FaceTrack

    openings = np.full((len(rows), len(regions)), np.nan)
    with ExitStack() as stack:
        capture = cv2.VideoCapture(str(video))
        stack.callback(capture.release)
        if not capture.isOpened():
            raise OSError('Video could not be opened')
        tracks = []
        for _, _, box, region in regions:
            track = FaceTrack(box, region, max_gap_s=0)
            stack.callback(track.close)
            tracks.append(track)
        previous = -1
        for index, row in enumerate(rows):
            frame_index = row['frame_index']
            for _ in range(frame_index - previous):
                if not capture.grab():
                    return openings
            previous = frame_index
            ok, frame = capture.retrieve()
            if ok:
                for column, track in enumerate(tracks):
                    points = track.update(frame, row['time_s'])['landmarks']
                    openings[index, column] = mouth_opening(points)
    return openings


def audio_levels(audio, timestamps):
    levels = np.full(len(timestamps), np.nan)
    radius = round(.03 * AUDIO_RATE)
    for i, timestamp in enumerate(timestamps):
        center = round(timestamp * AUDIO_RATE)
        left, right = max(0, center - radius), min(len(audio), center + radius)
        if right - left >= radius:
            rms = np.sqrt(np.mean(audio[left:right] ** 2))
            levels[i] = 20 * np.log10(max(rms, 1e-6))
    return levels


def match_faces(levels, openings, regions, expected_samples):
    usable_audio = np.isfinite(levels)
    minimum_samples = max(8, .7 * expected_samples)
    if usable_audio.sum() < minimum_samples:
        return dict(status='insufficient_audio')
    low, high = np.percentile(levels[usable_audio], [20, 80])
    if high < -45 or high - low < 12:
        return dict(status='insufficient_audio')
    quiet = levels <= low + 3
    loud = levels >= high - 3
    faces = []
    for column, (track, target, _, _) in enumerate(regions):
        aperture = openings[:, column]
        valid = usable_audio & np.isfinite(aperture)
        if valid.sum() < minimum_samples or (valid & quiet).sum() < 3 or (valid & loud).sum() < 3:
            continue
        delta = float(np.median(aperture[valid & loud]) - np.median(aperture[valid & quiet]))
        corr = float(np.corrcoef(levels[valid], aperture[valid])[0, 1]) if np.ptp(aperture[valid]) > 1e-6 else 0.0
        faces.append(dict(track=track, target_id=target, sample_count=int(valid.sum()),
                          correlation=round(corr, 4), mouth_opening_delta=round(delta, 4)))
    result = dict(status='insufficient_face_data', faces=faces)
    if not faces:
        return result
    moving = sorted((f for f in faces if f['mouth_opening_delta'] >= .025),
                    key=lambda f: f['correlation'], reverse=True)
    if not moving or moving[0]['correlation'] < .55:
        return dict(result, status='uncertain')
    best = moving[0]
    if len(moving) > 1 and best['correlation'] - moving[1]['correlation'] < .18:
        return dict(result, status='ambiguous')
    if best['target_id'] is None:
        return dict(result, status='untargeted_face')
    return dict(result, status='matched', target_id=best['target_id'])


def align_calls(video, calls, rows, scene, fps):
    pending = [call for call in calls if not (call.get('speaker_target_id') and
                                             call.get('speaker_source') == 'manual_user_verified')]
    if not pending:
        return
    regions = face_regions(scene)
    status = None
    if not any(target for _, target, _, _ in regions):
        status = 'missing_face_regions'
    else:
        try:
            audio, first_video_pts = read_audio(video)
        except (OSError, RuntimeError, ImportError, ValueError, subprocess.CalledProcessError):
            status = 'audio_unavailable'
    if status is None:
        timed = [r for r in rows if r['time_s'] is not None]
        selected = [r for r in timed if any(c['start_s'] <= r['time_s'] <= c['end_s'] for c in pending)]
        origin = timed[0]['time_s'] - timed[0]['frame_index'] / fps
        timestamps = np.array([r['time_s'] for r in selected])
        levels = audio_levels(audio, timestamps + first_video_pts - origin)
        try:
            openings = measure_faces(video, selected, regions)
        except (OSError, ImportError):
            status = 'video_unavailable'
    for call in pending:
        call.update(speaker_target_id=None, speaker_source='unresolved')
        if status is None:
            keep = (call['start_s'] <= timestamps) & (timestamps <= call['end_s'])
            expected = (call['end_s'] - call['start_s']) * fps
            evidence = match_faces(levels[keep], openings[keep], regions, expected)
        else:
            evidence = dict(status=status)
        call['speaker_alignment'] = dict(evidence, label=STATUS_LABELS[evidence['status']])
        if evidence['status'] == 'matched':
            call.update(speaker_target_id=evidence['target_id'], speaker_source=SOURCE)
