"""
Tüm Baş Pozu ve Bakış Tahmin Modelleri için Ortak Taban Sınıf (Base Estimator).
"""
from abc import ABC, abstractmethod
from typing import Optional
import numpy as np
from common.types import PoseResult


class BaseEstimator(ABC):
    def __init__(self, name: str):
        self.name = name
        self.is_ready = False

    @abstractmethod
    def setup(self) -> bool:
        """Modeli, ağırlıkları ve kütüphaneleri belleğe yükler."""
        pass

    @abstractmethod
    def predict(self, frame_bgr: np.ndarray, frame_index: int, timestamp: Optional[float] = None) -> PoseResult:
        """Tek bir video karesi (BGR formatında) alıp standart PoseResult döner."""
        pass

    @abstractmethod
    def reset(self):
        """Video geçişlerinde filtre ve dahili durumları sıfırlar."""
        pass
