clear; clc;

thisDir = fileparts(mfilename('fullpath'));
moduleDir = fileparts(thisDir);
rootDir = fileparts(moduleDir);
if isempty(rootDir) || isempty(moduleDir)
    rootDir = pwd;
    moduleDir = fullfile(rootDir, 'terminalLoh_wdro');
end

addpath(rootDir);
addpath(thisDir);
addpath(fullfile(rootDir, 'fa_h2'));
addpath(fullfile(rootDir, 'fa_h2', 'fuzhu'));
addpath(fullfile(rootDir, 'fa_h2', 'fuzhu', 'terminalLoh_windmc'));
addpath(fullfile(rootDir, 'utils'));

config = struct();
config.rootDir = rootDir;
config.moduleDir = moduleDir;
config.inputPathTable = fullfile(moduleDir, 'output', ...
    'stage2_lookahead_W3', 'lookahead_path_table.csv');
config.windowConfigFile = fullfile(moduleDir, 'config', ...
    'lookahead_window_W3.csv');
config.locationConfigFile = fullfile(moduleDir, 'config', ...
    'lookahead_location_W3.csv');
config.intensityConfigFile = fullfile(moduleDir, 'config', ...
    'lookahead_intensity_W3.csv');
config.outputDir = fullfile(moduleDir, 'output', ...
    'stage2_lookahead_W3_B2_DAC_samples_R200');
config.docsDir = fullfile(moduleDir, 'docs');

config.stage_label = 'B2';
config.P_B2 = 20;
config.M_B2 = 10;
config.P = config.P_B2;
config.M = config.M_B2;
config.random_seed_B2 = 20260708;
config.random_seed = config.random_seed_B2;
config.pathSelectionMode = 'random_if_needed';
config.windDecayB = 0.6;
config.designWindSpeedVN = 25;
config.roadDesignWindVN = 30;
config.roadSlowdownLambda = 1.0;
config.serviceRadiusPenalty = 1.0;
config.serviceTimeLimit = 60;
config.slowRoadPCloseThreshold = 1e-6;
config.demandToleranceKg = 1e-9;

if ~exist(config.outputDir, 'dir'); mkdir(config.outputDir); end
if ~exist(config.docsDir, 'dir'); mkdir(config.docsDir); end

result = build_lookahead_W3_DAC_samples_h2(config);
diagB2 = write_lookahead_W3_B2_diagnostics_h2( ...
    result.site_node, result.summary, config, result); %#ok<NASGU>

fprintf('\nStage 2B2 W=3 D/A/C R=200 samples finished.\n');
fprintf('Output directory:\n%s\n', config.outputDir);
