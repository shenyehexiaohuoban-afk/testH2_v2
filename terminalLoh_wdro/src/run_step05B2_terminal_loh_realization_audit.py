"""Step-05B-2 read-only TerminalLOH realization audit.

This script consumes only accepted lightweight outputs from Step-05B-1 and the
frozen 35-state TerminalLOH tables.  It does not load, train, or modify the MSP.
"""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path

import numpy as np
import pandas as pd


EPS = 1.0e-12
GAP_EPS = 1.0e-9
METHODS = ("saa", "chi2_eta003")
METHOD_LABEL = {"saa": "SAA", "chi2_eta003": "eta=0.03"}
SITE_COLS = {
    1: ("target_site1", "final_site1", "gap_site1"),
    2: ("target_site2", "final_site2", "gap_site2"),
    3: ("target_site3", "final_site3", "gap_site3"),
    4: ("target_site4", "final_site4", "gap_site4"),
}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def finite_mean(values: pd.Series) -> float:
    values = pd.to_numeric(values, errors="coerce")
    return float(values.mean()) if values.notna().any() else np.nan


def weighted_mean(values: pd.Series, weights: pd.Series) -> float:
    mask = values.notna() & weights.notna() & (weights > 0)
    if not mask.any():
        return np.nan
    return float(np.average(values.loc[mask], weights=weights.loc[mask]))


def load_and_validate_inputs(repo: Path):
    run_b1 = repo / "results/task-002-stage2b-b3-smoke/58-main-msp-terminal-gap-mechanism-audit/run-004"
    c6 = repo / "results/task-002-stage2b-b3-smoke/53-35state-saa-vs-eta003-terminal-loh/run-024"
    rowwise_path = run_b1 / "terminal_target_vs_final_inventory.csv"
    worse_path = run_b1 / "ordinary_shortage_worse_scenario_audit.csv"
    saa_table_path = c6 / "terminal_loh_table_saa.csv"
    dro_table_path = c6 / "terminal_loh_table_eta_003.csv"
    paths = [rowwise_path, worse_path, saa_table_path, dro_table_path]
    for path in paths:
        if not path.is_file():
            raise FileNotFoundError(f"Missing frozen input: {path}")

    rowwise = pd.read_csv(rowwise_path)
    worse = pd.read_csv(worse_path)
    saa_table = pd.read_csv(saa_table_path)
    dro_table = pd.read_csv(dro_table_path)

    if len(rowwise) != 20000 or set(rowwise["method"]) != set(METHODS):
        raise RuntimeError("Expected exactly 20000 rows and the two frozen methods.")
    for method in METHODS:
        part = rowwise[rowwise["method"] == method].sort_values("path_id")
        if len(part) != 10000 or not np.array_equal(part["path_id"].to_numpy(), np.arange(1, 10001)):
            raise RuntimeError(f"{method}: expected path_id 1..10000 exactly once.")

    saa_paths = rowwise[rowwise["method"] == "saa"].sort_values("path_id")
    dro_paths = rowwise[rowwise["method"] == "chi2_eta003"].sort_values("path_id")
    event_cols = ["path_id", "hit_terminal", "terminal_stage", "terminal_state", "a", "loc", "lf"]
    if not saa_paths[event_cols].reset_index(drop=True).equals(dro_paths[event_cols].reset_index(drop=True)):
        raise RuntimeError("The two methods do not have identical rowwise terminal events.")
    if int(saa_paths["hit_terminal"].sum()) != 6053:
        raise RuntimeError("Expected exactly 6053 common terminal-hit paths.")

    for table, expected_eta, label in ((saa_table, 0.0, "SAA"), (dro_table, 0.03, "eta=0.03")):
        if len(table) != 35 or not np.array_equal(table["state_id"].to_numpy(), np.arange(1, 36)):
            raise RuntimeError(f"{label}: frozen table must contain ordered state_id 1..35.")
        if float(np.max(np.abs(table["eta"].to_numpy(dtype=float) - expected_eta))) > EPS:
            raise RuntimeError(f"{label}: unexpected eta column.")
        mapped_state = (table["intensity"].to_numpy(dtype=int) - 2) * 7 + table["loc"].to_numpy(dtype=int)
        if not np.array_equal(mapped_state, table["state_id"].to_numpy(dtype=int)):
            raise RuntimeError(f"{label}: state_id/intensity/location mapping mismatch.")

    rowwise = rowwise.copy()
    rowwise["state_id"] = np.where(
        rowwise["hit_terminal"].eq(1),
        (rowwise["a"].astype(int) - 2) * 7 + rowwise["loc"].astype(int),
        0,
    ).astype(int)

    for method, table in (("saa", saa_table), ("chi2_eta003", dro_table)):
        part = rowwise[(rowwise["method"] == method) & rowwise["hit_terminal"].eq(1)].copy()
        lookup = table.set_index("state_id")
        for site in range(1, 5):
            expected = part["state_id"].map(lookup[f"T{site}_kg"]).to_numpy(dtype=float)
            actual = part[f"target_site{site}"].to_numpy(dtype=float)
            if float(np.max(np.abs(expected - actual))) > 1.0e-8:
                raise RuntimeError(f"{method}: target mismatch at site {site}.")

    target_sum_error = np.max(np.abs(rowwise["target_total"] - rowwise[[f"target_site{i}" for i in range(1, 5)]].sum(axis=1)))
    final_sum_error = np.max(np.abs(rowwise["final_total"] - rowwise[[f"final_site{i}" for i in range(1, 5)]].sum(axis=1)))
    gap_sum_error = np.max(np.abs(rowwise["gap_total"] - rowwise[[f"gap_site{i}" for i in range(1, 5)]].sum(axis=1)))
    if max(target_sum_error, final_sum_error, gap_sum_error) > 1.0e-8:
        raise RuntimeError("Station/four-station total reconstruction failed.")

    recomputed_worse = set(
        saa_paths.loc[
            dro_paths["ordinary_shortage"].to_numpy() > saa_paths["ordinary_shortage"].to_numpy() + GAP_EPS,
            "path_id",
        ].astype(int)
    )
    frozen_worse = set(worse["path_id"].astype(int))
    if recomputed_worse != frozen_worse or len(frozen_worse) != 280:
        raise RuntimeError("The Step-05B-1 280-path subset was not reproduced exactly.")

    integrity = {
        "target_sum_error": float(target_sum_error),
        "final_sum_error": float(final_sum_error),
        "gap_sum_error": float(gap_sum_error),
        "common_terminal_hits": 6053,
        "unreached_state_count": 35 - int(rowwise.loc[rowwise["hit_terminal"].eq(1), "state_id"].nunique()),
    }
    source_paths = {
        "step05b1_rowwise": rowwise_path,
        "step05b1_ordinary_worse": worse_path,
        "c6_saa_table": saa_table_path,
        "c6_eta003_table": dro_table_path,
    }
    return rowwise, worse, saa_table, dro_table, integrity, source_paths


