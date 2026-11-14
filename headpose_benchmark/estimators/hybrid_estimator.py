"""
Hibrit ve Kaskad Baş Yönü Tahmincileri:
1. MediaPipePnpLkTracker (MediaPipe_PnP_LK_Tracker)           — FaceMesh + KP köprüsü; ikisi de yoksa LK süzülmesi
2. HybridKeypointEstimator (Hybrid_PnP_KP_Step5)              — FaceMesh her 5. karede, arada BlazeFace KP
3. CascadePnpRepNetEstimator (Cascade_PnP_to_6DRepNet360)     — profilde her kare 6DRepNet360
4. CascadePnpBlazeFaceEstimator (Cascade_PnP_to_BlazeFaceKP)  — profilde her kare BlazeFace KP (hızlı)
5. CascadePnpRepNetStridedEstimator (Cascade_PnP_to_6DRepNet360_Stride4)
   — profilde yalnız her 4. karede 6DRepNet360, aradaki kareler BlazeFace KP göreli dönüşüyle

Not (Hybrid_PnP_LK_Step5 neden kaldırıldı): Deniz videosunda çocuğun kafası 2–4 px/kare ötelenir.
LK ortanca kayması bu ötelemeyi dönme sanar; öteleme/dönme küresel ayrıştırmasıyla bile sabit karelerde
0.5–1.8 °/kare (12–43 °/s) sahte dönme kalır ve 20 °/s yerleşme eşiğini bozar. Ayrıca anahtar karede
FaceMesh kaybolduğunda yüz-tespit-yok sonucu döndüğü için SO(3) dizisinde her 5 karede bir boşluk
oluşuyordu (unknown_end_data_gap). KP köprüsü ikisini de giderir.
"""
import time
from typing import Optional

import numpy as np
import cv2

from estimators.base import BaseEstimator
from estimators.mediapipe_pnp import MediaPipePnpEstimator
from estimators.optical_flow import OpticalFlowEstimator
from estimators.repnet360 import SixDRepNet360Estimator
from estimators.blazeface_kp import KeypointPoseBridge, observe_landmark_frame
from common.types import PoseResult
from common.geometry import rotation_matrix_to_euler


def _landmark_pose_ok(res: PoseResult) -> bool:
    return bool(res.face_detected and res.rotation_matrix is not None)


