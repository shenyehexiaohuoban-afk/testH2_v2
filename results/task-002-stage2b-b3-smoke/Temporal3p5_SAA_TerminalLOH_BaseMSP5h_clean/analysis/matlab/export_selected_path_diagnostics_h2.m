function export_selected_path_diagnostics_h2(diagInfo, outDir, opts)
%EXPORT_SELECTED_PATH_DIAGNOSTICS_H2 Write selected-path diagnostics to CSV.
%
% CSV outputs are diagnostic only and are not used by training/evaluation.

if nargin < 3 || isempty(opts)
    opts = struct();
end
if ~exist(outDir, 'dir')
    mkdir(outDir);
end

writetable(diagInfo.selected_summary, fullfile(outDir, 'selected_path_summary.csv'));
writetable(diagInfo.timeseries, fullfile(outDir, 'selected_paths_timeseries.csv'));
writetable(diagInfo.site_balance, fullfile(outDir, 'selected_paths_site_balance.csv'));
writetable(diagInfo.transport_edges, fullfile(outDir, 'selected_paths_transport_edges.csv'));
writetable(diagInfo.cost_breakdown, fullfile(outDir, 'selected_paths_cost_breakdown.csv'));
writetable(diagInfo.loh_demand_detail, fullfile(outDir, 'selected_paths_loh_demand_detail.csv'));
if isfield(diagInfo, 'transition_expectation')
    writetable(diagInfo.transition_expectation, ...
        fullfile(outDir, 'selected_paths_transition_expectation.csv'));
end
if isfield(diagInfo, 'transition_expectation_summary')
    writetable(diagInfo.transition_expectation_summary, ...
        fullfile(outDir, 'selected_paths_transition_expectation_summary.csv'));
end
if isfield(diagInfo, 'cut_marginal_value')
    writetable(diagInfo.cut_marginal_value, ...
        fullfile(outDir, 'selected_paths_cut_marginal_value.csv'));
end
save(fullfile(outDir, 'selected_path_diagnostics.mat'), 'diagInfo', '-v7.3');
write_readme(outDir);
write_analysis_readme(outDir);

if isfield(opts, 'exportDiagnosticFigures') && opts.exportDiagnosticFigures
    try
        export_figures(diagInfo, fullfile(outDir, 'selected_path_figures'));
    catch ME
        warning('export_selected_path_diagnostics_h2:FigureExportFailed', ...
            'Failed to export diagnostic figures: %s', ME.message);
    end
end
end

function write_readme(outDir)
txt = [
"Selected path diagnostics for H2 FA-MSP"
""
"Files:"
"- selected_path_summary.csv: one row per selected OOS path, including selection type, cost, beta, production, transport, and LOH shortage totals."
"- selected_paths_timeseries.csv: one row per selected path and stage. It tracks state, beta, x totals, production, demand service, HTT transport, TerminalLOH, and stage costs."
"- selected_paths_site_balance.csv: one row per path, stage, and site. It explains LOH changes through production, normal demand, transport in/out, and balance residual."
"- selected_paths_transport_edges.csv: one row per directed HTT edge and stage, including f_ij, distance, beta-adjusted cost, and edge transport cost."
"- selected_paths_cost_breakdown.csv: one row per path and stage. Actual OOS stage cost excludes theta; theta is diagnostic only."
"- selected_paths_loh_demand_detail.csv: site-level comparison of x_before_demand and TerminalLOH at the lf=Nc-1 LOH demand/check stage."
"- selected_paths_transition_expectation.csv: next-state transition probabilities and weighted next-step TerminalLOH for each selected normal stage."
"- selected_paths_transition_expectation_summary.csv: expected next-step TerminalLOH by selected path and normal stage."
"- selected_paths_cut_marginal_value.csv: active future-value cut slope by site at each selected normal stage."
""
"Status values:"
"- normal: ordinary non-terminal stage with production, normal H2 demand, storage, and HTT movement."
"- loh_demand_stage: lf=Nc-1 demand/check stage. TerminalLOH shortage is evaluated once here."
"- absorbing_lfNc: lf=Nc zero-cost absorbing state. No new LOH demand is created."
"- dissipated_absorb: a=1 dissipated state with zero cost."
"- post_absorb: stages after demand/absorption has already been reached; cost is zero and x is carried forward."
""
"Definitions:"
"- x_before/x_after are site LOH values immediately before/after the stage."
"- TerminalLOH is a reserve requirement evaluated only at lf=Nc-1, not an inventory withdrawal."
"- lf=Nc is an absorbing boundary with cost 0."
"- beta is transport friction/risk. It affects ordinary-stage HTT capacity/cost and is not an absorbing flag."
"- balance_residual should be close to 0 in normal stages: x_after - (x_before + production + transport_in - transport_out - normal_served)."
];
fid = fopen(fullfile(outDir, 'selected_path_diagnostics_README.txt'), 'w');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', txt);
end

function write_analysis_readme(outDir)
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

function export_figures(diagInfo, figDir)
if ~exist(figDir, 'dir')
    mkdir(figDir);
end
paths = unique(diagInfo.timeseries.path_id);
for pp = 1:numel(paths)
    pid = paths(pp);
    rows = diagInfo.timeseries(diagInfo.timeseries.path_id == pid, :);
    siteRows = diagInfo.site_balance(diagInfo.site_balance.path_id == pid, :);

    f1 = figure('Visible', 'off');
    tiledlayout(2, 1);
    nexttile;
    plot(rows.t, rows.a, '-o'); hold on;
    plot(rows.t, rows.loc, '-s');
    plot(rows.t, rows.lf, '-^');
    legend({'a','loc','lf'}, 'Location', 'best');
    xlabel('stage'); ylabel('state');
    nexttile;
    plot(rows.t, rows.beta, '-o');
    xlabel('stage'); ylabel('beta');
    saveas(f1, fullfile(figDir, sprintf('path_%d_state_beta.png', pid)));
    close(f1);

    f2 = figure('Visible', 'off');
    plot(rows.t, rows.x_total_before, '-o'); hold on;
    plot(rows.t, rows.x_total_after, '-s');
    plot(rows.t, rows.TerminalLOH_total, '--');
    legend({'x before','x after','TerminalLOH'}, 'Location', 'best');
    xlabel('stage'); ylabel('kg');
    saveas(f2, fullfile(figDir, sprintf('path_%d_loh_total.png', pid)));
    close(f2);

    f3 = figure('Visible', 'off');
    hold on;
    sites = unique(siteRows.site_id);
    for ss = 1:numel(sites)
        sr = siteRows(siteRows.site_id == sites(ss), :);
        plot(sr.t, sr.x_after, '-o', 'DisplayName', sprintf('site %d', sites(ss)));
    end
    legend('Location', 'best');
    xlabel('stage'); ylabel('x after kg');
    saveas(f3, fullfile(figDir, sprintf('path_%d_loh_by_site.png', pid)));
    close(f3);

    f4 = figure('Visible', 'off');
    plot(rows.t, rows.production_total, '-o'); hold on;
    plot(rows.t, rows.htt_transport_total, '-s');
    plot(rows.t, rows.normal_served_total, '-^');
    legend({'production','HTT transport','normal served'}, 'Location', 'best');
    xlabel('stage'); ylabel('kg');
    saveas(f4, fullfile(figDir, sprintf('path_%d_operations.png', pid)));
    close(f4);
end
end
