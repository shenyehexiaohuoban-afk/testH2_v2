function write_foundation_fix_diagnostics_h2(result, foundation, config)
%WRITE_FOUNDATION_FIX_DIAGNOSTICS_H2 Write Foundation Fix outputs and plots.

writetable(build_parameter_snapshot(result, foundation, config), ...
    fullfile(config.outputDir, 'foundation_fix_parameter_snapshot.csv'));
writetable(foundation.stage_coordinates, fullfile(config.outputDir, ...
    'foundation_fix_stage_coordinates.csv'));
writetable(foundation.geometry_by_loc, fullfile(config.outputDir, ...
    'foundation_fix_geometry_by_loc.csv'));
writetable(result.risk, fullfile(config.outputDir, ...
    'foundation_fix_wind_risk_summary.csv'));
writetable(result.mc_by_slice, fullfile(config.outputDir, ...
    'foundation_fix_D_by_slice.csv'));
writetable(result.D_Hres3h_summary, fullfile(config.outputDir, ...
    'foundation_fix_D_Hres3h_summary.csv'));
writetable(result.comparison, fullfile(config.outputDir, ...
    'Wstep40_45_comparison.csv'));
writetable(result.reaudit_checks, fullfile(config.outputDir, ...
    'foundation_fix_reaudit_checks.csv'));

write_diagnostics_summary(result, foundation, config);
write_implementation_audit(result, foundation, config);
write_figures(result, foundation, config);
end

function T = build_parameter_snapshot(result, foundation, config)
key = ["warning_distance_km_eq"; "y_base"; "minimum_actual_distance"; ...
    "closest_loc"; "closest_object"; "closest_object_id"; ...
    "closest_point_x"; "closest_point_y"; "Rmax_values"; ...
    "Rmax_ref"; "Wstep_values"; "W"; "slice_duration_h"; ...
    "Hres_total_h"; "a_values"; "loc_values"; "smoke_a_values"; ...
    "smoke_loc_values"; "mc_count"; "mc_seed"; "eta_FC"; ...
    "LHV_H2_kWh_per_kg"; "P_node_load_total_kW"; ...
    "P_node_load_source"; "grid_distance_method"; ...
    "road_distance_method"; "Rmax_mode"; "old_ranking_hardcoded_40"];
