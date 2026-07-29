# Existing document consistency

## Statements that are explicit

- `docs/baseline/BASELINE.md:18-20` defines W1-W3 as one hour each and defines aggregate demand as their sum.
- `docs/baseline/BASELINE.md:34-37` states that component resistance is shared across W1-W3 and damage persists after first failure; road slowdown keeps the historical maximum.
- `terminalLoh_wdro/docs/README_lookahead_W3_path_generation.md:45-49` describes W1-W3 as offline look-ahead consequence scenarios rather than an expansion of the MSP state space, and originally directs later work to aggregate D/A/C.
- `codex_rule/longtask.md:390-403` describes post-impact scenario generation for pre-deployment TerminalLOH and explicitly says the project is not becoming a full post-disaster rolling-operation model.
- `results/.../28-period-vs-aggregate-loss/run-001/README.md:9` documents the implemented shared T, period-specific balance, no advance service, and no shortage carryover.

## Information-structure gap

The audit also searched all tracked MATLAB/Python source and Markdown/TXT material for full-information, sequential-revelation, nonanticipativity, scenario-tree, advance-service, and backlog terminology. Only the Step-03Y implementation notes explicitly describe advance service/backlog; no repository statement selects an information-revelation regime.

The reviewed repository materials do not explicitly state that all three future periods' D/A/C are known before W1 service is chosen. They also do not explicitly require sequential revelation or nonanticipativity. The phrase 'look-ahead scenario' and the offline pre-layout scope do not, by themselves, resolve this operational-information assumption.

Accordingly, the current implementation is not contradicted by an explicit sequential-revelation statement, but neither is its full-scenario-information assumption explicitly authorized. The correct freeze gate is a user modeling decision, not an inference from successful solves.
