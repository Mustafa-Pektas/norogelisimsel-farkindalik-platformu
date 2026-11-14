"""
MediaPipe FaceMesh + 3D Metrik Kafatası Yönelim Çözücüsü + SQPnP Reprojection Kontrolü
+ Forward-Backward Optik Akışlı Dinamik Kafa Kutusu Takibi (Isme_Tepki/FaceTrack Mimarisi)
+ BlazeFace 6 Anahtar Nokta Profil Köprüsü (KeypointPoseBridge).

Profil köprüsü: FaceMesh ~60° üstü profil dönüşlerinde yüz noktalarını kaybeder. Köprü açıkken
(varsayılan) FaceMesh kaybolduğunda veya profil (|yaw| ≥ 62°) başladığında açılar BlazeFace anahtar
noktalarından, son güvenilir FaceMesh karesine göre göreli olarak hesaplanır; SO(3) dizisi kesintisiz
kalır. 1-Euro / Kalman filtreleri FaceMesh ve köprü karelerinden oluşan BİRLEŞİK açı akışına sürekli
uygulanır; geçişler bu sayede yumuşaktır (filtre köprü sırasında sıfırlanmaz).
"""
import time
from typing import Optional, List, Tuple
import numpy as np
import cv2

from estimators.base import BaseEstimator
from estimators.blazeface_kp import KeypointPoseBridge
from common.types import PoseResult
from common.geometry import (
    solve_mediapipe_3d_head_pose,
    euler_to_rotation_matrix,
)
from common.filters import OneEuroFilter, AngleKalmanFilter


FACE_TRACK_INDICES = [
    1, 4, 5, 6, 10, 33, 61, 105, 133, 152, 168, 197,
    263, 291, 334, 362, 199, 234, 454, 50, 280
]


