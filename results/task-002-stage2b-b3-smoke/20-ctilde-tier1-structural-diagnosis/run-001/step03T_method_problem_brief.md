# Step-03T Method Problem Brief

## Directly supported diagnosis

The frozen Tier-1 records and selected exact replays show that small d_new can coexist with non-substitutable TerminalLOH layouts when demand location, reachability, station identity, exclusive coverage, service redundancy, or reachable-road ranking changes jointly.
The diagnostic features are explanatory only. This audit does not define, recommend, or implement a replacement distance.
Representative family counts: service coupling=15, spatial demand=0, capacity switching=0, aggregation/scale=0, mixed=3.
Tier-1 raw rows=7733, unordered unique pairs=6321, unique scenarios=3383.
After removing the top 10% highest-frequency scenarios, the remaining pair share is 0.516100 across 6 states.

## Features separating substitutable and non-substitutable neighbors

The descriptive comparison is archived in step03T_tier1_control_comparison.csv. Its fixed fields include demand relocation, changed reachability weighted by demand, exclusive/shared/unreachable demand, best-site identity, impedance ranking, T differences, and bidirectional regret.
The comparison table contains 15 predefined diagnostic metrics.
No classifier, regression, fitted parameter, validation sample, or weight scan is used.

## Problems a later method must resolve

1. Preserve node demand location relevant to the four-station layout.
2. Preserve the joint relationship between demand, reachability, station identity, exclusive coverage, and service redundancy.
3. Preserve consequential changes in best and second-best reachable service options without treating unreachable demand as an ordinary long-distance relation.
4. Distinguish genuine service-structure changes from capacity or optimization boundary effects.
5. Avoid suppressing consequential local relationships through fixed aggregation scales.

## Minimum mathematical properties

A later candidate must retain nonnegativity, symmetry, zero-distance equivalence, triangle inequality, and a scenario-independent fixed scale. It must remain usable by exact constraint generation and must not depend on validation data.

## Computational limits

A later candidate must not solve an optimization model inside every scenario-pair distance, materially expand the formal WDRO variables or constraints, require an in-memory R-by-R matrix, require regeneration of Step-03J, or tune against validation data.

## Current conclusion

A. SERVICE_COUPLING_OMISSION_DOMINANT

The current fixed constants remain kappa=1, D/Ctilde weights=0.6/0.4, and C_bound=357.1526447416079. They are not modified here.
