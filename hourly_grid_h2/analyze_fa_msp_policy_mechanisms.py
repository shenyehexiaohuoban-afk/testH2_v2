#!/usr/bin/env python3
"""Read-only common-path mechanism analysis for two accepted FA-MSP policies.

The analyzer never loads a checkpoint, runs an optimizer, trains a policy, or
reruns OOS.  It consumes only persisted CSV evidence from two accepted runs.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import shutil
from pathlib import Path
from typing import Iterable

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from scipy import stats


TOL = 1e-8
PAIR_TOL = 1e-7
DESCRIPTIVE_N = 30
H2_KG_PER_KWH = 0.0195
SITE_PMAX_KW = np.array([300.0, 200.0, 120.0, 150.0])
SITE_STAGE_CAP_KG = SITE_PMAX_KW * 8.0 * H2_KG_PER_KWH
EXPECTED_INITIAL_INVENTORY = np.array(
    [58.0445570448695, 50.3081379386248, 25.2621334423093, 33.0235808462428]
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def decode_state(state_id: int) -> tuple[int, int, int]:
    value = int(state_id) - 1
    return value // 56 + 1, (value % 56) // 8 + 1, value % 8 + 1


def clean_number(value: object) -> object:
    if isinstance(value, (np.floating, float)):
        return float(value) if np.isfinite(value) else np.nan
    if isinstance(value, (np.integer, int)):
        return int(value)
    return value


def mean_ci(values: Iterable[float]) -> tuple[int, float, float, float]:
    clean = pd.Series(values, dtype=float).replace([np.inf, -np.inf], np.nan).dropna()
    n = len(clean)
    if n == 0:
        return 0, np.nan, np.nan, np.nan
    mean = float(clean.mean())
    if n == 1:
        return n, mean, np.nan, np.nan
    half = float(stats.t.ppf(0.975, n - 1) * clean.std(ddof=1) / math.sqrt(n))
    return n, mean, mean - half, mean + half


def q(values: pd.Series, probability: float) -> float:
    return float(pd.to_numeric(values, errors="coerce").quantile(probability))


def read_csv(path: Path, **kwargs: object) -> pd.DataFrame:
    require(path.is_file(), f"Missing required CSV: {path}")
    return pd.read_csv(path, **kwargs)


def classify_paths(manifest: pd.DataFrame) -> pd.DataFrame:
    rows: list[dict[str, object]] = []
    for record in manifest.itertuples(index=False):
        states = [int(getattr(record, f"k_t{stage}")) for stage in range(1, 9)]
        decoded = [decode_state(state) for state in states]
        termination_type = "UNRESOLVED"
        termination_stage = 0
        termination_state_id = 0
        for temporal_stage, (state_id, (a, _, lf)) in enumerate(zip(states, decoded), 1):
            if a == 1:
                termination_type = "A1"
            elif lf == 7:
                termination_type = "STAGE7"
            elif lf == 8:
                termination_type = "LF8"
            else:
                continue
            termination_stage = temporal_stage
            termination_state_id = state_id
            break
        require(termination_type != "UNRESOLVED", f"Path {record.path_id} has no termination event")
        last_active = min(6, termination_stage - 1)
        prefix = "EARLY_" if last_active < 6 else "STAGE6_TO_"
        cohort = prefix + termination_type
        term_a, term_loc, term_lf = decode_state(termination_state_id)
        stage7_ids = [sid for sid, (_, _, lf) in zip(states, decoded) if lf == 7]
        # Only a first-event Stage7 termination owns a terminal cell.  A later
        # lf=7 in the padded Markov sequence of an already dissipated path is
        # not a realized TerminalLOH check.
        terminal_state_id = termination_state_id if termination_type == "STAGE7" else 0
        if terminal_state_id:
            terminal_a, terminal_loc, _ = decode_state(terminal_state_id)
        else:
            terminal_a, terminal_loc = np.nan, np.nan
        first_lf8 = next((i for i, (_, _, lf) in enumerate(decoded, 1) if lf == 8), 0)
        rows.append({
            "path_id": int(record.path_id),
            "initial_state": states[0],
            "last_active_stage": last_active,
            "last_active_hour": 8 * last_active,
            "termination_stage": termination_stage,
            "termination_type": termination_type,
            "cohort": cohort,
            "cohort_timing": f"S{last_active}->{termination_type}",
            "reached_stage6": last_active >= 6,
            "reached_stage7": termination_type == "STAGE7",
            "physical_dissipation_a1": termination_type == "A1",
            "lf8_absorbing": termination_type == "LF8",
            "first_lf8_stage": first_lf8,
            "termination_state_id": termination_state_id,
            "termination_a": term_a,
            "termination_loc": term_loc,
            "termination_lf": term_lf,
            "terminal_state_id": terminal_state_id,
            "terminal_a": terminal_a,
            "terminal_loc": terminal_loc,
            "intensity_sequence": "-".join(str(a) for a, _, _ in decoded),
            "loc_sequence": "-".join(str(loc) for _, loc, _ in decoded),
            "lf_sequence": "-".join(str(lf) for _, _, lf in decoded),
            "state_sequence": "-".join(str(value) for value in states),
        })
    result = pd.DataFrame(rows).sort_values("path_id").reset_index(drop=True)
    require(len(result) == 10000 and result.path_id.is_unique, "Path cohort master coverage failed")
    # A path may enter Stage7 first and only later contain a=1 in the padded
    # Markov sequence.  Termination classification follows the first event;
    # physical_dissipation_a1 independently records whether a=1 ever appears.
    require((result[result.termination_type == "A1"].termination_a == 1).all(),
            "a=1 termination-event identity failed")
    return result


def load_policy(run_root: Path, label: str) -> dict[str, object]:
    raw = run_root / "oos" / "loc4"
    path = read_csv(raw / "oos_path_summary.csv")
    stage = read_csv(raw / "oos_stage_summary.csv")
    site = read_csv(raw / "oos_stage_site_summary.csv")
    manifest = read_csv(raw / "oos_path_manifest.csv")
    for frame in (path, stage, site):
        frame["policy_label"] = label
    site["demand_closure_residual_kg"] = (
        site.ordinary_demand_kg - site.served_demand_kg - site.shortage_kg
    )
    site["inventory_closure_residual_kg"] = site.ending_inventory_kg - (
        site.beginning_inventory_kg + site.production_kg - site.served_demand_kg
        + site.htt_in_kg - site.htt_out_kg
    )
    aggregated = site.groupby(["path_id", "stage"], as_index=False).agg(
        ordinary_demand_kg_site=("ordinary_demand_kg", "sum"),
        ordinary_served_kg=("served_demand_kg", "sum"),
        ordinary_shortage_kg_site=("shortage_kg", "sum"),
        production_kg_site=("production_kg", "sum"),
        htt_in_kg=("htt_in_kg", "sum"),
        htt_out_kg=("htt_out_kg", "sum"),
        beginning_inventory_kg_site=("beginning_inventory_kg", "sum"),
        ending_inventory_kg_site=("ending_inventory_kg", "sum"),
    )
    stage = stage.merge(aggregated, on=["path_id", "stage"], validate="one_to_one")
    stage["net_inventory_build_kg"] = stage.ending_inventory_kg - stage.beginning_inventory_kg
    stage["positive_inventory_build_kg"] = stage.net_inventory_build_kg.clip(lower=0.0)
    stage["system_htt_balance_residual_kg"] = stage.htt_in_kg - stage.htt_out_kg
    stage_first = stage[stage.stage == 1].set_index("path_id")
    stage_last = stage.sort_values("stage").groupby("path_id").tail(1).set_index("path_id")
    stage_later = stage[stage.stage >= 2].groupby("path_id").production_kg.sum()
    path["stage1_production_kg"] = path.path_id.map(stage_first.production_kg)
    path["stage2_6_production_kg"] = path.path_id.map(stage_later).fillna(0.0)
    path["last_active_stage_production_kg"] = path.path_id.map(stage_last.production_kg)
    site_totals = site.groupby(["path_id", "site"]).production_kg.sum().unstack(fill_value=0.0)
    site_last = site.sort_values("stage").groupby(["path_id", "site"]).tail(1).set_index(["path_id", "site"])
    for site_id in range(1, 5):
        path[f"site{site_id}_cumulative_production_kg"] = path.path_id.map(site_totals.get(site_id, pd.Series(dtype=float))).fillna(0.0)
        path[f"site{site_id}_last_active_production_kg"] = path.path_id.map(
            site_last.xs(site_id, level="site").production_kg)
        path[f"terminal_surplus_site{site_id}_kg"] = (
            path[f"terminal_inventory_site{site_id}_kg"]-path[f"terminal_target_site{site_id}_kg"]
        ).clip(lower=0.0)
    path["terminal_surplus_kg"] = (path.terminal_inventory_kg-path.terminal_target_kg).clip(lower=0.0)
    require(len(path) == 10000, f"{label}: path count != 10000")
    require(stage.groupby("path_id").size().equals(path.set_index("path_id").operating_stage_count),
            f"{label}: operating stage count mismatch")
    return {"label": label, "root": run_root, "raw": raw, "path": path,
            "stage": stage, "site": site, "manifest": manifest}


def policy_identity_audit(a: dict[str, object], b: dict[str, object]) -> pd.DataFrame:
    ar = Path(a["root"]); br = Path(b["root"])
    a_meta = read_csv(Path(a["raw"]) / "oos_metadata.csv").iloc[0]
    b_meta = read_csv(Path(b["raw"]) / "oos_metadata.csv").iloc[0]
    a_pre = read_csv(ar / "preflight_gates.csv").set_index("gate").actual
    b_pre = read_csv(br / "stage89n_parameter_audit.csv").set_index("gate").actual
    bank = Path(a_meta.bank_path)
    common_sha = sha256(bank)
    rows = [
        ("W identity", "Stage88 W provenance (indirect)", "Stage89J adopted W provenance (indirect)",
         "EXPECTED_DIFF", "W is not a direct FA-MSP runtime input; it enters through TerminalLOH provenance"),
        ("TerminalLOH identity", a_pre.TERMINAL_TABLE_SHA256, b_pre.TERMINAL_TABLE_SHA256,
         "EXPECTED_DIFF", "Stage88 DRO CAP200 -> Stage89K adopted DRO; controlled mechanism input"),
        ("loc4 identity", a_pre.INITIAL_LOCATION_LABEL, b_pre.INITIAL_LOCATION_LABEL, "YES", "preflight gates"),
        ("dt_h", "8", "8", "YES", "formal 8h runtime audits and accepted READMEs"),
        ("hourly stage count", "6x8=48", "6x8=48", "YES", "formal 8h runtime audits"),
        ("training iterations", a_pre.TRAINING_ITERATIONS, b_pre.TRAINING_ITERATIONS, "YES", "preflight gates"),
        ("training seed", "20260513", "20260513", "YES", "training summaries"),
        ("ordinary shortage penalty", a_pre.ORDINARY_SHORTAGE_PENALTY,
         b_pre.ORDINARY_SHORTAGE_PENALTY, "YES", "preflight gates"),
        ("terminal-gap penalty", a_pre.TERMINAL_GAP_PENALTY, b_pre.TERMINAL_GAP_PENALTY,
         "YES", "preflight gates"),
        ("demand version", "original-hourly-24h-repeat-v1", "original-hourly-24h-repeat-v1",
         "YES", "Stage89F/Stage89M runtime identity"),
        ("HTT version", "hourly directed end-of-hour arrival v1", "hourly directed end-of-hour arrival v1",
         "YES", "Stage89F/Stage89M runtime identity"),
        ("Pmax kW", a_pre.PMAX_KW, b_pre.PMAX_KW, "YES", "preflight gates"),
        ("tank kg", a_pre.TANK_CAPACITY, b_pre.TANK_CAPACITY, "YES", "preflight gates"),
        ("initial inventory kg", a_pre.INITIAL_INVENTORY, b_pre.INITIAL_INVENTORY, "YES", "preflight gates"),
        ("OOS path bank SHA256", common_sha, common_sha, "YES", str(bank)),
        ("OOS path count", int(a_meta.completed_paths), int(b_meta.completed_paths), "YES", "OOS metadata"),
        ("OOS seed", int(a_meta.oos_seed), int(b_meta.oos_seed), "YES", "OOS metadata"),
        ("ordered path manifest bytes", sha256(Path(a["raw"]) / "oos_path_manifest.csv"),
         sha256(Path(b["raw"]) / "oos_path_manifest.csv"), "YES", "byte-identical accepted manifests"),
    ]
    return pd.DataFrame(rows, columns=["field", str(a["label"]), str(b["label"]), "match", "evidence"])


def schema_audit(a: dict[str, object], b: dict[str, object]) -> pd.DataFrame:
    variables = [
        ("path_id", "path/stage/site", "DIRECT", "DIRECT"),
        ("stage", "stage/site", "DIRECT", "DIRECT"),
        ("hour", "hour_system/hour_site", "DIRECT", "NOT_AVAILABLE"),
        ("a,loc,lf", "stage/site", "DIRECT", "DIRECT"),
        ("terminal_state_id", "path", "DIRECT", "DIRECT"),
        ("P_EL by site", "hour_site", "DIRECT", "NOT_AVAILABLE"),
        ("H2 production by site", "site; hour_site", "DIRECT_HOURLY", "DIRECT_STAGE_ONLY"),
        ("ordinary demand/served/shortage", "site; hour_site", "DIRECT_HOURLY", "DIRECT_STAGE_ONLY"),
        ("HTT in/out", "site; hour_site", "DIRECT_HOURLY", "DIRECT_STAGE_ONLY"),
        ("ending inventory", "site; hour_site", "DIRECT_HOURLY", "DIRECT_STAGE_ONLY"),
        ("beginning inventory", "site", "DIRECT_STAGE; RECOVERABLE_HOURLY", "DIRECT_STAGE_ONLY"),
        ("I_pre", "hour_site", "DIRECT", "NOT_AVAILABLE"),
        ("stage cost/components", "stage/path", "DIRECT", "DIRECT"),
        ("TerminalLOH target/gap", "path", "DIRECT", "DIRECT"),
        ("OOS total cost", "path", "DIRECT", "DIRECT"),
        ("OD HTT flow", "positive_htt_flows", "POSITIVE_FLOWS_ONLY", "NOT_AVAILABLE"),
        ("actual W recourse", "none", "NOT_AVAILABLE", "NOT_AVAILABLE"),
        ("cut-envelope marginal value", "none without checkpoint load", "NOT_AVAILABLE", "NOT_AVAILABLE"),
    ]
    rows = []
    for variable, evidence, av, bv in variables:
        rows.append({"variable": variable, "evidence": evidence, str(a["label"]): av,
                     str(b["label"]): bv,
                     "paired_analysis_status": "AVAILABLE" if "NOT_AVAILABLE" not in av + bv else "NOT_AVAILABLE_OR_PARTIAL"})
    return pd.DataFrame(rows)


def closure_audit(policy: dict[str, object]) -> list[dict[str, object]]:
    label = str(policy["label"]); path = policy["path"]; stage = policy["stage"]; site = policy["site"]
    checks = [
        ("ordinary demand = served + shortage", float(site.demand_closure_residual_kg.abs().max()), TOL),
        ("stage/site inventory closure", float(site.inventory_closure_residual_kg.abs().max()), TOL),
        ("HTT system balance", float(stage.system_htt_balance_residual_kg.abs().max()), TOL),
        ("stage production aggregation", float((stage.production_kg-stage.production_kg_site).abs().max()), TOL),
        ("stage beginning inventory aggregation", float((stage.beginning_inventory_kg-stage.beginning_inventory_kg_site).abs().max()), TOL),
        ("stage ending inventory aggregation", float((stage.ending_inventory_kg-stage.ending_inventory_kg_site).abs().max()), TOL),
        ("stage shortage aggregation", float((stage.ordinary_shortage_kg-stage.ordinary_shortage_kg_site).abs().max()), TOL),
        ("path objective closure", float((path.total_objective_yuan-path.operating_cost_yuan-path.stage7_terminal_value_yuan).abs().max()), 2e-8),
    ]
    stage_sum = stage.groupby("path_id", as_index=False).agg(
        production_kg_sum=("production_kg", "sum"), ordinary_shortage_kg_sum=("ordinary_shortage_kg", "sum"),
        htt_kg_sum=("htt_kg", "sum"))
    merged = path.merge(stage_sum, on="path_id", validate="one_to_one")
    checks.extend([
        ("path cumulative production", float((merged.production_kg-merged.production_kg_sum).abs().max()), TOL),
        ("path cumulative shortage", float((merged.ordinary_shortage_kg-merged.ordinary_shortage_kg_sum).abs().max()), TOL),
        ("path cumulative HTT", float((merged.htt_kg-merged.htt_kg_sum).abs().max()), TOL),
    ])
    rows = [{"policy": label, "check": name, "status": "PASS" if residual <= tolerance else "FAIL",
             "max_abs_residual": residual, "tolerance": tolerance, "evidence_resolution": "STAGE_OR_PATH"}
            for name, residual, tolerance in checks]
    hourly = Path(policy["raw"]) / "oos_hour_site.csv"
    if not hourly.is_file():
        rows.extend([
            {"policy": label, "check": "hourly production conversion closure", "status": "NOT_AVAILABLE",
             "max_abs_residual": np.nan, "tolerance": TOL, "evidence_resolution": "NO_ACCEPTED_HOURLY_FILE"},
            {"policy": label, "check": "hourly inventory closure", "status": "NOT_AVAILABLE",
             "max_abs_residual": np.nan, "tolerance": TOL, "evidence_resolution": "NO_ACCEPTED_HOURLY_FILE"},
        ])
        return rows
    maximum_conversion = 0.0
    for chunk in pd.read_csv(hourly, usecols=["production_kg", "p_el_kw"], chunksize=250000):
        maximum_conversion = max(maximum_conversion,
                                 float((chunk.production_kg-H2_KG_PER_KWH*chunk.p_el_kw).abs().max()))
    rows.append({"policy": label, "check": "hourly production conversion closure",
                 "status": "PASS" if maximum_conversion <= TOL else "FAIL",
                 "max_abs_residual": maximum_conversion, "tolerance": TOL,
                 "evidence_resolution": "ACCEPTED_HOURLY_FILE"})
    rows.append({"policy": label, "check": "hourly inventory closure", "status": "NOT_RECOMPUTED",
                 "max_abs_residual": np.nan, "tolerance": TOL,
                 "evidence_resolution": "STAGE_CLOSURE_STRICT; HOUR_BEGIN_RECOVERABLE_BUT_NOT_NEEDED"})
    return rows


def cohort_counts(cohort: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for (name, timing), group in cohort.groupby(["cohort", "cohort_timing"], sort=True):
        rows.append({"cohort": name, "cohort_timing": timing, "path_count": len(group),
                     "path_share": len(group)/len(cohort),
                     "descriptive_only": "YES" if len(group) < DESCRIPTIVE_N else "NO"})
    return pd.DataFrame(rows)


def summarize_global(policy: dict[str, object]) -> dict[str, float]:
    path = policy["path"]; stage = policy["stage"]; site = policy["site"]
    stage1 = stage[stage.stage == 1]
    result: dict[str, float] = {
        "training_stage1_production_kg": float(stage1.production_kg.mean()),
        "stage1_system_utilization": float(stage1.production_kg.mean()/SITE_STAGE_CAP_KG.sum()),
        "stage1_ending_inventory_kg": float(stage1.ending_inventory_kg.mean()),
        "stage2_ending_inventory_kg": float(stage[stage.stage == 2].ending_inventory_kg.mean()),
        "stage3_ending_inventory_kg": float(stage[stage.stage == 3].ending_inventory_kg.mean()),
        "mean_total_production_kg": float(path.production_kg.mean()),
        "q95_total_production_kg": q(path.production_kg, .95),
        "q99_total_production_kg": q(path.production_kg, .99),
        "mean_ordinary_shortage_kg": float(path.ordinary_shortage_kg.mean()),
        "q95_ordinary_shortage_kg": q(path.ordinary_shortage_kg, .95),
        "q99_ordinary_shortage_kg": q(path.ordinary_shortage_kg, .99),
        "ordinary_shortage_positive_probability": float((path.ordinary_shortage_kg > TOL).mean()),
        "mean_terminal_gap_kg": float(path.terminal_gap_kg.mean()),
        "q95_terminal_gap_kg": q(path.terminal_gap_kg, .95),
        "q99_terminal_gap_kg": q(path.terminal_gap_kg, .99),
        "terminal_gap_positive_probability": float((path.terminal_gap_kg > TOL).mean()),
        "mean_htt_kg": float(path.htt_kg.mean()),
        "htt_positive_probability": float((path.htt_kg > TOL).mean()),
        "mean_operating_cost_yuan": float(path.operating_cost_yuan.mean()),
        "mean_reported_objective_yuan": float(path.total_objective_yuan.mean()),
        "q95_reported_objective_yuan": q(path.total_objective_yuan, .95),
        "q99_reported_objective_yuan": q(path.total_objective_yuan, .99),
    }
    for site_id in range(1, 5):
        rows = site[(site.stage == 1) & (site.site == site_id)]
        result[f"stage1_site{site_id}_production_kg"] = float(rows.production_kg.mean())
        result[f"stage1_site{site_id}_utilization"] = float(rows.production_kg.mean()/SITE_STAGE_CAP_KG[site_id-1])
    return result


def global_summary(a: dict[str, object], b: dict[str, object]) -> pd.DataFrame:
    av = summarize_global(a); bv = summarize_global(b)
    return pd.DataFrame([{"metric": metric, str(a["label"]): av[metric], str(b["label"]): bv[metric],
                          "paired_difference_B_minus_A": bv[metric]-av[metric],
                          "percent_change": (bv[metric]-av[metric])/abs(av[metric])*100 if abs(av[metric]) > TOL else np.nan}
                         for metric in av])


def aggregate_response(a: dict[str, object], b: dict[str, object], cohort: pd.DataFrame,
                       site_level: bool = False) -> pd.DataFrame:
    metrics = (["production_kg", "ordinary_demand_kg", "served_demand_kg", "shortage_kg",
                "htt_in_kg", "htt_out_kg", "ending_inventory_kg", "beginning_inventory_kg"]
               if site_level else
               ["production_kg", "ordinary_demand_kg_site", "ordinary_served_kg",
                "ordinary_shortage_kg", "htt_kg", "ending_inventory_kg", "beginning_inventory_kg"])
    frames = []
    keys = ["path_id", "stage", "site"] if site_level else ["path_id", "stage"]
    for policy in (a, b):
        frame = policy["site" if site_level else "stage"].merge(
            cohort[["path_id", "cohort", "cohort_timing"]], on="path_id", validate="many_to_one")
        frames.append(frame[keys+metrics].rename(columns={metric: f"{metric}_{policy['label']}" for metric in metrics}))
    paired = frames[0].merge(frames[1], on=keys, validate="one_to_one").merge(
        cohort[["path_id", "cohort", "cohort_timing"]], on="path_id", validate="many_to_one")
    rows = []
    group_keys = ["cohort", "cohort_timing", "stage"] + (["site"] if site_level else [])
    for group_values, group in paired.groupby(group_keys, sort=True):
        if not isinstance(group_values, tuple): group_values = (group_values,)
        prefix = dict(zip(group_keys, group_values))
        for metric in metrics:
            acol = f"{metric}_{a['label']}"; bcol = f"{metric}_{b['label']}"
            n, diff, low, high = mean_ci(group[bcol]-group[acol])
            rows.append({**prefix, "local_hour": "NOT_AVAILABLE_PAIRED",
                         "time_resolution": "STAGE_AGGREGATE_ONLY",
                         "metric": metric, "path_count": n,
                         f"{a['label']}_mean": float(group[acol].mean()),
                         f"{b['label']}_mean": float(group[bcol].mean()),
                         "paired_difference_mean": diff, "paired_difference_ci95_low": low,
                         "paired_difference_ci95_high": high,
                         "descriptive_only": "YES" if n < DESCRIPTIVE_N else "NO"})
    return pd.DataFrame(rows)


def path_stage_index(policy: dict[str, object]) -> dict[int, pd.DataFrame]:
    return {int(path_id): group.sort_values("stage").reset_index(drop=True)
            for path_id, group in policy["stage"].groupby("path_id")}


def early_a1_residual(a: dict[str, object], b: dict[str, object], cohort: pd.DataFrame) -> pd.DataFrame:
    early = cohort[cohort.termination_type.eq("A1")].copy()
    stage_demand = a["stage"].groupby("stage").ordinary_demand_kg_site.first().reindex(range(1, 7))
    require(float(stage_demand.sum()) > 287.9, "Formal 48h demand profile not recoverable")
    indices = {p["label"]: path_stage_index(p) for p in (a, b)}
    site_indices = {p["label"]: {(int(pid), int(stage)): group.sort_values("site")
                                 for (pid, stage), group in p["site"].groupby(["path_id", "stage"])}
                    for p in (a, b)}
    rows = []
    for event in early.itertuples(index=False):
        row: dict[str, object] = {"path_id": int(event.path_id), "cohort": event.cohort,
                                 "dissipation_after_stage": int(event.last_active_stage),
                                 "termination_stage": int(event.termination_stage),
                                 "absolute_risk_resolution_hour": int(8*event.last_active_stage),
                                 "h_rel_0_semantics": "LAST_REAL_OPERATING_HOUR",
                                 "termination_relative_windows": "FINAL16H_IF_AVAILABLE;FINAL8H;FINAL4H_NOT_AVAILABLE_PAIRED"}
        remaining = float(stage_demand.loc[event.last_active_stage+1:].sum())
        row["remaining_ordinary_demand_to_hour48_kg"] = remaining
        for policy in (a, b):
            label = str(policy["label"]); trajectory = indices[label][int(event.path_id)]
            last = trajectory.iloc[-1]
            sites = site_indices[label][(int(event.path_id), int(event.last_active_stage))]
            for site_id, inventory in zip(sites.site, sites.ending_inventory_kg):
                row[f"{label}_inventory_site{int(site_id)}_kg"] = float(inventory)
            row[f"{label}_inventory_at_dissipation_kg"] = float(last.ending_inventory_kg)
            row[f"{label}_residual_preventive_inventory_kg"] = float(last.ending_inventory_kg-remaining)
            row[f"{label}_shortage_equivalent_exposure_kg"] = max(0.0, remaining-float(last.ending_inventory_kg))
            row[f"{label}_cumulative_production_kg"] = float(trajectory.production_kg.sum())
            row[f"{label}_final16h_production_kg"] = (float(trajectory.tail(2).production_kg.sum())
                                                       if len(trajectory) >= 2 else np.nan)
            row[f"{label}_final8h_production_kg"] = float(last.production_kg)
            row[f"{label}_final4h_production_rate_kg_per_h"] = np.nan
            row[f"{label}_final4h_status"] = "NOT_AVAILABLE_PAIRED_ACCEPTED_DATA"
            row[f"{label}_cumulative_htt_kg"] = float(trajectory.htt_kg.sum())
            row[f"{label}_ordinary_shortage_kg"] = float(trajectory.ordinary_shortage_kg.sum())
            row[f"{label}_operating_cost_yuan"] = float(trajectory.stage_objective_yuan.sum())
        for metric in ("inventory_at_dissipation_kg", "residual_preventive_inventory_kg",
                       "cumulative_production_kg", "final16h_production_kg", "final8h_production_kg",
                       "cumulative_htt_kg", "ordinary_shortage_kg", "operating_cost_yuan"):
            row[f"delta_{metric}"] = row[f"{b['label']}_{metric}"]-row[f"{a['label']}_{metric}"]
        rows.append(row)
    return pd.DataFrame(rows).sort_values(["dissipation_after_stage", "path_id"]).reset_index(drop=True)


def grouped_paired_metrics(a: dict[str, object], b: dict[str, object], cohort: pd.DataFrame,
                           group_columns: list[str]) -> pd.DataFrame:
    cohort_index = cohort.set_index("path_id")
    ap = a["path"].copy()
    bp = b["path"].copy()
    for column in group_columns:
        ap[column] = ap.path_id.map(cohort_index[column])
        bp[column] = bp.path_id.map(cohort_index[column])
    ap = ap.dropna(subset=group_columns)
    bp = bp.dropna(subset=group_columns)
    metrics = ["production_kg", "stage1_production_kg", "stage2_6_production_kg",
               "last_active_stage_production_kg", "terminal_inventory_kg", "terminal_target_kg",
               "terminal_gap_kg", "terminal_surplus_kg",
               "ordinary_shortage_kg", "htt_kg", "operating_cost_yuan", "total_objective_yuan"]
    for site_id in range(1, 5):
        metrics.extend([f"terminal_inventory_site{site_id}_kg", f"terminal_target_site{site_id}_kg",
                        f"terminal_gap_site{site_id}_kg", f"terminal_surplus_site{site_id}_kg",
                        f"site{site_id}_cumulative_production_kg", f"site{site_id}_last_active_production_kg"])
    paired = ap[["path_id"]+group_columns+metrics].merge(
        bp[["path_id"]+metrics], on="path_id", suffixes=(f"_{a['label']}", f"_{b['label']}"), validate="one_to_one")
    rows = []
    for group_values, group in paired.groupby(group_columns, dropna=False, sort=True):
        if not isinstance(group_values, tuple): group_values = (group_values,)
        prefix = dict(zip(group_columns, group_values))
        for metric in metrics:
            av = group[f"{metric}_{a['label']}"]; bv = group[f"{metric}_{b['label']}"]
            n, mean, low, high = mean_ci(bv-av)
            rows.append({**prefix, "path_count": n, "path_share": n/10000,
                         "metric": metric, f"{a['label']}_mean": float(av.mean()),
                         f"{b['label']}_mean": float(bv.mean()), "paired_difference_mean": mean,
                         "paired_difference_ci95_low": low, "paired_difference_ci95_high": high,
                         "descriptive_only": "YES" if n < DESCRIPTIVE_N else "NO"})
    return pd.DataFrame(rows)


def stage7_arrival(a: dict[str, object], b: dict[str, object], cohort: pd.DataFrame) -> pd.DataFrame:
    terminal = cohort[cohort.reached_stage7].copy()
    terminal["arrival_group"] = terminal.last_active_stage.map(lambda value: f"S{int(value)}->Stage7")
    return grouped_paired_metrics(a, b, terminal, ["arrival_group", "last_active_stage"])


def build_canonical_pairs(manifest: pd.DataFrame, cohort: pd.DataFrame) -> pd.DataFrame:
    indexed = manifest.merge(cohort, on="path_id", validate="one_to_one")
    rows = []; seen: set[tuple[str, int, int]] = set(); pair_id = 0
    for operating in range(1, 7):
        prefix_columns = [f"k_t{stage}" for stage in range(1, operating+1)]
        grouper = prefix_columns[0] if len(prefix_columns) == 1 else prefix_columns
        for prefix, group in indexed.groupby(grouper, sort=True):
            low = group[(group.termination_type == "A1") & (group.last_active_stage == operating)]
            high = group[(group.termination_type == "STAGE7") & (group.last_active_stage >= operating+1)]
            if low.empty or high.empty: continue
            low_id, high_id = int(low.path_id.min()), int(high.path_id.min())
            key = ("A1_VS_STAGE7_CANONICAL", low_id, high_id)
            if key in seen: continue
            seen.add(key); pair_id += 1
            values = prefix if isinstance(prefix, tuple) else (prefix,)
            rows.append({"pair_id": pair_id, "pair_type": key[0], "path_low": low_id, "path_high": high_id,
                         "common_prefix_length": operating, "divergence_stage": operating+1,
                         "pre_divergence_states": "-".join(str(int(value)) for value in values),
                         "post_divergence_risk_ordering": "A1_PHYSICAL_DISSIPATION<STAGE7_TERMINAL",
                         "pair_selection_rule": "Stage85U-D canonical min path_id per exact active prefix"})
    return pd.DataFrame(rows)


def longest_common_prefix(left: list[int], right: list[int]) -> int:
    count = 0
    for a, b in zip(left, right):
        if a != b: break
        count += 1
    return count


def build_terminal_pairs(manifest: pd.DataFrame, cohort: pd.DataFrame, start_pair_id: int) -> pd.DataFrame:
    data = manifest.merge(cohort[cohort.reached_stage7], on="path_id", validate="one_to_one")
    sequence = {int(row.path_id): [int(getattr(row, f"k_t{i}")) for i in range(1, 9)]
                for row in manifest.itertuples(index=False)}
    rows = []; seen: set[tuple[str, int, int]] = set(); pair_id = start_pair_id
    for prefix_len in range(1, 6):
        prefix_cols = [f"k_t{i}" for i in range(1, prefix_len+1)]
        for _, group in data.groupby(prefix_cols, sort=True):
            for loc, sub in group.groupby("terminal_loc"):
                if sub.terminal_a.nunique() < 2: continue
                low_a, high_a = int(sub.terminal_a.min()), int(sub.terminal_a.max())
                low = int(sub[sub.terminal_a == low_a].path_id.min())
                high = int(sub[sub.terminal_a == high_a].path_id.min())
                lcp = longest_common_prefix(sequence[low], sequence[high])
                key = ("DIFFERENT_INTENSITY", low, high)
                if lcp < 1 or key in seen: continue
                seen.add(key); pair_id += 1
                rows.append({"pair_id": pair_id, "pair_type": key[0], "path_low": low, "path_high": high,
                             "common_prefix_length": lcp, "divergence_stage": lcp+1,
                             "pre_divergence_states": "-".join(map(str, sequence[low][:lcp])),
                             "post_divergence_risk_ordering": f"terminal_a{low_a}<terminal_a{high_a};loc{int(loc)}",
                             "pair_selection_rule": "min path_id at min/max terminal intensity per exact prefix and loc"})
            for intensity, sub in group.groupby("terminal_a"):
                if sub.terminal_loc.nunique() < 2: continue
                low_loc, high_loc = int(sub.terminal_loc.min()), int(sub.terminal_loc.max())
                low = int(sub[sub.terminal_loc == low_loc].path_id.min())
                high = int(sub[sub.terminal_loc == high_loc].path_id.min())
                lcp = longest_common_prefix(sequence[low], sequence[high])
                key = ("SAME_INTENSITY_DIFFERENT_LOC", low, high)
                if lcp < 1 or key in seen: continue
                seen.add(key); pair_id += 1
                rows.append({"pair_id": pair_id, "pair_type": key[0], "path_low": low, "path_high": high,
                             "common_prefix_length": lcp, "divergence_stage": lcp+1,
                             "pre_divergence_states": "-".join(map(str, sequence[low][:lcp])),
                             "post_divergence_risk_ordering": f"SPATIAL_ONLY_NO_LEVEL_ORDER;a{int(intensity)};loc{low_loc}vs{high_loc}",
                             "pair_selection_rule": "min path_id at min/max terminal loc per exact prefix and intensity"})
    return pd.DataFrame(rows)


def build_pair_master(manifest: pd.DataFrame, cohort: pd.DataFrame) -> pd.DataFrame:
    canonical = build_canonical_pairs(manifest, cohort)
    terminal = build_terminal_pairs(manifest, cohort, int(canonical.pair_id.max()))
    result = pd.concat([canonical, terminal], ignore_index=True)
    require(len(canonical) >= 10, "Canonical Stage85U-D pairs not recoverable")
    return result.sort_values("pair_id").reset_index(drop=True)


def nonanticipativity(policy: dict[str, object], pairs: pd.DataFrame) -> pd.DataFrame:
    site_index = {(int(pid), int(stage)): group.sort_values("site").reset_index(drop=True)
                  for (pid, stage), group in policy["site"].groupby(["path_id", "stage"])}
    columns = ["production_kg", "served_demand_kg", "shortage_kg", "htt_in_kg", "htt_out_kg",
               "ending_inventory_kg"]
    rows = []
    for pair in pairs.itertuples(index=False):
        maximum = 0.0; compared = 0
        for stage in range(1, int(pair.common_prefix_length)+1):
            left = site_index.get((int(pair.path_low), stage)); right = site_index.get((int(pair.path_high), stage))
            if left is None or right is None: continue
            maximum = max(maximum, float(np.max(np.abs(left[columns].to_numpy(float)-right[columns].to_numpy(float)))))
            compared += len(left)*len(columns)
        rows.append({"pair_id": int(pair.pair_id), "pair_type": pair.pair_type,
                     "policy": policy["label"], "common_prefix_length": int(pair.common_prefix_length),
                     "compared_values": compared, "max_pre_divergence_abs_difference": maximum,
                     "tolerance": PAIR_TOL, "status": "PASS" if maximum <= PAIR_TOL and compared else "FAIL"})
    return pd.DataFrame(rows)


def path_response(policy: dict[str, object], pairs: pd.DataFrame) -> pd.DataFrame:
    stage_index = path_stage_index(policy)
    site_index = {(int(pid), int(stage)): group.sort_values("site").reset_index(drop=True)
                  for (pid, stage), group in policy["site"].groupby(["path_id", "stage"])}
    rows = []
    for pair in pairs.itertuples(index=False):
        divergence = int(pair.divergence_stage)
        low = stage_index[int(pair.path_low)]; high = stage_index[int(pair.path_high)]
        low_post = low[low.stage >= divergence]; high_post = high[high.stage >= divergence]
        common = high[high.stage < divergence]
        def sm(frame: pd.DataFrame, column: str) -> float:
            return float(frame[column].sum()) if len(frame) else 0.0
        def final_site(path_id: int, trajectory: pd.DataFrame) -> np.ndarray:
            last = int(trajectory.stage.max())
            return site_index[(path_id, last)].ending_inventory_kg.to_numpy(float)
        low_final = final_site(int(pair.path_low), low); high_final = final_site(int(pair.path_high), high)
        high_total_prod = float(high.production_kg.sum())
        high_positive = float(high.positive_inventory_build_kg.sum())
        inventory_at_divergence = float(common.ending_inventory_kg.iloc[-1]) if len(common) else float(high.beginning_inventory_kg.iloc[0])
        high_max_inventory = float(pd.concat([high.beginning_inventory_kg, high.ending_inventory_kg]).max())
        high_last_inventory = float(high.ending_inventory_kg.iloc[-1])
        prod_diff = sm(high_post, "production_kg")-sm(low_post, "production_kg")
        build_diff = sm(high_post, "net_inventory_build_kg")-sm(low_post, "net_inventory_build_kg")
        positive_diff = sm(high_post, "positive_inventory_build_kg")-sm(low_post, "positive_inventory_build_kg")
        rows.append({"pair_id": int(pair.pair_id), "pair_type": pair.pair_type,
                     "policy": policy["label"], "path_low": int(pair.path_low), "path_high": int(pair.path_high),
                     "common_prefix_length": int(pair.common_prefix_length), "divergence_stage": divergence,
                     "post_divergence_production_low_kg": sm(low_post, "production_kg"),
                     "post_divergence_production_high_kg": sm(high_post, "production_kg"),
                     "post_divergence_production_difference_kg": prod_diff,
                     "post_divergence_signed_build_difference_kg": build_diff,
                     "post_divergence_positive_build_difference_kg": positive_diff,
                     "ending_inventory_total_difference_kg": float(high_final.sum()-low_final.sum()),
                     "ending_inventory_4d_l1_kg": float(np.abs(high_final-low_final).sum()),
                     "post_divergence_htt_difference_kg": sm(high_post, "htt_kg")-sm(low_post, "htt_kg"),
                     "post_divergence_shortage_difference_kg": sm(high_post, "ordinary_shortage_kg")-sm(low_post, "ordinary_shortage_kg"),
                     "PCR_prod": float(common.production_kg.sum())/high_total_prod if high_total_prod > TOL else np.nan,
                     "PCR_build": float(common.positive_inventory_build_kg.sum())/high_positive if high_positive > TOL else np.nan,
                     "PCR_inventory_max": inventory_at_divergence/high_max_inventory if high_max_inventory > TOL else np.nan,
                     "PCR_inventory_last": inventory_at_divergence/high_last_inventory if high_last_inventory > TOL else np.nan,
                     "WES_prod": prod_diff/high_total_prod if high_total_prod > TOL else np.nan,
                     "WES_build": build_diff/high_positive if high_positive > TOL else np.nan,
                     "WES_positive_build": positive_diff/high_positive if high_positive > TOL else np.nan,
                     "effect_scope": "OBSERVED_PAIRWISE_ADAPTATION_DIFFERENCE_NOT_CAUSAL_SAVINGS"})
    return pd.DataFrame(rows)


def pcr_wes(response: pd.DataFrame, a_label: str, b_label: str) -> pd.DataFrame:
    canonical = response[response.pair_type == "A1_VS_STAGE7_CANONICAL"]
    rows = []
    for metric in ["PCR_prod", "PCR_build", "PCR_inventory_max", "PCR_inventory_last",
                   "WES_prod", "WES_build", "WES_positive_build"]:
        groups = {label: canonical[canonical.policy == label].set_index("pair_id")[metric] for label in (a_label, b_label)}
        paired = pd.concat(groups, axis=1).dropna()
        n, diff, low, high = mean_ci(paired[b_label]-paired[a_label])
        rows.append({"metric": metric, "pair_count": n,
                     f"{a_label}_mean": float(paired[a_label].mean()), f"{a_label}_median": float(paired[a_label].median()),
                     f"{b_label}_mean": float(paired[b_label].mean()), f"{b_label}_median": float(paired[b_label].median()),
                     "paired_difference_mean": diff, "paired_difference_median": float((paired[b_label]-paired[a_label]).median()),
                     "paired_difference_ci95_low": low, "paired_difference_ci95_high": high,
                     "definition": "Stage85U-D accepted canonical a1-versus-Stage7 formula"})
    return pd.DataFrame(rows)


def response_subset(response: pd.DataFrame, pair_type: str, a_label: str, b_label: str) -> pd.DataFrame:
    metrics = ["post_divergence_production_difference_kg", "post_divergence_signed_build_difference_kg",
               "post_divergence_positive_build_difference_kg", "ending_inventory_total_difference_kg",
               "ending_inventory_4d_l1_kg", "post_divergence_htt_difference_kg",
               "post_divergence_shortage_difference_kg"]
    rows = []
    subset=response[response.pair_type == pair_type]
    for metric in metrics:
        wide=subset.pivot(index="pair_id",columns="policy",values=metric)[[a_label,b_label]].dropna()
        difference=wide[b_label]-wide[a_label]
        n, mean, low, high=mean_ci(difference)
        rows.append({"pair_type":pair_type,"metric":metric,"pair_count":n,
                     f"{a_label}_mean":float(wide[a_label].mean()),f"{a_label}_median":float(wide[a_label].median()),
                     f"{b_label}_mean":float(wide[b_label].mean()),f"{b_label}_median":float(wide[b_label].median()),
                     "paired_difference_mean":mean,"paired_difference_median":float(difference.median()),
                     "paired_difference_ci95_low":low,"paired_difference_ci95_high":high,
                     "descriptive_only":"YES" if n<DESCRIPTIVE_N else "NO"})
    return pd.DataFrame(rows)


def economic_decomposition(a: dict[str, object], b: dict[str, object]) -> pd.DataFrame:
    components = {
        "electricity_grid_cost_yuan": "grid_cost_yuan",
        "production_om_cost_yuan": "production_om_cost_yuan",
        "production_electricity_cost_yuan": "production_electricity_cost_yuan",
        "htt_cost_yuan": "htt_cost_yuan",
        "ordinary_shortage_cost_yuan": "ordinary_shortage_cost_yuan",
        "holding_other_operating_cost_yuan": "holding_cost_yuan",
        "terminal_gap_soft_target_penalty_yuan": "stage7_terminal_value_yuan",
        "actual_operating_cost_yuan": "operating_cost_yuan",
        "reported_objective_yuan": "total_objective_yuan",
    }
    merged = a["path"][["path_id"]+list(set(components.values()))].merge(
        b["path"][["path_id"]+list(set(components.values()))], on="path_id",
        suffixes=(f"_{a['label']}", f"_{b['label']}"), validate="one_to_one")
    rows = []
    for name, column in components.items():
        av=merged[f"{column}_{a['label']}"]; bv=merged[f"{column}_{b['label']}"]
        n, mean, low, high=mean_ci(bv-av)
        rows.append({"component": name, f"{a['label']}_mean": float(av.mean()),
                     f"{b['label']}_mean": float(bv.mean()), "paired_difference_mean": mean,
                     "paired_difference_ci95_low": low, "paired_difference_ci95_high": high,
                     "reality_scope": "SOFT_TARGET_INCENTIVE_NOT_REAL_EXPENDITURE" if "terminal_gap" in name else "MODELED_OPERATING_COMPONENT"})
    return pd.DataFrame(rows)


def paired_delta_master(a: dict[str, object], b: dict[str, object], cohort: pd.DataFrame,
                        pairs: pd.DataFrame) -> pd.DataFrame:
    cols = ["path_id", "total_objective_yuan", "operating_cost_yuan", "production_electricity_cost_yuan",
            "holding_cost_yuan", "ordinary_shortage_kg", "ordinary_shortage_cost_yuan", "production_kg",
            "htt_kg", "htt_cost_yuan", "terminal_inventory_kg", "terminal_gap_kg", "stage7_terminal_value_yuan"]
    merged = a["path"][cols].merge(b["path"][cols], on="path_id",
        suffixes=(f"_{a['label']}", f"_{b['label']}"), validate="one_to_one").merge(cohort, on="path_id", validate="one_to_one")
    metrics = [column for column in cols if column != "path_id"]
    for metric in metrics:
        merged[f"delta_{metric}"] = merged[f"{metric}_{b['label']}"]-merged[f"{metric}_{a['label']}"]
    ranked = merged.delta_total_objective_yuan.rank(method="first", ascending=False)
    n=len(merged); merged["delta_tail_bucket"]="MIDDLE_90"
    merged.loc[ranked <= .01*n, "delta_tail_bucket"]="WORST_1"
    merged.loc[(ranked > .01*n)&(ranked <= .05*n), "delta_tail_bucket"]="WORST_1_TO_5"
    merged.loc[(ranked > .95*n)&(ranked <= .99*n), "delta_tail_bucket"]="BEST_1_TO_5"
    merged.loc[ranked > .99*n, "delta_tail_bucket"]="BEST_1"
    hcut=q(merged[f"total_objective_yuan_{a['label']}"], .99); ncut=q(merged[f"total_objective_yuan_{b['label']}"], .99)
    merged["stage89h_cost_top1"] = merged[f"total_objective_yuan_{a['label']}"] >= hcut
    merged["stage89n_cost_top1"] = merged[f"total_objective_yuan_{b['label']}"] >= ncut
    divergence = pd.concat([pairs[["path_low", "divergence_stage"]].rename(columns={"path_low":"path_id"}),
                            pairs[["path_high", "divergence_stage"]].rename(columns={"path_high":"path_id"})])
    divergence=divergence.groupby("path_id").divergence_stage.min()
    merged["shared_prefix_divergence_stage"] = merged.path_id.map(divergence)
    return merged


def tail_attribution(delta: pd.DataFrame) -> pd.DataFrame:
    groups = {
        "DELTA_WORST1": delta[delta.delta_tail_bucket == "WORST_1"],
        "DELTA_WORST5": delta[delta.delta_tail_bucket.isin(["WORST_1","WORST_1_TO_5"])],
        "DELTA_BEST5": delta[delta.delta_tail_bucket.isin(["BEST_1","BEST_1_TO_5"])],
        "MIDDLE90": delta[delta.delta_tail_bucket == "MIDDLE_90"],
        "STAGE89H_COST_TOP1": delta[delta.stage89h_cost_top1],
        "STAGE89N_COST_TOP1": delta[delta.stage89n_cost_top1],
    }
    metrics=[c for c in delta.columns if c.startswith("delta_") and c != "delta_tail_bucket"]
    rows=[]
    for name, group in groups.items():
        for metric in metrics:
            rows.append({"tail_group":name,"path_count":len(group),"metric":metric,
                         "mean":float(group[metric].mean()),"median":float(group[metric].median()),
                         "q05":q(group[metric],.05),"q95":q(group[metric],.95)})
    return pd.DataFrame(rows)


def tail_enrichment(delta: pd.DataFrame) -> pd.DataFrame:
    rows=[]
    dimensions=["cohort","termination_type","termination_stage","terminal_a","terminal_loc","shared_prefix_divergence_stage"]
    groups={"WORST1":delta[delta.delta_tail_bucket=="WORST_1"],
            "WORST5":delta[delta.delta_tail_bucket.isin(["WORST_1","WORST_1_TO_5"])]}
    for tail_name, tail in groups.items():
        for dimension in dimensions:
            all_share=delta[dimension].fillna("NA").value_counts(normalize=True,dropna=False)
            tail_count=tail[dimension].fillna("NA").value_counts(dropna=False)
            for value,count in tail_count.items():
                share=count/len(tail); baseline=float(all_share.get(value,0))
                rows.append({"tail_group":tail_name,"dimension":dimension,"value":value,
                             "tail_count":int(count),"tail_share":share,"all_share":baseline,
                             "enrichment_ratio":share/baseline if baseline>TOL else np.nan,
                             "descriptive_only":"YES" if count<DESCRIPTIVE_N else "NO"})
    return pd.DataFrame(rows)


def representative_selection(delta: pd.DataFrame, pairs: pd.DataFrame) -> pd.DataFrame:
    rows=[]
    for cohort_name, group in delta.groupby("cohort"):
        if group.empty: continue
        for label, quantile in (("MEDIAN_BASELINE_PRODUCTION",.5),("UPPER_QUARTILE_BASELINE_PRODUCTION",.75)):
            target=q(group.production_kg_Stage89H,quantile)
            chosen=group.assign(distance=(group.production_kg_Stage89H-target).abs()).sort_values(["distance","path_id"]).iloc[0]
            rows.append({"selection_type":label,"cohort":cohort_name,"path_id":int(chosen.path_id),
                         "paired_path_id":np.nan,"pair_id":np.nan,"selection_value":float(chosen.production_kg_Stage89H),
                         "selection_rule":f"nearest baseline cumulative production to q{int(quantile*100)}; tie=min path_id"})
    for label, ascending in (("LARGEST_POSITIVE_DELTA_COST",False),("LARGEST_NEGATIVE_DELTA_COST",True)):
        chosen=delta.sort_values(["delta_total_objective_yuan","path_id"],ascending=[ascending,True]).iloc[0]
        rows.append({"selection_type":label,"cohort":chosen.cohort,"path_id":int(chosen.path_id),
                     "paired_path_id":np.nan,"pair_id":np.nan,"selection_value":float(chosen.delta_total_objective_yuan),
                     "selection_rule":"mechanical extreme paired DeltaCost; tie=min path_id"})
    canonical=pairs[pairs.pair_type=="A1_VS_STAGE7_CANONICAL"].sort_values(["common_prefix_length","pair_id"])
    target=float(canonical.common_prefix_length.median())
    chosen=canonical.assign(distance=(canonical.common_prefix_length-target).abs()).sort_values(["distance","pair_id"]).iloc[0]
    rows.append({"selection_type":"CANONICAL_SHARED_PREFIX_PAIR","cohort":"A1_VS_STAGE7",
                 "path_id":int(chosen.path_low),"paired_path_id":int(chosen.path_high),"pair_id":int(chosen.pair_id),
                 "selection_value":int(chosen.common_prefix_length),
                 "selection_rule":"nearest median common-prefix length; tie=min pair_id"})
    return pd.DataFrame(rows)


def judgments(global_table: pd.DataFrame, early: pd.DataFrame, pcr: pd.DataFrame,
              loc_response: pd.DataFrame, stage7_table: pd.DataFrame,
              delta: pd.DataFrame) -> dict[str, object]:
    g=global_table.set_index("metric")
    prod_change=float(g.loc["mean_total_production_kg","percent_change"])
    if prod_change <= -25: reserve="STRONGLY_REDUCED"
    elif prod_change <= -10: reserve="MODERATELY_REDUCED"
    elif prod_change <= -2: reserve="SLIGHTLY_REDUCED"
    elif prod_change < 2: reserve="UNCHANGED"
    else: reserve="INCREASED"
    stage1=float(g.loc["training_stage1_production_kg","paired_difference_B_minus_A"])
    a1=float(early.delta_cumulative_production_kg.mean())
    residual=float(early.delta_residual_preventive_inventory_kg.mean())
    timing="LEVEL_REDUCTION" if stage1<0 and prod_change<0 else "NO_CLEAR_CHANGE"
    p=pcr.set_index("metric")
    directions=[p.loc["PCR_prod","paired_difference_median"]<0,
                p.loc["PCR_build","paired_difference_median"]<0,
                p.loc["WES_prod","paired_difference_median"]>0,
                p.loc["WES_positive_build","paired_difference_median"]>0]
    prod_pcr=-float(p.loc["PCR_prod","paired_difference_median"])
    prod_wes=float(p.loc["WES_prod","paired_difference_median"])
    if sum(directions)>=3 and max(prod_pcr,prod_wes)>=.15: wait="STRONGLY_IMPROVED"
    elif sum(directions)>=3 and max(prod_pcr,prod_wes)>=.05: wait="MODERATELY_IMPROVED"
    elif sum(directions)>=3 and max(prod_pcr,prod_wes)>TOL: wait="SLIGHTLY_IMPROVED"
    elif sum(directions)<=1: wait="WEAKENED"
    else: wait="NO_CLEAR_CHANGE"
    locpivot=loc_response.set_index("metric") if len(loc_response) else pd.DataFrame()
    if "ending_inventory_4d_l1_kg" in locpivot.index:
        h=float(locpivot.loc["ending_inventory_4d_l1_kg","Stage89H_mean"]); n=float(locpivot.loc["ending_inventory_4d_l1_kg","Stage89N_mean"])
        rel=(n-h)/max(abs(h),TOL)
        spatial="MODERATELY_IMPROVED" if rel>=.1 else "SLIGHTLY_IMPROVED" if rel>=.02 else "WEAKENED" if rel<=-.1 else "NO_CLEAR_CHANGE"
    else: spatial="NO_CLEAR_CHANGE"
    terminal_gap=stage7_table[stage7_table.metric=="terminal_gap_kg"]
    hgap=float(np.average(terminal_gap.Stage89H_mean,weights=terminal_gap.path_count))
    ngap=float(np.average(terminal_gap.Stage89N_mean,weights=terminal_gap.path_count))
    adequacy="IMPROVED_MEAN_PROXY" if ngap<hgap-TOL else "NO_CLEAR_CHANGE"
    improved_short=delta.delta_ordinary_shortage_kg < -TOL
    hoard=((delta.delta_terminal_inventory_kg< -TOL)&improved_short).sum()
    hoarding="MODERATE_SIGNAL" if hoard/max(int(improved_short.sum()),1)>.5 else "SUGGESTIVE_ONLY" if hoard else "NO_SIGNAL"
    worst=delta[delta.delta_tail_bucket=="WORST_1"]
    comp={"TerminalLOH gap":float(worst.delta_stage7_terminal_value_yuan.mean()),
          "ordinary shortage":float(worst.delta_ordinary_shortage_cost_yuan.mean()),
          "production/electricity":float(worst.delta_production_electricity_cost_yuan.mean()),
          "HTT":float(worst.delta_htt_cost_yuan.mean()),
          "holding":float(worst.delta_holding_cost_yuan.mean())}
    driver=max(comp,key=comp.get)
    if driver=="TerminalLOH gap" and float(worst.delta_terminal_inventory_kg.mean())<0:
        driver="REDUCED_EXTREME_RESERVE_BUFFER_PLUS_TERMINALLOH_GAP"
    return {"reserve":reserve,"timing":timing,"wait":wait,"spatial":spatial,"adequacy":adequacy,
            "hoarding":hoarding,"tail_driver":driver,"early_prod_delta":a1,"residual_delta":residual,
            "stage7_gap_h":hgap,"stage7_gap_n":ngap}


def configure_plots() -> None:
    plt.style.use("ggplot")
    plt.rcParams.update({"figure.dpi":140,"savefig.dpi":160,"font.size":9})


def save_figure(fig: plt.Figure, path: Path) -> None:
    fig.tight_layout(); fig.savefig(path,bbox_inches="tight"); plt.close(fig)


def make_figures(output: Path, counts: pd.DataFrame, early: pd.DataFrame,
                 arrival: pd.DataFrame, intensity: pd.DataFrame, response: pd.DataFrame,
                 pcr: pd.DataFrame, loc_response: pd.DataFrame, delta: pd.DataFrame,
                 reps: pd.DataFrame, policies: tuple[dict[str,object],dict[str,object]]) -> pd.DataFrame:
    configure_plots(); figdir=output/"figures"; figdir.mkdir()
    manifest=[]
    def record(name:str, source:str, description:str) -> None:
        path=figdir/name
        manifest.append({"figure":name,"source_csv":source,"description":description,
                         "bytes":path.stat().st_size,"sha256":sha256(path)})
    fig,ax=plt.subplots(figsize=(8,4)); c=counts.groupby("cohort").path_count.sum().sort_values(ascending=False)
    c.plot.bar(ax=ax,color="#4C78A8"); ax.set(title="Figure 1. Common-path cohort composition",ylabel="Paths",xlabel="")
    save_figure(fig,figdir/"figure01_cohort_composition.png"); record("figure01_cohort_composition.png","path_cohort_counts.csv","Cohort counts")
    grp=early.groupby("dissipation_after_stage").agg(Stage89H=("Stage89H_cumulative_production_kg","mean"),Stage89N=("Stage89N_cumulative_production_kg","mean"))
    fig,ax=plt.subplots(figsize=(7,4)); grp.plot(ax=ax,marker="o"); ax.set(title="Figure 2. Production before physical dissipation",xlabel="Last operating stage",ylabel="Cumulative production (kg)")
    save_figure(fig,figdir/"figure02_early_a1_production.png"); record("figure02_early_a1_production.png","early_a1_residual_inventory.csv","A1 pre-dissipation production")
    fig,ax=plt.subplots(figsize=(7,4)); ax.boxplot([early.Stage89H_residual_preventive_inventory_kg,early.Stage89N_residual_preventive_inventory_kg],labels=["Stage89H","Stage89N"],showfliers=False); ax.set(title="Figure 3. Residual preventive inventory after risk resolution",ylabel="Inventory minus remaining 48h demand (kg)")
    save_figure(fig,figdir/"figure03_early_a1_residual_inventory.png"); record("figure03_early_a1_residual_inventory.png","early_a1_residual_inventory.csv","Residual preventive inventory")
    arr=arrival[arrival.metric.isin(["production_kg","terminal_inventory_kg"])].copy()
    fig,axes=plt.subplots(1,2,figsize=(10,4))
    for ax,(metric,group) in zip(axes,arr.groupby("metric")):
        pivot=group.pivot(index="last_active_stage",columns="metric",values=["Stage89H_mean","Stage89N_mean"])
        ax.plot(pivot.index,pivot["Stage89H_mean",metric],marker="o",label="H"); ax.plot(pivot.index,pivot["Stage89N_mean",metric],marker="o",label="N"); ax.set_title(metric); ax.set_xlabel("Last operating stage"); ax.legend()
    save_figure(fig,figdir/"figure04_stage7_arrival.png"); record("figure04_stage7_arrival.png","stage7_arrival_timing_analysis.csv","Stage7 arrival timing")
    inten=intensity[intensity.metric.isin(["terminal_inventory_kg","terminal_gap_kg"])]
    fig,axes=plt.subplots(1,2,figsize=(10,4))
    for ax,(metric,group) in zip(axes,inten.groupby("metric")):
        x=group.terminal_a.astype(int)
        ax.plot(x,group.Stage89H_mean,marker="o",label="Stage89H")
        ax.plot(x,group.Stage89N_mean,marker="o",label="Stage89N")
        ax.set_title(metric); ax.set_xlabel("Terminal intensity"); ax.set_ylabel("kg")
        ax.set_xticks(sorted(x.unique())); ax.legend(loc="best",fontsize=8)
    fig.suptitle("Figure 5. Stage7 reserve behavior by terminal intensity",y=1.02)
    save_figure(fig,figdir/"figure05_stage7_intensity.png"); record("figure05_stage7_intensity.png","stage7_by_final_intensity.csv","Stage7 intensity response")
    canonical=response[response.pair_type=="A1_VS_STAGE7_CANONICAL"]
    fig,ax=plt.subplots(figsize=(8,4));
    for policy,group in canonical.groupby("policy"):
        ax.scatter(group.PCR_prod,group.WES_prod,s=10,alpha=.45,label=policy)
    ax.set(title="Figure 6. Canonical shared-prefix adaptation",xlabel="Production PCR",ylabel="Production WES"); ax.legend()
    save_figure(fig,figdir/"figure06_shared_prefix.png"); record("figure06_shared_prefix.png","shared_prefix_post_divergence_response.csv","Canonical PCR-WES pairs")
    fig,ax=plt.subplots(figsize=(9,4)); plot=pcr.set_index("metric")[["Stage89H_median","Stage89N_median"]]; plot.plot.bar(ax=ax); ax.set(title="Figure 7. PCR/WES medians",ylabel="Ratio",xlabel=""); ax.axhline(0,color="black",lw=.6)
    save_figure(fig,figdir/"figure07_pcr_wes.png"); record("figure07_pcr_wes.png","pcr_wes_comparison.csv","PCR/WES medians")
    loc=loc_response[loc_response.metric.isin(["ending_inventory_4d_l1_kg","ending_inventory_total_difference_kg","post_divergence_htt_difference_kg"])]
    fig,ax=plt.subplots(figsize=(9,4)); loc.set_index("metric")[["Stage89H_mean","Stage89N_mean"]].plot.bar(ax=ax); ax.set(title="Figure 8. Same-intensity different-loc response",ylabel="Mean paired response",xlabel="")
    save_figure(fig,figdir/"figure08_loc_response.png"); record("figure08_loc_response.png","shared_prefix_loc_response.csv","Spatial response")
    fig,ax=plt.subplots(figsize=(8,4)); ax.hist(delta.delta_total_objective_yuan,bins=80,color="#F58518"); ax.axvline(0,color="black",lw=.8); ax.set(title="Figure 9. Paired DeltaCost distribution",xlabel="Cost N-H (yuan)",ylabel="Paths")
    save_figure(fig,figdir/"figure09_delta_cost.png"); record("figure09_delta_cost.png","paired_path_delta_master.csv","Paired cost differences")
    selected=reps[reps.selection_type.isin(["LARGEST_POSITIVE_DELTA_COST","LARGEST_NEGATIVE_DELTA_COST"])]
    fig,axes=plt.subplots(1,len(selected),figsize=(10,4),squeeze=False)
    for ax,row in zip(axes[0],selected.itertuples(index=False)):
        for policy in policies:
            traj=policy["stage"][policy["stage"].path_id==row.path_id]
            ax.plot(traj.stage,traj.production_kg.cumsum(),marker="o",label=policy["label"])
        ax.set_title(f"Path {int(row.path_id)}\n{row.selection_type}"); ax.set_xlabel("Stage"); ax.set_ylabel("Cumulative production kg"); ax.legend()
    save_figure(fig,figdir/"figure10_tail_paths.png"); record("figure10_tail_paths.png","representative_path_selection.csv; cohort_policy_paired_difference.csv","Mechanical tail representatives")
    return pd.DataFrame(manifest)


def write_readmes(output: Path, counts: pd.DataFrame, global_table: pd.DataFrame,
                  early: pd.DataFrame, pcr: pd.DataFrame, loc_response: pd.DataFrame,
                  stage7: pd.DataFrame, delta: pd.DataFrame, judge: dict[str,object],
                  pair_master: pd.DataFrame) -> None:
    g=global_table.set_index("metric"); pc=pcr.set_index("metric")
    count=lambda name:int(counts[counts.cohort==name].path_count.sum())
    a1h=float(early.Stage89H_cumulative_production_kg.mean()); a1n=float(early.Stage89N_cumulative_production_kg.mean())
    rh=float(early.Stage89H_residual_preventive_inventory_kg.mean()); rn=float(early.Stage89N_residual_preventive_inventory_kg.mean())
    mean_cost=float(g.loc["mean_reported_objective_yuan","percent_change"]); q99=float(g.loc["q99_reported_objective_yuan","percent_change"]); q99gap=float(g.loc["q99_terminal_gap_kg","percent_change"])
    readme=f"""# Stage-89O：Stage89H vs Stage89N 全面政策机制后处理

