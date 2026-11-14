"""
Gemini senaryo üretimi stres testi raporu (+ üretilen senaryoların içerik kalite denetimi)

Girdi : rag_stress_test.js --save-outputs çıktıları (aşama başına bir JSON)
Çıktı : Gemini_stres_testi_raporu.html / .pdf / .xlsx

Kalite denetimi (her başarılı çıktı; sunucu zaten JSON yapısını doğrular):
  K1 Yapı           — sunucu sözleşme doğrulaması geçti (success)
  K2 Türkçe karakter— Türkçe yazılmış ve Türkçe karakterler korunmuş (ASCII'ye indirgenmemiş)
  K3 Tanı dili yok  — anlatı metninde (başlıklar hariç) otizm / tanı / teşhis / gelişimsel gecikme / atipik / risk vb. yok
  K4 Davranışa uygun— istenen davranışın (D01/D02/D04) temel öğeleri metinde var
  K5 Dallar farklı  — en az iki farklı sonuç dalı; devam metinleri birbirinin kopyası değil
  K6 Yaş tutarlı    — metinde ay/yaş (ör. "30-36 ay") geçiyorsa istenen yaş bandında
  K7 Uzunluk makul  — başlangıç ve dal metinleri çok kısa/uzun değil
  K8 Kart kuralı    — D01'de yetişkin adı tekrar seslenmiyor; D02'de çocuğa dokunup başını çevirmiyor
  K9 Meta sızıntı yok — anlatıya yönerge/meta yorum karışmamış ("taslak önerisi", "uzman incelemesi", "bu senaryoda"...)
  U1 Gözlenebilirlik (uyarı) — iç durum fiilleri (düşünür, hisseder, anlar...) sayısı
  U2 Başlık etiketi (uyarı)  — dal başlığında "Tipik/Atipik" etiketi (sistemin iç etiketi; kullanıcıya gösterilirse gözden geçirilmeli)
Kullanım:
  python stres_testi_raporu.py --phase "1 kullanıcı=p1.json" --phase "4 kullanıcı=p2.json" ... --out-dir rapor
      [--manual manuel_inceleme.json]
"""
import argparse
import base64
import html
import io
import json
import os
import re
import textwrap
from itertools import combinations
from typing import Any, Dict, List, Optional

import numpy as np

AGE_BANDS = {"12_18": (12, 18), "18_24": (18, 24), "24_36": (24, 36)}
_FOLD = str.maketrans("çğıöşüÇĞİÖŞÜâîû", "cgiosucgiosuaiu")


def fold(s: str) -> str:
    """Türkçe karakterleri ASCII'ye indirger; denetimler aksan farkından etkilenmesin."""
    return (s or "").replace("İ", "i").translate(_FOLD).lower()


# Anlatı metninde (başlıklar hariç) tanı/klinik dil — katlanmış (ASCII) metinde, tam kelime biçimleri
DIAG = re.compile(r"\b(otiz\w*|otisti\w*|osb|tani|tanisi|tanisini|tanisina|tani koy\w*|teshis\w*|bozukluk\w*|sendrom\w*|"
                  r"gelisimsel gecikme\w*|gerilik\w*|geriligi|atipik\w*|anormal\w*|hastalik\w*|riskli|risk|risk[il]\w*|"
                  r"patoloj\w*|semptom\w*|belirti|belirtisi|belirtileri)\b")
LABEL = re.compile(r"\b(atipik|tipik)\b")
MENTAL = re.compile(r"\b(dusunur|dusunuyor|hisseder|hissediyor|anlar|anliyor|fark eder|merak eder|ister|istiyor|"
                    r"sever|seviyor|mutlu olur|uzulur|sikilir|heyecanlanir)\b")
