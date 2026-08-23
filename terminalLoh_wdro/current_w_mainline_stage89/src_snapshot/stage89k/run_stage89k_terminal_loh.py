from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import shutil
import time
from dataclasses import asdict, dataclass
from pathlib import Path

import gurobipy as gp
import numpy as np
import pandas as pd
from scipy import sparse
from scipy.io import loadmat


EXPECTED_GUROBI = (12, 0, 1)
CAPACITY = np.asarray([300.0, 200.0, 100.0, 200.0])
C_H2 = 32.5213675213675
M_H2 = 1283.205
ETA = 0.03
OBJECTIVE_SCALE = 1.0e5
ABS_GAP_TOL = 1.0e-4
REL_GAP_TOL = 1.0e-8
FEAS_TOL = 1.0e-9
OPT_TOL = 1.0e-9
QA_TOL = 1.0e-7


STATUS_NAMES = {
    gp.GRB.LOADED: "LOADED",
    gp.GRB.OPTIMAL: "OPTIMAL",
    gp.GRB.INFEASIBLE: "INFEASIBLE",
    gp.GRB.INF_OR_UNBD: "INF_OR_UNBD",
    gp.GRB.UNBOUNDED: "UNBOUNDED",
    gp.GRB.CUTOFF: "CUTOFF",
    gp.GRB.ITERATION_LIMIT: "ITERATION_LIMIT",
    gp.GRB.NODE_LIMIT: "NODE_LIMIT",
    gp.GRB.TIME_LIMIT: "TIME_LIMIT",
    gp.GRB.SOLUTION_LIMIT: "SOLUTION_LIMIT",
    gp.GRB.INTERRUPTED: "INTERRUPTED",
    gp.GRB.NUMERIC: "NUMERIC",
    gp.GRB.SUBOPTIMAL: "SUBOPTIMAL",
}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while block := handle.read(1024 * 1024):
            digest.update(block)
    return digest.hexdigest()


def status_name(status: int) -> str:
    return STATUS_NAMES.get(int(status), f"STATUS_{status}")


def configure_model(model: gp.Model, *, method: int | None = None, time_limit: float = 1800.0) -> None:
    model.Params.OutputFlag = 0
    model.Params.FeasibilityTol = FEAS_TOL
    model.Params.OptimalityTol = OPT_TOL
    model.Params.TimeLimit = time_limit
    model.Params.InfUnbdInfo = 1
    model.Params.Threads = 1
    if method is not None:
        model.Params.Method = method


@dataclass
class DualStructure:
    D: np.ndarray
    Aroad: np.ndarray
    Aelec: np.ndarray
    C: np.ndarray
    G: int
    K: int
    I: int
    N: int
    demand_linear: np.ndarray
    road_linear: np.ndarray
    elec_linear: np.ndarray
    g_u: np.ndarray
    g_r: np.ndarray
    k_r: np.ndarray
    i_r: np.ndarray
    g_e: np.ndarray
    k_e: np.ndarray
    i_e: np.ndarray
    road_demand_rows: np.ndarray
    elec_demand_rows: np.ndarray
    demand_values: np.ndarray
    road_cost: np.ndarray
    n_u: int
    n_r: int
    n_e: int
    fixed_matrix: sparse.csr_matrix
    fixed_rhs_base: np.ndarray
    fixed_sense: np.ndarray
    shortage_rows: sparse.csr_matrix
    total_demand: np.ndarray
    inventory_row_start: int
    fc_row_start: int


