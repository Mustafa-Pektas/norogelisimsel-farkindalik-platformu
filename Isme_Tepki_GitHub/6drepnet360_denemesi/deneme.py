"""Deniz videosu için 6DRepNet360 baş pozu denemesi."""

import argparse
import csv
import hashlib
import json
import math
import sys
from contextlib import ExitStack
from pathlib import Path


WEIGHT_NAME = "6DRepNet360_Full-Rotation_300W_LP+Panoptic.pth"
WEIGHT_URL = "https://cloud.ovgu.de/s/TewGC9TDLGgKkmS/download/" + WEIGHT_NAME
DEMO_DIR = Path(__file__).resolve().parent
DEFAULT_WEIGHTS = DEMO_DIR / WEIGHT_NAME
SESSION_DIR = DEMO_DIR.parent / "ses_yonelme"
VIDEO_PATH = SESSION_DIR / "sample" / "source.mp4"
CONFIG_PATH = SESSION_DIR / "config" / "deniz.json"
WINDOW = "6DRepNet360 | Esc veya Q: cikis"


def arguments():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--weights", type=Path, default=DEFAULT_WEIGHTS, help="Yerel .pth ağırlığı")
    parser.add_argument("--device", choices=("auto", "cpu", "cuda"), default="auto")
    parser.add_argument("--roi", nargs=4, type=int, metavar=("X", "Y", "GENISLIK", "YUKSEKLIK"),
                        help="Başı kapsayan sabit piksel alanı")
    parser.add_argument("--csv", type=Path, help="Kare bazında CSV çıktısı")
    parser.add_argument("--no-preview", action="store_true", help="Videoyu pencere açmadan işle")
    parser.add_argument("--max-frames", type=int, help="İşlenecek en fazla kare sayısı")
    args = parser.parse_args()
    if args.roi and (min(args.roi[:2]) < 0 or min(args.roi[2:]) < 1):
        parser.error("ROI başlangıcı negatif olamaz ve genişlik/yükseklik pozitif olmalıdır.")
    if args.max_frames is not None and args.max_frames < 1:
        parser.error("--max-frames pozitif olmalıdır.")
    return args


def fixed_box(roi, width, height):
    x, y, w, h = roi
    if x + w > width or y + h > height:
        raise ValueError(f"ROI, {width}x{height} boyutundaki karenin dışına taşıyor.")
    return x, y, x + w, y + h


def load_model(path, device, torch, models):
    # The official inference script uses a ResNet-50 with a six-value linear_reg head.
    model = models.resnet50(weights=None)
    model.avgpool = torch.nn.AvgPool2d(7)
    model.fc = torch.nn.Linear(model.fc.in_features, 6)

    state = torch.load(path, map_location="cpu", weights_only=True)
    state = state.get("model_state_dict", state)
    state = {name.removeprefix("module.").replace("linear_reg.", "fc.", 1): value
             for name, value in state.items()}
    model.load_state_dict(state, strict=True)
    return model.to(device).eval()


def pose_preprocess(transforms):
    return transforms.Compose([
        transforms.ToPILImage(), transforms.Resize(256), transforms.CenterCrop(224),
        transforms.ToTensor(), transforms.Normalize((0.485, 0.456, 0.406), (0.229, 0.224, 0.225)),
    ])


def estimate(model, preprocess, crop, device, cv2, torch):
    rgb = cv2.cvtColor(crop, cv2.COLOR_BGR2RGB)
    with torch.inference_mode():
        pose = model(preprocess(rgb).unsqueeze(0).to(device))
        normalize = torch.nn.functional.normalize
        x = normalize(pose[:, :3], dim=1, eps=1e-8)
        z = normalize(torch.linalg.cross(x, pose[:, 3:], dim=1), dim=1, eps=1e-8)
        y = torch.linalg.cross(z, x, dim=1)
        rotation = torch.stack((x, y, z), dim=-1)[0].cpu().numpy()

    r = rotation
    horizontal = math.hypot(r[0, 0], r[1, 0])
    yaw = math.atan2(-r[2, 0], horizontal)
    if horizontal < 1e-6:
        pitch, roll = math.atan2(-r[1, 2], r[1, 1]), 0.0
    else:
        pitch = math.atan2(r[2, 1], r[2, 2])
        roll = math.atan2(r[1, 0], r[0, 0])
    return tuple(map(math.degrees, (pitch, yaw, roll))), rotation


