# Stage89N Stage85R adapter diff

Mother source: `hourly_grid_h2/run_stage85r_dro_p150_p200_5h_10k_h2.m`.

Stage89N retains the Stage85R training loop, unchanged shared `forward_pass_h2` / `backward_pass_h2`, cut update, four-inventory policy representation, and Stage85R OOS `evaluate_path` mathematics. It inherits the Stage85H-A process boundary: train, save, exit, verify zero MATLAB/Gurobi processes, external streaming SHA-256, one clean checkpoint load, reload QA, then OOS in that clean process.

| Stage85R original | Stage89N adaptation | Classification |
|---|---|---|
| Historical Stage53/Stage73 input wiring | Stage89M current entry with adopted Stage89K DRO table and strict SHA/version gates | allowed current input |
| Historical `params.k_init` | mechanically map the same initial `a/lf` to `loc4`; training and OOS use index 81 | allowed initial state |
| P150/P200 two-arm five-hour comparison | one ordinary-shortage-200 arm, exactly 10 iterations | allowed budget/reporting |
| terminal-gap penalty 2000 | terminal-gap penalty 1000 | allowed fixed economic parameter |
| historical table/tank input | Stage89K DRO eta=0.03, tanks `[300,200,100,200]`, Site4 Pmax 150 kW | allowed adopted input |
| generated two-policy common bank | direct read-only reuse of accepted Stage89H run-003 loc4 path bank, SHA-256 `6bf3d119...386c6` | allowed common-path identity |
| per-arm checkpoint under results | one checkpoint under `terminalLoh_wdro/output/stage89n_.../run-001/`, referenced by lightweight identity CSV | allowed large-output location |
| Stage85R output/reporting | isolated Stage89N result path and controlled comparison reports | allowed reporting |
| Stage85R optional hourly/positive-flow OOS detail files | retain path/stage/site summaries but do not stream non-required hourly/flow detail after run-002 reproduced native heap corruption at path 6700 | allowed reporting-only stabilization; `evaluate_path` mathematics unchanged |

Explicit unchanged items: training-loop order, forward call, backward call, cut generation/update, Stage1 single-`params.k_init` cut semantics, hourly builder, Stage7 value/subgradient mathematics, state representation, stage solver/update chain, and OOS path evaluation mathematics.

```text
BACKWARD_CORE_MODIFIED = NO
FORWARD_CORE_MODIFIED = NO
MULTILOC_STAGE1_ADAPTATION_USED = NO
UNEXPECTED_RUNNER_DIFF = NO
```
