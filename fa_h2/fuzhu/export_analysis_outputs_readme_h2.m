function export_analysis_outputs_readme_h2(outDir)
%EXPORT_ANALYSIS_OUTPUTS_README_H2 Write README for H2 analysis CSV outputs.

if ~exist(outDir, 'dir')
    mkdir(outDir);
end

txt = [
"H2 analysis output notes"
""
"terminal_load_mode:"
"- node_load uses IEEE33 node active load as the possible lost-load scale, then converts kW to kg H2 with support_hours / (eta_FC * LHV_H2)."
"- critical_load uses the older CriticalLoad.H_node_kg critical-load scale for comparison."
""
"terminal_load_check.csv:"
"- node, P_node_load_kw, P_critical_base_kw_if_available, critical_to_node_ratio, H_node_load_kg, and H_node_critical_kg_if_available compare the two scales."
"- The summary row reports total_P_node_load_kw, total_P_critical_base_kw, total_H_node_load_kg, and total_H_node_critical_kg in the same columns."
""
"selected_paths_transition_expectation.csv:"
"- For each selected normal stage, it enumerates one-step next states, transition_probability, next-state TerminalLOH by site, and probability-weighted TerminalLOH."
"- The summary file aggregates P_next_loh_demand_stage and expected next-step TerminalLOH by site."
""
"selected_paths_cut_marginal_value.csv:"
"- For each selected normal stage and site, it reports the active future-value cut slope at the current x solution."
"- marginal_value_of_1kg_LOH is -slope; larger values mean one more kg at that site has larger estimated future cost reduction."
""
"oos_risk_metrics.csv:"
"- VaR and CVaR are empirical OOS post-processing metrics. They are not part of the MSP objective and do not change cuts."
""
"Cost stages:"
"- absorbing_lfNc, dissipated_absorb, and post_absorb stages have zero ordinary cost terms because no production, transport, holding, or normal demand LP is solved after absorption."
""
"Runtime and folders:"
"- opts.time_limit = 3600 in main_msp_h2_near.m is the daily main setting; run_h2_ablation_suite quick mode uses 600 seconds per experiment."
"- fa_h2/fuzhu contains helper, diagnostic, and export functions. It is not an output directory."
];

fid = fopen(fullfile(outDir, 'analysis_outputs_README.txt'), 'w');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', txt);
end
