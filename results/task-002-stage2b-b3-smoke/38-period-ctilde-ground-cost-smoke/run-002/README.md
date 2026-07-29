# Step-03Z-C Three-Period D + Ctilde Ground-Cost Smoke Audit

Conclusion: **C. METRIC_VALID_BUT_SCALE_NOT_FROZEN**

This independent audit extends the frozen aggregate `0.6*d_D+0.4*d_Ctilde` formula by comparing W1-W1, W2-W2, and W3-W3 and averaging the three period components. It does not run WDRO/MSP, optimize TerminalLOH, read validation, add A, tune rho, or scan weights.

- states: 7, 9, 11, 19
- nominal prefix per state: R=2000
- selected scenarios: 194
- selected unordered pairs: 5078
- fixed-T scenario evaluations: 776
- pooled fixed-T rows with fewer low-distance mismatches under period distance: 0/4
- pooled fixed-T rows with higher Spearman correlation under period distance: 3/4
- maximum program triangle violation: 2.2204460492503131e-16
- runtime_sec: 80.014604
- peak_working_set_bytes: 1428611072

The metric audit passes on the effective scenario representation. Formal expansion is nevertheless blocked because Dscale remains state-specific and derived from each state's nominal R=15000 sample maximum.

## Deterministic Selection Coverage

state 7: selected=22
- ZERO_DEMAND: 8
- LOW_DEMAND: 8
- MEDIUM_DEMAND: 8
- HIGH_DEMAND: 8
- SINGLE_PERIOD_CONCENTRATED: 8
- THREE_PERIOD_UNIFORM: 0
- REACHABILITY_CHANGE: 4
- AGGREGATE_SERVICE_DELETION: 0
state 9: selected=56
- ZERO_DEMAND: 8
- LOW_DEMAND: 8
- MEDIUM_DEMAND: 8
- HIGH_DEMAND: 8
- SINGLE_PERIOD_CONCENTRATED: 8
- THREE_PERIOD_UNIFORM: 8
- REACHABILITY_CHANGE: 8
- AGGREGATE_SERVICE_DELETION: 8
state 11: selected=57
- ZERO_DEMAND: 8
- LOW_DEMAND: 8
- MEDIUM_DEMAND: 8
- HIGH_DEMAND: 8
- SINGLE_PERIOD_CONCENTRATED: 8
- THREE_PERIOD_UNIFORM: 8
- REACHABILITY_CHANGE: 8
- AGGREGATE_SERVICE_DELETION: 8
state 19: selected=59
- ZERO_DEMAND: 8
- LOW_DEMAND: 8
- MEDIUM_DEMAND: 8
- HIGH_DEMAND: 8
- SINGLE_PERIOD_CONCENTRATED: 8
- THREE_PERIOD_UNIFORM: 8
- REACHABILITY_CHANGE: 8
- AGGREGATE_SERVICE_DELETION: 8
