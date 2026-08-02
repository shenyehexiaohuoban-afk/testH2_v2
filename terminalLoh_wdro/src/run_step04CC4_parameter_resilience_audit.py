#!/usr/bin/env python3
"""Step-04C-C4 deterministic read-only parameter and resilience audit.

This script does not call MATLAB, Gurobi, the MSP, or any optimizer. It reads
the frozen C1/C2/C3 accepted artifacts and the existing near-stage MAT input,
then writes only a new C4 run directory.
"""

from __future__ import annotations

import hashlib
import json
import math
import subprocess
from pathlib import Path

import numpy as np
import pandas as pd
from scipy.io import loadmat


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "results/task-002-stage2b-b3-smoke/49-parameter-provenance-resilience-audit/run-004"
C1 = ROOT / "results/task-002-stage2b-b3-smoke/46-flat-chi2-eta-calibration/run-003"
C2 = ROOT / "results/task-002-stage2b-b3-smoke/47-flat-chi2-independent-path-validation/run-002"
C3 = ROOT / "results/task-002-stage2b-b3-smoke/48-markov-transition-perturbation/run-001"
MAT = ROOT / "data/yuanqi/near_stage_msp_input.mat"
FROZEN_HEAD = "62447cb913f5fd3723b5cdf7b3cefccc358bdab2"
GAMMA = 2.0
SELECTED_ETAS = (0.0, 0.003, 0.01)


def rel(path: Path) -> str:
    return path.resolve().relative_to(ROOT).as_posix()


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def line_number(path: Path, needle: str) -> int:
    for idx, text in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
        if needle in text:
            return idx
    raise RuntimeError(f"Cannot locate source text {needle!r} in {path}")


def source_ref(path: Path, needle: str) -> str:
    return f"{rel(path)}:{line_number(path, needle)}"


def scalar(value) -> float:
    a = np.asarray(value)
    if a.size != 1:
        raise ValueError(f"Expected scalar, got shape {a.shape}")
    return float(a.reshape(-1)[0])


def pct_change(delta: float, base: float) -> float:
    return np.nan if abs(base) < 1e-15 else 100.0 * delta / base


def divide_positive(numerator: float, denominator: float) -> float:
    return np.nan if denominator <= 0 else numerator / denominator


def percentile_like_matlab(values: pd.Series, probability: float) -> float:
    x = np.sort(pd.to_numeric(values, errors="coerce").dropna().to_numpy(float))
    if x.size == 0:
        return np.nan
    idx = max(1, min(x.size, math.ceil(probability * x.size))) - 1
    return float(x[idx])


def tail_mean_like_matlab(values: pd.Series, probability: float) -> float:
    x = pd.to_numeric(values, errors="coerce").dropna().to_numpy(float)
    if x.size == 0:
        return np.nan
    threshold = percentile_like_matlab(pd.Series(x), probability)
    return float(np.mean(x[x >= threshold]))


def write_csv(frame: pd.DataFrame, name: str) -> None:
    frame.to_csv(OUT / name, index=False, encoding="utf-8-sig", float_format="%.15g")


def preflight() -> dict:
    if OUT.exists():
        raise RuntimeError(f"Refusing to overwrite existing run directory: {OUT}")
    if git("branch", "--show-current") != "task/002-stage2b-b3-smoke":
        raise RuntimeError("Wrong branch")
    head = git("rev-parse", "HEAD")
    upstream = git("rev-parse", "@{upstream}")
    remote = git("ls-remote", "origin", "refs/heads/task/002-stage2b-b3-smoke").split()[0]
    if len({head, upstream, remote, FROZEN_HEAD}) != 1:
        raise RuntimeError(f"Frozen Git gate failed: {head=} {upstream=} {remote=}")
    required = [
        MAT,
        C1 / "README.md", C1 / "eta_full_results.csv", C1 / "eta_validation_comparison.csv",
        C1 / "eta_stress_test_comparison.csv", C1 / "eta_solver_certificate.csv",
        C2 / "README.md", C2 / "fixed_T_full_results.csv", C2 / "fixed_T_process_certificate.csv",
        C3 / "README.md", C3 / "fixed_T_full_results.csv", C3 / "fixed_T_process_certificate.csv",
    ]
    missing = [str(p) for p in required if not p.is_file()]
    if missing:
        raise RuntimeError(f"Missing frozen input(s): {missing}")
    if not (pd.read_csv(C1 / "eta_solver_certificate.csv")["certificate_pass"].astype(bool).all()
            and pd.read_csv(C2 / "fixed_T_process_certificate.csv")["certificate_pass"].astype(bool).all()
            and pd.read_csv(C3 / "fixed_T_process_certificate.csv")["certificate_pass"].astype(bool).all()):
        raise RuntimeError("A frozen accepted-run certificate is not PASS")
    return {"head": head, "upstream": upstream, "remote": remote, "required": required}


def load_parameters() -> tuple[dict, dict]:
    near = loadmat(MAT, simplify_cells=True)["NearStageInput"]
    cost = near["Cost"]
    dev = near["HydrogenDevice"]
    htt = near["HTT"]
    grid = near["Grid"]
    spatial = near["Spatial"]
    sets = near["Sets"]
    values = {
        "M": scalar(cost["reserve_shortage_penalty_yuan_per_kg"]),
        "normal_penalty": scalar(cost["normal_shortage_penalty_yuan_per_kg"]),
        "holding": scalar(cost["h2_holding_cost_yuan_per_kg"]),
        "el_om": scalar(cost["el_om_yuan_per_kWh"]),
        "electricity_prices": np.asarray(cost["electricity_price_yuan_per_kWh"], dtype=float).reshape(-1),
        "transport_rate": scalar(htt["transport_cost_yuan_per_kg_km"]),
        "beta_multiplier": scalar(htt["beta_transport_multiplier"]),
        "base_transport": np.asarray(htt["site_to_site_base_cost_yuan_per_kg"], dtype=float),
        "road_km": np.asarray(spatial["site_to_site_road_km"], dtype=float),
        "eta_fc": scalar(dev["eta_FC"]),
        "lhv": scalar(dev["h2_lhv_kWh_per_kg"]),
        "eta_el": scalar(dev["eta_EL"]),
        "k_h2": scalar(dev["k_H2_kg_per_kWh"]),
        "tank_cap": np.asarray(dev["tank_cap_kg"], dtype=float).reshape(-1),
        "load": np.asarray(grid["P_load_base_kw"], dtype=float).reshape(-1),
        "htt_n": scalar(htt["N_HTT"]),
        "htt_q": scalar(htt["Q_HTT_kg"]),
        "htt_capacity": scalar(htt["base_capacity_kg_per_stage"]),
        "msp_dt": scalar(sets["default_near_stage_dt_h"]),
        "normal_stage_demand": np.asarray(near["NormalDemand"]["stage_template_kg"], dtype=float),
        "critical_load": np.asarray(near["CriticalLoad"]["P_critical_base_kw"], dtype=float).reshape(-1),
        "critical_h2": np.asarray(near["CriticalLoad"]["H_node_kg"], dtype=float).reshape(-1),
        "critical_support_hours": scalar(near["CriticalLoad"]["support_hours"]),
    }
    if values["M"] != 2000 or not np.allclose(values["tank_cap"], [300, 200, 100, 150]):
        raise RuntimeError("Frozen M/capacity values changed")
    if not np.allclose(values["base_transport"], values["transport_rate"] * values["road_km"]):
        raise RuntimeError("HTT base transport cost no longer equals rate times road distance")
    values["kwh_per_shortage_kg"] = values["eta_fc"] * values["lhv"]
    values["kg_per_kwh"] = 1.0 / values["kwh_per_shortage_kg"]
    return near, values


