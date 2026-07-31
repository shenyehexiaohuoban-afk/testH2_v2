function out = evaluate_step04CA2_period_fixed_T_detailed_h2( ...
        Dperiod,Aperiod,Cperiod,Trows,M,config)
%EVALUATE_STEP04CA2_PERIOD_FIXED_T_DETAILED_H2 Audit-only detailed recourse.
%
% This is the frozen sparse period recourse from
% evaluate_terminal_loh_period_fixed_T_sparse_h2 with additional period and
% failure-mechanism summaries. It does not alter the formal solver core.

if nargin<6||isempty(config),config=struct();end
config=fill_defaults(config);
[R,K,N]=size(Dperiod);I=size(Aperiod,3);
if R<1||K~=3||I~=4||~isequal(size(Aperiod),[R,K,I,N])|| ...
        ~isequal(size(Cperiod),[R,K,I,N])||~isequal(size(Trows),[R,I])|| ...
        any(~isfinite(Dperiod),'all')||any(Dperiod<0,'all')|| ...
        any(Aperiod>0.5&~isfinite(Cperiod),'all')|| ...
        any(~isfinite(Trows),'all')||any(Trows<-1e-10,'all')|| ...
        ~isscalar(M)||~isfinite(M)||M<=0
    error('evaluate_step04CA2_period_fixed_T_detailed_h2:BadInput','Invalid D/A/C, T, or M.');
end
if ~ismember(exist('gurobi','file'),[2,3]),error('Gurobi MATLAB interface is required.');end

buildTic=tic;Ceff=Cperiod;Ceff(~isfinite(Ceff)|Aperiod<=0.5)=0;
demandMask=Dperiod>0;yMask=Aperiod>0.5&reshape(demandMask,[R,K,1,N]);
demandLinear=find(demandMask);yLinear=find(yMask);nU=numel(demandLinear);nY=numel(yLinear);
[gU,kU,nUsub]=ind2sub([R,K,N],demandLinear);
[gY,kY,iY,nYsub]=ind2sub([R,K,I,N],yLinear);
out=empty_output(R,K,I,nY,nU);
out.total_demand_kg=reshape(sum(Dperiod,[2,3]),[R,1]);
reachableCount=reshape(sum(Aperiod,3),[R,K,N]);
out.unreachable_demand_kg=reshape(sum(Dperiod.*double(reachableCount==0),[2,3]),[R,1]);
out.single_site_demand_kg=reshape(sum(Dperiod.*double(reachableCount==1),[2,3]),[R,1]);
out.unreachable_demand_node_period_count=reshape(sum((Dperiod>0)&reachableCount==0,[2,3]),[R,1]);
if nU==0
    out.status="OPTIMAL_ZERO_DEMAND";out.exitflag=1;out.operating_loss=zeros(R,1);
    out.service_cost=zeros(R,1);out.shortage_kg=zeros(R,1);out.shortage_loss=zeros(R,1);
    out.stage_shortage_kg=zeros(R,K);out.stage_service_kg=zeros(R,K);
    out.site_service_total=zeros(R,I);out.service_satisfaction_rate=ones(R,1);
    out.build_runtime_sec=toc(buildTic);out.solve_runtime_sec=0;return;
end

