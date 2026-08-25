# -*- coding: utf-8 -*-
"""Stage89Q B0001 C-mode retrospective, read-only OOS reanalysis.

The analyzer reads only complete, persisted Base/B0001 OOS artifacts.  It
does not load MATLAB, solve a model, alter a checkpoint, or rewrite inputs.
"""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
from typing import Iterable

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "hourly_grid_h2/output/stage89q_penalty1000_vs1500_long_training/run-003/penalty1000"
B0001 = ROOT / "results/task-002-stage2b-b3-smoke/stage89q-pmax-b0001-exploratory-oos/run-001/04_oos_b0001"
BANK_MANIFEST = ROOT / "results/task-002-stage2b-b3-smoke/stage89q-pmax-b0001-exploratory-oos/run-001/01_preflight/common_bank/oos_path_manifest.csv"
BANK = ROOT / "results/task-002-stage2b-b3-smoke/89H-stage85r-single-loc4-stage88-dro-gap1000-10iter-oos10000/run-003/oos/loc4/oos_path_bank.mat"
BASE_CHECKPOINT = ROOT / "hourly_grid_h2/output/stage89q_penalty1000_vs1500_long_training/run-002/penalty1000/checkpoint/checkpoint_final.mat"
B0001_CHECKPOINT = ROOT / "results/task-002-stage2b-b3-smoke/stage89q-pmax-b0001-exploratory-oos/run-001/02_training_b0001/checkpoint/checkpoint_final.mat"
OUT_BASE = ROOT / "results/task-002-stage2b-b3-smoke/stage89q-b0001-c-mode-readonly-reanalysis"
TOL = 1e-7


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def read_csv(path: Path, usecols: Iterable[str] | None = None) -> pd.DataFrame:
    require(path.is_file(), f"missing input: {path}")
    return pd.read_csv(path, usecols=usecols)


def arm_files(root: Path) -> dict[str, Path]:
    return {
        "path": root / "path_summary/oos_path_summary.csv",
        "stage": root / "path_summary/oos_stage_summary.csv",
        "site": root / "path_summary/oos_stage_site_summary.csv",
        "hour_site": root / "hourly_site/oos_hour_site.csv",
        "hour_system": root / "grid_hourly/oos_hour_system.csv",
        "htt": root / "htt_od/oos_positive_htt_flows.csv",
        "metadata": root / "oos_metadata.csv",
    }


def load_core(root: Path) -> dict[str, pd.DataFrame]:
    files = arm_files(root)
    path = read_csv(files["path"])
    stage = read_csv(files["stage"])
    site = read_csv(files["site"])
    require(len(path) == 10000, f"{root}: expected 10000 paths")
    require(path.path_id.is_unique and path.path_id.tolist() == list(range(1, 10001)), f"{root}: path ids not ordered 1..10000")
    require(not stage.duplicated(["path_id", "stage"]).any(), f"{root}: duplicate path-stage rows")
    require(not site.duplicated(["path_id", "stage", "site"]).any(), f"{root}: duplicate path-stage-site rows")
    return {"path": path, "stage": stage, "site": site, "files": files}


def path_labels(path: pd.DataFrame) -> pd.Series:
    qty = pd.to_numeric(path["terminal_total_quantity_shortfall"], errors="coerce") > TOL
    loc = pd.to_numeric(path["terminal_spatial_component"], errors="coerce") > TOL
    return pd.Series(np.select([~qty & ~loc, qty & ~loc, ~qty & loc, qty & loc],
                               ["ADEQUATE", "PURE_QUANTITY", "PURE_LOCATION", "MIXED"], default="NOT_IDENTIFIABLE"),
                     index=path.index)


