
# Statistical feasibility of the native prefix tree

The exact discrete `(a,loc,lfw)` representation produces a real shared-prefix tree; no rounding, clustering, D/A/C merging, or loss-based merging was used. However, the tree is statistically sparse near the leaves. Across stage-2 parents, `80.5505%` have fewer than 10 supporting records and `38.3160%` have exactly one supporting record.

Answers to the required feasibility questions:

1. A meaningful native shared-prefix tree exists: **yes, mechanically**.
2. Data are sufficient to estimate every node conditional reliably: **no**.
3. Independent radius calibration for every node is suitable: **no**.
4. Stage-shared radii may be considered later: **possibly, but require validation/calibration data**.
5. A global shared radius is the only currently defensible structured simplification: **more defensible than node-specific radii, but still uncalibrated**.
6. The structured route should not be the formal mainline now: **yes**. Use flat finite-support chi-square DRO as the unique Step-04B direction while retaining the tree prototype as a diagnostic.

No clustering, smoothing, pseudocount, shrinkage, or artificial node merge was implemented.
