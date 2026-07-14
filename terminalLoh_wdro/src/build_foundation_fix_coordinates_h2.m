function foundation = build_foundation_fix_coordinates_h2(config)
%BUILD_FOUNDATION_FIX_COORDINATES_H2 Verify warning geometry and stage y.

requiredFiles = {config.warningSolutionFile, config.warningGeometryFile, ...
    config.warningRankingFile, config.warningStageSummaryFile, ...
    config.warningDiagnosticsFile, config.warningRankingSourceFile, ...
    config.locCoordinateFile, ...
    config.nearInputFile, config.roadEdgeFile, config.siteNodeFile};
for ii = 1:numel(requiredFiles)
    if ~isfile(requiredFiles{ii})
        error('build_foundation_fix_coordinates_h2:MissingInput', ...
            'Missing required input: %s', requiredFiles{ii});
    end
end

warningTbl = readtable(config.warningSolutionFile);
if height(warningTbl) ~= 1
    error('build_foundation_fix_coordinates_h2:BadWarningSolution', ...
        'warning_y_base_solution.csv must contain exactly one row.');
end
rankingTbl = readtable(config.warningRankingFile, 'TextType', 'string');
if height(rankingTbl) < 2
    error('build_foundation_fix_coordinates_h2:BadRanking', ...
        'Wstep_candidate_ranking.csv must contain at least two rows.');
end
rankingTbl = sortrows(rankingTbl, 'rank');
if double(rankingTbl.Wstep(1)) ~= config.recommendedWstep || ...
        double(rankingTbl.Wstep(2)) ~= config.comparisonWstep
    error('build_foundation_fix_coordinates_h2:UnexpectedOldRanking', ...
        'Expected old ranking Wstep 40 first and 45 second.');
end
warningGeometryTbl = readtable(config.warningGeometryFile, 'TextType', 'string');
warningStageTbl = readtable(config.warningStageSummaryFile, 'TextType', 'string');
warningDiagnosticsText = string(fileread(config.warningDiagnosticsFile));
if isempty(warningGeometryTbl) || isempty(warningStageTbl) || ...
        strlength(warningDiagnosticsText) == 0
    error('build_foundation_fix_coordinates_h2:EmptyWarningAuditInput', ...
        'Warning geometry, stage summary, and diagnostics must be nonempty.');
end
rankingSourceText = string(fileread(config.warningRankingSourceFile));
hardcoded40 = contains(rankingSourceText, 'recommendedWstep = 40') || ...
    contains(rankingSourceText, 'recommendedWstep=40');
usesScoreRanking = contains(rankingSourceText, 'rankWork.neg_score') && ...
    contains(rankingSourceText, "sortrows(rankWork, {'neg_score', 'Wstep'})");
if ~usesScoreRanking
    error('build_foundation_fix_coordinates_h2:RankingMechanismNotVerified', ...
        'Could not verify score-based Wstep ranking in source.');
end

locRaw = readtable(config.locCoordinateFile, 'TextType', 'string');
requiredLocVars = {'loc', 'x_coord'};
for ii = 1:numel(requiredLocVars)
    if ~ismember(requiredLocVars{ii}, locRaw.Properties.VariableNames)
        error('build_foundation_fix_coordinates_h2:MissingLocColumn', ...
            'loc coordinate table is missing %s.', requiredLocVars{ii});
    end
end
locTbl = unique(locRaw(:, {'loc', 'x_coord'}), 'rows', 'stable');
locTbl = sortrows(locTbl, 'loc');
expectedLoc = (-2:10).';
if ~isequal(double(locTbl.loc(:)), expectedLoc)
    error('build_foundation_fix_coordinates_h2:UnexpectedLocSet', ...
        'Expected loc=-2:10 in the foundation coordinate table.');
end

raw = load(config.nearInputFile, 'NearStageInput');
if ~isfield(raw, 'NearStageInput')
    error('build_foundation_fix_coordinates_h2:MissingNearStageInput', ...
        'NearStageInput is missing from %s.', config.nearInputFile);
end
layout = build_h2_spatial_layout_preview(raw.NearStageInput);
[gridSeg, roadSeg, siteTbl] = build_segments(config, layout);

recomputed = solve_warning_y_base_h2(locTbl, gridSeg, roadSeg, ...
    config.warningDistanceKmEq);
fileYBase = double(warningTbl.y_base(1));
if abs(fileYBase - recomputed.y_base) > 1e-5
    error('build_foundation_fix_coordinates_h2:YBaseMismatch', ...
        'File y_base %.12g differs from recomputed %.12g.', ...
        fileYBase, recomputed.y_base);
end
if abs(recomputed.minimum_actual_distance - config.warningDistanceKmEq) > 1e-5
    error('build_foundation_fix_coordinates_h2:WarningDistanceMismatch', ...
        'Recomputed minimum distance %.12g does not match target %.12g.', ...
        recomputed.minimum_actual_distance, config.warningDistanceKmEq);
end

closestLine = gridSeg(gridSeg.line_id == recomputed.closest_object_id, :);
if recomputed.closest_object_type == "grid_line" && height(closestLine) ~= 1
    error('build_foundation_fix_coordinates_h2:MissingClosestLine', ...
        'Could not identify recomputed closest grid line.');
end

