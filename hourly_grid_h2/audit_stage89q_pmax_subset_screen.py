#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Independent source/output audit for Stage-89Q-G4-Lite."""

from __future__ import annotations

import ast
import hashlib
import math
import os
from pathlib import Path

import numpy as np
import pandas as pd
from scipy.io import loadmat


ROOT = Path(__file__).resolve().parents[1]
RUN = ROOT / "results/task-002-stage2b-b3-smoke/stage89q-penalty1000-vs1500-long-training/run-003"
DEEP = RUN / "05_analysis/10_deep_penalty1000"
PHYS = DEEP / "17_pmax_flexibility_audit"
G2 = DEEP / "19_s4_grid_aware_recoverability"
G3 = DEEP / "20_all125_grid_aware_recoverability"
OUT = DEEP / "21_pmax_subset_screen"
FIG = RUN / "06_figures/15_pmax_subset_screen"
FORMAL = ROOT / "data/yuanqi/near_stage_msp_input.mat"
MAIN = ROOT / "hourly_grid_h2/analyze_stage89q_pmax_subset_screen.py"
TOL = 1e-7
HOST_TOL = 1e-5
EXPECTED_ORDER = ["B0000","B1000","B0100","B0010","B0001","B1100","B1010","B1001",
                  "B0110","B0101","B0011","B1110","B1101","B1011","B0111","B1111"]
NEW_MULTI = {"B1100","B1010","B1001","B0110","B0101","B0011","B1110","B1101","B1011","B0111"}


def io_path(path: Path) -> str:
    value=str(path.resolve())
    return "\\\\?\\"+value if os.name=="nt" and not value.startswith("\\\\?\\") else value


def sha256(path: Path) -> str:
    digest=hashlib.sha256()
    with open(io_path(path),"rb") as stream:
        for block in iter(lambda:stream.read(1024*1024),b""): digest.update(block)
    return digest.hexdigest()


def save_csv(frame: pd.DataFrame,path: Path) -> None:
    frame.to_csv(io_path(path),index=False,encoding="utf-8-sig",float_format="%.12g")


def bits(candidate: str) -> np.ndarray:
    return np.array([int(x) for x in candidate[1:]],dtype=int)


def dotted(node: ast.AST) -> str:
    if isinstance(node,ast.Name): return node.id
    if isinstance(node,ast.Attribute):
        prefix=dotted(node.value); return f"{prefix}.{node.attr}" if prefix else node.attr
    return ""


def forbidden(path: Path) -> list[str]:
    tree=ast.parse(path.read_text(encoding="utf-8")); found=[]
    for node in ast.walk(tree):
        if isinstance(node,(ast.Import,ast.ImportFrom)):
            module=getattr(node,"module","") or ""; names=[x.name for x in node.names]+[module]
            found.extend(x for x in names if x in {"random","gurobipy","cvxpy","pulp"} or x.startswith("numpy.random"))
        elif isinstance(node,ast.Call) and dotted(node.func).startswith(("np.random","numpy.random","gurobipy")): found.append(dotted(node.func))
    return sorted(set(found))


