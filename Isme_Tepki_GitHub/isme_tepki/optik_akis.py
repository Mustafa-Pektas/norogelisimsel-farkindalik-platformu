"""Kamera hareketi düzeltilmiş baş akışı ve olay durumları."""
import csv
import math

import numpy as np
from scipy.spatial.transform import Rotation


DEFAULTS = dict(start_speed=0.30, stop_speed=0.12, motion_hold_s=0.08, stop_hold_s=0.16,
                baseline_s=0.25, departure_deg=15.0, return_deg=8.0, pose_hold_s=0.16)
EPS = 1e-6


def parameters(overrides):
    if not isinstance(overrides, dict) or overrides.keys() - DEFAULTS.keys():
        raise ValueError('optical_flow bir nesne olmali ve yalniz belgelenen ayarlari icermeli.')
    options = dict(DEFAULTS, **overrides)
    if any(type(v) not in (int, float) or not math.isfinite(v) or v <= 0 for v in options.values()):
        raise ValueError('Optik akis ayarlari pozitif ve sonlu olmali.')
    if options['stop_speed'] >= options['start_speed'] or options['return_deg'] >= options['departure_deg']:
        raise ValueError('Durma/baslama ve donus/ayrilma esikleri artan sirada olmali.')
    return options


def pixel_box(box, width, height, inset=0):
    if not isinstance(box, (list, tuple)) or len(box) != 4:
        return None
    if not all(type(v) in (int, float) and math.isfinite(v) for v in box):
        return None
    x1, y1, x2, y2 = np.clip(box, 0, 1) * [width, height, width, height]
    dx, dy = (x2 - x1) * inset, (y2 - y1) * inset
    x1, y1, x2, y2 = (round(v) for v in (x1 + dx, y1 + dy, x2 - dx, y2 - dy))
    return (x1, y1, x2, y2) if x2 - x1 >= 16 and y2 - y1 >= 16 else None


def point_pairs(cv, before, after, mask, count, spacing):
    points = cv.goodFeaturesToTrack(before, maxCorners=count, qualityLevel=.01,
                                    minDistance=spacing, mask=mask)
    empty = np.empty((0, 2), dtype=np.float32)
    if points is None:
        return empty, empty
    moved, ok, error = cv.calcOpticalFlowPyrLK(before, after, points, None)
    if moved is None:
        return empty, empty
    back, valid, _ = cv.calcOpticalFlowPyrLK(after, before, moved, None)
    if back is None:
        return empty, empty
    good = (ok.ravel() == 1) & (valid.ravel() == 1) & (error.ravel() < 25)
    good &= np.linalg.norm(back - points, axis=2).ravel() < 1.5
    return points[good, 0], moved[good, 0]


def measure_pair(cv, before, after, box, next_box, foreground, dt):
    height, width = before.shape
    head = np.zeros_like(before)
    x1, y1, x2, y2 = box
    head[y1:y2, x1:x2] = 255
    p0, p1 = point_pairs(cv, before, after, head, 80, 4)
    a, b, c, d = next_box
    inside = (a <= p1[:, 0]) & (p1[:, 0] < c) & (b <= p1[:, 1]) & (p1[:, 1] < d)
    p0, p1 = p0[inside], p1[inside]
    if len(p0) < 10:
        return None, len(p0), 0, 'insufficient_head_tracks'

    background = np.full_like(before, 255)
    for rect in foreground:
        region = pixel_box(rect, width, height, inset=-.10)
        if region:
            left, top, right, bottom = region
            background[max(0, top):bottom, max(0, left):right] = 0
    q0, q1 = point_pairs(cv, before, after, background, 120, 12)
    # Hedef bölgelerine doğru kayan arka plan noktalarını da çıkar.
    x, y = np.rint(q1).astype(int).T
    visible = (0 <= x) & (x < width) & (0 <= y) & (y < height)
    q0, q1 = q0[visible], q1[visible]
    clear = background[y[visible], x[visible]] > 0
    q0, q1 = q0[clear], q1[clear]
    if len(q0) < 20:
        return None, len(p0), 0, 'insufficient_background_tracks'
    transform, inliers = cv.estimateAffinePartial2D(q0, q1, ransacReprojThreshold=1.5)
    if transform is None:
        return None, len(p0), 0, 'unstable_background'
    supports = q0[inliers.ravel().astype(bool)]
    if (len(supports) < max(20, .65 * len(q0)) or
            np.any(np.ptp(supports, axis=0) < np.array([width, height]) * .15)):
        return None, len(p0), len(supports), 'unstable_background'

    predicted = p0 @ transform[:, :2].T + transform[:, 2]
    movement = np.median(np.linalg.norm(p1 - predicted, axis=1))
    # box kenarları takip noktalarının maskesi için %12 içe alınmıştır.
    head_diagonal = math.hypot(x2 - x1, y2 - y1) / .76
    return float(movement / head_diagonal / dt), len(p0), len(supports), 'measured'


