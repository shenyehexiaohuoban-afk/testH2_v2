function result = calibrate_lookahead_y_step_h2(config)
%CALIBRATE_LOOKAHEAD_Y_STEP_H2 Calibrate positive-y look-ahead step.
%
% This routine only evaluates wind/road probability diagnostics. It does
% not sample D/A/C scenarios and does not call WDRO or MSP.

requiredFiles = {config.locCoordinateFile, config.pathTableFile, ...
    config.nearInputFile, config.roadEdgeFile, config.siteNodeFile};
for ii = 1:numel(requiredFiles)
    if ~isfile(requiredFiles{ii})
        error('calibrate_lookahead_y_step_h2:MissingInput', ...
            'Missing required input file: %s', requiredFiles{ii});
    end
end

locTbl = readtable(config.locCoordinateFile);
pathTbl = readtable(config.pathTableFile);
locTbl = sortrows(locTbl, 'loc');
locX = double(locTbl.x_coord(:));
xLocStep = median(diff(sort(unique(locX))));
candidateYStep = config.candidateMultipliers(:) .* xLocStep;

yBase = median(double(pathTbl.y_coord(:)));

raw = load(config.nearInputFile, 'NearStageInput');
if ~isfield(raw, 'NearStageInput')
    error('calibrate_lookahead_y_step_h2:MissingNearStageInput', ...
        'Missing NearStageInput in %s.', config.nearInputFile);
end
layout = build_h2_spatial_layout_preview(raw.NearStageInput);
roadNetwork = build_stage2_road_network_for_y_step(config, layout);

lineY = double(layout.lines.line_mid_y_km(:));
roadY = double(roadNetwork.edge_mid_y_km(:));
objectY = [lineY; roadY];
systemYMin = min(objectY);
systemYMax = max(objectY);
systemYMedian = median(objectY);

minPositiveY = yBase + config.yDirection * min(candidateYStep);
positiveMovesTowardSystem = config.yDirection > 0 && ...
    yBase < systemYMin && minPositiveY > yBase;

result = struct();
result.config = config;
result.loc_table = locTbl;
result.x_loc_step = xLocStep;
result.y_base = yBase;
result.candidate_y_step = candidateYStep;
result.candidate_multipliers = config.candidateMultipliers(:);
result.system_y_min = systemYMin;
result.system_y_max = systemYMax;
result.system_y_median = systemYMedian;
result.line_count = height(layout.lines);
result.road_edge_count = height(roadNetwork);
result.a_values = config.aValues(:);
result.tau_values = config.tauValues(:);
result.y_positive_moves_toward_system = positiveMovesTowardSystem;
result.recommended_y_step = NaN;
result.recommended_multiplier = NaN;

if positiveMovesTowardSystem
    result.status = 'blocked_positive_y_moves_toward_system';
    result.direction_note = sprintf(['Positive y moves from y_base=%.12g ' ...
        'toward system y range [%.12g, %.12g], so calibration stopped.'], ...
        yBase, systemYMin, systemYMax);
    [result.candidate_diagnostics, result.by_intensity, ...
        result.by_loc, result.wind_road_decay] = ...
        build_blocked_tables(config, locTbl, candidateYStep, xLocStep, yBase);
    return;
end

vmaxByA = build_vmax_map_y_step();
rmaxByA = build_rmax_map_y_step();
rmaxWeights = [0.3; 0.5; 0.2];

[candidateTbl, byIntensityTbl, byLocTbl, windTbl] = compute_candidate_tables( ...
    config, locTbl, layout, roadNetwork, candidateYStep, xLocStep, ...
    yBase, vmaxByA, rmaxByA, rmaxWeights);

candidateTbl = add_reduction_and_rule(candidateTbl, candidateYStep);
[recStep, recMult] = recommend_y_step(candidateTbl);

result.status = 'completed';
result.direction_note = 'Positive y did not trigger the closer-to-system stop rule.';
result.candidate_diagnostics = candidateTbl;
result.by_intensity = byIntensityTbl;
result.by_loc = byLocTbl;
result.wind_road_decay = windTbl;
result.recommended_y_step = recStep;
result.recommended_multiplier = recMult;
end

function roadNetwork = build_stage2_road_network_for_y_step(config, layout)
roadEdgesRaw = readtable(config.roadEdgeFile);
siteNodes = readtable(config.siteNodeFile);
require_vars_y_step(roadEdgesRaw, {'road_edge_id', 'from_node', 'to_node'}, ...
    'stage1_road_edges.csv');
require_vars_y_step(siteNodes, {'site_id', 'grid_node'}, ...
    'stage1_site_nodes.csv');

windNodePos = sortrows(layout.nodes(:, {'node_id', 'x_km', 'y_km'}), ...
    'node_id');
