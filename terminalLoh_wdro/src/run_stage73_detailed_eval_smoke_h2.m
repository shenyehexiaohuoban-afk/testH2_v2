function run_stage73_detailed_eval_smoke_h2()
%RUN_STAGE73_DETAILED_EVAL_SMOKE_H2 Two-path directed-HTT schema smoke.

rootDir=fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(rootDir); addpath(fullfile(rootDir,'fa_h2')); addpath(fullfile(rootDir,'fa_h2','fuzhu'));
addpath(fullfile(rootDir,'utils')); addpath(fullfile(rootDir,'terminalLoh_wdro','src'));
runId=char(string(getenv('STAGE73_RUN_ID')));
outDir=fullfile(rootDir,'results','task-002-stage2b-b3-smoke', ...
    '73-htt-transport-cost-sensitivity',runId,'config_smoke','detailed_eval_smoke');
if exist(outDir,'dir'); error('run_stage73_detailed_eval_smoke_h2:OutputExists','%s',outDir); end
mkdir(outDir);
ws=fullfile(rootDir,'results','task-002-stage2b-b3-smoke', ...
    '71-stage-duration-capacity-sensitivity','run-001','E1_8h','case-saa','native_output','h2_workspace.mat');
loaded=load(ws,'params','modelLib','trainInfo');
[summaryTbl,httTbl]=evaluate_stage73_policy_detailed_h2(loaded.modelLib,loaded.params,'Reference_08_smoke','saa',2);
if height(summaryTbl)~=2 || any(httTbl.origin_site==httTbl.destination_site) || ...
        any(httTbl.htt_utilization>1+1e-7) || ...
        max(abs(httTbl.transport_cost_yuan-httTbl.flow_kg.*httTbl.actual_unit_cost_yuan_per_kg))>1e-8
    error('run_stage73_detailed_eval_smoke_h2:MechanicalFailure', ...
        'Directed HTT smoke schema or cost identity failed.');
end
[~,~,groupId]=unique([httTbl.path_id httTbl.stage],'rows');
counts=accumarray(groupId,1);
if any(counts~=12)
    error('run_stage73_detailed_eval_smoke_h2:ODCount', ...
        'Every active path-stage must archive exactly 12 directed OD rows.');
end
writetable(summaryTbl,fullfile(outDir,'smoke_path_summary.csv'));
writetable(httTbl,fullfile(outDir,'smoke_htt_directed_od_path_stage.csv'));
fid=fopen(fullfile(outDir,'DETAILED_EVAL_SMOKE_PASS.txt'),'w');
fprintf(fid,'status=PASS\npath_count=2\ndirected_rows=%d\nrows_per_active_path_stage=12\n',height(httTbl));
fprintf(fid,'reference_policy=%s\ncompleted_at=%s\n',ws,datestr(now,31)); fclose(fid);
end
