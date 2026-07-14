function result = evaluate_warning_Rmax_Wstep_candidate_h2(config)
%EVALUATE_WARNING_RMAX_WSTEP_CANDIDATE_H2 Full warning/Rmax/Wstep sweep.

validate_config(config);

locTbl = readtable(config.locCoordinateFile);
locTbl = sortrows(locTbl(:, {'loc', 'x_coord', 'y_coord'}), 'loc');

raw = load(config.nearInputFile, 'NearStageInput');
if ~isfield(raw, 'NearStageInput')
    error('evaluate_warning_Rmax_Wstep_candidate_h2:MissingNearStageInput', ...
        'Missing NearStageInput in %s.', config.nearInputFile);
end
layout = build_h2_spatial_layout_preview(raw.NearStageInput);
[gridSeg, roadSeg, siteTbl] = build_warning_geometry(config, layout);

ySolution = solve_warning_y_base_h2(locTbl, gridSeg, roadSeg, ...
    config.warningDistanceKmEq);

fullRiskTbl = build_full_risk_table(config, locTbl, gridSeg, roadSeg, ...
    ySolution.y_base);
fullRiskTbl = add_lf7_change_and_peak_stage(fullRiskTbl);
geometryTbl = build_geometry_table(config, locTbl, gridSeg, roadSeg, ...
    ySolution.y_base);
stageSummaryTbl = build_stage_summary(fullRiskTbl);
sensitivityTbl = build_sensitivity_summary(stageSummaryTbl);
indicatorTbl = build_candidate_indicators(fullRiskTbl, stageSummaryTbl, ...
    config);
[indicatorTbl, rankingTbl] = rank_Wstep_candidates_h2(indicatorTbl, config);

result = struct();
result.config = config;
result.loc_table = locTbl;
result.layout = layout;
result.grid_segments = gridSeg;
result.road_segments = roadSeg;
result.site_table = siteTbl;
result.y_base_solution = ySolution;
result.geometry_by_loc = geometryTbl;
result.full_risk = fullRiskTbl;
result.stage_summary = stageSummaryTbl;
result.candidate_indicators = indicatorTbl;
result.candidate_ranking = rankingTbl;
result.sensitivity_summary = sensitivityTbl;
result.anomalies = detect_warning_sweep_anomalies(fullRiskTbl, ...
    stageSummaryTbl, indicatorTbl, config);
end

function validate_config(config)
files = {config.locCoordinateFile, config.nearInputFile, ...
    config.roadEdgeFile, config.siteNodeFile};
for ii = 1:numel(files)
    if ~isfile(files{ii})
        error('evaluate_warning_Rmax_Wstep_candidate_h2:MissingInput', ...
            'Missing required input file: %s', files{ii});
    end
end
if config.warningDistanceKmEq <= 0 || any(config.RmaxValues <= 0) || ...
        any(config.WstepValues <= 0)
    error('evaluate_warning_Rmax_Wstep_candidate_h2:BadConfig', ...
        'warningDistanceKmEq, RmaxValues, and WstepValues must be positive.');
end
end

function [gridSeg, roadSeg, siteTbl] = build_warning_geometry(config, layout)
nodes = sortrows(layout.nodes, 'node_id');
lineRows = layout.lines;
lineRows = sortrows(lineRows, 'line_id');
gridSeg = table(lineRows.line_id, lineRows.from_node, lineRows.to_node, ...
    nodes.x_km(lineRows.from_node), nodes.y_km(lineRows.from_node), ...
    nodes.x_km(lineRows.to_node), nodes.y_km(lineRows.to_node), ...
    'VariableNames', {'line_id', 'from_node', 'to_node', ...
    'x1', 'y1', 'x2', 'y2'});

roadRaw = readtable(config.roadEdgeFile);
siteRaw = readtable(config.siteNodeFile);
require_vars_warning(roadRaw, {'road_edge_id', 'from_node', 'to_node'}, ...
    'stage1_road_edges.csv');
require_vars_warning(siteRaw, {'site_id', 'grid_node'}, ...
    'stage1_site_nodes.csv');
roadSeg = table(double(roadRaw.road_edge_id), double(roadRaw.from_node), ...
    double(roadRaw.to_node), ...
    nodes.x_km(double(roadRaw.from_node)), ...
    nodes.y_km(double(roadRaw.from_node)), ...
    nodes.x_km(double(roadRaw.to_node)), ...
    nodes.y_km(double(roadRaw.to_node)), ...
    'VariableNames', {'road_edge_id', 'from_node', 'to_node', ...
    'x1', 'y1', 'x2', 'y2'});
