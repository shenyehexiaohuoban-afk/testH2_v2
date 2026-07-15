# Fixed-Seed W3 Main Path Sample Audit

- task_id: `task-001`
- step_id: `02-w3-main-path-sampling-fixed-seed-audit`
- run_id: `run-003`
- status: `PASS`
- MATLAB command: `cd('C:/Users/chaos/Desktop/biye/test/testH2_v2'); run('terminalLoh_wdro/src/run_stage2a2_W3_fixed_seed_sample_audit_h2.m');`
- PASS count: 18
- FAIL count: 0

## Fixed Sample

- seed: 20260706; rows: 525000; initial states: 35.
- samples per initial state: 15000; empirical weight: 6.66666666666667e-05.
- path_probability is audit-only and is not used as an empirical weight.

## Acceptance Metrics

- p95 maximum absolute error: 0.00806666666667.
- worst maximum absolute error: 0.0131333333333.
- mean joint-state TV: 0.02954596508.
- nonconfigured stage transition records: 0.
- path_probability recomputation max error: 4.98732999343e-18.

## Integrity and Scope

- source sample unchanged: 1.
- candidate matrices unchanged: 1.
- no resampling, B3, tail supplementation, WDRO, Gurobi, or MSP.