def build_state_station_table(rowwise: pd.DataFrame, saa_table: pd.DataFrame, dro_table: pd.DataFrame) -> pd.DataFrame:
    table_by_method = {"saa": saa_table.set_index("state_id"), "chi2_eta003": dro_table.set_index("state_id")}
    rows = []
    for method in METHODS:
        method_rows = rowwise[(rowwise["method"] == method) & rowwise["hit_terminal"].eq(1)]
        frozen = table_by_method[method]
        for state_id in range(1, 36):
            state_paths = method_rows[method_rows["state_id"] == state_id]
            count = len(state_paths)
            state_meta = frozen.loc[state_id]
            for site in range(1, 5):
                target_col, final_col, gap_col = SITE_COLS[site]
                target = float(state_meta[f"T{site}_kg"])
                if count:
                    final = state_paths[final_col].astype(float)
                    gap = state_paths[gap_col].astype(float)
                    mean_final = float(final.mean())
                    mean_gap = float(gap.mean())
                    positive_gap_probability = float((gap > GAP_EPS).mean()) if target > EPS else 0.0
                    mean_attainment = float((np.minimum(final, target) / target).mean()) if target > EPS else np.nan
                    relative_gap = mean_gap / target if target > EPS else np.nan
                else:
                    mean_final = mean_gap = positive_gap_probability = mean_attainment = relative_gap = np.nan
                rows.append(
                    {
                        "method": method,
                        "method_label": METHOD_LABEL[method],
                        "state_id": state_id,
                        "intensity": int(state_meta["intensity"]),
                        "loc": int(state_meta["loc"]),
                        "lfw_table": int(state_meta["lfw"]),
                        "main_msp_terminal_k": int(((int(state_meta["intensity"]) - 1) * 7 + (int(state_meta["loc"]) - 1)) * 8 + 7),
                        "site": site,
                        "target_kg": target,
                        "target_class": "positive_target" if target > EPS else "zero_target",
                        "arrival_count": count,
                        "arrival_frequency_full_oos": count / 10000.0,
                        "arrival_frequency_given_terminal_hit": count / 6053.0,
                        "mean_final_inventory_kg": mean_final,
                        "mean_gap_kg": mean_gap,
                        "mean_attainment": mean_attainment,
                        "positive_gap_probability": positive_gap_probability,
                        "mean_relative_gap": relative_gap,
                    }
                )
    return pd.DataFrame(rows)


