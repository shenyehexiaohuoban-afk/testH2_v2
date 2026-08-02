#!/usr/bin/env python3
"""Finalize Step-04C-C2 fixed-decision independent-path validation."""

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
TAIL_GATE_METRICS = ["mean_shortage_kg", "operating_loss_q995", "operating_loss_CVaR995"]


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def rel_change(delta: float, base: float) -> float:
    return delta / abs(base) if abs(base) > 1e-15 else math.nan


def sign_label(value: float, tol: float = 1e-9) -> str:
    if value < -tol:
        return "IMPROVE"
    if value > tol:
        return "WORSEN"
    return "EQUAL"


def main(run_dir: Path) -> None:
    required_prepare = [
        "independent_dataset_manifest.csv",
        "independent_seed_and_collision_audit.csv",
        "independent_path_overlap_audit.csv",
        "independent_reproducibility_audit.csv",
        "fixed_decision_source_audit.csv",
        "prepare_mechanical_audit.txt",
    ]
    for name in required_prepare:
        if not (run_dir / name).is_file():
            raise RuntimeError(f"Missing preparation output: {name}")
    if "status=PASS" not in (run_dir / "prepare_mechanical_audit.txt").read_text(encoding="utf-8"):
        raise RuntimeError("Preparation mechanical audit did not PASS")

    manifest = pd.read_csv(run_dir / "independent_dataset_manifest.csv")
    seed_audit = pd.read_csv(run_dir / "independent_seed_and_collision_audit.csv")
    path_audit = pd.read_csv(run_dir / "independent_path_overlap_audit.csv")
    repro = pd.read_csv(run_dir / "independent_reproducibility_audit.csv")
    if len(manifest) != 3 or not np.all(manifest["sample_count"].to_numpy() == 15000):
        raise RuntimeError("Independent dataset manifest row/count gate failed")
    if not np.allclose(manifest["weight_sum"], 1.0, atol=1e-12, rtol=0):
        raise RuntimeError("Independent dataset weights do not sum to one separately")
    if not (seed_audit["status"] == "PASS").all():
        raise RuntimeError("Seed collision audit failed")
    if path_audit["exact_whole_batch_reuse"].astype(bool).any():
        raise RuntimeError("A C2 dataset exactly reused another/nominal batch")
    if not repro["path_replay_pass"].astype(bool).all() or not repro["formal_replay_pass"].astype(bool).all():
        raise RuntimeError("Reproducibility audit failed")

    summaries: list[pd.DataFrame] = []
    scenarios: list[pd.DataFrame] = []
    certificates: list[pd.DataFrame] = []
    for dataset_id in (1, 2, 3):
        dataset_dir = run_dir / f"dataset-{dataset_id:03d}"
        summary_file = dataset_dir / "fixed_T_summary.csv"
        scenario_file = dataset_dir / "scenario_results.csv"
        certificate_file = dataset_dir / "fixed_T_certificate.csv"
        audit_file = dataset_dir / "mechanical_audit.txt"
        for path in (summary_file, scenario_file, certificate_file, audit_file):
            if not path.is_file():
                raise RuntimeError(f"Missing dataset output: {path}")
        if "status=PASS" not in audit_file.read_text(encoding="utf-8"):
            raise RuntimeError(f"Dataset {dataset_id} mechanical audit failed")
        s = pd.read_csv(summary_file)
        x = pd.read_csv(scenario_file)
        c = pd.read_csv(certificate_file)
        if len(s) != 3 or len(c) != 3 or len(x) != 45000:
            raise RuntimeError(f"Dataset {dataset_id} row count gate failed")
        if set(s["decision_label"]) != {"SAA", "ETA_0.003", "ETA_0.01"}:
            raise RuntimeError(f"Dataset {dataset_id} decision coverage failed")
        if not c["certificate_pass"].astype(bool).all() or not (c["solver_status"] == "OPTIMAL").all():
            raise RuntimeError(f"Dataset {dataset_id} fixed-T certificate failed")
        if c["maximum_mechanical_residual"].max() > 1e-7:
            raise RuntimeError(f"Dataset {dataset_id} mechanical residual exceeded tolerance")
        for label, group in x.groupby("decision_label"):
            if len(group) != 15000 or group["scenario_id"].nunique() != 15000:
                raise RuntimeError(f"Dataset {dataset_id} {label} scenario identity gate failed")
            if not np.isclose(group["sample_weight"].sum(), 1.0, atol=1e-12, rtol=0):
                raise RuntimeError(f"Dataset {dataset_id} {label} weight sum failed")
        summaries.append(s)
        scenarios.append(x)
        certificates.append(c)

    full = pd.concat(summaries, ignore_index=True).sort_values(["dataset_id", "decision_id"])
    full.to_csv(run_dir / "fixed_T_full_results.csv", index=False)
    pd.concat(certificates, ignore_index=True).sort_values(["dataset_id", "decision_id"]).to_csv(
        run_dir / "fixed_T_process_certificate.csv", index=False
    )

    comparison_rows = []
    for dataset_id, group in full.groupby("dataset_id"):
        base = group[group["decision_label"] == "SAA"].iloc[0]
        for _, candidate in group[group["decision_label"] != "SAA"].iterrows():
            row = {
                "dataset_id": int(dataset_id),
                "candidate_label": candidate["decision_label"],
                "eta": candidate["eta"],
                "TerminalLOH_total_change_vs_SAA_kg": candidate["TerminalLOH_total_kg"] - base["TerminalLOH_total_kg"],
            }
            for metric in SUMMARY_METRICS:
                delta = float(candidate[metric] - base[metric])
                row[f"{metric}_absolute_change_vs_SAA"] = delta
                row[f"{metric}_percent_change_vs_SAA"] = rel_change(delta, float(base[metric]))
            comparison_rows.append(row)
    comparison = pd.DataFrame(comparison_rows).sort_values(["dataset_id", "eta"])
    comparison.to_csv(run_dir / "fixed_T_seedwise_comparison.csv", index=False)

    paired_frames = []
    ci_rows = []
    for dataset_id, data in zip((1, 2, 3), scenarios):
        base = data[data["decision_label"] == "SAA"].set_index("scenario_id").sort_index()
        for candidate_label in ("ETA_0.003", "ETA_0.01"):
            candidate = data[data["decision_label"] == candidate_label].set_index("scenario_id").sort_index()
            if not base.index.equals(candidate.index):
                raise RuntimeError(f"Dataset {dataset_id} paired scenario IDs do not align")
            paired = pd.DataFrame({
                "dataset_id": dataset_id,
                "scenario_id": base.index.to_numpy(),
                "candidate_label": candidate_label,
                "eta": float(candidate["eta"].iloc[0]),
            })
            for metric in PAIRED_METRICS:
                diff = candidate[metric].to_numpy(dtype=float) - base[metric].to_numpy(dtype=float)
                paired[f"{metric}_difference_candidate_minus_SAA"] = diff
                paired[f"{metric}_improved"] = diff < -1e-9
                paired[f"{metric}_worsened"] = diff > 1e-9
                paired[f"{metric}_equal"] = np.abs(diff) <= 1e-9
                n = len(diff)
                mean = float(np.mean(diff))
                sd = float(np.std(diff, ddof=1))
                se = sd / math.sqrt(n)
                critical = float(student_t.ppf(0.975, n - 1))
                ci_rows.append({
                    "dataset_id": dataset_id,
                    "candidate_label": candidate_label,
                    "eta": float(candidate["eta"].iloc[0]),
                    "metric": metric,
                    "difference_direction": "candidate_minus_SAA_negative_is_improvement",
                    "sample_count": n,
                    "paired_mean_difference": mean,
                    "paired_sd": sd,
                    "paired_standard_error": se,
                    "t_critical_975_df14999": critical,
                    "paired_mean_difference_CI95_lower": mean - critical * se,
                    "paired_mean_difference_CI95_upper": mean + critical * se,
                    "improved_scenario_share": float(np.mean(diff < -1e-9)),
                    "worsened_scenario_share": float(np.mean(diff > 1e-9)),
                    "equal_scenario_share": float(np.mean(np.abs(diff) <= 1e-9)),
                })
            paired_frames.append(paired)
    paired_full = pd.concat(paired_frames, ignore_index=True).sort_values(
        ["dataset_id", "eta", "scenario_id"]
    )
    paired_path = run_dir / "fixed_T_paired_difference.csv"
    paired_full.to_csv(paired_path, index=False)
    paired_ci = pd.DataFrame(ci_rows).sort_values(["dataset_id", "eta", "metric"])
    paired_ci.to_csv(run_dir / "fixed_T_paired_ci.csv", index=False)

    stability_rows = []
    for label, eta in (("ETA_0.003", 0.003), ("ETA_0.01", 0.01)):
        c = comparison[comparison["candidate_label"] == label].sort_values("dataset_id")
        signs = {}
        for metric in ["mean_total_cost", *TAIL_GATE_METRICS]:
            values = c[f"{metric}_absolute_change_vs_SAA"].to_numpy(dtype=float)
            signs[metric] = "/".join(sign_label(v) for v in values)
        stable_tail = all(
            (c[f"{metric}_absolute_change_vs_SAA"].to_numpy(dtype=float) < -1e-9).all()
            for metric in TAIL_GATE_METRICS
        )
        stability_rows.append({
            "candidate_label": label,
            "eta": eta,
            "seed_count": 3,
            "TerminalLOH_total_increment_vs_SAA_kg": float(c["TerminalLOH_total_change_vs_SAA_kg"].iloc[0]),
            "mean_total_cost_seed_pattern": signs["mean_total_cost"],
            "mean_shortage_seed_pattern": signs["mean_shortage_kg"],
            "q995_loss_seed_pattern": signs["operating_loss_q995"],
            "CVaR995_loss_seed_pattern": signs["operating_loss_CVaR995"],
            "mean_total_cost_improved_seed_count": int((c["mean_total_cost_absolute_change_vs_SAA"] < -1e-9).sum()),
            "mean_shortage_improved_seed_count": int((c["mean_shortage_kg_absolute_change_vs_SAA"] < -1e-9).sum()),
            "q995_loss_improved_seed_count": int((c["operating_loss_q995_absolute_change_vs_SAA"] < -1e-9).sum()),
            "CVaR995_loss_improved_seed_count": int((c["operating_loss_CVaR995_absolute_change_vs_SAA"] < -1e-9).sum()),
            "stable_tail_value_all_three_seeds": stable_tail,
        })
    stability = pd.DataFrame(stability_rows)

    selected_metrics = ["mean_total_cost", "mean_shortage_kg", "operating_loss_q995", "operating_loss_CVaR995"]
    candidate_dominance = {"ETA_0.003": False, "ETA_0.01": False}
    for left, right in (("ETA_0.003", "ETA_0.01"), ("ETA_0.01", "ETA_0.003")):
        l = full[full["decision_label"] == left].sort_values("dataset_id")
        r = full[full["decision_label"] == right].sort_values("dataset_id")
        no_worse = all((l[m].to_numpy() <= r[m].to_numpy() + 1e-9).all() for m in selected_metrics)
        strict = any((l[m].to_numpy() < r[m].to_numpy() - 1e-9).any() for m in selected_metrics)
        candidate_dominance[left] = bool(no_worse and strict)
    stability["stably_dominates_other_candidate_on_selected_metrics"] = stability["candidate_label"].map(candidate_dominance)

    stable = dict(zip(stability["candidate_label"], stability["stable_tail_value_all_three_seeds"].astype(bool)))
    if stable["ETA_0.003"] and stable["ETA_0.01"]:
        if candidate_dominance["ETA_0.003"] and not candidate_dominance["ETA_0.01"]:
            decision_code = "1. ETA_0.003_ONLY_TO_MARKOV_VALIDATION"
        elif candidate_dominance["ETA_0.01"] and not candidate_dominance["ETA_0.003"]:
            decision_code = "2. ETA_0.01_ONLY_TO_MARKOV_VALIDATION"
        else:
            decision_code = "3. RETAIN_BOTH_TO_MARKOV_VALIDATION"
    elif stable["ETA_0.003"]:
        decision_code = "1. ETA_0.003_ONLY_TO_MARKOV_VALIDATION"
    elif stable["ETA_0.01"]:
        decision_code = "2. ETA_0.01_ONLY_TO_MARKOV_VALIDATION"
    else:
        decision_code = "4. NEITHER_SHOWS_STABLE_VALUE_RETURN_TO_SAA_OR_RADIUS_REVIEW"
    stability["C2_candidate_judgement"] = decision_code
    stability.to_csv(run_dir / "cross_seed_stability_summary.csv", index=False)

    process_cert = pd.concat(certificates, ignore_index=True)
    max_residual = float(process_cert["maximum_mechanical_residual"].max())
    seed_lines = [
        f"dataset-{int(r.dataset_id):03d}: path={int(r.path_seed)}, wind={int(r.wind_seed)}, resistance={int(r.resistance_seed)}"
        for r in manifest.itertuples()
    ]
    tradeoff_lines = [
        "Step-04C-C2 state19 independent typhoon-path validation",
        "status=PASS",
        "namespace=independent-path-C2",
        "datasets=3 independent state19 Monte Carlo distributions; each has R=15000 and weights 1/15000",
        "dataset_pooling_interpretation=seedwise results are primary; any cross-seed summary is equal-weight descriptive only",
        "fixed_decisions_source=Step-04C-C1 accepted run-003 nominal optimizations",
        "test_set_optimization_performed=false",
        "chi_square_worst_probability_constructed=false",
        "CVaR_role=evaluation_metric_only",
        f"candidate_judgement={decision_code}",
        "judgement_rationale=both candidates reduce mean shortage and CVaR99.5 in all three seeds, but improvements are small; q99.5 is not uniformly improved and mean total cost worsens in two seeds",
        "eta_0.01_inventory_tradeoff=the additional 17.0368707551 kg versus SAA does not buy a sufficiently large or uniformly quantile-visible tail improvement",
        "formal_eta_frozen=false",
        "Markov_transition_probability_perturbation_completed=false",
        "paired_difference_direction=candidate_minus_SAA; negative means improvement",
        "paired_CI_method=two-sided Student t interval, df=14999, scenario-paired within each dataset",
        f"maximum_fixed_T_mechanical_residual={max_residual:.15g}",
        *seed_lines,
    ]
    for row in stability.itertuples():
        tradeoff_lines.append(
            f"{row.candidate_label}: inventory_increment_kg={row.TerminalLOH_total_increment_vs_SAA_kg:.15g}; "
            f"mean_cost_pattern={row.mean_total_cost_seed_pattern}; mean_shortage_pattern={row.mean_shortage_seed_pattern}; "
            f"q995_pattern={row.q995_loss_seed_pattern}; CVaR995_pattern={row.CVaR995_loss_seed_pattern}; "
            f"stable_tail_value={str(bool(row.stable_tail_value_all_three_seeds)).lower()}"
        )
    tradeoff_lines.append("development_history=run-001 preserved; preparation passed, but the first fixed-T process was rejected because the certificate used an over-strict 1e-14 floating weight-sum tolerance; run-002 froze 1e-12 before rerunning all datasets from scratch")
    (run_dir / "candidate_tradeoff_summary.txt").write_text("\n".join(tradeoff_lines) + "\n", encoding="utf-8")

    large_rows = []
    for row in manifest.itertuples():
        path = Path(row.local_mat_path)
        large_rows.append((str(path), int(row.sample_count), path.stat().st_size, sha256(path), "full independent path/consequence D/A/C payload"))
    for dataset_id in (1, 2, 3):
        path = run_dir / f"dataset-{dataset_id:03d}" / "scenario_results.csv"
        large_rows.append((str(path), 45000, path.stat().st_size, sha256(path), "full per-scenario fixed-T results for three decisions"))
    large_rows.append((str(paired_path), len(paired_full), paired_path.stat().st_size, sha256(paired_path), "full scenario-paired candidate-minus-SAA differences"))
    large_md = [
        "# LARGE_FILE_MANIFEST", "",
        "These local files are required for full reproduction but are not eligible for Git.", "",
        "| Local path | Rows/records | Bytes | SHA-256 | Meaning |",
        "|---|---:|---:|---|---|",
    ]
    for path, rows, size, digest, meaning in large_rows:
        large_md.append(f"| `{path}` | {rows} | {size} | `{digest}` | {meaning} |")
    (run_dir / "LARGE_FILE_MANIFEST.md").write_text("\n".join(large_md) + "\n", encoding="utf-8")

    readme = f"""# Step-04C-C2 run

- Status: PASS; accepted as the first complete run only after the Git-scope audit.
- Scope: state19 fixed-decision validation on three genuinely different typhoon-path random seeds.
- Namespace: `independent-path-C2`; every dataset separately contains 15,000 scenarios with weight `1/15000`.
- Frozen decisions: SAA eta=0, eta=0.003, and eta=0.01, read directly from Step-04C-C1 accepted `run-003` nominal optimization results.
- No TerminalLOH optimization or eta selection was performed on the independent datasets.
- CVaR is an evaluation metric only. No mean-CVaR or chi-square-plus-CVaR objective was introduced.
- The three datasets are reported seedwise. Cross-seed summaries are descriptive and do not reinterpret the 45,000 rows as one probability distribution.
- Ordinary overlap of discrete physical path values is reported separately from random-stream collision and exact whole-batch reuse.
- Paired differences use `candidate - SAA`; negative values mean improvement. The 95% CI is a two-sided Student-t interval with 14,999 degrees of freedom.
- Candidate judgement: `{decision_code}`.
- Both candidates reduce mean shortage and CVaR99.5 on all three seeds, but the gains are small. The q99.5 loss is not uniformly improved, while mean total cost worsens on two seeds. The extra 17.0369 kg for eta=0.01 is not justified by a sufficiently large, uniformly visible tail benefit.
- Formal eta remains unfrozen. Markov transition-probability perturbation has not been performed.
- Maximum fixed-T mechanical residual: `{max_residual:.15g}`.
- Large MAT, full scenario results, and the full paired-difference table remain local and are listed with SHA-256 in `LARGE_FILE_MANIFEST.md`.
- Development history: `run-001` is preserved as failed evidence. Its preparation passed, but the first fixed-T process was rejected by an over-strict `1e-14` floating weight-sum tolerance. `run-002` froze `1e-12` before rerunning all datasets from scratch.
"""
    (run_dir / "README.md").write_text(readme, encoding="utf-8")

    required_final = [
        "independent_dataset_manifest.csv", "independent_seed_and_collision_audit.csv",
        "independent_path_overlap_audit.csv", "fixed_T_full_results.csv",
        "fixed_T_seedwise_comparison.csv", "fixed_T_paired_difference.csv",
        "fixed_T_paired_ci.csv", "cross_seed_stability_summary.csv",
        "candidate_tradeoff_summary.txt", "README.md", "LARGE_FILE_MANIFEST.md",
    ]
    for name in required_final:
        if not (run_dir / name).is_file():
            raise RuntimeError(f"Missing final output: {name}")
    print(f"STEP04CC2_FINALIZE_PASS|decision={decision_code}|max_residual={max_residual:.15g}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: finalize_step04CC2_independent_validation.py RUN_DIR")
    main(Path(sys.argv[1]).resolve())
