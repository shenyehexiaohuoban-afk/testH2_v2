# Step-03Z-A three-period model information audit

- Frozen branch: `task/002-stage2b-b3-smoke`.
- Frozen local/upstream HEAD: `61122dee2cde34736111f0987905da6a3c63d35a`.
- Method: static source, result, and repository-document audit only.
- Solver calls: `0`; WDRO calls: `0`; MSP calls: `0`; validation reads: `0`.
- No Step-03Y R=2000 case was rerun.
- Conclusion: `B. USER_DECISION_REQUIRED_ON_INFORMATION_STRUCTURE`.

The implemented period SAA is internally a two-stage full-scenario-information model. One common pre-event TerminalLOH vector is optimized before scenario-specific recourse. Within each realized scenario, all W1-W3 service and shortage variables are optimized together, while all three periods consume the same site reserve. There are no nonanticipativity constraints or scenario-tree node decisions.

The repository explains the three one-hour windows, persistent damage, cumulative demand, pre-layout purpose, shared reserve, and the absence of advance service/backlog. It does not explicitly state whether all W1-W3 consequences are known at the start of post-disaster recourse or revealed sequentially. That modeling assumption therefore requires an explicit user decision before formal freeze.

## Protected start status

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
?? terminalLoh_wdro/src/run_step03XB_old_ground_cost_recompute.py
?? terminalLoh_wdro/src/run_step03X_old_vs_ctilde_fixed_loss.py
?? terminalLoh_wdro/src/run_step03YBB_period_lp_equivalence_audit_h2.m
?? terminalLoh_wdro/src/run_step03YCA_saa_weight_capacity_audit_h2.m
?? terminalLoh_wdro/src/run_step03YC_period_vs_aggregate_terminalLOH_h2.m
?? terminalLoh_wdro/src/run_step03YE_period_vs_aggregate_saa_stability_h2.m
?? terminalLoh_wdro/src/run_step03ZA_information_structure_audit.py
```
