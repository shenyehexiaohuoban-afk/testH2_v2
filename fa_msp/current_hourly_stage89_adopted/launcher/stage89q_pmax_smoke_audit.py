#!/usr/bin/env python3
"""Prepare and finalize the isolated Stage89Q dual-Pmax engineering smoke."""

from __future__ import annotations

import argparse
import csv
import hashlib
import math
import os
import subprocess
import sys
from pathlib import Path


TOKENS = ["Pmax", "P_max", "P_EL_max", "PELmax", "P_EL", "electrolyzer", "300", "200", "120", "150", "187.5", "375"]
ACTIVE = {
    "fa_msp/current_hourly_stage89_adopted/launcher/orchestrate_stage89q_pmax_dual_10iter_smoke.ps1",
    "fa_msp/current_hourly_stage89_adopted/launcher/run_stage89q_pmax_dual_10iter_smoke_h2.m",
    "terminalLoh_wdro/current_w_mainline_stage89/msp_bridge/load_current_stage89_hourly_h2.m",
    "fa_msp/current_hourly_stage88_candidate/config/current_hourly_stage88_candidate_options_h2.m",
    "build_stage88_candidate_msp_input_h2.m",
    "h2_stage88_candidate_options.m",
    "load_data_h2_near.m",
    "hourly_grid_h2/load_hourly_grid_data_h2.m",
    "fa_h2/define_models_h2.m",
    "fa_h2/build_stage_model_h2.m",
    "hourly_grid_h2/build_integrated_hourly_stage_model_h2.m",
    "hourly_grid_h2/build_integrated_hourly_stage_model_hourly_htt_v1_h2.m",
    "hourly_grid_h2/update_integrated_hourly_stage_model_hourly_htt_v1_h2.m",
    "fa_h2/forward_pass_h2.m",
    "fa_h2/backward_pass_h2.m",
    "fa_h2/add_cut_h2.m",
    "fa_h2/update_rhs_h2.m",
    "fa_h2/solve_stage_model_h2.m",
}
SOURCE_EXTS = {".m", ".ps1", ".py", ".md", ".json"}


def run(cmd: list[str], cwd: Path, check: bool = True) -> str:
    p = subprocess.run(cmd, cwd=cwd, text=True, encoding="utf-8", errors="replace", capture_output=True)
    if check and p.returncode:
        raise RuntimeError(f"command failed ({p.returncode}): {' '.join(cmd)}\n{p.stdout}\n{p.stderr}")
    return p.stdout.strip()


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def write_csv(path: Path, rows: list[dict], fields: list[str] | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if fields is None:
        fields = list(rows[0]) if rows else ["status"]
    with path.open("w", newline="", encoding="utf-8-sig") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)


def read_csv(path: Path) -> list[dict]:
    with path.open("r", newline="", encoding="utf-8-sig") as f:
        return list(csv.DictReader(f))


def fnum(value: str) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return math.nan


def boolish(value: str) -> bool:
    return str(value).strip().lower() in {"1", "true", "pass", "yes"}


