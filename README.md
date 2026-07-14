# Hydrogen-Electric-Road Resilience Scheduling

This repository contains a MATLAB research project for typhoon-aware hydrogen,
electric-grid, and road-network resilience scheduling. It includes the FA-MSP
baseline, the H2 application model, and an isolated `terminalLoh_wdro` workflow
for offline TerminalLOH scenario generation and diagnostics.

## Current Baseline

The accepted foundation baseline is documented in
[`docs/baseline/BASELINE.md`](docs/baseline/BASELINE.md). In summary:

- the Foundation Fix and its v2 re-audit are complete;
- W1, W2, and W3 represent three one-hour slices, so `Hres=3 h`;
- `Wstep=40` is the current recommended spatial step;
- `persistent_fixed_resistance` is the selected no-repair damage-persistence
  convention for a future formal B3 run;
- Stage2A2, formal B3, Stage2C, and MSP integration have not been executed.

## Repository Structure

- `main_msp_h2_near.m`, `run_h2_with_options.m`: H2 MSP entry points.
- `fa_h2/`: FA-MSP stage models, forward/backward logic, cuts, and evaluation.
- `terminalLoh_wdro/src/`: isolated WDRO and look-ahead research source code.
- `terminalLoh_wdro/config/`: look-ahead configuration tables.
- `terminalLoh_wdro/docs/`: method and stage documentation.
- `terminalLoh_wdro/checks/`: validation notes and check definitions.
- `data/`: required model and scenario inputs.
- `codex_rule/`: project execution rules and change log.
- `docs/baseline/`: repository baseline and file-audit records.

Generated results under `terminalLoh_wdro/output/` and `output_h2/` are kept
local and excluded from version control. The repository therefore records the
source, configuration, checks, documentation, and required inputs without
committing bulky reproducible outputs.

## Environment

The project is developed in MATLAB. Some formal optimization workflows require
Gurobi, but no solver license, account credential, or local environment file
should be committed. Run scripts only after reviewing the current stage notes
and project rules.

## Working Rules

Before changing the project, read:

1. `codex_rule/core.md`
2. `codex_rule/longtask.md`
3. `codex_rule/log.md`
4. the current task specification

Additional agent instructions are in [`AGENTS.md`](AGENTS.md).

## Reproducibility Notes

- Required source and input files are intended to be tracked.
- Generated output directories are intentionally ignored.
- The current repository audit is recorded in
  [`docs/baseline/repository_file_audit.md`](docs/baseline/repository_file_audit.md).
- No open-source `LICENSE` file has been selected yet. Choose and add one before
  treating a public GitHub copy as open-source software.
