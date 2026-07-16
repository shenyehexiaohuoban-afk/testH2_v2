# Corrected Observed W3 Tail Candidate Screening

- task_id: `task-001`
- step_id: `03-stage2b-tail-candidate-design`
- run_id: `run-002`
- status: `PASS`; PASS=20; FAIL=0.
- MATLAB command: `cd('C:/Users/chaos/Desktop/biye/test/testH2_v2'); run('terminalLoh_wdro/src/run_stage2b_correct_observed_tail_screening_h2.m');`

## Four-Proxy Combined Candidates

- q95.0: high-risk paths=23510; boundary paths=5541; Pareto paths=268; equal-state mean empirical mass=0.0831257143.
- q99.0: high-risk paths=7316; boundary paths=2387; Pareto paths=239; equal-state mean empirical mass=0.0212114286.
- q99.5: high-risk paths=4310; boundary paths=1497; Pareto paths=215; equal-state mean empirical mass=0.010767619.

## Per-Proxy Counts

- grid_max_wind_mps q95.0: selected=20170; strict=15024; boundary=5146; Pareto=117.
- grid_max_wind_mps q99.0: selected=5747; strict=3498; boundary=2249; Pareto=104.
- grid_max_wind_mps q99.5: selected=3322; strict=1909; boundary=1413; Pareto=92.
- grid_cumulative_excess_mps q95.0: selected=14950; strict=14881; boundary=69; Pareto=182.
- grid_cumulative_excess_mps q99.0: selected=4030; strict=3927; boundary=103; Pareto=155.
- grid_cumulative_excess_mps q99.5: selected=2191; strict=2138; boundary=53; Pareto=135.
- road_max_wind_mps q95.0: selected=20170; strict=15024; boundary=5146; Pareto=117.
- road_max_wind_mps q99.0: selected=5747; strict=3498; boundary=2249; Pareto=104.
- road_max_wind_mps q99.5: selected=3322; strict=1909; boundary=1413; Pareto=92.
- road_cumulative_excess_mps q95.0: selected=13675; strict=13289; boundary=386; Pareto=188.
- road_cumulative_excess_mps q99.0: selected=3823; strict=3726; boundary=97; Pareto=163.
- road_cumulative_excess_mps q99.5: selected=2262; strict=2145; boundary=117; Pareto=146.

- q99.5 subset q99 subset q95: required and audited.
- risk must be positive; zero-risk paths are excluded even when q=0.
- empirical mass is frequency/15000; path_probability is Pareto-only.
- no wind recomputation, resampling, full legal-path search, B3, WDRO, Gurobi, or MSP.
