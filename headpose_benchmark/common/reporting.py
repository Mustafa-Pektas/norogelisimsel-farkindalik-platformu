"""
Konsolide Raporlar: tüm modeller için tek dosyalık
  1) tum_modeller_raporu.pdf      — çok sayfalı (A3 yatay): genel tablo, çok-model bindirme, her model ayrı sayfa
  2) karsilastirma_tablosu.xlsx   — çok sayfalı Excel: genel tablo + gömülü grafik, kare-kare yan yana,
                                    her model ayrı sayfa (özet + gömülü 5 panelli grafik + kare verisi)
  3) tum_modeller_raporu.html     — tek, çevrimdışı, etkileşimli HTML (sekmeler + "Tümünü Göster",
                                    base64 gömülü grafikler)

Ayrı bas_acilari_*.png dosyası YAZILMAZ; grafikler bellekte üretilip raporlara gömülür.
Bağımlılıklar: matplotlib (PDF + grafikler), openpyxl + pillow (Excel). Eksik olan biçim atlanır ve
uyarı basılır; diğer raporlar yine üretilir.

Sütun tanımları:
  omega_deg_s      : EMA_050 (α=0.50) SO(3) dizisinin 5 aralıklı medyan açısal hızı — dönüş başlangıç
                     (≥ 45 °/s) ve bitiş (≤ 20 °/s) kararında kullanılan sinyal.
  pose_change_deg  : Çağrı öncesi medoid baş pozuna göre geodezik sapma.
  bridged          : Kare BlazeFace KP köprüsü veya 6DRepNet360 yedeğiyle üretildi.
  gaze_target      : Görselleştiricideki histerezisli hedef (toy / adult_face / none / unavailable).
"""
import base64
import html
import io
import math
import os
import re
from typing import Any, Dict, List, Optional

import numpy as np

from common.geometry import rotation_matrix_to_euler, estimate_scene_gaze_target

REFERENCE_FALLBACKS = ["6DRepNet360_Heavy_Reference", "Cascade_PnP_to_6DRepNet360"]

PDF_NAME = "tum_modeller_raporu.pdf"
XLSX_NAME = "karsilastirma_tablosu.xlsx"
HTML_NAME = "tum_modeller_raporu.html"


# --------------------------------------------------------------------------------------- veri hazırlığı
def _f(v: Any, nd: int = 2) -> Optional[float]:
    if v is None:
        return None
    try:
        fv = float(v)
    except (TypeError, ValueError):
        return None
    return round(fv, nd) if math.isfinite(fv) else None


def _euler_series(mats: List[Optional[np.ndarray]]):
    y, p, r = [], [], []
    for m in mats:
        if m is None:
            y.append(np.nan); p.append(np.nan); r.append(np.nan)
        else:
            a, b, c = rotation_matrix_to_euler(m)
            y.append(a); p.append(b); r.append(c)
    return np.array(y), np.array(p), np.array(r)


def _segments(mask: List[bool], times: np.ndarray):
    """Ardışık True bloklarını (t_başlangıç, t_bitiş) aralıklarına çevirir."""
    segs, start = [], None
    dt = float(np.median(np.diff(times))) if len(times) > 1 else 1.0 / 24.0
    for i, m in enumerate(mask):
        if m and start is None:
            start = i
        if (not m or i == len(mask) - 1) and start is not None:
            end = i if m else i - 1
            segs.append((float(times[start]), float(times[end]) + dt))
            start = None
    return segs


