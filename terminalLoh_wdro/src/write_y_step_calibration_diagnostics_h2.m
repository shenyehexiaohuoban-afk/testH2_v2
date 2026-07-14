function write_y_step_calibration_diagnostics_h2(result, config)
%WRITE_Y_STEP_CALIBRATION_DIAGNOSTICS_H2 Write y-step calibration outputs.

if ~exist(config.outputDir, 'dir')
    mkdir(config.outputDir);
end

writetable(result.candidate_diagnostics, fullfile(config.outputDir, ...
    'y_step_candidate_diagnostics.csv'));
writetable(result.by_intensity, fullfile(config.outputDir, ...
    'y_step_by_intensity_summary.csv'));
writetable(result.by_loc, fullfile(config.outputDir, ...
    'y_step_by_loc_summary.csv'));
writetable(result.wind_road_decay, fullfile(config.outputDir, ...
    'wind_road_decay_by_tau_summary.csv'));

write_recommendation(result, config);
write_implementation_audit(result, config);
end

function write_recommendation(result, config)
fileName = fullfile(config.outputDir, 'y_step_recommendation.txt');
fid = fopen(fileName, 'w');
if fid < 0
    error('write_y_step_calibration_diagnostics_h2:OpenFailed', ...
        'Could not open %s.', fileName);
end
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, 'Stage2-Foundation-yStep-Calibration recommendation\n\n');
fprintf(fid, 'Status: %s\n', result.status);
fprintf(fid, 'x_loc_step: %.12g\n', result.x_loc_step);
fprintf(fid, 'y_base: %.12g\n', result.y_base);
fprintf(fid, 'system_y_min: %.12g\n', result.system_y_min);
fprintf(fid, 'system_y_max: %.12g\n', result.system_y_max);
fprintf(fid, 'system_y_median: %.12g\n', result.system_y_median);
fprintf(fid, 'candidate_y_step_over_x_step: %s\n', ...
    strtrim(sprintf('%.12g ', result.candidate_multipliers)));
fprintf(fid, 'candidate_y_step: %s\n\n', ...
    strtrim(sprintf('%.12g ', result.candidate_y_step)));

fprintf(fid, 'Direction check:\n');
fprintf(fid, '- y positive direction moves away from system: %d\n', ...
    ~result.y_positive_moves_toward_system);
fprintf(fid, '- %s\n\n', result.direction_note);

if strcmp(result.status, 'blocked_positive_y_moves_toward_system')
    fprintf(fid, 'Recommended y_step: NaN (blocked)\n');
    fprintf(fid, 'Recommendation reason: positive y is not a valid away-from-system direction under the current coordinate system.\n');
    fprintf(fid, 'W1/W2/W3 line_pFail_p95: not evaluated because the required direction sanity check failed.\n');
    fprintf(fid, 'W1/W2/W3 road_pClose_p95: not evaluated because the required direction sanity check failed.\n');
    fprintf(fid, 'W3 basically no longer affects system: not assessed.\n');
    fprintf(fid, 'Human confirmation required: yes. Confirm whether y negative is the intended away-from-system direction, or redefine the coordinate frame.\n');
    fprintf(fid, 'Suggest Foundation Fix: yes, but first fix the y direction convention before applying a y_step.\n');
    return;
end

fprintf(fid, 'Recommended y_step: %.12g\n', result.recommended_y_step);
fprintf(fid, 'Recommended y_step_over_x_step: %.12g\n', ...
    result.recommended_multiplier);

if isnan(result.recommended_y_step)
    fprintf(fid, 'Recommendation reason: no tested candidate satisfied the W3 decay rule.\n');
    fprintf(fid, 'Suggested next candidates: [5, 6, 8] * x_loc_step.\n');
else
    fprintf(fid, 'Recommendation reason: smallest candidate satisfying W3 line and road decay rules.\n');
end

