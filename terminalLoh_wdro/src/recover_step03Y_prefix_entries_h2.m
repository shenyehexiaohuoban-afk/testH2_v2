function [entries, context] = recover_step03Y_prefix_entries_h2( ...
        rootDir, stateIds, sampleSizes, continueOnStateFailure, datasetRole)
%RECOVER_STEP03Y_PREFIX_ENTRIES_H2 Deterministically replay frozen prefixes.

if nargin < 4 || isempty(continueOnStateFailure)
    continueOnStateFailure = false;
end
if nargin < 5 || isempty(datasetRole)
    datasetRole = "nominal";
end
datasetRole = string(datasetRole);
validRoles = ["nominal", "validation-1", "validation-2"];
if ~isscalar(datasetRole) || ~ismember(datasetRole, validRoles)
    error('recover_step03Y_prefix_entries_h2:BadDatasetRole', ...
        'datasetRole must be nominal, validation-1, or validation-2.');
end

moduleDir = fullfile(rootDir, 'terminalLoh_wdro');
thisDir = fullfile(moduleDir, 'src');
addpath(rootDir); addpath(thisDir);
addpath(fullfile(rootDir, 'fa_h2', 'fuzhu', 'terminalLoh_windmc'));

rowsPerState = 15000;
windSeedOffset = 330000000;
demandToleranceKg = 1e-10;
config = build_config(rootDir, moduleDir, datasetRole);

nominalOptions = detectImportOptions(config.nominalCsv);
nominalOptions = setvartype(nominalOptions, 'initial_state', 'string');
nominal = readtable(config.nominalCsv, nominalOptions);
mainSample = readtable(config.mainSampleFile);
seedMap = readtable(config.seedMapFile, 'TextType', 'string');
seedMap = seedMap(seedMap.dataset_role == datasetRole & ...
    ismember(double(seedMap.initial_state_id), stateIds), :);
baseSeeds = unique(double(seedMap.base_joint_seed));
if numel(baseSeeds) ~= 1
    error('recover_step03Y_prefix_entries_h2:SeedMap', ...
        'Frozen dataset role does not map to one base seed.');
end
baseSeed = baseSeeds(1);
windConfig = load_formal_b3_wind_config_h2(config.formalWindConfigFile);
rawNear = load(config.nearInputFile, 'NearStageInput');
near = rawNear.NearStageInput;
model = build_replay_model(config, near);

entries = repmat(struct('R', NaN, 'identity', table(), ...
    'Dagg', [], 'Aagg', [], 'Cagg', [], 'Dperiod', [], ...
    'Aperiod', [], 'Cperiod', [], 'audit', struct()), ...
    numel(sampleSizes), 1);
