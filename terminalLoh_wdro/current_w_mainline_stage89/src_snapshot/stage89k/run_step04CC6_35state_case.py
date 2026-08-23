from __future__ import annotations

import argparse
import csv
import hashlib
import math
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path

import gurobipy as gp
import numpy as np
import pandas as pd
from scipy import sparse
from scipy.io import loadmat, savemat


EXPECTED_BRANCH = "task/002-stage2b-b3-smoke"
EXPECTED_HEAD = "6840dccd995cf87d9e348ce8090003c6a74b773d"
EXPECTED_GUROBI = (12, 0, 1)
CAPACITY = np.asarray([300.0, 200.0, 100.0, 150.0])
C_H2 = 32.5213675213675
M_H2 = 1283.205
ELECTRICITY_PER_KG = 18.3315
OBJECTIVE_SCALE = 1.0e5
ABS_GAP_TOL = 1.0e-4
REL_GAP_TOL = 1.0e-8


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


def git_output(repo: Path, *args: str) -> str:
    completed = subprocess.run(
        ["git", *args], cwd=repo, check=True, text=True, capture_output=True
    )
    return completed.stdout.strip()


def assert_git_gate(repo: Path) -> None:
    require(git_output(repo, "branch", "--show-current") == EXPECTED_BRANCH, "C6 branch gate failed")
    require(git_output(repo, "rev-parse", "HEAD") == EXPECTED_HEAD, "C6 local HEAD gate failed")
    require(git_output(repo, "rev-parse", "@{upstream}") == EXPECTED_HEAD, "C6 upstream gate failed")


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
    model.Params.FeasibilityTol = 1.0e-9
    model.Params.OptimalityTol = 1.0e-9
    model.Params.TimeLimit = time_limit
    model.Params.InfUnbdInfo = 1
    model.Params.Threads = 1
    if method is not None:
        model.Params.Method = method


@dataclass
class PeriodStructure:
    D: np.ndarray
    A: np.ndarray
    C: np.ndarray
    G: int
    K: int
    I: int
    N: int
    demand_linear: np.ndarray
    y_linear: np.ndarray
    g_u: np.ndarray
    k_u: np.ndarray
    g_y: np.ndarray
    k_y: np.ndarray
    i_y: np.ndarray
    y_demand_rows: np.ndarray
    demand_values: np.ndarray
    y_cost: np.ndarray
    n_u: int
    n_y: int
    fixed_matrix: sparse.csr_matrix
    fixed_rhs_base: np.ndarray
    fixed_sense: np.ndarray
    shortage_rows: sparse.csr_matrix
    total_demand: np.ndarray


def build_period_structure(D: np.ndarray, A: np.ndarray, C: np.ndarray) -> PeriodStructure:
    D = np.asarray(D, dtype=float)
    A = np.asarray(A)
    C = np.asarray(C, dtype=float)
    require(D.ndim == 3 and D.shape[1] == 3, "Prepared D shape is invalid")
    G, K, N = D.shape
    require(A.shape == (G, K, 4, N) and C.shape == A.shape, "Prepared A/C shape is invalid")
    require(np.isfinite(D).all() and (D >= 0).all(), "Prepared D values are invalid")
    require(np.isfinite(C[A > 0.5]).all(), "Reachable C values must be finite")
    I = 4

    demand_mask = D > 0
    y_mask = (A > 0.5) & demand_mask[:, :, None, :]
    demand_linear = np.flatnonzero(demand_mask.ravel(order="F"))
    y_linear = np.flatnonzero(y_mask.ravel(order="F"))
    g_u, k_u, _ = np.unravel_index(demand_linear, (G, K, N), order="F")
    g_y, k_y, i_y, n_y_sub = np.unravel_index(y_linear, (G, K, I, N), order="F")
    n_u = demand_linear.size
    n_y = y_linear.size
    demand_row_flat = np.full(G * K * N, -1, dtype=np.int64)
    demand_row_flat[demand_linear] = np.arange(n_u, dtype=np.int64)
    y_demand_linear = np.ravel_multi_index((g_y, k_y, n_y_sub), (G, K, N), order="F")
    y_demand_rows = demand_row_flat[y_demand_linear]
    require((y_demand_rows >= 0).all(), "Reachable service arc lacks a positive-demand row")

    c_eff = np.where((A > 0.5) & np.isfinite(C), C, 0.0)
    demand_values = D.ravel(order="F")[demand_linear]
    y_cost = c_eff.ravel(order="F")[y_linear]

    n_rows = n_u + G * I
    row = np.concatenate(
        [
            np.arange(n_u, dtype=np.int64),
            y_demand_rows,
            n_u + g_y * I + i_y,
        ]
    )
    col = np.concatenate(
        [
            n_y + np.arange(n_u, dtype=np.int64),
            np.arange(n_y, dtype=np.int64),
            np.arange(n_y, dtype=np.int64),
        ]
    )
    values = np.ones(row.size, dtype=float)
    fixed_matrix = sparse.coo_matrix((values, (row, col)), shape=(n_rows, n_y + n_u)).tocsr()
    fixed_rhs_base = np.zeros(n_rows, dtype=float)
    fixed_rhs_base[:n_u] = demand_values
    fixed_sense = np.full(n_rows, b"<", dtype="S1")
    fixed_sense[:n_u] = b"="
    shortage_rows = sparse.coo_matrix(
        (
            np.ones(n_u, dtype=float),
            (g_u, n_y + np.arange(n_u, dtype=np.int64)),
        ),
        shape=(G, n_y + n_u),
    ).tocsr()
    total_demand = D.sum(axis=(1, 2))
    return PeriodStructure(
        D=D,
        A=A,
        C=C,
        G=G,
        K=K,
        I=I,
        N=N,
        demand_linear=demand_linear,
        y_linear=y_linear,
        g_u=g_u,
        k_u=k_u,
        g_y=g_y,
        k_y=k_y,
        i_y=i_y,
        y_demand_rows=y_demand_rows,
        demand_values=demand_values,
        y_cost=y_cost,
        n_u=n_u,
        n_y=n_y,
        fixed_matrix=fixed_matrix,
        fixed_rhs_base=fixed_rhs_base,
        fixed_sense=fixed_sense,
        shortage_rows=shortage_rows,
        total_demand=total_demand,
    )


