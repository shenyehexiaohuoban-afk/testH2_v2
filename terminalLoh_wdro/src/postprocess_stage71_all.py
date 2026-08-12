"""Unified Stage-71 postprocessing after all six numerical cases finish."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd


BIN_EDGES = [-np.inf, 1, 10, 20, 30, 50, 100, np.inf]
BIN_LABELS = ["<=1", "1-10", "10-20", "20-30", "30-50", "50-100", ">100"]
PREP_COUNTS = [2, 3, 4, 5, 6]
EXPERIMENTS = ["Baseline_6h", "E1_8h", "E2_6h_pmax_4over3", "E3_8h_htt_4over3"]
DIRS = {
    "E1_8h": "E1_8h",
    "E2_6h_pmax_4over3": "E2_6h_pmax_4over3",
    "E3_8h_htt_4over3": "E3_8h_htt_4over3",
}
SOURCE_HASHES = {
    "oos": "6e4ed488423e3cbb838c4a6f8b45019cf4ecf32a82850880399a08aafc7aff85",
    "stage65": "58336879de53ea1d216315af7c813c02944b1a0e9746246184ffecb519e9914b",
    "stage68": "66ba1d7ad593b44b292626ecf24261dae37f0bd28b937e47af0947c1b2fb47f0",
}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def load_new_pair(run_root: Path, experiment: str) -> pd.DataFrame:
    case_root = run_root / DIRS[experiment]
    saa = pd.read_csv(case_root / "case-saa/stage71_oos_path_summary.csv")
    dro = pd.read_csv(case_root / "case-chi2_eta003/stage71_oos_path_summary.csv")
    require(len(saa) == len(dro) == 10000, f"10000-path gate failed: {experiment}")
    require(np.array_equal(saa.path_id, dro.path_id), f"SAA/DRO path mismatch: {experiment}")
    identity = ["path_id", "terminal_hit", "terminal_stage", "terminal_state_k", "a", "loc", "lf", "terminal_state"]
    for col in identity[1:]:
        require(np.allclose(saa[col].fillna(-999), dro[col].fillna(-999)),
                f"SAA/DRO identity mismatch {experiment}: {col}")
    out = saa[identity].copy()
    metrics = ["production", "htt", "ordinary_shortage", "final_inventory",
               "operating_cost", "reported_objective", "terminal_gap_penalty",
               "terminal_loh_target", "terminal_gap", "production_cost",
               "transport_cost", "holding_cost", "ordinary_shortage_cost"]
    for metric in metrics:
        out[f"saa_{metric}"] = saa[metric]
        out[f"dro_{metric}"] = dro[metric]
        out[f"delta_{metric}"] = dro[metric] - saa[metric]
    for site in range(1, 5):
        out[f"saa_final_site{site}"] = saa[f"final_site{site}"]
        out[f"dro_final_site{site}"] = dro[f"final_site{site}"]
        out[f"saa_target_site{site}"] = saa[f"target_site{site}"]
        out[f"dro_target_site{site}"] = dro[f"target_site{site}"]
        out[f"saa_gap_site{site}"] = saa[f"gap_site{site}"]
        out[f"dro_gap_site{site}"] = dro[f"gap_site{site}"]
    out["delta_i"] = out.delta_final_inventory
    out["experiment"] = experiment
    return out


def load_all(repo: Path, run_root: Path) -> tuple[dict[str, pd.DataFrame], pd.DataFrame]:
    base = repo / "results/task-002-stage2b-b3-smoke"
    stage65 = base / "65-oos-pathwise-saa-dro-performance-audit/run-002/pathwise_saa_dro_comparison.csv"
    stage68_path = base / "68-oos-risk-feature-association-audit/run-004/pathwise_risk_feature_analysis_table.csv"
    oos = repo / "output_h2/details/h2_OOS.csv"
    for key, path in {"oos": oos, "stage65": stage65, "stage68": stage68_path}.items():
        require(sha256_file(path) == SOURCE_HASHES[key], f"Frozen source hash mismatch: {key}")
    baseline = pd.read_csv(stage65)
    baseline["delta_i"] = baseline.delta_final_inventory
    baseline["experiment"] = "Baseline_6h"
    stage68 = pd.read_csv(stage68_path, usecols=["path_id", "terminal_hit", "preparation_stage_count"])
    require(len(baseline) == len(stage68) == 10000, "Baseline path-count gate failed.")
    require(np.array_equal(baseline.path_id, stage68.path_id), "Baseline/Stage-68 path identity failed.")
    datasets = {"Baseline_6h": baseline}
    for experiment in EXPERIMENTS[1:]:
        datasets[experiment] = load_new_pair(run_root, experiment)
    for experiment, frame in datasets.items():
        merged = frame.merge(stage68, on=["path_id", "terminal_hit"], validate="one_to_one")
        require(int(merged.terminal_hit.sum()) == 6053, f"Terminal-hit gate failed: {experiment}")
        datasets[experiment] = merged
    return datasets, stage68


def summarize(datasets: dict[str, pd.DataFrame]) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    summary_rows, dist_rows, prep_rows, gap_rows, cost_rows = [], [], [], [], []
    for experiment in EXPERIMENTS:
        frame = datasets[experiment]
        hit = frame[frame.terminal_hit == 1].copy()
        hit["delta_i_bin"] = pd.cut(hit.delta_i, BIN_EDGES, labels=BIN_LABELS,
                                    right=True, include_lowest=True).astype(str)
        def share(mask: pd.Series) -> float:
            return float(mask.mean())
        summary_rows.append({
            "experiment": experiment,
            "path_count": len(frame), "terminal_hit_path_count": len(hit),
            "mean_delta_production_kg": frame.delta_production.mean(),
            "mean_delta_htt_kg": frame.delta_htt.mean(),
            "mean_delta_i_kg": frame.delta_i.mean(),
            "terminal_hit_delta_i_le_1_share": share(hit.delta_i <= 1),
            "terminal_hit_delta_i_gt_10_share": share(hit.delta_i > 10),
            "terminal_hit_delta_i_gt_20_share": share(hit.delta_i > 20),
            "terminal_hit_delta_i_20_50_share": share((hit.delta_i > 20) & (hit.delta_i <= 50)),
            "saa_terminal_gap_mean_kg": hit.saa_terminal_gap.mean(),
            "dro_terminal_gap_mean_kg": hit.dro_terminal_gap.mean(),
            "saa_gap_positive_share": share(hit.saa_terminal_gap > 1e-9),
            "dro_gap_positive_share": share(hit.dro_terminal_gap > 1e-9),
            "mean_delta_ordinary_shortage_kg": frame.delta_ordinary_shortage.mean(),
            "mean_delta_operating_cost": frame.delta_operating_cost.mean(),
            "mean_delta_reported_objective": frame.delta_reported_objective.mean(),
            "mean_delta_production_cost": frame.get("delta_production_cost", pd.Series(dtype=float)).mean(),
            "mean_delta_transport_cost": frame.get("delta_transport_cost", pd.Series(dtype=float)).mean(),
            "mean_delta_holding_cost": frame.get("delta_holding_cost", pd.Series(dtype=float)).mean(),
            "mean_delta_ordinary_shortage_cost": frame.get("delta_ordinary_shortage_cost", pd.Series(dtype=float)).mean(),
        })
        counts = hit.delta_i_bin.value_counts().reindex(BIN_LABELS, fill_value=0)
        for label in BIN_LABELS:
            dist_rows.append({"experiment": experiment, "delta_i_bin": label,
                              "path_count": int(counts[label]), "share": counts[label] / len(hit)})
        for prep in PREP_COUNTS:
            group = hit[hit.preparation_stage_count == prep]
            bins = pd.cut(group.delta_i, BIN_EDGES, labels=BIN_LABELS,
                          right=True, include_lowest=True).astype(str)
            bin_counts = bins.value_counts().reindex(BIN_LABELS, fill_value=0)
            for label in BIN_LABELS:
                prep_rows.append({"experiment": experiment, "preparation_stage_count": prep,
                                  "delta_i_bin": label, "path_count": int(bin_counts[label]),
                                  "row_share": bin_counts[label] / len(group) if len(group) else np.nan,
                                  "prep_path_count": len(group), "mean_delta_i_kg": group.delta_i.mean(),
                                  "median_delta_i_kg": group.delta_i.median(),
                                  "delta_i_le_1_share": (group.delta_i <= 1).mean(),
                                  "delta_i_gt_10_share": (group.delta_i > 10).mean(),
                                  "delta_i_gt_20_share": (group.delta_i > 20).mean()})
        for method in ["saa", "dro"]:
            values = hit[f"{method}_terminal_gap"]
            gap_rows.append({"experiment": experiment, "method": method.upper(),
                             "path_count": len(values), "mean_gap_kg": values.mean(),
                             "median_gap_kg": values.median(), "q95_gap_kg": values.quantile(.95),
                             "gap_positive_count": int((values > 1e-9).sum()),
                             "gap_positive_share": (values > 1e-9).mean()})
        cost_rows.append({
            "experiment": experiment,
            "saa_ordinary_shortage_mean_kg": frame.saa_ordinary_shortage.mean(),
            "dro_ordinary_shortage_mean_kg": frame.dro_ordinary_shortage.mean(),
            "delta_ordinary_shortage_mean_kg": frame.delta_ordinary_shortage.mean(),
            "saa_operating_cost_mean": frame.saa_operating_cost.mean(),
            "dro_operating_cost_mean": frame.dro_operating_cost.mean(),
            "delta_operating_cost_mean": frame.delta_operating_cost.mean(),
            "delta_production_cost_mean": frame.get("delta_production_cost", pd.Series(dtype=float)).mean(),
            "delta_transport_cost_mean": frame.get("delta_transport_cost", pd.Series(dtype=float)).mean(),
            "delta_holding_cost_mean": frame.get("delta_holding_cost", pd.Series(dtype=float)).mean(),
            "delta_ordinary_shortage_cost_mean": frame.get("delta_ordinary_shortage_cost", pd.Series(dtype=float)).mean(),
        })
    return tuple(map(pd.DataFrame, [summary_rows, dist_rows, prep_rows, gap_rows, cost_rows]))


def config_summary(run_root: Path) -> pd.DataFrame:
    rows = [{"experiment": "Baseline_6h", "dt_h": 6, "pmax1_kw": 300, "pmax2_kw": 200,
             "pmax3_kw": 120, "pmax4_kw": 150, "rmax1_kg": 35.10, "rmax2_kg": 23.40,
             "rmax3_kg": 14.04, "rmax4_kg": 17.55, "htt_capacity_kg_per_stage": 160,
             "training_budget_s": 3600, "source": "accepted Stage-57 run-003 / Stage-65 run-002"}]
    for experiment in EXPERIMENTS[1:]:
        identity = pd.read_csv(run_root / DIRS[experiment] / "case-saa/parameter_identity.csv").iloc[0]
        rows.append({"experiment": experiment, "dt_h": identity.dt_h,
                     **{f"pmax{i}_kw": identity[f"pmax{i}_kw"] for i in range(1, 5)},
                     **{f"rmax{i}_kg": identity[f"rmax{i}_kg"] for i in range(1, 5)},
                     "htt_capacity_kg_per_stage": identity.htt_capacity_kg_per_stage,
                     "training_budget_s": identity.time_limit_s,
                     "source": "Stage-71 isolated sensitivity policy"})
    return pd.DataFrame(rows)


def figures(out: Path, dist: pd.DataFrame, prep: pd.DataFrame, gaps: pd.DataFrame, costs: pd.DataFrame) -> None:
    colors = ["#697386", "#2F6BFF", "#00A389", "#F59E0B"]
    pivot = dist.pivot(index="experiment", columns="delta_i_bin", values="share").reindex(EXPERIMENTS)[BIN_LABELS]
    ax = pivot.plot(kind="bar", stacked=True, figsize=(11, 6), color=plt.cm.viridis(np.linspace(.1, .9, len(BIN_LABELS))))
    ax.set_ylabel("Share of terminal-hit paths"); ax.set_xlabel(""); ax.legend(title="Delta I bin", ncol=4)
    plt.tight_layout(); plt.savefig(out / "fig1_delta_i_distribution.png", dpi=180); plt.close()
    prep_one = prep.drop_duplicates(["experiment", "preparation_stage_count"])
    fig, ax = plt.subplots(figsize=(10, 5.5))
    for color, experiment in zip(colors, EXPERIMENTS):
        q = prep_one[prep_one.experiment == experiment]
        ax.plot(q.preparation_stage_count, 100*q.delta_i_le_1_share, marker="o", label=experiment, color=color)
    ax.set_xlabel("Preparation-stage count"); ax.set_ylabel("Delta I <=1 kg (%)"); ax.legend(); ax.grid(alpha=.2)
    fig.tight_layout(); fig.savefig(out / "fig2_prep_small_change_share.png", dpi=180); plt.close(fig)
    fig, ax = plt.subplots(figsize=(10, 5.5))
    for color, experiment in zip(colors, EXPERIMENTS):
        q = prep_one[prep_one.experiment == experiment]
        ax.plot(q.preparation_stage_count, q.mean_delta_i_kg, marker="o", label=experiment, color=color)
    ax.set_xlabel("Preparation-stage count"); ax.set_ylabel("Mean Delta I (kg)"); ax.legend(); ax.grid(alpha=.2)
    fig.tight_layout(); fig.savefig(out / "fig3_prep_mean_delta_i.png", dpi=180); plt.close(fig)
    gap_pivot = gaps.pivot(index="experiment", columns="method", values="mean_gap_kg").reindex(EXPERIMENTS)
    ax = gap_pivot.plot(kind="bar", figsize=(10, 5.5), color=["#697386", "#2F6BFF"])
    ax.set_ylabel("Mean terminal gap (kg)"); ax.set_xlabel(""); plt.tight_layout()
    plt.savefig(out / "fig4_terminal_gap.png", dpi=180); plt.close()
    fig, axes = plt.subplots(1, 2, figsize=(12, 5))
    axes[0].bar(EXPERIMENTS, costs.delta_operating_cost_mean, color=colors)
    axes[0].set_title("DRO - SAA operating cost"); axes[0].tick_params(axis="x", rotation=20)
    axes[1].bar(EXPERIMENTS, costs.delta_ordinary_shortage_mean_kg, color=colors)
    axes[1].set_title("DRO - SAA ordinary shortage"); axes[1].tick_params(axis="x", rotation=20)
    fig.tight_layout(); fig.savefig(out / "fig5_operating_cost_shortage.png", dpi=180); plt.close(fig)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-root", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    run_root = (repo / args.run_root).resolve()
    out = (repo / args.output).resolve()
    require(not out.exists(), f"Refusing to overwrite cross-analysis output: {out}")
    out.mkdir(parents=True)
    datasets, _ = load_all(repo, run_root)
    summary, dist, prep, gaps, costs = summarize(datasets)
    configs = config_summary(run_root)
    configs.to_csv(out / "experiment_config_summary.csv", index=False)
    summary.to_csv(out / "cross_experiment_summary.csv", index=False)
    dist.to_csv(out / "deltaI_distribution_comparison.csv", index=False)
    prep.to_csv(out / "prep_deltaI_cross_comparison.csv", index=False)
    gaps.to_csv(out / "terminal_gap_comparison.csv", index=False)
    costs.to_csv(out / "ordinary_shortage_cost_comparison.csv", index=False)
    figures(out, dist, prep, gaps, costs)
    lines = ["Stage-71 automatic numeric summary", "", "Scope: descriptive common-OOS comparison; no causal claim.", ""]
    for row in summary.itertuples(index=False):
        lines.append(f"{row.experiment}: mean Delta production={row.mean_delta_production_kg:.9f} kg; "
                     f"mean Delta HTT={row.mean_delta_htt_kg:.9f} kg; mean Delta I={row.mean_delta_i_kg:.9f} kg; "
                     f"terminal-hit <=1={row.terminal_hit_delta_i_le_1_share:.6%}; "
                     f">10={row.terminal_hit_delta_i_gt_10_share:.6%}; >20={row.terminal_hit_delta_i_gt_20_share:.6%}; "
                     f"SAA/DRO gap={row.saa_terminal_gap_mean_kg:.9f}/{row.dro_terminal_gap_mean_kg:.9f} kg; "
                     f"Delta ordinary shortage={row.mean_delta_ordinary_shortage_kg:.9f} kg; "
                     f"Delta operating cost={row.mean_delta_operating_cost:.9f}.")
    (out / "final_numeric_summary.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    (out / "README.md").write_text(
        "# Stage-71 cross-experiment analysis\n\nStatus: candidate PASS pending independent verification.\n\n"
        "Baseline is the frozen accepted Stage-57/65 result. E1/E2/E3 use isolated one-hour fixed-budget policies "
        "and the exact frozen 10000x8 OOS paths. Reported objective is retained separately from modeled operating cost.\n",
        encoding="utf-8")
    print(f"Stage-71 postprocess complete: {out}")


if __name__ == "__main__":
    main()
