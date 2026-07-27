# Step-03P D/A/C Formula and Literature Audit

## Current transport cost

For atoms r and s, the accepted code computes:

- `Delta_D(r,s)=sum_n |D_rn-D_sn|`.
- `Delta_A(r,s)=sum_i sum_n |A_rin-A_sin|`.
- `Delta_C(r,s)=sum_i sum_n 1(A_rin=1 and A_sin=1)|C_rin-C_sin|`.
- Each component is divided by its maximum pairwise value plus epsDistance when the maximum exceeds scaleTolerance.
- The accepted DAC weights are D/A/C=0.6/0.25/0.15.
- The formal code does not median-rescale the completed cost. Step-03P additionally divides every experimental variant by its own nonzero pairwise median so all ablations use the same median cost scale and rho=0.02 is comparable.

A is not duplicated by C. A records loss of service feasibility. C only compares difficulty where both atoms remain reachable. An A mismatch therefore cannot be converted into an ordinary large finite distance, and an unreachable arc cannot carry y in the loss LP.

## Scenario service loss

For scenario s, the recourse loss is `ell_s(T)=min sum_i,n C_sin*y_sin + M*sum_n u_sn`, subject to demand balance, `sum_n y_sin<=T_i`, and `0<=y_sin<=A_sin*D_sn`. D sets demand and arc bounds; A decides whether service is possible; C ranks the cost of reachable service; u is unmet hydrogen.

## D granularity

The four-region audit assigns each IEEE-33 node to the site with the shortest undamaged road-network distance, breaking ties by the lower site id. The resulting node-to-region map is:
`node 1 -> site 1`, `node 2 -> site 1`, `node 3 -> site 1`, `node 4 -> site 1`, `node 5 -> site 1`, `node 6 -> site 1`, `node 7 -> site 2`, `node 8 -> site 2`, `node 9 -> site 2`, `node 10 -> site 2`, `node 11 -> site 2`, `node 12 -> site 2`, `node 13 -> site 2`, `node 14 -> site 2`, `node 15 -> site 2`, `node 16 -> site 2`, `node 17 -> site 3`, `node 18 -> site 3`, `node 19 -> site 1`, `node 20 -> site 1`, `node 21 -> site 1`, `node 22 -> site 1`, `node 23 -> site 1`, `node 24 -> site 1`, `node 25 -> site 1`, `node 26 -> site 1`, `node 27 -> site 4`, `node 28 -> site 4`, `node 29 -> site 4`, `node 30 -> site 4`, `node 31 -> site 4`, `node 32 -> site 4`, `node 33 -> site 4`

## Mathematical terminology

D and A L1 components are metrics on their represented arrays. The C mask depends on the compared pair and can violate triangle inequality. Even if D and A happen to offset sampled C violations in a finite weighted matrix, the transport-cost function is not guaranteed to be a metric on the full D/A/C scenario space. Therefore a demonstrated masked-C violation requires the term optimal-transport DRO with a custom Kantorovich transport cost, not a strict Wasserstein metric.

## Literature positioning

- Blanchet, Kang, Murthy, and Zhang (2019), `Data-Driven Optimal Transport Cost Selection for Distributionally Robust Optimization`, WSC, DOI 10.1109/WSC40007.2019.9004785: transport cost should be validated against data and the downstream task. Step-03P applies this by checking D/A/C weights against loss and TerminalLOH effects.
- Bertsimas and Mundru (2023), `Optimization-Based Scenario Reduction for Data-Driven Two-Stage Stochastic Optimization`, Operations Research 71(4), DOI 10.1287/opre.2022.2265: scenario differences should preserve optimization-relevant cost and decision effects. Step-03P borrows the diagnostic principle but performs no scenario reduction.
- Zhang, Yang, and Gao, `A Short and General Duality Proof for Wasserstein Distributionally Robust Optimization`, Operations Research, DOI 10.1287/opre.2023.0135: the duality applies under general transport-cost conditions. Step-03P uses this distinction to separate a general Kantorovich cost from a strict metric claim.
