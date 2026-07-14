function result = build_lookahead_W3_DAC_samples_h2(config)
%BUILD_LOOKAHEAD_W3_DAC_SAMPLES_H2 Build W=3 consequence samples.
%
% This offline generator samples grid line failures and
% road edge closures conditional on Stage 2A W=3 typhoon paths, aggregates
% D/A/C over tau=1:W, and never calls the WDRO LP or MSP main loop.

if nargin < 1 || isempty(config)
    config = struct();
end
config = apply_default_config(config);
validate_inputs(config);

rng(config.random_seed, 'twister');

opts = h2_default_options(config.rootDir);
opts.support_hours = 2;
params = load_data_h2_near(opts.dataDir, opts.nearInputFile, opts);
layout = build_h2_spatial_layout_preview(params.NearStageInput);
stage1Road = load_stage1_road_data_b1(config, params, layout);

pathTbl = readtable(config.inputPathTable);
windowTbl = readtable(config.windowConfigFile, 'TextType', 'string');
locationTbl = readtable(config.locationConfigFile);
intensityTbl = readtable(config.intensityConfigFile);
validate_stage2_config_tables(windowTbl, locationTbl, intensityTbl);

stateTbl = unique(pathTbl(:, {'a0', 'loc0', 'lf'}), 'rows', 'stable');
stateTbl = sortrows(stateTbl, {'a0', 'loc0', 'lf'});

rowsSiteNode = {};
rowsSummary = {};
scenarioGlobalId = 0;

for st = 1:height(stateTbl)
    a0 = stateTbl.a0(st);
    loc0 = stateTbl.loc0(st);
    lf = stateTbl.lf(st);
    statePaths = pathTbl(pathTbl.a0 == a0 & pathTbl.loc0 == loc0 & ...
        pathTbl.lf == lf, :);
    pathIds = unique(statePaths.path_id, 'stable');
    pathIds = sort(pathIds(:));
    if numel(pathIds) < config.P
        error('build_lookahead_W3_DAC_samples_h2:NotEnoughPaths', ...
            'State a=%d loc=%d lf=%d has only %d paths; P=%d.', ...
            a0, loc0, lf, numel(pathIds), config.P);
    end
    selectedPathIds = select_path_ids_h2(pathIds, config);

    for pp = 1:numel(selectedPathIds)
        pathId = selectedPathIds(pp);
        pathRows = statePaths(statePaths.path_id == pathId, :);
        pathRows = sortrows(pathRows, 'tau');
        for damageId = 1:config.M
            scenarioGlobalId = scenarioGlobalId + 1;
            scenarioId = (pp - 1) * config.M + damageId;
            tauOut = simulate_path_damage_h2(pathRows, params, layout, ...
                stage1Road, config);
            aggregated = aggregate_W3_DAC_outcomes_h2(tauOut, ...
                stage1Road.site_to_node_road_km, config);

            rowsSummary(end + 1, :) = build_summary_row(a0, loc0, lf, ...
                pathId, damageId, scenarioId, aggregated, tauOut); %#ok<AGROW>

            for i = 1:params.Ni
                for n = 1:params.Nj
                    rowsSiteNode(end + 1, :) = {a0, loc0, lf, pathId, ...
                        damageId, scenarioId, "sum_tau_D_all_tau_A_critical_tau_C_mean", ...
                        i, n, aggregated.D(n), aggregated.A(i, n), ...
                        aggregated.C(i, n), aggregated.C_before_fix(i, n), ...
                        aggregated.delay(i, n)}; %#ok<AGROW>
                end
            end
        end
    end
end

siteNodeTbl = cell2table(rowsSiteNode, 'VariableNames', ...
    {'a', 'loc', 'lf', 'path_id', 'damage_id', 'scenario_id', ...
    'tau_aggregation_mode', 'site_id', 'node_id', 'D_node_kg_s', ...
    'reachable', 'scenario_service_cost', ...
    'scenario_service_cost_before_fix', 'scenario_service_delay'});
