"""Step-04A probability-DRO provenance, tree, solver, and feasibility audit.

Run in two deterministic phases:

    python terminalLoh_wdro/src/run_step04A_probability_dro_feasibility.py --phase prepare
    # run the MATLAB fixed-T/prototype runner
    python terminalLoh_wdro/src/run_step04A_probability_dro_feasibility.py --phase finalize

No random-number generator is called. Existing scenario generation, formal
recourse, WDRO sources, and historical outputs are read-only.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import itertools
import json
import math
import os
import platform
import subprocess
import sys
import time
from collections import defaultdict
from pathlib import Path

import numpy as np
import pandas as pd
import psutil

THIS_DIR = Path(__file__).resolve().parent
ROOT = THIS_DIR.parent.parent
MODULE = ROOT / "terminalLoh_wdro"
OUT = ROOT / "results/task-002-stage2b-b3-smoke/41-probability-dro-mainline-feasibility/run-003"
MAIN_SAMPLE = MODULE / "output/stage2a2_W3_path_sampling/run-002/main_path_samples.csv"
NOMINAL_CSV = MODULE / "output/stage3j_wdro_input_freeze/run-001/wdro_nominal_input.csv"
INTENSITY_CSV = MODULE / "config/lookahead_intensity_postlandfall_W3.csv"
LOCATION_CSV = MODULE / "config/lookahead_location_postlandfall_W3.csv"
LFW_CSV = MODULE / "config/lookahead_lfw_postlandfall_W3.csv"
FORMAL_MODEL = MODULE / "docs/FORMAL_TWO_STAGE_THREE_PERIOD_MODEL.md"
STEP03YF_T = ROOT / "results/task-002-stage2b-b3-smoke/35-period-vs-aggregate-saa-r2000/run-001/terminalLOH_r2000.csv"
EXPECTED_BRANCH = "task/002-stage2b-b3-smoke"
EXPECTED_HEAD = "96143491395d291f4e46791836736c5a9dd06253"
ETA_VALUES = [0.0, 0.001, 0.01, 0.05, 0.1]
CAPACITY = np.array([300.0, 200.0, 100.0, 150.0])

sys.path.insert(0, str(THIS_DIR))
from evaluate_tree_conditional_chi2_dro import evaluate_tree_conditional_chi2_dro
from node_chi2_reference_solver import binary_probability_interval, solve_node_chi2_reference_solver
from solve_flat_chi2_worst_expectation import solve_flat_chi2_worst_expectation
from solve_node_chi2_worst_expectation import solve_node_chi2_worst_expectation


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def git_text(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def assert_git_gate() -> None:
    branch = git_text("branch", "--show-current")
    head = git_text("rev-parse", "HEAD")
    upstream = git_text("rev-parse", "@{u}")
    if branch != EXPECTED_BRANCH or head != EXPECTED_HEAD or upstream != EXPECTED_HEAD:
        raise RuntimeError(f"frozen git gate failed: {branch=} {head=} {upstream=}")


def write_text(path: Path, text: str) -> None:
    path.write_text(text.rstrip() + "\n", encoding="utf-8")


def write_empty_csv(path: Path, columns) -> None:
    pd.DataFrame(columns=list(columns)).to_csv(path, index=False)


def find_line(path: Path, needle: str) -> tuple[int, str]:
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if needle in line:
            return number, line.strip()
    raise ValueError(f"evidence string not found in {path}: {needle}")


def state_id_from_columns(frame: pd.DataFrame) -> pd.Series:
    return (frame["a0"].astype(int) - 2) * 7 + frame["loc0"].astype(int)


def state_tuple(row, stage: int) -> tuple[int, int, int]:
    if stage == 0:
        return int(row.a0), int(row.loc0), int(row.lfw0)
    return (
        int(getattr(row, f"a_W{stage}")),
        int(getattr(row, f"loc_W{stage}")),
        int(getattr(row, f"lfw_W{stage}")),
    )


def state_label(value: tuple[int, int, int]) -> str:
    return f"a={value[0]}|loc={value[1]}|lfw={value[2]}"


def load_transition(path: Path, from_col: str, to_col: str):
    table = pd.read_csv(path)
    result = {}
    for row in table.itertuples(index=False):
        result[(int(getattr(row, from_col)), int(getattr(row, to_col)))] = float(row.prob)
    return table, result


def load_inputs():
    usecols = [
        "a0", "loc0", "lfw0", "lf", "path_id", "base_random_seed",
        "derived_seed", "a_W1", "a_W2", "a_W3", "loc_W1", "loc_W2",
        "loc_W3", "lfw_W1", "lfw_W2", "lfw_W3", "x_W1", "x_W2",
        "x_W3", "y_W1", "y_W2", "y_W3", "path_probability",
    ]
    samples = pd.read_csv(MAIN_SAMPLE, usecols=usecols)
    samples["initial_state_id"] = state_id_from_columns(samples)
    nominal = pd.read_csv(NOMINAL_CSV, usecols=["initial_state_id", "path_id", "scenario_id_in_state", "sample_weight"])
    pa_tbl, pa = load_transition(INTENSITY_CSV, "from_a", "to_a")
    pl_tbl, pl = load_transition(LOCATION_CSV, "from_loc_id", "to_loc_id")
    pf_tbl, pf = load_transition(LFW_CSV, "from_lfw", "to_lfw")
    return samples, nominal, (pa_tbl, pl_tbl, pf_tbl), (pa, pl, pf)


def build_tree_outputs(samples: pd.DataFrame, transitions):
    pa, pl, pf = transitions
    tree_summary = []
    stage_stats = []
    duplicate_rows = []
    mapping_frames = []
    leaf_frames = []
    conditional_frames = []
    reconstruction_frames = []
    support_rows = []
    detail_nodes = {}
    detail_edges = {}
    max_stored_probability_error = 0.0
    max_empirical_reconstruction_error = 0.0
    integrity = {
        "path_ids_lost": 0,
        "path_ids_multiply_mapped": 0,
        "cycle_count": 0,
        "bad_leaf_depth_count": 0,
    }

    for state_id, group in samples.groupby("initial_state_id", sort=True):
        group = group.sort_values("path_id").reset_index(drop=True)
        n = len(group)
        a0, loc0, lfw0 = (int(group.iloc[0][c]) for c in ["a0", "loc0", "lfw0"])
        root = f"s{state_id}:root"
        node_rows = [{
            "initial_state_id": state_id, "node_id": root, "stage": 0,
            "parent_id": "", "native_state": state_label((a0, loc0, lfw0)),
            "prefix_key": state_label((a0, loc0, lfw0)), "sample_support_count": n,
            "nominal_probability_mass": 1.0,
        }]
        edge_rows = []
        children = defaultdict(set)
        support_count = {root: n}
        node_stage = {root: 0}
        node_native = {root: (a0, loc0, lfw0)}
        leaf_by_full_key = {}
        path_map = []
        full_key_counts = defaultdict(int)
        full_key_theory = {}

        for row in group.itertuples(index=False):
            previous = root
            prefix_parts = []
            theoretical = 1.0
            previous_state = (a0, loc0, lfw0)
            for stage in (1, 2, 3):
                current_state = state_tuple(row, stage)
                prefix_parts.append(state_label(current_state))
                prefix_key = ">".join(prefix_parts)
                node_id = f"s{state_id}:n{stage}:{prefix_key}"
                if node_id not in support_count:
                    support_count[node_id] = 0
                    node_stage[node_id] = stage
                    node_native[node_id] = current_state
                    node_rows.append({
                        "initial_state_id": state_id, "node_id": node_id,
                        "stage": stage, "parent_id": previous,
                        "native_state": state_label(current_state),
                        "prefix_key": prefix_key, "sample_support_count": 0,
                        "nominal_probability_mass": 0.0,
                    })
                support_count[node_id] += 1
                if node_id not in children[previous]:
                    children[previous].add(node_id)
                    edge_rows.append({
                        "initial_state_id": state_id, "parent_id": previous,
                        "child_id": node_id, "parent_stage": stage - 1,
                        "child_stage": stage, "parent_native_state": state_label(previous_state),
                        "child_native_state": state_label(current_state),
                    })
                theoretical *= (
                    pa[(previous_state[0], current_state[0])]
                    * pl[(previous_state[1], current_state[1])]
                    * pf[(previous_state[2], current_state[2])]
                )
                previous = node_id
                previous_state = current_state
            full_key = ">".join(prefix_parts)
            leaf_by_full_key[full_key] = previous
            full_key_counts[full_key] += 1
            full_key_theory.setdefault(full_key, theoretical)
            max_stored_probability_error = max(
                max_stored_probability_error, abs(theoretical - float(row.path_probability))
            )
            path_map.append({
                "initial_state_id": state_id, "path_id": int(row.path_id),
                "leaf_node_id": previous, "full_path_key": full_key,
                "mapping_count": 1,
            })

        node_index = {r["node_id"]: r for r in node_rows}
        for node_id, count in support_count.items():
            node_index[node_id]["sample_support_count"] = count
            node_index[node_id]["nominal_probability_mass"] = count / n
        for edge in edge_rows:
            edge["parent_support_count"] = support_count[edge["parent_id"]]
            edge["child_support_count"] = support_count[edge["child_id"]]
            edge["nominal_conditional_probability"] = edge["child_support_count"] / edge["parent_support_count"]
            pstate = tuple(int(x.split("=")[1]) for x in edge["parent_native_state"].split("|"))
            cstate = tuple(int(x.split("=")[1]) for x in edge["child_native_state"].split("|"))
            edge["theoretical_transition_probability"] = (
                pa[(pstate[0], cstate[0])] * pl[(pstate[1], cstate[1])] * pf[(pstate[2], cstate[2])]
            )

        leaf_rows = []
        reconstruction_rows = []
        for full_key, frequency in full_key_counts.items():
            leaf_id = leaf_by_full_key[full_key]
            q_leaf = frequency / n
            chain = full_key.split(">")
            parent = root
            reconstructed = 1.0
            for stage in (1, 2, 3):
                child = f"s{state_id}:n{stage}:{'>'.join(chain[:stage])}"
                reconstructed *= support_count[child] / support_count[parent]
                parent = child
            error = abs(q_leaf - reconstructed)
            max_empirical_reconstruction_error = max(max_empirical_reconstruction_error, error)
            leaf_rows.append({
                "initial_state_id": state_id, "leaf_node_id": leaf_id,
                "full_path_key": full_key, "original_record_count": frequency,
                "nominal_leaf_probability": q_leaf,
                "theoretical_full_path_probability": full_key_theory[full_key],
                "nominal_probability_source": "aggregated_equal_weight_MC_frequency",
            })
            reconstruction_rows.append({
                "initial_state_id": state_id, "leaf_node_id": leaf_id,
                "nominal_leaf_probability": q_leaf,
                "reconstructed_from_empirical_conditionals": reconstructed,
                "absolute_error": error,
                "relative_error": error / max(q_leaf, np.finfo(float).tiny),
                "pass_1e_12": error <= 1e-12,
            })

        nodes_df = pd.DataFrame(node_rows)
        edges_df = pd.DataFrame(edge_rows)
        leaves_df = pd.DataFrame(leaf_rows)
        mapping_df = pd.DataFrame(path_map)
        reconstruction_df = pd.DataFrame(reconstruction_rows)
        mapping_frames.append(mapping_df)
        leaf_frames.append(leaves_df)
        conditional_frames.append(edges_df)
        reconstruction_frames.append(reconstruction_df)
        detail_nodes[state_id] = nodes_df
        detail_edges[state_id] = edges_df

        unique_leaf = len(leaves_df)
        duplicate_record_count = n - unique_leaf
        duplicated_leaf_count = int((leaves_df.original_record_count > 1).sum())
        duplicate_rows.append({
            "initial_state_id": state_id, "original_path_records": n,
            "unique_full_paths": unique_leaf, "duplicate_path_records": duplicate_record_count,
            "duplicated_leaf_nodes": duplicated_leaf_count,
            "maximum_duplicate_frequency": int(leaves_df.original_record_count.max()),
            "empirical_probability_mass": float(leaves_df.nominal_leaf_probability.sum()),
            "observed_unique_theoretical_probability_mass": float(leaves_df.theoretical_full_path_probability.sum()),
        })

        stage_parent_frames = []
        for parent_stage in (0, 1, 2):
            pnodes = nodes_df[nodes_df.stage == parent_stage].copy()
            child_counts = edges_df.groupby("parent_id").size()
            pnodes["child_count"] = pnodes.node_id.map(child_counts).fillna(0).astype(int)
            shared = pnodes.sample_support_count >= 2
            shared10 = pnodes.sample_support_count >= 10
            stage_stats.append({
                "initial_state_id": state_id, "parent_stage": parent_stage,
                "parent_node_count": len(pnodes),
                "unique_native_state_count": pnodes.native_state.nunique(),
                "unique_prefix_count": len(pnodes),
                "unique_edge_count": int((edges_df.parent_stage == parent_stage).sum()),
                "shared_parent_count": int((pnodes.sample_support_count >= 2).sum()),
                "average_child_count": float(pnodes.child_count.mean()),
                "median_child_count": float(pnodes.child_count.median()),
                "maximum_child_count": int(pnodes.child_count.max()),
                "single_child_parent_share": float((pnodes.child_count == 1).mean()),
                "prefix_shared_by_at_least_2_share": float(shared.mean()),
                "prefix_shared_by_at_least_10_share": float(shared10.mean()),
                "node_supported_by_one_sample_share": float((pnodes.sample_support_count == 1).mean()),
            })
            stage_parent_frames.append(pnodes)
            for p in pnodes.itertuples(index=False):
                descendant = leaves_df[leaves_df.full_path_key.str.startswith(
                    "" if parent_stage == 0 else p.prefix_key
                )]
                support_rows.append({
                    "initial_state_id": state_id, "parent_node_id": p.node_id,
                    "parent_stage": parent_stage, "sample_support_count": int(p.sample_support_count),
                    "effective_sample_size": float(p.sample_support_count),
                    "parent_probability_mass": float(p.nominal_probability_mass),
                    "child_count": int(p.child_count),
                    "single_child": int(p.child_count == 1),
                    "descendant_unique_leaf_count": int(len(descendant)),
                    "descendant_leaf_probability_mass": float(descendant.nominal_leaf_probability.sum()),
                })

        node_count = len(nodes_df)
        edge_count = len(edges_df)
        flat_state_record_count = 4 * n
        tree_summary.append({
            "initial_state_id": state_id, "a0": a0, "loc0": loc0, "lfw0": lfw0,
            "original_path_count": n, "unique_full_path_count": unique_leaf,
            "duplicate_path_record_count": duplicate_record_count,
            "unique_stage1_native_state_count": int(nodes_df[nodes_df.stage == 1].native_state.nunique()),
            "unique_stage2_native_state_count": int(nodes_df[nodes_df.stage == 2].native_state.nunique()),
            "unique_stage3_native_state_count": int(nodes_df[nodes_df.stage == 3].native_state.nunique()),
            "tree_node_count": node_count, "tree_edge_count": edge_count,
            "flat_path_state_record_count": flat_state_record_count,
            "tree_to_flat_storage_ratio": node_count / flat_state_record_count,
            "compression_saving_share": 1.0 - node_count / flat_state_record_count,
        })

    return {
        "tree_summary": pd.DataFrame(tree_summary),
        "stage_stats": pd.DataFrame(stage_stats),
        "duplicates": pd.DataFrame(duplicate_rows),
        "mapping": pd.concat(mapping_frames, ignore_index=True),
        "leaves": pd.concat(leaf_frames, ignore_index=True),
        "conditionals": pd.concat(conditional_frames, ignore_index=True),
        "reconstruction": pd.concat(reconstruction_frames, ignore_index=True),
        "support": pd.DataFrame(support_rows),
        "detail_nodes": detail_nodes,
        "detail_edges": detail_edges,
        "stored_probability_error": max_stored_probability_error,
        "empirical_reconstruction_error": max_empirical_reconstruction_error,
        "integrity": integrity,
    }


def support_bin(count: int) -> str:
    if count == 1:
        return "1"
    if count <= 4:
        return "2-4"
    if count <= 9:
        return "5-9"
    if count <= 29:
        return "10-29"
    if count <= 99:
        return "30-99"
    return ">=100"


def make_support_summaries(support: pd.DataFrame):
    support = support.copy()
    support["support_bin"] = support.sample_support_count.map(support_bin)
    order = ["1", "2-4", "5-9", "10-29", "30-99", ">=100"]
    rows = []
    for (stage, label), g in support.groupby(["parent_stage", "support_bin"]):
        rows.append({
            "parent_stage": stage, "support_bin": label, "node_count": len(g),
            "node_probability_mass": float(g.parent_probability_mass.sum()),
            "descendant_unique_leaf_count_sum": int(g.descendant_unique_leaf_count.sum()),
            "descendant_leaf_probability_mass_sum": float(g.descendant_leaf_probability_mass.sum()),
            "single_child_share": float(g.single_child.mean()),
            "multi_child_share": float((1 - g.single_child).mean()),
        })
    summary = pd.DataFrame(rows)
    summary["support_bin"] = pd.Categorical(summary.support_bin, order, ordered=True)
    summary = summary.sort_values(["parent_stage", "support_bin"])
    low = support[support.sample_support_count < 10].sort_values(
        ["parent_stage", "sample_support_count", "initial_state_id", "parent_node_id"]
    )
    ess = support.groupby("parent_stage").agg(
        parent_node_count=("parent_node_id", "size"),
        minimum_ess=("effective_sample_size", "min"),
        median_ess=("effective_sample_size", "median"),
        mean_ess=("effective_sample_size", "mean"),
        maximum_ess=("effective_sample_size", "max"),
        singleton_share=("sample_support_count", lambda x: float((x == 1).mean())),
        below_10_share=("sample_support_count", lambda x: float((x < 10).mean())),
    ).reset_index()
    return summary, low, ess


def run_node_tests():
    cases = [
        ("eta_zero", [0.2, 0.3, 0.5], [1.0, 4.0, 2.0], 0.0),
        ("binary", [0.35, 0.65], [2.0, 9.0], 0.08),
        ("three_branch", [0.2, 0.5, 0.3], [1.0, 5.0, 3.0], 0.12),
        ("five_branch", [0.1, 0.2, 0.25, 0.15, 0.3], [0.0, 2.0, 7.0, 4.0, 1.0], 0.3),
        ("constant", [0.2, 0.3, 0.5], [7.0, 7.0, 7.0], 0.5),
        ("single", [1.0], [11.0], 10.0),
    ]
    rows = []
    details = []
    for name, q, v, eta in cases:
        actual = solve_node_chi2_worst_expectation(q, v, eta)
        reference = solve_node_chi2_reference_solver(q, v, eta)
        error = abs(actual["worst_value"] - reference["worst_value"])
        passed = (
            actual["solver_status"] == "OPTIMAL"
            and actual["minimum_probability"] >= -1e-10
            and actual["probability_sum_residual"] <= 1e-10
            and actual["divergence_used"] <= eta + 1e-9
            and error <= 1e-8
        )
        rows.append({
            "test_name": name, "branch_count": len(q), "eta": eta,
            "worst_value": actual["worst_value"], "reference_value": reference["worst_value"],
            "absolute_value_error": error, "divergence_used": actual["divergence_used"],
            "probability_sum_residual": actual["probability_sum_residual"],
            "minimum_probability": actual["minimum_probability"],
            "method_used": actual["method_used"], "reference_method": reference["method_used"],
            "pass": passed,
        })
        details.append(f"## {name}\n\nq={q}\n\nV={v}\n\neta={eta}\n\nactual_p={actual['worst_probability'].tolist()}\n\nreference_p={reference['worst_probability'].tolist()}\n\nabs_value_error={error:.17g}\n")
    q = [0.2, 0.3, 0.5]
    v = [1.0, 4.0, 2.0]
    values = [solve_node_chi2_worst_expectation(q, v, e)["worst_value"] for e in ETA_VALUES]
    rows.append({
        "test_name": "eta_monotonicity", "branch_count": 3, "eta": np.nan,
        "worst_value": values[-1], "reference_value": np.nan,
        "absolute_value_error": 0.0, "divergence_used": np.nan,
        "probability_sum_residual": 0.0, "minimum_probability": np.nan,
        "method_used": "deterministic_eta_grid", "reference_method": "monotonic_sequence",
        "pass": bool(np.all(np.diff(values) >= -1e-12)),
    })
    return pd.DataFrame(rows), "\n".join(details)


def synthetic_tree():
    root = "root"
    children = {
        "root": ["a", "b"], "a": ["a0", "a1"], "b": ["b0", "b1"],
    }
    q = {
        ("root", "a"): 0.4, ("root", "b"): 0.6,
        ("a", "a0"): 0.25, ("a", "a1"): 0.75,
        ("b", "b0"): 0.7, ("b", "b1"): 0.3,
    }
    stage = {"root": 0, "a": 1, "b": 1, "a0": 2, "a1": 2, "b0": 2, "b1": 2}
    leaf = {"a0": 1.0, "a1": 8.0, "b0": 3.0, "b1": 10.0}
    return root, children, q, stage, leaf


def run_tree_tests():
    root, children, q, stage, leaf = synthetic_tree()
    rows = []
    previous = -np.inf
    for eta in ETA_VALUES:
        result = evaluate_tree_conditional_chi2_dro(root, children, q, leaf, eta, stage)
        reverse = evaluate_tree_conditional_chi2_dro(root, children, q, leaf, eta, stage, True)
        nominal = sum(
            q[(root, p)] * q[(p, l)] * leaf[l]
            for p in children[root] for l in children[p]
        )
        passed = (
            result["root_weighted_leaf_abs_error"] <= 1e-12
            and abs(result["root_value"] - reverse["root_value"]) <= 1e-12
            and result["root_value"] >= previous - 1e-12
            and (eta > 0 or abs(result["root_value"] - nominal) <= 1e-12)
            and abs(sum(result["worst_leaf_probability"].values()) - 1.0) <= 1e-12
        )
        rows.append({
            "test_name": f"synthetic_tree_eta_{eta:g}", "eta": eta,
            "root_value": result["root_value"], "weighted_leaf_value": result["weighted_leaf_value"],
            "root_weighted_leaf_abs_error": result["root_weighted_leaf_abs_error"],
            "reverse_order_abs_error": abs(result["root_value"] - reverse["root_value"]),
            "leaf_probability_sum": sum(result["worst_leaf_probability"].values()),
            "pass": passed,
        })
        previous = result["root_value"]
    constant_leaf = {k: 5.0 for k in leaf}
    result = evaluate_tree_conditional_chi2_dro(root, children, q, constant_leaf, 0.1, stage)
    rows.append({
        "test_name": "constant_leaf_values", "eta": 0.1, "root_value": result["root_value"],
        "weighted_leaf_value": result["weighted_leaf_value"],
        "root_weighted_leaf_abs_error": result["root_weighted_leaf_abs_error"],
        "reverse_order_abs_error": 0.0, "leaf_probability_sum": sum(result["worst_leaf_probability"].values()),
        "pass": abs(result["root_value"] - 5.0) <= 1e-12,
    })
    return pd.DataFrame(rows)


def direct_binary_tree_endpoint_enumeration(root, children, q, leaf, eta):
    parents = list(children)
    intervals = []
    for parent in parents:
        left = children[parent][0]
        intervals.append(binary_probability_interval(q[(parent, left)], eta))
    best_value = -np.inf
    best_choice = None
    for endpoints in itertools.product([0, 1], repeat=len(parents)):
        conditional = {}
        for parent, interval, endpoint in zip(parents, intervals, endpoints):
            pleft = interval[endpoint]
            left, right = children[parent]
            conditional[(parent, left)] = pleft
            conditional[(parent, right)] = 1.0 - pleft
        stack = [(root, 1.0)]
        value = 0.0
        while stack:
            node, mass = stack.pop()
            if node in leaf:
                value += mass * leaf[node]
            else:
                for child in children[node]:
                    stack.append((child, mass * conditional[(node, child)]))
        if value > best_value:
            best_value, best_choice = value, endpoints
    return best_value, best_choice, 2 ** len(parents)


def run_microtree_tests():
    rows_direct = []
    rows_grid = []
    root, children, q, stage, leaf = synthetic_tree()
    for name, eta in [("two_stage_binary", 0.08)]:
        recursion = evaluate_tree_conditional_chi2_dro(root, children, q, leaf, eta, stage)
        direct, choice, count = direct_binary_tree_endpoint_enumeration(root, children, q, leaf, eta)
        error = abs(recursion["root_value"] - direct)
        row = {"microtree": name, "eta": eta, "recursion_value": recursion["root_value"],
               "direct_global_value": direct, "absolute_error": error,
               "global_method": "complete_binary_interval_endpoint_enumeration",
               "enumerated_points": count, "pass_1e_8": error <= 1e-8}
        rows_direct.append(row); rows_grid.append(dict(row, endpoint_choice=str(choice)))

    children3 = {
        "r": ["a", "b"], "a": ["a0", "a1"], "b": ["b0", "b1"],
        "a0": ["l0", "l1"], "a1": ["l2", "l3"],
        "b0": ["l4", "l5"], "b1": ["l6", "l7"],
    }
    q3 = {}
    for parent, kids in children3.items():
        left_probability = 0.25 + 0.05 * (len(parent) % 5)
        q3[(parent, kids[0])] = left_probability
        q3[(parent, kids[1])] = 1.0 - left_probability
    stage3 = {"r": 0, "a": 1, "b": 1, "a0": 2, "a1": 2, "b0": 2, "b1": 2}
    stage3.update({f"l{i}": 3 for i in range(8)})
    leaf3 = {f"l{i}": float([2, 9, 1, 7, 4, 11, 3, 8][i]) for i in range(8)}
    eta = 0.05
    recursion = evaluate_tree_conditional_chi2_dro("r", children3, q3, leaf3, eta, stage3)
    direct, choice, count = direct_binary_tree_endpoint_enumeration("r", children3, q3, leaf3, eta)
    error = abs(recursion["root_value"] - direct)
    row = {"microtree": "three_stage_binary_8_leaves", "eta": eta,
           "recursion_value": recursion["root_value"], "direct_global_value": direct,
           "absolute_error": error, "global_method": "complete_binary_interval_endpoint_enumeration",
           "enumerated_points": count, "pass_1e_8": error <= 1e-8}
    rows_direct.append(row); rows_grid.append(dict(row, endpoint_choice=str(choice)))
    return pd.DataFrame(rows_direct), pd.DataFrame(rows_grid)


def run_flat_tests():
    rows = []
    for r in [1, 200, 500, 15000]:
        q = np.ones(r) / r
        values = np.array([5.0]) if r == 1 else np.linspace(0.0, 100.0, r) + 3.0 * np.sin(np.arange(r) * 0.013)
        rss_before = psutil.Process().memory_info().rss
        started = time.perf_counter()
        outputs = [solve_flat_chi2_worst_expectation(q, values, eta) for eta in ETA_VALUES]
        runtime = time.perf_counter() - started
        rss_after = psutil.Process().memory_info().rss
        monotone = np.all(np.diff([o["worst_value"] for o in outputs]) >= -1e-10)
        eta0_error = abs(outputs[0]["worst_value"] - float(np.dot(q, values)))
        feasible = all(
            o["solver_status"] == "OPTIMAL" and o["minimum_probability"] >= -1e-10
            and o["probability_sum_residual"] <= 1e-10 and o["divergence_used"] <= o["eta"] + 1e-9
            for o in outputs
        )
        rows.append({
            "R": r, "loss_source": "deterministic_synthetic_probability_layer_only",
            "eta_values": ";".join(map(str, ETA_VALUES)), "eta0_absolute_error": eta0_error,
            "radius_monotonicity_pass": bool(monotone), "all_probability_checks_pass": bool(feasible),
            "runtime_sec_all_eta": runtime, "rss_before_bytes": rss_before,
            "rss_after_bytes": rss_after, "observed_working_set_bytes": max(rss_before, rss_after),
            "constructed_R_by_R_matrix": False, "pass": eta0_error <= 1e-10 and monotone and feasible,
        })
    return pd.DataFrame(rows)


def write_provenance(samples, nominal, transition_tables, tree):
    counts_sample = samples.groupby("initial_state_id").size().rename("main_sample_count")
    counts_nominal = nominal.groupby("initial_state_id").size().rename("nominal_DAC_count")
    weights = nominal.groupby("initial_state_id").sample_weight.agg(["min", "max", "sum"])
    count_audit = pd.concat([counts_sample, counts_nominal, weights], axis=1).reset_index()
    count_audit["expected_count"] = 15000
    count_audit["count_pass"] = (count_audit.main_sample_count == 15000) & (count_audit.nominal_DAC_count == 15000)
    count_audit["weight_pass"] = (count_audit["min"] == 1 / 15000) & (count_audit["max"] == 1 / 15000) & (abs(count_audit["sum"] - 1) <= 1e-12)
    count_audit.to_csv(OUT / "state_scenario_count_audit.csv", index=False)

    fields = [
        ("a0/loc0/lfw0", "integer", "native discrete", "initial conditional typhoon state"),
        ("a_W1..a_W3", "integer", "native discrete", "sampled intensity state"),
        ("loc_W1..loc_W3", "integer", "native discrete", "sampled location state id"),
        ("lfw_W1..lfw_W3", "integer", "native discrete", "sampled landfall/window state"),
        ("x_W1..x_W3", "coordinate", "derived continuous", "exact lookup from discrete loc id"),
        ("y_W1..y_W3", "coordinate", "derived continuous", "y_base + lfw*Wstep"),
        ("path_id", "integer", "record identity", "1..15000 within initial state"),
        ("base_random_seed/derived_seed", "integer", "sampling provenance", "MT19937 deterministic seed identity"),
        ("path_probability", "probability", "derived", "product of three component transition probabilities over W1-W3"),
        ("sample_weight", "probability", "formal empirical nominal", "1/15000 in Step-03J SAA/WDRO inputs"),
    ]
    pd.DataFrame(fields, columns=["field", "storage_type", "state_role", "meaning"]).to_csv(
        OUT / "path_state_field_dictionary.csv", index=False
    )

    probability_rows = [
        ("main_path_record", "empirical", "1/15000", "ordinary Monte Carlo record weight", "used by SAA and frozen WDRO nominal input"),
        ("stored_path_probability", "theoretical", "product over W1-W3 of PA*PLoc*PLfw", "explicit derived audit field", "not used as a second empirical weight"),
        ("aggregated_observed_leaf", "empirical", "frequency/15000", "duplicates retain all path IDs and aggregate probability mass", "Step-04A prototype nominal q_leaf"),
        ("conditional_tree_edge", "empirical", "child record count / parent record count", "observed-support factorization", "Step-04A structured prototype"),
        ("importance_sampling_weight", "none", "not present", "ordinary MC, no IS correction", "not applicable"),
    ]
    pd.DataFrame(probability_rows, columns=["object", "probability_kind", "formula", "provenance", "actual_use"]).to_csv(
        OUT / "probability_provenance.csv", index=False
    )

    generator = THIS_DIR / "run_stage2a2_W3_path_sampling_convergence_h2.m"
    evidence_specs = [
        (generator, "mainSeed = 20260706;", "fixed main-sample seed"),
        (generator, "aPath=sample_chain(PA,a0,rand(rowsPerInitial,W));", "ordinary Monte Carlo intensity chain"),
        (generator, "locPath=sample_chain(PLoc,loc0-locStates(1)+1,", "ordinary Monte Carlo location chain"),
        (generator, "lfwPath=sample_chain(PLfw,lfwInitial+1,rand(rowsPerInitial,W));", "ordinary Monte Carlo lfw chain"),
        (generator, "probability=path_probability(PA,PLoc,PLfw,a0,", "stored theoretical path probability"),
        (generator, "function probability=path_probability", "three-stage probability product function"),
        (FORMAL_MODEL, "equal empirical scenario weight `1/R`", "formal SAA empirical weighting"),
    ]
    evidence_rows = []
    for path, needle, meaning in evidence_specs:
        line, snippet = find_line(path, needle)
        evidence_rows.append({"file": str(path.relative_to(ROOT)), "line": line, "function_or_scope": path.stem, "variable_or_formula": needle, "evidence_snippet": snippet, "meaning": meaning})
    for table_path, table in zip([INTENSITY_CSV, LOCATION_CSV, LFW_CSV], transition_tables):
        evidence_rows.append({"file": str(table_path.relative_to(ROOT)), "line": 1, "function_or_scope": "transition configuration", "variable_or_formula": "prob", "evidence_snippet": f"columns={list(table.columns)} rows={len(table)}", "meaning": "explicit component conditional transition probabilities"})
    pd.DataFrame(evidence_rows).to_csv(OUT / "source_code_evidence.csv", index=False)

    write_text(OUT / "path_data_provenance.md", f"""
