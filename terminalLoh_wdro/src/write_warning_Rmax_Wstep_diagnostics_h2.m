function write_warning_Rmax_Wstep_diagnostics_h2(result, config)
%WRITE_WARNING_RMAX_WSTEP_DIAGNOSTICS_H2 Write sweep diagnostics and plots.

if ~exist(config.outputDir, 'dir')
    mkdir(config.outputDir);
end
figDir = fullfile(config.outputDir, 'figures');
if ~exist(figDir, 'dir')
    mkdir(figDir);
end

write_y_base_solution(result, config);
writetable(result.geometry_by_loc, fullfile(config.outputDir, ...
    'warning_geometry_by_loc.csv'));
writetable(result.full_risk, fullfile(config.outputDir, ...
    'Rmax_Wstep_full_risk_table.csv'));
writetable(result.stage_summary, fullfile(config.outputDir, ...
    'Rmax_Wstep_stage_summary.csv'));
writetable(result.candidate_indicators, fullfile(config.outputDir, ...
    'Wstep_candidate_indicators.csv'));
writetable(result.candidate_ranking, fullfile(config.outputDir, ...
    'Wstep_candidate_ranking.csv'));
writetable(result.sensitivity_summary, fullfile(config.outputDir, ...
    'Rmax_sensitivity_summary.csv'));
write_parameter_snapshot(result, config);
write_diagnostics_summary(result, config);
write_warning_figures(result, config, figDir);
end

function write_y_base_solution(result, config)
s = result.y_base_solution;
tbl = table(s.y_base, s.warning_distance_target, ...
    s.minimum_actual_distance, s.closest_loc, string(s.closest_object_type), ...
    s.closest_object_id, s.distance_error, s.center_x, s.center_y, ...
    s.closest_x, s.closest_y, ...
    'VariableNames', {'y_base', 'warning_distance_target', ...
    'minimum_actual_distance', 'closest_loc', 'closest_object_type', ...
    'closest_object_id', 'distance_error', 'center_x', 'center_y', ...
    'closest_object_x', 'closest_object_y'});
writetable(tbl, fullfile(config.outputDir, 'warning_y_base_solution.csv'));
end

function write_parameter_snapshot(result, config)
key = ["warning_distance_km_eq"; "Rmax_values"; "Wstep_values"; ...
    "stage_names"; "stage_offsets"; "a_values"; "loc_count"; ...
    "windDecayB"; "designWindSpeedVN"; "roadDesignWindVN"; ...
    "distance_method"; "Rmax_probability_assigned"; ...
    "D_A_C_generated"; "WDRO_run"; "MSP_modified"];
value = [string(config.warningDistanceKmEq); ...
    strjoin(string(config.RmaxValues), "|"); ...
    strjoin(string(config.WstepValues), "|"); ...
    strjoin(string(config.stageNames), "|"); ...
    strjoin(string(config.stageOffsets), "|"); ...
    strjoin(string(config.aValues), "|"); ...
    string(height(result.loc_table)); string(config.windDecayB); ...
    string(config.designWindSpeedVN); string(config.roadDesignWindVN); ...
    "grid and road point-to-segment distance"; "no"; "no"; "no"; "no"];
snapshot = table(key, value, 'VariableNames', {'key', 'value'});
writetable(snapshot, fullfile(config.outputDir, 'parameter_snapshot.csv'));
end

function write_diagnostics_summary(result, config)
fileName = fullfile(config.outputDir, 'diagnostics_summary.txt');
fid = fopen(fileName, 'w');
if fid < 0
    error('write_warning_Rmax_Wstep_diagnostics_h2:OpenFailed', ...
        'Could not open %s.', fileName);
end
cleanup = onCleanup(@() fclose(fid));

ranking = result.candidate_ranking;
recommended = ranking(ranking.rank == 1, :);
second = ranking(ranking.rank == 2, :);
if isempty(second)
    secondW = NaN;
else
    secondW = second.Wstep(1);