def prepare_model_data(entry: Dict[str, Any], video: Dict[str, Any], fps: float) -> Dict[str, Any]:
    """Tek model için kare tablosu, çizim serileri ve özet metrikleri hazırlar."""
    results = entry["results"]
    tm = entry["turn_metrics"]
    series = tm["_plot_series"]
    roi = video["roi"]
    width, height = [int(v) for v in video["resolution"].split("x")]
    targets = roi.get("targets") or []
    calls = roi.get("calls") or []
    pcs = tm.get("pose_change_summary") or {}
    base_yaw = pcs.get("baseline_yaw", -20.0)
    base_pitch = pcs.get("baseline_pitch", -20.0)

    times = np.array([float(r.metadata.get("decoder_time_s", r.frame_index / fps)) for r in results])
    raw_y, raw_p, raw_r = _euler_series(series["raw_matrices"])
    ema_y, ema_p, ema_r = _euler_series(series["ema050_matrices"])
    omega_raw = np.array([np.nan if f["speed_deg_s"] is None else f["speed_deg_s"] for f in series["raw_features"]])
    omega = np.array([np.nan if f["median_speed_deg_s"] is None else f["median_speed_deg_s"]
                      for f in series["ema050_features"]])

    frames, prev_target = [], None
    for i, r in enumerate(results):
        t = float(times[i])
        call_active = any(float(c.get("start_s", -1)) <= t <= float(c.get("end_s", -1)) for c in calls)
        eyes = r.metadata.get("eyes_center_roi")
        if eyes and len(eyes) == 2:
            ex, ey = roi["x"] + eyes[0], roi["y"] + eyes[1]
        else:
            ex, ey = roi["x"] + roi["width"] * 0.5, roi["y"] + roi["height"] * 0.45
        if r.yaw is not None and r.pitch is not None:
            g = estimate_scene_gaze_target(
                float(ex), float(ey), r.gaze_yaw if r.gaze_yaw is not None else r.yaw,
                r.gaze_pitch if r.gaze_pitch is not None else r.pitch, width, height, targets,
                pose_change_deg=r.metadata.get("pose_change_deg"), baseline_yaw=base_yaw,
                baseline_pitch=base_pitch, prev_target=prev_target,
            )
            target = g["target"]
        else:
            target = "unavailable"
        prev_target = target if target in ("toy", "adult_face") else None
        bridged = bool(r.metadata.get("used_kp_bridge") or r.metadata.get("used_6d_fallback"))
        frames.append({
            "frame": r.frame_index,
            "time_s": round(t, 4),
            "call_active": call_active,
            "valid": series["raw_matrices"][i] is not None,
            "bridged": bridged,
            "yaw": _f(r.yaw),
            "pitch": _f(r.pitch),
            "roll": _f(r.roll),
            "pose_change_deg": _f(r.metadata.get("pose_change_deg")),
            "omega_deg_s": _f(omega[i]),
            "gaze_target": target,
            "latency_ms": _f(r.latency_ms),
            "flag": r.flag,
        })

    stat = entry["stat"]
    d01 = stat["d01_first_head_turn"]
    call0 = float(calls[0]["start_s"]) if calls else None
    onset, end = d01.get("onset_s"), d01.get("end_s")
    return {
        "name": entry["name"],
        "stat": stat,
        "frames": frames,
        "times": times,
        "plot": {
            "yaw": np.array([np.nan if f["yaw"] is None else f["yaw"] for f in frames]),
            "pitch": np.array([np.nan if f["pitch"] is None else f["pitch"] for f in frames]),
            "roll": np.array([np.nan if f["roll"] is None else f["roll"] for f in frames]),
            "raw_yaw": raw_y, "raw_pitch": raw_p, "raw_roll": raw_r,
            "ema_yaw": ema_y, "ema_pitch": ema_p, "ema_roll": ema_r,
            "pose_change": np.array([np.nan if f["pose_change_deg"] is None else f["pose_change_deg"] for f in frames]),
            "omega": omega, "omega_raw": omega_raw,
            "bridged_segments": _segments([f["bridged"] for f in frames], times),
        },
        "calls": calls,
        "baseline": (base_yaw, base_pitch),
        "onset": onset, "end": end,
        "reaction_ms": round((onset - call0) * 1000.0) if (onset is not None and call0 is not None) else None,
        "duration_s": round(end - onset, 3) if (onset is not None and end is not None) else None,
        "candidates": {
            "EMA_050": tm.get("ema_050_candidates") or [],
            "EMA_025": tm.get("ema_025_candidates") or [],
            "Raw": tm.get("raw_candidates") or [],
        },
    }