@dataclass
class FixedResult:
    status: str
    operating_loss: np.ndarray
    shortage_kg: np.ndarray
    site_service: np.ndarray
    site_capacity_dual: np.ndarray
    max_demand_balance_error: float
    max_site_capacity_violation: float
    objective_reconstruction_error: float
    runtime_sec: float


def solve_fixed_recourse(structure: PeriodStructure, T: np.ndarray, C_in_objective: bool) -> FixedResult:
    started = time.perf_counter()
    G, I = structure.G, structure.I
    T = np.asarray(T, dtype=float).reshape(I)
    rhs = structure.fixed_rhs_base.copy()
    rhs[structure.n_u :] = np.tile(T, G)
    objective = np.zeros(structure.n_y + structure.n_u, dtype=float)
    if C_in_objective:
        objective[: structure.n_y] = structure.y_cost / OBJECTIVE_SCALE
    objective[structure.n_y :] = M_H2 / OBJECTIVE_SCALE
    model = gp.Model("step04cc6_fixed_recourse")
    configure_model(model)
    x = model.addMVar(objective.size, lb=0.0, ub=gp.GRB.INFINITY, obj=objective)
    model.ModelSense = gp.GRB.MINIMIZE
    constraints = model.addMConstr(structure.fixed_matrix, x, structure.fixed_sense, rhs)
    model.optimize()
    status = status_name(model.Status)
    if model.Status != gp.GRB.OPTIMAL:
        model.dispose()
        raise RuntimeError(f"Fixed recourse failed: {status}")
    values = np.asarray(x.X, dtype=float)
    y = values[: structure.n_y]
    u = values[structure.n_y :]
    shortage = np.bincount(structure.g_u, weights=u, minlength=G)
    if C_in_objective:
        service_cost = np.bincount(structure.g_y, weights=structure.y_cost * y, minlength=G)
    else:
        service_cost = np.zeros(G, dtype=float)
    operating_loss = M_H2 * shortage + service_cost
    site_service = np.zeros((G, I), dtype=float)
    np.add.at(site_service, (structure.g_y, structure.i_y), y)
    demand_service = np.bincount(structure.y_demand_rows, weights=y, minlength=structure.n_u)
    pi = np.asarray(constraints.Pi, dtype=float)
    capacity_dual = pi[structure.n_u :].reshape(G, I) * OBJECTIVE_SCALE
    demand_error = float(np.max(np.abs(demand_service + u - structure.demand_values), initial=0.0))
    capacity_violation = float(np.max(site_service - T[None, :], initial=0.0))
    reconstruction = abs(float(model.ObjVal) * OBJECTIVE_SCALE - float(operating_loss.sum()))
    model.dispose()
    return FixedResult(
        status=status,
        operating_loss=operating_loss,
        shortage_kg=shortage,
        site_service=site_service,
        site_capacity_dual=capacity_dual,
        max_demand_balance_error=demand_error,
        max_site_capacity_violation=capacity_violation,
        objective_reconstruction_error=reconstruction,
        runtime_sec=time.perf_counter() - started,
    )


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
    require(q.size == loss.size and q.size > 0, "Worst-probability vector size mismatch")
    require(np.isfinite(q).all() and (q > 0).all() and np.isfinite(loss).all(), "Worst-probability input invalid")
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
            p = np.zeros(R, dtype=float)
            p[maximum_mask] = q[maximum_mask] / q_maximum
            method = "maximum_loss_face"
        else:
            active = np.ones(R, dtype=bool)
            p = np.zeros(R, dtype=float)
            converged = False
            for _ in range(R + 1):
                qa = q[active]
                va = loss[active]
                qsum = float(qa.sum())
                minimum_divergence = 1.0 / qsum - 1.0
                remaining = eta - minimum_divergence
                require(remaining >= -100.0 * tolerance, "Active-set minimum divergence exceeded eta")
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
            require(converged, "Worst-probability KKT active set did not converge")
            method = "kkt_active_set"
    divergence = float(np.sum((p - q) ** 2 / q))
    probability_sum_residual = abs(float(p.sum()) - 1.0)
    minimum_probability = float(p.min())
    require(
        probability_sum_residual <= 1.0e-10
        and minimum_probability >= -1.0e-10
        and divergence <= eta + 1.0e-9,
        "Worst-probability feasibility audit failed",
    )
    return AdversaryResult(
        worst_value=float(np.dot(p, loss)),
        probability=p,
        divergence=divergence,
        probability_sum_residual=probability_sum_residual,
        minimum_probability=minimum_probability,
        effective_sample_size=float(1.0 / np.dot(p, p)),
        method=method,
    )


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


