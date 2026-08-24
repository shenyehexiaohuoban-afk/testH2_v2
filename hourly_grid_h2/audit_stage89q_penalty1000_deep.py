#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Independent audit of Stage89Q penalty=1000 deep read-only outputs."""

from pathlib import Path

import numpy as np
import pandas as pd
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
RUN = ROOT / "results/task-002-stage2b-b3-smoke/stage89q-penalty1000-vs1500-long-training/run-003"
RAW = ROOT / "hourly_grid_h2/output/stage89q_penalty1000_vs1500_long_training/run-003/penalty1000"
OUT = RUN / "05_analysis/10_deep_penalty1000"
FIG = RUN / "06_figures/08_penalty1000_deep_analysis"
TOL = 1e-7


def main():
    source = pd.read_csv(RAW / "path_summary/oos_path_summary.csv")
    termination = pd.read_csv(OUT / "01_path_accounting/path_termination_full_accounting.csv")
    zero_positive = pd.read_csv(OUT / "02_stage7_adequate_surplus/stage7_zero_vs_positive_target.csv")
    surplus = pd.read_csv(OUT / "02_stage7_adequate_surplus/stage7_adequate_surplus_summary.csv")
    states = pd.read_csv(OUT / "03_terminal_state_35/stage7_by_terminal_state_35.csv")
    sites = pd.read_csv(OUT / "05_shortfall_sites/stage7_shortfall_by_site.csv")
    mechanisms = pd.read_csv(OUT / "05_shortfall_sites/stage7_shortfall_mechanism_groups.csv")
    tail = pd.read_csv(OUT / "10_tail/stage7_tail_full_profile.csv")
    cases = pd.read_csv(OUT / "11_cases/case_path_selection.csv")
    economics = pd.read_csv(OUT / "12_economics/economics_overall_distribution.csv")
    training = pd.read_csv(OUT / "13_training_depth/training_depth_diagnosis.csv")
    summary = pd.read_csv(OUT / "14_summary/penalty1000_full_diagnostic_summary.csv")
    readme = (OUT / "14_summary/README.md").read_text(encoding="utf-8")

    s7 = source[source.reached_stage7.eq(1)].copy()
    positive = s7[s7.target_total > TOL]
    failed = s7[s7.terminal_site_gap > TOL]
    adequate = s7[s7.terminal_site_gap <= TOL]
    rows = []

    def check(name, observed, expected, passed, tolerance="exact"):
        rows.append({"check": name, "observed": observed, "expected": expected, "tolerance": tolerance, "pass": bool(passed)})

    check("source_rows", len(source), 10000, len(source) == 10000)
    check("termination_sum", termination["count"].sum(), 10000, termination["count"].sum() == 10000)
    check("lf8_count", int(termination.loc[termination.termination_type.eq("LF8_ABSORBING"), "count"].iloc[0]), 379, int(termination.loc[termination.termination_type.eq("LF8_ABSORBING"), "count"].iloc[0]) == 379)
    check("stage7_count", len(s7), 6124, len(s7) == 6124)
    check("zero_target_count", int((s7.target_total <= TOL).sum()), 5001, int((s7.target_total <= TOL).sum()) == 5001)
    check("positive_target_count", len(positive), 1123, len(positive) == 1123)
    check("positive_target_gap_probability", positive.terminal_gap_any.mean(), 473 / 1123, abs(positive.terminal_gap_any.mean() - 473 / 1123) <= 1e-12, "1e-12")
    check("adequate_count", len(adequate), 5651, len(adequate) == 5651)
    check("surplus_identity", float(surplus.identity_max_abs_residual_kg.iloc[0]), f"<={TOL}", float(surplus.identity_max_abs_residual_kg.iloc[0]) <= TOL, TOL)
    check("terminal_state_rows", len(states), 35, len(states) == 35)
    check("terminal_state_sample_sum", int(states.path_count.sum()), 6124, int(states.path_count.sum()) == 6124)
    check("site_shortfall_denominator", sorted(sites.shortfall_path_count.unique().tolist()), [473], sites.shortfall_path_count.eq(473).all())
    check("mechanism_count_sum", int(mechanisms.path_count.sum()), 473, int(mechanisms.path_count.sum()) == 473)
    check("tail_count_sum", int(tail.N.sum()), 6124, int(tail.N.sum()) == 6124)
    check("tail_gap_contribution_sum", tail.gap_contribution_fraction_of_stage7_expected_gap.sum(), 1.0, abs(tail.gap_contribution_fraction_of_stage7_expected_gap.sum() - 1) <= 1e-10, "1e-10")
    check("worst_case_path", int(cases.loc[cases.case.eq("最严重不足"), "path_id"].iloc[0]), 3909, int(cases.loc[cases.case.eq("最严重不足"), "path_id"].iloc[0]) == 3909)
    source_cost = source.actual_operating_cost
    reported_mean = economics.loc[economics.metric.eq("actual_operating_cost"), "mean"].iloc[0]
    check("economics_mean", reported_mean, source_cost.mean(), abs(reported_mean - source_cost.mean()) <= 1e-7, "1e-7")
    check("training_mixed_assessment", training.assessment.astype(str).str.contains("MIXED_STABILITY").any(), True, training.assessment.astype(str).str.contains("MIXED_STABILITY").any())
    check("summary_has_positive_target_rate", summary.metric.eq("positive_target_adequacy_rate").any(), True, summary.metric.eq("positive_target_adequacy_rate").any())
    check("readme_no_convergence_claim", "FULLY_CONVERGED = NO" in readme, True, "FULLY_CONVERGED = NO" in readme)
    check("readme_no_penalty1500_start", "不启动penalty=1500" in readme, True, "不启动penalty=1500" in readme)

    required = [
        "01_path_accounting/path_termination_full_accounting.csv",
        "02_stage7_adequate_surplus/stage7_zero_vs_positive_target.csv",
        "02_stage7_adequate_surplus/stage7_adequate_surplus_summary.csv",
        "02_stage7_adequate_surplus/stage7_surplus_absolute_bins.csv",
        "02_stage7_adequate_surplus/stage7_surplus_ratio_bins.csv",
        "02_stage7_adequate_surplus/stage7_site_surplus_summary.csv",
        "03_terminal_state_35/stage7_by_terminal_state_35.csv",
        "04_arrival_timing/stage7_by_arrival_stage_detailed.csv",
        "04_arrival_timing/stage7_arrival_by_intensity.csv",
        "04_arrival_timing/stage7_time_to_adequacy.csv",
        "05_shortfall_sites/stage7_shortfall_by_site.csv",
        "05_shortfall_sites/stage7_shortfall_site_combinations.csv",
        "05_shortfall_sites/stage7_shortfall_mechanism_groups.csv",
        "06_spatial_htt/spatial_mismatch_timeline.csv",
        "06_spatial_htt/htt_helpfulness_summary.csv",
        "06_spatial_htt/pure_location_failure_diagnosis.csv",
        "07_catchup_limits/shortfall_catchup_feasibility_diagnostic.csv",
        "07_catchup_limits/electrolyzer_binding_by_site.csv",
        "07_catchup_limits/voltage_binding_diagnosis.csv",
        "08_ordinary_shortage/ordinary_shortage_detailed.csv",
        "08_ordinary_shortage/ordinary_vs_terminal_tradeoff.csv",
        "08_ordinary_shortage/ordinary_shortage_mechanism.csv",
        "09_dissipation/dissipation_detailed_summary.csv",
        "09_dissipation/preventive_inventory_exposure.csv",
        "10_tail/stage7_tail_full_profile.csv",
        "11_cases/case_path_selection.csv",
        "12_economics/economics_cost_definition_audit.md",
        "12_economics/economics_overall_distribution.csv",
        "12_economics/economics_by_path_group.csv",
        "12_economics/cost_vs_terminal_outcome.csv",
        "12_economics/model_penalty_components.csv",
        "13_training_depth/training_depth_diagnosis.csv",
        "14_summary/penalty1000_full_diagnostic_summary.csv",
        "14_summary/README.md",
    ]
    missing = [name for name in required if not (OUT / name).is_file()]
    check("required_output_files", len(missing), 0, not missing)
    pngs = sorted(FIG.glob("*.png"))
    dimensions_ok = True
    for png in pngs:
        with Image.open(png) as image:
            dimensions_ok &= image.width >= 800 and image.height >= 500
    check("figure_count", len(pngs), 20, len(pngs) == 20)
    check("figure_dimensions", dimensions_ok, True, dimensions_ok)

    qa = pd.DataFrame(rows)
    qa.to_csv(OUT / "14_summary/independent_deep_analysis_audit.csv", index=False, encoding="utf-8-sig")
    if not qa["pass"].all():
        raise RuntimeError(qa[~qa["pass"]].to_string(index=False))
    print(f"INDEPENDENT_STAGE89Q_DEEP_AUDIT=PASS checks={len(qa)}")


if __name__ == "__main__":
    main()
