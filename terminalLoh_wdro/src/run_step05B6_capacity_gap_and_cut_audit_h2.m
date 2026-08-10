function run_step05B6_capacity_gap_and_cut_audit_h2(runId)
%RUN_STEP05B6_CAPACITY_GAP_AND_CUT_AUDIT_H2 Read-only Step-05B-6 audit.
% Solves the same ex-post service-preserving physical LP for SAA and DRO
% on state16/17/18/19 paths, then inspects archived cuts at the fixed
% state19 eight-path replay inventories. It never trains or adds cuts.

if nargin < 1 || strlength(string(runId)) == 0
    runId = "run-001";
end

repo = fileparts(fileparts(fileparts(mfilename('fullpath'))));
focusStates = [16 17 18 19];
state19Paths = [1529 2134 5371 8092 8289 8650 9095 9913];
outDir = fullfile(repo, 'results', 'task-002-stage2b-b3-smoke', ...
    '63-saa-dro-capacity-gap-and-state19-training-audit', char(runId));
if isfolder(outDir)
    error('run_step05B6:OutputExists', 'Output directory exists: %s', outDir);
end
mkdir(outDir);

source57 = fullfile(repo, 'results', 'task-002-stage2b-b3-smoke', ...
    '57-main-msp-converged-terminal-loh-ab', 'run-003');
source61 = fullfile(repo, 'results', 'task-002-stage2b-b3-smoke', ...
    '61-terminal-loh-system-feasibility-audit', 'run-001');
source62 = fullfile(repo, 'results', 'task-002-stage2b-b3-smoke', ...
    '62-terminal-loh-information-revelation-audit', 'run-002');
replayFile = fullfile(source61, 'replay_stage_site_observations.csv');
droPhysicalFile = fullfile(source61, 'physical_feasibility_path_audit.csv');
traceFile = fullfile(source62, 'selected_path_inventory_trace.csv');
oosFile = fullfile(repo, 'output_h2', 'details', 'h2_OOS.csv');
files = {replayFile, droPhysicalFile, traceFile, oosFile};
for i = 1:numel(files)
    require_file(files{i});
end

workspaces = struct();
workspaces.saa = fullfile(source57, 'case-saa', 'native_output', 'h2_workspace.mat');
workspaces.chi2_eta003 = fullfile(source57, 'case-chi2_eta003', ...
    'native_output', 'h2_workspace.mat');
require_file(workspaces.saa);
require_file(workspaces.chi2_eta003);

replay = readtable(replayFile, 'TextType', 'string');
droPhysical = readtable(droPhysicalFile, 'TextType', 'string');
trace = readtable(traceFile, 'TextType', 'string');
OOS = readmatrix(oosFile);
if ~isequal(size(OOS), [10000 8])
    error('run_step05B6:OOSShape', 'Expected frozen OOS shape 10000x8.');
end

methods = ["saa", "chi2_eta003"];
capacityRows = cell(0, 22);
cutRowsAll = cell(0, 34);
archiveRows = cell(0, 16);
maxDroReplayResidual = 0;
maxLpResidual = 0;

