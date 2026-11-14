"""
Geometrik hesaplamalar, SO(3) rotasyon matrisleri, Gimbal-Lock korumalı Euler dönüşümleri,
SQPnP + RefineLM + Reprojection RMSE Doğrulamalı 3D Baş Pozu Çözücüsü ve Göz Merkezli Sahne Hedef Tahmini.
"""
import math
from typing import Tuple, Dict, Any, List, Optional
import numpy as np
import cv2


CANONICAL_FACE_INDICES = [1, 152, 33, 263, 61, 291]
CANONICAL_FACE_MODEL_3D = np.array([
    [0.0, 0.0, 0.0],          # 1: Burun ucu
    [0.0, -63.6, -12.5],      # 152: Çene ucu
    [-43.3, 32.7, -26.0],     # 33: Sol göz dış köşe
    [43.3, 32.7, -26.0],      # 263: Sağ göz dış köşe
    [-28.9, -28.9, -24.1],    # 61: Sol ağız köşesi
    [28.9, -28.9, -24.1],     # 291: Sağ ağız köşesi
], dtype=np.float64)


def get_camera_matrix(width: int, height: int) -> Tuple[np.ndarray, np.ndarray]:
    """Kamera iç parametre matrisini (focal length ve optical center) oluşturur."""
    focal_length = float(max(width, height))
    center = (width / 2.0, height / 2.0)
    camera_matrix = np.array([
        [focal_length, 0.0, center[0]],
        [0.0, focal_length, center[1]],
        [0.0, 0.0, 1.0]
    ], dtype=np.float64)
    dist_coeffs = np.zeros((4, 1), dtype=np.float64)
    return camera_matrix, dist_coeffs


def _wrap_deg(angle: float) -> float:
    """Açıyı [-180, +180] aralığına sarar."""
    return (angle + 180.0) % 360.0 - 180.0


def rotation_matrix_to_euler(R: np.ndarray) -> Tuple[float, float, float]:
    """
    3x3 SO(3) Rotasyon matrisinden Gimbal-Lock korumalı Euler açılarını (Yaw, Pitch, Roll) hesaplar.
    """
    sy = math.sqrt(R[0, 0] * R[0, 0] + R[1, 0] * R[1, 0])
    yaw_rad = math.atan2(-R[2, 0], sy)
    yaw = math.degrees(yaw_rad)

    if sy > 1e-6:
        pitch_std = math.degrees(math.atan2(R[2, 1], R[2, 2]))
        roll_std = math.degrees(math.atan2(R[1, 0], R[0, 0]))
    else:
        pitch_std = 0.0
        roll_std = 0.0

    if sy < 0.52:
        if R[2, 0] >= 0:  # Yaw <= 0 (sağa dönüş) -> s = pitch + roll
            coupled_rad = math.atan2(-(R[0, 1] + R[1, 2]), R[1, 1] - R[0, 2])
            coupled_deg = math.degrees(coupled_rad)
            w = max(0.0, min(1.0, (sy - 0.28) / 0.24))
            if abs(pitch_std) > 75.0 or abs(roll_std) > 75.0:
                w = 0.0
            roll = w * roll_std
            pitch = _wrap_deg(coupled_deg - roll)
        else:  # Yaw > 0 (sola dönüş) -> s = pitch - roll
            coupled_rad = math.atan2(R[0, 1] - R[1, 2], R[1, 1] + R[0, 2])
            coupled_deg = math.degrees(coupled_rad)
            w = max(0.0, min(1.0, (sy - 0.28) / 0.24))
            if abs(pitch_std) > 75.0 or abs(roll_std) > 75.0:
                w = 0.0
            roll = w * roll_std
            pitch = _wrap_deg(coupled_deg + roll)
    else:
        pitch = pitch_std
        roll = roll_std

    return yaw, pitch, roll


