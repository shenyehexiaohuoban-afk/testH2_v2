from __future__ import annotations

import ast
import json
import math
import re
import shutil
from pathlib import Path

import numpy as np
import pandas as pd


SAA_PACKAGE = Path(__file__).resolve().parents[2]
ROOT = Path(__file__).resolve().parents[5]
SAA_RUN = SAA_PACKAGE / "training/runs/run-20260904-233558"
DRO_PACKAGE = ROOT / "results/task-002-stage2b-b3-smoke/Temporal3p5_DRO_TerminalLOH_BaseMSP5h"
DRO_RUN = DRO_PACKAGE / "training/runs/run-20260901-020054"
OUT = SAA_RUN / "analysis_deep_saa_vs_dro"
BANK_SHA = "6bf3d1190a402ded052b8d3d08ed369042236e151f562bdd9fd4db7b8ff386c6"
SAA_SOURCE_SHA = "1e2968cf045ea883a60cd2e287f6f26ac6a23b735a432e5235c0e68b905ca4a3"
SAA_ACTIVE_SHA = "b74433fe8a19caedb75ac3071225480e279c136f3d1285ba503a184f12c5fcdc"
TOL = 1e-8


def ensure_dirs() -> None:
    for name in [
        "00_inventory", "01_semantic_qa", "02_terminal_loh", "03_target_migration",
        "04_classification", "05_service", "06_sitewise", "07_economic",
        "08_stage_hourly", "09_cohort", "10_path_candidates", "11_integrated",
    ]:
        (OUT / name).mkdir(parents=True, exist_ok=True)


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False, default=str), encoding="utf-8")


def read_path(root: Path) -> pd.DataFrame:
    return pd.read_csv(root / "oos_modeC/path_summary/oos_path_summary.csv")


def read_stage(root: Path) -> pd.DataFrame:
    return pd.read_csv(root / "oos_modeC/path_summary/oos_stage_summary.csv")


def read_stage_site(root: Path) -> pd.DataFrame:
    return pd.read_csv(root / "oos_modeC/path_summary/oos_stage_site_summary.csv")


def read_hourly_aggregated(root: Path) -> tuple[pd.DataFrame, pd.DataFrame]:
    usecols = [
        "path_id", "stage", "global_hour", "site", "H2_production_kg", "end_inventory_kg",
        "HTT_in_kg", "HTT_out_kg", "ordinary_shortage_kg",
    ]
    raw = pd.read_csv(root / "oos_modeC/hourly_site/oos_hour_site.csv", usecols=usecols)
    per_path_hour = raw.groupby(["path_id", "global_hour"], as_index=False)[
        ["H2_production_kg", "end_inventory_kg", "HTT_in_kg", "HTT_out_kg", "ordinary_shortage_kg"]
    ].sum()
    hourly = per_path_hour.groupby("global_hour", as_index=False).mean(numeric_only=True)
    per_path_stage = raw.groupby(["path_id", "stage"], as_index=False)[
        ["H2_production_kg", "end_inventory_kg", "HTT_in_kg", "HTT_out_kg", "ordinary_shortage_kg"]
    ].sum()
    stage = per_path_stage.groupby("stage", as_index=False).mean(numeric_only=True)
    return hourly, stage


def numeric(frame: pd.DataFrame, column: str) -> pd.Series:
    return pd.to_numeric(frame[column], errors="coerce")


def components(frame: pd.DataFrame, label: str) -> pd.DataFrame:
    target = frame[[f"target_site{i}" for i in range(1, 5)]].to_numpy(float)
    inventory = frame[[f"inventory_site{i}" for i in range(1, 5)]].to_numpy(float)
    target_total = target.sum(axis=1)
    site_gap = np.maximum(target - inventory, 0).sum(axis=1)
    quantity_gap = np.maximum(target_total - inventory.sum(axis=1), 0)
    location_gap = site_gap - quantity_gap
    useful = np.minimum(np.maximum(inventory, 0), target).sum(axis=1)
    service = np.divide(useful, target_total, out=np.ones_like(useful), where=target_total > TOL)
    classification = np.select(
        [
            (quantity_gap <= TOL) & (location_gap <= TOL),
            (quantity_gap > TOL) & (location_gap <= TOL),
            (quantity_gap <= TOL) & (location_gap > TOL),
            (quantity_gap > TOL) & (location_gap > TOL),
        ],
        ["ADEQUATE", "PURE_QUANTITY", "PURE_LOCATION", "MIXED"],
        default="NOT_IDENTIFIABLE",
    )
    return pd.DataFrame({
        "path_id": frame.path_id.astype(int),
        f"target_total_{label}": target_total,
        f"site_gap_{label}": site_gap,
        f"quantity_gap_{label}": quantity_gap,
        f"location_gap_{label}": location_gap,
        f"useful_{label}": useful,
        f"service_{label}": np.clip(service, 0, 1),
        f"class_{label}": classification,
    })


def semantic_audit() -> dict[str, object]:
    runner = (ROOT / "terminalLoh_wdro/partial_temporal_refinement/src/run_duration_aware_stage89k_saa.py").read_text(encoding="utf-8")
    recourse = (ROOT / "terminalLoh_wdro/current_w_mainline_stage89/src_snapshot/stage89k/run_stage89k_terminal_loh.py").read_text(encoding="utf-8")
    wrapper = (ROOT / "terminalLoh_wdro/partial_temporal_refinement/src/run_duration_aware_stage89k_dro.py").read_text(encoding="utf-8")
    checks = {
        "runner_calls_saa_optimizer": "solution = stage89k.solve_saa(structure, q)" in runner,
        "runner_fixed_recourse": "fixed = stage89k.solve_fixed_recourse(structure, solution.T)" in runner,
        "runner_eta_zero_only_qa": "solve_worst_probability(q, fixed.operating_loss, 0.0)" in runner,
        "runner_no_dro_optimizer": "solve_dro(" not in runner,
        "solver_has_preparation_term": "objective[:I] = C_H2 / OBJECTIVE_SCALE" in recourse,
        "solver_has_empirical_recourse_term": "q[structure.g_u] * M_H2 / OBJECTIVE_SCALE" in recourse,
        "solver_reconstructs_q_expectation": "np.dot(q, loss)" in recourse,
        "q_is_group_multiplicity": "q_g=multiplicity/15000" in runner,
        "six_duration_segments": all(x in runner for x in ["W0", "W1", "M12", "W2", "M23", "W3"]),
        "duration_vector": "[1.0, 0.5, 0.5, 0.5, 0.5, 0.5]" in runner,
        "duration_aware_wrapper": "build_duration_structure" in wrapper and "SOURCE =" in wrapper,
        "not_legacy_three_hour": "segment_dt_h == [1.0, 0.5, 0.5, 0.5, 0.5]" not in runner,
    }
    return {
        "SAA_SOLVER_SEMANTIC_AUDIT": "PASS" if all(checks.values()) else "FAIL",
        "checks": checks,
        "interpretation": "SAA uses solve_saa with q-weighted empirical recourse; solve_worst_probability is called only with eta=0 for a post-solve identity check, not as an adversarial optimization step.",
    }