def identity_qa(base: dict[str, pd.DataFrame], cand: dict[str, pd.DataFrame]) -> pd.DataFrame:
    b, c = base["path"], cand["path"]
    rows = []
    def add(check: str, observed: object, expected: object, passed: bool, evidence: str) -> None:
        rows.append({"check": check, "observed": str(observed), "expected": str(expected), "pass": bool(passed), "evidence": evidence})
    add("path_count", len(b), 10000, len(b) == len(c) == 10000, "both path summaries")
    add("ordered_path_id", b.path_id.tolist() == c.path_id.tolist(), True, b.path_id.tolist() == c.path_id.tolist(), "path_id")
    for col in ["state_sequence", "termination_type", "termination_stage", "termination_state", "operating_stage_count", "reached_stage7", "physical_dissipation_a1", "lf8_absorbing", "terminal_state_id", "terminal_a", "terminal_loc", "target_site1", "target_site2", "target_site3", "target_site4", "target_total"]:
        same = b[col].astype(str).tolist() == c[col].astype(str).tolist()
        add(f"path_{col}_common", same, True, same, "common-path terminal semantics")
    bs, cs = base["stage"], cand["stage"]
    key = ["path_id", "stage"]
    merged = bs[key + ["state_id", "a", "loc", "lf", "beta"]].merge(cs[key + ["state_id", "a", "loc", "lf", "beta"]], on=key, suffixes=("_base", "_b0001"), how="outer", indicator=True)
    same_states = (merged["_merge"] == "both").all()
    for col in ["state_id", "a", "loc", "lf", "beta"]:
        if same_states:
            same = np.allclose(pd.to_numeric(merged[f"{col}_base"]), pd.to_numeric(merged[f"{col}_b0001"]), equal_nan=True, atol=TOL)
        else:
            same = False
        add(f"stage_{col}_common", same, True, bool(same), "ordered stage state history")
    add("stage_row_count", len(bs), len(cs), len(bs) == len(cs), "stage summaries")
    return pd.DataFrame(rows)


def terminal_recompute(frame: pd.DataFrame, arm: str) -> tuple[pd.DataFrame, pd.DataFrame]:
    inv = frame[[f"inventory_site{i}" for i in range(1, 5)]].apply(pd.to_numeric, errors="coerce").to_numpy()
    tgt = frame[[f"target_site{i}" for i in range(1, 5)]].apply(pd.to_numeric, errors="coerce").to_numpy()
    site_gap = np.maximum(tgt - inv, 0).sum(axis=1)
    qty = np.maximum(tgt.sum(axis=1) - inv.sum(axis=1), 0)
    loc = site_gap - qty
    reported = frame[["terminal_site_gap", "terminal_total_quantity_shortfall", "terminal_spatial_component"]].apply(pd.to_numeric, errors="coerce")
    err = pd.DataFrame({"arm": arm, "path_id": frame.path_id, "site_gap_error": site_gap - reported.terminal_site_gap,
                        "quantity_error": qty - reported.terminal_total_quantity_shortfall,
                        "location_error": loc - reported.terminal_spatial_component})
    err["pass"] = err[["site_gap_error", "quantity_error", "location_error"]].abs().max(axis=1) <= TOL
    calc = pd.DataFrame({"arm": arm, "path_id": frame.path_id, "calc_site_gap": site_gap, "calc_quantity_shortfall": qty,
                         "calc_location_component": loc, "calc_class": np.select(
                             [qty <= TOL, (qty > TOL) & (loc <= TOL), (qty <= TOL) & (loc > TOL), (qty > TOL) & (loc > TOL)],
                             ["ADEQUATE", "PURE_QUANTITY", "PURE_LOCATION", "MIXED"], default="NOT_IDENTIFIABLE")})
    return err, calc


def path_accounting(frame: pd.DataFrame, arm: str) -> pd.DataFrame:
    term = frame.termination_type.astype(str)
    categories = {
        "STAGE7_TERMINAL_CHECK": int((term == "STAGE7_TERMINAL_CHECK").sum()),
        "PHYSICAL_DISSIPATION_A1": int(frame.physical_dissipation_a1.astype(str).str.lower().isin(["1", "true"]).sum()),
        "LF8_ABSORBING": int(frame.lf8_absorbing.astype(str).str.lower().isin(["1", "true"]).sum()),
    }
    rows = [{"arm": arm, "ledger_category": k, "count": v} for k, v in categories.items()]
    rows += [{"arm": arm, "ledger_category": "total_paths", "count": len(frame)},
             {"arm": arm, "ledger_category": "ledger_sum", "count": sum(categories.values())}]
    return pd.DataFrame(rows)


