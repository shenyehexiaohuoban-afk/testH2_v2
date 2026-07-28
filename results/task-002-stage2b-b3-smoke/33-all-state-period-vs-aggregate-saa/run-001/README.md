# Step-03Y-D run-001

## Scope

All 35 initial states use the first 100 and first 500 frozen nominal records. Period D/reachability/cost are deterministically replayed from the accepted Step-03Y-A random streams; no new random scenarios are generated.

## Result

- Mechanical status: `PASS`.
- Completed states: `35`; failed states: `0`.
- R=500 numerically identical aggregate/period T states: `12`.
- R=500 close diagnostic states: `19/35`. The diagnostic uses maximum site and total capacity fractions <= `0.1` and maximum cross relative regret <= `0.01`; it is descriptive, not a formal model threshold.
- Recommended attention states: `NONE`.
- Recommended weak-time-compression control state: `7`.
- Solver calls: `210`; runtime: `190.070672 s`; peak working set: `1666736128 bytes`.
- WDRO, MSP, validation, distance, and rho calls: `0`.

## Frozen start status

```text
## task/002-stage2b-b3-smoke...origin/task/002-stage2b-b3-smoke
 M ../../codex_rule/log.md
?? ../../results/task-002-stage2b-b3-smoke/16-dac-transport-cost-audit/run-001/
?? ../../results/task-002-stage2b-b3-smoke/23-fixed-decision-loss-consistency/run-001.failed-001/
?? ../../results/task-002-stage2b-b3-smoke/24-old-vs-ctilde-fixed-loss/
?? ../../results/task-002-stage2b-b3-smoke/25-old-cost-evidence-trace/
?? ../../results/task-002-stage2b-b3-smoke/26-old-ground-cost-recompute/
?? ../../results/task-002-stage2b-b3-smoke/27-period-data-recoverability/run-001.failed-001/
?? ../../results/task-002-stage2b-b3-smoke/27-period-data-recoverability/run-002/recovered_period_data.mat
?? ../../results/task-002-stage2b-b3-smoke/30-period-lp-equivalence-audit/
?? ../../results/task-002-stage2b-b3-smoke/31-period-vs-aggregate-terminalLOH/
?? ../../results/task-002-stage2b-b3-smoke/32-saa-weight-capacity-audit/
?? recover_step03Y_prefix_entries_h2.m
?? run_step03XB_old_ground_cost_recompute.py
?? run_step03X_old_vs_ctilde_fixed_loss.py
?? run_step03YBB_period_lp_equivalence_audit_h2.m
?? run_step03YCA_saa_weight_capacity_audit_h2.m
?? run_step03YC_period_vs_aggregate_terminalLOH_h2.m
?? run_step03YD_all_state_period_vs_aggregate_saa_h2.m
?? solve_step03Y_saa_audit_h2.m
```

See the CSV files for site-level T, objective decomposition, cross regret, saturation, demand counts, and R=100-to-R=500 stability.
