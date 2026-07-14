function [transTbl, checkTbl] = build_lookahead_transition_intensity_h2(P_intensity, config) %#ok<INUSD>
%BUILD_LOOKAHEAD_TRANSITION_INTENSITY_H2 Copy intensity transition for look-ahead.

P = double(P_intensity);
if size(P, 1) ~= size(P, 2)
    error('build_lookahead_transition_intensity_h2:NonSquareMatrix', ...
        'Intensity transition matrix must be square.');
end
rowSums = sum(P, 2);
if any(rowSums <= 0)
    error('build_lookahead_transition_intensity_h2:BadRowSum', ...
        'Intensity transition matrix has non-positive row sum.');
end
P = P ./ rowSums;

rows = {};
nA = size(P, 1);
for fromA = 1:nA
    for toA = 1:nA
        p = P(fromA, toA);
        if p > 0
            rows(end + 1, :) = {fromA, toA, p}; %#ok<AGROW>
        end
    end
end
transTbl = cell2table(rows, 'VariableNames', {'from_a', 'to_a', 'prob'});

checkRows = {};
for fromA = 1:nA
    rowsA = transTbl(transTbl.from_a == fromA, :);
    probSum = sum(rowsA.prob);
    if abs(probSum - 1) <= 1e-8
        status = "OK";
    else
        status = "BAD_PROB_SUM";
    end
    checkRows(end + 1, :) = {fromA, probSum, height(rowsA), ...
        min(rowsA.to_a), max(rowsA.to_a), char(status)}; %#ok<AGROW>
end
checkTbl = cell2table(checkRows, 'VariableNames', ...
    {'from_a', 'prob_sum', 'nonzero_to_count', ...
    'min_to_a', 'max_to_a', 'status'});
end
