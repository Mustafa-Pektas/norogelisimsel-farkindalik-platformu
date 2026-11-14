"""
D01 Baş Dönüşü Başlangıç (Onset), Bitiş / Yerleşme (Settling), Çağrı Öncesi Başlangıç Pozuna Göre
SO(3) Medoid Sapma Açısı (pose_change_deg). Grafikler common/reporting.py'de (PDF/Excel/HTML) üretilir.
"""
import math
from typing import List, Dict, Any, Optional
import numpy as np
from scipy.spatial.transform import Rotation

from common.types import PoseResult
from common.geometry import rotation_matrix_to_euler


DEFAULT_MOTION_CONFIG = {
    "protocol": "head-motion-candidates-engineering-v1",
    "window_intervals": 5,
    "start_confirmation_samples": 3,
    "stop_confirmation_samples": 5,
    "max_dt_factor": 1.5,
    "nominal_fps": 24,
    "base_setting": {"id": "base", "start_deg_s": 45, "stop_deg_s": 20},
}


def project_so3(value: Optional[np.ndarray]) -> Optional[np.ndarray]:
    """Geçerli 3x3 SO(3) matrisini doğrular ve küçük yuvarlama hatalarını SVD ile düzeltir."""
    if value is None:
        return None
    m = np.asarray(value, dtype=float)
    if (
        m.shape != (3, 3)
        or not np.isfinite(m).all()
        or abs(np.linalg.det(m) - 1.0) > 1e-3
        or np.max(abs(m.T @ m - np.eye(3))) > 1e-3
    ):
        return None
    u, _, vt = np.linalg.svd(m)
    return u @ np.diag([1.0, 1.0, np.linalg.det(u @ vt)]) @ vt


def so3_angle_deg(a: np.ndarray, b: np.ndarray) -> float:
    return math.degrees(math.acos(float(np.clip((np.trace(a.T @ b) - 1.0) / 2.0, -1.0, 1.0))))


def causal_ema_matrices(matrices: List[Optional[np.ndarray]], alpha: float = 0.5) -> List[Optional[np.ndarray]]:
    """Nedensel SO(3) log/exp Üstel Hareketli Ortalama (EMA). None geldiğinde süreklilik sıfırlanır."""
    result = []
    previous = None
    for matrix in matrices:
        m = project_so3(matrix)
        if m is None:
            previous = None
            result.append(None)
            continue
        if previous is None:
            previous = m
        else:
            previous = previous @ Rotation.from_rotvec(
                alpha * Rotation.from_matrix(previous.T @ m).as_rotvec()
            ).as_matrix()
        result.append(previous.copy())
    return result


def compute_baseline_pose_change(
    results: List[PoseResult],
    calls: Optional[List[Dict[str, Any]]] = None,
    fps: float = 24.0,
) -> Optional[Dict[str, Any]]:
    """
    Isme_Tepki/sesyon/vision.py::add_pose_change ile birebir uyumlu olarak:
    Çağrı öncesi (start_s - 0.8 sn .. start_s - 0.1 sn) geçerli SO(3) matrislerinin
    geodezik medoidini (en merkezi referans pozu) bulur ve her kare için
    pose_change_deg (Head change: X.X deg) değerini hesaplar.
    """
    if calls and len(calls) > 0:
        c0 = calls[0]
        b_end = float(c0.get("start_s", 1.5)) - 0.10
        b_start = max(0.0, float(c0.get("start_s", 1.5)) - 0.90)
    else:
        b_start, b_end = 0.0, 1.40

    base_mats = []
    for r in results:
        t_s = r.metadata.get("decoder_time_s", r.frame_index / fps)
        m = project_so3(r.rotation_matrix) if (r.face_detected and r.rotation_matrix is not None) else None
        if m is not None and b_start <= t_s <= b_end:
            base_mats.append(m)

    # Eğer dar pencerede yeterli örnek yoksa ilk 20 geçerli kareyi kullan
    if len(base_mats) < 4:
        for r in results:
            m = project_so3(r.rotation_matrix) if (r.face_detected and r.rotation_matrix is not None) else None
            if m is not None:
                base_mats.append(m)
            if len(base_mats) >= 12:
                break

    if not base_mats:
        for r in results:
            r.metadata["pose_change_deg"] = None
        return None

    # Geodezik Medoid (diğer referans karelere toplam açısal uzaklığı en küçük olan matris)
    ref_mat = min(base_mats, key=lambda a: sum(so3_angle_deg(a, b) for b in base_mats))

    max_change = 0.0
    first_dev_12deg_s = None
    call_start = float(calls[0]["start_s"]) if (calls and len(calls) > 0) else 1.40

    for r in results:
        t_s = r.metadata.get("decoder_time_s", r.frame_index / fps)
        m = project_so3(r.rotation_matrix) if (r.face_detected and r.rotation_matrix is not None) else None
        if m is not None:
            chg = round(so3_angle_deg(m, ref_mat), 2)
            r.metadata["pose_change_deg"] = chg
            if t_s >= call_start:
                if chg > max_change:
                    max_change = chg
                if chg >= 12.0 and first_dev_12deg_s is None:
                    first_dev_12deg_s = round(t_s, 4)
        else:
            r.metadata["pose_change_deg"] = None

    base_yaw, base_pitch, base_roll = rotation_matrix_to_euler(ref_mat)
    return {
        "baseline_samples": len(base_mats),
        "baseline_yaw": round(base_yaw, 2),
        "baseline_pitch": round(base_pitch, 2),
        "baseline_roll": round(base_roll, 2),
        "max_post_call_pose_change_deg": round(max_change, 2),
        "first_12deg_deviation_s": first_dev_12deg_s,
    }


