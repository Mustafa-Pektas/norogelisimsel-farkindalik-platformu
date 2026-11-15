"""Event decisions. Scores are diagnostics, never behavioral probabilities."""
LABELS = {
    "toward_caller": "Çağıran kişiye yönelme adayı gözlendi",
    "toward_visible_adult": "Görüntüdeki yetişkine yönelme adayı gözlendi; konuşan kişi eşleşmesi bilinmiyor",
    "toward_other": "Başka hedefe yönelme adayı gözlendi",
    "already_oriented": "Çağrı öncesinde yetişkine yönelmişti",
    "no_orientation_observed": "Tanımlı gözlem aralığında yönelme gözlenmedi",
    "uncertain": "Sonuç belirsiz",
    "not_evaluable": "Değerlendirilemedi"
}


def sustained(rows, predicate, hold_s, max_gap_s):
    """Only contiguous observed samples support a run; never bridge missing data."""
    start = previous = None
    for row in rows:
        t = row["time_s"]
        if not predicate(row):
            start = previous = None
            continue
        if start is None or t - previous > max_gap_s:
            start = t
        previous = t
        if t - start + 1e-7 >= hold_s:
            return {"start_s": start, "confirmed_s": t}
    return None


def evaluate(call, rows, gaze_rows, settings, fps, duration):
    s = settings
    begin = call["start_s"]
    end = min(duration, begin + s["observation_s"])
    baseline = [r for r in rows if begin-s["baseline_s"] <= r["time_s"] < begin-s["baseline_guard_s"]]
    after = [r for r in rows if begin <= r["time_s"] <= end]
    gazebase = [r for r in gaze_rows if begin-s["baseline_s"] <= r["time_s"] < begin-s["baseline_guard_s"]]
    gazepost = [r for r in gaze_rows if begin <= r["time_s"] <= end]
    posebase = [r for r in baseline if r.get("rotation_vector") is not None]
    coverage = sum(r.get("rotation_vector") is not None for r in after)/max(1, len(after))
    gaze_coverage = sum(r.get("target") not in (None, "unavailable") for r in gazepost)/max(1, len(gazepost))
    sample_gap = 1.6/s["gaze_fps"]
    adult_ids = {"adult_face", "adult_body"}
    # Require an observed below-to-above threshold crossing. Reappearance after
    # a gap at an already changed angle cannot establish movement onset.
    onset_rows=[]
    armed=False
    previous_t=None
    for row in rows:
        t=row["time_s"]
        if t<begin-s["baseline_s"] or t>end:
            continue
        change=row.get("pose_change_deg")
        if change is None or (previous_t is not None and t-previous_t>1.6/fps):
            armed=False
        if change is not None and change<s["movement_degrees"]:
            armed=True
        annotated=dict(row)
        annotated["new_motion"]=armed and change is not None and change>=s["movement_degrees"]
        onset_rows.append(annotated)
        previous_t=t
    motion_run=sustained(onset_rows,lambda r:r["new_motion"],s["movement_hold_s"],1.6/fps)
    movement=motion_run if motion_run and motion_run["start_s"]>=begin else None
    # Missing gaze, ambiguous and off-screen samples all break a target run.
    adult = sustained(gazepost, lambda r: r.get("target") in adult_ids, s["target_hold_s"], sample_gap)
    other = sustained(gazepost, lambda r: r.get("target") not in adult_ids | {None,"ambiguous","unavailable","offscreen"}, s["target_hold_s"], sample_gap)
    already = sustained(gazebase, lambda r: r.get("target") in adult_ids, s["target_hold_s"], sample_gap)
    reasons = []
    first_deviation=movement
    if adult and movement and adult["start_s"]-movement["start_s"]>s.get("max_motion_target_gap_s",1.0):
        movement=None
        reasons.append("İlk baş pozu değişimi hedef geçişinden uzakta; yetişkine dönüşün başlangıcı olarak kullanılmadı.")
    baseline_ok = len(posebase) >= s["min_baseline_samples"]
    if not baseline_ok:
        reasons.append("Çağrı öncesinde yeterli baş pozu ölçümü yok.")
    if coverage < s["min_coverage"]:
        reasons.append("Baş pozu ölçüm kapsaması düşük; kayıp kareler tepki yok sayılmadı.")
    if gaze_coverage < s["min_coverage"]:
        reasons.append("Hedef tahmini kapsaması düşük.")
    if not call.get("speaker_target_id"):
        reasons.append("Çağıran kişinin görüntüdeki yetişkin olduğu doğrulanmadı.")
    reasons.append("Çağrı zamanı önceki otomatik kayıttan alındı; zamanlama belirsizliği sayısallaştırılmadı.")
    decision = "uncertain"
    if already and gazebase and gazebase[-1].get("target") in adult_ids:
        decision = "already_oriented"
    elif adult:
        # A sustained gaze target transition independently supports a visual
        # orientation candidate. It cannot establish exact head movement onset.
        clear_prior={"toy"}
        if gazebase and gazebase[-1].get("target") in clear_prior:
            decision = "toward_caller" if call.get("speaker_target_id") in adult_ids else "toward_visible_adult"
            reasons.append("Çağrı öncesi oyuncak hedefinden ardışık yetişkin hedef tahminlerine geçiş gözlendi.")
            if movement:
                reasons.append("Hedef geçişine yakın baş pozu değişimi de ölçüldü; eşik zamanı fiziksel hareket başlangıcı değildir.")
        else:
            reasons.append("Çağrı öncesi hedef durumu geçişi doğrulayacak kadar net değil.")
    elif other and movement and baseline_ok:
        # Adult later within the same window has priority; an initial toy fixation is not a new turn.
        if other["start_s"] >= movement["start_s"] - 1/s["gaze_fps"]:
            decision = "toward_other"
    elif coverage < s["min_coverage"] or gaze_coverage < s["min_coverage"] or not baseline_ok:
        decision = "not_evaluable"
    elif not movement:
        # A no-response result additionally needs target estimates to remain unambiguous.
        clear = sum(r.get("target") not in {None,"ambiguous","unavailable","offscreen"} for r in gazepost)/max(1,len(gazepost))
        if clear >= s["min_coverage"] and not adult:
            decision = "no_orientation_observed"
        else:
            reasons.append("Baş hareketi eşiği aşılmadı fakat hedef kanıtı kesin olumsuz karar için yeterli değil.")
    if adult and not movement:
        reasons.append("Yetişkin hedefi tahmin edildi; güvenilir baş hareketi başlangıcı bulunamadı.")
    if adult:
        supporting=[g for g in gazepost if adult["start_s"]<=g["time_s"]<=adult["confirmed_s"]]
        if any(g.get("head_source")=="optical_flow" for g in supporting):
            reasons.append("Yetişkin hedefi dizisinde profil yüz nedeniyle baş kutusu optik akışla izleniyor; doğrudan yüz noktası ölçümü yok.")
    quality = "yeterli" if min(coverage,gaze_coverage) >= s["min_coverage"] and baseline_ok else "sınırlı"
    return {
        "call": call, "observation_start_s": begin, "observation_end_s": end,
        "status": decision, "label_tr": LABELS[decision],
        "movement": movement, "first_pose_deviation": first_deviation, "adult_target_run": adult,
        "movement_latency_from_start_s": round(movement["start_s"]-begin,4) if movement else None,
        "movement_latency_from_end_s": round(movement["start_s"]-call["end_s"],4) if movement else None,
        "target_latency_from_start_s": round(adult["start_s"]-begin,4) if adult else None,
        "pose_coverage": round(coverage,4), "gaze_coverage": round(gaze_coverage,4),
        "baseline_pose_samples": len(posebase), "measurement_quality": quality,
        "decision_confidence": "kalibre edilmedi", "confidence_probability": None,
        "reasons": reasons,
        "interpretation": "Çağrı sonrası görsel yönelme adayıdır; nedensellik, kesin bakış veya klinik değerlendirme değildir."
    }