def euler_to_rotation_matrix(yaw_deg: float, pitch_deg: float, roll_deg: float) -> np.ndarray:
    """
    Derece cinsinden (Yaw, Pitch, Roll) açılarından 6DRepNet360 ile birebir aynı
    koordinat uzayında 3x3 SO(3) rotasyon matrisi (R = Rz(roll) @ Ry(yaw) @ Rx(pitch)) üretir.
    """
    x = math.radians(pitch_deg)
    y = math.radians(yaw_deg)
    z = math.radians(roll_deg)

    Rx = np.array([
        [1.0, 0.0, 0.0],
        [0.0, math.cos(x), -math.sin(x)],
        [0.0, math.sin(x), math.cos(x)]
    ], dtype=np.float64)

    Ry = np.array([
        [math.cos(y), 0.0, math.sin(y)],
        [0.0, 1.0, 0.0],
        [-math.sin(y), 0.0, math.cos(y)]
    ], dtype=np.float64)

    Rz = np.array([
        [math.cos(z), -math.sin(z), 0.0],
        [math.sin(z), math.cos(z), 0.0],
        [0.0, 0.0, 1.0]
    ], dtype=np.float64)

    return Rz @ Ry @ Rx


def solve_sqpnp_reprojection(face_landmarks, width: int, height: int) -> Dict[str, Any]:
    """
    Isme_Tepki/sesyon/vision.py içindeki SOLVEPNP_SQPNP + solvePnPRefineLM + Reprojection RMSE
    hesabını çalıştırır.
    """
    image_pts = np.array(
        [[face_landmarks[i].x * width, face_landmarks[i].y * height] for i in CANONICAL_FACE_INDICES],
        dtype=np.float64,
    )
    camera_matrix, dist_coeffs = get_camera_matrix(width, height)
    try:
        ok, rvec, tvec = cv2.solvePnP(
            CANONICAL_FACE_MODEL_3D,
            image_pts,
            camera_matrix,
            dist_coeffs,
            flags=cv2.SOLVEPNP_SQPNP,
        )
        if not ok:
            return {"valid": False, "reprojection_px": None}
        if hasattr(cv2, "solvePnPRefineLM"):
            rvec, tvec = cv2.solvePnPRefineLM(
                CANONICAL_FACE_MODEL_3D, image_pts, camera_matrix, dist_coeffs, rvec, tvec
            )
        if not (np.isfinite(rvec).all() and np.isfinite(tvec).all() and float(tvec[2, 0]) > 0):
            return {"valid": False, "reprojection_px": None}

        projected, _ = cv2.projectPoints(CANONICAL_FACE_MODEL_3D, rvec, tvec, camera_matrix, dist_coeffs)
        reproj_err = float(np.sqrt(np.mean(np.sum((projected.reshape(-1, 2) - image_pts) ** 2, axis=1))))
        return {
            "valid": reproj_err <= 12.0,
            "reprojection_px": round(reproj_err, 3),
        }
    except Exception:
        return {"valid": False, "reprojection_px": None}


