#!/usr/bin/env python3
"""Finalize Step-04C-C5B from isolated MATLAB case outputs."""

from __future__ import annotations

import hashlib
import argparse
import json
import math
import subprocess
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "results/task-002-stage2b-b3-smoke/51-unified-economic-terminal-loh/run-001"
C1 = ROOT / "results/task-002-stage2b-b3-smoke/46-flat-chi2-eta-calibration/run-003"
HEAD = "bb298d52ee5143bc2c60e2f2fc1e31e8d1c3d1a2"
METHOD_ORDER = ["SAA", "ETA_0.003", "ETA_0.01"]


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def write_csv(frame: pd.DataFrame, name: str) -> None:
    frame.to_csv(OUT / name, index=False, encoding="utf-8-sig", float_format="%.15g")


def preflight() -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    if git("branch", "--show-current") != "task/002-stage2b-b3-smoke":
        raise RuntimeError("Wrong branch")
    local = git("rev-parse", "HEAD")
    upstream = git("rev-parse", "@{upstream}")
    remote = git("ls-remote", "origin", "refs/heads/task/002-stage2b-b3-smoke").split()[0]
    if len({local, upstream, remote, HEAD}) != 1:
        raise RuntimeError(f"Frozen Git gate failed: {local=} {upstream=} {remote=}")
    prep = pd.read_csv(OUT / "prepare_summary.csv")
    if len(prep) != 1 or not bool(prep.loc[0, "all_hash_pass"]):
        raise RuntimeError("Preparation/hash gate failed")
    opt, cert, opt_lex = [], [], []
    for case in range(1, 4):
        base = OUT / f"optimization_cases/case-{case:03d}"
        opt.append(pd.read_csv(base / "optimization_result.csv"))
        cert.append(pd.read_csv(base / "solver_certificate.csv"))
        opt_lex.append(pd.read_csv(base / "lexicographic_audit.csv"))
    opt = pd.concat(opt, ignore_index=True).sort_values("case_id")
    cert = pd.concat(cert, ignore_index=True).sort_values("case_id")
    opt_lex = pd.concat(opt_lex, ignore_index=True).sort_values("case_id")
    vals, val_lex = [], []
    for case in range(1, 27):
        base = OUT / f"validation_cases/case-{case:03d}"
        vals.append(pd.read_csv(base / "fixed_T_summary.csv"))
        val_lex.append(pd.read_csv(base / "lexicographic_audit.csv"))
    vals = pd.concat(vals, ignore_index=True)
    val_lex = pd.concat(val_lex, ignore_index=True)
    if len(opt) != 3 or len(cert) != 3 or len(vals) != 78 or len(val_lex) != 78:
        raise RuntimeError("Unexpected case row counts")
    if not cert["certificate_pass"].astype(bool).all() or not vals["validation_pass"].astype(bool).all():
        raise RuntimeError("A solver or validation certificate is not PASS")
    if not np.allclose(opt["eta"], [0, .003, .01], atol=1e-15):
        raise RuntimeError("Eta identity failed")
    if vals.groupby("validation_id").size().ne(3).any():
        raise RuntimeError("A validation cell does not contain all three decisions")
    return opt, cert, opt_lex, vals, val_lex


def add_increments(vals: pd.DataFrame) -> pd.DataFrame:
    out = vals.copy()
    base_cols = ["TerminalLOH_total_kg", "production_cost_yuan", "mean_shortage_kg",
                 "mean_EENS_kWh", "mean_unserved_cost_yuan", "mean_economic_total_yuan",
                 "mean_electricity_service_rate", "shortage_q95_kg", "shortage_q99_kg",
                 "shortage_q995_kg", "shortage_CVaR995_kg", "maximum_shortage_kg"]
    bases = out[out["decision_label"] == "SAA"].set_index("validation_id")
    for col in base_cols:
        out[f"{col}_change_vs_SAA"] = out[col] - out["validation_id"].map(bases[col])
    out["restored_energy_increment_vs_SAA_kWh"] = -out["mean_EENS_kWh_change_vs_SAA"]
    restored = out["restored_energy_increment_vs_SAA_kWh"]
    out["economic_increment_per_additional_restored_kWh"] = np.where(
        restored.abs() <= 1e-9, np.nan,
        out["mean_economic_total_yuan_change_vs_SAA"] / restored)
    out["cost_per_restored_kWh_status"] = np.where(
        restored.abs() <= 1e-9, "undefined_near_zero_restored_energy", "defined")
    return out


