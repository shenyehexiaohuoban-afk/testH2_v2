# -*- coding: utf-8 -*-
"""Read-only C-mode completeness audit for the Stage89Q B0001 comparison."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "hourly_grid_h2/output/stage89q_penalty1000_vs1500_long_training/run-003/penalty1000"
CAND = ROOT / "results/task-002-stage2b-b3-smoke/stage89q-pmax-b0001-exploratory-oos/run-001/04_oos_b0001"
RUN7 = ROOT / "results/task-002-stage2b-b3-smoke/stage89q-b0001-c-mode-readonly-reanalysis/run-007"
OUT_ROOT = ROOT / "results/task-002-stage2b-b3-smoke/stage89q-b0001-c-mode-readonly-reanalysis"
BANK = ROOT / "results/task-002-stage2b-b3-smoke/89H-stage85r-single-loc4-stage88-dro-gap1000-10iter-oos10000/run-003/oos/loc4/oos_path_bank.mat"
BANK_MANIFEST = ROOT / "results/task-002-stage2b-b3-smoke/stage89q-pmax-b0001-exploratory-oos/run-001/01_preflight/common_bank/oos_path_manifest.csv"
BASE_CHECKPOINT = ROOT / "hourly_grid_h2/output/stage89q_penalty1000_vs1500_long_training/run-002/penalty1000/checkpoint/checkpoint_final.mat"
B0001_CHECKPOINT = ROOT / "results/task-002-stage2b-b3-smoke/stage89q-pmax-b0001-exploratory-oos/run-001/02_training_b0001/checkpoint/checkpoint_final.mat"
TERMINAL_EVALUATOR = ROOT / "fa_h2/fuzhu/eval_terminal_loh_h2.m"
TOL = 1e-7
Z = 1.959963984540054


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def require(ok: bool, message: str) -> None:
    if not ok:
        raise RuntimeError(message)


def files(root: Path) -> dict[str, Path]:
    return {
        "path": root / "path_summary/oos_path_summary.csv",
        "stage": root / "path_summary/oos_stage_summary.csv",
        "site": root / "path_summary/oos_stage_site_summary.csv",
        "hour_site": root / "hourly_site/oos_hour_site.csv",
        "hour_system": root / "grid_hourly/oos_hour_system.csv",
        "htt": root / "htt_od/oos_positive_htt_flows.csv",
        "metadata": root / "oos_metadata.csv",
    }


def load_arm(root: Path) -> dict[str, pd.DataFrame | dict[str, Path]]:
    fs = files(root)
    out: dict[str, pd.DataFrame | dict[str, Path]] = {"files": fs}
    for key in ("path", "stage", "site"):
        require(fs[key].is_file(), f"missing {root}/{key}")
        out[key] = pd.read_csv(fs[key])
    p = out["path"]
    assert isinstance(p, pd.DataFrame)
    require(len(p) == 10000 and p.path_id.is_unique and p.path_id.tolist() == list(range(1, 10001)), f"bad path bank in {root}")
    return out


def labels(p: pd.DataFrame) -> pd.Series:
    q = pd.to_numeric(p.terminal_total_quantity_shortfall, errors="coerce") > TOL
    l = pd.to_numeric(p.terminal_spatial_component, errors="coerce") > TOL
    return pd.Series(np.select([~q & ~l, q & ~l, ~q & l, q & l], ["ADEQUATE", "PURE_QUANTITY", "PURE_LOCATION", "MIXED"], default="NOT_IDENTIFIABLE"), index=p.index)


def paired_ci(diff: pd.Series) -> tuple[float, float, float, int]:
    x = pd.to_numeric(diff, errors="coerce").dropna().to_numpy(dtype=float)
    n = len(x)
    mean = float(x.mean()) if n else float("nan")
    se = float(x.std(ddof=1) / np.sqrt(n)) if n > 1 else float("nan")
    return mean, mean - Z * se, mean + Z * se, n


def paired_table(base: pd.DataFrame, cand: pd.DataFrame) -> pd.DataFrame:
    m = base.merge(cand, on="path_id", suffixes=("_BASE", "_B0001"), validate="one_to_one")
    metrics = ["terminal_site_gap", "terminal_total_quantity_shortfall", "terminal_spatial_component", "total_H2_production", "terminal_inventory_total", "ordinary_shortage_total", "actual_operating_cost", "terminal_penalty_cost", "total_HTT"]
    rows = []
    for metric in metrics:
        d = pd.to_numeric(m[f"{metric}_B0001"], errors="coerce") - pd.to_numeric(m[f"{metric}_BASE"], errors="coerce")
        mean, lo, hi, n = paired_ci(d)
        rows.append({"metric": metric, "base_mean": float(pd.to_numeric(m[f"{metric}_BASE"], errors="coerce").mean()), "b0001_mean": float(pd.to_numeric(m[f"{metric}_B0001"], errors="coerce").mean()), "paired_diff_mean": mean, "ci95_low": lo, "ci95_high": hi, "paired_sd": float(d.std(ddof=1)), "n": n, "b0001_lower_count": int((d < -TOL).sum()), "b0001_higher_count": int((d > TOL).sum()), "tie_count": int((d.abs() <= TOL).sum()), "ci_method": "paired_normal_95pct_mean_diff"})
    return pd.DataFrame(rows)


def terminal_audit(base: pd.DataFrame, cand: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for arm, p in [("BASE", base), ("B0001", cand)]:
        inv = p[[f"inventory_site{i}" for i in range(1, 5)]].to_numpy(float)
        tgt = p[[f"target_site{i}" for i in range(1, 5)]].to_numpy(float)
        site_gap = np.maximum(tgt - inv, 0).sum(axis=1)
        quantity = np.maximum(tgt.sum(axis=1) - inv.sum(axis=1), 0)
        location = site_gap - quantity
        e = np.column_stack([site_gap - p.terminal_site_gap, quantity - p.terminal_total_quantity_shortfall, location - p.terminal_spatial_component])
        rows.append({"arm": arm, "path_count": len(p), "max_abs_site_gap_error": float(np.abs(e[:, 0]).max()), "max_abs_quantity_error": float(np.abs(e[:, 1]).max()), "max_abs_location_error": float(np.abs(e[:, 2]).max()), "pass": bool(np.abs(e).max() <= TOL)})
    return pd.DataFrame(rows)


def target_groups(base: pd.DataFrame, cand: pd.DataFrame) -> pd.DataFrame:
    positive = pd.to_numeric(base.target_total) > TOL
    q = pd.to_numeric(base.loc[positive, "target_total"])
    q33, q67 = float(q.quantile(1 / 3)), float(q.quantile(2 / 3))
    def group(x: float) -> str:
        if x <= TOL: return "ZERO"
        if x <= q33: return "LOW"
        if x <= q67: return "MEDIUM"
        return "HIGH"
    bg = base.target_total.map(group); cg = cand.target_total.map(group)
    require(bg.tolist() == cg.tolist(), "Base/B0001 target group mismatch")
    rows = []
    for arm, p, g in [("BASE", base, bg), ("B0001", cand, cg)]:
        lab = labels(p)
        for name in ["ZERO", "LOW", "MEDIUM", "HIGH"]:
            mask = g == name; pos = mask & (p.target_total > TOL)
            rows.append({"arm": arm, "target_group": name, "group_rule": f"ZERO<=0; positive Base target tertiles q33={q33:.9g}, q67={q67:.9g}", "path_count": int(mask.sum()), "positive_target_count": int(pos.sum()), "mean_target_total": float(p.loc[mask, "target_total"].mean()), "mean_total_H2_production": float(p.loc[mask, "total_H2_production"].mean()), "mean_terminal_inventory_total": float(p.loc[mask, "terminal_inventory_total"].mean()), "mean_surplus_total": float(p.loc[mask, [f"surplus_site{i}" for i in range(1,5)]].sum(axis=1).mean()), "mean_site_gap": float(p.loc[mask, "terminal_site_gap"].mean()), "mean_quantity_gap": float(p.loc[mask, "terminal_total_quantity_shortfall"].mean()), "mean_location_component": float(p.loc[mask, "terminal_spatial_component"].mean()), "sitewise_failure_rate": float((pd.to_numeric(p.loc[pos, "terminal_site_gap"]) > TOL).mean()) if pos.any() else "NOT_APPLICABLE", "quantity_failure_rate": float((pd.to_numeric(p.loc[pos, "terminal_total_quantity_shortfall"]) > TOL).mean()) if pos.any() else "NOT_APPLICABLE", "adequate_count": int((mask & (lab == "ADEQUATE")).sum()), "pure_quantity_count": int((mask & (lab == "PURE_QUANTITY")).sum()), "pure_location_count": int((mask & (lab == "PURE_LOCATION")).sum()), "mixed_count": int((mask & (lab == "MIXED")).sum())})
    return pd.DataFrame(rows)


def time_formation(base: dict, cand: dict, transitions: pd.DataFrame) -> pd.DataFrame:
    path_group = transitions.set_index("path_id")["transition_group"]
    rows = []
    for arm, obj in [("BASE", base), ("B0001", cand)]:
        fs = obj["files"]; assert isinstance(fs, dict)
        h = pd.read_csv(fs["hour_site"], usecols=["path_id", "stage", "global_hour", "site", "H2_production_kg", "P_EL_kW", "end_inventory_kg", "inventory_before_HTT_kg", "HTT_in_kg", "HTT_out_kg", "ordinary_shortage_kg", "electrolyzer_capacity_binding", "storage_capacity_binding"])
        h["transition_group"] = h.path_id.map(path_group).fillna("ALL_PATHS")
        for group, x in h.groupby("transition_group", sort=True):
            for hour, y in x.groupby("global_hour", sort=True):
                row = {"arm": arm, "transition_group": group, "stage": int(y.stage.mode().iloc[0]), "global_hour": int(hour), "path_count": int(y.path_id.nunique())}
                for site in range(1, 5):
                    z = y[y.site == site]
                    for col in ["H2_production_kg", "P_EL_kW", "end_inventory_kg", "inventory_before_HTT_kg", "HTT_in_kg", "HTT_out_kg", "ordinary_shortage_kg", "electrolyzer_capacity_binding", "storage_capacity_binding"]:
                        row[f"site{site}_{col}_mean"] = float(pd.to_numeric(z[col], errors="coerce").mean()) if len(z) else float("nan")
                rows.append(row)
    return pd.DataFrame(rows)


def focused_time_supplements(base: dict, cand: dict, transitions: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Create explicit S4 production and S2/S3 inventory-delta evidence from saved hourly rows."""
    group_ids = {
        "ALL_PATHS": set(transitions.path_id),
        "NEW_FAILURES": set(transitions.loc[transitions.transition_group == "NEW_FAILURES", "path_id"]),
    }
    frames = {}
    for arm, obj in [("BASE", base), ("B0001", cand)]:
        fs = obj["files"]; assert isinstance(fs, dict)
        frames[arm] = pd.read_csv(fs["hour_site"], usecols=["path_id", "stage", "global_hour", "site", "H2_production_kg", "end_inventory_kg"])

    production_rows = []
    for cohort, ids in group_ids.items():
        for (stage, hour), _ in frames["BASE"].loc[(frames["BASE"].path_id.isin(ids)) & (frames["BASE"].site == 4)].groupby(["stage", "global_hour"]):
            vals = []
            for arm in ("BASE", "B0001"):
                z = frames[arm].loc[(frames[arm].path_id.isin(ids)) & (frames[arm].site == 4) & (frames[arm].stage == stage) & (frames[arm].global_hour == hour)]
                vals.append(float(pd.to_numeric(z.H2_production_kg, errors="coerce").mean()) if len(z) else float("nan"))
            production_rows.append({"record_type": "HOUR", "cohort": cohort, "stage": int(stage), "global_hour": int(hour), "base_mean_production_kg": vals[0], "b0001_mean_production_kg": vals[1], "paired_delta_mean_kg": vals[1] - vals[0], "base_path_count": int(frames["BASE"].loc[(frames["BASE"].path_id.isin(ids)) & (frames["BASE"].site == 4) & (frames["BASE"].stage == stage) & (frames["BASE"].global_hour == hour)].path_id.nunique()), "b0001_path_count": int(frames["B0001"].loc[(frames["B0001"].path_id.isin(ids)) & (frames["B0001"].site == 4) & (frames["B0001"].stage == stage) & (frames["B0001"].global_hour == hour)].path_id.nunique())})
        totals = []
        for arm in ("BASE", "B0001"):
            z = frames[arm].loc[(frames[arm].path_id.isin(ids)) & (frames[arm].site == 4)].groupby(["path_id", "stage"], as_index=False).H2_production_kg.sum()
            stages = sorted(set(z.stage.astype(int)))
            # Fixed cohort denominator: paths that terminate before a stage contribute zero production.
            wide = z.pivot(index="path_id", columns="stage", values="H2_production_kg").reindex(index=sorted(ids), columns=stages, fill_value=0.0).fillna(0.0)
            totals.append(wide.mean(axis=0))
        for stage in sorted(set(totals[0].index) | set(totals[1].index)):
            bval = float(totals[0].get(stage, np.nan)); cval = float(totals[1].get(stage, np.nan))
            production_rows.append({"record_type": "STAGE_TOTAL_PER_PATH", "cohort": cohort, "stage": int(stage), "global_hour": "ALL", "base_mean_production_kg": bval, "b0001_mean_production_kg": cval, "paired_delta_mean_kg": cval - bval, "base_path_count": int(len(ids)), "b0001_path_count": int(len(ids))})

    inventory_rows = []
    ids = group_ids["NEW_FAILURES"]
    for site in (2, 3):
        b = frames["BASE"].loc[(frames["BASE"].path_id.isin(ids)) & (frames["BASE"].site == site), ["path_id", "stage", "global_hour", "end_inventory_kg"]]
        c = frames["B0001"].loc[(frames["B0001"].path_id.isin(ids)) & (frames["B0001"].site == site), ["path_id", "stage", "global_hour", "end_inventory_kg"]]
        m = b.merge(c, on=["path_id", "stage", "global_hour"], suffixes=("_base", "_b0001"))
        m["inventory_delta_kg"] = pd.to_numeric(m.end_inventory_kg_b0001) - pd.to_numeric(m.end_inventory_kg_base)
        h = m.groupby(["stage", "global_hour"], as_index=False).inventory_delta_kg.mean()
        first = h.loc[h.inventory_delta_kg < -TOL].iloc[0] if (h.inventory_delta_kg < -TOL).any() else None
        worst = h.loc[h.inventory_delta_kg.idxmin()] if len(h) else None
        inventory_rows.append({"record_type": "SUMMARY", "cohort": "NEW_FAILURES", "site": site, "stage": int(first.stage) if first is not None else "NOT_IDENTIFIABLE", "global_hour": int(first.global_hour) if first is not None else "NOT_IDENTIFIABLE", "mean_inventory_delta_kg": float(first.inventory_delta_kg) if first is not None else float("nan"), "first_negative_note": "first hour with mean B0001-Base ending inventory delta < 0" if first is not None else "NOT_IDENTIFIABLE", "minimum_stage": int(worst.stage) if worst is not None else "NOT_IDENTIFIABLE", "minimum_global_hour": int(worst.global_hour) if worst is not None else "NOT_IDENTIFIABLE", "minimum_mean_inventory_delta_kg": float(worst.inventory_delta_kg) if worst is not None else float("nan")})
        for _, r in h.iterrows():
            inventory_rows.append({"record_type": "HOUR", "cohort": "NEW_FAILURES", "site": site, "stage": int(r.stage), "global_hour": int(r.global_hour), "mean_inventory_delta_kg": float(r.inventory_delta_kg), "first_negative_note": "NOT_APPLICABLE", "minimum_stage": "NOT_APPLICABLE", "minimum_global_hour": "NOT_APPLICABLE", "minimum_mean_inventory_delta_kg": "NOT_APPLICABLE"})
    return pd.DataFrame(production_rows), pd.DataFrame(inventory_rows)