BEHAVIOR_KEYS = {  # katlanmış metinde aranır
    "D01": [r"(adini|ismini|isim|seslen|cagir|\bder\b|soyler|adiyla)", r"(don|bak|yonel)"],
    "D02": [r"(isaret|parma[kg]|gosterir)", r"(bak|yonel|takip|doner|cevir)"],
    "D04": [r"(fincan|bebe[kg]|oyuncak)", r"(gibi|icir|besle|uyut|taklit|yapar|hayali)"],
}
RULE_VIOLATION = {
    "D01": re.compile(r"(tekrar|yeniden|ikinci kez|bir kez daha|birkac kez)[^.]{0,40}(seslen|cagir|adini|ismini|soyle)"),
    "D02": re.compile(r"(cocugun|cocuga)[^.]{0,30}(dokun|basini cevir|elinden tut)"),
}
META = re.compile(r"(taslak oneri\w*|uzman incelem\w*|ekip incelem\w*|klinik (bir )?esik|prototip\w*|bu senaryo\w*|"
                  r"senaryoda\b|uyarlan\w*|temsili|temsil ed\w*|basari sinir\w*|hukum veril\w*|yonerge geregi|kart(ta|in) belirt\w*)")
TR_WORDS = re.compile(r"\b(ve|bir|ile|cocuk|yetiskin|sahne|oyun|bu|olarak|dogru)\b")
CHECKS = ["K1 Yapı", "K2 Türkçe karakter", "K3 Tanı dili yok", "K4 Davranışa uygun", "K5 Dallar farklı",
          "K6 Yaş tutarlı", "K7 Uzunluk makul", "K8 Kart kuralı", "K9 Meta sızıntı yok"]


def words(s: str) -> set:
    return set(re.findall(r"\w+", s.lower()))


def jaccard(a: str, b: str) -> float:
    A, B = words(a), words(b)
    return len(A & B) / max(1, len(A | B))


def parse_output(raw: Optional[str]) -> Optional[Dict[str, Any]]:
    if not isinstance(raw, str):
        return None
    s = raw.strip()
    m = re.match(r"^```json[ \t]*\r?\n([\s\S]*?)\r?\n```$", s, re.I)
    if m:
        s = m.group(1)
    try:
        v = json.loads(s)
    except Exception:
        return None
    if isinstance(v, dict) and "scenarioInput" in v and isinstance(v["scenarioInput"], dict):
        v = v["scenarioInput"]
    return v if isinstance(v, dict) else None


def scenario_texts(v: Dict[str, Any]):
    start = v.get("commonStart") or ""
    alts = v.get("alternatives") or []
    branches = [" ".join(str(a.get(k) or "") for k in ("title", "continuation", "ending")) for a in alts if isinstance(a, dict)]
    for st in v.get("stages") or []:
        for b in st.get("branches") or []:
            branches.append(" ".join(str(b.get(k) or "") for k in ("title", "continuation", "ending")))
    scenes = [str(s.get("description") or "") for s in v.get("linearScenes") or []]
    return start, alts, branches, scenes


