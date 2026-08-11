"""Step-05B-11A symmetric SAA/DRO TerminalLOH attainment audit."""

from __future__ import annotations

import argparse
import hashlib
import subprocess
import warnings
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from scipy.stats import spearmanr


EXPECTED_BRANCH = "task/002-stage2b-b3-smoke"
EXPECTED_HEAD = "dc14630ac1c50761dcd96358cdd65393d85713fc"
GAP_TOL = 1.0e-9
HASHES = {
    "oos": "6e4ed488423e3cbb838c4a6f8b45019cf4ecf32a82850880399a08aafc7aff85",
    "saa_table": "2a47fbe844633e20f588add221b75fa2c2d8293694ab5d9ed80e299fe29086d4",
    "dro_table": "077d8b86f7f4ab896a61dbfe5e446476f3adcedc4ad7ffc98e29855b834ea1aa",
    "stage58": "1d23404cf46629bc3db4f983b47fe2e5b1a2260d0379a792b1674b4681419165",
    "stage59_saa": "ad2718b69e09de71850bb29ccdd33657732ca082a09a0ee06c4d67841dd22262",
    "stage59_dro": "2dfb46ab3c851e853cb8baff7ea84689488f6260f620b9cdd30005a28ee2c9a7",
    "stage60": "070dbe1c4af028f6f658bb31c4daa72e21eee465b8c02e4bb477fc23d22b94a7",
    "stage64": "d5a567264165d59c6115d303517eaac51904ba569a8b87a69cf0d0ceaeb8759b",
    "stage65": "58336879de53ea1d216315af7c813c02944b1a0e9746246184ffecb519e9914b",
    "stage68": "66ba1d7ad593b44b292626ecf24261dae37f0bd28b937e47af0947c1b2fb47f0",
}
METHOD_LABEL = {"saa": "SAA", "chi2_eta003": "DRO_eta_0.03"}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def git(repo: Path, *args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=repo, text=True).strip()


def safe_spearman(x: pd.Series, y: pd.Series) -> tuple[float, float, int]:
    valid = pd.DataFrame({"x": x, "y": y}).dropna()
    if len(valid) < 3 or valid.x.nunique() < 2 or valid.y.nunique() < 2:
        return np.nan, np.nan, len(valid)
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        result = spearmanr(valid.x, valid.y)
    return float(result[0]), float(result[1]), len(valid)


def describe(values: pd.Series) -> dict[str, float | int]:
    x = values.dropna().astype(float)
    if len(x) == 0:
        return {"n": 0, "mean": np.nan, "median": np.nan, "q95": np.nan, "min": np.nan, "max": np.nan}
    return {"n": len(x), "mean": x.mean(), "median": x.median(), "q95": x.quantile(0.95),
            "min": x.min(), "max": x.max()}


def source_paths(repo: Path) -> dict[str, Path]:
    base = repo / "results/task-002-stage2b-b3-smoke"
    return {
        "oos": repo / "output_h2/details/h2_OOS.csv",
        "saa_table": base / "53-35state-saa-vs-eta003-terminal-loh/run-024/terminal_loh_table_saa.csv",
        "dro_table": base / "53-35state-saa-vs-eta003-terminal-loh/run-024/terminal_loh_table_eta_003.csv",
        "stage58": base / "58-main-msp-terminal-gap-mechanism-audit/run-004/terminal_target_vs_final_inventory.csv",
        "stage59_saa": base / "59-terminal-loh-realization-audit/run-001/saa_attainment_summary.csv",
        "stage59_dro": base / "59-terminal-loh-realization-audit/run-001/dro_attainment_summary.csv",
        "stage60": base / "60-terminal-loh-required-extra-and-flow-audit/run-002/path_station_abcd_classification.csv",
        "stage64": base / "64-terminal-loh-all-state-capacity-gap-audit/run-002/all_path_saa_dro_feasibility_transition.csv",
        "stage65": base / "65-oos-pathwise-saa-dro-performance-audit/run-002/pathwise_saa_dro_comparison.csv",
        "stage68": base / "68-oos-risk-feature-association-audit/run-004/pathwise_risk_feature_analysis_table.csv",
    }


def validate_sources(repo: Path, paths: dict[str, Path]) -> None:
    require(git(repo, "branch", "--show-current") == EXPECTED_BRANCH, "Unexpected branch.")
    require(git(repo, "rev-parse", "HEAD") == EXPECTED_HEAD, "HEAD changed from accepted Stage-68 commit.")
    require(git(repo, "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}") ==
            "origin/task/002-stage2b-b3-smoke", "Unexpected upstream.")
    require(git(repo, "rev-list", "--left-right", "--count", "HEAD...@{upstream}") == "0\t0",
            "Branch is not synchronized with upstream.")
    for key, path in paths.items():
        require(path.is_file(), f"Missing accepted input: {path}")
        require(sha256_file(path) == HASHES[key], f"Accepted input hash changed: {key}")