value = [string(config.warningDistanceKmEq); string(foundation.y_base); ...
    string(foundation.recomputed_solution.minimum_actual_distance); ...
    string(foundation.recomputed_solution.closest_loc); ...
    foundation.recomputed_solution.closest_object_type; ...
    string(foundation.recomputed_solution.closest_object_id); ...
    string(foundation.recomputed_solution.closest_x); ...
    string(foundation.recomputed_solution.closest_y); ...
    strjoin(string(config.RmaxValues), '|'); string(config.RmaxRef); ...
    strjoin(string(config.WstepValues), '|'); string(config.W); ...
    string(config.sliceDurationH); string(config.HresTotalH); ...
    strjoin(string(config.aValues), '|'); ...
    strjoin(string(foundation.loc_table.loc.'), '|'); ...
    strjoin(string(config.smokeAValues), '|'); ...
    strjoin(string(config.smokeLocValues), '|'); string(config.mcCount); ...
    string(config.mcSeed); string(result.eta_FC); ...
    string(result.LHV_H2_kWh_per_kg); ...
    string(result.P_node_load_total_kw); result.load_source; ...
    config.distanceMethod; result.road_distance_mode; result.Rmax_mode; ...
    string(foundation.old_ranking_hardcoded_40)];
T = table(key, value);
end

function write_diagnostics_summary(result, foundation, config)
fid = fopen(fullfile(config.outputDir, 'diagnostics_summary.txt'), 'w');
if fid < 0
    error('write_foundation_fix_diagnostics_h2:OpenFailed', ...
        'Could not open diagnostics_summary.txt.');
end
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, 'TerminalLOH Foundation Fix and Hres3h re-audit\n\n');
fprintf(fid, 'Scope: independent Foundation Fix diagnostics only. No formal B3, path probability, WDRO, TerminalLOH, or MSP run.\n\n');
fprintf(fid, 'Geometry verification\n');
fprintf(fid, '- y_base from warning solution: %.12g\n', foundation.y_base);
fprintf(fid, '- independently recomputed y_base: %.12g\n', ...
    foundation.recomputed_solution.y_base);
fprintf(fid, '- minimum actual distance: %.12g (target %.12g)\n', ...
    foundation.recomputed_solution.minimum_actual_distance, ...
    config.warningDistanceKmEq);
fprintf(fid, '- closest loc/object: loc=%g, %s %g\n', ...
    foundation.recomputed_solution.closest_loc, ...
    foundation.recomputed_solution.closest_object_type, ...
    foundation.recomputed_solution.closest_object_id);
fprintf(fid, '- closest point: (%.12g, %.12g), center=(%.12g, %.12g)\n\n', ...
    foundation.recomputed_solution.closest_x, ...
    foundation.recomputed_solution.closest_y, ...
    foundation.recomputed_solution.center_x, foundation.y_base);

for wstep = config.WstepValues(:).'
    c = foundation.stage_coordinates( ...
        foundation.stage_coordinates.Wstep == wstep, :);
    c = sortrows(c, 'stage_index');
    fprintf(fid, 'Wstep=%g stage y coordinates [lf7,W1,W2,W3]: %s\n', ...
        wstep, strjoin(compose('%.12g', c.y_coord.'), ', '));
end

fprintf(fid, '\nHres3h conversion\n');
fprintf(fid, '- P_loss unit: kW\n');
fprintf(fid, '- D unit: kg-H2\n');
fprintf(fid, '- slice duration: %.12g h\n', config.sliceDurationH);
fprintf(fid, '- W: %d; total Hres: %.12g h\n', config.W, config.HresTotalH);
fprintf(fid, '- eta_FC: %.12g; LHV_H2: %.12g kWh/kg\n', ...
    result.eta_FC, result.LHV_H2_kWh_per_kg);
fprintf(fid, '- node load source: %s; total %.12g kW\n', ...
    result.load_source, result.P_node_load_total_kw);
fprintf(fid, '- lf7 is diagnostic only and is excluded from Hres3h.\n');
fprintf(fid, '- D_total identity max error: %.12g\n\n', ...
    max(result.D_Hres3h_summary.D_sum_identity_max_abs_error));

fprintf(fid, 'Rmax and Wstep handling\n');
fprintf(fid, '- Rmax support points: %s; no probabilities assigned.\n', ...
    strjoin(string(config.RmaxValues), ', '));
fprintf(fid, '- a controls Vmax only; old a-to-Rmax mapping is disabled.\n');
fprintf(fid, '- Rmax is fixed across lf7/W1/W2/W3 and is not resampled.\n');
fprintf(fid, '- MC count=%d, base seed=%d; Wstep 40/45 use common random numbers.\n\n', ...
    config.mcCount, config.mcSeed);

fprintf(fid, 'Wstep 40 versus 45\n');
fprintf(fid, '- status: %s\n', result.recommendation.status);
fprintf(fid, '- recommended Wstep: %.12g\n', ...
    result.recommendation.recommended_Wstep);
fprintf(fid, '- mean absolute D_total difference at Rmax=40: %.12g kg\n', ...
    result.recommendation.mean_abs_D_delta_kg);
fprintf(fid, '- relative D signal at Rmax=40: %.12g\n', ...
    result.recommendation.relative_D_signal);
fprintf(fid, '- mean absolute road closed-count difference: %.12g\n', ...
    result.recommendation.mean_abs_road_closed_delta);
fprintf(fid, '- reason: %s\n\n', result.recommendation.reason);

failed = result.reaudit_checks(~result.reaudit_checks.passed, :);
fprintf(fid, 'Re-audit pass checks: %d/%d passed.\n', ...
    sum(result.reaudit_checks.passed), height(result.reaudit_checks));
if isempty(failed)
    fprintf(fid, 'All configured Foundation Fix pass checks passed.\n');
else
    fprintf(fid, 'Failed checks: %s\n', ...
        strjoin(string(failed.check_name), ', '));
end
end

function write_implementation_audit(result, foundation, config)
fid = fopen(fullfile(config.outputDir, 'implementation_audit.md'), 'w');
if fid < 0
    error('write_foundation_fix_diagnostics_h2:AuditOpenFailed', ...
        'Could not open implementation_audit.md.');
end
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, '# Foundation Fix implementation audit\n\n');
fprintf(fid, '- Scope: Foundation coordinate/risk/Hres3h fix and re-audit only.\n');
fprintf(fid, '- Source functions reused: `build_h2_spatial_layout_preview`, `compute_wind_speed_radial_h2`, `compute_line_failure_prob_h2`, `compute_point_to_segment_distance_h2`, and `solve_warning_y_base_h2`.\n');
fprintf(fid, '- Source data: `%s`, `%s`, `%s`, `%s`.\n', ...
    config.nearInputFile, config.roadEdgeFile, config.siteNodeFile, ...
    config.locCoordinateFile);
fprintf(fid, '- y_base source was read from `%s` and independently recomputed.\n', ...
    config.warningSolutionFile);
fprintf(fid, '- Closest point verified: loc=%g, %s %g, point=(%.12g, %.12g).\n', ...
    foundation.recomputed_solution.closest_loc, ...
    foundation.recomputed_solution.closest_object_type, ...
    foundation.recomputed_solution.closest_object_id, ...
    foundation.recomputed_solution.closest_x, ...
    foundation.recomputed_solution.closest_y);
fprintf(fid, '- Grid and road distances use point-to-segment geometry.\n');
fprintf(fid, '- The fixed y coordinate enters distance, wind, line pFail, road pClose, line-failure MC, connectivity, P_loss, and D.\n');
fprintf(fid, '- `a` controls Vmax only. Rmax is directly fixed at 30/40/50 for sensitivity and has no assigned probability.\n');
fprintf(fid, '- The old a-to-Rmax table is not called. Rmax is not sampled or resampled across stages.\n');
fprintf(fid, '- Real node load source: `%s`; no IEEE33 fallback, mock, dummy, placeholder, or random demand is used.\n', result.load_source);
fprintf(fid, '- D conversion: `P_loss_kW * 1 h / (eta_FC * LHV_H2)` for W1/W2/W3; lf7 is excluded.\n');
fprintf(fid, '- eta_FC=%.12g, LHV_H2=%.12g kWh/kg, total node load=%.12g kW.\n', ...
    result.eta_FC, result.LHV_H2_kWh_per_kg, ...
    result.P_node_load_total_kw);
fprintf(fid, '- Smoke MC only: Nmc=%d, seed=%d, selected a=%s, loc=%s. This is not formal B3.\n', ...
    config.mcCount, config.mcSeed, strjoin(string(config.smokeAValues), '|'), ...
    strjoin(string(config.smokeLocValues), '|'));
fprintf(fid, '- Wstep 40 and 45 share common random numbers for comparable consequences.\n');
fprintf(fid, '- Old warning ranking hard-coded Wstep 40: %d. It used a score and ascending-Wstep tie break.\n', ...
    foundation.old_ranking_hardcoded_40);
fprintf(fid, '- Current 40/45 conclusion: `%s`; %s\n', ...
    result.recommendation.status, result.recommendation.reason);
fprintf(fid, '- Formal path probabilities computed: no.\n');
fprintf(fid, '- Formal D/A/C or B3 samples generated: no.\n');
fprintf(fid, '- WDRO/Gurobi/TerminalLOH run: no.\n');
fprintf(fid, '- MSP main model modified or run: no.\n');
fprintf(fid, '- Old B1/B2/Foundation outputs overwritten: no.\n');
end

function write_figures(result, foundation, config)
figDir = fullfile(config.outputDir, 'figures');
if ~isfolder(figDir)
    mkdir(figDir);
end
for wstep = config.WstepValues(:).'
    plot_spatial(foundation, config, wstep, fullfile(figDir, ...
        sprintf('foundation_fix_spatial_Wstep%d.png', wstep)));
end
plot_stage_risk(result.stage_risk, 'line_pFail_p95_across_cases', ...
    'Line pFail p95', fullfile(figDir, ...
    'foundation_fix_line_pFail_by_stage.png'));
plot_stage_risk(result.stage_risk, 'road_pClose_p95_across_cases', ...
    'Road pClose p95', fullfile(figDir, ...
    'foundation_fix_road_pClose_by_stage.png'));
plot_mc_stage(result.D_Hres3h_summary, 'P_loss', fullfile(figDir, ...
    'foundation_fix_P_loss_by_stage.png'));
plot_mc_stage(result.D_Hres3h_summary, 'D', fullfile(figDir, ...
    'foundation_fix_D_by_slice.png'));
plot_d_total_comparison(result.comparison, fullfile(figDir, ...
    'foundation_fix_Wstep40_45_D_total_comparison.png'));
plot_rmax_sensitivity(result.stage_risk, fullfile(figDir, ...
    'foundation_fix_Rmax_risk_sensitivity.png'));
end

function plot_spatial(foundation, config, wstep, outFile)
fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 1100 650]);
cleanup = onCleanup(@() close(fig));
ax = axes(fig); hold(ax, 'on'); grid(ax, 'on'); axis(ax, 'equal');
g = foundation.grid_segments;
r = foundation.road_segments;
for ii = 1:height(r)
    plot(ax, [r.x1(ii), r.x2(ii)], [r.y1(ii), r.y2(ii)], ...
        '-', 'Color', [0.8 0.8 0.8], 'LineWidth', 0.5, ...
        'HandleVisibility', 'off');
end
for ii = 1:height(g)
    plot(ax, [g.x1(ii), g.x2(ii)], [g.y1(ii), g.y2(ii)], ...
        '-', 'Color', [0.15 0.35 0.65], 'LineWidth', 1.1, ...
        'HandleVisibility', 'off');
end
loc3 = foundation.loc_table(foundation.loc_table.loc == 3, :);
colors = lines(4);
for ss = 1:4
    y = foundation.y_base + config.stageOffsets(ss) * wstep;
    scatter(ax, loc3.x_coord, y, 55, colors(ss, :), 'filled', ...
        'HandleVisibility', 'off');
    text(ax, loc3.x_coord + 1.5, y, char(config.stageNames(ss)), ...
        'Color', colors(ss, :));
end
theta = linspace(0, 2*pi, 240);
for rmax = config.RmaxValues(:).'
    y = foundation.y_base + config.stageOffsets(3) * wstep;
    plot(ax, loc3.x_coord + rmax*cos(theta), y + rmax*sin(theta), ...
        '--', 'LineWidth', 0.8, 'DisplayName', sprintf('Rmax=%g', rmax));
end
xlabel(ax, 'x (km-equivalent)'); ylabel(ax, 'y (km-equivalent)');
title(ax, sprintf('Foundation Fix spatial stages, loc=3, Wstep=%g', wstep));
legend(ax, 'Location', 'eastoutside');
exportgraphics(fig, outFile, 'Resolution', 180);
end

function plot_stage_risk(S, metric, yLabel, outFile)
fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 900 520]);
cleanup = onCleanup(@() close(fig));
ax = axes(fig); hold(ax, 'on'); grid(ax, 'on');
for rmax = unique(S.Rmax).'
    for wstep = unique(S.Wstep).'
        sub = S(S.Rmax == rmax & S.Wstep == wstep, :);
        sub = sortrows(sub, 'stage_index');
        plot(ax, sub.stage_index, sub.(metric), '-o', 'LineWidth', 1.2, ...
            'DisplayName', sprintf('Rmax=%g Wstep=%g', rmax, wstep));
    end
