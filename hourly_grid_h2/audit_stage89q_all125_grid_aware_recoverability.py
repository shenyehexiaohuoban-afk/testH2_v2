#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Independent source recomposition audit for Stage-89Q-G3."""

from __future__ import annotations

import ast
import hashlib
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
S4 = DEEP / "19_s4_grid_aware_recoverability"
OUT = DEEP / "20_all125_grid_aware_recoverability"
FIG = RUN / "06_figures/14_all125_grid_aware_recoverability"
FORMAL = ROOT / "data/yuanqi/near_stage_msp_input.mat"
MAIN = ROOT / "hourly_grid_h2/analyze_stage89q_all125_grid_aware_recoverability.py"
BASE = np.array([300., 200., 120., 150.])
CANDIDATE = np.array([375., 250., 150., 187.5])
INCREMENTS = CANDIDATE - BASE
TOL = 1e-7
HOST_TOL = 1e-5

EXPECTED_RAW = {
    RAW / "path_summary/oos_path_summary.csv": "99ec55faba4e60e88b25d757deb1a8146515faf666d52979fe69c64362047502",
    RAW / "path_summary/oos_stage_summary.csv": "969c373a9a2ff1b271cde6fda95a6fe8e64b10362518fe4b807c0dc86437c15d",
    RAW / "path_summary/oos_stage_site_summary.csv": "eab41bdf5d58fc971bc65af8c5745de3bd08cc25a0a4d44cc386aeba3f99c89e",
    RAW / "hourly_site/oos_hour_site.csv": "af3b3d5c4aa69e6d29b35a88008b4d82360c4b8391fc783141078f7ad68b0cda",
    RAW / "grid_hourly/oos_hour_system.csv": "b9eaa83ee3e8a720f3cb5afd5d54da050c2d3ef45c434efe74f8ba8b976b63c6",
}


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


def forbidden_capabilities(path: Path) -> list[str]:
    tree = ast.parse(path.read_text(encoding="utf-8"))
    found = []
    for node in ast.walk(tree):
        if isinstance(node, (ast.Import, ast.ImportFrom)):
            names = [x.name for x in node.names]
            module = getattr(node, "module", "") or ""
            for name in names + [module]:
                if name in {"random", "gurobipy", "cvxpy", "pulp"} or name.startswith("numpy.random"):
                    found.append(name)
        elif isinstance(node, ast.Call):
            name = dotted(node.func)
            if name.startswith(("np.random", "numpy.random", "gurobipy")):
                found.append(name)
    return sorted(set(found))