end

fprintf(fid, 'Stage2 Foundation warning-distance Rmax/Wstep sweep\n\n');
fprintf(fid, 'Scope: spatial and risk diagnostics only. No D/A/C samples were generated, WDRO was not run, MSP main model was not modified, and old outputs were not overwritten.\n\n');
fprintf(fid, 'Warning distance target: %.12g km-equivalent.\n', config.warningDistanceKmEq);
fprintf(fid, 'Solved y_base: %.12g.\n', result.y_base_solution.y_base);
fprintf(fid, 'Minimum actual distance: %.12g, closest loc=%g, closest object=%s %g, error=%.12g.\n\n', ...
    result.y_base_solution.minimum_actual_distance, ...
    result.y_base_solution.closest_loc, ...
    string(result.y_base_solution.closest_object_type), ...
    result.y_base_solution.closest_object_id, ...
    result.y_base_solution.distance_error);

fprintf(fid, 'Rmax values tested: %s. No probabilities were assigned to Rmax support points.\n', ...
    strjoin(string(config.RmaxValues), ', '));
fprintf(fid, 'Wstep candidates tested: %s.\n\n', ...
    strjoin(string(config.WstepValues), ', '));

fprintf(fid, 'Recommendation:\n');
fprintf(fid, '- recommended_Wstep = %.12g\n', recommended.Wstep(1));
fprintf(fid, '- second_best_Wstep = %.12g\n', secondW);
fprintf(fid, '- reason = %s\n', string(recommended.reason(1)));
fprintf(fid, '- limitations = %s\n\n', string(recommended.limitations(1)));

fprintf(fid, 'Rmax=40 p95/max stage summary by Wstep:\n');
for ww = config.WstepValues(:).'
    rows = result.stage_summary(result.stage_summary.Rmax == 40 & ...
        result.stage_summary.Wstep == ww, :);
    rows = sortrows(rows, 'stage_index');
    fprintf(fid, '- Wstep %.12g line_pFail_p95=%s line_pFail_max=%s road_pClose_p95=%s road_pClose_max=%s\n', ...
        ww, strtrim(sprintf('%.6g ', rows.line_pFail_p95_p95)), ...
        strtrim(sprintf('%.6g ', rows.line_pFail_max_max)), ...
        strtrim(sprintf('%.6g ', rows.road_pClose_p95_p95)), ...
        strtrim(sprintf('%.6g ', rows.road_pClose_max_max)));
end
fprintf(fid, '\n');

fprintf(fid, 'Candidate ranking:\n');
for rr = 1:height(ranking)
    fprintf(fid, '- rank %d: Wstep=%.12g, score=%.6g, reason=%s, limitations=%s\n', ...
        ranking.rank(rr), ranking.Wstep(rr), ranking.overall_score(rr), ...
        string(ranking.reason(rr)), string(ranking.limitations(rr)));
end

fprintf(fid, '\nAnomaly checks:\n');
anom = result.anomalies;
fprintf(fid, '- distance decreases but local wind decreases: %d (can occur inside Rmax radial profile).\n', anom.distance_decreases_but_wind_decreases);
fprintf(fid, '- many p95=0 but max high: %d.\n', anom.p95_zero_but_max_high);
fprintf(fid, '- risk dominated by extreme a/loc cases: %d.\n', anom.risk_extreme_case_dominated);
fprintf(fid, '- all Wstep risks nearly same: %d.\n', anom.all_Wstep_risks_nearly_same);
fprintf(fid, '- road pClose always zero: %d.\n', anom.road_pClose_always_zero);
fprintf(fid, '- line risk saturated at lf7: %d.\n', anom.line_risk_lf7_saturated);
fprintf(fid, '- Wstep=50 may skip main band: %d.\n', anom.Wstep50_skips_main_band);
fprintf(fid, '- Wstep=30 W3 not main impact: %d.\n', anom.Wstep30_W3_not_main_impact);
fprintf(fid, '- coordinate scale issue: %d.\n', anom.coordinate_scale_issue);
fprintf(fid, '- road distance uses segment distances, not midpoint approximation: %d.\n', anom.road_distance_segment_not_midpoint);
fprintf(fid, '- old a-to-Rmax table called: %d.\n', anom.old_a_to_Rmax_table_called);
fprintf(fid, '- Rmax randomized across stages: %d.\n\n', anom.Rmax_randomized_across_stage);