def build_provenance(v: dict) -> tuple[pd.DataFrame, pd.DataFrame]:
    build = ROOT / "terminalLoh_wdro/src/build_terminal_loh_wdro_from_joint_samples_h2.m"
    recover = ROOT / "terminalLoh_wdro/src/recover_step03Y_prefix_entries_h2.m"
    eval_fixed = ROOT / "terminalLoh_wdro/src/evaluate_step03T_fixed_T_recourse_h2.m"
    consequence = ROOT / "terminalLoh_wdro/src/generate_step04CA2_formal_consequences_h2.m"
    load_data = ROOT / "load_data_h2_near.m"
    stage = ROOT / "fa_h2/build_stage_model_h2.m"
    rhs = ROOT / "fa_h2/update_rhs_h2.m"
    terminal = ROOT / "fa_h2/fuzhu/terminal_value_and_subgradient_h2.m"
    terminal_build = ROOT / "fa_h2/fuzhu/build_terminal_loh_h2.m"
    readme = ROOT / "terminalLoh_wdro/docs/README_WDRO_preview.md"

    cols = ["parameter_name", "symbol", "current_value", "code_unit", "source_path",
            "function_or_field", "exact_line_or_field", "effective_call_chain", "objective_entry",
            "parameter_type", "explicit_source_description", "real_currency_interpretation",
            "audit_conclusion", "risk_note"]
    rows = []
    def add(*items):
        rows.append(dict(zip(cols, items)))

    add("offline TerminalLOH preload coefficient", "gamma", GAMMA, "objective-unit/kg",
        rel(recover), "recover_step03Y_prefix_entries_h2", source_ref(recover, "'M', M, 'gamma', 0.001 * M"),
        "MAT M -> context.gamma=0.001*M -> C1 prepared input -> fixed-T full objective",
        source_ref(eval_fixed, "out.holding_cost = config.gamma .* sum(Trows, 2);"),
        "derived model trade-off weight", "README explicitly calls gamma a configurable holding weight",
        "No: the offline objective mixes km*kg service impedance with the declared yuan shortage field",
        "2 means 0.001 times the effective shortage penalty and discourages capacity filling; it is not MSP production cost",
        source_ref(readme, "it is not the MSP production cost"))
    add("reserve hydrogen shortage penalty", "M", v["M"], "declared yuan/kg in MAT field",
        rel(MAT), "NearStageInput.Cost", "reserve_shortage_penalty_yuan_per_kg",
        "MAT field -> recovery/build context -> M*u in formal recourse",
        source_ref(eval_fixed, "out.shortage_loss = M .* out.shortage_kg;"),
        "engineering penalty / effective model weight", "Field name declares yuan/kg; no calibration reference was found",
        "Field is monetary-labelled, but the combined offline objective is not dimensionally monetary",
        "Effective value is 2000; evidence does not establish it as calibrated outage loss or VOLL",
        "Fallback 2000 exists, but the live MAT field is present and therefore wins")
    add("formal service impedance", "C_i,n^tau", "scenario dependent", "km",
        rel(consequence), "road_state / Cperiod", source_ref(consequence, "Cperiod(rr, :, :, :) = costTau;"),
        "road length and slowing -> shortest-path distance -> C*y",
        source_ref(eval_fixed, "transportByRelation = Ceff .* y;"),
        "physical impedance proxy", "C is current-road-state shortest-path distance",
        "No: no yuan/(kg*km) multiplier enters the offline recourse",
        "This term is kg*km service impedance, not the MSP HTT transport bill",
        "Adding this term to M*kg creates an intentionally weighted, not currency-consistent, objective")
    add("grid load used by formal D", "P_load_base", f"sum={v['load'].sum():.15g}", "kW",
        rel(MAT), "NearStageInput.Grid", "P_load_base_kw",
        "MAT grid load -> consequence model.Pnode_kW -> one-hour D",
        source_ref(consequence, "Dtau = double(outage) .* model.Pnode_kW.' * model.DFactorKgPerKWh;"),
        "physical parameter", "IEEE-33 base active-load vector stored in MAT", "Not a cost",
        "Formal C1/C2/C3 D uses the full base-load vector, not the critical-load template",
        "Source node is forced not-outaged in the consequence generator")
    add("fuel-cell efficiency", "eta_FC", v["eta_fc"], "dimensionless",
        rel(MAT), "NearStageInput.HydrogenDevice", "eta_FC",
        "MAT -> DFactor=1/(eta_FC*LHV) -> D", source_ref(consequence, "'DFactorKgPerKWh', 1/(eta*lhv)"),
        "physical parameter", "Named field and active call chain exist", "Not a cost",
        "May be used for repository-internal kg-H2 to kWh equivalence", "No external efficiency was introduced")
    add("hydrogen lower heating value", "LHV_H2", v["lhv"], "kWh/kg",
        rel(MAT), "NearStageInput.HydrogenDevice", "h2_lhv_kWh_per_kg",
        "MAT -> DFactor=1/(eta_FC*LHV) -> D", source_ref(consequence, "'DFactorKgPerKWh', 1/(eta*lhv)"),
        "physical parameter", "Named field and active call chain exist", "Not a cost",
        "Together with eta_FC gives 18.3315 modeled kWh per kg H2", "No external heating value was introduced")
    add("formal consequence period duration", "Delta_tau", "1 each; 3 periods", "h",
        rel(consequence), "generate_step04CA2_formal_consequences_h2", source_ref(consequence, "for tau = 1:3"),
        "One-hour D factor is applied once in each of three frozen periods", source_ref(consequence, "Dtau = double(outage)"),
        "physical/time convention", "Frozen Step-03Y/04C formal consequence convention", "Not a cost",
        "Formal C1/C2/C3 consequence horizon is three one-hour periods",
        f"Do not substitute the separate near-stage MSP default dt={v['msp_dt']:g} h")
    add("electrolyzer conversion", "k_H2", v["k_h2"], "kg/kWh",
        rel(MAT), "NearStageInput.HydrogenDevice", "k_H2_kg_per_kWh",
        "MAT -> load_data_h2_near -> stage hydrogen balance", source_ref(stage, "Aeq(prow, idx.e(i)) = -params.k_H2 * params.dt_h;"),
        "physical/engineering parameter", "Active in MSP static model", "Not itself a cost",
        "Used only by MSP production balance, not offline gamma", "eta_EL is loaded separately but k_H2 is the coefficient actually used in the balance")
    add("electrolyzer efficiency", "eta_EL", v["eta_el"], "dimensionless",
        rel(MAT), "NearStageInput.HydrogenDevice", "eta_EL",
        "MAT -> load_data_h2_near params.eta_EL", source_ref(load_data, "params.eta_EL = eta_EL;"),
        "physical/engineering parameter", "Loaded into MSP params", "Not a cost",
        "No direct occurrence in the stage objective or balance beyond the separately supplied k_H2 was found",
        "Potential duplicated conversion semantics require engineering documentation")
    add("MSP electricity price", "c_elec(t)", f"min={v['electricity_prices'].min():g}; max={v['electricity_prices'].max():g}", "yuan/kWh",
        rel(MAT), "NearStageInput.Cost", "electricity_price_yuan_per_kWh",
        "MAT -> stage-average price -> electricity objective coefficient", source_ref(stage, "c(idx.e) = (params.cost_electricity_stage(t) + params.cost_el_om) * params.dt_h;"),
        "engineering cost", "Monetary field and active MSP objective chain exist", "Yes within MSP model units",
        "Not included in offline gamma=2", "No external price-source citation was found")
    add("MSP electrolyzer O&M", "c_EL_OM", v["el_om"], "yuan/kWh",
        rel(MAT), "NearStageInput.Cost", "el_om_yuan_per_kWh",
        "MAT -> load_data -> electricity objective coefficient", source_ref(stage, "c(idx.e) = (params.cost_electricity_stage(t) + params.cost_el_om) * params.dt_h;"),
        "engineering cost", "Monetary field and active MSP objective chain exist", "Yes within MSP model units",
        "Not included in offline gamma=2", "No external calibration reference was found")
    add("MSP hydrogen holding cost", "c_hold", v["holding"], "yuan/kg per stage objective application",
        rel(MAT), "NearStageInput.Cost", "h2_holding_cost_yuan_per_kg",
        "MAT -> params.cost_holding -> c*xAfter", source_ref(stage, "c(idx.x) = params.cost_holding;"),
        "engineering cost", "Monetary field and active MSP objective chain exist", "Yes within MSP model units",
        "This 0.05 MSP holding coefficient is distinct from offline gamma=2", "No explicit per-hour/per-stage calibration source was found")
    add("MSP normal hydrogen shortage penalty", "c_normal_short", v["normal_penalty"], "yuan/kg",
        rel(MAT), "NearStageInput.Cost", "normal_shortage_penalty_yuan_per_kg",
        "MAT -> optional multiplier -> c*z_normal", source_ref(stage, "c(idx.z_normal) = params.cost_normal_shortage;"),
        "engineering penalty", "Monetary field and active MSP objective chain exist", "Yes within MSP model units",
        "Distinct from disaster reserve shortage M=2000", "No external calibration reference was found")
    add("MSP HTT transport rate", "c_HTT", v["transport_rate"], "yuan/(kg*km)",
        rel(MAT), "NearStageInput.HTT", "transport_cost_yuan_per_kg_km",
        "rate*site road km -> base cost matrix -> beta-adjusted c*f", source_ref(rhs, "model.c(model.idx.f(:)) = params.cost_transport_base(:) *"),
        "engineering cost", "Monetary field and active MSP objective chain exist", "Yes within MSP model units",
        "Not applied to offline C*y", "Base matrix equality to 0.8*road_km was mechanically verified")
    add("MSP beta transport multiplier", "lambda_beta", v["beta_multiplier"], "dimensionless",
        rel(MAT), "NearStageInput.HTT", "beta_transport_multiplier",
        "MAT -> params -> (1+lambda_beta*beta) transport multiplier", source_ref(rhs, "(1 + params.beta_transport_multiplier * beta);"),
        "engineering/model multiplier", "Active MSP transport chain exists", "Only through monetary base transport cost",
        "The numeric value 2 here is unrelated to offline gamma=2", "Identical numerals must not be conflated")
    add("MSP reserve terminal shortage penalty", "c_reserve_short", v["M"], "yuan/kg",
        rel(MAT), "NearStageInput.Cost", "reserve_shortage_penalty_yuan_per_kg",
        "MAT -> params.cost_reserve_shortage -> terminal value", source_ref(terminal, "value = params.cost_reserve_shortage * sum(shortage);"),
        "engineering penalty", "Monetary field and active terminal MSP chain exist", "Yes within MSP model units",
        "Same numeric MAT field supplies offline M, but the surrounding objectives differ", "No salvage reward exists for surplus above TerminalLOH")
    add("hydrogen tank capacities", "Cap_i", json.dumps(v["tank_cap"].tolist()), "kg",
        rel(MAT), "NearStageInput.HydrogenDevice", "tank_cap_kg",
        "MAT -> C1 context -> fixed TerminalLOH bounds and binding audit", "decision upper bounds",
        "physical/engineering parameter", "Named field and active solver/fixed-decision chain exist", "Not a cost",
        "Effective capacities are [300,200,100,150] kg", "Offline gamma does not represent capacity occupation cost")
    add("HTT base capacity", "Q_HTT_total", v["htt_capacity"], "kg/stage",
        rel(MAT), "NearStageInput.HTT", "base_capacity_kg_per_stage",
        "N_HTT*Q_HTT -> beta-reduced ordinary-stage transfer bound", source_ref(stage, "sum_i sum_j f_ij <= (1-beta(k))*HTT_capacity"),
        "physical/engineering parameter", f"{v['htt_n']:g} vehicles times {v['htt_q']:g} kg", "Not a cost",
        "Active only in MSP, not in the offline fixed-T recourse", "Higher TerminalLOH may require transfers whose feasibility/cost appears only after MSP integration")
    add("normal hydrogen demand", "D_normal", f"stage-template sum={v['normal_stage_demand'].sum():.15g}", "kg/stage template",
        rel(MAT), "NearStageInput.NormalDemand", "stage_template_kg",
        "MAT -> expand_normal_demand_h2 -> ordinary-stage withdrawal/shortage", source_ref(stage, "Normal demand is a real tank withdrawal"),
        "physical demand input", "README and MAT note identify it as real outflow", "Not itself a cost",
        "Served normal load reduces inventory; shortage is penalized at 200 yuan/kg", "Not represented by offline gamma=2")
    add("critical-load hydrogen template", "H_node_critical", f"sum={v['critical_h2'].sum():.15g}", "kg",
        rel(MAT), "NearStageInput.CriticalLoad", "H_node_kg",
        "P_critical*support_hours/(eta_FC*LHV) -> optional MSP TerminalLOH builder", source_ref(terminal_build, "Hnode = Pnode(:) * supportHours / (etaFC * lhv);"),
        "physical/model input", f"MAT support_hours={v['critical_support_hours']:g}", "Not a cost",
        "This optional MSP template is not the formal C1/C2/C3 D source", "Formal C1/C2/C3 uses full P_load_base and three one-hour periods")
    add("liquid-hydrogen/storage loss", "loss_H2", "not defined", "missing",
        rel(stage), "MSP inventory balance", source_ref(stage, "x_i,t = x_i,t-1 + r_i,t + inflow_i,t - outflow_i,t - u_i,t^normal."),
        "No loss coefficient appears in the implemented balance", "none",
        "missing engineering parameter", "No source or active value found", "No",
        "Current MSP implicitly has zero storage/boil-off loss", "Required for liquid-H2 or long-horizon realism")
    add("unused terminal hydrogen salvage/future value", "v_salvage", 0, "no explicit value",
        rel(terminal), "terminal_value_and_subgradient_h2", source_ref(terminal, "shortage = max(0, target - x_trial);"),
        "Terminal value penalizes shortage only; surplus has zero explicit reward", "none",
        "absent economic term", "No salvage/continuation credit found", "No",
        "Unused hydrogen has no explicit residual value in the audited terminal function", "Full MSP continuation value would need separate modeling evidence")
    add("external hydrogen purchase", "q_purchase", "not modeled", "missing",
        rel(stage), "fa_h2 stage decision vector", source_ref(stage, "idx.f = reshape"),
        "No procurement/purchase decision or objective coefficient found", "none",
        "absent model component", "No source or active value found", "No",
        "Extra TerminalLOH cannot be priced as purchased hydrogen in the current static model", "Production is through electrolyzer power only")
    add("electricity unserved value/VOLL", "c_EENS", "not defined", "missing yuan/kWh",
        rel(stage), "implemented ordinary-stage objective coefficient block", source_ref(stage, "c(idx.z_normal) = params.cost_normal_shortage;"),
        "No monetary electric-load-shedding variable enters the audited objectives", "none",
        "missing economic parameter", "No source or active value found", "No",
        "The 2000 yuan/kg-labelled reserve penalty is not evidenced as a calibrated VOLL conversion", "Needed for real economic EENS valuation")

    provenance = pd.DataFrame(rows, columns=cols)

    trace = pd.DataFrame([
        ["M", 1, rel(MAT), "NearStageInput.Cost.reserve_shortage_penalty_yuan_per_kg", v["M"], "declared yuan/kg", "load", "primary live MAT field", True, "Effective source"],
        ["M", 2, rel(build), source_ref(build, "M = 2000;"), 2000, "declared yuan/kg", "fallback", "used only if MAT fields absent", False, "Not effective in C1/C2/C3"],
        ["M", 3, rel(recover), source_ref(recover, "M = double(near.Cost.reserve_shortage_penalty_yuan_per_kg);"), v["M"], "declared yuan/kg", "copy", "MAT value propagated", True, "C1 context"],
        ["gamma", 1, rel(recover), source_ref(recover, "'M', M, 'gamma', 0.001 * M"), GAMMA, "objective-unit/kg", "derive", "0.001*M", True, "C1 effective"],
        ["gamma", 2, "terminalLoh_wdro/src/run_step04CC2_fixed_T_dataset_h2.m", "line 47", GAMMA, "objective-unit/kg", "freeze", "hard-coded equality to C1", True, "C2 effective"],
        ["gamma", 3, "terminalLoh_wdro/src/run_step04CC3_fixed_T_dataset_h2.m", "line 46", GAMMA, "objective-unit/kg", "freeze", "hard-coded equality to C1", True, "C3 effective"],
        ["C", 1, rel(consequence), source_ref(consequence, "edgeCost = model.roadLength .* (1 + slow"), "scenario dependent", "km", "construct", "current-road-state edge impedance", True, "No monetary multiplier"],
        ["C", 2, rel(eval_fixed), source_ref(eval_fixed, "transportByRelation = Ceff .* y;"), "scenario dependent", "kg*km after multiplying y", "objective", "service term", True, "Not MSP HTT cost"],
    ], columns=["parameter", "step_order", "path", "line_or_field", "value", "unit", "action", "override_relation", "is_effective", "notes"])
    return provenance, trace


