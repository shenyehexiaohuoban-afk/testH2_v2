function run_stage73_detailed_oos_evaluator_h2()
%RUN_STAGE73_DETAILED_OOS_EVALUATOR_H2 Evaluate reference or trained policy.

rootDir=fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(rootDir); addpath(fullfile(rootDir,'fa_h2')); addpath(fullfile(rootDir,'fa_h2','fuzhu'));
addpath(fullfile(rootDir,'utils')); addpath(fullfile(rootDir,'terminalLoh_wdro','src'));
runId=char(string(getenv('STAGE73_RUN_ID')));
experimentId=upper(char(string(getenv('STAGE73_EXPERIMENT_ID'))));
terminalMode=lower(string(getenv('STAGE73_TERMINAL_MODE')));
cfg=stage73_transport_cost_config_h2(rootDir,experimentId);
stageRoot=fullfile(rootDir,'results','task-002-stage2b-b3-smoke','73-htt-transport-cost-sensitivity',runId);
caseDir=fullfile(stageRoot,cfg.output_name,"case-"+terminalMode);
if strcmp(experimentId, 'REFERENCE_08')
    refCase=fullfile(rootDir,'results','task-002-stage2b-b3-smoke', ...
        '71-stage-duration-capacity-sensitivity','run-001','E1_8h',"case-"+terminalMode);
    workspaceFile=fullfile(refCase,'native_output','h2_workspace.mat');
    if ~exist(caseDir,'dir'); mkdir(caseDir); end
    fid=fopen(fullfile(caseDir,'REFERENCE_POLICY_SOURCE.txt'),'w');
    fprintf(fid,'source=%s\nretrained=false\n',workspaceFile); fclose(fid);
else
    workspaceFile=fullfile(caseDir,'native_output','h2_workspace.mat');
end
if ~isfile(workspaceFile); error('run_stage73_detailed_oos_evaluator_h2:MissingWorkspace','%s',workspaceFile); end
if isfile(fullfile(caseDir,'EVAL_DONE.txt')); error('run_stage73_detailed_oos_evaluator_h2:AlreadyDone','%s',caseDir); end
loaded=load(workspaceFile,'params','modelLib','trainInfo','opts');
if abs(loaded.params.dt_h-8)>1e-12 || abs(loaded.params.htt_capacity_base-160)>1e-12 || ...
        max(abs(loaded.params.cost_transport_base-cfg.transport_base_cost),[],'all')>1e-9 || ...
        ~loaded.params.use_beta_capacity || ~loaded.params.use_beta_cost
    error('run_stage73_detailed_oos_evaluator_h2:PolicyIdentityMismatch', ...
        'Policy does not match the Stage-73 scheme identity.');
end
if ~strcmp(experimentId, 'REFERENCE_08') && loaded.trainInfo.stop_flag ~= 2
    error('run_stage73_detailed_oos_evaluator_h2:TrainingBudgetIdentity', ...
        'New sensitivity policy is not a one-hour stop_flag=2 policy.');
end
[summaryTbl,httTbl]=evaluate_stage73_policy_detailed_h2(loaded.modelLib,loaded.params,cfg.output_name,terminalMode);
writetable(summaryTbl,fullfile(caseDir,'stage73_oos_path_summary.csv'));
writetable(httTbl,fullfile(caseDir,'htt_directed_od_path_stage.csv'));
save(fullfile(caseDir,'stage73_oos_eval.mat'),'summaryTbl','-v7.3');
fid=fopen(fullfile(caseDir,'EVAL_DONE.txt'),'w');
fprintf(fid,'status=PASS\nscheme=%s\nterminal_mode=%s\npath_count=%d\nterminal_hit_count=%d\n', ...
    cfg.output_name,terminalMode,height(summaryTbl),sum(summaryTbl.terminal_hit));
fprintf(fid,'directed_rows=%d\ncompleted_at=%s\n',height(httTbl),datestr(now,31)); fclose(fid);
end