fromNode = double(roadEdgesRaw.from_node);
toNode = double(roadEdgesRaw.to_node);
fromX = windNodePos.x_km(fromNode);
fromY = windNodePos.y_km(fromNode);
toX = windNodePos.x_km(toNode);
toY = windNodePos.y_km(toNode);
edgeMidX = (fromX + toX) ./ 2;
edgeMidY = (fromY + toY) ./ 2;
edgeLength = hypot(toX - fromX, toY - fromY);
roadNetwork = table(double(roadEdgesRaw.road_edge_id), fromNode, toNode, ...
    fromX, fromY, toX, toY, edgeMidX, edgeMidY, edgeLength, ...
    'VariableNames', {'road_edge_id', 'from_node', 'to_node', ...
    'from_x_km', 'from_y_km', 'to_x_km', 'to_y_km', ...
    'edge_mid_x_km', 'edge_mid_y_km', 'edge_length_km'});
end

function require_vars_y_step(tbl, names, fileName)
for ii = 1:numel(names)
    if ~ismember(names{ii}, tbl.Properties.VariableNames)
        error('calibrate_lookahead_y_step_h2:MissingColumn', ...
            '%s is missing required column %s.', fileName, names{ii});
    end
end
end

function [candidateTbl, byIntensityTbl, byLocTbl, windTbl] = ...
    compute_candidate_tables(config, locTbl, layout, roadNetwork, ...
    candidateYStep, xLocStep, yBase, vmaxByA, rmaxByA, rmaxWeights)

candidateRows = {};
intensityRows = {};
locRows = {};
windRows = {};

for cc = 1:numel(candidateYStep)
    yStep = candidateYStep(cc);
    multiplier = yStep / xLocStep;
    for tt = 1:numel(config.tauValues)
        tau = config.tauValues(tt);
        yTau = yBase + tau * yStep;
        allLineWind = [];
        allLineP = [];
        allRoadWind = [];
        allRoadP = [];

        for aa = config.aValues(:).'
            lineWindA = [];
            linePA = [];
            roadWindA = [];
            roadPA = [];
            for rr = 1:height(locTbl)
                xCoord = double(locTbl.x_coord(rr));
                [lineWind, lineP, roadWind, roadP] = evaluate_center( ...
                    xCoord, yTau, aa, layout, roadNetwork, config, ...
                    vmaxByA, rmaxByA, rmaxWeights);
                lineWindA = [lineWindA; lineWind(:)]; %#ok<AGROW>
                linePA = [linePA; lineP(:)]; %#ok<AGROW>
                roadWindA = [roadWindA; roadWind(:)]; %#ok<AGROW>
                roadPA = [roadPA; roadP(:)]; %#ok<AGROW>
            end
            intensityRows(end + 1, :) = {yStep, multiplier, aa, tau, ...
                max(linePA), pct_y_step(linePA, 95), mean(linePA), ...
                max(roadPA), pct_y_step(roadPA, 95), mean(roadPA)}; %#ok<AGROW>
            allLineWind = [allLineWind; lineWindA]; %#ok<AGROW>
            allLineP = [allLineP; linePA]; %#ok<AGROW>
            allRoadWind = [allRoadWind; roadWindA]; %#ok<AGROW>
            allRoadP = [allRoadP; roadPA]; %#ok<AGROW>
        end

        for rr = 1:height(locTbl)
            loc = double(locTbl.loc(rr));
            xCoord = double(locTbl.x_coord(rr));
            linePLoc = [];
            roadPLoc = [];
            for aa = config.aValues(:).'
                [~, lineP, ~, roadP] = evaluate_center( ...
                    xCoord, yTau, aa, layout, roadNetwork, config, ...
                    vmaxByA, rmaxByA, rmaxWeights);
                linePLoc = [linePLoc; lineP(:)]; %#ok<AGROW>
                roadPLoc = [roadPLoc; roadP(:)]; %#ok<AGROW>
            end
            locRows(end + 1, :) = {yStep, multiplier, loc, tau, xCoord, ...
                yTau, max(linePLoc), pct_y_step(linePLoc, 95), ...
                max(roadPLoc), pct_y_step(roadPLoc, 95)}; %#ok<AGROW>
        end

        candidateRows(end + 1, :) = {yStep, multiplier, xLocStep, yBase, ...
            tau, yTau, max(allLineP), pct_y_step(allLineP, 95), ...
            mean(allLineP), median(allLineP), max(allRoadP), ...
            pct_y_step(allRoadP, 95), mean(allRoadP), median(allRoadP), ...
            NaN, NaN, false}; %#ok<AGROW>
        windRows(end + 1, :) = {yStep, tau, max(allLineWind), ...
            pct_y_step(allLineWind, 95), max(allLineP), ...
            pct_y_step(allLineP, 95), max(allRoadWind), ...
            pct_y_step(allRoadWind, 95), max(allRoadP), ...
            pct_y_step(allRoadP, 95)}; %#ok<AGROW>
    end