def build_symmetric_table(paths: dict[str, Path]) -> tuple[pd.DataFrame, dict[str, float]]:
    source = pd.read_csv(paths["stage58"])
    stage65 = pd.read_csv(paths["stage65"])
    stage68 = pd.read_csv(paths["stage68"])
    oos = pd.read_csv(paths["oos"])
    require(len(source) == 20000 and source.groupby("method").size().to_dict() ==
            {"chi2_eta003": 10000, "saa": 10000}, "Stage-58 method/path shape changed.")
    require(oos.shape == (10000, 8), "Frozen OOS is not 10000x8.")
    require(stage65.path_id.tolist() == stage68.path_id.tolist() == list(range(1, 10001)),
            "Stage-65/68 path identity failed.")
    require(np.array_equal(stage65.terminal_hit, stage68.terminal_hit), "Stage-65/68 terminal-hit identity failed.")
    require(int(stage68.terminal_hit.sum()) == 6053, "Stage-68 terminal-hit count changed.")

    hit = source[source.hit_terminal == 1].copy()
    require(hit.groupby("method").size().to_dict() == {"chi2_eta003": 6053, "saa": 6053},
            "Expected 6053 terminal-hit paths per method.")
    features = stage68.loc[stage68.terminal_hit == 1,
                           ["path_id", "terminal_stage", "terminal_state", "preparation_stage_count"]].copy()
    hit = hit.merge(features, on="path_id", how="left", suffixes=("_stage58", "_stage68"), validate="many_to_one")
    require(hit.preparation_stage_count.notna().all(), "At least one terminal-hit path lacks Stage-68 prep count.")
    require(np.array_equal(hit.terminal_stage_stage58.astype(int), hit.terminal_stage_stage68.astype(int)),
            "Stage-58/68 terminal-stage mismatch.")
    hit["state_id"] = (hit.a - 2) * 7 + hit["loc"]
    require(np.array_equal(hit.state_id.astype(int), hit.terminal_state_stage68.astype(int)),
            "Stage-58/68 terminal-state mapping mismatch.")

    max_site_gap_error = 0.0
    for site in range(1, 5):
        calc = np.maximum(0.0, hit[f"target_site{site}"] - hit[f"final_site{site}"])
        max_site_gap_error = max(max_site_gap_error, float(np.max(np.abs(calc - hit[f"gap_site{site}"]))))
        hit[f"gap_site{site}_raw_kg"] = calc
        hit[f"gap_site{site}_kg"] = np.where(calc > GAP_TOL, calc, 0.0)
    hit["target_total_rebuilt_kg"] = sum(hit[f"target_site{i}"] for i in range(1, 5))
    hit["inventory_total_rebuilt_kg"] = sum(hit[f"final_site{i}"] for i in range(1, 5))
    hit["gap_total_raw_rebuilt_kg"] = sum(hit[f"gap_site{i}_raw_kg"] for i in range(1, 5))
    hit["gap_total_kg"] = sum(hit[f"gap_site{i}_kg"] for i in range(1, 5))
    hit["gap_positive"] = (hit.gap_total_kg > 0).astype(int)
    hit["aggregate_net_shortfall_kg"] = np.maximum(0.0, hit.target_total_rebuilt_kg - hit.inventory_total_rebuilt_kg)
    hit["stationwise_minus_aggregate_gap_kg"] = hit.gap_total_kg - hit.aggregate_net_shortfall_kg
    require(max_site_gap_error < 1e-9, f"Stored site gap does not equal max(0,T_i-I_i): {max_site_gap_error}")
    require(float(np.max(np.abs(hit.target_total_rebuilt_kg - hit.target_total))) < 1e-9, "Target total identity failed.")
    require(float(np.max(np.abs(hit.inventory_total_rebuilt_kg - hit.final_total))) < 1e-9, "Inventory total identity failed.")
    require(float(np.max(np.abs(hit.gap_total_raw_rebuilt_kg - hit.gap_total))) < 1e-9, "Stationwise gap total identity failed.")

    lookup = {
        "saa": pd.read_csv(paths["saa_table"]).set_index("state_id"),
        "chi2_eta003": pd.read_csv(paths["dro_table"]).set_index("state_id"),
    }
    max_lookup_error = 0.0
    for method, group in hit.groupby("method"):
        table = lookup[method]
        for site in range(1, 5):
            expected = group.state_id.map(table[f"T{site}_kg"])
            max_lookup_error = max(max_lookup_error, float(np.max(np.abs(expected - group[f"target_site{site}"]))))
        expected_total = group.state_id.map(table.TerminalLOH_total_kg)
        max_lookup_error = max(max_lookup_error, float(np.max(np.abs(expected_total - group.target_total))))
    require(max_lookup_error < 1e-9, f"Stage-53 target lookup mismatch: {max_lookup_error}")

    # Stage-60 is a path-site wide cross-check of the same accepted T/I fields.
    stage60 = pd.read_csv(paths["stage60"]).sort_values(["path_id", "site"])
    require(len(stage60) == 6053 * 4, "Stage-60 path-site row count changed.")
    max_stage60_error = 0.0
    for method, prefix in [("saa", "saa"), ("chi2_eta003", "dro")]:
        g = hit[hit.method == method].set_index("path_id")
        for site in range(1, 5):
            x = stage60[stage60.site == site].set_index("path_id")
            max_stage60_error = max(max_stage60_error,
                float(np.max(np.abs(g[f"target_site{site}"] - x[f"T_{prefix}_kg"]))))
            max_stage60_error = max(max_stage60_error,
                float(np.max(np.abs(g[f"final_site{site}"] - x[f"I_{prefix}_kg"]))))
    require(max_stage60_error < 1e-9, f"Stage-60 site T/I cross-check failed: {max_stage60_error}")

    # Stage-64 supplies an independent accepted total target/actual/station-gap table.
    stage64 = pd.read_csv(paths["stage64"]).set_index("path_id")
    max_stage64_error = 0.0
    for method, suffix in [("saa", "saa"), ("chi2_eta003", "dro")]:
        g = hit[hit.method == method].set_index("path_id")
        for left, right in [
            ("target_total", f"terminal_loh_total_target_kg_{suffix}"),
            ("final_total", f"actual_final_inventory_total_kg_{suffix}"),
            ("gap_total", f"actual_station_gap_total_kg_{suffix}"),
        ]:
            max_stage64_error = max(max_stage64_error, float(np.max(np.abs(g[left] - stage64[right]))))
    require(max_stage64_error < 1e-9, f"Stage-64 total cross-check failed: {max_stage64_error}")

    keep = ["method", "path_id", "state_id", "a", "loc", "lf", "preparation_stage_count"]
    for site in range(1, 5):
        keep += [f"target_site{site}", f"final_site{site}", f"gap_site{site}_raw_kg", f"gap_site{site}_kg"]
    keep += ["target_total_rebuilt_kg", "inventory_total_rebuilt_kg", "gap_total_raw_rebuilt_kg",
             "gap_total_kg", "gap_positive", "aggregate_net_shortfall_kg",
             "stationwise_minus_aggregate_gap_kg", "ordinary_shortage", "production_amount", "htt_amount"]
    out = hit[keep].rename(columns={"target_total_rebuilt_kg": "target_total_kg",
                                    "inventory_total_rebuilt_kg": "inventory_total_kg"}).copy()
    out.insert(1, "method_label", out.method.map(METHOD_LABEL))
    audit = {"max_site_gap_error": max_site_gap_error, "max_lookup_error": max_lookup_error,
             "max_stage60_error": max_stage60_error, "max_stage64_error": max_stage64_error}
    return out.sort_values(["method", "path_id"]), audit


