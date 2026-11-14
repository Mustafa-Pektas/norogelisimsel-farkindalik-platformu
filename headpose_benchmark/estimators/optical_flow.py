"""
Lucas-Kanade Optik Akış Tabanlı Kafa Hareketi ve Diferansiyel Yönelim Takibi.
Yalnızca çocuk baş bölgesi (ROI: 320x320) merkez maskesi içinde ileri-geri (forward-backward)
tutarlılığı doğrulanmış köşe noktalarını takip eder.
"""
import time
from typing import Optional
import numpy as np
import cv2

from estimators.base import BaseEstimator
from common.types import PoseResult
from common.geometry import euler_to_rotation_matrix


class OpticalFlowEstimator(BaseEstimator):
    def __init__(self, max_corners: int = 80, quality_level: float = 0.02, min_distance: float = 6.0):
        super().__init__(name="Lucas_Kanade_Optical_Flow")
        self.max_corners = max_corners
        self.quality_level = quality_level
        self.min_distance = min_distance

        self.prev_gray = None
        self.prev_pts = None
        self.cum_yaw = 0.0
        self.cum_pitch = -20.0

        self.lk_params = dict(
            winSize=(21, 21),
            maxLevel=3,
            criteria=(cv2.TERM_CRITERIA_EPS | cv2.TERM_CRITERIA_COUNT, 15, 0.03),
        )

    def setup(self) -> bool:
        self.is_ready = True
        return True

    def _create_head_center_mask(self, h: int, w: int) -> np.ndarray:
        """ROI'nin kenarlarındaki arka planı dışlamak için merkez kafa bölgesine eliptik maske uygular."""
        mask = np.zeros((h, w), dtype=np.uint8)
        cv2.ellipse(
            mask,
            (w // 2, h // 2),
            (int(w * 0.36), int(h * 0.38)),
            0,
            0,
            360,
            255,
            -1,
        )
        return mask

    def init_with_landmarks(self, gray: np.ndarray, pts_xy: list, init_yaw: float = 0.0, init_pitch: float = -20.0):
        """MediaPipe yüz noktalarından optik akış noktalarını doğrudan başlatır."""
        self.prev_gray = gray.copy()
        self.prev_pts = np.array(pts_xy, dtype=np.float32).reshape(-1, 1, 2)
        self.cum_yaw = init_yaw
        self.cum_pitch = init_pitch

    def predict(self, roi_bgr: np.ndarray, frame_index: int, timestamp: Optional[float] = None) -> PoseResult:
        t_start = time.perf_counter()
        gray = cv2.cvtColor(roi_bgr, cv2.COLOR_BGR2GRAY)
        h, w = gray.shape

        if self.prev_gray is None or self.prev_pts is None or len(self.prev_pts) < 8:
            self.prev_gray = gray
            mask = self._create_head_center_mask(h, w)
            self.prev_pts = cv2.goodFeaturesToTrack(
                gray,
                maxCorners=self.max_corners,
                qualityLevel=self.quality_level,
                minDistance=self.min_distance,
                mask=mask,
            )
            latency = (time.perf_counter() - t_start) * 1000.0
            has_pts = self.prev_pts is not None and len(self.prev_pts) >= 8
            return PoseResult(
                frame_index=frame_index,
                face_detected=False,
                yaw=self.cum_yaw if has_pts else None,
                pitch=self.cum_pitch if has_pts else None,
                roll=0.0 if has_pts else None,
                latency_ms=latency,
                flag="OPTICAL_FLOW_ROI_ONLY" if has_pts else "TRACKING_LOST",
            )

        next_pts, status, _ = cv2.calcOpticalFlowPyrLK(
            self.prev_gray, gray, self.prev_pts, None, **self.lk_params
        )
        back_pts, status_back, _ = cv2.calcOpticalFlowPyrLK(
            gray, self.prev_gray, next_pts, None, **self.lk_params
        )

        fb_err = np.linalg.norm(self.prev_pts - back_pts, axis=2).reshape(-1)
        valid_mask = (status.reshape(-1) == 1) & (status_back.reshape(-1) == 1) & (fb_err < 2.5)

        good_new = next_pts[valid_mask].reshape(-1, 2)
        good_old = self.prev_pts[valid_mask].reshape(-1, 2)

        in_bounds = (
            (good_new[:, 0] >= 10)
            & (good_new[:, 0] < w - 10)
            & (good_new[:, 1] >= 10)
            & (good_new[:, 1] < h - 10)
        )
        good_new = good_new[in_bounds]
        good_old = good_old[in_bounds]

        if len(good_new) < 8:
            self.prev_gray = gray
            self.prev_pts = None
            latency = (time.perf_counter() - t_start) * 1000.0
            return PoseResult(
                frame_index=frame_index,
                face_detected=False,
                latency_ms=latency,
                flag="TRACKING_LOST",
            )

        displacements = good_new - good_old
        dx = float(np.median(displacements[:, 0]))
        dy = float(np.median(displacements[:, 1]))

        # Ekranda sağa hareket (dx > 0) -> negatif Yaw; aşağı hareket (dy > 0) -> negatif Pitch
        scale = 90.0 / (w * 0.35)
        d_yaw = -dx * scale
        d_pitch = -dy * scale

        self.cum_yaw = float(np.clip(self.cum_yaw + d_yaw, -95.0, 95.0))
        self.cum_pitch = float(np.clip(self.cum_pitch + d_pitch, -75.0, 75.0))

        self.prev_gray = gray
        self.prev_pts = good_new.reshape(-1, 1, 2)
        center_xy = [float(np.mean(good_new[:, 0])), float(np.mean(good_new[:, 1]))]
        face_bbox_roi = [
            float(max(0.0, np.min(good_new[:, 0]) - 12.0)),
            float(max(0.0, np.min(good_new[:, 1]) - 15.0)),
            float(min(float(w - 1), np.max(good_new[:, 0]) + 12.0)),
            float(min(float(h - 1), np.max(good_new[:, 1]) + 15.0)),
        ]
        pts_list = [[float(p[0]), float(p[1])] for p in good_new[:20]]
        latency = (time.perf_counter() - t_start) * 1000.0

        return PoseResult(
            frame_index=frame_index,
            face_detected=False,
            yaw=self.cum_yaw,
            pitch=self.cum_pitch,
            roll=0.0,
            rotation_matrix=euler_to_rotation_matrix(self.cum_yaw, self.cum_pitch, 0.0),
            confidence=min(1.0, float(len(good_new)) / 25.0),
            latency_ms=latency,
            flag="OPTICAL_FLOW_ROI_ONLY",
            metadata={
                "delta_yaw": round(d_yaw, 2),
                "delta_pitch": round(d_pitch, 2),
                "tracked_pts": len(good_new),
                "nose_xy_roi": center_xy,
                "face_bbox_roi": face_bbox_roi,
                "landmarks_draw_roi": pts_list,
            },
        )

    def reset(self):
        self.prev_gray = None
        self.prev_pts = None
        self.cum_yaw = 0.0
        self.cum_pitch = -20.0