end
xticks(ax, 0:3); xticklabels(ax, {'lf7','W1','W2','W3'});
ylabel(ax, yLabel); title(ax, [yLabel ' by stage']);
legend(ax, 'Location', 'eastoutside');
exportgraphics(fig, outFile, 'Resolution', 180);
end

function plot_mc_stage(S, mode, outFile)
sub = S(S.Rmax == 40, :);
fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 900 520]);
cleanup = onCleanup(@() close(fig));
ax = axes(fig); hold(ax, 'on'); grid(ax, 'on');
for wstep = unique(sub.Wstep).'
    s = sub(sub.Wstep == wstep, :);
    if strcmp(mode, 'P_loss')
        vals = [mean(s.P_loss_W1_mean_kW), mean(s.P_loss_W2_mean_kW), ...
            mean(s.P_loss_W3_mean_kW)];
        label = 'Mean P loss (kW)';
    else
        vals = [mean(s.D_W1_mean_kg), mean(s.D_W2_mean_kg), ...
            mean(s.D_W3_mean_kg)];
        label = 'Mean D slice (kg-H2)';
    end
    plot(ax, 1:3, vals, '-o', 'LineWidth', 1.4, ...
        'DisplayName', sprintf('Wstep=%g', wstep));
end
xticks(ax, 1:3); xticklabels(ax, {'W1','W2','W3'});
ylabel(ax, label); title(ax, [label ' (Rmax=40 smoke MC)']);
legend(ax, 'Location', 'best');
exportgraphics(fig, outFile, 'Resolution', 180);
end

