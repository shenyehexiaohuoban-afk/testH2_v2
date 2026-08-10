# Step-05B-2 TerminalLOH realization audit

Accepted result: `run-001`.

This is a read-only post-processing audit of the accepted Step-05B-1 common-sample path table and the frozen C6 35-state TerminalLOH tables. It does not retrain the MSP, call forward/backward/cut, change TerminalLOH, or change the 200/2000 penalties.

Key interpretation:

- `eta003` means eta = 0.03.
- All station and four-station total units are explicitly separated.
- The strict increment ratio is reported only where `DeltaT > 0`; zero and negative increments are retained as separate classes.
- Four frozen states were not reached by these 10000 OOS paths. Their realized metrics are intentionally `NaN`, not imputed.
- Final bounded judgment: **D**, with targeted follow-up recommended for the dominant low-realization states and sites.

See `aggregation_definition_audit.txt` for aggregation rules and `step05b2_judgment.txt` for the bounded conclusion.