class MediaPipePnpEstimator(BaseEstimator):
    def __init__(
        self,
        filter_type: str = "none",
        min_detection_confidence: float = 0.2,
        min_tracking_confidence: float = 0.2,
        static_image_mode: bool = False,
        kp_bridge: bool = True,
    ):
        name_map = {
            "none": "MediaPipe_SolvePnP_Raw",
            "1euro": "MediaPipe_SolvePnP_1Euro",
            "kalman": "MediaPipe_SolvePnP_Kalman",
        }
        super().__init__(name=name_map.get(filter_type, "MediaPipe_SolvePnP"))
        self.filter_type = filter_type
        # Seyrek (anahtar kare) çağrılarda izleme modu ardışık kare varsayar; bağımsız tespit daha doğrudur
        self.static_image_mode = static_image_mode
        self.min_det_conf = min_detection_confidence
        self.min_trk_conf = min_tracking_confidence
        self.face_mesh = None
        self.prev_angles: Optional[tuple] = None
        # Kaskad/hibrit sarmalayıcılar kendi köprülerini yönettiği için iç FaceMesh'te köprüyü kapatır
        self.use_kp_bridge = kp_bridge
        self.bridge: Optional[KeypointPoseBridge] = None

        # Forward-Backward LK Optik Akış Kafa Kutusu Takipçisi (FaceTrack)
        self.prev_gray: Optional[np.ndarray] = None
        self.tracked_bbox_roi: Optional[List[float]] = None
        self.tracked_nose_roi: Optional[List[float]] = None
        self.tracked_eyes_roi: Optional[List[float]] = None
        self.flow_gap_frames: int = 0
        self.max_flow_gap_frames: int = 60  # 2.5 sn @ 24 FPS

        if filter_type == "1euro":
            self.filter_yaw = OneEuroFilter(min_cutoff=0.8, beta=0.005)
            self.filter_pitch = OneEuroFilter(min_cutoff=0.8, beta=0.005)
            self.filter_roll = OneEuroFilter(min_cutoff=0.8, beta=0.005)
        elif filter_type == "kalman":
            self.filter_yaw = AngleKalmanFilter()
            self.filter_pitch = AngleKalmanFilter()
            self.filter_roll = AngleKalmanFilter()
        else:
            self.filter_yaw = None
            self.filter_pitch = None
            self.filter_roll = None

    def setup(self) -> bool:
        try:
            try:
                from mediapipe.python.solutions import face_mesh as mp_face_mesh
            except Exception:
                import mediapipe as mp
                mp_face_mesh = mp.solutions.face_mesh

            self.mp_face_mesh = mp_face_mesh
            self.face_mesh = self.mp_face_mesh.FaceMesh(
                static_image_mode=self.static_image_mode,
                max_num_faces=1,
                refine_landmarks=True,
                min_detection_confidence=self.min_det_conf,
                min_tracking_confidence=self.min_trk_conf,
            )
        except Exception as e:
            print(f"    [MediaPipe Setup Hatası]: {e}")
            self.is_ready = False
            return False

        if self.use_kp_bridge:
            bridge = KeypointPoseBridge()
            # Köprü kurulamazsa model saf FaceMesh olarak çalışmaya devam eder
            self.bridge = bridge if bridge.setup() else None
        self.is_ready = True
        return True

    def _filter_angles(self, yaw: float, pitch: float, roll: float,
                       timestamp: Optional[float]) -> Tuple[float, float, float]:
        if self.filter_yaw is None:
            return yaw, pitch, roll
        return (
            self.filter_yaw.filter(yaw, timestamp),
            self.filter_pitch.filter(pitch, timestamp),
            self.filter_roll.filter(roll, timestamp),
        )

    def _shift_box_with_fb_flow(self, gray: np.ndarray, w: int, h: int) -> bool:
        """
        Isme_Tepki/sesyon/vision.py::FaceTrack._flow ile birebir aynı
        Forward-Backward Lucas-Kanade Optik Akış (fb_err < 1.5 px) kutu kaydırması.
        """
        if self.prev_gray is None or self.tracked_bbox_roi is None:
            return False
        x1, y1, x2, y2 = [int(round(v)) for v in self.tracked_bbox_roi]
        x1, y1 = max(0, x1), max(0, y1)
        x2, y2 = min(w, x2), min(h, y2)
        if x2 - x1 < 12 or y2 - y1 < 12:
            return False

        mask = np.zeros_like(self.prev_gray)
        mask[y1:y2, x1:x2] = 255
        pts = cv2.goodFeaturesToTrack(
            self.prev_gray,
            mask=mask,
            maxCorners=40,
            qualityLevel=0.01,
            minDistance=4,
            blockSize=7,
        )
        if pts is None or len(pts) < 6:
            return False

        p1, st1, _ = cv2.calcOpticalFlowPyrLK(self.prev_gray, gray, pts, None, winSize=(15, 15), maxLevel=2)
        p0r, st0, _ = cv2.calcOpticalFlowPyrLK(gray, self.prev_gray, p1, None, winSize=(15, 15), maxLevel=2)
        if p1 is None or p0r is None:
            return False

        fb_err = np.linalg.norm(pts - p0r, axis=2).reshape(-1)
        good = (st1.reshape(-1) == 1) & (st0.reshape(-1) == 1) & (fb_err < 1.5)
        if int(np.count_nonzero(good)) < 6:
            return False

        shift = np.median(p1[good] - pts[good], axis=0).reshape(2)
        dx, dy = float(shift[0]), float(shift[1])
        bx1, by1, bx2, by2 = self.tracked_bbox_roi
        bw, bh = bx2 - bx1, by2 - by1
        nx1 = float(np.clip(bx1 + dx, 0.0, max(0.0, w - bw)))
        ny1 = float(np.clip(by1 + dy, 0.0, max(0.0, h - bh)))
        self.tracked_bbox_roi = [nx1, ny1, nx1 + bw, ny1 + bh]
        if self.tracked_nose_roi is not None:
            self.tracked_nose_roi = [
                float(np.clip(self.tracked_nose_roi[0] + dx, 0.0, w - 1)),
                float(np.clip(self.tracked_nose_roi[1] + dy, 0.0, h - 1)),
            ]
        if self.tracked_eyes_roi is not None:
            self.tracked_eyes_roi = [
                float(np.clip(self.tracked_eyes_roi[0] + dx, 0.0, w - 1)),
                float(np.clip(self.tracked_eyes_roi[1] + dy, 0.0, h - 1)),
            ]
        return True

    def predict(self, roi_bgr: np.ndarray, frame_index: int, timestamp: Optional[float] = None) -> PoseResult:
        if not self.is_ready or self.face_mesh is None:
            return PoseResult(frame_index=frame_index, face_detected=False, flag="MODEL_NOT_READY")

        t_start = time.perf_counter()
        h, w = roi_bgr.shape[:2]
        gray = cv2.cvtColor(roi_bgr, cv2.COLOR_BGR2GRAY)
        roi_rgb = cv2.cvtColor(roi_bgr, cv2.COLOR_BGR2RGB)

        results = self.face_mesh.process(roi_rgb)
        obs = self.bridge.detect(roi_bgr) if self.bridge is not None else None

        # 1) FaceMesh ham açıları (kare-arası sıçrama sınırlaması dahil, filtre ÖNCESİ)
        mesh = None
        if results.multi_face_landmarks:
            face_landmarks = results.multi_face_landmarks[0].landmark
            pose = solve_mediapipe_3d_head_pose(face_landmarks, w, h)
            yaw, pitch, roll = pose["yaw"], pose["pitch"], pose["roll"]
            if self.prev_angles is not None:
                py, pp, pr = self.prev_angles
                yaw = py + float(np.clip(yaw - py, -22.0, 22.0))
                pitch = pp + float(np.clip(pitch - pp, -18.0, 18.0))
                roll = pr + float(np.clip(roll - pr, -15.0, 15.0))
            mesh = (yaw, pitch, roll, pose, face_landmarks)

        profile = (
            self.bridge.wants_profile(obs, mesh[0] if mesh is not None else None)
            if self.bridge is not None else False
        )

        # 2) FaceMesh güvenilir: FaceMesh pozu (+ köprü çapası güncellenir)
        if mesh is not None and not profile:
            yaw, pitch, roll, pose, face_landmarks = mesh
            self.prev_angles = (yaw, pitch, roll)
            if self.bridge is not None and obs is not None:
                self.bridge.set_anchor(obs, yaw, pitch, roll)
            fyaw, fpitch, froll = self._filter_angles(yaw, pitch, roll, timestamp)
            R = euler_to_rotation_matrix(fyaw, fpitch, froll)

            self.prev_gray = gray
            self.tracked_bbox_roi = list(pose["face_bbox_roi"])
            self.tracked_nose_roi = list(pose["nose_xy_roi"])
            self.tracked_eyes_roi = list(pose["eyes_center_roi"])
            self.flow_gap_frames = 0

            track_pts = [
                [face_landmarks[idx].x * w, face_landmarks[idx].y * h]
                for idx in FACE_TRACK_INDICES
            ]
            latency = (time.perf_counter() - t_start) * 1000.0
            return PoseResult(
                frame_index=frame_index,
                face_detected=True,
                yaw=fyaw,
                pitch=fpitch,
                roll=froll,
                rotation_matrix=R,
                confidence=0.95,
                latency_ms=latency,
                flag="OK",
                metadata={
                    "child_track": "landmarks",
                    "eyes_source": "landmarks",
                    "used_kp_bridge": False,
                    "pose_reprojection_px": pose["pose_reprojection_px"],
                    "sqpnp_valid": pose["sqpnp_valid"],
                    "eyes_center_roi": pose["eyes_center_roi"],
                    "nose_xy_roi": pose["nose_xy_roi"],
                    "face_bbox_roi": pose["face_bbox_roi"],
                    "landmarks_draw_roi": pose["landmarks_draw_roi"],
                    "iris_pts_roi": pose["iris_pts_roi"],
                    "track_pts_roi": track_pts,
                },
            )

        # 3) Profil / FaceMesh kaybı: BlazeFace KP köprüsü (filtre akışı kesintisiz sürer)
        if obs is not None:
            self.prev_angles = None
            res = self.bridge.make_result(obs, frame_index, 0.0)
            res.yaw, res.pitch, res.roll = self._filter_angles(res.yaw, res.pitch, res.roll, timestamp)
            res.rotation_matrix = euler_to_rotation_matrix(res.yaw, res.pitch, res.roll)
            self.prev_gray = gray
            self.tracked_bbox_roi = list(obs["face_bbox_roi"])
            self.tracked_nose_roi = list(obs["nose_xy_roi"])
            self.tracked_eyes_roi = list(obs["eyes_center_roi"])
            self.flow_gap_frames = 0
            res.latency_ms = (time.perf_counter() - t_start) * 1000.0
            return res

        # 4) Ne FaceMesh ne KP: yalnız LK ile kafa kutusu kaydırma (poz yok)
        self.prev_angles = None
        box_shifted = False
        if self.flow_gap_frames < self.max_flow_gap_frames:
            box_shifted = self._shift_box_with_fb_flow(gray, w, h)
        self.prev_gray = gray
        if box_shifted:
            self.flow_gap_frames += 1
        else:
            self.flow_gap_frames = self.max_flow_gap_frames + 1

        latency = (time.perf_counter() - t_start) * 1000.0
        meta = {"child_track": "optical_flow_box" if box_shifted else "lost"}
        if box_shifted and self.tracked_bbox_roi is not None:
            meta["face_bbox_roi"] = list(self.tracked_bbox_roi)
            if self.tracked_nose_roi is not None:
                meta["nose_xy_roi"] = list(self.tracked_nose_roi)
            if self.tracked_eyes_roi is not None:
                meta["eyes_center_roi"] = list(self.tracked_eyes_roi)
                meta["eyes_source"] = "flow"
        return PoseResult(
            frame_index=frame_index,
            face_detected=False,
            latency_ms=latency,
            flag="NO_FACE_DETECTED",
            metadata=meta,
        )

    def reset(self):
        self.prev_angles = None
        self.prev_gray = None
        self.tracked_bbox_roi = None
        self.tracked_nose_roi = None
        self.tracked_eyes_roi = None
        self.flow_gap_frames = 0
        if self.filter_yaw is not None:
            self.filter_yaw.reset()
            self.filter_pitch.reset()
            self.filter_roll.reset()
        if self.bridge is not None:
            self.bridge.reset()
        if self.face_mesh is not None:
            self.face_mesh.reset()