idx.y=1:nY;idx.u=nY+(1:nU);nvar=nY+nU;
obj=zeros(nvar,1);obj(idx.y)=Ceff(yLinear)./config.objectiveScale;
obj(idx.u)=M./config.objectiveScale;lb=zeros(nvar,1);ub=inf(nvar,1);
demandRow=zeros(R,K,N,'uint32');demandRow(demandLinear)=uint32(1:nU);
yDemandLinear=sub2ind([R,K,N],gY,kY,nYsub);yDemandRows=double(demandRow(yDemandLinear));
nRows=nU+R*I;nnzCount=nU+2*nY;rowIndex=zeros(nnzCount,1);colIndex=zeros(nnzCount,1);
value=ones(nnzCount,1);nz=0;
pos=nz+(1:nU);rowIndex(pos)=1:nU;colIndex(pos)=idx.u;nz=nz+nU;
pos=nz+(1:nY);rowIndex(pos)=yDemandRows;colIndex(pos)=idx.y;nz=nz+nY;
pos=nz+(1:nY);rowIndex(pos)=nU+(gY-1)*I+iY;colIndex(pos)=idx.y;
rhs=zeros(nRows,1);sense=repmat('<',nRows,1);rhs(1:nU)=Dperiod(demandLinear);sense(1:nU)='=';
rhs(nU+(1:R*I))=reshape(Trows.',[],1);
model=struct('A',sparse(rowIndex,colIndex,value,nRows,nvar),'obj',obj,'rhs',rhs, ...
    'sense',sense,'lb',lb,'ub',ub,'modelsense','min','modelname','step04CA2_fixed_T_detailed');
out.build_runtime_sec=toc(buildTic);out.variable_count=nvar;out.linear_constraint_count=nRows;
out.linear_matrix_nnz=nnz(model.A);params=struct('OutputFlag',config.gurobiOutputFlag, ...
    'FeasibilityTol',config.gurobiFeasibilityTol,'OptimalityTol',config.gurobiOptimalityTol, ...
    'TimeLimit',config.gurobiTimeLimit,'InfUnbdInfo',1,'Threads',config.gurobiThreads);
solveTic=tic;result=gurobi(model,params);out.solve_runtime_sec=toc(solveTic);out.status=string(result.status);
if ~strcmp(result.status,'OPTIMAL'),return;end

y=result.x(idx.y);u=result.x(idx.u);out.exitflag=1;
out.service_cost=accumarray(gY,Ceff(yLinear).*y,[R,1]);
out.shortage_kg=accumarray(gU,u,[R,1]);out.shortage_loss=M.*out.shortage_kg;
out.operating_loss=out.service_cost+out.shortage_loss;
out.stage_shortage_kg=accumarray([gU,kU],u,[R,K]);
out.stage_service_kg=accumarray([gY,kY],y,[R,K]);
out.site_service_total=accumarray([gY,iY],y,[R,I]);
out.service_satisfaction_rate=ones(R,1);positive=out.total_demand_kg>0;
out.service_satisfaction_rate(positive)=1-out.shortage_kg(positive)./out.total_demand_kg(positive);
demandService=accumarray(yDemandRows,y,[nU,1]);
capacityRows=nU+(1:R*I);
if isfield(result,'pi')&&numel(result.pi)>=max(capacityRows)
    rawPi=reshape(result.pi(capacityRows),[I,R]).'.*config.objectiveScale;
    out.site_capacity_shadow_price=max(0,-rawPi);
else,out.site_capacity_shadow_price=NaN(R,I);end
out.max_demand_balance_error=max(abs(demandService+u-Dperiod(demandLinear)),[],'omitnan');
out.max_site_capacity_violation=max(out.site_service_total-Trows,[],'all');
out.objective_reconstruction_abs_error=abs(sum(out.operating_loss)-result.objval*config.objectiveScale);
end

function config=fill_defaults(config)
defaults=struct('gurobiOutputFlag',0,'gurobiFeasibilityTol',1e-9, ...
    'gurobiOptimalityTol',1e-9,'gurobiTimeLimit',1800,'gurobiThreads',0,'objectiveScale',1e5);
names=fieldnames(defaults);for ii=1:numel(names),if ~isfield(config,names{ii})||isempty(config.(names{ii})),config.(names{ii})=defaults.(names{ii});end,end
end
function out=empty_output(R,K,I,nY,nU)
out=struct('status',"NOT_SOLVED",'exitflag',0,'operating_loss',NaN(R,1), ...
    'service_cost',NaN(R,1),'shortage_kg',NaN(R,1),'shortage_loss',NaN(R,1), ...
    'stage_shortage_kg',NaN(R,K),'stage_service_kg',NaN(R,K), ...
    'site_service_total',NaN(R,I),'site_capacity_shadow_price',NaN(R,I), ...
    'service_satisfaction_rate',NaN(R,1),'total_demand_kg',NaN(R,1), ...
    'unreachable_demand_kg',NaN(R,1),'single_site_demand_kg',NaN(R,1), ...
    'unreachable_demand_node_period_count',NaN(R,1), ...
    'max_demand_balance_error',NaN,'max_site_capacity_violation',NaN, ...
    'objective_reconstruction_abs_error',NaN,'build_runtime_sec',NaN,'solve_runtime_sec',NaN, ...
    'service_variable_count',nY,'shortage_variable_count',nU,'variable_count',nY+nU, ...
    'linear_constraint_count',NaN,'linear_matrix_nnz',NaN,'constructed_R_by_R_matrix',false);
end
