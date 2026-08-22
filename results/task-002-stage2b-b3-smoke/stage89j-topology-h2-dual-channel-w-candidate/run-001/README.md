# Stage-89J formal topology-based H2 dual-channel W candidate bank

Status: **FORMAL_W_CANDIDATE**. This is an isolated candidate: **NOT CURRENT_W_MAINLINE**, **NOT ACCEPTED_TERMINALLOH**, and **NOT MSP-ACCEPTED**.

## Outcome

- Built 35 state banks from 525,000 frozen trajectory identities without any W/grid/road redraw.
- Used W1-M12-W2-M23-W3 grid exposure, actual endpoint sampled Vmax midpoint interpolation, persistent fixed resistance, and G1 strong-hardening sensitivity only on lines 1-2 and 2-3.
- Kept official W1/W2/W3 one-hour service slices and current three-point Stage88 Aroad/C semantics.
- Applied deterministic MAT-order five-tie radial reconstruction from source bus 1.
- Exact signature `(Dres,Aroad,Aelec,C)` produced **457,431** groups, exactly matching Stage-89I's **457,431** expectation.
- `q_g=multiplicity/15000`; all 35 multiplicity and probability gates pass at machine precision.
- FC capacity is static metadata only and is not part of exact grouping.

`H2_island_candidate_D_share` is a topology candidate-demand share. It is not restored-load share and makes no grid-forming, black-start, voltage, thermal, or dynamic-FC claim.

## Scope gates

CURRENT_W_MAINLINE_MODIFIED=NO
STAGE88_MODIFIED=NO
STAGE89H_MODIFIED=NO
W_TRAJECTORY_RESAMPLED=NO
GRID_FAILURE_RANDOMNESS_RESAMPLED=NO
ROAD_FAILURE_RANDOMNESS_RESAMPLED=NO
SAA_DRO_RUN=NO
TERMINALLOH_RUN=NO
FA_MSP_RUN=NO
OOS_RUN=NO
NEW_BINARY_VARIABLES=0
NEW_NONLINEAR_MODEL=NO

The 1.10 GB candidate body is under `terminalLoh_wdro/output/stage89j_topology_h2_dual_channel_w_candidate/run-001/` per the large-output rule. Its lightweight schema, per-state manifest, exact-group index, statistics, QA, static FC metadata, and full source provenance are in this results directory. Runtime: 294.306 seconds.

Recommended next stage: Stage-89K TerminalLOH SAA/DRO on this isolated candidate.