def detect_v1_candidates(
    records: List[Dict[str, Any]],
    fps: float = 24.0,
    start_deg_s: float = 45.0,
    stop_deg_s: float = 20.0,
    window_intervals: int = 5,
    start_confirm: int = 3,
    stop_confirm: int = 5,
) -> Dict[str, Any]:
    """
    research/d01/motion_candidates.py::detect ile birebir aynı V1 hareket adaylarını bulur.
    """
    dt_max = 1.5 / fps
    mats = [project_so3(r.get("rotation_matrix")) if r.get("valid", False) else None for r in records]
    speed = [None] * len(records)

    for i in range(1, len(records)):
        t_cur = records[i].get("time_s")
        t_prev = records[i - 1].get("time_s")
        if t_cur is None or t_prev is None:
            continue
        dt = t_cur - t_prev
        if (
            mats[i] is not None
            and mats[i - 1] is not None
            and records[i]["frame_index"] == records[i - 1]["frame_index"] + 1
            and math.isfinite(dt)
            and 0 < dt <= dt_max
        ):
            speed[i] = so3_angle_deg(mats[i - 1], mats[i]) / dt

    features = []
    for i, rec in enumerate(records):
        window = speed[max(0, i - window_intervals + 1) : i + 1]
        valid = i >= window_intervals and len(window) == window_intervals and all(v is not None for v in window)
        features.append({
            "frame_index": rec["frame_index"],
            "time_s": rec["time_s"],
            "speed_deg_s": speed[i],
            "median_speed_deg_s": float(np.median(window)) if valid else None,
        })

    events = []
    active = None
    high = []
    low = []
    baseline = False

    def close_unknown(reason: str, idx: int):
        nonlocal active
        active.update(
            end_s=None,
            end_frame=None,
            end_confirmed_s=None,
            end_status=reason,
            last_supported_time_s=features[idx]["time_s"],
        )
        events.append(active)
        active = None

    for i, f in enumerate(features):
        val = f["median_speed_deg_s"]
        if val is None:
            high = []
            low = []
            if active is not None:
                close_unknown("unknown_end_data_gap", max(0, i - 1))
            baseline = False
            continue

        if active is None:
            if val <= stop_deg_s:
                low.append(i)
                if len(low) >= stop_confirm:
                    baseline = True
            else:
                low = []

            if val >= start_deg_s:
                high.append(i)
                if len(high) >= start_confirm:
                    first = features[high[0]]
                    active = {
                        "candidate_id": f"candidate_{len(events) + 1:03d}",
                        "start_s": round(first["time_s"], 4) if baseline else None,
                        "start_frame": first["frame_index"] if baseline else None,
                        "start_status": "observed_rule_boundary" if baseline else "unknown_start_no_quiet_baseline",
                        "first_high_evidence_s": round(first["time_s"], 4),
                        "start_confirmed_s": round(f["time_s"], 4),
                    }
                    high = []
                    low = []
            else:
                high = []
        else:
            if val <= stop_deg_s:
                low.append(i)
                if len(low) >= stop_confirm:
                    first = features[low[0]]
                    active.update(
                        end_s=round(first["time_s"], 4),
                        end_frame=first["frame_index"],
                        end_status="observed_rule_boundary",
                        end_confirmed_s=round(f["time_s"], 4),
                    )
                    events.append(active)
                    active = None
                    baseline = True
                    high = []
                    low = []
            else:
                low = []

    if active is not None:
        close_unknown("unknown_end_clip_ended", len(features) - 1)

    return {
        "candidates": events,
        "features": features,
    }


