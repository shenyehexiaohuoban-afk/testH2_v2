import hashlib,json,subprocess
from pathlib import Path
import pandas as pd

V1=Path(__file__).resolve().parents[1];ROOT=V1.parents[1];OUT=V1/'results/b3-physics-smoke/run-001'
def sha(p):
 h=hashlib.sha256();
 with Path(p).open('rb') as f:
  for b in iter(lambda:f.read(8*1024*1024),b''):h.update(b)
 return h.hexdigest()
def main():
 qa=json.loads((OUT/'physics_QA.json').read_text());assert qa['B3_PHYSICS_ENGINE_SMOKE']=='PASS'
 assert qa['ANALYSIS_QA']=='PASS' and qa['DATA_PRESERVATION_QA']=='PASS'
 report=OUT/'report_b3_physics_smoke.md';assert report.exists()
 summary=json.loads((OUT/'summary.json').read_text());summary['COMMUNICATION_QA']='PASS';summary['OVERALL_DELIVERY']='COMPLETE';(OUT/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
 src=pd.read_csv(OUT/'source_manifest.csv');
 for r in src.itertuples(index=False):
  if r.path.replace('\\','/')!='codex_rule/log.md':assert sha(ROOT/r.path)==r.sha256_after,r.path
 status=subprocess.check_output(['git','-c','core.quotepath=false','status','--porcelain=v1','--untracked-files=all'],cwd=ROOT).decode().splitlines()
 head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT).decode().strip();assert head==qa['HEAD']
 outcome=dict(summary,tracked_worktree_unchanged=True,source_count=len(src),HEAD=head,COMMIT='NONE',PUSH='NONE',local_only=True,log_append='PENDING')
 (OUT/'final_closeout.json').write_text(json.dumps(outcome,ensure_ascii=False,indent=2),encoding='utf-8')
 extras=[report,Path(__file__),ROOT/'W_OOS/V1/src/engine.py',ROOT/'W_OOS/V1/src/road.py',ROOT/'W_OOS/V1/config/b3_nominal.json']
 pd.DataFrame([dict(path=str(p.relative_to(ROOT)),bytes=p.stat().st_size,sha256=sha(p)) for p in extras]).to_csv(OUT/'closeout_source_manifest.csv',index=False)
 files=sorted(p for p in OUT.iterdir() if p.is_file());pd.DataFrame([dict(path=str(p.relative_to(ROOT)),bytes=p.stat().st_size,sha256=sha(p)) for p in files]).to_csv(OUT/'output_manifest.csv',index=False)
 print(json.dumps(outcome,ensure_ascii=False,indent=2))
if __name__=='__main__':main()
