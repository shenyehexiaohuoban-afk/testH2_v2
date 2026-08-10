clear; clc;

rootDir = fileparts(mfilename('fullpath'));
if isempty(rootDir)
    rootDir = pwd;
end

runId = string(getenv('STEP05B_RUN_ID'));
if strlength(runId) == 0 || isempty(regexp(char(runId), '^run-\d{3}$', 'once'))
    error('run_main_msp_h2_converged_ab:BadRunId', ...
        'Set STEP05B_RUN_ID to a fresh run-xxx value.');
end

terminalMode = lower(string(getenv('STEP05B_TERMINAL_MODE')));
if ~ismember(terminalMode, ["saa", "chi2_eta003"])
    error('run_main_msp_h2_converged_ab:BadTerminalMode', ...
        'STEP05B_TERMINAL_MODE must be saa or chi2_eta003.');
end

runDir = fullfile(rootDir, 'results', 'task-002-stage2b-b3-smoke', ...
    '57-main-msp-converged-terminal-loh-ab', char(runId));
nativeOutputDir = fullfile(runDir, "case-" + terminalMode, 'native_output');
if exist(nativeOutputDir, 'dir')
    error('run_main_msp_h2_converged_ab:OutputExists', ...
        'Refusing to overwrite existing formal output: %s', nativeOutputDir);
end

opts = h2_default_options(rootDir);
if opts.seed ~= 20260513
    error('run_main_msp_h2_converged_ab:SeedDrift', ...
        'Expected frozen native seed 20260513, got %.0f.', opts.seed);
end

% Formal native stopping logic is unchanged. These are safety ceilings only;
% an accepted Step-05B case must finish with stop_flag=4 (LB stall criterion).
opts.time_limit = 86400;
opts.max_iter = 100000;
opts.stall = 500;
opts.eps_tol = 1e-5;
opts.cutviol_maxiter = 100000;

opts.outputDir = nativeOutputDir;
opts.oosFile = fullfile(rootDir, 'output_h2', 'details', 'h2_OOS.csv');
opts.regenOOS = false;
if ~isfile(opts.oosFile)
    error('run_main_msp_h2_converged_ab:MissingFrozenOOS', ...
        'Missing protected common OOS input: %s', opts.oosFile);
end

lookupRoot = fullfile(rootDir, 'results', 'task-002-stage2b-b3-smoke', ...
    '53-35state-saa-vs-eta003-terminal-loh', 'run-024');
opts.terminal_loh_mode = char(terminalMode);
if terminalMode == "saa"
    opts.terminal_loh_lookup_file = fullfile(lookupRoot, ...
        'terminal_loh_table_saa.csv');
else
    opts.terminal_loh_lookup_file = fullfile(lookupRoot, ...
        'terminal_loh_table_eta_003.csv');
end
opts.allow_zero_terminal_loh = true;

result = run_h2_with_options(opts);
if result.trainInfo.stop_flag ~= 4
    error('run_main_msp_h2_converged_ab:NotConverged', ...
        ['Formal training did not stop by the accepted LB-stall criterion. ' ...
        'stop_flag=%d, iter=%d, elapsed=%.6f s.'], ...
        result.trainInfo.stop_flag, result.trainInfo.iter, ...
        result.trainInfo.train_time);
end
if ~(isfinite(result.trainInfo.relative_gap) && ...
        result.trainInfo.relative_gap < opts.eps_tol)
    error('run_main_msp_h2_converged_ab:BadConvergenceCertificate', ...
        'Stored relative gap %.12g does not satisfy eps_tol %.12g.', ...
        result.trainInfo.relative_gap, opts.eps_tol);
end
