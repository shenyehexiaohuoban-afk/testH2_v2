
# Probability DRO Mainline Handover

## 1. Original objective

For each typhoon initial state, choose one pre-disaster four-site TerminalLOH vector shared by all possible paths. After a complete three-period path is realized, optimize the frozen joint W1-W3 service and shortage recourse.

## 2. Frozen operational model

The formal model remains the **two-stage three-period operational model under full scenario information**. W1-W3 jointly consume one TerminalLOH reserve. No scenario-tree operating decisions or nonanticipativity constraints are introduced. The probability tree described below is only a probability factorization device.

## 3. Data structure

There are 35 initial states and exactly 15,000 conditional Monte Carlo records per state. Each path contains exact discrete `(a,loc,lfw)` states for W1-W3 and complete three-period D/A/C consequences.

## 4. Why the Wasserstein ground-cost line stopped

The corrected demand scale is mathematically valid, but fixed-T loss alignment remains poor. Simple separable D/A/C matrix distance does not represent station identity, substitute service, reachability, and shared-inventory coupling. Existing WDRO code/results remain historical comparison evidence.

## 5. Prohibited ground-cost work

Do not tune Dscale, Cscale, 0.6/0.4 weights, restore a separate A term, add S/G/artificial features, or infer a transport distance from operating losses.

## 6. New mathematical objective

Optimize `gamma*sum(T) + sup_p sum_r p_r Q(T,xi_r)` over a Pearson chi-square ambiguity set on finite observed path probabilities, without any path-pair distance.

## 7. Structured versus flat

Structured conditional DRO perturbs each parent conditional distribution independently and reconstructs leaf probabilities by products. Flat DRO perturbs the complete observed leaf/record probability vector directly. The native tree exists, but late-node statistical support is weak; flat chi-square is the selected mainline.

## 8. Step-04A scope

This step recovers provenance and trees, verifies probability factorization, implements deterministic probability-layer solvers, tests real fixed T on R=200 subtrees, derives outer integration, and runs only an isolated R=100 end-to-end prototype.

## 9. Step-04B to Step-04E

- Step-04B: implement the production flat SOCP/QCP solver and decomposition architecture.
- Step-04C: calibrate eta using training, validation, and independent OOS paths.
- Step-04D: compare weighted SAA, mean-CVaR, flat chi-square DRO, optional structured diagnostic, and historical Wasserstein results.
- Step-04E: freeze the method only after OOS validation; Word and literature work remain outside Codex's current scope.

## 10. Open questions

Formal eta calibration, production R=15,000 decomposition tolerances, and treatment of theoretical positive paths absent from the stored consequence support remain unresolved.

Current classification: `S-C. TREE_RECOVERABLE_BUT_STATISTICALLY_WEAK`; `F-A. FLAT_CHI2_DRO_FEASIBLE`; `B. FLAT_CHI2_DRO_MAINLINE_FEASIBLE`.

## 11. Step-04B production solver result

Step-04B is accepted at `results/task-002-stage2b-b3-smoke/42-flat-chi2-dro-production-solver/run-003/` with `A. FULL_R15000_FLAT_CHI2_SOLVER_VERIFIED`.

The production implementation provides:

- direct weighted SAA for `eta=0`;
- the exact conjugate/rotated-cone QCP for small and medium exact support;
- a certified large-support convex cutting-plane decomposition with explicit lower and upper bounds;
- byte-exact aggregation over every formal three-period D/A/C input;
- independent fixed-T recourse, probability, divergence, strong-duality, and objective reconstruction audits;
- a unified state/R/eta/time-limit/output MATLAB entry point.

For state 19 at original `R=15000`, byte-exact D/A/C aggregation produced `7334` groups from `15000` records, with zero hash-collision splits. The grouped and ungrouped fixed-T and outer objectives passed numerical equivalence checks. No `R x R` scenario matrix was constructed.

The formal state-19 results are:

- SAA: `T=[294.589913536808, 138.832065024684, 93.0093009300931, 150]`, total `676.431279491585 kg`, complete objective `11444.8775967693`;
- flat chi-square test at `eta=0.01`: `T=[300, 143.468740452331, 100, 150]`, total `693.468740452331 kg`, worst expected recourse `13916.4637289198`, complete robust objective `15303.4012098245`.

The `eta=0.01` value is an implementation test radius, not a calibrated formal radius. Step-04B makes no out-of-sample superiority claim.

## 12. Unique next task

Proceed only to **Step-04C: chi-square radius calibration, independent OOS validation, and Markov transition probability perturbation stress tests**. Do not return to Wasserstein ground-cost tuning and do not run all 35 final states before Step-04C defines the validation protocol.

## 13. Step-04C-A support-out extreme-path audit

Step-04C-A is archived at `results/task-002-stage2b-b3-smoke/43-extreme-path-integration-feasibility/run-001/` with mechanical audit `PASS`.

Live source/data reconstruction confirmed:

- 1,595 observed and 2,410 unobserved proxy/quantile-labelled Pareto records, 4,005 rows total;
- exact 12-field physical-path deduplication yields 1,126 unique paths and removes 2,879 repeated proxy/level labels;
- all 1,126 paths are legal positive-probability Markov paths;
- exact nominal path overlap is 268 support-in paths and 858 support-out paths, with no physical-path duplicates;
- recomputed path probability matches the stored value with maximum absolute error `1.0164395367051604e-20` and maximum relative error `3.6642270354059247e-15`.

The selected-path probability sums are conditional theoretical mass for a directed proxy-selected subset. They are not a complete extreme-event probability, cannot be summed across initial states without an initial-state distribution, and do not replace equal empirical nominal record weights.

The support-out paths do not have the frozen `path_id`, `joint_stream_position`, wind stream, and resistance stream identity required by the formal three-period D/A/C replay. Historical Step-03B used fixed representative wind and retained summaries plus six-decimal consequence signatures rather than byte-exact formal three-period D/A/C arrays. Therefore no formal recourse harm evaluation, exact formal D/A/C duplicate audit, or state-19 enhanced solver prototype was run. No eta or epsilon was selected.

The mathematical candidate remains a convex combination of the existing nominal chi-square risk and a separately defined support-out extreme risk, preferably extreme maximum first. Equal-weight append and direct theoretical-path-probability append are rejected.

Classifications:

- `E-D. INPUT_OR_PROVENANCE_UNRESOLVED`;
- `I-B. FIXED_T_ONLY_FULL_INTEGRATION_UNRESOLVED`;
- `C. RESOLVE_EXTREME_INPUT_OR_PROBABILITY_FIRST`.

## 14. Superseding unique next task

Before any extreme-aware calibration or optimization, define and freeze a non-random, auditable mapping from every selected support-out path to formal stagewise wind quantiles, persistent resistance draws, and complete byte-exact three-period D/A/C. The design must also state whether the paths are deterministic stress scenarios or part of a probability-complete stochastic augmentation. Only then run fixed-T harm evaluation and the state-19 extreme-max prototype.
