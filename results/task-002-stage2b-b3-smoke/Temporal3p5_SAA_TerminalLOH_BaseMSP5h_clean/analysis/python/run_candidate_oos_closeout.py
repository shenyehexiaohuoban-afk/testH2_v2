"""Candidate-agnostic closeout wrapper for a completed analysis directory."""
from __future__ import annotations
import argparse
from pathlib import Path

def main() -> None:
    ap=argparse.ArgumentParser(); ap.add_argument('--analysis-root',type=Path,required=True); a=ap.parse_args()
    required=['analysis_control_card.md','C_mode_coverage_matrix.csv','issue_by_issue_result_ledger.csv','communication_qa.csv','data_preservation_qa.csv']
    missing=[x for x in required if not (a.analysis_root/x).is_file()]
    (a.analysis_root/'C_MODE_CLOSEOUT.txt').write_text('status='+('PASS' if not missing else 'FAIL')+'\nmissing='+','.join(missing)+'\n',encoding='utf-8')
    if missing: raise SystemExit('Missing closeout artifacts: '+', '.join(missing))

if __name__=='__main__': main()
