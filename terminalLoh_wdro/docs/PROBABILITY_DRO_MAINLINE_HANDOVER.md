
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

## 22. Step-04C-C3 accepted Markov transition-probability perturbation diagnostic

Step-04C-C3 `run-001` is accepted at `results/task-002-stage2b-b3-smoke/48-markov-transition-perturbation/run-001/`. It evaluates the three frozen C1 decisions on state19 only. TerminalLOH was never reoptimized on C3 data, the chi-square adversary was not constructed, and CVaR is an evaluation metric only.

The frozen decisions remain:

- SAA eta `0`: `T=[294.589913536808,138.832065024684,93.0093009300931,150]`, total `676.431279491585 kg`;
- eta `0.003`: `T=[299.211738691929,137.483280118695,94.3580963878466,150]`, total `681.053115198470 kg`;
- eta `0.01`: `T=[300,143.468150246686,100,150]`, total `693.468150246686 kg`.

The seven distribution scenarios are nominal; intensity-only/location-only/lfw-only at delta `0.05`; and combined mild/medium/strong at delta `0.02/0.05/0.10`. Every matrix row uses `P_delta=(1-delta)P_nominal+delta*P_stress`, stays on original positive support, remains nonnegative and normalized, and leaves deterministic rows unchanged. The maximum row-sum error is `1.33226762955019e-15`; support, formula, and deterministic-row errors are zero.

Location perturbation was not blocked. Before C3 outcomes were observed, the repository's accepted Wstep=40 fixed geometry was converted to a location-only exposure ordering by equally averaging `d_system_min` over lfw `0:3`; smaller mean distance is higher exposure. The resulting highest-risk order begins `loc=3,2,4,1,0`. The rule uses no TerminalLOH, loss, or C3 result.

Namespace `markov-perturbation-C3` freezes three path/wind/resistance seed triplets:

- seed 1: `1113527767 / 664410789 / 1303781022`;
- seed 2: `326796064 / 69348633 / 697256691`;
- seed 3: `1029622182 / 840401885 / 272840227`.

All seeds are collision-free against the audited historical namespaces. Each distribution-seed dataset has exactly 15000 state19 scenarios with a separate `1/15000` probability law. Within a seed, all seven distributions reuse identical path-uniform blocks and identical wind/resistance streams for common-random-number pairing; the three seed triplets are independent. Every path and formal D/A/C generation was replayed exactly. No whole path batch reused nominal, C2, or another C3 distribution unchanged.

All 63 fixed-decision evaluations are `OPTIMAL`, and the maximum formal three-period recourse residual is `5.6843418860808e-13`. Actual transition frequencies contain no transition outside original support. The only 21 unvisited row-frequency cases are location `from_state=-2`, which can first appear only at the final W3 state from state19 and therefore has no outgoing transition inside the modeled horizon.

For both eta candidates, paired mean operating-loss and shortage differences have 95% intervals below zero in all 21 distribution-seed cells. However, the additional inventory is not economically recovered consistently across perturbation directions:

- total-cost paired intervals are below zero in 13/21 cells for each candidate;
- all three seeds show significant total-cost improvement for intensity-only, combined-mild, combined-medium, and combined-strong;
- nominal and location-only do not recover the inventory cost; lfw-only does so on only one seed;
- mean total-cost, operating-loss, and shortage advantages grow monotonically along nominal -> combined mild -> combined medium -> combined strong for both candidates and all three seeds;
- q99.5 and CVaR99.5 advantages do not increase monotonically.

Across seeds, eta `0.003` mean total-cost changes versus SAA are `-25.3588` for intensity-only, `-13.8174/-29.9038/-63.3130` for combined mild/medium/strong, and `-0.0292/+0.2594/-5.8598` for nominal/location-only/lfw-only. Eta `0.01` changes are `-59.6087`, `-29.6933/-83.6070/-174.7311`, and `+7.7443/+5.7130/-11.0688`, respectively. Negative means the candidate is cheaper than SAA after inventory cost.

The accepted C3 judgement is option 4. Pearson chi-square decisions show real operating-risk value, especially under intensity and combined probability shifts, but do not show enough cross-direction total-economic stability to select eta or justify continuing the chi-square mainline. Formal eta remains unfrozen. The recommended formal reference is SAA unless the research question is explicitly redesigned.

## 23. Current decision boundary after Step-04C-C3

The planned C1 initial screening, C2 independent-path validation, and C3 Markov probability perturbation layers are complete. C1 identified `{0.003,0.01}` only as validation candidates; C2 found consistent but small risk reductions with mixed total cost; C3 found stronger risk and economic value under intensity/combined shifts but not under nominal/location-only shifts. Do not freeze either eta. The current recommendation is to stop the Pearson chi-square selection mainline and return to SAA as the formal state19 reference. Any further eta or ambiguity-set work requires a new, explicitly authorized research question rather than an automatic continuation.

