
# Extreme path provenance

Live inputs confirm a two-part source. The observed side is `terminalLoh_wdro\output\stage2b_tail_candidate_design\run-002\tail_pareto_candidate_paths.csv` (1595 labelled rows). The support-out side is `terminalLoh_wdro\output\stage2b_tail_candidate_design\run-004\reexported_unobserved_pareto_paths.csv` (2410 labelled rows). `run_stage2b_deduplicate_tail_paths_h2.m` groups the exact 12-field `(a, loc, lfw)` initial/W1/W2/W3 key and produces 1126 unique physical paths.

The four proxy fields are grid maximum wind, grid cumulative exceedance above 25 m/s, road maximum wind, and road cumulative exceedance above 30 m/s. Screening is state-specific at q95/q99/q99.5. Within each state, proxy, and level, Pareto retention favors lower theoretical path probability and higher proxy risk. No operating loss appears in the selection rule.

The candidate files retain the discrete path and theoretical `path_probability`; they do not retain a complete byte-exact formal three-period D/A/C realization. Historical Step-03B stores stage summaries and rounded signatures under `fixed_representative` wind, not the current formal `stagewise_random_triangular` input identity.