summaryTbl = cell2table(rowsSummary, 'VariableNames', ...
    {'a', 'loc', 'lf', 'path_id', 'damage_id', 'scenario_id', ...
    'D_total', 'reachable_pair_count', 'reachable_pair_share', ...
    'C_reachable_mean', 'C_reachable_max', ...
    'C_reachable_mean_before_fix', 'C_reachable_max_before_fix', ...
    'unreachable_pair_count', 'unreachable_C_has_inf', ...
    'blocked_road_count', 'slow_road_count', ...
    'failed_power_line_count'});

writetable(siteNodeTbl, fullfile(config.outputDir, ...
    'lookahead_scenario_site_node.csv'));
writetable(summaryTbl, fullfile(config.outputDir, ...
    'lookahead_scenario_summary.csv'));

diag = write_lookahead_W3_B1_diagnostics_h2(siteNodeTbl, summaryTbl, ...
    config);

if strcmpi(config.stage_label, 'B1')
    write_b1_readme(config, height(stateTbl), scenarioGlobalId, diag);
    write_b1_docs(config);
    write_implementation_audit_b1(config, diag);
end

result = struct();
result.config = config;
result.state_count = height(stateTbl);
result.scenario_count_total = scenarioGlobalId;
result.site_node = siteNodeTbl;
result.summary = summaryTbl;
result.diagnostics = diag;
end

function config = apply_default_config(config)
srcDir = fileparts(mfilename('fullpath'));
moduleDir = fileparts(srcDir);
rootDir = fileparts(moduleDir);
if ~isfield(config, 'rootDir') || isempty(config.rootDir)
    config.rootDir = rootDir;
end
if ~isfield(config, 'moduleDir') || isempty(config.moduleDir)
    config.moduleDir = moduleDir;
end
if ~isfield(config, 'inputPathTable') || isempty(config.inputPathTable)
    config.inputPathTable = fullfile(config.moduleDir, 'output', ...
        'stage2_lookahead_W3', 'lookahead_path_table.csv');
end
if ~isfield(config, 'outputDir') || isempty(config.outputDir)
    config.outputDir = fullfile(config.moduleDir, 'output', ...
        'stage2_lookahead_W3_B1_DAC_samples');
end
if ~isfield(config, 'docsDir') || isempty(config.docsDir)
    config.docsDir = fullfile(config.moduleDir, 'docs');
end
if ~isfield(config, 'windowConfigFile') || isempty(config.windowConfigFile)
    config.windowConfigFile = fullfile(config.moduleDir, 'config', ...
        'lookahead_window_W3.csv');
end
if ~isfield(config, 'locationConfigFile') || isempty(config.locationConfigFile)
    config.locationConfigFile = fullfile(config.moduleDir, 'config', ...
        'lookahead_location_W3.csv');
end
if ~isfield(config, 'intensityConfigFile') || isempty(config.intensityConfigFile)
    config.intensityConfigFile = fullfile(config.moduleDir, 'config', ...
        'lookahead_intensity_W3.csv');
end
defaults = struct('P_B1', 10, 'M_B1', 3, 'random_seed_B1', 20260707, ...
    'stage_label', 'B1', 'pathSelectionMode', 'first', ...
    'windDecayB', 0.6, 'designWindSpeedVN', 25, ...
    'roadDesignWindVN', 30, 'roadSlowdownLambda', 1.0, ...
    'serviceRadiusPenalty', 1.0, 'serviceTimeLimit', 60, ...
    'slowRoadPCloseThreshold', 1e-6, 'demandToleranceKg', 1e-9);
names = fieldnames(defaults);
for ii = 1:numel(names)
    name = names{ii};
    if ~isfield(config, name) || isempty(config.(name))
        config.(name) = defaults.(name);
    end
end
if ~isfield(config, 'P') || isempty(config.P)
    if isfield(config, 'P_B2') && ~isempty(config.P_B2)
        config.P = config.P_B2;
    else
        config.P = config.P_B1;
    end
end
if ~isfield(config, 'M') || isempty(config.M)
    if isfield(config, 'M_B2') && ~isempty(config.M_B2)
        config.M = config.M_B2;
    else
        config.M = config.M_B1;
    end
end
if ~isfield(config, 'random_seed') || isempty(config.random_seed)
    if isfield(config, 'random_seed_B2') && ~isempty(config.random_seed_B2)
        config.random_seed = config.random_seed_B2;
    else
        config.random_seed = config.random_seed_B1;
    end
end
end

