# Deep SAA-vs-DRO Analysis Freeze

This directory freezes the existing paired BASE2-SAA versus BASE2-DRO analysis. No analysis script, TerminalLOH solve, training, optimization, or OOS run was executed during closeout.

The frozen evidence supports a cost-preparedness-risk-coverage trade-off: SAA has lower preparation exposure, lower operating cost, lower mean absolute terminal site gap, and a higher positive-target fully/sitewise adequate fraction; DRO has broader protection targets, higher target-mass-weighted service, and more pre-disaster H2 preparation. This is descriptive paired MSP policy-propagation evidence, not final W-stage robustness validation. It is not a fixed-target causal comparison, and `FULLY_CONVERGED = NOT_ESTABLISHED` remains unchanged.

Frozen headline values are recorded in `final_metrics.json` and `DEEP_ANALYSIS_FREEZE_QA.json`. Large runtime artifacts remain local and untracked.
