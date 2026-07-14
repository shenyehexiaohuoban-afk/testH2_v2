function [transTbl, checkTbl, kernelTbl] = build_lookahead_transition_loc_h2(P_loc, locExtTbl, config)
%BUILD_LOOKAHEAD_TRANSITION_LOC_H2 Build extended-location transition table.

P = double(P_loc);
if size(P, 1) ~= size(P, 2)
    error('build_lookahead_transition_loc_h2:NonSquareMatrix', ...
        'Location transition matrix must be square.');
end
rowSums = sum(P, 2);
if any(rowSums <= 0)
    error('build_lookahead_transition_loc_h2:BadRowSum', ...
        'Location transition matrix has non-positive row sum.');
end
P = P ./ rowSums;

nLoc = size(P, 1);
deltaVals = (-(nLoc - 1):(nLoc - 1)).';
deltaProb = zeros(numel(deltaVals), 1);
for from = 1:nLoc
    for to = 1:nLoc
        delta = to - from;
        idx = find(deltaVals == delta, 1, 'first');
        deltaProb(idx) = deltaProb(idx) + P(from, to) / nLoc;
    end
end
deltaProb = deltaProb ./ sum(deltaProb);
kernelTbl = table(deltaVals, deltaProb, ...
    'VariableNames', {'delta_loc', 'prob'});

locIds = double(locExtTbl.loc_id(:));
locMinExt = min(locIds);
locMaxExt = max(locIds);
rows = {};
for ff = 1:numel(locIds)
    fromLoc = locIds(ff);
    toMap = containers.Map('KeyType', 'double', 'ValueType', 'double');
    for dd = 1:numel(deltaVals)
        p = deltaProb(dd);
        if p <= 0
            continue;
        end
        toLoc = fromLoc + deltaVals(dd);
        toLoc = min(max(toLoc, locMinExt), locMaxExt);
        if isKey(toMap, toLoc)
            toMap(toLoc) = toMap(toLoc) + p;
        else
            toMap(toLoc) = p;
        end
    end
    keysCell = keys(toMap);
    toLocs = sort(cell2mat(keysCell(:)));
    for tt = 1:numel(toLocs)
        rows(end + 1, :) = {fromLoc, toLocs(tt), toMap(toLocs(tt))}; %#ok<AGROW>
    end
end
transTbl = cell2table(rows, 'VariableNames', ...
    {'from_loc_id', 'to_loc_id', 'prob'});

checkRows = {};
for ff = 1:numel(locIds)
    fromLoc = locIds(ff);
    rowsF = transTbl(transTbl.from_loc_id == fromLoc, :);
    probSum = sum(rowsF.prob);
    if abs(probSum - 1) <= 1e-8
        status = "OK";
    else
        status = "BAD_PROB_SUM";
    end
    checkRows(end + 1, :) = {fromLoc, probSum, height(rowsF), ...
        min(rowsF.to_loc_id), max(rowsF.to_loc_id), char(status)}; %#ok<AGROW>
end
checkTbl = cell2table(checkRows, 'VariableNames', ...
    {'from_loc_id', 'prob_sum', 'nonzero_to_count', ...
    'min_to_loc_id', 'max_to_loc_id', 'status'});
end
