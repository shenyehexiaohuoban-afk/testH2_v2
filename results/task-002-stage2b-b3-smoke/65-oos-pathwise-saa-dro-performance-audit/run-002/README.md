# Step-05B-8 pathwise SAA/DRO OOS performance audit

Accepted run: `run-002`.

This read-only audit pairs the archived SAA and eta=0.03 DRO policies on the exact same 10000x8 OOS paths. It uses the mechanically verified Step-05B-1 path results; no MATLAB/Gurobi call, training, resampling, cut generation, TerminalLOH change, penalty change, or W-stage evaluation is performed.

`operating_cost` is the existing reported objective minus `2000 * terminal_gap`. It contains production electricity/O&M, HTT cost, holding cost, and ordinary-shortage penalty. It is a diagnostic comparison of actual modeled operating terms, while the reported objective is retained separately.

The full 10000-row master table is retained locally and recorded in `LARGE_FILE_MANIFEST.md` when it exceeds the lightweight Git threshold. Summary, confidence-interval, tail, terminal-hit, state-mechanism, and judgment outputs are reviewable results.
