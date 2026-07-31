function complete_step04CA2_state19_support_in_dro_detail_h2()
%COMPLETE_STEP04CA2_STATE19_SUPPORT_IN_DRO_DETAIL_H2 Add missing period detail.

started=tic;thisDir=fileparts(mfilename('fullpath'));moduleDir=fileparts(thisDir);rootDir=fileparts(moduleDir);
addpath(rootDir);addpath(thisDir);add_gurobi_path();
expected="efb1b2d2cdee7baa900ad02ce1b639fc0e8adbbb";assert_git_gate(expected);
outDir=fullfile(rootDir,'results','task-002-stage2b-b3-smoke', ...
    '44-extreme-formal-consequence-freeze','run-003');
inputFile=fullfile(outDir,'in_support_proxy_validation.csv');
auditFile=fullfile(outDir,'state19_support_in_dro_detail_audit.csv');
if ~isfile(inputFile)||isfile(auditFile),error('Accepted input missing or detail audit already exists.');end

pathFile=fullfile(rootDir,'results','task-002-stage2b-b3-smoke', ...
    '43-extreme-path-integration-feasibility','run-001','extreme_path_manifest.csv');
overlapFile=fullfile(rootDir,'results','task-002-stage2b-b3-smoke', ...
    '43-extreme-path-integration-feasibility','run-001','extreme_nominal_overlap_audit.csv');
tFile=fullfile(rootDir,'results','task-002-stage2b-b3-smoke', ...
    '42-flat-chi2-dro-production-solver','run-003','saa_vs_dro_terminalLOH.csv');
paths=readtable(pathFile,'TextType','string');overlap=readtable(overlapFile,'TextType','string');
support=aslogical(paths.in_nominal_path_support);paths=paths(support&double(paths.a0)==4&double(paths.loc0)==5,:);
identity=innerjoin(paths,overlap(:,{'unique_path_id','path_id','scenario_id_in_state', ...
    'joint_stream_position','wind_seed','resistance_seed'}),'Keys','unique_path_id');
if height(identity)~=6,error('Expected six state19 support-in identities.');end
identity.wind_stream_position=double(identity.joint_stream_position);
identity.resistance_stream_position=double(identity.joint_stream_position);
identity.resistance_stream_rule=repmat("nominal_after_permutation",height(identity),1);
formal=generate_step04CA2_formal_consequences_h2(rootDir,identity);
t=readtable(tFile);t=t(t.initial_state_id==19&t.R==15000&abs(t.eta-0.01)<1e-12,:);
droT=[t.DRO_T1_kg,t.DRO_T2_kg,t.DRO_T3_kg,t.DRO_T4_kg];
cfg=struct('gurobiOutputFlag',0,'gurobiTimeLimit',600,'objectiveScale',1e5, ...
    'gurobiFeasibilityTol',1e-9,'gurobiOptimalityTol',1e-9,'gurobiThreads',0);
ev=evaluate_step04CA2_period_fixed_T_detailed_h2(formal.Dperiod,formal.Aperiod,formal.Cperiod,repmat(droT,6,1),2000,cfg);
if ev.exitflag~=1||ev.status~="OPTIMAL"||ev.max_demand_balance_error>1e-7||ev.max_site_capacity_violation>1e-7
    error('State19 support-in DRO detail solve failed.');
end

base=readtable(inputFile,'TextType','string');base.state19_DRO_service_cost=NaN(height(base),1);
base.state19_DRO_shortage_W1_kg=NaN(height(base),1);base.state19_DRO_shortage_W2_kg=NaN(height(base),1);
base.state19_DRO_shortage_W3_kg=NaN(height(base),1);base.state19_DRO_detail_status=repmat("NOT_APPLICABLE",height(base),1);
for rr=1:6
    row=find(double(base.unique_path_id)==double(identity.unique_path_id(rr)));
    if numel(row)~=1,error('State19 detail identity mapping failed.');end
    base.state19_DRO_service_cost(row)=ev.service_cost(rr);
    base.state19_DRO_shortage_W1_kg(row)=ev.stage_shortage_kg(rr,1);
    base.state19_DRO_shortage_W2_kg(row)=ev.stage_shortage_kg(rr,2);
    base.state19_DRO_shortage_W3_kg(row)=ev.stage_shortage_kg(rr,3);
    base.state19_DRO_detail_status(row)="OPTIMAL";
end
writetable(base,inputFile);

audit=table(double(identity.unique_path_id),ev.operating_loss,ev.service_cost,ev.shortage_kg, ...
    ev.stage_shortage_kg(:,1),ev.stage_shortage_kg(:,2),ev.stage_shortage_kg(:,3), ...
    ev.service_satisfaction_rate,repmat(string(ev.status),6,1), ...
    'VariableNames',{'unique_path_id','DRO_operating_loss','DRO_service_cost','DRO_shortage_kg', ...
    'DRO_shortage_W1_kg','DRO_shortage_W2_kg','DRO_shortage_W3_kg','DRO_service_satisfaction_rate','solver_status'});
writetable(audit,auditFile);

runtimeFile=fullfile(outDir,'runtime_and_solver_calls.csv');runtime=readtable(runtimeFile,'TextType','string');
total=runtime(runtime.stage=="TOTAL",:);runtime=runtime(runtime.stage~="TOTAL",:);elapsed=toc(started);
newCalls=double(total.cumulative_solver_calls)+1;newEvals=double(total.cumulative_scenario_evaluations)+6;
runtime=[runtime;table("state19_support_in_DRO_period_detail",elapsed,newCalls,newEvals,"PASS", ...
    'VariableNames',runtime.Properties.VariableNames); ...
    table("TOTAL",double(total.runtime_sec)+elapsed,newCalls,newEvals,"PASS", ...
    'VariableNames',runtime.Properties.VariableNames)];
writetable(runtime,runtimeFile);
fid=fopen(fullfile(outDir,'matlab_run_metadata.txt'),'a');cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'posthoc_state19_DRO_detail_solver_calls=1\naccepted_total_solver_calls=%d\naccepted_total_scenario_evaluations=%d\n',newCalls,newEvals);
fprintf('STEP04CA2_STATE19_DETAIL_PASS|rows=6|runtime=%.6f|total_solver_calls=%d\n',elapsed,newCalls);
end

function values=aslogical(values),if islogical(values),return;elseif isnumeric(values),values=values~=0;else,s=lower(strtrim(string(values)));values=s=="true"|s=="1";end,end
function add_gurobi_path(),for c={fullfile(getenv('GUROBI_HOME'),'matlab'),'D:\gurobi1201\win64\matlab','C:\gurobi1201\win64\matlab'},if ~isempty(c{1})&&isfolder(c{1}),addpath(c{1});end,end,end
function assert_git_gate(head),[a,b]=system('git rev-parse HEAD');[c,d]=system('git rev-parse @{upstream}');if a~=0||c~=0||strtrim(string(b))~=head||strtrim(string(d))~=head,error('Frozen Git gate failed.');end,end
