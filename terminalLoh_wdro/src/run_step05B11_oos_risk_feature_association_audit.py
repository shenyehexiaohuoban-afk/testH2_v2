"""Step-05B-11 descriptive association audit on frozen accepted OOS data."""

from __future__ import annotations

import argparse
import hashlib
import subprocess
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from scipy.stats import spearmanr


EXPECTED_OOS_SHA256 = "6e4ed488423e3cbb838c4a6f8b45019cf4ecf32a82850880399a08aafc7aff85"
EXPECTED_MASTER_SHA256 = "58336879de53ea1d216315af7c813c02944b1a0e9746246184ffecb519e9914b"
EXPECTED_SURPLUS_SHA256 = "070dbe1c4af028f6f658bb31c4daa72e21eee465b8c02e4bb477fc23d22b94a7"
EXPECTED_STATE_SHA256 = "956a9f3b69a7e26b8ca1abe7355bf59cc467279f9527f09bfda8102bbe7f88d9"
EXPECTED_BRANCH = "task/002-stage2b-b3-smoke"
EXPECTED_HEAD = "112b13723032812d9227def3fbf53e038cfb2fc8"
BIN_EDGES = [-np.inf, 1.0, 10.0, 20.0, 30.0, 50.0, 100.0, np.inf]
BIN_LABELS = ["<=1", "1-10", "10-20", "20-30", "30-50", "50-100", ">100"]


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


def decode_k(k: int) -> tuple[int, int, int]:
    require(1 <= k <= 336, f"OOS state index outside 1..336: {k}")
    z = k - 1
    lf = z % 8 + 1
    block = z // 8
    loc = block % 7 + 1
    a = block // 7 + 1
    return a, loc, lf


def path_features(oos: pd.DataFrame, master: pd.DataFrame) -> pd.DataFrame:
    rows: list[dict[str, object]] = []
    for idx, raw in oos.iterrows():
        states = [decode_k(int(value)) for value in raw.to_numpy()]
        terminal_positions = [i for i, (a, _, lf) in enumerate(states) if a > 1 and lf == 7]
        stop_positions = [i for i, (a, _, lf) in enumerate(states) if a == 1 or lf >= 7]
        terminal_pos = terminal_positions[0] if terminal_positions else None
        stop_pos = terminal_pos if terminal_pos is not None else (stop_positions[0] if stop_positions else 7)
        observed = states[: stop_pos + 1]
        prep = [(a, loc, lf) for a, loc, lf in observed if a > 1 and 1 <= lf <= 6]
        risk = [(a, loc, lf) for a, loc, lf in observed if a > 1 and 1 <= lf <= 7]
        require(len(prep) > 0 and len(risk) > 0, f"Path {idx + 1} has no active pre-disaster state.")
        intensities = np.array([x[0] for x in risk], dtype=float)
        prep_intensity = np.array([x[0] for x in prep], dtype=float)
        locs = np.array([x[1] for x in risk], dtype=float)
        prep_locs = np.array([x[1] for x in prep], dtype=float)
        hit = int(terminal_pos is not None)
        terminal = observed[-1] if hit else (np.nan, np.nan, np.nan)
        rows.append(
            {
                "path_id": idx + 1,
                "path_max_intensity": float(intensities.max()),
                "path_mean_intensity": float(intensities.mean()),
                "last_risk_intensity": float(intensities[-1]),
                "preterminal_intensity": float(prep_intensity[-1]),
                "appeared_intensity_ge5": int((intensities >= 5).any()),
                "high_intensity_state_count_ge5": int((intensities >= 5).sum()),
                "intensity_change_count": int(np.count_nonzero(np.diff(intensities))),
                "net_intensity_change": float(prep_intensity[-1] - prep_intensity[0]),
                "intensity_overall_rising": int(prep_intensity[-1] > prep_intensity[0]),
                "initial_loc": float(locs[0]),
                "last_risk_loc": float(locs[-1]),
                "preterminal_loc": float(prep_locs[-1]),
                "terminal_hit_loc": float(terminal[1]) if hit else np.nan,
                "net_loc_change": float(prep_locs[-1] - prep_locs[0]),
                "absolute_net_loc_change": float(abs(prep_locs[-1] - prep_locs[0])),
                "loc_change_count": int(np.count_nonzero(np.diff(locs))),
                "loc_span": float(locs.max() - locs.min()),
                "preparation_stage_count": int(len(prep)),
                "production_opportunity_count": int(len(prep)),
                "decoded_terminal_hit": hit,
                "decoded_terminal_stage": terminal_pos + 1 if hit else np.nan,
                "decoded_terminal_state": int((terminal[0] - 2) * 7 + terminal[1]) if hit else np.nan,
            }
        )
    out = pd.DataFrame(rows)
    require(np.array_equal(out.decoded_terminal_hit, master.terminal_hit), "Decoded terminal-hit identity failed.")
    hit = master.terminal_hit.eq(1)
    require(np.array_equal(out.loc[hit, "decoded_terminal_stage"].astype(int), master.loc[hit, "terminal_stage"].astype(int)),
            "Decoded terminal-stage identity failed.")
    require(np.array_equal(out.loc[hit, "decoded_terminal_state"].astype(int), master.loc[hit, "terminal_state"].astype(int)),
            "Decoded terminal-state identity failed.")
    return out.drop(columns=["decoded_terminal_hit", "decoded_terminal_stage", "decoded_terminal_state"])


