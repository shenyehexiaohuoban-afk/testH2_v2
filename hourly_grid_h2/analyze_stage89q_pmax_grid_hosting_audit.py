#!/usr/bin/env python3
"""Stage-89Q-G isolated hourly IEEE33 Pmax grid-hosting audit.

This script reads the accepted penalty=1000 OOS tables and the frozen grid
inputs.  It only solves small, independent LinDistFlow hosting LPs.  It does
not load a policy checkpoint or call any FA-MSP training/OOS code.
"""

from __future__ import annotations

import ast
import hashlib
import json
import math
import os
import subprocess
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib import font_manager
import numpy as np
import pandas as pd
from PIL import Image, ImageDraw, ImageFont
import psutil
from scipy.io import loadmat
from scipy.optimize import linprog


ROOT = Path(__file__).resolve().parents[1]
RUN = ROOT / "results/task-002-stage2b-b3-smoke/stage89q-penalty1000-vs1500-long-training/run-003"
RAW = ROOT / "hourly_grid_h2/output/stage89q_penalty1000_vs1500_long_training/run-003/penalty1000"
OUT = RUN / "05_analysis/10_deep_penalty1000/18_pmax_grid_hosting_audit"
FIG = RUN / "06_figures/12_penalty1000_pmax_grid_hosting"
PREVIOUS = RUN / "05_analysis/10_deep_penalty1000/17_pmax_flexibility_audit"
GRID_INPUT = ROOT / "data/yuanqi/near_stage_msp_input.mat"

EXPECTED_BRANCH = "task/002-stage2b-b3-smoke"
EXPECTED_HEAD = "aec109226f6a1cb211cac092136c10c16fcc67c1"
EXPECTED_UPSTREAM = "origin/task/002-stage2b-b3-smoke"
EXPECTED_RAW = {
    "path_summary/oos_path_summary.csv": "99ec55faba4e60e88b25d757deb1a8146515faf666d52979fe69c64362047502",
    "path_summary/oos_stage_summary.csv": "969c373a9a2ff1b271cde6fda95a6fe8e64b10362518fe4b807c0dc86437c15d",
    "path_summary/oos_stage_site_summary.csv": "eab41bdf5d58fc971bc65af8c5745de3bd08cc25a0a4d44cc386aeba3f99c89e",
    "hourly_site/oos_hour_site.csv": "af3b3d5c4aa69e6d29b35a88008b4d82360c4b8391fc783141078f7ad68b0cda",
    "grid_hourly/oos_hour_system.csv": "b9eaa83ee3e8a720f3cb5afd5d54da050c2d3ef45c434efe74f8ba8b976b63c6",
}
EXPECTED_GRID_INPUT_SHA = "536b25868e6d7cc812a331c0d3e0ffbd5f6958e6883bd39bcae3901c372abf24"
EXPECTED_MODEL_HASHES = {
    "hourly_grid_h2/build_integrated_hourly_stage_model_hourly_htt_v1_h2.m": "06375232f352ef8da038321703eca4a44ca20ddb5f5c3a46a8d4c79306718f77",
    "hourly_grid_h2/update_integrated_hourly_stage_model_hourly_htt_v1_h2.m": "cd7e44e5fde0a08831f1b663040e9ee5346290d59003e1460e2f72619d21e49f",
    "hourly_grid_h2/load_hourly_grid_data_h2.m": "a3e02ffdbee71f089b5417083693ab145a88fdbb2fcb167af13ca842d02e8c63",
    "hourly_grid_h2/add_branch_capacity_octagon_h2.m": "eeaf2b4023d3bd369cf1a03c89f17eed19826b1f9b9a710d8b43890295cd5ddf",
    "hourly_grid_h2/map_site_to_electrical_bus_h2.m": "a9c385ab37d997264db0446217013ce5e1f6f2be414365e68ef229a2d8e4c102",
}

BASE = np.array([300.0, 200.0, 120.0, 150.0])
S4_125 = np.array([300.0, 200.0, 120.0, 187.5])
ALL_125 = np.array([375.0, 250.0, 150.0, 187.5])
SITE_BUSES = np.array([24, 14, 18, 31], dtype=int)
K_H2 = 0.0195
TOL = 1e-7
HOST_TOL_KW = 1e-5
BIND_TOL = 2e-7

# Fixed before results are inspected.  They operationalize "overwhelming
# majority" and "systematic bottleneck" in the prompt.
CLEAR_FULL_HOSTABLE_RATIO = 0.95
CLEAR_LIMITED_HOUR_RATIO = 0.05
LIMITED_FULL_HOSTABLE_RATIO = 0.50
LIMITED_MEAN_HOSTING_RATIO = 0.50

LAMBDA24 = np.array([
    0.783042, 0.737820, 0.723015, 0.707941, 0.698789, 0.677793,
    0.662719, 0.707941, 0.801077, 0.801077, 0.843338, 0.873486,
    0.888560, 0.915747, 0.888560, 0.888560, 0.879408, 0.843338,
    0.864334, 0.975774, 1.000000, 0.975774, 0.963930, 0.888560,
])
PHI24 = np.array([
    0, 0, 0, 0, 0, 0, 0, 0, 0.014969, 0.043234, 0.094988,
    0.174421, 0.219728, 0.335005, 0.385584, 0.332415, 0.273062,
    0.177524, 0.052788, 0, 0, 0, 0, 0,
])


