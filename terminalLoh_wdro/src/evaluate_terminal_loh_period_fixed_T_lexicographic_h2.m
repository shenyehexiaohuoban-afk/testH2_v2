function out = evaluate_terminal_loh_period_fixed_T_lexicographic_h2( ...
        Dperiod,Aperiod,Cperiod,Trows,M,config)
%EVALUATE_TERMINAL_LOH_PERIOD_FIXED_T_LEXICOGRAPHIC_H2 Strict two-stage replay.
%
% Phase 1 minimizes shortage cost only. Phase 2 fixes every scenario's
% phase-1-optimal total shortage with an equality and minimizes C*y. Thus
% road distance/impedance never enters the monetary objective and cannot
% trade against even a small amount of shortage.

if nargin<6||isempty(config),config=struct();end
config=fill_defaults(config);
[R,K,N]=size(Dperiod);I=size(Aperiod,3);
if R<1||K~=3||I~=4||~isequal(size(Aperiod),[R,K,I,N])|| ...
        ~isequal(size(Cperiod),[R,K,I,N])||~isequal(size(Trows),[R,I])|| ...
        any(~isfinite(Dperiod),'all')||any(Dperiod<0,'all')|| ...
        any(Aperiod>0.5&~isfinite(Cperiod),'all')|| ...
        any(~isfinite(Trows),'all')||any(Trows<-1e-10,'all')|| ...
        ~isscalar(M)||~isfinite(M)||M<=0
    error('evaluate_terminal_loh_period_fixed_T_lexicographic_h2:BadInput', ...
        'Invalid formal D/A/C, fixed T, or shortage penalty.');
end
if ~ismember(exist('gurobi','file'),[2,3])
    error('evaluate_terminal_loh_period_fixed_T_lexicographic_h2:MissingGurobi', ...
        'The Gurobi MATLAB interface is required.');
end

buildStarted=tic;
Ceff=Cperiod;Ceff(~isfinite(Ceff)|Aperiod<=0.5)=0;
demandMask=Dperiod>0;
yMask=Aperiod>0.5&reshape(demandMask,[R,K,1,N]);
demandLinear=find(demandMask);yLinear=find(yMask);
nU=numel(demandLinear);nY=numel(yLinear);
[gU,kU,~]=ind2sub([R,K,N],demandLinear);
[gY,kY,iY,nYsub]=ind2sub([R,K,I,N],yLinear);
out=empty_output(R,K,I,nY,nU);
out.total_demand_kg=reshape(sum(Dperiod,[2,3]),[R,1]);
if nU==0
    out.status="OPTIMAL_ZERO_DEMAND";out.primary_status=out.status;
    out.secondary_status=out.status;out.exitflag=1;
    out.shortage_kg=zeros(R,1);out.shortage_loss_yuan=zeros(R,1);
    out.service_distance=zeros(R,1);out.site_service_total=zeros(R,I);
    out.stage_shortage_kg=zeros(R,K);out.stage_service_kg=zeros(R,K);
    out.service_satisfaction_rate=ones(R,1);out.build_runtime_sec=toc(buildStarted);
    out.primary_solve_runtime_sec=0;out.secondary_solve_runtime_sec=0;
    out.max_demand_balance_error=0;out.max_site_capacity_violation=0;
    out.max_shortage_preservation_error_kg=0;out.primary_objective_preservation_error_yuan=0;
    return;
end

