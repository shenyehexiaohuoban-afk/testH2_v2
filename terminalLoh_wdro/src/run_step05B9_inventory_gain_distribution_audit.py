"""Generate the Step-05B-9 fixed-bin OOS inventory-gain audit."""

from __future__ import annotations

import argparse
import hashlib
import math
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd


TOL = 1.0e-8
EXPECTED_MASTER_SHA256 = "58336879de53ea1d216315af7c813c02944b1a0e9746246184ffecb519e9914b"
EXPECTED_SOURCE_SHA256 = "1d23404cf46629bc3db4f983b47fe2e5b1a2260d0379a792b1674b4681419165"
BIN_EDGES = [-np.inf, 1.0, 10.0, 20.0, 30.0, 50.0, 100.0, np.inf]
BIN_LABELS = ["<=1", "1-10", "10-20", "20-30", "30-50", "50-100", ">100"]
THRESHOLDS = [1.0, 10.0, 20.0, 30.0, 50.0, 100.0]


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def mean_or_nan(series: pd.Series) -> float:
    return float(series.mean()) if len(series) else np.nan


def build_bins(master: pd.DataFrame) -> pd.DataFrame:
    working = master.copy()
    working["inventory_gain_bin"] = pd.cut(
        working.delta_final_inventory,
        bins=BIN_EDGES,
        labels=BIN_LABELS,
        right=True,
        include_lowest=True,
        ordered=True,
    )
    require(working.inventory_gain_bin.notna().all(), "At least one path was not assigned to a fixed bin.")
    rows: list[dict[str, object]] = []
    for order, label in enumerate(BIN_LABELS, start=1):
        group = working[working.inventory_gain_bin == label]
        hit = group[group.terminal_hit == 1]
        rows.append(
            {
                "bin_order": order,
                "inventory_gain_bin_kg": label,
                "path_count": int(len(group)),
                "path_share": len(group) / 10000,
                "mean_delta_inventory_kg": mean_or_nan(group.delta_final_inventory),
                "median_delta_inventory_kg": float(group.delta_final_inventory.median()) if len(group) else np.nan,
                "min_delta_inventory_kg": float(group.delta_final_inventory.min()) if len(group) else np.nan,
                "max_delta_inventory_kg": float(group.delta_final_inventory.max()) if len(group) else np.nan,
                "mean_delta_production_kg": mean_or_nan(group.delta_production),
                "mean_delta_htt_kg": mean_or_nan(group.delta_htt),
                "mean_delta_operating_cost_yuan": mean_or_nan(group.delta_operating_cost),
                "mean_delta_ordinary_shortage_kg": mean_or_nan(group.delta_ordinary_shortage),
                "terminal_hit_path_count": int(len(hit)),
                "terminal_hit_share": len(hit) / len(group) if len(group) else np.nan,
                "mean_delta_terminal_loh_hit_only_kg": mean_or_nan(hit.delta_terminal_loh_target),
            }
        )
    out = pd.DataFrame(rows)
    require(int(out.path_count.sum()) == 10000, "Fixed-bin counts do not sum to 10000.")
    require(abs(float(out.path_share.sum()) - 1.0) < 1e-12, "Fixed-bin shares do not sum to one.")
    return out


def build_thresholds(master: pd.DataFrame) -> pd.DataFrame:
    rows: list[dict[str, object]] = []
    for threshold in THRESHOLDS:
        group = master[master.delta_final_inventory > threshold]
        rows.append(
            {
                "threshold_kg_strictly_greater_than": threshold,
                "path_count": int(len(group)),
                "path_share": len(group) / 10000,
                "mean_delta_inventory_kg": mean_or_nan(group.delta_final_inventory),
                "mean_delta_operating_cost_yuan": mean_or_nan(group.delta_operating_cost),
                "mean_delta_production_kg": mean_or_nan(group.delta_production),
                "mean_delta_htt_kg": mean_or_nan(group.delta_htt),
                "mean_delta_ordinary_shortage_kg": mean_or_nan(group.delta_ordinary_shortage),
                "terminal_hit_share": float(group.terminal_hit.mean()) if len(group) else np.nan,
            }
        )
    return pd.DataFrame(rows)


