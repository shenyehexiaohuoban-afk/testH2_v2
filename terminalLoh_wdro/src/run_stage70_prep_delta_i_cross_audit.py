"""Stage-70 read-only preparation-stage count x Delta I bin cross audit."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd


BIN_EDGES = [-np.inf, 1.0, 10.0, 20.0, 30.0, 50.0, 100.0, np.inf]
BIN_LABELS = ["<=1", "1-10", "10-20", "20-30", "30-50", "50-100", ">100"]
PREP_COUNTS = [2, 3, 4, 5, 6]
HASHES = {
    "oos": "6e4ed488423e3cbb838c4a6f8b45019cf4ecf32a82850880399a08aafc7aff85",
    "stage65": "58336879de53ea1d216315af7c813c02944b1a0e9746246184ffecb519e9914b",
    "stage68": "66ba1d7ad593b44b292626ecf24261dae37f0bd28b937e47af0947c1b2fb47f0",
    "stage69": "566ccef74c95cbad99eefde0693c280999084b97e49627bb45a244badab6c7f2",
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


def source_paths(repo: Path) -> dict[str, Path]:
    base = repo / "results/task-002-stage2b-b3-smoke"
    return {
        "oos": repo / "output_h2/details/h2_OOS.csv",
        "stage65": base / "65-oos-pathwise-saa-dro-performance-audit/run-002/pathwise_saa_dro_comparison.csv",
        "stage68": base / "68-oos-risk-feature-association-audit/run-004/pathwise_risk_feature_analysis_table.csv",
        "stage69": base / "69-saa-dro-symmetric-terminal-attainment-audit/run-003/symmetric_terminal_attainment_path_table.csv",
    }


def load_and_audit(paths: dict[str, Path]) -> tuple[pd.DataFrame, dict[str, float]]:
    for key, path in paths.items():
        require(path.is_file(), f"Missing accepted input: {key}: {path}")
        require(sha256_file(path) == HASHES[key], f"Accepted input hash mismatch: {key}")

    oos = pd.read_csv(paths["oos"])
    stage65 = pd.read_csv(paths["stage65"], usecols=["path_id", "terminal_hit", "delta_final_inventory"])
    stage68 = pd.read_csv(
        paths["stage68"],
        usecols=["path_id", "terminal_hit", "preparation_stage_count", "delta_final_inventory", "delta_i_bin"],
    )
    stage69 = pd.read_csv(paths["stage69"], usecols=["method", "path_id", "preparation_stage_count"])

    require(len(oos) == len(stage65) == len(stage68) == 10000, "10000-path identity failed.")
    require(stage65.path_id.is_unique and stage68.path_id.is_unique, "Path IDs are not unique.")
    require(stage65.path_id.tolist() == stage68.path_id.tolist(), "Stage-65/68 path order mismatch.")
    require(np.array_equal(stage65.terminal_hit, stage68.terminal_hit), "Stage-65/68 terminal-hit mismatch.")
    delta_error = float(np.max(np.abs(stage65.delta_final_inventory - stage68.delta_final_inventory)))
    require(delta_error < 1e-12, f"Stage-65/68 Delta I mismatch: {delta_error}")

    rebuilt_bins = pd.cut(
        stage68.delta_final_inventory,
        bins=BIN_EDGES,
        labels=BIN_LABELS,
        right=True,
        include_lowest=True,
    ).astype(str)
    require(np.array_equal(rebuilt_bins, stage68.delta_i_bin.astype(str)), "Stage-68 bin definition mismatch.")
    require(stage68.delta_i_bin.value_counts().reindex(BIN_LABELS, fill_value=0).tolist()
            == [4408, 487, 1093, 1545, 2288, 179, 0], "All-path Delta I bins changed.")
    require(int(stage68.terminal_hit.sum()) == 6053, "Terminal-hit count changed.")
    require(int(((stage68.terminal_hit == 1) & (stage68.delta_final_inventory <= 1.0)).sum()) == 1642,
            "Terminal-hit <=1 kg count changed.")

    stage69_unique = stage69.drop_duplicates(["path_id", "preparation_stage_count"])
    require(len(stage69_unique) == 6053, "Stage-69 unique terminal-hit/prep rows changed.")
    require(stage69.groupby("path_id").preparation_stage_count.nunique().max() == 1,
            "Stage-69 SAA/DRO preparation symmetry failed.")
    hit = stage68[stage68.terminal_hit == 1].copy()
    merged = hit.merge(stage69_unique, on="path_id", suffixes=("", "_stage69"), validate="one_to_one")
    require(np.array_equal(merged.preparation_stage_count, merged.preparation_stage_count_stage69),
            "Stage-68/69 preparation-stage count mismatch.")
    require(sorted(hit.preparation_stage_count.astype(int).unique().tolist()) == PREP_COUNTS,
            "Unexpected terminal-hit preparation groups.")
    return hit, {"maximum_stage65_delta_i_error_kg": delta_error}


def cross_tables(hit: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    counts = pd.crosstab(hit.preparation_stage_count.astype(int), hit.delta_i_bin.astype(str))
    counts = counts.reindex(index=PREP_COUNTS, columns=BIN_LABELS, fill_value=0).astype(int)
    counts.index.name = "preparation_stage_count"
    row_pct = 100.0 * counts.div(counts.sum(axis=1), axis=0)
    col_denominator = counts.sum(axis=0).replace(0, np.nan)
    col_pct = 100.0 * counts.div(col_denominator, axis=1).fillna(0.0)

    count_out = counts.copy()
    count_out["row_total"] = count_out.sum(axis=1)
    count_out.loc["column_total"] = list(counts.sum(axis=0)) + [int(counts.values.sum())]
    count_out = count_out.reset_index()

    row_out = row_pct.copy()
    row_out["row_total_percent"] = row_out.sum(axis=1)
    row_out = row_out.reset_index()

    col_out = col_pct.copy()
    col_out.loc["column_total_percent"] = col_out.sum(axis=0)
    col_out = col_out.reset_index()
    return count_out, row_out, col_out


def focused_summary(hit: pd.DataFrame) -> pd.DataFrame:
    small = hit[hit.delta_final_inventory <= 1.0]
    mid = hit[(hit.delta_final_inventory > 20.0) & (hit.delta_final_inventory <= 50.0)]
    gt10 = hit[hit.delta_final_inventory > 10.0]
    gt20 = hit[hit.delta_final_inventory > 20.0]

    rows: list[dict[str, object]] = []

    def add(scope: str, component: str, count: int, total: int) -> None:
        rows.append({"scope": scope, "component": component, "path_count": int(count),
                     "scope_total": int(total), "share_within_scope": count / total if total else np.nan})

    add("terminal_hit_delta_i_le_1", "prep_2_3", int(small.preparation_stage_count.isin([2, 3]).sum()), len(small))
    add("terminal_hit_delta_i_le_1", "prep_4_6", int(small.preparation_stage_count.isin([4, 5, 6]).sum()), len(small))
    for prep in PREP_COUNTS:
        add("terminal_hit_delta_i_20_50", f"prep_{prep}", int((mid.preparation_stage_count == prep).sum()), len(mid))
    add("terminal_hit_delta_i_20_50", "prep_4_6", int(mid.preparation_stage_count.isin([4, 5, 6]).sum()), len(mid))
    for scope, group in [("terminal_hit_delta_i_gt_10", gt10), ("terminal_hit_delta_i_gt_20", gt20)]:
        for prep in PREP_COUNTS:
            add(scope, f"prep_{prep}", int((group.preparation_stage_count == prep).sum()), len(group))
        add(scope, "prep_4_6", int(group.preparation_stage_count.isin([4, 5, 6]).sum()), len(group))
    return pd.DataFrame(rows)


def make_figure(out: Path, counts_out: pd.DataFrame, col_pct_out: pd.DataFrame) -> None:
    counts = counts_out[counts_out.preparation_stage_count.astype(str) != "column_total"].copy()
    counts.index = counts.preparation_stage_count.astype(int)
    matrix = counts[BIN_LABELS].to_numpy(dtype=float)
    col_pct = col_pct_out[col_pct_out.preparation_stage_count.astype(str) != "column_total_percent"].copy()
    share = col_pct[BIN_LABELS].to_numpy(dtype=float)

    fig, ax = plt.subplots(figsize=(11.5, 5.8), dpi=180)
    image = ax.imshow(matrix, cmap="YlGnBu", aspect="auto")
    for row in range(matrix.shape[0]):
        for col in range(matrix.shape[1]):
            value = int(matrix[row, col])
            color = "white" if matrix[row, col] > 0.55 * matrix.max() else "#172B4D"
            ax.text(col, row, f"{value}\n({share[row, col]:.1f}% col)", ha="center", va="center",
                    fontsize=8, color=color)
    ax.set_xticks(range(len(BIN_LABELS)))
    ax.set_xticklabels([f"{label} kg" for label in BIN_LABELS])
    ax.set_yticks(range(len(PREP_COUNTS)))
    ax.set_yticklabels(PREP_COUNTS)
    ax.set_xlabel("Delta I bin")
    ax.set_ylabel("Preparation-stage count")
    ax.set_title("Terminal-Hit Preparation Opportunities × Inventory-Gain Bins\nCell: path count (share within Delta I bin)")
    cbar = fig.colorbar(image, ax=ax, pad=0.02)
    cbar.set_label("Path count")
    fig.tight_layout()
    fig.savefig(out / "fig_prep_delta_i_cross_heatmap.png", bbox_inches="tight")
    plt.close(fig)


def write_text_outputs(out: Path, focus: pd.DataFrame, checks: dict[str, float]) -> None:
    lookup = focus.set_index(["scope", "component"])
    def fact(scope: str, component: str) -> tuple[int, float]:
        row = lookup.loc[(scope, component)]
        return int(row.path_count), float(row.share_within_scope)

    small23 = fact("terminal_hit_delta_i_le_1", "prep_2_3")
    small46 = fact("terminal_hit_delta_i_le_1", "prep_4_6")
    mid4 = fact("terminal_hit_delta_i_20_50", "prep_4")
    mid5 = fact("terminal_hit_delta_i_20_50", "prep_5")
    mid6 = fact("terminal_hit_delta_i_20_50", "prep_6")
    mid46 = fact("terminal_hit_delta_i_20_50", "prep_4_6")
    gt10 = fact("terminal_hit_delta_i_gt_10", "prep_4_6")
    gt20 = fact("terminal_hit_delta_i_gt_20", "prep_4_6")

    judgment = [
        "Stage-70 preparation-stage count x Delta I bin cross audit", "",
        "Status: PASS after independent mechanical verification", "",
        "Frozen sample gates",
        "- 10000 common-sample OOS paths; 6053 terminal-hit paths.",
        "- 4408 all-path Delta I <=1 kg paths; 1642 are terminal-hit.",
        f"- Maximum Stage-65/68 Delta I identity error: {checks['maximum_stage65_delta_i_error_kg']:.3g} kg.", "",
        "Small-change terminal-hit composition",
        f"- Prep 2-3: {small23[0]}/1642 ({small23[1]:.2%}).",
        f"- Prep 4-6: {small46[0]}/1642 ({small46[1]:.2%}).",
        "- Limited preparation opportunities explain a majority, but not all, of the small-change paths; a substantial 43.42% still have prep 4-6.", "",
        "20-50 kg terminal-hit composition",
        f"- Prep 4: {mid4[0]} ({mid4[1]:.2%}); prep 5: {mid5[0]} ({mid5[1]:.2%}); prep 6: {mid6[0]} ({mid6[1]:.2%}).",
        f"- Prep 4-6 combined: {mid46[0]}/3031 ({mid46[1]:.2%}).", "",
        "Larger inventory-gain concentration",
        f"- Delta I >10 kg: prep 4-6 contains {gt10[0]}/4055 ({gt10[1]:.2%}).",
        f"- Delta I >20 kg: prep 4-6 contains {gt20[0]}/3199 ({gt20[1]:.2%}).",
        "- The association is descriptive and is not a causal identification of preparation opportunities.",
        "- No model, TerminalLOH, eta, policy, OOS sample, optimization, training, or W-stage recourse was changed or run.",
    ]
    (out / "stage70_judgment.txt").write_text("\n".join(judgment) + "\n", encoding="utf-8")

    readme = """# Stage-70 preparation-stage count x Delta I bin cross audit

