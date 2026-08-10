# Step-05B one-hour fixed-budget SAA versus eta=0.03 FA-MSP run

This directory contains the two archived policies subsequently used by
Step-05B-1 through Step-05B-7.

Both cases used the same frozen 10000x8 OOS dataset and the same model,
sampling, costs, solver settings, physical parameters, and 2000 yuan/kg
TerminalLOH gap penalty. The only model input difference was the SAA versus
eta=0.03 TerminalLOH table.

Important status: these are one-hour fixed-budget policies, not formally
converged policies. Both stopped with `stop_flag=2` because the 3600-second
training time limit was reached. SAA completed 1113 iterations and DRO 1199.

The full workspaces and path-level outputs remain local. Lightweight training
and evaluation summaries are recorded in `fixed_budget_training_summary.csv`;
large-file hashes are recorded in `LARGE_FILE_MANIFEST.md`.

No later Step-05B audit retrained either policy.
