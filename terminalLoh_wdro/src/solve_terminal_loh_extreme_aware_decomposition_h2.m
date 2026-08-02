function sol = solve_terminal_loh_extreme_aware_decomposition_h2( ...
        Dnom,Anom,Cnom,q,Dext,Aext,Cext,pathId,replicaRank, ...
        Cap,M,gamma,eta,betaExt,riskType,topK,config)
%SOLVE_TERMINAL_LOH_EXTREME_AWARE_DECOMPOSITION_H2 Certified convex cuts.
%
% The nominal term is the frozen weighted SAA risk (eta=0) or the exact
% Pearson chi-square risk (eta>0).  The extreme term is either the maximum
% path loss or the average of the top-k path losses, where each path loss is
% the maximum across its frozen deterministic consequence replicas.  No
% probability mass is assigned to extreme paths or replicas.

% Every evaluated T supplies globally valid nominal and extreme subgradient
% cuts from the frozen recourse site-capacity duals.  The master objective is
% a lower bound and complete fixed-T evaluation supplies an upper bound.

if nargin<17||isempty(config),config=struct();end
config=fill_defaults(config);
q=double(q(:));q=q./sum(q);Cap=double(Cap(:));pathId=double(pathId(:));
replicaRank=double(replicaRank(:));riskType=upper(string(riskType));
G=numel(q);E=numel(pathId);I=numel(Cap);
if G<1||E<1||I~=4||~isequal(size(Dnom,1),G)||~isequal(size(Dext,1),E)|| ...
        ~isequal(size(Anom),[G,3,I,size(Dnom,3)])|| ...
        ~isequal(size(Cnom),size(Anom))|| ...
        ~isequal(size(Aext),[E,3,I,size(Dext,3)])|| ...
        ~isequal(size(Cext),size(Aext))|| ...
        any(~isfinite(q))||any(q<=0)||abs(sum(q)-1)>1e-10|| ...
        ~isscalar(eta)||~isfinite(eta)||eta<0|| ...
        ~isscalar(betaExt)||~isfinite(betaExt)||betaExt<0|| ...
        ~ismember(riskType,["R1_MAX","R2_TOPK"])
    error('solve_terminal_loh_extreme_aware_decomposition_h2:BadInput', ...
        'Nominal/extreme arrays, weights, or risk settings are invalid.');
end

% Evaluate nominal and frozen-extreme recourse in one Gurobi call per cut.
% This is algebraically identical to two independent block-diagonal LPs,
% but avoids repeated MEX allocation/free cycles that proved unstable in
% long isolated runs under MATLAB R2022a.
Dall=cat(1,Dnom,Dext);Aall=cat(1,Anom,Aext);Call=cat(1,Cnom,Cext);
[pathValues,~,pathMap]=unique(pathId,'sorted');nPaths=numel(pathValues);
if riskType=="R1_MAX",topK=1;end
if ~isscalar(topK)||topK<1||topK>nPaths||topK~=floor(topK)
    error('solve_terminal_loh_extreme_aware_decomposition_h2:BadTopK', ...
        'topK must be an integer between one and the number of paths.');
