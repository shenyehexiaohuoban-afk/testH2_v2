"""Independent mechanical verifier for Step-05B-11."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path

import numpy as np
import pandas as pd
from PIL import Image
from scipy.stats import spearmanr


EXPECTED = {
    "oos": "6e4ed488423e3cbb838c4a6f8b45019cf4ecf32a82850880399a08aafc7aff85",
    "master": "58336879de53ea1d216315af7c813c02944b1a0e9746246184ffecb519e9914b",
    "surplus": "070dbe1c4af028f6f658bb31c4daa72e21eee465b8c02e4bb477fc23d22b94a7",
    "state": "956a9f3b69a7e26b8ca1abe7355bf59cc467279f9527f09bfda8102bbe7f88d9",
}
EXPECTED_COUNTS = [4408, 487, 1093, 1545, 2288, 179, 0]
LABELS = ["<=1", "1-10", "10-20", "20-30", "30-50", "50-100", ">100"]


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def decode(k: int) -> tuple[int, int, int]:
    z = int(k) - 1
    return z // 56 + 1, (z // 8) % 7 + 1, z % 8 + 1


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    out = (repo / args.output).resolve()
    require(out.is_dir(), f"Missing output directory: {out}")

    paths = {
        "master": repo / "results/task-002-stage2b-b3-smoke/65-oos-pathwise-saa-dro-performance-audit/run-002/pathwise_saa_dro_comparison.csv",
        "oos": repo / "output_h2/details/h2_OOS.csv",
        "surplus": repo / "results/task-002-stage2b-b3-smoke/60-terminal-loh-required-extra-and-flow-audit/run-002/path_station_abcd_classification.csv",
        "state": repo / "results/task-002-stage2b-b3-smoke/53-35state-saa-vs-eta003-terminal-loh/run-024/terminal_loh_saa_vs_eta003_comparison.csv",
    }
    for key, path in paths.items():
        require(sha256_file(path) == EXPECTED[key], f"Protected source hash mismatch: {key}")

    accepted = pd.read_csv(paths["master"])
    table = pd.read_csv(out / "pathwise_risk_feature_analysis_table.csv")
    oos = pd.read_csv(paths["oos"])
    require(len(table) == 10000 and table.path_id.tolist() == list(range(1, 10001)), "Analysis table path identity failed.")
    for col in ["delta_final_inventory", "delta_production", "delta_htt", "delta_ordinary_shortage", "delta_operating_cost"]:
        err = float(np.max(np.abs(table[col].to_numpy() - accepted[col].to_numpy())))
        require(err < 1e-12, f"Accepted Stage-65 field changed: {col}, error={err}")

    decoded_rows = []
    for _, raw in oos.iterrows():
        states = [decode(v) for v in raw]
        stop = next((i for i, (a, _, lf) in enumerate(states) if a == 1 or lf >= 7), 7)
        obs = states[: stop + 1]
        prep = [s for s in obs if s[0] > 1 and s[2] <= 6]
        risk = [s for s in obs if s[0] > 1 and s[2] <= 7]
        decoded_rows.append((max(s[0] for s in risk), np.mean([s[0] for s in risk]), len(prep), prep[-1][1] - prep[0][1]))
    decoded = np.asarray(decoded_rows, dtype=float)
    checks = [
        ("path_max_intensity", decoded[:, 0]),
        ("path_mean_intensity", decoded[:, 1]),
        ("preparation_stage_count", decoded[:, 2]),
        ("net_loc_change", decoded[:, 3]),
    ]
    max_feature_error = 0.0
    for col, values in checks:
        err = float(np.max(np.abs(table[col].to_numpy(dtype=float) - values)))
        max_feature_error = max(max_feature_error, err)
        require(err < 1e-12, f"Independent path-feature reconstruction failed: {col}")

    delta = table.delta_final_inventory
    masks = [delta <= 1, delta.gt(1) & delta.le(10), delta.gt(10) & delta.le(20),
             delta.gt(20) & delta.le(30), delta.gt(30) & delta.le(50),
             delta.gt(50) & delta.le(100), delta > 100]
    counts = [int(mask.sum()) for mask in masks]
    require(counts == EXPECTED_COUNTS, f"Fixed-bin reproduction failed: {counts}")
    require(int((delta.gt(20) & delta.le(50)).sum()) == 3833, "20-50 kg count is not 3833.")
    require(abs(float((delta.gt(20) & delta.le(50)).mean()) - 0.3833) < 1e-12, "20-50 kg share is not 38.33%.")
    archived_bins = pd.read_csv(out / "delta_i_bins.csv")
    require(archived_bins.delta_i_bin_kg.astype(str).tolist() == LABELS, "Archived bin labels changed.")
    require(archived_bins.path_count.astype(int).tolist() == EXPECTED_COUNTS, "Archived bin counts changed.")

    corr = pd.read_csv(out / "spearman_correlations.csv")
    max_corr_error = 0.0
    for row in corr.itertuples():
        valid = table[[row.feature, "delta_final_inventory"]].dropna()
        if valid[row.feature].nunique() < 2:
            continue
        calc = float(spearmanr(valid[row.feature], valid.delta_final_inventory)[0])
        err = abs(calc - float(row.spearman_rho))
        max_corr_error = max(max_corr_error, err)
        require(err < 1e-12, f"Spearman reproduction failed: {row.feature}")

    state_summary = pd.read_csv(out / "terminal_state_summary.csv")
    require(int(state_summary.path_count.sum()) == 6053, "Terminal-state frequencies do not sum to 6053.")
    prep_summary = pd.read_csv(out / "preparation_stage_comparison.csv")
    prep_counts = prep_summary.groupby("group").path_count.first().sum()
    require(int(prep_counts) == 10000, "Preparation groups do not cover 10000 paths.")
    hit_summary = pd.read_csv(out / "terminal_hit_comparison.csv")
    require(int(hit_summary.groupby("group").path_count.first().sum()) == 10000, "Terminal-hit groups do not cover all paths.")

    figure_names = [
        "fig1_delta_i_bin_independent_risk_boxplots.png",
        "fig2_independent_risk_vs_delta_i_scatter.png",
        "fig3_terminal_hit_delta_i_distribution.png",
        "fig4_preparation_stage_count_delta_i.png",
        "fig5_terminal_state_frequency_and_delta_i.png",
    ]
    dimensions = []
    for name in figure_names:
        with Image.open(out / name) as image:
            image.verify()
        with Image.open(out / name) as image:
            dimensions.append(f"{name}:{image.width}x{image.height}")
            require(image.width >= 1000 and image.height >= 700, f"Figure too small: {name}")

    text = [
        "Step-05B-11 independent mechanical audit: PASS", "",
        "Path identity: exact 1..10000", "SAA/DRO accepted path fields: exact reproduction",
        f"Frozen OOS SHA-256: {EXPECTED['oos']}", f"Fixed-bin counts: {'/'.join(map(str, counts))}",
        "20-50 kg combined: 3833 paths (38.33%)", f"Maximum independent path-feature error: {max_feature_error:.3g}",
        f"Maximum Spearman reproduction error: {max_corr_error:.3g}",
        "Terminal-hit state-frequency total: 6053", "Figure integrity: PASS", *dimensions,
        "No model solve, training, resampling, or W-stage recourse was used by this verifier.",
    ]
    (out / "independent_mechanical_audit.txt").write_text("\n".join(text) + "\n", encoding="utf-8")
    print(f"Step-05B-11 independent verification PASS: {out}")


if __name__ == "__main__":
    main()