for kk = 1:numel(sampleSizes)
    R = sampleSizes(kk);
    combined = [];
    combinedAuditRows = cell(numel(stateIds), 4);
    for ss = 1:numel(stateIds)
        stateId = stateIds(ss);
        meta = nominal(double(nominal.initial_state_id) == stateId, :);
        meta = sortrows(meta, 'scenario_id_in_state');
        if height(meta) ~= rowsPerState || ...
                ~isequal(double(meta.scenario_id_in_state(1:R)), (1:R).')
            if ~continueOnStateFailure
                error('recover_step03Y_prefix_entries_h2:BadPrefix', ...
                    'Nominal scenario IDs are not the required 1:R prefix.');
            end
            request = make_request_from_meta(meta, stateId, R, rowsPerState);
            recovered = failed_recovered(request, model, ...
                "Nominal scenario IDs are not the required 1:R prefix.");
            audit = failed_audit(stateId, recovered.identity.replay_failure_message(1));
            [combined, combinedAuditRows] = append_state_recovery( ...
                combined, combinedAuditRows, ss, recovered, audit, stateId);
            continue;
        end
        request = make_request_from_meta(meta, stateId, R, rowsPerState);
        try
            [recovered, audit] = recover_once(request, nominal, mainSample, ...
                seedMap, windConfig, model, config, baseSeed, windSeedOffset, ...
                rowsPerState, demandToleranceKg);
            recovered.identity.replay_state_pass = true(R, 1);
            recovered.identity.replay_failure_message = strings(R, 1);
        catch exception
            if ~continueOnStateFailure
                rethrow(exception);
            end
            recovered = failed_recovered(request, model, string(exception.message));
            audit = failed_audit(stateId, string(exception.message));
        end
        [combined, combinedAuditRows] = append_state_recovery( ...
            combined, combinedAuditRows, ss, recovered, audit, stateId);
    end
    stateAudit = cell2table(combinedAuditRows, 'VariableNames', ...
        {'initial_state_id', 'passed', 'max_DAC_error', 'failure_message'});
    audit = struct('all_final_DAC_exact', all(stateAudit.passed), ...
        'max_DAC_error', max(stateAudit.max_DAC_error), ...
        'all_stream_hashes_match', all(stateAudit.passed), ...
        'stream_match_count', sum(stateAudit.passed), ...
        'state_audit', stateAudit);
    entries(kk).R = R;
    entries(kk).identity = combined.identity;
    entries(kk).Dagg = combined.Dagg;
    entries(kk).Aagg = combined.Aagg;
    entries(kk).Cagg = combined.Cagg;
    entries(kk).Dperiod = combined.Dperiod;
    entries(kk).Aperiod = combined.Aperiod;
    entries(kk).Cperiod = combined.Cperiod;
    entries(kk).audit = audit;
end

if isfield(near.Cost, 'reserve_shortage_penalty_yuan_per_kg')
    M = double(near.Cost.reserve_shortage_penalty_yuan_per_kg);
elseif isfield(near.Cost, 'cost_reserve_shortage')
    M = double(near.Cost.cost_reserve_shortage);
else
    error('recover_step03Y_prefix_entries_h2:MissingPenalty', ...
        'Cannot trace the shortage penalty.');
end

function request = make_request_from_meta(meta, stateId, R, rowsPerState)
requestRows = cell(R, 4);
availableRows = min(height(meta), R);
for rr = 1:R
    if rr <= availableRows
        scenarioId = double(meta.scenario_id_in_state(rr));
        pathId = double(meta.path_id(rr));
        if ismember('sample_weight', meta.Properties.VariableNames)
            nominalWeight = double(meta.sample_weight(rr));
        else
            nominalWeight = 1 / rowsPerState;
        end
    else
        scenarioId = rr;
        pathId = NaN;
        nominalWeight = 1 / rowsPerState;
    end
    requestRows(rr, :) = {stateId, scenarioId, pathId, nominalWeight};
end
request = cell2table(requestRows, 'VariableNames', ...
    {'initial_state_id', 'scenario_id', 'path_id', 'frozen_nominal_weight'});
end

function recovered = failed_recovered(request, model, message)
R = height(request);
identity = request;
identity.joint_stream_position = NaN(R, 1);
identity.wind_seed = NaN(R, 1);
identity.resistance_seed = NaN(R, 1);
identity.final_D_exact = false(R, 1);
identity.final_A_exact = false(R, 1);
identity.final_C_exact = false(R, 1);
identity.max_DAC_error = inf(R, 1);
identity.replay_state_pass = false(R, 1);
identity.replay_failure_message = repmat(string(message), R, 1);
recovered = struct('identity', identity, ...
    'Dperiod', NaN(R, 3, model.nNodes), ...
    'Aperiod', false(R, 3, model.nSites, model.nNodes), ...
    'Cperiod', NaN(R, 3, model.nSites, model.nNodes), ...
    'Dagg', NaN(R, model.nNodes), ...
    'Aagg', false(R, model.nSites, model.nNodes), ...
    'Cagg', NaN(R, model.nSites, model.nNodes));
end

function audit = failed_audit(stateId, message)
audit = struct('all_final_DAC_exact', false, 'max_DAC_error', Inf, ...
    'all_stream_hashes_match', false, 'stream_match_count', 0, ...
    'state_audit', table(stateId, false, Inf, string(message), ...
    'VariableNames', {'initial_state_id', 'passed', ...
    'max_DAC_error', 'failure_message'}));
end

function [combined, auditRows] = append_state_recovery( ...
        combined, auditRows, auditIndex, recovered, audit, stateId)
if isempty(combined)
    combined = recovered;
else
    combined.identity = [combined.identity; recovered.identity];
    combined.Dperiod = cat(1, combined.Dperiod, recovered.Dperiod);
    combined.Aperiod = cat(1, combined.Aperiod, recovered.Aperiod);
    combined.Cperiod = cat(1, combined.Cperiod, recovered.Cperiod);
    combined.Dagg = cat(1, combined.Dagg, recovered.Dagg);
    combined.Aagg = cat(1, combined.Aagg, recovered.Aagg);
    combined.Cagg = cat(1, combined.Cagg, recovered.Cagg);
end
if isfield(audit, 'state_audit')
    stateRow = audit.state_audit(1, :);
    auditRows(auditIndex, :) = {stateId, logical(stateRow.passed), ...
        double(stateRow.max_DAC_error), string(stateRow.failure_message)};
else
    auditRows(auditIndex, :) = {stateId, ...
        audit.all_final_DAC_exact && audit.all_stream_hashes_match, ...
        audit.max_DAC_error, ""};
end
end
context = struct('Cap', double(near.HydrogenDevice.tank_cap_kg(:)), ...
    'M', M, 'gamma', 0.001 * M, 'rowsPerState', rowsPerState, ...
    'config', config, 'nSites', model.nSites, 'nNodes', model.nNodes);
end

function [recovered, audit] = recover_once(request, nominal, mainSample, ...
        seedMap, windConfig, model, config, baseSeed, windSeedOffset, ...
        rowsPerState, demandToleranceKg)
R = height(request);
Dperiod = zeros(R, 3, model.nNodes);
Aperiod = false(R, 3, model.nSites, model.nNodes);
Cperiod = inf(R, 3, model.nSites, model.nNodes);
DaggAll = zeros(R, model.nNodes);
AaggAll = false(R, model.nSites, model.nNodes);
CaggAll = inf(R, model.nSites, model.nNodes);
identity = request;
identity.joint_stream_position = zeros(R, 1);
identity.wind_seed = zeros(R, 1);
identity.resistance_seed = zeros(R, 1);
identity.final_D_exact = false(R, 1);
identity.final_A_exact = false(R, 1);
identity.final_C_exact = false(R, 1);
identity.max_DAC_error = inf(R, 1);
streamMatches = 0;
sidecar = matfile(config.nominalMat);
states = unique(request.initial_state_id);

for ss = 1:numel(states)
    stateId = states(ss);
    meta = nominal(double(nominal.initial_state_id) == stateId, :);
    if height(meta) ~= rowsPerState
        error('recover_step03Y_prefix_entries_h2:NominalBlock', ...
            'Nominal state block does not contain 15000 rows.');
    end
    a0 = double(meta.a0(1));
    loc0 = double(meta.loc0(1));
    lfw0 = double(meta.lfw0(1));
    stateSample = mainSample(double(mainSample.a0) == a0 & ...
        double(mainSample.loc0) == loc0 & ...
        double(mainSample.lfw0) == lfw0, :);
    if height(stateSample) ~= rowsPerState
        error('recover_step03Y_prefix_entries_h2:MainSampleBlock', ...
            'Main-sample state block does not contain 15000 rows.');
    end

    resistanceSeed = baseSeed + 100003 * stateId;
    rng(resistanceSeed, 'twister');
    permutation = randperm(rowsPerState).';
    lineU = rand(rowsPerState, model.nLines);
    roadU = rand(rowsPerState, model.nRoads);
    selected = stateSample(permutation, :);
    windSeed = windSeedOffset + baseSeed + 100019 * stateId;
    stream = RandStream('mt19937ar', 'Seed', windSeed);
    qAll = rand(stream, rowsPerState, 3);
    seedRow = seedMap(double(seedMap.initial_state_id) == stateId, :);
    streamPass = height(seedRow) == 1 && ...
        sha256_uint32(permutation) == string(seedRow.step3i_permutation_sha256) && ...
        sha256_double(qAll(:, 1)) == string(seedRow.q_W1_sha256) && ...
        sha256_double(qAll(:, 2)) == string(seedRow.q_W2_sha256) && ...
        sha256_double(qAll(:, 3)) == string(seedRow.q_W3_sha256);
    if ~streamPass
        error('recover_step03Y_prefix_entries_h2:StreamMismatch', ...
            'Frozen random-stream hashes do not match Step-03J.');
    end
    streamMatches = streamMatches + 1;

    localRows = find(request.initial_state_id == stateId);
    for jj = 1:numel(localRows)
        outRow = localRows(jj);
        scenarioId = request.scenario_id(outRow);
        row = meta(double(meta.scenario_id_in_state) == scenarioId, :);
        if height(row) ~= 1 || double(row.path_id) ~= request.path_id(outRow)
            error('recover_step03Y_prefix_entries_h2:IdentityMismatch', ...
                'Frozen scenario/path identity mismatch.');
        end
        pos = double(row.joint_stream_position);
        sample = selected(pos, :);
        if double(sample.path_id) ~= request.path_id(outRow)
            error('recover_step03Y_prefix_entries_h2:StreamMapping', ...
                'Frozen joint-stream path mapping mismatch.');
        end

        aStage = double([sample.a_W1, sample.a_W2, sample.a_W3]);
        locStage = double([sample.loc_W1, sample.loc_W2, sample.loc_W3]);
        lfwStage = double([sample.lfw_W1, sample.lfw_W2, sample.lfw_W3]);
        pFail = cell(3, 1);
        pClose = cell(3, 1);
        for tau = 1:3
            vmax = triangular_by_level(aStage(tau), qAll(pos, tau), ...
                windConfig.randomLower, windConfig.randomMode, ...
                windConfig.randomUpper);
            idx = state_index(model, aStage(tau), locStage(tau), ...
                lfwStage(tau));
            pFail{tau} = compute_line_failure_prob_h2( ...
                model.lineFactor(idx, :) .* vmax, model.designWindSpeedVN);
            pClose{tau} = compute_line_failure_prob_h2( ...
                model.roadFactor(idx, :) .* vmax, model.roadDesignWindVN);
        end

        failed = false(3, model.nLines);
        closed = false(3, model.nRoads);
        slow = zeros(3, model.nRoads);
        failed(1, :) = lineU(pos, :) <= pFail{1};
        failed(2, :) = failed(1, :) | lineU(pos, :) <= pFail{2};
        failed(3, :) = failed(2, :) | lineU(pos, :) <= pFail{3};
        closed(1, :) = roadU(pos, :) <= pClose{1};
        closed(2, :) = closed(1, :) | roadU(pos, :) <= pClose{2};
        closed(3, :) = closed(2, :) | roadU(pos, :) <= pClose{3};
        slow(1, :) = pClose{1};
        slow(2, :) = max(slow(1, :), pClose{2});
        slow(3, :) = max(slow(2, :), pClose{3});

        outage = false(3, model.nNodes);
        for tau = 1:3
            outage(tau, :) = double(failed(tau, :)) * ...
                model.nodePathIncidence.' > 0;
            outage(tau, model.sourceNode) = false;
        end
        Dtau = double(outage) .* model.Pnode_kW.' * model.DFactorKgPerKWh;
        reachTau = false(3, model.nSites, model.nNodes);
        costTau = inf(3, model.nSites, model.nNodes);
        for tau = 1:3
            edgeCost = model.roadLength .* (1 + slow(tau, :).');
            edgeCost(closed(tau, :).') = Inf;
            [reach, cost] = road_state(model.nNodes, model.roadFrom, ...
                model.roadTo, edgeCost, model.siteNodes);
            reachTau(tau, :, :) = reach;
            costTau(tau, :, :) = cost;
        end

        Dagg = sum(Dtau, 1);
        Aagg = false(model.nSites, model.nNodes);
        Cagg = inf(model.nSites, model.nNodes);
        for node = 1:model.nNodes
            critical = find(Dtau(:, node) > demandToleranceKg);
            if isempty(critical)
                critical = (1:3).';
            end
            for site = 1:model.nSites
                reach = squeeze(reachTau(critical, site, node));
                if all(reach)
                    Aagg(site, node) = true;
                    Cagg(site, node) = mean(squeeze( ...
                        costTau(critical, site, node)));
                end
            end
        end

        globalRow = (stateId - 1) * rowsPerState + scenarioId;
        Dnom = double(sidecar.D_node_kg(globalRow, :));
        Anom = logical(squeeze(sidecar.A_site_node(globalRow, :, :)));
        Cnom = double(squeeze(sidecar.C_site_node_km(globalRow, :, :)));
        dExact = isequal(Dagg, Dnom);
        aExact = isequal(Aagg, Anom);
        cExact = isequaln(Cagg, Cnom);
        finiteBoth = isfinite(Cagg) & isfinite(Cnom);
        cError = 0;
        if any(finiteBoth, 'all')
            cError = max(abs(Cagg(finiteBoth) - Cnom(finiteBoth)));
        end

        Dperiod(outRow, :, :) = Dtau;
        Aperiod(outRow, :, :, :) = reachTau;
        Cperiod(outRow, :, :, :) = costTau;
        DaggAll(outRow, :) = Dagg;
        AaggAll(outRow, :, :) = Aagg;
        CaggAll(outRow, :, :) = Cagg;
        identity.joint_stream_position(outRow) = pos;
        identity.wind_seed(outRow) = windSeed;
        identity.resistance_seed(outRow) = resistanceSeed;
        identity.final_D_exact(outRow) = dExact;
        identity.final_A_exact(outRow) = aExact;
        identity.final_C_exact(outRow) = cExact;
        identity.max_DAC_error(outRow) = max([max(abs(Dagg - Dnom)), ...
            cError, double(sum(Aagg ~= Anom, 'all')), ...
            double(sum(isinf(Cagg) ~= isinf(Cnom), 'all'))]);
        if ~(dExact && aExact && cExact)
            error('recover_step03Y_prefix_entries_h2:DACMismatch', ...
                'Deterministically replayed aggregate D/A/C differs from nominal.');
        end
    end
end

recovered = struct('identity', identity, 'Dperiod', Dperiod, ...
    'Aperiod', Aperiod, 'Cperiod', Cperiod, 'Dagg', DaggAll, ...
    'Aagg', AaggAll, 'Cagg', CaggAll);
audit = struct('all_final_DAC_exact', ...
    all(identity.final_D_exact & identity.final_A_exact & ...
    identity.final_C_exact), 'max_DAC_error', max(identity.max_DAC_error), ...
    'all_stream_hashes_match', streamMatches == numel(states), ...
    'stream_match_count', streamMatches);
end

function config = build_config(rootDir, moduleDir, datasetRole)
config.mainSampleFile = fullfile(moduleDir, 'output', ...
    'stage2a2_W3_path_sampling', 'run-002', 'main_path_samples.csv');
if datasetRole == "nominal"
    csvName = 'wdro_nominal_input.csv';
    matName = 'wdro_nominal_input_DAC.mat';
elseif datasetRole == "validation-1"
    csvName = 'wdro_validation_1.csv';
    matName = 'wdro_validation_1_DAC.mat';
else
    csvName = 'wdro_validation_2.csv';
    matName = 'wdro_validation_2_DAC.mat';
end
config.nominalCsv = fullfile(moduleDir, 'output', ...
    'stage3j_wdro_input_freeze', 'run-001', csvName);
config.nominalMat = fullfile(moduleDir, 'output', ...
    'stage3j_wdro_input_freeze', 'run-001', matName);
config.seedMapFile = fullfile(moduleDir, 'output', ...
    'stage3j_wdro_input_freeze', 'run-001', 'dataset_role_and_seed_map.csv');
config.nearInputFile = fullfile(rootDir, 'data', 'yuanqi', ...
    'near_stage_msp_input.mat');
config.formalWindConfigFile = fullfile(moduleDir, 'config', ...
    'formal_b3_wind_modes.csv');
config.warningSolutionFile = fullfile(moduleDir, 'output', ...
    'stage2_foundation_warning100_Rmax30_40_50_Wstep_sweep', ...
    'warning_y_base_solution.csv');
config.locCoordinateFile = fullfile(moduleDir, 'output', ...
    'stage2_foundation_audit', 'loc_lf_coordinate_table.csv');
config.roadEdgeFile = fullfile(rootDir, 'data', 'yuanqi', ...
    'stage1_road_edges.csv');
config.siteNodeFile = fullfile(rootDir, 'data', 'yuanqi', ...
    'stage1_site_nodes.csv');
config.Rmax = 40;
config.Wstep = 40;
config.windDecayB = 0.6;
config.designWindSpeedVN = 25;
config.roadDesignWindVN = 30;
config.sourceNode = 1;
end

function model = build_replay_model(config, near)
warning = readtable(config.warningSolutionFile);
yBase = double(warning.y_base(1));
locRaw = readtable(config.locCoordinateFile);
locTable = sortrows(unique(locRaw(:, {'loc', 'x_coord'}), ...
    'rows', 'stable'), 'loc');
layout = build_h2_spatial_layout_preview(near);
nodes = sortrows(layout.nodes, 'node_id');
lines = sortrows(layout.lines, 'line_id');
grid = table(lines.line_id, lines.source_edge_id, lines.from_node, ...
    lines.to_node, nodes.x_km(lines.from_node), ...
    nodes.y_km(lines.from_node), nodes.x_km(lines.to_node), ...
    nodes.y_km(lines.to_node), 'VariableNames', {'line_id', ...
    'source_edge_id', 'from_node', 'to_node', 'x1', 'y1', 'x2', 'y2'});
roadRaw = readtable(config.roadEdgeFile);
road = table(double(roadRaw.road_edge_id), double(roadRaw.from_node), ...
    double(roadRaw.to_node), nodes.x_km(double(roadRaw.from_node)), ...
    nodes.y_km(double(roadRaw.from_node)), ...
    nodes.x_km(double(roadRaw.to_node)), ...
    nodes.y_km(double(roadRaw.to_node)), 'VariableNames', ...
    {'road_edge_id', 'from_node', 'to_node', 'x1', 'y1', 'x2', 'y2'});
site = sortrows(readtable(config.siteNodeFile), 'site_id');
Pnode = double(near.Grid.P_load_base_kw(:));
eta = double(near.HydrogenDevice.eta_FC);
lhv = double(near.HydrogenDevice.h2_lhv_kWh_per_kg);
locValues = sort(double(locTable.loc));
lineFactor = zeros(6 * numel(locValues) * 4, height(grid));
roadFactor = zeros(6 * numel(locValues) * 4, height(road));
stateIndex = zeros(6, numel(locValues), 4);
row = 0;
for a = 1:6
    for loc = locValues(:).'
        locRow = locTable(locTable.loc == loc, :);
        for lfw = 0:3
            row = row + 1;
            x = double(locRow.x_coord);
            y = yBase + lfw * config.Wstep;
            lineDistance = compute_point_to_segment_distance_h2( ...
                x, y, grid.x1, grid.y1, grid.x2, grid.y2);
            roadDistance = compute_point_to_segment_distance_h2( ...
                x, y, road.x1, road.y1, road.x2, road.y2);
            lineFactor(row, :) = compute_wind_speed_radial_h2( ...
                lineDistance, 1, config.Rmax, config.windDecayB).';
            roadFactor(row, :) = compute_wind_speed_radial_h2( ...
                roadDistance, 1, config.Rmax, config.windDecayB).';
            stateIndex(a, loc - min(locValues) + 1, lfw + 1) = row;
        end
    end
end
model = struct('lineFactor', lineFactor, 'roadFactor', roadFactor, ...
    'stateIndex', stateIndex, 'locMin', min(locValues), ...
    'nLines', height(grid), 'nRoads', height(road), ...
    'nNodes', numel(Pnode), 'nSites', height(site), ...
    'sourceNode', config.sourceNode, 'Pnode_kW', Pnode, ...
    'nodePathIncidence', radial_node_path_incidence(numel(Pnode), ...
    grid.from_node, grid.to_node, config.sourceNode), ...
    'roadFrom', double(road.from_node), 'roadTo', double(road.to_node), ...
    'roadLength', hypot(road.x2 - road.x1, road.y2 - road.y1), ...
    'siteNodes', double(site.grid_node), ...
    'DFactorKgPerKWh', 1 / (eta * lhv), ...
    'designWindSpeedVN', config.designWindSpeedVN, ...
    'roadDesignWindVN', config.roadDesignWindVN);
end

function incidence = radial_node_path_incidence( ...
        nNodes, fromNode, toNode, sourceNode)
nLines = numel(fromNode);
adj = cell(nNodes, 1);
edgeAdj = cell(nNodes, 1);
for line = 1:nLines
    i = fromNode(line);
    j = toNode(line);
    adj{i}(end + 1) = j;
    edgeAdj{i}(end + 1) = line;
    adj{j}(end + 1) = i;
    edgeAdj{j}(end + 1) = line;
end
parent = zeros(nNodes, 1);
parentEdge = zeros(nNodes, 1);
visited = false(nNodes, 1);
queue = zeros(nNodes, 1);
head = 1;
tail = 1;
queue(1) = sourceNode;
visited(sourceNode) = true;
while head <= tail
    u = queue(head);
    head = head + 1;
    for kk = 1:numel(adj{u})
        v = adj{u}(kk);
        if visited(v)
            continue;
        end
        visited(v) = true;
        parent(v) = u;
        parentEdge(v) = edgeAdj{u}(kk);
        tail = tail + 1;
        queue(tail) = v;
    end
end
incidence = false(nNodes, nLines);
for node = 1:nNodes
    current = node;
    while current ~= sourceNode
        incidence(node, parentEdge(current)) = true;
        current = parent(current);
    end
end
end

function idx = state_index(model, a, loc, lfw)
idx = model.stateIndex(sub2ind(size(model.stateIndex), ...
    a, loc - model.locMin + 1, lfw + 1));
if idx <= 0
    error('recover_step03Y_prefix_entries_h2:MissingState', ...
        'Replay state index is missing.');
end
end

function vmax = triangular_by_level(a, q, lower, mode, upper)
if a == 1
    vmax = 0;
    return;
end
lo = lower(a);
mid = mode(a);
hi = upper(a);
split = (mid - lo) / (hi - lo);
if q <= split
    vmax = lo + sqrt(q * (hi - lo) * (mid - lo));
else
    vmax = hi - sqrt((1 - q) * (hi - lo) * (hi - mid));
end
end

function [reach, cost] = road_state( ...
        nNodes, fromNode, toNode, edgeCost, sources)
adjacency = inf(nNodes);
adjacency(1:nNodes + 1:end) = 0;
for edge = 1:numel(edgeCost)
    if ~isfinite(edgeCost(edge))
        continue;
    end
    i = fromNode(edge);
    j = toNode(edge);
    if edgeCost(edge) < adjacency(i, j)
        adjacency(i, j) = edgeCost(edge);
        adjacency(j, i) = edgeCost(edge);
    end
end
reach = false(numel(sources), nNodes);
cost = inf(numel(sources), nNodes);
for site = 1:numel(sources)
    distance = inf(1, nNodes);
    visited = false(1, nNodes);
    distance(sources(site)) = 0;
    for iteration = 1:nNodes
        candidate = distance;
        candidate(visited) = Inf;
        [best, node] = min(candidate);
        if ~isfinite(best)
            break;
        end
        visited(node) = true;
        distance = min(distance, best + adjacency(node, :));
    end
    reach(site, :) = isfinite(distance);
    cost(site, :) = distance;
end
end

function hash = sha256_uint32(values)
md = java.security.MessageDigest.getInstance('SHA-256');
bytes = typecast(uint32(values(:)), 'uint8');
md.update(typecast(bytes, 'int8'));
digest = typecast(md.digest(), 'uint8');
hash = lower(string(reshape(dec2hex(digest, 2).', 1, [])));
end

function hash = sha256_double(values)
md = java.security.MessageDigest.getInstance('SHA-256');
bytes = typecast(double(values(:)), 'uint8');
md.update(typecast(bytes, 'int8'));
digest = typecast(md.digest(), 'uint8');
hash = lower(string(reshape(dec2hex(digest, 2).', 1, [])));
end
