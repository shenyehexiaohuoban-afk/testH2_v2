# BASE2-SAA Reconstructed-Source 35-State Numerical Reproduction

The current reconstructed dependency was executed through the current SAA runner in a new isolated output directory. No historical output was overwritten.

- `RECONSTRUCTION_STATUS = PASS`
- `HISTORICAL_EXACT_SOURCE_IDENTITY = NOT_PROVEN`
- `HISTORICAL_RUNTIME_BYTECODE_EQUIVALENCE = PASS`
- `FORENSIC_EVIDENCE_LEVEL = LEVEL_B`
- `CURRENT_RECONSTRUCTED_SOURCE_SHA256 = 14436f4bad0f7f46d5d0a59f69c463a11efbfe9f255b6e26e7acfb1573985de8`
- `HISTORICAL_SAA_TABLE_SHA256 = 1e2968cf045ea883a60cd2e287f6f26ac6a23b735a432e5235c0e68b905ca4a3`
- `RECONSTRUCTED_TABLE_SHA256 = 1e2968cf045ea883a60cd2e287f6f26ac6a23b735a432e5235c0e68b905ca4a3`
- `SAA_OPTIMAL_COUNT = 35/35`
- `MAX_ABS_T_DIFF_ALL = 0`
- `MAX_ABS_TOTAL_DIFF = 0`
- `MEAN_ABS_T_DIFF = 0`
- `STATE_ORDER_IDENTITY = YES`
- `STATE_MAPPING_IDENTITY = YES`
- `SAA_PROBABILITY_SEMANTICS = PASS`
- `DURATION_AWARE_RECOURSE_SEMANTICS = PASS`
- `OBJECTIVE_SEMANTICS = PASS`
- `HISTORICAL_OUTPUT_MODIFIED = NO`
- `MSP_TRAINING_RERUN = NO`
- `OOS_RERUN = NO`
- `READY_FOR_REPRODUCIBILITY_CLOSEOUT = NO`

The historical exact source bytes remain unproven. The historical PYC and current reconstructed source are normalized/semantic-bytecode equivalent, and the reconstructed source independently reproduced the frozen 35-state SAA TerminalLOH scientific values within the declared `1e-10 kg` tolerance.

Scientific T1-T4 and total values are compared mechanically in `historical_vs_reconstructed_T.csv`. The historical table's saved objective, empirical expected recourse, solver status, probability, duration, inventory, and cost QA fields are also compared mechanically in `objective_comparison.csv`; preparation cost, demand-balance QA, and FC-capacity QA are labeled `NOT_AVAILABLE` because those fields are not saved in the historical table.

No MATLAB, OOS, MSP training, DRO recalculation, grouped-bank regeneration, W regeneration, checkpoint/cut edit, historical-output edit, eta metadata edit, commit, or push was performed.