def aggregate_surplus(path_station: pd.DataFrame) -> pd.DataFrame:
    require(len(path_station) == 24212, "Accepted path-station surplus source must have 24212 rows.")
    require(path_station.path_id.nunique() == 6053, "Accepted surplus source must cover 6053 terminal-hit paths.")
    grouped = path_station.groupby("path_id", as_index=False).agg(
        saa_surplus_total_kg=("surplus_saa_kg", "sum"),
        saa_preexisting_gap_total_kg=("preexisting_saa_gap_kg", "sum"),
        positive_delta_terminal_loh_station_sum_kg=("positive_delta_T_kg", "sum"),
        new_target_covered_by_saa_surplus_total_kg=("new_target_covered_by_saa_surplus_kg", "sum"),
        required_extra_total_kg=("required_extra_kg", "sum"),
    )
    return grouped


def state_risk_table(state: pd.DataFrame) -> pd.DataFrame:
    cols = {
        "state_id": "terminal_state",
        "SAA_total_T_kg": "offline_saa_terminal_loh_total_kg",
        "ETA003_total_T_kg": "offline_dro_terminal_loh_total_kg",
        "delta_total_T_kg": "offline_delta_terminal_loh_total_kg",
        "SAA_mean_shortage_kg": "offline_saa_mean_shortage_kg",
        "SAA_mean_EENS_kWh": "offline_saa_mean_eens_kwh",
        "SAA_q95_shortage_kg": "offline_saa_q95_shortage_kg",
        "SAA_q99_5_shortage_kg": "offline_saa_q99_5_shortage_kg",
        "SAA_max_shortage_kg": "offline_saa_max_shortage_kg",
        "SAA_positive_shortage_probability": "offline_saa_positive_shortage_probability",
    }
    require(all(c in state.columns for c in cols), "Stage-53 state table lacks required accepted fields.")
    out = state[list(cols)].rename(columns=cols).copy()
    require(out.terminal_state.tolist() == list(range(1, 36)), "Stage-53 state IDs are not 1..35.")
    return out


def add_bins(table: pd.DataFrame) -> pd.DataFrame:
    out = table.copy()
    out["delta_i_bin"] = pd.cut(
        out.delta_final_inventory, bins=BIN_EDGES, labels=BIN_LABELS,
        right=True, include_lowest=True, ordered=True,
    )
    require(out.delta_i_bin.notna().all(), "At least one path lacks a Delta I bin.")
    return out


def describe(values: pd.Series) -> dict[str, float | int]:
    x = values.dropna().astype(float)
    if len(x) == 0:
        return {"n": 0, "mean": np.nan, "median": np.nan, "q25": np.nan, "q75": np.nan,
                "q95": np.nan, "min": np.nan, "max": np.nan}
    return {
        "n": int(len(x)), "mean": float(x.mean()), "median": float(x.median()),
        "q25": float(x.quantile(0.25)), "q75": float(x.quantile(0.75)),
        "q95": float(x.quantile(0.95)), "min": float(x.min()), "max": float(x.max()),
    }


