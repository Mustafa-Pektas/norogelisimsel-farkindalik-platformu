"""
D01 Çocuk Baş Bölgesi (ROI) ve Sahne Hedefleri Çözücüsü:
1. Bilinen D01 pilot videolarında ve 'Deniz' (İsme Tepki) videosunda onaylı ROI,
   sahne hedefleri (adult_face, adult_body, toy) ve seslenme (call) zamanlarını kullanır.
2. Herhangi bir yeni/farklı videoda ise sunucudaki Gemini Flash-Lite API'sini kullanarak
   videonun başlangıç ve orta karelerinden:
   - Çocuğun baş bölgesini (child_head_box_1000)
   - Yetişkinin yüz ve gövde kutularını (adult_face_box_1000, adult_body_box_1000)
   - Çocuğun ilgilendiği oyuncak/nesne kutusunu (toy_box_1000)
   tek çağrıda (~0.5 sn) otomatik tespit eder.
3. Çevrimdışı ortamda çalışılıyorsa MediaPipe çok-ölçekli yüz taramasına yedek (fallback) yapar.
"""
import os
import copy
import json
import base64
import hashlib
import urllib.request
import urllib.error
from pathlib import Path
from typing import Dict, Any, Optional, Tuple, List
import numpy as np
import cv2


KNOWN_D01_ROIS: Dict[str, Dict[str, Any]] = {
    # Video C: 20261024200833.mp4 (168 kare, 1280x720, 24 FPS)
    "b6e12246983f8852f2cef4397b328ec9c0412294564a17212a4021a653eaf605": {
        "video_id": "20261024200833",
        "x": 220,
        "y": 140,
        "width": 320,
        "height": 320,
        "padding_ltrb_source_px": [0, 0, 0, 0],
        "padding_rgb": None,
        "human_supplied": True,
        "calls": [
            {"id": "call_01", "name": "Seslenme", "start_s": 0.90, "end_s": 1.50}
        ],
        "targets": [
            {"id": "adult_face", "type": "person_face", "bbox": [0.72, 0.08, 0.96, 0.48]},
            {"id": "toy", "type": "object", "bbox": [0.20, 0.58, 0.55, 0.95]},
        ],
    },
    # Video B: 20261028135334.mp4 (167 kare, 1280x720, 24 FPS)
    "6f127ff5c5ebcb5a8e6dc6bf7ca1fb6ad2bbab3b4bdffda6fe6fb2da7bb4f6a1": {
        "video_id": "20261028135334",
        "x": 250,
        "y": -40,
        "width": 440,
        "height": 440,
        "padding_ltrb_source_px": [0, 40, 0, 0],
        "padding_rgb": [128, 128, 128],
        "human_supplied": True,
        "calls": [],
        "targets": [],
    },
    # Deniz Videosu: video_2026-11-07_17-13-48.mp4 / orijinal.mp4 (192 kare, 1280x720, 24 FPS)
    "859ee4bb02fb1e4467694f8631cbd16462bd7d2ecbac76c66d28b7f96024977e": {
        "video_id": "deniz_20261010235630",
        "x": 330,
        "y": 110,
        "width": 360,
        "height": 360,
        "padding_ltrb_source_px": [0, 0, 0, 0],
        "padding_rgb": [128, 128, 128],
        "human_supplied": True,
        "adult_direction_in_image": "right",
        "calls": [
            {
                "id": "deniz_01",
                "name": "Deniz",
                "language": "tr",
                "start_s": 1.65,
                "end_s": 2.53,
            }
        ],
        "targets": [
            {"id": "adult_face", "type": "person_face", "bbox": [0.63, 0.08, 0.77, 0.37]},
            {"id": "toy", "type": "object", "bbox": [0.27, 0.79, 0.59, 0.99]},
        ],
    },
}

# Deniz videosunun sunucuda ve depoda bulunan kopyası (sample_videos/video_2026-11-07_17-13-48.mp4).
# Aynı sahne, ROI, hedefler ve "Deniz" çağrısı (1.65–2.53 sn); yalnız dosya kodlaması farklı.
DENIZ_SERVER_SHA256 = "ac7edda0df9fd3871ce7ddb5b07e4ad91994d6c283865c2104f3bf2c97a24487"
KNOWN_D01_ROIS[DENIZ_SERVER_SHA256] = copy.deepcopy(
    KNOWN_D01_ROIS["859ee4bb02fb1e4467694f8631cbd16462bd7d2ecbac76c66d28b7f96024977e"]
)

