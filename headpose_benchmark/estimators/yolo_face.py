"""
YOLOv8n-Face + OpenCV SolvePnP
Celil'in Planı: Aşırı Dönüşler, Profil ve Yüz Kapanmaları Alternatifi
"""
import os
import time
from typing import Optional
import numpy as np
import cv2

from estimators.base import BaseEstimator
from common.types import PoseResult
from common.geometry import get_camera_matrix, rotation_matrix_to_euler


# 5 Temel Landmark için 3D Kanonik Yüz Modeli (Sol Göz, Sağ Göz, Burun, Sol Ağız, Sağ Ağız)
CANONICAL_5_POINTS_3D = np.array([
    [-225.0, 170.0, -135.0],  # Sol göz
    [225.0, 170.0, -135.0],   # Sağ göz
    [0.0, 0.0, 0.0],          # Burun ucu
    [-150.0, -150.0, -125.0], # Sol ağız
    [150.0, -150.0, -125.0]   # Sağ ağız
], dtype=np.float64)


class YOLOv8FaceEstimator(BaseEstimator):
    def __init__(self, onnx_path: Optional[str] = None):
        super().__init__(name="YOLOv8n_Face_SolvePnP")
        self.onnx_path = onnx_path or "yolov8n-face.onnx"
        self.net = None
        self.ultralytics_model = None

    def setup(self) -> bool:
        # 1. Ultralytics kütüphanesi varsa dene
        try:
            from ultralytics import YOLO
            # Eğer model dosyası varsa yükle
            if os.path.exists(self.onnx_path) or os.path.exists("yolov8n-face.pt"):
                target = self.onnx_path if os.path.exists(self.onnx_path) else "yolov8n-face.pt"
                self.ultralytics_model = YOLO(target)
                self.is_ready = True
                return True
        except ImportError:
            pass

        # 2. OpenCV DNN ile ONNX yüklemeyi dene
        if os.path.exists(self.onnx_path):
            try:
                self.net = cv2.dnn.readNetFromONNX(self.onnx_path)
                self.net.setPreferableBackend(cv2.dnn.DNN_BACKEND_OPENCV)
                self.net.setPreferableTarget(cv2.dnn.DNN_TARGET_CPU)
                self.is_ready = True
                return True
            except Exception:
                pass

        self.is_ready = False
        return False

    def predict(self, frame_bgr: np.ndarray, frame_index: int, timestamp: Optional[float] = None) -> PoseResult:
        if not self.is_ready:
            return PoseResult(
                frame_index=frame_index,
                face_detected=False,
                flag="WEIGHTS_NOT_FOUND (yolov8n-face.onnx veya .pt gerekli)"
            )

        t_start = time.perf_counter()
        h, w = frame_bgr.shape[:2]

        try:
            if self.ultralytics_model is not None:
                results = self.ultralytics_model(frame_bgr, verbose=False)
                if not results or len(results[0].boxes) == 0:
                    latency = (time.perf_counter() - t_start) * 1000.0
                    return PoseResult(frame_index=frame_index, face_detected=False, latency_ms=latency, flag="NO_FACE_DETECTED")

                # En yüksek güvenli yüzün landmarklarını al
                box = results[0].boxes[0]
                if hasattr(results[0], 'keypoints') and results[0].keypoints is not None:
                    kpts = results[0].keypoints.xy[0].cpu().numpy()  # 5 nokta
                    image_points = np.array(kpts[:5], dtype=np.float64)
                else:
                    # Sadece kutu varsa kutu merkezinden kaba tahmin
                    latency = (time.perf_counter() - t_start) * 1000.0
                    return PoseResult(frame_index=frame_index, face_detected=True, latency_ms=latency, flag="BBOX_ONLY")

            cam_matrix, dist_coeffs = get_camera_matrix(w, h)
            success, rvec, tvec = cv2.solvePnP(
                CANONICAL_5_POINTS_3D,
                image_points,
                cam_matrix,
                dist_coeffs,
                flags=cv2.SOLVEPNP_ITERATIVE
            )

            if not success:
                latency = (time.perf_counter() - t_start) * 1000.0
                return PoseResult(frame_index=frame_index, face_detected=True, latency_ms=latency, flag="SOLVEPNP_FAILED")

            R, _ = cv2.Rodrigues(rvec)
            yaw, pitch, roll = rotation_matrix_to_euler(R)
            latency = (time.perf_counter() - t_start) * 1000.0

            return PoseResult(
                frame_index=frame_index,
                face_detected=True,
                yaw=yaw,
                pitch=pitch,
                roll=roll,
                rotation_matrix=R,
                confidence=0.88,
                latency_ms=latency,
                flag="OK"
            )
        except Exception as e:
            latency = (time.perf_counter() - t_start) * 1000.0
            return PoseResult(frame_index=frame_index, face_detected=False, latency_ms=latency, flag=f"ERROR: {str(e)}")

    def reset(self):
        pass
