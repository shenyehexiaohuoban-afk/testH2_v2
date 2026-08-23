# Stage-89K TerminalLOH dual-channel candidate

Status: **FORMAL_TERMINALLOH_CANDIDATE**; **NOT CURRENT_TERMINALLOH**, **NOT CURRENT_W_MAINLINE**, **NOT MSP-ACCEPTED**.

## Outcome

All 35 SAA and 35 Pearson chi-square DRO cases are optimal and pass inventory, FC-capacity, q/p probability, ambiguity-radius, demand-balance, objective reconstruction, and certified gap gates. Stage-89J was read without resampling or modification. The reported change is the **FULL CANDIDATE EFFECT** and is not attributed to any single mechanism. FA-MSP and OOS were not run.

- Stage88/Stage89K SAA mean T total: `344.707198/237.923792 kg`.
- Stage88/Stage89K DRO mean T total: `382.034556/277.210943 kg`.
- Mean q-weighted road/electrical/shortage over 70 mode-state cases: `37.299741/9.272277/7.083733 kg`.
- FC capacity binding observed: `YES`.

## Runs and artifacts

`run-001` is preserved as failed after a post-solve Pandas result-serialization error in the first smoke case; it never entered DRO or the formal solve. This accepted candidate is `run-002`, which restarted input SHA/schema QA and all six smoke cases.

Large per-case arrays and checkpoint artifacts: `terminalLoh_wdro/output/stage89k_terminalLoh_dual_channel_candidate/run-002`. `large_output_manifest.csv` records every large/checkpoint file's path, bytes, SHA-256 and logical row count.
