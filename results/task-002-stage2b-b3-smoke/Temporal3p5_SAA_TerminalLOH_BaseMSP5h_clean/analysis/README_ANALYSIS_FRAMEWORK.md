# Analysis framework

The MATLAB and Python files under this directory are reusable source programs.
`run_candidate_oos_analysis.py` reads paired Base/candidate OOS roots supplied
by the caller and writes C-mode control card, paired KPI/CI, target-group,
time-formation, mechanism, tail/cost, historical-issue, coverage, ledger,
communication and data-preservation outputs. `run_candidate_oos_closeout.py`
performs the final artifact gate. Training status and evidence are read from
candidate metadata when supplied; no stability or convergence label is fixed
in this template. No historical analysis output is included.
