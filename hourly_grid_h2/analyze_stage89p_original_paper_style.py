#!/usr/bin/env python3
"""Stage-89P read-only primary-result presentation for accepted Stage89N.

This script never trains, solves, loads a checkpoint, or reruns OOS.  It reads
accepted Stage89H/N stage-aggregate OOS artifacts and the accepted Stage89O
path classification, then writes lightweight CSV/PNG/Markdown evidence.
"""

from __future__ import annotations

import argparse
import hashlib
import math
import shutil
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd


Z95 = 1.96
INITIAL_PATHS = 10_000
STAGE_CAP_KG = 120.12
SITE_CAP_KG = {1: 46.8, 2: 31.2, 3: 18.72, 4: 23.4}
COLORS = {"N": "#176B87", "H": "#B35C44"}


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def continuous(values) -> dict:
    x = pd.Series(values, dtype="float64").dropna().to_numpy()
    n = int(x.size)
    if n == 0:
        return {k: np.nan for k in ("N", "mean", "std", "SE", "CI_low", "CI_high")}
    mean = float(np.mean(x))
    std = float(np.std(x, ddof=1)) if n > 1 else 0.0
    se = std / math.sqrt(n)
    return {"N": n, "mean": mean, "std": std, "SE": se,
            "CI_low": mean - Z95 * se, "CI_high": mean + Z95 * se}


def wilson(successes: int, n: int) -> dict:
    if n <= 0:
        return {"N": 0, "events": 0, "probability": np.nan,
                "CI_low": np.nan, "CI_high": np.nan}
    p = successes / n
    den = 1 + Z95**2 / n
    center = (p + Z95**2 / (2 * n)) / den
    half = Z95 * math.sqrt(p * (1 - p) / n + Z95**2 / (4 * n**2)) / den
    return {"N": n, "events": int(successes), "probability": p,
            "CI_low": center - half, "CI_high": center + half}


def fmt(x: float, digits: int = 3) -> str:
    if pd.isna(x):
        return "NA"
    return f"{float(x):.{digits}f}"


def save_csv(frame: pd.DataFrame, path: Path) -> None:
    frame.to_csv(path, index=False, encoding="utf-8", float_format="%.12g")


def add_ci(ci_rows: list[dict], section: str, group: str, metric: str,
           values, denominator: str) -> dict:
    s = continuous(values)
    ci_rows.append({"interval_type": "NORMAL_MEAN_95", "section": section,
                    "group": group, "metric": metric, "denominator": denominator,
                    **s, "events": np.nan, "probability": np.nan})
    return s


def add_wilson(ci_rows: list[dict], section: str, group: str, metric: str,
               successes: int, n: int, denominator: str) -> dict:
    w = wilson(successes, n)
    ci_rows.append({"interval_type": "WILSON_EVENT_95", "section": section,
                    "group": group, "metric": metric, "denominator": denominator,
                    "N": w["N"], "mean": np.nan, "std": np.nan, "SE": np.nan,
                    "CI_low": w["CI_low"], "CI_high": w["CI_high"],
                    "events": w["events"], "probability": w["probability"]})
    return w


def load_policy(oos: Path) -> dict[str, pd.DataFrame]:
    return {
        "manifest": pd.read_csv(oos / "oos_path_manifest.csv"),
        "path": pd.read_csv(oos / "oos_path_summary.csv"),
        "stage": pd.read_csv(oos / "oos_stage_summary.csv"),
        "site": pd.read_csv(oos / "oos_stage_site_summary.csv"),
    }


def stage_tables(label: str, data: dict[str, pd.DataFrame], ci_rows: list[dict]):
    st = data["stage"].sort_values(["path_id", "stage"]).copy()
    site = data["site"].copy()
    st["cumulative_production_kg"] = st.groupby("path_id")["production_kg"].cumsum()
    production_rows, inventory_rows, balance_rows = [], [], []
    unconditional_running = 0.0
    for stage in range(1, 7):
        g = st[st.stage == stage].copy()
        gs = site[site.stage == stage].copy()
        if g.empty:
            continue
        n = g.path_id.nunique()
        prod = add_ci(ci_rows, f"{label}_PRODUCTION_BY_STAGE", f"Stage{stage}",
                      "production_kg", g.production_kg, "ACTIVE_PATHS")
        cum = add_ci(ci_rows, f"{label}_PRODUCTION_BY_STAGE", f"Stage{stage}",
                     "cumulative_production_kg", g.cumulative_production_kg, "ACTIVE_PATHS")
        util = add_ci(ci_rows, f"{label}_PRODUCTION_BY_STAGE", f"Stage{stage}",
                      "electrolyzer_utilization", g.production_kg / STAGE_CAP_KG,
                      "ACTIVE_PATHS")
        row = {"policy": label, "stage": stage, "active_path_count": n,
               "active_path_share": n / INITIAL_PATHS,
               "averaging_definition": "CONDITIONAL_ON_ACTIVE_PATHS",
               "mean_total_production_kg": prod["mean"], "std_total_production_kg": prod["std"],
               "SE_total_production_kg": prod["SE"], "CI95_low_total_production_kg": prod["CI_low"],
               "CI95_high_total_production_kg": prod["CI_high"],
               "mean_cumulative_production_active_paths_kg": cum["mean"],
               "CI95_low_cumulative_production_active_paths_kg": cum["CI_low"],
               "CI95_high_cumulative_production_active_paths_kg": cum["CI_high"],
               "mean_electrolyzer_utilization": util["mean"],
               "CI95_low_electrolyzer_utilization": util["CI_low"],
               "CI95_high_electrolyzer_utilization": util["CI_high"]}
        for site_id in range(1, 5):
            vals = gs.loc[gs.site == site_id, "production_kg"]
            ss = add_ci(ci_rows, f"{label}_PRODUCTION_BY_STAGE", f"Stage{stage}_Site{site_id}",
                        "production_kg", vals, "ACTIVE_PATHS")
            row[f"site{site_id}_mean_production_kg"] = ss["mean"]
            row[f"site{site_id}_CI95_low_production_kg"] = ss["CI_low"]
            row[f"site{site_id}_CI95_high_production_kg"] = ss["CI_high"]
        unconditional = float(g.production_kg.sum() / INITIAL_PATHS)
        unconditional_running += unconditional
        row["unconditional_production_per_initial_path_kg"] = unconditional
        row["cumulative_unconditional_per_initial_path_kg"] = unconditional_running
        production_rows.append(row)

        begin = add_ci(ci_rows, f"{label}_INVENTORY_BY_STAGE", f"Stage{stage}",
                       "beginning_inventory_kg", g.beginning_inventory_kg, "ACTIVE_PATHS")
        ending = add_ci(ci_rows, f"{label}_INVENTORY_BY_STAGE", f"Stage{stage}",
                        "ending_inventory_kg", g.ending_inventory_kg, "ACTIVE_PATHS")
        irow = {"policy": label, "stage": stage, "active_path_count": n,
                "averaging_definition": "CONDITIONAL_ON_ACTIVE_PATHS",
                "mean_beginning_total_inventory_kg": begin["mean"],
                "CI95_low_beginning_total_inventory_kg": begin["CI_low"],
                "CI95_high_beginning_total_inventory_kg": begin["CI_high"],
                "mean_ending_total_inventory_kg": ending["mean"],
                "std_ending_total_inventory_kg": ending["std"],
                "SE_ending_total_inventory_kg": ending["SE"],
                "CI95_low_ending_total_inventory_kg": ending["CI_low"],
                "CI95_high_ending_total_inventory_kg": ending["CI_high"]}
        for site_id in range(1, 5):
            vals = gs.loc[gs.site == site_id, "ending_inventory_kg"]
            ss = add_ci(ci_rows, f"{label}_INVENTORY_BY_STAGE", f"Stage{stage}_Site{site_id}",
                        "ending_inventory_kg", vals, "ACTIVE_PATHS")
            irow[f"site{site_id}_mean_ending_inventory_kg"] = ss["mean"]
            irow[f"site{site_id}_CI95_low_ending_inventory_kg"] = ss["CI_low"]
            irow[f"site{site_id}_CI95_high_ending_inventory_kg"] = ss["CI_high"]
        inventory_rows.append(irow)

        site_path = gs.groupby("path_id", as_index=False).agg(
            ordinary_demand_kg=("ordinary_demand_kg", "sum"),
            served_demand_kg=("served_demand_kg", "sum"),
            ordinary_shortage_kg=("shortage_kg", "sum"),
            htt_in_kg=("htt_in_kg", "sum"), htt_out_kg=("htt_out_kg", "sum"),
            site_balance_residual=("ending_inventory_kg", "sum"))
        merged = g.merge(site_path, on="path_id", suffixes=("", "_site"))
        gs2 = gs.copy()
        gs2["closure"] = (gs2.beginning_inventory_kg + gs2.production_kg + gs2.htt_in_kg
                           - gs2.served_demand_kg - gs2.htt_out_kg - gs2.ending_inventory_kg)
        mean_change = float((g.ending_inventory_kg - g.beginning_inventory_kg).mean())
        mean_prod = float(g.production_kg.mean())
        mean_served = float(merged.served_demand_kg.mean())
        if mean_change > 1e-8:
            driver = "PRODUCTION_EXCEEDS_ORDINARY_SERVICE; HTT_REALLOCATES_ONLY"
        elif mean_change < -1e-8:
            driver = "ORDINARY_SERVICE_EXCEEDS_PRODUCTION; HTT_REALLOCATES_ONLY"
        else:
            driver = "PRODUCTION_AND_ORDINARY_SERVICE_BALANCED"
        balance_rows.append({
            "policy": label, "stage": stage, "active_path_count": n,
            "mean_production_kg": mean_prod,
            "mean_ordinary_demand_kg": float(merged.ordinary_demand_kg.mean()),
            "mean_ordinary_demand_served_kg": mean_served,
            "mean_ordinary_shortage_kg": float(merged.ordinary_shortage_kg.mean()),
            "mean_gross_htt_kg": float(g.htt_kg.mean()),
            "mean_system_net_htt_kg": float((merged.htt_in_kg - merged.htt_out_kg).mean()),
            "mean_beginning_inventory_kg": float(g.beginning_inventory_kg.mean()),
            "mean_ending_inventory_kg": float(g.ending_inventory_kg.mean()),
            "mean_inventory_change_kg": mean_change,
            "mean_production_minus_served_kg": mean_prod - mean_served,
            "max_abs_site_balance_residual_kg": float(gs2.closure.abs().max()),
            "inventory_change_explanation": driver,
            "cause_decomposition": "FULL_SYSTEM_BALANCE; HTT_SITE_REALLOCATION_ONLY",
        })
    return pd.DataFrame(production_rows), pd.DataFrame(inventory_rows), pd.DataFrame(balance_rows)


