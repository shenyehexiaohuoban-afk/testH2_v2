
# Recommended solver architecture

Use **flat finite-support Pearson chi-square DRO with a convex single-level SOCP/QCP**, first at R=200/500 and then with an L-shaped/Benders implementation for R=15000. The formulation has O(R) probability-risk blocks and avoids every R-by-R scenario pair.

Do not promote the structured conditional model to the formal mainline. The native tree exists, but stage-2 parents with fewer than 10 records account for `80.5505%` and singleton parents account for `38.3160%`. Retain structured recursion as a diagnostic and reconsider it only if probability support or a justified pooling/calibration scheme is supplied.
