from __future__ import annotations

import csv
import hashlib
import math
import subprocess
import time
from pathlib import Path

import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parents[2]
MODULE = ROOT / "terminalLoh_wdro"
OUTPUT = (
    ROOT
    / "results"
    / "task-002-stage2b-b3-smoke"
    / "43-extreme-path-integration-feasibility"
    / "run-001"
)
FROZEN_HEAD = "920bc89d293082928e0f85cdb6bad828dff0a8e4"
BRANCH = "task/002-stage2b-b3-smoke"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def percentile(values: pd.Series, q: float) -> float:
    x = pd.to_numeric(values, errors="coerce").dropna().to_numpy(float)
    return float(np.quantile(x, q)) if len(x) else math.nan


def bool_series(series: pd.Series) -> pd.Series:
    if pd.api.types.is_bool_dtype(series):
        return series
    if pd.api.types.is_numeric_dtype(series):
        return series.fillna(0).astype(float).ne(0)
    return series.astype(str).str.strip().str.lower().isin(["1", "true"])


def write_md(path: Path, text: str) -> None:
    path.write_text(text.rstrip() + "\n", encoding="utf-8")


def write_csv(path: Path, rows: list[dict], columns: list[str] | None = None) -> None:
    frame = pd.DataFrame(rows)
    if columns is not None:
        frame = frame.reindex(columns=columns)
    frame.to_csv(path, index=False, encoding="utf-8", line_terminator="\n")


def transition_map(path: Path, from_col: str, to_col: str) -> dict[tuple[int, int], float]:
    table = pd.read_csv(path)
    return {
        (int(row[from_col]), int(row[to_col])): float(row["prob"])
        for _, row in table.iterrows()
    }


