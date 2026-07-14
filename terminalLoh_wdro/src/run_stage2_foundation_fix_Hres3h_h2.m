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
    'stage2_foundation_fix_Hres3h_Wstep40_reaudit');
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
config.RmaxValues = [30, 40, 50];
config.RmaxRef = 40;
config.WstepValues = [40, 45];
config.recommendedWstep = 40;
config.comparisonWstep = 45;
config.W = 3;
config.sliceDurationH = 1;
config.HresTotalH = 3;
config.stageNames = ["lf7", "W1", "W2", "W3"];
config.stageOffsets = [0, 1, 2, 3];
config.aValues = 2:6;
config.smokeAValues = [4, 6];
config.smokeLocValues = [0, 3, 10];
config.mcCount = 200;
config.mcSeed = 20260713;
config.windDecayB = 0.6;
config.designWindSpeedVN = 25;
config.roadDesignWindVN = 30;
config.roadSlowdownLambda = 1.0;
config.slowRoadPCloseThreshold = 1e-6;
config.sourceNode = 1;
config.distanceMethod = "point_to_segment";

config.protectedOutputDirs = {
    fullfile(moduleDir, 'output', 'stage2_lookahead_W3'), ...
    fullfile(moduleDir, 'output', 'stage2_lookahead_W3_B1_DAC_samples'), ...
    fullfile(moduleDir, 'output', 'stage2_lookahead_W3_B2_DAC_samples_R200'), ...
    fullfile(moduleDir, 'output', 'stage2_foundation_audit'), ...
    fullfile(moduleDir, 'output', 'stage2_foundation_yStep_calibration'), ...
    config.warningSweepDir};

if isfolder(config.outputDir)
    existing = dir(config.outputDir);
    existing = existing(~ismember({existing.name}, {'.', '..'}));
    if ~isempty(existing)
        error('run_stage2_foundation_fix_Hres3h_h2:OutputExists', ...
            'Refusing to overwrite nonempty output directory: %s', ...
            config.outputDir);
    end
else
    mkdir(config.outputDir);
end

protectedBefore = snapshot_protected_outputs(config.protectedOutputDirs);
foundation = build_foundation_fix_coordinates_h2(config);
result = evaluate_foundation_fix_chain_h2(config, foundation);
[comparisonTbl, recommendation] = compare_Wstep40_45_foundation_h2( ...
    result, config);
checksTbl = run_stage2_foundation_reaudit_h2(result, foundation, ...
    comparisonTbl, recommendation, config, protectedBefore);

result.comparison = comparisonTbl;
result.recommendation = recommendation;
result.reaudit_checks = checksTbl;
write_foundation_fix_diagnostics_h2(result, foundation, config);

fprintf('\nStage2 Foundation Fix Hres3h re-audit finished.\n');
fprintf('Output directory:\n%s\n', config.outputDir);
fprintf('Verified y_base = %.12g\n', foundation.y_base);
fprintf('Smoke MC count = %d, seed = %d\n', ...
    config.mcCount, config.mcSeed);
fprintf('Recommendation status: %s\n', recommendation.status);

function snap = snapshot_protected_outputs(paths)
snap = table(strings(numel(paths), 1), zeros(numel(paths), 1), ...
    zeros(numel(paths), 1), 'VariableNames', ...
    {'path', 'file_count', 'latest_datenum'});
for ii = 1:numel(paths)
    p = paths{ii};
    snap.path(ii) = string(p);
    if ~isfolder(p)
        snap.file_count(ii) = -1;
        snap.latest_datenum(ii) = NaN;
        continue;
    end
    items = dir(fullfile(p, '**', '*'));
    items = items(~[items.isdir]);
    snap.file_count(ii) = numel(items);
    if isempty(items)
        snap.latest_datenum(ii) = 0;
    else
        snap.latest_datenum(ii) = max([items.datenum]);
    end
end
end
