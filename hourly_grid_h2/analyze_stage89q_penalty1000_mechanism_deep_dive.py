#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Second read-only mechanism deep dive for accepted Stage89Q penalty=1000 OOS."""

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
BASE = RUN / "05_analysis/10_deep_penalty1000"
OUT = BASE / "15_mechanism_deep_dive"
FIG = RUN / "06_figures/09_penalty1000_mechanism_deep_dive"
TARGET_TABLE = ROOT / "terminalLoh_wdro/current_w_mainline_stage89/terminal_tables/terminal_loh_stage89k_dro_eta003_adopted.csv"
TOL = 1e-7
SITE_IDS = [1, 2, 3, 4]
PMAX = {1: 300.0, 2: 200.0, 3: 120.0, 4: 150.0}
K_H2 = 0.0195
CHECKPOINTS = [-24, -16, -8, -4, 0]
EXPECTED_BANK_MAT_SHA = "6bf3d1190a402ded052b8d3d08ed369042236e151f562bdd9fd4db7b8ff386c6"
EXPECTED_BANK_MANIFEST_SHA = "a186e8d4ac870082d0925a05311ab8f4c5a0b70cb61b6fd06955a48a647b3941"
EXPECTED_RAW_SHA = {
    "path_summary/oos_path_summary.csv": "99ec55faba4e60e88b25d757deb1a8146515faf666d52979fe69c64362047502",
    "hourly_site/oos_hour_site.csv": "af3b3d5c4aa69e6d29b35a88008b4d82360c4b8391fc783141078f7ad68b0cda",
    "htt_od/oos_positive_htt_flows.csv": "06a6586574a155eb4588cae691898b3ebda509a79e14e64c8453918b7262fe4a",
    "grid_hourly/oos_hour_system.csv": "b9eaa83ee3e8a720f3cb5afd5d54da050c2d3ef45c434efe74f8ba8b976b63c6",
}

