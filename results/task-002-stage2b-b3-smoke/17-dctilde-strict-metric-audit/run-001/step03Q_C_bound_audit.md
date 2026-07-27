# Step-03Q C Bound Audit

## Deterministic bound

The formal B3 road cost is `edgeCost = roadLength .* (1 + pClose)` and closed edges are set to `Inf` (`evaluate_formal_stagewise_b3_stability_block_h2.m:47-48,63-76`). `compute_line_failure_prob_h2.m:9-13` clips pClose to [0,1].
All finite edge costs therefore satisfy `edgeCost <= 2*roadLength`. Positive edge costs imply a reachable shortest path can be chosen simple, so it uses each road edge at most once. Every possible reachable path cost is bounded by `2*sum(all road lengths)`. A mean across reachable critical W1-W3 windows remains under the same bound (`aggregate_W3_DAC_outcomes_h2.m:23-55`).

Road coordinates are the same `layout.nodes.x_km/y_km` used by the formal B3 model (`build_foundation_fix_coordinates_h2.m:162-184`; `run_stage3i_formal_stagewise_random_b3_h2.m:440-477`).

- road_file: `C:\Users\chaos\Desktop\biye\test\testH2_v2\data\yuanqi\stage1_road_edges.csv`
- edge_count: 41
- sum_road_length_km: 178.576322370804
- maximum finite edge multiplier: 2
- C_bound_km: 357.1526447416079

## Full frozen-data coverage

- nominal: records=525000, reachable values=60963033, min=0, max=129.024752116, violations=0
- validation-1: records=525000, reachable values=60951465, min=0, max=124.252824334, violations=0
- validation-2: records=525000, reachable values=60945725, min=0, max=124.3035828, violations=0

This bound is topology- and model-derived, not the R=2000 sample maximum and not a physical upper bound for arbitrary external road networks.