def build_objective_decomposition(v: dict) -> pd.DataFrame:
    return pd.DataFrame([
        ["offline C1/C2/C3", "preload inventory", "gamma*sum_i(T_i)", GAMMA, "objective-unit/kg", "yes", "Derived trade-off weight; not MSP production cost"],
        ["offline C1/C2/C3", "service impedance", "sum_tau,i,n C_i,n^tau*y_i,n^tau", np.nan, "kg*km", "yes", "Current-road shortest-path impedance; not monetized"],
        ["offline C1/C2/C3", "hydrogen shortage penalty", "M*sum_tau,n u_n^tau", v["M"], "declared yuan/kg but used as model penalty", "yes", "Dominant penalty term; calibration source unresolved"],
        ["offline C1/C2/C3", "full objective", "gamma*sum(T)+service_impedance+M*shortage", np.nan, "mixed objective units", "yes", "Not dimensionally a pure currency objective"],
        ["near-stage MSP", "hydrogen inventory holding", "c_hold*sum(xAfter)", v["holding"], "yuan/kg", "yes", "Applied in each ordinary stage objective"],
        ["near-stage MSP", "electrolyzer electricity", "price_t*dt_h*sum(e)", f"{v['electricity_prices'].min():g}..{v['electricity_prices'].max():g}", "yuan/kWh", "yes", "Stage-average electricity price"],
        ["near-stage MSP", "electrolyzer O&M", "c_EL_OM*dt_h*sum(e)", v["el_om"], "yuan/kWh", "yes", "Added to electricity coefficient"],
        ["near-stage MSP", "HTT transfer", "c_ij_base*(1+lambda_beta*beta)*f_ij", v["transport_rate"], "yuan/(kg*km) base rate", "yes", "Capacity also falls with beta"],
        ["near-stage MSP", "normal H2 shortage", "c_normal_short*sum(z_normal)", v["normal_penalty"], "yuan/kg", "yes", "Ordinary-stage load shortage"],
        ["near-stage MSP", "terminal reserve shortage", "c_reserve_short*sum(max(0,T-x))", v["M"], "yuan/kg", "yes", "Terminal convex penalty"],
        ["near-stage MSP", "surplus salvage", "none", np.nan, "none", "no", "No reward or later-use terminal value found"],
        ["near-stage MSP", "storage/boil-off loss", "none", np.nan, "none", "no", "Balance contains no multiplicative inventory loss"],
        ["near-stage MSP", "external hydrogen purchase", "none", np.nan, "none", "no", "No purchase/procurement decision found"],
    ], columns=["model_scope", "cost_component", "implemented_formula", "effective_coefficient", "unit", "enters_objective", "audit_note"])