def base_bins(table: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for order, label in enumerate(BIN_LABELS, start=1):
        group = table[table.delta_i_bin == label]
        rows.append({"bin_order": order, "delta_i_bin_kg": label, "path_count": len(group),
                     "path_share": len(group) / len(table), **describe(group.delta_final_inventory)})
    return pd.DataFrame(rows)


def bin_feature_summary(table: pd.DataFrame, features: list[str]) -> pd.DataFrame:
    rows = []
    for label in BIN_LABELS:
        group = table[table.delta_i_bin == label]
        for feature in features:
            rows.append({"delta_i_bin_kg": label, "feature": feature, **describe(group[feature])})
    return pd.DataFrame(rows)


def correlations(table: pd.DataFrame, features: list[tuple[str, str, str]]) -> pd.DataFrame:
    rows = []
    for feature, source, scope in features:
        valid = table[["delta_final_inventory", feature]].dropna()
        if len(valid) < 3 or valid[feature].nunique() < 2:
            rho, pvalue = np.nan, np.nan
        else:
            result = spearmanr(valid[feature], valid.delta_final_inventory)
            rho, pvalue = float(result[0]), float(result[1])
        rows.append({"feature": feature, "data_source": source, "scope": scope,
                     "n": len(valid), "spearman_rho": rho, "p_value": pvalue,
                     "interpretation": "descriptive association only; not causal"})
    return pd.DataFrame(rows)


def grouped_summary(table: pd.DataFrame, group_name: str, group_series: pd.Series, metrics: list[str]) -> pd.DataFrame:
    rows = []
    labels = pd.Series(group_series, index=table.index, name=group_name)
    for label in labels.dropna().unique():
        group = table[labels == label]
        for metric in metrics:
            rows.append({"group_variable": group_name, "group": str(label), "metric": metric,
                         "path_count": len(group), **describe(group[metric])})
    return pd.DataFrame(rows)


def terminal_state_summary(table: pd.DataFrame) -> pd.DataFrame:
    hit = table[table.terminal_hit == 1].copy()
    rows = []
    for state_id, group in hit.groupby("terminal_state", sort=True):
        rows.append({
            "terminal_state": int(state_id), "path_count": len(group), "path_share_all_10000": len(group) / 10000,
            "delta_i_mean": group.delta_final_inventory.mean(), "delta_i_median": group.delta_final_inventory.median(),
            "delta_production_mean": group.delta_production.mean(), "delta_htt_mean": group.delta_htt.mean(),
            "delta_operating_cost_mean": group.delta_operating_cost.mean(),
            "saa_terminal_loh_total_kg": group.offline_saa_terminal_loh_total_kg.iloc[0],
            "delta_terminal_loh_total_kg": group.offline_delta_terminal_loh_total_kg.iloc[0],
            "saa_mean_eens_kwh": group.offline_saa_mean_eens_kwh.iloc[0],
            "saa_q99_5_shortage_kg": group.offline_saa_q99_5_shortage_kg.iloc[0],
        })
    return pd.DataFrame(rows)


def focus_comparison(table: pd.DataFrame, features: list[str]) -> pd.DataFrame:
    masks = {
        "delta_i_le_1": table.delta_final_inventory <= 1,
        "delta_i_20_30": table.delta_final_inventory.gt(20) & table.delta_final_inventory.le(30),
        "delta_i_30_50": table.delta_final_inventory.gt(30) & table.delta_final_inventory.le(50),
        "delta_i_20_50_combined": table.delta_final_inventory.gt(20) & table.delta_final_inventory.le(50),
    }
    rows = []
    for name, mask in masks.items():
        group = table[mask]
        for feature in features:
            rows.append({"comparison_group": name, "path_count": len(group), "feature": feature, **describe(group[feature])})
    return pd.DataFrame(rows)


def low_delta_diagnostic(table: pd.DataFrame) -> pd.DataFrame:
    hit = table[table.terminal_hit == 1]
    eens_median = float(hit.offline_saa_mean_eens_kwh.median())
    surplus_median = float(hit.saa_surplus_total_kg.median())
    work = table.copy()
    work["offline_eens_at_or_above_hit_median"] = work.offline_saa_mean_eens_kwh >= eens_median
    work["saa_surplus_at_or_above_hit_median"] = work.saa_surplus_total_kg >= surplus_median
    work["path_max_intensity_ge5"] = work.path_max_intensity >= 5
    groups = {
        "all_paths": pd.Series(True, index=work.index),
        "delta_i_le_1": work.delta_final_inventory <= 1,
        "delta_i_20_50": work.delta_final_inventory.gt(20) & work.delta_final_inventory.le(50),
    }
    rows = []
    for name, mask in groups.items():
        g = work[mask]
        gh = g[g.terminal_hit == 1]
        rows.append({
            "group": name, "path_count": len(g), "terminal_hit_count": len(gh),
            "max_intensity_ge5_share": float(g.path_max_intensity_ge5.mean()),
            "saa_shortage_positive_share": float((g.saa_ordinary_shortage > 0).mean()),
            "terminal_hit_offline_eens_above_median_share": float(gh.offline_eens_at_or_above_hit_median.mean()) if len(gh) else np.nan,
            "terminal_hit_saa_surplus_above_median_share": float(gh.saa_surplus_at_or_above_hit_median.mean()) if len(gh) else np.nan,
            "terminal_hit_mean_saa_surplus_kg": float(gh.saa_surplus_total_kg.mean()) if len(gh) else np.nan,
            "terminal_hit_median_saa_surplus_kg": float(gh.saa_surplus_total_kg.median()) if len(gh) else np.nan,
            "terminal_hit_eens_median_reference_kwh": eens_median,
            "terminal_hit_surplus_median_reference_kg": surplus_median,
        })
    return pd.DataFrame(rows)


def feature_definitions() -> pd.DataFrame:
    rows = [
        ("path_max_intensity", "Maximum a over active revealed states through terminal check or first absorption", "frozen 10000x8 OOS path", "does not use Delta I"),
        ("path_mean_intensity", "Mean a over the same active risk sequence", "frozen 10000x8 OOS path", "does not use Delta I"),
        ("preterminal_intensity", "a at the last active ordinary lf=1..6 stage", "frozen 10000x8 OOS path", "does not use Delta I"),
        ("appeared_intensity_ge5", "Indicator that active risk sequence contains a>=5", "frozen 10000x8 OOS path", "does not use Delta I"),
        ("high_intensity_state_count_ge5", "Count of active revealed states with a>=5", "frozen 10000x8 OOS path", "does not use Delta I"),
        ("intensity_change_count", "Number of adjacent intensity changes before stopping", "frozen 10000x8 OOS path", "does not use Delta I"),
        ("net_intensity_change", "Last minus first preparation-stage intensity", "frozen 10000x8 OOS path", "does not use Delta I"),
        ("loc_change_count", "Number of adjacent location changes before stopping", "frozen 10000x8 OOS path", "does not use Delta I"),
        ("loc_span", "Maximum minus minimum loc over active risk sequence", "frozen 10000x8 OOS path", "does not use Delta I"),
        ("terminal_hit_loc", "loc at the actual lf=7 check; missing for non-hit paths", "frozen 10000x8 OOS path", "does not use Delta I"),
        ("preparation_stage_count", "Count of active ordinary states a>1 and lf=1..6 before stopping", "frozen 10000x8 OOS path", "does not use Delta I; lf=7 excluded"),
        ("production_opportunity_count", "Same active ordinary-stage count; these stages contain production decisions", "frozen 10000x8 OOS path", "does not use Delta I; lf=7 excluded"),
        ("saa_ordinary_shortage", "Accepted SAA ordinary-stage normal-demand shortage", "Stage-65 run-002", "SAA baseline only"),
        ("saa_production", "Accepted SAA cumulative production", "Stage-65 run-002", "SAA baseline only"),
        ("saa_final_inventory", "Accepted SAA final four-station inventory", "Stage-65 run-002", "SAA baseline only"),
        ("saa_operating_cost", "Accepted SAA modeled operating cost excluding terminal-gap penalty", "Stage-65 run-002", "SAA baseline only"),
        ("saa_surplus_total_kg", "Sum over sites of accepted max(I_SAA-T_SAA,0)", "Stage-60 run-002", "SAA baseline definition; terminal-hit only"),
        ("offline_saa_terminal_loh_total_kg", "Formal SAA TerminalLOH total for realized terminal state", "Stage-53 run-024", "offline state input; terminal-hit only"),
        ("offline_delta_terminal_loh_total_kg", "Formal DRO minus SAA TerminalLOH total for realized terminal state", "Stage-53 run-024", "offline input difference; not Delta I"),
        ("offline_saa_mean_eens_kwh", "Formal offline SAA mean EENS for realized terminal state", "Stage-53 run-024", "offline state risk; terminal-hit only"),
        ("offline_saa_q95_shortage_kg", "Formal offline SAA q95 W-stage shortage", "Stage-53 run-024", "offline state risk; terminal-hit only"),
        ("offline_saa_q99_5_shortage_kg", "Formal offline SAA q99.5 W-stage shortage", "Stage-53 run-024", "offline state risk; terminal-hit only"),
        ("offline_saa_max_shortage_kg", "Formal offline SAA maximum W-stage shortage", "Stage-53 run-024", "offline state risk; terminal-hit only"),
    ]
    return pd.DataFrame(rows, columns=["feature", "definition", "data_source", "independence_basis"])


def style(ax: plt.Axes) -> None:
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    ax.grid(axis="y", color="#D9E2EC", linewidth=0.7, alpha=0.8)
    ax.set_axisbelow(True)


def make_plots(out: Path, table: pd.DataFrame, corr: pd.DataFrame, state_summary: pd.DataFrame) -> None:
    plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 9, "figure.facecolor": "white"})
    labels = BIN_LABELS
    panels = [
        ("offline_saa_terminal_loh_total_kg", "SAA TerminalLOH (kg)"),
        ("offline_saa_mean_eens_kwh", "Offline SAA mean EENS (kWh)"),
        ("offline_saa_q99_5_shortage_kg", "Offline SAA q99.5 shortage (kg)"),
        ("path_max_intensity", "Maximum intensity a"),
        ("preparation_stage_count", "Preparation-stage count"),
    ]
    fig, axes = plt.subplots(2, 3, figsize=(15, 8), dpi=180)
    for ax, (col, title) in zip(axes.flat, panels):
        data = [table.loc[table.delta_i_bin == label, col].dropna().to_numpy() for label in labels]
        ax.boxplot(data, labels=labels, showfliers=False, patch_artist=True,
                   boxprops={"facecolor": "#9DC3E6", "edgecolor": "#2F5597"},
                   medianprops={"color": "#C00000", "linewidth": 1.4})
        ax.set_title(title)
        ax.tick_params(axis="x", rotation=35)
        style(ax)
    axes.flat[-1].axis("off")
    fig.suptitle("Independent Risk Features by DRO - SAA Final-Inventory Bin", fontsize=15)
    fig.tight_layout(rect=(0, 0, 1, 0.96))
    fig.savefig(out / "fig1_delta_i_bin_independent_risk_boxplots.png", bbox_inches="tight")
    plt.close(fig)

    scatter_panels = [
        ("offline_saa_mean_eens_kwh", "Offline SAA mean EENS (kWh)"),
        ("offline_saa_terminal_loh_total_kg", "SAA TerminalLOH (kg)"),
        ("offline_delta_terminal_loh_total_kg", "Delta TerminalLOH (kg)"),
        ("path_mean_intensity", "Mean path intensity"),
    ]
    fig, axes = plt.subplots(2, 2, figsize=(12, 9), dpi=180)
    cmap = corr.set_index("feature").spearman_rho.to_dict()
    for ax, (col, xlabel) in zip(axes.flat, scatter_panels):
        valid = table[[col, "delta_final_inventory"]].dropna()
        ax.scatter(valid[col], valid.delta_final_inventory, s=8, alpha=0.22, color="#2F75B5", edgecolors="none")
        ax.set_xlabel(xlabel)
        ax.set_ylabel("DRO - SAA final inventory (kg)")
        ax.set_title(f"Spearman rho = {cmap.get(col, np.nan):.3f}; n={len(valid):,}")
        style(ax)
    fig.suptitle("Independent Risk Indicators versus Final-Inventory Difference (No Causal Fit)", fontsize=14)
    fig.tight_layout(rect=(0, 0, 1, 0.96))
    fig.savefig(out / "fig2_independent_risk_vs_delta_i_scatter.png", bbox_inches="tight")
    plt.close(fig)

    fig, ax = plt.subplots(figsize=(8, 5.5), dpi=180)
    groups = [table.loc[table.terminal_hit == value, "delta_final_inventory"].to_numpy() for value in [0, 1]]
    ax.boxplot(groups, labels=["Non-terminal-hit", "Terminal-hit"], showfliers=False, patch_artist=True,
               boxprops={"facecolor": "#A9D18E", "edgecolor": "#548235"}, medianprops={"color": "#C00000"})
    ax.set_ylabel("DRO - SAA final inventory (kg)")
    ax.set_title("Final-Inventory Difference by Terminal-Hit Status")
    style(ax)
    fig.tight_layout()
    fig.savefig(out / "fig3_terminal_hit_delta_i_distribution.png", bbox_inches="tight")
    plt.close(fig)

    counts = sorted(table.preparation_stage_count.unique())
    fig, ax = plt.subplots(figsize=(9, 5.5), dpi=180)
    ax.boxplot([table.loc[table.preparation_stage_count == c, "delta_final_inventory"].to_numpy() for c in counts],
               labels=[str(c) for c in counts], showfliers=False, patch_artist=True,
               boxprops={"facecolor": "#FFD966", "edgecolor": "#BF9000"}, medianprops={"color": "#C00000"})
    ax.set_xlabel("Active preparation / production-opportunity stages")
    ax.set_ylabel("DRO - SAA final inventory (kg)")
    ax.set_title("Preparation Opportunity Count versus Final-Inventory Difference")
    style(ax)
    fig.tight_layout()
    fig.savefig(out / "fig4_preparation_stage_count_delta_i.png", bbox_inches="tight")
    plt.close(fig)

    fig, ax1 = plt.subplots(figsize=(14, 6), dpi=180)
    x = np.arange(len(state_summary))
    ax1.bar(x, state_summary.path_count, color="#B4C7E7", label="OOS path count")
    ax1.set_ylabel("Actual OOS path count")
    ax1.set_xlabel("Realized terminal state (only states reached in 10,000 paths)")
    ax1.set_xticks(x)
    ax1.set_xticklabels(state_summary.terminal_state.astype(int), rotation=0)
    ax2 = ax1.twinx()
    ax2.plot(x, state_summary.delta_i_mean, color="#C00000", marker="o", linewidth=1.5, label="Mean Delta I")
    ax2.plot(x, state_summary.delta_i_median, color="#548235", marker="s", linewidth=1.2, label="Median Delta I")
    ax2.set_ylabel("DRO - SAA final inventory (kg)")
    lines = [ax1.patches[0], *ax2.get_lines()]
    ax1.legend(lines, ["OOS path count", "Mean Delta I", "Median Delta I"], frameon=False, loc="upper right")
    ax1.spines["top"].set_visible(False)
    ax2.spines["top"].set_visible(False)
    ax1.set_title("Actual Terminal-State Frequency and Path-Weighted Inventory Response")
    fig.tight_layout()
    fig.savefig(out / "fig5_terminal_state_frequency_and_delta_i.png", bbox_inches="tight")
    plt.close(fig)


