function solution = solve_warning_y_base_h2(locTbl, gridSeg, roadSeg, targetDistance)
%SOLVE_WARNING_Y_BASE_H2 Solve common southern y_base for warning distance.

if targetDistance <= 0
    error('solve_warning_y_base_h2:BadTarget', ...
        'targetDistance must be positive.');
end
if isempty(locTbl) || isempty(gridSeg) || isempty(roadSeg)
    error('solve_warning_y_base_h2:EmptyInput', ...
        'locTbl, gridSeg, and roadSeg must be nonempty.');
end

systemYMin = min([gridSeg.y1; gridSeg.y2; roadSeg.y1; roadSeg.y2]);
upper = systemYMin - 1e-6;
[fUpper, ~] = min_system_distance_at_y(locTbl, gridSeg, roadSeg, upper);
if fUpper > targetDistance
    error('solve_warning_y_base_h2:NoSouthernBracket', ...
        ['At the southern system boundary, minimum distance %.12g already ' ...
        'exceeds target %.12g. Cannot solve southern y_base.'], ...
        fUpper, targetDistance);
end

lower = upper - max(1000, 10 * targetDistance);
[fLower, ~] = min_system_distance_at_y(locTbl, gridSeg, roadSeg, lower);
iter = 0;
while fLower < targetDistance && iter < 20
    lower = lower - max(1000, 10 * targetDistance) * 2^iter;
    [fLower, ~] = min_system_distance_at_y(locTbl, gridSeg, roadSeg, lower);
    iter = iter + 1;
end
if fLower < targetDistance
    error('solve_warning_y_base_h2:NoLowerBracket', ...
        'Could not find a southern y value with distance above target.');
end

for iter = 1:100
    mid = (lower + upper) / 2;
    [fMid, ~] = min_system_distance_at_y(locTbl, gridSeg, roadSeg, mid);
    if fMid > targetDistance
        lower = mid;
    else
        upper = mid;
    end
    if abs(fMid - targetDistance) <= 1e-8
        break;
    end
end
yBase = (lower + upper) / 2;
[minDist, closest] = min_system_distance_at_y(locTbl, gridSeg, roadSeg, yBase);

solution = struct();
solution.y_base = yBase;
solution.warning_distance_target = targetDistance;
solution.minimum_actual_distance = minDist;
solution.closest_loc = closest.loc;
solution.closest_object_type = closest.object_type;
solution.closest_object_id = closest.object_id;
solution.closest_x = closest.closest_x;
solution.closest_y = closest.closest_y;
solution.center_x = closest.center_x;
solution.center_y = yBase;
solution.distance_error = minDist - targetDistance;
solution.system_y_min = systemYMin;
solution.bracket_lower = lower;
solution.bracket_upper = upper;
end

function [minDist, closest] = min_system_distance_at_y(locTbl, gridSeg, roadSeg, y)
minDist = Inf;
closest = struct('loc', NaN, 'object_type', "", 'object_id', NaN, ...
    'closest_x', NaN, 'closest_y', NaN, 'center_x', NaN);
for ii = 1:height(locTbl)
    x = double(locTbl.x_coord(ii));
    [dGrid, ~, cgx, cgy] = compute_point_to_segment_distance_h2( ...
        x, y, gridSeg.x1, gridSeg.y1, gridSeg.x2, gridSeg.y2);
    [dRoad, ~, crx, cry] = compute_point_to_segment_distance_h2( ...
        x, y, roadSeg.x1, roadSeg.y1, roadSeg.x2, roadSeg.y2);
    [dg, ig] = min(dGrid);
    [dr, ir] = min(dRoad);
    if dg <= dr
        d = dg;
        objectType = "grid_line";
        objectId = gridSeg.line_id(ig);
        cx = cgx(ig);
        cy = cgy(ig);
    else
        d = dr;
        objectType = "road_edge";
        objectId = roadSeg.road_edge_id(ir);
        cx = crx(ir);
        cy = cry(ir);
    end
    if d < minDist
        minDist = d;
        closest.loc = locTbl.loc(ii);
        closest.object_type = objectType;
        closest.object_id = objectId;
        closest.closest_x = cx;
        closest.closest_y = cy;
        closest.center_x = x;
    end
end
end