def build_bin_cost_summary(bins: pd.DataFrame) -> pd.DataFrame:
    out = bins[
        [
            "bin_order",
            "inventory_gain_bin_kg",
            "path_count",
            "path_share",
            "mean_delta_inventory_kg",
            "mean_delta_production_kg",
            "mean_delta_htt_kg",
            "mean_delta_operating_cost_yuan",
            "mean_delta_ordinary_shortage_kg",
        ]
    ].copy()
    out["operating_cost_per_mean_inventory_gain_yuan_per_kg"] = np.where(
        out.mean_delta_inventory_kg.abs() > 1.0e-6,
        out.mean_delta_operating_cost_yuan / out.mean_delta_inventory_kg,
        np.nan,
    )
    out["global_mean_operating_cost_contribution_yuan"] = (
        out.path_share * out.mean_delta_operating_cost_yuan.fillna(0.0)
    )
    out["global_mean_inventory_contribution_kg"] = (
        out.path_share * out.mean_delta_inventory_kg.fillna(0.0)
    )
    return out


def build_negative_and_near_zero(master: pd.DataFrame) -> pd.DataFrame:
    groups = [
        ("delta_inventory_lt_minus_1kg", master.delta_final_inventory < -1.0),
        ("abs_delta_inventory_le_1kg", master.delta_final_inventory.abs() <= 1.0),
        ("delta_inventory_gt_1kg", master.delta_final_inventory > 1.0),
    ]
    rows: list[dict[str, object]] = []
    for name, mask in groups:
        group = master[mask]
        rows.append(
            {
                "record_type": "group_summary",
                "group": name,
                "path_id": np.nan,
                "path_count": int(len(group)),
                "path_share": len(group) / 10000,
                "delta_inventory_kg": mean_or_nan(group.delta_final_inventory),
                "min_delta_inventory_kg": float(group.delta_final_inventory.min()) if len(group) else np.nan,
                "max_delta_inventory_kg": float(group.delta_final_inventory.max()) if len(group) else np.nan,
                "delta_production_kg": mean_or_nan(group.delta_production),
                "delta_htt_kg": mean_or_nan(group.delta_htt),
                "delta_operating_cost_yuan": mean_or_nan(group.delta_operating_cost),
                "delta_ordinary_shortage_kg": mean_or_nan(group.delta_ordinary_shortage),
                "terminal_hit": float(group.terminal_hit.mean()) if len(group) else np.nan,
                "terminal_state": np.nan,
            }
        )
    negative = master[master.delta_final_inventory < -TOL]
    require(len(negative) == 3, "Expected exactly three negative inventory-delta paths.")
    for _, row in negative.iterrows():
        rows.append(
            {
                "record_type": "negative_path",
                "group": "delta_inventory_negative",
                "path_id": int(row.path_id),
                "path_count": 1,
                "path_share": 0.0001,
                "delta_inventory_kg": float(row.delta_final_inventory),
                "min_delta_inventory_kg": float(row.delta_final_inventory),
                "max_delta_inventory_kg": float(row.delta_final_inventory),
                "delta_production_kg": float(row.delta_production),
                "delta_htt_kg": float(row.delta_htt),
                "delta_operating_cost_yuan": float(row.delta_operating_cost),
                "delta_ordinary_shortage_kg": float(row.delta_ordinary_shortage),
                "terminal_hit": int(row.terminal_hit),
                "terminal_state": row.terminal_state,
            }
        )
    return pd.DataFrame(rows)


def style_axes(ax: plt.Axes) -> None:
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    ax.grid(axis="y", color="#D9E2EC", linewidth=0.8, alpha=0.8)
    ax.set_axisbelow(True)


