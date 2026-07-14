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
