function result = evaluate_fixed_resistance_damage_h2(config, foundation)
%EVALUATE_FIXED_RESISTANCE_DAMAGE_H2 Three-mode CRN damage comparison.

near = foundation.raw_near;
if ~isfield(near.Grid, 'P_load_base_kw')
    error('evaluate_fixed_resistance_damage_h2:MissingNodeLoad', ...
        'NearStageInput.Grid.P_load_base_kw is required; no fallback is allowed.');
end
Pnode = double(near.Grid.P_load_base_kw(:));
etaFC = double(near.HydrogenDevice.eta_FC);
lhv = double(near.HydrogenDevice.h2_lhv_kWh_per_kg);
gridSeg = foundation.grid_segments;
roadSeg = foundation.road_segments;
locTbl = foundation.loc_table;
siteNodes = readtable(config.siteNodeFile);
require_vars(siteNodes, {'site_id', 'grid_node'}, 'stage1_site_nodes.csv');
siteNodes = sortrows(siteNodes, 'site_id');

nLines = height(gridSeg);
nRoad = height(roadSeg);
nNodes = numel(Pnode);
nSites = height(siteNodes);
if nNodes ~= 33 || nSites ~= 4
    error('evaluate_fixed_resistance_damage_h2:UnexpectedDimensions', ...
        'Expected 33 grid/road nodes and 4 site anchors; found %d and %d.', ...
        nNodes, nSites);
end
if any(siteNodes.grid_node < 1 | siteNodes.grid_node > nNodes)
    error('evaluate_fixed_resistance_damage_h2:BadSiteAnchor', ...
        'Every site grid_node must be in 1:%d.', nNodes);
end

roadLength = hypot(roadSeg.x2 - roadSeg.x1, roadSeg.y2 - roadSeg.y1);
if any(~isfinite(roadLength) | roadLength <= 0)
    error('evaluate_fixed_resistance_damage_h2:BadRoadLength', ...
        'Road edge lengths must be finite and positive.');
end

W = numel(config.damageStageNames);
expectedRows = numel(config.damageModes) * numel(config.RmaxValues) * ...
    numel(config.aValues) * numel(config.locValues) * config.Nmc * W;