end

candidateTbl = cell2table(candidateRows, 'VariableNames', ...
    {'candidate_y_step', 'candidate_y_step_over_x_step', 'x_loc_step', ...
    'y_base', 'tau', 'y_tau', 'line_pFail_max', 'line_pFail_p95', ...
    'line_pFail_mean', 'line_pFail_median', 'road_pClose_max', ...
    'road_pClose_p95', 'road_pClose_mean', 'road_pClose_median', ...
    'line_pFail_p95_reduction_vs_tau1', ...
    'road_pClose_p95_reduction_vs_tau1', 'meets_W3_decay_rule'});
byIntensityTbl = cell2table(intensityRows, 'VariableNames', ...
    {'candidate_y_step', 'candidate_y_step_over_x_step', 'a', 'tau', ...
    'line_pFail_max', 'line_pFail_p95', 'line_pFail_mean', ...
    'road_pClose_max', 'road_pClose_p95', 'road_pClose_mean'});
byLocTbl = cell2table(locRows, 'VariableNames', ...
    {'candidate_y_step', 'candidate_y_step_over_x_step', 'loc', 'tau', ...
    'x_coord', 'y_tau', 'line_pFail_max', 'line_pFail_p95', ...
    'road_pClose_max', 'road_pClose_p95'});
windTbl = cell2table(windRows, 'VariableNames', ...
    {'candidate_y_step', 'tau', 'line_wind_speed_max', ...
    'line_wind_speed_p95', 'line_pFail_max', 'line_pFail_p95', ...
    'road_wind_speed_max', 'road_wind_speed_p95', 'road_pClose_max', ...
    'road_pClose_p95'});
end

function [lineWind, lineP, roadWind, roadP] = evaluate_center( ...
    xCoord, yCoord, a, layout, roadNetwork, config, vmaxByA, rmaxByA, ...
    rmaxWeights)

Vmax = vmaxByA(max(1, min(numel(vmaxByA), a)));
linePByR = zeros(height(layout.lines), numel(rmaxWeights));
roadPByR = zeros(height(roadNetwork), numel(rmaxWeights));
lineWindByR = zeros(height(layout.lines), numel(rmaxWeights));
roadWindByR = zeros(height(roadNetwork), numel(rmaxWeights));

lineDist = hypot(layout.lines.line_mid_x_km - xCoord, ...
    layout.lines.line_mid_y_km - yCoord);
roadDist = hypot(roadNetwork.edge_mid_x_km - xCoord, ...
    roadNetwork.edge_mid_y_km - yCoord);

for rr = 1:numel(rmaxWeights)
    Rmax = rmaxByA(max(1, min(size(rmaxByA, 1), a)), rr);
    lineWindByR(:, rr) = compute_wind_speed_radial_h2(lineDist, Vmax, ...
        Rmax, config.windDecayB);
    roadWindByR(:, rr) = compute_wind_speed_radial_h2(roadDist, Vmax, ...
        Rmax, config.windDecayB);
    linePByR(:, rr) = compute_line_failure_prob_h2(lineWindByR(:, rr), ...
        config.designWindSpeedVN);
    roadPByR(:, rr) = compute_line_failure_prob_h2(roadWindByR(:, rr), ...
        config.roadDesignWindVN);
end

lineWind = lineWindByR * rmaxWeights(:);
roadWind = roadWindByR * rmaxWeights(:);
lineP = linePByR * rmaxWeights(:);
roadP = roadPByR * rmaxWeights(:);
end

function tbl = add_reduction_and_rule(tbl, candidateYStep)
for cc = 1:numel(candidateYStep)
    rows = find(abs(tbl.candidate_y_step - candidateYStep(cc)) <= 1e-9);
    tau1 = rows(tbl.tau(rows) == 1);
    tau3 = rows(tbl.tau(rows) == 3);
    if isempty(tau1) || isempty(tau3)
        continue;
    end
    lineBase = max(tbl.line_pFail_p95(tau1), eps);
    roadBase = max(tbl.road_pClose_p95(tau1), eps);
    for rr = rows(:).'
        tbl.line_pFail_p95_reduction_vs_tau1(rr) = ...
            1 - tbl.line_pFail_p95(rr) / lineBase;
        tbl.road_pClose_p95_reduction_vs_tau1(rr) = ...
            1 - tbl.road_pClose_p95(rr) / roadBase;
    end
    lineDecay = tbl.line_pFail_p95_reduction_vs_tau1(tau3) >= 0.9 || ...
        tbl.line_pFail_p95(tau3) <= 1e-3;
    roadDecay = tbl.road_pClose_p95_reduction_vs_tau1(tau3) >= 0.9 || ...
        tbl.road_pClose_p95(tau3) <= 1e-3;
    tau1Influence = tbl.line_pFail_p95(tau1) > 1e-6 || ...
        tbl.line_pFail_max(tau1) > 1e-6;
    tbl.meets_W3_decay_rule(tau3) = lineDecay && roadDecay && tau1Influence;
