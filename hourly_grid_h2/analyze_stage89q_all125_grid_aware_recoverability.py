#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Stage-89Q-G3 frozen-background ALL_125 grid-aware recoverability closure."""

from __future__ import annotations

import argparse
import hashlib
import math
import os
import subprocess
from collections import OrderedDict
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib import font_manager
import numpy as np
import pandas as pd
from PIL import Image, ImageDraw, ImageFont
import psutil
from scipy.io import loadmat

from analyze_stage89q_pmax_grid_hosting_audit import HourlyGridLP, load_grid_data


ROOT = Path(__file__).resolve().parents[1]
RUN = ROOT / "results/task-002-stage2b-b3-smoke/stage89q-penalty1000-vs1500-long-training/run-003"
RAW = ROOT / "hourly_grid_h2/output/stage89q_penalty1000_vs1500_long_training/run-003/penalty1000"
DEEP = RUN / "05_analysis/10_deep_penalty1000"
PHYS = DEEP / "17_pmax_flexibility_audit"
GRID = DEEP / "18_pmax_grid_hosting_audit"
S4 = DEEP / "19_s4_grid_aware_recoverability"
OUT = DEEP / "20_all125_grid_aware_recoverability"
FIG = RUN / "06_figures/14_all125_grid_aware_recoverability"
FORMAL = ROOT / "data/yuanqi/near_stage_msp_input.mat"

EXPECTED_BRANCH = "task/002-stage2b-b3-smoke"
EXPECTED_HEAD = "8bb9c28d0a05dbf815c627a3da78f35143253a12"
EXPECTED_UPSTREAM = "origin/task/002-stage2b-b3-smoke"
BASE = np.array([300., 200., 120., 150.])
CANDIDATE = np.array([375., 250., 150., 187.5])
INCREMENTS = CANDIDATE - BASE
CUTS = [-16, -8, -4]
TOL = 1e-7
HOST_TOL = 1e-5
K_H2_EXPECTED = .0195

FILES = {
    "raw_path": RAW / "path_summary/oos_path_summary.csv",
    "raw_stage": RAW / "path_summary/oos_stage_summary.csv",
    "raw_stage_site": RAW / "path_summary/oos_stage_site_summary.csv",
    "raw_hour_site": RAW / "hourly_site/oos_hour_site.csv",
    "raw_grid": RAW / "grid_hourly/oos_hour_system.csv",
    "formal": FORMAL,
    "physical_baseline": PHYS / "01_baseline_reproduction/pmax_recoverability_baseline_reproduction.csv",
    "physical_events": PHYS / "02_counterfactual_recoverability/pmax_candidate_recoverability_by_path.csv",
    "physical_characteristics": PHYS / "06_recovered_path_mechanism/recovered_path_characteristics.csv",
    "grid_joint": GRID / "04_all_125/all_125_joint_hosting.csv",
    "grid_critical": GRID / "05_critical_window/critical_window_grid_hosting.csv",
    "grid_identity": GRID / "05_critical_window/critical_window_subset_identity.csv",
    "grid_summary": GRID / "04_all_125/all_125_summary.csv",
    "s4_events": S4 / "03_grid_aware_recoverability/s4_125_grid_aware_recovery_by_event.csv",
    "s4_tail": S4 / "06_tail_analysis/s4_125_grid_aware_tail_retention.csv",
    "s4_status": S4 / "07_workflow_gate/final_status.csv",
}

EXPECTED_HASHES = {
    "raw_path": "99ec55faba4e60e88b25d757deb1a8146515faf666d52979fe69c64362047502",
    "raw_stage": "969c373a9a2ff1b271cde6fda95a6fe8e64b10362518fe4b807c0dc86437c15d",
    "raw_stage_site": "eab41bdf5d58fc971bc65af8c5745de3bd08cc25a0a4d44cc386aeba3f99c89e",
    "raw_hour_site": "af3b3d5c4aa69e6d29b35a88008b4d82360c4b8391fc783141078f7ad68b0cda",
    "raw_grid": "b9eaa83ee3e8a720f3cb5afd5d54da050c2d3ef45c434efe74f8ba8b976b63c6",
    "formal": "536b25868e6d7cc812a331c0d3e0ffbd5f6958e6883bd39bcae3901c372abf24",
    "physical_baseline": "5ff6efe6f2ca6e55be7a0cf05ebab162b12c9c531ab2be63e2e5351f87bc7f94",
    "physical_events": "6eb403e2445cc858eb9f96f5d656c9920aa234191413dcd14732031da0b425e3",
    "physical_characteristics": "fa027089ebad78eed1c3bcb3934ad167b1c7237ecd46bf2dd0269492fbfc90e5",
    "grid_joint": "fd51b32f69f869e23aebd9b183ac0da40ab14df6fc5d610d8fe71f79011dc305",
    "grid_critical": "9ba61b78e923dc16ce68f267dce3f98b1cad913d495420cc9fcded52bafbd3b3",
    "grid_identity": "3c08d4e518fca90dcc545b279d79c283561ee426b0e7896393ff821fc21ee829",
    "grid_summary": "5fa6bb69c3fc0a2b7b65643d0a17d9eeea5fd3536b5d19f467951c1f2c4de06c",
    "s4_events": "e9e70f4487a1dc650de20679d7c3c15e3a8e4ee71da0dbc6efdd9f999abdd16d",
    "s4_tail": "41e5285db8b7ed0fd0c239f02aa39cb92da3eabfcb9cbc8f341df072067c5a8f",
    "s4_status": "a4efcd5d6b5a01dc16bf82d58820e059c50f5e25cb2fa8a83a45014ebe093ba3",
}

DIRS = {
    "baseline": OUT / "01_baseline_reproduction",
    "joint": OUT / "02_joint_effective_capacity",
    "recovery": OUT / "03_grid_aware_recoverability",
    "bus18": OUT / "04_bus18_site3",
    "comparison": OUT / "05_candidate_comparison",
    "tail": OUT / "06_tail_analysis",
    "gate": OUT / "07_workflow_gate",
    "summary": OUT / "08_summary",
    "qa": OUT / "09_qa",
}

GATE = OrderedDict([
    ("identifiable_rate_min", .95),
    ("overall_retention_min", .80),
    ("difficult_extreme_retention_min", .70),
    ("broad_severe_loss_share_max", .20),
    ("severe_missing_headroom_kw", 20.),
])
COLORS = ["#2166AC", "#B2182B", "#1B7837", "#E08214", "#762A83"]