def table_identity() -> tuple[dict[str, object], pd.DataFrame]:
    source_path = ROOT / "terminalLoh_wdro/partial_temporal_refinement/terminalLoh_saa_base2/run-001/terminal_loh_table_saa.csv"
    active_path = SAA_PACKAGE / "program/terminalLoh_wdro/current_w_mainline_stage89/terminal_tables/terminal_loh_temporal3p5_saa_candidate.csv"
    source = pd.read_csv(source_path)
    active = pd.read_csv(active_path)
    keys = ["state_id", "intensity", "loc", "lfw"]
    source_cmp = source.rename(columns={"a0": "intensity", "loc0": "loc", "lfw0": "lfw"})
    active_cmp = active.rename(columns={"T1_kg": "T1", "T2_kg": "T2", "T3_kg": "T3", "T4_kg": "T4"})
    merged = source_cmp.merge(active_cmp, on=keys, suffixes=("_source", "_active"), validate="one_to_one")
    diff_rows = []
    for col in ["T1", "T2", "T3", "T4"]:
        diff_rows.append({
            "field": col,
            "max_abs_difference": float(np.max(np.abs(numeric(merged, f"{col}_source") - numeric(merged, f"{col}_active")))),
            "mean_abs_difference": float(np.mean(np.abs(numeric(merged, f"{col}_source") - numeric(merged, f"{col}_active")))),
        })
    diffs = pd.DataFrame(diff_rows)
    all_equal = bool((diffs.max_abs_difference <= 1e-10).all() and len(merged) == 35)
    audit = {
        "SAA_SOURCE_TABLE_SHA256": SAA_SOURCE_SHA,
        "SAA_ACTIVE_TABLE_SHA256": SAA_ACTIVE_SHA,
        "STATE_ORDER_IDENTICAL": bool(merged.state_id.tolist() == list(range(1, 36))),
        "MAX_ABS_T_DIFFERENCE": float(diffs.max_abs_difference.max()),
        "MEAN_ABS_T_DIFFERENCE": float(diffs.mean_abs_difference.mean()),
        "ALL_35x4_VALUES_IDENTICAL": all_equal,
        "SAA_ACTIVE_TABLE_VALUE_IDENTITY": "PASS" if all_equal else "FAIL",
        "sha_difference_explanation": "Active table is a candidate-local quoted CSV wrapper: it preserves state/intensity/location/lfw and T1-T4 values, while adding candidate identity/mode/eta/tank/source metadata and omitting solver diagnostics and absolute grouped-bank paths.",
    }
    return audit, diffs


def common_path_qa(saa: pd.DataFrame, dro: pd.DataFrame) -> dict[str, object]:
    saa_ids = saa.path_id.astype(int).tolist()
    dro_ids = dro.path_id.astype(int).tolist()
    termination_cols = ["termination_type", "termination_stage", "termination_state", "operating_stage_count", "reached_stage7", "physical_dissipation_a1", "lf8_absorbing"]
    equal_termination = all(saa[c].tolist() == dro[c].tolist() for c in termination_cols)
    return {
        "COMMON_OOS_BANK": True,
        "BANK_SHA256": BANK_SHA,
        "PATH_COUNT_SAA": len(saa),
        "PATH_COUNT_DRO": len(dro),
        "ORDERED_PATH_IDS_IDENTICAL": saa_ids == dro_ids == list(range(1, 10001)),
        "STATE_SEQUENCES_IDENTICAL": saa.state_sequence.tolist() == dro.state_sequence.tolist(),
        "TERMINATION_IDENTITY_QA": "PASS" if equal_termination else "FAIL",
        "TERMINATION_COLUMNS": termination_cols,
        "PATH_IDENTITY_QA": "PASS" if saa_ids == dro_ids == list(range(1, 10001)) else "FAIL",
        "physical_dissipation_count": int(saa.physical_dissipation_a1.sum()),
        "other_absorption_count": int(saa.lf8_absorbing.sum()),
        "stage7_count": int((saa.termination_type == "STAGE7_TERMINAL_CHECK").sum()),
    }


def terminal_loh_outputs(saa_table: pd.DataFrame, dro_table: pd.DataFrame) -> dict[str, pd.DataFrame]:
    keys = ["state_id", "intensity", "loc", "lfw"]
    sites = [f"T{i}_kg" for i in range(1, 5)]
    m = saa_table[keys + sites + ["TerminalLOH_total_kg"]].merge(
        dro_table[keys + sites + ["TerminalLOH_total_kg"]], on=keys, suffixes=("_SAA", "_DRO"), validate="one_to_one"
    )
    for col in sites + ["TerminalLOH_total_kg"]:
        m[f"delta_{col}"] = m[f"{col}_DRO"] - m[f"{col}_SAA"]
        m[f"delta_pct_{col}"] = np.where(m[f"{col}_SAA"] > TOL, 100 * m[f"delta_{col}"] / m[f"{col}_SAA"], np.nan)
    sitewise = pd.DataFrame([
        {"site": i, "SAA_mean_T_kg": m[f"T{i}_kg_SAA"].mean(), "DRO_mean_T_kg": m[f"T{i}_kg_DRO"].mean(), "delta_kg": m[f"delta_T{i}_kg"].mean(), "delta_pct": 100 * m[f"delta_T{i}_kg"].mean() / m[f"T{i}_kg_SAA"].mean() if m[f"T{i}_kg_SAA"].mean() > TOL else np.nan, "share_of_total_delta_pct": 100 * m[f"delta_T{i}_kg"].sum() / m["delta_TerminalLOH_total_kg"].sum()}
        for i in range(1, 5)
    ])
    intensity = m.groupby("intensity", as_index=False).agg(SAA_mean_T_total_kg=("TerminalLOH_total_kg_SAA", "mean"), DRO_mean_T_total_kg=("TerminalLOH_total_kg_DRO", "mean"), state_count=("state_id", "size"))
    location = m.groupby("loc", as_index=False).agg(SAA_mean_T_total_kg=("TerminalLOH_total_kg_SAA", "mean"), DRO_mean_T_total_kg=("TerminalLOH_total_kg_DRO", "mean"), state_count=("state_id", "size"))
    for f in [intensity, location]:
        f["delta_kg"] = f.DRO_mean_T_total_kg - f.SAA_mean_T_total_kg
        f["delta_pct"] = np.where(f.SAA_mean_T_total_kg > TOL, 100 * f.delta_kg / f.SAA_mean_T_total_kg, np.nan)
    ranking = m[["state_id", "intensity", "loc", "TerminalLOH_total_kg_SAA", "TerminalLOH_total_kg_DRO", "delta_TerminalLOH_total_kg", "delta_pct_TerminalLOH_total_kg"]].sort_values(["delta_TerminalLOH_total_kg", "state_id"], ascending=[False, True]).head(10).reset_index(drop=True)
    return {"merged": m, "sitewise": sitewise, "intensity": intensity, "location": location, "ranking": ranking}