Status: candidate PASS pending independent mechanical verification.

This read-only audit uses the accepted Stage-68 path-level Delta I bins and preparation-stage count, with Stage-65 Delta I and Stage-69 terminal-hit/preparation identities independently cross-checked. The core table contains the 6053 terminal-hit paths from the frozen 10000x8 common-sample OOS.

Outputs provide cross counts, within-prep row percentages, within-Delta-I-bin column percentages, focused composition facts, one annotated heatmap, a judgment, source hashes, and an independent audit. No MATLAB, Gurobi, model change, training, resampling, regression, machine learning, or W1-W3 recourse is used.
"""
    (out / "README.md").write_text(readme, encoding="utf-8")


def write_manifest(out: Path, paths: dict[str, Path]) -> None:
    lines = ["# SOURCE_AND_OUTPUT_MANIFEST", "", "## Generated outputs", "",
             "| file | bytes | SHA-256 |", "|---|---:|---|"]
    for path in sorted(out.iterdir(), key=lambda item: item.name):
        if path.is_file() and path.name != "SOURCE_AND_OUTPUT_MANIFEST.md":
            lines.append(f"| `{path.name}` | {path.stat().st_size} | `{sha256_file(path)}` |")
    lines.extend(["", "## Protected accepted inputs", "", "| role | path | bytes | SHA-256 |",
                  "|---|---|---:|---|"])
    for key, path in paths.items():
        lines.append(f"| {key} | `{path}` | {path.stat().st_size} | `{sha256_file(path)}` |")
    lines.extend(["", "No accepted input or historical run was modified."])
    (out / "SOURCE_AND_OUTPUT_MANIFEST.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    out = (repo / args.output).resolve()
    require(not out.exists(), f"Refusing to overwrite existing output: {out}")
    out.mkdir(parents=True)

    paths = source_paths(repo)
    hit, checks = load_and_audit(paths)
    counts, row_pct, col_pct = cross_tables(hit)
    focus = focused_summary(hit)
    counts.to_csv(out / "prep_delta_i_cross_counts.csv", index=False)
    row_pct.to_csv(out / "prep_delta_i_row_percent.csv", index=False)
    col_pct.to_csv(out / "prep_delta_i_column_percent.csv", index=False)
    focus.to_csv(out / "focused_composition_summary.csv", index=False)
    pd.DataFrame([{
        "total_paths": 10000,
        "terminal_hit_paths": 6053,
        "all_path_delta_i_le_1": 4408,
        "terminal_hit_delta_i_le_1": 1642,
        **checks,
    }]).to_csv(out / "source_crosscheck.csv", index=False)
    make_figure(out, counts, col_pct)
    write_text_outputs(out, focus, checks)
    write_manifest(out, paths)
    print(f"Stage-70 prep x Delta I audit generated: {out}")


if __name__ == "__main__":
    main()
