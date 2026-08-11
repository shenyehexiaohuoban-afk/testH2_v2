# TerminalLOH to H2 FA-MSP interface audit

## 1. Frozen formal lookup tables

SAA:

```text
results/task-002-stage2b-b3-smoke/53-35state-saa-vs-eta003-terminal-loh/run-024/terminal_loh_table_saa.csv
SHA-256: 2a47fbe844633e20f588add221b75fa2c2d8293694ab5d9ed80e299fe29086d4
```

Pearson chi-square DRO, eta=0.03:

```text
results/task-002-stage2b-b3-smoke/53-35state-saa-vs-eta003-terminal-loh/run-024/terminal_loh_table_eta_003.csv
SHA-256: 077d8b86f7f4ab896a61dbfe5e446476f3adcedc4ad7ffc98e29855b834ea1aa
```

Both files have 35 rows and 11 columns:

```text
state_id,state_label,intensity,loc,lfw,eta,
T1_kg,T2_kg,T3_kg,T4_kg,TerminalLOH_total_kg
```

The effective TerminalLOH decision table is therefore 35 states by 4 stations. `state_id` is exactly `1:35`; `intensity` is `2:6`; `loc` is `1:7`; the source-generation label `lfw` is frozen at zero. The SAA eta column is zero and the DRO eta column is 0.03.

## 2. Evidence that `eta_003` means eta=0.03

This is mechanically established in three independent places:

1. The accepted C6 `run-024/README.md` explicitly states that the token `eta003` means `eta=0.03`, not `eta=0.003`.
2. Every row of `terminal_loh_table_eta_003.csv` has `eta=0.03`.
3. `fa_h2/fuzhu/load_terminal_loh_lookup_h2.m:72-82` requires `expectedEta=0.03` whenever `terminal_loh_mode='chi2_eta003'` and rejects any mismatch.

The filename is historically compact and potentially ambiguous, but the runtime meaning is not ambiguous.

## 3. Loader and 35-state to 336-state mapping

`load_data_h2_near.m` performs the interface assembly:

```text
load_data_h2_near.m
  -> fa_h2/fuzhu/build_terminal_loh_h2.m       [construct legacy baseline]
  -> if terminal_loh_mode ~= legacy:
       fa_h2/fuzhu/load_terminal_loh_lookup_h2.m [replace with frozen lookup]
  -> params.TerminalLOH = TerminalLOH
```

The lookup mapper enforces:

```text
state_id = (intensity - 2) * 7 + loc
main MSP target state: (a=intensity, loc=loc, lf=7)
k = ((a - 1) * 7 + (loc - 1)) * 8 + 7
```

It builds `TerminalLOH=zeros(4,336)`, writes each table row into exactly one `lf=7` column, and requires every non-target column to remain zero. Station order is exactly `T1_kg,T2_kg,T3_kg,T4_kg`.

The mapper also performs frozen negative/positive controls:

- state7 must be exactly zero in both tables;
- state13 must match the mode-specific frozen vector;
- state19 must match the mode-specific frozen vector;
- row totals must equal `TerminalLOH_total_kg`;
- targets must not exceed active tank capacities.

## 4. How the table enters `params.TerminalLOH`

`load_data_h2_near.m:134-142` first constructs the daily legacy TerminalLOH and then, for `terminal_loh_mode='saa'` or `'chi2_eta003'`, calls `load_terminal_loh_lookup_h2` to replace it. Lines 211-214 store:

```text
params.TerminalLOH
params.terminal_loh_mode
params.terminal_impact_template_used / lookup source
params.terminal_loh_lookup_audit
```

This initial legacy construction is not evidence of table contamination: the non-legacy branch replaces the entire 4x336 array and the lookup loader requires all non-target columns to be zero. It is, however, a useful implementation detail for future audits.

## 5. Where lf=7 is defined and evaluated

The Markov joint state has `Na=6`, `Nb=7`, `Nc=8`, and `K=336`. In `load_data_h2_near.m`:

```text
is_loh_demand_stage = (a > 1 && lf == Nc - 1) = lf=7
is_terminal_landfall = (lf == Nc) = lf=8
is_absorbing = dissipated or lf=8
```

The terminal check is a reserve adequacy check, not an inventory withdrawal:

```text
gap_i = max(0, TerminalLOH_i(k) - x_i)
terminal_value = cost_reserve_shortage * sum_i(gap_i)
```

The current frozen reserve-gap penalty remains 2000 yuan/kg in the accepted FA-MSP experiments.

- Training forward path: `fa_h2/forward_pass_h2.m:34-40` calls `eval_terminal_loh_h2` at an lf=7 state, records the terminal cost/shortage, keeps inventory unchanged, and absorbs the path.
- OOS evaluation: `fa_h2/eval_h2.m:68-77` calls the same terminal evaluator and records path terminal shortage/cost.
- `lf=8` is a zero-cost absorbing boundary and creates no new TerminalLOH check.

## 6. Terminal value/subgradient to backward cuts

`fa_h2/fuzhu/terminal_value_and_subgradient_h2.m` implements the analytic convex future value:

```text
V_k(x) = p * sum_i max(0, TerminalLOH_i(k) - x_i)
g_i = -p when x_i < TerminalLOH_i(k) - 1e-9
g_i = 0 otherwise
```

where `p=params.cost_reserve_shortage`.

Propagation chain:

```text
params.TerminalLOH(:,k)
  -> terminal_value_and_subgradient_h2(x_trial,params,k)
  -> backward_pass_h2 builds Q(k), gState(k,:)
  -> P_joint(n,:) probability-weights Q and g
  -> alpha = Qvalue - g' * x_trial
  -> add_cut_h2 installs theta >= alpha + g' * x
  -> next forward pass solves the same stage model with the appended cuts
```

`add_cut_h2.m` encodes the inequality as one new model row with station-inventory coefficients `g`, theta coefficient `-1`, and right-hand side `-alpha`.

Accepted Step-05A1 `run-001` provides runtime propagation evidence: both tables reached terminal value/subgradient, generated different first cuts in 1156 stage-state models, and the next forward iteration responded to the updated cuts.

## 7. How experiments switch tables

The switch is at the options/launcher layer, not inside the mathematical core:

```text
opts.terminal_loh_mode = 'saa' | 'chi2_eta003'
opts.terminal_loh_lookup_file = <one of the two run-024 CSV files>
```

Accepted experiment interfaces:

- `run_main_msp_h2_native_smoke.m` reads `STEP05A1_TERMINAL_MODE` for the short dual-table smoke.
- `run_main_msp_h2_fixed_budget_ab.m` reads `STEP05B_TERMINAL_MODE` for the accepted one-hour fixed-budget A/B policies.
- `run_main_msp_h2_converged_ab.m` uses the same table switch but is not the source of an accepted converged A/B result.

No separate SAA/DRO copy of forward, backward, cut, model, or evaluation code exists.
