clear; clc;

rootDir = fileparts(mfilename('fullpath'));
if isempty(rootDir)
    rootDir = pwd;
end

runId = string(getenv('STEP05A0B_RUN_ID'));
if strlength(runId) == 0 || isempty(regexp(char(runId), '^run-\d{3}$', 'once'))
    error('run_main_msp_h2_native_smoke:BadRunId', ...
        'Set STEP05A0B_RUN_ID to a fresh run-xxx value.');
end

terminalMode = lower(string(getenv('STEP05A1_TERMINAL_MODE')));
if strlength(terminalMode) == 0
    runDir = fullfile(rootDir, 'results', 'task-002-stage2b-b3-smoke', ...
        '55-main-msp-native-smoke', char(runId));
    nativeOutputDir = fullfile(runDir, 'native_output');
elseif ismember(terminalMode, ["saa", "chi2_eta003"])
    runDir = fullfile(rootDir, 'results', 'task-002-stage2b-b3-smoke', ...
        '56-main-msp-dual-terminal-loh-smoke', char(runId));
    nativeOutputDir = fullfile(runDir, "case-" + terminalMode, 'native_output');
else
    error('run_main_msp_h2_native_smoke:BadTerminalMode', ...
        'STEP05A1_TERMINAL_MODE must be saa or chi2_eta003.');
end
if exist(nativeOutputDir, 'dir')
    error('run_main_msp_h2_native_smoke:OutputExists', ...
        'Refusing to overwrite existing smoke output: %s', nativeOutputDir);
end

opts = h2_default_options(rootDir);
if opts.seed ~= 20260513
    error('run_main_msp_h2_native_smoke:SeedDrift', ...
        'Expected frozen native seed 20260513, got %.0f.', opts.seed);
end

opts.time_limit = 300;
opts.outputDir = nativeOutputDir;
opts.oosFile = fullfile(rootDir, 'output_h2', 'details', 'h2_OOS.csv');
if ~isfile(opts.oosFile)
    error('run_main_msp_h2_native_smoke:MissingFrozenOOS', ...
        'Missing protected native OOS input: %s', opts.oosFile);
end

if strlength(terminalMode) > 0
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
    % The frozen C6 lookup tables intentionally contain an exact-zero
    % state7 negative control. This existing validation permission changes
    % no model equation and is identical in both Step-05A1 smoke cases.
    opts.allow_zero_terminal_loh = true;
end

result = run_h2_with_options(opts); %#ok<NASGU>
