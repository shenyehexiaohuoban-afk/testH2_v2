# Flat Pearson Chi-Square DRO Solver Specification

## Scope

This specification implements the flat finite-support probability-DRO model for the frozen **two-stage three-period operational model under full scenario information**. It does not modify scenario generation, transition matrices, the frozen recourse model, or historical Wasserstein code/results.

For one initial state, every original Monte Carlo record has nominal mass `q_r=1/R`. The stored `path_probability` field is not applied again.

## Ambiguity set

The Pearson ambiguity set is

`P_eta = {p >= 0: sum(p)=1, sum_r (p_r-q_r)^2/q_r <= eta}`.

Eta is a nonnegative implementation input. Step-04B does not select or calibrate a formal eta.

## Exact dual reformulation

Let `z_r=Q(T,xi_r)`. With `f(t)=(t-1)^2` on `t>=0`,

`f*(s) = -1 + (max(s+2,0))^2/4`.

For `eta>0`, strong duality follows from the strictly feasible nominal distribution `p=q`. The worst expectation equals

`min_{lambda>=0,nu} nu + lambda*(eta-1) + sum_r q_r h_r`

subject to

- `t_r >= z_r - nu + 2*lambda`;
- `t_r >= 0`, `h_r >= 0`;
- `t_r^2 <= 4*lambda*h_r`.

The quadratic constraint is a rotated second-order cone. In Gurobi's `x'Qx` convention, the two symmetric `lambda,h_r` entries are each `-2`, giving the required cross term `-4*lambda*h_r`.

The closure at `lambda=0` is explicit: the cone forces `t_r=0`, and the linear row forces `nu>=z_r`, yielding the valid worst-support bound `max_r z_r`. No division by lambda is implemented.

Eta zero does not use a degenerate dual. It calls the weighted SAA LP directly.

## Frozen recourse integration

The formal recourse remains

- period demand balance `sum_i y_r^tau(i,n)+u_r^tau(n)=D_r^tau(n)`;
- reachability through creation of service variables only for `A_r^tau(i,n)=1`;
- one shared three-period site row `sum_{tau,n} y_r^tau(i,n)<=T_i`;
- service cost `C_r^tau(i,n)` and shortage penalty `M=2000`.

Only positive-demand reachable service arcs are created. This is an exact sparse representation: demand balance and nonnegativity already imply `y_r^tau(i,n)<=D_r^tau(n)`, so the former explicit reachable upper bound is redundant. No scenario pair or `R x R` matrix is created.

## Exact duplicate aggregation

Aggregation is permitted only when all raw bytes of every formal three-period D/A/C input are identical. SHA-256 is used only to form candidate buckets; every member is then compared byte-for-byte with its representative. No rounding, tolerance, path identifier, or fixed-T loss is part of the key.

For group `g`, `q_g=multiplicity_g/R`. Because every record in a group has the same recourse function for every `T`, the objective depends only on total group probability. For a fixed group total, Pearson divergence is minimized by distributing probability proportionally to the original nominal masses. Therefore the grouped and ungrouped ambiguity problems, fixed-T risks, SAA problem, and outer DRO problem are exactly equivalent.

## Independent audit

After every optimized `T`, the solver independently:

1. resolves the frozen fixed-T recourse on exact group representatives;
2. expands group losses to all original records;
3. solves the Pearson probability adversary by an independent KKT active-set method;
4. checks probability nonnegativity, probability sum, divergence, strong-duality gap, complete-objective reconstruction, demand balance, site capacity, and cone residuals.

The recovered original-record probability inside a group is the group worst mass divided by the exact multiplicity.

## Public MATLAB interfaces

- `solve_terminal_loh_saa_h2`: weighted formal SAA LP;
- `solve_terminal_loh_flat_chi2_qcp_h2`: positive-eta flat chi-square QCP, with eta zero routed directly to SAA;
- `solve_terminal_loh_flat_chi2_decomposition_h2`: certified risk cutting-plane solver with explicit lower/upper bounds and termination gap for large support;
- `evaluate_terminal_loh_period_fixed_T_sparse_h2`: fixed-T formal recourse evaluator;
- `solve_flat_chi2_worst_probability_h2`: independent worst-probability recovery;
- `aggregate_exact_period_scenarios_h2`: byte-exact D/A/C aggregation;
- `audit_flat_chi2_terminal_solution_h2`: probability, duality, objective, and recourse audit;
- `run_flat_chi2_terminal_case_h2`: state/R/eta/time-limit/output entry point.

All interfaces remain isolated under `terminalLoh_wdro/src/` and do not replace the frozen SAA, WDRO, MSP, path-generation, or validation code.