fprintf(fid, '\nCandidate tau p95 summary:\n');
for cc = 1:numel(result.candidate_y_step)
    yStep = result.candidate_y_step(cc);
    rows = result.candidate_diagnostics( ...
        abs(result.candidate_diagnostics.candidate_y_step - yStep) <= 1e-9, :);
    rows = sortrows(rows, 'tau');
    fprintf(fid, '- y_step=%.12g: line_pFail_p95=[%s], road_pClose_p95=[%s]\n', ...
        yStep, strtrim(sprintf('%.12g ', rows.line_pFail_p95)), ...
        strtrim(sprintf('%.12g ', rows.road_pClose_p95)));
end

fprintf(fid, '\nW3 basically no longer affects system: see meets_W3_decay_rule in y_step_candidate_diagnostics.csv.\n');
fprintf(fid, 'Human confirmation required: yes.\n');
fprintf(fid, 'Suggest Foundation Fix: yes, if the recommended y_step and direction convention are accepted.\n');
end

function write_implementation_audit(result, config)
fileName = fullfile(config.outputDir, ...
    'implementation_audit_yStep_calibration.txt');
fid = fopen(fileName, 'w');
if fid < 0
    error('write_y_step_calibration_diagnostics_h2:AuditOpenFailed', ...
        'Could not open %s.', fileName);
end
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, 'Stage2-Foundation-yStep-Calibration implementation audit\n\n');
fprintf(fid, 'This run only performs y_step calibration diagnostics.\n');
fprintf(fid, 'Generated new D/A/C samples: no.\n');
fprintf(fid, 'Ran WDRO: no.\n');
fprintf(fid, 'Called Gurobi: no.\n');
fprintf(fid, 'Modified MSP main model: no.\n');
fprintf(fid, 'Overwrote B1/B2 outputs: no.\n');
fprintf(fid, 'Output directory: %s\n\n', config.outputDir);

fprintf(fid, 'Source functions used:\n');
fprintf(fid, '- build_h2_spatial_layout_preview.m\n');
fprintf(fid, '- compute_wind_speed_radial_h2.m\n');
fprintf(fid, '- compute_line_failure_prob_h2.m\n');
fprintf(fid, '- B2 road coordinate logic reproduced from load_stage1_road_data_b1 in build_lookahead_W3_DAC_samples_h2.m\n\n');

fprintf(fid, 'Data files used:\n');
fprintf(fid, '- %s\n', config.locCoordinateFile);
fprintf(fid, '- %s\n', config.pathTableFile);
fprintf(fid, '- %s\n', config.nearInputFile);
fprintf(fid, '- %s\n', config.roadEdgeFile);
fprintf(fid, '- %s\n\n', config.siteNodeFile);

fprintf(fid, 'Coordinate facts:\n');
fprintf(fid, '- x_loc_step = %.12g\n', result.x_loc_step);
fprintf(fid, '- y_base = %.12g\n', result.y_base);
fprintf(fid, '- system_y_range = [%.12g, %.12g]\n', ...
    result.system_y_min, result.system_y_max);
fprintf(fid, '- line_count = %d\n', result.line_count);
fprintf(fid, '- road_edge_count = %d\n\n', result.road_edge_count);

fprintf(fid, 'Positive y direction matches away-from-system interpretation: %d\n', ...
    ~result.y_positive_moves_toward_system);
fprintf(fid, 'Direction note: %s\n', result.direction_note);
fprintf(fid, 'Coordinate scale abnormality found: %d\n', ...
    result.y_positive_moves_toward_system);
if result.y_positive_moves_toward_system
    fprintf(fid, 'Scale/direction issue: y_base is below the system y range, so positive y moves toward the system.\n');
end
fprintf(fid, 'Recommended y_step: %.12g\n', result.recommended_y_step);
fprintf(fid, 'Recommend entering Foundation Fix: %d\n', true);
if result.y_positive_moves_toward_system
    fprintf(fid, 'Foundation Fix should first resolve the sign convention for y progression before changing Stage2A/B code.\n');
else
    fprintf(fid, 'Foundation Fix may apply the recommended y_step after human confirmation.\n');
end
end