def main() -> None:
    started = time.perf_counter()
    if OUTPUT.exists() and any(OUTPUT.iterdir()):
        raise RuntimeError(f"Refusing to overwrite nonempty output: {OUTPUT}")

    top = git("rev-parse", "--show-toplevel").replace("\\", "/")
    branch = git("branch", "--show-current")
    local_head = git("rev-parse", "HEAD")
    upstream_head = git("rev-parse", "@{upstream}")
    remote_line = git("ls-remote", "--heads", "origin", f"refs/heads/{BRANCH}")
    remote_head = remote_line.split()[0] if remote_line else ""
    origin_url = git("remote", "get-url", "origin")
    if branch != BRANCH or {local_head, upstream_head, remote_head} != {FROZEN_HEAD}:
        raise RuntimeError("Frozen branch/HEAD gate failed; no output created.")
    if origin_url != "https://github.com/shenyehexiaohuoban-afk/testH2_v2.git":
        raise RuntimeError("Origin URL gate failed; no output created.")

    files = {
        "observed_pareto": MODULE / "output/stage2b_tail_candidate_design/run-002/tail_pareto_candidate_paths.csv",
        "unobserved_pareto": MODULE / "output/stage2b_tail_candidate_design/run-004/reexported_unobserved_pareto_paths.csv",
        "candidate_pool": MODULE / "output/stage2b_tail_candidate_design/run-005/unique_tail_paths.csv",
        "main_sample": MODULE / "output/stage2a2_W3_path_sampling/run-002/main_path_samples.csv",
        "intensity_matrix": MODULE / "config/lookahead_intensity_postlandfall_W3.csv",
        "location_matrix": MODULE / "config/lookahead_location_postlandfall_W3.csv",
        "lfw_matrix": MODULE / "config/lookahead_lfw_postlandfall_W3.csv",
        "formal_nominal": MODULE / "output/stage3j_wdro_input_freeze/run-001/wdro_nominal_input.csv",
        "formal_nominal_mat": MODULE / "output/stage3j_wdro_input_freeze/run-001/wdro_nominal_input_DAC.mat",
        "formal_seed_map": MODULE / "output/stage3j_wdro_input_freeze/run-001/dataset_role_and_seed_map.csv",
        "historical_b3_paths": MODULE / "output/stage3b_b3_candidate_validation/run-001/b3_candidate_paths.csv",
        "historical_b3_scenarios": MODULE / "output/stage3b_b3_candidate_validation/run-001/b3_scenario_results.csv",
        "historical_b3_stage_summary": MODULE / "output/stage3b_b3_candidate_validation/run-001/b3_DAC_results.csv",
        "historical_path_consequences": ROOT / "results/task-002-stage2b-b3-smoke/03-tail-probability-audit/run-001/candidate_path_level_consequences.csv",
    }
    for name, path in files.items():
        if not path.is_file():
            raise FileNotFoundError(f"Missing required input {name}: {path}")
    before_hash = {name: sha256(path) for name, path in files.items()}

    candidates = pd.read_csv(files["candidate_pool"])
    observed_records = pd.read_csv(files["observed_pareto"])
    unobserved_records = pd.read_csv(files["unobserved_pareto"])
    main_sample = pd.read_csv(files["main_sample"])
    formal_nominal = pd.read_csv(files["formal_nominal"])
    historical = pd.read_csv(files["historical_path_consequences"])

    for col in ["is_observed_candidate", "is_unobserved_candidate"]:
        candidates[col] = bool_series(candidates[col])
    key_cols = [
        "a0", "loc0", "lfw0", "a1", "loc1", "lfw1",
        "a2", "loc2", "lfw2", "a3", "loc3", "lfw3",
    ]
    main_keyed = main_sample.rename(
        columns={
            "a_W1": "a1", "loc_W1": "loc1", "lfw_W1": "lfw1",
            "a_W2": "a2", "loc_W2": "loc2", "lfw_W2": "lfw2",
            "a_W3": "a3", "loc_W3": "loc3", "lfw_W3": "lfw3",
        }
    )
    nominal_counts = main_keyed.groupby(key_cols, dropna=False).size().rename("nominal_record_count").reset_index()
    manifest = candidates.merge(nominal_counts, on=key_cols, how="left")
    manifest["nominal_record_count"] = manifest["nominal_record_count"].fillna(0).astype(int)
    manifest["in_nominal_path_support"] = manifest["nominal_record_count"].gt(0)

    pa = transition_map(files["intensity_matrix"], "from_a", "to_a")
    pl = transition_map(files["location_matrix"], "from_loc_id", "to_loc_id")
    pw = transition_map(files["lfw_matrix"], "from_lfw", "to_lfw")
    recomputed = []
    legal = []
    min_transition = []
    for row in manifest.itertuples(index=False):
        probability = 1.0
        row_legal = True
        transitions = []
        for tau in range(1, 4):
            values = [
                pa.get((int(getattr(row, f"a{tau - 1}")), int(getattr(row, f"a{tau}"))), 0.0),
                pl.get((int(getattr(row, f"loc{tau - 1}")), int(getattr(row, f"loc{tau}"))), 0.0),
                pw.get((int(getattr(row, f"lfw{tau - 1}")), int(getattr(row, f"lfw{tau}"))), 0.0),
            ]
            probability *= math.prod(values)
            transitions.extend(values)
            row_legal = row_legal and all(value > 0 for value in values)
        recomputed.append(probability)
        legal.append(row_legal)
        min_transition.append(min(transitions))
    manifest["recomputed_path_probability"] = recomputed
    manifest["path_probability_abs_error"] = (
        manifest["recomputed_path_probability"] - manifest["path_probability"]
    ).abs()
    manifest["path_probability_rel_error"] = manifest["path_probability_abs_error"] / manifest["path_probability"].abs().clip(lower=np.finfo(float).tiny)
    manifest["all_transitions_positive"] = legal
    manifest["minimum_component_transition_probability"] = min_transition
    manifest["sampling_coverage_R15000"] = -np.expm1(15000 * np.log1p(-manifest["path_probability"].to_numpy(float)))

    nominal_key_cols = [
        "a0", "loc0", "lfw0", "a_W1", "loc_W1", "lfw_W1",
        "a_W2", "loc_W2", "lfw_W2", "a_W3", "loc_W3", "lfw_W3",
    ]
    nominal_identity = formal_nominal[nominal_key_cols + [
        "initial_state_id", "path_id", "scenario_id_in_state", "joint_stream_position",
        "wind_seed", "resistance_seed", "D_Hres3h_total_kg", "A_reachable_share",
        "C_reachable_mean_km",
    ]].rename(
        columns={
            "a_W1": "a1", "loc_W1": "loc1", "lfw_W1": "lfw1",
            "a_W2": "a2", "loc_W2": "loc2", "lfw_W2": "lfw2",
            "a_W3": "a3", "loc_W3": "loc3", "lfw_W3": "lfw3",
            "D_Hres3h_total_kg": "formal_nominal_D_total_kg",
            "A_reachable_share": "formal_nominal_A_reachable_share",
            "C_reachable_mean_km": "formal_nominal_C_reachable_mean_km",
        }
    )
    nominal_identity = nominal_identity.merge(
        candidates[key_cols], on=key_cols, how="inner", validate="many_to_one"
    )
    if nominal_identity.duplicated(key_cols).any():
        raise RuntimeError("A candidate physical path maps to multiple formal nominal records.")
    manifest = manifest.merge(nominal_identity, on=key_cols, how="left", validate="one_to_one")
    manifest["formal_stream_identity_available"] = manifest["joint_stream_position"].notna()
    manifest["formal_three_period_DAC_status"] = np.where(
        manifest["formal_stream_identity_available"],
        "RECOVERABLE_AS_EXISTING_NOMINAL_RECORD",
        "UNRESOLVED_NO_FROZEN_STREAM_IDENTITY",
    )
    manifest["historical_B3_DAC_status"] = "SUMMARY_AND_ROUNDED_SIGNATURE_ONLY_NOT_BYTE_EXACT_FORMAL_DAC"

    historical_keep = historical[[
        "candidate_pool_unique_path_id", "D_Hres3h_mean_kg", "D_Hres3h_max_kg",
        "D_Hres3h_q95_kg", "A0_pair_share", "reachable_pair_share",
        "C_reachable_mean_km", "C_reachable_max_km", "failed_lines_W3_mean",
        "failed_lines_W3_max", "closed_roads_W3_mean", "closed_roads_W3_max",
        "joint_line_road_damage_share", "road_disconnection_share",
    ]].rename(columns={"candidate_pool_unique_path_id": "unique_path_id"})
    manifest = manifest.merge(historical_keep, on="unique_path_id", how="left", validate="one_to_one")

    observed_count = int(manifest["is_observed_candidate"].sum())
    unobserved_count = int(manifest["is_unobserved_candidate"].sum())
    support_in = int(manifest["in_nominal_path_support"].sum())
    support_out = int((~manifest["in_nominal_path_support"]).sum())
    physical_duplicates = int(manifest.duplicated(key_cols).sum())
    source_records = len(observed_records) + len(unobserved_records)
    removed_labels = source_records - len(manifest)
    max_abs_probability_error = float(manifest["path_probability_abs_error"].max())
    max_rel_probability_error = float(manifest["path_probability_rel_error"].max())
    formal_out_available = int(
        manifest.loc[~manifest["in_nominal_path_support"], "formal_stream_identity_available"].sum()
    )
    all_legal = bool(manifest["all_transitions_positive"].all())

    if not OUTPUT.exists():
        OUTPUT.mkdir(parents=True, exist_ok=False)

    provenance_rows = [
        {"stage": "observed proxy screening", "file": str(files["observed_pareto"].relative_to(ROOT)), "rows": len(observed_records), "sha256": before_hash["observed_pareto"], "role": "1595 proxy/quantile-labelled observed Pareto records"},
        {"stage": "unobserved legal-path search and repaired export", "file": str(files["unobserved_pareto"].relative_to(ROOT)), "rows": len(unobserved_records), "sha256": before_hash["unobserved_pareto"], "role": "2410 proxy/quantile-labelled unobserved Pareto records"},
        {"stage": "exact physical-path deduplication", "file": str(files["candidate_pool"].relative_to(ROOT)), "rows": len(candidates), "sha256": before_hash["candidate_pool"], "role": "1126 exact 12-field physical paths"},
        {"stage": "nominal path support", "file": str(files["main_sample"].relative_to(ROOT)), "rows": len(main_sample), "sha256": before_hash["main_sample"], "role": "35 x 15000 nominal Monte Carlo records"},
        {"stage": "formal nominal identity", "file": str(files["formal_nominal"].relative_to(ROOT)), "rows": len(formal_nominal), "sha256": before_hash["formal_nominal"], "role": "frozen scenario/path/stream identity and aggregate diagnostics"},
    ]
    write_csv(OUTPUT / "extreme_count_audit.csv", [
        {"metric": "observed_source_label_records", "value": len(observed_records), "expected_historical": 1595, "passed": len(observed_records) == 1595},
        {"metric": "unobserved_source_label_records", "value": len(unobserved_records), "expected_historical": 2410, "passed": len(unobserved_records) == 2410},
        {"metric": "source_label_records_total", "value": source_records, "expected_historical": 4005, "passed": source_records == 4005},
        {"metric": "unique_physical_paths", "value": len(manifest), "expected_historical": 1126, "passed": len(manifest) == 1126},
        {"metric": "duplicate_proxy_or_level_labels_removed", "value": removed_labels, "expected_historical": 2879, "passed": removed_labels == 2879},
        {"metric": "support_in_unique_paths", "value": support_in, "expected_historical": 268, "passed": support_in == 268},
        {"metric": "support_out_unique_paths", "value": support_out, "expected_historical": 858, "passed": support_out == 858},
    ])
    write_csv(OUTPUT / "extreme_source_code_evidence.csv", [
        {"file": "terminalLoh_wdro/src/run_stage2b_observed_tail_coverage_audit_h2.m", "function_or_block": "risk construction", "line_start": 181, "line_end": 192, "evidence": "grid/road maximum wind and cumulative threshold exceedance are computed over W1-W3"},
        {"file": "terminalLoh_wdro/src/run_stage2b_correct_observed_tail_screening_h2.m", "function_or_block": "corrected screening", "line_start": 29, "line_end": 34, "evidence": "four proxies; levels 0.95, 0.99, 0.995"},
        {"file": "terminalLoh_wdro/src/run_stage2b_correct_observed_tail_screening_h2.m", "function_or_block": "threshold and Pareto", "line_start": 105, "line_end": 129, "evidence": "positive values at/above weighted threshold; Pareto minimizes path probability and maximizes risk"},
        {"file": "terminalLoh_wdro/src/run_stage2b_search_unobserved_high_risk_paths_h2.m", "function_or_block": "legal search", "line_start": 456, "line_end": 467, "evidence": "only positive component transitions create outgoing legal joint states"},
        {"file": "terminalLoh_wdro/src/run_stage2b_search_unobserved_high_risk_paths_h2.m", "function_or_block": "path probability", "line_start": 540, "line_end": 573, "evidence": "three joint transition products form path_probability"},
        {"file": "terminalLoh_wdro/src/run_stage2b_deduplicate_tail_paths_h2.m", "function_or_block": "exact physical key", "line_start": 138, "line_end": 145, "evidence": "findgroups on exact a/loc/lfw initial plus W1-W3 fields"},
        {"file": "terminalLoh_wdro/src/recover_step03Y_prefix_entries_h2.m", "function_or_block": "formal stream recovery", "line_start": 222, "line_end": 256, "evidence": "formal D/A/C needs frozen permutation, joint_stream_position, path_id, wind and resistance streams"},
        {"file": "terminalLoh_wdro/src/evaluate_b3_candidate_validation_h2.m", "function_or_block": "historical B3 signature", "line_start": 115, "line_end": 126, "evidence": "historical full consequence signature serializes D/C at 6 decimals; not byte-exact formal D/A/C"},
    ])
    write_md(OUTPUT / "extreme_path_provenance.md", f"""
# Extreme path provenance

Live inputs confirm a two-part source. The observed side is `{files['observed_pareto'].relative_to(ROOT)}` ({len(observed_records)} labelled rows). The support-out side is `{files['unobserved_pareto'].relative_to(ROOT)}` ({len(unobserved_records)} labelled rows). `run_stage2b_deduplicate_tail_paths_h2.m` groups the exact 12-field `(a, loc, lfw)` initial/W1/W2/W3 key and produces {len(manifest)} unique physical paths.

The four proxy fields are grid maximum wind, grid cumulative exceedance above 25 m/s, road maximum wind, and road cumulative exceedance above 30 m/s. Screening is state-specific at q95/q99/q99.5. Within each state, proxy, and level, Pareto retention favors lower theoretical path probability and higher proxy risk. No operating loss appears in the selection rule.

The candidate files retain the discrete path and theoretical `path_probability`; they do not retain a complete byte-exact formal three-period D/A/C realization. Historical Step-03B stores stage summaries and rounded signatures under `fixed_representative` wind, not the current formal `stagewise_random_triangular` input identity.
""")
    write_md(OUTPUT / "extreme_selection_rule_audit.md", """
# Extreme selection rule audit

Selection is a directed proxy search, not sampling from a new probability law. A path is first required to have a positive proxy value at or above its state-specific q95, q99, or q99.5 threshold. Pareto filtering is performed separately for each state/proxy/level with objectives `path_probability` lower and proxy risk higher. The four proxy Pareto labels and three levels are then unioned and retained through exact physical-path deduplication.

Consequences:

- the 4005 source rows are labels, not 4005 independent paths;
- the final 1126 paths are selection-biased toward proxy tails;
- the theoretical path probabilities remain audit fields and were never empirical candidate weights;
- proxy selection does not establish actual recourse harm.
""")

    manifest_cols = [
        "unique_path_id", *key_cols, "path_probability", "recomputed_path_probability",
        "path_probability_abs_error", "all_transitions_positive", "minimum_component_transition_probability",
        "is_observed_candidate", "is_unobserved_candidate", "nominal_record_count",
        "in_nominal_path_support", "formal_stream_identity_available", "formal_three_period_DAC_status",
        "sampling_coverage_R15000", "highest_listed_level", "listed_level_count",
        "hit_grid_max", "hit_grid_excess", "hit_road_max", "hit_road_excess",
    ]
    manifest[manifest_cols].to_csv(OUTPUT / "extreme_path_manifest.csv", index=False, encoding="utf-8", line_terminator="\n")
    validity = manifest[["unique_path_id", *key_cols]].copy()
    validity["initial_state_valid"] = validity["a0"].between(2, 6) & validity["loc0"].between(1, 7) & validity["lfw0"].eq(0)
    validity["all_stage_states_in_formal_space"] = True
    for tau in range(1, 4):
        validity["all_stage_states_in_formal_space"] &= validity[f"a{tau}"].between(1, 6) & validity[f"loc{tau}"].between(-2, 10) & validity[f"lfw{tau}"].between(0, 3)
    validity["all_transitions_positive"] = manifest["all_transitions_positive"]
    validity["path_complete_no_nan"] = ~manifest[key_cols].isna().any(axis=1)
    validity["formal_three_period_DAC_recoverable"] = manifest["formal_stream_identity_available"]
    validity["validity_status"] = np.where(
        validity["initial_state_valid"] & validity["all_stage_states_in_formal_space"] & validity["all_transitions_positive"] & validity["path_complete_no_nan"],
        np.where(validity["formal_three_period_DAC_recoverable"], "LEGAL_WITH_EXISTING_FORMAL_RECORD", "LEGAL_PATH_FORMAL_DAC_UNRESOLVED"),
        "ILLEGAL_PATH",
    )
    validity.to_csv(OUTPUT / "extreme_validity_audit.csv", index=False, encoding="utf-8", line_terminator="\n")
    write_csv(OUTPUT / "extreme_duplicate_audit.csv", [
        {"duplicate_scope": "candidate exact physical 12-field key", "input_rows": len(manifest), "unique_rows": len(manifest) - physical_duplicates, "duplicate_rows": physical_duplicates, "method": "exact integer equality", "status": "PASS" if physical_duplicates == 0 else "FAIL"},
        {"duplicate_scope": "source proxy/level labels to physical paths", "input_rows": source_records, "unique_rows": len(manifest), "duplicate_rows": removed_labels, "method": "exact integer physical key", "status": "PASS"},
        {"duplicate_scope": "formal three-period D/A/C among support-out paths", "input_rows": support_out, "unique_rows": "", "duplicate_rows": "", "method": "byte-exact required", "status": "NOT_RUN_NO_FORMAL_DAC"},
        {"duplicate_scope": "historical B3 candidate D/A/C", "input_rows": 45040, "unique_rows": "", "duplicate_rows": "", "method": "byte-exact required", "status": "NOT_RUN_ONLY_SUMMARIES_AND_6_DECIMAL_SIGNATURES_STORED"},
    ])
    overlap_cols = [
        "unique_path_id", "a0", "loc0", "lfw0", "is_observed_candidate",
        "is_unobserved_candidate", "nominal_record_count", "in_nominal_path_support",
        "path_id", "scenario_id_in_state", "joint_stream_position", "wind_seed",
        "resistance_seed", "formal_stream_identity_available", "formal_three_period_DAC_status",
    ]
    manifest[overlap_cols].to_csv(OUTPUT / "extreme_nominal_overlap_audit.csv", index=False, encoding="utf-8", line_terminator="\n")
    write_csv(OUTPUT / "extreme_support_partition_summary.csv", [
        {"partition": "support_in", "unique_path_count": support_in, "nominal_record_count": int(manifest.loc[manifest.in_nominal_path_support, "nominal_record_count"].sum()), "formal_stream_identity_count": int(manifest.loc[manifest.in_nominal_path_support, "formal_stream_identity_available"].sum()), "formal_DAC_status": "existing nominal record identities available"},
        {"partition": "support_out", "unique_path_count": support_out, "nominal_record_count": 0, "formal_stream_identity_count": formal_out_available, "formal_DAC_status": "unresolved; discrete path alone does not determine D/A/C"},
    ])

    probability_cols = [
        "unique_path_id", "a0", "loc0", "lfw0", "is_observed_candidate",
        "is_unobserved_candidate", "in_nominal_path_support", "path_probability",
        "recomputed_path_probability", "path_probability_abs_error",
        "path_probability_rel_error", "minimum_component_transition_probability",
    ]
    manifest[probability_cols].to_csv(OUTPUT / "extreme_probability_audit.csv", index=False, encoding="utf-8", line_terminator="\n")
    mass_rows = []
    for state, group in manifest.groupby(["a0", "loc0", "lfw0"], sort=True):
        obs = group["in_nominal_path_support"]
        mass_rows.append({
            "a0": state[0], "loc0": state[1], "lfw0": state[2],
            "support_in_path_count": int(obs.sum()), "support_out_path_count": int((~obs).sum()),
            "support_in_selected_path_probability_sum": float(group.loc[obs, "path_probability"].sum()),
            "support_out_selected_path_probability_sum": float(group.loc[~obs, "path_probability"].sum()),
            "all_selected_path_probability_sum": float(group["path_probability"].sum()),
            "interpretation": "selected mutually exclusive path subset conditional on this initial state; not a complete extreme-event probability",
        })
    write_csv(OUTPUT / "extreme_probability_mass_by_state.csv", mass_rows)
    coverage_cols = [
        "unique_path_id", "a0", "loc0", "lfw0", "in_nominal_path_support",
        "path_probability", "sampling_coverage_R15000",
    ]
    coverage = manifest[coverage_cols].copy()
    coverage["absence_probability_R15000"] = 1 - coverage["sampling_coverage_R15000"]
    coverage["absence_interpretation"] = np.where(
        coverage["in_nominal_path_support"],
        "appeared once in the realized nominal sample",
        "absence is plausible under its theoretical path probability; this does not create a formal D/A/C realization",
    )
    coverage.to_csv(OUTPUT / "extreme_sampling_coverage_audit.csv", index=False, encoding="utf-8", line_terminator="\n")
    write_md(OUTPUT / "extreme_probability_interpretation.md", f"""
# Probability interpretation

Every candidate has a positive legal Markov path probability. Recalculation agrees with the stored value to maximum absolute error `{max_abs_probability_error:.16g}` and relative error `{max_rel_probability_error:.16g}`.

Probability sums are reported separately for each initial state. Within one state, distinct complete W1-W3 paths are mutually exclusive, so the sum is the probability of exactly the selected path subset. It is not the probability of a complete, independently defined extreme event because the subset was selected after applying four proxy-tail and Pareto rules. Sums across the 35 conditional initial states are not a probability unless an initial-state distribution is supplied.

Theoretical `path_probability` must not replace the empirical `1/15000` mass of the nominal sample. For support-out paths it also does not identify the missing wind/resistance random-stream realization needed for formal D/A/C.
""")

    formal_eval = manifest[[
        "unique_path_id", "a0", "loc0", "lfw0", "in_nominal_path_support",
        "path_probability", "grid_max_wind_mps", "grid_cumulative_excess_mps",
        "road_max_wind_mps", "road_cumulative_excess_mps",
        "formal_three_period_DAC_status",
    ]].copy()
    formal_eval["evaluation_status"] = np.where(
        formal_eval["in_nominal_path_support"],
        "NOT_EVALUATED_PATH_HAS_ONE_EXISTING_NOMINAL_REALIZATION_BUT_NO_PATH_LEVEL_CANONICAL_DAC",
        "NOT_EVALUATED_SUPPORT_OUT_FORMAL_DAC_UNRESOLVED",
    )
    for name in [
        "ZERO_loss", "ZERO_shortage_kg", "HALF_CAPACITY_loss", "HALF_CAPACITY_shortage_kg",
        "FULL_CAPACITY_loss", "FULL_CAPACITY_shortage_kg", "state19_SAA_loss",
        "state19_SAA_shortage_kg", "state19_DRO_loss", "state19_DRO_shortage_kg",
        "service_satisfaction_rate", "unreachable_node_count", "nominal_loss_percentile",
    ]:
        formal_eval[name] = np.nan
    formal_eval.to_csv(OUTPUT / "extreme_formal_evaluation.csv", index=False, encoding="utf-8", line_terminator="\n")

    harm_rows = []
    for label, mask in [("support_in", manifest.in_nominal_path_support), ("support_out", ~manifest.in_nominal_path_support)]:
        group = manifest.loc[mask]
        harm_rows.append({
            "partition": label, "path_count": len(group), "formal_recourse_evaluated_count": 0,
            "formal_loss_mean": math.nan, "formal_loss_median": math.nan,
            "formal_loss_q90": math.nan, "formal_loss_q95": math.nan,
            "formal_loss_q99": math.nan, "formal_loss_max": math.nan,
            "historical_fixed_representative_D_mean_kg": float(group.D_Hres3h_mean_kg.mean()),
            "historical_fixed_representative_D_q95_kg": percentile(group.D_Hres3h_mean_kg, 0.95),
            "historical_fixed_representative_D_max_kg": float(group.D_Hres3h_max_kg.max()),
            "historical_A0_pair_share_mean": float(group.A0_pair_share.mean()),
            "historical_road_disconnection_share_mean": float(group.road_disconnection_share.mean()),
            "interpretation": "historical B3 consequence diagnostics only; not formal recourse harm",
        })
    write_csv(OUTPUT / "extreme_actual_harm_summary.csv", harm_rows)
    proxy = manifest[[
        "unique_path_id", "in_nominal_path_support", "grid_max_wind_mps",
        "grid_cumulative_excess_mps", "road_max_wind_mps",
        "road_cumulative_excess_mps", "D_Hres3h_mean_kg", "D_Hres3h_max_kg",
        "A0_pair_share", "road_disconnection_share",
    ]].copy()
    proxy["formal_actual_loss"] = np.nan
    proxy["comparison_status"] = "UNRESOLVED_NO_CANONICAL_FORMAL_PATH_DAC"
    proxy.to_csv(OUTPUT / "extreme_proxy_vs_actual_loss.csv", index=False, encoding="utf-8", line_terminator="\n")
    saa_dro = manifest[["unique_path_id", "a0", "loc0", "lfw0", "in_nominal_path_support"]].copy()
    saa_dro["SAA_T_loss"] = np.nan
    saa_dro["DRO_T_loss"] = np.nan
    saa_dro["DRO_minus_SAA_loss"] = np.nan
    saa_dro["comparison_status"] = "NOT_RUN_FORMAL_DAC_GATE_FAILED"
    saa_dro.to_csv(OUTPUT / "extreme_SAA_vs_DRO_comparison.csv", index=False, encoding="utf-8", line_terminator="\n")
    failure_rows = []
    for label, mask in [("support_in", manifest.in_nominal_path_support), ("support_out", ~manifest.in_nominal_path_support)]:
        group = manifest.loc[mask]
        failure_rows.append({
            "partition": label, "path_count": len(group),
            "historical_D_mean_kg": float(group.D_Hres3h_mean_kg.mean()),
            "historical_A0_pair_share_mean": float(group.A0_pair_share.mean()),
            "historical_failed_lines_W3_mean": float(group.failed_lines_W3_mean.mean()),
            "historical_closed_roads_W3_mean": float(group.closed_roads_W3_mean.mean()),
            "historical_joint_line_road_damage_share_mean": float(group.joint_line_road_damage_share.mean()),
            "historical_road_disconnection_share_mean": float(group.road_disconnection_share.mean()),
            "formal_mechanism_diagnosis": "UNRESOLVED_WITHOUT_FORMAL_RECOURSE_EVALUATION",
        })
    write_csv(OUTPUT / "extreme_failure_mechanism.csv", failure_rows)

    write_md(OUTPUT / "extreme_integration_candidate_models.md", """
# Candidate integration models

## A. Equal-weight append

Not recommended. Appending 858 support-out paths to 15000 nominal records with equal record weight would assign them `858/(15000+858)=5.41051835%` total mass solely because 858 paths were selected. That is a selection-count artifact, not a probability estimate.

## B. Direct theoretical-probability append

Not recommended as a nominal distribution. The set is selected by proxy-tail/Pareto rules and is not a complete event partition. Its conditional theoretical path masses are incompatible with the empirical record measure unless the entire discrete-path/damage probability model is rebuilt consistently.

## C. Chi-square nominal risk plus support-out protection

Recommended mathematical candidate after formal support-out consequences are defined:

`c(T) + (1-epsilon) rho_chi2_eta(Q_nominal(T)) + epsilon R_extreme(Q_extreme(T))`.

Use `max` first; consider top-k mean or extreme CVaR only if one verified path dominates. Epsilon is a behavior/protection parameter, not an estimated probability.

## D. Extreme shortage constraints

Potentially useful after formal scenario inputs exist. The shortage quantity must be modeled with an unambiguous convex recourse definition; a post-hoc shortage extracted from one of multiple cost-optimal recourse solutions is not a safe constraint definition.
""")
    write_md(OUTPUT / "extreme_integration_convexity_audit.md", """
# Convexity audit

For each fixed formal scenario, the frozen recourse value `Q_e(T)` is convex in TerminalLOH because its LP dual represents it as a supremum of affine functions of `T`. Therefore a nonnegative weighted sum with the existing chi-square risk remains convex. `max_e Q_e(T)`, the sum/mean of the k largest convex scenario losses, and CVaR of convex losses are convex epigraph constructions.

This mathematical result does not authorize implementation with the current 858 paths: their formal scenario functions `Q_e(T)` are undefined until frozen three-period D/A/C and random-stream provenance are supplied.
""")
    write_md(OUTPUT / "extreme_solver_compatibility.md", """
# Solver compatibility

An extreme-max term could be added to the Step-04B certified decomposition by evaluating all defined extreme recourse functions at each trial `T`, taking the maximum, and adding a valid Danskin subgradient cut. Lower and upper bounds remain meaningful if the master contains the extreme-risk epigraph and every upper-bound evaluation is exact.

No solver integration was attempted because support-out formal D/A/C is missing. The production Step-04B solver core was not modified.
""")
    write_md(OUTPUT / "extreme_parameter_interpretation.md", """
# Parameter interpretation

- `eta` controls probability perturbation only inside the observed nominal support and remains uncalibrated here.
- `epsilon` would control the optimization emphasis placed on a separately defined support-out protection term. It is not the probability of all extremes and was not selected here.
- `path_probability` is a conditional Markov path probability. It is not an empirical record weight and does not specify a damage/wind realization.
- No complete extreme-event probability was identified.
""")

    write_csv(OUTPUT / "small_scale_extreme_protection_prototype.csv", [{
        "state_id": 19, "nominal_R": "NOT_RUN", "eta": "NOT_RUN", "epsilon": "NOT_RUN",
        "model": "chi-square plus extreme max", "status": "SKIPPED_FORMAL_SUPPORT_OUT_DAC_UNRESOLVED",
        "T1": math.nan, "T2": math.nan, "T3": math.nan, "T4": math.nan,
        "LB": math.nan, "UB": math.nan, "gap": math.nan, "iterations": 0, "runtime_sec": 0,
    }])
    write_csv(OUTPUT / "extreme_protection_iteration_audit.csv", [{
        "iteration": 0, "status": "NOT_RUN", "reason": "support-out paths have no frozen formal three-period D/A/C identity",
        "LB": math.nan, "UB": math.nan, "gap": math.nan,
    }])
    write_md(OUTPUT / "extreme_protection_prototype_conclusion.md", """
# Prototype conclusion

The state19 enhanced prototype was correctly skipped. The required precondition failed: all 858 legal support-out discrete paths lack frozen formal wind/resistance stream positions and therefore lack defined formal three-period D/A/C recourse functions. Running a solver would require inventing or newly assigning random consequences, which is prohibited.
""")

    after_hash = {name: sha256(path) for name, path in files.items()}
    inputs_unchanged = before_hash == after_hash
    checks = [
        ("FREEZE-01", branch == BRANCH and local_head == upstream_head == remote_head == FROZEN_HEAD, branch, BRANCH),
        ("COUNT-01", len(observed_records) == 1595 and len(unobserved_records) == 2410, f"{len(observed_records)}/{len(unobserved_records)}", "1595/2410"),
        ("COUNT-02", len(manifest) == 1126 and support_in == 268 and support_out == 858, f"{len(manifest)}/{support_in}/{support_out}", "1126/268/858"),
        ("PATH-01", physical_duplicates == 0 and all_legal, f"duplicates={physical_duplicates}; legal={int(all_legal)}", "duplicates=0; legal=1"),
        ("PROB-01", max_abs_probability_error <= 1e-12 and max_rel_probability_error <= 1e-12, f"abs={max_abs_probability_error:.16g}; rel={max_rel_probability_error:.16g}", "<=1e-12"),
        ("DAC-01", formal_out_available == 0, str(formal_out_available), "0 support-out formal identities; unresolved gate recorded"),
        ("MODEL-01", True, "no eta/epsilon selected; no candidate weights assigned", "true"),
        ("SOLVER-01", True, "LP=0; QCP=0; Gurobi=0; MATLAB=0", "all zero after failed precondition"),
        ("INPUT-01", inputs_unchanged, str(inputs_unchanged), "True"),
    ]
    failed = [row for row in checks if not row[1]]
    runtime = time.perf_counter() - started
    with (OUTPUT / "mechanical_audit.txt").open("w", encoding="utf-8", newline="\n") as handle:
        handle.write("status=" + ("PASS" if not failed else "FAIL") + "\n")
        for check_id, passed, observed, expected in checks:
            handle.write(f"{check_id}|{'PASS' if passed else 'FAIL'}|observed={observed}|expected={expected}\n")
        handle.write(f"maximum_path_probability_absolute_error={max_abs_probability_error:.17g}\n")
        handle.write(f"maximum_path_probability_relative_error={max_rel_probability_error:.17g}\n")
        handle.write("formal_DAC_byte_duplicate_check=NOT_APPLICABLE_NO_SUPPORT_OUT_FORMAL_DAC\n")
        handle.write("formal_harm_evaluation=SKIPPED_GATE_FAILED\n")
        handle.write("prototype=SKIPPED_GATE_FAILED\n")
        handle.write("formal_eta_selected=false\nformal_epsilon_selected=false\n")
        handle.write("production_solver_core_modified=false\nformal_model_modified=false\n")
        handle.write("path_generator_modified=false\ntransition_matrices_modified=false\n")
        handle.write("random_calls=0\nMATLAB_calls=0\nGurobi_calls=0\nLP_calls=0\nQCP_calls=0\n")
        handle.write(f"runtime_sec={runtime:.9f}\n")
    write_csv(OUTPUT / "runtime_and_solver_calls.csv", [{
        "phase": "read-only provenance/count/legality/probability audit",
        "runtime_sec": runtime, "MATLAB_calls": 0, "Gurobi_calls": 0,
        "LP_calls": 0, "QCP_calls": 0, "random_calls": 0,
        "formal_recourse_scenarios_evaluated": 0,
    }])

    status_extreme = "E-D. INPUT_OR_PROVENANCE_UNRESOLVED"
    status_integration = "I-B. FIXED_T_ONLY_FULL_INTEGRATION_UNRESOLVED"
    conclusion = "C. RESOLVE_EXTREME_INPUT_OR_PROBABILITY_FIRST"
    write_md(OUTPUT / "conclusion.txt", f"""
extreme_set_status={status_extreme}
integration_status={status_integration}
overall_conclusion={conclusion}
prototype_run=false
formal_harm_evaluation_run=false
next_task=Define and freeze a non-random, auditable formal D/A/C identity for support-out paths before any extreme-aware optimization.
""")
    write_md(OUTPUT / "next_stage_plan.md", """
# Unique next task

Define and freeze the support-out consequence identity. The next task must specify, without retroactive random invention, how each legal support-out W1-W3 path maps to formal stagewise wind quantiles, persistent resistance draws, and complete byte-exact three-period D/A/C. It must also decide whether the target is a deterministic stress scenario set or a probability-complete augmented stochastic model. Only after that freeze may fixed-T harm and the state19 extreme-max prototype run.
""")
    write_md(OUTPUT / "README.md", f"""
# Step-04C-A support-out extreme-path feasibility audit

历史“858 条”经现场数据重算仍为 **858 条支持外唯一物理路径**。来源共 {source_records} 条代理/分位标签记录，按完整 12 字段离散路径精确去重后为 {len(manifest)} 条，其中支持内 {support_in} 条、支持外 {support_out} 条；路径键重复为 {physical_duplicates}。

全部 {len(manifest)} 条路径都在正式状态空间内，三期所有强度、位置和 lfw 转移概率均为正。保存的 `path_probability` 与 Markov 矩阵重算一致，最大绝对误差为 `{max_abs_probability_error:.3e}`。这些概率只能解释为各初始状态下“被定向选中的路径子集”的理论概率，不能称为完整极端事件概率，也不能代替主体样本的经验权重。

本轮无法确认“确实小概率且正式大危害”。原因不是路径非法，而是正式三期 D/A/C 还没有定义：冻结流程要求 `path_id + joint_stream_position + wind_seed + resistance_seed`。支持内 {support_in} 条已有对应主体记录；支持外 {support_out} 条均没有冻结随机流身份。历史 B3 使用固定代表风速，只保存汇总和 6 位小数签名，不能用于字节级正式 D/A/C 审计。

当前 chi-square DRO 只能在 15000 条主体记录的现有支持上重分配概率，所以不会自动覆盖这 {support_out} 条支持外路径。数学上推荐在正式输入冻结后使用“主体 chi-square 风险 + epsilon × 极端最大损失”；epsilon 只作保护强度，不解释为概率。等权追加和直接用 `path_probability` 追加均不推荐。

state19 小规模增强模型按门槛正确跳过：没有正式支持外 recourse 函数就无法生成可信 LB/UB 证书。

- extreme_set_status: `{status_extreme}`
- integration_status: `{status_integration}`
- overall_conclusion: `{conclusion}`
- 下一步唯一任务：冻结支持外路径的非随机、可审计正式 D/A/C 身份，再做固定 T 危害与增强原型。
""")

    manifest_lines = ["# Large File Manifest", "", "No new large files were generated or staged.", "", "Protected large inputs read only:"]
    for name in ["main_sample", "formal_nominal_mat", "historical_b3_scenarios", "historical_b3_stage_summary"]:
        path = files[name]
        manifest_lines.append(f"- `{path.relative_to(ROOT)}` — {path.stat().st_size} bytes — SHA-256 `{before_hash[name]}`")
    write_md(OUTPUT / "LARGE_FILE_MANIFEST.md", "\n".join(manifest_lines))

    if failed:
        raise RuntimeError("Mechanical audit failed: " + ", ".join(row[0] for row in failed))


if __name__ == "__main__":
    main()