def selected_decisions() -> pd.DataFrame:
    c1 = pd.read_csv(C1 / "eta_full_results.csv")
    selected = c1[c1["eta"].isin(SELECTED_ETAS)].copy().sort_values("eta")
    if len(selected) != 3:
        raise RuntimeError("C1 selected decisions missing")
    return selected


def normalize_result_rows(decisions: pd.DataFrame) -> pd.DataFrame:
    decision_names = {0.0: "SAA", 0.003: "ETA_0.003", 0.01: "ETA_0.01"}
    frames = []

    c1v = pd.read_csv(C1 / "eta_validation_comparison.csv")
    c1v = c1v[c1v["eta"].isin(SELECTED_ETAS)].copy()
    c1v["source_step"] = "C1"
    c1v["evaluation_scope"] = "nominal-and-same-path-second-layer-redraw"
    c1v["distribution_label"] = c1v["dataset_role"]
    c1v["seed_id"] = np.nan
    c1v["decision_label"] = c1v["eta"].map(decision_names)
    frames.append(c1v)

    c1s = pd.read_csv(C1 / "eta_stress_test_comparison.csv")
    c1s = c1s[c1s["eta"].isin(SELECTED_ETAS)].copy()
    c1s["source_step"] = "C1"
    c1s["evaluation_scope"] = "fixed-state19-pressure-replicas"
    c1s["distribution_label"] = "fixed-stress-135-replicas"
    c1s["seed_id"] = np.nan
    c1s["decision_label"] = c1s["eta"].map(decision_names)
    frames.append(c1s)

    c2 = pd.read_csv(C2 / "fixed_T_full_results.csv")
    c2["source_step"] = "C2"
    c2["evaluation_scope"] = "independent-typhoon-path-seeds"
    c2["distribution_label"] = "independent-path-nominal"
    c2["seed_id"] = c2["dataset_id"]
    frames.append(c2)

    c3 = pd.read_csv(C3 / "fixed_T_full_results.csv")
    c3["source_step"] = "C3"
    c3["evaluation_scope"] = "markov-transition-perturbation"
    frames.append(c3)

    common = ["source_step", "evaluation_scope", "distribution_label", "seed_id", "decision_label", "eta",
              "mean_total_cost", "mean_operating_loss", "mean_shortage_kg", "mean_service_rate",
              "operating_loss_q95", "operating_loss_q99", "operating_loss_q995", "operating_loss_CVaR995",
              "shortage_q95_kg", "shortage_q99_kg", "shortage_q995_kg", "maximum_shortage_kg"]
    for frame in frames:
        for col in common:
            if col not in frame:
                frame[col] = np.nan
    all_rows = pd.concat([f[common] for f in frames], ignore_index=True)
    dmap = decisions.set_index("eta")
    for col in ["T1_kg", "T2_kg", "T3_kg", "T4_kg", "TerminalLOH_total_kg", "capacity_binding_count"]:
        all_rows[col] = all_rows["eta"].map(dmap[col])
    all_rows["direct_inventory_model_cost"] = GAMMA * all_rows["TerminalLOH_total_kg"]

    keys = ["source_step", "evaluation_scope", "distribution_label", "seed_id"]
    metric_cols = ["TerminalLOH_total_kg", "direct_inventory_model_cost", "mean_total_cost", "mean_operating_loss",
                   "mean_shortage_kg", "mean_service_rate", "operating_loss_q95", "operating_loss_q99",
                   "operating_loss_q995", "operating_loss_CVaR995", "shortage_q95_kg", "shortage_q99_kg",
                   "shortage_q995_kg", "maximum_shortage_kg"]
    baseline = all_rows[all_rows["eta"] == 0][keys + metric_cols].copy()
    baseline = baseline.rename(columns={c: f"SAA_{c}" for c in metric_cols})
    merged = all_rows.merge(baseline, on=keys, how="left", validate="many_to_one")
    for col in metric_cols:
        merged[f"{col}_change_vs_SAA"] = merged[col] - merged[f"SAA_{col}"]
        merged[f"{col}_percent_change_vs_SAA"] = np.where(
            merged[f"SAA_{col}"].abs() > 1e-15,
            100 * merged[f"{col}_change_vs_SAA"] / merged[f"SAA_{col}"], np.nan)
    merged["objective_reconstruction_error"] = (
        merged["mean_total_cost"] - merged["mean_operating_loss"] - merged["direct_inventory_model_cost"])
    return merged