def check_output(rec: Dict[str, Any], request: Dict[str, Any]) -> Dict[str, Any]:
    behavior = ((request.get("behaviors") or [{}])[0]).get("behaviorId")
    band = AGE_BANDS.get(((request.get("ageGroup") or {}).get("id")) or "", None)
    v = parse_output(rec.get("rawResponse"))
    res = {c: None for c in CHECKS}
    res["K1 Yapı"] = rec.get("outcome") == "success"
    if v is None:
        res["not"] = "çıktı ayrıştırılamadı"
        return res
    start, alts, branches, scenes = scenario_texts(v)
    full = " ".join([start] + branches + scenes)
    titles_raw = [str(a.get("title") or "") for a in alts if isinstance(a, dict)]
    narrative = " ".join([start, *scenes] + [" ".join(str(a.get(k) or "") for k in ("continuation", "ending"))
                                             for a in alts if isinstance(a, dict)])
    f_full, f_narr = fold(full), fold(narrative)
    tr_chars = len(re.findall(r"[çğıöşüÇĞİÖŞÜ]", full))
    res["K2 Türkçe karakter"] = tr_chars >= 5 and len(TR_WORDS.findall(f_full)) >= 3
    diag = sorted({m.group(0) for m in DIAG.finditer(f_narr)})
    res["K3 Tanı dili yok"] = not diag
    keys = BEHAVIOR_KEYS.get(behavior)
    res["K4 Davranışa uygun"] = all(re.search(k, f_full) for k in keys) if keys else None
    conts = [str(a.get("continuation") or "") for a in alts if isinstance(a, dict)]
    titles = [t.strip().lower() for t in titles_raw]
    sim = max((jaccard(a, b) for a, b in combinations(conts, 2)), default=1.0)
    res["K5 Dallar farklı"] = len(conts) >= 2 and len(set(titles)) == len(titles) and sim < 0.6
    ages = []
    for a, b in re.findall(r"(\d{1,2})\s*(?:-|–|ila|ile)\s*(\d{1,2})\s*ay", f_full):
        ages += [int(a), int(b)]
    rest = re.sub(r"(\d{1,2})\s*(?:-|–|ila|ile)\s*(\d{1,2})\s*ay", " ", f_full)
    ages += [int(x) for x in re.findall(r"(\d{1,2})\s*ay(?:lik|lık)?\b", rest)]
    ages += [int(x) * 12 for x in re.findall(r"\b(\d)\s*yas", rest)]
    res["K6 Yaş tutarlı"] = True if (not ages or not band) else all(band[0] <= a <= band[1] for a in ages)
    lens_ok = 60 <= len(start) <= 1500 and all(20 <= len(b) <= 1200 for b in branches) if branches else False
    res["K7 Uzunluk makul"] = lens_ok
    rule = RULE_VIOLATION.get(behavior)
    res["K8 Kart kuralı"] = True if rule is None else not rule.search(f_full)
    meta = sorted({m.group(0) for m in META.finditer(f_narr)})
    res["K9 Meta sızıntı yok"] = not meta
    res["meta ifadeler"] = meta
    res["U1 iç durum fiili"] = len(MENTAL.findall(f_full))
    res["U2 başlıkta tipik/atipik"] = sum(bool(LABEL.search(fold(t))) for t in titles_raw)
    res["tanı terimleri"] = diag
    res["dal benzerliği"] = round(sim, 2)
    res["yaş ifadeleri"] = ages
    res["başlangıç"] = start
    res["dallar"] = [{"title": a.get("title"), "continuation": a.get("continuation"), "ending": a.get("ending")}
                     for a in alts if isinstance(a, dict)]
    return res


def pct(values: List[float], p: float) -> Optional[float]:
    v = sorted(x for x in values if isinstance(x, (int, float)))
    if not v:
        return None
    return v[min(len(v) - 1, int(np.ceil(p / 100 * len(v))) - 1)]


def load(phases: List[str]):
    inputs = {i["id"]: i["request"] for i in
              json.load(open(os.path.join(os.path.dirname(__file__), "..", "experiments", "comparison_24.json"), encoding="utf-8"))["inputs"]}
    out = []
    for p in phases:
        label, path = p.split("=", 1)
        d = json.load(open(path, encoding="utf-8"))
        for r in d["records"]:
            r["phase"] = label
            r["quality"] = check_output(r, inputs.get(r["inputId"], {})) if r.get("rawResponse") else None
        out.append({"label": label, "data": d})
    return out, inputs


def perf_rows(phases):
    rows = []
    for ph in phases:
        rs = ph["data"]["records"]
        o = ph["data"]["summary"]["overall"]
        ok = [r for r in rs if r["outcome"] == "success"]
        m = lambda key, src=rs: [r["measurement"].get(key) for r in src if r.get("measurement") and r["measurement"].get(key) is not None]
        rows.append({
            "Aşama": ph["label"],
            "Uç nokta": ",".join(ph["data"]["options"]["endpoints"]),
            "Eşzamanlı": ph["data"]["options"]["concurrency"],
            "İstek": len(rs), "Başarılı": len(ok),
            "Hata %": round(100 * (1 - len(ok) / max(1, len(rs))), 1),
            "Sonuçlar": ", ".join(f"{k}:{v}" for k, v in sorted(o["outcomes"].items())),
            "İstemci p50 (s)": None if not ok else round(pct([r["clientMs"] for r in ok], 50) / 1000, 2),
            "İstemci p95 (s)": None if not ok else round(pct([r["clientMs"] for r in ok], 95) / 1000, 2),
            "RAG p50 (ms)": None if not m("retrievalDurationMs") else round(pct(m("retrievalDurationMs"), 50), 1),
            "RAG p95 (ms)": None if not m("retrievalDurationMs") else round(pct(m("retrievalDurationMs"), 95), 1),
            "Kuyruk p50 (s)": None if not m("queueWaitMs") else round(pct(m("queueWaitMs"), 50) / 1000, 2),
            "Kuyruk p95 (s)": None if not m("queueWaitMs") else round(pct(m("queueWaitMs"), 95) / 1000, 2),
            "Gemini p50 (s)": None if not m("providerDurationMs", ok) else round(pct(m("providerDurationMs", ok), 50) / 1000, 2),
            "Gemini p95 (s)": None if not m("providerDurationMs", ok) else round(pct(m("providerDurationMs", ok), 95) / 1000, 2),
            "Verim (istek/dk)": round(60 * o["throughputPerS"], 1),
        })
    return rows


