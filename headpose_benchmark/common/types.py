"""
Ortak veri tipleri ve veri yapıları.
Tüm tahmin modelleri bu standart sınıfla çıktı verir.
"""
from dataclasses import dataclass, field
from typing import Optional, List, Dict, Any
import numpy as np


@dataclass
class PoseResult:
    frame_index: int
    face_detected: bool
    yaw: Optional[float] = None        # Derece cinsinden (sağa dönüş pozitif +)
    pitch: Optional[float] = None      # Derece cinsinden (yukarı bakış pozitif +)
    roll: Optional[float] = None       # Derece cinsinden (sağa yatış pozitif +)
    rotation_matrix: Optional[np.ndarray] = None  # 3x3 SO(3) rotasyon matrisi
    gaze_yaw: Optional[float] = None   # Göz bebeği yatay bakış açısı (kaba oran)
    gaze_pitch: Optional[float] = None # Göz bebeği dikey bakış açısı
    confidence: float = 0.0
    latency_ms: float = 0.0            # Bu kare için saf çıkarım süresi (milisaniye)
    flag: str = "OK"                   # "OK", "NO_FACE_DETECTED", "TRACKING_LOST", "DRIFT_CORRECTED"
    metadata: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "frame_index": self.frame_index,
            "face_detected": self.face_detected,
            "yaw": round(self.yaw, 2) if self.yaw is not None else None,
            "pitch": round(self.pitch, 2) if self.pitch is not None else None,
            "roll": round(self.roll, 2) if self.roll is not None else None,
            "gaze_yaw": round(self.gaze_yaw, 2) if self.gaze_yaw is not None else None,
            "gaze_pitch": round(self.gaze_pitch, 2) if self.gaze_pitch is not None else None,
            "confidence": round(self.confidence, 3),
            "latency_ms": round(self.latency_ms, 2),
            "flag": self.flag,
            "metadata": self.metadata,
        }