def solve_mediapipe_3d_head_pose(face_landmarks, width: int, height: int) -> Dict[str, Any]:
    """
    MediaPipe FaceMesh 3D metrik landmarklarından kararlı 3D baş yönelimini (Yaw, Pitch, Roll ve SO(3) R),
    kafatası dolgulu dar kafa kutusunu ve GÖZ MERKEZİ (eyes_center_roi) koordinatlarını hesaplar.
    """
    def pt3d(idx: int) -> np.ndarray:
        lm = face_landmarks[idx]
        return np.array([lm.x * width, lm.y * height, lm.z * width], dtype=np.float64)

    p_left = np.mean([pt3d(33), pt3d(234), pt3d(127), pt3d(61)], axis=0)
    p_right = np.mean([pt3d(263), pt3d(454), pt3d(356), pt3d(291)], axis=0)
    p_top = np.mean([pt3d(10), pt3d(168), pt3d(105), pt3d(334)], axis=0)
    p_bottom = np.mean([pt3d(152), pt3d(199), pt3d(175)], axis=0)
    p_nose = np.mean([pt3d(1), pt3d(4)], axis=0)
    p_mid_lr = 0.5 * (p_left + p_right)

    v_x = p_right - p_left
    v_y = p_bottom - p_top
    face_h = max(10.0, float(np.linalg.norm(v_y[:2])))

    yaw_from_3d = math.degrees(math.atan2(-v_x[2], max(4.0, abs(v_x[0]))))
    nose_dx_ratio = float(np.clip((p_nose[0] - p_mid_lr[0]) / (face_h * 0.55), -1.2, 1.2))
    yaw_from_nose = -math.degrees(math.asin(np.clip(nose_dx_ratio, -0.98, 0.98)))
    yaw_deg = float(np.clip(0.65 * yaw_from_3d + 0.35 * yaw_from_nose, -95.0, 95.0))

    pitch_deg = float(np.clip(math.degrees(math.atan2(-v_y[2], max(10.0, v_y[1]))) - 8.0, -75.0, 75.0))
    roll_deg = float(np.clip(math.degrees(math.atan2(-v_y[0], max(10.0, v_y[1]))), -60.0, 60.0))

    R = euler_to_rotation_matrix(yaw_deg, pitch_deg, roll_deg)
    sqpnp_info = solve_sqpnp_reprojection(face_landmarks, width, height)

    xs = [lm.x * width for lm in face_landmarks]
    ys = [lm.y * height for lm in face_landmarks]
    x1, y1, x2, y2 = min(xs), min(ys), max(xs), max(ys)
    bw, bh = max(8.0, x2 - x1), max(8.0, y2 - y1)

    face_bbox_roi = [
        float(max(0.0, x1 - 0.14 * bw)),
        float(max(0.0, y1 - 0.28 * bh)),
        float(min(float(width - 1), x2 + 0.14 * bw)),
        float(min(float(height - 1), y2 + 0.08 * bh)),
    ]

    vis_indices = [1, 4, 10, 33, 133, 362, 263, 61, 291, 152, 168, 234, 454, 105, 334]
    landmarks_draw_roi = [
        [float(face_landmarks[i].x * width), float(face_landmarks[i].y * height)]
        for i in vis_indices
    ]

    iris_pts_roi = []
    if len(face_landmarks) > 473:
        iris_pts_roi = [
            [float(face_landmarks[468].x * width), float(face_landmarks[468].y * height)],
            [float(face_landmarks[473].x * width), float(face_landmarks[473].y * height)],
        ]
        # İki göz bebeğinin tam orta noktası (Göz Merkezi)
        eyes_center_roi = [
            0.5 * (iris_pts_roi[0][0] + iris_pts_roi[1][0]),
            0.5 * (iris_pts_roi[0][1] + iris_pts_roi[1][1]),
        ]
    else:
        # Göz köşeleri (33, 133, 362, 263) ve burun köprüsü (168) ortalaması
        eye_idxs = [33, 133, 362, 263, 168]
        eyes_center_roi = [
            float(np.mean([face_landmarks[i].x * width for i in eye_idxs])),
            float(np.mean([face_landmarks[i].y * height for i in eye_idxs])),
        ]

    nose_xy_roi = [float(face_landmarks[1].x * width), float(face_landmarks[1].y * height)]

    return {
        "yaw": yaw_deg,
        "pitch": pitch_deg,
        "roll": roll_deg,
        "rotation_matrix": R,
        "pose_reprojection_px": sqpnp_info["reprojection_px"],
        "sqpnp_valid": sqpnp_info["valid"],
        "eyes_center_roi": eyes_center_roi,
        "nose_xy_roi": nose_xy_roi,
        "face_bbox_roi": face_bbox_roi,
        "landmarks_draw_roi": landmarks_draw_roi,
        "iris_pts_roi": iris_pts_roi,
    }


