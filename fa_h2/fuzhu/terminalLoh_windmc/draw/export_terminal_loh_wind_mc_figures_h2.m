function export_terminal_loh_wind_mc_figures_h2(diagTables, windMC, optsWind)
%EXPORT_TERMINAL_LOH_WIND_MC_FIGURES_H2 Export offline wind-MC preview figures.

if ~isfield(optsWind, 'outputDir')
    error('export_terminal_loh_wind_mc_figures_h2:MissingOutputDir', ...
        'optsWind.outputDir is required.');
end
if ~isfield(windMC, 'layout')
    error('export_terminal_loh_wind_mc_figures_h2:MissingLayout', ...
        'windMC.layout is required for plotting.');
end

if isfield(optsWind, 'elecFigureDir') && ~isempty(optsWind.elecFigureDir)
    figRoot = optsWind.elecFigureDir;
else
    figRoot = fullfile(optsWind.outputDir, 'figures');
end
dirs = {
    fullfile(figRoot, 'layout')
    fullfile(figRoot, 'storm_states')
    fullfile(figRoot, 'line_maps')
    fullfile(figRoot, 'node_maps')
    fullfile(figRoot, 'terminal_loh')
    fullfile(figRoot, 'summary')
    };
for ii = 1:numel(dirs)
    if ~exist(dirs{ii}, 'dir')
        mkdir(dirs{ii});
    end
end

plot_terminal_loh_layout_overview_h2( ...
    windMC.layout, fullfile(figRoot, 'layout', 'layout_overview.png'));

states = [4 2; 5 4; 6 6];
for ss = 1:size(states, 1)
    a = states(ss, 1);
    loc = states(ss, 2);
    plot_terminal_loh_storm_state_h2(diagTables, windMC, a, loc, ...
        fullfile(figRoot, 'storm_states', sprintf('storm_state_a%d_loc%d.png', a, loc)));

    plot_terminal_loh_line_metric_map_h2(diagTables, windMC, a, loc, "mid", ...
        'wind_speed_mps', '风速（m/s）', [], ...
        fullfile(figRoot, 'line_maps', sprintf('line_windspeed_a%d_loc%d_rmid.png', a, loc)));
    plot_terminal_loh_line_metric_map_h2(diagTables, windMC, a, loc, "mid", ...
        'failure_probability', '故障概率', [0, 0.8], ...
        fullfile(figRoot, 'line_maps', sprintf('line_failureprob_a%d_loc%d_rmid.png', a, loc)));

    plot_terminal_loh_node_outage_map_h2(diagTables, windMC, a, loc, "mid", ...
        fullfile(figRoot, 'node_maps', sprintf('node_outage_prob_a%d_loc%d_rmid.png', a, loc)));
    plot_terminal_loh_site_bar_h2(diagTables.by_state, a, loc, ...
        fullfile(figRoot, 'terminal_loh', sprintf('terminal_loh_bar_a%d_loc%d.png', a, loc)));
end

plot_terminal_loh_summary_h2(diagTables.by_state, 'a', ...
    fullfile(figRoot, 'summary', 'summary_by_a.png'));
plot_terminal_loh_summary_h2(diagTables.by_state, 'loc', ...
    fullfile(figRoot, 'summary', 'summary_by_loc.png'));

export_selected_line_diagnostics_h2(diagTables, 5, 4, "mid", ...
    fullfile(figRoot, 'line_maps', 'selected_lines_diagnostics_a5_loc4_rmid.csv'), ...
    fullfile(figRoot, 'line_maps', 'selected_lines_diagnostics_a5_loc4_rmid.png'));

fprintf('终端储氢需求风场蒙特卡洛图片已输出到:\n%s\n', figRoot);
end
