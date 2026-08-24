#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Read-only Stage89Q HTT flexibility and wait-and-see audit."""

from __future__ import annotations

import argparse
import ast
import hashlib
import math
import os
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
OUT = RUN / "05_analysis/10_deep_penalty1000/16_htt_flexibility_audit"
FIG = RUN / "06_figures/10_penalty1000_htt_flexibility_audit"
TARGET = ROOT / "terminalLoh_wdro/current_w_mainline_stage89/terminal_tables/terminal_loh_stage89k_dro_eta003_adopted.csv"
BANK = RUN / "03_oos/common/oos_path_manifest.csv"
BANK_IDENTITY = RUN / "03_oos/common/bank_identity.csv"
OLD_RECOVER = RUN / "05_analysis/10_deep_penalty1000/15_mechanism_deep_dive/03_physical_recoverability/physical_recoverability_diagnostic.csv"
OLD_CANDIDATE = RUN / "05_analysis/10_deep_penalty1000/06_spatial_htt/pure_location_failure_diagnosis.csv"
TRAINING = ROOT / "results/task-002-stage2b-b3-smoke/stage89q-penalty1000-vs1500-long-training/run-002/02_training/penalty1000/training_summary.csv"

DIRS = {
    "model": OUT / "01_model_audit",
    "physical": OUT / "02_physical_limits",
    "upper": OUT / "03_capacity_upper_bound",
    "sensitivity": OUT / "04_cap_sensitivity",
    "alignment": OUT / "05_information_alignment",
    "underdispatch": OUT / "06_underdispatch",
    "od": OUT / "07_od_structure",
    "flex": OUT / "08_temporal_vs_spatial_flexibility",
    "economics": OUT / "09_economics",
    "summary": OUT / "10_summary",
    "qa": OUT / "11_qa",
}

TOL = 1e-7
SITE_IDS = [1, 2, 3, 4]
TANK_CAP = {1: 300.0, 2: 200.0, 3: 100.0, 4: 200.0}
PMAX = {1: 300.0, 2: 200.0, 3: 120.0, 4: 150.0}
CUTS = [-16, -8, -4]
RELATIVE_CHECKPOINTS = [-24, -16, -8, -4, -2, -1]
MULTIPLIERS = [1.0, 1.25, 1.5, 2.0, math.inf]
EXPECTED = {
    "path_summary/oos_path_summary.csv": "99ec55faba4e60e88b25d757deb1a8146515faf666d52979fe69c64362047502",
    "path_summary/oos_stage_summary.csv": "969c373a9a2ff1b271cde6fda95a6fe8e64b10362518fe4b807c0dc86437c15d",
    "path_summary/oos_stage_site_summary.csv": "eab41bdf5d58fc971bc65af8c5745de3bd08cc25a0a4d44cc386aeba3f99c89e",
    "hourly_site/oos_hour_site.csv": "af3b3d5c4aa69e6d29b35a88008b4d82360c4b8391fc783141078f7ad68b0cda",
    "grid_hourly/oos_hour_system.csv": "b9eaa83ee3e8a720f3cb5afd5d54da050c2d3ef45c434efe74f8ba8b976b63c6",
    "htt_od/oos_positive_htt_flows.csv": "06a6586574a155eb4588cae691898b3ebda509a79e14e64c8453918b7262fe4a",
}
EXPECTED_BANK_MAT = "6bf3d1190a402ded052b8d3d08ed369042236e151f562bdd9fd4db7b8ff386c6"
EXPECTED_BANK_CSV = "a186e8d4ac870082d0925a05311ab8f4c5a0b70cb61b6fd06955a48a647b3941"
EXPECTED_TARGET = "2fa1958944110701239a109ebf46d959324a351f2f27c1c3fbd62f333066eaa8"


def io_path(path: Path) -> str:
    resolved = str(path.resolve())
    return f"\\\\?\\{resolved}" if os.name == "nt" and not resolved.startswith("\\\\?\\") else resolved


def dotted_name(node: ast.AST) -> str:
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        prefix = dotted_name(node.value)
        return f"{prefix}.{node.attr}" if prefix else node.attr
    return ""


