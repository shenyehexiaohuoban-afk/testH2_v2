function run_stage74_selected_path_replay_h2()
%RUN_STAGE74_SELECTED_PATH_REPLAY_H2 Replay only preselected Stage-74 paths.
% This is a fixed-policy diagnostic. It does not train, add cuts, or sample.

rootDir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(rootDir); addpath(fullfile(rootDir,'fa_h2'));
addpath(fullfile(rootDir,'fa_h2','fuzhu')); addpath(fullfile(rootDir,'utils'));

outDir = fullfile(rootDir,'results','task-002-stage2b-b3-smoke', ...
    '74-cd02-representative-path-mechanism-audit','run-001');
selectionFile = fullfile(outDir,'representative_path_selection.csv');
if ~isfile(selectionFile)
    error('run_stage74_selected_path_replay_h2:MissingSelection','%s',selectionFile);
end
selectedBase = readtable(selectionFile);
selectedBase = selectedBase(selectedBase.selected == 1, :);
selectedBase = sortrows(selectedBase,'path_id');
if height(selectedBase) < 3 || height(selectedBase) > 5
    error('run_stage74_selected_path_replay_h2:BadSelectionCount', ...
        'Expected 3 to 5 fixed selected paths, got %d.', height(selectedBase));
end

stageRoot = fullfile(rootDir,'results','task-002-stage2b-b3-smoke', ...
    '73-htt-transport-cost-sensitivity','run-001');
cases = {
    'H02','saa';
    'H02','chi2_eta003';
    'Reference_08','saa';
    'Reference_08','chi2_eta003'};

for cc = 1:size(cases,1)
    scheme = cases{cc,1}; method = cases{cc,2};
    caseDir = fullfile(stageRoot,scheme,"case-"+string(method));
    if strcmp(scheme,'Reference_08')
        workspaceFile = fullfile(rootDir,'results','task-002-stage2b-b3-smoke', ...
            '71-stage-duration-capacity-sensitivity','run-001','E1_8h', ...
            "case-"+string(method),'native_output','h2_workspace.mat');
        expectedCd = 0.8;
    else
        workspaceFile = fullfile(caseDir,'native_output','h2_workspace.mat');
        expectedCd = 0.2;
    end
    loaded = load(workspaceFile,'params','modelLib','trainInfo','opts');
    if abs(loaded.params.dt_h-8)>1e-12 || abs(loaded.params.htt_capacity_base-160)>1e-12 || ...
            ~loaded.params.use_beta_capacity || ~loaded.params.use_beta_cost
        error('run_stage74_selected_path_replay_h2:PolicyIdentity','%s %s',scheme,method);
    end
    dist = loaded.params.site_to_site_road_km;
    expectedBase = expectedCd * dist;
    if max(abs(loaded.params.cost_transport_base-expectedBase),[],'all') > 1e-8
        error('run_stage74_selected_path_replay_h2:TransportIdentity','%s %s',scheme,method);
    end
    if strcmp(scheme,'H02') && loaded.trainInfo.stop_flag ~= 2
        error('run_stage74_selected_path_replay_h2:BudgetIdentity','%s %s',scheme,method);
    end

    raw = readtable(loaded.params.oosFile);
    needed = "k_t" + (1:loaded.params.T);
    OS = table2array(raw(:,cellstr(needed)));
    selected = selectedBase(:,{'path_id'});
    selected.path_type = repmat(string(scheme)+"_"+string(method),height(selected),1);
    diagInfo = diagnose_selected_paths_h2(selected,loaded.modelLib,loaded.params,OS,struct(),struct());
    prefix = lower(string(scheme))+"_"+lower(string(method));
    writetable(diagInfo.timeseries,fullfile(outDir,prefix+"_timeseries.csv"));
    writetable(diagInfo.site_balance,fullfile(outDir,prefix+"_site_balance.csv"));
    writetable(diagInfo.transport_edges,fullfile(outDir,prefix+"_transport_edges.csv"));
    writetable(diagInfo.cost_breakdown,fullfile(outDir,prefix+"_cost_breakdown.csv"));
    writetable(diagInfo.transition_expectation_summary, ...
        fullfile(outDir,prefix+"_transition_expectation_summary.csv"));
end

fid=fopen(fullfile(outDir,'SELECTED_PATH_REPLAY_DONE.txt'),'w');
fprintf(fid,'status=PASS\nselected_paths=%d\n',height(selectedBase));
fprintf(fid,'cases=H02_saa,H02_chi2_eta003,Reference_08_saa,Reference_08_chi2_eta003\n');
fprintf(fid,'training=false\nresampling=false\nnew_cuts=false\n');
fprintf(fid,'scope=preselected_paths_only\ncompleted_at=%s\n',datestr(now,31));
fclose(fid);
end
