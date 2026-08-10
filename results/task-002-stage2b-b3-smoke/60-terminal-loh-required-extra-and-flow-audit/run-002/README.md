# Step-05B-3 required-extra and hydrogen-flow audit

Accepted result: `run-002`.

`run-001` is preserved as a failed launcher attempt: MATLAB did not have the new audit source directory on its path, so no replay began.

This run contains a strict common-sample required-extra audit plus deterministic replay of the two saved fixed policies on the unchanged 10000x8 OOS path table. It does not train the MSP, change TerminalLOH, change 200/2000, regenerate OOS paths, or modify any core model file.

Important interpretation:

- `required_extra = max(0, T_dro - I_saa)` includes both an uncovered new target increment and any pre-existing SAA gap.
- `effective_realization` is defined only when `required_extra > 0` and is never clipped.
- A/B/C/D classes follow the task definitions exactly. Class A is additionally split diagnostically when the DRO policy later falls below a target already covered by SAA inventory.
- Flow and binding tables cover the 11 selected C/D state-site pairs. They are descriptive selected-subset diagnostics; paths can occur in multiple focal pairs.
- `eta003` means eta = 0.03.

See `mechanism_summary.txt` and `step05b3_judgment.txt` for the conclusion.
