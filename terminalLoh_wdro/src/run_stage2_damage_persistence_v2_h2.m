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
addpath(fullfile(rootDir, 'fa_h2', 'fuzhu', 'terminalLoh_windmc'));

config = struct();
config.rootDir = rootDir;
config.moduleDir = moduleDir;
config.outputDir = fullfile(moduleDir, 'output', ...
    'stage2_damage_persistence_v2');
config.warningSweepDir = fullfile(moduleDir, 'output', ...
    'stage2_foundation_warning100_Rmax30_40_50_Wstep_sweep');
config.warningSolutionFile = fullfile(config.warningSweepDir, ...
    'warning_y_base_solution.csv');
config.warningGeometryFile = fullfile(config.warningSweepDir, ...
    'warning_geometry_by_loc.csv');
config.warningRankingFile = fullfile(config.warningSweepDir, ...
    'Wstep_candidate_ranking.csv');
config.warningStageSummaryFile = fullfile(config.warningSweepDir, ...
    'Rmax_Wstep_stage_summary.csv');
config.warningDiagnosticsFile = fullfile(config.warningSweepDir, ...
    'diagnostics_summary.txt');
config.warningRankingSourceFile = fullfile(thisDir, ...
    'rank_Wstep_candidates_h2.m');
config.locCoordinateFile = fullfile(moduleDir, 'output', ...
    'stage2_foundation_audit', 'loc_lf_coordinate_table.csv');
config.nearInputFile = fullfile(rootDir, 'data', 'yuanqi', ...
    'near_stage_msp_input.mat');
config.roadEdgeFile = fullfile(rootDir, 'data', 'yuanqi', ...
    'stage1_road_edges.csv');
config.siteNodeFile = fullfile(rootDir, 'data', 'yuanqi', ...
    'stage1_site_nodes.csv');

config.warningDistanceKmEq = 100;
config.WstepValues = 40;
config.recommendedWstep = 40;
config.comparisonWstep = 45;
config.Wstep = config.WstepValues(1);
config.stageNames = ["lf7", "W1", "W2", "W3"];
config.stageOffsets = [0, 1, 2, 3];
config.damageStageNames = ["W1", "W2", "W3"];
config.damageStageOffsets = [1, 2, 3];
config.damageModes = ["independent_snapshot", ...
    "persistent_independent_draws", "persistent_fixed_resistance"];
config.RmaxValues = [30, 40, 50];
config.aValues = [4, 6];
config.locValues = [0, 3, 10];
config.W = 3;
config.sliceDurationH = 1;
config.HresTotalH = 3;
config.Nmc = 200;
config.rngSeed = 20260716;
config.windDecayB = 0.6;
config.designWindSpeedVN = 25;
config.roadDesignWindVN = 30;
config.roadSlowdownLambda = 1.0;
config.slowRoadThreshold = 1e-6;
config.sourceNode = 1;
config.distanceMethod = "point_to_segment";
config.CDefinition = "dist(n)";
config.fullLossTolerance = 1e-9;
config.massSaturationThreshold = 0.5;
config.stageDistinctionThreshold = 0.05;
config.overestimateThreshold = 0.05;

config.protectedOutputDirs = {
    fullfile(moduleDir, 'output', 'stage2_lookahead_W3'), ...
    fullfile(moduleDir, 'output', 'stage2_lookahead_W3_B1_DAC_samples'), ...
    fullfile(moduleDir, 'output', 'stage2_lookahead_W3_B2_DAC_samples_R200'), ...
    fullfile(moduleDir, 'output', 'stage2_foundation_audit'), ...
    fullfile(moduleDir, 'output', 'stage2_foundation_yStep_calibration'), ...
    config.warningSweepDir, ...
    fullfile(moduleDir, 'output', 'stage2_foundation_fix_Hres3h_Wstep40_reaudit'), ...
    fullfile(moduleDir, 'output', 'stage2_foundation_fix_Hres3h_Wstep40_reaudit_v2'), ...
    fullfile(moduleDir, 'output', 'stage2_damage_persistence_smoke')};
