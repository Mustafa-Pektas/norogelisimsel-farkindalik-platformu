"""Çocuğun tam açılı baş pozunu videodan ölçer ve kaynakları ayrı tutar."""
import csv
import importlib.util
import json
import math

import numpy as np
from scipy.spatial.transform import Rotation


LABELS = {'directmhp': 'DirectMHP-S CMU-HPE', 'repnet360': '6DRepNet360', 'recorded': 'Mevcut baş pozu'}
DETECTION_THRESHOLD = .30
MAX_TRACK_GAP_S = .35


def box_at(value):
    if not isinstance(value, (tuple, list)) or len(value) != 4:
        return None
    if not all(type(v) in (float, int) and math.isfinite(v) for v in value):
        return None
    left, top, right, bottom = np.clip(value, 0, 1).tolist()
    if left >= right or top >= bottom:
        return None
    return left, top, right, bottom


def tracked_box(row, person):
    if row.get(person + '_track') == 'lost':
        return None
    return box_at(row.get(person + '_bbox'))


def center(box):
    return (box[0] + box[2]) / 2, (box[1] + box[3]) / 2


def iou(box, other):
    if other is None:
        return 0.0
    x1, y1, x2, y2 = box
    a1, b1, a2, b2 = other
    intersection = max(0, min(x2, a2) - max(x1, a1)) * max(0, min(y2, b2) - max(y1, b1))
    union = (x2 - x1) * (y2 - y1) + (a2 - a1) * (b2 - b1) - intersection
    return intersection / union


def choose_child(detections, references, adult, search):
    """Çocuk ve yetişkin aynı karedeyken yalnız desteklenen başı seç."""
    ranked = []
    for detection in detections:
        box = detection['bbox']
        x, y = center(box)
        if search and not (search[0] <= x <= search[2] and search[1] <= y <= search[3]):
            continue
        overlap = max((iou(box, ref) for ref in references), default=0.0)
        adult_overlap = iou(box, adult)
        if adult_overlap >= .20 and adult_overlap > overlap + .05:
            continue
        if references and overlap < .10:
            continue
        ranked.append((overlap + .20 * detection['confidence'], detection))
    if not ranked or (not references and (search is None or len(ranked) != 1)):
        return None
    ranked.sort(key=lambda scored: scored[0], reverse=True)
    if len(ranked) > 1 and ranked[0][0] - ranked[1][0] < .12:
        return None
    return ranked[0][1]


def direct_rotation(normalized_angles):
    pitch, yaw, roll = (np.asarray(normalized_angles) - .5) * [180, 360, 180]
    # Resmî DirectMHP video_vis3d.py yerel dönüşü bu eksen düzeniyle oluşturur.
    return Rotation.from_euler('xyz', [pitch, -yaw, -roll], degrees=True).as_matrix().T


def resolve_device(torch, requested):
    if requested == 'cpu':
        return 'cpu'
    if torch.cuda.is_available():
        return 'cuda'
    if requested == 'cuda':
        raise ValueError('CUDA istenmiş ancak bu Python ortamında kullanılamıyor. '
                         'CUDA destekli PyTorch ile çalıştırın veya --head-pose-device cpu seçin.')
    return 'cpu'


class DirectMHP:
    def __init__(self, path, torch, device):
        extra_files = {'directmhp.json': ''}
        self.model = torch.jit.load(str(path), map_location=device, _extra_files=extra_files).eval()
        self.metadata = json.loads(extra_files['directmhp.json'])
        if self.metadata.get('model') != LABELS['directmhp'] or self.metadata.get('input_hw') != [768, 1280]:
            raise ValueError('DirectMHP-S CMU-HPE TorchScript modeli bekleniyor.')
        self.torch = torch
        self.device = device

    def detect(self, frame, cv2):
        height, width = frame.shape[:2]
        target_h, target_w = self.metadata['input_hw']
        factor = min(target_w / width, target_h / height)
        new_w, new_h = max(1, round(width * factor)), max(1, round(height * factor))
        left, top = (target_w - new_w) // 2, (target_h - new_h) // 2
        resized = cv2.resize(frame, (new_w, new_h), interpolation=cv2.INTER_LINEAR)
        padded = np.full((target_h, target_w, 3), 114, dtype=np.uint8)
        padded[top:top + new_h, left:left + new_w] = resized
        rgb = np.ascontiguousarray(padded[:, :, ::-1].transpose(2, 0, 1))
        inputs = self.torch.from_numpy(rgb)[None].to(device=self.device, dtype=self.torch.float32) / 255
        pred = self.model(inputs)[0].cpu().numpy()
        scores = pred[:, 4] * pred[:, 5]
        keep = np.isfinite(pred).all(axis=1) & (scores >= DETECTION_THRESHOLD) & (pred[:, 2:4] >= 2).all(axis=1)
        pred, scores = pred[keep], scores[keep]
        if not len(scores):
            return []
        corners = pred[:, :4].copy()
        corners[:, :2] -= corners[:, 2:4] / 2
        kept = cv2.dnn.NMSBoxes(corners.tolist(), scores.tolist(), DETECTION_THRESHOLD, .45)
        detections = []
        for index in np.asarray(kept).ravel():
            x, y, w, h = corners[index].tolist()
            box = box_at(((x - left) / new_w, (y - top) / new_h,
                          (x + w - left) / new_w, (y + h - top) / new_h))
            if box:
                detections.append(dict(bbox=box, confidence=float(scores[index]), angles=pred[index, 6:9]))
        return detections


