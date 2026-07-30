
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