FILENAME_FALLBACK_ROIS: Dict[str, str] = {
    "20261024200833.mp4": "b6e12246983f8852f2cef4397b328ec9c0412294564a17212a4021a653eaf605",
    "20261028135334.mp4": "6f127ff5c5ebcb5a8e6dc6bf7ca1fb6ad2bbab3b4bdffda6fe6fb2da7bb4f6a1",
    "video_2026-11-07_17-13-48.mp4": DENIZ_SERVER_SHA256,
    "orijinal.mp4": "859ee4bb02fb1e4467694f8631cbd16462bd7d2ecbac76c66d28b7f96024977e",
}


def compute_file_sha256(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def _load_gemini_credentials() -> Tuple[Optional[str], str]:
    """
    Ortam değişkenlerinden veya sunucudaki /opt/norogelisim/app/backend/.env dosyasından
    GEMINI_API_KEY ve model adını otomatik okur.
    """
    api_key = os.environ.get("GEMINI_API_KEY")
    model_name = os.environ.get("SCENARIO_INPUT_MODEL") or "gemini-2.5-flash-lite"

    env_paths = [
        "/opt/norogelisim/app/backend/.env",
        str(Path(__file__).resolve().parents[2] / "backend" / ".env"),
    ]
    for env_path in env_paths:
        if os.path.exists(env_path):
            try:
                with open(env_path, "r", encoding="utf-8") as f:
                    for line in f:
                        line = line.strip()
                        if not line or line.startswith("#") or "=" not in line:
                            continue
                        k, v = line.split("=", 1)
                        k = k.strip()
                        v = v.strip().strip('"').strip("'")
                        if k == "GEMINI_API_KEY" and v and "BURAYA_" not in v and not api_key:
                            api_key = v
                        elif k == "SCENARIO_INPUT_MODEL" and v:
                            model_name = v
            except Exception:
                pass
    return api_key, model_name


def _box1000_to_norm_xyxy(box: Any) -> Optional[List[float]]:
    """[ymin, xmin, ymax, xmax] (0..1000) kutusunu [xmin, ymin, xmax, ymax] (0..1) formatına çevirir."""
    if not isinstance(box, list) or len(box) != 4:
        return None
    try:
        ymin, xmin, ymax, xmax = [ float(v) / 1000.0 for v in box ]
        xmin = float(np.clip(xmin, 0.0, 1.0))
        ymin = float(np.clip(ymin, 0.0, 1.0))
        xmax = float(np.clip(xmax, 0.0, 1.0))
        ymax = float(np.clip(ymax, 0.0, 1.0))
        if xmax > xmin + 0.02 and ymax > ymin + 0.02:
            return [round(xmin, 4), round(ymin, 4), round(xmax, 4), round(ymax, 4)]
    except Exception:
        pass
    return None


def gemini_detect_child_roi(frames_bgr: List[np.ndarray], video_id: str) -> Optional[Dict[str, Any]]:
    """
    Videonun başlangıç ve orta karelerini tek bir Gemini Flash-Lite çağrısında göndererek:
    - Sahnedeki ÇOCUĞUN baş bölgesini (child_head_box_1000)
    - Yetişkinin yüz ve gövde bölgelerini (adult_face_box_1000, adult_body_box_1000)
    - Çocuğun oynadığı oyuncak/nesne bölgesini (toy_box_1000)
    otomatik tespit eder.
    """
    api_key, configured_model = _load_gemini_credentials()
    if not api_key or not frames_bgr:
        return None

    vid_h, vid_w = frames_bgr[0].shape[:2]
    parts = []
    for frm in frames_bgr[:2]:
        ok, buf = cv2.imencode(".jpg", frm, [int(cv2.IMWRITE_JPEG_QUALITY), 85])
        if ok:
            b64_img = base64.b64encode(buf.tobytes()).decode("ascii")
            parts.append({"inline_data": {"mime_type": "image/jpeg", "data": b64_img}})

    if not parts:
        return None

    prompt = (
        "Analyze these frames from a child-development video and locate the CHILD (toddler/young child, "
        "NOT the adult/parent/caregiver) as well as scene targets. Return a JSON object with:\n"
        "- child_head_box_1000: [ymin, xmin, ymax, xmax] (0..1000) covering the union of the child's entire head across the frames.\n"
        "- adult_face_box_1000: [ymin, xmin, ymax, xmax] (0..1000) for the adult/caregiver's head/face if visible, else null.\n"
        "- adult_body_box_1000: [ymin, xmin, ymax, xmax] (0..1000) for the adult/caregiver's torso/body if visible, else null.\n"
        "- toy_box_1000: [ymin, xmin, ymax, xmax] (0..1000) for the main toy/object the child is playing with or looking at, else null.\n"
        "- adult_direction_in_image: 'right', 'left', or 'none' (where the adult is relative to the child in the image)."
    )
    parts.append({"text": prompt})

    payload = {
        "contents": [{"parts": parts}],
        "generationConfig": {
            "temperature": 0.0,
            "responseMimeType": "application/json",
        },
    }

    candidate_models = []
    for m in (configured_model, "gemini-3.5-flash-lite", "gemini-2.5-flash", "gemini-3.1-flash-lite"):
        if m and m not in candidate_models:
            candidate_models.append(m)

    for model_id in candidate_models:
        url = f"https://generativelanguage.googleapis.com/v1beta/models/{model_id}:generateContent?key={api_key}"
        try:
            req = urllib.request.Request(
                url,
                data=json.dumps(payload).encode("utf-8"),
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=12) as resp:
                body = json.loads(resp.read().decode("utf-8"))
            text = body["candidates"][0]["content"]["parts"][0]["text"]
            parsed = json.loads(text)
            box = parsed.get("child_head_box_1000")
            if isinstance(box, list) and len(box) == 4:
                ymin, xmin, ymax, xmax = [float(v) for v in box]
                cx = ((xmin + xmax) * 0.5 / 1000.0) * vid_w
                cy = ((ymin + ymax) * 0.5 / 1000.0) * vid_h
                head_w = ((xmax - xmin) / 1000.0) * vid_w
                head_h = ((ymax - ymin) / 1000.0) * vid_h
                head_size = max(head_w, head_h)

                # MediaPipe ile Piksel Hassasiyetinde Merkezleme (Füzyon)
                try:
                    try:
                        from mediapipe.python.solutions import face_detection as mp_fd
                    except Exception:
                        import mediapipe as mp
                        mp_fd = mp.solutions.face_detection

                    rgb_0 = cv2.cvtColor(frames_bgr[0], cv2.COLOR_BGR2RGB)
                    with mp_fd.FaceDetection(model_selection=1, min_detection_confidence=0.25) as fd:
                        res = fd.process(rgb_0)
                        if res and res.detections:
                            child_candidates = []
                            for det in res.detections:
                                bb = det.location_data.relative_bounding_box
                                f_cx = (bb.xmin + bb.width * 0.5) * vid_w
                                f_cy = (bb.ymin + bb.height * 0.5) * vid_h
                                f_size = max(bb.width * vid_w, bb.height * vid_h)
                                # Gemini'nin çocuk kutusunun içindeki veya çok yakınındaki yüzü seç
                                if (xmin * 0.85 <= (f_cx / vid_w * 1000.0) <= xmax * 1.15 and
                                    ymin * 0.85 <= (f_cy / vid_h * 1000.0) <= ymax * 1.25):
                                    dist = np.hypot(f_cx - cx, f_cy - cy)
                                    child_candidates.append((dist, f_cx, f_cy, f_size))
                            if child_candidates:
                                child_candidates.sort(key=lambda c: c[0])
                                _, best_cx, best_cy, best_fsize = child_candidates[0]
                                cx = best_cx
                                cy = best_cy
                                head_size = max(head_size, best_fsize * 1.8)
                except Exception:
                    pass

                roi_side = int(np.clip(head_size * 1.8, 320, min(vid_w, vid_h)))
                roi_side = (roi_side // 10) * 10

                # Yetişkin yönüne göre asimetrik hareket payı (çocuk dönünce başı kutudan taşmasın)
                adult_dir = parsed.get("adult_direction_in_image")
                if adult_dir == "right":
                    cx += roi_side * 0.06
                    cy -= roi_side * 0.08
                elif adult_dir == "left":
                    cx -= roi_side * 0.06
                    cy -= roi_side * 0.08
                else:
                    cy -= roi_side * 0.05

                rx = int(np.clip(cx - roi_side * 0.5, 0, max(0, vid_w - roi_side)))
                ry = int(np.clip(cy - roi_side * 0.5, 0, max(0, vid_h - roi_side)))

                targets = []
                af = _box1000_to_norm_xyxy(parsed.get("adult_face_box_1000"))
                if af:
                    targets.append({"id": "adult_face", "type": "person_face", "bbox": af})
                tb = _box1000_to_norm_xyxy(parsed.get("toy_box_1000"))
                if tb:
                    targets.append({"id": "toy", "type": "object", "bbox": tb})

                return {
                    "video_id": video_id,
                    "x": rx,
                    "y": ry,
                    "width": roi_side,
                    "height": roi_side,
                    "padding_ltrb_source_px": [0, 0, 0, 0],
                    "padding_rgb": [128, 128, 128],
                    "human_supplied": False,
                    "source": f"gemini_semantic_child_roi ({model_id})",
                    "adult_direction_in_image": parsed.get("adult_direction_in_image"),
                    "targets": targets,
                    "calls": [],
                }
        except Exception as exc:
            print(f"    [Gemini ROI Uyarı ({model_id})]: {exc}", flush=True)
            continue
    return None


def auto_detect_child_roi(video_path: str) -> Dict[str, Any]:
    """
    Önceden tanımlı olmayan herhangi bir yeni video verildiğinde:
    1. Önce Gemini Flash-Lite ile videonun başlangıç ve orta karesinden çocuğu ve hedefleri tespit eder.
    2. Eğer API anahtarı veya internet yoksa MediaPipe FaceDetection yedeğine düşer.
    """
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise ValueError(f"Video açılamadı: {video_path}")

    vid_w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)) or 1280
    vid_h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT)) or 720
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT)) or 120
    mid_idx = max(1, total_frames // 2)

    key_frames: List[np.ndarray] = []
    sample_frames: List[np.ndarray] = []
    idx = 0
    while True:
        ret, frame = cap.read()
        if not ret:
            break
        if idx in (0, mid_idx):
            key_frames.append(frame)
        if idx < 60 and idx % 5 == 0:
            sample_frames.append(frame)
        idx += 1
        if idx > mid_idx and len(key_frames) >= 2:
            break
    cap.release()

    video_id = Path(video_path).stem

    if key_frames:
        print("--> Yeni video tespit edildi: Gemini Flash-Lite ile çocuk ROI ve sahne hedefleri aranıyor...", flush=True)
        gemini_roi = gemini_detect_child_roi(key_frames, video_id)
        if gemini_roi is not None:
            t_ids = [t["id"] for t in gemini_roi.get("targets", [])]
            print(
                f"--> Gemini Çocuk ROI Buldu: x={gemini_roi['x']}, y={gemini_roi['y']}, "
                f"{gemini_roi['width']}x{gemini_roi['height']} | Hedefler: {t_ids}",
                flush=True,
            )
            return gemini_roi

    detected_candidates = []
    try:
        try:
            from mediapipe.python.solutions import face_detection as mp_face_det
        except Exception:
            import mediapipe as mp
            mp_face_det = mp.solutions.face_detection

        for model_sel in (1, 0):
            with mp_face_det.FaceDetection(model_selection=model_sel, min_detection_confidence=0.3) as fd:
                for frame in sample_frames:
                    rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                    res = fd.process(rgb)
                    if not res.detections:
                        continue
                    for det in res.detections:
                        bb = det.location_data.relative_bounding_box
                        bw = bb.width * vid_w
                        bh = bb.height * vid_h
                        cx = (bb.xmin + bb.width * 0.5) * vid_w
                        cy = (bb.ymin + bb.height * 0.5) * vid_h
                        size = max(bw, bh)
                        if size >= 35:
                            detected_candidates.append((cx, cy, size))
            if detected_candidates:
                break
    except Exception:
        pass

    if detected_candidates:
        med_cx = float(np.median([c[0] for c in detected_candidates]))
        med_cy = float(np.median([c[1] for c in detected_candidates]))
        med_size = float(np.median([c[2] for c in detected_candidates]))
        roi_side = int(np.clip(med_size * 2.4, 320, min(vid_w, vid_h)))
        roi_side = (roi_side // 10) * 10
        rx = int(np.clip(med_cx - roi_side * 0.5, 0, max(0, vid_w - roi_side)))
        ry = int(np.clip(med_cy - roi_side * 0.5, 0, max(0, vid_h - roi_side)))
        return {
            "video_id": video_id,
            "x": rx,
            "y": ry,
            "width": roi_side,
            "height": roi_side,
            "padding_ltrb_source_px": [0, 0, 0, 0],
            "padding_rgb": [128, 128, 128],
            "human_supplied": False,
            "source": "mediapipe_fallback_roi",
            "targets": [],
            "calls": [],
        }

    roi_side = min(vid_w, vid_h, 480)
    return {
        "video_id": video_id,
        "x": (vid_w - roi_side) // 2,
        "y": (vid_h - roi_side) // 2,
        "width": roi_side,
        "height": roi_side,
        "padding_ltrb_source_px": [0, 0, 0, 0],
        "padding_rgb": [128, 128, 128],
        "human_supplied": False,
        "source": "center_fallback_roi",
        "targets": [],
        "calls": [],
    }


def resolve_video_roi(
    video_path: str,
    custom_roi_str: Optional[str] = None,
    force_auto: bool = False,
) -> Tuple[Dict[str, Any], str]:
    video_sha = compute_file_sha256(video_path)

    if custom_roi_str:
        parts = [int(p.strip()) for p in custom_roi_str.split(",")]
        if len(parts) != 4:
            raise ValueError("--roi formatı 'x,y,width,height' olmalıdır (örn: 220,140,320,320)")
        x, y, w, h = parts
        base_known = KNOWN_D01_ROIS.get(video_sha, {})
        return {
            "video_id": Path(video_path).stem,
            "x": x,
            "y": y,
            "width": w,
            "height": h,
            "padding_ltrb_source_px": [0, 0, 0, 0],
            "padding_rgb": [128, 128, 128],
            "human_supplied": True,
            "source": "cli_override",
            "targets": base_known.get("targets", []),
            "calls": base_known.get("calls", []),
        }, video_sha

    if not force_auto:
        if video_sha in KNOWN_D01_ROIS:
            roi = dict(KNOWN_D01_ROIS[video_sha])
            roi["source"] = "d01_pilot_profiles_sha256"
            return roi, video_sha

        fname = Path(video_path).name
        if fname in FILENAME_FALLBACK_ROIS:
            roi = dict(KNOWN_D01_ROIS[FILENAME_FALLBACK_ROIS[fname]])
            roi["source"] = "d01_pilot_profiles_filename"
            return roi, video_sha

    roi = auto_detect_child_roi(video_path)
    # Bilinen çağrı zamanı varsa otomatik ROI'ye de ekle
    if video_sha in KNOWN_D01_ROIS and not roi.get("calls"):
        roi["calls"] = KNOWN_D01_ROIS[video_sha].get("calls", [])
        if not roi.get("targets"):
            roi["targets"] = KNOWN_D01_ROIS[video_sha].get("targets", [])
    return roi, video_sha


def crop_roi_bgr(frame_bgr: np.ndarray, roi: Dict[str, Any]) -> np.ndarray:
    img_h, img_w = frame_bgr.shape[:2]
    x = int(roi["x"])
    y = int(roi["y"])
    w = int(roi["width"])
    h = int(roi["height"])

    left = max(0, x)
    top = max(0, y)
    right = min(img_w, x + w)
    bottom = min(img_h, y + h)

    if left == x and top == y and right == x + w and bottom == y + h:
        return frame_bgr[top:bottom, left:right].copy()

    pad_rgb = roi.get("padding_rgb") or [128, 128, 128]
    pad_bgr = (int(pad_rgb[2]), int(pad_rgb[1]), int(pad_rgb[0]))
    canvas = np.full((h, w, 3), pad_bgr, dtype=np.uint8)

    if right > left and bottom > top:
        crop = frame_bgr[top:bottom, left:right]
        dst_x = left - x
        dst_y = top - y
        canvas[dst_y:dst_y + (bottom - top), dst_x:dst_x + (right - left)] = crop

    return canvas