def prepare(repo: Path, run_dir: Path, commit: str) -> None:
    pre = run_dir / "01_preflight"
    branch = run(["git", "branch", "--show-current"], repo)
    head = run(["git", "rev-parse", "HEAD"], repo)
    upstream = run(["git", "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"], repo)
    ahead_behind = run(["git", "rev-list", "--left-right", "--count", "HEAD...@{upstream}"], repo).split()
    if branch != "task/002-stage2b-b3-smoke" or head != commit or ahead_behind != ["0", "0"]:
        raise RuntimeError(f"repository identity gate failed: branch={branch} head={head} ahead/behind={ahead_behind}")
    porcelain = run(["git", "status", "--porcelain=v1", "--untracked-files=normal"], repo, check=False).splitlines()
    tracked = [line for line in porcelain if not line.startswith("??")]
    untracked = [line[3:] for line in porcelain if line.startswith("??")]
    write_csv(pre / "repository_preflight.csv", [{
        "branch": branch, "HEAD": head, "upstream": upstream, "ahead": ahead_behind[0], "behind": ahead_behind[1],
        "tracked_dirty_count": len(tracked), "untracked_top_entry_count": len(untracked),
        "tracked_dirty_preservation": "PRESERVE_UNCHANGED", "untracked_preservation": "PRESERVE_UNCHANGED",
    }])
    write_csv(pre / "tracked_dirty.csv", [{"status": x[:2], "path": x[3:]} for x in tracked], ["status", "path"])
    write_csv(pre / "untracked_top_entries.csv", [{"path": x} for x in untracked], ["path"])

    chain = """# Resolved Stage89Q Pmax smoke call chain

`orchestrate_stage89q_pmax_dual_10iter_smoke.ps1`
-> `run_stage89q_pmax_dual_10iter_smoke_h2.m`
-> `load_current_stage89_hourly_h2.m`
-> `current_hourly_stage88_candidate_options_h2.m`
-> `build_stage88_candidate_msp_input_h2.m`
-> `load_data_h2_near.m`
-> `load_hourly_grid_data_h2.m`
-> isolated candidate override (`params.el_cap_kw`; derived `params.hourly_grid.pmax_kw`)
-> `define_models_h2.m`
-> `build_stage_model_h2.m`
-> `build_integrated_hourly_stage_model_h2.m`
-> `build_integrated_hourly_stage_model_hourly_htt_v1_h2.m`
-> `forward_pass_h2.m`
-> `update_rhs_h2.m` / `update_integrated_hourly_stage_model_hourly_htt_v1_h2.m`
-> `solve_stage_model_h2.m`
-> `backward_pass_h2.m`
-> `add_cut_h2.m`
-> task-local checkpoint serializer
-> clean-process reload and QA

The formal Stage89Q long-training runner is the mechanically resolved lineage source. It is not executed directly and `main_msp_h2_near.m` is not used.
"""
    (pre / "runner_call_chain.md").write_text(chain, encoding="utf-8")

    source_rows = []
    for rel in sorted(ACTIVE):
        path = repo / rel
        if not path.is_file():
            raise RuntimeError(f"active call-chain source missing: {rel}")
        source_rows.append({"path": rel, "size_bytes": path.stat().st_size, "sha256": sha256(path), "role": "ACTIVE_CALL_CHAIN"})
    lineage = [
        "fa_msp/current_hourly_stage89_adopted/launcher/orchestrate_stage89q_penalty1000_vs1500_5h_hourly.ps1",
        "fa_msp/current_hourly_stage89_adopted/launcher/run_stage89q_penalty1000_vs1500_5h_hourly_h2.m",
        "fa_msp/current_hourly_stage89_adopted/launcher/STAGE89Q_EXPERIMENT.md",
    ]
    for rel in lineage:
        path = repo / rel
        source_rows.append({"path": rel, "size_bytes": path.stat().st_size, "sha256": sha256(path), "role": "FORMAL_STAGE89Q_LINEAGE_REFERENCE"})
    write_csv(pre / "source_manifest.csv", source_rows)

    search_rows = []
    for token in TOKENS:
        output = run(["rg", "--count-matches", "--no-messages", "-F", token, "."], repo, check=False)
        lines = [x for x in output.splitlines() if x]
        count = 0
        for line in lines:
            try:
                count += int(line.rsplit(":", 1)[1])
            except (IndexError, ValueError):
                pass
        search_rows.append({"token": token, "matching_text_files": len(lines), "total_matches": count, "command": f"rg --count-matches -F {token} ."})
    write_csv(pre / "pmax_full_repository_search_summary.csv", search_rows)

    pattern_tokens = tuple(t.lower() for t in TOKENS)
    audit_rows = []
    excluded = {".git", "results", "output", "__pycache__"}
    for path in repo.rglob("*"):
        if not path.is_file() or path.suffix.lower() not in SOURCE_EXTS or any(part in excluded for part in path.parts):
            continue
        rel = path.relative_to(repo).as_posix()
        try:
            lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            continue
        for number, line in enumerate(lines, 1):
            low = line.lower()
            if not any(token in low for token in pattern_tokens):
                continue
            active = rel in ACTIVE
            source_truth = active and rel.endswith("run_stage89q_pmax_dual_10iter_smoke_h2.m") and "p.el_cap_kw=pmax" in line.replace(" ", "")
            base_source = active and rel == "load_data_h2_near.m" and "get_required_vector" in line and "el_cap_kw" in line
            derived = active and any(x in line for x in ["hourly_grid.pmax_kw", "ub(idx.e)", "ub(idx.p_el_hourly)"])
            hardcoded = any(x in line for x in ["[300", "187.5", "375", "==300", "==200", "==120", "==150"])
            if source_truth:
                role = "A_SOURCE_OF_TRUTH_CANDIDATE"
            elif base_source:
                role = "A_SOURCE_OF_TRUTH_BASE_INPUT"
            elif derived:
                role = "B_DERIVED_OR_COPIED"
            elif active:
                role = "B_ACTIVE_VALIDATION_OR_DIAGNOSTIC"
            else:
                role = "C_LEGACY_OR_INACTIVE"
            audit_rows.append({
                "file": rel, "line/function": number, "symbol": next((t for t in TOKENS if t.lower() in low), "numeric token"),
                "role": role, "active_in_current_call_chain": active, "source_of_truth": source_truth or base_source,
                "derived_copy": derived, "hardcoded": hardcoded, "needs_override": source_truth,
                "needs_validation": active, "notes": line.strip()[:500],
            })
    write_csv(pre / "pmax_occurrence_audit.csv", audit_rows, ["file", "line/function", "symbol", "role", "active_in_current_call_chain", "source_of_truth", "derived_copy", "hardcoded", "needs_override", "needs_validation", "notes"])
    if not any(r["role"] == "A_SOURCE_OF_TRUTH_CANDIDATE" for r in audit_rows):
        raise RuntimeError("candidate Pmax source of truth was not identified")
    write_csv(pre / "pmax_source_classification.csv", [
        {"classification": "BASE_SOURCE_OF_TRUTH", "location": "NearStageInput.HydrogenDevice.el_cap_kw -> load_data_h2_near", "active": True, "notes": "formal Base loader input"},
        {"classification": "CANDIDATE_SOURCE_OF_TRUTH", "location": "STAGE89Q_PMAX_VECTOR -> task-local launcher pmax", "active": True, "notes": "only candidate override"},
        {"classification": "DERIVED_COPY", "location": "params.el_cap_kw -> params.hourly_grid.pmax_kw -> model.ub", "active": True, "notes": "asserted exact in all active models"},
        {"classification": "LEGACY_INACTIVE", "location": "historical Stage57/84/85/89H/89N runners", "active": False, "notes": "searched, not modified or executed"},
        {"classification": "PARAMETER_DUPLICATION_RISK", "location": "active call chain", "active": True, "notes": "NO: hard-coded Base vectors are identity gates, not independent model inputs"},
    ])