def build_incremental_table(state_station: pd.DataFrame) -> pd.DataFrame:
    saa = state_station[state_station["method"] == "saa"].set_index(["state_id", "site"])
    dro = state_station[state_station["method"] == "chi2_eta003"].set_index(["state_id", "site"])
    rows = []
    for key in saa.index:
        a = saa.loc[key]
        b = dro.loc[key]
        delta_t = float(b["target_kg"] - a["target_kg"])
        delta_i = float(b["mean_final_inventory_kg"] - a["mean_final_inventory_kg"]) if a["arrival_count"] > 0 else np.nan
        if delta_t > EPS:
            category = "positive_delta_target"
            ratio = delta_i / delta_t if np.isfinite(delta_i) else np.nan
        elif delta_t < -EPS:
            category = "negative_delta_target"
            ratio = np.nan
        else:
            category = "zero_delta_target"
            ratio = np.nan
        freq_full = float(a["arrival_frequency_full_oos"])
        freq_terminal = float(a["arrival_frequency_given_terminal_hit"])
        rows.append(
            {
                "state_id": int(key[0]),
                "intensity": int(a["intensity"]),
                "loc": int(a["loc"]),
                "main_msp_terminal_k": int(a["main_msp_terminal_k"]),
                "site": int(key[1]),
                "arrival_count": int(a["arrival_count"]),
                "arrival_frequency_full_oos": freq_full,
                "arrival_frequency_given_terminal_hit": freq_terminal,
                "T_saa_kg": float(a["target_kg"]),
                "T_dro_kg": float(b["target_kg"]),
                "DeltaT_dro_minus_saa_kg": delta_t,
                "mean_I_saa_kg": float(a["mean_final_inventory_kg"]),
                "mean_I_dro_kg": float(b["mean_final_inventory_kg"]),
                "DeltaI_dro_minus_saa_kg": delta_i,
                "increment_class": category,
                "increment_realization_ratio": ratio,
                "saa_mean_attainment": float(a["mean_attainment"]),
                "dro_mean_attainment": float(b["mean_attainment"]),
                "attainment_delta_dro_minus_saa": float(b["mean_attainment"] - a["mean_attainment"]),
                "weighted_DeltaT_per_full_oos_path_kg": freq_full * delta_t,
                "weighted_DeltaI_per_full_oos_path_kg": freq_full * delta_i if np.isfinite(delta_i) else np.nan,
                "weighted_DeltaT_per_terminal_hit_path_kg": freq_terminal * delta_t,
                "weighted_DeltaI_per_terminal_hit_path_kg": freq_terminal * delta_i if np.isfinite(delta_i) else np.nan,
                "unrealized_increment_DeltaT_minus_DeltaI_kg": delta_t - delta_i if np.isfinite(delta_i) else np.nan,
                "weighted_unrealized_increment_per_terminal_hit_path_kg": freq_terminal * (delta_t - delta_i) if np.isfinite(delta_i) else np.nan,
            }
        )
    return pd.DataFrame(rows)


def build_state_summary(rowwise: pd.DataFrame, incremental: pd.DataFrame, worse: pd.DataFrame) -> pd.DataFrame:
    worse_ids = set(worse["path_id"].astype(int))
    rows = []
    for state_id in range(1, 36):
        state = {"state_id": state_id}
        method_parts = {}
        for method in METHODS:
            part = rowwise[(rowwise["method"] == method) & rowwise["hit_terminal"].eq(1) & rowwise["state_id"].eq(state_id)]
            method_parts[method] = part
            prefix = "saa" if method == "saa" else "dro"
            count = len(part)
            state[f"{prefix}_arrival_count"] = count
            if count:
                target_total = float(part["target_total"].iloc[0])
                state[f"{prefix}_target_total_kg"] = target_total
                state[f"{prefix}_mean_final_total_kg"] = float(part["final_total"].mean())
                state[f"{prefix}_mean_gap_total_kg"] = float(part["gap_total"].mean())
                if target_total > EPS:
                    state[f"{prefix}_mean_attainment"] = float(part["attainment_ratio"].mean())
                    state[f"{prefix}_positive_gap_probability"] = float((part["gap_total"] > GAP_EPS).mean())
                else:
                    state[f"{prefix}_mean_attainment"] = np.nan
                    state[f"{prefix}_positive_gap_probability"] = 0.0
            else:
                frozen_rows = incremental[incremental["state_id"] == state_id]
                state[f"{prefix}_target_total_kg"] = float(frozen_rows[f"T_{'saa' if prefix == 'saa' else 'dro'}_kg"].sum())
                state[f"{prefix}_mean_final_total_kg"] = np.nan
                state[f"{prefix}_mean_gap_total_kg"] = np.nan
                state[f"{prefix}_mean_attainment"] = np.nan
                state[f"{prefix}_positive_gap_probability"] = np.nan

        saa_part = method_parts["saa"]
        count = len(saa_part)
        state["arrival_count"] = count
        state["arrival_frequency_full_oos"] = count / 10000.0
        state["arrival_frequency_given_terminal_hit"] = count / 6053.0
        state["DeltaT_total_kg"] = state["dro_target_total_kg"] - state["saa_target_total_kg"]
        state["DeltaI_total_kg"] = state["dro_mean_final_total_kg"] - state["saa_mean_final_total_kg"]
        state["increment_realization_ratio_total"] = (
            state["DeltaI_total_kg"] / state["DeltaT_total_kg"]
            if state["DeltaT_total_kg"] > EPS and np.isfinite(state["DeltaI_total_kg"])
            else np.nan
        )
        state["attainment_delta_dro_minus_saa"] = state["dro_mean_attainment"] - state["saa_mean_attainment"]
        state["weighted_DeltaT_per_terminal_hit_path_kg"] = state["arrival_frequency_given_terminal_hit"] * state["DeltaT_total_kg"]
        state["weighted_DeltaI_per_terminal_hit_path_kg"] = state["arrival_frequency_given_terminal_hit"] * state["DeltaI_total_kg"]
        state["weighted_unrealized_increment_per_terminal_hit_path_kg"] = (
            state["arrival_frequency_given_terminal_hit"] * (state["DeltaT_total_kg"] - state["DeltaI_total_kg"])
            if state["DeltaT_total_kg"] > EPS and np.isfinite(state["DeltaI_total_kg"])
            else np.nan
        )
        state_path_ids = set(saa_part["path_id"].astype(int))
        worse_count = len(state_path_ids & worse_ids)
        state["ordinary_shortage_worse_count"] = worse_count
        state["ordinary_shortage_worse_share_of_all_280"] = worse_count / 280.0
        state["ordinary_shortage_worse_probability_given_state"] = worse_count / count if count else np.nan
        rows.append(state)
    return pd.DataFrame(rows)


