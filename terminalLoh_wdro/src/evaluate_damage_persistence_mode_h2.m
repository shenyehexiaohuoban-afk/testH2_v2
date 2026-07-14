function result = evaluate_damage_persistence_mode_h2(config, foundation)
%EVALUATE_DAMAGE_PERSISTENCE_MODE_H2 Common-random-number mode smoke MC.

near = foundation.raw_near;
if ~isfield(near.Grid, 'P_load_base_kw')
    error('evaluate_damage_persistence_mode_h2:MissingNodeLoad', ...
        'NearStageInput.Grid.P_load_base_kw is required; no fallback is allowed.');
end
Pnode = double(near.Grid.P_load_base_kw(:));
etaFC = double(near.HydrogenDevice.eta_FC);
lhv = double(near.HydrogenDevice.h2_lhv_kWh_per_kg);
gridSeg = foundation.grid_segments;
roadSeg = foundation.road_segments;
locTbl = foundation.loc_table;
nLines = height(gridSeg);
nRoad = height(roadSeg);
nNodes = numel(Pnode);
W = numel(config.damageStageNames);
expectedRows = numel(config.damageModes) * numel(config.RmaxValues) * ...
    numel(config.aValues) * numel(config.locValues) * config.Nmc * W;
rows = cell(expectedRows, 39);
rr = 0;

for rIdx = 1:numel(config.RmaxValues)
    rmax = config.RmaxValues(rIdx);
    for a = config.aValues(:).'
        Vmax = intensity_to_vmax(a);
        for loc = config.locValues(:).'
            locRow = locTbl(locTbl.loc == loc, :);
            if height(locRow) ~= 1
                error('evaluate_damage_persistence_mode_h2:MissingLoc', ...
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
                for modeIdx = 1:numel(config.damageModes)
                    mode = config.damageModes(modeIdx);
                    failedPrevious = false(nLines, 1);
                    closedPrevious = false(nRoad, 1);
                    slowdownPrevious = zeros(nRoad, 1);
                    for ss = 1:W
                        d = stageData(ss);
                        lineU = reshape(lineUniform(mm, :, ss), [], 1);
                        roadU = reshape(roadUniform(mm, :, ss), [], 1);
                        rawFailed = lineU < d.pFail;
                        rawClosed = roadU < d.pClose;
                        slowdownNew = config.roadSlowdownLambda .* d.pClose;
                        if mode == "persistent_damage"
                            newlyFailed = rawFailed & ~failedPrevious;
                            newlyClosed = rawClosed & ~closedPrevious;
                            failed = failedPrevious | rawFailed;
                            closed = closedPrevious | rawClosed;
                            slowdown = max(slowdownPrevious, slowdownNew);
                            failedPrevious = failed;
                            closedPrevious = closed;
                            slowdownPrevious = slowdown;
                        else
                            newlyFailed = rawFailed;
                            newlyClosed = rawClosed;
                            failed = rawFailed;
                            closed = rawClosed;
                            slowdown = slowdownNew;
                        end

                        connected = connected_to_source(nNodes, ...
                            gridSeg.from_node, gridSeg.to_node, ~failed, ...
                            config.sourceNode);
                        outage = ~connected(:);
                        outage(config.sourceNode) = false;
                        P_loss_node = double(outage) .* Pnode;
                        Dnode = compute_Hres3h_node_demand_h2(P_loss_node, ...
                            config.sliceDurationH, etaFC, lhv);
                        slowRoad = ~closed & slowdown > config.slowRoadThreshold;
                        lineChecksum = sum(lineU .* (1:nLines).');
                        roadChecksum = sum(roadU .* (1:nRoad).');

                        rr = rr + 1;
                        rows(rr, :) = {mode, rmax, 40, a, loc, ...
                            config.damageStageNames(ss), ss, mm, commonSeed, ...
                            x, d.y, Vmax, sum(rawFailed), sum(newlyFailed), ...
                            sum(failed), sum(rawClosed), sum(newlyClosed), ...
                            sum(closed), sum(slowRoad), mean(1 + slowdown), ...
                            max(1 + slowdown), sum(outage), sum(P_loss_node), ...
                            sum(Dnode), mean(d.pFail), pct(d.pFail, 95), ...
                            max(d.pFail), mean(d.pClose), pct(d.pClose, 95), ...
                            max(d.pClose), lineChecksum, roadChecksum, ...
                            config.sliceDurationH, etaFC, lhv, config.sourceNode, ...
                            config.distanceMethod, false, ...
                            "same wind/probability/draw; mode changes inheritance only"}; %#ok<AGROW>
                    end
                end
            end
        end
    end
end

if rr ~= expectedRows
    error('evaluate_damage_persistence_mode_h2:RowCountMismatch', ...
        'Generated %d rows, expected %d.', rr, expectedRows);
end
bySlice = cell2table(rows, 'VariableNames', ...
    {'damage_mode', 'Rmax', 'Wstep', 'a', 'loc', 'stage', ...
    'stage_index', 'scenario_id', 'common_random_seed', 'center_x', ...
    'center_y', 'Vmax_mps', 'raw_failed_line_draw_count', ...
    'newly_failed_line_count', 'failed_line_count', ...
    'raw_closed_road_draw_count', 'newly_closed_road_count', ...
    'closed_road_count', 'slow_road_count', ...
    'slowdown_multiplier_mean', 'slowdown_multiplier_max', ...
    'outage_node_count', 'P_loss_total_kW', 'D_slice_total_kg', ...
    'line_pFail_mean', 'line_pFail_p95', 'line_pFail_max', ...
    'road_pClose_mean', 'road_pClose_p95', 'road_pClose_max', ...
    'line_uniform_checksum', 'road_uniform_checksum', ...
    'slice_duration_h', 'eta_FC', 'LHV_H2_kWh_per_kg', ...
    'source_node', 'distance_method', 'repair_enabled', ...
    'mode_difference_scope'});

result = struct();
result.by_slice = bySlice;
result.n_lines = nLines;
result.n_roads = nRoad;
result.n_nodes = nNodes;
result.max_P_loss_kW = sum(Pnode);
result.max_D_slice_kg = sum(Pnode) * config.sliceDurationH / (etaFC * lhv);
result.eta_FC = etaFC;
result.LHV_H2_kWh_per_kg = lhv;
result.y_base = foundation.y_base;
end

function stageData = build_stage_data(config, yBase, x, Vmax, rmax, ...
    gridSeg, roadSeg)
W = numel(config.damageStageNames);
stageData = repmat(struct('y', NaN, 'pFail', [], 'pClose', []), W, 1);
for ss = 1:W
    y = yBase + config.damageStageOffsets(ss) * 40;
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

function Vmax = intensity_to_vmax(a)
map = [0; 20.8; 28.55; 37.05; 46.20; 55.50];
if a < 1 || a > numel(map) || floor(a) ~= a
    error('evaluate_damage_persistence_mode_h2:BadIntensity', ...
        'Unsupported intensity a=%g.', a);
end
Vmax = map(a);
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