def main() -> None:
    files = {
        "events": OUT / "03_grid_aware_recoverability/all125_grid_aware_recovery_by_event.csv",
        "hourly": OUT / "02_joint_effective_capacity/all125_site_resolved_joint_hourly.csv",
        "checkpoint": OUT / "03_grid_aware_recoverability/all125_grid_aware_summary_by_checkpoint.csv",
        "failure": OUT / "03_grid_aware_recoverability/all125_grid_aware_summary_by_failure_type.csv",
        "ablation": OUT / "03_grid_aware_recoverability/all125_site_ablation_by_event.csv",
        "site": OUT / "03_grid_aware_recoverability/all125_site_contribution_summary.csv",
        "tail": OUT / "06_tail_analysis/all125_grid_aware_tail_retention.csv",
        "bus": OUT / "04_bus18_site3/site3_bus18_recovery_loss.csv",
        "comparison": OUT / "05_candidate_comparison/s4_vs_all125_grid_aware_comparison.csv",
        "status": OUT / "07_workflow_gate/final_status.csv",
    }
    if not all(os.path.isfile(io_path(path)) for path in files.values()):
        raise RuntimeError("Missing G3 output before independent audit")
    out = {key: pd.read_csv(io_path(path)) for key, path in files.items()}
    physical = pd.read_csv(PHYS / "02_counterfactual_recoverability/pmax_candidate_recoverability_by_path.csv")
    physical_base = pd.read_csv(PHYS / "01_baseline_reproduction/pmax_recoverability_baseline_reproduction.csv")
    prior_grid = pd.read_csv(GRID / "05_critical_window/critical_window_grid_hosting.csv")
    saved_joint = pd.read_csv(GRID / "04_all_125/all_125_joint_hosting.csv").set_index("profile_id")
    grid_summary = pd.read_csv(GRID / "04_all_125/all_125_summary.csv").set_index("metric").value.astype(float)
    s4_events = pd.read_csv(S4 / "03_grid_aware_recoverability/s4_125_grid_aware_recovery_by_event.csv")
    formal = loadmat(io_path(FORMAL), simplify_cells=True)["NearStageInput"]["HydrogenDevice"]
    k_h2 = float(formal["k_H2_kg_per_kWh"])
    events, hourly, ablation = out["events"], out["hourly"], out["ablation"]
    checks = []

    def check(name, observed, expected, passed, source):
        checks.append({"check": name, "observed": observed, "expected": expected, "source": source, "pass": bool(passed)})

    for path, expected in EXPECTED_RAW.items():
        observed = sha256(path)
        check(f"raw_hash_{path.name}", observed, expected, observed == expected, "raw bytes")
    check("formal_hash", sha256(FORMAL), "536b2586...", sha256(FORMAL) == "536b25868e6d7cc812a331c0d3e0ffbd5f6958e6883bd39bcae3901c372abf24", "formal MAT")
    check("formal_k_h2", k_h2, .0195, abs(k_h2-.0195) <= TOL, "formal MAT")
    check("formal_base_pmax", np.asarray(formal["el_cap_kw"]).tolist(), BASE.tolist(), np.array_equal(np.asarray(formal["el_cap_kw"],dtype=float),BASE), "formal MAT")
    check("formal_tank_caps", np.asarray(formal["tank_cap_kg"]).tolist(), [300,200,100,150], np.array_equal(np.asarray(formal["tank_cap_kg"]),[300,200,100,150]), "formal MAT")
    for cut, count in [(-16,70),(-8,156),(-4,167)]:
        observed = int(physical_base.loc[physical_base.relative_hour==cut,"recomputed_unrecoverable_count"].iloc[0])
        check(f"base_{cut}h", observed, count, observed == count, "physical baseline")
    recovered = physical[(physical.candidate=="ALL_125") & physical.recovered_relative_to_base]
    for cut, count in [(-16,52),(-8,46),(-4,20)]:
        observed = int((recovered.relative_hour==cut).sum())
        check(f"ALL_recovered_{cut}h", observed, count, observed == count, "physical event source")
    for cut, count in [(-16,18),(-8,110),(-4,147)]:
        observed = int(((physical.candidate=="ALL_125")&(physical.relative_hour==cut)&physical.PHYSICALLY_UNRECOVERABLE).sum())
        check(f"ALL_unrecoverable_{cut}h", observed, count, observed == count, "physical event source")
    check("event_exact_identity", set(zip(events.path_id,events.checkpoint_relative_hour)), set(zip(recovered.path_id,recovered.relative_hour)), set(zip(events.path_id,events.checkpoint_relative_hour))==set(zip(recovered.path_id,recovered.relative_hour)), "event keys")
    check("unique_recovered_paths", events.path_id.nunique(), 99, events.path_id.nunique()==99, "event output")
    check("pure_location_zero", int((events.failure_type=="pure_location").sum()), 0, not (events.failure_type=="pure_location").any(), "event output")
    prior = prior_grid[(prior_grid.subset=="ALL125_PHYSICALLY_RECOVERED")&(prior_grid.candidate=="ALL_125")]
    check("prior_grid_rows", len(prior), 1584, len(prior)==1584, "Stage89Q-G")
    check("hourly_key_identity", set(zip(hourly.path_id,hourly.relative_hour)), set(zip(prior.path_id,prior.relative_hour)), set(zip(hourly.path_id,hourly.relative_hour))==set(zip(prior.path_id,prior.relative_hour)), "path-hour keys")
    check("each_path_16_real_hours", hourly.groupby("path_id").size().min(), 16, (hourly.groupby("path_id").size()==16).all(), "G3 hourly")
    check("no_padded_hours", [hourly.relative_hour.min(),hourly.relative_hour.max()], [-16,-1], hourly.relative_hour.between(-16,-1).all(), "G3 hourly")
    check("G_joint_mean_hosting",grid_summary["joint_mean_hosting_ratio"],.9630173862776531,abs(grid_summary["joint_mean_hosting_ratio"]-.9630173862776531)<=1e-12,"Stage89Q-G summary")
    check("G_full_stress_ratio",grid_summary["full_candidate_stress_feasible_ratio"],.85345659838818,abs(grid_summary["full_candidate_stress_feasible_ratio"]-.85345659838818)<=1e-12,"Stage89Q-G summary")
    check("G_critical_full_ratio",prior.full_to_candidate_hostable.eq("YES").mean(),.767676767676768,abs(prior.full_to_candidate_hostable.eq("YES").mean()-.767676767676768)<=1e-12,"Stage89Q-G critical")
    check("G_site3_critical_ratio",prior.site3_full_to_candidate_hostable.eq("YES").mean(),.839015151515151,abs(prior.site3_full_to_candidate_hostable.eq("YES").mean()-.839015151515151)<=1e-12,"Stage89Q-G critical")
    check("G_bus18_critical",prior.critical_bus.eq(18).mean(),1.,prior.critical_bus.eq(18).all(),"Stage89Q-G critical")
    check("G_branch_substation_zero",[grid_summary["branch_limited_ratio"],grid_summary["substation_limited_ratio"]],[0.,0.],grid_summary["branch_limited_ratio"]==grid_summary["substation_limited_ratio"]==0,"Stage89Q-G summary")
    bounds_ok = True
    vector_sum_ok = True
    saved_total_ok = True
    for row in hourly.itertuples(index=False):
        pel = np.array([getattr(row,f"site{i}_joint_feasible_pel_kw") for i in range(1,5)])
        realized = np.array([getattr(row,f"site{i}_realized_pel_kw") for i in range(1,5)])
        bounds_ok &= bool(np.all(pel>=realized-TOL) and np.all(pel<=CANDIDATE+TOL))
        vector_sum_ok &= abs(pel.sum()-row.joint_feasible_total_pel_kw)<=TOL
        saved_total_ok &= abs((pel-realized).sum()-saved_joint.loc[row.profile_id,"joint_increment_feasible_kw"])<=HOST_TOL
    check("site_vector_bounds", bounds_ok, True, bounds_ok, "site-resolved LP witness")
    check("site_vector_sum", vector_sum_ok, True, vector_sum_ok, "site-resolved LP witness")
    check("saved_joint_total_identity", saved_total_ok, True, saved_total_ok, "Stage89Q-G total")
    check("joint_feasibility_witness_flag", hourly.site_resolved_joint_feasibility_witness.eq("YES").all(), True, hourly.site_resolved_joint_feasibility_witness.eq("YES").all(), "G3 hourly")
    formula_ok = alpha_ok = evaluator_ok = True
    for row in events.itertuples(index=False):
        window = hourly[(hourly.path_id==row.path_id)&(hourly.relative_hour>=row.checkpoint_relative_hour)]
        n = -row.checkpoint_relative_hour
        base_margin = row.current_inventory_kg + BASE.sum()*k_h2*n - row.target_total_kg
        required = max(0.,-TOL-base_margin)
        alpha = required/(k_h2*n*INCREMENTS.sum())
        grid_margin = row.current_inventory_kg + k_h2*window.joint_feasible_total_pel_kw.sum() - row.target_total_kg
        formula_ok &= abs(required-row.required_extra_H2_kg)<=1e-8 and abs(grid_margin-row.grid_aware_recovery_margin_kg)<=1e-8
        alpha_ok &= abs(alpha-row.alpha_required_uniform)<=1e-8 and -TOL<=alpha<=1+TOL
        evaluator_ok &= ((grid_margin>=-TOL)==(row.grid_aware_recovery_supported=="YES"))
    check("physical_formula_recomposition", formula_ok, True, formula_ok, "independent formula")
    check("uniform_alpha_recomposition", alpha_ok, True, alpha_ok, "independent formula")
    check("grid_evaluator_recomposition", evaluator_ok, True, evaluator_ok, "independent formula")
    ablation_ok = True
    for row in ablation.itertuples(index=False):
        event = events[(events.path_id==row.path_id)&(events.checkpoint_relative_hour==row.checkpoint_relative_hour)].iloc[0]
        n = -row.checkpoint_relative_hour
        base_margin = event.current_inventory_kg + BASE.sum()*k_h2*n - event.target_total_kg
        margin = base_margin + (INCREMENTS.sum()-INCREMENTS[row.site-1])*k_h2*n
        ablation_ok &= abs(margin-row.ablated_physical_margin_kg)<=1e-8
        ablation_ok &= ((margin < -TOL)==(row.increment_necessary=="YES"))
    check("site_ablation_recomposition", ablation_ok, True, ablation_ok, "independent formula")
    check("ablation_rows", len(ablation), 472, len(ablation)==472, "G3 output")
    check("classification_complete", events.classification.isin(["FULL_CANDIDATE_HOSTABLE_AND_SUPPORTED","PARTIALLY_GRID_CLIPPED_BUT_STILL_SUPPORTED","GRID_CLIPPING_REMOVES_RECOVERY_SUPPORT","NOT_IDENTIFIABLE"]).all(), True, True, "G3 events")
    check("identifiable_rate", events.grid_aware_identifiable.eq("YES").mean(), 1., events.grid_aware_identifiable.eq("YES").all(), "G3 events")
    for row in out["checkpoint"].itertuples(index=False):
        group=events[events.checkpoint_relative_hour==row.checkpoint_relative_hour]
        values=[len(group),group.grid_aware_recovery_supported.eq("YES").sum(),group.classification.eq("GRID_CLIPPING_REMOVES_RECOVERY_SUPPORT").sum()]
        expected=[row.hydrogen_side_recovered,row.grid_aware_supported,row.grid_clipping_removed]
        check(f"checkpoint_summary_{row.checkpoint_relative_hour}",values,expected,values==expected,"event aggregation")
    check("failure_rows", set(out["failure"].failure_type), {"pure_quantity","pure_location","mixed"}, set(out["failure"].failure_type)=={"pure_quantity","pure_location","mixed"}, "failure summary")
    check("tail_rows", set(out["tail"].tail_group), {"normal95","difficult4","extreme1"}, set(out["tail"].tail_group)=={"normal95","difficult4","extreme1"}, "tail summary")
    lost=events[events.classification=="GRID_CLIPPING_REMOVES_RECOVERY_SUPPORT"]
    check("bus_loss_row_count",len(out["bus"]),len(lost),len(out["bus"])==len(lost),"bus18 detail")
    check("bus_loss_identity",set(zip(out["bus"].path_id,out["bus"].checkpoint_relative_hour)),set(zip(lost.path_id,lost.checkpoint_relative_hour)),set(zip(out["bus"].path_id,out["bus"].checkpoint_relative_hour))==set(zip(lost.path_id,lost.checkpoint_relative_hour)),"bus18 detail")
    check("branch_limited_zero",hourly.branch_limited_flag.astype(bool).sum(),0,not hourly.branch_limited_flag.astype(bool).any(),"G3 hourly")
    check("substation_limited_zero",hourly.substation_limited_flag.astype(bool).sum(),0,not hourly.substation_limited_flag.astype(bool).any(),"G3 hourly")
    s4row=out["comparison"].set_index("candidate").loc["S4_125"]
    check("S4_event_count_read",s4row.hydrogen_side_recovered_events,len(s4_events),s4row.hydrogen_side_recovered_events==len(s4_events)==48,"S4-G2 output")
    check("S4_retained_read",s4row.grid_aware_retained_events,s4_events.grid_aware_recovery_supported.eq("YES").sum(),s4row.grid_aware_retained_events==s4_events.grid_aware_recovery_supported.eq("YES").sum()==39,"S4-G2 output")
    check("S4_retention_read",s4row.overall_retention_ratio,.8125,abs(s4row.overall_retention_ratio-.8125)<=TOL,"S4-G2 output")
    status=out["status"].set_index("status").value
    check("recommendation_enumerated",status["RECOMMEND_FRESH_ALL_125_ZERO_CUT_SMOKE"],"YES/NO/NEEDS_MORE_GRID_DIAGNOSTIC",status["RECOMMEND_FRESH_ALL_125_ZERO_CUT_SMOKE"] in {"YES","NO","NEEDS_MORE_GRID_DIAGNOSTIC"},"status")
    check("priority_enumerated",status["GRID_AWARE_PILOT_PRIORITY"],"enumerated",status["GRID_AWARE_PILOT_PRIORITY"] in {"S4_125","ALL_125","BOTH","NEITHER","NOT_IDENTIFIABLE"},"status")
    check("independent_headrooms_not_summed",status["INDEPENDENT_SITE_HEADROOMS_SUMMED"],"NO",status["INDEPENDENT_SITE_HEADROOMS_SUMMED"]=="NO","status")
    check("no_forbidden_training_random_capability",forbidden_capabilities(MAIN),[],forbidden_capabilities(MAIN)==[],"main analyzer AST")
    check("figure_count",len(list(FIG.glob("[0-9][0-9]_*.png"))),14,len(list(FIG.glob("[0-9][0-9]_*.png")))==14,"figure directory")
    check("contact_sheet_present",(FIG/"contact_sheet.png").is_file(),True,(FIG/"contact_sheet.png").is_file(),"figure directory")
    artifacts=[p for base in [OUT,FIG] for p in base.rglob("*") if p.is_file()]
    check("lightweight_extensions_only",sorted({p.suffix.lower() for p in artifacts}),[".csv",".md",".png"],all(p.suffix.lower() in {".csv",".md",".png"} for p in artifacts),"accepted trees")
    frame=pd.DataFrame(checks)
    save_csv(frame,OUT/"09_qa/independent_qa.csv")
    if not frame["pass"].all():
        raise RuntimeError("Independent QA failed: " + "; ".join(frame.loc[~frame["pass"],"check"]))
    print(f"Independent QA PASS: {len(frame)}/{len(frame)}",flush=True)


if __name__ == "__main__":
    main()