for method = methods
    loaded = load(workspaces.(char(method)), 'params', 'modelLib', 'trainInfo');
    p = loaded.params;
    if loaded.trainInfo.stop_flag ~= 2
        error('run_step05B6:StopFlag', '%s stop_flag changed from 2.', method);
    end
    completedBackwardIterations = loaded.trainInfo.iter - 1;
    lastForwardPath = double(loaded.trainInfo.last_forward.in_sample(:));
    if numel(lastForwardPath) ~= p.T
        error('run_step05B6:LastForwardShape', 'Unexpected last forward path shape.');
    end

    methodReplay = replay(replay.method == method & ...
        ismember(double(replay.state_id), focusStates), :);
    pathIds = unique(double(methodReplay.path_id), 'sorted');
    if numel(pathIds) ~= 255
        error('run_step05B6:PathCount', ...
            'Expected 255 focus paths for %s, got %d.', method, numel(pathIds));
    end

    for q = 1:numel(pathIds)
        pathId = pathIds(q);
        rows = methodReplay(double(methodReplay.path_id) == pathId, :);
        stateId = unique(double(rows.state_id));
        terminalK = unique(double(rows.terminal_state_k));
        tTerm = unique(double(rows.terminal_stage));
        if numel(stateId) ~= 1 || numel(terminalK) ~= 1 || numel(tTerm) ~= 1
            error('run_step05B6:ReplayIdentity', 'Non-unique path identity for %d.', pathId);
        end
        served = zeros(tTerm-1, p.Ni);
        for t = 1:tTerm-1
            for site = 1:p.Ni
                one = rows(double(rows.stage) == t & double(rows.site) == site, :);
                if height(one) ~= 1
                    error('run_step05B6:ReplayCoverage', ...
                        'Missing replay row method=%s path=%d t=%d site=%d.', ...
                        method, pathId, t, site);
                end
                served(t, site) = double(one.normal_served_kg);
            end
        end
        target = p.TerminalLOH(:, terminalK);
        [phys, residual] = solve_physical_path(p, OOS(pathId,:), tTerm, served, target);
        maxLpResidual = max(maxLpResidual, residual);
        targetTotal = sum(target);
        totalGap = max(0, targetTotal-phys.max_terminal_total);
        totalSufficient = totalGap <= 1e-7;
        spatialFeasible = phys.min_terminal_gap <= 1e-7;
        terminalRows = rows(double(rows.terminal_event) == 1, :);
        actualTotal = sum(double(terminalRows.end_inventory_kg));
        ordinaryServedTotal = sum(served, 'all');

        if method == "chi2_eta003"
            old = droPhysical(double(droPhysical.path_id) == pathId, :);
            if height(old) ~= 1
                error('run_step05B6:DroReference', 'Missing Step-05B-4 row %d.', pathId);
            end
            refResidual = max(abs([phys.max_terminal_total - ...
                double(old.service_preserving_max_terminal_total_kg), ...
                phys.min_terminal_gap - double(old.service_preserving_min_terminal_gap_kg)]));
            maxDroReplayResidual = max(maxDroReplayResidual, refResidual);
        else
            refResidual = NaN;
        end

        capacityRows(end+1,:) = {method, pathId, stateId, terminalK, tTerm, ...
            targetTotal, actualTotal, ordinaryServedTotal, sum(p.x_0), sum(p.x_cap), ...
            phys.max_terminal_total, phys.min_terminal_gap, totalGap, ...
            totalGap/max(targetTotal, 1e-12), totalSufficient, spatialFeasible, ...
            string(phys.max_status), string(phys.gap_status), phys.solve_pass, ...
            residual, refResidual, completedBackwardIterations}; %#ok<AGROW>
    end

    state19Replay = replay(replay.method == method & ...
        ismember(double(replay.path_id), state19Paths), :);
    for pathId = state19Paths
        for t = [5 6]
            k = OOS(pathId, t);
            traceRows = trace(trace.method == method & ...
                double(trace.path_id) == pathId & double(trace.decision_stage) == t, :);
            if isempty(traceRows)
                % The path has already reached lf=7/absorbed, so there is no
                % ordinary stage model or policy inventory to audit here.
                continue;
            end
            if height(traceRows) ~= p.Ni
                error('run_step05B6:TraceCoverage', ...
                    'Expected four Step-05B-5 trace rows method=%s path=%d t=%d.', ...
                    method, pathId, t);
            end
            [~, traceOrder] = sort(double(traceRows.site));
            traceRows = traceRows(traceOrder,:);
            xRows = state19Replay(double(state19Replay.path_id) == pathId & ...
                double(state19Replay.stage) == t, :);
            if height(xRows) ~= p.Ni
                error('run_step05B6:State19ReplayCoverage', ...
                    'Expected four rows method=%s path=%d t=%d.', method, pathId, t);
            end
            [~, orderSite] = sort(double(xRows.site));
            xRows = xRows(orderSite,:);
            x = double(xRows.end_inventory_kg);
            model = loaded.modelLib.models{t,k};
            if isempty(model)
                error('run_step05B6:MissingModel', 'Missing model t=%d,k=%d.', t, k);
            end
            baseRows = max(model.rowMap.htt_capacity);
            savedCutRows = (baseRows+1):size(model.A,1);
            if numel(savedCutRows) ~= completedBackwardIterations
                error('run_step05B6:CutIterationMap', ...
                    ['Expected one archived cut per completed backward iteration at ' ...
                     't=%d,k=%d for %s: cuts=%d iterations=%d.'], ...
                    t, k, method, numel(savedCutRows), completedBackwardIterations);
            end
            slopes = model.A(savedCutRows, model.idx.x);
            rhs = -model.b(savedCutRows) + slopes*x;
            cumulativeMax = cummax(rhs);
            updateFlag = [true; diff(cumulativeMax) > 1e-9*max(1,abs(cumulativeMax(2:end)))];
            activeRhs = max(rhs);
            tol = 1e-6*max(1,abs(activeRhs));
            activeLocal = find(abs(rhs-activeRhs) <= tol);
            chosenLocal = activeLocal(1);
            chosenMarginal = -slopes(chosenLocal,:).';
            activeMarginals = -slopes(activeLocal,:);
            [~, rankOrder] = sort(chosenMarginal, 'descend');
            ranks = zeros(p.Ni,1);
            ranks(rankOrder) = 1:p.Ni;
            lastEnvelopeUpdate = find(updateFlag, 1, 'last');
            lastForwardMatch = lastForwardPath(t) == k;

            nodeCount = unique(double(traceRows.node_oos_path_count));
            futureCount = unique(double(traceRows.future_terminal_state_count));
            realizedProbability = unique(double(traceRows.outcome_frequency));
            targetRange = unique(double(traceRows.conditional_max_site_target_range_kg));
            if any([numel(nodeCount),numel(futureCount),numel(realizedProbability),numel(targetRange)] ~= 1)
                error('run_step05B6:TraceNodeIdentity', 'Non-unique node metadata.');
            end

            archiveRows(end+1,:) = {method, pathId, t, k, p.S(k,1), p.S(k,2), ...
                p.S(k,3), nodeCount, nodeCount/10000, futureCount, ...
                realizedProbability, targetRange, completedBackwardIterations, ...
                numel(savedCutRows), lastForwardMatch, lastEnvelopeUpdate}; %#ok<AGROW>

            for site = 1:p.Ni
                cutRowsAll(end+1,:) = {method, pathId, t, k, p.S(k,1), p.S(k,2), ...
                    p.S(k,3), nodeCount, nodeCount/10000, futureCount, ...
                    realizedProbability, targetRange, site, x(site), ...
                    double(traceRows.realized_terminal_target_kg(site)), ...
                    double(traceRows.conditional_terminal_target_mean_kg(site)), ...
                    numel(savedCutRows), numel(activeLocal), activeRhs, chosenLocal, ...
                    chosenLocal, chosenMarginal(site), ranks(site), ...
                    min(activeMarginals(:,site)), max(activeMarginals(:,site)), ...
                    mean(activeMarginals(:,site)), sum(updateFlag), ...
                    lastEnvelopeUpdate, completedBackwardIterations-lastEnvelopeUpdate, ...
                    lastForwardMatch, loaded.trainInfo.iter, loaded.trainInfo.train_time, ...
                    loaded.trainInfo.stop_flag, completedBackwardIterations}; %#ok<AGROW>
            end
        end
    end
    clear loaded;
