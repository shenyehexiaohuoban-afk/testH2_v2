function write_oos_readme(runDir, rootDir, sourceRun, oosFile, nOS, direct, recourse, delta, directElapsed, recourseElapsed)
fid = fopen(fullfile(runDir, 'README.md'), 'w', 'n', 'UTF-8');
if fid < 0
    error('Stage90B2OOS:Write', 'Cannot write README.');
end

function out = relative_path(rootDir, path)
path = char(string(path));
rootDir = char(string(rootDir));
if startsWith(path, rootDir)
    out = strrep(path(numel(rootDir)+2:end), '\\', '/');
else
    out = path;
end
end
c = onCleanup(@() fclose(fid)); %#ok<NASGU>
nl = char(10);
fprintf(fid, ['# Stage90B2 paired OOS evaluation' nl nl]);
fprintf(fid, ['- Read-only evaluation of saved run-004; no retraining or parameter changes.' nl]);
fprintf(fid, '- Same first %d rows of `%s` evaluated under TERMINAL_REDISTRIBUTION and DIRECT_GAP.%s', nOS, relative_path(rootDir, oosFile), nl);
fprintf(fid, ['- This compares evaluators for the same recourse-trained policy; it is not a separately trained DIRECT_GAP baseline.' nl nl]);
fprintf(fid, 'DIRECT_GAP mean = %.12g yuan/path; TERMINAL_REDISTRIBUTION mean = %.12g yuan/path; paired mean direct-minus-recourse = %.12g yuan/path.%s', direct.oos_mean, recourse.oos_mean, mean(delta), nl);
fprintf(fid, 'Recourse-better paths = %d/%d (%.6f); recourse-worse paths = %d; equal paths = %d.%s', sum(delta > 1e-7), nOS, mean(delta > 1e-7), sum(delta < -1e-7), sum(abs(delta) <= 1e-7), nl);
fprintf(fid, 'Recourse average terminal gap = %.12g kg/path; average physical shipping = %.12g yuan/path; recourse elapsed %.3fs; direct elapsed %.3fs.%s', recourse.avg_terminal_reserve_shortage, mean(sum(recourse.terminal_redistribution_cost,2)), recourseElapsed, directElapsed, nl);
fprintf(fid, 'Source run: `%s`.%s', relative_path(rootDir, sourceRun), nl);
end
