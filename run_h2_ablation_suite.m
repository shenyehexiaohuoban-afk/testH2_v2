clear; clc;

%% Ablation suite controls
suiteMode = 'quick';   % 'quick' | 'full' | 'selected'
selectedExperiments = {};
customTimeLimit = [];

rootDir = fileparts(mfilename('fullpath'));
if isempty(rootDir)
    rootDir = pwd;
end

baseSeed = 20260513;
ablationRoot = fullfile(rootDir, 'output_h2', 'ablation');
if ~exist(ablationRoot, 'dir')
    mkdir(ablationRoot);
end

experiments = define_ablation_experiments();
[experimentsToRun, timeLimitSec] = select_experiments(experiments, suiteMode, ...
    selectedExperiments, customTimeLimit);

summaryVarNames = ablation_summary_varnames();
summaryRows = cell(numel(experimentsToRun), numel(summaryVarNames));
sharedOOSFile = fullfile(ablationRoot, 'shared_h2_OOS.csv');

for ee = 1:numel(experimentsToRun)
    expCfg = experimentsToRun(ee);
    fprintf('\n=== Running ablation %s ===\n', expCfg.name);

    opts = h2_default_options(rootDir);
    opts.time_limit = timeLimitSec;
    opts.terminal_load_mode = expCfg.terminal_load_mode;
    opts.beta_enabled = expCfg.beta_enabled;
    opts.normal_shortage_penalty_multiplier = expCfg.normal_shortage_penalty_multiplier;
    opts.outputDir = fullfile(ablationRoot, expCfg.name);
    opts.seed = baseSeed + expCfg.id;
    opts.oosFile = sharedOOSFile;

    result = run_h2_with_options(opts); %#ok<NASGU>
    summaryRows(ee, :) = build_summary_row(expCfg, opts);
end

summaryTbl = cell2table(summaryRows, 'VariableNames', summaryVarNames);
writetable(summaryTbl, fullfile(ablationRoot, 'ablation_summary.csv'));
write_ablation_summary_readable(summaryTbl, fullfile(ablationRoot, 'ablation_summary_readable.txt'));
write_ablation_readme(ablationRoot);

fprintf('\nAblation summary exported to %s\n', fullfile(ablationRoot, 'ablation_summary.csv'));

function experiments = define_ablation_experiments()
experiments = struct( ...
    'id', {1, 2, 3, 4}, ...
    'name', {'A_node_load_beta_base', ...
             'B_node_load_no_beta', ...
             'C_critical_load_beta_base', ...
             'D_node_load_beta_high_normal_penalty'}, ...
    'terminal_load_mode', {'node_load', 'node_load', 'critical_load', 'node_load'}, ...
    'beta_enabled', {true, false, true, true}, ...
    'normal_shortage_penalty_multiplier', {1, 1, 1, 10});
end

function [selected, timeLimitSec] = select_experiments(experiments, suiteMode, selectedNames, customTimeLimit)
switch lower(string(suiteMode))
    case "quick"
        selected = experiments;
        timeLimitSec = 600;
    case "full"
        selected = experiments;
        timeLimitSec = 3600;
    case "selected"
        if isempty(selectedNames)
            error('run_h2_ablation_suite:EmptySelectedExperiments', ...
                'selectedExperiments must list at least one experiment when suiteMode = ''selected''.');
        end
        allNames = string({experiments.name});
        keep = ismember(allNames, string(selectedNames));
        missing = setdiff(string(selectedNames), allNames);
        if ~isempty(missing)
            error('run_h2_ablation_suite:UnknownExperiment', ...
                'Unknown selected experiment: %s.', strjoin(missing, ', '));
        end
        selected = experiments(keep);
        if isempty(customTimeLimit)
            timeLimitSec = 3600;
        else
            timeLimitSec = customTimeLimit;
        end
    otherwise
        error('run_h2_ablation_suite:BadSuiteMode', ...
            'suiteMode must be ''quick'', ''full'', or ''selected''.');
end

if ~isscalar(timeLimitSec) || timeLimitSec <= 0
    error('run_h2_ablation_suite:BadTimeLimit', 'time limit must be a positive scalar.');
end
end

function row = build_summary_row(expCfg, opts)
readableFile = fullfile(opts.outputDir, 'benchmark', 'H2results_readable.csv');
riskFile = fullfile(opts.outputDir, 'details', 'oos_risk_metrics.csv');
if ~isfile(readableFile)
    error('run_h2_ablation_suite:MissingReadableResults', ...
        'Experiment %s did not create %s.', expCfg.name, readableFile);
end
if ~isfile(riskFile)
    error('run_h2_ablation_suite:MissingRiskMetrics', ...
        'Experiment %s did not create %s.', expCfg.name, riskFile);
end

readable = readtable(readableFile);
risk = readtable(riskFile);