## 24. Step-04C-C4 accepted parameter provenance and resilience audit

Step-04C-C4 accepted `run-004` is at `results/task-002-stage2b-b3-smoke/49-parameter-provenance-resilience-audit/run-004/`. This step is a deterministic read-only audit of the frozen C1/C2/C3 decisions and results. It did not optimize TerminalLOH, select eta, change formal recourse, run the MSP, or change any historical input/output. Development `run-001` is preserved as failed because its first provenance table did not explicitly enumerate every requested absent/unmodeled parameter. `run-002` corrected the coverage and passed its CSV checks but retained a wrong README run label. `run-003` corrected self-identification but retained generic source labels for three absent parameters. `run-004` anchored those absence findings to exact implemented balance/objective paths and repeated the full audit from scratch.

The current offline objective is:

`gamma*sum_i(T_i) + sum_{tau,i,n} C_i,n^tau*y_i,n^tau + M*sum_{tau,n} u_n^tau`.

The effective `M=2000` comes from `NearStageInput.Cost.reserve_shortage_penalty_yuan_per_kg`. Its field name declares yuan/kg, but no engineering source was found for the numeric calibration. The effective `gamma=2` is derived as `0.001*M` and is explicitly documented as a small configurable TerminalLOH holding weight, not MSP hydrogen-production cost. Because `C` is shortest-path distance in km and enters directly as `C*y` with no monetary conversion, the complete offline objective has mixed model units. Do not describe gamma as `2 yuan/kg` or the offline total cost as a verified currency amount.

The eta `0.01` decision adds `17.0368707551011 kg` relative to SAA, so its direct offline increment is exactly `34.0737415102021` objective units at gamma `2`. This increment does not cover MSP electricity production, electrolyzer O&M, HTT transport, ordinary inventory holding, normal-H2 shortage, storage loss, or salvage. The audited MSP separately contains electricity prices `0.3-0.98 yuan/kWh`, electrolyzer O&M `0.012 yuan/kWh`, holding `0.05 yuan/kg`, normal shortage `200 yuan/kg`, HTT transport `0.8 yuan/(kg*km)`, beta transport multiplier `2`, and reserve shortage `2000 yuan/kg`. Storage/boil-off loss, external H2 purchase, terminal surplus salvage, and electric VOLL are absent.

The formal consequence conversion is active and auditable: each of three one-hour periods uses `D=outage*P_load_base/(eta_FC*LHV)`, with `eta_FC=0.55`, `LHV=33.33 kWh/kg`, and total base load `3715 kW`. Therefore shortage may be converted back as `18.3315 kWh` of repository-model-equivalent unrestored energy per kg H2 shortage. This supports equivalent EENS and restored-energy comparisons inside the model convention. It is not a currency valuation and does not establish that the separate critical-load template or a complete power-system restoration model is represented.

The seedwise fixed-decision break-even coefficient is `gamma_break_even=(SAA operating loss - candidate operating loss)/(candidate inventory - SAA inventory)`. It is an ex-post threshold, not a reoptimized sensitivity. Under C3, both candidates have positive operating-loss and shortage improvements in all 21 distribution-seed cells. At gamma `2`, eta `0.003` is no more expensive than SAA in `18/21` cells and eta `0.01` in `15/21`. Nominal break-even ranges are `1.643969-2.613615` and `1.403499-1.641199`; combined-strong ranges are `14.935213-16.909684` and `11.048791-12.926954`, for eta `0.003` and `0.01` respectively. Full seedwise and per-distribution min/mean/max values are frozen in the accepted CSVs.

## 25. Current decision boundary after Step-04C-C4

C4 changes the interpretation of the existing evidence, not the frozen decisions. Pearson chi-square inventories consistently reduce modeled operating loss and shortage, and their value becomes much stronger under intensity and combined Markov shifts. However, the current offline total is not a verified monetary system cost, and extra TerminalLOH cost cannot be reduced to `2 yuan/kg` or `34 yuan` without additional calibration and MSP integration.

Retain eta `0.003` as a mild resilience alternative and eta `0.01` as a conservative upper resilience alternative for transparent comparison, but do not freeze either as the formal eta and do not claim that DRO全面优于SAA. SAA remains the formal state19 reference under the current evidence. Reopening the chi-square selection mainline requires an explicitly authorized research question plus monetary calibration for preload/service terms, storage loss/salvage assumptions, and a documented link from reserve shortage to electric VOLL. TerminalLOH inventory also cannot replace road restoration, network hardening, or other resilience measures.

## 26. Step-04C-C5B accepted unified-economic state19 recalculation

