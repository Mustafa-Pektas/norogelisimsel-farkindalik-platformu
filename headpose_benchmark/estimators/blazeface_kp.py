"""
BlazeFace (MediaPipe FaceDetection, kısa menzil) 6 anahtar noktasıyla profil dönüşlerinde süren
hızlı baş pozu köprüsü (Keypoint Pose Bridge).

Neden: MediaPipe FaceMesh ~60° üstü profil dönüşlerinde yüz noktalarını kaybeder (Deniz videosu
85–134. kareler). Lucas-Kanade piksel kayması ise kafa ötelemesini (2–4 px/kare) dönme sanar.
BlazeFace aynı karelerde yüzü ~0.9 skorla bulmaya devam eder ve anahtar noktaları dönüşü taşır:
  - Göz arası mesafe / yüz kutusu yüksekliği  -> |yaw| = acos(oran / E0)   (E0: önden oran, kalibre)
  - Burunun göz ortasına göre yatay işareti      -> yaw işareti
  - Kulak ortası -> burun vektörünün eğimi (phi) -> profilde baş kaldırma/indirme (pitch)
  - Göz çizgisinin açısı                         -> önden görünümde yuvarlanma (roll)

Pozlar her zaman SON GÜVENİLİR FaceMesh karesine (çapa) göre GÖRELİ hesaplanır; böylece FaceMesh ->
köprü -> FaceMesh geçişlerinde SO(3) matris dizisi kesintisiz kalır ve açısal hız hesaplanabilir.
CPU gecikmesi ~2 ms (360x360 ROI).
"""
import math
from collections import deque
from typing import Optional, Dict, Any, List

import numpy as np
import cv2

from common.types import PoseResult
from common.geometry import euler_to_rotation_matrix


DEFAULT_FRONTAL_EYE_RATIO = 0.40      # Önden göz arası / yüz yüksekliği (kalibrasyon yoksa)
PROFILE_ENTER_YAW_DEG = 62.0          # Bu |yaw| üstünde FaceMesh yerine köprü kullanılır
PROFILE_EXIT_YAW_DEG = 55.0           # Bu |yaw| altına inince FaceMesh'e geri dönülür (histerezis)


def _wrap_deg(a: float) -> float:
    return (a + 180.0) % 360.0 - 180.0


class _CausalSmoother:
    """Nedensel 3'lü medyan + üstel ortalama (tek başına sıçrayan anahtar nokta gürültüsünü bastırır)."""

    def __init__(self, alpha: float = 0.6, wrap: bool = False):
        self.alpha = alpha
        self.wrap = wrap
        self.hist: deque = deque(maxlen=3)
        self.value: Optional[float] = None

    def __call__(self, x: float) -> float:
        if self.wrap and self.value is not None:
            x = self.value + _wrap_deg(x - self.value)
        self.hist.append(x)
        med = float(np.median(self.hist))
        self.value = med if self.value is None else self.alpha * med + (1.0 - self.alpha) * self.value
        return self.value

    def reset(self):
        self.hist.clear()
        self.value = None


