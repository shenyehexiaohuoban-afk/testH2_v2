# Step-05B-11 OOS risk-feature association audit

Status: **PASS**. Independent mechanical verification completed successfully.

This read-only audit uses the accepted Stage-53 run-024 offline state results, Stage-60 run-002 accepted SAA-surplus definition, Stage-65 run-002 10000-path paired master, Stage-66 run-001 fixed bins, and the exact frozen 10000x8 OOS path file. It does not modify either optimization model and does not run MATLAB, Gurobi, training, resampling, or W1-W3 recourse.

Git precheck: branch `task/002-stage2b-b3-smoke`, HEAD `112b13723032812d9227def3fbf53e038cfb2fc8`. HEAD equals the frozen baseline and Stage-68 was unused at task start.

The principal unit is the actual OOS path (`path_id=1..10000`). Terminal-state summaries retain actual OOS frequencies; no 35-state equal weighting is used as the main evaluation.

Risk features are independent of Delta I: they come from the frozen path itself, the SAA baseline, or accepted Stage-53 offline state risk. Correlations and group differences are descriptive only. Terminal gap remains a soft reserve-target gap, ordinary shortage remains pre-disaster normal-demand shortage, and offline W-stage shortage/EENS is not relabeled as either quantity.

See `risk_feature_definitions.csv`, `spearman_correlations.csv`, group summaries, figures, `step05b11_judgment.txt`, and `independent_mechanical_audit.txt`.
