# Step-03Z-E Corrected Period Demand-Scale Alignment Audit

Conclusion: **B. D_SCALE_FIX_CORRECT_BUT_ALIGNMENT_STILL_POOR**

This controlled audit reuses the exact 194 scenarios, 5078 pairs, fixed TerminalLOH vectors, and 776 operating-loss values from Step-03Z-C run-002. It recalculates only the demand component, total distance, and derived diagnostics. Solver calls and fixed-loss recomputations are zero.

## Formula

- Old: `mean_tau(Delta_D_tau/(Dscale_state+1e-9))`.
- Corrected: `sum_tau Delta_D_tau/(607.96988789788054+1e-9)`.
- Unchanged: `d=0.6*d_D+0.4*d_Ctilde`, with Ctilde averaged across W1-W3.

The global scale is reproduced from all non-source load loss over three one-hour periods with absolute error `1.1368683772161603e-13 kg`.

## Main fixed-loss result

A material improvement is defined before classification as an absolute low-distance/high-loss mismatch-share reduction of at least `0.01`. Classification A additionally requires at least 3 of 4 pooled fixed T sets and at least 3 of 4 state-average results to meet that threshold.

- materially improved pooled fixed T sets: 2/4
- materially improved state means: 1/4
- metric checks: PASS
- corrected zero-distance fixed-loss difference: 0

| T | old mismatch share | corrected mismatch share | old minus corrected | old Spearman | corrected Spearman |
|---|---:|---:|---:|---:|---:|
| ZERO | 0.887175325 | 0.841720779 | 0.045454545 | 0.791896573 | 0.910101679 |
| HALF_CAPACITY | 0.922077922 | 0.910714286 | 0.011363636 | 0.892513650 | 0.912031034 |
| FULL_CAPACITY | 0.922077922 | 0.927759740 | -0.005681818 | 0.864246048 | 0.757921156 |
| STEP03YF_PERIOD_R2000 | 0.923701299 | 0.928571429 | -0.004870130 | 0.867367992 | 0.764895031 |

State 7 uses the same global denominator as all other states. Its maximum d_D changes from `0.31895256492734297` to `0.66666666666557173`; the total-distance rank Spearman remains `0.99179047641699691`.

State-average mismatch-share changes are recorded in `alignment_by_state.csv`; only 1 state mean(s) meet the one-percentage-point material threshold.

runtime_sec=3.692390
peak_working_set_bytes=1286602752
state_mean_rows=4
