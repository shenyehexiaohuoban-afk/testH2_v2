"""Reconstruct leaf probabilities from parent-child conditional probabilities."""

from __future__ import annotations

from typing import Dict, Iterable, Mapping, Tuple


def reconstruct_worst_leaf_probabilities(
    root_id: str,
    children_by_parent: Mapping[str, Iterable[str]],
    conditional_probability: Mapping[Tuple[str, str], float],
) -> Dict[str, float]:
    mass = {root_id: 1.0}
    stack = [root_id]
    leaves: Dict[str, float] = {}
    while stack:
        parent = stack.pop()
        children = list(children_by_parent.get(parent, []))
        if not children:
            leaves[parent] = mass[parent]
            continue
        for child in children:
            mass[child] = mass[parent] * float(conditional_probability[(parent, child)])
            stack.append(child)
    return leaves


__all__ = ["reconstruct_worst_leaf_probabilities"]