def _agreement(model: Dict[str, Any], ref: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    if ref is None or ref["name"] == model["name"]:
        return {"d_onset_s": None, "d_end_s": None, "pc_mae_deg": None, "yaw_mae_deg": None,
                "text": "referans" if ref is not None else "—"}
    d_on = round(model["onset"] - ref["onset"], 3) if (model["onset"] is not None and ref["onset"] is not None) else None
    d_end = round(model["end"] - ref["end"], 3) if (model["end"] is not None and ref["end"] is not None) else None
    n = min(len(model["frames"]), len(ref["frames"]))
    a = model["plot"]["pose_change"][:n]; b = ref["plot"]["pose_change"][:n]
    ok = np.isfinite(a) & np.isfinite(b)
    pc_mae = round(float(np.mean(np.abs(a[ok] - b[ok]))), 2) if ok.any() else None
    ya = model["plot"]["yaw"][:n]; yb = ref["plot"]["yaw"][:n]
    okk = np.isfinite(ya) & np.isfinite(yb)
    yaw_mae = round(float(np.mean(np.abs(ya[okk] - yb[okk]))), 2) if okk.any() else None
    parts = []
    parts.append(f"Δbaşl {d_on:+.2f}s" if d_on is not None else "Δbaşl —")
    parts.append(f"Δbitiş {d_end:+.2f}s" if d_end is not None else "Δbitiş —")
    parts.append(f"sapma MAE {pc_mae:.1f}°" if pc_mae is not None else "sapma MAE —")
    return {"d_onset_s": d_on, "d_end_s": d_end, "pc_mae_deg": pc_mae, "yaw_mae_deg": yaw_mae,
            "text": " | ".join(parts)}


def summary_row(m: Dict[str, Any]) -> Dict[str, Any]:
    """Genel karşılaştırma tablosu satırı (sıra = sütun sırası)."""
    if m.get("unavailable"):
        return {"Model": m["name"], "Durum": "UNAVAILABLE", "Not": m["stat"].get("reason", "")}
    s = m["stat"]
    t = s["timing_warmup_excluded"]
    pcs = s.get("pose_change_summary") or {}
    ag = m["agreement"]
    return {
        "Model": m["name"],
        "Durum": s["status"],
        "Toplam Süre (s)": _f(s["total_wall_time_s"]),
        "Medyan (ms)": _f(t["median_latency_ms"]),
        "P95 (ms)": _f(t["p95_latency_ms"]),
        "Geçerli Kare": s["valid_pose_frames"],
        "Köprü Kare": int(s.get("kp_bridge_frames", 0)) + int(s.get("fallback_6d_frames", 0)),
        "Kayıp Kare": s["lost_frames_count"],
        "Taban Yaw (°)": _f(pcs.get("baseline_yaw"), 1),
        "Taban Pitch (°)": _f(pcs.get("baseline_pitch"), 1),
        "Maks Sapma (°)": _f(pcs.get("max_post_call_pose_change_deg"), 1),
        "12° Sapma (s)": _f(pcs.get("first_12deg_deviation_s"), 3),
        "Dönüş Başl. (s)": _f(m["onset"], 3),
        "Dönüş Bitiş (s)": _f(m["end"], 3),
        "Tepki Gecikmesi (ms)": m["reaction_ms"],
        "Dönüş Süresi (s)": m["duration_s"],
        "Bitiş Durumu": s["d01_first_head_turn"].get("end_status"),
        "Δ Başl. vs Ref (s)": ag["d_onset_s"],
        "Δ Bitiş vs Ref (s)": ag["d_end_s"],
        "Sapma MAE vs Ref (°)": ag["pc_mae_deg"],
    }


def model_metric_pairs(m: Dict[str, Any]) -> List[List[Any]]:
    row = summary_row(m)
    s = m["stat"]
    extra = [
        ["Optik Akış Kare", s.get("optical_flow_only_frames")],
        ["KP Köprü Kare", s.get("kp_bridge_frames", 0)],
        ["6DRepNet Yedek Kare", s.get("fallback_6d_frames", 0)],
        ["Yüz Tespit Oranı (%)", s.get("face_detection_rate_pct")],
        ["Kurulum (ms)", s.get("setup_time_ms")],
        ["Başlangıç Onayı (s)", s["d01_first_head_turn"].get("onset_confirmed_s")],
        ["Bitiş Onayı (s)", s["d01_first_head_turn"].get("end_confirmed_s")],
        ["Referans Uyumu", m["agreement"]["text"]],
        ["Yaw MAE vs Ref (°)", m["agreement"]["yaw_mae_deg"]],
    ]
    return [[k, v] for k, v in row.items() if k != "Model"] + extra


# --------------------------------------------------------------------------------------- grafikler
def _mpl():
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    return plt


def _shade_calls(ax, calls, label=True):
    for j, c in enumerate(calls):
        ax.axvspan(float(c.get("start_s", 0)), float(c.get("end_s", 0)), color="#fde68a", alpha=0.55,
                   lw=0, label=(f"Seslenme ({c.get('name', 'Call')})" if (label and j == 0) else None))
        ax.axvline(float(c.get("start_s", 0)), color="#dc2626", ls="--", lw=1.1,
                   label=("Çağrı başlangıcı" if (label and j == 0) else None))


def draw_model_panels(fig, gs_slice, m: Dict[str, Any]):
    """5 panel: Yaw, Pitch, Roll, Baştan Sapma, Açısal Hız ω (çağrı + dönüş penceresi + köprü bölgeleri)."""
    p, t = m["plot"], m["times"]
    sub = gs_slice.subgridspec(5, 1, hspace=0.12)
    axes = [fig.add_subplot(sub[i]) for i in range(5)]
    for ax in axes[1:]:
        ax.sharex(axes[0])
    specs = [
        ("Yaw (°)", p["raw_yaw"], p["ema_yaw"], p["yaw"]),
        ("Pitch (°)", p["raw_pitch"], p["ema_pitch"], p["pitch"]),
        ("Roll (°)", p["raw_roll"], p["ema_roll"], p["roll"]),
    ]
    for ax, (lbl, raw, ema, rep) in zip(axes[:3], specs):
        ax.plot(t, raw, color="#9ca3af", lw=0.9, label="Ham (SO(3))")
        ax.plot(t, ema, color="#2563eb", lw=1.8, label="EMA_050")
        ax.set_ylabel(lbl)
    axes[3].plot(t, p["pose_change"], color="#7c3aed", lw=1.8, label="Baştan sapma")
    axes[3].axhline(12.0, color="#7c3aed", ls=":", lw=1, label="12° eşiği")
    axes[3].set_ylabel("Sapma (°)")
    axes[4].plot(t, p["omega_raw"], color="#9ca3af", lw=0.8, label="ω anlık (ham)")
    axes[4].plot(t, p["omega"], color="#2563eb", lw=1.8, label="ω medyan (EMA_050)")
    axes[4].axhline(45.0, color="#dc2626", ls="--", lw=1, label="45 °/s başlangıç")
    axes[4].axhline(20.0, color="#16a34a", ls="--", lw=1, label="20 °/s bitiş")
    axes[4].set_ylabel("ω (°/s)")
    axes[4].set_xlabel("Zaman (s)")
    finite = p["omega"][np.isfinite(p["omega"])]
    if finite.size:
        axes[4].set_ylim(0, max(120.0, min(400.0, float(np.percentile(finite, 98)) * 1.25)))

    for i, ax in enumerate(axes):
        _shade_calls(ax, m["calls"], label=(i == 0))
        for k, (a, b) in enumerate(p["bridged_segments"]):
            ax.axvspan(a, b, color="#f0abfc", alpha=0.18, lw=0,
                       label=("Köprü (KP/6D) kareleri" if (i == 0 and k == 0) else None))
        if m["onset"] is not None:
            ax.axvline(m["onset"], color="#ea580c", lw=1.4, label=("Dönüş başlangıcı" if i == 0 else None))
            if m["end"] is not None:
                ax.axvspan(m["onset"], m["end"], color="#86efac", alpha=0.35, lw=0,
                           label=("Dönüş penceresi" if i == 0 else None))
                ax.axvline(m["end"], color="#15803d", lw=1.4, label=("Dönüş bitişi" if i == 0 else None))
        ax.grid(alpha=0.25)
        if i < 4:
            ax.tick_params(labelbottom=False)
        ax.legend(loc="upper left", fontsize=7, ncol=4, framealpha=0.85)
    return axes


def model_chart_png(m: Dict[str, Any], dpi: int = 110) -> bytes:
    plt = _mpl()
    fig = plt.figure(figsize=(15, 11))
    gs = fig.add_gridspec(1, 1, left=0.06, right=0.985, top=0.95, bottom=0.05)
    draw_model_panels(fig, gs[0], m)
    fig.suptitle(f"{m['name']} — Baş Açıları, Baştan Sapma ve Açısal Hız", fontsize=14, fontweight="bold")
    buf = io.BytesIO()
    fig.savefig(buf, format="png", dpi=dpi)
    plt.close(fig)
    return buf.getvalue()


def draw_overlay(fig, models: List[Dict[str, Any]], ref: Optional[Dict[str, Any]]):
    plt = _mpl()
    axes = fig.subplots(3, 1, sharex=True)
    keys = [("yaw", "Yaw (°)"), ("pitch", "Pitch (°)"), ("pose_change", "Baştan Sapma (°)")]
    cmap = plt.get_cmap("tab20")
    calls = models[0]["calls"] if models else []
    for ai, (ax, (key, lbl)) in enumerate(zip(axes, keys)):
        _shade_calls(ax, calls, label=(ai == 0))
        for i, m in enumerate(models):
            if ref is not None and m["name"] == ref["name"]:
                continue
            ax.plot(m["times"], m["plot"][key], color=cmap(i % 20), lw=1.2, alpha=0.9, label=m["name"] if ai == 0 else None)
        if ref is not None:
            ax.plot(ref["times"], ref["plot"][key], color="black", lw=2.6, label=f"REFERANS: {ref['name']}" if ai == 0 else None)
        ax.set_ylabel(lbl)
        ax.grid(alpha=0.25)
    axes[-1].set_xlabel("Zaman (s)")
    title = "Çok Modelli Bindirme Karşılaştırması"
    title += f" — referans: {ref['name']}" if ref is not None else " — 6DRepNet360 referansı bu koşuda yok"
    fig.suptitle(title, fontsize=14, fontweight="bold")
    axes[0].legend(loc="upper left", bbox_to_anchor=(1.005, 1.0), fontsize=8, framealpha=0.9)
    return axes


def overlay_png(models, ref, dpi: int = 110) -> bytes:
    plt = _mpl()
    fig = plt.figure(figsize=(16, 10))
    draw_overlay(fig, models, ref)
    fig.subplots_adjust(left=0.06, right=0.78, top=0.93, bottom=0.06, hspace=0.08)
    buf = io.BytesIO()
    fig.savefig(buf, format="png", dpi=dpi)
    plt.close(fig)
    return buf.getvalue()


# --------------------------------------------------------------------------------------- PDF
def _fmt(v: Any) -> str:
    if v is None:
        return "—"
    if isinstance(v, bool):
        return "evet" if v else "hayır"
    if isinstance(v, float):
        return f"{v:.2f}" if abs(v) < 1000 else f"{v:.0f}"
    return str(v)


def _header_two_lines(c: str) -> str:
    """Sütun başlığını en çok iki satıra böler: birim '(..)' ya da 'vs Ref' ikinci satıra gider."""
    if " vs " in c:
        a, b = c.split(" vs ", 1)
        return f"{a}\nvs {b}"
    if " (" in c:
        a, b = c.split(" (", 1)
        return f"{a}\n({b}"
    words = c.split()
    if len(words) >= 2:
        return f"{' '.join(words[:-1])}\n{words[-1]}"
    return c


def _video_lines(video: Dict[str, Any], ref_name: Optional[str]) -> List[str]:
    roi = video["roi"]
    calls = roi.get("calls") or []
    call_s = ", ".join(f"{c.get('name')} {c.get('start_s')}–{c.get('end_s')} s" for c in calls) or "çağrı tanımsız"
    return [
        f"Video: {video['filename']}  |  {video['resolution']} @ {video['fps']:.1f} FPS  |  {video['total_frames']} kare  |  ısınma: ilk {video['warmup_frames_discarded']} kare",
        f"SHA256: {video['sha256']}",
        f"ROI: x={roi['x']}, y={roi['y']}, {roi['width']}x{roi['height']} ({roi.get('source')})  |  Hedefler: {[t.get('id') for t in roi.get('targets') or []]}  |  Seslenme: {call_s}",
        f"Referans model: {ref_name or 'yok (6DRepNet360 bu koşuda çalışmadı)'}  |  Dönüş: EMA_050 SO(3), başlangıç ω ≥ 45 °/s, bitiş ω ≤ 20 °/s",
    ]


def write_pdf(path: str, video, models_all, models, ref):
    plt = _mpl()
    from matplotlib.backends.backend_pdf import PdfPages
    A3 = (16.54, 11.69)
    with PdfPages(path) as pdf:
        # Sayfa 1: genel tablo
        fig = plt.figure(figsize=A3)
        fig.suptitle("D01 İsme Tepki — Baş Pozu Model Karşılaştırması (Genel Özet)", fontsize=16, fontweight="bold", y=0.975)
        for i, line in enumerate(_video_lines(video, ref["name"] if ref else None)):
            fig.text(0.02, 0.935 - i * 0.022, line, fontsize=9.5, family="monospace")
        rows = [summary_row(m) for m in models_all]
        cols = [c for c in summary_row(models[0]).keys()] if models else ["Model", "Durum", "Not"]
        ax = fig.add_axes([0.01, 0.06, 0.98, 0.78])
        ax.axis("off")
        cell = [[_fmt(r.get(c)) for c in cols] for r in rows]
        short = [_header_two_lines(c) for c in cols]
        # Sabit oranlı sütunlar: tablo her zaman sayfa genişliğine sığar
        wide = {"Model": 3.2, "Bitiş Durumu": 2.1, "Durum": 1.5}
        # Diğer sütunlar en uzun başlık satırına göre genişler (iki satırlı başlık taşmasın)
        weights = [wide.get(c, max(1.0, max(len(x) for x in h.split("\n")) / 8.5)) for c, h in zip(cols, short)]
        col_w = [w / sum(weights) for w in weights]
        tbl = ax.table(cellText=cell, colLabels=short, loc="upper center", cellLoc="center", colWidths=col_w)
        tbl.auto_set_font_size(False)
        tbl.set_fontsize(7.0)
        tbl.scale(1.0, 2.0)
        for (r_i, c_i), c in tbl.get_celld().items():
            if r_i == 0:
                c.set_facecolor("#1f3a5f"); c.get_text().set_color("white"); c.get_text().set_fontweight("bold")
                c.set_height(c.get_height() * 2.0)
            elif r_i % 2 == 0:
                c.set_facecolor("#eef2f7")
            if c_i == 0 and r_i > 0:
                c.get_text().set_horizontalalignment("left")
                c.PAD = 0.02
        fig.text(0.02, 0.025, "Not: Saniye eşikleri simülasyon/analiz parametreleridir; bu rapor klinik tanı aracı değildir.",
                 fontsize=8.5, style="italic")
        pdf.savefig(fig); plt.close(fig)

        # Sayfa 2: bindirme
        fig = plt.figure(figsize=A3)
        draw_overlay(fig, models, ref)
        fig.subplots_adjust(left=0.05, right=0.80, top=0.93, bottom=0.06, hspace=0.08)
        pdf.savefig(fig); plt.close(fig)

        # Sayfa 3..N: her model
        for m in models:
            fig = plt.figure(figsize=A3)
            fig.suptitle(f"{m['name']}", fontsize=16, fontweight="bold", y=0.985)
            gs = fig.add_gridspec(2, 1, height_ratios=[1.0, 4.2], left=0.05, right=0.985, top=0.95, bottom=0.045, hspace=0.12)
            tax = fig.add_subplot(gs[0]); tax.axis("off")
            pairs = model_metric_pairs(m)
            per_col = math.ceil(len(pairs) / 3)
            cells = []
            for r_i in range(per_col):
                row = []
                for c_i in range(3):
                    k = c_i * per_col + r_i
                    row += [pairs[k][0], _fmt(pairs[k][1])] if k < len(pairs) else ["", ""]
                cells.append(row)
            t = tax.table(cellText=cells, loc="center", cellLoc="left", colWidths=[0.15, 0.18] * 3)
            t.auto_set_font_size(False); t.set_fontsize(8.2); t.scale(1, 1.25)
            for (r_i, c_i), c in t.get_celld().items():
                if c_i % 2 == 0:
                    c.set_facecolor("#eef2f7"); c.get_text().set_fontweight("bold")
            draw_model_panels(fig, gs[1], m)
            pdf.savefig(fig); plt.close(fig)


# --------------------------------------------------------------------------------------- Excel
def _sheet_name(name: str, used: set) -> str:
    base = re.sub(r"[\[\]\:\*\?\/\\]", "_", name)[:31]
    s, k = base, 2
    while s in used:
        suffix = f"~{k}"
        s = base[:31 - len(suffix)] + suffix
        k += 1
    used.add(s)
    return s


def write_xlsx(path: str, video, models_all, models, ref, overlay_bytes, chart_bytes):
    from openpyxl import Workbook
    from openpyxl.drawing.image import Image as XLImage
    from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
    from openpyxl.utils import get_column_letter

    head_fill = PatternFill("solid", fgColor="1F3A5F")
    sub_fill = PatternFill("solid", fgColor="DCE6F1")
    head_font = Font(bold=True, color="FFFFFF")
    thin = Side(style="thin", color="C9D3DF")
    border = Border(left=thin, right=thin, top=thin, bottom=thin)
    keep_alive = []

    def style_header(ws, row, c1, c2, fill=head_fill, font=head_font):
        for c in range(c1, c2 + 1):
            cell = ws.cell(row=row, column=c)
            cell.fill, cell.font, cell.border = fill, font, border
            cell.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)

    def put(ws, row, col, val):
        cell = ws.cell(row=row, column=col, value=val)
        cell.border = border
        if isinstance(val, float):
            cell.number_format = "0.00"
        return cell

    def autofit(ws, max_w=42, min_w=8):
        widths: Dict[int, int] = {}
        for row in ws.iter_rows():
            for c in row:
                if c.value is not None:
                    widths[c.column] = max(widths.get(c.column, 0), len(str(c.value)))
        for col, w in widths.items():
            ws.column_dimensions[get_column_letter(col)].width = max(min_w, min(max_w, w + 2))

    def add_png(ws, data: bytes, anchor: str, width_px: int):
        bio = io.BytesIO(data); keep_alive.append(bio)
        img = XLImage(bio)
        scale = width_px / img.width
        img.width, img.height = int(img.width * scale), int(img.height * scale)
        ws.add_image(img, anchor)
        return img.height

    wb = Workbook()
    used: set = set()

    # Sayfa 1: genel kıyaslama
    ws = wb.active
    ws.title = _sheet_name("Genel_Kiyaslama", used)
    for i, line in enumerate(_video_lines(video, ref["name"] if ref else None), start=1):
        ws.cell(row=i, column=1, value=line).font = Font(italic=(i > 1), bold=(i == 1))
    hdr_row = 6
    cols = list(summary_row(models[0]).keys()) if models else ["Model", "Durum", "Not"]
    for j, c in enumerate(cols, start=1):
        ws.cell(row=hdr_row, column=j, value=c)
    style_header(ws, hdr_row, 1, len(cols))
    ws.row_dimensions[hdr_row].height = 32
    for i, m in enumerate(models_all, start=hdr_row + 1):
        r = summary_row(m)
        for j, c in enumerate(cols, start=1):
            put(ws, i, j, r.get(c))
    autofit(ws, max_w=30)
    ws.column_dimensions["A"].width = 36
    ws.freeze_panes = ws.cell(row=hdr_row + 1, column=2)
    if overlay_bytes:
        add_png(ws, overlay_bytes, f"A{hdr_row + len(models_all) + 3}", 1500)

    # Sayfa 2: kare-kare yan yana
    ws2 = wb.create_sheet(_sheet_name("Tum_Modeller_Yan_Yana", used))
    per = ["yaw", "pitch", "roll", "pose_change_deg", "omega_deg_s", "gaze_target", "bridged"]
    base_cols = ["frame", "time_s", "call_active"]
    for j, c in enumerate(base_cols, start=1):
        ws2.cell(row=2, column=j, value=c)
        ws2.merge_cells(start_row=1, start_column=j, end_row=1, end_column=j)
    col = len(base_cols) + 1
    for m in models:
        ws2.cell(row=1, column=col, value=m["name"])
        ws2.merge_cells(start_row=1, start_column=col, end_row=1, end_column=col + len(per) - 1)
        for k, c in enumerate(per):
            ws2.cell(row=2, column=col + k, value=c)
        style_header(ws2, 1, col, col + len(per) - 1)
        col += len(per)
    style_header(ws2, 1, 1, len(base_cols))
    style_header(ws2, 2, 1, col - 1, fill=sub_fill, font=Font(bold=True, color="1F3A5F"))
    n = max((len(m["frames"]) for m in models), default=0)
    ref_frames = models[0]["frames"] if models else []
    for i in range(n):
        r = 3 + i
        f0 = ref_frames[i] if i < len(ref_frames) else {}
        put(ws2, r, 1, f0.get("frame")); put(ws2, r, 2, f0.get("time_s")); put(ws2, r, 3, f0.get("call_active"))
        c = len(base_cols) + 1
        for m in models:
            f = m["frames"][i] if i < len(m["frames"]) else {}
            for k, key in enumerate(per):
                put(ws2, r, c + k, f.get(key))
            c += len(per)
    for j in range(1, col):
        ws2.column_dimensions[get_column_letter(j)].width = 11
    ws2.freeze_panes = "D3"

    # Sayfa 3..N: her model
    frame_cols = ["frame", "time_s", "valid", "bridged", "yaw", "pitch", "roll",
                  "pose_change_deg", "omega_deg_s", "gaze_target", "latency_ms", "flag"]
    for m in models:
        wsm = wb.create_sheet(_sheet_name(m["name"], used))
        wsm.cell(row=1, column=1, value=m["name"]).font = Font(bold=True, size=14, color="1F3A5F")
        wsm.cell(row=2, column=1, value="Metrik"); wsm.cell(row=2, column=2, value="Değer")
        style_header(wsm, 2, 1, 2)
        pairs = model_metric_pairs(m)
        for i, (k, v) in enumerate(pairs, start=3):
            put(wsm, i, 1, k).font = Font(bold=True)
            put(wsm, i, 2, v)
        row = 3 + len(pairs) + 1
        wsm.cell(row=row, column=1, value="Dönüş adayları (başlangıç → bitiş, durum)").font = Font(bold=True)
        for kind, cands in m["candidates"].items():
            row += 1
            txt = "; ".join(f"{c.get('start_s')}→{c.get('end_s')} ({c.get('end_status')})" for c in cands) or "—"
            put(wsm, row, 1, kind); put(wsm, row, 2, txt)
        img_h = add_png(wsm, chart_bytes[m["name"]], "D2", 1100) if m["name"] in chart_bytes else 0
        data_row = max(row + 3, 2 + int(img_h / 20) + 3)
        wsm.cell(row=data_row - 1, column=1, value="Kare kare veri").font = Font(bold=True, size=12, color="1F3A5F")
        for j, c in enumerate(frame_cols, start=1):
            wsm.cell(row=data_row, column=j, value=c)
        style_header(wsm, data_row, 1, len(frame_cols))
        for i, f in enumerate(m["frames"], start=data_row + 1):
            for j, c in enumerate(frame_cols, start=1):
                put(wsm, i, j, f.get(c))
        wsm.column_dimensions["A"].width = 26
        wsm.column_dimensions["B"].width = 34
        for j in range(3, len(frame_cols) + 1):
            wsm.column_dimensions[get_column_letter(j)].width = 13
    wb.save(path)


