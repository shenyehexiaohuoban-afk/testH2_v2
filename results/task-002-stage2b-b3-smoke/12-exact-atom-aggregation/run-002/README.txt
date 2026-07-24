Step-03L run-002: exact WDRO atom aggregation audit

A=0 reconciliation
Step-03I reported 0.079234760 from W1-W3 stage-pair A0 share with denominator R*3*4*33.
Step-03K reported 0.120302554 for nominal from WDRO aggregated-atom A0 share with denominator R*4*33.
Recommended names keep these dimensions explicit; no accepted historical result is overwritten.

Exact equivalence
The key contains all 33 D doubles, all 132 A values, and all 132 C doubles after only A=0/nonfinite positions are set to zero exactly as the current masked-C logic excludes them.
No rounding, tolerance grouping, summary-field grouping, clustering, or scenario deletion is used.
Each class representative is an actual source record. Class weight is class_size/15000 and the complete original-path mapping is retained locally.

Solver capability
The loader reads sample_weight, but solve_wdro_terminal_loh_lp_h2 has no weight argument and fixes obj(alpha)=1/R.
Therefore the exact aggregated data are audit-only and cannot become formal WDRO input without a separately authorized solver weight-interface change.
No Gurobi comparison is run in Step-03L.

K_exact min/mean/median/q95/max = 116/7100.343/8433/14550.600/14609.
Maximum aggregate metric preservation error = 4.3769432522822171e-12.
Maximum relative preservation error = 5.9209670220810312e-14; pass rule is abs error <= 1e-13*max(1,abs(value)).
Decision: EXACT_AGGREGATION_STILL_TOO_LARGE
Exact aggregation is valid, but at least one K_exact remains above Step-03K measured R=1000.

The exact aggregated CSV/MAT files and 525000-row mapping remain local. Git should contain only this run's summaries, schema, manifest, and SHA-256 values.
This run does not implement approximate reduction, tail sampling, clustering, constraint generation, solver refactoring, formal WDRO, Gurobi, or MSP.