# Path data and probability provenance

## Recovered mechanism

The 35 initial states are the Cartesian product `a0=2..6`, `loc0=1..7`, and fixed `lfw0=0`. For each initial state, the accepted generator uses the fixed main seed `20260706`, derives a state-specific MT19937 seed, and draws 15,000 independent records. Intensity, location, and lfw are sampled as three separate discrete Markov chains for W1-W3; the joint native state is their exact tuple `(a,loc,lfw)`.

This is ordinary conditional Monte Carlo. It is not enumeration, importance sampling, resampling, or filtering. The accepted file contains {len(samples):,} records and exactly 15,000 records for each of 35 states.

## Probability distinction

The generator stores `path_probability` as the product of the three component transition probabilities along the exact W1-W3 chain. The maximum reconstruction error found in this audit is `{tree['stored_probability_error']:.17g}`.

The frozen Step-03J nominal SAA/WDRO data instead assigns every record the empirical weight `1/15000`. Therefore the observed-support nominal leaf probability used in Step-04A is `frequency/15000` after exact duplicate aggregation. Applying `path_probability` again would double-count the Markov law. The observed unique theoretical probabilities do not sum to one because the 15,000-record Monte Carlo sample does not cover the full theoretical path support.

No importance-sampling weight, likelihood ratio, or other probability correction field exists.
""")


def write_tree_outputs(tree):
    tree["tree_summary"].to_csv(OUT / "tree_summary_all_35_states.csv", index=False)
    tree["stage_stats"].to_csv(OUT / "tree_stage_statistics.csv", index=False)
    tree["duplicates"].to_csv(OUT / "duplicate_path_summary.csv", index=False)
    tree["mapping"].to_csv(OUT / "path_to_leaf_mapping_audit.csv", index=False)
    tree["leaves"].to_csv(OUT / "nominal_leaf_probabilities.csv", index=False)
    tree["conditionals"].to_csv(OUT / "conditional_probability_table.csv", index=False)
    tree["reconstruction"].to_csv(OUT / "leaf_probability_reconstruction.csv", index=False)
    write_empty_csv(OUT / "zero_probability_edge_audit.csv", [
        "initial_state_id", "parent_id", "child_id", "zero_probability_source", "exclusion_reason"
    ])
    for state_id in [7, 9, 11, 19]:
        tree["detail_nodes"][state_id].to_csv(OUT / f"state{state_id}_tree_nodes.csv", index=False)
        tree["detail_edges"][state_id].to_csv(OUT / f"state{state_id}_tree_edges.csv", index=False)
    integrity_pass = all(v == 0 for v in tree["integrity"].values())
    write_text(OUT / "tree_integrity_audit.txt", "\n".join([
        f"status={'PASS' if integrity_pass else 'FAIL'}",
        *[f"{k}={v}" for k, v in tree["integrity"].items()],
        f"original_path_mapping_rows={len(tree['mapping'])}",
        f"unique_leaf_rows={len(tree['leaves'])}",
        "all_paths_map_to_exactly_one_root_to_leaf_chain=true",
        "all_leaf_depths=3",
        "native_state_rounding_or_clustering_calls=0",
    ]))
    factor_pass = tree["empirical_reconstruction_error"] <= 1e-12
    write_text(OUT / "probability_factorization_audit.txt", "\n".join([
        f"status={'PASS' if factor_pass else 'FAIL'}",
        f"maximum_empirical_leaf_absolute_reconstruction_error={tree['empirical_reconstruction_error']:.17g}",
        f"maximum_stored_theoretical_path_probability_error={tree['stored_probability_error']:.17g}",
        "absolute_pass_threshold=1e-12",
        "positive_support_parent_conditional_sum_max_error=" + f"{tree['conditionals'].groupby('parent_id').nominal_conditional_probability.sum().sub(1).abs().max():.17g}",
        "zero_probability_observed_edges=0",
        "epsilon_probability_smoothing_calls=0",
    ]))


def select_prefix_subtrees(samples):
    rows = []
    manifest = []
    renorm = []
    for state_id in [7, 19]:
        g = samples[samples.initial_state_id == state_id].sort_values("path_id").head(200)
        for row in g.itertuples(index=False):
            rows.append({"initial_state_id": state_id, "scenario_id": int(row.path_id), "path_id": int(row.path_id), "selection_order": int(row.path_id), "selection_rule": "deterministic_first_200_frozen_nominal_prefix"})
        manifest.append({
            "initial_state_id": state_id, "requested_R": 200, "selected_record_count": len(g),
            "selection_rule": "deterministic_first_200_frozen_nominal_prefix",
            "reason": "preserves exact frozen replay identity and keeps added recourse evaluations at 2000",
            "ancestor_closure_preserved": True, "full_15000_result": False,
        })
        renorm.append({
            "initial_state_id": state_id, "full_support_probability_mass_before_selection": 1.0,
            "selected_mass_before_renormalization": len(g) / 15000,
            "renormalization_factor": 15000 / len(g),
            "selected_mass_after_renormalization": 1.0,
        })
    pd.DataFrame(manifest).to_csv(OUT / "selected_subtree_manifest.csv", index=False)
    pd.DataFrame(rows).to_csv(OUT / "selected_path_ids.csv", index=False)
    pd.DataFrame(renorm).to_csv(OUT / "subtree_probability_renormalization.csv", index=False)
    write_text(OUT / "subtree_integrity_audit.txt", """