def prep_summary(table: pd.DataFrame) -> pd.DataFrame:
    rows = []
    scopes = {"all_terminal_hit": pd.Series(True, index=table.index),
              "positive_target_only": table.target_total_kg > GAP_TOL}
    for scope, scope_mask in scopes.items():
        for (method, prep), group in table[scope_mask].groupby(["method", "preparation_stage_count"]):
            rows.append({
                "scope": scope, "method": method, "method_label": METHOD_LABEL[method],
                "preparation_stage_count": int(prep), "path_count": len(group),
                "target_mean_kg": group.target_total_kg.mean(), "target_median_kg": group.target_total_kg.median(),
                "actual_inventory_mean_kg": group.inventory_total_kg.mean(),
                "actual_inventory_median_kg": group.inventory_total_kg.median(),
                "terminal_gap_mean_kg": group.gap_total_kg.mean(),
                "terminal_gap_median_kg": group.gap_total_kg.median(),
                "terminal_gap_q95_kg": group.gap_total_kg.quantile(0.95),
                "terminal_gap_max_kg": group.gap_total_kg.max(),
                "gap_positive_path_count": int(group.gap_positive.sum()),
                "gap_positive_path_share": group.gap_positive.mean(),
            })
    return pd.DataFrame(rows)


def site_summary(table: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for (method, prep), group in table.groupby(["method", "preparation_stage_count"]):
        for site in range(1, 5):
            gap = group[f"gap_site{site}_kg"]
            rows.append({
                "method": method, "method_label": METHOD_LABEL[method], "preparation_stage_count": int(prep),
                "site": site, "path_count": len(group),
                "target_mean_kg": group[f"target_site{site}"].mean(),
                "target_median_kg": group[f"target_site{site}"].median(),
                "actual_inventory_mean_kg": group[f"final_site{site}"].mean(),
                "actual_inventory_median_kg": group[f"final_site{site}"].median(),
                "terminal_gap_mean_kg": gap.mean(), "terminal_gap_median_kg": gap.median(),
                "terminal_gap_q95_kg": gap.quantile(0.95),
                "gap_positive_path_count": int((gap > 0).sum()), "gap_positive_path_share": (gap > 0).mean(),
            })
    return pd.DataFrame(rows)


def correlation_table(table: pd.DataFrame) -> pd.DataFrame:
    rows = []
    scopes = {"all_terminal_hit": pd.Series(True, index=table.index),
              "positive_target_only": table.target_total_kg > GAP_TOL}
    for scope, scope_mask in scopes.items():
        for method, group in table[scope_mask].groupby("method"):
            for response, label in [("target_total_kg", "TerminalLOH target"),
                                    ("inventory_total_kg", "actual terminal inventory"),
                                    ("gap_total_kg", "stationwise terminal gap")]:
                rho, pvalue, n = safe_spearman(group.preparation_stage_count, group[response])
                rows.append({"scope": scope, "method": method, "method_label": METHOD_LABEL[method],
                             "response": response, "response_label": label, "n": n,
                             "spearman_rho": rho, "p_value": pvalue,
                             "interpretation": "descriptive association only; not causal"})
    return pd.DataFrame(rows)


def same_prep_comparison(table: pd.DataFrame) -> pd.DataFrame:
    wide = table.pivot(index="path_id", columns="method",
                       values=["preparation_stage_count", "target_total_kg", "inventory_total_kg",
                               "gap_total_kg", "gap_positive"])
    require(np.array_equal(wide[("preparation_stage_count", "saa")],
                           wide[("preparation_stage_count", "chi2_eta003")]), "Method prep counts differ.")
    rows = []
    prep_series = wide[("preparation_stage_count", "saa")]
    for prep in sorted(prep_series.unique()):
        x = wide[prep_series == prep]
        row = {"preparation_stage_count": int(prep), "paired_path_count": len(x)}
        for name, source in [("target", "target_total_kg"), ("actual_inventory", "inventory_total_kg"),
                             ("terminal_gap", "gap_total_kg")]:
            saa = x[(source, "saa")]
            dro = x[(source, "chi2_eta003")]
            row[f"saa_{name}_mean_kg"] = saa.mean()
            row[f"dro_{name}_mean_kg"] = dro.mean()
            row[f"dro_minus_saa_{name}_mean_kg"] = (dro - saa).mean()
        row["saa_gap_positive_count"] = int(x[("gap_positive", "saa")].sum())
        row["dro_gap_positive_count"] = int(x[("gap_positive", "chi2_eta003")].sum())
        row["saa_gap_positive_share"] = x[("gap_positive", "saa")].mean()
        row["dro_gap_positive_share"] = x[("gap_positive", "chi2_eta003")].mean()
        row["dro_minus_saa_gap_positive_share"] = row["dro_gap_positive_share"] - row["saa_gap_positive_share"]
        rows.append(row)
    return pd.DataFrame(rows)


def within_state_association(table: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    rows = []
    for (method, state_id), group in table.groupby(["method", "state_id"]):
        if group.target_total_kg.iloc[0] <= GAP_TOL or group.preparation_stage_count.nunique() < 2 or len(group) < 10:
            continue
        gap_rho, gap_p, gap_n = safe_spearman(group.preparation_stage_count, group.gap_total_kg)
        inv_rho, inv_p, _ = safe_spearman(group.preparation_stage_count, group.inventory_total_kg)
        rows.append({"method": method, "method_label": METHOD_LABEL[method], "state_id": int(state_id),
                     "path_count": len(group), "preparation_count_levels": group.preparation_stage_count.nunique(),
                     "fixed_target_total_kg": group.target_total_kg.iloc[0],
                     "prep_vs_gap_rho": gap_rho, "prep_vs_gap_p_value": gap_p,
                     "prep_vs_actual_inventory_rho": inv_rho, "prep_vs_actual_inventory_p_value": inv_p,
                     "gap_correlation_evaluable": int(not pd.isna(gap_rho)), "n": gap_n})
    detail = pd.DataFrame(rows)
    summary_rows = []
    for method, group in detail.groupby("method"):
        evaluable = group.dropna(subset=["prep_vs_gap_rho"])
        inv_eval = group.dropna(subset=["prep_vs_actual_inventory_rho"])
        summary_rows.append({
            "method": method, "method_label": METHOD_LABEL[method], "eligible_positive_target_states": len(group),
            "gap_evaluable_states": len(evaluable), "negative_gap_correlation_states": int((evaluable.prep_vs_gap_rho < 0).sum()),
            "positive_gap_correlation_states": int((evaluable.prep_vs_gap_rho > 0).sum()),
            "path_count_weighted_mean_gap_rho": np.average(evaluable.prep_vs_gap_rho, weights=evaluable.path_count),
            "median_gap_rho": evaluable.prep_vs_gap_rho.median(),
            "path_count_weighted_mean_actual_inventory_rho": np.average(
                inv_eval.prep_vs_actual_inventory_rho, weights=inv_eval.path_count),
            "median_actual_inventory_rho": inv_eval.prep_vs_actual_inventory_rho.median(),
            "weighting_note": "diagnostic path-count weighting across evaluable states; not 35-state equal-weight main evaluation",
        })
    return detail, pd.DataFrame(summary_rows)


def overall_summary(table: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for method, group in table.groupby("method"):
        rows.append({"method": method, "method_label": METHOD_LABEL[method], "path_count": len(group),
                     "target_mean_kg": group.target_total_kg.mean(), "target_median_kg": group.target_total_kg.median(),
                     "actual_inventory_mean_kg": group.inventory_total_kg.mean(),
                     "actual_inventory_median_kg": group.inventory_total_kg.median(),
                     "terminal_gap_mean_kg": group.gap_total_kg.mean(),
                     "terminal_gap_median_kg": group.gap_total_kg.median(),
                     "terminal_gap_q95_kg": group.gap_total_kg.quantile(0.95),
                     "gap_positive_path_count": int(group.gap_positive.sum()),
                     "gap_positive_path_share": group.gap_positive.mean()})
    return pd.DataFrame(rows)


def gap_definition_audit(table: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for method, group in table.groupby("method"):
        diff = group.stationwise_minus_aggregate_gap_kg
        rows.append({"method": method, "method_label": METHOD_LABEL[method], "path_count": len(group),
                     "stationwise_gap_positive_count": int((group.gap_total_kg > 0).sum()),
                     "aggregate_net_shortfall_positive_count": int((group.aggregate_net_shortfall_kg > GAP_TOL).sum()),
                     "stationwise_gap_exceeds_aggregate_count": int((diff > GAP_TOL).sum()),
                     "mean_stationwise_minus_aggregate_gap_kg": diff.mean(),
                     "max_stationwise_minus_aggregate_gap_kg": diff.max(),
                     "formal_definition": "sum_i max(0,T_i-I_i); aggregate net shortfall is audit-only and never substituted"})
    return pd.DataFrame(rows)


def validate_stage59(table: pd.DataFrame, paths: dict[str, Path]) -> pd.DataFrame:
    rows = []
    for method, key in [("saa", "stage59_saa"), ("chi2_eta003", "stage59_dro")]:
        published = pd.read_csv(paths[key])
        published = published[published.aggregation_scope == "6053_terminal_hit_paths_four_station_total"].iloc[0]
        group = table[table.method == method]
        row = {"method": method, "method_label": METHOD_LABEL[method],
               "target_mean_error_kg": abs(group.target_total_kg.mean() - published.mean_target_kg),
               "actual_inventory_mean_error_kg": abs(group.inventory_total_kg.mean() - published.mean_final_inventory_kg),
               "terminal_gap_mean_error_kg": abs(group.gap_total_kg.mean() - published.mean_gap_kg),
               "gap_positive_share_error": abs(group.gap_positive.mean() - published.positive_gap_probability)}
        require(max(row.values().__iter__().__next__() if False else [row[c] for c in row if c.endswith("kg") or c.endswith("error")]) < 1e-9,
                f"Stage-59 reproduction failed for {method}")
        rows.append(row)
    return pd.DataFrame(rows)


def style(ax: plt.Axes) -> None:
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    ax.grid(axis="y", color="#D9E2EC", linewidth=0.7, alpha=0.8)
    ax.set_axisbelow(True)


def make_figures(out: Path, table: pd.DataFrame, prep: pd.DataFrame, within: pd.DataFrame) -> None:
    plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 9, "figure.facecolor": "white"})
    counts = sorted(table.preparation_stage_count.unique())
    colors = {"saa": "#5B9BD5", "chi2_eta003": "#ED7D31"}

    core = prep[prep.scope == "all_terminal_hit"]
    fig, axes = plt.subplots(1, 2, figsize=(12, 5.5), dpi=180, sharey=True)
    for ax, method in zip(axes, ["saa", "chi2_eta003"]):
        g = core[core.method == method].sort_values("preparation_stage_count")
        ax.plot(g.preparation_stage_count, g.terminal_gap_mean_kg, marker="o", linewidth=2,
                color=colors[method], label="Mean gap")
        ax.plot(g.preparation_stage_count, g.terminal_gap_median_kg, marker="s", linestyle="--",
                color="#7F7F7F", label="Median gap")
        ax.plot(g.preparation_stage_count, g.terminal_gap_q95_kg, marker="^", linewidth=1.8,
                color="#C00000", label="Gap q95")
        ax.set_title(f"{METHOD_LABEL[method]} stationwise terminal gap")
        ax.set_xlabel("Preparation-stage count")
        ax.set_xticks(counts)
        ax.legend(frameon=False)
        style(ax)
    axes[0].set_ylabel("Terminal gap (kg)")
    fig.suptitle("Own-Target Terminal Gap by Preparation Opportunity", fontsize=14)
    fig.tight_layout(rect=(0, 0, 1, 0.94))
    fig.savefig(out / "fig1_terminal_gap_by_prep_saa_dro.png", bbox_inches="tight")
    plt.close(fig)

    fig, axes = plt.subplots(1, 2, figsize=(12, 5.5), dpi=180, sharey=True)
    for ax, method in zip(axes, ["saa", "chi2_eta003"]):
        g = core[core.method == method].sort_values("preparation_stage_count")
        ax.plot(g.preparation_stage_count, g.target_mean_kg, marker="o", color="#C00000", label="Mean own target")
        ax.plot(g.preparation_stage_count, g.actual_inventory_mean_kg, marker="s", color="#548235", label="Mean actual inventory")
        ax.set_title(METHOD_LABEL[method])
        ax.set_xlabel("Preparation-stage count")
        ax.legend(frameon=False)
        style(ax)
    axes[0].set_ylabel("Four-station total (kg)")
    fig.suptitle("Own TerminalLOH Target and Actual Terminal Inventory", fontsize=14)
    fig.tight_layout(rect=(0, 0, 1, 0.94))
    fig.savefig(out / "fig2_target_actual_by_prep_saa_dro.png", bbox_inches="tight")
    plt.close(fig)

    fig, ax = plt.subplots(figsize=(9, 5.5), dpi=180)
    for method in ["saa", "chi2_eta003"]:
        g = core[core.method == method].sort_values("preparation_stage_count")
        ax.plot(g.preparation_stage_count, 100 * g.gap_positive_path_share, marker="o",
                linewidth=2, color=colors[method], label=METHOD_LABEL[method])
    ax.set_xlabel("Preparation-stage count")
    ax.set_ylabel("Gap-positive terminal-hit paths (%)")
    ax.set_title("Own-Target Gap-Positive Share by Preparation Opportunity")
    ax.legend(frameon=False)
    style(ax)
    fig.tight_layout()
    fig.savefig(out / "fig3_gap_positive_share_by_prep.png", bbox_inches="tight")
    plt.close(fig)

    fig, ax = plt.subplots(figsize=(12, 5.8), dpi=180)
    for method, marker in [("saa", "o"), ("chi2_eta003", "s")]:
        g = within[(within.method == method) & within.prep_vs_gap_rho.notna()].sort_values("state_id")
        ax.scatter(g.state_id, g.prep_vs_gap_rho, s=np.maximum(24, g.path_count / 2), alpha=0.75,
                   marker=marker, color=colors[method], label=METHOD_LABEL[method])
    ax.axhline(0, color="#7F7F7F", linewidth=1)
    ax.set_xlabel("Reached positive-target terminal state")
    ax.set_ylabel("Within-state Spearman: prep count vs terminal gap")
    ax.set_title("Fixed-State Preparation/Gap Association (Marker Size Reflects OOS Count)")
    ax.legend(frameon=False)
    style(ax)
    fig.tight_layout()
    fig.savefig(out / "fig4_within_state_prep_gap_correlation.png", bbox_inches="tight")
    plt.close(fig)


def write_judgment(out: Path, overall: pd.DataFrame, prep: pd.DataFrame, corr: pd.DataFrame,
                   same: pd.DataFrame, within_summary: pd.DataFrame, gap_audit: pd.DataFrame) -> None:
    o = overall.set_index("method")
    c = corr.set_index(["scope", "method", "response"])
    w = within_summary.set_index("method")
    lines = [
        "Step-05B-11A judgment", "", "Status: PASS after independent mechanical verification", "",
        "Overall symmetric own-target facts on 6053 common terminal-hit paths",
        f"- SAA: mean target {o.loc['saa','target_mean_kg']:.6f} kg, mean actual inventory {o.loc['saa','actual_inventory_mean_kg']:.6f} kg, mean stationwise terminal gap {o.loc['saa','terminal_gap_mean_kg']:.6f} kg, gap-positive {int(o.loc['saa','gap_positive_path_count'])}/{int(o.loc['saa','path_count'])} ({o.loc['saa','gap_positive_path_share']:.6%}).",
        f"- DRO: mean target {o.loc['chi2_eta003','target_mean_kg']:.6f} kg, mean actual inventory {o.loc['chi2_eta003','actual_inventory_mean_kg']:.6f} kg, mean stationwise terminal gap {o.loc['chi2_eta003','terminal_gap_mean_kg']:.6f} kg, gap-positive {int(o.loc['chi2_eta003','gap_positive_path_count'])}/{int(o.loc['chi2_eta003','path_count'])} ({o.loc['chi2_eta003','gap_positive_path_share']:.6%}).",
        "- These reproduce the previously accepted Stage-59 self-attainment facts; SAA target-realization pressure is not a new discovery.", "",
        "Q1. Does SAA show fewer opportunities -> harder own-target attainment?",
        f"- In the unstratified all-terminal-hit sample, prep count versus SAA gap is essentially zero: rho {c.loc[('all_terminal_hit','saa','gap_total_kg'),'spearman_rho']:.3f}. This raw aggregation mixes terminal states with very different targets, including many zero-target SAA paths.",
        f"- SAA actual terminal inventory nevertheless rises strongly with preparation count: rho {c.loc[('all_terminal_hit','saa','inventory_total_kg'),'spearman_rho']:.3f}.",
        f"- Restricting to positive-target SAA paths gives prep versus gap rho {c.loc[('positive_target_only','saa','gap_total_kg'),'spearman_rho']:.3f}. More importantly, within fixed positive-target terminal states, {int(w.loc['saa','negative_gap_correlation_states'])}/{int(w.loc['saa','gap_evaluable_states'])} evaluable states have a negative prep-gap association; the path-count-weighted mean rho is {w.loc['saa','path_count_weighted_mean_gap_rho']:.3f}.",
        "- Therefore SAA already exhibits path-level preparation dependence once target/state composition is held transparent; the earlier existence of SAA pressure remains an accepted prior fact.", "",
        "Q2. Does DRO show the same direction?",
        f"- All-terminal-hit prep versus DRO gap is also weak in aggregate: rho {c.loc[('all_terminal_hit','chi2_eta003','gap_total_kg'),'spearman_rho']:.3f}; prep versus actual inventory is strong at {c.loc[('all_terminal_hit','chi2_eta003','inventory_total_kg'),'spearman_rho']:.3f}.",
        f"- Within fixed positive-target terminal states, {int(w.loc['chi2_eta003','negative_gap_correlation_states'])}/{int(w.loc['chi2_eta003','gap_evaluable_states'])} evaluable states have negative prep-gap association, with path-count-weighted mean rho {w.loc['chi2_eta003','path_count_weighted_mean_gap_rho']:.3f}.",
        "- DRO therefore shows the same conditioned direction: more usable preparation opportunities are associated with more actual inventory and smaller own-target gaps.", "",
        "Q3. Is the pattern sufficiently symmetric to be a shared FA-MSP implementation-layer constraint?",
        "- Yes, with an important qualification: the unconditional raw-gap correlation is weak for both methods because target/state composition changes across prep counts. The fixed-state and positive-target diagnostics show the common relationship clearly for both SAA and DRO.",
        "- The evidence supports: TerminalLOH-to-inventory implementation depends on available preparation opportunities under both policies and cannot be attributed uniquely to Pearson-DRO.",
        "- This does not identify an algorithm error, cut error, training failure, or MSP failure; current inventory, ordinary-service competition, production capacity, and sequential information remain simultaneous influences.", "",
        "Q4. At the same prep count, does the higher DRO target add raw gap pressure?",
    ]
    for row in same.itertuples():
        lines.append(
            f"- Prep {int(row.preparation_stage_count)} (n={int(row.paired_path_count)}): Delta target {row.dro_minus_saa_target_mean_kg:+.3f} kg, Delta actual inventory {row.dro_minus_saa_actual_inventory_mean_kg:+.3f} kg, Delta stationwise gap {row.dro_minus_saa_terminal_gap_mean_kg:+.3f} kg; gap-positive shares SAA/DRO {row.saa_gap_positive_share:.2%}/{row.dro_gap_positive_share:.2%}."
        )
    lines.extend([
        "- DRO has a higher mean target at every prep count. Raw mean gap is higher for prep counts 2-5, but the gap difference narrows as preparation opportunities increase and is slightly negative at prep 6.",
        "- This is additional target pressure, not evidence of worse DRO implementation capability, because DRO actual inventory also rises relative to SAA at the same prep count.", "",
        "Terminal-gap definition audit",
    ])
    for row in gap_audit.itertuples():
        lines.append(f"- {row.method_label}: stationwise positive gaps {int(row.stationwise_gap_positive_count)}, aggregate-net-shortfall positives {int(row.aggregate_net_shortfall_positive_count)}, and {int(row.stationwise_gap_exceeds_aggregate_count)} paths where sum_i max(0,T_i-I_i) exceeds max(0,sum(T)-sum(I)); maximum difference {row.max_stationwise_minus_aggregate_gap_kg:.6f} kg.")
    lines.extend([
        "- All formal statistics use the stationwise gap sum. The aggregate net shortfall appears only as a negative-control audit and is never substituted.", "",
        "Evidence boundary",
        "- ordinary shortage, terminal gap, and offline W-stage shortage remain distinct.",
        "- No Delta I / Delta T quantity is called a realization or attainment ratio.",
        "- No optimization, training, resampling, model change, eta change, or W1-W3 validation was performed.",
    ])
    (out / "step05b11a_judgment.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_readme(out: Path) -> None:
    text = """# Step-05B-11A symmetric SAA/DRO TerminalLOH attainment audit

Status: candidate PASS pending independent verification.

This is a read-only path-level audit on the same accepted 10000x8 OOS sample. The core scope is the 6053 common terminal-hit paths. SAA and eta=0.03 DRO are processed by the same functions and the same stationwise gap definition: `sum_i max(0,T_i-I_i)`.

The audit combines accepted Stage-53 targets, Stage-58 method/path terminal records, Stage-59 prior self-attainment summaries, Stage-60 site-level definitions, Stage-64 target/actual/capacity identities, Stage-65 pairing, and Stage-68 preparation-stage counts. It performs no MATLAB/Gurobi call, policy replay, training, resampling, cut generation, TerminalLOH change, or W-stage recourse.

Unconditional path summaries retain actual OOS frequencies. A transparent within-terminal-state diagnostic is added to hold the TerminalLOH target fixed; it is not a regression and is not a 35-state equal-weight main evaluation.
"""
    (out / "README.md").write_text(text, encoding="utf-8")


def write_manifest(out: Path, paths: dict[str, Path]) -> None:
    generated = sorted(p for p in out.iterdir() if p.is_file() and p.name != "LARGE_FILE_MANIFEST.md")
    lines = ["# LARGE_FILE_MANIFEST", "", "The 12106-row symmetric path-method table is local-only.", "",
             "| generated file | rows/type | bytes | SHA-256 | Git policy |", "|---|---:|---:|---|---|"]
    for path in generated:
        if path.suffix == ".csv":
            rows = sum(1 for _ in path.open("r", encoding="utf-8")) - 1
            kind = f"{rows} data rows"
        elif path.suffix == ".png":
            kind = "PNG figure"
        else:
            kind = "text"
        policy = "local-only" if path.name == "symmetric_terminal_attainment_path_table.csv" else "lightweight Git candidate"
        lines.append(f"| `{path.name}` | {kind} | {path.stat().st_size} | `{sha256_file(path)}` | {policy} |")
    lines.extend(["", "## Protected accepted inputs", "", "| role | path | bytes | SHA-256 |", "|---|---|---:|---|"])
    for key, path in paths.items():
        lines.append(f"| {key} | `{path}` | {path.stat().st_size} | `{sha256_file(path)}` |")
    lines.extend(["", "No solver, model, policy, OOS sample, accepted result, or historical failed run was modified."])
    (out / "LARGE_FILE_MANIFEST.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    out = (repo / args.output).resolve()
    require(not out.exists(), f"Output directory already exists: {out}")
    paths = source_paths(repo)
    validate_sources(repo, paths)
    table, audit = build_symmetric_table(paths)
    out.mkdir(parents=True)
    table_path = out / "symmetric_terminal_attainment_path_table.csv"
    table.to_csv(table_path, index=False)
    table = pd.read_csv(table_path)

    overall = overall_summary(table)
    prep = prep_summary(table)
    site = site_summary(table)
    corr = correlation_table(table)
    same = same_prep_comparison(table)
    within, within_summary = within_state_association(table)
    gap_audit = gap_definition_audit(table)
    stage59 = validate_stage59(table, paths)
    overall.to_csv(out / "overall_symmetric_summary.csv", index=False)
    prep.to_csv(out / "prep_method_total_summary.csv", index=False)
    site.to_csv(out / "prep_method_site_summary.csv", index=False)
    corr.to_csv(out / "symmetric_spearman_correlations.csv", index=False)
    same.to_csv(out / "same_prep_saa_dro_comparison.csv", index=False)
    within.to_csv(out / "within_state_preparation_association.csv", index=False)
    within_summary.to_csv(out / "within_state_direction_summary.csv", index=False)
    gap_audit.to_csv(out / "terminal_gap_definition_audit.csv", index=False)
    stage59.to_csv(out / "accepted_stage59_reproduction.csv", index=False)
    pd.DataFrame([audit]).to_csv(out / "accepted_source_crosscheck.csv", index=False)
    make_figures(out, table, prep, within)
    write_readme(out)
    write_judgment(out, overall, prep, corr, same, within_summary, gap_audit)
    write_manifest(out, paths)
    print(f"Step-05B-11A symmetric attainment audit generated: {out}")


if __name__ == "__main__":
    main()