def build_structure(D: np.ndarray, Aroad: np.ndarray, Aelec: np.ndarray, C: np.ndarray, fc_cap: np.ndarray) -> DualStructure:
    D = np.asarray(D, dtype=float)
    Aroad = np.asarray(Aroad)
    Aelec = np.asarray(Aelec)
    C = np.asarray(C, dtype=float)
    require(D.ndim == 3 and D.shape[1] == 3, "Dres shape is invalid")
    G, K, N = D.shape
    I = 4
    expected = (G, K, I, N)
    require(Aroad.shape == expected and Aelec.shape == expected and C.shape == expected, "channel shape mismatch")
    require(np.isfinite(D).all() and (D >= 0).all(), "Dres values are invalid")
    require(np.isfinite(C[Aroad > 0.5]).all(), "reachable road C must be finite")
    require(np.asarray(fc_cap).shape == (I,) and np.isfinite(fc_cap).all() and (fc_cap > 0).all(), "FC cap invalid")

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
    require((road_demand_rows >= 0).all() and (elec_demand_rows >= 0).all(), "service arc lacks positive demand")
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
    values = np.ones(row.size, dtype=float)
    fixed_matrix = sparse.coo_matrix((values, (row, col)), shape=(n_rows, nvar)).tocsr()
    fixed_rhs_base = np.zeros(n_rows, dtype=float)
    fixed_rhs_base[:n_u] = demand_values
    fixed_rhs_base[fc_row_start:] = np.tile(fc_cap, G * K)
    fixed_sense = np.full(n_rows, b"<", dtype="S1")
    fixed_sense[:n_u] = b"="
    shortage_rows = sparse.coo_matrix(
        (np.ones(n_u), (g_u, n_r + n_e + np.arange(n_u))), shape=(G, nvar)
    ).tocsr()
    return DualStructure(
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


@dataclass
class FixedResult:
    status: str
    operating_loss: np.ndarray
    shortage_kg: np.ndarray
    road_service: np.ndarray
    elec_service: np.ndarray
    elec_service_slice: np.ndarray
    site_capacity_dual: np.ndarray
    max_demand_balance_error: float
    max_inventory_violation: float
    max_fc_violation: float
    objective_reconstruction_error: float
    runtime_sec: float


def unpack_service(structure: DualStructure, values: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    yr = values[: structure.n_r]
    ye = values[structure.n_r : structure.n_r + structure.n_e]
    u = values[structure.n_r + structure.n_e :]
    road = np.zeros((structure.G, structure.I))
    elec = np.zeros((structure.G, structure.I))
    elec_slice = np.zeros((structure.G, structure.K, structure.I))
    np.add.at(road, (structure.g_r, structure.i_r), yr)
    np.add.at(elec, (structure.g_e, structure.i_e), ye)
    np.add.at(elec_slice, (structure.g_e, structure.k_e, structure.i_e), ye)
    demand_service = np.bincount(structure.road_demand_rows, weights=yr, minlength=structure.n_u)
    demand_service += np.bincount(structure.elec_demand_rows, weights=ye, minlength=structure.n_u)
    shortage = np.bincount(structure.g_u, weights=u, minlength=structure.G)
    return shortage, road, elec, elec_slice, demand_service


def solve_fixed_recourse(structure: DualStructure, T: np.ndarray) -> FixedResult:
    started = time.perf_counter()
    T = np.asarray(T, dtype=float).reshape(4)
    rhs = structure.fixed_rhs_base.copy()
    rhs[structure.inventory_row_start : structure.fc_row_start] = np.tile(T, structure.G)
    objective = np.zeros(structure.fixed_matrix.shape[1])
    objective[structure.n_r + structure.n_e :] = M_H2 / OBJECTIVE_SCALE
    model = gp.Model("stage89k_fixed_recourse")
    configure_model(model)
    x = model.addMVar(objective.size, lb=0.0, ub=gp.GRB.INFINITY, obj=objective)
    model.ModelSense = gp.GRB.MINIMIZE
    constraints = model.addMConstr(structure.fixed_matrix, x, structure.fixed_sense, rhs)
    model.optimize()
    status = status_name(model.Status)
    require(model.Status == gp.GRB.OPTIMAL, f"fixed recourse failed: {status}")
    values = np.asarray(x.X, dtype=float)
    shortage, road, elec, elec_slice, demand_service = unpack_service(structure, values)
    loss = M_H2 * shortage
    pi = np.asarray(constraints.Pi, dtype=float)
    dual = pi[structure.inventory_row_start : structure.fc_row_start].reshape(structure.G, 4) * OBJECTIVE_SCALE
    result = FixedResult(
        status=status,
        operating_loss=loss,
        shortage_kg=shortage,
        road_service=road,
        elec_service=elec,
        elec_service_slice=elec_slice,
        site_capacity_dual=dual,
        max_demand_balance_error=float(np.max(np.abs(demand_service + values[structure.n_r + structure.n_e :] - structure.demand_values), initial=0.0)),
        max_inventory_violation=float(np.max(road + elec - T[None, :], initial=0.0)),
        max_fc_violation=float(np.max(elec_slice - FC_CAP[None, None, :], initial=0.0)),
        objective_reconstruction_error=abs(float(model.ObjVal) * OBJECTIVE_SCALE - float(loss.sum())),
        runtime_sec=time.perf_counter() - started,
    )
    model.dispose()
    return result


@dataclass
class AdversaryResult:
    worst_value: float
    probability: np.ndarray
    divergence: float
    probability_sum_residual: float
    minimum_probability: float
    effective_sample_size: float
    method: str


def solve_worst_probability(q: np.ndarray, loss: np.ndarray, eta: float, tolerance: float = 1.0e-12) -> AdversaryResult:
    q = np.asarray(q, dtype=float).reshape(-1)
    loss = np.asarray(loss, dtype=float).reshape(-1)
    require(q.size == loss.size and q.size > 0, "worst-probability vector size mismatch")
    require(np.isfinite(q).all() and (q > 0).all() and np.isfinite(loss).all(), "worst-probability input invalid")
    q = q / q.sum()
    eta = max(0.0, float(eta))
    R = q.size
    if R == 1:
        p = np.ones(1)
        method = "single_scenario_degenerate"
    elif eta <= tolerance:
        p = q.copy()
        method = "eta_zero_direct_saa"
    elif float(loss.max() - loss.min()) <= tolerance * max(1.0, float(np.abs(loss).max())):
        p = q.copy()
        method = "constant_loss_degenerate"
    else:
        maximum = float(loss.max())
        maximum_mask = np.abs(loss - maximum) <= tolerance * max(1.0, abs(maximum))
        q_maximum = float(q[maximum_mask].sum())
        eta_to_maximum_face = 1.0 / q_maximum - 1.0
        if eta >= eta_to_maximum_face - tolerance:
            p = np.zeros(R)
            p[maximum_mask] = q[maximum_mask] / q_maximum
            method = "maximum_loss_face"
        else:
            active = np.ones(R, dtype=bool)
            p = np.zeros(R)
            converged = False
            for _ in range(R + 1):
                qa = q[active]
                va = loss[active]
                qsum = float(qa.sum())
                minimum_divergence = 1.0 / qsum - 1.0
                remaining = eta - minimum_divergence
                require(remaining >= -100.0 * tolerance, "active-set minimum divergence exceeded eta")
                mean_value = float(np.dot(qa, va) / qsum)
                variance_numerator = float(np.dot(qa, (va - mean_value) ** 2))
                if variance_numerator <= tolerance:
                    pa = qa / qsum
                else:
                    scale = math.sqrt(max(0.0, remaining) / variance_numerator)
                    pa = qa / qsum + scale * qa * (va - mean_value)
                bad = pa < -100.0 * tolerance
                if not bad.any():
                    ids = np.flatnonzero(active)
                    p[ids] = np.maximum(pa, 0.0)
                    p /= p.sum()
                    converged = True
                    break
                ids = np.flatnonzero(active)
                active[ids[bad]] = False
            require(converged, "worst-probability KKT active set did not converge")
            method = "kkt_active_set"
    divergence = float(np.sum((p - q) ** 2 / q))
    residual = abs(float(p.sum()) - 1.0)
    minimum = float(p.min())
    require(residual <= 1.0e-10 and minimum >= -1.0e-10 and divergence <= eta + 1.0e-9, "worst-probability feasibility failed")
    return AdversaryResult(float(np.dot(p, loss)), p, divergence, residual, minimum, float(1.0 / np.dot(p, p)), method)


@dataclass
class Solution:
    status: str
    T: np.ndarray
    objective_value: float
    model_risk_value: float
    scenario_operating_loss: np.ndarray
    nominal_expected_recourse: float
    solve_runtime_sec: float
    lower_bound: float
    upper_bound: float
    absolute_gap: float
    relative_gap: float
    iteration_count: int
    cut_count: int
    fixed_result: FixedResult
    group_worst_probability: np.ndarray


def solve_saa(structure: DualStructure, q: np.ndarray) -> Solution:
    started = time.perf_counter()
    q = np.asarray(q, dtype=float).reshape(-1)
    q /= q.sum()
    G, I = structure.G, structure.I
    base_nvar = structure.fixed_matrix.shape[1]
    nvar = I + base_nvar
    objective = np.zeros(nvar)
    objective[:I] = C_H2 / OBJECTIVE_SCALE
    objective[I + structure.n_r + structure.n_e :] = q[structure.g_u] * M_H2 / OBJECTIVE_SCALE
    lower = np.zeros(nvar)
    upper = np.full(nvar, gp.GRB.INFINITY)
    upper[:I] = CAPACITY
    shifted = sparse.hstack((sparse.csr_matrix((structure.fixed_matrix.shape[0], I)), structure.fixed_matrix), format="lil")
    for g in range(G):
        for i in range(I):
            shifted[structure.inventory_row_start + g * I + i, i] = -1.0
    matrix = shifted.tocsr()
    rhs = structure.fixed_rhs_base.copy()
    model = gp.Model("stage89k_saa")
    configure_model(model, method=2)
    x = model.addMVar(nvar, lb=lower, ub=upper, obj=objective)
    model.ModelSense = gp.GRB.MINIMIZE
    model.addMConstr(matrix, x, structure.fixed_sense, rhs)
    model.optimize()
    status = status_name(model.Status)
    require(model.Status == gp.GRB.OPTIMAL, f"SAA failed: {status}")
    values = np.asarray(x.X, dtype=float)
    T = values[:I]
    shortage, road, elec, elec_slice, demand_service = unpack_service(structure, values[I:])
    loss = M_H2 * shortage
    fixed = FixedResult(
        status=status,
        operating_loss=loss,
        shortage_kg=shortage,
        road_service=road,
        elec_service=elec,
        elec_service_slice=elec_slice,
        site_capacity_dual=np.full((G, I), np.nan),
        max_demand_balance_error=float(np.max(np.abs(demand_service + values[I + structure.n_r + structure.n_e :] - structure.demand_values), initial=0.0)),
        max_inventory_violation=float(np.max(road + elec - T[None, :], initial=0.0)),
        max_fc_violation=float(np.max(elec_slice - FC_CAP[None, None, :], initial=0.0)),
        objective_reconstruction_error=abs(float(model.ObjVal) * OBJECTIVE_SCALE - (C_H2 * float(T.sum()) + float(np.dot(q, loss)))),
        runtime_sec=time.perf_counter() - started,
    )
    value = float(model.ObjVal) * OBJECTIVE_SCALE
    model.dispose()
    nominal = float(np.dot(q, loss))
    return Solution(status, T, value, nominal, loss, nominal, time.perf_counter() - started, value, value, 0.0, 0.0, 1, 0, fixed, q.copy())


def solve_master(points: np.ndarray, risks: np.ndarray, gradients: np.ndarray) -> tuple[np.ndarray, float]:
    n_cuts = points.shape[0]
    matrix = sparse.csr_matrix(np.column_stack((-gradients, np.ones(n_cuts))))
    rhs = risks - np.einsum("ij,ij->i", gradients, points)
    objective = np.asarray([C_H2, C_H2, C_H2, C_H2, 1.0])
    model = gp.Model("stage89k_chi2_master")
    configure_model(model, time_limit=60.0)
    x = model.addMVar(5, lb=np.zeros(5), ub=np.asarray([*CAPACITY, gp.GRB.INFINITY]), obj=objective)
    model.ModelSense = gp.GRB.MINIMIZE
    model.addMConstr(matrix, x, np.full(n_cuts, b">", dtype="S1"), rhs)
    model.optimize()
    require(model.Status == gp.GRB.OPTIMAL, f"DRO master failed: {status_name(model.Status)}")
    values = np.asarray(x.X, dtype=float)
    objective_value = float(model.ObjVal)
    model.dispose()
    return values[:4], objective_value


def solve_dro(structure: DualStructure, q: np.ndarray, eta: float) -> Solution:
    started = time.perf_counter()
    q = np.asarray(q, dtype=float).reshape(-1)
    q /= q.sum()
    points: list[np.ndarray] = []
    risks: list[float] = []
    gradients: list[np.ndarray] = []
    objectives: list[float] = []
    losses: list[np.ndarray] = []
    probabilities: list[np.ndarray] = []
    fixed_results: list[FixedResult] = []
    best_upper = math.inf
    best_index = -1

    def evaluate_and_add(T: np.ndarray) -> None:
        nonlocal best_upper, best_index
        T = np.maximum(0.0, np.minimum(CAPACITY, np.asarray(T, dtype=float)))
        fixed = solve_fixed_recourse(structure, T)
        require(np.isfinite(fixed.site_capacity_dual).all(), "DRO capacity dual nonfinite")
        adversary = solve_worst_probability(q, fixed.operating_loss, eta)
        gradient = np.sum(adversary.probability[:, None] * fixed.site_capacity_dual, axis=0)
        require((gradient <= 1.0e-6).all(), "positive capacity subgradient")
        objective = C_H2 * float(T.sum()) + adversary.worst_value
        points.append(T.copy())
        risks.append(adversary.worst_value)
        gradients.append(gradient)
        objectives.append(objective)
        losses.append(fixed.operating_loss.copy())
        probabilities.append(adversary.probability.copy())
        fixed_results.append(fixed)
        if objective < best_upper:
            best_upper = objective
            best_index = len(points) - 1

    for initial in (np.zeros(4), 0.5 * CAPACITY, CAPACITY.copy()):
        evaluate_and_add(initial)
    lower_bound = -math.inf
    status = "ITERATION_LIMIT"
    iteration = 0
    for iteration in range(1, 151):
        require(time.perf_counter() - started < 7200.0, "DRO total time limit exceeded")
        point_array = np.vstack(points)
        candidate, lower_bound = solve_master(point_array, np.asarray(risks), np.vstack(gradients))
        absolute_gap = best_upper - lower_bound
        relative_gap = absolute_gap / max(1.0, abs(best_upper))
        print(f"DRO_ITER|iter={iteration}|cuts={len(points)}|LB={lower_bound:.12f}|UB={best_upper:.12f}|gap={absolute_gap:.9g}|rel={relative_gap:.9g}", flush=True)
        if absolute_gap <= ABS_GAP_TOL or relative_gap <= REL_GAP_TOL:
            status = "OPTIMAL"
            break
        distance = np.max(np.abs(point_array - candidate[None, :]), axis=1)
        require(not np.any(distance <= 1.0e-8), "DRO decomposition numerical stall")
        evaluate_and_add(candidate)
    absolute_gap = best_upper - lower_bound
    relative_gap = absolute_gap / max(1.0, abs(best_upper))
    require(status == "OPTIMAL" and best_index >= 0, f"DRO decomposition failed: {status}")
    return Solution(
        status,
        points[best_index],
        best_upper,
        risks[best_index],
        losses[best_index],
        float(np.dot(q, losses[best_index])),
        time.perf_counter() - started,
        lower_bound,
        best_upper,
        absolute_gap,
        relative_gap,
        iteration,
        len(points),
        fixed_results[best_index],
        probabilities[best_index],
    )


@dataclass
class LexResult:
    shortage_kg: np.ndarray
    road_service: np.ndarray
    elec_service: np.ndarray
    elec_service_slice: np.ndarray
    service_impedance: np.ndarray
    max_shortage_preservation_error: float
    max_demand_balance_error: float
    max_inventory_violation: float
    max_fc_violation: float
    primary_runtime_sec: float
    secondary_runtime_sec: float


def solve_lexicographic(structure: DualStructure, T: np.ndarray) -> LexResult:
    rhs = structure.fixed_rhs_base.copy()
    rhs[structure.inventory_row_start : structure.fc_row_start] = np.tile(np.asarray(T, dtype=float), structure.G)
    nvar = structure.fixed_matrix.shape[1]
    primary_obj = np.zeros(nvar)
    primary_obj[structure.n_r + structure.n_e :] = M_H2 / OBJECTIVE_SCALE
    started = time.perf_counter()
    primary = gp.Model("stage89k_lex_primary")
    configure_model(primary)
    x1 = primary.addMVar(nvar, lb=0.0, ub=gp.GRB.INFINITY, obj=primary_obj)
    primary.ModelSense = gp.GRB.MINIMIZE
    primary.addMConstr(structure.fixed_matrix, x1, structure.fixed_sense, rhs)
    primary.optimize()
    require(primary.Status == gp.GRB.OPTIMAL, f"lex primary failed: {status_name(primary.Status)}")
    values1 = np.asarray(x1.X, dtype=float)
    shortage_primary, _, _, _, _ = unpack_service(structure, values1)
    primary_runtime = time.perf_counter() - started
    primary.dispose()

    secondary_matrix = sparse.vstack((structure.fixed_matrix, structure.shortage_rows), format="csr")
    secondary_rhs = np.concatenate((rhs, shortage_primary))
    secondary_sense = np.concatenate((structure.fixed_sense, np.full(structure.G, b"=", dtype="S1")))
    secondary_obj = np.zeros(nvar)
    secondary_obj[: structure.n_r] = structure.road_cost / OBJECTIVE_SCALE
    started = time.perf_counter()
    secondary = gp.Model("stage89k_lex_secondary")
    configure_model(secondary)
    x2 = secondary.addMVar(nvar, lb=0.0, ub=gp.GRB.INFINITY, obj=secondary_obj)
    secondary.ModelSense = gp.GRB.MINIMIZE
    secondary.addMConstr(secondary_matrix, x2, secondary_sense, secondary_rhs)
    secondary.optimize()
    require(secondary.Status == gp.GRB.OPTIMAL, f"lex secondary failed: {status_name(secondary.Status)}")
    values = np.asarray(x2.X, dtype=float)
    shortage, road, elec, elec_slice, demand_service = unpack_service(structure, values)
    impedance = np.bincount(structure.g_r, weights=structure.road_cost * values[: structure.n_r], minlength=structure.G)
    result = LexResult(
        shortage,
        road,
        elec,
        elec_slice,
        impedance,
        float(np.max(np.abs(shortage - shortage_primary), initial=0.0)),
        float(np.max(np.abs(demand_service + values[structure.n_r + structure.n_e :] - structure.demand_values), initial=0.0)),
        float(np.max(road + elec - np.asarray(T)[None, :], initial=0.0)),
        float(np.max(elec_slice - FC_CAP[None, None, :], initial=0.0)),
        primary_runtime,
        time.perf_counter() - started,
    )
    secondary.dispose()
    return result


def load_context(repo: Path) -> tuple[pd.DataFrame, np.ndarray]:
    manifest = pd.read_csv(repo / "results/task-002-stage2b-b3-smoke/stage89j-topology-h2-dual-channel-w-candidate/run-001/candidate_bank_manifest.csv")
    fc = pd.read_csv(repo / "results/task-002-stage2b-b3-smoke/stage89j-topology-h2-dual-channel-w-candidate/run-001/fc_static_capacity_metadata.csv")
    require(len(manifest) == 35 and int(manifest.n_draws.sum()) == 525000 and int(manifest.n_exact_groups.sum()) == 457431, "Stage89J manifest count gate failed")
    require((manifest.gate == "PASS").all(), "Stage89J manifest gate not PASS")
    require(list(fc.site_index.astype(int)) == [1, 2, 3, 4], "FC metadata site order invalid")
    caps = fc.H_FC_cap_kg_per_slice.to_numpy(dtype=float)
    require(np.allclose(fc.fc_cap_kw, [300, 150, 120, 150]) and np.allclose(fc.eta_FC, 0.55) and np.allclose(fc.h2_lhv_kWh_per_kg, 33.33) and np.allclose(fc.official_slice_duration_h, 1.0), "FC metadata parameter gate failed")
    return manifest, caps


def audit_inputs(repo: Path, result_dir: Path) -> None:
    manifest, _ = load_context(repo)
    rows = []
    for row in manifest.itertuples(index=False):
        path = repo / row.candidate_bank_path
        exists = path.is_file()
        actual_bytes = path.stat().st_size if exists else -1
        actual_sha = sha256_file(path) if exists else ""
        data = loadmat(path, squeeze_me=True) if exists and actual_sha == row.candidate_bank_sha256 else {}
        schema_pass = bool(data) and all(name in data for name in ["Dres", "Aroad", "Aelec", "C", "q_g", "multiplicity", "groupId"])
        if schema_pass:
            q = np.asarray(data["q_g"], dtype=float).reshape(-1)
            schema_pass = (
                np.asarray(data["Dres"]).shape == (row.n_exact_groups, 3, 33)
                and np.asarray(data["Aroad"]).shape == (row.n_exact_groups, 3, 4, 33)
                and np.asarray(data["Aelec"]).shape == (row.n_exact_groups, 3, 4, 33)
                and np.asarray(data["C"]).shape == (row.n_exact_groups, 3, 4, 33)
                and q.size == row.n_exact_groups
                and abs(float(q.sum()) - 1.0) <= 1.0e-12
            )
        gate = exists and actual_bytes == row.candidate_bank_bytes and actual_sha == row.candidate_bank_sha256 and schema_pass
        rows.append(
            {
                "state": row.state_id,
                "intensity": row.intensity,
                "loc": row.loc,
                "n_draws": row.n_draws,
                "n_exact_groups": row.n_exact_groups,
                "expected_bytes": row.candidate_bank_bytes,
                "actual_bytes": actual_bytes,
                "expected_sha256": row.candidate_bank_sha256,
                "actual_sha256": actual_sha,
                "file_exists": int(exists),
                "schema_pass": int(schema_pass),
                "sha_pass": int(actual_sha == row.candidate_bank_sha256),
                "input_gate": "PASS" if gate else "FAIL",
            }
        )
    frame = pd.DataFrame(rows)
    frame.to_csv(result_dir / "candidate_bank_input_qa.csv", index=False)
    require(len(frame) == 35 and (frame.input_gate == "PASS").all(), "candidate bank input QA failed")


def json_ready(value):
    if isinstance(value, np.ndarray):
        return value.tolist()
    if isinstance(value, (np.floating, np.integer)):
        return value.item()
    raise TypeError(type(value).__name__)


def next_attempt(root: Path, state: int) -> Path:
    root.mkdir(parents=True, exist_ok=True)
    for attempt in range(1, 1000):
        path = root / f"state-{state:03d}.attempt-{attempt:03d}"
        if not path.exists():
            path.mkdir()
            return path
    raise RuntimeError("too many attempts")


def run_case(repo: Path, result_dir: Path, large_dir: Path, state: int, mode: str, phase: str) -> None:
    require(tuple(gp.gurobi.version()) == EXPECTED_GUROBI, f"requires gurobipy {EXPECTED_GUROBI}")
    manifest, caps = load_context(repo)
    global FC_CAP
    FC_CAP = caps
    selected = manifest[manifest.state_id == state]
    require(len(selected) == 1, "state manifest lookup failed")
    row = selected.iloc[0]
    payload = repo / row.candidate_bank_path
    require(payload.is_file() and payload.stat().st_size == int(row.candidate_bank_bytes), "payload bytes failed")
    require(sha256_file(payload) == row.candidate_bank_sha256, "payload SHA failed")
    data = loadmat(payload, squeeze_me=True)
    require(int(data["stateId"]) == state and int(data["originalR"]) == 15000, "payload identity failed")
    q = np.asarray(data["q_g"], dtype=float).reshape(-1)
    require((q > 0).all() and abs(float(q.sum()) - 1.0) <= 1.0e-12, "q_g QA failed")
    q /= q.sum()
    structure = build_structure(data["Dres"], data["Aroad"], data["Aelec"], data["C"], caps)
    require(structure.G == int(row.n_exact_groups), "support count mismatch")
    case_root = large_dir / ("smoke_cases" if phase == "smoke" else "formal_cases") / mode.lower()
    final_dir = case_root / f"state-{state:03d}"
    if final_dir.is_dir() and (final_dir / "CASE_COMPLETE.txt").is_file():
        print(f"CASE_SKIP|phase={phase}|mode={mode}|state={state}", flush=True)
        return
    attempt = next_attempt(case_root, state)
    started = time.perf_counter()
    print(f"CASE_START|phase={phase}|mode={mode}|state={state}|groups={structure.G}|road_arcs={structure.n_r}|elec_arcs={structure.n_e}", flush=True)
    solution = solve_saa(structure, q) if mode == "SAA" else solve_dro(structure, q, ETA)
    fixed = solve_fixed_recourse(structure, solution.T)
    adversary = solve_worst_probability(q, fixed.operating_loss, 0.0 if mode == "SAA" else ETA)
    lex = solve_lexicographic(structure, solution.T)
    inventory = lex.road_service + lex.elec_service
    inv_binding = np.abs(inventory - solution.T[None, :]) <= 1.0e-6
    fc_binding = np.abs(lex.elec_service_slice - caps[None, None, :]) <= 1.0e-6
    objective_rebuild = C_H2 * float(solution.T.sum()) + adversary.worst_value
    checks = {
        "status_optimal": solution.status == "OPTIMAL",
        "T_caps": bool((solution.T >= -QA_TOL).all() and (solution.T <= CAPACITY + QA_TOL).all()),
        "service_nonnegative": bool((lex.road_service >= -QA_TOL).all() and (lex.elec_service >= -QA_TOL).all()),
        "inventory": lex.max_inventory_violation <= QA_TOL,
        "fc_capacity": lex.max_fc_violation <= QA_TOL,
        "demand_balance": lex.max_demand_balance_error <= QA_TOL,
        "shortage_preserved": lex.max_shortage_preservation_error <= QA_TOL,
        "q_sum": abs(float(q.sum()) - 1.0) <= 1.0e-12,
        "p_sum": adversary.probability_sum_residual <= 1.0e-10,
        "pearson": adversary.divergence <= (0.0 if mode == "SAA" else ETA) + 1.0e-9,
        "objective_finite": math.isfinite(solution.objective_value),
        "objective_rebuild": abs(solution.objective_value - objective_rebuild) <= 1.0e-3,
        "gap": solution.absolute_gap <= ABS_GAP_TOL + 1.0e-9 or solution.relative_gap <= REL_GAP_TOL + 1.0e-12,
    }
    require(all(checks.values()), f"case QA failed: {[key for key, value in checks.items() if not value]}")
    q_road = float(np.dot(q, lex.road_service.sum(axis=1)))
    q_elec = float(np.dot(q, lex.elec_service.sum(axis=1)))
    q_short = float(np.dot(q, lex.shortage_kg))
    total_service = q_road + q_elec
    summary = {
        "phase": phase,
        "mode": mode,
        "state": state,
        "intensity": int(row.intensity),
        "loc": int(row["loc"]),
        "lfw": int(row.lfw),
        "eta": 0.0 if mode == "SAA" else ETA,
        "groups": structure.G,
        "T": solution.T,
        "T_total": float(solution.T.sum()),
        "objective": solution.objective_value,
        "nominal_expected_recourse": solution.nominal_expected_recourse,
        "worst_expected_recourse": adversary.worst_value,
        "LB": solution.lower_bound,
        "UB": solution.upper_bound,
        "absolute_gap": solution.absolute_gap,
        "relative_gap": solution.relative_gap,
        "iterations": solution.iteration_count,
        "cuts": solution.cut_count,
        "runtime_sec": time.perf_counter() - started,
        "q_sum": float(q.sum()),
        "p_sum": float(adversary.probability.sum()),
        "p_min": adversary.minimum_probability,
        "pearson_divergence": adversary.divergence,
        "adversary_method": adversary.method,
        "max_demand_balance_error": lex.max_demand_balance_error,
        "max_inventory_violation": lex.max_inventory_violation,
        "max_fc_violation": lex.max_fc_violation,
        "max_shortage_preservation_error": lex.max_shortage_preservation_error,
        "q_weighted_shortage_kg": q_short,
        "q_weighted_road_service_kg": q_road,
        "q_weighted_electrical_service_kg": q_elec,
        "road_service_share": q_road / total_service if total_service > 0 else 0.0,
        "electrical_service_share": q_elec / total_service if total_service > 0 else 0.0,
        "fc_binding_frequency": float(np.sum(q[:, None, None] * fc_binding) / (structure.K * structure.I)),
        "fc_binding_any_share": float(np.dot(q, fc_binding.any(axis=(1, 2)))),
        "inventory_binding_frequency": float(np.sum(q[:, None] * inv_binding) / structure.I),
        "inventory_binding_by_site": np.sum(q[:, None] * inv_binding, axis=0),
        "checks": checks,
        "solver_status": solution.status,
    }
    np.savez_compressed(
        attempt / "case_arrays.npz",
        q=q,
        p=adversary.probability,
        shortage_kg=lex.shortage_kg,
        road_service_kg=lex.road_service,
        electrical_service_kg=lex.elec_service,
        electrical_service_slice_kg=lex.elec_service_slice,
        inventory_binding=inv_binding,
        fc_binding=fc_binding,
    )
    (attempt / "result.json").write_text(json.dumps(summary, indent=2, default=json_ready), encoding="utf-8")
    (attempt / "CASE_COMPLETE.txt").write_text(f"status=PASS\nphase={phase}\nmode={mode}\nstate={state}\npid={os.getpid()}\n", encoding="ascii")
    require(not final_dir.exists(), "refusing to overwrite final case")
    attempt.rename(final_dir)
    print(f"CASE_COMPLETE|phase={phase}|mode={mode}|state={state}|runtime={time.perf_counter()-started:.3f}", flush=True)


def read_case(path: Path) -> dict:
    return json.loads((path / "result.json").read_text(encoding="utf-8"))


def finalize(repo: Path, result_dir: Path, large_dir: Path) -> None:
    records = []
    for mode in ("SAA", "DRO"):
        for state in range(1, 36):
            path = large_dir / "formal_cases" / mode.lower() / f"state-{state:03d}"
            require(path.is_dir() and (path / "CASE_COMPLETE.txt").is_file(), f"formal case missing: {mode} state {state}")
            record = read_case(path)
            require(record["solver_status"] == "OPTIMAL" and all(record["checks"].values()), f"formal case QA failed: {mode} state {state}")
            records.append(record)
    frame = pd.DataFrame(records)
    status_rows = []
    inventory_rows = []
    fc_rows = []
    prob_rows = []
    diagnostic_rows = []
    for r in records:
        status_rows.append(
            {
                "state": r["state"], "intensity": r["intensity"], "loc": r["loc"], "mode": r["mode"],
                "solver_status": r["solver_status"], "objective": r["objective"], "T1": r["T"][0], "T2": r["T"][1], "T3": r["T"][2], "T4": r["T"][3], "T_total": r["T_total"],
                "LB": r["LB"], "UB": r["UB"], "absolute_gap": r["absolute_gap"], "relative_gap": r["relative_gap"], "iterations": r["iterations"], "cuts": r["cuts"], "runtime_sec": r["runtime_sec"], "case_pass": 1,
            }
        )
        inventory_rows.append(
            {
                "state": r["state"], "intensity": r["intensity"], "loc": r["loc"], "mode": r["mode"], "T1": r["T"][0], "T2": r["T"][1], "T3": r["T"][2], "T4": r["T"][3],
                "max_inventory_violation_kg": r["max_inventory_violation"], "binding_share_site1": r["inventory_binding_by_site"][0], "binding_share_site2": r["inventory_binding_by_site"][1], "binding_share_site3": r["inventory_binding_by_site"][2], "binding_share_site4": r["inventory_binding_by_site"][3], "inventory_qa": "PASS",
            }
        )
        fc_rows.append(
            {
                "state": r["state"], "intensity": r["intensity"], "loc": r["loc"], "mode": r["mode"], "fc_cap_site1": FC_CAP[0], "fc_cap_site2": FC_CAP[1], "fc_cap_site3": FC_CAP[2], "fc_cap_site4": FC_CAP[3],
                "max_fc_violation_kg": r["max_fc_violation"], "fc_binding_frequency": r["fc_binding_frequency"], "fc_binding_any_share": r["fc_binding_any_share"], "fc_capacity_qa": "PASS",
            }
        )
        prob_rows.append(
            {
                "state": r["state"], "intensity": r["intensity"], "loc": r["loc"], "mode": r["mode"], "eta": r["eta"], "q_g_sum": r["q_sum"], "p_g_sum": r["p_sum"], "p_g_min": r["p_min"], "pearson_divergence": r["pearson_divergence"], "adversary_method": r["adversary_method"], "probability_qa": "PASS",
            }
        )
        diagnostic_rows.append(
            {
                "state": r["state"], "intensity": r["intensity"], "loc": r["loc"], "mode": r["mode"], "q_weighted_shortage_kg": r["q_weighted_shortage_kg"], "q_weighted_road_service_kg": r["q_weighted_road_service_kg"], "q_weighted_electrical_service_kg": r["q_weighted_electrical_service_kg"], "road_service_share": r["road_service_share"], "electrical_service_share": r["electrical_service_share"], "fc_binding_frequency": r["fc_binding_frequency"], "fc_binding_any_share": r["fc_binding_any_share"], "inventory_binding_frequency": r["inventory_binding_frequency"], "inventory_binding_site1": r["inventory_binding_by_site"][0], "inventory_binding_site2": r["inventory_binding_by_site"][1], "inventory_binding_site3": r["inventory_binding_by_site"][2], "inventory_binding_site4": r["inventory_binding_by_site"][3],
            }
        )
    status = pd.DataFrame(status_rows).sort_values(["state", "mode"])
    status.to_csv(result_dir / "solver_status_by_state.csv", index=False)
    pd.DataFrame(inventory_rows).sort_values(["state", "mode"]).to_csv(result_dir / "inventory_qa.csv", index=False)
    pd.DataFrame(fc_rows).sort_values(["state", "mode"]).to_csv(result_dir / "fc_capacity_qa.csv", index=False)
    pd.DataFrame(prob_rows).sort_values(["state", "mode"]).to_csv(result_dir / "probability_dro_qa.csv", index=False)
    diagnostics = pd.DataFrame(diagnostic_rows).sort_values(["state", "mode"])
    diagnostics.to_csv(result_dir / "dual_channel_service_diagnostics.csv", index=False)

    old_saa = pd.read_csv(repo / "terminalLoh_wdro/current_w_mainline_stage88/msp_bridge/terminal_loh_stage88_saa_cap200.csv")
    old_dro = pd.read_csv(repo / "terminalLoh_wdro/current_w_mainline_stage88/msp_bridge/terminal_loh_stage88_dro_eta003_cap200.csv")
    new_saa = status[status["mode"] == "SAA"].set_index("state")
    new_dro = status[status["mode"] == "DRO"].set_index("state")
    comparisons = []
    for state in range(1, 36):
        osaa = old_saa[old_saa.state_id == state].iloc[0]
        odro = old_dro[old_dro.state_id == state].iloc[0]
        nsaa = new_saa.loc[state]
        ndro = new_dro.loc[state]
        row = {"state": state, "intensity": int(osaa.intensity), "loc": int(osaa["loc"])}
        for label, old, new in (("saa", osaa, nsaa), ("dro", odro, ndro)):
            old_t = np.asarray([old[f"T{i}_kg"] for i in range(1, 5)], dtype=float)
            new_t = np.asarray([new[f"T{i}"] for i in range(1, 5)], dtype=float)
            for i in range(4):
                row[f"old_{label}_T{i+1}"] = old_t[i]
                row[f"new_{label}_T{i+1}"] = new_t[i]
                row[f"delta_{label}_T{i+1}"] = new_t[i] - old_t[i]
            old_total = float(old_t.sum())
            delta = float(new_t.sum() - old_total)
            row[f"old_{label}_T_total"] = old_total
            row[f"new_{label}_T_total"] = float(new_t.sum())
            row[f"delta_{label}_total"] = delta
            row[f"delta_{label}_percent"] = 100.0 * delta / old_total if old_total > 0 else np.nan
        comparisons.append(row)
    comparison = pd.DataFrame(comparisons)
    comparison.to_csv(result_dir / "terminalLoh_old_vs_new_by_state.csv", index=False)

    intensity_rows = []
    for intensity in range(2, 7):
        subset = comparison[comparison.intensity == intensity]
        row = {"intensity": intensity, "state_count": len(subset)}
        for mode in ("saa", "dro"):
            row[f"old_{mode}_mean_T_total"] = subset[f"old_{mode}_T_total"].mean()
            row[f"new_{mode}_mean_T_total"] = subset[f"new_{mode}_T_total"].mean()
            row[f"new_{mode}_median_T_total"] = subset[f"new_{mode}_T_total"].median()
            row[f"absolute_change_{mode}_mean_T_total"] = row[f"new_{mode}_mean_T_total"] - row[f"old_{mode}_mean_T_total"]
            row[f"percentage_change_{mode}_mean_T_total"] = 100.0 * row[f"absolute_change_{mode}_mean_T_total"] / row[f"old_{mode}_mean_T_total"] if row[f"old_{mode}_mean_T_total"] > 0 else np.nan
            for site in range(1, 5):
                row[f"new_{mode}_mean_T{site}"] = subset[f"new_{mode}_T{site}"].mean()
                row[f"old_{mode}_mean_T{site}"] = subset[f"old_{mode}_T{site}"].mean()
        intensity_rows.append(row)
    intensity = pd.DataFrame(intensity_rows)
    intensity.to_csv(result_dir / "terminalLoh_intensity_summary.csv", index=False)

    make_plots(result_dir, comparison, intensity, diagnostics)
    write_large_output_manifest(repo, result_dir, large_dir)
    write_source_manifest(repo, result_dir, large_dir)
    means = {
        "old_saa_mean": float(comparison.old_saa_T_total.mean()),
        "new_saa_mean": float(comparison.new_saa_T_total.mean()),
        "old_dro_mean": float(comparison.old_dro_T_total.mean()),
        "new_dro_mean": float(comparison.new_dro_T_total.mean()),
        "mean_road": float(diagnostics.q_weighted_road_service_kg.mean()),
        "mean_elec": float(diagnostics.q_weighted_electrical_service_kg.mean()),
        "mean_shortage": float(diagnostics.q_weighted_shortage_kg.mean()),
        "fc_binding_observed": bool((diagnostics.fc_binding_frequency > 0).any()),
    }
    (result_dir / "final_metrics.json").write_text(json.dumps(means, indent=2), encoding="utf-8")
    (result_dir / "README.md").write_text(
        "# Stage-89K TerminalLOH dual-channel candidate\n\n"
        "Status: **FORMAL_TERMINALLOH_CANDIDATE**; **NOT CURRENT_TERMINALLOH**, **NOT CURRENT_W_MAINLINE**, **NOT MSP-ACCEPTED**.\n\n"
        "## Outcome\n\n"
        "All 35 SAA and 35 Pearson chi-square DRO cases are optimal and pass inventory, FC-capacity, q/p probability, ambiguity-radius, demand-balance, objective reconstruction, and certified gap gates. Stage-89J was read without resampling or modification. The reported change is the **FULL CANDIDATE EFFECT** and is not attributed to any single mechanism. FA-MSP and OOS were not run.\n\n"
        f"- Stage88/Stage89K SAA mean T total: `{means['old_saa_mean']:.6f}/{means['new_saa_mean']:.6f} kg`.\n"
        f"- Stage88/Stage89K DRO mean T total: `{means['old_dro_mean']:.6f}/{means['new_dro_mean']:.6f} kg`.\n"
        f"- Mean q-weighted road/electrical/shortage over 70 mode-state cases: `{means['mean_road']:.6f}/{means['mean_elec']:.6f}/{means['mean_shortage']:.6f} kg`.\n"
        f"- FC capacity binding observed: `{'YES' if means['fc_binding_observed'] else 'NO'}`.\n\n"
        "## Runs and artifacts\n\n"
        "`run-001` is preserved as failed after a post-solve Pandas result-serialization error in the first smoke case; it never entered DRO or the formal solve. This accepted candidate is `run-002`, which restarted input SHA/schema QA and all six smoke cases.\n\n"
        f"Large per-case arrays and checkpoint artifacts: `{large_dir.relative_to(repo).as_posix()}`. `large_output_manifest.csv` records every large/checkpoint file's path, bytes, SHA-256 and logical row count.\n",
        encoding="utf-8",
    )


def make_plots(result_dir: Path, comparison: pd.DataFrame, intensity: pd.DataFrame, diagnostics: pd.DataFrame) -> None:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    plot_dir = result_dir / "plots"
    plot_dir.mkdir(exist_ok=True)
    x = comparison.state.to_numpy()
    fig, ax = plt.subplots(figsize=(10, 5))
    ax.plot(x, comparison.old_saa_T_total, label="Stage88 SAA", linewidth=1.5)
    ax.plot(x, comparison.new_saa_T_total, label="Stage89K SAA", linewidth=1.5)
    ax.plot(x, comparison.old_dro_T_total, label="Stage88 DRO", linewidth=1.5)
    ax.plot(x, comparison.new_dro_T_total, label="Stage89K DRO", linewidth=1.5)
    ax.set(xlabel="State", ylabel="T total (kg)", title="Stage88 vs Stage89K T total by state")
    ax.grid(alpha=0.25); ax.legend(ncol=2); fig.tight_layout(); fig.savefig(plot_dir / "stage88_vs_stage89k_T_total_by_state.png", dpi=180); plt.close(fig)

    fig, ax = plt.subplots(figsize=(8, 5))
    ax.plot(intensity.intensity, intensity.new_saa_mean_T_total, marker="o", label="SAA mean")
    ax.plot(intensity.intensity, intensity.new_dro_mean_T_total, marker="o", label="DRO mean")
    ax.set(xlabel="Intensity", ylabel="Mean T total (kg)", title="Stage89K SAA vs DRO by intensity")
    ax.grid(alpha=0.25); ax.legend(); fig.tight_layout(); fig.savefig(plot_dir / "saa_vs_dro_T_total_by_intensity.png", dpi=180); plt.close(fig)

    fig, axes = plt.subplots(1, 2, figsize=(12, 5), sharey=True)
    for ax, mode in zip(axes, ("saa", "dro")):
        for site in range(1, 5):
            delta = intensity[f"new_{mode}_mean_T{site}"] - intensity[f"old_{mode}_mean_T{site}"]
            ax.plot(intensity.intensity, delta, marker="o", label=f"Site{site}")
        ax.axhline(0, color="black", linewidth=0.8)
        ax.set(title=mode.upper(), xlabel="Intensity", ylabel="Mean T change (kg)")
        ax.grid(alpha=0.25)
    axes[1].legend(); fig.suptitle("Site1-4 T change by intensity"); fig.tight_layout(); fig.savefig(plot_dir / "site_T_change_by_intensity.png", dpi=180); plt.close(fig)

    diag = diagnostics.groupby(["intensity", "mode"])[["road_service_share", "electrical_service_share"]].mean().reset_index()
    fig, axes = plt.subplots(1, 2, figsize=(10, 5), sharey=True)
    for ax, mode in zip(axes, ("SAA", "DRO")):
        part = diag[diag["mode"] == mode]
        ax.bar(part.intensity, part.road_service_share, label="Road")
        ax.bar(part.intensity, part.electrical_service_share, bottom=part.road_service_share, label="Electrical")
        ax.set(title=mode, xlabel="Intensity", ylabel="Mean service share", ylim=(0, 1.05))
    axes[1].legend(); fig.suptitle("Road vs electrical service share"); fig.tight_layout(); fig.savefig(plot_dir / "road_vs_electrical_service_share.png", dpi=180); plt.close(fig)


def write_source_manifest(repo: Path, result_dir: Path, large_dir: Path) -> None:
    paths = [
        result_dir / "run_stage89k_terminal_loh.py",
        result_dir / "stage88_terminalLoh_semantics_audit.md",
        repo / "terminalLoh_wdro/current_w_mainline_stage88/src_snapshot/terminalLoh_wdro/src/run_step04CC6_35state_case.py",
        repo / "terminalLoh_wdro/current_w_mainline_stage88/src_snapshot/terminalLoh_wdro/src/run_stage88a_terminal_loh_case.py",
        repo / "results/task-002-stage2b-b3-smoke/stage89j-topology-h2-dual-channel-w-candidate/run-001/candidate_bank_manifest.csv",
        repo / "results/task-002-stage2b-b3-smoke/stage89j-topology-h2-dual-channel-w-candidate/run-001/fc_static_capacity_metadata.csv",
        repo / "results/task-002-stage2b-b3-smoke/topology-h2-dual-channel-minimal-model/run-006/shared_inventory_semantics_audit.md",
    ]
    rows = []
    for path in paths:
        rows.append({"path": path.relative_to(repo).as_posix(), "bytes": path.stat().st_size, "sha256": sha256_file(path), "role": "Stage89K source/input lineage"})
    for path in sorted(large_dir.rglob("CASE_COMPLETE.txt")):
        rows.append({"path": path.relative_to(repo).as_posix(), "bytes": path.stat().st_size, "sha256": sha256_file(path), "role": "formal/smoke checkpoint completion marker"})
    pd.DataFrame(rows).to_csv(result_dir / "source_manifest.csv", index=False)


def write_large_output_manifest(repo: Path, result_dir: Path, large_dir: Path) -> None:
    rows = []
    for path in sorted(large_dir.rglob("*")):
        if not path.is_file() or path.parent.name == "process_logs":
            continue
        logical_rows = ""
        if path.name == "case_arrays.npz":
            with np.load(path) as data:
                logical_rows = int(np.asarray(data["q"]).size)
        elif path.name in {"result.json", "CASE_COMPLETE.txt"}:
            logical_rows = 1
        rows.append(
            {
                "path": path.relative_to(repo).as_posix(),
                "bytes": path.stat().st_size,
                "sha256": sha256_file(path),
                "logical_rows": logical_rows,
                "role": "Stage89K smoke/formal case output or completion checkpoint",
            }
        )
    require(len(rows) == 76 * 3, "large output manifest expected 76 cases x 3 files")
    pd.DataFrame(rows).to_csv(result_dir / "large_output_manifest.csv", index=False)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["audit-input", "case", "finalize"])
    parser.add_argument("--repo", required=True)
    parser.add_argument("--result-dir", required=True)
    parser.add_argument("--large-dir", required=True)
    parser.add_argument("--state", type=int)
    parser.add_argument("--mode", choices=["SAA", "DRO"])
    parser.add_argument("--phase", choices=["smoke", "formal"], default="formal")
    args = parser.parse_args()
    repo = Path(args.repo).resolve()
    result_dir = Path(args.result_dir).resolve()
    large_dir = Path(args.large_dir).resolve()
    result_dir.mkdir(parents=True, exist_ok=True)
    large_dir.mkdir(parents=True, exist_ok=True)
    global FC_CAP
    _, FC_CAP = load_context(repo)
    if args.command == "audit-input":
        audit_inputs(repo, result_dir)
    elif args.command == "case":
        require(args.state is not None and args.mode is not None and 1 <= args.state <= 35, "case arguments missing")
        run_case(repo, result_dir, large_dir, args.state, args.mode, args.phase)
    else:
        finalize(repo, result_dir, large_dir)


if __name__ == "__main__":
    main()
