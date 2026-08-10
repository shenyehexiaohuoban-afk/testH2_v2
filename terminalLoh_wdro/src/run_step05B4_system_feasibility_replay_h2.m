function run_step05B4_system_feasibility_replay_h2(runId)
%RUN_STEP05B4_SYSTEM_FEASIBILITY_REPLAY_H2 Read-only system feasibility audit.
% Replays the two saved policies on the frozen OOS paths and solves small
% service-preserving physical diagnostic LPs for the seven requested states.
% No MSP training, cuts, or parameter changes occur.

if nargin < 1 || strlength(string(runId)) == 0
    runId = "run-001";
end

rootDir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(rootDir);
addpath(fullfile(rootDir, 'fa_h2'));
addpath(fullfile(rootDir, 'fa_h2', 'fuzhu'));
addpath(fullfile(rootDir, 'utils'));

focusStates = [12 16 17 18 19 13 14];
sourceRun = fullfile(rootDir, 'results', 'task-002-stage2b-b3-smoke', ...
    '57-main-msp-converged-terminal-loh-ab', 'run-003');
sourceB1 = fullfile(rootDir, 'results', 'task-002-stage2b-b3-smoke', ...
    '58-main-msp-terminal-gap-mechanism-audit', 'run-004', ...
    'terminal_target_vs_final_inventory.csv');
outDir = fullfile(rootDir, 'results', 'task-002-stage2b-b3-smoke', ...
    '61-terminal-loh-system-feasibility-audit', char(runId));
if isfolder(outDir)
    error('run_step05B4_system_feasibility_replay_h2:OutputExists', ...
        'Output directory already exists: %s', outDir);
end
mkdir(outDir);

saaWorkspace = fullfile(sourceRun, 'case-saa', 'native_output', 'h2_workspace.mat');
droWorkspace = fullfile(sourceRun, 'case-chi2_eta003', 'native_output', 'h2_workspace.mat');
require_file(saaWorkspace);
require_file(droWorkspace);
require_file(sourceB1);

b1 = readtable(sourceB1, 'TextType', 'string');
b1saa = sortrows(b1(b1.method == "saa" & b1.hit_terminal == 1, :), 'path_id');
b1dro = sortrows(b1(b1.method == "chi2_eta003" & b1.hit_terminal == 1, :), 'path_id');
if height(b1saa) ~= 6053 || height(b1dro) ~= 6053
    error('run_step05B4_system_feasibility_replay_h2:BadB1Rows', ...
        'Expected 6053 terminal-hit rows per method.');
end
b1saa.state_id = (double(b1saa.a) - 2) * 7 + double(b1saa.loc);
b1dro.state_id = (double(b1dro.a) - 2) * 7 + double(b1dro.loc);
if any(double(b1saa.path_id) ~= double(b1dro.path_id)) || ...
        any(double(b1saa.state_id) ~= double(b1dro.state_id))
    error('run_step05B4_system_feasibility_replay_h2:CommonSampleMismatch', ...
        'Step-05B-1 common terminal events do not match.');
end
selectedPathIds = double(b1saa.path_id(ismember(double(b1saa.state_id), focusStates)));
if numel(selectedPathIds) ~= 649
    error('run_step05B4_system_feasibility_replay_h2:UnexpectedSelectedCount', ...
        'Expected 649 selected terminal-hit paths, got %d.', numel(selectedPathIds));
end

[obsSaa, httSaa, arcSaa, auditSaa, oosFileSaa] = replay_observations( ...
    saaWorkspace, "saa", selectedPathIds, focusStates, b1saa, false);
[obsDro, httDro, arcDro, auditDro, oosFileDro, physical] = replay_observations( ...
    droWorkspace, "chi2_eta003", selectedPathIds, focusStates, b1dro, true);
if ~strcmpi(char(oosFileSaa), char(oosFileDro))
    error('run_step05B4_system_feasibility_replay_h2:OOSMismatch', ...
        'The two workspaces reference different OOS files.');
end

writetable([obsSaa; obsDro], fullfile(outDir, 'replay_stage_site_observations.csv'));
writetable([httSaa; httDro], fullfile(outDir, 'replay_stage_htt_observations.csv'));
writetable([arcSaa; arcDro], fullfile(outDir, 'replay_htt_arc_observations.csv'));
writetable(physical, fullfile(outDir, 'physical_feasibility_path_audit.csv'));