siteTbl = sortrows(layout.sites, 'site_id');
end

function require_vars_warning(tbl, names, fileName)
for ii = 1:numel(names)
    if ~ismember(names{ii}, tbl.Properties.VariableNames)
        error('evaluate_warning_Rmax_Wstep_candidate_h2:MissingColumn', ...
            '%s is missing column %s.', fileName, names{ii});
    end
end
end

function T = build_full_risk_table(config, locTbl, gridSeg, roadSeg, yBase)
stages = config.stageNames(:);
stageOffsets = config.stageOffsets(:);
rows = cell(numel(config.RmaxValues) * numel(config.WstepValues) * ...
    numel(stages) * numel(config.aValues) * height(locTbl), 43);
rr = 0;
for rmax = config.RmaxValues(:).'
    for wstep = config.WstepValues(:).'
        for ss = 1:numel(stages)
            stage = stages{ss};
            stageIndex = ss - 1;
            y = yBase + stageOffsets(ss) * wstep;
            for aa = config.aValues(:).'
                Vmax = intensity_to_vmax_warning(aa);
                for ll = 1:height(locTbl)
                    loc = double(locTbl.loc(ll));
                    x = double(locTbl.x_coord(ll));
                    [lineDist, ~, ~, ~] = compute_point_to_segment_distance_h2( ...
                        x, y, gridSeg.x1, gridSeg.y1, gridSeg.x2, gridSeg.y2);
                    [roadDist, ~, ~, ~] = compute_point_to_segment_distance_h2( ...
                        x, y, roadSeg.x1, roadSeg.y1, roadSeg.x2, roadSeg.y2);
                    [dGrid, closestLinePos] = min(lineDist);
                    [dRoad, closestRoadPos] = min(roadDist);
                    dSystem = min(dGrid, dRoad);
                    lineWind = compute_wind_speed_radial_h2(lineDist, Vmax, ...
                        rmax, config.windDecayB);
                    roadWind = compute_wind_speed_radial_h2(roadDist, Vmax, ...
                        rmax, config.windDecayB);
                    lineP = compute_line_failure_prob_h2(lineWind, ...
                        config.designWindSpeedVN);
                    roadP = compute_line_failure_prob_h2(roadWind, ...
                        config.roadDesignWindVN);
                    allDist = [lineDist(:); roadDist(:)];
                    ringIntersects = min(allDist) <= rmax && max(allDist) >= rmax;
                    rmaxPosition = classify_rmax_position(dSystem, rmax);
                    rr = rr + 1;
                    rows(rr, :) = {rmax, wstep, stage, stageIndex, aa, ...
                        loc, x, y, Vmax, dGrid, dRoad, dSystem, ...
                        gridSeg.line_id(closestLinePos), ...
                        roadSeg.road_edge_id(closestRoadPos), ...
                        mean(lineWind), pct_warning(lineWind, 50), ...
                        pct_warning(lineWind, 95), max(lineWind), ...
                        mean(roadWind), pct_warning(roadWind, 50), ...
                        pct_warning(roadWind, 95), max(roadWind), ...
                        mean(lineP), pct_warning(lineP, 50), ...
                        pct_warning(lineP, 95), max(lineP), ...
                        mean(roadP), pct_warning(roadP, 50), ...
                        pct_warning(roadP, 95), max(roadP), ...
                        NaN, NaN, NaN, NaN, NaN, NaN, ...
                        "", "", ringIntersects, rmaxPosition, ...
                        min(allDist), max(allDist), "segment_distance"}; %#ok<AGROW>
                end
            end
        end
    end
end

T = cell2table(rows(1:rr, :), 'VariableNames', ...
    {'Rmax', 'Wstep', 'stage', 'stage_index', 'a', 'loc', ...
    'typhoon_center_x', 'typhoon_center_y', 'Vmax_mps', ...
    'd_grid_min', 'd_road_min', 'd_system_min', ...
    'closest_line_id', 'closest_road_edge_id', ...
    'line_wind_mean', 'line_wind_p50', 'line_wind_p95', ...
    'line_wind_max', 'road_wind_mean', 'road_wind_p50', ...
    'road_wind_p95', 'road_wind_max', 'line_pFail_mean', ...
    'line_pFail_p50', 'line_pFail_p95', 'line_pFail_max', ...
    'road_pClose_mean', 'road_pClose_p50', 'road_pClose_p95', ...
    'road_pClose_max', 'line_pFail_p95_abs_change_vs_lf7', ...
    'line_pFail_p95_rel_change_vs_lf7', ...
    'road_pClose_p95_abs_change_vs_lf7', ...
    'road_pClose_p95_rel_change_vs_lf7', ...
    'combined_p95_abs_change_vs_lf7', ...
    'combined_p95_rel_change_vs_lf7', ...
    'line_peak_stage_for_a_loc', 'road_peak_stage_for_a_loc', ...
    'rmax_ring_intersects_system_objects', ...
    'system_position_relative_to_Rmax', ...
    'distance_min_all_objects', 'distance_max_all_objects', ...
    'distance_method'});