def solve_saa(structure: PeriodStructure, q: np.ndarray) -> Solution:
    started = time.perf_counter()
    q = np.asarray(q, dtype=float).reshape(-1)
    q = q / q.sum()
    I, G = structure.I, structure.G
    nvar = I + structure.n_y + structure.n_u
    objective = np.zeros(nvar, dtype=float)
    objective[:I] = C_H2 / OBJECTIVE_SCALE
    objective[I + structure.n_y :] = q[structure.g_u] * M_H2 / OBJECTIVE_SCALE
    lower = np.zeros(nvar, dtype=float)
    upper = np.full(nvar, gp.GRB.INFINITY, dtype=float)
    upper[:I] = CAPACITY

    rows = np.concatenate(
        [
            np.arange(structure.n_u, dtype=np.int64),
            structure.y_demand_rows,
            structure.n_u + structure.g_y * I + structure.i_y,
            structure.n_u + np.tile(np.arange(G, dtype=np.int64) * I, I) + np.repeat(np.arange(I), G),
        ]
    )
    cols = np.concatenate(
        [
            I + structure.n_y + np.arange(structure.n_u, dtype=np.int64),
            I + np.arange(structure.n_y, dtype=np.int64),
            I + np.arange(structure.n_y, dtype=np.int64),
            np.repeat(np.arange(I, dtype=np.int64), G),
        ]
    )
    values = np.concatenate(
        [
            np.ones(structure.n_u + 2 * structure.n_y, dtype=float),
            -np.ones(G * I, dtype=float),
        ]
    )
    matrix = sparse.coo_matrix(
        (values, (rows, cols)), shape=(structure.n_u + G * I, nvar)
    ).tocsr()
    rhs = np.zeros(structure.n_u + G * I, dtype=float)
    rhs[: structure.n_u] = structure.demand_values
    sense = np.full(rhs.size, b"<", dtype="S1")
    sense[: structure.n_u] = b"="

    model = gp.Model("step04cc6_saa")
    configure_model(model, method=2)
    x = model.addMVar(nvar, lb=lower, ub=upper, obj=objective)
    model.ModelSense = gp.GRB.MINIMIZE
    constraints = model.addMConstr(matrix, x, sense, rhs)
    model.optimize()
    status = status_name(model.Status)
    require(model.Status == gp.GRB.OPTIMAL, f"SAA failed: {status}")
    values_x = np.asarray(x.X, dtype=float)
    T = values_x[:I]
    y = values_x[I : I + structure.n_y]
    u = values_x[I + structure.n_y :]
    shortage = np.bincount(structure.g_u, weights=u, minlength=G)
    operating_loss = M_H2 * shortage
    site_service = np.zeros((G, I), dtype=float)
    np.add.at(site_service, (structure.g_y, structure.i_y), y)
    demand_service = np.bincount(structure.y_demand_rows, weights=y, minlength=structure.n_u)
    pi = np.asarray(constraints.Pi, dtype=float)
    fixed_result = FixedResult(
        status=status,
        operating_loss=operating_loss,
        shortage_kg=shortage,
        site_service=site_service,
        site_capacity_dual=pi[structure.n_u :].reshape(G, I) * OBJECTIVE_SCALE,
        max_demand_balance_error=float(np.max(np.abs(demand_service + u - structure.demand_values), initial=0.0)),
        max_site_capacity_violation=float(np.max(site_service - T[None, :], initial=0.0)),
        objective_reconstruction_error=abs(
            float(model.ObjVal) * OBJECTIVE_SCALE
            - (C_H2 * float(T.sum()) + float(np.dot(q, operating_loss)))
        ),
        runtime_sec=time.perf_counter() - started,
    )
    objective_value = float(model.ObjVal) * OBJECTIVE_SCALE
    model.dispose()
    nominal = float(np.dot(q, operating_loss))
    return Solution(
        status=status,
        T=T,
        objective_value=objective_value,
        model_risk_value=nominal,
        scenario_operating_loss=operating_loss,
        nominal_expected_recourse=nominal,
        solve_runtime_sec=time.perf_counter() - started,
        lower_bound=objective_value,
        upper_bound=objective_value,
        absolute_gap=0.0,
        relative_gap=0.0,
        iteration_count=1,
        cut_count=0,
        fixed_result=fixed_result,
        group_worst_probability=q.copy(),
    )


def solve_master(points: np.ndarray, risks: np.ndarray, gradients: np.ndarray) -> tuple[np.ndarray, float]:
    n_cuts = points.shape[0]
    matrix = sparse.csr_matrix(np.column_stack((-gradients, np.ones(n_cuts))))
    rhs = risks - np.einsum("ij,ij->i", gradients, points)
    objective = np.asarray([C_H2, C_H2, C_H2, C_H2, 1.0])
    lower = np.zeros(5, dtype=float)
    upper = np.asarray([*CAPACITY, gp.GRB.INFINITY], dtype=float)
    model = gp.Model("step04cc6_chi2_master")
    configure_model(model, time_limit=60.0)
    x = model.addMVar(5, lb=lower, ub=upper, obj=objective)
    model.ModelSense = gp.GRB.MINIMIZE
    model.addMConstr(matrix, x, np.full(n_cuts, b">", dtype="S1"), rhs)
    model.optimize()
    status = status_name(model.Status)
    require(model.Status == gp.GRB.OPTIMAL, f"DRO master failed: {status}")
    values = np.asarray(x.X, dtype=float)
    objective_value = float(model.ObjVal)
    model.dispose()
    return values[:4], objective_value


