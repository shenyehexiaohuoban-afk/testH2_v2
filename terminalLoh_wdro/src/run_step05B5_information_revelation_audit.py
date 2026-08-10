"""Prepare the read-only Step-05B-5 information-revelation audit."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path

import numpy as np
import pandas as pd


TOL = 1.0e-7
FOCUS_STATES = [12, 13, 14, 19]
CAPACITY_STATES = [16, 17, 18, 19]


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def decode_state(k: int) -> tuple[int, int, int]:
    zero = int(k) - 1
    return zero // 56 + 1, (zero % 56) // 8 + 1, zero % 8 + 1


def state_id_from_k(k: int) -> int:
    a, loc, lf = decode_state(k)
    if a <= 1 or lf != 7:
        return 0
    return (a - 2) * 7 + loc


def ranking_signature(values: np.ndarray) -> str:
    if float(np.sum(values)) <= TOL:
        return "zero_target"
    order = np.argsort(-values, kind="stable") + 1
    return ">".join(str(int(value)) for value in order)


def top_site(values: np.ndarray) -> int:
    if float(np.sum(values)) <= TOL:
        return 0
    return int(np.argmax(values) + 1)


def build_terminal_outcomes(oos: np.ndarray) -> pd.DataFrame:
    rows = []
    for row_id, path in enumerate(oos, start=1):
        terminal_state = 0
        terminal_stage = 0
        terminal_k = 0
        for stage, k in enumerate(path, start=1):
            state_id = state_id_from_k(int(k))
            if state_id > 0:
                terminal_state = state_id
                terminal_stage = stage
                terminal_k = int(k)
                break
        rows.append((row_id, terminal_state, terminal_stage, terminal_k))
    return pd.DataFrame(
        rows,
        columns=["path_id", "terminal_state_id", "terminal_stage", "terminal_state_k"],
    )


def build_target_matrix(table: pd.DataFrame) -> np.ndarray:
    matrix = np.zeros((36, 4), dtype=float)
    indexed = table.set_index("state_id")
    expected = list(range(1, 36))
    if list(indexed.index) != expected:
        raise RuntimeError("DRO TerminalLOH table must contain ordered states 1..35.")
    matrix[1:, :] = indexed[["T1_kg", "T2_kg", "T3_kg", "T4_kg"]].to_numpy(float)
    if not np.allclose(
        matrix[1:, :].sum(axis=1), indexed["TerminalLOH_total_kg"].to_numpy(float), atol=1e-8
    ):
        raise RuntimeError("TerminalLOH station totals do not reproduce table totals.")
    return matrix


def build_active_observations(
    oos: np.ndarray, outcomes: pd.DataFrame, targets: np.ndarray
) -> pd.DataFrame:
    outcome_by_path = outcomes.set_index("path_id")
    rows = []
    for path_id, path in enumerate(oos, start=1):
        outcome = int(outcome_by_path.loc[path_id, "terminal_state_id"])
        for decision_stage, k in enumerate(path, start=1):
            a, loc, lf = decode_state(int(k))
            if a <= 1 or lf >= 7:
                continue
            vector = targets[outcome]
            rows.append(
                {
                    "path_id": path_id,
                    "decision_stage": decision_stage,
                    "history_node_id": f"t{decision_stage}_k{int(k)}",
                    "current_k": int(k),
                    "current_a": a,
                    "current_loc": loc,
                    "current_lf": lf,
                    "future_terminal_state_id": outcome,
                    "future_outcome_kind": "terminal_state" if outcome > 0 else "no_terminal_event",
                    "future_target_T1_kg": vector[0],
                    "future_target_T2_kg": vector[1],
                    "future_target_T3_kg": vector[2],
                    "future_target_T4_kg": vector[3],
                    "future_target_total_kg": float(vector.sum()),
                    "future_target_top_site": top_site(vector),
                    "future_target_ranking": ranking_signature(vector),
                }
            )
    return pd.DataFrame(rows)


def build_node_outputs(active: pd.DataFrame, targets: np.ndarray) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    map_rows: list[dict] = []
    node_rows: list[dict] = []
    dispersion_rows: list[dict] = []
    group_columns = [
        "decision_stage", "history_node_id", "current_k", "current_a", "current_loc", "current_lf"
    ]
    for keys, group in active.groupby(group_columns, sort=True):
        meta = dict(zip(group_columns, keys))
        node_count = int(len(group))
        counts = group["future_terminal_state_id"].value_counts().sort_index()
        for outcome, count in counts.items():
            outcome = int(outcome)
            vector = targets[outcome]
            map_rows.append(
                {
                    **meta,
                    "node_oos_path_count": node_count,
                    "future_terminal_state_id": outcome,
                    "future_outcome_kind": "terminal_state" if outcome > 0 else "no_terminal_event",
                    "outcome_path_count": int(count),
                    "outcome_frequency": float(count / node_count),
                    "T1_kg": vector[0],
                    "T2_kg": vector[1],
                    "T3_kg": vector[2],
                    "T4_kg": vector[3],
                    "TerminalLOH_total_kg": float(vector.sum()),
                    "target_top_site": top_site(vector),
                    "target_ranking": ranking_signature(vector),
                }
            )

        outcome_ids = group["future_terminal_state_id"].to_numpy(int)
        all_values = targets[outcome_ids]
        terminal_mask = outcome_ids > 0
        terminal_values = all_values[terminal_mask]
        terminal_ids = outcome_ids[terminal_mask]
        positive_target_mask = all_values.sum(axis=1) > TOL
        positive_target_values = all_values[positive_target_mask]
        outcome_probs = counts.to_numpy(float) / node_count
        max_outcome_position = int(np.argmax(outcome_probs))
        modal_outcome = int(counts.index[max_outcome_position])
        all_top = np.array([top_site(value) for value in all_values], dtype=int)
        all_rank = np.array([ranking_signature(value) for value in all_values], dtype=object)
        top_counts = pd.Series(all_top).value_counts(normalize=True)
        rank_counts = pd.Series(all_rank).value_counts(normalize=True)
        if terminal_values.size:
            terminal_top = np.array([top_site(value) for value in terminal_values], dtype=int)
            terminal_rank = np.array([ranking_signature(value) for value in terminal_values], dtype=object)
            conditional_top_counts = pd.Series(terminal_top).value_counts(normalize=True)
            conditional_rank_counts = pd.Series(terminal_rank).value_counts(normalize=True)
            terminal_state_counts = pd.Series(terminal_ids).value_counts(normalize=True)
            conditional_modal_state = int(terminal_state_counts.index[0])
            conditional_max_state_probability = float(terminal_state_counts.iloc[0])
            conditional_modal_top_site = int(conditional_top_counts.index[0])
            conditional_modal_top_probability = float(conditional_top_counts.iloc[0])
            conditional_modal_ranking = str(conditional_rank_counts.index[0])
            conditional_modal_ranking_probability = float(conditional_rank_counts.iloc[0])
            conditional_vector_count = int(np.unique(np.round(terminal_values, 10), axis=0).shape[0])
            cond_mean = terminal_values.mean(axis=0)
            cond_min = terminal_values.min(axis=0)
            cond_max = terminal_values.max(axis=0)
            cond_std = terminal_values.std(axis=0, ddof=0)
        else:
            conditional_modal_state = 0
            conditional_max_state_probability = np.nan
            conditional_modal_top_site = 0
            conditional_modal_top_probability = np.nan
            conditional_modal_ranking = "no_terminal_descendant"
            conditional_modal_ranking_probability = np.nan
            conditional_vector_count = 0
            cond_mean = np.full(4, np.nan)
            cond_min = np.full(4, np.nan)
            cond_max = np.full(4, np.nan)
            cond_std = np.full(4, np.nan)
        if positive_target_values.size:
            positive_top = np.array([top_site(value) for value in positive_target_values], dtype=int)
            positive_rank = np.array(
                [ranking_signature(value) for value in positive_target_values], dtype=object
            )
            positive_top_counts = pd.Series(positive_top).value_counts(normalize=True)
            positive_rank_counts = pd.Series(positive_rank).value_counts(normalize=True)
            positive_modal_top_site = int(positive_top_counts.index[0])
            positive_modal_top_probability = float(positive_top_counts.iloc[0])
            positive_modal_ranking = str(positive_rank_counts.index[0])
            positive_modal_ranking_probability = float(positive_rank_counts.iloc[0])
        else:
            positive_modal_top_site = 0
            positive_modal_top_probability = np.nan
            positive_modal_ranking = "no_positive_target_descendant"
            positive_modal_ranking_probability = np.nan
        all_mean = all_values.mean(axis=0)
        all_min = all_values.min(axis=0)
        all_max = all_values.max(axis=0)
        all_std = all_values.std(axis=0, ddof=0)
        node_row = {
            **meta,
            "node_oos_path_count": node_count,
            "future_outcome_count_including_no_terminal": int(len(counts)),
            "future_terminal_state_count": int(np.unique(terminal_ids).size),
            "terminal_hit_probability": float(terminal_mask.mean()),
            "positive_target_probability": float(positive_target_mask.mean()),
            "modal_future_outcome_id": modal_outcome,
            "max_future_outcome_probability": float(outcome_probs[max_outcome_position]),
            "conditional_modal_terminal_state_id": conditional_modal_state,
            "conditional_max_terminal_state_probability": conditional_max_state_probability,
            "target_vector_count_including_zero": int(np.unique(np.round(all_values, 10), axis=0).shape[0]),
            "target_vector_exact_including_zero": int(np.unique(np.round(all_values, 10), axis=0).shape[0] == 1),
            "conditional_terminal_target_vector_count": conditional_vector_count,
            "conditional_terminal_target_vector_exact": int(conditional_vector_count == 1 and terminal_values.size > 0),
            "modal_top_site_including_no_terminal": int(top_counts.index[0]),
            "modal_top_site_probability_including_no_terminal": float(top_counts.iloc[0]),
            "conditional_modal_top_site": conditional_modal_top_site,
            "conditional_modal_top_site_probability": conditional_modal_top_probability,
            "conditional_top_site_certain": int(
                terminal_values.size > 0 and conditional_modal_top_probability >= 1.0 - 1e-12
            ),
            "positive_target_modal_top_site": positive_modal_top_site,
            "positive_target_modal_top_site_probability": positive_modal_top_probability,
            "positive_target_top_site_certain": int(
                positive_target_values.size > 0 and positive_modal_top_probability >= 1.0 - 1e-12
            ),
            "modal_target_ranking_including_no_terminal": str(rank_counts.index[0]),
            "modal_target_ranking_probability_including_no_terminal": float(rank_counts.iloc[0]),
            "conditional_modal_target_ranking": conditional_modal_ranking,
            "conditional_modal_target_ranking_probability": conditional_modal_ranking_probability,
            "positive_target_modal_ranking": positive_modal_ranking,
            "positive_target_modal_ranking_probability": positive_modal_ranking_probability,
            "conditional_target_std_l2_kg": float(np.linalg.norm(cond_std)) if terminal_values.size else np.nan,
            "conditional_max_site_target_range_kg": float(np.max(cond_max - cond_min)) if terminal_values.size else np.nan,
        }
        node_rows.append(node_row)
        for site in range(1, 5):
            dispersion_rows.append(
                {
                    **meta,
                    "node_oos_path_count": node_count,
                    "site": site,
                    "unconditional_target_mean_kg": all_mean[site - 1],
                    "unconditional_target_min_kg": all_min[site - 1],
                    "unconditional_target_max_kg": all_max[site - 1],
                    "unconditional_target_std_kg": all_std[site - 1],
                    "unconditional_target_range_kg": all_max[site - 1] - all_min[site - 1],
                    "conditional_terminal_target_mean_kg": cond_mean[site - 1],
                    "conditional_terminal_target_min_kg": cond_min[site - 1],
                    "conditional_terminal_target_max_kg": cond_max[site - 1],
                    "conditional_terminal_target_std_kg": cond_std[site - 1],
                    "conditional_terminal_target_range_kg": cond_max[site - 1] - cond_min[site - 1],
                }
            )
    return pd.DataFrame(map_rows), pd.DataFrame(node_rows), pd.DataFrame(dispersion_rows)


def attach_node_information(
    observations: pd.DataFrame,
    node_summary: pd.DataFrame,
    node_map: pd.DataFrame,
) -> pd.DataFrame:
    node_keys = ["decision_stage", "history_node_id", "current_k"]
    merged = observations.merge(node_summary, on=node_keys + ["current_a", "current_loc", "current_lf"], how="left")
    probability = node_map[node_keys + ["future_terminal_state_id", "outcome_frequency"]]
    merged = merged.merge(probability, on=node_keys + ["future_terminal_state_id"], how="left")
    if merged["node_oos_path_count"].isna().any() or merged["outcome_frequency"].isna().any():
        raise RuntimeError("Failed to attach history-node information to path observations.")
    return merged


def summarize_scope(scope: str, frame: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for lf in range(1, 7):
        group = frame[frame["current_lf"] == lf]
        if group.empty:
            continue
        rows.append(
            {
                "scope": scope,
                "lf": lf,
                "path_stage_observation_count": int(len(group)),
                "unique_history_node_count": int(group["history_node_id"].nunique()),
                "unique_path_count": int(group["path_id"].nunique()),
                "mean_node_oos_path_count": float(group["node_oos_path_count"].mean()),
                "mean_future_outcome_count_including_no_terminal": float(
                    group["future_outcome_count_including_no_terminal"].mean()
                ),
                "mean_future_terminal_state_count": float(group["future_terminal_state_count"].mean()),
                "mean_terminal_hit_probability": float(group["terminal_hit_probability"].mean()),
                "mean_positive_target_probability": float(group["positive_target_probability"].mean()),
                "mean_max_future_outcome_probability": float(group["max_future_outcome_probability"].mean()),
                "mean_realized_terminal_state_probability": float(group["outcome_frequency"].mean()),
                "exact_target_vector_observation_share": float(
                    group["target_vector_exact_including_zero"].mean()
                ),
                "conditional_terminal_target_vector_exact_observation_share": float(
                    group["conditional_terminal_target_vector_exact"].mean()
                ),
                "mean_conditional_modal_top_site_probability": float(
                    group["conditional_modal_top_site_probability"].mean()
                ),
                "conditional_top_site_certain_observation_share": float(
                    group["conditional_top_site_certain"].mean()
                ),
                "mean_positive_target_modal_top_site_probability": float(
                    group["positive_target_modal_top_site_probability"].mean()
                ),
                "positive_target_top_site_certain_observation_share": float(
                    group["positive_target_top_site_certain"].mean()
                ),
                "mean_conditional_target_std_l2_kg": float(group["conditional_target_std_l2_kg"].mean()),
                "mean_conditional_max_site_target_range_kg": float(
                    group["conditional_max_site_target_range_kg"].mean()
                ),
            }
        )
    return pd.DataFrame(rows)


def build_capacity_gap_summary(physical: pd.DataFrame) -> pd.DataFrame:
    rows = []
    work = physical[physical["state_id"].isin(CAPACITY_STATES)].copy()
    work["total_capacity_gap_kg"] = np.maximum(
        0.0, work["T_total_dro_kg"] - work["service_preserving_max_terminal_total_kg"]
    )
    for state, group in work.groupby("state_id"):
        positive = group[group["total_capacity_gap_kg"] > TOL]
        rows.append(
            {
                "state": int(state),
                "path_count": int(len(group)),
                "total_insufficient_path_count": int(len(positive)),
                "total_insufficient_path_share": float(len(positive) / len(group)),
                "T_total_dro_kg": float(group["T_total_dro_kg"].iloc[0]),
                "mean_max_feasible_total_inventory_kg": float(
                    group["service_preserving_max_terminal_total_kg"].mean()
                ),
                "mean_gap_all_paths_kg": float(group["total_capacity_gap_kg"].mean()),
                "median_gap_all_paths_kg": float(group["total_capacity_gap_kg"].median()),
                "q95_gap_all_paths_kg": float(group["total_capacity_gap_kg"].quantile(0.95)),
                "max_gap_all_paths_kg": float(group["total_capacity_gap_kg"].max()),
                "mean_gap_insufficient_paths_kg": float(positive["total_capacity_gap_kg"].mean()),
                "median_gap_insufficient_paths_kg": float(positive["total_capacity_gap_kg"].median()),
                "q95_gap_insufficient_paths_kg": float(positive["total_capacity_gap_kg"].quantile(0.95)),
                "max_gap_insufficient_paths_kg": float(positive["total_capacity_gap_kg"].max()),
            }
        )
    return pd.DataFrame(rows).sort_values("state")


def select_feasible_unmet(physical: pd.DataFrame) -> pd.DataFrame:
    selected = physical[
        physical["state_id"].isin(FOCUS_STATES)
        & physical["path_classification"].eq("C")
        & (physical["actual_terminal_gap_kg"] > TOL)
    ].copy()
    return selected.sort_values(["state_id", "path_id"])


def build_selected_trace(
    replay_site: pd.DataFrame,
    selected: pd.DataFrame,
    oos: np.ndarray,
    targets: np.ndarray,
    node_summary: pd.DataFrame,
    node_map: pd.DataFrame,
    dispersion: pd.DataFrame,
) -> pd.DataFrame:
    selected_keys = selected[[
        "path_id", "state_id", "actual_terminal_gap_kg", "actual_I_total_dro_kg",
        "T_total_dro_kg", "actual_total_sufficient", "actual_spatial_mismatch",
        "service_preserving_max_terminal_total_kg",
    ]]
    trace = replay_site.merge(selected_keys, on=["path_id", "state_id"], how="inner")
    trace = trace[trace["active"].astype(bool)].copy()
    trace["decision_stage"] = trace["stage"].astype(int)
    trace["current_k"] = [
        int(oos[int(path_id) - 1, int(stage) - 1])
        for path_id, stage in zip(trace["path_id"], trace["decision_stage"])
    ]
    decoded = np.array([decode_state(k) for k in trace["current_k"]], dtype=int)
    trace["current_a"] = decoded[:, 0]
    trace["current_loc"] = decoded[:, 1]
    trace["current_lf"] = decoded[:, 2]
    trace = trace[(trace["current_a"] > 1) & (trace["current_lf"] < 7)].copy()
    trace["history_node_id"] = [
        f"t{int(stage)}_k{int(k)}" for stage, k in zip(trace["decision_stage"], trace["current_k"])
    ]
    trace["future_terminal_state_id"] = trace["state_id"].astype(int)
    trace = attach_node_information(trace, node_summary, node_map)

    dispersion_columns = [
        "decision_stage", "history_node_id", "current_k", "site",
        "unconditional_target_mean_kg", "unconditional_target_std_kg",
        "unconditional_target_range_kg", "conditional_terminal_target_mean_kg",
        "conditional_terminal_target_std_kg", "conditional_terminal_target_range_kg",
    ]
    trace = trace.merge(dispersion[dispersion_columns], on=["decision_stage", "history_node_id", "current_k", "site"], how="left")
    trace["realized_terminal_target_kg"] = [
        targets[int(state), int(site) - 1]
        for state, site in zip(trace["state_id"], trace["site"])
    ]
    trace["realized_terminal_target_total_kg"] = trace["state_id"].map(
        {state: float(targets[state].sum()) for state in FOCUS_STATES}
    )
    trace["realized_target_share"] = (
        trace["realized_terminal_target_kg"] / trace["realized_terminal_target_total_kg"]
    )
    conditional_total = trace.groupby(
        ["method", "path_id", "state_id", "decision_stage"]
    )["conditional_terminal_target_mean_kg"].transform("sum")
    trace["node_conditional_mean_target_share"] = np.where(
        conditional_total > TOL,
        trace["conditional_terminal_target_mean_kg"] / conditional_total,
        np.nan,
    )
    inventory_total = trace.groupby(
        ["method", "path_id", "state_id", "decision_stage"]
    )["end_inventory_kg"].transform("sum")
    trace["inventory_total_kg"] = inventory_total
    trace["inventory_share"] = trace["end_inventory_kg"] / inventory_total
    trace["inventory_vs_realized_target_l1_piece"] = (
        0.5 * np.abs(trace["inventory_share"] - trace["realized_target_share"])
    )
    trace["inventory_vs_node_conditional_mean_l1_piece"] = (
        0.5 * np.abs(trace["inventory_share"] - trace["node_conditional_mean_target_share"])
    )
    group_keys = ["method", "path_id", "state_id", "decision_stage"]
    trace["inventory_vs_realized_target_distribution_l1"] = trace.groupby(group_keys)[
        "inventory_vs_realized_target_l1_piece"
    ].transform("sum")
    trace["inventory_vs_node_conditional_mean_distribution_l1"] = trace.groupby(group_keys)[
        "inventory_vs_node_conditional_mean_l1_piece"
    ].transform("sum")

    inventory_wide = trace.pivot_table(
        index=["path_id", "state_id", "decision_stage", "site"],
        columns="method", values="end_inventory_kg", aggfunc="first",
    ).reset_index()
    if not {"saa", "chi2_eta003"}.issubset(inventory_wide.columns):
        raise RuntimeError("Selected trace lacks paired SAA/DRO inventory rows.")
    inventory_wide["abs_policy_inventory_difference_kg"] = np.abs(
        inventory_wide["chi2_eta003"] - inventory_wide["saa"]
    )
    stage_difference = inventory_wide.groupby(
        ["path_id", "state_id", "decision_stage"], as_index=False
    ).agg(
        policy_inventory_absolute_difference_l1_kg=("abs_policy_inventory_difference_kg", "sum")
    )
    trace = trace.merge(stage_difference, on=["path_id", "state_id", "decision_stage"], how="left")
    keep = [
        "method", "path_id", "state_id", "decision_stage", "current_k", "current_a",
        "current_loc", "current_lf", "history_node_id", "site", "node_oos_path_count",
        "future_outcome_count_including_no_terminal", "future_terminal_state_count",
        "terminal_hit_probability", "outcome_frequency", "conditional_modal_terminal_state_id",
        "conditional_max_terminal_state_probability", "conditional_modal_top_site",
        "conditional_modal_top_site_probability", "conditional_top_site_certain",
        "positive_target_probability", "positive_target_modal_top_site",
        "positive_target_modal_top_site_probability", "positive_target_top_site_certain",
        "conditional_target_std_l2_kg", "conditional_max_site_target_range_kg",
        "conditional_terminal_target_mean_kg", "conditional_terminal_target_std_kg",
        "conditional_terminal_target_range_kg", "realized_terminal_target_kg",
        "realized_target_share", "start_inventory_kg", "end_inventory_kg", "inventory_total_kg",
        "inventory_share", "production_kg", "prod_utilization", "normal_served_kg",
        "normal_shortage_kg", "htt_inflow_kg", "htt_outflow_kg", "net_htt_inflow_kg",
        "inventory_vs_realized_target_distribution_l1",
        "inventory_vs_node_conditional_mean_distribution_l1",
        "policy_inventory_absolute_difference_l1_kg", "actual_terminal_gap_kg",
        "actual_I_total_dro_kg", "T_total_dro_kg", "actual_total_sufficient",
        "actual_spatial_mismatch", "service_preserving_max_terminal_total_kg",
    ]
    return trace[keep].sort_values(["state_id", "path_id", "decision_stage", "method", "site"])


def build_alignment_summary(trace: pd.DataFrame) -> pd.DataFrame:
    dro = trace[trace["method"] == "chi2_eta003"].copy()
    path_stage = dro.groupby(
        ["path_id", "state_id", "decision_stage", "current_lf", "history_node_id"], as_index=False
    ).agg(
        node_oos_path_count=("node_oos_path_count", "first"),
        future_outcome_count_including_no_terminal=("future_outcome_count_including_no_terminal", "first"),
        future_terminal_state_count=("future_terminal_state_count", "first"),
        terminal_hit_probability=("terminal_hit_probability", "first"),
        realized_terminal_state_probability=("outcome_frequency", "first"),
        conditional_max_terminal_state_probability=("conditional_max_terminal_state_probability", "first"),
        conditional_modal_top_site_probability=("conditional_modal_top_site_probability", "first"),
        conditional_top_site_certain=("conditional_top_site_certain", "first"),
        positive_target_probability=("positive_target_probability", "first"),
        positive_target_modal_top_site_probability=("positive_target_modal_top_site_probability", "first"),
        positive_target_top_site_certain=("positive_target_top_site_certain", "first"),
        conditional_target_std_l2_kg=("conditional_target_std_l2_kg", "first"),
        conditional_max_site_target_range_kg=("conditional_max_site_target_range_kg", "first"),
        inventory_vs_realized_target_distribution_l1=("inventory_vs_realized_target_distribution_l1", "first"),
        inventory_vs_node_conditional_mean_distribution_l1=("inventory_vs_node_conditional_mean_distribution_l1", "first"),
        policy_inventory_absolute_difference_l1_kg=("policy_inventory_absolute_difference_l1_kg", "first"),
        inventory_total_kg=("inventory_total_kg", "first"),
        target_total_kg=("T_total_dro_kg", "first"),
        actual_terminal_gap_kg=("actual_terminal_gap_kg", "first"),
        actual_total_sufficient=("actual_total_sufficient", "first"),
        actual_spatial_mismatch=("actual_spatial_mismatch", "first"),
    )
    result = path_stage.groupby(["state_id", "decision_stage", "current_lf"], as_index=False).agg(
        selected_path_count=("path_id", "nunique"),
        unique_history_node_count=("history_node_id", "nunique"),
        mean_node_oos_path_count=("node_oos_path_count", "mean"),
        mean_future_outcome_count_including_no_terminal=("future_outcome_count_including_no_terminal", "mean"),
        mean_future_terminal_state_count=("future_terminal_state_count", "mean"),
        mean_terminal_hit_probability=("terminal_hit_probability", "mean"),
        mean_realized_terminal_state_probability=("realized_terminal_state_probability", "mean"),
        mean_conditional_max_terminal_state_probability=("conditional_max_terminal_state_probability", "mean"),
        mean_conditional_modal_top_site_probability=("conditional_modal_top_site_probability", "mean"),
        conditional_top_site_certain_path_share=("conditional_top_site_certain", "mean"),
        mean_positive_target_probability=("positive_target_probability", "mean"),
        mean_positive_target_modal_top_site_probability=("positive_target_modal_top_site_probability", "mean"),
        positive_target_top_site_certain_path_share=("positive_target_top_site_certain", "mean"),
        mean_conditional_target_std_l2_kg=("conditional_target_std_l2_kg", "mean"),
        mean_conditional_max_site_target_range_kg=("conditional_max_site_target_range_kg", "mean"),
        mean_inventory_vs_realized_target_distribution_l1=("inventory_vs_realized_target_distribution_l1", "mean"),
        mean_inventory_vs_node_conditional_mean_distribution_l1=("inventory_vs_node_conditional_mean_distribution_l1", "mean"),
        mean_policy_inventory_absolute_difference_l1_kg=("policy_inventory_absolute_difference_l1_kg", "mean"),
        mean_inventory_total_kg=("inventory_total_kg", "mean"),
        mean_target_total_kg=("target_total_kg", "mean"),
        mean_terminal_gap_kg=("actual_terminal_gap_kg", "mean"),
        actual_total_sufficient_path_share=("actual_total_sufficient", "mean"),
        actual_spatial_mismatch_path_share=("actual_spatial_mismatch", "mean"),
    )
    return result.rename(columns={"state_id": "state"})


def build_cut_request(
    trace: pd.DataFrame, selected: pd.DataFrame, targets: np.ndarray
) -> pd.DataFrame:
    dro_trace = trace[trace["method"] == "chi2_eta003"].copy()
    request_rows = []
    for state in FOCUS_STATES:
        candidates = selected[selected["state_id"] == state].sort_values(
            ["actual_terminal_gap_kg", "path_id"], ascending=[False, True]
        )
        used_nodes: set[tuple[int, int]] = set()
        chosen = 0
        for meta in candidates.itertuples(index=False):
            rows = dro_trace[(dro_trace["path_id"] == meta.path_id) & (dro_trace["state_id"] == state)]
            if rows.empty:
                continue
            latest_stage = int(rows["decision_stage"].max())
            stage_rows = rows[rows["decision_stage"] == latest_stage].sort_values("site")
            node_key = (latest_stage, int(stage_rows["current_k"].iloc[0]))
            if node_key in used_nodes:
                continue
            used_nodes.add(node_key)
            for method in ["saa", "chi2_eta003"]:
                method_rows = trace[
                    (trace["method"] == method)
                    & (trace["path_id"] == meta.path_id)
                    & (trace["state_id"] == state)
                    & (trace["decision_stage"] == latest_stage)
                ].sort_values("site")
                if len(method_rows) != 4:
                    raise RuntimeError("Cut request path-stage does not have four station rows.")
                row = {
                    "method": method,
                    "path_id": int(meta.path_id),
                    "state": state,
                    "decision_stage": latest_stage,
                    "current_k": node_key[1],
                    "current_a": int(method_rows["current_a"].iloc[0]),
                    "current_loc": int(method_rows["current_loc"].iloc[0]),
                    "current_lf": int(method_rows["current_lf"].iloc[0]),
                    "history_node_id": str(method_rows["history_node_id"].iloc[0]),
                    "selection_reason": "largest_terminal_gap_distinct_latest_information_node",
                    "terminal_gap_kg": float(meta.actual_terminal_gap_kg),
                    "node_oos_path_count": int(method_rows["node_oos_path_count"].iloc[0]),
                    "future_terminal_state_count": int(method_rows["future_terminal_state_count"].iloc[0]),
                    "realized_terminal_state_probability": float(method_rows["outcome_frequency"].iloc[0]),
                    "conditional_modal_top_site": int(method_rows["conditional_modal_top_site"].iloc[0]),
                    "conditional_modal_top_site_probability": float(
                        method_rows["conditional_modal_top_site_probability"].iloc[0]
                    ),
                    "positive_target_modal_top_site": int(
                        method_rows["positive_target_modal_top_site"].iloc[0]
                    ),
                    "positive_target_modal_top_site_probability": float(
                        method_rows["positive_target_modal_top_site_probability"].iloc[0]
                    ),
                    "conditional_max_site_target_range_kg": float(
                        method_rows["conditional_max_site_target_range_kg"].iloc[0]
                    ),
                    "inventory_vs_realized_target_distribution_l1": float(
                        method_rows["inventory_vs_realized_target_distribution_l1"].iloc[0]
                    ),
                }
                for site in range(1, 5):
                    site_row = method_rows[method_rows["site"] == site].iloc[0]
                    row[f"x{site}_kg"] = float(site_row["end_inventory_kg"])
                    row[f"realized_target_site{site}_kg"] = float(targets[state, site - 1])
                    row[f"node_conditional_mean_target_site{site}_kg"] = float(
                        site_row["conditional_terminal_target_mean_kg"]
                    )
                request_rows.append(row)
            chosen += 1
            if chosen >= 3:
                break
    request = pd.DataFrame(request_rows)
    if request.empty or set(request["method"].unique()) != {"saa", "chi2_eta003"}:
        raise RuntimeError("Representative cut request is incomplete.")
    return request.sort_values(["state", "path_id", "method"])


def compute(repo: Path) -> dict[str, object]:
    step53 = repo / "results/task-002-stage2b-b3-smoke/53-35state-saa-vs-eta003-terminal-loh/run-024"
    step61 = repo / "results/task-002-stage2b-b3-smoke/61-terminal-loh-system-feasibility-audit/run-001"
    oos_file = repo / "output_h2/details/h2_OOS.csv"
    table_file = step53 / "terminal_loh_table_eta_003.csv"
    physical_file = step61 / "physical_feasibility_path_audit.csv"
    replay_file = step61 / "replay_stage_site_observations.csv"
    for path in [oos_file, table_file, physical_file, replay_file]:
        if not path.is_file():
            raise FileNotFoundError(path)

    oos_frame = pd.read_csv(oos_file)
    oos = oos_frame.to_numpy(int)
    if oos.shape != (10000, 8):
        raise RuntimeError(f"Frozen OOS shape changed: {oos.shape}")
    table = pd.read_csv(table_file)
    targets = build_target_matrix(table)
    outcomes = build_terminal_outcomes(oos)
    if int((outcomes["terminal_state_id"] > 0).sum()) != 6053:
        raise RuntimeError("Expected 6053 terminal-hit OOS paths.")
    active = build_active_observations(oos, outcomes, targets)
    node_map, node_summary, dispersion = build_node_outputs(active, targets)
    active_with_info = attach_node_information(active, node_summary, node_map)

    physical = pd.read_csv(physical_file)
    replay = pd.read_csv(replay_file)
    selected = select_feasible_unmet(physical)
    expected_selected = {12: 68, 13: 11, 14: 42, 19: 8}
    actual_selected = selected.groupby("state_id").size().to_dict()
    if actual_selected != expected_selected:
        raise RuntimeError(f"Feasible-unmet selected counts changed: {actual_selected}")
    outcome_lookup = outcomes.set_index("path_id")["terminal_state_id"]
    if not all(int(outcome_lookup.loc[int(row.path_id)]) == int(row.state_id) for row in selected.itertuples()):
        raise RuntimeError("Selected physical rows do not match OOS terminal states.")

    capacity_gap = build_capacity_gap_summary(physical)
    trace = build_selected_trace(replay, selected, oos, targets, node_summary, node_map, dispersion)
    alignment = build_alignment_summary(trace)
    cut_request = build_cut_request(trace, selected, targets)

    stage_parts = [summarize_scope("all_active_oos_paths", active_with_info)]
    selected_path_ids = set(selected["path_id"].astype(int))
    selected_active = active_with_info[active_with_info["path_id"].isin(selected_path_ids)].copy()
    for state in FOCUS_STATES:
        path_ids = set(selected[selected["state_id"] == state]["path_id"].astype(int))
        stage_parts.append(
            summarize_scope(f"state{state}_physical_feasible_actual_unmet", selected_active[selected_active["path_id"].isin(path_ids)])
        )
    stage_summary = pd.concat(stage_parts, ignore_index=True)

    clairvoyant_text = """Step-05B-4 diagnostic LP information-scope audit

