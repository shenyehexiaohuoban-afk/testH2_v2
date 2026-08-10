function run_step05B7_all_state_capacity_audit_h2(runId)
%RUN_STEP05B7_ALL_STATE_CAPACITY_AUDIT_H2 Read-only all-state capacity audit.
% Replays the two archived policies on the same frozen OOS paths and solves
% one ex-post service-preserving maximum-terminal-inventory LP per method and
% terminal-hit path. No training, sampling, or cut generation occurs.

if nargin < 1 || strlength(string(runId)) == 0
    runId = "run-001";
end

repo = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(repo);
addpath(fullfile(repo, 'fa_h2'));
addpath(fullfile(repo, 'fa_h2', 'fuzhu'));
addpath(fullfile(repo, 'utils'));

outDir = fullfile(repo, 'results', 'task-002-stage2b-b3-smoke', ...
    '64-terminal-loh-all-state-capacity-gap-audit', char(runId));
if isfolder(outDir)
    error('run_step05B7:OutputExists', 'Output directory exists: %s', outDir);
end
mkdir(outDir);

source57 = fullfile(repo, 'results', 'task-002-stage2b-b3-smoke', ...
    '57-main-msp-converged-terminal-loh-ab', 'run-003');
source63 = fullfile(repo, 'results', 'task-002-stage2b-b3-smoke', ...
    '63-saa-dro-capacity-gap-and-state19-training-audit', 'run-003');
b6RawFile = fullfile(source63, 'capacity_gap_path_raw.csv');
oosFile = fullfile(repo, 'output_h2', 'details', 'h2_OOS.csv');
require_file(b6RawFile);
require_file(oosFile);

workspaces = struct();
workspaces.saa = fullfile(source57, 'case-saa', 'native_output', 'h2_workspace.mat');
workspaces.chi2_eta003 = fullfile(source57, 'case-chi2_eta003', ...
    'native_output', 'h2_workspace.mat');
require_file(workspaces.saa);
require_file(workspaces.chi2_eta003);

OOS = readmatrix(oosFile);
if ~isequal(size(OOS), [10000 8])
    error('run_step05B7:OOSShape', 'Expected frozen OOS shape 10000x8.');
end
b6 = readtable(b6RawFile, 'TextType', 'string');

methods = ["saa", "chi2_eta003"];
pathRows = cell(0, 27);
resourceRows = cell(0, 11);
prodValues = cell(2,35);
storageValues = cell(2,35);
httValues = cell(2,35);
maxLpResidual = 0;
maxB6Residual = 0;
maxSavedEvalResidual = 0;
methodElapsed = zeros(2,1);

