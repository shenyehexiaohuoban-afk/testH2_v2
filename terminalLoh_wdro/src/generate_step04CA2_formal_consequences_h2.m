function out = generate_step04CA2_formal_consequences_h2(rootDir, identity)
%GENERATE_STEP04CA2_FORMAL_CONSEQUENCES_H2 Freeze/replay formal consequences.
%
% identity must contain the exact physical path, independent wind and
% resistance stream identities, and one of two resistance stream rules:
%   namespace_direct_position  - Step-04C-A2 support-out namespace;
%   nominal_after_permutation  - exact Step-03J nominal replay semantics.

required = {'a0','loc0','lfw0','a1','loc1','lfw1','a2','loc2','lfw2', ...
    'a3','loc3','lfw3','wind_seed','resistance_seed', ...
    'wind_stream_position','resistance_stream_position','resistance_stream_rule'};
for ii = 1:numel(required)
    if ~ismember(required{ii}, identity.Properties.VariableNames)
        error('generate_step04CA2_formal_consequences_h2:MissingField', ...
            'Identity table is missing %s.', required{ii});
    end
end

thisDir = fileparts(mfilename('fullpath'));
moduleDir = fileparts(thisDir);
addpath(rootDir); addpath(thisDir);
addpath(fullfile(rootDir, 'fa_h2', 'fuzhu', 'terminalLoh_windmc'));
config = build_config(rootDir, moduleDir);
windConfig = load_formal_b3_wind_config_h2(config.formalWindConfigFile);
if windConfig.defaultMode ~= "stagewise_random_triangular"
    error('Formal wind mode is not stagewise_random_triangular.');
end
nearRaw = load(config.nearInputFile, 'NearStageInput');
model = build_model(config, nearRaw.NearStageInput);

R = height(identity); K = 3; I = model.nSites; N = model.nNodes;
Dperiod = zeros(R, K, N);
Aperiod = false(R, K, I, N);
Cperiod = inf(R, K, I, N);
failedLine = false(R, K, model.nLines);
closedRoad = false(R, K, model.nRoads);
wind = zeros(R, K); windQ = zeros(R, K);
lineUUsed = zeros(R, model.nLines); roadUUsed = zeros(R, model.nRoads);

rules = unique(string(identity.resistance_stream_rule));
if any(~ismember(rules, ["namespace_direct_position", "nominal_after_permutation"]))
    error('Unsupported resistance stream rule.');
end
groups = findgroups(double(identity.wind_seed), double(identity.resistance_seed), ...
    string(identity.resistance_stream_rule));