Mechanical source evidence
- run_step05B4_system_feasibility_replay_h2.m:132-165 first selects a realized OOS path, finds its realized terminal time/state, and loads the realized terminal target.
- Lines 167-187 reconstruct the complete realized ordinary-service matrix along that path.
- Line 243 calls solve_physical_path(p, OOS(s,:), tTerm, servedMatrix, target), passing the complete realized path, realized terminal time, realized service quantities, and realized target into a new optimization of all preceding production/inventory/HTT decisions.
- solve_physical_path at lines 314 onward jointly reoptimizes decisions for all pre-terminal stages.

Audit conclusion
- YES: the 1298 Step-05B-4 diagnostic LPs are ex-post perfect-information / clairvoyant physical-feasibility diagnostics.
- They prove only: given the complete realized future path and final TerminalLOH state, the preserved physical constraints can or cannot realize the target while maintaining the saved DRO policy's ordinary H2 service quantities.
- They do NOT prove that the original FA-MSP policy, which observes uncertainty sequentially, should have selected the same station allocation before the terminal state was known.

True FA-MSP information node used in Step-05B-5
- forward_pass_h2.m:14-15 samples and observes current Markov state k_t from P_joint.
- forward_pass_h2.m:51-53 selects modelLib.models{t,k_t}; the endogenous state is the incoming four-station inventory vector.
- backward_pass_h2.m:42 uses P_joint(n,:) for future-value aggregation.
- Therefore the exogenous recombining information node is (decision stage t, current Markov state k), with current inventory x as the endogenous state. This audit never groups by a future terminal state when defining a node.
- Empirical descendant frequencies are calculated from all 10000 frozen OOS paths reaching each (t,k) node. A no-terminal descendant is retained as outcome 0 with zero TerminalLOH rather than silently discarded.
"""

    integrity = f"""Step-05B-5 prepare integrity audit

