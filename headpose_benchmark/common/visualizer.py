"""
Görselleştirme ve Sesli Video Çıktısı Üretici (Annotated Video Writer + FFmpeg Audio Muxer).
- Gereksiz X/Y/Z koordinat eksenleri kaldırıldı (sade ve net görünüm).
- Pembe bakış oku ve bakış noktasındaki hedef halkası HER ZAMAN çocuğun gözlerinin ortasından çıkar.
- Bakış hedefi ('toy' veya 'adult_face') başlangıç oturuş pozuna göre kalibre edilir ve
  zamansal yumuşatma (EMA) ile titreme/yanlış yere gitme tamamen engellenir.
- Orijinal video sesini koruyan otomatik FFmpeg H.264 + AAC birleştirici içerir.
"""
import os
import math
import shutil
import subprocess
from typing import Dict, Any, Optional, List
import numpy as np
import cv2

from common.types import PoseResult
from common.geometry import estimate_scene_gaze_target


TARGET_COLORS = {
    "adult_face": (90, 220, 80),
    "toy": (0, 180, 255),
}


def _draw_tight_face_box(frame: np.ndarray, x1: int, y1: int, x2: int, y2: int, color: tuple):
    """Yüzü/kafayı tam saran ince çerçeve ve belirgin köşe braketleri çizer."""
    cv2.rectangle(frame, (x1, y1), (x2, y2), color, 1, cv2.LINE_AA)
    clen = max(8, min(18, (x2 - x1) // 5))
    t = 2
    # Sol-Üst
    cv2.line(frame, (x1, y1), (x1 + clen, y1), color, t, cv2.LINE_AA)
    cv2.line(frame, (x1, y1), (x1, y1 + clen), color, t, cv2.LINE_AA)
    # Sağ-Üst
    cv2.line(frame, (x2, y1), (x2 - clen, y1), color, t, cv2.LINE_AA)
    cv2.line(frame, (x2, y1), (x2, y1 + clen), color, t, cv2.LINE_AA)
    # Sol-Alt
    cv2.line(frame, (x1, y2), (x1 + clen, y2), color, t, cv2.LINE_AA)
    cv2.line(frame, (x1, y2), (x1, y2 - clen), color, t, cv2.LINE_AA)
    # Sağ-Alt
    cv2.line(frame, (x2, y2), (x2 - clen, y2), color, t, cv2.LINE_AA)
    cv2.line(frame, (x2, y2), (x2, y2 - clen), color, t, cv2.LINE_AA)


def _draw_gaze_target_and_arrows(
    frame: np.ndarray,
    eye_x: int,
    eye_y: int,
    arrow_end: Optional[List[int]],
    gaze_pt: Optional[List[int]],
    target_label: str,
):
    """
    Göz merkezinden (eye_x, eye_y) çıkan:
    1) Pembe Bakış Oku + Hedef Noktasındaki Düzgün Çift Halka (Target Reticle)
    2) Kısa Turkuaz Baş Yönü Oku
    (X/Y/Z koordinat düzlemi karmaşası olmadan temiz çizim)
    """
    # 1. Pembe Bakış Hattı ve Hedef Noktası Yuvarlağı (Yalnızca doğrulanmış bir hedefe bakıyorsa çizilir)
    if gaze_pt is not None and len(gaze_pt) == 2 and target_label in ("toy", "adult_face"):
        gx, gy = int(gaze_pt[0]), int(gaze_pt[1])
        # Gözden hedefe giden koyu dış konturlu parlak pembe/eflatun ok
        cv2.arrowedLine(
            frame,
            (eye_x, eye_y),
            (gx, gy),
            (40, 0, 50),
            4,
            cv2.LINE_AA,
            tipLength=0.04,
        )
        cv2.arrowedLine(
            frame,
            (eye_x, eye_y),
            (gx, gy),
            (255, 50, 255),
            2,
            cv2.LINE_AA,
            tipLength=0.04,
        )
        # Bakış noktasındaki düzgün çift katmanlı hedef yuvarlağı
        cv2.circle(frame, (gx, gy), 14, (45, 0, 55), 3, cv2.LINE_AA)
        cv2.circle(frame, (gx, gy), 14, (255, 60, 255), 2, cv2.LINE_AA)
        cv2.circle(frame, (gx, gy), 4, (255, 230, 255), -1, cv2.LINE_AA)

    # 2. Göz Merkezinden Çıkan Kısa Baş Yönü Oku (Turkuaz)
    if arrow_end is not None and len(arrow_end) == 2:
        ax, ay = int(arrow_end[0]), int(arrow_end[1])
        cv2.arrowedLine(
            frame,
            (eye_x, eye_y),
            (ax, ay),
            (0, 0, 0),
            5,
            cv2.LINE_AA,
            tipLength=0.24,
        )
        cv2.arrowedLine(
            frame,
            (eye_x, eye_y),
            (ax, ay),
            (255, 215, 0),
            3,
            cv2.LINE_AA,
            tipLength=0.24,
        )

    # Göz merkezi başlangıç noktası (Sarı-Beyaz odak noktası)
    cv2.circle(frame, (eye_x, eye_y), 5, (20, 20, 20), -1, cv2.LINE_AA)
    cv2.circle(frame, (eye_x, eye_y), 3, (0, 255, 255), -1, cv2.LINE_AA)


def render_hud_overlay(
    frame: np.ndarray,
    result: PoseResult,
    model_name: str,
    fps: float,
    total_frames: int,
    roi: Dict[str, Any],
    turn_metrics: Optional[Dict[str, Any]] = None,
    smoothed_state: Optional[Dict[str, Any]] = None,
) -> np.ndarray:
    """
    Videonun üstüne sahne hedef kutularını (adult_face, toy), ROI kutusunu,
    dinamik kafa kutusunu, yüz/göz noktalarını ve göz merkezinden çıkan bakış okunu çizer.
    """
    out = frame.copy()
    h, w = out.shape[:2]

    rx = max(0, int(roi["x"]))
    ry = max(0, int(roi["y"]))
    rw = int(roi["width"])
    rh = int(roi["height"])
    targets = roi.get("targets") or []
    calls = roi.get("calls") or []

    # 0. Sahne Hedef Kutuları (adult_face ve toy)
    for t in targets:
        t_id = t.get("id", "target")
        if t_id not in TARGET_COLORS:
            continue
        bbox = t.get("bbox")
        if not bbox or len(bbox) != 4:
            continue
        tx1, ty1 = int(round(bbox[0] * w)), int(round(bbox[1] * h))
        tx2, ty2 = int(round(bbox[2] * w)), int(round(bbox[3] * h))
        t_col = TARGET_COLORS[t_id]
        cv2.rectangle(out, (tx1, ty1), (tx2, ty2), t_col, 2, cv2.LINE_AA)
        cv2.putText(
            out,
            t_id,
            (tx1, max(108, ty1 - 7)),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.55,
            t_col,
            2,
            cv2.LINE_AA,
        )

    child_track = result.metadata.get("child_track", "landmarks" if result.face_detected else "lost")
    if result.face_detected:
        if result.flag == "FALLBACK_6DREPNET":
            box_color = (0, 200, 255)  # Kehribar / Turuncu
            status_text = "6DREPNET FALLBACK AKTIF"
        elif result.metadata.get("used_kp_bridge"):
            box_color = (255, 120, 220)  # Eflatun
            status_text = f"BLAZEFACE KP KOPRUSU ({result.flag})"
        else:
            box_color = (0, 255, 100)  # Yeşil
            status_text = f"3D POZ GECERLI ({result.flag})"
    elif result.flag in ("OPTICAL_FLOW_ROI_ONLY", "OPTICAL_FLOW_INTERPOLATED") or child_track == "optical_flow_box":
        box_color = (255, 200, 0)      # Turkuaz
        status_text = "OPTIK AKIS KUTU TAKIBI (PROFIL / 3D NOKTA YOK)"
    else:
        box_color = (0, 40, 255)       # Kırmızı
        status_text = f"YUZ / TAKIP KAYIP ({result.flag})"

    # 1. Dış Sabit Çocuk Baş Bölgesi (ROI) Kutusu
    cv2.rectangle(out, (rx, ry), (min(w - 1, rx + rw), min(h - 1, ry + rh)), box_color, 2, cv2.LINE_AA)
    cv2.putText(
        out,
        f"D01 ROI ({rw}x{rh})",
        (rx, max(108, ry - 8)),
        cv2.FONT_HERSHEY_DUPLEX,
        0.5,
        box_color,
        1,
        cv2.LINE_AA,
    )

    # 2. Dinamik Dar Kafa Kutusu ve Göz Merkezi (Eye Origin) Hesabı
    face_bbox = result.metadata.get("face_bbox_roi")
    eyes_roi = result.metadata.get("eyes_center_roi")

    if face_bbox and len(face_bbox) == 4:
        fx1 = int(roi["x"] + face_bbox[0])
        fy1 = int(roi["y"] + face_bbox[1])
        fx2 = int(roi["x"] + face_bbox[2])
        fy2 = int(roi["y"] + face_bbox[3])
        tight_col = (0, 255, 255) if result.face_detected else (255, 190, 0)
        _draw_tight_face_box(out, fx1, fy1, fx2, fy2, tight_col)
    else:
        fx1 = int(roi["x"] + rw * 0.16)
        fy1 = int(roi["y"] + rh * 0.18)
        fx2 = int(roi["x"] + rw * 0.68)
        fy2 = int(roi["y"] + rh * 0.82)
        if result.face_detected:
            _draw_tight_face_box(out, fx1, fy1, fx2, fy2, (0, 230, 255))

    # Göz Merkezini (eye_cx, eye_cy) belirle. Öncelik: gözlemlenmiş göz noktası (FaceMesh iris/göz
    # köşeleri; profilde BlazeFace göz anahtar noktaları — iki göz görünür göze çakışır). Koşucu,
    # gözü olmayan modellere ortak FaceMesh/BlazeFace takibini zaten doldurur.
    if eyes_roi and len(eyes_roi) == 2:
        raw_eye_x = float(roi["x"] + eyes_roi[0])
        raw_eye_y = float(roi["y"] + eyes_roi[1])
    elif face_bbox and len(face_bbox) == 4:
        yaw_val = result.yaw if result.yaw is not None else -20.0
        # Sağa profil dönüşte gözler kafa kutusunun sağ-orta kısmındadır (anatomik göz konumu)
        horiz_ratio = float(np.clip(0.52 + (-yaw_val / 90.0) * 0.22, 0.28, 0.74))
        raw_eye_x = float(fx1 + (fx2 - fx1) * horiz_ratio)
        raw_eye_y = float(fy1 + (fy2 - fy1) * 0.48)
    else:
        raw_eye_x = float((fx1 + fx2) * 0.5)
        raw_eye_y = float(fy1 + (fy2 - fy1) * 0.48)

    # Göz merkezini zamansal olarak yumuşat (titremeyi önler)
    if smoothed_state is not None:
        if smoothed_state.get("eye_xy") is None:
            smoothed_state["eye_xy"] = [raw_eye_x, raw_eye_y]
        else:
            smoothed_state["eye_xy"][0] = 0.60 * raw_eye_x + 0.40 * smoothed_state["eye_xy"][0]
            smoothed_state["eye_xy"][1] = 0.60 * raw_eye_y + 0.40 * smoothed_state["eye_xy"][1]
        eye_cx = int(round(smoothed_state["eye_xy"][0]))
        eye_cy = int(round(smoothed_state["eye_xy"][1]))
    else:
        eye_cx = int(round(raw_eye_x))
        eye_cy = int(round(raw_eye_y))

    # 3. Yüz Landmark Noktaları ve Göz Bebekleri (Iris)
    lm_pts: Optional[List[List[float]]] = result.metadata.get("landmarks_draw_roi")
    if lm_pts:
        for pt in lm_pts:
            px = int(roi["x"] + pt[0])
            py = int(roi["y"] + pt[1])
            cv2.circle(out, (px, py), 2, (120, 255, 120), -1, cv2.LINE_AA)

    iris_pts: Optional[List[List[float]]] = result.metadata.get("iris_pts_roi")
    if iris_pts:
        for ipt in iris_pts:
            ix = int(roi["x"] + ipt[0])
            iy = int(roi["y"] + ipt[1])
            cv2.circle(out, (ix, iy), 4, (255, 0, 255), 1, cv2.LINE_AA)
            cv2.circle(out, (ix, iy), 2, (0, 255, 255), -1, cv2.LINE_AA)

    # 4. Göz Merkezinden Çıkan Pembe Bakış Oku + Hedef Yuvarlağı ve Baş Yönü Oku
    #    Hedef: histerezisli toy <-> adult_face durum makinesi (geometry.select_gaze_target).
    #    Pembe uç yalnız doğrulanmış hedef noktasına kilitlenir (hedefler arasında boşluktan geçmez);
    #    yumuşak geçişi pozdan sürekli dönen turkuaz baş yönü oku gösterir. Poz yoksa son hedef yalnız
    #    MAX_HOLD_FRAMES kare korunur (tek karelik düşüşler), sonra pembe ok gizlenir.
    MAX_HOLD_FRAMES = 1
    state = smoothed_state if smoothed_state is not None else {}
    target_label = "unavailable"
    g_pt: Optional[List[int]] = None
    arrow_end: Optional[List[int]] = None
    if result.yaw is not None and result.pitch is not None:
        gaze_yaw_eff = result.gaze_yaw if result.gaze_yaw is not None else result.yaw
        gaze_pitch_eff = result.gaze_pitch if result.gaze_pitch is not None else result.pitch
        gaze_info = estimate_scene_gaze_target(
            float(eye_cx),
            float(eye_cy),
            gaze_yaw_eff,
            gaze_pitch_eff,
            w,
            h,
            targets,
            pose_change_deg=result.metadata.get("pose_change_deg"),
            baseline_yaw=float(state.get("baseline_yaw", -20.0)),
            baseline_pitch=float(state.get("baseline_pitch", -20.0)),
            prev_target=state.get("last_target"),
        )
        target_label = gaze_info.get("target", "none")
        raw_g_pt = gaze_info.get("gaze_point_px")
        arrow_end = gaze_info.get("arrow_end_px")
        state["hold_frames"] = 0
    elif state.get("last_target") in ("toy", "adult_face") and state.get("hold_frames", 0) < MAX_HOLD_FRAMES:
        # Poz geçici yok: son doğrulanmış hedefi koru
        state["hold_frames"] = state.get("hold_frames", 0) + 1
        target_label = state["last_target"]
        raw_g_pt = state.get("target_xy")
    else:
        raw_g_pt = None

    if target_label in ("toy", "adult_face") and raw_g_pt:
        state["last_target"] = target_label
        state["target_xy"] = list(raw_g_pt)
        g_pt = [int(raw_g_pt[0]), int(raw_g_pt[1])]
    elif target_label not in ("toy", "adult_face"):
        state["last_target"] = None
        state["target_xy"] = None

    # Turkuaz baş yönü okunu zamanda yumuşat (yön vektörü EMA)
    if arrow_end is not None:
        vx, vy = arrow_end[0] - eye_cx, arrow_end[1] - eye_cy
        n = max(1e-4, math.hypot(vx, vy))
        ux, uy = vx / n, vy / n
        if state.get("head_dir") is not None:
            ux = 0.5 * ux + 0.5 * state["head_dir"][0]
            uy = 0.5 * uy + 0.5 * state["head_dir"][1]
            n2 = max(1e-4, math.hypot(ux, uy))
            ux, uy = ux / n2, uy / n2
        state["head_dir"] = [ux, uy]
        arrow_end = [int(round(eye_cx + ux * 95.0)), int(round(eye_cy + uy * 95.0))]
    else:
        state["head_dir"] = None

    if arrow_end is not None or g_pt is not None:
        _draw_gaze_target_and_arrows(out, eye_cx, eye_cy, arrow_end, g_pt, target_label)

    # 5. Üst Yarı-Saydam Telemetri Bandı (HUD)
    overlay = out.copy()
    cv2.rectangle(overlay, (0, 0), (w, 96), (18, 20, 28), -1)
    cv2.addWeighted(overlay, 0.82, out, 0.18, 0, out)

    t_sec = result.metadata.get("decoder_time_s", result.frame_index / fps)
    active_calls = [c.get("name", "Call") for c in calls if float(c.get("start_s", -1)) <= t_sec <= float(c.get("end_s", -1))]
    call_str = active_calls[0] if active_calls else "-"
    call_col = (0, 255, 255) if active_calls else (200, 205, 215)

    cv2.putText(
        out,
        f"MODEL: {model_name}",
        (15, 26),
        cv2.FONT_HERSHEY_DUPLEX,
        0.62,
        (255, 255, 255),
        1,
        cv2.LINE_AA,
    )
    cv2.putText(
        out,
        f"CALL: {call_str} | Hedef: {target_label}",
        (450, 26),
        cv2.FONT_HERSHEY_DUPLEX,
        0.58,
        call_col,
        1,
        cv2.LINE_AA,
    )
    cv2.putText(
        out,
        f"Kare: {result.frame_index:03d}/{total_frames} | t={t_sec:.2f}s",
        (w - 290, 26),
        cv2.FONT_HERSHEY_DUPLEX,
        0.55,
        (215, 220, 225),
        1,
        cv2.LINE_AA,
    )

    cv2.circle(out, (22, 56), 6, box_color, -1, cv2.LINE_AA)
    cv2.putText(out, status_text, (36, 60), cv2.FONT_HERSHEY_DUPLEX, 0.50, box_color, 1, cv2.LINE_AA)

    if result.yaw is not None:
        angle_str = f"Yaw: {result.yaw:+.1f} | Pitch: {(result.pitch or 0.0):+.1f} | Roll: {(result.roll or 0.0):+.1f} deg"
        cv2.putText(out, angle_str, (450, 60), cv2.FONT_HERSHEY_DUPLEX, 0.54, (0, 255, 255), 1, cv2.LINE_AA)

    cv2.putText(
        out,
        f"{result.latency_ms:.1f} ms",
        (w - 115, 60),
        cv2.FONT_HERSHEY_DUPLEX,
        0.58,
        (180, 255, 180),
        1,
        cv2.LINE_AA,
    )

    pose_chg = result.metadata.get("pose_change_deg")
    reproj_px = result.metadata.get("pose_reprojection_px")
    chg_text = f"{pose_chg:.1f} deg" if pose_chg is not None else "yok"
    rep_text = f"{reproj_px:.2f} px" if reproj_px is not None else "-"
    sub_hud = f"Baslangic Pozundan Sapma (Head change): {chg_text} | SQPnP Reproj: {rep_text} | Pembe Ok: Gozden Bakis Hedefi"
    cv2.putText(out, sub_hud, (18, 86), cv2.FONT_HERSHEY_SIMPLEX, 0.50, (175, 210, 245), 1, cv2.LINE_AA)

    # 6. Alt Bilgi Barı
    if turn_metrics is not None:
        onset = turn_metrics.get("first_turn_onset_s")
        end = turn_metrics.get("first_turn_end_s")
        onset_str = f"{onset:.2f} sn" if onset is not None else "Bulunamadi"
        end_str = f"{end:.2f} sn" if end is not None else f"Olculemedi ({turn_metrics.get('first_turn_end_status')})"
        summary_str = f"Ilk Bas Donusu -> Baslangic: {onset_str} | Bitis: {end_str}"
        cv2.rectangle(out, (10, h - 38), (650, h - 8), (20, 20, 20), -1)
        cv2.putText(out, summary_str, (18, h - 17), cv2.FONT_HERSHEY_DUPLEX, 0.52, (0, 230, 255), 1, cv2.LINE_AA)

    if result.gaze_yaw is not None:
        gaze_str = f"Iris Gaze Yaw: {result.gaze_yaw:+.1f} deg"
        cv2.rectangle(out, (w - 300, h - 38), (w - 10, h - 8), (20, 20, 20), -1)
        cv2.putText(out, gaze_str, (w - 290, h - 17), cv2.FONT_HERSHEY_DUPLEX, 0.55, (0, 180, 255), 1, cv2.LINE_AA)

    return out


class VideoAnnotator:
    def __init__(
        self,
        output_path: str,
        fps: float,
        width: int,
        height: int,
        roi: Dict[str, Any],
        source_video_path: Optional[str] = None,
        baseline_yaw: float = -20.0,
        baseline_pitch: float = -20.0,
    ):
        self.output_path = output_path
        self.source_video_path = source_video_path
        self.fps = fps
        self.width = width
        self.height = height
        self.roi = roi
        self.smoothed_state: Dict[str, Any] = {
            "eye_xy": None,
            "gaze_xy": None,
            "last_target": None,
            "target_xy": None,
            "hold_frames": 0,
            "head_dir": None,
            "baseline_yaw": baseline_yaw,
            "baseline_pitch": baseline_pitch,
        }
        self.temp_silent_path = output_path + ".silent_tmp.mp4"
        fourcc = cv2.VideoWriter_fourcc(*"mp4v")
        self.writer = cv2.VideoWriter(self.temp_silent_path, fourcc, fps, (width, height))

    def write_frame(
        self,
        frame_bgr: np.ndarray,
        result: PoseResult,
        model_name: str,
        total_frames: int,
        turn_metrics: Optional[Dict[str, Any]] = None,
    ):
        annotated = render_hud_overlay(
            frame_bgr,
            result,
            model_name,
            self.fps,
            total_frames,
            self.roi,
            turn_metrics,
            self.smoothed_state,
        )
        self.writer.write(annotated)

    def release(self):
        if self.writer is not None:
            self.writer.release()
            self.writer = None

        if not os.path.exists(self.temp_silent_path):
            return

        ffmpeg_exe = shutil.which("ffmpeg")
        if ffmpeg_exe and self.source_video_path and os.path.exists(self.source_video_path):
            try:
                subprocess.run(
                    [
                        ffmpeg_exe,
                        "-y",
                        "-v",
                        "error",
                        "-i",
                        self.temp_silent_path,
                        "-i",
                        self.source_video_path,
                        "-map",
                        "0:v:0",
                        "-map",
                        "1:a:0?",
                        "-c:v",
                        "libx264",
                        "-pix_fmt",
                        "yuv420p",
                        "-crf",
                        "20",
                        "-c:a",
                        "aac",
                        "-movflags",
                        "+faststart",
                        self.output_path,
                    ],
                    check=True,
                )
                os.remove(self.temp_silent_path)
                return
            except Exception as exc:
                print(f"    [FFmpeg Ses Birleştirme Uyarı]: {exc}", flush=True)

        if os.path.exists(self.output_path):
            os.remove(self.output_path)
        os.replace(self.temp_silent_path, self.output_path)
