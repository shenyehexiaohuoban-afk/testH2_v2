#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Independent raw-based QA for the Stage89Q Pmax flexibility audit."""

from __future__ import annotations

import ast
import hashlib
import math
import os
from collections import OrderedDict
from pathlib import Path

import numpy as np
import pandas as pd
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
RUN = ROOT / "results/task-002-stage2b-b3-smoke/stage89q-penalty1000-vs1500-long-training/run-003"
RAW = ROOT / "hourly_grid_h2/output/stage89q_penalty1000_vs1500_long_training/run-003/penalty1000"
OUT = RUN / "05_analysis/10_deep_penalty1000/17_pmax_flexibility_audit"
FIG = RUN / "06_figures/11_penalty1000_pmax_flexibility_audit"
PREVIOUS = RUN / "05_analysis/10_deep_penalty1000/15_mechanism_deep_dive"
TARGET = ROOT / "terminalLoh_wdro/current_w_mainline_stage89/terminal_tables/terminal_loh_stage89k_dro_eta003_adopted.csv"
BANK_IDENTITY = RUN / "03_oos/common/bank_identity.csv"
TOL = 1e-7
K_H2 = 0.0195
CUTS = [-16, -8, -4]
BASE = (300.0, 200.0, 120.0, 150.0)
CANDIDATES = OrderedDict([
    ("B0", BASE),
    ("S1_125", (375.0, 200.0, 120.0, 150.0)),
    ("S2_125", (300.0, 250.0, 120.0, 150.0)),
    ("S3_125", (300.0, 200.0, 150.0, 150.0)),
    ("S4_125", (300.0, 200.0, 120.0, 187.5)),
    ("S1_150", (450.0, 200.0, 120.0, 150.0)),
    ("S2_150", (300.0, 300.0, 120.0, 150.0)),
    ("S3_150", (300.0, 200.0, 180.0, 150.0)),
    ("S4_150", (300.0, 200.0, 120.0, 225.0)),
    ("ALL_125", (375.0, 250.0, 150.0, 187.5)),
    ("ALL_150", (450.0, 300.0, 180.0, 225.0)),
])
EXPECTED_RAW = {
    "path_summary/oos_path_summary.csv": "99ec55faba4e60e88b25d757deb1a8146515faf666d52979fe69c64362047502",
    "path_summary/oos_stage_summary.csv": "969c373a9a2ff1b271cde6fda95a6fe8e64b10362518fe4b807c0dc86437c15d",
    "path_summary/oos_stage_site_summary.csv": "eab41bdf5d58fc971bc65af8c5745de3bd08cc25a0a4d44cc386aeba3f99c89e",
    "hourly_site/oos_hour_site.csv": "af3b3d5c4aa69e6d29b35a88008b4d82360c4b8391fc783141078f7ad68b0cda",
    "grid_hourly/oos_hour_system.csv": "b9eaa83ee3e8a720f3cb5afd5d54da050c2d3ef45c434efe74f8ba8b976b63c6",
}
EXPECTED_TARGET = "2fa1958944110701239a109ebf46d959324a351f2f27c1c3fbd62f333066eaa8"
EXPECTED_BANK_MAT = "6bf3d1190a402ded052b8d3d08ed369042236e151f562bdd9fd4db7b8ff386c6"
EXPECTED_BANK_CSV = "a186e8d4ac870082d0925a05311ab8f4c5a0b70cb61b6fd06955a48a647b3941"