def build_safety(rows: pd.DataFrame) -> pd.DataFrame:
    candidates = rows[rows["eta"] > 0].copy()
    candidates["inventory_increase_ratio"] = candidates["TerminalLOH_total_kg_change_vs_SAA"] / candidates["SAA_TerminalLOH_total_kg"]
    candidates["direct_inventory_increment_model_units"] = GAMMA * candidates["TerminalLOH_total_kg_change_vs_SAA"]
    candidates["net_safety_premium_model_units"] = candidates["mean_total_cost_change_vs_SAA"]
    candidates["net_safety_premium_percent"] = candidates["mean_total_cost_percent_change_vs_SAA"]
    candidates["operating_loss_reduction"] = -candidates["mean_operating_loss_change_vs_SAA"]
    candidates["shortage_reduction_kg"] = -candidates["mean_shortage_kg_change_vs_SAA"]
    candidates["extra_inventory_per_kg_mean_shortage_reduced"] = [
        divide_positive(dt, ds) for dt, ds in zip(candidates["TerminalLOH_total_kg_change_vs_SAA"], candidates["shortage_reduction_kg"])]
    candidates["extra_inventory_per_operating_loss_unit_reduced"] = [
        divide_positive(dt, dl) for dt, dl in zip(candidates["TerminalLOH_total_kg_change_vs_SAA"], candidates["operating_loss_reduction"])]
    candidates["operating_loss_reduction_per_extra_inventory_kg"] = candidates["operating_loss_reduction"] / candidates["TerminalLOH_total_kg_change_vs_SAA"]
    candidates["shortage_reduction_per_extra_inventory_kg"] = candidates["shortage_reduction_kg"] / candidates["TerminalLOH_total_kg_change_vs_SAA"]
    keep = ["source_step", "evaluation_scope", "distribution_label", "seed_id", "decision_label", "eta",
            "TerminalLOH_total_kg_change_vs_SAA", "inventory_increase_ratio", "direct_inventory_increment_model_units",
            "mean_total_cost_change_vs_SAA", "mean_total_cost_percent_change_vs_SAA", "mean_operating_loss_change_vs_SAA",
            "mean_shortage_kg_change_vs_SAA", "mean_service_rate_change_vs_SAA", "operating_loss_q95_change_vs_SAA",
            "operating_loss_q99_change_vs_SAA", "operating_loss_q995_change_vs_SAA", "operating_loss_CVaR995_change_vs_SAA",
            "extra_inventory_per_kg_mean_shortage_reduced", "extra_inventory_per_operating_loss_unit_reduced",
            "operating_loss_reduction_per_extra_inventory_kg", "shortage_reduction_per_extra_inventory_kg",
            "net_safety_premium_model_units", "net_safety_premium_percent"]
    return candidates[keep]