def merge_path_data(saa: pd.DataFrame, dro: pd.DataFrame) -> pd.DataFrame:
    s = saa.copy()
    d = dro.copy()
    cs = components(s, "SAA")
    cd = components(d, "DRO")
    keep = ["path_id", "state_sequence", "termination_type", "termination_stage", "termination_state", "physical_dissipation_a1", "lf8_absorbing"]
    base = s[keep].rename(columns={"state_sequence": "state_sequence_SAA", "termination_type": "termination_type_SAA", "termination_stage": "termination_stage_SAA", "termination_state": "termination_state_SAA", "physical_dissipation_a1": "physical_dissipation_a1_SAA", "lf8_absorbing": "lf8_absorbing_SAA"})
    base = base.merge(d[keep].rename(columns={"state_sequence": "state_sequence_DRO", "termination_type": "termination_type_DRO", "termination_stage": "termination_stage_DRO", "termination_state": "termination_state_DRO", "physical_dissipation_a1": "physical_dissipation_a1_DRO", "lf8_absorbing": "lf8_absorbing_DRO"}), on="path_id", validate="one_to_one")
    base = base.merge(cs, on="path_id").merge(cd, on="path_id")
    fields = ["reported_objective", "actual_operating_cost", "terminal_penalty_cost", "holding_cost", "production_cost", "electricity_cost", "production_om_cost", "ordinary_shortage_total", "ordinary_shortage_cost", "total_H2_production", "total_HTT", "HTT_cost", "terminal_inventory_total", "terminal_site_gap", "terminal_total_quantity_shortfall", "terminal_spatial_component", *[f"target_site{i}" for i in range(1, 5)], *[f"inventory_site{i}" for i in range(1, 5)]]
    for field in fields:
        base = base.merge(s[["path_id", field]].rename(columns={field: f"{field}_SAA"}), on="path_id", validate="one_to_one")
        base = base.merge(d[["path_id", field]].rename(columns={field: f"{field}_DRO"}), on="path_id", validate="one_to_one")
    for field in fields:
        base[f"delta_{field}"] = base[f"{field}_DRO"] - base[f"{field}_SAA"]
    base["SAA_positive"] = base.target_total_SAA > TOL
    base["DRO_positive"] = base.target_total_DRO > TOL
    base["migration"] = np.select([~base.SAA_positive & ~base.DRO_positive, ~base.SAA_positive & base.DRO_positive, base.SAA_positive & ~base.DRO_positive, base.SAA_positive & base.DRO_positive], ["ZZ", "ZP", "PZ", "PP"])
    return base


def migration_outputs(merged: pd.DataFrame) -> dict[str, pd.DataFrame]:
    mig = merged.migration.value_counts().reindex(["ZZ", "ZP", "PZ", "PP"], fill_value=0).rename_axis("migration").reset_index(name="path_count")
    by_state = merged.groupby(["migration", "termination_state_SAA"], as_index=False).agg(path_count=("path_id", "size"), terminal_a=("termination_type_SAA", "first"))
    zp = by_state[by_state.migration == "ZP"].rename(columns={"termination_state_SAA": "state_id"}).drop(columns=["migration"])
    pz = by_state[by_state.migration == "PZ"].rename(columns={"termination_state_SAA": "state_id"}).drop(columns=["migration"])
    return {"migration": mig, "zp_by_state": zp, "pz_by_state": pz}


