# Implementation Audit

- Inputs: run-001 observed unique-path risks and stored quantiles only.
- Equality tolerance: 1e-12 relative to max(1,abs(q)).
- Candidate rule: risk>0 and (risk>q or risk=q within tolerance).
- Pareto domain: candidates at the same state/proxy/quantile only.
- Pareto objectives: lower path_probability and higher risk.
- Empirical weighting: frequency/15000; path_probability is not a weight.
- run-001 unchanged: 1.
- proxy nesting pass: 1; combined nesting pass: 1.
- positive-risk pass: 1; Pareto subset pass: 1.
- No combined risk score, resampling, wind recomputation, legal-path search, B3, WDRO, Gurobi, or MSP.