fprintf(fid, 'Interpretation notes:\n');
fprintf(fid, '- Positive y is now treated as typhoon motion from south toward and through the system.\n');
fprintf(fid, '- km-equivalent is an internal project coordinate scale, not a real GIS distance.\n');
fprintf(fid, '- warning_distance_km_eq=100 is a modeling distance for TerminalLOH pre-layout diagnostics, not an official meteorological warning line.\n');
fprintf(fid, '- Rmax=30/40/50 are sensitivity support points and have no formal probability in this diagnostic.\n');
fprintf(fid, '- The recommendation is not applied to Stage2B2/B3/Stage2C by this run.\n');
end

function write_warning_figures(result, config, figDir)
plot_spatial_overview(result, config, fullfile(figDir, 'spatial_overview_warning100.png'));
for ww = config.WstepValues(:).'
    plot_wstep_centers(result, config, ww, fullfile(figDir, ...
        sprintf('center_positions_Wstep_%g_Rmax40.png', ww)));
end
plot_stage_metric(result, 40, 'line_pFail_p95_p95', ...
    'line pFail p95 by stage (Rmax=40)', ...
    fullfile(figDir, 'line_pFail_p95_by_stage_Rmax40.png'));
plot_stage_metric(result, 40, 'road_pClose_p95_p95', ...
    'road pClose p95 by stage (Rmax=40)', ...
    fullfile(figDir, 'road_pClose_p95_by_stage_Rmax40.png'));
plot_sensitivity(result, fullfile(figDir, 'Rmax_sensitivity_summary.png'));
plot_ranking(result, fullfile(figDir, 'Wstep_candidate_ranking.png'));
end

function plot_spatial_overview(result, config, outFile)
fig = figure('Visible', 'off', 'Color', 'w');
ax = axes(fig);
hold(ax, 'on');
plot_segments(ax, result.grid_segments, [0.1 0.3 0.9], 1.4);
plot_segments(ax, result.road_segments, [0.55 0.55 0.55], 0.8);
scatter(ax, result.site_table.x_km, result.site_table.y_km, 50, 's', ...
    'filled', 'MarkerFaceColor', [0.0 0.45 0.35]);
locX = result.loc_table.x_coord;
locY = repmat(result.y_base_solution.y_base, height(result.loc_table), 1);
scatter(ax, locX, locY, 30, 'v', 'filled', 'MarkerFaceColor', [0.8 0.1 0.1]);
plot(ax, [result.y_base_solution.center_x, result.y_base_solution.closest_x], ...
    [result.y_base_solution.center_y, result.y_base_solution.closest_y], ...
    'r-', 'LineWidth', 1.5);
title(ax, 'warning-distance geometry overview');
xlabel(ax, 'x km-equivalent');
ylabel(ax, 'y km-equivalent');
axis(ax, 'equal');
grid(ax, 'on');
legend(ax, {'grid lines', 'road edges', 'H2 sites', 'lf7 centers', ...
    'closest distance'}, 'Location', 'bestoutside');
save_fig(fig, outFile);
end

