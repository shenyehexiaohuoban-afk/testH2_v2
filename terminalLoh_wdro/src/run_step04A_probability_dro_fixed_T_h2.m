function run_step04A_probability_dro_fixed_T_h2()
%RUN_STEP04A_PROBABILITY_DRO_FIXED_T_H2 Fixed-T and small flat-DRO prototype.

runTic = tic;
thisDir = fileparts(mfilename('fullpath'));
moduleDir = fileparts(thisDir);
rootDir = fileparts(moduleDir);
addpath(rootDir); addpath(thisDir);
for candidate = {fullfile(getenv('GUROBI_HOME'), 'matlab'), ...
        'D:\gurobi1201\win64\matlab', 'C:\gurobi1201\win64\matlab'}
    if ~isempty(candidate{1}) && isfolder(candidate{1}), addpath(candidate{1}); end
end
assert_git_gate("task/002-stage2b-b3-smoke", ...
    "96143491395d291f4e46791836736c5a9dd06253");
if ~ismember(exist('gurobi', 'file'), [2, 3])
    error('Step-04A requires the Gurobi MATLAB interface.');
end

outputDir = fullfile(rootDir, 'results', 'task-002-stage2b-b3-smoke', ...
    '41-probability-dro-mainline-feasibility', 'run-003');
selectionFile = fullfile(outputDir, 'selected_path_ids.csv');
tFile = fullfile(rootDir, 'results', 'task-002-stage2b-b3-smoke', ...
    '35-period-vs-aggregate-saa-r2000', 'run-001', 'terminalLOH_r2000.csv');
required = {selectionFile, tFile, ...
    fullfile(thisDir, 'recover_step03Y_prefix_entries_h2.m'), ...
    fullfile(thisDir, 'evaluate_step03Y_period_fixed_T_recourse_h2.m')};
for ii = 1:numel(required)
    if ~isfile(required{ii}), error('Missing required input: %s', required{ii}); end
end
outputs = {'fixed_T_losses_raw.csv', 'fixed_T_loss_solver_audit.csv', ...
    'small_scale_terminalLOH_prototype_summary.csv', ...
    'small_scale_terminalLOH_solver_audit.txt'};
for ii = 1:numel(outputs)
    if isfile(fullfile(outputDir, outputs{ii}))
        error('Refusing to overwrite Step-04A output: %s', outputs{ii});
    end
end

selection = readtable(selectionFile, 'TextType', 'string');
tPublished = readtable(tFile, 'TextType', 'string');
states = [7, 19]; R = 200; M = 2000; gamma = 2;
Cap = [300, 200, 100, 150];
solverConfig = struct('gurobiOutputFlag', 0, 'gurobiFeasibilityTol', 1e-9, ...
    'gurobiOptimalityTol', 1e-9, 'gurobiTimeLimit', 600, ...
    'objectiveScale', 1);
lossRows = cell(numel(states) * 5 * R, 21); lr = 0;
auditRows = cell(numel(states) * 5, 13); ar = 0;
peakWorkingSet = memory_snapshot();