# --------------------------------------------------------------------------------------- HTML
_CSS = """
:root{--ink:#1b2430;--muted:#5b6675;--line:#d8dee8;--head:#1f3a5f;--soft:#eef2f7;--accent:#2563eb;--bg:#f7f9fc;--card:#fff}
*{box-sizing:border-box}body{margin:0;font:14px/1.45 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;color:var(--ink);background:var(--bg)}
header{padding:20px 24px 8px}h1{margin:0 0 6px;font-size:22px}h2{margin:0 0 12px;font-size:18px}h3{margin:18px 0 8px;font-size:15px}
.meta{color:var(--muted);font:12px/1.5 ui-monospace,Consolas,monospace;white-space:pre-wrap}
nav{position:sticky;top:0;z-index:5;background:var(--bg);padding:10px 24px;border-bottom:1px solid var(--line);display:flex;flex-wrap:wrap;gap:6px}
nav button{border:1px solid var(--line);background:var(--card);color:var(--ink);padding:6px 10px;border-radius:6px;cursor:pointer;font-size:12.5px}
nav button.active{background:var(--head);color:#fff;border-color:var(--head)}
main{padding:16px 24px 40px}.card{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:18px;margin-bottom:22px}
.tw{overflow-x:auto}table{border-collapse:collapse;width:100%;font-size:12.5px}th,td{border:1px solid var(--line);padding:5px 7px;text-align:center;white-space:nowrap}
th{background:var(--head);color:#fff;position:sticky;top:0}tbody tr:nth-child(even){background:var(--soft)}td.k{text-align:left;font-weight:600;background:var(--soft)}
td.l{text-align:left}img{max-width:100%;height:auto;border:1px solid var(--line);border-radius:6px;display:block}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:14px}.note{color:var(--muted);font-size:12px;font-style:italic}
"""