def forbidden_capability_references(path: Path) -> list[str]:
    tree = ast.parse(Path(path).read_text(encoding="utf-8"))
    references = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            references.extend(alias.name for alias in node.names)
        elif isinstance(node, ast.ImportFrom):
            references.append(node.module or "")
        elif isinstance(node, ast.Call):
            references.append(dotted_name(node.func))
    prefixes = ("scipy.optimize", "gurobipy", "cvxpy", "pulp", "np.random", "numpy.random", "random.")
    return sorted({name for name in references if name == "random" or name.startswith(prefixes)})


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with open(io_path(path), "rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def save_csv(frame: pd.DataFrame, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    frame.to_csv(io_path(path), index=False, encoding="utf-8-sig", float_format="%.12g")


def setup() -> None:
    for directory in [OUT, FIG, *DIRS.values()]:
        directory.mkdir(parents=True, exist_ok=True)
    fonts = {item.name for item in font_manager.fontManager.ttflist}
    font = next((name for name in ("Microsoft YaHei", "Microsoft YaHei UI", "SimHei") if name in fonts), None)
    if font is None:
        raise RuntimeError("No Chinese font is available")
    plt.rcParams.update({"font.family": font, "axes.unicode_minus": False, "font.size": 10,
                         "figure.dpi": 140, "savefig.dpi": 180})


def raw_paths() -> dict[str, Path]:
    paths = {name: RAW / name for name in EXPECTED}
    paths.update({
        "bank": BANK,
        "bank_identity": BANK_IDENTITY,
        "target": TARGET,
        "intensity": ROOT / "data/intensity.csv",
        "location": ROOT / "data/location.csv",
        "landfall": ROOT / "data/landfall_7.csv",
        "old_recover": OLD_RECOVER,
        "old_candidate": OLD_CANDIDATE,
        "training": TRAINING,
        "builder": ROOT / "hourly_grid_h2/build_integrated_hourly_stage_model_hourly_htt_v1_h2.m",
        "updater": ROOT / "hourly_grid_h2/update_integrated_hourly_stage_model_hourly_htt_v1_h2.m",
        "solver": ROOT / "fa_h2/solve_stage_model_h2.m",
        "loader": ROOT / "load_data_h2_near.m",
        "launcher": ROOT / "fa_msp/current_hourly_stage89_adopted/launcher/run_stage89q_penalty1000_vs1500_5h_hourly_h2.m",
    })
    missing = [f"{name}: {path}" for name, path in paths.items() if not path.is_file()]
    if missing:
        raise RuntimeError("Missing inputs:\n" + "\n".join(missing))
    return paths


def load_data(paths: dict[str, Path]):
    p = pd.read_csv(paths["path_summary/oos_path_summary.csv"])
    stage = pd.read_csv(paths["path_summary/oos_stage_summary.csv"])
    site = pd.read_csv(paths["path_summary/oos_stage_site_summary.csv"])
    hour = pd.read_csv(paths["hourly_site/oos_hour_site.csv"])
    system = pd.read_csv(paths["grid_hourly/oos_hour_system.csv"])
    flow = pd.read_csv(paths["htt_od/oos_positive_htt_flows.csv"])
    bank = pd.read_csv(paths["bank"])
    target = pd.read_csv(paths["target"])
    return p, stage, site, hour, system, flow, bank, target


def classify_paths(p: pd.DataFrame) -> pd.DataFrame:
    out = p.copy()
    out["positive_target"] = out.target_total > TOL
    out["adequate_positive"] = out.positive_target & (out.terminal_site_gap <= TOL)
    out["total_margin"] = out.terminal_inventory_total - out.target_total
    out["path_group"] = np.select(
        [out.terminal_gap_class.eq("PURE_QUANTITY_SHORTFALL"),
         out.terminal_gap_class.eq("PURE_SPATIAL_MISMATCH"),
         out.terminal_gap_class.eq("MIXED_QUANTITY_AND_SPATIAL"),
         out.adequate_positive],
        ["pure_quantity", "pure_location", "mixed", "positive_target_adequate"],
        default="other")
    out["end_hour"] = 8 * out.operating_stage_count
    out["tail_group"] = "not_stage7_tail"
    stage7 = out[out.reached_stage7.eq(1)].sort_values(["terminal_site_gap", "path_id"], ascending=[False, True])
    extreme_ids = set(stage7.head(62).path_id)
    difficult_ids = set(stage7.iloc[62:307].path_id)
    out.loc[out.path_id.isin(difficult_ids), "tail_group"] = "difficult4"
    out.loc[out.path_id.isin(extreme_ids), "tail_group"] = "extreme1"
    return out


def load_matrix(path: Path) -> np.ndarray:
    matrix = pd.read_csv(path).to_numpy(float)
    if matrix.shape[0] != matrix.shape[1] or np.any(matrix < 0):
        raise RuntimeError(f"Invalid transition matrix: {path}")
    return matrix / matrix.sum(axis=1, keepdims=True)


def information_proxy(paths: dict[str, Path], target: pd.DataFrame) -> pd.DataFrame:
    pi = load_matrix(paths["intensity"])
    pl = load_matrix(paths["location"])
    pf = load_matrix(paths["landfall"])
    transition = np.kron(np.kron(pi, pl), pf)
    states = np.array([(a, loc, lf) for a in range(1, 7) for loc in range(1, 8) for lf in range(1, 9)])
    is_a1 = states[:, 0] == 1
    is_lf8 = (states[:, 0] > 1) & (states[:, 2] == 8)
    is_s7 = (states[:, 0] > 1) & (states[:, 2] == 7)
    absorbing = is_a1 | is_lf8 | is_s7
    transient = np.where(~absorbing)[0]
    outcomes = np.zeros((336, 37))
    outcomes[is_a1, 0] = 1
    outcomes[is_lf8, 1] = 1
    s7_idx = np.where(is_s7)[0]
    columns = 2 + (states[s7_idx, 0] - 2) * 7 + states[s7_idx, 1] - 1
    outcomes[s7_idx, columns] = 1
    q = transition[np.ix_(transient, transient)]
    direct = transition[np.ix_(transient, np.where(absorbing)[0])] @ outcomes[absorbing]
    outcomes[transient] = np.linalg.solve(np.eye(len(transient)) - q, direct)
    if np.max(np.abs(outcomes.sum(axis=1) - 1)) > 1e-12:
        raise RuntimeError("Absorption probability closure failed")
    table = target.sort_values(["intensity", "loc"])
    target_matrix = table[[f"T{i}_kg" for i in SITE_IDS]].to_numpy(float)
    p_s7 = outcomes[:, 2:].sum(axis=1)
    expected = outcomes[:, 2:] @ target_matrix
    conditional = np.divide(expected, p_s7[:, None], out=np.full_like(expected, np.nan), where=p_s7[:, None] > 0)
    rows = []
    for idx, (a, loc, lf) in enumerate(states):
        row = {"state_id": idx + 1, "a": a, "loc": loc, "lf": lf,
               "P_a1": outcomes[idx, 0], "P_lf8": outcomes[idx, 1], "P_stage7": p_s7[idx],
               "probability_sum": outcomes[idx].sum(),
               "proxy_definition": "UNCONDITIONAL_E_T_WITH_ZERO_TARGET_FOR_NON_STAGE7_ABSORPTION"}
        for site_id in SITE_IDS:
            row[f"expected_terminal_target_proxy_site{site_id}_kg"] = expected[idx, site_id - 1]
            row[f"conditional_target_given_stage7_site{site_id}_kg"] = conditional[idx, site_id - 1]
        row["expected_terminal_target_proxy_total_kg"] = expected[idx].sum()
        row["conditional_target_given_stage7_total_kg"] = conditional[idx].sum()
        rows.append(row)
    result = pd.DataFrame(rows)
    save_csv(result, DIRS["alignment"] / "information_state_terminal_target_proxy.csv")
    return result


def add_relative_time(p: pd.DataFrame, hour: pd.DataFrame, system: pd.DataFrame):
    ends = p.set_index("path_id").end_hour
    h = hour.copy()
    s = system.copy()
    h["end_hour"] = h.path_id.map(ends)
    s["end_hour"] = s.path_id.map(ends)
    # Decision hour -1 is the last ordinary hour; Stage7 itself is t=0.
    h["relative_hour"] = h.global_hour - h.end_hour - 1
    s["relative_hour"] = s.global_hour - s.end_hour - 1
    return h, s


def group_ids(p: pd.DataFrame) -> dict[str, set[int]]:
    result = {
        "all_paths": set(p.path_id),
        "positive_target_adequate": set(p.loc[p.adequate_positive, "path_id"]),
        "positive_target_shortfall": set(p.loc[p.positive_target & (p.terminal_site_gap > TOL), "path_id"]),
        "pure_quantity": set(p.loc[p.path_group.eq("pure_quantity"), "path_id"]),
        "pure_location": set(p.loc[p.path_group.eq("pure_location"), "path_id"]),
        "mixed": set(p.loc[p.path_group.eq("mixed"), "path_id"]),
        "surplus_gt100": set(p.loc[p.adequate_positive & (p.total_margin > 100), "path_id"]),
        "surplus_gt200": set(p.loc[p.adequate_positive & (p.total_margin > 200), "path_id"]),
        "difficult_5pct": set(p.loc[p.tail_group.isin(["difficult4", "extreme1"]), "path_id"]),
        "extreme_1pct": set(p.loc[p.tail_group.eq("extreme1"), "path_id"]),
    }
    return result


def utilization_audit(p: pd.DataFrame, system: pd.DataFrame):
    groups = group_ids(p)
    rows = []
    rel_rows = []
    for label, ids in groups.items():
        frame = system[system.path_id.isin(ids)]
        u = frame.fleet_utilization
        rows.append({
            "group": label, "path_count": len(ids), "real_hour_count": len(frame),
            "mean_utilization": u.mean(), "median_utilization": u.median(),
            "q90": u.quantile(.90), "q95": u.quantile(.95), "q99": u.quantile(.99),
            **{f"hours_ge_{threshold}": int((u >= threshold).sum()) for threshold in (.80, .90, .95, .99)},
            **{f"fraction_ge_{threshold}": float((u >= threshold).mean()) for threshold in (.80, .90, .95, .99)},
            "exact_binding_hours": int((np.abs(frame.total_HTT_kg - frame.fleet_capacity_kg) <= 1e-6).sum()),
            "exact_binding_fraction": float((np.abs(frame.total_HTT_kg - frame.fleet_capacity_kg) <= 1e-6).mean()),
            "near_binding_fraction": float((u >= .99).mean()),
        })
        for rel in RELATIVE_CHECKPOINTS:
            cell = frame[frame.relative_hour.eq(rel)]
            rel_rows.append({"group": label, "relative_hour": rel,
                             "path_count_available": cell.path_id.nunique(), "real_hour_count": len(cell),
                             "mean_utilization": cell.fleet_utilization.mean(),
                             "median_utilization": cell.fleet_utilization.median(),
                             "q95_utilization": cell.fleet_utilization.quantile(.95),
                             "mean_HTT_kg": cell.total_HTT_kg.mean(),
                             "mean_capacity_kg": cell.fleet_capacity_kg.mean(),
                             "binding_fraction": cell.fleet_capacity_binding.mean() if len(cell) else np.nan})
    summary = pd.DataFrame(rows)
    relative = pd.DataFrame(rel_rows)
    save_csv(summary, DIRS["summary"] / "htt_aggregate_utilization_summary.csv")
    save_csv(relative, DIRS["summary"] / "htt_aggregate_utilization_by_relative_hour.csv")
    return summary, relative


def envelope_for_path(path_row: pd.Series, path_hour: pd.DataFrame, path_system: pd.DataFrame,
                      cutoff: int, multiplier: float) -> dict[str, object]:
    start = path_hour[path_hour.relative_hour.eq(cutoff)]
    remaining = path_hour[path_hour.relative_hour.between(cutoff, -1)].copy()
    remaining_system = path_system[path_system.relative_hour.between(cutoff, -1)].sort_values("relative_hour")
    if len(start) != 4 or remaining.relative_hour.nunique() != abs(cutoff) or len(remaining_system) != abs(cutoff):
        return {"valid": False, "reason": "CHECKPOINT_NOT_AVAILABLE_WITHOUT_ZERO_PADDING"}
    target = np.array([path_row[f"target_site{i}"] for i in SITE_IDS], float)
    safe_by_hour = []
    need_by_hour = []
    no_transfer_pre_by_hour = []
    for site_id in SITE_IDS:
        sh = remaining[remaining.site.eq(site_id)].sort_values("relative_hour")
        begin = float(sh.iloc[0].begin_inventory_kg)
        net = (sh.H2_production_kg - sh.ordinary_served_kg).to_numpy(float)
        pre = begin + np.cumsum(net)
        final_margin = float(pre[-1] - target[site_id - 1])
        # A transfer at hour h must preserve both the final target and every later
        # observed ordinary-service inventory level. The shrinking suffix minimum
        # makes this cumulative removable-inventory bound monotone by construction.
        suffix_min_pre = np.minimum.accumulate(pre[::-1])[::-1]
        safe = np.maximum(np.minimum(max(final_margin, 0.0), suffix_min_pre), 0)
        need = np.full_like(pre, max(-final_margin, 0.0))
        safe_by_hour.append(safe)
        need_by_hour.append(need)
        no_transfer_pre_by_hour.append(pre)
    safe_matrix = np.array(safe_by_hour)
    need_matrix = np.array(need_by_hour)
    pre_matrix = np.array(no_transfer_pre_by_hour)
    available = safe_matrix.sum(axis=0)
    required = float(need_matrix[:, 0].sum())
    caps = remaining_system.fleet_capacity_kg.to_numpy(float)
    used = remaining_system.total_HTT_kg.to_numpy(float)
    cumulative = 0.0
    if math.isinf(multiplier):
        cumulative = float(available[-1])
    else:
        for supply, cap in zip(available, caps):
            cumulative = min(float(supply), cumulative + float(cap) * multiplier)
    final_need_sites = need_matrix[:, -1] > TOL
    final_headroom = np.maximum(np.array([TANK_CAP[i] for i in SITE_IDS]) - pre_matrix[:, -1], 0)
    destination_headroom = float(final_headroom[final_need_sites].sum())
    total_cap = math.inf if math.isinf(multiplier) else float(caps.sum() * multiplier)
    final_supply = float(available[-1])
    origin_limit = final_supply + TOL < required
    aggregate_limit = (not math.isinf(multiplier) and final_supply + TOL >= required and total_cap + TOL < required)
    timing_limit = (not math.isinf(multiplier) and final_supply + TOL >= required and total_cap + TOL >= required and cumulative + TOL < required)
    headroom_limit = destination_headroom + TOL < float(need_matrix[:, -1].sum())
    result = {
        "valid": True,
        "origin_inventory_available": float(safe_matrix[:, 0].sum()),
        "total_surplus_kg": final_supply,
        "total_site_shortfall_kg": required,
        "aggregate_htt_capacity_remaining": total_cap,
        "aggregate_htt_used_remaining": float(used.sum()),
        "aggregate_htt_slack_remaining": math.inf if math.isinf(multiplier) else float((caps * multiplier - used).sum()),
        "destination_headroom_total": destination_headroom,
        "minimum_required_redistribution_kg": required,
        "optimistic_redistributable_kg": float(cumulative),
        "origin_inventory_limit_flag": origin_limit,
        "aggregate_capacity_limit_flag": aggregate_limit,
        "destination_headroom_limit_flag": headroom_limit,
        "timing_limit_flag": timing_limit,
        "not_identifiable_flag": cumulative + TOL >= required,
        "optimistic_recoverable_flag": cumulative + TOL >= required,
        "final_no_future_HTT_inventory_total_kg": float(pre_matrix[:, -1].sum()),
        "remaining_actual_production_kg": float(remaining.H2_production_kg.sum()),
        "remaining_actual_served_demand_kg": float(remaining.ordinary_served_kg.sum()),
        "remaining_ordinary_demand_kg": float(remaining.ordinary_demand_kg.sum()),
        "remaining_observed_shortage_kg": float(remaining.ordinary_shortage_kg.sum()),
        "source_availability_is_monotone": bool(np.all(np.diff(available) >= -TOL)),
        "reason": "UPPER_BOUND_SUFFICIENT_NOT_FEASIBILITY_PROOF" if cumulative + TOL >= required else "UPPER_BOUND_BELOW_REQUIRED_REDISTRIBUTION",
    }
    for index, site_id in enumerate(SITE_IDS):
        result[f"site{site_id}_origin_inventory_available_at_cutoff_kg"] = float(safe_matrix[index, 0])
        result[f"site{site_id}_origin_inventory_available_final_hour_kg"] = float(safe_matrix[index, -1])
        result[f"site{site_id}_shortfall_at_cutoff_kg"] = float(need_matrix[index, 0])
        result[f"site{site_id}_shortfall_final_hour_kg"] = float(need_matrix[index, -1])
        result[f"site{site_id}_destination_headroom_final_hour_kg"] = float(final_headroom[index])
    return result


def physical_and_sensitivity(p: pd.DataFrame, hour: pd.DataFrame, system: pd.DataFrame):
    selected = p[p.path_group.isin(["pure_location", "mixed"])]
    detail_rows = []
    sensitivity_rows = []
    for _, row in selected.iterrows():
        ph = hour[hour.path_id.eq(row.path_id)]
        ps = system[system.path_id.eq(row.path_id)]
        for cutoff in CUTS:
            base = envelope_for_path(row, ph, ps, cutoff, 1.0)
            record = {"path_id": int(row.path_id), "path_type": row.path_group,
                      "relative_hour": cutoff, **base}
            if base.get("valid"):
                infinite = envelope_for_path(row, ph, ps, cutoff, math.inf)
                record["infinite_cap_optimistic_redistributable_kg"] = infinite["optimistic_redistributable_kg"]
                record["infinite_cap_optimistic_recoverable_flag"] = infinite["optimistic_recoverable_flag"]
            detail_rows.append(record)
            for multiplier in MULTIPLIERS:
                result = envelope_for_path(row, ph, ps, cutoff, multiplier)
                sensitivity_rows.append({"path_id": int(row.path_id), "path_type": row.path_group,
                                         "relative_hour": cutoff,
                                         "HTT_CAP_MULTIPLIER": "INF" if math.isinf(multiplier) else f"{multiplier:.2f}",
                                         "base_capacity_kg_per_h": 160,
                                         "valid": result.get("valid", False),
                                         "minimum_required_redistribution_kg": result.get("minimum_required_redistribution_kg", np.nan),
                                         "optimistic_redistributable_kg": result.get("optimistic_redistributable_kg", np.nan),
                                         "optimistic_recoverable_flag": result.get("optimistic_recoverable_flag", False),
                                         "reason": result.get("reason")})
    detail = pd.DataFrame(detail_rows)
    sens_detail = pd.DataFrame(sensitivity_rows)
    save_csv(detail, DIRS["physical"] / "htt_physical_limit_by_path_time.csv")
    comparison = detail[["path_id", "path_type", "relative_hour", "valid",
                         "minimum_required_redistribution_kg", "optimistic_redistributable_kg",
                         "optimistic_recoverable_flag", "infinite_cap_optimistic_redistributable_kg",
                         "infinite_cap_optimistic_recoverable_flag", "reason"]].rename(
        columns={"optimistic_redistributable_kg": "current_cap_optimistic_redistributable_kg",
                 "optimistic_recoverable_flag": "current_cap_optimistic_recoverable_flag"})
    save_csv(comparison, DIRS["upper"] / "current_vs_infinite_htt_upper_bound.csv")
    summary_rows = []
    for (ptype, rel), group in comparison[comparison.valid].groupby(["path_type", "relative_hour"]):
        current = int(group.current_cap_optimistic_recoverable_flag.sum())
        infinite = int(group.infinite_cap_optimistic_recoverable_flag.sum())
        summary_rows.append({"path_type": ptype, "relative_hour": rel, "actual_n": len(group),
                             "current_cap_potentially_recoverable_count": current,
                             "current_cap_upper_bound_unrecoverable_count": len(group) - current,
                             "infinite_cap_potentially_recoverable_count": infinite,
                             "infinite_cap_upper_bound_unrecoverable_count": len(group) - infinite,
                             "incremental_potentially_recovered_by_infinite_cap": infinite - current,
                             "claim_scope": "OPTIMISTIC_CAPACITY_ENVELOPE_NOT_POLICY_OR_FEASIBILITY_OPTIMIZATION"})
    upper_summary = pd.DataFrame(summary_rows)
    save_csv(upper_summary, DIRS["upper"] / "current_vs_infinite_htt_upper_bound_summary.csv")
    save_csv(sens_detail, DIRS["sensitivity"] / "htt_cap_upper_bound_sensitivity_by_path.csv")
    sens_summary_rows = []
    order = ["1.00", "1.25", "1.50", "2.00", "INF"]
    for (ptype, rel), group in sens_detail[sens_detail.valid].groupby(["path_type", "relative_hour"]):
        previous_recovered = None
        previous_numeric = None
        for token in order:
            cell = group[group.HTT_CAP_MULTIPLIER.eq(token)]
            recovered = int(cell.optimistic_recoverable_flag.sum())
            unrecoverable = len(cell) - recovered
            if previous_recovered is None:
                incremental = 0
                marginal = np.nan
            else:
                incremental = recovered - previous_recovered
                if token == "INF":
                    marginal = np.nan
                else:
                    numeric = float(token)
                    marginal = incremental / ((numeric - previous_numeric) / .25)
            sens_summary_rows.append({"path_type": ptype, "relative_hour": rel,
                                      "HTT_CAP_MULTIPLIER": token, "actual_n": len(cell),
                                      "recoverable_count": recovered, "unrecoverable_count": unrecoverable,
                                      "incremental_recovered_paths": incremental,
                                      "marginal_improvement_per_25pct_capacity": marginal,
                                      "claim_scope": "OPTIMISTIC_CAPACITY_ENVELOPE"})
            previous_recovered = recovered
            if token != "INF":
                previous_numeric = float(token)
    sens_summary = pd.DataFrame(sens_summary_rows)
    save_csv(sens_summary, DIRS["sensitivity"] / "htt_cap_upper_bound_sensitivity.csv")
    return detail, comparison, upper_summary, sens_detail, sens_summary


def alignment_audit(p: pd.DataFrame, hour: pd.DataFrame, flow: pd.DataFrame, proxy: pd.DataFrame):
    target_map = p.set_index("path_id")
    proxy_map = proxy.set_index("state_id")
    f = flow.copy()
    for role, site_col, inv_col in [("origin", "origin_site", "source_inventory_pre_htt_kg"),
                                     ("destination", "destination_site", "destination_inventory_pre_htt_kg")]:
        f[f"ex_post_{role}_target_kg"] = [target_map.at[pid, f"target_site{int(site)}"]
                                                    for pid, site in zip(f.path_id, f[site_col])]
        f[f"proxy_{role}_target_kg"] = [proxy_map.at[state, f"expected_terminal_target_proxy_site{int(site)}_kg"]
                                                  for state, site in zip(f.state_id, f[site_col])]
    f["ex_post_origin_surplus_kg"] = (f.source_inventory_pre_htt_kg - f.ex_post_origin_target_kg).clip(lower=0)
    f["ex_post_destination_deficit_kg"] = (f.ex_post_destination_target_kg - f.destination_inventory_pre_htt_kg).clip(lower=0)
    f["information_proxy_origin_surplus_kg"] = (f.source_inventory_pre_htt_kg - f.proxy_origin_target_kg).clip(lower=0)
    f["information_proxy_destination_deficit_kg"] = (f.proxy_destination_target_kg - f.destination_inventory_pre_htt_kg).clip(lower=0)
    f["ex_post_aligned_kg"] = f[["flow_kg", "ex_post_origin_surplus_kg", "ex_post_destination_deficit_kg"]].min(axis=1)
    f["information_proxy_aligned_kg"] = f[["flow_kg", "information_proxy_origin_surplus_kg",
                                           "information_proxy_destination_deficit_kg"]].min(axis=1)
    f["ex_post_non_aligned_kg"] = f.flow_kg - f.ex_post_aligned_kg
    f["conservative_expost_nonaligned_but_information_aligned_kg"] = (
        f.information_proxy_aligned_kg - f.ex_post_aligned_kg).clip(lower=0)
    f["strict_flow_row_reversal"] = (f.ex_post_aligned_kg <= TOL) & (f.information_proxy_aligned_kg > TOL)
    f["alignment_scope"] = "FINAL_TARGET_EX_POST_VS_UNCONDITIONAL_EXPECTED_TERMINAL_TARGET_PROXY"
    path_group = p.set_index("path_id").path_group
    f["path_group"] = f.path_id.map(path_group)
    groups = {"all_flows": set(p.path_id), "pure_location": set(p.loc[p.path_group.eq("pure_location"), "path_id"]),
              "mixed": set(p.loc[p.path_group.eq("mixed"), "path_id"]),
              "positive_target_adequate": set(p.loc[p.adequate_positive, "path_id"])}
    summaries = []
    for label, ids in groups.items():
        g = f[f.path_id.isin(ids)]
        total = g.flow_kg.sum()
        summaries.append({"record_type": "SUMMARY", "group": label, "path_count_with_HTT": g.path_id.nunique(),
                          "flow_row_count": len(g), "total_HTT_kg": total,
                          "ex_post_aligned_HTT_kg": g.ex_post_aligned_kg.sum(),
                          "ex_post_alignment_fraction": g.ex_post_aligned_kg.sum() / total if total > TOL else np.nan,
                          "information_proxy_aligned_HTT_kg": g.information_proxy_aligned_kg.sum(),
                          "information_proxy_alignment_fraction": g.information_proxy_aligned_kg.sum() / total if total > TOL else np.nan,
                          "strict_reversal_path_count": g.loc[g.strict_flow_row_reversal, "path_id"].nunique(),
                          "strict_reversal_flow_row_count": int(g.strict_flow_row_reversal.sum()),
                          "conservative_expost_nonaligned_but_information_aligned_kg": g.conservative_expost_nonaligned_but_information_aligned_kg.sum(),
                          "proxy_limit": "NOT_CONTINUATION_VALUE_NOT_DRO_CUT_NOT_FORMAL_OPTIMAL_TARGET"})
    detail_cols = ["path_id", "path_group", "stage", "state_id", "global_hour", "origin_site", "destination_site",
                   "flow_kg", "ex_post_origin_target_kg", "ex_post_destination_target_kg",
                   "proxy_origin_target_kg", "proxy_destination_target_kg", "ex_post_aligned_kg",
                   "information_proxy_aligned_kg", "ex_post_non_aligned_kg",
                   "conservative_expost_nonaligned_but_information_aligned_kg", "strict_flow_row_reversal", "alignment_scope"]
    detail = f[detail_cols].copy()
    detail.insert(0, "record_type", "FLOW")
    combined = pd.concat([detail, pd.DataFrame(summaries)], ignore_index=True, sort=False)
    save_csv(combined, DIRS["alignment"] / "htt_alignment_expost_vs_information_proxy.csv")
    return f, pd.DataFrame(summaries)


def information_opportunities(p: pd.DataFrame, hour: pd.DataFrame, system: pd.DataFrame,
                              proxy: pd.DataFrame) -> pd.DataFrame:
    h = hour.merge(proxy[["state_id", *[f"expected_terminal_target_proxy_site{i}_kg" for i in SITE_IDS]]],
                   on="state_id", how="left")
    h["proxy_target_kg"] = [row[f"expected_terminal_target_proxy_site{int(row.site)}_kg"] for _, row in h.iterrows()]
    h["proxy_surplus_kg"] = (h.inventory_before_HTT_kg - h.proxy_target_kg).clip(lower=0)
    h["proxy_deficit_kg"] = (h.proxy_target_kg - h.inventory_before_HTT_kg).clip(lower=0)
    h["proxy_destination_headroom_kg"] = np.where(h.proxy_deficit_kg > TOL,
                                                   h.site.map(TANK_CAP) - h.inventory_before_HTT_kg, 0)
    agg = h.groupby(["path_id", "global_hour", "relative_hour", "state_id"], as_index=False).agg(
        proxy_surplus_kg=("proxy_surplus_kg", "sum"), proxy_deficit_kg=("proxy_deficit_kg", "sum"),
        proxy_destination_headroom_kg=("proxy_destination_headroom_kg", "sum"),
        actual_HTT_kg=("HTT_out_kg", "sum"))
    agg = agg.merge(system[["path_id", "global_hour", "fleet_capacity_kg", "total_HTT_kg", "fleet_utilization"]],
                    on=["path_id", "global_hour"], how="left")
    agg["fleet_slack_kg"] = agg.fleet_capacity_kg - agg.total_HTT_kg
    agg["strict_information_consistent_physical_opportunity_kg"] = agg[["proxy_surplus_kg", "proxy_deficit_kg",
                                                                          "proxy_destination_headroom_kg", "fleet_slack_kg"]].min(axis=1).clip(lower=0)
    agg["strict_opportunity_flag"] = agg.strict_information_consistent_physical_opportunity_kg > TOL
    return agg


def underdispatch_reclassification(p: pd.DataFrame, physical: pd.DataFrame, opportunities: pd.DataFrame,
                                   aligned_flow: pd.DataFrame, candidate: pd.DataFrame):
    source_text = "有库存也有系统HTT空间但未充分调运（道路可达性未保存，属候选诊断）"
    candidates = candidate[candidate.diagnosis.eq(source_text)].copy()
    if len(candidates) != 98:
        raise RuntimeError(f"Candidate under-dispatch source count changed: {len(candidates)}")
    rows = []
    for path_id in candidates.path_id.astype(int):
        pp = physical[(physical.path_id == path_id) & physical.valid.fillna(False)].sort_values("relative_hour")
        op = opportunities[opportunities.path_id.eq(path_id)].sort_values("relative_hour")
        af = aligned_flow[aligned_flow.path_id.eq(path_id)]
        required = float(p.loc[p.path_id.eq(path_id), "terminal_site_gap"].iloc[0])
        no_supply = len(pp) > 0 and bool((pp.total_surplus_kg + TOL < pp.minimum_required_redistribution_kg).all())
        supply16 = pp.loc[pp.relative_hour.eq(-16), "origin_inventory_available"]
        supply8 = pp.loc[pp.relative_hour.eq(-8), "origin_inventory_available"]
        supply4 = pp.loc[pp.relative_hour.eq(-4), "origin_inventory_available"]
        late = (len(supply4) == 1 and supply4.iloc[0] > TOL and
                (len(supply16) == 0 or supply16.iloc[0] <= TOL) and
                (len(supply8) == 0 or supply8.iloc[0] <= TOL))
        cap_limited = bool((pp.aggregate_capacity_limit_flag.fillna(False) &
                            pp.infinite_cap_optimistic_recoverable_flag.fillna(False)).any())
        headroom = bool(pp.destination_headroom_limit_flag.fillna(False).any())
        info_hours = op.loc[op.strict_opportunity_flag, "relative_hour"]
        first_info = info_hours.min() if len(info_hours) else np.nan
        info_not_revealed = pd.isna(first_info) or first_info >= -4
        strict_reversal_kg = float(af.conservative_expost_nonaligned_but_information_aligned_kg.sum())
        expost_but_info = bool((af.strict_flow_row_reversal).any() and strict_reversal_kg > TOL)
        eligible = op[(op.relative_hour <= -1) & op.strict_opportunity_flag]
        strict_unused_opportunity = float(eligible.strict_information_consistent_physical_opportunity_kg.sum())
        upper_bound_room = bool(pp.optimistic_recoverable_flag.fillna(False).any())
        capacity_available_unused = bool(strict_unused_opportunity + TOL >= required and upper_bound_room and
                                         not no_supply and not late and not cap_limited and not headroom and not info_not_revealed)
        physical_flags = [no_supply, late, cap_limited, headroom]
        if sum(physical_flags) >= 2:
            classification = "MULTIPLE_LIMITS"
        elif no_supply:
            classification = "NO_MOVABLE_SURPLUS"
        elif late:
            classification = "SURPLUS_APPEARED_TOO_LATE"
        elif cap_limited:
            classification = "AGGREGATE_HTT_CAPACITY_LIMITED"
        elif headroom:
            classification = "DESTINATION_TANK_HEADROOM_LIMITED"
        elif info_not_revealed:
            classification = "INFORMATION_NOT_YET_REVEALED"
        elif expost_but_info:
            classification = "EX_POST_MISALIGNED_BUT_INFORMATION_CONSISTENT"
        elif capacity_available_unused:
            classification = "CAPACITY_AVAILABLE_BUT_NOT_USED"
        else:
            classification = "NOT_IDENTIFIABLE"
        rows.append({"path_id": path_id, "source_classification": "CANDIDATE_UNDER_DISPATCH_98",
                     "reclassification": classification, "terminal_gap_kg": required,
                     "no_movable_surplus_flag": no_supply, "surplus_appeared_too_late_flag": late,
                     "aggregate_capacity_limited_flag": cap_limited, "destination_headroom_limited_flag": headroom,
                     "information_not_yet_revealed_flag": info_not_revealed,
                     "expost_misaligned_but_information_consistent_flag": expost_but_info,
                     "capacity_available_but_not_used_strict_flag": capacity_available_unused,
                     "first_information_consistent_opportunity_relative_hour": first_info,
                     "strict_information_consistent_unused_opportunity_kg_sum": strict_unused_opportunity,
                     "conservative_expost_nonaligned_but_information_aligned_kg": strict_reversal_kg,
                     "formal_pairwise_road_block": "NO_SUCH_HARD_CONSTRAINT",
                     "causal_policy_failure_claim": "NO"})
    detail = pd.DataFrame(rows)
    order = ["NO_MOVABLE_SURPLUS", "SURPLUS_APPEARED_TOO_LATE", "AGGREGATE_HTT_CAPACITY_LIMITED",
             "DESTINATION_TANK_HEADROOM_LIMITED", "INFORMATION_NOT_YET_REVEALED",
             "EX_POST_MISALIGNED_BUT_INFORMATION_CONSISTENT", "CAPACITY_AVAILABLE_BUT_NOT_USED",
             "MULTIPLE_LIMITS", "NOT_IDENTIFIABLE"]
    summary = detail.reclassification.value_counts().reindex(order, fill_value=0).rename_axis("reclassification").reset_index(name="path_count")
    summary["fraction_of_98"] = summary.path_count / 98
    save_csv(detail, DIRS["underdispatch"] / "underdispatch_reclassification.csv")
    save_csv(summary, DIRS["underdispatch"] / "underdispatch_summary.csv")
    return detail, summary


def timing_audit(p: pd.DataFrame, system: pd.DataFrame):
    ids = group_ids(p)
    selected = ["positive_target_adequate", "pure_location", "mixed", "surplus_gt100", "surplus_gt200"]
    path_rows = []
    profile_rows = []
    for label in selected:
        for path_id in sorted(ids[label]):
            ph = system[system.path_id.eq(path_id)].sort_values("relative_hour")
            active = ph[ph.total_HTT_kg > TOL]
            record = {"group": label, "path_id": path_id, "real_hour_count": len(ph),
                      "first_HTT_hour_gt0": active.relative_hour.min() if len(active) else np.nan,
                      "first_meaningful_HTT_hour_ge1kg": ph.loc[ph.total_HTT_kg >= 1 - TOL, "relative_hour"].min(),
                      "first_meaningful_HTT_hour_ge5kg": ph.loc[ph.total_HTT_kg >= 5 - TOL, "relative_hour"].min(),
                      "peak_HTT_hour": ph.loc[ph.total_HTT_kg.idxmax(), "relative_hour"] if len(ph) else np.nan,
                      "peak_HTT_kg": ph.total_HTT_kg.max() if len(ph) else np.nan,
                      "last_HTT_hour": active.relative_hour.max() if len(active) else np.nan,
                      "final16h_HTT_kg": ph.loc[ph.relative_hour >= -16, "total_HTT_kg"].sum(),
                      "final8h_HTT_kg": ph.loc[ph.relative_hour >= -8, "total_HTT_kg"].sum(),
                      "final4h_HTT_kg": ph.loc[ph.relative_hour >= -4, "total_HTT_kg"].sum()}
            for checkpoint in [-24, -16, -8, -4, 0]:
                record[f"cumulative_HTT_by_{checkpoint}h_kg"] = ph.loc[ph.relative_hour < checkpoint, "total_HTT_kg"].sum()
                record[f"checkpoint_{checkpoint}h_available"] = checkpoint == 0 or bool((ph.relative_hour == checkpoint).any())
            path_rows.append(record)
        group_hour = system[system.path_id.isin(ids[label]) & system.relative_hour.between(-24, -1)]
        for rel, cell in group_hour.groupby("relative_hour"):
            profile_rows.append({"group": label, "relative_hour": rel, "actual_n": cell.path_id.nunique(),
                                 "mean_HTT_kg": cell.total_HTT_kg.mean(), "median_HTT_kg": cell.total_HTT_kg.median(),
                                 "q95_HTT_kg": cell.total_HTT_kg.quantile(.95),
                                 "mean_utilization": cell.fleet_utilization.mean()})
    detail = pd.DataFrame(path_rows)
    profile = pd.DataFrame(profile_rows)
    numeric = [c for c in detail.columns if c not in {"group", "path_id"} and detail[c].dtype != bool]
    summary = detail.groupby("group", as_index=False).agg(path_count=("path_id", "nunique"),
                                                           **{f"mean_{c}": (c, "mean") for c in numeric})
    save_csv(detail, DIRS["summary"] / "htt_timing_by_path.csv")
    save_csv(summary, DIRS["summary"] / "htt_timing_by_group.csv")
    save_csv(profile, DIRS["summary"] / "htt_timing_last24h_profile.csv")
    return detail, summary, profile


def od_audit(p: pd.DataFrame, flow: pd.DataFrame, aligned: pd.DataFrame, proxy_opportunities: pd.DataFrame):
    ids = group_ids(p)
    group_names = ["positive_target_adequate", "pure_location", "mixed", "difficult_5pct"]
    rows = []
    all_total = flow.flow_kg.sum()
    for origin in SITE_IDS:
        for destination in SITE_IDS:
            if origin == destination:
                continue
            f = flow[(flow.origin_site == origin) & (flow.destination_site == destination)]
            row = {"origin_site": origin, "destination_site": destination,
                   "flow_occurrence": len(f), "active_path_hour_count": f[["path_id", "global_hour"]].drop_duplicates().shape[0],
                   "active_path_count": f.path_id.nunique(), "total_kg": f.flow_kg.sum(),
                   "mean_when_active_kg": f.flow_kg.mean(), "q95_when_active_kg": f.flow_kg.quantile(.95),
                   "share_of_all_HTT": f.flow_kg.sum() / all_total if all_total > TOL else np.nan}
            for label in group_names:
                gf = flow[flow.path_id.isin(ids[label])]
                denom = gf.flow_kg.sum()
                value = gf[(gf.origin_site == origin) & (gf.destination_site == destination)].flow_kg.sum()
                row[f"share_in_{label}"] = value / denom if denom > TOL else np.nan
                row[f"kg_in_{label}"] = value
            rows.append(row)
    summary = pd.DataFrame(rows)
    save_csv(summary, DIRS["od"] / "htt_od_flow_summary.csv")
    outcome_rows = []
    shortfall = p[p.path_group.isin(["pure_location", "mixed"])]
    for origin in SITE_IDS:
        for destination in SITE_IDS:
            if origin == destination:
                continue
            eligible = shortfall[(shortfall[f"surplus_site{origin}"] > TOL) & (shortfall[f"gap_site{destination}"] > TOL)]
            actual = aligned[(aligned.path_id.isin(eligible.path_id)) &
                             (aligned.origin_site == origin) & (aligned.destination_site == destination)]
            outcome_rows.append({"alignment_view": "EX_POST_FINAL_TARGET", "origin_site": origin,
                                 "destination_site": destination, "path_count": len(eligible),
                                 "potential_match_kg": np.minimum(eligible[f"surplus_site{origin}"], eligible[f"gap_site{destination}"]).sum(),
                                 "actual_same_OD_HTT_kg": actual.flow_kg.sum(),
                                 "aligned_HTT_kg": actual.ex_post_aligned_kg.sum()})
            info = aligned[(aligned.origin_site == origin) & (aligned.destination_site == destination) &
                           (aligned.information_proxy_origin_surplus_kg > TOL) &
                           (aligned.information_proxy_destination_deficit_kg > TOL)]
            outcome_rows.append({"alignment_view": "CONTEMPORANEOUS_INFORMATION_PROXY", "origin_site": origin,
                                 "destination_site": destination, "path_count": info.path_id.nunique(),
                                 "path_hour_count": info[["path_id", "global_hour"]].drop_duplicates().shape[0],
                                 "actual_same_OD_HTT_kg": info.flow_kg.sum(),
                                 "aligned_HTT_kg": info.information_proxy_aligned_kg.sum()})
    outcome = pd.DataFrame(outcome_rows)
    save_csv(outcome, DIRS["od"] / "surplus_to_deficit_od_summary.csv")
    return summary, outcome


def flexibility_classification(p: pd.DataFrame, physical: pd.DataFrame, old_recover: pd.DataFrame):
    failed = p[p.positive_target & (p.terminal_site_gap > TOL)]
    old8 = old_recover[old_recover.hours_before_stage7.eq(8)].set_index("path_id")
    rows = []
    for _, row in failed.iterrows():
        production_signal = (row.path_group in {"pure_quantity", "mixed"} and row.path_id in old8.index and
                             old8.at[row.path_id, "TARGET_STILL_PHYSICALLY_REACHABLE"] == "NO")
        ph = physical[(physical.path_id == row.path_id) & physical.valid.fillna(False)]
        redistribution_signal = (row.path_group in {"pure_location", "mixed"} and len(ph) > 0 and
                                 bool(((ph.total_surplus_kg > TOL) &
                                       (ph.infinite_cap_optimistic_redistributable_kg > TOL)).any()))
        if production_signal and redistribution_signal:
            classification = "both"
        elif production_signal:
            classification = "production-dominated"
        elif redistribution_signal:
            classification = "redistribution-dominated"
        else:
            classification = "neither / not identifiable"
        rows.append({"path_id": int(row.path_id), "terminal_gap_class": row.terminal_gap_class,
                     "terminal_gap_kg": row.terminal_site_gap,
                     "production_unreachable_at_minus8h_signal": production_signal,
                     "spatial_redistribution_room_signal": redistribution_signal,
                     "flexibility_bottleneck_classification": classification,
                     "Pmax_role": "TEMPORAL_PRODUCTION_FLEXIBILITY",
                     "HTT_role": "SPATIAL_REDISTRIBUTION_FLEXIBILITY",
                     "claim_scope": "MECHANISM_SIGNAL_NOT_CAUSAL_POLICY_COUNTERFACTUAL"})
    detail = pd.DataFrame(rows)
    summary = detail.flexibility_bottleneck_classification.value_counts().rename_axis("classification").reset_index(name="path_count")
    summary["fraction_of_473"] = summary.path_count / 473
    save_csv(detail, DIRS["flex"] / "flexibility_bottleneck_classification.csv")
    save_csv(summary, DIRS["flex"] / "flexibility_bottleneck_summary.csv")
    return detail, summary


def economics_audit(training: pd.DataFrame, flow: pd.DataFrame, opportunities: pd.DataFrame):
    c0 = float(training.c0_yuan_per_kg.iloc[0])
    inferred_cd = (flow.unit_cost_yuan_per_kg - c0) / (flow.distance_km * (1 + 2 * flow.beta))
    active_keys = flow[["path_id", "global_hour"]].drop_duplicates().assign(HTT_active=True)
    econ = opportunities.merge(active_keys, on=["path_id", "global_hour"], how="left")
    econ["HTT_active"] = econ.HTT_active.fillna(False)
    rows = []
    for active, group in econ.groupby("HTT_active"):
        rows.append({"HTT_hour_status": "ACTIVE" if active else "INACTIVE", "path_hour_count": len(group),
                     "mean_proxy_surplus_kg": group.proxy_surplus_kg.mean(),
                     "mean_proxy_deficit_kg": group.proxy_deficit_kg.mean(),
                     "mean_information_consistent_physical_opportunity_kg": group.strict_information_consistent_physical_opportunity_kg.mean(),
                     "mean_fleet_slack_kg": group.fleet_slack_kg.mean(),
                     "marginal_continuation_value_proxy": "NOT_AVAILABLE",
                     "marginal_economic_causality": "HTT_MARGINAL_ECONOMIC_CAUSALITY_NOT_IDENTIFIABLE"})
    summary = pd.DataFrame(rows)
    save_csv(summary, DIRS["economics"] / "htt_cost_signal_summary.csv")
    text = f"""# HTT cost只读审计

- `c0 = {c0:.6f} yuan/kg`，来自Stage89Q训练摘要和正式launcher checkpoint metadata。
- `c_d = {inferred_cd.median():.6f} yuan/(kg km)`，由保存的OD距离、beta与逐kg成本机械反算；最大绝对偏差 `{(inferred_cd - .2).abs().max():.3e}`。
- beta成本倍率为 `1 + 2*beta`；容量倍率为 `1-beta`。
- 成本是纯逐kg变量成本：`c0 + 0.2*distance*(1+2*beta)`；没有fixed dispatch fee。
- 保存结果没有逐小时cut边际值或完整决策KKT归因，因此 `HTT_MARGINAL_ECONOMIC_CAUSALITY_NOT_IDENTIFIABLE`。
- 不能仅因HTT有正成本就断言“成本太高导致未运输”。
"""
    (DIRS["economics"] / "htt_cost_formal_audit.md").write_text(text, encoding="utf-8")
    return summary, inferred_cd


def write_model_audit(paths: dict[str, Path], training: pd.DataFrame) -> None:
    text = f"""# 当前正式FA-MSP的HTT约束审计

## 结论

当前Stage89Q使用 `hourly-h2-hourly-htt-v1` 连续LP。每个普通阶段有8个独立小时OD流量 `f(i,j,h)`。每小时先由期初库存、当小时制氢和普通供氢形成 `I_pre`，再结算HTT形成 `I_end`；仅第8小时 `I_end` 跨阶段。

`PRE_DISASTER_HTT_PAIRWISE_ROAD_HARD_CONSTRAINT = NO`

Stage89K灾后 `A_road` 不进入灾前hourly HTT OD可达性约束。当前site-to-site道路距离只进入每kg运输成本。

## 机械定位

| 项目 | 正式语义 | 源码/函数 | 变量或参数 |
|---|---|---|---|
| 变量 | 4x4x8非负连续OD流；`f(i,i,h)=0` | `hourly_grid_h2/build_integrated_hourly_stage_model_hourly_htt_v1_h2.m`, `build_integrated_hourly_stage_model_hourly_htt_v1_h2` | `idx.f_hourly`, `lb`, `ub` |
| 目标系数 | `c0 + c_d(i,j)*(1+2*beta)`，逐kg变量成本 | builder及`update_integrated_hourly_stage_model_hourly_htt_v1_h2.m` | `model.c`, `base_c`, `beta_transport_multiplier=2` |
| 当前c0 | `{float(training.c0_yuan_per_kg.iloc[0]):.6f} yuan/kg` | Stage89Q `training_summary.csv` / launcher metadata | `htt_base_service_cost_yuan_per_kg` |
| 当前c_d | `0.2*distance_km yuan/kg` | `load_data_h2_near.m`与Stage89Q launcher identity | `cost_transport_base` |
| 库存先后 | `I_pre=I_begin+production-served`; `I_end=I_pre+in-out` | builder `preHttRows`, `endingRows` | `h2_inventory_pre_htt`, `h2_inventory_hourly` |
| 起点出流 | `sum_j f(i,j,h) <= I_pre(i,h)` | builder `httOutflowRows` | `htt_outflow_availability` |
| 系统总运力 | `sum_ij f(i,j,h) <= (1-beta)*160` kg/h | builder `httRows`; updater `hourlyCapacity` | `htt_capacity_base=160` |
| beta容量 | 启用时乘 `1-beta` | updater | `use_beta_capacity=true` |
| beta成本 | 启用时距离成本乘 `1+2*beta` | updater | `use_beta_cost=true` |
| 储罐 | `I_pre`和`I_end`逐小时均不超过 `[300,200,100,200]` kg | builder upper bounds | `x_cap` |
| 同小时普通需求 | incoming在需求结算之后到达，不能服务当小时已结算需求 | builder equality order | `preHttRows` before `endingRows` |
| 同小时再次转运 | 不允许；outflow只受本小时 `I_pre` 支撑，incoming只进入 `I_end` | builder origin row/end balance | `htt_outflow_availability` |
| 运输时延 | 语义为1小时末到达，无大于1小时路线时延 | builder model metadata | `htt_trip_time_assumption_h=1` |

## 真实存在

- 每小时系统aggregate capacity；
- 每站每小时origin inventory availability；
- 每小时起点/终点储罐上限；
- beta同时影响系统容量和距离变量成本；
- 完整有向OD连续流，禁止自运。

## 不存在

- pairwise OD hard capacity；
- pairwise road accessibility hard constraint；
- truck integer或dispatch binary；
- minimum shipment；
- fixed dispatch cost；
- site-specific fleet；
- route-specific travel time或大于1小时行程；
- 同小时incoming再转运或服务已结算普通需求。

输入物理来源仍记录为 `N_HTT=2`, `Q_HTT=80 kg`，但LP只使用乘积形成的aggregate `160 kg/h`，没有显式车辆变量。
"""
    (DIRS["model"] / "htt_formal_constraint_audit.md").write_text(text, encoding="utf-8")


def make_figures(util: pd.DataFrame, util_rel: pd.DataFrame, timing_profile: pd.DataFrame,
                 upper: pd.DataFrame, sens: pd.DataFrame, under: pd.DataFrame,
                 od: pd.DataFrame, od_outcome: pd.DataFrame, align_summary: pd.DataFrame,
                 physical: pd.DataFrame, flex_summary: pd.DataFrame) -> list[Path]:
    figures = []

    def finish(fig, name):
        path = FIG / name
        fig.savefig(path, bbox_inches="tight", facecolor="white")
        plt.close(fig)
        figures.append(path)

    all_u = util.iloc[0]
    fig, ax = plt.subplots(figsize=(9, 5.2))
    thresholds = ["均值", "中位数", "q90", "q95", "q99"]
    values = [all_u.mean_utilization, all_u.median_utilization, all_u.q90, all_u.q95, all_u.q99]
    ax.bar(thresholds, np.array(values) * 100, color=["#287271", "#5b8e7d", "#f4a261", "#e76f51", "#9b2226"])
    ax.set_ylabel("HTT总运力利用率（%）"); ax.set_title("全部真实普通决策小时的HTT总运力利用率")
    ax.grid(axis="y", alpha=.25)
    finish(fig, "01_HTT总运力利用率分布.png")

    fig, ax = plt.subplots(figsize=(10, 5.5))
    for label, color in [("positive_target_adequate", "#287271"), ("pure_location", "#e76f51"), ("mixed", "#6a4c93")]:
        g = util_rel[(util_rel.group == label) & util_rel.relative_hour.between(-24, -1)].sort_values("relative_hour")
        ax.plot(g.relative_hour, 100 * g.mean_utilization, marker="o", label=label, color=color)
    ax.set_xlabel("相对Stage7小时"); ax.set_ylabel("平均利用率（%）"); ax.set_title("Stage7前24小时HTT总运力利用率")
    ax.legend(); ax.grid(alpha=.25)
    finish(fig, "02_Stage7前24小时HTT利用率.png")

    fig, ax = plt.subplots(figsize=(10, 5.5))
    for label, color in [("positive_target_adequate", "#287271"), ("pure_location", "#e76f51"), ("mixed", "#6a4c93")]:
        g = timing_profile[timing_profile.group.eq(label)].sort_values("relative_hour")
        ax.plot(g.relative_hour, g.mean_HTT_kg, marker="o", label=label, color=color)
    ax.set_xlabel("相对Stage7小时"); ax.set_ylabel("平均HTT（kg/h）"); ax.set_title("达标、纯位置不足与混合不足的HTT时序")
    ax.legend(); ax.grid(alpha=.25)
    finish(fig, "03_三类路径HTT时序.png")

    fig, axes = plt.subplots(1, 2, figsize=(11, 5), sharey=True)
    for ax, ptype in zip(axes, ["pure_location", "mixed"]):
        g = upper[upper.path_type.eq(ptype)].sort_values("relative_hour")
        x = np.arange(len(g)); width = .36
        ax.bar(x - width/2, g.current_cap_potentially_recoverable_count, width, label="当前cap", color="#287271")
        ax.bar(x + width/2, g.infinite_cap_potentially_recoverable_count, width, label="无限cap", color="#e9c46a")
        ax.set_xticks(x); ax.set_xticklabels([f"{v}h" for v in g.relative_hour]); ax.set_title(ptype); ax.grid(axis="y", alpha=.25)
    axes[0].set_ylabel("上界未排除的路径数"); axes[1].legend(); fig.suptitle("当前与无限HTT总运力的物理上界对照")
    finish(fig, "04_当前与无限HTT可恢复上界.png")

    fig, axes = plt.subplots(1, 2, figsize=(11, 5), sharey=True)
    for ax, ptype in zip(axes, ["pure_location", "mixed"]):
        for rel, color in zip(CUTS, ["#287271", "#f4a261", "#9b2226"]):
            g = sens[(sens.path_type == ptype) & (sens.relative_hour == rel)]
            g = g.set_index("HTT_CAP_MULTIPLIER").reindex(["1.00", "1.25", "1.50", "2.00", "INF"])
            ax.plot(range(5), g.unrecoverable_count, marker="o", label=f"{rel}h", color=color)
        ax.set_xticks(range(5)); ax.set_xticklabels(["1.00", "1.25", "1.50", "2.00", "INF"]); ax.set_title(ptype); ax.grid(alpha=.25)
    axes[0].set_ylabel("上界仍不可恢复路径数"); axes[1].legend(); fig.suptitle("HTT capacity multiplier上界敏感性")
    finish(fig, "05_HTT容量倍数敏感性.png")

    u = under[under.path_count > 0]
    fig, ax = plt.subplots(figsize=(10, 5.6))
    ax.barh(u.reclassification, u.path_count, color="#457b9d")
    ax.set_xlabel("路径数"); ax.set_title("98条candidate under-dispatch重新分类"); ax.grid(axis="x", alpha=.25)
    finish(fig, "06_underdispatch重分类.png")

    labels = [f"{int(r.origin_site)}→{int(r.destination_site)}" for r in od.itertuples()]
    fig, ax = plt.subplots(figsize=(10, 5.2))
    ax.bar(labels, od.total_kg, color="#2a9d8f"); ax.set_ylabel("累计HTT（kg）"); ax.set_title("12个有向OD累计流量")
    ax.tick_params(axis="x", rotation=45); ax.grid(axis="y", alpha=.25)
    finish(fig, "07_有向OD总流量.png")

    matrix = np.zeros((4, 4))
    ex = od_outcome[od_outcome.alignment_view.eq("EX_POST_FINAL_TARGET")]
    for r in ex.itertuples(): matrix[int(r.origin_site)-1, int(r.destination_site)-1] = r.path_count
    fig, ax = plt.subplots(figsize=(7, 6))
    im = ax.imshow(matrix, cmap="YlOrRd"); ax.set_xticks(range(4)); ax.set_xticklabels([f"缺口站{i}" for i in SITE_IDS]); ax.set_yticks(range(4)); ax.set_yticklabels([f"盈余站{i}" for i in SITE_IDS])
    for i in range(4):
        for j in range(4): ax.text(j, i, f"{matrix[i,j]:.0f}", ha="center", va="center")
    ax.set_title("最终盈余站→最终缺口站出现次数"); fig.colorbar(im, ax=ax, label="路径数")
    finish(fig, "08_盈余缺口OD热图.png")

    a = align_summary[align_summary.group.isin(["all_flows", "pure_location", "mixed"])]
    x = np.arange(len(a)); width = .36
    fig, ax = plt.subplots(figsize=(9, 5.2))
    ax.bar(x-width/2, 100*a.ex_post_alignment_fraction, width, label="最终目标事后口径", color="#e76f51")
    ax.bar(x+width/2, 100*a.information_proxy_alignment_fraction, width, label="当时信息代理", color="#287271")
    ax.set_xticks(x); ax.set_xticklabels(a.group); ax.set_ylabel("aligned HTT占比（%）"); ax.set_title("事后目标与当时信息代理的HTT方向一致性")
    ax.legend(); ax.grid(axis="y", alpha=.25)
    finish(fig, "09_事后与信息一致性对照.png")

    pure = physical[(physical.path_type == "pure_location") & physical.valid.fillna(False)]
    flag_names = [("origin_inventory_limit_flag", "起点库存"), ("aggregate_capacity_limit_flag", "总运力"),
                  ("destination_headroom_limit_flag", "终点罐空间"), ("timing_limit_flag", "时点")]
    fig, ax = plt.subplots(figsize=(9, 5.2))
    x = np.arange(3); width = .18
    for idx, (column, label) in enumerate(flag_names):
        vals = [int(pure.loc[pure.relative_hour.eq(rel), column].sum()) for rel in CUTS]
        ax.bar(x + (idx-1.5)*width, vals, width, label=label)
    ax.set_xticks(x); ax.set_xticklabels([f"{r}h" for r in CUTS]); ax.set_ylabel("触发路径数"); ax.set_title("pure-location物理限制分解")
    if not any(int(pure[column].sum()) for column, _ in flag_names):
        ax.set_ylim(0, 1)
        ax.text(.5, .5, "三个时点均未触发严格物理限制 flag", transform=ax.transAxes,
                ha="center", va="center", color="#495057")
    ax.legend(); ax.grid(axis="y", alpha=.25)
    finish(fig, "10_purelocation物理限制分解.png")

    fig, ax = plt.subplots(figsize=(9, 5.2))
    ax.barh(flex_summary.classification, flex_summary.path_count, color=["#457b9d", "#e76f51", "#6a4c93", "#adb5bd"][:len(flex_summary)])
    ax.set_xlabel("路径数"); ax.set_title("时间制氢能力与空间重配能力分类"); ax.grid(axis="x", alpha=.25)
    finish(fig, "11_生产与空间灵活性分类.png")

    fig, axes = plt.subplots(1, 3, figsize=(14, 4.8))
    axes[0].bar([">=80%", ">=90%", ">=95%", ">=99%"],
                [all_u["hours_ge_0.8"], all_u["hours_ge_0.9"],
                 all_u["hours_ge_0.95"], all_u["hours_ge_0.99"]], color="#287271")
    axes[0].set_title("总运力高利用小时"); axes[0].tick_params(axis="x", rotation=25)
    inf_gain = upper.groupby("relative_hour").incremental_potentially_recovered_by_infinite_cap.sum()
    axes[1].bar([f"{i}h" for i in inf_gain.index], inf_gain.values, color="#e9c46a"); axes[1].set_title("无限cap新增上界可恢复")
    if not inf_gain.any():
        axes[1].set_ylim(0, 1)
        axes[1].text(.5, .5, "无新增路径", transform=axes[1].transAxes,
                     ha="center", va="center", color="#495057")
    short_under_labels = {
        "NOT_IDENTIFIABLE": "不可识别",
        "CAPACITY_AVAILABLE_BUT_NOT_USED": "有容量但未用",
        "EX_POST_MISALIGNED_BUT_INFORMATION_CONSISTENT": "事后错向/当时一致",
        "INFORMATION_NOT_YET_REVEALED": "信息未揭示",
    }
    visible_under = under[under.path_count > 0]
    under_positions = np.arange(len(visible_under))
    axes[2].barh(under_positions, visible_under.path_count, color="#457b9d")
    axes[2].set_yticks(under_positions); axes[2].set_yticklabels([]); axes[2].tick_params(axis="y", length=0)
    for position, row in zip(under_positions, visible_under.itertuples()):
        axes[2].text(.6, position, short_under_labels[row.reclassification], va="center", ha="left",
                     color="#212529", bbox={"facecolor": "white", "alpha": .78, "edgecolor": "none", "pad": 1})
    axes[2].set_title("候选under-dispatch")
    fig.suptitle("HTT机制审计总结：容量、时点、信息与空间价值信号", fontsize=14)
    finish(fig, "12_HTT机制总结.png")

    thumbnails = []
    for path in figures:
        with Image.open(path) as image:
            thumb = image.convert("RGB"); thumb.thumbnail((520, 320)); thumbnails.append((path.name, thumb.copy()))
    row_height = 370
    sheet = Image.new("RGB", (1100, 6 * row_height), "white")
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 18) if Path("C:/Windows/Fonts/msyh.ttc").is_file() else ImageFont.load_default()
    for idx, (name, thumb) in enumerate(thumbnails):
        col, row = idx % 2, idx // 2; x, y = 20 + col * 540, 15 + row * row_height
        sheet.paste(thumb, (x, y + 28)); draw.text((x, y), name, fill="black", font=font)
    contact = FIG / "contact_sheet.png"; sheet.save(contact); figures.append(contact)
    return figures


