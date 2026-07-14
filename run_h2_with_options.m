function result = run_h2_with_options(opts)
%RUN_H2_WITH_OPTIONS Run one configured H2 FA-MSP experiment.

if nargin < 1 || isempty(opts)
    opts = h2_default_options(pwd);
elseif ~isfield(opts, 'rootDir') || isempty(opts.rootDir)
    opts = merge_options(h2_default_options(pwd), opts);
else
    opts = merge_options(h2_default_options(opts.rootDir), opts);
end

rootDir = opts.rootDir;
dataDir = opts.dataDir;
nearInputFile = opts.nearInputFile;
outputDir = opts.outputDir;
benchmarkDir = fullfile(outputDir, 'benchmark');
detailsDir = fullfile(outputDir, 'details');

if ~isfile(nearInputFile)
    error('run_h2_with_options:MissingNearInput', ...
        'Missing NearStageInput file: %s', nearInputFile);
end
if ~isfile(opts.beta_template_file)
    error('run_h2_with_options:MissingBetaTemplate', ...
        'Missing beta template file: %s', opts.beta_template_file);
end
if ~isfile(opts.terminal_impact_template_file)
    error('run_h2_with_options:MissingTerminalImpactTemplate', ...
        'Missing terminal impact template file: %s', opts.terminal_impact_template_file);
end

addpath(rootDir);
addpath(fullfile(rootDir, 'fa_h2'));
addpath(fullfile(rootDir, 'fa_h2', 'fuzhu'));
addpath(fullfile(rootDir, 'utils'));

rng(opts.seed, 'twister');

if ~exist(outputDir, 'dir'); mkdir(outputDir); end
if ~exist(benchmarkDir, 'dir'); mkdir(benchmarkDir); end
if ~exist(detailsDir, 'dir'); mkdir(detailsDir); end

params = load_data_h2_near(dataDir, nearInputFile, opts);
params.rootDir = rootDir;
params.outputDir = outputDir;
params.benchmarkDir = benchmarkDir;
params.detailsDir = detailsDir;
if isfield(opts, 'oosFile') && ~isempty(opts.oosFile)
    params.oosFile = opts.oosFile;
else
    params.oosFile = fullfile(detailsDir, 'h2_OOS.csv');
end
params.store_eval_decisions = opts.store_eval_decisions;

export_terminal_load_check_h2(params, detailsDir);
export_analysis_outputs_readme_h2(detailsDir);

fprintf('H2 T = %d\n', params.T);
fprintf('H2 K = %d\n', params.K);
fprintf('H2 Ni = %d stations\n', params.Ni);
fprintf('Number of absorbing states = %d\n', numel(params.absorbing_states));
fprintf('Max row-sum error of P_joint = %.2e\n', max(abs(sum(params.P_joint, 2) - 1)));
fprintf('Initial state S(k_init,:) = \n');
disp(params.S(params.k_init, :));

if opts.regenOOS || ~isfile(params.oosFile)
    create_oos_paths_h2(params, params.oosFile);
end
validate_oos_files_h2(params);

fprintf('\nBuilding H2 FA/MSP stage-state model library...\n');
modelLib = define_models_h2(params);

if opts.runDualCheck
    check_dual_sign_h2(modelLib, params);
end

trainInfo = struct();
evalInfo = struct();

if opts.runTraining
    fprintf('Training H2 FA/MSP policy...\n');
    [modelLib, trainInfo] = train_models_h2(modelLib, params);
end

if opts.runEvaluation
    fprintf('Evaluating trained H2 FA/MSP policy...\n');
    evalInfo = eval_h2(modelLib, params);
    evalInfo.oos_risk_metrics = compute_oos_risk_metrics_table_h2(evalInfo);
    writetable(evalInfo.oos_risk_metrics, fullfile(detailsDir, 'oos_risk_metrics.csv'));
end

selectedDiagInfo = struct();
if opts.runEvaluation && opts.runSelectedPathDiagnostics && ~isempty(fieldnames(evalInfo))
    try
        OS_paths_for_diag = readmatrix(params.oosFile);
        OS_paths_for_diag = OS_paths_for_diag(1:evalInfo.nbOS_used, 1:params.T);
        selectedPaths = select_representative_paths_h2(evalInfo, params, OS_paths_for_diag, opts);
        selectedDiagInfo = diagnose_selected_paths_h2( ...
            selectedPaths, modelLib, params, OS_paths_for_diag, opts, evalInfo);
        export_selected_path_diagnostics_h2(selectedDiagInfo, detailsDir, opts);
        fprintf('Selected path diagnostics exported to %s\n', detailsDir);
    catch ME
        warning('run_h2_with_options:SelectedDiagnosticsFailed', ...
            'Selected path diagnostics failed: %s', ME.message);
    end
end