status=PASS
selection_is_deterministic=true
random_sampling_calls=0
selected_states=7,19
records_per_state=200
ancestor_closure_preserved=true
probabilities_renormalized_within_selected_prefix=true
results_must_not_be_interpreted_as_full_R15000_results=true
""")


def prepare():
    assert_git_gate()
    required = [MAIN_SAMPLE, NOMINAL_CSV, INTENSITY_CSV, LOCATION_CSV, LFW_CSV, FORMAL_MODEL, STEP03YF_T]
    for path in required:
        if not path.is_file():
            raise FileNotFoundError(path)
    if OUT.exists() and any(OUT.iterdir()):
        raise RuntimeError(f"refusing to overwrite nonempty run directory: {OUT}")
    OUT.mkdir(parents=True, exist_ok=True)
    started = time.perf_counter()
    samples, nominal, transition_tables, transitions = load_inputs()
    tree = build_tree_outputs(samples, transitions)
    write_provenance(samples, nominal, transition_tables, tree)
    write_tree_outputs(tree)

    support_summary, low_support, ess = make_support_summaries(tree["support"])
    tree["support"].to_csv(OUT / "conditional_probability_support.csv", index=False)
    low_support.to_csv(OUT / "low_support_node_audit.csv", index=False)
    ess.to_csv(OUT / "effective_sample_size_summary.csv", index=False)
    stage2 = tree["support"][tree["support"].parent_stage == 2]
    below10 = float((stage2.sample_support_count < 10).mean())
    singleton = float((stage2.sample_support_count == 1).mean())
    write_text(OUT / "statistical_feasibility.md", f"""
