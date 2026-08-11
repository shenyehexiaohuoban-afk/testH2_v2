"""Independent mechanical verification for Step-05B-9 run-001."""

from __future__ import annotations

import hashlib
import struct
import subprocess
from pathlib import Path

import numpy as np
import pandas as pd


EXPECTED_MASTER_SHA256 = "58336879de53ea1d216315af7c813c02944b1a0e9746246184ffecb519e9914b"
EXPECTED_SOURCE_SHA256 = "1d23404cf46629bc3db4f983b47fe2e5b1a2260d0379a792b1674b4681419165"
BIN_LABELS = ["<=1", "1-10", "10-20", "20-30", "30-50", "50-100", ">100"]
BIN_EDGES = [-np.inf, 1.0, 10.0, 20.0, 30.0, 50.0, 100.0, np.inf]
THRESHOLDS = [1.0, 10.0, 20.0, 30.0, 50.0, 100.0]
EXPECTED_BIN_COUNTS = [4408, 487, 1093, 1545, 2288, 179, 0]
EXPECTED_THRESHOLD_COUNTS = [5592, 5105, 4012, 2467, 179, 0]
TOL = 1.0e-8


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def png_dimensions(path: Path) -> tuple[int, int]:
    with path.open("rb") as handle:
        header = handle.read(24)
    require(header[:8] == b"\x89PNG\r\n\x1a\n", f"Not a PNG file: {path}")
    require(header[12:16] == b"IHDR", f"PNG lacks IHDR at expected offset: {path}")
    return struct.unpack(">II", header[16:24])


def max_abs_error(left: pd.Series, right: pd.Series) -> float:
    left_values = left.to_numpy(dtype=float)
    right_values = right.to_numpy(dtype=float)
    both_nan = np.isnan(left_values) & np.isnan(right_values)
    require(np.array_equal(np.isnan(left_values), np.isnan(right_values)), "NaN locations differ.")
    if both_nan.all():
        return 0.0
    return float(np.max(np.abs(left_values[~both_nan] - right_values[~both_nan])))


