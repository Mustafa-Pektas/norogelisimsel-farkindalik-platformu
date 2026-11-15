"""Shared recorded-rotation processing; no model imports or label inputs."""
import numpy as np
from scipy.spatial.transform import Rotation


def causal_ema_matrices(matrices, alpha, break_before=()):
    """Existing relative SO(3) log/exp EMA. None breaks continuity, no fill."""
    result=[]; previous=None
    for index,matrix in enumerate(matrices):
        if index in break_before:previous=None
        if matrix is None:
            previous=None; result.append(None)
            continue
        previous=matrix if previous is None else previous @ Rotation.from_rotvec(
            alpha * Rotation.from_matrix(previous.T @ matrix).as_rotvec()).as_matrix()
        result.append(previous.copy())
    return result
