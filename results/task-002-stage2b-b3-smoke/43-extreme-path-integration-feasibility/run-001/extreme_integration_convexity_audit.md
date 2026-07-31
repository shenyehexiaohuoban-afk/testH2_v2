
# Convexity audit

For each fixed formal scenario, the frozen recourse value `Q_e(T)` is convex in TerminalLOH because its LP dual represents it as a supremum of affine functions of `T`. Therefore a nonnegative weighted sum with the existing chi-square risk remains convex. `max_e Q_e(T)`, the sum/mean of the k largest convex scenario losses, and CVaR of convex losses are convex epigraph constructions.

This mathematical result does not authorize implementation with the current 858 paths: their formal scenario functions `Q_e(T)` are undefined until frozen three-period D/A/C and random-stream provenance are supplied.
