# Step-05B-9 OOS inventory-gain distribution audit

Accepted run: `run-001`.

This read-only audit uses the Step-05B-8 10000-row common-sample path table and applies only the fixed bins and exceedance thresholds specified by the task. It does not train, resample, invoke MATLAB/Gurobi, generate cuts, change TerminalLOH, change 200/2000, or modify core FA-MSP code.

The three figures use path-level inventory differences only; no state averages enter the plots.

Independent mechanical verification passed for all fixed-bin and threshold counts, source reconstruction, negative/near-zero cases, PNG integrity, and protected-source checks. See `independent_mechanical_audit.txt` and `source_integrity_audit.txt`.

Source-integrity note: the actual corrected local Step-05B-8 master file is 5114286 bytes with SHA-256 `58336879...9914b`. The older Step-05B-8 manifest entry predates the corrected state-ID mapping and is stale. The prior accepted run is not modified; this run records the actual source hash and independently reconciles the master against the frozen Step-05B-1 path data.
