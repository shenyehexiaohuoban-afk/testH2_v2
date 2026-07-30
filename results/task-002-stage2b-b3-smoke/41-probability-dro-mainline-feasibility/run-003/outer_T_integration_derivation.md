
# Outer TerminalLOH integration derivation

For scenario `r`, the frozen recourse LP value `Q_r(T)` is convex and nonincreasing in the four capacity right-hand sides `T`. The flat Pearson chi-square risk has the exact f-divergence dual

`min_{lambda>=0, nu} nu + lambda*eta + sum_r q_r*lambda*f*((Q_r(T)-nu)/lambda)`,

where `f(t)=(t-1)^2` for `t>=0` and

`f*(s) = -1 + (max(s+2,0))^2/4`.

Introduce `t_r >= Q_r(T)-nu+2*lambda`, `t_r>=0`, `h_r>=0`, and the rotated-cone constraint `t_r^2 <= 4*lambda*h_r`. Because `sum q_r=1`, the risk epigraph objective is

`nu + lambda*(eta-1) + sum_r q_r*h_r`.

The formal recourse primal variables can be included directly. Set `z_r` equal to each scenario operating cost and use `z_r` in the cone inequality. The robust objective is increasing in `z_r`, so minimization selects optimal recourse without a bilevel problem. This gives a strict single-level convex QCP/SOCP with no integer variables and no scenario-pair matrix.

Route A (recommended): extensive-form flat SOCP/QCP for small/medium R, with one common T, scenario recourse, and O(R) probability-dual cone blocks.

Route B: L-shaped/Benders decomposition. The master contains T and the chi-square risk epigraph; recourse cuts expose each convex Q_r(T). This is the recommended scaling architecture for R=15000 if the extensive form is too large.

Route C: an outer-T/adversarial-probability/recourse constraint-generation loop is possible, but convergence must be based on valid convex cuts. A heuristic alternating method is not acceptable as exact DRO.

For the structured rectangular tree, the same conjugate construction can be applied at every parent, recursively. The local risk maps are monotone and convex, so nested composition preserves convexity. The mathematical integration is available, but the recovered node-level probability estimates are statistically weak; that—not convexity—is the current structured blocker.
