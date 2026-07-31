# Step-04B flat chi-square production solver

The production solver uses the frozen formal three-period recourse, equal empirical record mass, byte-exact D/A/C aggregation, an O(R) convex QCP, direct SAA at eta zero, and independent fixed-T probability recovery. No path probability is reused and no R-by-R matrix is constructed.

State 19 R=15000 has 7334 exact groups from 15000 original records.

- eta 0: status OPTIMAL, T=[294.589914, 138.832065, 93.009301, 150.000000], objective 11444.877596769, dual gap 7.28e-12.
- eta 0.01: status OPTIMAL, T=[300.000000, 143.468740, 100.000000, 150.000000], objective 15303.401209824, dual gap 1.56e-10.

Solver classification: `A. FULL_R15000_FLAT_CHI2_SOLVER_VERIFIED`.

Unique next task: **Step-04C: chi-square radius calibration, independent OOS validation, and Markov transition probability perturbation stress tests**.

Protected tracked files unchanged: true. Historical untracked status preserved: true. No OOS superiority is claimed and no formal eta is selected.