fid = fopen(fullfile(outDir, 'replay_integrity_audit.txt'), 'w');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, 'Step-05B-4 deterministic replay and physical-LP integrity audit\n\n');
fprintf(fid, 'Focus states: %s\n', mat2str(focusStates));
fprintf(fid, 'Selected terminal-hit paths: %d\n', numel(selectedPathIds));
fprintf(fid, 'Common OOS file: %s\n', oosFileSaa);
fprintf(fid, 'OOS SHA-256: %s\n', sha256_file(char(oosFileSaa)));
fprintf(fid, 'SAA replay elapsed seconds: %.12g\n', auditSaa.elapsed);
fprintf(fid, 'DRO replay elapsed seconds: %.12g\n', auditDro.elapsed);
fprintf(fid, 'SAA max errors: saved_final=%.12g, B1_final=%.12g, terminal_state=%d\n', ...
    auditSaa.saved_final_error, auditSaa.b1_final_error, auditSaa.terminal_state_mismatch_count);
fprintf(fid, 'DRO max errors: saved_final=%.12g, B1_final=%.12g, terminal_state=%d\n', ...
    auditDro.saved_final_error, auditDro.b1_final_error, auditDro.terminal_state_mismatch_count);
fprintf(fid, 'Physical diagnostic LP rows: %d\n', height(physical));
fprintf(fid, 'Physical LP optimal rows: %d\n', sum(physical.solve_pass));
fprintf(fid, 'Max conservation residual: %.12g\n', max(physical.max_conservation_residual));
fprintf(fid, 'Max target/gap reconstruction residual: %.12g\n', max(physical.target_gap_reconstruction_residual));
fprintf(fid, 'Replay PASS: %d\n', auditSaa.pass && auditDro.pass);
fprintf(fid, 'Physical LP PASS: %d\n', all(physical.solve_pass));
fprintf(fid, '\nPhysical diagnostic definition:\n');
fprintf(fid, '- ordinary service at every stage/site is fixed to the actual DRO replay service; it is not cancelled or reduced.\n');
fprintf(fid, '- original initial inventory, station tank capacity, electrolyzer capacity/conversion, inventory conservation, and beta-dependent aggregate HTT capacity are enforced.\n');
fprintf(fid, '- HTT is internal transfer and never contributes to system hydrogen supply.\n');
fprintf(fid, '- cuts, theta, and monetary objective terms are intentionally absent; results are diagnostic physical feasibility, not an optimized MSP policy.\n');
fprintf(fid, '- the current main MSP has no pairwise hard road-reachability constraint on HTT arcs.\n');
clear cleaner;

fprintf('Step-05B-4 replay and physical audit completed: %s\n', outDir);
end


function [stageSite, stageHtt, arcObs, audit, oosFile, physical] = ...
        replay_observations(workspaceFile, method, selectedPathIds, focusStates, b1Method, doPhysical)
loaded = load(workspaceFile, 'params', 'modelLib', 'evalInfo', 'trainInfo');
required = {'params','modelLib','evalInfo','trainInfo'};
for ii = 1:numel(required)
    if ~isfield(loaded, required{ii})
        error('replay_observations:MissingWorkspaceField', ...
            'Workspace %s lacks %s.', workspaceFile, required{ii});
    end
end
if loaded.trainInfo.stop_flag ~= 2
    error('replay_observations:UnexpectedStopFlag', ...
        'Expected fixed-budget stop_flag=2.');
end
p = loaded.params;
p.store_eval_decisions = true;
oosFile = string(p.oosFile);
OOS = readmatrix(oosFile);
OOS = OOS(1:p.nbOS, 1:p.T);
detailed = eval_h2(loaded.modelLib, p);

savedFinalError = max(abs(detailed.final_loh(:) - loaded.evalInfo.final_loh(:)));
expected = nan(numel(selectedPathIds), p.Ni);
b1Selected = b1Method(ismember(double(b1Method.path_id), selectedPathIds), :);
b1Selected = sortrows(b1Selected, 'path_id');
for site = 1:p.Ni
    expected(:, site) = double(b1Selected.(sprintf('final_site%d', site)));