def quality_rows(records, key_fn, key_name):
    groups: Dict[str, List[Dict[str, Any]]] = {}
    for r in records:
        if r.get("quality") and r["outcome"] == "success":
            groups.setdefault(key_fn(r), []).append(r["quality"])
    rows = []
    for k in sorted(groups):
        qs = groups[k]
        row = {key_name: k, "Çıktı": len(qs)}
        for c in CHECKS:
            vals = [q[c] for q in qs if q.get(c) is not None]
            row[c] = None if not vals else round(100 * sum(vals) / len(vals), 1)
        row["Tümü geçti %"] = round(100 * sum(all(q.get(c) in (True, None) for c in CHECKS) for q in qs) / len(qs), 1)
        row["İç durum fiili (ort.)"] = round(float(np.mean([q.get("U1 iç durum fiili", 0) for q in qs])), 2)
        row["Başlıkta tipik/atipik %"] = round(100 * sum(q.get("U2 başlıkta tipik/atipik", 0) > 0 for q in qs) / len(qs), 1)
        rows.append(row)
    return rows


def diversity_rows(records, inputs):
    by: Dict[str, List[str]] = {}
    for r in records:
        q = r.get("quality")
        if q and q.get("başlangıç") and r["endpoint"] == "input":
            by.setdefault(r["inputId"], []).append(q["başlangıç"])
    rows = []
    for k, starts in sorted(by.items()):
        sims = [jaccard(a, b) for a, b in combinations(starts, 2)]
        req = inputs.get(k, {})
        rows.append({"Girdi": k, "Davranış": (req.get("behaviors") or [{}])[0].get("behaviorId"),
                     "Yaş bandı": (req.get("ageGroup") or {}).get("id"), "Çıktı": len(starts),
                     "Ortalama benzerlik": None if not sims else round(float(np.mean(sims)), 2),
                     "Neredeyse kopya (>0,85) %": None if not sims else round(100 * sum(s > 0.85 for s in sims) / len(sims), 1)})
    return rows


def failures(records, limit=12):
    out = []
    for r in records:
        q = r.get("quality")
        if not q or r["outcome"] != "success":
            continue
        bad = [c for c in CHECKS if q.get(c) is False]
        if bad:
            detail = []
            if q.get("tanı terimleri"):
                detail.append("terimler: " + ", ".join(q["tanı terimleri"]))
            if "K6 Yaş tutarlı" in bad:
                detail.append(f"yaş: {q.get('yaş ifadeleri')}")
            if q.get("meta ifadeler"):
                detail.append("meta: " + ", ".join(q["meta ifadeler"][:4]))
            if "K5 Dallar farklı" in bad:
                detail.append(f"dal benzerliği {q.get('dal benzerliği')}")
            out.append({"Aşama": r["phase"], "İstek": r["index"], "Girdi": r["inputId"], "Kol": r.get("arm") or "—",
                        "Başarısız": ", ".join(bad), "Ayrıntı": "; ".join(detail),
                        "Başlangıç (ilk 160 karakter)": (q.get("başlangıç") or "")[:160]})
    return out[:limit], len(out)


# ------------------------------------------------------------------------------------------- grafikler
def _plt():
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    return plt


def png(fig):
    buf = io.BytesIO()
    fig.savefig(buf, format="png", dpi=110, bbox_inches="tight")
    _plt().close(fig)
    return buf.getvalue()


