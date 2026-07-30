"""Independent deterministic references for the node chi-square solver."""

from __future__ import annotations

import time
from typing import Iterable

import numpy as np
from scipy.optimize import minimize


def solve_node_chi2_reference_solver(
    nominal_probability: Iterable[float], values: Iterable[float], eta: float
):
    started = time.perf_counter()
    q = np.asarray(list(nominal_probability), dtype=float)
    q = q / np.sum(q)
    v = np.asarray(list(values), dtype=float)
    if q.size == 1 or eta <= 1e-14 or np.ptp(v) <= 1e-14:
        p = q.copy()
        status = "OPTIMAL_DEGENERATE"
    else:
        constraints = [
            {"type": "eq", "fun": lambda p: np.sum(p) - 1.0},
            {
                "type": "ineq",
                "fun": lambda p: float(eta - np.sum((p - q) ** 2 / q)),
            },
        ]
        result = minimize(
            lambda p: -float(np.dot(p, v)),
            q.copy(),
            method="SLSQP",
            bounds=[(0.0, 1.0)] * q.size,
            constraints=constraints,
            options={"ftol": 1e-13, "maxiter": 4000, "disp": False},
        )
        p = np.maximum(result.x, 0.0)
        p = p / np.sum(p)
        status = "OPTIMAL" if result.success else "FAILED: " + str(result.message)
    return {
        "worst_value": float(np.dot(p, v)),
        "worst_probability": p,
        "divergence_used": float(np.sum((p - q) ** 2 / q)),
        "probability_sum_residual": float(abs(np.sum(p) - 1.0)),
        "minimum_probability": float(np.min(p)),
        "solver_status": status,
        "runtime_sec": float(time.perf_counter() - started),
        "method_used": "independent_scipy_slsqp_convex_nlp",
    }


def binary_probability_interval(q_left: float, eta: float):
    q_left = float(q_left)
    radius = np.sqrt(max(0.0, float(eta)) * q_left * (1.0 - q_left))
    return max(0.0, q_left - radius), min(1.0, q_left + radius)


__all__ = ["solve_node_chi2_reference_solver", "binary_probability_interval"]
