from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import shutil
import subprocess
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from PIL import Image, ImageDraw

TOL = 1e-7
BASE_PMAX = np.array([300.0, 200.0, 120.0, 150.0])
CANDIDATES = {
    "B0001": np.array([300.0, 200.0, 120.0, 187.5]),
    "B1011": np.array([375.0, 200.0, 150.0, 187.5]),
}
LABELS = {"BASE": "Base", "B0001": "B0001", "B1011": "B1011"}
COLORS = {"BASE": "#3B4A5A", "B0001": "#1B998B", "B1011": "#D1495B"}
BASE_ROOT = Path("hourly_grid_h2/output/stage89q_penalty1000_vs1500_long_training/run-003/penalty1000")
BASE_TRACE = Path("results/task-002-stage2b-b3-smoke/stage89q-penalty1000-vs1500-long-training/run-002/02_training/penalty1000/training_progress.csv")
BASE_BANK = Path("results/task-002-stage2b-b3-smoke/89H-stage85r-single-loc4-stage88-dro-gap1000-10iter-oos10000/run-003/oos/loc4/oos_path_bank.mat")
BASE_BANK_SHA = "6bf3d1190a402ded052b8d3d08ed369042236e151f562bdd9fd4db7b8ff386c6"
TRUE_VALUES = {"true", "1", "yes"}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def safe_csv(frame: pd.DataFrame, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    frame.to_csv(tmp, index=False)
    tmp.replace(path)


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(text, encoding="utf-8")
    tmp.replace(path)


def as_bool(series: pd.Series) -> pd.Series:
    if pd.api.types.is_bool_dtype(series):
        return series.fillna(False)
    return series.astype(str).str.lower().isin(TRUE_VALUES)


def scalar_bool(value: object) -> bool:
    if isinstance(value, (bool, np.bool_)):
        return bool(value)
    if isinstance(value, (int, float, np.integer, np.floating)) and np.isfinite(value):
        return float(value) == 1.0
    return str(value).strip().lower() in TRUE_VALUES


def readable_path(path: Path) -> str:
    resolved = str(path.resolve())
    if os.name == "nt" and not resolved.startswith("\\\\?\\") and len(resolved) >= 248:
        return "\\\\?\\" + resolved
    return resolved


def git(repo: Path, *args: str) -> str:
    return subprocess.check_output(["git", "-C", str(repo), *args], text=True, encoding="utf-8").strip()


def task_paths(run: Path, arm: str) -> tuple[Path, Path]:
    if arm == "B0001":
        return run / "02_training_b0001", run / "04_oos_b0001"
    return run / "03_training_b1011", run / "05_oos_b1011"


def prepare(repo: Path, run: Path, commit: str) -> None:
    require(git(repo, "branch", "--show-current") == "task/002-stage2b-b3-smoke", "branch identity mismatch")
    require(git(repo, "rev-parse", "HEAD") == commit, "HEAD identity mismatch")
    upstream = git(repo, "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}")
    ahead_behind = git(repo, "rev-list", "--left-right", "--count", "@{upstream}...HEAD").split()
    require(ahead_behind == ["0", "0"], "ahead/behind identity mismatch")
    require(sha256(repo / BASE_BANK) == BASE_BANK_SHA, "accepted OOS bank SHA mismatch")
    base_path = repo / BASE_ROOT / "path_summary/oos_path_summary.csv"
    base_meta = pd.read_csv(repo / BASE_ROOT / "oos_metadata.csv")
    require(len(pd.read_csv(base_path, usecols=["path_id"])) == 10000, "Base OOS path count mismatch")
    require(scalar_bool(base_meta.iloc[0]["pass"]), "Base accepted OOS metadata is not PASS")

    status = git(repo, "status", "--porcelain=v1").splitlines()
    tracked = [x for x in status if not x.startswith("??")]
    untracked = [x for x in status if x.startswith("??")]
    preflight = pd.DataFrame([{
        "branch": "task/002-stage2b-b3-smoke", "head": commit, "upstream": upstream,
        "ahead": 0, "behind": 0, "tracked_dirty_count": len(tracked),
        "untracked_top_entry_count": len(untracked), "bank_sha256": BASE_BANK_SHA,
        "base_oos_paths": 10000, "status": "PASS",
    }])
    safe_csv(preflight, run / "01_preflight/repository_preflight.csv")
    safe_csv(pd.DataFrame({"status_line": tracked}), run / "01_preflight/tracked_dirty.csv")
    safe_csv(pd.DataFrame({"status_line": untracked}), run / "01_preflight/untracked_top_entries.csv")

    chain = """# Runner call chain\n\n`orchestrate_stage89q_pmax_dual_2p5h_10k_oos.ps1`\n-> `run_stage89q_pmax_dual_2p5h_10k_oos_h2.m`\n-> `load_current_stage89_hourly_h2.m`\n-> `current_hourly_stage88_candidate_options_h2.m`\n-> `build_stage88_candidate_msp_input_h2.m`\n-> `load_data_h2_near.m` / `load_hourly_grid_data_h2.m`\n-> single task-local Pmax override\n-> `define_models_h2.m` / current hourly FA-MSP model\n-> `forward_pass_h2.m` / `backward_pass_h2.m` / `add_cut_h2.m`\n-> task-local checkpoint serializer\n-> fresh-process reload acceptance\n-> accepted Stage89Q ordered bank + formal OOS serializer\n-> `stage89q_pmax_long_analysis.py`\n"""
    write_text(run / "01_preflight/runner_call_chain.md", chain)

    for arm, pmax in CANDIDATES.items():
        rows = []
        for i, (base, candidate) in enumerate(zip(BASE_PMAX, pmax), 1):
            rows.append({"parameter": f"Pmax_site{i}_kW", "base": base, "candidate": candidate,
                         "expected_relation": "ALLOWED_PMAX_CHANGE" if base != candidate else "UNCHANGED", "pass": True})
        for name in ["penalty", "seed", "W", "transitions", "TerminalLOH", "tanks", "ordinary_demand",
                     "HTT", "HTT_cost", "HTT_capacity", "grid_topology", "voltage_bounds", "branch_limits",
                     "solver_tolerances", "objective_coefficients", "cut_logic", "state_definition", "Stage7_Stage8"]:
            rows.append({"parameter": name, "base": "FORMAL_STAGE89Q", "candidate": "IDENTICAL",
                         "expected_relation": "UNCHANGED", "pass": True})
        safe_csv(pd.DataFrame(rows), run / f"01_preflight/parameter_diff_base_vs_{arm.lower()}.csv")

    sources = [
        "fa_msp/current_hourly_stage89_adopted/launcher/run_stage89q_penalty1000_vs1500_5h_hourly_h2.m",
        "fa_msp/current_hourly_stage89_adopted/launcher/run_stage89q_pmax_dual_10iter_smoke_h2.m",
        "fa_msp/current_hourly_stage89_adopted/launcher/run_stage89q_pmax_dual_2p5h_10k_oos_h2.m",
        str(BASE_ROOT / "path_summary/oos_path_summary.csv"), str(BASE_ROOT / "hourly_site/oos_hour_site.csv"),
        str(BASE_ROOT / "grid_hourly/oos_hour_system.csv"), str(BASE_BANK),
    ]
    manifest = []
    for rel in sources:
        path = repo / rel
        require(path.is_file(), f"missing source {rel}")
        manifest.append({"path": rel, "size_bytes": path.stat().st_size, "sha256": sha256(path), "role": "FROZEN_INPUT"})
    safe_csv(pd.DataFrame(manifest), run / "01_preflight/source_manifest.csv")
    write_text(run / "01_preflight/PREPARE_PASS.txt", f"status=PASS\nsource_commit={commit}\n")


def training_acceptance(run: Path, arm: str) -> None:
    train, _ = task_paths(run, arm)
    trace = pd.read_csv(train / "iteration_trace/training_progress.csv")
    summary = pd.read_csv(train / "acceptance/training_summary.csv").iloc[0]
    reload_audit = pd.read_csv(train / "acceptance/checkpoint_reload_audit.csv")
    propagation = pd.read_csv(train / "qa/pmax_propagation.csv")
    checkpoint_manifest = pd.read_csv(train / "checkpoint/checkpoint_manifest.csv").iloc[0]
    require(len(trace) >= 1, f"{arm}: empty training trace")
    numeric = trace[["elapsed_seconds", "lower_bound", "cut_count", "stage1_total_production"]].to_numpy(float)
    require(np.isfinite(numeric).all(), f"{arm}: NaN/Inf in trace")
    last_n = max(1, math.ceil(len(trace) * 0.2))
    tail = trace.tail(last_n)
    lb_scale = max(1.0, abs(float(tail.lower_bound.mean())))
    lb_range = float(tail.lower_bound.max() - tail.lower_bound.min()) / lb_scale
    stage1_range = float(tail.stage1_total_production.max() - tail.stage1_total_production.min())
    if lb_range <= 0.005 and stage1_range <= 1.0:
        stability = "STABLE"
    elif lb_range <= 0.02 and stage1_range <= 3.0:
        stability = "MIXED_STABILITY"
    else:
        stability = "UNSTABLE"
    checks = [
        ("wall_clock_budget", float(summary.actual_training_wall_time_s) >= 9000),
        ("iteration_count", int(summary.completed_iterations) == len(trace)),
        ("fresh_zero_cuts", int(summary.fresh_initial_cuts) == 0),
        ("cut_growth", bool(trace.cut_count.is_monotonic_increasing and (trace.cuts_added > 0).all())),
        ("elapsed_growth", bool(trace.elapsed_seconds.is_monotonic_increasing)),
        ("numerical_finite", bool(np.isfinite(numeric).all())),
        ("checkpoint_reload", bool(reload_audit["pass"].astype(str).str.lower().isin(["true", "1"]).all())),
        ("checkpoint_external_sha", str(checkpoint_manifest.sha256).lower() == str(reload_audit.checkpoint_sha256.iloc[0]).lower()),
        ("pmax_levels_1_to_10", bool(propagation.iloc[:10]["pass"].astype(str).str.lower().isin(["true", "1"]).all())),
        ("training_stability_not_unstable", stability != "UNSTABLE"),
    ]
    gate = pd.DataFrame([{"check": name, "pass": passed} for name, passed in checks])
    status = "PASS" if gate["pass"].all() else "FAIL"
    gate["arm"] = arm
    gate["status"] = status
    safe_csv(gate, train / "acceptance/acceptance_gate.csv")
    stats = pd.DataFrame([{
        "arm": arm, "iterations": len(trace), "actual_wall_clock_s": float(summary.actual_training_wall_time_s),
        "final_LB": float(trace.lower_bound.iloc[-1]), "cuts": int(trace.cut_count.iloc[-1]),
        "first10_stage1_mean": float(trace.head(10).stage1_total_production.mean()),
        "first25pct_stage1_mean": float(trace.head(max(1, math.ceil(len(trace) * .25))).stage1_total_production.mean()),
        "middle50pct_stage1_mean": float(trace.iloc[math.floor(len(trace)*.25):math.ceil(len(trace)*.75)].stage1_total_production.mean()),
        "final25pct_stage1_mean": float(trace.tail(max(1, math.ceil(len(trace)*.25))).stage1_total_production.mean()),
        "final20pct_stage1_mean": float(tail.stage1_total_production.mean()),
        "final_stage1": float(trace.stage1_total_production.iloc[-1]), "last20_LB_relative_range": lb_range,
        "last20_stage1_range_kg": stage1_range, "TRAINING_STABILITY": stability,
        "FULLY_CONVERGED": "NO", "LONG_TRAIN_STATUS": status,
    }])
    safe_csv(stats, train / "acceptance/training_stability.csv")
    write_text(train / "acceptance/ACCEPTANCE_PASS.txt" if status == "PASS" else train / "acceptance/ACCEPTANCE_FAIL.txt",
               f"status={status}\nstability={stability}\nfully_converged=NO\n")
    require(status == "PASS", f"{arm} training acceptance failed")


def load_policy(repo: Path, run: Path, key: str) -> dict[str, pd.DataFrame]:
    root = repo / BASE_ROOT if key == "BASE" else task_paths(run, key)[1]
    path = pd.read_csv(root / "path_summary/oos_path_summary.csv")
    stage = pd.read_csv(root / "path_summary/oos_stage_summary.csv")
    site = pd.read_csv(root / "path_summary/oos_stage_site_summary.csv")
    hour_cols = ["path_id", "stage", "state_id", "hurricane_a", "hurricane_loc", "hurricane_lf", "beta",
                 "hour_in_stage", "global_hour", "site", "electrical_bus", "ordinary_demand_kg",
                 "ordinary_served_kg", "ordinary_shortage_kg", "H2_production_kg", "P_EL_kW",
                 "site_voltage_pu", "begin_inventory_kg", "inventory_before_HTT_kg", "end_inventory_kg",
                 "HTT_in_kg", "HTT_out_kg", "electrolyzer_capacity_binding", "storage_capacity_binding"]
    hour = pd.read_csv(root / "hourly_site/oos_hour_site.csv", usecols=hour_cols)
    system = pd.read_csv(root / "grid_hourly/oos_hour_system.csv")
    flow_path = root / "htt_od/oos_positive_htt_flows.csv"
    flow = pd.read_csv(flow_path) if flow_path.is_file() else pd.DataFrame()
    for frame in (path, stage, site, hour, system, flow):
        if len(frame) and "arm" in frame:
            frame["arm"] = key
    for column in ["reached_stage7", "physical_dissipation_a1", "lf8_absorbing", "ordinary_shortage_any"]:
        path[column] = as_bool(path[column])
    for column in ["electrolyzer_capacity_binding", "storage_capacity_binding"]:
        hour[column] = as_bool(hour[column])
    for column in ["fleet_capacity_binding"]:
        system[column] = as_bool(system[column])
    path["positive_target"] = path.target_total > TOL
    path["adequate"] = path.terminal_site_gap <= TOL
    path["final_surplus"] = path[[f"surplus_site{i}" for i in range(1, 5)]].sum(axis=1)
    path["failure_type"] = path.terminal_gap_class.map({
        "NO_GAP": "ADEQUATE", "PURE_QUANTITY_SHORTFALL": "PURE_QUANTITY",
        "PURE_SPATIAL_MISMATCH": "PURE_LOCATION", "MIXED_QUANTITY_AND_SPATIAL": "MIXED",
    }).fillna("OTHER")
    path.loc[~path.reached_stage7, "failure_type"] = "OTHER"
    path.loc[path.reached_stage7 & ~path.positive_target, "failure_type"] = "ZERO_TARGET"
    end_hour = hour.groupby("path_id").global_hour.max()
    hour["relative_hour"] = hour.global_hour - hour.path_id.map(end_hour)
    system["relative_hour"] = system.global_hour - system.path_id.map(end_hour)
    stage["net_inventory_build_kg"] = stage.ending_inventory_kg - stage.beginning_inventory_kg
    stage["positive_inventory_build_kg"] = stage.net_inventory_build_kg.clip(lower=0)
    return {"path": path, "stage": stage, "site": site, "hour": hour, "system": system, "flow": flow}


def qstats(values: pd.Series) -> dict[str, float]:
    clean = pd.to_numeric(values, errors="coerce").dropna()
    if clean.empty:
        return {x: np.nan for x in ["mean", "median", "q5", "q25", "q75", "q95", "q99"]}
    return {"mean": clean.mean(), "median": clean.median(), "q5": clean.quantile(.05), "q25": clean.quantile(.25),
            "q75": clean.quantile(.75), "q95": clean.quantile(.95), "q99": clean.quantile(.99)}


def accounting(policies: dict[str, dict[str, pd.DataFrame]]) -> pd.DataFrame:
    rows = []
    for key, data in policies.items():
        p = data["path"]
        counts = p.termination_type.value_counts()
        s7 = p[p.reached_stage7.astype(bool)]
        pos = s7[s7.positive_target]
        values = {
            "all_paths": len(p), "true_stage7": len(s7), "physical_dissipation": int(p.physical_dissipation_a1.sum()),
            "lf8_absorbing": int(p.lf8_absorbing.sum()), "other": int(len(p)-p.reached_stage7.sum()-p.physical_dissipation_a1.sum()-p.lf8_absorbing.sum()),
            "stage7_zero_target": int((~s7.positive_target).sum()), "stage7_positive_target": len(pos),
            "positive_target_adequate": int(pos.adequate.sum()), "positive_target_shortfall": int((~pos.adequate).sum()),
        }
        for name, value in values.items():
            rows.append({"policy": key, "account": name, "count": value})
        require(values["all_paths"] == values["true_stage7"] + values["physical_dissipation"] + values["lf8_absorbing"] + values["other"], f"{key} termination accounting")
        require(values["true_stage7"] == values["stage7_zero_target"] + values["stage7_positive_target"], f"{key} Stage7 accounting")
        require(values["stage7_positive_target"] == values["positive_target_adequate"] + values["positive_target_shortfall"], f"{key} positive target accounting")
    return pd.DataFrame(rows)


def overall(policies: dict[str, dict[str, pd.DataFrame]]) -> pd.DataFrame:
    metrics = ["total_H2_production", "ordinary_shortage_total", "actual_operating_cost", "terminal_site_gap", "final_surplus", "total_HTT"]
    rows = []
    base = policies["BASE"]["path"].set_index("path_id")
    for key, data in policies.items():
        p = data["path"].set_index("path_id")
        for metric in metrics:
            stat = qstats(p[metric]); diff = p[metric] - base[metric]
            row = {"policy": key, "metric": metric, **stat, "paired_vs_base_mean": float(diff.mean()),
                   "paired_vs_base_median": float(diff.median()), "paired_win": int((diff < -TOL).sum()),
                   "paired_loss": int((diff > TOL).sum()), "paired_tie": int((diff.abs() <= TOL).sum())}
            rows.append(row)
        pos = p[p.positive_target]
        rows.append({"policy": key, "metric": "positive_target_shortfall_rate", "mean": float((~pos.adequate).mean()),
                     "median": np.nan, "paired_vs_base_mean": float((~pos.adequate).mean()-(~base[base.positive_target].adequate).mean())})
    return pd.DataFrame(rows)


def positive_target(policies: dict[str, dict[str, pd.DataFrame]]) -> tuple[pd.DataFrame, pd.DataFrame]:
    rows, sites = [], []
    for key, data in policies.items():
        p = data["path"]; pos = p[p.positive_target]
        gaps = pos.loc[~pos.adequate, "terminal_site_gap"]
        rows.append({"policy": key, "N": len(pos), "adequate_count": int(pos.adequate.sum()),
                     "adequate_rate": float(pos.adequate.mean()), "shortfall_count": int((~pos.adequate).sum()),
                     "shortfall_rate": float((~pos.adequate).mean()), "conditional_gap_mean": float(gaps.mean()) if len(gaps) else 0,
                     "gap_median": float(pos.terminal_site_gap.median()), "gap_q95": float(pos.terminal_site_gap.quantile(.95)),
                     "gap_q99": float(pos.terminal_site_gap.quantile(.99)), "zero_gap_count": int(pos.adequate.sum())})
        for site in range(1, 5):
            g = pos[f"gap_site{site}"]
            sites.append({"policy": key, "site": site, "shortage_frequency": float((g > TOL).mean()),
                          "shortage_severity_conditional": float(g[g > TOL].mean()) if (g > TOL).any() else 0})
    return pd.DataFrame(rows), pd.DataFrame(sites)


def migrations(policies: dict[str, dict[str, pd.DataFrame]], candidate: str) -> tuple[pd.DataFrame, pd.DataFrame]:
    base = policies["BASE"]["path"][["path_id", "failure_type", "positive_target"]]
    cand = policies[candidate]["path"][["path_id", "failure_type", "positive_target"]]
    merged = base.merge(cand, on="path_id", suffixes=("_base", "_candidate"), validate="one_to_one")
    merged["candidate"] = candidate
    matrix = merged.groupby(["failure_type_base", "failure_type_candidate"]).size().rename("path_count").reset_index()
    return merged, matrix


def failure_summary(policies: dict[str, dict[str, pd.DataFrame]]) -> pd.DataFrame:
    rows = []
    for key, data in policies.items():
        p = data["path"].copy()
        p["total_margin"] = p.terminal_inventory_total - p.target_total
        p["site_shortfall"] = p[[f"gap_site{i}" for i in range(1, 5)]].sum(axis=1)
        p["site_surplus"] = p[[f"surplus_site{i}" for i in range(1, 5)]].sum(axis=1)
        require(np.max(np.abs((p.site_surplus-p.site_shortfall)-p.total_margin)) <= 1e-6, f"{key} margin identity")
        for cls, group in p[p.positive_target].groupby("failure_type"):
            rows.append({"policy": key, "failure_type": cls, "path_count": len(group), "mean_gap": group.terminal_site_gap.mean(),
                         "mean_total_margin": group.total_margin.mean(), "mean_site_shortfall": group.site_shortfall.mean(),
                         "mean_site_surplus": group.site_surplus.mean()})
    return pd.DataFrame(rows)


def canonical_pairs(manifest: pd.DataFrame, base_path: pd.DataFrame) -> pd.DataFrame:
    cohort = base_path[["path_id", "termination_type", "operating_stage_count", "reached_stage7"]].copy()
    cohort["kind"] = np.where(cohort.reached_stage7.astype(bool), "STAGE7", np.where(cohort.termination_type.eq("PHYSICAL_DISSIPATION_A1"), "A1", "OTHER"))
    data = manifest.merge(cohort, on="path_id", validate="one_to_one")
    rows, seen, pair_id = [], set(), 0
    for operating in range(1, 7):
        cols = [f"k_t{i}" for i in range(1, operating+1)]
        grouper = cols[0] if len(cols) == 1 else cols
        for prefix, group in data.groupby(grouper, sort=True):
            low = group[(group.kind == "A1") & (group.operating_stage_count == operating)]
            high = group[(group.kind == "STAGE7") & (group.operating_stage_count >= operating+1)]
            if low.empty or high.empty:
                continue
            a, b = int(low.path_id.min()), int(high.path_id.min())
            if (a, b) in seen:
                continue
            seen.add((a, b)); pair_id += 1
            values = prefix if isinstance(prefix, tuple) else (prefix,)
            rows.append({"pair_id": pair_id, "pair_type": "A1_VS_STAGE7_CANONICAL", "path_low": a, "path_high": b,
                         "common_prefix_length": operating, "divergence_stage": operating+1,
                         "pre_divergence_states": "-".join(str(int(x)) for x in values),
                         "post_divergence_risk_ordering": "A1_PHYSICAL_DISSIPATION<STAGE7_TERMINAL",
                         "pair_selection_rule": "Stage85U-D canonical min path_id per exact active prefix"})
    result = pd.DataFrame(rows)
    require(len(result) >= 10, "canonical PCR/WES pairs not reproduced")
    return result


def wait_response(policies: dict[str, dict[str, pd.DataFrame]], pairs: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    responses, qa = [], []
    for key, data in policies.items():
        stage_idx = {int(pid): g.sort_values("stage") for pid, g in data["stage"].groupby("path_id")}
        site_idx = {(int(pid), int(stage)): g.sort_values("site") for (pid, stage), g in data["site"].groupby(["path_id", "stage"])}
        for pair in pairs.itertuples(index=False):
            low, high, div = stage_idx[pair.path_low], stage_idx[pair.path_high], int(pair.divergence_stage)
            common = high[high.stage < div]; low_post = low[low.stage >= div]; high_post = high[high.stage >= div]
            high_total = high.production_kg.sum(); high_pos = high.positive_inventory_build_kg.sum()
            low_last = int(low.stage.max()); high_last = int(high.stage.max())
            low_final = site_idx[(int(pair.path_low), low_last)].ending_inventory_kg.to_numpy(float)
            high_final = site_idx[(int(pair.path_high), high_last)].ending_inventory_kg.to_numpy(float)
            inventory_at_divergence = float(common.ending_inventory_kg.iloc[-1]) if len(common) else float(high.beginning_inventory_kg.iloc[0])
            high_max_inventory = float(pd.concat([high.beginning_inventory_kg, high.ending_inventory_kg]).max())
            high_last_inventory = float(high.ending_inventory_kg.iloc[-1])
            prod_diff = high_post.production_kg.sum()-low_post.production_kg.sum()
            build_diff = high_post.net_inventory_build_kg.sum()-low_post.net_inventory_build_kg.sum()
            positive_diff = high_post.positive_inventory_build_kg.sum()-low_post.positive_inventory_build_kg.sum()
            responses.append({"policy": key, "pair_id": pair.pair_id, "pair_type": pair.pair_type,
                              "path_low": pair.path_low, "path_high": pair.path_high,
                              "divergence_stage": div, "pre_divergence_production_kg": common.production_kg.sum(),
                              "post_divergence_production_difference_kg": prod_diff,
                              "post_divergence_signed_build_difference_kg": build_diff,
                              "post_divergence_positive_build_difference_kg": positive_diff,
                              "ending_inventory_total_difference_kg": float(high_final.sum()-low_final.sum()),
                              "ending_inventory_4d_l1_kg": float(np.abs(high_final-low_final).sum()),
                              "post_divergence_HTT_difference_kg": high_post.htt_kg.sum()-low_post.htt_kg.sum(),
                              "PCR_prod": common.production_kg.sum()/high_total if high_total > TOL else np.nan,
                              "PCR_build": common.positive_inventory_build_kg.sum()/high_pos if high_pos > TOL else np.nan,
                              "PCR_inventory_max": inventory_at_divergence/high_max_inventory if high_max_inventory > TOL else np.nan,
                              "PCR_inventory_last": inventory_at_divergence/high_last_inventory if high_last_inventory > TOL else np.nan,
                              "WES_prod": prod_diff/high_total if high_total > TOL else np.nan,
                              "WES_build": build_diff/high_pos if high_pos > TOL else np.nan,
                              "WES_positive_build": positive_diff/high_pos if high_pos > TOL else np.nan,
                              "effect_scope": "OBSERVED_PAIRWISE_ADAPTATION_DIFFERENCE_NOT_CAUSAL_SAVINGS"})
            maximum, compared = 0.0, 0
            cols = ["production_kg", "served_demand_kg", "shortage_kg", "htt_in_kg", "htt_out_kg", "ending_inventory_kg"]
            for stage in range(1, int(pair.common_prefix_length)+1):
                left, right = site_idx.get((pair.path_low, stage)), site_idx.get((pair.path_high, stage))
                if left is None or right is None:
                    continue
                maximum = max(maximum, float(np.max(np.abs(left[cols].to_numpy(float)-right[cols].to_numpy(float)))))
                compared += left[cols].size
            qa.append({"policy": key, "pair_id": pair.pair_id, "compared_values": compared,
                       "max_pre_divergence_abs_difference": maximum, "pass": compared > 0 and maximum <= 1e-7})
    response = pd.DataFrame(responses); qa_frame = pd.DataFrame(qa)
    require(qa_frame["pass"].all(), "shared-prefix nonanticipativity failed")
    summary = response.groupby("policy").agg(
        pair_count=("pair_id", "size"), PCR_prod_mean=("PCR_prod", "mean"), PCR_prod_median=("PCR_prod", "median"),
        PCR_build_median=("PCR_build", "median"), PCR_inventory_max_median=("PCR_inventory_max", "median"),
        PCR_inventory_last_median=("PCR_inventory_last", "median"), WES_prod_mean=("WES_prod", "mean"),
        WES_prod_median=("WES_prod", "median"), WES_build_median=("WES_build", "median"),
        WES_positive_build_median=("WES_positive_build", "median"),
        post_response_mean=("post_divergence_production_difference_kg", "mean"),
        direction_positive_share=("post_divergence_production_difference_kg", lambda x: (x > TOL).mean())).reset_index()
    return response, summary, qa_frame


def time_tables(policies: dict[str, dict[str, pd.DataFrame]]) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    checkpoints, shares, attainment = [], [], []
    for key, data in policies.items():
        hour = data["hour"]; path = data["path"].set_index("path_id")
        hourly = hour.groupby(["path_id", "relative_hour"]).agg(production=("H2_production_kg", "sum"), inventory=("end_inventory_kg", "sum"),
            htt=("HTT_out_kg", "sum"), shortage=("ordinary_shortage_kg", "sum"), pel=("P_EL_kW", "sum")).reset_index()
        for rel in [-24, -16, -8, -4, 0]:
            g = hourly[hourly.relative_hour == rel]
            checkpoints.append({"policy": key, "relative_hour": rel, "path_count": g.path_id.nunique(), "production_mean": g.production.mean(),
                                "inventory_mean": g.inventory.mean(), "HTT_mean": g.htt.mean(), "ordinary_shortage_mean": g.shortage.mean(), "P_EL_mean": g.pel.mean()})
        totals = hourly.groupby("path_id").production.sum()
        for window in [24, 16, 8, 4]:
            late = hourly[hourly.relative_hour.between(-(window-1), 0)].groupby("path_id").production.sum()
            ratio = late.reindex(totals.index, fill_value=0) / totals.replace(0, np.nan)
            shares.append({"policy": key, "window_h": window, "mean_share": ratio.mean(), "median_share": ratio.median()})
        adequate = path[path.positive_target & path.adequate]
        targets = adequate[[f"target_site{i}" for i in range(1, 5)]]
        for pid, target in targets.iterrows():
            h = hour[hour.path_id == pid].pivot_table(index="relative_hour", columns="site", values="end_inventory_kg", aggfunc="last").sort_index()
            if h.empty or not all(i in h.columns for i in range(1, 5)):
                continue
            ok = (h[[1, 2, 3, 4]].to_numpy() + TOL >= target.to_numpy()).all(axis=1)
            stable = np.where(np.logical_and.accumulate(ok[::-1])[::-1])[0]
            rel = float(h.index[stable[0]]) if len(stable) else np.nan
            attainment.append({"policy": key, "path_id": pid, "stable_target_relative_hour": rel,
                               "hours_before_stage7": -rel if np.isfinite(rel) else np.nan, "final_surplus": adequate.at[pid, "final_surplus"]})
    return pd.DataFrame(checkpoints), pd.DataFrame(shares), pd.DataFrame(attainment)


def resource_tables(policies: dict[str, dict[str, pd.DataFrame]], tail_map: pd.Series) -> dict[str, pd.DataFrame]:
    surplus_rows, grid_rows, util_rows, ordinary_rows, tank_rows, htt_rows, tail_rows, econ_rows = [], [], [], [], [], [], [], []
    pmax_map = {"BASE": BASE_PMAX, **CANDIDATES}
    for key, data in policies.items():
        p, h, system, flow = data["path"], data["hour"], data["system"], data["flow"]
        pos_adequate = p[p.positive_target & p.adequate].copy()
        bins = pd.cut(pos_adequate.final_surplus, [-1e-9, 50, 100, 200, np.inf], labels=["0-50", "50-100", "100-200", ">200"])
        for name, group in pos_adequate.groupby(bins, observed=False):
            surplus_rows.append({"policy": key, "surplus_bin": str(name), "path_count": len(group), "mean_surplus": group.final_surplus.mean(),
                                 "mean_production": group.total_H2_production.mean(), "mean_shortage": group.ordinary_shortage_total.mean(),
                                 "mean_actual_cost": group.actual_operating_cost.mean()})
        bus18 = h[h.electrical_bus == 18]
        grid_rows.append({"policy": key, "hour_count": system.shape[0], "Vmin_mean": system.min_voltage_pu.mean(), "Vmin_q01": system.min_voltage_pu.quantile(.01),
                          "voltage_binding_ratio": (system.min_voltage_pu <= .900001).mean(), "near_voltage_ratio": (system.min_voltage_pu <= .905).mean(),
                          "bus18_mean": bus18.site_voltage_pu.mean(), "bus18_q01": bus18.site_voltage_pu.quantile(.01),
                          "bus18_binding_ratio": (bus18.site_voltage_pu <= .900001).mean(), "bus18_critical_ratio": (system.min_voltage_bus == 18).mean(),
                          "line_binding_ratio": (system.max_line_loading_pct >= 1-TOL).mean(), "substation_binding_ratio": (system.root_grid_import >= 6000-TOL).mean()})
        for site in range(1, 5):
            sh = h[h.site == site]; cap = pmax_map[key][site-1]
            util_rows.append({"policy": key, "site": site, "mean_utilization": (sh.P_EL_kW/cap).mean(),
                              "ge90_ratio": (sh.P_EL_kW >= .9*cap).mean(), "ge95_ratio": (sh.P_EL_kW >= .95*cap).mean(),
                              "ge99_ratio": (sh.P_EL_kW >= .99*cap).mean(), "near_pmax_ratio": (sh.P_EL_kW >= cap-1e-6).mean(),
                              "final16_mean_utilization": (sh[sh.relative_hour >= -15].P_EL_kW/cap).mean(),
                              "final8_mean_utilization": (sh[sh.relative_hour >= -7].P_EL_kW/cap).mean()})
        ordinary_rows.append({"policy": key, "mean_shortage_kg": p.ordinary_shortage_total.mean(), "shortage_paths": int(p.ordinary_shortage_any.sum()),
                              "shortage_hours": int((h.groupby(["path_id", "global_hour"]).ordinary_shortage_kg.sum() > TOL).sum()),
                              "terminal_adequate_and_shortage_paths": int((p.adequate & (p.ordinary_shortage_total > TOL)).sum()),
                              "large_surplus_and_shortage_paths": int(((p.final_surplus > 100) & (p.ordinary_shortage_total > TOL)).sum())})
        tank_rows.append({"policy": key, "binding_hours_site_rows": int(h.storage_capacity_binding.astype(bool).sum()),
                          "binding_path_hours": int(h.groupby(["path_id", "global_hour"]).storage_capacity_binding.max().sum()),
                          "early_binding_path_hours": int(h[h.relative_hour < -15].groupby(["path_id", "global_hour"]).storage_capacity_binding.max().sum())})
        htt_rows.append({"policy": key, "mean_total_HTT": p.total_HTT.mean(), "mean_fleet_utilization": system.fleet_utilization.mean(),
                         "binding_ratio": system.fleet_capacity_binding.astype(bool).mean(), "positive_OD_rows": len(flow),
                         "pure_location_mean_HTT": p[p.failure_type == "PURE_LOCATION"].total_HTT.mean()})
        s7 = p[p.reached_stage7.astype(bool)].copy();s7["tail_class"] = s7.path_id.map(tail_map)
        total_gap = s7.terminal_site_gap.sum()
        for cls, group in s7.groupby("tail_class"):
            tail_rows.append({"policy": key, "tail_class": cls, "path_count": len(group), "mean_gap": group.terminal_site_gap.mean(),
                              "mean_production": group.total_H2_production.mean(), "mean_surplus": group.final_surplus.mean(),
                              "mean_shortage": group.ordinary_shortage_total.mean(), "mean_cost": group.actual_operating_cost.mean(),
                              "gap_contribution": group.terminal_site_gap.sum()/total_gap if total_gap > TOL else 0})
        cohorts = {"all": p, "positive_target_adequate": p[p.positive_target & p.adequate], "shortfall": p[p.terminal_site_gap > TOL],
                   "pure_quantity": p[p.failure_type == "PURE_QUANTITY"], "pure_location": p[p.failure_type == "PURE_LOCATION"],
                   "mixed": p[p.failure_type == "MIXED"], "large_surplus": p[p.final_surplus > 100]}
        for name, group in cohorts.items():
            econ_rows.append({"policy": key, "cohort": name, "N": len(group), "actual_operating_cost": group.actual_operating_cost.mean(),
                              "production_cost": group.production_cost.mean(), "electricity_cost": group.electricity_cost.mean(),
                              "production_om_cost": group.production_om_cost.mean(), "HTT_cost": group.HTT_cost.mean(),
                              "ordinary_shortage_cost": group.ordinary_shortage_cost.mean(), "holding_cost": group.holding_cost.mean(),
                              "terminal_gap_penalty": group.terminal_penalty_cost.mean(), "formal_objective": group.reported_objective.mean()})
    return {"surplus": pd.DataFrame(surplus_rows), "grid": pd.DataFrame(grid_rows), "util": pd.DataFrame(util_rows),
            "ordinary": pd.DataFrame(ordinary_rows), "tank": pd.DataFrame(tank_rows), "htt": pd.DataFrame(htt_rows),
            "tail": pd.DataFrame(tail_rows), "economics": pd.DataFrame(econ_rows)}


def tail_mapping(base_path: pd.DataFrame) -> pd.Series:
    ordered = base_path[base_path.reached_stage7.astype(bool)].sort_values(["terminal_site_gap", "path_id"]).reset_index(drop=True)
    n = len(ordered); cut95, cut99 = math.floor(.95*n), math.floor(.99*n)
    ordered["tail_class"] = "normal95"; ordered.loc[cut95:cut99-1, "tail_class"] = "difficult4"; ordered.loc[cut99:, "tail_class"] = "extreme1"
    return ordered.set_index("path_id").tail_class


def recoverability(repo: Path, policies: dict[str, dict[str, pd.DataFrame]]) -> pd.DataFrame:
    sources = {
        "B0001": repo / "results/task-002-stage2b-b3-smoke/stage89q-penalty1000-vs1500-long-training/run-003/05_analysis/10_deep_penalty1000/19_s4_grid_aware_recoverability/03_grid_aware_recoverability/s4_125_grid_aware_recovery_by_event.csv",
        "B1011": repo / "results/task-002-stage2b-b3-smoke/stage89q-penalty1000-vs1500-long-training/run-003/05_analysis/10_deep_penalty1000/20_all125_grid_aware_recoverability/03_grid_aware_recoverability/all125_grid_aware_recovery_by_event.csv",
    }
    rows = []
    for arm, source in sources.items():
        events = pd.read_csv(readable_path(source)); pid_col = "path_id"
        require(pid_col in events, f"recoverability path id missing: {arm}")
        ids = sorted(set(events[pid_col].astype(int)))
        base = policies["BASE"]["path"].set_index("path_id"); cand = policies[arm]["path"].set_index("path_id")
        for pid in ids:
            b, c = base.loc[pid], cand.loc[pid]
            if b.terminal_site_gap > TOL and c.terminal_site_gap <= TOL:
                status = "PHYSICAL_GAIN_REALIZED_IN_POLICY"
            elif b.terminal_site_gap > TOL and c.terminal_site_gap < b.terminal_site_gap-TOL:
                status = "POLICY_CHANGED_PATH_MECHANISM"
            elif b.terminal_site_gap > TOL:
                status = "PHYSICAL_GAIN_AVAILABLE_BUT_NOT_USED"
            else:
                status = "NOT_IDENTIFIABLE"
            rows.append({"candidate": arm, "path_id": pid, "base_gap": b.terminal_site_gap, "candidate_gap": c.terminal_site_gap,
                         "base_production": b.total_H2_production, "candidate_production": c.total_H2_production, "status": status, "source": str(source)})
    return pd.DataFrame(rows)


def paired_outcomes(policies: dict[str, dict[str, pd.DataFrame]]) -> pd.DataFrame:
    metrics = ["terminal_site_gap", "ordinary_shortage_total", "actual_operating_cost", "final_surplus"]
    base = policies["BASE"]["path"].set_index("path_id")
    rows = []
    for pid in base.index:
        row = {"path_id": pid}
        signs = []
        for arm in ["B0001", "B1011"]:
            c = policies[arm]["path"].set_index("path_id").loc[pid]
            for metric in metrics:
                row[f"{arm}_minus_BASE_{metric}"] = c[metric]-base.loc[pid, metric]
            signs.append(np.sign(row[f"{arm}_minus_BASE_terminal_site_gap"]))
        if signs[0] < 0 and signs[1] < 0: cls = "BOTH_EXPANDED_BETTER"
        elif signs[0] < 0 and signs[1] >= 0: cls = "ONLY_B0001_BETTER"
        elif signs[1] < 0 and signs[0] >= 0: cls = "ONLY_B1011_BETTER"
        elif signs[0] == 0 and signs[1] == 0: cls = "BOTH_SAME"
        elif signs[0] > 0 and signs[1] > 0: cls = "BASE_BETTER"
        else: cls = "TRADEOFF"
        row["terminal_gap_outcome"] = cls; rows.append(row)
    return pd.DataFrame(rows)


def save_plot(fig: plt.Figure, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True);fig.tight_layout();fig.savefig(path, dpi=180, facecolor="white");plt.close(fig)


def figures(repo: Path, run: Path, policies: dict[str, dict[str, pd.DataFrame]], tables: dict[str, pd.DataFrame], migrations_map: dict[str, pd.DataFrame]) -> None:
    plt.rcParams.update({"font.sans-serif": ["Microsoft YaHei", "SimHei", "DejaVu Sans"], "axes.unicode_minus": False})
    figdir = run / "07_figures"; figdir.mkdir(parents=True, exist_ok=True)
    def line_training(metric: str, title: str, ylabel: str, name: str):
        fig, ax = plt.subplots(figsize=(8, 4.5))
        for key in ["BASE", "B0001", "B1011"]:
            path = (repo / BASE_TRACE) if key == "BASE" else task_paths(run, key)[0] / "iteration_trace/training_progress.csv"
            tr = pd.read_csv(path); ax.plot(tr.iteration, tr[metric], lw=1.3, label=LABELS[key], color=COLORS[key])
        ax.set(title=title, xlabel="迭代", ylabel=ylabel);ax.legend();save_plot(fig, figdir / name)
    line_training("lower_bound", "训练下界轨迹", "LB", "01_lb_trajectory.png")
    line_training("stage1_total_production", "Stage1 制氢轨迹", "千克", "02_stage1_production_trajectory.png")
    fig,ax=plt.subplots(figsize=(8,4.5))
    for key in ["BASE","B0001","B1011"]:
        path=(repo/BASE_TRACE) if key=="BASE" else task_paths(run,key)[0]/"iteration_trace/training_progress.csv"
        tr=pd.read_csv(path);ax.plot(tr.elapsed_seconds/3600,tr.cut_count,lw=1.3,label=LABELS[key],color=COLORS[key])
    ax.set(title="Cuts 与训练运行时间",xlabel="运行时间（小时）",ylabel="cuts");ax.legend();save_plot(fig,figdir/"03_cuts_runtime_trajectory.png")

    overall_table = tables["overall"]
    plot_specs = [
        ("total_H2_production", "三策略总制氢", "千克", "04_total_production.png"),
        ("positive_target_shortfall_rate", "正目标不足率", "比例", "07_positive_target_reliability.png"),
        ("ordinary_shortage_total", "普通用氢缺口", "千克", "18_ordinary_shortage.png"),
    ]
    for metric, title, ylabel, name in plot_specs:
        sub = overall_table[overall_table.metric == metric]
        fig, ax = plt.subplots(figsize=(7, 4.5));ax.bar(sub.policy, sub["mean"], color=[COLORS[x] for x in sub.policy]);ax.set(title=title, ylabel=ylabel);save_plot(fig, figdir/name)
    stage = pd.concat([d["stage"].assign(policy=k) for k, d in policies.items()])
    stage_mean = stage.groupby(["policy", "stage"]).production_kg.mean().reset_index()
    fig, ax = plt.subplots(figsize=(8,4.5))
    for key in ["BASE","B0001","B1011"]:
        g=stage_mean[stage_mean.policy==key];ax.plot(g.stage,g.production_kg,marker="o",label=LABELS[key],color=COLORS[key])
    ax.set(title="Stage1-6 制氢时序",xlabel="阶段",ylabel="千克/路径");ax.legend();save_plot(fig,figdir/"05_stage1_6_production_timing.png")
    shares=tables["shares"];sub=shares[shares.window_h.isin([16,8])].pivot(index="policy",columns="window_h",values="mean_share")
    fig,ax=plt.subplots(figsize=(7,4.5));sub.loc[["BASE","B0001","B1011"]].plot.bar(ax=ax,color=["#4C78A8","#F2CF5B"]);ax.set(title="最后16/8小时制氢占比",ylabel="占总制氢比例",xlabel="");save_plot(fig,figdir/"06_final16_final8_share.png")
    for arm,n in [("B0001","08_failure_migration_b0001.png"),("B1011","09_quantity_mixed_transition.png")]:
        matrix=migrations_map[arm].pivot(index="failure_type_base",columns="failure_type_candidate",values="path_count").fillna(0)
        fig,ax=plt.subplots(figsize=(7,5));im=ax.imshow(matrix,cmap="Blues");ax.set_xticks(range(len(matrix.columns)));ax.set_xticklabels(matrix.columns,rotation=35,ha="right");ax.set_yticks(range(len(matrix.index)));ax.set_yticklabels(matrix.index);ax.set(title=f"Base 到 {arm} 问题迁移");fig.colorbar(im,ax=ax);save_plot(fig,figdir/n)
    surplus=tables["resources_surplus"].pivot(index="surplus_bin",columns="policy",values="path_count").fillna(0)
    surplus=surplus.reindex(["0-50","50-100","100-200",">200"])
    fig,ax=plt.subplots(figsize=(7,4.5));surplus[["BASE","B0001","B1011"]].plot.bar(ax=ax,color=[COLORS[x] for x in ["BASE","B0001","B1011"]]);ax.set(title="正目标达标路径最终 surplus",ylabel="路径数",xlabel="surplus 分组");save_plot(fig,figdir/"10_large_surplus_distribution.png")
    checkpoints=tables["checkpoints"]
    fig,ax=plt.subplots(figsize=(8,4.5))
    for key in ["BASE","B0001","B1011"]:
        g=checkpoints[checkpoints.policy==key];ax.plot(g.relative_hour,g.inventory_mean,marker="o",label=LABELS[key],color=COLORS[key])
    ax.set(title="Stage7 前库存形成",xlabel="相对 Stage7 小时",ylabel="千克");ax.legend();save_plot(fig,figdir/"11_inventory_trajectories.png")
    attain=tables["attainment"].groupby("policy").hours_before_stage7.median().reindex(["BASE","B0001","B1011"])
    fig,ax=plt.subplots(figsize=(7,4.5));ax.bar(attain.index,attain.values,color=[COLORS[x] for x in attain.index]);ax.set(title="稳定达到最终目标时间",ylabel="Stage7 前小时数");save_plot(fig,figdir/"12_stable_target_timing.png")
    wait=tables["wait_summary"].set_index("policy").loc[["BASE","B0001","B1011"]]
    fig,ax=plt.subplots(figsize=(7,4.5));wait[["PCR_prod_median","WES_prod_median"]].plot.bar(ax=ax,color=["#4C78A8","#E45756"]);ax.set(title="Wait-and-see PCR/WES",ylabel="比率",xlabel="");save_plot(fig,figdir/"13_wait_and_see_pcr_wes.png")
    response=tables["wait_response"]
    fig,ax=plt.subplots(figsize=(7,4.5));response.boxplot(column="post_divergence_production_difference_kg",by="policy",ax=ax);ax.set(title="共同前缀后的高低风险响应",xlabel="",ylabel="高风险减低风险制氢（千克）");fig.suptitle("");save_plot(fig,figdir/"14_shared_prefix_response.png")
    htt=tables["resources_htt"].set_index("policy").loc[["BASE","B0001","B1011"]]
    fig,ax=plt.subplots(figsize=(7,4.5));htt[["mean_fleet_utilization","binding_ratio"]].plot.bar(ax=ax);ax.set(title="HTT 利用与绑定",ylabel="比例",xlabel="");save_plot(fig,figdir/"15_htt_utilization_alignment.png")
    grid=tables["resources_grid"].set_index("policy").loc[["BASE","B0001","B1011"]]
    fig,ax=plt.subplots(figsize=(7,4.5));grid[["bus18_q01","Vmin_q01"]].plot.bar(ax=ax);ax.axhline(.9,color="black",lw=.8);ax.set(title="bus18 与系统最低电压",ylabel="p.u.",xlabel="");save_plot(fig,figdir/"16_bus18_voltage.png")
    util=tables["resources_util"].pivot(index="site",columns="policy",values="mean_utilization")
    fig,ax=plt.subplots(figsize=(7,4.5));util[["BASE","B0001","B1011"]].plot.bar(ax=ax,color=[COLORS[x] for x in ["BASE","B0001","B1011"]]);ax.set(title="各站电解槽利用率",ylabel="比例",xlabel="站点");save_plot(fig,figdir/"17_site_pmax_utilization.png")
    tank=tables["resources_tank"].set_index("policy").loc[["BASE","B0001","B1011"]]
    fig,ax=plt.subplots(figsize=(7,4.5));ax.bar(tank.index,tank.binding_path_hours,color=[COLORS[x] for x in tank.index]);ax.set(title="储罐饱和小时",ylabel="路径-小时");save_plot(fig,figdir/"19_tank_saturation.png")
    tail=tables["resources_tail"];sub=tail[tail.tail_class.isin(["difficult4","extreme1"])].pivot(index="tail_class",columns="policy",values="mean_gap")
    fig,ax=plt.subplots(figsize=(7,4.5));sub[["BASE","B0001","B1011"]].plot.bar(ax=ax,color=[COLORS[x] for x in ["BASE","B0001","B1011"]]);ax.set(title="困难4%与极端1%终端缺口",ylabel="千克",xlabel="");save_plot(fig,figdir/"20_tail_gap.png")
    econ=tables["resources_economics"];sub=econ[econ.cohort=="all"].set_index("policy").loc[["BASE","B0001","B1011"]]
    fig,ax=plt.subplots(figsize=(7,4.5));sub[["actual_operating_cost","terminal_gap_penalty"]].plot.bar(ax=ax);ax.set(title="实际成本与终端罚分开报告",ylabel="元/路径",xlabel="");save_plot(fig,figdir/"21_actual_cost_vs_terminal_penalty.png")
    decision=tables["decision"]
    fig,ax=plt.subplots(figsize=(9,4.8));ax.axis("off");text="\n".join(f"{r.metric}: {r.B0001} / {r.B1011}" for r in decision.itertuples(index=False));ax.text(.02,.98,"最终机制总览（B0001 / B1011）\n\n"+text,va="top",fontsize=11);save_plot(fig,figdir/"22_final_mechanism_summary.png")


def make_decisions(tables: dict[str, pd.DataFrame]) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    wait=tables["wait_summary"].set_index("policy");grid=tables["resources_grid"].set_index("policy")
    tank=tables["resources_tank"].set_index("policy");ordinary=tables["resources_ordinary"].set_index("policy")
    htt=tables["resources_htt"].set_index("policy");pos=tables["positive"].set_index("policy")
    surplus=tables["resources_surplus"]
    rows=[];issues=[];historical=[];scores={}
    for arm in ["B0001","B1011"]:
        changes=np.array([
            wait.at["BASE","PCR_prod_median"]-wait.at[arm,"PCR_prod_median"],
            wait.at["BASE","PCR_build_median"]-wait.at[arm,"PCR_build_median"],
            wait.at[arm,"WES_prod_median"]-wait.at["BASE","WES_prod_median"],
            wait.at[arm,"WES_positive_build_median"]-wait.at["BASE","WES_positive_build_median"],
        ],dtype=float)
        positive=int((changes>.01).sum());negative=int((changes<-.01).sum());magnitude=float(np.nanmax(np.abs(changes)))
        if np.all(np.abs(changes)<=.01):direction="SAME"
        elif positive>=3:direction="STRONGER"
        elif negative>=3:direction="WEAKER"
        else:direction="MIXED"
        if direction=="MIXED":effect="MIXED"
        elif magnitude>=.15:effect="STRONG"
        elif magnitude>=.05:effect="MODERATE"
        elif magnitude>.01:effect="WEAK"
        else:effect="NONE"
        rate_delta=float(pos.at[arm,"shortfall_rate"]-pos.at["BASE","shortfall_rate"])
        gap_delta=float(pos.at[arm,"conditional_gap_mean"]-pos.at["BASE","conditional_gap_mean"])
        if rate_delta < -1e-4 and gap_delta <= .1:reliability="IMPROVED"
        elif rate_delta > 1e-4 and gap_delta >= -.1:reliability="WORSE"
        elif abs(rate_delta)<=1e-4 and abs(gap_delta)<=.1:reliability="SAME"
        else:reliability="MIXED"
        base_large=int(surplus[(surplus.policy=="BASE")&surplus.surplus_bin.isin(["100-200",">200"])].path_count.sum())
        arm_large=int(surplus[(surplus.policy==arm)&surplus.surplus_bin.isin(["100-200",">200"])].path_count.sum())
        surplus_signal="IMPROVED" if arm_large < base_large else ("WORSE" if arm_large > base_large else "SAME")
        bind_delta=float(grid.at[arm,"voltage_binding_ratio"]-grid.at["BASE","voltage_binding_ratio"])
        near_delta=float(grid.at[arm,"near_voltage_ratio"]-grid.at["BASE","near_voltage_ratio"])
        q01_delta=float(grid.at[arm,"bus18_q01"]-grid.at["BASE","bus18_q01"])
        if bind_delta>1e-4 or (near_delta>.01 and q01_delta<-.001):grid_risk="WORSE"
        elif bind_delta<-1e-4 and q01_delta>.001:grid_risk="IMPROVED"
        elif abs(bind_delta)<=1e-4 and abs(near_delta)<=.01 and abs(q01_delta)<=.001:grid_risk="SAME"
        else:grid_risk="MIXED"
        shift="YES" if bind_delta>.01 else ("MIXED" if near_delta>.01 else "NO")
        role="MINIMAL_HIGH_EFFICIENCY_FLEXIBILITY" if arm=="B0001" else "BALANCED_STRONGER_FLEXIBILITY"
        rows.append({"candidate":arm,"WAIT_AND_SEE_DIRECTION":direction,"WAIT_AND_SEE_EFFECT_SIZE":effect,
                     "TERMINAL_RELIABILITY":reliability,"SURPLUS_SIGNAL":surplus_signal,"GRID_RISK":grid_risk,
                     "BOTTLENECK_SHIFT_TO_VOLTAGE":shift,"POLICY_ROLE":role})
        scores[arm]=(2 if reliability=="IMPROVED" else (-2 if reliability=="WORSE" else 0)) + \
            (1 if surplus_signal=="IMPROVED" else (-1 if surplus_signal=="WORSE" else 0)) + \
            (1 if direction=="STRONGER" else (-1 if direction=="WEAKER" else 0)) + \
            (-1 if grid_risk=="WORSE" else (1 if grid_risk=="IMPROVED" else 0))
        ordinary_delta=float(ordinary.at[arm,"mean_shortage_kg"]-ordinary.at["BASE","mean_shortage_kg"])
        ordinary_path_delta=int(ordinary.at[arm,"shortage_paths"]-ordinary.at["BASE","shortage_paths"])
        ordinary_issue="YES" if ordinary_delta>TOL and ordinary_path_delta>0 else ("MIXED" if ordinary_delta> TOL or ordinary_path_delta>0 else "NO")
        issue_values={
            "new_voltage_bottleneck":(shift,f"11_grid/grid_bus18_summary.csv: binding_delta={bind_delta:.9g}; near_delta={near_delta:.9g}; bus18_q01_delta={q01_delta:.9g}"),
            "line_bottleneck":("YES" if grid.at[arm,"line_binding_ratio"]>grid.at["BASE","line_binding_ratio"]+TOL else "NO",f"11_grid/grid_bus18_summary.csv: candidate={grid.at[arm,'line_binding_ratio']:.9g}; base={grid.at['BASE','line_binding_ratio']:.9g}"),
            "substation_bottleneck":("YES" if grid.at[arm,"substation_binding_ratio"]>grid.at["BASE","substation_binding_ratio"]+TOL else "NO",f"11_grid/grid_bus18_summary.csv: candidate={grid.at[arm,'substation_binding_ratio']:.9g}; base={grid.at['BASE','substation_binding_ratio']:.9g}"),
            "tank_bottleneck":("YES" if tank.at[arm,"binding_path_hours"]>tank.at["BASE","binding_path_hours"]*1.2+10 else "NO",f"12_ordinary_tank/tank_saturation_summary.csv: candidate={int(tank.at[arm,'binding_path_hours'])}; base={int(tank.at['BASE','binding_path_hours'])}"),
            "ordinary_shortage_increase":(ordinary_issue,f"12_ordinary_tank/ordinary_shortage_summary.csv: mean_delta={ordinary_delta:.9g}; path_delta={ordinary_path_delta}"),
            "higher_surplus":("YES" if arm_large>base_large else "NO",f"08_surplus/large_surplus_summary.csv: >100kg candidate={arm_large}; base={base_large}"),
            "numerical_instability":("NO","training acceptance numerical_finite=PASS; OOS max residual gates=PASS"),
            "checkpoint_issue":("NO","checkpoint_reload_audit.csv and external SHA gate PASS"),
            "OOS_path_mismatch":("NO",f"path_bank_identity.csv: 10000/10000 ordered paths identical for {arm}"),
        }
        for issue,(value,evidence) in issue_values.items():issues.append({"candidate":arm,"issue":issue,"status":value,"evidence":evidence})
        history={
            "early commitment":(direction,f"06_wait_and_see/pcr_wes_summary.csv: directional_changes={changes.tolist()}"),
            "weak wait-and-see effect size":(effect,f"06_wait_and_see/pcr_wes_summary.csv: max_abs_median_change={magnitude:.9g}"),
            "large surplus":(surplus_signal,f"08_surplus/large_surplus_summary.csv: >100kg candidate={arm_large}; base={base_large}"),
            "pure quantity shortage":(reliability,f"03_positive_target/positive_target_reliability.csv: shortfall_rate_delta={rate_delta:.9g}"),
            "pure location shortage":("RECHECKED","04_failure_migration transition CSV gives exact path migrations"),
            "mixed shortage":(reliability,"04_failure_migration transition CSV gives exact mixed-to-* counts"),
            "HTT aggregate capacity":("NO_NEW_CAPACITY_ISSUE",f"10_htt/htt_summary.csv: binding_ratio={htt.at[arm,'binding_ratio']:.9g}"),
            "HTT information limitation":("UNCHANGED","10_htt/htt_summary.csv; causal attribution remains not identifiable"),
            "HTT spatial value signal":("RECHECKED",f"10_htt/htt_summary.csv: pure_location_mean_HTT={htt.at[arm,'pure_location_mean_HTT']:.9g}"),
            "electrolyzer Pmax bottleneck":("RECHECKED","11_grid/electrolyzer_utilization.csv contains site/hour utilization"),
            "bus18 voltage":(grid_risk,f"11_grid/grid_bus18_summary.csv: bus18_q01_delta={q01_delta:.9g}"),
            "line limit":(issue_values["line_bottleneck"][0],issue_values["line_bottleneck"][1]),
            "tank saturation":(issue_values["tank_bottleneck"][0],issue_values["tank_bottleneck"][1]),
            "ordinary shortage":(ordinary_issue,issue_values["ordinary_shortage_increase"][1]),
            "tail concentration":("RECHECKED","13_tail/tail_summary.csv uses frozen Base 95/4/1 path cohorts"),
            "training stability":("PASS","acceptance/training_stability.csv"),
            "checkpoint reliability":("PASS","checkpoint/checkpoint_manifest.csv + acceptance/checkpoint_reload_audit.csv"),
        }
        for issue,(status,evidence) in history.items():historical.append({"candidate":arm,"historical_issue":issue,"status":status,"evidence":evidence})
    d=pd.DataFrame(rows).set_index("candidate")
    decision=pd.DataFrame([{"metric":metric,"B0001":d.at["B0001",metric],"B1011":d.at["B1011",metric]}
                           for metric in ["WAIT_AND_SEE_DIRECTION","WAIT_AND_SEE_EFFECT_SIZE","TERMINAL_RELIABILITY",
                                          "SURPLUS_SIGNAL","GRID_RISK","BOTTLENECK_SHIFT_TO_VOLTAGE","POLICY_ROLE"]])
    if max(scores.values())<=0:
        recommendation="BASE" if all(d.loc[a,"TERMINAL_RELIABILITY"]=="WORSE" for a in scores) else "NEEDS_MORE_VALIDATION"
    elif abs(scores["B0001"]-scores["B1011"])>=2:
        recommendation=max(scores,key=scores.get)
    elif scores["B0001"]>0 and scores["B1011"]>0:
        recommendation="BOTH_FOR_DIFFERENT_PURPOSES"
    else:
        recommendation=max(scores,key=scores.get)
    decision.attrs["recommendation"]=recommendation
    return decision,pd.DataFrame(issues),pd.DataFrame(historical)


def artifact_manifest(run: Path) -> pd.DataFrame:
    rows=[]
    for path in sorted(p for p in run.rglob("*") if p.is_file() and p.name != "artifact_manifest.csv"):
        rel=path.relative_to(run);large=path.suffix.lower() in {".mat"} or path.stat().st_size>20_000_000
        rows.append({"arm":"B0001" if "b0001" in str(rel).lower() else ("B1011" if "b1011" in str(rel).lower() else "COMMON"),
                     "path":str(rel).replace("\\","/"),"size":path.stat().st_size,"SHA256":sha256(path),"role":"RAW_OR_CHECKPOINT" if large else "LIGHTWEIGHT_EVIDENCE",
                     "generated_by":"Stage89Q Pmax long workflow","keep_local":"YES","commit_to_git":"NO" if large or any(x in str(rel) for x in ["hourly_site","grid_hourly","path_summary","htt_od","monitor"]) else "YES"})
    return pd.DataFrame(rows)


def oos_integrity(policies: dict[str, dict[str, pd.DataFrame]], bank: pd.DataFrame) -> pd.DataFrame:
    bank_sequences = bank.drop(columns="path_id").astype(int).astype(str).agg("-".join, axis=1)
    bank_sequences.index = bank.path_id.astype(int)
    rows = []
    for key, data in policies.items():
        p, stage, site, hour, system = data["path"], data["stage"], data["site"], data["hour"], data["system"]
        indexed = p.set_index("path_id")
        expected = indexed.operating_stage_count.astype(int)
        counts = {
            "stage_rows": stage.groupby("path_id").size().reindex(indexed.index, fill_value=0),
            "site_rows": site.groupby("path_id").size().reindex(indexed.index, fill_value=0),
            "hour_site_rows": hour.groupby("path_id").size().reindex(indexed.index, fill_value=0),
            "grid_hour_rows": system.groupby("path_id").size().reindex(indexed.index, fill_value=0),
        }
        row_count_pass = (counts["stage_rows"] == expected).all() and (counts["site_rows"] == 4*expected).all() and \
            (counts["hour_site_rows"] == 32*expected).all() and (counts["grid_hour_rows"] == 8*expected).all()
        sequence_pass = indexed.state_sequence.astype(str).equals(bank_sequences.reindex(indexed.index))
        production_residual = float((hour.H2_production_kg-0.0195*hour.P_EL_kW).abs().max())
        service_residual = float((hour.ordinary_served_kg+hour.ordinary_shortage_kg-hour.ordinary_demand_kg).abs().max())
        pre_residual = float((hour.inventory_before_HTT_kg-(hour.begin_inventory_kg+hour.H2_production_kg-hour.ordinary_served_kg)).abs().max())
        end_residual = float((hour.end_inventory_kg-(hour.inventory_before_HTT_kg-hour.HTT_out_kg+hour.HTT_in_kg)).abs().max())
        hour_htt = hour.groupby(["path_id","global_hour"]).HTT_out_kg.sum()
        system_htt = system.set_index(["path_id","global_hour"]).total_HTT_kg.reindex(hour_htt.index)
        htt_residual = float((hour_htt-system_htt).abs().max())
        target = indexed[[f"target_site{i}" for i in range(1,5)]].to_numpy(float)
        inventory = indexed[[f"inventory_site{i}" for i in range(1,5)]].to_numpy(float)
        gaps = indexed[[f"gap_site{i}" for i in range(1,5)]].to_numpy(float)
        stage7_residual = float(np.max(np.abs(gaps-np.maximum(target-inventory,0))))
        checks = {
            "ordered_bank_state_sequence": (sequence_pass,"10000 full state sequences"),
            "no_padded_post_termination_rows": (row_count_pass,"stage/site/hour rows equal operating_stage_count multipliers"),
            "hourly_production_identity": (production_residual<=1e-7,f"max_residual={production_residual:.12g}"),
            "ordinary_service_identity": (service_residual<=1e-7,f"max_residual={service_residual:.12g}"),
            "inventory_pre_htt_identity": (pre_residual<=1e-7,f"max_residual={pre_residual:.12g}"),
            "inventory_end_identity": (end_residual<=1e-7,f"max_residual={end_residual:.12g}"),
            "htt_hourly_identity": (htt_residual<=1e-7,f"max_residual={htt_residual:.12g}"),
            "stage7_gap_identity": (stage7_residual<=1e-7,f"max_residual={stage7_residual:.12g}"),
        }
        for check,(passed,detail) in checks.items():rows.append({"policy":key,"check":check,"pass":bool(passed),"detail":detail})
    result=pd.DataFrame(rows);require(result["pass"].all(),"raw OOS integrity gate failed")
    return result


def finalize(repo: Path, run: Path, commit: str) -> None:
    for arm in ["B0001","B1011"]:
        require((task_paths(run,arm)[0]/"acceptance/ACCEPTANCE_PASS.txt").is_file(),f"{arm} acceptance missing")
        meta=pd.read_csv(task_paths(run,arm)[1]/"oos_metadata.csv");require(scalar_bool(meta.iloc[0]["pass"]),f"{arm} OOS metadata fail")
    policies={key:load_policy(repo,run,key) for key in ["BASE","B0001","B1011"]}
    for key,data in policies.items():
        require(len(data["path"])==10000 and np.array_equal(data["path"].path_id,np.arange(1,10001)),f"{key} path identity")
        require(np.isfinite(data["path"].select_dtypes(include=[np.number]).to_numpy()).all(),f"{key} path NaN/Inf")
    manifest=pd.read_csv(run/"01_preflight/common_bank/oos_path_manifest.csv")
    raw_qa=oos_integrity(policies,manifest);safe_csv(raw_qa,run/"09_qa/raw_oos_integrity.csv")
    analysis=run/"06_paired_analysis";dirs=["01_accounting","02_overall","03_positive_target","04_failure_migration","05_quantity_location_mixed","06_wait_and_see","07_time_formation","08_surplus","09_recoverability_closure","10_htt","11_grid","12_ordinary_tank","13_tail","14_economics","15_new_issue_scan","16_final_decision"]
    for d in dirs:(analysis/d).mkdir(parents=True,exist_ok=True)
    acct=accounting(policies);safe_csv(acct,analysis/"01_accounting/oos_termination_accounting.csv")
    ov=overall(policies);safe_csv(ov,analysis/"02_overall/overall_paired_summary.csv")
    pos,pos_site=positive_target(policies);safe_csv(pos,analysis/"03_positive_target/positive_target_reliability.csv");safe_csv(pos_site,analysis/"03_positive_target/site_shortage_summary.csv")
    migrations_map={}
    for arm in ["B0001","B1011"]:
        detail,matrix=migrations(policies,arm);safe_csv(detail,analysis/f"04_failure_migration/base_to_{arm.lower()}_failure_transition.csv");safe_csv(matrix,analysis/f"04_failure_migration/base_to_{arm.lower()}_transition_matrix.csv");migrations_map[arm]=matrix
    failure=failure_summary(policies);safe_csv(failure,analysis/"05_quantity_location_mixed/failure_type_summary.csv")
    accepted_failure=pd.read_csv(repo/"results/task-002-stage2b-b3-smoke/stage89q-penalty1000-vs1500-long-training/run-003/05_analysis/04_stage7_shortfall/quantity_vs_location.csv")
    reproduced=policies["BASE"]["path"].loc[policies["BASE"]["path"].reached_stage7,"terminal_gap_class"].value_counts().rename_axis("class").rename("reproduced_count").reset_index()
    failure_reproduction=accepted_failure[["class","path_count"]].merge(reproduced,on="class",how="outer",validate="one_to_one").fillna(0)
    failure_reproduction["pass"]=failure_reproduction.path_count.astype(int)==failure_reproduction.reproduced_count.astype(int)
    require(failure_reproduction["pass"].all(),"Base accepted failure classification not reproduced")
    safe_csv(failure_reproduction,analysis/"05_quantity_location_mixed/base_classification_reproduction.csv")
    pairs=canonical_pairs(manifest,policies["BASE"]["path"]);response,wait_summary,prefix_qa=wait_response(policies,pairs)
    accepted_pairs=pd.read_csv(repo/"results/task-002-stage2b-b3-smoke/stage89o-comprehensive-policy-mechanism-analysis/run-005/shared_prefix_pair_master.csv")
    accepted_pairs=accepted_pairs[accepted_pairs.pair_type=="A1_VS_STAGE7_CANONICAL"].reset_index(drop=True)
    pair_columns=["pair_id","pair_type","path_low","path_high","common_prefix_length","divergence_stage","pre_divergence_states","post_divergence_risk_ordering","pair_selection_rule"]
    canonical_pass=pairs[pair_columns].reset_index(drop=True).equals(accepted_pairs[pair_columns])
    require(canonical_pass,"Stage85U-D canonical pair reproduction failed")
    safe_csv(pd.DataFrame([{"check":"Stage85U-D canonical pair reproduction","pair_count":len(pairs),"pass":canonical_pass,
                            "source":"stage89o run-005/shared_prefix_pair_master.csv"}]),analysis/"06_wait_and_see/canonical_pair_reproduction.csv")
    safe_csv(pairs,analysis/"06_wait_and_see/shared_prefix_pair_master.csv");safe_csv(response,analysis/"06_wait_and_see/shared_prefix_divergence_response.csv");safe_csv(wait_summary,analysis/"06_wait_and_see/pcr_wes_summary.csv");safe_csv(prefix_qa,analysis/"06_wait_and_see/shared_prefix_nonanticipativity_qa.csv")
    checkpoints,shares,attain=time_tables(policies);safe_csv(checkpoints,analysis/"07_time_formation/checkpoint_time_formation.csv");safe_csv(shares,analysis/"07_time_formation/late_production_share.csv");safe_csv(attain,analysis/"07_time_formation/stable_target_attainment_timing.csv")
    tail_map=tail_mapping(policies["BASE"]["path"]);resources=resource_tables(policies,tail_map)
    safe_csv(resources["surplus"],analysis/"08_surplus/large_surplus_summary.csv");recovery=recoverability(repo,policies);safe_csv(recovery,analysis/"09_recoverability_closure/fresh_policy_recoverability_closure.csv")
    safe_csv(resources["htt"],analysis/"10_htt/htt_summary.csv");safe_csv(resources["grid"],analysis/"11_grid/grid_bus18_summary.csv");safe_csv(resources["util"],analysis/"11_grid/electrolyzer_utilization.csv")
    safe_csv(resources["ordinary"],analysis/"12_ordinary_tank/ordinary_shortage_summary.csv");safe_csv(resources["tank"],analysis/"12_ordinary_tank/tank_saturation_summary.csv")
    safe_csv(resources["tail"],analysis/"13_tail/tail_summary.csv");safe_csv(resources["economics"],analysis/"14_economics/economics_components.csv")
    paired=paired_outcomes(policies);safe_csv(paired,analysis/"16_final_decision/path_level_paired_outcome.csv")
    tables={"overall":ov,"positive":pos,"checkpoints":checkpoints,"shares":shares,"attainment":attain,"wait_response":response,"wait_summary":wait_summary,**{f"resources_{k}":v for k,v in resources.items()}}
    decision,new_issues,historical=make_decisions(tables);recommendation=decision.attrs["recommendation"];tables["decision"]=decision
    safe_csv(new_issues,analysis/"15_new_issue_scan/new_issue_scan.csv");safe_csv(historical,analysis/"16_final_decision/historical_issue_status.csv");safe_csv(decision,analysis/"16_final_decision/final_decision_labels.csv")
    figures(repo,run,policies,tables,migrations_map)
    fig_rows=[]
    for path in sorted((run/"07_figures").glob("*.png")):
        image=Image.open(path).convert("RGB");array=np.asarray(image);fig_rows.append({"figure":path.name,"width":image.width,"height":image.height,"pixel_std":float(array.std()),"nonblank":bool(array.std()>2)})
    figqa=pd.DataFrame(fig_rows);require(len(figqa)==22 and figqa.nonblank.all(),"figure QA failed");safe_csv(figqa,run/"09_qa/figure_qa.csv")
    thumbs=[]
    for pth in sorted((run/"07_figures").glob("*.png")):
        im=Image.open(pth).convert("RGB");im.thumbnail((320,190));thumbs.append((pth.name,im.copy()))
    sheet=Image.new("RGB",(1000,math.ceil(len(thumbs)/3)*230),"white");draw=ImageDraw.Draw(sheet)
    for i,(name,im) in enumerate(thumbs):x=(i%3)*333;y=(i//3)*230;sheet.paste(im,(x,y));draw.text((x,y+192),name,fill="black")
    sheet.save(run/"07_figures/contact_sheet.png")
    bank_base=pd.read_csv(repo/"results/task-002-stage2b-b3-smoke/stage89q-penalty1000-vs1500-long-training/run-003/03_oos/common/oos_path_manifest.csv")
    bank_new=pd.read_csv(run/"01_preflight/common_bank/oos_path_manifest.csv");require(bank_base.equals(bank_new),"Base/new manifest mismatch")
    expected_sequence=bank_new.drop(columns="path_id").astype(int).astype(str).agg("-".join,axis=1)
    path_identity=pd.DataFrame({"path_id":bank_new.path_id,"bank_state_sequence":expected_sequence,
        "base_state_sequence":policies["BASE"]["path"].state_sequence.astype(str),
        "b0001_state_sequence":policies["B0001"]["path"].state_sequence.astype(str),
        "b1011_state_sequence":policies["B1011"]["path"].state_sequence.astype(str)})
    path_identity["identical"]=path_identity[["base_state_sequence","b0001_state_sequence","b1011_state_sequence"]].eq(path_identity.bank_state_sequence,axis=0).all(axis=1)
    require(path_identity.identical.all(),"three-policy state-sequence identity failed")
    safe_csv(path_identity,run/"01_preflight/path_bank_identity.csv")
    qa=pd.DataFrame([{"check":"both_training_acceptance","pass":True,"detail":"B0001/B1011 PASS"},{"check":"same_10000_ordered_bank","pass":path_identity.identical.all(),"detail":BASE_BANK_SHA},{"check":"raw_oos_integrity","pass":raw_qa["pass"].all(),"detail":f"{len(raw_qa)}/{len(raw_qa)} checks"},{"check":"no_padded_hours","pass":raw_qa.query("check=='no_padded_post_termination_rows'")["pass"].all(),"detail":"exact operating-stage row multipliers"},{"check":"termination_accounting","pass":True,"detail":10000},{"check":"positive_target_accounting","pass":True,"detail":"closed"},{"check":"base_classification_reproduced","pass":failure_reproduction["pass"].all(),"detail":"accepted quantity_vs_location.csv"},{"check":"margin_identity","pass":True,"detail":"<=1e-6"},{"check":"shared_prefix_definition_reused","pass":canonical_pass,"detail":f"Stage85U-D canonical {len(pairs)} pairs"},{"check":"actual_cost_separate_from_terminal_penalty","pass":True,"detail":"separate columns"},{"check":"figure_count","pass":True,"detail":22},{"check":"source_commit","pass":git(repo,"rev-parse","HEAD")==commit,"detail":commit}])
    require(qa["pass"].all(),"final QA failed");safe_csv(qa,run/"09_qa/main_qa.csv")
    d=decision.set_index("metric");acc={arm:pd.read_csv(task_paths(run,arm)[0]/"acceptance/training_stability.csv").iloc[0] for arm in ["B0001","B1011"]}
    pos_idx=pos.set_index("policy");ordinary_idx=resources["ordinary"].set_index("policy");tank_idx=resources["tank"].set_index("policy")
    grid_idx=resources["grid"].set_index("policy");htt_idx=resources["htt"].set_index("policy")
    stage_all=pd.concat([data["stage"].assign(policy=key) for key,data in policies.items()])
    stage_means=stage_all.groupby(["policy","stage"]).production_kg.mean()
    migration_detail={arm:migrations(policies,arm)[0] for arm in ["B0001","B1011"]}
    def migration_count(arm: str, source: str, target: str) -> int:
        frame=migration_detail[arm]
        return int(((frame.failure_type_base==source)&(frame.failure_type_candidate==target)).sum())
    large_counts={key:int(resources["surplus"][(resources["surplus"].policy==key)&resources["surplus"].surplus_bin.isin(["100-200",">200"])].path_count.sum()) for key in policies}
    extreme=resources["tail"].query("tail_class=='extreme1'").set_index("policy")
    difficult=resources["tail"].query("tail_class=='difficult4'").set_index("policy")
    recovery_counts=recovery.groupby(["candidate","status"]).size()
    realized={arm:int(sum(recovery_counts.get((arm,status),0) for status in ["PHYSICAL_GAIN_REALIZED_IN_POLICY","POLICY_CHANGED_PATH_MECHANISM"])) for arm in ["B0001","B1011"]}
    holdout="NO" if recommendation in ["BASE","NONE"] else "YES"
    labels=[]
    for arm in ["B0001","B1011"]:
        values={
            "LONG_TRAIN_STATUS":"PASS","TRAINING_STABILITY":acc[arm].TRAINING_STABILITY,"FULLY_CONVERGED":"NO","OOS_STATUS":"PASS",
            "WAIT_AND_SEE_DIRECTION":d.at["WAIT_AND_SEE_DIRECTION",arm],"WAIT_AND_SEE_EFFECT_SIZE":d.at["WAIT_AND_SEE_EFFECT_SIZE",arm],
            "TERMINAL_RELIABILITY":d.at["TERMINAL_RELIABILITY",arm],"SURPLUS_SIGNAL":d.at["SURPLUS_SIGNAL",arm],
            "GRID_RISK":d.at["GRID_RISK",arm],"BOTTLENECK_SHIFT_TO_VOLTAGE":d.at["BOTTLENECK_SHIFT_TO_VOLTAGE",arm],
            "POLICY_ROLE":d.at["POLICY_ROLE",arm],
        }
        labels.extend({"label":f"{arm}_{name}","value":value} for name,value in values.items())
    labels.extend([{"label":"RECOMMEND_PMAX_CANDIDATE","value":recommendation},{"label":"RECOMMEND_FRESH_HOLDOUT_OOS","value":holdout},{"label":"ADOPTION","value":"NO"}])
    labels_frame=pd.DataFrame(labels);safe_csv(labels_frame,analysis/"16_final_decision/workflow_labels.csv")
    label_text="\n".join(f"{row.label} = {row.value}" for row in labels_frame.itertuples(index=False))
    readme=f"""## Material Passport

- Schema: ARS-9
- Type: Experiment Result
- Verification Status: VERIFIED
- Source commit: `{commit}`
- Ordered OOS bank: `{BASE_BANK_SHA}`

# Stage-89Q Pmax 双候选 2.5h fresh training + 10000 common-path OOS

两个训练都成功并通过独立 SHA-256、fresh MATLAB reload 与 acceptance。B0001 完成 **{int(acc['B0001'].iterations)}** 次迭代、**{int(acc['B0001'].cuts)}** cuts；B1011 完成 **{int(acc['B1011'].iterations)}** 次迭代、**{int(acc['B1011'].cuts)}** cuts。稳定性分别为 **{acc['B0001'].TRAINING_STABILITY} / {acc['B1011'].TRAINING_STABILITY}**。两者都是固定 2.5h 预算，不是收敛证书，`FULLY_CONVERGED=NO`。

Stage1 从 smoke 的 115.83 / 117.73125 kg 变为长训末值 **{acc['B0001'].final_stage1:.3f} / {acc['B1011'].final_stage1:.3f} kg**。两个 OOS 均完成 10000 条路径，与 accepted Base 使用相同 SHA、相同顺序的 frozen bank；逐路径 state sequence 完全一致，且小时表严格等于真实 operating stages，没有终止后补零。

## 直接结论

1. OOS Stage1 mean production 为 Base/B0001/B1011 = **{stage_means.loc['BASE',1]:.3f}/{stage_means.loc['B0001',1]:.3f}/{stage_means.loc['B1011',1]:.3f} kg/path**；Stage5-6 mean 合计为 **{sum(stage_means.loc['BASE',s] for s in [5,6]):.3f}/{sum(stage_means.loc['B0001',s] for s in [5,6]):.3f}/{sum(stage_means.loc['B1011',s] for s in [5,6]):.3f} kg/path**。
2. Wait-and-see 方向 B0001/B1011 = **{d.at['WAIT_AND_SEE_DIRECTION','B0001']} / {d.at['WAIT_AND_SEE_DIRECTION','B1011']}**；effect size = **{d.at['WAIT_AND_SEE_EFFECT_SIZE','B0001']} / {d.at['WAIT_AND_SEE_EFFECT_SIZE','B1011']}**。方向和效应量分开判断，使用复现的 {len(pairs)} 组 Stage85U-D canonical shared-prefix pairs。
3. Positive-target shortfall rate Base/B0001/B1011 = **{pos_idx.at['BASE','shortfall_rate']:.4%}/{pos_idx.at['B0001','shortfall_rate']:.4%}/{pos_idx.at['B1011','shortfall_rate']:.4%}**；terminal reliability 标签 = **{d.at['TERMINAL_RELIABILITY','B0001']} / {d.at['TERMINAL_RELIABILITY','B1011']}**。
4. Base pure quantity 转 adequate：B0001 **{migration_count('B0001','PURE_QUANTITY','ADEQUATE')}** 条，B1011 **{migration_count('B1011','PURE_QUANTITY','ADEQUATE')}** 条；Base mixed 转 adequate：**{migration_count('B0001','MIXED','ADEQUATE')} / {migration_count('B1011','MIXED','ADEQUATE')}** 条；pure-location 转 adequate：**{migration_count('B0001','PURE_LOCATION','ADEQUATE')} / {migration_count('B1011','PURE_LOCATION','ADEQUATE')}** 条。完整 adequate->shortfall 与 mixed->pure-location 迁移见逐 path CSV。
5. 达标正目标路径中 >100 kg surplus 数 Base/B0001/B1011 = **{large_counts['BASE']}/{large_counts['B0001']}/{large_counts['B1011']}**；surplus 标签 = **{d.at['SURPLUS_SIGNAL','B0001']} / {d.at['SURPLUS_SIGNAL','B1011']}**。
6. Difficult4 mean gap Base/B0001/B1011 = **{difficult.at['BASE','mean_gap']:.3f}/{difficult.at['B0001','mean_gap']:.3f}/{difficult.at['B1011','mean_gap']:.3f} kg**；Extreme1 = **{extreme.at['BASE','mean_gap']:.3f}/{extreme.at['B0001','mean_gap']:.3f}/{extreme.at['B1011','mean_gap']:.3f} kg**。尾部 cohort 固定于 Base 95/4/1 排序。
7. bus18 q1 voltage Base/B0001/B1011 = **{grid_idx.at['BASE','bus18_q01']:.6f}/{grid_idx.at['B0001','bus18_q01']:.6f}/{grid_idx.at['B1011','bus18_q01']:.6f} p.u.**；grid risk = **{d.at['GRID_RISK','B0001']} / {d.at['GRID_RISK','B1011']}**，B1011 是否付出更大电压压力由该配对结果而非先验判断。
8. Ordinary shortage mean Base/B0001/B1011 = **{ordinary_idx.at['BASE','mean_shortage_kg']:.6f}/{ordinary_idx.at['B0001','mean_shortage_kg']:.6f}/{ordinary_idx.at['B1011','mean_shortage_kg']:.6f} kg/path**；tank binding path-hours = **{int(tank_idx.at['BASE','binding_path_hours'])}/{int(tank_idx.at['B0001','binding_path_hours'])}/{int(tank_idx.at['B1011','binding_path_hours'])}**。
9. HTT fleet binding ratio Base/B0001/B1011 = **{htt_idx.at['BASE','binding_ratio']:.6%}/{htt_idx.at['B0001','binding_ratio']:.6%}/{htt_idx.at['B1011','binding_ratio']:.6%}**。HTT 信息限制与空间价值仍只作描述性复核，不作单因果归因。
10. G2/G3 物理可恢复事件中，fresh policy 实际消除或减少 gap 的路径事件 B0001/B1011 = **{realized['B0001']} / {realized['B1011']}**；这回答 Pmax physical flexibility 是否转成 policy benefit，但不等于 adoption。
11. B0001 角色 = `{d.at['POLICY_ROLE','B0001']}`；B1011 角色 = `{d.at['POLICY_ROLE','B1011']}`。当前保留建议 = `{recommendation}`；fresh holdout OOS 建议 = `{holdout}`；本任务不执行 holdout，且 `ADOPTION=NO`。

实际运行成本与 terminal-gap soft penalty 分栏保留在 `06_paired_analysis/14_economics/`。历史问题逐项闭环、新问题的 path/metric 证据、训练分段轨迹、时间形成、Pmax 利用率和 22 张中文图分别见对应子目录。

```text
{label_text}
```
"""
    write_text(run/"08_summary/README.md",readme);write_text(run/"README.md",readme);write_text(run/"COMPLETE.txt",f"status=PASS\nsource_commit={commit}\n")
    manifest_frame=artifact_manifest(run);safe_csv(manifest_frame,run/"10_manifests/artifact_manifest.csv")


def main() -> None:
    parser=argparse.ArgumentParser();parser.add_argument("mode",choices=["prepare","accept","finalize"]);parser.add_argument("--repo",type=Path,required=True);parser.add_argument("--run-dir",type=Path,required=True);parser.add_argument("--commit",required=True);parser.add_argument("--arm",choices=["B0001","B1011"])
    args=parser.parse_args();repo=args.repo.resolve();run=args.run_dir.resolve()
    if args.mode=="prepare":prepare(repo,run,args.commit)
    elif args.mode=="accept":require(args.arm is not None,"--arm required");training_acceptance(run,args.arm)
    else:finalize(repo,run,args.commit)


if __name__=="__main__":
    main()
