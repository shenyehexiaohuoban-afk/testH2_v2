# Large File Manifest

- repository: `testH2_v2`
- branch: `task/001-stage2a2-path-prob`
- task_id: `task-001`
- step_id: `03-stage2b-tail-candidate-design`
- run_id: `run-001`
- archive_date: `2026-07-16`

## Local-Only Path Tables

| file | rows | size_bytes | size_mib | sha256 |
|---|---:|---:|---:|---|
| `observed_unique_path_risk.csv` | 256884 | 47387183 | 45.190 | `95be36b0cfbd6981ed76b6d03f62eb80f427a913024af193abe1a20d1b1e31b0` |
| `high_exposure_paths.csv` | 340173 | 81135594 | 77.380 | `f513998939479493004e7670cdf21a2aec589dcd133f3b2a408c4143fd8271d8` |

- local_directory: `terminalLoh_wdro/output/stage2b_tail_candidate_design/run-001/`
- uploaded_to_git: `false`
- local_files_preserved: `true`
- reason: `path-level tables are large; Git archives only the compact audit outputs and file metadata`

The original 525,000-row main sample is also local-only and remains unchanged in
`terminalLoh_wdro/output/stage2a2_W3_path_sampling/run-002/`.