for mi = 1:numel(methods)
    method = methods(mi);
    loaded = load(workspaces.(char(method)), 'params', 'modelLib', 'evalInfo', 'trainInfo');
    needed = {'params','modelLib','evalInfo','trainInfo'};
    for f = 1:numel(needed)
        if ~isfield(loaded, needed{f})
            error('run_step05B7:WorkspaceSchema', ...
                'Workspace %s lacks %s.', workspaces.(char(method)), needed{f});
        end
    end
    if loaded.trainInfo.stop_flag ~= 2
        error('run_step05B7:StopFlag', '%s stop_flag changed from 2.', method);
    end
    p = loaded.params;
    p.store_eval_decisions = true;
    if ~strcmpi(char(p.oosFile), oosFile)
        error('run_step05B7:OOSReference', '%s workspace references another OOS.', method);
    end
    detailed = eval_h2(loaded.modelLib, p);
    methodElapsed(mi) = detailed.elapsed;
    savedResidual = max(abs(detailed.final_loh(:)-loaded.evalInfo.final_loh(:)));
    maxSavedEvalResidual = max(maxSavedEvalResidual, savedResidual);
    if savedResidual > 1e-8
        error('run_step05B7:ReplayMismatch', '%s saved evaluation mismatch.', method);
    end

    terminalPaths = find(detailed.first_loh_demand_stage > 0);
    if numel(terminalPaths) ~= 6053
        error('run_step05B7:TerminalPathCount', ...
            'Expected 6053 terminal-hit paths for %s.', method);
    end

    for q = 1:numel(terminalPaths)
        pathId = terminalPaths(q);
        tTerm = detailed.first_loh_demand_stage(pathId);
        terminalK = OOS(pathId,tTerm);
        a = p.S(terminalK,1);
        loc = p.S(terminalK,2);
        lf = p.S(terminalK,3);
        if lf ~= 7
            error('run_step05B7:TerminalLf', 'Path %d terminal lf is not 7.', pathId);
        end
        stateId = (a-2)*7+loc;
        if stateId < 1 || stateId > 35
            error('run_step05B7:StateMap', 'Invalid state id %d.', stateId);
        end
        target = p.TerminalLOH(:,terminalK);
        targetTotal = sum(target);
        nStage = tTerm-1;
        served = zeros(nStage,p.Ni);
        cumulativeProduction = 0;
        cumulativeAvailableProduction = 0;
        pathProdUtil = zeros(0,1);
        pathStorageUtil = zeros(0,1);
        pathHttUtil = zeros(0,1);

        for t = 1:nStage
            served(t,:) = detailed.u_normal{pathId,t}(:).';
            production = detailed.rval{pathId,t}(:);
            inventory = detailed.xval{pathId,t}(:);
            flow = detailed.fval{pathId,t};
            productionCap = p.k_H2*p.dt_h*p.el_cap_kw(:);
            cumulativeProduction = cumulativeProduction + sum(production);
            cumulativeAvailableProduction = cumulativeAvailableProduction + sum(productionCap);
            pathProdUtil = [pathProdUtil; production./productionCap]; %#ok<AGROW>
            pathStorageUtil = [pathStorageUtil; inventory./p.x_cap(:)]; %#ok<AGROW>
            beta = p.beta(OOS(pathId,t));
            if p.use_beta_capacity
                httCap = max(0,(1-beta)*p.htt_capacity_base);
            else
                httCap = p.htt_capacity_base;
            end
            if httCap > 1e-12
                pathHttUtil(end+1,1) = sum(flow,'all')/httCap; %#ok<AGROW>
            end
        end
        prodValues{mi,stateId} = [prodValues{mi,stateId}; pathProdUtil];
        storageValues{mi,stateId} = [storageValues{mi,stateId}; pathStorageUtil];
        httValues{mi,stateId} = [httValues{mi,stateId}; pathHttUtil];

        if nStage == 1
            enteringLastInventory = sum(p.x_0);
        else
            enteringLastInventory = sum(detailed.xval{pathId,nStage-1});
        end
        actualFinal = detailed.final_loh(pathId,:).';
        actualTotal = sum(actualFinal);
        actualStationGap = sum(max(0,target-actualFinal));
        [maxFeasibleTotal, lpStatus, residual] = solve_max_terminal_total( ...
            p, OOS(pathId,:), tTerm, served);
        maxLpResidual = max(maxLpResidual,residual);
        capacityGap = max(0,targetTotal-maxFeasibleTotal);
        headroom = maxFeasibleTotal-targetTotal;
        totalSufficient = capacityGap <= 1e-7;
        cumulativeService = sum(served,'all');

        b6row = b6(b6.method == method & double(b6.path_id) == pathId, :);
        if ~isempty(b6row)
            if height(b6row) ~= 1
                error('run_step05B7:B6Duplicate', 'Duplicate B6 row for path %d.', pathId);
            end
            b6Residual = max(abs([targetTotal-double(b6row.terminal_loh_total_target_kg), ...
                actualTotal-double(b6row.actual_terminal_total_inventory_kg), ...
                maxFeasibleTotal-double(b6row.max_feasible_terminal_total_inventory_kg), ...
                capacityGap-double(b6row.system_total_capacity_gap_kg)]));
            maxB6Residual = max(maxB6Residual,b6Residual);
        else
            b6Residual = NaN;
        end

        pathRows(end+1,:) = {method,pathId,stateId,a,loc,lf,terminalK,tTerm, ...
            targetTotal,actualTotal,actualStationGap,maxFeasibleTotal,capacityGap, ...
            headroom,totalSufficient,sum(p.x_0),enteringLastInventory, ...
            cumulativeService,cumulativeProduction,cumulativeAvailableProduction, ...
            cumulativeProduction/max(cumulativeAvailableProduction,1e-12), ...
            mean(pathStorageUtil),mean(pathHttUtil),string(lpStatus),residual, ...
            b6Residual,loaded.trainInfo.stop_flag}; %#ok<AGROW>
    end
    clear detailed loaded;
end

for mi = 1:numel(methods)
    for stateId = 1:35
        resources = {"electrolyzer_production",prodValues{mi,stateId}; ...
            "storage",storageValues{mi,stateId}; "htt",httValues{mi,stateId}};
        for r = 1:size(resources,1)
            values = double(resources{r,2});
            values = values(isfinite(values));
            if isempty(values)
                stats = nan(1,7);
                count = 0;
            else
                count = numel(values);
                stats = [mean(values),median(values),quantile(values,0.95), ...
                    max(values),mean(values>=0.95),mean(values>=0.99),min(values)];
            end
            resourceRows(end+1,:) = {methods(mi),stateId,resources{r,1},count, ...
                stats(1),stats(2),stats(3),stats(4),stats(5),stats(6),stats(7)}; %#ok<AGROW>
        end
    end
