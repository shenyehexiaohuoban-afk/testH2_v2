#!/usr/bin/env python3
"""Independent raw-based QA for Stage-89Q-G grid-hosting outputs."""

from __future__ import annotations

import ast
import hashlib
import os
from pathlib import Path

import numpy as np
import pandas as pd
from PIL import Image
from scipy.io import loadmat


ROOT = Path(__file__).resolve().parents[1]
RUN = ROOT / "results/task-002-stage2b-b3-smoke/stage89q-penalty1000-vs1500-long-training/run-003"
RAW = ROOT / "hourly_grid_h2/output/stage89q_penalty1000_vs1500_long_training/run-003/penalty1000"
OUT = RUN / "05_analysis/10_deep_penalty1000/18_pmax_grid_hosting_audit"
FIG = RUN / "06_figures/12_penalty1000_pmax_grid_hosting"
PREVIOUS = RUN / "05_analysis/10_deep_penalty1000/17_pmax_flexibility_audit"
GRID_INPUT = ROOT / "data/yuanqi/near_stage_msp_input.mat"
EXPECTED_RAW = {
    "path_summary/oos_path_summary.csv": "99ec55faba4e60e88b25d757deb1a8146515faf666d52979fe69c64362047502",
    "path_summary/oos_stage_summary.csv": "969c373a9a2ff1b271cde6fda95a6fe8e64b10362518fe4b807c0dc86437c15d",
    "path_summary/oos_stage_site_summary.csv": "eab41bdf5d58fc971bc65af8c5745de3bd08cc25a0a4d44cc386aeba3f99c89e",
    "hourly_site/oos_hour_site.csv": "af3b3d5c4aa69e6d29b35a88008b4d82360c4b8391fc783141078f7ad68b0cda",
    "grid_hourly/oos_hour_system.csv": "b9eaa83ee3e8a720f3cb5afd5d54da050c2d3ef45c434efe74f8ba8b976b63c6",
}
BASE = np.array([300., 200., 120., 150.])
S4 = np.array([300., 200., 120., 187.5])
ALL = np.array([375., 250., 150., 187.5])
TOL = 1e-7


