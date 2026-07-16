# Implementation Audit

- reachable joint states cached once: 312.
- wind model: Rmax=40, B=0.6, grid/road thresholds=25/30 m/s.
- maximum risk-cache difference versus run-001: 5.11590769747272e-13.
- reverse-DP upper bounds: max recursion for peak wind, additive recursion for exceedance sums.
- crosscheck states: (2,1,0), (2,4,0), (4,1,0), (4,4,0), (6,4,0), (6,7,0).
- full-enumeration missed paths: 0.
- inputs unchanged: 1.
- path_probability is theoretical/Pareto only; no empirical weighting or combined score.
- no supplemental paths, B3, WDRO, Gurobi, or MSP.
