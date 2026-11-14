"""
D01 Baş Hareketi Yöntem Karşılaştırma Raporu (birden çok video, tek rapor)

Girdi : her video için benchmark_runner.py çıktısı (benchmark_results.json)
Çıktı : D01_yontem_karsilastirma.html / .pdf / .xlsx

İçerik
  1. Hız ve maliyet       — kare başı süre, 3,5 dk video için tahmini süre, aylık kapasite, video başı maliyet
  2. Doğruluk             — 6DRepNet360 referansına göre dönüş başlangıç/bitiş farkı, sapma MAE, kayıp kare
  3. Olay durum makinesi  — Baktı / Durdu / Bakış süresi / Geri döndü (her model, her video)
  4. Optik akış denemesi  — poz modeli olmadan hareket başlama/durma anı; poz tabanlı sonuçla kıyas
Eşikler mühendislik parametreleridir; rapor klinik tanı aracı değildir.

Kullanım:
  python karsilastirma_raporu.py --run Deniz=outputs/deniz/benchmark_results.json \
      --run Video2=outputs/video2/benchmark_results.json --out-dir rapor [--aylik-ucret-tl 500]
"""
import argparse
import base64
import html
import io
import json
import math
import os
from typing import Any, Dict, List, Optional

import numpy as np

REFERENCE_ORDER = ["6DRepNet360_Heavy_Reference", "Cascade_PnP_to_6DRepNet360"]
LONG_VIDEO_FRAMES = 210 * 24          # 3,5 dk @ 24 FPS (pilot üst sınırı)
SECONDS_PER_MONTH = 30 * 24 * 3600
STATE_COLORS = {"BEKLEME": "#e5e7eb", "BAKIYOR": "#fdba74", "DURDU": "#93c5fd",
                "GERI_DONUYOR": "#c4b5fd", "GERI_DONDU": "#86efac", "BELIRSIZ": "#fca5a5"}
STATE_TR = {"BEKLEME": "Bekleme", "BAKIYOR": "Baktı (dönüyor)", "DURDU": "Durdu (bakıyor)",
            "GERI_DONUYOR": "Geri dönüyor", "GERI_DONDU": "Geri döndü", "BELIRSIZ": "Belirsiz"}
DURUM_TR = {"geri_dondu": "baktı → durdu → geri döndü", "yavas_geri_donus": "baktı → durdu → yavaş geri döndü",
            "geri_dondu_bitis_belirsiz": "geri dönüş başladı, bitişi yok", "geri_donus_yok": "baktı → durdu (dönmedi)",
            "durma_gozlenemedi": "baktı, durma gözlenemedi", "kucuk_hareket": "küçük hareket (<12°)",
            "bakis_yok": "çağrı sonrası hareket yok"}


# ----------------------------------------------------------------------------------------- yardımcılar
def fnum(v, nd=2):
    if v is None:
        return None
    try:
        f = float(v)
    except (TypeError, ValueError):
        return None
    return round(f, nd) if math.isfinite(f) else None


def fmt(v, nd=2, unit=""):
    if v is None:
        return "—"
    if isinstance(v, (int, float)):
        return f"{v:.{nd}f}{unit}" if isinstance(v, float) else f"{v}{unit}"
    return str(v)


def signed(v, nd=2, unit=" s"):
    return "—" if v is None else f"{v:+.{nd}f}{unit}"


def load_runs(pairs: List[str]) -> List[Dict[str, Any]]:
    runs = []
    for p in pairs:
        label, path = p.split("=", 1)
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        models = {k: v for k, v in data["models"].items() if v.get("status") == "COMPLETED"}
        ref = next((models[n] | {"name": n} for n in REFERENCE_ORDER if n in models), None)
        runs.append({"label": label, "data": data, "models": models, "ref": ref,
                     "unavailable": [k for k, v in data["models"].items() if v.get("status") != "COMPLETED"]})
    return runs


def series_mae(a: Dict[str, Any], b: Dict[str, Any]) -> Optional[float]:
    sa, sb = (a.get("series") or {}).get("pose_change"), (b.get("series") or {}).get("pose_change")
    if not sa or not sb:
        return None
    n = min(len(sa), len(sb))
    d = [abs(x - y) for x, y in zip(sa[:n], sb[:n]) if x is not None and y is not None]
    return round(float(np.mean(d)), 2) if d else None


