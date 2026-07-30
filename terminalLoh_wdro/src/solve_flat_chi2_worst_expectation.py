"""Flat finite-support Pearson chi-square worst expectation."""

from __future__ import annotations

from typing import Iterable

from solve_node_chi2_worst_expectation import solve_node_chi2_worst_expectation


def solve_flat_chi2_worst_expectation(
    nominal_probability: Iterable[float], values: Iterable[float], eta: float
):
    result = solve_node_chi2_worst_expectation(nominal_probability, values, eta)
    result["method_used"] = "flat_" + str(result["method_used"])
    return result


__all__ = ["solve_flat_chi2_worst_expectation"]
