# Observed W3 Tail-Risk and Probability-Mass Coverage Audit

- task_id: `task-001`
- step_id: `03-stage2b-tail-candidate-design`
- run_id: `run-001`
- status: `PASS`; PASS=20; FAIL=0.
- MATLAB command: `cd('C:/Users/chaos/Desktop/biye/test/testH2_v2'); run('terminalLoh_wdro/src/run_stage2b_observed_tail_coverage_audit_h2.m');`

## Coverage

- observed unique paths: 256884.
- theoretical mass coverage range: 0.588788683701 to 0.789271202401.
- path-count coverage range: 0.0101094767279 to 0.0174146283824.

## Equal-State Tail Quantiles

- grid_max_wind_mps: q95=39.5430207, q99=43.1841934, q99.5=47.2251991.
- grid_cumulative_excess_mps: q95=641.088195, q99=878.515831, q99.5=989.135725.
- road_max_wind_mps: q95=39.5430207, q99=43.1841934, q99.5=47.2251991.
- road_cumulative_excess_mps: q95=477.064491, q99=702.853029, q99.5=811.707499.
- grid_longest_consecutive_exceedance_windows: q95=2.2, q99=2.57142857, q99.5=2.71428571.
- road_longest_consecutive_exceedance_windows: q95=1.77142857, q99=2.17142857, q99.5=2.37142857.

- high-exposure long rows: 340173.
- Pareto long rows: 895.
- risk model: Rmax_ref=40, wind decay B=0.6, point-to-segment distances.
- empirical weights are frequency/15000; path_probability is not an empirical weight.
- no resampling, supplemental paths, B3, WDRO, Gurobi, or MSP.