def io_path(path: Path) -> str:
    resolved = str(path.resolve())
    return f"\\\\?\\{resolved}" if os.name == "nt" and not resolved.startswith("\\\\?\\") else resolved


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with open(io_path(path), "rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def id_set_sha(values) -> str:
    payload = ",".join(str(int(v)) for v in sorted(values)).encode("ascii")
    return hashlib.sha256(payload).hexdigest()


def dotted_name(node: ast.AST) -> str:
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        prefix = dotted_name(node.value)
        return f"{prefix}.{node.attr}" if prefix else node.attr
    return ""


def forbidden_references(path: Path) -> list[str]:
    tree = ast.parse(path.read_text(encoding="utf-8"))
    names = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            names.extend(alias.name for alias in node.names)
        elif isinstance(node, ast.ImportFrom):
            names.append(node.module or "")
        elif isinstance(node, ast.Call):
            names.append(dotted_name(node.func))
    prefixes = ("scipy.optimize", "gurobipy", "cvxpy", "pulp", "np.random", "numpy.random", "random.")
    return sorted({name for name in names if name == "random" or name.startswith(prefixes)})


def save_csv(frame: pd.DataFrame, path: Path) -> None:
    frame.to_csv(io_path(path), index=False, encoding="utf-8-sig", float_format="%.12g")


def main() -> None:
    before = {name: sha256(RAW / name) for name in EXPECTED_RAW}
    path = pd.read_csv(RAW / "path_summary/oos_path_summary.csv")
    hour = pd.read_csv(RAW / "hourly_site/oos_hour_site.csv")
    system = pd.read_csv(RAW / "grid_hourly/oos_hour_system.csv")
    baseline = pd.read_csv(OUT / "01_baseline_reproduction/pmax_recoverability_baseline_reproduction.csv")
    baseline_detail = pd.read_csv(OUT / "01_baseline_reproduction/baseline_reproduction_by_path.csv")
    baseline_qa = pd.read_csv(OUT / "01_baseline_reproduction/baseline_reproduction_QA.csv")
    by_path = pd.read_csv(OUT / "02_counterfactual_recoverability/pmax_candidate_recoverability_by_path.csv")
    summary = pd.read_csv(OUT / "02_counterfactual_recoverability/pmax_candidate_recoverability_summary.csv")
    failure = pd.read_csv(OUT / "02_counterfactual_recoverability/pmax_failure_type_summary.csv")
    window = pd.read_csv(OUT / "03_recoverability_window/recoverability_window_shift_by_path.csv")
    window_summary = pd.read_csv(OUT / "03_recoverability_window/recoverability_window_shift_summary.csv")
    effectiveness = pd.read_csv(OUT / "04_site_effectiveness/site_specific_pmax_effectiveness.csv")
    need = pd.read_csv(OUT / "04_site_effectiveness/site_need_vs_pmax_effectiveness.csv")
    grid = pd.read_csv(OUT / "05_grid_hosting/pmax_grid_hosting_screen.csv")
    recovered = pd.read_csv(OUT / "06_recovered_path_mechanism/recovered_path_characteristics.csv")
    tail = pd.read_csv(OUT / "07_tail_effect/pmax_tail_recoverability.csv")
    ranking = pd.read_csv(OUT / "08_candidate_ranking/pmax_candidate_ranking.csv")
    statuses = pd.read_csv(OUT / "09_summary/final_status.csv").set_index("status").value.to_dict()
    readme = (OUT / "09_summary/README.md").read_text(encoding="utf-8")
    visual = pd.read_csv(OUT / "10_qa/visual_audit.csv")
    manifest = pd.read_csv(OUT / "09_summary/lightweight_manifest.csv")
    old_recover = pd.read_csv(PREVIOUS / "03_physical_recoverability/physical_recoverability_diagnostic.csv")
    old_site = pd.read_csv(PREVIOUS / "04_site_mismatch/site_mismatch_od_summary.csv")
    old_util = pd.read_csv(PREVIOUS / "06_electrolyzer/electrolyzer_utilization_by_site_group.csv")
    rows = []

    def check(name, observed, expected, passed, tolerance="exact"):
        rows.append({"check": name, "observed": observed, "expected": expected,
                     "tolerance": tolerance, "pass": bool(passed)})

    check("accepted_raw_hashes_before", str(before), str(EXPECTED_RAW), before == EXPECTED_RAW)
    check("terminal_hash", sha256(TARGET), EXPECTED_TARGET, sha256(TARGET) == EXPECTED_TARGET)
    bank = pd.read_csv(BANK_IDENTITY).iloc[0]
    check("bank_identity", f"{bank.bank_sha256}/{bank.manifest_sha256}", f"{EXPECTED_BANK_MAT}/{EXPECTED_BANK_CSV}",
          bank.bank_sha256 == EXPECTED_BANK_MAT and bank.manifest_sha256 == EXPECTED_BANK_CSV)
    s7 = path[path.reached_stage7.eq(1)]
    failed = path[(path.target_total > TOL) & (path.terminal_site_gap > TOL)].copy()
    check("path_stage7_shortfall_counts", f"{len(path)}/{len(s7)}/{len(failed)}", "10000/6124/473",
          len(path) == 10000 and len(s7) == 6124 and len(failed) == 473)
    counts = failed.terminal_gap_class.value_counts().to_dict()
    check("failure_partition", counts, "118/203/152",
          counts.get("PURE_QUANTITY_SHORTFALL") == 118 and counts.get("PURE_SPATIAL_MISMATCH") == 203 and counts.get("MIXED_QUANTITY_AND_SPATIAL") == 152)
    check("no_padded_zero_hours", len(system), int((8 * path.operating_stage_count).sum()),
          len(system) == int((8 * path.operating_stage_count).sum()))
    observed_pmax = hour[hour.electrolyzer_capacity_binding.eq(1)].groupby("site").P_EL_kW.max().to_dict()
    expected_pmax = dict(zip([1, 2, 3, 4], BASE))
    check("formal_Pmax_identity", observed_pmax, expected_pmax,
          all(abs(observed_pmax.get(site, np.nan) - value) <= TOL for site, value in expected_pmax.items()))

    failed["end_hour"] = 8 * failed.operating_stage_count
    h = hour[hour.path_id.isin(failed.path_id)].merge(failed[["path_id", "end_hour", "target_total", "terminal_gap_class"]], on="path_id", validate="many_to_one")
    h["relative_hour"] = h.global_hour - h.end_hour
    totals = h.groupby(["path_id", "relative_hour", "target_total", "terminal_gap_class"], as_index=False).end_inventory_kg.sum().rename(columns={"end_inventory_kg": "current_inventory_kg"})
    totals["remaining_hours"] = -totals.relative_hour
    previous_counts = {-16: 70, -8: 156, -4: 167}
    for relative_hour, expected_count in previous_counts.items():
        current = totals[totals.relative_hour.eq(relative_hour)]
        ids = set(current.loc[current.current_inventory_kg + sum(BASE) * K_H2 * (-relative_hour) - current.target_total < -TOL, "path_id"])
        previous_ids = set(old_recover.loc[(old_recover.hours_before_stage7.eq(-relative_hour)) & old_recover.TARGET_STILL_PHYSICALLY_REACHABLE.eq("NO"), "path_id"])
        output = baseline[baseline.relative_hour.eq(relative_hour)].iloc[0]
        check(f"baseline_count_{relative_hour}", len(ids), expected_count, len(ids) == expected_count)
        check(f"baseline_set_{relative_hour}", id_set_sha(ids), id_set_sha(previous_ids), ids == previous_ids)
        check(f"baseline_valid_n_{relative_hour}", len(current), int(output.valid_real_checkpoint_paths), len(current) == int(output.valid_real_checkpoint_paths))
    check("baseline_all_qa", int(baseline_qa["pass"].sum()), len(baseline_qa), baseline_qa["pass"].all())
    check("baseline_missing_not_padded", int((~baseline_detail.checkpoint_present).sum()), 3, int((~baseline_detail.checkpoint_present).sum()) == 3)

    independent_sets = {}
    exact_first = {}
    physical_monotone = True
    for name, pmax in CANDIDATES.items():
        cap = sum(pmax) * K_H2
        temp = totals.copy()
        temp["margin"] = temp.current_inventory_kg + cap * temp.remaining_hours - temp.target_total
        temp["unrecoverable"] = temp.margin < -TOL
        exact_first[name] = temp[temp.unrecoverable].groupby("path_id").relative_hour.min().to_dict()
        for _, group in temp.sort_values(["path_id", "relative_hour"]).groupby("path_id"):
            physical_monotone &= bool(np.all(np.diff(group.margin.to_numpy()) <= TOL))
        for relative_hour in CUTS:
            current = temp[temp.relative_hour.eq(relative_hour)]
            ids = set(current.loc[current.unrecoverable, "path_id"])
            independent_sets[(name, relative_hour)] = ids
            output = summary[(summary.candidate.eq(name)) & summary.hours_before_stage7.eq(-relative_hour)].iloc[0]
            detail_ids = set(by_path.loc[(by_path.candidate.eq(name)) & by_path.relative_hour.eq(relative_hour) & by_path.PHYSICALLY_UNRECOVERABLE, "path_id"])
            check(f"candidate_count_{name}_{relative_hour}", len(ids), int(output.physically_unrecoverable), len(ids) == int(output.physically_unrecoverable))
            check(f"candidate_set_{name}_{relative_hour}", id_set_sha(ids), id_set_sha(detail_ids), ids == detail_ids)
            check(f"candidate_valid_n_{name}_{relative_hour}", len(current), int(output.valid_real_checkpoint_paths), len(current) == int(output.valid_real_checkpoint_paths))
    check("within_candidate_hourly_margin_monotone", physical_monotone, True, physical_monotone)
    set_monotone = all(independent_sets[(name, cut)] <= independent_sets[("B0", cut)] for name in list(CANDIDATES)[1:] for cut in CUTS)
    check("expanded_Pmax_set_monotonicity", set_monotone, True, set_monotone)
    check("reported_monotonicity_violations", int(summary.monotonicity_violation_count.sum()), 0, summary.monotonicity_violation_count.sum() == 0)

    base_first = exact_first["B0"]
    exact_match = True
    for name in CANDIDATES:
        output = window[window.candidate.eq(name)].set_index("path_id")
        for path_id in failed.path_id:
            expected_first = exact_first[name].get(path_id, np.nan)
            observed_first = output.loc[path_id, "FIRST_PHYSICALLY_UNRECOVERABLE_HOUR"]
            if not (pd.isna(expected_first) and pd.isna(observed_first)) and expected_first != observed_first:
                exact_match = False
            expected_shift = expected_first - base_first.get(path_id, np.nan) if path_id in exact_first[name] and path_id in base_first else np.nan
            observed_shift = output.loc[path_id, "unrecoverable_window_shift_hours"]
            if not (pd.isna(expected_shift) and pd.isna(observed_shift)) and abs(expected_shift - observed_shift) > TOL:
                exact_match = False
    check("exact_window_recompute", exact_match, True, exact_match)
    all150_window = window_summary[window_summary.candidate.eq("ALL_150")].iloc[0]
    check("ALL150_window_shift", f"{int(all150_window.shifted_path_count)}/{all150_window.mean_shift_hours:.12g}/{all150_window.max_shift_hours:.0f}", "212/4.8037037037/19",
          int(all150_window.shifted_path_count) == 212 and abs(all150_window.mean_shift_hours - 4.8037037037) <= 1e-10 and all150_window.max_shift_hours == 19)

    fcounts = failure.groupby(["candidate", "failure_type", "hours_before_stage7"]).size()
    check("failure_summary_complete", len(fcounts), 11 * 3 * 3, len(fcounts) == 99)
    pure_location = failure[failure.failure_type.eq("pure_location")]
    check("pure_location_zero_effect", int(pure_location.recovery_gain.sum()), 0, pure_location.recovery_gain.sum() == 0)
    check("ALL150_checkpoint_counts", summary[summary.candidate.eq("ALL_150")].sort_values("hours_before_stage7", ascending=False).physically_unrecoverable.astype(int).tolist(), [7, 66, 122],
          summary[summary.candidate.eq("ALL_150")].sort_values("hours_before_stage7", ascending=False).physically_unrecoverable.astype(int).tolist() == [7, 66, 122])

    old_need = old_site[(old_site.record_type.eq("site_summary")) & old_site.group.eq("all_shortfall")].sort_values("site")
    old_u = old_util[old_util.group.eq("shortfall")].sort_values("site")
    need_sorted = need.sort_values("site")
    site_copy = np.allclose(need_sorted.shortage_frequency, old_need.shortage_occurrence) and np.allclose(need_sorted.shortage_q95_kg, old_need.shortage_q95_if_positive_kg) and np.allclose(need_sorted.electrolyzer_mean_util, old_u.mean_utilization) and np.allclose(need_sorted.near_max_ratio, old_u.near_max_ratio)
    check("previous_site_mechanism_values_reused", site_copy, True, site_copy)
    check("site4_need_evidence_highest", f"{need_sorted.loc[need_sorted.site.eq(4),'shortage_frequency'].iloc[0]:.12g}/{need_sorted.loc[need_sorted.site.eq(4),'near_max_ratio'].iloc[0]:.12g}", "four-site maxima",
          need_sorted.loc[need_sorted.site.eq(4), "shortage_frequency"].iloc[0] == need_sorted.shortage_frequency.max() and need_sorted.loc[need_sorted.site.eq(4), "near_max_ratio"].iloc[0] == need_sorted.near_max_ratio.max())
    check("site_effectiveness_rows", len(effectiveness), 8, len(effectiveness) == 8)
    check("site4_125_efficiency", effectiveness.loc[effectiveness.candidate.eq("S4_125"), "RECOVERED_PATHS_PER_ADDED_KW"].iloc[0], 1.28,
          abs(effectiveness.loc[effectiveness.candidate.eq("S4_125"), "RECOVERED_PATHS_PER_ADDED_KW"].iloc[0] - 1.28) <= 1e-12)

    check("grid_bus_mapping", grid.electrical_bus.astype(int).tolist(), [24, 14, 18, 31], grid.electrical_bus.astype(int).tolist() == [24, 14, 18, 31])
    check("grid_site3_warning", grid.loc[grid.site.eq(3), "GRID_HOSTING_SIGNAL_FOR_EXPANSION"].iloc[0], "POTENTIALLY_VOLTAGE_LIMITED",
          grid.loc[grid.site.eq(3), "GRID_HOSTING_SIGNAL_FOR_EXPANSION"].iloc[0] == "POTENTIALLY_VOLTAGE_LIMITED")
    check("incremental_grid_not_identifiable", grid.INCREMENTAL_ELECTRICAL_HOSTING.unique().tolist(), "NOT_IDENTIFIABLE",
          grid.INCREMENTAL_ELECTRICAL_HOSTING.str.contains("NOT_IDENTIFIABLE").all())
    check("bus18_current_binding_exists", int(grid.current_system_bus18_voltage_binding_hours.max()), ">0", grid.current_system_bus18_voltage_binding_hours.max() > 0)

    check("recovered_characteristics_closure", len(recovered), int(summary.recovered_relative_to_base.sum()), len(recovered) == int(summary.recovered_relative_to_base.sum()))
    check("recovered_claim_scope", recovered.candidate_recoverable_status.unique().tolist(), ["NOT_RULED_OUT_BY_OPTIMISTIC_BOUND"],
          recovered.candidate_recoverable_status.eq("NOT_RULED_OUT_BY_OPTIMISTIC_BOUND").all())
    stage7_order = s7.sort_values(["terminal_site_gap", "path_id"]).reset_index(drop=True)
    cut95, cut99 = math.floor(.95 * len(stage7_order)), math.floor(.99 * len(stage7_order))
    tail_ids = {
        "normal95": set(stage7_order.iloc[:cut95].path_id),
        "difficult4": set(stage7_order.iloc[cut95:cut99].path_id),
        "extreme1": set(stage7_order.iloc[cut99:].path_id),
    }
    tail_ok = True
    for tier, ids in tail_ids.items():
        expected_n = len(set(failed.path_id) & ids)
        observed = tail[(tail.candidate.eq("B0")) & tail.tail_group.eq(tier)].tail_shortfall_paths.unique()
        tail_ok &= len(observed) == 1 and int(observed[0]) == expected_n
    check("tail_partition_recompute", tail_ok, True, tail_ok)

    check("ranking_candidates", len(ranking), 10, len(ranking) == 10)
    check("best_targeted", statuses.get("BEST_TARGETED_CANDIDATE"), "S4_125", statuses.get("BEST_TARGETED_CANDIDATE") == "S4_125" and ranking.loc[ranking.BEST_TARGETED_CANDIDATE.eq("YES"), "candidate"].tolist() == ["S4_125"])
    check("best_uniform", statuses.get("BEST_UNIFORM_CANDIDATE"), "ALL_125", statuses.get("BEST_UNIFORM_CANDIDATE") == "ALL_125" and ranking.loc[ranking.BEST_UNIFORM_CANDIDATE.eq("YES"), "candidate"].tolist() == ["ALL_125"])
    expected_statuses = {
        "PMAX_PHYSICAL_FLEXIBILITY_SIGNAL": "STRONG", "PMAX_SHIFTS_UNRECOVERABLE_WINDOW": "YES",
        "PMAX_PURE_QUANTITY_EFFECT": "STRONG", "PMAX_MIXED_EFFECT": "STRONG",
        "PMAX_PURE_LOCATION_EFFECT": "NONE", "GRID_HOSTING_FOR_SELECTED_CANDIDATE": "NOT_IDENTIFIABLE",
        "RECOMMEND_FRESH_PMAX_POLICY_PILOT": "NEEDS_GRID_CHECK", "NO_REOPTIMIZATION": "YES",
        "NO_RANDOM_DRAW": "YES", "NO_PARAMETER_WRITEBACK": "YES", "PENALTY1500_STARTED": "NO",
    }
    check("final_statuses", {key: statuses.get(key) for key in expected_statuses}, expected_statuses,
          all(statuses.get(key) == value for key, value in expected_statuses.items()))
    check("readme_20_answers", sum(line.startswith("## ") for line in readme.splitlines()), 20,
          all(f"## {number}." in readme for number in range(1, 21)))
    check("readme_scope_guard", "只有 fresh retraining 才能知道" in readme, True,
          "只有 fresh retraining 才能知道" in readme and "NOT_RULED_OUT_BY_OPTIMISTIC_BOUND" in readme)

    scripts = [ROOT / "hourly_grid_h2/analyze_stage89q_pmax_flexibility_audit.py", Path(__file__)]
    forbidden = {path.name: forbidden_references(path) for path in scripts}
    check("no_optimizer_or_random_capabilities", forbidden, "all empty", all(not values for values in forbidden.values()))
    pngs = sorted(FIG.glob("*.png"))
    check("figure_count", len(pngs), 13, len(pngs) == 13)
    image_ok = []
    for image_path in pngs:
        with Image.open(io_path(image_path)) as image:
            pixels = np.asarray(image.convert("RGB"), dtype=np.float32)
            image_ok.append(image.width >= 700 and image.height >= 400 and pixels.std() > 3)
    check("figure_dimensions_and_nonblank", all(image_ok), True, all(image_ok))
    check("manual_visual_qa", visual.manual_visual_status.value_counts().to_dict(), {"PASS": 13},
          len(visual) == 13 and visual.manual_visual_status.eq("PASS").all())

    manifest_ok = True
    for row in manifest.itertuples():
        artifact = ROOT / row.relative_path
        manifest_ok &= artifact.is_file() and artifact.stat().st_size == int(row.size_bytes) and sha256(artifact) == row.sha256
    check("manifest_hashes", manifest_ok, True, manifest_ok)
    after = {name: sha256(RAW / name) for name in EXPECTED_RAW}
    check("accepted_raw_hashes_after", str(after), str(EXPECTED_RAW), after == EXPECTED_RAW)
    frame = pd.DataFrame(rows)
    save_csv(frame, OUT / "10_qa/independent_qa.csv")
    if not frame["pass"].all():
        failed_checks = frame.loc[~frame["pass"], "check"].tolist()
        raise RuntimeError(f"Independent QA failed: {failed_checks}")
    print(f"Independent Stage89Q Pmax QA PASS: {len(frame)}/{len(frame)}")


if __name__ == "__main__":
    main()
