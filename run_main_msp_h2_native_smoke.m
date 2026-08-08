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

runDir = fullfile(rootDir, 'results', 'task-002-stage2b-b3-smoke', ...
    '55-main-msp-native-smoke', char(runId));
nativeOutputDir = fullfile(runDir, 'native_output');
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

result = run_h2_with_options(opts); %#ok<NASGU>