row = { ...
    string(expCfg.name), string(expCfg.terminal_load_mode), expCfg.beta_enabled, ...
    expCfg.normal_shortage_penalty_multiplier, ...
    table_value(readable, 'cost_normal_shortage_base'), ...
    table_value(readable, 'cost_normal_shortage'), ...
    opts.time_limit, opts.seed, ...
    table_value(readable, 'LB'), table_value(readable, 'OOS_mean'), ...
    table_value(readable, 'CI_low'), table_value(readable, 'CI_high'), ...
    table_value(readable, 'nbOS_used'), table_value(readable, 'iterations'), ...
    table_value(readable, 'stop_flag'), table_value(readable, 'train_time'), ...
    table_value(readable, 'eval_time'), table_value(readable, 'avg_normal_shortage'), ...
    table_value(readable, 'avg_terminal_reserve_shortage'), ...
    table_value(readable, 'avg_terminal_cost'), ...
    table_value(readable, 'hit_loh_demand_ratio'), ...
    table_value(readable, 'avg_transport'), table_value(readable, 'avg_production'), ...
    table_value(readable, 'avg_final_loh_total'), ...
    table_value(risk, 'VaR_95'), table_value(risk, 'CVaR_95'), ...
    table_value(risk, 'VaR_99'), table_value(risk, 'CVaR_99'), ...
    table_value(risk, 'max_cost'), ...
    table_value(risk, 'top5pct_avg_terminal_shortage'), ...
    table_value(risk, 'top5pct_avg_terminal_cost')};
end

function names = ablation_summary_varnames()
names = {'experiment_name', 'terminal_load_mode', 'beta_enabled', ...
    'normal_shortage_penalty_multiplier', 'cost_normal_shortage_base', ...
    'cost_normal_shortage', 'time_limit_sec', 'seed', ...
    'Final_LB', 'OOS_mean', 'CI_low', 'CI_high', 'nbOS_used', ...
    'iterations', 'stop_flag', 'train_time', 'eval_time', ...
    'avg_normal_shortage', 'avg_terminal_reserve_shortage', ...
    'avg_terminal_cost', 'hit_LOH_demand_ratio', 'avg_HTT_transport', ...
    'avg_production', 'avg_final_LOH_total', 'VaR_95', 'CVaR_95', ...
    'VaR_99', 'CVaR_99', 'max_cost', ...
    'top5pct_avg_terminal_shortage', 'top5pct_avg_terminal_cost'};
end

function val = table_value(tbl, fieldName)
if ~ismember(fieldName, tbl.Properties.VariableNames)
    warning('run_h2_ablation_suite:MissingNonCriticalField', ...
        'Missing field %s; writing NaN.', fieldName);
    val = NaN;
    return;
end
val = tbl.(fieldName)(1);
end

function write_ablation_summary_readable(summaryTbl, outFile)
fid = fopen(outFile, 'w');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'H2 ablation summary\n\n');
for rr = 1:height(summaryTbl)
    fprintf(fid, '%s\n', summaryTbl.experiment_name(rr));
    fprintf(fid, '  terminal_load_mode: %s\n', summaryTbl.terminal_load_mode(rr));
    fprintf(fid, '  beta_enabled: %d\n', summaryTbl.beta_enabled(rr));
    fprintf(fid, '  normal_shortage_penalty_multiplier: %.6g\n', ...
        summaryTbl.normal_shortage_penalty_multiplier(rr));
    fprintf(fid, '  OOS_mean: %.6f\n', summaryTbl.OOS_mean(rr));
    fprintf(fid, '  CVaR_95: %.6f\n', summaryTbl.CVaR_95(rr));
    fprintf(fid, '  avg_terminal_reserve_shortage: %.6f\n\n', ...
        summaryTbl.avg_terminal_reserve_shortage(rr));
end
end

function write_ablation_readme(ablationRoot)
txt = [
"H2 FA-MSP ablation suite"
""
"Experiments:"
"- A_node_load_beta_base: node_load TerminalLOH, beta enabled, normal shortage penalty multiplier 1."
"- B_node_load_no_beta: node_load TerminalLOH, beta disabled."
"- C_critical_load_beta_base: critical_load TerminalLOH, beta enabled."
"- D_node_load_beta_high_normal_penalty: node_load TerminalLOH, beta enabled, normal shortage penalty multiplier 10."
""
"Modes:"
"- quick runs all four experiments with time_limit = 600 seconds each."
"- full runs all four experiments with time_limit = 3600 seconds each."
"- selected runs selectedExperiments only; customTimeLimit is used when set, otherwise 3600 seconds."
""
"Model interpretation:"
"- CVaR is an empirical OOS post-processing metric only. It is not part of the MSP objective or cut generation."
"- beta_enabled=false sets params.beta to all zero and disables beta capacity/cost effects."
"- node_load uses IEEE33 total node active load as the TerminalLOH scale; critical_load uses the older critical-load scale."
"- high_normal_penalty means the normal H2 load shortage penalty is multiplied by 10."
""
"Outputs:"
"- ablation_summary.csv has one row per experiment with configuration, train/eval summary, shortage, transport, production, VaR, and CVaR metrics."
"- Each experiment writes benchmark/ and details/ under output_h2/ablation/<experiment_name>/."
"- The suite uses output_h2/ablation/shared_h2_OOS.csv so the four experiments share OOS typhoon paths when the file is present or created by the first run."
];
fid = fopen(fullfile(ablationRoot, 'ablation_README.txt'), 'w');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', txt);
end
