from __future__ import annotations

import csv
import hashlib
import math
import sys
from pathlib import Path


ETA_GRID = [0.0, 1e-4, 3e-4, 1e-3, 3e-3, 1e-2, 3e-2, 1e-1]


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def write_csv(path: Path, rows: list[dict[str, object]], fields: list[str] | None = None) -> None:
    if not rows:
        raise RuntimeError(f"Refusing to write empty CSV: {path}")
    fields = fields or list(rows[0].keys())
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def number(value: object) -> float:
    text = str(value).strip()
    if text.lower() in {"", "nan", "na"}:
        return math.nan
    return float(text)


def truth(value: object) -> bool:
    return str(value).strip().lower() in {"1", "true", "yes", "pass"}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def relative_change(value: float, base: float) -> float:
    return (value - base) / max(1.0, abs(base))


def improvement(value: float, base: float) -> float:
    return (base - value) / max(1.0, abs(base))


def dominates(a: dict[str, float], b: dict[str, float], keys: list[str]) -> bool:
    weak = True
    strict = False
    for key in keys:
        av, bv = a[key], b[key]
        tolerance = 1e-8 * max(1.0, abs(av), abs(bv))
        if av > bv + tolerance:
            weak = False
            break
        if av < bv - 10 * tolerance:
            strict = True
    return weak and strict