def judgments(util: pd.DataFrame, upper: pd.DataFrame, physical: pd.DataFrame,
              under: pd.DataFrame, align: pd.DataFrame) -> dict[str, str]:
    all_u = util[util.group.eq("all_paths")].iloc[0]
    gains = upper.incremental_potentially_recovered_by_infinite_cap.sum()
    cap_limited = int(physical.aggregate_capacity_limit_flag.fillna(False).sum())
    timing_limited = int(physical.timing_limit_flag.fillna(False).sum())
    info_count = int(under.loc[under.reclassification.eq("INFORMATION_NOT_YET_REVEALED"), "path_count"].sum())
    proxy_gain = align.loc[align.group.eq("pure_location"), "information_proxy_alignment_fraction"].iloc[0] - align.loc[align.group.eq("pure_location"), "ex_post_alignment_fraction"].iloc[0]
    aggregate = "NO" if all_u.q99 < .8 and gains == 0 and cap_limited == 0 else ("MIXED" if gains < 20 else "YES")
    timing = "YES" if timing_limited > 0 else "NO"
    information = "YES" if info_count >= 20 else ("MIXED" if info_count > 0 else "NO")
    spatial = "STRONG" if proxy_gain > .10 else ("MODERATE" if proxy_gain > .03 else "WEAK")
    recommend = "YES" if aggregate == "YES" else ("NEEDS_MORE_DIAGNOSTIC" if aggregate == "MIXED" else "NO")
    return {"HTT_AGGREGATE_CAPACITY_BOTTLENECK": aggregate, "HTT_TIMING_BOTTLENECK": timing,
            "HTT_INFORMATION_LIMIT_SIGNAL": information, "HTT_SPATIAL_VALUE_SIGNAL": spatial,
            "RECOMMEND_HTT_CAPACITY_SENSITIVITY": recommend}