idx.y=1:nY;idx.u=nY+(1:nU);nvar=nY+nU;
lb=zeros(nvar,1);ub=inf(nvar,1);
demandRow=zeros(R,K,N,'uint32');demandRow(demandLinear)=uint32(1:nU);
yDemandLinear=sub2ind([R,K,N],gY,kY,nYsub);
yDemandRows=double(demandRow(yDemandLinear));
nBaseRows=nU+R*I;nnzCount=nU+2*nY;
rowIndex=zeros(nnzCount,1);colIndex=zeros(nnzCount,1);value=ones(nnzCount,1);nz=0;
pos=nz+(1:nU);rowIndex(pos)=1:nU;colIndex(pos)=idx.u;nz=nz+nU;
pos=nz+(1:nY);rowIndex(pos)=yDemandRows;colIndex(pos)=idx.y;nz=nz+nY;
pos=nz+(1:nY);rowIndex(pos)=nU+(gY-1)*I+iY;colIndex(pos)=idx.y;
baseA=sparse(rowIndex,colIndex,value,nBaseRows,nvar);
baseRhs=zeros(nBaseRows,1);baseSense=repmat('<',nBaseRows,1);
baseRhs(1:nU)=Dperiod(demandLinear);baseSense(1:nU)='=';
baseRhs(nU+(1:R*I))=reshape(Trows.',[],1);
params=struct('OutputFlag',config.gurobiOutputFlag, ...
    'FeasibilityTol',config.gurobiFeasibilityTol, ...
    'OptimalityTol',config.gurobiOptimalityTol, ...
    'TimeLimit',config.gurobiTimeLimit,'InfUnbdInfo',1, ...
    'Threads',config.gurobiThreads);

primaryObj=zeros(nvar,1);primaryObj(idx.u)=M/config.objectiveScale;
primaryModel=struct('A',baseA,'obj',primaryObj,'rhs',baseRhs, ...
    'sense',baseSense,'lb',lb,'ub',ub,'modelsense','min', ...
    'modelname','fixed_T_primary_shortage_only');
out.build_runtime_sec=toc(buildStarted);
primaryStarted=tic;primaryResult=gurobi(primaryModel,params);
out.primary_solve_runtime_sec=toc(primaryStarted);
out.primary_status=string(primaryResult.status);
if ~strcmp(primaryResult.status,'OPTIMAL'),out.status="PRIMARY_"+out.primary_status;return;end
uPrimary=primaryResult.x(idx.u);
shortagePrimary=accumarray(gU,uPrimary,[R,1]);

shortageRows=sparse(gU,idx.u,ones(nU,1),R,nvar);
secondaryObj=zeros(nvar,1);secondaryObj(idx.y)=Ceff(yLinear)/config.objectiveScale;
secondaryModel=struct('A',[baseA;shortageRows],'obj',secondaryObj, ...
    'rhs',[baseRhs;shortagePrimary],'sense',[baseSense;repmat('=',R,1)], ...
    'lb',lb,'ub',ub,'modelsense','min', ...
    'modelname','fixed_T_secondary_service_distance');
secondaryStarted=tic;secondaryResult=gurobi(secondaryModel,params);
out.secondary_solve_runtime_sec=toc(secondaryStarted);
out.secondary_status=string(secondaryResult.status);
if ~strcmp(secondaryResult.status,'OPTIMAL')
    out.status="SECONDARY_"+out.secondary_status;return;
end

y=secondaryResult.x(idx.y);u=secondaryResult.x(idx.u);
shortageSecondary=accumarray(gU,u,[R,1]);
serviceDistance=accumarray(gY,Ceff(yLinear).*y,[R,1]);
siteService=accumarray([gY,iY],y,[R,I]);
demandService=accumarray(yDemandRows,y,[nU,1]);
out.exitflag=1;out.status="OPTIMAL";
out.shortage_kg=shortageSecondary;
out.shortage_loss_yuan=M.*shortageSecondary;
out.service_distance=serviceDistance;
out.site_service_total=siteService;
out.stage_shortage_kg=accumarray([gU,kU],u,[R,K]);
out.stage_service_kg=accumarray([gY,kY],y,[R,K]);
out.service_satisfaction_rate=ones(R,1);positive=out.total_demand_kg>0;
out.service_satisfaction_rate(positive)=1-shortageSecondary(positive)./out.total_demand_kg(positive);
out.service_satisfaction_rate=max(0,min(1,out.service_satisfaction_rate));
out.primary_objective_yuan=M*sum(shortagePrimary);
out.secondary_objective_distance=sum(serviceDistance);
out.max_shortage_preservation_error_kg=max(abs(shortageSecondary-shortagePrimary),[],'omitnan');
out.primary_objective_preservation_error_yuan=abs(M*sum(shortageSecondary)-out.primary_objective_yuan);
out.max_demand_balance_error=max(abs(demandService+u-Dperiod(demandLinear)),[],'omitnan');
out.max_site_capacity_violation=max(siteService-Trows,[],'all');
out.secondary_objective_reconstruction_abs_error=abs(sum(serviceDistance)- ...
    secondaryResult.objval*config.objectiveScale);
out.primary_objective_reconstruction_abs_error=abs(out.primary_objective_yuan- ...
    primaryResult.objval*config.objectiveScale);
capacityRows=nU+(1:R*I);
if isfield(primaryResult,'pi')&&numel(primaryResult.pi)>=max(capacityRows)
    out.primary_site_capacity_dual=reshape(primaryResult.pi(capacityRows),[I,R]).' ...
        .*config.objectiveScale;
end
end

function config=fill_defaults(config)
defaults=struct('gurobiOutputFlag',0,'gurobiFeasibilityTol',1e-9, ...
    'gurobiOptimalityTol',1e-9,'gurobiTimeLimit',1800, ...
    'gurobiThreads',1,'objectiveScale',1e5);
names=fieldnames(defaults);
for ii=1:numel(names)
    if ~isfield(config,names{ii})||isempty(config.(names{ii}))
        config.(names{ii})=defaults.(names{ii});
    end
end
end

function out=empty_output(R,K,I,nY,nU)
out=struct('status',"NOT_SOLVED",'primary_status',"NOT_SOLVED", ...
    'secondary_status',"NOT_SOLVED",'exitflag',0,'shortage_kg',NaN(R,1), ...
    'shortage_loss_yuan',NaN(R,1),'service_distance',NaN(R,1), ...
    'site_service_total',NaN(R,I),'stage_shortage_kg',NaN(R,K), ...
    'stage_service_kg',NaN(R,K),'service_satisfaction_rate',NaN(R,1), ...
    'total_demand_kg',NaN(R,1),'primary_objective_yuan',NaN, ...
    'secondary_objective_distance',NaN,'max_shortage_preservation_error_kg',NaN, ...
    'primary_objective_preservation_error_yuan',NaN, ...
    'max_demand_balance_error',NaN,'max_site_capacity_violation',NaN, ...
    'primary_objective_reconstruction_abs_error',NaN, ...
    'secondary_objective_reconstruction_abs_error',NaN, ...
    'primary_site_capacity_dual',NaN(R,I),'build_runtime_sec',NaN, ...
    'primary_solve_runtime_sec',NaN,'secondary_solve_runtime_sec',NaN, ...
    'service_variable_count',nY,'shortage_variable_count',nU, ...
    'variable_count',nY+nU,'constructed_R_by_R_matrix',false);
end
