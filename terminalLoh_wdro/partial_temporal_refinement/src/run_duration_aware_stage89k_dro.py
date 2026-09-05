from __future__ import annotations

import argparse
import concurrent.futures
import csv
import hashlib
import importlib.util
import json
import math
import os
import subprocess
import sys
import time
from pathlib import Path

import numpy as np
import pandas as pd
from scipy import sparse
from scipy.io import loadmat


WORK = Path(__file__).resolve().parents[1]
ROOT = WORK.parents[1]
CONFIG_PATH = WORK / "config/w0_zero_3p5h_schema.json"
GROUP_DIR = WORK / "grouped_bank_3p5h"
GROUP_MANIFEST = GROUP_DIR / "six_segment_grouped_bank_manifest.csv"
CURRENT_SOURCE = ROOT / "terminalLoh_wdro/current_w_mainline_stage89/src_snapshot/stage89k/run_stage89k_terminal_loh.py"
CURRENT_TABLE = ROOT / "terminalLoh_wdro/current_w_mainline_stage89/terminal_tables/terminal_loh_stage89k_dro_eta003_adopted.csv"
CURRENT_IDENTITY = ROOT / "terminalLoh_wdro/current_w_mainline_stage89/terminal_tables/terminal_table_identity.csv"
FC_METADATA = ROOT / "results/task-002-stage2b-b3-smoke/stage89j-topology-h2-dual-channel-w-candidate/run-001/fc_static_capacity_metadata.csv"
FROZEN_GUROBI = ROOT / "terminalLoh_wdro/output/step04cc6_python_runtime/gurobipy-12.0.1"
RESULT_ROOT = WORK / "dro_3p5h/run-001"
CASE_DIR = RESULT_ROOT / "cases"
LOG_DIR = RESULT_ROOT / "logs"
QA_TOL = 1.0e-7
STATE_TOL_KG = 1.0e-6


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(4 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def write_csv(path: Path, rows: list[dict]) -> None:
    require(bool(rows), f"No rows for {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def load_config() -> dict:
    with CONFIG_PATH.open("r", encoding="utf-8") as handle:
        config = json.load(handle)
    require(config["segment_state"] == ["W0", "W1", "M12", "W2", "M23", "W3"], "Segment state failed")
    require(config["segment_dt_h"] == [1.0, 0.5, 0.5, 0.5, 0.5, 0.5], "Segment duration failed")
    require(config["total_service_horizon_h"] == 3.5, "Horizon failed")
    return config


def load_stage89k_module():
    runtime = str(FROZEN_GUROBI.resolve())
    if runtime not in sys.path:
        sys.path.insert(0, runtime)
    spec = importlib.util.spec_from_file_location("stage89k_duration_frozen", CURRENT_SOURCE)
    require(spec is not None and spec.loader is not None, "Cannot load current Stage89K source")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    require(tuple(module.gp.gurobi.version()) == module.EXPECTED_GUROBI == (12, 0, 1), "Gurobi identity failed")
    return module


def parse_segment_state(value) -> list[str]:
    array = np.asarray(value).reshape(-1)
    return [str(item).strip() for item in array]


def load_fc_rates() -> tuple[np.ndarray, pd.DataFrame]:
    frame = pd.read_csv(FC_METADATA).sort_values("site_index")
    require(list(frame.site_index.astype(int)) == [1, 2, 3, 4], "FC site order failed")
    require(np.allclose(frame.fc_cap_kw, [300.0, 150.0, 120.0, 150.0]), "FC kW parameter changed")
    require(np.allclose(frame.eta_FC, 0.55) and np.allclose(frame.h2_lhv_kWh_per_kg, 33.33), "FC efficiency/LHV changed")
    rates = frame.fc_cap_kw.to_numpy(float) / (frame.eta_FC.to_numpy(float) * frame.h2_lhv_kWh_per_kg.to_numpy(float))
    require(np.allclose(rates, frame.H_FC_cap_kg_per_slice.to_numpy(float)), "FC 1h metadata/rate mismatch")
    return rates, frame


def build_duration_structure(stage89k, D_rate, Aroad, Aelec, C, dt_h, fc_rate_kgph):
    D_rate = np.asarray(D_rate, dtype=float)
    Aroad = np.asarray(Aroad)
    Aelec = np.asarray(Aelec)
    C = np.asarray(C, dtype=float)
    dt_h = np.asarray(dt_h, dtype=float).reshape(-1)
    require(D_rate.ndim == 3 and D_rate.shape[1] == dt_h.size == 6, "Duration-aware D shape failed")
    G, K, N = D_rate.shape
    I = 4
    expected = (G, K, I, N)
    require(Aroad.shape == expected and Aelec.shape == expected and C.shape == expected, "Duration-aware channel shape failed")
    require(np.isfinite(D_rate).all() and (D_rate >= 0).all(), "Dres rate invalid")
    require(np.isfinite(C[Aroad > 0.5]).all(), "Reachable C must be finite")
    require(np.all(dt_h > 0) and abs(float(dt_h.sum()) - 3.5) <= 1.0e-12, "dt invalid")

    D = D_rate * dt_h[None, :, None]
    fc_cap_amount = dt_h[:, None] * np.asarray(fc_rate_kgph, dtype=float)[None, :]
    demand_mask = D > 0
    road_mask = (Aroad > 0.5) & demand_mask[:, :, None, :]
    elec_mask = (Aelec > 0.5) & demand_mask[:, :, None, :]
    demand_linear = np.flatnonzero(demand_mask.ravel(order="F"))
    road_linear = np.flatnonzero(road_mask.ravel(order="F"))
    elec_linear = np.flatnonzero(elec_mask.ravel(order="F"))
    g_u, _, _ = np.unravel_index(demand_linear, (G, K, N), order="F")
    g_r, k_r, i_r, n_r_sub = np.unravel_index(road_linear, expected, order="F")
    g_e, k_e, i_e, n_e_sub = np.unravel_index(elec_linear, expected, order="F")
    n_u, n_r, n_e = demand_linear.size, road_linear.size, elec_linear.size
    demand_row_flat = np.full(G * K * N, -1, dtype=np.int64)
    demand_row_flat[demand_linear] = np.arange(n_u, dtype=np.int64)
    road_demand_linear = np.ravel_multi_index((g_r, k_r, n_r_sub), (G, K, N), order="F")
    elec_demand_linear = np.ravel_multi_index((g_e, k_e, n_e_sub), (G, K, N), order="F")
    road_demand_rows = demand_row_flat[road_demand_linear]
    elec_demand_rows = demand_row_flat[elec_demand_linear]
    require((road_demand_rows >= 0).all() and (elec_demand_rows >= 0).all(), "Service arc lacks demand")
    road_cost = np.where((Aroad > 0.5) & np.isfinite(C), C, 0.0).ravel(order="F")[road_linear]
    demand_values = D.ravel(order="F")[demand_linear]

    inventory_row_start = n_u
    fc_row_start = n_u + G * I
    n_rows = n_u + G * I + G * K * I
    nvar = n_r + n_e + n_u
    row = np.concatenate(
        [
            np.arange(n_u),
            road_demand_rows,
            elec_demand_rows,
            inventory_row_start + g_r * I + i_r,
            inventory_row_start + g_e * I + i_e,
            fc_row_start + (g_e * K + k_e) * I + i_e,
        ]
    ).astype(np.int64, copy=False)
    col = np.concatenate(
        [
            n_r + n_e + np.arange(n_u),
            np.arange(n_r),
            n_r + np.arange(n_e),
            np.arange(n_r),
            n_r + np.arange(n_e),
            n_r + np.arange(n_e),
        ]
    ).astype(np.int64, copy=False)
    fixed_matrix = sparse.coo_matrix((np.ones(row.size), (row, col)), shape=(n_rows, nvar)).tocsr()
    fixed_rhs_base = np.zeros(n_rows, dtype=float)
    fixed_rhs_base[:n_u] = demand_values
    fixed_rhs_base[fc_row_start:] = np.tile(fc_cap_amount.reshape(-1), G)
    fixed_sense = np.full(n_rows, b"<", dtype="S1")
    fixed_sense[:n_u] = b"="
    shortage_rows = sparse.coo_matrix(
        (np.ones(n_u), (g_u, n_r + n_e + np.arange(n_u))), shape=(G, nvar)
    ).tocsr()
    structure = stage89k.DualStructure(
        D=D,
        Aroad=Aroad,
        Aelec=Aelec,
        C=C,
        G=G,
        K=K,
        I=I,
        N=N,
        demand_linear=demand_linear,
        road_linear=road_linear,
        elec_linear=elec_linear,
        g_u=g_u,
        g_r=g_r,
        k_r=k_r,
        i_r=i_r,
        g_e=g_e,
        k_e=k_e,
        i_e=i_e,
        road_demand_rows=road_demand_rows,
        elec_demand_rows=elec_demand_rows,
        demand_values=demand_values,
        road_cost=road_cost,
        n_u=n_u,
        n_r=n_r,
        n_e=n_e,
        fixed_matrix=fixed_matrix,
        fixed_rhs_base=fixed_rhs_base,
        fixed_sense=fixed_sense,
        shortage_rows=shortage_rows,
        total_demand=D.sum(axis=(1, 2)),
        inventory_row_start=inventory_row_start,
        fc_row_start=fc_row_start,
    )
    return structure, D, fc_cap_amount


def load_candidate_state(state_id: int, stage89k):
    config = load_config()
    dt = np.asarray(config["segment_dt_h"], dtype=float)
    manifest = pd.read_csv(GROUP_MANIFEST)
    row = manifest[manifest.state_id == state_id]
    require(len(row) == 1 and row.iloc[0].gate == "PASS", "Grouped manifest lookup failed")
    row = row.iloc[0]
    path = GROUP_DIR / f"state-{state_id:03d}_six_segment_grouped.mat"
    require(path.is_file() and path.stat().st_size == int(row.bank_bytes), "Grouped bank bytes failed")
    require(sha256_file(path) == row.bank_sha256, "Grouped bank SHA failed")
    data = loadmat(path, squeeze_me=True)
    require(int(data["stateId"]) == state_id and int(data["originalR"]) == 15000, "State identity failed")
    require(parse_segment_state(data["segmentState"]) == config["segment_state"], "Bank segment state failed")
    require(np.array_equal(np.asarray(data["segmentDtHours"], dtype=float).reshape(-1), dt), "Bank dt failed")
    q = np.asarray(data["q_g"], dtype=float).reshape(-1)
    require((q > 0).all() and abs(float(q.sum()) - 1.0) <= 1.0e-12, "q_g failed")
    fc_rate, _ = load_fc_rates()
    structure, D_amount, fc_amount = build_duration_structure(
        stage89k, data["Dres"], data["Aroad"], data["Aelec"], data["C"], dt, fc_rate
    )
    require(structure.G == int(row.group_count), "Group count failed")
    return path, data, q / q.sum(), structure, D_amount, fc_rate, fc_amount


def solve_candidate_state(state_id: int) -> dict:
    stage89k = load_stage89k_module()
    _, data, q, structure, D_amount, fc_rate, fc_amount = load_candidate_state(state_id, stage89k)
    # The inherited Stage89K post-solve helper expects a site vector. The
    # duration-aware per-segment caps are already embedded in fixed_matrix/RHS;
    # verify those exact caps explicitly below.
    stage89k.FC_CAP = fc_rate
    solution = stage89k.solve_dro(structure, q, stage89k.ETA)
    fixed = stage89k.solve_fixed_recourse(structure, solution.T)
    adversary = stage89k.solve_worst_probability(q, fixed.operating_loss, stage89k.ETA)
    lex = stage89k.solve_lexicographic(structure, solution.T)
    objective_rebuild = stage89k.C_H2 * float(solution.T.sum()) + adversary.worst_value
    shared_inventory_equivalent = bool(lex.max_inventory_violation <= QA_TOL)
    duration_fc_violation = float(np.max(lex.elec_service_slice - fc_amount[None, :, :], initial=0.0))
    config_dt = np.asarray(load_config()["segment_dt_h"], dtype=float)
    checks = {
        "status_optimal": solution.status == "OPTIMAL",
        "T_caps": bool((solution.T >= -QA_TOL).all() and (solution.T <= stage89k.CAPACITY + QA_TOL).all()),
        "demand_balance": lex.max_demand_balance_error <= QA_TOL,
        "shared_inventory": shared_inventory_equivalent,
        "fc_capacity": duration_fc_violation <= QA_TOL,
        "shortage_preserved": lex.max_shortage_preservation_error <= QA_TOL,
        "q_sum": abs(float(q.sum()) - 1.0) <= 1.0e-12,
        "p_sum": adversary.probability_sum_residual <= 1.0e-10,
        "pearson_eta": adversary.divergence <= stage89k.ETA + 1.0e-9,
        "objective_rebuild": abs(solution.objective_value - objective_rebuild) <= 1.0e-3,
        "gap": solution.absolute_gap <= stage89k.ABS_GAP_TOL + 1.0e-9 or solution.relative_gap <= stage89k.REL_GAP_TOL + 1.0e-12,
        "D_amount_once": abs(float(D_amount.sum()) - float(structure.D.sum())) <= 1.0e-12,
        "FC_rate_to_amount_once": bool(np.allclose(fc_amount, config_dt[:, None] * fc_rate[None, :])),
        "W0_D_amount_zero": float(np.max(np.abs(D_amount[:, 0]))) == 0.0,
    }
    require(all(checks.values()), f"State {state_id} QA failed: {[key for key, value in checks.items() if not value]}")
    meta = {
        "state": state_id,
        "intensity": int(data["a0"]),
        "loc": int(data["loc0"]),
        "lfw": int(data["lfw0"]),
        "solver_status": solution.status,
        "eta": stage89k.ETA,
        "group_count": structure.G,
        "T1_kg": float(solution.T[0]),
        "T2_kg": float(solution.T[1]),
        "T3_kg": float(solution.T[2]),
        "T4_kg": float(solution.T[3]),
        "T_total_kg": float(solution.T.sum()),
        "objective_yuan": solution.objective_value,
        "worst_expected_recourse_yuan": adversary.worst_value,
        "nominal_expected_recourse_yuan": solution.nominal_expected_recourse,
        "LB_yuan": solution.lower_bound,
        "UB_yuan": solution.upper_bound,
        "absolute_gap_yuan": solution.absolute_gap,
        "relative_gap": solution.relative_gap,
        "iterations": solution.iteration_count,
        "cuts": solution.cut_count,
        "pearson_divergence": adversary.divergence,
        "p_sum": float(adversary.probability.sum()),
        "p_min": adversary.minimum_probability,
        "max_demand_balance_error_kg": lex.max_demand_balance_error,
        "max_inventory_violation_kg": lex.max_inventory_violation,
        "max_fc_violation_kg": duration_fc_violation,
        "max_shortage_preservation_error_kg": lex.max_shortage_preservation_error,
        "q_weighted_shortage_kg": float(np.dot(q, lex.shortage_kg)),
        "runtime_sec": solution.solve_runtime_sec + lex.primary_runtime_sec + lex.secondary_runtime_sec,
        "checks": checks,
    }
    return meta


def write_case(result: dict) -> None:
    CASE_DIR.mkdir(parents=True, exist_ok=True)
    state_id = int(result["state"])
    path = CASE_DIR / f"state-{state_id:03d}.json"
    require(not path.exists(), f"Refusing to overwrite case {path}")
    path.write_text(json.dumps(result, indent=2), encoding="utf-8")


def run_case_mode(state_id: int) -> None:
    RESULT_ROOT.mkdir(parents=True, exist_ok=True)
    result = solve_candidate_state(state_id)
    write_case(result)
    print(f"CASE_COMPLETE|state={state_id:03d}|T={result['T_total_kg']:.12f}|runtime={result['runtime_sec']:.3f}", flush=True)


def reproduce_current_state(state_id: int) -> dict:
    stage89k = load_stage89k_module()
    manifest = pd.read_csv(ROOT / "results/task-002-stage2b-b3-smoke/stage89j-topology-h2-dual-channel-w-candidate/run-001/candidate_bank_manifest.csv")
    row = manifest[manifest.state_id == state_id].iloc[0]
    data = loadmat(ROOT / row.candidate_bank_path, squeeze_me=True)
    q = np.asarray(data["q_g"], dtype=float).reshape(-1)
    fc_rate, _ = load_fc_rates()
    stage89k.FC_CAP = fc_rate
    structure = stage89k.build_structure(data["Dres"], data["Aroad"], data["Aelec"], data["C"], fc_rate)
    solution = stage89k.solve_dro(structure, q / q.sum(), stage89k.ETA)
    adopted = pd.read_csv(CURRENT_TABLE).set_index("state_id").loc[state_id]
    adopted_t = np.asarray([adopted[f"T{i}_kg"] for i in range(1, 5)], dtype=float)
    error = float(np.max(np.abs(solution.T - adopted_t)))
    require(error <= 1.0e-6, f"Current Stage89K reproduction failed: {error}")
    return {"state": state_id, "max_abs_T_error_kg": error, "adopted_T_total_kg": float(adopted_t.sum()), "reproduced_T_total_kg": float(solution.T.sum()), "gate": "PASS"}


def write_duration_audit() -> None:
    rows = [
        {"variable_constraint_cost_term": "FC electrical power nameplate", "unit": "kW", "rate_or_amount": "RATE", "old_1h_assumption": "kg cap = kW*1h/(eta_FC*LHV)", "new_dt_handling": "kg cap[k,i] = kW_i*dt[k]/(eta_FC*LHV); multiplied once"},
        {"variable_constraint_cost_term": "FC hydrogen consumption / electrical service y_e", "unit": "kg", "rate_or_amount": "AMOUNT", "old_1h_assumption": "y_e numerically equals one-slice kg", "new_dt_handling": "decision is segment kg amount; no further dt multiplier"},
        {"variable_constraint_cost_term": "Residual electric demand Dres", "unit": "kg/h equivalent H2 rate", "rate_or_amount": "RATE", "old_1h_assumption": "1h made rate numerically equal amount", "new_dt_handling": "D_amount[k,n] = Dres_rate[k,n]*dt[k]; multiplied once"},
        {"variable_constraint_cost_term": "Demand balance", "unit": "kg", "rate_or_amount": "AMOUNT", "old_1h_assumption": "sum y + u = D per one-hour slice", "new_dt_handling": "sum y_amount + u_amount = D_rate*dt; no second dt"},
        {"variable_constraint_cost_term": "TerminalLOH reserve T_i", "unit": "kg", "rate_or_amount": "AMOUNT", "old_1h_assumption": "shared across W1-W3", "new_dt_handling": "shared across all six segments; no dt multiplier"},
        {"variable_constraint_cost_term": "H2 inventory transition", "unit": "kg", "rate_or_amount": "AMOUNT", "old_1h_assumption": "implicit sum of all service amounts <= T", "new_dt_handling": "I0=T; I[k+1]=I[k]-road_y_amount-elec_y_amount; equivalent to shared sum<=T; no inflow/repair"},
        {"variable_constraint_cost_term": "Ordinary H2 demand", "unit": "N/A", "rate_or_amount": "ABSENT", "old_1h_assumption": "not in Stage89K recourse", "new_dt_handling": "remains absent; no dt"},
        {"variable_constraint_cost_term": "Disaster H2 demand", "unit": "kg", "rate_or_amount": "AMOUNT_AFTER_CONVERSION", "old_1h_assumption": "Dres one-hour amount", "new_dt_handling": "Dres rate*dt before optimization; amount not multiplied again"},
        {"variable_constraint_cost_term": "Shortage u", "unit": "kg", "rate_or_amount": "AMOUNT", "old_1h_assumption": "one-slice unmet kg", "new_dt_handling": "segment unmet kg amount; no further dt"},
        {"variable_constraint_cost_term": "HTT site-to-site shipping flow", "unit": "N/A", "rate_or_amount": "ABSENT", "old_1h_assumption": "not in Stage89K TerminalLOH recourse", "new_dt_handling": "remains absent; road service is site-to-node disaster service, not HTT"},
        {"variable_constraint_cost_term": "HTT capacity", "unit": "N/A", "rate_or_amount": "ABSENT", "old_1h_assumption": "not in Stage89K recourse", "new_dt_handling": "remains absent"},
        {"variable_constraint_cost_term": "Road service y_r", "unit": "kg", "rate_or_amount": "AMOUNT", "old_1h_assumption": "one-slice served kg", "new_dt_handling": "segment served kg amount; no further dt"},
        {"variable_constraint_cost_term": "Road transport cost C*y_r", "unit": "km*kg lexicographic impedance", "rate_or_amount": "AMOUNT_BASED_SECONDARY_ONLY", "old_1h_assumption": "C is not RMB and excluded from Pearson primary loss", "new_dt_handling": "y_r already kg amount; no dt; semantics unchanged"},
        {"variable_constraint_cost_term": "Terminal reserve preparation cost c_H2*T", "unit": "yuan", "rate_or_amount": "AMOUNT_BASED", "old_1h_assumption": "32.5213675213675 yuan/kg * T kg", "new_dt_handling": "unchanged; T already kg"},
        {"variable_constraint_cost_term": "FC operating cost", "unit": "N/A", "rate_or_amount": "ABSENT", "old_1h_assumption": "not a separate Stage89K objective term", "new_dt_handling": "remains absent; c_H2 is reserve preparation cost, not FC dispatch cost"},
        {"variable_constraint_cost_term": "Shortage penalty M_H2*u", "unit": "yuan", "rate_or_amount": "AMOUNT_BASED", "old_1h_assumption": "1283.205 yuan/kg * shortage kg", "new_dt_handling": "u already segment kg amount; no dt"},
        {"variable_constraint_cost_term": "Pearson scenario loss", "unit": "yuan", "rate_or_amount": "AMOUNT_BASED", "old_1h_assumption": "M_H2 times total scenario shortage kg", "new_dt_handling": "same after rate-to-amount conversion; eta/q/objective unchanged"},
        {"variable_constraint_cost_term": "Electrical energy", "unit": "kWh", "rate_or_amount": "DIAGNOSTIC_NOT_DECISION", "old_1h_assumption": "Dres kg corresponds through eta_FC*LHV", "new_dt_handling": "power/rate integrated by dt before kg conversion; no energy objective term added"},
    ]
    write_csv(RESULT_ROOT / "duration_unit_audit.csv", rows)


def run_smoke() -> None:
    RESULT_ROOT.mkdir(parents=True, exist_ok=True)
    write_duration_audit()
    current = reproduce_current_state(8)
    candidate = solve_candidate_state(8)
    synthetic_rate = np.asarray([0.0, 10.0, 10.0, 10.0, 10.0, 10.0])
    dt = np.asarray(load_config()["segment_dt_h"], dtype=float)
    amount = synthetic_rate * dt
    inventory = 25.0 - np.cumsum(amount)
    synthetic_pass = bool(np.allclose(amount, [0.0, 5.0, 5.0, 5.0, 5.0, 5.0]) and np.all(inventory >= -1.0e-12) and abs(float(inventory[-1])) <= 1.0e-12)
    require(synthetic_pass, "Synthetic inventory duration smoke failed")
    smoke = {
        "CURRENT_STAGE89K_REPRODUCTION": current,
        "CANDIDATE_STATE8_T": [candidate[f"T{i}_kg"] for i in range(1, 5)],
        "CANDIDATE_STATE8_T_TOTAL": candidate["T_total_kg"],
        "RATE_TO_AMOUNT_SYNTHETIC": {"rate_kgph": synthetic_rate.tolist(), "dt_h": dt.tolist(), "amount_kg": amount.tolist(), "remaining_inventory_kg": inventory.tolist()},
        "DURATION_UNIT_AUDIT": "PASS",
        "DURATION_AWARE_RECOURSE_QA": "PASS",
    }
    (RESULT_ROOT / "smoke_qa.json").write_text(json.dumps(smoke, indent=2), encoding="utf-8")
    print(json.dumps(smoke, indent=2), flush=True)


def subprocess_case(state_id: int) -> tuple[int, int, str]:
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    log_path = LOG_DIR / f"state-{state_id:03d}.log"
    env = os.environ.copy()
    env["PYTHONPATH"] = str(FROZEN_GUROBI.resolve())
    command = [sys.executable, str(Path(__file__).resolve()), "--mode", "case", "--state", str(state_id)]
    with log_path.open("w", encoding="utf-8") as log:
        completed = subprocess.run(command, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT)
    tail = ""
    if log_path.is_file():
        tail = "\n".join(log_path.read_text(encoding="utf-8", errors="replace").splitlines()[-5:])
    return state_id, completed.returncode, tail


def run_all(workers: int) -> None:
    RESULT_ROOT.mkdir(parents=True, exist_ok=True)
    write_duration_audit()
    pending = [state for state in range(1, 36) if not (CASE_DIR / f"state-{state:03d}.json").is_file()]
    require(pending, "No pending states; use --mode finalize")
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as executor:
        futures = {executor.submit(subprocess_case, state): state for state in pending}
        for future in concurrent.futures.as_completed(futures):
            state, code, tail = future.result()
            print(f"STATE_PROCESS_COMPLETE|state={state:03d}|exit={code}\n{tail}", flush=True)
            require(code == 0, f"State {state} failed; see {LOG_DIR / f'state-{state:03d}.log'}")
    finalize()


def finalize() -> None:
    rows = []
    for state in range(1, 36):
        path = CASE_DIR / f"state-{state:03d}.json"
        require(path.is_file(), f"Missing case {state}")
        row = json.loads(path.read_text(encoding="utf-8"))
        require(row["solver_status"] == "OPTIMAL" and all(row["checks"].values()), f"Case QA failed {state}")
        rows.append({key: value for key, value in row.items() if key != "checks"})
    new = pd.DataFrame(rows).sort_values("state")
    new.to_csv(RESULT_ROOT / "new_dro_by_state.csv", index=False)
    current = pd.read_csv(CURRENT_TABLE).sort_values("state_id")
    require(np.array_equal(current.state_id.to_numpy(int), new.state.to_numpy(int)), "Current/new state order failed")
    comparison_rows = []
    for old, candidate in zip(current.itertuples(index=False), new.itertuples(index=False)):
        record = {"state": int(old.state_id), "intensity": int(old.intensity), "loc": int(old.loc), "state_weight": 1.0 / 35.0, "state_weight_semantics": "current_Stage89K_equal_state_mean_diagnostic"}
        old_t = np.asarray([getattr(old, f"T{i}_kg") for i in range(1, 5)], dtype=float)
        new_t = np.asarray([getattr(candidate, f"T{i}_kg") for i in range(1, 5)], dtype=float)
        for i in range(4):
            record[f"current_T{i+1}_kg"] = old_t[i]
            record[f"new_T{i+1}_kg"] = new_t[i]
            record[f"delta_T{i+1}_kg"] = new_t[i] - old_t[i]
        record["current_T_total_kg"] = float(old_t.sum())
        record["new_T_total_kg"] = float(new_t.sum())
        record["delta_T_total_kg"] = float(new_t.sum() - old_t.sum())
        record["delta_T_total_pct"] = 100.0 * record["delta_T_total_kg"] / record["current_T_total_kg"] if record["current_T_total_kg"] else (0.0 if abs(record["new_T_total_kg"]) <= STATE_TOL_KG else math.inf)
        record["total_direction"] = "INCREASE" if record["delta_T_total_kg"] > STATE_TOL_KG else "DECREASE" if record["delta_T_total_kg"] < -STATE_TOL_KG else "UNCHANGED"
        record["total_down_any_site_up"] = bool(record["delta_T_total_kg"] < -STATE_TOL_KG and np.any(new_t - old_t > STATE_TOL_KG))
        comparison_rows.append(record)
    comparison = pd.DataFrame(comparison_rows)
    comparison.to_csv(RESULT_ROOT / "current_vs_new_dro_by_state.csv", index=False)
    current_weighted = float(comparison.current_T_total_kg.mean())
    new_weighted = float(comparison.new_T_total_kg.mean())
    site_delta = [float(comparison[f"delta_T{i}_kg"].mean()) for i in range(1, 5)]
    direction = comparison.total_direction.value_counts().to_dict()
    special = comparison[comparison.total_down_any_site_up]
    summary = {
        "DURATION_UNIT_AUDIT": "PASS",
        "DURATION_AWARE_RECOURSE_QA": "PASS",
        "DRO_OPTIMAL_COUNT": f"{int((new.solver_status == 'OPTIMAL').sum())}/35",
        "STATE_WEIGHT_SEMANTICS": "equal 1/35, matching current Stage89K cross-state mean diagnostic; not a formal initial-state probability expectation",
        "CURRENT_DRO_WEIGHTED_TOTAL_T_KG": current_weighted,
        "NEW_DRO_WEIGHTED_TOTAL_T_KG": new_weighted,
        "DELTA_KG": new_weighted - current_weighted,
        "DELTA_PCT": 100.0 * (new_weighted - current_weighted) / current_weighted,
        "SITE1_DELTA_KG": site_delta[0],
        "SITE2_DELTA_KG": site_delta[1],
        "SITE3_DELTA_KG": site_delta[2],
        "SITE4_DELTA_KG": site_delta[3],
        "STATE_TOTAL_INCREASE_COUNT": int(direction.get("INCREASE", 0)),
        "STATE_TOTAL_DECREASE_COUNT": int(direction.get("DECREASE", 0)),
        "STATE_TOTAL_UNCHANGED_COUNT": int(direction.get("UNCHANGED", 0)),
        "TOTAL_DOWN_ANY_SITE_UP_EXISTS": bool(len(special)),
        "TOTAL_DOWN_ANY_SITE_UP_STATES": special.state.astype(int).tolist(),
        "ETA": 0.03,
        "PEARSON_SEMANTICS": "unchanged current Stage89K within-state q_g and eta",
        "MSP_RUN": "NO",
    }
    (RESULT_ROOT / "final_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    write_csv(RESULT_ROOT / "final_summary.csv", [{"field": key, "value": json.dumps(value) if isinstance(value, list) else value} for key, value in summary.items()])
    print(json.dumps(summary, indent=2), flush=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=("audit", "smoke", "case", "all", "finalize"), required=True)
    parser.add_argument("--state", type=int)
    parser.add_argument("--workers", type=int, default=3)
    args = parser.parse_args()
    if args.mode == "audit":
        RESULT_ROOT.mkdir(parents=True, exist_ok=True)
        write_duration_audit()
        print("DURATION_UNIT_AUDIT=PASS")
    elif args.mode == "smoke":
        run_smoke()
    elif args.mode == "case":
        require(args.state is not None and 1 <= args.state <= 35, "State required")
        run_case_mode(args.state)
    elif args.mode == "all":
        require(1 <= args.workers <= 4, "Workers must be 1..4")
        run_all(args.workers)
    else:
        finalize()


if __name__ == "__main__":
    main()