def make_plots(out: Path, master: pd.DataFrame, bins: pd.DataFrame, thresholds: pd.DataFrame) -> None:
    plt.rcParams.update(
        {
            "font.family": "DejaVu Sans",
            "font.size": 10,
            "axes.titlesize": 14,
            "axes.labelsize": 11,
            "figure.facecolor": "white",
            "axes.facecolor": "white",
        }
    )
    delta = master.delta_final_inventory.to_numpy(dtype=float)

    fig, ax = plt.subplots(figsize=(10, 5.6), dpi=180)
    hist_edges = np.arange(math.floor(delta.min() / 2) * 2, max(102, math.ceil(delta.max() / 2) * 2 + 2), 2)
    ax.hist(delta, bins=hist_edges, color="#2F75B5", edgecolor="white", linewidth=0.45)
    for threshold in [1, 10, 20, 30, 50, 100]:
        ax.axvline(threshold, color="#B4C7E7", linewidth=0.8, linestyle="--", alpha=0.8)
    ax.axvline(float(delta.mean()), color="#C00000", linewidth=1.8, label=f"Mean = {delta.mean():.2f} kg")
    ax.set_title("Distribution of DRO - SAA Final Inventory (10,000 OOS Paths)")
    ax.set_xlabel("Final inventory difference (kg)")
    ax.set_ylabel("Path count")
    ax.legend(frameon=False)
    style_axes(ax)
    fig.tight_layout()
    fig.savefig(out / "inventory_gain_histogram.png", bbox_inches="tight")
    plt.close(fig)

    fig, ax = plt.subplots(figsize=(10, 5.6), dpi=180)
    colors = ["#A5A5A5", "#9DC3E6", "#5B9BD5", "#70AD47", "#FFC000", "#ED7D31", "#C00000"]
    bars = ax.bar(bins.inventory_gain_bin_kg, bins.path_share * 100, color=colors, width=0.72)
    for bar, count, share in zip(bars, bins.path_count, bins.path_share):
        ax.text(bar.get_x() + bar.get_width() / 2, bar.get_height() + 0.7,
                f"{share:.2%}\n({int(count):,})", ha="center", va="bottom", fontsize=9)
    ax.set_title("OOS Path Share by Fixed Final-Inventory-Gain Bin")
    ax.set_xlabel("DRO - SAA final inventory bin (kg)")
    ax.set_ylabel("Share of 10,000 paths (%)")
    ax.set_ylim(0, max(5, float((bins.path_share * 100).max()) * 1.18))
    style_axes(ax)
    fig.tight_layout()
    fig.savefig(out / "inventory_gain_bin_share.png", bbox_inches="tight")
    plt.close(fig)

    fig, ax = plt.subplots(figsize=(10, 5.6), dpi=180)
    curve_x = np.linspace(min(-10.0, math.floor(delta.min())), 105.0, 600)
    curve_y = np.array([(delta > value).mean() for value in curve_x]) * 100
    ax.plot(curve_x, curve_y, color="#2F75B5", linewidth=2.2)
    ax.scatter(thresholds.threshold_kg_strictly_greater_than,
               thresholds.path_share * 100, color="#C00000", zorder=3, s=34)
    for _, row in thresholds.iterrows():
        ax.annotate(f">{row.threshold_kg_strictly_greater_than:g}: {row.path_share:.2%}",
                    (row.threshold_kg_strictly_greater_than, row.path_share * 100),
                    xytext=(5, 7), textcoords="offset points", fontsize=8.5)
    ax.set_title("Exceedance Curve of Final Inventory Gain")
    ax.set_xlabel("Inventory-gain threshold (kg)")
    ax.set_ylabel("Paths exceeding threshold (%)")
    ax.set_xlim(curve_x.min(), curve_x.max())
    ax.set_ylim(0, 105)
    style_axes(ax)
    fig.tight_layout()
    fig.savefig(out / "inventory_gain_exceedance_curve.png", bbox_inches="tight")
    plt.close(fig)


