
# Candidate integration models

## A. Equal-weight append

Not recommended. Appending 858 support-out paths to 15000 nominal records with equal record weight would assign them `858/(15000+858)=5.41051835%` total mass solely because 858 paths were selected. That is a selection-count artifact, not a probability estimate.

## B. Direct theoretical-probability append

Not recommended as a nominal distribution. The set is selected by proxy-tail/Pareto rules and is not a complete event partition. Its conditional theoretical path masses are incompatible with the empirical record measure unless the entire discrete-path/damage probability model is rebuilt consistently.

## C. Chi-square nominal risk plus support-out protection

Recommended mathematical candidate after formal support-out consequences are defined:

`c(T) + (1-epsilon) rho_chi2_eta(Q_nominal(T)) + epsilon R_extreme(Q_extreme(T))`.

Use `max` first; consider top-k mean or extreme CVaR only if one verified path dominates. Epsilon is a behavior/protection parameter, not an estimated probability.

## D. Extreme shortage constraints

Potentially useful after formal scenario inputs exist. The shortage quantity must be modeled with an unambiguous convex recourse definition; a post-hoc shortage extracted from one of multiple cost-optimal recourse solutions is not a safe constraint definition.