def solve_dro(structure: PeriodStructure, q: np.ndarray, eta: float) -> Solution:
    started = time.perf_counter()
    q = np.asarray(q, dtype=float).reshape(-1)
    q = q / q.sum()
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
        fixed = solve_fixed_recourse(structure, T, C_in_objective=False)
        require(np.isfinite(fixed.site_capacity_dual).all(), "DRO recourse capacity dual is nonfinite")
        adversary = solve_worst_probability(q, fixed.operating_loss, eta)
        gradient = np.sum(adversary.probability[:, None] * fixed.site_capacity_dual, axis=0)
        require((gradient <= 1.0e-6).all(), "Positive capacity subgradient violates monotonicity")
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
        risk_array = np.asarray(risks)
        gradient_array = np.vstack(gradients)
        candidate, lower_bound = solve_master(point_array, risk_array, gradient_array)
        absolute_gap = best_upper - lower_bound
        relative_gap = absolute_gap / max(1.0, abs(best_upper))
        print(
            f"decomposition iter={iteration} cuts={len(points)} "
            f"LB={lower_bound:.12f} UB={best_upper:.12f} gap={absolute_gap:.9g} rel={relative_gap:.9g}",
            flush=True,
        )
        if absolute_gap <= ABS_GAP_TOL or relative_gap <= REL_GAP_TOL:
            status = "OPTIMAL"
            break
        distance = np.max(np.abs(point_array - candidate[None, :]), axis=1)
        require(not np.any(distance <= 1.0e-8), "DRO decomposition numerical stall")
        evaluate_and_add(candidate)
    absolute_gap = best_upper - lower_bound
    relative_gap = absolute_gap / max(1.0, abs(best_upper))
    if status == "ITERATION_LIMIT" and (absolute_gap <= ABS_GAP_TOL or relative_gap <= REL_GAP_TOL):
        status = "OPTIMAL"
    require(status == "OPTIMAL", f"DRO decomposition failed: {status}")
    require(best_index >= 0, "DRO decomposition has no incumbent")
    T = points[best_index]
    loss = losses[best_index]
    risk = risks[best_index]
    return Solution(
        status=status,
        T=T,
        objective_value=best_upper,
        model_risk_value=risk,
        scenario_operating_loss=loss,
        nominal_expected_recourse=float(np.dot(q, loss)),
        solve_runtime_sec=time.perf_counter() - started,
        lower_bound=lower_bound,
        upper_bound=best_upper,
        absolute_gap=absolute_gap,
        relative_gap=relative_gap,
        iteration_count=iteration,
        cut_count=len(points),
        fixed_result=fixed_results[best_index],
        group_worst_probability=probabilities[best_index],
    )


@dataclass
class LexResult:
    shortage_kg: np.ndarray
    service_distance: np.ndarray
    site_service: np.ndarray
    service_satisfaction_rate: np.ndarray
    secondary_objective_distance: float
    max_shortage_preservation_error: float
    primary_preservation_error: float
    max_demand_balance_error: float
    max_site_capacity_violation: float
    primary_reconstruction_error: float
    secondary_reconstruction_error: float
    primary_runtime_sec: float
    secondary_runtime_sec: float


