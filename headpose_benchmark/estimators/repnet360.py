"""
6DRepNet360 Ağır Derin Öğrenme Modeli (Referans Zemin)
research/d01/official_runtime.py ile birebir aynı ön-işleme ve SO(3) çıkarım mantığını kullanır;
Euler açılarını ise Gimbal-Lock korumalı rotation_matrix_to_euler ile raporlar.

İki arka uç:
  - backend="torch": resmi PyTorch kaynak kodu + .pth ağırlıkları (CPU).
  - backend="onnx" : tools/export_6drepnet_onnx.py ile dışa aktarılmış .onnx + ONNX Runtime (CPU).
                     PyTorch / torchvision GEREKMEZ; ön-işleme PIL + NumPy ile torchvision ile birebir aynıdır
                     (Resize(256, bilinear) -> CenterCrop(224) -> ToTensor -> Normalize).
Yol geçersiz kılma (yerel test / farklı sunucu düzeni için) ortam değişkenleri:
  REPNET360_WEIGHTS, REPNET360_SOURCE, REPNET360_ONNX
"""
import os
import sys
import time
import importlib
from pathlib import Path
from typing import Optional, List

import numpy as np
import cv2

from estimators.base import BaseEstimator
from common.types import PoseResult
from common.geometry import rotation_matrix_to_euler


DEFAULT_WEIGHTS = [
    "/opt/norogelisim/araclar/6DRepNet360_Full-Rotation_300W_LP+Panoptic.pth",
    "C:/Projeler/Norogelisim/araclar/6DRepNet360_Full-Rotation_300W_LP+Panoptic.pth",
]
DEFAULT_SOURCES = [
    "/opt/norogelisim/dis_kaynaklar/6DRepNet360",
    "C:/Projeler/Norogelisim/dis_kaynaklar/6DRepNet360",
]
DEFAULT_ONNX = [
    "/opt/norogelisim/araclar/6DRepNet360_Full-Rotation_300W_LP+Panoptic.onnx",
    "C:/Projeler/Norogelisim/araclar/6DRepNet360_Full-Rotation_300W_LP+Panoptic.onnx",
]
IMAGENET_MEAN = np.array([0.485, 0.456, 0.406], dtype=np.float32)
IMAGENET_STD = np.array([0.229, 0.224, 0.225], dtype=np.float32)


def _first_existing(paths: List[Optional[str]]) -> Optional[str]:
    return next((p for p in paths if p and os.path.exists(p)), None)


def preprocess_numpy(roi_bgr: np.ndarray) -> np.ndarray:
    """torchvision Resize(256)+CenterCrop(224)+ToTensor+Normalize ile birebir aynı (PIL bilinear)."""
    from PIL import Image

    img = Image.fromarray(cv2.cvtColor(roi_bgr, cv2.COLOR_BGR2RGB))
    w, h = img.size
    if w <= h:
        nw, nh = 256, int(256 * h / w)
    else:
        nw, nh = int(256 * w / h), 256
    img = img.resize((nw, nh), Image.BILINEAR)
    top = int(round((nh - 224) / 2.0))
    left = int(round((nw - 224) / 2.0))
    img = img.crop((left, top, left + 224, top + 224))
    arr = np.asarray(img, dtype=np.float32) / 255.0
    arr = (arr - IMAGENET_MEAN) / IMAGENET_STD
    return np.ascontiguousarray(arr.transpose(2, 0, 1)[None, ...], dtype=np.float32)


def ortho6d_to_rotation_matrix(poses: np.ndarray) -> np.ndarray:
    """6DRepNet utils.compute_rotation_matrix_from_ortho6d'nin NumPy karşılığı (sütunlar x, y, z)."""
    p = np.asarray(poses, dtype=np.float64).reshape(-1, 6)
    x_raw, y_raw = p[:, 0:3], p[:, 3:6]
    x = x_raw / np.maximum(np.linalg.norm(x_raw, axis=1, keepdims=True), 1e-8)
    z = np.cross(x, y_raw)
    z = z / np.maximum(np.linalg.norm(z, axis=1, keepdims=True), 1e-8)
    y = np.cross(z, x)
    return np.stack([x, y, z], axis=2)