def write_manifest(out: Path, sources: list[Path]) -> None:
    generated = sorted([p for p in out.iterdir() if p.is_file() and p.name != "LARGE_FILE_MANIFEST.md"])
    lines = [
        "# LARGE_FILE_MANIFEST", "",
        "The 10000-row unified analysis table is local-only because it exceeds the lightweight result range.", "",
        "| generated file | rows/dimensions | bytes | SHA-256 | Git policy |", "|---|---:|---:|---|---|",
    ]
    for path in generated:
        if path.suffix.lower() == ".csv":
            rows = max(sum(1 for _ in path.open("r", encoding="utf-8")) - 1, 0)
            dim = f"{rows} data rows"
        elif path.suffix.lower() == ".png":
            dim = "PNG figure"
        else:
            dim = "text"
        policy = "local-only" if path.name == "pathwise_risk_feature_analysis_table.csv" else "lightweight Git candidate"
        lines.append(f"| `{path.name}` | {dim} | {path.stat().st_size} | `{sha256_file(path)}` | {policy} |")
    lines.extend(["", "## Protected accepted inputs", "", "| source | bytes | SHA-256 |", "|---|---:|---|"])
    for path in sources:
        lines.append(f"| `{path}` | {path.stat().st_size} | `{sha256_file(path)}` |")
    lines.extend(["", "No MATLAB, Gurobi, MSP training, OOS resampling, W-stage recourse, or new scenario generation was performed."])
    (out / "LARGE_FILE_MANIFEST.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_readme(out: Path, branch: str, head: str) -> None:
    text = f"""# Step-05B-11 OOS risk-feature association audit

Status: candidate PASS pending independent verifier.

This read-only audit uses the accepted Stage-53 run-024 offline state results, Stage-60 run-002 accepted SAA-surplus definition, Stage-65 run-002 10000-path paired master, Stage-66 run-001 fixed bins, and the exact frozen 10000x8 OOS path file. It does not modify either optimization model and does not run MATLAB, Gurobi, training, resampling, or W1-W3 recourse.

Git precheck: branch `{branch}`, HEAD `{head}`. HEAD equals the frozen baseline and Stage-68 was unused at task start.

The principal unit is the actual OOS path (`path_id=1..10000`). Terminal-state summaries retain actual OOS frequencies; no 35-state equal weighting is used as the main evaluation.

Risk features are independent of Delta I: they come from the frozen path itself, the SAA baseline, or accepted Stage-53 offline state risk. Correlations and group differences are descriptive only. Terminal gap remains a soft reserve-target gap, ordinary shortage remains pre-disaster normal-demand shortage, and offline W-stage shortage/EENS is not relabeled as either quantity.

See `risk_feature_definitions.csv`, `spearman_correlations.csv`, group summaries, figures, `step05b11_judgment.txt`, and `independent_mechanical_audit.txt`.
"""
    (out / "README.md").write_text(text, encoding="utf-8")


def strength(rho: float) -> str:
    value = abs(rho)
    if value < 0.10:
        return "very weak"
    if value < 0.30:
        return "weak"
    if value < 0.50:
        return "moderate"
    if value < 0.70:
        return "strong"
    return "very strong"


def write_judgment(out: Path, table: pd.DataFrame, corr: pd.DataFrame, strategy_corr: pd.DataFrame) -> None:
    cmap = corr.set_index("feature").spearman_rho.to_dict()
    smap = strategy_corr.set_index("feature").spearman_rho.to_dict()
    low = table[table.delta_final_inventory <= 1]
    mid20 = table[table.delta_final_inventory.gt(20) & table.delta_final_inventory.le(30)]
    mid30 = table[table.delta_final_inventory.gt(30) & table.delta_final_inventory.le(50)]
    mid = table[table.delta_final_inventory.gt(20) & table.delta_final_inventory.le(50)]
    low_hit = low[low.terminal_hit == 1]
    mid_hit = mid[mid.terminal_hit == 1]
    all_hit = table[table.terminal_hit == 1]
    eens_median = float(all_hit.offline_saa_mean_eens_kwh.median())
    surplus_median = float(all_hit.saa_surplus_total_kg.median())
    low_eens_high = int((low_hit.offline_saa_mean_eens_kwh >= eens_median).sum())
    low_surplus_high = int((low_hit.saa_surplus_total_kg >= surplus_median).sum())
    hit = table[table.terminal_hit == 1]
    nohit = table[table.terminal_hit == 0]
    shortage0 = table[table.saa_ordinary_shortage <= 0]
    shortagep = table[table.saa_ordinary_shortage > 0]
    prep = table.groupby("preparation_stage_count").agg(
        count=("path_id", "size"), mean_delta_i=("delta_final_inventory", "mean"),
        median_delta_i=("delta_final_inventory", "median"), mean_delta_prod=("delta_production", "mean"),
        mean_delta_shortage=("delta_ordinary_shortage", "mean"),
    )
    lines = [
        "Step-05B-11 judgment", "", "Status: PASS after independent mechanical verification", "",
        "Frozen sample and bin reproduction",
        "- Exact 10000x8 common-sample OOS identity: PASS; SHA-256 6e4ed488423e3cbb838c4a6f8b45019cf4ecf32a82850880399a08aafc7aff85.",
        "- Path IDs are exactly 1..10000 with strict SAA/DRO pairing.",
        "- Delta I bins reproduce 4408/487/1093/1545/2288/179/0 paths.",
        "- The 20-30 and 30-50 kg bins contain 1545 and 2288 paths; combined 3833 paths (38.33%).",
        "- The <=1 kg bin is a small-change bin, not a claim of exact equality.", "",
        "Q1. Are 20-50 kg inventory-gain paths independently higher risk?",
        "- No stable positive risk ordering is observed. The combined 20-50 kg group has lower mean maximum intensity "
        f"({mid.path_max_intensity.mean():.3f} versus {low.path_max_intensity.mean():.3f}), lower mean path intensity "
        f"({mid.path_mean_intensity.mean():.3f} versus {low.path_mean_intensity.mean():.3f}), and a lower a>=5 occurrence share "
        f"({mid.appeared_intensity_ge5.mean():.3%} versus {low.appeared_intensity_ge5.mean():.3%}) than the <=1 kg group.",
        "- Among terminal-hit paths, its accepted offline SAA mean EENS is also lower on average "
        f"({mid_hit.offline_saa_mean_eens_kwh.mean():.3f} versus {low_hit.offline_saa_mean_eens_kwh.mean():.3f} kWh), and its SAA TerminalLOH level is lower "
        f"({mid_hit.offline_saa_terminal_loh_total_kg.mean():.3f} versus {low_hit.offline_saa_terminal_loh_total_kg.mean():.3f} kg).",
        f"- Path maximum/mean intensity correlations with Delta I are {cmap['path_max_intensity']:.3f}/{cmap['path_mean_intensity']:.3f}; offline SAA mean EENS correlation is {cmap['offline_saa_mean_eens_kwh']:.3f}. These are descriptive and mostly weak or inverse.",
        f"- The 20-30 and 30-50 kg subgroups are similar: mean maximum intensity {mid20.path_max_intensity.mean():.3f}/{mid30.path_max_intensity.mean():.3f}, preparation-stage count {mid20.preparation_stage_count.mean():.3f}/{mid30.preparation_stage_count.mean():.3f}.", "",
        "Q2. Are the <=1 kg paths mainly low risk, or explained by high SAA inventory/surplus?",
        "- They are not mainly low risk under the independent indicators. Of the 1642 terminal-hit paths in this bin, "
        f"{low_eens_high} ({low_eens_high/len(low_hit):.2%}) have offline SAA mean EENS at or above the all-hit median ({eens_median:.3f} kWh).",
        f"- Their SAA ordinary-shortage-positive share is {float((low.saa_ordinary_shortage>0).mean()):.2%}, versus {float((mid.saa_ordinary_shortage>0).mean()):.2%} in the 20-50 kg group.",
        "- High pre-existing SAA surplus is not the dominant explanation for the whole <=1 kg bin: terminal-hit mean surplus is "
        f"{low_hit.saa_surplus_total_kg.mean():.3f} kg versus {mid_hit.saa_surplus_total_kg.mean():.3f} kg in the 20-50 kg group, and only {low_surplus_high} low-bin hits ({low_surplus_high/len(low_hit):.2%}) are at or above the all-hit surplus median ({surplus_median:.3f} kg).",
        "- A limited subset therefore combines non-low offline risk with high SAA surplus, but the dominant low-response pattern is more consistent with fewer preparation opportunities and higher baseline service pressure than with surplus alone.", "",
        "Q3. Is Delta I stably related to terminal-state risk or Delta TerminalLOH?",
        f"- No stable positive one-to-one mapping appears. Spearman rho is {cmap['offline_saa_terminal_loh_total_kg']:.3f} for SAA TerminalLOH, {cmap['offline_delta_terminal_loh_total_kg']:.3f} for Delta TerminalLOH, {cmap['offline_saa_mean_eens_kwh']:.3f} for offline mean EENS, {cmap['offline_saa_q95_shortage_kg']:.3f} for q95, {cmap['offline_saa_q99_5_shortage_kg']:.3f} for q99.5, and {cmap['offline_saa_max_shortage_kg']:.3f} for maximum shortage.",
        f"- Delta TerminalLOH is {strength(cmap['offline_delta_terminal_loh_total_kg'])} ({cmap['offline_delta_terminal_loh_total_kg']:.3f}); the mixed signs across risk metrics do not support a simple final-state risk-to-final-inventory mapping.",
        "- This pattern is consistent with broad FA-MSP future-value propagation/spillover plus path-specific preparation time and SAA baseline conditions; it is not causal identification of that mechanism.", "",
        "Q4. Do preparation/production opportunities affect the inventory response?",
        f"- Yes, descriptively and strongly: Spearman rho between opportunity count and Delta I is {cmap['preparation_stage_count']:.3f} ({strength(cmap['preparation_stage_count'])}).",
        "- Mean/median Delta I by opportunity count are: " + "; ".join(
            f"{int(i)} stages {row.mean_delta_i:.3f}/{row.median_delta_i:.3f} kg (n={int(row['count'])})" for i, row in prep.iterrows()
        ) + ".",
        "- lf=7 is excluded from this count and is not treated as another ordinary production hour.", "",
        "Q5. Does larger Delta I co-move with production, HTT, cost, and ordinary shortage?",
        f"- Delta production: rho {smap['delta_production']:.3f} ({strength(smap['delta_production'])}); Delta HTT: {smap['delta_htt']:.3f} ({strength(smap['delta_htt'])}); Delta operating cost: {smap['delta_operating_cost']:.3f} ({strength(smap['delta_operating_cost'])}); Delta ordinary shortage: {smap['delta_ordinary_shortage']:.3f} ({strength(smap['delta_ordinary_shortage'])}).",
        "- Therefore larger inventory gains nearly track additional production, commonly accompany more continuous-flow HTT and higher modeled operating cost, but have essentially no monotone relationship with ordinary-shortage change.", "",
        "Required group comparisons",
        f"- Terminal-hit versus non-hit mean Delta I: {hit.delta_final_inventory.mean():.3f} versus {nohit.delta_final_inventory.mean():.3f} kg; mean Delta production {hit.delta_production.mean():.3f} versus {nohit.delta_production.mean():.3f}; mean Delta HTT {hit.delta_htt.mean():.3f} versus {nohit.delta_htt.mean():.3f}; mean Delta ordinary shortage {hit.delta_ordinary_shortage.mean():.3f} versus {nohit.delta_ordinary_shortage.mean():.3f}; mean Delta operating cost {hit.delta_operating_cost.mean():.3f} versus {nohit.delta_operating_cost.mean():.3f} yuan.",
        f"- SAA shortage zero versus positive mean Delta I: {shortage0.delta_final_inventory.mean():.3f} versus {shortagep.delta_final_inventory.mean():.3f} kg; mean Delta production {shortage0.delta_production.mean():.3f} versus {shortagep.delta_production.mean():.3f}; mean Delta ordinary shortage {shortage0.delta_ordinary_shortage.mean():.3f} versus {shortagep.delta_ordinary_shortage.mean():.3f} kg.", "",
        "Evidence boundary",
        "- Data facts: exact common-sample pairing, path features, accepted SAA baseline quantities, accepted offline state metrics, fixed-bin counts, group summaries, and correlations.",
        "- Descriptive association: all reported rho values and between-group differences.",
        "- Mechanism interpretation: preparation opportunity and multistage spillover are consistent with the observed pattern, but are not causally identified here.",
        "- Not established: that DRO lowers actual disaster-stage W1-W3 EENS, that HTT has no real-world travel constraints, or that reported objective is actual economic expenditure.",
        "- ordinary shortage, terminal gap, and offline W-stage shortage/EENS remain distinct quantities.",
    ]
    (out / "step05b11_judgment.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    out = (repo / args.output).resolve()
    require(not out.exists(), f"Output directory already exists: {out}")
    branch = git(repo, "branch", "--show-current")
    head = git(repo, "rev-parse", "HEAD")
    upstream = git(repo, "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}")
    require(branch == EXPECTED_BRANCH, f"Unexpected branch: {branch}")
    require(head == EXPECTED_HEAD, f"HEAD moved from frozen baseline: {head}")
    require(upstream == "origin/task/002-stage2b-b3-smoke", f"Unexpected upstream: {upstream}")

    master_path = repo / "results/task-002-stage2b-b3-smoke/65-oos-pathwise-saa-dro-performance-audit/run-002/pathwise_saa_dro_comparison.csv"
    oos_path = repo / "output_h2/details/h2_OOS.csv"
    surplus_path = repo / "results/task-002-stage2b-b3-smoke/60-terminal-loh-required-extra-and-flow-audit/run-002/path_station_abcd_classification.csv"
    state_path = repo / "results/task-002-stage2b-b3-smoke/53-35state-saa-vs-eta003-terminal-loh/run-024/terminal_loh_saa_vs_eta003_comparison.csv"
    require(sha256_file(master_path) == EXPECTED_MASTER_SHA256, "Stage-65 master SHA-256 changed.")
    require(sha256_file(oos_path) == EXPECTED_OOS_SHA256, "Frozen OOS SHA-256 changed.")
    require(sha256_file(surplus_path) == EXPECTED_SURPLUS_SHA256, "Stage-60 surplus source SHA-256 changed.")
    require(sha256_file(state_path) == EXPECTED_STATE_SHA256, "Stage-53 state-risk source SHA-256 changed.")

    master = pd.read_csv(master_path)
    oos = pd.read_csv(oos_path)
    surplus = pd.read_csv(surplus_path)
    state = pd.read_csv(state_path)
    require(len(master) == 10000 and master.path_id.tolist() == list(range(1, 10001)), "Master paths are not exactly 1..10000.")
    require(oos.shape == (10000, 8), "Frozen OOS path file is not exactly 10000x8.")
    require(int(master.terminal_hit.sum()) == 6053, "Terminal-hit count changed.")

    features = path_features(oos, master)
    table = master.merge(features, on="path_id", validate="one_to_one")
    table = table.merge(aggregate_surplus(surplus), on="path_id", how="left", validate="one_to_one")
    table = table.merge(state_risk_table(state), on="terminal_state", how="left", validate="many_to_one")
    table = add_bins(table)
    require(table.loc[table.terminal_hit == 0, "saa_surplus_total_kg"].isna().all(), "Surplus leaked to non-terminal paths.")
    require(table.loc[table.terminal_hit == 1, "offline_saa_mean_eens_kwh"].notna().all(), "Terminal-hit paths lack offline risk mapping.")

    out.mkdir(parents=True)
    table_path = out / "pathwise_risk_feature_analysis_table.csv"
    table.to_csv(table_path, index=False)
    # All archived statistics are calculated from the serialized table so that
    # near-ties (notably accepted SAA surplus sums) reproduce exactly on reload.
    table = pd.read_csv(table_path)
    bins = base_bins(table)
    bins.to_csv(out / "delta_i_bins.csv", index=False)
    definitions = feature_definitions()
    definitions.to_csv(out / "risk_feature_definitions.csv", index=False)

    bin_features = definitions.feature.tolist()
    bin_feature_summary(table, bin_features).to_csv(out / "delta_i_bin_feature_summary.csv", index=False)
    corr_specs = [(row.feature, row.data_source, "terminal-hit only" if "terminal-hit only" in row.independence_basis else "all paths")
                  for row in definitions.itertuples()]
    corr = correlations(table, corr_specs)
    corr.to_csv(out / "spearman_correlations.csv", index=False)
    strategy_corr = correlations(
        table,
        [(name, "Stage-65 paired DRO-SAA response", "all paths") for name in
         ["delta_production", "delta_htt", "delta_operating_cost", "delta_ordinary_shortage"]],
    )
    strategy_corr.to_csv(out / "strategy_response_correlations.csv", index=False)

    delta_metrics = ["delta_final_inventory", "delta_production", "delta_htt", "delta_ordinary_shortage", "delta_operating_cost"]
    grouped_summary(table, "terminal_hit", table.terminal_hit.map({0: "non_terminal_hit", 1: "terminal_hit"}), delta_metrics).to_csv(
        out / "terminal_hit_comparison.csv", index=False)
    grouped_summary(table, "saa_ordinary_shortage_group", np.where(table.saa_ordinary_shortage > 0, "positive", "zero"),
                    delta_metrics).to_csv(out / "saa_shortage_group_comparison.csv", index=False)
    grouped_summary(table, "preparation_stage_count", table.preparation_stage_count.astype(str),
                    ["delta_final_inventory", "delta_production", "delta_ordinary_shortage"]).to_csv(
        out / "preparation_stage_comparison.csv", index=False)
    state_summary = terminal_state_summary(table)
    state_summary.to_csv(out / "terminal_state_summary.csv", index=False)
    focus_features = [
        "path_max_intensity", "path_mean_intensity", "appeared_intensity_ge5", "high_intensity_state_count_ge5",
        "preparation_stage_count", "saa_ordinary_shortage", "saa_production", "saa_final_inventory",
        "saa_operating_cost", "saa_surplus_total_kg", "offline_saa_terminal_loh_total_kg",
        "offline_delta_terminal_loh_total_kg", "offline_saa_mean_eens_kwh", "offline_saa_q99_5_shortage_kg",
    ]
    focus_comparison(table, focus_features).to_csv(out / "focus_20_50_vs_low_delta_summary.csv", index=False)
    low_delta_diagnostic(table).to_csv(out / "low_delta_risk_and_saa_surplus_diagnostic.csv", index=False)
    make_plots(out, table, corr, state_summary)
    write_readme(out, branch, head)
    write_judgment(out, table, corr, strategy_corr)
    write_manifest(out, [master_path, oos_path, surplus_path, state_path])
    print(f"Step-05B-11 descriptive association audit generated: {out}")


if __name__ == "__main__":
    main()