for gg = 1:max(groups)
    rows = find(groups == gg);
    windSeed = double(identity.wind_seed(rows(1)));
    resistanceSeed = double(identity.resistance_seed(rows(1)));
    rule = string(identity.resistance_stream_rule(rows(1)));
    maxWindPos = max(double(identity.wind_stream_position(rows)));
    maxResistancePos = max(double(identity.resistance_stream_position(rows)));
    if rule == "nominal_after_permutation"
        streamRows = 15000;
        if maxWindPos > streamRows || maxResistancePos > streamRows
            error('Nominal stream position exceeds 15000.');
        end
    else
        streamRows = max(maxWindPos, maxResistancePos);
    end

    windStream = RandStream('mt19937ar', 'Seed', windSeed);
    qAll = rand(windStream, streamRows, 3);
    previousRng = rng;
    cleanupRng = onCleanup(@() rng(previousRng)); %#ok<NASGU>
    rng(resistanceSeed, 'twister');
    if rule == "nominal_after_permutation"
        randperm(streamRows); %#ok<RANDPERM> exact Step-03J stream consumption
    end
    lineU = rand(streamRows, model.nLines);
    roadU = rand(streamRows, model.nRoads);
    rng(previousRng);
    clear cleanupRng;

    for jj = 1:numel(rows)
        rr = rows(jj);
        wp = double(identity.wind_stream_position(rr));
        rp = double(identity.resistance_stream_position(rr));
        q = qAll(wp, :);
        lineDraw = lineU(rp, :); roadDraw = roadU(rp, :);
        windQ(rr, :) = q; lineUUsed(rr, :) = lineDraw; roadUUsed(rr, :) = roadDraw;
        aStage = double([identity.a1(rr), identity.a2(rr), identity.a3(rr)]);
        locStage = double([identity.loc1(rr), identity.loc2(rr), identity.loc3(rr)]);
        lfwStage = double([identity.lfw1(rr), identity.lfw2(rr), identity.lfw3(rr)]);
        pFail = cell(3, 1); pClose = cell(3, 1);
        for tau = 1:3
            wind(rr, tau) = triangular_by_level(aStage(tau), q(tau), ...
                windConfig.randomLower, windConfig.randomMode, windConfig.randomUpper);
            idx = state_index(model, aStage(tau), locStage(tau), lfwStage(tau));
            pFail{tau} = compute_line_failure_prob_h2( ...
                model.lineFactor(idx, :) .* wind(rr, tau), model.designWindSpeedVN);
            pClose{tau} = compute_line_failure_prob_h2( ...
                model.roadFactor(idx, :) .* wind(rr, tau), model.roadDesignWindVN);
        end

        failed = false(3, model.nLines); closed = false(3, model.nRoads);
        slow = zeros(3, model.nRoads);
        failed(1, :) = lineDraw <= pFail{1};
        failed(2, :) = failed(1, :) | lineDraw <= pFail{2};
        failed(3, :) = failed(2, :) | lineDraw <= pFail{3};
        closed(1, :) = roadDraw <= pClose{1};
        closed(2, :) = closed(1, :) | roadDraw <= pClose{2};
        closed(3, :) = closed(2, :) | roadDraw <= pClose{3};
        slow(1, :) = pClose{1};
        slow(2, :) = max(slow(1, :), pClose{2});
        slow(3, :) = max(slow(2, :), pClose{3});
        failedLine(rr, :, :) = failed; closedRoad(rr, :, :) = closed;

        outage = false(3, N);
        for tau = 1:3
            outage(tau, :) = double(failed(tau, :)) * model.nodePathIncidence.' > 0;
            outage(tau, model.sourceNode) = false;
        end
        Dtau = double(outage) .* model.Pnode_kW.' * model.DFactorKgPerKWh;
        reachTau = false(3, I, N); costTau = inf(3, I, N);
        for tau = 1:3
            edgeCost = model.roadLength .* (1 + slow(tau, :).');
            edgeCost(closed(tau, :).') = Inf;
            [reach, cost] = road_state(N, model.roadFrom, model.roadTo, ...
                edgeCost, model.siteNodes);
            reachTau(tau, :, :) = reach; costTau(tau, :, :) = cost;
        end
        Dperiod(rr, :, :) = Dtau;
        Aperiod(rr, :, :, :) = reachTau;
        Cperiod(rr, :, :, :) = costTau;
    end
end

scenarioHash = strings(R, 1); damageHash = strings(R, 1);
for rr = 1:R
    scenarioHash(rr) = hash_scenario(squeeze(Dperiod(rr, :, :)), ...
        squeeze(Aperiod(rr, :, :, :)), squeeze(Cperiod(rr, :, :, :)), ...
        squeeze(failedLine(rr, :, :)), squeeze(closedRoad(rr, :, :)), wind(rr, :));
    damageHash(rr) = hash_damage(squeeze(failedLine(rr, :, :)), ...
        squeeze(closedRoad(rr, :, :)));
end

out = struct(); out.identity = identity;
out.Dperiod = Dperiod; out.Aperiod = Aperiod; out.Cperiod = Cperiod;
out.failed_line = failedLine; out.closed_road = closedRoad;
out.wind_mps = wind; out.wind_q = windQ;
out.line_resistance_u = lineUUsed; out.road_resistance_u = roadUUsed;
out.scenario_sha256 = scenarioHash; out.damage_sha256 = damageHash;
out.full_D_sha256 = sha256_double(Dperiod);
out.full_A_sha256 = sha256_uint8(uint8(Aperiod));
out.full_C_sha256 = sha256_double(Cperiod);
out.full_failed_line_sha256 = sha256_uint8(uint8(failedLine));
out.full_closed_road_sha256 = sha256_uint8(uint8(closedRoad));
out.full_wind_sha256 = sha256_double(wind);
out.model = rmfield(model, {'lineFactor','roadFactor','nodePathIncidence'});
end

function config = build_config(rootDir, moduleDir)
config.nearInputFile = fullfile(rootDir, 'data', 'yuanqi', 'near_stage_msp_input.mat');
config.formalWindConfigFile = fullfile(moduleDir, 'config', 'formal_b3_wind_modes.csv');
config.warningSolutionFile = fullfile(moduleDir, 'output', ...
    'stage2_foundation_warning100_Rmax30_40_50_Wstep_sweep', 'warning_y_base_solution.csv');
config.locCoordinateFile = fullfile(moduleDir, 'output', ...
    'stage2_foundation_audit', 'loc_lf_coordinate_table.csv');
config.roadEdgeFile = fullfile(rootDir, 'data', 'yuanqi', 'stage1_road_edges.csv');
config.siteNodeFile = fullfile(rootDir, 'data', 'yuanqi', 'stage1_site_nodes.csv');
config.Rmax = 40; config.Wstep = 40; config.windDecayB = 0.6;
config.designWindSpeedVN = 25; config.roadDesignWindVN = 30; config.sourceNode = 1;
end

function model = build_model(config, near)
warning = readtable(config.warningSolutionFile); yBase = double(warning.y_base(1));
locRaw = readtable(config.locCoordinateFile);
locTable = sortrows(unique(locRaw(:, {'loc','x_coord'}), 'rows', 'stable'), 'loc');
layout = build_h2_spatial_layout_preview(near);
nodes = sortrows(layout.nodes, 'node_id'); lines = sortrows(layout.lines, 'line_id');
grid = table(lines.line_id, lines.from_node, lines.to_node, ...
    nodes.x_km(lines.from_node), nodes.y_km(lines.from_node), ...
    nodes.x_km(lines.to_node), nodes.y_km(lines.to_node), ...
    'VariableNames', {'line_id','from_node','to_node','x1','y1','x2','y2'});
roadRaw = readtable(config.roadEdgeFile);
road = table(double(roadRaw.road_edge_id), double(roadRaw.from_node), ...
    double(roadRaw.to_node), nodes.x_km(double(roadRaw.from_node)), ...
    nodes.y_km(double(roadRaw.from_node)), nodes.x_km(double(roadRaw.to_node)), ...
    nodes.y_km(double(roadRaw.to_node)), 'VariableNames', ...
    {'road_edge_id','from_node','to_node','x1','y1','x2','y2'});
site = sortrows(readtable(config.siteNodeFile), 'site_id');
Pnode = double(near.Grid.P_load_base_kw(:));
eta = double(near.HydrogenDevice.eta_FC); lhv = double(near.HydrogenDevice.h2_lhv_kWh_per_kg);
locValues = sort(double(locTable.loc));
lineFactor = zeros(6 * numel(locValues) * 4, height(grid));
roadFactor = zeros(6 * numel(locValues) * 4, height(road));
stateIndex = zeros(6, numel(locValues), 4); row = 0;
for a = 1:6
    for loc = locValues(:).'
        locRow = locTable(locTable.loc == loc, :);
        for lfw = 0:3
            row = row + 1; x = double(locRow.x_coord); y = yBase + lfw * config.Wstep;
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
    'nLines', height(grid), 'nRoads', height(road), 'nNodes', numel(Pnode), ...
    'nSites', height(site), 'sourceNode', config.sourceNode, 'Pnode_kW', Pnode, ...
    'nodePathIncidence', radial_node_path_incidence(numel(Pnode), ...
    grid.from_node, grid.to_node, config.sourceNode), ...
    'roadFrom', double(road.from_node), 'roadTo', double(road.to_node), ...
    'roadLength', hypot(road.x2-road.x1, road.y2-road.y1), ...
    'siteNodes', double(site.grid_node), 'DFactorKgPerKWh', 1/(eta*lhv), ...
    'designWindSpeedVN', config.designWindSpeedVN, ...
    'roadDesignWindVN', config.roadDesignWindVN);
end

function incidence = radial_node_path_incidence(nNodes, fromNode, toNode, sourceNode)
nLines = numel(fromNode); adj = cell(nNodes,1); edgeAdj = cell(nNodes,1);
for ll = 1:nLines
    i=fromNode(ll); j=toNode(ll); adj{i}(end+1)=j; edgeAdj{i}(end+1)=ll; %#ok<AGROW>
    adj{j}(end+1)=i; edgeAdj{j}(end+1)=ll; %#ok<AGROW>
end
parent=zeros(nNodes,1); parentEdge=zeros(nNodes,1); visited=false(nNodes,1);
queue=zeros(nNodes,1); head=1; tail=1; queue(1)=sourceNode; visited(sourceNode)=true;
while head<=tail
    u=queue(head); head=head+1;
    for kk=1:numel(adj{u})
        v=adj{u}(kk); if visited(v), continue; end
        visited(v)=true; parent(v)=u; parentEdge(v)=edgeAdj{u}(kk);
        tail=tail+1; queue(tail)=v;
    end
end
if ~all(visited), error('Formal grid is not connected.'); end
incidence=false(nNodes,nLines);
for node=1:nNodes
    cur=node;
    while cur~=sourceNode
        incidence(node,parentEdge(cur))=true; cur=parent(cur);
    end
end
end

function idx = state_index(model, a, loc, lfw)
if a<1||a>6||loc<model.locMin||loc>model.locMin+size(model.stateIndex,2)-1||lfw<0||lfw>3
    error('Joint state is outside the formal support.');
end
idx = model.stateIndex(sub2ind(size(model.stateIndex), ...
    a, loc-model.locMin+1, lfw+1));
if idx<=0, error('Joint state is missing from the wind cache.'); end
end

function vmax = triangular_by_level(a,q,lower,mode,upper)
if a==1, vmax=0; return; end
lo=lower(a); mid=mode(a); hi=upper(a); split=(mid-lo)/(hi-lo);
if q<=split, vmax=lo+sqrt(q*(hi-lo)*(mid-lo));
else, vmax=hi-sqrt((1-q)*(hi-lo)*(hi-mid)); end
end

function [reach,cost] = road_state(nNodes,fromNode,toNode,edgeCost,sources)
adjacency=inf(nNodes); adjacency(1:nNodes+1:end)=0;
for edge=1:numel(edgeCost)
    if ~isfinite(edgeCost(edge)), continue; end
    i=fromNode(edge); j=toNode(edge);
    if edgeCost(edge)<adjacency(i,j)
        adjacency(i,j)=edgeCost(edge); adjacency(j,i)=edgeCost(edge);
    end
end
reach=false(numel(sources),nNodes); cost=inf(numel(sources),nNodes);
for site=1:numel(sources)
    distance=inf(1,nNodes); visited=false(1,nNodes); distance(sources(site))=0;
    for iteration=1:nNodes
        candidate=distance; candidate(visited)=Inf; [best,node]=min(candidate);
        if ~isfinite(best), break; end
        visited(node)=true; distance=min(distance,best+adjacency(node,:));
    end
    reach(site,:)=isfinite(distance); cost(site,:)=distance;
end
end

function hash = hash_scenario(D,A,C,failed,closed,wind)
md=java.security.MessageDigest.getInstance('SHA-256');
update_double(md,D); update_uint8(md,uint8(A)); update_double(md,C);
update_uint8(md,uint8(failed)); update_uint8(md,uint8(closed)); update_double(md,wind);
hash=digest_text(md);
end
function hash = hash_damage(failed,closed)
md=java.security.MessageDigest.getInstance('SHA-256');
update_uint8(md,uint8(failed)); update_uint8(md,uint8(closed)); hash=digest_text(md);
end
function hash=sha256_double(x),md=java.security.MessageDigest.getInstance('SHA-256');update_double(md,x);hash=digest_text(md);end
function hash=sha256_uint8(x),md=java.security.MessageDigest.getInstance('SHA-256');update_uint8(md,x);hash=digest_text(md);end
function update_double(md,x),bytes=typecast(double(x(:)),'uint8');md.update(typecast(bytes,'int8'));end
function update_uint8(md,x),md.update(typecast(uint8(x(:)),'int8'));end
function hash=digest_text(md),digest=typecast(md.digest(),'uint8');hash=lower(string(reshape(dec2hex(digest,2).',1,[])));end
