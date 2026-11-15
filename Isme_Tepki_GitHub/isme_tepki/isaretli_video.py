"""Baş pozu, hedef tahmini ve olay zamanlarını sesli videoya işler."""
from bisect import bisect_right
from pathlib import Path
import subprocess
import tempfile

import numpy as np


FILENAME = 'isaretli_video.mp4'
HEAD = (98, 230, 168)
REFERENCE = (255, 199, 95)
TARGET = (216, 162, 255)
TEXT = (243, 248, 253)
MUTED = (163, 182, 200)
BACKGROUND = (15, 24, 36)
TARGET_LABELS = {'adult_face': 'Yetişkinin yüzü', 'adult_body': 'Yetişkinin gövdesi',
                 'toy': 'Oyuncak', 'ambiguous': 'Belirsiz', 'offscreen': 'Kadraj dışında',
                 'unavailable': 'Ölçüm yok'}


def seconds(time_s):
    return f'{time_s:.3f}'.replace('.', ',') + ' sn'


def event_label(samples, time_s, empty, late=False):
    started = [sample for sample in samples if sample['time_s'] <= time_s + 1e-6]
    if not started:
        return empty, '', MUTED
    item = max(started, key=lambda sample: sample['time_s'])
    prefix = 'Pencere dışı · ' if late else ''
    if item['confirmed_s'] > time_s + 1e-6:
        return prefix + seconds(item['time_s']), 'Aday · doğrulama bekleniyor', REFERENCE
    return prefix + seconds(item['time_s']), 'Doğrulama ' + seconds(item['confirmed_s']), HEAD


def event_panels(event, time_s):
    experiment = event.get('optical_flow') if event else None
    if not experiment:
        return []
    end = event['observation_end_s']
    pending = 'Bekleniyor' if time_s < end else 'Gözlemde doğrulanmadı'
    look = experiment['look']
    if look['status'] == 'unknown_caller':
        look_empty = 'Çağıran kişi belirsiz'
    elif look['status'] == 'already_oriented':
        look_empty = 'Çağrı öncesinde yönelmiş'
    else:
        look_empty = pending
    watched_return = experiment['return_to_baseline']['events']
    late = experiment.get('return_after_window', [])
    returned = event_label(watched_return, time_s, pending)
    if not watched_return and any(c['time_s'] <= time_s + 1e-6 for c in late):
        returned = event_label(late, time_s, pending, late=True)
    stop = experiment['stop']
    return [
        ('Baktı', event_label([look] if look['status'] == 'observed' else [], time_s, look_empty)),
        ('Durdu', event_label(stop['events'], time_s,
                              'Optik akış ölçümü yok' if stop['status'] == 'no_flow_data' else pending)),
        ('Geri döndü', returned),
    ]


