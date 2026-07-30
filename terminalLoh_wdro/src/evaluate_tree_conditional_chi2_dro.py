"""Backward recursion for a rectangular conditional chi-square tree."""

from __future__ import annotations

import time
from typing import Dict, Iterable, Mapping, Tuple

import numpy as np

from reconstruct_worst_leaf_probabilities import reconstruct_worst_leaf_probabilities
from solve_node_chi2_worst_expectation import solve_node_chi2_worst_expectation


def evaluate_tree_conditional_chi2_dro(
    root_id: str,
    children_by_parent: Mapping[str, Iterable[str]],
    nominal_conditional_probability: Mapping[Tuple[str, str], float],
    leaf_value: Mapping[str, float],
    eta_by_parent,
    stage_by_node: Mapping[str, int],
    reverse_parent_order: bool = False,
):
    started = time.perf_counter()
    value: Dict[str, float] = {str(k): float(v) for k, v in leaf_value.items()}
    worst_conditional: Dict[Tuple[str, str], float] = {}
    node_results = {}
    parent_nodes = [p for p, c in children_by_parent.items() if list(c)]
    parent_nodes.sort(key=lambda n: (stage_by_node[n], n), reverse=True)
    if reverse_parent_order:
        grouped = {}
        for node in parent_nodes:
            grouped.setdefault(stage_by_node[node], []).append(node)
        parent_nodes = []
        for stage in sorted(grouped, reverse=True):
            parent_nodes.extend(reversed(grouped[stage]))
    for parent in parent_nodes:
        children = list(children_by_parent[parent])
        q = np.asarray(
            [nominal_conditional_probability[(parent, child)] for child in children],
            dtype=float,
        )
        child_values = np.asarray([value[child] for child in children], dtype=float)
        eta = float(eta_by_parent[parent] if isinstance(eta_by_parent, dict) else eta_by_parent)
        result = solve_node_chi2_worst_expectation(q, child_values, eta)
        value[parent] = float(result["worst_value"])
        node_results[parent] = result
        for child, probability in zip(children, result["worst_probability"]):
            worst_conditional[(parent, child)] = float(probability)
    leaf_probability = reconstruct_worst_leaf_probabilities(
        root_id, children_by_parent, worst_conditional
    )
    weighted_leaf_value = sum(leaf_probability[k] * leaf_value[k] for k in leaf_value)
    return {
        "root_value": value[root_id],
        "worst_conditional_probability": worst_conditional,
        "worst_leaf_probability": leaf_probability,
        "node_results": node_results,
        "weighted_leaf_value": float(weighted_leaf_value),
        "root_weighted_leaf_abs_error": float(abs(value[root_id] - weighted_leaf_value)),
        "runtime_sec": float(time.perf_counter() - started),
    }


__all__ = ["evaluate_tree_conditional_chi2_dro"]