end

capacityNames = {'method','path_id','state_id','terminal_state_k','terminal_stage', ...
    'terminal_loh_total_target_kg','actual_terminal_total_inventory_kg', ...
    'preserved_ordinary_service_total_kg','initial_total_inventory_kg', ...
    'total_storage_capacity_kg','max_feasible_terminal_total_inventory_kg', ...
    'min_feasible_station_gap_kg','system_total_capacity_gap_kg', ...
    'capacity_gap_share_of_target','system_total_sufficient','station_targets_feasible', ...
    'max_total_status','min_gap_status','solve_pass','max_lp_residual', ...
    'step05b4_dro_reproduction_residual','completed_backward_iterations'};
capacity = cell2table(capacityRows, 'VariableNames', capacityNames);
writetable(capacity, fullfile(outDir, 'capacity_gap_path_raw.csv'));

archiveNames = {'method','path_id','decision_stage','current_k','current_a', ...
    'current_loc','current_lf','node_oos_path_count','node_oos_frequency', ...
    'future_terminal_state_count','realized_terminal_state_probability', ...
    'conditional_max_site_target_range_kg','completed_backward_iterations', ...
    'saved_cut_count','last_forward_node_match','last_envelope_update_iteration'};
archive = cell2table(archiveRows, 'VariableNames', archiveNames);
writetable(archive, fullfile(outDir, 'state19_training_archive_raw.csv'));