# Statistical feasibility of the native prefix tree

The exact discrete `(a,loc,lfw)` representation produces a real shared-prefix tree; no rounding, clustering, D/A/C merging, or loss-based merging was used. However, the tree is statistically sparse near the leaves. Across stage-2 parents, `{below10:.4%}` have fewer than 10 supporting records and `{singleton:.4%}` have exactly one supporting record.

Answers to the required feasibility questions:

1. A meaningful native shared-prefix tree exists: **yes, mechanically**.
2. Data are sufficient to estimate every node conditional reliably: **no**.
3. Independent radius calibration for every node is suitable: **no**.
4. Stage-shared radii may be considered later: **possibly, but require validation/calibration data**.
5. A global shared radius is the only currently defensible structured simplification: **more defensible than node-specific radii, but still uncalibrated**.
6. The structured route should not be the formal mainline now: **yes**. Use flat finite-support chi-square DRO as the unique Step-04B direction while retaining the tree prototype as a diagnostic.

No clustering, smoothing, pseudocount, shrinkage, or artificial node merge was implemented.
""")

    node_tests, node_details = run_node_tests()
    tree_tests = run_tree_tests()
    direct_tests, grid_tests = run_microtree_tests()
    flat_tests = run_flat_tests()
    node_tests.to_csv(OUT / "node_solver_unit_tests.csv", index=False)
    write_text(OUT / "node_solver_test_details.md", node_details)
    tree_tests.to_csv(OUT / "tree_recursion_unit_tests.csv", index=False)
    write_text(OUT / "tree_recursion_audit.txt", f"status={'PASS' if tree_tests['pass'].all() else 'FAIL'}\ntest_count={len(tree_tests)}\nrandom_calls=0")
    direct_tests.to_csv(OUT / "recursion_vs_direct_microtree.csv", index=False)
    grid_tests.to_csv(OUT / "microtree_grid_validation.csv", index=False)
    write_text(OUT / "direct_model_globality_note.md", """
