"""
MediaPipe Iris Tabanlı Göz Bebeği Bakış Açısı ve 3D Kafa Pozu Tahmini.
Çocuk baş bölgesi (ROI: 320x320) üzerinde çalışır.
Profil dönüşlerinde (FaceMesh/iris kaybı veya |yaw| ≥ 62°) baş pozu BlazeFace KP köprüsüyle sürer;
o karelerde iris görünmediği için gaze_yaw/gaze_pitch boş bırakılır.
"""
import time
from typing import Optional
import numpy as np
import cv2

from estimators.base import BaseEstimator
from estimators.blazeface_kp import KeypointPoseBridge
from common.types import PoseResult
from common.geometry import solve_mediapipe_3d_head_pose, euler_to_rotation_matrix


class MediaPipeIrisEstimator(BaseEstimator):
    def __init__(self, min_detection_confidence: float = 0.2, min_tracking_confidence: float = 0.2,
                 kp_bridge: bool = True):
        super().__init__(name="MediaPipe_Iris_Gaze")
        self.min_det_conf = min_detection_confidence
        self.min_trk_conf = min_tracking_confidence
        self.face_mesh = None
        self.prev_angles: Optional[tuple] = None
        self.use_kp_bridge = kp_bridge
        self.bridge: Optional[KeypointPoseBridge] = None

    def setup(self) -> bool:
        try:
            try:
                from mediapipe.python.solutions import face_mesh as mp_face_mesh
            except Exception:
                import mediapipe as mp
                mp_face_mesh = mp.solutions.face_mesh

            self.mp_face_mesh = mp_face_mesh
            self.face_mesh = self.mp_face_mesh.FaceMesh(
                static_image_mode=False,
                max_num_faces=1,
                refine_landmarks=True,  # Iris noktaları (468-477) aktif
                min_detection_confidence=self.min_det_conf,
                min_tracking_confidence=self.min_trk_conf,
            )
        except Exception as e:
            print(f"    [MediaPipe Iris Setup Hatası]: {e}")
            self.is_ready = False
            return False
        if self.use_kp_bridge:
            bridge = KeypointPoseBridge()
            self.bridge = bridge if bridge.setup() else None
        self.is_ready = True
        return True

    def predict(self, roi_bgr: np.ndarray, frame_index: int, timestamp: Optional[float] = None) -> PoseResult:
        if not self.is_ready or self.face_mesh is None:
            return PoseResult(frame_index=frame_index, face_detected=False, flag="MODEL_NOT_READY")

        t_start = time.perf_counter()
        h, w = roi_bgr.shape[:2]
        roi_rgb = cv2.cvtColor(roi_bgr, cv2.COLOR_BGR2RGB)

        results = self.face_mesh.process(roi_rgb)
        obs = self.bridge.detect(roi_bgr) if self.bridge is not None else None

        mesh = None
        if results.multi_face_landmarks:
            landmarks = results.multi_face_landmarks[0].landmark
            pose = solve_mediapipe_3d_head_pose(landmarks, w, h)
            yaw, pitch, roll = pose["yaw"], pose["pitch"], pose["roll"]
            if self.prev_angles is not None:
                py, pp, pr = self.prev_angles
                yaw = py + float(np.clip(yaw - py, -22.0, 22.0))
                pitch = pp + float(np.clip(pitch - pp, -18.0, 18.0))
                roll = pr + float(np.clip(roll - pr, -15.0, 15.0))
            mesh = (yaw, pitch, roll, pose, landmarks)

        profile = (
            self.bridge.wants_profile(obs, mesh[0] if mesh is not None else None)
            if self.bridge is not None else False
        )

        if mesh is None or profile:
            self.prev_angles = None
            if obs is not None:
                return self.bridge.make_result(obs, frame_index, (time.perf_counter() - t_start) * 1000.0)
            return PoseResult(
                frame_index=frame_index,
                face_detected=False,
                latency_ms=(time.perf_counter() - t_start) * 1000.0,
                flag="NO_FACE_DETECTED",
            )

        yaw, pitch, roll, pose, landmarks = mesh
        self.prev_angles = (yaw, pitch, roll)
        if self.bridge is not None and obs is not None:
            self.bridge.set_anchor(obs, yaw, pitch, roll)
        R = euler_to_rotation_matrix(yaw, pitch, roll)

        # Iris Bakış Açısı (Her iki gözün ortalaması)
        left_pupil = np.array([landmarks[468].x * w, landmarks[468].y * h])
        left_outer = np.array([landmarks[33].x * w, landmarks[33].y * h])
        left_inner = np.array([landmarks[133].x * w, landmarks[133].y * h])

        right_pupil = np.array([landmarks[473].x * w, landmarks[473].y * h])
        right_inner = np.array([landmarks[362].x * w, landmarks[362].y * h])
        right_outer = np.array([landmarks[263].x * w, landmarks[263].y * h])

        ratios = []
        lw = np.linalg.norm(left_inner - left_outer)
        if lw > 1e-3:
            ratios.append(np.linalg.norm(left_pupil - left_outer) / lw)
        rw = np.linalg.norm(right_outer - right_inner)
        if rw > 1e-3:
            ratios.append(np.linalg.norm(right_pupil - right_inner) / rw)

        horizontal_ratio = float(np.mean(ratios)) if ratios else 0.5
        # Sağa bakış negatif Yaw ile uyumlu olacak şekilde ölçekle
        gaze_offset = -(horizontal_ratio - 0.5) * 50.0
        gaze_yaw = float(np.clip(yaw + gaze_offset, -95.0, 95.0))

        latency = (time.perf_counter() - t_start) * 1000.0

        return PoseResult(
            frame_index=frame_index,
            face_detected=True,
            yaw=yaw,
            pitch=pitch,
            roll=roll,
            rotation_matrix=R,
            gaze_yaw=gaze_yaw,
            gaze_pitch=pitch,
            confidence=0.92,
            latency_ms=latency,
            flag="OK",
            metadata={
                "gaze_ratio": round(horizontal_ratio, 3),
                "eyes_source": "landmarks",
                "used_kp_bridge": False,
                "eyes_center_roi": pose["eyes_center_roi"],
                "nose_xy_roi": pose["nose_xy_roi"],
                "face_bbox_roi": pose["face_bbox_roi"],
                "landmarks_draw_roi": pose["landmarks_draw_roi"],
                "iris_pts_roi": pose["iris_pts_roi"],
            },
        )

    def reset(self):
        self.prev_angles = None
        if self.bridge is not None:
            self.bridge.reset()
        if self.face_mesh is not None:
            self.face_mesh.reset()