def annotate(frame, box, angles, rotation, cv2):
    label = "Bas takibi kayip"
    if box is not None:
        left, top, right, bottom = box
        center = ((left + right) // 2, (top + bottom) // 2)
        size = max(12, min(right - left, bottom - top) // 3)
        cv2.rectangle(frame, (left, top), (right - 1, bottom - 1), (60, 210, 60), 2)
        # Project using the image-axis convention of the official visualization.
        for axis, color in enumerate(((0, 0, 255), (0, 255, 0), (255, 0, 0))):
            sign = -1 if axis == 1 else 1
            end = (round(center[0] + sign * size * float(rotation[axis, 0])),
                   round(center[1] - sign * size * float(rotation[axis, 1])))
            cv2.line(frame, center, end, color, 3, cv2.LINE_AA)
        pitch, yaw, roll = angles
        label = f"Pitch {pitch:+.1f} | Yaw {yaw:+.1f} | Roll {roll:+.1f}"

    for color, thickness in (((0, 0, 0), 4), ((255, 255, 255), 1)):
        cv2.putText(frame, label, (12, 28), cv2.FONT_HERSHEY_SIMPLEX, 0.6,
                    color, thickness, cv2.LINE_AA)


def run(args):
    config = json.loads(CONFIG_PATH.read_text(encoding="utf-8-sig"))
    checksum = hashlib.sha256(VIDEO_PATH.read_bytes()).hexdigest()
    if checksum != config["expected_sha256"]:
        raise ValueError(f"Video içeriği Deniz sahne ayarıyla eşleşmiyor: {VIDEO_PATH}")
    if not args.weights.is_file():
        raise FileNotFoundError(
            f"Ağırlık bulunamadı: {args.weights}\nResmi indirme adresi: {WEIGHT_URL}"
        )
    import cv2
    import torch
    from torchvision import models, transforms

    sys.path.insert(0, str(SESSION_DIR))
    from sesyon.vision import FaceTrack, pixels

    has_cuda = torch.cuda.is_available()
    if args.device == "cuda" and not has_cuda:
        raise RuntimeError("Bu PyTorch ortamında CUDA kullanılamıyor. --device cpu ile deneyin.")
    device = ("cuda" if has_cuda else "cpu") if args.device == "auto" else args.device
    if device == "cpu":
        torch.set_num_threads(min(torch.get_num_threads(), 4))
    model = load_model(args.weights, device, torch, models)
    preprocess = pose_preprocess(transforms)
    with ExitStack() as resources:
        capture = cv2.VideoCapture(str(VIDEO_PATH))
        resources.callback(capture.release)
        if not capture.isOpened():
            raise RuntimeError(f"Video açılamadı: {VIDEO_PATH}")
        fps = capture.get(cv2.CAP_PROP_FPS)
        if not math.isfinite(fps) or fps <= 0:
            raise RuntimeError("Videonun kare hızı okunamadı.")
        width, height = config["expected_size"]
        roi_box = fixed_box(args.roi, width, height) if args.roi else None
        tracker = None
        if roi_box is None:
            tracker = FaceTrack(config["child_head"], config["child_search_region"],
                                config["settings"]["max_flow_gap_s"])
            resources.callback(tracker.close)
        if not args.no_preview:
            cv2.namedWindow(WINDOW, cv2.WINDOW_NORMAL)
            resources.callback(cv2.destroyAllWindows)
        writer = None
        if args.csv:
            output = resources.enter_context(args.csv.open("x", encoding="utf-8-sig", newline=""))
            writer = csv.writer(output)
            writer.writerow(["frame", "pose_found", "pitch_deg", "yaw_deg", "roll_deg"]
                            + [f"r{row}{col}" for row in range(3) for col in range(3)]
                            + ["track_source"])
        frames = poses = 0
        while args.max_frames is None or frames < args.max_frames:
            ok, frame = capture.read()
            if not ok:
                if frames == 0:
                    raise RuntimeError("Videodan kare okunamadı.")
                break
            box = roi_box
            track_source = "roi"
            if tracker is not None:
                tracked = tracker.update(frame, frames / fps)
                track_source = tracked["source"]
                if track_source != "lost":
                    box = pixels(tracked["bbox"], width, height)
            angles = rotation = None
            values = [""] * 12
            if box is not None:
                left, top, right, bottom = box
                angles, rotation = estimate(model, preprocess, frame[top:bottom, left:right], device, cv2, torch)
                values = [f"{value:.6f}" for value in (*angles, *rotation.ravel())]
                poses += 1
            if writer:
                writer.writerow([frames, int(box is not None), *values, track_source])
            frames += 1
            if not args.no_preview:
                annotate(frame, box, angles, rotation, cv2)
                cv2.imshow(WINDOW, frame)
                if cv2.waitKey(1) & 0xFF in (27, ord("q")):
                    break
                if cv2.getWindowProperty(WINDOW, cv2.WND_PROP_VISIBLE) < 1:
                    break
    print(f"{device.upper()} | {frames} kare işlendi, {poses} karede baş pozu hesaplandı.")


if __name__ == "__main__":
    try:
        run(arguments())
    except (ImportError, OSError, RuntimeError, ValueError) as error:
        sys.exit(f"Hata: {error}")
    except KeyboardInterrupt:
        sys.exit(130)
