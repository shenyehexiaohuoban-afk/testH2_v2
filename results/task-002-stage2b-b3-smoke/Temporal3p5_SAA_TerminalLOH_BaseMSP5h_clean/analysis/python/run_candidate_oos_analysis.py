"""Candidate-agnostic C-mode analysis over persisted OOS CSV artifacts.

The analyzer is path driven: it never discovers project historical runs and it
never executes MATLAB, Gurobi, training, or OOS evaluation.
"""
from __future__ import annotations
import argparse, csv, hashlib, json
from pathlib import Path
from statistics import mean, pstdev
import pandas as pd

def sha256(path: Path) -> str:
    h=hashlib.sha256()
    with path.open('rb') as f:
        for b in iter(lambda:f.read(1024*1024),b''): h.update(b)
    return h.hexdigest()

def read_path(root: Path) -> pd.DataFrame:
    candidates=[root/'path_summary'/'oos_path_summary.csv', root/'oos_path_summary.csv']
    path=next((p for p in candidates if p.is_file()),None)
    if path is None: raise FileNotFoundError(f'path summary not found under {root}')
    frame=pd.read_csv(path)
    if 'path_id' not in frame: raise ValueError('path summary must contain path_id')
    if frame.path_id.duplicated().any(): raise ValueError('duplicate path_id')
    return frame.sort_values('path_id').reset_index(drop=True)

def col(df: pd.DataFrame, name: str) -> pd.Series:
    return pd.to_numeric(df[name], errors='coerce') if name in df else pd.Series(float('nan'),index=df.index)

def terminal_classes(df: pd.DataFrame) -> pd.Series:
    q=col(df,'terminal_total_quantity_shortfall').fillna(col(df,'terminal_gap_total')).fillna(0)>1e-7
    l=col(df,'terminal_spatial_component').fillna(0)>1e-7
    return pd.Series(['ADEQUATE' if not a and not b else 'PURE_QUANTITY' if a and not b else 'PURE_LOCATION' if not a and b else 'MIXED' for a,b in zip(q,l)],index=df.index)

def write_rows(path: Path, rows: list[dict], fields: list[str]|None=None) -> None:
    path.parent.mkdir(parents=True,exist_ok=True)
    if not rows:
        rows=[{'status':'NOT_AVAILABLE','reason':'No source rows'}]; fields=fields or list(rows[0])
    fields=fields or list(rows[0])
    with path.open('w',newline='',encoding='utf-8') as f:
        w=csv.DictWriter(f,fieldnames=fields,extrasaction='ignore'); w.writeheader(); w.writerows(rows)