def fig_latency(phases):
    plt = _plt()
    fig, (a1, a2) = plt.subplots(1, 2, figsize=(13, 4.6))
    labels = [p["label"] for p in phases]
    rag, queue, prov, other = [], [], [], []
    data = []
    for p in phases:
        ok = [r for r in p["data"]["records"] if r["outcome"] == "success" and r.get("measurement")]
        med = lambda k: float(np.median([r["measurement"].get(k) or 0 for r in ok])) / 1000 if ok else 0
        cl = float(np.median([r["clientMs"] for r in ok])) / 1000 if ok else 0
        rag.append(med("retrievalDurationMs")); queue.append(med("queueWaitMs")); prov.append(med("providerDurationMs"))
        other.append(max(0.0, cl - rag[-1] - queue[-1] - prov[-1]))
        data.append([r["clientMs"] / 1000 for r in ok])
    x = np.arange(len(labels))
    b = np.zeros(len(labels))
    for vals, name, col in ((rag, "RAG (kart arama)", "#16a34a"), (queue, "Kuyrukta bekleme", "#f59e0b"),
                            (prov, "Gemini yanıtı", "#2563eb"), (other, "Ağ + doğrulama", "#94a3b8")):
        a1.bar(x, vals, bottom=b, label=name, color=col)
        b += np.array(vals)
    a1.set_xticks(x, labels, rotation=15)
    a1.set_ylabel("Medyan süre (s)")
    a1.set_title("Yanıt süresinin bileşenleri (başarılı istekler, medyan)")
    a1.legend(fontsize=8)
    a2.boxplot([d if d else [0] for d in data], showfliers=True)
    a2.set_xticks(np.arange(1, len(labels) + 1), labels)
    a2.set_ylabel("Kullanıcının beklediği süre (s)")
    a2.set_title("İstemci bekleme süresi dağılımı")
    a2.tick_params(axis="x", rotation=15)
    for ax in (a1, a2):
        ax.grid(axis="y", alpha=0.3)
    return png(fig)


def fig_outcomes(phases):
    plt = _plt()
    names = sorted({k for p in phases for k in p["data"]["summary"]["overall"]["outcomes"]})
    colors = {"success": "#16a34a", "capacity_rejected": "#f59e0b", "provider_error": "#dc2626",
              "provider_quota": "#7c3aed", "validation_error": "#db2777", "server_timeout": "#0ea5e9"}
    fig, ax = plt.subplots(figsize=(11, 3.8))
    x = np.arange(len(phases))
    b = np.zeros(len(phases))
    for n in names:
        vals = np.array([p["data"]["summary"]["overall"]["outcomes"].get(n, 0) for p in phases])
        ax.bar(x, vals, bottom=b, label=n, color=colors.get(n, "#64748b"))
        b += vals
    ax.set_xticks(x, [p["label"] for p in phases], rotation=15)
    ax.set_ylabel("İstek sayısı")
    ax.set_title("İstek sonuçları (aşama başına)")
    ax.legend(fontsize=8, ncol=3)
    ax.grid(axis="y", alpha=0.3)
    return png(fig)


# ------------------------------------------------------------------------------------------- yazıcılar
def fmtv(v):
    if v is None:
        return "—"
    if isinstance(v, float):
        return f"{v:.2f}".rstrip("0").rstrip(".") if abs(v) < 1000 else f"{v:.0f}"
    if isinstance(v, bool):
        return "evet" if v else "hayır"
    return str(v)


def table_html(rows, left=("Aşama", "Sonuçlar", "Başarısız", "Ayrıntı", "Başlangıç (ilk 160 karakter)", "Kol", "Girdi")):
    if not rows:
        return "<p class='note'>Veri yok.</p>"
    cols = list(rows[0].keys())
    head = "".join(f"<th>{html.escape(c)}</th>" for c in cols)
    body = "".join("<tr>" + "".join(f"<td class='{'l' if c in left else ''}'>{html.escape(fmtv(r.get(c)))}</td>" for c in cols) + "</tr>" for r in rows)
    return f"<div class='tw'><table><thead><tr>{head}</tr></thead><tbody>{body}</tbody></table></div>"