Frozen OOS: {oos_file}
OOS SHA-256: {sha256_file(oos_file)}
OOS shape: {oos.shape[0]} x {oos.shape[1]}
Terminal-hit paths: {int((outcomes.terminal_state_id > 0).sum())}
Active path-stage observations: {len(active)}
Recombining (t,k) information nodes: {node_summary.history_node_id.nunique()}
Node-outcome rows: {len(node_map)}
Node-site dispersion rows: {len(dispersion)}
Physical-feasible actual-unmet selected paths: {len(selected)}
Selected counts by state: {actual_selected}
Selected trace rows: {len(trace)}
Representative cut request rows: {len(cut_request)}
No training, sampling, cut generation, TerminalLOH change, or penalty change was performed.
Prepare PASS: 1
"""
    return {
        "capacity_gap": capacity_gap,
        "node_map": node_map,
        "dispersion": dispersion,
        "stage_summary": stage_summary,
        "trace": trace,
        "alignment": alignment,
        "cut_request": cut_request,
        "clairvoyant_text": clairvoyant_text,
        "integrity": integrity,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--phase", choices=["dry-run", "prepare"], default="dry-run")
    parser.add_argument("--run-id", default="run-001")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    result = compute(repo)
    if args.phase == "dry-run":
        print(result["integrity"])
        print(result["capacity_gap"].to_string(index=False))
        print(result["stage_summary"].to_string(index=False))
        return

    out = repo / "results/task-002-stage2b-b3-smoke/62-terminal-loh-information-revelation-audit" / args.run_id
    if out.exists():
        raise RuntimeError(f"Refusing to overwrite existing run directory: {out}")
    out.mkdir(parents=True)
    result["capacity_gap"].to_csv(out / "total_capacity_gap_summary.csv", index=False, float_format="%.15g")
    result["node_map"].to_csv(out / "history_node_terminal_state_map.csv", index=False, float_format="%.15g")
    result["dispersion"].to_csv(out / "history_node_terminal_loh_dispersion.csv", index=False, float_format="%.15g")
    result["stage_summary"].to_csv(out / "stage_information_revelation_summary.csv", index=False, float_format="%.15g")
    result["trace"].to_csv(out / "selected_path_inventory_trace.csv", index=False, float_format="%.15g")
    result["alignment"].to_csv(out / "selected_node_policy_alignment.csv", index=False, float_format="%.15g")
    result["cut_request"].to_csv(out / "cut_audit_request.csv", index=False, float_format="%.15g")
    (out / "clairvoyant_lp_scope_audit.txt").write_text(result["clairvoyant_text"], encoding="utf-8")
    (out / "prepare_integrity_audit.txt").write_text(result["integrity"], encoding="utf-8")
    print(f"Step-05B-5 prepare PASS: {out}")


if __name__ == "__main__":
    main()
