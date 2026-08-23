from __future__ import annotations

import argparse
import csv
import hashlib
import importlib.util
import math
import subprocess
import sys
import time
import traceback
from dataclasses import dataclass
from pathlib import Path

import h5py
import numpy as np
import pandas as pd
from scipy.io import loadmat, savemat


OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[3]
BASE = ROOT / "results/task-002-stage2b-b3-smoke"
D01 = BASE / "w-grid-outage-reconfiguration-diagnostic/run-003"
D02 = BASE / "w-5point-reconfig-hardening-preview/run-003"
D03 = BASE / "topology-based-h2-island-diagnostic/run-001"
D04 = BASE / "topology-h2-dual-channel-minimal-model/run-006"
STAGE87 = BASE / "87C-A-stage87b-formal-w-bank/run-001"
STAGE88 = BASE / "88A-h2-bank-terminal-loh-site4-capacity-sensitivity/run-001"
STAGE89I = BASE / "stage89i-dual-channel-support-expansion-audit/run-002"
H2_MANIFEST = STAGE88 / "h2_bank_manifest.csv"
STAGE87_MANIFEST = STAGE87 / "checkpoint_completion_manifest.csv"
STAGE89I_COUNTS = STAGE89I / "support_expansion_by_state.csv"
CANDIDATE_MAT = ROOT / "terminalLoh_wdro/current_w_mainline_stage88/msp_bridge/near_stage_msp_input_stage88_cap200_candidate.mat"
GROUP_SOURCE = ROOT / "terminalLoh_wdro/src/aggregate_exact_period_scenarios_h2.m"
GROUP_NOJVM = ROOT / "terminalLoh_wdro/src/aggregate_exact_period_scenarios_c6_nojvm_h2.m"
BANK_SOURCE = ROOT / "terminalLoh_wdro/src/run_stage88a_h2_bank_state_h2.m"
SITE_MAP_SOURCE = ROOT / "hourly_grid_h2/map_site_to_electrical_bus_h2.m"
BANK_DIR = ROOT / "terminalLoh_wdro/output/stage89j_topology_h2_dual_channel_w_candidate/run-001"

R = 15000
K = 3
N = 33
I = 4
EXPECTED_TOTAL_SUPPORT = 457431
EXPECTED_TOPOLOGY_COUNT = 160862
SOURCE_BUS = 1
SITE_BUSES = {1: 24, 2: 14, 3: 18, 4: 31}
OFFICIAL_SLICE_DURATION_H = 1.0
Q_TOL = 32.0 * np.finfo(np.float64).eps