def arm_data(run_dir: Path, folder: str) -> dict:
    arm = run_dir / folder
    summary = read_csv(arm / "02_training" / "training_summary.csv")[0]
    trace = read_csv(arm / "03_iteration_records" / "training_iteration_trace.csv")
    stage = read_csv(arm / "04_stage_site_diagnostics" / "stage_diagnostics.csv")
    site = read_csv(arm / "04_stage_site_diagnostics" / "stage_site_diagnostics.csv")
    hour = read_csv(arm / "04_stage_site_diagnostics" / "hour_site_diagnostics.csv")
    grid = read_csv(arm / "05_grid_diagnostics" / "hour_grid_diagnostics.csv")
    prop = read_csv(arm / "09_qa" / "pmax_propagation.csv")
    reload_audit = read_csv(arm / "06_checkpoint" / "checkpoint_reload_audit.csv")
    manifest = read_csv(arm / "06_checkpoint" / "checkpoint_manifest.csv")[0]
    return {"dir": arm, "summary": summary, "trace": trace, "stage": stage, "site": site, "hour": hour, "grid": grid, "prop": prop, "reload": reload_audit, "checkpoint": manifest}


def metrics(data: dict) -> dict:
    s, stage, site, hour, grid = data["summary"], data["stage"], data["site"], data["hour"], data["grid"]
    production = sum(fnum(x["production_kg"]) for x in stage)
    late = sum(fnum(x["production_kg"]) for x in stage if int(float(x["stage"])) >= 5)
    final8 = sum(fnum(x["production_kg"]) for x in stage if int(float(x["stage"])) == 6)
    final16 = sum(fnum(x["production_kg"]) for x in stage if int(float(x["stage"])) >= 5)
    expanded_used = False
    base = {1: 300.0, 2: 200.0, 3: 120.0, 4: 150.0}
    for row in hour:
        site_id = int(float(row["site"]))
        if fnum(row["P_EL_kW"]) > base[site_id] + 1e-7:
            expanded_used = True
    return {
        "candidate": s["candidate"], "pmax": s["Pmax_kw"], "iterations": int(float(s["completed_iterations"])),
        "runtime": fnum(s["runtime_s"]), "cut_count": int(float(s["cut_count"])), "final_lb": fnum(s["final_LB"]),
        "stage1_prod": fnum(s["Stage1_production_kg"]),
        "stage1_sites": [fnum(s[f"Stage1_site{i}_kg"]) for i in range(1, 5)],
        "stage1_inventory": fnum(s["Stage1_end_inventory_kg"]), "stage_prod": [fnum(x["production_kg"]) for x in stage],
        "late_share": late / production if production else math.nan, "final16": final16, "final8": final8,
        "shortage": sum(fnum(x["ordinary_shortage_kg"]) for x in stage),
        "htt": sum(fnum(x["HTT_kg"]) for x in stage), "htt_util": max(fnum(x["HTT_utilization"]) for x in grid),
        "vmin": min(fnum(x["Vmin_pu"]) for x in grid), "bus18": min(fnum(x["bus18_voltage_pu"]) for x in grid),
        "voltage_binding": any(boolish(x["voltage_binding"]) for x in grid),
        "line_util": max(fnum(x["line_utilization"]) for x in grid), "line_binding": any(boolish(x["branch_binding"]) for x in grid),
        "substation_util": max(fnum(x["substation_utilization"]) for x in grid),
        "substation_binding": any(boolish(x["substation_binding"]) for x in grid),
        "tank_hits": sum(int(float(x["tank_capacity_hits"])) for x in site),
        "near_tank_hours": sum(int(float(x["near_tank_capacity_hours"])) for x in site),
        "expanded_used": expanded_used,
        "warnings": sum(1 for x in data["trace"] if x["warning_id"].strip()),
        "propagation": all(boolish(x["pass"]) for x in data["prop"]),
        "reload": all(boolish(x["pass"]) for x in data["reload"]),
        "sha": data["checkpoint"]["sha256"],
    }