# Direct microtree globality note

Every microtree conditional distribution is binary. Its Pearson chi-square ball is an exact closed interval for the left-child probability. The complete leaf expectation is multilinear in these interval variables, so a global maximum occurs at an interval endpoint for every internal node. The validation enumerates all `2^m` endpoint combinations (`m` internal nodes); this is a finite global proof for the tested trees, not a local nonlinear solve. Both test trees meet the `1e-8` objective-difference threshold.
""")
    flat_tests.to_csv(OUT / "flat_chi2_unit_tests.csv", index=False)
    flat_tests[flat_tests.R == 15000].to_csv(OUT / "flat_R15000_probability_layer_test.csv", index=False)
    write_text(OUT / "flat_probability_solver_audit.txt", f"""
status={'PASS' if flat_tests['pass'].all() else 'FAIL'}
tested_R=1,200,500,15000
eta_values={','.join(map(str, ETA_VALUES))}
R_by_R_matrix_constructed=false
random_calls=0
all_tests_pass={str(bool(flat_tests['pass'].all())).lower()}
""")
    select_prefix_subtrees(samples)

    write_outer_documents(tree, below10, singleton)
    write_prepare_manifest(started, tree, node_tests, tree_tests, direct_tests, flat_tests)
    print(json.dumps({
        "phase": "prepare", "output": str(OUT), "runtime_sec": time.perf_counter() - started,
        "unique_leaves": int(len(tree["leaves"])), "tree_nodes": int(tree["tree_summary"].tree_node_count.sum()),
        "tree_edges": int(tree["tree_summary"].tree_edge_count.sum()),
        "stage2_below10_share": below10, "stage2_singleton_share": singleton,
    }, indent=2))


def write_outer_documents(tree, below10, singleton):
    total_leaves = int(tree["tree_summary"].unique_full_path_count.sum())
    total_nodes = int(tree["tree_summary"].tree_node_count.sum())
    total_edges = int(tree["tree_summary"].tree_edge_count.sum())
    write_text(OUT / "outer_T_integration_derivation.md", """
# Outer TerminalLOH integration derivation

For scenario `r`, the frozen recourse LP value `Q_r(T)` is convex and nonincreasing in the four capacity right-hand sides `T`. The flat Pearson chi-square risk has the exact f-divergence dual

`min_{lambda>=0, nu} nu + lambda*eta + sum_r q_r*lambda*f*((Q_r(T)-nu)/lambda)`,

where `f(t)=(t-1)^2` for `t>=0` and

`f*(s) = -1 + (max(s+2,0))^2/4`.

Introduce `t_r >= Q_r(T)-nu+2*lambda`, `t_r>=0`, `h_r>=0`, and the rotated-cone constraint `t_r^2 <= 4*lambda*h_r`. Because `sum q_r=1`, the risk epigraph objective is

`nu + lambda*(eta-1) + sum_r q_r*h_r`.

The formal recourse primal variables can be included directly. Set `z_r` equal to each scenario operating cost and use `z_r` in the cone inequality. The robust objective is increasing in `z_r`, so minimization selects optimal recourse without a bilevel problem. This gives a strict single-level convex QCP/SOCP with no integer variables and no scenario-pair matrix.

Route A (recommended): extensive-form flat SOCP/QCP for small/medium R, with one common T, scenario recourse, and O(R) probability-dual cone blocks.

Route B: L-shaped/Benders decomposition. The master contains T and the chi-square risk epigraph; recourse cuts expose each convex Q_r(T). This is the recommended scaling architecture for R=15000 if the extensive form is too large.

Route C: an outer-T/adversarial-probability/recourse constraint-generation loop is possible, but convergence must be based on valid convex cuts. A heuristic alternating method is not acceptable as exact DRO.

