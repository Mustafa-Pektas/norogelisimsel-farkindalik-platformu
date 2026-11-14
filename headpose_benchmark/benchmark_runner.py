"""
D01 Baş Yönü ve Bakış Tahmini Kıyaslama Koşturucusu (Benchmark Runner)
- Standart D01 / Deniz Çocuk Baş Bölgesi veya Gemini Flash-Lite Otomatik ROI üzerinde çalışır.
- Hem Baştan Sona (End-to-End Wall-Clock) Toplam Süreyi hem de Kare Başına Medyan/p95 Gecikmeyi ölçer.
- Geçerli 3D Poz Kare Sayısını, Yalnız Optik Akış Kare Sayısını ve Kayıp Kare Sayısını raporlar.
- D01 V1 protokolüyle İlk Baş Dönüşünün Başlangıç (Onset), Bitiş (End) saniyelerini ve
  Çağrı Öncesi Başlangıç Pozundan Sapma Açısını (Head change deg) hesaplar.
- Her model için Sesli İşaretlenmiş Video (.mp4) üretir (--no-video ile kapatılır).
- Tüm modeller için tek dosyalık konsolide raporlar üretir (common/reporting.py; --no-report ile kapatılır):
  tum_modeller_raporu.pdf, karsilastirma_tablosu.xlsx, tum_modeller_raporu.html. Ayrık PNG yazılmaz.
"""
import os
import sys
import time
import json
import math
import argparse
from typing import List, Dict, Any, Optional
import numpy as np
import cv2

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common.types import PoseResult
from common.roi import resolve_video_roi, crop_roi_bgr
from common.d01_kinematics import evaluate_d01_turn_metrics
from common.reporting import write_reports
from common.visualizer import VideoAnnotator
from estimators.mediapipe_pnp import MediaPipePnpEstimator
from estimators.optical_flow import OpticalFlowEstimator
from estimators.hybrid_estimator import (
    MediaPipePnpLkTracker,
    HybridKeypointEstimator,
    CascadePnpRepNetEstimator,
    CascadePnpBlazeFaceEstimator,
    CascadePnpRepNetStridedEstimator,
)
from estimators.mediapipe_iris import MediaPipeIrisEstimator
from estimators.repnet360 import SixDRepNet360Estimator
from estimators.yolo_face import YOLOv8FaceEstimator
from estimators.l2cs_net import L2CSNetEstimator


def get_all_estimators():
    return [
        MediaPipePnpEstimator(filter_type="none"),
        MediaPipePnpEstimator(filter_type="1euro"),
        MediaPipePnpEstimator(filter_type="kalman"),
        MediaPipePnpLkTracker(),
        HybridKeypointEstimator(keyframe_interval=5),
        # Not: CascadePnpBlazeFaceEstimator artık MediaPipe_SolvePnP_Raw ile birebir aynıdır (köprü
        # tüm FaceMesh modellerine taşındı); yalnız ortak göz takibi için kullanılır.
        MediaPipeIrisEstimator(),
        OpticalFlowEstimator(),
        SixDRepNet360Estimator(cpu_threads=4),
        CascadePnpRepNetEstimator(),
        CascadePnpRepNetStridedEstimator(stride=4),
        CascadePnpRepNetStridedEstimator(stride=4, backend="onnx"),
        YOLOv8FaceEstimator(),
        L2CSNetEstimator(),
    ]