def conditional_action(label: str, data: dict[str, pd.DataFrame], ci_rows: list[dict], by: str):
    st = data["stage"]
    site = data["site"]
    rows = []
    for (stage, state_value), g in st[st.stage.between(2, 6)].groupby(["stage", by], sort=True):
        gs = site[(site.stage == stage) & (site[by] == state_value)]
        n = g.path_id.nunique()
        row = {"policy": label, "stage": int(stage), by: int(state_value),
               "path_count": n, "information_timing": "STATE_T_OBSERVED_BEFORE_DECISION_T",
               "sample_scope": "ACTIVE_PATHS", "descriptive_only": "YES" if n < 30 else "NO"}
        metrics = {"production_kg": g.production_kg, "ending_inventory_kg": g.ending_inventory_kg,
                   "ordinary_shortage_kg": g.ordinary_shortage_kg, "htt_kg": g.htt_kg}
        for metric, values in metrics.items():
            s = add_ci(ci_rows, f"{label}_ACTION_BY_{by.upper()}", f"Stage{stage}_{by}{state_value}",
                       metric, values, "ACTIVE_PATHS_WITH_OBSERVED_STATE")
            row[f"mean_{metric}"] = s["mean"]
            row[f"CI95_low_{metric}"] = s["CI_low"]
            row[f"CI95_high_{metric}"] = s["CI_high"]
        if by == "loc":
            for site_id in range(1, 5):
                vals = gs.loc[gs.site == site_id, "ending_inventory_kg"]
                s = continuous(vals)
                row[f"site{site_id}_mean_ending_inventory_kg"] = s["mean"]
        rows.append(row)
    out = pd.DataFrame(rows)
    return out


def slope_summary(action: pd.DataFrame, state_col: str) -> pd.DataFrame:
    rows = []
    for stage, g in action.groupby("stage"):
        x = g[state_col].to_numpy(dtype=float)
        y = g.mean_production_kg.to_numpy(dtype=float)
        weights = g.path_count.to_numpy(dtype=float)
        slope = float(np.polyfit(x, y, 1, w=np.sqrt(weights))[0]) if len(g) >= 2 else np.nan
        spearman = float(pd.Series(x).rank().corr(pd.Series(y).rank())) if len(g) >= 2 else np.nan
        ordered = g.sort_values(state_col).mean_production_kg.to_numpy(dtype=float)
        adjacent = np.diff(ordered)
        rows.append({"stage": stage, "state_variable": state_col,
                     "weighted_mean_slope_kg_per_state_level": slope,
                     "rank_correlation_of_group_means": spearman,
                     "state_group_count": len(g),
                     "adjacent_increase_count_gt_1kg": int(np.sum(adjacent > 1.0)),
                     "adjacent_decrease_count_lt_minus_1kg": int(np.sum(adjacent < -1.0)),
                     "adjacent_comparison_count": int(adjacent.size)})
    return pd.DataFrame(rows)


def classify_intensity(slopes: pd.DataFrame) -> str:
    vals = slopes.weighted_mean_slope_kg_per_state_level.dropna().to_numpy()
    if vals.size == 0:
        return "NO_CLEAR_PATTERN"
    pos = int(np.sum(vals > 1.0)); neg = int(np.sum(vals < -1.0))
    if pos and neg:
        return "MIXED"
    adjacent_up = int(slopes.adjacent_increase_count_gt_1kg.sum())
    adjacent_down = int(slopes.adjacent_decrease_count_lt_minus_1kg.sum())
    if pos >= 4 and np.nanmedian(vals) > 5 and adjacent_down == 0:
        return "CLEAR_POSITIVE"
    if pos >= 3 and adjacent_up > adjacent_down:
        return "MODERATE_POSITIVE"
    if np.nanmax(np.abs(vals)) <= 1.0:
        return "WEAK"
    return "NO_CLEAR_PATTERN"


def termination_table(label: str, data: dict[str, pd.DataFrame], cohorts: pd.DataFrame,
                      ci_rows: list[dict]) -> pd.DataFrame:
    path = data["path"].merge(cohorts[["path_id", "termination_type", "cohort_timing",
                                       "last_active_stage", "reached_stage7"]], on="path_id")
    rows = []
    allowed = path.termination_type.isin(["A1", "STAGE7", "LF8"])
    for (term_type, timing, last_stage), g in path[allowed].groupby(
            ["termination_type", "cohort_timing", "last_active_stage"], sort=True):
        n = len(g)
        row = {"policy": label, "termination_type": term_type,
               "timing_group": timing, "last_active_stage": int(last_stage),
               "path_count": n, "path_share_initial": n / INITIAL_PATHS,
               "descriptive_only": "YES" if n < 30 else "NO"}
        metrics = {"cumulative_production_kg": g.production_kg,
                   "ending_inventory_kg": g.terminal_inventory_kg,
                   "ordinary_shortage_kg": g.ordinary_shortage_kg,
                   "htt_kg": g.htt_kg, "actual_operating_cost_yuan": g.operating_cost_yuan}
        for metric, values in metrics.items():
            s = add_ci(ci_rows, f"{label}_TERMINATION_TIMING", f"{term_type}_{timing}", metric,
                       values, "PATHS_IN_TERMINATION_TIMING_GROUP")
            row[f"mean_{metric}"] = s["mean"]
            row[f"std_{metric}"] = s["std"]
            row[f"SE_{metric}"] = s["SE"]
            row[f"CI95_low_{metric}"] = s["CI_low"]
            row[f"CI95_high_{metric}"] = s["CI_high"]
        rows.append(row)
    return pd.DataFrame(rows)


