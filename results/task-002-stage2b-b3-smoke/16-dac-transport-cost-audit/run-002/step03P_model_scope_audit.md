# Step-03P Model Scope Audit

## Frozen scenario representation

`load_frozen_b3_wdro_dataset_h2.m:28-30,45-50` restores each post-disaster atom as complete node demand `D(Rx33)`, binary reachability `A(Rx4x33)`, and conditional service distance `C(Rx4x33)`. Path, wind, resistance seed, line-failure count, and road-closure count remain metadata and are not solver arguments.

`D` is the three-hour node hydrogen requirement produced upstream from grid load loss. `A=1` means that a site can serve a node over every demand-critical window used by the W1-W3 aggregation. `C` is the mean current-road-state shortest-path distance over those critical reachable windows; when `A=0`, `C=Inf` is a sentinel and is masked out.

## Loss and decision scope

The formal solver signature `solve_wdro_terminal_loh_lp_h2(D,A,C,Cap,M,rho,dMat,config)` contains no other sample-varying consequence argument. Lines 64-69 use `A` and `D` to set service-arc bounds. Lines 90-101 impose `sum_i y^s_{i,n}+u^s_n=D^s_n`. Lines 103-113 impose `sum_n y^s_{i,n}<=T_i`. Lines 115-131 define scenario loss from reachable `C*y` plus shortage penalty `M*u`.

Thus, after the upstream grid-road consequence chain has produced D/A/C, TerminalLOH depends on samples only through D/A/C. Wind, failed-line counts, road-closure counts, path states, and random seeds can change D/A/C upstream but have no additional direct path into the WDRO LP. Fixed model parameters such as M, gamma, rho, and capacity bounds are not sample-varying omitted state.

TerminalLOH is not a result for one atom. For one initial state, all R atoms jointly determine four common T variables through the optimal-transport DRO dual. MSP later uses state-level TerminalLOH for pre-landfall placement; this audit does not run MSP.

This study intentionally excludes site damage, vehicle count, vehicle capacity, repeated trips, and post-disaster vehicle routing.

## Capacity used in this audit

Step-03P uses the complete physical upper bound `Cap=[300 200 100 150] kg`; no 0.8 reduction is applied. Step-03O remains an unchanged historical audit.
Shortage penalty M=2000 from `NearStageInput.Cost.reserve_shortage_penalty_yuan_per_kg`.
