# Step-04C-C4 parameter provenance and resilience audit

Status: **ACCEPTED**  
Run: `run-004`  
Frozen Git HEAD/upstream/remote: `62447cb913f5fd3723b5cdf7b3cefccc358bdab2`

## Scope

This is a deterministic, read-only audit. It reads C1 accepted `run-003`, C2 accepted `run-002`, C3 accepted `run-001`, the live frozen near-stage MAT input, and protected scenario-result tables only to recompute shortage CVaR99.5 for C2/C3. It does not optimize TerminalLOH, choose eta, run MATLAB/Gurobi/MSP, alter formal recourse, or assign probability to the fixed pressure replicas.

## Main findings

- `gamma=2` is `0.001*M`, a derived offline trade-off weight. It is not evidenced as `2 yuan/kg` and does not cover production, transport, storage, losses, or salvage.
- `M=2000` is effectively loaded from the MAT field `reserve_shortage_penalty_yuan_per_kg`. The declared field unit is yuan/kg, but the numeric calibration source is absent and the offline objective is mixed-unit because `C*y` is kg-km.
- eta=0.01 adds `17.0368707551011 kg`, giving `34.0737415102021` direct offline objective units at gamma=2.
- Repository parameters support the model-equivalent inverse conversion `shortage_kg * 18.3315 kWh/kg`. This is not an external conversion and should not be overstated as independently calibrated full-grid EENS.
- Both chi-square candidates have consistent operating-risk value in C2/C3. eta=0.003 is the cleaner mild resilience candidate; eta=0.01 is a conservative upper candidate whose extra inventory has clearer value under stronger probability shifts than under nominal/location-only conditions. Formal eta remains unfrozen.

## Mechanical acceptance

- economic rows: `84`; safety rows: `56`; gamma-by-seed rows: `48`; gamma summary rows: `16`
- maximum total-cost reconstruction error: `1.27602106658742e-09`
- C1/C2/C3 frozen certificates: PASS
- source script contains no solver or MSP call
- historical runs and local large files were read-only and were not copied into this run

## Frozen input SHA-256

- `data/yuanqi/near_stage_msp_input.mat`: `536b25868e6d7cc812a331c0d3e0ffbd5f6958e6883bd39bcae3901c372abf24`
- `results/task-002-stage2b-b3-smoke/46-flat-chi2-eta-calibration/run-003/README.md`: `3902051d6c9c64a7517d364840d25a402d56569e8da9c0ea8eac912a2d026150`
- `results/task-002-stage2b-b3-smoke/46-flat-chi2-eta-calibration/run-003/eta_full_results.csv`: `16947d17fc2a3ff4a30bb966e14b5b76a0bf19a27dec48722ab405b930c6daf0`
- `results/task-002-stage2b-b3-smoke/46-flat-chi2-eta-calibration/run-003/eta_validation_comparison.csv`: `c6bdd35a2481b070790cb914be52a4e86c0c9e043c15fd1e5d8d41c738d48ac0`
- `results/task-002-stage2b-b3-smoke/46-flat-chi2-eta-calibration/run-003/eta_stress_test_comparison.csv`: `c68f1ae78fed72257fba4ab36594bf3a425c3065ab7caa614d3d2fc22fea2f80`
- `results/task-002-stage2b-b3-smoke/46-flat-chi2-eta-calibration/run-003/eta_solver_certificate.csv`: `63e8b8316aafd73284a087a6af10a5dcf257a87ddf739bf70b4d5171574a3769`
- `results/task-002-stage2b-b3-smoke/47-flat-chi2-independent-path-validation/run-002/README.md`: `dda0a47e8a00e5823aa7efe085519804a0920387f9864acb94902e136cf9d74e`
- `results/task-002-stage2b-b3-smoke/47-flat-chi2-independent-path-validation/run-002/fixed_T_full_results.csv`: `d5684b4640f965850d4c2341e06290b56d9c04a19af452375316723bfb17ad74`
- `results/task-002-stage2b-b3-smoke/47-flat-chi2-independent-path-validation/run-002/fixed_T_process_certificate.csv`: `e9e78d51fb9a9c4fd681fdbf211f66810e0d92502c5bd7a64da7cc55236390ff`
- `results/task-002-stage2b-b3-smoke/48-markov-transition-perturbation/run-001/README.md`: `e5288eeb894a1e5af4a723ad3d27de8264fe394deabbfb51dad10c02f2b13b49`
- `results/task-002-stage2b-b3-smoke/48-markov-transition-perturbation/run-001/fixed_T_full_results.csv`: `80f4159c77e322e870c7fd29a2f7486babb2241cce93112e221bdafe62c1cbce`
- `results/task-002-stage2b-b3-smoke/48-markov-transition-perturbation/run-001/fixed_T_process_certificate.csv`: `1214b3cef032934a403f27621cea6fd5bc9b6d98b616d53f600476d10ea88863`

See `audit_conclusion.txt` for the bounded interpretation and the CSV files for complete seedwise evidence.