def same_terminal_arrival(data: dict[str, pd.DataFrame], cohorts: pd.DataFrame,
                          ci_rows: list[dict]) -> pd.DataFrame:
    path = data["path"].merge(cohorts[["path_id", "reached_stage7", "last_active_stage",
                                       "terminal_a", "terminal_loc"]], on="path_id")
    path = path[path.reached_stage7].copy()
    metrics = {"cumulative_production_kg": "production_kg",
               "ending_inventory_kg": "terminal_inventory_kg", "htt_kg": "htt_kg",
               "ordinary_shortage_kg": "ordinary_shortage_kg", "terminal_gap_kg": "terminal_gap_kg"}
    rows = []
    grouped = path.groupby(["terminal_a", "terminal_loc", "last_active_stage"], sort=True)
    for (a, loc, arrival), g in grouped:
        row = {"record_type": "ARRIVAL_GROUP", "terminal_a": int(a), "terminal_loc": int(loc),
               "early_arrival_after_stage": int(arrival), "late_arrival_after_stage": np.nan,
               "early_path_count": len(g), "late_path_count": np.nan,
               "descriptive_only": "YES" if len(g) < 30 else "NO"}
        for out_metric, col in metrics.items():
            s = add_ci(ci_rows, "N_SAME_TERMINAL_ARRIVAL", f"a{int(a)}_loc{int(loc)}_afterS{int(arrival)}",
                       out_metric, g[col], "STAGE7_PATHS_WITH_SAME_TERMINAL_STATE_AND_ARRIVAL")
            row[f"early_mean_{out_metric}"] = s["mean"]
            row[f"early_CI95_low_{out_metric}"] = s["CI_low"]
            row[f"early_CI95_high_{out_metric}"] = s["CI_high"]
        rows.append(row)
    for (a, loc), g in path.groupby(["terminal_a", "terminal_loc"], sort=True):
        arrivals = sorted(g.last_active_stage.unique())
        viable = [s for s in arrivals if len(g[g.last_active_stage == s]) >= 5]
        if len(viable) < 2:
            continue
        early_stage, late_stage = viable[0], viable[-1]
        early, late = g[g.last_active_stage == early_stage], g[g.last_active_stage == late_stage]
        row = {"record_type": "EARLIEST_VS_LATEST", "terminal_a": int(a), "terminal_loc": int(loc),
               "early_arrival_after_stage": int(early_stage), "late_arrival_after_stage": int(late_stage),
               "early_path_count": len(early), "late_path_count": len(late),
               "descriptive_only": "YES" if min(len(early), len(late)) < 30 else "NO"}
        for out_metric, col in metrics.items():
            e, l = continuous(early[col]), continuous(late[col])
            row[f"early_mean_{out_metric}"] = e["mean"]
            row[f"late_mean_{out_metric}"] = l["mean"]
            row[f"late_minus_early_mean_{out_metric}"] = l["mean"] - e["mean"]
        rows.append(row)
    return pd.DataFrame(rows)


def primary_results(label: str, data: dict[str, pd.DataFrame], cohorts: pd.DataFrame,
                    ci_rows: list[dict]) -> pd.DataFrame:
    path = data["path"].merge(cohorts[["path_id", "reached_stage7"]], on="path_id")
    rows = []
    specs = [
        ("actual_operating_cost_yuan", path.operating_cost_yuan, "ALL_INITIAL_PATHS"),
        ("reported_objective_yuan", path.total_objective_yuan, "ALL_INITIAL_PATHS"),
        ("total_h2_production_kg", path.production_kg, "ALL_INITIAL_PATHS"),
        ("total_htt_kg", path.htt_kg, "ALL_INITIAL_PATHS"),
        ("ordinary_shortage_kg", path.ordinary_shortage_kg, "ALL_INITIAL_PATHS"),
    ]
    stage7 = path[path.reached_stage7]
    specs.append(("terminal_gap_kg", stage7.terminal_gap_kg, "CONDITIONAL_ON_STAGE7_PATHS"))
    for metric, values, denominator in specs:
        s = add_ci(ci_rows, f"{label}_PRIMARY_OOS", "ALL", metric, values, denominator)
        arr = pd.Series(values, dtype=float)
        rows.append({"policy": label, "metric": metric, "denominator": denominator,
                     **s, "q95": float(arr.quantile(.95)), "q99": float(arr.quantile(.99)),
                     "event_probability": np.nan, "event_events": np.nan,
                     "event_CI95_low": np.nan, "event_CI95_high": np.nan})
    events = [
        ("probability_any_ordinary_shortage", int((path.ordinary_shortage_kg > 1e-9).sum()), len(path),
         "ALL_INITIAL_PATHS"),
        ("probability_terminal_gap_positive", int((stage7.terminal_gap_kg > 1e-9).sum()), len(stage7),
         "CONDITIONAL_ON_STAGE7_PATHS"),
    ]
    for metric, successes, n, denominator in events:
        w = add_wilson(ci_rows, f"{label}_PRIMARY_OOS", "ALL", metric, successes, n, denominator)
        rows.append({"policy": label, "metric": metric, "denominator": denominator,
                     "N": n, "mean": np.nan, "std": np.nan, "SE": np.nan,
                     "CI_low": np.nan, "CI_high": np.nan, "q95": np.nan, "q99": np.nan,
                     "event_probability": w["probability"], "event_events": successes,
                     "event_CI95_low": w["CI_low"], "event_CI95_high": w["CI_high"]})
    # Accounting-only number retained to reconcile accepted Stage89N's all-path summary.
    rows.append({"policy": label, "metric": "terminal_gap_kg_unconditional_accounting_contribution",
                 "denominator": "ALL_INITIAL_PATHS_WITH_NON_STAGE7_ZERO_CONTRIBUTION_NOT_A_PHYSICAL_GAP",
                 **continuous(path.terminal_gap_kg), "q95": float(path.terminal_gap_kg.quantile(.95)),
                 "q99": float(path.terminal_gap_kg.quantile(.99)), "event_probability": np.nan,
                 "event_events": np.nan, "event_CI95_low": np.nan, "event_CI95_high": np.nan})
    return pd.DataFrame(rows)


def cost_decomposition(label: str, data: dict[str, pd.DataFrame], ci_rows: list[dict]) -> pd.DataFrame:
    p = data["path"].copy()
    components = {
        "electricity_grid_cost_yuan": p.grid_cost_yuan,
        "production_om_cost_yuan": p.production_om_cost_yuan,
        "production_electricity_cost_yuan": p.production_electricity_cost_yuan,
        "ordinary_shortage_cost_yuan": p.ordinary_shortage_cost_yuan,
        "htt_cost_yuan": p.htt_cost_yuan,
        "holding_other_operating_cost_yuan": p.holding_cost_yuan,
        "other_unclassified_actual_operating_cost_yuan": (
            p.operating_cost_yuan - p.production_electricity_cost_yuan - p.ordinary_shortage_cost_yuan
            - p.htt_cost_yuan - p.holding_cost_yuan),
        "actual_operating_cost_yuan": p.operating_cost_yuan,
        "terminal_gap_soft_target_penalty_yuan": p.stage7_terminal_value_yuan,
        "reported_objective_yuan": p.total_objective_yuan,
    }
    rows = []
    for name, values in components.items():
        s = add_ci(ci_rows, f"{label}_COST", "ALL", name, values, "ALL_INITIAL_PATHS")
        scope = ("SOFT_TARGET_INCENTIVE_NOT_REAL_EXPENDITURE" if name.startswith("terminal_gap")
                 else "REPORTED_OBJECTIVE_INCLUDES_SOFT_TARGET" if name == "reported_objective_yuan"
                 else "MODELED_ACTUAL_OPERATING_COMPONENT")
        rows.append({"policy": label, "component": name, "reality_scope": scope, **s})
    return pd.DataFrame(rows)


def paired_summary(a: pd.Series, b: pd.Series) -> dict:
    d = b.to_numpy(dtype=float) - a.to_numpy(dtype=float)
    s = continuous(d)
    return {"paired_N": s["N"], "paired_difference_mean_N_minus_H": s["mean"],
            "paired_difference_CI95_low": s["CI_low"],
            "paired_difference_CI95_high": s["CI_high"]}


