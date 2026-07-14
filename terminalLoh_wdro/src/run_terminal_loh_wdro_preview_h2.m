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

config = struct();
config.rootDir = rootDir;
config.moduleDir = moduleDir;
config.inputCsv = fullfile(rootDir, 'output_h2', ...
    'wind_terminal_loh_preview', 'riskcap_mean', ...
    'joint_scenario_site_node.csv');
config.nearInputFile = fullfile(rootDir, 'data', 'yuanqi', ...
    'near_stage_msp_input.mat');
config.siteInputCsv = fullfile(rootDir, 'data', 'yuanqi', ...
    'near_stage_msp_site_input.csv');

config.rho_list = [0, 0.02, 0.05, 0.10];
config.outputDir = fullfile(moduleDir, 'output', ...
    'stage1_single_window_DA_update');
config.distance_modes = {'D_only', 'DA', 'DAC_maskedC'};
config.capacity_fraction = 0.8;
config.gamma = [];
config.saveAllocation = true;

config.distanceWeights = struct('D', 0.6, 'A', 0.2, 'C', 0.2);
config.distanceWeightsDA = struct('D', 0.7, 'A', 0.3, 'C', 0);
config.distanceWeightsDACMaskedC = struct('D', 0.6, 'A', 0.25, 'C', 0.15);
config.epsDistance = 1e-9;
config.scaleTolerance = 1e-12;
config.gurobiOutputFlag = 0;
config.gurobiTimeLimit = [];

gurobiHome = getenv('GUROBI_HOME');
gurobiMatlabCandidates = {};
if ~isempty(gurobiHome)
    gurobiMatlabCandidates{end + 1} = fullfile(gurobiHome, 'matlab'); %#ok<SAGROW>
end
gurobiMatlabCandidates{end + 1} = fullfile('D:\', 'gurobi1201', 'win64', 'matlab');
gurobiMatlabCandidates{end + 1} = fullfile('C:\', 'gurobi1201', 'win64', 'matlab');
for cc = 1:numel(gurobiMatlabCandidates)
    if exist(gurobiMatlabCandidates{cc}, 'dir')
        addpath(gurobiMatlabCandidates{cc});
    end
end

if ~ismember(exist('gurobi', 'file'), [2, 3])
    error('run_terminal_loh_wdro_preview_h2:MissingGurobi', ...
        ['Gurobi MATLAB function was not found on the MATLAB path. ' ...
        'This WDRO prototype requires Gurobi; no linprog fallback is implemented.']);
end

result = build_terminal_loh_wdro_from_joint_samples_h2(config); %#ok<NASGU>

fprintf('\nWDRO TerminalLOH offline preview finished.\n');
fprintf('Output directory:\n%s\n', config.outputDir);