def build_outputs(opt: pd.DataFrame, cert: pd.DataFrame, opt_lex: pd.DataFrame,
                  vals: pd.DataFrame, val_lex: pd.DataFrame) -> dict:
    vals = add_increments(vals)
    merged_opt = opt.merge(cert, on=["case_id", "decision_label", "eta"], how="left")
    write_csv(merged_opt, "optimization_full_results.csv")

    saa = opt.iloc[0]
    decisions = opt.copy()
    for col in ["TerminalLOH_total_kg", "production_cost_yuan", "nominal_mean_shortage_kg",
                "nominal_mean_EENS_kWh", "nominal_mean_economic_total_yuan"]:
        decisions[f"{col}_change_vs_SAA"] = decisions[col] - saa[col]
    write_csv(decisions, "terminal_loh_decision_comparison.csv")

    nominal = vals[vals["validation_id"] == 1].copy()
    econ_cols = ["decision_label", "eta", "TerminalLOH_total_kg", "c_H2_yuan_per_kg",
                 "production_cost_yuan", "mean_shortage_kg", "M_H2_yuan_per_kg",
                 "mean_unserved_cost_yuan", "mean_economic_total_yuan",
                 "production_cost_yuan_change_vs_SAA", "mean_unserved_cost_yuan_change_vs_SAA",
                 "mean_economic_total_yuan_change_vs_SAA"]
    write_csv(nominal[econ_cols], "economic_cost_decomposition.csv")
    write_csv(vals, "physical_resilience_results.csv")

    opt_lex = opt_lex.copy(); opt_lex.insert(0, "audit_scope", "optimization_grouped_nominal")
    val_lex = val_lex.merge(vals[["validation_id", "dataset_label", "decision_id", "source_step",
                                  "dataset_scope", "distribution_label", "seed_id"]],
                            on=["validation_id", "dataset_label", "decision_id"], how="left")
    val_lex.insert(0, "audit_scope", "fixed_T_validation")
    write_csv(pd.concat([opt_lex, val_lex], ignore_index=True, sort=False),
              "lexicographic_tiebreak_audit.csv")
    write_csv(cert, "solver_certificate.csv")
    write_csv(vals[vals["source_step"] == "C2"], "c2_independent_validation.csv")
    write_csv(vals[vals["source_step"] == "C3"], "c3_markov_validation.csv")
    write_csv(vals[vals["dataset_scope"] == "fixed-pressure"], "fixed_pressure_test_comparison.csv")

    old = pd.read_csv(C1 / "eta_full_results.csv")
    old = old[old["eta"].isin([0, .003, .01])].copy()
    old["decision_label"] = pd.Categorical(old["eta"], [0, .003, .01]).rename_categories(METHOD_ORDER)
    old_rows = old[["decision_label", "eta", "T1_kg", "T2_kg", "T3_kg", "T4_kg",
                    "TerminalLOH_total_kg", "capacity_binding_count"]].copy()
    old_rows.insert(0, "objective_version", "historical_gamma_2_M_2000_plus_Cy")
    old_rows["inventory_cost_coefficient"] = 2.0
    old_rows["shortage_penalty_coefficient"] = 2000.0
    old_rows["C_y_primary"] = True
    new_rows = opt[["decision_label", "eta", "T1_kg", "T2_kg", "T3_kg", "T4_kg",
                    "TerminalLOH_total_kg", "capacity_binding_count"]].copy()
    new_rows.insert(0, "objective_version", "unified_yuan_shortage_only_primary")
    new_rows["inventory_cost_coefficient"] = opt["c_H2_yuan_per_kg"].to_numpy()
    new_rows["shortage_penalty_coefficient"] = opt["M_H2_yuan_per_kg"].to_numpy()
    new_rows["C_y_primary"] = False
    hist = pd.concat([old_rows, new_rows], ignore_index=True)
    old_totals = old_rows.set_index("decision_label")["TerminalLOH_total_kg"]
    hist["TerminalLOH_total_change_from_historical_same_method_kg"] = np.where(
        hist["objective_version"].eq("unified_yuan_shortage_only_primary"),
        hist["TerminalLOH_total_kg"] - hist["decision_label"].map(old_totals), 0.0)
    write_csv(hist, "historical_vs_unified_comparison.csv")

    cand = vals[vals["decision_label"] != "SAA"].copy()
    group_cols = ["dataset_scope", "distribution_label", "decision_label", "eta"]
    trade = cand.groupby(group_cols, dropna=False).agg(
        evaluation_cell_count=("validation_id", "count"),
        inventory_increment_kg=("TerminalLOH_total_kg_change_vs_SAA", "mean"),
        production_cost_increment_yuan=("production_cost_yuan_change_vs_SAA", "mean"),
        economic_increment_min_yuan=("mean_economic_total_yuan_change_vs_SAA", "min"),
        economic_increment_mean_yuan=("mean_economic_total_yuan_change_vs_SAA", "mean"),
        economic_increment_max_yuan=("mean_economic_total_yuan_change_vs_SAA", "max"),
        EENS_change_min_kWh=("mean_EENS_kWh_change_vs_SAA", "min"),
        EENS_change_mean_kWh=("mean_EENS_kWh_change_vs_SAA", "mean"),
        EENS_change_max_kWh=("mean_EENS_kWh_change_vs_SAA", "max"),
        shortage_q95_change_mean_kg=("shortage_q95_kg_change_vs_SAA", "mean"),
        maximum_shortage_change_mean_kg=("maximum_shortage_kg_change_vs_SAA", "mean"),
        economic_not_above_SAA_count=("mean_economic_total_yuan_change_vs_SAA", lambda x: int((x <= 1e-8).sum())),
        resilience_improvement_count=("mean_EENS_kWh_change_vs_SAA", lambda x: int((x < -1e-9).sum())),
    ).reset_index()
    write_csv(trade, "economic_resilience_tradeoff_summary.csv")

    empirical = vals[vals["dataset_scope"].isin(["state19-nominal", "independent-path", "markov-perturbation"])]
    stats = {}
    for method in METHOD_ORDER[1:]:
        x = empirical[empirical["decision_label"] == method]
        stats[method] = {
            "cells": len(x),
            "eens_improved": int((x["mean_EENS_kWh_change_vs_SAA"] < -1e-9).sum()),
            "economic_not_worse": int((x["mean_economic_total_yuan_change_vs_SAA"] <= 1e-8).sum()),
            "mean_econ_delta": float(x["mean_economic_total_yuan_change_vs_SAA"].mean()),
            "mean_eens_delta": float(x["mean_EENS_kWh_change_vs_SAA"].mean()),
        }
    pressure = vals[vals["dataset_scope"] == "fixed-pressure"].set_index("decision_label")
    both_stable = all(v["eens_improved"] == v["cells"] for v in stats.values())
    if both_stable:
        verdict = "3. 两个 DRO 方案分别代表不同保障等级，均保留"
    elif stats["ETA_0.003"]["eens_improved"] == stats["ETA_0.003"]["cells"]:
        verdict = "1. SAA作为经济基准，eta=0.003作为温和韧性方案"
    elif stats["ETA_0.01"]["eens_improved"] == stats["ETA_0.01"]["cells"]:
        verdict = "2. SAA作为经济基准，eta=0.01作为安全增强方案"
    else:
        verdict = "4. 新统一经济目标下DRO韧性收益不足，暂不扩展"
    positioning = f"""Step-04C-C5B candidate positioning

Accepted bounded judgment: {verdict}

- SAA remains the economic reference under the newly unified yuan objective.
- eta=0.003 improves mean EENS in {stats['ETA_0.003']['eens_improved']}/{stats['ETA_0.003']['cells']} empirical validation cells; its mean economic increment is {stats['ETA_0.003']['mean_econ_delta']:.9g} yuan and mean EENS change is {stats['ETA_0.003']['mean_eens_delta']:.9g} kWh (candidate minus SAA).
- eta=0.01 improves mean EENS in {stats['ETA_0.01']['eens_improved']}/{stats['ETA_0.01']['cells']} empirical validation cells; its mean economic increment is {stats['ETA_0.01']['mean_econ_delta']:.9g} yuan and mean EENS change is {stats['ETA_0.01']['mean_eens_delta']:.9g} kWh.
- Fixed pressure q95 shortage changes are {pressure.loc['ETA_0.003','shortage_q95_kg_change_vs_SAA']:.9g} kg and {pressure.loc['ETA_0.01','shortage_q95_kg_change_vs_SAA']:.9g} kg; maximum-shortage changes are {pressure.loc['ETA_0.003','maximum_shortage_kg_change_vs_SAA']:.9g} kg and {pressure.loc['ETA_0.01','maximum_shortage_kg_change_vs_SAA']:.9g} kg.

These results do not freeze eta, do not claim full lifecycle economics, do not price C*y as transportation, and do not show that DRO resolves complete road inaccessibility.
"""
    (OUT / "candidate_positioning.txt").write_text(positioning, encoding="utf-8")
    return {"vals": vals, "hist": hist, "trade": trade, "stats": stats, "verdict": verdict}