def delta(a, b):
    return None if a is None or b is None else round(float(a) - float(b), 3)


# ----------------------------------------------------------------------------------------- tablolar
def speed_cost_rows(runs, monthly_price: Optional[float]):
    names = sorted({n for r in runs for n in r["models"]})
    rows = []
    for n in names:
        per_frame, setup = [], []
        for r in runs:
            m = r["models"].get(n)
            if not m:
                continue
            per_frame.append(m["total_wall_time_s"] / max(1, m["total_frames_processed"]))
            setup.append(m.get("setup_time_ms", 0) / 1000.0)
        if not per_frame:
            continue
        s_per_frame = float(np.mean(per_frame))
        median_ms = float(np.mean([r["models"][n]["timing_warmup_excluded"]["median_latency_ms"] for r in runs if n in r["models"]]))
        long_s = s_per_frame * LONG_VIDEO_FRAMES + float(np.mean(setup))
        per_month = SECONDS_PER_MONTH / long_s
        rows.append({
            "Model": n,
            "Medyan (ms/kare)": round(median_ms, 1),
            "Uçtan uca (ms/kare)": round(s_per_frame * 1000, 1),
            "Gerçek zamanlı (≤41,7 ms)": "evet" if s_per_frame * 1000 <= 1000 / 24 else "hayır",
            "3,5 dk video (dk)": round(long_s / 60, 1),
            "15 dk sınırına sığar": "evet" if long_s <= 900 else "hayır",
            "Aylık kapasite (3,5 dk video)": int(per_month),
            "Video başı maliyet (TL)": None if monthly_price is None else round(monthly_price / per_month, 3),
        })
    rows.sort(key=lambda r: r["Uçtan uca (ms/kare)"])
    return rows


def accuracy_rows(run):
    ref = run["ref"]
    rows = []
    for n, m in sorted(run["models"].items(), key=lambda kv: kv[1]["timing_warmup_excluded"]["median_latency_ms"]):
        d = m["d01_first_head_turn"]
        rd = ref["d01_first_head_turn"] if ref else {}
        is_ref = ref is not None and n == ref["name"]
        rows.append({
            "Model": n + (" (REFERANS)" if is_ref else ""),
            "Geçerli / Kayıp kare": f"{m['valid_pose_frames']} / {m['lost_frames_count']}",
            "Dönüş başl. (s)": fnum(d.get("onset_s"), 3),
            "Dönüş bitiş (s)": fnum(d.get("end_s"), 3),
            "Δ başl. vs ref": None if is_ref else delta(d.get("onset_s"), rd.get("onset_s")),
            "Δ bitiş vs ref": None if is_ref else delta(d.get("end_s"), rd.get("end_s")),
            "Sapma MAE vs ref (°)": None if (is_ref or not ref) else series_mae(m, ref),
            "Maks sapma (°)": fnum((m.get("pose_change_summary") or {}).get("max_post_call_pose_change_deg"), 1),
            "Bitiş durumu": d.get("end_status"),
        })
    return rows


def event_rows(run):
    ref = run["ref"]
    re_ = (ref or {}).get("d01_events") or {}
    rows = []
    for n, m in sorted(run["models"].items(), key=lambda kv: kv[1]["timing_warmup_excluded"]["median_latency_ms"]):
        e = m.get("d01_events") or {}
        is_ref = ref is not None and n == ref["name"]
        rows.append({
            "Model": n + (" (REFERANS)" if is_ref else ""),
            "Baktı (s)": fnum(e.get("bakti_s"), 3),
            "Durdu (s)": fnum(e.get("durdu_s"), 3),
            "Bakış süresi (s)": fnum(e.get("bakis_suresi_s"), 2),
            "Geri dönüş başl. (s)": fnum(e.get("geri_donus_baslangic_s"), 3),
            "Geri döndü (s)": fnum(e.get("geri_dondu_s"), 3),
            "Zirve sapma (°)": fnum(e.get("zirve_sapma_deg"), 1),
            "Sonuç": DURUM_TR.get(e.get("durum"), e.get("durum")),
            "Δ geri döndü vs ref": None if is_ref else delta(e.get("geri_dondu_s"), re_.get("geri_dondu_s")),
        })
    return rows


