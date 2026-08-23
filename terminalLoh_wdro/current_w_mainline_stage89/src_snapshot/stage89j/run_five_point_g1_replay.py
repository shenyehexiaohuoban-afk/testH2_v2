from __future__ import annotations

import hashlib
import math
import subprocess
from collections import deque
from datetime import datetime
from pathlib import Path

import h5py
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from scipy.io import loadmat


ROOT = Path(__file__).resolve().parents[4]
OUT = Path(__file__).resolve().parent
PLOTS = OUT / "plots"
STAGE87 = ROOT / "results/task-002-stage2b-b3-smoke/87C-A-stage87b-formal-w-bank/run-001"
D01 = ROOT / "results/task-002-stage2b-b3-smoke/w-grid-outage-reconfiguration-diagnostic/run-003"
NEAR_MAT = ROOT / "data/yuanqi/near_stage_msp_input.mat"
WIND_CONFIG = ROOT / "terminalLoh_wdro/config/formal_b3_wind_modes.csv"
LOCATION_SUPPORT = ROOT / "terminalLoh_wdro/config/stage87b_candidate1/location_support_stage87b.csv"
LFW_SUPPORT = ROOT / "terminalLoh_wdro/config/stage87b_candidate1/lfw_support_stage87b.csv"
FORMAL_SOURCE = ROOT / "terminalLoh_wdro/current_w_mainline_stage88/src_snapshot/terminalLoh_wdro/src/generate_step04CA2_formal_consequences_h2.m"
MODEL_SOURCE = ROOT / "terminalLoh_wdro/current_w_mainline_stage88/src_snapshot/terminalLoh_wdro/src/build_w_dac_model_h2.m"
FRAGILITY_SOURCE = ROOT / "terminalLoh_wdro/current_w_mainline_stage88/src_snapshot/fa_h2/fuzhu/terminalLoh_windmc/compute_line_failure_prob_h2.m"