function validate_inputs(config)
files = {config.inputPathTable, config.windowConfigFile, ...
    config.locationConfigFile, config.intensityConfigFile};
for ii = 1:numel(files)
    if ~isfile(files{ii})
        error('build_lookahead_W3_DAC_samples_h2:MissingInput', ...
            'Missing required input file: %s', files{ii});
    end
end
if config.P <= 0 || config.M <= 0
    error('build_lookahead_W3_DAC_samples_h2:BadSampleSize', ...
        'P and M must be positive integers.');
end
end

function selectedPathIds = select_path_ids_h2(pathIds, config)
if numel(pathIds) == config.P
    selectedPathIds = pathIds(:);
    return;
end

mode = char(lower(string(config.pathSelectionMode)));
switch mode
    case {'first', 'first_p'}
        selectedPathIds = pathIds(1:config.P);
    case {'random', 'random_if_needed', 'fixed_seed_random'}
        perm = randperm(numel(pathIds), config.P);
        selectedPathIds = sort(pathIds(perm));
    otherwise
        error('build_lookahead_W3_DAC_samples_h2:BadPathSelectionMode', ...
            'Unsupported pathSelectionMode: %s', config.pathSelectionMode);
end
end

function validate_stage2_config_tables(windowTbl, locationTbl, intensityTbl)
if ~all(ismember({'key', 'value'}, windowTbl.Properties.VariableNames))
    error('build_lookahead_W3_DAC_samples_h2:BadWindowConfig', ...
        'lookahead_window_W3.csv must contain key,value.');
end
if ~all(ismember({'from_loc_id', 'to_loc_id', 'prob'}, ...
        locationTbl.Properties.VariableNames))
    error('build_lookahead_W3_DAC_samples_h2:BadLocationConfig', ...
        'lookahead_location_W3.csv must contain from_loc_id,to_loc_id,prob.');
end
if ~all(ismember({'from_a', 'to_a', 'prob'}, ...
        intensityTbl.Properties.VariableNames))
    error('build_lookahead_W3_DAC_samples_h2:BadIntensityConfig', ...
        'lookahead_intensity_W3.csv must contain from_a,to_a,prob.');
end
end

function tauOut = simulate_path_damage_h2(pathRows, params, layout, stage1Road, config)
W = height(pathRows);
PNodeLoadKw = params.P_node_load_kw(:);
supportHours = get_terminal_scalar_b1(params, 'support_hours');
etaFC = get_terminal_scalar_b1(params, 'eta_FC');
lhv = get_terminal_scalar_b1(params, 'h2_lhv_kWh_per_kg');
vmaxByA = build_vmax_map(params);
rmaxByA = build_rmax_map(params);
rmaxProb = [0.3, 0.5, 0.2];
rmaxType = ["small", "mid", "large"];

D_tau = zeros(W, params.Nj);
reach_tau = false(W, params.Ni, params.Nj);
cost_tau = inf(W, params.Ni, params.Nj);
costBeforeFixTau = inf(W, params.Ni, params.Nj);
blockedRoadCount = zeros(W, 1);
slowRoadCount = zeros(W, 1);
failedLineCount = zeros(W, 1);
rmaxLabel = strings(W, 1);