def solve_lexicographic(structure: PeriodStructure, T: np.ndarray) -> LexResult:
    G = structure.G
    T = np.asarray(T, dtype=float).reshape(4)
    rhs = structure.fixed_rhs_base.copy()
    rhs[structure.n_u :] = np.tile(T, G)
    nvar = structure.n_y + structure.n_u
    primary_obj = np.zeros(nvar, dtype=float)
    primary_obj[structure.n_y :] = M_H2 / OBJECTIVE_SCALE

    primary_started = time.perf_counter()
    primary_model = gp.Model("step04cc6_lex_primary")
    configure_model(primary_model)
    x1 = primary_model.addMVar(nvar, lb=0.0, ub=gp.GRB.INFINITY, obj=primary_obj)
    primary_model.ModelSense = gp.GRB.MINIMIZE
    primary_model.addMConstr(structure.fixed_matrix, x1, structure.fixed_sense, rhs)
    primary_model.optimize()
    require(primary_model.Status == gp.GRB.OPTIMAL, f"Lex primary failed: {status_name(primary_model.Status)}")
    primary_values = np.asarray(x1.X, dtype=float)
    primary_u = primary_values[structure.n_y :]
    shortage_primary = np.bincount(structure.g_u, weights=primary_u, minlength=G)
    primary_obj_yuan = M_H2 * float(shortage_primary.sum())
    primary_reconstruction = abs(primary_obj_yuan - float(primary_model.ObjVal) * OBJECTIVE_SCALE)
    primary_runtime = time.perf_counter() - primary_started
    primary_model.dispose()

    secondary_matrix = sparse.vstack((structure.fixed_matrix, structure.shortage_rows), format="csr")
    secondary_rhs = np.concatenate((rhs, shortage_primary))
    secondary_sense = np.concatenate((structure.fixed_sense, np.full(G, b"=", dtype="S1")))
    secondary_obj = np.zeros(nvar, dtype=float)
    secondary_obj[: structure.n_y] = structure.y_cost / OBJECTIVE_SCALE
    secondary_started = time.perf_counter()
    secondary_model = gp.Model("step04cc6_lex_secondary")
    configure_model(secondary_model)
    x2 = secondary_model.addMVar(nvar, lb=0.0, ub=gp.GRB.INFINITY, obj=secondary_obj)
    secondary_model.ModelSense = gp.GRB.MINIMIZE
    secondary_model.addMConstr(secondary_matrix, x2, secondary_sense, secondary_rhs)
    secondary_model.optimize()
    require(secondary_model.Status == gp.GRB.OPTIMAL, f"Lex secondary failed: {status_name(secondary_model.Status)}")
    values = np.asarray(x2.X, dtype=float)
    y = values[: structure.n_y]
    u = values[structure.n_y :]
    shortage = np.bincount(structure.g_u, weights=u, minlength=G)
    service_distance = np.bincount(structure.g_y, weights=structure.y_cost * y, minlength=G)
    site_service = np.zeros((G, 4), dtype=float)
    np.add.at(site_service, (structure.g_y, structure.i_y), y)
    demand_service = np.bincount(structure.y_demand_rows, weights=y, minlength=structure.n_u)
    service_rate = np.ones(G, dtype=float)
    positive = structure.total_demand > 0
    service_rate[positive] = 1.0 - shortage[positive] / structure.total_demand[positive]
    service_rate = np.clip(service_rate, 0.0, 1.0)
    secondary_sum = float(service_distance.sum())
    secondary_reconstruction = abs(secondary_sum - float(secondary_model.ObjVal) * OBJECTIVE_SCALE)
    secondary_runtime = time.perf_counter() - secondary_started
    secondary_model.dispose()
    return LexResult(
        shortage_kg=shortage,
        service_distance=service_distance,
        site_service=site_service,
        service_satisfaction_rate=service_rate,
        secondary_objective_distance=secondary_sum,
        max_shortage_preservation_error=float(np.max(np.abs(shortage - shortage_primary), initial=0.0)),
        primary_preservation_error=abs(M_H2 * float(shortage.sum()) - primary_obj_yuan),
        max_demand_balance_error=float(np.max(np.abs(demand_service + u - structure.demand_values), initial=0.0)),
        max_site_capacity_violation=float(np.max(site_service - T[None, :], initial=0.0)),
        primary_reconstruction_error=primary_reconstruction,
        secondary_reconstruction_error=secondary_reconstruction,
        primary_runtime_sec=primary_runtime,
        secondary_runtime_sec=secondary_runtime,
    )


def percentile_nearest_rank(values: np.ndarray, probability: float) -> float:
    ordered = np.sort(np.asarray(values, dtype=float).reshape(-1))
    index = max(1, min(ordered.size, math.ceil(probability * ordered.size))) - 1
    return float(ordered[index])


def tail_stats(values: np.ndarray) -> dict[str, float]:
    values = np.asarray(values, dtype=float).reshape(-1)
    q95 = percentile_nearest_rank(values, 0.95)
    q99 = percentile_nearest_rank(values, 0.99)
    q995 = percentile_nearest_rank(values, 0.995)
    return {
        "q95": q95,
        "q99": q99,
        "q995": q995,
        "cvar95": float(values[values >= q95].mean()),
        "cvar99": float(values[values >= q99].mean()),
        "cvar995": float(values[values >= q995].mean()),
        "maximum": float(values.max()),
    }


