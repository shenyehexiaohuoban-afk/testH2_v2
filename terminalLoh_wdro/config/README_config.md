# WDRO Look-Ahead Config

This directory keeps only the main Stage 2A W=3 look-ahead configuration
tables. These tables follow the MSP-stage idea of separate intensity,
location, and landfall/window inputs, but they are used only by the offline
WDRO-TerminalLOH look-ahead module.

## Main Tables

1. `lookahead_intensity_W3.csv`

   Typhoon intensity transition table.

   Columns: `from_a,to_a,prob`

2. `lookahead_location_W3.csv`

   Look-ahead location transition table on the extended `loc_id` line.
   `loc_id` may include zero or negative halo ids.
   `lookahead_location_W3.csv` is not a row-by-row copy of the original MSP
   location transition matrix; it extracts an empirical displacement kernel
   from `data/location.csv` and applies that kernel to the extended location
   set `loc=-2:10`, avoiding boundary truncation and allowing W=3
   look-ahead paths to enter the left and right halo regions.

   Columns: `from_loc_id,to_loc_id,prob`

3. `lookahead_window_W3.csv`

   Key-value table for global look-ahead settings.

   Required keys: `W`, `P`, `random_seed`, `loc_min`, `loc_max`,
   `halo_width`, `lf_terminal`

## Scope

- These files do not modify the original MSP state space.
- These files do not modify `data/location.csv`, `data/intensity.csv`, or
  `data/landfall_7.csv`.
- `W` is represented in path outputs by `tau=1,...,W`; it is not the original
  MSP `lf`, and this module does not introduce `lf=8,9,10`.
- The `row_id` mapping for MATLAB-safe indexing and other intermediate
  diagnostics are stored under:

  `terminalLoh_wdro/output/stage2_lookahead_W3/config_diagnostics/`

Downstream WDRO consequence samples should keep reachability `A` binary:
`A=1` means a feasible service path exists and `A=0` means fully unreachable.
Roads that remain passable but become slow should be represented by a larger
service cost / impedance / travel time `C`, not by fractional values such as
`A=0.3`.

## Post-Landfall W3 Transition Candidates

The three legacy files above remain unchanged and are retained for comparison.
Task-001 step-01 adds four separate engineering-candidate files:

1. `lookahead_intensity_postlandfall_W3.csv`
2. `lookahead_location_postlandfall_W3.csv`
3. `lookahead_lfw_postlandfall_W3.csv`
4. `lookahead_window_postlandfall_W3.csv`

The post-landfall intensity candidate reduces each existing `a=2:5`
enhancement probability to 20% of its legacy value. The removed probability
mass is allocated two-thirds to weakening and one-third to staying at the same
intensity. Enhancement remains possible but less likely. State `a=1` remains
absorbing, while `a=6` uses `6->5=0.60` and `6->6=0.40`.

The loc candidate uses the displacement kernel
`[-3,-2,-1,0,+1,+2,+3]` with probabilities
`[0.04,0.10,0.22,0.18,0.28,0.13,0.05]`. Most mass is assigned to adjacent
states, and farther moves in the same direction are less likely. Invalid
boundary targets are deleted and the remaining mass is renormalized; no
probability is clamped onto a boundary state.

The lfw candidate uses states `0:3` and a backward/stay/forward kernel of
`0.10/0.20/0.70`. Boundary rows delete invalid targets and renormalize the
remaining mass. A backward lfw transition is spatial trajectory variation; it
does not reverse time or restore previously damaged equipment.

`W1`, `W2`, and `W3` are consecutive one-hour time windows. They are not fixed
lfw states. The actual x coordinate is determined by loc, while the actual y
coordinate is determined by
`y = -89.9999703886 + lfw * 40`. The window value `P=20` is only the legacy
diagnostic sample count and is not the complete path count.

These probabilities are transparent and reproducible engineering candidates.
They have not been calibrated against real typhoon observations, have not been
accepted as final parameters, and are not connected to the formal path
generator yet.