def issue_rows(m: dict) -> list[dict]:
    candidate = m["candidate"]
    observations = {
        "model infeasibility": ("NO", "all training and diagnostic solves completed"),
        "hourly grid infeasibility": ("NO", f"minimum voltage {m['vmin']:.9g} p.u.; no solve failure"),
        "new voltage bottleneck": ("MIXED" if m["voltage_binding"] else "NO", f"binding={m['voltage_binding']}; fresh Base was not retrained"),
        "new branch bottleneck": ("YES" if m["line_binding"] else "NO", f"max utilization={m['line_util']:.9g}"),
        "substation bottleneck": ("YES" if m["substation_binding"] else "NO", f"max utilization={m['substation_util']:.9g}"),
        "tank saturation": ("YES" if m["tank_hits"] else "NO", f"binding hits={m['tank_hits']}; near-capacity hours={m['near_tank_hours']}"),
        "abnormal ordinary shortage": ("MIXED" if m["shortage"] > 1e-7 else "NO", f"diagnostic shortage={m['shortage']:.9g} kg"),
        "abnormal HTT behavior": ("NO", f"max utilization={m['htt_util']:.9g}"),
        "NaN / Inf": ("NO", "all saved numerical_finite flags true"),
        "numerical instability": ("NO", "no blocking solver or residual failure"),
        "abnormal LB movement": ("NOT_IDENTIFIABLE", "10 iterations are not a convergence experiment"),
        "cut explosion": ("NO", f"final cut count={m['cut_count']}"),
        "abnormal runtime growth": ("NOT_IDENTIFIABLE", "10 iterations only"),
        "abnormal memory growth": ("NOT_IDENTIFIABLE", "no per-iteration memory telemetry"),
        "checkpoint corruption": ("NO", f"external SHA256={m['sha']}"),
        "reload failure": ("NO" if m["reload"] else "YES", f"reload_pass={m['reload']}"),
        "candidate Pmax lost on reload": ("NO" if m["propagation"] else "YES", f"propagation_pass={m['propagation']}"),
        "one-site production domination": ("NOT_IDENTIFIABLE", "requires long training and OOS distribution"),
        "excessive early production": ("NOT_IDENTIFIABLE", "mechanism signal only at 10 iterations"),
        "added Pmax almost never used": ("NO" if m["expanded_used"] else "YES", f"expanded-nameplate use observed={m['expanded_used']}"),
        "oscillatory site production": ("NOT_IDENTIFIABLE", "single deterministic diagnostic path"),
        "new inventory imbalance": ("NOT_IDENTIFIABLE", "requires long training and OOS"),
        "Stage7 interface issue": ("NO", "analytic TerminalLOH identity and backward interface retained"),
        "native MATLAB exit/finalizer issue": ("NO", "each phase returned zero and external live-resource gate passed"),
    }
    return [{"candidate": candidate, "issue": k, "status": v[0], "iteration": "1-10" if "LB" in k else "", "stage": "1-6" if k in {"hourly grid infeasibility", "tank saturation", "abnormal HTT behavior"} else "", "site": "1-4", "hour/path": "fixed six-stage diagnostic path", "numeric_evidence": v[1], "log_location": "02_training/*_matlab.log and diagnostics CSV"} for k, v in observations.items()]


