function pathTbl = sample_lookahead_paths_W3_h2(locTransTbl, intTransTbl, locExtTbl, config)
%SAMPLE_LOOKAHEAD_PATHS_W3_H2 Sample W-step typhoon paths from lf=7 states.

rng(config.random_seed, 'twister');

nA = max([intTransTbl.from_a; intTransTbl.to_a]);
origLocIds = (config.loc_min:config.loc_max).';
nLocOrig = numel(origLocIds);
lfTerminal = config.lf_terminal;
origLocIds = sort(origLocIds(:));

rows = cell((nA - 1) * nLocOrig * config.P * config.W, 11);
rr = 0;
for a0 = 2:nA
    for locIdx = 1:numel(origLocIds)
        loc0 = origLocIds(locIdx);
        for pathId = 1:config.P
            curA = a0;
            curLoc = loc0;
            for tau = 1:config.W
                curA = sample_next_intensity(intTransTbl, curA);
                curLoc = sample_next_loc(locTransTbl, curLoc);
                locRow = locExtTbl(locExtTbl.loc_id == curLoc, :);
                if height(locRow) ~= 1
                    error('sample_lookahead_paths_W3_h2:MissingLocRow', ...
                        'Missing loc row for loc_id=%d.', curLoc);
                end
                rr = rr + 1;
                rows(rr, :) = {a0, loc0, lfTerminal, pathId, tau, ...
                    curA, curLoc, locRow.row_id, locRow.x_coord, ...
                    locRow.y_coord, config.random_seed};
            end
        end
    end
end

pathTbl = cell2table(rows(1:rr, :), 'VariableNames', ...
    {'a0', 'loc0', 'lf', 'path_id', 'tau', 'a_tau', 'loc_tau', ...
    'loc_row_id', 'x_coord', 'y_coord', 'random_seed'});
end

function nextA = sample_next_intensity(tbl, fromA)
rows = tbl(tbl.from_a == fromA, :);
if isempty(rows)
    error('sample_lookahead_paths_W3_h2:MissingIntensityTransition', ...
        'No intensity transition rows for from_a=%d.', fromA);
end
nextA = rows.to_a(sample_discrete(rows.prob));
end

function nextLoc = sample_next_loc(tbl, fromLoc)
rows = tbl(tbl.from_loc_id == fromLoc, :);
if isempty(rows)
    error('sample_lookahead_paths_W3_h2:MissingLocTransition', ...
        'No loc transition rows for from_loc_id=%d.', fromLoc);
end
nextLoc = rows.to_loc_id(sample_discrete(rows.prob));
end

function idx = sample_discrete(prob)
p = double(prob(:));
p = p ./ sum(p);
u = rand();
idx = find(u <= cumsum(p), 1, 'first');
if isempty(idx)
    idx = numel(p);
end
end