def flow_rows(runs):
    rows = []
    for r in runs:
        f = r["data"].get("optical_flow_stop") or {}
        st = f.get("stillness") or {}
        rd = (r["ref"] or {}).get("d01_first_head_turn") or {}
        rows.append({
            "Video": r["label"],
            "Poz (ref) başl. → bitiş": f"{fmt(fnum(rd.get('onset_s'), 2))} → {fmt(fnum(rd.get('end_s'), 2))} s",
            "Akış artık kuralı başl. → durma": f"{fmt(fnum(f.get('first_movement_start_s'), 2))} → {fmt(fnum(f.get('first_movement_stop_s'), 2))} s",
            "Δ durma (artık) vs ref": delta(f.get("first_movement_stop_s"), rd.get("end_s")),
            "Akış durgunluk kuralı (s)": fnum(st.get("first_still_s"), 2),
            "Δ durgunluk vs ref": delta(st.get("first_still_s"), rd.get("end_s")),
            "Akış süresi (s)": f.get("wall_time_s"),
            "Sonuç": f.get("status"),
        })
    return rows


# ----------------------------------------------------------------------------------------- grafikler
def _plt():
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    return plt


def png(fig) -> bytes:
    buf = io.BytesIO()
    fig.savefig(buf, format="png", dpi=110, bbox_inches="tight")
    _plt().close(fig)
    return buf.getvalue()


def fig_speed(rows):
    plt = _plt()
    fig, ax = plt.subplots(figsize=(11, 0.42 * len(rows) + 1.4))
    names = [r["Model"] for r in rows]
    vals = [r["Uçtan uca (ms/kare)"] for r in rows]
    colors = ["#16a34a" if r["15 dk sınırına sığar"] == "evet" else "#dc2626" for r in rows]
    ax.barh(names, vals, color=colors)
    ax.set_xscale("log")
    ax.invert_yaxis()
    ax.axvline(1000 / 24, color="#2563eb", ls="--", lw=1, label="Gerçek zamanlı (41,7 ms/kare)")
    ax.axvline(900 / LONG_VIDEO_FRAMES * 1000, color="#dc2626", ls=":", lw=1.2,
               label="3,5 dk video 15 dk'da biter (178 ms/kare)")
    for y, v in enumerate(vals):
        ax.text(v * 1.05, y, f"{v:.0f} ms", va="center", fontsize=8)
    ax.set_xlabel("Uçtan uca süre / kare (ms, log ölçek) — sunucu")
    ax.legend(loc="lower right", fontsize=8)
    ax.grid(axis="x", alpha=0.3)
    ax.set_title("Hız: kare başına uçtan uca süre (yeşil = 3,5 dk video 15 dk içinde biter)", fontsize=11)
    return png(fig)


def fig_events(run):
    """Referans modelin sapma + açısal hız serisi; durum makinesi bölgeleri renkli."""
    plt = _plt()
    ref = run["ref"] or next(iter(run["models"].values()))
    ser = ref.get("series") or {}
    t = np.array(ser.get("t") or [], dtype=float)
    pc = np.array([np.nan if v is None else v for v in ser.get("pose_change") or []], dtype=float)
    om = np.array([np.nan if v is None else v for v in ser.get("omega") or []], dtype=float)
    calls = (run["data"]["video"]["roi"].get("calls") or [])
    fig, (a1, a2) = plt.subplots(2, 1, figsize=(12, 5.6), sharex=True)
    for ax in (a1, a2):
        seen = set()
        for state, s0, s1 in ref.get("d01_event_segments") or []:
            ax.axvspan(s0, s1, color=STATE_COLORS.get(state, "#eee"), alpha=0.55, lw=0,
                       label=None if state in seen else STATE_TR.get(state, state))
            seen.add(state)
        for c in calls:
            ax.axvline(float(c["start_s"]), color="#b91c1c", ls="--", lw=1.1)
        ax.grid(alpha=0.25)
    a1.plot(t, pc, color="#7c3aed", lw=1.8, label="Başlangıç pozundan sapma")
    ev = ref.get("d01_events") or {}
    if ev.get("geri_donus_esigi_deg"):
        a1.axhline(ev["geri_donus_esigi_deg"], color="#16a34a", ls=":", lw=1.2, label="Geri dönüş eşiği")
    a1.axhline(12, color="#ea580c", ls=":", lw=1, label="12° bakış eşiği")
    a1.set_ylabel("Sapma (°)")
    a1.legend(loc="upper left", fontsize=7.5, ncol=4)
    a2.plot(t, om, color="#2563eb", lw=1.6, label="Açısal hız ω (EMA_050 medyan)")
    a2.axhline(45, color="#dc2626", ls="--", lw=1, label="45 °/s başlangıç")
    a2.axhline(20, color="#16a34a", ls="--", lw=1, label="20 °/s durma")
    a2.set_ylabel("ω (°/s)")
    a2.set_xlabel("Zaman (s)  — kırmızı kesikli: çağrı başlangıcı")
    a2.legend(loc="upper left", fontsize=7.5, ncol=3)
    a1.set_title(f"{run['label']} — olay durum makinesi ({ref.get('name', '')})", fontsize=11)
    return png(fig)


