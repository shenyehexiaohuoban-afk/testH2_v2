# Stage 2B2 W=3 D/A/C Samples R200

## Goal

Stage 2B2 expands the Stage 2B1 smoke-test consequence generation to medium samples. It generates D/A/C samples and diagnostics only. It does not run WDRO-LP, call Gurobi, connect to MSP, or write TerminalLOH.

## Project Stage Structure

- Stage 1: single-window DA/DAC WDRO prototype.
- Stage 2A: W=3 look-ahead typhoon path generation.
- Stage 2B1: W=3 small-sample D/A/C smoke test.
- Stage 2B2: W=3 R=200 D/A/C consequence generation and diagnostics.
- Stage 2C: future W=3 DA-WDRO run using B2 outputs.

## Inputs

- `C:\Users\chaos\Desktop\biye\test\testH2_v2\terminalLoh_wdro\output\stage2_lookahead_W3\lookahead_path_table.csv`
- `C:\Users\chaos\Desktop\biye\test\testH2_v2\terminalLoh_wdro\config\lookahead_window_W3.csv`
- `C:\Users\chaos\Desktop\biye\test\testH2_v2\terminalLoh_wdro\config\lookahead_location_W3.csv`
- `C:\Users\chaos\Desktop\biye\test\testH2_v2\terminalLoh_wdro\config\lookahead_intensity_W3.csv`

## Sample Size

- `P_B2=20`: selected W=3 paths per lf=7 state.
- `M_B2=10`: damage samples per selected path.
- `R_B2=200`: D/A/C consequence scenarios per state.
- `random_seed_B2=20260708`.

If a state has exactly `P_B2` available paths, all are used. If it has more, paths are selected by fixed-seed random sampling and sorted before scenario generation.

## D/A/C Definitions

- `D`: W=3 cumulative node hydrogen demand, `D_n=sum_tau D_{n,tau}`.
- `A`: binary site-node reachability. `A=1` means a feasible service path exists; `A=0` means fully unreachable.
- `C`: current road-state shortest path service cost `dist(n)` from Dijkstra after sampled slowdowns and closures.

`A` is never used for partial reachability. Reachable but slow roads keep `A=1` and are represented by larger `C`. The formal `C` field does not use `baseCost + dist(n)`; that before-fix value is diagnostic only.

## Outputs

Output directory: `C:\Users\chaos\Desktop\biye\test\testH2_v2\terminalLoh_wdro\output\stage2_lookahead_W3_B2_DAC_samples_R200`

- `lookahead_scenario_site_node.csv`
- `lookahead_scenario_summary.csv`
- `lookahead_D_total_distribution_summary.csv`
- `lookahead_reachability_summary.csv`
- `lookahead_cost_summary.csv`
- `implementation_audit_B2.txt`
- `README_B2_DAC_samples_R200.txt`

## Why B2 Still Does Not Run WDRO

B2 is a data generation and diagnostic gate. It verifies D/A/C dimensions, binary reachability, finite reachable costs, unreachable masking behavior, and demand tail diagnostics before Stage 2C consumes the samples for DA-WDRO.

## Stage 2C Interface

Stage 2C should read `lookahead_scenario_site_node.csv` and use `D_node_kg_s`, `reachable`, and `scenario_service_cost` as the DA sample inputs. Unreachable `C=Inf` entries must be ignored by masked-C diagnostics and must not enter reachable cost statistics.
