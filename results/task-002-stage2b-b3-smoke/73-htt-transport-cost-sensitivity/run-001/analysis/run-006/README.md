# Stage-73 E1-8h HTT transport-cost sensitivity

Status: PASS. This directory is the accepted unified postprocess for run-001 after independent mechanical verification and visual QA.

Reference c_d=0.8 reuses the accepted Stage-71 E1 policy. H04/H02/H01 change only c_d to 0.4/0.2/0.1 and use one-hour fixed-budget policies. All eight evaluations use the same frozen 10000x8 OOS state paths and 6053 terminal-hit paths.

The full path-stage-directed-OD archives remain in each case directory. `htt_directed_od_path_stage_manifest.csv` records paths, row counts, bytes, and SHA-256 without copying roughly 400 MB into this analysis directory.

Interpretation limits: stop_flag=2 is not formal convergence; static terminal surplus-gap coverage is not nonanticipative recourse feasibility; separately trained policy contrasts are descriptive rather than pure causal estimates. No coefficient is automatically adopted as a formal model value.

Primary results are in `transport_cost_sensitivity_summary.csv`, `htt_by_stage.csv`, `htt_od_summary.csv`, `htt_utilization_summary.csv`, `htt_flow_quality_audit.csv`, `spatial_mismatch_comparison.csv`, `production_inventory_shortage_cost.csv`, `deltaI_comparison.csv`, `mechanical_verification.txt`, and `transport_cost_judgment.txt`.