cutNames = {'method','path_id','decision_stage','current_k','current_a', ...
    'current_loc','current_lf','node_oos_path_count','node_oos_frequency', ...
    'future_terminal_state_count','realized_terminal_state_probability', ...
    'conditional_max_site_target_range_kg','site','archived_inventory_kg', ...
    'realized_terminal_target_kg','node_conditional_mean_target_kg', ...
    'saved_cut_count','active_cut_count','active_cut_rhs', ...
    'chosen_active_cut_local_index','chosen_active_cut_source_iteration', ...
    'chosen_marginal_value_of_1kg_inventory','chosen_marginal_value_rank', ...
    'active_marginal_value_min','active_marginal_value_max', ...
    'active_marginal_value_mean','envelope_update_count', ...
    'last_envelope_update_iteration','iterations_since_last_envelope_update', ...
    'last_forward_node_match','training_iteration_count','training_time_seconds', ...
    'stop_flag','completed_backward_iterations'};
cutAudit = cell2table(cutRowsAll, 'VariableNames', cutNames);
writetable(cutAudit, fullfile(outDir, 'state19_saved_cut_raw.csv'));

fid = fopen(fullfile(outDir, 'matlab_readonly_integrity_audit.txt'), 'w');
if fid < 0
    error('run_step05B6:IntegrityOpen', 'Cannot write integrity file.');
end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'Step-05B-6 MATLAB read-only audit\n\n');
fprintf(fid, 'Frozen OOS: %s\n', oosFile);
fprintf(fid, 'OOS SHA-256: %s\n', sha256_file(oosFile));
fprintf(fid, 'Capacity LP rows: %d\n', height(capacity));
fprintf(fid, 'Expected capacity LP rows: 510\n');
fprintf(fid, 'Optimal LP rows: %d\n', sum(capacity.solve_pass));
fprintf(fid, 'Maximum LP residual: %.12g\n', maxLpResidual);
fprintf(fid, 'Maximum DRO reproduction residual vs Step-05B-4: %.12g\n', maxDroReplayResidual);
fprintf(fid, 'State19 archive node rows: %d\n', height(archive));
fprintf(fid, 'State19 cut-site rows: %d\n', height(cutAudit));
fprintf(fid, 'SAA iterations/time/stop: %d / %.12g / %d\n', ...
    max(cutAudit.training_iteration_count(cutAudit.method=="saa")), ...
    max(cutAudit.training_time_seconds(cutAudit.method=="saa")), ...
    max(cutAudit.stop_flag(cutAudit.method=="saa")));
fprintf(fid, 'DRO iterations/time/stop: %d / %.12g / %d\n', ...
    max(cutAudit.training_iteration_count(cutAudit.method=="chi2_eta003")), ...
    max(cutAudit.training_time_seconds(cutAudit.method=="chi2_eta003")), ...
    max(cutAudit.stop_flag(cutAudit.method=="chi2_eta003")));
fprintf(fid, 'Per-iteration training paths were not archived; OOS node frequency is not training visit frequency.\n');
fprintf(fid, 'Cut insertion order maps one-to-one to completed backward iterations because every eligible ordinary model receives one shared cut per completed iteration.\n');
fprintf(fid, 'No eval_h2, forward pass, backward pass, add_cut, training, sampling, or parameter mutation was called.\n');
fprintf(fid, 'MATLAB audit PASS: %d\n', height(capacity)==510 && ...
    all(capacity.solve_pass) && maxLpResidual <= 1e-7 && ...
    maxDroReplayResidual <= 1e-7 && height(archive)==20 && height(cutAudit)==80);
clear cleanup;

fprintf('Step-05B-6 MATLAB read-only audit completed: %s\n', outDir);
end


function [out,maxResidual] = solve_physical_path(p,path,tTerm,servedMatrix,target)
nStage = tTerm-1;
Ni = p.Ni;
perStage = 3*Ni + Ni*Ni;
nvars = nStage*perStage;
idx = cell(nStage,1);
lb = zeros(nvars,1);
ub = inf(nvars,1);
for t = 1:nStage
    offset = (t-1)*perStage;
    idx{t}.x = offset+(1:Ni);
    idx{t}.e = offset+Ni+(1:Ni);
    idx{t}.r = offset+2*Ni+(1:Ni);
    idx{t}.f = reshape(offset+3*Ni+(1:Ni*Ni),Ni,Ni);
    ub(idx{t}.x) = p.x_cap(:);
    ub(idx{t}.e) = p.el_cap_kw(:);
    for i = 1:Ni
        ub(idx{t}.f(i,i)) = 0;
    end
end