[finalLB, iterations, stopFlag, trainTime] = extract_train_summary(trainInfo);
[oosMean, ciLow, ciHigh, evalTime, nbOSUsed] = extract_eval_summary(evalInfo);

fprintf('\nH2 Final LB = %.6f\n', finalLB);
fprintf('H2 OOS mean = %.6f\n', oosMean);
fprintf('H2 95%% CI = [%.6f, %.6f]\n', ciLow, ciHigh);
fprintf('H2 nbOS_used = %d\n', nbOSUsed);
fprintf('H2 iterations = %d\n', iterations);
fprintf('H2 stop_flag = %d\n', stopFlag);
fprintf('H2 train_time = %.2fs\n', trainTime);
fprintf('H2 eval_time = %.2fs\n', evalTime);

save(fullfile(outputDir, 'h2_workspace.mat'), ...
    'params', 'modelLib', 'trainInfo', 'evalInfo', 'selectedDiagInfo', 'opts', '-v7.3');

readableTbl = build_h2_readable_results(params, finalLB, oosMean, ciLow, ciHigh, ...
    trainTime, evalTime, iterations, stopFlag, nbOSUsed, evalInfo);
writetable(readableTbl, fullfile(benchmarkDir, 'H2results_readable.csv'));

if isfield(evalInfo, 'stageCost') && ~isempty(evalInfo.stageCost)
    writetable(build_h2_path_cost_table(evalInfo.stageCost, evalInfo.pathCost), ...
        fullfile(detailsDir, 'h2_oos_path_costs.csv'));
    writetable(build_h2_path_summary_table(evalInfo), ...
        fullfile(detailsDir, 'h2_oos_summary_by_path.csv'));
    writetable(build_h2_terminal_summary_table(evalInfo), ...
        fullfile(detailsDir, 'h2_terminal_summary.csv'));
end

result = struct();
result.params = params;
result.modelLib = modelLib;
result.trainInfo = trainInfo;
result.evalInfo = evalInfo;
result.selectedDiagInfo = selectedDiagInfo;
result.outputDir = outputDir;
result.benchmarkDir = benchmarkDir;
result.detailsDir = detailsDir;
result.opts = opts;
result.readable = readableTbl;
end

function opts = merge_options(defaults, overrides)
opts = defaults;
names = fieldnames(overrides);
for ii = 1:numel(names)
    opts.(names{ii}) = overrides.(names{ii});
end
end

function validate_oos_files_h2(params)
OOS = readmatrix(params.oosFile);
if size(OOS, 1) < params.nbOS
    error('run_h2_with_options:InsufficientOOSRows', ...
        'H2 OOS file has %d rows, but params.nbOS = %d.', size(OOS, 1), params.nbOS);
end
if size(OOS, 2) < params.T
    error('run_h2_with_options:InsufficientOOSColumns', ...
        'H2 OOS file has %d columns, but params.T = %d.', size(OOS, 2), params.T);
end
end

function [finalLB, iterations, stopFlag, trainTime] = extract_train_summary(trainInfo)
finalLB = NaN; iterations = NaN; stopFlag = NaN; trainTime = NaN;
if ~isempty(fieldnames(trainInfo))
    finalLB = trainInfo.LB(end);
    iterations = trainInfo.iter;
    stopFlag = trainInfo.stop_flag;
    trainTime = trainInfo.train_time;
end
end

function [oosMean, ciLow, ciHigh, evalTime, nbOSUsed] = extract_eval_summary(evalInfo)
oosMean = NaN; ciLow = NaN; ciHigh = NaN; evalTime = NaN; nbOSUsed = NaN;
if ~isempty(fieldnames(evalInfo))
    oosMean = evalInfo.oos_mean;
    ciLow = evalInfo.ci_low;
    ciHigh = evalInfo.ci_high;
    evalTime = evalInfo.elapsed;
    nbOSUsed = evalInfo.nbOS_used;
end
end

function readableTbl = build_h2_readable_results(params, finalLB, oosMean, ciLow, ciHigh, ...
    trainTime, evalTime, iterations, stopFlag, nbOSUsed, evalInfo)
ciHalfWidth = oosMean - ciLow;
timestamp = string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
avgNormal = NaN; avgReserve = NaN; avgTerminalCost = NaN; hitRatio = NaN;
avgTransport = NaN; avgProduction = NaN; avgFinalLOH = NaN;
var95 = NaN; cvar95 = NaN; var99 = NaN; cvar99 = NaN; maxCost = NaN;
top5Shortage = NaN;
if ~isempty(fieldnames(evalInfo))
    avgNormal = evalInfo.avg_normal_shortage;
    avgReserve = evalInfo.avg_terminal_reserve_shortage;
    avgTerminalCost = evalInfo.avg_terminal_cost;
    hitRatio = evalInfo.hit_loh_demand_ratio;
    avgTransport = evalInfo.avg_transport;
    avgProduction = evalInfo.avg_production;
    avgFinalLOH = evalInfo.avg_final_loh_total;
    if isfield(evalInfo, 'oos_risk_metrics') && ~isempty(evalInfo.oos_risk_metrics)
        riskTbl = evalInfo.oos_risk_metrics;
        var95 = riskTbl.VaR_95(1);
        cvar95 = riskTbl.CVaR_95(1);
        var99 = riskTbl.VaR_99(1);
        cvar99 = riskTbl.CVaR_99(1);
        maxCost = riskTbl.max_cost(1);
        top5Shortage = riskTbl.top5pct_avg_terminal_shortage(1);
    end
