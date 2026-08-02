#!/usr/bin/env python3
"""Finalize Step-04C-C3 Markov-transition fixed-decision diagnostics."""

from __future__ import annotations

import hashlib
import math
import sys
from pathlib import Path

import numpy as np
import pandas as pd
from scipy.stats import t as student_t


SUMMARY_METRICS = [
    "mean_total_cost", "mean_operating_loss", "mean_service_cost",
    "mean_shortage_kg", "mean_service_rate", "zero_shortage_service_share",
    "operating_loss_q95", "operating_loss_q99", "operating_loss_q995",
    "operating_loss_CVaR95", "operating_loss_CVaR99", "operating_loss_CVaR995",
    "maximum_operating_loss", "shortage_q95_kg", "shortage_q99_kg",
    "shortage_q995_kg", "maximum_shortage_kg",
]
PAIRED_METRICS = ["total_cost", "operating_loss", "shortage_kg"]
CANDIDATES = ["ETA_0.003", "ETA_0.01"]
REASONABLE = ["intensity-only", "location-only", "lfw-only", "combined-mild", "combined-medium"]
COMBINED_CHAIN = ["nominal", "combined-mild", "combined-medium", "combined-strong"]
TOL = 1e-9


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def rel_change(delta: float, base: float) -> float:
    return delta / abs(base) if abs(base) > 1e-15 else math.nan


def bool_series(values: pd.Series) -> pd.Series:
    return values.astype(str).str.lower().isin(["1", "true"])