Aeq = zeros(nStage*2*Ni,nvars);
beq = zeros(nStage*2*Ni,1);
A = zeros(nStage,nvars);
b = zeros(nStage,1);
eqRow = 0;
for t = 1:nStage
    for i = 1:Ni
        eqRow = eqRow+1;
        Aeq(eqRow,idx{t}.x(i)) = 1;
        if t > 1
            Aeq(eqRow,idx{t-1}.x(i)) = -1;
            beq(eqRow) = -servedMatrix(t,i);
        else
            beq(eqRow) = p.x_0(i)-servedMatrix(t,i);
        end
        Aeq(eqRow,idx{t}.r(i)) = -1;
        for j = 1:Ni
            if j ~= i
                Aeq(eqRow,idx{t}.f(j,i)) = Aeq(eqRow,idx{t}.f(j,i))-1;
                Aeq(eqRow,idx{t}.f(i,j)) = Aeq(eqRow,idx{t}.f(i,j))+1;
            end
        end
        eqRow = eqRow+1;
        Aeq(eqRow,idx{t}.r(i)) = 1;
        Aeq(eqRow,idx{t}.e(i)) = -p.k_H2*p.dt_h;
    end
    A(t,idx{t}.f(:)) = 1;
    beta = p.beta(path(t));
    if p.use_beta_capacity
        b(t) = max(0,(1-beta)*p.htt_capacity_base);
    else
        b(t) = p.htt_capacity_base;
    end
end

base = struct();
base.A = sparse([A;Aeq]);
base.rhs = [b;beq];
base.sense = [repmat('<',size(A,1),1);repmat('=',size(Aeq,1),1)];
base.lb = lb;
base.ub = ub;
base.modelsense = 'min';
params = struct('OutputFlag',0,'InfUnbdInfo',1);

objMax = zeros(nvars,1);
objMax(idx{nStage}.x) = -1;
modelMax = base;
modelMax.obj = objMax;
resMax = gurobi(modelMax,params);

gIdx = nvars+(1:Ni);
modelGap = struct();
Agap = zeros(Ni,nvars+Ni);
for i = 1:Ni
    Agap(i,idx{nStage}.x(i)) = -1;
    Agap(i,gIdx(i)) = -1;
end
modelGap.A = sparse([[A;Aeq],zeros(size(A,1)+size(Aeq,1),Ni);Agap]);
modelGap.rhs = [b;beq;-target(:)];
modelGap.sense = [repmat('<',size(A,1),1);repmat('=',size(Aeq,1),1);repmat('<',Ni,1)];
modelGap.lb = [lb;zeros(Ni,1)];
modelGap.ub = [ub;inf(Ni,1)];
modelGap.obj = [zeros(nvars,1);ones(Ni,1)];
modelGap.modelsense = 'min';
resGap = gurobi(modelGap,params);

out = struct();
out.max_status = string(resMax.status);
out.gap_status = string(resGap.status);
out.solve_pass = strcmp(resMax.status,'OPTIMAL') && strcmp(resGap.status,'OPTIMAL');
if ~out.solve_pass
    out.max_terminal_total = NaN;
    out.min_terminal_gap = NaN;
    maxResidual = inf;
    return;
end
out.max_terminal_total = sum(resMax.x(idx{nStage}.x));
out.min_terminal_gap = sum(resGap.x(gIdx));
maxResidual = 0;
maxResidual = max(maxResidual,max(abs(Aeq*resMax.x-beq)));
maxResidual = max(maxResidual,max(A*resMax.x-b));
maxResidual = max(maxResidual,max(abs(Aeq*resGap.x(1:nvars)-beq)));
maxResidual = max(maxResidual,max(A*resGap.x(1:nvars)-b));
maxResidual = max(maxResidual,max(-resGap.x(gIdx)));
end


function require_file(path)
if ~isfile(path)
    error('run_step05B6:MissingFile', 'Missing required file: %s', path);
end
end


function hash = sha256_file(path)
md = java.security.MessageDigest.getInstance('SHA-256');
fid = fopen(path,'r');
if fid < 0
    error('sha256_file:OpenFailed','Could not open %s.',path);
end
cleaner = onCleanup(@() fclose(fid));
while true
    data = fread(fid,1024*1024,'*uint8');
    if isempty(data), break; end
    md.update(data);
end
raw = typecast(md.digest(),'uint8');
hash = lower(reshape(dec2hex(raw,2).',1,[]));
clear cleaner;
end