end

readableTbl = table( ...
    "H2-FA-MSP-R", params.Ni, params.T, params.K, params.k_init, nbOSUsed, ...
    finalLB, oosMean, ciLow, ciHigh, ciHalfWidth, trainTime, evalTime, ...
    iterations, stopFlag, avgNormal, avgReserve, avgTransport, avgProduction, ...
    avgFinalLOH, params.beta_enabled, string(params.beta_mode), ...
    string(params.terminal_loh_mode), string(params.terminal_load_mode), ...
    params.terminal_load_info.total_P_node_load_kw, ...
    params.terminal_load_info.total_H_node_load_kg, ...
    params.cost_normal_shortage_base, params.normal_shortage_penalty_multiplier, ...
    params.cost_normal_shortage, params.time_limit, ...
    string(params.terminal_impact_template_used), params.use_nonterminal_targetloh, ...
    params.use_beta_capacity, params.use_beta_cost, params.use_tank_min, false, avgTerminalCost, ...
    hitRatio, var95, cvar95, var99, cvar99, maxCost, top5Shortage, "lf=Nc-1", "lf=Nc", ...
    "Gurobi", timestamp, ...
    'VariableNames', {'policy', 'Ni', 'T', 'K', 'k_init', 'nbOS_used', ...
    'LB', 'OOS_mean', 'CI_low', 'CI_high', 'CI_half_width', ...
    'train_time', 'eval_time', 'iterations', 'stop_flag', ...
    'avg_normal_shortage', 'avg_terminal_reserve_shortage', 'avg_transport', ...
    'avg_production', 'avg_final_loh_total', 'beta_enabled', 'beta_mode', ...
    'terminal_loh_mode', 'terminal_load_mode', 'total_P_node_load_kw', ...
    'total_H_node_load_kg', 'cost_normal_shortage_base', ...
    'normal_shortage_penalty_multiplier', 'cost_normal_shortage', ...
    'time_limit_sec', 'terminal_impact_template_used', 'use_nonterminal_targetloh', ...
    'beta_capacity_enabled', 'beta_cost_enabled', 'use_tank_min', 'use_el_ramp', ...
    'avg_terminal_cost', 'hit_loh_demand_ratio', 'VaR_95', 'CVaR_95', ...
    'VaR_99', 'CVaR_99', 'max_cost', 'top5pct_avg_terminal_shortage', ...
    'loh_demand_stage', 'absorbing_stage', 'solver', 'timestamp'});
end

function pathCostTbl = build_h2_path_cost_table(stageCost, pathCost)
nPaths = size(stageCost, 1);
T = size(stageCost, 2);
pathIds = (1:nPaths).';
costNames = arrayfun(@(tt) sprintf('cost_t%d', tt), 1:T, 'UniformOutput', false);
varNames = [{'path_id'}, costNames, {'total_cost'}];
pathCostTbl = array2table([pathIds, stageCost, pathCost(:)], 'VariableNames', varNames);
end

function summaryTbl = build_h2_path_summary_table(evalInfo)
nPaths = numel(evalInfo.pathCost);
summaryTbl = table( ...
    (1:nPaths).', evalInfo.pathCost(:), ...
    sum(evalInfo.normal_shortage, 2), sum(evalInfo.terminal_reserve_shortage, 2), ...
    sum(evalInfo.transport_amount, 2), sum(evalInfo.production_amount, 2), ...
    sum(evalInfo.final_loh, 2), sum(evalInfo.terminal_cost, 2), ...
    evalInfo.hit_loh_demand(:), evalInfo.first_loh_demand_stage(:), ...
    'VariableNames', {'path_id', 'total_cost', 'normal_shortage', ...
    'terminal_reserve_shortage', 'transport_amount', 'production_amount', ...
    'final_loh_total', 'terminal_cost', 'hit_loh_demand', 'first_loh_demand_stage'});
end

function terminalTbl = build_h2_terminal_summary_table(evalInfo)
nPaths = numel(evalInfo.pathCost);
terminalTbl = table( ...
    (1:nPaths).', sum(evalInfo.terminal_reserve_shortage, 2), ...
    sum(evalInfo.terminal_cost, 2), ...
    'VariableNames', {'path_id', 'terminal_reserve_shortage', 'terminal_cost'});
end