class SixDRepNet360Estimator(BaseEstimator):
    def __init__(
        self,
        weights_path: Optional[str] = None,
        official_source: Optional[str] = None,
        cpu_threads: int = 4,
        backend: str = "torch",
        onnx_path: Optional[str] = None,
    ):
        if backend not in ("torch", "onnx"):
            raise ValueError("backend 'torch' veya 'onnx' olmalıdır")
        super().__init__(name="6DRepNet360_Heavy_Reference" + ("_ONNX" if backend == "onnx" else ""))
        self.weights_path = weights_path
        self.official_source = official_source
        self.onnx_path = onnx_path
        self.cpu_threads = cpu_threads
        self.backend = backend
        self.model = None
        self.utils = None
        self.session = None
        self.input_name = None
        self.resize = None
        self.crop = None
        self.normalize = None

    # ------------------------------------------------------------------ kurulum
    def setup(self) -> bool:
        return self._setup_onnx() if self.backend == "onnx" else self._setup_torch()

    def _setup_onnx(self) -> bool:
        found = _first_existing([self.onnx_path, os.environ.get("REPNET360_ONNX")] + DEFAULT_ONNX)
        if not found:
            print("    [6DRepNet360 ONNX] .onnx dosyası bulunamadı (tools/export_6drepnet_onnx.py ile üretin).")
            self.is_ready = False
            return False
        try:
            import onnxruntime as ort

            so = ort.SessionOptions()
            so.intra_op_num_threads = self.cpu_threads
            so.inter_op_num_threads = 1
            so.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
            so.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
            self.session = ort.InferenceSession(found, sess_options=so, providers=["CPUExecutionProvider"])
            self.input_name = self.session.get_inputs()[0].name
            self.onnx_path = found
            self.is_ready = True
            return True
        except Exception as exc:
            print(f"    [6DRepNet360 ONNX Setup Hatası]: {exc}")
            self.is_ready = False
            return False

    def _setup_torch(self) -> bool:
        found_weights = _first_existing([self.weights_path, os.environ.get("REPNET360_WEIGHTS")] + DEFAULT_WEIGHTS)
        found_source = _first_existing([self.official_source, os.environ.get("REPNET360_SOURCE")] + DEFAULT_SOURCES)
        if not found_weights or not found_source:
            self.is_ready = False
            return False

        try:
            import torch
            import torchvision
            from torchvision import transforms

            torch.set_num_threads(self.cpu_threads)

            source_path = Path(found_source).resolve() / "sixdrepnet360"
            if str(source_path) not in sys.path:
                sys.path.insert(0, str(source_path))

            test_mod = importlib.import_module("test")
            utils_mod = importlib.import_module("utils")

            self.model = test_mod.SixDRepNet360(
                torchvision.models.resnet.Bottleneck, [3, 4, 6, 3], 6
            ).cpu()
            state = torch.load(found_weights, map_location="cpu", weights_only=True)
            state = state["model_state_dict"] if "model_state_dict" in state else state
            self.model.load_state_dict(state, strict=True)
            self.model.eval()
            self.utils = utils_mod
            self.test_module = test_mod
            self.weights_path = found_weights

            self.resize = transforms.Resize(256)
            self.crop = transforms.CenterCrop(224)
            self.normalize = transforms.Compose([
                transforms.ToTensor(),
                transforms.Normalize([0.485, 0.456, 0.406], [0.229, 0.224, 0.225]),
            ])

            self.is_ready = True
            return True
        except Exception as exc:
            print(f"    [6DRepNet360 Setup Hatası]: {exc}")
            self.is_ready = False
            return False

    # ------------------------------------------------------------------ çıkarım
    def infer_rotation(self, roi_bgr: np.ndarray) -> np.ndarray:
        """Tek ROI için 3x3 rotasyon matrisi (float64)."""
        if self.backend == "onnx":
            out = self.session.run(None, {self.input_name: preprocess_numpy(roi_bgr)})[0]
            out = np.asarray(out)
            if out.shape[-2:] == (3, 3):
                return out.reshape(-1, 3, 3)[0].astype(np.float64)
            return ortho6d_to_rotation_matrix(out)[0]

        import torch
        from PIL import Image

        pil_img = Image.fromarray(cv2.cvtColor(roi_bgr, cv2.COLOR_BGR2RGB))
        tensor = self.normalize(self.crop(self.resize(pil_img))).unsqueeze(0).cpu()
        with torch.inference_mode():
            result = self.model(tensor)
        return result[0].cpu().numpy().astype(np.float64)

    def predict(self, roi_bgr: np.ndarray, frame_index: int, timestamp: Optional[float] = None) -> PoseResult:
        if not self.is_ready or (self.model is None and self.session is None):
            return PoseResult(frame_index=frame_index, face_detected=False, flag="MODEL_OR_WEIGHTS_NOT_FOUND")

        t_start = time.perf_counter()
        try:
            R_np = self.infer_rotation(roi_bgr)
            # Gimbal-Lock korumalı Euler ayrıştırması
            yaw_deg, pitch_deg, roll_deg = rotation_matrix_to_euler(R_np)
            latency = (time.perf_counter() - t_start) * 1000.0
            return PoseResult(
                frame_index=frame_index,
                face_detected=True,
                yaw=yaw_deg,
                pitch=pitch_deg,
                roll=roll_deg,
                rotation_matrix=R_np,
                confidence=0.98,
                latency_ms=latency,
                flag="OK",
                metadata={"repnet_backend": self.backend},
            )
        except Exception as e:
            latency = (time.perf_counter() - t_start) * 1000.0
            return PoseResult(
                frame_index=frame_index,
                face_detected=False,
                latency_ms=latency,
                flag=f"INFERENCE_ERROR: {str(e)}",
            )

    def reset(self):
        pass
