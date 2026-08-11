# Step-05B-10 current project architecture audit

Status: **PASS**

This run freezes a read-only navigation map of the repository at branch `task/002-stage2b-b3-smoke` and commit `091cde8c617e44f5190f1f277042ddfc7752d65b`.

The audit used only source inspection, accepted README/judgment files, CSV metadata, Git metadata, file hashes, and directory scans. It did not run MATLAB or Gurobi, train or evaluate a policy, resample OOS paths, generate cuts, change TerminalLOH, change 200/2000, or modify any existing result.

## Primary conclusions

- The daily H2 FA-MSP entry is `main_msp_h2_near.m`.
- Its native call chain is `h2_default_options -> run_h2_with_options -> load_data_h2_near -> define_models_h2 -> train_models_h2 -> forward_pass_h2/backward_pass_h2/add_cut_h2 -> eval_h2`.
- The daily entry still defaults to legacy `terminal_impact_template.csv` TerminalLOH. The accepted SAA versus eta=0.03 research comparison uses the separate thin launchers and options layer to inject two frozen 35-state lookup tables into the same unchanged FA-MSP chain.
- The current probability-DRO research mainline is finite-support SAA versus flat Pearson chi-square probability DRO, followed by 35-state TerminalLOH lookup, H2 FA-MSP training, and common-sample OOS evaluation.
- Historical Wasserstein/DAC/Ctilde/distance-scale/extreme-aware modules remain in the repository as retained evidence, but they are not the source of the current two FA-MSP lookup tables.

## Output guide

- `current_repository_tree.txt`: task-oriented repository tree and local/Git storage boundaries.
- `current_mainline_call_chain.md`: verified native and experiment-entry call chains.
- `terminal_loh_to_msp_interface.md`: exact SAA/DRO table paths, 35-to-336 mapping, and terminal-value/cut propagation.
- `current_results_stage_index.csv`: accepted/failed stage map from Step-04C-C6 through Step-05B-9.
- `current_mainline_vs_history.md`: current research line versus retained historical modules.
- `architecture_judgment.txt`: bounded architecture judgment, known documentation/name drift, and minimum future task reading list.

No Commit or Push was performed for this task.