_JS = """
function show(id){document.querySelectorAll('section.card').forEach(s=>{s.hidden=!(id==='__all__'||s.id===id||s.id==='genel')});
document.querySelectorAll('nav button').forEach(b=>b.classList.toggle('active',b.dataset.t===id));
if(id!=='__all__'&&id!=='genel'){const el=document.getElementById(id);if(el)el.scrollIntoView({behavior:'smooth',block:'start'})}}
document.querySelectorAll('nav button').forEach(b=>b.addEventListener('click',()=>show(b.dataset.t)));show('__all__');
"""


def _h(v: Any) -> str:
    return html.escape(_fmt(v))


def write_html(path: str, video, models_all, models, ref, overlay_bytes, chart_bytes):
    def b64(data: bytes) -> str:
        return "data:image/png;base64," + base64.b64encode(data).decode("ascii")

    cols = list(summary_row(models[0]).keys()) if models else ["Model", "Durum", "Not"]
    rows_html = "".join(
        "<tr>" + "".join(f"<td class='{'l' if c == 'Model' else ''}'>{_h(summary_row(m).get(c))}</td>" for c in cols) + "</tr>"
        for m in models_all
    )
    ids = {m["name"]: "m_" + re.sub(r"[^A-Za-z0-9_]", "_", m["name"]) for m in models}
    nav = ["<button data-t='__all__'>Tümünü Göster</button>", "<button data-t='genel'>Genel Kıyaslama</button>"]
    nav += [f"<button data-t='{ids[m['name']]}'>{html.escape(m['name'])}</button>" for m in models]

    cards = []
    for m in models:
        pairs = model_metric_pairs(m)
        half = math.ceil(len(pairs) / 2)
        mt = "".join(
            "<tr>" + "".join(
                f"<td class='k'>{html.escape(str(p[0]))}</td><td>{_h(p[1])}</td>" for p in pr if p
            ) + "</tr>"
            for pr in zip(pairs[:half], pairs[half:] + [None] * (2 * half - len(pairs)))
        )
        cand_rows = "".join(
            f"<tr><td class='k'>{kind}</td><td>{html.escape(c.get('candidate_id', ''))}</td><td>{_h(c.get('start_s'))}</td>"
            f"<td>{_h(c.get('first_high_evidence_s'))}</td><td>{_h(c.get('end_s'))}</td><td>{html.escape(str(c.get('end_status')))}</td></tr>"
            for kind, cands in m["candidates"].items() for c in cands
        ) or "<tr><td colspan='6'>Aday yok</td></tr>"
        chart = f"<img alt='{html.escape(m['name'])} grafiği' src='{b64(chart_bytes[m['name']])}'>" if m["name"] in chart_bytes else "<p class='note'>Grafik üretilemedi (matplotlib yok).</p>"
        cards.append(
            f"<section class='card' id='{ids[m['name']]}'><h2>{html.escape(m['name'])}</h2>"
            f"<div class='tw'><table><tbody>{mt}</tbody></table></div>"
            f"<h3>Dönüş adayları</h3><div class='tw'><table><thead><tr><th>Tür</th><th>Aday</th><th>Başlangıç (s)</th>"
            f"<th>İlk yüksek hız (s)</th><th>Bitiş (s)</th><th>Bitiş durumu</th></tr></thead><tbody>{cand_rows}</tbody></table></div>"
            f"<h3>Baş açıları, baştan sapma ve açısal hız</h3>{chart}</section>"
        )

    overlay = f"<img alt='Çok modelli bindirme grafiği' src='{b64(overlay_bytes)}'>" if overlay_bytes else ""
    doc = f"""<!doctype html><html lang="tr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Baş Pozu Model Raporu — {html.escape(video['filename'])}</title><style>{_CSS}</style></head><body>
<header><h1>D01 İsme Tepki — Baş Pozu Model Karşılaştırması</h1><div class="meta">{html.escape(chr(10).join(_video_lines(video, ref['name'] if ref else None)))}</div>
<p class="note">Saniye eşikleri simülasyon/analiz parametreleridir; bu rapor klinik tanı aracı değildir.</p></header>
<nav>{''.join(nav)}</nav><main>
<section class="card" id="genel"><h2>Genel Kıyaslama</h2><div class="tw"><table><thead><tr>{''.join(f'<th>{html.escape(c)}</th>' for c in cols)}</tr></thead>
<tbody>{rows_html}</tbody></table></div><h3>Çok modelli bindirme</h3>{overlay}</section>
{''.join(cards)}</main><script>{_JS}</script></body></html>"""
    with open(path, "w", encoding="utf-8") as f:
        f.write(doc)