class MediaPipePnpLkTracker(BaseEstimator):
    """FaceMesh (+ BlazeFace KP profil köprüsü); ikisi de yoksa naif LK süzülmesi (LK pozu SO(3) dizisine katılmaz)."""

    def __init__(self):
        super().__init__(name="MediaPipe_PnP_LK_Tracker")
        # FaceMesh + BlazeFace KP köprüsü; ikisi de yoksa LK ile yalnız kutu/kaba açı süzülmesi
        self.pnp = MediaPipePnpEstimator(filter_type="none", min_detection_confidence=0.2, min_tracking_confidence=0.2,
                                         kp_bridge=True)
        self.flow = OpticalFlowEstimator()
        self.lk_consecutive_frames = 0
        self.max_lk_coast_frames = 35

    def setup(self) -> bool:
        ok_pnp = self.pnp.setup()
        ok_flow = self.flow.setup()
        self.is_ready = ok_pnp and ok_flow
        return self.is_ready

    def predict(self, roi_bgr: np.ndarray, frame_index: int, timestamp: Optional[float] = None) -> PoseResult:
        t_start = time.perf_counter()
        gray = cv2.cvtColor(roi_bgr, cv2.COLOR_BGR2GRAY)

        pnp_res = self.pnp.predict(roi_bgr, frame_index, timestamp)
        if _landmark_pose_ok(pnp_res):
            self.lk_consecutive_frames = 0
            track_pts = pnp_res.metadata.get("track_pts_roi")
            if track_pts:
                self.flow.init_with_landmarks(
                    gray,
                    track_pts,
                    init_yaw=pnp_res.yaw or 0.0,
                    init_pitch=pnp_res.pitch or -20.0,
                )
            pnp_res.latency_ms = (time.perf_counter() - t_start) * 1000.0
            return pnp_res

        self.lk_consecutive_frames += 1
        if self.lk_consecutive_frames <= self.max_lk_coast_frames and self.flow.prev_pts is not None:
            flow_res = self.flow.predict(roi_bgr, frame_index, timestamp)
            total_lat = (time.perf_counter() - t_start) * 1000.0
            if flow_res.flag == "OPTICAL_FLOW_ROI_ONLY":
                meta = dict(flow_res.metadata)
                # Göz konumu için FaceMesh'in LK ile kaydırdığı kutu bilgisini koru
                for k in ("face_bbox_roi", "eyes_center_roi", "nose_xy_roi", "eyes_source"):
                    if pnp_res.metadata.get(k) is not None:
                        meta[k] = pnp_res.metadata[k]
                return PoseResult(
                    frame_index=frame_index,
                    face_detected=False,
                    yaw=flow_res.yaw,
                    pitch=flow_res.pitch,
                    roll=0.0,
                    rotation_matrix=None,
                    confidence=flow_res.confidence,
                    latency_ms=total_lat,
                    flag="OPTICAL_FLOW_ROI_ONLY",
                    metadata=meta,
                )

        self.flow.prev_pts = None
        total_lat = (time.perf_counter() - t_start) * 1000.0
        return PoseResult(
            frame_index=frame_index,
            face_detected=False,
            latency_ms=total_lat,
            flag="TRACKING_LOST",
            metadata={k: v for k, v in pnp_res.metadata.items() if k in ("face_bbox_roi", "eyes_center_roi", "nose_xy_roi", "eyes_source")},
        )

    def reset(self):
        self.pnp.reset()
        self.flow.reset()
        self.lk_consecutive_frames = 0


class HybridKeypointEstimator(BaseEstimator):
    """
    FaceMesh 3D poz her `keyframe_interval` karede bir (çapa); aradaki kareler ve profil dönüşleri
    ~2 ms'lik BlazeFace anahtar nokta köprüsüyle çapaya göre göreli hesaplanır.
    """

    def __init__(self, keyframe_interval: int = 5):
        super().__init__(name=f"Hybrid_PnP_KP_Step{keyframe_interval}")
        self.interval = keyframe_interval
        self.pnp = MediaPipePnpEstimator(filter_type="none", min_detection_confidence=0.2,
                                         min_tracking_confidence=0.2, static_image_mode=True,
                                         kp_bridge=False)
        self.bridge = KeypointPoseBridge(frontal_deadband_deg=8.0)
        self.need_keyframe = True
        self.last_mesh_yaw: Optional[float] = None

    def setup(self) -> bool:
        ok_pnp = self.pnp.setup()
        ok_kp = self.bridge.setup()
        self.is_ready = ok_pnp and ok_kp
        return self.is_ready

    def predict(self, roi_bgr: np.ndarray, frame_index: int, timestamp: Optional[float] = None) -> PoseResult:
        t_start = time.perf_counter()
        obs = self.bridge.detect(roi_bgr)
        is_keyframe = self.need_keyframe or (frame_index % self.interval == 0)

        if is_keyframe:
            pnp_res = self.pnp.predict(roi_bgr, frame_index, timestamp)
            self.last_mesh_yaw = pnp_res.yaw if _landmark_pose_ok(pnp_res) else None
            profile = self.bridge.wants_profile(obs, self.last_mesh_yaw)
            if _landmark_pose_ok(pnp_res) and not profile:
                observe_landmark_frame(self.bridge, obs, pnp_res)
                self.need_keyframe = obs is None
                pnp_res.metadata["used_kp_bridge"] = False
                pnp_res.metadata["keyframe"] = True
                pnp_res.latency_ms = (time.perf_counter() - t_start) * 1000.0
                return pnp_res
            if obs is not None:
                self.need_keyframe = False
                return self.bridge.make_result(obs, frame_index, (time.perf_counter() - t_start) * 1000.0)
            self.need_keyframe = True
            pnp_res.latency_ms = (time.perf_counter() - t_start) * 1000.0
            return pnp_res

        self.bridge.wants_profile(obs, self.last_mesh_yaw)
        if obs is not None:
            return self.bridge.make_result(obs, frame_index, (time.perf_counter() - t_start) * 1000.0,
                                           flag="KP_INTERPOLATED")
        self.need_keyframe = True
        return PoseResult(frame_index=frame_index, face_detected=False,
                          latency_ms=(time.perf_counter() - t_start) * 1000.0, flag="TRACKING_LOST")

    def reset(self):
        self.pnp.reset()
        self.bridge.reset()
        self.need_keyframe = True
        self.last_mesh_yaw = None