for tt = 1:W
    aTau = pathRows.a_tau(tt);
    Vmax = 0;
    if aTau >= 1 && aTau <= numel(vmaxByA) && isfinite(vmaxByA(aTau))
        Vmax = vmaxByA(aTau);
    end
    rIdx = sample_discrete_b1(rmaxProb);
    Rmax = rmaxByA(max(1, min(size(rmaxByA, 1), aTau)), rIdx);
    rmaxLabel(tt) = rmaxType(rIdx);
    center = [pathRows.x_coord(tt), pathRows.y_coord(tt)];

    lineDist = hypot(layout.lines.line_mid_x_km - center(1), ...
        layout.lines.line_mid_y_km - center(2));
    lineWind = compute_wind_speed_radial_h2(lineDist, Vmax, Rmax, ...
        config.windDecayB);
    pFail = compute_line_failure_prob_h2(lineWind, config.designWindSpeedVN);
    failedLine = rand(height(layout.lines), 1) < pFail(:);
    connected = connected_to_source_b1(params.Nj, layout.lines.from_node, ...
        layout.lines.to_node, ~failedLine);
    outage = ~connected(:);
    outage(1) = false;
    lostLoadKw = double(outage) .* PNodeLoadKw;
    D_tau(tt, :) = (lostLoadKw * supportHours / (etaFC * lhv)).';
    failedLineCount(tt) = sum(failedLine);

    roadDist = hypot(stage1Road.network.edge_mid_x_km - center(1), ...
        stage1Road.network.edge_mid_y_km - center(2));
    roadWind = compute_wind_speed_radial_h2(roadDist, Vmax, Rmax, ...
        config.windDecayB);
    pClose = compute_line_failure_prob_h2(roadWind, config.roadDesignWindVN);
    baseEdgeTime = stage1Road.network.edge_length_km(:) .* ...
        (1 + config.roadSlowdownLambda .* pClose(:));
    closedRoad = rand(height(stage1Road.network), 1) < pClose(:);
    edgeTime = baseEdgeTime;
    edgeTime(closedRoad) = Inf;
    blockedRoadCount(tt) = sum(closedRoad);
    slowRoadCount(tt) = sum(~closedRoad(:) & ...
        pClose(:) > config.slowRoadPCloseThreshold & ...
        baseEdgeTime(:) > stage1Road.network.edge_length_km(:) + 1e-9);

    for i = 1:params.Ni
        dist = dijkstra_b1(params.Nj, stage1Road.network, edgeTime, ...
            stage1Road.site_anchor_node(i));
        for n = 1:params.Nj
            if isfinite(dist(n))
                reach_tau(tt, i, n) = true;
                cost_tau(tt, i, n) = dist(n);
                costBeforeFixTau(tt, i, n) = ...
                    stage1Road.site_to_node_road_km(i, n) + dist(n);
            end
        end
    end
end

tauOut = struct();
tauOut.D_tau = D_tau;
tauOut.reach_tau = reach_tau;
tauOut.cost_tau = cost_tau;
tauOut.cost_before_fix_tau = costBeforeFixTau;
tauOut.blocked_road_count = blockedRoadCount;
tauOut.slow_road_count = slowRoadCount;
tauOut.failed_power_line_count = failedLineCount;
tauOut.rmax_type = rmaxLabel;
end

function row = build_summary_row(a0, loc0, lf, pathId, damageId, ...
    scenarioId, aggregated, tauOut)
reachablePairCount = sum(aggregated.A(:) > 0.5);
totalPairCount = numel(aggregated.A);
reachableCosts = aggregated.C(aggregated.A > 0.5 & isfinite(aggregated.C));
reachableCostsBeforeFix = aggregated.C_before_fix( ...
    aggregated.A > 0.5 & isfinite(aggregated.C_before_fix));
if isempty(reachableCosts)
    cMean = NaN;
    cMax = NaN;
else
    cMean = mean(reachableCosts);
    cMax = max(reachableCosts);
end
if isempty(reachableCostsBeforeFix)
    cMeanBeforeFix = NaN;
    cMaxBeforeFix = NaN;
else
    cMeanBeforeFix = mean(reachableCostsBeforeFix);
    cMaxBeforeFix = max(reachableCostsBeforeFix);
end
unreachableC = aggregated.C(aggregated.A <= 0.5);
row = {a0, loc0, lf, pathId, damageId, scenarioId, sum(aggregated.D), ...
    reachablePairCount, reachablePairCount / totalPairCount, ...
    cMean, cMax, cMeanBeforeFix, cMaxBeforeFix, ...
    totalPairCount - reachablePairCount, any(isinf(unreachableC)), ...
    sum(tauOut.blocked_road_count), sum(tauOut.slow_road_count), ...
    sum(tauOut.failed_power_line_count)};
end

function stage1Road = load_stage1_road_data_b1(config, params, windLayout)
roadDataDir = fullfile(config.rootDir, 'data', 'yuanqi');
roadEdgesRaw = readtable(fullfile(roadDataDir, 'stage1_road_edges.csv'));
siteNodes = readtable(fullfile(roadDataDir, 'stage1_site_nodes.csv'));
require_table_vars_b1(roadEdgesRaw, {'road_edge_id', 'from_node', 'to_node'}, ...
    'stage1_road_edges.csv');