def fig_flow(run):
    plt = _plt()
    f = run["data"].get("optical_flow_stop") or {}
    st = f.get("stillness") or {}
    n = len(f.get("series") or [])
    t = np.arange(n) / float(run["data"]["video"]["fps"] or 24)
    rd = (run["ref"] or {}).get("d01_first_head_turn") or {}
    fig, (a1, a2) = plt.subplots(2, 1, figsize=(12, 5.4), sharex=True)
    res = np.array([np.nan if v is None else v for v in f.get("series") or []], dtype=float) * 100
    mot = np.array([np.nan if v is None else v for v in st.get("series") or [np.nan] * n], dtype=float) * 100
    a1.plot(t, res, color="#0891b2", lw=1.6, label="Artık akış (öteleme çıkarılmış), % yüz genişliği/kare")
    if f.get("start_threshold"):
        a1.axhline(f["start_threshold"] * 100, color="#dc2626", ls="--", lw=1, label="başlama eşiği")
        a1.axhline(f["stop_threshold"] * 100, color="#16a34a", ls="--", lw=1, label="durma eşiği")
    a2.plot(t, mot, color="#475569", lw=1.6, label="Toplam akış, % yüz genişliği/kare")
    if st.get("threshold"):
        a2.axhline(st["threshold"] * 100, color="#16a34a", ls="--", lw=1, label="durgunluk eşiği")
    for ax in (a1, a2):
        if rd.get("onset_s") is not None and rd.get("end_s") is not None:
            ax.axvspan(rd["onset_s"], rd["end_s"], color="#fdba74", alpha=0.45, lw=0, label="Poz (ref) dönüş penceresi")
        for c in run["data"]["video"]["roi"].get("calls") or []:
            ax.axvline(float(c["start_s"]), color="#b91c1c", ls="--", lw=1.1)
        ax.grid(alpha=0.25)
    if f.get("first_movement_stop_s") is not None:
        a1.axvline(f["first_movement_stop_s"], color="#0891b2", lw=2, label="akış: durma")
    if st.get("first_still_s") is not None:
        a2.axvline(st["first_still_s"], color="#475569", lw=2, label="akış: durgunluk")
    a1.legend(loc="upper right", fontsize=7.5)
    a2.legend(loc="upper right", fontsize=7.5)
    a2.set_xlabel("Zaman (s)")
    a1.set_title(f"{run['label']} — optik akışla hareket/durma denemesi", fontsize=11)
    return png(fig)