def io_path(path: Path) -> str:
    resolved = str(path.resolve())
    return "\\\\?\\" + resolved if os.name == "nt" and not resolved.startswith("\\\\?\\") else resolved


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with open(io_path(path), "rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def id_set_sha(values) -> str:
    payload = ",".join(str(int(v)) for v in sorted(set(values))).encode("ascii")
    return hashlib.sha256(payload).hexdigest()


def dotted_name(node: ast.AST) -> str:
    if isinstance(node,ast.Name):
        return node.id
    if isinstance(node,ast.Attribute):
        prefix=dotted_name(node.value)
        return f"{prefix}.{node.attr}" if prefix else node.attr
    return ""


def main() -> None:
    rows = []

    def check(name, observed, expected, passed, tolerance="exact"):
        rows.append({"check":name,"observed":observed,"expected":expected,
                     "tolerance":tolerance,"pass":bool(passed)})

    hashes = {name:sha256(RAW/name) for name in EXPECTED_RAW}
    check("accepted_raw_hashes", hashes, EXPECTED_RAW, hashes==EXPECTED_RAW)
    grid = loadmat(io_path(GRID_INPUT), simplify_cells=True)["NearStageInput"]
    formal_pmax = np.asarray(grid["HydrogenDevice"]["el_cap_kw"],float).ravel()
    formal_map = np.asarray(grid["Grid"]["site_node_map"],int).ravel()
    check("formal_Base_Pmax", formal_pmax.tolist(), BASE.tolist(), np.allclose(formal_pmax,BASE,atol=TOL))
    check("candidate_Pmax", f"{S4.tolist()}/{ALL.tolist()}", "S4_125/ALL_125", True)
    check("site_bus_mapping", formal_map.tolist(), [24,14,18,31], formal_map.tolist()==[24,14,18,31])
    check("formal_grid_bounds", f"{grid['Grid']['vmin_pu']}/{grid['Grid']['vmax_pu']}/{grid['Grid']['branch_limit_mva']}",
          "0.9/1.1/6", grid['Grid']['vmin_pu']==.9 and grid['Grid']['vmax_pu']==1.1 and grid['Grid']['branch_limit_mva']==6)

    hour = pd.read_csv(RAW/"hourly_site/oos_hour_site.csv", usecols=["path_id","global_hour","site","P_EL_kW"])
    system = pd.read_csv(RAW/"grid_hourly/oos_hour_system.csv", usecols=["path_id","global_hour"])
    path = pd.read_csv(RAW/"path_summary/oos_path_summary.csv")
    wide = hour.pivot(index=["path_id","global_hour"],columns="site",values="P_EL_kW").reset_index()
    wide.columns=["path_id","global_hour","pel1_kw","pel2_kw","pel3_kw","pel4_kw"]
    unique = wide.drop(columns="path_id").drop_duplicates()
    check("real_hour_counts", f"{len(system)}/{len(hour)}", "285888/1143552", len(system)==285888 and len(hour)==1143552)
    check("no_padded_hours", len(system), int((8*path.operating_stage_count).sum()), len(system)==int((8*path.operating_stage_count).sum()))
    check("raw_unique_electrical_profiles", len(unique), 1244, len(unique)==1244)

    base_qa = pd.read_csv(OUT/"02_base_reproduction/base_grid_QA_reproduction.csv")
    s4 = pd.read_csv(OUT/"03_s4_125/s4_125_hourly_hosting.csv")
    s4sum = pd.read_csv(OUT/"03_s4_125/s4_125_summary.csv")
    site = pd.read_csv(OUT/"04_all_125/all_125_site_headroom.csv")
    joint = pd.read_csv(OUT/"04_all_125/all_125_joint_hosting.csv")
    stress = pd.read_csv(OUT/"04_all_125/all_125_full_candidate_stress.csv")
    allsum = pd.read_csv(OUT/"04_all_125/all_125_summary.csv")
    critical = pd.read_csv(OUT/"05_critical_window/critical_window_grid_hosting.csv")
    critical_sum = pd.read_csv(OUT/"05_critical_window/critical_window_summary.csv")
    identity = pd.read_csv(OUT/"05_critical_window/critical_window_subset_identity.csv").set_index("subset")
    flex = pd.read_csv(OUT/"06_flexibility_vs_grid/pmax_gain_vs_grid_hosting.csv")
    decision = pd.read_csv(OUT/"07_candidate_decision/candidate_grid_hosting_decision.csv")
    status = pd.read_csv(OUT/"07_candidate_decision/final_status.csv").set_index("status").value.to_dict()
    visual = pd.read_csv(OUT/"09_qa/visual_audit.csv")
    manifest = pd.read_csv(OUT/"08_summary/lightweight_manifest.csv")
    readme = (OUT/"08_summary/README.md").read_text(encoding="utf-8")

    check("base_reproduction_all_PASS", int(base_qa["pass"].sum()), len(base_qa), base_qa["pass"].all())
    check("profile_output_counts", f"{len(s4)}/{len(site)}/{len(joint)}/{len(stress)}", "1244/4976/1244/1244",
          len(s4)==1244 and len(site)==4976 and len(joint)==1244 and len(stress)==1244)
    check("profile_weight_coverage", f"{s4.occurrence_count.sum()}/{joint.occurrence_count.sum()}", "285888/285888",
          s4.occurrence_count.sum()==joint.occurrence_count.sum()==285888)
    check("single_site_weight_coverage", site.groupby("site").occurrence_count.sum().to_dict(),
          "285888 each", (site.groupby("site").occurrence_count.sum()==285888).all())
    check("S4_arithmetic", True, True,
          np.allclose(s4.total_increment_needed_to_candidate_kw,187.5-s4.realized_pel4_kw,atol=TOL) and
          np.allclose(s4.current_remaining_base_headroom_kw,150-s4.realized_pel4_kw,atol=TOL))
    check("ALL_site_arithmetic", True, True,
          np.allclose(site.total_increment_needed_to_candidate_kw,site.candidate_pmax_kw-site.realized_pel_kw,atol=TOL))
    check("ALL_joint_arithmetic", True, True,
          np.allclose(joint.joint_increment_requested_from_realized_kw,
                      ALL.sum()-joint[[f"realized_pel{i}_kw" for i in range(1,5)]].sum(axis=1),atol=TOL))
    check("nonnegative_hosting", min(s4.max_additional_site4_hosting_kw.min(),site.max_additional_site_hosting_kw.min(),joint.joint_increment_feasible_kw.min()), ">=-1e-7",
          min(s4.max_additional_site4_hosting_kw.min(),site.max_additional_site_hosting_kw.min(),joint.joint_increment_feasible_kw.min())>=-TOL)
    check("hosted_not_above_requested", True, True,
          (s4.max_additional_site4_hosting_kw<=s4.total_increment_needed_to_candidate_kw+TOL).all() and
          (site.max_additional_site_hosting_kw<=site.total_increment_needed_to_candidate_kw+TOL).all() and
          (joint.joint_increment_feasible_kw<=joint.joint_increment_requested_from_realized_kw+TOL).all())
    check("S4_full_flag_identity", True, True,
          np.array_equal(s4.S4_FULL_INCREMENT_HOSTABLE.eq("YES"),
                         s4.max_additional_site4_hosting_kw+1e-5>=s4.total_increment_needed_to_candidate_kw))
    check("ALL_full_flag_identity", True, True,
          np.array_equal(joint.FULL_CANDIDATE_STRESS_FEASIBLE.eq("YES"),
                         joint.joint_increment_feasible_kw+1e-5>=joint.joint_increment_requested_from_realized_kw))
    check("stress_interpretation_boundary", stress.STRESS_FAIL_POLICY_INTERPRETATION.str.contains("FAIL_ONLY|FULL_SIMULTANEOUS").all(), True,
          stress.STRESS_FAIL_POLICY_INTERPRETATION.str.contains("FAIL_ONLY|FULL_SIMULTANEOUS").all())
    check("voltage_constraints", min(s4.min_voltage_pu.min(),site.min_voltage_pu.min(),joint.min_voltage_pu.min()), ">=0.9-1e-7",
          min(s4.min_voltage_pu.min(),site.min_voltage_pu.min(),joint.min_voltage_pu.min())>=.9-TOL)
    check("octagon_constraints", max(s4.max_octagon_violation_kva.max(),site.max_octagon_violation_kva.max(),joint.max_octagon_violation_kva.max()), "<=1e-7",
          max(s4.max_octagon_violation_kva.max(),site.max_octagon_violation_kva.max(),joint.max_octagon_violation_kva.max())<=TOL)
    check("true_apparent_power_constraints", max(s4.max_true_s_mva.max(),site.max_true_s_mva.max(),joint.max_true_s_mva.max()), "<=6+1e-7",
          max(s4.max_true_s_mva.max(),site.max_true_s_mva.max(),joint.max_true_s_mva.max())<=6+TOL)
    check("balance_residuals", max(s4.max_p_balance_error_kw.max(),site.max_p_balance_error_kw.max(),joint.max_p_balance_error_kw.max()), "<=1e-7",
          max(s4.max_p_balance_error_kw.max(),site.max_p_balance_error_kw.max(),joint.max_p_balance_error_kw.max())<=TOL)

    previous = pd.read_csv(PREVIOUS/"02_counterfactual_recoverability/pmax_candidate_recoverability_by_path.csv")
    def ids(candidate,hours,column):
        return set(previous[(previous.candidate.eq(candidate)) & previous.hours_before_stage7.eq(hours) & previous[column]].path_id.astype(int))
    expected_sets={
        "BASE_UNRECOVERABLE_-16H":ids("B0",16,"PHYSICALLY_UNRECOVERABLE"),
        "BASE_UNRECOVERABLE_-8H":ids("B0",8,"PHYSICALLY_UNRECOVERABLE"),
        "BASE_UNRECOVERABLE_-4H":ids("B0",4,"PHYSICALLY_UNRECOVERABLE"),
        "ALL125_PHYSICALLY_RECOVERED":set(previous[(previous.candidate.eq("ALL_125"))&previous.recovered_relative_to_base].path_id.astype(int)),
        "S4_125_PHYSICALLY_RECOVERED":set(previous[(previous.candidate.eq("S4_125"))&previous.recovered_relative_to_base].path_id.astype(int)),
    }
    identities_ok=all(identity.loc[name,"path_count"]==len(values) and identity.loc[name,"path_id_set_sha256"]==id_set_sha(values) for name,values in expected_sets.items())
    check("critical_subset_raw_identity", identities_ok, True, identities_ok)
    check("critical_real_hours_only", int((critical_sum.real_hour_count<=critical_sum.nominal_window_hour_count).all()), 1,
          (critical_sum.real_hour_count<=critical_sum.nominal_window_hour_count).all())
    check("critical_detail_unique", int(critical.duplicated(["subset","candidate","path_id","global_hour"]).sum()), 0,
          not critical.duplicated(["subset","candidate","path_id","global_hour"]).any())
    recovered_detail=critical[(critical.subset.eq("ALL125_PHYSICALLY_RECOVERED"))&critical.candidate.eq("ALL_125")]
    recovered_summary=critical_sum[(critical_sum.subset.eq("ALL125_PHYSICALLY_RECOVERED"))&critical_sum.candidate.eq("ALL_125")].iloc[0]
    site_critical_ok=all(abs(recovered_detail[f"site{i}_full_to_candidate_hostable"].eq("YES").mean()-recovered_summary[f"site{i}_full_to_candidate_hostable_ratio"])<=TOL for i in range(1,5))
    check("critical_site_ratios_recomputed", site_critical_ok, True, site_critical_ok)

    s4_weight=s4.occurrence_count
    s4_ratio=np.average(s4.S4_FULL_INCREMENT_HOSTABLE.eq("YES"),weights=s4_weight)
    all_ratio=np.average(joint.FULL_CANDIDATE_STRESS_FEASIBLE.eq("YES"),weights=joint.occurrence_count)
    d=decision.set_index("candidate")
    check("decision_all_hour_ratios", f"{s4_ratio}/{all_ratio}", "recomputed", abs(d.loc["S4_125","all_hour_full_hostable_ratio"]-s4_ratio)<=TOL and abs(d.loc["ALL_125","all_hour_full_hostable_ratio"]-all_ratio)<=TOL)
    check("summary_total_hours", f"{s4sum.loc[s4sum.metric.eq('total_checked_hours'),'value'].iloc[0]}/{allsum.loc[allsum.metric.eq('total_checked_hours'),'value'].iloc[0]}", "285888/285888",
          float(s4sum.loc[s4sum.metric.eq('total_checked_hours'),'value'].iloc[0])==285888 and float(allsum.loc[allsum.metric.eq('total_checked_hours'),'value'].iloc[0])==285888)
    previous_summary=pd.read_csv(PREVIOUS/"02_counterfactual_recoverability/pmax_candidate_recoverability_summary.csv")
    flex_ok=True
    for _, row in flex.iterrows():
        p=previous_summary[previous_summary.candidate.eq(row["candidate"])].set_index("hours_before_stage7")
        flex_ok &= row["physical_recovery_gain_-16"]==p.loc[16,"recovered_relative_to_base"]
        flex_ok &= row["physical_recovery_gain_-8"]==p.loc[8,"recovered_relative_to_base"]
        flex_ok &= row["physical_recovery_gain_-4"]==p.loc[4,"recovered_relative_to_base"]
    check("physical_gain_copied_not_scaled", flex_ok, True, flex_ok)
    check("effective_gain_boundary", flex.interpretation_boundary.str.contains("DO_NOT_MULTIPLY").all(), True,
          flex.interpretation_boundary.str.contains("DO_NOT_MULTIPLY").all())
    check("policy_actual_use_status", status.get("POLICY_ACTUAL_USE"), "NOT_AVAILABLE_BEFORE_FRESH_RETRAINING",
          status.get("POLICY_ACTUAL_USE")=="NOT_AVAILABLE_BEFORE_FRESH_RETRAINING")
    check("no_training_OOS_status", f"{status.get('NO_FA_MSP_TRAINING')}/{status.get('NO_OOS_RERUN')}", "YES/YES",
          status.get('NO_FA_MSP_TRAINING')==status.get('NO_OOS_RERUN')=="YES")
    check("README_20_answers", sum(line.startswith("## ") for line in readme.splitlines()), ">=20",
          all(f"## {i}." in readme for i in range(1,21)))
    check("README_required_boundaries", True, True,
          "不一定" in readme and "不能，必须 fresh retraining。" in readme and "不能，必须 fresh retraining + OOS。" in readme)

    scripts=[ROOT/"hourly_grid_h2/analyze_stage89q_pmax_grid_hosting_audit.py",Path(__file__)]
    forbidden=[]
    for script in scripts:
        text=script.read_text(encoding="utf-8")
        tree=ast.parse(text)
        called={getattr(node.func,"id","") for node in ast.walk(tree) if isinstance(node,ast.Call)}
        forbidden += sorted(called & {"train_models_h2","forward_pass_h2","backward_pass_h2","add_cut_h2"})
        for node in ast.walk(tree):
            if isinstance(node,ast.Import):
                forbidden += [alias.name for alias in node.names if alias.name=="random" or alias.name.startswith("numpy.random")]
            elif isinstance(node,ast.ImportFrom):
                module=node.module or ""
                if module=="random" or module.startswith("numpy.random"): forbidden.append(module)
            elif isinstance(node,ast.Call):
                name=dotted_name(node.func)
                if name.startswith("np.random") or name.startswith("numpy.random"): forbidden.append(name)
    check("no_FA_core_or_random_capability", forbidden, [], not forbidden)

    pngs=sorted(p for p in FIG.glob("*.png") if p.name!="contact_sheet.png")
    check("required_figure_count", len(pngs), 12, len(pngs)==12)
    image_ok=[]
    for image_path in pngs:
        with Image.open(io_path(image_path)) as image:
            pixels=np.asarray(image.convert("RGB"),dtype=np.float32)
            image_ok.append(image.width>=700 and image.height>=400 and pixels.std()>3)
    check("figure_dimensions_nonblank", all(image_ok), True, all(image_ok))
    check("manual_visual_QA", visual.manual_visual_status.value_counts().to_dict(), {"PASS":12},
          len(visual)==12 and visual.manual_visual_status.eq("PASS").all())
    manifest_ok=True
    for item in manifest.itertuples():
        artifact=ROOT/item.relative_path
        manifest_ok &= artifact.is_file() and artifact.stat().st_size==int(item.size_bytes) and sha256(artifact)==item.sha256
    check("manifest_hashes", manifest_ok, True, manifest_ok)
    check("accepted_raw_hashes_after", {name:sha256(RAW/name) for name in EXPECTED_RAW}, EXPECTED_RAW,
          {name:sha256(RAW/name) for name in EXPECTED_RAW}==EXPECTED_RAW)

    frame=pd.DataFrame(rows)
    frame.to_csv(io_path(OUT/"09_qa/independent_qa.csv"),index=False,encoding="utf-8-sig")
    if not frame["pass"].all():
        raise RuntimeError(f"Independent QA failed: {frame.loc[~frame['pass'],'check'].tolist()}")
    print(f"Independent Stage89Q-G QA PASS: {len(frame)}/{len(frame)}")


if __name__=="__main__":
    main()