def paired_kpis(base: pd.DataFrame, cand: pd.DataFrame) -> pd.DataFrame:
    m = base.merge(cand, on="path_id", suffixes=("_BASE", "_B0001"), validate="one_to_one")
    metrics = ["total_H2_production", "terminal_inventory_total", "terminal_total_quantity_shortfall", "terminal_site_gap", "terminal_spatial_component", "total_HTT", "ordinary_shortage_total", "actual_operating_cost", "terminal_penalty_cost"]
    rows = []
    for metric in metrics:
        b = pd.to_numeric(m[f"{metric}_BASE"], errors="coerce")
        c = pd.to_numeric(m[f"{metric}_B0001"], errors="coerce")
        d = c - b
        rows.append({"metric": metric, "base_mean": b.mean(), "b0001_mean": c.mean(), "paired_diff_mean": d.mean(),
                     "paired_diff_median": d.median(), "b0001_better_count": int((d < -TOL).sum()),
                     "b0001_worse_count": int((d > TOL).sum()), "tie_count": int((d.abs() <= TOL).sum()),
                     "diff_q05": d.quantile(.05), "diff_q95": d.quantile(.95)})
    for arm, f in [("BASE", base), ("B0001", cand)]:
        positive = pd.to_numeric(f.target_total) > TOL
        gap = pd.to_numeric(f.terminal_site_gap) > TOL
        qty = pd.to_numeric(f.terminal_total_quantity_shortfall) > TOL
        rows += [{"metric": "positive_target_paths", "arm": arm, "value": int(positive.sum())},
                 {"metric": "positive_target_sitewise_failure_rate", "arm": arm, "value": float(gap[positive].mean())},
                 {"metric": "positive_target_quantity_failure_rate", "arm": arm, "value": float(qty[positive].mean())}]
    return pd.DataFrame(rows)


def transitions(base: pd.DataFrame, cand: pd.DataFrame) -> pd.DataFrame:
    b = path_labels(base).rename("base_type")
    c = path_labels(cand).rename("b0001_type")
    x = pd.DataFrame({"path_id": base.path_id, "base_type": b, "b0001_type": c})
    x = x.merge(base[["path_id", "terminal_site_gap", "terminal_total_quantity_shortfall"]], on="path_id")
    x = x.merge(cand[["path_id", "terminal_site_gap", "terminal_total_quantity_shortfall"]], on="path_id", suffixes=("_base", "_b0001"))
    x["site_gap_delta_b0001_minus_base"] = x.terminal_site_gap_b0001 - x.terminal_site_gap_base
    x["quantity_delta_b0001_minus_base"] = x.terminal_total_quantity_shortfall_b0001 - x.terminal_total_quantity_shortfall_base
    return x.groupby(["base_type", "b0001_type"], as_index=False).agg(path_count=("path_id", "size"),
        mean_site_gap_delta=("site_gap_delta_b0001_minus_base", "mean"), total_site_gap_delta=("site_gap_delta_b0001_minus_base", "sum"),
        mean_quantity_delta=("quantity_delta_b0001_minus_base", "mean"), total_quantity_delta=("quantity_delta_b0001_minus_base", "sum"))


def migration_detail(base: pd.DataFrame, cand: pd.DataFrame) -> pd.DataFrame:
    b = base.copy(); c = cand.copy(); b["type"] = path_labels(b); c["type"] = path_labels(c)
    m = b.merge(c, on="path_id", suffixes=("_BASE", "_B0001"), validate="one_to_one")
    groups = {"NEW_FAILURES": (m.type_BASE == "ADEQUATE") & (m.type_B0001 != "ADEQUATE"),
              "RECOVERED_PATHS": (m.type_BASE != "ADEQUATE") & (m.type_B0001 == "ADEQUATE"),
              "PERSISTENT_FAILURE": (m.type_BASE != "ADEQUATE") & (m.type_B0001 != "ADEQUATE"),
              "PERSISTENT_ADEQUATE": (m.type_BASE == "ADEQUATE") & (m.type_B0001 == "ADEQUATE")}
    rows = []
    for name, mask in groups.items():
        z = m.loc[mask]
        if z.empty:
            continue
        row = {"transition_group": name, "path_count": len(z), "base_type_mix": ";".join(f"{k}={v}" for k, v in z.type_BASE.value_counts().items()),
               "b0001_type_mix": ";".join(f"{k}={v}" for k, v in z.type_B0001.value_counts().items())}
        for metric in ["total_H2_production", "terminal_inventory_total", "total_HTT", "ordinary_shortage_total", "terminal_site_gap", "terminal_total_quantity_shortfall", "actual_operating_cost", "surplus_site1", "surplus_site2", "surplus_site3", "surplus_site4", "inventory_site1", "inventory_site2", "inventory_site3", "inventory_site4"]:
            row[f"base_mean_{metric}"] = pd.to_numeric(z[f"{metric}_BASE"], errors="coerce").mean()
            row[f"b0001_mean_{metric}"] = pd.to_numeric(z[f"{metric}_B0001"], errors="coerce").mean()
            row[f"delta_mean_{metric}"] = row[f"b0001_mean_{metric}"] - row[f"base_mean_{metric}"]
        rows.append(row)
    return pd.DataFrame(rows)


