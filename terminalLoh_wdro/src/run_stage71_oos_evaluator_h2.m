rootDir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(rootDir);
addpath(fullfile(rootDir, 'fa_h2'));
addpath(fullfile(rootDir, 'fa_h2', 'fuzhu'));
addpath(fullfile(rootDir, 'utils'));
addpath(fullfile(rootDir, 'terminalLoh_wdro', 'src'));

runId = char(string(getenv('STAGE71_RUN_ID')));
experimentId = char(string(getenv('STAGE71_EXPERIMENT_ID')));
terminalMode = lower(string(getenv('STAGE71_TERMINAL_MODE')));
cfg = stage71_experiment_config_h2(rootDir, experimentId);
caseDir = fullfile(rootDir, 'results', 'task-002-stage2b-b3-smoke', ...
    '71-stage-duration-capacity-sensitivity', runId, cfg.output_name, ...
    "case-" + terminalMode);
workspaceFile = fullfile(caseDir, 'native_output', 'h2_workspace.mat');
if ~isfile(workspaceFile)
    error('run_stage71_oos_evaluator_h2:MissingWorkspace', ...
        'Missing trained workspace: %s', workspaceFile);
end
if isfile(fullfile(caseDir, 'EVAL_DONE.txt'))
    error('run_stage71_oos_evaluator_h2:AlreadyDone', ...
        'Evaluation marker already exists: %s', caseDir);
end

loaded = load(workspaceFile, 'params', 'modelLib', 'trainInfo', 'opts');
if loaded.trainInfo.stop_flag ~= 2 || abs(loaded.params.dt_h - cfg.dt_h) > 1e-12 || ...
        max(abs(loaded.params.el_cap_kw(:).' - cfg.pmax_kw)) > 1e-9 || ...
        abs(loaded.params.htt_capacity_base - cfg.htt_capacity_kg_per_stage) > 1e-9
    error('run_stage71_oos_evaluator_h2:PolicyIdentityMismatch', ...
        'Trained policy parameters do not match the Stage-71 experiment config.');
end

summaryTbl = evaluate_stage71_policy_h2(loaded.modelLib, loaded.params);
outCsv = fullfile(caseDir, 'stage71_oos_path_summary.csv');
writetable(summaryTbl, outCsv);
save(fullfile(caseDir, 'stage71_oos_eval.mat'), 'summaryTbl', '-v7.3');

fid = fopen(fullfile(caseDir, 'EVAL_DONE.txt'), 'w');
fprintf(fid, 'status=PASS\nexperiment=%s\nterminal_mode=%s\n', ...
    experimentId, terminalMode);
fprintf(fid, 'path_count=%d\nterminal_hit_count=%d\ncompleted_at=%s\n', ...
    height(summaryTbl), sum(summaryTbl.terminal_hit), datestr(now, 31));
fclose(fid);
