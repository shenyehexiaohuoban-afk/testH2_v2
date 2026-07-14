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
    'stage2_foundation_warning100_Rmax30_40_50_Wstep_sweep');
config.locCoordinateFile = fullfile(moduleDir, 'output', ...
    'stage2_foundation_audit', 'loc_lf_coordinate_table.csv');
config.nearInputFile = fullfile(rootDir, 'data', 'yuanqi', ...
    'near_stage_msp_input.mat');
config.roadEdgeFile = fullfile(rootDir, 'data', 'yuanqi', ...
    'stage1_road_edges.csv');
config.siteNodeFile = fullfile(rootDir, 'data', 'yuanqi', ...
    'stage1_site_nodes.csv');

config.warningDistanceKmEq = 100;
config.RmaxValues = [30, 40, 50];
config.WstepValues = [30, 35, 40, 45, 50];
config.stageNames = {'lf7', 'W1', 'W2', 'W3'};
config.stageOffsets = [0, 1, 2, 3];
config.aValues = 2:6;
config.windDecayB = 0.6;
config.designWindSpeedVN = 25;
config.roadDesignWindVN = 30;

if ~exist(config.outputDir, 'dir')
    mkdir(config.outputDir);
end

result = evaluate_warning_Rmax_Wstep_candidate_h2(config);
write_warning_Rmax_Wstep_diagnostics_h2(result, config);

fprintf('\nStage2 warning-distance Rmax/Wstep sweep finished.\n');
fprintf('Output directory:\n%s\n', config.outputDir);
fprintf('Solved y_base = %.12g\n', result.y_base_solution.y_base);
if ~isempty(result.candidate_ranking)
    fprintf('Recommended Wstep = %.12g\n', result.candidate_ranking.Wstep(1));
end
