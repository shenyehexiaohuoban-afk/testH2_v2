function locExtTbl = build_lookahead_location_ext_h2(origLocIds, locCoordTbl, config)
%BUILD_LOOKAHEAD_LOCATION_EXT_H2 Build W-halo location ids and coordinates.

origLocIds = double(origLocIds(:));
if isempty(origLocIds)
    error('build_lookahead_location_ext_h2:EmptyLocIds', ...
        'Original loc ids cannot be empty.');
end
if any(diff(origLocIds) ~= 1)
    error('build_lookahead_location_ext_h2:NonConsecutiveLocIds', ...
        'Original loc ids must be consecutive.');
end
if ~all(ismember({'loc', 'center_x_km', 'center_y_km'}, ...
        locCoordTbl.Properties.VariableNames))
    error('build_lookahead_location_ext_h2:MissingCoordColumns', ...
        'locCoordTbl must contain loc, center_x_km, and center_y_km.');
end

if isfield(config, 'halo_width')
    haloWidth = config.halo_width;
else
    haloWidth = config.W;
end
locMin = min(origLocIds);
locMax = max(origLocIds);
extLocIds = (locMin - haloWidth:locMax + haloWidth).';
rowId = (1:numel(extLocIds)).';
isOriginal = extLocIds >= locMin & extLocIds <= locMax;
baseLocId = min(max(extLocIds, locMin), locMax);

coordRows = locCoordTbl(ismember(locCoordTbl.loc, origLocIds), :);
coordRows = sortrows(coordRows, 'loc');
if height(coordRows) ~= numel(origLocIds)
    error('build_lookahead_location_ext_h2:CoordLocMismatch', ...
        'Coordinate table does not contain all original loc ids.');
end
xOrig = double(coordRows.center_x_km(:));
yOrig = double(coordRows.center_y_km(:));
if numel(xOrig) == 1
    leftStepX = 1;
    rightStepX = 1;
    leftStepY = 0;
    rightStepY = 0;
else
    leftStepX = xOrig(2) - xOrig(1);
    rightStepX = xOrig(end) - xOrig(end - 1);
    leftStepY = yOrig(2) - yOrig(1);
    rightStepY = yOrig(end) - yOrig(end - 1);
end

xCoord = zeros(numel(extLocIds), 1);
yCoord = zeros(numel(extLocIds), 1);
for rr = 1:numel(extLocIds)
    locId = extLocIds(rr);
    if locId < locMin
        offset = locMin - locId;
        xCoord(rr) = xOrig(1) - offset * leftStepX;
        yCoord(rr) = yOrig(1) - offset * leftStepY;
    elseif locId > locMax
        offset = locId - locMax;
        xCoord(rr) = xOrig(end) + offset * rightStepX;
        yCoord(rr) = yOrig(end) + offset * rightStepY;
    else
        idx = find(origLocIds == locId, 1, 'first');
        xCoord(rr) = xOrig(idx);
        yCoord(rr) = yOrig(idx);
    end
end

locExtTbl = table(extLocIds, rowId, double(isOriginal), baseLocId, ...
    xCoord, yCoord, ...
    'VariableNames', {'loc_id', 'row_id', 'is_original', ...
    'base_loc_id', 'x_coord', 'y_coord'});
end