def evaluate_d01_turn_metrics(
    results: List[PoseResult],
    fps: float = 24.0,
    calls: Optional[List[Dict[str, Any]]] = None,
) -> Dict[str, Any]:
    """
    Modelin çıktısı üzerinden:
    - Geçerli 3D baş pozu kare sayısı, optik akış kare sayısı, kayıp kare sayısı
    - Çağrı öncesi başlangıç pozuna göre SO(3) sapma açısı (pose_change_deg)
    - Raw, EMA_050 (alpha=0.50) ve EMA_025 (alpha=0.25) ile baş dönüşü adaylarını hesaplar.
    """
    pose_change_summary = compute_baseline_pose_change(results, calls=calls, fps=fps)

    raw_matrices = [
        r.rotation_matrix if (r.face_detected and r.rotation_matrix is not None) else None
        for r in results
    ]
    ema050_matrices = causal_ema_matrices(raw_matrices, alpha=0.50)
    ema025_matrices = causal_ema_matrices(raw_matrices, alpha=0.25)

    raw_records, ema050_records, ema025_records = [], [], []
    for i, r in enumerate(results):
        t_s = r.metadata.get("decoder_time_s")
        if t_s is None:
            t_s = i / fps
        raw_m = project_so3(raw_matrices[i])
        m050 = ema050_matrices[i]
        m025 = ema025_matrices[i]
        raw_records.append({"frame_index": r.frame_index, "time_s": float(t_s), "rotation_matrix": raw_m, "valid": raw_m is not None})
        ema050_records.append({"frame_index": r.frame_index, "time_s": float(t_s), "rotation_matrix": m050, "valid": m050 is not None})
        ema025_records.append({"frame_index": r.frame_index, "time_s": float(t_s), "rotation_matrix": m025, "valid": m025 is not None})

    det_raw = detect_v1_candidates(raw_records, fps=fps)
    det_ema050 = detect_v1_candidates(ema050_records, fps=fps)
    det_ema025 = detect_v1_candidates(ema025_records, fps=fps)

    candidates_ema = det_ema050["candidates"]
    candidates_raw = det_raw["candidates"]

    # Eğer çağrı zamanı varsa, çağrı başlangıcından (veya hemen öncesinden) sonraki ilk dönüşü önceliklendir
    call_start_ref = float(calls[0]["start_s"]) - 0.15 if (calls and len(calls) > 0) else 0.0

    def _pick_turn(cands: List[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
        if not cands:
            return None
        for c in cands:
            t0 = c.get("start_s") if c.get("start_s") is not None else c.get("first_high_evidence_s", 0.0)
            if t0 is not None and t0 >= call_start_ref:
                return c
        # Seslenme sonrasında aday yoksa çağrı ÖNCESİ hareket isme tepki sayılmaz
        return None

    first_turn = _pick_turn(candidates_ema) or _pick_turn(candidates_raw)
    if first_turn is not None:
        no_turn_status = None
    elif candidates_ema or candidates_raw:
        no_turn_status = "no_turn_after_call"   # yalnız seslenme öncesi hareket var
    else:
        no_turn_status = "no_turn_detected"

    valid_pose_frames = sum(1 for m in raw_matrices if project_so3(m) is not None)
    optical_flow_only_frames = sum(
        1 for r in results if r.flag in ("OPTICAL_FLOW_ROI_ONLY", "OPTICAL_FLOW_INTERPOLATED", "OPTICAL_FLOW_TRACKED")
    )
    fallback_6d_frames = sum(
        1 for r in results if r.metadata.get("used_6d_fallback") is True
    )
    kp_bridge_frames = sum(
        1 for r in results if r.metadata.get("used_kp_bridge") is True
    )
    # Kayıp: kinematiğe girecek SO(3) matrisi olmayan ve yalnız-optik-akış olarak da işaretlenmemiş kareler
    lost_frames = sum(
        1 for i, r in enumerate(results)
        if project_so3(raw_matrices[i]) is None
        and r.flag not in ("OPTICAL_FLOW_ROI_ONLY", "OPTICAL_FLOW_INTERPOLATED", "OPTICAL_FLOW_TRACKED")
    )

    return {
        "valid_pose_frames": valid_pose_frames,
        "optical_flow_only_frames": optical_flow_only_frames,
        "lost_frames": max(0, lost_frames),
        "fallback_6d_frames": fallback_6d_frames,
        "kp_bridge_frames": kp_bridge_frames,
        "pose_change_summary": pose_change_summary,
        "first_turn_onset_s": (
            first_turn["start_s"]
            if first_turn and first_turn.get("start_s") is not None
            else (first_turn["first_high_evidence_s"] if first_turn else None)
        ),
        "first_turn_onset_confirmed_s": first_turn["start_confirmed_s"] if first_turn else None,
        "first_turn_end_s": first_turn["end_s"] if first_turn else None,
        "first_turn_end_confirmed_s": first_turn["end_confirmed_s"] if first_turn else None,
        "first_turn_end_status": first_turn["end_status"] if first_turn else no_turn_status,
        "ema_050_candidates": candidates_ema,
        "ema_025_candidates": det_ema025["candidates"],
        "raw_candidates": candidates_raw,
        "_plot_series": {
            "raw_matrices": raw_matrices,
            "ema050_matrices": ema050_matrices,
            "ema025_matrices": ema025_matrices,
            "raw_features": det_raw["features"],
            "ema050_features": det_ema050["features"],
            "ema025_features": det_ema025["features"],
        },
    }