rows = cell(expectedRows, 58);
rr = 0;
maxPLoss = sum(Pnode((1:nNodes).' ~= config.sourceNode));
maxDSlice = maxPLoss * config.sliceDurationH / (etaFC * lhv);

for rIdx = 1:numel(config.RmaxValues)
    rmax = config.RmaxValues(rIdx);
    for a = config.aValues(:).'
        Vmax = intensity_to_vmax(a);
        for loc = config.locValues(:).'
            locRow = locTbl(locTbl.loc == loc, :);
            if height(locRow) ~= 1
                error('evaluate_fixed_resistance_damage_h2:MissingLoc', ...
                    'loc=%g must appear exactly once.', loc);
            end
            x = double(locRow.x_coord);
            commonSeed = config.rngSeed + 100000 * rIdx + ...
                1000 * a + 10 * (loc + 3);
            rng(commonSeed, 'twister');
            lineUniform = rand(config.Nmc, nLines, W);
            roadUniform = rand(config.Nmc, nRoad, W);
            stageData = build_stage_data(config, foundation.y_base, x, ...
                Vmax, rmax, gridSeg, roadSeg);

            for mm = 1:config.Nmc
                fixedLineU = reshape(lineUniform(mm, :, 1), [], 1);
                fixedRoadU = reshape(roadUniform(mm, :, 1), [], 1);
                fixedLineChecksum = weighted_checksum(fixedLineU);
                fixedRoadChecksum = weighted_checksum(fixedRoadU);

                for modeIdx = 1:numel(config.damageModes)
                    mode = config.damageModes(modeIdx);
                    failedPrevious = false(nLines, 1);
                    closedPrevious = false(nRoad, 1);
                    slowdownPrevious = zeros(nRoad, 1);

                    for ss = 1:W
                        d = stageData(ss);
                        baseLineU = reshape(lineUniform(mm, :, ss), [], 1);
                        baseRoadU = reshape(roadUniform(mm, :, ss), [], 1);
                        if mode == "persistent_fixed_resistance"
                            appliedLineU = fixedLineU;
                            appliedRoadU = fixedRoadU;
                            lineReuseError = max(abs(appliedLineU - fixedLineU));
                            roadReuseError = max(abs(appliedRoadU - fixedRoadU));
                        else
                            appliedLineU = baseLineU;
                            appliedRoadU = baseRoadU;
                            lineReuseError = NaN;
                            roadReuseError = NaN;
                        end

                        rawFailed = appliedLineU <= d.pFail;
                        rawClosed = appliedRoadU <= d.pClose;
                        slowdownNew = config.roadSlowdownLambda .* d.pClose;

                        if mode == "independent_snapshot"
                            failed = rawFailed;
                            closed = rawClosed;
                            slowdown = slowdownNew;
                            newlyFailed = rawFailed;
                            newlyClosed = rawClosed;
                            scope = "current-stage draw; recovery allowed";
                        else
                            newlyFailed = rawFailed & ~failedPrevious;
                            newlyClosed = rawClosed & ~closedPrevious;
                            failed = failedPrevious | rawFailed;
                            closed = closedPrevious | rawClosed;
                            slowdown = max(slowdownPrevious, slowdownNew);
                            failedPrevious = failed;
                            closedPrevious = closed;
                            slowdownPrevious = slowdown;
                            if mode == "persistent_independent_draws"
                                scope = "stage draws plus cumulative OR/max; no repair";
                            else
                                scope = "fixed component threshold plus cumulative OR/max; no repair";
                            end
                        end

                        connected = connected_to_source(nNodes, ...
                            gridSeg.from_node, gridSeg.to_node, ~failed, ...
                            config.sourceNode);
                        outage = ~connected(:);
                        outage(config.sourceNode) = false;
                        P_loss_node = double(outage) .* Pnode;
                        Dnode = compute_Hres3h_node_demand_h2(P_loss_node, ...
                            config.sliceDurationH, etaFC, lhv);

                        edgeCost = roadLength .* (1 + slowdown);
                        edgeCost(closed) = Inf;
                        Cdist = road_shortest_paths(nNodes, roadSeg.from_node, ...
                            roadSeg.to_node, edgeCost, double(siteNodes.grid_node));
                        A = isfinite(Cdist);
                        finiteC = Cdist(A);
                        reachablePairCount = sum(A(:));
                        totalPairCount = numel(A);
                        slowRoad = ~closed & slowdown > config.slowRoadThreshold;

                        rr = rr + 1;
                        rows(rr, :) = {mode, rmax, config.Wstep, a, loc, ...
                            config.damageStageNames(ss), ss, mm, commonSeed, ...
                            x, d.y, Vmax, sum(rawFailed), sum(newlyFailed), ...
                            sum(failed), sum(rawClosed), sum(newlyClosed), ...
                            sum(closed), sum(slowRoad), mean(slowdown), ...
                            max(slowdown), sum(outage), sum(P_loss_node), ...
                            sum(Dnode), mean(d.pFail), pct(d.pFail, 95), ...
                            max(d.pFail), mean(d.pClose), pct(d.pClose, 95), ...
                            max(d.pClose), weighted_checksum(baseLineU), ...
                            weighted_checksum(baseRoadU), fixedLineChecksum, ...
                            fixedRoadChecksum, weighted_checksum(appliedLineU), ...
                            weighted_checksum(appliedRoadU), lineReuseError, ...
                            roadReuseError, reachablePairCount, ...
                            reachablePairCount / totalPairCount, numel(finiteC), ...
                            mean_or_nan(finiteC), pct(finiteC, 95), ...
                            max_or_nan(finiteC), totalPairCount - reachablePairCount, ...
                            all(A(:) == 0 | A(:) == 1), ...
                            all(isfinite(Cdist(A))), all(~isfinite(Cdist(~A))), ...
                            config.sliceDurationH, etaFC, lhv, config.sourceNode, ...
                            config.distanceMethod, config.CDefinition, false, ...
                            scope, maxPLoss, maxDSlice}; %#ok<AGROW>
                    end
                end
            end
        end
    end
end

if rr ~= expectedRows
    error('evaluate_fixed_resistance_damage_h2:RowCountMismatch', ...
        'Generated %d rows, expected %d.', rr, expectedRows);
end

bySlice = cell2table(rows, 'VariableNames', ...
    {'damage_mode', 'Rmax', 'Wstep', 'a', 'loc', 'stage', ...
    'stage_index', 'scenario_id', 'common_random_seed', 'center_x', ...
    'center_y', 'Vmax_mps', 'raw_failed_line_draw_count', ...
    'newly_failed_line_count', 'failed_line_count', ...
    'raw_closed_road_draw_count', 'newly_closed_road_count', ...
    'closed_road_count', 'slow_road_count', 'slowdown_severity_mean', ...
    'slowdown_severity_max', 'outage_node_count', 'P_loss_total_kW', ...
    'D_slice_total_kg', 'line_pFail_mean', 'line_pFail_p95', ...
    'line_pFail_max', 'road_pClose_mean', 'road_pClose_p95', ...
    'road_pClose_max', 'base_line_stage_uniform_checksum', ...
    'base_road_stage_uniform_checksum', 'fixed_line_threshold_checksum', ...
    'fixed_road_threshold_checksum', 'applied_line_threshold_checksum', ...
    'applied_road_threshold_checksum', ...
    'fixed_line_threshold_reuse_max_abs_error', ...
    'fixed_road_threshold_reuse_max_abs_error', 'reachable_pair_count', ...
    'reachable_pair_share', 'finite_C_count', 'C_finite_mean', ...
    'C_finite_p95', 'C_finite_max', 'unreachable_pair_count', ...
    'A_binary_ok', 'reachable_C_all_finite', ...
    'unreachable_C_excluded_from_statistics', 'slice_duration_h', ...
    'eta_FC', 'LHV_H2_kWh_per_kg', 'source_node', 'distance_method', ...
    'C_definition', 'repair_enabled', 'mode_difference_scope', ...
    'max_P_loss_kW', 'max_D_slice_kg'});

result = struct();
result.by_slice = bySlice;
result.n_lines = nLines;
result.n_roads = nRoad;
result.n_nodes = nNodes;
result.n_sites = nSites;
result.max_P_loss_kW = maxPLoss;
result.max_D_slice_kg = maxDSlice;
result.eta_FC = etaFC;
result.LHV_H2_kWh_per_kg = lhv;
result.y_base = foundation.y_base;
end

function stageData = build_stage_data(config, yBase, x, Vmax, rmax, ...
    gridSeg, roadSeg)
W = numel(config.damageStageNames);
stageData = repmat(struct('y', NaN, 'pFail', [], 'pClose', []), W, 1);
for ss = 1:W
    y = yBase + config.damageStageOffsets(ss) * config.Wstep;
    lineDist = compute_point_to_segment_distance_h2(x, y, ...
        gridSeg.x1, gridSeg.y1, gridSeg.x2, gridSeg.y2);
    roadDist = compute_point_to_segment_distance_h2(x, y, ...
        roadSeg.x1, roadSeg.y1, roadSeg.x2, roadSeg.y2);
    lineWind = compute_wind_speed_radial_h2(lineDist, Vmax, rmax, ...
        config.windDecayB);
    roadWind = compute_wind_speed_radial_h2(roadDist, Vmax, rmax, ...
        config.windDecayB);
    stageData(ss).y = y;
    stageData(ss).pFail = compute_line_failure_prob_h2(lineWind, ...
        config.designWindSpeedVN);
    stageData(ss).pClose = compute_line_failure_prob_h2(roadWind, ...
        config.roadDesignWindVN);
end
end

function connected = connected_to_source(Nj, fromNode, toNode, activeLine, sourceNode)
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
queue(1) = sourceNode;
connected(sourceNode) = true;
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

function D = road_shortest_paths(Nj, fromNode, toNode, edgeCost, sources)
adj = inf(Nj, Nj);
adj(1:(Nj + 1):end) = 0;
for ee = 1:numel(edgeCost)
    if ~isfinite(edgeCost(ee))
        continue;
    end
    i = fromNode(ee);
    j = toNode(ee);
    if edgeCost(ee) < adj(i, j)
        adj(i, j) = edgeCost(ee);
        adj(j, i) = edgeCost(ee);
    end
end
D = inf(numel(sources), Nj);
for ii = 1:numel(sources)
    dist = inf(1, Nj);
    visited = false(1, Nj);
    dist(sources(ii)) = 0;
    for iter = 1:Nj
        candidate = dist;
        candidate(visited) = Inf;
        [best, u] = min(candidate);
        if ~isfinite(best)
            break;
        end
        visited(u) = true;
        dist = min(dist, best + adj(u, :));
    end
    D(ii, :) = dist;
end
end

function Vmax = intensity_to_vmax(a)
map = [0; 20.8; 28.55; 37.05; 46.20; 55.50];
if a < 1 || a > numel(map) || floor(a) ~= a
    error('evaluate_fixed_resistance_damage_h2:BadIntensity', ...
        'Unsupported intensity a=%g.', a);
end
Vmax = map(a);
end

function require_vars(tbl, names, fileName)
for ii = 1:numel(names)
    if ~ismember(names{ii}, tbl.Properties.VariableNames)
        error('evaluate_fixed_resistance_damage_h2:MissingColumn', ...
            '%s is missing %s.', fileName, names{ii});
    end
end
end

function value = weighted_checksum(x)
w = (1:numel(x)).';
value = sum(double(x(:)) .* w);
end

function value = mean_or_nan(x)
if isempty(x)
    value = NaN;
else
    value = mean(x);
end
end

function value = max_or_nan(x)
if isempty(x)
    value = NaN;
else
    value = max(x);
end
end

function value = pct(x, p)
x = sort(double(x(:)));
x = x(isfinite(x));
if isempty(x)
    value = NaN;
else
    idx = max(1, min(numel(x), ceil(p / 100 * numel(x))));
    value = x(idx);
end
end
