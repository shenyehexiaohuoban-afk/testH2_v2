"""Exact finite-support Pearson chi-square worst expectation.

The implementation uses the KKT active-set solution and never constructs a
pairwise scenario matrix. Nominal probabilities must be strictly positive;
zero-probability support is excluded by the caller.
"""

from __future__ import annotations

import time
from typing import Dict, Iterable

import numpy as np


def _divergence(p: np.ndarray, q: np.ndarray) -> float:
    return float(np.sum((p - q) ** 2 / q))


def solve_node_chi2_worst_expectation(
    nominal_probability: Iterable[float],
    values: Iterable[float],
    eta: float,
    tolerance: float = 1e-12,
) -> Dict[str, object]:
    """Maximize ``p @ values`` in a Pearson chi-square ball around ``q``."""

    started = time.perf_counter()
    q = np.asarray(list(nominal_probability), dtype=float).reshape(-1)
    v = np.asarray(list(values), dtype=float).reshape(-1)
    if q.size == 0 or q.shape != v.shape:
        raise ValueError("q and values must be nonempty vectors of equal length")
    if not np.all(np.isfinite(q)) or not np.all(q > 0):
        raise ValueError("all nominal probabilities must be finite and positive")
    if not np.all(np.isfinite(v)):
        raise ValueError("all child values must be finite")
    if not np.isfinite(eta) or eta < -tolerance:
        raise ValueError("eta must be finite and nonnegative")
    eta = max(0.0, float(eta))
    q = q / np.sum(q)

    if q.size == 1:
        p = np.ones(1)
        method = "single_child_degenerate"
    elif eta <= tolerance:
        p = q.copy()
        method = "eta_zero_degenerate"
    elif float(np.max(v) - np.min(v)) <= tolerance:
        p = q.copy()
        method = "constant_value_degenerate"
    else:
        vmax = float(np.max(v))
        max_mask = np.abs(v - vmax) <= tolerance * max(1.0, abs(vmax))
        qmax = float(np.sum(q[max_mask]))
        eta_to_max = 1.0 / qmax - 1.0
        if eta >= eta_to_max - tolerance:
            p = np.zeros_like(q)
            p[max_mask] = q[max_mask] / qmax
            method = "maximum_value_face"
        else:
            active = np.ones(q.size, dtype=bool)
            for _ in range(q.size + 1):
                qa = q[active]
                va = v[active]
                qsum = float(np.sum(qa))
                minimum_divergence = 1.0 / qsum - 1.0
                remaining = eta - minimum_divergence
                if remaining < -100.0 * tolerance:
                    raise RuntimeError("active-set divergence exceeded eta")
                mean_value = float(np.dot(qa, va) / qsum)
                variance_numerator = float(np.dot(qa, (va - mean_value) ** 2))
                if variance_numerator <= tolerance:
                    pa = qa / qsum
                else:
                    scale = np.sqrt(max(0.0, remaining) / variance_numerator)
                    pa = qa / qsum + scale * qa * (va - mean_value)
                negative_local = np.where(pa < -100.0 * tolerance)[0]
                if negative_local.size == 0:
                    p = np.zeros_like(q)
                    p[np.where(active)[0]] = np.maximum(pa, 0.0)
                    p = p / np.sum(p)
                    method = "kkt_active_set"
                    break
                active_indices = np.where(active)[0]
                active[active_indices[negative_local]] = False
            else:
                raise RuntimeError("chi-square active-set solver did not converge")

    divergence = _divergence(p, q)
    probability_sum_residual = float(abs(np.sum(p) - 1.0))
    minimum_probability = float(np.min(p))
    feasible = (
        probability_sum_residual <= 1e-10
        and minimum_probability >= -1e-10
        and divergence <= eta + 1e-9
    )
    return {
        "worst_value": float(np.dot(p, v)),
        "worst_probability": p,
        "nominal_probability": q,
        "eta": eta,
        "divergence_used": divergence,
        "probability_sum_residual": probability_sum_residual,
        "minimum_probability": minimum_probability,
        "solver_status": "OPTIMAL" if feasible else "NUMERICAL_FAILURE",
        "runtime_sec": float(time.perf_counter() - started),
        "method_used": method,
    }


__all__ = ["solve_node_chi2_worst_expectation"]