INTENSITIES = (3, 4, 5, 6)
VARIANTS = ("B0", "B1", "B2", "G1", "G2")
POINTS = ("W1", "M12", "W2", "M23", "W3")
OFFICIAL = np.array([0, 2, 4])
N_PER_STATE = 15000
N_LINES = 32
TOTAL_LOAD_KW = 3715.0
RMAX_KM = 40.0
DECAY_B = 0.6
DESIGN_WIND_MPS = 25.0
DF_KG_PER_KWH = 1.0 / (0.55 * 33.33)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def git_tracking(path: Path) -> str:
    rel = path.resolve().relative_to(ROOT.resolve()).as_posix()
    result = subprocess.run(
        ["git", "ls-files", "--error-unmatch", "--", rel],
        cwd=ROOT,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return "tracked" if result.returncode == 0 else "untracked"


def read_inputs():
    near = loadmat(NEAR_MAT, squeeze_me=True, struct_as_record=False)["NearStageInput"]
    edges = np.asarray(near.Grid.power_edges, dtype=int)
    branch_idx = np.atleast_1d(np.asarray(near.Grid.branch_indices, dtype=int)).ravel()
    loads = np.asarray(near.Grid.P_load_base_kw, dtype=float).ravel()
    raw_xy = np.asarray(near.Spatial.node_positions, dtype=float)
    x = -40.0 + (raw_xy[:, 0] - raw_xy[:, 0].min()) * 30.0 / np.ptp(raw_xy[:, 0])
    y = 10.0 + (raw_xy[:, 1] - raw_xy[:, 1].min()) * 25.0 / np.ptp(raw_xy[:, 1])
    if edges.shape != (37, 3) or not np.array_equal(branch_idx, np.arange(1, 33)):
        raise RuntimeError("IEEE33 topology gate failed")
    if len(loads) != 33 or not math.isclose(loads.sum(), TOTAL_LOAD_KW, abs_tol=1e-9):
        raise RuntimeError("IEEE33 load gate failed")
    if not np.all(edges[:32, 2] == 1) or not np.all(edges[32:, 2] == 0):
        raise RuntimeError("Expected 32 normally-closed and five normally-open lines")
    return near, edges, loads, x, y


def radial_path_masks(edges: np.ndarray) -> np.ndarray:
    adjacency: list[list[tuple[int, int]]] = [[] for _ in range(33)]
    for edge, (u1, v1, _) in enumerate(edges[:32]):
        u, v = int(u1 - 1), int(v1 - 1)
        adjacency[u].append((v, edge))
        adjacency[v].append((u, edge))
    parent = np.full(33, -1, dtype=int)
    parent_edge = np.full(33, -1, dtype=int)
    parent[0] = 0
    queue = deque([0])
    while queue:
        u = queue.popleft()
        for v, edge in adjacency[u]:
            if parent[v] >= 0:
                continue
            parent[v] = u
            parent_edge[v] = edge
            queue.append(v)
    if np.any(parent < 0):
        raise RuntimeError("Base feeder is disconnected")
    masks = np.zeros(33, dtype=np.uint64)
    for node in range(33):
        u = node
        while u:
            masks[node] |= np.uint64(1) << np.uint64(parent_edge[u])
            u = int(parent[u])
    return masks


def masks_from_failed(failed: np.ndarray) -> np.ndarray:
    powers = (np.uint64(1) << np.arange(32, dtype=np.uint64)).reshape(32, 1)
    return (failed.astype(np.uint64) @ powers).ravel()


def radial_loss(masks: np.ndarray, path_masks: np.ndarray, loads: np.ndarray) -> np.ndarray:
    loss = np.zeros(len(masks), dtype=float)
    for node in range(1, 33):
        loss += loads[node] * ((masks & path_masks[node]) != 0)
    return loss


def make_reconfiguration_solver(edges: np.ndarray):
    adjacency: list[list[tuple[int, int]]] = [[] for _ in range(33)]
    for edge, (u1, v1, status) in enumerate(edges):
        u, v = int(u1 - 1), int(v1 - 1)
        failed_bit = edge if status == 1 else -1
        adjacency[u].append((v, failed_bit))
        adjacency[v].append((u, failed_bit))
    cache: dict[int, int] = {}

    def solve(mask: int) -> int:
        if mask in cache:
            return cache[mask]
        seen = 1
        stack = [0]
        while stack:
            u = stack.pop()
            for v, failed_bit in adjacency[u]:
                bit = 1 << v
                if seen & bit:
                    continue
                if failed_bit >= 0 and mask & (1 << failed_bit):
                    continue
                seen |= bit
                stack.append(v)
        cache[mask] = seen
        return seen

    return solve, cache


def ideal_reconfiguration_loss(masks: np.ndarray, loads: np.ndarray, solve) -> np.ndarray:
    unique, inverse = np.unique(masks, return_inverse=True)
    reachable_unique = np.fromiter(
        (solve(int(mask)) for mask in unique), dtype=np.uint64, count=len(unique)
    )
    reachable = reachable_unique[inverse]
    supplied = np.zeros(len(masks), dtype=float)
    for node in range(33):
        supplied += loads[node] * ((reachable >> np.uint64(node)) & np.uint64(1))
    return loads.sum() - supplied


def point_to_segment_distance(
    px: np.ndarray, py: np.ndarray, x1: np.ndarray, y1: np.ndarray,
    x2: np.ndarray, y2: np.ndarray,
) -> np.ndarray:
    dx, dy = x2 - x1, y2 - y1
    denominator = dx * dx + dy * dy
    t = np.clip(
        ((px[:, None] - x1) * dx + (py[:, None] - y1) * dy) / denominator,
        0.0,
        1.0,
    )
    return np.hypot(px[:, None] - (x1 + t * dx), py[:, None] - (y1 + t * dy))


def local_wind(
    center_x: np.ndarray, center_y: np.ndarray, vmax: np.ndarray,
    x1: np.ndarray, y1: np.ndarray, x2: np.ndarray, y2: np.ndarray,
) -> np.ndarray:
    distance = point_to_segment_distance(center_x, center_y, x1, y1, x2, y2)
    factor = np.where(
        distance <= RMAX_KM,
        distance / RMAX_KM,
        (RMAX_KM / np.maximum(distance, np.finfo(float).eps)) ** DECAY_B,
    )
    return factor * vmax[:, None]


def fragility(wind_mps: np.ndarray) -> np.ndarray:
    probability = np.zeros_like(wind_mps, dtype=float)
    middle = (wind_mps > DESIGN_WIND_MPS) & (wind_mps < 2 * DESIGN_WIND_MPS)
    probability[middle] = (
        np.exp(0.6931 * (wind_mps[middle] - DESIGN_WIND_MPS) / DESIGN_WIND_MPS) - 1.0
    )
    probability[wind_mps >= 2 * DESIGN_WIND_MPS] = 1.0
    return np.clip(probability, 0.0, 1.0)


def replay_line_thresholds(seed: int, stream_position: np.ndarray) -> np.ndarray:
    # MATLAB rng(seed,'twister'); randperm(15000); rand(15000,32).
    # randperm(15000) consumes exactly 15000 MT19937 uniforms here. MATLAB
    # rand fills column-major, hence numpy's (32,15000).T construction.
    rng = np.random.RandomState(seed)
    rng.random_sample(N_PER_STATE)
    all_u = rng.random_sample((N_LINES, N_PER_STATE)).T
    return all_u[stream_position.astype(int) - 1]


def load_state(state_id: int):
    nominal_path = STAGE87 / "checkpoints" / f"state-{state_id:03d}_nominal.csv"
    mat_path = STAGE87 / "checkpoints" / f"state-{state_id:03d}_DAC.mat"
    columns = [
        "path_id", "joint_stream_position", "wind_seed", "resistance_seed",
        "a_W1", "loc_W1", "lfw_W1", "center_x_W1", "center_y_W1",
        "a_W2", "loc_W2", "lfw_W2", "center_x_W2", "center_y_W2",
        "a_W3", "loc_W3", "lfw_W3", "center_x_W3", "center_y_W3",
        "wind_W1_mps", "wind_W2_mps", "wind_W3_mps",
    ]
    nominal = pd.read_csv(nominal_path, usecols=columns)
    with h5py.File(mat_path, "r") as handle:
        failed = np.asarray(handle["failed_line"], dtype=np.uint8).transpose(2, 1, 0).astype(bool)
        wind = np.asarray(handle["wind_mps"], dtype=float).T
        wind_q = np.asarray(handle["wind_q"], dtype=float).T
        path_id = np.asarray(handle["path_id"], dtype=np.uint32).ravel()
    expected_id = np.arange(1, N_PER_STATE + 1, dtype=np.uint32)
    if len(nominal) != N_PER_STATE or not np.array_equal(path_id, expected_id):
        raise RuntimeError(f"State {state_id} path identity failed")
    return nominal_path, mat_path, nominal, failed, wind, wind_q


def point_probabilities(
    nominal: pd.DataFrame, shifts: np.ndarray,
    x1: np.ndarray, y1: np.ndarray, x2: np.ndarray, y2: np.ndarray,
) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    endpoint_x = nominal[["center_x_W1", "center_x_W2", "center_x_W3"]].to_numpy(float)
    endpoint_y = nominal[["center_y_W1", "center_y_W2", "center_y_W3"]].to_numpy(float)
    endpoint_v = nominal[["wind_W1_mps", "wind_W2_mps", "wind_W3_mps"]].to_numpy(float)
    point_x = np.column_stack(
        [endpoint_x[:, 0], 0.5 * (endpoint_x[:, 0] + endpoint_x[:, 1]), endpoint_x[:, 1],
         0.5 * (endpoint_x[:, 1] + endpoint_x[:, 2]), endpoint_x[:, 2]]
    )
    point_y = np.column_stack(
        [endpoint_y[:, 0], 0.5 * (endpoint_y[:, 0] + endpoint_y[:, 1]), endpoint_y[:, 1],
         0.5 * (endpoint_y[:, 1] + endpoint_y[:, 2]), endpoint_y[:, 2]]
    )
    point_v = np.column_stack(
        [endpoint_v[:, 0], 0.5 * (endpoint_v[:, 0] + endpoint_v[:, 1]), endpoint_v[:, 1],
         0.5 * (endpoint_v[:, 1] + endpoint_v[:, 2]), endpoint_v[:, 2]]
    )
    probability = np.empty((N_PER_STATE, 5, N_LINES), dtype=float)
    wind = np.empty_like(probability)
    for point in range(5):
        wind[:, point, :] = local_wind(
            point_x[:, point], point_y[:, point], point_v[:, point], x1, y1, x2, y2
        )
        probability[:, point, :] = fragility(wind[:, point, :] - shifts[None, :])
    return probability, wind, point_x, point_y


def cumulative_failure(uniform: np.ndarray, probability: np.ndarray) -> np.ndarray:
    return uniform[:, None, :] <= np.maximum.accumulate(probability, axis=1)


def metric_row(
    intensity: int, loc: int | str, variant: str,
    failed_official: np.ndarray, loss_official: np.ndarray,
) -> dict[str, float | int | str]:
    failed_count = failed_official.sum(axis=2).ravel()
    loss_pct = (100.0 * loss_official / TOTAL_LOAD_KW).ravel()
    d_total = loss_official.sum(axis=1) * DF_KG_PER_KWH
    full = loss_official.ravel() >= TOTAL_LOAD_KW - 1e-9
    return {
        "intensity": intensity,
        "loc": loc,
        "variant": variant,
        "trajectory_count": failed_official.shape[0],
        "official_slice_observation_count": failed_official.shape[0] * 3,
        "mean_failed_line_count": float(failed_count.mean()),
        "q95_failed_line_count": float(np.quantile(failed_count, 0.95)),
        "mean_lost_load_pct": float(loss_pct.mean()),
        "q95_lost_load_pct": float(np.quantile(loss_pct, 0.95)),
        "q99_lost_load_pct": float(np.quantile(loss_pct, 0.99)),
        "prob_loss_gt_50pct": float(np.mean(loss_pct > 50.0)),
        "prob_loss_gt_75pct": float(np.mean(loss_pct > 75.0)),
        "prob_loss_gt_90pct": float(np.mean(loss_pct > 90.0)),
        "prob_loss_ge_99pct": float(np.mean(loss_pct >= 99.0)),
        "prob_full_blackout": float(np.mean(full)),
        "mean_D_kg": float(d_total.mean()),
        "q95_D_kg": float(np.quantile(d_total, 0.95)),
        "q99_D_kg": float(np.quantile(d_total, 0.99)),
        "max_D_kg": float(d_total.max()),
        "D_time_horizon_h": 3.0,
        "midpoint_direct_duration_h": 0.0,
    }


def paired_reduction(base: pd.Series, candidate: pd.Series) -> dict[str, float]:
    output: dict[str, float] = {}
    for metric in ("mean_D_kg", "q95_D_kg", "q99_D_kg"):
        output[f"{metric}_reduction_pct"] = (
            100.0 * (float(base[metric]) - float(candidate[metric])) / float(base[metric])
            if float(base[metric]) > 0 else 0.0
        )
    output["full_blackout_probability_reduction_abs"] = float(
        base.prob_full_blackout - candidate.prob_full_blackout
    )
    output["full_blackout_probability_reduction_relative_pct"] = (
        100.0 * output["full_blackout_probability_reduction_abs"] / float(base.prob_full_blackout)
        if float(base.prob_full_blackout) > 0 else 0.0
    )
    return output


def value_level(reduction: dict[str, float]) -> str:
    high = (
        reduction["q95_D_kg_reduction_pct"] >= 20.0
        or reduction["q99_D_kg_reduction_pct"] >= 20.0
        or reduction["full_blackout_probability_reduction_abs"] >= 0.05
    )
    moderate = (
        reduction["q95_D_kg_reduction_pct"] >= 5.0
        or reduction["q99_D_kg_reduction_pct"] >= 5.0
        or reduction["full_blackout_probability_reduction_abs"] >= 0.01
    )
    return "HIGH" if high else "MODERATE" if moderate else "LOW"


def make_plots(metrics: pd.DataFrame, critical: pd.DataFrame) -> None:
    PLOTS.mkdir(parents=True, exist_ok=True)
    colors = {"B0": "#666666", "B1": "#3b82f6", "B2": "#f59e0b", "G1": "#10b981", "G2": "#8b5cf6"}
    x = np.arange(len(INTENSITIES))
    width = 0.16

    fig, ax = plt.subplots(figsize=(9.4, 5.2))
    for index, variant in enumerate(VARIANTS):
        rows = metrics[metrics.variant == variant].set_index("intensity").loc[list(INTENSITIES)]
        ax.bar(x + (index - 2) * width, rows.mean_lost_load_pct, width, label=variant, color=colors[variant])
    ax.set_xticks(x); ax.set_xticklabels([f"a{a}" for a in INTENSITIES]); ax.set_ylabel("Mean lost load (%)")
    ax.set_title("Mean lost load: exposure, reconfiguration, and hardening")
    ax.legend(ncol=5); ax.grid(axis="y", alpha=0.25); fig.tight_layout()
    fig.savefig(PLOTS / "01_mean_lost_load_by_intensity.png", dpi=180); plt.close(fig)

    fig, axes = plt.subplots(1, 2, figsize=(12, 4.8), sharey=True)
    for axis, metric, label in zip(axes, ["q95_lost_load_pct", "q99_lost_load_pct"], ["q95", "q99"]):
        for variant in VARIANTS:
            rows = metrics[metrics.variant == variant].set_index("intensity").loc[list(INTENSITIES)]
            axis.plot(x, rows[metric], marker="o", label=variant, color=colors[variant])
        axis.set_xticks(x); axis.set_xticklabels([f"a{a}" for a in INTENSITIES]); axis.set_title(f"{label} lost load")
        axis.set_ylabel("Lost load (%)"); axis.grid(alpha=0.25)
    axes[1].legend(ncol=2); fig.tight_layout()
    fig.savefig(PLOTS / "02_q95_q99_lost_load_by_intensity.png", dpi=180); plt.close(fig)

    fig, ax = plt.subplots(figsize=(9.2, 5.0))
    for variant in VARIANTS:
        rows = metrics[metrics.variant == variant].set_index("intensity").loc[list(INTENSITIES)]
        ax.plot(x, 100 * rows.prob_full_blackout, marker="o", label=variant, color=colors[variant])
    ax.set_xticks(x); ax.set_xticklabels([f"a{a}" for a in INTENSITIES]); ax.set_ylabel("Full blackout probability (%)")
    ax.set_title("Full-blackout tail by intensity"); ax.legend(ncol=5); ax.grid(alpha=0.25)
    fig.tight_layout(); fig.savefig(PLOTS / "03_full_blackout_probability.png", dpi=180); plt.close(fig)

    tail = metrics[metrics.intensity.isin([5, 6])]
    fig, axes = plt.subplots(1, 2, figsize=(12, 4.8), sharey=True)
    for axis, intensity in zip(axes, [5, 6]):
        rows = tail[tail.intensity == intensity].set_index("variant").loc[list(VARIANTS)]
        xx = np.arange(len(VARIANTS)); axis.bar(xx - 0.18, rows.q95_D_kg, 0.36, label="q95 D")
        axis.bar(xx + 0.18, rows.q99_D_kg, 0.36, label="q99 D")
        axis.set_xticks(xx); axis.set_xticklabels(VARIANTS); axis.set_title(f"a{intensity} D tail"); axis.grid(axis="y", alpha=0.25)
    axes[0].set_ylabel("D (kg), official 3 h"); axes[1].legend(); fig.tight_layout()
    fig.savefig(PLOTS / "04_a5_a6_D_tail.png", dpi=180); plt.close(fig)

    crit = critical[(critical.intensity.isin([5, 6])) & (critical.line_id.isin([1, 2]))]
    fig, axes = plt.subplots(1, 2, figsize=(12, 4.8), sharey=True)
    for axis, line_id in zip(axes, [1, 2]):
        part = crit[crit.line_id == line_id]
        for variant in ("B2", "G1", "G2"):
            rows = part[part.variant == variant].set_index("intensity").loc[[5, 6]]
            axis.plot([5, 6], 100 * rows.final_failure_probability, marker="o", label=variant)
        axis.set_xticks([5, 6]); axis.set_xticklabels(["a5", "a6"]); axis.set_title(f"Line {line_id}: final failure")
        axis.set_ylabel("Probability (%)"); axis.grid(alpha=0.25)
    axes[1].legend(); fig.tight_layout()
    fig.savefig(PLOTS / "05_critical_line_failure_probability.png", dpi=180); plt.close(fig)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    near, edges, loads, node_x, node_y = read_inputs()
    path_masks = radial_path_masks(edges)
    solve_reconfiguration, recon_cache = make_reconfiguration_solver(edges)
    base_edges = edges[:32, :2] - 1
    x1, y1 = node_x[base_edges[:, 0]], node_y[base_edges[:, 0]]
    x2, y2 = node_x[base_edges[:, 1]], node_y[base_edges[:, 1]]
    shifts = {
        "B2": np.zeros(N_LINES),
        "G1": np.array([10.0, 10.0] + [0.0] * 30),
        "G2": np.array([10.0, 10.0, 5.0, 5.0, 5.0] + [0.0] * 27),
    }

    state_metric_rows: list[dict] = []
    intensity_metric_rows: list[dict] = []
    endpoint_audit_rows: list[dict] = []
    sample_rows: list[dict] = []
    critical_rows: list[dict] = []
    incremental_rows: list[dict] = []
    manifest_paths: dict[Path, str] = {
        NEAR_MAT: "IEEE33 topology, load, spatial coordinates, H2 conversion",
        WIND_CONFIG: "actual Vmax triangular distribution definition",
        LOCATION_SUPPORT: "Stage87B x-coordinate support",
        LFW_SUPPORT: "Stage87B y-coordinate support",
        FORMAL_SOURCE: "frozen failure sampling and persistence semantics",
        MODEL_SOURCE: "wind geometry and D conversion semantics",
        FRAGILITY_SOURCE: "current grid line fragility function",
        D01 / "README.md": "accepted D01 baseline diagnostic",
        D01 / "reconfiguration_effect_by_intensity.csv": "accepted B0/B1 comparison target",
        Path(__file__): "this deterministic paired postprocessor",
    }

    for intensity in INTENSITIES:
        combined_failed: dict[str, list[np.ndarray]] = {variant: [] for variant in VARIANTS}
        combined_loss: dict[str, list[np.ndarray]] = {variant: [] for variant in VARIANTS}
        critical_acc = {
            (variant, line): {"failed_final": 0, "obs": 0, "full": 0, "joint": 0, "attrib": 0}
            for variant in ("B2", "G1", "G2") for line in range(1, 6)
        }
        incremental_acc = {
            line: {"m12": 0, "m23": 0, "w2": 0, "w3": 0, "den": 0}
            for line in range(1, N_LINES + 1)
        }

        for loc in range(1, 8):
            state_id = (intensity - 2) * 7 + loc
            nominal_path, mat_path, nominal, saved_failed, saved_wind, wind_q = load_state(state_id)
            manifest_paths[nominal_path] = "frozen path identity, centers, Vmax, seeds, positions"
            manifest_paths[mat_path] = "frozen exact failure and D realization"
            stream_position = nominal.joint_stream_position.to_numpy(int)
            uniform = replay_line_thresholds(int(nominal.resistance_seed.iloc[0]), stream_position)
            probabilities = {}
            failure5 = {}
            point_meta = None
            for variant in ("B2", "G1", "G2"):
                p, point_wind, point_x, point_y = point_probabilities(
                    nominal, shifts[variant], x1, y1, x2, y2
                )
                probabilities[variant] = p
                failure5[variant] = cumulative_failure(uniform, p)
                point_meta = (point_wind, point_x, point_y)

            replay3 = cumulative_failure(uniform, probabilities["B2"][:, OFFICIAL, :])
            mismatch = int(np.count_nonzero(replay3 ^ saved_failed))
            endpoint_csv_wind = nominal[["wind_W1_mps", "wind_W2_mps", "wind_W3_mps"]].to_numpy(float)
            endpoint_diff = float(np.max(np.abs(endpoint_csv_wind - saved_wind)))
            if mismatch != 0 or endpoint_diff > 1e-12:
                raise RuntimeError(
                    f"State {state_id} replay gate failed: {mismatch=}, {endpoint_diff=}"
                )
            endpoint_audit_rows.append({
                "initial_state_id": state_id,
                "intensity": intensity,
                "loc": loc,
                "trajectory_count": N_PER_STATE,
                "actual_endpoint_vmax_available": "YES",
                "vmax_source": str(mat_path.relative_to(ROOT)) + "::wind_mps",
                "vmax_semantics": "actual sampled triangular Vmax used by formal consequence source",
                "mat_vs_nominal_csv_max_abs_diff_mps": endpoint_diff,
                "wind_q_available": "YES",
                "wind_q_min": float(wind_q.min()),
                "wind_q_max": float(wind_q.max()),
                "failure_replay_bit_mismatch_count": mismatch,
                "replay_pass": "YES",
            })
            sample_rows.append({
                "initial_state_id": state_id,
                "intensity": intensity,
                "loc": loc,
                "path_id_start": 1,
                "path_id_end": N_PER_STATE,
                "trajectory_count": N_PER_STATE,
                "selection_rule": "ALL_FROZEN_PATH_IDS_1_TO_15000",
                "result_based_selection": "NO",
                "paired_hurricane_realization": "YES",
                "paired_line_resistance_uniform": "YES",
            })

            failed_variants = {
                "B0": saved_failed,
                "B1": saved_failed,
                "B2": failure5["B2"][:, OFFICIAL, :],
                "G1": failure5["G1"][:, OFFICIAL, :],
                "G2": failure5["G2"][:, OFFICIAL, :],
            }
            loss_variants: dict[str, np.ndarray] = {}
            for variant in VARIANTS:
                masks = masks_from_failed(failed_variants[variant].reshape(-1, N_LINES))
                if variant == "B0":
                    loss = radial_loss(masks, path_masks, loads)
                else:
                    loss = ideal_reconfiguration_loss(masks, loads, solve_reconfiguration)
                loss_variants[variant] = loss.reshape(N_PER_STATE, 3)
                state_metric_rows.append(
                    metric_row(intensity, loc, variant, failed_variants[variant], loss_variants[variant])
                )
                combined_failed[variant].append(failed_variants[variant])
                combined_loss[variant].append(loss_variants[variant])

            p_base = probabilities["B2"]
            f5_base = failure5["B2"]
            cross_m12 = (uniform <= p_base[:, 1, :]) & (
                uniform > np.maximum(p_base[:, 0, :], p_base[:, 2, :])
            )
            prior_m23 = np.maximum.reduce([p_base[:, 0, :], p_base[:, 1, :], p_base[:, 2, :]])
            cross_m23 = (uniform <= p_base[:, 3, :]) & (
                uniform > np.maximum(prior_m23, p_base[:, 4, :])
            )
            inc_w2 = f5_base[:, 2, :] & ~saved_failed[:, 1, :]
            inc_w3 = f5_base[:, 4, :] & ~saved_failed[:, 2, :]
            for line in range(1, N_LINES + 1):
                acc = incremental_acc[line]
                acc["m12"] += int(cross_m12[:, line - 1].sum())
                acc["m23"] += int(cross_m23[:, line - 1].sum())
                acc["w2"] += int(inc_w2[:, line - 1].sum())
                acc["w3"] += int(inc_w3[:, line - 1].sum())
                acc["den"] += N_PER_STATE

            for variant in ("B2", "G1", "G2"):
                failed_official = failed_variants[variant]
                loss_official = loss_variants[variant]
                flat_masks = masks_from_failed(failed_official.reshape(-1, N_LINES))
                full = loss_official.ravel() >= TOTAL_LOAD_KW - 1e-9
                for line in range(1, 6):
                    acc = critical_acc[(variant, line)]
                    line_failed = failed_official[:, :, line - 1].ravel()
                    forced_masks = flat_masks & ~(np.uint64(1) << np.uint64(line - 1))
                    forced_loss = ideal_reconfiguration_loss(forced_masks, loads, solve_reconfiguration)
                    attributable = full & (forced_loss < TOTAL_LOAD_KW - 1e-9)
                    acc["failed_final"] += int(failed_official[:, 2, line - 1].sum())
                    acc["obs"] += N_PER_STATE * 3
                    acc["full"] += int(full.sum())
                    acc["joint"] += int((full & line_failed).sum())
                    acc["attrib"] += int(attributable.sum())

        for variant in VARIANTS:
            failed_all = np.concatenate(combined_failed[variant], axis=0)
            loss_all = np.concatenate(combined_loss[variant], axis=0)
            intensity_metric_rows.append(metric_row(intensity, "ALL", variant, failed_all, loss_all))

        for (variant, line), acc in critical_acc.items():
            critical_rows.append({
                "intensity": intensity,
                "variant": variant,
                "line_id": line,
                "from_bus": int(edges[line - 1, 0]),
                "to_bus": int(edges[line - 1, 1]),
                "final_failure_probability": acc["failed_final"] / (7 * N_PER_STATE),
                "full_blackout_observation_probability": acc["full"] / acc["obs"],
                "joint_line_failed_and_full_blackout_probability": acc["joint"] / acc["obs"],
                "prob_line_failed_given_full_blackout": acc["joint"] / acc["full"] if acc["full"] else 0.0,
                "full_blackout_attributable_count": acc["attrib"],
                "full_blackout_attributable_probability": acc["attrib"] / acc["obs"],
                "share_of_full_blackout_attributable_to_line": acc["attrib"] / acc["full"] if acc["full"] else 0.0,
                "attribution_definition": "full under variant; not full when this line alone is forced surviving",
            })
        for line, acc in incremental_acc.items():
            incremental_rows.append({
                "intensity": intensity,
                "line_id": line,
                "from_bus": int(edges[line - 1, 0]),
                "to_bus": int(edges[line - 1, 1]),
                "trajectory_count": acc["den"],
                "net_new_threshold_crossing_M12_count": acc["m12"],
                "net_new_threshold_crossing_M12_probability": acc["m12"] / acc["den"],
                "net_new_threshold_crossing_M23_count": acc["m23"],
                "net_new_threshold_crossing_M23_probability": acc["m23"] / acc["den"],
                "incremental_failed_at_official_W2_count": acc["w2"],
                "incremental_failed_at_official_W2_probability": acc["w2"] / acc["den"],
                "incremental_failed_at_official_W3_count": acc["w3"],
                "incremental_failed_at_official_W3_probability": acc["w3"] / acc["den"],
            })

    state_metrics = pd.DataFrame(state_metric_rows)
    metrics = pd.DataFrame(intensity_metric_rows)
    critical = pd.DataFrame(critical_rows)
    incremental = pd.DataFrame(incremental_rows)
    endpoint_audit = pd.DataFrame(endpoint_audit_rows)
    sample_manifest = pd.DataFrame(sample_rows)

    state_metrics.to_csv(OUT / "scenario_variant_metrics.csv", index=False)
    metrics.to_csv(OUT / "metrics_by_intensity_variant.csv", index=False)
    critical.to_csv(OUT / "critical_line_tail_effect.csv", index=False)
    incremental.to_csv(OUT / "fivepoint_incremental_failure.csv", index=False)
    endpoint_audit.to_csv(OUT / "endpoint_vmax_availability_audit.csv", index=False)
    sample_manifest.to_csv(OUT / "preview_sample_manifest.csv", index=False)

    hardening = pd.DataFrame([
        {"variant": "G0/B2", "line": "all", "shift_mps": 0.0, "level": "none", "meaning": "five-point ideal-reconfiguration baseline"},
        {"variant": "G1", "line": "1-2", "shift_mps": 10.0, "level": "strong", "meaning": "MECHANISM_SENSITIVITY_LEVEL"},
        {"variant": "G1", "line": "2-3", "shift_mps": 10.0, "level": "strong", "meaning": "MECHANISM_SENSITIVITY_LEVEL"},
        {"variant": "G2", "line": "1-2", "shift_mps": 10.0, "level": "strong", "meaning": "MECHANISM_SENSITIVITY_LEVEL"},
        {"variant": "G2", "line": "2-3", "shift_mps": 10.0, "level": "strong", "meaning": "MECHANISM_SENSITIVITY_LEVEL"},
        {"variant": "G2", "line": "3-4", "shift_mps": 5.0, "level": "moderate", "meaning": "MECHANISM_SENSITIVITY_LEVEL"},
        {"variant": "G2", "line": "4-5", "shift_mps": 5.0, "level": "moderate", "meaning": "MECHANISM_SENSITIVITY_LEVEL"},
        {"variant": "G2", "line": "5-6", "shift_mps": 5.0, "level": "moderate", "meaning": "MECHANISM_SENSITIVITY_LEVEL"},
    ])
    hardening["implementation"] = "F_H(v)=F(v-shift_mps), same frozen line resistance u"
    hardening["engineering_design_claim"] = "NO"
    hardening.to_csv(OUT / "hardening_definition.csv", index=False)

    ties = []
    for index, (u, v, status) in enumerate(edges[32:], start=33):
        ties.append({
            "tie_line": f"{int(u)}-{int(v)}",
            "source": "data/yuanqi/near_stage_msp_input.mat::NearStageInput.Grid.power_edges",
            "source_edge_id": index,
            "status_in_base_case": "normally_open" if int(status) == 0 else "closed",
            "included_in_branch_indices": "NO",
            "ideal_tie_line_availability": "YES",
            "tie_line_failure_modeled": "NO",
            "confirmed": "YES",
        })
    pd.DataFrame(ties).to_csv(OUT / "tie_line_source_audit.csv", index=False)

    comparison_rows = []
    levels: dict[tuple[str, int], str] = {}
    for intensity in (5, 6):
        indexed = metrics[metrics.intensity == intensity].set_index("variant")
        for label, base_name, candidate_name in (("G1_vs_B2", "B2", "G1"), ("G2_vs_G1", "G1", "G2")):
            reduction = paired_reduction(indexed.loc[base_name], indexed.loc[candidate_name])
            level = value_level(reduction)
            levels[(label, intensity)] = level
            comparison_rows.append({
                "comparison": label,
                "intensity": intensity,
                **reduction,
                "value_level": level,
            })
    comparisons = pd.DataFrame(comparison_rows)
    comparisons.to_csv(OUT / "hardening_tail_comparison.csv", index=False)

    overall_g1 = min((levels[("G1_vs_B2", a)] for a in (5, 6)), key=("LOW", "MODERATE", "HIGH").index)
    overall_g2 = min((levels[("G2_vs_G1", a)] for a in (5, 6)), key=("LOW", "MODERATE", "HIGH").index)
    make_plots(metrics, critical)

    audit_text = f"""# Failure sampling semantics audit

## Mechanical source result

`CURRENT_FAILURE_SAMPLING = PERSISTENT_FIXED_RESISTANCE_THRESHOLD`

For each trajectory, the formal source creates one `lineDraw[32]` vector after the state-specific resistance seed/permutation stream. The same per-line uniform is compared with each slice probability. Failure is updated as `failed(t)=failed(t-1) OR lineDraw<=F(v_t)`. It is therefore not an independent Bernoulli draw at each slice and not a separately sampled failure time; it is a shared frozen resistance threshold with persistent state.

The grid fragility is `F(v)=0` for `v<=25`, `exp(0.6931*(v-25)/25)-1` for `25<v<50`, and `1` for `v>=50` m/s. Current hardening is implemented only for this preview as the requested horizontal sensitivity `F_H(v)=F(v-DeltaV)` using the identical `lineDraw`.

The MAT checkpoint does not store `line_resistance_u`, but `state-xxx_nominal.csv` stores `resistance_seed` and `joint_stream_position`. Replaying MATLAB's MT19937 stream, including the exact 15000-uniform `randperm` consumption and column-major `rand(15000,32)`, reproduced all {sum(row['trajectory_count'] for row in endpoint_audit_rows):,} trajectories × 3 slices × 32 lines with **{int(endpoint_audit.failure_replay_bit_mismatch_count.sum())} mismatched bits**.

`FROZEN_RANDOMNESS_REUSABLE_FOR_5POINT = YES`

## Vmax and midpoint gate

`ACTUAL_ENDPOINT_VMAX_AVAILABLE = YES`

`wind_mps[trajectory,W1:W3]` is assigned directly from the stagewise triangular inverse-CDF draw and is then multiplied by the spatial wind factor. It is actual sampled endpoint Vmax, not category midpoint/mean. MAT-vs-CSV maximum difference is {endpoint_audit.mat_vs_nominal_csv_max_abs_diff_mps.max():.3g} m/s. M12/M23 use coordinate midpoints and arithmetic interpolation of these frozen endpoint Vmax values; each asset's local wind is recomputed from the midpoint center and current radial model.

## Time and road scope

M12/M23 are hazard-update points only. They receive zero direct duration; D remains the sum of W1/W2/W3 official 1 h slices, so `sum(delta_t)=3 h`. A midpoint crossing persists into the next official slice. Roads remain at the existing three-point Stage88 state because this first pass is `GRID_ONLY_5POINT_PREVIEW`.
"""
    (OUT / "failure_sampling_semantics_audit.md").write_text(audit_text, encoding="utf-8")

    table = metrics.set_index(["intensity", "variant"])
    b1a5, b2a5 = table.loc[(5, "B1")], table.loc[(5, "B2")]
    b1a6, b2a6 = table.loc[(6, "B1")], table.loc[(6, "B2")]
    g1a5, g1a6 = table.loc[(5, "G1")], table.loc[(6, "G1")]
    g2a5, g2a6 = table.loc[(5, "G2")], table.loc[(6, "G2")]
    g1r5 = paired_reduction(b2a5, g1a5); g1r6 = paired_reduction(b2a6, g1a6)
    g2r5 = paired_reduction(g1a5, g2a5); g2r6 = paired_reduction(g1a6, g2a6)
    readme = f"""# Five-point hazard exposure + IEEE33 reconfiguration + targeted hardening preview

Task type: `METHOD_PREVIEW / DIAGNOSTIC_ONLY`. The current W mainline is unchanged. This run performs a full vectorized post-process of the frozen a3-a6 bank: 28 initial states × 15000 trajectories = 420000 paired trajectories. It does not regenerate the 525000-path W bank.

## Gate result and scope

- Fixed line-resistance randomness was exactly replayed: total failure-bit mismatches = 0.
- Actual sampled endpoint Vmax is available and used. Midpoint local wind is recomputed from midpoint center + midpoint Vmax + asset geometry.
- Five tie lines are mechanically read from the project MAT and assumed always available: 8-21, 9-15, 12-22, 18-33, 25-29.
- Reconfiguration is the D01 connectivity-only radial-spanning-tree upper bound. No AC/DistFlow, voltage, thermal, switching time/cost, repairs, DER or tie fragility is introduced.
- This is `GRID_ONLY_5POINT_PREVIEW`: roads remain on the formal three-point state.
- M12/M23 have zero direct duration. D is still evaluated on W1/W2/W3 with 1 h each (`3 h` total).

## Mechanisms kept separate

1. Mechanism A — denser five-point exposure: B2 vs B1 reveals midpoint threshold crossings and can increase persistent outage.
2. Mechanism B — ideal tie-line reconfiguration: B1 vs B0 restores source connectivity and lowers outage under an upper-bound assumption.
3. Mechanism C — targeted fragility hardening: G1/G2 vs B2 lower critical upstream failure probabilities using paired frozen thresholds.

## Key a5/a6 results

| Comparison | intensity | mean D change | q95 D change | q99 D change | full blackout change |
|---|---:|---:|---:|---:|---:|
| B2 vs B1 | a5 | {(b2a5.mean_D_kg/b1a5.mean_D_kg-1)*100:.3f}% | {(b2a5.q95_D_kg/b1a5.q95_D_kg-1)*100:.3f}% | {(b2a5.q99_D_kg/b1a5.q99_D_kg-1)*100:.3f}% | {(b2a5.prob_full_blackout-b1a5.prob_full_blackout)*100:.3f} pp |
| B2 vs B1 | a6 | {(b2a6.mean_D_kg/b1a6.mean_D_kg-1)*100:.3f}% | {(b2a6.q95_D_kg/b1a6.q95_D_kg-1)*100:.3f}% | {(b2a6.q99_D_kg/b1a6.q99_D_kg-1)*100:.3f}% | {(b2a6.prob_full_blackout-b1a6.prob_full_blackout)*100:.3f} pp |
| G1 vs B2 reduction | a5 | {g1r5['mean_D_kg_reduction_pct']:.3f}% | {g1r5['q95_D_kg_reduction_pct']:.3f}% | {g1r5['q99_D_kg_reduction_pct']:.3f}% | {g1r5['full_blackout_probability_reduction_abs']*100:.3f} pp |
| G1 vs B2 reduction | a6 | {g1r6['mean_D_kg_reduction_pct']:.3f}% | {g1r6['q95_D_kg_reduction_pct']:.3f}% | {g1r6['q99_D_kg_reduction_pct']:.3f}% | {g1r6['full_blackout_probability_reduction_abs']*100:.3f} pp |
| G2 vs G1 reduction | a5 | {g2r5['mean_D_kg_reduction_pct']:.3f}% | {g2r5['q95_D_kg_reduction_pct']:.3f}% | {g2r5['q99_D_kg_reduction_pct']:.3f}% | {g2r5['full_blackout_probability_reduction_abs']*100:.3f} pp |
| G2 vs G1 reduction | a6 | {g2r6['mean_D_kg_reduction_pct']:.3f}% | {g2r6['q95_D_kg_reduction_pct']:.3f}% | {g2r6['q99_D_kg_reduction_pct']:.3f}% | {g2r6['full_blackout_probability_reduction_abs']*100:.3f} pp |

Value rule (declared mechanically in `run_preview.py`): for each intensity, `HIGH` if q95 or q99 D reduction is at least 20%, or absolute full-blackout reduction is at least 5 percentage points; `MODERATE` if the corresponding thresholds are 5% or 1 point; otherwise `LOW`. Overall value is the lower of a5/a6 to avoid overclaiming.

`STRONG_HARDENING_1_2_2_3_VALUE = {overall_g1}`

`ADDITIONAL_MODERATE_HARDENING_3_4_4_5_5_6_VALUE = {overall_g2}`

## Interpretation boundary

The +10/+5 m/s shifts are mechanism sensitivity levels, not claims about any physical retrofit's guaranteed resistance improvement. No D/A/C regrouping, SAA, DRO, TerminalLOH or FA-MSP calculation is included. The result only answers whether a formal W upgrade is physically promising.

## Output map

- `failure_sampling_semantics_audit.md`: exact sampling, replay, Vmax and time gates.
- `scenario_variant_metrics.csv`: 28 initial-state × 5 variant metrics.
- `metrics_by_intensity_variant.csv`: requested a3-a6 aggregate metrics.
- `critical_line_tail_effect.csv`: line 1-2 through 5-6 tail attribution, including counterfactual full-blackout attribution.
- `fivepoint_incremental_failure.csv`: line-specific midpoint crossings and W2/W3 increments.
- `hardening_tail_comparison.csv`: a5/a6 G1 and G2 paired reductions and value labels.
- `source_manifest.csv`: byte/hash identity of every input actually read.
"""
    (OUT / "README.md").write_text(readme, encoding="utf-8")

    manifest_rows = []
    for path, role in sorted(manifest_paths.items(), key=lambda item: str(item[0])):
        stat = path.stat()
        manifest_rows.append({
            "path": str(path.resolve()),
            "size": stat.st_size,
            "mtime": datetime.fromtimestamp(stat.st_mtime).astimezone().isoformat(),
            "sha256": sha256_file(path),
            "role": role,
            "tracked_untracked": git_tracking(path),
        })
    pd.DataFrame(manifest_rows).to_csv(OUT / "source_manifest.csv", index=False)

    qa = pd.DataFrame([
        {"check": "failure_replay_all_28_states", "status": "PASS", "value": int(endpoint_audit.failure_replay_bit_mismatch_count.sum()), "requirement": "0 mismatched bits"},
        {"check": "endpoint_vmax_mat_csv_identity", "status": "PASS", "value": endpoint_audit.mat_vs_nominal_csv_max_abs_diff_mps.max(), "requirement": "<=1e-12 m/s CSV serialization tolerance"},
        {"check": "trajectory_count", "status": "PASS", "value": int(sample_manifest.trajectory_count.sum()), "requirement": "420000 a3-a6 frozen trajectories"},
        {"check": "tie_line_count", "status": "PASS", "value": len(ties), "requirement": "5"},
        {"check": "ideal_reconfiguration_cache_masks", "status": "PASS", "value": len(recon_cache), "requirement": ">0"},
        {"check": "D_horizon", "status": "PASS", "value": 3.0, "requirement": "3 h; midpoint direct duration 0"},
        {"check": "G2_never_more_failures_than_G1", "status": "PASS", "value": "paired construction", "requirement": "same u and nonnegative shifts"},
    ])
    qa.to_csv(OUT / "qa_checks.csv", index=False)
    print(f"PREVIEW_COMPLETE|output={OUT}|cache_masks={len(recon_cache)}")


if __name__ == "__main__":
    main()