class CascadePnpBlazeFaceEstimator(BaseEstimator):
    """FaceMesh her karede; FaceMesh kaybolduğunda veya profil (|yaw| ≥ 62°) başladığında BlazeFace KP köprüsü."""

    def __init__(self):
        super().__init__(name="Cascade_PnP_to_BlazeFaceKP")
        self.pnp = MediaPipePnpEstimator(filter_type="none", min_detection_confidence=0.2, min_tracking_confidence=0.2,
                                         kp_bridge=False)
        self.bridge = KeypointPoseBridge()

    def setup(self) -> bool:
        ok_pnp = self.pnp.setup()
        ok_kp = self.bridge.setup()
        self.is_ready = ok_pnp and ok_kp
        return self.is_ready

    def predict(self, roi_bgr: np.ndarray, frame_index: int, timestamp: Optional[float] = None) -> PoseResult:
        t_start = time.perf_counter()
        pnp_res = self.pnp.predict(roi_bgr, frame_index, timestamp)
        obs = self.bridge.detect(roi_bgr)
        profile = self.bridge.wants_profile(obs, pnp_res.yaw if _landmark_pose_ok(pnp_res) else None)

        if _landmark_pose_ok(pnp_res) and not profile:
            observe_landmark_frame(self.bridge, obs, pnp_res)
            pnp_res.metadata["used_kp_bridge"] = False
            pnp_res.latency_ms = (time.perf_counter() - t_start) * 1000.0
            return pnp_res
        if obs is not None:
            return self.bridge.make_result(obs, frame_index, (time.perf_counter() - t_start) * 1000.0)
        pnp_res.latency_ms = (time.perf_counter() - t_start) * 1000.0
        return pnp_res

    def reset(self):
        self.pnp.reset()
        self.bridge.reset()