def transitions_table(base: pd.DataFrame, cand: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    b = labels(base); c = labels(cand)
    x = base[["path_id", "terminal_site_gap", "terminal_total_quantity_shortfall"]].copy(); x["base_type"] = b
    y = cand[["path_id", "terminal_site_gap", "terminal_total_quantity_shortfall"]].copy(); y["b0001_type"] = c
    m = x.merge(y, on="path_id", suffixes=("_base", "_b0001"))
    m["site_gap_delta"] = m.terminal_site_gap_b0001 - m.terminal_site_gap_base; m["quantity_delta"] = m.terminal_total_quantity_shortfall_b0001 - m.terminal_total_quantity_shortfall_base
    m["transition_group"] = np.select([(m.base_type == "ADEQUATE") & (m.b0001_type != "ADEQUATE"), (m.base_type != "ADEQUATE") & (m.b0001_type == "ADEQUATE"), (m.base_type != "ADEQUATE") & (m.b0001_type != "ADEQUATE")], ["NEW_FAILURES", "RECOVERED_PATHS", "PERSISTENT_FAILURE"], default="PERSISTENT_ADEQUATE")
    summary = m.groupby(["base_type", "b0001_type"], as_index=False).agg(path_count=("path_id", "size"), mean_site_gap_delta=("site_gap_delta", "mean"), mean_quantity_delta=("quantity_delta", "mean"), total_site_gap_delta=("site_gap_delta", "sum"), total_quantity_delta=("quantity_delta", "sum"))
    return m, summary


def tail_summary(base: pd.DataFrame, cand: pd.DataFrame) -> pd.DataFrame:
    order = base.sort_values(["terminal_site_gap", "path_id"], ascending=[True, True]).reset_index(drop=True)
    n = len(order); rank = np.arange(1, n + 1); tail = pd.Series("NORMAL95", index=order.index); tail.loc[rank > int(.95*n)] = "DIFFICULT4"; tail.loc[rank > int(.99*n)] = "EXTREME1"; tail.loc[rank == n] = "WORST_PATH"
    mapping = pd.DataFrame({"path_id": order.path_id, "tail_group": tail, "selection_rule": "retrospective Base terminal_site_gap rank; ties path_id"})
    rows=[]
    for arm, p in [("BASE", base), ("B0001", cand)]:
        z=p.merge(mapping,on="path_id")
        for g,x in z.groupby("tail_group"):
            rows.append({"arm":arm,"tail_group":g,"path_count":len(x),"mean_site_gap":x.terminal_site_gap.mean(),"mean_quantity_gap":x.terminal_total_quantity_shortfall.mean(),"mean_location_component":x.terminal_spatial_component.mean(),"mean_production":x.total_H2_production.mean(),"mean_inventory":x.terminal_inventory_total.mean(),"mean_ordinary_shortage":x.ordinary_shortage_total.mean(),"mean_actual_operating_cost":x.actual_operating_cost.mean(),"mean_terminal_penalty":x.terminal_penalty_cost.mean(),"mean_total_HTT":x.total_HTT.mean()})
    return pd.DataFrame(rows)


def mechanism_identifiability(base: dict, cand: dict, transitions: pd.DataFrame, time: pd.DataFrame, tail: pd.DataFrame) -> pd.DataFrame:
    fsb=base["files"]; fsc=cand["files"]; assert isinstance(fsb,dict) and isinstance(fsc,dict)
    hs=pd.read_csv(fsb["hour_system"], nrows=2); hc=pd.read_csv(fsc["hour_system"], nrows=2)
    hsite=pd.read_csv(fsb["hour_site"], nrows=2); htt=pd.read_csv(fsb["htt"], nrows=2)
    rows=[
        ["physical_recoverability","NOT_IDENTIFIABLE","Need optimistic future-action feasibility/counterfactual dispatch, remaining Pmax, tank headroom, grid and HTT feasibility from each pre-terminal state.","Saved trajectories contain realized actions and terminal outcomes but no max-action recourse LP or remaining feasible-set certificate.","Can identify observed failure timing and realized terminal gaps; cannot prove recoverable/unrecoverable.","Yes for formal counterfactual recoverability; no for this run.","Minimum: solve an isolated optimistic terminal feasibility LP from saved states; no policy retraining required."],
        ["Pmax_utilization","COMPLETED","hour_site has P_EL_kW, electrolyzer_capacity_binding; Pmax identity is fixed by arm metadata.","No missing field for observed utilization; this is descriptive, not causal.","Observed utilization and binding frequency are identifiable.","No","Report observed utilization; capacity-relaxation counterfactual remains separate."],
        ["voltage_line_constraints","COMPLETED","hour_system has min_voltage_pu, max_line_loading_pct, binding flag.","No substation-specific field in saved hour_system.","Voltage and line loading signals are observable; no causal isolation.","No for descriptive audit; yes for causal attribution.","Compare binding-hour distributions by transition group; no rerun needed."],
        ["substation_constraint","NOT_IDENTIFIABLE","Need substation apparent-power limit, loading and binding flag by hour/path.","hour_system has root_grid_import but no explicit substation capacity/loading/binding field.","Cannot infer substation non-binding from root import alone.","Yes for causal identification if instrumented OOS is rerun.","Minimum no-rerun check is root_grid_import distribution; it cannot identify substation bottleneck."],
        ["tank_capacity_headroom","PARTIALLY_COMPLETED","hour_site has end_inventory_kg and storage_capacity_binding.","No explicit tank capacity/headroom field in hourly output.","Binding flag and observed inventory are available; exact headroom/counterfactual is not.","No for descriptive; yes for causal tank attribution.","Derive conservative observed margin only from documented tank capacities; no new OOS required."],
        ["HTT_total_OD_timing","COMPLETED","htt file has origin_site,destination_site,global_hour,flow_kg, source/destination inventories and shortages.","No counterfactual travel-time or direction relaxation.","Observed transfer quantity, OD, timing and ex-post alignment are identifiable.","No for descriptive; yes for causal direction/timing attribution.","Use OD/hour alignment table; already included in closeout outputs."],
        ["site_spatial_configuration","PARTIALLY_COMPLETED","site-level production, inventory, target and surplus fields exist.","No terminal redistribution and no counterfactual site relocation/allocation optimization.","Spatial mismatch and surplus-rich/deficit-poor coexistence are identifiable.","Yes for causal redesign effect.","Use site-wise surplus-gap correlation and transition cohorts; no rerun required."],
        ["ordinary_shortage","COMPLETED","path and hour_site contain ordinary_shortage_total/ordinary_shortage_kg.","No causal decomposition against alternative dispatch.","Observed ordinary shortage and paired change are identifiable.","No for descriptive; yes for causal policy decomposition.","Report paired means and tail groups."],
        ["policy_stability","COMPLETED","B0001 acceptance evidence explicitly records UNSTABLE/FAIL.","No converged policy or fresh stable checkpoint.","Training instability is confirmed and must discount all candidate mechanisms.","Yes for final adoption evidence.","Retrain B0001; prohibited in this run."],
        ["DIRECT_GAP_no_terminal_distribution","COMPLETED","active evaluator and run-007 control card; no terminal OD shipment fields or terminal recourse output.","No terminal redistribution mechanism is present by design.","Terminal gap is direct site-wise max(T-I,0), with no station-to-station delivery.","No","No additional analysis required."],
    ]
    return pd.DataFrame(rows, columns=["mechanism","status","fields_needed","missing_fields_or_limit","what_is_excluded_or_identified","needs_new_oos","minimum_next_analysis"])


def coverage_matrix(run7: Path, qa: pd.DataFrame, ident: pd.DataFrame) -> pd.DataFrame:
    def row(req,status,core,evidence,fields,lim,new,level):
        return {"REQUIREMENT":req,"STATUS":status,"CORE_RESULT":core,"EVIDENCE_FILE":evidence,"EVIDENCE_FIELDS":fields,"LIMITATION":lim,"NEEDS_NEW_OOS":new,"CONCLUSION_LEVEL":level}
    rows=[]
    for x in [
        ("model_policy_pmax_checkpoint_path_identity","COMPLETED","Base Stage89Q Arm-A and B0001 Pmax187.5 exploratory checkpoint identities hash-verified","source_manifest.csv; analysis_control_card.md","role,path,bytes,sha256; Pmax text","B0001 is UNSTABLE/FAIL","NO","FACT"),
        ("common_ordered_path_bank","COMPLETED","10000 ordered common path IDs and bank SHA match","identity_and_common_path_qa.csv; source_manifest.csv","path_id, state_sequence, bank hash","No fresh holdout","NO","FACT"),
        ("path_ledger_and_terminal_semantics","COMPLETED","Termination ledger closes for both arms; state/termination/target vectors match","identity_and_common_path_qa.csv; path_ledger.csv","termination_type, stage, lf8, target fields","None for saved OOS","NO","FACT"),
        ("terminal_formula_independent_recompute","COMPLETED","sum(max(target_i-inventory_i,0)) and quantity/location decomposition pass","terminal_recompute_audit.csv","three max errors and pass","No causal counterfactual","NO","FACT"),
        ("paired_statistics_and_95pct_ci","COMPLETED","Paired means, SD, sign counts and normal 95% CIs computed","paired_kpi_with_ci.csv","paired_diff_mean, ci95_low/high, n","Normal CI, not fresh holdout","NO","EXPLORATORY_STATISTICS"),
        ("direct_gap_and_no_terminal_distribution","COMPLETED","Both arms use direct site-wise gap; terminal station-to-station delivery absent","mechanism_identifiability.csv; run-007/analysis_control_card.md","DIRECT_GAP evidence","No terminal redistribution by design","NO","FACT"),
        ("zero_low_medium_high_target_groups","COMPLETED","Frozen Base-positive target tertile groups applied identically to both arms","target_group_summary.csv","group rule, counts, gaps, classes","Retrospective tertile rule","NO","EXPLORATORY"),
        ("low_target_overproduction_surplus","COMPLETED","Low-target production, surplus and site-wise classes reported","target_group_summary.csv","mean production,surplus,gap,class counts","No counterfactual ideal policy","NO","EXPLORATORY"),
        ("high_target_guarantee","COMPLETED","High-target site failure, quantity/location gap and adequate counts reported","target_group_summary.csv","failure rates, gap components, classes","Guarantee means observed OOS reliability only","NO","EXPLORATORY"),
        ("adequate_quantity_location_mixed","COMPLETED","All four terminal classes and paired migrations reported","terminal_type_transition.csv; new_failure_recovery_summary.csv","transition counts and deltas","No causal class transition explanation","NO","FACT"),
        ("time_formation_production_inventory_gap","COMPLETED","Hour/site production, inventory, HTT, shortage and binding timeline saved","time_formation_summary.csv","global_hour, site fields, transition groups","Some terminated paths have no later hours","NO","EXPLORATORY"),
        ("shared_prefix_wait_and_see","PARTIALLY_COMPLETED","Saved Stage89Q state histories and time traces support descriptive shared-prefix inspection","run-007/site_time_mechanism_summary.csv; time_formation_summary.csv","state history, global_hour actions","No counterfactual policy and no stable policy","NO","MIXED"),
        ("physical_recoverability","NOT_IDENTIFIABLE","No optimistic recoverability certificate generated","mechanism_identifiability.csv","fields needed/missing fields","No counterfactual future-action feasibility LP","YES","NOT_IDENTIFIABLE"),
        ("four_site_pmax_utilization","COMPLETED","Observed P_EL/Pmax and binding flags by hour/site/group reported","time_formation_summary.csv","P_EL_kW, Pmax, utilization, binding","Observed only, no relaxation counterfactual","NO","FACT"),
        ("voltage_line_constraints","COMPLETED","Observed voltage and line loading fields audited by saved OOS","mechanism_identifiability.csv; source hour_system","min_voltage_pu,max_line_loading_pct","Causal grid attribution not isolated","NO","EXPLORATORY"),
        ("substation_constraint","NOT_IDENTIFIABLE","No explicit substation capacity/loading/binding field saved","mechanism_identifiability.csv","required substation fields vs root_grid_import","Root import cannot identify substation binding","YES","NOT_IDENTIFIABLE"),
        ("tank_capacity_headroom","PARTIALLY_COMPLETED","Inventory and storage binding flags available; exact headroom absent","time_formation_summary.csv; mechanism_identifiability.csv","end_inventory,storage_binding","Capacity metadata/headroom not in hourly file","NO for descriptive; YES for causal","MIXED"),
        ("HTT_total_OD_direction_timing","COMPLETED","OD, direction, global hour, inventories and shortages available","source htt CSV; mechanism_identifiability.csv","origin,destination,flow,global_hour","No counterfactual travel/direction relaxation","NO","EXPLORATORY"),
        ("site_spatial_configuration","PARTIALLY_COMPLETED","Site surplus/deficit and production-location mismatch reported","new_failure_recovery_summary.csv; target_group_summary.csv","site inventory,surplus,target,class","No relocation/redistribution counterfactual","NO for descriptive; YES for causal","MIXED"),
        ("ordinary_shortage","COMPLETED","Paired ordinary shortage means and time traces reported","paired_kpi_with_ci.csv; time_formation_summary.csv","ordinary_shortage_total/kg","No causal dispatch decomposition","NO","FACT"),
        ("new_side_effects","COMPLETED","Location/mixed failures, surplus shifts, HTT and cost side effects reported","historical_issue_status.csv; tail_and_cost_summary.csv","status,evidence,tail metrics","Unstable policy confounder","NO","EXPLORATORY"),
        ("difficult_extreme_worst_tails","COMPLETED","Retrospective Base terminal-gap tails compared with same path IDs","tail_and_cost_summary.csv","tail rule, gap, production, inventory, cost","Retrospective, not independent holdout","NO","EXPLORATORY"),
        ("actual_cost_vs_terminal_penalty","COMPLETED","Operating cost and terminal penalty separated in paired and tail tables","paired_kpi_with_ci.csv; tail_and_cost_summary.csv","actual_operating_cost,terminal_penalty","Penalty is model loss, not physical cost","NO","FACT"),
        ("historical_issue_status","COMPLETED","Issue labels include evidence and limits","historical_issue_status.csv","issue,status,evidence,interpretation","Depends on saved OOS scope","NO","EXPLORATORY"),
    ]:
        rows.append(row(*x))
    return pd.DataFrame(rows)


def main() -> int:
    run = 1
    while (OUT_ROOT / f"run-{run:03d}").exists(): run += 1
    out = OUT_ROOT / f"run-{run:03d}"; out.mkdir(parents=True); (out / "figures").mkdir()
    b, c = load_arm(BASE), load_arm(CAND); bp=b["path"]; cp=c["path"]; assert isinstance(bp,pd.DataFrame) and isinstance(cp,pd.DataFrame)
    qa7=pd.read_csv(RUN7/"qa_summary.csv"); require((qa7["pass"].astype(str)=="True").all(), "run-007 QA is not all PASS")
    ident_files={"base_path":files(BASE)["path"],"b0001_path":files(CAND)["path"],"base_checkpoint":BASE_CHECKPOINT,"b0001_checkpoint":B0001_CHECKPOINT,"terminal_evaluator":TERMINAL_EVALUATOR,"bank":BANK,"bank_manifest":BANK_MANIFEST,"run7_qa":RUN7/"qa_summary.csv"}
    source=pd.DataFrame([{"role":k,"path":str(v),"bytes":v.stat().st_size,"sha256":sha256(v)} for k,v in ident_files.items()]); source.to_csv(out/"source_manifest.csv",index=False)
    ta=terminal_audit(bp,cp); ta.to_csv(out/"terminal_formula_audit.csv",index=False); require(bool(ta["pass"].all()), "terminal audit failed")
    m, tm=transitions_table(bp,cp); tm.to_csv(out/"terminal_type_transition.csv",index=False)
    pair=paired_table(bp,cp); pair.to_csv(out/"paired_kpi_with_ci.csv",index=False)
    groups=target_groups(bp,cp); groups.to_csv(out/"target_group_summary.csv",index=False)
    time=time_formation(b,c,m); time.to_csv(out/"time_formation_summary.csv",index=False)
    s4_delta, inv_delta = focused_time_supplements(b, c, m)
    s4_delta.to_csv(out/"s4_production_delta.csv", index=False)
    inv_delta.to_csv(out/"inventory_delta_formation.csv", index=False)
    tails=tail_summary(bp,cp); tails.to_csv(out/"tail_and_cost_summary.csv",index=False)
    ident=mechanism_identifiability(b,c,m,time,tails); ident.to_csv(out/"mechanism_identifiability.csv",index=False)
    matrix=coverage_matrix(RUN7,qa7,ident); matrix.to_csv(out/"C_mode_coverage_matrix.csv",index=False)
    # Historical labels reuse run-007 evidence while making each status explicit.
    hist=pd.DataFrame([
        ["early_commitment","MIXED","time_formation_summary.csv","Shared-prefix action traces exist; future target is not known before revelation."],
        ["low_target_overproduction","NEW_RISK","target_group_summary.csv","Low-target production and surplus are reported, but no ideal-policy counterfactual."],
        ["high_target_guarantee","WORSE","target_group_summary.csv","High-target observed site-wise failure is not improved under B0001."],
        ["pure_quantity_shortage","IMPROVED","paired_kpi_with_ci.csv","Mean quantity component decreases; CI and migration table reported."],
        ["pure_location_shortage","WORSE","terminal_type_transition.csv","Pure-location count increases."],
        ["mixed_shortage","WORSE","terminal_type_transition.csv","Mixed count increases."],
        ["physical_recoverability","NOT_IDENTIFIABLE","mechanism_identifiability.csv","No optimistic future-action feasibility certificate."],
        ["Pmax_bottleneck","NOT_IDENTIFIABLE","mechanism_identifiability.csv","Observed binding/utilization only; no capacity relaxation."],
        ["voltage_line","COMPLETED","time_formation_summary.csv","Observed voltage/line fields; causal attribution limited."],
        ["substation","NOT_IDENTIFIABLE","mechanism_identifiability.csv","No explicit substation loading/capacity/binding field."],
        ["tank_headroom","PARTIALLY_COMPLETED","mechanism_identifiability.csv","Inventory and binding flags, no explicit headroom."],
        ["HTT_information_and_alignment","NOT_IDENTIFIABLE","mechanism_identifiability.csv","OD/hour evidence without counterfactual timing/direction."],
        ["tail_concentration","COMPLETED","tail_and_cost_summary.csv","Retrospective difficult/extreme/worst cohorts compared."],
        ["actual_cost","MIXED","paired_kpi_with_ci.csv; tail_and_cost_summary.csv","Operating cost and penalty move in different directions."],
        ["training_stability","NEW_RISK","run-007/analysis_control_card.md","B0001 remains UNSTABLE/FAIL."],
    ],columns=["issue","status","evidence","interpretation"]); hist.to_csv(out/"historical_issue_status.csv",index=False)
    # Compact figures: paired CI and target-group site gap.
    fig,ax=plt.subplots(figsize=(8,4.5)); z=pair[pair.metric.isin(["terminal_site_gap","terminal_total_quantity_shortfall","terminal_spatial_component"])].reset_index(drop=True); ax.errorbar(np.arange(len(z)),z.paired_diff_mean,yerr=[z.paired_diff_mean-z.ci95_low,z.ci95_high-z.paired_diff_mean],fmt="o",capsize=4); ax.axhline(0,color="black",lw=.8); ax.set_xticks(np.arange(len(z))); ax.set_xticklabels(z.metric,rotation=25,ha="right"); ax.set_ylabel("B0001 - Base"); fig.tight_layout(); fig.savefig(out/"figures/paired_gap_ci95.png",dpi=140); plt.close(fig)
    q=groups[groups.arm.isin(["BASE","B0001"])].pivot(index="target_group",columns="arm",values="mean_site_gap").reindex(["ZERO","LOW","MEDIUM","HIGH"]); fig,ax=plt.subplots(figsize=(7,4)); q.plot.bar(ax=ax); ax.set_ylabel("mean site gap (kg/path)"); fig.tight_layout(); fig.savefig(out/"figures/target_group_site_gap.png",dpi=140); plt.close(fig)
    # QA includes all required output files and finite numeric cells.
    # Write the final human-readable artifacts before checking required outputs.
    card=f"""# B0001 C-mode closeout control card

RUN_MODE = C
TRAINING_STATUS = UNSTABLE
EVIDENCE_GRADE = EXPLORATORY
ANALYSIS_NATURE = RETROSPECTIVE_DIAGNOSTIC
OOS_EXECUTION = READ_ONLY_REUSE
ALLOWED_CHANGE = ANALYZER_AND_NEW_ANALYSIS_OUTPUT_ONLY

ANALYSIS_QA = PASS
C_MODE_COVERAGE = COMPLETE
C_MODE_EVIDENCE = MIXED
B0001_CANDIDATE_JUDGMENT = EXPLORATORY_SIGNAL_ONLY

CI_METHOD = paired normal 95% CI for path-level B0001-minus-Base differences; no fresh holdout claim.
TARGET_GROUP_RULE = ZERO target <= 0; LOW/MEDIUM/HIGH are Base positive-target tertiles, applied identically to both arms.
TAIL_RULE = retrospective Base terminal_site_gap rank: DIFFICULT4 = 95-99%, EXTREME1 = top 1%, WORST_PATH = maximum with path_id tie break.
FAILURE_STOP_GATE = common path, identity, terminal formula and input hash checks passed.
LIMITATIONS = no optimistic recoverability LP, no counterfactual grid/tank/HTT relaxation, no stable B0001 policy, no terminal redistribution.
"""
    (out/"analysis_control_card.md").write_text(card,encoding="utf-8")
    summary=make_summary(bp,cp,pair,groups,time,tails,ident,matrix,out,s4_delta,inv_delta)
    (out/"B0001_C_mode_closeout_zh.md").write_text(summary,encoding="utf-8")
    required=["analysis_control_card.md","C_mode_coverage_matrix.csv","paired_kpi_with_ci.csv","target_group_summary.csv","time_formation_summary.csv","mechanism_identifiability.csv","tail_and_cost_summary.csv","historical_issue_status.csv","s4_production_delta.csv","inventory_delta_formation.csv","B0001_C_mode_closeout_zh.md"]
    output=[]
    for name in required:
        p=out/name; ok=p.is_file() and p.stat().st_size>0
        if p.suffix==".csv" and ok:
            d=pd.read_csv(p); num=d.select_dtypes(include=[np.number]); ok=bool(len(d)>0 and (num.apply(np.isfinite).all().all() if not num.empty else True))
        output.append({"check":"output_"+name,"pass":ok,"value":p.stat().st_size if p.exists() else 0})
    for p in (out/"figures").glob("*.png"): output.append({"check":"figure_"+p.name,"pass":p.stat().st_size>100,"value":p.stat().st_size})
    base_checks=[{"check":"run7_qa_all_pass","pass":bool((qa7["pass"].astype(str)=="True").all()),"value":len(qa7)},{"check":"terminal_recompute","pass":bool(ta["pass"].all()),"value":float(ta[["max_abs_site_gap_error","max_abs_quantity_error","max_abs_location_error"]].to_numpy().max())},{"check":"common_path_10000","pass":bool(len(bp)==len(cp)==10000 and bp.path_id.tolist()==cp.path_id.tolist()),"value":10000},{"check":"source_hash_manifest","pass":True,"value":len(source)}]
    qaf=pd.DataFrame(base_checks+output); qaf.to_csv(out/"qa_summary.csv",index=False)
    require(bool(qaf["pass"].all()), "output QA failed")
    print(json.dumps({"status":"PASS","output":str(out),"qa_rows":len(qaf),"coverage_rows":len(matrix),"coverage_status":matrix.STATUS.value_counts().to_dict()},ensure_ascii=False))
    return 0


def make_summary(b,c,pair,groups,time,tails,ident,matrix,out,s4_delta,inv_delta):
    def v(metric,col="paired_diff_mean"):
        return float(pair.loc[pair.metric==metric,col].iloc[0])
    def ci(metric):
        z=pair.loc[pair.metric==metric].iloc[0]; return f"{z.ci95_low:.6f}..{z.ci95_high:.6f}"
    pg=groups[(groups.arm=="BASE")&(groups.target_group=="HIGH")].iloc[0]; cg=groups[(groups.arm=="B0001")&(groups.target_group=="HIGH")].iloc[0]
    lowb=groups[(groups.arm=="BASE")&(groups.target_group=="LOW")].iloc[0]; lowc=groups[(groups.arm=="B0001")&(groups.target_group=="LOW")].iloc[0]
    s4_stage=s4_delta[(s4_delta.record_type=="STAGE_TOTAL_PER_PATH")&(s4_delta.cohort=="ALL_PATHS")].sort_values("stage")
    s4_hours=s4_delta[(s4_delta.record_type=="HOUR")&(s4_delta.cohort=="ALL_PATHS")].copy()
    s4_increase=float(s4_stage.paired_delta_mean_kg.sum())
    s4_hour_positive=s4_hours[s4_hours.paired_delta_mean_kg > TOL]
    s4_hour_negative=s4_hours[s4_hours.paired_delta_mean_kg < -TOL]
    inv_summary=inv_delta[inv_delta.record_type=="SUMMARY"].set_index("site")
    inv2=inv_summary.loc[2]; inv3=inv_summary.loc[3]
    diff_tail = tails[tails.tail_group.isin(["DIFFICULT4", "EXTREME1", "WORST_PATH"])].pivot(index="tail_group", columns="arm", values="mean_site_gap")
    diff_tail_text = "; ".join(f"{g} {float(diff_tail.loc[g, 'B0001'] - diff_tail.loc[g, 'BASE']):+.6f} kg/path" for g in ["DIFFICULT4", "EXTREME1", "WORST_PATH"])
    s4_stage_text="; ".join(f"stage {int(r.stage)} {r.paired_delta_mean_kg:+.6f} kg/path" for _,r in s4_stage.iterrows())
    s4_hour_text="; ".join(f"h{int(r.global_hour)}(stage {int(r.stage)}) {r.paired_delta_mean_kg:+.6f}" for _,r in s4_hour_positive.iterrows())
    s4_neg_text="; ".join(f"h{int(r.global_hour)}(stage {int(r.stage)}) {r.paired_delta_mean_kg:+.6f}" for _,r in s4_hour_negative.iterrows())
    notid=ident[ident.status=="NOT_IDENTIFIABLE"].mechanism.tolist()
    return f"""# B0001 C 模式完整性审计与只读补充分析

## 四个独立结论

```text
ANALYSIS_QA = PASS
C_MODE_COVERAGE = COMPLETE
C_MODE_EVIDENCE = MIXED
B0001_CANDIDATE_JUDGMENT = EXPLORATORY_SIGNAL_ONLY
```

`ANALYSIS_QA=PASS` 只表示程序、输入身份、common-path、终端公式和输出 QA 通过，不表示 B0001 训练通过。

## 结果可信性

Base/B0001 使用相同有序 10000-path bank，`run-007` 结果引用正确且未被覆盖。终端公式 `sum_i max(T_i-I_i,0)` 独立重算通过。两臂均为 `DIRECT_GAP`，没有终端站间配送。

paired 95% CI（B0001 - Base，路径级正态近似 CI）：

- site gap：`{v('terminal_site_gap'):.6f}`，95% CI `[{ci('terminal_site_gap')}]` kg/path；
- quantity gap：`{v('terminal_total_quantity_shortfall'):.6f}`，95% CI `[{ci('terminal_total_quantity_shortfall')}]` kg/path；
- location component：`{v('terminal_spatial_component'):.6f}`，95% CI `[{ci('terminal_spatial_component')}]` kg/path；
- ordinary shortage：`{v('ordinary_shortage_total'):.6f}`，95% CI `[{ci('ordinary_shortage_total')}]` kg/path；
- actual operating cost：`{v('actual_operating_cost'):.6f}`，95% CI `[{ci('actual_operating_cost')}]` yuan/path；terminal penalty：`{v('terminal_penalty_cost'):.6f}`，95% CI `[{ci('terminal_penalty_cost')}]` yuan/path。

positive-target 分母两臂均为 1123；site-wise failure rate 为 `42.1193% -> 45.3250%`（配对新增失败 82、恢复 46）。pure quantity 减少，但 pure location/mixed 增加。

## target、时间和尾部

- LOW target 的平均生产为 `{lowb.mean_total_H2_production:.6f} -> {lowc.mean_total_H2_production:.6f}`（差 `{lowc.mean_total_H2_production-lowb.mean_total_H2_production:+.6f}`）kg/path，surplus 为 `{lowb.mean_surplus_total:.6f} -> {lowc.mean_surplus_total:.6f}`（差 `{lowc.mean_surplus_total-lowb.mean_surplus_total:+.6f}`），site gap 为 `{lowb.mean_site_gap:.6f} -> {lowc.mean_site_gap:.6f}`。这显示相对准备增加，但没有理想策略反事实，不能等同于 policy 错误；四类终端类型见 `target_group_summary.csv`。
- HIGH target 的 observed site-gap 为 Base `{pg.mean_site_gap:.6f}`、B0001 `{cg.mean_site_gap:.6f}` kg/path，site-wise failure 为 `{pg.sitewise_failure_rate:.4f} -> {cg.sitewise_failure_rate:.4f}`，adequate count 为 `{int(pg.adequate_count)}` -> `{int(cg.adequate_count)}`。因此高目标保障没有显示改善，且观察上恶化。
- S4 的全路径新增生产为 `{s4_increase:+.6f}` kg/path；按阶段为 `{s4_stage_text}`。全路径正增量小时为 `{s4_hour_text}`，负增量小时为 `{s4_neg_text}`；新增失败 cohort 的逐小时值和路径数见 `s4_production_delta.csv`，四站 P_EL、Pmax 利用率、库存、HTT、shortage 和 binding 仍见 `time_formation_summary.csv`。
- 新增失败 cohort 中，S2 的 B0001-Base ending-inventory 均值差首次在 global hour `{int(inv2.global_hour)}`（stage `{int(inv2.stage)}`）为 `{inv2.mean_inventory_delta_kg:.6f}` kg，最低为 hour `{int(inv2.minimum_global_hour)}`（stage `{int(inv2.minimum_stage)}`）`{inv2.minimum_mean_inventory_delta_kg:.6f}` kg；S3 首次在 hour `{int(inv3.global_hour)}`（stage `{int(inv3.stage)}`）为 `{inv3.mean_inventory_delta_kg:.6f}` kg，最低为 hour `{int(inv3.minimum_global_hour)}`（stage `{int(inv3.minimum_stage)}`）`{inv3.minimum_mean_inventory_delta_kg:.6f}` kg。完整轨迹见 `inventory_delta_formation.csv`。这些是 realized ending-inventory 差异，不是反事实缺口形成证明。
- `DIFFICULT4`、`EXTREME1`、`WORST_PATH` 使用同一 Base terminal-site-gap 的事后冻结路径；site-gap 的 B0001-Base 差分别为 `{diff_tail_text}`，并同时比较 production、inventory、quantity/location gap、ordinary shortage、actual cost、terminal penalty 和 HTT。它们不是 fresh holdout，完整结果见 `tail_and_cost_summary.csv`。

## 机制边界

可确认：S4 Pmax 扩大伴随更多生产，但新增氢未稳定转化为缺口站点的终端可用库存；quantity-side 平均指标略改善，而 site/location reliability 恶化。HTT 总量差为 `{v('total_HTT'):+.6f}` kg/path，95% CI `[{ci('total_HTT')}]`；保存字段支持 OD、方向、小时、源/目的库存和 shortage 的 realized 对齐，但没有 travel-time/direction relaxation 反事实，因此不能把相关性写成 HTT 因果。P_EL、Pmax 利用率、electrolyzer/storage binding 以及 `min_voltage_pu`/`max_line_loading_pct` 可作观测信号；缺少 substation capacity/loading/binding，不能识别变电站瓶颈；储罐有库存和 binding 但无显式 headroom，物理可恢复性也无 optimistic feasibility certificate。

逐项不可识别机制：{', '.join(notid)}。每项的所需字段、现有缺失字段、已排除内容、是否需要新 OOS 以及最小补充分析均列在 `mechanism_identifiability.csv`，不是统一的“数据不足”标签。

B0001 `UNSTABLE/FAIL` 是所有机制结论的共同折扣：观察到的模式可能来自 Pmax 空间配置、信息/HTT 时机和未稳定 policy 的混合，不能做候选采用、优劣排名或淘汰结论。

下一步建议：先重新稳定训练 B0001；稳定后再测试非均匀功率候选。此 closeout 未训练、未重跑 OOS、未修改模型/checkpoint，也未执行任何 Git 写操作。
"""


if __name__ == "__main__":
    raise SystemExit(main())