# ----------------------------------------------------------------------------------------- metin
def findings(runs, speed_rows):
    out = []
    ok_rows = [r for r in speed_rows if r["15 dk sınırına sığar"] == "evet"]
    ref_name = next((r["ref"]["name"] for r in runs if r["ref"]), None)
    ref_row = next((r for r in speed_rows if r["Model"] == ref_name), None)
    if ref_row:
        out.append(f"Referans {ref_name} sunucuda {ref_row['Uçtan uca (ms/kare)']:.0f} ms/kare çalışıyor; "
                   f"3,5 dk'lık bir video ≈ {ref_row['3,5 dk video (dk)']:.0f} dk sürer ({ref_row['15 dk sınırına sığar']}: 15 dk sınırı).")
    # Doğruluk: referansa en yakın hızlı modeller
    good = []
    for r in speed_rows:
        n = r["Model"]
        if n == ref_name:
            continue
        ds = []
        for run in runs:
            m, ref = run["models"].get(n), run["ref"]
            if not m or not ref:
                continue
            for k in ("onset_s", "end_s"):
                d = delta(m["d01_first_head_turn"].get(k), ref["d01_first_head_turn"].get(k))
                ds.append(abs(d) if d is not None else 9.9)
            ds.append(0 if m["lost_frames_count"] == 0 else 9.9)
        if ds and max(ds) <= 0.15:
            good.append((r["Uçtan uca (ms/kare)"], n))
    if good:
        best = sorted(good)[0]
        out.append(f"Her iki videoda referansla dönüş başlangıç/bitişi ±0,15 s içinde, kayıpsız ve en hızlı model: "
                   f"{best[1]} ({best[0]:.0f} ms/kare). Uyan diğer modeller: {', '.join(n for _, n in sorted(good)[1:]) or '—'}.")
    out.append(f"15 dk sınırına 3,5 dk'lık videoyu sığdıran model sayısı: {len(ok_rows)}/{len(speed_rows)}.")
    for run in runs:
        e = ((run["ref"] or {}).get("d01_events") or {})
        if e:
            out.append(f"{run['label']}: referans modelde {DURUM_TR.get(e.get('durum'), e.get('durum'))} — baktı {fmt(fnum(e.get('bakti_s'), 2))} s, "
                       f"durdu {fmt(fnum(e.get('durdu_s'), 2))} s, bakış süresi {fmt(fnum(e.get('bakis_suresi_s'), 2))} s, "
                       f"geri döndü {fmt(fnum(e.get('geri_dondu_s'), 2))} s.")
    return out


FLOW_TEXT = (
    "Optik akış, baş pozunu hesaplamadan yalnız piksel hareketinden 'baş durdu mu' sorusunu cevaplamak için denendi. "
    "İki kural sınandı: (1) artık akış — yüz kutusundaki akıştan medyan öteleme çıkarılır, kalan düzensiz hareket dönmeyi "
    "temsil eder; (2) durgunluk — toplam akış çağrı öncesi düzeyin %35'inin altına inince baş durmuş sayılır. "
    "Bulgu: kurallar videolar arasında tutarlı değil. Hızlı bir dönüşte yüz kutusu dönüşü takip ettiği ve profilde doku "
    "azaldığı için akış dönüşü her zaman tepe olarak göstermiyor; çağrı öncesi çocuğun kıpırdanması (öteleme 2–4 px/kare) "
    "taban düzeyini yükseltiyor. Bu nedenle optik akış tek başına 'durdu' anını güvenilir vermiyor; poz tabanlı açısal hız "
    "(ω ≤ 20 °/s) kuralı her iki videoda da tutarlı sonuç verdi. Optik akış, poz modelinin yüz kaybettiği kısa boşlukları "
    "köprülemek için yardımcı sinyal olarak kalmalı."
)

FSM_TEXT = (
    "Durum makinesi her kareyi şu durumlardan birine koyar: BEKLEME → BAKTI (çağrıdan sonraki ilk baş hareketi; "
    "başlangıç ω ≥ 45 °/s, zirve sapma ≥ 12°) → DURDU (ω ≤ 20 °/s; baş yeni yönde tutuluyor, bakış süresi burada sayılır) "
    "→ GERİ DÖNÜYOR (sonraki hareket) → GERİ DÖNDÜ (sapma, zirvenin %35'inin veya 6°'nin altına iner). "
    "Hız eşiğini aşmadan yavaşça dönen baş 'yavaş geri dönüş' olarak ayrıca işaretlenir; klip bitene kadar dönmezse "
    "bakış süresi alt sınır olarak verilir. Tüm eşikler mühendislik parametresidir ve uzman kalibrasyonu bekler."
)

COST_TEXT = (
    "Maliyet, ölçülen sunucu süresinden hesaplanır: 3,5 dk'lık video (5040 kare) için süre = uçtan uca ms/kare × 5040 + "
    "model yükleme. Sunucu aynı anda tek analiz çalıştırdığından aylık kapasite = 30 gün / video süresi; video başı maliyet "
    "= aylık sunucu ücreti / aylık kapasite. Ölçüm 4 vCPU (Xeon E5-2699 v4, GPU yok) VDS üzerinde yapıldı; aynı VDS'in "
    "hızı günden güne 2–3 kat değişebildiği önceki ölçümlerde görüldü."
)