T.combined_p95 = max(T.line_pFail_p95, T.road_pClose_p95);
T.combined_max = max(T.line_pFail_max, T.road_pClose_max);
end

function T = add_lf7_change_and_peak_stage(T)
for ii = 1:height(T)
    mask = T.Rmax == T.Rmax(ii) & T.Wstep == T.Wstep(ii) & ...
        T.a == T.a(ii) & T.loc == T.loc(ii) & ...
        strcmp(T.stage, 'lf7');
    base = T(mask, :);
    if height(base) ~= 1
        error('evaluate_warning_Rmax_Wstep_candidate_h2:BadLf7Base', ...
            'Expected one lf7 baseline row.');
    end
    T.line_pFail_p95_abs_change_vs_lf7(ii) = ...
        T.line_pFail_p95(ii) - base.line_pFail_p95;
    T.road_pClose_p95_abs_change_vs_lf7(ii) = ...
        T.road_pClose_p95(ii) - base.road_pClose_p95;
    T.combined_p95_abs_change_vs_lf7(ii) = ...
        T.combined_p95(ii) - base.combined_p95;
    T.line_pFail_p95_rel_change_vs_lf7(ii) = ...
        rel_change_warning(T.line_pFail_p95(ii), base.line_pFail_p95);
    T.road_pClose_p95_rel_change_vs_lf7(ii) = ...
        rel_change_warning(T.road_pClose_p95(ii), base.road_pClose_p95);
    T.combined_p95_rel_change_vs_lf7(ii) = ...
        rel_change_warning(T.combined_p95(ii), base.combined_p95);
end

groups = unique(T(:, {'Rmax', 'Wstep', 'a', 'loc'}), 'rows');
for gg = 1:height(groups)
    mask = T.Rmax == groups.Rmax(gg) & T.Wstep == groups.Wstep(gg) & ...
        T.a == groups.a(gg) & T.loc == groups.loc(gg);
    rows = find(mask);
    [~, iLine] = max(T.line_pFail_p95(rows));
    [~, iRoad] = max(T.road_pClose_p95(rows));
    lineStage = T.stage{rows(iLine)};
    roadStage = T.stage{rows(iRoad)};
    T.line_peak_stage_for_a_loc(rows) = repmat(string(lineStage), numel(rows), 1);
    T.road_peak_stage_for_a_loc(rows) = repmat(string(roadStage), numel(rows), 1);
end
end

function geometryTbl = build_geometry_table(config, locTbl, gridSeg, roadSeg, yBase)
rows = {};
for wstep = config.WstepValues(:).'
    for ss = 1:numel(config.stageNames)
        stage = config.stageNames{ss};
        y = yBase + config.stageOffsets(ss) * wstep;
        for ll = 1:height(locTbl)
            x = double(locTbl.x_coord(ll));
            [lineDist, ~, ~, ~] = compute_point_to_segment_distance_h2( ...
                x, y, gridSeg.x1, gridSeg.y1, gridSeg.x2, gridSeg.y2);
            [roadDist, ~, ~, ~] = compute_point_to_segment_distance_h2( ...
                x, y, roadSeg.x1, roadSeg.y1, roadSeg.x2, roadSeg.y2);
            rows(end + 1, :) = {wstep, stage, ss - 1, double(locTbl.loc(ll)), ...
                x, y, min(lineDist), min(roadDist), ...
                min(min(lineDist), min(roadDist))}; %#ok<AGROW>
        end
    end
end
geometryTbl = cell2table(rows, 'VariableNames', ...
    {'Wstep', 'stage', 'stage_index', 'loc', 'x', 'y', ...
    'd_grid', 'd_road', 'd_system'});
end