CSS = """
:root{--ink:#1b2430;--muted:#5b6675;--line:#d8dee8;--head:#1f3a5f;--soft:#eef2f7;--bg:#f7f9fc;--card:#fff}
*{box-sizing:border-box}body{margin:0;font:14px/1.5 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;color:var(--ink);background:var(--bg)}
header,main{max-width:1240px;margin:0 auto;padding:16px 20px}h1{font-size:22px;margin:8px 0}h2{font-size:18px;margin:0 0 10px}h3{font-size:15px;margin:16px 0 8px}
.card{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:18px;margin-bottom:18px}
.tw{overflow-x:auto}table{border-collapse:collapse;width:100%;font-size:12.5px}th,td{border:1px solid var(--line);padding:5px 7px;text-align:center}
th{background:var(--head);color:#fff}tbody tr:nth-child(even){background:var(--soft)}td.l{text-align:left}
img{max-width:100%;height:auto;border:1px solid var(--line);border-radius:6px;margin:8px 0}.note{color:var(--muted);font-size:12.5px}
ul{margin:6px 0 0 18px;padding:0}li{margin:3px 0}blockquote{margin:8px 0;padding:8px 12px;background:var(--soft);border-left:3px solid var(--head)}
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--phase", action="append", required=True)
    ap.add_argument("--out-dir", default="stres_raporu")
    ap.add_argument("--manual", default=None, help="Elle inceleme notları (JSON: {ozet, ornekler:[{baslik, yorum}]})")
    ap.add_argument("--meta", default=None, help="Ek açıklama (JSON: {sunucu, model, kapasite, ...})")
    args = ap.parse_args()
    phases, inputs = load(args.phase)
    records = [r for p in phases for r in p["data"]["records"]]
    perf = perf_rows(phases)
    q_input = quality_rows(records, lambda r: f"{r['inputId']} ({(inputs[r['inputId']]['behaviors'][0]['behaviorId'])})", "Girdi")
    q_arm = quality_rows([r for r in records if r["endpoint"] == "compare"], lambda r: f"Kol {r['arm']}", "Deney kolu")
    q_all = quality_rows(records, lambda r: "TÜMÜ", "Kapsam")
    div = diversity_rows(records, inputs)
    fails, n_fail = failures(records)
    manual = json.load(open(args.manual, encoding="utf-8")) if args.manual else None
    meta = json.load(open(args.meta, encoding="utf-8")) if args.meta else {}
    imgs = {"lat": fig_latency(phases), "out": fig_outcomes(phases)}

    total = len(records)
    ok = sum(r["outcome"] == "success" for r in records)
    qa = q_all[0] if q_all else {}
    findings = [
        f"Toplam {total} istek gönderildi; {ok} başarılı (%{100 * ok / max(1, total):.1f}).",
        f"RAG (kart arama) süresi medyan {pct([r['measurement']['retrievalDurationMs'] for r in records if r.get('measurement') and r['measurement'].get('retrievalDurationMs') is not None], 50) or 0:.1f} ms; "
        f"yanıt süresinin neredeyse tamamını Gemini belirliyor.",
        f"Başarılı çıktıların %{qa.get('Tümü geçti %', 0)}'i tüm otomatik içerik denetimlerinden geçti "
        f"(tanı dili yok: %{qa.get('K3 Tanı dili yok')}, davranışa uygun: %{qa.get('K4 Davranışa uygun')}, dallar farklı: %{qa.get('K5 Dallar farklı')}).",
    ] + (meta.get("bulgular") or [])
    meta_lines = "".join(f"<li><b>{html.escape(k)}</b>: {html.escape(str(v))}</li>" for k, v in meta.items() if k != "bulgular")
    manual_html = ""
    if manual:
        manual_html = f"<p>{html.escape(manual.get('ozet', ''))}</p>" + "".join(
            f"<h3>{html.escape(o['baslik'])}</h3><blockquote>{html.escape(o.get('alinti', ''))}</blockquote><p>{html.escape(o['yorum'])}</p>"
            for o in manual.get("ornekler", []))
    b64 = lambda b: "data:image/png;base64," + base64.b64encode(b).decode()
    checks_desc = "".join(f"<li>{html.escape(l.strip())}</li>" for l in __doc__.split("Kalite denetimi")[1].split("Kullanım")[0].splitlines()[1:] if l.strip())
    doc = f"""<!doctype html><html lang="tr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Gemini Stres Testi</title><style>{CSS}</style></head><body>
