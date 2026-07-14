# Stage 1 Single-Window WDRO Check

This check folder records the scope and interpretation of the first-stage
WDRO-TerminalLOH prototype.

## Scope

- The current WDRO input is a single-window joint consequence sample table,
  equivalent to `W=1`.
- The sampled states are `lf=7` terminal-check states.
- Each `lf=7` state currently has `R=10` joint scenarios.
- The current WDRO output is not connected to MSP.
- The current module does not implement `W=3` look-ahead after `lf=7`.
- The current output is for prototype validation only and is not a formal
  paper-grade numerical result.

## rho and SAA Interpretation

- Under the complete consequence-space distance, `rho=0` can be interpreted
  as the SAA degeneration check for the empirical joint consequence samples.
- `DAC` is the current complete consequence-space prototype because it uses
  demand `D`, reachability `A`, and service cost `C`.
- `D_only` is a debugging/comparison distance mode. It is not a strict SAA
  check over the complete consequence space because it ignores `A` and `C`.

## rho Sensitivity

- With the current small `R=10` prototype, increasing `rho` does not
  necessarily make `TerminalLOH` monotone increasing.
- The current `wdro_rho_sensitivity_summary.csv` should be read as a
  diagnostic, not as a final robustness conclusion.
- Follow-up validation needs `W=3`, larger sample sizes such as `R=50/100`,
  and out-of-sample testing.

## Files To Check

- `terminalLoh_wdro/output/stage1_single_window/terminal_loh_by_state_WDRO.csv`
- `terminalLoh_wdro/output/stage1_single_window/terminal_loh_allocation_WDRO.csv`
- `terminalLoh_wdro/output/stage1_single_window/wdro_distance_matrix_summary.csv`
- `terminalLoh_wdro/output/stage1_single_window/wdro_rho_sensitivity_summary.csv`
- `terminalLoh_wdro/output/stage1_single_window/WDRO_README.txt`