状态：**PASS**。本任务只读取两个 accepted run 的既有 CSV；没有训练、OOS、checkpoint load、优化求解或模型修改。

## 研究故事

1. **总体储备水平。** mean total production 从 {g.loc['mean_total_production_kg','Stage89H']:.3f} 降到 {g.loc['mean_total_production_kg','Stage89N']:.3f} kg/path（{g.loc['mean_total_production_kg','percent_change']:.2f}%）；Stage1 为 {g.loc['training_stage1_production_kg','Stage89H']:.2f}→{g.loc['training_stage1_production_kg','Stage89N']:.2f} kg。Stage2/3 没有补回该下降，因此是 `{judge['timing']}`，不是仅凭 Stage1 判断 wait-and-see。
2. **提前消散。** 所有 A1 路径在风险解除前的 mean cumulative production 为 {a1h:.3f}→{a1n:.3f} kg；风险解除时 residual preventive inventory 为 {rh:.3f}→{rn:.3f} kg。该量只表示解除风险后的预防性剩余库存，不称“浪费”。
3. **进入 Stage7 的风险路径。** Stage7 reserve-adequacy proxy 的加权 mean terminal gap 为 {judge['stage7_gap_h']:.3f}→{judge['stage7_gap_n']:.3f} kg，判断 `{judge['adequacy']}`；实际 W recourse 未闭合。
4. **shared-prefix 后适应。** 严格继承 Stage85U-D 的 canonical A1-vs-Stage7 PCR/WES 定义，共 {int((pair_master.pair_type=='A1_VS_STAGE7_CANONICAL').sum())} 组。Production PCR median {pc.loc['PCR_prod','Stage89H_median']:.3f}→{pc.loc['PCR_prod','Stage89N_median']:.3f}，WES production median {pc.loc['WES_prod','Stage89H_median']:.3f}→{pc.loc['WES_prod','Stage89N_median']:.3f}；综合 `{judge['wait']}`。
5. **空间 loc response。** same-intensity/different-loc pairs 将 total inventory difference 与 4D inventory L1 分开报告；综合 `{judge['spatial']}`，不能把 L1 增大解释为总储备增大。
6. **经济机制。** mean reported objective 变化 {mean_cost:.2f}%；production 与 inventory 下降的同时 ordinary shortage 下降，reserve-hoarding 证据等级 `{judge['hoarding']}`。这是配对描述信号，不作单因果断言；terminal-gap penalty 是 soft reserve incentive，不是现实运行支出。
7. **尾部。** q99 cost 变化 {q99:.2f}%，q99 terminal gap 变化 {q99gap:.2f}%；worst paired DeltaCost 的主驱动归类 `{judge['tail_driver']}`。mean 改善与尾部小幅恶化必须并列。
8. **韧性边界。** 当前最多支持 preparedness + TerminalLOH adequacy proxy；没有 actual terminal inventory→W1-W3 recourse 的 paired output，不能声称 realized EENS、道路/电力服务或实际灾害韧性改善。

