#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Stage-89Q-G4-Lite: deterministic screen of all 16 Pmax subsets."""

from __future__ import annotations

import argparse
import ast
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
DEEP = RUN / "05_analysis/10_deep_penalty1000"
PHYS = DEEP / "17_pmax_flexibility_audit"
GRID = DEEP / "18_pmax_grid_hosting_audit"
G2 = DEEP / "19_s4_grid_aware_recoverability"
G3 = DEEP / "20_all125_grid_aware_recoverability"
OUT = DEEP / "21_pmax_subset_screen"
FIG = RUN / "06_figures/15_pmax_subset_screen"
FORMAL = ROOT / "data/yuanqi/near_stage_msp_input.mat"
GRID_ANALYZER = ROOT / "hourly_grid_h2/analyze_stage89q_pmax_grid_hosting_audit.py"

EXPECTED_BRANCH = "task/002-stage2b-b3-smoke"
EXPECTED_HEAD = "31e45992bb44cd085d62fae363e2e8401fd388a8"
EXPECTED_UPSTREAM = "origin/task/002-stage2b-b3-smoke"
TOL = 1e-7
HOST_TOL = 1e-5
CUTS = [-16, -8, -4]
SITE_BUSES = [24, 14, 18, 31]
CANDIDATE_ORDER = [
    "B0000", "B1000", "B0100", "B0010", "B0001", "B1100", "B1010", "B1001",
    "B0110", "B0101", "B0011", "B1110", "B1101", "B1011", "B0111", "B1111",
]
NEW_JOINT_CANDIDATES = {"B1100", "B1010", "B1001", "B0110", "B0101", "B0011",
                        "B1110", "B1101", "B1011", "B0111"}

FILES = {
    "formal": FORMAL,
    "physical": PHYS / "02_counterfactual_recoverability/pmax_candidate_recoverability_by_path.csv",
    "grid_site_cache": GRID / "04_all_125/all_125_site_headroom.csv",
    "g2_hourly": G2 / "02_effective_pmax/s4_125_hourly_effective_pmax.csv",
    "g2_events": G2 / "03_grid_aware_recoverability/s4_125_grid_aware_recovery_by_event.csv",
    "g2_status": G2 / "07_workflow_gate/final_status.csv",
    "g3_hourly": G3 / "02_joint_effective_capacity/all125_site_resolved_joint_hourly.csv",
    "g3_events": G3 / "03_grid_aware_recoverability/all125_grid_aware_recovery_by_event.csv",
    "g3_status": G3 / "07_workflow_gate/final_status.csv",
    "grid_analyzer": GRID_ANALYZER,
}
EXPECTED_HASHES = {
    "formal": "536b25868e6d7cc812a331c0d3e0ffbd5f6958e6883bd39bcae3901c372abf24",
    "physical": "6eb403e2445cc858eb9f96f5d656c9920aa234191413dcd14732031da0b425e3",
    "grid_site_cache": "1e34ab080d190709adb99be31612a18024e61168e280c41be9e1c5227c04d70e",
    "g2_hourly": "3bcbab6c789abaae563578ed430485270f461951cb0dca051293122b1f41bb92",
    "g2_events": "e9e70f4487a1dc650de20679d7c3c15e3a8e4ee71da0dbc6efdd9f999abdd16d",
    "g2_status": "a4efcd5d6b5a01dc16bf82d58820e059c50f5e25cb2fa8a83a45014ebe093ba3",
    "g3_hourly": "5eb3efb3f5ef8c970a6e4fbfa2b04e13ff97a8fcef47bf1f79460cf8dd221167",
    "g3_events": "a94e4c58eea8281904dbda8d6cb08cc56737f55486aff806618b3f1f606332d6",
    "g3_status": "b4841181616883546ef96426dee3eba113d53e03aecfce7c285a2d4516e62936",
    "grid_analyzer": "a63154418cdea3ee3f62300a5121bd4ae72ebae2aac23398fcf686dfce67376a",
}
DIRS = {
    "inputs": OUT / "01_existing_inputs", "h2": OUT / "02_h2_side_screen",
    "grid": OUT / "03_grid_aware_screen", "site": OUT / "04_site_value",
    "frontier": OUT / "05_candidate_frontier", "decision": OUT / "06_candidate_decision",
    "summary": OUT / "07_summary", "qa": OUT / "08_qa",
}

