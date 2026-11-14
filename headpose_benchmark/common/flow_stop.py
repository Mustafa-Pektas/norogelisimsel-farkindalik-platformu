"""
Optik akışla baş hareketinin başlama / durma anı denemesi (poz modeli KULLANMADAN).

Yöntem (her kare çifti için, yalnız yüz kutusu içinde):
  1. Farneback yoğun optik akış (gri ROI kırpıntısı).
  2. Kutudaki akışın medyan vektörü = baş/kamera ÖTELEMESİ; bundan çıkarılır.
  3. Kalan "artık akış" büyüklüğünün medyanı / yüz genişliği  → dönme + yüz deformasyonu sinyali.
     (Saf öteleme medyanla silinir; dönmede yüzün iki yanı farklı hızda kayar ve artık büyür.)
  4. 5 karelik kayan medyan, çağrı öncesi sessiz dönemden robust eşik (medyan + k·MAD).
  5. Kinematik kuralla aynı yapı: 3 ardışık yüksek → hareket başladı, 5 ardışık düşük → durdu.

Eşikler mühendislik parametreleridir (klinik değildir). Sonuç, poz tabanlı dönüş bitişiyle
karşılaştırılmak üzere rapora yazılır.
"""
from typing import Any, Dict, List, Optional

import numpy as np

FLOW_STOP_CONFIG = {
    "protocol": "flow-residual-stop-v1",
    "smooth_frames": 5,
    "start_k_mad": 6.0,
    "stop_k_mad": 2.5,
    "start_confirm": 3,
    "stop_confirm": 5,
    "min_floor": 0.004,   # yüz genişliğinin %0.4'ü / kare: gürültü tabanı
    "still_ratio": 0.35,  # durgunluk: toplam hareket < çağrı öncesi medyanın %35'i
}


def _robust(values: List[float]):
    a = np.asarray([v for v in values if v is not None and np.isfinite(v)], dtype=float)
    if a.size == 0:
        return None, None
    med = float(np.median(a))
    mad = float(np.median(np.abs(a - med))) * 1.4826
    return med, mad


def compute_flow_series(video_path: str, roi: Dict[str, Any], face_boxes: Dict[int, Any],
                        crop_fn, fps: float) -> Dict[str, Any]:
    """Kare başına öteleme (px) ve artık akış (yüz genişliğine oranla) serisi."""
    import cv2
    cap = cv2.VideoCapture(video_path)
    prev = None
    rows = []
    idx = 0
    last_box = None
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        gray = cv2.cvtColor(crop_fn(frame, roi), cv2.COLOR_BGR2GRAY)
        box = face_boxes.get(idx) or last_box
        row = {"frame": idx, "time_s": round(idx / fps, 4), "translation_px": None, "residual": None, "motion": None}
        if prev is not None and box is not None:
            x1, y1, x2, y2 = [int(round(v)) for v in box]
            h, w = gray.shape
            x1, y1 = max(0, x1), max(0, y1)
            x2, y2 = min(w, x2), min(h, y2)
            if x2 - x1 >= 16 and y2 - y1 >= 16:
                flow = cv2.calcOpticalFlowFarneback(prev[y1:y2, x1:x2], gray[y1:y2, x1:x2], None,
                                                    0.5, 3, 15, 3, 5, 1.2, 0)
                v = flow.reshape(-1, 2)
                t = np.median(v, axis=0)
                res = np.linalg.norm(v - t, axis=1)
                row["translation_px"] = round(float(np.linalg.norm(t)), 3)
                row["residual"] = round(float(np.median(res)) / float(x2 - x1), 5)
                row["motion"] = round(float(np.median(np.linalg.norm(v, axis=1))) / float(x2 - x1), 5)
        if box is not None:
            last_box = box
        rows.append(row)
        prev = gray
        idx += 1
    cap.release()
    return {"rows": rows}


def detect_flow_stop(rows: List[Dict[str, Any]], call_start_s: Optional[float],
                     config: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    cfg = dict(FLOW_STOP_CONFIG, **(config or {}))
    k = int(cfg["smooth_frames"])
    raw = [r["residual"] for r in rows]
    sm: List[Optional[float]] = []
    for i in range(len(raw)):
        w = [v for v in raw[max(0, i - k + 1): i + 1] if v is not None]
        sm.append(float(np.median(w)) if len(w) >= 3 else None)
    times = [r["time_s"] for r in rows]
    cs = call_start_s if call_start_s is not None else 1.4
    base = [v for v, t in zip(sm, times) if v is not None and t < cs]
    med, mad = _robust(base)
    if med is None:
        return {"config": cfg, "status": "taban_yok", "series": sm}
    mad = max(mad, cfg["min_floor"] / 4)
    hi = max(med + cfg["start_k_mad"] * mad, med + cfg["min_floor"])
    lo = max(med + cfg["stop_k_mad"] * mad, med + cfg["min_floor"] / 2)

    movements = []
    active = None
    high, low = [], []
    for i, v in enumerate(sm):
        if v is None:
            high, low = [], []
            continue
        if active is None:
            high = high + [i] if v >= hi else []
            if len(high) >= cfg["start_confirm"]:
                active = {"start_s": times[high[0]], "start_confirmed_s": times[i]}
                high, low = [], []
        else:
            low = low + [i] if v <= lo else []
            if len(low) >= cfg["stop_confirm"]:
                active.update(stop_s=times[low[0]], stop_confirmed_s=times[i])
                movements.append(active)
                active, low = None, []
    if active is not None:
        active.update(stop_s=None, stop_confirmed_s=None)
        movements.append(active)

    post = [m for m in movements if m["start_s"] >= cs - 0.15]
    first = post[0] if post else None

    # Kural 2 — "durgunluk": toplam hareket (öteleme dahil) çağrı öncesi medyanın
    # still_ratio katının altına iner ve stop_confirm kare orada kalırsa baş durmuş sayılır.
    motion_raw = [r.get("motion") for r in rows]
    msm: List[Optional[float]] = []
    for i in range(len(motion_raw)):
        w = [v for v in motion_raw[max(0, i - k + 1): i + 1] if v is not None]
        msm.append(float(np.median(w)) if len(w) >= 3 else None)
    mbase = [v for v, t in zip(msm, times) if v is not None and t < cs]
    still = {"status": "taban_yok"}
    if mbase:
        mmed = float(np.median(mbase))
        thr = mmed * cfg["still_ratio"]
        run, still_s = [], []
        for i, v in enumerate(msm):
            if times[i] < cs:
                continue
            run = run + [i] if (v is not None and v <= thr) else []
            if len(run) >= cfg["stop_confirm"]:
                still_s.append(times[run[0]])
                break
        still = {"status": "ok" if still_s else "durgunluk_yok", "baseline_median": round(mmed, 5),
                 "threshold": round(thr, 5), "first_still_s": still_s[0] if still_s else None,
                 "series": [None if v is None else round(v, 5) for v in msm]}
    return {
        "stillness": still,
        "config": cfg,
        "status": "ok" if first else ("hareket_yok" if not movements else "cagri_sonrasi_hareket_yok"),
        "baseline_median": round(med, 5), "baseline_mad": round(mad, 5),
        "start_threshold": round(hi, 5), "stop_threshold": round(lo, 5),
        "first_movement_start_s": first["start_s"] if first else None,
        "first_movement_stop_s": first.get("stop_s") if first else None,
        "movements": movements,
        "series": [None if v is None else round(v, 5) for v in sm],
        "translation_px": [r["translation_px"] for r in rows],
    }
