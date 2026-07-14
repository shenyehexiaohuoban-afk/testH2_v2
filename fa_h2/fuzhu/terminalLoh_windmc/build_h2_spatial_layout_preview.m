function layout = build_h2_spatial_layout_preview(NearStageInput)
%BUILD_H2_SPATIAL_LAYOUT_PREVIEW Build offline wind-preview coordinates.

nodeXYRaw = double(NearStageInput.Spatial.node_positions);
siteXYRaw = double(NearStageInput.Spatial.site_positions);
if size(nodeXYRaw, 1) ~= 33 || size(nodeXYRaw, 2) ~= 2
    error('build_h2_spatial_layout_preview:BadNodePositions', ...
        'NearStageInput.Spatial.node_positions must be 33-by-2.');
end

nodeX = affine_scale(nodeXYRaw(:, 1), -40, -10);
nodeY = affine_scale(nodeXYRaw(:, 2), 10, 35);
siteX = affine_apply(siteXYRaw(:, 1), min(nodeXYRaw(:, 1)), max(nodeXYRaw(:, 1)), -40, -10);
siteY = affine_apply(siteXYRaw(:, 2), min(nodeXYRaw(:, 2)), max(nodeXYRaw(:, 2)), 10, 35);

nodeTbl = table((1:33).', nodeX, nodeY, ...
    'VariableNames', {'node_id', 'x_km', 'y_km'});
siteTbl = table((1:size(siteXYRaw, 1)).', siteX, siteY, ...
    'VariableNames', {'site_id', 'x_km', 'y_km'});

if ~isfield(NearStageInput, 'Grid') || ~isfield(NearStageInput.Grid, 'power_edges') || ...
        ~isfield(NearStageInput.Grid, 'branch_indices')
    error('build_h2_spatial_layout_preview:MissingGridLines', ...
        'NearStageInput.Grid.power_edges and branch_indices are required.');
end
edgesAll = double(NearStageInput.Grid.power_edges);
branchIdx = double(NearStageInput.Grid.branch_indices(:));
edges = edgesAll(branchIdx, :);
fromNode = edges(:, 1);
toNode = edges(:, 2);
lineMidX = (nodeX(fromNode) + nodeX(toNode)) / 2;
lineMidY = (nodeY(fromNode) + nodeY(toNode)) / 2;
lineTbl = table((1:numel(branchIdx)).', branchIdx, fromNode, toNode, ...
    lineMidX, lineMidY, ...
    'VariableNames', {'line_id', 'source_edge_id', 'from_node', 'to_node', ...
    'line_mid_x_km', 'line_mid_y_km'});

locCenterX = [-50; -33; -17; 0; 17; 33; 50];
locCenterY = zeros(numel(locCenterX), 1);
locTbl = table((1:numel(locCenterX)).', locCenterX, locCenterY, ...
    'VariableNames', {'loc', 'center_x_km', 'center_y_km'});

layout = struct();
layout.nodes = nodeTbl;
layout.lines = lineTbl;
layout.locs = locTbl;
layout.sites = siteTbl;
layout.combined = build_combined_layout_table(nodeTbl, lineTbl, locTbl, siteTbl);
end

function y = affine_scale(x, newMin, newMax)
y = affine_apply(x, min(x), max(x), newMin, newMax);
end

function y = affine_apply(x, oldMin, oldMax, newMin, newMax)
if oldMax <= oldMin
    error('build_h2_spatial_layout_preview:BadCoordinateRange', ...
        'Coordinate range must be nonzero.');
end
y = newMin + (double(x) - oldMin) .* (newMax - newMin) ./ (oldMax - oldMin);
end

function tbl = build_combined_layout_table(nodeTbl, lineTbl, locTbl, siteTbl)
rows = {};
for i = 1:height(nodeTbl)
    rows(end + 1, :) = {"node", i, nodeTbl.node_id(i), NaN, NaN, NaN, NaN, NaN, ...
        nodeTbl.x_km(i), nodeTbl.y_km(i), NaN, NaN}; %#ok<AGROW>
end
for i = 1:height(lineTbl)
    rows(end + 1, :) = {"line_midpoint", i, NaN, lineTbl.line_id(i), ...
        lineTbl.from_node(i), lineTbl.to_node(i), NaN, NaN, ...
        NaN, NaN, lineTbl.line_mid_x_km(i), lineTbl.line_mid_y_km(i)}; %#ok<AGROW>
end
for i = 1:height(locTbl)
    rows(end + 1, :) = {"loc_center", i, NaN, NaN, NaN, NaN, locTbl.loc(i), NaN, ...
        locTbl.center_x_km(i), locTbl.center_y_km(i), NaN, NaN}; %#ok<AGROW>
end
for i = 1:height(siteTbl)
    rows(end + 1, :) = {"h2_site", i, NaN, NaN, NaN, NaN, NaN, siteTbl.site_id(i), ...
        siteTbl.x_km(i), siteTbl.y_km(i), NaN, NaN}; %#ok<AGROW>
end
tbl = cell2table(rows, 'VariableNames', {'record_type', 'record_id', ...
    'node_id', 'line_id', 'from_node', 'to_node', 'loc', 'site_id', ...
    'x_km', 'y_km', 'line_mid_x_km', 'line_mid_y_km'});
end
