# Stage-90A Terminal H2 Redistribution

Stage7 now has an isolated candidate implementation for one finite terminal
redistribution action. The accepted default is unchanged:

```text
terminal_recourse_mode = DIRECT_GAP
Q7(I,T) = 1000 * sum_i max(T_i - I_i, 0)
```

Candidate mode is selected explicitly with
`h2_stage90a_candidate_options(rootDir, K_terminal_kg)` defaults to the frozen
`K_terminal_kg = 160` kg. It solves a pure LP
over direct station-to-station shipments and residual site gaps after the
TerminalLOH target has been revealed. The LP is called by the same shared
Stage7 evaluator in forward, backward, and OOS paths; it is not OOS
post-processing.

## Human-readable answers

1. Pure-location penalty occurs because the old Stage7 checks each site
   independently and has no final spatial recourse; system-wide surplus cannot
   cover another site's gap.
2. Siddig & Song's terminal shipping is a formal post-revelation decision in
   their multistage stochastic program, not an after-the-fact metric.
3. We borrow the structural point that terminal shipping remains inside the
   terminal value function and therefore affects earlier policy through cuts.
4. We differ by redistributing H2 among four stations, with no road
   reachability, no demand-point routing, and one aggregate terminal capacity.
5. Variables are direct `x_ij` and residual `g_i`; objective is OD shipping
   cost plus 1000 yuan/kg residual gap; donor, gap-balance, and capacity rows
   enforce the physics.
6. Yes. It is a continuous LP with no integer or binary variable.
7. Yes. Its inventory value is convex piecewise linear.
8. The Stage6 slope is the sum of donor-row and gap-row RHS duals, in the
   four-site inventory order. The exact derivation is in
   `terminal_dual_derivation.md`.
9. Yes by design: forward, backward, and OOS call the same evaluator.
10. Existing HTT is `(1-beta)*160 kg` per formal ordinary hour/stage, with
    `160 = N_HTT*Q_HTT = 2*80`. The terminal candidate freezes an aggregate
    one-shot capacity of `K_terminal=160 kg`; it does not add a duration.
11. Yes. `TERMINAL_CAPACITY_MAPPING = FROZEN_AGGREGATE_160_KG`; the candidate
    uses the explicit frozen value and does not select a terminal duration.
12. The main risks are charging terminal shipping twice, or counting target
    construction as terminal shipping. The candidate does neither.
13. Yes. `K_terminal_kg=0` takes the old direct-gap branch exactly, verified in
    Unit Case D.
14. The existing four-dimensional state and zero-cut launch structure are
    present, but the new candidate has not been trained and no fresh
    zero-cut smoke was started.
15. Yes, Stage90B fresh zero-cut 10-iteration engineering smoke is the next step.

## Stage-90A labels

```text
TERMINAL_RECOURSE_FORMULATION = PASS
PURE_LP_STRUCTURE = YES
FORWARD_BACKWARD_CONSISTENCY_DESIGN = PASS
TERMINAL_DUAL_SUBGRADIENT = VERIFIED
K_TERMINAL_MAPPING = FROZEN_AGGREGATE_160_KG
ZERO_CAPACITY_BACKWARD_COMPATIBILITY = PASS
READY_FOR_STAGE90B_SMOKE = YES
```

`K_terminal=160 kg` is an explicit aggregate one-shot terminal action. It is
not an additional operating stage and does not use road-capacity degradation.

## Verification

`run_stage90a_terminal_recourse_tests.m` runs deterministic Cases A-I and
writes `unit_test_results.csv` plus `qa_summary.csv`. The current run is 9/9
PASS, with capacity non-truncation and over-capacity binding checks included,
and maximum finite-difference gradient error
`2.61934474110603e-09` and zero primal/dual-complementarity residuals in the
reported LP QA fields.
