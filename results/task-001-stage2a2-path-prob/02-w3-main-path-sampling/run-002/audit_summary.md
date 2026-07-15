# W3 Main Path Sampling Convergence Audit

- task_id: `task-001`
- step_id: `02-w3-main-path-sampling`
- run_id: `run-002`
- status: `PASS`
- MATLAB command: `cd('C:/Users/chaos/Desktop/biye/test/testH2_v2'); run('terminalLoh_wdro/src/run_stage2a2_W3_path_sampling_convergence_h2.m');`
- PASS count: 15
- FAIL count: 0

## Design

- initial states: a0=2:6, loc0=1:7, lfw0=0 (35 states).
- N candidates: 15000, 20000, 30000.
- convergence seeds: 20260721, 20260722, 20260723, 20260724, 20260725.
- each seed/state generates 30000 paths once; N candidates use nested prefixes.
- exact W1-W3 distributions use transition-matrix multiplication.

## Convergence

- N=15000: p95 max error 0.0074; worst max error 0.0154717; mean joint TV 0.0296189; pass=1.
- N=20000: p95 max error 0.00643333; worst max error 0.014045; mean joint TV 0.02561; pass=1.
- N=30000: p95 max error 0.00549613; worst max error 0.0121283; mean joint TV 0.0208151; pass=1.

## Transition Frequency Check

- audit N: 15000.
- intensity: max probability error 0.000624601; p95 error 0.000580238; mean row TV 0.000319661; minimum from-state count 263841.
- loc: max probability error 0.00206671; p95 error 0.000880873; mean row TV 0.00125504; minimum from-state count 54710.
- lfw: max probability error 0.000500771; p95 error 0.000500771; mean row TV 0.000244504; minimum from-state count 78586.

- recommended N: 15000 per initial state.
- main sample seed: 20260706; main sample rows: 525000.

## Coordinates and Scope

- y = -89.9999703886000 + lfw * 40.
- x uses the existing NearStageInput loc layout and halo extrapolation.
- candidate matrices unchanged during run: 1.
- run-001 output unchanged during run: 1.
- ordinary probability sampling only; no risk screening or tail enrichment.
- formal path generator, B3, WDRO, Gurobi, MSP, Foundation, and Persistence were not run.
