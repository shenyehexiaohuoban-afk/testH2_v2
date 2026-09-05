function opts = base_reference_options_h2(rootDir)
%BASE_REFERENCE_OPTIONS_H2 Canonical Stage89Q Base program options.

if nargin < 1 || isempty(rootDir)
    rootDir = fileparts(mfilename('fullpath'));
end

opts = h2_default_options(rootDir);
% Canonical Stage89Q Base initial state; candidates may override explicitly.
opts.k_init = 81;
opts.nearInputFile = fullfile(rootDir, 'data', 'yuanqi', ...
    'near_stage_msp_input.mat');
opts.dt_h = 8;
opts.enable_hourly_grid = true;
opts.hourly_grid_vmin_pu = 0.90;
opts.hourly_grid_vmax_pu = 1.10;
opts.use_tank_min = false;
opts.normal_demand_mode = 'repeat_template';
opts.terminal_loh_mode = 'legacy';
opts.reserve_shortage_penalty_yuan_per_kg = 1000;
opts.runTraining = false;
opts.runEvaluation = false;
opts.runSelectedPathDiagnostics = false;
opts.regenOOS = false;
opts.store_eval_decisions = false;
end
