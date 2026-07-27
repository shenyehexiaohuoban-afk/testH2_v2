# Step-03S Risk-Decision Feature Definition

The 16-dimensional z vector is used only to compare the 35 conditional nominal distributions. It does not replace the formal D+Ctilde ground distance.

## Features

1. total_D = sum_n D_n.
2. unreachable_D = demand on nodes unreachable from all four sites.
3. unreachable_D_ratio = unreachable_D/max(total_D,eps).
4-7. reachable_D_i = sum_n A_i,n D_n for sites 1-4.
8-11. demand_weighted_C_i = sum_n A_i,n D_n C_i,n / sum_n A_i,n D_n. The value is defined as zero when the denominator is zero.
12-16. unchanged formal recourse loss at fixed T anchors 0%, 25%, 50%, 75%, and 100% of the common full capacity.

Feature order: total_D, unreachable_D, unreachable_D_ratio, reachable_D_1, reachable_D_2, reachable_D_3, reachable_D_4, demand_weighted_C_1, demand_weighted_C_2, demand_weighted_C_3, demand_weighted_C_4, loss_T0, loss_T25, loss_T50, loss_T75, loss_T100.
Capacity vector: [300,200,100,150] kg.
Shortage penalty M: 2000; source: NearStageInput.Cost.reserve_shortage_penalty_yuan_per_kg.
Feature standardization uses only all 525000 nominal rows: (z-global mean)/global standard deviation. Constant features use scale 1 and remain zero after centering.

## Formal tail-distance constants

Tail neighbor searches retain d_new=0.6*d_D+0.4*d_Ctilde, kappa=1, and C_bound=357.1526447416079 km. The fixed 10%, 5%, 1%, and loss-similarity thresholds are declared before results are inspected and are not validation-tuned.