end
b1FinalError = max(abs(detailed.final_loh(selectedPathIds,:) - expected), [], 'all');
terminalMismatch = 0;
for q = 1:numel(selectedPathIds)
    s = selectedPathIds(q);
    tTerm = detailed.first_loh_demand_stage(s);
    if tTerm <= 0 || OOS(s,tTerm) ~= double(b1Selected.terminal_state(q))
        terminalMismatch = terminalMismatch + 1;
    end
end
audit = struct();
audit.elapsed = detailed.elapsed;
audit.saved_final_error = savedFinalError;
audit.b1_final_error = b1FinalError;
audit.terminal_state_mismatch_count = terminalMismatch;
audit.pass = max(savedFinalError,b1FinalError) <= 1e-8 && terminalMismatch == 0;
if ~audit.pass
    error('replay_observations:ReplayMismatch', '%s replay failed.', method);
end

siteRows = cell(0, 28);
httRows = cell(0, 14);
arcRows = cell(0, 12);
physicalRows = cell(0, 23);

for q = 1:numel(selectedPathIds)
    s = selectedPathIds(q);
    tTerm = detailed.first_loh_demand_stage(s);
    terminalK = OOS(s,tTerm);
    a = p.S(terminalK,1);
    loc = p.S(terminalK,2);
    stateId = (a - 2) * 7 + loc;
    if ~ismember(stateId, focusStates)
        error('replay_observations:StateSelectionMismatch', ...
            'Unexpected state %d.', stateId);
    end
    target = p.TerminalLOH(:,terminalK);
    prev = p.x_0(:);
    servedMatrix = zeros(tTerm-1,p.Ni);

    for t = 1:tTerm
        kk = OOS(s,t);
        beta = p.beta(kk);
        if p.use_beta_capacity
            httCap = max(0,(1-beta)*p.htt_capacity_base);
        else
            httCap = p.htt_capacity_base;
        end
        startX = prev;
        terminalEvent = t == tTerm;
        if ~isempty(detailed.xval{s,t})
            active = true;
            endX = detailed.xval{s,t}(:);
            e = detailed.eval{s,t}(:);
            prod = detailed.rval{s,t}(:);
            f = detailed.fval{s,t};
            served = detailed.u_normal{s,t}(:);
            shortage = detailed.z_normal{s,t}(:);
            servedMatrix(t,:) = served.';
            prev = endX;
        else
            active = false;
            endX = prev;
            e = zeros(p.Ni,1);
            prod = zeros(p.Ni,1);
            f = zeros(p.Ni,p.Ni);
            served = zeros(p.Ni,1);
            shortage = zeros(p.Ni,1);
        end
        inflow = sum(f,1).';
        outflow = sum(f,2);
        totalFlow = sum(f,'all');
        if active && httCap > 1e-12
            httUtil = totalFlow/httCap;
        else
            httUtil = NaN;
        end
        for site = 1:p.Ni
            prodCap = p.k_H2*p.dt_h*p.el_cap_kw(site);
            if active && prodCap > 0
                prodUtil = prod(site)/prodCap;
            else
                prodUtil = NaN;
            end
            storageUtil = endX(site)/p.x_cap(site);
            if terminalEvent
                terminalTarget = target(site);
                terminalGap = max(0,target(site)-endX(site));
            else
                terminalTarget = 0;
                terminalGap = 0;
            end
            siteRows(end+1,:) = {method,s,stateId,terminalK,tTerm,t,site,active, ...
                terminalEvent,startX(site),endX(site),prod(site),prodCap,prodUtil, ...
                p.x_cap(site),storageUtil,p.D_normal(site,t),served(site),shortage(site), ...
                inflow(site),outflow(site),inflow(site)-outflow(site),beta,httCap, ...
                httUtil,terminalTarget,terminalGap,e(site)}; %#ok<AGROW>
        end
        httRows(end+1,:) = {method,s,stateId,terminalK,tTerm,t,active,beta, ...
            totalFlow,httCap,httUtil,sum(prod),sum(served),sum(shortage)}; %#ok<AGROW>
        if active
            for origin = 1:p.Ni
                for destination = 1:p.Ni
                    if origin == destination
                        continue;
                    end
                    arcRows(end+1,:) = {method,s,stateId,terminalK,tTerm,t, ...
                        origin,destination,f(origin,destination),totalFlow,httCap,httUtil}; %#ok<AGROW>
                end
            end
        end
    end

    if doPhysical
        [phys, maxResidual] = solve_physical_path(p,OOS(s,:),tTerm,servedMatrix,target);
        actualFinal = detailed.final_loh(s,:).';
        actualGap = sum(max(0,target-actualFinal));
        targetTotal = sum(target);
        actualTotal = sum(actualFinal);
        lowerBoundTotalGap = max(0,targetTotal-phys.max_terminal_total);
        spatialExcessGap = max(0,phys.min_terminal_gap-lowerBoundTotalGap);
        tol = 1e-7;
        totalSufficient = phys.max_terminal_total >= targetTotal-tol;
        spatialFeasible = phys.min_terminal_gap <= tol;
        actualTotalSufficient = actualTotal >= targetTotal-tol;
        actualSpatialMismatch = actualTotalSufficient && actualGap > tol;
        if ~phys.solve_pass
            pathClass = "E";
        elseif ~totalSufficient && spatialExcessGap > tol
            pathClass = "D";
        elseif ~totalSufficient
            pathClass = "A";
        elseif ~spatialFeasible
            pathClass = "B";
        else
            pathClass = "C";
        end
        conservationResidual = abs(actualTotal - (sum(p.x_0) + ...
            sum(detailed.production_amount(s,1:tTerm-1),'all') - ...
            sum(servedMatrix,'all')));
        gapResidual = abs(actualGap-sum(max(0,target-actualFinal)));
        physicalRows(end+1,:) = {s,stateId,terminalK,tTerm,targetTotal,actualTotal, ...
            actualGap,phys.max_terminal_total,phys.min_terminal_gap, ...
            lowerBoundTotalGap,spatialExcessGap,totalSufficient,spatialFeasible, ...
            actualTotalSufficient,actualSpatialMismatch,pathClass,phys.max_status, ...
            phys.gap_status,phys.solve_pass,sum(p.x_0),sum(p.x_cap), ...
            maxResidual,max(conservationResidual,gapResidual)}; %#ok<AGROW>
    end
