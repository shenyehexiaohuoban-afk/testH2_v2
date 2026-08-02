# Step-04C-C3 Markov transition perturbation diagnostic

- Status: PASS after all 21 dataset preparations, 63 fixed-decision evaluations, matrix audits, CRN audits, replay audits, row-count checks, and mechanical certificates passed.
- Scope: state19 only. The three TerminalLOH vectors were read directly from C1 accepted run-003 and were never optimized or selected on C3 data.
- Distributions: nominal; intensity-only/location-only/lfw-only at delta 0.05; combined mild/medium/strong at delta 0.02/0.05/0.10.
- Location ordering: lower equal-weight mean Wstep=40 point-to-system distance over lfw 0:3 is higher exposure. This fixed geometry ordering is independent of TerminalLOH, recourse loss, and C3 outcomes.
- Sampling: each distribution and seed is a separate 15,000-row state19 conditional Monte Carlo distribution with weight 1/15000. Distributions and seeds are not pooled into one probability law.
- Common random numbers: within a seed, all seven distributions reuse identical path-uniform blocks and identical wind/resistance random streams; only transition matrices differ. The three seed triplets are independent and collision-free against the audited historical namespaces.
- seed 1: path=1113527767, wind=664410789, resistance=1303781022
- seed 2: path=326796064, wind=69348633, resistance=697256691
- seed 3: path=1029622182, wind=840401885, resistance=272840227
- CVaR is an evaluation metric only. No chi-square worst-probability construction, Wasserstein ground cost, extreme-aware objective, MSP, or TerminalLOH reoptimization was called.
- Paired differences are candidate minus SAA on the same scenario. Negative values mean improvement; 95% intervals use Student t with 14,999 degrees of freedom.
- Both candidates have strictly negative paired 95% intervals for mean operating loss and mean shortage in all 21 distribution-seed cells. Their overall economic value is less stable because the extra inventory cost is not recovered under nominal or location-only shifts, and lfw-only is significant for only one seed.
- For both candidates, mean total-cost improvement has a strictly negative paired 95% interval in all three seeds for intensity-only, combined-mild, combined-medium, and combined-strong. Mean total-cost advantage grows monotonically along nominal -> combined mild -> combined medium -> combined strong in all three seeds.
- The 21 `NOT_VISITED` transition-frequency rows are exactly location state -2, which can appear only at the third/terminal step from state19 and therefore is never an origin row inside the three-transition horizon. No observed transition leaves nominal support.
- Interpretation: 4. 两者在各类扰动下仍无足够稳定价值，建议停止chi-square主线并回到SAA. This is a C3 mainline recommendation, not a formal eta freeze.
- Full MAT, scenario-level results, diaries, and process logs remain local and are recorded in `LARGE_FILE_MANIFEST.md`.
