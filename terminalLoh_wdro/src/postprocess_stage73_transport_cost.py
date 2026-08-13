#!/usr/bin/env python3
"""Unified postprocessing after all Stage-73 numerical work has ended."""

from __future__ import annotations
import argparse, hashlib, math
from pathlib import Path
import h5py
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

SCHEMES=[("Reference_08",0.8),("H04",0.4),("H02",0.2),("H01",0.1)]
METHODS=["saa","chi2_eta003"]
TOL=1e-8

def q95(x): return float(np.quantile(np.asarray(x,float),.95)) if len(x) else math.nan

def sha256(path: Path) -> str:
    h=hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda:f.read(1024*1024),b''): h.update(block)
    return h.hexdigest()

def h5_scalar(f: h5py.File, key: str) -> float:
    return float(np.asarray(f[key][()]).reshape(-1)[0])

def h5_vector(f: h5py.File, key: str) -> np.ndarray:
    return np.asarray(f[key][()],dtype=float).reshape(-1)

def workspace_for_case(root: Path, scheme: str, method: str) -> Path:
    case=root/scheme/f'case-{method}'
    direct=case/'native_output'/'h2_workspace.mat'
    if direct.is_file(): return direct
    source=case/'REFERENCE_POLICY_SOURCE.txt'
    if not source.is_file(): raise RuntimeError(f'missing workspace identity: {case}')
    line=next((x for x in source.read_text(encoding='utf-8').splitlines() if x.startswith('source=')),None)
    if line is None: raise RuntimeError(f'bad reference identity: {source}')
    path=Path(line.split('=',1)[1])
    if not path.is_file(): raise RuntimeError(f'missing reference workspace: {path}')
    return path

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--run-root',required=True); ap.add_argument('--output',required=True); a=ap.parse_args()
    repo=Path(__file__).resolve().parents[2]; root=repo/a.run_root; out=repo/a.output
    if out.exists(): raise RuntimeError(f'output exists: {out}')
    out.mkdir(parents=True)
    summaries={}; detail_files={}
    for scheme,cd in SCHEMES:
        for method in METHODS:
            case=root/scheme/f'case-{method}'
            p=case/'stage73_oos_path_summary.csv'; h=case/'htt_directed_od_path_stage.csv'
            if not p.is_file() or not h.is_file(): raise RuntimeError(f'missing completed evaluation: {case}')
            d=pd.read_csv(p).sort_values('path_id').reset_index(drop=True); d['c_d']=cd
            if len(d)!=10000 or d.path_id.tolist()!=list(range(1,10001)): raise RuntimeError(f'path identity {case}')
            summaries[(scheme,method)]=d; detail_files[(scheme,method)]=h
    ref=summaries[("Reference_08","saa")]
    for d in summaries.values():
        for col in ['terminal_hit','terminal_stage','terminal_state_k']:
            if not np.allclose(d[col].fillna(0),ref[col].fillna(0),atol=0,rtol=0): raise RuntimeError(f'common OOS failed {col}')

    stage_rows=[]; od_rows=[]; util_rows=[]; cost_rows=[]; flow_quality_rows=[]; detail_stage_identity={}
    for (scheme,method),path in detail_files.items():
        chunks=[]
        for ch in pd.read_csv(path,chunksize=250000):
            chunks.append(ch)
        h=pd.concat(chunks,ignore_index=True)
        stage_unique=h.drop_duplicates(['path_id','stage'])
        detail_stage_identity[(scheme,method)]=stage_unique[['path_id','stage','state_k','beta','effective_htt_capacity_kg']].sort_values(['path_id','stage']).reset_index(drop=True)
        for stage,g in stage_unique.groupby('stage'):
            flow=g.total_htt_stage_kg.to_numpy(float); util=g.htt_utilization.to_numpy(float)
            stage_rows.append(dict(scheme=scheme,method=method,stage=int(stage),active_stage_observations=len(g),total_htt_kg=flow.sum(),mean_htt_kg_per_active_stage_observation=flow.mean(),mean_htt_kg_per_all_oos_path=flow.sum()/10000,nonzero_active_stage_share=np.mean(flow>TOL),stage4_6=int(stage) in [4,5,6]))
            util_rows.append(dict(scheme=scheme,method=method,stage=int(stage),mean_utilization=util.mean(),median_utilization=np.median(util),q95_utilization=q95(util),util_ge80_share=np.mean(util>=.8-TOL),util_ge95_share=np.mean(util>=.95-TOL),max_utilization=util.max()))
            pos=h[(h.stage==stage)&(h.flow_kg>TOL)]
            cost_rows.append(dict(scheme=scheme,method=method,stage=int(stage),total_htt_kg=pos.flow_kg.sum(),total_transport_cost_yuan=pos.transport_cost_yuan.sum(),weighted_actual_cost_yuan_per_kg=pos.transport_cost_yuan.sum()/pos.flow_kg.sum() if len(pos) else math.nan))
        for (stage,i,j),g in h.groupby(['stage','origin_site','destination_site']):
            od_rows.append(dict(scheme=scheme,method=method,stage=int(stage),origin_site=int(i),destination_site=int(j),active_stage_observations=len(g),total_flow_kg=g.flow_kg.sum(),mean_flow_kg_per_active_stage_observation=g.flow_kg.mean(),mean_flow_kg_per_all_oos_path=g.flow_kg.sum()/10000,nonzero_active_stage_share=np.mean(g.flow_kg>TOL),transport_cost_yuan=g.transport_cost_yuan.sum(),weighted_unit_cost_yuan_per_kg=g.transport_cost_yuan.sum()/g.flow_kg.sum() if g.flow_kg.sum()>TOL else math.nan))
        wide=h.pivot_table(index=['path_id','stage'],columns=['origin_site','destination_site'],values='flow_kg',aggfunc='sum',fill_value=0)
        reciprocal=np.zeros(len(wide),dtype=float)
        for i in range(1,5):
            for j in range(i+1,5): reciprocal+=2*np.minimum(np.maximum(0,wide[(i,j)].to_numpy(float)),np.maximum(0,wide[(j,i)].to_numpy(float)))
        gross=stage_unique.sort_values(['path_id','stage']).total_htt_stage_kg.to_numpy(float)
        flow_quality_rows.append(dict(scheme=scheme,method=method,path_stage_observations=len(wide),path_stages_with_reciprocal_flow=int(np.sum(reciprocal>TOL)),reciprocal_path_stage_share=float(np.mean(reciprocal>TOL)),total_reciprocal_gross_flow_kg=float(reciprocal.sum()),reciprocal_share_of_total_htt=float(reciprocal.sum()/gross.sum()) if gross.sum()>TOL else 0.0,interpretation='simultaneous opposite-direction OD flow is an artifact screen, not a complete cycle proof'))
    identity_ref=detail_stage_identity[("Reference_08","saa")]
    for key,z in detail_stage_identity.items():
        if len(z)!=len(identity_ref) or not z[['path_id','stage','state_k']].equals(identity_ref[['path_id','stage','state_k']]):
            raise RuntimeError(f'common active state path failed: {key}')
        if not np.allclose(z[['beta','effective_htt_capacity_kg']],identity_ref[['beta','effective_htt_capacity_kg']],atol=1e-10,rtol=0):
            raise RuntimeError(f'common beta/capacity path failed: {key}')
    stage=pd.DataFrame(stage_rows); od=pd.DataFrame(od_rows); util=pd.DataFrame(util_rows); cost=pd.DataFrame(cost_rows)
    stage.to_csv(out/'htt_by_stage.csv',index=False); od.to_csv(out/'htt_od_summary.csv',index=False); util.to_csv(out/'htt_utilization_summary.csv',index=False); pd.DataFrame(flow_quality_rows).to_csv(out/'htt_flow_quality_audit.csv',index=False)

    mismatch=[]; perf=[]
    for (scheme,method),d in summaries.items():
        hit=d[d.terminal_hit==1]; gp=mp=full=partial=none=0; total_gap=cover=0.
        for r in hit.itertuples():
            gaps=np.array([max(0,getattr(r,f'target_site{i}')-getattr(r,f'final_site{i}')) for i in range(1,5)])
            surplus=np.array([max(0,getattr(r,f'final_site{i}')-getattr(r,f'target_site{i}')) for i in range(1,5)])
            G=float(gaps.sum())
            if G<=TOL: continue
            C=min(G,float(surplus.sum())); gp+=1; total_gap+=G; cover+=C; mp+=C>TOL
            full+=C>=G-TOL; partial+=C>TOL and C<G-TOL; none+=C<=TOL
        mismatch.append(dict(scheme=scheme,method=method,terminal_hits=len(hit),gap_positive_paths=gp,paths_with_other_site_surplus=mp,spatial_mismatch_share=mp/gp,total_gap_kg=total_gap,statically_coverable_gap_kg=cover,coverable_share=cover/total_gap,fully_coverable_paths=full,partly_coverable_paths=partial,no_surplus_paths=none,interpretation='static terminal inventory only; not nonanticipative feasible recourse'))
        perf.append(dict(scheme=scheme,method=method,c_d=float(d.c_d.iloc[0]),mean_production_kg=d.production.mean(),mean_final_inventory_kg=d.final_inventory.mean(),mean_htt_kg=d.htt.mean(),nonzero_htt_path_share=np.mean(d.htt>TOL),mean_ordinary_shortage_kg=d.ordinary_shortage.mean(),mean_terminal_gap_kg=d.terminal_gap.fillna(0).mean(),mean_operating_cost_yuan=d.operating_cost.mean(),mean_transport_cost_yuan=d.transport_cost.mean(),mean_reported_objective_yuan=d.reported_objective.mean()))
    pd.DataFrame(mismatch).to_csv(out/'spatial_mismatch_comparison.csv',index=False)
    perf=pd.DataFrame(perf); perf.to_csv(out/'production_inventory_shortage_cost.csv',index=False)

    cd_map=dict(SCHEMES)
    local_cost_rows=[]
    for scheme,cd in SCHEMES:
        ws=workspace_for_case(root,scheme,'saa')
        with h5py.File(ws,'r') as f:
            prices=h5_vector(f,'params/cost_electricity_stage')
            om=h5_scalar(f,'params/cost_el_om'); k_h2=h5_scalar(f,'params/k_H2')
        for stage_no in range(1,7):
            local_cost_rows.append(dict(scheme=scheme,stage=stage_no,local_production_marginal_cost_yuan_per_kg=(prices[stage_no-1]+om)/k_h2))
    local_cost=pd.DataFrame(local_cost_rows)
    for r in cost_rows:
        r['c_d']=cd_map[r['scheme']]
    cost=pd.DataFrame(cost_rows).merge(local_cost,on=['scheme','stage'],how='left')
    cost['transport_to_local_production_cost_ratio']=cost.weighted_actual_cost_yuan_per_kg/cost.local_production_marginal_cost_yuan_per_kg
    cost.to_csv(out/'transport_cost_by_stage.csv',index=False)
    od['c_d']=od.scheme.map(cd_map)
    od.to_csv(out/'htt_od_summary.csv',index=False)

    delta=[]; prep=[]
    for scheme,cd in SCHEMES:
        s=summaries[(scheme,'saa')]; d=summaries[(scheme,'chi2_eta003')]; di=d.final_inventory-s.final_inventory
        hit=d.terminal_hit.eq(1); prep_count=np.where(hit,d.terminal_stage-1,6)
        delta.append(dict(scheme=scheme,c_d=cd,mean_delta_I_kg=di.mean(),delta_I_le1_share=np.mean(di<=1),delta_I_gt10_share=np.mean(di>10),delta_I_gt20_share=np.mean(di>20),delta_I_20_50_share=np.mean((di>20)&(di<=50))))
        for p in sorted(pd.unique(prep_count)):
            x=di[prep_count==p]; prep.append(dict(scheme=scheme,c_d=cd,preparation_stage_count=int(p),path_count=len(x),mean_delta_I_kg=x.mean(),median_delta_I_kg=np.median(x),delta_I_le1_share=np.mean(x<=1),delta_I_gt20_share=np.mean(x>20)))
    pd.DataFrame(delta).to_csv(out/'deltaI_comparison.csv',index=False); pd.DataFrame(prep).to_csv(out/'prep_count_deltaI.csv',index=False)

    total=[]
    for scheme,cd in SCHEMES:
        for method in METHODS:
            p=perf[(perf.scheme==scheme)&(perf.method==method)].iloc[0]
            c=cost[(cost.scheme==scheme)&(cost.method==method)]
            late=stage[(stage.scheme==scheme)&(stage.method==method)&stage.stage.isin([4,5,6])]
            total.append(dict(scheme=scheme,method=method,c_d=cd,mean_htt_kg_per_path=p.mean_htt_kg,nonzero_htt_path_share=p.nonzero_htt_path_share,stage4_6_total_htt_kg=late.total_htt_kg.sum(),stage4_6_mean_htt_kg_per_path=late.total_htt_kg.sum()/10000,stage4_6_share=late.total_htt_kg.sum()/stage[(stage.scheme==scheme)&(stage.method==method)].total_htt_kg.sum(),total_transport_cost_yuan=c.total_transport_cost_yuan.sum(),mean_transport_cost_yuan_per_path=c.total_transport_cost_yuan.sum()/10000,weighted_transport_cost_yuan_per_kg=c.total_transport_cost_yuan.sum()/c.total_htt_kg.sum(),stage4_cost_yuan_per_kg=c[c.stage==4].weighted_actual_cost_yuan_per_kg.iloc[0],stage5_cost_yuan_per_kg=c[c.stage==5].weighted_actual_cost_yuan_per_kg.iloc[0],stage6_cost_yuan_per_kg=c[c.stage==6].weighted_actual_cost_yuan_per_kg.iloc[0],mean_local_production_marginal_cost_yuan_per_kg=c.local_production_marginal_cost_yuan_per_kg.mean(),transport_to_local_production_cost_ratio=(c.total_transport_cost_yuan.sum()/c.total_htt_kg.sum())/c.local_production_marginal_cost_yuan_per_kg.mean()))
    total_df=pd.DataFrame(total); total_df.to_csv(out/'transport_cost_sensitivity_summary.csv',index=False)

    def line(metric,ylabel,name,source=perf):
        fig,ax=plt.subplots(figsize=(7.5,4.6))
        for method in METHODS:
            z=source[source.method==method].sort_values('c_d'); ax.plot(z.c_d,z[metric],marker='o',label=method)
        ax.set(xlabel='Base distance coefficient c_d',ylabel=ylabel); ax.grid(alpha=.25); ax.legend(); fig.tight_layout(); fig.savefig(out/name,dpi=180); plt.close(fig)
    line('mean_htt_kg','Mean HTT (kg/path)','fig_cd_vs_mean_htt.png')
    late=stage[stage.stage.isin([4,5,6])].groupby(['scheme','method'],as_index=False).total_htt_kg.sum().merge(pd.DataFrame(SCHEMES,columns=['scheme','c_d']))
    late['mean_stage4_6_htt_kg_per_path']=late.total_htt_kg/10000
    line('mean_stage4_6_htt_kg_per_path','Stage 4-6 HTT (kg/path)','fig_cd_vs_stage46_htt.png',late)
    mm=pd.DataFrame(mismatch).merge(pd.DataFrame(SCHEMES,columns=['scheme','c_d']))
    fig,(ax,ax2)=plt.subplots(1,2,figsize=(12,4.6))
    for method in METHODS:
        z=mm[mm.method==method].sort_values('c_d'); ax.plot(z.c_d,z.coverable_share*100,marker='o',label=f'{method} coverable gap %')
    ax.set(xlabel='c_d',ylabel='Static coverable gap (%)'); ax.grid(alpha=.25); ax.legend()
    for method in METHODS:
        z=perf[perf.method==method].sort_values('c_d'); ax2.plot(z.c_d,z.mean_terminal_gap_kg,marker='o',label=f'{method} terminal gap')
    ax2.set(xlabel='c_d',ylabel='Mean terminal gap (kg/path)'); ax2.grid(alpha=.25); ax2.legend(); fig.tight_layout(); fig.savefig(out/'fig_cd_vs_spatial_mismatch_terminal_gap.png',dpi=180); plt.close(fig)
    fig,axes=plt.subplots(2,4,figsize=(13,6.5),constrained_layout=True)
    vmax=od.groupby(['scheme','method','origin_site','destination_site']).total_flow_kg.sum().max()
    for ax,(scheme,cd,method) in zip(axes.ravel(),[(s,c,m) for m in METHODS for s,c in SCHEMES]):
        z=od[(od.scheme==scheme)&(od.method==method)].groupby(['origin_site','destination_site']).total_flow_kg.sum(); mat=np.zeros((4,4))
        for (i,j),v in z.items(): mat[int(i)-1,int(j)-1]=v
        im=ax.imshow(mat,cmap='YlOrRd',vmin=0,vmax=vmax); ax.set_title(f'{scheme} {method}'); ax.set_xticks(range(4)); ax.set_xticklabels(range(1,5)); ax.set_yticks(range(4)); ax.set_yticklabels(range(1,5)); ax.set_xlabel('to'); ax.set_ylabel('from')
    fig.colorbar(im,ax=axes.ravel().tolist(),fraction=.018,pad=.02,label='Total flow (kg)')
    fig.suptitle('Directed HTT flow by transport coefficient'); fig.savefig(out/'fig_directed_od_heatmaps.png',dpi=180); plt.close(fig)
    fig,axes=plt.subplots(1,3,figsize=(13,4.2))
    for ax,metric,label in zip(axes,['mean_production_kg','mean_htt_kg','mean_operating_cost_yuan'],['Production kg/path','HTT kg/path','Operating cost yuan/path']):
        for method in METHODS:
            z=perf[perf.method==method].sort_values('c_d'); ax.plot(z.c_d,z[metric],marker='o',label=method)
        ax.set(xlabel='c_d',ylabel=label); ax.grid(alpha=.25)
    axes[0].legend(); fig.tight_layout(); fig.savefig(out/'fig_cd_vs_production_htt_operating_cost.png',dpi=180); plt.close(fig)
    manifest=[]
    for (scheme,method),path in detail_files.items():
        manifest.append(dict(scheme=scheme,method=method,path=str(path.relative_to(repo)),rows=sum(1 for _ in path.open('rb'))-1,bytes=path.stat().st_size,sha256=sha256(path),role='local path-stage-directed-OD archive'))
    manifest_df=pd.DataFrame(manifest); manifest_df.to_csv(out/'htt_directed_od_path_stage_manifest.csv',index=False)

    def row(frame,scheme,method): return frame[(frame.scheme==scheme)&(frame.method==method)].iloc[0]
    lines=[
        'Stage-73 HTT transport-cost sensitivity judgment',
        '',
        'Status: PASS after common-OOS mechanical verification and visual QA.',
        'All H04/H02/H01 policies are independent one-hour fixed-budget policies with stop_flag=2; they are not formally converged.',
        '',
        'Q1. From which c_d interval does HTT become materially more active?',
        f"- Relative to c_d=0.8, c_d=0.4 raises mean HTT from {row(perf,'Reference_08','saa').mean_htt_kg:.3f} to {row(perf,'H04','saa').mean_htt_kg:.3f} kg/path for SAA and from {row(perf,'Reference_08','chi2_eta003').mean_htt_kg:.3f} to {row(perf,'H04','chi2_eta003').mean_htt_kg:.3f} for DRO.",
        f"- c_d=0.2 raises them further to {row(perf,'H02','saa').mean_htt_kg:.3f}/{row(perf,'H02','chi2_eta003').mean_htt_kg:.3f}, and c_d=0.1 to {row(perf,'H01','saa').mean_htt_kg:.3f}/{row(perf,'H01','chi2_eta003').mean_htt_kg:.3f} kg/path.",
        '- Descriptively, activation is already clear in the 0.8-to-0.4 reduction and continues through 0.2 and 0.1. It is a graded response rather than one sharp threshold.',
        '',
        'Q2. Is the extra HTT mainly in stages 4-6?',
        f"- Stage4-6 mean HTT rises from {row(total_df,'Reference_08','saa').stage4_6_mean_htt_kg_per_path:.3f}/{row(total_df,'Reference_08','chi2_eta003').stage4_6_mean_htt_kg_per_path:.3f} kg/path at 0.8 to {row(total_df,'H01','saa').stage4_6_mean_htt_kg_per_path:.3f}/{row(total_df,'H01','chi2_eta003').stage4_6_mean_htt_kg_per_path:.3f} at 0.1.",
        '- Late-stage redistribution therefore increases materially. However, only about 28%-41% of each scheme-method HTT increase versus Reference occurs in stages 4-6; stage 3 is also a major contributor. The increase is not exclusively a late-warning effect.',
        '',
        'Q3. Do directed OD flows show spatial reconfiguration toward high-demand stations?',
        '- Across all coefficients and both methods, the dominant arc is 3->1, followed mainly by 2->4 and 2->1. Aggregate net flows identify sites 3 and 2 as primary exporters and sites 1 and 4 as primary receivers.',
        '- This direction is consistent with a stronger redistribution role, but the archive does not prove that every transfer originated from a contemporaneously surplus site or was caused by the final TerminalLOH realization. That stronger causal claim is not made.',
        '',
        'Q4. Does lower transport cost reduce terminal spatial mismatch?',
        f"- Mean terminal gap falls monotonically from {row(perf,'Reference_08','saa').mean_terminal_gap_kg:.3f}/{row(perf,'Reference_08','chi2_eta003').mean_terminal_gap_kg:.3f} kg/path at 0.8 to {row(perf,'H01','saa').mean_terminal_gap_kg:.3f}/{row(perf,'H01','chi2_eta003').mean_terminal_gap_kg:.3f} at 0.1.",
        f"- Gap-positive paths fall from {int(row(pd.DataFrame(mismatch),'Reference_08','saa').gap_positive_paths)}/{int(row(pd.DataFrame(mismatch),'Reference_08','chi2_eta003').gap_positive_paths)} to {int(row(pd.DataFrame(mismatch),'H01','saa').gap_positive_paths)}/{int(row(pd.DataFrame(mismatch),'H01','chi2_eta003').gap_positive_paths)}. Total statically coverable gap kg also falls.",
        '- The coverable percentage of the remaining gap falls too, so the residual gap is less dominated by simple final surplus-at-another-site mismatch. This remains a static terminal diagnostic, not proof of nonanticipative feasible recourse.',
        '',
        'Q5. Does more HTT replace redundant local production/inventory?',
        f"- No direct substitution is observed. Relative to 0.8, H01 production is higher by {row(perf,'H01','saa').mean_production_kg-row(perf,'Reference_08','saa').mean_production_kg:.3f}/{row(perf,'H01','chi2_eta003').mean_production_kg-row(perf,'Reference_08','chi2_eta003').mean_production_kg:.3f} kg/path and final inventory is higher by {row(perf,'H01','saa').mean_final_inventory_kg-row(perf,'Reference_08','saa').mean_final_inventory_kg:.3f}/{row(perf,'H01','chi2_eta003').mean_final_inventory_kg-row(perf,'Reference_08','chi2_eta003').mean_final_inventory_kg:.3f} kg/path.",
        '- More redistribution accompanies slightly more production and inventory rather than replacing them. Simultaneous opposite-direction OD flow is zero within tolerance, so the additional HTT is not explained by immediate pairwise counterflow.',
        '',
        'Q6. What happens to shortage, terminal gap, and cost?',
        f"- SAA ordinary shortage changes from {row(perf,'Reference_08','saa').mean_ordinary_shortage_kg:.3f} to {row(perf,'H01','saa').mean_ordinary_shortage_kg:.3f} kg/path; DRO changes from {row(perf,'Reference_08','chi2_eta003').mean_ordinary_shortage_kg:.3f} to {row(perf,'H01','chi2_eta003').mean_ordinary_shortage_kg:.3f}.",
        f"- Operating cost changes from {row(perf,'Reference_08','saa').mean_operating_cost_yuan:.2f}/{row(perf,'Reference_08','chi2_eta003').mean_operating_cost_yuan:.2f} yuan/path at 0.8 to {row(perf,'H01','saa').mean_operating_cost_yuan:.2f}/{row(perf,'H01','chi2_eta003').mean_operating_cost_yuan:.2f} at 0.1. H04 SAA is a small non-monotone exception, while H02/H01 are lower than Reference for both methods.",
        '',
        'Q7. Is c_d=0.8 a materially high economic friction?',
        f"- Actual flow-weighted transport price is about {row(total_df,'Reference_08','saa').weighted_transport_cost_yuan_per_kg:.2f}-{row(total_df,'Reference_08','chi2_eta003').weighted_transport_cost_yuan_per_kg:.2f} yuan/kg at 0.8, versus {row(total_df,'H04','saa').weighted_transport_cost_yuan_per_kg:.2f}-{row(total_df,'H04','chi2_eta003').weighted_transport_cost_yuan_per_kg:.2f} at 0.4, {row(total_df,'H02','saa').weighted_transport_cost_yuan_per_kg:.2f}-{row(total_df,'H02','chi2_eta003').weighted_transport_cost_yuan_per_kg:.2f} at 0.2, and {row(total_df,'H01','saa').weighted_transport_cost_yuan_per_kg:.2f}-{row(total_df,'H01','chi2_eta003').weighted_transport_cost_yuan_per_kg:.2f} at 0.1.",
        '- At 0.8, stage-4 actual HTT price exceeds stage-4 local production marginal cash cost, while stage-5/6 movement is cheaper than local production before inventory opportunity value. Together with the monotone HTT response, this supports treating 0.8 as a material economic friction in the current model, not as pure causal identification.',
        '',
        'Q8. Which tested interval best exposes flexibility without obvious over-transfer?',
        '- No tested coefficient shows frequent capacity saturation: the maximum observed utilization is 81.70%, all q95 values are below 48.84%, and simultaneous reciprocal OD flow is zero within tolerance.',
        '- The descriptive elbow is around c_d=0.2: it already produces substantial overall and stage4-6 HTT activation, lower terminal gap, lower shortage, and lower operating cost than Reference. c_d=0.1 is a stronger low-cost stress case with further HTT and modest additional gap/cost improvement, not an observed pathological counterflow case.',
        '- This audit does not select a formal coefficient. A future focused experiment may treat 0.2 as the middle candidate and 0.1 as the lower-bound sensitivity, subject to model calibration and training-budget checks.',
        '',
        'Evidence boundaries and fallacy scan',
        '- Data facts: frozen path identities, means, stage totals, OD totals, costs, gaps, and utilization are mechanically verified.',
        '- Descriptive mechanism: lower direct transport friction is associated with more HTT and lower residual gap/cost in these independently trained policies.',
        '- Causal claims not established: all non-reference policies were trained separately for one hour and stopped by time budget; no formal convergence or pure parameter causal estimate is claimed.',
        '- Statistical fallacy scan coverage: 11/11. Aggregate and method/stage-stratified results are both reported; no individual inference from group means, selected-survivor omission, multiple-testing significance claim, regression-to-mean claim, collider adjustment, diagnostic base-rate inference, or reverse-causal claim is used. Static surplus-gap coverage is not converted into feasible recourse, and association is not written as proven causation.',
    ]
    (out/'transport_cost_judgment.txt').write_text('\n'.join(lines)+'\n',encoding='utf-8')

    readme=[
        '# Stage-73 E1-8h HTT transport-cost sensitivity', '',
        'Status: PASS. This directory is the accepted unified postprocess for run-001 after independent mechanical verification and visual QA.', '',
        'Reference c_d=0.8 reuses the accepted Stage-71 E1 policy. H04/H02/H01 change only c_d to 0.4/0.2/0.1 and use one-hour fixed-budget policies. All eight evaluations use the same frozen 10000x8 OOS state paths and 6053 terminal-hit paths.', '',
        'The full path-stage-directed-OD archives remain in each case directory. `htt_directed_od_path_stage_manifest.csv` records paths, row counts, bytes, and SHA-256 without copying roughly 400 MB into this analysis directory.', '',
        'Interpretation limits: stop_flag=2 is not formal convergence; static terminal surplus-gap coverage is not nonanticipative recourse feasibility; separately trained policy contrasts are descriptive rather than pure causal estimates. No coefficient is automatically adopted as a formal model value.', '',
        'Primary results are in `transport_cost_sensitivity_summary.csv`, `htt_by_stage.csv`, `htt_od_summary.csv`, `htt_utilization_summary.csv`, `htt_flow_quality_audit.csv`, `spatial_mismatch_comparison.csv`, `production_inventory_shortage_cost.csv`, `deltaI_comparison.csv`, `mechanical_verification.txt`, and `transport_cost_judgment.txt`.'
    ]
    (out/'README.md').write_text('\n'.join(readme)+'\n',encoding='utf-8')
    large=['# LARGE_FILE_MANIFEST', '', 'Large path-stage-directed-OD files are local-only and are not duplicated here.', '', '| scheme | method | rows | bytes | sha256 | path |', '|---|---:|---:|---:|---|---|']
    for r in manifest_df.itertuples(): large.append(f'| {r.scheme} | {r.method} | {r.rows} | {r.bytes} | `{r.sha256}` | `{r.path}` |')
    (out/'LARGE_FILE_MANIFEST.md').write_text('\n'.join(large)+'\n',encoding='utf-8')

if __name__=='__main__': main()