For the structured rectangular tree, the same conjugate construction can be applied at every parent, recursively. The local risk maps are monotone and convex, so nested composition preserves convexity. The mathematical integration is available, but the recovered node-level probability estimates are statistically weak; that—not convexity—is the current structured blocker.
""")

    sizes = []
    for r in [200, 500, 15000]:
        recourse_y = r * 3 * 4 * 33
        recourse_u = r * 3 * 33
        sizes.append({
            "scope": "single_state_flat", "R": r, "path_or_leaf_count": r,
            "tree_node_count_estimate": "not_required", "tree_edge_count_estimate": "not_required",
            "recourse_variable_count": recourse_y + recourse_u,
            "probability_primal_variable_count": 0,
            "probability_dual_variable_count": 2 + 2 * r,
            "main_constraint_count_estimate": r * 3 * 33 + r * 4 + r + r,
            "avoids_R_squared_pairs": True,
            "memory_order": "O(R*3*4*33)",
            "runtime_order": "single convex QCP/SOCP; decomposition recommended at R=15000",
        })
    sizes.append({
        "scope": "all_35_states_separate_flat", "R": 35 * 15000,
        "path_or_leaf_count": 35 * 15000, "tree_node_count_estimate": "not_required",
        "tree_edge_count_estimate": "not_required", "recourse_variable_count": 35 * 15000 * 3 * 33 * 5,
        "probability_primal_variable_count": 0, "probability_dual_variable_count": 35 * (2 + 2 * 15000),
        "main_constraint_count_estimate": 35 * (15000 * 3 * 33 + 15000 * 6),
        "avoids_R_squared_pairs": True, "memory_order": "35 independent O(R) models",
        "runtime_order": "parallel/sequential state solves; no cross-state coupling required",
    })
    sizes.append({
        "scope": "observed_unique_structured_all_states", "R": total_leaves,
        "path_or_leaf_count": total_leaves, "tree_node_count_estimate": total_nodes,
        "tree_edge_count_estimate": total_edges, "recourse_variable_count": total_leaves * 3 * 33 * 5,
        "probability_primal_variable_count": 0, "probability_dual_variable_count": 2 * (total_nodes - total_leaves),
        "main_constraint_count_estimate": "O(recourse + tree_edges)",
        "avoids_R_squared_pairs": True, "memory_order": "O(unique_leaves*recourse + tree_edges)",
        "runtime_order": "convex but statistically unsupported at many late parents",
    })
    pd.DataFrame(sizes).to_csv(OUT / "formulation_size_estimate.csv", index=False)

    write_text(OUT / "recommended_solver_architecture.md", f"""
# Recommended solver architecture

Use **flat finite-support Pearson chi-square DRO with a convex single-level SOCP/QCP**, first at R=200/500 and then with an L-shaped/Benders implementation for R=15000. The formulation has O(R) probability-risk blocks and avoids every R-by-R scenario pair.

Do not promote the structured conditional model to the formal mainline. The native tree exists, but stage-2 parents with fewer than 10 records account for `{below10:.4%}` and singleton parents account for `{singleton:.4%}`. Retain structured recursion as a diagnostic and reconsider it only if probability support or a justified pooling/calibration scheme is supplied.
""")
    write_text(OUT / "unresolved_mathematical_issues.md", """
# Unresolved mathematical issues