class CascadePnpRepNetEstimator(BaseEstimator):
    """
    Yüz noktaları MediaPipe ile bulunduğunda hızlı 3D çözümü kullanan,
    yüz noktaları kaybolduğunda (profil dönüşte) 6DRepNet360'ı devreye alan Kaskad model.
    Geçiş anında her iki model aynı Gimbal-Lock korumalı SO(3) uzayında hizalanır.
    """
    def __init__(self):
        super().__init__(name="Cascade_PnP_to_6DRepNet360")
        self.pnp = MediaPipePnpEstimator(filter_type="none", min_detection_confidence=0.2, min_tracking_confidence=0.2,
                                         kp_bridge=False)
        self.repnet = SixDRepNet360Estimator(cpu_threads=4)
        self.r_align: Optional[np.ndarray] = None
        self.last_nose_xy = None
        self.last_face_bbox = None
        self.last_eyes_xy = None

    def setup(self) -> bool:
        ok_pnp = self.pnp.setup()
        ok_rep = self.repnet.setup()
        self.is_ready = ok_pnp and ok_rep
        return self.is_ready

    def predict(self, roi_bgr: np.ndarray, frame_index: int, timestamp: Optional[float] = None) -> PoseResult:
        t_start = time.perf_counter()
        pnp_res = self.pnp.predict(roi_bgr, frame_index, timestamp)

        if _landmark_pose_ok(pnp_res):
            if self.r_align is None:
                rep_init = self.repnet.predict(roi_bgr, frame_index, timestamp)
                if rep_init.face_detected and rep_init.rotation_matrix is not None:
                    self.r_align = rep_init.rotation_matrix @ pnp_res.rotation_matrix.T
                else:
                    self.r_align = np.eye(3, dtype=np.float64)

            pnp_res.rotation_matrix = self.r_align @ pnp_res.rotation_matrix
            # Hizalanmış matristen Gimbal-Lock korumalı açıları yeniden çek (geçiş sıçramasını sıfırlar)
            pnp_res.yaw, pnp_res.pitch, pnp_res.roll = rotation_matrix_to_euler(pnp_res.rotation_matrix)
            pnp_res.metadata["used_6d_fallback"] = False
            self.last_nose_xy = pnp_res.metadata.get("nose_xy_roi")
            self.last_face_bbox = pnp_res.metadata.get("face_bbox_roi")
            self.last_eyes_xy = pnp_res.metadata.get("eyes_center_roi")
            pnp_res.latency_ms = (time.perf_counter() - t_start) * 1000.0
            return pnp_res

        rep_res = self.repnet.predict(roi_bgr, frame_index, timestamp)
        rep_res.flag = "FALLBACK_6DREPNET"
        rep_res.metadata["used_6d_fallback"] = True
        _copy_head_track(rep_res, pnp_res, self.last_face_bbox, self.last_eyes_xy, self.last_nose_xy)
        rep_res.latency_ms = (time.perf_counter() - t_start) * 1000.0
        return rep_res

    def reset(self):
        self.pnp.reset()
        self.repnet.reset()
        self.r_align = None
        self.last_nose_xy = None
        self.last_face_bbox = None
        self.last_eyes_xy = None


