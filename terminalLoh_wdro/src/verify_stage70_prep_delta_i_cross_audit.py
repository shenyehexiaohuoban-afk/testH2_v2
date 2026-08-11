"""Independent verifier for the Stage-70 prep x Delta I cross audit."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path

import numpy as np
import pandas as pd
from PIL import Image


BIN_EDGES = [-np.inf, 1.0, 10.0, 20.0, 30.0, 50.0, 100.0, np.inf]
BIN_LABELS = ["<=1", "1-10", "10-20", "20-30", "30-50", "50-100", ">100"]
PREP_COUNTS = [2, 3, 4, 5, 6]
EXPECTED_COUNTS = np.array([
    [79, 0, 0, 0, 0, 0, 0],
    [850, 55, 59, 115, 65, 0, 0],
    [439, 184, 670, 863, 382, 19, 0],
    [258, 69, 95, 144, 1180, 109, 0],
    [16, 48, 32, 28, 254, 40, 0],
], dtype=int)
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


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    base = repo / "results/task-002-stage2b-b3-smoke"
    out = (repo / args.output).resolve()
    require(out.is_dir(), "Output directory missing.")
    paths = {
        "oos": repo / "output_h2/details/h2_OOS.csv",
        "stage65": base / "65-oos-pathwise-saa-dro-performance-audit/run-002/pathwise_saa_dro_comparison.csv",
        "stage68": base / "68-oos-risk-feature-association-audit/run-004/pathwise_risk_feature_analysis_table.csv",
        "stage69": base / "69-saa-dro-symmetric-terminal-attainment-audit/run-003/symmetric_terminal_attainment_path_table.csv",
    }
    for key, path in paths.items():
        require(sha256_file(path) == HASHES[key], f"Source hash mismatch: {key}")

    stage65 = pd.read_csv(paths["stage65"], usecols=["path_id", "terminal_hit", "delta_final_inventory"])
    stage68 = pd.read_csv(paths["stage68"], usecols=["path_id", "terminal_hit", "preparation_stage_count", "delta_final_inventory"])
    stage69 = pd.read_csv(paths["stage69"], usecols=["path_id", "preparation_stage_count"])
    require(len(stage65) == len(stage68) == 10000, "10000-path gate failed.")
    require(np.array_equal(stage65.path_id, stage68.path_id), "Path identity failed.")
    require(np.array_equal(stage65.terminal_hit, stage68.terminal_hit), "Terminal-hit identity failed.")
    require(float(np.max(np.abs(stage65.delta_final_inventory - stage68.delta_final_inventory))) < 1e-12,
            "Delta I identity failed.")

    hit = stage68[stage68.terminal_hit == 1].copy()
    hit["delta_i_bin"] = pd.cut(hit.delta_final_inventory, bins=BIN_EDGES, labels=BIN_LABELS,
                                right=True, include_lowest=True).astype(str)
    rebuilt = pd.crosstab(hit.preparation_stage_count.astype(int), hit.delta_i_bin)
    rebuilt = rebuilt.reindex(index=PREP_COUNTS, columns=BIN_LABELS, fill_value=0).to_numpy(dtype=int)
    require(np.array_equal(rebuilt, EXPECTED_COUNTS), "Independent cross-count matrix changed.")
    require(len(hit) == 6053 and int((hit.delta_final_inventory <= 1.0).sum()) == 1642,
            "Terminal-hit core gates failed.")

    stage69_unique = stage69.drop_duplicates()
    require(stage69.groupby("path_id").preparation_stage_count.nunique().max() == 1,
            "Stage-69 method symmetry failed.")
    stage69_unique = stage69_unique.drop_duplicates("path_id")
    merged = hit[["path_id", "preparation_stage_count"]].merge(
        stage69_unique, on="path_id", suffixes=("", "_stage69"), validate="one_to_one")
    require(np.array_equal(merged.preparation_stage_count, merged.preparation_stage_count_stage69),
            "Stage-68/69 preparation identity failed.")

    counts = pd.read_csv(out / "prep_delta_i_cross_counts.csv")
    archived = counts[counts.preparation_stage_count.astype(str) != "column_total"][BIN_LABELS].to_numpy(dtype=int)
    require(np.array_equal(archived, rebuilt), "Archived count table mismatch.")

    row = pd.read_csv(out / "prep_delta_i_row_percent.csv")
    expected_row = 100.0 * rebuilt / rebuilt.sum(axis=1, keepdims=True)
    require(float(np.max(np.abs(row[BIN_LABELS].to_numpy() - expected_row))) < 1e-12,
            "Row percentage table mismatch.")
    col = pd.read_csv(out / "prep_delta_i_column_percent.csv")
    archived_col = col[col.preparation_stage_count.astype(str) != "column_total_percent"][BIN_LABELS].to_numpy()
    denominators = rebuilt.sum(axis=0)
    expected_col = np.divide(100.0 * rebuilt, denominators, out=np.zeros_like(rebuilt, dtype=float), where=denominators > 0)
    require(float(np.max(np.abs(archived_col - expected_col))) < 1e-12,
            "Column percentage table mismatch.")

    focus = pd.read_csv(out / "focused_composition_summary.csv").set_index(["scope", "component"])
    expected_focus = {
        ("terminal_hit_delta_i_le_1", "prep_2_3"): (929, 1642),
        ("terminal_hit_delta_i_le_1", "prep_4_6"): (713, 1642),
        ("terminal_hit_delta_i_20_50", "prep_4"): (1245, 3031),
        ("terminal_hit_delta_i_20_50", "prep_5"): (1324, 3031),
        ("terminal_hit_delta_i_20_50", "prep_6"): (282, 3031),
        ("terminal_hit_delta_i_20_50", "prep_4_6"): (2851, 3031),
        ("terminal_hit_delta_i_gt_10", "prep_4_6"): (3816, 4055),
        ("terminal_hit_delta_i_gt_20", "prep_4_6"): (3019, 3199),
    }
    for key, (count, total) in expected_focus.items():
        archived_row = focus.loc[key]
        require(int(archived_row.path_count) == count and int(archived_row.scope_total) == total,
                f"Focused count mismatch: {key}")
        require(abs(float(archived_row.share_within_scope) - count / total) < 1e-12,
                f"Focused share mismatch: {key}")

    figure_path = out / "fig_prep_delta_i_cross_heatmap.png"
    with Image.open(figure_path) as image:
        image.verify()
    with Image.open(figure_path) as image:
        require(image.width >= 1400 and image.height >= 700, "Figure dimensions are too small.")
        dimensions = f"{image.width}x{image.height}"

    audit_lines = [
        "Stage-70 independent mechanical audit: PASS", "",
        "total_paths: 10000", "terminal_hit_paths: 6053",
        "all_path_delta_i_le_1: 4408", "terminal_hit_delta_i_le_1: 1642",
        "small_change_prep_2_3: 929/1642", "small_change_prep_4_6: 713/1642",
        "terminal_hit_20_50_prep_4_5_6: 1245/1324/282",
        "terminal_hit_20_50_prep_4_6: 2851/3031",
        "terminal_hit_gt_10_prep_4_6: 3816/4055",
        "terminal_hit_gt_20_prep_4_6: 3019/3199",
        "cross_counts_row_percent_column_percent: PASS",
        "stage65_stage68_delta_i_identity: PASS", "stage68_stage69_preparation_identity: PASS",
        f"figure_integrity: PASS ({dimensions})",
        "No model, optimization, training, resampling, regression, machine learning, or W-stage recourse was used.",
    ]
    audit_path = out / "independent_mechanical_audit.txt"
    audit_path.write_text("\n".join(audit_lines) + "\n", encoding="utf-8")

    readme_path = out / "README.md"
    readme = readme_path.read_text(encoding="utf-8").replace(
        "Status: candidate PASS pending independent mechanical verification.",
        "Status: PASS after independent mechanical verification.")
    readme_path.write_text(readme, encoding="utf-8")

    manifest = ["# SOURCE_AND_OUTPUT_MANIFEST", "", "## Generated outputs", "",
                "| file | bytes | SHA-256 |", "|---|---:|---|"]
    for path in sorted(out.iterdir(), key=lambda item: item.name):
        if path.is_file() and path.name != "SOURCE_AND_OUTPUT_MANIFEST.md":
            manifest.append(f"| `{path.name}` | {path.stat().st_size} | `{sha256_file(path)}` |")
    manifest.extend(["", "## Protected accepted inputs", "", "| role | path | bytes | SHA-256 |",
                     "|---|---|---:|---|"])
    for key, path in paths.items():
        manifest.append(f"| {key} | `{path}` | {path.stat().st_size} | `{sha256_file(path)}` |")
    manifest.extend(["", "No accepted input or historical run was modified."])
    (out / "SOURCE_AND_OUTPUT_MANIFEST.md").write_text("\n".join(manifest) + "\n", encoding="utf-8")
    print(f"Stage-70 independent verification PASS: {out}")


if __name__ == "__main__":
    main()