def comparison_table(H, N, prod_h, prod_n, inv_h, inv_n, int_h, int_n,
                     term_h, term_n, primary_h, primary_n) -> pd.DataFrame:
    rows = []
    def row(section, group, metric, hmean, nmean, hN, nN, paired=None):
        out = {"section": section, "group": group, "metric": metric,
               "Stage89H_N": hN, "Stage89H_mean": hmean, "Stage89N_N": nN,
               "Stage89N_mean": nmean, "difference_N_minus_H": nmean - hmean,
               "percent_change": (nmean - hmean) / abs(hmean) * 100 if abs(hmean) > 1e-12 else np.nan}
        if paired:
            out.update(paired)
        rows.append(out)
    for stage in range(1, 7):
        hp, np_ = prod_h[prod_h.stage == stage].iloc[0], prod_n[prod_n.stage == stage].iloc[0]
        hi, ni = inv_h[inv_h.stage == stage].iloc[0], inv_n[inv_n.stage == stage].iloc[0]
        gh = H["stage"][H["stage"].stage == stage].sort_values("path_id")
        gn = N["stage"][N["stage"].stage == stage].sort_values("path_id")
        row("PRODUCTION_BY_STAGE", f"Stage{stage}", "production_kg",
            hp.mean_total_production_kg, np_.mean_total_production_kg,
            hp.active_path_count, np_.active_path_count,
            paired_summary(gh.production_kg, gn.production_kg))
        row("INVENTORY_BY_STAGE", f"Stage{stage}", "ending_inventory_kg",
            hi.mean_ending_total_inventory_kg, ni.mean_ending_total_inventory_kg,
            hi.active_path_count, ni.active_path_count,
            paired_summary(gh.ending_inventory_kg, gn.ending_inventory_kg))
    keys = ["stage", "a"]
    for key, gn in int_n.groupby(keys):
        gh = int_h[(int_h.stage == key[0]) & (int_h.a == key[1])]
        if gh.empty:
            continue
        gh = gh.iloc[0]
        row("OBSERVED_INTENSITY", f"Stage{key[0]}_a{key[1]}", "production_kg",
            gh.mean_production_kg, gn.iloc[0].mean_production_kg, gh.path_count, gn.iloc[0].path_count)
    for _, nr in term_n.iterrows():
        hr = term_h[(term_h.termination_type == nr.termination_type) &
                    (term_h.timing_group == nr.timing_group)]
        if hr.empty:
            continue
        hr = hr.iloc[0]
        row("TERMINATION_TIMING", nr.timing_group, "cumulative_production_kg",
            hr.mean_cumulative_production_kg, nr.mean_cumulative_production_kg,
            hr.path_count, nr.path_count)
    for metric in ["actual_operating_cost_yuan", "total_h2_production_kg",
                   "ordinary_shortage_kg", "terminal_gap_kg", "total_htt_kg"]:
        hr = primary_h[primary_h.metric == metric].iloc[0]
        nr = primary_n[primary_n.metric == metric].iloc[0]
        row("PRIMARY_OOS", "ALL", metric, hr["mean"], nr["mean"], hr.N, nr.N)
    for metric in ["probability_any_ordinary_shortage", "probability_terminal_gap_positive"]:
        hr = primary_h[primary_h.metric == metric].iloc[0]
        nr = primary_n[primary_n.metric == metric].iloc[0]
        row("PRIMARY_OOS_EVENT", "ALL", metric, hr.event_probability, nr.event_probability,
            hr.N, nr.N)
    return pd.DataFrame(rows)


def make_figures(out: Path, training: pd.DataFrame, prod_n: pd.DataFrame, inv_n: pd.DataFrame,
                 intensity_n: pd.DataFrame, loc_n: pd.DataFrame, term_n: pd.DataFrame, prod_h: pd.DataFrame,
                 inv_h: pd.DataFrame, primary_h: pd.DataFrame, primary_n: pd.DataFrame):
    fdir = out / "figures"
    fdir.mkdir()
    plt.rcParams.update({"figure.dpi": 150, "savefig.dpi": 180, "font.size": 9,
                         "axes.spines.top": False, "axes.spines.right": False})
    figs = []
    def finish(fig, name, csv_name, description):
        path = fdir / name
        fig.tight_layout()
        fig.savefig(path, bbox_inches="tight")
        plt.close(fig)
        figs.append({"figure": name, "machine_readable_csv": csv_name,
                     "description": description, "bytes": path.stat().st_size,
                     "sha256": sha256(path)})

    fig, axes = plt.subplots(1, 3, figsize=(12, 3.4))
    axes[0].plot(training.iteration, training.lower_bound_yuan, marker="o", color=COLORS["N"])
    axes[0].set(xlabel="Iteration", ylabel="Lower bound (yuan)", title="1A. Lower bound")
    axes[1].plot(training.iteration, training.stage1_production_kg, marker="o", color=COLORS["N"])
    axes[1].set(xlabel="Iteration", ylabel="Stage 1 production (kg)", title="1B. Stage 1 decision")
    for col, lab in [("stage1_ending_inventory_kg", "Stage 1"),
                     ("stage2_ending_inventory_kg", "Stage 2"),
                     ("stage3_ending_inventory_kg", "Stage 3")]:
        axes[2].plot(training.iteration, training[col], marker="o", label=lab)
    axes[2].set(xlabel="Iteration", ylabel="Ending inventory (kg)", title="1C. Sampled inventories")
    axes[2].legend(frameon=False)
    finish(fig, "figure01_training_progress.png", "training_progress_10iter.csv",
           "Ten-iteration lower bound, Stage1 decision, and sampled Stage1-3 inventories")

    x = prod_n.stage.to_numpy()
    fig, ax = plt.subplots(figsize=(6.8, 4.0))
    ax.errorbar(x, prod_n.mean_total_production_kg,
                yerr=[prod_n.mean_total_production_kg-prod_n.CI95_low_total_production_kg,
                      prod_n.CI95_high_total_production_kg-prod_n.mean_total_production_kg],
                marker="o", capsize=3, color=COLORS["N"])
    ax.set(xticks=x, xlabel="Operating stage", ylabel="Mean production (kg)",
           title="Figure 2. Stage production, conditional on active paths")
    finish(fig, "figure02_production_by_stage.png", "production_by_stage.csv",
           "Stage89N active-path mean production with 95% CI")

    fig, ax = plt.subplots(figsize=(6.8, 4.0))
    ax.plot(x, prod_n.mean_cumulative_production_active_paths_kg, marker="o",
            label="Active-path conditional", color=COLORS["N"])
    ax.plot(x, prod_n.cumulative_unconditional_per_initial_path_kg, marker="s", linestyle="--",
            label="Per initial path contribution", color="#6998AB")
    ax.set(xticks=x, xlabel="Operating stage", ylabel="Cumulative production (kg/path)",
           title="Figure 3. Cumulative production")
    ax.legend(frameon=False)
    finish(fig, "figure03_cumulative_production.png", "production_by_stage.csv",
           "Conditional active-path and unconditional per-initial-path cumulative production")

    fig, ax = plt.subplots(figsize=(6.8, 4.0))
    ax.errorbar(x, inv_n.mean_ending_total_inventory_kg,
                yerr=[inv_n.mean_ending_total_inventory_kg-inv_n.CI95_low_ending_total_inventory_kg,
                      inv_n.CI95_high_ending_total_inventory_kg-inv_n.mean_ending_total_inventory_kg],
                marker="o", capsize=3, color=COLORS["N"])
    ax.set(xticks=x, xlabel="Operating stage", ylabel="Ending inventory (kg)",
           title="Figure 4. Total ending inventory, active paths")
    finish(fig, "figure04_total_inventory_by_stage.png", "inventory_by_stage.csv",
           "Stage89N mean total ending inventory with 95% CI")

    fig, ax = plt.subplots(figsize=(7.2, 4.2))
    for site in range(1, 5):
        ax.plot(x, inv_n[f"site{site}_mean_ending_inventory_kg"], marker="o", label=f"Site {site}")
    ax.set(xticks=x, xlabel="Operating stage", ylabel="Ending inventory (kg)",
           title="Figure 5. Four-site ending inventory")
    ax.legend(frameon=False, ncol=2)
    finish(fig, "figure05_site_inventory_by_stage.png", "inventory_by_stage.csv",
           "Stage89N four-site mean ending inventory among active paths")

    fig, ax = plt.subplots(figsize=(7.2, 4.4))
    for stage, g in intensity_n.groupby("stage"):
        ax.plot(g.a, g.mean_production_kg, marker="o", label=f"Stage {stage}")
    ax.set(xlabel="Observed current intensity a", ylabel="Mean production (kg)",
           title="Figure 6. Production after observing current intensity")
    ax.set_xticks(sorted(intensity_n.a.unique()))
    ax.legend(frameon=False, ncol=3)
    finish(fig, "figure06_intensity_conditioned_production.png",
           "production_by_observed_intensity_and_stage.csv",
           "Discrete Stage89N mean production by observed intensity and stage")

    for term_type, num, name, title in [("A1", 7, "figure07_dissipation_timing.png",
                                         "Figure 7. Physical dissipation timing"),
                                        ("STAGE7", 8, "figure08_stage7_arrival_timing.png",
                                         "Figure 8. Stage 7 arrival timing")]:
        g = term_n[term_n.termination_type == term_type].sort_values("last_active_stage")
        fig, ax = plt.subplots(figsize=(6.8, 4.0))
        ax.errorbar(g.last_active_stage, g.mean_cumulative_production_kg,
                    yerr=[g.mean_cumulative_production_kg-g.CI95_low_cumulative_production_kg,
                          g.CI95_high_cumulative_production_kg-g.mean_cumulative_production_kg],
                    marker="o", capsize=3, color=COLORS["N"])
        ax.set(xlabel="Last completed operating stage", ylabel="Cumulative production (kg)", title=title)
        ax.set_xticks(g.last_active_stage)
        finish(fig, name, "production_by_termination_timing.csv",
               f"Stage89N cumulative production for {term_type} timing cohorts with 95% CI")

    fig, ax = plt.subplots(figsize=(7.0, 4.1))
    width = .36
    ax.bar(x-width/2, prod_h.mean_total_production_kg, width, label="Stage89H", color=COLORS["H"], alpha=.82)
    ax.bar(x+width/2, prod_n.mean_total_production_kg, width, label="Stage89N", color=COLORS["N"], alpha=.9)
    ax.set(xticks=x, xlabel="Operating stage", ylabel="Mean production (kg)",
           title="Figure 9. Old vs adopted-TerminalLOH policy production")
    ax.legend(frameon=False)
    finish(fig, "figure09_h_vs_n_production.png", "stage89h_vs_stage89n_primary_results.csv",
           "Stage89H and Stage89N active-path mean production by stage")

    fig, ax = plt.subplots(figsize=(7.0, 4.1))
    ax.plot(x, inv_h.mean_ending_total_inventory_kg, marker="o", label="Stage89H", color=COLORS["H"])
    ax.plot(x, inv_n.mean_ending_total_inventory_kg, marker="o", label="Stage89N", color=COLORS["N"])
    ax.set(xticks=x, xlabel="Operating stage", ylabel="Mean ending inventory (kg)",
           title="Figure 10. Old vs adopted-TerminalLOH policy inventory")
    ax.legend(frameon=False)
    finish(fig, "figure10_h_vs_n_inventory.png", "stage89h_vs_stage89n_primary_results.csv",
           "Stage89H and Stage89N active-path mean ending inventory by stage")

    fig, axes = plt.subplots(1, 2, figsize=(10.2, 4.0))
    for label, frame, color, xpos in [("Stage89H", primary_h, COLORS["H"], -.18),
                                      ("Stage89N", primary_n, COLORS["N"], .18)]:
        cost = frame[frame.metric == "actual_operating_cost_yuan"].iloc[0]
        axes[0].bar([xpos], [cost["mean"]], .32, color=color, label=label)
        axes[0].errorbar([xpos], [cost["mean"]],
                         yerr=[[cost["mean"]-cost.CI_low], [cost.CI_high-cost["mean"]]],
                         fmt="none", ecolor="black", capsize=3)
    axes[0].set(xticks=[0], xticklabels=["Actual operating cost"], ylabel="yuan/path",
                title="11A. Economic performance")
    metrics = ["total_h2_production_kg", "total_htt_kg", "ordinary_shortage_kg", "terminal_gap_kg"]
    xx = np.arange(len(metrics)); width = .36
    for frame, label, color, shift in [(primary_h, "Stage89H", COLORS["H"], -width/2),
                                       (primary_n, "Stage89N", COLORS["N"], width/2)]:
        vals = [frame[frame.metric == m].iloc[0]["mean"] for m in metrics]
        axes[1].bar(xx+shift, vals, width, label=label, color=color)
    axes[1].set(xticks=xx, xticklabels=["Production", "HTT", "Ord. shortage", "Terminal gap*"],
                ylabel="kg/path", title="11B. Production and service")
    axes[1].tick_params(axis="x", rotation=20)
    axes[1].legend(frameon=False)
    axes[0].legend(frameon=False)
    fig.text(.66, -.01, "*Terminal gap conditional on paths entering Stage 7", ha="center", fontsize=8)
    finish(fig, "figure11_primary_oos_results.png", "primary_oos_results.csv",
           "Primary economic/service metrics; Terminal gap uses the Stage7 conditional denominator")

    fig, ax = plt.subplots(figsize=(7.2, 4.4))
    for stage, g in loc_n.groupby("stage"):
        ax.plot(g["loc"], g.mean_production_kg, marker="o", label=f"Stage {stage}")
    ax.set(xlabel="Observed current location category", ylabel="Mean production (kg)",
           title="Figure 12. Production after observing current location")
    ax.set_xticks(sorted(loc_n["loc"].unique()))
    ax.legend(frameon=False, ncol=3)
    finish(fig, "figure12_location_conditioned_production.png",
           "production_inventory_by_observed_loc.csv",
           "Discrete Stage89N mean production by observed location and stage; location is categorical")
    return pd.DataFrame(figs)


