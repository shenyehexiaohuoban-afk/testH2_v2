function summaryTbl = write_lookahead_path_diagnostics_h2(pathTbl, locExtTbl, config)
%WRITE_LOOKAHEAD_PATH_DIAGNOSTICS_H2 Build summary and README for W3 paths.

origLocs = locExtTbl.loc_id(locExtTbl.is_original == 1);
locMin = min(origLocs);
locMax = max(origLocs);

stateTbl = unique(pathTbl(:, {'a0', 'loc0', 'lf'}), 'rows', 'stable');
rows = {};
for ss = 1:height(stateTbl)
    a0 = stateTbl.a0(ss);
    loc0 = stateTbl.loc0(ss);
    lf = stateTbl.lf(ss);
    stateRows = pathTbl(pathTbl.a0 == a0 & pathTbl.loc0 == loc0 & ...
        pathTbl.lf == lf, :);
    terminalRows = stateRows(stateRows.tau == config.W, :);
    rows(end + 1, :) = {a0, loc0, lf, config.P, config.W, ...
        numel(unique(stateRows.path_id)), ...
        sum(stateRows.loc_tau < locMin), ...
        sum(stateRows.loc_tau > locMax), ...
        sum(stateRows.loc_tau >= locMin & stateRows.loc_tau <= locMax), ...
        numel(unique(terminalRows.loc_tau)), min(terminalRows.loc_tau), ...
        max(terminalRows.loc_tau), min(terminalRows.a_tau), ...
        max(terminalRows.a_tau)}; %#ok<AGROW>
end

summaryTbl = cell2table(rows, 'VariableNames', ...
    {'a0', 'loc0', 'lf', 'P', 'W', 'path_count', ...
    'left_halo_visit_count', 'right_halo_visit_count', ...
    'internal_loc_visit_count', 'unique_terminal_loc_count', ...
    'terminal_loc_min', 'terminal_loc_max', 'terminal_a_min', ...
    'terminal_a_max'});

readmeFile = fullfile(config.outputDir, 'lookahead_path_readme.txt');
fid = fopen(readmeFile, 'w');
if fid < 0
    error('write_lookahead_path_diagnostics_h2:ReadmeOpenFailed', ...
        'Could not open lookahead_path_readme.txt.');
end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'Stage 2A W=3 look-ahead typhoon path generation\n\n');
fprintf(fid, '1. This stage only generates W=3 future typhoon paths.\n');
fprintf(fid, '2. It has not sampled electric-grid or road disasters.\n');
fprintf(fid, '3. It has not generated D,A,C consequence samples.\n');
fprintf(fid, '4. It has not run WDRO.\n');
fprintf(fid, '5. loc extension is only for WDRO look-ahead path generation.\n');
fprintf(fid, '6. It does not modify the original MSP state space.\n');
fprintf(fid, '7. It does not use artificial impact decay coefficients.\n');
fprintf(fid, '8. W is represented by tau/window_id and is not the original MSP lf.\n\n');
fprintf(fid, 'Settings: W=%d, P=%d, random_seed=%d.\n', ...
    config.W, config.P, config.random_seed);
fprintf(fid, 'Path rows: %d.\n', height(pathTbl));
fprintf(fid, 'State rows: %d.\n', height(summaryTbl));
fprintf(fid, 'Left halo visits: %d.\n', sum(summaryTbl.left_halo_visit_count));
fprintf(fid, 'Right halo visits: %d.\n', sum(summaryTbl.right_halo_visit_count));
end