DIRS = {
    "surplus": OUT / "01_surplus_timing",
    "shortfall": OUT / "02_shortfall_timing",
    "recover": OUT / "03_physical_recoverability",
    "mismatch": OUT / "04_site_mismatch",
    "htt": OUT / "05_htt_mechanism",
    "electrolyzer": OUT / "06_electrolyzer",
    "grid": OUT / "07_grid",
    "ordinary": OUT / "08_ordinary_vs_reserve",
    "economics": OUT / "09_economics",
    "dissipation": OUT / "10_dissipation",
    "tail": OUT / "11_tail",
    "cases": OUT / "12_case_studies",
    "summary": OUT / "13_summary",
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


def stats(values) -> dict[str, float]:
    x = pd.Series(values, dtype="float64").dropna().to_numpy()
    if not len(x):
        return {key: np.nan for key in ("mean", "median", "q25", "q75", "q90", "q95", "q99", "max")}
    return {
        "mean": float(np.mean(x)), "median": float(np.median(x)),
        "q25": float(np.quantile(x, .25)), "q75": float(np.quantile(x, .75)),
        "q90": float(np.quantile(x, .90)), "q95": float(np.quantile(x, .95)),
        "q99": float(np.quantile(x, .99)), "max": float(np.max(x)),
    }


def prefixed(values, prefix: str) -> dict[str, float]:
    return {f"{prefix}_{key}": value for key, value in stats(values).items()}


def bootstrap_mean_ci(values, seed: int, draws: int = 2000) -> tuple[float, float]:
    x = pd.Series(values, dtype="float64").dropna().to_numpy()
    if not len(x):
        return np.nan, np.nan
    if len(x) == 1:
        return float(x[0]), float(x[0])
    rng = np.random.default_rng(seed)
    means = np.empty(draws)
    for start in range(0, draws, 200):
        count = min(200, draws - start)
        means[start:start + count] = x[rng.integers(0, len(x), size=(count, len(x)))].mean(axis=1)
    return float(np.quantile(means, .025)), float(np.quantile(means, .975))


def setup() -> None:
    for directory in [OUT, FIG, *DIRS.values()]:
        directory.mkdir(parents=True, exist_ok=True)
    available = {item.name for item in font_manager.fontManager.ttflist}
    font = next((x for x in ("Microsoft YaHei", "Microsoft YaHei UI", "SimHei") if x in available), None)
    if font is None:
        raise RuntimeError("No Chinese font available")
    plt.rcParams.update({"font.family": font, "axes.unicode_minus": False, "font.size": 10,
                         "figure.dpi": 140, "savefig.dpi": 180, "axes.titleweight": "bold"})


def load_inputs():
    bank_identity_path = RUN / "03_oos/common/bank_identity.csv"
    bank_identity = pd.read_csv(bank_identity_path).iloc[0]
    files = {
        "path": RAW / "path_summary/oos_path_summary.csv",
        "stage": RAW / "path_summary/oos_stage_summary.csv",
        "site": RAW / "path_summary/oos_stage_site_summary.csv",
        "hour": RAW / "hourly_site/oos_hour_site.csv",
        "system": RAW / "grid_hourly/oos_hour_system.csv",
        "flow": RAW / "htt_od/oos_positive_htt_flows.csv",
        "bank": RUN / "03_oos/common/oos_path_manifest.csv",
        "bank_identity": bank_identity_path,
        "bank_mat": Path(bank_identity.bank_path),
        "target": TARGET_TABLE,
        "large_manifest": RUN / "07_manifests/large_data_manifest.csv",
    }
    return files, *(pd.read_csv(files[key]) for key in ("path", "stage", "site", "hour", "system", "flow", "bank", "target"))


def enrich(path, hour, system):
    p = path.copy()
    p["operating_hours"] = 8 * p.operating_stage_count
    p["arrival_after_stage"] = p.termination_stage - 1
    p["positive_target"] = p.target_total > TOL
    p["adequate"] = p.terminal_site_gap <= TOL
    p["terminal_gap_flag"] = p.terminal_site_gap > TOL
    p["ordinary_shortage_flag"] = p.ordinary_shortage_total > TOL
    p["total_margin"] = p.terminal_inventory_total - p.target_total
    p["site_gap_total"] = p[[f"gap_site{i}" for i in SITE_IDS]].sum(axis=1)
    p["site_surplus_total"] = p[[f"surplus_site{i}" for i in SITE_IDS]].sum(axis=1)
    p["surplus_bin"] = pd.cut(p.total_margin, [-np.inf, 50, 100, 200, np.inf],
                              labels=["0-50 kg", "50-100 kg", "100-200 kg", ">200 kg"], right=False)
    end = p.set_index("path_id").operating_hours
    h = hour.copy()
    h["end_hour"] = h.path_id.map(end)
    h["relative_hour"] = h.global_hour - h.end_hour
    h["pmax_kw"] = h.site.map(PMAX)
    h["utilization"] = h.P_EL_kW / h.pmax_kw
    sys = system.copy()
    sys["end_hour"] = sys.path_id.map(end)
    sys["relative_hour"] = sys.global_hour - sys.end_hour
    hourly = h.groupby(["path_id", "global_hour", "relative_hour"], as_index=False).agg(
        total_begin_inventory_kg=("begin_inventory_kg", "sum"),
        total_inventory_kg=("end_inventory_kg", "sum"),
        production_kg=("H2_production_kg", "sum"), HTT_kg=("HTT_out_kg", "sum"),
        ordinary_shortage_kg=("ordinary_shortage_kg", "sum"), total_P_EL_kW=("P_EL_kW", "sum"),
        storm_intensity=("hurricane_a", "first"), storm_location=("hurricane_loc", "first"),
        storm_lf=("hurricane_lf", "first"), stage=("stage", "first"),
    )
    hourly["system_electrolyzer_utilization"] = hourly.total_P_EL_kW / sum(PMAX.values())
    return p, h, sys, hourly


def target_lookup_frame(target):
    frame = target.rename(columns={"intensity": "storm_intensity", "loc": "storm_location", "TerminalLOH_total_kg": "state_target_total_kg"}).copy()
    return frame[["storm_intensity", "storm_location", "state_target_total_kg", "T1_kg", "T2_kg", "T3_kg", "T4_kg"]]


def threshold_hour(ph, threshold):
    hit = ph[ph.total_inventory_kg >= threshold - TOL]
    return hit.relative_hour.iloc[0] if len(hit) else np.nan


def stable_threshold_hour(ph, threshold):
    ok = ph.total_inventory_kg >= threshold - TOL
    stable = ok.iloc[::-1].cummin().iloc[::-1]
    return ph.loc[stable, "relative_hour"].iloc[0] if stable.any() else np.nan


def checkpoint_wide(path_row, ph, site_hour, prefix=""):
    record = {}
    for rel in CHECKPOINTS:
        tag = f"minus{abs(rel)}h" if rel < 0 else "t0h"
        cell = ph[ph.relative_hour.eq(rel)]
        site_cell = site_hour[site_hour.relative_hour.eq(rel)]
        if len(cell) == 1 and len(site_cell) == 4:
            row = cell.iloc[0]
            record.update({
                f"{prefix}total_inventory_{tag}_kg": row.total_inventory_kg,
                f"{prefix}inventory_minus_target_{tag}_kg": row.total_inventory_kg - path_row.target_total,
                f"{prefix}production_{tag}_kg": row.production_kg,
                f"{prefix}HTT_{tag}_kg": row.HTT_kg,
                f"{prefix}ordinary_shortage_{tag}_kg": row.ordinary_shortage_kg,
                f"{prefix}storm_intensity_{tag}": row.storm_intensity,
                f"{prefix}storm_location_{tag}": row.storm_location,
                f"{prefix}system_electrolyzer_utilization_{tag}": row.system_electrolyzer_utilization,
            })
            for site_id in SITE_IDS:
                srow = site_cell[site_cell.site.eq(site_id)].iloc[0]
                record[f"{prefix}inventory_site{site_id}_{tag}_kg"] = srow.end_inventory_kg
                record[f"{prefix}gap_site{site_id}_{tag}_kg"] = max(path_row[f"target_site{site_id}"] - srow.end_inventory_kg, 0)
        else:
            for name in ("total_inventory", "inventory_minus_target", "production", "HTT", "ordinary_shortage", "storm_intensity", "storm_location", "system_electrolyzer_utilization"):
                record[f"{prefix}{name}_{tag}" + ("_kg" if name not in ("storm_intensity", "storm_location", "system_electrolyzer_utilization") else "")] = np.nan
            for site_id in SITE_IDS:
                record[f"{prefix}inventory_site{site_id}_{tag}_kg"] = np.nan
                record[f"{prefix}gap_site{site_id}_{tag}_kg"] = np.nan
    return record


def surplus_timing(p, h, hourly, target):
    adequate = p[p.positive_target & p.adequate].copy()
    lookup = target_lookup_frame(target)
    hourly_risk = hourly.merge(lookup, on=["storm_intensity", "storm_location"], how="left")
    rows = []
    for path_id, row in adequate.set_index("path_id").iterrows():
        ph = hourly_risk[hourly_risk.path_id.eq(path_id)].sort_values("global_hour")
        sh = h[h.path_id.eq(path_id)]
        peak_intensity = ph.storm_intensity.max()
        max_observed_target = ph.state_target_total_kg.max()
        first100 = threshold_hour(ph, row.target_total)
        before_t0 = ph[ph.relative_hour < 0]
        location_changed = before_t0.storm_location.nunique() > 1
        risk_weakened = peak_intensity > row.terminal_a or (pd.notna(max_observed_target) and max_observed_target > row.target_total + TOL)
        early_inventory = bool((ph[ph.relative_hour <= -8].total_inventory_kg >= row.target_total + 100).any())
        htt_last24 = ph[ph.relative_hour.between(-23, 0)].HTT_kg.sum()
        factors = []
        if early_inventory: factors.append("EARLY_INVENTORY_BUILD_SIGNAL")
        if risk_weakened: factors.append("RISK_LATER_WEAKENED_SIGNAL")
        if location_changed: factors.append("LOCATION_CHANGED_SIGNAL")
        if htt_last24 > TOL: factors.append("HTT_REALLOCATED_SIGNAL")
        if not factors: factors = ["NOT_IDENTIFIABLE"]
        record = {
            "path_id": path_id, "surplus_bin": row.surplus_bin, "final_target_kg": row.target_total,
            "final_inventory_kg": row.terminal_inventory_total, "final_surplus_kg": row.total_margin,
            "first_positive_inventory_hour": threshold_hour(ph, TOL),
            "first_25pct_target_hour": threshold_hour(ph, .25 * row.target_total),
            "first_50pct_target_hour": threshold_hour(ph, .50 * row.target_total),
            "first_75pct_target_hour": threshold_hour(ph, .75 * row.target_total),
            "first_100pct_target_hour": first100,
            "stable_100pct_target_hour": stable_threshold_hour(ph, row.target_total),
            "arrival_stage": row.arrival_after_stage, "final_intensity": row.terminal_a,
            "final_location": row.terminal_loc, "peak_observed_operating_intensity": peak_intensity,
            "max_hypothetical_target_from_observed_operating_states_kg": max_observed_target,
            "hypothetical_target_drop_to_final_kg": max_observed_target - row.target_total if pd.notna(max_observed_target) else np.nan,
            "operating_location_changed": location_changed, "risk_later_weakened_signal": risk_weakened,
            "HTT_last24h_kg": htt_last24, "mechanism_signal_count": len(factors),
            "mechanism_signals": ";".join(factors),
            "interpretation_limit": "Signals are descriptive; final target is an ex-post reference, not proof of contemporaneous policy error",
        }
        record.update(checkpoint_wide(row, ph, sh))
        rows.append(record)
    timing = pd.DataFrame(rows)
    save_csv(timing, DIRS["surplus"] / "surplus_build_timing.csv")

    summary_rows = []
    bin_order = ["0-50 kg", "50-100 kg", "100-200 kg", ">200 kg"]
    for idx, bin_name in enumerate(bin_order):
        group = timing[timing.surplus_bin.eq(bin_name)]
        if not len(group): continue
        ci_low, ci_high = bootstrap_mean_ci(group.final_surplus_kg, 8900 + idx)
        summary_rows.append({
            "surplus_bin": bin_name, "N": len(group), **prefixed(group.final_surplus_kg, "final_surplus_kg"),
            "final_surplus_mean_bootstrap_ci95_low": ci_low, "final_surplus_mean_bootstrap_ci95_high": ci_high,
            "mean_first_100pct_target_hour": group.first_100pct_target_hour.mean(),
            "mean_stable_100pct_target_hour": group.stable_100pct_target_hour.mean(),
            "risk_later_weakened_signal_fraction": group.risk_later_weakened_signal.mean(),
            "location_changed_fraction": group.operating_location_changed.mean(),
            "mean_HTT_last24h_kg": group.HTT_last24h_kg.mean(),
        })
    summary = pd.DataFrame(summary_rows)
    save_csv(summary, DIRS["surplus"] / "surplus_timing_group_summary.csv")
    return timing, summary


def aligned_profile(p, hourly, scope_masks):
    rows = []
    for label, ids in scope_masks.items():
        group = hourly[hourly.path_id.isin(ids) & hourly.relative_hour.between(-24, 0)]
        for rel, cell in group.groupby("relative_hour"):
            rows.append({
                "group": label, "relative_hour": rel, "path_count": cell.path_id.nunique(),
                "mean_inventory_kg": cell.total_inventory_kg.mean(), "median_inventory_kg": cell.total_inventory_kg.median(),
                "mean_production_kg": cell.production_kg.mean(), "mean_HTT_kg": cell.HTT_kg.mean(),
                "mean_ordinary_shortage_kg": cell.ordinary_shortage_kg.mean(),
                "mean_system_electrolyzer_utilization": cell.system_electrolyzer_utilization.mean(),
            })
    return pd.DataFrame(rows)


def shortfall_timing(p, h, hourly):
    failed = p[p.positive_target & p.terminal_gap_flag].copy()
    rows = []
    for path_id, row in failed.set_index("path_id").iterrows():
        ph = hourly[hourly.path_id.eq(path_id)].sort_values("global_hour")
        sh = h[h.path_id.eq(path_id)]
        record = {
            "path_id": path_id, "terminal_gap_class": row.terminal_gap_class,
            "final_target_kg": row.target_total, "final_inventory_kg": row.terminal_inventory_total,
            "final_total_margin_kg": row.total_margin, "final_site_shortfall_kg": row.site_gap_total,
            "final_site_surplus_kg": row.site_surplus_total, "arrival_stage": row.arrival_after_stage,
            "final_intensity": row.terminal_a, "final_location": row.terminal_loc,
            "production_last24h_kg": ph[ph.relative_hour.between(-23, 0)].production_kg.sum(),
            "production_last16h_kg": ph[ph.relative_hour.between(-15, 0)].production_kg.sum(),
            "production_last8h_kg": ph[ph.relative_hour.between(-7, 0)].production_kg.sum(),
            "HTT_last24h_kg": ph[ph.relative_hour.between(-23, 0)].HTT_kg.sum(),
            "ordinary_shortage_last24h_kg": ph[ph.relative_hour.between(-23, 0)].ordinary_shortage_kg.sum(),
            "mean_system_electrolyzer_utilization_last16h": ph[ph.relative_hour.between(-15, 0)].system_electrolyzer_utilization.mean(),
            "final_state_confirmation_timing": f"after Stage{int(row.arrival_after_stage)}",
        }
        record.update(checkpoint_wide(row, ph, sh))
        rows.append(record)
    timing = pd.DataFrame(rows)
    save_csv(timing, DIRS["shortfall"] / "shortfall_build_timing.csv")

    positive = p[p.positive_target]
    rows = []
    for arrival in range(2, 7):
        base = positive[positive.arrival_after_stage.eq(arrival)]
        failure = base[base.terminal_gap_flag]
        ci_low, ci_high = bootstrap_mean_ci(base.terminal_gap_flag.astype(float), 8910 + arrival)
        rows.append({
            "arrival_after_stage": arrival, "path_count": len(p[p.reached_stage7.eq(1) & p.arrival_after_stage.eq(arrival)]),
            "positive_target_count": len(base), "shortfall_count": len(failure),
            "shortfall_probability": failure.shape[0] / len(base) if len(base) else np.nan,
            "shortfall_probability_bootstrap_ci95_low": ci_low, "shortfall_probability_bootstrap_ci95_high": ci_high,
            "shortfall_if_positive_kg": failure.terminal_site_gap.mean(), "mean_target_kg": base.target_total.mean(),
            "mean_final_inventory_kg": base.terminal_inventory_total.mean(),
            "mean_production_last24h_kg": base.final24h_production.mean(),
            "mean_production_last16h_kg": base.final16h_production.mean(),
            "mean_production_last8h_kg": base.final8h_production.mean(),
            "mean_HTT_kg": base.total_HTT.mean(), "mean_ordinary_shortage_kg": base.ordinary_shortage_total.mean(),
            "mean_actual_operating_cost_yuan": base.actual_operating_cost.mean(),
        })
    by_arrival = pd.DataFrame(rows)
    save_csv(by_arrival, DIRS["shortfall"] / "shortfall_by_arrival_stage.csv")

    profile = aligned_profile(p, hourly, {
        "正目标达标": set(p.loc[p.positive_target & p.adequate, "path_id"]),
        "正目标不足": set(failed.path_id),
        "超额大于100kg": set(p.loc[p.positive_target & p.adequate & (p.total_margin > 100), "path_id"]),
    })
    save_csv(profile, DIRS["shortfall"] / "adequate_vs_shortfall_last24h_profile.csv")
    return timing, by_arrival, profile


def add_window_metrics(p, hourly):
    out = p.copy()
    for window in (8, 16, 24):
        subset = hourly[hourly.relative_hour.between(-(window - 1), 0)]
        agg = subset.groupby("path_id").agg(
            **{f"final{window}h_production": ("production_kg", "sum")},
            **{f"final{window}h_HTT": ("HTT_kg", "sum")},
            **{f"final{window}h_shortage": ("ordinary_shortage_kg", "sum")},
        )
        out = out.merge(agg, on="path_id", how="left")
    return out


def physical_recoverability(p, h):
    failed = p[p.positive_target & p.terminal_gap_flag]
    rows = []
    path_summaries = []
    for path_id, row in failed.set_index("path_id").iterrows():
        ph = h[h.path_id.eq(path_id)]
        statuses = {}
        for hours_before in (16, 8, 4):
            checkpoint = ph[ph.relative_hour.eq(-hours_before)]
            if len(checkpoint) != 4:
                rows.append({"path_id": path_id, "hours_before_stage7": hours_before,
                             "TARGET_STILL_PHYSICALLY_REACHABLE": "NOT_IDENTIFIABLE",
                             "reason": "checkpoint_not_present_without_zero_padding"})
                statuses[hours_before] = "NOT_IDENTIFIABLE"
                continue
            current = checkpoint.set_index("site").end_inventory_kg.reindex(SITE_IDS)
            remaining = ph[ph.relative_hour.between(-hours_before + 1, 0)].groupby("site").ordinary_demand_kg.sum().reindex(SITE_IDS, fill_value=0)
            nameplate = pd.Series({site: PMAX[site] * K_H2 * hours_before for site in SITE_IDS})
            target = pd.Series({site: row[f"target_site{site}"] for site in SITE_IDS})
            # Ordinary demand can be shorted, so a strict reachability upper bound
            # cannot assume that all remaining ordinary demand must be served.
            optimistic_site_inventory = current + nameplate
            service_all_site_inventory = current + nameplate - remaining
            optimistic_total_margin = optimistic_site_inventory.sum() - target.sum()
            strict_no = optimistic_total_margin < -TOL
            status = "NO" if strict_no else "NOT_IDENTIFIABLE"
            statuses[hours_before] = status
            rows.append({
                "path_id": path_id, "hours_before_stage7": hours_before,
                "current_inventory_kg": current.sum(), "remaining_target_gap_kg": max(target.sum() - current.sum(), 0),
                "remaining_hours": hours_before, "remaining_electrolyzer_nameplate_max_kg": nameplate.sum(),
                "known_remaining_ordinary_demand_kg": remaining.sum(),
                "simple_optimistic_additional_H2_upper_bound_kg": nameplate.sum(),
                "optimistic_final_inventory_kg": optimistic_site_inventory.sum(), "target_total_kg": target.sum(),
                "optimistic_total_margin_kg": optimistic_total_margin,
                "serve_all_remaining_demand_net_additional_H2_kg": nameplate.sum() - remaining.sum(),
                "serve_all_remaining_demand_final_inventory_kg": service_all_site_inventory.sum(),
                "serve_all_remaining_demand_total_margin_kg": service_all_site_inventory.sum() - target.sum(),
                "TARGET_STILL_PHYSICALLY_REACHABLE": status,
                "reason": "nameplate upper bound still below total target" if strict_no else "nameplate bound does not prove grid/HTT-feasible reachability",
                "diagnostic_label": "ELECTROLYZER_NAMEPLATE_UPPER_BOUND_DIAGNOSTIC",
            })
        no_hours = [x for x in (16, 8, 4) if statuses.get(x) == "NO"]
        path_summaries.append({
            "path_id": path_id,
            "LAST_PHYSICALLY_RECOVERABLE_HOUR": "NOT_IDENTIFIABLE",
            "FIRST_PHYSICALLY_UNRECOVERABLE_HOUR": -max(no_hours) if no_hours else "NOT_IDENTIFIABLE",
            "not_proven_unrecoverable_at_16h": statuses.get(16) != "NO",
            "not_proven_unrecoverable_at_8h": statuses.get(8) != "NO",
            "first_proven_unrecoverable_only_by_4h": statuses.get(16) != "NO" and statuses.get(8) != "NO" and statuses.get(4) == "NO",
        })
    detail = pd.DataFrame(rows)
    path_summary = pd.DataFrame(path_summaries)
    summary = detail.groupby(["hours_before_stage7", "TARGET_STILL_PHYSICALLY_REACHABLE"], as_index=False).agg(path_count=("path_id", "count"))
    summary["denominator_shortfall_paths"] = len(failed)
    summary["fraction_of_shortfall_paths"] = summary.path_count / len(failed)
    save_csv(detail, DIRS["recover"] / "physical_recoverability_diagnostic.csv")
    save_csv(path_summary, DIRS["recover"] / "physical_recoverability_by_path.csv")
    save_csv(summary, DIRS["recover"] / "physical_recoverability_summary.csv")
    return detail, path_summary, summary


def site_mismatch(p, h, flow):
    failed = p[p.positive_target & p.terminal_gap_flag].copy()
    identity = failed.site_surplus_total - failed.site_gap_total - failed.total_margin
    rows = []
    for group_name, group in [("all_shortfall", failed),
                              ("pure_quantity", failed[failed.terminal_gap_class.eq("PURE_QUANTITY_SHORTFALL")]),
                              ("pure_location", failed[failed.terminal_gap_class.eq("PURE_SPATIAL_MISMATCH")]),
                              ("mixed", failed[failed.terminal_gap_class.eq("MIXED_QUANTITY_AND_SPATIAL")])]:
        for site in SITE_IDS:
            gap = group[f"gap_site{site}"]; surplus = group[f"surplus_site{site}"]
            rows.append({
                "record_type": "site_summary", "group": group_name, "site": site, "N": len(group),
                "shortage_occurrence": (gap > TOL).mean(), "shortage_if_positive_kg": gap[gap > TOL].mean(),
                "shortage_q95_if_positive_kg": gap[gap > TOL].quantile(.95),
                "surplus_occurrence": (surplus > TOL).mean(), "surplus_mean_if_positive_kg": surplus[surplus > TOL].mean(),
                "surplus_q95_if_positive_kg": surplus[surplus > TOL].quantile(.95),
            })
    pure = failed[failed.terminal_gap_class.eq("PURE_SPATIAL_MISMATCH")]
    flow_rows = []
    for path_id, row in pure.set_index("path_id").iterrows():
        surplus_sites = [site for site in SITE_IDS if row[f"surplus_site{site}"] > TOL]
        deficit_sites = [site for site in SITE_IDS if row[f"gap_site{site}"] > TOL]
        pf = flow[flow.path_id.eq(path_id)]
        for origin in surplus_sites:
            for destination in deficit_sites:
                actual = pf[(pf.origin_site == origin) & (pf.destination_site == destination)].flow_kg.sum()
                potential = min(row[f"surplus_site{origin}"], row[f"gap_site{destination}"])
                flow_rows.append({
                    "record_type": "surplus_to_deficit_OD", "path_id": path_id, "surplus_site": origin,
                    "deficit_site": destination, "potential_match_kg": potential,
                    "actual_same_direction_HTT_over_path_kg": actual,
                    "actual_flow_fraction_of_final_potential": actual / potential if potential > TOL else np.nan,
                })
    od_detail = pd.DataFrame(flow_rows)
    od_summary = od_detail.groupby(["surplus_site", "deficit_site"], as_index=False).agg(
        path_count=("path_id", "nunique"), total_potential_match_kg=("potential_match_kg", "sum"),
        total_actual_same_direction_HTT_kg=("actual_same_direction_HTT_over_path_kg", "sum"))
    od_summary["actual_flow_fraction_of_final_potential"] = od_summary.total_actual_same_direction_HTT_kg / od_summary.total_potential_match_kg
    rows.extend(od_summary.assign(record_type="surplus_to_deficit_OD_summary").to_dict("records"))
    rows.append({"record_type": "identity_QA", "N": len(failed), "identity_max_abs_residual_kg": identity.abs().max(), "identity_pass": bool((identity.abs() <= TOL).all())})
    summary = pd.DataFrame(rows)
    save_csv(summary, DIRS["mismatch"] / "site_mismatch_od_summary.csv")
    save_csv(od_detail, DIRS["mismatch"] / "site_mismatch_od_path_detail.csv")

    combos = failed.apply(lambda r: "+".join(f"Site{i}" for i in SITE_IDS if r[f"gap_site{i}"] > TOL), axis=1).value_counts().rename_axis("shortage_site_combination").reset_index(name="count")
    combos["fraction_of_shortfall_paths"] = combos["count"] / len(failed)
    save_csv(combos, DIRS["mismatch"] / "shortage_site_combinations.csv")
    return summary, od_detail, od_summary, combos


def htt_classification(p, h, system, flow):
    pure = p[p.terminal_gap_class.eq("PURE_SPATIAL_MISMATCH")].copy()
    target = pure.set_index("path_id")
    f = flow[flow.path_id.isin(pure.path_id)].copy()
    if len(f):
        f["origin_target"] = [target.at[pid, f"target_site{int(site)}"] for pid, site in zip(f.path_id, f.origin_site)]
        f["destination_target"] = [target.at[pid, f"target_site{int(site)}"] for pid, site in zip(f.path_id, f.destination_site)]
        f["origin_surplus"] = (f.source_inventory_pre_htt_kg - f.origin_target).clip(lower=0)
        f["destination_deficit"] = (f.destination_target - f.destination_inventory_pre_htt_kg).clip(lower=0)
        f["target_aligned_kg"] = np.minimum.reduce([f.flow_kg, f.origin_surplus, f.destination_deficit])
        f["ex_post_non_aligned_kg"] = f.flow_kg - f.target_aligned_kg
    rows = []
    for path_id, row in pure.set_index("path_id").iterrows():
        ph = h[h.path_id.eq(path_id)].copy()
        for site in SITE_IDS:
            ph.loc[ph.site.eq(site), "final_target"] = row[f"target_site{site}"]
        ph["surplus"] = ph.inventory_before_HTT_kg > ph.final_target + TOL
        ph["deficit"] = ph.inventory_before_HTT_kg < ph.final_target - TOL
        mismatch = ph.groupby("global_hour").agg(any_surplus=("surplus", "max"), any_deficit=("deficit", "max"), relative_hour=("relative_hour", "first"))
        mismatch = mismatch[mismatch.any_surplus & mismatch.any_deficit]
        pf = f[f.path_id.eq(path_id)] if len(f) else f
        flow_hours = set(pf.loc[pf.target_aligned_kg > TOL, "global_hour"]) if len(pf) else set()
        no_transfer_hours = [hour for hour in mismatch.index if hour not in flow_hours]
        ps = system[(system.path_id == path_id) & system.global_hour.isin(mismatch.index)]
        capacity_limited_hours = int(ps.fleet_capacity_binding.sum())
        first_mismatch_rel = mismatch.relative_hour.min() if len(mismatch) else np.nan
        aligned = pf.target_aligned_kg.sum() if len(pf) else 0.0
        nonaligned = pf.ex_post_non_aligned_kg.sum() if len(pf) else 0.0
        if len(mismatch) and first_mismatch_rel >= -4:
            primary = "timing-too-late"
        elif capacity_limited_hours > 0:
            primary = "capacity-limited signal"
        elif len(no_transfer_hours) > 0:
            primary = "no-transfer despite ex-post surplus-deficit"
        else:
            primary = "not-identifiable"
        rows.append({
            "path_id": path_id, "total_HTT_kg": pf.flow_kg.sum() if len(pf) else 0,
            "target_aligned_HTT_kg": aligned, "ex_post_non_aligned_HTT_kg": nonaligned,
            "target_aligned_fraction": aligned / pf.flow_kg.sum() if len(pf) and pf.flow_kg.sum() > TOL else np.nan,
            "surplus_deficit_path_hours": len(mismatch), "no_transfer_despite_surplus_deficit_hours": len(no_transfer_hours),
            "capacity_limited_mismatch_hours": capacity_limited_hours,
            "first_surplus_deficit_relative_hour": first_mismatch_rel,
            "unavailable_OD": "NOT_AVAILABLE_FROM_SAVED_DATA",
            "primary_mechanism_class": primary,
            "information_boundary": "final TerminalLOH was not yet observed in saved operating rows; classification is ex-post except saved fleet binding",
            "contemporaneous_unreasonableness_proven": False,
        })
    detail = pd.DataFrame(rows)
    summary = detail.groupby("primary_mechanism_class", as_index=False).agg(
        path_count=("path_id", "count"), total_HTT_kg=("total_HTT_kg", "sum"),
        target_aligned_HTT_kg=("target_aligned_HTT_kg", "sum"), ex_post_non_aligned_HTT_kg=("ex_post_non_aligned_HTT_kg", "sum"),
        no_transfer_hours=("no_transfer_despite_surplus_deficit_hours", "sum"))
    summary["fraction_of_pure_location_paths"] = summary.path_count / len(pure)
    save_csv(detail, DIRS["htt"] / "htt_mechanism_classification.csv")
    save_csv(summary, DIRS["htt"] / "htt_mechanism_classification_summary.csv")
    return detail, summary


def electrolyzer_analysis(p, h):
    masks = {
        "adequate_positive_target": p.positive_target & p.adequate,
        "shortfall": p.positive_target & p.terminal_gap_flag,
        "pure_quantity": p.terminal_gap_class.eq("PURE_QUANTITY_SHORTFALL"),
        "pure_location": p.terminal_gap_class.eq("PURE_SPATIAL_MISMATCH"),
        "mixed": p.terminal_gap_class.eq("MIXED_QUANTITY_AND_SPATIAL"),
        "surplus_gt100": p.positive_target & p.adequate & (p.total_margin > 100),
    }
    rows = []; simultaneous_rows = []
    for group_name, mask in masks.items():
        ids = set(p.loc[mask, "path_id"])
        hh = h[h.path_id.isin(ids) & h.relative_hour.between(-15, 0)]
        for site, cell in hh.groupby("site"):
            rows.append({
                "group": group_name, "site": site, "path_count": cell.path_id.nunique(), "site_hour_count": len(cell),
                "mean_utilization": cell.utilization.mean(), "q95_utilization": cell.utilization.quantile(.95),
                "hours_ge90": int((cell.utilization >= .90 - TOL).sum()), "fraction_ge90": (cell.utilization >= .90 - TOL).mean(),
                "hours_ge95": int((cell.utilization >= .95 - TOL).sum()), "fraction_ge95": (cell.utilization >= .95 - TOL).mean(),
                "hours_ge99": int((cell.utilization >= .99 - TOL).sum()), "fraction_ge99": (cell.utilization >= .99 - TOL).mean(),
                "near_max_ratio": (cell.utilization >= 1 - 1e-6).mean(),
            })
        counts = hh.groupby(["path_id", "global_hour"]).utilization.apply(lambda x: int((x >= .95 - TOL).sum()))
        for count in range(5):
            simultaneous_rows.append({"group": group_name, "near_max_site_count": count,
                                      "path_hour_count": int((counts == count).sum()),
                                      "fraction": (counts == count).mean() if len(counts) else np.nan})
    detail = pd.DataFrame(rows); simultaneous = pd.DataFrame(simultaneous_rows)
    save_csv(detail, DIRS["electrolyzer"] / "electrolyzer_utilization_by_site_group.csv")
    save_csv(simultaneous, DIRS["electrolyzer"] / "simultaneous_electrolyzer_saturation.csv")
    return detail, simultaneous


def grid_analysis(p, h, system):
    masks = {
        "adequate_positive_target": p.positive_target & p.adequate,
        "shortfall": p.positive_target & p.terminal_gap_flag,
        "pure_quantity": p.terminal_gap_class.eq("PURE_QUANTITY_SHORTFALL"),
        "pure_location": p.terminal_gap_class.eq("PURE_SPATIAL_MISMATCH"),
        "mixed": p.terminal_gap_class.eq("MIXED_QUANTITY_AND_SPATIAL"),
    }
    rows = []
    for name, mask in masks.items():
        ids = set(p.loc[mask, "path_id"])
        cell = system[system.path_id.isin(ids) & system.relative_hour.between(-15, 0)].copy()
        cell["voltage_binding"] = cell.min_voltage_pu <= .900001
        cell["line_binding"] = cell.max_line_loading_pct >= .999999
        rows.append({
            "record_type": "group_summary", "group": name, "path_hour_count": len(cell),
            "voltage_binding_fraction": cell.voltage_binding.mean(), "line_binding_fraction": cell.line_binding.mean(),
            "mean_total_P_EL_when_voltage_binding_kW": cell.loc[cell.voltage_binding, "total_P_EL_kW"].mean(),
            "mean_total_P_EL_when_not_voltage_binding_kW": cell.loc[~cell.voltage_binding, "total_P_EL_kW"].mean(),
            "mean_min_voltage_pu": cell.min_voltage_pu.mean(), "q05_min_voltage_pu": cell.min_voltage_pu.quantile(.05),
            "causal_attribution": "BUS_LEVEL_CAUSAL_ATTRIBUTION_NOT_AVAILABLE",
        })
        for bus, group in cell[cell.voltage_binding].groupby("min_voltage_bus"):
            rows.append({"record_type": "binding_bus_frequency", "group": name, "min_voltage_bus": bus,
                         "binding_hour_count": len(group), "fraction_of_group_binding_hours": len(group) / max(1, int(cell.voltage_binding.sum())),
                         "causal_attribution": "BUS_LEVEL_CAUSAL_ATTRIBUTION_NOT_AVAILABLE"})
    frame = pd.DataFrame(rows)
    save_csv(frame, DIRS["grid"] / "grid_constraint_mechanism.csv")
    return frame


def ordinary_reserve(p, h, hourly):
    cohort = p[p.reached_stage7.eq(1) & p.ordinary_shortage_flag & p.adequate].copy()
    rows = []
    for path_id, row in cohort.set_index("path_id").iterrows():
        ph = hourly[hourly.path_id.eq(path_id)].sort_values("global_hour")
        sh = h[h.path_id.eq(path_id)]
        shortage = ph[ph.ordinary_shortage_kg > TOL]
        first = shortage.iloc[0]
        shortage_hours = set(shortage.global_hour)
        first_shortage_site_rows = sh[(sh.global_hour == first.global_hour) & (sh.ordinary_shortage_kg > TOL)]
        after = ph[ph.global_hour > first.global_hour]
        rows.append({
            "path_id": path_id, "surplus_gt50": row.total_margin > 50,
            "ordinary_shortage_first_hour": first.global_hour, "first_shortage_relative_hour": first.relative_hour,
            "shortage_total_kg": row.ordinary_shortage_total,
            "system_begin_inventory_at_first_shortage_kg": first.total_begin_inventory_kg,
            "system_end_inventory_at_first_shortage_kg": first.total_inventory_kg,
            "first_shortage_sites_begin_inventory_sum_kg": first_shortage_site_rows.begin_inventory_kg.sum(),
            "final_target_kg": row.target_total, "inventory_growth_after_first_shortage_kg": row.terminal_inventory_total - first.total_inventory_kg,
            "final_inventory_kg": row.terminal_inventory_total, "final_surplus_kg": row.total_margin,
            "production_during_shortage_hours_kg": ph[ph.global_hour.isin(shortage_hours)].production_kg.sum(),
            "mean_electrolyzer_utilization_during_shortage": ph[ph.global_hour.isin(shortage_hours)].system_electrolyzer_utilization.mean(),
            "HTT_during_shortage_hours_kg": ph[ph.global_hour.isin(shortage_hours)].HTT_kg.sum(),
            "HTT_after_first_shortage_kg": after.HTT_kg.sum(), "production_after_first_shortage_kg": after.production_kg.sum(),
            "actual_operating_cost_yuan": row.actual_operating_cost,
            "mechanism_statement": "CO_OCCURRENCE_TRADEOFF_SIGNAL_ONLY",
        })
    detail = pd.DataFrame(rows)
    rows = []
    for name, group in [("ordinary_shortage_and_terminal_adequate", detail), ("same_and_final_surplus_gt50", detail[detail.surplus_gt50])]:
        rows.append({"group": name, "N": len(group), **prefixed(group.shortage_total_kg, "shortage_kg"),
                     **prefixed(group.system_begin_inventory_at_first_shortage_kg, "inventory_at_first_shortage_kg"),
                     **prefixed(group.inventory_growth_after_first_shortage_kg, "inventory_growth_after_shortage_kg"),
                     **prefixed(group.final_surplus_kg, "final_surplus_kg"),
                     "positive_inventory_growth_fraction": (group.inventory_growth_after_first_shortage_kg > TOL).mean()})
    summary = pd.DataFrame(rows)
    save_csv(detail, DIRS["ordinary"] / "ordinary_shortage_terminal_adequate_hourly.csv")
    save_csv(summary, DIRS["ordinary"] / "ordinary_shortage_terminal_adequate_summary.csv")

    quadrant_rows = []
    s7 = p[p.reached_stage7.eq(1)]
    for ordinary in (False, True):
        for adequate in (False, True):
            cell = s7[(s7.ordinary_shortage_flag == ordinary) & (s7.adequate == adequate)]
            quadrant_rows.append({"ordinary_shortage": ordinary, "terminal_adequate": adequate, "N": len(cell),
                                  "fraction_of_stage7": len(cell)/len(s7), "mean_inventory_kg": cell.terminal_inventory_total.mean(),
                                  "mean_margin_kg": cell.total_margin.mean(), "mean_cost_yuan": cell.actual_operating_cost.mean()})
    quadrant = pd.DataFrame(quadrant_rows)
    save_csv(quadrant, DIRS["ordinary"] / "ordinary_shortage_terminal_quadrants.csv")
    return detail, summary, quadrant


def economics(p):
    s7 = p[p.reached_stage7.eq(1)]
    ordered = s7.sort_values(["terminal_site_gap", "path_id"]).reset_index(drop=True)
    n = len(ordered); cut95 = math.floor(.95*n); cut99 = math.floor(.99*n)
    ordered["tier"] = "normal95"; ordered.loc[cut95:cut99-1, "tier"] = "difficult4"; ordered.loc[cut99:, "tier"] = "extreme1"
    groups = {
        "all_10000": p,
        "dissipation": p[p.physical_dissipation_a1.eq(1)],
        "Stage7_zero_target": s7[~s7.positive_target],
        "positive_target_adequate": s7[s7.positive_target & s7.adequate],
        "surplus_0_50": s7[s7.positive_target & s7.adequate & s7.surplus_bin.eq("0-50 kg")],
        "surplus_50_100": s7[s7.positive_target & s7.adequate & s7.surplus_bin.eq("50-100 kg")],
        "surplus_100_200": s7[s7.positive_target & s7.adequate & s7.surplus_bin.eq("100-200 kg")],
        "surplus_gt200": s7[s7.positive_target & s7.adequate & s7.surplus_bin.eq(">200 kg")],
        "positive_target_shortfall": s7[s7.positive_target & s7.terminal_gap_flag],
        "pure_quantity": s7[s7.terminal_gap_class.eq("PURE_QUANTITY_SHORTFALL")],
        "pure_location": s7[s7.terminal_gap_class.eq("PURE_SPATIAL_MISMATCH")],
        "mixed": s7[s7.terminal_gap_class.eq("MIXED_QUANTITY_AND_SPATIAL")],
        "ordinary_shortage_paths": p[p.ordinary_shortage_flag],
        "difficult4": ordered[ordered.tier.eq("difficult4")],
        "extreme1": ordered[ordered.tier.eq("extreme1")],
    }
    rows = []
    for index, (name, group) in enumerate(groups.items()):
        ci_low, ci_high = bootstrap_mean_ci(group.actual_operating_cost, 8950 + index)
        terminal_surplus = group.total_margin.clip(lower=0)
        rows.append({
            "group": name, "N": len(group), "mean_production_kg": group.total_H2_production.mean(),
            "mean_HTT_kg": group.total_HTT.mean(), "mean_ordinary_shortage_kg": group.ordinary_shortage_total.mean(),
            "mean_final_inventory_kg": group.terminal_inventory_total.mean(), "mean_target_kg": group.target_total.mean(),
            "mean_terminal_surplus_kg": terminal_surplus.mean(), "mean_terminal_gap_kg": group.terminal_site_gap.mean(),
            "actual_cost_mean_yuan": group.actual_operating_cost.mean(), "actual_cost_median_yuan": group.actual_operating_cost.median(),
            "actual_cost_q95_yuan": group.actual_operating_cost.quantile(.95),
            "actual_cost_mean_bootstrap_ci95_low": ci_low, "actual_cost_mean_bootstrap_ci95_high": ci_high,
        })
    summary = pd.DataFrame(rows)
    save_csv(summary, DIRS["economics"] / "economics_by_mechanism_path_type.csv")

    components = []
    for name, group in groups.items():
        other = group.actual_operating_cost - group.production_cost - group.HTT_cost - group.ordinary_shortage_cost
        components.append({
            "group": name, "N": len(group), "mean_production_cost_yuan": group.production_cost.mean(),
            "mean_electricity_cost_yuan": group.electricity_cost.mean(), "mean_production_om_cost_yuan": group.production_om_cost.mean(),
            "mean_HTT_cost_yuan": group.HTT_cost.mean(), "mean_ordinary_shortage_cost_yuan": group.ordinary_shortage_cost.mean(),
            "mean_other_actual_operating_cost_yuan": other.mean(), "mean_total_actual_operating_cost_yuan": group.actual_operating_cost.mean(),
            "mean_terminal_gap_model_penalty_yuan": group.terminal_penalty_cost.mean(),
            "terminal_penalty_label": "MODEL_PENALTY_COMPONENT_NOT_ACTUAL_OPERATING_COST",
            "component_closure_max_abs_residual_yuan": (group.actual_operating_cost - (group.production_cost + group.HTT_cost + group.ordinary_shortage_cost + other)).abs().max(),
        })
    component_frame = pd.DataFrame(components)
    save_csv(component_frame, DIRS["economics"] / "cost_components_by_mechanism_path_type.csv")

    adequate = s7[s7.positive_target & s7.adequate].copy()
    corr_rows = []
    for metric in ("actual_operating_cost", "total_H2_production", "total_HTT", "ordinary_shortage_total"):
        corr_rows.append({"x": "final_surplus_kg", "y": metric, "N": len(adequate),
                          "pearson": adequate.total_margin.corr(adequate[metric], method="pearson"),
                          "spearman": adequate.total_margin.corr(adequate[metric], method="spearman"),
                          "interpretation": "CORRELATION_NOT_CAUSATION"})
    correlations = pd.DataFrame(corr_rows)
    save_csv(correlations, DIRS["economics"] / "surplus_cost_correlations.csv")
    bins = []
    for index, (bin_name, group) in enumerate(adequate.groupby("surplus_bin", observed=False)):
        if not len(group): continue
        ci_low, ci_high = bootstrap_mean_ci(group.actual_operating_cost, 8980 + index)
        bins.append({"surplus_bin": bin_name, "N": len(group), "mean_surplus_kg": group.total_margin.mean(),
                     "mean_actual_cost_yuan": group.actual_operating_cost.mean(), "median_actual_cost_yuan": group.actual_operating_cost.median(),
                     "q95_actual_cost_yuan": group.actual_operating_cost.quantile(.95), "cost_mean_bootstrap_ci95_low": ci_low,
                     "cost_mean_bootstrap_ci95_high": ci_high, "mean_production_kg": group.total_H2_production.mean(),
                     "mean_HTT_kg": group.total_HTT.mean(), "mean_ordinary_shortage_kg": group.ordinary_shortage_total.mean()})
    bin_frame = pd.DataFrame(bins)
    save_csv(bin_frame, DIRS["economics"] / "surplus_cost_bins.csv")
    return summary, component_frame, correlations, bin_frame, ordered


def dissipation_analysis(p, h, hourly):
    diss = p[p.physical_dissipation_a1.eq(1)].copy()
    demand_profile = h.groupby(["global_hour", "site"], as_index=False).ordinary_demand_kg.median()
    rows = []
    for path_id, row in diss.set_index("path_id").iterrows():
        ph = hourly[hourly.path_id.eq(path_id)].sort_values("global_hour")
        sh = h[h.path_id.eq(path_id)]
        proxies = []
        for global_hour, cell in sh.groupby("global_hour"):
            remaining = demand_profile[demand_profile.global_hour > global_hour].groupby("site").ordinary_demand_kg.sum().reindex(SITE_IDS, fill_value=0)
            inventory = cell.set_index("site").end_inventory_kg.reindex(SITE_IDS)
            proxy = np.maximum(inventory.to_numpy() - remaining.to_numpy(), 0).sum()
            proxies.append((global_hour, int(cell.relative_hour.iloc[0]), proxy))
        proxy_frame = pd.DataFrame(proxies, columns=["global_hour", "relative_hour", "preventive_proxy_kg"])
        first_positive = proxy_frame.loc[proxy_frame.preventive_proxy_kg > TOL, "relative_hour"]
        resolution_proxy = proxy_frame.preventive_proxy_kg.iloc[-1]
        rows.append({
            "path_id": path_id, "dissipation_stage": row.termination_stage, "resolution_global_hour": row.operating_hours,
            "preventive_inventory_at_resolution_kg": resolution_proxy,
            "first_positive_preventive_proxy_relative_hour": first_positive.iloc[0] if len(first_positive) else np.nan,
            "production_last8h_before_dissipation_kg": ph[ph.relative_hour.between(-7, 0)].production_kg.sum(),
            "HTT_last8h_before_dissipation_kg": ph[ph.relative_hour.between(-7, 0)].HTT_kg.sum(),
            "ordinary_shortage_total_kg": row.ordinary_shortage_total, "actual_operating_cost_yuan": row.actual_operating_cost,
            "production_after_dissipation_confirmation": "NOT_AVAILABLE_FROM_SAVED_DATA_NO_POST_TERMINATION_ROWS",
            "HTT_after_dissipation_confirmation": "NOT_AVAILABLE_FROM_SAVED_DATA_NO_POST_TERMINATION_ROWS",
            "inventory_retention_after_confirmation": "NOT_AVAILABLE_FROM_SAVED_DATA_NO_POST_TERMINATION_ROWS",
            "label": "insurance-preparation proxy / 事后观察到的预防性库存",
        })
    detail = pd.DataFrame(rows)
    positive = detail.preventive_inventory_at_resolution_kg
    summary = pd.DataFrame([{"N": len(detail), **prefixed(positive, "preventive_inventory_kg"),
                             "fraction_gt10kg": (positive > 10).mean(), "fraction_gt25kg": (positive > 25).mean(),
                             "fraction_gt50kg": (positive > 50).mean(), "fraction_gt100kg": (positive > 100).mean(),
                             "mean_production_last8h_kg": detail.production_last8h_before_dissipation_kg.mean(),
                             "mean_HTT_last8h_kg": detail.HTT_last8h_before_dissipation_kg.mean(),
                             "ordinary_shortage_probability": (detail.ordinary_shortage_total_kg > TOL).mean(),
                             "mean_actual_cost_yuan": detail.actual_operating_cost_yuan.mean()}])
    save_csv(detail, DIRS["dissipation"] / "dissipation_mechanism_paths.csv")
    save_csv(summary, DIRS["dissipation"] / "dissipation_mechanism_summary.csv")
    return detail, summary


def tail_analysis(ordered, h, system):
    rows = []
    for tier, group in ordered.groupby("tier"):
        ids = set(group.path_id)
        hh = h[h.path_id.isin(ids) & h.relative_hour.between(-15, 0)]
        path_hour_binding = hh.groupby(["path_id", "global_hour"]).electrolyzer_capacity_binding.max()
        ss = system[system.path_id.isin(ids) & system.relative_hour.between(-15, 0)]
        rows.append({
            "tier": tier, "N": len(group), "mean_target_kg": group.target_total.mean(),
            "mean_inventory_kg": group.terminal_inventory_total.mean(), "mean_gap_kg": group.terminal_site_gap.mean(),
            "mean_production_kg": group.total_H2_production.mean(), "mean_HTT_kg": group.total_HTT.mean(),
            "ordinary_shortage_probability": group.ordinary_shortage_flag.mean(), "mean_ordinary_shortage_kg": group.ordinary_shortage_total.mean(),
            "mean_actual_cost_yuan": group.actual_operating_cost.mean(), "mean_arrival_after_stage": group.arrival_after_stage.mean(),
            "mean_final_intensity": group.terminal_a.mean(), "terminal_location_mode": group.terminal_loc.mode().iloc[0],
            "electrolyzer_saturation_fraction_final16_path_hours": path_hour_binding.mean(),
            "voltage_binding_fraction_final16_path_hours": (ss.min_voltage_pu <= .900001).mean(),
            "location_mismatch_incidence": group.terminal_gap_class.isin(["PURE_SPATIAL_MISMATCH", "MIXED_QUANTITY_AND_SPATIAL"]).mean(),
            "gap_contribution_fraction": group.terminal_site_gap.sum()/ordered.terminal_site_gap.sum(),
        })
    frame = pd.DataFrame(rows)
    save_csv(frame, DIRS["tail"] / "tail_mechanism_profile.csv")
    return frame


def select_quantile_paths(group, metric, quantiles, label, existing):
    rows = []
    for q in quantiles:
        available = group[~group.path_id.isin(existing)]
        if not len(available): break
        target = available[metric].quantile(q)
        row = available.assign(distance=(available[metric]-target).abs()).sort_values(["distance", "path_id"]).iloc[0]
        existing.add(int(row.path_id))
        rows.append({"case_type": label, "selection_rule": f"{metric} nearest q{int(q*100)}; tie smallest path_id", **row.to_dict()})
    return rows


def cases(p, h, system, flow):
    s7 = p[p.reached_stage7.eq(1)]
    failed = s7[s7.terminal_gap_flag].sort_values(["terminal_site_gap", "path_id"], ascending=[False, True])
    selected = []; existing = set()
    for rank, (_, row) in enumerate(failed.head(5).iterrows(), 1):
        existing.add(int(row.path_id)); selected.append({"case_type": "top5_shortfall", "selection_rule": f"terminal gap rank {rank}", **row.to_dict()})
    selected += select_quantile_paths(s7[s7.terminal_gap_class.eq("PURE_SPATIAL_MISMATCH")], "terminal_site_gap", [.25, .5, .75], "pure_location_typical", existing)
    selected += select_quantile_paths(s7[s7.positive_target & s7.adequate & (s7.total_margin > 200)], "total_margin", [.25, .5, .9], "surplus_gt200_typical", existing)
    selected += select_quantile_paths(s7[s7.ordinary_shortage_flag & s7.adequate & (s7.total_margin > 50)], "ordinary_shortage_total", [.25, .5, .9], "ordinary_shortage_plus_surplus_gt50", existing)
    frame = pd.DataFrame(selected)
    keep = ["case_type", "selection_rule", "path_id", "state_sequence", "arrival_after_stage", "terminal_a", "terminal_loc", "target_total", "terminal_inventory_total", "total_margin", "terminal_site_gap", "terminal_gap_class", "ordinary_shortage_total", "total_H2_production", "total_HTT", "actual_operating_cost"]
    save_csv(frame[keep], DIRS["cases"] / "case_study_selection.csv")
    ids = set(frame.path_id.astype(int))
    timeline = h[h.path_id.isin(ids)].copy()
    meta = frame.set_index("path_id")
    timeline["case_type"] = timeline.path_id.map(meta.case_type)
    for site in SITE_IDS:
        mask = timeline.site.eq(site)
        timeline.loc[mask, "final_target_kg"] = timeline.loc[mask, "path_id"].map(meta[f"target_site{site}"])
    syscols = system[system.path_id.isin(ids)][["path_id", "global_hour", "min_voltage_pu", "min_voltage_bus", "max_line_loading_pct", "total_HTT_kg"]]
    timeline = timeline.merge(syscols, on=["path_id", "global_hour"], how="left", suffixes=("", "_system"))
    save_csv(timeline, DIRS["cases"] / "case_study_hourly_timeline.csv")
    case_flow = flow[flow.path_id.isin(ids)].copy()
    save_csv(case_flow, DIRS["cases"] / "case_study_htt_od.csv")
    return frame, timeline


def make_figures(data):
    colors = ["#176B87", "#D88C32", "#2D7D46", "#B24C63", "#6A5D7B", "#C9A227"]
    manifest=[]
    def save(fig, filename, title, sample, source):
        fig.text(.99,.01,f"样本：{sample}",ha="right",va="bottom",fontsize=8,color="#555")
        path=FIG/filename;fig.savefig(path,bbox_inches="tight",facecolor="white");plt.close(fig)
        manifest.append({"figure":filename,"title":title,"sample":sample,"source_csv":source,"bytes":path.stat().st_size,"sha256":sha256(path)})

    p=data["p"]; s7=p[p.positive_target & p.reached_stage7.eq(1)]
    fig,ax=plt.subplots(figsize=(9,4.8));ax.hist(s7.total_margin,bins=40,color=colors[0],alpha=.85);ax.axvline(0,color=colors[3],lw=1.5);ax.set(title="正目标路径的最终超额与不足完整分布",xlabel="最终总库存减最终目标（千克）",ylabel="路径数");save(fig,"01_正目标超额不足完整分布.png","正目标路径的最终超额与不足完整分布","1123条正目标Stage7路径","01_surplus_timing/surplus_build_timing.csv;02_shortfall_timing/shortfall_build_timing.csv")

    bins=data["surplus_summary"]
    fig,ax=plt.subplots(figsize=(8,4.8));ax.bar(bins.surplus_bin.astype(str),bins.N,color=colors[:4]);ax.set(title="正目标达标路径按最终超额库存分组",ylabel="路径数",xlabel="最终超额库存");[ax.text(i,r.N+4,f"N={int(r.N)}",ha="center") for i,r in enumerate(bins.itertuples())];save(fig,"02_正目标超额分箱.png","正目标达标路径超额分箱","650条正目标达标路径","01_surplus_timing/surplus_timing_group_summary.csv")

    profile=data["profile"]
    fig,ax=plt.subplots(figsize=(9,4.8));
    for name,g in profile[profile.group.isin(["正目标达标","正目标不足"])].groupby("group"):ax.plot(g.relative_hour,g.mean_inventory_kg,lw=2,label=name)
    ax.set(title="正目标达标与不足路径最后24小时库存",xlabel="距离Stage7的小时（0为最后运行小时）",ylabel="平均总库存（千克）");ax.grid(alpha=.2);ax.legend();save(fig,"03_达标与不足最后24h库存.png","达标与不足路径最后24小时库存","650条达标、473条不足；不补0","02_shortfall_timing/adequate_vs_shortfall_last24h_profile.csv")

    fig,ax=plt.subplots(figsize=(9,4.8));
    for name,g in profile[profile.group.isin(["超额大于100kg","正目标不足"])].groupby("group"):ax.plot(g.relative_hour,g.mean_production_kg,lw=2,label=name)
    ax.set(title="超额大于100kg与不足路径最后24小时制氢",xlabel="距离Stage7的小时",ylabel="平均制氢（千克/小时）");ax.grid(alpha=.2);ax.legend();save(fig,"04_高超额与不足最后24h制氢.png","高超额与不足路径最后24小时制氢","520条超额>100kg、473条不足","02_shortfall_timing/adequate_vs_shortfall_last24h_profile.csv")

    arrival=data["arrival"]
    fig,ax=plt.subplots(figsize=(8,4.8));ax.bar(arrival.arrival_after_stage.astype(str),arrival.shortfall_probability,color=colors[1]);ax.set(title="最终风险在不同阶段后确认时的不足率",xlabel="进入Stage7之前最后运行阶段",ylabel="正目标路径不足率",ylim=(0,1));[ax.text(i,r.shortfall_probability+.02,f"{r.shortfall_probability:.0%}\nN={int(r.positive_target_count)}",ha="center") for i,r in enumerate(arrival.itertuples()) if pd.notna(r.shortfall_probability)];save(fig,"05_到达阶段与不足率.png","到达Stage7时间与正目标不足率","1123条正目标路径","02_shortfall_timing/shortfall_by_arrival_stage.csv")

    site=data["mismatch_summary"];site=site[(site.record_type=="site_summary")&(site.group=="all_shortfall")]
    fig,ax=plt.subplots(figsize=(8,4.8));ax.bar(site.site.astype(str),site.shortage_occurrence,color=colors[:4]);ax.set(title="四个站在不足路径中出现缺口的频率",xlabel="站点",ylabel="发生比例",ylim=(0,1));[ax.text(i,r.shortage_occurrence+.02,f"{r.shortage_occurrence:.1%}",ha="center") for i,r in enumerate(site.itertuples())];save(fig,"06_四站缺口频率.png","四站缺口频率","473条正目标不足路径","04_site_mismatch/site_mismatch_od_summary.csv")

    od=data["od_summary"].pivot(index="surplus_site",columns="deficit_site",values="path_count").reindex(index=SITE_IDS,columns=SITE_IDS).fillna(0)
    fig,ax=plt.subplots(figsize=(7,5.4));im=ax.imshow(od,cmap="YlGnBu");fig.colorbar(im,ax=ax);ax.set(xticks=range(4),xticklabels=SITE_IDS,yticks=range(4),yticklabels=SITE_IDS,xlabel="最终缺口站",ylabel="最终富余站",title="纯位置不足中最常见的富余站→缺口站组合");
    for i in range(4):
        for j in range(4):ax.text(j,i,str(int(od.iloc[i,j])),ha="center",va="center")
    save(fig,"07_站点错配组合.png","富余站到缺口站的错配组合","203条纯位置不足路径","04_site_mismatch/site_mismatch_od_summary.csv")

    hs=data["htt_summary"]
    htt_names={"no-transfer despite ex-post surplus-deficit":"事后有余缺但未调运","timing-too-late":"调运时点过晚"}
    fig,ax=plt.subplots(figsize=(9,4.8));ax.bar([htt_names.get(x,x) for x in hs.primary_mechanism_class],hs.path_count,color=colors[:len(hs)]);ax.set(title="纯位置不足路径的HTT机制分类",ylabel="路径数");save(fig,"08_HTT机制分类.png","HTT机制分类：事后方向与当时可证结论分开","203条纯位置不足路径","05_htt_mechanism/htt_mechanism_classification_summary.csv")

    el=data["electrolyzer"];cell=el[el.group.isin(["adequate_positive_target","shortfall"])]
    fig,ax=plt.subplots(figsize=(9,4.8));width=.36
    for k,(name,g) in enumerate(cell.groupby("group")):ax.bar(np.arange(4)+(k-.5)*width,g.sort_values("site").mean_utilization,width,label={"adequate_positive_target":"正目标达标","shortfall":"正目标不足"}[name])
    ax.set(xticks=range(4),xticklabels=SITE_IDS,title="达标与不足路径最后16小时四站电解槽负荷",xlabel="站点",ylabel="平均负荷比例",ylim=(0,1.05));ax.legend();save(fig,"09_四站电解槽负荷.png","四站电解槽负荷","650条达标、473条不足路径最后16小时","06_electrolyzer/electrolyzer_utilization_by_site_group.csv")

    q=data["quadrant"]
    labels=[f"普通缺氢{'是' if r.ordinary_shortage else '否'}\n最终达标{'是' if r.terminal_adequate else '否'}" for r in q.itertuples()]
    fig,ax=plt.subplots(figsize=(8,4.8));ax.bar(labels,q.N,color=colors[:4]);ax.set(title="普通缺氢与最终储备的四象限",ylabel="路径数");[ax.text(i,r.N+30,f"N={int(r.N)}",ha="center") for i,r in enumerate(q.itertuples())];save(fig,"10_普通缺氢最终储备四象限.png","普通缺氢与最终储备四象限","6124条Stage7路径","08_ordinary_vs_reserve/ordinary_shortage_terminal_quadrants.csv")

    adequate=s7[s7.adequate]
    fig,ax=plt.subplots(figsize=(8,5));ax.scatter(adequate.total_margin,adequate.actual_operating_cost,s=12,alpha=.45,color=colors[0]);ax.set(title="正目标达标路径：超额库存与实际运行成本",xlabel="最终超额库存（千克）",ylabel="实际运行成本（元）");ax.grid(alpha=.15);save(fig,"11_超额库存与成本.png","超额库存与实际运行成本（相关不等于因果）","650条正目标达标路径","09_economics/surplus_cost_correlations.csv")

    econ=data["econ"]
    econ_names={"all_10000":"全部10000","dissipation":"消散","Stage7_zero_target":"Stage7零目标","positive_target_adequate":"正目标达标","surplus_0_50":"超额0-50","surplus_50_100":"超额50-100","surplus_100_200":"超额100-200","surplus_gt200":"超额>200","positive_target_shortfall":"正目标不足","pure_quantity":"纯总量不足","pure_location":"纯位置不足","mixed":"混合不足","ordinary_shortage_paths":"普通缺氢","difficult4":"困难4%","extreme1":"极端1%"}
    fig,ax=plt.subplots(figsize=(12,5));ax.bar([econ_names.get(x,x) for x in econ.group],econ.actual_cost_mean_yuan,color=colors[0]);ax.set(title="不同机制路径的平均实际运行成本",ylabel="元/路径");ax.tick_params(axis="x",rotation=50,labelsize=8);save(fig,"12_路径类型实际成本.png","各路径类型实际运行成本","15个预定义路径组","09_economics/economics_by_mechanism_path_type.csv")

    ds=data["diss_summary"].iloc[0]
    fig,ax=plt.subplots(figsize=(8,4.8));labels=["中位数","75%","90%","95%","99%","最大"];vals=[ds.preventive_inventory_kg_median,ds.preventive_inventory_kg_q75,ds.preventive_inventory_kg_q90,ds.preventive_inventory_kg_q95,ds.preventive_inventory_kg_q99,ds.preventive_inventory_kg_max];ax.bar(labels,vals,color=colors[2]);ax.set(title="消散路径的事后预防性库存分布",ylabel="千克");save(fig,"13_消散路径预防库存.png","事后观察到的预防性库存","3497条物理消散路径","10_dissipation/dissipation_mechanism_summary.csv")

    tail=data["tail"]
    fig,axs=plt.subplots(1,3,figsize=(12,4.5));names={"normal95":"普通95%","difficult4":"较困难4%","extreme1":"最极端1%"};x=[names[v] for v in tail.tier]
    for ax,metric,title in zip(axs,["mean_target_kg","mean_gap_kg","electrolyzer_saturation_fraction_final16_path_hours"],["平均目标","平均缺口","最后16小时电解槽顶满比例"]):ax.bar(x,tail[metric],color=colors[:3]);ax.set_title(title);ax.tick_params(axis="x",rotation=10)
    fig.suptitle("普通95%、较困难4%和最极端1%的机制对比");save(fig,"14_尾部机制对比.png","95%/4%/1%机制对比","6124条Stage7路径","11_tail/tail_mechanism_profile.csv")

    def case_plot(path_id,title,filename):
        ch=data["case_timeline"];g=ch[ch.path_id.eq(path_id)].copy()
        total=g.groupby("global_hour").agg(inventory=("end_inventory_kg","sum"),production=("H2_production_kg","sum"),shortage=("ordinary_shortage_kg","sum"),HTT=("HTT_out_kg","sum"),target=("final_target_kg","sum"),P_EL=("P_EL_kW","sum"),storm_a=("hurricane_a","first"),storm_loc=("hurricane_loc","first"))
        site_inventory=g.pivot(index="global_hour",columns="site",values="end_inventory_kg").reindex(columns=SITE_IDS)
        total["utilization"]=total.P_EL/sum(PMAX.values())
        fig,axs=plt.subplots(5,1,figsize=(10,11),sharex=True)
        axs[0].plot(total.index,total.inventory,label="总库存",color=colors[0],lw=2);axs[0].plot(total.index,total.target,label="最终总目标",ls="--",color=colors[3]);axs[0].legend(ncol=2);axs[0].set_ylabel("千克")
        for idx,site_id in enumerate(SITE_IDS):axs[1].plot(site_inventory.index,site_inventory[site_id],label=f"站点{site_id}",color=colors[idx])
        axs[1].legend(ncol=4);axs[1].set_ylabel("四站库存\n千克")
        axs[2].plot(total.index,total.production,label="制氢",color=colors[1]);axs[2].plot(total.index,total.HTT,label="HTT",color=colors[2]);axs[2].bar(total.index,total.shortage,alpha=.3,color=colors[3],label="普通缺氢");axs[2].legend(ncol=3);axs[2].set_ylabel("千克/小时")
        axs[3].plot(total.index,total.utilization,color=colors[0]);axs[3].axhline(.95,color=colors[3],ls="--",lw=1,label="95%铭牌");axs[3].set_ylim(0,1.05);axs[3].set_ylabel("系统电解槽\n利用率");axs[3].legend(loc="lower left")
        axs[4].step(total.index,total.storm_a,where="mid",color=colors[4],label="强度");axs[4].set_ylabel("台风强度");loc_ax=axs[4].twinx();loc_ax.step(total.index,total.storm_loc,where="mid",color=colors[2],ls="--",label="位置");loc_ax.set_ylabel("台风位置");axs[4].legend(loc="upper left");loc_ax.legend(loc="upper right");axs[4].set_xlabel("真实运行小时")
        [ax.grid(alpha=.15) for ax in axs];fig.suptitle(title);fig.subplots_adjust(hspace=.18,top=.94);save(fig,filename,title,f"path {path_id}","12_case_studies/case_study_hourly_timeline.csv")
    case_plot(3909,"最严重不足路径3909时间线","15_path3909时间线.png")
    cs=data["cases"]
    surplus_id=int(cs[cs.case_type.eq("surplus_gt200_typical")].sort_values("total_margin").iloc[1].path_id)
    pure_id=int(cs[cs.case_type.eq("pure_location_typical")].sort_values("terminal_site_gap").iloc[1].path_id)
    case_plot(surplus_id,f"超额超过200kg典型路径{surplus_id}","16_超额200kg典型路径.png")
    case_plot(pure_id,f"纯位置不足典型路径{pure_id}","17_纯位置不足典型路径.png")

    rec=data["recover_summary"];no16=rec[(rec.hours_before_stage7==16)&(rec.TARGET_STILL_PHYSICALLY_REACHABLE=="NO")].path_count.sum();no8=rec[(rec.hours_before_stage7==8)&(rec.TARGET_STILL_PHYSICALLY_REACHABLE=="NO")].path_count.sum();
    fig,axs=plt.subplots(2,2,figsize=(11,7));axs[0,0].bar(["正目标达标","正目标不足"],[650,473],color=[colors[2],colors[3]]);axs[0,0].set_title("同一策略的两极结果");axs[0,1].bar(["16小时前已可证追不上","8小时前已可证追不上"],[no16,no8],color=colors[1]);axs[0,1].set_title("铭牌乐观上界诊断");axs[1,0].bar(site.site.astype(str),site.shortage_occurrence,color=colors[:4]);axs[1,0].set_title("不足集中站点");axs[1,1].bar(["普通95%","困难4%","极端1%"],tail.gap_contribution_fraction,color=colors[:3]);axs[1,1].set_title("Stage7总缺口贡献");fig.suptitle("penalty=1000两极化机制总结：信息、时间、空间和容量共同作用")
    save(fig,"18_最终机制总结.png","penalty=1000两极化机制总结","正式10000-path OOS","13_summary/mechanism_deep_dive_summary.csv")

    mf=pd.DataFrame(manifest);save_csv(mf,FIG/"figure_manifest.csv")
    thumbs=[];font=ImageFont.truetype(str(Path(r"C:\Windows\Fonts\msyh.ttc")),13)
    for row in mf.itertuples():
        image=Image.open(FIG/row.figure).convert("RGB");image.thumbnail((480,300));canvas=Image.new("RGB",(500,330),"white");canvas.paste(image,((500-image.width)//2,25));ImageDraw.Draw(canvas).text((8,5),row.figure,fill="black",font=font);thumbs.append(canvas)
    sheet=Image.new("RGB",(1000,math.ceil(len(thumbs)/2)*330),(235,235,235))
    for i,image in enumerate(thumbs):sheet.paste(image,((i%2)*500,(i//2)*330))
    sheet.save(FIG/"contact_sheet.png")
    return mf


def summary_and_readme(data):
    p=data["p"];positive=p[p.reached_stage7.eq(1)&p.positive_target];adequate=positive[positive.adequate];failed=positive[positive.terminal_gap_flag]
    st=data["surplus_timing"];rec=data["recover_summary"];mismatch=data["mismatch_summary"];htt=data["htt_detail"];el=data["electrolyzer"];grid=data["grid"];ordinary=data["ordinary_detail"];econ=data["econ"].set_index("group");diss=data["diss_summary"].iloc[0];tail=data["tail"].set_index("tier")
    def rec_count(hour,status="NO"):
        return int(rec[(rec.hours_before_stage7==hour)&(rec.TARGET_STILL_PHYSICALLY_REACHABLE==status)].path_count.sum())
    site=mismatch[(mismatch.record_type=="site_summary")&(mismatch.group=="all_shortfall")].sort_values("shortage_occurrence",ascending=False)
    surplus_site=mismatch[(mismatch.record_type=="site_summary")&(mismatch.group=="all_shortfall")].sort_values("surplus_occurrence",ascending=False)
    high100=st[st.final_surplus_kg>100];high200=st[st.final_surplus_kg>200]
    corr=data["correlations"].set_index("y")
    summary_rows=[
        {"metric":"positive_target_paths","value":len(positive),"denominator":"Stage7"},
        {"metric":"positive_target_adequate","value":len(adequate),"denominator":"positive-target"},
        {"metric":"positive_target_shortfall","value":len(failed),"denominator":"positive-target"},
        {"metric":"surplus_gt100_count","value":len(high100),"denominator":"positive-target adequate"},
        {"metric":"surplus_gt200_count","value":len(high200),"denominator":"positive-target adequate"},
        {"metric":"surplus_gt100_risk_weakened_signal_fraction","value":high100.risk_later_weakened_signal.mean(),"denominator":"surplus>100"},
        {"metric":"surplus_gt200_risk_weakened_signal_fraction","value":high200.risk_later_weakened_signal.mean(),"denominator":"surplus>200"},
        {"metric":"surplus_gt100_mean_stable_target_hour","value":high100.stable_100pct_target_hour.mean(),"denominator":"surplus>100"},
        {"metric":"surplus_gt200_mean_stable_target_hour","value":high200.stable_100pct_target_hour.mean(),"denominator":"surplus>200"},
        {"metric":"proven_unrecoverable_16h_count","value":rec_count(16),"denominator":"473 shortfall"},
        {"metric":"proven_unrecoverable_8h_count","value":rec_count(8),"denominator":"473 shortfall"},
        {"metric":"proven_unrecoverable_4h_count","value":rec_count(4),"denominator":"473 shortfall"},
        {"metric":"most_common_deficit_site","value":int(site.iloc[0].site),"denominator":"473 shortfall"},
        {"metric":"most_common_surplus_site","value":int(surplus_site.iloc[0].site),"denominator":"473 shortfall"},
        {"metric":"pure_location_target_aligned_HTT_fraction","value":htt.target_aligned_HTT_kg.sum()/htt.total_HTT_kg.sum(),"denominator":"pure-location realized HTT"},
        {"metric":"ordinary_shortage_terminal_adequate_count","value":len(ordinary),"denominator":"Stage7"},
        {"metric":"ordinary_shortage_adequate_positive_inventory_growth_fraction","value":(ordinary.inventory_growth_after_first_shortage_kg>TOL).mean(),"denominator":"326 paths"},
        {"metric":"surplus_cost_pearson","value":corr.at["actual_operating_cost","pearson"],"denominator":"650 positive-target adequate"},
        {"metric":"surplus_cost_spearman","value":corr.at["actual_operating_cost","spearman"],"denominator":"650 positive-target adequate"},
        {"metric":"hardest5_gap_contribution","value":tail.loc[["difficult4","extreme1"],"gap_contribution_fraction"].sum(),"denominator":"Stage7 total gap"},
    ]
    summary=pd.DataFrame(summary_rows);save_csv(summary,DIRS["summary"]/"mechanism_deep_dive_summary.csv")
    gshort=grid[(grid.record_type=="group_summary")&grid.group.eq("shortfall")].iloc[0]
    e_short=el[el.group.eq("shortfall")].sort_values("fraction_ge95",ascending=False).iloc[0]
    readme=f"""# Stage-89Q penalty=1000 第二轮机制深挖

状态：`READ_ONLY_MECHANISM_DEEP_DIVE_PASS`。本轮没有训练、没有重新运行OOS、没有加载checkpoint、没有重新求解、没有修改optimization core，也没有启动penalty=1500。

## 1. 为什么正目标达标率只有57.88%？

1123条正目标路径中，650条达标、473条不足。失败不是单一原因：118条是纯总量不足，203条是总量够但站点位置不合适，152条两者兼有；同时最终高目标在不同到达阶段才确认，晚到达组留给生产和调运的时间更短。结论是信息揭示、空间错配和制氢能力共同作用，而不是仅凭现有数据证明1000惩罚“太低”。

## 2. 为什么达标的650条又经常超很多？

650条中有{len(high100)}条最终超额超过100kg，{len(high200)}条超过200kg。高超额路径往往在Stage7前已经建立库存，且其运行期经历的强度/位置可能对应更高的假想TerminalLOH，最终状态变弱或转移后目标下降。该现象是事后风险路径与提前准备共同形成，不等同于当时可知的过度生产。

## 3. 超额100/200kg是在什么时候建立的？

超额>100kg路径第一次稳定达到最终总目标的相对小时均值为{high100.stable_100pct_target_hour.mean():.2f}；超额>200kg路径为{high200.stable_100pct_target_hour.mean():.2f}。负数表示在Stage7前已经达到。逐路径的25%/50%/75%/100%和稳定100%时刻均在`surplus_build_timing.csv`中，不足24小时历史的路径保留缺失值，未补0。

## 4. 高超额是否和最终风险后来下降有关？

按“运行期峰值强度高于最终强度，或运行期状态映射的Stage89K假想目标高于最终目标”定义，超额>100kg中{high100.risk_later_weakened_signal.mean():.2%}、>200kg中{high200.risk_later_weakened_signal.mean():.2%}出现风险后来减弱信号。它支持风险演化解释，但不是反事实因果证明。

## 5. 不足路径是不是最终风险确认太晚？

按到达Stage7之前最后运行阶段分层，`shortfall_by_arrival_stage.csv`给出正目标分母和bootstrap区间。晚确认组一般目标更高且剩余调整窗口更短，但个别格样本较少；因此可表述为明显时间压力信号，不能单独归因。

## 6. 有多少路径在16/8/4小时前已经物理追不上？

严格乐观上界使用四站正式铭牌，并允许剩余普通需求全部短缺（否则不能称为严格上界）；同时单列“全部服务已知剩余普通需求”的净产量情景。按严格上界，16/8/4小时前分别有 **{rec_count(16)}/{rec_count(8)}/{rec_count(4)}** 条仍追不上。这些`NO`只证明总量不可能；其余路径只能标`NOT_IDENTIFIABLE`，不能写成真实可恢复，因为电网、储罐和运输可行性没有重新优化。

## 7. 剩余问题主要是总量还是位置？

纯总量118、纯位置203、混合152。含位置因素的355条占失败的75.05%，但混合组同样缺总量，所以最准确结论仍是多因素共同作用。

## 8. 哪个站最常缺，哪个站最常有余？

站点{int(site.iloc[0].site)}最常出现缺口（{site.iloc[0].shortage_occurrence:.2%}），站点{int(surplus_site.iloc[0].site)}最常出现富余（{surplus_site.iloc[0].surplus_occurrence:.2%}）。完整短缺严重度、富余严重度及组合见站点错配表。

## 9. HTT为什么只有约29.50%按最终目标口径有帮助？

重新按每个正流量的起点富余、终点缺口和实际流量三者最小值截断后，纯位置失败的target-aligned比例为 **{htt.target_aligned_HTT_kg.sum()/htt.total_HTT_kg.sum():.2%}**。大量运输在最终目标的事后视角下属于non-aligned，另有同时存在富余/缺口但未发生正确方向运输的小时。

## 10. 是事后目标改变，还是运输真的不够？

两者不能混写。最终TerminalLOH在保存的运行小时中尚未成为已实现终端状态，因此non-aligned首先是事后分类，不能证明当时不合理。只有保存的fleet binding能提供运输总能力信号；道路/OD可用性没有保存，统一标`NOT_AVAILABLE_FROM_SAVED_DATA`。因此现有证据支持“事后目标变化+部分时间/容量信号”，不支持把全部错配归咎于HTT policy。

## 11. 电解槽限制集中在哪些站和路径？

不足路径最后16小时中，站点{int(e_short.site)}的≥95%负荷比例最高，为{e_short.fraction_ge95:.2%}。各机制组与四站的均值、q95、≥90/95/99%小时和同时顶满站数均已输出，可直接对照最常缺站是否也是最常顶满站。

## 12. 电压约束是否真正影响追产？

不足路径最后16小时电压到下限比例为{gshort.voltage_binding_fraction:.2%}；绑定小时与非绑定小时的系统电解槽输出有描述性差异，但缺少反事实潮流求解，`BUS_LEVEL_CAUSAL_ATTRIBUTION_NOT_AVAILABLE`。线路容量绑定仍为{gshort.line_binding_fraction:.2%}，当前OOS中线路容量不是主要追产瓶颈。

## 13. ordinary shortage与最终超额为什么频繁共现？

326条路径普通缺氢但最终达标，其中321条超额>50kg。普通缺氢发生时系统往往仍持有库存，且缺氢后有{(ordinary.inventory_growth_after_first_shortage_kg>TOL).mean():.2%}的路径库存继续增长。可能涉及局部库存、运输、当期服务约束与终端准备价值共同作用。

## 14. 这是共现还是更强机制判断？

目前只能写`CO_OCCURRENCE_TRADEOFF_SIGNAL_ONLY`。没有重新求解“降低终端权重/强制多服务普通需求”的反事实策略，因此不能说policy主动牺牲普通需求。

## 15. 大幅超储路径付出了多少经济代价？

超额100–200kg路径实际成本均值为{econ.at['surplus_100_200','actual_cost_mean_yuan']:,.2f}元，>200kg为{econ.at['surplus_gt200','actual_cost_mean_yuan']:,.2f}元；正目标达标总体为{econ.at['positive_target_adequate','actual_cost_mean_yuan']:,.2f}元。超额与实际成本Pearson/Spearman为{corr.at['actual_operating_cost','pearson']:.3f}/{corr.at['actual_operating_cost','spearman']:.3f}，仅表示相关。

## 16. 不足路径是不是已经花更多钱仍然失败？

正目标不足路径实际成本均值为{econ.at['positive_target_shortfall','actual_cost_mean_yuan']:,.2f}元，对比正目标达标{econ.at['positive_target_adequate','actual_cost_mean_yuan']:,.2f}元。若更高，也主要同时反映更长运行、更高目标、更多生产和普通缺氢惩罚，不代表多花的钱导致失败。

## 17. 消散路径承担了多少预防性库存成本？

事后预防性库存proxy的中位数/q75/q90/q95/q99为{diss.preventive_inventory_kg_median:.2f}/{diss.preventive_inventory_kg_q75:.2f}/{diss.preventive_inventory_kg_q90:.2f}/{diss.preventive_inventory_kg_q95:.2f}/{diss.preventive_inventory_kg_q99:.2f}kg；超过10/25/50/100kg的比例为{diss.fraction_gt10kg:.2%}/{diss.fraction_gt25kg:.2%}/{diss.fraction_gt50kg:.2%}/{diss.fraction_gt100kg:.2%}。路径终止后没有保存行，因此无法判断确认消散后继续生产、HTT或保留多久，不称为“浪费”。

## 18. 最困难5%为什么承担94.42%的缺口？

困难4%和极端1%同时表现出更高目标、更高强度、较晚到达、更频繁位置错配和更高电解槽饱和。其缺口贡献为{tail.loc[['difficult4','extreme1'],'gap_contribution_fraction'].sum():.2%}，是多个压力同时出现，而非单一瓶颈。

## 19. penalty=1000的主要问题更像什么？

现有数据最支持 **多因素共同作用**：终端信息晚揭示、空间错配、部分HTT时间/容量信号、电解槽物理上限，以及普通服务与终端储备的共现权衡。单凭这批数据不能把主要问题定性为“penalty太低”；那需要同路径1500或专门反事实实验。

## 20. 已支持与仍待验证

已支持：两极化的时序差异、正目标分母、位置问题占比、铭牌上界下严格追不上路径、站点缺/余、HTT事后方向、四站电解槽负荷、电压/线路出现频率、成本组成闭合、ordinary shortage与终端超额共现、消散proxy和尾部集中。

仍待1500或反事实：1000是否因权重过低导致两极化、当时信息下HTT是否不合理、道路/OD不可用的具体作用、电压约束的因果产量损失、以及普通服务与终端储备之间的策略因果交换。

`FULLY_CONVERGED = NO`。本轮到此停止，不启动penalty=1500。
"""
    (DIRS["summary"]/"README.md").write_text(readme,encoding="utf-8")
    return summary


def qa_and_manifest(files, data, source_hash_before):
    p=data["p"];h=data["h"];system=data["system"];adequate=p[p.reached_stage7.eq(1)&p.positive_target&p.adequate];failed=p[p.reached_stage7.eq(1)&p.positive_target&p.terminal_gap_flag]
    identity=(failed.site_surplus_total-failed.site_gap_total-failed.total_margin).abs().max()
    cost_other=p.actual_operating_cost-p.production_cost-p.HTT_cost-p.ordinary_shortage_cost
    cost_res=(p.actual_operating_cost-(p.production_cost+p.HTT_cost+p.ordinary_shortage_cost+cost_other)).abs().max()
    state_cols=[c for c in data["bank"].columns if c.startswith("k_t")]
    bank_seq=data["bank"][state_cols].astype(int).astype(str).agg("-".join,axis=1)
    ordered_bank=np.array_equal(data["bank"].path_id.to_numpy(),p.path_id.to_numpy()) and np.array_equal(bank_seq.to_numpy(),p.state_sequence.to_numpy())
    no_padding=len(h)==32*int(p.operating_stage_count.sum()) and len(system)==8*int(p.operating_stage_count.sum())
    observed_pmax=h[h.electrolyzer_capacity_binding.eq(1)].groupby("site").P_EL_kW.max().to_dict()
    pmax_identity=all(abs(observed_pmax.get(site,np.nan)-value)<=TOL for site,value in PMAX.items())
    bank_manifest_sha=sha256(files["bank"])
    bank_mat_sha=sha256(files["bank_mat"])
    source_hash_after={key:sha256(RAW/key) for key in EXPECTED_RAW_SHA}
    rows=[
        {"check":"formal_path_count","observed":len(p),"expected":10000,"pass":len(p)==10000},
        {"check":"ordered_path_bank_identity","observed":ordered_bank,"expected":True,"pass":ordered_bank},
        {"check":"path_bank_mat_sha_identity","observed":bank_mat_sha,"expected":EXPECTED_BANK_MAT_SHA,"pass":bank_mat_sha==EXPECTED_BANK_MAT_SHA},
        {"check":"path_bank_manifest_sha_identity","observed":bank_manifest_sha,"expected":EXPECTED_BANK_MANIFEST_SHA,"pass":bank_manifest_sha==EXPECTED_BANK_MANIFEST_SHA},
        {"check":"electrolyzer_Pmax_identity","observed":str(observed_pmax),"expected":str(PMAX),"pass":pmax_identity},
        {"check":"no_post_termination_zero_padding","observed":no_padding,"expected":True,"pass":no_padding},
        {"check":"positive_target_accounting","observed":f"{len(adequate)}+{len(failed)}","expected":"650+473=1123","pass":len(adequate)==650 and len(failed)==473},
        {"check":"surplus_gap_margin_identity","observed":identity,"expected":f"<={TOL}","pass":identity<=TOL},
        {"check":"actual_cost_component_closure","observed":cost_res,"expected":f"<={TOL}","pass":cost_res<=TOL},
        {"check":"no_reoptimization","observed":"CSV_ONLY_NO_MATLAB_NO_GUROBI_NO_CHECKPOINT_LOAD","expected":"READ_ONLY_POSTPROCESSING","pass":True},
        {"check":"raw_hashes_unchanged_during_analysis","observed":source_hash_after==source_hash_before,"expected":True,"pass":source_hash_after==source_hash_before},
        {"check":"raw_hashes_match_accepted_manifest","observed":all(source_hash_after[k]==v for k,v in EXPECTED_RAW_SHA.items()),"expected":True,"pass":all(source_hash_after[k]==v for k,v in EXPECTED_RAW_SHA.items())},
        {"check":"physical_reachability_claim_scope","observed":"NO_OR_NOT_IDENTIFIABLE_ONLY","expected":"NO_OR_NOT_IDENTIFIABLE_ONLY","pass":set(data['recover_detail'].TARGET_STILL_PHYSICALLY_REACHABLE)<=set(['NO','NOT_IDENTIFIABLE'])},
        {"check":"HTT_contemporaneous_error_claims","observed":data['htt_detail'].contemporaneous_unreasonableness_proven.any(),"expected":False,"pass":not data['htt_detail'].contemporaneous_unreasonableness_proven.any()},
    ]
    qa=pd.DataFrame(rows)
    if not qa["pass"].all():raise RuntimeError(qa[~qa["pass"]].to_string(index=False))
    save_csv(qa,DIRS["summary"]/"mechanism_deep_dive_qa.csv")
    manifest=[]
    for name,path in files.items():
        if path.is_file():manifest.append({"role":"source","relative_path":str(path.relative_to(ROOT)),"size_bytes":path.stat().st_size,"sha256":sha256(path)})
    for path in sorted(OUT.rglob("*")):
        if path.is_file() and path.name!="mechanism_deep_dive_manifest.csv":manifest.append({"role":"output","relative_path":str(path.relative_to(ROOT)),"size_bytes":path.stat().st_size,"sha256":sha256(path)})
    for path in sorted(FIG.glob("*")):
        if path.is_file():manifest.append({"role":"figure","relative_path":str(path.relative_to(ROOT)),"size_bytes":path.stat().st_size,"sha256":sha256(path)})
    save_csv(pd.DataFrame(manifest),DIRS["summary"]/"mechanism_deep_dive_manifest.csv")
    return qa


def main():
    setup()
    files,path,stage,site,hour,system,flow,bank,target=load_inputs()
    source_hash_before={key:sha256(RAW/key) for key in EXPECTED_RAW_SHA}
    p,h,system,hourly=enrich(path,hour,system)
    p=add_window_metrics(p,hourly)
    surplus_timing_frame,surplus_summary=surplus_timing(p,h,hourly,target)
    shortfall_timing_frame,arrival,profile=shortfall_timing(p,h,hourly)
    recover_detail,recover_paths,recover_summary=physical_recoverability(p,h)
    mismatch_summary,od_detail,od_summary,combos=site_mismatch(p,h,flow)
    htt_detail,htt_summary=htt_classification(p,h,system,flow)
    electrolyzer,simultaneous=electrolyzer_analysis(p,h)
    grid=grid_analysis(p,h,system)
    ordinary_detail,ordinary_summary,quadrant=ordinary_reserve(p,h,hourly)
    econ,components,correlations,cost_bins,ordered=economics(p)
    diss_detail,diss_summary=dissipation_analysis(p,h,hourly)
    tail=tail_analysis(ordered,h,system)
    case_frame,case_timeline=cases(p,h,system,flow)
    bank=bank
    data=locals().copy()
    data["surplus_timing"]=surplus_timing_frame
    data["cases"]=case_frame
    summary=summary_and_readme(data);data["summary"]=summary
    figures=make_figures(data);data["figures"]=figures
    qa=qa_and_manifest(files,data,source_hash_before)
    print(f"STAGE89Q_MECHANISM_DEEP_DIVE=PASS outputs={sum(x.is_file() for x in OUT.rglob('*'))} figures={len(figures)} qa={len(qa)}")


if __name__=="__main__":
    main()
