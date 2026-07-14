# Stage 2B1 W=3 D/A/C Smoke Samples

## Goal

Generate small W=3 look-ahead consequence samples for WDRO-TerminalLOH data-interface checks. This stage does not run WDRO-LP and does not connect to MSP.

## Sample Size

- `P_B1=10`: selected typhoon paths per lf=7 state.
- `M_B1=3`: damage samples per selected path.
- `R_B1=30`: D/A/C consequence scenarios per state.

The current implementation uses the first `P_B1` path ids from the Stage 2A path table for each state and samples damage with seed `20260707`.

This first-path selection is only a smoke-test choice. It should not be used as a formal paper sampling design; Stage B2 should switch to fixed-seed random sampling or stratified sampling.

## B1 Simplifications

- Uses the existing preview wind/grid/road Monte Carlo structure and fragility functions.
- Uses the existing Vmax/Rmax mapping and Rmax probabilities `[0.3,0.5,0.2]` from the offline preview prototype.
- Reads site/node counts from `load_data_h2_near` (`params.Ni=4`, `params.Nj=33` in the current data), rather than inventing dimensions.
- Uses first-path selection only for smoke testing. Formal B2 sampling should use fixed-seed random sampling or stratified sampling.
- B1 outputs are not formal paper numerical results.

## D/A/C Definitions

- `D`: node hydrogen demand aggregated over tau=1:W.
- `A`: binary 4-site by 33-node reachability. `A=1` means a feasible service path exists; `A=0` means fully unreachable.
- `C`: reachable service cost / travel impedance / travel time.

`C` is the current road-state shortest path cost returned by Dijkstra on edge times after slowdown and closures. It is not `baseCost + currentCost`; the earlier B1 duplicate-base formula has been fixed, and before/after C diagnostics are written.

Reachable but slow road conditions, such as flooding, congestion, fallen trees, detours, or speed limits, are represented by `A=1` with larger `C`. Fractional reachability values such as `A=0.3` are not used.

## W=3 Aggregation

- `D_n = sum_tau D_{n,tau}`.
- `A_i,n=1` only if all critical demand windows for node `n` are reachable from site `i`; otherwise `A_i,n=0`.
- If `A_i,n=1`, `C_i,n` is the mean reachable-window service cost. If `A_i,n=0`, `C_i,n=Inf`.

## Outputs

Output directory: `C:\Users\chaos\Desktop\biye\test\testH2_v2\terminalLoh_wdro\output\stage2_lookahead_W3_B1_DAC_samples`

- `lookahead_scenario_site_node.csv`
- `lookahead_scenario_summary.csv`
- `lookahead_D_total_distribution_summary.csv`
- `lookahead_reachability_summary.csv`
- `lookahead_cost_summary.csv`
- `README_B1_DAC_samples.txt`

## Next Step

Stage B2 should expand the scenario count, for example to R=200 or R=500 per state, before running WDRO on W=3 consequence samples.
