clear; clc;

rootDir = fileparts(mfilename('fullpath'));
if isempty(rootDir)
    rootDir = pwd;
end

opts = h2_default_options(rootDir);

% Daily main-version overrides. Keep ablation settings in run_h2_ablation_suite.m.
opts.time_limit = 3600;
opts.terminal_load_mode = 'node_load';
opts.beta_enabled = true;
opts.normal_shortage_penalty_multiplier = 1;
opts.outputDir = fullfile(rootDir, 'output_h2');

result = run_h2_with_options(opts); %#ok<NASGU>