end

pathNames = {'method','path_id','state_id','a','loc','lf','terminal_state_k', ...
    'terminal_stage','terminal_loh_total_target_kg','actual_final_inventory_total_kg', ...
    'actual_station_gap_total_kg','max_feasible_terminal_inventory_total_kg', ...
    'system_capacity_gap_kg','capacity_headroom_kg','system_total_sufficient', ...
    'initial_inventory_total_kg','inventory_entering_last_preterminal_stage_kg', ...
    'cumulative_normal_h2_service_kg','cumulative_production_kg', ...
    'cumulative_available_production_capacity_kg','path_production_utilization', ...
    'path_mean_storage_utilization','path_mean_htt_utilization','lp_status', ...
    'max_lp_residual','step05b6_reproduction_residual','training_stop_flag'};
pathAudit = cell2table(pathRows, 'VariableNames', pathNames);
writetable(pathAudit, fullfile(outDir, 'all_state_path_capacity_raw.csv'));

resourceNames = {'method','state_id','resource','observation_count', ...
    'mean_utilization','median_utilization','q95_utilization','max_utilization', ...
    'util_ge95_share','util_ge99_share','min_utilization'};
resourceAudit = cell2table(resourceRows, 'VariableNames', resourceNames);
writetable(resourceAudit, fullfile(outDir, 'resource_utilization_state_raw.csv'));

fid = fopen(fullfile(outDir, 'matlab_readonly_integrity_audit.txt'),'w');
if fid < 0
    error('run_step05B7:IntegrityOpen','Cannot write integrity file.');
end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid,'Step-05B-7 MATLAB read-only all-state audit\n\n');
fprintf(fid,'Frozen OOS: %s\n',oosFile);
fprintf(fid,'OOS SHA-256: %s\n',sha256_file(oosFile));
fprintf(fid,'Path rows: %d (expected 12106)\n',height(pathAudit));
fprintf(fid,'SAA terminal-hit rows: %d\n',sum(pathAudit.method=="saa"));
fprintf(fid,'DRO terminal-hit rows: %d\n',sum(pathAudit.method=="chi2_eta003"));
fprintf(fid,'Reached states SAA/DRO: %d/%d\n', ...
    numel(unique(pathAudit.state_id(pathAudit.method=="saa"))), ...
    numel(unique(pathAudit.state_id(pathAudit.method=="chi2_eta003"))));
fprintf(fid,'Optimal LP rows: %d\n',sum(pathAudit.lp_status=="OPTIMAL"));
fprintf(fid,'Maximum LP residual: %.12g\n',maxLpResidual);
fprintf(fid,'Maximum Step-05B-6 reproduction residual: %.12g\n',maxB6Residual);
fprintf(fid,'Maximum saved-evaluation replay residual: %.12g\n',maxSavedEvalResidual);
fprintf(fid,'SAA/DRO deterministic eval seconds: %.12g / %.12g\n',methodElapsed(1),methodElapsed(2));
fprintf(fid,'Resource summary rows: %d\n',height(resourceAudit));
fprintf(fid,'No training, resampling, forward training pass, backward pass, add_cut, TerminalLOH change, or penalty change occurred.\n');
pass = height(pathAudit)==12106 && all(pathAudit.lp_status=="OPTIMAL") && ...
    maxLpResidual<=1e-7 && maxB6Residual<=1e-7 && maxSavedEvalResidual<=1e-8;
fprintf(fid,'MATLAB audit PASS: %d\n',pass);
clear cleanup;
if ~pass
    error('run_step05B7:MechanicalGate','MATLAB mechanical gate failed.');
end
fprintf('Step-05B-7 MATLAB all-state audit completed: %s\n',outDir);
end


function [maxTotal,status,maxResidual] = solve_max_terminal_total(p,path,tTerm,servedMatrix)
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
model = struct();
model.A = sparse([A;Aeq]);
model.rhs = [b;beq];
model.sense = [repmat('<',size(A,1),1);repmat('=',size(Aeq,1),1)];
model.lb = lb;
model.ub = ub;
model.obj = zeros(nvars,1);
model.obj(idx{nStage}.x) = -1;
model.modelsense = 'min';
params = struct('OutputFlag',0,'InfUnbdInfo',1);
result = gurobi(model,params);
status = string(result.status);
if status ~= "OPTIMAL"
    maxTotal = NaN;
    maxResidual = inf;
    return;
end
maxTotal = sum(result.x(idx{nStage}.x));
maxResidual = max([max(abs(Aeq*result.x-beq)); max(A*result.x-b); 0]);
end


function require_file(path)
if ~isfile(path)
    error('run_step05B7:MissingFile','Missing required file: %s',path);
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