# ----------------------------------------------------------------------------------------- yazıcılar
def write_xlsx(path, sections):
    from openpyxl import Workbook
    from openpyxl.styles import Alignment, Font, PatternFill
    from openpyxl.utils import get_column_letter
    wb = Workbook()
    wb.remove(wb.active)
    for title, rows in sections:
        ws = wb.create_sheet(title[:31])
        if not rows:
            continue
        cols = list(rows[0].keys())
        for j, c in enumerate(cols, 1):
            cell = ws.cell(row=1, column=j, value=c)
            cell.font = Font(bold=True, color="FFFFFF")
            cell.fill = PatternFill("solid", fgColor="1F3A5F")
            cell.alignment = Alignment(wrap_text=True, horizontal="center")
        for i, r in enumerate(rows, 2):
            for j, c in enumerate(cols, 1):
                ws.cell(row=i, column=j, value=r.get(c))
        for j, c in enumerate(cols, 1):
            w = max(len(str(c)), *(len(str(r.get(c) or "")) for r in rows))
            ws.column_dimensions[get_column_letter(j)].width = min(48, max(10, w + 2))
        ws.freeze_panes = "B2"
    wb.save(path)


def table_html(rows, signed_cols=()):
    if not rows:
        return "<p class='note'>Veri yok.</p>"
    cols = list(rows[0].keys())
    head = "".join(f"<th>{html.escape(c)}</th>" for c in cols)
    body = ""
    for r in rows:
        cells = []
        for c in cols:
            v = r.get(c)
            txt = signed(v) if (c in signed_cols and isinstance(v, (int, float))) else fmt(v)
            cls = " class='l'" if c in ("Model", "Video", "Sonuç") else ""
            cells.append(f"<td{cls}>{html.escape(txt)}</td>")
        body += "<tr>" + "".join(cells) + "</tr>"
    return f"<div class='tw'><table><thead><tr>{head}</tr></thead><tbody>{body}</tbody></table></div>"


CSS = """
:root{--ink:#1b2430;--muted:#5b6675;--line:#d8dee8;--head:#1f3a5f;--soft:#eef2f7;--bg:#f7f9fc;--card:#fff}
*{box-sizing:border-box}body{margin:0;font:14px/1.5 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;color:var(--ink);background:var(--bg)}
header,main{max-width:1240px;margin:0 auto;padding:16px 20px}h1{font-size:22px;margin:8px 0}h2{font-size:18px;margin:0 0 10px}h3{font-size:15px;margin:16px 0 8px}
.card{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:18px;margin-bottom:18px}
.tw{overflow-x:auto}table{border-collapse:collapse;width:100%;font-size:12.5px}th,td{border:1px solid var(--line);padding:5px 7px;text-align:center;white-space:nowrap}
th{background:var(--head);color:#fff}tbody tr:nth-child(even){background:var(--soft)}td.l{text-align:left}
img{max-width:100%;height:auto;border:1px solid var(--line);border-radius:6px;margin:8px 0}.note{color:var(--muted);font-size:12.5px}
ul{margin:6px 0 0 18px;padding:0}li{margin:3px 0}
"""


