
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

## 15. Step-04C-A2 formal consequence freeze and harm validation

Step-04C-A2 is accepted at `results/task-002-stage2b-b3-smoke/44-extreme-formal-consequence-freeze/run-003/` with mechanical audit `PASS`.

The 858 support-out paths were sorted by the exact 12-field physical key and assigned five deterministic conditional consequence replicas each. Namespace `STEP04CA2_SUPPORT_OUT_V1` therefore contains 4,290 identities. The mapping uses path rank, replica rank, fixed wind seed `1704202601`, fixed resistance seed `2704202601`, and joint stream position `5*(path_rank-1)+replica_rank`. The namespace has zero seed/stream identity collision with nominal, validation-1, or validation-2. Byte-exact replay, identity uniqueness, D/A/C domains, persistent damage, source-demand, reachability, and service-cost business-logic audits all passed.

The 268 support-in paths were replayed from their existing nominal formal identities. Against each path's one existing formal consequence realization, the historical composite proxy has Spearman `0.526366`, q95 hit rate `0.166667`, and obvious-false-positive share `0.416667`. The proxy is directionally informative but is not precise enough to serve as the final formal-loss ranking by itself.

Under the formal state-19 SAA TerminalLOH, 3,919/4,290 replicas and 787/858 paths satisfy the conservative verified-harm rule: theoretical path probability below `1/15000`, formal loss at or above the state-19 nominal q95, and positive shortage; a path must satisfy the replica rule in at least three of five replicas and have mean loss above the same q95. The support-out set is therefore formally harmful rather than merely proxy-high. The main failure mechanism is road-network interruption in 4,215 replicas.

State-19 SAA mean loss and shortage across the 4,290 replicas are `419577.004127` and `208.386979 kg`; the Step-04B DRO T values give `418595.750349` and `207.890628 kg`. DRO reduces loss on `21.5152%` of replicas and shortage on `7.4126%`; the two fixed decisions leave nearly the same zero-shortage share, so the existing DRO T is not a general extreme-path cure. All six state-19 support-in paths also retain complete SAA/DRO total and W1-W3 shortage detail; DRO improves formal loss on one and worsens none.

The five consequence replicas are frozen stress realizations, not empirical probabilities. No eta or epsilon was calibrated, no probability mass was assigned to the replicas, and no enhanced DRO or all-state optimization was run.

Classifications:

- `A. FORMAL_CONSEQUENCE_IDENTITIES_FROZEN`;
- `H-A. SUPPORT_OUT_EXTREMES_ACTUALLY_HARMFUL`;
- `A. PROCEED_TO_STEP04C_B_EXTREME_AWARE_DRO`.

The unique next task is Step-04C-B: define and audit the convex nominal chi-square plus frozen extreme-risk protection model while preserving the replicas as a separate stress set rather than empirical probability augmentation.

## 16. Step-04C-B accepted extreme-aware decision-value audit

Step-04C-B `run-014` is accepted as the first complete formal run at `results/task-002-stage2b-b3-smoke/45-extreme-aware-dro-decision-value/run-014/`. It used the frozen Step-04C-A/A2 inputs and existing audit definitions without assigning empirical probability mass to the frozen extreme replicas.

The isolated formal grid contains all 30 combinations of eta `{0,0.01}`, extreme-risk design `{R1_MAX,R2_TOPK_5PCT(k=2),R2_TOPK_10PCT(k=3)}`, and kappa `{0,0.001,0.005,0.01,0.05}`. Every combination was recomputed from scratch, certified by LB/UB bounds, and independently reevaluated at fixed TerminalLOH. All 30 optimization cases, all 30 fixed-T audits, and all six FULL_CAPACITY eta/risk audits passed. The maximum absolute and relative certificate gaps were `2.14564443012932e-05` and `1.40207029843264e-09`.

The nominal support remains the state-19 R=15000 set with 7334 byte-exact D/A/C groups. The extreme stress input contains only the 27 state-19 physical paths and 135 frozen consequence replicas selected by the Step-04C-B state-19 gate; the other-initial-state path count is zero.

The accepted decisions are:

- SAA: `T=[294.589913536808,138.832065024684,93.0093009300931,150]`, total `676.431279491585 kg`;
- pure chi-square at eta `0.01`: `T=[300,143.468740452331,100,150]`, total `693.468740452331 kg`;
- every positive-kappa extreme-enhanced solution coincides with its corresponding eta baseline;
- FULL_CAPACITY: `T=[300,200,100,150]`, total `750 kg`.

Across SAA, pure chi-square, every enhanced decision, and FULL_CAPACITY, the three extreme-risk values remain exactly `899141.407567379` for R1, `879011.626917991` for R2 with k=2, and `872171.138280415` for R2 with k=3. FULL_CAPACITY therefore provides zero recoverable-risk denominator. Headroom is zero and ClosedRatio is correctly undefined, rather than zero or a claimed numerical improvement.