config.protectedMSPFiles = {
    fullfile(rootDir, 'main_msp_h2_near.m'), ...
    fullfile(rootDir, 'h2_default_options.m'), ...
    fullfile(rootDir, 'run_h2_with_options.m'), ...
    fullfile(rootDir, 'run_h2_ablation_suite.m'), ...
    fullfile(rootDir, 'load_data_h2_near.m'), ...
    fullfile(rootDir, 'fa_h2', 'build_stage_model_h2.m'), ...
    fullfile(rootDir, 'fa_h2', 'update_rhs_h2.m'), ...
    fullfile(rootDir, 'fa_h2', 'solve_stage_model_h2.m'), ...
    fullfile(rootDir, 'fa_h2', 'forward_pass_h2.m'), ...
    fullfile(rootDir, 'fa_h2', 'backward_pass_h2.m'), ...
    fullfile(rootDir, 'fa_h2', 'add_cut_h2.m'), ...
    fullfile(rootDir, 'fa_h2', 'train_models_h2.m'), ...
    fullfile(rootDir, 'fa_h2', 'eval_h2.m'), config.nearInputFile};
config.executedSourceFiles = {
    fullfile(thisDir, 'run_stage2_damage_persistence_v2_h2.m'), ...
    fullfile(thisDir, 'evaluate_fixed_resistance_damage_h2.m'), ...
    fullfile(thisDir, 'compare_damage_persistence_modes_v2_h2.m'), ...
    fullfile(thisDir, 'write_damage_persistence_v2_diagnostics_h2.m')};

if isfolder(config.outputDir)
    existing = dir(config.outputDir);
    existing = existing(~ismember({existing.name}, {'.', '..'}));
    if ~isempty(existing)
        error('run_stage2_damage_persistence_v2_h2:OutputExists', ...
            'Refusing to overwrite nonempty output directory: %s', ...
            config.outputDir);
    end
else
    mkdir(config.outputDir);
end

config.protectedOutputBefore = snapshot_directories(config.protectedOutputDirs);
config.protectedMSPBefore = snapshot_files(config.protectedMSPFiles);
foundation = build_foundation_fix_coordinates_h2(config);
result = evaluate_fixed_resistance_damage_h2(config, foundation);
[hresTbl, comparisonTbl, stateSaturationTbl, roadACTbl, checksTbl, diagnostics] = ...
    compare_damage_persistence_modes_v2_h2(result, config);
write_damage_persistence_v2_diagnostics_h2(result.by_slice, hresTbl, ...
    comparisonTbl, stateSaturationTbl, roadACTbl, checksTbl, diagnostics, config);

fprintf('\nW1-W3 damage persistence v2 finished.\n');
fprintf('Output directory:\n%s\n', config.outputDir);
fprintf('Common random numbers pass: %d\n', diagnostics.common_random_numbers_pass);
fprintf('Fixed-threshold reuse pass: %d\n', diagnostics.fixed_threshold_reuse_pass);
fprintf('Formal-B3 recommendation: %s\n', diagnostics.B3_recommendation);

function T = snapshot_directories(paths)
T = table(strings(numel(paths), 1), zeros(numel(paths), 1), ...
    zeros(numel(paths), 1), zeros(numel(paths), 1), ...
    'VariableNames', {'path', 'file_count', 'latest_datenum', 'total_bytes'});
for ii = 1:numel(paths)
    T.path(ii) = string(paths{ii});
    if ~isfolder(paths{ii})
        T.file_count(ii) = -1;
        T.latest_datenum(ii) = NaN;
        T.total_bytes(ii) = -1;
        continue;
    end
    items = dir(fullfile(paths{ii}, '**', '*'));
    items = items(~[items.isdir]);
    T.file_count(ii) = numel(items);
    if isempty(items)
        T.latest_datenum(ii) = 0;
        T.total_bytes(ii) = 0;
    else
        T.latest_datenum(ii) = max([items.datenum]);
        T.total_bytes(ii) = sum([items.bytes]);
    end
end
end

function T = snapshot_files(paths)
T = table(strings(numel(paths), 1), false(numel(paths), 1), ...
    zeros(numel(paths), 1), zeros(numel(paths), 1), ...
    'VariableNames', {'path', 'exists', 'datenum', 'bytes'});
for ii = 1:numel(paths)
    T.path(ii) = string(paths{ii});
    T.exists(ii) = isfile(paths{ii});
    if T.exists(ii)
        info = dir(paths{ii});
        T.datenum(ii) = info.datenum;
        T.bytes(ii) = info.bytes;
    else
        T.datenum(ii) = NaN;
        T.bytes(ii) = -1;
    end
end
end