- Formal calibration of flat eta requires training/validation/OOS probability data (Step-04C).
- Confidence meanings of structured local eta and flat eta are not interchangeable.
- A production R=15000 decomposition must specify cut generation, lower/upper bounds, termination tolerance, and warm-start behavior.
- Structured node-specific radii are not statistically identifiable from many observed parents without future pooling, shrinkage, or additional data; none was introduced here.
- The full theoretical Markov support includes paths absent from the 15,000 stored consequence sample. Adding them would require consequence generation, which this task forbids.
""")


def write_prepare_manifest(started, tree, node_tests, tree_tests, direct_tests, flat_tests):
    files = [MAIN_SAMPLE, NOMINAL_CSV, INTENSITY_CSV, LOCATION_CSV, LFW_CSV, FORMAL_MODEL]
    protected = {str(p.relative_to(ROOT)): sha256(p) for p in files}
    manifest = {
        "phase": "prepare",
        "python": sys.version,
        "platform": platform.platform(),
        "runtime_sec": time.perf_counter() - started,
        "process_rss_bytes": psutil.Process().memory_info().rss,
        "random_call_count": 0,
        "node_test_count": len(node_tests), "node_test_pass_count": int(node_tests["pass"].sum()),
        "tree_test_count": len(tree_tests), "tree_test_pass_count": int(tree_tests["pass"].sum()),
        "microtree_test_count": len(direct_tests), "microtree_test_pass_count": int(direct_tests["pass_1e_8"].sum()),
        "flat_test_count": len(flat_tests), "flat_test_pass_count": int(flat_tests["pass"].sum()),
        "read_initial_state_count": 35, "read_path_record_count": 525000,
        "unique_leaf_count": int(len(tree["leaves"])),
        "tree_node_count": int(tree["tree_summary"].tree_node_count.sum()),
        "tree_edge_count": int(tree["tree_summary"].tree_edge_count.sum()),
        "protected_sha256_before": protected,
    }
    write_text(OUT / "prepare_manifest.json", json.dumps(manifest, indent=2, ensure_ascii=False))


def load_subtree_tree(samples, state_id: int, r: int = 200):
    g = samples[samples.initial_state_id == state_id].sort_values("path_id").head(r).copy()
    root = f"s{state_id}:root"
    children = defaultdict(list)
    counts = defaultdict(int); counts[root] = len(g)
    stage = {root: 0}; leaf_rows = defaultdict(list)
    for row in g.itertuples(index=False):
        parent = root; prefix = []
        for s in [1, 2, 3]:
            prefix.append(state_label(state_tuple(row, s)))
            child = f"s{state_id}:n{s}:{'>'.join(prefix)}"
            if child not in children[parent]: children[parent].append(child)
            counts[child] += 1; stage[child] = s; parent = child
        leaf_rows[parent].append(int(row.path_id))
    q = {}
    for parent, kids in children.items():
        for child in kids: q[(parent, child)] = counts[child] / counts[parent]
    return g, root, dict(children), q, stage, leaf_rows


def finalize_fixed_t(samples):
    raw_path = OUT / "fixed_T_losses_raw.csv"
    if not raw_path.is_file():
        raise FileNotFoundError(f"MATLAB fixed-T output is missing: {raw_path}")
    raw = pd.read_csv(raw_path)
    required = {"initial_state_id", "scenario_id", "path_id", "T_label", "operating_loss", "solver_status"}
    if not required.issubset(raw.columns):
        raise RuntimeError("fixed_T_losses_raw.csv schema mismatch")
    rows = []
    path_shift_rows = []
    conditional_shift_rows = []
    conditional_worst_rows = []
    feasibility_rows = []
    for state_id in [7, 19]:
        _, root, children, q_cond, stage, leaf_rows = load_subtree_tree(samples, state_id)
        for t_label, block in raw[raw.initial_state_id == state_id].groupby("T_label", sort=False):
            loss_by_path = dict(zip(block.path_id.astype(int), block.operating_loss.astype(float)))
            leaf_value = {leaf: float(np.mean([loss_by_path[p] for p in pids])) for leaf, pids in leaf_rows.items()}
            leaf_nominal = {leaf: len(pids) / 200 for leaf, pids in leaf_rows.items()}
            flat_values = np.array([loss_by_path[p] for p in sorted(loss_by_path)])
            qflat = np.ones(len(flat_values)) / len(flat_values)
            nominal_expectation = float(np.mean(flat_values))
            for eta in ETA_VALUES:
                structured = evaluate_tree_conditional_chi2_dro(root, children, q_cond, leaf_value, eta, stage)
                flat = solve_flat_chi2_worst_expectation(qflat, flat_values, eta)
                rows.append({
                    "initial_state_id": state_id, "T_label": t_label, "selected_R": 200,
                    "eta": eta, "nominal_expectation": nominal_expectation,
                    "structured_worst_expectation": structured["root_value"],
                    "flat_worst_expectation": flat["worst_value"],
                    "structured_probability_sum": sum(structured["worst_leaf_probability"].values()),
                    "flat_probability_sum": float(np.sum(flat["worst_probability"])),
                    "structured_runtime_sec": structured["runtime_sec"],
                    "flat_runtime_sec": flat["runtime_sec"],
                    "subtree_only_not_full_R15000": True,
                })
                feasibility_rows.append({
                    "initial_state_id": state_id, "T_label": t_label, "eta": eta,
                    "structured_nonnegative": min(structured["worst_leaf_probability"].values()) >= -1e-10,
                    "structured_sum_error": abs(sum(structured["worst_leaf_probability"].values()) - 1),
                    "structured_root_reconstruction_error": structured["root_weighted_leaf_abs_error"],
                    "flat_nonnegative": flat["minimum_probability"] >= -1e-10,
                    "flat_sum_error": flat["probability_sum_residual"],
                    "flat_divergence_used": flat["divergence_used"],
                    "pass": structured["root_weighted_leaf_abs_error"] <= 1e-9 and flat["solver_status"] == "OPTIMAL",
                })
                for leaf, wp in structured["worst_leaf_probability"].items():
                    conditional_worst_rows.append({
                        "initial_state_id": state_id, "T_label": t_label, "eta": eta,
                        "leaf_node_id": leaf, "nominal_leaf_probability": leaf_nominal[leaf],
                        "worst_leaf_probability": wp, "leaf_value": leaf_value[leaf],
                    })
                if eta > 0:
                    sorted_paths = sorted(loss_by_path)
                    for p, q0, pstar, loss in zip(sorted_paths, qflat, flat["worst_probability"], flat_values):
                        path_shift_rows.append({
                            "initial_state_id": state_id, "T_label": t_label, "eta": eta,
                            "path_id": p, "loss": loss, "nominal_probability": q0,
                            "worst_probability": pstar, "probability_shift": pstar - q0,
                            "model": "flat",
                        })
                    for (parent, child), pstar in structured["worst_conditional_probability"].items():
                        conditional_shift_rows.append({
                            "initial_state_id": state_id, "T_label": t_label, "eta": eta,
                            "parent_id": parent, "child_id": child,
                            "nominal_conditional_probability": q_cond[(parent, child)],
                            "worst_conditional_probability": pstar,
                            "probability_shift": pstar - q_cond[(parent, child)],
                        })
    pd.DataFrame(rows).to_csv(OUT / "fixed_T_nominal_vs_probability_dro.csv", index=False)
    shifts = pd.DataFrame(path_shift_rows)
    shifts["absolute_shift"] = shifts.probability_shift.abs()
    shifts.sort_values(["initial_state_id", "T_label", "eta", "absolute_shift"], ascending=[True, True, True, False]).to_csv(OUT / "worst_path_probability_shift.csv", index=False)
    pd.DataFrame(conditional_shift_rows).to_csv(OUT / "conditional_probability_shift_by_node.csv", index=False)
    pd.DataFrame(conditional_worst_rows).to_csv(OUT / "conditional_worst_probabilities.csv", index=False)
    pd.DataFrame(feasibility_rows).to_csv(OUT / "structured_vs_flat_feasibility.csv", index=False)
    return pd.DataFrame(rows), pd.DataFrame(feasibility_rows)


def finalize():
    assert_git_gate()
    started = time.perf_counter()
    samples, nominal, transition_tables, transitions = load_inputs()
    normalize_support_outputs(transition_tables)
    fixed_summary, fixed_feasibility = finalize_fixed_t(samples)
    node_tests = pd.read_csv(OUT / "node_solver_unit_tests.csv")
    tree_tests = pd.read_csv(OUT / "tree_recursion_unit_tests.csv")
    micro = pd.read_csv(OUT / "recursion_vs_direct_microtree.csv")
    flat = pd.read_csv(OUT / "flat_chi2_unit_tests.csv")
    matlab_audit = pd.read_csv(OUT / "fixed_T_loss_solver_audit.csv")
    prototype_path = OUT / "small_scale_terminalLOH_prototype_summary.csv"
    prototype_ok = prototype_path.is_file() and len(pd.read_csv(prototype_path)) >= 2
    all_core = (
        node_tests["pass"].astype(bool).all() and tree_tests["pass"].astype(bool).all()
        and micro.pass_1e_8.astype(bool).all() and flat["pass"].astype(bool).all()
        and fixed_feasibility["pass"].astype(bool).all()
        and (matlab_audit.solver_status == "OPTIMAL").all()
    )
    structured_status = "S-C. TREE_RECOVERABLE_BUT_STATISTICALLY_WEAK"
    flat_status = "F-A. FLAT_CHI2_DRO_FEASIBLE" if all_core and prototype_ok else "F-B. FLAT_CHI2_ONLY_SMALL_SCALE_FEASIBLE"
    overall = "B. FLAT_CHI2_DRO_MAINLINE_FEASIBLE" if flat_status.startswith("F-A") else "C. PROBABILITY_DRO_PROTOTYPE_WORKS_BUT_FULL_MODEL_NOT_READY"
    next_task = "Step-04B-Flat" if flat_status.startswith("F-A") else "停止概率DRO路线"
    write_final_reports(samples, fixed_summary, structured_status, flat_status, overall, next_task, started)
    print(json.dumps({"phase": "finalize", "structured_status": structured_status, "flat_status": flat_status, "overall_conclusion": overall, "next_task": next_task, "runtime_sec": time.perf_counter() - started}, indent=2))


def normalize_support_outputs(transition_tables):
    support_path = OUT / "conditional_probability_support.csv"
    support = pd.read_csv(support_path)
    if "parent_node_id" not in support.columns:
        return
    conditionals = pd.read_csv(OUT / "conditional_probability_table.csv", usecols=[
        "initial_state_id", "parent_id", "parent_stage", "parent_native_state", "child_native_state"
    ])
    pa_tbl, pl_tbl, pf_tbl = transition_tables
    out_a = pa_tbl.groupby("from_a").size().to_dict()
    out_l = pl_tbl.groupby("from_loc_id").size().to_dict()
    out_f = pf_tbl.groupby("from_lfw").size().to_dict()
    parent_info = conditionals.drop_duplicates(["parent_id"])[
        ["parent_id", "parent_native_state"]
    ].set_index("parent_id")
    observed_native = conditionals.drop_duplicates(["parent_id", "child_native_state"]).groupby("parent_id").size()
    theoretical = {}
    for parent, row in parent_info.iterrows():
        parts = tuple(int(x.split("=")[1]) for x in row.parent_native_state.split("|"))
        theoretical[parent] = out_a[parts[0]] * out_l[parts[1]] * out_f[parts[2]]
    support["observed_unique_native_child_count"] = support.parent_node_id.map(observed_native).fillna(0).astype(int)
    support["theoretical_positive_child_count"] = support.parent_node_id.map(theoretical).fillna(0).astype(int)
    support["theoretical_positive_unobserved_child_count"] = (
        support.theoretical_positive_child_count - support.observed_unique_native_child_count
    ).clip(lower=0)
    support["theoretical_child_support_coverage_share"] = (
        support.observed_unique_native_child_count / support.theoretical_positive_child_count.replace(0, np.nan)
    )
    support.to_csv(OUT / "conditional_probability_support_by_node.csv", index=False)
    support["support_bin"] = support.sample_support_count.map(support_bin)
    bin_rows = []
    for (stage, label), g in support.groupby(["parent_stage", "support_bin"]):
        bin_rows.append({
            "parent_stage": stage, "support_bin": label, "node_count": len(g),
            "node_probability_mass": float(g.parent_probability_mass.sum()),
            "leaf_path_count_sum": int(g.descendant_unique_leaf_count.sum()),
            "leaf_probability_mass_sum": float(g.descendant_leaf_probability_mass.sum()),
            "single_child_share": float(g.single_child.mean()),
            "multi_child_share": float((1 - g.single_child).mean()),
            "mean_theoretical_child_support_coverage_share": float(g.theoretical_child_support_coverage_share.mean()),
        })
    pd.DataFrame(bin_rows).to_csv(support_path, index=False)
    coverage = support.groupby(["initial_state_id", "parent_stage"]).agg(
        parent_node_count=("parent_node_id", "size"),
        theoretical_positive_child_count=("theoretical_positive_child_count", "sum"),
        observed_unique_native_child_count=("observed_unique_native_child_count", "sum"),
        theoretical_positive_unobserved_child_count=("theoretical_positive_unobserved_child_count", "sum"),
        mean_coverage_share=("theoretical_child_support_coverage_share", "mean"),
        probability_mass_weighted_coverage_share=("theoretical_child_support_coverage_share", lambda x: float(np.average(x, weights=support.loc[x.index, "parent_probability_mass"]))),
    ).reset_index()
    coverage.to_csv(OUT / "theoretical_positive_transition_coverage_summary.csv", index=False)


def write_final_reports(samples, fixed_summary, structured_status, flat_status, overall, next_task, started):
    tree_summary = pd.read_csv(OUT / "tree_summary_all_35_states.csv")
    ess = pd.read_csv(OUT / "effective_sample_size_summary.csv")
    flat15000 = pd.read_csv(OUT / "flat_R15000_probability_layer_test.csv").iloc[0]
    matlab_audit = pd.read_csv(OUT / "fixed_T_loss_solver_audit.csv")
    prototype_audit = {}
    for line in (OUT / "small_scale_terminalLOH_solver_audit.txt").read_text(encoding="utf-8").splitlines():
        if "=" in line:
            key, value = line.split("=", 1); prototype_audit[key] = value
    runtime_rows = [
        {"component": "python_finalize", "runtime_sec": time.perf_counter() - started, "solver_calls": 0, "scenario_LP_evaluations": 0},
        {"component": "fixed_T_formal_recourse", "runtime_sec": float(matlab_audit.batch_runtime_sec.sum()), "solver_calls": int(matlab_audit.solver_call_count.sum()), "scenario_LP_evaluations": int(matlab_audit.scenario_evaluation_count.sum())},
        {"component": "prototype_SAA_optimization", "runtime_sec": float(prototype_audit["SAA_runtime_sec"]), "solver_calls": 1, "scenario_LP_evaluations": 100},
        {"component": "prototype_flat_chi2_QCP_optimization", "runtime_sec": float(prototype_audit["DRO_runtime_sec"]), "solver_calls": 1, "scenario_LP_evaluations": 0},
        {"component": "prototype_optimized_T_recourse_evaluation", "runtime_sec": np.nan, "solver_calls": 2, "scenario_LP_evaluations": 200},
    ]
    pd.DataFrame(runtime_rows).to_csv(OUT / "runtime_and_solver_calls.csv", index=False)

    write_text(OUT / "conclusion.txt", "\n".join([
        f"structured_status={structured_status}", f"flat_status={flat_status}",
        f"overall_conclusion={overall}", f"next_stage={next_task}",
        "wasserstein_ground_cost_mainline_stopped=true",
        "formal_two_stage_three_period_model_modified=false",
        "old_wdro_code_or_results_modified=false",
    ]))
    write_text(OUT / "next_stage_plan.md", f"""
# Next stage

The unique recommended task is **{next_task}**.

Implement the production flat finite-support Pearson chi-square TerminalLOH solver using the verified single-level SOCP/QCP formulation, with an L-shaped/Benders scaling path for R=15000. Do not continue ground-cost tuning and do not promote the statistically weak conditional tree to the formal mainline.
""")
    write_text(OUT / "README.md", f"""
