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

config = struct();
config.rootDir = rootDir;
config.moduleDir = moduleDir;
config.outputDir = fullfile(moduleDir, 'output', ...
    'stage2_foundation_yStep_calibration');
config.locCoordinateFile = fullfile(moduleDir, 'output', ...
    'stage2_foundation_audit', 'loc_lf_coordinate_table.csv');
config.pathTableFile = fullfile(moduleDir, 'output', ...
    'stage2_lookahead_W3', 'lookahead_path_table.csv');
config.nearInputFile = fullfile(rootDir, 'data', 'yuanqi', ...
    'near_stage_msp_input.mat');
config.roadEdgeFile = fullfile(rootDir, 'data', 'yuanqi', ...
    'stage1_road_edges.csv');
config.siteNodeFile = fullfile(rootDir, 'data', 'yuanqi', ...
    'stage1_site_nodes.csv');

config.candidateMultipliers = [0.5, 1, 1.5, 2, 3, 4];
config.aValues = 2:6;
config.tauValues = 1:3;
config.yDirection = 1;
config.yBaseMode = 'path_table_median';
config.windDecayB = 0.6;
config.designWindSpeedVN = 25;
config.roadDesignWindVN = 30;

if ~exist(config.outputDir, 'dir')
    mkdir(config.outputDir);
end

result = calibrate_lookahead_y_step_h2(config);
write_y_step_calibration_diagnostics_h2(result, config);

fprintf('\nStage2 foundation y-step calibration finished.\n');
fprintf('Status: %s\n', result.status);
fprintf('Output directory:\n%s\n', config.outputDir);