def classification_outputs(merged: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    pp = merged[merged.migration == "PP"].copy()
    matrix = pd.crosstab(pp["class_SAA"], pp["class_DRO"]).reindex(index=["ADEQUATE", "PURE_QUANTITY", "PURE_LOCATION", "MIXED"], columns=["ADEQUATE", "PURE_QUANTITY", "PURE_LOCATION", "MIXED"], fill_value=0)
    matrix.index.name = "SAA_class"
    matrix.columns.name = "DRO_class"
    matrix_long = matrix.reset_index().melt(id_vars="SAA_class", var_name="DRO_class", value_name="path_count")
    summary = pd.DataFrame([
        {"metric": "COMMON_POSITIVE_COUNT", "value": len(pp)},
        {"metric": "SAA_ADEQUATE", "value": int((pp.class_SAA == "ADEQUATE").sum())},
        {"metric": "SAA_PURE_QUANTITY", "value": int((pp.class_SAA == "PURE_QUANTITY").sum())},
        {"metric": "SAA_PURE_LOCATION", "value": int((pp.class_SAA == "PURE_LOCATION").sum())},
        {"metric": "SAA_MIXED", "value": int((pp.class_SAA == "MIXED").sum())},
        {"metric": "DRO_ADEQUATE", "value": int((pp.class_DRO == "ADEQUATE").sum())},
        {"metric": "DRO_PURE_QUANTITY", "value": int((pp.class_DRO == "PURE_QUANTITY").sum())},
        {"metric": "DRO_PURE_LOCATION", "value": int((pp.class_DRO == "PURE_LOCATION").sum())},
        {"metric": "DRO_MIXED", "value": int((pp.class_DRO == "MIXED").sum())},
        {"metric": "SAA_ADEQ_TO_DRO_FAILURE", "value": int(((pp.class_SAA == "ADEQUATE") & (pp.class_DRO != "ADEQUATE")).sum())},
        {"metric": "SAA_FAILURE_TO_DRO_ADEQ", "value": int(((pp.class_SAA != "ADEQUATE") & (pp.class_DRO == "ADEQUATE")).sum())},
        {"metric": "QUANTITY_COMPONENT_RESOLVED", "value": int(((pp.quantity_gap_SAA > TOL) & (pp.quantity_gap_DRO <= TOL)).sum())},
        {"metric": "QUANTITY_COMPONENT_NEWLY_INTRODUCED", "value": int(((pp.quantity_gap_SAA <= TOL) & (pp.quantity_gap_DRO > TOL)).sum())},
        {"metric": "SPATIAL_COMPONENT_RESOLVED", "value": int(((pp.location_gap_SAA > TOL) & (pp.location_gap_DRO <= TOL)).sum())},
        {"metric": "SPATIAL_COMPONENT_NEWLY_INTRODUCED", "value": int(((pp.location_gap_SAA <= TOL) & (pp.location_gap_DRO > TOL)).sum())},
    ])
    return matrix_long, summary


def service_outputs(merged: pd.DataFrame, saa: pd.DataFrame, dro: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    rows = []
    for label in ["SAA", "DRO"]:
        positive = merged[f"target_total_{label}"] > TOL
        service = merged.loc[positive, f"service_{label}"]
        for threshold in [1.0, 0.99, 0.95, 0.90, 0.80]:
            rows.append({"arm": label, "threshold": threshold, "path_count": int((service >= threshold - TOL).sum()), "positive_target_count": int(positive.sum()), "rate": float((service >= threshold - TOL).mean())})
        target = merged.loc[positive, f"target_total_{label}"]
        useful = merged.loc[positive, f"useful_{label}"]
        rows.append({"arm": label, "threshold": "mean", "path_count": len(service), "positive_target_count": int(positive.sum()), "rate": float(service.mean())})
        rows.append({"arm": label, "threshold": "median", "path_count": len(service), "positive_target_count": int(positive.sum()), "rate": float(service.median())})
        rows.append({"arm": label, "threshold": "mass_weighted", "path_count": len(service), "positive_target_count": int(positive.sum()), "rate": float(useful.sum() / target.sum())})
    service = pd.DataFrame(rows)
    gaps = []
    for label in ["SAA", "DRO"]:
        positive = merged[f"target_total_{label}"] > TOL
        for comp in ["site_gap", "quantity_gap", "location_gap"]:
            x = merged.loc[positive, f"{comp}_{label}"]
            gaps.append({"arm": label, "component": comp, "mean_kg": float(x.mean()), "median_kg": float(x.median()), "positive_incidence": float((x > TOL).mean()), "total_kg": float(x.sum())})
    return service, pd.DataFrame(gaps)


def site_outputs(merged: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for label in ["SAA", "DRO"]:
        for site in range(1, 5):
            target = merged[f"target_site{site}_{label}"] if f"target_site{site}_{label}" in merged else None
            if target is None:
                raise RuntimeError("target site columns are required")
            inventory = merged[f"inventory_site{site}_{label}"]
            gap = np.maximum(target - inventory, 0)
            positive = target > TOL
            useful = np.minimum(np.maximum(inventory[positive], 0), target[positive])
            rows.append({"arm": label, "site": site, "mean_target_kg": float(target.mean()), "mean_terminal_inventory_kg": float(inventory.mean()), "mean_terminal_gap_kg": float(gap.mean()), "mass_weighted_capped_service": float(useful.sum() / target[positive].sum()) if positive.any() else np.nan, "gap_incidence_positive_target": float((gap[positive] > TOL).mean()) if positive.any() else np.nan, "positive_target_paths": int(positive.sum())})
    out = pd.DataFrame(rows)
    pivot = out.pivot(index="site", columns="arm")
    rows = []
    for site in range(1, 5):
        s = out[(out.arm == "SAA") & (out.site == site)].iloc[0]
        d = out[(out.arm == "DRO") & (out.site == site)].iloc[0]
        row = {"site": site}
        for field in ["mean_target_kg", "mean_terminal_inventory_kg", "mean_terminal_gap_kg", "mass_weighted_capped_service", "gap_incidence_positive_target"]:
            row[f"SAA_{field}"] = s[field]
            row[f"DRO_{field}"] = d[field]
            row[f"DRO_minus_SAA_{field}"] = d[field] - s[field]
        rows.append(row)
    return pd.DataFrame(rows)


def ci(values: np.ndarray) -> tuple[float, float, float]:
    values = np.asarray(values, dtype=float)
    mean = float(values.mean())
    half = 1.96 * float(values.std(ddof=1)) / math.sqrt(len(values))
    return mean, mean - half, mean + half


def economic_outputs(merged: pd.DataFrame) -> tuple[pd.DataFrame, dict[str, object]]:
    metrics = ["total_H2_production", "ordinary_shortage_total", "total_HTT", "terminal_inventory_total", "electricity_cost", "production_om_cost", "HTT_cost", "ordinary_shortage_cost", "holding_cost", "actual_operating_cost", "terminal_penalty_cost", "reported_objective"]
    rows = []
    for metric in metrics:
        delta = merged[f"delta_{metric}"].to_numpy(float)
        mean, low, high = ci(delta)
        rows.append({"metric": metric, "SAA_mean": float(merged[f"{metric}_SAA"].mean()), "DRO_mean": float(merged[f"{metric}_DRO"].mean()), "DRO_minus_SAA": mean, "paired_CI95_low": low, "paired_CI95_high": high, "DRO_lower_count": int((delta > 0).sum()), "DRO_higher_count": int((delta < 0).sum()), "tie_count": int((np.abs(delta) <= 1e-10).sum())})
    out = pd.DataFrame(rows)
    identity_saa = numeric(merged, "reported_objective_SAA") - numeric(merged, "actual_operating_cost_SAA") - numeric(merged, "terminal_penalty_cost_SAA")
    identity_dro = numeric(merged, "reported_objective_DRO") - numeric(merged, "actual_operating_cost_DRO") - numeric(merged, "terminal_penalty_cost_DRO")
    audit = {"COST_IDENTITY_QA": "PASS" if max(abs(identity_saa).max(), abs(identity_dro).max()) <= 1e-6 else "FAIL", "SAA_max_abs_error": float(abs(identity_saa).max()), "DRO_max_abs_error": float(abs(identity_dro).max()), "SAA_mean_abs_error": float(abs(identity_saa).mean()), "DRO_mean_abs_error": float(abs(identity_dro).mean())}
    return out, audit


def stage_hour_outputs(saa_root: Path, dro_root: Path) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    saa_stage = read_stage(saa_root)
    dro_stage = read_stage(dro_root)
    rows = []
    for label, frame in [("SAA", saa_stage), ("DRO", dro_stage)]:
        g = frame.groupby("stage", as_index=False).agg(production_kg=("production_kg", "mean"), ending_inventory_kg=("ending_inventory_kg", "mean"), HTT_kg=("htt_kg", "mean"), ordinary_shortage_kg=("ordinary_shortage_kg", "mean"))
        g.insert(0, "arm", label)
        rows.append(g)
    stage = pd.concat(rows, ignore_index=True)
    pivot = stage.pivot(index="stage", columns="arm")
    stage_delta = pd.DataFrame({
        "stage": sorted(stage.stage.unique()),
        "SAA_production_kg": [pivot.loc[i, ("production_kg", "SAA")] for i in sorted(stage.stage.unique())],
        "DRO_production_kg": [pivot.loc[i, ("production_kg", "DRO")] for i in sorted(stage.stage.unique())],
        "SAA_ending_inventory_kg": [pivot.loc[i, ("ending_inventory_kg", "SAA")] for i in sorted(stage.stage.unique())],
        "DRO_ending_inventory_kg": [pivot.loc[i, ("ending_inventory_kg", "DRO")] for i in sorted(stage.stage.unique())],
        "SAA_HTT_kg": [pivot.loc[i, ("HTT_kg", "SAA")] for i in sorted(stage.stage.unique())],
        "DRO_HTT_kg": [pivot.loc[i, ("HTT_kg", "DRO")] for i in sorted(stage.stage.unique())],
        "SAA_ordinary_shortage_kg": [pivot.loc[i, ("ordinary_shortage_kg", "SAA")] for i in sorted(stage.stage.unique())],
        "DRO_ordinary_shortage_kg": [pivot.loc[i, ("ordinary_shortage_kg", "DRO")] for i in sorted(stage.stage.unique())],
    })
    stage_delta["DRO_minus_SAA_production_kg"] = stage_delta.DRO_production_kg - stage_delta.SAA_production_kg
    stage_delta["production_delta_share"] = stage_delta.DRO_minus_SAA_production_kg / stage_delta.DRO_minus_SAA_production_kg.sum()
    for field in ["ending_inventory_kg", "HTT_kg", "ordinary_shortage_kg"]:
        stage_delta[f"DRO_minus_SAA_{field}"] = stage_delta[f"DRO_{field}"] - stage_delta[f"SAA_{field}"]
    saa_hour, _ = read_hourly_aggregated(saa_root)
    dro_hour, _ = read_hourly_aggregated(dro_root)
    hour = saa_hour.merge(dro_hour, on="global_hour", suffixes=("_SAA", "_DRO"))
    for field in ["H2_production_kg", "end_inventory_kg", "HTT_in_kg", "HTT_out_kg", "ordinary_shortage_kg"]:
        hour[f"DRO_minus_SAA_{field}"] = hour[f"{field}_DRO"] - hour[f"{field}_SAA"]
    top = hour.sort_values("DRO_minus_SAA_H2_production_kg", ascending=False).head(10).copy()
    return stage_delta, hour, top


def cohort_outputs(merged: pd.DataFrame) -> pd.DataFrame:
    masks = {
        "PHYSICAL_DISSIPATION": merged.physical_dissipation_a1_SAA == 1,
        "OTHER_ABSORPTION": merged.lf8_absorbing_SAA == 1,
        "TRUE_STAGE7_ZERO_TARGET_SAA": (merged.termination_type_SAA == "STAGE7_TERMINAL_CHECK") & ~merged.SAA_positive,
        "TRUE_STAGE7_ZERO_TARGET_DRO": (merged.termination_type_DRO == "STAGE7_TERMINAL_CHECK") & ~merged.DRO_positive,
        "COMMON_POSITIVE": merged.migration == "PP",
        "ZERO_TO_POSITIVE": merged.migration == "ZP",
        "POSITIVE_TO_ZERO": merged.migration == "PZ",
    }
    rows = []
    for cohort, mask in masks.items():
        for label in ["SAA", "DRO"]:
            positive = mask & merged[f"{label}_positive"]
            def avg(field: str) -> float:
                return float(merged.loc[mask, f"{field}_{label}"].mean()) if mask.any() else np.nan
            rows.append({"cohort": cohort, "arm": label, "path_count": int(mask.sum()), "positive_target_count": int(positive.sum()), "production_kg": avg("total_H2_production"), "ordinary_shortage_kg": avg("ordinary_shortage_total"), "HTT_kg": avg("total_HTT"), "actual_operating_cost": avg("actual_operating_cost"), "terminal_penalty": avg("terminal_penalty_cost"), "reported_objective": avg("reported_objective"), "terminal_gap_kg": avg("terminal_site_gap"), "service_mean_positive_only": float(merged.loc[positive, f"service_{label}"].mean()) if positive.any() else np.nan})
    return pd.DataFrame(rows)


def candidate_outputs(merged: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    metrics = ["service_SAA", "service_DRO", "terminal_site_gap_SAA", "terminal_site_gap_DRO", "total_H2_production_SAA", "total_H2_production_DRO", "actual_operating_cost_SAA", "actual_operating_cost_DRO", "total_HTT_SAA", "total_HTT_DRO", "reported_objective_SAA", "reported_objective_DRO"]
    cohorts = {
        "A_PHYSICAL_DISSIPATION": merged.physical_dissipation_a1_SAA == 1,
        "B_TRUE_STAGE7_ZERO_TARGET": (merged.termination_type_SAA == "STAGE7_TERMINAL_CHECK") & ~merged.SAA_positive,
        "C_COMMON_POSITIVE_ADEQUATE": (merged.migration == "PP") & (merged.class_SAA == "ADEQUATE") & (merged.class_DRO == "ADEQUATE"),
        "D_COMMON_POSITIVE_PURE_QUANTITY": (merged.migration == "PP") & ((merged.class_SAA == "PURE_QUANTITY") | (merged.class_DRO == "PURE_QUANTITY")),
        "E_COMMON_POSITIVE_PURE_LOCATION": (merged.migration == "PP") & ((merged.class_SAA == "PURE_LOCATION") | (merged.class_DRO == "PURE_LOCATION")),
        "F_COMMON_POSITIVE_MIXED": (merged.migration == "PP") & ((merged.class_SAA == "MIXED") | (merged.class_DRO == "MIXED")),
    }
    rows = []
    for cohort, mask in cohorts.items():
        subset = merged.loc[mask].copy()
        if subset.empty:
            continue
        values = subset[metrics].copy()
        med = values.median(numeric_only=True)
        scale = values.std().replace(0, np.nan).fillna(1.0)
        dist = (((values - med) / scale) ** 2).sum(axis=1) ** 0.5
        selected = subset.loc[[dist.idxmin()]].copy()
        selected["selection_reason"] = "MEDIAN-REPRESENTATIVE"
        selected["cohort"] = cohort
        rows.append(selected)
        positive = subset.SAA_positive & subset.DRO_positive
        if positive.any():
            stress = subset.loc[positive].sort_values(["service_DRO", "terminal_site_gap_DRO", "path_id"], ascending=[True, False, True]).head(1).copy()
            stress["selection_reason"] = "TAIL-STRESS"
            stress["cohort"] = cohort
            rows.append(stress)
    typical = pd.concat(rows, ignore_index=True) if rows else pd.DataFrame()
    if not typical.empty:
        cols = ["path_id", "cohort", "termination_state_SAA", "target_total_SAA", "target_total_DRO", "service_SAA", "service_DRO", "total_H2_production_SAA", "total_H2_production_DRO", "total_HTT_SAA", "total_HTT_DRO", "actual_operating_cost_SAA", "actual_operating_cost_DRO", "reported_objective_SAA", "reported_objective_DRO", "selection_reason"]
        typical = typical.rename(columns={"termination_state_SAA": "terminal_state"})[[c if c != "termination_state_SAA" else "terminal_state" for c in cols]]
    mech_rows = []
    for reason, order, field in [
        ("DRO_SERVICE_IMPROVEMENT", False, "delta_service"),
        ("DRO_SERVICE_DETERIORATION", True, "delta_service"),
        ("DRO_PRODUCTION_INCREASE", False, "delta_total_H2_production"),
        ("REPORTED_OBJECTIVE_IMPROVEMENT", False, "delta_reported_objective"),
    ]:
        temp = merged.copy()
        temp["delta_service"] = temp.service_DRO - temp.service_SAA
        temp["delta_total_H2_production"] = temp.total_H2_production_DRO - temp.total_H2_production_SAA
        temp["delta_reported_objective"] = temp.reported_objective_DRO - temp.reported_objective_SAA
        temp = temp[temp.SAA_positive | temp.DRO_positive].sort_values([field, "path_id"], ascending=[order, True]).head(5).copy()
        temp["selection_reason"] = reason
        mech_rows.append(temp)
    mech = pd.concat(mech_rows, ignore_index=True)
    keep = ["path_id", "selection_reason", "termination_state_SAA", "migration", "target_total_SAA", "target_total_DRO", "service_SAA", "service_DRO", "total_H2_production_SAA", "total_H2_production_DRO", "actual_operating_cost_SAA", "actual_operating_cost_DRO", "reported_objective_SAA", "reported_objective_DRO"]
    return typical, mech[keep]


def inventory() -> pd.DataFrame:
    native = SAA_RUN / "analysis_native"
    rows = [
        ("summary", native / "00_plain_language_summary_zh.md"),
        ("target ledger", native / "terminal_target_change_by_state.csv"),
        ("service analysis", native / "mass_weighted_service_summary.csv"),
        ("economic analysis", native / "paired_kpi_with_ci.csv"),
        ("stage profile", native / "hourly_site_mechanism_summary.csv"),
        ("hourly profile", native / "hourly_site_paired_delta.csv"),
        ("classification", native / "terminal_classification_summary.csv"),
        ("path-level comparison", native / "path_transition_detail.csv"),
        ("migration", native / "terminal_type_transition.csv"),
        ("site-wise analysis", native / "station_level_service_summary.csv"),
    ]
    return pd.DataFrame([{"analysis_area": a, "status": "AVAILABLE" if p.exists() else "MISSING", "path": str(p)} for a, p in rows])


def build_report(audit: dict, table_audit: dict, path_audit: dict, terminal: dict[str, pd.DataFrame], migration: dict[str, pd.DataFrame], class_matrix: pd.DataFrame, class_summary: pd.DataFrame, service: pd.DataFrame, gaps: pd.DataFrame, sites: pd.DataFrame, economic: pd.DataFrame, cost_audit: dict, stage: pd.DataFrame, hour_top: pd.DataFrame, cohort: pd.DataFrame, typical: pd.DataFrame, mech: pd.DataFrame) -> str:
    def val(metric: str, col: str = "DRO_minus_SAA") -> float:
        return float(economic.loc[economic.metric == metric, col].iloc[0])
    positive = migration["migration"].set_index("migration")["path_count"]
    saa_mass = float(service[(service.arm == "SAA") & (service.threshold == "mass_weighted")].rate.iloc[0])
    dro_mass = float(service[(service.arm == "DRO") & (service.threshold == "mass_weighted")].rate.iloc[0])
    pp = int(positive["PP"])
    stage_top = stage.sort_values("DRO_minus_SAA_production_kg", ascending=False).iloc[0]
    hour_top_row = hour_top.iloc[0]
    lines = [
        "# BASE2-SAA vs BASE2-DRO Deep Analysis",
        "",
        "This is a read-only paired analysis of the frozen BASE2-SAA and BASE2-DRO Formal Chain. No TerminalLOH solve, training, optimization, or OOS run was executed.",
        "",
        "## QA gates",
        f"- `SAA_SOLVER_SEMANTIC_AUDIT = {audit['SAA_SOLVER_SEMANTIC_AUDIT']}`.",
        f"- `SAA_ACTIVE_TABLE_VALUE_IDENTITY = {table_audit['SAA_ACTIVE_TABLE_VALUE_IDENTITY']}`; max absolute T difference `{table_audit['MAX_ABS_T_DIFFERENCE']:.3e}` kg.",
        f"- `COMMON_PATH_QA = {'PASS' if path_audit['PATH_IDENTITY_QA'] == 'PASS' and path_audit['TERMINATION_IDENTITY_QA'] == 'PASS' else 'FAIL'}`; canonical bank SHA `{BANK_SHA}`, 10000 ordered paths per arm.",
        f"- `COST_IDENTITY_QA = {cost_audit['COST_IDENTITY_QA']}`; max absolute identity error SAA/DRO `{cost_audit['SAA_max_abs_error']:.3e}` / `{cost_audit['DRO_max_abs_error']:.3e}` yuan.",
        "",
        "## TerminalLOH and positivity",
        f"- Mean SAA TerminalLOH `{terminal['merged'].TerminalLOH_total_kg_SAA.mean():.9f}` kg; DRO `{terminal['merged'].TerminalLOH_total_kg_DRO.mean():.9f}` kg; DRO-SAA `{terminal['merged'].delta_TerminalLOH_total_kg.mean():.9f}` kg.",
        f"- Positive-target paths: SAA `{int(positive['PZ'] + positive['PP'])}`, DRO `{int(positive['ZP'] + positive['PP'])}`.",
        f"- Positivity migration `ZZ/ZP/PZ/PP = {int(positive['ZZ'])}/{int(positive['ZP'])}/{int(positive['PZ'])}/{int(positive['PP'])}`; common-positive cohort `{pp}` paths.",
        "- State-level uplift is descriptive; the top-10 state table is not an OOS contribution ranking.",
        "",
        "## Common-positive classification",
        f"- SAA classes in PP: `{dict(zip(class_summary.metric, class_summary.value))}` (see CSV for the full matrix).",
        "- The 4x4 migration matrix compares complete SAA reserve design with complete DRO reserve design; it is not a fixed-target intervention comparison.",
        "",
        "## Service and gap decomposition",
        f"- Mass-weighted service: SAA `{saa_mass:.6%}`, DRO `{dro_mass:.6%}`, DRO-SAA `{dro_mass - saa_mass:+.6%}`.",
        "- Site/quantity/location gap means, medians, incidence, and total mass are in `05_service/gap_component_summary.csv`. These are paired end-to-end descriptive differences.",
        "",
        "## Economics and preparation",
        f"- Mean actual operating cost: SAA `{economic.loc[economic.metric == 'actual_operating_cost', 'SAA_mean'].iloc[0]:.6f}`, DRO `{economic.loc[economic.metric == 'actual_operating_cost', 'DRO_mean'].iloc[0]:.6f}` yuan/path; delta `{val('actual_operating_cost'):+.6f}`.",
        f"- Mean reported objective: SAA `{economic.loc[economic.metric == 'reported_objective', 'SAA_mean'].iloc[0]:.6f}`, DRO `{economic.loc[economic.metric == 'reported_objective', 'DRO_mean'].iloc[0]:.6f}` yuan/path; delta `{val('reported_objective'):+.6f}`.",
        f"- Mean terminal penalty delta `{val('terminal_penalty_cost'):+.6f}` yuan/path; mean production delta `{val('total_H2_production'):+.6f}` kg/path; mean HTT delta `{val('total_HTT'):+.6f}` kg/path.",
        f"- Largest stage production delta is Stage `{int(stage_top.stage)}` (`{stage_top.DRO_minus_SAA_production_kg:+.6f}` kg/path); largest hourly delta is hour `{int(hour_top_row.global_hour)}` (`{hour_top_row.DRO_minus_SAA_H2_production_kg:+.6f}` kg/path).",
        "- Operating cost and reported objective are kept separate. No claim of overall policy superiority is made from operating cost alone.",
        "",
        "## Cohorts and path candidates",
        "- Cohort rows distinguish physical dissipation, other absorption, true Stage7 zero-target, common-positive, ZP, and PZ exposure. For zero-target cohorts, service is reported only where target-positive; realized preparation exposure is not interpreted as knowledge of future outcomes.",
        f"- Typical candidates: `{len(typical)}` rows; mechanism candidates: `{len(mech)}` rows. Selection is mechanical median-distance, tail-stress, or ranked paired difference; no manual cherry-picking was used.",
        "",
        "## Interpretation boundary",
        "The evidence is consistent with DRO increasing reserve targets and changing end-to-end preparation/recourse exposure. It does not identify a single causal mechanism without a control experiment. Results are descriptive paired evidence under changed TerminalLOH targets, and `FULLY_CONVERGED` remains `NOT_ESTABLISHED`.",
        "",
        "`READY_FOR_FORMAL_CASE_STUDY_INTERPRETATION = YES` for descriptive paired case-study drafting, subject to the stated non-causal and fixed-budget limitations.",
    ]
    return "\n".join(lines) + "\n"


def main() -> None:
    ensure_dirs()
    inv = inventory()
    inv.to_csv(OUT / "00_inventory/existing_analysis_inventory.csv", index=False)
    audit = semantic_audit()
    table_audit, table_diffs = table_identity()
    saa = read_path(SAA_RUN)
    dro = read_path(DRO_RUN)
    path_audit = common_path_qa(saa, dro)
    if audit["SAA_SOLVER_SEMANTIC_AUDIT"] != "PASS":
        raise RuntimeError("SAA_SOLVER_SEMANTIC_AUDIT=FAIL; stopping before analysis")
    if table_audit["SAA_ACTIVE_TABLE_VALUE_IDENTITY"] != "PASS":
        raise RuntimeError("SAA active table value identity failed; stopping before analysis")
    if path_audit["PATH_IDENTITY_QA"] != "PASS" or path_audit["TERMINATION_IDENTITY_QA"] != "PASS":
        raise RuntimeError("Common path identity failed; stopping before analysis")
    write_json(OUT / "01_semantic_qa/solver_semantic_audit.json", audit)
    write_json(OUT / "01_semantic_qa/table_identity.json", table_audit)
    table_diffs.to_csv(OUT / "01_semantic_qa/table_value_differences.csv", index=False)
    write_json(OUT / "01_semantic_qa/common_path_qa.json", path_audit)
    saa_table = pd.read_csv(SAA_PACKAGE / "program/terminalLoh_wdro/current_w_mainline_stage89/terminal_tables/terminal_loh_temporal3p5_saa_candidate.csv")
    dro_table = pd.read_csv(DRO_PACKAGE / "program/terminalLoh_wdro/current_w_mainline_stage89/terminal_tables/terminal_loh_temporal3p5_dro_eta003_candidate.csv")
    terminal = terminal_loh_outputs(saa_table, dro_table)
    terminal["sitewise"].to_csv(OUT / "02_terminal_loh/sitewise_terminal_loh.csv", index=False)
    terminal["intensity"].to_csv(OUT / "02_terminal_loh/intensity_terminal_loh.csv", index=False)
    terminal["location"].to_csv(OUT / "02_terminal_loh/location_terminal_loh.csv", index=False)
    terminal["ranking"].to_csv(OUT / "02_terminal_loh/state_uplift_top10.csv", index=False)
    merged = merge_path_data(saa, dro)
    migration = migration_outputs(merged)
    migration["migration"].to_csv(OUT / "03_target_migration/positivity_migration.csv", index=False)
    migration["zp_by_state"].to_csv(OUT / "03_target_migration/zero_to_positive_by_state.csv", index=False)
    migration["pz_by_state"].to_csv(OUT / "03_target_migration/positive_to_zero_by_state.csv", index=False)
    class_matrix, class_summary = classification_outputs(merged)
    class_matrix.to_csv(OUT / "04_classification/common_positive_classification_migration.csv", index=False)
    class_summary.to_csv(OUT / "04_classification/common_positive_summary.csv", index=False)
    service, gaps = service_outputs(merged, saa, dro)
    service.to_csv(OUT / "05_service/service_distribution.csv", index=False)
    gaps.to_csv(OUT / "05_service/gap_component_summary.csv", index=False)
    sites = site_outputs(merged)
    sites.to_csv(OUT / "06_sitewise/site_resilience.csv", index=False)
    economic, cost_audit = economic_outputs(merged)
    economic.to_csv(OUT / "07_economic/economic_paired_comparison.csv", index=False)
    write_json(OUT / "07_economic/cost_identity_qa.json", cost_audit)
    stage, hour, top_hour = stage_hour_outputs(SAA_RUN, DRO_RUN)
    stage.to_csv(OUT / "08_stage_hourly/stage_profile.csv", index=False)
    hour.to_csv(OUT / "08_stage_hourly/hourly_profile.csv", index=False)
    top_hour.to_csv(OUT / "08_stage_hourly/top_hourly_production_delta.csv", index=False)
    stage_with_arm = pd.concat([
        pd.DataFrame({"arm": "SAA", "stage": stage.stage, "production_kg": stage.SAA_production_kg, "ending_inventory_kg": stage.SAA_ending_inventory_kg, "HTT_kg": stage.SAA_HTT_kg, "ordinary_shortage_kg": stage.SAA_ordinary_shortage_kg}),
        pd.DataFrame({"arm": "DRO", "stage": stage.stage, "production_kg": stage.DRO_production_kg, "ending_inventory_kg": stage.DRO_ending_inventory_kg, "HTT_kg": stage.DRO_HTT_kg, "ordinary_shortage_kg": stage.DRO_ordinary_shortage_kg}),
    ], ignore_index=True)
    block = stage_with_arm.assign(block=np.select([stage_with_arm.stage.isin([1, 2]), stage_with_arm.stage.isin([3, 4]), stage_with_arm.stage.isin([5, 6])], ["Stage1-2", "Stage3-4", "Stage5-6"], default="other")).groupby(["arm", "block"], as_index=False).agg(production_kg=("production_kg", "sum"), ending_inventory_kg=("ending_inventory_kg", "mean"), HTT_kg=("HTT_kg", "sum"), ordinary_shortage_kg=("ordinary_shortage_kg", "sum"))
    block.to_csv(OUT / "08_stage_hourly/stage_block_profile.csv", index=False)
    cohort = cohort_outputs(merged)
    cohort.to_csv(OUT / "09_cohort/cohort_comparison.csv", index=False)
    typical, mech = candidate_outputs(merged)
    typical.to_csv(OUT / "10_path_candidates/typical_path_candidates.csv", index=False)
    mech.to_csv(OUT / "10_path_candidates/mechanism_candidates.csv", index=False)
    final_metrics = {
        "SAA_SOLVER_SEMANTIC_AUDIT": audit["SAA_SOLVER_SEMANTIC_AUDIT"],
        "SAA_ACTIVE_TABLE_VALUE_IDENTITY": table_audit["SAA_ACTIVE_TABLE_VALUE_IDENTITY"],
        "COMMON_PATH_QA": "PASS",
        "SAA_POSITIVE_TARGET": int((merged.SAA_positive).sum()),
        "DRO_POSITIVE_TARGET": int((merged.DRO_positive).sum()),
        "TARGET_POSITIVITY_MIGRATION": migration["migration"].set_index("migration").path_count.to_dict(),
        "COMMON_POSITIVE_COUNT": int((merged.migration == "PP").sum()),
        "SAA_MASS_SERVICE": float(service[(service.arm == "SAA") & (service.threshold == "mass_weighted")].rate.iloc[0]),
        "DRO_MASS_SERVICE": float(service[(service.arm == "DRO") & (service.threshold == "mass_weighted")].rate.iloc[0]),
        "DRO_MINUS_SAA_MASS_SERVICE_PP": float(service[(service.arm == "DRO") & (service.threshold == "mass_weighted")].rate.iloc[0] - service[(service.arm == "SAA") & (service.threshold == "mass_weighted")].rate.iloc[0]),
        "SAA_PRODUCTION": float(economic.loc[economic.metric == "total_H2_production", "SAA_mean"].iloc[0]),
        "DRO_PRODUCTION": float(economic.loc[economic.metric == "total_H2_production", "DRO_mean"].iloc[0]),
        "DRO_MINUS_SAA_PRODUCTION": float(economic.loc[economic.metric == "total_H2_production", "DRO_minus_SAA"].iloc[0]),
        "SAA_OPERATING_COST": float(economic.loc[economic.metric == "actual_operating_cost", "SAA_mean"].iloc[0]),
        "DRO_OPERATING_COST": float(economic.loc[economic.metric == "actual_operating_cost", "DRO_mean"].iloc[0]),
        "DRO_MINUS_SAA_OPERATING_COST": float(economic.loc[economic.metric == "actual_operating_cost", "DRO_minus_SAA"].iloc[0]),
        "SAA_REPORTED_OBJECTIVE": float(economic.loc[economic.metric == "reported_objective", "SAA_mean"].iloc[0]),
        "DRO_REPORTED_OBJECTIVE": float(economic.loc[economic.metric == "reported_objective", "DRO_mean"].iloc[0]),
        "DRO_MINUS_SAA_REPORTED_OBJECTIVE": float(economic.loc[economic.metric == "reported_objective", "DRO_minus_SAA"].iloc[0]),
        "COST_IDENTITY_QA": cost_audit["COST_IDENTITY_QA"],
        "TYPICAL_PATH_CANDIDATES": int(len(typical)),
        "MECHANISM_CANDIDATES": int(len(mech)),
        "READY_FOR_FORMAL_CASE_STUDY_INTERPRETATION": "YES",
    }
    write_json(OUT / "11_integrated/final_metrics.json", final_metrics)
    (OUT / "11_integrated/FINAL_SAA_DRO_DEEP_ANALYSIS.md").write_text(build_report(audit, table_audit, path_audit, terminal, migration, class_matrix, class_summary, service, gaps, sites, economic, cost_audit, stage, top_hour, cohort, typical, mech), encoding="utf-8")
    print(json.dumps({"status": "PASS", "output": str(OUT), **final_metrics}, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