def _target_boxes_px(targets: Optional[List[Dict[str, Any]]], width: int, height: int) -> Dict[str, List[float]]:
    boxes: Dict[str, List[float]] = {}
    for t in targets or []:
        tid = t.get("id")
        bbox = t.get("bbox")
        if tid in ("toy", "adult_face") and bbox and len(bbox) == 4:
            boxes[tid] = [bbox[0] * width, bbox[1] * height, bbox[2] * width, bbox[3] * height]
    return boxes


def target_anchor_point(target: str, box: List[float]) -> List[int]:
    """Hedef kutusu içindeki sabit odak noktası (oyuncakta orta-üst, yetişkinde göz/burun bölgesi)."""
    x1, y1, x2, y2 = box
    if target == "adult_face":
        return [int(round(x1 + 0.46 * (x2 - x1))), int(round(y1 + 0.48 * (y2 - y1)))]
    # Oyuncak kutuları çoğu zaman masa/zemin yüzeyini de kapsar; oyuncaklar kutunun üst-orta kısmındadır
    return [int(round(0.5 * (x1 + x2))), int(round(y1 + 0.35 * (y2 - y1)))]


def select_gaze_target(
    prev_target: Optional[str],
    yaw_deg: float,
    pitch_deg: float,
    baseline_yaw: float,
    baseline_pitch: float,
    pose_change_deg: Optional[float],
    adult_is_right: Optional[bool],
    has_toy: bool,
    has_adult: bool,
) -> Optional[str]:
    """
    Histerezisli iki-hedef durum makinesi (D01 protokolü: çağrı öncesi çocuk oyuncakla oynar).
    - Taban (çağrı öncesi medoid) poz = oyuncağa bakış. Göreli açılar bu poza göre hesaplanır.
    - 'adult_face'e geçiş: tabandan ≥ 25° sapma VE baş yetişkin tarafına dönük (yetişkin sağdaysa
      göreli yaw ≤ -15°, soldaysa ≥ +15°) ya da baş belirgin kalkık (göreli pitch ≥ +18°).
    - 'toy'a dönüş: sapma ≤ 15° ya da baş artık yetişkine dönük değil ve kalkık değil (göreli pitch ≤ +8°).
    - Arada önceki hedef korunur; böylece ok hedefler arasında titremez ve boş arka plana gitmez.
    """
    rel_yaw = (yaw_deg - baseline_yaw + 180.0) % 360.0 - 180.0
    rel_pitch = pitch_deg - baseline_pitch
    if adult_is_right is None:
        toward_adult = rel_pitch >= 18.0
    else:
        toward_adult = (rel_yaw <= -15.0) if adult_is_right else (rel_yaw >= 15.0)
        toward_adult = toward_adult or rel_pitch >= 18.0

    if pose_change_deg is None:
        # Taban poza göre sapma ölçülemiyorsa (SO(3) poz yok) hedef doğrulanamaz: pembe ok gizlenir
        return None

    if prev_target == "adult_face" and has_adult:
        back_to_toy = pose_change_deg <= 15.0 or (not toward_adult and rel_pitch <= 8.0)
        if back_to_toy:
            return "toy" if has_toy else None
        return "adult_face"

    if has_adult and pose_change_deg >= 25.0 and toward_adult:
        return "adult_face"
    if has_toy:
        return "toy"
    return None