def measure(video, original, rows, scene, fps):
    import cv2 as cv

    fixed_foreground = [scene.get('child_search_region'), scene.get('adult_search_region')]
    fixed_foreground += [target.get('bbox') for target in scene.get('targets', [])]
    features = []
    capture = cv.VideoCapture(str(video))
    previous = previous_box = previous_raw = None
    try:
        if not capture.isOpened():
            raise ValueError('Optik akis icin video acilamadi.')
        for index, (raw, row) in enumerate(zip(original, rows)):
            frame = row['frame_index']
            before_index = rows[index - 1]['frame_index'] if index else -1
            for _ in range(frame - before_index - 1):
                if not capture.grab():
                    break
            ok, image = capture.read()
            t = row['time_s']
            sample = dict(frame_index=frame, time_s=t, speed=None, head_tracks=0,
                          background_inliers=0, quality='missing_video_frame')
            features.append(sample)
            box = gray = None
            if ok:
                height, width = image.shape[:2]
                if raw.get('child_track') != 'lost':
                    box = pixel_box(raw.get('child_bbox'), width, height, inset=.12)
                sample['quality'] = 'missing_head_region'
                if box:
                    gray = cv.cvtColor(image, cv.COLOR_BGR2GRAY)
                    sample['quality'] = 'no_adjacent_head_frame'
                    before_t = rows[index - 1]['time_s'] if index else None
                    if (previous_box and frame == before_index + 1 and t is not None and
                            before_t is not None and 0 < t - before_t <= 1.5 / fps):
                        foreground = fixed_foreground + [r.get(key) for r in (previous_raw, raw)
                                                         for key in ('child_bbox', 'adult_bbox')]
                        speed, head_count, bg_count, quality = measure_pair(
                            cv, previous, gray, previous_box, box, foreground, t - before_t)
                        sample.update(speed=speed, head_tracks=head_count,
                                      background_inliers=bg_count, quality=quality)
            previous, previous_box, previous_raw = gray, box, raw
    finally:
        capture.release()
    return features


def motion_stops(samples, options):
    """Bilinmiyor → sabit → hareketli → sabit. İlk düşük örnek olay zamanıdır."""
    state = 'unknown'
    high = low = first_high = onset = None
    stops = []
    for sample in samples:
        t, speed = sample['time_s'], sample['speed']
        if speed is None:
            state = 'unknown'
            high = low = first_high = onset = None
        else:
            high = (t if high is None else high) if speed >= options['start_speed'] else None
            low = (t if low is None else low) if speed <= options['stop_speed'] else None
            if state != 'moving' and high is not None and t - high + EPS >= options['motion_hold_s']:
                first_high = high
                onset = high if state == 'still' else None
                state = 'moving'
            if low is not None and t - low + EPS >= options['stop_hold_s']:
                if state == 'moving':
                    stops.append(dict(event='durdu', time_s=low, confirmed_s=t,
                                      movement_start_s=onset, first_motion_evidence_s=first_high))
                state = 'still'
        sample['state'] = state
    return stops


def pose_events(rows, start, finish, fps, options):
    """Sabit çağrı öncesi poz → pozdan ayrıldı → başlangıç pozuna döndü."""
    max_gap = 1.5 / fps
    before = [r for r in rows if r['time_s'] is not None and
              start - options['baseline_s'] - max_gap <= r['time_s'] < start]
    if not before or start - before[-1]['time_s'] > max_gap or not before[-1]['valid']:
        return dict(status='unknown_baseline', events=[])
    baseline = [before[-1]]
    for r in reversed(before[:-1]):
        latest = baseline[-1]
        if (not r['valid'] or latest['frame_index'] != r['frame_index'] + 1 or
                latest['time_s'] - r['time_s'] > max_gap):
            break
        baseline.append(r)
        if baseline[0]['time_s'] - r['time_s'] + EPS >= options['baseline_s']:
            break
    if baseline[0]['time_s'] - baseline[-1]['time_s'] + EPS < options['baseline_s']:
        return dict(status='unknown_baseline', events=[])
    rotations = Rotation.from_matrix([r['rotation_matrix'] for r in baseline])
    anchor = rotations.mean()
    if np.max(np.degrees((anchor.inv() * rotations).magnitude())) > options['return_deg']:
        return dict(status='unstable_baseline', events=[])

    state = 'near_baseline'
    previous = before[-1]
    run = departure = None
    events = []
    for row in rows:
        t = row['time_s']
        if t is None or not start <= t <= finish:
            continue
        if not row['valid'] or row['frame_index'] != previous['frame_index'] + 1 or t - previous['time_s'] > max_gap:
            state, run, departure = 'near_baseline', None, None
        previous = row
        if not row['valid']:
            continue
        pose = Rotation.from_matrix(row['rotation_matrix'])
        distance = np.degrees((anchor.inv() * pose).magnitude())
        matches = distance >= options['departure_deg'] if state == 'near_baseline' else distance <= options['return_deg']
        run = (t if run is None else run) if matches else None
        if run is None or t - run + EPS < options['pose_hold_s']:
            continue
        if state == 'near_baseline':
            departure = run
            state = 'away'
        else:
            events.append(dict(event='geri_dondu', time_s=run, confirmed_s=t, departure_s=departure))
            state = 'near_baseline'
        run = None
    return dict(status='observed' if events else 'unconfirmed', events=events)


def export_samples(path, samples):
    with path.open('w', encoding='utf-8-sig', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=['frame_index', 'time_s', 'speed', 'head_tracks',
                                                    'background_inliers', 'quality', 'state'])
        writer.writeheader()
        writer.writerows(samples)
