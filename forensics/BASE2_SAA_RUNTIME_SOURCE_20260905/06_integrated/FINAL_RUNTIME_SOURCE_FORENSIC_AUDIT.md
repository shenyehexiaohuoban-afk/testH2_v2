# BASE2-SAA Historical Runtime-Source Forensic Audit

This audit is read-only with respect to scientific sources/results. No scientific module was imported or executed; the current source was only compiled to an in-memory code object.

## Result

- `FORENSIC_AUDIT_STATUS = COMPLETED_NOT_PROVEN`
- `CURRENT_DEPENDENCY_PATH = C:\Users\chaos\Desktop\biye\test\testH2_v2\terminalLoh_wdro\partial_temporal_refinement\src\run_duration_aware_stage89k_dro.py`
- `CURRENT_DEPENDENCY_SHA256 = 14436f4bad0f7f46d5d0a59f69c463a11efbfe9f255b6e26e7acfb1573985de8`
- `HISTORICAL_PYC_FOUND = YES`
- `HISTORICAL_PYC_PATH = C:\Users\chaos\Desktop\biye\test\testH2_v2\terminalLoh_wdro\partial_temporal_refinement\src\__pycache__\run_duration_aware_stage89k_dro.cpython-39.pyc`
- `HISTORICAL_PYC_SHA256 = 58758bca8025c28cce78d3546b7d80db7f692da62d5cf203f73ced47de0c9a9f`
- `PYC_TIMESTAMP = 2026-08-31T14:32:25+00:00`
- `PYC_INVALIDATION_MODE = TIMESTAMP`
- `PYC_COFILENAME = terminalLoh_wdro\partial_temporal_refinement\src\run_duration_aware_stage89k_dro.py`
- `PYC_HEADER_MATCHES_CURRENT_SOURCE_MTIME_AND_SIZE = YES`
- `PYC_STRICT_BYTECODE_MATCH = NO`
- `PYC_NORMALIZED_BYTECODE_MATCH = YES`
- `PYC_SEMANTIC_BYTECODE_MATCH = YES`
- `LOCAL_HISTORY_SOURCE_FOUND = NO`
- `LOCAL_HISTORY_SOURCE_SHA256 = NA`
- `GIT_HISTORICAL_BLOB_FOUND = NO`
- `GIT_HISTORICAL_BLOB_SHA256 = NA`
- `RUNTIME_DEPENDENCY_PATH_DETERMINISTIC = YES`
- `ALTERNATE_MODULE_RESOLUTION_POSSIBLE = NO`
- `TIMELINE_CONSISTENCY = CONSISTENT`
- `EVIDENCE_LEVEL = LEVEL_B`
- `SAA_RUNTIME_SOURCE_IDENTITY_PROVEN = NO`
- `SAA_RUNTIME_BYTECODE_EQUIVALENCE = PASS`
- `CAN_CURRENT_DEPENDENCY_BE_COMMITTED_AS_HISTORICAL_EXACT_SOURCE = NO`
- `READY_FOR_REPRODUCIBILITY_CLOSEOUT = NO`
- `FULLY_CONVERGED = NOT_ESTABLISHED`
- `CURRENT_BRANCH = task/002-stage2b-b3-smoke`
- `HEAD = 605bb7f49fb91491e8ec70cbd25fff0b16659665`
- `UPSTREAM = 605bb7f49fb91491e8ec70cbd25fff0b16659665`
- `AHEAD_BEHIND = 0	0`
- `FINAL_PROCESS_OBSERVATION = MATLAB PID 9668 observed; this audit did not start or terminate it`
- `RECOMMENDED_NEXT_STEP = Ask the user whether to accept a bytecode-equivalent reconstructed-source label; exact historical source closeout still requires a historical source/hash/snapshot. Do not commit the dependency as historical exact source.`

## Evidence interpretation

The timestamp-based CPython 3.9 PYC predates the SAA solve, its header timestamp and source-size fields match the current source filesystem metadata, and its recursive code objects match the current source compilation. The runner constructs one explicit filesystem path and loads it with `spec_from_file_location`, so ordinary `PYTHONPATH` resolution cannot substitute another same-named module.

This establishes exact runtime bytecode equivalence at LEVEL_B, not byte-for-byte historical source identity. A PYC does not preserve enough source formatting/comment information to reconstruct or prove the original `.py` SHA-256. No historical source copy or historical manifest containing dependency SHA-256 was found.

## Boundaries

No SAA/DRO solve, MATLAB execution, Gurobi execution, MSP training, OOS, deep analysis, metadata correction, checkpoint/cut/table edit, Git commit, or push was performed. A MATLAB process (PID 9668) was observed during the final status check and was not terminated.