The accepted mechanical/model status is `M-A. EXTREME_AWARE_CONVEX_MODEL_VERIFIED`. The computed decision-value and overall method candidates remain `V-C. EXTREME_RISK_LARGELY_IRREDUCIBLE_BY_TERMINALLOH` and `B. KEEP_EXTREMES_AS_STRESS_VALIDATION_AND_CALIBRATE_PURE_CHI2`. Accepting `run-014` confirms the run and evidence; it does not independently freeze those method candidates.

Development history remains local and is not part of the accepted Git archive. In particular, run-011 completed the 30 combinations but failed FULL_CAPACITY table assembly because of a 42/43-column mismatch; run-013 completed the 30 combinations, 30 fixed-T audits, and six FULL_CAPACITY audits but its finalizer rejected the valid all-zero recoverable denominator. Run-014 corrected both output defects and repeated all combinations from scratch.

## 17. Current decision boundary

Do not rerun Step-04C-B merely to reproduce the accepted grid. The next action requires the user's research judgment on whether to freeze the candidate conclusion, keep the extreme replicas as stress-validation evidence, and proceed with pure chi-square radius calibration and independent validation.

## 18. Step-04C-C1 accepted eta initial screening

Step-04C-C1 `run-003` is accepted at `results/task-002-stage2b-b3-smoke/46-flat-chi2-eta-calibration/run-003/`. It is a state-19-only initial screening of the pure flat Pearson chi-square radius, not a formal eta calibration.

The frozen grid is `eta={0,0.0001,0.0003,0.001,0.003,0.01,0.03,0.1}`. Every eta was optimized on the nominal R=15000 state-19 distribution in an isolated MATLAB process, then independently reevaluated at fixed TerminalLOH on nominal, validation-1, validation-2, and the isolated 27-path/135-replica state-19 stress set. All process exit codes, solver statuses, LB/UB certificates, probability recovery, strong duality, divergence, probability conservation, and formal three-period recourse residuals passed. No R-by-R matrix, Wasserstein solver, Step-04C-B extreme-aware solver, MSP, or other initial state was used.

The TerminalLOH decisions are:

- eta `0`: `[294.589913536808,138.832065024684,93.0093009300931,150]`, total `676.431279491585 kg`;
- eta `0.0001`: `[297.847966567418,137.998799867703,93.8425660904143,150]`, total `679.689332525535 kg`;
- eta `0.0003`: `[297.848292841337,137.999286473295,93.8422374510755,150]`, total `679.689816765707 kg`;
- eta `0.001`: `[298.697267638016,137.997293570043,93.8438898641278,150]`, total `680.538451072186 kg`;
- eta `0.003`: `[299.211738691929,137.483280118695,94.3580963878466,150]`, total `681.053115198470 kg`;
- eta `0.01`: `[300,143.468150246686,100,150]`, total `693.468150246686 kg`;
- eta `0.03`: `[300,153.848478776362,100,150]`, total `703.848478776362 kg`;
- eta `0.1`: `[300,174.391416112881,100,150]`, total `724.391416112881 kg`.

Eta zero returns to the Step-04B SAA reference with maximum TerminalLOH error `1.99e-13 kg` and objective error `1.73e-10`. Across the eight cases, the maximum absolute LB/UB gap is `1.23689203974209e-4`, the maximum relative gap is `9.76551225047717e-9`, the maximum strong-duality gap is `1.73167791217566e-9`, the maximum probability-sum residual is `4.39648317751562e-14`, and the maximum mechanical residual is `1.60071067512035e-10`. Positive eta cases use the requested divergence to numerical tolerance.

Validation-1 and validation-2 remain second-layer wind-speed and resistance redraws on the same typhoon paths. They are not independent-path out-of-sample samples. The 27 state-19 paths and 135 frozen consequence replicas remain a fixed reproducible stress set with no empirical probability and no contribution to the optimization objective. Their q95 and maximum operating loss remain exactly `820195.36161099` and `899141.407567379` for every eta, although mean stress loss falls gradually as inventory rises.

No eta is strictly dominated across every tracked nominal, redraw-validation, and stress metric. However eta `0.0001` and `0.0003` are effectively the same low-radius decision plateau. Eta `0.03` and `0.1` add `27.4172` and `47.9601 kg` relative to SAA while leaving stress q95 and maximum loss unchanged; their average validation CVaR99.5 improvements remain only `0.3868%` and `0.5928%`. The recommended two-point set for the next different-path-seed validation is therefore `{0.003,0.01}`: eta `0.003` is the upper edge of the at-most-5-kg inventory plateau, and eta `0.01` is retained only as the first capacity-binding structural-jump upper candidate.

Development history remains local. `run-001` stopped at eta `0.001` because the C1 outer certificate incorrectly required both absolute and relative gaps, even though the accepted Step-04B solver stops when either tolerance is met. `run-002` completed all cases mechanically but its automatic shortlist was too broad. `run-003` froze the corrected certificate and two-point screening rules before execution, repeated all eight eta cases from scratch, and reproduced run-002's non-runtime numerical results exactly.

## 19. Current decision boundary after Step-04C-C1

