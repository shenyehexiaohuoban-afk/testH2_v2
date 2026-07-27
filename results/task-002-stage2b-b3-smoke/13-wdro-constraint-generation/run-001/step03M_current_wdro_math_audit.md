# Step-03M Current WDRO Mathematical Audit

## Scope and suitability

The accepted solver is `solve_wdro_terminal_loh_lp_h2.m`; the accepted distance builder is `build_wdro_distance_matrix_h2.m`. Neither file is modified by Step-03M.

The current finite-support Wasserstein dual is suitable for an exact exchange method. For fixed restricted-master variables, every omitted pair constraint has an explicit violation value and all ordered pairs can be scanned exactly.

## Variables

- `T_i`, i=1,...,4: TerminalLOH at each of the four sites, bounded by `Cap_i`.
- `y^s_{i,n}`: hydrogen service from site i to node n in consequence atom s.
- `u^s_n`: unmet node demand in atom s.
- `L_s`: optimized service and shortage loss of atom s.
- `lambda >= 0`: Wasserstein-radius dual multiplier.
- `alpha_r` unrestricted: empirical-atom dual intercept.

## Current objective

`min gamma * sum_i T_i + rho * lambda + (1/R) * sum_r alpha_r`.

The implementation fixes the empirical mass at `1/R`; it does not accept non-equal sample weights.

## Consequence and service constraints

For every atom s and node n: `sum_i y^s_{i,n} + u^s_n = D^s_n`.

For every atom s and site i: `sum_n y^s_{i,n} <= T_i`, with `0 <= T_i <= Cap_i`.

Reachability enters through `0 <= y^s_{i,n} <= A^s_{i,n} D^s_n`.

Loss is constrained by `L_s >= sum_{i,n} Ceff^s_{i,n} y^s_{i,n} + M sum_n u^s_n`, where `Ceff=0` at A=0 and reachable C must be finite.

## Wasserstein distance

Step-03M uses the accepted `DAC_maskedC` distance. D contributes full node-level L1 demand difference, A contributes full 4x33 binary reachability L1 difference, and C contributes L1 service-cost difference only where both atoms have A=1.

Component weights are D/A/C = 0.6/0.25/0.15. Each component is divided by its maximum pairwise value plus epsDistance 1e-09 when that scale exceeds 1e-12.

Path states, sampled winds, and random seeds are metadata and do not enter the current distance or loss.

## Origin of the R-squared constraints

For every empirical atom r and consequence atom s, the solver adds `alpha_r + lambda*d(r,s) >= L_s`, equivalently `L_s - lambda*d(r,s) - alpha_r <= 0`. The nested r,s loops create exactly R^2 rows.

## Exact separation

For each r, Step-03M computes `max_s {L_s - lambda*d(r,s) - alpha_r}` over every s. If the maximum exceeds 1e-8, the most violated pair for that r is added. The distance scale scan, every iteration scan, and the post-convergence independent scan cover all ordered pairs in blocks without retaining an R-by-R distance matrix.

This is an exact exchange implementation for the current finite LP. It uses no clustering, scenario reduction, random subset, approximate nearest neighbor, or partial separation.

For the 1e-8 objective comparison, the unchanged full solver is called under a temporary out-of-repository `gurobi.env` with `OptimalityTol=1e-9`, `FeasibilityTol=1e-9`, and `NumericFocus=3`. This avoids a measured default-tolerance alpha/L slack while leaving the accepted solver source, default mode, and repository configuration unchanged.

## Experiment parameters

`M=2000` from `NearStageInput.Cost.reserve_shortage_penalty_yuan_per_kg`; `gamma=2`; `Cap=0.8*tank_capacity=[240 160 80 120]` kg; rho values are 0 and the existing minimum positive radius 0.02.

Literature basis: Mohajerin Esfahani and Kuhn (2018) for the Wasserstein dual reformulation; Luo and Mehrotra (2019) for exchange/cutting-surface decomposition. The present experiment retains this project's existing four-site TerminalLOH variables and D/A/C definitions.
