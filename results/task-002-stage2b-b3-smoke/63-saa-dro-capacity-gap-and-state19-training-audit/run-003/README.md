# Step-05B-6 SAA/DRO capacity-gap and state19 training audit

Accepted local audit run: `run-003`

## Scope

- Reused the exact frozen 10000x8 OOS paths.
- Solved 510 ex-post perfect-information, service-preserving physical LP rows: 255 paths for SAA and the same 255 paths for DRO.
- Each method used its own archived policy ordinary-service quantities and its own TerminalLOH table.
- Inspected only archived cuts at ordinary late nodes on the fixed eight state19 paths.
- No MSP training, resampling, forward/backward pass, new cut, TerminalLOH change, or 200/2000 change occurred.

## Main result

SAA already has material system-total shortfall in all four states; DRO increases targets and further raises the shortfall. Across the 255 paired paths, 191 are infeasible under both targets, 50 are feasible under both, and 14 are SAA-feasible but DRO-infeasible. This supports capacity classification **B: SAA shortfall pre-exists and DRO amplifies it**.

The state19 eight-path set remains physically feasible under the ex-post diagnostic. Exact training-node visits cannot be reconstructed because per-iteration sampled paths were not archived. The k222 static cut anomaly is real, but current evidence is insufficient to label it a one-hour-training failure; state19 training classification is **F**.

All eight fixed paths are total-sufficient and station-target-feasible in the
clairvoyant diagnostic, while all eight have a positive archived DRO terminal
gap. Seven of the eight archived policy paths already have enough actual total
inventory, confirming that this subset is not the system-total-shortfall group.

## Important interpretation boundary

These physical LPs know the realized full path and terminal state. They do not prove that the original non-anticipative FA-MSP could make the same allocation at each historical decision time.

## Failed runs retained

- `run-001`: cut-detail output schema was initialized as 35 columns for a 34-field row.
- `run-002`: attempted to inspect an ordinary cut model after a path had already reached the lf=7 TerminalLOH state.

Both failures were audit-script issues, are preserved with `FAILURE.txt`, and
did not train, resample, add cuts, or modify protected inputs.