class CascadePnpRepNetStridedEstimator(BaseEstimator):
    """
    Hızlı kaskad: FaceMesh güvenilirken FaceMesh; profil/kayıp aralığında 6DRepNet360 yalnızca her
    `stride` karede bir mutlak çapa olarak çalışır, aradaki kareler BlazeFace KP göreli dönüşüyle
    (R = A·D·Aᵀ·R_rep_çapa, D = R_kp_şimdi·R_kp_çapaᵀ, A = FaceMesh→6DRepNet hizalaması) doldurulur.
    """

    def __init__(self, stride: int = 4, backend: str = "torch"):
        # backend="onnx": 6DRepNet360 ONNX Runtime ile (tools/export_6drepnet_onnx.py çıktısı)
        super().__init__(name=f"Cascade_PnP_to_6DRepNet360_Stride{stride}" + ("_ONNX" if backend == "onnx" else ""))
        self.stride = max(1, int(stride))
        self.backend = backend
        self.pnp = MediaPipePnpEstimator(filter_type="none", min_detection_confidence=0.2, min_tracking_confidence=0.2,
                                         kp_bridge=False)
        self.repnet = SixDRepNet360Estimator(cpu_threads=4, backend=backend)
        self.bridge = KeypointPoseBridge()
        self.r_align: Optional[np.ndarray] = None
        self.rep_anchor: Optional[np.ndarray] = None
        self.kp_anchor: Optional[np.ndarray] = None
        self.bridge_count = 0

    def setup(self) -> bool:
        ok_pnp = self.pnp.setup()
        ok_rep = self.repnet.setup()
        ok_kp = self.bridge.setup()
        self.is_ready = ok_pnp and ok_rep and ok_kp
        return self.is_ready

    def predict(self, roi_bgr: np.ndarray, frame_index: int, timestamp: Optional[float] = None) -> PoseResult:
        t_start = time.perf_counter()
        pnp_res = self.pnp.predict(roi_bgr, frame_index, timestamp)
        obs = self.bridge.detect(roi_bgr)
        profile = self.bridge.wants_profile(obs, pnp_res.yaw if _landmark_pose_ok(pnp_res) else None)

        if _landmark_pose_ok(pnp_res) and not profile:
            observe_landmark_frame(self.bridge, obs, pnp_res)
            if self.r_align is None:
                rep_init = self.repnet.predict(roi_bgr, frame_index, timestamp)
                if rep_init.face_detected and rep_init.rotation_matrix is not None:
                    self.r_align = rep_init.rotation_matrix @ pnp_res.rotation_matrix.T
                else:
                    self.r_align = np.eye(3, dtype=np.float64)
            pnp_res.rotation_matrix = self.r_align @ pnp_res.rotation_matrix
            pnp_res.yaw, pnp_res.pitch, pnp_res.roll = rotation_matrix_to_euler(pnp_res.rotation_matrix)
            pnp_res.metadata["used_6d_fallback"] = False
            pnp_res.metadata["used_kp_bridge"] = False
            self.rep_anchor = None
            self.kp_anchor = None
            self.bridge_count = 0
            pnp_res.latency_ms = (time.perf_counter() - t_start) * 1000.0
            return pnp_res

        kp_R = self.bridge.pose(obs)["rotation_matrix"] if obs is not None else None
        need_rep = (
            self.rep_anchor is None
            or self.kp_anchor is None
            or kp_R is None
            or self.bridge_count % self.stride == 0
        )
        self.bridge_count += 1

        R = None
        used_6d = False
        if need_rep:
            rep_res = self.repnet.predict(roi_bgr, frame_index, timestamp)
            if rep_res.face_detected and rep_res.rotation_matrix is not None:
                R = rep_res.rotation_matrix
                self.rep_anchor = R.copy()
                self.kp_anchor = None if kp_R is None else kp_R.copy()
                used_6d = True
        if R is None and self.rep_anchor is not None and self.kp_anchor is not None and kp_R is not None:
            A = self.r_align if self.r_align is not None else np.eye(3)
            D = kp_R @ self.kp_anchor.T
            R = A @ D @ A.T @ self.rep_anchor

        latency = (time.perf_counter() - t_start) * 1000.0
        if R is None:
            pnp_res.latency_ms = latency
            return pnp_res

        yaw, pitch, roll = rotation_matrix_to_euler(R)
        res = PoseResult(
            frame_index=frame_index,
            face_detected=True,
            yaw=yaw,
            pitch=pitch,
            roll=roll,
            rotation_matrix=R,
            confidence=0.95 if used_6d else 0.85,
            latency_ms=latency,
            flag="FALLBACK_6DREPNET" if used_6d else "KP_DELTA_FROM_6DREPNET",
            metadata={"used_6d_fallback": used_6d, "used_kp_bridge": not used_6d},
        )
        if obs is not None:
            for k in ("eyes_center_roi", "nose_xy_roi", "face_bbox_roi", "landmarks_draw_roi"):
                res.metadata[k] = obs[k]
            res.metadata["eyes_source"] = "blazeface"
        else:
            _copy_head_track(res, pnp_res, None, None, None)
        return res

    def reset(self):
        self.pnp.reset()
        self.repnet.reset()
        self.bridge.reset()
        self.r_align = None
        self.rep_anchor = None
        self.kp_anchor = None
        self.bridge_count = 0


def _copy_head_track(dst: PoseResult, pnp_res: PoseResult, last_bbox, last_eyes, last_nose):
    """Landmark üretmeyen kareye FaceMesh'in (LK ile kaydırılmış) kutusunu/gözünü taşır; kaynağı işaretler."""
    for key, last in (("face_bbox_roi", last_bbox), ("eyes_center_roi", last_eyes), ("nose_xy_roi", last_nose)):
        if pnp_res.metadata.get(key) is not None:
            dst.metadata[key] = pnp_res.metadata[key]
        elif last is not None:
            dst.metadata[key] = last
    dst.metadata["eyes_source"] = pnp_res.metadata.get("eyes_source", "stale")
