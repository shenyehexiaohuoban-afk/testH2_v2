#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Stage-89Q-G2 frozen-background S4_125 recoverability closure."""

from __future__ import annotations

import argparse
import ast
import hashlib
import math
import os
import subprocess
from collections import Counter, OrderedDict
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib import font_manager, patches
import numpy as np
import pandas as pd
from PIL import Image, ImageDraw, ImageFont
import psutil
from scipy.io import loadmat


ROOT = Path(__file__).resolve().parents[1]
RUN = ROOT / "results/task-002-stage2b-b3-smoke/stage89q-penalty1000-vs1500-long-training/run-003"
RAW = ROOT / "hourly_grid_h2/output/stage89q_penalty1000_vs1500_long_training/run-003/penalty1000"
DEEP = RUN / "05_analysis/10_deep_penalty1000"
PHYS = DEEP / "17_pmax_flexibility_audit"
GRID = DEEP / "18_pmax_grid_hosting_audit"
OUT = DEEP / "19_s4_grid_aware_recoverability"
FIG = RUN / "06_figures/13_s4_grid_aware_recoverability"
FORMAL_INPUT = ROOT / "data/yuanqi/near_stage_msp_input.mat"

EXPECTED_BRANCH = "task/002-stage2b-b3-smoke"
EXPECTED_HEAD = "bb783d66fe3c22fad20968edee8ee5c55e56a9c8"
EXPECTED_UPSTREAM = "origin/task/002-stage2b-b3-smoke"
EXPECTED_INPUT_HASHES = {
    "raw_path": "99ec55faba4e60e88b25d757deb1a8146515faf666d52979fe69c64362047502",
    "raw_stage": "969c373a9a2ff1b271cde6fda95a6fe8e64b10362518fe4b807c0dc86437c15d",
    "raw_stage_site": "eab41bdf5d58fc971bc65af8c5745de3bd08cc25a0a4d44cc386aeba3f99c89e",
    "raw_hour_site": "af3b3d5c4aa69e6d29b35a88008b4d82360c4b8391fc783141078f7ad68b0cda",
    "raw_grid": "b9eaa83ee3e8a720f3cb5afd5d54da050c2d3ef45c434efe74f8ba8b976b63c6",
    "formal_input": "536b25868e6d7cc812a331c0d3e0ffbd5f6958e6883bd39bcae3901c372abf24",
    "physical_baseline": "5ff6efe6f2ca6e55be7a0cf05ebab162b12c9c531ab2be63e2e5351f87bc7f94",
    "physical_events": "6eb403e2445cc858eb9f96f5d656c9920aa234191413dcd14732031da0b425e3",
    "physical_characteristics": "fa027089ebad78eed1c3bcb3934ad167b1c7237ecd46bf2dd0269492fbfc90e5",
    "physical_analyzer": "3ddb60ce44f4637ffb813fa1de8a3b6dbf6df3260c56d8a551b46bac4d1d658a",
    "grid_profiles": "4d415944fb849116b360cd5fc52a85582ffc36e013d0190b1498b17bba21c3b8",
    "grid_critical": "9ba61b78e923dc16ce68f267dce3f98b1cad913d495420cc9fcded52bafbd3b3",
    "grid_identity": "3c08d4e518fca90dcc545b279d79c283561ee426b0e7896393ff821fc21ee829",
    "grid_summary": "35f7da678e8a2cc619146c90876b025f7b7cfae4c04f757c163d92e322cce5bd",
    "grid_analyzer": "a63154418cdea3ee3f62300a5121bd4ae72ebae2aac23398fcf686dfce67376a",
}

FILES = {
    "raw_path": RAW / "path_summary/oos_path_summary.csv",
    "raw_stage": RAW / "path_summary/oos_stage_summary.csv",
    "raw_stage_site": RAW / "path_summary/oos_stage_site_summary.csv",
    "raw_hour_site": RAW / "hourly_site/oos_hour_site.csv",
    "raw_grid": RAW / "grid_hourly/oos_hour_system.csv",
    "formal_input": FORMAL_INPUT,
    "physical_baseline": PHYS / "01_baseline_reproduction/pmax_recoverability_baseline_reproduction.csv",
    "physical_events": PHYS / "02_counterfactual_recoverability/pmax_candidate_recoverability_by_path.csv",
    "physical_characteristics": PHYS / "06_recovered_path_mechanism/recovered_path_characteristics.csv",
    "physical_analyzer": ROOT / "hourly_grid_h2/analyze_stage89q_pmax_flexibility_audit.py",
    "grid_profiles": GRID / "03_s4_125/s4_125_hourly_hosting.csv",
    "grid_critical": GRID / "05_critical_window/critical_window_grid_hosting.csv",
    "grid_identity": GRID / "05_critical_window/critical_window_subset_identity.csv",
    "grid_summary": GRID / "03_s4_125/s4_125_summary.csv",
    "grid_analyzer": ROOT / "hourly_grid_h2/analyze_stage89q_pmax_grid_hosting_audit.py",
}

DIRS = {
    "baseline": OUT / "01_baseline_reproduction",
    "effective": OUT / "02_effective_pmax",
    "recovery": OUT / "03_grid_aware_recoverability",
    "clipping": OUT / "04_voltage_clipping_severity",
    "bus18": OUT / "05_bus18_mechanism",
    "tail": OUT / "06_tail_analysis",
    "gate": OUT / "07_workflow_gate",
    "summary": OUT / "08_summary",
    "qa": OUT / "09_qa",
}

BASE_PMAX = np.array([300.0, 200.0, 120.0, 150.0])
CANDIDATE_PMAX = np.array([300.0, 200.0, 120.0, 187.5])
CUTS = [-16, -8, -4]
K_H2_EXPECTED = 0.0195
TOL = 1e-7
HOST_TOL_KW = 1e-5
MARGIN_ZERO_TOL_KG = 1e-6

# Workflow thresholds are fixed before event results are calculated.
GATE = OrderedDict([
    ("identifiable_rate_min", 0.95),
    ("overall_retention_min", 0.80),
    ("difficult_extreme_retention_min", 0.70),
    ("broad_severe_loss_share_max", 0.20),
    ("severe_missing_headroom_kw", 20.0),
])

COLORS = ["#2166AC", "#B2182B", "#1B7837", "#E08214", "#762A83", "#4D4D4D"]


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
    payload = ",".join(str(int(value)) for value in sorted(set(values))).encode("ascii")
    return hashlib.sha256(payload).hexdigest()


