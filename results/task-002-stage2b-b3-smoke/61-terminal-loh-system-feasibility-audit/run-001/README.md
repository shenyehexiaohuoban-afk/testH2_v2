# Step-05B-4 TerminalLOH system feasibility audit

This accepted read-only audit separates three questions that must not be conflated:

1. **System-total supply:** can the four-station system retain the DRO total target while serving the ordinary H2 load actually served by the saved DRO policy?
2. **Physical spatial feasibility:** when total supply is sufficient, can the original beta-dependent HTT and station constraints place enough inventory at every target station before the terminal event?
3. **Saved-policy realization:** did the existing fixed one-hour policy actually retain and allocate the required inventory?

## Inputs and integrity

- Frozen Git baseline: `06f10864f36a6358eb671632ce3e032ddf0ae97e` on `task/002-stage2b-b3-smoke`.
- Saved SAA and eta=0.03 policies: Step-05B `run-003`.
- Common OOS table: `output_h2/details/h2_OOS.csv`, SHA-256 `6e4ed488423e3cbb838c4a6f8b45019cf4ecf32a82850880399a08aafc7aff85`.
- Focus states: 12, 16, 17, 18, 19; reference states: 13, 14.
- Selected terminal-hit paths: 649. Both saved-policy replays reproduce archived final inventory to at most `5.12e-13`; terminal-state mismatch count is zero.
- Diagnostic LPs: 1298/1298 OPTIMAL; maximum conservation residual `4.97e-14` and maximum target/gap reconstruction residual below `6.3e-13`.

## Diagnostic classification

- **A:** system-total hydrogen is insufficient under the preserved physical constraints and fixed ordinary service.
- **B:** system total is sufficient, but the original HTT/site constraints cannot realize all station targets.
- **C:** system total and spatial placement are physically feasible, but the saved policy does not necessarily realize them; inspect cuts, value signals, and actual HTT allocation.
- **D:** system-total insufficiency and an additional spatial impediment coexist.
- **E:** solver/data evidence is insufficient.

Observed path counts are A=226, C=423, with B=D=E=0. The absence of B/D is a result of this frozen physical model, not a general statement that transport never matters.

## Important model boundary

HTT is an internal four-station transfer and is never counted as new hydrogen. The current main MSP imposes a beta-dependent aggregate HTT capacity and cost, but no pairwise hard road-reachability constraint on HTT arcs. Consequently, these results support only the current model's spatial-feasibility statement.

## Output guide

- `state_system_feasibility_summary.csv`: primary state-level total/spatial/resource table.
- `state_site_spatial_balance.csv`: SAA/DRO station targets, final inventory, surplus, deficit, and path shares.
- `stage_total_h2_balance.csv`: stage-level four-station hydrogen conservation and ordinary-service totals.
- `stage_site_inventory_trace.csv`: station inventory, production, service, and transport traces.
- `htt_redistribution_trace.csv`: actual station inflow/outflow/net flow and aggregate HTT utilization.
- `resource_utilization_summary.csv`: continuous mean/median/q95/max utilization and >=95%/>=99% shares.
- `state12_16_17_18_19_detailed_check.csv`: required focus-state detail.
- `state13_14_reference_check.csv`: reference-state detail.
- `physical_feasibility_path_audit.csv`: path-level diagnostic LP evidence.
- `replay_integrity_audit.txt`: deterministic replay and LP mechanical certificate.
- `step05b4_judgment.txt`: bounded interpretation and next-step recommendation.

## Replay certificate

```text
Step-05B-4 deterministic replay and physical-LP integrity audit

Focus states: [12 16 17 18 19 13 14]
Selected terminal-hit paths: 649
Common OOS file: C:\Users\chaos\Desktop\biye\test\testH2_v2\output_h2\details\h2_OOS.csv
OOS SHA-256: 6e4ed488423e3cbb838c4a6f8b45019cf4ecf32a82850880399a08aafc7aff85
SAA replay elapsed seconds: 114.6185866
DRO replay elapsed seconds: 119.6750604
SAA max errors: saved_final=0, B1_final=5.11590769747e-13, terminal_state=0
DRO max errors: saved_final=0, B1_final=5.11590769747e-13, terminal_state=0
Physical diagnostic LP rows: 649
Physical LP optimal rows: 649
Max conservation residual: 4.97379915032e-14
Max target/gap reconstruction residual: 6.25277607469e-13
Replay PASS: 1
Physical LP PASS: 1

Physical diagnostic definition:
- ordinary service at every stage/site is fixed to the actual DRO replay service; it is not cancelled or reduced.
- original initial inventory, station tank capacity, electrolyzer capacity/conversion, inventory conservation, and beta-dependent aggregate HTT capacity are enforced.
- HTT is internal transfer and never contributes to system hydrogen supply.
- cuts, theta, and monetary objective terms are intentionally absent; results are diagnostic physical feasibility, not an optimized MSP policy.
- the current main MSP has no pairwise hard road-reachability constraint on HTT arcs.
```
