# Scale Provenance Audit

`C_bound=357.1526447416079 km` is global and deterministic: Step-03Q derives it as twice the sum of all road-edge lengths, using the frozen maximum slowdown multiplier 2. It does not depend on state, R, or the selected audit scenarios.

Dscale is not global. Step-03S defines it independently for each initial state as the exact L1 diameter of all 15000 nominal aggregate D rows. Consequently it is state-specific and nominal-sample-specific. It does not change when this audit uses R=2000 because the R=15000 value is reused literally, but it is not a universally frozen ground-cost scale.

The exact scan removes duplicate D rows before blockwise comparison; this is algebraically identical to scanning all 15000 x 15000 pairs. Only the maximum is retained.

| state | Dscale | unique D rows | Step-03S checkpoint | provenance |
|---:|---:|---:|:---:|---|
| 7 | 423.58781332678717 | 99 | true | R15000_EXACT_RECOMPUTE_AND_STEP03S_CHECKPOINT |
| 9 | 607.96988789788054 | 1114 | false | R15000_EXACT_RECOMPUTE_SAME_FROZEN_FORMULA |
| 11 | 607.96988789788054 | 1043 | true | R15000_EXACT_RECOMPUTE_AND_STEP03S_CHECKPOINT |
| 19 | 607.96988789788054 | 3332 | false | R15000_EXACT_RECOMPUTE_SAME_FROZEN_FORMULA |

scale_recovery_runtime_sec=1.153787
classification_effect=METRIC_VALID_BUT_SCALE_NOT_FROZEN if all other checks pass