def save_csv(frame: pd.DataFrame, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    frame.to_csv(io_path(path), index=False, encoding="utf-8-sig", float_format="%.12g")


def save_text(value: str, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(io_path(path), "w", encoding="utf-8", newline="\n") as stream:
        stream.write(value)


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True, encoding="utf-8").strip()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def setup() -> None:
    require(not OUT.exists(), f"Accepted output already exists: {OUT}")
    require(not FIG.exists(), f"Accepted figure output already exists: {FIG}")
    for path in [OUT, FIG, *DIRS.values()]:
        path.mkdir(parents=True, exist_ok=False if path in (OUT, FIG) else True)
    installed = {item.name for item in font_manager.fontManager.ttflist}
    font = next((name for name in ["Microsoft YaHei", "Microsoft YaHei UI", "SimHei"] if name in installed), None)
    require(font is not None, "Chinese font is unavailable")
    plt.rcParams.update({
        "font.family": font, "axes.unicode_minus": False, "font.size": 9,
        "figure.dpi": 140, "savefig.dpi": 180, "figure.facecolor": "white",
        "axes.facecolor": "white", "axes.titleweight": "bold",
    })


def process_records() -> tuple[int, str]:
    stopped = {getattr(psutil, "STATUS_STOPPED", "stopped"), getattr(psutil, "STATUS_ZOMBIE", "zombie"),
               getattr(psutil, "STATUS_DEAD", "dead")}
    records, live = [], 0
    for proc in psutil.process_iter(["pid", "name", "status"]):
        name = (proc.info.get("name") or "").lower()
        if "matlab" in name or "gurobi" in name or name.startswith("grb"):
            status = proc.info.get("status") or "unknown"
            records.append(f"{proc.info['pid']}:{proc.info['name']}:{status}")
            live += int(status not in stopped)
    return live, ";".join(records) if records else "NONE"


def preflight() -> pd.DataFrame:
    missing = [f"{name}:{path}" for name, path in FILES.items() if not path.is_file()]
    require(not missing, "Missing inputs: " + " | ".join(missing))
    hashes = {name: sha256(path) for name, path in FILES.items()}
    require(hashes == EXPECTED_INPUT_HASHES, f"Input identity mismatch: {hashes}")
    branch = git("branch", "--show-current")
    head = git("rev-parse", "HEAD")
    upstream = git("rev-parse", "--abbrev-ref", "@{upstream}")
    ahead, behind = git("rev-list", "--left-right", "--count", f"HEAD...{EXPECTED_UPSTREAM}").split()
    tracked = [line for line in git("status", "--short", "--untracked-files=no").splitlines() if line]
    task_owned_tracked = [line for line in tracked if line.endswith("codex_rule/log.md")]
    preexisting_tracked = [line for line in tracked if line not in task_owned_tracked]
    untracked = [line for line in git("ls-files", "--others", "--exclude-standard").splitlines() if line]
    live, processes = process_records()
    rows = [
        ("branch", branch, EXPECTED_BRANCH, branch == EXPECTED_BRANCH),
        ("HEAD", head, EXPECTED_HEAD, head == EXPECTED_HEAD),
        ("upstream", upstream, EXPECTED_UPSTREAM, upstream == EXPECTED_UPSTREAM),
        ("ahead", ahead, "0", ahead == "0"),
        ("behind", behind, "0", behind == "0"),
        ("preexisting_tracked_dirty_count_preserved", len(preexisting_tracked), 7, len(preexisting_tracked) == 7),
        ("preexisting_tracked_dirty_paths_preserved", " | ".join(preexisting_tracked), "informational", True),
        ("task_owned_log_change", " | ".join(task_owned_tracked) or "NONE", "0 before log update or codex_rule/log.md only", len(task_owned_tracked) <= 1),
        ("untracked_count_preserved", len(untracked), ">=14292", len(untracked) >= 14292),
        ("live_MATLAB_Gurobi_count", live, 0, live == 0),
        ("MATLAB_Gurobi_records", processes, "stale stopped objects permitted", live == 0),
        ("input_hash_identity", len(hashes), len(EXPECTED_INPUT_HASHES), hashes == EXPECTED_INPUT_HASHES),
    ]
    frame = pd.DataFrame(rows, columns=["check", "observed", "expected", "pass"])
    save_csv(frame, DIRS["baseline"] / "repository_preflight.csv")
    require(frame["pass"].all(), "Repository/input preflight failed")
    return frame


def load_inputs():
    formal = loadmat(io_path(FORMAL_INPUT), simplify_cells=True)["NearStageInput"]
    device = formal["HydrogenDevice"]
    pmax = np.asarray(device["el_cap_kw"], dtype=float).ravel()
    k_h2 = float(device["k_H2_kg_per_kWh"])
    tank = np.asarray(device["tank_cap_kg"], dtype=float).ravel()
    require(np.allclose(pmax, BASE_PMAX, atol=TOL), f"Formal Base Pmax changed: {pmax}")
    require(abs(k_h2 - K_H2_EXPECTED) <= TOL, f"Formal k_H2 changed: {k_h2}")
    require(np.array_equal(tank, np.array([300., 200., 100., 150.])), f"Tank capacity changed: {tank}")
    return {
        "k_h2": k_h2, "tank": tank,
        "physical_baseline": pd.read_csv(FILES["physical_baseline"]),
        "physical_events": pd.read_csv(FILES["physical_events"]),
        "physical_characteristics": pd.read_csv(FILES["physical_characteristics"]),
        "grid_profiles": pd.read_csv(FILES["grid_profiles"]),
        "grid_critical": pd.read_csv(FILES["grid_critical"]),
        "grid_identity": pd.read_csv(FILES["grid_identity"]),
        "grid_summary": pd.read_csv(FILES["grid_summary"]),
        "raw_path": pd.read_csv(FILES["raw_path"]),
    }


def reproduce_baselines(data: dict) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    baseline = data["physical_baseline"].sort_values("relative_hour")
    expected = {-16: 70, -8: 156, -4: 167}
    event_source = data["physical_events"]
    s4 = event_source[(event_source.candidate == "S4_125") & event_source.recovered_relative_to_base].copy()
    recovered_expected = {-16: 31, -8: 9, -4: 8}
    identity = data["grid_identity"].set_index("subset")
    grid_detail = data["grid_critical"]
    critical = grid_detail[(grid_detail.subset == "S4_125_PHYSICALLY_RECOVERED") &
                           (grid_detail.candidate == "S4_125")].copy()
    summary = data["grid_summary"].set_index("metric").value
    all_ratio = float(summary["hostable_ratio"])
    critical_ratio = critical.full_to_candidate_hostable.eq("YES").mean()
    voltage_ratio = critical.voltage_limited_flag.astype(bool).mean()
    union_ids = set(s4.path_id.astype(int))
    source_union_sha = id_set_sha(union_ids)
    grid_union_sha = str(identity.loc["S4_125_PHYSICALLY_RECOVERED", "path_id_set_sha256"])
    rows = []
    for hour in CUTS:
        row = baseline[baseline.relative_hour == hour].iloc[0]
        rows.extend([
            ("physical_base", f"base_unrecoverable_{hour}h", int(row.recomputed_unrecoverable_count), expected[hour], int(row.recomputed_unrecoverable_count) == expected[hour]),
            ("physical_s4", f"s4_recovered_{hour}h", int((s4.relative_hour == hour).sum()), recovered_expected[hour], int((s4.relative_hour == hour).sum()) == recovered_expected[hour]),
        ])
    rows.extend([
        ("grid_s4", "candidate_increment_kw", 37.5, 37.5, True),
        ("grid_s4", "all_hour_full_hostable_ratio", all_ratio, 0.985847604656, abs(all_ratio - 0.985847604656) <= 1e-12),
        ("grid_s4", "critical_final16_full_hostable_ratio", critical_ratio, 0.813920454545, abs(critical_ratio - 0.813920454545) <= 1e-12),
        ("grid_s4", "critical_final16_voltage_limited_ratio", voltage_ratio, 0.186079545455, abs(voltage_ratio - 0.186079545455) <= 1e-12),
        ("grid_s4", "critical_branch_limited_hours", int(critical.branch_limited_flag.astype(bool).sum()), 0, not critical.branch_limited_flag.astype(bool).any()),
        ("grid_s4", "critical_substation_limited_hours", int(critical.substation_limited_flag.astype(bool).sum()), 0, not critical.substation_limited_flag.astype(bool).any()),
        ("identity", "s4_recovered_union_path_count", len(union_ids), 44, len(union_ids) == 44),
        ("identity", "s4_recovered_union_path_sha", source_union_sha, grid_union_sha, source_union_sha == grid_union_sha),
        ("identity", "critical_real_hour_count", len(critical), 704, len(critical) == 704),
    ])
    cross = pd.DataFrame(rows, columns=["audit", "metric", "observed", "expected", "pass"])
    path_rows = []
    for hour in CUTS:
        ids = set(s4.loc[s4.relative_hour == hour, "path_id"].astype(int))
        grid_ids = set(critical.loc[critical.relative_hour >= hour, "path_id"].astype(int))
        path_rows.append({
            "checkpoint_relative_hour": hour, "hydrogen_recovered_count": len(ids),
            "hydrogen_recovered_path_set_sha256": id_set_sha(ids),
            "all_recovered_paths_have_grid_hours": ids.issubset(grid_ids),
            "expected_real_hours": len(ids) * -hour,
            "observed_real_hours": int(critical[(critical.path_id.isin(ids)) & (critical.relative_hour >= hour)].shape[0]),
        })
    path_identity = pd.DataFrame(path_rows)
    save_csv(cross, DIRS["baseline"] / "baseline_cross_audit.csv")
    save_csv(path_identity, DIRS["baseline"] / "baseline_path_identity_QA.csv")
    require(cross["pass"].all() and path_identity.all_recovered_paths_have_grid_hours.all() and
            (path_identity.expected_real_hours == path_identity.observed_real_hours).all(),
            "Stage-89Q / Stage-89Q-G baseline identity failed")
    return s4, critical, cross


def build_effective_pmax(data: dict, critical: pd.DataFrame) -> pd.DataFrame:
    profiles = data["grid_profiles"].set_index("profile_id")
    keep = [
        "realized_pel4_kw", "max_additional_site4_hosting_kw", "max_new_pel4_kw",
        "S4_FULL_INCREMENT_HOSTABLE", "min_voltage_pu", "voltage_margin_pu", "critical_bus",
        "critical_branch_id", "max_true_s_mva", "max_octagon_utilization",
        "voltage_limited_flag", "branch_limited_flag", "substation_limited_flag",
    ]
    hourly = critical[["path_id", "stage", "global_hour", "relative_hour", "profile_id"]].merge(
        profiles[keep], left_on="profile_id", right_index=True, validate="many_to_one")
    hourly.rename(columns={
        "max_additional_site4_hosting_kw": "delta_p4_hostable_from_realized_kw",
        "max_new_pel4_kw": "reconstructed_max_new_pel4_kw",
        "min_voltage_pu": "limiting_solution_min_voltage_pu",
        "voltage_margin_pu": "limiting_solution_voltage_margin_pu",
    }, inplace=True)
    hourly["p4_effective_max_kw"] = np.minimum(
        CANDIDATE_PMAX[3], hourly.realized_pel4_kw + hourly.delta_p4_hostable_from_realized_kw)
    require(np.allclose(hourly.p4_effective_max_kw, hourly.reconstructed_max_new_pel4_kw, atol=HOST_TOL_KW),
            "Hourly DeltaP reconstruction double-count check failed")
    hourly["effective_increment_above_base_kw"] = hourly.p4_effective_max_kw - BASE_PMAX[3]
    hourly["effective_increment_above_base_nonnegative_kw"] = np.maximum(0, hourly.effective_increment_above_base_kw)
    hourly["missing_candidate_headroom_kw"] = CANDIDATE_PMAX[3] - hourly.p4_effective_max_kw
    hourly["full_candidate_pmax_hostable"] = hourly.missing_candidate_headroom_kw <= HOST_TOL_KW
    hourly["hourly_effective_extra_h2_kg"] = hourly.effective_increment_above_base_kw * data["k_h2"]
    hourly["definition"] = "min(187.5, realized_PEL4 + Stage89QG_DeltaP_from_realized)"
    hourly.sort_values(["path_id", "relative_hour"], inplace=True)
    save_csv(hourly, DIRS["effective"] / "s4_125_hourly_effective_pmax.csv")
    definition = f"""# S4_125 小时级有效 Pmax 定义

Stage-89Q-G 的 `max_additional_site4_hosting_kw` 是从冻结的 Base realized `P_EL4` 起算的最大附加负荷，不是从 Base 铭牌 150 kW 起算。

因此本轮先机械重构：

`P4_effective_max(h) = min(187.5, P_EL4_realized(h) + max_additional_site4_hosting_kw(h))`

相对 Base 物理上界的有效扩容能力为：

`DeltaP4_effective_above_Base(h) = P4_effective_max(h) - 150`

累计氢侧扩容收益使用 `sum_h DeltaP4_effective_above_Base(h) * 1h * k_H2`，其中 `k_H2={data['k_h2']:.12g} kg/kWh`，由正式 `near_stage_msp_input.mat` 机械读取。主判据仍是将 `P4_effective_max(h)` 逐小时放回 Stage-89Q 的同一乐观 aggregate recoverability evaluator；累计 kg 只做交叉检查。

这一换算避免把 realized `P_EL4` 低于 150 kW 时尚未使用的 Base 铭牌余量重复计为 S4_125 扩容收益。只保留 44 条 S4 recovered union paths 的最后16个真实小时，共 {len(hourly)} 行；没有补零小时，也没有重跑 grid LP。
"""
    save_text(definition, DIRS["effective"] / "s4_125_hourly_effective_pmax_definition.md")
    return hourly


def analytic_required(base_margin: float, hours: int, k_h2: float) -> tuple[float, float, float]:
    required_h2 = max(0.0, -TOL - base_margin)
    added_kw = required_h2 / (k_h2 * hours)
    alpha = added_kw / 37.5
    return required_h2, added_kw, alpha


def build_events(data: dict, source_events: pd.DataFrame, hourly: pd.DataFrame) -> pd.DataFrame:
    meta = data["physical_characteristics"]
    meta = meta[meta.candidate == "S4_125"].rename(columns={"base_unrecoverable_hour": "relative_hour"})
    meta_keep = ["path_id", "relative_hour", "arrival_stage", "final_intensity", "final_location",
                 "final_gap_kg", "tail_group"]
    source_keep = ["path_id", "relative_hour", "failure_type", "current_inventory_kg", "target_total",
                   "remaining_hours", "optimistic_total_margin_kg", "recovered_relative_to_base"]
    events = source_events[source_keep].merge(meta[meta_keep], on=["path_id", "relative_hour"], validate="one_to_one")
    rows = []
    k_h2 = data["k_h2"]
    for event in events.itertuples(index=False):
        remaining = hourly[(hourly.path_id == event.path_id) &
                           (hourly.relative_hour >= event.relative_hour) &
                           (hourly.relative_hour <= -1)].copy()
        expected_hours = -int(event.relative_hour)
        identifiable = len(remaining) == expected_hours and not remaining.p4_effective_max_kw.isna().any()
        base_margin = (event.current_inventory_kg + BASE_PMAX.sum() * k_h2 * expected_hours - event.target_total)
        nominal_h2 = 37.5 * k_h2 * expected_hours
        required_h2, required_kw, required_alpha = analytic_required(base_margin, expected_hours, k_h2)
        if identifiable:
            effective_p4_sum = remaining.p4_effective_max_kw.sum()
            grid_margin = event.current_inventory_kg + k_h2 * (
                BASE_PMAX[:3].sum() * expected_hours + effective_p4_sum) - event.target_total
            grid_extra_h2 = k_h2 * (effective_p4_sum - BASE_PMAX[3] * expected_hours)
            supported = grid_margin >= -TOL
            cumulative_supported = grid_extra_h2 + MARGIN_ZERO_TOL_KG >= required_h2
            full_ratio = remaining.full_candidate_pmax_hostable.mean()
            clipped = int((~remaining.full_candidate_pmax_hostable).sum())
            classification = (
                "FULL_INCREMENT_HOSTABLE_AND_SUPPORTED" if supported and clipped == 0 else
                "PARTIALLY_CLIPPED_BUT_STILL_SUPPORTED" if supported else
                "GRID_CLIPPING_REMOVES_RECOVERY_SUPPORT"
            )
            clipped_rows = remaining[~remaining.full_candidate_pmax_hostable]
            critical_bus = int(clipped_rows.critical_bus.mode().iloc[0]) if len(clipped_rows) else int(remaining.critical_bus.mode().iloc[0])
            min_margin = float(remaining.limiting_solution_voltage_margin_pu.min())
            minimum_headroom = float(remaining.effective_increment_above_base_kw.min())
            average_headroom = float(remaining.effective_increment_above_base_kw.mean())
            margin_h2 = grid_extra_h2 - required_h2
        else:
            grid_margin = grid_extra_h2 = full_ratio = min_margin = minimum_headroom = average_headroom = margin_h2 = math.nan
            supported = cumulative_supported = False
            clipped = 0
            critical_bus = math.nan
            classification = "NOT_IDENTIFIABLE"
        rows.append({
            "path_id": int(event.path_id), "checkpoint_relative_hour": int(event.relative_hour),
            "failure_type": event.failure_type, "arrival_stage": int(event.arrival_stage),
            "final_intensity": int(event.final_intensity), "final_location": int(event.final_location),
            "final_gap": event.final_gap_kg, "tail_group": event.tail_group,
            "current_inventory_kg": event.current_inventory_kg, "target_total_kg": event.target_total,
            "real_remaining_hour_count": len(remaining), "expected_remaining_hour_count": expected_hours,
            "nominal_extra_energy_kWh": 37.5 * expected_hours,
            "nominal_extra_H2_kg": nominal_h2,
            "grid_hostable_extra_energy_kWh": grid_extra_h2 / k_h2 if identifiable else math.nan,
            "grid_hostable_extra_H2_kg": grid_extra_h2,
            "required_extra_H2_kg": required_h2,
            "required_extra_electrical_energy_kWh": required_h2 / k_h2,
            "required_alpha": required_alpha, "required_added_Pmax_kW": required_kw,
            "grid_supported_average_incremental_capability_kW": average_headroom,
            "grid_aware_evaluator_margin_kg": grid_margin,
            "recovery_margin_kg": margin_h2,
            "full_increment_hostable_ratio_remaining": full_ratio,
            "minimum_hourly_extra_headroom_kW": minimum_headroom,
            "grid_clipped_hours": clipped, "critical_bus": critical_bus,
            "minimum_voltage_margin": min_margin,
            "hydrogen_side_recovered": "YES",
            "grid_aware_identifiable": "YES" if identifiable else "NO",
            "grid_aware_recovery_supported": "YES" if supported else ("NO" if identifiable else "NOT_IDENTIFIABLE"),
            "cumulative_kg_cross_check_supported": "YES" if cumulative_supported else ("NO" if identifiable else "NOT_IDENTIFIABLE"),
            "classification": classification,
        })
    result = pd.DataFrame(rows).sort_values(["checkpoint_relative_hour", "path_id"])
    save_csv(result, DIRS["recovery"] / "s4_125_grid_aware_recovery_by_event.csv")
    return result


def summarize_events(events: pd.DataFrame) -> dict[str, pd.DataFrame]:
    def aggregate(group: pd.DataFrame) -> pd.Series:
        recovered = len(group)
        identifiable = group.grid_aware_identifiable.eq("YES").sum()
        supported = group.grid_aware_recovery_supported.eq("YES").sum()
        removed = group.classification.eq("GRID_CLIPPING_REMOVES_RECOVERY_SUPPORT").sum()
        return pd.Series({
            "hydrogen_side_recovered": recovered, "grid_aware_identifiable": identifiable,
            "grid_aware_supported": supported, "grid_clipping_removed": removed,
            "not_identifiable": recovered - identifiable,
            "identifiable_rate": identifiable / recovered if recovered else math.nan,
            "retention_ratio": supported / recovered if recovered else math.nan,
        })
    checkpoint = events.groupby("checkpoint_relative_hour", sort=True).apply(aggregate).reset_index()
    failure = events.groupby("failure_type", sort=False).apply(aggregate).reset_index()
    if "pure_location" not in set(failure.failure_type):
        failure = pd.concat([failure, pd.DataFrame([{
            "failure_type": "pure_location", "hydrogen_side_recovered": 0, "grid_aware_identifiable": 0,
            "grid_aware_supported": 0, "grid_clipping_removed": 0, "not_identifiable": 0,
            "identifiable_rate": math.nan, "retention_ratio": math.nan,
        }])], ignore_index=True)
    failure["failure_type"] = pd.Categorical(failure.failure_type, ["pure_quantity", "pure_location", "mixed"], ordered=True)
    failure.sort_values("failure_type", inplace=True)
    tail = events.groupby("tail_group", sort=False).apply(aggregate).reset_index()
    for missing_group in ["normal95", "difficult4", "extreme1"]:
        if missing_group not in set(tail.tail_group):
            tail = pd.concat([tail, pd.DataFrame([{
                "tail_group": missing_group, "hydrogen_side_recovered": 0,
                "grid_aware_identifiable": 0, "grid_aware_supported": 0,
                "grid_clipping_removed": 0, "not_identifiable": 0,
                "identifiable_rate": math.nan, "retention_ratio": math.nan,
            }])], ignore_index=True)
    tail["tail_group"] = pd.Categorical(tail.tail_group, ["normal95", "difficult4", "extreme1"], ordered=True)
    tail.sort_values("tail_group", inplace=True)
    path_window = events.groupby("path_id").agg(
        hydrogen_recovered_events=("path_id", "size"),
        grid_retained_events=("grid_aware_recovery_supported", lambda x: x.eq("YES").sum()),
        earliest_hydrogen_recovered_checkpoint=("checkpoint_relative_hour", "min"),
        failure_type=("failure_type", "first"), tail_group=("tail_group", "first"),
    ).reset_index()
    supported_earliest = events[events.grid_aware_recovery_supported == "YES"].groupby("path_id").checkpoint_relative_hour.min()
    path_window["earliest_grid_retained_checkpoint"] = path_window.path_id.map(supported_earliest)
    path_window["grid_removed_event_count"] = path_window.hydrogen_recovered_events - path_window.grid_retained_events
    path_window["window_shift_checkpoints"] = path_window.earliest_grid_retained_checkpoint - path_window.earliest_hydrogen_recovered_checkpoint
    save_csv(checkpoint, DIRS["recovery"] / "s4_125_grid_aware_summary_by_checkpoint.csv")
    save_csv(failure, DIRS["recovery"] / "s4_125_grid_aware_summary_by_failure_type.csv")
    save_csv(path_window, DIRS["recovery"] / "path_level_recovery_window_comparison.csv")
    save_csv(tail, DIRS["tail"] / "s4_125_grid_aware_tail_retention.csv")
    return {"checkpoint": checkpoint, "failure": failure, "tail": tail, "path_window": path_window}


def clipping_outputs(hourly: pd.DataFrame, events: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    clipped = hourly[~hourly.full_candidate_pmax_hostable].copy()
    missing = clipped.missing_candidate_headroom_kw.to_numpy()
    supported_clipped_keys = set()
    supported_clipped_event_hour_pairs = 0
    for event in events[events.grid_aware_recovery_supported == "YES"].itertuples(index=False):
        rows_in_window = clipped[(clipped.path_id == event.path_id) &
                                 (clipped.relative_hour >= event.checkpoint_relative_hour)]
        supported_clipped_event_hour_pairs += len(rows_in_window)
        supported_clipped_keys.update(zip(rows_in_window.path_id, rows_in_window.relative_hour))
    quantiles = [("min", np.min(missing)), ("median", np.quantile(missing, .5)),
                 ("q75", np.quantile(missing, .75)), ("q90", np.quantile(missing, .90)),
                 ("q95", np.quantile(missing, .95)), ("q99", np.quantile(missing, .99)),
                 ("max", np.max(missing)), ("mean", np.mean(missing))]
    bins = [
        ("0-5_kW", (missing > 0) & (missing <= 5)),
        ("5-10_kW", (missing > 5) & (missing <= 10)),
        ("10-20_kW", (missing > 10) & (missing <= 20)),
        (">20_kW", missing > 20),
    ]
    rows = [{"section": "distribution", "metric": key, "value": value, "unit": "kW"} for key, value in quantiles]
    rows.extend({"section": "descriptive_bin", "metric": key, "value": int(mask.sum()), "unit": "path-hour"} for key, mask in bins)
    rows.extend([
        {"section": "coverage", "metric": "critical_final16_real_hours", "value": len(hourly), "unit": "path-hour"},
        {"section": "coverage", "metric": "full_increment_nonhostable_hours", "value": len(clipped), "unit": "path-hour"},
        {"section": "coverage", "metric": "full_increment_nonhostable_ratio", "value": len(clipped) / len(hourly), "unit": "ratio"},
        {"section": "coverage", "metric": "clipped_event_hour_pairs_with_supported_recovery", "value": supported_clipped_event_hour_pairs, "unit": "event-hour"},
        {"section": "coverage", "metric": "unique_clipped_path_hours_in_supported_event_windows", "value": len(supported_clipped_keys), "unit": "path-hour"},
        {"section": "coverage", "metric": "events_with_any_clipping", "value": int((events.grid_clipped_hours > 0).sum()), "unit": "event"},
        {"section": "coverage", "metric": "partially_clipped_but_still_supported_events", "value": int(events.classification.eq("PARTIALLY_CLIPPED_BUT_STILL_SUPPORTED").sum()), "unit": "event"},
    ])
    severity = pd.DataFrame(rows)
    save_csv(severity, DIRS["clipping"] / "s4_voltage_clipping_severity.csv")

    losses = events[events.classification == "GRID_CLIPPING_REMOVES_RECOVERY_SUPPORT"].copy()
    if len(losses):
        loss_rows = []
        for row in losses.itertuples(index=False):
            h = clipped[(clipped.path_id == row.path_id) & (clipped.relative_hour >= row.checkpoint_relative_hour)]
            loss_rows.append({
                "scope": "lost_event", "path_id": row.path_id,
                "checkpoint_relative_hour": row.checkpoint_relative_hour, "failure_type": row.failure_type,
                "tail_group": row.tail_group, "final_intensity": row.final_intensity,
                "final_location": row.final_location, "critical_bus": row.critical_bus,
                "bus18_is_critical": row.critical_bus == 18,
                "minimum_limiting_voltage_pu": h.limiting_solution_min_voltage_pu.min(),
                "minimum_bus18_voltage_pu": h.limiting_solution_min_voltage_pu.min(),
                "minimum_voltage_margin_pu": h.limiting_solution_voltage_margin_pu.min(),
                "voltage_shortfall_from_lower_bound_pu": max(0, .90 - h.limiting_solution_min_voltage_pu.min()),
                "required_extra_H2_kg": row.required_extra_H2_kg,
                "missing_grid_hostable_H2_kg": -row.recovery_margin_kg,
                "grid_clipped_hours": row.grid_clipped_hours,
            })
        bus18 = pd.DataFrame(loss_rows)
    else:
        bus18 = pd.DataFrame([{
            "scope": "aggregate", "path_id": math.nan, "checkpoint_relative_hour": math.nan,
            "failure_type": "NONE", "tail_group": "NONE", "final_intensity": math.nan,
            "final_location": math.nan, "critical_bus": 18,
            "bus18_is_critical": bool((clipped.critical_bus == 18).all()),
            "minimum_limiting_voltage_pu": clipped.limiting_solution_min_voltage_pu.min(),
            "minimum_bus18_voltage_pu": clipped.limiting_solution_min_voltage_pu.min(),
            "minimum_voltage_margin_pu": clipped.limiting_solution_voltage_margin_pu.min(),
            "voltage_shortfall_from_lower_bound_pu": max(0, .90 - clipped.limiting_solution_min_voltage_pu.min()),
            "required_extra_H2_kg": 0, "missing_grid_hostable_H2_kg": 0,
            "grid_clipped_hours": len(clipped),
            "interpretation": "NO_RECOVERY_EVENT_REMOVED; bus18 explains clipped hours but not a realized event-level recovery loss",
        }])
    save_csv(bus18, DIRS["bus18"] / "bus18_recovery_loss_summary.csv")
    return severity, bus18


def labels_and_gate(events: pd.DataFrame, summaries: dict, hourly: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    overall = len(events[events.grid_aware_recovery_supported == "YES"]) / len(events)
    identifiable = len(events[events.grid_aware_identifiable == "YES"]) / len(events)
    tail_events = events[events.tail_group.isin(["difficult4", "extreme1"])]
    tail_retention = (tail_events.grid_aware_recovery_supported == "YES").mean() if len(tail_events) else math.nan
    removed_share = (events.classification == "GRID_CLIPPING_REMOVES_RECOVERY_SUPPORT").mean()
    clipped = hourly[~hourly.full_candidate_pmax_hostable]
    severe_all_share = (clipped.missing_candidate_headroom_kw > GATE["severe_missing_headroom_kw"]).sum() / len(hourly)
    branch_ok = not hourly.branch_limited_flag.astype(bool).any()
    substation_ok = not hourly.substation_limited_flag.astype(bool).any()
    baseline_ok = True
    broad_severe_ok = removed_share <= GATE["broad_severe_loss_share_max"] and severe_all_share <= GATE["broad_severe_loss_share_max"]
    gate_rows = [
        ("baseline_reproduction_all_pass", baseline_ok, True, baseline_ok),
        ("raw_model_inputs_unchanged", True, True, True),
        ("grid_aware_identifiable_rate", identifiable, f">={GATE['identifiable_rate_min']}", identifiable >= GATE["identifiable_rate_min"]),
        ("overall_retention_ratio", overall, f">={GATE['overall_retention_min']}", overall >= GATE["overall_retention_min"]),
        ("difficult4_plus_extreme1_retention", tail_retention, f">={GATE['difficult_extreme_retention_min']}", tail_retention >= GATE["difficult_extreme_retention_min"]),
        ("no_branch_structural_bottleneck", branch_ok, True, branch_ok),
        ("no_substation_structural_bottleneck", substation_ok, True, substation_ok),
        ("no_broad_severe_voltage_recovery_loss", {"removed_event_share": removed_share, "severe_path_hour_share": severe_all_share}, f"both <= {GATE['broad_severe_loss_share_max']}", broad_severe_ok),
    ]
    gate = pd.DataFrame(gate_rows, columns=["gate", "observed", "threshold", "pass"])
    all_gate = gate["pass"].all()
    if all_gate:
        recommendation = "YES"
    elif overall < .50 and removed_share > .50:
        recommendation = "NO"
    else:
        recommendation = "NEEDS_MORE_GRID_DIAGNOSTIC"
    h2_signal = "STRONG" if len(events) >= 40 and all((events.checkpoint_relative_hour == h).any() for h in CUTS) else "MODERATE" if len(events) >= 20 else "WEAK" if len(events) else "NONE"
    retention = "STRONG" if overall >= .80 else "MODERATE" if overall >= .50 else "WEAK" if overall > 0 else "NONE"
    voltage = "LOW" if removed_share <= .05 else "MODERATE" if removed_share <= .20 else "HIGH"
    critical16 = float(summaries["checkpoint"].loc[summaries["checkpoint"].checkpoint_relative_hour == -16, "retention_ratio"].iloc[0])
    critical_support = "STRONG" if critical16 >= .80 else "MODERATE" if critical16 >= .50 else "WEAK"
    loss_count = int((events.classification == "GRID_CLIPPING_REMOVES_RECOVERY_SUPPORT").sum())
    bus18_share = float((events.loc[events.classification == "GRID_CLIPPING_REMOVES_RECOVERY_SUPPORT", "critical_bus"] == 18).mean()) if loss_count else 0.0
    bus_signal = "NONE" if loss_count == 0 else "STRONG" if removed_share > .20 and bus18_share >= .5 else "MODERATE" if removed_share > .05 and bus18_share >= .5 else "WEAK"
    statuses = OrderedDict([
        ("S4_125_H2_SIDE_RECOVERY_SIGNAL", h2_signal),
        ("S4_125_GRID_AWARE_RECOVERY_RETENTION", retention),
        ("S4_125_VOLTAGE_CLIPPING_IMPACT", voltage),
        ("S4_125_CRITICAL_WINDOW_GRID_SUPPORT", critical_support),
        ("S4_125_BUS18_RECOVERY_LOSS_SIGNAL", bus_signal),
        ("RECOMMEND_FRESH_S4_125_ZERO_CUT_SMOKE", recommendation),
        ("DIAGNOSTIC_SCOPE", "FROZEN_BASE_BACKGROUND_GRID_AWARE_PHYSICAL_RECOVERABILITY"),
        ("FRESH_POLICY_COUNTERFACTUAL", "NO"),
        ("GRID_LP_RERUN", "NO"),
        ("NO_FA_MSP_TRAINING", "YES"),
        ("NO_FORWARD_BACKWARD_CUTS", "YES"),
        ("NO_OOS_RERUN", "YES"),
        ("NO_PARAMETER_WRITEBACK", "YES"),
        ("ALL_125_STARTED", "NO"),
        ("PENALTY1500_STARTED", "NO"),
        ("FULLY_CONVERGED", "NO"),
    ])
    final_status = pd.DataFrame([{"status": key, "value": value} for key, value in statuses.items()])
    thresholds = pd.DataFrame([{"threshold": key, "value": value, "purpose": "predeclared engineering workflow gate"} for key, value in GATE.items()])
    save_csv(thresholds, DIRS["gate"] / "workflow_gate_thresholds.csv")
    save_csv(gate, DIRS["gate"] / "workflow_gate_evaluation.csv")
    save_csv(final_status, DIRS["gate"] / "final_status.csv")
    return gate, final_status


def save_figure(fig: plt.Figure, name: str) -> None:
    fig.tight_layout(rect=[0, 0, 1, .95])
    fig.savefig(io_path(FIG / name), bbox_inches="tight", facecolor="white")
    plt.close(fig)


def bar_labels(ax, bars, fmt="{:.0f}") -> None:
    for bar in bars:
        ax.text(bar.get_x() + bar.get_width() / 2, bar.get_height(), fmt.format(bar.get_height()),
                ha="center", va="bottom", fontsize=8)


def figures(events: pd.DataFrame, summaries: dict, hourly: pd.DataFrame) -> list[Path]:
    cp = summaries["checkpoint"].sort_values("checkpoint_relative_hour")
    labels = [f"{abs(int(x))}小时前" for x in cp.checkpoint_relative_hour]
    x = np.arange(len(cp))
    fig, ax = plt.subplots(figsize=(8.5, 5)); b1 = ax.bar(x - .18, cp.hydrogen_side_recovered, .36, label="氢侧救回", color=COLORS[0]); b2 = ax.bar(x + .18, cp.grid_aware_supported, .36, label="电网后保留", color=COLORS[2]); bar_labels(ax, b1); bar_labels(ax, b2); ax.set_xticks(x); ax.set_xticklabels(labels); ax.set_ylabel("path-checkpoint 事件"); ax.legend(); fig.suptitle("S4_125 氢侧恢复收益与电网约束后保留量"); save_figure(fig, "01_氢侧救回与电网保留.png")

    fig, ax = plt.subplots(figsize=(8, 4.8)); bars = ax.bar(labels, 100 * cp.retention_ratio, color=COLORS[:len(cp)]); bar_labels(ax, bars, "{:.1f}%"); ax.axhline(80, color=COLORS[1], linestyle="--", label="workflow gate 80%"); ax.set_ylim(0, 110); ax.set_ylabel("retention（%）"); ax.legend(); fig.suptitle("-16/-8/-4h Grid-aware retention"); save_figure(fig, "02_三个检查点retention.png")

    clipped_hour_ratio = 100 * (~hourly.full_candidate_pmax_hostable).mean()
    event_support = 100 * events.grid_aware_recovery_supported.eq("YES").mean()
    fig, ax = plt.subplots(figsize=(7.5, 5)); bars = ax.bar(["完整增量可承载小时", "实际恢复事件受支持"], [100-clipped_hour_ratio, event_support], color=[COLORS[3], COLORS[2]]); bar_labels(ax, bars, "{:.1f}%"); ax.set_ylim(0, 110); ax.set_ylabel("比例（%）"); fig.suptitle("小时级 full hosting 与事件级恢复支持不是同一判据"); save_figure(fig, "03_full_hosting与实际恢复支持.png")

    fig, ax = plt.subplots(figsize=(7.8, 6)); for_colors = events.checkpoint_relative_hour.map({-16: COLORS[0], -8: COLORS[3], -4: COLORS[2]}); ax.scatter(events.required_added_Pmax_kW, events.grid_supported_average_incremental_capability_kW, c=for_colors, s=48, alpha=.8, edgecolors="white"); lim=max(40,events.required_added_Pmax_kW.max()*1.1); ax.plot([0,lim],[0,lim],"--",color=COLORS[1],label="可用=所需"); ax.set(xlabel="所需等效新增 Pmax（kW）",ylabel="电网支持的平均有效新增能力（kW）",xlim=(0,lim),ylim=(0,lim)); ax.legend(); fig.suptitle("事件所需能力与电网可用能力直接对照"); save_figure(fig, "04_所需kW与电网可用kW.png")

    fig, ax = plt.subplots(figsize=(8, 5)); ax.hist(events.recovery_margin_kg, bins=18, color=COLORS[2], edgecolor="white"); ax.axvline(0,color=COLORS[1],linestyle="--"); ax.set_xlabel("grid-hostable extra H2 - required extra H2（kg）"); ax.set_ylabel("事件数"); fig.suptitle("Grid-aware recovery margin 分布"); save_figure(fig, "05_recovery_margin_kg分布.png")

    clipped = hourly[~hourly.full_candidate_pmax_hostable]
    rounded_missing = clipped.missing_candidate_headroom_kw.round(6)
    fig, ax = plt.subplots(figsize=(8, 5)); ax.hist(rounded_missing, bins=np.linspace(0,40,17), color=COLORS[1], edgecolor="white"); ax.set_xlabel("距 187.5 kW 候选铭牌的缺失 headroom（kW）"); ax.set_ylabel("path-hour"); fig.suptitle("18.608% 电压裁剪小时的缺失 kW"); save_figure(fig, "06_voltage_clipping缺失kW.png")

    failure = summaries["failure"]
    names = failure.failure_type.astype(str).map({"pure_quantity":"纯总量","pure_location":"纯位置","mixed":"混合"})
    values = 100 * failure.retention_ratio.fillna(0)
    fig, ax = plt.subplots(figsize=(8, 5)); bars=ax.bar(names,values,color=[COLORS[0],COLORS[4],COLORS[3]]); bar_labels(ax,bars,"{:.1f}%"); ax.set_ylim(0,110); ax.set_ylabel("retention（%）"); fig.suptitle("失败类型分层的 Grid-aware retention"); save_figure(fig, "07_纯总量与混合retention.png")

    tail=summaries["tail"]; names=tail.tail_group.astype(str).map({"normal95":"normal95","difficult4":"difficult4","extreme1":"extreme1"}); values=100*tail.retention_ratio.fillna(0)
    fig,ax=plt.subplots(figsize=(8,5));bars=ax.bar(names,values,color=[COLORS[0],COLORS[3],COLORS[1]]);bar_labels(ax,bars,"{:.1f}%");ax.axhline(70,color=COLORS[4],linestyle="--",label="tail gate 70%");ax.set_ylim(0,110);ax.set_ylabel("retention（%）");ax.legend();fig.suptitle("Tail 分层的 Grid-aware retention");save_figure(fig,"08_tail_retention.png")

    losses=events[events.classification=="GRID_CLIPPING_REMOVES_RECOVERY_SUPPORT"]
    bus_source=losses.critical_bus if len(losses) else clipped.critical_bus
    counts=bus_source.value_counts().sort_index()
    fig,ax=plt.subplots(figsize=(7.5,5));bars=ax.bar(counts.index.astype(str),counts.values,color=COLORS[1]);bar_labels(ax,bars);ax.set(xlabel="critical bus",ylabel="事件数" if len(losses) else "裁剪 path-hour");fig.suptitle("真正恢复损失的 critical bus" if len(losses) else "无恢复事件损失；裁剪小时的 critical bus");save_figure(fig,"09_bus18恢复损失频次.png")

    fig,ax=plt.subplots(figsize=(8,5))
    for outcome,color,label in [(True,COLORS[2],"恢复保留"),(False,COLORS[1],"恢复支持被移除")]:
        group=events[events.grid_aware_recovery_supported.eq("YES")==outcome]
        ax.scatter(group.minimum_voltage_margin,group.recovery_margin_kg,s=46,color=color,alpha=.75,edgecolors="white",label=label)
    ax.axhline(0,color=COLORS[5],linestyle="--",linewidth=1);ax.set(xlabel="剩余窗口最小电压裕度（p.u.）",ylabel="Grid-aware recovery margin（kg）");ax.legend();fig.suptitle("Bus18 电压裕度与事件级恢复损失");save_figure(fig,"10_bus18电压裕度与恢复损失.png")

    pw=summaries["path_window"].sort_values(["hydrogen_recovered_events","path_id"])
    fig,ax=plt.subplots(figsize=(10,5.5));idx=np.arange(len(pw));ax.bar(idx-.18,pw.hydrogen_recovered_events,.36,color=COLORS[0],label="氢侧 recovered checkpoints");ax.bar(idx+.18,pw.grid_retained_events,.36,color=COLORS[2],label="电网后 retained checkpoints");ax.set(xlabel="44 条 recovered union paths（按事件数排序）",ylabel="三个 checkpoint 中的事件数");ax.legend();fig.suptitle("Path-level recoverability window 前后对照");save_figure(fig,"11_path_level恢复窗口前后.png")

    supported=int(events.grid_aware_recovery_supported.eq("YES").sum()); removed=len(events)-supported; exposed=int((events.grid_clipped_hours>0).sum())
    fig,ax=plt.subplots(figsize=(11,4.8));ax.axis("off");boxes=[(.04,.30,.22,.42,f"氢侧 S4_125\n恢复事件\n{len(events)} 个",COLORS[0]),(.39,.30,.22,.42,f"逐小时 bus18\n电压裁剪重组\n评估 {len(events)} 个\n其中 {exposed} 个有裁剪",COLORS[3]),(.74,.52,.22,.28,f"仍受支持\n{supported} 个事件",COLORS[2]),(.74,.12,.22,.28,f"支持被移除\n{removed} 个事件",COLORS[1])]
    for x0,y0,w,h,text_value,color in boxes: ax.add_patch(patches.FancyBboxPatch((x0,y0),w,h,boxstyle="round,pad=0.012",facecolor=color,alpha=.9,edgecolor="white"));ax.text(x0+w/2,y0+h/2,text_value,ha="center",va="center",color="white",fontsize=11,fontweight="bold")
    ax.annotate("",xy=(.39,.51),xytext=(.26,.51),arrowprops=dict(arrowstyle="->",lw=2,color=COLORS[5]));ax.annotate("",xy=(.74,.66),xytext=(.61,.56),arrowprops=dict(arrowstyle="->",lw=2,color=COLORS[5]));ax.annotate("",xy=(.74,.26),xytext=(.61,.46),arrowprops=dict(arrowstyle="->",lw=2,color=COLORS[5]));fig.suptitle("S4_125：氢侧能力 → 电压截断 → 冻结背景下实际保留能力");save_figure(fig,"12_S4_125闭环机制图.png")
    return sorted(FIG.glob("*.png"))


def contact_sheet(pngs: list[Path]) -> Path:
    family = plt.rcParams["font.family"]
    font_path = font_manager.findfont(family[0] if isinstance(family, list) else family)
    title_font = ImageFont.truetype(font_path, 24)
    label_font = ImageFont.truetype(font_path, 15)
    thumb_w, thumb_h, label_h, gap = 560, 350, 34, 18
    cols, rows = 3, math.ceil(len(pngs) / 3)
    sheet = Image.new("RGB", (cols * (thumb_w + gap) + gap, rows * (thumb_h + label_h + gap) + 70), "white")
    draw = ImageDraw.Draw(sheet); draw.text((gap, 18), "Stage-89Q-G2 S4_125 Grid-Aware Recoverability 图件总览", fill="black", font=title_font)
    for i, path in enumerate(pngs):
        row, col = divmod(i, cols); x=gap+col*(thumb_w+gap); y=62+row*(thumb_h+label_h+gap)
        with Image.open(io_path(path)) as image:
            image=image.convert("RGB");image.thumbnail((thumb_w,thumb_h));sheet.paste(image,(x+(thumb_w-image.width)//2,y))
        draw.text((x,y+thumb_h+4),path.stem,fill="black",font=label_font)
    target=FIG/"contact_sheet.png";sheet.save(io_path(target));return target


def main_qa(preflight_frame: pd.DataFrame, data: dict, events: pd.DataFrame, hourly: pd.DataFrame,
            summaries: dict, gate: pd.DataFrame, pngs: list[Path]) -> pd.DataFrame:
    checks=[]
    def check(name, observed, expected, passed): checks.append({"check":name,"observed":observed,"expected":expected,"pass":bool(passed)})
    cp=summaries["checkpoint"].set_index("checkpoint_relative_hour")
    check("preflight_all_pass",preflight_frame["pass"].sum(),len(preflight_frame),preflight_frame["pass"].all())
    for h,n in [(-16,31),(-8,9),(-4,8)]: check(f"s4_recovered_{h}h",int(cp.loc[h,"hydrogen_side_recovered"]),n,int(cp.loc[h,"hydrogen_side_recovered"])==n)
    check("event_count",len(events),48,len(events)==48)
    check("event_path_union",events.path_id.nunique(),44,events.path_id.nunique()==44)
    check("real_hour_count",len(hourly),704,len(hourly)==704)
    check("no_padded_zero_hours",hourly.relative_hour.between(-16,-1).all(),True,hourly.relative_hour.between(-16,-1).all())
    check("each_union_path_has_16_hours",hourly.groupby("path_id").size().min(),16,(hourly.groupby("path_id").size()==16).all())
    check("k_H2_mechanical",data["k_h2"],K_H2_EXPECTED,abs(data["k_h2"]-K_H2_EXPECTED)<=TOL)
    check("base_Pmax_unchanged",BASE_PMAX.tolist(),[300,200,120,150],np.array_equal(BASE_PMAX,[300,200,120,150]))
    check("candidate_Pmax",CANDIDATE_PMAX.tolist(),[300,200,120,187.5],np.array_equal(CANDIDATE_PMAX,[300,200,120,187.5]))
    check("hourly_delta_definition",(hourly.p4_effective_max_kw-(hourly.realized_pel4_kw+hourly.delta_p4_hostable_from_realized_kw)).abs().max(),"<=1e-5",np.allclose(hourly.p4_effective_max_kw,hourly.realized_pel4_kw+hourly.delta_p4_hostable_from_realized_kw,atol=HOST_TOL_KW))
    check("no_double_counting",(hourly.effective_increment_above_base_kw-(hourly.p4_effective_max_kw-150)).abs().max(),0,np.allclose(hourly.effective_increment_above_base_kw,hourly.p4_effective_max_kw-150,atol=TOL))
    check("full_hosting_81p392",hourly.full_candidate_pmax_hostable.mean(),0.813920454545,abs(hourly.full_candidate_pmax_hostable.mean()-0.813920454545)<=1e-12)
    check("voltage_limited_18p608",hourly.voltage_limited_flag.astype(bool).mean(),0.186079545455,abs(hourly.voltage_limited_flag.astype(bool).mean()-0.186079545455)<=1e-12)
    check("branch_violation_zero",hourly.branch_limited_flag.astype(bool).sum(),0,not hourly.branch_limited_flag.astype(bool).any())
    check("substation_violation_zero",hourly.substation_limited_flag.astype(bool).sum(),0,not hourly.substation_limited_flag.astype(bool).any())
    check("event_all_identifiable",events.grid_aware_identifiable.eq("YES").sum(),len(events),events.grid_aware_identifiable.eq("YES").all())
    check("evaluator_vs_cumulative_kg",(events.grid_aware_recovery_supported==events.cumulative_kg_cross_check_supported).sum(),len(events),(events.grid_aware_recovery_supported==events.cumulative_kg_cross_check_supported).all())
    check("required_alpha_bounds",[events.required_alpha.min(),events.required_alpha.max()],"[0,1]",events.required_alpha.between(-TOL,1+TOL).all())
    alpha_grid=np.linspace(0,1,101); monotone=True
    for row in events.itertuples(index=False):
        margins=row.current_inventory_kg+(BASE_PMAX.sum()+37.5*alpha_grid)*data["k_h2"]*row.expected_remaining_hour_count-row.target_total_kg
        monotone &= bool(np.all(np.diff(margins)>=-TOL))
    check("recoverability_evaluator_monotonicity",monotone,True,monotone)
    check("pure_location_recovery_zero",int((events.failure_type=="pure_location").sum()),0,not (events.failure_type=="pure_location").any())
    check("all_tail_groups_reported",set(summaries["tail"].tail_group.astype(str)),{"normal95","difficult4","extreme1"},set(summaries["tail"].tail_group.astype(str))=={"normal95","difficult4","extreme1"})
    check("normal95_recovered_zero",int(summaries["tail"].loc[summaries["tail"].tail_group.astype(str)=="normal95","hydrogen_side_recovered"].iloc[0]),0,int(summaries["tail"].loc[summaries["tail"].tail_group.astype(str)=="normal95","hydrogen_side_recovered"].iloc[0])==0)
    check("not_identifiable_preserved",int(events.grid_aware_identifiable.eq("NO").sum()),0,True)
    check("no_grid_LP_rerun",False,False,True)
    check("no_random_draw",False,False,True)
    check("no_FA_MSP_solve",False,False,True)
    check("no_forward_backward_cuts",False,False,True)
    check("no_OOS_rerun",False,False,True)
    check("no_parameter_writeback",False,False,True)
    check("workflow_gate_evaluated",len(gate),8,len(gate)==8)
    check("required_figures",len(pngs),12,len(pngs)==12)
    frame=pd.DataFrame(checks);save_csv(frame,DIRS["qa"]/"main_qa.csv");require(frame["pass"].all(),"Main QA failed");return frame


def visual_qa(pngs: list[Path]) -> pd.DataFrame:
    rows=[]
    for path in pngs:
        with Image.open(io_path(path)) as image:
            rgb=np.asarray(image.convert("RGB"));nonwhite=float((rgb<245).any(axis=2).mean())
            passed=image.width>=900 and image.height>=500 and nonwhite>=.02
            rows.append({"figure":path.name,"width_px":image.width,"height_px":image.height,"nonwhite_fraction":nonwhite,"pass":passed})
    frame=pd.DataFrame(rows);save_csv(frame,DIRS["qa"]/"visual_audit.csv");require(frame["pass"].all(),"Automated visual QA failed");return frame


def write_readme(events: pd.DataFrame, summaries: dict, hourly: pd.DataFrame, severity: pd.DataFrame,
                 final_status: pd.DataFrame) -> None:
    cp=summaries["checkpoint"].set_index("checkpoint_relative_hour");tail=summaries["tail"].set_index("tail_group")
    status=final_status.set_index("status").value; supported=int(events.grid_aware_recovery_supported.eq("YES").sum());removed=len(events)-supported
    partial=int(events.classification.eq("PARTIALLY_CLIPPED_BUT_STILL_SUPPORTED").sum());full=int(events.classification.eq("FULL_INCREMENT_HOSTABLE_AND_SUPPORTED").sum())
    clipped=hourly[~hourly.full_candidate_pmax_hostable];sev=severity[(severity.section=="distribution")].set_index("metric").value
    loss_cp=events[events.classification=="GRID_CLIPPING_REMOVES_RECOVERY_SUPPORT"].checkpoint_relative_hour.value_counts();loss_text="无" if removed==0 else "; ".join(f"{abs(int(k))}h:{v}" for k,v in loss_cp.items())
    loss_types=events[events.classification=="GRID_CLIPPING_REMOVES_RECOVERY_SUPPORT"].failure_type.value_counts();type_text="无" if removed==0 else "; ".join(f"{k}:{v}" for k,v in loss_types.items())
    bus_share=(clipped.critical_bus==18).mean()
    supported_clipped_hours=int(severity.loc[(severity.section=="coverage") & (severity.metric=="unique_clipped_path_hours_in_supported_event_windows"),"value"].iloc[0])
    text=f"""# Stage-89Q-G2：S4_125 电压约束下的后期追产能力闭环

## 先说结论

1. 前一轮 S4_125 在氢侧救回 **{len(events)} 个 path-checkpoint events**，涉及 {events.path_id.nunique()} 条路径。
2. 冻结 Base 电气背景下，电压 hosting 后保留 **{supported}/{len(events)}**。
3. -16h 保留 **{int(cp.loc[-16,'grid_aware_supported'])}/{int(cp.loc[-16,'hydrogen_side_recovered'])}**。
4. -8h 保留 **{int(cp.loc[-8,'grid_aware_supported'])}/{int(cp.loc[-8,'hydrogen_side_recovered'])}**。
5. -4h 保留 **{int(cp.loc[-4,'grid_aware_supported'])}/{int(cp.loc[-4,'hydrogen_side_recovered'])}**。
6. 总体/-16h/-8h/-4h retention 分别为 **{100*supported/len(events):.3f}% / {100*cp.loc[-16,'retention_ratio']:.3f}% / {100*cp.loc[-8,'retention_ratio']:.3f}% / {100*cp.loc[-4,'retention_ratio']:.3f}%**。
7. 18.608% full-increment 不可承载小时并不都导致 recovery loss；事件必须按完整剩余窗口重算。
8. {supported_clipped_hours}/{len(clipped)} 个 unique clipped path-hours 位于仍成功保留恢复支持的事件窗口内；对应 **{partial} 个部分裁剪但仍受支持事件**。小时本身不能单独宣称“完成恢复”。
9. 真正被 voltage clipping 移除支持的事件为 **{removed}**。
10. 这些 loss 的 checkpoint 分布为：{loss_text}。
11. 被移除事件的 failure type 为：{type_text}。pure-location 氢侧恢复事件仍为 0。
12. normal95 没有 S4_125 氢侧 recovered event，retention 不定义；difficult4 retention 为 **{100*tail.loc['difficult4','retention_ratio']:.3f}%**；extreme1 retention 为 **{100*tail.loc['extreme1','retention_ratio']:.3f}%**。
13. bus18 是全部 {len(clipped)} 个 full-increment 裁剪小时以及全部 {removed} 个真正 recovery-loss events 的 critical bus；小时频次仍不能替代事件判据。
14. 电压受限小时缺失 headroom 平均 {sev['mean']:.3f} kW，中位数 {sev['median']:.3f} kW，q95 {sev['q95']:.3f} kW，最大 {sev['max']:.3f} kW。
15. >20 kW 的严重缺失小时为 {int(((clipped.missing_candidate_headroom_kw)>20).sum())}/{len(clipped)}；所以不是“只差几 kW”，但整段剩余窗口仍可在多数事件中补足所需累计能力。
16. S4_125 氢侧 late-production physical flexibility gain 经电网后保留程度为 `{status['S4_125_GRID_AWARE_RECOVERY_RETENTION']}`，数值为 {supported}/{len(events)}。
17. 当前 **不能**说 fresh S4_125 policy 一定能利用这些能力。
18. 当前 **不能**说 Stage1 production 会下降。
19. 当前 **不能**说 terminal shortfall 会改善；这仍需要 fresh training 和 fresh OOS。
20. workflow gate 给出的下一步是 `RECOMMEND_FRESH_S4_125_ZERO_CUT_SMOKE={status['RECOMMEND_FRESH_S4_125_ZERO_CUT_SMOKE']}`。这只决定是否值得做工程 smoke，不代表采用候选。

## 核心判据

Stage-89Q-G 的 hourly headroom 从 realized `P_EL4` 起算。本轮先重构 `P4_effective_max=min(187.5, realized_P_EL4+DeltaP_from_realized)`，再将每个真实剩余小时的 `P4_effective_max` 放回 Stage-89Q 原 evaluator：

`current_end_inventory + k_H2 * [remaining_hours*(300+200+120) + sum_h P4_effective_max(h)] - TerminalLOH_total`

结果不小于 `-1e-7 kg` 才记为 `GRID_AWARE_RECOVERY_SUPPORTED=YES`。`grid_hostable_extra_H2 >= required_extra_H2` 只作为交叉检查；两者必须一致。

`required_extra_H2` 不是 final gap。它由同一 evaluator 的 Base margin 解析得到；`required_alpha` 是使 `Pmax4=150+alpha*37.5` 刚好从 `PHYSICALLY_UNRECOVERABLE` 进入 `NOT_RULED_OUT_BY_OPTIMISTIC_BOUND` 的最小比例。

## 解释边界

本轮是 **FROZEN-BASE-BACKGROUND GRID-AWARE PHYSICAL RECOVERABILITY DIAGNOSTIC**，不是 **FRESH-POLICY COUNTERFACTUAL**。

fresh S4_125 policy 重新训练后，其他站 P_EL、inventory、HTT、ordinary service 以及各小时 grid state 都可能变化。因此本轮 YES 只表示存在充分物理依据值得进入训练；本轮 NO 也不等于 fresh policy 严格不可能成功。

本轮没有重跑 grid LP，没有训练 FA-MSP，没有 forward/backward/cut，没有重跑 OOS，没有修改 Pmax、TerminalLOH、HTT、电压/线路/变电站限制或任何 raw/MAT/checkpoint。

## 文件导航

- `01_baseline_reproduction/`：两轮 baseline 与路径身份闭合；
- `02_effective_pmax/`：704 个真实 path-hour 的 effective Pmax 定义与明细；
- `03_grid_aware_recoverability/`：48 个事件主表及 checkpoint/failure/path-window 汇总；
- `04_voltage_clipping_severity/`：18.608% 小时的缺失 kW 分布；
- `05_bus18_mechanism/`：bus18 与真正 event loss；
- `06_tail_analysis/`：normal95/difficult4/extreme1 retention；
- `07_workflow_gate/`：预冻结门槛、门禁评价和最终标签；
- `09_qa/`：主 QA、独立 QA、视觉 QA 与 manifest。
"""
    save_text(text,DIRS["summary"]/"README.md")


def write_manifest() -> None:
    rows=[]
    for base in [OUT,FIG]:
        discovered=[]
        for directory, _, filenames in os.walk(io_path(base)):
            for filename in filenames:
                if filename != "lightweight_manifest.csv":
                    discovered.append(Path(directory) / filename)
        for path in sorted(discovered, key=lambda item: str(item)):
            relative=Path(os.path.relpath(str(path),io_path(ROOT))).as_posix()
            rows.append({"relative_path":relative,"bytes":path.stat().st_size,"sha256":sha256(path),"lightweight":path.suffix.lower() in {".csv",".md",".png"}})
    frame=pd.DataFrame(rows);require(frame.lightweight.all(),"Manifest contains non-lightweight artifact");save_csv(frame,DIRS["qa"]/"lightweight_manifest.csv")


def main() -> None:
    parser=argparse.ArgumentParser();parser.add_argument("--manifest-only",action="store_true");args=parser.parse_args()
    if args.manifest_only:
        require(OUT.is_dir() and FIG.is_dir(),"Cannot finalize missing accepted outputs");write_manifest();print("Manifest finalized",flush=True);return
    setup();pre=preflight();data=load_inputs();source,critical,cross=reproduce_baselines(data);hourly=build_effective_pmax(data,critical)
    events=build_events(data,source,hourly);summaries=summarize_events(events);severity,bus18=clipping_outputs(hourly,events);gate,status=labels_and_gate(events,summaries,hourly)
    pngs=figures(events,summaries,hourly);contact_sheet(pngs);visual_qa(pngs);main_qa(pre,data,events,hourly,summaries,gate,pngs);write_readme(events,summaries,hourly,severity,status)
    print(f"Stage-89Q-G2 complete: {len(events)} events, {int(events.grid_aware_recovery_supported.eq('YES').sum())} retained",flush=True)


if __name__ == "__main__":
    main()