class KeypointPoseBridge:
    def __init__(self, min_detection_confidence: float = 0.3, model_selection: int = 0,
                 frontal_deadband_deg: float = 0.0):
        self.min_conf = min_detection_confidence
        self.model_selection = model_selection
        # Profil dışındayken çapadan bu kadar küçük KP açı değişimleri yok sayılır (seyrek FaceMesh
        # çapalı hibritte anahtar kareler arası testere dişi sahte hızı önler; büyük dönüşler geçer).
        self.frontal_deadband = float(frontal_deadband_deg)
        self.detector = None
        self.e0_samples: deque = deque(maxlen=40)
        self.anchor: Optional[Dict[str, float]] = None
        self.profile_mode = False
        self.ratio_max = 0.0          # Gözlenen en büyük (yumuşatılmış) göz oranı: E0 alt sınırı
        self._sign = -1.0             # Yaw işareti (histerezisli; burun göz ortasına çok yakınken korunur)
        self._s_ratio = _CausalSmoother(0.6)
        self._s_side = _CausalSmoother(0.6)
        self._s_phi = _CausalSmoother(0.6, wrap=True)
        self._s_eyeline = _CausalSmoother(0.6, wrap=True)

    # ------------------------------------------------------------------ kurulum
    def setup(self) -> bool:
        try:
            try:
                from mediapipe.python.solutions import face_detection as mp_fd
            except Exception:
                import mediapipe as mp
                mp_fd = mp.solutions.face_detection
            self.detector = mp_fd.FaceDetection(
                model_selection=self.model_selection,
                min_detection_confidence=self.min_conf,
            )
            return True
        except Exception as exc:
            print(f"    [BlazeFace Setup Hatası]: {exc}")
            self.detector = None
            return False

    def reset(self):
        self.anchor = None
        self.profile_mode = False
        self.ratio_max = 0.0
        self._sign = -1.0
        self.e0_samples.clear()
        for s in (self._s_ratio, self._s_side, self._s_phi, self._s_eyeline):
            s.reset()

    # ------------------------------------------------------------------ gözlem
    def detect(self, roi_bgr: np.ndarray) -> Optional[Dict[str, Any]]:
        """Tek kare anahtar nokta gözlemi; yumuşatılmış ipuçlarını ve çizim/göz bilgisini döner."""
        if self.detector is None:
            return None
        h, w = roi_bgr.shape[:2]
        res = self.detector.process(cv2.cvtColor(roi_bgr, cv2.COLOR_BGR2RGB))
        if not res.detections:
            return None
        det = max(res.detections, key=lambda d: d.score[0])
        bb = det.location_data.relative_bounding_box
        box_w, box_h = bb.width * w, bb.height * h
        if box_h < 8.0:
            return None
        kps = [np.array([p.x * w, p.y * h], dtype=np.float64) for p in det.location_data.relative_keypoints]
        if len(kps) < 6:
            return None
        r_eye, l_eye, nose, mouth, r_ear, l_ear = kps[:6]
        eye_mid = 0.5 * (r_eye + l_eye)
        ear_mid = 0.5 * (r_ear + l_ear)

        ratio = float(np.linalg.norm(l_eye - r_eye) / box_h)
        side = float((nose[0] - eye_mid[0]) / box_h)        # +: burun göz ortasının sağında
        phi = math.degrees(math.atan2(ear_mid[1] - nose[1], abs(nose[0] - ear_mid[0]) + 1e-3))
        eyeline = math.degrees(math.atan2(l_eye[1] - r_eye[1], l_eye[0] - r_eye[0]))

        x1, y1 = bb.xmin * w, bb.ymin * h
        face_bbox = [
            float(max(0.0, x1 - 0.12 * box_w)),
            float(max(0.0, y1 - 0.30 * box_h)),
            float(min(w - 1.0, x1 + 1.12 * box_w)),
            float(min(h - 1.0, y1 + 1.06 * box_h)),
        ]
        s_ratio = self._s_ratio(ratio)
        s_side = self._s_side(side)
        self.ratio_max = max(self.ratio_max, s_ratio)
        if abs(s_side) > 0.03:
            self._sign = -1.0 if s_side > 0 else 1.0
        return {
            "score": float(det.score[0]),
            "ratio": s_ratio,
            "side": s_side,
            "sign": self._sign,
            "phi": self._s_phi(phi),
            "eyeline": self._s_eyeline(eyeline),
            "raw_ratio": ratio,
            "eyes_center_roi": [float(eye_mid[0]), float(eye_mid[1])],
            "nose_xy_roi": [float(nose[0]), float(nose[1])],
            "face_bbox_roi": face_bbox,
            "landmarks_draw_roi": [[float(p[0]), float(p[1])] for p in kps[:6]],
        }

    # ------------------------------------------------------------------ geometri
    @property
    def e0(self) -> float:
        """
        Önden göz oranı. Anahtar nokta hataları oranı hep KÜÇÜLTÜR (göz noktası kayması/örtüşme),
        bu yüzden medyan yerine üst yüzdelik ve gözlenen en büyük oran alt sınır olarak kullanılır.
        """
        # Önden oran için fiziksel alt sınır (BlazeFace kutusunda çocuk yüzü ≈ 0.40); videonun başında
        # yalnız yan bakan karelerden kalibre edilip düşük kalırsa yaw'ı küçük gösterir.
        est = DEFAULT_FRONTAL_EYE_RATIO
        if len(self.e0_samples) >= 3:
            est = max(est, float(np.percentile(self.e0_samples, 80)))
        est = max(est, 0.95 * self.ratio_max)
        return float(np.clip(est, 0.25, 0.60))

    def signed_yaw(self, obs: Dict[str, Any]) -> float:
        """Göz arası orandan |yaw|, burun konumundan işaret (sağa burun -> negatif yaw)."""
        mag = math.degrees(math.acos(float(np.clip(obs["ratio"] / self.e0, 0.0, 1.0))))
        return float(obs.get("sign", -1.0 if obs["side"] > 0 else 1.0)) * mag

    def wants_profile(self, obs: Optional[Dict[str, Any]], landmark_yaw: Optional[float] = None) -> bool:
        """
        Histerezisli profil kararı: FaceMesh bu karede güvenilir mi?
        Giriş için KP |yaw| ≥ 62° yetmez; FaceMesh de dönüşü görüyor olmalı (|yaw| ≥ 55°) ya da yüzü
        kaybetmiş olmalı. Çıkış: KP |yaw| ≤ 55° veya FaceMesh yüzü |yaw| < 50° ile görüyor.
        Not: Kafa çok öne eğikken (pitch ≲ -45°) göz oranı küçülür ve KP yaw'ı abartır; bu yüzden
        FaceMesh'in görüşü karar için baskındır.
        """
        if obs is None:
            return self.profile_mode
        mag = abs(self.signed_yaw(obs))
        if self.profile_mode:
            mesh_frontal = landmark_yaw is not None and abs(landmark_yaw) < 50.0
            self.profile_mode = mag > PROFILE_EXIT_YAW_DEG and not mesh_frontal
        else:
            mesh_agrees = landmark_yaw is None or abs(landmark_yaw) >= 55.0
            self.profile_mode = mag >= PROFILE_ENTER_YAW_DEG and mesh_agrees
        return self.profile_mode

    def set_anchor(self, obs: Dict[str, Any], yaw: float, pitch: float, roll: float):
        """FaceMesh'in güvenilir olduğu karede çapayı ve E0 kalibrasyonunu günceller."""
        if abs(yaw) <= 50.0:
            c = math.cos(math.radians(yaw))
            if c > 0.3:
                self.e0_samples.append(obs["ratio"] / c)
        self.anchor = {
            "yaw": float(yaw), "pitch": float(pitch), "roll": float(roll),
            "yaw_kp": self.signed_yaw(obs), "phi": obs["phi"], "eyeline": obs["eyeline"],
        }

    def pose(self, obs: Dict[str, Any]) -> Dict[str, Any]:
        """Çapaya göre göreli (yaw, pitch, roll) ve SO(3) matrisi."""
        yaw_now = self.signed_yaw(obs)
        if self.anchor is None:
            # Hiç FaceMesh çapası yoksa (video profilde başlıyorsa) mevcut kareyi çapa kabul et.
            self.anchor = {"yaw": yaw_now, "pitch": -20.0, "roll": 0.0, "yaw_kp": yaw_now,
                           "phi": obs["phi"], "eyeline": obs["eyeline"]}
        a = self.anchor
        gate = (lambda d: d if abs(d) >= self.frontal_deadband else 0.0) \
            if (self.frontal_deadband > 0 and not self.profile_mode) else (lambda d: d)
        yaw_rel = a["yaw"] + gate(yaw_now - a["yaw_kp"])
        # Derin profilde (|yaw_kp| 62°→82°) mutlak KP yaw'a kademeli geçiş: hızlı dönüşte geride kalan
        # FaceMesh çapasının hatası profilde birikmez; geçiş sürekli olduğu için hız sıçraması yaratmaz.
        # Yalnız profil kipinde: önden bakışta (ör. anahtar kareler arası) mutlak KP yaw kafa eğikliğinden
        # etkilenebildiği için yalnız göreli değişim kullanılır.
        w_abs = float(np.clip((abs(yaw_now) - PROFILE_ENTER_YAW_DEG) / 20.0, 0.0, 1.0)) if self.profile_mode else 0.0
        yaw = float(np.clip(yaw_rel + w_abs * (yaw_now - yaw_rel), -100.0, 100.0))

        # Profil ağırlığı: |yaw| büyüdükçe phi -> pitch, küçükken göz çizgisi -> roll güvenilir
        w_prof = float(np.clip((abs(yaw) - 40.0) / 25.0, 0.0, 1.0))
        pitch = float(np.clip(a["pitch"] + gate(w_prof * _wrap_deg(obs["phi"] - a["phi"])), -85.0, 85.0))
        roll = float(np.clip(a["roll"] + gate((1.0 - w_prof) * _wrap_deg(obs["eyeline"] - a["eyeline"])), -75.0, 75.0))
        return {"yaw": yaw, "pitch": pitch, "roll": roll,
                "rotation_matrix": euler_to_rotation_matrix(yaw, pitch, roll)}

    def make_result(self, obs: Dict[str, Any], frame_index: int, latency_ms: float,
                    flag: str = "BLAZEFACE_KP") -> PoseResult:
        p = self.pose(obs)
        return PoseResult(
            frame_index=frame_index,
            face_detected=True,
            yaw=p["yaw"],
            pitch=p["pitch"],
            roll=p["roll"],
            rotation_matrix=p["rotation_matrix"],
            confidence=float(obs["score"]) * 0.9,
            latency_ms=latency_ms,
            flag=flag,
            metadata={
                "child_track": "blazeface_kp",
                "used_kp_bridge": True,
                "eyes_source": "blazeface",
                "kp_eye_ratio": round(obs["raw_ratio"], 4),
                "kp_frontal_ratio_e0": round(self.e0, 4),
                "eyes_center_roi": obs["eyes_center_roi"],
                "nose_xy_roi": obs["nose_xy_roi"],
                "face_bbox_roi": obs["face_bbox_roi"],
                "landmarks_draw_roi": obs["landmarks_draw_roi"],
            },
        )


def observe_landmark_frame(bridge: KeypointPoseBridge, obs: Optional[Dict[str, Any]], res: PoseResult) -> None:
    """FaceMesh sonucu kullanıldığında köprü çapasını günceller (yardımcı)."""
    if obs is not None and res.yaw is not None and res.pitch is not None and res.roll is not None:
        bridge.set_anchor(obs, res.yaw, res.pitch, res.roll)


__all__: List[str] = [
    "KeypointPoseBridge",
    "observe_landmark_frame",
    "PROFILE_ENTER_YAW_DEG",
    "PROFILE_EXIT_YAW_DEG",
]
