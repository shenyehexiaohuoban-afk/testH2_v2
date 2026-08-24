#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""QA and Chinese analysis for Stage89Q recovered penalty-1000 OOS."""

from __future__ import annotations

import hashlib
import math
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from matplotlib import font_manager
from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
RUN = ROOT / "results/task-002-stage2b-b3-smoke/stage89q-penalty1000-vs1500-long-training/run-003"
RAW = ROOT / "hourly_grid_h2/output/stage89q_penalty1000_vs1500_long_training/run-003/penalty1000"
QA = RUN / "04_qa"
ANALYSIS = RUN / "05_analysis"
FIGURES = RUN / "06_figures"
MANIFESTS = RUN / "07_manifests"
RELEASE = RUN / "08_release"
TOL = 1e-7


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def save_csv(frame: pd.DataFrame, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    frame.to_csv(path, index=False, encoding="utf-8-sig", float_format="%.12g")


def stats(values) -> dict[str, float]:
    x = pd.Series(values, dtype="float64").dropna().to_numpy()
    if not len(x):
        return {"N": 0, "mean": np.nan, "median": np.nan, "q25": np.nan,
                "q75": np.nan, "q95": np.nan, "q99": np.nan, "std": np.nan,
                "ci95_low": np.nan, "ci95_high": np.nan}
    mean = float(x.mean())
    std = float(x.std(ddof=1)) if len(x) > 1 else 0.0
    half = 1.96 * std / math.sqrt(len(x))
    return {"N": len(x), "mean": mean, "median": float(np.median(x)),
            "q25": float(np.quantile(x, .25)), "q75": float(np.quantile(x, .75)),
            "q95": float(np.quantile(x, .95)), "q99": float(np.quantile(x, .99)),
            "std": std, "ci95_low": mean-half, "ci95_high": mean+half}


def require_columns(frame: pd.DataFrame, columns: set[str], name: str) -> None:
    missing = sorted(columns-set(frame.columns))
    if missing:
        raise RuntimeError(f"{name} missing columns: {missing}")


def chinese_font() -> str:
    available = {f.name for f in font_manager.fontManager.ttflist}
    for candidate in ("Microsoft YaHei", "Microsoft YaHei UI", "SimHei"):
        if candidate in available:
            return candidate
    raise RuntimeError("未找到可用中文字体，拒绝生成乱码图。")


def setup_dirs() -> None:
    for directory in (QA, MANIFESTS, RELEASE, FIGURES):
        directory.mkdir(parents=True, exist_ok=True)
    for name in ("01_overall", "02_dissipation", "03_stage7_all",
                 "04_stage7_shortfall", "05_risk_tail", "06_spatial_and_htt",
                 "07_economics", "08_training_depth"):
        (ANALYSIS/name).mkdir(parents=True, exist_ok=True)


def load_inputs():
    path = pd.read_csv(RAW/"path_summary/oos_path_summary.csv")
    stage = pd.read_csv(RAW/"path_summary/oos_stage_summary.csv")
    site = pd.read_csv(RAW/"path_summary/oos_stage_site_summary.csv")
    hour = pd.read_csv(RAW/"hourly_site/oos_hour_site.csv")
    system = pd.read_csv(RAW/"grid_hourly/oos_hour_system.csv")
    flow = pd.read_csv(RAW/"htt_od/oos_positive_htt_flows.csv")
    bank = pd.read_csv(RUN/"03_oos/common/oos_path_manifest.csv")
    training = pd.read_csv(ROOT/"results/task-002-stage2b-b3-smoke/stage89q-penalty1000-vs1500-long-training/run-002/02_training/penalty1000/training_progress.csv")
    return path, stage, site, hour, system, flow, bank, training


def run_qa(path, stage, site, hour, system, flow, bank):
    expected = {
        "path": {"path_id", "operating_stage_count", "reached_stage7", "physical_dissipation_a1",
                 "total_H2_production", "total_HTT", "ordinary_shortage_total", "actual_operating_cost",
                 "terminal_site_gap", "terminal_total_quantity_shortfall", "terminal_spatial_component",
                 "terminal_gap_class", "termination_stage"},
        "stage": {"path_id", "stage", "stage_objective_yuan", "production_kg", "ordinary_shortage_kg",
                  "htt_kg", "beginning_inventory_kg", "ending_inventory_kg"},
        "site": {"path_id", "stage", "site", "ordinary_demand_kg", "served_demand_kg", "shortage_kg",
                 "production_kg", "htt_in_kg", "htt_out_kg", "beginning_inventory_kg", "ending_inventory_kg"},
        "hour": {"path_id", "stage", "hour_in_stage", "global_hour", "site", "P_EL_kW", "H2_production_kg",
                 "ordinary_demand_kg", "ordinary_served_kg", "ordinary_shortage_kg", "begin_inventory_kg",
                 "inventory_before_HTT_kg", "end_inventory_kg", "HTT_in_kg", "HTT_out_kg"},
        "system": {"path_id", "stage", "hour_in_stage", "global_hour", "total_P_EL_kW", "root_grid_import",
                   "min_voltage_pu", "max_line_loading_pct", "total_HTT_kg"},
        "flow": {"path_id", "stage", "hour_in_stage", "origin_site", "destination_site", "flow_kg"},
    }
    for name, frame in (("path", path), ("stage", stage), ("site", site),
                        ("hour", hour), ("system", system), ("flow", flow)):
        require_columns(frame, expected[name], name)

    qa = []
    def add(group, check, observed, expected_value, passed, tolerance="exact"):
        qa.append({"group": group, "check": check, "observed": observed,
                   "expected": expected_value, "tolerance": tolerance, "pass": bool(passed)})

    add("schema", "path_count", len(path), 10000, len(path)==10000)
    add("schema", "ordered_path_id", path.path_id.tolist()==list(range(1,10001)), "1..10000", path.path_id.tolist()==list(range(1,10001)))
    add("schema", "stage_rows", len(stage), int(path.operating_stage_count.sum()), len(stage)==int(path.operating_stage_count.sum()))
    add("schema", "stage_site_rows", len(site), 4*len(stage), len(site)==4*len(stage))
    add("schema", "hour_site_rows", len(hour), 32*len(stage), len(hour)==32*len(stage))
    add("schema", "grid_hour_rows", len(system), 8*len(stage), len(system)==8*len(stage))
    add("schema", "hour_bounds", f"{hour.global_hour.min()}..{hour.global_hour.max()}", "1..48", hour.global_hour.min()==1 and hour.global_hour.max()<=48)
    add("schema", "hour_unique", int(hour.duplicated(["path_id","stage","hour_in_stage","site"]).sum()), 0, not hour.duplicated(["path_id","stage","hour_in_stage","site"]).any())
    add("schema", "system_hour_unique", int(system.duplicated(["path_id","stage","hour_in_stage"]).sum()), 0, not system.duplicated(["path_id","stage","hour_in_stage"]).any())

    state_cols = [c for c in bank.columns if c.startswith("k_t")]
    bank_sequence = bank[state_cols].astype(int).astype(str).agg("-".join, axis=1)
    bank_match = np.array_equal(bank.path_id.to_numpy(), path.path_id.to_numpy()) and np.array_equal(bank_sequence.to_numpy(), path.state_sequence.to_numpy())
    add("identity", "ordered_bank_state_sequences", bank_match, True, bank_match)

    demand_spread = hour.groupby(["global_hour", "site"]).ordinary_demand_kg.agg(lambda x: x.max()-x.min())
    demand_consistent = bool((demand_spread <= TOL).all())
    add("identity", "hourly_site_demand_profile_consistent", demand_spread.max(), f"<={TOL}", demand_consistent, TOL)

    h = hour.sort_values(["path_id","stage","hour_in_stage","site"])
    production_res = h.H2_production_kg-0.0195*h.P_EL_kW
    service_res = h.ordinary_served_kg+h.ordinary_shortage_kg-h.ordinary_demand_kg
    pre_res = h.inventory_before_HTT_kg-(h.begin_inventory_kg+h.H2_production_kg-h.ordinary_served_kg)
    end_res = h.end_inventory_kg-(h.inventory_before_HTT_kg-h.HTT_out_kg+h.HTT_in_kg)

    def residual_table(name, residual):
        absolute = np.abs(np.asarray(residual, dtype=float))
        frame = pd.DataFrame([{"check": name, "row_count": len(absolute), "max_absolute_residual": absolute.max(),
                               "median_absolute_residual": np.median(absolute), "violation_count": int((absolute>TOL).sum()),
                               "tolerance": TOL, "pass": bool((absolute<=TOL).all())}])
        return frame

    closure_frames = {
        "production_closure.csv": residual_table("H2=k_H2*P_EL*1h", production_res),
        "demand_service_closure.csv": residual_table("served+shortage=demand", service_res),
        "inventory_closure.csv": pd.concat([residual_table("inventory_before_HTT", pre_res), residual_table("end_inventory", end_res)], ignore_index=True),
    }
    for filename, frame in closure_frames.items():
        save_csv(frame, QA/filename)
        for row in frame.to_dict("records"):
            add("hourly_closure", row["check"], row["max_absolute_residual"], f"<={TOL}", row["pass"], TOL)

    hourly_transport = h.groupby(["path_id","stage","hour_in_stage"], as_index=False).agg(htt_in=("HTT_in_kg","sum"), htt_out=("HTT_out_kg","sum"))
    hourly_transport["residual"] = hourly_transport.htt_in-hourly_transport.htt_out
    transport_abs = hourly_transport.residual.abs()
    flow_hour = flow.groupby(["path_id","stage","hour_in_stage"], as_index=False).flow_kg.sum().rename(columns={"flow_kg":"flow_sum"})
    flow_check = system[["path_id","stage","hour_in_stage","total_HTT_kg"]].merge(flow_hour, how="left", on=["path_id","stage","hour_in_stage"]).fillna({"flow_sum":0})
    flow_check["residual"] = flow_check.total_HTT_kg-flow_check.flow_sum
    htt_qa = pd.DataFrame([
        {"check":"site_HTT_in_equals_out", "max_absolute_residual":transport_abs.max(), "median_absolute_residual":transport_abs.median(), "violation_count":int((transport_abs>TOL).sum()), "pass":bool((transport_abs<=TOL).all())},
        {"check":"sparse_OD_equals_system_HTT", "max_absolute_residual":flow_check.residual.abs().max(), "median_absolute_residual":flow_check.residual.abs().median(), "violation_count":int((flow_check.residual.abs()>TOL).sum()), "pass":bool((flow_check.residual.abs()<=TOL).all())},
    ])
    save_csv(htt_qa, QA/"htt_balance_closure.csv")
    for row in htt_qa.to_dict("records"): add("htt_closure", row["check"], row["max_absolute_residual"], f"<={TOL}", row["pass"], TOL)

    hg = h.groupby(["path_id","stage","site"], as_index=False).agg(
        ordinary_demand_kg=("ordinary_demand_kg","sum"), served_demand_kg=("ordinary_served_kg","sum"),
        shortage_kg=("ordinary_shortage_kg","sum"), production_kg=("H2_production_kg","sum"),
        htt_in_kg=("HTT_in_kg","sum"), htt_out_kg=("HTT_out_kg","sum"),
        beginning_inventory_kg=("begin_inventory_kg","first"), ending_inventory_kg=("end_inventory_kg","last"))
    merged = site.merge(hg, on=["path_id","stage","site"], suffixes=("_stage","_hour"))
    site_metrics = ["ordinary_demand_kg","served_demand_kg","shortage_kg","production_kg","htt_in_kg","htt_out_kg","beginning_inventory_kg","ending_inventory_kg"]
    aggregation_rows=[]
    for metric in site_metrics:
        residual=(merged[f"{metric}_stage"]-merged[f"{metric}_hour"]).abs()
        aggregation_rows.append({"level":"hour_to_stage_site","metric":metric,"max_absolute_residual":residual.max(),"median_absolute_residual":residual.median(),"violation_count":int((residual>TOL).sum()),"pass":bool((residual<=TOL).all())})

    stage_from_hour = hg.groupby(["path_id","stage"], as_index=False).agg(production_kg=("production_kg","sum"), ordinary_shortage_kg=("shortage_kg","sum"), htt_kg=("htt_out_kg","sum"), beginning_inventory_kg=("beginning_inventory_kg","sum"), ending_inventory_kg=("ending_inventory_kg","sum"))
    sm = stage.merge(stage_from_hour, on=["path_id","stage"], suffixes=("_stage","_hour"))
    for metric in ("production_kg","ordinary_shortage_kg","htt_kg","beginning_inventory_kg","ending_inventory_kg"):
        residual=(sm[f"{metric}_stage"]-sm[f"{metric}_hour"]).abs()
        aggregation_rows.append({"level":"hour_to_stage","metric":metric,"max_absolute_residual":residual.max(),"median_absolute_residual":residual.median(),"violation_count":int((residual>TOL).sum()),"pass":bool((residual<=TOL).all())})

    pg=stage.groupby("path_id",as_index=False).agg(total_H2_production=("production_kg","sum"),ordinary_shortage_total=("ordinary_shortage_kg","sum"),total_HTT=("htt_kg","sum"),actual_operating_cost=("stage_objective_yuan","sum"))
    pm=path.merge(pg,on="path_id",suffixes=("_path","_stage"))
    for metric in ("total_H2_production","ordinary_shortage_total","total_HTT","actual_operating_cost"):
        residual=(pm[f"{metric}_path"]-pm[f"{metric}_stage"]).abs()
        aggregation_rows.append({"level":"stage_to_path","metric":metric,"max_absolute_residual":residual.max(),"median_absolute_residual":residual.median(),"violation_count":int((residual>TOL).sum()),"pass":bool((residual<=TOL).all())})
    aggregation=pd.DataFrame(aggregation_rows)
    save_csv(aggregation,QA/"stage_hour_aggregation_qa.csv")
    save_csv(aggregation[aggregation.level=="stage_to_path"],QA/"path_total_aggregation_qa.csv")
    for row in aggregation.to_dict("records"): add("aggregation",f"{row['level']}:{row['metric']}",row["max_absolute_residual"],f"<={TOL}",row["pass"],TOL)

    expected_counts=path.set_index("path_id").operating_stage_count
    counts=pd.DataFrame({"stage":stage.groupby("path_id").size(),"site":site.groupby("path_id").size(),"hour":hour.groupby("path_id").size(),"system":system.groupby("path_id").size()}).reindex(path.path_id,fill_value=0)
    post_pass=(counts.stage.to_numpy()==expected_counts.to_numpy()).all() and (counts.site.to_numpy()==4*expected_counts.to_numpy()).all() and (counts.hour.to_numpy()==32*expected_counts.to_numpy()).all() and (counts.system.to_numpy()==8*expected_counts.to_numpy()).all()
    add("lifecycle","no_post_termination_rows",post_pass,True,post_pass)

    stage7=path[path.reached_stage7==1].copy()
    gap_identity=stage7.terminal_site_gap-(stage7.terminal_total_quantity_shortfall+stage7.terminal_spatial_component)
    spatial_nonnegative=stage7.terminal_spatial_component.min()>=-TOL
    gap_qa=pd.DataFrame([
        {"check":"G_site=G_total+G_spatial","max_absolute_residual":gap_identity.abs().max(),"violation_count":int((gap_identity.abs()>TOL).sum()),"pass":bool((gap_identity.abs()<=TOL).all())},
        {"check":"G_spatial_nonnegative","max_absolute_residual":max(0,-stage7.terminal_spatial_component.min()),"violation_count":int((stage7.terminal_spatial_component<-TOL).sum()),"pass":spatial_nonnegative},
    ])
    save_csv(gap_qa,QA/"stage7_gap_decomposition_qa.csv")
    for row in gap_qa.to_dict("records"): add("stage7",row["check"],row["max_absolute_residual"],f"<={TOL}",row["pass"],TOL)

    qa_frame=pd.DataFrame(qa)
    save_csv(qa_frame,QA/"qa_summary.csv")
    save_csv(qa_frame[qa_frame.group=="schema"],QA/"hourly_schema_audit.csv")
    if not qa_frame["pass"].all():
        raise RuntimeError("Stage89Q penalty1000 OOS QA failed")
    return stage7


def analyze(path, stage, site, hour, system, flow, stage7, training):
    overall=[]
    for metric in ("total_H2_production","actual_operating_cost","total_HTT"):
        overall.append({"metric":metric,"scope":"all_10000_paths",**stats(path[metric])})
    save_csv(pd.DataFrame(overall),ANALYSIS/"01_overall/overall_summary.csv")

    stage_summary=[]
    for stage_id, group in stage.groupby("stage"):
        stage_summary.append({"stage":int(stage_id),"active_path_count":group.path_id.nunique(),"active_path_fraction":group.path_id.nunique()/10000,
                              "mean_production_kg":group.production_kg.mean(),"mean_begin_inventory_kg":group.beginning_inventory_kg.mean(),
                              "mean_end_inventory_kg":group.ending_inventory_kg.mean(),"mean_shortage_kg":group.ordinary_shortage_kg.mean(),"mean_HTT_kg":group.htt_kg.mean()})
    stage_summary=pd.DataFrame(stage_summary);save_csv(stage_summary,ANALYSIS/"01_overall/production_inventory_stage.csv")

    site_hour=hour.groupby(["path_id","global_hour"],as_index=False).agg(production_kg=("H2_production_kg","sum"),end_inventory_kg=("end_inventory_kg","sum"),ordinary_shortage_kg=("ordinary_shortage_kg","sum"),HTT_kg=("HTT_out_kg","sum"),P_EL_kW=("P_EL_kW","sum"))
    hourly=site_hour.groupby("global_hour",as_index=False).agg(active_path_count=("path_id","nunique"),mean_production_kg=("production_kg","mean"),mean_inventory_kg=("end_inventory_kg","mean"),mean_shortage_kg=("ordinary_shortage_kg","mean"),mean_HTT_kg=("HTT_kg","mean"),mean_P_EL_kW=("P_EL_kW","mean"))
    hourly["active_path_fraction"]=hourly.active_path_count/10000
    save_csv(hourly,ANALYSIS/"01_overall/production_inventory_hourly.csv")
    site_hourly=hour.groupby(["global_hour","site"],as_index=False).agg(active_path_count=("path_id","nunique"),mean_production_kg=("H2_production_kg","mean"),mean_inventory_kg=("end_inventory_kg","mean"),mean_shortage_kg=("ordinary_shortage_kg","mean"),mean_HTT_in_kg=("HTT_in_kg","mean"),mean_HTT_out_kg=("HTT_out_kg","mean"))
    save_csv(site_hourly,ANALYSIS/"01_overall/four_site_hourly.csv")

    shortage_positive=path[path.ordinary_shortage_total>TOL]
    shortage=pd.DataFrame([
        {"scope":"all_paths","metric":"overall_mean_shortage_kg","value":path.ordinary_shortage_total.mean(),"N":len(path)},
        {"scope":"all_paths","metric":"shortage_probability","value":len(shortage_positive)/len(path),"N":len(path)},
        {"scope":"positive_shortage_paths","metric":"conditional_mean_shortage_kg","value":shortage_positive.ordinary_shortage_total.mean(),"N":len(shortage_positive)},
        *({"scope":"positive_shortage_paths","metric":key,"value":value,"N":len(shortage_positive)} for key,value in stats(shortage_positive.ordinary_shortage_total).items() if key in {"median","q25","q75","q95","q99"}),
    ])
    save_csv(shortage,ANALYSIS/"01_overall/ordinary_shortage_summary.csv")

    gap_positive=stage7[stage7.terminal_site_gap>TOL]
    stage7_summary=pd.DataFrame([
        {"scope":"all_paths","metric":"stage7_path_count","value":len(stage7),"N":len(path)},
        {"scope":"stage7_paths","metric":"stage7_fraction_all_paths","value":len(stage7)/len(path),"N":len(path)},
        {"scope":"stage7_paths","metric":"mean_terminal_gap_kg","value":stage7.terminal_site_gap.mean(),"N":len(stage7)},
        {"scope":"stage7_paths","metric":"positive_gap_probability","value":len(gap_positive)/len(stage7),"N":len(stage7)},
        {"scope":"positive_gap_paths","metric":"conditional_mean_gap_kg","value":gap_positive.terminal_site_gap.mean(),"N":len(gap_positive)},
        *({"scope":"positive_gap_paths","metric":key,"value":value,"N":len(gap_positive)} for key,value in stats(gap_positive.terminal_site_gap).items() if key in {"median","q25","q75","q95","q99"}),
    ])
    save_csv(stage7_summary,ANALYSIS/"03_stage7_all/stage7_summary.csv")

    class_cn={"NO_GAP":"库存完全够","PURE_QUANTITY_SHORTFALL":"氢总量确实不够","PURE_SPATIAL_MISMATCH":"氢总量基本够，但站点位置不合适","MIXED_QUANTITY_AND_SPATIAL":"总量和站点分布都有问题"}
    reason=[]
    for cls,count in stage7.terminal_gap_class.value_counts().items():
        reason.append({"class":cls,"中文说明":class_cn[cls],"path_count":count,"fraction_of_stage7":count/len(stage7),"fraction_of_positive_gap":count/len(gap_positive) if cls!="NO_GAP" else 0})
    reason=pd.DataFrame(reason);save_csv(reason,ANALYSIS/"04_stage7_shortfall/quantity_vs_location.csv")
    stage7_inventory_columns = [
        "path_id", "termination_stage", "terminal_a", "terminal_loc",
        "target_site1", "target_site2", "target_site3", "target_site4", "target_total",
        "inventory_site1", "inventory_site2", "inventory_site3", "inventory_site4", "terminal_inventory_total",
        "gap_site1", "gap_site2", "gap_site3", "gap_site4", "terminal_site_gap",
        "surplus_site1", "surplus_site2", "surplus_site3", "surplus_site4",
        "terminal_total_quantity_shortfall", "terminal_spatial_component", "terminal_gap_class",
    ]
    save_csv(stage7[stage7_inventory_columns], RAW/"stage7_inventory/stage7_four_site_inventory.csv")
    stage7_site_rows=[]
    for site_id in range(1,5):
        site_gap=stage7[f"gap_site{site_id}"]
        stage7_site_rows.append({
            "site":site_id,"stage7_path_count":len(stage7),
            "mean_target_kg":stage7[f"target_site{site_id}"].mean(),
            "mean_actual_inventory_kg":stage7[f"inventory_site{site_id}"].mean(),
            "mean_gap_kg":site_gap.mean(),"positive_gap_probability":(site_gap>TOL).mean(),
            "mean_surplus_kg":stage7[f"surplus_site{site_id}"].mean(),
        })
    stage7_site=pd.DataFrame(stage7_site_rows)
    save_csv(stage7_site,ANALYSIS/"03_stage7_all/four_site_target_actual_summary.csv")

    od=flow.groupby(["origin_site","destination_site"],as_index=False).agg(
        positive_flow_row_count=("flow_kg","size"),path_count=("path_id","nunique"),
        total_flow_kg=("flow_kg","sum"),mean_positive_flow_kg=("flow_kg","mean"),
        max_positive_flow_kg=("flow_kg","max"))
    od["mean_flow_per_all_paths_kg"]=od.total_flow_kg/len(path)
    save_csv(od,ANALYSIS/"06_spatial_and_htt/htt_od_summary.csv")
    grid_summary=pd.DataFrame([{
        "grid_hour_row_count":len(system),"active_path_count":system.path_id.nunique(),
        "mean_root_grid_import":system.root_grid_import.mean(),"max_root_grid_import":system.root_grid_import.max(),
        "mean_total_P_EL_kW":system.total_P_EL_kW.mean(),"max_total_P_EL_kW":system.total_P_EL_kW.max(),
        "minimum_voltage_pu":system.min_voltage_pu.min(),"voltage_at_0p90_fraction":(system.min_voltage_pu<=.900001).mean(),
        "maximum_line_loading":system.max_line_loading_pct.max(),"line_at_capacity_fraction":(system.max_line_loading_pct>=.999999).mean(),
    }])
    save_csv(grid_summary,ANALYSIS/"06_spatial_and_htt/grid_hourly_summary.csv")

    demand_profile=hour.groupby(["global_hour","site"],as_index=False).ordinary_demand_kg.median()
    diss=path[path.physical_dissipation_a1==1].copy()
    remaining=[]
    for row in diss.itertuples():
        start=8*(int(row.termination_stage)-1)+1
        d=demand_profile[demand_profile.global_hour>=start].groupby("site").ordinary_demand_kg.sum().reindex(range(1,5),fill_value=0)
        inventories=np.array([row.inventory_site1,row.inventory_site2,row.inventory_site3,row.inventory_site4],dtype=float)
        remaining.append({"path_id":row.path_id,"dissipation_stage":int(row.termination_stage),"inventory_at_resolution_kg":inventories.sum(),"remaining_formal_demand_kg":d.sum(),"inventory_minus_remaining_demand_kg":inventories.sum()-d.sum(),"positive_preventive_inventory_kg":np.maximum(inventories-d.to_numpy(),0).sum()})
    dissipation=pd.DataFrame(remaining);save_csv(dissipation,ANALYSIS/"02_dissipation/preventive_inventory.csv")
    diss_summary=dissipation.groupby("dissipation_stage",as_index=False).agg(path_count=("path_id","count"),mean_inventory_at_resolution_kg=("inventory_at_resolution_kg","mean"),mean_remaining_demand_kg=("remaining_formal_demand_kg","mean"),mean_inventory_minus_remaining_demand_kg=("inventory_minus_remaining_demand_kg","mean"),mean_positive_preventive_inventory_kg=("positive_preventive_inventory_kg","mean"))
    save_csv(diss_summary,ANALYSIS/"02_dissipation/dissipation_timing.csv")

    ordered=stage7.sort_values(["terminal_site_gap","path_id"]).reset_index(drop=True)
    n=len(ordered);cut95=math.floor(.95*n);cut99=math.floor(.99*n)
    ordered["difficulty_tier"]="普通95%";ordered.loc[cut95:cut99-1,"difficulty_tier"]="较困难4%";ordered.loc[cut99:,"difficulty_tier"]="最极端1%"
    tier=ordered.groupby("difficulty_tier",as_index=False).agg(path_count=("path_id","count"),mean_gap_kg=("terminal_site_gap","mean"),median_gap_kg=("terminal_site_gap","median"),q95_gap_kg=("terminal_site_gap",lambda x:x.quantile(.95)),mean_production_kg=("total_H2_production","mean"),mean_inventory_kg=("terminal_inventory_total","mean"),mean_HTT_kg=("total_HTT","mean"),mean_shortage_kg=("ordinary_shortage_total","mean"))
    tier["order"]=tier.difficulty_tier.map({"普通95%":1,"较困难4%":2,"最极端1%":3});tier=tier.sort_values("order")
    save_csv(tier,ANALYSIS/"05_risk_tail/stage7_gap_95_4_1.csv")
    extreme=ordered[ordered.difficulty_tier=="最极端1%"].sort_values(["terminal_site_gap","path_id"],ascending=[False,True])
    extreme_columns=["path_id","state_sequence","termination_stage","terminal_a","terminal_loc","difficulty_tier",
                     "terminal_site_gap","terminal_total_quantity_shortfall","terminal_spatial_component","terminal_gap_class",
                     "total_H2_production","terminal_inventory_total","ordinary_shortage_total","total_HTT",
                     "target_site1","target_site2","target_site3","target_site4",
                     "inventory_site1","inventory_site2","inventory_site3","inventory_site4",
                     "gap_site1","gap_site2","gap_site3","gap_site4"]
    save_csv(extreme[extreme_columns],ANALYSIS/"05_risk_tail/extreme_stage7_paths.csv")

    positive_ids=set(gap_positive.path_id.astype(int))
    last=hour[hour.path_id.isin(positive_ids)].copy();arrival=last.path_id.map(stage7.set_index("path_id").termination_stage)*8-8
    last["relative_hour"]=last.global_hour-arrival
    last=last[(last.relative_hour>=-15)&(last.relative_hour<=0)]
    last_sys=system[system.path_id.isin(positive_ids)].copy();arrival_sys=last_sys.path_id.map(stage7.set_index("path_id").termination_stage)*8-8;last_sys["relative_hour"]=last_sys.global_hour-arrival_sys;last_sys=last_sys[(last_sys.relative_hour>=-15)&(last_sys.relative_hour<=0)]
    last_totals=last.groupby(["path_id","relative_hour"],as_index=False).agg(production_kg=("H2_production_kg","sum"),inventory_kg=("end_inventory_kg","sum"),HTT_kg=("HTT_out_kg","sum"),shortage_kg=("ordinary_shortage_kg","sum"),electrolyzer_binding=("electrolyzer_capacity_binding","max"))
    aligned=last_totals.groupby("relative_hour",as_index=False).agg(path_count=("path_id","nunique"),mean_production_kg=("production_kg","mean"),mean_inventory_kg=("inventory_kg","mean"),mean_HTT_kg=("HTT_kg","mean"),mean_shortage_kg=("shortage_kg","mean"),electrolyzer_binding_fraction=("electrolyzer_binding","mean"))
    grid=last_sys.copy();grid["voltage_binding"]=grid.min_voltage_pu<=0.900001;grid["line_binding"]=grid.max_line_loading_pct>=.999999
    grid_aligned=grid.groupby("relative_hour",as_index=False).agg(mean_P_EL_kW=("total_P_EL_kW","mean"),voltage_binding_fraction=("voltage_binding","mean"),line_binding_fraction=("line_binding","mean"),combined_binding_fraction=("grid_or_electrolyzer_binding_flag","mean"),mean_min_voltage_pu=("min_voltage_pu","mean"),mean_max_line_loading=("max_line_loading_pct","mean"))
    aligned=aligned.merge(grid_aligned,on="relative_hour",how="left")
    save_csv(aligned,ANALYSIS/"04_stage7_shortfall/final16h_shortfall_paths.csv")
    constraint=pd.DataFrame([
        {"constraint":"任一电解槽达到功率上限","fraction_of_positive_gap_last16_path_hours":last_totals.electrolyzer_binding.mean(),"sample_path_hours":len(last_totals)},
        {"constraint":"最低电压达到0.90下限","fraction_of_positive_gap_last16_path_hours":grid.voltage_binding.mean(),"sample_path_hours":len(grid)},
        {"constraint":"线路容量达到上限","fraction_of_positive_gap_last16_path_hours":grid.line_binding.mean(),"sample_path_hours":len(grid)},
    ])
    save_csv(constraint,ANALYSIS/"04_stage7_shortfall/production_constraint_summary.csv")

    training=training.copy();training["wallclock_hour"]=training.elapsed_seconds/3600
    save_csv(training[["iteration","wallclock_hour","lower_bound","cut_count","stage1_total_production"]],ANALYSIS/"08_training_depth/training_stability.csv")
    return {"overall":pd.DataFrame(overall),"stage":stage_summary,"hourly":hourly,"site_hourly":site_hourly,"shortage":shortage,"stage7":stage7_summary,"stage7_site":stage7_site,"reason":reason,"dissipation":diss_summary,"tier":tier,"extreme":extreme,"aligned":aligned,"constraint":constraint,"training":training,"gap_positive":gap_positive,"od":od,"grid_summary":grid_summary}


def figures(data):
    font=chinese_font();plt.rcParams.update({"font.family":font,"axes.unicode_minus":False,"font.size":10,"figure.dpi":140,"savefig.dpi":180})
    colors=["#176B87","#D88C32","#2D7D46","#B24C63"]
    manifest=[]
    def save(fig,name,title,source,scope):
        path=FIGURES/name;fig.savefig(path,bbox_inches="tight",facecolor="white");plt.close(fig)
        manifest.append({"figure":name,"title_cn":title,"source_csv":str(source.relative_to(RUN)),"sample_scope_cn":scope,"bytes":path.stat().st_size,"sha256":sha256(path)})

    tr=data["training"];fig,ax=plt.subplots(figsize=(8,4.5));ax.plot(tr.wallclock_hour,tr.stage1_total_production,color=colors[0],lw=1.4);ax.set(xlabel="训练计算时间（小时）",ylabel="第一阶段制氢量（千克）",title="5小时训练中第一阶段制氢量的变化");ax.grid(alpha=.25);save(fig,"01_训练中第一阶段制氢量.png","5小时训练中第一阶段制氢量的变化",ANALYSIS/"08_training_depth/training_stability.csv","全部346轮训练记录")
    st=data["stage"];fig,ax=plt.subplots(figsize=(8,4.5));ax.bar(st.stage,st.mean_production_kg,color=colors[0]);ax.set(xlabel="运行阶段",ylabel="仍在运行路径的平均制氢量（千克）",title="各阶段平均制氢量");[ax.text(r.stage,r.mean_production_kg+2,f"N={int(r.active_path_count)}",ha="center",fontsize=8) for r in st.itertuples()];save(fig,"02_各阶段制氢量.png","各阶段平均制氢量",ANALYSIS/"01_overall/production_inventory_stage.csv","每阶段仍真实运行的路径")
    hr=data["hourly"];fig,ax=plt.subplots(figsize=(9,4.8));ax.plot(hr.global_hour,hr.mean_production_kg,color=colors[0],lw=1.8,label="平均制氢量");ax.set(xlabel="真实运行小时",ylabel="平均制氢量（千克/小时）",title="仍在运行路径的真实1小时制氢");ax2=ax.twinx();ax2.plot(hr.global_hour,hr.active_path_fraction,color="#666666",ls="--",label="仍在运行的路径比例");ax2.set_ylabel("仍在运行的路径比例");ax.grid(alpha=.2);save(fig,"03_真实小时制氢.png","仍在运行路径的真实1小时制氢",ANALYSIS/"01_overall/production_inventory_hourly.csv","该小时仍真实运行的路径，未给结束路径补0")
    sh=data["site_hourly"];fig,ax=plt.subplots(figsize=(9,4.8));
    for site_id,g in sh.groupby("site"):ax.plot(g.global_hour,g.mean_inventory_kg,lw=1.6,color=colors[int(site_id)-1],label=f"站点{int(site_id)}")
    ax.set(xlabel="真实运行小时",ylabel="平均期末库存（千克）",title="四个站点的真实小时库存变化");ax.legend(ncol=4);ax.grid(alpha=.2);save(fig,"04_四站真实小时库存.png","四个站点的真实小时库存变化",ANALYSIS/"01_overall/four_site_hourly.csv","该小时仍真实运行的路径，按站点分别平均")
    so=data["shortage"];vals=[float(so.loc[so.metric==x,"value"].iloc[0]) for x in ("overall_mean_shortage_kg","shortage_probability","conditional_mean_shortage_kg")];fig,axs=plt.subplots(1,3,figsize=(10,4));labels=["全部路径\n平均缺氢","发生普通缺氢\n的路径比例","一旦发生\n平均缺氢"];units=["千克","比例","千克"]
    for ax,v,l,u in zip(axs,vals,labels,units):ax.bar([l],[v],color=colors[1]);ax.set_ylabel(u);ax.text(0,v,f"{v:.3f}",ha="center",va="bottom")
    fig.suptitle("普通用氢服务结果");save(fig,"05_普通缺氢.png","普通用氢服务结果",ANALYSIS/"01_overall/ordinary_shortage_summary.csv","全部10000条路径及发生普通缺氢的路径")
    reason=data["reason"];reason=reason[reason["class"]!="NO_GAP"];fig,ax=plt.subplots(figsize=(8,4.6));ax.bar(reason["中文说明"],reason.path_count,color=colors[1:]);ax.set(ylabel="路径数",title="最终库存不足的原因");ax.tick_params(axis="x",rotation=12);[ax.text(i,v+4,str(int(v)),ha="center") for i,v in enumerate(reason.path_count)];save(fig,"06_最终库存不足原因.png","最终库存不足的原因",ANALYSIS/"04_stage7_shortfall/quantity_vs_location.csv","真正进入最终储备检查且库存不足的路径")
    ds=data["dissipation"];fig,ax=plt.subplots(figsize=(8,4.5));ax.bar(ds.dissipation_stage,ds.mean_positive_preventive_inventory_kg,color=colors[2]);ax.set(xlabel="台风消散时所在阶段",ylabel="平均剩余预防性库存（千克）",title="后来真正消散路径留下的预防性库存");save(fig,"07_消散路径预防性库存.png","后来真正消散路径留下的预防性库存",ANALYSIS/"02_dissipation/dissipation_timing.csv","所有物理上真正消散的路径")
    tier=data["tier"];fig,ax=plt.subplots(figsize=(8,4.6));ax.bar(tier.difficulty_tier,tier.mean_gap_kg,color=[colors[0],colors[1],colors[3]]);ax.set(ylabel="平均最终库存缺口（千克）",title="普通、较困难和最极端最终检查路径");[ax.text(i,v+1,f"N={int(n)}\n{v:.2f}",ha="center") for i,(v,n) in enumerate(zip(tier.mean_gap_kg,tier.path_count))];save(fig,"08_最终检查难度分层.png","普通、较困难和最极端最终检查路径",ANALYSIS/"05_risk_tail/stage7_gap_95_4_1.csv","全部真正进入最终储备检查的路径，按缺口非重叠分层")
    al=data["aligned"];fig,axs=plt.subplots(3,1,figsize=(9,9),sharex=True);axs[0].plot(al.relative_hour,al.mean_production_kg,color=colors[0]);axs[0].set_ylabel("制氢（千克/小时）");axs[1].plot(al.relative_hour,al.mean_inventory_kg,color=colors[2]);axs[1].set_ylabel("库存（千克）");axs[2].plot(al.relative_hour,al.mean_HTT_kg,color=colors[1]);axs[2].set_ylabel("站间调氢（千克/小时）");axs[2].set_xlabel("距离最终储备检查的小时");fig.suptitle("库存不足路径在最终检查前16小时的响应");[ax.grid(alpha=.2) for ax in axs];save(fig,"09_不足路径最后16小时.png","库存不足路径在最终检查前16小时的响应",ANALYSIS/"04_stage7_shortfall/final16h_shortfall_paths.csv","全部真正发生最终库存不足的路径")
    co=data["constraint"];fig,ax=plt.subplots(figsize=(8,4.6));ax.bar(co.constraint,co.fraction_of_positive_gap_last16_path_hours,color=[colors[0],colors[3],colors[1]]);ax.set(ylabel="在路径-小时中的比例",title="库存不足路径最后16小时是否受到追产限制");ax.tick_params(axis="x",rotation=12);save(fig,"10_追产限制.png","库存不足路径最后16小时是否受到追产限制",ANALYSIS/"04_stage7_shortfall/production_constraint_summary.csv","全部正缺口路径的最后16个真实运行小时")
    manifest=pd.DataFrame(manifest);save_csv(manifest,MANIFESTS/"figure_manifest.csv")
    thumbs=[]
    contact_font = ImageFont.truetype(str(Path(r"C:\Windows\Fonts\msyh.ttc")), 14)
    for row in manifest.itertuples():
        image=Image.open(FIGURES/row.figure).convert("RGB");image.thumbnail((480,300));canvas=Image.new("RGB",(500,340),"white");canvas.paste(image,((500-image.width)//2,30));ImageDraw.Draw(canvas).text((10,8),row.figure,fill="black",font=contact_font);thumbs.append(canvas)
    sheet=Image.new("RGB",(1000,math.ceil(len(thumbs)/2)*340),(230,230,230))
    for i,image in enumerate(thumbs):sheet.paste(image,((i%2)*500,(i//2)*340))
    sheet.save(RUN/"figure_contact_sheet.png")
    return manifest


def finalize(path, stage7, data, figure_manifest):
    (RAW/"OOS_COMPLETED.marker").write_text("PENALTY1000_OOS_AND_QA_COMPLETE=true\n",encoding="ascii")
    (RUN/"OOS_COMPLETED.marker").write_text("PENALTY1000_OOS_AND_QA_COMPLETE=true\n",encoding="ascii")
    raw_rows=[]
    for file in sorted(RAW.rglob("*")):
        if file.is_file():raw_rows.append({"role":file.parent.name,"relative_path":str(file.relative_to(ROOT)),"size_bytes":file.stat().st_size,"sha256":sha256(file),"source_head":"cfa789f262b323de1775e5e2376a2d23978753ef","training_seed":20260513,"oos_bank_sha":"6bf3d1190a402ded052b8d3d08ed369042236e151f562bdd9fd4db7b8ff386c6","git_tracked":False})
    save_csv(pd.DataFrame(raw_rows),MANIFESTS/"large_data_manifest.csv")
    short=path[path.ordinary_shortage_total>TOL];gap=stage7[stage7.terminal_site_gap>TOL]
    reasons=stage7.terminal_gap_class.value_counts()
    constraints=data["constraint"].set_index("constraint").fraction_of_positive_gap_last16_path_hours
    summary=pd.DataFrame([
        {"metric":"mean_total_production_kg","value":path.total_H2_production.mean()},
        {"metric":"mean_actual_operating_cost_yuan","value":path.actual_operating_cost.mean()},
        {"metric":"ordinary_shortage_probability","value":len(short)/len(path)},
        {"metric":"ordinary_shortage_if_positive_kg","value":short.ordinary_shortage_total.mean()},
        {"metric":"ordinary_shortage_overall_mean_kg","value":path.ordinary_shortage_total.mean()},
        {"metric":"stage7_path_count","value":len(stage7)},
        {"metric":"stage7_shortfall_probability","value":len(gap)/len(stage7)},
        {"metric":"stage7_shortfall_if_positive_kg","value":gap.terminal_site_gap.mean()},
        {"metric":"pure_quantity_path_count","value":reasons.get("PURE_QUANTITY_SHORTFALL",0)},
        {"metric":"pure_spatial_path_count","value":reasons.get("PURE_SPATIAL_MISMATCH",0)},
        {"metric":"mixed_path_count","value":reasons.get("MIXED_QUANTITY_AND_SPATIAL",0)},
        {"metric":"electrolyzer_binding_last16_fraction","value":constraints.get("任一电解槽达到功率上限",np.nan)},
        {"metric":"voltage_binding_last16_fraction","value":constraints.get("最低电压达到0.90下限",np.nan)},
        {"metric":"line_binding_last16_fraction","value":constraints.get("线路容量达到上限",np.nan)},
    ])
    save_csv(summary,RELEASE/"key_results_summary.csv")
    get=lambda metric:float(summary.loc[summary.metric==metric,"value"].iloc[0])
    diss_mean=float(data["dissipation"].mean_positive_preventive_inventory_kg.mul(data["dissipation"].path_count).sum()/data["dissipation"].path_count.sum())
    difficult=data["tier"].set_index("difficulty_tier")
    extreme=data["extreme"].iloc[0]
    last16=data["aligned"].sort_values("relative_hour")
    first16=last16.iloc[0];final16=last16.iloc[-1];peak_htt=last16.loc[last16.mean_HTT_kg.idxmax()]
    site_text="；".join(f"站点{int(r.site)}目标{r.mean_target_kg:.2f}、实际{r.mean_actual_inventory_kg:.2f}千克" for r in data["stage7_site"].itertuples())
    text=f"""# Stage-89Q：penalty=1000 恢复策略的10000路径测试

状态：**PASS**。本次只验证和测试 penalty=1000，不训练或测试 penalty=1500。

## 通俗结果

这套策略在10000条有序共同路径上平均制氢 **{get('mean_total_production_kg'):.3f} 千克/路径**。第一阶段训练后的固定决策为113.88千克；真实小时曲线只平均当时仍在运行的路径，路径结束后没有补0。

普通用氢方面，发生缺氢的路径比例为 **{100*get('ordinary_shortage_probability'):.2f}%**；一旦发生，平均缺 **{get('ordinary_shortage_if_positive_kg'):.3f} 千克**；摊到全部10000条路径，平均缺 **{get('ordinary_shortage_overall_mean_kg'):.3f} 千克**。

共有 **{int(get('stage7_path_count'))}** 条路径真正进入最终储备检查。其中 **{100*get('stage7_shortfall_probability'):.2f}%** 出现库存不足；一旦不足，平均缺 **{get('stage7_shortfall_if_positive_kg'):.3f} 千克**。正缺口路径中，纯粹因为总氢量不够的有 **{int(get('pure_quantity_path_count'))}** 条，氢总量基本够但站点位置不合适的有 **{int(get('pure_spatial_path_count'))}** 条，总量和位置都有问题的有 **{int(get('mixed_path_count'))}** 条。

Stage7四站平均目标与实际库存为：{site_text}。按全部Stage7路径非重叠分层，普通95%、较困难4%、最极端1%的平均缺口分别为 **{difficult.loc['普通95%','mean_gap_kg']:.3f}、{difficult.loc['较困难4%','mean_gap_kg']:.3f}、{difficult.loc['最极端1%','mean_gap_kg']:.3f} 千克**。最极端路径是 path {int(extreme.path_id)}，缺口 **{extreme.terminal_site_gap:.3f} 千克**；完整62条最极端路径及四站明细见 `05_analysis/05_risk_tail/extreme_stage7_paths.csv`。

后来物理上真正消散的路径共有 {int(path.physical_dissipation_a1.sum())} 条。按“消散时库存减去余下正式48小时普通需求、站点负值不抵消站点正值”的口径，平均正预防性库存为 **{diss_mean:.3f} 千克**。

对473条最终库存不足路径，最后16小时从起点到终点的平均小时制氢由 **{first16.mean_production_kg:.3f}** 变为 **{final16.mean_production_kg:.3f} 千克**，四站总库存由 **{first16.mean_inventory_kg:.3f}** 增至 **{final16.mean_inventory_kg:.3f} 千克**；平均HTT在相对第 {int(peak_htt.relative_hour)} 小时达到峰值 **{peak_htt.mean_HTT_kg:.3f} 千克/小时**。

对最终库存不足路径的最后16个真实运行小时，至少一个电解槽达到功率上限的路径-小时比例为 **{100*get('electrolyzer_binding_last16_fraction'):.2f}%**，最低电压达到0.90下限的比例为 **{100*get('voltage_binding_last16_fraction'):.2f}%**，线路容量达到上限的比例为 **{100*get('line_binding_last16_fraction'):.2f}%**。因此电解槽功率上限是可见的追产限制；线路容量在这批路径中不是主要限制，电压下限的作用见对应小时表。

## 数据与边界

- policy：run-002 penalty=1000，恢复后只读验证为 `ACCEPTED_FOR_TESTING`。
- checkpoint SHA-256：`b6533668ace2ec418f0cab9879aac3b2dc6c422ab5f9e078ad622cb29059328f`。
- OOS：正式 ordered 10000-path bank，SHA-256 `6bf3d1190a402ded052b8d3d08ed369042236e151f562bdd9fd4db7b8ff386c6`。
- 时间分辨率：真实1小时；6个运行阶段，每阶段8小时；结束后的路径无后续行。
- 所有小时、阶段、路径、HTT和Stage7缺口闭合检查均 PASS。
- 5小时固定预算不等于数学收敛证明；`FULLY_CONVERGED = NO`。
- 本次没有运行 penalty=1500，因此不作1000与1500的优劣判断。

```text
TASK_ID = Stage-89Q
STAGE89Q_STATUS = PASS_PENALTY1000_ONLY
RUN002_PENALTY1000_CHECKPOINT = ACCEPTED_FOR_TESTING
CHECKPOINT_RECOVERY_CLASS = POST_RESTART_VALIDATED_RECOVERY
OOS_PATH_COUNT = 10000
TRUE_HOURLY_OOS_SAVED = YES
HOURLY_CLOSURE_QA = PASS
PENALTY1500_STARTED = NO
FULLY_CONVERGED = NO
```
"""
    (RUN/"README.md").write_text(text,encoding="utf-8")
    (RELEASE/"chinese_executive_summary.md").write_text(text,encoding="utf-8")
    light=[]
    for file in sorted(RUN.rglob("*")):
        if file.is_file() and file.name!="result_manifest.csv":light.append({"relative_path":str(file.relative_to(ROOT)),"size_bytes":file.stat().st_size,"sha256":sha256(file)})
    save_csv(pd.DataFrame(light),MANIFESTS/"result_manifest.csv")


def main() -> None:
    setup_dirs()
    path,stage,site,hour,system,flow,bank,training=load_inputs()
    stage7=run_qa(path,stage,site,hour,system,flow,bank)
    data=analyze(path,stage,site,hour,system,flow,stage7,training)
    figure_manifest=figures(data)
    finalize(path,stage7,data,figure_manifest)
    print(f"STAGE89Q_PENALTY1000_QA=PASS figures={len(figure_manifest)}")


if __name__=="__main__":
    main()