Step-04C-C5B accepted `run-003` is at `results/task-002-stage2b-b3-smoke/51-unified-economic-terminal-loh/run-003/`. It independently reoptimizes state19 SAA and flat Pearson eta `0.003/0.01` under a yuan-consistent primary objective. It does not run the MSP, modify the historical formal solvers, change D/A/C, use validation data for optimization, use the old Wasserstein route, or run other initial states.

The frozen economic conversion is:

- live MSP 24-hour electricity price min/max/mean: `0.3/0.98/0.634166666666667 yuan/kWh`;
- `k_H2=0.0195 kg/kWh`, so `SEC_H2=51.2820512821 kWh/kg`;
- local preparation cost `c_H2=32.5213675214 yuan/kg`; no repeated eta-EL multiplication;
- `LHV=33.33 kWh/kg`, `eta_FC=0.55`, so `18.3315 kWh/kg-H2`;
- VOLL-derived shortage penalty `M_H2=70*18.3315=1283.205 yuan/kg-H2`.

The primary objective contains only `c_H2*sum(T)` and expected/worst-case `M_H2*shortage`. `C*y` is not currency, transport cost, or Pearson loss. A strict second LP fixes each scenario's primary-optimal shortage by equality and then minimizes `sum(C*y)`; the maximum observed shortage-preservation error is `1.1368683772e-13 kg`.

The new decisions are:

- SAA: `T=[222.840465864768,119.193737555574,36.003600360036,133.376974061042]`, total `511.414777841420 kg`;
- eta `0.003`: `T=[225.290752999455,121.925712142017,41.462552723036,137.464508019752]`, total `526.143525884259 kg`;
- eta `0.01`: `T=[226.659147502450,121.966076719698,44.414041094008,139.650354720371]`, total `532.689620036528 kg`.

No site reaches capacity. Relative to SAA, eta `0.003` adds `14.728748042839 kg` and `478.999028 yuan` preparation cost; eta `0.01` adds `21.274842195108 kg` and `691.886962 yuan`. On nominal state19, their mean EENS reductions are `6.362986918676` and `8.915826503816 kWh`, with economic premiums `33.589944` and `67.779107 yuan`. Their nominal incremental costs per additionally restored kWh are `5.278959` and `7.602111 yuan/kWh`.

Both candidates reduce mean EENS in all 25 empirical validation cells: state19 nominal, all three separate C2 independent-path sets, and all 21 C3 distribution-seed cells. C2 and C3 nominal/location-only cells retain small positive economic premiums. Intensity-only and combined mild/medium/strong cells are economically favorable for both candidates on every seed. Under combined-strong, mean changes across seeds are eta `0.003`: `-19.110154 kWh` EENS and `-858.711741 yuan`; eta `0.01`: `-27.005124 kWh` and `-1198.471740 yuan`.

The state19 fixed pressure set remains a 27-path/135-replica descriptive stress test with no empirical probability. Eta `0.003/0.01` reduce q95 shortage by `4.913443/7.864932 kg`, but maximum shortage is unchanged at `449.226740855904 kg`. This is continuing evidence that inventory alone does not solve completely unreachable road/service configurations.

All optimization and validation certificates pass. Eta `0.003` LB/UB are `26171.6135975414/26171.6138457859` with relative gap `9.4852556077e-09`; eta `0.01` LB/UB are `27448.9846575327/27448.9847293963` with relative gap `2.6180795517e-09`. Strong-duality, probability conservation/nonnegativity, divergence, EENS identity, and recourse mechanics all pass. No R-by-R matrix was built.

Development `run-001` is preserved after a 52-versus-51 output-column assembly error following three successful optimizations. `run-002` is preserved after all 30 MATLAB processes passed but the Python plot finalizer encountered local Matplotlib style/API incompatibility. `run-003` repeated every process from scratch and all 31 isolated processes exited zero. Neither failed run is eligible for Git.

## 27. Current decision boundary after Step-04C-C5B

The unified yuan objective materially changes inventory levels: historical mixed-unit totals `676.431279/681.053115/693.468150 kg` become `511.414778/526.143526/532.689620 kg`. The historical statement that eta `0.01` adds only `17.036871 kg` no longer applies; the new increment is `21.274842 kg`.

Use SAA as the economic benchmark, eta `0.003` as the lower-premium mild-resilience scheme, and eta `0.01` as the higher-guarantee scheme. This is candidate judgement option 3; neither radius is formally frozen and neither DRO scheme全面支配SAA. The evidence supports carrying all three schemes into the 35-state calculation because both DRO decisions improve mean EENS in every empirical validation cell and show increasing economic value under intensity/combined probability shifts. Preserve the explicit limitation that fixed-pressure maximum shortage is unchanged and TerminalLOH cannot replace road restoration or network hardening.