function plot_d_total_comparison(C, outFile)
sub = C(C.Rmax == 40, :);
fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 900 520]);
cleanup = onCleanup(@() close(fig));
ax = axes(fig); grid(ax, 'on'); hold(ax, 'on');
scatter(ax, sub.W40_D_total_mean_kg, sub.W45_D_total_mean_kg, ...
    55, sub.a, 'filled');
mx = max([sub.W40_D_total_mean_kg; sub.W45_D_total_mean_kg; 1]);
plot(ax, [0 mx], [0 mx], '--k');
xlabel(ax, 'Wstep 40 mean D total (kg-H2)');
ylabel(ax, 'Wstep 45 mean D total (kg-H2)');
title(ax, 'Wstep 40/45 Hres3h consequence comparison, Rmax=40');
colorbar(ax);
exportgraphics(fig, outFile, 'Resolution', 180);
end

function plot_rmax_sensitivity(S, outFile)
fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 900 520]);
cleanup = onCleanup(@() close(fig));
ax = axes(fig); hold(ax, 'on'); grid(ax, 'on');
for wstep = unique(S.Wstep).'
    vals = zeros(3, 1);
    rvals = unique(S.Rmax);
    for ii = 1:numel(rvals)
        sub = S(S.Wstep == wstep & S.Rmax == rvals(ii) & ...
            S.stage_index >= 1, :);
        vals(ii) = max(max(sub.line_pFail_p95_across_cases, ...
            sub.road_pClose_p95_across_cases));
    end
    plot(ax, rvals, vals, '-o', 'LineWidth', 1.4, ...
        'DisplayName', sprintf('Wstep=%g', wstep));
end
xlabel(ax, 'Rmax (km-equivalent)'); ylabel(ax, 'Peak p95 risk');
title(ax, 'Rmax sensitivity across W1/W2/W3');
legend(ax, 'Location', 'best');
exportgraphics(fig, outFile, 'Resolution', 180);
end