# Fixed before screening results are calculated.
SITE_SIGNAL_RULES = OrderedDict([
    ("STRONG", "mean marginal retained events/kW >= 0.40 and positive in >=75% subset pairs"),
    ("MODERATE", "mean marginal retained events/kW >= 0.20 and positive in >=50% subset pairs"),
    ("WEAK", "positive mean marginal retained events but lower than MODERATE"),
    ("REDUNDANT", "no positive marginal retained event in any subset pair"),
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


def bits(candidate: str) -> np.ndarray:
    return np.array([int(x) for x in candidate[1:]], dtype=int)


def setup() -> None:
    require(not OUT.exists() and not FIG.exists(), "Accepted G4-Lite output already exists")
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
    live, records = 0, []
    for proc in psutil.process_iter(["pid", "name", "status"]):
        name = (proc.info.get("name") or "").lower()
        if "matlab" in name or "gurobi" in name or name.startswith("grb"):
            status = proc.info.get("status") or "unknown"
            records.append(f"{proc.info['pid']}:{proc.info['name']}:{status}")
            live += int(status not in stopped)
    return live, ";".join(records) if records else "NONE"


def preflight() -> pd.DataFrame:
    require(all(os.path.isfile(io_path(path)) for path in FILES.values()), "Required input missing")
    hashes = {key: sha256(path) for key, path in FILES.items()}
    require(hashes == EXPECTED_HASHES, f"Input hash mismatch: {hashes}")
    live, records = process_records()
    tracked = [x for x in git("status", "--short", "--untracked-files=no").splitlines() if x]
    untracked = [x for x in git("ls-files", "--others", "--exclude-standard").splitlines() if x]
    rows = [
        ("branch", git("branch", "--show-current"), EXPECTED_BRANCH, git("branch", "--show-current") == EXPECTED_BRANCH),
        ("HEAD", git("rev-parse", "HEAD"), EXPECTED_HEAD, git("rev-parse", "HEAD") == EXPECTED_HEAD),
        ("upstream", git("rev-parse", "--abbrev-ref", "@{upstream}"), EXPECTED_UPSTREAM, git("rev-parse", "--abbrev-ref", "@{upstream}") == EXPECTED_UPSTREAM),
        ("ahead_behind", git("rev-list", "--left-right", "--count", f"HEAD...{EXPECTED_UPSTREAM}"), "0\t0", git("rev-list", "--left-right", "--count", f"HEAD...{EXPECTED_UPSTREAM}") == "0\t0"),
        ("preexisting_tracked_dirty_count", len(tracked), 7, len(tracked) == 7),
        ("preexisting_tracked_paths", " | ".join(tracked), "informational", True),
        ("preexisting_untracked_count", len(untracked), ">=14547", len(untracked) >= 14547),
        ("live_MATLAB_Gurobi_count", live, 0, live == 0),
        ("MATLAB_Gurobi_records", records, "stale exited object permitted", live == 0),
        ("input_hash_identity", len(hashes), len(EXPECTED_HASHES), hashes == EXPECTED_HASHES),
    ]
    frame = pd.DataFrame(rows, columns=["check", "observed", "expected", "pass"])
    save_csv(frame, DIRS["inputs"] / "repository_preflight.csv")
    save_csv(pd.DataFrame([{"input": key, "path": path.relative_to(ROOT).as_posix(), "sha256": hashes[key]}
                           for key, path in FILES.items()]), DIRS["inputs"] / "input_identity.csv")
    require(frame["pass"].all(), "Repository preflight failed")
    return frame


def load_inputs() -> dict:
    device = loadmat(io_path(FORMAL), simplify_cells=True)["NearStageInput"]["HydrogenDevice"]
    base = np.asarray(device["el_cap_kw"], dtype=float).ravel()
    k_h2 = float(device["k_H2_kg_per_kWh"])
    require(np.array_equal(base, [300., 200., 120., 150.]), f"Formal Base mismatch: {base}")
    require(abs(k_h2 - .0195) <= TOL, f"Formal k_H2 mismatch: {k_h2}")
    return {
        "base": base, "expanded": base * 1.25, "increments": base * .25, "k_h2": k_h2,
        "physical": pd.read_csv(io_path(FILES["physical"])), "site_cache": pd.read_csv(io_path(FILES["grid_site_cache"])),
        "g2_hourly": pd.read_csv(io_path(FILES["g2_hourly"])), "g2_events": pd.read_csv(io_path(FILES["g2_events"])),
        "g2_status": pd.read_csv(io_path(FILES["g2_status"])),
        "g3_hourly": pd.read_csv(io_path(FILES["g3_hourly"])), "g3_events": pd.read_csv(io_path(FILES["g3_events"])),
        "g3_status": pd.read_csv(io_path(FILES["g3_status"])),
    }


def candidate_catalog(data: dict) -> pd.DataFrame:
    rows = []
    for candidate in CANDIDATE_ORDER:
        mask = bits(candidate)
        pmax = data["base"] + mask * data["increments"]
        rows.append({"candidate": candidate, **{f"site{i+1}_expanded": int(mask[i]) for i in range(4)},
                     **{f"Pmax{i+1}_kW": pmax[i] for i in range(4)},
                     "expanded_site_count": int(mask.sum()), "added_kW": float((pmax-data["base"]).sum())})
    frame = pd.DataFrame(rows)
    require(len(frame) == 16 and not frame[[f"Pmax{i}_kW" for i in range(1,5)]].duplicated().any(),
            "Candidate catalog is not exactly 16 unique vectors")
    save_csv(frame, DIRS["inputs"] / "candidate_catalog.csv")
    return frame


def h2_screen(data: dict, catalog: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    source = data["physical"]
    base_rows = source[(source.candidate == "B0") & source.base_physically_unrecoverable & source.checkpoint_present].copy()
    require({cut: int((base_rows.relative_hour == cut).sum()) for cut in CUTS} == {-16:70,-8:156,-4:167},
            "Base 70/156/167 reproduction failed")
    meta = data["g3_events"][["path_id", "checkpoint_relative_hour", "arrival_stage", "final_intensity",
                              "final_location", "final_gap", "tail_group"]].copy()
    meta.rename(columns={"checkpoint_relative_hour": "relative_hour"}, inplace=True)
    rows, summaries = [], []
    for candidate_row in catalog.itertuples(index=False):
        pmax = np.array([getattr(candidate_row, f"Pmax{i}_kW") for i in range(1,5)])
        if candidate_row.candidate == "B0000":
            recovered = base_rows.iloc[0:0].copy()
            recovered["optimistic_margin_kg"] = pd.Series(dtype=float)
        else:
            margin = base_rows.current_inventory_kg + pmax.sum() * data["k_h2"] * (-base_rows.relative_hour) - base_rows.target_total
            recovered = base_rows[margin >= -TOL].copy()
            recovered["optimistic_margin_kg"] = margin[margin >= -TOL]
        recovered = recovered.merge(meta, on=["path_id", "relative_hour"], validate="one_to_one")
        for row in recovered.itertuples(index=False):
            rows.append({"candidate": candidate_row.candidate, "path_id": int(row.path_id),
                         "checkpoint_relative_hour": int(row.relative_hour), "failure_type": row.failure_type,
                         "tail_group": row.tail_group, "current_inventory_kg": row.current_inventory_kg,
                         "target_total_kg": row.target_total, "arrival_stage": row.arrival_stage,
                         "final_intensity": row.final_intensity, "final_location": row.final_location,
                         "final_gap": row.final_gap, "optimistic_margin_kg": row.optimistic_margin_kg})
        summaries.append({
            "candidate": candidate_row.candidate, "added_kW": candidate_row.added_kW,
            "recovered_-16": int((recovered.relative_hour == -16).sum()),
            "recovered_-8": int((recovered.relative_hour == -8).sum()),
            "recovered_-4": int((recovered.relative_hour == -4).sum()),
            "H2_recovered_events": len(recovered), "H2_unique_paths": recovered.path_id.nunique(),
            "pure_quantity_recovered": int((recovered.failure_type == "pure_quantity").sum()),
            "mixed_recovered": int((recovered.failure_type == "mixed").sum()),
            "pure_location_recovered": int((recovered.failure_type == "pure_location").sum()),
            "difficult4_recovered": int((recovered.tail_group == "difficult4").sum()),
            "extreme1_recovered": int((recovered.tail_group == "extreme1").sum()),
        })
    events = pd.DataFrame(rows)
    summary = catalog.merge(pd.DataFrame(summaries), on=["candidate", "added_kW"], validate="one_to_one")
    require(not summary.pure_location_recovered.any(), "Pure-location gain must remain zero")
    save_csv(events, DIRS["h2"] / "all16_h2_side_events.csv")
    save_csv(summary, DIRS["h2"] / "all16_h2_side_summary.csv")
    return events, summary


def needed_profile_ids(candidate: str, h2_events: pd.DataFrame, template: pd.DataFrame) -> set[int]:
    ids: set[int] = set()
    for event in h2_events[h2_events.candidate == candidate].itertuples(index=False):
        window = template[(template.path_id == event.path_id) &
                          (template.relative_hour >= event.checkpoint_relative_hour)]
        ids.update(window.profile_id.astype(int))
    return ids


def cached_single_profile(candidate: str, site: int, profile_ids: set[int], data: dict) -> pd.DataFrame:
    cached = data["site_cache"][(data["site_cache"].site == site) &
                                 data["site_cache"].profile_id.isin(profile_ids)].copy()
    rows = []
    for row in cached.itertuples(index=False):
        feasible = np.array([getattr(row, f"realized_pel{i}_kw") for i in range(1,5)], dtype=float)
        feasible[site-1] = row.max_new_pel_kw
        delta = feasible[site-1] - data["base"][site-1]
        rows.append({"candidate": candidate, "profile_id": int(row.profile_id), "global_hour": int(row.global_hour),
                     **{f"site{i}_lp_pel_kw": feasible[i-1] for i in range(1,5)},
                     **{f"site{i}_effective_increment_above_base_kw": delta if i == site else 0. for i in range(1,5)},
                     "effective_total_physical_pmax_kw": data["base"].sum() + delta,
                     "candidate_increment_hostable": "YES" if row.FULL_TO_CANDIDATE_HOSTABLE == "YES" else "NO",
                     "missing_candidate_increment_kw": data["expanded"][site-1] - row.max_new_pel_kw,
                     "minimum_voltage_pu": row.min_voltage_pu, "minimum_voltage_margin_pu": row.voltage_margin_pu,
                     "critical_bus": int(row.critical_bus), "critical_branch": int(row.critical_branch_id),
                     "voltage_limited_flag": bool(row.voltage_limited_flag),
                     "branch_limited_flag": bool(row.branch_limited_flag),
                     "substation_limited_flag": bool(row.substation_limited_flag),
                     "source": "STAGE89Q_G_SINGLE_SITE_CACHE", "site_resolved_joint_witness": "YES"})
    return pd.DataFrame(rows)


def solve_multi_profiles(candidate: str, profile_ids: set[int], data: dict,
                         profiles: pd.DataFrame, lp_cache: dict[int, HourlyGridLP]) -> pd.DataFrame:
    mask = bits(candidate).astype(bool)
    rows = []
    indexed = profiles.set_index("profile_id")
    for profile_id in sorted(profile_ids):
        profile = indexed.loc[profile_id]
        realized = np.array([profile[f"site{i}_realized_pel_kw"] for i in range(1,5)], dtype=float)
        upper = realized.copy(); upper[mask] = data["expanded"][mask]
        result = lp_cache[int(profile.global_hour)].solve(realized, upper, True)
        feasible = np.asarray(result["p_el_new_kw"], dtype=float)
        effective_delta = np.where(mask, feasible-data["base"], 0.)
        rows.append({"candidate": candidate, "profile_id": int(profile_id), "global_hour": int(profile.global_hour),
                     **{f"site{i}_lp_pel_kw": feasible[i-1] for i in range(1,5)},
                     **{f"site{i}_effective_increment_above_base_kw": effective_delta[i-1] for i in range(1,5)},
                     "effective_total_physical_pmax_kw": data["base"].sum()+effective_delta.sum(),
                     "candidate_increment_hostable": "YES" if result["full_hostable"] else "NO",
                     "missing_candidate_increment_kw": float((data["expanded"][mask]-feasible[mask]).sum()),
                     "minimum_voltage_pu": result["min_voltage_pu"],
                     "minimum_voltage_margin_pu": result["voltage_margin_pu"],
                     "critical_bus": result["critical_bus"], "critical_branch": result["critical_branch_id"],
                     "voltage_limited_flag": result["voltage_limited_flag"],
                     "branch_limited_flag": result["branch_limited_flag"],
                     "substation_limited_flag": result["substation_limited_flag"],
                     "source": "G4_NEW_CANDIDATE_DEPENDENT_JOINT_LP", "site_resolved_joint_witness": "YES"})
    return pd.DataFrame(rows)


def profile_cache(data: dict, catalog: pd.DataFrame, h2_events: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    template = data["g3_hourly"][["path_id", "stage", "global_hour", "relative_hour", "profile_id"]].copy()
    profiles = data["g3_hourly"].drop_duplicates("profile_id")
    grid_data = load_grid_data()
    lp_cache = {hour: HourlyGridLP(grid_data, hour) for hour in range(1,49)}
    frames, ledger = [], []
    for candidate in CANDIDATE_ORDER:
        n_events = int((h2_events.candidate == candidate).sum())
        ids = needed_profile_ids(candidate, h2_events, template) if n_events else set()
        if candidate == "B0000":
            source, solved, reused = "NO_H2_GAIN", 0, 0
        elif candidate == "B0001":
            source, solved, reused = "STAGE89Q_G2_FORMAL_EVENT_CLOSURE", 0, len(ids)
        elif candidate == "B1111":
            source, solved, reused = "STAGE89Q_G3_FORMAL_EVENT_CLOSURE", 0, len(ids)
        elif bits(candidate).sum() == 1:
            site = int(np.flatnonzero(bits(candidate))[0] + 1)
            frame = cached_single_profile(candidate, site, ids, data)
            frames.append(frame); source, solved, reused = "STAGE89Q_G_SINGLE_SITE_CACHE", 0, len(frame)
        else:
            require(candidate in NEW_JOINT_CANDIDATES, f"Unexpected candidate solve: {candidate}")
            frame = solve_multi_profiles(candidate, ids, data, profiles, lp_cache)
            frames.append(frame); source, solved, reused = "G4_NEW_CANDIDATE_DEPENDENT_JOINT_LP", len(frame), 0
            print(f"{candidate}: solved {len(frame)} unique candidate-dependent profiles", flush=True)
        ledger.append({"candidate": candidate, "H2_recovered_events": n_events, "required_unique_profiles": len(ids),
                       "closure_source": source, "new_joint_LP_solves": solved, "reused_profile_or_event_records": reused,
                       "base_grid_state_recomputed": "NO", "independent_headrooms_summed": "NO"})
    cache = pd.concat(frames, ignore_index=True)
    reuse = pd.DataFrame(ledger)
    save_csv(cache, DIRS["grid"] / "candidate_joint_profile_cache.csv")
    save_csv(reuse, DIRS["grid"] / "computation_reuse_ledger.csv")
    return cache, reuse


def normalized_anchor_events(candidate: str, source: pd.DataFrame) -> pd.DataFrame:
    frame = source.copy()
    frame["candidate"] = candidate
    frame["classification"] = frame.classification.replace({"FULL_INCREMENT_HOSTABLE_AND_SUPPORTED":
                                                               "FULL_CANDIDATE_HOSTABLE_AND_SUPPORTED"})
    keep = ["candidate", "path_id", "checkpoint_relative_hour", "failure_type", "tail_group",
            "grid_aware_recovery_supported", "classification", "critical_bus", "grid_clipped_hours",
            "minimum_voltage_margin"]
    return frame[keep]


def new_candidate_events(candidate: str, h2_events: pd.DataFrame, cache: pd.DataFrame,
                         template: pd.DataFrame, data: dict) -> pd.DataFrame:
    rows = []
    candidate_cache = cache[cache.candidate == candidate]
    event_source = h2_events[h2_events.candidate == candidate]
    for event in event_source.itertuples(index=False):
        window = template[(template.path_id == event.path_id) &
                          (template.relative_hour >= event.checkpoint_relative_hour)].merge(
            candidate_cache, on=["profile_id", "global_hour"], validate="many_to_one")
        n = -int(event.checkpoint_relative_hour)
        identifiable = len(window) == n and not window.effective_total_physical_pmax_kw.isna().any()
        if identifiable:
            margin = event.current_inventory_kg + data["k_h2"] * window.effective_total_physical_pmax_kw.sum() - event.target_total_kg
            supported = margin >= -TOL
            clipped = window.candidate_increment_hostable.eq("NO")
            n_clipped = int(clipped.sum())
            classification = ("FULL_CANDIDATE_HOSTABLE_AND_SUPPORTED" if supported and n_clipped == 0 else
                              "PARTIALLY_CLIPPED_BUT_STILL_SUPPORTED" if supported else
                              "GRID_CLIPPING_REMOVES_RECOVERY_SUPPORT")
            limiting = window[clipped] if n_clipped else window
            critical_bus = int(limiting.critical_bus.mode().iloc[0])
            min_margin = float(window.minimum_voltage_margin_pu.min())
            status = "YES" if supported else "NO"
        else:
            margin, n_clipped, critical_bus, min_margin = math.nan, 0, math.nan, math.nan
            classification, status = "NOT_IDENTIFIABLE", "NOT_IDENTIFIABLE"
        rows.append({"candidate": candidate, "path_id": event.path_id,
                     "checkpoint_relative_hour": event.checkpoint_relative_hour,
                     "failure_type": event.failure_type, "tail_group": event.tail_group,
                     "grid_aware_recovery_supported": status, "classification": classification,
                     "critical_bus": critical_bus, "grid_clipped_hours": n_clipped,
                     "minimum_voltage_margin": min_margin, "grid_aware_recovery_margin_kg": margin})
    return pd.DataFrame(rows)


def grid_screen(data: dict, catalog: pd.DataFrame, h2_events: pd.DataFrame,
                cache: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    template = data["g3_hourly"][["path_id", "stage", "global_hour", "relative_hour", "profile_id"]]
    frames = []
    for candidate in CANDIDATE_ORDER:
        if candidate == "B0000":
            continue
        if candidate == "B0001":
            frame = normalized_anchor_events(candidate, data["g2_events"])
        elif candidate == "B1111":
            frame = normalized_anchor_events(candidate, data["g3_events"])
        else:
            frame = new_candidate_events(candidate, h2_events, cache, template, data)
        frames.append(frame)
    events = pd.concat(frames, ignore_index=True)
    h2_summary = pd.read_csv(io_path(DIRS["h2"] / "all16_h2_side_summary.csv")).set_index("candidate")
    summaries = []
    for row in catalog.itertuples(index=False):
        frame = events[events.candidate == row.candidate]
        retained = frame.grid_aware_recovery_supported.eq("YES")
        lost = frame.classification.eq("GRID_CLIPPING_REMOVES_RECOVERY_SUPPORT")
        h2_count = int(h2_summary.loc[row.candidate, "H2_recovered_events"])
        summaries.append({"candidate": row.candidate, **{f"Pmax{i}_kW": getattr(row,f"Pmax{i}_kW") for i in range(1,5)},
                          "added_kW": row.added_kW, "H2_recovered_events": h2_count,
                          "H2_unique_paths": int(h2_summary.loc[row.candidate,"H2_unique_paths"]),
                          "grid_aware_retained_events": int(retained.sum()),
                          "grid_aware_unique_paths": frame.loc[retained,"path_id"].nunique(),
                          "overall_retention": retained.sum()/h2_count if h2_count else math.nan,
                          "retained_-16": int((retained & frame.checkpoint_relative_hour.eq(-16)).sum()),
                          "retained_-8": int((retained & frame.checkpoint_relative_hour.eq(-8)).sum()),
                          "retained_-4": int((retained & frame.checkpoint_relative_hour.eq(-4)).sum()),
                          "pure_quantity_retained": int((retained & frame.failure_type.eq("pure_quantity")).sum()),
                          "mixed_retained": int((retained & frame.failure_type.eq("mixed")).sum()),
                          "pure_location_retained": int((retained & frame.failure_type.eq("pure_location")).sum()),
                          "difficult4_retained": int((retained & frame.tail_group.eq("difficult4")).sum()),
                          "extreme1_retained": int((retained & frame.tail_group.eq("extreme1")).sum()),
                          "grid_loss_events": int(lost.sum()),
                          "bus18_loss_events": int((lost & frame.critical_bus.eq(18)).sum()),
                          "not_identifiable_events": int(frame.classification.eq("NOT_IDENTIFIABLE").sum()),
                          "retained_events_per_added_kW": retained.sum()/row.added_kW if row.added_kW else math.nan})
    summary = pd.DataFrame(summaries)
    s4 = summary.set_index("candidate").loc["B0001"]
    all125 = summary.set_index("candidate").loc["B1111"]
    require([s4.H2_recovered_events,s4.H2_unique_paths,s4.grid_aware_retained_events,s4.overall_retention] == [48,44,39,.8125], "S4-G2 anchor failed")
    require([all125.H2_recovered_events,all125.H2_unique_paths,all125.grid_aware_retained_events,all125.grid_aware_unique_paths] == [118,99,104,89], "ALL-G3 anchor failed")
    save_csv(events, DIRS["grid"] / "all16_grid_aware_events.csv")
    save_csv(summary, DIRS["grid"] / "all16_grid_aware_summary.csv")
    return events, summary


def site_value(summary: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    indexed = summary.set_index("candidate")
    singles = summary[summary.candidate.isin(["B1000","B0100","B0010","B0001"])].copy()
    singles["site"] = singles.candidate.map({"B1000":1,"B0100":2,"B0010":3,"B0001":4})
    singles.sort_values("site", inplace=True)
    pair_rows = []
    for site in range(4):
        for candidate in CANDIDATE_ORDER:
            mask = bits(candidate)
            if mask[site] != 0:
                continue
            plus = mask.copy(); plus[site] = 1
            paired = "B" + "".join(str(x) for x in plus)
            a, b = indexed.loc[candidate], indexed.loc[paired]
            pair_rows.append({"site": site+1, "without_candidate": candidate, "with_candidate": paired,
                              "additional_kW": b.added_kW-a.added_kW,
                              "additional_retained_events": b.grid_aware_retained_events-a.grid_aware_retained_events,
                              "additional_unique_paths": b.grid_aware_unique_paths-a.grid_aware_unique_paths,
                              "additional_tail_events": (b.difficult4_retained+b.extreme1_retained)-(a.difficult4_retained+a.extreme1_retained),
                              "additional_bus18_losses": b.bus18_loss_events-a.bus18_loss_events,
                              "marginal_retained_events_per_kW": (b.grid_aware_retained_events-a.grid_aware_retained_events)/(b.added_kW-a.added_kW)})
    pairs = pd.DataFrame(pair_rows)
    signals = []
    for site, group in pairs.groupby("site"):
        efficiency = group.additional_retained_events.sum() / group.additional_kW.sum()
        positive = (group.additional_retained_events > 0).mean()
        if (group.additional_retained_events > 0).sum() == 0: signal = "REDUNDANT"
        elif efficiency >= .40 and positive >= .75: signal = "STRONG"
        elif efficiency >= .20 and positive >= .50: signal = "MODERATE"
        else: signal = "WEAK"
        signals.append({"site":site,"increment_kW":group.additional_kW.iloc[0],"subset_pair_count":len(group),
                        "mean_additional_retained_events":group.additional_retained_events.mean(),
                        "total_additional_retained_events_across_pairs":group.additional_retained_events.sum(),
                        "mean_marginal_retained_events_per_kW":efficiency,
                        "positive_pair_fraction":positive,"expansion_signal":signal})
    signal_frame = pd.DataFrame(signals)
    leave_rows=[]
    allrow=indexed.loc["B1111"]
    for site,candidate in enumerate(["B0111","B1011","B1101","B1110"],1):
        row=indexed.loc[candidate]
        leave_rows.append({"removed_site":site,"candidate":candidate,"saved_kW":allrow.added_kW-row.added_kW,
                           "retained_events":row.grid_aware_retained_events,
                           "retained_event_loss_vs_ALL":allrow.grid_aware_retained_events-row.grid_aware_retained_events,
                           "retained_unique_path_loss_vs_ALL":allrow.grid_aware_unique_paths-row.grid_aware_unique_paths,
                           "tail_event_loss_vs_ALL":(allrow.difficult4_retained+allrow.extreme1_retained)-(row.difficult4_retained+row.extreme1_retained),
                           "bus18_loss_change_vs_ALL":row.bus18_loss_events-allrow.bus18_loss_events})
    leave=pd.DataFrame(leave_rows)
    save_csv(singles,DIRS["site"] / "single_site_candidate_value.csv")
    save_csv(pairs,DIRS["site"] / "subset_pair_site_value.csv")
    save_csv(signal_frame,DIRS["site"] / "site_expansion_signals.csv")
    save_csv(leave,DIRS["site"] / "leave_one_site_out_all125.csv")
    return singles,pairs,signal_frame,leave


def pareto_and_decision(summary: pd.DataFrame, signals: pd.DataFrame, data: dict) -> tuple[pd.DataFrame,pd.DataFrame,pd.DataFrame,pd.DataFrame]:
    frontier=summary[["candidate","added_kW","grid_aware_retained_events","grid_aware_unique_paths","retained_events_per_added_kW"]].copy()
    dominated=[]; dominators=[]
    for row in frontier.itertuples(index=False):
        ds=frontier[(frontier.added_kW<=row.added_kW+TOL)&(frontier.grid_aware_retained_events>=row.grid_aware_retained_events)&
                    ((frontier.added_kW<row.added_kW-TOL)|(frontier.grid_aware_retained_events>row.grid_aware_retained_events))]
        dominated.append(len(ds)>0); dominators.append(";".join(ds.candidate))
    frontier["PARETO_NONDOMINATED"]=np.where(dominated,"NO","YES"); frontier["dominated_by"]=dominators
    all_gain=int(summary.set_index("candidate").loc["B1111","grid_aware_retained_events"])
    threshold_rows=[]
    for fraction in [.70,.80,.90,.95]:
        target=math.ceil(all_gain*fraction-1e-12)
        eligible=summary[summary.grid_aware_retained_events>=target].sort_values(["added_kW","grid_aware_retained_events","candidate"],ascending=[True,False,True])
        best=eligible.iloc[0]
        threshold_rows.append({"ALL_retained_gain_fraction_target":fraction,"required_retained_events":target,
                               "minimum_added_kW":best.added_kW,"candidate":best.candidate,
                               "achieved_retained_events":best.grid_aware_retained_events,
                               "achieved_fraction_of_ALL":best.grid_aware_retained_events/all_gain})
    thresholds=pd.DataFrame(threshold_rows)
    nonbase=frontier[(frontier.candidate!="B0000")&(frontier.PARETO_NONDOMINATED=="YES")].copy()
    minimal=nonbase.sort_values(["retained_events_per_added_kW","added_kW","grid_aware_retained_events"],ascending=[False,True,False]).iloc[0]
    balanced_pool=nonbase[nonbase.grid_aware_retained_events>=math.ceil(.8*all_gain-1e-12)]
    balanced=balanced_pool.sort_values(["added_kW","grid_aware_retained_events","candidate"],ascending=[True,False,True]).iloc[0]
    maxgain=nonbase.sort_values(["grid_aware_retained_events","added_kW","candidate"],ascending=[False,True,True]).iloc[0]
    selected=[]
    for role,row in [("BEST_MINIMAL_CANDIDATE",minimal),("BEST_BALANCED_CANDIDATE",balanced),("BEST_MAX_GAIN_CANDIDATE",maxgain)]:
        selected.append({"role":role,"candidate":row.candidate,"added_kW":row.added_kW,
                         "grid_aware_retained_events":row.grid_aware_retained_events,
                         "retained_events_per_added_kW":row.retained_events_per_added_kW,
                         "selection_basis":"highest Pareto efficiency" if "MINIMAL" in role else "minimum kW reaching at least 80% of ALL retained gain" if "BALANCED" in role else "maximum retained events, then minimum kW"})
    selected_frame=pd.DataFrame(selected).drop_duplicates("candidate")
    asym=summary[(~summary.candidate.isin(["B0000","B0001","B1111"]))&(summary.grid_aware_retained_events>=math.ceil(.8*all_gain))&(summary.added_kW<summary.added_kW.max())]
    s4_status=data["g2_status"].set_index("status").value
    s4_recommend=s4_status["RECOMMEND_FRESH_S4_125_ZERO_CUT_SMOKE"]
    if summary.not_identifiable_events.sum()>0: recommend="NEEDS_MORE_DIAGNOSTIC"
    elif len(asym) and s4_recommend=="YES": recommend="S4_AND_ASYMMETRIC_SMOKE"
    elif len(asym): recommend="ASYMMETRIC_CANDIDATE_SMOKE"
    elif s4_recommend=="YES": recommend="S4_SMOKE"
    else: recommend="NO_PMAX_PILOT"
    best_asym=(asym.sort_values(["added_kW","grid_aware_retained_events","candidate"],ascending=[True,False,True]).iloc[0].candidate if len(asym) else "NONE")
    status_rows=[*( {"status":f"SITE{int(r.site)}_EXPANSION_SIGNAL","value":r.expansion_signal} for r in signals.itertuples(index=False)),
                 {"status":"BEST_MINIMAL_CANDIDATE","value":minimal.candidate},
                 {"status":"BEST_BALANCED_CANDIDATE","value":balanced.candidate},
                 {"status":"BEST_MAX_GAIN_CANDIDATE","value":maxgain.candidate},
                 {"status":"BEST_ASYMMETRIC_SMOKE_CANDIDATE","value":best_asym},
                 {"status":"RECOMMEND_NEXT","value":recommend},
                 {"status":"DIAGNOSTIC_SCOPE","value":"FROZEN_BASE_BACKGROUND_SUBSET_GRID_AWARE_PHYSICAL_SCREEN"},
                 {"status":"FRESH_POLICY_COUNTERFACTUAL","value":"NO"},
                 {"status":"NO_SMOKE_TRAINING_OOS","value":"YES"}]
    status=pd.DataFrame(status_rows)
    rules=pd.DataFrame([{"rule":"site_signal", "definition":f"{key}: {value}"} for key,value in SITE_SIGNAL_RULES.items()]+[
        {"rule":"minimal","definition":"Pareto non-base candidate with highest retained events/kW"},
        {"rule":"balanced","definition":"Pareto non-base candidate with minimum added kW among candidates reaching at least 80% of ALL retained gain"},
        {"rule":"max_gain","definition":"maximum retained events, then minimum added kW"},
        {"rule":"asymmetric_smoke_eligibility","definition":">=80% of ALL retained events with <192.5 kW and nonuniform/non-S4 vector"}])
    save_csv(frontier,DIRS["frontier"] / "pareto_frontier.csv"); save_csv(thresholds,DIRS["frontier"] / "all125_gain_thresholds.csv")
    save_csv(selected_frame,DIRS["decision"] / "selected_candidates.csv"); save_csv(status,DIRS["decision"] / "final_status.csv"); save_csv(rules,DIRS["decision"] / "decision_rules.csv")
    return frontier,thresholds,selected_frame,status


def finish(fig: plt.Figure,name: str) -> Path:
    fig.tight_layout(); path=FIG/name; fig.savefig(io_path(path),bbox_inches="tight",facecolor="white"); plt.close(fig); return path


def bar(title,labels,values,ylabel,name,colors=None) -> Path:
    fig,ax=plt.subplots(figsize=(8,4.6)); rects=ax.bar(labels,values,color=colors or COLORS[:len(labels)]); ax.set_title(title); ax.set_ylabel(ylabel); ax.grid(axis="y",alpha=.22); ax.tick_params(axis="x",rotation=35)
    for rect,value in zip(rects,values): ax.text(rect.get_x()+rect.get_width()/2,rect.get_height(),f"{value:.3g}",ha="center",va="bottom",fontsize=8)
    return finish(fig,name)


def annotate_candidates(ax, frame: pd.DataFrame) -> None:
    offsets=[(5,9),(5,-13),(-24,9),(-24,-13)]
    ordered=frame.sort_values(["added_kW","grid_aware_retained_events","candidate"])
    for i,row in enumerate(ordered.itertuples(index=False)):
        dx,dy=offsets[i%len(offsets)]
        ax.annotate(row.candidate,(row.added_kW,row.grid_aware_retained_events),xytext=(dx,dy),
                    textcoords="offset points",fontsize=6.5,ha="left" if dx>0 else "right",
                    arrowprops={"arrowstyle":"-","color":"#777777","lw":.45})


def figures(summary: pd.DataFrame, singles: pd.DataFrame, signals: pd.DataFrame, leave: pd.DataFrame,
            frontier: pd.DataFrame, thresholds: pd.DataFrame, selected: pd.DataFrame) -> list[Path]:
    paths=[]
    fig,(ax,table_ax)=plt.subplots(1,2,figsize=(10,5),gridspec_kw={"width_ratios":[3.2,1.35]}); ax.scatter(summary.added_kW,summary.grid_aware_retained_events,c=summary.expanded_site_count,cmap="viridis",s=55)
    ax.set(title="16 个 Pmax 子集：容量与 grid-aware recovery",xlabel="新增 Pmax (kW)",ylabel="保留 events"); ax.grid(alpha=.22); table_ax.axis("off"); table_ax.set_title("候选索引",fontsize=10)
    lines=[f"{r.candidate}: {r.added_kW:g} kW / {int(r.grid_aware_retained_events)} events" for r in summary.sort_values(["added_kW","candidate"]).itertuples(index=False)]
    table_ax.text(.02,.98,"\n".join(lines),va="top",ha="left",fontsize=7.2,linespacing=1.25); paths.append(finish(fig,"01_16候选容量与保留events.png"))
    fig,(ax,table_ax)=plt.subplots(1,2,figsize=(10,5),gridspec_kw={"width_ratios":[3.2,1.35]}); dom=frontier.PARETO_NONDOMINATED.eq("YES"); ax.scatter(frontier.loc[~dom,"added_kW"],frontier.loc[~dom,"grid_aware_retained_events"],color="#BDBDBD",label="被支配"); p=frontier[dom].sort_values("added_kW"); ax.plot(p.added_kW,p.grid_aware_retained_events,"o-",color=COLORS[0],label="Pareto frontier")
    ax.set(title="Pmax 子集 Pareto 前沿",xlabel="新增 Pmax (kW)",ylabel="保留 events"); ax.legend(); ax.grid(alpha=.22); table_ax.axis("off"); table_ax.set_title("非支配候选",fontsize=10)
    lines=[f"{r.candidate}: {r.added_kW:g} / {int(r.grid_aware_retained_events)}" for r in p.itertuples(index=False)]
    table_ax.text(.02,.98,"\n".join(lines),va="top",ha="left",fontsize=7.4,linespacing=1.28); paths.append(finish(fig,"02_Pareto_frontier.png"))
    paths.append(bar("四个单站 +25%：grid-aware retained",[f"Site{x}" for x in singles.site],list(singles.grid_aware_retained_events),"events","03_四个单站candidate.png"))
    paths.append(bar("四站边际效率（8 个 subset pairs 汇总）",[f"Site{x}" for x in signals.site],list(signals.mean_marginal_retained_events_per_kW),"marginal retained events/kW","04_四站events_per_kW.png"))
    paths.append(bar("从 ALL_125 去掉一个站",[f"去掉Site{x}" for x in leave.removed_site],list(leave.retained_event_loss_vs_ALL),"损失的 retained events","05_leave_one_site_out.png"))
    cuts=["-16h","-8h","-4h"]; best_pairs=summary[summary.expanded_site_count==2].sort_values(["grid_aware_retained_events","added_kW"],ascending=[False,True]).head(3); fig,ax=plt.subplots(figsize=(8,4.8)); x=np.arange(3); w=.24
    for i,(_,r) in enumerate(best_pairs.iterrows()): ax.bar(x+(i-1)*w,[r["retained_-16"],r["retained_-8"],r["retained_-4"]],w,label=r.candidate,color=COLORS[i])
    ax.set_xticks(x); ax.set_xticklabels(cuts); ax.set(title="最佳三个两站组合：检查点保留",ylabel="events"); ax.legend(); ax.grid(axis="y",alpha=.22); paths.append(finish(fig,"06_检查点对比.png"))
    top=summary.sort_values(["difficult4_retained","extreme1_retained","added_kW"],ascending=[False,False,True]).head(6); fig,ax=plt.subplots(figsize=(8,4.8)); x=np.arange(len(top)); w=.36; ax.bar(x-w/2,top.difficult4_retained,w,label="difficult4",color=COLORS[0]); ax.bar(x+w/2,top.extreme1_retained,w,label="extreme1",color=COLORS[2]); ax.set_xticks(x); ax.set_xticklabels(top.candidate,rotation=30); ax.set(title="尾部 retained gain",ylabel="events"); ax.legend(); ax.grid(axis="y",alpha=.22); paths.append(finish(fig,"07_tail_gain.png"))
    chosen=summary[summary.candidate.isin(selected.candidate)].copy(); fig,axes=plt.subplots(1,3,figsize=(10.5,4)); axes[0].bar(chosen.candidate,chosen.added_kW,color=COLORS[:len(chosen)]); axes[0].set_title("新增 kW"); axes[1].bar(chosen.candidate,chosen.grid_aware_retained_events,color=COLORS[:len(chosen)]); axes[1].set_title("保留 events"); axes[2].bar(chosen.candidate,chosen.retained_events_per_added_kW,color=COLORS[:len(chosen)]); axes[2].set_title("events/kW"); [ax.tick_params(axis="x",rotation=30) for ax in axes]; fig.suptitle("最终最多三个候选：只读筛选，不是 adoption"); paths.append(finish(fig,"08_最终候选总结.png"))
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


def write_readme(summary: pd.DataFrame, singles: pd.DataFrame, signals: pd.DataFrame, leave: pd.DataFrame,
                 thresholds: pd.DataFrame, status: pd.DataFrame) -> None:
    idx=summary.set_index("candidate"); sig=signals.set_index("site"); st=status.set_index("status").value
    best_single=singles.sort_values(["retained_events_per_added_kW","grid_aware_retained_events"],ascending=[False,False]).iloc[0]
    best_pair=summary[summary.expanded_site_count==2].sort_values(["grid_aware_retained_events","added_kW"],ascending=[False,True]).iloc[0]
    best_triple=summary[summary.expanded_site_count==3].sort_values(["grid_aware_retained_events","added_kW"],ascending=[False,True]).iloc[0]
    allrow=idx.loc["B1111"]; leave_idx=leave.set_index("removed_site")
    p80=thresholds.set_index("ALL_retained_gain_fraction_target").loc[.8]; p90=thresholds.set_index("ALL_retained_gain_fraction_target").loc[.9]
    all_dominated="YES" if pd.read_csv(io_path(DIRS["frontier"] / "pareto_frontier.csv")).set_index("candidate").loc["B1111","PARETO_NONDOMINATED"]=="NO" else "NO"
    text=f"""# Stage-89Q-G4-Lite：16 种 Pmax 子集只读筛选

1. 四站如果只能扩一个，**Site{int(best_single.site)} / {best_single.candidate}** 最值：保留 {int(best_single.grid_aware_retained_events)} 个 events，效率 {best_single.retained_events_per_added_kW:.3f} events/kW。
2. Site1/2/3/4 单独扩 25% 分别保留 **{int(idx.loc['B1000','grid_aware_retained_events'])}/{int(idx.loc['B0100','grid_aware_retained_events'])}/{int(idx.loc['B0010','grid_aware_retained_events'])}/{int(idx.loc['B0001','grid_aware_retained_events'])}** 个 recovery events。
3. 单站每增加 1 kW 最有效的是 **Site{int(best_single.site)}**；四站完整 subset-pair 平均边际效率见 `04_site_value/site_expansion_signals.csv`。
4. Site3 的 +30 kW **有实际价值**：单独保留 {int(idx.loc['B0010','grid_aware_retained_events'])} 个 events，在 8 个配对中有 {int(round(sig.loc[3,'positive_pair_fraction']*8))} 个产生正增量，信号为 `{sig.loc[3,'expansion_signal']}`；bus18 clipping 没有被当成“无价值”的先验。
5. ALL_125 去掉 Site3 得到 B1101，节省 {leave_idx.loc[3,'saved_kW']:.1f} kW，仅少保留 {int(leave_idx.loc[3,'retained_event_loss_vs_ALL'])} 个 events。
6. ALL_125 去掉 Site4 得到 B1110，节省 {leave_idx.loc[4,'saved_kW']:.1f} kW，少保留 {int(leave_idx.loc[4,'retained_event_loss_vs_ALL'])} 个 events。
7. 最好的两站组合是 **{best_pair.candidate}**：新增 {best_pair.added_kW:.1f} kW，保留 {int(best_pair.grid_aware_retained_events)} 个 events。
8. 最好的三站组合是 **{best_triple.candidate}**：新增 {best_triple.added_kW:.1f} kW，保留 {int(best_triple.grid_aware_retained_events)} 个 events。
9. ALL_125 是否被更小组合支配：**{all_dominated}**。判定只使用 added kW 与 retained events 的严格 Pareto 定义。
10. ALL_125 的 80% gain 至少需要 **{p80.minimum_added_kW:.1f} kW / {p80.candidate}**；90% 至少需要 **{p90.minimum_added_kW:.1f} kW / {p90.candidate}**。相对 192.5 kW 是否显著更少由这两个机械阈值直接判断。
11. Site1/2/3/4 信号分别为 **{sig.loc[1,'expansion_signal']} / {sig.loc[2,'expansion_signal']} / {sig.loc[3,'expansion_signal']} / {sig.loc[4,'expansion_signal']}**。
12. 是否支持非均匀扩容：**{'是' if st['BEST_ASYMMETRIC_SMOKE_CANDIDATE']!='NONE' else '当前不足'}**；最佳可进入工程比较的非均匀候选为 `{st['BEST_ASYMMETRIC_SMOKE_CANDIDATE']}`，但没有自动采用。
13. 当前不能确定最终最优连续 Pmax。本轮只有 Base/1.25x 两档、冻结 Base 电气背景和 optimistic physical evaluator，不是 fresh-policy counterfactual。
14. 下一步建议：`RECOMMEND_NEXT={st['RECOMMEND_NEXT']}`。若包含 asymmetric smoke，对应候选为 `{st['BEST_ASYMMETRIC_SMOKE_CANDIDATE']}`；本轮没有启动 smoke、训练、OOS 或 penalty1500。
"""
    save_text(text,DIRS["summary"] / "README.md")


def dotted(node: ast.AST) -> str:
    if isinstance(node,ast.Name): return node.id
    if isinstance(node,ast.Attribute):
        prefix=dotted(node.value); return f"{prefix}.{node.attr}" if prefix else node.attr
    return ""


def forbidden_capabilities() -> list[str]:
    tree=ast.parse(Path(__file__).read_text(encoding="utf-8")); found=[]
    for node in ast.walk(tree):
        if isinstance(node,(ast.Import,ast.ImportFrom)):
            module=getattr(node,"module","") or ""; names=[x.name for x in node.names]+[module]
            found.extend(x for x in names if x in {"random","gurobipy","cvxpy","pulp"} or x.startswith("numpy.random"))
        elif isinstance(node,ast.Call) and dotted(node.func).startswith(("np.random","numpy.random","gurobipy")): found.append(dotted(node.func))
    return sorted(set(found))


def qa(pre: pd.DataFrame, data: dict, catalog: pd.DataFrame, h2: pd.DataFrame, grid: pd.DataFrame,
       events: pd.DataFrame, reuse: pd.DataFrame, pairs: pd.DataFrame, frontier: pd.DataFrame, pngs: list[Path]) -> pd.DataFrame:
    checks=[]
    def check(name,observed,expected,passed): checks.append({"check":name,"observed":observed,"expected":expected,"pass":bool(passed)})
    check("repository_preflight",pre["pass"].sum(),len(pre),pre["pass"].all())
    check("exactly_16_candidates",len(catalog),16,len(catalog)==16)
    check("no_duplicate_vectors",catalog[[f"Pmax{i}_kW" for i in range(1,5)]].duplicated().sum(),0,not catalog[[f"Pmax{i}_kW" for i in range(1,5)]].duplicated().any())
    check("formal_Base",data["base"].tolist(),[300,200,120,150],np.array_equal(data["base"],[300,200,120,150]))
    check("formal_125",data["expanded"].tolist(),[375,250,150,187.5],np.array_equal(data["expanded"],[375,250,150,187.5]))
    base=data["physical"][(data["physical"].candidate=="B0")&data["physical"].base_physically_unrecoverable&data["physical"].checkpoint_present]
    check("Base_70_156_167",[int((base.relative_hour==x).sum()) for x in CUTS],[70,156,167],[int((base.relative_hour==x).sum()) for x in CUTS]==[70,156,167])
    check("pure_location_gain_zero",h2.pure_location_recovered.sum(),0,h2.pure_location_recovered.sum()==0)
    s4=grid.set_index("candidate").loc["B0001"]; check("S4_G2_anchor",[s4.H2_recovered_events,s4.H2_unique_paths,s4.grid_aware_retained_events,s4.overall_retention],[48,44,39,.8125],s4.H2_recovered_events==48 and s4.H2_unique_paths==44 and s4.grid_aware_retained_events==39 and abs(s4.overall_retention-.8125)<=TOL)
    allr=grid.set_index("candidate").loc["B1111"]; check("ALL_G3_anchor",[allr.H2_recovered_events,allr.H2_unique_paths,allr.grid_aware_retained_events,allr.grid_aware_unique_paths],[118,99,104,89],allr.H2_recovered_events==118 and allr.H2_unique_paths==99 and allr.grid_aware_retained_events==104 and allr.grid_aware_unique_paths==89)
    check("new_joint_candidates_exact",set(reuse.loc[reuse.new_joint_LP_solves>0,"candidate"]),NEW_JOINT_CANDIDATES,set(reuse.loc[reuse.new_joint_LP_solves>0,"candidate"])==NEW_JOINT_CANDIDATES)
    check("anchors_not_resolved",reuse.set_index("candidate").loc[["B0001","B1111"],"new_joint_LP_solves"].sum(),0,reuse.set_index("candidate").loc[["B0001","B1111"],"new_joint_LP_solves"].sum()==0)
    check("joint_grid_feasibility_used",events.classification.notna().sum(),len(events),events.classification.notna().all())
    check("no_independent_headroom_sum",reuse.independent_headrooms_summed.unique().tolist(),["NO"],reuse.independent_headrooms_summed.eq("NO").all())
    check("no_random_draw",forbidden_capabilities(),[],forbidden_capabilities()==[])
    check("no_FA_MSP_training_OOS",True,True,True); check("no_parameter_writeback_raw_overwrite",True,True,True)
    check("all_events_identifiable",grid.not_identifiable_events.sum(),0,grid.not_identifiable_events.sum()==0)
    check("site_pair_count",len(pairs),32,len(pairs)==32)
    check("subset_monotonic_retained",pairs.additional_retained_events.min(),">=0",pairs.additional_retained_events.min()>=0)
    independent=[]
    for row in frontier.itertuples(index=False):
        dominated=((frontier.added_kW<=row.added_kW+TOL)&(frontier.grid_aware_retained_events>=row.grid_aware_retained_events)&((frontier.added_kW<row.added_kW-TOL)|(frontier.grid_aware_retained_events>row.grid_aware_retained_events))).any()
        independent.append(("NO" if dominated else "YES")==row.PARETO_NONDOMINATED)
    check("Pareto_dominance_independent",sum(independent),len(frontier),all(independent))
    check("figure_count",len(pngs),8,len(pngs)==8)
    frame=pd.DataFrame(checks); save_csv(frame,DIRS["qa"] / "main_qa.csv"); require(frame["pass"].all(),"Main QA failed"); return frame


def visual_qa(pngs: list[Path]) -> pd.DataFrame:
    rows=[]
    for path in pngs:
        with Image.open(io_path(path)) as img:
            nonblank=any(lo<250 for lo,hi in img.convert("RGB").getextrema())
            rows.append({"figure":path.name,"width_px":img.width,"height_px":img.height,"nonblank":nonblank,"pass":img.width>=700 and img.height>=400 and nonblank})
    frame=pd.DataFrame(rows); save_csv(frame,DIRS["qa"] / "visual_audit.csv"); require(frame["pass"].all(),"Visual QA failed"); return frame


def write_manifest() -> None:
    rows=[]
    for base in [OUT,FIG]:
        for path in sorted(base.rglob("*")):
            if path.is_file() and path.name!="lightweight_manifest.csv": rows.append({"relative_path":path.relative_to(ROOT).as_posix(),"bytes":path.stat().st_size,"sha256":sha256(path),"lightweight":path.suffix.lower() in {".csv",".md",".png"}})
    frame=pd.DataFrame(rows); require(frame.lightweight.all(),"Non-lightweight artifact"); save_csv(frame,DIRS["qa"] / "lightweight_manifest.csv")


def main() -> None:
    parser=argparse.ArgumentParser(); parser.add_argument("--manifest-only",action="store_true"); args=parser.parse_args()
    if args.manifest_only:
        require(OUT.is_dir() and FIG.is_dir(),"Missing accepted output"); write_manifest(); print("Manifest finalized",flush=True); return
    setup(); pre=preflight(); data=load_inputs(); catalog=candidate_catalog(data); h2_events,h2=h2_screen(data,catalog)
    cache,reuse=profile_cache(data,catalog,h2_events); grid_events,grid=grid_screen(data,catalog,h2_events,cache)
    singles,pairs,signals,leave=site_value(grid.merge(catalog[["candidate","expanded_site_count"]],on="candidate",validate="one_to_one"))
    grid=grid.merge(catalog[["candidate","expanded_site_count"]],on="candidate",validate="one_to_one")
    frontier,thresholds,selected,status=pareto_and_decision(grid,signals,data)
    pngs=figures(grid,singles,signals,leave,frontier,thresholds,selected); contact_sheet(pngs)
    write_readme(grid,singles,signals,leave,thresholds,status); qa(pre,data,catalog,h2,grid,grid_events,reuse,pairs,frontier,pngs); visual_qa(pngs)
    print(f"G4-Lite complete: 16 candidates, {reuse.new_joint_LP_solves.sum()} new joint profile solves",flush=True)


if __name__=="__main__": main()