def method_summary(method: str, rowwise: pd.DataFrame, state_station: pd.DataFrame, state_summary: pd.DataFrame) -> pd.DataFrame:
    hit = rowwise[(rowwise["method"] == method) & rowwise["hit_terminal"].eq(1)].copy()
    target_cols = [f"target_site{i}" for i in range(1, 5)]
    final_cols = [f"final_site{i}" for i in range(1, 5)]
    gap_cols = [f"gap_site{i}" for i in range(1, 5)]
    targets = hit[target_cols].to_numpy(dtype=float)
    finals = hit[final_cols].to_numpy(dtype=float)
    gaps = hit[gap_cols].to_numpy(dtype=float)
    positive_cells = targets > EPS
    positive_paths = hit["target_total"] > EPS
    ss = state_station[(state_station["method"] == method) & state_station["arrival_count"].gt(0)]
    ss_pos = ss[ss["target_kg"] > EPS]
    prefix = "saa" if method == "saa" else "dro"
    st_pos = state_summary[(state_summary["arrival_count"] > 0) & (state_summary[f"{prefix}_target_total_kg"] > EPS)]
    common_pos = state_summary[
        (state_summary["arrival_count"] > 0)
        & (state_summary["saa_target_total_kg"] > EPS)
        & (state_summary["dro_target_total_kg"] > EPS)
    ]

    metrics = [
        ("all_10000_paths_four_station_total", 10000, float(rowwise[rowwise["method"] == method]["target_total"].mean()), float(rowwise[rowwise["method"] == method]["final_total"].mean()), float(rowwise[rowwise["method"] == method]["gap_total"].mean()), np.nan, np.nan, np.nan),
        ("6053_terminal_hit_paths_four_station_total", len(hit), float(hit["target_total"].mean()), float(hit["final_total"].mean()), float(hit["gap_total"].mean()), np.nan, float((hit["gap_total"] > GAP_EPS).mean()), np.nan),
        ("own_positive_target_paths_four_station_total", int(positive_paths.sum()), float(hit.loc[positive_paths, "target_total"].mean()), float(hit.loc[positive_paths, "final_total"].mean()), float(hit.loc[positive_paths, "gap_total"].mean()), float(hit.loc[positive_paths, "attainment_ratio"].mean()), float((hit.loc[positive_paths, "gap_total"] > GAP_EPS).mean()), 1.0 - float(hit.loc[positive_paths, "gap_total"].sum() / hit.loc[positive_paths, "target_total"].sum())),
        ("own_positive_target_station_path_cells", int(positive_cells.sum()), float(targets[positive_cells].mean()), float(finals[positive_cells].mean()), float(gaps[positive_cells].mean()), float(np.mean(np.minimum(finals[positive_cells], targets[positive_cells]) / targets[positive_cells])), float(np.mean(gaps[positive_cells] > GAP_EPS)), 1.0 - float(gaps[positive_cells].sum() / targets[positive_cells].sum())),
        ("equal_observed_positive_state_station_cells", len(ss_pos), float(ss_pos["target_kg"].mean()), float(ss_pos["mean_final_inventory_kg"].mean()), float(ss_pos["mean_gap_kg"].mean()), float(ss_pos["mean_attainment"].mean()), float(ss_pos["positive_gap_probability"].mean()), 1.0 - float(ss_pos["mean_gap_kg"].sum() / ss_pos["target_kg"].sum())),
        ("equal_observed_positive_target_states", len(st_pos), float(st_pos[f"{prefix}_target_total_kg"].mean()), float(st_pos[f"{prefix}_mean_final_total_kg"].mean()), float(st_pos[f"{prefix}_mean_gap_total_kg"].mean()), float(st_pos[f"{prefix}_mean_attainment"].mean()), float(st_pos[f"{prefix}_positive_gap_probability"].mean()), 1.0 - float(st_pos[f"{prefix}_mean_gap_total_kg"].sum() / st_pos[f"{prefix}_target_total_kg"].sum())),
        ("common_positive_target_states_oos_frequency_weighted", int(common_pos["arrival_count"].sum()), weighted_mean(common_pos[f"{prefix}_target_total_kg"], common_pos["arrival_count"]), weighted_mean(common_pos[f"{prefix}_mean_final_total_kg"], common_pos["arrival_count"]), weighted_mean(common_pos[f"{prefix}_mean_gap_total_kg"], common_pos["arrival_count"]), weighted_mean(common_pos[f"{prefix}_mean_attainment"], common_pos["arrival_count"]), weighted_mean(common_pos[f"{prefix}_positive_gap_probability"], common_pos["arrival_count"]), 1.0 - float((common_pos[f"{prefix}_mean_gap_total_kg"] * common_pos["arrival_count"]).sum() / (common_pos[f"{prefix}_target_total_kg"] * common_pos["arrival_count"]).sum())),
    ]
    return pd.DataFrame(
        metrics,
        columns=["aggregation_scope", "observation_count", "mean_target_kg", "mean_final_inventory_kg", "mean_gap_kg", "mean_attainment", "positive_gap_probability", "target_mass_weighted_attainment"],
    ).assign(method=method, method_label=METHOD_LABEL[method])[
        ["method", "method_label", "aggregation_scope", "observation_count", "mean_target_kg", "mean_final_inventory_kg", "mean_gap_kg", "mean_attainment", "positive_gap_probability", "target_mass_weighted_attainment"]
    ]


