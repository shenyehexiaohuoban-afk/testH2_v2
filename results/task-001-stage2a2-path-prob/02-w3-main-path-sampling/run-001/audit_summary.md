# W3 Main Path Sampling Convergence Audit

- task_id: `task-001`
- step_id: `02-w3-main-path-sampling`
- run_id: `run-001`
- status: `PASS`
- MATLAB command: `cd('C:/Users/chaos/Desktop/biye/test/testH2_v2'); run('terminalLoh_wdro/src/run_stage2a2_W3_path_sampling_convergence_h2.m');`
- PASS count: 11
- FAIL count: 0

## Design

- initial states: a0=2:6, loc0=1:7, lfw0=0 (35 states).
- N candidates: 500, 1000, 2000, 5000, 10000.
- convergence seeds: 20260721, 20260722, 20260723, 20260724, 20260725.
- each seed/state generates 10000 paths once; N candidates use nested prefixes.
- exact W1-W3 distributions use transition-matrix multiplication.

## Convergence

- N=500: p95 max error 0.0408; worst max error 0.076; mean joint TV 0.156715; pass=0.
- N=1000: p95 max error 0.03004; worst max error 0.051; mean joint TV 0.111973; pass=0.
- N=2000: p95 max error 0.0205; worst max error 0.036005; mean joint TV 0.0795619; pass=0.
- N=5000: p95 max error 0.0133; worst max error 0.023497; mean joint TV 0.0508741; pass=0.
- N=10000: p95 max error 0.0094; worst max error 0.0163; mean joint TV 0.0359743; pass=0.

- recommended N: none; criteria were not relaxed.

## Coordinates and Scope

- y = -89.9999703886000 + lfw * 40.
- x uses the existing NearStageInput loc layout and halo extrapolation.
- candidate matrices unchanged during run: 1.
- ordinary probability sampling only; no risk screening or tail enrichment.
- formal path generator, B3, WDRO, Gurobi, MSP, Foundation, and Persistence were not run.
