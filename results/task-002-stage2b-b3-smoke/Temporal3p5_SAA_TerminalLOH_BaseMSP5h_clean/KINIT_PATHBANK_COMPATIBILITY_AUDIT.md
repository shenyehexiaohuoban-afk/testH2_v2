# K_INIT / Path-Bank Identity Audit

Static-only audit performed 2026-08-26. No training, OOS, analysis, B1011 run, or checkpoint write was performed.

## Resolved identities

- Stage89Q formal Base checkpoint: `params.k_init=81`. Its `opts.k_init=65` is legacy option residue; the accepted Stage89Q loader remaps the loaded base state to the same intensity/landfall state at `loc=4`, yielding state 81.
- B0001 formal checkpoint: `params.k_init=81`, from `B0001/training/run_candidate_formal_h2.m` (`baseState -> initialA/initialLf -> state_id(initialA,4,initialLf)`) and the same Stage89Q launcher remap.
- R3 checkpoint: `params.k_init=65`, from the inherited Base `h2_default_options.m` default because the R3 runner did not apply the Stage89Q `loc=4` remap.
- Canonical Base default: `K_INIT=81`, explicit in `RUN_CONFIG.txt` and `program/base_reference_options_h2.m`; training callers propagate `CANDIDATE_K_INIT` and checkpoint metadata.

## Canonical bank

`results/task-002-stage2b-b3-smoke/89H-stage85r-single-loc4-stage88-dro-gap1000-10iter-oos10000/run-003/oos/loc4/oos_path_bank.mat`

The accepted ordered manifest has 10000 rows. The unique first-stage state set is `[81]`; the first path is `[81,91,110,87,96,48,56,56]`.

## Testing contract

`program/validate_checkpoint_pathbank_compatibility.m` is called before `eval_h2`. It checks checkpoint `params.k_init`, a unique bank first-state identity, equality of those identities, the requested model cell and struct type, `beq`, `rowMap.inventory_eq`, and valid inventory equality indices. Failure evidence is saved with `CHECKPOINT_PATHBANK_COMPATIBILITY_QA = FAIL` and `FAILURE_CLASS = CHECKPOINT_PATHBANK_INITIAL_STATE_MISMATCH` before exiting.