@dataclass(frozen=True)
class TopologyPayload:
    d_raw: np.ndarray
    dres: np.ndarray
    d_main_recovered: np.ndarray
    d_h2_island: np.ndarray
    d_black_island: np.ndarray
    aelec: np.ndarray
    component_by_node: np.ndarray
    source_node_count: int
    component_count: int
    closed_tie_count: int


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def dynamic_import(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    require(spec is not None and spec.loader is not None, f"Cannot import {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def update_digest(digest, state_id: int, payload) -> None:
    digest.update(np.asarray([state_id], dtype="<u2").tobytes())
    if isinstance(payload, np.ndarray):
        digest.update(np.ascontiguousarray(payload).tobytes())
    else:
        digest.update(str(payload).encode("ascii"))


def tracking(path: Path) -> str:
    rel = path.resolve().relative_to(ROOT.resolve()).as_posix()
    result = subprocess.run(
        ["git", "ls-files", "--error-unmatch", "--", rel], cwd=ROOT,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    return "tracked" if result.returncode == 0 else "untracked"


def rel(path: Path) -> str:
    return path.resolve().relative_to(ROOT.resolve()).as_posix()


def write_csv(path: Path, rows: list[dict], fieldnames: list[str] | None = None) -> None:
    require(bool(rows), f"No rows for {path.name}")
    names = fieldnames or list(rows[0])
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=names)
        writer.writeheader()
        writer.writerows(rows)


def byte_rows(array: np.ndarray, dtype) -> np.ndarray:
    data = np.ascontiguousarray(array, dtype=dtype)
    return data.view(np.uint8).reshape(data.shape[0], -1)


def exact_groups(arrays: list[np.ndarray]):
    """Stable first-occurrence groups under exact raw-byte row equality."""
    require(bool(arrays), "Empty exact signature")
    rows = arrays[0] if len(arrays) == 1 else np.concatenate(arrays, axis=1)
    packed = np.ascontiguousarray(rows).view(np.dtype((np.void, rows.shape[1]))).ravel()
    _, first, inverse_sorted, counts_sorted = np.unique(
        packed, return_index=True, return_inverse=True, return_counts=True
    )
    order = np.argsort(first, kind="stable")
    representatives = first[order].astype(np.int64)
    multiplicity = counts_sorted[order].astype(np.uint16)
    remap = np.empty(len(order), dtype=np.uint16)
    remap[order] = np.arange(1, len(order) + 1, dtype=np.uint16)
    group_id = remap[inverse_sorted]
    require(np.array_equal(representatives, np.sort(representatives)), "Representative stability gate failed")
    require(int(multiplicity.sum(dtype=np.uint64)) == R, "Multiplicity sum gate failed")
    return representatives, group_id, multiplicity


def signature_rows(dres, aroad, aelec, c):
    # MATLAB column-major within a draw: K fastest, then I, then N.
    return [
        byte_rows(dres.transpose(0, 2, 1), np.float64),
        byte_rows(aroad.transpose(0, 3, 2, 1), np.uint8),
        byte_rows(aelec.transpose(0, 3, 2, 1), np.uint8),
        byte_rows(c.transpose(0, 3, 2, 1), np.float64),
    ]


def old_signature_rows(d, aroad, c):
    return [
        byte_rows(d.transpose(0, 2, 1), np.float64),
        byte_rows(aroad.transpose(0, 3, 2, 1), np.uint8),
        byte_rows(c.transpose(0, 3, 2, 1), np.float64),
    ]


def load_stage88_bank(path: Path):
    with h5py.File(path, "r") as handle:
        path_id = np.asarray(handle["path_id"], dtype=np.uint32).ravel()
        d = np.asarray(handle["Dperiod"], dtype=np.float64).transpose(2, 1, 0)
        aroad = np.asarray(handle["Aperiod"], dtype=np.uint8).transpose(3, 2, 1, 0)
        c = np.asarray(handle["Cperiod"], dtype=np.float64).transpose(3, 2, 1, 0)
    require(np.array_equal(path_id, np.arange(1, R + 1, dtype=np.uint32)), "Stage88 path_id gate failed")
    require(d.shape == (R, K, N), "Stage88 D shape gate failed")
    require(aroad.shape == c.shape == (R, K, I, N), "Stage88 A/C shape gate failed")
    require(np.isfinite(d).all() and (d >= 0).all(), "Stage88 D value gate failed")
    require(np.isin(aroad, [0, 1]).all(), "Stage88 Aroad binary gate failed")
    require(np.isfinite(c[aroad > 0]).all(), "Reachable Stage88 C must be finite")
    return d, aroad, c


def solve_topology_payload(mask: int, topology, base_edges, ties, loads, factor) -> TopologyPayload:
    solved = topology.solve_topology(mask, base_edges, ties)
    require(not solved["has_cycle"], f"Cycle detected for mask {mask}")
    require(solved["edge_identity"] and solved["source_maximal"], f"Radial/source gate failed for mask {mask}")
    components = solved["component_by_node"]
    source_component = components[SOURCE_BUS]
    d_raw = np.zeros(N, dtype=np.float64)
    dres = np.zeros(N, dtype=np.float64)
    d_main = np.zeros(N, dtype=np.float64)
    d_h2 = np.zeros(N, dtype=np.float64)
    d_black = np.zeros(N, dtype=np.float64)
    aelec = np.zeros((I, N), dtype=np.uint8)
    originally_lost = set(solved["originally_lost"])
    for node in range(1, N + 1):
        value = loads[node - 1] * factor
        if node in originally_lost:
            d_raw[node - 1] = value
            category = solved["load_categories"][node]
            if category == "MAIN_GRID_RECOVERED":
                d_main[node - 1] = value
            elif category == "H2_ISLAND_CANDIDATE":
                d_h2[node - 1] = value
            elif category == "BLACK_ISLAND":
                d_black[node - 1] = value
            else:
                raise RuntimeError(f"Unknown load category {category}")
        if components[node] == source_component:
            continue
        dres[node - 1] = value
        for site, bus in SITE_BUSES.items():
            aelec[site - 1, node - 1] = np.uint8(components[bus] == components[node])
    require(np.array_equal(d_raw, d_main + d_h2 + d_black), f"Raw category partition failed mask {mask}")
    require(np.array_equal(dres, d_h2 + d_black), f"Dres category partition failed mask {mask}")
    require(not np.any(aelec[:, d_black > 0]), f"BLACK island Aelec violation mask {mask}")
    require(not np.any(aelec[:, d_main > 0]), f"Recovered node Aelec violation mask {mask}")
    component_array = np.asarray([components[node] for node in range(1, N + 1)], dtype=np.uint8)
    return TopologyPayload(
        d_raw=d_raw, dres=dres, d_main_recovered=d_main, d_h2_island=d_h2,
        d_black_island=d_black, aelec=aelec, component_by_node=component_array,
        source_node_count=int(solved["active_source_node_count"]),
        component_count=len(solved["components"]), closed_tie_count=len(solved["closed_ties"]),
    )


def expand_payload(masks: np.ndarray, cache: dict[int, TopologyPayload]):
    unique_masks, inverse = np.unique(masks, return_inverse=True)
    payloads = [cache[int(mask)] for mask in unique_masks]
    def expand(name, shape):
        templates = np.stack([getattr(payload, name) for payload in payloads])
        return templates[inverse].reshape(shape)
    return {
        "d_raw": expand("d_raw", (R, K, N)),
        "dres": expand("dres", (R, K, N)),
        "d_main_recovered": expand("d_main_recovered", (R, K, N)),
        "d_h2_island": expand("d_h2_island", (R, K, N)),
        "d_black_island": expand("d_black_island", (R, K, N)),
        "aelec": expand("aelec", (R, K, I, N)),
    }


def q95(values: np.ndarray) -> float:
    return float(np.quantile(values, 0.95))


def q99(values: np.ndarray) -> float:
    return float(np.quantile(values, 0.99))


def summary_metrics(dres_total, d_raw_sum, d_main_sum, d_h2_sum, d_black_sum,
                    any_aelec, serviceable_nodes, multiplicity, n_groups) -> dict:
    denominator = float(d_raw_sum)
    return {
        "n_draws": int(len(dres_total)),
        "n_exact_groups": int(n_groups),
        "mean_Dres": float(np.mean(dres_total)),
        "q95_Dres": q95(dres_total),
        "q99_Dres": q99(dres_total),
        "main_grid_recovered_D_share": float(d_main_sum / denominator) if denominator else 0.0,
        "H2_island_candidate_D_share": float(d_h2_sum / denominator) if denominator else 0.0,
        "black_island_D_share": float(d_black_sum / denominator) if denominator else 0.0,
        "P_any_Aelec": float(np.mean(any_aelec)),
        "mean_number_of_H2_serviceable_nodes": float(np.mean(serviceable_nodes)),
        "multiplicity_min": int(np.min(multiplicity)),
        "multiplicity_max": int(np.max(multiplicity)),
    }


def source_row(path: Path, role: str, actual_sha: str | None = None,
               expected_sha: str = "") -> dict:
    actual = actual_sha or sha256_file(path)
    return {
        "path": rel(path), "role": role, "bytes": path.stat().st_size,
        "sha256": actual, "expected_sha256": expected_sha,
        "hash_match": "PASS" if not expected_sha or actual == expected_sha else "FAIL",
        "git_status": tracking(path),
    }


def validate_fixed_inputs(preview):
    _, edges, loads, node_x, node_y = preview.read_inputs()
    base_edges = [tuple(map(int, row[:2])) for row in edges[:32]]
    ties = [tuple(map(int, row[:2])) for row in edges[32:]]
    require(ties == [(8, 21), (9, 15), (12, 22), (18, 33), (25, 29)], "Tie identity gate failed")
    edge_nodes = edges[:32, :2].astype(int) - 1
    x1, y1 = node_x[edge_nodes[:, 0]], node_y[edge_nodes[:, 0]]
    x2, y2 = node_x[edge_nodes[:, 1]], node_y[edge_nodes[:, 1]]
    candidate = loadmat(CANDIDATE_MAT, squeeze_me=True, struct_as_record=False)["NearStageInput"]
    device = candidate.HydrogenDevice
    fc_cap = np.atleast_1d(np.asarray(device.fc_cap_kw, dtype=np.float64)).ravel()
    eta_fc = float(device.eta_FC)
    lhv = float(device.h2_lhv_kWh_per_kg)
    require(np.array_equal(fc_cap, np.array([300.0, 150.0, 120.0, 150.0])), "FC cap identity gate failed")
    require(eta_fc == 0.55 and lhv == 33.33, "FC conversion parameter gate failed")
    factor = OFFICIAL_SLICE_DURATION_H / (eta_fc * lhv)
    return base_edges, ties, loads, x1, y1, x2, y2, fc_cap, eta_fc, lhv, factor


def run(preflight: bool = False) -> None:
    started = time.perf_counter()
    preview = dynamic_import("stage89j_accepted_d02", D02 / "run_preview.py")
    topology = dynamic_import("stage89j_accepted_d03", D03 / "run_diagnostic.py")
    base_edges, ties, loads, x1, y1, x2, y2, fc_cap, eta_fc, lhv, factor = validate_fixed_inputs(preview)

    manifest = pd.read_csv(H2_MANIFEST).sort_values("state_id")
    stage87_manifest = pd.read_csv(STAGE87_MANIFEST).sort_values("initial_state_id")
    expected = pd.read_csv(STAGE89I_COUNTS).sort_values("state_id")
    require(len(manifest) == len(stage87_manifest) == len(expected) == 35, "35-state manifest coverage gate failed")
    require(manifest.gate_pass.astype(int).eq(1).all(), "Stage88 source gate failed")
    require(stage87_manifest.status.eq("COMPLETE").all(), "Stage87 source completion gate failed")
    require(int(expected.n_unique_new.sum()) == EXPECTED_TOTAL_SUPPORT, "Stage89I expected total identity gate failed")

    if preflight:
        records = [next(manifest.itertuples(index=False))]
    else:
        sentinels = [OUT / "candidate_bank_manifest.csv", OUT / "README.md", OUT / "FAILURE.txt"]
        require(not any(path.exists() for path in sentinels), "Run directory already contains formal/failed outputs; use a new run number")
        records = list(manifest.itertuples(index=False))

    topology_cache: dict[int, TopologyPayload] = {}
    state_masks: dict[int, np.ndarray] = {}
    state_rows: list[dict] = []
    dres_qa_rows: list[dict] = []
    aelec_qa_rows: list[dict] = []
    source_rows: list[dict] = []
    per_intensity: dict[int, dict[str, list]] = {}
    trajectory_set_digest = hashlib.sha256()
    threshold_digest = hashlib.sha256()
    failure_digest = hashlib.sha256()
    road_bank_set_digest = hashlib.sha256()
    replay_mismatch_total = 0
    observation_count = 0

    static_sources = {
        Path(__file__).resolve(): "Stage-89J isolated formal candidate-bank builder",
        D01 / "README.md": "accepted source/reconfiguration context",
        D02 / "README.md": "accepted five-point G1 preview semantics",
        D02 / "run_preview.py": "frozen threshold and five-point deterministic replay implementation",
        D02 / "failure_sampling_semantics_audit.md": "fixed-resistance persistent-failure audit",
        D03 / "README.md": "accepted topology diagnostic",
        D03 / "run_diagnostic.py": "deterministic MAT-order radial reconstruction",
        D04 / "README.md": "accepted dual-channel minimal-model freeze",
        D04 / "D_res_semantics.md": "frozen Dres definition",
        D04 / "A_elec_definition.md": "frozen Aelec definition",
        D04 / "fc_equivalent_service_capacity.csv": "accepted static FC metadata cross-check",
        STAGE89I / "README.md": "accepted support-expansion expectation",
        STAGE89I_COUNTS: "accepted per-state NEW support expectation",
        H2_MANIFEST: "Stage88 road A/C bank identity and old exact-count source",
        STAGE87_MANIFEST: "frozen trajectory/scenario/DAC SHA registry",
        CANDIDATE_MAT: "mechanical FC parameter source",
        GROUP_SOURCE: "formal MATLAB exact grouping semantics",
        GROUP_NOJVM: "Stage88 no-JVM exact grouping semantics",
        BANK_SOURCE: "Stage88 multiplicity/qGroup semantics",
        SITE_MAP_SOURCE: "mechanically audited H2 site bus mapping",
        preview.NEAR_MAT: "IEEE33 topology/load and source-bus context",
    }
    for path, role in static_sources.items():
        require(path.is_file(), f"Missing fixed source {path}")
        source_rows.append(source_row(path, role))

    for record in records:
        state_id = int(record.state_id)
        intensity = int(record.a)
        loc = int(record.loc)
        stage87_row = stage87_manifest.loc[stage87_manifest.initial_state_id == state_id].iloc[0]
        expected_row = expected.loc[expected.state_id == state_id].iloc[0]
        nominal_path, formal_mat, nominal, saved_failed, _, _ = preview.load_state(state_id)
        trajectory_path = STAGE87 / "checkpoints" / f"state-{state_id:03d}_trajectory.csv"
        hashes = {
            trajectory_path: ("frozen W trajectory identity", str(stage87_row.trajectory_sha256)),
            nominal_path: ("frozen official scenario/path identity", str(stage87_row.scenario_sha256)),
            formal_mat: ("frozen Stage87 D/A/C and grid-failure realization", str(stage87_row.DAC_sha256)),
        }
        for path, (role, expected_sha) in hashes.items():
            actual_sha = sha256_file(path)
            require(actual_sha == expected_sha, f"Frozen source hash mismatch: {path}")
            source_rows.append(source_row(path, role, actual_sha, expected_sha))
        update_digest(trajectory_set_digest, state_id, hashes[trajectory_path][1])
        update_digest(trajectory_set_digest, state_id, hashes[nominal_path][1])

        uniform = preview.replay_line_thresholds(
            int(nominal.resistance_seed.iloc[0]), nominal.joint_stream_position.to_numpy(int)
        )
        update_digest(threshold_digest, state_id, np.asarray(uniform, dtype="<f8"))
        p_b2, _, _, _ = preview.point_probabilities(nominal, np.zeros(32), x1, y1, x2, y2)
        replay_b2 = preview.cumulative_failure(uniform, p_b2[:, preview.OFFICIAL, :])
        mismatch = int(np.count_nonzero(replay_b2 ^ saved_failed))
        replay_mismatch_total += mismatch
        require(mismatch == 0, f"Frozen B2 failure replay mismatch state {state_id}: {mismatch}")
        shifts_g1 = np.array([10.0, 10.0] + [0.0] * 30)
        p_g1, _, _, _ = preview.point_probabilities(nominal, shifts_g1, x1, y1, x2, y2)
        failed_g1 = preview.cumulative_failure(uniform, p_g1)[:, preview.OFFICIAL, :]
        masks = preview.masks_from_failed(failed_g1.reshape(-1, 32)).reshape(R, K).astype(np.uint64)
        state_masks[state_id] = masks
        update_digest(failure_digest, state_id, masks.astype("<u8"))
        observation_count += masks.size
        unique_masks = np.unique(masks)
        for mask in unique_masks:
            key = int(mask)
            if key not in topology_cache:
                topology_cache[key] = solve_topology_payload(key, topology, base_edges, ties, loads, factor)

        expanded = expand_payload(masks, topology_cache)
        d_raw = expanded["d_raw"]
        dres = expanded["dres"]
        d_main = expanded["d_main_recovered"]
        d_h2 = expanded["d_h2_island"]
        d_black = expanded["d_black_island"]
        aelec = expanded["aelec"]
        require(np.isfinite(dres).all() and (dres >= 0).all(), f"Dres value gate failed state {state_id}")
        require(np.isin(aelec, [0, 1]).all(), f"Aelec binary gate failed state {state_id}")
        require(np.array_equal(dres, d_h2 + d_black), f"Dres partition gate failed state {state_id}")
        require(np.array_equal(d_raw, d_main + d_h2 + d_black), f"Raw D partition gate failed state {state_id}")

        bank_path = Path(record.bank_path)
        bank_sha = sha256_file(bank_path)
        require(bank_sha == str(record.bank_sha256), f"Stage88 bank SHA mismatch state {state_id}")
        require(str(record.source_scenario_sha256) == str(stage87_row.scenario_sha256), "Scenario provenance mismatch")
        require(str(record.source_DAC_sha256) == str(stage87_row.DAC_sha256), "DAC provenance mismatch")
        source_rows.append(source_row(bank_path, "frozen Stage88 Aroad/C consequence bank", bank_sha, str(record.bank_sha256)))
        update_digest(road_bank_set_digest, state_id, bank_sha)
        d_old, aroad, c = load_stage88_bank(bank_path)
        old_reps, _, _ = exact_groups(old_signature_rows(d_old, aroad, c))
        new_reps, _, multiplicity = exact_groups(signature_rows(dres, aroad, aelec, c))
        n_old, n_new = len(old_reps), len(new_reps)
        require(n_old == int(record.exact_group_count), f"OLD exact-count mismatch state {state_id}")
        require(n_new == int(expected_row.n_unique_new), f"NEW Stage89I exact-count mismatch state {state_id}")

        dres_total = dres.sum(axis=(1, 2))
        any_aelec = aelec.any(axis=(1, 2, 3))
        serviceable_nodes = aelec.any(axis=2).sum(axis=2).reshape(-1)
        metrics = summary_metrics(
            dres_total, d_raw.sum(), d_main.sum(), d_h2.sum(), d_black.sum(),
            any_aelec, serviceable_nodes, multiplicity, n_new,
        )
        state_rows.append({"state_id": state_id, "intensity": intensity, "loc": loc, "lfw": 0, **metrics})
        dres_qa_rows.append({
            "state_id": state_id, "intensity": intensity, "loc": loc,
            "nonnegative_violation_count": int(np.count_nonzero(dres < 0)),
            "nonfinite_count": int(np.count_nonzero(~np.isfinite(dres))),
            "Dres_exceeds_Draw_count": int(np.count_nonzero(dres > d_raw)),
            "main_grid_recovered_Dres_nonzero_count": int(np.count_nonzero(dres[d_main > 0])),
            "raw_partition_max_abs_error": float(np.max(np.abs(d_raw - d_main - d_h2 - d_black))),
            "residual_partition_max_abs_error": float(np.max(np.abs(dres - d_h2 - d_black))),
            "H2_island_positive_Dres_count": int(np.count_nonzero(d_h2 > 0)),
            "black_island_positive_Dres_count": int(np.count_nonzero(d_black > 0)),
            "gate": "PASS",
        })
        aelec_qa_rows.append({
            "state_id": state_id, "intensity": intensity, "loc": loc,
            "nonbinary_count": int(np.count_nonzero(~np.isin(aelec, [0, 1]))),
            "main_grid_recovered_Aelec_nonzero_count": int(np.count_nonzero(aelec * (d_main[:, :, None, :] > 0))),
            "black_island_Aelec_nonzero_count": int(np.count_nonzero(aelec * (d_black[:, :, None, :] > 0))),
            "H2_island_Aelec_positive_count": int(np.count_nonzero(aelec * (d_h2[:, :, None, :] > 0))),
            "P_any_Aelec": float(any_aelec.mean()),
            "gate": "PASS",
        })
        bucket = per_intensity.setdefault(intensity, {
            "dres": [], "draws": [], "main": [], "h2": [], "black": [],
            "any": [], "nodes": [], "multiplicity": [], "groups": [],
        })
        bucket["dres"].append(dres_total)
        bucket["draws"].append(float(d_raw.sum()))
        bucket["main"].append(float(d_main.sum()))
        bucket["h2"].append(float(d_h2.sum()))
        bucket["black"].append(float(d_black.sum()))
        bucket["any"].append(any_aelec)
        bucket["nodes"].append(serviceable_nodes)
        bucket["multiplicity"].append(multiplicity)
        bucket["groups"].append(n_new)
        print(f"COUNT_COMPLETE|state={state_id}|old={n_old}|new={n_new}|topologies={len(topology_cache)}", flush=True)

    if preflight:
        state = state_rows[0]
        print(f"STAGE89J_PREFLIGHT_PASS|state={state['state_id']}|new={state['n_exact_groups']}|runtime={time.perf_counter()-started:.3f}")
        return

    require(len(state_rows) == 35 and observation_count == 35 * R * K, "Full frozen draw coverage gate failed")
    require(replay_mismatch_total == 0, "Aggregate frozen failure replay gate failed")
    new_total = sum(int(row["n_exact_groups"]) for row in state_rows)
    require(new_total == EXPECTED_TOTAL_SUPPORT, f"NEW_TOTAL_SUPPORT mismatch: {new_total} != {EXPECTED_TOTAL_SUPPORT}")
    require(len(topology_cache) == EXPECTED_TOPOLOGY_COUNT, "Topology-cache identity mismatch versus Stage89I")

    topology_digest = hashlib.sha256()
    for mask, payload in sorted(topology_cache.items()):
        topology_digest.update(np.asarray([mask], dtype="<u8").tobytes())
        topology_digest.update(payload.component_by_node.tobytes())
        topology_digest.update(payload.dres.astype("<f8").tobytes())
        topology_digest.update(payload.aelec.tobytes())
        topology_digest.update(np.asarray([
            payload.source_node_count, payload.component_count, payload.closed_tie_count
        ], dtype="<u2").tobytes())

    BANK_DIR.mkdir()
    exact_summary_path = OUT / "exact_group_summary.csv"
    bank_manifest_rows: list[dict] = []
    with exact_summary_path.open("w", newline="", encoding="utf-8") as exact_handle:
        exact_fields = ["state_id", "intensity", "loc", "group_id", "representative_path_id", "multiplicity", "q_g"]
        exact_writer = csv.DictWriter(exact_handle, fieldnames=exact_fields)
        exact_writer.writeheader()
        for record in records:
            state_id = int(record.state_id)
            intensity = int(record.a)
            loc = int(record.loc)
            masks = state_masks[state_id]
            expanded = expand_payload(masks, topology_cache)
            dres, aelec = expanded["dres"], expanded["aelec"]
            bank_path = Path(record.bank_path)
            _, aroad, c = load_stage88_bank(bank_path)
            reps, group_id, multiplicity = exact_groups(signature_rows(dres, aroad, aelec, c))
            group_count = len(reps)
            expected_count = int(expected.loc[expected.state_id == state_id, "n_unique_new"].iloc[0])
            require(group_count == expected_count, f"Write-pass support mismatch state {state_id}")
            q_group = multiplicity.astype(np.float64) / float(R)
            q_sum = float(q_group.sum(dtype=np.float64))
            q_fsum = float(math.fsum(q_group.tolist()))
            require(abs(q_sum - 1.0) <= Q_TOL and abs(q_fsum - 1.0) <= Q_TOL,
                    f"qGroup machine-precision gate failed state {state_id}")
            output_path = BANK_DIR / f"state-{state_id:03d}_stage89j_candidate_grouped.mat"
            payload = {
                "stateId": np.asarray([[state_id]], dtype=np.uint8),
                "a0": np.asarray([[intensity]], dtype=np.uint8),
                "loc0": np.asarray([[loc]], dtype=np.uint8),
                "lfw0": np.asarray([[0]], dtype=np.uint8),
                "sourceBus": np.asarray([[SOURCE_BUS]], dtype=np.uint8),
                "siteBus": np.asarray([[SITE_BUSES[i] for i in range(1, I + 1)]], dtype=np.uint8),
                "officialSliceDurationHours": np.asarray([[OFFICIAL_SLICE_DURATION_H]], dtype=np.float64),
                "Dres": dres[reps],
                "Aroad": aroad[reps],
                "Aelec": aelec[reps],
                "C": c[reps],
                "representativePathId": (reps + 1).astype(np.uint32).reshape(-1, 1),
                "multiplicity": multiplicity.reshape(-1, 1),
                "q_g": q_group.reshape(-1, 1),
                "groupId": group_id.reshape(-1, 1),
                "groupCount": np.asarray([[group_count]], dtype=np.uint16),
                "originalR": np.asarray([[R]], dtype=np.uint16),
                "fcStaticCapacityReference": rel(OUT / "fc_static_capacity_metadata.csv"),
                "sourceStage88BankSha256": str(record.bank_sha256),
                "failureIdentitySha256": failure_digest.hexdigest(),
                "signature": "(Dres,Aroad,Aelec,C)",
            }
            savemat(output_path, payload, do_compression=True, long_field_names=True, oned_as="column")
            output_sha = sha256_file(output_path)
            bank_manifest_rows.append({
                "state_id": state_id, "intensity": intensity, "loc": loc, "lfw": 0,
                "n_draws": R, "n_exact_groups": group_count,
                "multiplicity_sum": int(multiplicity.sum(dtype=np.uint64)),
                "q_g_sum": q_sum, "q_g_fsum": q_fsum,
                "representative_min_path_id": int(reps.min() + 1),
                "representative_max_path_id": int(reps.max() + 1),
                "signature": "(Dres,Aroad,Aelec,C)",
                "candidate_bank_path": rel(output_path), "candidate_bank_bytes": output_path.stat().st_size,
                "candidate_bank_sha256": output_sha,
                "source_stage88_bank_sha256": str(record.bank_sha256),
                "source_scenario_sha256": str(record.source_scenario_sha256),
                "source_DAC_sha256": str(record.source_DAC_sha256),
                "gate": "PASS",
            })
            for group, (representative, count, probability) in enumerate(
                zip(reps, multiplicity, q_group), start=1
            ):
                exact_writer.writerow({
                    "state_id": state_id, "intensity": intensity, "loc": loc,
                    "group_id": group, "representative_path_id": int(representative + 1),
                    "multiplicity": int(count), "q_g": repr(float(probability)),
                })
            print(f"BANK_COMPLETE|state={state_id}|groups={group_count}|bytes={output_path.stat().st_size}", flush=True)

    intensity_rows = []
    for intensity, bucket in sorted(per_intensity.items()):
        metrics = summary_metrics(
            np.concatenate(bucket["dres"]), sum(bucket["draws"]), sum(bucket["main"]),
            sum(bucket["h2"]), sum(bucket["black"]), np.concatenate(bucket["any"]),
            np.concatenate(bucket["nodes"]), np.concatenate(bucket["multiplicity"]), sum(bucket["groups"]),
        )
        intensity_rows.append({"intensity": intensity, "intensity_label": f"a{intensity}", **metrics})

    q_rows = [{
        "state_id": row["state_id"], "intensity": row["intensity"], "loc": row["loc"],
        "n_draws": row["n_draws"], "n_exact_groups": row["n_exact_groups"],
        "multiplicity_sum": bank_manifest_rows[idx]["multiplicity_sum"],
        "q_g_sum": bank_manifest_rows[idx]["q_g_sum"],
        "abs_q_g_sum_error": abs(bank_manifest_rows[idx]["q_g_sum"] - 1.0),
        "q_tolerance": Q_TOL, "gate": "PASS",
    } for idx, row in enumerate(state_rows)]

    fc_rows = []
    for site in range(1, I + 1):
        h_cap = fc_cap[site - 1] * OFFICIAL_SLICE_DURATION_H / (eta_fc * lhv)
        fc_rows.append({
            "site_id": f"Site{site}", "site_index": site, "bus": SITE_BUSES[site],
            "fc_cap_kw": fc_cap[site - 1], "eta_FC": eta_fc,
            "h2_lhv_kWh_per_kg": lhv, "official_slice_duration_h": OFFICIAL_SLICE_DURATION_H,
            "H_FC_cap_kg_per_slice": h_cap,
            "formula": "fc_cap_kw*official_slice_duration_h/(eta_FC*h2_lhv_kWh_per_kg)",
            "parameter_kind": "STATIC_METADATA_NOT_EXACT_SIGNATURE",
            "source": rel(CANDIDATE_MAT),
        })

    topology_rows = [{
        "unique_failure_topologies": len(topology_cache),
        "topology_observations": observation_count,
        "cache_misses_unique_solves": len(topology_cache),
        "cache_hits": observation_count - len(topology_cache),
        "cycle_detected": "NO", "radial_forest_valid": "YES",
        "source_component_deterministic": "YES", "h2_site_component_deterministic": "YES",
        "same_failure_mask_same_classification": "YES_BY_SINGLE_CACHED_IDENTITY",
        "source_bus": SOURCE_BUS,
        "tie_order": "8-21;9-15;12-22;18-33;25-29",
        "topology_replay_sha256": topology_digest.hexdigest(),
        "gate": "PASS",
    }]

    write_csv(OUT / "candidate_bank_manifest.csv", bank_manifest_rows)
    write_csv(OUT / "candidate_state_summary.csv", state_rows)
    write_csv(OUT / "candidate_intensity_summary.csv", intensity_rows)
    write_csv(OUT / "qg_probability_qa.csv", q_rows)
    write_csv(OUT / "dres_qa.csv", dres_qa_rows)
    write_csv(OUT / "aelec_qa.csv", aelec_qa_rows)
    write_csv(OUT / "topology_cache_summary.csv", topology_rows)
    write_csv(OUT / "fc_static_capacity_metadata.csv", fc_rows)

    for row in source_rows:
        require(row["hash_match"] == "PASS", f"Source manifest mismatch {row['path']}")
    write_csv(OUT / "source_manifest.csv", source_rows)

    schema = f"""# Stage-89J isolated candidate schema

Each `terminalLoh_wdro/output/stage89j_topology_h2_dual_channel_w_candidate/run-001/state-XXX_stage89j_candidate_grouped.mat` is a MATLAB v5 MAT file and loads directly with MATLAB `load`.

- State fields: `stateId`, `a0`, `loc0`, `lfw0`, `sourceBus`, `siteBus`, and `officialSliceDurationHours`.
- Grouped scenario fields: `Dres[G,3,33]` double, `Aroad[G,3,4,33]` uint8, `Aelec[G,3,4,33]` uint8, and `C[G,3,4,33]` double.
- Exact-group fields: `representativePathId[G,1]` uint32, `multiplicity[G,1]` uint16, `q_g[G,1]` double, `groupId[15000,1]` uint16, `groupCount`, and `originalR`.
- Stable representatives are the first frozen path occurrence. `groupId` is one-based and maps all 15,000 frozen draws to those representatives.
- The exact signature is `(Dres,Aroad,Aelec,C)`. Raw-byte equality uses MATLAB field order and column-major element order: K fastest, then I where present, then N. There is no rounding, tolerance, clustering, quantization, or approximate reduction.
- `q_g=multiplicity/15000`. FC capacity is static site metadata in `fc_static_capacity_metadata.csv` and is deliberately excluded from the signature.
- `Dres` retains demand in H2-containing non-source islands. `Aelec` is reachability/candidate service capability, not restored load.

The formal support total is {new_total}. Source and output SHA-256 identities are in the two manifests.
"""
    (OUT / "candidate_schema.md").write_text(schema, encoding="utf-8")

    replay_md = f"""# Frozen randomness replay QA

Status: **PASS**.

- W_TRAJECTORY_RESAMPLED = NO. All 35 frozen Stage87 trajectory and nominal scenario files match `checkpoint_completion_manifest.csv` SHA-256 values.
- W_TRANSITION_MATRIX_MODIFIED = NO. No trajectory generator or aw/locw/lfw probability code is called; existing frozen identities are consumed read-only.
- GRID_FAILURE_RANDOMNESS_RESAMPLED = NO. State-specific `resistance_seed` plus `joint_stream_position` replay the accepted MT19937 thresholds; aggregate B2 mismatch bits = {replay_mismatch_total}.
- ROAD_FAILURE_RANDOMNESS_RESAMPLED = NO. Aroad and C are read from the 35 Stage88 banks, and every full-bank SHA-256 matches `h2_bank_manifest.csv`.
- Frozen draws = 35 x 15000 = 525000; official failure observations = {observation_count}.

Deterministic combined identities:

- W trajectory/scenario source set SHA-256: `{trajectory_set_digest.hexdigest()}`
- fixed line-resistance uniform replay SHA-256: `{threshold_digest.hexdigest()}`
- G1 official-slice failure-mask identity SHA-256: `{failure_digest.hexdigest()}`
- Stage88 road-bank source set SHA-256: `{road_bank_set_digest.hexdigest()}`
- deterministic topology classification SHA-256: `{topology_digest.hexdigest()}`

These are replay identities, not new random seeds.
"""
    (OUT / "frozen_randomness_replay_qa.md").write_text(replay_md, encoding="utf-8")

    runtime = time.perf_counter() - started
    readme = f"""# Stage-89J formal topology-based H2 dual-channel W candidate bank

Status: **FORMAL_W_CANDIDATE**. This is an isolated candidate: **NOT CURRENT_W_MAINLINE**, **NOT ACCEPTED_TERMINALLOH**, and **NOT MSP-ACCEPTED**.

## Outcome

- Built 35 state banks from 525,000 frozen trajectory identities without any W/grid/road redraw.
- Used W1-M12-W2-M23-W3 grid exposure, actual endpoint sampled Vmax midpoint interpolation, persistent fixed resistance, and G1 strong-hardening sensitivity only on lines 1-2 and 2-3.
- Kept official W1/W2/W3 one-hour service slices and current three-point Stage88 Aroad/C semantics.
- Applied deterministic MAT-order five-tie radial reconstruction from source bus 1.
- Exact signature `(Dres,Aroad,Aelec,C)` produced **{new_total:,}** groups, exactly matching Stage-89I's **{EXPECTED_TOTAL_SUPPORT:,}** expectation.
- `q_g=multiplicity/15000`; all 35 multiplicity and probability gates pass at machine precision.
- FC capacity is static metadata only and is not part of exact grouping.

`H2_island_candidate_D_share` is a topology candidate-demand share. It is not restored-load share and makes no grid-forming, black-start, voltage, thermal, or dynamic-FC claim.

## Scope gates

CURRENT_W_MAINLINE_MODIFIED=NO  
STAGE88_MODIFIED=NO  
STAGE89H_MODIFIED=NO  
W_TRAJECTORY_RESAMPLED=NO  
GRID_FAILURE_RANDOMNESS_RESAMPLED=NO  
ROAD_FAILURE_RANDOMNESS_RESAMPLED=NO  
SAA_DRO_RUN=NO  
TERMINALLOH_RUN=NO  
FA_MSP_RUN=NO  
OOS_RUN=NO  
NEW_BINARY_VARIABLES=0  
NEW_NONLINEAR_MODEL=NO

The 1.10 GB candidate body is under `terminalLoh_wdro/output/stage89j_topology_h2_dual_channel_w_candidate/run-001/` per the large-output rule. Its lightweight schema, per-state manifest, exact-group index, statistics, QA, static FC metadata, and full source provenance are in this results directory. Runtime: {runtime:.3f} seconds.

Recommended next stage: Stage-89K TerminalLOH SAA/DRO on this isolated candidate.
"""
    (OUT / "README.md").write_text(readme, encoding="utf-8")
    print(f"STAGE89J_COMPLETE|support={new_total}|topologies={len(topology_cache)}|runtime={runtime:.3f}", flush=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--preflight", action="store_true", help="validate one frozen state without writing outputs")
    args = parser.parse_args()
    if args.preflight:
        run(preflight=True)
        return
    try:
        run(preflight=False)
    except Exception:
        failure = traceback.format_exc()
        (OUT / "FAILURE.txt").write_text(failure, encoding="utf-8")
        print(failure, file=sys.stderr)
        raise


if __name__ == "__main__":
    main()