function plot_wstep_centers(result, config, wstep, outFile)
fig = figure('Visible', 'off', 'Color', 'w');
ax = axes(fig);
hold(ax, 'on');
plot_segments(ax, result.grid_segments, [0.1 0.3 0.9], 1.0);
plot_segments(ax, result.road_segments, [0.65 0.65 0.65], 0.6);
colors = lines(numel(config.stageNames));
closestLoc = result.y_base_solution.closest_loc;
for ss = 1:numel(config.stageNames)
    y = result.y_base_solution.y_base + config.stageOffsets(ss) * wstep;
    scatter(ax, result.loc_table.x_coord, ...
        repmat(y, height(result.loc_table), 1), 24, colors(ss, :), ...
        'filled');
    locRow = result.loc_table(result.loc_table.loc == closestLoc, :);
    if ~isempty(locRow)
        draw_circle(ax, locRow.x_coord(1), y, 40, colors(ss, :));
    end
end
scatter(ax, result.site_table.x_km, result.site_table.y_km, 42, 's', ...
    'filled', 'MarkerFaceColor', [0.0 0.45 0.35]);
title(ax, sprintf('Wstep=%g, centers and Rmax=40 circles', wstep));
xlabel(ax, 'x km-equivalent');
ylabel(ax, 'y km-equivalent');
axis(ax, 'equal');
grid(ax, 'on');
legend(ax, [{'grid lines'}, {'road edges'}, config.stageNames(:).', ...
    {'H2 sites'}], 'Location', 'bestoutside');
save_fig(fig, outFile);
end

function plot_stage_metric(result, rmax, metricName, ttl, outFile)
fig = figure('Visible', 'off', 'Color', 'w');
ax = axes(fig);
hold(ax, 'on');
for ww = result.config.WstepValues(:).'
    rows = result.stage_summary(result.stage_summary.Rmax == rmax & ...
        result.stage_summary.Wstep == ww, :);
    rows = sortrows(rows, 'stage_index');
    plot(ax, rows.stage_index, rows.(metricName), '-o', ...
        'DisplayName', sprintf('Wstep=%g', ww), 'LineWidth', 1.2);
end
set(ax, 'XTick', 0:3, 'XTickLabel', result.config.stageNames);
ylabel(ax, metricName, 'Interpreter', 'none');
title(ax, ttl);
grid(ax, 'on');
legend(ax, 'Location', 'bestoutside');
save_fig(fig, outFile);
end

function plot_sensitivity(result, outFile)
fig = figure('Visible', 'off', 'Color', 'w');
ax = axes(fig);
hold(ax, 'on');
for rmax = result.config.RmaxValues(:).'
    rows = result.sensitivity_summary(result.sensitivity_summary.Rmax == rmax, :);
    rows = sortrows(rows, 'Wstep');
    plot(ax, rows.Wstep, rows.W2W3_max_combined_p95, '-o', ...
        'DisplayName', sprintf('Rmax=%g', rmax), 'LineWidth', 1.2);
end
xlabel(ax, 'Wstep');
ylabel(ax, 'W2/W3 max combined p95');
title(ax, 'Rmax sensitivity');
grid(ax, 'on');
legend(ax, 'Location', 'best');
save_fig(fig, outFile);
end

function plot_ranking(result, outFile)
fig = figure('Visible', 'off', 'Color', 'w');
ax = axes(fig);
rows = sortrows(result.candidate_ranking, 'rank');
bar(ax, categorical(string(rows.Wstep)), rows.overall_score);
xlabel(ax, 'Wstep');
ylabel(ax, 'overall score');
title(ax, 'Wstep candidate ranking');
grid(ax, 'on');
save_fig(fig, outFile);
end

function plot_segments(ax, seg, color, width)
for ii = 1:height(seg)
    plot(ax, [seg.x1(ii), seg.x2(ii)], [seg.y1(ii), seg.y2(ii)], ...
        '-', 'Color', color, 'LineWidth', width);
end
end

function draw_circle(ax, x, y, r, color)
theta = linspace(0, 2*pi, 100);
plot(ax, x + r*cos(theta), y + r*sin(theta), '--', ...
    'Color', color, 'LineWidth', 0.7);
end

function save_fig(fig, outFile)
set(fig, 'PaperPositionMode', 'auto');
print(fig, outFile, '-dpng', '-r160');
close(fig);
end
