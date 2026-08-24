# Resolved Stage89Q Pmax smoke call chain

`orchestrate_stage89q_pmax_dual_10iter_smoke.ps1`
-> `run_stage89q_pmax_dual_10iter_smoke_h2.m`
-> `load_current_stage89_hourly_h2.m`
-> `current_hourly_stage88_candidate_options_h2.m`
-> `build_stage88_candidate_msp_input_h2.m`
-> `load_data_h2_near.m`
-> `load_hourly_grid_data_h2.m`
-> isolated candidate override (`params.el_cap_kw`; derived `params.hourly_grid.pmax_kw`)
-> `define_models_h2.m`
-> `build_stage_model_h2.m`
-> `build_integrated_hourly_stage_model_h2.m`
-> `build_integrated_hourly_stage_model_hourly_htt_v1_h2.m`
-> `forward_pass_h2.m`
-> `update_rhs_h2.m` / `update_integrated_hourly_stage_model_hourly_htt_v1_h2.m`
-> `solve_stage_model_h2.m`
-> `backward_pass_h2.m`
-> `add_cut_h2.m`
-> task-local checkpoint serializer
-> clean-process reload and QA

The formal Stage89Q long-training runner is the mechanically resolved lineage source. It is not executed directly and `main_msp_h2_near.m` is not used.