def write_readme(p: pd.DataFrame, util: pd.DataFrame, upper: pd.DataFrame, sens: pd.DataFrame,
                 under: pd.DataFrame, align: pd.DataFrame, physical: pd.DataFrame,
                 flex: pd.DataFrame, status: dict[str, str]) -> None:
    all_u = util[util.group.eq("all_paths")].iloc[0]
    pure_align = align[align.group.eq("pure_location")].iloc[0]
    counts = under.set_index("reclassification").path_count.to_dict()
    sens_pure = sens[sens.path_type.eq("pure_location")]

    def cap_counts(token):
        g = sens_pure[sens_pure.HTT_CAP_MULTIPLIER.eq(token)]
        return "/".join(str(int(g.loc[g.relative_hour.eq(rel), "recoverable_count"].iloc[0])) for rel in CUTS)

    inf_gain = upper.groupby("relative_hour").incremental_potentially_recovered_by_infinite_cap.sum().to_dict()
    flex_counts = flex.set_index("classification").path_count.to_dict()
    text = f"""# Stage-89Q penalty=1000：HTT空间灵活性与wait-and-see专项审计

## 先说结论

当前HTT有真实的系统总运力约束，但保存的10000路径小时证据并不支持把203条pure-location failure主要归因于160*(1-beta) kg/h。全部真实普通决策小时利用率均值/中位数/q99为 **{all_u.mean_utilization:.2%}/{all_u.median_utilization:.2%}/{all_u.q99:.2%}**，精确绑定比例 **{all_u.exact_binding_fraction:.4%}**。无限aggregate cap在-16/-8/-4h相对当前cap新增的“上界未排除”路径数（pure-location+mixed合计）为 **{inf_gain.get(-16,0):.0f}/{inf_gain.get(-8,0):.0f}/{inf_gain.get(-4,0):.0f}**。这只是固定已实现制氢和普通服务轨迹的乐观容量包络，不是新policy或反事实最优解。

## 1. 当前HTT到底受哪些正式约束？

每小时有连续4x4有向OD流，`f_ii=0`；系统总流量不超过`(1-beta)*160`；每站outflow不超过当小时生产和普通服务结算后的`I_pre`；`I_pre`和`I_end`均受罐容限制。beta同时降低容量并提高距离变量成本。详见`01_model_audit/htt_formal_constraint_audit.md`。

## 2. 160*(1-beta) kg/h总运力是否经常绑定？

不经常。>=80/90/95/99%利用率小时数为 **{int(all_u['hours_ge_0.8'])}/{int(all_u['hours_ge_0.9'])}/{int(all_u['hours_ge_0.95'])}/{int(all_u['hours_ge_0.99'])}**，相对于{int(all_u.real_hour_count)}个真实小时。

## 3. 203条pure-location failure主要是不是总HTT运力不足？

不是主要证据。`HTT有总运力约束`不等于`总运力约束是当前pure-location failure的主要原因`。路径-时点级严格aggregate-capacity flag共 **{int(physical.aggregate_capacity_limit_flag.fillna(False).sum())}** 次。

## 4. 98条candidate under-dispatch重新分类后分别是什么？

NO_MOVABLE_SURPLUS={counts.get('NO_MOVABLE_SURPLUS',0)}；SURPLUS_APPEARED_TOO_LATE={counts.get('SURPLUS_APPEARED_TOO_LATE',0)}；AGGREGATE_HTT_CAPACITY_LIMITED={counts.get('AGGREGATE_HTT_CAPACITY_LIMITED',0)}；DESTINATION_TANK_HEADROOM_LIMITED={counts.get('DESTINATION_TANK_HEADROOM_LIMITED',0)}；INFORMATION_NOT_YET_REVEALED={counts.get('INFORMATION_NOT_YET_REVEALED',0)}；EX_POST_MISALIGNED_BUT_INFORMATION_CONSISTENT={counts.get('EX_POST_MISALIGNED_BUT_INFORMATION_CONSISTENT',0)}；CAPACITY_AVAILABLE_BUT_NOT_USED={counts.get('CAPACITY_AVAILABLE_BUT_NOT_USED',0)}；MULTIPLE_LIMITS={counts.get('MULTIPLE_LIMITS',0)}；NOT_IDENTIFIABLE={counts.get('NOT_IDENTIFIABLE',0)}。

## 5. 有多少路径根本没有可搬库存？

在98条严格重分类中为 **{counts.get('NO_MOVABLE_SURPLUS',0)}**；完整pure-location三时点物理表另行保留origin inventory flag，不能把不同分母混报。

## 6. 有多少是库存出现得太晚？

98条中严格分类为 **{counts.get('SURPLUS_APPEARED_TOO_LATE',0)}**。

## 7. 有多少是真正aggregate capacity limited？

98条中为 **{counts.get('AGGREGATE_HTT_CAPACITY_LIMITED',0)}**；物理表的路径-时点flag总数为 **{int(physical.aggregate_capacity_limit_flag.fillna(False).sum())}**。

## 8. 有多少是destination tank headroom问题？

98条中为 **{counts.get('DESTINATION_TANK_HEADROOM_LIMITED',0)}**。最终缺口本身通常小于对应站最终headroom，因此不能把罐容存在误写成罐容正在阻断。

## 9. 有多少是当时信息尚未揭示？

98条中为 **{counts.get('INFORMATION_NOT_YET_REVEALED',0)}**。这里使用Markov转移与Stage89K 35x4表的无条件`E[T_i|当前state]`代理，不使用最终目标。

## 10. 29.50%为什么不能叫“HTT正确率”？

它按最终Stage7目标事后回看，而且只是逐OD流量截断口径；当时决策尚不知道最终目标，也不是二元对错分类。pure-location事后aligned比例复算为 **{pure_align.ex_post_alignment_fraction:.4%}**。

## 11. 有多少ex-post non-aligned HTT在当时信息代理下合理？

pure-location中严格“事后aligned=0但信息代理aligned>0”的路径数为 **{int(pure_align.strict_reversal_path_count)}**，保守可确认流量为 **{pure_align.conservative_expost_nonaligned_but_information_aligned_kg:.3f} kg**。代理不是continuation value、DRO cut或正式最优target。

## 12. cap提高到200/240/320 kg/h物理上多救多少？

pure-location在-16/-8/-4h的上界可恢复数分别为：160=`{cap_counts('1.00')}`，200=`{cap_counts('1.25')}`，240=`{cap_counts('1.50')}`，320=`{cap_counts('2.00')}`。分母和边际增量见`04_cap_sensitivity`。

## 13. infinite aggregate capacity又能多救多少？

相对当前cap，pure-location+mixed在-16/-8/-4h分别新增 **{inf_gain.get(-16,0):.0f}/{inf_gain.get(-8,0):.0f}/{inf_gain.get(-4,0):.0f}** 条上界可恢复路径。

## 14. 如果infinite cap改善很小，真正瓶颈是什么？

更可能是起点可搬库存、库存出现时点、最终位置尚未揭示，以及未能从保存数据严格恢复的continuation-value空间信号，而不是系统总运力一个参数。

## 15. HTT主要缺容量，还是缺时间/信息/空间价值信号？

当前证据更偏向时间、信息和空间价值信号的组合；aggregate容量不是主导信号。

## 16. Pmax与HTT分别限制哪种wait-and-see灵活性？

Pmax限制后期新增氢的时间生产灵活性；HTT限制已有氢的空间重配置灵活性。473条分类中production-dominated={flex_counts.get('production-dominated',0)}，redistribution-dominated={flex_counts.get('redistribution-dominated',0)}，both={flex_counts.get('both',0)}，neither/not identifiable={flex_counts.get('neither / not identifiable',0)}。

## 17. 当前有证据支持下一步正式扩大HTT capacity吗？

状态为 **{status['RECOMMEND_HTT_CAPACITY_SENSITIVITY']}**。只有当上界敏感性显示稳定且明显的新增路径，同时真实小时利用率也显示容量压力，才值得fresh retraining验证。

## 18. 如果有，建议测试什么candidate？

若后续证据转为YES，优先测试200 kg/h，再决定是否240 kg/h；不建议直接跳到320或无限容量。

## 19. 为什么不应为了结果漂亮直接扩大HTT？

因为扩大cap会改变正式策略、训练cuts和成本权衡；当前只读上界不能证明新参数会改善OOS，更不能排除库存、信息和价值近似才是主因。

## 20. 哪些结论需要fresh retraining验证？

容量变化后的真实非预见性policy、HTT时序、普通缺氢、TerminalLOH gap、成本、tail风险和wait-and-see行为都必须fresh training加同一路径OOS验证。本轮没有运行任何这些工作。

```text
HTT_AGGREGATE_CAPACITY_BOTTLENECK = {status['HTT_AGGREGATE_CAPACITY_BOTTLENECK']}
HTT_TIMING_BOTTLENECK = {status['HTT_TIMING_BOTTLENECK']}
HTT_INFORMATION_LIMIT_SIGNAL = {status['HTT_INFORMATION_LIMIT_SIGNAL']}
HTT_SPATIAL_VALUE_SIGNAL = {status['HTT_SPATIAL_VALUE_SIGNAL']}
RECOMMEND_HTT_CAPACITY_SENSITIVITY = {status['RECOMMEND_HTT_CAPACITY_SENSITIVITY']}
FULLY_CONVERGED = NO
PENALTY1500_STARTED = NO
NO_REOPTIMIZATION = YES
NO_RANDOM_DRAW = YES
```
"""
    (DIRS["summary"] / "README.md").write_text(text, encoding="utf-8")
    save_csv(pd.DataFrame([status]), DIRS["summary"] / "final_status.csv")


