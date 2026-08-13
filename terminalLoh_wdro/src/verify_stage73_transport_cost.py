#!/usr/bin/env python3
from __future__ import annotations
import argparse
from pathlib import Path
import numpy as np
import pandas as pd

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--run-root',required=True); ap.add_argument('--output',required=True); a=ap.parse_args()
    repo=Path(__file__).resolve().parents[2]; root=repo/a.run_root; out=repo/a.output
    required=['README.md','LARGE_FILE_MANIFEST.md','transport_cost_sensitivity_summary.csv','htt_by_stage.csv','htt_od_summary.csv','htt_utilization_summary.csv','htt_flow_quality_audit.csv','htt_directed_od_path_stage_manifest.csv','spatial_mismatch_comparison.csv','production_inventory_shortage_cost.csv','deltaI_comparison.csv','transport_cost_judgment.txt']
    missing=[x for x in required if not (out/x).is_file()]
    if missing: raise RuntimeError(f'missing {missing}')
    paths=[]; hits=[]; prep=[]; state_path=[]; beta_capacity=[]; max_flow_cost=0.; max_total=0.; max_util=0.
    for scheme,cd in [('Reference_08',.8),('H04',.4),('H02',.2),('H01',.1)]:
        for method in ['saa','chi2_eta003']:
            case=root/scheme/f'case-{method}'; d=pd.read_csv(case/'stage73_oos_path_summary.csv').sort_values('path_id'); paths.append(len(d)); hits.append(int(d.terminal_hit.sum())); prep.append(tuple(d.terminal_stage.fillna(7).astype(int).value_counts().sort_index().items()))
            total_detail=0.; total_cost=0.; stage_ids=[]
            for h in pd.read_csv(case/'htt_directed_od_path_stage.csv',chunksize=250000):
                max_flow_cost=max(max_flow_cost,float(np.max(np.abs(h.transport_cost_yuan-h.flow_kg*h.actual_unit_cost_yuan_per_kg))))
                total_detail+=h.flow_kg.sum(); total_cost+=h.transport_cost_yuan.sum(); max_util=max(max_util,float(h.htt_utilization.max()))
                stage_ids.append(h.drop_duplicates(['path_id','stage'])[['path_id','stage','state_k','beta','effective_htt_capacity_kg']])
            stage_ids=pd.concat(stage_ids).drop_duplicates(['path_id','stage']).sort_values(['path_id','stage']).reset_index(drop=True)
            state_path.append(tuple(map(tuple,stage_ids[['path_id','stage','state_k']].to_numpy())))
            beta_capacity.append(tuple(map(tuple,np.round(stage_ids[['beta','effective_htt_capacity_kg']].to_numpy(),10))))
            max_total=max(max_total,abs(total_detail-d.htt.sum()),abs(total_cost-d.transport_cost.sum()))
    if paths!=[10000]*8 or hits!=[6053]*8 or len(set(prep))!=1: raise RuntimeError(f'common OOS failed paths={paths} hits={hits}')
    if len(set(state_path))!=1 or len(set(beta_capacity))!=1: raise RuntimeError('common path-stage state/beta/capacity identity failed')
    mm=pd.read_csv(out/'spatial_mismatch_comparison.csv')
    max_mismatch_conservation=float(np.max(np.maximum(0,mm.statically_coverable_gap_kg-mm.total_gap_kg)))
    fq=pd.read_csv(out/'htt_flow_quality_audit.csv')
    max_reciprocal_share=float(fq.reciprocal_share_of_total_htt.max())
    if max(max_flow_cost,max_total,max(0,max_util-1),max_mismatch_conservation)>1e-5: raise RuntimeError(f'closure flow_cost={max_flow_cost} totals={max_total} util={max_util} mismatch={max_mismatch_conservation}')
    audit=f'''Stage-73 mechanical verification\nstatus=PASS\npath_counts={paths}\nterminal_hits={hits}\ncommon_preparation_distribution=PASS\ncommon_path_stage_state_identity=PASS\ncommon_beta_effective_capacity_identity=PASS\nmax_flow_cost_error={max_flow_cost:.12g}\nmax_case_total_closure_error={max_total:.12g}\nmax_utilization={max_util:.12g}\nmax_spatial_mismatch_conservation_error={max_mismatch_conservation:.12g}\nmax_simultaneous_reciprocal_flow_share={max_reciprocal_share:.12g}\npolicies=fixed_budget_stop_flag_2_not_formally_converged\ncausal_interpretation=NOT_ESTABLISHED\n'''
    (out/'mechanical_verification.txt').write_text(audit,encoding='utf-8'); print('STAGE73_VERIFY_PASS')
if __name__=='__main__': main()