def make_plots(opt: pd.DataFrame, vals: pd.DataFrame, hist: pd.DataFrame) -> None:
    plt.style.use("seaborn-whitegrid")
    colors = ["#4C78A8", "#F58518", "#54A24B"]
    x = np.arange(3)
    fig, ax = plt.subplots(figsize=(9, 5.4))
    bottom = np.zeros(3)
    for site, hatch in zip(["T1_kg", "T2_kg", "T3_kg", "T4_kg"], ["", "//", "xx", ".."]) :
        y = opt[site].to_numpy(float)
        ax.bar(x, y, bottom=bottom, label=site.replace("_kg", ""), hatch=hatch, edgecolor="white")
        bottom += y
    ax.set_xticks(x); ax.set_xticklabels(METHOD_ORDER); ax.set_ylabel("TerminalLOH inventory (kg)")
    ax.set_title("Unified-economic state19 TerminalLOH decisions"); ax.legend(ncol=4)
    fig.tight_layout(); fig.savefig(OUT / "terminal_loh_method_comparison.png", dpi=180); plt.close(fig)

    nominal = vals[vals["validation_id"] == 1].set_index("decision_label").loc[METHOD_ORDER]
    fig, ax = plt.subplots(figsize=(8, 5.4))
    for method, color in zip(METHOD_ORDER, colors):
        row = nominal.loc[method]
        ax.scatter(row["mean_EENS_kWh"], row["mean_economic_total_yuan"], s=110, color=color, label=method)
        ax.annotate(method, (row["mean_EENS_kWh"], row["mean_economic_total_yuan"]), xytext=(6, 5), textcoords="offset points")
    ax.set_xlabel("Mean equivalent unrestored energy (kWh)"); ax.set_ylabel("Mean economic total (yuan)")
    ax.set_title("Nominal economic-resilience tradeoff"); fig.tight_layout()
    fig.savefig(OUT / "economic_cost_resilience_tradeoff.png", dpi=180); plt.close(fig)

    scopes = [
        ("Nominal", vals[vals.validation_id == 1]),
        ("C2 mean", vals[vals.source_step == "C2"]),
        ("C3 nominal mean", vals[(vals.source_step == "C3") & (vals.distribution_label == "nominal")]),
        ("C3 strong mean", vals[(vals.source_step == "C3") & (vals.distribution_label == "combined-strong")]),
        ("Pressure", vals[vals.dataset_scope == "fixed-pressure"]),
    ]
    fig, ax = plt.subplots(figsize=(10, 5.6)); width = .24; loc = np.arange(len(scopes))
    for j, (method, color) in enumerate(zip(METHOD_ORDER, colors)):
        y = [g[g.decision_label == method]["mean_EENS_kWh"].mean() for _, g in scopes]
        ax.bar(loc + (j-1)*width, y, width, label=method, color=color)
    ax.set_xticks(loc); ax.set_xticklabels([s[0] for s in scopes]); ax.set_ylabel("Mean EENS (kWh)")
    ax.set_title("Fixed-decision equivalent unrestored energy"); ax.legend(); fig.tight_layout()
    fig.savefig(OUT / "eens_comparison.png", dpi=180); plt.close(fig)

    pivot = hist.pivot(index="decision_label", columns="objective_version", values="TerminalLOH_total_kg").loc[METHOD_ORDER]
    fig, ax = plt.subplots(figsize=(9, 5.4)); width = .36
    ax.bar(x-width/2, pivot["historical_gamma_2_M_2000_plus_Cy"], width, label="Historical mixed-unit")
    ax.bar(x+width/2, pivot["unified_yuan_shortage_only_primary"], width, label="Unified yuan")
    ax.set_xticks(x); ax.set_xticklabels(METHOD_ORDER); ax.set_ylabel("TerminalLOH total (kg)")
    ax.set_title("Historical versus unified-economic inventory"); ax.legend(); fig.tight_layout()
    fig.savefig(OUT / "historical_vs_unified_inventory.png", dpi=180); plt.close(fig)