def run_benchmark(
    video_path: str,
    warmup_frames: int = 20,
    selected_names: Optional[List[str]] = None,
    render_videos: bool = True,
    output_dir: str = "outputs",
    custom_roi_str: Optional[str] = None,
    force_auto_roi: bool = False,
    out_path: Optional[str] = None,
    write_report: bool = True,
    reference_model: Optional[str] = None,
) -> Dict[str, Any]:
    if not os.path.exists(video_path):
        raise FileNotFoundError(f"Video bulunamadı: {video_path}")

    if render_videos or write_report:
        os.makedirs(output_dir, exist_ok=True)
    report_entries: List[Dict[str, Any]] = []
    # Ara kayıt (her model bitince) --out ile verilen dosyaya yazılır; verilmezse çıktı dizinine.
    checkpoint_path = out_path or os.path.join(output_dir, "benchmark_results.json")
    if os.path.dirname(checkpoint_path):
        os.makedirs(os.path.dirname(checkpoint_path), exist_ok=True)

    roi, video_sha256 = resolve_video_roi(video_path, custom_roi_str, force_auto=force_auto_roi)

    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise ValueError(f"Video açılamadı: {video_path}")

    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    fps = cap.get(cv2.CAP_PROP_FPS) or 24.0
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    cap.release()

    estimators = get_all_estimators()
    if selected_names:
        estimators = [e for e in estimators if any(s.lower() in e.name.lower() for s in selected_names)]

    calls = roi.get("calls") or []
    targets = roi.get("targets") or []
    call_desc_list = [f"{c.get('name')} ({c.get('start_s')}s-{c.get('end_s')}s)" for c in calls]

    print(f"\n=====================================================================", flush=True)
    print(f" D01 BAŞ YÖNÜ & BAKIŞ TAHMİNİ KIYASLAMASI (XEON E5-2699 v4 CPU)", flush=True)
    print(f" Video          : {os.path.basename(video_path)} ({width}x{height}, {fps:.1f} FPS, {total_frames} kare)", flush=True)
    print(f" Video SHA256   : {video_sha256}", flush=True)
    print(f" Baş Bölgesi ROI: x={roi['x']}, y={roi['y']}, w={roi['width']}, h={roi['height']} ({roi.get('source')})", flush=True)
    print(f" Sahne Hedefleri: {[t.get('id') for t in targets]} | Çağrılar: {call_desc_list}", flush=True)
    print(f" Isınma (Warmup): İlk {warmup_frames} kare medyan gecikme hesabından düşülecek", flush=True)
    print(f" Video & Grafik : {'AÇIK (' + output_dir + ' klasörüne sesli MP4 + PNG kaydedilecek)' if render_videos else 'KAPALI'}", flush=True)
    print(f" Aday Modeller  : {[e.name for e in estimators]}", flush=True)
    print(f"=====================================================================\n", flush=True)

    benchmark_summary: Dict[str, Any] = {
        "video": {
            "path": video_path,
            "filename": os.path.basename(video_path),
            "sha256": video_sha256,
            "total_frames": total_frames,
            "fps": fps,
            "resolution": f"{width}x{height}",
            "roi": roi,
            "warmup_frames_discarded": warmup_frames,
        },
        "models": {},
    }

    # Ortak Göz Merkezi ve Kafa Kutusu Takibi: FaceMesh gözleri, profil dönüşte BlazeFace göz
    # anahtar noktaları. Landmark/göz üretmeyen ya da gözü yalnız LK ile kaydırılmış modellerde
    # (6DRepNet360, LK, saf FaceMesh'in kayıp kareleri) pembe/turkuaz okların gözden çıkması için.
    shared_head_tracks: Dict[int, Dict[str, Any]] = {}
    eye_tracker = CascadePnpBlazeFaceEstimator()
    if eye_tracker.setup():
        cap_tr = cv2.VideoCapture(video_path)
        idx_tr = 0
        while True:
            ret_tr, frm_tr = cap_tr.read()
            if not ret_tr:
                break
            roi_tr = crop_roi_bgr(frm_tr, roi)
            res_tr = eye_tracker.predict(roi_tr, idx_tr, idx_tr / fps)
            shared_head_tracks[idx_tr] = {
                "face_bbox_roi": res_tr.metadata.get("face_bbox_roi"),
                "eyes_center_roi": res_tr.metadata.get("eyes_center_roi"),
                "nose_xy_roi": res_tr.metadata.get("nose_xy_roi"),
                "eyes_source": res_tr.metadata.get("eyes_source"),
            }
            idx_tr += 1
        cap_tr.release()
        eye_tracker.reset()

    for est in estimators:
        print(f"--> [{est.name}] hazırlanıyor...", flush=True)
        t_setup_start = time.perf_counter()
        try:
            ready = est.setup()
        except Exception as exc:
            print(f"    [UYARI] {est.name} setup hatası: {exc}", flush=True)
            ready = False
        setup_ms = (time.perf_counter() - t_setup_start) * 1000.0

        if not ready:
            print(f"    [ATLANDI] {est.name} hazır değil (isteğe bağlı model ağırlığı kurulu değil).\n", flush=True)
            benchmark_summary["models"][est.name] = {
                "status": "UNAVAILABLE",
                "reason": "Optional model weights or dependencies not installed",
            }
            report_entries.append({"name": est.name, "stat": benchmark_summary["models"][est.name], "results": None})
            continue

        # 1. AŞAMA: Saf Uçtan Uca Analiz Koşusu (Video yazma I/O yükü olmadan gerçek süre ölçümü)
        cap = cv2.VideoCapture(video_path)
        frame_idx = 0
        results: List[PoseResult] = []
        latencies_after_warmup: List[float] = []

        print(f"    Analiz başladı ({total_frames} kare, ROI={roi['width']}x{roi['height']})...", flush=True)
        t_wall_start = time.perf_counter()

        while True:
            ret, frame = cap.read()
            if not ret:
                break

            pos_msec = cap.get(cv2.CAP_PROP_POS_MSEC)
            decoder_time_s = (
                pos_msec / 1000.0
                if (isinstance(pos_msec, (int, float)) and math.isfinite(pos_msec) and pos_msec >= 0)
                else (frame_idx / fps)
            )
            if frame_idx > 0 and decoder_time_s <= 0.0:
                decoder_time_s = frame_idx / fps

            roi_bgr = crop_roi_bgr(frame, roi)
            res = est.predict(roi_bgr, frame_idx, decoder_time_s)
            res.metadata["decoder_time_s"] = round(decoder_time_s, 6)
            results.append(res)

            if frame_idx >= warmup_frames:
                latencies_after_warmup.append(res.latency_ms)

            frame_idx += 1
            if frame_idx % 10 == 0 or frame_idx == total_frames:
                print(
                    f"    Kare {frame_idx}/{total_frames} işlendi... "
                    f"(son kare: {res.latency_ms:.1f} ms, durum: {res.flag})",
                    flush=True,
                )

        total_wall_time_s = time.perf_counter() - t_wall_start
        cap.release()
        est.reset()

        # Modelin kendi gözü gerçek gözlemden (FaceMesh/BlazeFace) gelmiyorsa ortak takipten doldur
        trusted_eyes = ("landmarks", "blazeface")
        for r in results:
            tr_info = shared_head_tracks.get(r.frame_index)
            if not tr_info:
                continue
            own_trusted = r.metadata.get("eyes_source") in trusted_eyes and r.metadata.get("eyes_center_roi")
            shared_trusted = tr_info.get("eyes_source") in trusted_eyes and tr_info.get("eyes_center_roi")
            if not own_trusted and (shared_trusted or not r.metadata.get("eyes_center_roi")):
                for key in ("eyes_center_roi", "face_bbox_roi", "nose_xy_roi", "eyes_source"):
                    if tr_info.get(key) is not None:
                        r.metadata[key] = tr_info[key]
            elif not r.metadata.get("face_bbox_roi") and tr_info.get("face_bbox_roi"):
                r.metadata["face_bbox_roi"] = tr_info["face_bbox_roi"]

        # 2. AŞAMA: D01 İlk Baş Dönüşü + Çağrı Öncesi Başlangıç Pozundan Sapma (pose_change_deg) Hesabı
        turn_metrics = evaluate_d01_turn_metrics(results, fps=fps, calls=calls)

        # Bakış hedefi kalibrasyonu: çağrı öncesi medoid baş pozu (çocuk oyuncağa bakarken)
        pcs = turn_metrics.get("pose_change_summary") or {}
        if pcs.get("baseline_yaw") is not None:
            baseline_yaw = float(pcs["baseline_yaw"])
            baseline_pitch = float(pcs["baseline_pitch"])
        else:
            init_yaws = [r.yaw for r in results[:36] if r.yaw is not None and math.isfinite(r.yaw)]
            init_pitches = [r.pitch for r in results[:36] if r.pitch is not None and math.isfinite(r.pitch)]
            baseline_yaw = float(np.median(init_yaws)) if init_yaws else -20.0
            baseline_pitch = float(np.median(init_pitches)) if init_pitches else -20.0

        # 3. AŞAMA: Görselleştirilmiş Sesli .mp4 Video (grafikler konsolide raporlara gömülür)
        if render_videos:
            clean_name = est.name.replace(" ", "_")
            video_out_path = os.path.join(output_dir, f"annotated_{clean_name}.mp4")
            annotator = VideoAnnotator(
                video_out_path,
                fps,
                width,
                height,
                roi,
                source_video_path=video_path,
                baseline_yaw=baseline_yaw,
                baseline_pitch=baseline_pitch,
            )
            cap_v = cv2.VideoCapture(video_path)
            idx_v = 0
            while True:
                ret_v, frame_v = cap_v.read()
                if not ret_v or idx_v >= len(results):
                    break
                annotator.write_frame(frame_v, results[idx_v], est.name, total_frames, turn_metrics)
                idx_v += 1
            cap_v.release()
            annotator.release()
            print(f"    [VIDEO] Kaydedildi: {video_out_path}", flush=True)

        # Serileştirme öncesi ağır matris serilerini çıkar (raporlar için ayrı kopyada tutulur)
        report_turn_metrics = dict(turn_metrics)
        turn_metrics.pop("_plot_series", None)

        valid_pose_frames = turn_metrics["valid_pose_frames"]
        optical_flow_frames = turn_metrics["optical_flow_only_frames"]
        lost_frames_count = turn_metrics["lost_frames"]
        detection_rate = (valid_pose_frames / len(results) * 100.0) if results else 0.0
        lost_indices = [r.frame_index for r in results if not r.face_detected]

        if latencies_after_warmup:
            median_lat = float(np.median(latencies_after_warmup))
            p95_lat = float(np.percentile(latencies_after_warmup, 95))
            mean_lat = float(np.mean(latencies_after_warmup))
            effective_fps = 1000.0 / median_lat if median_lat > 0 else 0.0
        else:
            median_lat = p95_lat = mean_lat = effective_fps = 0.0

        sample_angles = [
            {
                "frame": r.frame_index,
                "time_s": round(r.metadata.get("decoder_time_s", r.frame_index / fps), 3),
                "yaw": round(r.yaw, 2) if r.yaw is not None else None,
                "pitch": round(r.pitch, 2) if r.pitch is not None else None,
                "roll": round(r.roll, 2) if r.roll is not None else None,
                "pose_change_deg": r.metadata.get("pose_change_deg"),
                "flag": r.flag,
            }
            for r in results[:: max(1, len(results) // 14)]
        ]

        model_stat = {
            "status": "COMPLETED",
            "setup_time_ms": round(setup_ms, 2),
            "total_frames_processed": len(results),
            "total_wall_time_s": round(total_wall_time_s, 2),
            "valid_pose_frames": valid_pose_frames,
            "optical_flow_only_frames": optical_flow_frames,
            "lost_frames_count": lost_frames_count,
            "fallback_6d_frames": turn_metrics["fallback_6d_frames"],
            "kp_bridge_frames": turn_metrics["kp_bridge_frames"],
            "face_detection_rate_pct": round(detection_rate, 2),
            "face_lost_sample_indices": lost_indices[:25],
            "pose_change_summary": turn_metrics.get("pose_change_summary"),
            "d01_first_head_turn": {
                "onset_s": turn_metrics["first_turn_onset_s"],
                "onset_confirmed_s": turn_metrics["first_turn_onset_confirmed_s"],
                "end_s": turn_metrics["first_turn_end_s"],
                "end_confirmed_s": turn_metrics["first_turn_end_confirmed_s"],
                "end_status": turn_metrics["first_turn_end_status"],
            },
            "timing_warmup_excluded": {
                "median_latency_ms": round(median_lat, 2),
                "p95_latency_ms": round(p95_lat, 2),
                "mean_latency_ms": round(mean_lat, 2),
                "effective_fps_at_median": round(effective_fps, 2),
            },
            "sample_yaw_angles": sample_angles,
        }
        benchmark_summary["models"][est.name] = model_stat
        report_entries.append({"name": est.name, "stat": model_stat, "results": results,
                               "turn_metrics": report_turn_metrics})
        with open(checkpoint_path, "w", encoding="utf-8") as f_chk:
            json.dump(benchmark_summary, f_chk, ensure_ascii=False, indent=2)
        print(
            f"    [BİTTİ] Toplam Süre: {total_wall_time_s:.2f} sn | Medyan: {median_lat:.2f} ms | "
            f"Geçerli Poz: {valid_pose_frames}/{len(results)} | Optik Akış: {optical_flow_frames} | Kayıp: {lost_frames_count} | "
            f"İlk Dönüş: {turn_metrics['first_turn_onset_s']} sn -> {turn_metrics['first_turn_end_s']} sn ({turn_metrics['first_turn_end_status']})\n",
            flush=True,
        )

    if write_report and report_entries:
        print("--> Konsolide raporlar üretiliyor (PDF / Excel / HTML)...", flush=True)
        outs = write_reports(output_dir, benchmark_summary, report_entries, fps, reference_name=reference_model)
        benchmark_summary["reports"] = outs
        for kind, p in outs.items():
            print(f"    [RAPOR] {kind.upper():5s}: {p if p else 'ATLANDI (bağımlılık eksik)'}", flush=True)

    return benchmark_summary


def print_markdown_table(summary: Dict[str, Any]):
    v = summary["video"]
    roi = v["roi"]
    print("\n=========================================================================================", flush=True)
    print(f"### BAŞ POZU & BAKIŞ KIYASLAMA TABLOSU ({v['filename']} | ROI: {roi['width']}x{roi['height']} @{roi['x']},{roi['y']})\n", flush=True)
    print(
        "| Yöntem | Baştan Sona Süre | Medyan (p95) Gecikme | Geçerli Poz / Optik Akış / Kayıp | Maks Sapma (12° İlk Sapma) | Dönüş Başlangıç -> Bitiş |",
        flush=True,
    )
    print("| :--- | :--- | :--- | :--- | :--- | :--- |", flush=True)

    for name, data in summary.get("models", {}).items():
        if data.get("status") != "COMPLETED":
            continue
        t = data["timing_warmup_excluded"]
        d01 = data["d01_first_head_turn"]
        pchg = data.get("pose_change_summary") or {}
        max_deg = pchg.get("max_post_call_pose_change_deg")
        dev12_s = pchg.get("first_12deg_deviation_s")
        if max_deg is not None:
            dev_str = f"{max_deg:.1f}° ({dev12_s:.2f} sn)" if dev12_s is not None else f"{max_deg:.1f}° (-)"
        else:
            dev_str = "-"

        onset_str = f"{d01['onset_s']:.2f} sn" if d01["onset_s"] is not None else "Bulunamadı"
        if d01["end_s"] is not None:
            end_str = f"**{d01['end_s']:.2f} sn**"
        else:
            end_str = f"Ölçülemedi (*{d01['end_status']}*)"

        fb_note = f" (+{data['fallback_6d_frames']} kare 6D)" if data.get("fallback_6d_frames", 0) > 0 else ""
        if data.get("kp_bridge_frames", 0) > 0:
            fb_note += f" (+{data['kp_bridge_frames']} kare KP köprü)"
        counts_str = f"{data['valid_pose_frames']} poz / {data['optical_flow_only_frames']} akış / {data['lost_frames_count']} kayıp{fb_note}"

        print(
            f"| **{name}** | {data['total_wall_time_s']:.2f} sn | {t['median_latency_ms']} ms ({t['p95_latency_ms']} ms) | {counts_str} | {dev_str} | {onset_str} -> {end_str} |",
            flush=True,
        )
    print("=========================================================================================\n", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="D01 Baş Yönü Kıyaslama Koşturucusu")
    parser.add_argument("--video", type=str, required=True, help="Test video dosyası yolu (.mp4)")
    parser.add_argument("--warmup", type=int, default=20, help="Süreye katılmayacak ilk ısınma karesi sayısı (varsayılan: 20)")
    parser.add_argument("--roi", type=str, default=None, help="Özel ROI: x,y,width,height (örn: 220,140,320,320)")
    parser.add_argument("--auto-roi", action="store_true", help="Sabit profil yerine Gemini Flash-Lite ile çocuk ROI'sini otomatik bul")
    parser.add_argument("--models", nargs="*", default=None, help="Yalnızca belirtilen modelleri çalıştır")
    parser.add_argument("--out", type=str, default="benchmark_results.json", help="Çıktı JSON dosya yolu")
    parser.add_argument("--output-dir", type=str, default="outputs", help="Görselleştirilmiş videoların kaydedileceği dizin")
    parser.add_argument("--no-video", action="store_true", help="Görselleştirilmiş video kaydetmeyi kapat")
    parser.add_argument("--no-report", action="store_true", help="PDF / Excel / HTML konsolide raporlarını üretme")
    parser.add_argument("--reference-model", type=str, default=None,
                        help="Uyum ölçütü için referans model adı (varsayılan: 6DRepNet360_Heavy_Reference, yoksa Cascade_PnP_to_6DRepNet360)")

    args = parser.parse_args()
    res = run_benchmark(
        video_path=args.video,
        warmup_frames=args.warmup,
        selected_names=args.models,
        render_videos=not args.no_video,
        output_dir=args.output_dir,
        custom_roi_str=args.roi,
        force_auto_roi=args.auto_roi,
        out_path=args.out,
        write_report=not args.no_report,
        reference_model=args.reference_model,
    )
    print_markdown_table(res)

    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(res, f, ensure_ascii=False, indent=2)
    print(f"Ayrıntılı sonuçlar kaydedildi: {args.out}", flush=True)
