clear; clc;

rootDir = fileparts(mfilename('fullpath'));
if isempty(rootDir)
    rootDir = pwd;
end

runId = string(getenv('STEP05B_RUN_ID'));
if strlength(runId) == 0 || isempty(regexp(char(runId), '^run-\d{3}$', 'once'))
    error('run_main_msp_h2_fixed_budget_ab:BadRunId', ...
        'Set STEP05B_RUN_ID to a fresh run-xxx value.');
end

terminalMode = lower(string(getenv('STEP05B_TERMINAL_MODE')));
if ~ismember(terminalMode, ["saa", "chi2_eta003"])
    error('run_main_msp_h2_fixed_budget_ab:BadTerminalMode', ...
        'STEP05B_TERMINAL_MODE must be saa or chi2_eta003.');
end

runDir = fullfile(rootDir, 'results', 'task-002-stage2b-b3-smoke', ...
    '57-main-msp-converged-terminal-loh-ab', char(runId));
nativeOutputDir = fullfile(runDir, "case-" + terminalMode, 'native_output');
if exist(nativeOutputDir, 'dir')
    error('run_main_msp_h2_fixed_budget_ab:OutputExists', ...
        'Refusing to overwrite existing output: %s', nativeOutputDir);
end

opts = h2_default_options(rootDir);
if opts.seed ~= 20260513
    error('run_main_msp_h2_fixed_budget_ab:SeedDrift', ...
        'Expected frozen native seed 20260513, got %.0f.', opts.seed);
end

% User-authorized fixed-budget comparison matching the historical native
% main entry. This intentionally reports stop_flag=2 and must not be called
% a formal convergence result.
opts.time_limit = 3600;
opts.max_iter = 100000;
opts.stall = 500;
opts.eps_tol = 1e-5;
opts.cutviol_maxiter = 100000;

opts.outputDir = nativeOutputDir;
opts.oosFile = fullfile(rootDir, 'output_h2', 'details', 'h2_OOS.csv');
opts.regenOOS = false;
if ~isfile(opts.oosFile)
    error('run_main_msp_h2_fixed_budget_ab:MissingFrozenOOS', ...
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
if result.trainInfo.stop_flag ~= 2
    error('run_main_msp_h2_fixed_budget_ab:UnexpectedStop', ...
        ['Fixed-budget training was expected to stop at the native 3600 s ' ...
        'time limit. stop_flag=%d, iter=%d, elapsed=%.6f s.'], ...
        result.trainInfo.stop_flag, result.trainInfo.iter, ...
        result.trainInfo.train_time);
end