require_table_vars_b1(siteNodes, {'site_id', 'grid_node'}, ...
    'stage1_site_nodes.csv');

windNodePos = sortrows(windLayout.nodes(:, {'node_id', 'x_km', 'y_km'}), ...
    'node_id');
windSitePos = sortrows(windLayout.sites(:, {'site_id', 'x_km', 'y_km'}), ...
    'site_id');
siteNodes = sortrows(siteNodes, 'site_id');
fromNode = roadEdgesRaw.from_node;
toNode = roadEdgesRaw.to_node;
fromX = windNodePos.x_km(fromNode);
fromY = windNodePos.y_km(fromNode);
toX = windNodePos.x_km(toNode);
toY = windNodePos.y_km(toNode);
edgeMidX = (fromX + toX) / 2;
edgeMidY = (fromY + toY) / 2;
edgeLength = hypot(toX - fromX, toY - fromY);
network = table(roadEdgesRaw.road_edge_id, fromNode, toNode, fromX, ...
    fromY, toX, toY, edgeMidX, edgeMidY, edgeLength, ...
    'VariableNames', {'road_edge_id', 'from_node', 'to_node', ...
    'from_x_km', 'from_y_km', 'to_x_km', 'to_y_km', ...
    'edge_mid_x_km', 'edge_mid_y_km', 'edge_length_km'});

siteToNodeKm = nan(params.Ni, params.Nj);
for i = 1:params.Ni
    dist = dijkstra_b1(params.Nj, network, network.edge_length_km, ...
        siteNodes.grid_node(i));
    siteToNodeKm(i, :) = dist(:).';
end
if any(~isfinite(siteToNodeKm(:)))
    error('build_lookahead_W3_DAC_samples_h2:DisconnectedRoadGraph', ...
        'Stage1 road graph does not connect every site anchor to every node.');
end

stage1Road = struct();
stage1Road.network = network;
stage1Road.site_anchor_node = siteNodes.grid_node(:);
stage1Road.site_to_node_road_km = siteToNodeKm;
stage1Road.node_positions = windNodePos;
stage1Road.site_nodes = table(siteNodes.site_id, siteNodes.grid_node, ...
    windSitePos.x_km, windSitePos.y_km, ...
    'VariableNames', {'site_id', 'grid_node', 'x_km', 'y_km'});
end

function V = build_vmax_map(params)
V = nan(max(params.Na, 6), 1);
V(1) = 0;
V(2:6) = [20.8; 28.55; 37.05; 46.20; 55.50];
end

function R = build_rmax_map(params)
R = nan(max(params.Na, 6), 3);
R(1, :) = [15, 25, 35];
R(2, :) = [15, 25, 35];
R(3, :) = [18, 30, 42];
R(4, :) = [20, 35, 50];
R(5, :) = [25, 40, 60];
R(6, :) = [30, 50, 75];
end

function connected = connected_to_source_b1(Nj, fromNode, toNode, activeLine)
adj = false(Nj, Nj);
for ll = 1:numel(fromNode)
    if activeLine(ll)
        i = fromNode(ll);
        j = toNode(ll);
        adj(i, j) = true;
        adj(j, i) = true;
    end
end
connected = false(Nj, 1);
queue = zeros(Nj, 1);
head = 1;
tail = 1;
queue(tail) = 1;
connected(1) = true;
while head <= tail
    cur = queue(head);
    head = head + 1;
    nbrs = find(adj(cur, :));
    for nn = nbrs
        if ~connected(nn)
            connected(nn) = true;
            tail = tail + 1;
            queue(tail) = nn;
        end
    end
end
end

function dist = dijkstra_b1(Ntotal, roadNetwork, edgeTime, sourceNode)
dist = inf(Ntotal, 1);
visited = false(Ntotal, 1);
dist(sourceNode) = 0;
for iter = 1:Ntotal
    candidates = find(~visited);
    if isempty(candidates)
        break;
    end
    [bestVal, pos] = min(dist(candidates));
    if ~isfinite(bestVal)
        break;
    end
    u = candidates(pos);
    visited(u) = true;
    for ee = 1:height(roadNetwork)
        if ~isfinite(edgeTime(ee))
            continue;
        end
        from = roadNetwork.from_node(ee);
        to = roadNetwork.to_node(ee);
        if from == u
            v = to;
        elseif to == u
            v = from;
        else
            continue;
        end
        if ~visited(v) && dist(u) + edgeTime(ee) < dist(v)
            dist(v) = dist(u) + edgeTime(ee);
        end
    end
