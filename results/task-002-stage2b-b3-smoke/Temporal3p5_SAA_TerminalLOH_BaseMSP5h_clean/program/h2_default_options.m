function opts = h2_default_options(rootDir)
%H2_DEFAULT_OPTIONS Default options for the H2 FA-MSP near-disaster run.

if nargin < 1 || isempty(rootDir)
    rootDir = pwd;
end

dataDir = fullfile(rootDir, 'data');

opts = struct();
opts.rootDir = rootDir;
opts.dataDir = dataDir;
opts.nearInputFile = fullfile(dataDir, 'yuanqi', 'near_stage_msp_input.mat');
opts.beta_template_file = fullfile(dataDir, 'yuanqi', 'beta_template_v2.csv');
opts.terminal_impact_template_file = fullfile(dataDir, 'yuanqi', 'terminal_impact_template.csv');
opts.outputDir = fullfile(rootDir, 'output_h2');

% Canonical Stage89Q Base initial state; candidate overrides are explicit.
opts.k_init = 81;
opts.nbOS = 10000;
opts.max_iter = 100000;
opts.stall = 500;
opts.cutviol_maxiter = 100000;
opts.time_limit = 3600;
opts.eps_tol = 1e-5;

opts.normal_demand_mode = 'repeat_template';
opts.electricity_price_mode = 'stage_average_repeat_hourly';
opts.terminal_load_mode = 'node_load';
opts.terminal_loh_mode = 'legacy';
opts.terminal_loh_lookup_file = '';

opts.beta_enabled = true;
opts.use_beta_capacity = true;
opts.use_beta_cost = true;
opts.normal_shortage_penalty_multiplier = 1;
opts.htt_base_service_cost_yuan_per_kg = 0;

opts.allow_incomplete_beta_template = false;
opts.allow_default_terminal_impact = false;
opts.use_tank_min = false;
opts.store_eval_decisions = false;

% Hourly IEEE-33 coupling is opt-in.  The accepted legacy path remains the
% default and does not load or build any grid variables.
opts.enable_hourly_grid = false;
opts.hourly_grid_vmin_pu = 0.90;
opts.hourly_grid_vmax_pu = 1.10;

opts.runTraining = true;
opts.runEvaluation = true;
opts.regenOOS = false;
opts.runDualCheck = false;
opts.runSelectedPathDiagnostics = true;
opts.numDiagnosticPaths = 6;
opts.exportDiagnosticFigures = false;

opts.seed = 20260513;
end
