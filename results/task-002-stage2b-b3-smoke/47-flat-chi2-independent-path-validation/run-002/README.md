# Step-04C-C2 run

- Status: PASS; accepted as the first complete run only after the Git-scope audit.
- Scope: state19 fixed-decision validation on three genuinely different typhoon-path random seeds.
- Namespace: `independent-path-C2`; every dataset separately contains 15,000 scenarios with weight `1/15000`.
- Frozen decisions: SAA eta=0, eta=0.003, and eta=0.01, read directly from Step-04C-C1 accepted `run-003` nominal optimization results.
- No TerminalLOH optimization or eta selection was performed on the independent datasets.
- CVaR is an evaluation metric only. No mean-CVaR or chi-square-plus-CVaR objective was introduced.
- The three datasets are reported seedwise. Cross-seed summaries are descriptive and do not reinterpret the 45,000 rows as one probability distribution.
- Ordinary overlap of discrete physical path values is reported separately from random-stream collision and exact whole-batch reuse.
- Paired differences use `candidate - SAA`; negative values mean improvement. The 95% CI is a two-sided Student-t interval with 14,999 degrees of freedom.
- Candidate judgement: `4. NEITHER_SHOWS_STABLE_VALUE_RETURN_TO_SAA_OR_RADIUS_REVIEW`.
- Both candidates reduce mean shortage and CVaR99.5 on all three seeds, but the gains are small. The q99.5 loss is unchanged in two seeds for eta=0.003 and one seed for eta=0.01, while mean total cost worsens on two seeds. The extra 17.0369 kg for eta=0.01 is therefore not justified by a sufficiently large, uniformly visible tail benefit.
- Formal eta remains unfrozen. Markov transition-probability perturbation has not been performed.
- Maximum fixed-T mechanical residual: `5.11590769747272e-13`.
- Large MAT, full scenario results, and the full paired-difference table remain local and are listed with SHA-256 in `LARGE_FILE_MANIFEST.md`.
- Development history: `run-001` is preserved as failed evidence. Its three dataset preparations passed, but the first fixed-T process was rejected by an over-strict `1e-14` floating weight-sum tolerance. `run-002` froze `1e-12` before regenerating and reevaluating all three datasets from scratch.