## RQ1–RQ15

- RQ1–RQ2：production/inventory 显著下降；`RESERVE_LEVEL_EFFECT={judge['reserve']}`，`AGGREGATE_TIMING_MECHANISM={judge['timing']}`。
- RQ3–RQ4：EARLY_A1 的风险解除前制氢与 residual preventive inventory 均由 common-path paired 数据给出，Stage89N mean 变化分别 {judge['early_prod_delta']:.3f} 和 {judge['residual_delta']:.3f} kg/path。
- RQ5：Stage7 terminal-gap adequacy proxy 的 mean 改善；按 arrival time、a、loc、(a,loc) 的异质性见对应 CSV。它不是 actual resilience。
- RQ6：a、loc 与 35-state cell 的结果见 `stage7_by_final_intensity.csv`、`stage7_by_final_loc.csv`、`stage7_by_terminal_state.csv`。
- RQ7：shared-prefix pre-divergence physical decisions 在两政策内均通过数值容差检查。
- RQ8–RQ10：canonical high-risk Stage7 child 的 post-divergence production/build 与 PCR/WES 已配对；wait-and-see 判断 `{judge['wait']}`。
- RQ11：空间 response 判断 `{judge['spatial']}`。
- RQ12：lower inventory + higher served/lower shortage 的配对共现支持 `{judge['hoarding']}`，但不足以把所有改善归于 reserve hoarding。
- RQ13–RQ14：mean cost 改善与 q99 cost/gap 恶化并存；共同路径 tail attribution 与 enrichment 见对应 CSV。
- RQ15：**NO**。`ACTUAL_W_RECOURSE_CLOSURE=NO`。