Formal eta is not frozen. Proceed to different typhoon-path random seeds using SAA plus eta `{0.003,0.01}`, followed by Markov transition-probability perturbation. Only after those two evidence layers may a formal eta be selected. Do not describe validation-1/2 as independent-path validation and do not use the frozen extreme replicas as empirical probability mass.

## 20. Step-04C-C2 accepted independent-path validation

Step-04C-C2 `run-002` is accepted at `results/task-002-stage2b-b3-smoke/47-flat-chi2-independent-path-validation/run-002/`. It evaluates three frozen C1 nominal-optimization decisions on three genuinely different state-19 typhoon-path Monte Carlo sets. The C2 sets are evaluation-only: TerminalLOH and eta were not optimized or selected on them, no chi-square worst probability was constructed, and CVaR appears only as an evaluation metric.

The frozen decisions are SAA eta `0`, `T=[294.589913536808,138.832065024684,93.0093009300931,150]`; eta `0.003`, `T=[299.211738691929,137.483280118695,94.3580963878466,150]`; and eta `0.01`, `T=[300,143.468150246686,100,150]`. They are byte-source-audited against C1 accepted `run-003` and remain fixed across all three C2 sets.

Namespace `independent-path-C2` freezes the following path/wind/resistance seeds:

- dataset 1: `98661732 / 59333257 / 1707588495`;
- dataset 2: `341739613 / 1254046069 / 1872944571`;
- dataset 3: `1766178367 / 619431891 / 538665406`.

Each dataset contains exactly 15000 scenarios with separate weights `1/15000`. The three sets are not pooled or reinterpreted as one probability distribution. All seeds are distinct and collision-free against the accepted main/convergence path streams, Step-03J nominal/validation streams, and Step-04C-A2 wind/resistance streams. Two complete generations of each dataset match on physical-path sequence and all formal consequence hashes.

No dataset exactly reuses the nominal path batch or another C2 batch. Same-position path matches against nominal are only `4`, `10`, and `0`; because the path support is discrete, around `59%` of rows have a physical path value that also occurs somewhere in nominal. This ordinary support overlap is reported separately and is not called a random-stream collision. None of the three C2 sets contains any of the 27 fixed state-19 A2 pressure paths.

All nine fixed-T recourse evaluations are `OPTIMAL`; the maximum mechanical residual is `5.11590769747272e-13`. The key seedwise `(mean total cost, mean shortage kg, q99.5 loss, CVaR99.5 loss)` results are:

- dataset 1: SAA `(11693.786461,4.720568,278961.188361,396783.160623)`; eta 0.003 `(11689.444935,4.713680,277243.358358,396370.687006)`; eta 0.01 `(11682.601102,4.697828,277243.358358,395801.459711)`;
- dataset 2: SAA `(11220.198642,4.489693,262951.013517,361437.221483)`; eta 0.003 `(11221.061242,4.485483,262951.013517,361352.370944)`; eta 0.01 `(11226.968236,4.476177,262779.597273,360587.344598)`;
- dataset 3: SAA `(11122.897910,4.443133,248516.182252,358576.156349)`; eta 0.003 `(11127.247526,4.440681,248516.182252,358560.800963)`; eta 0.01 `(11133.674598,4.431552,248516.182252,357516.630150)`.

Within every dataset, candidate-minus-SAA paired operating-loss and shortage mean differences have 95% CIs below zero. Total-cost results are mixed. Eta 0.003 gives total-cost differences `-4.3415 [-10.1395,1.4564]`, `+0.8626 [-4.0316,5.7568]`, and `+4.3496 [0.5763,8.1229]`; eta 0.01 gives `-11.1854 [-25.5022,3.1315]`, `+6.7696 [-3.3106,16.8498]`, and `+10.7767 [1.0931,20.4603]`.

Both candidates reduce mean shortage and CVaR99.5 on all three seeds, but the gains are small. Eta 0.003 adds `4.621835706886 kg` and changes q99.5 on only one seed; eta 0.01 adds `17.036870755101 kg` and changes q99.5 on two seeds. Mean total cost worsens on two seeds for each candidate, and eta 0.003 slightly worsens dataset-2 maximum loss/shortage. The accepted C2 candidate judgement is option 4: neither candidate shows sufficient stable value to justify selection; return to SAA or recheck the radius range. This is not a formal eta freeze.

Development `run-001` remains local and preserved. Its three dataset preparations passed, but the first fixed-T process was rejected by an over-strict `1e-14` floating weight-sum tolerance. `run-002` froze `1e-12`, regenerated all three datasets from scratch, and passed all processes. Full MAT/scenario/paired files remain local and are recorded by size and SHA-256 in the accepted large-file manifest.

## 21. Current decision boundary after Step-04C-C2

Formal eta remains unfrozen and Markov transition-probability perturbation has not been performed. C2 does not support advancing eta `0.003` or `0.01` as the selected radius: the robust candidates buy consistent but very small mean-shortage/CVaR reductions, with mixed mean cost and limited quantile movement. Before Markov perturbation, decide whether to carry SAA as the primary reference or reopen the eta range; do not silently select either C1 candidate.