function S = build_stage_summary(T)
groups = unique(T(:, {'Rmax', 'Wstep', 'stage', 'stage_index'}), 'rows');
groups = sortrows(groups, {'Rmax', 'Wstep', 'stage_index'});
rows = {};
metricNames = {'line_wind_p95', 'line_wind_max', 'road_wind_p95', ...
    'road_wind_max', 'line_pFail_p95', 'line_pFail_max', ...
    'road_pClose_p95', 'road_pClose_max', 'combined_p95', 'combined_max'};
for gg = 1:height(groups)
    mask = T.Rmax == groups.Rmax(gg) & T.Wstep == groups.Wstep(gg) & ...
        strcmp(T.stage, groups.stage{gg});
    sub = T(mask, :);
    row = {groups.Rmax(gg), groups.Wstep(gg), groups.stage{gg}, ...
        groups.stage_index(gg), height(sub)};
    for mm = 1:numel(metricNames)
        x = sub.(metricNames{mm});
        row = [row, {mean(x), pct_warning(x, 50), pct_warning(x, 95), max(x)}]; %#ok<AGROW>
    end
    [~, imax] = max(sub.combined_p95);
    row = [row, {sub.a(imax), sub.loc(imax), sub.combined_p95(imax)}]; %#ok<AGROW>
    rows(end + 1, :) = row; %#ok<AGROW>
end
names = {'Rmax', 'Wstep', 'stage', 'stage_index', 'case_count'};
for mm = 1:numel(metricNames)
    names = [names, strcat(metricNames{mm}, {'_mean', '_p50', '_p95', '_max'})]; %#ok<AGROW>
end
names = [names, {'max_risk_a', 'max_risk_loc', 'max_risk_combined_p95'}];
S = cell2table(rows, 'VariableNames', names);
end

function sensitivityTbl = build_sensitivity_summary(stageSummaryTbl)
wsteps = unique(stageSummaryTbl.Wstep);
rows = {};
for ww = 1:numel(wsteps)
    wstep = wsteps(ww);
    for rmax = unique(stageSummaryTbl.Rmax).'
        sub = stageSummaryTbl(stageSummaryTbl.Wstep == wstep & ...
            stageSummaryTbl.Rmax == rmax, :);
        sub = sortrows(sub, 'stage_index');
        risk = sub.combined_p95_p95;
        [peakRisk, idx] = max(risk);
        rows(end + 1, :) = {wstep, rmax, sub.stage{idx}, peakRisk, ...
            risk(1), risk(2), risk(3), risk(4), ...
            max(risk(3:4)), peakRisk / max(risk(1), eps)}; %#ok<AGROW>
    end
end
sensitivityTbl = cell2table(rows, 'VariableNames', ...
    {'Wstep', 'Rmax', 'peak_stage', 'peak_combined_p95', ...
    'lf7_combined_p95', 'W1_combined_p95', 'W2_combined_p95', ...
    'W3_combined_p95', 'W2W3_max_combined_p95', ...
    'peak_to_lf7_ratio'});
end

function indicators = build_candidate_indicators(T, stageSummaryTbl, config)
wsteps = config.WstepValues(:);
rows = {};
for ii = 1:numel(wsteps)
    wstep = wsteps(ii);
    s40 = select_stage_vector(stageSummaryTbl, 40, wstep);
    s30 = select_stage_vector(stageSummaryTbl, 30, wstep);
    s50 = select_stage_vector(stageSummaryTbl, 50, wstep);
    lineGain = s40.line_pFail_p95(2) - s40.line_pFail_p95(1);
    roadGain = s40.road_pClose_p95(2) - s40.road_pClose_p95(1);
    combined = max(s40.line_pFail_p95, s40.road_pClose_p95);
    [~, peakIdx] = max(combined(2:4));
    peakIdx = peakIdx + 1;
    mainStage = config.stageNames{peakIdx};
    stageSep = (max(combined) - min(combined)) / max(max(combined), eps);
    mask40W = T.Rmax == 40 & T.Wstep == wstep & T.stage_index >= 1;
    geometryCoverage = mean(T.rmax_ring_intersects_system_objects(mask40W) | ...
        strcmp(T.system_position_relative_to_Rmax(mask40W), 'inside_Rmax') | ...
        strcmp(T.system_position_relative_to_Rmax(mask40W), 'near_Rmax'));
    r30 = robustness_score_warning(s30);
    r50 = robustness_score_warning(s50);
    mainScore = main_score_warning(s40, geometryCoverage);
    [maxRisk, maxRow] = max(T.combined_p95(T.Rmax == 40 & T.Wstep == wstep));
    sub40 = T(T.Rmax == 40 & T.Wstep == wstep, :);
    rows(end + 1, :) = {wstep, lineGain, roadGain, mainStage, ...
        stageSep, geometryCoverage, r30, mainScore, r50, NaN, ...
        sub40.a(maxRow), sub40.loc(maxRow), sub40.stage{maxRow}, ...
        maxRisk, s40.line_pFail_p95(1), s40.line_pFail_p95(2), ...
        s40.line_pFail_p95(3), s40.line_pFail_p95(4), ...
        s40.line_pFail_max(1), s40.line_pFail_max(2), ...
        s40.line_pFail_max(3), s40.line_pFail_max(4), ...
        s40.road_pClose_p95(1), s40.road_pClose_p95(2), ...
        s40.road_pClose_p95(3), s40.road_pClose_p95(4), ...
        s40.road_pClose_max(1), s40.road_pClose_max(2), ...
        s40.road_pClose_max(3), s40.road_pClose_max(4)}; %#ok<AGROW>