def estimate_scene_gaze_target(
    eye_x_px: float,
    eye_y_px: float,
    yaw_deg: Optional[float],
    pitch_deg: Optional[float],
    width: int,
    height: int,
    targets: Optional[List[Dict[str, Any]]],
    pose_change_deg: Optional[float] = None,
    baseline_yaw: float = -20.0,
    baseline_pitch: float = -20.0,
    prev_target: Optional[str] = None,
) -> Dict[str, Any]:
    """
    Çocuğun GÖZ MERKEZİNDEN (eye_x_px, eye_y_px) çıkan bakışın:
    1) Sahnedeki hedefi ('toy' / 'adult_face' / None) — histerezisli durum makinesiyle,
    2) Pembe bakış çizgisinin bittiği SABİT hedef noktasını (gaze_point_px; hedef yoksa None),
    3) Kısa turkuaz baş yönü okunun ucunu (arrow_end_px)
    döner. Pembe ok yalnız doğrulanmış bir hedefe çizilir; asla boş arka plana yönelmez.
    """
    if yaw_deg is None or pitch_deg is None:
        return {"target": "unavailable", "gaze_point_px": None, "arrow_end_px": None}

    boxes = _target_boxes_px(targets, width, height)
    adult_is_right = None
    if "adult_face" in boxes:
        af = boxes["adult_face"]
        adult_is_right = 0.5 * (af[0] + af[2]) >= eye_x_px

    target = select_gaze_target(
        prev_target, yaw_deg, pitch_deg, baseline_yaw, baseline_pitch, pose_change_deg,
        adult_is_right, "toy" in boxes, "adult_face" in boxes,
    )

    gaze_pt = target_anchor_point(target, boxes[target]) if target in boxes else None

    # Turkuaz baş yönü oku SÜREKLİDİR: oyuncak yönünden (taban) yetişkin yönüne, tabandan sapmanın
    # yetişkine doğru ilerleme oranıyla döner. Pembe ok ise yalnız doğrulanmış hedefe kilitlenir.
    rel_yaw_deg = (yaw_deg - baseline_yaw + 180.0) % 360.0 - 180.0
    rel_pitch_deg = pitch_deg - baseline_pitch
    if "toy" in boxes or "adult_face" in boxes:
        def _unit(kind: str):
            p = target_anchor_point(kind, boxes[kind])
            dx, dy = p[0] - eye_x_px, p[1] - eye_y_px
            n = max(1e-4, math.hypot(dx, dy))
            return dx / n, dy / n
        toy_dir = _unit("toy") if "toy" in boxes else (0.0, 1.0)
        adult_dir = _unit("adult_face") if "adult_face" in boxes else toy_dir
        if adult_is_right is None:
            toward = rel_pitch_deg > 0
        else:
            toward = (rel_yaw_deg < 0) if adult_is_right else (rel_yaw_deg > 0)
            toward = toward or rel_pitch_deg > 0
        f = float(np.clip(((pose_change_deg or 0.0) - 10.0) / 25.0, 0.0, 1.0)) if toward else 0.0
        if target == "adult_face":
            f = max(f, 0.85)
        elif target == "toy":
            f = min(f, 0.6)
        vx = (1.0 - f) * toy_dir[0] + f * adult_dir[0]
        vy = (1.0 - f) * toy_dir[1] + f * adult_dir[1]
    else:
        vx = math.sin(-math.radians(rel_yaw_deg))
        vy = -math.sin(math.radians(rel_pitch_deg)) + 0.35
    v_len = max(1e-4, math.hypot(vx, vy))
    arrow_end = [
        int(round(eye_x_px + (vx / v_len) * 95.0)),
        int(round(eye_y_px + (vy / v_len) * 95.0)),
    ]
    return {
        "target": target if target is not None else "none",
        "gaze_point_px": gaze_pt,
        "arrow_end_px": arrow_end,
    }


def geodesic_distance_deg(R1: np.ndarray, R2: np.ndarray) -> float:
    """
    İki 3x3 rotasyon matrisi arasındaki Geodezik Mesafeyi (açısal fark) derece olarak ölçer.
    """
    if R1 is None or R2 is None:
        return float('nan')
    try:
        M = np.dot(R1, R2.T)
        trace = np.trace(M)
        cos_angle = (trace - 1.0) / 2.0
        cos_angle = max(-1.0, min(1.0, cos_angle))
        return math.degrees(math.acos(cos_angle))
    except Exception:
        return float('nan')
