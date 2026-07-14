# W=3 Look-Ahead Typhoon Path Generation

This Stage 2A module generates W=3 future typhoon paths for WDRO-TerminalLOH.

## Scope

- It only samples future typhoon intensity and location paths.
- It does not sample grid failures or road failures.
- It does not generate D,A,C consequence samples.
- It does not run WDRO-LP.
- It is not connected to MSP.

## Config Tables

- `lookahead_intensity_W3.csv`: intensity transition table with `from_a,to_a,prob`.
- `lookahead_location_W3.csv`: location transition table with `from_loc_id,to_loc_id,prob`.
- `lookahead_window_W3.csv`: key-value settings for W, P, seed, original loc range, halo width, and terminal lf.
- Intermediate mapping and kernel tables are under `output/stage2_lookahead_W3/config_diagnostics/`.

## Symbols

- `W`: look-ahead window count. Current W=3.
- `P`: number of sampled paths per source lf=7 state. Current P=20.
- `tau`: look-ahead step, tau=1,...,W. It is not MSP lf.
- `loc_id`: physical look-ahead location identifier; halo ids may be zero or negative.
- `row_id`: positive MATLAB-safe row index for each loc_id.

## Location Extension

- Original loc range: 1:7.
- Extended loc range: -2:10.
- Halo coordinates are extrapolated from the existing windmc loc centers using boundary adjacent spacing.
- No artificial L/R impact decay coefficients are used.

## Transition Logic

- `data/location.csv`, `data/intensity.csv`, and `data/landfall_7.csv` are not modified.
- `lookahead_location_W3.csv` is the main look-ahead location transition table on the extended loc_id line.
- The current first version uses a displacement kernel inferred from original loc transitions.
- Displacement kernel support count: 13, probability sum 1.
- `lookahead_intensity_W3.csv` is the main look-ahead intensity transition table.

## Why MSP lf Is Not Changed

The look-ahead horizon is represented by `tau` rather than `lf=8,9,10` because this module is not expanding the MSP state space. It only generates future typhoon path scenarios used later for offline TerminalLOH consequence sampling.

## Next Step

The next stage should condition grid and road disaster sampling on each W=3 path, aggregate D,A,C consequence samples, and then run the WDRO-TerminalLOH LP on those consequence samples.

When those consequence samples are generated, reachability `A` should remain
binary: `A=1` means a feasible service path exists and `A=0` means fully
unreachable. Slow but passable road conditions should be represented by larger
service cost / impedance / travel time `C`, not by fractional reachability
values such as `A=0.3`.