end
indicators = cell2table(rows, 'VariableNames', ...
    {'Wstep', 'lf7_to_W1_line_gain', 'lf7_to_W1_road_gain', ...
    'main_impact_stage', 'stage_separation', 'geometry_coverage', ...
    'Rmax30_robustness', 'Rmax40_main_score', 'Rmax50_robustness', ...
    'overall_rank', 'Rmax40_max_risk_a', 'Rmax40_max_risk_loc', ...
    'Rmax40_max_risk_stage', 'Rmax40_max_combined_p95', ...
    'Rmax40_lf7_line_pFail_p95', 'Rmax40_W1_line_pFail_p95', ...
    'Rmax40_W2_line_pFail_p95', 'Rmax40_W3_line_pFail_p95', ...
    'Rmax40_lf7_line_pFail_max', 'Rmax40_W1_line_pFail_max', ...
    'Rmax40_W2_line_pFail_max', 'Rmax40_W3_line_pFail_max', ...
    'Rmax40_lf7_road_pClose_p95', 'Rmax40_W1_road_pClose_p95', ...
    'Rmax40_W2_road_pClose_p95', 'Rmax40_W3_road_pClose_p95', ...
    'Rmax40_lf7_road_pClose_max', 'Rmax40_W1_road_pClose_max', ...
    'Rmax40_W2_road_pClose_max', 'Rmax40_W3_road_pClose_max'});
end

function s = select_stage_vector(stageSummaryTbl, rmax, wstep)
sub = stageSummaryTbl(stageSummaryTbl.Rmax == rmax & ...
    stageSummaryTbl.Wstep == wstep, :);
sub = sortrows(sub, 'stage_index');
if height(sub) ~= 4
    error('evaluate_warning_Rmax_Wstep_candidate_h2:MissingStageSummary', ...
        'Missing stage summary rows for Rmax=%g Wstep=%g.', rmax, wstep);
end
s = struct();
s.line_pFail_p95 = sub.line_pFail_p95_p95(:).';
s.line_pFail_max = sub.line_pFail_max_max(:).';
s.road_pClose_p95 = sub.road_pClose_p95_p95(:).';
s.road_pClose_max = sub.road_pClose_max_max(:).';
end

function score = main_score_warning(s, geometryCoverage)
combined = max(s.line_pFail_p95, s.road_pClose_p95);
lf7 = combined(1);
w = combined(2:4);
score = 0;
if max(w) > lf7 * 1.1 + 1e-6
    score = score + 1;
end
if combined(2) > lf7 + 1e-6
    score = score + 1;
end
if max(combined(3:4)) >= max(0.01, lf7 * 1.5)
    score = score + 1;
end
if geometryCoverage > 0.15
    score = score + 1;
end
if max(combined) - min(combined) > 0.05 * max(combined)
    score = score + 1;
end
if max(combined(3:4)) >= 0.5 * max(w)
    score = score + 1;
end
end

function score = robustness_score_warning(s)
combined = max(s.line_pFail_p95, s.road_pClose_p95);
lf7 = combined(1);
score = 0;
if max(combined(3:4)) > lf7 * 1.1 + 1e-6
    score = score + 1;
end
if max(combined(3:4)) >= 0.01
    score = score + 1;
end
if (max(combined) - min(combined)) / max(max(combined), eps) > 0.1
    score = score + 1;
end
if lf7 < 0.8
    score = score + 1;
end
end