def main() -> None:
    repo = Path(__file__).resolve().parents[2]
    out = repo / "results/task-002-stage2b-b3-smoke/66-oos-inventory-gain-distribution-audit/run-001"
    master_path = repo / "results/task-002-stage2b-b3-smoke/65-oos-pathwise-saa-dro-performance-audit/run-002/pathwise_saa_dro_comparison.csv"
    source_path = repo / "results/task-002-stage2b-b3-smoke/58-main-msp-terminal-gap-mechanism-audit/run-004/terminal_target_vs_final_inventory.csv"

    required = [
        "README.md",
        "inventory_gain_bins.csv",
        "inventory_gain_thresholds.csv",
        "inventory_gain_bin_cost_summary.csv",
        "negative_and_near_zero_cases.csv",
        "inventory_gain_histogram.png",
        "inventory_gain_bin_share.png",
        "inventory_gain_exceedance_curve.png",
        "step05b9_judgment.txt",
        "LARGE_FILE_MANIFEST.md",
    ]
    missing = [name for name in required if not (out / name).is_file()]
    require(not missing, f"Missing required output files: {missing}")
    require(sha256_file(master_path) == EXPECTED_MASTER_SHA256, "Step-05B-8 master SHA-256 changed.")
    require(sha256_file(source_path) == EXPECTED_SOURCE_SHA256, "Step-05B-1 source SHA-256 changed.")

    master = pd.read_csv(master_path)
    bins = pd.read_csv(out / "inventory_gain_bins.csv")
    thresholds = pd.read_csv(out / "inventory_gain_thresholds.csv")
    cost = pd.read_csv(out / "inventory_gain_bin_cost_summary.csv")
    cases = pd.read_csv(out / "negative_and_near_zero_cases.csv")
    source = pd.read_csv(source_path)

    require(len(master) == 10000 and master.path_id.tolist() == list(range(1, 10001)),
            "Master is not exactly path IDs 1..10000.")
    source_saa = source[source.method == "saa"].sort_values("path_id")
    source_dro = source[source.method == "chi2_eta003"].sort_values("path_id")
    require(source_saa.path_id.tolist() == master.path_id.tolist() == source_dro.path_id.tolist(),
            "Master/source path IDs differ.")
    reconstructed_delta = source_dro.final_total.to_numpy() - source_saa.final_total.to_numpy()
    source_reproduction_error = float(
        np.max(np.abs(reconstructed_delta - master.delta_final_inventory.to_numpy()))
    )
    require(source_reproduction_error < 1.0e-9, "Step-05B-1 inventory-delta reconstruction failed.")

    assigned = pd.cut(
        master.delta_final_inventory,
        bins=BIN_EDGES,
        labels=BIN_LABELS,
        right=True,
        include_lowest=True,
        ordered=True,
    )
    recomputed_bin_counts = [int((assigned == label).sum()) for label in BIN_LABELS]
    require(recomputed_bin_counts == EXPECTED_BIN_COUNTS, "Fixed right-closed bin counts changed.")
    require(bins.inventory_gain_bin_kg.tolist() == BIN_LABELS, "Archived bin order/labels changed.")
    require(bins.path_count.astype(int).tolist() == EXPECTED_BIN_COUNTS, "Archived bin counts differ.")
    require(int(bins.path_count.sum()) == 10000, "Archived bin counts do not sum to 10000.")
    require(abs(float(bins.path_share.sum()) - 1.0) < 1.0e-12, "Archived bin shares do not sum to one.")

    bin_rows = []
    for label in BIN_LABELS:
        group = master[assigned == label]
        hit = group[group.terminal_hit == 1]
        bin_rows.append(
            {
                "mean_delta_inventory_kg": group.delta_final_inventory.mean(),
                "median_delta_inventory_kg": group.delta_final_inventory.median(),
                "min_delta_inventory_kg": group.delta_final_inventory.min(),
                "max_delta_inventory_kg": group.delta_final_inventory.max(),
                "mean_delta_production_kg": group.delta_production.mean(),
                "mean_delta_htt_kg": group.delta_htt.mean(),
                "mean_delta_operating_cost_yuan": group.delta_operating_cost.mean(),
                "mean_delta_ordinary_shortage_kg": group.delta_ordinary_shortage.mean(),
                "terminal_hit_share": len(hit) / len(group) if len(group) else np.nan,
                "mean_delta_terminal_loh_hit_only_kg": hit.delta_terminal_loh_target.mean(),
            }
        )
    recomputed_bins = pd.DataFrame(bin_rows)
    max_bin_metric_error = 0.0
    for column in recomputed_bins.columns:
        error = max_abs_error(bins[column], recomputed_bins[column])
        max_bin_metric_error = max(max_bin_metric_error, error)
        require(error < 1.0e-9, f"Bin metric recomputation failed for {column}: {error}")

    recomputed_threshold_counts = [int((master.delta_final_inventory > value).sum()) for value in THRESHOLDS]
    require(recomputed_threshold_counts == EXPECTED_THRESHOLD_COUNTS, "Strict threshold counts changed.")
    require(thresholds.path_count.astype(int).tolist() == EXPECTED_THRESHOLD_COUNTS,
            "Archived threshold counts differ.")
    max_threshold_metric_error = 0.0
    for row_index, value in enumerate(THRESHOLDS):
        group = master[master.delta_final_inventory > value]
        expected = {
            "path_share": len(group) / 10000,
            "mean_delta_inventory_kg": group.delta_final_inventory.mean(),
            "mean_delta_operating_cost_yuan": group.delta_operating_cost.mean(),
            "mean_delta_production_kg": group.delta_production.mean(),
            "mean_delta_htt_kg": group.delta_htt.mean(),
            "mean_delta_ordinary_shortage_kg": group.delta_ordinary_shortage.mean(),
            "terminal_hit_share": group.terminal_hit.mean(),
        }
        for column, expected_value in expected.items():
            archived_value = thresholds.loc[row_index, column]
            if pd.isna(expected_value):
                require(pd.isna(archived_value), f"Threshold {value:g} {column} should be undefined.")
                continue
            error = abs(float(archived_value) - float(expected_value))
            max_threshold_metric_error = max(max_threshold_metric_error, error)
            require(error < 1.0e-9, f"Threshold {value:g} metric mismatch for {column}: {error}")

    require(cost.path_count.astype(int).tolist() == EXPECTED_BIN_COUNTS, "Cost-summary bin counts differ.")
    require(int((master.delta_final_inventory < -1.0).sum()) == 3, "DeltaI < -1 count changed.")
    require(int((master.delta_final_inventory.abs() <= 1.0).sum()) == 4405, "|DeltaI| <= 1 count changed.")
    require(int((master.delta_final_inventory > 1.0).sum()) == 5592, "DeltaI > 1 count changed.")
    require(int((master.delta_final_inventory > TOL).sum()) == 5600, "Positive path count changed.")
    require(int((master.delta_final_inventory.abs() <= TOL).sum()) == 4397, "Equal path count changed.")
    require(int((master.delta_final_inventory < -TOL).sum()) == 3, "Negative path count changed.")

    group_counts = cases[cases.record_type == "group_summary"].set_index("group").path_count.astype(int)
    require(int(group_counts["delta_inventory_lt_minus_1kg"]) == 3, "Archived <-1 group count differs.")
    require(int(group_counts["abs_delta_inventory_le_1kg"]) == 4405, "Archived near-zero group count differs.")
    require(int(group_counts["delta_inventory_gt_1kg"]) == 5592, "Archived >1 group count differs.")
    negative_rows = cases[cases.record_type == "negative_path"].sort_values("path_id")
    require(negative_rows.path_id.astype(int).tolist() == [2275, 6091, 9717],
            "Negative path IDs changed.")

    png_sizes = {}
    for name in ["inventory_gain_histogram.png", "inventory_gain_bin_share.png", "inventory_gain_exceedance_curve.png"]:
        width, height = png_dimensions(out / name)
        require(width >= 1000 and height >= 500, f"PNG dimensions too small: {name} {width}x{height}")
        png_sizes[name] = f"{width}x{height}"

    protected = [
        "main_msp_h2_near.m", "h2_default_options.m", "run_h2_with_options.m",
        "load_data_h2_near.m", "data/yuanqi/near_stage_msp_input.mat",
        "fa_h2/build_stage_model_h2.m", "fa_h2/update_rhs_h2.m",
        "fa_h2/solve_stage_model_h2.m", "fa_h2/forward_pass_h2.m",
        "fa_h2/backward_pass_h2.m", "fa_h2/add_cut_h2.m",
        "fa_h2/train_models_h2.m", "fa_h2/eval_h2.m",
        "codex_rule/core.md", "codex_rule/longtask.md",
    ]
    protected_diff = subprocess.run(
        ["git", "diff", "--name-only", "--", *protected],
        cwd=repo,
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    require(not protected_diff, f"Protected tracked files changed: {protected_diff}")

    audit_lines = [
        "Step-05B-9 independent mechanical audit",
        "",
        "paired_paths: 10000",
        "fixed_bins_right_closed: PASS",
        f"fixed_bin_counts: {'/'.join(str(value) for value in EXPECTED_BIN_COUNTS)}",
        f"strict_threshold_counts: {'/'.join(str(value) for value in EXPECTED_THRESHOLD_COUNTS)}",
        "inventory_increase_equal_decrease: 5600/4397/3",
        "negative_lt_minus_1_near_zero_le_1_gt_1: 3/4405/5592",
        "negative_path_ids: 2275/6091/9717",
        f"max_source_reproduction_error_kg: {source_reproduction_error:.12g}",
        f"max_bin_metric_recompute_error: {max_bin_metric_error:.12g}",
        f"max_threshold_metric_recompute_error: {max_threshold_metric_error:.12g}",
        *[f"{name}_dimensions: {size}" for name, size in png_sizes.items()],
        "required_outputs_present: PASS",
        "independent_mechanical_audit_PASS: 1",
    ]
    (out / "independent_mechanical_audit.txt").write_text(
        "\n".join(audit_lines) + "\n", encoding="utf-8"
    )

    source_lines = [
        "Step-05B-9 source integrity audit",
        "",
        f"Step-05B-8 master SHA-256: {sha256_file(master_path)}",
        f"Step-05B-1 reconciliation source SHA-256: {sha256_file(source_path)}",
        "Protected MSP/model/data/rule tracked files differ from frozen HEAD: no",
        "MATLAB/Gurobi invoked: no",
        "Training/resampling/cut generation: no",
        "TerminalLOH and 200/2000 modified: no",
        "Historical runs modified by this verifier: no",
        "Source integrity PASS: 1",
    ]
    (out / "source_integrity_audit.txt").write_text(
        "\n".join(source_lines) + "\n", encoding="utf-8"
    )
    print("Step-05B-9 independent verification PASS")


if __name__ == "__main__":
    main()