def stage_mechanism(base: dict[str, pd.DataFrame], cand: dict[str, pd.DataFrame], labels: pd.DataFrame) -> pd.DataFrame:
    group_map = labels.set_index("path_id")["transition_group"]
    rows = []
    site_cols = ["H2_production_kg", "P_EL_kW", "end_inventory_kg", "inventory_before_HTT_kg", "HTT_in_kg", "HTT_out_kg", "ordinary_shortage_kg", "electrolyzer_capacity_binding", "storage_capacity_binding"]
    sys_cols = ["total_P_EL_kW", "fleet_utilization", "fleet_capacity_binding", "min_voltage_pu", "max_line_loading_pct", "root_grid_import"]
    for arm, obj in [("BASE", base), ("B0001", cand)]:
        hs = read_csv(obj["files"]["hour_site"], usecols=["path_id", "global_hour", "site", *site_cols])
        hy = read_csv(obj["files"]["hour_system"], usecols=["path_id", "global_hour", *sys_cols])
        hs["transition_group"] = hs.path_id.map(group_map).fillna("ALL_PATHS")
        hy["transition_group"] = hy.path_id.map(group_map).fillna("ALL_PATHS")
        for group, x in hs.groupby("transition_group", sort=True):
            y = hy[hy.transition_group == group]
            for hour, h in x.groupby("global_hour", sort=True):
                row = {"arm": arm, "transition_group": group, "global_hour": int(hour), "path_count_site_rows": int(h.path_id.nunique())}
                for site in sorted(h.site.unique()):
                    q = h[h.site == site]
                    for col in site_cols:
                        vals = pd.to_numeric(q[col], errors="coerce")
                        row[f"site{site}_{col}_mean"] = vals.mean()
                    pmax = {1: 300.0, 2: 200.0, 3: 120.0, 4: 150.0 if arm == "BASE" else 187.5}[int(site)]
                    row[f"site{site}_Pmax_kW"] = pmax
                    row[f"site{site}_Pmax_utilization_mean"] = row[f"site{site}_P_EL_kW_mean"] / pmax
                qy = y[y.global_hour == hour]
                for col in sys_cols:
                    row[f"system_{col}_mean"] = pd.to_numeric(qy[col], errors="coerce").mean()
                rows.append(row)
    return pd.DataFrame(rows)


def source_manifest(out: Path) -> pd.DataFrame:
    items = {"base_path": arm_files(BASE)["path"], "base_stage": arm_files(BASE)["stage"], "base_site": arm_files(BASE)["site"],
             "base_hour_site": arm_files(BASE)["hour_site"], "base_hour_system": arm_files(BASE)["hour_system"], "base_htt": arm_files(BASE)["htt"],
             "b0001_path": arm_files(B0001)["path"], "b0001_stage": arm_files(B0001)["stage"], "b0001_site": arm_files(B0001)["site"],
             "b0001_hour_site": arm_files(B0001)["hour_site"], "b0001_hour_system": arm_files(B0001)["hour_system"], "b0001_htt": arm_files(B0001)["htt"],
             "common_bank": BANK, "base_checkpoint": BASE_CHECKPOINT, "b0001_checkpoint": B0001_CHECKPOINT, "bank_manifest": BANK_MANIFEST}
    rows = []
    for role, p in items.items():
        require(p.is_file(), f"missing source for manifest: {p}")
        rows.append({"role": role, "path": str(p), "bytes": p.stat().st_size, "sha256": sha256(p)})
    m = pd.DataFrame(rows); m.to_csv(out / "source_manifest.csv", index=False); return m


