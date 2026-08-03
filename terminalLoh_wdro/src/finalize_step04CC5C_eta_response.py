from __future__ import annotations

import argparse
import hashlib
import subprocess
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from scipy.io import loadmat

EXPECTED_HEAD = "309639d5d9c18a8951227fd5cfa04d5eeb20e9ef"
EXPECTED_BRANCH = "task/002-stage2b-b3-smoke"
ETA = np.array([0.0, 0.0003, 0.001, 0.003, 0.01, 0.03])
ELECTRICITY_PER_KG = 18.3315
TOL = 1e-9


def git(repo: Path, *args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=repo, text=True).strip()


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def write_csv(work: Path, frame: pd.DataFrame, name: str) -> None:
    frame.to_csv(work / name, index=False, float_format="%.15g")


def read_cases(work: Path, count: int, subdir: str, filename: str) -> pd.DataFrame:
    rows = []
    for i in range(1, count + 1):
        path = work / subdir / f"case-{i:03d}" / filename
        if not path.is_file():
            raise RuntimeError(f"Missing case output: {path}")
        rows.append(pd.read_csv(path))
    return pd.concat(rows, ignore_index=True)


def add_validation_deltas(frame: pd.DataFrame) -> pd.DataFrame:
    out = frame.copy()
    metrics = [
        "TerminalLOH_total_kg", "production_cost_yuan", "mean_shortage_kg",
        "mean_EENS_kWh", "mean_economic_total_yuan", "mean_electricity_service_rate",
        "shortage_q95_kg", "shortage_q99_kg", "shortage_q995_kg",
        "shortage_CVaR95_kg", "shortage_CVaR99_kg", "shortage_CVaR995_kg",
        "maximum_shortage_kg",
    ]
    for _, idx in out.groupby("validation_id").groups.items():
        group = out.loc[idx]
        saa = group.loc[np.isclose(group["eta"], 0.0)]
        if len(saa) != 1:
            raise RuntimeError("Each validation dataset must contain exactly one SAA row.")
        for metric in metrics:
            out.loc[idx, f"{metric}_change_vs_SAA"] = group[metric] - float(saa.iloc[0][metric])
    return out


