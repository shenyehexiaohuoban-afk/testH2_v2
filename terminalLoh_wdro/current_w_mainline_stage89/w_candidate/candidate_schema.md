# Stage-89J isolated candidate schema

Each `terminalLoh_wdro/output/stage89j_topology_h2_dual_channel_w_candidate/run-001/state-XXX_stage89j_candidate_grouped.mat` is a MATLAB v5 MAT file and loads directly with MATLAB `load`.

- State fields: `stateId`, `a0`, `loc0`, `lfw0`, `sourceBus`, `siteBus`, and `officialSliceDurationHours`.
- Grouped scenario fields: `Dres[G,3,33]` double, `Aroad[G,3,4,33]` uint8, `Aelec[G,3,4,33]` uint8, and `C[G,3,4,33]` double.
- Exact-group fields: `representativePathId[G,1]` uint32, `multiplicity[G,1]` uint16, `q_g[G,1]` double, `groupId[15000,1]` uint16, `groupCount`, and `originalR`.
- Stable representatives are the first frozen path occurrence. `groupId` is one-based and maps all 15,000 frozen draws to those representatives.
- The exact signature is `(Dres,Aroad,Aelec,C)`. Raw-byte equality uses MATLAB field order and column-major element order: K fastest, then I where present, then N. There is no rounding, tolerance, clustering, quantization, or approximate reduction.
- `q_g=multiplicity/15000`. FC capacity is static site metadata in `fc_static_capacity_metadata.csv` and is deliberately excluded from the signature.
- `Dres` retains demand in H2-containing non-source islands. `Aelec` is reachability/candidate service capability, not restored load.

The formal support total is 457431. Source and output SHA-256 identities are in the two manifests.