<header><h1>Gemini Senaryo Üretimi — Stres Testi ve Çıktı Kalitesi</h1>
<p class="note">Sentetik eğitim senaryoları üretimi ölçülmüştür; çıktılar klinik tanı amacı taşımaz.</p></header><main>
<section class="card"><h2>Özet</h2><ul>{''.join(f'<li>{html.escape(x)}</li>' for x in findings)}</ul><h3>Test ortamı</h3><ul>{meta_lines}</ul></section>
<section class="card"><h2>1. Performans</h2><img alt="süreler" src="{b64(imgs['lat'])}"><img alt="sonuçlar" src="{b64(imgs['out'])}">{table_html(perf)}
<p class="note">capacity_rejected: aynı anda gelen istek sayısı kapasite + kuyruğu aştığı için Gemini'ye gönderilmeden anında reddedildi. provider_error: Gemini geçici hata (ör. 503). provider_quota: Gemini kota reddi.</p></section>
<section class="card"><h2>2. Çıktı kalitesi (otomatik denetim)</h2><ul>{checks_desc}</ul>
<h3>Genel</h3>{table_html(q_all)}<h3>Girdiye göre</h3>{table_html(q_input)}<h3>Deney koluna göre (A: kural yok, B: tek kart, C: tüm kartlar, D: JSON RAG)</h3>{table_html(q_arm)}
<h3>Çeşitlilik (aynı girdiye üretilen başlangıçların benzerliği)</h3>{table_html(div)}
<h3>Denetimden geçemeyen çıktılar ({n_fail}; ilk {len(fails)})</h3>{table_html(fails)}</section>
<section class="card"><h2>3. Elle inceleme</h2>{manual_html or "<p class='note'>Elle inceleme notu eklenmedi.</p>"}</section>
</main></body></html>"""
    os.makedirs(args.out_dir, exist_ok=True)
    base = os.path.join(args.out_dir, "Gemini_stres_testi_raporu")
    with open(base + ".html", "w", encoding="utf-8") as f:
        f.write(doc)

    # Excel
    from openpyxl import Workbook
    from openpyxl.styles import Font, PatternFill, Alignment
    from openpyxl.utils import get_column_letter
    wb = Workbook(); wb.remove(wb.active)
    sample_rows = [{"Aşama": r["phase"], "İstek": r["index"], "Girdi": r["inputId"], "Kol": r.get("arm"), "Sonuç": r["outcome"],
                    "İstemci (s)": round(r["clientMs"] / 1000, 2),
                    **{c: (r.get("quality") or {}).get(c) for c in CHECKS},
                    "Başlangıç": (r.get("quality") or {}).get("başlangıç"),
                    "Dallar": json.dumps((r.get("quality") or {}).get("dallar"), ensure_ascii=False) if r.get("quality") else None,
                    "Hata": r.get("error")} for r in records]
    for title, rows in (("Performans", perf), ("Kalite_Genel", q_all), ("Kalite_Girdi", q_input), ("Kalite_Kol", q_arm),
                        ("Cesitlilik", div), ("Tum_Istekler", sample_rows)):
        ws = wb.create_sheet(title)
        if not rows:
            continue
        cols = list(rows[0].keys())
        for j, c in enumerate(cols, 1):
            cell = ws.cell(row=1, column=j, value=c)
            cell.font = Font(bold=True, color="FFFFFF"); cell.fill = PatternFill("solid", fgColor="1F3A5F")
            cell.alignment = Alignment(wrap_text=True, horizontal="center")
        for i, r in enumerate(rows, 2):
            for j, c in enumerate(cols, 1):
                v = r.get(c)
                ws.cell(row=i, column=j, value=v if not isinstance(v, (list, dict)) else json.dumps(v, ensure_ascii=False))
        for j, c in enumerate(cols, 1):
            ws.column_dimensions[get_column_letter(j)].width = 60 if c in ("Başlangıç", "Dallar") else 16
        ws.freeze_panes = "B2"
    wb.save(base + ".xlsx")

    # PDF
    plt = _plt()
    from matplotlib.backends.backend_pdf import PdfPages
    from PIL import Image
    A4L = (11.69, 8.27)

    def page_table(pdf, title, rows, wide=None, img=None, note=None):
        fig = plt.figure(figsize=A4L)
        fig.text(0.03, 0.95, title, fontsize=13, fontweight="bold")
        top = 0.92
        if note:
            for i, line in enumerate(textwrap.wrap(note, 170)):
                fig.text(0.03, top - i * 0.024, line, fontsize=8.5)
            top -= 0.024 * len(textwrap.wrap(note, 170)) + 0.01
        if img is not None:
            h = 0.42
            ax = fig.add_axes([0.03, top - h, 0.94, h]); ax.imshow(Image.open(io.BytesIO(img))); ax.axis("off")
            top -= h + 0.01
        if rows:
            cols = list(rows[0].keys())
            w = [(wide or {}).get(c, 1.0) for c in cols]
            ax = fig.add_axes([0.02, 0.03, 0.96, max(0.1, top - 0.04)]); ax.axis("off")
            t = ax.table(cellText=[[textwrap.shorten(fmtv(r.get(c)), 70) for c in cols] for r in rows],
                         colLabels=["\n".join(textwrap.wrap(c, 14)) for c in cols], loc="upper center", cellLoc="center",
                         colWidths=[x / sum(w) for x in w])
            t.auto_set_font_size(False); t.set_fontsize(6.8); t.scale(1, 1.4)
            for (ri, ci), c in t.get_celld().items():
                if ri == 0:
                    c.set_facecolor("#1f3a5f"); c.get_text().set_color("white"); c.set_height(c.get_height() * 1.8)
                elif ri % 2 == 0:
                    c.set_facecolor("#eef2f7")
        pdf.savefig(fig); plt.close(fig)

    with PdfPages(base + ".pdf") as pdf:
        fig = plt.figure(figsize=A4L)
        fig.text(0.04, 0.93, "Gemini Senaryo Üretimi — Stres Testi ve Çıktı Kalitesi", fontsize=16, fontweight="bold")
        y = 0.86
        for line in [f"• {x}" for x in findings] + [""] + [f"{k}: {v}" for k, v in meta.items() if k != "bulgular"]:
            for w in textwrap.wrap(line, 150) or [""]:
                fig.text(0.04, y, w, fontsize=9.5); y -= 0.03
        if manual:
            y -= 0.02
            fig.text(0.04, y, "Elle inceleme:", fontsize=10, fontweight="bold"); y -= 0.03
            for w in textwrap.wrap(manual.get("ozet", ""), 150):
                fig.text(0.04, y, w, fontsize=9.5); y -= 0.028
        pdf.savefig(fig); plt.close(fig)
        page_table(pdf, "1. Performans", perf, wide={"Sonuçlar": 3.2, "Aşama": 1.6}, img=imgs["lat"])
        page_table(pdf, "1b. İstek sonuçları", [], img=imgs["out"])
        page_table(pdf, "2. Çıktı kalitesi — genel ve girdiye göre", q_all + q_input, wide={"Kapsam": 1.6, "Girdi": 2.2})
        if q_arm:
            page_table(pdf, "2b. Çıktı kalitesi — deney kollarına göre", q_arm)
        page_table(pdf, "2c. Çeşitlilik", div)
        if fails:
            page_table(pdf, f"2d. Denetimden geçemeyen çıktılar ({n_fail})", fails,
                       wide={"Başlangıç (ilk 160 karakter)": 4.5, "Ayrıntı": 2.2, "Başarısız": 2.0})
        if manual:
            fig = plt.figure(figsize=A4L)
            fig.text(0.04, 0.94, "3. Elle inceleme", fontsize=14, fontweight="bold")
            y = 0.89
            for o in manual.get("ornekler", []):
                for w in textwrap.wrap(o["baslik"], 140):
                    fig.text(0.04, y, w, fontsize=10, fontweight="bold"); y -= 0.028
                for w in textwrap.wrap(o["yorum"], 160):
                    fig.text(0.05, y, w, fontsize=8.8); y -= 0.025
                y -= 0.012
                if y < 0.08:
                    pdf.savefig(fig); plt.close(fig); fig = plt.figure(figsize=A4L); y = 0.93
            pdf.savefig(fig); plt.close(fig)
    # İnceleme için tüm çıktılar (elle okuma)
    with open(base + "_ciktilar.json", "w", encoding="utf-8") as f:
        json.dump([{k: r.get(k) for k in ("phase", "index", "endpoint", "arm", "inputId", "outcome", "error")} |
                   {"quality": {k: v for k, v in (r.get("quality") or {}).items()}} for r in records], f, ensure_ascii=False, indent=1)
    for x in findings:
        print("•", x)
    print("Rapor:", base + ".html/.pdf/.xlsx")


if __name__ == "__main__":
    main()