def repnet_estimator(root, weights, torch, device):
    from torchvision import models, transforms

    spec = importlib.util.spec_from_file_location('repnet360_demo', root / '6drepnet360_denemesi/deneme.py')
    demo = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(demo)
    model = demo.load_model(weights, device, torch, models)
    preprocess = demo.pose_preprocess(transforms)
    return model, preprocess, demo.estimate


def pose_sample(row, status, box=None, confidence=None, rotation=None):
    return dict(frame_index=row['frame_index'], time_s=row['time_s'], valid=rotation is not None,
                rotation_matrix=None if rotation is None else rotation.tolist(), status=status,
                bbox=box, confidence=confidence)


def measure(video, rows, original, scene, root, paths, device='cpu'):
    import cv2
    import torch

    tracks = {name: [] for name in paths}
    threads = torch.get_num_threads()
    torch.set_num_threads(min(4, threads))
    try:
        direct = DirectMHP(paths['directmhp'], torch, device)
        repnet = repnet_estimator(root, paths['repnet360'], torch, device) if 'repnet360' in paths else None
        search = box_at(scene.get('child_search_region'))
        seed = box_at(scene.get('child_head'))
        previous_box = previous_time = None
        capture = cv2.VideoCapture(str(video))
        try:
            if not capture.isOpened():
                raise ValueError('Baş pozu deneyi için video açılamadı.')
            previous_index = -1
            with torch.inference_mode():
                for raw, row in zip(original, rows):
                    index, time_s = row['frame_index'], row['time_s']
                    for _ in range(index - previous_index - 1):
                        if not capture.grab():
                            break
                    ok, frame = capture.read()
                    previous_index = index
                    if not ok or time_s is None:
                        for samples in tracks.values():
                            samples.append(pose_sample(row, 'missing_frame_or_time'))
                        continue
                    child = tracked_box(raw, 'child')
                    recent = previous_box if previous_time is not None and time_s - previous_time <= MAX_TRACK_GAP_S else None
                    references = [box for box in (child, recent) if box is not None]
                    if not references and index == 0 and seed is not None:
                        references = [seed]
                    detected = direct.detect(frame, cv2)
                    match = choose_child(detected, references, tracked_box(raw, 'adult'), search)
                    if match:
                        previous_box, previous_time = match['bbox'], time_s
                        new_pose = pose_sample(row, 'measured', previous_box, match['confidence'],
                                               direct_rotation(match['angles']))
                    else:
                        new_pose = pose_sample(row, 'unmatched_child' if detected else 'no_head_detection')
                    tracks['directmhp'].append(new_pose)
                    if repnet:
                        tracks['repnet360'].append(measure_repnet(row, frame, child, repnet, cv2, torch, device))
        finally:
            capture.release()
        return tracks, direct.metadata
    finally:
        torch.set_num_threads(threads)


def measure_repnet(row, frame, box, repnet, cv2, torch, device):
    if box is None:
        return pose_sample(row, 'no_tracked_head')
    height, width = frame.shape[:2]
    x1, y1, x2, y2 = (round(value * size) for value, size in zip(box, (width, height, width, height)))
    if x2 - x1 < 16 or y2 - y1 < 16:
        return pose_sample(row, 'small_head_box', box)
    model, preprocess, estimate = repnet
    _, rotation = estimate(model, preprocess, frame[y1:y2, x1:x2], device, cv2, torch)
    if not np.isfinite(rotation).all() or abs(np.linalg.det(rotation) - 1) > .001:
        return pose_sample(row, 'invalid_rotation', box)
    return pose_sample(row, 'measured', box, rotation=rotation)


def export(path, tracks):
    with path.open('w', encoding='utf-8-sig', newline='') as stream:
        writer = csv.writer(stream)
        writer.writerow(['method', 'frame_index', 'time_s', 'valid', 'status', 'confidence',
                         'box_left', 'box_top', 'box_right', 'box_bottom'] +
                        [f'r{i}{j}' for i in range(3) for j in range(3)])
        for name, samples in tracks.items():
            for sample in samples:
                box = sample.get('bbox') or [None] * 4
                rotation = sample['rotation_matrix']
                matrix = [value for row in rotation for value in row] if rotation is not None else [None] * 9
                writer.writerow([name, sample['frame_index'], sample['time_s'], sample['valid'],
                                 sample.get('status'), sample.get('confidence'), *box, *matrix])