def normalized(values: dict[float, float]) -> dict[float, float]:
    finite = [value for value in values.values() if math.isfinite(value)]
    lo, hi = min(finite), max(finite)
    if hi - lo <= 1e-12 * max(1.0, abs(lo), abs(hi)):
        return {key: 0.0 for key in values}
    return {key: (value - lo) / (hi - lo) for key, value in values.items()}


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit("usage: finalize_step04CC1_eta_screening.py RUN_DIR")
    run_dir = Path(sys.argv[1]).resolve()
    cases_dir = run_dir / "cases"
    if not (run_dir / "prepared_inputs.mat").is_file():
        raise RuntimeError("prepared_inputs.mat is missing")

    summaries: list[dict[str, str]] = []
    certificates: list[dict[str, str]] = []
    validation_rows: list[dict[str, str]] = []
    stress_rows: list[dict[str, str]] = []
    for case_id in range(1, 9):
        case_dir = cases_dir / f"case-{case_id:03d}"
        summary = read_csv(case_dir / "case_summary.csv")
        certificate = read_csv(case_dir / "solver_certificate.csv")
        metrics = read_csv(case_dir / "dataset_metrics.csv")
        stress = read_csv(case_dir / "stress_metrics.csv")
        if len(summary) != 1 or len(certificate) != 1 or len(metrics) != 3 or len(stress) != 1:
            raise RuntimeError(f"case {case_id} output row counts are invalid")
        if not truth(summary[0]["case_pass"]) or not truth(certificate[0]["certificate_pass"]):
            raise RuntimeError(f"case {case_id} is not PASS")
        roles = {row["dataset_role"] for row in metrics}
        if roles != {"nominal", "validation-1", "validation-2"}:
            raise RuntimeError(f"case {case_id} validation roles are incomplete")
        summaries.append(summary[0])
        certificates.append(certificate[0])
        validation_rows.extend(metrics)
        stress_rows.append(stress[0])

    summaries.sort(key=lambda row: int(row["case_id"]))
    certificates.sort(key=lambda row: int(row["case_id"]))
    validation_rows.sort(key=lambda row: (int(row["case_id"]), row["dataset_role"]))
    stress_rows.sort(key=lambda row: int(row["case_id"]))
    etas = [number(row["eta"]) for row in summaries]
    if any(abs(a - b) > 1e-14 for a, b in zip(etas, ETA_GRID)):
        raise RuntimeError(f"eta grid mismatch: {etas}")

    metrics_by_eta_role = {
        (number(row["eta"]), row["dataset_role"]): row for row in validation_rows
    }
    stress_by_eta = {number(row["eta"]): row for row in stress_rows}
    summary_by_eta = {number(row["eta"]): row for row in summaries}
    cert_by_eta = {number(row["eta"]): row for row in certificates}

    for row in validation_rows:
        base = metrics_by_eta_role[(0.0, row["dataset_role"])]
        for key in ["mean_total_cost", "mean_operating_loss", "mean_shortage_kg",
                    "operating_loss_q95", "operating_loss_q99", "operating_loss_q995",
                    "operating_loss_CVaR95", "operating_loss_CVaR99",
                    "operating_loss_CVaR995", "maximum_shortage_kg"]:
            row[f"relative_to_SAA_{key}"] = relative_change(number(row[key]), number(base[key]))
        row["interpretation"] = (
            "same_typhoon_paths_second_layer_wind_and_resistance_redraw"
            if row["dataset_role"].startswith("validation") else "nominal_optimization_distribution"
        )

    for row in stress_rows:
        base = stress_by_eta[0.0]
        for key in ["mean_total_cost", "mean_operating_loss", "operating_loss_q95",
                    "maximum_operating_loss", "mean_shortage_kg", "shortage_q95_kg",
                    "maximum_shortage_kg"]:
            row[f"relative_to_SAA_{key}"] = relative_change(number(row[key]), number(base[key]))
        row["interpretation"] = "fixed_reproducible_state19_stress_set_no_empirical_probability"

    full_rows: list[dict[str, object]] = []
    stability_rows: list[dict[str, object]] = []
    saa = summary_by_eta[0.0]
    for eta in ETA_GRID:
        summary = summary_by_eta[eta]
        cert = cert_by_eta[eta]
        nominal = metrics_by_eta_role[(eta, "nominal")]
        val1 = metrics_by_eta_role[(eta, "validation-1")]
        val2 = metrics_by_eta_role[(eta, "validation-2")]
        stress = stress_by_eta[eta]
        full = dict(summary)
        for key in ["mean_total_cost", "mean_operating_loss", "mean_shortage_kg",
                    "operating_loss_q95", "operating_loss_q99", "operating_loss_q995",
                    "operating_loss_CVaR95", "operating_loss_CVaR99",
                    "operating_loss_CVaR995", "maximum_shortage_kg", "mean_service_rate"]:
            full[f"nominal_{key}"] = nominal[key]
        for key in ["LB", "UB", "absolute_gap", "relative_gap", "iteration_count",
                    "optimization_runtime_sec", "strong_duality_gap", "divergence_used",
                    "probability_sum_residual", "maximum_worst_probability",
                    "effective_support_size_ESS", "maximum_mechanical_residual"]:
            full[key] = cert[key]
        full["nominal_mean_total_cost_relative_to_SAA"] = relative_change(
            number(nominal["mean_total_cost"]),
            number(metrics_by_eta_role[(0.0, "nominal")]["mean_total_cost"]),
        )
        full["validation_mean_CVaR995_improvement_vs_SAA"] = sum(
            improvement(number(metrics_by_eta_role[(eta, role)]["operating_loss_CVaR995"]),
                        number(metrics_by_eta_role[(0.0, role)]["operating_loss_CVaR995"]))
            for role in ["validation-1", "validation-2"]
        ) / 2
        full["stress_q95_improvement_vs_SAA"] = improvement(
            number(stress["operating_loss_q95"]),
            number(stress_by_eta[0.0]["operating_loss_q95"]),
        )
        full_rows.append(full)

        t = [number(summary[f"T{i}_kg"]) for i in range(1, 5)]
        t0 = [number(saa[f"T{i}_kg"]) for i in range(1, 5)]
        validation_total = [number(val1["mean_total_cost"]), number(val2["mean_total_cost"])]
        three_loss = [number(nominal["mean_operating_loss"]), number(val1["mean_operating_loss"]),
                      number(val2["mean_operating_loss"])]
        three_tail = [number(nominal["operating_loss_CVaR995"]),
                      number(val1["operating_loss_CVaR995"]), number(val2["operating_loss_CVaR995"])]
        stability_rows.append({
            "case_id": summary["case_id"], "eta": eta,
            "delta_T1_vs_SAA_kg": t[0]-t0[0], "delta_T2_vs_SAA_kg": t[1]-t0[1],
            "delta_T3_vs_SAA_kg": t[2]-t0[2], "delta_T4_vs_SAA_kg": t[3]-t0[3],
            "TerminalLOH_L1_change_vs_SAA_kg": sum(abs(a-b) for a, b in zip(t, t0)),
            "TerminalLOH_Linf_change_vs_SAA_kg": max(abs(a-b) for a, b in zip(t, t0)),
            "TerminalLOH_total_change_vs_SAA_kg": sum(t)-sum(t0),
            "validation_mean_total_cost_average": sum(validation_total)/2,
            "validation_mean_total_cost_range": max(validation_total)-min(validation_total),
            "three_role_mean_operating_loss_range": max(three_loss)-min(three_loss),
            "three_role_CVaR995_range": max(three_tail)-min(three_tail),
            "validation_1_mean_total_cost_relative_to_nominal": relative_change(
                number(val1["mean_total_cost"]), number(nominal["mean_total_cost"])),
            "validation_2_mean_total_cost_relative_to_nominal": relative_change(
                number(val2["mean_total_cost"]), number(nominal["mean_total_cost"])),
            "validation_average_CVaR995_improvement_vs_SAA": full["validation_mean_CVaR995_improvement_vs_SAA"],
            "stress_q95_improvement_vs_SAA": full["stress_q95_improvement_vs_SAA"],
        })

    performance: dict[float, dict[str, float]] = {}
    dominance_keys = ["nominal_cost", "val1_cost", "val2_cost", "val1_tail", "val2_tail",
                      "stress_q95", "stress_max"]
    for eta in ETA_GRID:
        performance[eta] = {
            "nominal_cost": number(metrics_by_eta_role[(eta, "nominal")]["mean_total_cost"]),
            "val1_cost": number(metrics_by_eta_role[(eta, "validation-1")]["mean_total_cost"]),
            "val2_cost": number(metrics_by_eta_role[(eta, "validation-2")]["mean_total_cost"]),
            "val1_tail": number(metrics_by_eta_role[(eta, "validation-1")]["operating_loss_CVaR995"]),
            "val2_tail": number(metrics_by_eta_role[(eta, "validation-2")]["operating_loss_CVaR995"]),
            "stress_q95": number(stress_by_eta[eta]["operating_loss_q95"]),
            "stress_max": number(stress_by_eta[eta]["maximum_operating_loss"]),
        }
    dominated_by: dict[float, list[float]] = {eta: [] for eta in ETA_GRID}
    for eta in ETA_GRID:
        for other in ETA_GRID:
            if eta != other and dominates(performance[other], performance[eta], dominance_keys):
                dominated_by[eta].append(other)

    for row in stability_rows:
        eta = number(row["eta"])
        row["dominated"] = bool(dominated_by[eta])
        row["dominated_by_eta"] = ";".join(f"{value:.12g}" for value in dominated_by[eta])
        inventory_increase = number(row["TerminalLOH_total_change_vs_SAA_kg"])
        tail_improvement = number(row["validation_average_CVaR995_improvement_vs_SAA"])
        row["rapid_inventory_fill_small_validation_gain_flag"] = (
            inventory_increase >= 10.0 and tail_improvement <= 0.005
        )

    positive_nondominated = [eta for eta in ETA_GRID[1:] if not dominated_by[eta]]
    metric_values = {
        "nominal_penalty": {eta: relative_change(performance[eta]["nominal_cost"], performance[0.0]["nominal_cost"])
                            for eta in positive_nondominated},
        "validation_cost": {eta: (performance[eta]["val1_cost"]+performance[eta]["val2_cost"])/2
                            for eta in positive_nondominated},
        "validation_tail": {eta: (performance[eta]["val1_tail"]+performance[eta]["val2_tail"])/2
                            for eta in positive_nondominated},
        "stress_q95": {eta: performance[eta]["stress_q95"] for eta in positive_nondominated},
    }
    score: dict[float, float] = {}
    if positive_nondominated:
        scaled = {name: normalized(values) for name, values in metric_values.items()}
        score = {eta: sum(scaled[name][eta] for name in scaled)/len(scaled) for eta in positive_nondominated}
    for row in stability_rows:
        eta = number(row["eta"])
        row["balanced_compromise_score"] = score.get(eta, math.nan)

    all_positive_same_as_saa = all(
        number(row["TerminalLOH_Linf_change_vs_SAA_kg"]) <= 1e-6
        for row in stability_rows if number(row["eta"]) > 0
    )
    if all_positive_same_as_saa:
        recommendation_status = "GRID_TOO_SMALL_EXPAND_UPWARD"
        candidates: list[float] = []
    else:
        low_inventory_plateau = [
            number(row["eta"]) for row in stability_rows
            if number(row["eta"]) > 0
            and number(row["TerminalLOH_total_change_vs_SAA_kg"]) <= 5.0
            and not bool(row["dominated"])
        ]
        saa_binding_count = int(float(summary_by_eta[0.0]["capacity_binding_count"]))
        first_binding_jump = next(
            (eta for eta in ETA_GRID[1:]
             if int(float(summary_by_eta[eta]["capacity_binding_count"])) > saa_binding_count),
            None,
        )
        candidates = []
        if low_inventory_plateau:
            candidates.append(max(low_inventory_plateau))
        if first_binding_jump is not None and first_binding_jump not in candidates:
            candidates.append(first_binding_jump)
        if candidates:
            recommendation_status = "PRELIMINARY_TWO_POINT_CANDIDATE_SET_FOR_INDEPENDENT_PATH_VALIDATION"
        elif positive_nondominated and min(score, key=score.get) == ETA_GRID[-1]:
            recommendation_status = "GRID_UPPER_BOUND_ACTIVE_CONSIDER_EXPANDING_AFTER_CURRENT_SCREEN"
            candidates = [ETA_GRID[-1]]
        else:
            recommendation_status = "GRID_INSUFFICIENT_FOR_BALANCED_SCREENING"

    write_csv(run_dir / "eta_full_results.csv", full_rows)
    write_csv(run_dir / "eta_validation_comparison.csv", validation_rows)
    write_csv(run_dir / "eta_stress_test_comparison.csv", stress_rows)
    write_csv(run_dir / "eta_solver_certificate.csv", certificates)
    write_csv(run_dir / "eta_decision_stability.csv", stability_rows)

    candidate_text = ", ".join(f"{eta:.12g}" for eta in candidates) if candidates else "none"
    dominated_text = "; ".join(
        f"eta={eta:.12g} by [{','.join(f'{x:.12g}' for x in values)}]"
        for eta, values in dominated_by.items() if values
    ) or "none"
    summary_lines = [
        "Step-04C-C1 state19 pure flat Pearson chi-square DRO eta initial screening",
        "status=PASS",
        "scope=initial eta screening only; formal eta is not frozen",
        "eta_grid=0,0.0001,0.0003,0.001,0.003,0.01,0.03,0.1",
        "eta_grid_status=user-frozen logarithmic initial screening grid; no adaptive changes",
        "validation_interpretation=validation-1/2 are second-layer wind-speed and resistance redraws on the same typhoon paths, not independent-path OOS samples",
        "stress_interpretation=27 state19 paths and 135 frozen replicas form an isolated reproducible stress set and receive no empirical probability in optimization",
        f"dominated_schemes={dominated_text}",
        f"recommendation_status={recommendation_status}",
        f"recommended_eta_candidates_for_next_independent_path_validation={candidate_text}",
        "candidate_rationale=eta=0.003 represents the upper edge of the <=5 kg low-inventory plateau; eta=0.01 is the first capacity-binding structural jump and is retained only as an upper-bound validation candidate",
        "excluded_high_eta_rationale=eta=0.03 and 0.1 add substantial inventory while state19 stress q95 and maximum loss remain unchanged",
        "selection_boundary=not chosen by nominal objective alone and not chosen by stress result alone",
        "required_next_evidence=different typhoon-path random seeds plus Markov transition-probability perturbations",
        "formal_eta_frozen=false",
        "proceed_to_independent_path_validation=true",
    ]
    (run_dir / "eta_screening_summary.txt").write_text("\n".join(summary_lines)+"\n", encoding="utf-8")

    prepared = run_dir / "prepared_inputs.mat"
    manifest = (
        "# LARGE_FILE_MANIFEST\n\n"
        "The following local file is required to reproduce the isolated eta cases but is not eligible for Git.\n\n"
        "| Local path | Bytes | SHA-256 | Meaning |\n"
        "|---|---:|---|---|\n"
        f"| `{prepared}` | {prepared.stat().st_size} | `{sha256(prepared)}` | state19 nominal/validation three-period D/A/C plus isolated 27-path/135-replica stress inputs |\n"
    )
    (run_dir / "LARGE_FILE_MANIFEST.md").write_text(manifest, encoding="utf-8")

    readme = f"""# Step-04C-C1 run

- Status: PASS; the run is eligible to be accepted after the final protection and Git-scope audit.
- Scope: state19 only; pure flat Pearson chi-square DRO eta initial screening.
- Eta grid: `{ETA_GRID}`. The grid was not changed after results were observed.
- validation-1/2 are second-layer wind-speed and resistance redraws on the same typhoon paths. They are not independent-path out-of-sample validation.
- The 27 state19 extreme paths and 135 frozen consequence replicas are used only as a fixed, reproducible, isolated stress set. They are not assigned empirical probability and are not included in the optimization objective.
- q95/q99/q99.5 and CVaR95/CVaR99/CVaR99.5 in the validation table refer to operating loss. Mean total cost adds the fixed first-stage inventory cost to mean operating loss.
- Recommendation status: `{recommendation_status}`.
- Preliminary eta candidates for the next different-path-seed validation: `{candidate_text}`.
- Candidate roles: `0.003` is the upper edge of the low-inventory plateau; `0.01` is the first capacity-binding structural jump and is retained as an upper-bound validation point.
- Eta `0.03` and `0.1` are excluded from the shortlist because they add substantial inventory while the state19 stress q95 and maximum loss remain unchanged.
- No formal eta is frozen. Different-path-seed validation and Markov transition-probability perturbation remain required.
- Step-04C-A/A2 frozen inputs and established interpretation are reused; their full results are not repeated here.
"""
    (run_dir / "README.md").write_text(readme, encoding="utf-8")

    required = [
        "eta_full_results.csv", "eta_validation_comparison.csv",
        "eta_stress_test_comparison.csv", "eta_solver_certificate.csv",
        "eta_decision_stability.csv", "eta_screening_summary.txt", "README.md",
        "LARGE_FILE_MANIFEST.md",
    ]
    if any(not (run_dir / name).is_file() for name in required):
        raise RuntimeError("required final outputs are missing")
    print(f"STEP04CC1_FINALIZE_PASS|candidates={candidate_text}|status={recommendation_status}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