def write_single_row_csv(path: Path, row: dict[str, object]) -> None:
    pd.DataFrame([row]).to_csv(path, index=False)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--work-dir", required=True)
    parser.add_argument("--case-id", required=True, type=int)
    args = parser.parse_args()
    started = time.perf_counter()
    require(tuple(gp.gurobi.version()) == EXPECTED_GUROBI, f"C6 requires gurobipy {EXPECTED_GUROBI}")
    work_dir = Path(args.work_dir).resolve()
    repo = work_dir.parents[3]
    assert_git_gate(repo)
    require(1 <= args.case_id <= 70, "case-id must be in 1:70")

    grid = pd.read_csv(work_dir / "solve_case_grid.csv")
    require(len(grid) == 70, "C6 case grid must contain 70 rows")
    selected = grid[grid.case_id == args.case_id]
    require(len(selected) == 1, "C6 case-grid lookup failed")
    row = selected.iloc[0]
    state_id = int(row.state_id)
    eta = float(row.eta)
    method_label = str(row.method_label)
    state_label = str(row.state_label)
    case_dir = work_dir / "optimization_cases" / f"case-{args.case_id:03d}"
    require(not case_dir.exists(), f"Refusing to overwrite C6 case directory: {case_dir}")
    case_dir.mkdir(parents=True)

    manifest = pd.read_csv(work_dir / "prepared_state_manifest.csv")
    payload_rows = manifest[manifest.state_id == state_id]
    require(len(payload_rows) == 1, "Prepared-state manifest lookup failed")
    manifest_row = payload_rows.iloc[0]
    payload_path = Path(str(manifest_row.local_payload_path))
    require(payload_path.is_file(), f"Prepared state payload is missing: {payload_path}")
    require(sha256_file(payload_path) == str(manifest_row.payload_sha256).lower(), "Prepared payload SHA-256 gate failed")
    data = loadmat(payload_path, squeeze_me=True, struct_as_record=False)
    require(int(data["stateId"]) == state_id and int(data["originalR"]) == 15000, "Prepared payload identity gate failed")
    require(int(data["groupCount"]) == np.asarray(data["qGroup"]).size, "Prepared group count mismatch")
    require(np.asarray(data["groupId"]).size == 15000, "Prepared record mapping count mismatch")
    require(np.allclose(np.asarray(data["Cap"], dtype=float).reshape(-1), CAPACITY, atol=1.0e-12), "Prepared capacity mismatch")
    require(abs(float(data["cH2"]) - C_H2) <= 1.0e-10, "Prepared c_H2 mismatch")
    require(abs(float(data["M"]) - M_H2) <= 1.0e-9, "Prepared M_H2 mismatch")
    require(abs(float(data["electricityPerKg"]) - ELECTRICITY_PER_KG) <= 1.0e-12, "Prepared EENS conversion mismatch")
    q_group = np.asarray(data["qGroup"], dtype=float).reshape(-1)
    q_group /= q_group.sum()
    require(abs(float(q_group.sum()) - 1.0) <= 1.0e-12 and (q_group > 0).all(), "Prepared group probability gate failed")
    structure = build_period_structure(data["DperiodGroup"], data["AperiodGroup"], data["CperiodGroup"])
    require(structure.G == int(data["groupCount"]), "Prepared structure group count mismatch")

    print(
        f"STEP04CC6_PYTHON_CASE_START|case={args.case_id}|state={state_id}|eta={eta:.12g}|groups={structure.G}",
        flush=True,
    )
    if eta <= 1.0e-14:
        solution = solve_saa(structure, q_group)
    else:
        require(abs(eta - 0.03) <= 1.0e-14, "C6 allows only eta=0 or eta=0.03")
        solution = solve_dro(structure, q_group, eta)

    audit_fixed = solve_fixed_recourse(structure, solution.T, C_in_objective=False)
    adversary = solve_worst_probability(q_group, audit_fixed.operating_loss, eta)
    group_id = np.asarray(data["groupId"], dtype=np.int64).reshape(-1) - 1
    multiplicity = np.asarray(data["multiplicity"], dtype=float).reshape(-1)
    require(group_id.min() >= 0 and group_id.max() < structure.G, "Prepared groupId is outside group range")
    record_probability = adversary.probability[group_id] / multiplicity[group_id]
    record_loss = audit_fixed.operating_loss[group_id]
    record_shortage_primary = record_loss / M_H2
    q_record = np.full(15000, 1.0 / 15000.0)
    record_divergence = float(np.sum((record_probability - q_record) ** 2 / q_record))
    probability_sum_residual = abs(float(record_probability.sum()) - 1.0)
    nominal_expected = float(np.dot(q_group, audit_fixed.operating_loss))
    worst_expected = float(np.dot(record_probability, record_loss))
    production_cost = C_H2 * float(solution.T.sum())
    robust_total = production_cost + worst_expected
    strong_duality_gap = abs(solution.model_risk_value - worst_expected)
    strong_duality_relative_gap = strong_duality_gap / max(1.0, abs(worst_expected))
    total_objective_gap = abs(solution.objective_value - robust_total)
    maximum_mechanical_audit = max(
        audit_fixed.max_demand_balance_error,
        max(0.0, audit_fixed.max_site_capacity_violation),
        probability_sum_residual,
        max(0.0, -float(record_probability.min())),
        max(0.0, record_divergence - eta),
        total_objective_gap,
    )
    audit_pass = (
        strong_duality_gap <= 1.0e-3
        and strong_duality_relative_gap <= 5.0e-6
        and total_objective_gap <= 1.0e-3
        and total_objective_gap / max(1.0, abs(robust_total)) <= 5.0e-6
        and probability_sum_residual <= 1.0e-10
        and float(record_probability.min()) >= -1.0e-10
        and record_divergence <= eta + 1.0e-8
        and audit_fixed.max_demand_balance_error <= 1.0e-7
        and audit_fixed.max_site_capacity_violation <= 1.0e-7
    )
    require(audit_pass, "C6 independent probability/mechanical audit failed")

    lex = solve_lexicographic(structure, solution.T)
    record_shortage = lex.shortage_kg[group_id]
    record_demand = structure.total_demand[group_id]
    record_service_rate = lex.service_satisfaction_rate[group_id]
    shortage_stats = tail_stats(record_shortage)
    mean_shortage = float(record_shortage.mean())
    mean_eens = mean_shortage * ELECTRICITY_PER_KG
    positive_shortage_probability = float(np.mean(record_shortage > 1.0e-10))
    service_rate = float(record_service_rate.mean())
    aggregate_service_rate = 1.0 - float(record_shortage.sum()) / max(float(record_demand.sum()), np.finfo(float).eps)
    nominal_outage_loss = M_H2 * mean_shortage
    nominal_economic_total = production_cost + nominal_outage_loss
    secondary_expected = float(np.dot(q_group, lex.service_distance))
    binding = np.abs(solution.T - CAPACITY) <= 1.0e-6

    primary_consistency = abs(solution.objective_value - (production_cost + worst_expected))
    fixed_consistency = abs(nominal_expected - nominal_outage_loss)
    lex_residual = max(
        lex.max_demand_balance_error,
        max(0.0, lex.max_site_capacity_violation),
        lex.max_shortage_preservation_error,
        lex.primary_reconstruction_error / max(1.0, M_H2 * float(lex.shortage_kg.sum())),
        lex.secondary_reconstruction_error / max(1.0, lex.secondary_objective_distance),
    )
    maximum_residual = max(maximum_mechanical_audit, lex_residual)
    gap_pass = solution.absolute_gap <= ABS_GAP_TOL + 1.0e-9 or solution.relative_gap <= REL_GAP_TOL + 1.0e-12
    eta_zero_pass = eta > 1.0e-14 or adversary.method == "eta_zero_direct_saa"
    certificate_pass = (
        solution.status == "OPTIMAL"
        and gap_pass
        and audit_pass
        and strong_duality_gap <= 1.0e-3
        and probability_sum_residual <= 1.0e-10
        and float(record_probability.min()) >= -1.0e-10
        and record_divergence <= eta + 1.0e-8
        and primary_consistency <= 1.0e-3
        and fixed_consistency <= 1.0e-5
        and lex.max_shortage_preservation_error <= 1.0e-7
        and lex.primary_preservation_error <= 1.0e-3
        and lex_residual <= 1.0e-7
        and abs(mean_eens - mean_shortage * ELECTRICITY_PER_KG) <= 1.0e-9
        and eta_zero_pass
    )
    require(certificate_pass, "C6 case certificate failed")

    result_row: dict[str, object] = {
        "case_id": args.case_id,
        "state_id": state_id,
        "state_label": state_label,
        "intensity": int(data["a0"]),
        "loc": int(data["loc0"]),
        "lfw": int(data["lfw0"]),
        "method_label": method_label,
        "eta": eta,
        "scenario_count": 15000,
        "exact_group_count": structure.G,
        "T1_kg": solution.T[0],
        "T2_kg": solution.T[1],
        "T3_kg": solution.T[2],
        "T4_kg": solution.T[3],
        "TerminalLOH_total_kg": float(solution.T.sum()),
        "T1_capacity_kg": CAPACITY[0],
        "T2_capacity_kg": CAPACITY[1],
        "T3_capacity_kg": CAPACITY[2],
        "T4_capacity_kg": CAPACITY[3],
        "T1_capacity_binding": int(binding[0]),
        "T2_capacity_binding": int(binding[1]),
        "T3_capacity_binding": int(binding[2]),
        "T4_capacity_binding": int(binding[3]),
        "capacity_binding_count": int(binding.sum()),
        "c_H2_yuan_per_kg": C_H2,
        "local_hydrogen_preparation_cost_yuan": production_cost,
        "M_H2_yuan_per_kg": M_H2,
        "mean_shortage_kg": mean_shortage,
        "mean_EENS_kWh": mean_eens,
        "service_rate": service_rate,
        "aggregate_service_rate": aggregate_service_rate,
        "probability_positive_shortage": positive_shortage_probability,
        "shortage_q95_kg": shortage_stats["q95"],
        "shortage_q99_kg": shortage_stats["q99"],
        "shortage_q99_5_kg": shortage_stats["q995"],
        "shortage_CVaR95_kg": shortage_stats["cvar95"],
        "shortage_CVaR99_kg": shortage_stats["cvar99"],
        "shortage_CVaR99_5_kg": shortage_stats["cvar995"],
        "max_shortage_kg": shortage_stats["maximum"],
        "EENS_q95_kWh": shortage_stats["q95"] * ELECTRICITY_PER_KG,
        "EENS_q99_kWh": shortage_stats["q99"] * ELECTRICITY_PER_KG,
        "EENS_q99_5_kWh": shortage_stats["q995"] * ELECTRICITY_PER_KG,
        "EENS_CVaR95_kWh": shortage_stats["cvar95"] * ELECTRICITY_PER_KG,
        "EENS_CVaR99_kWh": shortage_stats["cvar99"] * ELECTRICITY_PER_KG,
        "EENS_CVaR99_5_kWh": shortage_stats["cvar995"] * ELECTRICITY_PER_KG,
        "max_EENS_kWh": shortage_stats["maximum"] * ELECTRICITY_PER_KG,
        "nominal_expected_outage_loss_yuan": nominal_outage_loss,
        "nominal_total_economic_cost_yuan": nominal_economic_total,
        "nominal_expected_recourse_yuan": nominal_expected,
        "worst_expected_outage_loss_yuan": worst_expected,
        "robust_training_objective_yuan": solution.objective_value,
        "secondary_expected_service_distance": secondary_expected,
        "secondary_group_sum_service_distance": lex.secondary_objective_distance,
        "optimization_runtime_sec": solution.solve_runtime_sec,
        "lex_primary_runtime_sec": lex.primary_runtime_sec,
        "lex_secondary_runtime_sec": lex.secondary_runtime_sec,
        "case_total_runtime_sec": time.perf_counter() - started,
        "solver_status": solution.status,
        "audit_status": "PASS",
        "case_pass": 1,
    }
    write_single_row_csv(case_dir / "case_result.csv", result_row)

    certificate_row: dict[str, object] = {
        "case_id": args.case_id,
        "state_id": state_id,
        "state_label": state_label,
        "method_label": method_label,
        "eta": eta,
        "LB_yuan": solution.lower_bound,
        "UB_yuan": solution.upper_bound,
        "absolute_gap_yuan": solution.absolute_gap,
        "relative_gap": solution.relative_gap,
        "iteration_count": solution.iteration_count,
        "cut_count": solution.cut_count,
        "strong_duality_gap_yuan": strong_duality_gap,
        "strong_duality_relative_gap": strong_duality_relative_gap,
        "primary_objective_reconstruction_error_yuan": primary_consistency,
        "fixed_T_nominal_reconstruction_error_yuan": fixed_consistency,
        "divergence_used": record_divergence,
        "divergence_slack": eta - record_divergence,
        "probability_sum_residual": probability_sum_residual,
        "minimum_worst_probability": float(record_probability.min()),
        "maximum_worst_probability": float(record_probability.max()),
        "effective_support_size_ESS": float(1.0 / np.dot(record_probability, record_probability)),
        "positive_probability_support_count": int(np.sum(record_probability > 1.0e-15)),
        "lex_shortage_preservation_error_kg": lex.max_shortage_preservation_error,
        "lex_primary_preservation_error_yuan": lex.primary_preservation_error,
        "lex_mechanical_residual": lex_residual,
        "maximum_mechanical_residual": maximum_residual,
        "eta_zero_direct_SAA_pass": int(eta_zero_pass),
        "C_y_in_primary_objective": 0,
        "C_y_in_Pearson_loss": 0,
        "secondary_changed_T": 0,
        "constructed_R_by_R_matrix": 0,
        "certificate_pass": 1,
    }
    write_single_row_csv(case_dir / "solver_certificate.csv", certificate_row)

    total_variation = 0.5 * float(np.abs(record_probability - q_record).sum())
    order = np.argsort(-record_loss, kind="stable")
    top1 = order[: math.ceil(0.01 * 15000)]
    top5 = order[: math.ceil(0.05 * 15000)]
    weighted_shortage = float(np.dot(record_probability, record_shortage_primary))
    worst_row: dict[str, object] = {
        "case_id": args.case_id,
        "state_id": state_id,
        "state_label": state_label,
        "method_label": method_label,
        "eta": eta,
        "actual_chi2_divergence": record_divergence,
        "probability_sum": float(record_probability.sum()),
        "minimum_probability": float(record_probability.min()),
        "maximum_probability": float(record_probability.max()),
        "maximum_probability_to_nominal_ratio": float(np.max(record_probability / q_record)),
        "total_variation_distance": total_variation,
        "ESS": float(1.0 / np.dot(record_probability, record_probability)),
        "top1_fraction": 0.01,
        "top1_nominal_mass": float(q_record[top1].sum()),
        "top1_worst_mass": float(record_probability[top1].sum()),
        "top5_fraction": 0.05,
        "top5_nominal_mass": float(q_record[top5].sum()),
        "top5_worst_mass": float(record_probability[top5].sum()),
        "worst_weighted_mean_shortage_kg": weighted_shortage,
        "worst_weighted_mean_EENS_kWh": weighted_shortage * ELECTRICITY_PER_KG,
    }
    write_single_row_csv(case_dir / "worst_probability_summary.csv", worst_row)
    savemat(
        case_dir / "case_payload.mat",
        {
            "recordShortage": record_shortage.reshape(-1, 1),
            "recordDemand": record_demand.reshape(-1, 1),
            "recordOperatingLoss": record_loss.reshape(-1, 1),
            "p": record_probability.reshape(-1, 1),
            "q": q_record.reshape(-1, 1),
            "T": solution.T.reshape(1, -1),
            "eta": np.asarray([[eta]]),
            "stateId": np.asarray([[state_id]], dtype=np.int32),
        },
        do_compression=False,
    )
    (case_dir / "mechanical_audit.txt").write_text(
        "\n".join(
            [
                "status=PASS",
                f"case_id={args.case_id}",
                f"state_id={state_id}",
                f"eta={eta:.12g}",
                f"LB_yuan={solution.lower_bound:.15g}",
                f"UB_yuan={solution.upper_bound:.15g}",
                f"relative_gap={solution.relative_gap:.15g}",
                f"probability_sum_residual={probability_sum_residual:.15g}",
                f"divergence_used={record_divergence:.15g}",
                "C_y_in_primary=0",
                "C_y_in_Pearson_loss=0",
                "path_probability_used=0",
                "MSP_called=0",
                "MATLAB_used_for_optimization_case=0",
                "gurobipy_version=12.0.1",
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    (case_dir / "CASE_COMPLETE.txt").write_text(
        f"PASS\nstate_id={state_id}\neta={eta:.12g}\n", encoding="utf-8"
    )
    print(
        f"STEP04CC6_PYTHON_CASE_COMPLETE|case={args.case_id}|state={state_id}|eta={eta:.12g}|"
        f"total={solution.T.sum():.9f}|runtime={time.perf_counter() - started:.3f}",
        flush=True,
    )


if __name__ == "__main__":
    main()