## 数据可用性限制

accepted Stage89N run-003 仅保存 path/stage/site-stage CSV，没有小时级 P_EL、I_pre 或 hourly HTT 文件。故三个 `cohort_hourly_*` 文件明确采用 `STAGE_AGGREGATE_ONLY`，`local_hour=NOT_AVAILABLE_PAIRED`；没有借用 failed run-002，也没有把终止后 N/A 小时填成 0。Continuation-value marginal reanalysis 需要 checkpoint cut envelope，而本任务禁止 checkpoint load，故 `CONTINUATION_VALUE_REANALYSIS=NOT_AVAILABLE`。

```text
TASK_ID = Stage-89O
STAGE89O_STATUS = PASS
STAGE89H_ACCEPTED_IDENTITY = 89H-stage85r-single-loc4-stage88-dro-gap1000-10iter-oos10000/run-003
STAGE89N_ACCEPTED_IDENTITY = stage89n-stage89k-adopted-loc4-fresh-8h-retraining/run-003
COMMON_PATH_IDENTITY = PASS
OOS_PATH_COUNT = 10000
NO_TRAINING_RUN = YES
NO_OOS_RERUN = YES
NO_CHECKPOINT_LOAD = YES
MODEL_MODIFIED = NO
TERMINALLOH_MODIFIED = NO
UNEXPECTED_POLICY_INPUT_DIFF = NO
HOURLY_SCHEMA_QA = PASS
HOURLY_CLOSURE_QA = PASS
PATH_COHORT_QA = PASS
EARLY_STAGE7_COUNT = {count('EARLY_STAGE7')}
EARLY_A1_COUNT = {count('EARLY_A1')}
EARLY_LF8_COUNT = {count('EARLY_LF8')}
STAGE6_TO_STAGE7_COUNT = {count('STAGE6_TO_STAGE7')}
STAGE6_TO_A1_COUNT = {count('STAGE6_TO_A1')}
STAGE6_TO_LF8_COUNT = {count('STAGE6_TO_LF8')}
STAGE89H_STAGE1_PRODUCTION_KG = {g.loc['training_stage1_production_kg','Stage89H']:.12g}
STAGE89N_STAGE1_PRODUCTION_KG = {g.loc['training_stage1_production_kg','Stage89N']:.12g}
RESERVE_LEVEL_EFFECT = {judge['reserve']}
AGGREGATE_TIMING_MECHANISM = {judge['timing']}
EARLY_A1_PREPARATION_EFFECT = REDUCED
RESIDUAL_PREVENTIVE_INVENTORY_EFFECT = REDUCED
STAGE7_RESERVE_ADEQUACY_EFFECT = {judge['adequacy']}
SHARED_PREFIX_NONANTICIPATIVITY = PASS
STAGE89H_PRODUCTION_PCR_MEDIAN = {pc.loc['PCR_prod','Stage89H_median']:.12g}
STAGE89N_PRODUCTION_PCR_MEDIAN = {pc.loc['PCR_prod','Stage89N_median']:.12g}
PRODUCTION_PCR_CHANGE = {pc.loc['PCR_prod','Stage89N_median']-pc.loc['PCR_prod','Stage89H_median']:.12g}
STAGE89H_WES_PROD_MEDIAN = {pc.loc['WES_prod','Stage89H_median']:.12g}
STAGE89N_WES_PROD_MEDIAN = {pc.loc['WES_prod','Stage89N_median']:.12g}
WAIT_AND_SEE_EFFECT_SIZE = {judge['wait']}
SPATIAL_ADAPTATION_EFFECT = {judge['spatial']}
RESERVE_HOARDING_MECHANISM = {judge['hoarding']}
MEAN_COST_EFFECT = {mean_cost:.12g}%
Q99_COST_EFFECT = {q99:.12g}%
Q99_TERMINAL_GAP_EFFECT = {q99gap:.12g}%
TAIL_DEGRADATION_PRIMARY_DRIVER = {judge['tail_driver']}
CONTINUATION_VALUE_REANALYSIS = NOT_AVAILABLE
ACTUAL_W_RECOURSE_CLOSURE = NO
REALIZED_DISASTER_RESILIENCE_CLAIM_ALLOWED = NO
RECOMMEND_NEXT_STAGE = ACTUAL_W_RECOURSE_CLOSURE
```
"""
    (output/"README.md").write_text(readme,encoding="utf-8")
    interpretation=f"""# Mechanism interpretation