def build_incremental_summary(incremental: pd.DataFrame, state_summary: pd.DataFrame, rowwise: pd.DataFrame) -> pd.DataFrame:
    pos_cells = incremental[(incremental["increment_class"] == "positive_delta_target") & incremental["arrival_count"].gt(0)]
    pos_states = state_summary[(state_summary["DeltaT_total_kg"] > EPS) & state_summary["arrival_count"].gt(0)]
    saa_hit = rowwise[(rowwise["method"] == "saa") & rowwise["hit_terminal"].eq(1)].sort_values("path_id")
    dro_hit = rowwise[(rowwise["method"] == "chi2_eta003") & rowwise["hit_terminal"].eq(1)].sort_values("path_id")
    raw_delta_t = float((dro_hit["target_total"].to_numpy() - saa_hit["target_total"].to_numpy()).mean())
    raw_delta_i = float((dro_hit["final_total"].to_numpy() - saa_hit["final_total"].to_numpy()).mean())

    rows = [
        {
            "scope": "positive_DeltaT_state_station_cells_frequency_weighted",
            "eligible_unit_count": len(pos_cells),
            "weighted_DeltaT_kg_per_terminal_hit_path": float(pos_cells["weighted_DeltaT_per_terminal_hit_path_kg"].sum()),
            "weighted_DeltaI_kg_per_terminal_hit_path": float(pos_cells["weighted_DeltaI_per_terminal_hit_path_kg"].sum()),
            "increment_realization_ratio": float(pos_cells["weighted_DeltaI_per_terminal_hit_path_kg"].sum() / pos_cells["weighted_DeltaT_per_terminal_hit_path_kg"].sum()),
            "interpretation": "Primary strict station-level ratio; only cells with DeltaT>0 are eligible.",
        },
        {
            "scope": "positive_DeltaT_state_totals_frequency_weighted",
            "eligible_unit_count": len(pos_states),
            "weighted_DeltaT_kg_per_terminal_hit_path": float(pos_states["weighted_DeltaT_per_terminal_hit_path_kg"].sum()),
            "weighted_DeltaI_kg_per_terminal_hit_path": float(pos_states["weighted_DeltaI_per_terminal_hit_path_kg"].sum()),
            "increment_realization_ratio": float(pos_states["weighted_DeltaI_per_terminal_hit_path_kg"].sum() / pos_states["weighted_DeltaT_per_terminal_hit_path_kg"].sum()),
            "interpretation": "Four-station state-total ratio, excluding states with DeltaT=0.",
        },
        {
            "scope": "raw_all_terminal_hit_path_total_association",
            "eligible_unit_count": len(saa_hit),
            "weighted_DeltaT_kg_per_terminal_hit_path": raw_delta_t,
            "weighted_DeltaI_kg_per_terminal_hit_path": raw_delta_i,
            "increment_realization_ratio": raw_delta_i / raw_delta_t,
            "interpretation": "Diagnostic raw ratio; numerator includes state7 paths where DeltaT=0, so it is not the strict increment realization ratio.",
        },
    ]
    return pd.DataFrame(rows)