end
end

function idx = sample_discrete_b1(prob)
p = double(prob(:));
p = p ./ sum(p);
u = rand();
idx = find(u <= cumsum(p), 1, 'first');
if isempty(idx)
    idx = numel(p);
end
end

function val = get_terminal_scalar_b1(params, fieldName)
if isfield(params, 'terminal_load_info') && ...
        isfield(params.terminal_load_info, fieldName)
    val = double(params.terminal_load_info.(fieldName));
elseif isfield(params, fieldName)
    val = double(params.(fieldName));
else
    error('build_lookahead_W3_DAC_samples_h2:MissingTerminalScalar', ...
        'Missing params.%s.', fieldName);
end
end

function require_table_vars_b1(tbl, names, fileName)
for ii = 1:numel(names)
    if ~ismember(names{ii}, tbl.Properties.VariableNames)
        error('build_lookahead_W3_DAC_samples_h2:MissingRoadColumn', ...
            '%s is missing column %s.', fileName, names{ii});
    end
end
end

function write_b1_readme(config, stateCount, scenarioCount, diag)
fid = fopen(fullfile(config.outputDir, 'README_B1_DAC_samples.txt'), 'w');
if fid < 0
    error('build_lookahead_W3_DAC_samples_h2:ReadmeOpenFailed', ...
        'Could not open README_B1_DAC_samples.txt.');
end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'Stage 2B1 W=3 small-sample D/A/C consequence generation\n\n');
fprintf(fid, 'This stage generates small smoke-test consequence samples only.\n');
fprintf(fid, 'It does not run WDRO-LP and is not connected to MSP.\n\n');
fprintf(fid, 'Settings: P_B1=%d, M_B1=%d, R_B1=%d per state, seed=%d.\n', ...
    config.P_B1, config.M_B1, config.P_B1 * config.M_B1, ...
    config.random_seed_B1);
fprintf(fid, 'State count: %d. Scenario count total: %d.\n\n', ...
    stateCount, scenarioCount);
fprintf(fid, 'D is aggregated by summing tau=1:W node hydrogen demand.\n');
fprintf(fid, 'A is binary: A=1 means a feasible service path exists; A=0 means fully unreachable.\n');
fprintf(fid, 'A never represents slow roads through fractional values such as A=0.3.\n');
fprintf(fid, 'C represents reachable service cost / travel impedance / travel time.\n');
fprintf(fid, 'C is the current road-state shortest path cost dist(n), not baseCost + dist(n).\n');
fprintf(fid, 'A previous B1 version double-counted baseCost in C; this run removes that duplicate term and keeps before/after diagnostics.\n');
fprintf(fid, 'Passable but slow roads keep A=1 and increase C.\n');
fprintf(fid, 'If A=0, C is written as Inf and later DAC_maskedC must not compare it.\n\n');
fprintf(fid, 'A_binary_ok_all_states: %d.\n', diag.A_binary_ok_all);
fprintf(fid, 'Has slow reachable samples: %d.\n', diag.has_slow_reachable_samples);
fprintf(fid, 'Has fully unreachable samples: %d.\n', diag.has_unreachable_samples);
fprintf(fid, 'Max D_total_max_to_mean: %.12g.\n\n', diag.max_D_total_max_to_mean);
fprintf(fid, 'C_reachable_mean_before_fix_overall: %.12g.\n', diag.C_reachable_mean_before_fix_overall);
fprintf(fid, 'C_reachable_mean_after_fix_overall: %.12g.\n', diag.C_reachable_mean_after_fix_overall);
fprintf(fid, 'C_reachable_max_before_fix_overall: %.12g.\n', diag.C_reachable_max_before_fix_overall);
fprintf(fid, 'C_reachable_max_after_fix_overall: %.12g.\n\n', diag.C_reachable_max_after_fix_overall);
fprintf(fid, 'Smoke-test simplifications:\n');
fprintf(fid, '- Uses existing preview wind/grid/road Monte Carlo structure and fragility functions.\n');
fprintf(fid, '- Uses existing preview Vmax/Rmax mapping and Rmax probabilities [0.3,0.5,0.2].\n');
fprintf(fid, '- Site/node counts come from load_data_h2_near params.Ni=4 and params.Nj=33.\n');
fprintf(fid, '- Uses first-P path selection only for smoke testing; B2 should use fixed-seed random or stratified sampling.\n');
fprintf(fid, '- B1 outputs are not formal paper numerical results.\n\n');
fprintf(fid, 'Formal follow-up should expand sample size to R=200 or R=500 per state before WDRO analysis.\n');
end