def write_text_outputs(
    out: Path,
    master_path: Path,
    source_path: Path,
    master: pd.DataFrame,
    bins: pd.DataFrame,
    thresholds: pd.DataFrame,
) -> None:
    threshold_map = thresholds.set_index("threshold_kg_strictly_greater_than")
    largest_bin = bins.iloc[bins.path_count.idxmax()]
    positive_over_one = int((master.delta_final_inventory > 1.0).sum())
    mean_all = float(master.delta_final_inventory.mean())
    positive = master[master.delta_final_inventory > TOL]
    mean_positive = float(positive.delta_final_inventory.mean())

    readme = [
        "# Step-05B-9 OOS inventory-gain distribution audit",
        "",
        "Accepted run: `run-001`.",
        "",
        "This read-only audit uses the Step-05B-8 10000-row common-sample path table and applies only the fixed bins and exceedance thresholds specified by the task. It does not train, resample, invoke MATLAB/Gurobi, generate cuts, change TerminalLOH, change 200/2000, or modify core FA-MSP code.",
        "",
        "The three figures use path-level inventory differences only; no state averages enter the plots.",
        "",
        "Source-integrity note: the actual corrected local Step-05B-8 master file is 5114286 bytes with SHA-256 `58336879...9914b`. The older Step-05B-8 manifest entry predates the corrected state-ID mapping and is stale. The prior accepted run is not modified; this run records the actual source hash and independently reconciles the master against the frozen Step-05B-1 path data.",
    ]
    (out / "README.md").write_text("\n".join(readme) + "\n", encoding="utf-8")

    judgment = [
        "Step-05B-9 judgment",
        "",
        "Fixed-bin distribution",
    ]
    for _, row in bins.iterrows():
        mean_text = "undefined" if pd.isna(row.mean_delta_inventory_kg) else f"{row.mean_delta_inventory_kg:.9f} kg"
        cost_text = "undefined" if pd.isna(row.mean_delta_operating_cost_yuan) else f"{row.mean_delta_operating_cost_yuan:.9f} yuan"
        judgment.append(
            f"- {row.inventory_gain_bin_kg} kg: {int(row.path_count)} paths ({row.path_share:.6%}), mean inventory delta {mean_text}, mean operating-cost delta {cost_text}."
        )
    judgment.extend(["", "Strict exceedance thresholds"])
    for threshold, row in threshold_map.iterrows():
        threshold_mean_text = (
            "undefined"
            if pd.isna(row.mean_delta_inventory_kg)
            else f"{row.mean_delta_inventory_kg:.9f} kg"
        )
        threshold_cost_text = (
            "undefined"
            if pd.isna(row.mean_delta_operating_cost_yuan)
            else f"{row.mean_delta_operating_cost_yuan:.9f} yuan"
        )
        judgment.append(
            f"- DeltaI > {threshold:g} kg: {int(row.path_count)} paths ({row.path_share:.6%}), mean deltaI {threshold_mean_text}, mean operating-cost delta {threshold_cost_text}."
        )
    judgment.extend(
        [
            "",
            "Interpretation",
            f"- The largest fixed bin is {largest_bin.inventory_gain_bin_kg} kg with {int(largest_bin.path_count)} paths ({largest_bin.path_share:.6%}).",
            f"- {positive_over_one} paths exceed 1 kg; therefore the 5600 positive paths are not all material increases, although only {5600-positive_over_one} positive paths fall at or below 1 kg.",
            f"- The all-path mean is {mean_all:.9f} kg, below the positive-path conditional mean {mean_positive:.9f} kg because 4397 paths are equal within solver tolerance and 3 paths decline.",
            "- The appropriate description is: part of the OOS paths receive a clear reserve increase, while a large minority is essentially unchanged.",
            "- The full-sample mean alone hides material path heterogeneity and must be accompanied by the fixed-bin or threshold shares.",
            "",
            "Paper-ready wording",
            f"- Across 10,000 paired OOS paths, {threshold_map.loc[10.0, 'path_share']:.2%} gain more than 10 kg of terminal inventory, {threshold_map.loc[20.0, 'path_share']:.2%} gain more than 20 kg, and {threshold_map.loc[50.0, 'path_share']:.2%} gain more than 50 kg.",
            f"- The mean gain of {mean_all:.3f} kg reflects a mixed response: {bins.loc[bins.inventory_gain_bin_kg == '<=1', 'path_share'].iloc[0]:.2%} of paths remain at or below 1 kg, while substantial shares fall in the 20-50 kg bands.",
        ]
    )
    (out / "step05b9_judgment.txt").write_text("\n".join(judgment) + "\n", encoding="utf-8")

    files = [
        "inventory_gain_bins.csv",
        "inventory_gain_thresholds.csv",
        "inventory_gain_bin_cost_summary.csv",
        "negative_and_near_zero_cases.csv",
        "inventory_gain_histogram.png",
        "inventory_gain_bin_share.png",
        "inventory_gain_exceedance_curve.png",
    ]
    manifest = [
        "# LARGE_FILE_MANIFEST",
        "",
        "All Step-05B-9 outputs are lightweight and eligible for Git.",
        "",
        "| file | bytes | SHA-256 |",
        "|---|---:|---|",
    ]
    for filename in files:
        path = out / filename
        manifest.append(f"| `{filename}` | {path.stat().st_size} | `{sha256_file(path)}` |")
    manifest.extend(
        [
            "",
            f"Protected local source: `{master_path}`; 10000x47; {master_path.stat().st_size} bytes; SHA-256 `{sha256_file(master_path)}`; not copied or modified.",
            f"Frozen Step-05B-1 reconciliation source: `{source_path}`; {source_path.stat().st_size} bytes; SHA-256 `{sha256_file(source_path)}`; not copied or modified.",
            "No MAT, workspace, cache, solver output, or new scenario file was created.",
        ]
    )
    (out / "LARGE_FILE_MANIFEST.md").write_text("\n".join(manifest) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    repo = Path(__file__).resolve().parents[2]
    out = (repo / args.output).resolve()
    require(not out.exists(), f"Output directory already exists: {out}")
    out.mkdir(parents=True)

    master_path = repo / "results/task-002-stage2b-b3-smoke/65-oos-pathwise-saa-dro-performance-audit/run-002/pathwise_saa_dro_comparison.csv"
    source_path = repo / "results/task-002-stage2b-b3-smoke/58-main-msp-terminal-gap-mechanism-audit/run-004/terminal_target_vs_final_inventory.csv"
    require(sha256_file(master_path) == EXPECTED_MASTER_SHA256, "Step-05B-8 master SHA-256 changed.")
    require(sha256_file(source_path) == EXPECTED_SOURCE_SHA256, "Frozen Step-05B-1 source SHA-256 changed.")

    master = pd.read_csv(master_path)
    require(len(master) == 10000 and master.path_id.to_list() == list(range(1, 10001)),
            "Step-05B-8 master is not exactly paths 1..10000.")
    required_columns = [
        "delta_final_inventory", "delta_production", "delta_htt", "delta_operating_cost",
        "delta_ordinary_shortage", "terminal_hit", "delta_terminal_loh_target",
    ]
    require(all(column in master.columns for column in required_columns), "Master table lacks required columns.")
    require(abs(float(master.delta_final_inventory.mean()) - 15.514788165600883) < 1e-10,
            "Step-05B-8 mean inventory delta changed.")
    require(int((master.delta_final_inventory > TOL).sum()) == 5600, "Positive inventory count changed.")
    require(int((master.delta_final_inventory.abs() <= TOL).sum()) == 4397, "Equal inventory count changed.")
    require(int((master.delta_final_inventory < -TOL).sum()) == 3, "Negative inventory count changed.")

    source = pd.read_csv(source_path)
    saa = source[source.method == "saa"].sort_values("path_id")
    dro = source[source.method == "chi2_eta003"].sort_values("path_id")
    require(saa.path_id.to_list() == master.path_id.to_list() == dro.path_id.to_list(),
            "Source/master path IDs differ.")
    source_delta = dro.final_total.to_numpy() - saa.final_total.to_numpy()
    require(float(np.max(np.abs(source_delta - master.delta_final_inventory.to_numpy()))) < 1e-9,
            "Master inventory delta does not reproduce Step-05B-1.")

    bins = build_bins(master)
    thresholds = build_thresholds(master)
    cost_summary = build_bin_cost_summary(bins)
    negative = build_negative_and_near_zero(master)

    bins.to_csv(out / "inventory_gain_bins.csv", index=False)
    thresholds.to_csv(out / "inventory_gain_thresholds.csv", index=False)
    cost_summary.to_csv(out / "inventory_gain_bin_cost_summary.csv", index=False)
    negative.to_csv(out / "negative_and_near_zero_cases.csv", index=False)
    make_plots(out, master, bins, thresholds)
    write_text_outputs(out, master_path, source_path, master, bins, thresholds)
    print(f"Step-05B-9 inventory-gain distribution audit PASS: {out}")


if __name__ == "__main__":
    main()
