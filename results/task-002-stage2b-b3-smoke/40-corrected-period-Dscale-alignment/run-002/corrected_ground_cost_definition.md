# Corrected Three-Period Ground-Cost Definition

The corrected demand component is:

`d_D_corrected(r,s) = sum_tau sum_n abs(D_r^tau(n)-D_s^tau(n)) / (Dscale_global+1e-9)`,

with `Dscale_global=607.96988789788054 kg`. The old audited formula was `mean_tau(sum_n abs(D_r^tau-D_s^tau)/(Dscale_state+1e-9))`, which introduced an extra division by three and used a state-dependent aggregate scale.

The total remains `d=0.6*d_D_corrected+0.4*d_Ctilde_period`. There is no independent A term and no truncation. W1 is compared only with W1, W2 with W2, and W3 with W3.

Ctilde is unchanged. In each period, 4x33 local service-relation distances are averaged: both unreachable is 0, a reachability mismatch is 1, and both reachable is `abs(C1-C2)/357.1526447416079`. The three period Ctilde values are then averaged.

Ctilde keeps the period mean because each period component is already a dimensionless average over the same 132 service relations with local maximum 1. Equal averaging gives each physical period equal weight and retains the component range. Demand differs: its global denominator is explicitly the physical total over all three periods, so its matching numerator is the three-period sum rather than a second average.

Physical verification: non-source load `3715 kW`, eta `0.55000000000000004`, LHV `33.329999999999998 kWh/kg`, derived three-period upper `607.96988789788065 kg`.

This independent audit does not modify the formal SAA/WDRO distance implementation.