# --------------------------------------------------------------------------------------- giriş noktası
def write_reports(output_dir: str, summary: Dict[str, Any], entries: List[Dict[str, Any]], fps: float,
                  reference_name: Optional[str] = None) -> Dict[str, Optional[str]]:
    """Tüm raporları üretir; üretilen dosya yollarını döner (atlananlar None)."""
    os.makedirs(output_dir, exist_ok=True)
    video = summary["video"]
    models, models_all = [], []
    for e in entries:
        if e.get("results") is None:
            models_all.append({"name": e["name"], "stat": e["stat"], "unavailable": True})
            continue
        m = prepare_model_data(e, video, fps)
        models.append(m)
        models_all.append(m)

    ref = None
    for cand in ([reference_name] if reference_name else []) + REFERENCE_FALLBACKS:
        ref = next((m for m in models if m["name"] == cand), None)
        if ref is not None:
            break
    for m in models:
        m["agreement"] = _agreement(m, ref)

    out: Dict[str, Optional[str]] = {"pdf": None, "xlsx": None, "html": None}
    overlay_bytes, chart_bytes = None, {}
    try:
        _mpl()
        overlay_bytes = overlay_png(models, ref) if models else None
        chart_bytes = {m["name"]: model_chart_png(m) for m in models}
        path = os.path.join(output_dir, PDF_NAME)
        write_pdf(path, video, models_all, models, ref)
        out["pdf"] = path
    except ImportError as exc:
        print(f"    [RAPOR UYARI] matplotlib yok; PDF ve grafikler atlandı ({exc})", flush=True)

    try:
        path = os.path.join(output_dir, XLSX_NAME)
        write_xlsx(path, video, models_all, models, ref, overlay_bytes, chart_bytes)
        out["xlsx"] = path
    except ImportError as exc:
        print(f"    [RAPOR UYARI] openpyxl/pillow yok; Excel atlandı ({exc})", flush=True)

    path = os.path.join(output_dir, HTML_NAME)
    write_html(path, video, models_all, models, ref, overlay_bytes, chart_bytes)
    out["html"] = path

    # Eski koşulardan kalan ayrık grafikleri temizle (artık raporlara gömülü)
    for fn in os.listdir(output_dir):
        if fn.startswith("bas_acilari_") and fn.endswith(".png"):
            try:
                os.remove(os.path.join(output_dir, fn))
            except OSError:
                pass
    return out