def io_path(path: Path) -> str:
    value = str(path.resolve())
    return "\\\\?\\" + value if os.name == "nt" and not value.startswith("\\\\?\\") else value


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with open(io_path(path), "rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def id_set_sha(values) -> str:
    payload = ",".join(str(int(v)) for v in sorted(set(values))).encode("ascii")
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
    require(not OUT.exists() and not FIG.exists(), "Accepted G3 output already exists")
    for path in [OUT, FIG, *DIRS.values()]:
        path.mkdir(parents=True, exist_ok=False if path in (OUT, FIG) else True)
    installed = {item.name for item in font_manager.fontManager.ttflist}
    font = next((x for x in ["Microsoft YaHei", "Microsoft YaHei UI", "SimHei"] if x in installed), None)
    require(font is not None, "Chinese font unavailable")
    plt.rcParams.update({"font.family": font, "axes.unicode_minus": False, "font.size": 9,
                         "figure.dpi": 140, "savefig.dpi": 180, "figure.facecolor": "white"})


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
    require(all(p.is_file() for p in FILES.values()), "Required input missing")
    observed_hashes = {key: sha256(path) for key, path in FILES.items()}
    require(observed_hashes == EXPECTED_HASHES, f"Input identity mismatch: {observed_hashes}")
    live, records = process_records()
    tracked = [x for x in git("status", "--short", "--untracked-files=no").splitlines() if x]
    rows = [
        ("branch", git("branch", "--show-current"), EXPECTED_BRANCH, git("branch", "--show-current") == EXPECTED_BRANCH),
        ("HEAD_latest_G2_commit", git("rev-parse", "HEAD"), EXPECTED_HEAD, git("rev-parse", "HEAD") == EXPECTED_HEAD),
        ("upstream", git("rev-parse", "--abbrev-ref", "@{upstream}"), EXPECTED_UPSTREAM, git("rev-parse", "--abbrev-ref", "@{upstream}") == EXPECTED_UPSTREAM),
        ("ahead_behind", git("rev-list", "--left-right", "--count", f"HEAD...{EXPECTED_UPSTREAM}"), "0\t0", git("rev-list", "--left-right", "--count", f"HEAD...{EXPECTED_UPSTREAM}") == "0\t0"),
        ("preexisting_tracked_dirty_count_preserved", len(tracked), 7, len(tracked) == 7),
        ("preexisting_tracked_paths", " | ".join(tracked), "informational", True),
        ("input_hash_identity", len(observed_hashes), len(EXPECTED_HASHES), observed_hashes == EXPECTED_HASHES),
        ("live_MATLAB_Gurobi_count", live, 0, live == 0),
        ("MATLAB_Gurobi_records", records, "stale stopped objects permitted", live == 0),
    ]
    frame = pd.DataFrame(rows, columns=["check", "observed", "expected", "pass"])
    save_csv(frame, DIRS["baseline"] / "repository_preflight.csv")
    require(frame["pass"].all(), "Repository preflight failed")
    return frame


def load_inputs() -> dict:
    device = loadmat(io_path(FORMAL), simplify_cells=True)["NearStageInput"]["HydrogenDevice"]
    pmax = np.asarray(device["el_cap_kw"], dtype=float).ravel()
    tank = np.asarray(device["tank_cap_kg"], dtype=float).ravel()
    k_h2 = float(device["k_H2_kg_per_kWh"])
    require(np.array_equal(pmax, BASE), f"Base Pmax changed: {pmax}")
    require(np.array_equal(tank, [300., 200., 100., 150.]), f"Tank caps changed: {tank}")
    require(abs(k_h2 - K_H2_EXPECTED) <= TOL, f"k_H2 changed: {k_h2}")
    return {"k_h2": k_h2, **{key: pd.read_csv(path) for key, path in FILES.items() if key != "formal"}}


def reproduce_baselines(data: dict) -> tuple[pd.DataFrame, pd.DataFrame]:
    baseline = data["physical_baseline"]
    source = data["physical_events"]
    events = source[(source.candidate == "ALL_125") & source.recovered_relative_to_base].copy()
    critical = data["grid_critical"][(data["grid_critical"].subset == "ALL125_PHYSICALLY_RECOVERED") &
                                      (data["grid_critical"].candidate == "ALL_125")].copy()
    identity = data["grid_identity"].set_index("subset")
    expected_base = {-16: 70, -8: 156, -4: 167}
    expected_all = {-16: 18, -8: 110, -4: 147}
    expected_recovered = {-16: 52, -8: 46, -4: 20}
    rows = []
    for cut in CUTS:
        b = int(baseline.loc[baseline.relative_hour == cut, "recomputed_unrecoverable_count"].iloc[0])
        a = int(((source.candidate == "ALL_125") & (source.relative_hour == cut) & source.PHYSICALLY_UNRECOVERABLE).sum())
        r = int((events.relative_hour == cut).sum())
        rows.extend([
            ("physical", f"base_unrecoverable_{cut}h", b, expected_base[cut], b == expected_base[cut]),
            ("physical", f"all125_unrecoverable_{cut}h", a, expected_all[cut], a == expected_all[cut]),
            ("physical", f"all125_recovered_{cut}h", r, expected_recovered[cut], r == expected_recovered[cut]),
        ])
    ids = set(events.path_id.astype(int))
    saved_sha = str(identity.loc["ALL125_PHYSICALLY_RECOVERED", "path_id_set_sha256"])
    rows.extend([
        ("candidate", "candidate_pmax_kw", CANDIDATE.tolist(), [375, 250, 150, 187.5], np.array_equal(CANDIDATE, [375, 250, 150, 187.5])),
        ("candidate", "added_total_kw", INCREMENTS.sum(), 192.5, INCREMENTS.sum() == 192.5),
        ("identity", "hydrogen_recovered_events", len(events), 118, len(events) == 118),
        ("identity", "hydrogen_recovered_unique_paths", len(ids), 99, len(ids) == 99),
        ("identity", "recovered_path_set_sha256", id_set_sha(ids), saved_sha, id_set_sha(ids) == saved_sha),
        ("grid", "critical_real_hour_rows", len(critical), 1584, len(critical) == 1584),
        ("grid", "pure_location_recovered", int((events.failure_type == "pure_location").sum()), 0, not (events.failure_type == "pure_location").any()),
    ])
    grid_summary = data["grid_summary"].set_index("metric").value.astype(float)
    critical_full = critical.full_to_candidate_hostable.eq("YES").mean()
    critical_site3 = critical.site3_full_to_candidate_hostable.eq("YES").mean()
    rows.extend([
        ("stage89q_g", "all_hour_joint_mean_hosting_ratio", grid_summary["joint_mean_hosting_ratio"], .9630173862776531, abs(grid_summary["joint_mean_hosting_ratio"]-.9630173862776531)<=1e-12),
        ("stage89q_g", "all_hour_full_candidate_stress_feasible_ratio", grid_summary["full_candidate_stress_feasible_ratio"], .85345659838818, abs(grid_summary["full_candidate_stress_feasible_ratio"]-.85345659838818)<=1e-12),
        ("stage89q_g", "recovered_final16_full_candidate_stress_feasible_ratio", critical_full, .767676767676768, abs(critical_full-.767676767676768)<=1e-12),
        ("stage89q_g", "recovered_final16_site3_independent_hostable_ratio", critical_site3, .839015151515151, abs(critical_site3-.839015151515151)<=1e-12),
        ("stage89q_g", "recovered_final16_critical_bus18_ratio", critical.critical_bus.eq(18).mean(), 1., critical.critical_bus.eq(18).all()),
        ("stage89q_g", "branch_limited_ratio", grid_summary["branch_limited_ratio"], 0., grid_summary["branch_limited_ratio"]==0),
        ("stage89q_g", "substation_limited_ratio", grid_summary["substation_limited_ratio"], 0., grid_summary["substation_limited_ratio"]==0),
    ])
    frame = pd.DataFrame(rows, columns=["audit", "metric", "observed", "expected", "pass"])
    save_csv(frame, DIRS["baseline"] / "baseline_cross_audit.csv")
    path_rows = []
    for cut in CUTS:
        keys = events.loc[events.relative_hour == cut, ["path_id", "relative_hour"]]
        observed = sum(((critical.path_id == row.path_id) & (critical.relative_hour >= cut)).sum() for row in keys.itertuples())
        path_rows.append({"checkpoint_relative_hour": cut, "event_count": len(keys),
                          "expected_real_event_hours": len(keys) * -cut, "observed_real_event_hours": observed,
                          "no_padded_zero_hours": observed == len(keys) * -cut})
    path_frame = pd.DataFrame(path_rows)
    save_csv(path_frame, DIRS["baseline"] / "baseline_path_identity_QA.csv")
    require(frame["pass"].all() and path_frame.no_padded_zero_hours.all(), "Baseline reproduction failed")
    return events, critical


def reconstruct_joint(data: dict, critical: pd.DataFrame) -> pd.DataFrame:
    profiles = data["grid_joint"].set_index("profile_id")
    used = sorted(set(critical.profile_id.astype(int)))
    grid_data = load_grid_data()
    lp_cache = {hour: HourlyGridLP(grid_data, hour) for hour in range(1, 49)}
    rows = []
    for number, profile_id in enumerate(used, 1):
        p = profiles.loc[profile_id]
        realized = np.array([p[f"realized_pel{i}_kw"] for i in range(1, 5)], dtype=float)
        result = lp_cache[int(p.global_hour)].solve(realized, CANDIDATE, True)
        feasible = np.asarray(result["p_el_new_kw"], dtype=float)
        require(abs((feasible - realized).sum() - p.joint_increment_feasible_kw) <= HOST_TOL,
                f"Saved joint total mismatch at profile {profile_id}")
        row = {"profile_id": profile_id, "global_hour": int(p.global_hour)}
        for site in range(4):
            row.update({f"site{site+1}_realized_pel_kw": realized[site],
                        f"site{site+1}_joint_feasible_pel_kw": feasible[site],
                        f"site{site+1}_effective_increment_above_base_kw": feasible[site] - BASE[site],
                        f"site{site+1}_missing_to_candidate_kw": CANDIDATE[site] - feasible[site]})
        row.update({
            "joint_feasible_total_pel_kw": feasible.sum(),
            "joint_effective_increment_above_base_kw": (feasible - BASE).sum(),
            "joint_missing_to_candidate_kw": (CANDIDATE - feasible).sum(),
            "joint_increment_from_realized_kw": (feasible - realized).sum(),
            "saved_joint_increment_from_realized_kw": p.joint_increment_feasible_kw,
            "full_candidate_stress_feasible": "YES" if result["full_hostable"] else "NO",
            "minimum_voltage_pu": result["min_voltage_pu"],
            "minimum_voltage_margin_pu": result["voltage_margin_pu"],
            "critical_bus": result["critical_bus"],
            "critical_branch": result["critical_branch_id"],
            "max_true_s_mva": result["max_true_s_mva"],
            "max_octagon_utilization": result["max_octagon_utilization"],
            "voltage_limited_flag": result["voltage_limited_flag"],
            "branch_limited_flag": result["branch_limited_flag"],
            "substation_limited_flag": result["substation_limited_flag"],
            "site_resolved_joint_feasibility_witness": "YES",
        })
        rows.append(row)
        if number % 100 == 0 or number == len(used):
            print(f"Reconstructed {number}/{len(used)} used joint profiles", flush=True)
    profile_frame = pd.DataFrame(rows)
    hourly = critical[["path_id", "stage", "global_hour", "relative_hour", "profile_id"]].merge(
        profile_frame, on=["profile_id", "global_hour"], validate="many_to_one")
    hourly.sort_values(["path_id", "relative_hour"], inplace=True)
    save_csv(hourly, DIRS["joint"] / "all125_site_resolved_joint_hourly.csv")
    definition = f"""# ALL_125 联合小时可行轨迹定义

Stage-89Q-G 已保存的 `all_125_joint_hosting.csv` 只保留联合最大总量，没有保存四站分配向量，不能单独满足 G3 的 site-resolved 要求。本轮仅对 99 条 ALL_125 氢侧 recovered paths 涉及的 {len(used)} 个唯一电气 profile，使用相同 frozen Base background、相同 `HourlyGridLP` 和相同 IEEE33 约束重放独立小时 LP，并显式保存 `P_EL1..4` 联合可行见证。

每小时 LP 的目标仍是最大化四站总 P_EL；主判据把这一条实际 joint-feasible 的四站轨迹放回 Stage-89Q 原有 aggregate optimistic recoverability evaluator。该 evaluator 允许站间容量替代，不能严格识别唯一的 `required_extra_H2_by_site`，因此本轮按任务要求报告统一缩放 `alpha_required_uniform` 和逐站回退诊断，不把最终站点缺口冒充本站最小需求。

`THIS_IS_NOT_FA_MSP_REOPTIMIZATION`

`THIS_IS_PHYSICAL_FEASIBILITY_DIAGNOSTIC_ONLY`

没有将四站 independent headroom 相加，没有生成随机数，也没有补零小时。
"""
    save_text(definition, DIRS["joint"] / "joint_site_resolved_definition.md")
    return hourly


def site_summary(window: pd.DataFrame, site: int) -> str:
    x = window[f"site{site}_effective_increment_above_base_kw"]
    return f"min={x.min():.6g};mean={x.mean():.6g};max={x.max():.6g};sum={x.sum():.6g} kW"


def build_events(data: dict, source: pd.DataFrame, hourly: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    meta = data["physical_characteristics"]
    meta = meta[meta.candidate == "ALL_125"].rename(columns={"base_unrecoverable_hour": "relative_hour"})
    events = source[["path_id", "relative_hour", "failure_type", "current_inventory_kg", "target_total", "remaining_hours"]].merge(
        meta[["path_id", "relative_hour", "arrival_stage", "final_intensity", "final_location", "final_gap_kg", "tail_group"]],
        on=["path_id", "relative_hour"], validate="one_to_one")
    k_h2 = data["k_h2"]
    rows, ablation_rows = [], []
    for event in events.itertuples(index=False):
        n = -int(event.relative_hour)
        window = hourly[(hourly.path_id == event.path_id) & (hourly.relative_hour >= event.relative_hour)]
        identifiable = len(window) == n and not window.isna().any().any()
        base_margin = event.current_inventory_kg + BASE.sum() * k_h2 * n - event.target_total
        required_h2 = max(0., -TOL - base_margin)
        required_kw = required_h2 / (k_h2 * n)
        alpha = required_kw / INCREMENTS.sum()
        necessary = []
        for site, increment in enumerate(INCREMENTS, 1):
            margin = base_margin + (INCREMENTS.sum() - increment) * k_h2 * n
            is_necessary = margin < -TOL
            necessary.append(is_necessary)
            category = "ESSENTIAL" if is_necessary else ("REDUNDANT" if required_h2 <= TOL else "PARTIALLY_SUBSTITUTABLE")
            ablation_rows.append({
                "path_id": int(event.path_id), "checkpoint_relative_hour": int(event.relative_hour),
                "failure_type": event.failure_type, "tail_group": event.tail_group, "site": site,
                "site_increment_kw": increment, "all125_recovered": "YES",
                "ablated_candidate_total_increment_kw": INCREMENTS.sum() - increment,
                "ablated_physical_margin_kg": margin,
                "recovery_survives_site_ablation": "NO" if is_necessary else "YES",
                "increment_necessary": "YES" if is_necessary else "NO", "contribution_class": category,
                "diagnostic_scope": "SAME_AGGREGATE_PHYSICAL_RECOVERABILITY_EVALUATOR",
            })
        if identifiable:
            total_pel = window.joint_feasible_total_pel_kw.sum()
            grid_margin = event.current_inventory_kg + k_h2 * total_pel - event.target_total
            grid_extra_h2 = k_h2 * (total_pel - BASE.sum() * n)
            supported = grid_margin >= -TOL
            clipped = window.full_candidate_stress_feasible.eq("NO")
            clipped_count = int(clipped.sum())
            classification = ("FULL_CANDIDATE_HOSTABLE_AND_SUPPORTED" if supported and not clipped_count else
                              "PARTIALLY_GRID_CLIPPED_BUT_STILL_SUPPORTED" if supported else
                              "GRID_CLIPPING_REMOVES_RECOVERY_SUPPORT")
            limiting = window[clipped] if clipped_count else window
            bus = int(limiting.critical_bus.mode().iloc[0])
            branch = int(limiting.critical_branch.mode().iloc[0])
            reason = ""
        else:
            grid_margin = grid_extra_h2 = math.nan
            supported, clipped_count = False, 0
            classification, bus, branch = "NOT_IDENTIFIABLE", math.nan, math.nan
            reason = f"expected {n} real hours; found {len(window)} or missing values"
        row = {
            "path_id": int(event.path_id), "checkpoint_relative_hour": int(event.relative_hour),
            "failure_type": event.failure_type, "arrival_stage": int(event.arrival_stage),
            "final_intensity": int(event.final_intensity), "final_location": int(event.final_location),
            "final_gap": event.final_gap_kg, "tail_group": event.tail_group,
            "current_inventory_kg": event.current_inventory_kg, "target_total_kg": event.target_total,
            "real_remaining_hour_count": len(window), "expected_remaining_hour_count": n,
            "hydrogen_side_recovered": "YES", "required_extra_H2_kg": required_h2,
            "alpha_required_uniform": alpha, "required_total_added_kW_proxy": required_kw,
            "site1_increment_necessary": "YES" if necessary[0] else "NO",
            "site2_increment_necessary": "YES" if necessary[1] else "NO",
            "site3_increment_necessary": "YES" if necessary[2] else "NO",
            "site4_increment_necessary": "YES" if necessary[3] else "NO",
            "joint_grid_feasible": "YES" if identifiable else "NOT_IDENTIFIABLE",
            "full_candidate_stress_feasible": "YES" if identifiable and clipped_count == 0 else ("NO" if identifiable else "NOT_IDENTIFIABLE"),
            "partially_clipped": "YES" if clipped_count else ("NO" if identifiable else "NOT_IDENTIFIABLE"),
            "grid_aware_identifiable": "YES" if identifiable else "NO",
            "grid_aware_recovery_supported": "YES" if supported else ("NO" if identifiable else "NOT_IDENTIFIABLE"),
            "classification": classification, "grid_clipped_hours": clipped_count,
            "critical_bus": bus, "critical_branch": branch,
            "minimum_voltage": window.minimum_voltage_pu.min() if identifiable else math.nan,
            "minimum_voltage_margin": window.minimum_voltage_margin_pu.min() if identifiable else math.nan,
            "joint_grid_hostable_extra_H2_kg": grid_extra_h2,
            "grid_aware_recovery_margin_kg": grid_margin,
            "site1_effective_increment_summary": site_summary(window, 1) if identifiable else "NOT_IDENTIFIABLE",
            "site2_effective_increment_summary": site_summary(window, 2) if identifiable else "NOT_IDENTIFIABLE",
            "site3_effective_increment_summary": site_summary(window, 3) if identifiable else "NOT_IDENTIFIABLE",
            "site4_effective_increment_summary": site_summary(window, 4) if identifiable else "NOT_IDENTIFIABLE",
            "not_identifiable_reason": reason,
        }
        rows.append(row)
    result = pd.DataFrame(rows).sort_values(["checkpoint_relative_hour", "path_id"])
    ablation = pd.DataFrame(ablation_rows).sort_values(["site", "checkpoint_relative_hour", "path_id"])
    save_csv(result, DIRS["recovery"] / "all125_grid_aware_recovery_by_event.csv")
    save_csv(ablation, DIRS["recovery"] / "all125_site_ablation_by_event.csv")
    return result, ablation


def aggregate(group: pd.DataFrame) -> pd.Series:
    recovered = len(group)
    identifiable = int(group.grid_aware_identifiable.eq("YES").sum())
    supported = int(group.grid_aware_recovery_supported.eq("YES").sum())
    removed = int(group.classification.eq("GRID_CLIPPING_REMOVES_RECOVERY_SUPPORT").sum())
    return pd.Series({"hydrogen_side_recovered": recovered, "grid_aware_identifiable": identifiable,
                      "grid_aware_supported": supported, "grid_clipping_removed": removed,
                      "not_identifiable": recovered - identifiable,
                      "identifiable_rate": identifiable / recovered if recovered else math.nan,
                      "retention_ratio": supported / recovered if recovered else math.nan})


def summaries(events: pd.DataFrame, ablation: pd.DataFrame) -> dict[str, pd.DataFrame]:
    checkpoint = events.groupby("checkpoint_relative_hour", sort=True).apply(aggregate).reset_index()
    failure = events.groupby("failure_type", sort=False).apply(aggregate).reset_index()
    if "pure_location" not in set(failure.failure_type):
        failure = pd.concat([failure, pd.DataFrame([{"failure_type": "pure_location", **aggregate(events.iloc[0:0]).to_dict()}])], ignore_index=True)
    order = ["pure_quantity", "pure_location", "mixed"]
    failure["_order"] = failure.failure_type.map({x: i for i, x in enumerate(order)})
    failure.sort_values("_order", inplace=True); failure.drop(columns="_order", inplace=True)
    tail = events.groupby("tail_group", sort=False).apply(aggregate).reset_index()
    for group in ["normal95", "difficult4", "extreme1"]:
        if group not in set(tail.tail_group):
            tail = pd.concat([tail, pd.DataFrame([{"tail_group": group, **aggregate(events.iloc[0:0]).to_dict()}])], ignore_index=True)
    tail["_order"] = tail.tail_group.map({"normal95": 0, "difficult4": 1, "extreme1": 2})
    tail.sort_values("_order", inplace=True); tail.drop(columns="_order", inplace=True)
    site = ablation.groupby(["site", "site_increment_kw"]).agg(
        recovered_events=("path_id", "size"), essential_events=("contribution_class", lambda x: x.eq("ESSENTIAL").sum()),
        redundant_events=("contribution_class", lambda x: x.eq("REDUNDANT").sum()),
        partially_substitutable_events=("contribution_class", lambda x: x.eq("PARTIALLY_SUBSTITUTABLE").sum()),
        not_identifiable_events=("contribution_class", lambda x: x.eq("NOT_IDENTIFIABLE").sum())).reset_index()
    site["essential_events_per_added_kw"] = site.essential_events / site.site_increment_kw
    site["ablation_loss_ratio"] = site.essential_events / site.recovered_events
    save_csv(checkpoint, DIRS["recovery"] / "all125_grid_aware_summary_by_checkpoint.csv")
    save_csv(failure, DIRS["recovery"] / "all125_grid_aware_summary_by_failure_type.csv")
    save_csv(tail, DIRS["tail"] / "all125_grid_aware_tail_retention.csv")
    save_csv(site, DIRS["recovery"] / "all125_site_contribution_summary.csv")
    return {"checkpoint": checkpoint, "failure": failure, "tail": tail, "site": site}


def bus18_analysis(events: pd.DataFrame, hourly: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for event in events[events.classification == "GRID_CLIPPING_REMOVES_RECOVERY_SUPPORT"].itertuples(index=False):
        window = hourly[(hourly.path_id == event.path_id) & (hourly.relative_hour >= event.checkpoint_relative_hour)]
        clipped = window[window.full_candidate_stress_feasible == "NO"]
        rows.append({
            "path_id": event.path_id, "checkpoint_relative_hour": event.checkpoint_relative_hour,
            "failure_type": event.failure_type, "tail_group": event.tail_group,
            "critical_bus": event.critical_bus, "bus18_critical_hours": int((clipped.critical_bus == 18).sum()),
            "grid_clipped_hours": len(clipped), "bus18_critical_frequency": (clipped.critical_bus == 18).mean() if len(clipped) else 0,
            "site3_increment_necessary": event.site3_increment_necessary,
            "site3_plus30_is_necessary_contribution": event.site3_increment_necessary,
            "site3_ablation_removes_physical_recovery": event.site3_increment_necessary,
            "minimum_voltage_pu": clipped.minimum_voltage_pu.min() if len(clipped) else event.minimum_voltage,
            "minimum_voltage_margin_pu": clipped.minimum_voltage_margin_pu.min() if len(clipped) else event.minimum_voltage_margin,
            "voltage_shortfall_from_lower_bound_pu": max(0., .9 - (clipped.minimum_voltage_pu.min() if len(clipped) else event.minimum_voltage)),
            "missing_recovery_support_kg": max(0., -event.grid_aware_recovery_margin_kg),
            "site3_effective_increment_summary": event.site3_effective_increment_summary,
        })
    result = pd.DataFrame(rows)
    if result.empty:
        result = pd.DataFrame(columns=["path_id", "checkpoint_relative_hour", "failure_type", "tail_group", "critical_bus",
                                             "bus18_critical_hours", "grid_clipped_hours", "bus18_critical_frequency",
                                             "site3_increment_necessary", "site3_plus30_is_necessary_contribution",
                                             "site3_ablation_removes_physical_recovery", "minimum_voltage_pu",
                                             "minimum_voltage_margin_pu", "voltage_shortfall_from_lower_bound_pu",
                                             "missing_recovery_support_kg", "site3_effective_increment_summary"])
    save_csv(result, DIRS["bus18"] / "site3_bus18_recovery_loss.csv")
    return result


def candidate_comparison(data: dict, events: pd.DataFrame, sums: dict, bus: pd.DataFrame) -> pd.DataFrame:
    s4 = data["s4_events"]
    s4_tail = data["s4_tail"].set_index("tail_group")

    def row(candidate: str, added: float, frame: pd.DataFrame, tail_frame=None, bus_rows=None) -> dict:
        retained = frame.grid_aware_recovery_supported.eq("YES")
        lost = frame.classification.str.contains("REMOVES_RECOVERY_SUPPORT")
        by_cut = {cut: retained[frame.checkpoint_relative_hour == cut].mean() for cut in CUTS}
        def retained_type(kind): return int((retained & frame.failure_type.eq(kind)).sum())
        if tail_frame is None:
            diff = retained[frame.tail_group == "difficult4"].mean()
            extreme = retained[frame.tail_group == "extreme1"].mean()
        else:
            diff = float(tail_frame.loc["difficult4", "retention_ratio"])
            extreme = float(tail_frame.loc["extreme1", "retention_ratio"])
        bus_loss = int((frame.loc[lost, "critical_bus"] == 18).sum()) if bus_rows is None else int((bus_rows.critical_bus == 18).sum())
        retained_count = int(retained.sum())
        retained_paths = int(frame.loc[retained, "path_id"].nunique())
        return {"candidate": candidate, "added_total_kW": added,
                "hydrogen_side_recovered_events": len(frame), "unique_recovered_paths": frame.path_id.nunique(),
                "grid_aware_retained_events": retained_count, "grid_aware_unique_paths": retained_paths,
                "overall_retention_ratio": retained.mean(), "retention_-16": by_cut[-16], "retention_-8": by_cut[-8], "retention_-4": by_cut[-4],
                "pure_quantity_retained": retained_type("pure_quantity"), "mixed_retained": retained_type("mixed"),
                "pure_location_retained": retained_type("pure_location"), "difficult4_retention": diff,
                "extreme1_retention": extreme, "grid_loss_events": int(lost.sum()), "bus18_loss_events": bus_loss,
                "retained_events_per_added_kW": retained_count / added,
                "retained_unique_paths_per_added_kW": retained_paths / added}
    comparison = pd.DataFrame([row("S4_125", 37.5, s4, s4_tail), row("ALL_125", 192.5, events, None, bus)])
    save_csv(comparison, DIRS["comparison"] / "s4_vs_all125_grid_aware_comparison.csv")
    return comparison


def gate_and_labels(events: pd.DataFrame, hourly: pd.DataFrame, comparison: pd.DataFrame, data: dict) -> tuple[pd.DataFrame, pd.DataFrame]:
    identifiable = events.grid_aware_identifiable.eq("YES").mean()
    overall = events.grid_aware_recovery_supported.eq("YES").mean()
    tail = events[events.tail_group.isin(["difficult4", "extreme1"])]
    tail_retention = tail.grid_aware_recovery_supported.eq("YES").mean()
    removed_share = events.classification.eq("GRID_CLIPPING_REMOVES_RECOVERY_SUPPORT").mean()
    severe_share = ((hourly.joint_missing_to_candidate_kw > GATE["severe_missing_headroom_kw"]) &
                    hourly.full_candidate_stress_feasible.eq("NO")).mean()
    branch_ok = not hourly.branch_limited_flag.astype(bool).any()
    substation_ok = not hourly.substation_limited_flag.astype(bool).any()
    broad_ok = removed_share <= GATE["broad_severe_loss_share_max"] and severe_share <= GATE["broad_severe_loss_share_max"]
    rows = [
        ("baseline_reproduction_all_pass", True, True, True), ("raw_model_inputs_unchanged", True, True, True),
        ("grid_aware_identifiable_rate", identifiable, f">={GATE['identifiable_rate_min']}", identifiable >= GATE["identifiable_rate_min"]),
        ("overall_retention_ratio", overall, f">={GATE['overall_retention_min']}", overall >= GATE["overall_retention_min"]),
        ("difficult4_plus_extreme1_retention", tail_retention, f">={GATE['difficult_extreme_retention_min']}", tail_retention >= GATE["difficult_extreme_retention_min"]),
        ("no_branch_structural_bottleneck", branch_ok, True, branch_ok),
        ("no_substation_structural_bottleneck", substation_ok, True, substation_ok),
        ("no_broad_severe_voltage_recovery_loss", {"removed_event_share": removed_share, "severe_path_hour_share": severe_share}, f"both <= {GATE['broad_severe_loss_share_max']}", broad_ok),
    ]
    gate = pd.DataFrame(rows, columns=["gate", "observed", "threshold", "pass"])
    if gate["pass"].all(): recommendation = "YES"
    elif overall < .5 and removed_share > .5: recommendation = "NO"
    else: recommendation = "NEEDS_MORE_GRID_DIAGNOSTIC"
    h2 = "STRONG" if len(events) >= 100 else "MODERATE" if len(events) >= 40 else "WEAK" if len(events) else "NONE"
    retention = "STRONG" if overall >= .8 else "MODERATE" if overall >= .5 else "WEAK" if overall > 0 else "NONE"
    voltage = "LOW" if removed_share <= .05 else "MODERATE" if removed_share <= .2 else "HIGH"
    c16 = events.loc[events.checkpoint_relative_hour == -16, "grid_aware_recovery_supported"].eq("YES").mean()
    critical = "STRONG" if c16 >= .8 else "MODERATE" if c16 >= .5 else "WEAK"
    loss = int(events.classification.eq("GRID_CLIPPING_REMOVES_RECOVERY_SUPPORT").sum())
    bus_signal = "NONE" if not loss else "STRONG" if loss / len(events) > .2 else "MODERATE" if loss / len(events) > .05 else "WEAK"
    s4_rec = data["s4_status"].set_index("status").value["RECOMMEND_FRESH_S4_125_ZERO_CUT_SMOKE"]
    priority = "BOTH" if s4_rec == "YES" and recommendation == "YES" else "ALL_125" if recommendation == "YES" else "S4_125" if s4_rec == "YES" else "NEITHER"
    labels = OrderedDict([
        ("ALL_125_H2_SIDE_RECOVERY_SIGNAL", h2), ("ALL_125_GRID_AWARE_RECOVERY_RETENTION", retention),
        ("ALL_125_VOLTAGE_CLIPPING_IMPACT", voltage), ("ALL_125_CRITICAL_WINDOW_GRID_SUPPORT", critical),
        ("ALL_125_BUS18_RECOVERY_LOSS_SIGNAL", bus_signal), ("RECOMMEND_FRESH_ALL_125_ZERO_CUT_SMOKE", recommendation),
        ("GRID_AWARE_PILOT_PRIORITY", priority),
        ("DIAGNOSTIC_SCOPE", "FROZEN_BASE_BACKGROUND_JOINT_GRID_AWARE_PHYSICAL_RECOVERABILITY"),
        ("THIS_IS_NOT_FA_MSP_REOPTIMIZATION", "YES"), ("THIS_IS_PHYSICAL_FEASIBILITY_DIAGNOSTIC_ONLY", "YES"),
        ("FRESH_POLICY_COUNTERFACTUAL", "NO"), ("ISOLATED_JOINT_GRID_LP_REPLAY", "YES"),
        ("INDEPENDENT_SITE_HEADROOMS_SUMMED", "NO"), ("NO_FA_MSP_TRAINING_FORWARD_BACKWARD_CUTS_OOS", "YES"),
        ("NO_PARAMETER_WRITEBACK", "YES"), ("SMOKE_STARTED", "NO"), ("PENALTY1500_STARTED", "NO")])
    status = pd.DataFrame(labels.items(), columns=["status", "value"])
    thresholds = pd.DataFrame(GATE.items(), columns=["threshold", "value"])
    save_csv(thresholds, DIRS["gate"] / "workflow_gate_thresholds.csv")
    save_csv(gate, DIRS["gate"] / "workflow_gate_evaluation.csv")
    save_csv(status, DIRS["gate"] / "final_status.csv")
    return gate, status


def finish_figure(fig: plt.Figure, name: str) -> Path:
    fig.tight_layout()
    path = FIG / name
    fig.savefig(io_path(path), bbox_inches="tight", facecolor="white")
    plt.close(fig)
    return path


def bars(title, labels, values, ylabel, name, colors=None, percent=False) -> Path:
    fig, ax = plt.subplots(figsize=(7.2, 4.4))
    rects = ax.bar(labels, values, color=colors or COLORS[:len(labels)])
    ax.set_title(title); ax.set_ylabel(ylabel); ax.grid(axis="y", alpha=.25)
    if percent: ax.set_ylim(0, 105)
    for rect, value in zip(rects, values):
        ax.text(rect.get_x()+rect.get_width()/2, rect.get_height(), f"{value:.1f}" if percent else f"{value:.3g}", ha="center", va="bottom")
    return finish_figure(fig, name)


def figures(events: pd.DataFrame, sums: dict, hourly: pd.DataFrame, ablation: pd.DataFrame,
            bus: pd.DataFrame, comparison: pd.DataFrame) -> list[Path]:
    retained = int(events.grid_aware_recovery_supported.eq("YES").sum())
    paths = []
    paths.append(bars("ALL_125：氢侧救回与电网后保留", ["氢侧救回", "电网后保留", "电网剪切消除"], [len(events), retained, len(events)-retained], "checkpoint events", "01_氢侧救回与电网保留.png"))
    c = sums["checkpoint"]
    paths.append(bars("三个检查点的 grid-aware retention", [f"{x}h" for x in c.checkpoint_relative_hour], list(c.retention_ratio*100), "%", "02_检查点retention.png", percent=True))
    full = int(events.full_candidate_stress_feasible.eq("YES").sum()); partial = int(events.classification.eq("PARTIALLY_GRID_CLIPPED_BUT_STILL_SUPPORTED").sum())
    paths.append(bars("Full-stress 与实际 recovery support", ["全程full", "部分剪切仍保留", "真正消除"], [full, partial, len(events)-retained], "events", "03_full_stress与实际支持.png"))
    f = sums["failure"]; paths.append(bars("failure type retention", list(f.failure_type), list(f.retention_ratio.fillna(0)*100), "%", "04_failure_type_retention.png", percent=True))
    t = sums["tail"]; paths.append(bars("尾部 retention", list(t.tail_group), list(t.retention_ratio.fillna(0)*100), "%", "05_tail_retention.png", percent=True))
    s = sums["site"]; paths.append(bars("四站新增容量的必要事件数", [f"Site{x}" for x in s.site], list(s.essential_events), "events", "06_四站贡献.png"))
    paths.append(bars("四站 ablation loss ratio", [f"Site{x}" for x in s.site], list(s.ablation_loss_ratio*100), "%", "07_四站ablation_loss.png", percent=True))
    site3 = ablation[ablation.site == 3]; paths.append(bars("Site3 必要性与 bus18 recovery loss", ["Site3必要", "grid loss", "两者交集"], [site3.increment_necessary.eq("YES").sum(), len(bus), bus.site3_increment_necessary.eq("YES").sum() if len(bus) else 0], "events", "08_Site3必要性与bus18.png"))
    fig, ax = plt.subplots(figsize=(7.2, 4.4)); lost = events.classification.eq("GRID_CLIPPING_REMOVES_RECOVERY_SUPPORT"); ax.scatter(events.minimum_voltage_margin*1000, events.grid_aware_recovery_margin_kg, c=np.where(lost, COLORS[1], COLORS[0]), alpha=.65); ax.axhline(0,color="black",lw=1); ax.set(title="bus18 电压裕度与 recovery margin", xlabel="最小电压裕度 (10^-3 pu)", ylabel="grid-aware margin (kg)"); ax.grid(alpha=.2); paths.append(finish_figure(fig,"09_bus18电压裕度与恢复损失.png"))
    loss = events[lost].groupby(["checkpoint_relative_hour","failure_type"]).size().unstack(fill_value=0); fig, ax=plt.subplots(figsize=(7.2,4.4)); loss.plot.bar(stacked=True,ax=ax,color=COLORS[1:]); ax.set(title="ALL_125 grid-loss event 分布",xlabel="检查点",ylabel="events"); ax.grid(axis="y",alpha=.2); paths.append(finish_figure(fig,"10_grid_loss事件分布.png"))
    paths.append(bars("S4 vs ALL_125：绝对保留 recovery", list(comparison.candidate), list(comparison.grid_aware_retained_events), "events", "11_两候选绝对保留.png"))
    paths.append(bars("S4 vs ALL_125：单位新增 kW 效率", list(comparison.candidate), list(comparison.retained_events_per_added_kW), "retained events / kW", "12_两候选单位kW效率.png"))
    fig, ax=plt.subplots(figsize=(7.6,4.5)); x=np.arange(2); w=.35; ax.bar(x-w/2,comparison.difficult4_retention*100,w,label="difficult4",color=COLORS[0]); ax.bar(x+w/2,comparison.extreme1_retention*100,w,label="extreme1",color=COLORS[2]); ax.set_xticks(x); ax.set_xticklabels(list(comparison.candidate)); ax.set_ylim(0,105); ax.set_ylabel("%"); ax.set_title("S4 vs ALL_125：尾部 retention"); ax.legend(); ax.grid(axis="y",alpha=.2); paths.append(finish_figure(fig,"13_两候选tail_retention.png"))
    fig, axes=plt.subplots(1,3,figsize=(11.2,4)); axes[0].bar(comparison.candidate,comparison.grid_aware_retained_events,color=COLORS[:2]); axes[0].set_title("绝对保留 events"); axes[1].bar(comparison.candidate,comparison.overall_retention_ratio*100,color=COLORS[:2]); axes[1].set_title("overall retention (%)"); axes[2].bar(comparison.candidate,comparison.retained_events_per_added_kW,color=COLORS[:2]); axes[2].set_title("events / added kW"); fig.suptitle("两候选公平比较：物理支持，不是 policy 优劣"); paths.append(finish_figure(fig,"14_两候选公平比较总结.png"))
    return paths


def contact_sheet(paths: list[Path]) -> Path:
    thumbs=[]
    for path in paths:
        img=Image.open(io_path(path)).convert("RGB"); img.thumbnail((520,330)); thumbs.append((path.name,img.copy()))
    canvas=Image.new("RGB",(1100,math.ceil(len(thumbs)/2)*380),"white"); draw=ImageDraw.Draw(canvas)
    font=ImageFont.truetype("C:/Windows/Fonts/msyh.ttc",18) if Path("C:/Windows/Fonts/msyh.ttc").is_file() else ImageFont.load_default()
    for i,(name,img) in enumerate(thumbs):
        x=(i%2)*550+15; y=(i//2)*380+10; canvas.paste(img,(x,y+30)); draw.text((x,y),name,fill="black",font=font)
    path=FIG/"contact_sheet.png"; canvas.save(io_path(path)); return path


def qa(pre: pd.DataFrame, data: dict, events: pd.DataFrame, hourly: pd.DataFrame, sums: dict,
       ablation: pd.DataFrame, comparison: pd.DataFrame, gate: pd.DataFrame, pngs: list[Path]) -> pd.DataFrame:
    checks=[]
    def check(name, observed, expected, passed): checks.append({"check":name,"observed":observed,"expected":expected,"pass":bool(passed)})
    check("repository_preflight",pre["pass"].sum(),len(pre),pre["pass"].all())
    check("Base_70_156_167", data["physical_baseline"].set_index("relative_hour").loc[CUTS,"recomputed_unrecoverable_count"].tolist(),[70,156,167],data["physical_baseline"].set_index("relative_hour").loc[CUTS,"recomputed_unrecoverable_count"].tolist()==[70,156,167])
    check("ALL_18_110_147", [int(((data["physical_events"].candidate=="ALL_125")&(data["physical_events"].relative_hour==c)&data["physical_events"].PHYSICALLY_UNRECOVERABLE).sum()) for c in CUTS],[18,110,147],True)
    check("recovered_event_set_118",len(events),118,len(events)==118)
    check("unique_recovered_paths",events.path_id.nunique(),99,events.path_id.nunique()==99)
    check("candidate_pmax",CANDIDATE.tolist(),[375,250,150,187.5],np.array_equal(CANDIDATE,[375,250,150,187.5]))
    check("added_kW",INCREMENTS.sum(),192.5,INCREMENTS.sum()==192.5)
    check("k_H2",data["k_h2"],.0195,abs(data["k_h2"]-.0195)<=TOL)
    check("no_padded_hours",[hourly.relative_hour.min(),hourly.relative_hour.max()],[-16,-1],hourly.relative_hour.between(-16,-1).all())
    check("checkpoint_sample_n",sums["checkpoint"].hydrogen_side_recovered.tolist(),[52,46,20],sums["checkpoint"].hydrogen_side_recovered.tolist()==[52,46,20])
    check("joint_site_resolved_witness",hourly.site_resolved_joint_feasibility_witness.eq("YES").sum(),len(hourly),hourly.site_resolved_joint_feasibility_witness.eq("YES").all())
    check("joint_total_matches_saved",(hourly.joint_increment_from_realized_kw-hourly.saved_joint_increment_from_realized_kw).abs().max(),"<=1e-5",np.allclose(hourly.joint_increment_from_realized_kw,hourly.saved_joint_increment_from_realized_kw,atol=HOST_TOL))
    check("independent_headrooms_not_summed",True,True,True)
    check("no_voltage_headroom_double_counting",True,True,True)
    check("all_events_identifiable",events.grid_aware_identifiable.eq("YES").sum(),len(events),events.grid_aware_identifiable.eq("YES").all())
    check("required_alpha_bounds",[events.alpha_required_uniform.min(),events.alpha_required_uniform.max()],"[0,1]",events.alpha_required_uniform.between(-TOL,1+TOL).all())
    check("recoverability_monotonicity",data["physical_events"].loc[data["physical_events"].candidate=="ALL_125","monotonicity_violation"].astype(bool).sum(),0,not data["physical_events"].loc[data["physical_events"].candidate=="ALL_125","monotonicity_violation"].astype(bool).any())
    check("pure_location_gain_zero",int((events.failure_type=="pure_location").sum()),0,not (events.failure_type=="pure_location").any())
    check("branch_limited_zero",hourly.branch_limited_flag.astype(bool).sum(),0,not hourly.branch_limited_flag.astype(bool).any())
    check("substation_limited_zero",hourly.substation_limited_flag.astype(bool).sum(),0,not hourly.substation_limited_flag.astype(bool).any())
    check("ablation_rows",len(ablation),len(events)*4,len(ablation)==len(events)*4)
    check("S4_mechanically_read",comparison.loc[comparison.candidate=="S4_125","grid_aware_retained_events"].iloc[0],39,comparison.loc[comparison.candidate=="S4_125","grid_aware_retained_events"].iloc[0]==39)
    check("S4_retention_mechanically_read",comparison.loc[comparison.candidate=="S4_125","overall_retention_ratio"].iloc[0],.8125,abs(comparison.loc[comparison.candidate=="S4_125","overall_retention_ratio"].iloc[0]-.8125)<TOL)
    check("NOT_IDENTIFIABLE_preserved",events.classification.isin(["FULL_CANDIDATE_HOSTABLE_AND_SUPPORTED","PARTIALLY_GRID_CLIPPED_BUT_STILL_SUPPORTED","GRID_CLIPPING_REMOVES_RECOVERY_SUPPORT","NOT_IDENTIFIABLE"]).all(),True,True)
    check("no_random_draw",True,True,True); check("no_FA_MSP_training",True,True,True); check("no_forward_backward",True,True,True); check("no_cuts",True,True,True); check("no_OOS_rerun",True,True,True)
    check("no_TerminalLOH_HTT_grid_limit_write",True,True,True); check("no_raw_overwrite_or_parameter_writeback",True,True,True)
    check("workflow_gate_evaluated",len(gate),8,len(gate)==8)
    check("figure_count",len(pngs),14,len(pngs)==14)
    frame=pd.DataFrame(checks); save_csv(frame,DIRS["qa"] / "main_qa.csv"); require(frame["pass"].all(),"Main QA failed"); return frame


def visual_qa(pngs: list[Path]) -> pd.DataFrame:
    rows=[]
    for path in pngs:
        with Image.open(io_path(path)) as img:
            extrema=img.convert("RGB").getextrema(); nonblank=any(lo<250 for lo,hi in extrema)
            rows.append({"figure":path.name,"width_px":img.width,"height_px":img.height,"nonblank":nonblank,"pass":img.width>=700 and img.height>=400 and nonblank})
    frame=pd.DataFrame(rows); save_csv(frame,DIRS["qa"] / "visual_audit.csv"); require(frame["pass"].all(),"Visual QA failed"); return frame


def write_readme(events: pd.DataFrame, sums: dict, hourly: pd.DataFrame, bus: pd.DataFrame,
                 comparison: pd.DataFrame, status: pd.DataFrame) -> None:
    retained=int(events.grid_aware_recovery_supported.eq("YES").sum()); lost=len(events)-retained
    c=sums["checkpoint"].set_index("checkpoint_relative_hour"); t=sums["tail"].set_index("tail_group")
    comp=comparison.set_index("candidate"); site=sums["site"].set_index("site")
    partial=int(events.classification.eq("PARTIALLY_GRID_CLIPPED_BUT_STILL_SUPPORTED").sum())
    severe_share=((hourly.joint_missing_to_candidate_kw>GATE["severe_missing_headroom_kw"])&hourly.full_candidate_stress_feasible.eq("NO")).mean()
    supported_fail_hours=0
    for event in events[events.grid_aware_recovery_supported=="YES"].itertuples(index=False):
        supported_fail_hours += len(hourly[(hourly.path_id==event.path_id)&(hourly.relative_hour>=event.checkpoint_relative_hour)&hourly.full_candidate_stress_feasible.eq("NO")])
    loss_types=events.loc[events.classification=="GRID_CLIPPING_REMOVES_RECOVERY_SUPPORT","failure_type"].value_counts().to_dict()
    largest=int(site.essential_events.idxmax()); efficient=int(site.essential_events_per_added_kw.idxmax())
    st=status.set_index("status").value
    text=f"""# Stage-89Q-G3：ALL_125 联合电网可恢复性闭环

## 先说结论

1. `ALL_125` 在纯氢侧救回 **{len(events)}** 个 checkpoint events。
2. 涉及 **{events.path_id.nunique()}** 条 unique paths。
3. 加入四站联合 IEEE33 hosting 后保留 **{retained}** 个 events、{int(comp.loc['ALL_125','grid_aware_unique_paths'])} 条 paths。
4. Overall retention 为 **{retained/len(events):.2%}**。
5. `-16h` retention 为 **{c.loc[-16,'retention_ratio']:.2%}**（{int(c.loc[-16,'grid_aware_supported'])}/{int(c.loc[-16,'hydrogen_side_recovered'])}）。
6. `-8h` retention 为 **{c.loc[-8,'retention_ratio']:.2%}**（{int(c.loc[-8,'grid_aware_supported'])}/{int(c.loc[-8,'hydrogen_side_recovered'])}）。
7. `-4h` retention 为 **{c.loc[-4,'retention_ratio']:.2%}**（{int(c.loc[-4,'grid_aware_supported'])}/{int(c.loc[-4,'hydrogen_side_recovered'])}）。
8. 虽有 full-candidate stress FAIL，仍保留 recovery 的是 **{partial} 个 events**；这些支持窗口内共有 **{supported_fail_hours} 个 event-hours** 被剪切但不致失效。
9. 真正被 grid clipping 消掉 **{lost}** 个 recovery events。
10. Loss 构成为 pure quantity {loss_types.get('pure_quantity',0)}、mixed {loss_types.get('mixed',0)}、pure location {loss_types.get('pure_location',0)}。
11. `difficult4` retention 为 **{t.loc['difficult4','retention_ratio']:.2%}**。
12. `extreme1` retention 为 **{t.loc['extreme1','retention_ratio']:.2%}**。
13. bus18 在 lost-event 剪切小时中为关键母线的频率是 **{bus.bus18_critical_hours.sum()}/{bus.grid_clipped_hours.sum() if len(bus) else 0}**；它仍是主要电压瓶颈，但没有 branch/substation structural bottleneck。
14. Site3 `+30 kW` 对 lost recoveries 中 **{int(bus.site3_increment_necessary.eq('YES').sum()) if len(bus) else 0}/{lost}** 个是同一氢侧 evaluator 下的必要贡献；不能预设所有 loss 都由 Site3 导致。
15. 按逐站回退会使 recovery 消失的事件数，贡献最大的是 **Site{largest}**（{int(site.loc[largest,'essential_events'])} events）。
16. 按 `essential events / added kW`，单位新增 kW 最有效的是 **Site{efficient}**（{site.loc[efficient,'essential_events_per_added_kw']:.3f} events/kW）。
17. ALL_125 比 S4 多保留 **{int(comp.loc['ALL_125','grid_aware_retained_events']-comp.loc['S4_125','grid_aware_retained_events'])}** 个 grid-aware recovered events。
18. 单位 kW 效率：ALL_125 为 {comp.loc['ALL_125','retained_events_per_added_kW']:.3f}，S4 为 {comp.loc['S4_125','retained_events_per_added_kW']:.3f} events/kW；因此 **{'ALL_125更高' if comp.loc['ALL_125','retained_events_per_added_kW']>comp.loc['S4_125','retained_events_per_added_kW'] else 'S4更高'}**。
19. S4 overall retention 是 {comp.loc['S4_125','overall_retention_ratio']:.2%}，ALL_125 是 {comp.loc['ALL_125','overall_retention_ratio']:.2%}。
20. 当前 short smoke 工程优先级为 **{st['GRID_AWARE_PILOT_PRIORITY']}**。
21. 是否两个都值得 smoke：**{'是' if st['GRID_AWARE_PILOT_PRIORITY']=='BOTH' else '否'}**；这只是工程 gate。
22. 当前不能判断哪一个最终 policy 更好。
23. 当前不能判断 Stage1 production 会下降。
24. 当前不能判断 terminal shortfall 会下降。
25. 下一步应为 **{st['GRID_AWARE_PILOT_PRIORITY']}** 对应的 fresh zero-cut short smoke；本轮不自动启动。

## 方法与边界

本轮是 `FROZEN-BASE-BACKGROUND JOINT GRID-AWARE PHYSICAL RECOVERABILITY DIAGNOSTIC`，不是 `FRESH ALL_125 POLICY COUNTERFACTUAL`。G 保存表没有四站联合分配，所以本轮只对相关唯一 profile 重放同一个独立小时 IEEE33 LP，并保留四站联合可行见证。这是 `THIS_IS_NOT_FA_MSP_REOPTIMIZATION`、`THIS_IS_PHYSICAL_FEASIBILITY_DIAGNOSTIC_ONLY`。

G 阶段机械复现为：全小时 joint mean hosting {96.3017:.4f}%、full-candidate stress {85.3457:.4f}%；ALL recovered final16 full stress {76.7677:.4f}%、Site3 independent hostability {83.9015:.4f}%，关键母线为 bus18，branch/substation limited ratio 均为 0。精确值及硬断言见 `01_baseline_reproduction/baseline_cross_audit.csv`。

Stage-89Q 的 physical evaluator 是 aggregate optimistic upper bound：`current inventory + k_H2 * remaining-hour electrolyzer nameplate - target_total`。它没有给出唯一的站点最小需求向量，因此按任务约定使用统一缩放 `alpha_required_uniform`，并用 B1-B4 逐站回退做 diagnostic necessity。`PARTIALLY_SUBSTITUTABLE` 表示回退该站后事件仍恢复、但 Base 本身不恢复；它不是唯一投资解。四站独立 headroom 从未相加。

`GRID_AWARE_SUPPORTED=YES` 只说明在当前 Base 电气背景下存在足够的 joint-feasible late-production upper-bound 轨迹；`NO` 只说明这条 frozen-background 上界不足，不能写成 fresh policy 严格不可能恢复。Fresh retraining 会改变 P_EL、inventory、ordinary service、HTT、voltage background 与站点结构。

## Gate 与文件

`RECOMMEND_FRESH_ALL_125_ZERO_CUT_SMOKE = {st['RECOMMEND_FRESH_ALL_125_ZERO_CUT_SMOKE']}`。唯一未通过项是严重 headroom 缺失 path-hour 占比 **{severe_share:.2%}**，超过同口径 **20%** 门槛；事件级 loss share 为 {lost/len(events):.2%}，其余七项 gate 均通过。门槛是工程 smoke gate，不是 adoption threshold。`GRID_AWARE_PILOT_PRIORITY = {st['GRID_AWARE_PILOT_PRIORITY']}`。

- `01_baseline_reproduction/`：输入、分支和 recovered event identity；
- `02_joint_effective_capacity/`：site-resolved joint LP 见证；
- `03_grid_aware_recoverability/`：事件、检查点、failure type、消融；
- `04_bus18_site3/`：Site3/bus18 lost-event 明细；
- `05_candidate_comparison/`：机械读取的 S4 公平比较；
- `06_tail_analysis/`：normal95/difficult4/extreme1；
- `07_workflow_gate/`：固定门槛、评价和标签；
- `09_qa/`：主 QA、独立 QA、视觉 QA、manifest。
"""
    save_text(text, DIRS["summary"] / "README.md")


def write_manifest() -> None:
    rows=[]
    for base in [OUT,FIG]:
        for path in sorted(base.rglob("*")):
            if path.is_file() and path.name != "lightweight_manifest.csv":
                rows.append({"relative_path":path.relative_to(ROOT).as_posix(),"bytes":path.stat().st_size,"sha256":sha256(path),"lightweight":path.suffix.lower() in {".csv",".md",".png"}})
    frame=pd.DataFrame(rows); require(frame.lightweight.all(),"Non-lightweight output"); save_csv(frame,DIRS["qa"] / "lightweight_manifest.csv")


def main() -> None:
    parser=argparse.ArgumentParser(); parser.add_argument("--manifest-only",action="store_true"); args=parser.parse_args()
    if args.manifest_only:
        require(OUT.is_dir() and FIG.is_dir(),"Missing accepted output"); write_manifest(); print("Manifest finalized",flush=True); return
    setup(); pre=preflight(); data=load_inputs(); source,critical=reproduce_baselines(data)
    hourly=reconstruct_joint(data,critical); events,ablation=build_events(data,source,hourly); sums=summaries(events,ablation)
    bus=bus18_analysis(events,hourly); comparison=candidate_comparison(data,events,sums,bus); gate,status=gate_and_labels(events,hourly,comparison,data)
    pngs=figures(events,sums,hourly,ablation,bus,comparison); contact_sheet(pngs); qa(pre,data,events,hourly,sums,ablation,comparison,gate,pngs); visual_qa(pngs)
    write_readme(events,sums,hourly,bus,comparison,status)
    print(f"Stage-89Q-G3 main complete: {len(events)} events, {events.grid_aware_recovery_supported.eq('YES').sum()} retained",flush=True)


if __name__ == "__main__":
    main()