def build_low_realization_ranking(state_summary: pd.DataFrame) -> pd.DataFrame:
    ranked = state_summary[(state_summary["DeltaT_total_kg"] > EPS) & state_summary["arrival_count"].gt(0)].copy()
    ranked["unrealized_increment_total_kg"] = ranked["DeltaT_total_kg"] - ranked["DeltaI_total_kg"]
    ranked["weighted_unrealized_mass"] = ranked["arrival_count"] * ranked["unrealized_increment_total_kg"]
    total = ranked["weighted_unrealized_mass"].sum()
    ranked["share_of_weighted_unrealized_increment"] = ranked["weighted_unrealized_mass"] / total
    ranked = ranked.sort_values(["weighted_unrealized_mass", "increment_realization_ratio_total"], ascending=[False, True]).reset_index(drop=True)
    ranked.insert(0, "weighted_unrealized_rank", np.arange(1, len(ranked) + 1))
    return ranked


def build_ordinary_worse_link(rowwise: pd.DataFrame, worse: pd.DataFrame, state_summary: pd.DataFrame) -> pd.DataFrame:
    saa = rowwise[rowwise["method"] == "saa"].sort_values("path_id")
    link = worse[["path_id"]].merge(saa[["path_id", "hit_terminal", "state_id"]], on="path_id", how="left", validate="one_to_one")
    rows = []
    for state_id in range(0, 36):
        count = int((link["state_id"] == state_id).sum())
        if state_id == 0:
            rows.append(
                {
                    "state_id": 0,
                    "category": "no_terminal_hit",
                    "ordinary_shortage_worse_count": count,
                    "share_of_all_280": count / 280.0,
                    "baseline_terminal_arrival_count": 3947,
                    "baseline_share_full_oos": 0.3947,
                    "ordinary_worse_probability_given_category": count / 3947.0,
                    "DeltaT_total_kg": np.nan,
                    "DeltaI_total_kg": np.nan,
                    "saa_mean_attainment": np.nan,
                    "dro_mean_attainment": np.nan,
                    "attainment_delta_dro_minus_saa": np.nan,
                    "increment_realization_ratio_total": np.nan,
                }
            )
            continue
        st = state_summary[state_summary["state_id"] == state_id].iloc[0]
        rows.append(
            {
                "state_id": state_id,
                "category": "terminal_state",
                "ordinary_shortage_worse_count": count,
                "share_of_all_280": count / 280.0,
                "baseline_terminal_arrival_count": int(st["arrival_count"]),
                "baseline_share_full_oos": float(st["arrival_frequency_full_oos"]),
                "ordinary_worse_probability_given_category": count / st["arrival_count"] if st["arrival_count"] else np.nan,
                "DeltaT_total_kg": float(st["DeltaT_total_kg"]),
                "DeltaI_total_kg": float(st["DeltaI_total_kg"]),
                "saa_mean_attainment": float(st["saa_mean_attainment"]),
                "dro_mean_attainment": float(st["dro_mean_attainment"]),
                "attainment_delta_dro_minus_saa": float(st["attainment_delta_dro_minus_saa"]),
                "increment_realization_ratio_total": float(st["increment_realization_ratio_total"]),
            }
        )
    return pd.DataFrame(rows).sort_values(["ordinary_shortage_worse_count", "state_id"], ascending=[False, True]).reset_index(drop=True)