def main_qa(paths: dict[str, Path], before: dict[str, str], p: pd.DataFrame, hour: pd.DataFrame,
            system: pd.DataFrame, flow: pd.DataFrame, proxy: pd.DataFrame, physical: pd.DataFrame,
            alignment: pd.DataFrame, under: pd.DataFrame, figures: list[Path]) -> pd.DataFrame:
    rows = []
    def check(name, observed, expected, passed, detail=""):
        rows.append({"check": name, "observed": observed, "expected": expected, "pass": bool(passed), "detail": detail})
    bank_identity = pd.read_csv(paths["bank_identity"]).iloc[0]
    s7 = p[p.reached_stage7.eq(1)]
    positive = s7[s7.positive_target]
    failed = positive[positive.terminal_site_gap > TOL]
    check("path_bank_mat_sha", sha256(Path(bank_identity.bank_path)), EXPECTED_BANK_MAT,
          sha256(Path(bank_identity.bank_path)) == EXPECTED_BANK_MAT)
    check("ordered_bank_manifest_sha", sha256(BANK), EXPECTED_BANK_CSV, sha256(BANK) == EXPECTED_BANK_CSV)
    check("adopted_stage89k_target_sha", sha256(TARGET), EXPECTED_TARGET, sha256(TARGET) == EXPECTED_TARGET)
    check("path_count", len(p), 10000, len(p) == 10000)
    check("positive_target_partition", f"{int(positive.adequate_positive.sum())}+{len(failed)}", "650+473=1123",
          int(positive.adequate_positive.sum()) == 650 and len(failed) == 473)
    counts = failed.path_group.value_counts().to_dict()
    check("shortfall_partition", counts, {"pure_quantity": 118, "pure_location": 203, "mixed": 152},
          counts.get("pure_quantity") == 118 and counts.get("pure_location") == 203 and counts.get("mixed") == 152)
    check("underdispatch_source_and_output", len(under), 98, len(under) == 98)
    pre_res = np.abs(hour.inventory_before_HTT_kg - (hour.begin_inventory_kg + hour.H2_production_kg - hour.ordinary_served_kg)).max()
    end_res = np.abs(hour.end_inventory_kg - (hour.inventory_before_HTT_kg + hour.HTT_in_kg - hour.HTT_out_kg)).max()
    check("inventory_pre_balance", pre_res, f"<={TOL}", pre_res <= TOL)
    check("inventory_end_balance", end_res, f"<={TOL}", end_res <= TOL)
    check("tank_capacity", float(hour.end_inventory_kg.max()), "site-specific caps", bool((hour.end_inventory_kg <= hour.site.map(TANK_CAP) + TOL).all()))
    cap_violation = (system.total_HTT_kg - system.fleet_capacity_kg).max()
    check("hourly_aggregate_HTT_capacity", cap_violation, f"<={TOL}", cap_violation <= TOL)
    outflow = hour.groupby(["path_id", "global_hour"]).HTT_out_kg.sum()
    syst = system.set_index(["path_id", "global_hour"]).total_HTT_kg
    check("HTT_flow_conservation", float((outflow - syst).abs().max()), f"<={TOL}", float((outflow - syst).abs().max()) <= TOL)
    check("no_zero_padding", int(system.groupby("path_id").global_hour.nunique().sum()), int(p.end_hour.sum()),
          int(system.groupby("path_id").global_hour.nunique().sum()) == int(p.end_hour.sum()))
    check("physical_rows", len(physical), 355 * 3, len(physical) == 355 * 3)
    check("physical_source_monotone", bool(physical.loc[physical.valid.fillna(False), "source_availability_is_monotone"].all()), True,
          bool(physical.loc[physical.valid.fillna(False), "source_availability_is_monotone"].all()))
    check("information_probability_closure", float((proxy.probability_sum - 1).abs().max()), "<=1e-12",
          float((proxy.probability_sum - 1).abs().max()) <= 1e-12)
    pure = alignment[alignment.path_group.eq("pure_location")]
    expost_fraction = pure.ex_post_aligned_kg.sum() / pure.flow_kg.sum()
    check("pure_location_expost_alignment", expost_fraction, 0.295032472656,
          abs(expost_fraction - 0.295032472656) <= 1e-12)
    check("information_and_expost_separate", True, True,
          {"ex_post_aligned_kg", "information_proxy_aligned_kg"}.issubset(alignment.columns))
    check("relative_time_n_reported", True, True, (DIRS["summary"] / "htt_aggregate_utilization_by_relative_hour.csv").is_file())
    forbidden = forbidden_capability_references(Path(__file__))
    check("no_optimizer_or_random", forbidden, [], not forbidden, "AST import/call scan")
    check("figure_count", len(figures), 13, len(figures) == 13)
    after = {name: sha256(RAW / name) for name in EXPECTED}
    check("raw_hashes_unchanged", after, before, after == before)
    check("raw_hashes_accepted", before, EXPECTED, before == EXPECTED)
    qa = pd.DataFrame(rows)
    save_csv(qa, DIRS["qa"] / "main_qa.csv")
    if not qa["pass"].all():
        raise RuntimeError("Main QA failed:\n" + qa.loc[~qa["pass"]].to_string(index=False))
    return qa