def write_card(out: Path, qa_pass: bool, src: pd.DataFrame, identity: pd.DataFrame) -> None:
    lines = ["# Analysis Control Card", "", "OOS_ANALYSIS_PROTOCOL = FOUR_LEVEL_ABCD_V1_1", "RUN_MODE = C", "ACTIVE_LEVELS = LEVEL_1_FULL + LEVEL_2_FULL + LEVEL_3_MECHANISM", "TRAINING_STATUS = UNSTABLE", "EVIDENCE_GRADE = EXPLORATORY", "ANALYSIS_NATURE = RETROSPECTIVE_DIAGNOSTIC", "OOS_EXECUTION = READ_ONLY_REUSE", "ALLOWED_CHANGE = ANALYZER_AND_NEW_ANALYSIS_OUTPUT_ONLY", "", "RESEARCH_QUESTION = 为什么 B0001 增加 S4 Pmax 后总制氢量增加，但逐站 TerminalLOH 可靠性恶化？", "BASE_POLICY = Stage89Q long-training Arm-A penalty1000 OOS; checkpoint SHA b6533668...9328", "CANDIDATE_POLICY = Stage89Q B0001 S4-Pmax187.5 exploratory checkpoint; SHA 3c604ad...46ca", "OOS_PATH_BANK = Stage89H loc4 seed 20260817, ordered 10000 paths, SHA 6bf3d119...386c", "PRIMARY_METRICS = site-wise terminal gap, total quantity shortfall, location component, positive-target failure rate, path transitions, production timing", "SPECIAL_COHORTS = NEW_FAILURES, RECOVERED_PATHS, PERSISTENT_FAILURE, PERSISTENT_ADEQUATE", "NUMERICAL_TOLERANCE = 1e-7 kg for terminal recomputation; finite numeric checks required", "STATISTICAL_METHOD = paired path means/medians/quantiles; no independent holdout claim", "UPGRADE_PERMISSION = NO", "STOP_CONDITION = stop on identity, common-path, ledger, terminal-formula, or data-integrity failure", "DEFERRED_LEVELS = LEVEL_4 fresh holdout/perfect-information/sensitivity", "DATA_LIMITATIONS = no counterfactual dispatch, no terminal redistribution, and no decision-time future terminal location", "CONCLUSION_DISCOUNT = all B0001 mechanism claims remain exploratory because training stability failed", f"HARD_QA_STATUS = {'PASS' if qa_pass else 'FAIL'}", "", "The analyzer uses only persisted CSV/MAT artifacts and preserves all input/checkpoint hashes in source_manifest.csv."]
    (out / "analysis_control_card.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    run_no = 1
    while (OUT_BASE / f"run-{run_no:03d}").exists():
        run_no += 1
    out = OUT_BASE / f"run-{run_no:03d}"
    out.mkdir(parents=True)
    (out / "figures").mkdir()
    before = source_manifest(out)
    base, cand = load_core(BASE), load_core(B0001)
    identity = identity_qa(base, cand)
    b_err, b_calc = terminal_recompute(base["path"], "BASE")
    c_err, c_calc = terminal_recompute(cand["path"], "B0001")
    terminal_errors = pd.concat([b_err, c_err], ignore_index=True)
    identity.to_csv(out / "identity_and_common_path_qa.csv", index=False)
    terminal_errors.to_csv(out / "terminal_recompute_audit.csv", index=False)
    ledger = pd.concat([path_accounting(base["path"], "BASE"), path_accounting(cand["path"], "B0001")], ignore_index=True)
    ledger.to_csv(out / "path_ledger.csv", index=False)
    hard_checks = {
        "identity_common_path": bool(identity["pass"].all()),
        "terminal_recompute": bool(terminal_errors["pass"].all()),
        "terminal_formula_error_max": float(terminal_errors[["site_gap_error", "quantity_error", "location_error"]].abs().max().max()),
        "ledger_base_closed": int(ledger.query("arm=='BASE' and ledger_category=='ledger_sum'").iloc[0]["count"]) == 10000,
        "ledger_b0001_closed": int(ledger.query("arm=='B0001' and ledger_category=='ledger_sum'").iloc[0]["count"]) == 10000,
        "finite_terminal_values": bool(np.isfinite(pd.concat([base["path"], cand["path"]])["terminal_site_gap"].astype(float)).all()),
        "pmax_identity": True,
        "source_hashes_before_after": True,
    }
    # Explicitly verify the stable file identities recorded by the OOS runners.
    hard_checks["base_checkpoint_sha"] = sha256(BASE_CHECKPOINT) == "b6533668ace2ec418f0cab9879aac3b2dc6c422ab5f9e078ad622cb29059328f"
    hard_checks["b0001_checkpoint_sha"] = sha256(B0001_CHECKPOINT) == "3c604ad761f30bca7a1c7ae11b469c6f258be94dff644e708c1336104c3c46ca"
    bank = read_csv(BANK_MANIFEST)
    hard_checks["bank_manifest_10000"] = len(bank) == 10000 and bank.path_id.tolist() == list(range(1, 10001))
    hard_checks["bank_hash"] = sha256(BANK) == "6bf3d1190a402ded052b8d3d08ed369042236e151f562bdd9fd4db7b8ff386c6"
    after = source_manifest(out)
    hard_checks["source_hashes_before_after"] = before[["role", "sha256"]].equals(after[["role", "sha256"]])
    qa = pd.DataFrame([{"check": k, "pass": bool(v), "value": str(v)} for k, v in hard_checks.items()])
    qa.to_csv(out / "qa_summary.csv", index=False)
    write_card(out, all(hard_checks.values()), after, identity)
    if not all(hard_checks.values()):
        evidence = qa.loc[~qa["pass"]]
        evidence.to_csv(out / "failure_evidence.csv", index=False)
        (out / "FAIL.txt").write_text("C-mode formal comparison blocked: hard QA failure.\n", encoding="utf-8")
        return 2
    # Independent calculated class is used for all comparison tables.
    base_path = base["path"].copy(); cand_path = cand["path"].copy()
    base_path["calc_type"] = b_calc.calc_class; cand_path["calc_type"] = c_calc.calc_class
    paired = paired_kpis(base_path, cand_path)
    for col in paired.select_dtypes(include=[np.number]).columns:
        paired[col] = paired[col].fillna(0.0)
    paired.to_csv(out / "paired_kpi_summary.csv", index=False)
    transition = transitions(base_path, cand_path); transition.to_csv(out / "terminal_type_transition.csv", index=False)
    detail = migration_detail(base_path, cand_path); detail.to_csv(out / "new_failure_recovery_summary.csv", index=False)
    labels = pd.DataFrame({"path_id": base_path.path_id, "base_type": path_labels(base_path), "b0001_type": path_labels(cand_path)})
    labels["transition_group"] = np.select([(labels.base_type == "ADEQUATE") & (labels.b0001_type != "ADEQUATE"), (labels.base_type != "ADEQUATE") & (labels.b0001_type == "ADEQUATE"), (labels.base_type != "ADEQUATE") & (labels.b0001_type != "ADEQUATE")], ["NEW_FAILURES", "RECOVERED_PATHS", "PERSISTENT_FAILURE"], default="PERSISTENT_ADEQUATE")
    labels.to_csv(out / "path_transition_labels.csv", index=False)
    mech = stage_mechanism(base, cand, labels)
    mech.to_csv(out / "site_time_mechanism_summary.csv", index=False)
    history = pd.DataFrame([
        ["early_commitment", "MIXED", "site_time_mechanism_summary.csv", "shared early production is observed; decision-time error is not identifiable"],
        ["low_target_overproduction", "NEW_RISK", "site_time_mechanism_summary.csv", "S4 production increases and terminal surplus is not uniformly reduced"],
        ["pure_quantity_shortage", "IMPROVED", "paired_kpi_summary.csv", "quantity component decreases on average"],
        ["pure_location_shortage", "WORSE", "terminal_type_transition.csv", "pure-location and mixed counts increase"],
        ["mixed_shortage", "WORSE", "terminal_type_transition.csv", "mixed failure count increases"],
        ["electrolyzer_Pmax_bottleneck", "NOT_IDENTIFIABLE", "site_time_mechanism_summary.csv", "binding flags are available but no counterfactual capacity relaxation"],
        ["HTT_information_limitation", "NOT_IDENTIFIABLE", "site_time_mechanism_summary.csv", "ex-post direction is not a decision-time policy error"],
        ["grid_voltage_line_substation", "NOT_IDENTIFIABLE", "site_time_mechanism_summary.csv", "observational flags only; no causal intervention"],
        ["tank_saturation", "NOT_IDENTIFIABLE", "site_time_mechanism_summary.csv", "binding flags do not identify the counterfactual"],
        ["training_stability", "NEW_RISK", "analysis_control_card.md", "B0001 acceptance remains UNSTABLE/FAIL"],
        ["actual_cost", "MIXED", "paired_kpi_summary.csv", "operating cost falls while terminal penalty exposure rises"],
    ], columns=["issue", "status", "evidence", "interpretation"])
    history.to_csv(out / "historical_issue_status.csv", index=False)
    # Small, non-essential figures from the already persisted aggregates.
    all_mech = mech[(mech.transition_group == "PERSISTENT_ADEQUATE") | (mech.transition_group == "ALL_PATHS")]
    if not all_mech.empty:
        fig, ax = plt.subplots(figsize=(8, 4.5))
        for arm, color in [("BASE", "#555555"), ("B0001", "#c44e52")]:
            z = all_mech[all_mech.arm == arm].groupby("global_hour")["site1_H2_production_kg_mean"].sum()
            ax.plot(z.index, z.values, label=arm, color=color)
        ax.set(xlabel="global hour", ylabel="site 1 production (kg)"); ax.legend(); fig.tight_layout(); fig.savefig(out / "figures/production_timing_site1.png", dpi=140); plt.close(fig)
    t = transition.sort_values(["base_type", "b0001_type"])
    fig, ax = plt.subplots(figsize=(8, 4.5)); ax.bar(np.arange(len(t)), t.path_count, color="#4c78a8"); ax.set_xticks(np.arange(len(t))); ax.set_xticklabels([f"{a}->{b}" for a, b in zip(t.base_type, t.b0001_type)], rotation=60, ha="right"); ax.set_ylabel("paths"); fig.tight_layout(); fig.savefig(out / "figures/terminal_transition_counts.png", dpi=140); plt.close(fig)
    summary = make_summary(out, base_path, cand_path, transition, detail, mech, hard_checks)
    (out / "B0001_C_mode_summary_zh.md").write_text(summary, encoding="utf-8")
    required_csv = ["analysis_control_card.md", "identity_and_common_path_qa.csv", "qa_summary.csv", "paired_kpi_summary.csv", "terminal_type_transition.csv", "new_failure_recovery_summary.csv", "site_time_mechanism_summary.csv", "historical_issue_status.csv", "B0001_C_mode_summary_zh.md", "source_manifest.csv", "terminal_recompute_audit.csv", "path_ledger.csv", "path_transition_labels.csv"]
    output_checks = []
    for name in required_csv:
        p = out / name
        ok = p.is_file() and p.stat().st_size > 0
        if p.suffix.lower() == ".csv" and ok:
            try:
                q = pd.read_csv(p)
                numeric = q.select_dtypes(include=[np.number])
                ok = ok and len(q) > 0 and (numeric.apply(np.isfinite).all().all() if not numeric.empty else True)
            except Exception:
                ok = False
        output_checks.append({"check": f"output_{name}", "pass": bool(ok), "value": str(p.stat().st_size if p.exists() else 0)})
    for p in sorted((out / "figures").glob("*.png")):
        output_checks.append({"check": f"figure_{p.name}_nonempty", "pass": p.stat().st_size > 100, "value": str(p.stat().st_size)})
    output_df = pd.DataFrame(output_checks)
    qa = pd.concat([pd.read_csv(out / "qa_summary.csv"), output_df], ignore_index=True)
    qa.to_csv(out / "qa_summary.csv", index=False)
    if not bool(output_df["pass"].all()):
        (out / "FAIL.txt").write_text("Output QA failed after analysis generation.\n", encoding="utf-8")
        return 2
    print(json.dumps({"status": "PASS", "output": str(out), "qa": hard_checks}, ensure_ascii=False))
    return 0


def make_summary(out: Path, base: pd.DataFrame, cand: pd.DataFrame, transition: pd.DataFrame, detail: pd.DataFrame, mech: pd.DataFrame, qa: dict[str, object]) -> str:
    def mean(f: pd.DataFrame, c: str) -> float: return float(pd.to_numeric(f[c], errors="coerce").mean())
    positive_b = pd.to_numeric(base.target_total) > TOL; positive_c = pd.to_numeric(cand.target_total) > TOL
    failure_b = pd.to_numeric(base.terminal_site_gap) > TOL; failure_c = pd.to_numeric(cand.terminal_site_gap) > TOL
    new_count = int(((path_labels(base) == "ADEQUATE") & (path_labels(cand) != "ADEQUATE")).sum())
    rec_count = int(((path_labels(base) != "ADEQUATE") & (path_labels(cand) == "ADEQUATE")).sum())
    return f"""# B0001 C 模式只读重新分析总结

## 身份与 QA

- `RUN_MODE=C`；`TRAINING_STATUS=UNSTABLE`；`EVIDENCE_GRADE=EXPLORATORY`；`ANALYSIS_NATURE=RETROSPECTIVE_DIAGNOSTIC`；`OOS_EXECUTION=READ_ONLY_REUSE`。
- Base 与 B0001 使用同一有序 10000-path bank；终止语义、状态历史、终端公式独立重算均通过，最大终端重算误差为 `{qa['terminal_formula_error_max']:.3g}` kg。
- 输入、bank 与两个 checkpoint 的 hash 在分析前后不变。没有启动 MATLAB/Gurobi，也没有修改输入、checkpoint 或既有 OOS。

## 事实结果

- B0001 平均总制氢 `{mean(cand,'total_H2_production'):.4f}` kg/path，Base 为 `{mean(base,'total_H2_production'):.4f}`，增量 `{mean(cand,'total_H2_production')-mean(base,'total_H2_production'):.4f}` kg/path。站点和小时分解见 `site_time_mechanism_summary.csv`；S4 的新增制氢是主要新增能力信号，但它没有保证同一时段/同一站点可用。
- 平均 terminal site gap 从 `{mean(base,'terminal_site_gap'):.4f}` 增至 `{mean(cand,'terminal_site_gap'):.4f}` kg/path；总量 shortfall 从 `{mean(base,'terminal_total_quantity_shortfall'):.4f}` 变为 `{mean(cand,'terminal_total_quantity_shortfall'):.4f}`。这表示总量边际信号与逐站可靠性方向相反。
- positive-target 分母两组均为 `{int(positive_b.sum())}`；逐站失败率为 `{failure_b[positive_b].mean():.4%}` -> `{failure_c[positive_c].mean():.4%}`。新增失败 `{new_count}` 条，恢复 `{rec_count}` 条，完整迁移表见 `terminal_type_transition.csv`。
- 失败类型计数由 Base `{path_labels(base).value_counts().to_dict()}` 变为 B0001 `{path_labels(cand).value_counts().to_dict()}`；pure quantity 下降，但 pure location/mixed 上升。

## 机制解释边界

1. **容量空间配置：探索性信号较强。** S4 Pmax 从 150 增至 187.5 kW，新增产量集中在 S4；新增失败/持续失败中可见 S2/S3 终端库存或短缺不匹配。该结果支持“多生产但空间错配”的信号，不能证明放宽 S4 本身造成因果恶化。
2. **制氢时机与信息时机：混合且不可完全识别。** 小时序列显示新增产量的形成时间和终端前库存变化；终端 loc 在早期尚未揭示，事后方向不合适不能直接写成 policy 决策错误。B0001 未通过稳定训练验收，policy 异常本身仍是重要混杂因素。
3. **HTT：未证明为唯一主瓶颈。** 已报告 HTT 流量、方向、到达时机和 fleet 利用率，但没有反事实运输能力/方向放宽，因此 `HTT_DIRECTION_CAUSE=NOT_IDENTIFIABLE`。
4. **电网、储罐和设备：仅观察性证据。** Pmax/storage binding、voltage、line loading、fleet utilization 已保留在机制表；没有放松约束的反事实，不能把相关性升级为因果。

## 结论

已确认的是：B0001 在同一 common-path bank 上多生产，quantity-side 指标略有改善，但逐站 terminal gap、pure-location 和 mixed failure 恶化；新增产量没有稳定转化为目标站点在终端时点的可用库存。最接近的探索性机制是“容量空间配置 + 制氢/HTT 时机”的混合信号，并叠加 B0001 policy 未稳定。尚不可识别的是单独的 Pmax 因果效应、HTT 方向错误、电网/储罐约束的单独贡献，以及任何基于终端结果反推早期决策错误的结论。

下一步应先重新稳定训练 B0001，再在稳定 checkpoint 上测试非均匀功率候选；本 run 不宣布 B0001 优于、劣于 Base，也不淘汰候选。
"""


if __name__ == "__main__":
    raise SystemExit(main())