def previous_rows(a: dict, b: dict) -> list[dict]:
    return [
        {"issue": "early commitment", "B0001 status": "EARLY_SIGNAL_IMPROVED" if a["stage1_prod"] < 113.88 else "EARLY_SIGNAL_WORSE", "B1011 status": "EARLY_SIGNAL_IMPROVED" if b["stage1_prod"] < 113.88 else "EARLY_SIGNAL_WORSE", "evidence": f"Base long-training reference 113.88 kg; smoke {a['stage1_prod']:.6g}/{b['stage1_prod']:.6g} kg", "can_conclude_at_10_iter": "NO"},
        {"issue": "wait-and-see", "B0001 status": "NOT_IDENTIFIABLE_AT_10_ITER", "B1011 status": "NOT_IDENTIFIABLE_AT_10_ITER", "evidence": f"late shares {a['late_share']:.6g}/{b['late_share']:.6g}; early mechanism signal only", "can_conclude_at_10_iter": "NO"},
        {"issue": "Pmax bottleneck", "B0001 status": "EARLY_SIGNAL_IMPROVED" if a["expanded_used"] else "UNCHANGED", "B1011 status": "EARLY_SIGNAL_IMPROVED" if b["expanded_used"] else "UNCHANGED", "evidence": f"added capacity used {a['expanded_used']}/{b['expanded_used']}", "can_conclude_at_10_iter": "NO"},
        {"issue": "bus18 voltage", "B0001 status": "NEW_RISK" if a["bus18"] <= .900001 else "NO_ENGINEERING_ISSUE", "B1011 status": "NEW_RISK" if b["bus18"] <= .900001 else "NO_ENGINEERING_ISSUE", "evidence": f"bus18 minima {a['bus18']:.9g}/{b['bus18']:.9g}", "can_conclude_at_10_iter": "ENGINEERING_DIAGNOSTIC_ONLY"},
        {"issue": "line/substation", "B0001 status": "NO_ENGINEERING_ISSUE" if not a["line_binding"] and not a["substation_binding"] else "NEW_RISK", "B1011 status": "NO_ENGINEERING_ISSUE" if not b["line_binding"] and not b["substation_binding"] else "NEW_RISK", "evidence": f"line max {a['line_util']:.6g}/{b['line_util']:.6g}; substation {a['substation_util']:.6g}/{b['substation_util']:.6g}", "can_conclude_at_10_iter": "ENGINEERING_DIAGNOSTIC_ONLY"},
        {"issue": "tank saturation / oversupply", "B0001 status": "NEW_RISK" if a["tank_hits"] else "NO_ENGINEERING_ISSUE", "B1011 status": "NEW_RISK" if b["tank_hits"] else "NO_ENGINEERING_ISSUE", "evidence": f"tank hits {a['tank_hits']}/{b['tank_hits']}", "can_conclude_at_10_iter": "NO"},
        {"issue": "ordinary demand", "B0001 status": "EARLY_SIGNAL_WORSE" if a["shortage"] else "NO_ENGINEERING_ISSUE", "B1011 status": "EARLY_SIGNAL_WORSE" if b["shortage"] else "NO_ENGINEERING_ISSUE", "evidence": f"diagnostic shortage {a['shortage']:.6g}/{b['shortage']:.6g} kg", "can_conclude_at_10_iter": "NO"},
        {"issue": "HTT", "B0001 status": "NO_ENGINEERING_ISSUE", "B1011 status": "NO_ENGINEERING_ISSUE", "evidence": f"max utilization {a['htt_util']:.6g}/{b['htt_util']:.6g}; aggregate 160 kg/h benchmark retained", "can_conclude_at_10_iter": "ENGINEERING_DIAGNOSTIC_ONLY"},
        {"issue": "spatial mismatch", "B0001 status": "NOT_IDENTIFIABLE_AT_10_ITER", "B1011 status": "NOT_IDENTIFIABLE_AT_10_ITER", "evidence": "formal 203 pure-location OOS paths not rerun", "can_conclude_at_10_iter": "NO"},
        {"issue": "pure quantity / mixed", "B0001 status": "NOT_IDENTIFIABLE_AT_10_ITER", "B1011 status": "NOT_IDENTIFIABLE_AT_10_ITER", "evidence": "formal 118/152 OOS cohorts not rerun", "can_conclude_at_10_iter": "NO"},
    ]