def write_visual_audit(figures: list[Path], passed: bool) -> None:
    rows = []
    for path in figures:
        with Image.open(path) as image:
            rgb = np.asarray(image.convert("RGB"))
            nonblank = float(np.std(rgb)) > 2
            rows.append({"figure": path.name, "width": image.width, "height": image.height,
                         "nonblank_pixel_check": nonblank,
                         "manual_legibility_check": "PASS" if passed else "PENDING_MANUAL",
                         "manual_overlap_check": "PASS" if passed else "PENDING_MANUAL",
                         "result": "PASS" if passed and nonblank else "PENDING_MANUAL",
                         "note": "contact sheet and originals manually inspected" if passed else "run --finalize-visual after inspection"})
    save_csv(pd.DataFrame(rows), DIRS["qa"] / "visual_audit.csv")


def manifest(paths: dict[str, Path]) -> None:
    rows = []
    for role, path in paths.items():
        rows.append({"role": "source", "source_role": role, "relative_path": str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path),
                     "size_bytes": path.stat().st_size, "sha256": sha256(path)})
    for path in sorted(OUT.rglob("*")):
        # The independent QA rewrites its own report after validating this manifest;
        # excluding that self-referential file keeps all recorded hashes stable.
        if path.is_file() and path.name not in {"lightweight_manifest.csv", "independent_qa.csv"}:
            rows.append({"role": "output", "source_role": "", "relative_path": str(path.relative_to(ROOT)),
                         "size_bytes": path.stat().st_size, "sha256": sha256(path)})
    for path in sorted(FIG.glob("*")):
        if path.is_file():
            rows.append({"role": "figure", "source_role": "", "relative_path": str(path.relative_to(ROOT)),
                         "size_bytes": path.stat().st_size, "sha256": sha256(path)})
    save_csv(pd.DataFrame(rows), DIRS["summary"] / "lightweight_manifest.csv")