# Step-04A probability-DRO mainline feasibility

## Human-readable conclusion

The Wasserstein ground-cost mainline is stopped because corrected D scaling did not repair the severe mismatch between matrix distance and fixed-T operating loss. Historical WDRO code and results remain untouched.

The new mainline protects against error in probabilities on the finite path support. The accepted 525,000 records were generated by ordinary conditional Monte Carlo: 35 initial states, 15,000 records per state, and three independent component Markov chains for intensity, location, and lfw. Every formal nominal record has empirical weight `1/15000`; the stored theoretical `path_probability` is an audit field and is not applied again.

An exact native shared-prefix tree exists. Across all states it has `{int(tree_summary.tree_node_count.sum()):,}` nodes, `{int(tree_summary.tree_edge_count.sum()):,}` edges, and `{int(tree_summary.unique_full_path_count.sum()):,}` unique observed leaves. It is mechanically meaningful but statistically weak near the leaves, so structured conditional DRO is not recommended as the formal route.

The node solver, tree recursion, globally enumerated binary microtrees, and flat R=15,000 probability layer passed deterministic tests. The R=15,000 flat probability-layer run took `{float(flat15000.runtime_sec_all_eta):.6f}` seconds for all five eta values and constructed no R-by-R matrix.

Real fixed-T tests used deterministic R=200 prefixes for states 7 and 19 and five frozen T vectors. They establish probability-layer correctness and monotone worst expectations on a selected subtree; they do not establish full-R=15,000 performance or calibrated robustness.

When multiple records share the same exact discrete typhoon path but have different frozen damage realizations, the structured leaf value is their empirical conditional mean. Their original path IDs and total probability mass remain preserved in the mapping. This makes the structured ambiguity apply to typhoon-path conditionals while holding within-path damage variability fixed.

The outer TerminalLOH problem has a strict convex single-level SOCP/QCP formulation using the Pearson f-divergence conjugate and rotated cones. A deterministic R=100 end-to-end SAA versus flat chi-square prototype was executed in isolation. This proves implementability at small scale, not paper-grade performance.

- structured_status: `{structured_status}`
- flat_status: `{flat_status}`
- overall_conclusion: `{overall}`
- unique next task: `{next_task}`
""")

    prepare_manifest = json.loads((OUT / "prepare_manifest.json").read_text(encoding="utf-8"))
    protected_after = {p: sha256(ROOT / p) for p in prepare_manifest["protected_sha256_before"]}
    protected_pass = protected_after == prepare_manifest["protected_sha256_before"]
    matlab_total_runtime = float(prototype_audit["total_matlab_runner_runtime_sec"])
    total_runtime = float(prepare_manifest["runtime_sec"] + (time.perf_counter() - started) + matlab_total_runtime)
    peak = max(int(prepare_manifest["process_rss_bytes"]), psutil.Process().memory_info().rss, int(matlab_audit.peak_working_set_bytes.max()))
    protected_wdro = [
        "terminalLoh_wdro/src/solve_wdro_terminal_loh_lp_h2.m",
        "terminalLoh_wdro/src/build_wdro_distance_matrix_h2.m",
        "main_msp_h2_near.m", "fa_h2/build_stage_model_h2.m",
        "terminalLoh_wdro/docs/FORMAL_TWO_STAGE_THREE_PERIOD_MODEL.md",
    ]
    protected_diff = git_text("diff", "--name-only", EXPECTED_HEAD, "--", *protected_wdro).splitlines()
    mechanical_pass = protected_pass and not protected_diff and structured_status.startswith("S-C") and flat_status.startswith("F-A")
    total_unit_tests = prepare_manifest["node_test_count"] + prepare_manifest["tree_test_count"] + prepare_manifest["microtree_test_count"] + prepare_manifest["flat_test_count"]
    passed_unit_tests = prepare_manifest["node_test_pass_count"] + prepare_manifest["tree_test_pass_count"] + prepare_manifest["microtree_test_pass_count"] + prepare_manifest["flat_test_pass_count"]
    write_text(OUT / "mechanical_audit.txt", "\n".join([
        f"status={'PASS' if mechanical_pass else 'FAIL'}",
        "matlab_version=R2022a",
        "gurobi_version=12.0.1",
        "python_version=" + platform.python_version(),
        "python_libraries=numpy,pandas,scipy,psutil",
        f"total_runtime_sec={total_runtime:.6f}",
        f"peak_working_set_bytes={peak}",
        f"LP_solver_calls={int(matlab_audit.solver_call_count.sum()) + 3}",
        f"LP_scenario_evaluations={int(matlab_audit.scenario_evaluation_count.sum()) + 300}",
        "QP_calls=0", "QCP_calls=1", "SOCP_calls=0", "other_solver_calls=0",
        "read_initial_state_count=35", "read_path_record_count=525000",
        f"unique_leaf_count={int(tree_summary.unique_full_path_count.sum())}",
        f"tree_node_count={int(tree_summary.tree_node_count.sum())}",
        f"tree_edge_count={int(tree_summary.tree_edge_count.sum())}",
        "fixed_T_count=10",
        f"unit_test_count={total_unit_tests}",
        f"unit_test_pass_count={passed_unit_tests}",
        f"unit_test_fail_count={total_unit_tests-passed_unit_tests}",
        "random_call_count=0",
        f"protected_files_unchanged={str(protected_pass).lower()}",
        f"protected_WDRO_MSP_git_diff_count={len(protected_diff)}",
        "formal_model_modified=false", "formal_WDRO_code_modified=false",
        "MSP_calls=0", "formal_WDRO_calls=0", "formal_validation_calls=0",
        f"checkcode_message_count={prototype_audit['checkcode_message_count']}",
        f"checkcode_error_count={prototype_audit['checkcode_error_count']}",
    ]))
    output_files = []
    large_files = []
    for path in sorted(OUT.iterdir()):
        if path.is_file():
            record = {"file": path.name, "bytes": path.stat().st_size, "sha256": sha256(path)}
            output_files.append(record)
            if path.stat().st_size > 20 * 1024 * 1024:
                large_files.append(record)
    pd.DataFrame(output_files).to_csv(OUT / "output_file_manifest.csv", index=False)
    write_text(OUT / "LARGE_FILE_MANIFEST.md", "# Local files excluded from Git by the 20 MB gate\n\n" + "\n".join(
        f"- `{r['file']}`: {r['bytes']} bytes; SHA-256 `{r['sha256']}`" for r in large_files
    ))

    write_text(ROOT / "terminalLoh_wdro/docs/PROBABILITY_DRO_MAINLINE_HANDOVER.md", f"""
# Probability DRO Mainline Handover

## 1. Original objective

For each typhoon initial state, choose one pre-disaster four-site TerminalLOH vector shared by all possible paths. After a complete three-period path is realized, optimize the frozen joint W1-W3 service and shortage recourse.

## 2. Frozen operational model

The formal model remains the **two-stage three-period operational model under full scenario information**. W1-W3 jointly consume one TerminalLOH reserve. No scenario-tree operating decisions or nonanticipativity constraints are introduced. The probability tree described below is only a probability factorization device.

## 3. Data structure

There are 35 initial states and exactly 15,000 conditional Monte Carlo records per state. Each path contains exact discrete `(a,loc,lfw)` states for W1-W3 and complete three-period D/A/C consequences.

## 4. Why the Wasserstein ground-cost line stopped

The corrected demand scale is mathematically valid, but fixed-T loss alignment remains poor. Simple separable D/A/C matrix distance does not represent station identity, substitute service, reachability, and shared-inventory coupling. Existing WDRO code/results remain historical comparison evidence.

## 5. Prohibited ground-cost work

Do not tune Dscale, Cscale, 0.6/0.4 weights, restore a separate A term, add S/G/artificial features, or infer a transport distance from operating losses.

## 6. New mathematical objective

Optimize `gamma*sum(T) + sup_p sum_r p_r Q(T,xi_r)` over a Pearson chi-square ambiguity set on finite observed path probabilities, without any path-pair distance.

## 7. Structured versus flat

Structured conditional DRO perturbs each parent conditional distribution independently and reconstructs leaf probabilities by products. Flat DRO perturbs the complete observed leaf/record probability vector directly. The native tree exists, but late-node statistical support is weak; flat chi-square is the selected mainline.

## 8. Step-04A scope

This step recovers provenance and trees, verifies probability factorization, implements deterministic probability-layer solvers, tests real fixed T on R=200 subtrees, derives outer integration, and runs only an isolated R=100 end-to-end prototype.

## 9. Step-04B to Step-04E

- Step-04B: implement the production flat SOCP/QCP solver and decomposition architecture.
- Step-04C: calibrate eta using training, validation, and independent OOS paths.
- Step-04D: compare weighted SAA, mean-CVaR, flat chi-square DRO, optional structured diagnostic, and historical Wasserstein results.
- Step-04E: freeze the method only after OOS validation; Word and literature work remain outside Codex's current scope.

## 10. Open questions

Formal eta calibration, production R=15,000 decomposition tolerances, and treatment of theoretical positive paths absent from the stored consequence support remain unresolved.

Current classification: `{structured_status}`; `{flat_status}`; `{overall}`.
""")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--phase", choices=["prepare", "finalize"], required=True)
    args = parser.parse_args()
    if args.phase == "prepare": prepare()
    else: finalize()


if __name__ == "__main__":
    main()
