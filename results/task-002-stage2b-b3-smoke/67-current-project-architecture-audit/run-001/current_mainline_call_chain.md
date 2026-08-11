# Current H2 FA-MSP call-chain audit

## 1. Daily native entry

The actual daily entry is the root-level MATLAB script `main_msp_h2_near.m`. Only one file with this exact name exists in the scanned repository.

```text
main_msp_h2_near.m
  -> h2_default_options.m
  -> run_h2_with_options.m
       -> load_data_h2_near.m
       -> fa_h2/define_models_h2.m
            -> fa_h2/build_stage_model_h2.m
       -> fa_h2/train_models_h2.m
            -> fa_h2/forward_pass_h2.m
                 -> fa_h2/update_rhs_h2.m
                 -> fa_h2/solve_stage_model_h2.m
                 -> fa_h2/fuzhu/eval_terminal_loh_h2.m at an lf=7 hit
            -> fa_h2/backward_pass_h2.m
                 -> fa_h2/fuzhu/terminal_value_and_subgradient_h2.m for lf=7 states
                 -> fa_h2/update_rhs_h2.m + fa_h2/solve_stage_model_h2.m for ordinary states
                 -> fa_h2/add_cut_h2.m
       -> fa_h2/eval_h2.m
            -> fa_h2/update_rhs_h2.m + fa_h2/solve_stage_model_h2.m
            -> fa_h2/fuzhu/eval_terminal_loh_h2.m at an lf=7 hit
```

Mechanical source evidence:

- `main_msp_h2_near.m:8` calls `h2_default_options(rootDir)` and line 17 calls `run_h2_with_options(opts)`.
- `run_h2_with_options.m:43` calls `load_data_h2_near`; line 72 calls `define_models_h2`; line 83 calls `train_models_h2`; line 88 calls `eval_h2`.
- `define_models_h2.m:11` calls `build_stage_model_h2` and creates LP templates only for ordinary states.
- `train_models_h2.m:20-21` performs one forward pass, and line 38 performs one backward pass unless a stop condition was already met.
- `backward_pass_h2.m:52` passes the probability-weighted affine future-value approximation to `add_cut_h2`.
- The updated `modelLib` returned by the backward pass is supplied to the next training-loop forward pass; this propagation was also observed in accepted Step-05A0B/Step-05A1 smoke results.

## 2. Runtime paths and random/OOS controls

- `run_h2_with_options.m` adds the repository root, `fa_h2`, `fa_h2/fuzhu`, and `utils` to the MATLAB path.
- It calls `rng(opts.seed,'twister')`; the shared default seed is `20260513`.
- Training paths are sampled by `utils/mc_sample.m` from `params.P_joint`.
- Evaluation reads `params.oosFile`; the accepted Step-05B comparison freezes this to `output_h2/details/h2_OOS.csv` and does not regenerate it.

## 3. Daily default versus accepted SAA/DRO experiment entry

The daily entry is not itself switched to the new lookup tables:

- `h2_default_options.m` sets `terminal_loh_mode='legacy'`.
- `main_msp_h2_near.m` changes `terminal_load_mode`, time limit, beta, shortage multiplier, and output directory, but does not override `terminal_loh_mode`.
- Therefore daily native execution still uses `terminal_impact_template.csv -> build_terminal_loh_h2`.

The accepted SAA/DRO research experiments use thin launchers that retain the same `run_h2_with_options` chain:

- `run_main_msp_h2_native_smoke.m`: safe native smoke; optional `STEP05A1_TERMINAL_MODE=saa|chi2_eta003` for Step-05A1.
- `run_main_msp_h2_fixed_budget_ab.m`: accepted one-hour SAA/DRO A/B launcher; `STEP05B_TERMINAL_MODE=saa|chi2_eta003`.
- `run_main_msp_h2_converged_ab.m`: formal-stall-stop launcher exists, but there is no accepted converged SAA/DRO A/B result in the current results map.

## 4. Alternate and historical entries

- `run_h2_ablation_suite.m` is an alternate ablation launcher, not the daily main entry.
- `generate_terminal_loh_wind_mc_preview.m` is an older offline preview entry; it calls data-loading helpers but does not train the main MSP.
- `terminalLoh_wdro/src/run_terminal_loh_wdro_preview_h2.m` and the `solve_wdro_*` family are historical Wasserstein/offline TerminalLOH programs, not current FA-MSP entry points.
- No second tracked copy of `main_msp_h2_near.m`, `run_h2_with_options.m`, or the principal `fa_h2/*` function names was found. The main ambiguity comes from purpose-specific launchers and historical offline modules, not duplicate same-name implementations.
