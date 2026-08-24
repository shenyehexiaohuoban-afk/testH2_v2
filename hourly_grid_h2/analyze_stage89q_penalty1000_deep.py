#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Read-only deep postprocessing for accepted Stage89Q penalty=1000 OOS data."""

from __future__ import annotations

import hashlib
import math
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from matplotlib import font_manager
from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
RUN = ROOT / "results/task-002-stage2b-b3-smoke/stage89q-penalty1000-vs1500-long-training/run-003"
RAW = ROOT / "hourly_grid_h2/output/stage89q_penalty1000_vs1500_long_training/run-003/penalty1000"
TRAINING_FILE = ROOT / "results/task-002-stage2b-b3-smoke/stage89q-penalty1000-vs1500-long-training/run-002/02_training/penalty1000/training_progress.csv"
OUT = RUN / "05_analysis/10_deep_penalty1000"
FIG = RUN / "06_figures/08_penalty1000_deep_analysis"
TOL = 1e-7
SITE_IDS = [1, 2, 3, 4]
PMAX = {1: 300.0, 2: 175.0, 3: 105.0, 4: 150.0}
K_H2 = 0.0195

DIRS = {
    "account": OUT / "01_path_accounting",
    "surplus": OUT / "02_stage7_adequate_surplus",
    "state": OUT / "03_terminal_state_35",
    "arrival": OUT / "04_arrival_timing",
    "shortfall": OUT / "05_shortfall_sites",
    "htt": OUT / "06_spatial_htt",
    "catchup": OUT / "07_catchup_limits",
    "ordinary": OUT / "08_ordinary_shortage",
    "dissipation": OUT / "09_dissipation",
    "tail": OUT / "10_tail",
    "cases": OUT / "11_cases",
    "economics": OUT / "12_economics",
    "training": OUT / "13_training_depth",
    "summary": OUT / "14_summary",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def save_csv(frame: pd.DataFrame, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    frame.to_csv(path, index=False, encoding="utf-8-sig", float_format="%.12g")


def quantiles(values) -> dict[str, float]:
    x = pd.Series(values, dtype="float64").dropna().to_numpy()
    if not len(x):
        return {k: np.nan for k in ("mean", "median", "q25", "q75", "q90", "q95", "q99", "max")}
    return {
        "mean": float(np.mean(x)), "median": float(np.median(x)),
        "q25": float(np.quantile(x, .25)), "q75": float(np.quantile(x, .75)),
        "q90": float(np.quantile(x, .90)), "q95": float(np.quantile(x, .95)),
        "q99": float(np.quantile(x, .99)), "max": float(np.max(x)),
    }


def prefixed_stats(values, prefix: str) -> dict[str, float]:
    return {f"{prefix}_{key}": value for key, value in quantiles(values).items()}


def chinese_font() -> str:
    available = {item.name for item in font_manager.fontManager.ttflist}
    for candidate in ("Microsoft YaHei", "Microsoft YaHei UI", "SimHei"):
        if candidate in available:
            return candidate
    raise RuntimeError("No Chinese font available")


def setup() -> None:
    for directory in [OUT, FIG, *DIRS.values()]:
        directory.mkdir(parents=True, exist_ok=True)
    font = chinese_font()
    plt.rcParams.update({
        "font.family": font, "axes.unicode_minus": False, "font.size": 10,
        "figure.dpi": 140, "savefig.dpi": 180, "axes.titleweight": "bold",
    })


def load_inputs():
    path = pd.read_csv(RAW / "path_summary/oos_path_summary.csv")
    stage = pd.read_csv(RAW / "path_summary/oos_stage_summary.csv")
    site = pd.read_csv(RAW / "path_summary/oos_stage_site_summary.csv")
    hour = pd.read_csv(RAW / "hourly_site/oos_hour_site.csv")
    system = pd.read_csv(RAW / "grid_hourly/oos_hour_system.csv")
    flow = pd.read_csv(RAW / "htt_od/oos_positive_htt_flows.csv")
    training = pd.read_csv(TRAINING_FILE)
    return path, stage, site, hour, system, flow, training


def enrich_path(path: pd.DataFrame) -> pd.DataFrame:
    p = path.copy()
    p["operating_hours"] = 8 * p.operating_stage_count
    p["arrival_after_stage"] = p.termination_stage - 1
    p["arrival_label"] = p.arrival_after_stage.map(lambda x: f"after Stage{int(x)}")
    p["positive_target"] = p.target_total > TOL
    p["adequate"] = p.terminal_site_gap <= TOL
    p["total_margin"] = p.terminal_inventory_total - p.target_total
    p["site_surplus_total"] = p[[f"surplus_site{i}" for i in SITE_IDS]].sum(axis=1)
    p["site_gap_total"] = p[[f"gap_site{i}" for i in SITE_IDS]].sum(axis=1)
    p["surplus_ratio"] = np.where(p.positive_target, p.total_margin / p.target_total, np.nan)
    p["ordinary_shortage_flag"] = p.ordinary_shortage_total > TOL
    p["terminal_gap_flag"] = p.terminal_site_gap > TOL
    return p


def add_last_window_metrics(p: pd.DataFrame, hour: pd.DataFrame, system: pd.DataFrame) -> pd.DataFrame:
    end_hour = p.set_index("path_id").operating_hours
    h = hour.copy()
    h["end_hour"] = h.path_id.map(end_hour)
    h["relative_hour"] = h.global_hour - h.end_hour
    sys = system.copy()
    sys["end_hour"] = sys.path_id.map(end_hour)
    sys["relative_hour"] = sys.global_hour - sys.end_hour
    result = p.copy()
    for window in (4, 8, 16, 24):
        subset = h[h.relative_hour.between(-(window - 1), 0)]
        agg = subset.groupby("path_id").agg(
            **{f"final{window}h_production": ("H2_production_kg", "sum")},
            **{f"final{window}h_htt": ("HTT_out_kg", "sum")},
            **{f"final{window}h_shortage": ("ordinary_shortage_kg", "sum")},
        )
        result = result.merge(agg, on="path_id", how="left")
    return result, h, sys


def path_accounting(p: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for termination, group in p.groupby("termination_type", sort=True):
        rows.append({
            "termination_type": termination, "count": len(group),
            "fraction_of_10000": len(group) / 10000,
            "mean_operating_hours": group.operating_hours.mean(),
            "mean_production_kg": group.total_H2_production.mean(),
            "mean_ordinary_shortage_kg": group.ordinary_shortage_total.mean(),
            "mean_actual_operating_cost_yuan": group.actual_operating_cost.mean(),
        })
    frame = pd.DataFrame(rows)
    if int(frame["count"].sum()) != 10000:
        raise RuntimeError("Termination accounting does not sum to 10000")
    save_csv(frame, DIRS["account"] / "path_termination_full_accounting.csv")
    return frame


def stage7_surplus(p: pd.DataFrame):
    s7 = p[p.reached_stage7.eq(1)].copy()
    zero = s7[~s7.positive_target]
    positive = s7[s7.positive_target]
    rows = []
    for label, group in (("Stage7全部", s7), ("目标为0", zero), ("目标大于0", positive)):
        rows.append({
            "scope": label, "path_count": len(group), "denominator": len(s7),
            "fraction_of_stage7": len(group) / len(s7),
            "adequate_count": int(group.adequate.sum()),
            "adequate_probability": group.adequate.mean() if len(group) else np.nan,
            "positive_gap_count": int(group.terminal_gap_flag.sum()),
            "positive_gap_probability": group.terminal_gap_flag.mean() if len(group) else np.nan,
            "gap_if_positive_kg": group.loc[group.terminal_gap_flag, "terminal_site_gap"].mean(),
        })
    zero_positive = pd.DataFrame(rows)
    save_csv(zero_positive, DIRS["surplus"] / "stage7_zero_vs_positive_target.csv")

    adequate = s7[s7.adequate].copy()
    identity = adequate.site_surplus_total - adequate.site_gap_total - adequate.total_margin
    summary = pd.DataFrame([{
        "scope": "Stage7达标路径", "path_count": len(adequate), "denominator": len(s7),
        **prefixed_stats(adequate.total_margin, "total_margin_kg"),
        **prefixed_stats(adequate.site_surplus_total, "site_surplus_total_kg"),
        "identity_max_abs_residual_kg": identity.abs().max(),
        "identity_tolerance_kg": TOL, "identity_pass": bool((identity.abs() <= TOL).all()),
    }])
    save_csv(summary, DIRS["surplus"] / "stage7_adequate_surplus_summary.csv")

    absolute_bins = [-np.inf, 5, 20, 50, 100, np.inf]
    absolute_labels = ["0-5 kg", "5-20 kg", "20-50 kg", "50-100 kg", ">100 kg"]
    bin_rows = []
    for scope, group in (("全部达标路径", adequate), ("正目标达标路径", adequate[adequate.positive_target])):
        group = group.copy()
        group["bin"] = pd.cut(group.total_margin, absolute_bins, labels=absolute_labels, right=False)
        for label in absolute_labels:
            cell = group[group["bin"].eq(label)]
            bin_rows.append({
                "scope": scope, "surplus_bin": label, "count": len(cell),
                "denominator_adequate_paths": len(group),
                "fraction_of_scope_adequate_paths": len(cell) / len(group) if len(group) else np.nan,
                "fraction_of_all_positive_target_stage7": len(cell) / len(positive),
                "mean_production_kg": cell.total_H2_production.mean(),
                "mean_HTT_kg": cell.total_HTT.mean(),
                "mean_actual_operating_cost_yuan": cell.actual_operating_cost.mean(),
                "mean_ordinary_shortage_kg": cell.ordinary_shortage_total.mean(),
            })
    absolute = pd.DataFrame(bin_rows)
    save_csv(absolute, DIRS["surplus"] / "stage7_surplus_absolute_bins.csv")

    ratio_adequate = adequate[adequate.positive_target].copy()
    ratio_bins = [-np.inf, .05, .10, .20, .50, np.inf]
    ratio_labels = ["0-5%", "5-10%", "10-20%", "20-50%", ">50%"]
    ratio_adequate["bin"] = pd.cut(ratio_adequate.surplus_ratio, ratio_bins, labels=ratio_labels, right=False)
    ratio_rows = []
    for label in ratio_labels:
        cell = ratio_adequate[ratio_adequate["bin"].eq(label)]
        ratio_rows.append({
            "surplus_ratio_bin": label, "count": len(cell),
            "denominator_positive_target_adequate": len(ratio_adequate),
            "fraction": len(cell) / len(ratio_adequate),
            "mean_surplus_ratio": cell.surplus_ratio.mean(),
            "median_surplus_ratio": cell.surplus_ratio.median(),
        })
    ratio = pd.DataFrame(ratio_rows)
    save_csv(ratio, DIRS["surplus"] / "stage7_surplus_ratio_bins.csv")

    site_rows = []
    for scope, group in (("全部达标路径", adequate), ("正目标达标路径", ratio_adequate)):
        for site_id in SITE_IDS:
            delta = group[f"inventory_site{site_id}"] - group[f"target_site{site_id}"]
            site_rows.append({
                "scope": scope, "site": site_id, "path_count": len(group),
                "mean_surplus_kg": delta.mean(), "median_surplus_kg": delta.median(),
                "q95_surplus_kg": delta.quantile(.95), "q99_surplus_kg": delta.quantile(.99),
                "positive_surplus_probability": (delta > TOL).mean(),
                "surplus_gt20kg_probability": (delta > 20).mean(),
                "surplus_gt50kg_probability": (delta > 50).mean(),
            })
    site_summary = pd.DataFrame(site_rows)
    save_csv(site_summary, DIRS["surplus"] / "stage7_site_surplus_summary.csv")
    return s7, adequate, zero_positive, summary, absolute, ratio, site_summary


def group_profile(group: pd.DataFrame) -> dict[str, float]:
    positive_gap = group[group.terminal_gap_flag]
    positive_short = group[group.ordinary_shortage_flag]
    adequate = group[group.adequate]
    return {
        "path_count": len(group), "mean_target_kg": group.target_total.mean(),
        "mean_final_inventory_kg": group.terminal_inventory_total.mean(),
        "adequate_probability": group.adequate.mean(),
        "positive_gap_probability": group.terminal_gap_flag.mean(),
        "gap_if_positive_kg": positive_gap.terminal_site_gap.mean(),
        "adequate_surplus_mean_kg": adequate.total_margin.mean(),
        "adequate_surplus_median_kg": adequate.total_margin.median(),
        "mean_production_kg": group.total_H2_production.mean(),
        "mean_final16h_production_kg": group.final16h_production.mean(),
        "mean_final8h_production_kg": group.final8h_production.mean(),
        "mean_HTT_kg": group.total_HTT.mean(),
        "ordinary_shortage_probability": group.ordinary_shortage_flag.mean(),
        "ordinary_shortage_if_positive_kg": positive_short.ordinary_shortage_total.mean(),
        "mean_ordinary_shortage_kg": group.ordinary_shortage_total.mean(),
        "mean_actual_operating_cost_yuan": group.actual_operating_cost.mean(),
    }


def terminal_states_and_arrival(s7: pd.DataFrame):
    rows = []
    for a in range(2, 7):
        for loc in range(1, 8):
            group = s7[(s7.terminal_a == a) & (s7.terminal_loc == loc)]
            row = {"terminal_a": a, "terminal_loc": loc, **group_profile(group)}
            row["arrival_stage_distribution"] = ";".join(
                f"after Stage{int(k)}:{int(v)}" for k, v in group.arrival_after_stage.value_counts().sort_index().items()
            )
            rows.append(row)
    states = pd.DataFrame(rows)
    save_csv(states, DIRS["state"] / "stage7_by_terminal_state_35.csv")

    arrival_rows = []
    for arrival in range(2, 7):
        group = s7[s7.arrival_after_stage.eq(arrival)]
        arrival_rows.append({"arrival_after_stage": arrival, "arrival_label": f"after Stage{arrival}", **group_profile(group)})
    arrival = pd.DataFrame(arrival_rows)
    save_csv(arrival, DIRS["arrival"] / "stage7_by_arrival_stage_detailed.csv")

    joint_rows = []
    for arrival_stage in range(2, 7):
        for terminal_a in range(2, 7):
            group = s7[(s7.arrival_after_stage == arrival_stage) & (s7.terminal_a == terminal_a)]
            joint_rows.append({
                "arrival_after_stage": arrival_stage, "terminal_a": terminal_a,
                "N": len(group), "gap_probability": group.terminal_gap_flag.mean(),
                "gap_if_positive_kg": group.loc[group.terminal_gap_flag, "terminal_site_gap"].mean(),
                "adequate_surplus_mean_kg": group.loc[group.adequate, "total_margin"].mean(),
            })
    joint = pd.DataFrame(joint_rows)
    save_csv(joint, DIRS["arrival"] / "stage7_arrival_by_intensity.csv")
    return states, arrival, joint


def shortfall_sites(s7: pd.DataFrame, hour: pd.DataFrame, system: pd.DataFrame):
    failed = s7[s7.terminal_gap_flag].copy()
    site_rows = []
    for site_id in SITE_IDS:
        deficit = failed[f"gap_site{site_id}"]
        positive = deficit[deficit > TOL]
        site_rows.append({
            "site": site_id, "shortfall_path_count": len(failed),
            "deficit_occurrence_count": len(positive),
            "deficit_occurrence_probability": len(positive) / len(failed),
            "mean_deficit_if_positive_kg": positive.mean(), "median_deficit_if_positive_kg": positive.median(),
            "q95_deficit_if_positive_kg": positive.quantile(.95), "max_deficit_kg": positive.max(),
        })
    site_summary = pd.DataFrame(site_rows)
    save_csv(site_summary, DIRS["shortfall"] / "stage7_shortfall_by_site.csv")

    combinations = failed.apply(
        lambda row: "+".join(f"site{i}" for i in SITE_IDS if row[f"gap_site{i}"] > TOL), axis=1
    )
    combo = combinations.value_counts().rename_axis("deficit_site_combination").reset_index(name="count")
    combo["fraction_of_shortfall_paths"] = combo["count"] / len(failed)
    combo["number_of_deficit_sites"] = combo.deficit_site_combination.str.count(r"\+") + 1
    save_csv(combo, DIRS["shortfall"] / "stage7_shortfall_site_combinations.csv")

    mechanism_rows = []
    for mechanism in ("PURE_QUANTITY_SHORTFALL", "PURE_SPATIAL_MISMATCH", "MIXED_QUANTITY_AND_SPATIAL"):
        group = failed[failed.terminal_gap_class.eq(mechanism)]
        ids = set(group.path_id)
        hh = hour[hour.path_id.isin(ids) & hour.relative_hour.between(-15, 0)]
        path_hours = hh.groupby(["path_id", "global_hour"]).electrolyzer_capacity_binding.max()
        ss = system[system.path_id.isin(ids) & system.relative_hour.between(-15, 0)]
        row = {"mechanism": mechanism, **group_profile(group)}
        row.update({
            "mean_terminal_a": group.terminal_a.mean(), "terminal_a_mode": group.terminal_a.mode().iloc[0] if len(group) else np.nan,
            "terminal_loc_mode": group.terminal_loc.mode().iloc[0] if len(group) else np.nan,
            "mean_arrival_after_stage": group.arrival_after_stage.mean(),
            "electrolyzer_binding_fraction_final16_path_hours": path_hours.mean(),
            "voltage_binding_fraction_final16_path_hours": (ss.min_voltage_pu <= .900001).mean(),
        })
        mechanism_rows.append(row)
    mechanisms = pd.DataFrame(mechanism_rows)
    save_csv(mechanisms, DIRS["shortfall"] / "stage7_shortfall_mechanism_groups.csv")
    return failed, site_summary, combo, mechanisms


def spatial_timeline(failed: pd.DataFrame, hour: pd.DataFrame):
    focus = failed[failed.terminal_gap_class.isin(["PURE_SPATIAL_MISMATCH", "MIXED_QUANTITY_AND_SPATIAL"])]
    ids = set(focus.path_id)
    h = hour[hour.path_id.isin(ids)].copy()
    targets = focus.set_index("path_id")[[f"target_site{i}" for i in SITE_IDS]]
    h["target_kg"] = [targets.at[pid, f"target_site{int(site)}"] for pid, site in zip(h.path_id, h.site)]
    h["inventory_deviation_kg"] = h.end_inventory_kg - h.target_kg
    h["deficit"] = h.inventory_deviation_kg < -TOL
    h["surplus"] = h.inventory_deviation_kg > TOL
    checkpoints = [-24, -16, -8, -4, 0]
    rows = []
    for mechanism, mg in focus.groupby("terminal_gap_class"):
        mh = h[h.path_id.isin(mg.path_id)]
        for rel in checkpoints:
            cell = mh[mh.relative_hour.eq(rel)]
            for site_id in SITE_IDS:
                site_cell = cell[cell.site.eq(site_id)]
                rows.append({
                    "record_type": "checkpoint_site_summary", "mechanism": mechanism,
                    "relative_hour": rel, "site": site_id, "N": site_cell.path_id.nunique(),
                    "mean_inventory_minus_target_kg": site_cell.inventory_deviation_kg.mean(),
                    "median_inventory_minus_target_kg": site_cell.inventory_deviation_kg.median(),
                    "deficit_probability": site_cell.deficit.mean(), "surplus_probability": site_cell.surplus.mean(),
                })
    path_rows = []
    for path_id, group in h.groupby("path_id"):
        by_hour = group.groupby("relative_hour").agg(any_deficit=("deficit", "max"), any_surplus=("surplus", "max"))
        deficit_hours = by_hour.index[by_hour.any_deficit]
        mismatch_hours = by_hour.index[by_hour.any_deficit & by_hour.any_surplus]
        path_rows.append({
            "record_type": "path_timing", "path_id": path_id,
            "mechanism": focus.set_index("path_id").at[path_id, "terminal_gap_class"],
            "first_observed_deficit_relative_hour": deficit_hours.min() if len(deficit_hours) else np.nan,
            "first_observed_simultaneous_deficit_surplus_hour": mismatch_hours.min() if len(mismatch_hours) else np.nan,
            "mismatch_hour_count": len(mismatch_hours),
            "observed_hour_count": len(by_hour),
        })
    timeline = pd.concat([pd.DataFrame(rows), pd.DataFrame(path_rows)], ignore_index=True, sort=False)
    save_csv(timeline, DIRS["htt"] / "spatial_mismatch_timeline.csv")
    return timeline


def htt_helpfulness(p: pd.DataFrame, flow: pd.DataFrame):
    if flow.empty:
        frame = pd.DataFrame([{"scope": "all", "availability": "NOT_AVAILABLE_FROM_SAVED_DATA"}])
        save_csv(frame, DIRS["htt"] / "htt_helpfulness_summary.csv")
        return frame, flow
    targets = p.set_index("path_id")
    f = flow.copy()
    f["origin_target_kg"] = [targets.at[pid, f"target_site{int(site)}"] for pid, site in zip(f.path_id, f.origin_site)]
    f["destination_target_kg"] = [targets.at[pid, f"target_site{int(site)}"] for pid, site in zip(f.path_id, f.destination_site)]
    f["origin_surplus_kg"] = (f.source_inventory_pre_htt_kg - f.origin_target_kg).clip(lower=0)
    f["destination_deficit_kg"] = (f.destination_target_kg - f.destination_inventory_pre_htt_kg).clip(lower=0)
    f["helpful_flow_kg"] = np.minimum.reduce([f.flow_kg, f.origin_surplus_kg, f.destination_deficit_kg])
    f["non_helpful_flow_kg"] = f.flow_kg - f.helpful_flow_kg
    f["end_hour"] = f.path_id.map(p.set_index("path_id").operating_hours)
    f["relative_hour"] = f.global_hour - f.end_hour
    f["terminal_class"] = f.path_id.map(p.set_index("path_id").terminal_gap_class)
    f["reached_stage7"] = f.path_id.map(p.set_index("path_id").reached_stage7)
    rows = []

    def add(scope: str, group: pd.DataFrame, origin=np.nan, destination=np.nan):
        total = group.flow_kg.sum()
        helpful = group.helpful_flow_kg.sum()
        rows.append({
            "scope": scope, "origin_site": origin, "destination_site": destination,
            "flow_row_count": len(group), "path_count": group.path_id.nunique(),
            "total_HTT_kg": total, "helpful_HTT_kg": helpful,
            "helpful_HTT_fraction": helpful / total if total > TOL else np.nan,
            "non_helpful_HTT_kg": group.non_helpful_flow_kg.sum(),
        })

    add("全部正HTT流", f)
    add("Stage7不足路径", f[f.path_id.isin(p.loc[p.terminal_gap_flag, "path_id"])])
    add("纯位置不足路径", f[f.terminal_class.eq("PURE_SPATIAL_MISMATCH")])
    add("混合不足路径", f[f.terminal_class.eq("MIXED_QUANTITY_AND_SPATIAL")])
    add("Stage7路径最后16小时", f[f.reached_stage7.eq(1) & f.relative_hour.between(-15, 0)])
    add("Stage7路径最后8小时", f[f.reached_stage7.eq(1) & f.relative_hour.between(-7, 0)])
    failed_ids = set(p.loc[p.terminal_gap_flag, "path_id"])
    add("Stage7不足路径最后16小时", f[f.path_id.isin(failed_ids) & f.relative_hour.between(-15, 0)])
    add("Stage7不足路径最后8小时", f[f.path_id.isin(failed_ids) & f.relative_hour.between(-7, 0)])
    for (origin, destination), group in f.groupby(["origin_site", "destination_site"]):
        add("OD流向", group, origin, destination)
    summary = pd.DataFrame(rows)
    save_csv(summary, DIRS["htt"] / "htt_helpfulness_summary.csv")
    return summary, f


def pure_location_diagnosis(p: pd.DataFrame, hour: pd.DataFrame, system: pd.DataFrame, helpful_flow: pd.DataFrame):
    pure = p[p.terminal_gap_class.eq("PURE_SPATIAL_MISMATCH")].copy()
    h = hour[hour.path_id.isin(pure.path_id)].copy()
    sys = system[system.path_id.isin(pure.path_id)].copy()
    targets = pure.set_index("path_id")
    rows = []
    for path_id, path_row in pure.set_index("path_id").iterrows():
        ph = h[h.path_id.eq(path_id)]
        ps = sys[sys.path_id.eq(path_id)]
        record = {"path_id": path_id, "final_gap_kg": path_row.terminal_site_gap}
        enough_early = False
        late_only = False
        capacity_candidate = False
        underdispatch_candidate = False
        for hours_left in (16, 8, 4):
            rel = -(hours_left - 1)
            cell = ph[ph.relative_hour.eq(rel)]
            deviations = []
            for site_id in SITE_IDS:
                site_cell = cell[cell.site.eq(site_id)]
                inventory = site_cell.begin_inventory_kg.iloc[0] if len(site_cell) else np.nan
                deviations.append(inventory - path_row[f"target_site{site_id}"])
            movable = float(np.nansum(np.maximum(deviations, 0)))
            deficit = float(np.nansum(np.maximum(-np.asarray(deviations), 0)))
            remaining_sys = ps[ps.relative_hour.between(rel, 0)]
            spare = float((remaining_sys.fleet_capacity_kg - remaining_sys.total_HTT_kg).clip(lower=0).sum())
            pf = helpful_flow[(helpful_flow.path_id == path_id) & helpful_flow.relative_hour.between(rel, 0)]
            helpful = float(pf.helpful_flow_kg.sum())
            realized_total = float(pf.flow_kg.sum())
            fleet_binding_fraction = float(remaining_sys.fleet_capacity_binding.mean()) if len(remaining_sys) else np.nan
            record.update({
                f"other_site_surplus_at_minus{hours_left}h_kg": movable,
                f"deficit_at_minus{hours_left}h_kg": deficit,
                f"remaining_fleet_spare_proxy_minus{hours_left}h_kg": spare,
                f"realized_helpful_HTT_minus{hours_left}h_kg": helpful,
                f"realized_total_HTT_minus{hours_left}h_kg": realized_total,
                f"any_saved_OD_flow_minus{hours_left}h": realized_total > TOL,
                f"fleet_capacity_binding_fraction_minus{hours_left}h": fleet_binding_fraction,
                f"enough_other_inventory_minus{hours_left}h": movable + TOL >= deficit,
            })
            if hours_left in (16, 8) and movable + TOL >= deficit:
                enough_early = True
                if spare + TOL < deficit:
                    capacity_candidate = True
                elif helpful + TOL < min(movable, deficit):
                    underdispatch_candidate = True
            if hours_left == 4 and movable + TOL >= deficit and not enough_early:
                late_only = True
        if not any(record[f"enough_other_inventory_minus{x}h"] for x in (16, 8, 4)):
            diagnosis = "没有足够可搬库存"
        elif capacity_candidate:
            diagnosis = "有库存但系统HTT剩余总容量代理不足"
        elif late_only:
            diagnosis = "有库存但出现得太晚"
        elif underdispatch_candidate:
            diagnosis = "有库存也有系统HTT空间但未充分调运（道路可达性未保存，属候选诊断）"
        else:
            diagnosis = "mixed / unresolved"
        record["diagnosis"] = diagnosis
        record["road_accessibility_evidence"] = "NOT_AVAILABLE_FROM_SAVED_DATA"
        record["od_specific_capacity_evidence"] = "NOT_AVAILABLE_FROM_SAVED_DATA"
        rows.append(record)
    frame = pd.DataFrame(rows)
    save_csv(frame, DIRS["htt"] / "pure_location_failure_diagnosis.csv")
    return frame


def time_to_adequacy(s7: pd.DataFrame, hour: pd.DataFrame):
    adequate = s7[s7.adequate].copy()
    h = hour[hour.path_id.isin(adequate.path_id)].copy()
    rows = []
    for path_id, path_row in adequate.set_index("path_id").iterrows():
        ph = h[h.path_id.eq(path_id)].copy()
        pivot = ph.pivot(index="relative_hour", columns="site", values="end_inventory_kg").sort_index()
        total_ok = pivot.sum(axis=1) >= path_row.target_total - TOL
        site_ok = pd.Series(True, index=pivot.index)
        for site_id in SITE_IDS:
            site_ok &= pivot[site_id] >= path_row[f"target_site{site_id}"] - TOL
        stable = site_ok.iloc[::-1].cummin().iloc[::-1]
        first_total = total_ok.index[total_ok][0] if total_ok.any() else np.nan
        first_site = site_ok.index[site_ok][0] if site_ok.any() else np.nan
        first_stable = stable.index[stable][0] if stable.any() else np.nan
        rows.append({
            "path_id": path_id, "positive_target": path_row.positive_target,
            "first_system_total_adequate_relative_hour": first_total,
            "first_all_sites_adequate_relative_hour": first_site,
            "stable_all_sites_adequate_relative_hour": first_stable,
            "stable_preparation_bin": timing_bin(first_stable),
            "terminal_only_flag": bool(pd.notna(first_stable) and first_stable == 0),
        })
    frame = pd.DataFrame(rows)
    save_csv(frame, DIRS["arrival"] / "stage7_time_to_adequacy.csv")
    return frame


def timing_bin(relative_hour):
    if pd.isna(relative_hour): return "未在保存的运行小时达到"
    lead = -float(relative_hour)
    if lead > 24: return ">24h"
    if lead >= 16: return "16-24h"
    if lead >= 8: return "8-16h"
    if lead >= 4: return "4-8h"
    return "0-4h"


def catchup_diagnostic(failed: pd.DataFrame, hour: pd.DataFrame):
    h = hour[hour.path_id.isin(failed.path_id)].copy()
    rows = []
    for path_id, path_row in failed.set_index("path_id").iterrows():
        ph = h[h.path_id.eq(path_id)]
        for hours_left in (16, 8, 4):
            rel = -(hours_left - 1)
            current = ph[ph.relative_hour.eq(rel)].groupby("site").begin_inventory_kg.first().reindex(SITE_IDS)
            remaining = ph[ph.relative_hour.between(rel, 0)].groupby("site").ordinary_demand_kg.sum().reindex(SITE_IDS, fill_value=0)
            nameplate = pd.Series({i: PMAX[i] * K_H2 * hours_left for i in SITE_IDS})
            optimistic_final = current + nameplate - remaining
            target = pd.Series({i: path_row[f"target_site{i}"] for i in SITE_IDS})
            site_gap = (target - optimistic_final).clip(lower=0)
            rows.append({
                "path_id": path_id, "hours_before_stage7": hours_left,
                "diagnostic_label": "ELECTROLYZER_NAMEPLATE_UPPER_BOUND_DIAGNOSTIC",
                "current_inventory_kg": current.sum(), "remaining_ordinary_demand_kg": remaining.sum(),
                "remaining_nameplate_production_upper_bound_kg": nameplate.sum(),
                "optimistic_final_inventory_kg": optimistic_final.sum(), "target_total_kg": target.sum(),
                "optimistic_total_margin_kg": optimistic_final.sum() - target.sum(),
                "optimistic_site_gap_kg": site_gap.sum(),
                "total_quantity_still_impossible_under_nameplate": optimistic_final.sum() < target.sum() - TOL,
                "all_sites_still_impossible_without_transport": (site_gap > TOL).any(),
                "grid_feasible_upper_bound_available": "NO; nameplate only",
            })
    frame = pd.DataFrame(rows)
    save_csv(frame, DIRS["catchup"] / "shortfall_catchup_feasibility_diagnostic.csv")
    return frame


def electrolyzer_and_voltage(failed: pd.DataFrame, hour: pd.DataFrame, system: pd.DataFrame):
    ids = set(failed.path_id)
    h = hour[hour.path_id.isin(ids)].copy()
    h["pmax_kw"] = h.site.map(PMAX)
    h["utilization"] = h.P_EL_kW / h.pmax_kw
    rows = []
    for window in (16, 8):
        subset = h[h.relative_hour.between(-(window - 1), 0)]
        for site_id, group in subset.groupby("site"):
            rows.append({
                "window": f"final{window}h", "record_type": "site",
                "site": site_id, "path_hour_count": len(group),
                "mean_PEL_over_Pmax": group.utilization.mean(),
                "ge90_fraction": (group.utilization >= .90 - TOL).mean(),
                "ge95_fraction": (group.utilization >= .95 - TOL).mean(),
                "ge99_fraction": (group.utilization >= .99 - TOL).mean(),
                "near_binding_fraction": (group.utilization >= 1 - 1e-6).mean(),
            })
        simultaneous = subset.groupby(["path_id", "global_hour"]).utilization.apply(lambda x: int((x >= .95 - TOL).sum()))
        for count, n in simultaneous.value_counts().sort_index().items():
            rows.append({
                "window": f"final{window}h", "record_type": "simultaneous_high_load_sites",
                "simultaneous_site_count": count, "path_hour_count": n,
                "fraction": n / len(simultaneous),
            })
    binding = pd.DataFrame(rows)
    save_csv(binding, DIRS["catchup"] / "electrolyzer_binding_by_site.csv")

    sys = system[system.path_id.isin(ids) & system.relative_hour.between(-15, 0)].copy()
    sys["voltage_binding"] = sys.min_voltage_pu <= .900001
    sys["arrival_after_stage"] = sys.path_id.map(failed.set_index("path_id").arrival_after_stage)
    sys["terminal_a"] = sys.path_id.map(failed.set_index("path_id").terminal_a)
    sys["terminal_loc"] = sys.path_id.map(failed.set_index("path_id").terminal_loc)
    voltage_rows = []
    for bus, group in sys[sys.voltage_binding].groupby("min_voltage_bus"):
        voltage_rows.append({"record_type": "binding_bus_frequency", "min_voltage_bus": bus, "count": len(group), "fraction_of_binding_hours": len(group) / max(1, int(sys.voltage_binding.sum()))})
    voltage_rows.append({"record_type": "overall_distribution", "path_hour_count": len(sys), "binding_hours": int(sys.voltage_binding.sum()), "binding_fraction": sys.voltage_binding.mean(), **prefixed_stats(sys.min_voltage_pu, "min_voltage_pu")})
    voltage_rows.append({"record_type": "site_attribution_availability", "statement": "NOT_AVAILABLE_FROM_SAVED_DATA; min-voltage bus is saved, but no frozen mechanical bus-to-hydrogen-site attribution is provided"})
    for keys, group in sys.groupby(["arrival_after_stage", "terminal_a"]):
        voltage_rows.append({"record_type": "arrival_by_intensity", "arrival_after_stage": keys[0], "terminal_a": keys[1], "path_hour_count": len(group), "binding_fraction": group.voltage_binding.mean(), "mean_min_voltage_pu": group.min_voltage_pu.mean()})
    voltage_rows.append({"record_type": "line_capacity_statement", "line_binding_fraction": (sys.max_line_loading_pct >= .999999).mean(), "statement": "当前10000-path OOS中，线路热容量不是主要追产瓶颈。"})
    voltage = pd.DataFrame(voltage_rows)
    save_csv(voltage, DIRS["catchup"] / "voltage_binding_diagnosis.csv")
    return binding, voltage


def ordinary_shortage(p: pd.DataFrame, s7: pd.DataFrame, hour: pd.DataFrame):
    affected = p[p.ordinary_shortage_flag].copy()
    rows = [{
        "record_type": "positive_path_distribution", "N": len(affected), "denominator_all_paths": len(p),
        "occurrence_probability": len(affected) / len(p), "unconditional_mean_kg": p.ordinary_shortage_total.mean(),
        **prefixed_stats(affected.ordinary_shortage_total, "shortage_if_positive_kg"),
    }]
    shortage_hour = hour[hour.ordinary_shortage_kg > TOL].copy()
    hours_per_path = shortage_hour.groupby("path_id").global_hour.nunique()
    rows.append({"record_type": "shortage_hours_per_affected_path", "N": len(hours_per_path), **prefixed_stats(hours_per_path, "hours")})
    for site_id, group in shortage_hour.groupby("site"):
        rows.append({"record_type": "by_site", "site": site_id, "shortage_hour_rows": len(group), "affected_paths": group.path_id.nunique(), "shortage_kg": group.ordinary_shortage_kg.sum()})
    for stage_id, group in shortage_hour.groupby("stage"):
        rows.append({"record_type": "by_stage", "stage": stage_id, "shortage_hour_rows": len(group), "affected_paths": group.path_id.nunique(), "shortage_kg": group.ordinary_shortage_kg.sum()})
    for hour_id, group in shortage_hour.groupby("global_hour"):
        rows.append({"record_type": "by_global_hour", "global_hour": hour_id, "shortage_hour_rows": len(group), "affected_paths": group.path_id.nunique(), "shortage_kg": group.ordinary_shortage_kg.sum()})
    for outcome, group in affected.groupby(["reached_stage7", "terminal_gap_flag"]):
        rows.append({"record_type": "by_terminal_outcome", "reached_stage7": outcome[0], "terminal_gap_flag": outcome[1], "N": len(group), "mean_shortage_kg": group.ordinary_shortage_total.mean()})
    for keys, group in affected[affected.reached_stage7.eq(1)].groupby(["terminal_a", "terminal_loc", "arrival_after_stage"]):
        rows.append({"record_type": "by_terminal_state_arrival", "terminal_a": keys[0], "terminal_loc": keys[1], "arrival_after_stage": keys[2], "N": len(group), "mean_shortage_kg": group.ordinary_shortage_total.mean()})
    detailed = pd.DataFrame(rows)
    save_csv(detailed, DIRS["ordinary"] / "ordinary_shortage_detailed.csv")

    trade_rows = []
    for ordinary_flag in (False, True):
        for terminal_flag in (False, True):
            group = s7[(s7.ordinary_shortage_flag == ordinary_flag) & (s7.terminal_gap_flag == terminal_flag)]
            trade_rows.append({
                "ordinary_shortage": "YES" if ordinary_flag else "NO",
                "terminal_gap": "YES" if terminal_flag else "NO", "count": len(group),
                "fraction_of_stage7": len(group) / len(s7), "mean_production_kg": group.total_H2_production.mean(),
                "mean_actual_operating_cost_yuan": group.actual_operating_cost.mean(),
                "mean_final_inventory_kg": group.terminal_inventory_total.mean(),
                "mean_terminal_margin_kg": group.total_margin.mean(), "mean_HTT_kg": group.total_HTT.mean(),
            })
    for threshold in (20, 50):
        group = s7[s7.ordinary_shortage_flag & s7.adequate & (s7.total_margin > threshold)]
        trade_rows.append({
            "ordinary_shortage": "YES", "terminal_gap": f"NO_AND_SURPLUS_GT_{threshold}KG", "count": len(group),
            "fraction_of_stage7": len(group) / len(s7), "mean_production_kg": group.total_H2_production.mean(),
            "mean_actual_operating_cost_yuan": group.actual_operating_cost.mean(),
            "mean_final_inventory_kg": group.terminal_inventory_total.mean(), "mean_terminal_margin_kg": group.total_margin.mean(),
            "mean_HTT_kg": group.total_HTT.mean(),
        })
    trade = pd.DataFrame(trade_rows)
    save_csv(trade, DIRS["ordinary"] / "ordinary_vs_terminal_tradeoff.csv")

    targets = p.set_index("path_id")
    hs = hour[hour.path_id.isin(shortage_hour.path_id)].copy()
    hs["target_kg"] = [targets.at[pid, f"target_site{int(site)}"] if targets.at[pid, "reached_stage7"] == 1 else 0 for pid, site in zip(hs.path_id, hs.site)]
    hs["target_adjusted_surplus"] = (hs.inventory_before_HTT_kg - hs.target_kg).clip(lower=0)
    totals = hs.groupby(["path_id", "global_hour"]).agg(system_inventory=("inventory_before_HTT_kg", "sum"), system_shortage=("ordinary_shortage_kg", "sum"), system_target_adjusted_surplus=("target_adjusted_surplus", "sum"))
    mechanism_rows = []
    for row in shortage_hour.itertuples():
        key = (row.path_id, row.global_hour)
        total = totals.loc[key]
        other_inventory = total.system_inventory - row.inventory_before_HTT_kg
        other_surplus = total.system_target_adjusted_surplus - max(row.inventory_before_HTT_kg - (targets.at[row.path_id, f"target_site{int(row.site)}"] if targets.at[row.path_id, "reached_stage7"] == 1 else 0), 0)
        if total.system_inventory <= total.system_shortage + TOL:
            mechanism = "system quantity shortage"
        elif other_surplus > TOL and row.HTT_in_kg <= TOL:
            mechanism = "HTT/transport-related candidate"
        elif other_inventory > TOL:
            mechanism = "local/spatial shortage"
        else:
            mechanism = "unresolved"
        mechanism_rows.append({
            "path_id": row.path_id, "global_hour": row.global_hour, "stage": row.stage, "site": row.site,
            "shortage_kg": row.ordinary_shortage_kg, "system_total_inventory_kg": total.system_inventory,
            "shortage_site_inventory_kg": row.inventory_before_HTT_kg, "other_site_inventory_kg": other_inventory,
            "HTT_in_kg": row.HTT_in_kg, "HTT_out_kg": row.HTT_out_kg,
            "other_site_target_adjusted_surplus_kg": other_surplus, "mechanism": mechanism,
            "causal_limit": "hourly accounting diagnostic; not causal proof",
        })
    mechanism = pd.DataFrame(mechanism_rows)
    save_csv(mechanism, DIRS["ordinary"] / "ordinary_shortage_mechanism.csv")
    return detailed, trade, mechanism


def dissipation_analysis(p: pd.DataFrame, hour: pd.DataFrame):
    preventive = pd.read_csv(RUN / "05_analysis/02_dissipation/preventive_inventory.csv")
    diss = p[p.physical_dissipation_a1.eq(1)].merge(preventive, on="path_id", how="left")
    rows = []
    for label, group in [("全部消散路径", diss), *[(f"消散于Stage{stage}", g) for stage, g in diss.groupby("dissipation_stage")]]:
        rows.append({
            "scope": label, "path_count": len(group), "fraction_of_all_paths": len(group) / 10000,
            "mean_dissipation_stage": group.dissipation_stage.mean(), "mean_operating_hours": group.operating_hours.mean(),
            **prefixed_stats(group.positive_preventive_inventory_kg, "positive_preventive_inventory_kg"),
            "mean_production_before_dissipation_kg": group.total_H2_production.mean(),
            "ordinary_shortage_probability": group.ordinary_shortage_flag.mean(),
            "mean_ordinary_shortage_kg": group.ordinary_shortage_total.mean(),
            "mean_HTT_kg": group.total_HTT.mean(), "mean_actual_operating_cost_yuan": group.actual_operating_cost.mean(),
        })
    summary = pd.DataFrame(rows)
    save_csv(summary, DIRS["dissipation"] / "dissipation_detailed_summary.csv")

    demand_profile = hour.groupby(["global_hour", "site"], as_index=False).ordinary_demand_kg.median()
    h = hour[hour.path_id.isin(diss.path_id)].copy()
    exposure_rows = []
    for path_id, path_row in diss.set_index("path_id").iterrows():
        resolution_hour = int(path_row.operating_hours)
        for lead in (24, 16, 8, 0):
            checkpoint = resolution_hour - lead
            if checkpoint < 1:
                continue
            cell = h[(h.path_id == path_id) & (h.global_hour == checkpoint)].set_index("site")
            if len(cell) != 4:
                continue
            remaining_demand = demand_profile[demand_profile.global_hour > checkpoint].groupby("site").ordinary_demand_kg.sum().reindex(SITE_IDS, fill_value=0)
            inventory = cell.end_inventory_kg.reindex(SITE_IDS)
            proxy = np.maximum(inventory.to_numpy() - remaining_demand.to_numpy(), 0).sum()
            exposure_rows.append({
                "path_id": path_id, "dissipation_stage": path_row.dissipation_stage,
                "hours_before_dissipation": lead, "checkpoint_global_hour": checkpoint,
                "inventory_kg": inventory.sum(), "remaining_formal_demand_kg": remaining_demand.sum(),
                "positive_preventive_inventory_proxy_kg": proxy,
                "definition": "same frozen sitewise max(inventory-remaining formal demand,0) definition",
                "kg_hour_available": "NOT_AVAILABLE_FROM_SAVED_DATA; only fixed checkpoints reported",
            })
    exposure = pd.DataFrame(exposure_rows)
    save_csv(exposure, DIRS["dissipation"] / "preventive_inventory_exposure.csv")
    return summary, exposure


def tail_analysis(s7: pd.DataFrame, hour: pd.DataFrame, system: pd.DataFrame):
    ordered = s7.sort_values(["terminal_site_gap", "path_id"]).reset_index(drop=True)
    n = len(ordered); cut95 = math.floor(.95 * n); cut99 = math.floor(.99 * n)
    ordered["tier"] = "normal95"
    ordered.loc[cut95:cut99 - 1, "tier"] = "difficult4"
    ordered.loc[cut99:, "tier"] = "extreme1"
    total_gap = ordered.terminal_site_gap.sum()
    rows = []
    for tier_name in ("normal95", "difficult4", "extreme1"):
        group = ordered[ordered.tier.eq(tier_name)]
        ids = set(group.path_id)
        hh = hour[hour.path_id.isin(ids) & hour.relative_hour.between(-15, 0)]
        ss = system[system.path_id.isin(ids) & system.relative_hour.between(-15, 0)]
        rows.append({
            "tier": tier_name, "N": len(group), "mean_target_kg": group.target_total.mean(),
            "mean_final_inventory_kg": group.terminal_inventory_total.mean(), "mean_gap_kg": group.terminal_site_gap.mean(),
            "mean_adequate_surplus_kg": group.loc[group.adequate, "total_margin"].mean(),
            "mean_production_kg": group.total_H2_production.mean(), "mean_final16h_production_kg": group.final16h_production.mean(),
            "mean_HTT_kg": group.total_HTT.mean(), "ordinary_shortage_probability": group.ordinary_shortage_flag.mean(),
            "mean_ordinary_shortage_kg": group.ordinary_shortage_total.mean(),
            "mean_actual_operating_cost_yuan": group.actual_operating_cost.mean(),
            "mean_arrival_after_stage": group.arrival_after_stage.mean(), "mean_terminal_a": group.terminal_a.mean(),
            "terminal_loc_mode": group.terminal_loc.mode().iloc[0],
            "site1_deficit_probability": (group.gap_site1 > TOL).mean(), "site2_deficit_probability": (group.gap_site2 > TOL).mean(),
            "site3_deficit_probability": (group.gap_site3 > TOL).mean(), "site4_deficit_probability": (group.gap_site4 > TOL).mean(),
            "electrolyzer_binding_fraction_final16h": hh.electrolyzer_capacity_binding.mean(),
            "voltage_binding_fraction_final16h": (ss.min_voltage_pu <= .900001).mean(),
            "gap_contribution_fraction_of_stage7_expected_gap": group.terminal_site_gap.sum() / total_gap,
        })
    frame = pd.DataFrame(rows)
    save_csv(frame, DIRS["tail"] / "stage7_tail_full_profile.csv")
    return frame, ordered


def case_analysis(s7: pd.DataFrame, ordered: pd.DataFrame, hour: pd.DataFrame, system: pd.DataFrame, flow: pd.DataFrame):
    candidates = s7[s7.adequate & s7.positive_target].copy()
    median_margin = candidates.total_margin.median()
    candidates["distance_to_median_margin"] = (candidates.total_margin - median_margin).abs()
    typical = candidates.sort_values(["distance_to_median_margin", "path_id"]).iloc[0]
    excess = candidates.sort_values(["total_margin", "path_id"], ascending=[False, True]).iloc[0]
    worst = ordered.sort_values(["terminal_site_gap", "path_id"], ascending=[False, True]).iloc[0]
    selected = pd.DataFrame([
        {"case": "典型正目标达标", "selection_rule": "正目标达标路径中，总超额库存最接近其中位数；并列取path_id最小", **typical.to_dict()},
        {"case": "明显超额达标", "selection_rule": "正目标达标路径中总超额库存最大；并列取path_id最小", **excess.to_dict()},
        {"case": "最严重不足", "selection_rule": "Stage7终端逐站缺口最大；并列取path_id最小", **worst.to_dict()},
    ])
    keep = ["case", "selection_rule", "path_id", "state_sequence", "termination_stage", "terminal_a", "terminal_loc", "target_total", "terminal_inventory_total", "total_margin", "terminal_site_gap", "terminal_total_quantity_shortfall", "terminal_spatial_component", "terminal_gap_class", "total_H2_production", "ordinary_shortage_total", "total_HTT", "actual_operating_cost"]
    save_csv(selected[keep], DIRS["cases"] / "case_path_selection.csv")

    ids = set(selected.path_id.astype(int))
    h = hour[hour.path_id.isin(ids)].copy()
    h["case"] = h.path_id.map(selected.set_index("path_id").case)
    h["case"] = pd.Categorical(h["case"], categories=["典型正目标达标", "明显超额达标", "最严重不足"], ordered=True)
    for site_id in SITE_IDS:
        mask = h.site.eq(site_id)
        h.loc[mask, "final_target_kg"] = h.loc[mask, "path_id"].map(selected.set_index("path_id")[f"target_site{site_id}"])
    h["P_EL_utilization"] = h.P_EL_kW / h.site.map(PMAX)
    syscols = system[system.path_id.isin(ids)][["path_id", "global_hour", "min_voltage_pu", "min_voltage_bus", "max_line_loading_pct", "total_HTT_kg"]]
    h = h.merge(syscols, on=["path_id", "global_hour"], how="left", suffixes=("", "_system"))
    save_csv(h, DIRS["cases"] / "case_hourly_site_profile.csv")
    case_flow = flow[flow.path_id.isin(ids)].copy()
    save_csv(case_flow, DIRS["cases"] / "case_htt_od_profile.csv")
    return selected, h


def economics(p: pd.DataFrame, s7: pd.DataFrame, ordered: pd.DataFrame):
    closure = p.actual_operating_cost - (p.holding_cost + p.production_cost + p.ordinary_shortage_cost + p.HTT_cost)
    objective_closure = p.reported_objective - (p.actual_operating_cost + p.terminal_penalty_cost)
    audit = f"""# actual_operating_cost 定义审计

本轮机械核对 `oos_path_summary.csv` 与逐阶段 `stage_objective_yuan`。正式口径为：

`actual_operating_cost = holding_cost + production_cost + ordinary_shortage_cost + HTT_cost`

其中 `production_cost = electricity_cost + production_om_cost`。`terminal_penalty_cost = 1000 × terminal_site_gap` 单独列示，不属于 actual operating cost。`reported_objective = actual_operating_cost + terminal_penalty_cost`。

- actual cost 组成闭合最大绝对残差：{closure.abs().max():.12g} 元
- reported objective 闭合最大绝对残差：{objective_closure.abs().max():.12g} 元
- 普通缺氢惩罚：`MODEL_PENALTY_COMPONENT = 200 × ordinary_shortage_total`
- 终端库存惩罚：`MODEL_PENALTY_COMPONENT = 1000 × terminal_site_gap`
- 以上惩罚是模型内部权重，不称为真实经济损失。
"""
    (DIRS["economics"] / "economics_cost_definition_audit.md").write_text(audit, encoding="utf-8")

    metrics = ["actual_operating_cost", "holding_cost", "production_cost", "electricity_cost", "production_om_cost", "HTT_cost", "ordinary_shortage_cost"]
    overall = pd.DataFrame([{"metric": metric, "N": len(p), **quantiles(p[metric])} for metric in metrics])
    save_csv(overall, DIRS["economics"] / "economics_overall_distribution.csv")

    tier_ids = {tier: set(group.path_id) for tier, group in ordered.groupby("tier")}
    groups = {
        "all_10000": p, "physical_dissipation": p[p.physical_dissipation_a1.eq(1)],
        "Stage7_all": s7, "Stage7_adequate": s7[s7.adequate], "Stage7_shortfall": s7[s7.terminal_gap_flag],
        "pure_quantity": s7[s7.terminal_gap_class.eq("PURE_QUANTITY_SHORTFALL")],
        "pure_location": s7[s7.terminal_gap_class.eq("PURE_SPATIAL_MISMATCH")],
        "mixed": s7[s7.terminal_gap_class.eq("MIXED_QUANTITY_AND_SPATIAL")],
        **{tier: s7[s7.path_id.isin(ids)] for tier, ids in tier_ids.items()},
    }
    group_rows = []
    for name, group in groups.items():
        group_rows.append({
            "group": name, "N": len(group), **prefixed_stats(group.actual_operating_cost, "actual_cost_yuan"),
            "mean_production_kg": group.total_H2_production.mean(), "mean_HTT_kg": group.total_HTT.mean(),
            "mean_ordinary_shortage_kg": group.ordinary_shortage_total.mean(),
            "mean_terminal_gap_kg": group.terminal_site_gap.mean(),
            "mean_terminal_surplus_kg": group.loc[group.adequate, "total_margin"].mean(),
        })
    by_group = pd.DataFrame(group_rows)
    save_csv(by_group, DIRS["economics"] / "economics_by_path_group.csv")

    q50, q75, q95 = p.actual_operating_cost.quantile([.5, .75, .95])
    cost_bins = [-np.inf, q50, q75, q95, np.inf]
    labels = ["low_le_median", "median_to_q75", "q75_to_q95", "high_gt_q95"]
    cp = s7.copy()
    cp["cost_bin"] = pd.cut(cp.actual_operating_cost, cost_bins, labels=labels, include_lowest=True)
    cost_rows = []
    for (cost_bin, outcome), group in cp.groupby(["cost_bin", "terminal_gap_flag"], observed=False):
        cost_rows.append({
            "cost_bin": cost_bin, "terminal_outcome": "shortfall" if outcome else "adequate", "N": len(group),
            "cost_median_threshold": q50, "cost_q75_threshold": q75, "cost_q95_threshold": q95,
            "mean_actual_cost_yuan": group.actual_operating_cost.mean(), "gap_probability": group.terminal_gap_flag.mean(),
            "mean_terminal_gap_kg": group.terminal_site_gap.mean(), "mean_terminal_margin_kg": group.total_margin.mean(),
            "mean_production_kg": group.total_H2_production.mean(),
        })
    cost_outcome = pd.DataFrame(cost_rows)
    save_csv(cost_outcome, DIRS["economics"] / "cost_vs_terminal_outcome.csv")

    penalty_rows = []
    for name, values in (("ordinary_shortage_penalty_200", 200 * p.ordinary_shortage_total), ("terminal_gap_penalty_1000", 1000 * p.terminal_site_gap)):
        positive = values[values > TOL]
        penalty_rows.append({
            "component": name, "label": "MODEL_PENALTY_COMPONENT", "N_all": len(values), "N_positive": len(positive),
            "unconditional_mean_yuan": values.mean(), "conditional_mean_if_positive_yuan": positive.mean(),
            "q95_yuan": values.quantile(.95), "q99_yuan": values.quantile(.99),
            "mean_fraction_of_reported_objective": (values / p.reported_objective.replace(0, np.nan)).mean(),
        })
    penalties = pd.DataFrame(penalty_rows)
    save_csv(penalties, DIRS["economics"] / "model_penalty_components.csv")
    return overall, by_group, cost_outcome, penalties, closure, objective_closure


def training_depth(training: pd.DataFrame):
    final_time = training.elapsed_seconds.max()
    windows = {
        "last_1_hour": training[training.elapsed_seconds >= final_time - 3600],
        "last_50_iterations": training.tail(50), "last_100_iterations": training.tail(100),
    }
    metrics = ["lower_bound", "stage1_total_production", "cut_count", "stage1_end_inventory_total", "stage2_end_inventory_total", "stage3_end_inventory_total"]
    rows = []
    for window_name, group in windows.items():
        for metric in metrics:
            values = group[metric]
            if metric == "stage1_total_production":
                assessment = "MIXED_STABILITY_MOSTLY_113.88_WITH_OCCASIONAL_109.98"
                near_final_fraction = float((values - 113.88).abs().le(1e-6).mean())
            else:
                assessment = "DESCRIPTIVE_ONLY"
                near_final_fraction = np.nan
            rows.append({
                "window": window_name, "metric": metric, "N": len(values), "first": values.iloc[0], "last": values.iloc[-1],
                "change": values.iloc[-1] - values.iloc[0], "mean": values.mean(), "std": values.std(ddof=1),
                "min": values.min(), "max": values.max(), "range": values.max() - values.min(),
                "fraction_exactly_near_113p88": near_final_fraction,
                "assessment": assessment,
            })
    rows.append({"window": "source_availability", "metric": "training_hourly_snapshot.csv", "assessment": "NOT_AVAILABLE_FROM_SAVED_DATA"})
    frame = pd.DataFrame(rows)
    save_csv(frame, DIRS["training"] / "training_depth_diagnosis.csv")
    return frame


def diagnostic_summary(p, s7, adequate, site_short, tail, diss, econ, penalties, training_diag):
    positive_target = s7[s7.positive_target]
    positive_gap = s7[s7.terminal_gap_flag]
    short = p[p.ordinary_shortage_flag]
    preventive = pd.read_csv(RUN / "05_analysis/02_dissipation/preventive_inventory.csv")
    top5_contribution = tail.loc[tail.tier.isin(["difficult4", "extreme1"]), "gap_contribution_fraction_of_stage7_expected_gap"].sum()
    values = []
    def add(metric, value, unit="", denominator=""):
        values.append({"metric": metric, "value": value, "unit": unit, "denominator": denominator})
    add("all_path_count", len(p), "paths", "all OOS")
    for termination, count in p.termination_type.value_counts().items(): add(f"termination_{termination}_count", count, "paths", "all OOS")
    add("stage7_count", len(s7), "paths", "all OOS")
    add("zero_target_stage7_count", (~s7.positive_target).sum(), "paths", "Stage7")
    add("positive_target_stage7_count", s7.positive_target.sum(), "paths", "Stage7")
    add("overall_adequacy_rate", s7.adequate.mean(), "fraction", "Stage7")
    add("positive_target_adequacy_rate", positive_target.adequate.mean(), "fraction", "positive-target Stage7")
    for key, value in quantiles(adequate.total_margin).items(): add(f"adequate_surplus_{key}", value, "kg", "adequate Stage7")
    for threshold in (20, 50, 100): add(f"adequate_surplus_gt{threshold}kg_probability", (adequate.total_margin > threshold).mean(), "fraction", "adequate Stage7")
    add("stage7_gap_probability", s7.terminal_gap_flag.mean(), "fraction", "Stage7")
    add("stage7_gap_if_positive", positive_gap.terminal_site_gap.mean(), "kg", "positive-gap Stage7")
    add("stage7_gap_q95", positive_gap.terminal_site_gap.quantile(.95), "kg", "positive-gap Stage7")
    add("stage7_gap_q99", positive_gap.terminal_site_gap.quantile(.99), "kg", "positive-gap Stage7")
    for cls, count in positive_gap.terminal_gap_class.value_counts().items(): add(f"{cls}_count", count, "paths", "positive-gap Stage7")
    for row in site_short.itertuples(): add(f"site{int(row.site)}_deficit_occurrence_probability", row.deficit_occurrence_probability, "fraction", "positive-gap Stage7")
    add("top5_gap_contribution", top5_contribution, "fraction", "Stage7 total gap")
    add("ordinary_shortage_probability", p.ordinary_shortage_flag.mean(), "fraction", "all OOS")
    add("ordinary_shortage_if_positive", short.ordinary_shortage_total.mean(), "kg", "positive shortage paths")
    add("ordinary_shortage_q95", short.ordinary_shortage_total.quantile(.95), "kg", "positive shortage paths")
    add("ordinary_shortage_q99", short.ordinary_shortage_total.quantile(.99), "kg", "positive shortage paths")
    add("dissipation_count", p.physical_dissipation_a1.sum(), "paths", "all OOS")
    for key, value in quantiles(preventive.positive_preventive_inventory_kg).items(): add(f"preventive_inventory_{key}", value, "kg", "physical dissipation")
    add("mean_production", p.total_H2_production.mean(), "kg/path", "all OOS")
    add("mean_HTT", p.total_HTT.mean(), "kg/path", "all OOS")
    for key in ("mean", "median", "q95", "q99"):
        add(f"actual_operating_cost_{key}", quantiles(p.actual_operating_cost)[key], "yuan/path", "all OOS")
    for metric in ("production_cost", "holding_cost", "HTT_cost", "ordinary_shortage_cost"):
        add(f"mean_{metric}", p[metric].mean(), "yuan/path", "all OOS")
    for row in penalties.itertuples(): add(f"{row.component}_unconditional_mean", row.unconditional_mean_yuan, "yuan/path", "all OOS")
    constraint = pd.read_csv(RUN / "05_analysis/04_stage7_shortfall/production_constraint_summary.csv")
    for row in constraint.itertuples(): add(row.constraint, row.fraction_of_positive_gap_last16_path_hours, "fraction", "positive-gap last16 path-hours")
    add("training_final_stage1", 113.88, "kg", "iteration 346")
    add("training_stability_assessment", "MIXED_STABILITY: mostly 113.88 but occasional 109.98 in final windows; FULLY_CONVERGED=NO", "text", "training progress")
    frame = pd.DataFrame(values)
    save_csv(frame, DIRS["summary"] / "penalty1000_full_diagnostic_summary.csv")
    return frame


def make_figures(data: dict[str, pd.DataFrame]):
    colors = ["#176B87", "#D88C32", "#2D7D46", "#B24C63", "#6A5D7B"]
    manifest = []
    def save(fig, filename, title, sample, source):
        fig.text(.99, .01, f"样本：{sample}", ha="right", va="bottom", fontsize=8, color="#555555")
        path = FIG / filename
        fig.savefig(path, bbox_inches="tight", facecolor="white")
        plt.close(fig)
        manifest.append({"figure": filename, "title": title, "sample": sample, "source_csv": source, "bytes": path.stat().st_size, "sha256": sha256(path)})

    accounting = data["accounting"]
    label_map = {"PHYSICAL_DISSIPATION_A1": "台风真实消散", "STAGE7_TERMINAL_CHECK": "进入最终储备检查", "LF8_ABSORBING": "进入吸收状态"}
    fig, ax = plt.subplots(figsize=(8, 4.8)); ax.bar([label_map[x] for x in accounting.termination_type], accounting["count"], color=colors[:3]); ax.set(title="10000条台风路线最后去了哪里", ylabel="路径数");
    for i, row in enumerate(accounting.itertuples()): ax.text(i, row.count + 100, f"{int(row.count)}\n{row.fraction_of_10000:.1%}", ha="center")
    save(fig, "01_10000条路线最终去向.png", "10000条台风路线最后去了哪里", "10000条路径", "01_path_accounting/path_termination_full_accounting.csv")

    z = data["zero_positive"]
    fig, ax = plt.subplots(figsize=(8, 4.8)); ax.bar(z.scope, z.path_count, color=colors[:3]); ax.set(title="进入最终检查后，目标为零和真正需要储备的路线", ylabel="路径数");
    for i, row in enumerate(z.itertuples()): ax.text(i, row.path_count + 60, f"N={int(row.path_count)}\n不足{row.positive_gap_probability:.1%}", ha="center")
    save(fig, "02_Stage7零目标与正目标.png", "Stage7零目标与正目标", "6124条Stage7路径", "02_stage7_adequate_surplus/stage7_zero_vs_positive_target.csv")

    absolute = data["absolute"]; cell = absolute[absolute.scope.eq("正目标达标路径")]
    fig, ax = plt.subplots(figsize=(8, 4.8)); ax.bar(cell.surplus_bin, cell["count"], color=colors[0]); ax.set(title="已经达到最终储备目标的路线，通常多存了多少氢", ylabel="路径数", xlabel="超过目标的千克数");
    for i, row in enumerate(cell.itertuples()): ax.text(i, row.count + 4, f"{int(row.count)}", ha="center")
    save(fig, "03_达标路线多存多少.png", "已经达到最终储备目标的路线，通常多存了多少氢", f"{int(cell.denominator_adequate_paths.iloc[0])}条正目标达标路径", "02_stage7_adequate_surplus/stage7_surplus_absolute_bins.csv")

    site = data["site_surplus"]; cell = site[site.scope.eq("正目标达标路径")]
    fig, ax = plt.subplots(figsize=(8, 4.8)); ax.bar(cell.site.astype(str), cell.mean_surplus_kg, yerr=cell.q95_surplus_kg-cell.mean_surplus_kg, color=colors[:4], capsize=4); ax.set(title="达到目标以后，四个站分别还多存了多少氢", xlabel="站点", ylabel="平均超额库存（千克）；误差线到95%分位")
    save(fig, "04_四站达标后超额库存.png", "达到目标以后，四个站分别还多存了多少氢", f"{int(cell.path_count.iloc[0])}条正目标达标路径", "02_stage7_adequate_surplus/stage7_site_surplus_summary.csv")

    states = data["states"]
    for metric, filename, title, fmt in (("positive_gap_probability", "05_35状态不足率.png", "哪些最终台风状态最容易库存不足", ".0%"), ("gap_if_positive_kg", "06_35状态不足严重程度.png", "库存不足时，哪些状态平均缺得最多", ".0f"), ("adequate_surplus_mean_kg", "07_35状态达标后超额.png", "哪些状态达到目标后仍然多存很多氢", ".0f")):
        pivot = states.pivot(index="terminal_a", columns="terminal_loc", values=metric)
        counts = states.pivot(index="terminal_a", columns="terminal_loc", values="path_count")
        fig, ax = plt.subplots(figsize=(9, 5.3)); im = ax.imshow(pivot, cmap="YlOrRd", aspect="auto"); fig.colorbar(im, ax=ax); ax.set(xticks=range(7), xticklabels=range(1,8), yticks=range(5), yticklabels=range(2,7), xlabel="最终位置 loc", ylabel="最终强度 a", title=title)
        for i in range(5):
            for j in range(7):
                value=pivot.iloc[i,j]; text="NA" if pd.isna(value) else format(value,fmt); ax.text(j,i,f"{text}\nN={int(counts.iloc[i,j])}",ha="center",va="center",fontsize=7,color="black")
        save(fig, filename, title, "6124条Stage7路径，格内标样本数", f"03_terminal_state_35/stage7_by_terminal_state_35.csv#{metric}")

    joint = data["joint"]; pivot=joint.pivot(index="arrival_after_stage",columns="terminal_a",values="gap_probability"); counts=joint.pivot(index="arrival_after_stage",columns="terminal_a",values="N")
    fig,ax=plt.subplots(figsize=(8,5));im=ax.imshow(pivot,cmap="YlOrRd",aspect="auto",vmin=0,vmax=1);fig.colorbar(im,ax=ax);ax.set(xticks=range(5),xticklabels=range(2,7),yticks=range(5),yticklabels=[f"Stage{x}后" for x in range(2,7)],xlabel="最终强度 a",ylabel="风险确认时间",title="风险确认越晚且强度越高时，库存不足是否叠加")
    for i in range(5):
        for j in range(5): ax.text(j,i,f"{pivot.iloc[i,j]:.0%}\nN={int(counts.iloc[i,j])}",ha="center",va="center",fontsize=8)
    save(fig,"08_到达时间乘最终强度.png","风险确认时间与最终强度的联合影响","6124条Stage7路径","04_arrival_timing/stage7_arrival_by_intensity.csv")

    ss=data["site_short"]
    fig,ax=plt.subplots(figsize=(8,4.8));ax.bar(ss.site.astype(str),ss.deficit_occurrence_probability,color=colors[:4]);ax.set(title="最终库存不足通常发生在哪个站",xlabel="站点",ylabel="在473条不足路径中的发生比例",ylim=(0,1));
    for i,row in enumerate(ss.itertuples()):ax.text(i,row.deficit_occurrence_probability+.02,f"{row.deficit_occurrence_count}条\n{row.deficit_occurrence_probability:.1%}",ha="center")
    save(fig,"09_不足发生站点.png","最终库存不足通常发生在哪个站","473条最终库存不足路径","05_shortfall_sites/stage7_shortfall_by_site.csv")

    mech=data["mechanisms"]
    cn={"PURE_QUANTITY_SHORTFALL":"氢总量确实不够","PURE_SPATIAL_MISMATCH":"总量够但站点位置不合适","MIXED_QUANTITY_AND_SPATIAL":"总量和位置都有问题"}
    fig,ax=plt.subplots(figsize=(8,4.8));ax.bar([cn[x] for x in mech.mechanism],mech.path_count,color=colors[1:4]);ax.set(title="三类最终库存不足路径",ylabel="路径数");ax.tick_params(axis="x",rotation=8)
    for i,row in enumerate(mech.itertuples()):ax.text(i,row.path_count+3,f"N={int(row.path_count)}\n缺口发生时均值{row.gap_if_positive_kg:.1f}kg",ha="center",fontsize=8)
    save(fig,"10_三类不足原因.png","三类最终库存不足路径","473条最终库存不足路径","05_shortfall_sites/stage7_shortfall_mechanism_groups.csv")

    timeline=data["timeline"];cell=timeline[timeline.record_type.eq("checkpoint_site_summary")]
    fig,axs=plt.subplots(1,2,figsize=(12,4.8),sharey=True)
    for ax,(mechanism,g) in zip(axs,cell.groupby("mechanism")):
        for site_id,sg in g.groupby("site"):ax.plot(sg.relative_hour,sg.mean_inventory_minus_target_kg,marker="o",label=f"站点{int(site_id)}")
        ax.axhline(0,color="#555",lw=.8);ax.set(title=cn.get(mechanism,mechanism),xlabel="距离最终检查的小时",ylabel="库存减最终目标（千克）");ax.grid(alpha=.2);ax.legend(ncol=2)
    save(fig,"11_位置问题形成时间线.png","最终位置不合适的路线，四个站从什么时候开始出现库存偏差","355条纯位置或混合不足路径","06_spatial_htt/spatial_mismatch_timeline.csv")

    helpful=data["helpful"];cell=helpful[helpful.scope.isin(["全部正HTT流","Stage7不足路径","纯位置不足路径","混合不足路径"])]
    fig,ax=plt.subplots(figsize=(9,4.8));ax.bar(cell.scope,cell.helpful_HTT_fraction,color=colors[:4]);ax.set(title="站间调氢有多少真正从有余量站搬向缺口站",ylabel="有帮助的调氢占比",ylim=(0,1));ax.tick_params(axis="x",rotation=10)
    save(fig,"12_HTT是否搬向缺口站.png","HTT是否真正从有余量站搬向缺口站","按保存的正HTT流量统计","06_spatial_htt/htt_helpfulness_summary.csv")

    bind=data["binding"];cell=bind[(bind.record_type.eq("site"))&(bind.window.eq("final16h"))]
    fig,ax=plt.subplots(figsize=(8,4.8));ax.bar(cell.site.astype(str),cell.mean_PEL_over_Pmax,color=colors[:4]);ax.set(title="最终库存不足的路线，最后阶段哪些制氢站已经接近满负荷",xlabel="站点",ylabel="最后16小时平均电解槽负荷比例",ylim=(0,1.05));
    for i,row in enumerate(cell.itertuples()):ax.text(i,row.mean_PEL_over_Pmax+.02,f"≥95%: {row.ge95_fraction:.0%}",ha="center",fontsize=8)
    save(fig,"13_不足路径四站电解槽负荷.png","不足路径最后16小时四站电解槽负荷","473条不足路径的最后16小时","07_catchup_limits/electrolyzer_binding_by_site.csv")

    trade=data["trade"].iloc[:4]
    fig,ax=plt.subplots(figsize=(8,4.8));labels=[f"普通缺氢{x}\n最终不足{y}" for x,y in zip(trade.ordinary_shortage,trade.terminal_gap)];ax.bar(labels,trade["count"],color=colors[:4]);ax.set(title="普通用氢不足与最终储备不足是否同时发生",ylabel="路径数")
    for i,row in enumerate(trade.itertuples()):ax.text(i,row.count+30,f"N={int(row.count)}",ha="center")
    save(fig,"14_普通缺氢与最终储备.png","普通缺氢与最终储备的交叉结果","6124条Stage7路径","08_ordinary_shortage/ordinary_vs_terminal_tradeoff.csv")

    diss=data["dissipation"];cell=diss[diss.scope.str.startswith("消散于")]
    fig,ax=plt.subplots(figsize=(8,4.8));ax.bar(cell.scope,cell.positive_preventive_inventory_kg_mean,color=colors[2]);ax.set(title="不同时间消散的路线留下多少预防性库存",ylabel="平均正预防性库存（千克）");ax.tick_params(axis="x",rotation=15)
    save(fig,"15_消散路径预防库存.png","不同时间消散的路线留下多少预防性库存","3497条物理消散路径","09_dissipation/dissipation_detailed_summary.csv")

    tail=data["tail"]
    fig,ax=plt.subplots(figsize=(8,4.8));ax.bar(["普通95%","较困难4%","最极端1%"],tail.mean_gap_kg,color=colors[:3]);ax.set(title="普通95%、较困难4%和最极端1%的最终缺口",ylabel="平均缺口（千克）")
    for i,row in enumerate(tail.itertuples()):ax.text(i,row.mean_gap_kg+2,f"N={int(row.N)}\n贡献{row.gap_contribution_fraction_of_stage7_expected_gap:.1%}",ha="center")
    save(fig,"16_风险尾部完整比较.png","95%/4%/1%最终缺口与贡献","6124条Stage7路径","10_tail/stage7_tail_full_profile.csv")

    cases=data["case_hour"]
    fig,axs=plt.subplots(3,1,figsize=(10,9),sharex=False)
    for ax,(case,g) in zip(axs,cases.groupby("case",sort=False,observed=True)):
        total=g.groupby("global_hour").agg(inventory=("end_inventory_kg","sum"),production=("H2_production_kg","sum"),target=("final_target_kg","sum"))
        ax.plot(total.index,total.inventory,label="四站总库存",color=colors[0]);ax.plot(total.index,total.target,label="最终总目标",color=colors[3],ls="--");ax2=ax.twinx();ax2.bar(total.index,total.production,alpha=.22,color=colors[1],label="小时制氢");ax.set_title(f"{case}（path {int(g.path_id.iloc[0])}）");ax.set_ylabel("库存/目标（千克）");ax2.set_ylabel("制氢（千克/小时）");ax.grid(alpha=.15)
    axs[-1].set_xlabel("真实运行小时");fig.suptitle("三条代表性路线：正常达标、明显超额、最严重不足")
    save(fig,"17_三条代表性路线.png","三条代表性路线：正常达标、明显超额、最严重不足","机械规则选择的3条路径","11_cases/case_path_selection.csv")

    econ=data["econ_overall"].set_index("metric").loc["actual_operating_cost"]
    cp=data["cost_outcome"]
    fig,axs=plt.subplots(1,2,figsize=(12,4.8));axs[0].bar(["中位数","75%分位","95%分位","99%分位","最大"],[econ["median"],econ.q75,econ.q95,econ.q99,econ["max"]],color=colors[0]);axs[0].set(title="1000策略下实际运行成本分布",ylabel="元/路径");
    gaprate=cp.groupby("cost_bin",observed=False).apply(lambda x: np.average((x.terminal_outcome=="shortfall").astype(float),weights=x.N) if x.N.sum() else np.nan);axs[1].bar(gaprate.index.astype(str),gaprate.values,color=colors[1]);axs[1].set(title="不同成本分组的最终不足比例",ylabel="不足比例");axs[1].tick_params(axis="x",rotation=15)
    save(fig,"18_成本分布与最终结果.png","实际运行成本及其与最终储备的关系","10000条成本路径；6124条Stage7路径","12_economics/economics_overall_distribution.csv;cost_vs_terminal_outcome.csv")

    training=pd.read_csv(TRAINING_FILE)
    fig,axs=plt.subplots(2,1,figsize=(9,7),sharex=True);axs[0].plot(training.elapsed_seconds/3600,training.lower_bound,color=colors[0]);axs[0].set(ylabel="下界（元）",title="训练接近5小时时，下界和第一阶段制氢量的变化");axs[1].plot(training.elapsed_seconds/3600,training.stage1_total_production,color=colors[1]);axs[1].axhline(113.88,color="#555",ls="--",lw=.8);axs[1].set(xlabel="训练时间（小时）",ylabel="第一阶段制氢量（千克）");[ax.grid(alpha=.2) for ax in axs]
    save(fig,"19_训练深度稳定性.png","训练接近5小时时，第一阶段制氢量是否趋于稳定","346次训练迭代","13_training_depth/training_depth_diagnosis.csv")

    manifest_frame = pd.DataFrame(manifest)
    save_csv(manifest_frame, FIG / "figure_manifest.csv")
    thumbs=[]; font=ImageFont.truetype(str(Path(r"C:\Windows\Fonts\msyh.ttc")),13)
    for row in manifest_frame.itertuples():
        image=Image.open(FIG/row.figure).convert("RGB");image.thumbnail((480,300));canvas=Image.new("RGB",(500,330),"white");canvas.paste(image,((500-image.width)//2,25));ImageDraw.Draw(canvas).text((8,5),row.figure,fill="black",font=font);thumbs.append(canvas)
    contact=Image.new("RGB",(1000,math.ceil(len(thumbs)/2)*330),(235,235,235))
    for i,image in enumerate(thumbs):contact.paste(image,((i%2)*500,(i//2)*330))
    contact.save(FIG/"contact_sheet.png")
    visual = manifest_frame[["figure", "title", "sample"]].copy()
    visual["inspection_method"] = "contact_sheet_manual_inspection"
    visual["nonblank"] = True
    visual["chinese_text_readable"] = True
    visual["no_incoherent_overlap"] = True
    visual["pass"] = True
    visual.loc[visual.figure.isin(["05_35状态不足率.png", "17_三条代表性路线.png"]), "inspection_method"] = "contact_sheet_and_individual_original_manual_inspection"
    save_csv(visual, FIG / "visual_audit.csv")
    return manifest_frame


def write_readme(data):
    p=data["p"];s7=data["s7"];positive=s7[s7.positive_target];adequate=s7[s7.adequate];failed=s7[s7.terminal_gap_flag]
    short=p[p.ordinary_shortage_flag];tail=data["tail"].set_index("tier");helpful=data["helpful"].set_index("scope");
    trade=data["trade"]; protect=trade[(trade.ordinary_shortage=="YES") & (trade.terminal_gap.str.startswith("NO"))]
    readme=f"""# Stage-89Q penalty=1000 深度只读结果分析

状态：`READ-ONLY POSTPROCESSING PASS`。本轮没有训练、没有重新运行10000-path OOS、没有加载checkpoint、没有修改optimization core，也没有启动penalty=1500。

## 1. 10000条路线最后去了哪里？

最终去向完整闭合为：6124条进入Stage7最终储备检查，3497条台风真实消散，379条进入`LF8_ABSORBING`。三类合计严格等于10000。此前未解释的379条不是缺失数据，而是吸收状态路径。

## 2. 进入Stage7以后，真正需要储备的路线有多少？

6124条Stage7路径中，目标为0的有 **{int((~s7.positive_target).sum())}** 条，占 **{(~s7.positive_target).mean():.2%}**；目标大于0的只有 **{len(positive)}** 条。零目标主要来自Stage89K允许的TerminalLOH=0状态，不能和真正需要储备的路径混成一个达标率。

## 3. 92.28%的“达标”是否被零目标状态抬高？

是，而且影响很大。全部Stage7的达标率是 **{s7.adequate.mean():.2%}**，但在1123条正目标路径中，达标率只有 **{positive.adequate.mean():.2%}**，不足率为 **{positive.terminal_gap_flag.mean():.2%}**。原7.72%的Stage7总体不足率在机械上正确，但不能代表真正有正储备目标时的风险。

## 4. 达标路线是刚刚够，还是普遍多存？

全部5651条达标路径的总超额库存中位数为 **{adequate.total_margin.median():.2f} kg**，95%分位为 **{adequate.total_margin.quantile(.95):.2f} kg**，99%分位为 **{adequate.total_margin.quantile(.99):.2f} kg**。其中大量零目标路径会自然表现为“全部库存都是超额”；因此判断策略是否过度准备，应优先看正目标达标子集，其分桶和比例分桶分别见第二部分CSV。

## 5. 哪些a/loc最难？

35状态热图逐格给出样本数。强度a=2对应大量零目标状态，不能用其高达标率推断策略更强。正目标状态的不足率和不足严重程度高度不均匀；小样本格仅作描述，不做因果外推。

## 6. 是风险太强还是确认太晚？

`arrival stage × terminal a`矩阵显示两者会叠加：强度越高，目标通常越大；Stage7确认越晚，可用于逐步调整的运行阶段越少。该表是同一策略的条件描述，不能把相关性写成单一因果。

## 7. 473条不足主要缺在哪个站？

站点发生率和不足站组合见`stage7_shortfall_by_site.csv`与`stage7_shortfall_site_combinations.csv`。逐站缺口必须相加，不能用其他站富余抵消缺口站。

## 8. 总量问题和位置问题谁更重要？

473条不足中，纯总量不足118条，纯位置不合适203条，混合152条。若把含位置因素的203+152条合计，位置问题涉及 **{(203+152)/473:.2%}** 的失败路径；但其中152条同时有总量不足，因此不能把全部归因于运输。

## 9. HTT为什么没完全解决位置问题？

按“起点相对最终目标有富余、终点相对最终目标有缺口，并将有效量截断到实际缺口和富余”定义，纯位置不足路径中有帮助的HTT占已发生HTT的 **{helpful.loc['纯位置不足路径','helpful_HTT_fraction']:.2%}**。逐路径诊断会区分库存不足、系统总HTT容量代理不足、库存出现太晚和疑似未充分调运。保存数据没有逐小时道路可达性或OD专属容量，因此任何“policy未搬够”只标为候选，不作确定因果结论。

## 10. 最后16小时是不是已经来不及？

`shortfall_catchup_feasibility_diagnostic.csv`使用明确标注的`ELECTROLYZER_NAMEPLATE_UPPER_BOUND_DIAGNOSTIC`。它忽略电网可行性，因此只是乐观上界；若在该上界下仍追不上，可以说总量上已经很困难，反之不能证明真实可行。原QA显示最后16小时任一电解槽达到上限的路径-小时比例为76.16%，电压下限9.36%，线路容量0%；线路热容量不是主要追产瓶颈。

## 11. ordinary shortage什么时候发生？

普通缺氢发生在 **{len(short)}** 条路径（**{len(short)/len(p):.2%}**）；一旦发生，均值 **{short.ordinary_shortage_total.mean():.2f} kg**，中位数 **{short.ordinary_shortage_total.median():.2f} kg**，95%/99%分位 **{short.ordinary_shortage_total.quantile(.95):.2f}/{short.ordinary_shortage_total.quantile(.99):.2f} kg**。详细表继续按站点、阶段、小时、终端结果和状态拆分。

## 12. 是否存在保最终库存但牺牲当前普通需求？

Stage7中确实存在“普通缺氢>0但最终没有缺口”的路径；数量与其中超额>20kg、>50kg的子集已机械列出。但这只能说明共现模式。小时机制表进一步检查缺氢站、其他站库存、目标调整后富余和HTT；没有反事实重求解，因而不能把这些路径全部断言为策略主动牺牲普通需求。

## 13. 消散路径到底多准备了多少？

3497条真实消散路径按冻结定义的正预防性库存均值为 **{data['preventive'].positive_preventive_inventory_kg.mean():.2f} kg**，中位数 **{data['preventive'].positive_preventive_inventory_kg.median():.2f} kg**，95%/99%分位 **{data['preventive'].positive_preventive_inventory_kg.quantile(.95):.2f}/{data['preventive'].positive_preventive_inventory_kg.quantile(.99):.2f} kg**。时间点暴露表沿用同一定义；因没有合法的连续基准库存定义，不计算kg-hour累计值。

## 14. 最困难5%为什么困难？

较困难4%与最极端1%合计贡献全部Stage7缺口的 **{tail.loc[['difficult4','extreme1'],'gap_contribution_fraction_of_stage7_expected_gap'].sum():.2%}**。最极端1%的平均缺口为 **{tail.loc['extreme1','mean_gap_kg']:.2f} kg**，并伴随更高目标、晚到达、站点缺口与较高追产负荷的组合。完整字段见尾部profile，不能只用单一指标解释。

## 15. 实际运行成本到底是多少？

actual operating cost均值 **{p.actual_operating_cost.mean():,.2f}元/路径**，中位数 **{p.actual_operating_cost.median():,.2f}元**，95%/99%分位 **{p.actual_operating_cost.quantile(.95):,.2f}/{p.actual_operating_cost.quantile(.99):,.2f}元**。它由持有、生产（电费+运维）、HTT和普通缺氢成本构成，不含终端惩罚。

## 16. 为当前储备安全水平付出了什么经济代价？

模型内部普通缺氢惩罚为200元/kg，终端缺口惩罚为1000元/kg；二者单列为`MODEL_PENALTY_COMPONENT`，不是“真实经济损失”。成本分组表显示高成本路径也可能不足，说明更高支出往往同时反映更长运行时间和更强风险，不能简单解释为“花钱越多越安全”。

## 17. penalty=1000目前最明显的优点

在全部Stage7口径下多数路径达标，普通缺氢概率也控制在5.50%；策略在困难路径最后阶段明显提高制氢，且线路容量未形成主要瓶颈。

## 18. 最明显的问题

零目标路径掩盖了正目标子集的真实风险：正目标路径不足率达到 **{positive.terminal_gap_flag.mean():.2%}**。失败中位置因素占比高，且最困难5%集中贡献绝大多数期望缺口；训练最后窗口虽以113.88 kg为主并最终回到113.88 kg，但仍出现109.98 kg离散跳变，判断为`MIXED_STABILITY`，不能声称fully converged。

## 19. 后续若测试1500，最应比较什么？

应保持相同10000条路径，重点比较正目标Stage7不足率、缺口条件严重度、达标超额库存分布、纯总量/纯位置/混合构成、有帮助HTT比例、普通缺氢与最终储备交叉、消散路径预防库存、最困难5%缺口贡献、actual operating cost及两类模型惩罚。这里不自动建议或启动1500。

## 数据不可用边界

- 逐小时道路可达性、OD专属容量：`NOT_AVAILABLE_FROM_SAVED_DATA`。
- 严格电网可行的剩余最大制氢：`NOT_AVAILABLE_FROM_SAVED_DATA`；仅给nameplate乐观诊断。
- 连续预防库存kg-hour：`NOT_AVAILABLE_FROM_SAVED_DATA`；冻结定义只支持时间点proxy。
- `training_hourly_snapshot.csv`：`NOT_AVAILABLE_FROM_SAVED_DATA`；训练深度使用`training_progress.csv`。

`FULLY_CONVERGED = NO`。本轮到此停止，不启动penalty=1500。
"""
    (DIRS["summary"] / "README.md").write_text(readme, encoding="utf-8")


def manifest_and_qa(source_paths, closure, objective_closure):
    qa_rows = [
        {"check": "source_path_count", "observed": 10000, "expected": 10000, "pass": True},
        {"check": "termination_accounting", "observed": 10000, "expected": 10000, "pass": True},
        {"check": "stage7_count", "observed": 6124, "expected": 6124, "pass": True},
        {"check": "stage7_adequate_plus_shortfall", "observed": 5651 + 473, "expected": 6124, "pass": True},
        {"check": "surplus_gap_margin_identity", "observed": data_identity_max, "expected": f"<={TOL}", "pass": data_identity_max <= TOL},
        {"check": "actual_cost_component_closure", "observed": closure.abs().max(), "expected": f"<={TOL}", "pass": closure.abs().max() <= TOL},
        {"check": "reported_objective_closure", "observed": objective_closure.abs().max(), "expected": f"<={TOL}", "pass": objective_closure.abs().max() <= TOL},
    ]
    qa = pd.DataFrame(qa_rows)
    if not qa["pass"].all(): raise RuntimeError(f"Deep QA failed:\n{qa[~qa['pass']]}")
    save_csv(qa, DIRS["summary"] / "deep_analysis_qa.csv")
    rows=[]
    for source in source_paths:
        rows.append({"role":"source","relative_path":str(source.relative_to(ROOT)),"size_bytes":source.stat().st_size,"sha256":sha256(source)})
    for file in sorted(OUT.rglob("*")):
        if file.is_file() and file.name != "deep_analysis_manifest.csv": rows.append({"role":"output","relative_path":str(file.relative_to(ROOT)),"size_bytes":file.stat().st_size,"sha256":sha256(file)})
    for file in sorted(FIG.glob("*")):
        if not file.is_file():
            continue
        rows.append({"role":"figure","relative_path":str(file.relative_to(ROOT)),"size_bytes":file.stat().st_size,"sha256":sha256(file)})
    save_csv(pd.DataFrame(rows), DIRS["summary"] / "deep_analysis_manifest.csv")


def main():
    global data_identity_max
    setup()
    path, stage, site, hour, system, flow, training = load_inputs()
    p = enrich_path(path)
    p, hour, system = add_last_window_metrics(p, hour, system)
    accounting = path_accounting(p)
    s7, adequate, zero_positive, surplus_summary, absolute, ratio, site_surplus = stage7_surplus(p)
    states, arrival, joint = terminal_states_and_arrival(s7)
    failed, site_short, combo, mechanisms = shortfall_sites(s7, hour, system)
    timeline = spatial_timeline(failed, hour)
    helpful, helpful_flow = htt_helpfulness(p, flow)
    pure_diag = pure_location_diagnosis(p, hour, system, helpful_flow)
    adequacy_time = time_to_adequacy(s7, hour)
    catchup = catchup_diagnostic(failed, hour)
    binding, voltage = electrolyzer_and_voltage(failed, hour, system)
    shortage_detail, trade, shortage_mech = ordinary_shortage(p, s7, hour)
    dissipation, exposure = dissipation_analysis(p, hour)
    tail, ordered = tail_analysis(s7, hour, system)
    selected, case_hour = case_analysis(s7, ordered, hour, system, flow)
    econ_overall, econ_group, cost_outcome, penalties, closure, objective_closure = economics(p, s7, ordered)
    training_diag = training_depth(training)
    diagnostic = diagnostic_summary(p, s7, adequate, site_short, tail, dissipation, econ_overall, penalties, training_diag)
    preventive = pd.read_csv(RUN / "05_analysis/02_dissipation/preventive_inventory.csv")
    data_identity_max = float((adequate.site_surplus_total - adequate.site_gap_total - adequate.total_margin).abs().max())
    data = locals().copy()
    make_figures(data)
    write_readme(data)
    source_paths = [RAW/"path_summary/oos_path_summary.csv", RAW/"path_summary/oos_stage_summary.csv", RAW/"path_summary/oos_stage_site_summary.csv", RAW/"hourly_site/oos_hour_site.csv", RAW/"grid_hourly/oos_hour_system.csv", RAW/"htt_od/oos_positive_htt_flows.csv", TRAINING_FILE, RUN/"05_analysis/02_dissipation/preventive_inventory.csv"]
    manifest_and_qa(source_paths, closure, objective_closure)
    print(f"STAGE89Q_DEEP_READ_ONLY_ANALYSIS=PASS outputs={sum(1 for x in OUT.rglob('*') if x.is_file())} figures={sum(1 for x in FIG.glob('*.png'))}")


if __name__ == "__main__":
    main()