stateEntries = cell(numel(states), 1);
stateContexts = cell(numel(states), 1);
for ss = 1:numel(states)
    stateId = states(ss);
    selected = selection(selection.initial_state_id == stateId, :);
    if height(selected) ~= R || ...
            ~isequal(double(selected.scenario_id), (1:R).') || ...
            ~isequal(double(selected.path_id), (1:R).')
        error('State %d selection is not the required deterministic 1:R prefix.', stateId);
    end
    fprintf('Step-04A fixed-T replay: state=%d R=%d.\n', stateId, R);
    [entry, context] = recover_step03Y_prefix_entries_h2(rootDir, stateId, R, false);
    if ~entry.audit.all_final_DAC_exact || ~entry.audit.all_stream_hashes_match || ...
            entry.audit.max_DAC_error > 1e-10
        error('State %d deterministic period D/A/C replay failed.', stateId);
    end
    stateEntries{ss} = entry; stateContexts{ss} = context;
    periodT = read_period_T(tPublished, stateId);
    Tset = [zeros(1, 4); 0.5 .* Cap; Cap; periodT; ...
        [0.25, 0.50, 0.75, 1.00] .* Cap];
    labels = ["ZERO", "HALF_CAPACITY", "FULL_CAPACITY", ...
        "STEP03YF_PERIOD_R2000", "ASYMMETRIC_CAPACITY_FRACTION"];
    for tt = 1:5
        Trows = repmat(Tset(tt, :), R, 1);
        out = evaluate_step03Y_period_fixed_T_recourse_h2(entry.Dperiod, ...
            entry.Aperiod, entry.Cperiod, Trows, M, solverConfig);
        ar = ar + 1;
        peakWorkingSet = max(peakWorkingSet, memory_snapshot());
        auditRows(ar, :) = {stateId, labels(tt), string(out.status), 1, R, ...
            out.runtime_sec, out.objective_reconstruction_abs_error, ...
            out.max_demand_balance_error, out.max_site_capacity_violation, ...
            entry.audit.max_DAC_error, peakWorkingSet, 0, 0};
        if out.exitflag ~= 1
            continue;
        end
        for rr = 1:R
            lr = lr + 1;
            lossRows(lr, :) = {stateId, rr, double(entry.identity.path_id(rr)), ...
                labels(tt), Tset(tt, 1), Tset(tt, 2), Tset(tt, 3), Tset(tt, 4), ...
                out.operating_loss(rr), out.service_cost(rr), out.shortage_kg(rr), ...
                out.shortage_loss(rr), out.site_service_total(rr, 1), ...
                out.site_service_total(rr, 2), out.site_service_total(rr, 3), ...
                out.site_service_total(rr, 4), string(out.status), out.runtime_sec, ...
                out.max_demand_balance_error, out.max_site_capacity_violation, ...
                entry.audit.max_DAC_error};
        end
    end
end

lossTbl = cell2table(lossRows(1:lr, :), 'VariableNames', ...
    {'initial_state_id','scenario_id','path_id','T_label','T1_kg','T2_kg', ...
    'T3_kg','T4_kg','operating_loss','service_cost','shortage_kg', ...
    'shortage_loss','site1_service_kg','site2_service_kg','site3_service_kg', ...
    'site4_service_kg','solver_status','batch_runtime_sec', ...
    'max_demand_balance_error','max_site_capacity_violation','replay_max_DAC_error'});
auditTbl = cell2table(auditRows(1:ar, :), 'VariableNames', ...
    {'initial_state_id','T_label','solver_status','solver_call_count', ...
    'scenario_evaluation_count','batch_runtime_sec', ...
    'objective_reconstruction_abs_error','max_demand_balance_error', ...
    'max_site_capacity_violation','replay_max_DAC_error', ...
    'peak_working_set_bytes','random_call_count','failed_scenario_count'});
writetable(lossTbl, fullfile(outputDir, 'fixed_T_losses_raw.csv'));
writetable(auditTbl, fullfile(outputDir, 'fixed_T_loss_solver_audit.csv'));

%% Gate 11: isolated R=100 flat chi-square TerminalLOH prototype on state 19.
prototypeState = 19; prototypeR = 100; prototypeEta = 0.01;
prototypeIndex = find(states == prototypeState, 1);
entry = stateEntries{prototypeIndex};
context = stateContexts{prototypeIndex}; %#ok<NASGU>
D = entry.Dperiod(1:prototypeR, :, :);
A = entry.Aperiod(1:prototypeR, :, :, :);
C = entry.Cperiod(1:prototypeR, :, :, :);
prototypeConfig = struct('OutputFlag', 0, 'FeasibilityTol', 1e-8, ...
    'OptimalityTol', 1e-8, 'BarConvTol', 1e-9, 'TimeLimit', 1800, ...
    'objectiveScale', 1e5);
saa = solve_terminal_loh_saa(D, A, C, Cap, M, gamma, prototypeConfig);
dro = solve_terminal_loh_flat_chi2_qcp(D, A, C, Cap, M, gamma, ...
    prototypeEta, prototypeConfig);
if saa.exitflag ~= 1 || dro.exitflag ~= 1
    error('Small-scale TerminalLOH prototype did not solve to OPTIMAL.');
end
evalConfig = solverConfig; evalConfig.gurobiTimeLimit = 600;
saaEval = evaluate_step03Y_period_fixed_T_recourse_h2(D, A, C, ...
    repmat(saa.T.', prototypeR, 1), M, evalConfig);
droEval = evaluate_step03Y_period_fixed_T_recourse_h2(D, A, C, ...
    repmat(dro.T.', prototypeR, 1), M, evalConfig);
if saaEval.exitflag ~= 1 || droEval.exitflag ~= 1
    error('Prototype optimized-T recourse evaluation failed.');
end
[saaWorst, saaP, saaDiv] = solve_chi2_active_set( ...
    ones(prototypeR, 1) / prototypeR, saaEval.operating_loss, prototypeEta);
[droWorst, droP, droDiv] = solve_chi2_active_set( ...
    ones(prototypeR, 1) / prototypeR, droEval.operating_loss, prototypeEta);
prototypeRows = {
    "WEIGHTED_SAA", prototypeState, prototypeR, 0, saa.T(1), saa.T(2), ...
    saa.T(3), saa.T(4), mean(saaEval.operating_loss), saaWorst, ...
    gamma * sum(saa.T) + mean(saaEval.operating_loss), ...
    gamma * sum(saa.T) + saaWorst, max(abs(saaP - 1/prototypeR)), ...
    saa.runtime_sec, saa.status, saa.model_residual, 1, 1; ...
    "FLAT_CHI2_DRO", prototypeState, prototypeR, prototypeEta, ...
    dro.T(1), dro.T(2), dro.T(3), dro.T(4), mean(droEval.operating_loss), ...
    droWorst, gamma * sum(dro.T) + mean(droEval.operating_loss), ...
    gamma * sum(dro.T) + droWorst, max(abs(droP - 1/prototypeR)), ...
    dro.runtime_sec, dro.status, dro.model_residual, 1, 1};
prototypeTbl = cell2table(prototypeRows, 'VariableNames', ...
    {'model','initial_state_id','R','eta','T1_kg','T2_kg','T3_kg','T4_kg', ...
    'nominal_expected_operating_cost','eta001_worst_expected_operating_cost', ...
    'nominal_total_objective','eta001_robust_total_objective', ...
    'maximum_probability_shift','solver_runtime_sec','solver_status', ...
    'model_residual','optimization_solver_call_count','evaluation_solver_call_count'});
writetable(prototypeTbl, fullfile(outputDir, ...
    'small_scale_terminalLOH_prototype_summary.csv'));

checkMessages = checkcode(mfilename('fullpath'), '-id');
checkErrorCount = sum(arrayfun(@(x) startsWith(string(x.id), "MATLAB:"), checkMessages));
fid = fopen(fullfile(outputDir, 'small_scale_terminalLOH_solver_audit.txt'), 'w');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'status=PASS\n');
fprintf(fid, 'prototype_state=%d\nprototype_R=%d\nprototype_eta=%.17g\n', ...
    prototypeState, prototypeR, prototypeEta);
fprintf(fid, 'SAA_status=%s\nDRO_status=%s\n', saa.status, dro.status);
fprintf(fid, 'SAA_runtime_sec=%.9f\nDRO_runtime_sec=%.9f\n', ...
    saa.runtime_sec, dro.runtime_sec);
fprintf(fid, 'SAA_eta001_divergence=%.17g\nDRO_eta001_divergence=%.17g\n', ...
    saaDiv, droDiv);
fprintf(fid, 'optimization_LP_calls=1\noptimization_QCP_calls=1\n');
fprintf(fid, 'fixed_T_evaluation_LP_calls=2\n');
fprintf(fid, 'random_call_count=0\ncheckcode_message_count=%d\ncheckcode_error_count=%d\n', ...
    numel(checkMessages), checkErrorCount);
fprintf(fid, 'formal_model_modified=false\nformal_WDRO_calls=0\nMSP_calls=0\n');
fprintf(fid, 'total_matlab_runner_runtime_sec=%.9f\npeak_working_set_bytes=%.0f\n', ...
    toc(runTic), max(peakWorkingSet, memory_snapshot()));
clear cleanup
fprintf('Step-04A MATLAB fixed-T and prototype outputs completed.\n');
end

function T = read_period_T(tbl, stateId)
rows = tbl(double(tbl.initial_state_id) == stateId & double(tbl.R) == 2000, :);
rows = sortrows(rows, 'site_id');
if height(rows) ~= 4 || ~isequal(double(rows.site_id), (1:4).')
    error('Cannot recover Step-03Y-F period T for state %d.', stateId);
end
T = double(rows.T_period_kg).';
end

function sol = solve_terminal_loh_saa(D, A, C, Cap, M, gamma, config)
[R, K, N] = size(D); I = size(A, 3); scale = config.objectiveScale;
Ceff = C; Ceff(~isfinite(Ceff) | A <= 0.5) = 0;
next = 1; idx.T = next:(next+I-1); next = next + I;
idx.y = reshape(next:(next+R*K*I*N-1), [R,K,I,N]); next = next + R*K*I*N;
idx.u = reshape(next:(next+R*K*N-1), [R,K,N]); nvar = next + R*K*N - 1;
obj = zeros(nvar,1); obj(idx.T) = gamma/scale;
obj(idx.y(:)) = Ceff(:)/(R*scale); obj(idx.u(:)) = M/(R*scale);
lb = zeros(nvar,1); ub = inf(nvar,1); ub(idx.T) = Cap(:);
yUpper = A .* reshape(D,[R,K,1,N]);
ub(idx.y(:)) = yUpper(:);
[Acon,rhs,sense] = recourse_constraints(idx,D,R,K,I,N,nvar,true);
model = struct('A',Acon,'obj',obj,'rhs',rhs,'sense',sense,'lb',lb,'ub',ub,'modelsense','min');
params = gurobi_params(config); ticSolve = tic; result = gurobi(model,params); runtime = toc(ticSolve);
sol = struct('status',string(result.status),'exitflag',0,'T',NaN(I,1), ...
    'runtime_sec',runtime,'model_residual',NaN,'objective',NaN);
if strcmp(result.status,'OPTIMAL')
    sol.exitflag=1; sol.T=result.x(idx.T); sol.objective=result.objval*scale;
    equalityRows = sense == '=';
    sol.model_residual=max(abs(Acon(equalityRows,:)*result.x - rhs(equalityRows)),[],'omitnan');
end
end

function sol = solve_terminal_loh_flat_chi2_qcp(D,A,C,Cap,M,gamma,eta,config)
[R,K,N]=size(D); I=size(A,3); scale=config.objectiveScale; q=ones(R,1)/R;
Ceff=C; Ceff(~isfinite(Ceff)|A<=0.5)=0;
next=1; idx.T=next:(next+I-1); next=next+I;
idx.y=reshape(next:(next+R*K*I*N-1),[R,K,I,N]); next=next+R*K*I*N;
idx.u=reshape(next:(next+R*K*N-1),[R,K,N]); next=next+R*K*N;
idx.z=next:(next+R-1); next=next+R; idx.nu=next; next=next+1;
idx.lambda=next; next=next+1; idx.t=next:(next+R-1); next=next+R;
idx.h=next:(next+R-1); nvar=next+R-1;
obj=zeros(nvar,1); obj(idx.T)=gamma/scale; obj(idx.nu)=1;
obj(idx.lambda)=eta-1; obj(idx.h)=q;
lb=zeros(nvar,1); ub=inf(nvar,1); ub(idx.T)=Cap(:); lb(idx.nu)=-inf;
yUpper=A.*reshape(D,[R,K,1,N]);
ub(idx.y(:))=yUpper(:);
[baseA,baseRhs,baseSense]=recourse_constraints(idx,D,R,K,I,N,nvar,true);
nExtra=2*R;
row=[]; col=[]; val=[]; rhs=zeros(nExtra,1); sense=repmat('<',nExtra,1);
rr=0;
for s=1:R
    rr=rr+1; cols=[idx.z(s),reshape(idx.y(s,:,:,:),1,[]),reshape(idx.u(s,:,:),1,[])];
    values=[1,-reshape(Ceff(s,:,:,:),1,[])/scale,-M*ones(1,K*N)/scale];
    row=[row,repmat(rr,1,numel(cols))]; col=[col,cols]; val=[val,values]; %#ok<AGROW>
    sense(rr)='=';
    rr=rr+1; cols=[idx.z(s),idx.nu,idx.lambda,idx.t(s)]; values=[1,-1,2,-1];
    row=[row,repmat(rr,1,4)]; col=[col,cols]; val=[val,values]; %#ok<AGROW>
end
extraA=sparse(row,col,val,nExtra,nvar);
model=struct('A',[baseA;extraA],'obj',obj,'rhs',[baseRhs;rhs], ...
    'sense',[baseSense;sense],'lb',lb,'ub',ub,'modelsense','min');
qcon=struct([]);
for s=1:R
    Q=sparse(nvar,nvar); Q(idx.t(s),idx.t(s))=1;
    Q(idx.lambda,idx.h(s))=-2; Q(idx.h(s),idx.lambda)=-2;
    qcon(s).Qc=Q;
    qcon(s).q=zeros(nvar,1);
    qcon(s).rhs=0;
    qcon(s).sense='<';
    qcon(s).name=sprintf('chi2_rotated_%d',s); %#ok<AGROW>
end
model.quadcon=qcon; params=gurobi_params(config); params.BarConvTol=config.BarConvTol;
ticSolve=tic; result=gurobi(model,params); runtime=toc(ticSolve);
sol=struct('status',string(result.status),'exitflag',0,'T',NaN(I,1), ...
    'runtime_sec',runtime,'model_residual',NaN,'objective',NaN);
if strcmp(result.status,'OPTIMAL')
    sol.exitflag=1; sol.T=result.x(idx.T); sol.objective=result.objval*scale;
    equalityRows = model.sense == '=';
    sol.model_residual=max(abs(model.A(equalityRows,:)*result.x- ...
        model.rhs(equalityRows)),[],'omitnan');
end
end

function [Acon,rhs,sense]=recourse_constraints(idx,D,R,K,I,N,nvar,includeT)
nRows=R*K*N+R*I; maxNnz=R*K*N*(I+1)+R*I*(K*N+double(includeT));
ri=zeros(maxNnz,1); ci=zeros(maxNnz,1); vv=zeros(maxNnz,1);
rhs=zeros(nRows,1); sense=repmat('<',nRows,1); rr=0; nz=0;
for s=1:R
    for k=1:K
        for n=1:N
            rr=rr+1; cols=[reshape(idx.y(s,k,:,n),1,[]),idx.u(s,k,n)];
            pos=nz+(1:numel(cols));ri(pos)=rr;ci(pos)=cols;vv(pos)=1;nz=nz+numel(cols);
            rhs(rr)=D(s,k,n);sense(rr)='=';
        end
    end
    for i=1:I
        rr=rr+1; cols=reshape(idx.y(s,:,i,:),1,[]);
        values=ones(1,numel(cols));
        if includeT, cols=[cols,idx.T(i)];values=[values,-1];end
        pos=nz+(1:numel(cols));ri(pos)=rr;ci(pos)=cols;vv(pos)=values;nz=nz+numel(cols);
    end
end
Acon=sparse(ri(1:nz),ci(1:nz),vv(1:nz),nRows,nvar);
end

function params=gurobi_params(config)
params=struct('OutputFlag',config.OutputFlag,'FeasibilityTol',config.FeasibilityTol, ...
    'OptimalityTol',config.OptimalityTol,'TimeLimit',config.TimeLimit,'InfUnbdInfo',1);
end

function [worst,p,divergence]=solve_chi2_active_set(q,v,eta)
q=q(:)/sum(q);v=v(:);active=true(size(q));tol=1e-12;
if eta<=tol||max(v)-min(v)<=tol,p=q;
else
    maxMask=abs(v-max(v))<=tol*max(1,abs(max(v)));qmax=sum(q(maxMask));
    if eta>=1/qmax-1-tol,p=zeros(size(q));p(maxMask)=q(maxMask)/qmax;
    else
        while true
            qa=q(active);va=v(active);qs=sum(qa);minDiv=1/qs-1;
            mu=sum(qa.*va)/qs;varNum=sum(qa.*(va-mu).^2);
            pa=qa/qs+sqrt(max(0,eta-minDiv)/varNum).*qa.*(va-mu);
            bad=pa<-100*tol;
            if ~any(bad),p=zeros(size(q));ids=find(active);p(ids)=max(pa,0);p=p/sum(p);break;end
            ids=find(active);active(ids(bad))=false;
        end
    end
end
worst=sum(p.*v);divergence=sum((p-q).^2./q);
end

function assert_git_gate(expectedBranch,expectedHead)
[s1,branch]=system('git branch --show-current');[s2,head]=system('git rev-parse HEAD');
[s3,upstream]=system('git rev-parse @{upstream}');
if s1~=0||s2~=0||s3~=0||strtrim(string(branch))~=expectedBranch|| ...
        strtrim(string(head))~=expectedHead||strtrim(string(upstream))~=expectedHead
    error('Frozen Git gate failed.');
end
end

function bytes=memory_snapshot()
bytes=0;
try
    process=System.Diagnostics.Process.GetCurrentProcess();
    bytes=double(process.PeakWorkingSet64);
catch
    try
        user=memory;
        bytes=double(user.MemUsedMATLAB);
    catch
        bytes=0;
    end
end
end