def main() -> None:
    paths={
        "catalog":OUT/"01_existing_inputs/candidate_catalog.csv",
        "h2_events":OUT/"02_h2_side_screen/all16_h2_side_events.csv",
        "h2_summary":OUT/"02_h2_side_screen/all16_h2_side_summary.csv",
        "grid_events":OUT/"03_grid_aware_screen/all16_grid_aware_events.csv",
        "grid_summary":OUT/"03_grid_aware_screen/all16_grid_aware_summary.csv",
        "cache":OUT/"03_grid_aware_screen/candidate_joint_profile_cache.csv",
        "reuse":OUT/"03_grid_aware_screen/computation_reuse_ledger.csv",
        "pairs":OUT/"04_site_value/subset_pair_site_value.csv",
        "signals":OUT/"04_site_value/site_expansion_signals.csv",
        "leave":OUT/"04_site_value/leave_one_site_out_all125.csv",
        "frontier":OUT/"05_candidate_frontier/pareto_frontier.csv",
        "thresholds":OUT/"05_candidate_frontier/all125_gain_thresholds.csv",
        "selected":OUT/"06_candidate_decision/selected_candidates.csv",
        "status":OUT/"06_candidate_decision/final_status.csv",
    }
    if not all(os.path.isfile(io_path(path)) for path in paths.values()): raise RuntimeError("Missing G4-Lite outputs")
    out={key:pd.read_csv(io_path(path)) for key,path in paths.items()}
    physical=pd.read_csv(io_path(PHYS/"02_counterfactual_recoverability/pmax_candidate_recoverability_by_path.csv"))
    g2=pd.read_csv(io_path(G2/"03_grid_aware_recoverability/s4_125_grid_aware_recovery_by_event.csv"))
    g3=pd.read_csv(io_path(G3/"03_grid_aware_recoverability/all125_grid_aware_recovery_by_event.csv"))
    template=pd.read_csv(io_path(G3/"02_joint_effective_capacity/all125_site_resolved_joint_hourly.csv"))
    device=loadmat(io_path(FORMAL),simplify_cells=True)["NearStageInput"]["HydrogenDevice"]
    base=np.asarray(device["el_cap_kw"],dtype=float).ravel(); expanded=base*1.25; increments=base*.25
    k_h2=float(device["k_H2_kg_per_kWh"])
    checks=[]
    def check(name,observed,expected,passed,source): checks.append({"check":name,"observed":observed,"expected":expected,"source":source,"pass":bool(passed)})
    check("formal_hash",sha256(FORMAL),"536b2586...",sha256(FORMAL)=="536b25868e6d7cc812a331c0d3e0ffbd5f6958e6883bd39bcae3901c372abf24","formal MAT")
    check("formal_base",base.tolist(),[300,200,120,150],np.array_equal(base,[300,200,120,150]),"formal MAT")
    check("formal_expanded",expanded.tolist(),[375,250,150,187.5],np.array_equal(expanded,[375,250,150,187.5]),"formal MAT")
    check("formal_k_h2",k_h2,.0195,abs(k_h2-.0195)<=TOL,"formal MAT")
    catalog=out["catalog"]
    check("candidate_order",catalog.candidate.tolist(),EXPECTED_ORDER,catalog.candidate.tolist()==EXPECTED_ORDER,"catalog")
    check("candidate_count",len(catalog),16,len(catalog)==16,"catalog")
    check("candidate_vector_unique",catalog[[f"Pmax{i}_kW" for i in range(1,5)]].duplicated().sum(),0,not catalog[[f"Pmax{i}_kW" for i in range(1,5)]].duplicated().any(),"catalog")
    vector_ok=True
    for row in catalog.itertuples(index=False):
        expected=base+bits(row.candidate)*increments
        observed=np.array([getattr(row,f"Pmax{i}_kW") for i in range(1,5)])
        vector_ok &= np.array_equal(expected,observed) and abs((expected-base).sum()-row.added_kW)<=TOL
    check("candidate_vectors_from_formal",vector_ok,True,vector_ok,"formal MAT + catalog")
    base_rows=physical[(physical.candidate=="B0")&physical.base_physically_unrecoverable&physical.checkpoint_present]
    base_counts=[int((base_rows.relative_hour==cut).sum()) for cut in [-16,-8,-4]]
    check("base_70_156_167",base_counts,[70,156,167],base_counts==[70,156,167],"Stage89Q physical")
    h2_events=out["h2_events"]; h2_summary=out["h2_summary"].set_index("candidate")
    h2_identity_ok=True; h2_summary_ok=True
    for row in catalog.itertuples(index=False):
        pmax=np.array([getattr(row,f"Pmax{i}_kW") for i in range(1,5)])
        margin=base_rows.current_inventory_kg+pmax.sum()*k_h2*(-base_rows.relative_hour)-base_rows.target_total
        expected_keys=set() if row.candidate=="B0000" else set(zip(base_rows.loc[margin>=-TOL,"path_id"],base_rows.loc[margin>=-TOL,"relative_hour"]))
        observed=h2_events[h2_events.candidate==row.candidate]
        observed_keys=set(zip(observed.path_id,observed.checkpoint_relative_hour))
        h2_identity_ok &= expected_keys==observed_keys
        summary=h2_summary.loc[row.candidate]
        h2_summary_ok &= summary.H2_recovered_events==len(observed) and summary.H2_unique_paths==observed.path_id.nunique()
        h2_summary_ok &= all(summary[f"recovered_{cut}"]==int((observed.checkpoint_relative_hour==cut).sum()) for cut in [-16,-8,-4])
    check("all16_h2_event_identity",h2_identity_ok,True,h2_identity_ok,"independent physical formula")
    check("all16_h2_summary",h2_summary_ok,True,h2_summary_ok,"event aggregation")
    check("pure_location_gain_zero",h2_summary.pure_location_recovered.sum(),0,h2_summary.pure_location_recovered.sum()==0,"H2 summary")
    reuse=out["reuse"].set_index("candidate")
    check("new_multi_candidate_set",set(reuse.loc[reuse.new_joint_LP_solves>0].index),NEW_MULTI,set(reuse.loc[reuse.new_joint_LP_solves>0].index)==NEW_MULTI,"reuse ledger")
    check("anchors_not_resolved",reuse.loc[["B0001","B1111"],"new_joint_LP_solves"].sum(),0,reuse.loc[["B0001","B1111"],"new_joint_LP_solves"].sum()==0,"reuse ledger")
    check("base_not_recomputed",set(reuse.base_grid_state_recomputed),{"NO"},set(reuse.base_grid_state_recomputed)=={"NO"},"reuse ledger")
    check("independent_headrooms_not_summed",set(reuse.independent_headrooms_summed),{"NO"},set(reuse.independent_headrooms_summed)=={"NO"},"reuse ledger")
    profiles=template.drop_duplicates("profile_id").set_index("profile_id")
    cache=out["cache"]
    cache_ok=True; source_ok=True
    for row in cache.itertuples(index=False):
        mask=bits(row.candidate).astype(bool); profile=profiles.loc[row.profile_id]
        realized=np.array([profile[f"site{i}_realized_pel_kw"] for i in range(1,5)])
        pel=np.array([getattr(row,f"site{i}_lp_pel_kw") for i in range(1,5)])
        delta=np.array([getattr(row,f"site{i}_effective_increment_above_base_kw") for i in range(1,5)])
        cache_ok &= np.allclose(pel[~mask],realized[~mask],atol=TOL) and np.allclose(delta[~mask],0,atol=TOL)
        cache_ok &= np.all(pel[mask]>=realized[mask]-TOL) and np.all(pel[mask]<=expanded[mask]+TOL)
        cache_ok &= np.allclose(delta[mask],pel[mask]-base[mask],atol=TOL)
        cache_ok &= abs(row.effective_total_physical_pmax_kw-(base.sum()+delta.sum()))<=TOL
        source_ok &= row.source==("G4_NEW_CANDIDATE_DEPENDENT_JOINT_LP" if row.candidate in NEW_MULTI else "STAGE89Q_G_SINGLE_SITE_CACHE")
    check("site_resolved_cache_formula",cache_ok,True,cache_ok,"cache + G3 realized profiles")
    check("cache_source_partition",source_ok,True,source_ok,"cache")
    check("site_resolved_witness",cache.site_resolved_joint_witness.eq("YES").all(),True,cache.site_resolved_joint_witness.eq("YES").all(),"cache")
    grid_events=out["grid_events"]; grid_formula_ok=True
    for candidate in [x for x in EXPECTED_ORDER if x not in {"B0000","B0001","B1111"}]:
        candidate_cache=cache[cache.candidate==candidate]
        for event in h2_events[h2_events.candidate==candidate].itertuples(index=False):
            window=template[(template.path_id==event.path_id)&(template.relative_hour>=event.checkpoint_relative_hour)].merge(candidate_cache,on=["profile_id","global_hour"],validate="many_to_one")
            margin=event.current_inventory_kg+k_h2*window.effective_total_physical_pmax_kw.sum()-event.target_total_kg
            observed=grid_events[(grid_events.candidate==candidate)&(grid_events.path_id==event.path_id)&(grid_events.checkpoint_relative_hour==event.checkpoint_relative_hour)].iloc[0]
            grid_formula_ok &= abs(margin-observed.grid_aware_recovery_margin_kg)<=1e-8
            grid_formula_ok &= ((margin>=-TOL)==(observed.grid_aware_recovery_supported=="YES"))
    check("new_candidate_grid_margin_recomposition",grid_formula_ok,True,grid_formula_ok,"independent event-hour join")
    g2out=grid_events[grid_events.candidate=="B0001"]
    g3out=grid_events[grid_events.candidate=="B1111"]
    check("S4_anchor_event_identity",set(zip(g2out.path_id,g2out.checkpoint_relative_hour)),set(zip(g2.path_id,g2.checkpoint_relative_hour)),set(zip(g2out.path_id,g2out.checkpoint_relative_hour))==set(zip(g2.path_id,g2.checkpoint_relative_hour)),"G2 formal events")
    check("S4_anchor_retained",g2out.grid_aware_recovery_supported.eq("YES").sum(),39,g2out.grid_aware_recovery_supported.eq("YES").sum()==39,"G2 formal events")
    check("ALL_anchor_event_identity",set(zip(g3out.path_id,g3out.checkpoint_relative_hour)),set(zip(g3.path_id,g3.checkpoint_relative_hour)),set(zip(g3out.path_id,g3out.checkpoint_relative_hour))==set(zip(g3.path_id,g3.checkpoint_relative_hour)),"G3 formal events")
    check("ALL_anchor_retained_paths",[g3out.grid_aware_recovery_supported.eq("YES").sum(),g3out.loc[g3out.grid_aware_recovery_supported=="YES","path_id"].nunique()],[104,89],g3out.grid_aware_recovery_supported.eq("YES").sum()==104 and g3out.loc[g3out.grid_aware_recovery_supported=="YES","path_id"].nunique()==89,"G3 formal events")
    grid_summary=out["grid_summary"].set_index("candidate"); grid_summary_ok=True
    for candidate in EXPECTED_ORDER:
        frame=grid_events[grid_events.candidate==candidate]; retained=frame.grid_aware_recovery_supported.eq("YES"); row=grid_summary.loc[candidate]
        grid_summary_ok &= row.grid_aware_retained_events==retained.sum() and row.grid_aware_unique_paths==frame.loc[retained,"path_id"].nunique()
        grid_summary_ok &= row.grid_loss_events==frame.classification.eq("GRID_CLIPPING_REMOVES_RECOVERY_SUPPORT").sum()
    check("all16_grid_summary",grid_summary_ok,True,grid_summary_ok,"grid event aggregation")
    pairs=out["pairs"]; pair_ok=True
    for row in pairs.itertuples(index=False):
        a=grid_summary.loc[row.without_candidate]; b=grid_summary.loc[row.with_candidate]
        pair_ok &= row.additional_retained_events==b.grid_aware_retained_events-a.grid_aware_retained_events
        pair_ok &= row.additional_unique_paths==b.grid_aware_unique_paths-a.grid_aware_unique_paths
        pair_ok &= abs(row.additional_kW-(b.added_kW-a.added_kW))<=TOL
    check("32_subset_pair_recomposition",[len(pairs),pair_ok],[32,True],len(pairs)==32 and pair_ok,"grid summary")
    check("subset_retained_monotonic",pairs.additional_retained_events.min(),">=0",pairs.additional_retained_events.min()>=0,"site pairs")
    frontier=out["frontier"]; pareto_ok=True
    for row in frontier.itertuples(index=False):
        dominated=((frontier.added_kW<=row.added_kW+TOL)&(frontier.grid_aware_retained_events>=row.grid_aware_retained_events)&((frontier.added_kW<row.added_kW-TOL)|(frontier.grid_aware_retained_events>row.grid_aware_retained_events))).any()
        pareto_ok &= row.PARETO_NONDOMINATED==("NO" if dominated else "YES")
    check("Pareto_independent",pareto_ok,True,pareto_ok,"frontier recomposition")
    threshold_ok=True; all_gain=grid_summary.loc["B1111","grid_aware_retained_events"]
    for row in out["thresholds"].itertuples(index=False):
        target=math.ceil(row.ALL_retained_gain_fraction_target*all_gain-1e-12)
        eligible=out["grid_summary"][out["grid_summary"].grid_aware_retained_events>=target]
        threshold_ok &= row.required_retained_events==target and abs(row.minimum_added_kW-eligible.added_kW.min())<=TOL
    check("ALL_gain_thresholds",threshold_ok,True,threshold_ok,"grid summary")
    check("selected_candidates_max3",len(out["selected"]),"<=3",len(out["selected"])<=3,"decision")
    check("selected_expected_roles",set(out["selected"].candidate),{"B0001","B1011","B1111"},set(out["selected"].candidate)=={"B0001","B1011","B1111"},"decision rules")
    status=out["status"].set_index("status").value
    check("recommendation_enumerated",status["RECOMMEND_NEXT"],"enumerated",status["RECOMMEND_NEXT"] in {"S4_SMOKE","ASYMMETRIC_CANDIDATE_SMOKE","S4_AND_ASYMMETRIC_SMOKE","NEEDS_MORE_DIAGNOSTIC","NO_PMAX_PILOT"},"status")
    check("no_forbidden_capability",forbidden(MAIN),[],forbidden(MAIN)==[],"main AST")
    check("figure_count",len(list(FIG.glob("[0-9][0-9]_*.png"))),8,len(list(FIG.glob("[0-9][0-9]_*.png")))==8,"figure directory")
    check("contact_sheet",(FIG/"contact_sheet.png").is_file(),True,(FIG/"contact_sheet.png").is_file(),"figure directory")
    artifacts=[p for base_path in [OUT,FIG] for p in base_path.rglob("*") if p.is_file()]
    check("lightweight_extensions",sorted({p.suffix.lower() for p in artifacts}),[".csv",".md",".png"],all(p.suffix.lower() in {".csv",".md",".png"} for p in artifacts),"accepted trees")
    frame=pd.DataFrame(checks); save_csv(frame,OUT/"08_qa/independent_qa.csv")
    if not frame["pass"].all(): raise RuntimeError("Independent QA failed: "+"; ".join(frame.loc[~frame["pass"],"check"]))
    print(f"Independent QA PASS: {len(frame)}/{len(frame)}",flush=True)


if __name__=="__main__": main()