def build_response(opt: pd.DataFrame, nominal: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    opt = opt.sort_values("case_id").reset_index(drop=True)
    nominal = nominal.sort_values("decision_id").reset_index(drop=True)
    if not np.allclose(opt["eta"], ETA, atol=1e-14, rtol=0):
        raise RuntimeError("Optimization eta grid does not match the frozen six-point grid.")
    response = opt.copy()
    for col in ["T1_kg", "T2_kg", "T3_kg", "T4_kg", "TerminalLOH_total_kg",
                "production_cost_yuan", "nominal_mean_EENS_kWh",
                "nominal_mean_economic_total_yuan"]:
        response[f"{col}_change_vs_SAA"] = response[col] - response.loc[0, col]
        response[f"{col}_change_vs_previous_eta"] = response[col].diff()
    restored = response.loc[0, "nominal_mean_EENS_kWh"] - response["nominal_mean_EENS_kWh"]
    net = response["nominal_mean_economic_total_yuan"] - response.loc[0, "nominal_mean_economic_total_yuan"]
    response["nominal_restored_energy_vs_SAA_kWh"] = restored
    response["net_economic_increment_per_restored_kWh"] = np.where(
        np.abs(restored) > TOL, net / restored, np.nan
    )
    inv_delta = response["TerminalLOH_total_kg"].diff()
    eens_gain = -response["nominal_mean_EENS_kWh"].diff()
    response["marginal_EENS_improvement_per_added_kg"] = np.where(
        np.abs(inv_delta) > TOL, eens_gain / inv_delta, np.nan
    )
    econ = nominal[[
        "decision_id", "eta", "mean_shortage_kg", "mean_EENS_kWh",
        "mean_electricity_service_rate", "mean_unserved_cost_yuan",
        "mean_economic_total_yuan", "shortage_q95_kg", "shortage_q99_kg",
        "shortage_q995_kg", "shortage_CVaR95_kg", "shortage_CVaR99_kg",
        "shortage_CVaR995_kg", "maximum_shortage_kg", "maximum_EENS_kWh",
    ]].copy()
    econ["economic_total_change_vs_SAA"] = econ["mean_economic_total_yuan"] - econ.loc[0, "mean_economic_total_yuan"]
    econ["EENS_change_vs_SAA"] = econ["mean_EENS_kWh"] - econ.loc[0, "mean_EENS_kWh"]
    econ["economic_total_change_vs_previous_eta"] = econ["mean_economic_total_yuan"].diff()
    econ["EENS_change_vs_previous_eta"] = econ["mean_EENS_kWh"].diff()
    return response, econ


def metric_mean(frame: pd.DataFrame, eta: float, metric: str) -> float:
    rows = frame.loc[np.isclose(frame["eta"], eta)]
    if rows.empty:
        raise RuntimeError(f"Missing eta {eta} for {metric}")
    return float(rows[metric].mean())


def build_marginal(response: pd.DataFrame, c2: pd.DataFrame, c3: pd.DataFrame,
                   pressure: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for i in range(1, len(ETA)):
        prev, curr = ETA[i - 1], ETA[i]
        a, b = response.iloc[i - 1], response.iloc[i]
        inventory = float(b.TerminalLOH_total_kg - a.TerminalLOH_total_kg)
        production = float(b.production_cost_yuan - a.production_cost_yuan)
        nominal_gain = float(a.nominal_mean_EENS_kWh - b.nominal_mean_EENS_kWh)
        c2_gain = metric_mean(c2, prev, "mean_EENS_kWh") - metric_mean(c2, curr, "mean_EENS_kWh")
        medium = c3.loc[c3.distribution_label == "combined-medium"]
        strong = c3.loc[c3.distribution_label == "combined-strong"]
        medium_gain = metric_mean(medium, prev, "mean_EENS_kWh") - metric_mean(medium, curr, "mean_EENS_kWh")
        strong_gain = metric_mean(strong, prev, "mean_EENS_kWh") - metric_mean(strong, curr, "mean_EENS_kWh")
        pressure_gain = metric_mean(pressure, prev, "mean_EENS_kWh") - metric_mean(pressure, curr, "mean_EENS_kWh")
        q95_gain = metric_mean(pressure, prev, "shortage_q95_kg") - metric_mean(pressure, curr, "shortage_q95_kg")
        q995_gain = metric_mean(pressure, prev, "shortage_q995_kg") - metric_mean(pressure, curr, "shortage_q995_kg")
        max_gain = metric_mean(pressure, prev, "maximum_shortage_kg") - metric_mean(pressure, curr, "maximum_shortage_kg")
        unserved_drop = nominal_gain * 70.0
        rows.append({
            "segment": f"{prev:g}_to_{curr:g}", "eta_from": prev, "eta_to": curr,
            "eta_increment": curr - prev, "inventory_increment_kg": inventory,
            "production_cost_increment_yuan": production,
            "nominal_mean_EENS_improvement_kWh": nominal_gain,
            "C2_mean_EENS_improvement_kWh": c2_gain,
            "combined_medium_mean_EENS_improvement_kWh": medium_gain,
            "combined_strong_mean_EENS_improvement_kWh": strong_gain,
            "pressure_mean_EENS_improvement_kWh": pressure_gain,
            "pressure_q95_shortage_improvement_kg": q95_gain,
            "pressure_q995_shortage_improvement_kg": q995_gain,
            "maximum_shortage_improvement_kg": max_gain,
            "EENS_improvement_per_added_kg": nominal_gain / inventory if abs(inventory) > TOL else np.nan,
            "unserved_cost_drop_per_production_yuan": unserved_drop / production if abs(production) > TOL else np.nan,
        })
    return pd.DataFrame(rows)


def build_categories(work: Path) -> pd.DataFrame:
    payloads = []
    for i in range(1, 7):
        data = loadmat(work / "optimization_cases" / f"case-{i:03d}" / "case_payload.mat", squeeze_me=True)
        payloads.append(data)
    saa_shortage = np.asarray(payloads[0]["recordShortage"], dtype=float).reshape(-1)
    max_eta_shortage = np.asarray(payloads[-1]["recordShortage"], dtype=float).reshape(-1)
    unreachable = np.asarray(payloads[0]["recordUnreachableDemand"], dtype=float).reshape(-1)
    all_unreachable = np.asarray(payloads[0]["recordAllUnreachable"], dtype=bool).reshape(-1)
    positive = saa_shortage > 1e-9
    category = np.full(saa_shortage.size, "A_NO_SAA_SHORTAGE", dtype=object)
    invariant_road_floor = positive & (unreachable > 1e-9) & (np.abs(max_eta_shortage - saa_shortage) <= 1e-8)
    mask_d = positive & (all_unreachable | invariant_road_floor)
    mask_c = positive & ~mask_d & (unreachable > 1e-9)
    mask_b = positive & ~mask_d & ~mask_c
    category[mask_b] = "B_INVENTORY_RESPONSIVE_REACHABLE_SHORTAGE"
    category[mask_c] = "C_PARTIAL_ROAD_LIMITED_SHORTAGE"
    category[mask_d] = "D_UNREACHABLE_OR_INVENTORY_INVARIANT"
    rows = []
    for i, data in enumerate(payloads):
        shortage = np.asarray(data["recordShortage"], dtype=float).reshape(-1)
        used = np.asarray(data["recordInventoryUsed"], dtype=float).reshape(-1)
        eta = float(np.asarray(data["eta"]).squeeze())
        for label in [
            "A_NO_SAA_SHORTAGE", "B_INVENTORY_RESPONSIVE_REACHABLE_SHORTAGE",
            "C_PARTIAL_ROAD_LIMITED_SHORTAGE", "D_UNREACHABLE_OR_INVENTORY_INVARIANT",
        ]:
            mask = category == label
            rows.append({
                "case_id": i + 1, "eta": eta, "scenario_category": label,
                "scenario_count": int(mask.sum()), "scenario_share": float(mask.mean()),
                "mean_shortage_kg": float(shortage[mask].mean()) if mask.any() else np.nan,
                "mean_inventory_used_kg": float(used[mask].mean()) if mask.any() else np.nan,
                "mean_unreachable_demand_kg": float(unreachable[mask].mean()) if mask.any() else np.nan,
                "mean_shortage_improvement_vs_SAA_kg": float((saa_shortage[mask] - shortage[mask]).mean()) if mask.any() else np.nan,
                "contains_global_max_shortage_scenario": bool(np.any(mask & np.isclose(shortage, shortage.max(), atol=1e-9))),
            })
    return pd.DataFrame(rows)


def reproduction_audit(repo: Path, opt: pd.DataFrame, cert: pd.DataFrame) -> pd.DataFrame:
    c5b = pd.read_csv(repo / "results/task-002-stage2b-b3-smoke/51-unified-economic-terminal-loh/run-003/terminal_loh_decision_comparison.csv")
    c5b_cert = pd.read_csv(repo / "results/task-002-stage2b-b3-smoke/51-unified-economic-terminal-loh/run-003/solver_certificate.csv")
    rows = []
    for eta in [0.0, 0.003, 0.01]:
        new = opt.loc[np.isclose(opt.eta, eta)].iloc[0]
        old = c5b.loc[np.isclose(c5b.eta, eta)].iloc[0]
        nc = cert.loc[np.isclose(cert.eta, eta)].iloc[0]
        oc = c5b_cert.loc[np.isclose(c5b_cert.eta, eta)].iloc[0]
        tdiff = max(abs(float(new[f"T{i}_kg"]) - float(old[f"T{i}_kg"])) for i in range(1, 5))
        rows.append({
            "eta": eta, "maximum_T_abs_difference_kg": tdiff,
            "total_inventory_abs_difference_kg": abs(new.TerminalLOH_total_kg - old.TerminalLOH_total_kg),
            "nominal_EENS_abs_difference_kWh": abs(new.nominal_mean_EENS_kWh - old.nominal_mean_EENS_kWh),
            "nominal_economic_total_abs_difference_yuan": abs(new.nominal_mean_economic_total_yuan - old.nominal_mean_economic_total_yuan),
            "LB_abs_difference_yuan": abs(nc.LB_yuan - oc.LB_yuan),
            "UB_abs_difference_yuan": abs(nc.UB_yuan - oc.UB_yuan),
            "reproduction_pass": bool(tdiff <= 1e-6 and
                abs(new.nominal_mean_EENS_kWh - old.nominal_mean_EENS_kWh) <= 1e-6 and
                abs(new.nominal_mean_economic_total_yuan - old.nominal_mean_economic_total_yuan) <= 1e-5 and
                abs(nc.LB_yuan - oc.LB_yuan) <= 1e-4 and abs(nc.UB_yuan - oc.UB_yuan) <= 1e-4),
        })
    return pd.DataFrame(rows)


def plots(work: Path, response: pd.DataFrame, nominal: pd.DataFrame, validation: pd.DataFrame,
          prob: pd.DataFrame, marginal: pd.DataFrame) -> None:
    plt.style.use("default")
    x = np.arange(len(response)); labels = [f"{v:g}" for v in response.eta]

    def finish(name: str, ylabel: str) -> None:
        plt.xticks(x, labels); plt.xlabel("Pearson chi-square eta"); plt.ylabel(ylabel)
        plt.grid(True, alpha=.25); plt.tight_layout(); plt.savefig(work / name, dpi=180); plt.close()

    plt.figure(figsize=(7, 4)); plt.plot(x, response.TerminalLOH_total_kg, marker="o"); finish("eta_vs_terminal_loh.png", "TerminalLOH total (kg)")
    plt.figure(figsize=(8, 4.5))
    for col in ["T1_kg", "T2_kg", "T3_kg", "T4_kg"]: plt.plot(x, response[col], marker="o", label=col[:2])
    plt.legend(); finish("eta_vs_station_terminal_loh.png", "Station TerminalLOH (kg)")
    plt.figure(figsize=(7, 4)); plt.plot(x, nominal.mean_EENS_kWh, marker="o"); finish("eta_vs_nominal_eens.png", "Nominal mean EENS (kWh)")
    plt.figure(figsize=(7, 4)); plt.plot(x, nominal.mean_economic_total_yuan, marker="o"); finish("eta_vs_economic_cost.png", "Nominal economic total (yuan)")
    plt.figure(figsize=(8, 4.5))
    for col, label in [("shortage_q95_kg", "q95"), ("shortage_q99_kg", "q99"), ("shortage_q995_kg", "q99.5")]: plt.plot(x, nominal[col], marker="o", label=label)
    plt.legend(); finish("eta_vs_tail_shortage.png", "Nominal shortage (kg)")
    strong = validation.loc[validation.distribution_label == "combined-strong"].groupby("eta", as_index=False).mean(numeric_only=True).sort_values("eta")
    plt.figure(figsize=(7, 4)); plt.plot(x, strong.mean_EENS_kWh, marker="o"); finish("eta_vs_combined_strong_eens.png", "Combined-strong mean EENS (kWh)")
    pressure = validation.loc[validation.dataset_scope == "fixed-pressure"].sort_values("eta")
    plt.figure(figsize=(8, 4.5)); plt.plot(x, pressure.shortage_q95_kg, marker="o", label="q95"); plt.plot(x, pressure.maximum_shortage_kg, marker="o", label="maximum"); plt.legend(); finish("eta_vs_pressure_q95_and_max.png", "Pressure shortage (kg)")
    plt.figure(figsize=(7, 4)); plt.plot(x, prob.ESS, marker="o"); finish("eta_vs_effective_sample_size.png", "Worst-probability ESS")
    plt.figure(figsize=(8, 4.5)); mx=np.arange(len(marginal)); plt.bar(mx, marginal.nominal_mean_EENS_improvement_kWh); plt.xticks(mx, marginal.segment, rotation=25, ha="right"); plt.ylabel("Adjacent nominal EENS improvement (kWh)"); plt.grid(True, axis="y", alpha=.25); plt.tight_layout(); plt.savefig(work / "eta_marginal_resilience_gain.png", dpi=180); plt.close()


def write_judgment(work: Path, marginal: pd.DataFrame, response: pd.DataFrame,
                   pressure: pd.DataFrame, categories: pd.DataFrame) -> str:
    prior = marginal.loc[np.isclose(marginal.eta_from, .003) & np.isclose(marginal.eta_to, .01)].iloc[0]
    last = marginal.loc[np.isclose(marginal.eta_from, .01) & np.isclose(marginal.eta_to, .03)].iloc[0]
    compare_cols = ["nominal_mean_EENS_improvement_kWh", "C2_mean_EENS_improvement_kWh",
                    "combined_medium_mean_EENS_improvement_kWh", "combined_strong_mean_EENS_improvement_kWh",
                    "pressure_mean_EENS_improvement_kWh", "pressure_q95_shortage_improvement_kg",
                    "pressure_q995_shortage_improvement_kg"]
    last_not_larger = all(float(last[c]) <= float(prior[c]) + 1e-9 for c in compare_cols)
    max_flat = abs(float(last.maximum_shortage_improvement_kg)) <= 1e-9
    if last_not_larger and max_flat:
        code = "A"
        conclusion = "eta=0.003 and eta=0.01 cover the main effective interval; eta=0.03 has lower adjacent marginal benefit and is not recommended for the 35-state set."
    else:
        code = "B"
        conclusion = "eta=0.03 retains a larger adjacent gain in at least one strong-shift or tail dimension and may be carried as an additional high-guarantee candidate; eta remains unfrozen."
    d = categories.loc[(categories.eta == 0) & (categories.scenario_category == "D_UNREACHABLE_OR_INVENTORY_INVARIANT")].iloc[0]
    lines = [
        "Step-04C-C5C eta response and saturation judgment", "", f"Judgment: {code}", conclusion, "",
        f"0.003->0.01 inventory increment: {prior.inventory_increment_kg:.12g} kg",
        f"0.01->0.03 inventory increment: {last.inventory_increment_kg:.12g} kg",
        f"0.003->0.01 nominal EENS improvement: {prior.nominal_mean_EENS_improvement_kWh:.12g} kWh",
        f"0.01->0.03 nominal EENS improvement: {last.nominal_mean_EENS_improvement_kWh:.12g} kWh",
        f"0.01->0.03 combined-strong EENS improvement: {last.combined_strong_mean_EENS_improvement_kWh:.12g} kWh",
        f"0.01->0.03 pressure q95 shortage improvement: {last.pressure_q95_shortage_improvement_kg:.12g} kg",
        f"0.01->0.03 pressure q99.5 shortage improvement: {last.pressure_q995_shortage_improvement_kg:.12g} kg",
        f"0.01->0.03 maximum-shortage improvement: {last.maximum_shortage_improvement_kg:.12g} kg",
        f"SAA category-D share: {d.scenario_share:.12g}", "",
        "The comparison uses adjacent measured changes, not a fixed saturation threshold.",
        "Maximum-shortage invariance and category D are treated as a physical reachability ceiling, not evidence that eta is too small.",
        "Eta is not formally frozen, and inventory cannot replace road restoration or network hardening.",
    ]
    (work / "eta_saturation_judgment.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    return code


def large_manifest(work: Path) -> None:
    mats = sorted(work.glob("optimization_cases/case-*/case_payload.mat"))
    lines = ["# Large file manifest", "", "The following per-scenario diagnostic payloads remain local and are excluded from Git:", ""]
    for path in mats:
        lines.append(f"- `{path}` — {path.stat().st_size} bytes — SHA-256 `{sha256(path)}`")
    lines += ["", "Process logs, MATLAB diaries, optimization case directories, and validation case directories also remain local and are excluded from Git.", "No historical MAT, prepared input, accepted run, failed run, MSP file, or formal solver was modified."]
    (work / "LARGE_FILE_MANIFEST.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--work-dir", required=True)
    args = parser.parse_args()
    work = Path(args.work_dir).resolve(); repo = Path(__file__).resolve().parents[2]
    if git(repo, "branch", "--show-current") != EXPECTED_BRANCH or git(repo, "rev-parse", "HEAD") != EXPECTED_HEAD or git(repo, "rev-parse", "@{upstream}") != EXPECTED_HEAD:
        raise RuntimeError("C5C finalization Git gate failed.")

    opt = read_cases(work, 6, "optimization_cases", "optimization_result.csv").sort_values("case_id")
    cert = read_cases(work, 6, "optimization_cases", "solver_certificate.csv").sort_values("case_id")
    prob = read_cases(work, 6, "optimization_cases", "worst_probability_diagnostics.csv").sort_values("case_id")
    top = read_cases(work, 6, "optimization_cases", "top_loss_mass_shift.csv").sort_values(["case_id", "top_loss_fraction"])
    validation = add_validation_deltas(read_cases(work, 11, "validation_cases", "fixed_T_summary.csv"))
    audits = read_cases(work, 11, "validation_cases", "lexicographic_audit.csv")
    if len(opt) != 6 or len(validation) != 66 or not opt.case_pass.astype(bool).all() or not cert.certificate_pass.astype(bool).all() or not validation.validation_pass.astype(bool).all() or not audits.lexicographic_pass.astype(bool).all():
        raise RuntimeError("C5C optimization/validation completeness or certificate gate failed.")
    if cert.probability_sum_residual.abs().max() > 1e-10 or (cert.minimum_worst_probability < -1e-10).any() or (cert.divergence_used > cert.eta + 1e-8).any():
        raise RuntimeError("C5C probability certificate gate failed.")

    nominal = validation.loc[validation.dataset_scope == "state19-nominal"].copy()
    c2 = validation.loc[validation.dataset_scope == "independent-path"].copy()
    c3 = validation.loc[validation.dataset_scope == "markov-perturbation"].copy()
    pressure = validation.loc[validation.dataset_scope == "fixed-pressure"].copy()
    response, econ = build_response(opt, nominal)
    marginal = build_marginal(response, c2, c3, pressure)
    categories = build_categories(work)
    reproduction = reproduction_audit(repo, opt, cert)
    if not reproduction.reproduction_pass.all():
        raise RuntimeError("C5B eta=0/0.003/0.01 reproduction gate failed.")
    if np.max(np.abs(validation.mean_EENS_kWh - validation.mean_shortage_kg * ELECTRICITY_PER_KG)) > 1e-8:
        raise RuntimeError("EENS conversion identity failed.")

    write_csv(work, opt, "eta_optimization_results.csv")
    write_csv(work, response, "eta_terminal_loh_response.csv")
    write_csv(work, econ, "eta_nominal_economic_response.csv")
    write_csv(work, validation, "eta_tail_resilience_response.csv")
    write_csv(work, c2, "eta_c2_validation.csv")
    write_csv(work, c3, "eta_c3_combined_validation.csv")
    write_csv(work, pressure, "eta_fixed_pressure_response.csv")
    write_csv(work, prob, "eta_worst_probability_diagnostics.csv")
    write_csv(work, top, "eta_top_loss_mass_shift.csv")
    write_csv(work, prob[["case_id", "decision_label", "eta", "ESS", "total_variation_distance", "maximum_probability_to_nominal_ratio"]], "eta_effective_sample_size.csv")
    write_csv(work, marginal, "eta_marginal_benefit.csv")
    write_csv(work, categories, "eta_scenario_category_analysis.csv")
    write_csv(work, reproduction, "c5b_reproduction_audit.csv")
    write_csv(work, cert, "solver_certificate.csv")
    judgment = write_judgment(work, marginal, response, pressure, categories)
    plots(work, response, nominal.sort_values("eta"), validation, prob, marginal)
    large_manifest(work)

    readme = [
        "# Step-04C-C5C eta response and resilience saturation audit", "",
        "Status: **ACCEPTED**", f"Run: `{work.name}`", f"Judgment: **{judgment}**", "",
        "Six independent state19 nominal optimizations used the frozen grid `[0, 0.0003, 0.001, 0.003, 0.01, 0.03]` and the C5B yuan-consistent objective.",
        "C5B eta 0, 0.003, and 0.01 decisions, nominal EENS, economic totals, and LB/UB certificates reproduced within the frozen tolerances.",
        "Validation covers state19 nominal, three separate C2 independent-path datasets, three C3 combined-medium seeds, three C3 combined-strong seeds, and the descriptive 27-path/135-replica pressure set.",
        "The pressure set has no empirical probability and was not used for optimization.", "",
        "Actual Pearson probability movement, total variation, ESS, top-loss probability masses, serviceable-shortage mass, and all-unreachable mass are reported from the optimized adversarial probabilities.",
        "Scenario categories are frozen from SAA shortage and structural reachability: A no SAA shortage; B reachable inventory-responsive shortage; C partial road-limited shortage; D fully unreachable or road-floor shortage invariant through eta 0.03.", "",
        "No MSP, 35-state solve, Wasserstein model, CVaR objective, station-to-station transport model, or validation reoptimization was executed. `C*y` remains a strict secondary tie-break only. Eta remains unfrozen.",
    ]
    (work / "README.md").write_text("\n".join(readme) + "\n", encoding="utf-8")
    print(f"STEP04CC5C_FINALIZE_COMPLETE|judgment={judgment}|rows={len(validation)}")


if __name__ == "__main__":
    main()