end
end

function [recStep, recMult] = recommend_y_step(tbl)
rows = tbl(tbl.tau == 3 & tbl.meets_W3_decay_rule, :);
if isempty(rows)
    recStep = NaN;
    recMult = NaN;
    return;
end
rows = sortrows(rows, 'candidate_y_step');
recStep = rows.candidate_y_step(1);
recMult = rows.candidate_y_step_over_x_step(1);
end

function [candidateTbl, byIntensityTbl, byLocTbl, windTbl] = ...
    build_blocked_tables(config, locTbl, candidateYStep, xLocStep, yBase)

candidateRows = {};
intensityRows = {};
locRows = {};
windRows = {};
for cc = 1:numel(candidateYStep)
    yStep = candidateYStep(cc);
    multiplier = yStep / xLocStep;
    for tau = config.tauValues(:).'
        yTau = yBase + tau * yStep;
        candidateRows(end + 1, :) = {yStep, multiplier, xLocStep, yBase, ...
            tau, yTau, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, ...
            NaN, NaN, false}; %#ok<AGROW>
        windRows(end + 1, :) = {yStep, tau, NaN, NaN, NaN, NaN, NaN, ...
            NaN, NaN, NaN}; %#ok<AGROW>
        for aa = config.aValues(:).'
            intensityRows(end + 1, :) = {yStep, multiplier, aa, tau, ...
                NaN, NaN, NaN, NaN, NaN, NaN}; %#ok<AGROW>
        end
        for rr = 1:height(locTbl)
            locRows(end + 1, :) = {yStep, multiplier, double(locTbl.loc(rr)), ...
                tau, double(locTbl.x_coord(rr)), yTau, NaN, NaN, ...
                NaN, NaN}; %#ok<AGROW>
        end
    end
end

candidateTbl = cell2table(candidateRows, 'VariableNames', ...
    {'candidate_y_step', 'candidate_y_step_over_x_step', 'x_loc_step', ...
    'y_base', 'tau', 'y_tau', 'line_pFail_max', 'line_pFail_p95', ...
    'line_pFail_mean', 'line_pFail_median', 'road_pClose_max', ...
    'road_pClose_p95', 'road_pClose_mean', 'road_pClose_median', ...
    'line_pFail_p95_reduction_vs_tau1', ...
    'road_pClose_p95_reduction_vs_tau1', 'meets_W3_decay_rule'});
byIntensityTbl = cell2table(intensityRows, 'VariableNames', ...
    {'candidate_y_step', 'candidate_y_step_over_x_step', 'a', 'tau', ...
    'line_pFail_max', 'line_pFail_p95', 'line_pFail_mean', ...
    'road_pClose_max', 'road_pClose_p95', 'road_pClose_mean'});
byLocTbl = cell2table(locRows, 'VariableNames', ...
    {'candidate_y_step', 'candidate_y_step_over_x_step', 'loc', 'tau', ...
    'x_coord', 'y_tau', 'line_pFail_max', 'line_pFail_p95', ...
    'road_pClose_max', 'road_pClose_p95'});
windTbl = cell2table(windRows, 'VariableNames', ...
    {'candidate_y_step', 'tau', 'line_wind_speed_max', ...
    'line_wind_speed_p95', 'line_pFail_max', 'line_pFail_p95', ...
    'road_wind_speed_max', 'road_wind_speed_p95', 'road_pClose_max', ...
    'road_pClose_p95'});
end

function V = build_vmax_map_y_step()
V = nan(6, 1);
V(1) = 0;
V(2:6) = [20.8; 28.55; 37.05; 46.20; 55.50];
end

function R = build_rmax_map_y_step()
R = nan(6, 3);
R(1, :) = [15, 25, 35];
R(2, :) = [15, 25, 35];
R(3, :) = [18, 30, 42];
R(4, :) = [20, 35, 50];
R(5, :) = [25, 40, 60];
R(6, :) = [30, 50, 75];
end

function val = pct_y_step(x, pct)
x = sort(double(x(:)));
x = x(isfinite(x));
if isempty(x)
    val = NaN;
    return;
end
idx = max(1, min(numel(x), ceil(pct / 100 * numel(x))));
val = x(idx);
end
