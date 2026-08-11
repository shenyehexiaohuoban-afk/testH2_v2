"""Independent verifier for Step-05B-11A symmetric attainment audit."""

from __future__ import annotations

import argparse
import hashlib
import warnings
from pathlib import Path

import numpy as np
import pandas as pd
from PIL import Image
from scipy.stats import spearmanr


GAP_TOL = 1.0e-9
HASHES = {
    "oos": "6e4ed488423e3cbb838c4a6f8b45019cf4ecf32a82850880399a08aafc7aff85",
    "stage58": "1d23404cf46629bc3db4f983b47fe2e5b1a2260d0379a792b1674b4681419165",
    "stage64": "d5a567264165d59c6115d303517eaac51904ba569a8b87a69cf0d0ceaeb8759b",
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


def rho(x: pd.Series, y: pd.Series) -> float:
    valid = pd.DataFrame({"x": x, "y": y}).dropna()
    if valid.x.nunique() < 2 or valid.y.nunique() < 2:
        return np.nan
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        return float(spearmanr(valid.x, valid.y)[0])


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
        "stage58": base / "58-main-msp-terminal-gap-mechanism-audit/run-004/terminal_target_vs_final_inventory.csv",
        "stage64": base / "64-terminal-loh-all-state-capacity-gap-audit/run-002/all_path_saa_dro_feasibility_transition.csv",
        "stage65": base / "65-oos-pathwise-saa-dro-performance-audit/run-002/pathwise_saa_dro_comparison.csv",
        "stage68": base / "68-oos-risk-feature-association-audit/run-004/pathwise_risk_feature_analysis_table.csv",
    }
    for key, path in paths.items():
        require(sha256_file(path) == HASHES[key], f"Source hash mismatch: {key}")

    archived = pd.read_csv(out / "symmetric_terminal_attainment_path_table.csv")
    source = pd.read_csv(paths["stage58"])
    features = pd.read_csv(paths["stage68"], usecols=["path_id", "terminal_hit", "preparation_stage_count"])
    hit = source[source.hit_terminal == 1].merge(features[features.terminal_hit == 1], on="path_id", validate="many_to_one")
    require(len(archived) == len(hit) == 12106, "Symmetric path-method row count changed.")
    require(archived.groupby("method").size().to_dict() == {"chi2_eta003": 6053, "saa": 6053},
            "Method symmetry failed.")
    hit = hit.sort_values(["method", "path_id"]).reset_index(drop=True)
    archived = archived.sort_values(["method", "path_id"]).reset_index(drop=True)
    require(np.array_equal(hit.path_id, archived.path_id), "Path ordering/identity failed.")
    require(np.array_equal(hit.preparation_stage_count, archived.preparation_stage_count), "Stage-68 prep count mismatch.")

    max_site_gap_error = 0.0
    for site in range(1, 5):
        calc = np.maximum(0.0, hit[f"target_site{site}"] - hit[f"final_site{site}"])
        clean = np.where(calc > GAP_TOL, calc, 0.0)
        max_site_gap_error = max(max_site_gap_error,
            float(np.max(np.abs(calc - archived[f"gap_site{site}_raw_kg"]))))
        require(float(np.max(np.abs(clean - archived[f"gap_site{site}_kg"]))) < 1e-12,
                f"Clean station gap mismatch at site {site}.")
    rebuilt = sum(archived[f"gap_site{i}_kg"] for i in range(1, 5))
    require(float(np.max(np.abs(rebuilt - archived.gap_total_kg))) < 1e-12, "Stationwise total gap mismatch.")

    overall = pd.read_csv(out / "overall_symmetric_summary.csv").set_index("method")
    expected_counts = {"saa": 714, "chi2_eta003": 900}
    for method, group in archived.groupby("method"):
        require(int(group.gap_positive.sum()) == expected_counts[method], f"Gap-positive count mismatch: {method}")
        require(abs(group.target_total_kg.mean() - overall.loc[method, "target_mean_kg"]) < 1e-12,
                f"Overall target mean mismatch: {method}")
        require(abs(group.inventory_total_kg.mean() - overall.loc[method, "actual_inventory_mean_kg"]) < 1e-12,
                f"Overall inventory mean mismatch: {method}")
        require(abs(group.gap_total_kg.mean() - overall.loc[method, "terminal_gap_mean_kg"]) < 1e-12,
                f"Overall gap mean mismatch: {method}")

    corr = pd.read_csv(out / "symmetric_spearman_correlations.csv")
    max_corr_error = 0.0
    for row in corr.itertuples():
        group = archived[archived.method == row.method]
        if row.scope == "positive_target_only":
            group = group[group.target_total_kg > GAP_TOL]
        calc = rho(group.preparation_stage_count, group[row.response])
        if pd.isna(calc) and pd.isna(row.spearman_rho):
            continue
        err = abs(calc - row.spearman_rho)
        max_corr_error = max(max_corr_error, err)
        require(err < 1e-12, f"Spearman mismatch: {row.method}/{row.scope}/{row.response}")

    same = pd.read_csv(out / "same_prep_saa_dro_comparison.csv")
    require(same.paired_path_count.astype(int).tolist() == [79, 1144, 2557, 1855, 418],
            "Terminal-hit prep group counts changed.")
    require(int(same.paired_path_count.sum()) == 6053, "Prep groups do not sum to 6053.")

    stage64 = pd.read_csv(paths["stage64"]).set_index("path_id")
    max_stage64_error = 0.0
    for method, suffix in [("saa", "saa"), ("chi2_eta003", "dro")]:
        group = archived[archived.method == method].set_index("path_id")
        max_stage64_error = max(max_stage64_error,
            float(np.max(np.abs(group.target_total_kg - stage64[f"terminal_loh_total_target_kg_{suffix}"]))))
        max_stage64_error = max(max_stage64_error,
            float(np.max(np.abs(group.inventory_total_kg - stage64[f"actual_final_inventory_total_kg_{suffix}"]))))
    require(max_stage64_error < 1e-9, "Stage-64 independent total identity failed.")

    within = pd.read_csv(out / "within_state_preparation_association.csv")
    summary = pd.read_csv(out / "within_state_direction_summary.csv").set_index("method")
    require(int(summary.loc["saa", "gap_evaluable_states"]) == 18 and
            int(summary.loc["saa", "negative_gap_correlation_states"]) == 18,
            "SAA within-state direction count changed.")
    require(int(summary.loc["chi2_eta003", "gap_evaluable_states"]) == 19 and
            int(summary.loc["chi2_eta003", "negative_gap_correlation_states"]) == 19,
            "DRO within-state direction count changed.")
    require(len(within) == 44, "Within-state eligible row count changed.")

    gap_audit = pd.read_csv(out / "terminal_gap_definition_audit.csv").set_index("method")
    require(int(gap_audit.loc["saa", "stationwise_gap_exceeds_aggregate_count"]) == 385,
            "SAA stationwise-vs-aggregate distinction changed.")
    require(int(gap_audit.loc["chi2_eta003", "stationwise_gap_exceeds_aggregate_count"]) == 501,
            "DRO stationwise-vs-aggregate distinction changed.")

    figures = ["fig1_terminal_gap_by_prep_saa_dro.png", "fig2_target_actual_by_prep_saa_dro.png",
               "fig3_gap_positive_share_by_prep.png", "fig4_within_state_prep_gap_correlation.png"]
    dimensions = []
    for name in figures:
        with Image.open(out / name) as image:
            image.verify()
        with Image.open(out / name) as image:
            require(image.width >= 1000 and image.height >= 700, f"Figure too small: {name}")
            dimensions.append(f"{name}:{image.width}x{image.height}")

    lines = ["Step-05B-11A independent mechanical audit: PASS", "",
             "common_terminal_hit_paths: 6053", "symmetric_method_rows: 6053/6053",
             "preparation_group_counts: 79/1144/2557/1855/418",
             "gap_positive_counts_saa_dro: 714/900",
             f"maximum_site_gap_reconstruction_error_kg: {max_site_gap_error:.3g}",
             f"maximum_spearman_reproduction_error: {max_corr_error:.3g}",
             f"maximum_stage64_total_identity_error_kg: {max_stage64_error:.3g}",
             "within_state_negative_gap_correlations_saa: 18/18",
             "within_state_negative_gap_correlations_dro: 19/19",
             "stationwise_gap_exceeds_aggregate_counts_saa_dro: 385/501",
             "stationwise_gap_definition: PASS", "figure_integrity: PASS", *dimensions,
             "No optimization, training, resampling, model change, or W-stage recourse was performed."]
    audit_path = out / "independent_mechanical_audit.txt"
    audit_path.write_text("\n".join(lines) + "\n", encoding="utf-8")

    readme_path = out / "README.md"
    readme = readme_path.read_text(encoding="utf-8")
    readme = readme.replace("Status: candidate PASS pending independent verification.",
                            "Status: PASS after independent mechanical verification.")
    readme_path.write_text(readme, encoding="utf-8")

    manifest_path = out / "LARGE_FILE_MANIFEST.md"
    manifest = manifest_path.read_text(encoding="utf-8")
    generated, protected = manifest.split("\n## Protected accepted inputs\n", maxsplit=1)
    kept = [line for line in generated.splitlines()
            if not line.startswith("| `README.md`") and
            not line.startswith("| `independent_mechanical_audit.txt`")]
    readme_row = (f"| `README.md` | text | {readme_path.stat().st_size} | "
                  f"`{sha256_file(readme_path)}` | lightweight Git candidate |")
    audit_row = (f"| `independent_mechanical_audit.txt` | text | {audit_path.stat().st_size} | "
                 f"`{sha256_file(audit_path)}` | lightweight Git candidate |")
    kept.extend([readme_row, audit_row])
    manifest_path.write_text("\n".join(kept) + "\n\n## Protected accepted inputs\n" + protected,
                             encoding="utf-8")
    print(f"Step-05B-11A independent verification PASS: {out}")


if __name__ == "__main__":
    main()
