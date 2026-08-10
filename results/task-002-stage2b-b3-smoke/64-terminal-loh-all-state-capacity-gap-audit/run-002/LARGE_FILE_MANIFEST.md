# LARGE_FILE_MANIFEST

Local-only reproducibility inputs/outputs:

- `all_state_path_capacity_raw.csv`: 2985237 bytes, SHA-256 `b161c0694d88dd29c73a76b390918f010aaa9b61054f08443472c1d2caff8b2d`. Full 12106-row per-method/path diagnostic table; keep local and do not stage.
- `resource_utilization_state_raw.csv`: 21958 bytes, SHA-256 `39ae25f9933a28647abb2e85c6b63d4908f97fdf1d0de98f2d6bdb209a81bd6d`. Intermediate 210-row resource table; keep local because the finalized required resource table is committed instead.

No MAT, workspace, cache, or new OOS scenario file was created.

The required paired path transition table
`all_path_saa_dro_feasibility_transition.csv` is 1693589 bytes and is retained
as a reviewable task result. The larger raw LP table above remains local-only.