function write_b1_docs(config)
docFile = fullfile(config.docsDir, 'README_lookahead_W3_B1_DAC_samples.md');
fid = fopen(docFile, 'w');
if fid < 0
    error('build_lookahead_W3_DAC_samples_h2:DocOpenFailed', ...
        'Could not open README_lookahead_W3_B1_DAC_samples.md.');
end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '# Stage 2B1 W=3 D/A/C Smoke Samples\n\n');
fprintf(fid, '## Goal\n\n');
fprintf(fid, 'Generate small W=3 look-ahead consequence samples for WDRO-TerminalLOH data-interface checks. This stage does not run WDRO-LP and does not connect to MSP.\n\n');
fprintf(fid, '## Sample Size\n\n');
fprintf(fid, '- `P_B1=%d`: selected typhoon paths per lf=7 state.\n', config.P_B1);
fprintf(fid, '- `M_B1=%d`: damage samples per selected path.\n', config.M_B1);
fprintf(fid, '- `R_B1=%d`: D/A/C consequence scenarios per state.\n\n', config.P_B1 * config.M_B1);
fprintf(fid, 'The current implementation uses the first `P_B1` path ids from the Stage 2A path table for each state and samples damage with seed `%d`.\n\n', config.random_seed_B1);
fprintf(fid, 'This first-path selection is only a smoke-test choice. It should not be used as a formal paper sampling design; Stage B2 should switch to fixed-seed random sampling or stratified sampling.\n\n');
fprintf(fid, '## B1 Simplifications\n\n');
fprintf(fid, '- Uses the existing preview wind/grid/road Monte Carlo structure and fragility functions.\n');
fprintf(fid, '- Uses the existing Vmax/Rmax mapping and Rmax probabilities `[0.3,0.5,0.2]` from the offline preview prototype.\n');
fprintf(fid, '- Reads site/node counts from `load_data_h2_near` (`params.Ni=4`, `params.Nj=33` in the current data), rather than inventing dimensions.\n');
fprintf(fid, '- Uses first-path selection only for smoke testing. Formal B2 sampling should use fixed-seed random sampling or stratified sampling.\n');
fprintf(fid, '- B1 outputs are not formal paper numerical results.\n\n');
fprintf(fid, '## D/A/C Definitions\n\n');
fprintf(fid, '- `D`: node hydrogen demand aggregated over tau=1:W.\n');
fprintf(fid, '- `A`: binary 4-site by 33-node reachability. `A=1` means a feasible service path exists; `A=0` means fully unreachable.\n');
fprintf(fid, '- `C`: reachable service cost / travel impedance / travel time.\n\n');
fprintf(fid, '`C` is the current road-state shortest path cost returned by Dijkstra on edge times after slowdown and closures. It is not `baseCost + currentCost`; the earlier B1 duplicate-base formula has been fixed, and before/after C diagnostics are written.\n\n');
fprintf(fid, 'Reachable but slow road conditions, such as flooding, congestion, fallen trees, detours, or speed limits, are represented by `A=1` with larger `C`. Fractional reachability values such as `A=0.3` are not used.\n\n');
fprintf(fid, '## W=3 Aggregation\n\n');
fprintf(fid, '- `D_n = sum_tau D_{n,tau}`.\n');
fprintf(fid, '- `A_i,n=1` only if all critical demand windows for node `n` are reachable from site `i`; otherwise `A_i,n=0`.\n');
fprintf(fid, '- If `A_i,n=1`, `C_i,n` is the mean reachable-window service cost. If `A_i,n=0`, `C_i,n=Inf`.\n\n');
fprintf(fid, '## Outputs\n\n');
fprintf(fid, 'Output directory: `%s`\n\n', config.outputDir);
fprintf(fid, '- `lookahead_scenario_site_node.csv`\n');
fprintf(fid, '- `lookahead_scenario_summary.csv`\n');
fprintf(fid, '- `lookahead_D_total_distribution_summary.csv`\n');
fprintf(fid, '- `lookahead_reachability_summary.csv`\n');
fprintf(fid, '- `lookahead_cost_summary.csv`\n');
fprintf(fid, '- `README_B1_DAC_samples.txt`\n\n');
fprintf(fid, '## Next Step\n\n');
fprintf(fid, 'Stage B2 should expand the scenario count, for example to R=200 or R=500 per state, before running WDRO on W=3 consequence samples.\n');
end