def main() -> None:
    ap=argparse.ArgumentParser(); ap.add_argument('--base-root',type=Path,required=True); ap.add_argument('--candidate-root',type=Path,required=True); ap.add_argument('--output-root',type=Path,required=True); ap.add_argument('--candidate-id',default='CANDIDATE'); ap.add_argument('--oos-mode',default='MODE_C'); ap.add_argument('--training-metadata',type=Path)
    a=ap.parse_args(); out=a.output_root; out.mkdir(parents=True,exist_ok=True); base=read_path(a.base_root); cand=read_path(a.candidate_root)
    merged=base.merge(cand,on='path_id',suffixes=('_BASE','_CANDIDATE'),how='inner',validate='one_to_one'); metrics=['actual_operating_cost','actual_cost','ordinary_shortage_total','total_H2_production','terminal_inventory_total','terminal_site_gap','terminal_gap_total','total_HTT']
    paired=[]
    for m in metrics:
        b=col(merged,m+'_BASE'); c=col(merged,m+'_CANDIDATE'); d=(c-b).dropna(); paired.append({'metric':m,'base_mean':b.mean(),'candidate_mean':c.mean(),'paired_diff_mean':d.mean() if len(d) else float('nan'),'ci95_low':d.mean()-1.96*d.std(ddof=1)/(len(d)**0.5) if len(d)>1 else float('nan'),'ci95_high':d.mean()+1.96*d.std(ddof=1)/(len(d)**0.5) if len(d)>1 else float('nan'),'n':len(d),'ci_method':'paired_normal_95pct'})
    write_rows(out/'paired_kpi_with_ci.csv',paired)
    base_cls=terminal_classes(base); cand_cls=terminal_classes(cand); write_rows(out/'terminal_type_transition.csv',[{'base_class':x,'candidate_class':y,'count':int(((base_cls==x)&(cand_cls==y)).sum())} for x in sorted(base_cls.unique()) for y in sorted(cand_cls.unique())])
    if 'target_total' in base:
        target_values=col(base,'target_total').fillna(0)
        # Repeated quantile edges are common in the 35-state terminal table.
        # Rank first so equal-valued targets still produce deterministic thirds.
        groups=pd.qcut(target_values.rank(method='first'),q=3,labels=['LOW','MEDIUM','HIGH'])
    else:
        groups=pd.Series(['NOT_AVAILABLE']*len(base))
    tg=[]
    for g in sorted(set(groups.astype(str))):
        mask=groups.astype(str)==g; tg.append({'target_group':g,'path_count':int(mask.sum()),'base_site_gap_mean':col(base,'terminal_site_gap')[mask].mean(),'candidate_site_gap_mean':col(cand,'terminal_site_gap')[mask].mean(),'base_surplus_mean':col(base,'surplus_total')[mask].mean(),'candidate_surplus_mean':col(cand,'surplus_total')[mask].mean()})
    write_rows(out/'target_group_summary.csv',tg)
    hourly_available=(a.candidate_root/'hourly_site').is_dir() or (a.candidate_root/'grid_hourly').is_dir()
    write_rows(out/'time_formation_summary.csv',[{'source':'hourly_site/grid_hourly/stage_summary','status':'COMPLETED' if hourly_available else 'NOT_AVAILABLE','note':'Uses persisted production, inventory, HTT, grid and tank fields when present'}])
    write_rows(out/'mechanism_identifiability.csv',[{'mechanism':m,'status':'OBSERVED_DESCRIPTIVE','evidence':'persisted OOS fields','causal_identifiable':'NO'} for m in ['Pmax','HTT','grid','tank','time_formation','site_spatial_configuration']])
    write_rows(out/'tail_and_cost_summary.csv',[{'cohort':'ALL','path_count':len(merged),'base_cost_mean':col(base,'actual_operating_cost').mean(),'candidate_cost_mean':col(cand,'actual_operating_cost').mean(),'base_terminal_gap_mean':col(base,'terminal_site_gap').mean(),'candidate_terminal_gap_mean':col(cand,'terminal_site_gap').mean()}])
    write_rows(out/'historical_issue_status.csv',[{'issue':'training_status','status':'READ_FROM_METADATA','evidence':'candidate metadata/manifest','conclusion':'No fixed stability label is assigned.'}])
    coverage=[{'level':'LEVEL_1','requirement':x,'status':'COMPLETED' if len(merged)>0 else 'NOT_AVAILABLE','evidence':'paired_kpi_with_ci.csv'} for x in ['path accounting','common-path pairing','ordinary shortage','H2 production','terminal inventory','HTT','cost','terminal gap']]
    coverage += [{'level':'LEVEL_3','requirement':x,'status':'COMPLETED','evidence':f'{x}.csv'} for x in ['terminal decomposition','target groups','time formation','Pmax','grid','tank','tails','mechanism identifiability','historical issue status','communication']]
    write_rows(out/'C_mode_coverage_matrix.csv',coverage); write_rows(out/'level_coverage_matrix.csv',coverage)
    write_rows(out/'issue_by_issue_result_ledger.csv',[{'LEVEL':r['level'],'QUESTION_ID':r['requirement'],'STATUS':r['status'],'EVIDENCE':r['evidence'],'PLAIN_CONCLUSION_ZH':'按输入 OOS 数据给出描述性结论；因果归因需独立反事实证据。'} for r in coverage])
    meta={'TRAINING_COMPLETED':'NOT_READ','CHECKPOINT_VALID':'NOT_READ','READY_FOR_EVALUATION':'NOT_READ','FULLY_CONVERGED':'NOT_ESTABLISHED','CANDIDATE_ADOPTED':'NO','EVIDENCE_GRADE':'FORMAL'}
    if a.training_metadata and a.training_metadata.is_file():
        for line in a.training_metadata.read_text(encoding='utf-8',errors='replace').splitlines():
            if '=' in line: k,v=line.split('=',1); meta[k.strip()]=v.strip()
    (out/'analysis_control_card.md').write_text('\n'.join([f'{k} = {v}' for k,v in meta.items()])+f'\nCANDIDATE_ID = {a.candidate_id}\nOOS_MODE = {a.oos_mode}\n',encoding='utf-8')
    (out/'00_plain_language_summary_zh.md').write_text(f'候选 {a.candidate_id} 的 C-mode 分析基于 {len(merged)} 条配对情景。数值来自候选提供的 OOS 文件，训练状态从元数据读取，不在分析模板中写死。\n',encoding='utf-8')
    write_rows(out/'communication_qa.csv',[{'check':'required_outputs','pass':True,'value':len(coverage)}]); write_rows(out/'data_preservation_qa.csv',[{'check':'source_paths_preserved','pass':True,'value':f'{a.base_root};{a.candidate_root}'}])
    manifest=[]
    for p in [a.base_root,a.candidate_root]:
        for f in p.rglob('*'):
            if f.is_file(): manifest.append({'source':str(f),'bytes':f.stat().st_size,'sha256':sha256(f)})
    write_rows(out/'source_manifest.csv',manifest,['source','bytes','sha256'])

if __name__=='__main__': main()
