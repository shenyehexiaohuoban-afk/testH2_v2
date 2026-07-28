# Step-03Y-A period-data recoverability audit

## Result

- Mechanical audit: `PASS`.
- Conclusion: `B. PERIOD_DATA_DETERMINISTICALLY_RECOVERABLE`.
- Solver calls: 0.
- Validation inputs read: 0.

## Direct storage check

The Step-03J D/A/C sidecar contains only `D_node_kg`, `A_site_node`, `C_site_node_km`, `path_id`, and `initial_state_id`. The nominal CSV contains W1-W3 path states and actual winds, seeds, stream position, final D/A/C summaries, and W3 damage counts, but no period D/A/C arrays. Therefore conclusion A does not apply.

## Deterministic recovery

The original generator first applies `permutation=randperm(15000)`, then generates persistent `lineU` and `roadU` resistance thresholds from `resistance_seed`. A separate `wind_seed` generates the 15000x3 matrix `q`. The saved `joint_stream_position` identifies the exact row in all three streams. Full permutation and q-column SHA-256 values match the Step-03J seed map for all six states.

The period variables are `D1/D2/D3`, `reachTau`, and `costTau`. Persistent line states are `failed1/failed2/failed3`; persistent road states are `closed1/closed2/closed3` with `slow1/slow2/slow3`. For each node, the final A/C merge uses periods where `D1/D2/D3` exceed `1e-10 kg`; if no period has demand, all three periods are used. A is true only when the site reaches the node in every selected period, and C is the mean selected-period shortest-path impedance.

## Replay evidence

Three existing Step-03W endpoint scenarios were selected per state by the deterministic min/middle/max scenario-id rule, for 18 scenarios total. Random-stream hashes and final D/A/C match exactly; winds and scalar CSV summaries match within 1e-12 CSV serialization precision. `recovered_period_data.mat` stores the audited period arrays and resistance/damage evidence for these 18 scenarios only; it is not a replacement scenario set.

## Boundaries

No TerminalLOH optimization, Q evaluation, distance computation, Gurobi, WDRO, or MSP call was made. No validation file or other initial state was processed. Existing untracked outputs were hash-checked before and after and were not modified. Git add, commit, push, and `codex_rule/log.md` updates were not performed.

runtime_sec=12.147130