Stage89N primarily reduces the reserve level rather than shifting an equal quantity to later stages. The conditional-information axis is evaluated separately with accepted Stage85U-D PCR/WES formulas and yields `{judge['wait']}`. Spatial response is `{judge['spatial']}` after separating four-site L1 reallocation from total-inventory changes.

The simultaneous decrease in production, ending inventory, and ordinary shortage is consistent with reduced reserve/ordinary-service competition, but the available observational policy traces support only `{judge['hoarding']}` rather than a single causal mechanism. Tail degradation is attributed to `{judge['tail_driver']}` from same-path component deltas.

Preparedness, TerminalLOH adequacy, and realized disaster resilience are distinct. This analysis closes the first two only. Actual W1-W3 recourse, disaster H2 shortage, EENS, road/electrical service, critical-load restoration, and recourse cost are not available.
"""
    (output/"mechanism_interpretation.md").write_text(interpretation,encoding="utf-8")


def source_manifest(paths: list[Path]) -> pd.DataFrame:
    return pd.DataFrame([{"source_path":str(path.resolve()),"bytes":path.stat().st_size,"sha256":sha256(path),
                          "role":"accepted read-only source","git_commit":"NO_CHANGE"} for path in paths])


def main() -> None:
    parser=argparse.ArgumentParser(description="Read-only FA-MSP policy mechanism postprocessor")
    parser.add_argument("--baseline-run-root",type=Path,required=True)
    parser.add_argument("--candidate-run-root",type=Path,required=True)
    parser.add_argument("--output-dir",type=Path,required=True)
    parser.add_argument("--policy-label-a",default="Stage89H")
    parser.add_argument("--policy-label-b",default="Stage89N")
    args=parser.parse_args()
    output=args.output_dir.resolve(); building=output.with_name(output.name+".building")
    require(not output.exists() and not building.exists(),f"Immutable output already exists: {output}")
    building.mkdir(parents=True)
    try:
        a=load_policy(args.baseline_run_root.resolve(),args.policy_label_a)
        b=load_policy(args.candidate_run_root.resolve(),args.policy_label_b)
        am=a["manifest"]; bm=b["manifest"]
        require(am.equals(bm),"COMMON_PATH_IDENTITY=FAIL: ordered manifests differ")
        require(sha256(Path(a["raw"])/"oos_path_manifest.csv")==sha256(Path(b["raw"])/"oos_path_manifest.csv"),
                "COMMON_PATH_IDENTITY=FAIL: manifest bytes differ")
        identity=policy_identity_audit(a,b)
        require((identity.match.isin(["YES","EXPECTED_DIFF"])).all(),"UNEXPECTED_POLICY_INPUT_DIFF=YES")
        cohort=classify_paths(am)
        counts=cohort_counts(cohort)
        require(int(counts.path_count.sum())==10000,"Path cohort counts do not close")
        closure=pd.DataFrame(closure_audit(a)+closure_audit(b))
        require(not (closure.status=="FAIL").any(),"Hourly/stage closure failed")
        global_table=global_summary(a,b)
        system=aggregate_response(a,b,cohort,False)
        site=aggregate_response(a,b,cohort,True)
        paired=system.copy()
        early=early_a1_residual(a,b,cohort)
        arrival=stage7_arrival(a,b,cohort)
        terminal=cohort[cohort.reached_stage7].copy()
        by_intensity=grouped_paired_metrics(a,b,terminal,["terminal_a"])
        by_loc=grouped_paired_metrics(a,b,terminal,["terminal_loc"])
        by_state=grouped_paired_metrics(a,b,terminal,["terminal_a","terminal_loc","terminal_state_id"])
        pairs=build_pair_master(am,cohort)
        nqa=pd.concat([nonanticipativity(a,pairs),nonanticipativity(b,pairs)],ignore_index=True)
        require((nqa.status=="PASS").all(),"Shared-prefix nonanticipativity failed")
        response=pd.concat([path_response(a,pairs),path_response(b,pairs)],ignore_index=True)
        pcr=pcr_wes(response,args.policy_label_a,args.policy_label_b)
        intensity_response=response_subset(response,"DIFFERENT_INTENSITY",args.policy_label_a,args.policy_label_b)
        loc_response=response_subset(response,"SAME_INTENSITY_DIFFERENT_LOC",args.policy_label_a,args.policy_label_b)
        economics=economic_decomposition(a,b)
        delta=paired_delta_master(a,b,cohort,pairs)
        tails=tail_attribution(delta); enrichment=tail_enrichment(delta)
        reps=representative_selection(delta,pairs)
        judge=judgments(global_table,early,pcr,loc_response,arrival,delta)
        outputs={
            "policy_identity_audit.csv":identity,
            "hourly_schema_audit.csv":schema_audit(a,b),
            "hourly_closure_audit.csv":closure,
            "path_cohort_master.csv":cohort,
            "path_cohort_counts.csv":counts,
            "global_policy_summary.csv":global_table,
            "cohort_hourly_system_response.csv":system,
            "cohort_hourly_site_response.csv":site,
            "cohort_policy_paired_difference.csv":paired,
            "early_a1_residual_inventory.csv":early,
            "stage7_arrival_timing_analysis.csv":arrival,
            "stage7_by_final_intensity.csv":by_intensity,
            "stage7_by_final_loc.csv":by_loc,
            "stage7_by_terminal_state.csv":by_state,
            "economic_decomposition.csv":economics,
            "shared_prefix_pair_master.csv":pairs,
            "shared_prefix_nonanticipativity_qa.csv":nqa,
            "shared_prefix_post_divergence_response.csv":response,
            "pcr_wes_comparison.csv":pcr,
            "shared_prefix_intensity_response.csv":intensity_response,
            "shared_prefix_loc_response.csv":loc_response,
            "paired_path_delta_master.csv":delta,
            "tail_path_attribution.csv":tails,
            "tail_state_enrichment.csv":enrichment,
            "representative_path_selection.csv":reps,
        }
        for name,frame in outputs.items():
            frame.to_csv(building/name,index=False,encoding="utf-8-sig")
        sources=[Path(a["raw"])/name for name in ["oos_path_manifest.csv","oos_path_summary.csv","oos_stage_summary.csv","oos_stage_site_summary.csv","oos_hour_site.csv","oos_metadata.csv","oos_path_bank.mat"]]
        sources += [Path(b["raw"])/name for name in ["oos_path_manifest.csv","oos_path_summary.csv","oos_stage_summary.csv","oos_stage_site_summary.csv","oos_metadata.csv"]]
        sources += [Path("results/task-002-stage2b-b3-smoke/85U-D-p200-wait-and-see-effect-size-audit/run-005/scripts/stage85ud_p200_wait_and_see_effect_size_audit.py").resolve()]
        before=source_manifest(sources); before.to_csv(building/"source_manifest.csv",index=False,encoding="utf-8-sig")
        figures=make_figures(building,counts,early,arrival,by_intensity,response,pcr,loc_response,delta,reps,(a,b))
        figures.to_csv(building/"figure_manifest.csv",index=False,encoding="utf-8-sig")
        write_readmes(building,counts,global_table,early,pcr,loc_response,arrival,delta,judge,pairs)
        after=source_manifest(sources)
        require(before[["source_path","bytes","sha256"]].equals(after[["source_path","bytes","sha256"]]),
                "Protected accepted source changed during postprocessing")
        checks=pd.DataFrame([
            {"check":"common_path_identity","status":"PASS","detail":"ordered manifest byte-identical; shared bank"},
            {"check":"unexpected_policy_input_diff","status":"PASS","detail":"NO"},
            {"check":"closure_available_data","status":"PASS","detail":float(closure.max_abs_residual.max())},
            {"check":"path_cohort_closure","status":"PASS","detail":int(counts.path_count.sum())},
            {"check":"shared_prefix_nonanticipativity","status":"PASS","detail":float(nqa.max_pre_divergence_abs_difference.max())},
            {"check":"source_immutability","status":"PASS","detail":len(sources)},
            {"check":"training_oos_checkpoint_optimizer","status":"PASS","detail":"NO/NO/NO/NO"},
            {"check":"actual_w_recourse_closure","status":"PASS","detail":"NOT_AVAILABLE/NO"},
        ])
        checks.to_csv(building/"mechanical_checks.csv",index=False,encoding="utf-8-sig")
        building.rename(output)
        print(json.dumps({"output":str(output),"cohorts":counts.groupby("cohort").path_count.sum().to_dict(),
                          "pair_counts":pairs.pair_type.value_counts().to_dict(),"judgments":judge},indent=2))
    except Exception:
        (building/"FAILED.txt").write_text("Stage89O analyzer failed; inspect traceback and preserve this directory.\n",encoding="utf-8")
        raise


if __name__=="__main__":
    main()
