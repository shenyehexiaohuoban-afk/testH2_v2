# Step-03Q Metric Proof

Let U contain one unreachable symbol and reachable values c in [0,1], where c=C/C_bound. Define delta(U,U)=0, delta(c1,c2)=|c1-c2|, and delta(U,c)=delta(c,U)=kappa.

Nonnegativity, symmetry, and identity are immediate. For the triangle inequality:

1. All three reachable: ordinary absolute distance on [0,1] satisfies the triangle inequality.
2. All three unreachable: every term is zero.
3. One unreachable and two reachable: the only nontrivial inequality is |c1-c2| <= 2*kappa. Since |c1-c2|<=1, this holds for kappa>=0.5. The other orientations reduce to kappa<=kappa+|c1-c2|.
4. Two unreachable and one reachable: the nonzero direct distance is kappa and the two-leg alternatives are kappa or 2*kappa, so the inequality holds.

Therefore every local delta is a metric for kappa>=0.5. The mean of 132 local metrics is a metric on the Ctilde representation. The normalized node-demand L1 distance is also a metric under its fixed positive scale. A positive weighted sum with w_D>0 and w_Ctilde>0 is a metric on the joint (D,Ctilde) representation. Positive audit median scaling preserves all metric axioms.

Tested kappa values: 0.5, 1, 1.5. C_bound=357.1526447416079 km ensures every reachable normalized C lies in [0,1].
