# Current mainline versus retained historical modules

## Current research mainline

### 1. Finite-support SAA

- Each initial state uses its own 15000 frozen nominal three-period records.
- SAA is the `eta=0` reference and supplies one of the two formal 35-state lookup tables.
- Current C6 solver/source examples: `terminalLoh_wdro/src/solve_terminal_loh_saa_c6_h2.m` and `run_step04CC6_*`.

### 2. Flat Pearson chi-square probability DRO

- The ambiguity is on finite observed scenario probabilities, not on a pairwise scenario distance.
- The selected current probability-DRO line is flat leaf/record probability perturbation.
- Current source examples: `solve_terminal_loh_flat_chi2_core_c6_h2.m`, `solve_terminal_loh_flat_chi2_decomposition_c6_external_h2.m`, and `solve_flat_chi2_worst_expectation.py`.
- Eta=0.03 is a representative high-guarantee comparison radius; it is not statistically frozen as uniquely correct.

### 3. Formal 35-state TerminalLOH interface

- Current tables are the two C6 `run-024` CSV files.
- They cover `a=2..6`, `loc=1..7`, and are mapped to the 35 `lf=7` columns in the main 336-state Markov model.
- `fa_h2/fuzhu/load_terminal_loh_lookup_h2.m` is the only active lookup mapper for SAA/DRO FA-MSP experiments.

### 4. H2 FA-MSP

- The shared main model is the root `main_msp_h2_near.m` / `run_h2_with_options.m` chain with `fa_h2/*` forward/backward/cut/eval code.
- SAA and DRO do not have separate model algorithms; only the TerminalLOH table option differs in the accepted A/B design.
- The currently archived comparison policies are the one-hour fixed-budget Step-05B `run-003` policies, not formal convergence certificates.

### 5. Common-sample OOS evaluation

- Both archived policies use the same frozen `output_h2/details/h2_OOS.csv` 10000x8 table.
- Step-05B-8 is the primary 10000-path paired performance result.
- Step-05B-9 is the primary terminal-inventory-gain distribution companion.

## Retained history that is not the current two-table mainline

### Wasserstein ground-cost line

Representative sources/docs:

- `terminalLoh_wdro/src/build_wdro_distance_matrix_h2.m`
- `terminalLoh_wdro/src/solve_wdro_terminal_loh_lp_h2.m`
- `terminalLoh_wdro/src/solve_wdro_terminal_loh_lp_constraint_generation_h2.m`
- `terminalLoh_wdro/docs/README_WDRO_distance_DA.md`
- `terminalLoh_wdro/docs/README_WDRO_preview.md`

The probability-DRO handover states that this line stopped because corrected distance scale did not produce satisfactory fixed-loss alignment. It remains evidence and must not be deleted, but it does not generate the current eta=0.03 lookup table.

### Old DAC/Ctilde distance and Dscale/Cscale tuning

Representative sources/results:

- `run_step03P_dac_transport_cost_audit_h2.m`
- `run_step03Q_dctilde_strict_metric_audit_h2.m`
- `run_step03R_ctilde_decision_similarity_audit_h2.m`
- `run_step03ZC_period_ctilde_ground_cost_smoke_h2.m`
- `run_step03ZD_ground_cost_scale_audit_h2.m`
- `run_step03ZE_corrected_period_Dscale_alignment_h2.m`
- results stages 16-40.

These are retained diagnostic history. The current mainline explicitly prohibits returning to Dscale/Cscale or 0.6/0.4 distance-weight tuning as a substitute for probability DRO.

### Historical extreme-aware candidate line

Representative sources/results:

- `run_step04CA_extreme_path_integration_feasibility.py`
- `run_step04CA2_extreme_formal_consequence_freeze_h2.m`
- `run_step04CB_extreme_aware_dro_decision_value_h2.m`
- `solve_terminal_loh_extreme_aware_decomposition_h2.m`
- results stages 43-45.

This line supplied important stress-path evidence, but the formal C6 SAA/eta=0.03 tables and current FA-MSP A/B do not include a separate extreme-risk term.

### wind_mc / roadSoft / RiskCap-Mean preview line

- Entry: `generate_terminal_loh_wind_mc_preview.m`.
- Helpers: `fa_h2/fuzhu/terminalLoh_windmc/`.
- Output: `output_h2/wind_terminal_loh_preview/`.

This remains an older physicalized offline preview and is not the source used by the current SAA/DRO lookup loader. `longtask.md` still labels it as the current stage, which is documentation drift relative to the accepted Step-04C/Step-05 results.

## Configuration boundary

- `data/intensity.csv`, `data/location.csv`, `data/landfall_7.csv`, and `data/yuanqi/*` are active H2 FA-MSP runtime inputs.
- `terminalLoh_wdro/config/*` remains relevant to the archived/offline W3 scenario-generation lineage, but the Step-05 SAA/DRO FA-MSP runtime does not read those files to choose TerminalLOH; it reads the two accepted C6 result CSVs through explicit launcher options.
- `terminalLoh_wdro/docs/PROBABILITY_DRO_MAINLINE_HANDOVER.md` is the principal probability-DRO method handover, while its unique-next-task text before the later appended sections should be interpreted chronologically rather than as the present task boundary.

No historical source or result should be removed merely because it is no longer the active mainline.