def finalize_visual() -> None:
    figures = sorted(FIG.glob("*.png"))
    if len(figures) != 13:
        raise RuntimeError(f"Expected 12 figures plus contact sheet, found {len(figures)}")
    write_visual_audit(figures, True)
    manifest(raw_paths())
    print("STAGE89Q_HTT_VISUAL_AUDIT=PASS figures=13")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--finalize-visual", action="store_true")
    args = parser.parse_args()
    setup()
    if args.finalize_visual:
        finalize_visual()
        return
    paths = raw_paths()
    before = {name: sha256(RAW / name) for name in EXPECTED}
    if before != EXPECTED:
        raise RuntimeError(f"Accepted raw hash mismatch: {before}")
    p, stage, site, hour, system, flow, bank, target = load_data(paths)
    p = classify_paths(p)
    hour, system = add_relative_time(p, hour, system)
    proxy = information_proxy(paths, target)
    util, util_rel = utilization_audit(p, system)
    physical, comparison, upper, sens_detail, sens = physical_and_sensitivity(p, hour, system)
    aligned, align_summary = alignment_audit(p, hour, flow, proxy)
    opportunities = information_opportunities(p, hour, system, proxy)
    candidate = pd.read_csv(paths["old_candidate"])
    under_detail, under_summary = underdispatch_reclassification(p, physical, opportunities, aligned, candidate)
    timing_detail, timing_summary, timing_profile = timing_audit(p, system)
    od, od_outcome = od_audit(p, flow, aligned, opportunities)
    old_recover = pd.read_csv(paths["old_recover"])
    flex_detail, flex_summary = flexibility_classification(p, physical, old_recover)
    training = pd.read_csv(paths["training"])
    economics, inferred_cd = economics_audit(training, flow, opportunities)
    write_model_audit(paths, training)
    status = judgments(util, upper, physical, under_summary, align_summary)
    figures = make_figures(util, util_rel, timing_profile, upper, sens, under_summary, od, od_outcome,
                           align_summary, physical, flex_summary)
    write_readme(p, util, upper, sens, under_summary, align_summary, physical, flex_summary, status)
    qa = main_qa(paths, before, p, hour, system, flow, proxy, physical, aligned, under_detail, figures)
    write_visual_audit(figures, False)
    manifest(paths)
    print(f"STAGE89Q_HTT_FLEXIBILITY_ANALYSIS=PASS qa={len(qa)} figures={len(figures)} status={status}")


if __name__ == "__main__":
    main()