function anomalies = detect_warning_sweep_anomalies(T, stageSummaryTbl, indicators, config)
anomalies = struct();
anomalies.distance_decreases_but_wind_decreases = false;
groups = unique(T(:, {'Rmax', 'Wstep', 'a', 'loc'}), 'rows');
for gg = 1:height(groups)
    sub = T(T.Rmax == groups.Rmax(gg) & T.Wstep == groups.Wstep(gg) & ...
        T.a == groups.a(gg) & T.loc == groups.loc(gg), :);
    sub = sortrows(sub, 'stage_index');
    for ii = 2:height(sub)
        if sub.d_system_min(ii) < sub.d_system_min(ii - 1) && ...
                sub.line_wind_max(ii) < sub.line_wind_max(ii - 1)
            anomalies.distance_decreases_but_wind_decreases = true;
        end
    end
end
anomalies.p95_zero_but_max_high = any( ...
    (T.line_pFail_p95 <= 1e-12 & T.line_pFail_max > 0.1) | ...
    (T.road_pClose_p95 <= 1e-12 & T.road_pClose_max > 0.1));
anomalies.risk_extreme_case_dominated = any( ...
    stageSummaryTbl.combined_p95_max > ...
    10 * max(stageSummaryTbl.combined_p95_p95, eps));
meanByW = zeros(numel(config.WstepValues), 1);
for ii = 1:numel(config.WstepValues)
    rows = stageSummaryTbl.Rmax == 40 & ...
        stageSummaryTbl.Wstep == config.WstepValues(ii);
    meanByW(ii) = mean(stageSummaryTbl.combined_p95_p95(rows));
end
anomalies.all_Wstep_risks_nearly_same = ...
    (max(meanByW) - min(meanByW)) <= 0.05 * max(max(meanByW), eps);
anomalies.road_pClose_always_zero = all(T.road_pClose_max <= 0);
lf7Rows = stageSummaryTbl.Rmax == 40 & strcmp(stageSummaryTbl.stage, 'lf7');
anomalies.line_risk_lf7_saturated = any(stageSummaryTbl.line_pFail_p95_p95(lf7Rows) > 0.8);
row50 = indicators(indicators.Wstep == 50, :);
anomalies.Wstep50_skips_main_band = false;
if ~isempty(row50)
    w = [row50.Rmax40_W1_line_pFail_p95, row50.Rmax40_W2_line_pFail_p95, ...
        row50.Rmax40_W3_line_pFail_p95, row50.Rmax40_W1_road_pClose_p95, ...
        row50.Rmax40_W2_road_pClose_p95, row50.Rmax40_W3_road_pClose_p95];
    anomalies.Wstep50_skips_main_band = max(w(3:3:end)) < 0.5 * max(w);
end
row30 = indicators(indicators.Wstep == 30, :);
anomalies.Wstep30_W3_not_main_impact = false;
if ~isempty(row30)
    anomalies.Wstep30_W3_not_main_impact = ...
        max(row30.Rmax40_W3_line_pFail_p95, row30.Rmax40_W3_road_pClose_p95) < ...
        max(0.01, 1.2 * max(row30.Rmax40_lf7_line_pFail_p95, ...
        row30.Rmax40_lf7_road_pClose_p95));
end
anomalies.coordinate_scale_issue = false;
anomalies.road_distance_segment_not_midpoint = true;
anomalies.old_a_to_Rmax_table_called = false;
anomalies.Rmax_randomized_across_stage = false;
end

function Vmax = intensity_to_vmax_warning(a)
V = [0; 20.8; 28.55; 37.05; 46.20; 55.50];
if a < 1 || a > numel(V)
    error('evaluate_warning_Rmax_Wstep_candidate_h2:BadIntensity', ...
        'Unsupported intensity a=%g.', a);
end
Vmax = V(a);
end

function label = classify_rmax_position(dSystem, rmax)
if dSystem < 0.9 * rmax
    label = "inside_Rmax";
elseif dSystem <= 1.1 * rmax
    label = "near_Rmax";
else
    label = "outside_Rmax";
end
end

function val = pct_warning(x, pct)
x = sort(double(x(:)));
x = x(isfinite(x));
if isempty(x)
    val = NaN;
else
    idx = max(1, min(numel(x), ceil(pct / 100 * numel(x))));
    val = x(idx);
end
end

function r = rel_change_warning(val, baseVal)
if abs(baseVal) <= eps
    if abs(val) <= eps
        r = 0;
    else
        r = Inf;
    end
else
    r = (val - baseVal) / abs(baseVal);
end
end
