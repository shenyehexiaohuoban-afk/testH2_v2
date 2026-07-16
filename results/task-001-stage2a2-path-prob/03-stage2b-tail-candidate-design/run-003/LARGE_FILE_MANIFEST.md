# Large File Manifest

- repository: `testH2_v2`
- branch: `task/001-stage2a2-path-prob`
- task_id: `task-001`
- step_id: `03-stage2b-tail-candidate-design`
- run_id: `run-003`
- archive_date: `2026-07-16`

## Local-Only Path Table

| file | rows | size_bytes | size_mib | sha256 |
|---|---:|---:|---:|---|
| `unobserved_high_risk_legal_paths.csv` | 15388410 | 2121759312 | 2023.467 | `29a679e3388e5f58a71ecaef3e16d1980776bfe9e91a9e7603e5cec05f0a00f1` |

- local_directory: `terminalLoh_wdro/output/stage2b_tail_candidate_design/run-003/`
- uploaded_to_git: `false`
- local_file_preserved: `true`
- reason: `the path-level candidate table exceeds the repository large-result threshold; Git archives compact diagnostics, Pareto candidates, and this metadata only`

The table contains repeated path rows across quantile levels by design. The
summary CSV files report de-duplicated counts within each initial-state and
quantile grouping.
