# Step-03Z-D Ground-Cost Scale Audit

Conclusion: **B. D_SCALE_FORMULA_MISMATCH**

This audit is static except for a streaming scan of the stored nominal C array. It calls no solver, WDRO, MSP, validation, TerminalLOH optimization, or random scenario generator, and it does not change the frozen 0.6/0.4 formula.

## Main findings

- Current D: `sum_tau Delta_D_tau/(3*(Dscale+1e-9))`. Dscale is already a three-period aggregate scale, so the final period average shrinks D by an additional factor of three relative to the matching total-numerator formulation.
- One-period physical D upper: 202.65662929929354 kg; three-period upper: 607.96988789788065 kg.
- C_bound: 357.1526447416079 km, derived as twice the total road length. It is a finite post-disaster path-value upper bound.
- Nominal maximum finite C: 129.02475211610735 km; maximum same-state/same-coordinate finite difference: 117.808534620188 km.
- Cscale is conservative but compatible with `abs(C1-C2)` because finite C lies in [0,C_bound].
- Total ground cost is not required to lie in [0,1]. Under current weights, the formal Ctilde contribution is at most 0.4; the current D physical maximum contribution is state-dependent and reported in `component_range_summary.csv`.

runtime_sec=4.962332
peak_working_set_bytes=1285427200
component_summary_rows=13
current_D_to_matched_D_ratio=0.33333333333333331
weights=0.6/0.4