end

siteNames = {'method','path_id','state_id','terminal_state_k','terminal_stage', ...
    'stage','site','active','terminal_event','start_inventory_kg','end_inventory_kg', ...
    'production_kg','available_production_capacity_kg','prod_utilization', ...
    'storage_capacity_kg','storage_utilization','normal_demand_kg', ...
    'normal_served_kg','normal_shortage_kg','htt_inflow_kg','htt_outflow_kg', ...
    'net_htt_inflow_kg','beta','available_htt_capacity_kg','htt_utilization', ...
    'terminal_target_kg','terminal_gap_kg','electrolyzer_power_kw'};
stageSite = cell2table(siteRows,'VariableNames',siteNames);
httNames = {'method','path_id','state_id','terminal_state_k','terminal_stage', ...
    'stage','active','beta','total_htt_flow_kg','available_htt_capacity_kg', ...
    'htt_utilization','total_production_kg','total_normal_served_kg', ...
    'total_normal_shortage_kg'};
stageHtt = cell2table(httRows,'VariableNames',httNames);
arcNames = {'method','path_id','state_id','terminal_state_k','terminal_stage', ...
    'stage','origin_site','destination_site','flow_kg','total_htt_flow_kg', ...
    'available_htt_capacity_kg','htt_utilization'};
arcObs = cell2table(arcRows,'VariableNames',arcNames);
if doPhysical
    physicalNames = {'path_id','state_id','terminal_state_k','terminal_stage', ...
        'T_total_dro_kg','actual_I_total_dro_kg','actual_terminal_gap_kg', ...
        'service_preserving_max_terminal_total_kg','service_preserving_min_terminal_gap_kg', ...
        'system_total_shortfall_lower_bound_kg','spatial_excess_gap_kg', ...
        'physical_total_sufficient','physical_spatial_feasible', ...
        'actual_total_sufficient','actual_spatial_mismatch','path_classification', ...
        'max_total_status','min_gap_status','solve_pass','initial_total_inventory_kg', ...
        'total_storage_capacity_kg','max_conservation_residual', ...
        'target_gap_reconstruction_residual'};
    physical = cell2table(physicalRows,'VariableNames',physicalNames);
else
    physical = table();
end
clear detailed loaded;
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
    error('run_step05B4_system_feasibility_replay_h2:MissingFile', ...
        'Missing required file: %s',path);
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