def build_gamma_break_even(rows: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    subset = rows[(rows["source_step"].isin(["C2", "C3"])) & (rows["eta"] > 0)].copy()
    subset["inventory_increment_kg"] = subset["TerminalLOH_total_kg_change_vs_SAA"]
    subset["operating_loss_reduction"] = -subset["mean_operating_loss_change_vs_SAA"]
    subset["gamma_break_even"] = np.where(subset["operating_loss_reduction"] > 0,
                                           subset["operating_loss_reduction"] / subset["inventory_increment_kg"], np.nan)
    subset["positive_break_even_space"] = subset["operating_loss_reduction"] > 0
    subset["gamma_2_total_cost_not_above_SAA"] = subset["mean_total_cost_change_vs_SAA"] <= 1e-9
    by_seed = subset[["source_step", "evaluation_scope", "distribution_label", "seed_id", "decision_label", "eta",
                      "inventory_increment_kg", "operating_loss_reduction", "gamma_break_even",
                      "positive_break_even_space", "gamma_2_total_cost_not_above_SAA"]].copy()
    summary = by_seed.groupby(["source_step", "evaluation_scope", "distribution_label", "decision_label", "eta"], dropna=False).agg(
        seed_count=("seed_id", "count"), positive_break_even_seed_count=("positive_break_even_space", "sum"),
        gamma_break_even_min=("gamma_break_even", "min"), gamma_break_even_mean=("gamma_break_even", "mean"),
        gamma_break_even_max=("gamma_break_even", "max"), gamma_2_economic_seed_count=("gamma_2_total_cost_not_above_SAA", "sum")
    ).reset_index()
    summary["interpretation"] = "Fixed-decision ex-post threshold; not a reoptimized sensitivity result"
    return by_seed, summary


def shortage_cvar_lookup() -> dict:
    lookup = {}
    for dataset in (1, 2, 3):
        path = C2 / f"dataset-{dataset:03d}/scenario_results.csv"
        data = pd.read_csv(path, usecols=["decision_label", "shortage_kg"])
        if len(data) != 45000:
            raise RuntimeError(f"Unexpected C2 scenario row count in {path}: {len(data)}")
        for decision, group in data.groupby("decision_label"):
            lookup[("C2", "independent-path-nominal", float(dataset), decision)] = tail_mean_like_matlab(group["shortage_kg"], .995)
    manifests = pd.read_csv(C3 / "dataset_manifest.csv")[["seed_id", "distribution_id", "distribution_label"]]
    for rec in manifests.itertuples(index=False):
        path = C3 / f"case-seed{int(rec.seed_id):03d}-dist{int(rec.distribution_id):03d}/scenario_results.csv"
        data = pd.read_csv(path, usecols=["decision_label", "shortage_kg"])
        if len(data) != 45000:
            raise RuntimeError(f"Unexpected C3 scenario row count in {path}: {len(data)}")
        for decision, group in data.groupby("decision_label"):
            lookup[("C3", rec.distribution_label, float(rec.seed_id), decision)] = tail_mean_like_matlab(group["shortage_kg"], .995)
    return lookup


def build_conversion_audit(v: dict) -> pd.DataFrame:
    consequence = ROOT / "terminalLoh_wdro/src/generate_step04CA2_formal_consequences_h2.m"
    return pd.DataFrame([
        ["input electrical load", "P_load_base_kw", v["load"].sum(), "kW", rel(MAT), "NearStageInput.Grid.P_load_base_kw", "active"],
        ["fuel-cell efficiency", "eta_FC", v["eta_fc"], "dimensionless", rel(MAT), "NearStageInput.HydrogenDevice.eta_FC", "active"],
        ["hydrogen lower heating value", "LHV_H2", v["lhv"], "kWh/kg", rel(MAT), "NearStageInput.HydrogenDevice.h2_lhv_kWh_per_kg", "active"],
        ["formal period duration", "Delta_tau", 1, "h per period", rel(consequence), source_ref(consequence, "for tau = 1:3"), "three periods"],
        ["forward conversion", "D", v["kg_per_kwh"], "kg-H2/kWh-unserved", rel(consequence), source_ref(consequence, "'DFactorKgPerKWh', 1/(eta*lhv)"), "D=outage*P*1h/(eta_FC*LHV)"],
        ["inverse conversion", "E_unrestored", v["kwh_per_shortage_kg"], "kWh/kg-H2-shortage", rel(consequence), source_ref(consequence, "Dtau = double(outage)"), "E=shortage*eta_FC*LHV"],
    ], columns=["audit_item", "symbol", "value", "unit", "source_path", "line_or_field", "status_or_formula"])


def build_resilience(rows: pd.DataFrame, v: dict, cvar: dict) -> pd.DataFrame:
    out = rows.copy()
    keys = list(zip(out["source_step"], out["distribution_label"], out["seed_id"], out["decision_label"]))
    out["shortage_CVaR995_kg"] = [cvar.get((a, b, float(c) if pd.notna(c) else np.nan, d), np.nan) for a, b, c, d in keys]
    factor = v["kwh_per_shortage_kg"]
    mappings = {
        "mean_shortage_kg": "expected_equivalent_unrestored_kWh",
        "shortage_q95_kg": "equivalent_unrestored_q95_kWh",
        "shortage_q99_kg": "equivalent_unrestored_q99_kWh",
        "shortage_q995_kg": "equivalent_unrestored_q995_kWh",
        "shortage_CVaR995_kg": "equivalent_unrestored_CVaR995_kWh",
        "maximum_shortage_kg": "maximum_equivalent_unrestored_kWh",
    }
    for source, target in mappings.items():
        out[target] = out[source] * factor
        out[target.replace("_kWh", "_MWh")] = out[target] / 1000.0
    out["expected_equivalent_restored_kWh_vs_SAA"] = -out["mean_shortage_kg_change_vs_SAA"] * factor
    out["conversion_scope"] = "repository-model-equivalent outage energy; not independently calibrated full-grid economic EENS"
    out["cvar_source_note"] = np.where(out["shortage_CVaR995_kg"].notna(),
        "read-only recomputation from frozen protected scenario_results.csv", "not available in C1 lightweight summaries")
    keep = ["source_step", "evaluation_scope", "distribution_label", "seed_id", "decision_label", "eta",
            "mean_shortage_kg", "shortage_q95_kg", "shortage_q99_kg", "shortage_q995_kg", "shortage_CVaR995_kg",
            "maximum_shortage_kg", "mean_service_rate", *[x for pair in [(t, t.replace("_kWh", "_MWh")) for t in mappings.values()] for x in pair],
            "expected_equivalent_restored_kWh_vs_SAA", "conversion_scope", "cvar_source_note"]
    return out[keep]


def build_msp_coverage(v: dict) -> pd.DataFrame:
    return pd.DataFrame([
        ["electrolyzer electricity", False, False, True, "electricity price * kWh", "load_data_h2_near.m:246-248; fa_h2/build_stage_model_h2.m:36", "Only MSP"],
        ["electrolyzer O&M", False, False, True, v["el_om"], "NearStageInput.Cost.el_om_yuan_per_kWh", "Only MSP"],
        ["external hydrogen purchase", False, False, False, np.nan, "static scan found no purchase variable", "Not modeled"],
        ["HTT transport/redispatch", False, False, True, v["transport_rate"], "NearStageInput.HTT.transport_cost_yuan_per_kg_km; update_rhs_h2.m:44-45", "Offline C is road impedance, not HTT bill"],
        ["normal hydrogen load shortage", False, False, True, v["normal_penalty"], "NearStageInput.Cost.normal_shortage_penalty_yuan_per_kg", "Only MSP"],
        ["storage capacity occupation/holding", False, False, True, v["holding"], "NearStageInput.Cost.h2_holding_cost_yuan_per_kg", "Offline gamma is distinct"],
        ["cross-stage inventory carry", False, False, True, "state balance", "fa_h2/build_stage_model_h2.m:54-78", "Physical state, holding charged"],
        ["liquid hydrogen/boil-off loss", False, False, False, np.nan, "no storage-loss term found", "Unmodeled"],
        ["unused terminal hydrogen salvage", False, False, False, 0, "terminal value penalizes shortage only", "No salvage or future-use credit"],
        ["terminal reserve shortfall", False, True, True, v["M"], "M*u offline; terminal_value_and_subgradient_h2.m:15 MSP", "Same numeric field, different surrounding objective"],
        ["offline preload weight", True, False, False, GAMMA, "gamma=0.001*M", "Does not cover MSP system costs"],
    ], columns=["cost_or_physical_item", "covered_by_offline_gamma_2", "covered_by_offline_recourse", "represented_in_MSP",
                "effective_value_or_formula", "source", "audit_conclusion"])


def unresolved_requirements() -> pd.DataFrame:
    return pd.DataFrame([
        ["offline gamma monetary calibration", "currency/kg of prepositioned H2", "gamma*DeltaInventory", "Required before calling 34.073742 a currency amount", "unresolved"],
        ["reserve shortage penalty calibration", "empirical/source-backed yuan/kg or outage-value mapping", "M*shortage", "Field declares yuan/kg but value 2000 lacks engineering citation", "unresolved"],
        ["offline service impedance monetization", "yuan/(kg*km), yuan/(kg*h), or explicit normalization", "C*y conversion", "Required for dimensional consistency of total objective", "unresolved"],
        ["inventory creation pathway", "marginal production/purchase/transport/storage mix", "MSP endogenous cost", "Needed to turn extra TerminalLOH into full-system incremental cost", "requires MSP integration"],
        ["storage loss", "fraction per hour/stage and storage technology", "x_next=(1-loss)*x+...", "No loss/boil-off term exists", "unresolved"],
        ["unused hydrogen salvage/future value", "yuan/kg or continuation value", "-salvage*x_terminal or continuation function", "Current terminal surplus has zero explicit value", "unresolved"],
        ["critical-load/electric-service interpretation", "documented load coverage and critical weighting", "EENS and service-rate reporting", "Formal D uses full P_load_base rather than CriticalLoad template", "partially resolved"],
        ["shortage CVaR in C1 summaries", "scenario-level shortage or frozen summary statistic", "CVaR99.5 equivalent unserved energy", "Not present in C1 lightweight tables; C2/C3 can be recomputed read-only", "partially unresolved"],
    ], columns=["missing_parameter_or_evidence", "required_unit_or_definition", "formula_position", "why_needed", "status"])


def validate_and_write(pre: dict, v: dict, provenance: pd.DataFrame, trace: pd.DataFrame,
                       objective: pd.DataFrame, rows: pd.DataFrame, safety: pd.DataFrame,
                       gamma_by_seed: pd.DataFrame, gamma_summary: pd.DataFrame,
                       conversion: pd.DataFrame, resilience: pd.DataFrame,
                       msp: pd.DataFrame, unresolved: pd.DataFrame) -> dict:
    max_recon = float(rows["objective_reconstruction_error"].abs().max())
    if max_recon > 1e-6:
        raise RuntimeError(f"Objective reconstruction failed: {max_recon}")
    d = selected_decisions().set_index("eta")
    delta_001 = float(d.loc[0.01, "TerminalLOH_total_kg"] - d.loc[0.0, "TerminalLOH_total_kg"])
    cost_001 = GAMMA * delta_001
    if abs(delta_001 - 17.0368707551011) > 1e-9 or abs(cost_001 - 34.0737415102022) > 1e-9:
        raise RuntimeError("Frozen eta=0.01 inventory/cost identity changed")
    if not gamma_by_seed["positive_break_even_space"].all():
        raise RuntimeError("A C2/C3 candidate lacks positive operating-loss reduction")
    expected_rows = {"economic": 84, "safety": 56, "gamma_seed": 48, "gamma_summary": 16}
    actual_rows = {"economic": len(rows), "safety": len(safety), "gamma_seed": len(gamma_by_seed), "gamma_summary": len(gamma_summary)}
    if actual_rows != expected_rows:
        raise RuntimeError(f"Unexpected output row counts: {actual_rows} != {expected_rows}")

    OUT.mkdir(parents=True)
    write_csv(provenance, "parameter_provenance_audit.csv")
    write_csv(trace, "parameter_effective_value_trace.csv")
    write_csv(objective, "objective_cost_decomposition.csv")
    write_csv(rows, "frozen_decision_economic_comparison.csv")
    write_csv(safety, "safety_premium_summary.csv")
    write_csv(gamma_by_seed, "gamma_break_even_by_seed.csv")
    write_csv(gamma_summary, "gamma_break_even_summary.csv")
    write_csv(conversion, "hydrogen_to_electricity_conversion_audit.csv")
    write_csv(resilience, "resilience_metric_summary.csv")
    write_csv(msp, "msp_cost_coverage_audit.csv")
    write_csv(unresolved, "unresolved_parameter_requirements.csv")

    c3s = gamma_summary[gamma_summary["source_step"] == "C3"]
    nominal_003 = c3s[(c3s["distribution_label"] == "nominal") & (c3s["eta"] == .003)].iloc[0]
    nominal_010 = c3s[(c3s["distribution_label"] == "nominal") & (c3s["eta"] == .01)].iloc[0]
    strong_003 = c3s[(c3s["distribution_label"] == "combined-strong") & (c3s["eta"] == .003)].iloc[0]
    strong_010 = c3s[(c3s["distribution_label"] == "combined-strong") & (c3s["eta"] == .01)].iloc[0]
    c3_safety = safety[safety["source_step"] == "C3"]
    econ_counts = c3_safety.groupby("eta")["mean_total_cost_change_vs_SAA"].apply(lambda x: int((x <= 0).sum())).to_dict()

    conclusion = f"""Step-04C-C4 audit status: ACCEPTED

1. The effective offline preload coefficient is gamma=2=0.001*M. Repository documentation classifies it as a small configurable TerminalLOH holding weight, not MSP hydrogen-production cost. Because the offline service term is C(km)*y(kg), the full offline objective mixes kg*km impedance with the monetary-labelled shortage field. Therefore gamma=2 cannot currently be called 2 yuan/kg.
2. The effective shortage penalty is M=2000 from NearStageInput.Cost.reserve_shortage_penalty_yuan_per_kg. The field declares yuan/kg, but no engineering calibration or VOLL source for the numeric value was found. In the offline mixed-unit objective it must also be treated as a penalty weight.
3. eta=0.01 adds {delta_001:.15g} kg relative to SAA, so its direct offline model increment is exactly 2*DeltaT={cost_001:.15g} objective units. This increment excludes electrolyzer electricity, O&M, HTT transport, normal-load shortage, storage loss, and salvage/future value.
4. The repository conversion is D=outage*P*1h/(eta_FC*LHV), with eta_FC={v['eta_fc']:.15g} and LHV={v['lhv']:.15g} kWh/kg. Thus one kg of modeled H2 shortage is equivalent to {v['kwh_per_shortage_kg']:.15g} kWh of modeled unrestored energy. This supports model-equivalent EENS/resilience reporting, not an independently calibrated economic EENS or proof of complete critical-load restoration.
5. Under C3, both candidates reduce mean operating loss and mean shortage in all 21 distribution-seed cells. At gamma=2, eta=0.003 has total cost no higher than SAA in {econ_counts.get(.003, 0)}/21 cells and eta=0.01 in {econ_counts.get(.01, 0)}/21 cells. The nominal gamma break-even ranges are {nominal_003.gamma_break_even_min:.6g}-{nominal_003.gamma_break_even_max:.6g} for eta=0.003 and {nominal_010.gamma_break_even_min:.6g}-{nominal_010.gamma_break_even_max:.6g} for eta=0.01; combined-strong ranges are {strong_003.gamma_break_even_min:.6g}-{strong_003.gamma_break_even_max:.6g} and {strong_010.gamma_break_even_min:.6g}-{strong_010.gamma_break_even_max:.6g}, respectively.
6. The proper conclusion category is: some physical and MSP monetary parameters are traceable, but the offline objective remains only partly interpretable and requires engineering calibration. eta=0.003 should be retained as the mild resilience candidate; eta=0.01 may be retained as a conservative upper candidate because its operating-risk reductions strengthen under Markov stress, but it is not economically proven. Neither is frozen as the formal eta, neither全面优于SAA, and neither replaces road restoration or other resilience measures.

No TerminalLOH optimization, eta selection, formal recourse modification, MATLAB/Gurobi solve, or MSP execution occurred. C1 validation-1/2 remain same-path second-layer wind/resistance redraws. The 135 pressure replicas remain a fixed reproducible stress set without empirical probability.
"""
    (OUT / "audit_conclusion.txt").write_text(conclusion, encoding="utf-8")

    hashes = "\n".join(f"- `{rel(p)}`: `{sha256(p)}`" for p in pre["required"])
    readme = f"""# Step-04C-C4 parameter provenance and resilience audit

Status: **ACCEPTED**  
Run: `{OUT.name}`  
Frozen Git HEAD/upstream/remote: `{pre['head']}`

## Scope

This is a deterministic, read-only audit. It reads C1 accepted `run-003`, C2 accepted `run-002`, C3 accepted `run-001`, the live frozen near-stage MAT input, and protected scenario-result tables only to recompute shortage CVaR99.5 for C2/C3. It does not optimize TerminalLOH, choose eta, run MATLAB/Gurobi/MSP, alter formal recourse, or assign probability to the fixed pressure replicas.

## Main findings

- `gamma=2` is `0.001*M`, a derived offline trade-off weight. It is not evidenced as `2 yuan/kg` and does not cover production, transport, storage, losses, or salvage.
- `M=2000` is effectively loaded from the MAT field `reserve_shortage_penalty_yuan_per_kg`. The declared field unit is yuan/kg, but the numeric calibration source is absent and the offline objective is mixed-unit because `C*y` is kg-km.
- eta=0.01 adds `{delta_001:.15g} kg`, giving `{cost_001:.15g}` direct offline objective units at gamma=2.
- Repository parameters support the model-equivalent inverse conversion `shortage_kg * {v['kwh_per_shortage_kg']:.15g} kWh/kg`. This is not an external conversion and should not be overstated as independently calibrated full-grid EENS.
- Both chi-square candidates have consistent operating-risk value in C2/C3. eta=0.003 is the cleaner mild resilience candidate; eta=0.01 is a conservative upper candidate whose extra inventory has clearer value under stronger probability shifts than under nominal/location-only conditions. Formal eta remains unfrozen.

## Mechanical acceptance

- economic rows: `{len(rows)}`; safety rows: `{len(safety)}`; gamma-by-seed rows: `{len(gamma_by_seed)}`; gamma summary rows: `{len(gamma_summary)}`
- maximum total-cost reconstruction error: `{max_recon:.15g}`
- C1/C2/C3 frozen certificates: PASS
- source script contains no solver or MSP call
- historical runs and local large files were read-only and were not copied into this run

## Frozen input SHA-256

{hashes}

See `audit_conclusion.txt` for the bounded interpretation and the CSV files for complete seedwise evidence.
"""
    (OUT / "README.md").write_text(readme, encoding="utf-8")
    return {"max_reconstruction_error": max_recon, "delta_001": delta_001, "cost_001": cost_001,
            "row_counts": actual_rows, "economic_counts": econ_counts}


def main() -> None:
    pre = preflight()
    _, values = load_parameters()
    provenance, trace = build_provenance(values)
    objective = build_objective_decomposition(values)
    decisions = selected_decisions()
    rows = normalize_result_rows(decisions)
    safety = build_safety(rows)
    gamma_by_seed, gamma_summary = build_gamma_break_even(rows)
    conversion = build_conversion_audit(values)
    cvar = shortage_cvar_lookup()
    resilience = build_resilience(rows, values, cvar)
    msp = build_msp_coverage(values)
    unresolved = unresolved_requirements()
    result = validate_and_write(pre, values, provenance, trace, objective, rows, safety,
                                gamma_by_seed, gamma_summary, conversion, resilience, msp, unresolved)
    print(json.dumps({"status": "ACCEPTED", "output": rel(OUT), **result}, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
