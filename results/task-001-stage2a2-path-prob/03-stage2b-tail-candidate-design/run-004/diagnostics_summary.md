# Run-003 Pareto Archive Consistency Repair

- task_id: `task-001`
- step_id: `03-stage2b-tail-candidate-design`
- run_id: `run-004`
- status: `PASS`; PASS=18; FAIL=0.
- pre-repair local/archive total: 2194; expected total: 2410.
- q95.0 summary/local-before/archive-before/local-after/archive-after: `858/786/786/858/858`.
- q99.0 summary/local-before/archive-before/local-after/archive-after: `788/716/716/788/788`.
- q99.5 summary/local-before/archive-before/local-after/archive-after: `764/692/692/764/764`.
- repaired missing rows: 216.
- missing rows were exactly the Pareto rows for initial states `(2,1,0)`, `(2,2,0)`, and `(2,3,0)`.
- focus-state checks: 9 rows, all matching=1.
- repaired file SHA-256: `c11670b10e311d48c12952817dfd589f2efdac97c98563bb28b228415e97489d`.
- no sampling, wind calculation, legal-path search, B3, WDRO, Gurobi, or MSP.