def write_text_outputs(
    out_dir: Path,
    rowwise: pd.DataFrame,
    state_station: pd.DataFrame,
    incremental: pd.DataFrame,
    state_summary: pd.DataFrame,
    incremental_summary: pd.DataFrame,
    low_rank: pd.DataFrame,
    worse_link: pd.DataFrame,
    integrity: dict,
    source_paths: dict,
):
    saa_hit = rowwise[(rowwise["method"] == "saa") & rowwise["hit_terminal"].eq(1)]
    dro_hit = rowwise[(rowwise["method"] == "chi2_eta003") & rowwise["hit_terminal"].eq(1)]
    common_pos = state_summary[(state_summary["arrival_count"] > 0) & (state_summary["saa_target_total_kg"] > EPS) & (state_summary["dro_target_total_kg"] > EPS)]
    common_saa = weighted_mean(common_pos["saa_mean_attainment"], common_pos["arrival_count"])
    common_dro = weighted_mean(common_pos["dro_mean_attainment"], common_pos["arrival_count"])
    strict_cell = incremental_summary.iloc[0]
    strict_state = incremental_summary.iloc[1]
    raw = incremental_summary.iloc[2]
    top5_share = float(low_rank.head(5)["share_of_weighted_unrealized_increment"].sum())
    station_unreal = incremental[(incremental["increment_class"] == "positive_delta_target") & incremental["arrival_count"].gt(0)].copy()
    station_unreal["weighted_unrealized_mass"] = station_unreal["arrival_count"] * station_unreal["unrealized_increment_DeltaT_minus_DeltaI_kg"]
    station_rank = station_unreal.groupby("site", as_index=False).agg(weighted_DeltaT_mass=("weighted_DeltaT_per_terminal_hit_path_kg", "sum"), weighted_DeltaI_mass=("weighted_DeltaI_per_terminal_hit_path_kg", "sum"), weighted_unrealized_mass=("weighted_unrealized_mass", "sum"))
    station_rank["increment_realization_ratio"] = station_rank["weighted_DeltaI_mass"] / station_rank["weighted_DeltaT_mass"]
    station_rank["unrealized_share"] = station_rank["weighted_unrealized_mass"] / station_rank["weighted_unrealized_mass"].sum()
    worst_station = station_rank.sort_values("unrealized_share", ascending=False).iloc[0]
    worse_terminal = worse_link[worse_link["state_id"] > 0]
    top_worse = worse_terminal.sort_values("ordinary_shortage_worse_count", ascending=False).head(5)

    aggregation_text = f"""Step-05B-2 aggregation definition audit

Frozen sources
- Step-05B-1 accepted rowwise audit: {source_paths['step05b1_rowwise']}
- C6 SAA 35x4 table: {source_paths['c6_saa_table']}
- C6 eta=0.03 35x4 table: {source_paths['c6_eta003_table']}

Mechanical gates
- Row count: 20000 = 2 methods x 10000 common OOS paths.
- Common terminal-hit paths: {integrity['common_terminal_hits']}.
- Unreached frozen terminal states: {integrity['unreached_state_count']} of 35; their targets remain reported, while realized inventory/gap statistics are NaN.
- Four-station reconstruction max errors: target={integrity['target_sum_error']:.12g}, final={integrity['final_sum_error']:.12g}, gap={integrity['gap_sum_error']:.12g} kg.
- The Step-05B-1 ordinary-shortage-worse subset was reproduced exactly: 280 path IDs.

Units and aggregation
- station-level quantities are one station on one path, in kg.
- four-station total quantities are sums across T1..T4 or I1..I4 on one path, in kg.
- state_station_realization_table.csv has 35 states x 4 sites x 2 methods = 280 rows.
- equal-state summaries are descriptive only and are not probability expectations.
- OOS-weighted summaries use arrival_count/10000. Conditional terminal-hit summaries use arrival_count/6053.
- T=0 is labeled zero_target. Attainment and relative gap are undefined and are never divided by zero.
- DeltaT=0 and DeltaT<0 are not assigned an increment realization ratio. DeltaI is never clipped.

The earlier 98.12 versus 380.25 question
- SAA mean TerminalLOH target on 6053 terminal-hit paths = {saa_hit['target_total'].mean():.12f} kg.
- SAA mean final inventory on the same 6053 terminal-hit paths = {saa_hit['final_total'].mean():.12f} kg.
- Both numbers are four-station totals per terminal-hit path. They are not a per-station versus four-station unit mismatch.
- They are nevertheless not an attainment ratio: many reached SAA terminal states have zero TerminalLOH target, while final inventory remains physical inventory. Proper attainment is computed only for T>0 using min(I,T)/T.
- Eta corresponding values are target={dro_hit['target_total'].mean():.12f} kg and final={dro_hit['final_total'].mean():.12f} kg, also four-station totals.
"""
    (out_dir / "aggregation_definition_audit.txt").write_text(aggregation_text, encoding="utf-8")

    judgment = f"""Step-05B-2 judgment: D

SAA and eta=0.03 both show high own-target aggregate attainment, so the evidence does not support a global claim that the interface fails everywhere. On target-positive station-path cells, target-mass-weighted attainment is {1 - saa_hit[[f'gap_site{i}' for i in range(1,5)]].to_numpy()[saa_hit[[f'target_site{i}' for i in range(1,5)]].to_numpy() > EPS].sum() / saa_hit[[f'target_site{i}' for i in range(1,5)]].to_numpy()[saa_hit[[f'target_site{i}' for i in range(1,5)]].to_numpy() > EPS].sum():.6%} for SAA and {1 - dro_hit[[f'gap_site{i}' for i in range(1,5)]].to_numpy()[dro_hit[[f'target_site{i}' for i in range(1,5)]].to_numpy() > EPS].sum() / dro_hit[[f'target_site{i}' for i in range(1,5)]].to_numpy()[dro_hit[[f'target_site{i}' for i in range(1,5)]].to_numpy() > EPS].sum():.6%} for eta=0.03.

On the 24 reached states where both methods have a positive four-station target, however, OOS-frequency-weighted mean attainment falls from {common_saa:.6%} to {common_dro:.6%}. More importantly, the strict positive-DeltaT station-cell realization ratio is only {strict_cell['increment_realization_ratio']:.6%}; the positive-DeltaT state-total ratio is {strict_state['increment_realization_ratio']:.6%}. The raw all-terminal-hit ratio is {raw['increment_realization_ratio']:.6%}, but it is inflated by state7 paths where DeltaT=0 and final inventory still rises.

The non-realization is concentrated rather than uniform: the top five states contribute {top5_share:.6%} of OOS-weighted unrealized positive increment, and station {int(worst_station['site'])} contributes {float(worst_station['unrealized_share']):.6%}. Therefore the bounded conclusion is D: continue targeted production, HTT, inventory, capacity, and cut diagnostics for the dominant states/sites rather than globally changing TerminalLOH, 200/2000, or the MSP.

The 280 ordinary-shortage-worse paths contain {int(worse_link.loc[worse_link['state_id'].eq(0), 'ordinary_shortage_worse_count'].iloc[0])} non-terminal-hit paths and {int(worse_terminal['ordinary_shortage_worse_count'].sum())} terminal-hit paths. The five largest terminal-state counts are {', '.join('state%d=%d' % (int(r.state_id), int(r.ordinary_shortage_worse_count)) for _, r in top_worse.iterrows())}. This is a mechanism association only and does not establish Pearson DRO success or failure.
"""
    (out_dir / "step05b2_judgment.txt").write_text(judgment, encoding="utf-8")

    readme = f"""# Step-05B-2 TerminalLOH realization audit

Accepted result: `run-001`.

This is a read-only post-processing audit of the accepted Step-05B-1 common-sample path table and the frozen C6 35-state TerminalLOH tables. It does not retrain the MSP, call forward/backward/cut, change TerminalLOH, or change the 200/2000 penalties.

Key interpretation:

- `eta003` means eta = 0.03.
- All station and four-station total units are explicitly separated.
- The strict increment ratio is reported only where `DeltaT > 0`; zero and negative increments are retained as separate classes.
- Four frozen states were not reached by these 10000 OOS paths. Their realized metrics are intentionally `NaN`, not imputed.
- Final bounded judgment: **D**, with targeted follow-up recommended for the dominant low-realization states and sites.

See `aggregation_definition_audit.txt` for aggregation rules and `step05b2_judgment.txt` for the bounded conclusion.
"""
    (out_dir / "README.md").write_text(readme, encoding="utf-8")

    manifest_lines = [
        "# LARGE FILE MANIFEST",
        "",
        "No MAT, workspace, diary, complete OOS scenario file, or retraining output was copied into this run.",
        "",
        "| role | path | bytes | SHA-256 | policy |",
        "|---|---|---:|---|---|",
    ]
    for role, path in source_paths.items():
        manifest_lines.append(f"| {role} | `{path}` | {path.stat().st_size} | `{sha256_file(path)}` | protected read-only source, not copied |")
    for path in sorted(out_dir.glob("*")):
        if path.is_file() and path.name != "LARGE_FILE_MANIFEST.md":
            manifest_lines.append(f"| audit output | `{path.name}` | {path.stat().st_size} | `{sha256_file(path)}` | lightweight local result |")
    (out_dir / "LARGE_FILE_MANIFEST.md").write_text("\n".join(manifest_lines) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-id", default="run-001")
    args = parser.parse_args()

    repo = Path(__file__).resolve().parents[2]
    out_dir = repo / "results/task-002-stage2b-b3-smoke/59-terminal-loh-realization-audit" / args.run_id
    out_dir.mkdir(parents=True, exist_ok=False)

    rowwise, worse, saa_table, dro_table, integrity, source_paths = load_and_validate_inputs(repo)
    state_station = build_state_station_table(rowwise, saa_table, dro_table)
    incremental = build_incremental_table(state_station)
    state_summary = build_state_summary(rowwise, incremental, worse)
    saa_summary = method_summary("saa", rowwise, state_station, state_summary)
    dro_summary = method_summary("chi2_eta003", rowwise, state_station, state_summary)
    incremental_summary = build_incremental_summary(incremental, state_summary, rowwise)
    low_rank = build_low_realization_ranking(state_summary)
    worse_link = build_ordinary_worse_link(rowwise, worse, state_summary)
    special = state_summary[state_summary["state_id"].isin([7, 13, 19])].copy()

    state_station.to_csv(out_dir / "state_station_realization_table.csv", index=False, float_format="%.15g")
    saa_summary.to_csv(out_dir / "saa_attainment_summary.csv", index=False, float_format="%.15g")
    dro_summary.to_csv(out_dir / "dro_attainment_summary.csv", index=False, float_format="%.15g")
    incremental.to_csv(out_dir / "incremental_realization_table.csv", index=False, float_format="%.15g")
    incremental_summary.to_csv(out_dir / "incremental_realization_summary.csv", index=False, float_format="%.15g")
    state_summary.to_csv(out_dir / "terminal_state_weighted_summary.csv", index=False, float_format="%.15g")
    low_rank.to_csv(out_dir / "low_realization_state_ranking.csv", index=False, float_format="%.15g")
    worse_link.to_csv(out_dir / "ordinary_shortage_280_state_link.csv", index=False, float_format="%.15g")
    special.to_csv(out_dir / "state7_state13_state19_check.csv", index=False, float_format="%.15g")

    write_text_outputs(
        out_dir,
        rowwise,
        state_station,
        incremental,
        state_summary,
        incremental_summary,
        low_rank,
        worse_link,
        integrity,
        source_paths,
    )
    print(f"Step-05B-2 audit completed: {out_dir}")


if __name__ == "__main__":
    main()