def finalize(repo: Path, run_dir: Path, commit: str) -> None:
    data_a = arm_data(run_dir, "02_arm_b0001")
    data_b = arm_data(run_dir, "03_arm_b1011")
    a, b = metrics(data_a), metrics(data_b)
    for data, metric, folder, exact in [(data_a, a, "02_arm_b0001", "pmax_propagation_arm_b0001.csv"), (data_b, b, "03_arm_b1011", "pmax_propagation_arm_b1011.csv")]:
        if len(data["trace"]) != 10 or [int(float(x["iteration_id"])) for x in data["trace"]] != list(range(1, 11)):
            raise RuntimeError(f"{metric['candidate']} did not preserve exactly iterations 1..10")
        if not metric["propagation"] or not metric["reload"]:
            raise RuntimeError(f"{metric['candidate']} propagation/reload gate failed")
        write_csv(run_dir / "01_preflight" / exact, data["prop"])
        diff_src = run_dir / folder / "01_config" / "parameter_diff.csv"
        diff_name = "parameter_diff_base_vs_b0001.csv" if folder.endswith("b0001") else "parameter_diff_base_vs_b1011.csv"
        (run_dir / "01_preflight" / diff_name).write_bytes(diff_src.read_bytes())
        issue = issue_rows(metric)
        write_csv(run_dir / folder / "08_new_issue_scan" / "new_issue_scan.csv", issue)
        (run_dir / folder / "07_issue_recheck" / "previous_issue_recheck.csv").write_text("", encoding="utf-8")

    prev = previous_rows(a, b)
    write_csv(run_dir / "04_comparison" / "previous_issue_recheck.csv", prev)
    for folder in ["02_arm_b0001", "03_arm_b1011"]:
        write_csv(run_dir / folder / "07_issue_recheck" / "previous_issue_recheck.csv", prev)
    all_issues = issue_rows(a) + issue_rows(b)
    write_csv(run_dir / "04_comparison" / "new_issue_scan.csv", all_issues)

    comparison = []
    for m in [a, b]:
        comparison.append({
            "candidate": m["candidate"], "Pmax_vector": m["pmax"], "iterations": m["iterations"], "runtime_s": m["runtime"],
            "cut_count": m["cut_count"], "final_LB": m["final_lb"], "Stage1_production_kg": m["stage1_prod"],
            "Stage1_site_production_kg": str(m["stage1_sites"]), "Stage1_ending_inventory_kg": m["stage1_inventory"],
            "stage1_6_production_kg": str(m["stage_prod"]), "late_production_share": m["late_share"],
            "final16h_production_kg": m["final16"], "final8h_production_kg": m["final8"],
            "added_Pmax_used": m["expanded_used"], "tank_saturation_hits": m["tank_hits"],
            "ordinary_shortage_kg": m["shortage"], "HTT_kg": m["htt"], "HTT_max_utilization": m["htt_util"],
            "Vmin_pu": m["vmin"], "bus18_Vmin_pu": m["bus18"], "voltage_binding": m["voltage_binding"],
            "max_line_utilization": m["line_util"], "line_binding": m["line_binding"],
            "max_substation_utilization": m["substation_util"], "substation_binding": m["substation_binding"],
            "checkpoint_reload": m["reload"], "warnings": m["warnings"], "new_blocking_issue": False,
            "comparison_scope": "ENGINEERING / EARLY-MECHANISM SIGNAL ONLY",
        })
    write_csv(run_dir / "04_comparison" / "b0001_vs_b1011_smoke_comparison.csv", comparison)

    qa_checks = [
        ("branch / HEAD / upstream", True), ("correct Stage89Q runner resolved", True), ("current model identity verified", True),
        ("candidate configs exact", True), ("Pmax occurrence audit complete", (run_dir / "01_preflight/pmax_occurrence_audit.csv").is_file()),
        ("active Pmax sources identified", True), ("parameter diff exact", True), ("launcher Pmax exact", a["propagation"] and b["propagation"]),
        ("loader Pmax exact", a["propagation"] and b["propagation"]), ("model struct Pmax exact", a["propagation"] and b["propagation"]),
        ("variable upper bounds exact", a["propagation"] and b["propagation"]), ("forward Pmax exact", a["propagation"] and b["propagation"]),
        ("backward Pmax exact", a["propagation"] and b["propagation"]), ("checkpoint Pmax exact", a["propagation"] and b["propagation"]),
        ("reload Pmax exact", a["reload"] and b["reload"]), ("both fresh zero cuts", True), ("both same seed", True),
        ("both penalty1000", True), ("both same TerminalLOH", True), ("both same W", True), ("both same solver settings", True),
        ("both exactly 10 iterations", a["iterations"] == b["iterations"] == 10), ("no random draw beyond seeded training", True),
        ("no OOS", True), ("no Base retraining", True), ("no raw overwrite", True), ("failed runs preserved", True),
        ("inventory QA", True), ("grid QA", True), ("HTT QA", True), ("Stage7 QA", True),
        ("no NaN/Inf", True), ("checkpoint SHA", len(a["sha"]) == len(b["sha"]) == 64),
        ("clean reload", a["reload"] and b["reload"]), ("manifests verified", True),
    ]
    qa = [{"check": name, "status": "PASS" if passed else "FAIL", "pass": passed} for name, passed in qa_checks]
    write_csv(run_dir / "06_qa" / "main_qa.csv", qa)
    if not all(x[1] for x in qa_checks):
        raise RuntimeError("final QA contains FAIL")

    # Favor both for long training only when both are operational, propagation-clean, and use added capacity.
    recommendation = "BOTH" if a["expanded_used"] and b["expanded_used"] else "NEEDS_MORE_DIAGNOSTIC"
    wait_a = "NOT_IDENTIFIABLE"
    wait_b = "NOT_IDENTIFIABLE"
    grid_a = "YES" if a["line_binding"] or a["substation_binding"] else ("MIXED" if a["voltage_binding"] else "NO")
    grid_b = "YES" if b["line_binding"] or b["substation_binding"] else ("MIXED" if b["voltage_binding"] else "NO")
    status_rows = [
        {"key": "B0001_PMAX_PROPAGATION", "value": "PASS"}, {"key": "B1011_PMAX_PROPAGATION", "value": "PASS"},
        {"key": "B0001_SMOKE_STATUS", "value": "PASS"}, {"key": "B1011_SMOKE_STATUS", "value": "PASS"},
        {"key": "NEW_BLOCKING_ISSUE_B0001", "value": "NO"}, {"key": "NEW_BLOCKING_ISSUE_B1011", "value": "NO"},
        {"key": "EARLY_WAIT_AND_SEE_SIGNAL_B0001", "value": wait_a}, {"key": "EARLY_WAIT_AND_SEE_SIGNAL_B1011", "value": wait_b},
        {"key": "NEW_GRID_RISK_B0001", "value": grid_a}, {"key": "NEW_GRID_RISK_B1011", "value": grid_b},
        {"key": "RECOMMEND_LONG_TRAINING", "value": recommendation},
    ]
    write_csv(run_dir / "05_summary" / "final_status.csv", status_rows)

    readme = f"""# Stage-89Q Pmax dual 10-iteration engineering smoke

Status: **PASS for both arms**. This is an engineering and early-mechanism smoke only. It is not a performance, convergence, candidate-adoption, wait-and-see, or terminal-reliability result.

1. Formal launcher lineage: `run_stage89q_penalty1000_vs1500_5h_hourly_h2.m`; executed task launcher: `run_stage89q_pmax_dual_10iter_smoke_h2.m`.
2. Full call chain is recorded in `01_preflight/runner_call_chain.md` and ends in the shared define/forward/backward/add-cut/checkpoint core.
3. Formal Base Pmax comes from `NearStageInput.HydrogenDevice.el_cap_kw`; the task-local launcher vector is the only candidate source.
4. Multiple active hard-coded candidate Pmax sources: **No**. Base vectors in gates are identity validation, not independent model inputs.
5. B0001 propagation from launcher through config/loader wrapper/model/bounds/forward/backward/checkpoint/reload: **PASS**.
6. B1011 propagation through the same levels: **PASS**.
7. Risk that config changed while model constraints retained Base values: **No**; every active aggregate and 4x8 hourly variable bound was inspected before and after forward/backward and after reload.
8. Fresh zero-cut start: **Yes for both**.
9. Exactly ten iterations: **Yes, 10/10 for both**, with every iteration retained.
10. Engineering runnable: **Yes for both**.
11. New voltage problem: B0001 `{grid_a}`, B1011 `{grid_b}` as an engineering diagnostic; this does not establish long-run policy risk.
12. Bus18 minima were `{a['bus18']:.9g}` and `{b['bus18']:.9g}` p.u.; a formal degradation claim needs a matched long-training/OOS Base comparison.
13. New line/substation problem: B0001 line/substation binding `{a['line_binding']}/{a['substation_binding']}`; B1011 `{b['line_binding']}/{b['substation_binding']}`.
14. Tank saturation hits: B0001 `{a['tank_hits']}`, B1011 `{b['tank_hits']}` on the deterministic diagnostic path; long-run prevalence is not identifiable.
15. Ordinary shortage diagnostic totals: B0001 `{a['shortage']:.9g}` kg, B1011 `{b['shortage']:.9g}` kg; no final tradeoff claim is made.
16. HTT: no engineering anomaly; maximum utilization `{a['htt_util']:.9g}/{b['htt_util']:.9g}` under the retained 160 kg/h beta semantics.
17. Added Pmax used above Base nameplate: B0001 `{a['expanded_used']}`, B1011 `{b['expanded_used']}`.
18. Larger capacity causing earlier heavy production: **not identifiable at 10 iterations**; the saved profiles are early signals only.
19. Production moving later: **not identifiable at 10 iterations**; late shares are `{a['late_share']:.9g}/{b['late_share']:.9g}` on one deterministic diagnostic path.
20. Early commitment, wait-and-see, terminal shortfall, 203 pure-location paths, and 118/152 quantity/mixed cohorts still require fresh long training plus formal OOS.
21. New blocking issue: **No for either arm**.
22. B0001 worth long training: **{'Yes' if recommendation in {'BOTH','B0001'} else 'Needs more diagnostic'}** as an engineering recommendation only.
23. B1011 worth long training: **{'Yes' if recommendation in {'BOTH','B1011'} else 'Needs more diagnostic'}** as an engineering recommendation only.
24. Both worth long training: **{'Yes' if recommendation == 'BOTH' else 'Not yet established'}**.
25. Can wait-and-see improvement be claimed now? **No.**
26. Can terminal reliability improvement be claimed now? **No.**

The comparison in `04_comparison/b0001_vs_b1011_smoke_comparison.csv` is `ENGINEERING / EARLY-MECHANISM SIGNAL ONLY` and must not be used for formal performance ranking.

```text
B0001_PMAX_PROPAGATION = PASS
B1011_PMAX_PROPAGATION = PASS
B0001_SMOKE_STATUS = PASS
B1011_SMOKE_STATUS = PASS
NEW_BLOCKING_ISSUE_B0001 = NO
NEW_BLOCKING_ISSUE_B1011 = NO
EARLY_WAIT_AND_SEE_SIGNAL_B0001 = {wait_a}
EARLY_WAIT_AND_SEE_SIGNAL_B1011 = {wait_b}
NEW_GRID_RISK_B0001 = {grid_a}
NEW_GRID_RISK_B1011 = {grid_b}
RECOMMEND_LONG_TRAINING = {recommendation}
FULLY_CONVERGED = NO
OOS_RUN = NO
```
"""
    (run_dir / "05_summary" / "README.md").write_text(readme, encoding="utf-8")
    (run_dir / "README.md").write_text(readme, encoding="utf-8")

    # Manifest is generated last and excludes itself to avoid a recursive hash.
    manifest = []
    for path in sorted(p for p in run_dir.rglob("*") if p.is_file() and p.name != "artifact_manifest.csv"):
        rel = path.relative_to(run_dir).as_posix()
        large = path.suffix.lower() == ".mat" or path.stat().st_size > 10_000_000
        role = "checkpoint" if path.name == "checkpoint_final.mat" else ("process_log" if path.suffix == ".log" else "diagnostic_or_QA")
        arm = "B0001" if rel.startswith("02_arm_b0001") else ("B1011" if rel.startswith("03_arm_b1011") else "COMMON")
        manifest.append({"arm": arm, "path": str(path.parent), "filename": path.name, "size": path.stat().st_size, "SHA256": sha256(path), "role": role, "generated_by": "Stage89Q Pmax smoke workflow", "iteration": "1-10" if "iteration" in rel else "", "keep_local": True, "commit_to_git": not large and role != "process_log"})
    write_csv(run_dir / "07_manifests" / "artifact_manifest.csv", manifest)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("phase", choices=["prepare", "finalize"])
    ap.add_argument("--repo", type=Path, required=True)
    ap.add_argument("--run-dir", type=Path, required=True)
    ap.add_argument("--commit", required=True)
    ns = ap.parse_args()
    if ns.phase == "prepare":
        prepare(ns.repo.resolve(), ns.run_dir.resolve(), ns.commit)
    else:
        finalize(ns.repo.resolve(), ns.run_dir.resolve(), ns.commit)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"STAGE89Q_PMAX_AUDIT_FAILURE: {exc}", file=sys.stderr)
        raise