def write_html(path, ctx):
    b64 = lambda b: "data:image/png;base64," + base64.b64encode(b).decode()
    vids = "".join(
        f"<li><b>{html.escape(r['label'])}</b>: {html.escape(r['data']['video']['filename'])} — {r['data']['video']['total_frames']} kare, "
        f"{r['data']['video']['fps']:.0f} FPS; çağrı: {html.escape(', '.join(str(c.get('start_s')) + '–' + str(c.get('end_s')) + ' s' for c in r['data']['video']['roi'].get('calls') or []))}; "
        f"referans: {html.escape(r['ref']['name'] if r['ref'] else 'yok')}; çalışmayan modeller: {html.escape(', '.join(r['unavailable']) or '—')}</li>"
        for r in ctx["runs"])
    acc = "".join(f"<h3>{html.escape(r['label'])}</h3>" + table_html(rows, ("Δ başl. vs ref", "Δ bitiş vs ref"))
                  for r, rows in zip(ctx["runs"], ctx["acc"]))
    ev = "".join(f"<h3>{html.escape(r['label'])}</h3><img alt='olay grafiği' src='{b64(img)}'>" + table_html(rows, ("Δ geri döndü vs ref",))
                 for r, rows, img in zip(ctx["runs"], ctx["events"], ctx["event_imgs"]))
    fl = table_html(ctx["flow"], ("Δ durma (artık) vs ref", "Δ durgunluk vs ref")) + "".join(
        f"<img alt='akış grafiği' src='{b64(img)}'>" for img in ctx["flow_imgs"])
    price = ctx["price"]
    doc = f"""<!doctype html><html lang="tr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>D01 Yöntem Karşılaştırması</title><style>{CSS}</style></head><body>
<header><h1>D01 Baş Hareketi — Yöntem, Maliyet ve Olay Karşılaştırması</h1>
<p class="note">Oluşturulma: {html.escape(ctx['created'])}. Saniye eşikleri simülasyon/analiz parametreleridir; bu rapor klinik tanı aracı değildir.</p></header>
<main>
<section class="card"><h2>Özet bulgular</h2><ul>{''.join(f'<li>{html.escape(x)}</li>' for x in ctx['findings'])}</ul>
<h3>Videolar</h3><ul>{vids}</ul></section>
<section class="card"><h2>1. Hız ve maliyet (sunucu)</h2><p class="note">{html.escape(COST_TEXT)}
{'' if price is not None else ' Aylık sunucu ücreti girilmediği için video başı maliyet sütunu boş; --aylik-ucret-tl ile doldurulur.'}</p>
<img alt="hız grafiği" src="{b64(ctx['speed_img'])}">{table_html(ctx['speed'])}</section>
<section class="card"><h2>2. Doğruluk (6DRepNet360 referansına göre)</h2>
<p class="note">Δ: modelin dönüş başlangıç/bitiş zamanı eksi referansınki (s). Sapma MAE: kare kare başlangıç pozundan sapma farkının ortalaması.</p>{acc}</section>
<section class="card"><h2>3. Olay durum makinesi: Baktı → Durdu → Geri döndü</h2><p class="note">{html.escape(FSM_TEXT)}</p>{ev}</section>
<section class="card"><h2>4. Optik akışla durma anı denemesi</h2><p class="note">{html.escape(FLOW_TEXT)}</p>{fl}</section>
</main></body></html>"""
    with open(path, "w", encoding="utf-8") as f:
        f.write(doc)


