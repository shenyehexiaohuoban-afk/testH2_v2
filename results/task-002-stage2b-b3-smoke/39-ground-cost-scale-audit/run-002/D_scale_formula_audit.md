# D Scale Formula Audit

## Frozen implementation

For period tau, `Delta_D_tau=sum_n abs(D_r^tau(n)-D_s^tau(n))` and Step-03Z-C computes `d_D_tau=Delta_D_tau/(Dscale+1e-9)`. It then computes `d_D_period=(d_D_W1+d_D_W2+d_D_W3)/3`. Therefore:

`d_D_period_current = sum_tau Delta_D_tau / (3*(Dscale+1e-9))`.

Dscale is not a one-period scale. It is the state-specific exact L1 diameter of the **aggregate three-period D=sum_tau D^tau** in nominal R=15000. The implementation therefore divides each one-period numerator by a three-period aggregate scale and then averages again.

## Physical upper limits

The recovery code defines `D_n^tau=outage_n^tau*P_n/(eta_FC*LHV)` for each one-hour period. Here `eta_FC=0.55000000000000004`, `LHV=33.329999999999998 kWh/kg`, total node load is `3715 kW`, and the source-node load is zero.

Thus one-period L1 demand difference is at most `U1=sum_n P_n/(eta_FC*LHV)=202.65662929929354 kg`. The sum over three periods is at most `U3=3*U1=607.96988789788065 kg`.

## Matching formulations

Ignoring the negligible epsilon convention, the following are equivalent when `U3=3*U1`:

1. `sum_tau Delta_D_tau/U3`;
2. `(1/3)*sum_tau Delta_D_tau/U1`.

If the existing Dscale is retained as the three-period scale, its matching one-period denominator is `Dscale/3`. The current code instead uses Dscale itself in every period and then averages, giving exactly one third of `sum_tau Delta_D_tau/Dscale`. This is a repeated one-third shrinkage. The `1e-9` epsilon only creates a negligible denominator-level difference between the two matched expressions.

## State evidence

| state | aggregate Dscale | implied one-period scale | observed max current d_D_period | weighted max at 0.6 |
|---:|---:|---:|---:|---:|
| 7 | 423.587813326787 | 141.19593777559567 | 0.31895256492734297 | 0.19137153895640577 |
| 9 | 607.96988789788099 | 202.65662929929366 | 0.33333333333278498 | 0.19999999999967097 |
| 11 | 607.96988789788099 | 202.65662929929366 | 0.33333333333278498 | 0.19999999999967097 |
| 19 | 607.96988789788099 | 202.65662929929366 | 0.33333333333278498 | 0.19999999999967097 |

Assessment: `D_SCALE_FORMULA_MISMATCH`. The audit does not modify Dscale, the period averaging rule, or the 0.6 weight.
