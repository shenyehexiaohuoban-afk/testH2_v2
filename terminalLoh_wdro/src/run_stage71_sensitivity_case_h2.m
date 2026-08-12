function result = run_stage71_sensitivity_case_h2(experimentId)
%RUN_STAGE71_SENSITIVITY_CASE_H2 Train one isolated Stage-71 policy case.

rootDir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(rootDir);
addpath(fullfile(rootDir, 'terminalLoh_wdro', 'src'));

runId = char(string(getenv('STAGE71_RUN_ID')));
if isempty(regexp(runId, '^run-\d{3}$', 'once'))
    error('run_stage71_sensitivity_case_h2:BadRunId', ...
        'STAGE71_RUN_ID must be run-xxx.');
end
terminalMode = lower(string(getenv('STAGE71_TERMINAL_MODE')));
if ~ismember(terminalMode, ["saa", "chi2_eta003"])
    error('run_stage71_sensitivity_case_h2:BadTerminalMode', ...
        'STAGE71_TERMINAL_MODE must be saa or chi2_eta003.');
end

cfg = stage71_experiment_config_h2(rootDir, experimentId);
stageRoot = fullfile(rootDir, 'results', 'task-002-stage2b-b3-smoke', ...
    '71-stage-duration-capacity-sensitivity', runId);
caseDir = fullfile(stageRoot, cfg.output_name, "case-" + terminalMode);
nativeOutputDir = fullfile(caseDir, 'native_output');
if exist(caseDir, 'dir')
    error('run_stage71_sensitivity_case_h2:OutputExists', ...
        'Refusing to overwrite existing case directory: %s', caseDir);
end
mkdir(caseDir);

sensitivityInput = fullfile(caseDir, 'sensitivity_input.mat');
inputStruct = struct('NearStageInput', cfg.NearStageInput);
save(sensitivityInput, '-struct', 'inputStruct', '-v7');

opts = h2_default_options(rootDir);
opts.nearInputFile = sensitivityInput;
opts.dt_h = cfg.dt_h;
opts.time_limit = 3600;
opts.max_iter = 100000;
opts.stall = 500;
opts.eps_tol = 1e-5;
opts.cutviol_maxiter = 100000;
opts.outputDir = nativeOutputDir;
opts.oosFile = fullfile(rootDir, 'output_h2', 'details', 'h2_OOS.csv');
opts.regenOOS = false;
opts.runTraining = true;
opts.runEvaluation = false;
opts.runSelectedPathDiagnostics = false;
opts.store_eval_decisions = false;
opts.terminal_loh_mode = char(terminalMode);
lookupRoot = fullfile(rootDir, 'results', 'task-002-stage2b-b3-smoke', ...
    '53-35state-saa-vs-eta003-terminal-loh', 'run-024');
if terminalMode == "saa"
    opts.terminal_loh_lookup_file = fullfile(lookupRoot, 'terminal_loh_table_saa.csv');
else
    opts.terminal_loh_lookup_file = fullfile(lookupRoot, 'terminal_loh_table_eta_003.csv');
end
opts.allow_zero_terminal_loh = true;

identity = table(string(cfg.experiment_id), terminalMode, cfg.dt_h, 3600, ...
    cfg.pmax_kw(1), cfg.pmax_kw(2), cfg.pmax_kw(3), cfg.pmax_kw(4), ...
    cfg.rmax_kg_per_stage(1), cfg.rmax_kg_per_stage(2), ...
    cfg.rmax_kg_per_stage(3), cfg.rmax_kg_per_stage(4), ...
    cfg.htt_capacity_kg_per_stage, cfg.N_HTT, cfg.Q_HTT_kg, ...
    sum(cfg.normal_demand_template_kg, 'all'), ...
    cfg.holding_cost_yuan_per_kg_stage, ...
    cfg.normal_shortage_penalty_yuan_per_kg, ...
    cfg.terminal_gap_penalty_yuan_per_kg, ...
    'VariableNames', {'experiment','terminal_mode','dt_h','time_limit_s', ...
    'pmax1_kw','pmax2_kw','pmax3_kw','pmax4_kw', ...
    'rmax1_kg','rmax2_kg','rmax3_kg','rmax4_kg', ...
    'htt_capacity_kg_per_stage','N_HTT','Q_HTT_kg', ...
    'ordinary_demand_template_total_kg','holding_cost', ...
    'ordinary_shortage_penalty','terminal_gap_penalty'});
for t = 1:8
    identity.(sprintf('electricity_stage_price_%d', t)) = ...
        cfg.stage_electricity_price_yuan_per_kWh(t);
end
writetable(identity, fullfile(caseDir, 'parameter_identity.csv'));

result = run_h2_with_options(opts);
if result.trainInfo.stop_flag ~= 2
    error('run_stage71_sensitivity_case_h2:UnexpectedStop', ...
        ['Stage-71 fixed-budget case must stop at the 3600 s time limit. ' ...
        'stop_flag=%d, iter=%d, train_time=%.6f.'], ...
        result.trainInfo.stop_flag, result.trainInfo.iter, result.trainInfo.train_time);
end
if max(abs(result.params.el_cap_kw(:).' - cfg.pmax_kw)) > 1e-9 || ...
        abs(result.params.dt_h - cfg.dt_h) > 1e-12 || ...
        abs(result.params.htt_capacity_base - cfg.htt_capacity_kg_per_stage) > 1e-9
    error('run_stage71_sensitivity_case_h2:RuntimeIdentityMismatch', ...
        'Runtime parameter identity differs from the frozen Stage-71 config.');
end

fid = fopen(fullfile(caseDir, 'TRAIN_DONE.txt'), 'w');
fprintf(fid, 'status=PASS\nexperiment=%s\nterminal_mode=%s\n', ...
    cfg.experiment_id, terminalMode);
fprintf(fid, 'stop_flag=%d\niterations=%d\ntrain_time_s=%.12g\n', ...
    result.trainInfo.stop_flag, result.trainInfo.iter, result.trainInfo.train_time);
fprintf(fid, 'completed_at=%s\n', datestr(now, 31));
fclose(fid);
end