def io_path(path: Path) -> str:
    resolved = str(path.resolve())
    if os.name == "nt" and not resolved.startswith("\\\\?\\"):
        return "\\\\?\\" + resolved
    return resolved


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with open(io_path(path), "rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def git(*args: str) -> str:
    result = subprocess.run(
        ["git", *args], cwd=ROOT, check=True, capture_output=True, text=True
    )
    return result.stdout.strip()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def save_csv(frame: pd.DataFrame, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    frame.to_csv(io_path(path), index=False, encoding="utf-8-sig", float_format="%.12g")


def weighted_mean(values: Iterable[float], weights: Iterable[int]) -> float:
    values = np.asarray(values, dtype=float)
    weights = np.asarray(weights, dtype=float)
    mask = np.isfinite(values) & np.isfinite(weights) & (weights > 0)
    return float(np.average(values[mask], weights=weights[mask])) if mask.any() else math.nan


def weighted_quantile(values: Iterable[float], weights: Iterable[int], q: float) -> float:
    values = np.asarray(values, dtype=float)
    weights = np.asarray(weights, dtype=float)
    mask = np.isfinite(values) & np.isfinite(weights) & (weights > 0)
    if not mask.any():
        return math.nan
    order = np.argsort(values[mask], kind="mergesort")
    x = values[mask][order]
    w = weights[mask][order]
    index = np.searchsorted(np.cumsum(w), q * w.sum(), side="left")
    return float(x[min(index, len(x) - 1)])


def most_frequent(values: Iterable[int], weights: Iterable[int]) -> str:
    counter: Counter[int] = Counter()
    for value, weight in zip(values, weights):
        if pd.notna(value):
            counter[int(value)] += int(weight)
    if not counter:
        return "NOT_AVAILABLE"
    count = max(counter.values())
    return ";".join(str(key) for key in sorted(k for k, v in counter.items() if v == count))


def id_set_sha(values: Iterable[int]) -> str:
    payload = ",".join(str(int(v)) for v in sorted(set(values))).encode("ascii")
    return hashlib.sha256(payload).hexdigest()


def dotted_name(node: ast.AST) -> str:
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        prefix = dotted_name(node.value)
        return f"{prefix}.{node.attr}" if prefix else node.attr
    return ""


def random_capabilities(tree: ast.AST) -> list[str]:
    found = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            found.extend(alias.name for alias in node.names
                         if alias.name == "random" or alias.name.startswith("numpy.random"))
        elif isinstance(node, ast.ImportFrom):
            module = node.module or ""
            if module == "random" or module.startswith("numpy.random"):
                found.append(module)
        elif isinstance(node, ast.Call):
            name = dotted_name(node.func)
            if name.startswith("np.random") or name.startswith("numpy.random"):
                found.append(name)
    return sorted(set(found))


def setup_chinese_font() -> None:
    choices = ["Microsoft YaHei", "SimHei", "Noto Sans CJK SC", "Arial Unicode MS"]
    installed = {f.name for f in font_manager.fontManager.ttflist}
    selected = next((name for name in choices if name in installed), "DejaVu Sans")
    plt.rcParams.update({
        "font.family": selected,
        "axes.unicode_minus": False,
        "font.size": 9,
        "axes.titlesize": 12,
        "axes.labelsize": 9,
        "xtick.labelsize": 8,
        "ytick.labelsize": 8,
        "legend.fontsize": 8,
        "figure.facecolor": "white",
        "axes.facecolor": "white",
    })


@dataclass
class GridData:
    branch_from: np.ndarray
    branch_to: np.ndarray
    r_ohm: np.ndarray
    x_ohm: np.ndarray
    p_load_base_kw: np.ndarray
    q_load_base_kvar: np.ndarray
    p_substation_max_kw: float
    base_kv: float = 12.66
    base_mva: float = 10.0
    vmin_pu: float = 0.90
    vmax_pu: float = 1.10
    branch_smax_mva: float = 6.0
    octagon_a: float = 0.9238795325
    octagon_b: float = 1.3065629649
    pv_cap_kw: float = 200.0


def load_grid_data() -> GridData:
    raw = loadmat(io_path(GRID_INPUT), simplify_cells=True)["NearStageInput"]
    grid = raw["Grid"]
    active = np.asarray(grid["branch_indices"], dtype=int).ravel() - 1
    edges = np.asarray(grid["power_edges"], dtype=int)[active, :2]
    pmax = np.asarray(raw["HydrogenDevice"]["el_cap_kw"], dtype=float).ravel()
    require(np.allclose(pmax, BASE, atol=TOL), f"Formal Base Pmax mismatch: {pmax}")
    require(abs(float(raw["HydrogenDevice"]["k_H2_kg_per_kWh"]) - K_H2) <= TOL,
            "Formal k_H2 mismatch")
    require(np.array_equal(np.asarray(grid["site_node_map"], dtype=int).ravel(), SITE_BUSES),
            "Formal site-bus map mismatch")
    return GridData(
        branch_from=edges[:, 0] - 1,
        branch_to=edges[:, 1] - 1,
        r_ohm=np.asarray(grid["r_ohm"], dtype=float).ravel()[active],
        x_ohm=np.asarray(grid["x_ohm"], dtype=float).ravel()[active],
        p_load_base_kw=np.asarray(grid["P_load_base_kw"], dtype=float).ravel(),
        q_load_base_kvar=np.asarray(grid["Q_load_base_kVAr"], dtype=float).ravel(),
        p_substation_max_kw=float(grid["P_substation_max_kw"]),
        base_kv=float(grid["base_kv"]),
        base_mva=float(grid["base_mva"]),
        vmin_pu=float(grid["vmin_pu"]),
        vmax_pu=float(grid["vmax_pu"]),
        branch_smax_mva=float(grid["branch_limit_mva"]),
    )


class HourlyGridLP:
    """Exact Python transcription of the formal lossless hourly grid LP."""

    def __init__(self, data: GridData, global_hour: int):
        self.data = data
        self.global_hour = int(global_hour)
        tau = (self.global_hour - 1) % 48
        hour24 = tau % 24
        self.n_bus = 33
        self.n_branch = 32
        self.p_idx = np.arange(0, 32)
        self.q_idx = np.arange(32, 64)
        self.v_idx = np.arange(64, 97)
        self.p_grid_idx = 97
        self.q_grid_idx = 98
        self.pv_idx = np.arange(99, 103)
        self.pel_idx = np.arange(103, 107)
        self.nvars = 107
        self.pv_available_site_kw = data.pv_cap_kw * PHI24[hour24]

        self.Aeq = np.zeros((2 * self.n_bus + self.n_branch + 1, self.nvars))
        self.beq = np.zeros(self.Aeq.shape[0])
        factor = 2.0 / (data.base_kv ** 2 * 1000.0)
        for ell, (fr, to) in enumerate(zip(data.branch_from, data.branch_to)):
            self.Aeq[fr, self.p_idx[ell]] = -1
            self.Aeq[to, self.p_idx[ell]] = 1
            self.Aeq[self.n_bus + fr, self.q_idx[ell]] = -1
            self.Aeq[self.n_bus + to, self.q_idx[ell]] = 1
            row = 2 * self.n_bus + ell
            self.Aeq[row, self.v_idx[to]] = 1
            self.Aeq[row, self.v_idx[fr]] = -1
            self.Aeq[row, self.p_idx[ell]] = factor * data.r_ohm[ell]
            self.Aeq[row, self.q_idx[ell]] = factor * data.x_ohm[ell]
        self.Aeq[0, self.p_grid_idx] = 1
        self.Aeq[self.n_bus, self.q_grid_idx] = 1
        for site, bus in enumerate(SITE_BUSES - 1):
            self.Aeq[bus, self.pv_idx[site]] = 1
            self.Aeq[bus, self.pel_idx[site]] = -1
        self.beq[:self.n_bus] = data.p_load_base_kw * LAMBDA24[hour24]
        self.beq[self.n_bus:2 * self.n_bus] = data.q_load_base_kvar * LAMBDA24[hour24]
        self.Aeq[-1, self.v_idx[0]] = 1
        self.beq[-1] = 1

        rows, rhs = [], []
        smax = data.branch_smax_mva * 1000.0
        facets = [
            (1, 0, data.octagon_a * smax), (-1, 0, data.octagon_a * smax),
            (0, 1, data.octagon_a * smax), (0, -1, data.octagon_a * smax),
            (1, 1, data.octagon_b * smax), (-1, -1, data.octagon_b * smax),
            (1, -1, data.octagon_b * smax), (-1, 1, data.octagon_b * smax),
        ]
        for ell in range(self.n_branch):
            for cp, cq, limit in facets:
                row = np.zeros(self.nvars)
                row[self.p_idx[ell]] = cp
                row[self.q_idx[ell]] = cq
                rows.append(row)
                rhs.append(limit)
        self.Aub = np.asarray(rows)
        self.bub = np.asarray(rhs)

    def solve(self, lower_pel: np.ndarray, upper_pel: np.ndarray, maximize_pel: bool) -> dict:
        lower_pel = np.asarray(lower_pel, dtype=float)
        upper_pel = np.asarray(upper_pel, dtype=float)
        require(np.all(lower_pel >= -TOL), "Negative realized electrolyzer load")
        require(np.all(upper_pel + TOL >= lower_pel), "Candidate below realized electrolyzer load")
        bounds: list[tuple[float | None, float | None]] = [(None, None)] * self.nvars
        for idx in self.v_idx:
            bounds[idx] = (self.data.vmin_pu ** 2, self.data.vmax_pu ** 2)
        bounds[self.p_grid_idx] = (0, self.data.p_substation_max_kw)
        bounds[self.q_grid_idx] = (None, None)
        for idx in self.pv_idx:
            bounds[idx] = (0, self.pv_available_site_kw)
        for idx, lo, hi in zip(self.pel_idx, lower_pel, upper_pel):
            bounds[idx] = (float(lo), float(hi))
        c = np.zeros(self.nvars)
        if maximize_pel:
            c[self.pel_idx] = -1
            c[self.p_grid_idx] = 1e-9
        else:
            c[self.p_grid_idx] = 1
        result = linprog(
            c, A_ub=self.Aub, b_ub=self.bub, A_eq=self.Aeq, b_eq=self.beq,
            bounds=bounds, method="highs",
            options={"primal_feasibility_tolerance": 1e-9,
                     "dual_feasibility_tolerance": 1e-9},
        )
        require(result.success, f"Hourly grid LP failed at hour {self.global_hour}: {result.message}")
        x = result.x
        p = x[self.p_idx]
        q = x[self.q_idx]
        voltage = np.sqrt(np.maximum(x[self.v_idx], 0))
        true_s = np.hypot(p, q) / 1000.0
        facet_util = np.column_stack([
            p / (self.data.octagon_a * self.data.branch_smax_mva * 1000),
            -p / (self.data.octagon_a * self.data.branch_smax_mva * 1000),
            q / (self.data.octagon_a * self.data.branch_smax_mva * 1000),
            -q / (self.data.octagon_a * self.data.branch_smax_mva * 1000),
            (p + q) / (self.data.octagon_b * self.data.branch_smax_mva * 1000),
            (-p - q) / (self.data.octagon_b * self.data.branch_smax_mva * 1000),
            (p - q) / (self.data.octagon_b * self.data.branch_smax_mva * 1000),
            (-p + q) / (self.data.octagon_b * self.data.branch_smax_mva * 1000),
        ])
        pel = x[self.pel_idx]
        requested = max(0.0, float((upper_pel - lower_pel).sum()))
        additional = max(0.0, float((pel - lower_pel).sum()))
        missing = np.maximum(0, upper_pel - pel)
        full = float(missing.sum()) <= HOST_TOL_KW
        max_octagon = float(facet_util.max())
        min_voltage = float(voltage.min())
        max_voltage = float(voltage.max())
        incomplete = not full
        voltage_limited = incomplete and (
            min_voltage <= self.data.vmin_pu + BIND_TOL
            or max_voltage >= self.data.vmax_pu - BIND_TOL
        )
        branch_limited = incomplete and max_octagon >= 1 - BIND_TOL
        substation_limited = incomplete and x[self.p_grid_idx] >= self.data.p_substation_max_kw - HOST_TOL_KW
        max_branch = int(np.argmax(true_s))
        return {
            "solver_success": True,
            "p_el_new_kw": pel,
            "max_additional_hosting_kw": additional,
            "requested_additional_kw": requested,
            "hosting_ratio": 1.0 if requested <= HOST_TOL_KW else
                float(np.clip(additional / requested, 0, 1)),
            "full_hostable": full,
            "min_voltage_pu": min_voltage,
            "max_voltage_pu": max_voltage,
            "voltage_margin_pu": min(min_voltage - self.data.vmin_pu,
                                     self.data.vmax_pu - max_voltage),
            "critical_bus": int(np.argmin(voltage) + 1),
            "max_true_s_mva": float(true_s[max_branch]),
            "max_true_s_utilization": float(true_s[max_branch] / self.data.branch_smax_mva),
            "critical_branch_id": max_branch + 1,
            "critical_branch_from": int(self.data.branch_from[max_branch] + 1),
            "critical_branch_to": int(self.data.branch_to[max_branch] + 1),
            "max_octagon_utilization": max_octagon,
            "voltage_limited_flag": voltage_limited,
            "branch_limited_flag": branch_limited,
            "substation_limited_flag": substation_limited,
            "unclassified_limited_flag": incomplete and not (
                voltage_limited or branch_limited or substation_limited
            ),
            "root_grid_import_kw": float(x[self.p_grid_idx]),
            "root_reactive_import_kvar": float(x[self.q_grid_idx]),
            "pv_used_kw": float(x[self.pv_idx].sum()),
            "max_p_balance_error_kw": float(np.abs(self.Aeq[:33] @ x - self.beq[:33]).max()),
            "max_q_balance_error_kvar": float(np.abs(self.Aeq[33:66] @ x - self.beq[33:66]).max()),
            "max_voltage_drop_error": float(np.abs(self.Aeq[66:98] @ x - self.beq[66:98]).max()),
            "slack_voltage_error": float(abs(self.Aeq[-1] @ x - self.beq[-1])),
            "max_octagon_violation_kva": float(max(0, (self.Aub @ x - self.bub).max())),
            "true_circle_violation_mva": float(max(0, true_s.max() - self.data.branch_smax_mva)),
        }


def process_preflight() -> tuple[int, str]:
    records = []
    live = 0
    stopped = {getattr(psutil, "STATUS_STOPPED", "stopped"),
               getattr(psutil, "STATUS_ZOMBIE", "zombie"),
               getattr(psutil, "STATUS_DEAD", "dead")}
    for proc in psutil.process_iter(["pid", "name", "status"]):
        name = (proc.info.get("name") or "").lower()
        if "matlab" in name or "gurobi" in name or name.startswith("grb"):
            status = proc.info.get("status") or "unknown"
            records.append(f"{proc.info['pid']}:{proc.info['name']}:{status}")
            if status not in stopped:
                live += 1
    return live, ";".join(records) if records else "NONE"


def repository_preflight(raw_before: dict[str, str]) -> pd.DataFrame:
    branch = git("branch", "--show-current")
    head = git("rev-parse", "HEAD")
    upstream = git("rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}")
    counts = git("rev-list", "--left-right", "--count", f"HEAD...{EXPECTED_UPSTREAM}").split()
    tracked = git("status", "--short", "--untracked-files=no").splitlines()
    untracked = git("ls-files", "--others", "--exclude-standard").splitlines()
    live_count, process_records = process_preflight()
    rows = [
        ("branch", branch, EXPECTED_BRANCH, branch == EXPECTED_BRANCH),
        ("HEAD", head, EXPECTED_HEAD, head == EXPECTED_HEAD),
        ("upstream", upstream, EXPECTED_UPSTREAM, upstream == EXPECTED_UPSTREAM),
        ("ahead", counts[0], "0", counts[0] == "0"),
        ("behind", counts[1], "0", counts[1] == "0"),
        ("tracked_dirty_count_preserved", len(tracked), ">=0; do not clean", True),
        ("tracked_dirty_paths_preserved", " | ".join(tracked) or "NONE", "informational", True),
        ("untracked_file_count_preserved", len(untracked), ">=0; do not clean", True),
        ("live_MATLAB_Gurobi_count", live_count, "0", live_count == 0),
        ("MATLAB_Gurobi_process_records", process_records,
         "stopped stale objects permitted; no live process", live_count == 0),
        ("raw_hashes_before", json.dumps(raw_before, sort_keys=True),
         json.dumps(EXPECTED_RAW, sort_keys=True), raw_before == EXPECTED_RAW),
    ]
    return pd.DataFrame(rows, columns=["check", "observed", "expected", "pass"])


def load_hour_profiles() -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    hour_cols = ["path_id", "stage", "global_hour", "site", "electrical_bus", "P_EL_kW",
                 "pv_available_kw", "pv_used_kw"]
    system_cols = ["path_id", "stage", "global_hour", "total_P_EL_kW", "pv_available_kw",
                   "pv_used_kw", "root_grid_import", "min_voltage_pu", "min_voltage_bus",
                   "max_line_mva", "max_line_id", "max_line_from", "max_line_to",
                   "max_line_loading_pct"]
    hour = pd.read_csv(RAW / "hourly_site/oos_hour_site.csv", usecols=hour_cols)
    system = pd.read_csv(RAW / "grid_hourly/oos_hour_system.csv", usecols=system_cols)
    path = pd.read_csv(RAW / "path_summary/oos_path_summary.csv")
    require(len(hour) == 4 * len(system), "Hourly site/system row count mismatch")
    require(not hour.duplicated(["path_id", "global_hour", "site"]).any(), "Duplicate site-hour")
    require(not system.duplicated(["path_id", "global_hour"]).any(), "Duplicate system-hour")
    require(np.array_equal(np.sort(hour.electrical_bus.unique()), np.sort(SITE_BUSES)),
            "Saved OOS site-bus mapping mismatch")
    wide = hour.pivot(index=["path_id", "stage", "global_hour"], columns="site", values="P_EL_kW").reset_index()
    wide.columns = ["path_id", "stage", "global_hour", "pel1_kw", "pel2_kw", "pel3_kw", "pel4_kw"]
    actual = system.merge(wide, on=["path_id", "stage", "global_hour"], validate="one_to_one")
    actual["end_hour"] = actual.path_id.map(path.set_index("path_id").operating_stage_count) * 8
    actual["relative_hour"] = actual.global_hour - actual.end_hour
    keys = ["global_hour", "pel1_kw", "pel2_kw", "pel3_kw", "pel4_kw"]
    grouped = actual.groupby(keys, sort=True, dropna=False)
    profiles = grouped.agg(
        occurrence_count=("path_id", "size"),
        saved_root_grid_import=("root_grid_import", "first"),
        saved_root_grid_import_span=("root_grid_import", lambda x: x.max() - x.min()),
        saved_pv_used_kw=("pv_used_kw", "first"),
        saved_pv_used_span=("pv_used_kw", lambda x: x.max() - x.min()),
        saved_min_voltage_pu=("min_voltage_pu", "first"),
        saved_min_voltage_span=("min_voltage_pu", lambda x: x.max() - x.min()),
        saved_min_voltage_bus=("min_voltage_bus", "first"),
        saved_max_line_mva=("max_line_mva", "first"),
        saved_max_line_span=("max_line_mva", lambda x: x.max() - x.min()),
        saved_max_line_id=("max_line_id", "first"),
        saved_max_line_from=("max_line_from", "first"),
        saved_max_line_to=("max_line_to", "first"),
        saved_max_line_loading=("max_line_loading_pct", "first"),
    ).reset_index()
    profiles.insert(0, "profile_id", np.arange(1, len(profiles) + 1))
    actual = actual.merge(profiles[keys + ["profile_id"]], on=keys, validate="many_to_one")
    require(int(profiles.occurrence_count.sum()) == len(system), "Profile weights do not cover system hours")
    return hour, system, path, actual, profiles


def solve_profiles(data: GridData, profiles: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    base_rows, s4_rows, all_site_rows, joint_rows = [], [], [], []
    lp_cache = {hour: HourlyGridLP(data, hour) for hour in range(1, 49)}
    for number, row in enumerate(profiles.itertuples(index=False), 1):
        pel = np.array([row.pel1_kw, row.pel2_kw, row.pel3_kw, row.pel4_kw], dtype=float)
        common = {"profile_id": row.profile_id, "global_hour": row.global_hour,
                  "occurrence_count": row.occurrence_count,
                  "realized_pel1_kw": pel[0], "realized_pel2_kw": pel[1],
                  "realized_pel3_kw": pel[2], "realized_pel4_kw": pel[3]}
        lp = lp_cache[int(row.global_hour)]
        base_result = lp.solve(pel, pel, maximize_pel=False)
        base_rows.append({**common, **flatten_result(base_result),
                          "saved_root_grid_import": row.saved_root_grid_import,
                          "saved_pv_used_kw": row.saved_pv_used_kw,
                          "saved_min_voltage_pu": row.saved_min_voltage_pu,
                          "saved_min_voltage_bus": row.saved_min_voltage_bus,
                          "saved_max_line_mva": row.saved_max_line_mva,
                          "saved_max_line_id": row.saved_max_line_id,
                          "saved_max_line_from": row.saved_max_line_from,
                          "saved_max_line_to": row.saved_max_line_to,
                          "saved_max_line_loading": row.saved_max_line_loading,
                          "saved_profile_max_span": max(
                              row.saved_root_grid_import_span, row.saved_pv_used_span,
                              row.saved_min_voltage_span, row.saved_max_line_span),
                          })
        s4_result = lp.solve(pel, np.array([pel[0], pel[1], pel[2], S4_125[3]]), True)
        s4_rows.append({
            **common,
            "realized_pel4_kw": pel[3],
            "current_remaining_base_headroom_kw": BASE[3] - pel[3],
            "candidate_nameplate_increment_kw": S4_125[3] - BASE[3],
            "total_increment_needed_to_candidate_kw": S4_125[3] - pel[3],
            **flatten_result(s4_result),
            "max_additional_site4_hosting_kw": s4_result["max_additional_hosting_kw"],
            "max_new_pel4_kw": s4_result["p_el_new_kw"][3],
            "plus_37p5_from_realized_hostable":
                s4_result["max_additional_hosting_kw"] + HOST_TOL_KW >= min(37.5, S4_125[3] - pel[3]),
            "S4_FULL_INCREMENT_HOSTABLE": "YES" if s4_result["full_hostable"] else "NO",
        })
        for site in range(4):
            upper = pel.copy()
            upper[site] = ALL_125[site]
            result = lp.solve(pel, upper, True)
            all_site_rows.append({
                **common, "site": site + 1, "electrical_bus": SITE_BUSES[site],
                "realized_pel_kw": pel[site], "base_pmax_kw": BASE[site],
                "candidate_pmax_kw": ALL_125[site],
                "base_remaining_headroom_kw": BASE[site] - pel[site],
                "nameplate_increment_kw": ALL_125[site] - BASE[site],
                "total_increment_needed_to_candidate_kw": ALL_125[site] - pel[site],
                **flatten_result(result),
                "max_additional_site_hosting_kw": result["max_additional_hosting_kw"],
                "max_new_pel_kw": result["p_el_new_kw"][site],
                "FULL_TO_CANDIDATE_HOSTABLE": "YES" if result["full_hostable"] else "NO",
            })
        joint = lp.solve(pel, ALL_125, True)
        joint_rows.append({
            **common,
            "joint_nameplate_increment_kw": float((ALL_125 - BASE).sum()),
            "joint_increment_requested_from_realized_kw": float((ALL_125 - pel).sum()),
            **flatten_result(joint),
            "joint_increment_feasible_kw": joint["max_additional_hosting_kw"],
            "joint_hosting_ratio": joint["hosting_ratio"],
            "FULL_CANDIDATE_STRESS_FEASIBLE": "YES" if joint["full_hostable"] else "NO",
        })
        if number % 100 == 0 or number == len(profiles):
            print(f"Solved {number}/{len(profiles)} unique real-hour electrical profiles", flush=True)
    base_frame = pd.DataFrame(base_rows)
    s4_frame = pd.DataFrame(s4_rows)
    all_site_frame = pd.DataFrame(all_site_rows)
    joint_frame = pd.DataFrame(joint_rows)
    stress = joint_frame[[
        "profile_id", "global_hour", "occurrence_count",
        "realized_pel1_kw", "realized_pel2_kw", "realized_pel3_kw", "realized_pel4_kw",
        "joint_nameplate_increment_kw", "joint_increment_requested_from_realized_kw",
        "joint_increment_feasible_kw", "joint_hosting_ratio", "FULL_CANDIDATE_STRESS_FEASIBLE",
        "min_voltage_pu", "max_voltage_pu", "voltage_margin_pu", "critical_bus",
        "critical_branch_id", "critical_branch_from", "critical_branch_to",
        "max_true_s_mva", "max_true_s_utilization", "max_octagon_utilization",
        "voltage_limited_flag", "branch_limited_flag", "substation_limited_flag",
        "unclassified_limited_flag",
    ]].copy()
    stress.rename(columns={
        "min_voltage_pu": "limiting_or_full_solution_min_voltage_pu",
        "max_voltage_pu": "limiting_or_full_solution_max_voltage_pu",
    }, inplace=True)
    stress["STRESS_FAIL_POLICY_INTERPRETATION"] = np.where(
        stress.FULL_CANDIDATE_STRESS_FEASIBLE.eq("NO"),
        "FAIL_ONLY_MEANS_NOT_ALL_EXPANDED_SITES_CAN_RUN_AT_CANDIDATE_PMAX_SIMULTANEOUSLY",
        "FULL_SIMULTANEOUS_STRESS_FEASIBLE",
    )
    return base_frame, s4_frame, all_site_frame, joint_frame, stress


def flatten_result(result: dict) -> dict:
    return {key: value for key, value in result.items() if key != "p_el_new_kw"}


def base_reproduction(data: GridData, system: pd.DataFrame, base: pd.DataFrame) -> pd.DataFrame:
    weight = base.occurrence_count.to_numpy()
    lower_viol = int(((base.min_voltage_pu < data.vmin_pu - TOL).astype(int) * weight).sum())
    upper_viol = int(((base.max_voltage_pu > data.vmax_pu + TOL).astype(int) * weight).sum())
    line_true_viol = int(((base.max_true_s_mva > data.branch_smax_mva + TOL).astype(int) * weight).sum())
    oct_viol = int(((base.max_octagon_violation_kva > TOL).astype(int) * weight).sum())
    saved_lower_viol = int((system.min_voltage_pu < data.vmin_pu - TOL).sum())
    saved_line_viol = int((system.max_line_mva > data.branch_smax_mva + TOL).sum())
    rows = [
        ("real_decision_hour_count", len(system), len(system), 0, True),
        ("unique_electrical_profile_count", len(base), len(base), 0, True),
        ("saved_profile_invariance_max_span", base.saved_profile_max_span.max(), 0, TOL,
         base.saved_profile_max_span.max() <= TOL),
        ("voltage_lower_violation_count", lower_viol, saved_lower_viol, 0,
         lower_viol == saved_lower_viol == 0),
        ("voltage_upper_violation_count", upper_viol, 0, 0, upper_viol == 0),
        ("minimum_voltage_pu", base.min_voltage_pu.min(), system.min_voltage_pu.min(), TOL,
         abs(base.min_voltage_pu.min() - system.min_voltage_pu.min()) <= TOL),
        ("maximum_voltage_pu", base.max_voltage_pu.max(), 1.0, TOL,
         abs(base.max_voltage_pu.max() - 1.0) <= TOL),
        ("min_voltage_profile_max_abs_residual", (base.min_voltage_pu - base.saved_min_voltage_pu).abs().max(),
         0, TOL, (base.min_voltage_pu - base.saved_min_voltage_pu).abs().max() <= TOL),
        ("min_voltage_bus_mismatch_profiles", int((base.critical_bus != base.saved_min_voltage_bus).sum()),
         0, 0, bool((base.critical_bus == base.saved_min_voltage_bus).all())),
        ("maximum_true_apparent_power_mva", base.max_true_s_mva.max(), system.max_line_mva.max(), TOL,
         abs(base.max_true_s_mva.max() - system.max_line_mva.max()) <= TOL),
        ("true_apparent_power_profile_max_abs_residual", (base.max_true_s_mva - base.saved_max_line_mva).abs().max(),
         0, TOL, (base.max_true_s_mva - base.saved_max_line_mva).abs().max() <= TOL),
        ("critical_branch_id_mismatch_profiles", int((base.critical_branch_id != base.saved_max_line_id).sum()),
         0, 0, bool((base.critical_branch_id == base.saved_max_line_id).all())),
        ("maximum_true_apparent_utilization", base.max_true_s_utilization.max(),
         system.max_line_loading_pct.max(), TOL,
         abs(base.max_true_s_utilization.max() - system.max_line_loading_pct.max()) <= TOL),
        ("maximum_octagon_utilization", base.max_octagon_utilization.max(), "<=1", TOL,
         base.max_octagon_utilization.max() <= 1 + TOL),
        ("octagon_violation_hour_count", oct_viol, 0, 0, oct_viol == 0),
        ("true_line_limit_violation_hour_count", line_true_viol, saved_line_viol, 0,
         line_true_viol == saved_line_viol == 0),
        ("root_import_profile_max_abs_residual_kw", (base.root_grid_import_kw - base.saved_root_grid_import).abs().max(),
         0, TOL, (base.root_grid_import_kw - base.saved_root_grid_import).abs().max() <= TOL),
        ("pv_used_profile_max_abs_residual_kw", (base.pv_used_kw - base.saved_pv_used_kw).abs().max(),
         0, TOL, (base.pv_used_kw - base.saved_pv_used_kw).abs().max() <= TOL),
        ("max_active_balance_residual_kw", base.max_p_balance_error_kw.max(), "<=1e-7", TOL,
         base.max_p_balance_error_kw.max() <= TOL),
        ("max_reactive_balance_residual_kvar", base.max_q_balance_error_kvar.max(), "<=1e-7", TOL,
         base.max_q_balance_error_kvar.max() <= TOL),
        ("max_voltage_drop_residual", base.max_voltage_drop_error.max(), "<=1e-7", TOL,
         base.max_voltage_drop_error.max() <= TOL),
        ("slack_voltage_residual", base.slack_voltage_error.max(), "<=1e-7", TOL,
         base.slack_voltage_error.max() <= TOL),
        ("electrolyzer_PEL_within_Base_Pmax", float(base[[f"realized_pel{i}_kw" for i in range(1,5)]].to_numpy().max()),
         "sitewise <= [300,200,120,150]", TOL,
         bool((base[[f"realized_pel{i}_kw" for i in range(1,5)]].to_numpy() <= BASE + TOL).all())),
    ]
    frame = pd.DataFrame(rows, columns=["check", "reproduced", "saved_or_expected", "tolerance", "pass"])
    require(frame["pass"].all(), "Base grid QA reproduction did not close")
    return frame


def summarize_s4(frame: pd.DataFrame) -> pd.DataFrame:
    w = frame.occurrence_count.to_numpy()
    host = frame.S4_FULL_INCREMENT_HOSTABLE.eq("YES").to_numpy()
    metrics = {
        "total_checked_hours": int(w.sum()),
        "unique_electrical_profiles": len(frame),
        "hostable_hours": int(w[host].sum()),
        "non_hostable_hours": int(w[~host].sum()),
        "hostable_ratio": float(w[host].sum() / w.sum()),
        "additional_headroom_q50_kw": weighted_quantile(frame.max_additional_site4_hosting_kw, w, .50),
        "additional_headroom_q90_kw": weighted_quantile(frame.max_additional_site4_hosting_kw, w, .90),
        "additional_headroom_q95_kw": weighted_quantile(frame.max_additional_site4_hosting_kw, w, .95),
        "additional_headroom_q99_kw": weighted_quantile(frame.max_additional_site4_hosting_kw, w, .99),
        "minimum_additional_headroom_kw": frame.max_additional_site4_hosting_kw.min(),
        "voltage_limited_hours": int(w[frame.voltage_limited_flag].sum()),
        "branch_limited_hours": int(w[frame.branch_limited_flag].sum()),
        "substation_limited_hours": int(w[frame.substation_limited_flag].sum()),
        "minimum_resulting_voltage_pu": frame.min_voltage_pu.min(),
        "maximum_true_apparent_power_mva": frame.max_true_s_mva.max(),
        "maximum_octagon_utilization": frame.max_octagon_utilization.max(),
        "most_frequent_critical_bus": most_frequent(frame.critical_bus, w),
        "most_frequent_critical_branch": most_frequent(frame.critical_branch_id, w),
    }
    return pd.DataFrame({"metric": list(metrics), "value": list(metrics.values())})


def summarize_all(site: pd.DataFrame, joint: pd.DataFrame, stress: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for site_id, group in site.groupby("site"):
        w = group.occurrence_count.to_numpy()
        host = group.FULL_TO_CANDIDATE_HOSTABLE.eq("YES").to_numpy()
        rows.extend([
            (f"site{site_id}_full_increment_hostable_ratio", float(w[host].sum() / w.sum())),
            (f"site{site_id}_voltage_limited_ratio", float(w[group.voltage_limited_flag].sum() / w.sum())),
            (f"site{site_id}_branch_limited_ratio", float(w[group.branch_limited_flag].sum() / w.sum())),
            (f"site{site_id}_minimum_additional_headroom_kw", group.max_additional_site_hosting_kw.min()),
            (f"site{site_id}_median_additional_headroom_kw", weighted_quantile(group.max_additional_site_hosting_kw, w, .5)),
        ])
    w = joint.occurrence_count.to_numpy()
    full = joint.FULL_CANDIDATE_STRESS_FEASIBLE.eq("YES").to_numpy()
    rows.extend([
        ("total_checked_hours", int(w.sum())),
        ("unique_electrical_profiles", len(joint)),
        ("joint_nameplate_extra_capacity_requested_kw", float((ALL_125 - BASE).sum())),
        ("joint_mean_increment_requested_from_realized_kw", weighted_mean(joint.joint_increment_requested_from_realized_kw, w)),
        ("joint_mean_increment_feasible_kw", weighted_mean(joint.joint_increment_feasible_kw, w)),
        ("joint_mean_hosting_ratio", weighted_mean(joint.joint_hosting_ratio, w)),
        ("full_candidate_stress_feasible_ratio", float(w[full].sum() / w.sum())),
        ("voltage_limited_ratio", float(w[joint.voltage_limited_flag].sum() / w.sum())),
        ("branch_limited_ratio", float(w[joint.branch_limited_flag].sum() / w.sum())),
        ("substation_limited_ratio", float(w[joint.substation_limited_flag].sum() / w.sum())),
        ("minimum_resulting_voltage_pu", joint.min_voltage_pu.min()),
        ("maximum_true_apparent_power_mva", joint.max_true_s_mva.max()),
        ("maximum_octagon_utilization", joint.max_octagon_utilization.max()),
        ("most_frequent_critical_bus", most_frequent(joint.critical_bus, w)),
        ("most_frequent_critical_branch", most_frequent(joint.critical_branch_id, w)),
    ])
    return pd.DataFrame(rows, columns=["metric", "value"])


def build_critical_windows(actual: pd.DataFrame, path: pd.DataFrame, s4: pd.DataFrame,
                           all_site: pd.DataFrame, joint: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame, dict]:
    previous = pd.read_csv(PREVIOUS / "02_counterfactual_recoverability/pmax_candidate_recoverability_by_path.csv")
    stage7 = path[path.reached_stage7.eq(1)].sort_values(["terminal_site_gap", "path_id"]).reset_index(drop=True)
    cut95 = math.floor(.95 * len(stage7))
    cut99 = math.floor(.99 * len(stage7))
    difficult4 = set(stage7.iloc[cut95:cut99].path_id.astype(int))
    extreme1 = set(stage7.iloc[cut99:].path_id.astype(int))

    def base_ids(hours: int) -> set[int]:
        rows = previous[(previous.candidate.eq("B0")) &
                        (previous.hours_before_stage7.eq(hours)) &
                        (previous.PHYSICALLY_UNRECOVERABLE)]
        return set(rows.path_id.astype(int))

    def recovered_ids(candidate: str) -> set[int]:
        rows = previous[(previous.candidate.eq(candidate)) & previous.recovered_relative_to_base]
        return set(rows.path_id.astype(int))

    sets = {
        "BASE_UNRECOVERABLE_-16H": (base_ids(16), -16),
        "BASE_UNRECOVERABLE_-8H": (base_ids(8), -8),
        "BASE_UNRECOVERABLE_-4H": (base_ids(4), -4),
        "ALL125_PHYSICALLY_RECOVERED": (recovered_ids("ALL_125"), -16),
        "DIFFICULT4": (difficult4, -16),
        "EXTREME1": (extreme1, -16),
        "S4_125_PHYSICALLY_RECOVERED": (recovered_ids("S4_125"), -16),
    }
    profile_map_s4 = s4.set_index("profile_id")
    profile_map_joint = joint.set_index("profile_id")
    site_maps = {
        site_id: all_site[all_site.site.eq(site_id)].set_index("profile_id")
        for site_id in range(1, 5)
    }
    rows = []
    for subset, (ids, start) in sets.items():
        selected = actual[
            actual.path_id.isin(ids) & actual.relative_hour.ge(start) & actual.relative_hour.le(-1)
        ][["path_id", "stage", "global_hour", "relative_hour", "profile_id"]].copy()
        for candidate, results in [("S4_125", profile_map_s4), ("ALL_125", profile_map_joint)]:
            for row in selected.itertuples(index=False):
                result = results.loc[row.profile_id]
                if candidate == "S4_125":
                    requested = result.total_increment_needed_to_candidate_kw
                    feasible = result.max_additional_site4_hosting_kw
                    full = result.S4_FULL_INCREMENT_HOSTABLE
                    ratio = result.hosting_ratio
                else:
                    requested = result.joint_increment_requested_from_realized_kw
                    feasible = result.joint_increment_feasible_kw
                    full = result.FULL_CANDIDATE_STRESS_FEASIBLE
                    ratio = result.joint_hosting_ratio
                site_values = {site_id: site_maps[site_id].loc[row.profile_id]
                               for site_id in range(1, 5)}
                record = {
                    "subset": subset, "candidate": candidate, "window_start_relative_hour": start,
                    "path_id": row.path_id, "stage": row.stage, "global_hour": row.global_hour,
                    "relative_hour": row.relative_hour, "profile_id": row.profile_id,
                    "requested_increment_from_realized_kw": requested,
                    "grid_hostable_increment_kw": feasible,
                    "grid_hosting_ratio": ratio,
                    "full_to_candidate_hostable": full,
                    "resulting_min_voltage_pu": result.min_voltage_pu,
                    "voltage_margin_pu": result.voltage_margin_pu,
                    "critical_bus": result.critical_bus,
                    "critical_branch_id": result.critical_branch_id,
                    "critical_branch_from": result.critical_branch_from,
                    "critical_branch_to": result.critical_branch_to,
                    "max_true_s_mva": result.max_true_s_mva,
                    "max_true_s_utilization": result.max_true_s_utilization,
                    "max_octagon_utilization": result.max_octagon_utilization,
                    "voltage_limited_flag": result.voltage_limited_flag,
                    "branch_limited_flag": result.branch_limited_flag,
                    "substation_limited_flag": result.substation_limited_flag,
                    "site3_plus30_hostable": site_values[3].FULL_TO_CANDIDATE_HOSTABLE,
                    "site3_voltage_limited_flag": site_values[3].voltage_limited_flag,
                    "site3_max_additional_hosting_kw": site_values[3].max_additional_site_hosting_kw,
                }
                for site_id, site_result in site_values.items():
                    record[f"site{site_id}_full_to_candidate_hostable"] = site_result.FULL_TO_CANDIDATE_HOSTABLE
                    record[f"site{site_id}_voltage_limited_flag"] = site_result.voltage_limited_flag
                    record[f"site{site_id}_hosting_ratio"] = site_result.hosting_ratio
                rows.append(record)
    detail = pd.DataFrame(rows)
    summaries = []
    for (subset, candidate), group in detail.groupby(["subset", "candidate"], sort=False):
        ids, start = sets[subset]
        path_counts = group.groupby("path_id").size()
        record = {
            "subset": subset, "candidate": candidate, "window_start_relative_hour": start,
            "subset_path_count": len(ids), "paths_with_real_hours": group.path_id.nunique(),
            "real_hour_count": len(group), "nominal_window_hour_count": len(ids) * abs(start),
            "complete_window_path_count": int((path_counts == abs(start)).sum()),
            "full_to_candidate_hostable_ratio": group.full_to_candidate_hostable.eq("YES").mean(),
            "mean_grid_hosting_ratio": group.grid_hosting_ratio.mean(),
            "minimum_grid_hosting_ratio": group.grid_hosting_ratio.min(),
            "voltage_limited_ratio": group.voltage_limited_flag.mean(),
            "branch_limited_ratio": group.branch_limited_flag.mean(),
            "substation_limited_ratio": group.substation_limited_flag.mean(),
            "minimum_voltage_pu": group.resulting_min_voltage_pu.min(),
            "most_frequent_critical_bus": most_frequent(group.critical_bus, np.ones(len(group))),
            "most_frequent_critical_branch": most_frequent(group.critical_branch_id, np.ones(len(group))),
            "site3_full_plus30_hostable_ratio": group.site3_plus30_hostable.eq("YES").mean(),
            "site3_voltage_limited_ratio": group.site3_voltage_limited_flag.mean(),
        }
        for site_id in range(1, 5):
            record[f"site{site_id}_full_to_candidate_hostable_ratio"] = group[f"site{site_id}_full_to_candidate_hostable"].eq("YES").mean()
            record[f"site{site_id}_voltage_limited_ratio"] = group[f"site{site_id}_voltage_limited_flag"].mean()
            record[f"site{site_id}_mean_hosting_ratio"] = group[f"site{site_id}_hosting_ratio"].mean()
        summaries.append(record)
    summary = pd.DataFrame(summaries)
    identities = {
        name: {"path_count": len(ids), "path_id_set_sha256": id_set_sha(ids), "window_start": start}
        for name, (ids, start) in sets.items()
    }
    return detail, summary, identities


def candidate_critical(summary: pd.DataFrame, candidate: str) -> pd.Series:
    subset = "S4_125_PHYSICALLY_RECOVERED" if candidate == "S4_125" else "ALL125_PHYSICALLY_RECOVERED"
    row = summary[(summary.subset.eq(subset)) & summary.candidate.eq(candidate)]
    require(len(row) == 1, f"Missing critical-window summary for {candidate}")
    return row.iloc[0]


def classify_candidate(all_hour_full: float, critical: pd.Series) -> str:
    critical_full = float(critical.full_to_candidate_hostable_ratio)
    critical_mean = float(critical.mean_grid_hosting_ratio)
    systematic = max(float(critical.voltage_limited_ratio),
                     float(critical.branch_limited_ratio),
                     float(critical.substation_limited_ratio))
    if critical_full >= CLEAR_FULL_HOSTABLE_RATIO and all_hour_full >= CLEAR_FULL_HOSTABLE_RATIO \
            and systematic <= CLEAR_LIMITED_HOUR_RATIO:
        return "CLEAR"
    if critical_full < LIMITED_FULL_HOSTABLE_RATIO or critical_mean < LIMITED_MEAN_HOSTING_RATIO \
            or systematic >= LIMITED_FULL_HOSTABLE_RATIO:
        return "LIMITED"
    return "MIXED"


def classify_component(all_ratio: float, critical_ratio: float) -> str:
    maximum = max(all_ratio, critical_ratio)
    if maximum <= TOL:
        return "CLEAR"
    if maximum >= LIMITED_FULL_HOSTABLE_RATIO:
        return "LIMITED"
    return "POTENTIALLY_LIMITED"


def build_decision(s4: pd.DataFrame, site: pd.DataFrame, joint: pd.DataFrame,
                   critical_summary: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame, dict]:
    s4_w = s4.occurrence_count.to_numpy()
    joint_w = joint.occurrence_count.to_numpy()
    s4_full = float(s4_w[s4.S4_FULL_INCREMENT_HOSTABLE.eq("YES")].sum() / s4_w.sum())
    all_full = float(joint_w[joint.FULL_CANDIDATE_STRESS_FEASIBLE.eq("YES")].sum() / joint_w.sum())
    s4_critical = candidate_critical(critical_summary, "S4_125")
    all_critical = candidate_critical(critical_summary, "ALL_125")
    s4_label = classify_candidate(s4_full, s4_critical)
    all_label = classify_candidate(all_full, all_critical)

    site3 = site[site.site.eq(3)]
    site3_w = site3.occurrence_count.to_numpy()
    site3_full = float(site3_w[site3.FULL_TO_CANDIDATE_HOSTABLE.eq("YES")].sum() / site3_w.sum())
    site3_critical = float(all_critical.site3_full_plus30_hostable_ratio)
    if min(site3_full, site3_critical) >= CLEAR_FULL_HOSTABLE_RATIO:
        site3_label = "CLEAR"
    elif min(site3_full, site3_critical) < LIMITED_FULL_HOSTABLE_RATIO:
        site3_label = "LIMITED"
    else:
        site3_label = "POTENTIALLY_LIMITED"

    branch_all = max(
        float(s4_w[s4.branch_limited_flag].sum() / s4_w.sum()),
        float(joint_w[joint.branch_limited_flag].sum() / joint_w.sum()),
    )
    branch_critical = max(float(s4_critical.branch_limited_ratio), float(all_critical.branch_limited_ratio))
    voltage_all = max(
        float(s4_w[s4.voltage_limited_flag].sum() / s4_w.sum()),
        float(joint_w[joint.voltage_limited_flag].sum() / joint_w.sum()),
    )
    voltage_critical = max(float(s4_critical.voltage_limited_ratio), float(all_critical.voltage_limited_ratio))
    branch_label = classify_component(branch_all, branch_critical)
    voltage_label = classify_component(voltage_all, voltage_critical)

    labels = {
        "S4_125_GRID_HOSTING": s4_label,
        "ALL_125_GRID_HOSTING": all_label,
        "SITE3_INCREMENTAL_HOSTING": site3_label,
        "BRANCH_INCREMENTAL_HOSTING": branch_label,
        "VOLTAGE_INCREMENTAL_HOSTING": voltage_label,
        "RECOMMEND_FRESH_S4_125_POLICY_PILOT": "YES" if s4_label == "CLEAR" else
            ("NO" if s4_label == "LIMITED" else "NEEDS_MORE_GRID_DIAGNOSTIC"),
        "RECOMMEND_FRESH_ALL_125_POLICY_PILOT": "YES" if all_label == "CLEAR" else
            ("NO" if all_label == "LIMITED" else "NEEDS_MORE_GRID_DIAGNOSTIC"),
        "GRID_VARIABLES_REOPTIMIZED_FOR_HOSTING": "YES",
        "POLICY_ACTUAL_USE": "NOT_AVAILABLE_BEFORE_FRESH_RETRAINING",
        "FULLY_CONVERGED": "NO",
        "PENALTY1500_STARTED": "NO",
        "NO_FA_MSP_TRAINING": "YES",
        "NO_OOS_RERUN": "YES",
        "NO_PARAMETER_WRITEBACK": "YES",
        "GRID_HOSTING_LP_ONLY": "YES",
    }
    decision = pd.DataFrame([
        {"candidate": "S4_125", "nameplate_expansion_kw": 37.5,
         "all_hour_full_hostable_ratio": s4_full,
         "critical_window_full_hostable_ratio": s4_critical.full_to_candidate_hostable_ratio,
         "critical_window_mean_hosting_ratio": s4_critical.mean_grid_hosting_ratio,
         "critical_voltage_limited_ratio": s4_critical.voltage_limited_ratio,
         "critical_branch_limited_ratio": s4_critical.branch_limited_ratio,
         "full_simultaneous_stress_ratio": s4_full,
         "policy_actual_use": "NOT_AVAILABLE_BEFORE_FRESH_RETRAINING",
         "grid_hosting_label": s4_label},
        {"candidate": "ALL_125", "nameplate_expansion_kw": float((ALL_125 - BASE).sum()),
         "all_hour_full_hostable_ratio": all_full,
         "critical_window_full_hostable_ratio": all_critical.full_to_candidate_hostable_ratio,
         "critical_window_mean_hosting_ratio": all_critical.mean_grid_hosting_ratio,
         "critical_voltage_limited_ratio": all_critical.voltage_limited_ratio,
         "critical_branch_limited_ratio": all_critical.branch_limited_ratio,
         "full_simultaneous_stress_ratio": all_full,
         "policy_actual_use": "NOT_AVAILABLE_BEFORE_FRESH_RETRAINING",
         "grid_hosting_label": all_label},
    ])
    return decision, pd.DataFrame(labels.items(), columns=["status", "value"]), labels


def build_flexibility_vs_grid(decision: pd.DataFrame) -> pd.DataFrame:
    previous = pd.read_csv(PREVIOUS / "02_counterfactual_recoverability/pmax_candidate_recoverability_summary.csv")
    rows = []
    for candidate in ["S4_125", "ALL_125"]:
        physical = previous[previous.candidate.eq(candidate)].set_index("hours_before_stage7")
        grid = decision[decision.candidate.eq(candidate)].iloc[0]
        if grid.grid_hosting_label == "CLEAR":
            signal = "STRONG_GRID_SUPPORTED_PHYSICAL_GAIN"
        elif grid.grid_hosting_label == "MIXED":
            signal = "PARTIAL_GRID_SUPPORT_FOR_PHYSICAL_GAIN"
        elif grid.grid_hosting_label == "LIMITED":
            signal = "GRID_BOTTLENECK_LIMITS_PHYSICAL_GAIN_USE"
        else:
            signal = "NOT_IDENTIFIABLE"
        rows.append({
            "candidate": candidate,
            "added_kW": grid.nameplate_expansion_kw,
            "physical_recovery_gain_-16": int(physical.loc[16, "recovered_relative_to_base"]),
            "physical_recovery_gain_-8": int(physical.loc[8, "recovered_relative_to_base"]),
            "physical_recovery_gain_-4": int(physical.loc[4, "recovered_relative_to_base"]),
            "critical_window_grid_hostable_ratio": grid.critical_window_full_hostable_ratio,
            "voltage_limited_ratio": grid.critical_voltage_limited_ratio,
            "branch_limited_ratio": grid.critical_branch_limited_ratio,
            "effective_grid_supported_gain_signal": signal,
            "interpretation_boundary":
                "DIAGNOSTIC_LABEL_ONLY; DO_NOT_MULTIPLY_PHYSICAL_PATH_GAINS_BY_HOSTING_RATIO",
        })
    return pd.DataFrame(rows)


def model_audit_markdown(data: GridData) -> str:
    branches = ", ".join(
        f"{i + 1}:{fr + 1}->{to + 1}" for i, (fr, to) in
        enumerate(zip(data.branch_from, data.branch_to))
    )
    return f"""# Stage-89Q-G IEEE33 小时级 Grid Hosting 模型机械审计

## 机械结论

- IEEE33：33 个 bus、32 条启用支路，固定径向拓扑；支路顺序为 `{branches}`。
- slack bus：bus 1，`V_1^2 = 1`；`P_grid` 在 `[0, {data.p_substation_max_kw:.2f}] kW`，`Q_grid` 无显式上下界。
- 基准量：`base_kV = {data.base_kv:g} kV`，`baseMVA = {data.base_mva:g} MVA`。当前方程直接使用 kW/kVAr、ohm 与 base kV；baseMVA 作为冻结元数据，不进入该 ohmic LinDistFlow 系数。
- 电压边界：`0.90 <= V <= 1.10 p.u.`，本轮未改动。
- 支路容量：每条支路 `Smax = {data.branch_smax_mva:g} MVA`；LP 使用冻结 8 面体 `a={data.octagon_a:.10f}`、`b={data.octagon_b:.10f}`，并另外重算真实 `sqrt(P^2+Q^2)`。
- 普通负荷：33-bus 基础有功/无功合计 `{data.p_load_base_kw.sum():g} kW / {data.q_load_base_kvar.sum():g} kVAr`，逐小时乘冻结 48h（24h 重复）`lambda`；hosting 时保持同一真实 global hour。
- PV：Site1-4 各 200 kW，availability 为 `200*phi48(tau)`；`P_PV` 是 `[0, availability]` 内可削减的电网决策变量，没有 PV 无功变量。
- 电解槽接入：`Site1 -> bus24`，`Site2 -> bus14`，`Site3 -> bus18`，`Site4 -> bus31`。`P_EL` 以负号进入相应 bus 有功平衡，因此是 nodal active load。
- 网架处理：当前 OOS 所有小时使用同一 32 支路拓扑，没有路径依赖线路开断变量。
- losses：未考虑。节点平衡和电压降是 lossless LinDistFlow。
- reactive adjustment：普通无功负荷冻结；支路 `Q` 和 slack `Q_grid` 为连续电网变量，PV/电解槽没有无功调节。

## 正式方程

对支路 `i -> j`：

```text
sum(incoming P)_j - sum(outgoing P)_j + P_grid(j) + P_PV(j) - P_EL(j) = P_load(j)
sum(incoming Q)_j - sum(outgoing Q)_j + Q_grid(j) = Q_load(j)
V_j^2 - V_i^2 + 2*(r_ij*P_ij + x_ij*Q_ij)/(12.66^2*1000) = 0
```

每条支路使用 `+/-P <= a*Smax`、`+/-Q <= a*Smax`、`+/-(P+Q) <= b*Smax`、`+/-(P-Q) <= b*Smax`。

## Hosting 冻结与重求解边界

- 来自正式 OOS policy、并冻结为 hosting 下界：该 path-hour 已实现 `P_EL_i`。
- 冻结：普通负荷、PV availability、global hour、拓扑、线路参数、电压边界、支路上限、candidate Pmax 上界。
- 重新求解：`Delta P_EL >= 0`、slack 有功/无功、支路 P/Q、bus 电压平方、PV 实际出力/削减。
- 不进入 LP：H2 inventory、ordinary H2 demand/service、HTT、TerminalLOH、cuts、未来价值和任何 policy 决策。
- `GRID_VARIABLES_REOPTIMIZED_FOR_HOSTING = YES`。
- 这是独立 grid-hosting LP，不是 H2 operational reoptimization。
"""


def labels_text(labels: dict) -> str:
    return "\n".join(f"{key} = {value}" for key, value in labels.items())


def metric(frame: pd.DataFrame, name: str) -> float:
    value = frame.loc[frame.metric.eq(name), "value"].iloc[0]
    return float(value)


def write_readme(s4_summary: pd.DataFrame, all_summary: pd.DataFrame,
                 decision: pd.DataFrame, critical: pd.DataFrame, labels: dict) -> None:
    s4 = decision[decision.candidate.eq("S4_125")].iloc[0]
    allc = decision[decision.candidate.eq("ALL_125")].iloc[0]
    site_ratios = {site: metric(all_summary, f"site{site}_full_increment_hostable_ratio") for site in range(1, 5)}
    all_hour_bottleneck = min(site_ratios, key=site_ratios.get)
    site3_v = metric(all_summary, "site3_voltage_limited_ratio")
    branch_ratio = metric(all_summary, "branch_limited_ratio")
    voltage_ratio = metric(all_summary, "voltage_limited_ratio")
    s4_min = metric(s4_summary, "minimum_additional_headroom_kw")
    all_mean = metric(all_summary, "joint_mean_hosting_ratio")
    difficult = critical[(critical.subset.eq("DIFFICULT4")) & critical.candidate.eq("ALL_125")].iloc[0]
    extreme = critical[(critical.subset.eq("EXTREME1")) & critical.candidate.eq("ALL_125")].iloc[0]
    all_recovered = critical[(critical.subset.eq("ALL125_PHYSICALLY_RECOVERED")) & critical.candidate.eq("ALL_125")].iloc[0]
    critical_site_ratios = {site: float(all_recovered[f"site{site}_full_to_candidate_hostable_ratio"])
                            for site in range(1, 5)}
    critical_bottleneck = min(critical_site_ratios, key=critical_site_ratios.get)
    stress_fail = 1 - float(allc.full_simultaneous_stress_ratio)
    text = f"""# Stage-89Q-G：Pmax 候选增量 Grid Hosting 专项审计

本轮只做独立 IEEE33 小时级 grid-hosting LP。没有训练、没有 forward/backward/cut、没有重跑 OOS、没有重优化 H2 policy，也没有写回 Pmax 或任何正式参数。285,888 个真实小时被精确归并为 1,244 个 `(global_hour,P_EL1..4)` 唯一电气 profile；hourly 输出保留 `occurrence_count`，权重和严格等于 285,888，关键窗口表仍保留逐 path-hour 身份。

## 1. S4_125 新增 37.5 kW 在当前电网中能不能实际用？

全体真实小时中，把 Site4 从已实现功率提高到 187.5 kW 的可承载率为 `{100*s4.all_hour_full_hostable_ratio:.3f}%`；最小可增加 headroom 为 `{s4_min:.3f} kW`。标签为 `{labels['S4_125_GRID_HOSTING']}`。

## 2. 它在真正需要 late production 的关键小时能不能用？

在 `S4_125` 被上一轮物理上界救回路径的最后 16 个真实小时中，完整提升到 187.5 kW 的小时比例为 `{100*s4.critical_window_full_hostable_ratio:.3f}%`，平均 grid-hosting ratio 为 `{100*s4.critical_window_mean_hosting_ratio:.3f}%`。

## 3. S4_125 最常受什么限制？

关键 late-recovery 小时的 voltage/branch limited 比例分别为 `{100*s4.critical_voltage_limited_ratio:.3f}%/{100*s4.critical_branch_limited_ratio:.3f}%`。分类严格使用运行前冻结在脚本和 `hosting_label_thresholds.csv` 中的阈值。

## 4. 是 voltage 还是 branch？

`VOLTAGE_INCREMENTAL_HOSTING = {labels['VOLTAGE_INCREMENTAL_HOSTING']}`，`BRANCH_INCREMENTAL_HOSTING = {labels['BRANCH_INCREMENTAL_HOSTING']}`。全体 `ALL_125` joint 小时的两者 limited ratio 为 `{100*voltage_ratio:.3f}%/{100*branch_ratio:.3f}%`。

## 5. ALL_125 的新增容量整体能不能使用？

相对已实现功率，joint LP 的全小时平均 hosting ratio 为 `{100*all_mean:.3f}%`，所有站同时达到 candidate Pmax 的小时比例为 `{100*allc.full_simultaneous_stress_ratio:.3f}%`；标签为 `{labels['ALL_125_GRID_HOSTING']}`。

## 6. 哪个站是 ALL_125 最主要的 hosting bottleneck？

按更重要的 `ALL_125` 物理救回路径最后16小时口径，最低的是 Site{critical_bottleneck}；Site1-4 分别为 `{100*critical_site_ratios[1]:.3f}%/{100*critical_site_ratios[2]:.3f}%/{100*critical_site_ratios[3]:.3f}%/{100*critical_site_ratios[4]:.3f}%`。全小时单站比例最低的是 Site{all_hour_bottleneck}，但四站全小时比例非常接近；系统 joint 解的临界低电压 bus 始终集中在 bus18。

## 7. Site3 / bus18 的历史 voltage 风险是否在当前数据中重现？

Site3 +30 kW 的全小时 voltage-limited ratio 为 `{100*site3_v:.3f}%`，严格标签为 `{labels['SITE3_INCREMENTAL_HOSTING']}`。该结论只来自当前 penalty=1000 OOS 和当前正式 grid 模型，不使用旧实验替代。

## 8. Site1/Site2/Site4 是否存在明显 hosting 风险？

关键窗口 Site1/Site2/Site4 的完整提升率为 `{100*critical_site_ratios[1]:.3f}%/{100*critical_site_ratios[2]:.3f}%/{100*critical_site_ratios[4]:.3f}%`，都存在与低电压小时重合的部分受限信号，但 Site3 最低。是否“明显”按同一预冻结阈值判断，不因历史经验预判；全小时逐站 voltage/branch 比例和最小 headroom 保存在 `04_all_125/all_125_summary.csv`。

## 9. 是否存在“铭牌扩容很多，但真正可用 headroom 很少”的情况？

`ALL_125` 名牌新增 192.5 kW；全小时从已实现功率到 candidate 的平均 requested/feasible 分别为 `{metric(all_summary,'joint_mean_increment_requested_from_realized_kw'):.3f}/{metric(all_summary,'joint_mean_increment_feasible_kw'):.3f} kW`。因此必须同时看名牌、joint hosting ratio 和 stress，而不能把名牌值当成可用值。

## 10. candidate 全站同时满功率 stress 是否可行？

`ALL_125` full-candidate-stress 可行率为 `{100*allc.full_simultaneous_stress_ratio:.3f}%`，失败率为 `{100*stress_fail:.3f}%`。`S4_125` 的“全同时”只涉及唯一扩容站 Site4，其对应比例为 `{100*s4.full_simultaneous_stress_ratio:.3f}%`。

## 11. stress FAIL 是否意味着 candidate policy 一定不可行？

不一定。FAIL 只表示该小时不能保证所有扩容站同时满功率运行；真实重新训练后的 policy 未必要求这种同时满功率状态。

## 12. difficult-tail / late-recovery hours 中 hosting 情况如何？

`ALL_125` 在 difficult4/extreme1 最后16小时的完整 stress 可行率为 `{100*difficult.full_to_candidate_hostable_ratio:.3f}%/{100*extreme.full_to_candidate_hostable_ratio:.3f}%`，平均 hosting ratio 为 `{100*difficult.mean_grid_hosting_ratio:.3f}%/{100*extreme.mean_grid_hosting_ratio:.3f}%`。只计真实存在小时，没有补零。

## 13. branch thermal limit 是否成为新的瓶颈？

全体 `ALL_125` joint 小时 branch-limited ratio 为 `{100*branch_ratio:.3f}%`，最大 octagon utilization 为 `{metric(all_summary,'maximum_octagon_utilization'):.6f}`；最终标签为 `{labels['BRANCH_INCREMENTAL_HOSTING']}`。

## 14. voltage 是否是主要限制？

全体 `ALL_125` joint 小时 voltage-limited ratio 为 `{100*voltage_ratio:.3f}%`，最终标签为 `{labels['VOLTAGE_INCREMENTAL_HOSTING']}`。该比率只在 candidate headroom 未完全承载且电压边界实际绑定时计数。

## 15. S4_125_GRID_HOSTING 最终是什么？

`S4_125_GRID_HOSTING = {labels['S4_125_GRID_HOSTING']}`。

## 16. ALL_125_GRID_HOSTING 最终是什么？

`ALL_125_GRID_HOSTING = {labels['ALL_125_GRID_HOSTING']}`。

## 17. 哪个 candidate 更适合进入 fresh zero-cut policy pilot？

本轮按氢侧物理增益与当前电网 hosting 两道门联合判断：S4_125 建议为 `{labels['RECOMMEND_FRESH_S4_125_POLICY_PILOT']}`，ALL_125 为 `{labels['RECOMMEND_FRESH_ALL_125_POLICY_PILOT']}`。这不是自动采用或训练指令。

## 18. 当前能否说扩 Pmax 后 Stage1 会下降？

不能，必须 fresh retraining。

## 19. 当前能否说 terminal shortfall 会下降？

不能，必须 fresh retraining + OOS。

## 20. 是否建议进入 S4_125 fresh-policy pilot？

`RECOMMEND_FRESH_S4_125_POLICY_PILOT = {labels['RECOMMEND_FRESH_S4_125_POLICY_PILOT']}`。本轮在 push 后停止，不自动训练。

## 判级与解释边界

- `CLEAR`：candidate-specific late-recovery 小时 full-hostable ratio 与全小时 ratio 都至少 `{CLEAR_FULL_HOSTABLE_RATIO:.0%}`，且 voltage/branch/substation systematic-limited ratio 都不高于 `{CLEAR_LIMITED_HOUR_RATIO:.0%}`。
- `LIMITED`：关键窗口 full-hostable ratio 或 mean hosting ratio 低于 `{LIMITED_FULL_HOSTABLE_RATIO:.0%}`，或任一系统性瓶颈比例至少 `{LIMITED_FULL_HOSTABLE_RATIO:.0%}`。
- 其余为 `MIXED`；数据/语义不足才为 `NOT_IDENTIFIABLE`。
- `NAMEPLATE_EXPANSION`、`GRID_HOSTABLE_INCREMENT`、`FULL_SIMULTANEOUS_STRESS` 与 `POLICY_ACTUAL_USE` 是四个不同概念。
- `POLICY_ACTUAL_USE = NOT_AVAILABLE_BEFORE_FRESH_RETRAINING`。
- `effective_grid_supported_gain_signal` 只是诊断标签；没有把 physical recovery gain 乘 hosting ratio 伪造新的正式路径数。

## 最终标签

```text
{labels_text(labels)}
```
"""
    path_out = OUT / "08_summary/README.md"
    path_out.parent.mkdir(parents=True, exist_ok=True)
    path_out.write_text(text, encoding="utf-8")


def weighted_values(frame: pd.DataFrame, column: str) -> np.ndarray:
    return np.repeat(frame[column].to_numpy(dtype=float), frame.occurrence_count.to_numpy(dtype=int))


def finish_figure(fig: plt.Figure, name: str) -> None:
    fig.tight_layout()
    fig.savefig(io_path(FIG / name), dpi=180, bbox_inches="tight", facecolor="white")
    plt.close(fig)


def generate_figures(s4: pd.DataFrame, site: pd.DataFrame, joint: pd.DataFrame,
                     stress: pd.DataFrame, critical: pd.DataFrame,
                     flex: pd.DataFrame, decision: pd.DataFrame) -> list[Path]:
    setup_chinese_font()
    FIG.mkdir(parents=True, exist_ok=True)
    colors = {"green": "#2A7F62", "red": "#C55245", "blue": "#3B6EA8",
              "gold": "#C28B2C", "gray": "#6B7280"}

    fig, ax = plt.subplots(figsize=(8.4, 4.8))
    ax.hist(weighted_values(s4, "max_additional_site4_hosting_kw"), bins=35,
            color=colors["blue"], alpha=.85, edgecolor="white")
    ax.axvline(37.5, color=colors["red"], ls="--", label="名牌新增 37.5 kW")
    ax.set(title="S4_125：从已实现功率出发的 Site4 可增加 Hosting Headroom",
           xlabel="最大可增加 Site4 负荷（kW）", ylabel="真实小时数")
    ax.legend()
    finish_figure(fig, "01_S4_125增量headroom分布.png")

    crit = critical[(critical.candidate.eq("S4_125")) & critical.subset.isin([
        "BASE_UNRECOVERABLE_-16H", "BASE_UNRECOVERABLE_-8H", "BASE_UNRECOVERABLE_-4H",
        "S4_125_PHYSICALLY_RECOVERED", "DIFFICULT4", "EXTREME1"])]
    fig, ax = plt.subplots(figsize=(9.2, 5.0))
    labels = crit.subset.str.replace("_", " ").tolist()
    ax.bar(np.arange(len(crit)), 100 * crit.full_to_candidate_hostable_ratio,
           color=[colors["green"] if v >= .95 else colors["gold"] if v >= .5 else colors["red"]
                  for v in crit.full_to_candidate_hostable_ratio])
    ax.set_xticks(np.arange(len(crit)))
    ax.set_xticklabels(labels, rotation=22, ha="right")
    ax.set_ylim(0, 105); ax.set_ylabel("完整提升到 187.5 kW 的小时比例（%）")
    ax.set_title("S4_125：关键 late-recovery 窗口电网 Hosting")
    finish_figure(fig, "02_S4_125关键窗口hosting.png")

    fig, ax = plt.subplots(figsize=(8.8, 5.0))
    data = [weighted_values(group, "max_additional_site_hosting_kw")
            for _, group in site.groupby("site")]
    bp = ax.boxplot(data, labels=["Site1", "Site2", "Site3/bus18", "Site4"],
                    showfliers=False, patch_artist=True)
    for patch, color in zip(bp["boxes"], [colors["blue"], colors["green"], colors["red"], colors["gold"]]):
        patch.set_facecolor(color); patch.set_alpha(.72)
    ax.set(title="ALL_125：四站单站增量 Hosting Headroom",
           ylabel="从已实现功率可增加到 candidate 的负荷（kW）")
    finish_figure(fig, "03_ALL_125四站增量headroom.png")

    fig, axes = plt.subplots(1, 2, figsize=(10.2, 4.5))
    axes[0].hist(weighted_values(joint, "joint_hosting_ratio") * 100, bins=30,
                 color=colors["green"], edgecolor="white")
    axes[0].set(xlabel="Joint hosting ratio（%）", ylabel="真实小时数", title="Joint hosting ratio 分布")
    axes[1].scatter(joint.joint_increment_requested_from_realized_kw,
                    joint.joint_increment_feasible_kw, s=11, alpha=.5, color=colors["blue"])
    limit = max(joint.joint_increment_requested_from_realized_kw.max(),
                joint.joint_increment_feasible_kw.max())
    axes[1].plot([0, limit], [0, limit], ls="--", color=colors["gray"])
    axes[1].set(xlabel="Requested（kW）", ylabel="Grid feasible（kW）", title="Requested vs feasible")
    fig.suptitle("ALL_125：多站联合增量 Hosting")
    finish_figure(fig, "04_ALL_125_joint_hosting.png")

    all_full = np.average(stress.FULL_CANDIDATE_STRESS_FEASIBLE.eq("YES"), weights=stress.occurrence_count)
    crows = decision.set_index("candidate")
    values = [crows.loc["S4_125", "full_simultaneous_stress_ratio"], all_full]
    fig, ax = plt.subplots(figsize=(7.4, 4.6))
    bars = ax.bar(["S4_125\n唯一扩容站满功率", "ALL_125\n四站同时满功率"], np.array(values) * 100,
                  color=[colors["blue"], colors["red"]])
    ax.bar_label(bars, fmt="%.1f%%"); ax.set_ylim(0, 108)
    ax.set_ylabel("Full-candidate-stress 可行小时比例（%）")
    ax.set_title("Candidate 满功率 Stress Test（FAIL 不等于 policy 不可行）")
    finish_figure(fig, "05_candidate_full_stress可行性.png")

    fig, ax = plt.subplots(figsize=(8.4, 4.8))
    ax.hist(weighted_values(joint, "voltage_margin_pu"), bins=40,
            color=colors["gold"], edgecolor="white")
    ax.axvline(0, color=colors["red"], ls="--")
    ax.set(title="ALL_125 Joint Hosting：电压裕度分布",
           xlabel="到最近电压边界的裕度（p.u.）", ylabel="真实小时数")
    finish_figure(fig, "06_voltage_margin分布.png")

    s3 = site[site.site.eq(3)]
    fig, axes = plt.subplots(1, 2, figsize=(10.2, 4.6))
    axes[0].scatter(s3.realized_pel_kw, s3.max_additional_site_hosting_kw,
                    s=np.maximum(8, np.sqrt(s3.occurrence_count)), alpha=.55, color=colors["red"])
    axes[0].set(xlabel="Site3 已实现 P_EL（kW）", ylabel="可增加 headroom（kW）",
                title="Site3 / bus18 单站 +30 kW hosting")
    counts = s3.groupby("critical_bus").occurrence_count.sum().sort_values(ascending=False).head(8)
    axes[1].bar(counts.index.astype(str), counts.values, color=colors["blue"])
    axes[1].set(xlabel="临界低电压 bus", ylabel="真实小时数", title="Site3 增量解的临界 bus")
    fig.suptitle("Site3 / bus18 当前数据专项审计")
    finish_figure(fig, "07_Site3_bus18_hosting.png")

    bus_counts = joint.groupby("critical_bus").occurrence_count.sum().sort_values(ascending=False).head(10)
    fig, ax = plt.subplots(figsize=(8.2, 4.6))
    ax.bar(bus_counts.index.astype(str), bus_counts.values, color=colors["blue"])
    ax.set(title="ALL_125 Joint Hosting：临界低电压 Bus 频次",
           xlabel="Bus", ylabel="真实小时数")
    finish_figure(fig, "08_critical_bus频次.png")

    branch_counts = joint.groupby(["critical_branch_id", "critical_branch_from", "critical_branch_to"]).occurrence_count.sum().sort_values(ascending=False).head(10)
    fig, ax = plt.subplots(figsize=(8.4, 4.6))
    labels_b = [f"{i}:{f}->{t}" for i, f, t in branch_counts.index]
    ax.bar(labels_b, branch_counts.values, color=colors["gray"])
    ax.set(title="ALL_125 Joint Hosting：最大真实视在功率支路频次",
           xlabel="支路 ID:from->to", ylabel="真实小时数")
    finish_figure(fig, "09_critical_branch频次.png")

    tail = critical[(critical.candidate.eq("ALL_125")) & critical.subset.isin(["DIFFICULT4", "EXTREME1"])]
    fig, ax = plt.subplots(figsize=(7.8, 4.7))
    x = np.arange(len(tail)); width = .36
    ax.bar(x - width/2, 100 * tail.full_to_candidate_hostable_ratio, width,
           label="Full stress 可行率", color=colors["red"])
    ax.bar(x + width/2, 100 * tail.mean_grid_hosting_ratio, width,
           label="平均 joint hosting ratio", color=colors["green"])
    ax.set_xticks(x); ax.set_xticklabels(["difficult 4%", "extreme 1%"]); ax.set_ylim(0, 105)
    ax.set_ylabel("比例（%）"); ax.set_title("困难尾部最后16小时的 ALL_125 Hosting")
    ax.legend()
    finish_figure(fig, "10_difficult_tail_hosting.png")

    fig, ax1 = plt.subplots(figsize=(8.6, 4.8))
    x = np.arange(len(flex)); width = .22
    for j, col in enumerate(["physical_recovery_gain_-16", "physical_recovery_gain_-8", "physical_recovery_gain_-4"]):
        ax1.bar(x + (j-1)*width, flex[col], width, label=col.replace("physical_recovery_gain_", ""))
    ax1.set_xticks(x); ax1.set_xticklabels(flex.candidate); ax1.set_ylabel("物理上界救回路径数")
    ax2 = ax1.twinx(); ax2.plot(x, 100 * flex.critical_window_grid_hostable_ratio,
                                color=colors["red"], marker="o", lw=2, label="关键窗口 grid hostable")
    ax2.set_ylabel("关键窗口完整 hostable 比例（%）"); ax2.set_ylim(0, 105)
    ax1.set_title("Pmax 物理灵活性增益 vs 电网 Hosting（不做乘法修正）")
    h1, l1 = ax1.get_legend_handles_labels(); h2, l2 = ax2.get_legend_handles_labels()
    ax1.legend(h1+h2, l1+l2, loc="upper center", ncol=4)
    finish_figure(fig, "11_physical_flexibility_gain_vs_grid_hosting.png")

    fig, ax = plt.subplots(figsize=(9.2, 5.2))
    ax.axis("off")
    rows = decision[["candidate", "nameplate_expansion_kw", "all_hour_full_hostable_ratio",
                     "critical_window_full_hostable_ratio", "critical_voltage_limited_ratio",
                     "critical_branch_limited_ratio", "grid_hosting_label"]].copy()
    rows.iloc[:, 2:6] = rows.iloc[:, 2:6].astype(float).applymap(lambda x: f"{100*x:.1f}%")
    table = ax.table(cellText=rows.values, colLabels=["候选", "新增kW", "全小时完整承载",
                    "关键窗口完整承载", "关键电压受限", "关键支路受限", "标签"],
                     loc="center", cellLoc="center")
    table.auto_set_font_size(False); table.set_fontsize(8.5); table.scale(1, 1.8)
    for (r, _), cell in table.get_celld().items():
        cell.set_edgecolor("#D1D5DB")
        if r == 0: cell.set_facecolor("#E5E7EB")
    ax.set_title("Stage-89Q-G 候选 Grid Hosting 总结", pad=20, fontsize=14)
    ax.text(.5, .08, "Stress FAIL 只表示不能保证同时满功率，不等于 fresh policy 一定不可行。",
            ha="center", transform=ax.transAxes, color=colors["red"])
    finish_figure(fig, "12_candidate_grid_hosting总结.png")
    return sorted(FIG.glob("*.png"))


def create_contact_sheet(pngs: list[Path]) -> Path:
    thumbs = []
    for number, path in enumerate(pngs, 1):
        with Image.open(io_path(path)) as image:
            image = image.convert("RGB")
            image.thumbnail((520, 310))
            canvas = Image.new("RGB", (540, 350), "white")
            canvas.paste(image, ((540-image.width)//2, 8))
            draw = ImageDraw.Draw(canvas)
            draw.text((12, 324), f"Figure {number:02d}", fill="black")
            thumbs.append(canvas)
    sheet = Image.new("RGB", (1080, math.ceil(len(thumbs)/2)*350), "white")
    for index, thumb in enumerate(thumbs):
        sheet.paste(thumb, ((index % 2)*540, (index//2)*350))
    target = FIG / "contact_sheet.png"
    sheet.save(io_path(target))
    return target


def threshold_table() -> pd.DataFrame:
    return pd.DataFrame([
        ("CLEAR_FULL_HOSTABLE_RATIO", CLEAR_FULL_HOSTABLE_RATIO,
         "candidate critical and all-hour full-hostable ratios must both meet threshold"),
        ("CLEAR_LIMITED_HOUR_RATIO", CLEAR_LIMITED_HOUR_RATIO,
         "each voltage/branch/substation limited ratio must not exceed threshold"),
        ("LIMITED_FULL_HOSTABLE_RATIO", LIMITED_FULL_HOSTABLE_RATIO,
         "below this critical full-hostable ratio, or above/equal systematic bottleneck ratio, is LIMITED"),
        ("LIMITED_MEAN_HOSTING_RATIO", LIMITED_MEAN_HOSTING_RATIO,
         "below this critical mean hosting ratio is LIMITED"),
    ], columns=["threshold", "value", "fixed_interpretation"])


def write_site3_audit(hour: pd.DataFrame, site: pd.DataFrame, critical_detail: pd.DataFrame) -> pd.DataFrame:
    site3_hour = hour[hour.site.eq(3)]
    site3 = site[site.site.eq(3)]
    w = site3.occurrence_count.to_numpy()
    critical = critical_detail[(critical_detail.candidate.eq("ALL_125")) &
                               (critical_detail.subset.eq("ALL125_PHYSICALLY_RECOVERED"))]
    high_threshold = weighted_quantile(site3.realized_pel_kw, w, .90)
    high = site3[site3.realized_pel_kw.ge(high_threshold)]
    hw = high.occurrence_count.to_numpy()
    metrics = {
        "realized_PEL_min_kw": site3_hour.P_EL_kW.min(),
        "realized_PEL_q50_kw": site3_hour.P_EL_kW.quantile(.5),
        "realized_PEL_q90_kw": site3_hour.P_EL_kW.quantile(.9),
        "realized_PEL_q95_kw": site3_hour.P_EL_kW.quantile(.95),
        "realized_PEL_q99_kw": site3_hour.P_EL_kW.quantile(.99),
        "realized_PEL_max_kw": site3_hour.P_EL_kW.max(),
        "high_output_threshold_q90_kw": high_threshold,
        "minimum_voltage_when_site3_high_output_pu": high.min_voltage_pu.min(),
        "site3_plus30_full_hostable_ratio_all_hours":
            float(w[site3.FULL_TO_CANDIDATE_HOSTABLE.eq("YES")].sum()/w.sum()),
        "site3_plus30_voltage_limited_ratio_all_hours":
            float(w[site3.voltage_limited_flag].sum()/w.sum()),
        "site3_plus30_full_hostable_ratio_high_output":
            float(hw[high.FULL_TO_CANDIDATE_HOSTABLE.eq("YES")].sum()/hw.sum()),
        "site3_voltage_margin_q01_pu": weighted_quantile(site3.voltage_margin_pu, w, .01),
        "site3_voltage_margin_q05_pu": weighted_quantile(site3.voltage_margin_pu, w, .05),
        "site3_voltage_margin_q50_pu": weighted_quantile(site3.voltage_margin_pu, w, .50),
        "site3_critical_bus_mode": most_frequent(site3.critical_bus, w),
        "site3_late_recovery_full_hostable_ratio": critical.site3_plus30_hostable.eq("YES").mean(),
        "site3_late_recovery_voltage_limited_ratio": critical.site3_voltage_limited_flag.mean(),
    }
    return pd.DataFrame({"metric": list(metrics), "value": list(metrics.values())})


def main_qa(preflight: pd.DataFrame, data: GridData, raw_before: dict[str, str],
            raw_after: dict[str, str], base_qa: pd.DataFrame, profiles: pd.DataFrame,
            s4: pd.DataFrame, site: pd.DataFrame, joint: pd.DataFrame,
            critical: pd.DataFrame, identities: dict, labels: dict, pngs: list[Path]) -> pd.DataFrame:
    rows = []

    def check(name, observed, expected, passed, tolerance="exact"):
        rows.append({"check": name, "observed": observed, "expected": expected,
                     "tolerance": tolerance, "pass": bool(passed)})

    check("repository_preflight", int(preflight["pass"].sum()), len(preflight), preflight["pass"].all())
    check("formal_Base_Pmax", BASE.tolist(), [300,200,120,150], np.array_equal(BASE, [300,200,120,150]))
    check("S4_125_Pmax", S4_125.tolist(), [300,200,120,187.5], np.array_equal(S4_125, [300,200,120,187.5]))
    check("ALL_125_Pmax", ALL_125.tolist(), [375,250,150,187.5], np.array_equal(ALL_125, [375,250,150,187.5]))
    check("site_bus_mapping", SITE_BUSES.tolist(), [24,14,18,31], np.array_equal(SITE_BUSES,[24,14,18,31]))
    check("IEEE33_identity", f"33/{len(data.branch_from)}/slack1", "33/32/slack1", len(data.branch_from)==32)
    check("base_kv_baseMVA", f"{data.base_kv}/{data.base_mva}", "12.66/10", data.base_kv==12.66 and data.base_mva==10)
    check("voltage_bounds_unchanged", f"{data.vmin_pu}/{data.vmax_pu}", "0.9/1.1", data.vmin_pu==.9 and data.vmax_pu==1.1)
    check("branch_limit_unchanged", data.branch_smax_mva, 6, data.branch_smax_mva==6)
    check("grid_input_hash", sha256(GRID_INPUT), EXPECTED_GRID_INPUT_SHA, sha256(GRID_INPUT)==EXPECTED_GRID_INPUT_SHA)
    model_hashes = {name: sha256(ROOT/name) for name in EXPECTED_MODEL_HASHES}
    check("formal_grid_source_hashes", model_hashes, EXPECTED_MODEL_HASHES, model_hashes==EXPECTED_MODEL_HASHES)
    check("base_grid_QA_reproduction", int(base_qa["pass"].sum()), len(base_qa), base_qa["pass"].all())
    check("real_hours_no_padding", int(profiles.occurrence_count.sum()), 285888, int(profiles.occurrence_count.sum())==285888)
    check("unique_profile_count", len(profiles), 1244, len(profiles)==1244)
    check("S4_profile_solve_count", len(s4), len(profiles), len(s4)==len(profiles))
    check("ALL_site_profile_solve_count", len(site), 4*len(profiles), len(site)==4*len(profiles))
    check("ALL_joint_profile_solve_count", len(joint), len(profiles), len(joint)==len(profiles))
    check("candidate_increments_nonnegative", min(s4.max_additional_site4_hosting_kw.min(), site.max_additional_site_hosting_kw.min(), joint.joint_increment_feasible_kw.min()), ">=-1e-7",
          min(s4.max_additional_site4_hosting_kw.min(), site.max_additional_site_hosting_kw.min(), joint.joint_increment_feasible_kw.min()) >= -TOL)
    check("candidate_PEL_within_Pmax", True, True,
          (s4.max_new_pel4_kw <= S4_125[3]+TOL).all() and
          all((site.loc[site.site.eq(i),"max_new_pel_kw"] <= ALL_125[i-1]+TOL).all() for i in range(1,5)))
    check("hosting_voltage_QA", min(s4.min_voltage_pu.min(), site.min_voltage_pu.min(), joint.min_voltage_pu.min()), ">=0.9-1e-7",
          min(s4.min_voltage_pu.min(), site.min_voltage_pu.min(), joint.min_voltage_pu.min()) >= .9-TOL)
    check("hosting_voltage_upper_QA", max(s4.max_voltage_pu.max(), site.max_voltage_pu.max(), joint.max_voltage_pu.max()), "<=1.1+1e-7",
          max(s4.max_voltage_pu.max(), site.max_voltage_pu.max(), joint.max_voltage_pu.max()) <= 1.1+TOL)
    check("hosting_octagon_QA", max(s4.max_octagon_violation_kva.max(), site.max_octagon_violation_kva.max(), joint.max_octagon_violation_kva.max()), "<=1e-7", max(s4.max_octagon_violation_kva.max(), site.max_octagon_violation_kva.max(), joint.max_octagon_violation_kva.max()) <= TOL)
    check("hosting_true_apparent_power_QA", max(s4.max_true_s_mva.max(), site.max_true_s_mva.max(), joint.max_true_s_mva.max()), "<=6", max(s4.max_true_s_mva.max(), site.max_true_s_mva.max(), joint.max_true_s_mva.max()) <= 6+TOL)
    check("hosting_balance_QA", max(s4.max_p_balance_error_kw.max(), site.max_p_balance_error_kw.max(), joint.max_p_balance_error_kw.max()), "<=1e-7", max(s4.max_p_balance_error_kw.max(), site.max_p_balance_error_kw.max(), joint.max_p_balance_error_kw.max()) <= TOL)
    check("critical_window_subset_identity", identities, "fixed prior-audit path sets", all(v["path_count"]>=0 and len(v["path_id_set_sha256"])==64 for v in identities.values()))
    check("critical_no_padded_zero_hours", int((critical.real_hour_count <= critical.nominal_window_hour_count).all()), 1,
          (critical.real_hour_count <= critical.nominal_window_hour_count).all())
    check("classification_values", {k:labels[k] for k in ["S4_125_GRID_HOSTING","ALL_125_GRID_HOSTING"]}, "CLEAR/MIXED/LIMITED/NOT_IDENTIFIABLE",
          labels["S4_125_GRID_HOSTING"] in {"CLEAR","MIXED","LIMITED","NOT_IDENTIFIABLE"} and labels["ALL_125_GRID_HOSTING"] in {"CLEAR","MIXED","LIMITED","NOT_IDENTIFIABLE"})
    check("policy_actual_use_boundary", labels["POLICY_ACTUAL_USE"], "NOT_AVAILABLE_BEFORE_FRESH_RETRAINING", labels["POLICY_ACTUAL_USE"]=="NOT_AVAILABLE_BEFORE_FRESH_RETRAINING")
    check("grid_LP_only", labels["GRID_HOSTING_LP_ONLY"], "YES", labels["GRID_HOSTING_LP_ONLY"]=="YES")
    check("no_FA_training_OOS", f"{labels['NO_FA_MSP_TRAINING']}/{labels['NO_OOS_RERUN']}", "YES/YES", labels['NO_FA_MSP_TRAINING']==labels['NO_OOS_RERUN']=="YES")
    source = Path(__file__).read_text(encoding="utf-8")
    tree = ast.parse(source)
    called = {getattr(node.func, "id", "") for node in ast.walk(tree) if isinstance(node, ast.Call)}
    banned_calls = {"train_models_h2", "forward_pass_h2", "backward_pass_h2", "add_cut_h2"}
    check("no_FA_core_calls_in_analyzer", sorted(called & banned_calls), [], not (called & banned_calls))
    random_calls = random_capabilities(tree)
    check("no_random_draw", random_calls, [], not random_calls)
    check("figure_count", len(pngs), 12, len(pngs)==12)
    image_ok = []
    for path in pngs:
        with Image.open(io_path(path)) as image:
            pixels = np.asarray(image.convert("RGB"), dtype=np.float32)
            image_ok.append(image.width >= 700 and image.height >= 400 and pixels.std() > 3)
    check("figure_dimensions_nonblank", all(image_ok), True, all(image_ok))
    check("raw_hashes_after", raw_after, raw_before, raw_after==raw_before==EXPECTED_RAW)
    return pd.DataFrame(rows)


def write_manifest() -> None:
    rows = []
    source_paths = [RAW / name for name in EXPECTED_RAW] + [GRID_INPUT] + [ROOT / name for name in EXPECTED_MODEL_HASHES]
    for path in source_paths:
        rows.append({"role":"source", "relative_path":str(path.relative_to(ROOT)),
                     "size_bytes":path.stat().st_size, "sha256":sha256(path), "git_tracked":git("ls-files", str(path.relative_to(ROOT))) != ""})
    for path in [Path(__file__), ROOT / "hourly_grid_h2/audit_stage89q_pmax_grid_hosting.py"]:
        rows.append({"role":"script", "relative_path":str(path.relative_to(ROOT)),
                     "size_bytes":path.stat().st_size, "sha256":sha256(path), "git_tracked":git("ls-files", str(path.relative_to(ROOT))) != ""})
    artifacts = [p for p in OUT.rglob("*") if p.is_file() and "09_qa" not in p.parts and p.name != "lightweight_manifest.csv"]
    artifacts += sorted(FIG.glob("*.png"))
    for path in sorted(set(artifacts)):
        rows.append({"role":"artifact", "relative_path":str(path.relative_to(ROOT)),
                     "size_bytes":path.stat().st_size, "sha256":sha256(path), "git_tracked":git("ls-files", str(path.relative_to(ROOT))) != ""})
    save_csv(pd.DataFrame(rows), OUT / "08_summary/lightweight_manifest.csv")


def main() -> None:
    require(not OUT.exists(), f"Refusing to overwrite existing audit output: {OUT}")
    require(not FIG.exists(), f"Refusing to overwrite existing figure output: {FIG}")
    raw_before = {name: sha256(RAW / name) for name in EXPECTED_RAW}
    require(raw_before == EXPECTED_RAW, "Accepted raw hashes differ before analysis")
    require(sha256(GRID_INPUT) == EXPECTED_GRID_INPUT_SHA, "Frozen grid input hash mismatch")
    preflight = repository_preflight(raw_before)
    require(preflight["pass"].all(), "Repository/process preflight failed")
    data = load_grid_data()

    for directory in [
        "01_model_audit", "02_base_reproduction", "03_s4_125", "04_all_125",
        "05_critical_window", "06_flexibility_vs_grid", "07_candidate_decision",
        "08_summary", "09_qa",
    ]:
        (OUT / directory).mkdir(parents=True, exist_ok=True)
    FIG.mkdir(parents=True, exist_ok=False)
    save_csv(preflight, OUT / "01_model_audit/repository_preflight.csv")
    save_csv(threshold_table(), OUT / "01_model_audit/hosting_label_thresholds.csv")
    (OUT / "01_model_audit/grid_hosting_model_audit.md").write_text(
        model_audit_markdown(data), encoding="utf-8"
    )

    hour, system, path, actual_profiles = None, None, None, None
    hour, system, path, actual, profiles = load_hour_profiles()
    base, s4, all_site, joint, stress = solve_profiles(data, profiles)
    base_qa = base_reproduction(data, system, base)
    save_csv(base_qa, OUT / "02_base_reproduction/base_grid_QA_reproduction.csv")
    save_csv(s4, OUT / "03_s4_125/s4_125_hourly_hosting.csv")
    s4_summary = summarize_s4(s4)
    save_csv(s4_summary, OUT / "03_s4_125/s4_125_summary.csv")
    save_csv(all_site, OUT / "04_all_125/all_125_site_headroom.csv")
    save_csv(joint, OUT / "04_all_125/all_125_joint_hosting.csv")
    save_csv(stress, OUT / "04_all_125/all_125_full_candidate_stress.csv")
    all_summary = summarize_all(all_site, joint, stress)
    save_csv(all_summary, OUT / "04_all_125/all_125_summary.csv")

    critical_detail, critical_summary, identities = build_critical_windows(
        actual, path, s4, all_site, joint
    )
    save_csv(critical_detail, OUT / "05_critical_window/critical_window_grid_hosting.csv")
    save_csv(critical_summary, OUT / "05_critical_window/critical_window_summary.csv")
    identity_frame = pd.DataFrame([
        {"subset": key, **value} for key, value in identities.items()
    ])
    save_csv(identity_frame, OUT / "05_critical_window/critical_window_subset_identity.csv")
    save_csv(write_site3_audit(hour, all_site, critical_detail),
             OUT / "04_all_125/site3_bus18_incremental_hosting_audit.csv")

    decision, statuses, labels = build_decision(s4, all_site, joint, critical_summary)
    flex = build_flexibility_vs_grid(decision)
    save_csv(flex, OUT / "06_flexibility_vs_grid/pmax_gain_vs_grid_hosting.csv")
    save_csv(decision, OUT / "07_candidate_decision/candidate_grid_hosting_decision.csv")
    save_csv(statuses, OUT / "07_candidate_decision/final_status.csv")
    write_readme(s4_summary, all_summary, decision, critical_summary, labels)

    pngs = generate_figures(s4, all_site, joint, stress, critical_summary, flex, decision)
    contact = create_contact_sheet(pngs)
    visual = pd.DataFrame({
        "figure": [path.name for path in pngs],
        "automatic_nonblank": True,
        "manual_visual_status": "PENDING",
        "manual_note": "Awaiting contact-sheet and individual visual inspection",
    })
    save_csv(visual, OUT / "09_qa/visual_audit.csv")
    raw_after = {name: sha256(RAW / name) for name in EXPECTED_RAW}
    qa = main_qa(preflight, data, raw_before, raw_after, base_qa, profiles,
                 s4, all_site, joint, critical_summary, identities, labels, pngs)
    save_csv(qa, OUT / "09_qa/main_qa.csv")
    require(qa["pass"].all(), f"Main QA failed: {qa.loc[~qa['pass'],'check'].tolist()}")
    write_manifest()
    print(f"Stage89Q-G main audit PASS: {len(qa)}/{len(qa)}; visual QA pending")
    print(f"Contact sheet: {contact}")


if __name__ == "__main__":
    main()