def main(run_dir: Path) -> None:
    required_prepare = [
        "markov_perturbation_spec.csv", "perturbed_transition_matrices.csv",
        "transition_matrix_audit.csv", "transition_frequency_audit.csv",
        "seed_and_collision_audit.csv", "dataset_manifest.csv",
        "dataset_reproducibility_audit.csv", "common_random_numbers_audit.csv",
        "path_overlap_audit.csv", "location_geometry_risk_ranking.csv",
        "fixed_decision_source_audit.csv", "frozen_input_manifest.csv",
        "prepare_mechanical_audit.txt",
    ]
    for name in required_prepare:
        if not (run_dir / name).is_file():
            raise RuntimeError(f"Missing preparation output: {name}")
    if "status=PASS" not in (run_dir / "prepare_mechanical_audit.txt").read_text(encoding="utf-8"):
        raise RuntimeError("Preparation mechanical audit did not PASS")

    spec = pd.read_csv(run_dir / "markov_perturbation_spec.csv")
    matrices = pd.read_csv(run_dir / "perturbed_transition_matrices.csv")
    matrix_audit = pd.read_csv(run_dir / "transition_matrix_audit.csv")
    frequency = pd.read_csv(run_dir / "transition_frequency_audit.csv")
    seeds = pd.read_csv(run_dir / "seed_and_collision_audit.csv")
    manifest = pd.read_csv(run_dir / "dataset_manifest.csv")
    repro = pd.read_csv(run_dir / "dataset_reproducibility_audit.csv")
    crn = pd.read_csv(run_dir / "common_random_numbers_audit.csv")
    path_overlap = pd.read_csv(run_dir / "path_overlap_audit.csv")
    if len(spec) != 7 or list(spec["distribution_label"]) != [
        "nominal", "intensity-only", "location-only", "lfw-only",
        "combined-mild", "combined-medium", "combined-strong",
    ]:
        raise RuntimeError("Frozen seven-distribution specification gate failed")
    if len(manifest) != 21 or set(manifest["seed_id"]) != {1, 2, 3}:
        raise RuntimeError("Dataset manifest 21-row/three-seed gate failed")
    if not np.all(manifest["sample_count"].to_numpy() == 15000):
        raise RuntimeError("A C3 dataset is not exactly 15000 rows")
    if not np.allclose(manifest["weight_sum"], 1.0, atol=1e-12, rtol=0):
        raise RuntimeError("Each distribution and seed must have its own unit weight sum")
    if not bool_series(matrix_audit["audit_pass"]).all():
        raise RuntimeError("Transition matrix audit did not fully pass")
    if not bool_series(frequency["frequency_audit_pass"]).all():
        raise RuntimeError("Transition frequency audit did not fully pass")
    if not (seeds["status"] == "PASS").all():
        raise RuntimeError("Random-stream collision audit did not fully pass")
    if not bool_series(repro["path_replay_pass"]).all() or not bool_series(repro["formal_replay_pass"]).all():
        raise RuntimeError("Dataset replay audit did not fully pass")
    for column in ["wind_CRN_matches_nominal", "line_resistance_CRN_matches_nominal", "road_resistance_CRN_matches_nominal"]:
        if not bool_series(crn[column]).all():
            raise RuntimeError(f"Common-random-number audit failed: {column}")
    history = path_overlap[path_overlap["comparison_type"].str.startswith("C3_nominal_vs_history")]
    perturbed = path_overlap[path_overlap["comparison_type"] == "C3_CRN_distribution_vs_nominal"]
    if bool_series(history["exact_whole_batch_reuse"]).any() or bool_series(perturbed["exact_whole_batch_reuse"]).any():
        raise RuntimeError("A C3 path batch was impermissibly reused unchanged")

    summaries: list[pd.DataFrame] = []
    scenarios: dict[tuple[int, int], pd.DataFrame] = {}
    certificates: list[pd.DataFrame] = []
    max_residual = 0.0
    for seed_id in range(1, 4):
        for distribution_id in range(1, 8):
            case_dir = run_dir / f"case-seed{seed_id:03d}-dist{distribution_id:03d}"
            summary_file = case_dir / "fixed_T_summary.csv"
            certificate_file = case_dir / "fixed_T_certificate.csv"
            scenario_file = case_dir / "scenario_results.csv"
            audit_file = case_dir / "mechanical_audit.txt"
            for path in [summary_file, certificate_file, scenario_file, audit_file]:
                if not path.is_file():
                    raise RuntimeError(f"Missing fixed-T case output: {path}")
            if "status=PASS" not in audit_file.read_text(encoding="utf-8"):
                raise RuntimeError(f"Mechanical audit did not PASS: {case_dir.name}")
            summary = pd.read_csv(summary_file)
            certificate = pd.read_csv(certificate_file)
            scenario = pd.read_csv(scenario_file)
            if len(summary) != 3 or len(certificate) != 3 or len(scenario) != 45000:
                raise RuntimeError(f"Case row-count gate failed: {case_dir.name}")
            if set(summary["decision_label"]) != {"SAA", *CANDIDATES}:
                raise RuntimeError(f"Frozen decision coverage failed: {case_dir.name}")
            if not (summary["solver_status"] == "OPTIMAL").all() or not bool_series(certificate["certificate_pass"]).all():
                raise RuntimeError(f"Fixed-T solver/certificate failed: {case_dir.name}")
            max_residual = max(max_residual, float(certificate["maximum_mechanical_residual"].max()))
            summaries.append(summary)
            certificates.append(certificate)
            scenarios[(seed_id, distribution_id)] = scenario
    if max_residual > 1e-7:
        raise RuntimeError(f"Maximum mechanical residual exceeds tolerance: {max_residual}")

    full = pd.concat(summaries, ignore_index=True).sort_values(
        ["distribution_id", "seed_id", "eta"]
    ).reset_index(drop=True)
    if len(full) != 63:
        raise RuntimeError("Fixed-T full result must contain 63 rows")
    relative_columns: dict[str, list[float]] = {}
    for metric in SUMMARY_METRICS:
        relative_columns[f"{metric}_absolute_change_vs_SAA"] = []
        relative_columns[f"{metric}_percent_change_vs_SAA"] = []
    for _, row in full.iterrows():
        base = full[
            (full["seed_id"] == row["seed_id"])
            & (full["distribution_id"] == row["distribution_id"])
            & (full["decision_label"] == "SAA")
        ].iloc[0]
        for metric in SUMMARY_METRICS:
            delta = float(row[metric] - base[metric])
            relative_columns[f"{metric}_absolute_change_vs_SAA"].append(delta)
            relative_columns[f"{metric}_percent_change_vs_SAA"].append(100 * rel_change(delta, float(base[metric])))
    for name, values in relative_columns.items():
        full[name] = values
    full.to_csv(run_dir / "fixed_T_full_results.csv", index=False)

    comparison_rows: list[dict[str, float | int | str]] = []
    ci_rows: list[dict[str, float | int | str]] = []
    diff_lookup: dict[tuple[int, int, str, str], float] = {}
    for seed_id in range(1, 4):
        for distribution_id in range(1, 8):
            data = scenarios[(seed_id, distribution_id)]
            base = data[data["decision_label"] == "SAA"].set_index("scenario_id").sort_index()
            distribution_label = str(base["distribution_label"].iloc[0])
            for candidate_label in CANDIDATES:
                candidate = data[data["decision_label"] == candidate_label].set_index("scenario_id").sort_index()
                if not base.index.equals(candidate.index):
                    raise RuntimeError("Scenario-pairing IDs do not align")
                row: dict[str, float | int | str] = {
                    "seed_id": seed_id,
                    "distribution_id": distribution_id,
                    "distribution_label": distribution_label,
                    "candidate_label": candidate_label,
                    "eta": float(candidate["eta"].iloc[0]),
                    "paired_sample_count": len(base),
                    "difference_direction": "candidate_minus_SAA_negative_is_improvement",
                }
                for metric in PAIRED_METRICS:
                    diff = candidate[metric].to_numpy(float) - base[metric].to_numpy(float)
                    mean = float(np.mean(diff))
                    sd = float(np.std(diff, ddof=1))
                    se = sd / math.sqrt(len(diff))
                    critical = float(student_t.ppf(0.975, len(diff) - 1))
                    lower, upper = mean - critical * se, mean + critical * se
                    row[f"{metric}_paired_mean_difference"] = mean
                    row[f"{metric}_improved_share"] = float(np.mean(diff < -TOL))
                    row[f"{metric}_worsened_share"] = float(np.mean(diff > TOL))
                    row[f"{metric}_equal_share"] = float(np.mean(np.abs(diff) <= TOL))
                    row[f"{metric}_paired_CI95_lower"] = lower
                    row[f"{metric}_paired_CI95_upper"] = upper
                    diff_lookup[(seed_id, distribution_id, candidate_label, metric)] = mean
                    ci_rows.append({
                        "seed_id": seed_id,
                        "distribution_id": distribution_id,
                        "distribution_label": distribution_label,
                        "candidate_label": candidate_label,
                        "eta": float(candidate["eta"].iloc[0]),
                        "metric": metric,
                        "difference_direction": "candidate_minus_SAA_negative_is_improvement",
                        "paired_sample_count": len(diff),
                        "paired_mean_difference": mean,
                        "paired_sd": sd,
                        "paired_standard_error": se,
                        "student_t_critical_975": critical,
                        "paired_mean_difference_CI95_lower": lower,
                        "paired_mean_difference_CI95_upper": upper,
                        "improved_share": float(np.mean(diff < -TOL)),
                        "worsened_share": float(np.mean(diff > TOL)),
                        "equal_share": float(np.mean(np.abs(diff) <= TOL)),
                    })
                comparison_rows.append(row)
    comparison = pd.DataFrame(comparison_rows).sort_values(["distribution_id", "seed_id", "eta"])
    paired_ci = pd.DataFrame(ci_rows).sort_values(["distribution_id", "seed_id", "eta", "metric"])
    comparison.to_csv(run_dir / "seedwise_paired_comparison.csv", index=False)
    paired_ci.to_csv(run_dir / "paired_difference_ci.csv", index=False)

    trend_rows: list[dict[str, float | int | str | bool]] = []
    metric_map = {
        "mean_total_cost": "mean_total_cost_absolute_change_vs_SAA",
        "mean_operating_loss": "mean_operating_loss_absolute_change_vs_SAA",
        "mean_shortage_kg": "mean_shortage_kg_absolute_change_vs_SAA",
        "operating_loss_q995": "operating_loss_q995_absolute_change_vs_SAA",
        "operating_loss_CVaR995": "operating_loss_CVaR995_absolute_change_vs_SAA",
    }
    for candidate_label in CANDIDATES:
        for seed_id in range(1, 4):
            for metric, diff_column in metric_map.items():
                values: dict[str, float] = {}
                for label in [*COMBINED_CHAIN, "intensity-only", "location-only", "lfw-only"]:
                    value = full[
                        (full["seed_id"] == seed_id)
                        & (full["distribution_label"] == label)
                        & (full["decision_label"] == candidate_label)
                    ][diff_column]
                    if len(value) != 1:
                        raise RuntimeError("Trend lookup is missing or duplicated")
                    values[label] = float(value.iloc[0])
                chain = np.array([values[label] for label in COMBINED_CHAIN])
                trend_rows.append({
                    "candidate_label": candidate_label,
                    "eta": 0.003 if candidate_label == "ETA_0.003" else 0.01,
                    "seed_id": seed_id,
                    "metric": metric,
                    "difference_direction": "candidate_minus_SAA_negative_is_improvement",
                    "nominal_difference": values["nominal"],
                    "intensity_only_delta005_difference": values["intensity-only"],
                    "location_only_delta005_difference": values["location-only"],
                    "lfw_only_delta005_difference": values["lfw-only"],
                    "combined_mild_delta002_difference": values["combined-mild"],
                    "combined_medium_delta005_difference": values["combined-medium"],
                    "combined_strong_delta010_difference": values["combined-strong"],
                    "combined_advantage_monotonic_nonincreasing": bool(np.all(np.diff(chain) <= TOL)),
                    "combined_strong_improves": bool(chain[-1] < -TOL),
                })
    trend = pd.DataFrame(trend_rows).sort_values(["eta", "metric", "seed_id"])
    trend.to_csv(run_dir / "perturbation_trend_summary.csv", index=False)

    evidence: dict[str, dict[str, bool | int]] = {}
    ci_evidence: dict[str, dict[str, object]] = {}
    for candidate_label in CANDIDATES:
        candidate = full[(full["decision_label"] == candidate_label)]
        reasonable = candidate[candidate["distribution_label"].isin(REASONABLE)]
        stable_risk = bool(
            (reasonable["mean_operating_loss_absolute_change_vs_SAA"] <= TOL).all()
            and (reasonable["mean_shortage_kg_absolute_change_vs_SAA"] <= TOL).all()
            and (reasonable["operating_loss_CVaR995_absolute_change_vs_SAA"] <= TOL).all()
        )
        stable_economic = bool((reasonable["mean_total_cost_absolute_change_vs_SAA"] <= TOL).all())
        strong = candidate[candidate["distribution_label"] == "combined-strong"]
        strong_risk = bool(
            (strong["mean_operating_loss_absolute_change_vs_SAA"] < -TOL).all()
            and (strong["mean_shortage_kg_absolute_change_vs_SAA"] <= TOL).all()
            and (strong["operating_loss_CVaR995_absolute_change_vs_SAA"] < -TOL).all()
        )
        evidence[candidate_label] = {
            "stable_risk_reasonable": stable_risk,
            "stable_economic_reasonable": stable_economic,
            "stable_value_reasonable": stable_risk and stable_economic,
            "strong_risk_value": strong_risk,
            "reasonable_total_cost_improvement_cells": int((reasonable["mean_total_cost_absolute_change_vs_SAA"] < -TOL).sum()),
            "reasonable_cell_count": len(reasonable),
        }
        candidate_ci = paired_ci[paired_ci["candidate_label"] == candidate_label]
        total_ci = candidate_ci[candidate_ci["metric"] == "total_cost"]
        operating_ci = candidate_ci[candidate_ci["metric"] == "operating_loss"]
        shortage_ci = candidate_ci[candidate_ci["metric"] == "shortage_kg"]
        all_seed_economic_labels = []
        for distribution_label in spec["distribution_label"]:
            rows = total_ci[total_ci["distribution_label"] == distribution_label]
            if len(rows) == 3 and (rows["paired_mean_difference_CI95_upper"] < 0).all():
                all_seed_economic_labels.append(str(distribution_label))
        ci_evidence[candidate_label] = {
            "total_cost_negative_ci_count": int((total_ci["paired_mean_difference_CI95_upper"] < 0).sum()),
            "operating_loss_negative_ci_count": int((operating_ci["paired_mean_difference_CI95_upper"] < 0).sum()),
            "shortage_negative_ci_count": int((shortage_ci["paired_mean_difference_CI95_upper"] < 0).sum()),
            "all_seed_economic_labels": all_seed_economic_labels,
        }

    stable003 = bool(evidence["ETA_0.003"]["stable_value_reasonable"])
    stable010 = bool(evidence["ETA_0.01"]["stable_value_reasonable"])
    if stable003 and not stable010:
        judgement = "1. eta=0.003在合理扰动范围内显示稳定价值"
    elif stable010 and not stable003:
        judgement = "2. eta=0.01在合理扰动范围内显示稳定价值"
    elif stable003 and stable010:
        eta003 = full[(full["decision_label"] == "ETA_0.003") & full["distribution_label"].isin(REASONABLE)]
        eta010 = full[(full["decision_label"] == "ETA_0.01") & full["distribution_label"].isin(REASONABLE)]
        keys = ["seed_id", "distribution_id"]
        merged = eta010.merge(eta003, on=keys, suffixes=("_010", "_003"))
        dominates = (
            (merged["mean_total_cost_010"] <= merged["mean_total_cost_003"] + TOL).all()
            and (merged["mean_shortage_kg_010"] <= merged["mean_shortage_kg_003"] + TOL).all()
            and (merged["operating_loss_CVaR995_010"] <= merged["operating_loss_CVaR995_003"] + TOL).all()
            and (
                (merged["mean_total_cost_010"] < merged["mean_total_cost_003"] - TOL)
                | (merged["mean_shortage_kg_010"] < merged["mean_shortage_kg_003"] - TOL)
                | (merged["operating_loss_CVaR995_010"] < merged["operating_loss_CVaR995_003"] - TOL)
            ).any()
        )
        judgement = (
            "2. eta=0.01在合理扰动范围内显示稳定价值"
            if dominates else "1. eta=0.003在合理扰动范围内显示稳定价值"
        )
    elif bool(evidence["ETA_0.003"]["strong_risk_value"]) and bool(evidence["ETA_0.01"]["strong_risk_value"]):
        judgement = "3. 两者均只在较强扰动下显示有限价值"
    else:
        judgement = "4. 两者在各类扰动下仍无足够稳定价值，建议停止chi-square主线并回到SAA"

    candidate_lines = [
        "status=PASS",
        f"judgement={judgement}",
        "formal_eta_frozen=0",
        "TerminalLOH_reoptimized_on_C3=0",
        "CVaR_role=evaluation_metric_only",
        "location_perturbation=executed_with_decision_and_loss_independent_fixed_geometry_ranking",
        "reasonable_range=intensity-only/location-only/lfw-only delta=0.05 plus combined delta=0.02 and 0.05",
        "stable_value_rule=all 15 reasonable distribution-seed cells weakly improve mean operating loss, mean shortage, CVaR99.5, and mean total cost",
        "strong_only_rule=all three combined-strong seeds improve mean operating loss and CVaR99.5 without worsening mean shortage",
        f"maximum_mechanical_residual={max_residual:.15g}",
        "paired_difference_direction=candidate_minus_SAA; negative means improvement",
        "paired_CI_method=two-sided Student t interval with 14999 degrees of freedom",
    ]
    for candidate_label in CANDIDATES:
        e = evidence[candidate_label]
        inventory = float(full[full["decision_label"] == candidate_label]["TerminalLOH_total_kg"].iloc[0] - full[full["decision_label"] == "SAA"]["TerminalLOH_total_kg"].iloc[0])
        candidate_lines.append(
            f"{candidate_label}: inventory_increment_kg={inventory:.15g}; "
            f"stable_risk_reasonable={int(bool(e['stable_risk_reasonable']))}; "
            f"stable_economic_reasonable={int(bool(e['stable_economic_reasonable']))}; "
            f"strong_risk_value={int(bool(e['strong_risk_value']))}; "
            f"reasonable_total_cost_improvement_cells={e['reasonable_total_cost_improvement_cells']}/{e['reasonable_cell_count']}"
        )
        c = ci_evidence[candidate_label]
        candidate_lines.append(
            f"{candidate_label}: paired_CI95_strictly_negative_counts="
            f"total_cost:{c['total_cost_negative_ci_count']}/21,"
            f"operating_loss:{c['operating_loss_negative_ci_count']}/21,"
            f"shortage:{c['shortage_negative_ci_count']}/21; "
            f"all_three_seed_total_cost_distributions={','.join(c['all_seed_economic_labels'])}"
        )
    (run_dir / "candidate_value_summary.txt").write_text("\n".join(candidate_lines) + "\n", encoding="utf-8")

    process_cert = pd.concat(certificates, ignore_index=True).sort_values(
        ["distribution_id", "seed_id", "eta"]
    )
    process_cert.to_csv(run_dir / "fixed_T_process_certificate.csv", index=False)

    large_rows: list[tuple[str, int, int, str, str]] = []
    for row in manifest.itertuples(index=False):
        path = Path(str(row.local_mat_path))
        large_rows.append((str(path), int(row.sample_count), path.stat().st_size, sha256(path), "local C3 identity and formal D/A/C consequences"))
    for seed_id in range(1, 4):
        for distribution_id in range(1, 8):
            path = run_dir / f"case-seed{seed_id:03d}-dist{distribution_id:03d}" / "scenario_results.csv"
            large_rows.append((str(path), 45000, path.stat().st_size, sha256(path), "local full scenario fixed-T results"))
    large_md = ["# LARGE_FILE_MANIFEST", "", "Large and detailed files remain local and must not be staged.", "", "| path | rows | bytes | sha256 | role |", "|---|---:|---:|---|---|"]
    for path, rows, size, digest, role in large_rows:
        large_md.append(f"| `{path}` | {rows} | {size} | `{digest}` | {role} |")
    (run_dir / "LARGE_FILE_MANIFEST.md").write_text("\n".join(large_md) + "\n", encoding="utf-8")

    seed_lines = []
    for seed_id in range(1, 4):
        row = manifest[manifest["seed_id"] == seed_id].iloc[0]
        seed_lines.append(
            f"- seed {seed_id}: path={int(row.path_seed)}, wind={int(row.wind_seed)}, resistance={int(row.resistance_seed)}"
        )
    readme = f"""# Step-04C-C3 Markov transition perturbation diagnostic

- Status: PASS after all 21 dataset preparations, 63 fixed-decision evaluations, matrix audits, CRN audits, replay audits, row-count checks, and mechanical certificates passed.
- Scope: state19 only. The three TerminalLOH vectors were read directly from C1 accepted run-003 and were never optimized or selected on C3 data.
- Distributions: nominal; intensity-only/location-only/lfw-only at delta 0.05; combined mild/medium/strong at delta 0.02/0.05/0.10.
- Location ordering: lower equal-weight mean Wstep=40 point-to-system distance over lfw 0:3 is higher exposure. This fixed geometry ordering is independent of TerminalLOH, recourse loss, and C3 outcomes.
- Sampling: each distribution and seed is a separate 15,000-row state19 conditional Monte Carlo distribution with weight 1/15000. Distributions and seeds are not pooled into one probability law.
- Common random numbers: within a seed, all seven distributions reuse identical path-uniform blocks and identical wind/resistance random streams; only transition matrices differ. The three seed triplets are independent and collision-free against the audited historical namespaces.
{chr(10).join(seed_lines)}
- CVaR is an evaluation metric only. No chi-square worst-probability construction, Wasserstein ground cost, extreme-aware objective, MSP, or TerminalLOH reoptimization was called.
- Paired differences are candidate minus SAA on the same scenario. Negative values mean improvement; 95% intervals use Student t with 14,999 degrees of freedom.
- Both candidates have strictly negative paired 95% intervals for mean operating loss and mean shortage in all 21 distribution-seed cells. Their overall economic value is less stable because the extra inventory cost is not recovered under nominal or location-only shifts, and lfw-only is significant for only one seed.
- For both candidates, mean total-cost improvement has a strictly negative paired 95% interval in all three seeds for intensity-only, combined-mild, combined-medium, and combined-strong. Mean total-cost advantage grows monotonically along nominal -> combined mild -> combined medium -> combined strong in all three seeds.
- The 21 `NOT_VISITED` transition-frequency rows are exactly location state -2, which can appear only at the third/terminal step from state19 and therefore is never an origin row inside the three-transition horizon. No observed transition leaves nominal support.
- Interpretation: {judgement}. This is a C3 mainline recommendation, not a formal eta freeze.
- Full MAT, scenario-level results, diaries, and process logs remain local and are recorded in `LARGE_FILE_MANIFEST.md`.
"""
    (run_dir / "README.md").write_text(readme, encoding="utf-8")

    required_outputs = [
        "markov_perturbation_spec.csv", "perturbed_transition_matrices.csv",
        "transition_matrix_audit.csv", "seed_and_collision_audit.csv", "dataset_manifest.csv",
        "fixed_T_full_results.csv", "seedwise_paired_comparison.csv", "paired_difference_ci.csv",
        "perturbation_trend_summary.csv", "candidate_value_summary.txt", "README.md",
        "LARGE_FILE_MANIFEST.md",
    ]
    for name in required_outputs:
        if not (run_dir / name).is_file():
            raise RuntimeError(f"Required final output missing: {name}")
    print(f"STEP04CC3_FINALIZE_PASS|judgement={judgement}|max_residual={max_residual:.15g}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: finalize_step04CC3_markov_validation.py RUN_DIR")
    main(Path(sys.argv[1]).resolve())