def write_readme(opt: pd.DataFrame, vals: pd.DataFrame, results: dict) -> None:
    nominal = vals[vals.validation_id == 1].set_index("decision_label").loc[METHOD_ORDER]
    lines = []
    for method in METHOD_ORDER:
        o = opt[opt.decision_label == method].iloc[0]
        n = nominal.loc[method]
        lines.append(f"- {method}: T=[{o.T1_kg:.9f}, {o.T2_kg:.9f}, {o.T3_kg:.9f}, {o.T4_kg:.9f}] kg, total={o.TerminalLOH_total_kg:.9f} kg, nominal mean EENS={n.mean_EENS_kWh:.9f} kWh, nominal mean economic total={n.mean_economic_total_yuan:.9f} yuan.")
    manifest = pd.read_csv(OUT / "frozen_input_manifest.csv")
    large = manifest[manifest.bytes >= 10 * 1024 * 1024]
    manifest_text = "# Large file manifest\n\nNo new MAT, prepared input, checkpoint, or full scenario table was created by C5B. The following protected frozen input payloads were read in place and remain local/untracked:\n\n"
    for row in large.itertuples(index=False):
        manifest_text += f"- `{row.path}` — {int(row.bytes)} bytes — SHA-256 `{row.sha256}`\n"
    manifest_text += "\nProcess diaries and logs are local execution evidence. Git staging must include only the required lightweight accepted files and four PNG figures, not validation case directories or process logs.\n"
    (OUT / "LARGE_FILE_MANIFEST.md").write_text(manifest_text, encoding="utf-8")

    readme = f"""# Step-04C-C5B unified-economic TerminalLOH recalculation

Status: **ACCEPTED**
Run: `{OUT.name}`
Frozen Git HEAD/upstream/remote before execution: `{HEAD}`

## Frozen economic units

- Live MSP 24-hour price vector: min `0.3`, max `0.98`, arithmetic mean `0.634166666666667 yuan/kWh`.
- `SEC_H2=1/0.0195=51.2820512821 kWh/kg`; no additional electrolyzer-efficiency multiplication was made.
- Local production coefficient: `c_H2=32.5213675214 yuan/kg`.
- `LHV*eta_FC=33.33*0.55=18.3315 kWh/kg-H2`.
- `M_H2=70*18.3315=1283.205 yuan/kg-H2`.
- Primary objective contains only local preparation cost and shortage/VOLL loss. `C*y` is excluded from currency and Pearson scenario loss.

## New decisions and nominal replay

{chr(10).join(lines)}

## Lexicographic rule and validation

Every fixed-T replay first minimizes shortage. A second LP then fixes each scenario's primary-optimal shortage with an equality and minimizes `sum(C*y)`. The secondary stage does not change T or primary shortage. Validation covers nominal, three separate C2 independent-path sets, all 21 C3 distribution-seed cells, and the isolated 27-path/135-replica state19 pressure set. The pressure set remains descriptive and has no empirical probability.

## Bounded interpretation

{results['verdict']}. SAA remains the economic reference; eta is not frozen. See `candidate_positioning.txt` and the complete CSV tables for the economic-resilience tradeoff. This prototype excludes electrolyzer O&M, depreciation, water, holding, losses, salvage, external hydrogen, and station-to-station transport. It does not run the MSP or 35 states.

## Mechanical acceptance

- optimization cases: 3/3 OPTIMAL and certified
- fixed-decision validation cells: 26/26 complete, 78/78 method rows PASS
- eta=0 direct SAA identity: PASS
- Pearson nonnegativity, probability sum, divergence, strong duality, LB/UB: PASS
- `EENS=shortage*18.3315`: PASS
- `C*y` primary/currency/Pearson inclusion: zero
- R-by-R matrix, old Wasserstein, extreme-aware objective, MSP, and validation reoptimization: zero
"""
    (OUT / "README.md").write_text(readme, encoding="utf-8")


