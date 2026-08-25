# Stage90B candidate

This isolated launcher runs one Base-Pmax engineering smoke with the frozen
Stage90A terminal recourse. It loads the formal Stage89Q bridge, sets only the
explicit candidate fields in `config/stage90b_base_pmax_config.csv`, builds a
fresh model library, and runs exactly 10 iterations from zero cuts.

`orchestrate_stage90b_base_pmax_fresh_zero_cut_10iter.ps1` launches separate
MATLAB processes for CONFIG, TRAIN, and RELOAD. The training phase writes
iteration-level traces, terminal forward/OOS diagnostics, Stage1 grid/tank/
HTT checks, and a local checkpoint. The checkpoint is hashed after MATLAB
exits and is intentionally excluded from Git.

The smoke is an engineering early-signal check only. It cannot establish
wait-and-see improvement, terminal reliability improvement, convergence, or
candidate adoption.
