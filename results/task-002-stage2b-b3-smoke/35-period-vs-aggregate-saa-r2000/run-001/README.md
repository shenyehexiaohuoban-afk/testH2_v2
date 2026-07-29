# Step-03Y-F run-001

## Scope

States 7, 9, 11, and 19 use the exact first 2000 frozen nominal records. Each state was solved in an independent MATLAB process and released before the next state.

Aggregate and period-resolved SAA use identical gamma, shortage penalty, service-cost basis, capacities, record order, and equal 1/R weights. R=500 and R=1000 are reused from Step-03Y-D/E for comparison.

## Result

- Mechanical status: `PASS`.
- Conclusion: `C. STATE_DEPENDENT_OR_UNSTABLE`.
- Solver calls: `16`.
- Total isolated-state runtime: `139.495094 s`.
- Maximum per-process working set: `1414336512 bytes`.
- WDRO, MSP, validation, distance, rho, and new random scenario calls: `0`.

## State summary

- State 7: max site differences R=500/1000/2000 = `0.000000/0.000000/0.000000 kg`; R=2000 type `NUMERICALLY_IDENTICAL`.
- State 9: max site differences R=500/1000/2000 = `85.917683/29.457491/29.457491 kg`; R=2000 type `SITE_REALLOCATION_DOMINANT`.
- State 11: max site differences R=500/1000/2000 = `77.462292/6.000600/18.001800 kg`; R=2000 type `SMALL_MIXED_DIFFERENCE`.
- State 19: max site differences R=500/1000/2000 = `97.717044/81.235851/54.005401 kg`; R=2000 type `TOTAL_AND_SITE_DIFFER`.

The close diagnostic reuses Step-03Y-D's descriptive 10% capacity-difference and 1% cross-regret criteria; it is not a new formal model threshold.

State 11 remains inside that descriptive close band at R=2000, but it does not continue monotonic convergence: its maximum site difference rises from `6.000600 kg` at R=1000 to `18.001800 kg` at R=2000, and its total difference changes from numerical zero to `-29.972997 kg`.

## Frozen start status

```text
## task/002-stage2b-b3-smoke...origin/task/002-stage2b-b3-smoke
?? results/task-002-stage2b-b3-smoke/16-dac-transport-cost-audit/run-001/
?? results/task-002-stage2b-b3-smoke/23-fixed-decision-loss-consistency/run-001.failed-001/
?? results/task-002-stage2b-b3-smoke/24-old-vs-ctilde-fixed-loss/
?? results/task-002-stage2b-b3-smoke/25-old-cost-evidence-trace/
?? results/task-002-stage2b-b3-smoke/26-old-ground-cost-recompute/
?? results/task-002-stage2b-b3-smoke/27-period-data-recoverability/run-001.failed-001/
?? results/task-002-stage2b-b3-smoke/27-period-data-recoverability/run-002/recovered_period_data.mat
?? results/task-002-stage2b-b3-smoke/30-period-lp-equivalence-audit/
?? results/task-002-stage2b-b3-smoke/31-period-vs-aggregate-terminalLOH/
?? results/task-002-stage2b-b3-smoke/32-saa-weight-capacity-audit/
?? results/task-002-stage2b-b3-smoke/34-period-vs-aggregate-saa-stability/
?? results/task-002-stage2b-b3-smoke/35-period-vs-aggregate-saa-r2000/
?? terminalLoh_wdro/src/finalize_step03YF_r2000_h2.m
?? terminalLoh_wdro/src/run_step03XB_old_ground_cost_recompute.py
?? terminalLoh_wdro/src/run_step03X_old_vs_ctilde_fixed_loss.py
?? terminalLoh_wdro/src/run_step03YBB_period_lp_equivalence_audit_h2.m
?? terminalLoh_wdro/src/run_step03YCA_saa_weight_capacity_audit_h2.m
?? terminalLoh_wdro/src/run_step03YC_period_vs_aggregate_terminalLOH_h2.m
?? terminalLoh_wdro/src/run_step03YE_period_vs_aggregate_saa_stability_h2.m
?? terminalLoh_wdro/src/run_step03YF_r2000_state_h2.m
```