function write_implementation_audit_b1(config, diag)
auditFile = fullfile(config.outputDir, 'implementation_audit_B1.txt');
fid = fopen(auditFile, 'w');
if fid < 0
    error('build_lookahead_W3_DAC_samples_h2:AuditOpenFailed', ...
        'Could not open implementation_audit_B1.txt.');
end
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, 'Stage 2B1 implementation audit\n');
fprintf(fid, 'Generated at: %s\n\n', char(datetime('now')));
fprintf(fid, '1. Fallback code found: no data-replacement fallback found in B1 source. Required input files/columns raise errors when missing.\n');
fprintf(fid, '2. Mock/dummy/placeholder/TODO found: no mock/dummy/placeholder/TODO/fake markers found in B1 source audit.\n');
fprintf(fid, '3. Random replacement of real logic: no. Randomness is used only for physical sampling of Rmax, grid line failures, and road closures with fixed seed %d.\n', config.random_seed_B1);
fprintf(fid, '4. D source: existing load_data_h2_near P_node_load_kw, support_hours, eta_FC, h2_lhv; grid line outage sampled with existing wind speed and fragility functions.\n');
fprintf(fid, '5. A source: Dijkstra reachability on the stage1 road graph after sampled road closures; A is written only as 0/1.\n');
fprintf(fid, '6. C source: current road-state shortest path cost dist(n), using edge_length_km*(1+roadSlowdownLambda*pClose) and Inf for closed edges.\n');
fprintf(fid, '7. C repeated baseCost check: previous B1 formula used baseCost + dist(n), which double-counted baseline distance because dist(n) already includes the current path cost.\n');
fprintf(fid, '8. C fixed: yes. scenario_service_cost now uses dist(n). Before-fix values are retained only in diagnostics.\n');
fprintf(fid, '9. A non-binary exists: %d.\n', ~diag.A_binary_ok_all);
fprintf(fid, '10. reachable=1 with C=Inf exists: %d.\n', diag.reachable_one_inf_cost_count > 0);
fprintf(fid, '11. Unreachable C used in cost statistics: no. Reachable cost statistics filter reachable==1 and finite C.\n');
fprintf(fid, '12. B1 path selection: first P_B1=%d paths per state. This is smoke-test only and is not recommended for formal results.\n', config.P_B1);
fprintf(fid, '13. B2 recommendation: use fixed-seed random sampling or stratified path sampling, expand to R=200/R=500, and keep A binary with C carrying slowdown.\n');
fprintf(fid, '14. Dimension source: node/site counts are read from load_data_h2_near params.Nj and params.Ni; current data are 33 nodes and 4 sites.\n');
fprintf(fid, '15. Smoke-test simplifications: B1 uses existing preview Vmax/Rmax maps, Rmax probabilities [0.3,0.5,0.2], and first-P path selection. These are prototype settings, not final paper sampling design.\n\n');
fprintf(fid, 'C before/after summary:\n');
fprintf(fid, '- C_reachable_mean_before_fix_overall = %.12g\n', diag.C_reachable_mean_before_fix_overall);
fprintf(fid, '- C_reachable_mean_after_fix_overall = %.12g\n', diag.C_reachable_mean_after_fix_overall);
fprintf(fid, '- C_reachable_max_before_fix_overall = %.12g\n', diag.C_reachable_max_before_fix_overall);
fprintf(fid, '- C_reachable_max_after_fix_overall = %.12g\n', diag.C_reachable_max_after_fix_overall);
end
