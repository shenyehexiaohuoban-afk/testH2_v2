#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Independent audit for the Stage89Q penalty=1000 mechanism deep dive."""

from __future__ import annotations

import hashlib
from pathlib import Path

import numpy as np
import pandas as pd
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
RUN = ROOT / "results/task-002-stage2b-b3-smoke/stage89q-penalty1000-vs1500-long-training/run-003"
RAW = ROOT / "hourly_grid_h2/output/stage89q_penalty1000_vs1500_long_training/run-003/penalty1000"
OUT = RUN / "05_analysis/10_deep_penalty1000/15_mechanism_deep_dive"
FIG = RUN / "06_figures/09_penalty1000_mechanism_deep_dive"
BANK = RUN / "03_oos/common/oos_path_manifest.csv"
BANK_IDENTITY = RUN / "03_oos/common/bank_identity.csv"
SUMMARY = OUT / "13_summary"
TOL = 1e-7
EXPECTED_BANK_MAT_SHA = "6bf3d1190a402ded052b8d3d08ed369042236e151f562bdd9fd4db7b8ff386c6"
EXPECTED_BANK_MANIFEST_SHA = "a186e8d4ac870082d0925a05311ab8f4c5a0b70cb61b6fd06955a48a647b3941"
EXPECTED_RAW_SHA = {
    "path_summary/oos_path_summary.csv": "99ec55faba4e60e88b25d757deb1a8146515faf666d52979fe69c64362047502",
    "hourly_site/oos_hour_site.csv": "af3b3d5c4aa69e6d29b35a88008b4d82360c4b8391fc783141078f7ad68b0cda",
    "htt_od/oos_positive_htt_flows.csv": "06a6586574a155eb4588cae691898b3ebda509a79e14e64c8453918b7262fe4a",
    "grid_hourly/oos_hour_system.csv": "b9eaa83ee3e8a720f3cb5afd5d54da050c2d3ef45c434efe74f8ba8b976b63c6",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> None:
    source_hash_before = {name: sha256(RAW / name) for name in EXPECTED_RAW_SHA}
    source = pd.read_csv(RAW / "path_summary/oos_path_summary.csv")
    hourly = pd.read_csv(RAW / "hourly_site/oos_hour_site.csv")
    bank = pd.read_csv(BANK)
    bank_identity = pd.read_csv(BANK_IDENTITY).iloc[0]
    surplus = pd.read_csv(OUT / "01_surplus_timing/surplus_build_timing.csv")
    shortfall = pd.read_csv(OUT / "02_shortfall_timing/shortfall_build_timing.csv")
    recover = pd.read_csv(OUT / "03_physical_recoverability/physical_recoverability_diagnostic.csv")
    recover_summary = pd.read_csv(OUT / "03_physical_recoverability/physical_recoverability_summary.csv")
    htt_summary = pd.read_csv(OUT / "05_htt_mechanism/htt_mechanism_classification_summary.csv")
    ordinary = pd.read_csv(OUT / "08_ordinary_vs_reserve/ordinary_shortage_terminal_adequate_hourly.csv")
    cost = pd.read_csv(OUT / "09_economics/cost_components_by_mechanism_path_type.csv")
    dissipation = pd.read_csv(OUT / "10_dissipation/dissipation_mechanism_paths.csv")
    tail = pd.read_csv(OUT / "11_tail/tail_mechanism_profile.csv")
    cases = pd.read_csv(OUT / "12_case_studies/case_study_selection.csv")
    visual_audit = pd.read_csv(SUMMARY / "visual_audit.csv")
    readme = (SUMMARY / "README.md").read_text(encoding="utf-8")
    manifest_path = SUMMARY / "mechanism_deep_dive_manifest.csv"
    manifest_input = pd.read_csv(manifest_path)

    s7 = source[source.reached_stage7.eq(1)].copy()
    positive = s7[s7.target_total > TOL].copy()
    adequate = positive[positive.terminal_site_gap <= TOL].copy()
    failed = positive[positive.terminal_site_gap > TOL].copy()
    failed["site_shortfall"] = failed[[f"gap_site{i}" for i in range(1, 5)]].clip(lower=0).sum(axis=1)
    failed["site_surplus"] = failed[[f"surplus_site{i}" for i in range(1, 5)]].sum(axis=1)
    failed["total_margin"] = failed.terminal_inventory_total - failed.target_total
    pure_quantity = (failed.total_margin < -TOL) & (failed.site_surplus <= TOL)
    pure_location = (failed.total_margin >= -TOL) & (failed.site_shortfall > TOL)
    mixed = (failed.total_margin < -TOL) & (failed.site_surplus > TOL)

    rows: list[dict[str, object]] = []

    def check(name, observed, expected, passed, tolerance="exact"):
        rows.append({"check": name, "observed": observed, "expected": expected,
                     "tolerance": tolerance, "pass": bool(passed)})

    check("raw_hashes_match_accepted", source_hash_before, EXPECTED_RAW_SHA,
          source_hash_before == EXPECTED_RAW_SHA)
    check("path_bank_mat_sha", sha256(Path(bank_identity.bank_path)), EXPECTED_BANK_MAT_SHA,
          sha256(Path(bank_identity.bank_path)) == EXPECTED_BANK_MAT_SHA)
    check("path_bank_manifest_sha", sha256(BANK), EXPECTED_BANK_MANIFEST_SHA,
          sha256(BANK) == EXPECTED_BANK_MANIFEST_SHA)
    check("formal_path_count", len(source), 10000, len(source) == 10000)
    check("stage7_count", len(s7), 6124, len(s7) == 6124)
    check("positive_target_count", len(positive), 1123, len(positive) == 1123)
    check("positive_target_partition", f"{len(adequate)}+{len(failed)}", "650+473",
          len(adequate) == 650 and len(failed) == 473)
    bank_states = bank[[c for c in bank.columns if c.startswith("k_t")]].astype(int).astype(str).agg("-".join, axis=1)
    check("ordered_bank_identity", True, True,
          np.array_equal(source.path_id.to_numpy(), bank.path_id.to_numpy()) and
          np.array_equal(source.state_sequence.to_numpy(), bank_states.to_numpy()))
    observed_pmax = hourly[hourly.electrolyzer_capacity_binding.eq(1)].groupby("site").P_EL_kW.max().to_dict()
    expected_pmax = {1: 300.0, 2: 200.0, 3: 120.0, 4: 150.0}
    check("electrolyzer_Pmax_identity", observed_pmax, expected_pmax,
          all(abs(observed_pmax.get(site, np.nan) - value) <= TOL for site, value in expected_pmax.items()))
    check("surplus_path_ids_exact", len(surplus), 650,
          set(surplus.path_id) == set(adequate.path_id))
    check("shortfall_path_ids_exact", len(shortfall), 473,
          set(shortfall.path_id) == set(failed.path_id))
    merged = adequate[["path_id", "target_total", "terminal_inventory_total"]].merge(
        surplus[["path_id", "final_target_kg", "final_inventory_kg", "final_surplus_kg"]], on="path_id")
    max_surplus_error = np.max(np.abs(merged.final_surplus_kg -
                                      (merged.terminal_inventory_total - merged.target_total)))
    check("surplus_values_recomputed", max_surplus_error, f"<={TOL}", max_surplus_error <= TOL, TOL)
    max_identity_error = np.max(np.abs(failed.site_surplus - failed.site_shortfall - failed.total_margin))
    check("site_surplus_shortfall_identity", max_identity_error, f"<={TOL}", max_identity_error <= TOL, TOL)
    check("failure_mechanism_partition", f"{pure_quantity.sum()}+{pure_location.sum()}+{mixed.sum()}",
          "118+203+152", pure_quantity.sum() == 118 and pure_location.sum() == 203 and mixed.sum() == 152)
    check("recoverability_rows", len(recover), 473 * 3, len(recover) == 473 * 3)
    check("recoverability_path_ids_exact", recover.path_id.nunique(), 473,
          set(recover.path_id) == set(failed.path_id))
    allowed = {"NO", "NOT_IDENTIFIABLE"}
    check("recoverability_claim_scope", set(recover.TARGET_STILL_PHYSICALLY_REACHABLE), allowed,
          set(recover.TARGET_STILL_PHYSICALLY_REACHABLE) <= allowed)
    no_counts = recover[recover.TARGET_STILL_PHYSICALLY_REACHABLE.eq("NO")].groupby(
        "hours_before_stage7").size().to_dict()
    check("strict_unrecoverable_counts", no_counts, {16: 70, 8: 156, 4: 167},
          no_counts == {16: 70, 8: 156, 4: 167})
    check("strict_unrecoverable_monotone", [no_counts.get(x, 0) for x in (16, 8, 4)],
          "nondecreasing toward Stage7", no_counts.get(16, 0) <= no_counts.get(8, 0) <= no_counts.get(4, 0))
    check("recoverability_summary_agrees", int(recover_summary.path_count.sum()), 473 * 3,
          int(recover_summary.path_count.sum()) == 473 * 3)
    aligned = float(htt_summary.target_aligned_HTT_kg.sum() / htt_summary.total_HTT_kg.sum())
    check("pure_location_aligned_HTT_fraction", aligned, 0.295032472656,
          abs(aligned - 0.295032472656) <= 1e-12, "1e-12")
    ordinary_raw = s7[(s7.ordinary_shortage_any.eq(1)) & (s7.terminal_site_gap <= TOL)]
    ordinary_gt50 = ordinary_raw[(ordinary_raw.terminal_inventory_total - ordinary_raw.target_total) > 50]
    check("ordinary_shortage_terminal_adequate_count", len(ordinary_raw), 326, len(ordinary_raw) == 326)
    check("ordinary_shortage_surplus_gt50_count", len(ordinary_gt50), 321, len(ordinary_gt50) == 321)
    check("ordinary_output_path_ids_exact", len(ordinary), 326,
          set(ordinary.path_id) == set(ordinary_raw.path_id))
    all_cost = cost[cost.group.eq("all_10000")].iloc[0]
    check("actual_cost_mean", all_cost.mean_total_actual_operating_cost_yuan,
          source.actual_operating_cost.mean(),
          abs(all_cost.mean_total_actual_operating_cost_yuan - source.actual_operating_cost.mean()) <= TOL, TOL)
    check("cost_component_closure", cost.component_closure_max_abs_residual_yuan.max(), f"<={TOL}",
          cost.component_closure_max_abs_residual_yuan.max() <= TOL, TOL)
    check("terminal_penalty_separate", cost.terminal_penalty_label.nunique(), 1,
          cost.terminal_penalty_label.eq("MODEL_PENALTY_COMPONENT_NOT_ACTUAL_OPERATING_COST").all())
    check("dissipation_path_ids_exact", len(dissipation), 3497,
          set(dissipation.path_id) == set(source[source.physical_dissipation_a1.eq(1)].path_id))
    post_cols = ["production_after_dissipation_confirmation", "HTT_after_dissipation_confirmation",
                 "inventory_retention_after_confirmation"]
    check("no_post_termination_inference", True, True,
          dissipation[post_cols].apply(lambda col: col.str.startswith("NOT_AVAILABLE").all()).all())
    hardest5 = float(tail.loc[tail.tier.isin(["difficult4", "extreme1"]),
                                "gap_contribution_fraction"].sum())
    check("hardest5_gap_contribution", hardest5, 0.944196621992,
          abs(hardest5 - 0.944196621992) <= 1e-12, "1e-12")
    check("worst_path_3909_in_cases", 3909 in set(cases.path_id), True, 3909 in set(cases.path_id))
    top5 = set(failed.nlargest(5, "terminal_site_gap").path_id)
    check("top5_shortfall_cases_exact", len(top5), 5, top5 <= set(cases.path_id))
    check("readme_answers_20_questions", readme.count("## ") - 1, 20,
          all(f"## {i}." in readme for i in range(1, 21)))
    check("readme_stops_before_1500", "本轮到此停止，不启动penalty=1500" in readme, True,
          "本轮到此停止，不启动penalty=1500" in readme)

    expected_csv = 32
    qa_artifacts = {"independent_mechanism_audit.csv", "visual_audit.csv"}
    analysis_csvs = [path for path in OUT.rglob("*.csv") if path.name not in qa_artifacts]
    check("analysis_csv_count_before_independent_audit", len(analysis_csvs), expected_csv,
          len(analysis_csvs) == expected_csv)
    required_figures = {f"{i:02d}_" for i in range(1, 19)}
    pngs = sorted(FIG.glob("*.png"))
    numbered = {path.name[:3] for path in pngs if path.name[:2].isdigit()}
    dimensions_ok = True
    for path in pngs:
        with Image.open(path) as image:
            dimensions_ok &= image.width >= 800 and image.height >= 500
    check("numbered_figure_count", len(numbered), 18,
          len(numbered) == 18 and numbered == required_figures)
    check("contact_sheet_exists", (FIG / "contact_sheet.png").is_file(), True,
          (FIG / "contact_sheet.png").is_file())
    check("figure_dimensions", dimensions_ok, True, dimensions_ok)
    check("visual_audit_rows", len(visual_audit), 19, len(visual_audit) == 19)
    check("visual_audit_all_pass", visual_audit.result.eq("PASS").all(), True,
          visual_audit.result.eq("PASS").all())
    check("visual_audit_figure_identity", set(visual_audit.figure), {path.name for path in pngs},
          set(visual_audit.figure) == {path.name for path in pngs})
    auditable_manifest = manifest_input[manifest_input.role.ne("independent_audit")]
    missing_manifest_paths = [row.relative_path for row in auditable_manifest.itertuples()
                              if not (ROOT / row.relative_path).is_file()]
    bad_manifest_hashes = [row.relative_path for row in auditable_manifest.itertuples()
                           if (ROOT / row.relative_path).is_file() and sha256(ROOT / row.relative_path) != row.sha256]
    check("manifest_paths_exist", len(missing_manifest_paths), 0, not missing_manifest_paths)
    check("manifest_hashes_match", len(bad_manifest_hashes), 0, not bad_manifest_hashes)
    check("no_large_analysis_artifact", max(path.stat().st_size for path in OUT.rglob("*") if path.is_file()),
          "<25 MiB", all(path.stat().st_size < 25 * 1024 * 1024 for path in OUT.rglob("*") if path.is_file()))
    check("no_zero_padding", hourly.groupby("path_id").global_hour.max().equals(
          hourly.groupby("path_id").global_hour.nunique()), True,
          hourly.groupby("path_id").global_hour.max().equals(hourly.groupby("path_id").global_hour.nunique()))
    source_hash_after = {name: sha256(RAW / name) for name in EXPECTED_RAW_SHA}
    check("raw_hashes_unchanged_during_audit", source_hash_after, source_hash_before,
          source_hash_after == source_hash_before)

    qa = pd.DataFrame(rows)
    audit_path = SUMMARY / "independent_mechanism_audit.csv"
    qa.to_csv(audit_path, index=False, encoding="utf-8-sig")
    if not qa["pass"].all():
        raise RuntimeError(qa[~qa["pass"]].to_string(index=False))

    manifest = manifest_input.copy()
    relative = str(audit_path.relative_to(ROOT))
    visual_path = SUMMARY / "visual_audit.csv"
    additions = []
    for role, path in (("independent_audit", audit_path), ("manual_visual_audit", visual_path)):
        relative_path = str(path.relative_to(ROOT))
        manifest = manifest[manifest.relative_path.ne(relative_path)]
        additions.append({"role": role, "relative_path": relative_path,
                          "size_bytes": path.stat().st_size, "sha256": sha256(path)})
    manifest = pd.concat([manifest, pd.DataFrame(additions)], ignore_index=True)
    manifest.to_csv(manifest_path, index=False, encoding="utf-8-sig")
    print(f"INDEPENDENT_STAGE89Q_MECHANISM_AUDIT=PASS checks={len(qa)}")


if __name__ == "__main__":
    main()