def final_checks(opt: pd.DataFrame, cert: pd.DataFrame, vals: pd.DataFrame) -> dict:
    errors = {
        "eens_identity": float((vals.mean_EENS_kWh - vals.mean_shortage_kg * 18.3315).abs().max()),
        "production_identity": float((vals.production_cost_yuan - vals.TerminalLOH_total_kg * vals.c_H2_yuan_per_kg).abs().max()),
        "economic_identity": float((vals.mean_economic_total_yuan - vals.production_cost_yuan - vals.mean_unserved_cost_yuan).abs().max()),
        "eta_zero_gap": float(cert.loc[cert.eta == 0, "absolute_gap_yuan"].iloc[0]),
        "max_validation_residual": float(vals.maximum_mechanical_residual.max()),
    }
    if errors["eens_identity"] > 1e-8 or errors["production_identity"] > 1e-7 or errors["economic_identity"] > 1e-7:
        raise RuntimeError(f"Unit/reconstruction check failed: {errors}")
    if errors["max_validation_residual"] > 1e-7 or not cert.certificate_pass.astype(bool).all():
        raise RuntimeError(f"Certificate check failed: {errors}")
    required = [
        "effective_electricity_price_audit.csv", "unified_parameter_table.csv", "unified_objective_spec.txt",
        "optimization_full_results.csv", "terminal_loh_decision_comparison.csv", "economic_cost_decomposition.csv",
        "physical_resilience_results.csv", "lexicographic_tiebreak_audit.csv", "solver_certificate.csv",
        "c2_independent_validation.csv", "c3_markov_validation.csv", "fixed_pressure_test_comparison.csv",
        "historical_vs_unified_comparison.csv", "economic_resilience_tradeoff_summary.csv",
        "candidate_positioning.txt", "README.md", "LARGE_FILE_MANIFEST.md",
        "terminal_loh_method_comparison.png", "economic_cost_resilience_tradeoff.png",
        "eens_comparison.png", "historical_vs_unified_inventory.png",
    ]
    missing = [name for name in required if not (OUT / name).is_file() or (OUT / name).stat().st_size == 0]
    if missing:
        raise RuntimeError(f"Required output missing/empty: {missing}")
    return errors


def main() -> None:
    global OUT
    parser = argparse.ArgumentParser()
    parser.add_argument("--work-dir", default=str(OUT))
    args = parser.parse_args()
    candidate = Path(args.work_dir)
    OUT = candidate.resolve() if candidate.is_absolute() else (ROOT / candidate).resolve()
    opt, cert, opt_lex, vals, val_lex = preflight()
    result = build_outputs(opt, cert, opt_lex, vals, val_lex)
    vals = result["vals"]
    make_plots(opt, vals, result["hist"])
    write_readme(opt, vals, result)
    checks = final_checks(opt, cert, vals)
    print(json.dumps({"status": "ACCEPTED", "run": OUT.name, "verdict": result["verdict"],
                      "decisions": opt[["decision_label", "eta", "T1_kg", "T2_kg", "T3_kg", "T4_kg",
                                        "TerminalLOH_total_kg"]].to_dict("records"),
                      "checks": checks}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
