#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Independent raw/source audit for Stage-89Q-G2 outputs."""

from __future__ import annotations

import ast
import hashlib
import math
import os
from pathlib import Path

import numpy as np
import pandas as pd
from scipy.io import loadmat


ROOT = Path(__file__).resolve().parents[1]
RUN = ROOT / "results/task-002-stage2b-b3-smoke/stage89q-penalty1000-vs1500-long-training/run-003"
DEEP = RUN / "05_analysis/10_deep_penalty1000"
RAW = ROOT / "hourly_grid_h2/output/stage89q_penalty1000_vs1500_long_training/run-003/penalty1000"
PHYS = DEEP / "17_pmax_flexibility_audit"
GRID = DEEP / "18_pmax_grid_hosting_audit"
OUT = DEEP / "19_s4_grid_aware_recoverability"
FIG = RUN / "06_figures/13_s4_grid_aware_recoverability"
MAIN = ROOT / "hourly_grid_h2/analyze_stage89q_s4_grid_aware_recoverability.py"
FORMAL = ROOT / "data/yuanqi/near_stage_msp_input.mat"

EXPECTED_RAW = {
    RAW / "path_summary/oos_path_summary.csv": "99ec55faba4e60e88b25d757deb1a8146515faf666d52979fe69c64362047502",
    RAW / "path_summary/oos_stage_summary.csv": "969c373a9a2ff1b271cde6fda95a6fe8e64b10362518fe4b807c0dc86437c15d",
    RAW / "path_summary/oos_stage_site_summary.csv": "eab41bdf5d58fc971bc65af8c5745de3bd08cc25a0a4d44cc386aeba3f99c89e",
    RAW / "hourly_site/oos_hour_site.csv": "af3b3d5c4aa69e6d29b35a88008b4d82360c4b8391fc783141078f7ad68b0cda",
    RAW / "grid_hourly/oos_hour_system.csv": "b9eaa83ee3e8a720f3cb5afd5d54da050c2d3ef45c434efe74f8ba8b976b63c6",
}
BASE = np.array([300., 200., 120., 150.])
TOL = 1e-7
HOST_TOL = 1e-5


