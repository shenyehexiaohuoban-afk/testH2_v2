# Step-05B-7 all-state target/actual/feasible inventory audit

Accepted run: `run-002`

This read-only audit compares SAA and eta=0.03 DRO on the same 6053 terminal-hit paths. Each method keeps its own archived ordinary H2 service quantities and uses its own TerminalLOH target. No training, resampling, cut generation, TerminalLOH change, or 200/2000 change occurred.

The primary result is that state16/17/18/19 all have higher DRO actual inventory, but the DRO target rises faster. Across all reached states, 3 paths have SAA capacity gap greater than DRO, including 1 path that is SAA-infeasible but DRO-feasible. These exceptions are retained and explained rather than smoothed away.

The raw 12106-row LP table is retained locally for reproducibility and listed in `LARGE_FILE_MANIFEST.md`; required lightweight summaries are suitable for Git.

`independent_mechanical_audit.txt` independently reconstructs the closed-form
system inventory bound, capacity gaps, C6 target lookup, path transitions, and
reverse cases. `source_integrity_audit.txt` records the frozen OOS hash, the
byte-identical run-001/run-002 raw-file reuse, and the absence of protected
source differences.