rows = cell(numel(config.WstepValues) * numel(config.stageNames), 8);
rr = 0;
for ww = 1:numel(config.WstepValues)
    wstep = config.WstepValues(ww);
    for ss = 1:numel(config.stageNames)
        rr = rr + 1;
        rows(rr, :) = {wstep, config.stageNames(ss), ss - 1, ...
            ss > 1, fileYBase, config.stageOffsets(ss), ...
            fileYBase + config.stageOffsets(ss) * wstep, ...
            config.sliceDurationH * double(ss > 1)};
    end
end
stageCoordinates = cell2table(rows, 'VariableNames', ...
    {'Wstep', 'stage', 'stage_index', 'included_in_Hres3h', ...
    'y_base', 'stage_offset', 'y_coord', 'slice_duration_h'});

geometryRows = {};
for ww = 1:numel(config.WstepValues)
    wstep = config.WstepValues(ww);
    for ss = 1:numel(config.stageNames)
        y = fileYBase + config.stageOffsets(ss) * wstep;
        for ll = 1:height(locTbl)
            x = double(locTbl.x_coord(ll));
            [lineDist, ~, lineCx, lineCy] = ...
                compute_point_to_segment_distance_h2(x, y, gridSeg.x1, ...
                gridSeg.y1, gridSeg.x2, gridSeg.y2);
            [roadDist, ~, roadCx, roadCy] = ...
                compute_point_to_segment_distance_h2(x, y, roadSeg.x1, ...
                roadSeg.y1, roadSeg.x2, roadSeg.y2);
            [dGrid, iGrid] = min(lineDist);
            [dRoad, iRoad] = min(roadDist);
            geometryRows(end + 1, :) = {wstep, config.stageNames(ss), ...
                ss - 1, double(locTbl.loc(ll)), x, y, dGrid, dRoad, ...
                min(dGrid, dRoad), gridSeg.line_id(iGrid), ...
                lineCx(iGrid), lineCy(iGrid), roadSeg.road_edge_id(iRoad), ...
                roadCx(iRoad), roadCy(iRoad), config.distanceMethod}; %#ok<AGROW>
        end
    end
end
geometryTbl = cell2table(geometryRows, 'VariableNames', ...
    {'Wstep', 'stage', 'stage_index', 'loc', 'center_x', 'center_y', ...
    'd_grid_min', 'd_road_min', 'd_system_min', 'closest_line_id', ...
    'closest_line_x', 'closest_line_y', 'closest_road_edge_id', ...
    'closest_road_x', 'closest_road_y', 'distance_method'});

foundation = struct();
foundation.raw_near = raw.NearStageInput;
foundation.layout = layout;
foundation.grid_segments = gridSeg;
foundation.road_segments = roadSeg;
foundation.site_table = siteTbl;
foundation.loc_table = locTbl;
foundation.warning_file = warningTbl;
foundation.warning_ranking = rankingTbl;
foundation.warning_geometry = warningGeometryTbl;
foundation.warning_stage_summary = warningStageTbl;
foundation.warning_diagnostics_text = warningDiagnosticsText;
foundation.recomputed_solution = recomputed;
foundation.y_base = fileYBase;
foundation.stage_coordinates = stageCoordinates;
foundation.geometry_by_loc = geometryTbl;
foundation.closest_line = closestLine;
foundation.old_ranking_hardcoded_40 = hardcoded40;
foundation.old_ranking_uses_score = usesScoreRanking;
foundation.old_ranking_recommended = double(rankingTbl.Wstep(1));
foundation.old_ranking_second = double(rankingTbl.Wstep(2));
end

function [gridSeg, roadSeg, siteTbl] = build_segments(config, layout)
nodes = sortrows(layout.nodes, 'node_id');
lines = sortrows(layout.lines, 'line_id');
gridSeg = table(lines.line_id, lines.source_edge_id, lines.from_node, ...
    lines.to_node, nodes.x_km(lines.from_node), ...
    nodes.y_km(lines.from_node), nodes.x_km(lines.to_node), ...
    nodes.y_km(lines.to_node), 'VariableNames', ...
    {'line_id', 'source_edge_id', 'from_node', 'to_node', ...
    'x1', 'y1', 'x2', 'y2'});

roadRaw = readtable(config.roadEdgeFile);
siteRaw = readtable(config.siteNodeFile);
require_vars(roadRaw, {'road_edge_id', 'from_node', 'to_node'}, ...
    'stage1_road_edges.csv');
require_vars(siteRaw, {'site_id', 'grid_node'}, ...
    'stage1_site_nodes.csv');
roadSeg = table(double(roadRaw.road_edge_id), ...
    double(roadRaw.from_node), double(roadRaw.to_node), ...
    nodes.x_km(double(roadRaw.from_node)), ...
    nodes.y_km(double(roadRaw.from_node)), ...
    nodes.x_km(double(roadRaw.to_node)), ...
    nodes.y_km(double(roadRaw.to_node)), 'VariableNames', ...
    {'road_edge_id', 'from_node', 'to_node', 'x1', 'y1', 'x2', 'y2'});
siteTbl = sortrows(layout.sites, 'site_id');
end

function require_vars(tbl, names, fileName)
for ii = 1:numel(names)
    if ~ismember(names{ii}, tbl.Properties.VariableNames)
        error('build_foundation_fix_coordinates_h2:MissingColumn', ...
            '%s is missing %s.', fileName, names{ii});
    end
end
end
