"""
Zaman serisi yumuşatma ve gürültü azaltma filtreleri:
1. OneEuroFilter (Casiez et al.): Düşük hızda jitter'ı yok eder, yüksek hızda gecikmeyi sıfırlar.
2. AngleKalmanFilter: Basit 1D Kalman filtreleme.
"""
import math
import time
from typing import Optional


class OneEuroFilter:
    """
    1-Euro Filter for real-time human motion tracking.
    Reference: Géry Casiez, Nicolas Roussel, Daniel Vogel (CHI 2012).
    """
    def __init__(self, min_cutoff: float = 1.0, beta: float = 0.007, d_cutoff: float = 1.0):
        self.min_cutoff = float(min_cutoff)
        self.beta = float(beta)
        self.d_cutoff = float(d_cutoff)
        self.x_prev: Optional[float] = None
        self.dx_prev: float = 0.0
        self.t_prev: Optional[float] = None

    def _alpha(self, rate: float, cutoff: float) -> float:
        tau = 1.0 / (2.0 * math.pi * cutoff)
        te = 1.0 / rate if rate > 0 else 0.0
        return 1.0 / (1.0 + tau / te) if (te + tau) > 0 else 1.0

    def filter(self, x: float, timestamp: Optional[float] = None) -> float:
        if timestamp is None:
            timestamp = time.perf_counter()

        if self.t_prev is None or self.x_prev is None:
            self.x_prev = x
            self.dx_prev = 0.0
            self.t_prev = timestamp
            return x

        dt = timestamp - self.t_prev
        self.t_prev = timestamp
        if dt <= 0.0:
            return self.x_prev

        rate = 1.0 / dt

        # Filtrelenmiş türev (hız)
        dx = (x - self.x_prev) * rate
        a_d = self._alpha(rate, self.d_cutoff)
        dx_hat = a_d * dx + (1.0 - a_d) * self.dx_prev
        self.dx_prev = dx_hat

        # Dinamik kesme frekansı
        cutoff = self.min_cutoff + self.beta * abs(dx_hat)
        a = self._alpha(rate, cutoff)
        x_hat = a * x + (1.0 - a) * self.x_prev
        self.x_prev = x_hat

        return x_hat

    def reset(self):
        self.x_prev = None
        self.dx_prev = 0.0
        self.t_prev = None


class AngleKalmanFilter:
    """
    Sabit hızlı 1D Kalman filtresi: [açı, açısal_hız]
    """
    def __init__(self, process_noise: float = 1e-2, measurement_noise: float = 1e-1):
        self.q = process_noise
        self.r = measurement_noise
        self.x: float = 0.0      # Açı tahmini
        self.v: float = 0.0      # Açısal hız tahmini
        self.p_xx: float = 1.0   # Hata kovaryansı
        self.p_xv: float = 0.0
        self.p_vv: float = 1.0
        self.initialized = False
        self.last_time: Optional[float] = None

    def filter(self, measurement: float, timestamp: Optional[float] = None) -> float:
        if timestamp is None:
            timestamp = time.perf_counter()

        if not self.initialized or self.last_time is None:
            self.x = measurement
            self.v = 0.0
            self.p_xx = 1.0
            self.p_xv = 0.0
            self.p_vv = 1.0
            self.initialized = True
            self.last_time = timestamp
            return measurement

        dt = max(1e-4, timestamp - self.last_time)
        self.last_time = timestamp

        # Tahmin (Predict)
        x_pred = self.x + self.v * dt
        v_pred = self.v
        p_xx_pred = self.p_xx + 2.0 * dt * self.p_xv + dt * dt * self.p_vv + self.q
        p_xv_pred = self.p_xv + dt * self.p_vv
        p_vv_pred = self.p_vv + self.q

        # Güncelleme (Update)
        innov = measurement - x_pred
        s = p_xx_pred + self.r
        k_x = p_xx_pred / s
        k_v = p_xv_pred / s

        self.x = x_pred + k_x * innov
        self.v = v_pred + k_v * innov
        self.p_xx = (1.0 - k_x) * p_xx_pred
        self.p_xv = (1.0 - k_x) * p_xv_pred
        self.p_vv = -k_v * p_xv_pred + p_vv_pred

        return self.x

    def reset(self):
        self.initialized = False
        self.last_time = None