def draw_marks(frame, cv2, raw, direct, repnet, gaze):
    height, width = frame.shape[:2]

    def pixels(box):
        return tuple(round(value * size) for value, size in zip(box, (width, height, width, height)))

    reference = repnet.get('bbox') if repnet and repnet['valid'] else None
    head = direct.get('bbox') if direct and direct['valid'] else None
    if head is None and direct is None and raw.get('child_track') != 'lost':
        head = raw.get('child_bbox')
    if reference:
        x1, y1, x2, y2 = pixels(reference)
        cv2.rectangle(frame, (x1, y1), (x2, y2), REFERENCE[::-1], 2, cv2.LINE_AA)
    origin = None
    if head:
        x1, y1, x2, y2 = pixels(head)
        origin = ((x1 + x2) // 2, (y1 + y2) // 2)
        cv2.rectangle(frame, (x1, y1), (x2, y2), HEAD[::-1], 3, cv2.LINE_AA)
        if direct is not None:
            # DirectMHP'nin resmî 2B çiziminde başın ileri ekseni bu işaretlerle yansıtılır.
            projected = -np.asarray(direct['rotation_matrix'])[:2, 2]
            scale = .42 * min(x2 - x1, y2 - y1)
            point = tuple(np.rint(np.asarray(origin) + scale * projected).astype(int))
            cv2.arrowedLine(frame, origin, point, HEAD[::-1], 3, cv2.LINE_AA, tipLength=.19)
        elif raw.get('head_axis_px'):
            start, end = [tuple(map(round, point)) for point in raw['head_axis_px']]
            cv2.arrowedLine(frame, start, end, HEAD[::-1], 3, cv2.LINE_AA, tipLength=.19)
    picked = gaze.get('target')
    point = gaze.get('gaze_point')
    if point and picked not in (None, 'ambiguous', 'offscreen', 'unavailable'):
        mark = (round(point[0] * width), round(point[1] * height))
        if origin:
            cv2.line(frame, origin, mark, TARGET[::-1], 2, cv2.LINE_AA)
        cv2.circle(frame, mark, 8, TARGET[::-1], 3, cv2.LINE_AA)
    return bool(head), bool(reference)


def make_frame(frame, cv2, fonts, width, time_s, event, raw, direct, repnet, gaze, flow):
    from PIL import Image, ImageDraw

    head, reference = draw_marks(frame, cv2, raw, direct, repnet, gaze)
    frame_height, frame_width = frame.shape[:2]
    # Göstergeler görüntünün dışında kalır, kişi ve hedefler örtülmez.
    top, bottom = 86, 100
    canvas = Image.new('RGB', (width, frame_height + top + bottom + frame_height % 2), BACKGROUND)
    canvas.paste(Image.fromarray(cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)), ((width - frame_width) // 2, top))
    draw = ImageDraw.Draw(canvas)
    bold, regular, small = fonts
    draw.text((18, 10), seconds(time_s), font=bold, fill=TEXT)
    if event:
        call = event['call']
        if time_s < call['start_s']:
            stage = 'Çağrı öncesi'
        elif time_s <= call['end_s']:
            stage = 'Seslenme · ' + (call.get('name') or 'İsim')
        elif time_s <= event['observation_end_s']:
            stage = 'Gözlem · son ' + seconds(event['observation_end_s'])
        else:
            stage = 'Gözlem kapandı · ' + seconds(event['observation_end_s'])
        draw.text((175, 12), stage, font=regular, fill=TEXT)
    if flow and flow['speed'] is not None:
        speed = f"{flow['speed']:.3f}".replace('.', ',')
        draw.text((width - 335, 13), f'Optik akış  {speed} baş köşegeni/sn', font=small, fill=TEXT)

    labels = [('DirectMHP-S baş yönü' if direct is not None else 'Baş takibi', HEAD if head else MUTED)]
    if not head:
        labels[0] = (labels[0][0] + ' · ölçüm yok', MUTED)
    if reference:
        labels.append(('6DRepNet360 kutusu', REFERENCE))
    target = gaze.get('target') or 'unavailable'
    labels.append(('Hedef tahmini · ' + TARGET_LABELS.get(target, target), TARGET))
    x = 18
    for label, color in labels:
        draw.text((x, 52), label, font=small, fill=color)
        x += round(draw.textlength(label, font=small)) + 26

    y = top + frame_height + 8
    panels = event_panels(event, time_s)
    for i, (label, (value, detail, color)) in enumerate(panels):
        x = i * width // 3
        if i:
            draw.line((x, y, x, y + 75), fill=(54, 74, 94), width=1)
        draw.text((x + 18, y), label, font=regular, fill=TEXT)
        draw.text((x + 18, y + 28), value, font=regular, fill=color)
        if detail:
            draw.text((x + 18, y + 57), detail, font=small, fill=MUTED)
    if not panels:
        draw.text((18, y + 14), 'Bu videoda işaretlenecek çağrı olayı yok', font=regular, fill=MUTED)
    return cv2.cvtColor(np.asarray(canvas), cv2.COLOR_RGB2BGR)


def write_video(out, result, original, gaze, gaze_fps, pose_tracks, flow_samples):
    import cv2
    import matplotlib
    from PIL import ImageFont
    from sesyon.pipeline import ffmpeg_executable

    source = result['video']['path']
    fps = result['video']['fps']
    font_dir = Path(matplotlib.get_data_path()) / 'fonts/ttf'
    fonts = (ImageFont.truetype(str(font_dir / 'DejaVuSans-Bold.ttf'), 27),
             ImageFont.truetype(str(font_dir / 'DejaVuSans.ttf'), 21),
             ImageFont.truetype(str(font_dir / 'DejaVuSans.ttf'), 17))
    original_by_frame = {row.get('frame_index', row.get('frame')): row for row in original}
    poses = {name: {row['frame_index']: row for row in rows} for name, rows in (pose_tracks or {}).items()}
    flow = {row['frame_index']: row for row in (flow_samples or [])}
    calls = sorted(result['calls'], key=lambda event: event['call']['start_s'])
    call_starts = [event['call']['start_s'] for event in calls]
    gaze_times = [row['time_s'] for row in gaze]

    with tempfile.TemporaryDirectory(prefix='isaretli-', dir=out) as work:
        silent = Path(work) / 'silent.mp4'
        preview = Path(work) / FILENAME
        capture = cv2.VideoCapture(source)
        writer = None
        count = 0
        try:
            if not capture.isOpened():
                raise ValueError('İşaretli video için kaynak açılamadı.')
            while True:
                ok, frame = capture.read()
                if not ok:
                    break
                width = max(960, frame.shape[1] + frame.shape[1] % 2)
                raw = original_by_frame.get(count, {})
                time_s = raw.get('decoder_time_s', raw.get('time_s'))
                time_s = count / fps if time_s is None else time_s
                event = calls[max(0, bisect_right(call_starts, time_s) - 1)] if calls else None
                gaze_index = bisect_right(gaze_times, time_s + 1e-6) - 1
                latest = gaze[gaze_index] if gaze_index >= 0 and time_s - gaze_times[gaze_index] < 1.5 / gaze_fps else {}
                direct = poses.get('directmhp', {}).get(count, {'valid': False}) if 'directmhp' in poses else None
                repnet = poses.get('repnet360', {}).get(count)
                painted = make_frame(frame, cv2, fonts, width, time_s, event, raw,
                                     direct, repnet, latest, flow.get(count))
                if writer is None:
                    height = painted.shape[0]
                    writer = cv2.VideoWriter(str(silent), cv2.VideoWriter_fourcc(*'mp4v'), fps, (width, height))
                    if not writer.isOpened():
                        raise OSError('İşaretli video yazıcısı açılamadı.')
                writer.write(painted)
                count += 1
        finally:
            capture.release()
            if writer is not None:
                writer.release()
        if not count:
            raise ValueError('İşaretli video için kare okunamadı.')
        subprocess.run([ffmpeg_executable(), '-v', 'error', '-nostdin', '-i', str(silent),
                        '-i', source, '-map', '0:v:0', '-map', '1:a:0?', '-t', str(count / fps),
                        '-c:v', 'libx264', '-preset', 'fast', '-crf', '19', '-pix_fmt', 'yuv420p',
                        '-c:a', 'aac', '-movflags', '+faststart', str(preview)], check=True)
        preview.replace(out / FILENAME)
    return dict(filename=FILENAME, frame_count=count, fps=fps, width=width, height=height)