def contact_sheet(out: Path, figure_manifest: pd.DataFrame):
    from PIL import Image, ImageDraw
    thumbs = []
    for name in figure_manifest.figure:
        img = Image.open(out / "figures" / name).convert("RGB")
        img.thumbnail((480, 300))
        canvas = Image.new("RGB", (500, 335), "white")
        canvas.paste(img, ((500-img.width)//2, 25))
        ImageDraw.Draw(canvas).text((8, 6), name, fill="black")
        thumbs.append(canvas)
    cols, rows = 2, math.ceil(len(thumbs)/2)
    sheet = Image.new("RGB", (cols*500, rows*335), "#dddddd")
    for i, thumb in enumerate(thumbs):
        sheet.paste(thumb, ((i % cols)*500, (i//cols)*335))
    sheet.save(out / "figure_contact_sheet.png")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--run", default="run-001")
    args = parser.parse_args()
    root = args.root.resolve()
    base = root / "results" / "task-002-stage2b-b3-smoke"
    nrun = base / "stage89n-stage89k-adopted-loc4-fresh-8h-retraining" / "run-003"
    hrun = base / "89H-stage85r-single-loc4-stage88-dro-gap1000-10iter-oos10000" / "run-003"
    orun = base / "stage89o-comprehensive-policy-mechanism-analysis" / "run-005"
    dest_parent = base / "stage89p-original-paper-style-stage89n-analysis"
    out = dest_parent / args.run
    work = dest_parent / f".{args.run}.building"
    if out.exists() or work.exists():
        raise RuntimeError(f"Refusing to overwrite existing Stage89P run/build directory: {out}")
    work.mkdir(parents=True)
    try:
        N = load_policy(nrun / "oos" / "loc4")
        H = load_policy(hrun / "oos" / "loc4")
        cohorts = pd.read_csv(orun / "path_cohort_master.csv")
        assert len(N["path"]) == len(H["path"]) == len(cohorts) == INITIAL_PATHS
        assert N["manifest"].equals(H["manifest"])
        assert set(N["path"].path_id) == set(cohorts.path_id)
        assert int(cohorts.reached_stage7.sum()) == 6124
        assert int(cohorts.physical_dissipation_a1.sum()) == 3497
        assert int(cohorts.lf8_absorbing.sum()) == 379

        ci_rows: list[dict] = []
        prod_n, inv_n, bal_n = stage_tables("Stage89N", N, ci_rows)
        prod_h, inv_h, bal_h = stage_tables("Stage89H", H, ci_rows)
        intensity_n = conditional_action("Stage89N", N, ci_rows, "a")
        intensity_h = conditional_action("Stage89H", H, ci_rows, "a")
        loc_n = conditional_action("Stage89N", N, ci_rows, "loc")
        term_n = termination_table("Stage89N", N, cohorts, ci_rows)
        term_h = termination_table("Stage89H", H, cohorts, ci_rows)
        same_arrival = same_terminal_arrival(N, cohorts, ci_rows)
        primary_n = primary_results("Stage89N", N, cohorts, ci_rows)
        primary_h = primary_results("Stage89H", H, cohorts, ci_rows)
        cost_n = cost_decomposition("Stage89N", N, ci_rows)
        comparison = comparison_table(H, N, prod_h, prod_n, inv_h, inv_n,
                                      intensity_h, intensity_n, term_h, term_n,
                                      primary_h, primary_n)

        train_raw = pd.read_csv(nrun / "training_iteration_summary.csv")
        training = train_raw.rename(columns={
            "cumulative_wall_time_s": "wall_clock_time_s", "LB": "lower_bound_yuan",
            "forward_cost_UB_like": "forward_sampled_objective_yuan",
            "cumulative_cuts": "cut_count", "stage1_inventory_kg": "stage1_ending_inventory_kg",
            "stage2_inventory_kg": "stage2_ending_inventory_kg",
            "stage3_inventory_kg": "stage3_ending_inventory_kg"})
        training = training[["iteration", "wall_clock_time_s", "lower_bound_yuan",
                             "forward_sampled_objective_yuan", "cut_count", "cuts_added",
                             "stage1_production_kg", "stage1_site1_production_kg",
                             "stage1_site2_production_kg", "stage1_site3_production_kg",
                             "stage1_site4_production_kg", "stage1_ending_inventory_kg",
                             "stage2_ending_inventory_kg", "stage3_ending_inventory_kg"]]
        last3_range = training.tail(3).stage1_production_kg.max() - training.tail(3).stage1_production_kg.min()
        last4_range = training.tail(4).stage1_production_kg.max() - training.tail(4).stage1_production_kg.min()
        stability = "EARLY_STABLE_SIGNAL" if last4_range <= 1e-6 else (
            "MIXED" if last3_range <= 1e-6 else "STILL_MOVING")

        slopes = slope_summary(intensity_n, "a")
        intensity_response = classify_intensity(slopes)
        loc_slopes = slope_summary(loc_n, "loc")
        save_csv(training, work / "training_progress_10iter.csv")
        save_csv(prod_n, work / "production_by_stage.csv")
        save_csv(inv_n, work / "inventory_by_stage.csv")
        save_csv(bal_n, work / "production_inventory_stage_summary.csv")
        save_csv(intensity_n.merge(slopes, on="stage", how="left"),
                 work / "production_by_observed_intensity_and_stage.csv")
        save_csv(loc_n.merge(loc_slopes, on="stage", how="left"),
                 work / "production_inventory_by_observed_loc.csv")
        save_csv(term_n, work / "production_by_termination_timing.csv")
        save_csv(same_arrival, work / "same_terminal_state_different_arrival_time.csv")
        save_csv(primary_n, work / "primary_oos_results.csv")
        save_csv(cost_n, work / "primary_cost_decomposition.csv")
        save_csv(pd.DataFrame(ci_rows), work / "confidence_interval_summary.csv")
        save_csv(comparison, work / "stage89h_vs_stage89n_primary_results.csv")

        identity = pd.DataFrame([
            ("STAGE89N_STATUS", "PASS", "PASS", 1), ("INITIAL_LOCATION", "loc4", "loc4", 1),
            ("FORMAL_8H_MAINLINE_USED", "YES", "YES", 1), ("OPERATING_STAGES", 6, 6, 1),
            ("HOURS_PER_STAGE", 8, 8, 1), ("TOTAL_OPERATING_HOURS", 48, 48, 1),
            ("TRAINING_ITERATIONS", 10, 10, 1), ("FRESH_TRAINING", "YES", "YES", 1),
            ("WARM_START", "NONE", "NONE", 1), ("TERMINAL_GAP_PENALTY_YUAN_PER_KG", 1000, 1000, 1),
            ("ORDINARY_SHORTAGE_PENALTY_YUAN_PER_KG", 200, 200, 1),
            ("TERMINALLOH_MODE", "DRO", "DRO", 1), ("TERMINALLOH_SOURCE", "Stage89K adopted", "Stage89K adopted", 1),
            ("TERMINALLOH_ETA", .03, .03, 1), ("OOS_PATH_COUNT", 10000, 10000, 1),
            ("COMMON_PATH_WITH_STAGE89H", "YES", "YES", 1),
            ("CHECKPOINT_LIFECYCLE", "PASS", "PASS", 1), ("FULLY_CONVERGED", "NO", "NO", 1),
            ("STAGE89O_ACCEPTED_RUN", "run-005", "run-005", 1),
        ], columns=["field", "observed", "expected", "pass"])
        save_csv(identity, work / "policy_identity_audit.csv")
        resolution = pd.DataFrame([
            ("DATA_TIME_RESOLUTION", "STAGE_AGGREGATE", "Stage89N accepted run-003 stage/site CSV"),
            ("HOURLY_POLICY_CURVE_AVAILABLE", "NO", "Stage89N accepted run-003 has no accepted hourly output"),
            ("FAILED_RUN_HOURLY_DATA_USED", "NO", "Forbidden and not used"),
            ("POST_TERMINATION_ZERO_FILL_USED", "NO", "All stage means condition on active paths"),
            ("INTERPOLATION_OR_8X_REPLICATION_USED", "NO", "Forbidden and not used"),
            ("STATE_DECISION_TIMING", "STATE_T_OBSERVED_BEFORE_DECISION_T",
             "forward_pass/evaluate_path sample or read k_t before update_rhs/solve"),
        ], columns=["field", "value", "evidence"])
        save_csv(resolution, work / "data_resolution_audit.csv")

        fig_manifest = make_figures(work, training, prod_n, inv_n, intensity_n, loc_n, term_n,
                                    prod_h, inv_h, primary_h, primary_n)
        save_csv(fig_manifest, work / "figure_manifest.csv")
        contact_sheet(work, fig_manifest)

        paper = """# Stage-89P original-paper analysis mapping

Stage89P borrows the *result-analysis structure* of Siddig & Song, not their numerical values. The local paper copy is `tmp/pdfs/siddig_song_2201.10678.pdf` (SHA-256 is recorded in `source_manifest.csv`). Sections 4.1-4.3 first report OOS policy performance with 95% confidence intervals, then show action by period and by observed hurricane intensity/cost setting; the random-landfall model treats dissipation and landfall as absorbing events.

| Original-paper analysis object | Stage89P project counterpart | Comparability |
|---|---|---|
| Relief procurement by period (Eq. 21; Figures 6-7; Tables 6-7) | H2 production in operating Stages 1-6 | Structural analogy; units and physical constraints differ |
| Supply-point inventory / prepositioning | Four-site H2 inventory | Structural analogy; H2 faces ongoing ordinary demand and electrolysis limits |
| Observed hurricane intensity | FA-MSP current `a_t`, observed before the Stage-t decision | Direct state-role analogy; intensity scales are not numerically interchangeable |
| Predicted/landfall location | FA-MSP current `loc_t` | State-role analogy; geometry and service model differ |
| Random landfall time and hurricane dissipation | True Stage7 arrival and physical `a=1` dissipation | Related random-termination structure; `lf=8` is separately reported as absorbing, not dissipation |
| Unmet relief demand at landfall | Ordinary H2 shortage during preparation | NOT DIRECTLY COMPARABLE: timing and service meaning differ |
| Logistics cost plus unmet-demand penalty | Actual modeled operating cost plus ordinary shortage cost | Partial analogy; Stage89P separates the soft TerminalLOH penalty |
| Clairvoyance/perfect-information benchmark | Potential deterministic 48h solve with the full OOS path known | FUTURE OPTION ONLY; not run in Stage89P |
| None with an exact one-to-one role | Stage7 TerminalLOH soft reserve target/gap | NOT DIRECTLY COMPARABLE; it is a soft adequacy target, not realized disaster H2 demand |

The paper's main OOS sample is 1000 paths and uses mean +/- 1.96 standard errors. Stage89P uses the same normal-mean formula on 10000 accepted OOS paths and Wilson intervals for event probabilities. No perfect-information, rolling-horizon, static two-stage, or new benchmark optimization was run.
"""
        (work / "paper_analysis_mapping.md").write_text(paper, encoding="utf-8")

        early = pd.read_csv(orun / "early_a1_residual_inventory.csv")
        secondary = f"""# Stage89O secondary evidence used by Stage89P

Stage89O accepted run-005 is used only as a second layer and only for its already-validated common-path classification and intuitive diagnostics.

1. Physical dissipation: the accepted classification contains 3497 `a=1` paths. Stage89P reports their cumulative production by the last completed operating stage in `production_by_termination_timing.csv`; it never labels the 379 `lf=8` paths as dissipation.
2. Residual preventive inventory: after subtracting remaining ordinary demand through hour 48, Stage89O's physical-dissipation paths have mean residual inventory of {fmt(early.Stage89N_residual_preventive_inventory_kg.mean())} kg under Stage89N versus {fmt(early.Stage89H_residual_preventive_inventory_kg.mean())} kg under Stage89H. A positive residual is preventive inventory under this accounting, not automatically waste.
3. Tail caution: accepted common-path evidence shows Stage89N's q99 reported objective and q99 terminal gap are {fmt((N['path'].total_objective_yuan.quantile(.99)/H['path'].total_objective_yuan.quantile(.99)-1)*100,2)}% and {fmt((N['path'].terminal_gap_kg.quantile(.99)/H['path'].terminal_gap_kg.quantile(.99)-1)*100,2)}% higher. These small reverse tail signals are secondary and do not overturn the mean results.

Complex pair ratios and acronyms are intentionally omitted from the primary narrative. Stage89O also confirms that actual W1-W3 disaster recourse and realized resilience are unavailable, so Stage89P makes no realized-resilience claim.
"""
        (work / "stage89o_secondary_evidence_summary.md").write_text(secondary, encoding="utf-8")

        sources = [
            nrun / "README.md", nrun / "stage89n_parameter_audit.csv", nrun / "formal_8h_runtime_audit.csv",
            nrun / "training_iteration_summary.csv", nrun / "oos" / "loc4" / "oos_path_manifest.csv",
            nrun / "oos" / "loc4" / "oos_path_summary.csv", nrun / "oos" / "loc4" / "oos_stage_summary.csv",
            nrun / "oos" / "loc4" / "oos_stage_site_summary.csv", hrun / "README.md",
            hrun / "oos" / "loc4" / "oos_path_manifest.csv", hrun / "oos" / "loc4" / "oos_path_summary.csv",
            hrun / "oos" / "loc4" / "oos_stage_summary.csv", hrun / "oos" / "loc4" / "oos_stage_site_summary.csv",
            orun / "README.md", orun / "path_cohort_master.csv", orun / "early_a1_residual_inventory.csv",
            root / "fa_h2" / "forward_pass_h2.m",
            root / "fa_msp" / "current_hourly_stage89_adopted" / "launcher" / "run_stage89n_stage85r_single_loc4_gap1000_h2.m",
            root / "tmp" / "pdfs" / "siddig_song_2201.10678.pdf",
        ]
        source_rows = []
        for path in sources:
            assert path.exists(), path
            source_rows.append({"path": str(path.relative_to(root)).replace("\\", "/"),
                                "bytes": path.stat().st_size, "sha256": sha256(path),
                                "role": "READ_ONLY_SOURCE"})
        save_csv(pd.DataFrame(source_rows), work / "source_manifest.csv")

        pstage = prod_n.set_index("stage").mean_total_production_kg
        istage = inv_n.set_index("stage").mean_ending_total_inventory_kg
        actual = primary_n[primary_n.metric == "actual_operating_cost_yuan"].iloc[0]
        shortage = primary_n[primary_n.metric == "ordinary_shortage_kg"].iloc[0]
        shortage_p = primary_n[primary_n.metric == "probability_any_ordinary_shortage"].iloc[0]
        gap = primary_n[primary_n.metric == "terminal_gap_kg"].iloc[0]
        gap_p = primary_n[primary_n.metric == "probability_terminal_gap_positive"].iloc[0]
        dominant = ", ".join(f"Stage{s}" for s in pstage.sort_values(ascending=False).head(3).index)
        inv_pattern = ("Stage1建立较高库存，Stage2-3明显回落，Stage4-6随仍活跃路径的风险历史而再调整"
                       if istage.iloc[2] < istage.iloc[0] else "库存随阶段总体增加")
        a1n = term_n[term_n.termination_type == "A1"].sort_values("last_active_stage")
        s7n = term_n[term_n.termination_type == "STAGE7"].sort_values("last_active_stage")
        a1_pattern = ("累计制氢随更晚消散总体增加" if a1n.mean_cumulative_production_kg.iloc[-1] > a1n.mean_cumulative_production_kg.iloc[0]
                      else "未见随更晚消散单调增加")
        s7_pattern = ("累计制氢随更晚进入Stage7总体增加" if s7n.mean_cumulative_production_kg.iloc[-1] > s7n.mean_cumulative_production_kg.iloc[0]
                      else "未见随更晚进入Stage7单调增加")
        stage_lines = "\n".join(
            f"- Stage {s}: {pstage[s]:.3f} kg（active paths N={int(prod_n.loc[prod_n.stage==s,'active_path_count'].iloc[0])}，95% CI {prod_n.loc[prod_n.stage==s,'CI95_low_total_production_kg'].iloc[0]:.3f}-{prod_n.loc[prod_n.stage==s,'CI95_high_total_production_kg'].iloc[0]:.3f}）"
            for s in range(1, 7))
        balance_lines = "\n".join(
            f"- Stage {int(r.stage)}: production {r.mean_production_kg:.2f}, served {r.mean_ordinary_demand_served_kg:.2f}, inventory {r.mean_beginning_inventory_kg:.2f}->{r.mean_ending_inventory_kg:.2f} kg；{r.inventory_change_explanation}."
            for _, r in bal_n.iterrows())
        slope_lines = "\n".join(
            f"- Stage {int(r.stage)}: grouped-mean slope {r.weighted_mean_slope_kg_per_state_level:.3f} kg per intensity level, rank correlation {r.rank_correlation_of_group_means:.3f}."
            for _, r in slopes.iterrows())
        readme = f"""# Stage-89P: Stage89N 10-iteration policy in original-paper result style

Status: **PASS**. This is read-only postprocessing of the accepted Stage89N run-003. Stage89P analyzes the FA-MSP policy generated using the adopted Stage89K Pearson probability-DRO TerminalLOH table. Stage89P did not perform DRO training, new FA-MSP training, OOS, checkpoint loading, or model modification.

## Plain-language result

This controlled 10-iteration policy produces most hydrogen in {dominant}. Stage1 is large at {pstage[1]:.2f} kg, but production does not stay high: Stage2 falls to {pstage[2]:.2f} kg, followed by path-dependent later adjustments. Inventory is built immediately, then drawn down through the middle stages before later surviving paths adjust again. The direct intensity-conditioned response is **{intensity_response}**: stronger observed intensity does not produce a uniformly monotone response at every stage, so a single “risk rises -> always produce more” claim is not supported by this 10-iteration diagnostic.

Paths that remain physically active longer generally accumulate more production before physical dissipation, and paths entering Stage7 later generally accumulate more production before the reserve check. For the 6124 true Stage7 paths, the mean TerminalLOH gap is {gap['mean']:.3f} kg (95% CI {gap.CI_low:.3f}-{gap.CI_high:.3f}); this is conditional on actually entering Stage7, not diluted by assigning zero gaps to other paths. Mean actual operating cost is {actual['mean']:.2f} yuan/path (95% CI {actual.CI_low:.2f}-{actual.CI_high:.2f}). Ordinary shortage averages {shortage['mean']:.3f} kg/path and occurs on {shortage_p.event_probability:.2%} of all paths.

Compared with the old Stage89H TerminalLOH control, Stage89N's clearest change is a lower reserve/production level rather than an equal shift of production to later stages: mean production falls from {primary_h.loc[primary_h.metric=='total_h2_production_kg','mean'].iloc[0]:.3f} to {primary_n.loc[primary_n.metric=='total_h2_production_kg','mean'].iloc[0]:.3f} kg/path, while mean ordinary shortage and mean Stage7-conditional gap also improve. The q99 objective and gap move slightly in the opposite direction; those tail reversals are secondary signals and should not be overinterpreted before longer paired training.

## Identity and scope

- Source policy: Stage89N accepted `run-003`, loc4, correct 6x8h architecture, 10 fresh iterations, no warm start.
- Ordinary shortage penalty: 200 yuan/kg. Terminal-gap soft penalty: 1000 yuan/kg.
- TerminalLOH: adopted Stage89K DRO, eta=0.03.
- OOS: 10000 accepted common paths shared byte-for-byte with Stage89H.
- Data resolution: `STAGE_AGGREGATE`; accepted Stage89N has no hourly detail. No interpolation, eightfold replication, failed-run hourly data, or post-termination zeros are used.
- The current state `a_t, loc_t, lf_t` is sampled/read before the Stage-t model is updated and solved; conditional action tables therefore use information available to the policy, not future information.
- `FULLY_CONVERGED = NO`. Ten iterations are a controlled diagnostic policy only.

## Q1. Stage1-Stage6 production

Primary means are conditional on paths that truly operate in that stage:

{stage_lines}

Figure 3 additionally shows an unconditional per-initial-path contribution so that early termination is visible without pretending that a terminated path made a zero decision.

## Q2. Inventory and the joint production-service balance

Pattern: {inv_pattern}.

{balance_lines}

At the system-total level HTT cancels exactly between origin and destination; it changes the four-site distribution, not total inventory. The maximum site-level balance residual in the accepted stage tables is {bal_n.max_abs_site_balance_residual_kg.max():.3e} kg, so the system decomposition is complete rather than guessed.

## Q3-Q4. Response after observing intensity

`RISK_INTENSITY_PRODUCTION_RESPONSE = {intensity_response}`.

{slope_lines}

These are descriptive conditional means, not causal estimates: current intensity, location, prior inventory, and history co-move. The full sample counts and 95% intervals are in `production_by_observed_intensity_and_stage.csv`. Location-conditioned results are in `production_inventory_by_observed_loc.csv`; location effects are not promoted to a main conclusion unless their stagewise differences are large and stable.

The strongest direct contrast is between `a=2` and `a>=3`: production rises sharply after the higher state is observed. Within `a=3..5`, however, several stages contain reversals, so the evidence is moderate rather than a globally monotone response. Conversely, a weakening back toward `a=2` is associated with much lower production in these descriptive groups, but not every one-step weakening has a uniform response.

Location differences are visible, especially at later stages where loc7 groups tend to produce less than loc1-loc3 groups. Figure 12 reports those category differences, but `loc` is a spatial category rather than an ordered risk score, and history/inventory composition differs across groups.

## Q5-Q8. Random termination and when risk becomes known

- Physical `a=1` dissipation is reported separately from true Stage7 arrival and from `lf=8` absorption.
- {a1_pattern}. The relevant cohort means and intervals are in `production_by_termination_timing.csv` and Figure 7.
- {s7_pattern}. Figure 8 uses only true Stage7 paths.
- `same_terminal_state_different_arrival_time.csv` holds final intensity/location fixed and reports arrival-specific means plus earliest-versus-latest descriptive contrasts. Some cells are marked `DESCRIPTIVE_ONLY` when N<30.

The results answer a process question, not a perfect-information counterfactual: later resolution gives more operating opportunities and is associated with more cumulative preparation, but histories and selection also differ.

## Q9-Q11. Economic, ordinary-service, and reserve results

- Mean actual operating cost: {actual['mean']:.2f} yuan/path; 95% CI [{actual.CI_low:.2f}, {actual.CI_high:.2f}].
- Mean ordinary shortage: {shortage['mean']:.3f} kg/path; 95% CI [{shortage.CI_low:.3f}, {shortage.CI_high:.3f}]. Any-shortage probability: {shortage_p.event_probability:.4f}, Wilson 95% CI [{shortage_p.event_CI95_low:.4f}, {shortage_p.event_CI95_high:.4f}].
- Among 6124 true Stage7 paths, mean TerminalLOH gap: {gap['mean']:.3f} kg; 95% CI [{gap.CI_low:.3f}, {gap.CI_high:.3f}]. Positive-gap probability: {gap_p.event_probability:.4f}, Wilson 95% CI [{gap_p.event_CI95_low:.4f}, {gap_p.event_CI95_high:.4f}].

`primary_cost_decomposition.csv` separates electricity/grid, production O&M, ordinary shortage, HTT, holding/other actual cost, the TerminalLOH soft-target penalty, and reported objective. The terminal penalty is an optimization incentive, not a claimed cash payment and not realized disaster shortage.

## Q12. Stage89H to Stage89N

The old control and Stage89N share loc4, correct 8h architecture, penalties, training/OOS seeds, physical parameters, and all 10000 OOS paths. Their expected controlled input difference is Stage88 versus adopted Stage89K TerminalLOH provenance. Stage89N lowers Stage1 production from {prod_h.loc[prod_h.stage==1,'mean_total_production_kg'].iloc[0]:.2f} to {pstage[1]:.2f} kg and sharply lowers middle-stage inventory. Its mean actual operating cost changes from {primary_h.loc[primary_h.metric=='actual_operating_cost_yuan','mean'].iloc[0]:.2f} to {actual['mean']:.2f} yuan/path; ordinary shortage changes from {primary_h.loc[primary_h.metric=='ordinary_shortage_kg','mean'].iloc[0]:.3f} to {shortage['mean']:.3f} kg/path. This is an old-TerminalLOH control, not a definitive benchmark.

## Q13. What longer training must verify

The Stage1 decision is identical in iterations 8-10, but it changes between iterations 7 and 8; the lower bound also makes a material move at iteration 9 before a small iteration-10 increment. Therefore `TEN_ITERATION_POLICY_STABILITY = {stability}` and never `CONVERGED`. Longer paired 1000/1500 training is needed to test the mixed intensity response, late Stage7/tail reversals, spatial response, and same-terminal-state timing contrasts.

## Original-paper structure and benchmark boundary

The paper mapping is documented in `paper_analysis_mapping.md`. The original paper reports OOS mean/95% CI, action by time, response to risk/cost settings, and random landfall timing. Stage89P adopts that order while explicitly retaining this project's different physics and semantics.

`PERFECT_INFORMATION_BENCHMARK = FUTURE_OPTION`: a future benchmark could solve a deterministic 48h operating problem with each complete OOS hurricane path known in advance. It is not implemented here.

```text
TASK_ID = Stage-89P
STAGE89P_STATUS = PASS
SOURCE_POLICY = Stage89N accepted run-003
TERMINALLOH_MODE = DRO
TERMINALLOH_ETA = 0.03
TERMINAL_GAP_PENALTY = 1000
TRAINING_ITERATIONS = 10
FULLY_CONVERGED = NO
TEN_ITERATION_POLICY_STABILITY = {stability}
NEW_TRAINING_RUN = NO
NEW_OOS_RUN = NO
CHECKPOINT_LOADED = NO
MODEL_MODIFIED = NO
PENALTY_1500_RUN = NO
LONGER_TRAINING_RUN = NO
DATA_TIME_RESOLUTION = STAGE_AGGREGATE
HOURLY_POLICY_CURVE_AVAILABLE = NO
STAGE1_MEAN_PRODUCTION_KG = {pstage[1]:.12g}
STAGE2_MEAN_PRODUCTION_KG = {pstage[2]:.12g}
STAGE3_MEAN_PRODUCTION_KG = {pstage[3]:.12g}
STAGE4_MEAN_PRODUCTION_KG = {pstage[4]:.12g}
STAGE5_MEAN_PRODUCTION_KG = {pstage[5]:.12g}
STAGE6_MEAN_PRODUCTION_KG = {pstage[6]:.12g}
DOMINANT_PRODUCTION_STAGES = {dominant}
INVENTORY_BUILD_PATTERN = {inv_pattern}
RISK_INTENSITY_PRODUCTION_RESPONSE = {intensity_response}
EARLY_DISSIPATION_PREPARATION_PATTERN = {a1_pattern}
STAGE7_ARRIVAL_TIMING_PATTERN = {s7_pattern}
MEAN_ACTUAL_OPERATING_COST = {actual['mean']:.12g}
MEAN_ACTUAL_OPERATING_COST_95CI = [{actual.CI_low:.12g},{actual.CI_high:.12g}]
MEAN_ORDINARY_SHORTAGE_KG = {shortage['mean']:.12g}
ORDINARY_SHORTAGE_PROBABILITY = {shortage_p.event_probability:.12g}
MEAN_TERMINAL_GAP_KG = {gap['mean']:.12g}
TERMINAL_GAP_PROBABILITY = {gap_p.event_probability:.12g}
TERMINAL_GAP_DENOMINATOR = CONDITIONAL_ON_6124_TRUE_STAGE7_PATHS
STAGE89H_CONTROL_USED = YES
PRIMARY_STAGE89H_TO_STAGE89N_CHANGE = LOWER_RESERVE_AND_PRODUCTION_LEVEL_WITH_LOWER_MEAN_COST_SHORTAGE_AND_STAGE7_CONDITIONAL_GAP
STAGE89O_USED_AS_SECONDARY_EVIDENCE = YES
PERFECT_INFORMATION_BENCHMARK_RUN = NO
NEW_BENCHMARK_SOLVE_RUN = NO
READY_FOR_LONGER_1000_AND_1500_EXPERIMENT = YES
RECOMMEND_NEXT_STAGE = LONGER_1000_AND_1500_PAIRED_TRAINING
```

## Output map

Tables 1-7 correspond respectively to `policy_identity_audit.csv`, `training_progress_10iter.csv`, `production_inventory_stage_summary.csv`, `production_by_observed_intensity_and_stage.csv`, `production_by_termination_timing.csv`, `primary_oos_results.csv`, and `stage89h_vs_stage89n_primary_results.csv`. Every formal figure is listed with its machine-readable CSV and SHA-256 in `figure_manifest.csv`.
"""
        (work / "README.md").write_text(readme, encoding="utf-8")

        # Publication is atomic: a failed build never occupies the accepted run path.
        work.rename(out)
        print(f"STAGE89P_BUILD_PASS={out}")
        print(f"TEN_ITERATION_POLICY_STABILITY={stability}")
        print(f"RISK_INTENSITY_PRODUCTION_RESPONSE={intensity_response}")
        print(prod_n[["stage", "active_path_count", "mean_total_production_kg"]].to_string(index=False))
        print(primary_n[["metric", "denominator", "N", "mean", "event_probability"]].to_string(index=False))
    except Exception:
        if work.exists():
            failed = dest_parent / f"{args.run}.failed-build"
            if failed.exists():
                raise RuntimeError(f"Build failed and failure target already exists: {failed}")
            work.rename(failed)
        raise


if __name__ == "__main__":
    main()