end
for pathCheck=1:nPaths
    ranks=sort(replicaRank(pathMap==pathCheck));
    if ~isequal(ranks(:),(1:numel(ranks)).')
        error('solve_terminal_loh_extreme_aware_decomposition_h2:ReplicaIdentity', ...
            'Replica ranks must be complete and unique within every path.');
    end
end

started=tic;previousRuntime=0;iterationCompleted=0;
if isfield(config,'resumeState')&&~isempty(config.resumeState)
    state=config.resumeState;validate_resume_state(state,I,eta,betaExt,riskType,topK);
    points=state.points;nomRisk=state.nomRisk;extRisk=state.extRisk;
    nomGrad=state.nomGrad;extGrad=state.extGrad;
    activePathCell=state.activePathCell;activeReplicaCell=state.activeReplicaCell;
    evaluationRuntime=state.evaluationRuntime;masterRuntime=state.masterRuntime;
    bestUpper=state.bestUpper;bestIndex=state.bestIndex;
    bestNomLoss=state.bestNomLoss;bestExtLoss=state.bestExtLoss;
    bestPathLoss=state.bestPathLoss;bestProbability=state.bestProbability;
    bestNomFixed=state.bestNomFixed;bestExtFixed=state.bestExtFixed;
    bestActivePaths=state.bestActivePaths;bestActiveRows=state.bestActiveRows;
    masterCalls=state.masterCalls;lowerBound=state.lowerBound;
    convergenceRows=state.convergenceRows;iterationCompleted=state.iterationCompleted;
    previousRuntime=state.solveRuntimeSec;
else
    points=zeros(0,I);nomRisk=zeros(0,1);extRisk=zeros(0,1);
    nomGrad=zeros(0,I);extGrad=zeros(0,I);
    activePathCell=cell(0,1);activeReplicaCell=cell(0,1);
    evaluationRuntime=0;masterRuntime=0;bestUpper=inf;bestIndex=0;
    bestNomLoss=[];bestExtLoss=[];bestPathLoss=[];bestProbability=[];
    bestNomFixed=struct();bestExtFixed=struct();bestActivePaths=[];bestActiveRows=[];
    masterCalls=0;lowerBound=-inf;convergenceRows=cell(0,10);
    initial=[zeros(1,I);0.5.*Cap.';Cap.'];
    if isfield(config,'initialT')&&numel(config.initialT)==I
        initial=[reshape(double(config.initialT),1,I);initial];
    end
    initial=unique(initial,'rows','stable');
    for ii=1:size(initial,1),add_point(initial(ii,:));end
end
status="BATCH_LIMIT";iteration=iterationCompleted;
batchIterations=min(config.batchIterationLimit,config.maximumIterations-iterationCompleted);
for localIteration=1:batchIterations
    iteration=iterationCompleted+localIteration;
    if toc(started)>=config.totalTimeLimit,status="TIME_LIMIT";break;end
    masterTic=tic;master=solve_master(points,nomRisk,nomGrad,extRisk,extGrad, ...
        Cap,gamma,betaExt,config);masterRuntime=masterRuntime+toc(masterTic);
    masterCalls=masterCalls+1;
    if master.status~="OPTIMAL",status="MASTER_"+master.status;break;end
    lowerBound=master.objective;absoluteGap=bestUpper-lowerBound;
    relativeGap=absoluteGap/max(1,abs(bestUpper));
    convergenceRows(end+1,:)={iteration,size(points,1),lowerBound,bestUpper, ...
        absoluteGap,relativeGap,master.T(1),master.T(2),master.T(3),master.T(4)}; %#ok<AGROW>
    fprintf('  extreme-aware %s k=%d eta=%.4g beta=%.6g iter=%d cuts=%d LB=%.9f UB=%.9f gap=%.6g rel=%.3g\n', ...
        riskType,topK,eta,betaExt,iteration,size(points,1),lowerBound,bestUpper,absoluteGap,relativeGap);
    if absoluteGap<=config.absoluteGapTolerance||relativeGap<=config.relativeGapTolerance
        status="OPTIMAL";break;
    end
    distance=max(abs(points-master.T.'),[],2);
    if any(distance<=config.pointTolerance),status="NUMERICAL_STALL";break;end
    add_point(master.T.');
end

if status=="BATCH_LIMIT"&&iteration>=config.maximumIterations,status="ITERATION_LIMIT";end

absoluteGap=bestUpper-lowerBound;relativeGap=absoluteGap/max(1,abs(bestUpper));
if status=="ITERATION_LIMIT"&&(absoluteGap<=config.absoluteGapTolerance|| ...
        relativeGap<=config.relativeGapTolerance),status="OPTIMAL";end
[nomCutViolation,extCutViolation]=cut_validity(points,nomRisk,nomGrad,extRisk,extGrad);
activePathText=strings(size(points,1),1);activeReplicaText=strings(size(points,1),1);
for rr=1:size(points,1)
    activePathText(rr)=join(string(activePathCell{rr}),';');
    activeReplicaText(rr)=join(string(activeReplicaCell{rr}),';');
end
cutId=(1:size(points,1)).';cutHistory=table(cutId,points(:,1),points(:,2), ...
    points(:,3),points(:,4),nomRisk,extRisk,nomGrad(:,1),nomGrad(:,2), ...
    nomGrad(:,3),nomGrad(:,4),extGrad(:,1),extGrad(:,2),extGrad(:,3), ...
    extGrad(:,4),activePathText,activeReplicaText, ...
    'VariableNames',{'cut_id','T1','T2','T3','T4','nominal_risk', ...
    'extreme_risk','nominal_g1','nominal_g2','nominal_g3','nominal_g4', ...
    'extreme_g1','extreme_g2','extreme_g3','extreme_g4', ...
    'active_path_ids','active_replica_rows'});
if isempty(convergenceRows)
    convergence=cell2table(cell(0,10),'VariableNames',{'iteration','cut_count', ...
        'lower_bound','upper_bound','absolute_gap','relative_gap','master_T1','master_T2','master_T3','master_T4'});
else
    convergence=cell2table(convergenceRows,'VariableNames',{'iteration','cut_count', ...
        'lower_bound','upper_bound','absolute_gap','relative_gap','master_T1','master_T2','master_T3','master_T4'});
end

sol=struct('mode',"EXTREME_AWARE_CERTIFIED_DECOMPOSITION",'status',status, ...
    'exitflag',double(status=="OPTIMAL"),'eta',eta,'beta_ext',betaExt, ...
    'risk_type',riskType,'top_k',topK,'path_count',nPaths,'replica_count',E, ...
    'T',NaN(I,1),'objective_value',bestUpper,'nominal_risk_value',NaN, ...
    'extreme_risk_value',NaN,'first_stage_cost',NaN, ...
    'decomposition_lower_bound',lowerBound,'decomposition_upper_bound',bestUpper, ...
    'decomposition_absolute_gap',absoluteGap,'decomposition_relative_gap',relativeGap, ...
    'decomposition_iteration_count',iteration,'decomposition_cut_count',size(points,1), ...
    'master_solver_calls',masterCalls,'nominal_recourse_solver_calls',size(points,1), ...
    'extreme_recourse_solver_calls',size(points,1),'recourse_solver_calls',size(points,1), ...
    'solve_runtime_sec',previousRuntime+toc(started),'master_runtime_sec',masterRuntime, ...
    'evaluation_runtime_sec',evaluationRuntime,'nominal_cut_max_violation',nomCutViolation, ...
    'extreme_cut_max_violation',extCutViolation,'cut_history',cutHistory, ...
    'convergence_history',convergence,'constructed_R_by_R_matrix',false);
if bestIndex>0
    sol.T=points(bestIndex,:).';sol.first_stage_cost=gamma*sum(sol.T);
    sol.nominal_risk_value=nomRisk(bestIndex);sol.extreme_risk_value=extRisk(bestIndex);
    sol.nominal_group_loss=bestNomLoss;sol.extreme_replica_loss=bestExtLoss;
    sol.extreme_path_loss=bestPathLoss;sol.nominal_worst_probability=bestProbability;
    sol.nominal_fixed=bestNomFixed;sol.extreme_fixed=bestExtFixed;
    sol.active_path_ids=bestActivePaths;sol.active_replica_rows=bestActiveRows;
    sol.objective_reconstruction_error=abs(bestUpper-(sol.first_stage_cost+ ...
        sol.nominal_risk_value+betaExt*sol.extreme_risk_value));
end
if status=="BATCH_LIMIT"
    sol.resume_state=struct('version',1,'eta',eta,'betaExt',betaExt, ...
        'riskType',riskType,'topK',topK,'points',points,'nomRisk',nomRisk, ...
        'extRisk',extRisk,'nomGrad',nomGrad,'extGrad',extGrad, ...
        'activePathCell',{activePathCell},'activeReplicaCell',{activeReplicaCell}, ...
        'evaluationRuntime',evaluationRuntime,'masterRuntime',masterRuntime, ...
        'bestUpper',bestUpper,'bestIndex',bestIndex,'bestNomLoss',bestNomLoss, ...
        'bestExtLoss',bestExtLoss,'bestPathLoss',bestPathLoss, ...
        'bestProbability',bestProbability,'bestNomFixed',bestNomFixed, ...
        'bestExtFixed',bestExtFixed,'bestActivePaths',bestActivePaths, ...
        'bestActiveRows',bestActiveRows,'masterCalls',masterCalls, ...
        'lowerBound',lowerBound,'convergenceRows',{convergenceRows}, ...
        'iterationCompleted',iteration,'solveRuntimeSec',sol.solve_runtime_sec);
end

    function add_point(T)
        T=max(zeros(size(Cap.')),min(Cap.',double(T)));
        evalConfig=config;evalConfig.gurobiTimeLimit=min(config.recourseTimeLimit, ...
            max(1,config.totalTimeLimit));evalTic=tic;
        fixedAll=evaluate_terminal_loh_period_fixed_T_sparse_h2(Dall,Aall,Call, ...
            repmat(T,G+E,1),M,evalConfig);
        evaluationRuntime=evaluationRuntime+toc(evalTic);
        if fixedAll.exitflag~=1
            error('solve_terminal_loh_extreme_aware_decomposition_h2:RecourseFailure', ...
                'Nominal or extreme fixed-T recourse failed.');
        end
        if any(~isfinite(fixedAll.site_capacity_dual),'all')
            error('solve_terminal_loh_extreme_aware_decomposition_h2:MissingDual', ...
                'Finite recourse site-capacity duals are required.');
        end
        nomLoss=fixedAll.operating_loss(1:G);
        extLoss=fixedAll.operating_loss(G+1:G+E);
        nomDual=fixedAll.site_capacity_dual(1:G,:);
        extDual=fixedAll.site_capacity_dual(G+1:G+E,:);
        if eta<=1e-14
            p=q;nRisk=sum(q.*nomLoss);
        else
            adversary=solve_flat_chi2_worst_probability_h2(q,nomLoss,eta);
            p=adversary.worst_probability;nRisk=adversary.worst_value;
        end
        nGradient=sum(p.*nomDual,1);
        pLoss=zeros(nPaths,1);activeReplica=zeros(nPaths,1);
        for pathIndex=1:nPaths
            members=find(pathMap==pathIndex);[pLoss(pathIndex),local]=max(extLoss(members));
            activeReplica(pathIndex)=members(local);
        end
        if riskType=="R1_MAX"
            [eRisk,selected]=max(pLoss);selected=selected(:);
        else
            [~,order]=sortrows([-pLoss,pathValues],[1,2]);selected=order(1:topK);
            eRisk=mean(pLoss(selected));
        end
        activeRows=activeReplica(selected);
        eGradient=mean(extDual(activeRows,:),1);
        if any(nGradient>config.subgradientSignTolerance)|| ...
                any(eGradient>config.subgradientSignTolerance)
            error('solve_terminal_loh_extreme_aware_decomposition_h2:SubgradientSign', ...
                'Positive capacity subgradient violates nonincreasing recourse.');
        end
        obj=gamma*sum(T)+nRisk+betaExt*eRisk;
        points(end+1,:)=T;nomRisk(end+1,1)=nRisk;extRisk(end+1,1)=eRisk; %#ok<AGROW>
        nomGrad(end+1,:)=nGradient;extGrad(end+1,:)=eGradient; %#ok<AGROW>
        activePathCell{end+1,1}=pathValues(selected).'; %#ok<AGROW>
        activeReplicaCell{end+1,1}=activeRows.'; %#ok<AGROW>
        if obj<bestUpper
            bestUpper=obj;bestIndex=size(points,1);bestNomLoss=nomLoss;
            bestExtLoss=extLoss;bestPathLoss=pLoss;bestProbability=p;
            bestNomFixed=compact_fixed(fixedAll);bestExtFixed=compact_fixed(fixedAll);
            bestActivePaths=pathValues(selected).';bestActiveRows=activeRows.';
        end
    end
end

function out=compact_fixed(fixed)
out=struct('max_demand_balance_error',fixed.max_demand_balance_error, ...
    'max_site_capacity_violation',fixed.max_site_capacity_violation);
end

function validate_resume_state(state,I,eta,betaExt,riskType,topK)
required={'version','eta','betaExt','riskType','topK','points','nomRisk','extRisk', ...
    'nomGrad','extGrad','activePathCell','activeReplicaCell','evaluationRuntime', ...
    'masterRuntime','bestUpper','bestIndex','bestNomLoss','bestExtLoss','bestPathLoss', ...
    'bestProbability','bestNomFixed','bestExtFixed','bestActivePaths','bestActiveRows', ...
    'masterCalls','lowerBound','convergenceRows','iterationCompleted','solveRuntimeSec'};
if ~isstruct(state)||~all(isfield(state,required))||state.version~=1|| ...
        state.eta~=eta||state.betaExt~=betaExt||string(state.riskType)~=riskType|| ...
        state.topK~=topK||size(state.points,2)~=I||size(state.nomGrad,2)~=I|| ...
        size(state.extGrad,2)~=I||state.iterationCompleted<0
    error('solve_terminal_loh_extreme_aware_decomposition_h2:BadResumeState', ...
        'Certified batch resume state does not match this parameter combination.');
end
end

function master=solve_master(points,nRisk,nGrad,eRisk,eGrad,Cap,gamma,beta,config)
nCuts=size(points,1);I=numel(Cap);nvar=I+2;thetaN=I+1;thetaE=I+2;
A=sparse(2*nCuts,nvar);rhs=zeros(2*nCuts,1);sense=repmat('>',2*nCuts,1);
for kk=1:nCuts
    A(kk,1:I)=-nGrad(kk,:);A(kk,thetaN)=1;
    rhs(kk)=nRisk(kk)-nGrad(kk,:)*points(kk,:).';
    row=nCuts+kk;A(row,1:I)=-eGrad(kk,:);A(row,thetaE)=1;
    rhs(row)=eRisk(kk)-eGrad(kk,:)*points(kk,:).';
end
model=struct('A',A,'rhs',rhs,'sense',sense,'obj',[gamma*ones(I,1);1;beta], ...
    'lb',[zeros(I,1);0;0],'ub',[Cap(:);inf;inf],'modelsense','min', ...
    'modelname','step04CB_extreme_aware_master');
params=struct('OutputFlag',config.gurobiOutputFlag,'FeasibilityTol',config.gurobiFeasibilityTol, ...
    'OptimalityTol',config.gurobiOptimalityTol,'TimeLimit',config.masterTimeLimit, ...
    'Threads',config.gurobiThreads);
result=gurobi(model,params);master=struct('status',string(result.status), ...
    'T',NaN(I,1),'objective',NaN);
if strcmp(result.status,'OPTIMAL'),master.T=result.x(1:I);master.objective=result.objval;end
end

function [nomViolation,extViolation]=cut_validity(points,nRisk,nGrad,eRisk,eGrad)
n=size(points,1);nomViolation=-inf;extViolation=-inf;
for cc=1:n
    predictedNom=nRisk(cc)+(points-points(cc,:))*nGrad(cc,:).';
    predictedExt=eRisk(cc)+(points-points(cc,:))*eGrad(cc,:).';
    nomViolation=max(nomViolation,max(predictedNom-nRisk));
    extViolation=max(extViolation,max(predictedExt-eRisk));
end
nomViolation=max(0,nomViolation);extViolation=max(0,extViolation);
end

function config=fill_defaults(config)
defaults=struct('gurobiOutputFlag',0,'gurobiFeasibilityTol',1e-9, ...
    'gurobiOptimalityTol',1e-9,'gurobiThreads',0,'maximumIterations',100, ...
    'absoluteGapTolerance',1e-4,'relativeGapTolerance',1e-8, ...
    'pointTolerance',1e-8,'subgradientSignTolerance',1e-6, ...
    'totalTimeLimit',7200,'recourseTimeLimit',1800,'masterTimeLimit',60, ...
    'batchIterationLimit',inf, ...
    'objectiveScale',1e5);
names=fieldnames(defaults);for ii=1:numel(names)
    if ~isfield(config,names{ii})||isempty(config.(names{ii})),config.(names{ii})=defaults.(names{ii});end
end
end