def write_pdf(path, ctx):
    plt = _plt()
    from matplotlib.backends.backend_pdf import PdfPages
    import textwrap
    A4L = (11.69, 8.27)

    def text_page(pdf, title, paragraphs):
        fig = plt.figure(figsize=A4L)
        fig.text(0.04, 0.94, title, fontsize=16, fontweight="bold")
        y = 0.88
        for p in paragraphs:
            for line in textwrap.wrap(p, 150):
                fig.text(0.04, y, line, fontsize=9.5)
                y -= 0.028
            y -= 0.015
        pdf.savefig(fig); plt.close(fig)

    def table_page(pdf, title, rows, signed_cols=(), note=None, img=None):
        if not rows:
            return
        fig = plt.figure(figsize=A4L)
        fig.text(0.03, 0.95, title, fontsize=13, fontweight="bold")
        top = 0.92
        if note:
            for i, line in enumerate(textwrap.wrap(note, 170)[:6]):
                fig.text(0.03, top - i * 0.024, line, fontsize=8)
            top -= 0.024 * min(6, len(textwrap.wrap(note, 170))) + 0.01
        if img is not None:
            from PIL import Image
            im = Image.open(io.BytesIO(img))
            h = min(0.45, top - 0.05)
            ax_i = fig.add_axes([0.03, top - h, 0.94, h]); ax_i.imshow(im); ax_i.axis("off")
            top -= h + 0.01
        cols = list(rows[0].keys())
        cells = [[(signed(r.get(c)) if (c in signed_cols and isinstance(r.get(c), (int, float))) else fmt(r.get(c))) for c in cols] for r in rows]
        ax = fig.add_axes([0.02, 0.03, 0.96, max(0.1, top - 0.04)]); ax.axis("off")
        wide = {"Model": 3.0, "Sonuç": 2.2, "Video": 1.0}
        w = [wide.get(c, 1.0) for c in cols]
        t = ax.table(cellText=cells, colLabels=["\n".join(textwrap.wrap(c, 16)) for c in cols], loc="upper center",
                     cellLoc="center", colWidths=[x / sum(w) for x in w])
        t.auto_set_font_size(False); t.set_fontsize(7); t.scale(1, 1.35)
        for (ri, ci), c in t.get_celld().items():
            if ri == 0:
                c.set_facecolor("#1f3a5f"); c.get_text().set_color("white"); c.set_height(c.get_height() * 1.8)
            elif ri % 2 == 0:
                c.set_facecolor("#eef2f7")
        pdf.savefig(fig); plt.close(fig)

    with PdfPages(path) as pdf:
        text_page(pdf, "D01 Baş Hareketi — Yöntem, Maliyet ve Olay Karşılaştırması",
                  [f"Oluşturulma: {ctx['created']}. Saniye eşikleri simülasyon/analiz parametreleridir; klinik tanı aracı değildir."]
                  + ["• " + x for x in ctx["findings"]] + ["", "Maliyet yöntemi: " + COST_TEXT, "", "Durum makinesi: " + FSM_TEXT])
        table_page(pdf, "1. Hız ve maliyet (sunucu)", ctx["speed"], img=ctx["speed_img"])
        for r, rows in zip(ctx["runs"], ctx["acc"]):
            table_page(pdf, f"2. Doğruluk — {r['label']}", rows, ("Δ başl. vs ref", "Δ bitiş vs ref"))
        for r, rows, img in zip(ctx["runs"], ctx["events"], ctx["event_imgs"]):
            table_page(pdf, f"3. Olay durum makinesi — {r['label']}", rows, ("Δ geri döndü vs ref",), img=img)
        table_page(pdf, "4. Optik akışla durma anı denemesi", ctx["flow"], ("Δ durma (artık) vs ref", "Δ durgunluk vs ref"), note=FLOW_TEXT)
        for img in ctx["flow_imgs"]:
            fig = plt.figure(figsize=A4L)
            from PIL import Image
            ax = fig.add_axes([0.02, 0.02, 0.96, 0.96]); ax.imshow(Image.open(io.BytesIO(img))); ax.axis("off")
            pdf.savefig(fig); plt.close(fig)


def main():
    ap = argparse.ArgumentParser(description="D01 çok videolu yöntem karşılaştırma raporu")
    ap.add_argument("--run", action="append", required=True, help="Etiket=benchmark_results.json (birden çok)")
    ap.add_argument("--out-dir", default="karsilastirma_raporu")
    ap.add_argument("--aylik-ucret-tl", type=float, default=None, help="Sunucunun aylık ücreti (TL); video başı maliyet için")
    args = ap.parse_args()
    from datetime import datetime
    runs = load_runs(args.run)
    speed = speed_cost_rows(runs, args.aylik_ucret_tl)
    ctx = {
        "created": datetime.now().strftime("%Y-%m-%d %H:%M"), "runs": runs, "price": args.aylik_ucret_tl,
        "speed": speed, "acc": [accuracy_rows(r) for r in runs], "events": [event_rows(r) for r in runs],
        "flow": flow_rows(runs), "findings": findings(runs, speed),
        "speed_img": fig_speed(speed), "event_imgs": [fig_events(r) for r in runs],
        "flow_imgs": [fig_flow(r) for r in runs],
    }
    os.makedirs(args.out_dir, exist_ok=True)
    base = os.path.join(args.out_dir, "D01_yontem_karsilastirma")
    write_html(base + ".html", ctx)
    write_pdf(base + ".pdf", ctx)
    write_xlsx(base + ".xlsx", [("Hiz_ve_Maliyet", speed)] +
               [(f"Dogruluk_{r['label']}", rows) for r, rows in zip(runs, ctx["acc"])] +
               [(f"Olaylar_{r['label']}", rows) for r, rows in zip(runs, ctx["events"])] +
               [("Optik_Akis", ctx["flow"])])
    for x in ctx["findings"]:
        print("•", x)
    print("Rapor:", base + ".html/.pdf/.xlsx")


if __name__ == "__main__":
    main()