def io_path(path: Path) -> str:
    value = str(path.resolve())
    return "\\\\?\\" + value if os.name == "nt" and not value.startswith("\\\\?\\") else value


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with open(io_path(path), "rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def save_csv(frame: pd.DataFrame, path: Path) -> None:
    frame.to_csv(io_path(path), index=False, encoding="utf-8-sig", float_format="%.12g")


def dotted(node: ast.AST) -> str:
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        prefix = dotted(node.value)
        return f"{prefix}.{node.attr}" if prefix else node.attr
    return ""


def forbidden_calls(path: Path) -> list[str]:
    tree = ast.parse(path.read_text(encoding="utf-8"))
    found = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            found.extend(a.name for a in node.names if a.name in {"random", "gurobipy", "cvxpy", "pulp"} or a.name.startswith("numpy.random"))
        elif isinstance(node, ast.ImportFrom):
            module = node.module or ""
            if module in {"random", "gurobipy", "cvxpy", "pulp", "scipy.optimize"} or module.startswith("numpy.random"):
                found.append(module)
        elif isinstance(node, ast.Call):
            name = dotted(node.func)
            if name.startswith(("np.random", "numpy.random", "scipy.optimize", "gurobipy")):
                found.append(name)
    return sorted(set(found))


def main() -> None:
    event_file = OUT / "03_grid_aware_recoverability/s4_125_grid_aware_recovery_by_event.csv"
    hourly_file = OUT / "02_effective_pmax/s4_125_hourly_effective_pmax.csv"
    checkpoint_file = OUT / "03_grid_aware_recoverability/s4_125_grid_aware_summary_by_checkpoint.csv"
    failure_file = OUT / "03_grid_aware_recoverability/s4_125_grid_aware_summary_by_failure_type.csv"
    tail_file = OUT / "06_tail_analysis/s4_125_grid_aware_tail_retention.csv"
    severity_file = OUT / "04_voltage_clipping_severity/s4_voltage_clipping_severity.csv"
    bus_file = OUT / "05_bus18_mechanism/bus18_recovery_loss_summary.csv"
    status_file = OUT / "07_workflow_gate/final_status.csv"
    required = [event_file, hourly_file, checkpoint_file, failure_file, tail_file, severity_file, bus_file, status_file]
    if not all(os.path.isfile(io_path(path)) for path in required):
        raise RuntimeError("Missing G2 output before independent QA")

    physical = pd.read_csv(PHYS / "02_counterfactual_recoverability/pmax_candidate_recoverability_by_path.csv")
    physical_base = pd.read_csv(PHYS / "01_baseline_reproduction/pmax_recoverability_baseline_reproduction.csv")
    grid_detail = pd.read_csv(GRID / "05_critical_window/critical_window_grid_hosting.csv")
    grid_profiles = pd.read_csv(GRID / "03_s4_125/s4_125_hourly_hosting.csv")
    events = pd.read_csv(io_path(event_file))
    hourly = pd.read_csv(io_path(hourly_file))
    checkpoint = pd.read_csv(io_path(checkpoint_file))
    failure = pd.read_csv(io_path(failure_file))
    tail = pd.read_csv(io_path(tail_file))
    severity = pd.read_csv(io_path(severity_file))
    bus = pd.read_csv(io_path(bus_file))
    status = pd.read_csv(io_path(status_file)).set_index("status").value
    formal = loadmat(io_path(FORMAL), simplify_cells=True)["NearStageInput"]["HydrogenDevice"]
    k_h2 = float(formal["k_H2_kg_per_kWh"])

    checks = []
    def check(name, observed, expected, passed, source):
        checks.append({"check": name, "observed": observed, "expected": expected, "source": source, "pass": bool(passed)})

    for path, expected_hash in EXPECTED_RAW.items():
        observed = sha256(path)
        check(f"raw_hash_{path.name}", observed, expected_hash, observed == expected_hash, "raw bytes")
    check("formal_input_hash", sha256(FORMAL), "536b2586...", sha256(FORMAL) == "536b25868e6d7cc812a331c0d3e0ffbd5f6958e6883bd39bcae3901c372abf24", "formal MAT")
    check("formal_k_h2", k_h2, .0195, abs(k_h2-.0195) <= TOL, "formal MAT")
    check("formal_base_pmax", np.asarray(formal["el_cap_kw"]).tolist(), BASE.tolist(), np.array_equal(np.asarray(formal["el_cap_kw"],dtype=float), BASE), "formal MAT")
    check("formal_tank_caps", np.asarray(formal["tank_cap_kg"]).tolist(), [300,200,100,150], np.array_equal(np.asarray(formal["tank_cap_kg"]),[300,200,100,150]), "formal MAT")

    expected_base = {-16:70, -8:156, -4:167}
    for hour, count in expected_base.items():
        observed = int(physical_base.loc[physical_base.relative_hour == hour, "recomputed_unrecoverable_count"].iloc[0])
        check(f"base_{hour}h", observed, count, observed == count, "Stage89Q physical baseline")
    recovered = physical[(physical.candidate == "S4_125") & physical.recovered_relative_to_base]
    for hour, count in [(-16,31),(-8,9),(-4,8)]:
        observed = int((recovered.relative_hour == hour).sum())
        check(f"physical_recovered_{hour}h", observed, count, observed == count, "Stage89Q physical events")
    check("physical_event_exact_identity", set(zip(events.path_id,events.checkpoint_relative_hour)), set(zip(recovered.path_id,recovered.relative_hour)), set(zip(events.path_id,events.checkpoint_relative_hour)) == set(zip(recovered.path_id,recovered.relative_hour)), "event keys")
    check("pure_location_zero", int((events.failure_type == "pure_location").sum()), 0, not (events.failure_type == "pure_location").any(), "event output")

    prior = grid_detail[(grid_detail.subset == "S4_125_PHYSICALLY_RECOVERED") & (grid_detail.candidate == "S4_125")]
    check("grid_prior_rows", len(prior), 704, len(prior) == 704, "Stage89Q-G critical detail")
    check("hourly_key_identity", set(zip(hourly.path_id,hourly.relative_hour)), set(zip(prior.path_id,prior.relative_hour)), set(zip(hourly.path_id,hourly.relative_hour)) == set(zip(prior.path_id,prior.relative_hour)), "hour keys")
    check("each_path_16_real_hours", hourly.groupby("path_id").size().min(), 16, (hourly.groupby("path_id").size()==16).all(), "G2 hourly")
    check("no_padded_hours", [hourly.relative_hour.min(),hourly.relative_hour.max()], [-16,-1], hourly.relative_hour.between(-16,-1).all(), "G2 hourly")
    profile = grid_profiles.set_index("profile_id")
    merged = hourly.merge(profile[["realized_pel4_kw","max_additional_site4_hosting_kw","max_new_pel4_kw"]], left_on="profile_id",right_index=True,suffixes=("","_prior"),validate="many_to_one")
    recomputed_p4 = np.minimum(187.5, merged.realized_pel4_kw_prior + merged.max_additional_site4_hosting_kw)
    check("effective_pmax_reconstruction", np.max(np.abs(recomputed_p4-merged.p4_effective_max_kw)), "<=1e-5", np.allclose(recomputed_p4,merged.p4_effective_max_kw,atol=HOST_TOL), "Stage89Q-G profiles")
    check("profile_max_new_identity", np.max(np.abs(merged.max_new_pel4_kw-merged.p4_effective_max_kw)), "<=1e-5", np.allclose(merged.max_new_pel4_kw,merged.p4_effective_max_kw,atol=HOST_TOL), "Stage89Q-G profiles")
    check("base_increment_conversion", np.max(np.abs(merged.effective_increment_above_base_kw-(merged.p4_effective_max_kw-150))), 0, np.allclose(merged.effective_increment_above_base_kw,merged.p4_effective_max_kw-150,atol=TOL), "independent conversion")
    check("full_ratio", hourly.full_candidate_pmax_hostable.mean(), 0.813920454545, abs(hourly.full_candidate_pmax_hostable.mean()-.813920454545)<=1e-12, "G2 hourly")
    check("voltage_ratio", hourly.voltage_limited_flag.astype(bool).mean(), 0.186079545455, abs(hourly.voltage_limited_flag.astype(bool).mean()-.186079545455)<=1e-12, "G2 hourly")
    check("branch_limited_zero", hourly.branch_limited_flag.astype(bool).sum(), 0, not hourly.branch_limited_flag.astype(bool).any(), "G2 hourly")
    check("substation_limited_zero", hourly.substation_limited_flag.astype(bool).sum(), 0, not hourly.substation_limited_flag.astype(bool).any(), "G2 hourly")

    formula_ok = True
    evaluator_ok = True
    cumulative_ok = True
    for row in events.itertuples(index=False):
        h = hourly[(hourly.path_id == row.path_id) & (hourly.relative_hour >= row.checkpoint_relative_hour)]
        base_margin = row.current_inventory_kg + BASE.sum()*k_h2*row.expected_remaining_hour_count - row.target_total_kg
        req = max(0., -TOL-base_margin)
        grid_extra = k_h2*(h.p4_effective_max_kw.sum()-150*len(h))
        grid_margin = base_margin + grid_extra
        formula_ok &= abs(req-row.required_extra_H2_kg)<=1e-8 and abs(grid_extra-row.grid_hostable_extra_H2_kg)<=1e-8
        evaluator_ok &= ((grid_margin>=-TOL) == (row.grid_aware_recovery_supported=="YES"))
        cumulative_ok &= ((grid_extra+1e-6>=req) == (row.cumulative_kg_cross_check_supported=="YES"))
    check("required_and_grid_extra_formula", formula_ok, True, formula_ok, "independent event recomposition")
    check("hourly_evaluator_classification", evaluator_ok, True, evaluator_ok, "independent event recomposition")
    check("cumulative_kg_cross_check", cumulative_ok, True, cumulative_ok, "independent event recomposition")
    check("all_events_identifiable", events.grid_aware_identifiable.eq("YES").sum(), len(events), events.grid_aware_identifiable.eq("YES").all(), "G2 events")
    check("required_alpha_bounds", [events.required_alpha.min(),events.required_alpha.max()], "[0,1]", events.required_alpha.between(-TOL,1+TOL).all(), "G2 events")
    check("event_classification_complete", events.classification.isin(["FULL_INCREMENT_HOSTABLE_AND_SUPPORTED","PARTIALLY_CLIPPED_BUT_STILL_SUPPORTED","GRID_CLIPPING_REMOVES_RECOVERY_SUPPORT","NOT_IDENTIFIABLE"]).sum(), len(events), events.classification.notna().all(), "G2 events")

    for row in checkpoint.itertuples(index=False):
        group=events[events.checkpoint_relative_hour==row.checkpoint_relative_hour]
        check(f"checkpoint_summary_{row.checkpoint_relative_hour}", [row.hydrogen_side_recovered,row.grid_aware_supported,row.grid_clipping_removed], [len(group),group.grid_aware_recovery_supported.eq('YES').sum(),group.classification.eq('GRID_CLIPPING_REMOVES_RECOVERY_SUPPORT').sum()], row.hydrogen_side_recovered==len(group) and row.grid_aware_supported==group.grid_aware_recovery_supported.eq('YES').sum() and row.grid_clipping_removed==group.classification.eq('GRID_CLIPPING_REMOVES_RECOVERY_SUPPORT').sum(), "event aggregation")
    check("failure_summary_rows", set(failure.failure_type), {"pure_quantity","pure_location","mixed"}, set(failure.failure_type)=={"pure_quantity","pure_location","mixed"}, "failure summary")
    check("tail_definitions_preserved", set(tail.tail_group), {"normal95","difficult4","extreme1"}, set(tail.tail_group)=={"normal95","difficult4","extreme1"}, "Stage89Q tail labels")
    normal=tail[tail.tail_group=="normal95"].iloc[0]
    check("normal95_zero_row", [normal.hydrogen_side_recovered,normal.grid_aware_supported], [0,0], normal.hydrogen_side_recovered==normal.grid_aware_supported==0, "tail summary")
    clipped=hourly[~hourly.full_candidate_pmax_hostable]
    sev=severity.set_index(["section","metric"]).value
    check("clipping_count", int(sev[("coverage","full_increment_nonhostable_hours")]), len(clipped), int(sev[("coverage","full_increment_nonhostable_hours")])==len(clipped), "hourly aggregation")
    check("clipping_missing_mean", float(sev[("distribution","mean")]), clipped.missing_candidate_headroom_kw.mean(), abs(float(sev[("distribution","mean")])-clipped.missing_candidate_headroom_kw.mean())<=1e-9, "hourly aggregation")
    supported_clipped_keys=set()
    for row in events[events.grid_aware_recovery_supported=="YES"].itertuples(index=False):
        window=clipped[(clipped.path_id==row.path_id)&(clipped.relative_hour>=row.checkpoint_relative_hour)]
        supported_clipped_keys.update(zip(window.path_id,window.relative_hour))
    check("clipped_hours_inside_supported_windows", int(sev[("coverage","unique_clipped_path_hours_in_supported_event_windows")]), len(supported_clipped_keys), int(sev[("coverage","unique_clipped_path_hours_in_supported_event_windows")])==len(supported_clipped_keys)==95, "independent event-hour join")
    check("partially_clipped_supported_events", int(sev[("coverage","partially_clipped_but_still_supported_events")]), int(events.classification.eq("PARTIALLY_CLIPPED_BUT_STILL_SUPPORTED").sum()), int(sev[("coverage","partially_clipped_but_still_supported_events")])==int(events.classification.eq("PARTIALLY_CLIPPED_BUT_STILL_SUPPORTED").sum())==26, "independent event aggregation")
    check("bus18_clipped_hours", int((clipped.critical_bus==18).sum()), len(clipped), (clipped.critical_bus==18).all(), "G2 hourly")
    check("bus18_lost_event_rows", len(bus), int(events.classification.eq("GRID_CLIPPING_REMOVES_RECOVERY_SUPPORT").sum()), len(bus)==int(events.classification.eq("GRID_CLIPPING_REMOVES_RECOVERY_SUPPORT").sum())==9, "bus18 mechanism")
    check("bus18_lost_event_identity", set(bus.path_id.astype(int)), set(events.loc[events.classification=="GRID_CLIPPING_REMOVES_RECOVERY_SUPPORT","path_id"].astype(int)), set(bus.path_id.astype(int))==set(events.loc[events.classification=="GRID_CLIPPING_REMOVES_RECOVERY_SUPPORT","path_id"].astype(int)), "bus18 mechanism")
    check("bus18_voltage_fields", [bus.minimum_bus18_voltage_pu.min(),bus.voltage_shortfall_from_lower_bound_pu.max()], "V18>=0.9 and shortfall=0", bus.minimum_bus18_voltage_pu.min()>=.90-TOL and bus.voltage_shortfall_from_lower_bound_pu.max()<=TOL, "bus18 mechanism")
    check("final_status_retention_present", status["S4_125_GRID_AWARE_RECOVERY_RETENTION"], "enumerated", status["S4_125_GRID_AWARE_RECOVERY_RETENTION"] in {"STRONG","MODERATE","WEAK","NONE","NOT_IDENTIFIABLE"}, "final status")
    check("recommendation_enumerated", status["RECOMMEND_FRESH_S4_125_ZERO_CUT_SMOKE"], "YES/NO/NEEDS_MORE_GRID_DIAGNOSTIC", status["RECOMMEND_FRESH_S4_125_ZERO_CUT_SMOKE"] in {"YES","NO","NEEDS_MORE_GRID_DIAGNOSTIC"}, "final status")
    check("no_forbidden_solver_or_random_import", forbidden_calls(MAIN), [], forbidden_calls(MAIN)==[], "main analyzer AST")
    check("figure_count", len(list(FIG.glob("[0-9][0-9]_*.png"))), 12, len(list(FIG.glob("[0-9][0-9]_*.png")))==12, "figure directory")
    check("contact_sheet_present", (FIG/"contact_sheet.png").is_file(), True, (FIG/"contact_sheet.png").is_file(), "figure directory")
    allowed={".csv",".md",".png"}
    artifacts=[p for base in [OUT,FIG] for p in base.rglob("*") if p.is_file()]
    check("lightweight_extensions_only", sorted({p.suffix.lower() for p in artifacts}), sorted(allowed), all(p.suffix.lower() in allowed for p in artifacts), "accepted output tree")

    frame=pd.DataFrame(checks)
    save_csv(frame,OUT/"09_qa/independent_qa.csv")
    if not frame["pass"].all():
        failed=frame[~frame["pass"]]
        raise RuntimeError("Independent QA failed: " + "; ".join(failed.check))
    print(f"Independent QA PASS: {len(frame)}/{len(frame)}",flush=True)


if __name__ == "__main__":
    main()
