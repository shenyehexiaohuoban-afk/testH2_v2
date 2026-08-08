# Step-05A0B native FA-MSP smoke run-001

Status: `A / PASS`.

This run uses the new thin launcher `run_main_msp_h2_native_smoke.m`. The launcher calls the original `h2_default_options` and `run_h2_with_options`; it does not replace or modify model construction, forward, backward, cut generation, evaluation, TerminalLOH, the Markov model, seed, or physical/economic parameters.

Frozen smoke differences are recorded in `native_vs_smoke_options_audit.csv`. Native outputs are confined to `run-001/native_output`; the protected `output_h2` tree is read only.

The MATLAB process exited zero after approximately 6.76 minutes wall time. Training ran for 301.927 seconds and completed 162 forward iterations plus 161 backward passes. The final model contains 203021 appended cut rows, and iteration 2 onward reused the cut-enriched model library. The unchanged native evaluation then processed all 10000 OOS paths in 51.729 seconds.

Runtime evidence confirms 6053 OOS paths reached lf=7, 760 paths had positive terminal shortage, the active table remained the 4x336 `terminal_impact_template` table with 35 nonzero columns, and the terminal penalty remained 2000.

The first post-run cut-count audit failed only because empty absorbing-state model cells were not handled in the audit expression. Its log is retained. A corrected read-only audit completed successfully without rerunning or changing the smoke.
