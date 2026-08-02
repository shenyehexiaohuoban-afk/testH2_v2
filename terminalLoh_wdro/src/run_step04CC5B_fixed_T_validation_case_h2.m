function run_step04CC5B_fixed_T_validation_case_h2(workDir,validationId)
%RUN_STEP04CC5B_FIXED_T_VALIDATION_CASE_H2 One isolated fixed-decision set.

started=tic;workDir=string(workDir);validationId=double(validationId);
thisDir=fileparts(mfilename('fullpath'));rootDir=fileparts(fileparts(thisDir));
addpath(rootDir);addpath(thisDir);add_gurobi_path();
assert_git_gate("task/002-stage2b-b3-smoke", ...
    "bb298d52ee5143bc2c60e2f2fc1e31e8d1c3d1a2");
if ~isscalar(validationId)||validationId<1||validationId>26||validationId~=floor(validationId)
    error('validationId must be an integer from 1 through 26.');
end
caseDir=fullfile(workDir,'validation_cases',sprintf('case-%03d',validationId));
if isfolder(caseDir)
    entries=dir(caseDir);entries=entries(~ismember({entries.name},{'.','..'}));
    if ~isempty(entries),error('Refusing to overwrite nonempty validation case.');end
else,mkdir(caseDir);end
diary(fullfile(caseDir,'matlab_diary.txt'));cleanupDiary=onCleanup(@()diary('off')); %#ok<NASGU>

decisions=read_new_decisions(workDir);P=read_parameters(rootDir);
[D,A,C,meta]=load_dataset(rootDir,validationId);
R=size(D,1);config=struct('gurobiOutputFlag',0,'gurobiFeasibilityTol',1e-9, ...
    'gurobiOptimalityTol',1e-9,'gurobiThreads',1,'objectiveScale',1e5, ...
    'gurobiTimeLimit',1800);
summaryRows=cell(3,51);auditRows=cell(3,18);
for jj=1:3
    T=double([decisions.T1_kg(jj),decisions.T2_kg(jj), ...
        decisions.T3_kg(jj),decisions.T4_kg(jj)]);
    fprintf('STEP04CC5B_FIXED_START|validation=%d|role=%s|decision=%s\n', ...
        validationId,meta.dataset_label,string(decisions.decision_label(jj)));
    ev=evaluate_terminal_loh_period_fixed_T_lexicographic_h2( ...
        D,A,C,repmat(T,R,1),P.M_H2,config);
    if ev.exitflag~=1,error('Lexicographic fixed-T evaluation failed: %s',ev.status);end
    residual=max([ev.max_demand_balance_error,max(0,ev.max_site_capacity_violation), ...
        ev.max_shortage_preservation_error_kg, ...
        ev.primary_objective_reconstruction_abs_error/max(1,ev.primary_objective_yuan), ...
        ev.secondary_objective_reconstruction_abs_error/max(1,ev.secondary_objective_distance)],[],'omitnan');
    if residual>1e-7||ev.primary_objective_preservation_error_yuan>1e-3
        error('Fixed-T lexicographic mechanical audit failed: %.15g',residual);
    end
    shortage=ev.shortage_kg;eUnrestored=shortage*P.electricity_per_kg;
    unservedCost=shortage*P.M_H2;production=P.c_H2*sum(T);
    economicTotal=production+unservedCost;
    binding=abs(T-[300,200,100,150])<=1e-6;
    serviceRate=ev.service_satisfaction_rate;
    summaryRows(jj,:)={validationId,meta.source_step,meta.dataset_scope, ...
        meta.dataset_label,meta.seed_id,meta.distribution_id,meta.distribution_label, ...
        meta.weighting_interpretation,jj,string(decisions.decision_label(jj)), ...
        decisions.eta(jj),T(1),T(2),T(3),T(4),sum(T),binding(1),binding(2), ...
        binding(3),binding(4),sum(binding),R,P.c_H2,production,P.M_H2, ...
        mean(shortage),pct(shortage,.95),pct(shortage,.99),pct(shortage,.995), ...
        tail_mean(shortage,.95),tail_mean(shortage,.99),tail_mean(shortage,.995),max(shortage), ...
        mean(eUnrestored),pct(eUnrestored,.95),pct(eUnrestored,.99),pct(eUnrestored,.995), ...
        tail_mean(eUnrestored,.95),tail_mean(eUnrestored,.99),tail_mean(eUnrestored,.995), ...
        max(eUnrestored),mean(unservedCost),mean(economicTotal),mean(serviceRate), ...
        sum(shortage<=1e-9)/R,mean(ev.service_distance),ev.primary_solve_runtime_sec, ...
        ev.secondary_solve_runtime_sec,residual,string(ev.status),true};
    auditRows(jj,:)={validationId,meta.dataset_label,jj,string(decisions.decision_label(jj)), ...
        decisions.eta(jj),string(ev.primary_status),string(ev.secondary_status), ...
        ev.max_shortage_preservation_error_kg,ev.primary_objective_preservation_error_yuan, ...
        ev.max_demand_balance_error,ev.max_site_capacity_violation, ...
        ev.primary_objective_reconstruction_abs_error, ...
        ev.secondary_objective_reconstruction_abs_error,residual, ...
        false,false,false,true};
    fprintf('STEP04CC5B_FIXED_COMPLETE|validation=%d|decision=%s|shortage=%.9g|runtime=%.3f\n', ...
        validationId,string(decisions.decision_label(jj)),mean(shortage), ...
        ev.primary_solve_runtime_sec+ev.secondary_solve_runtime_sec);
end

names={'validation_id','source_step','dataset_scope','dataset_label','seed_id', ...
    'distribution_id','distribution_label','weighting_interpretation','decision_id', ...
    'decision_label','eta','T1_kg','T2_kg','T3_kg','T4_kg','TerminalLOH_total_kg', ...
    'T1_capacity_binding','T2_capacity_binding','T3_capacity_binding', ...
    'T4_capacity_binding','capacity_binding_count','sample_count','c_H2_yuan_per_kg', ...
    'production_cost_yuan','M_H2_yuan_per_kg','mean_shortage_kg','shortage_q95_kg', ...
    'shortage_q99_kg','shortage_q995_kg','shortage_CVaR95_kg','shortage_CVaR99_kg', ...
    'shortage_CVaR995_kg','maximum_shortage_kg','mean_EENS_kWh','EENS_q95_kWh', ...
    'EENS_q99_kWh','EENS_q995_kWh','EENS_CVaR95_kWh','EENS_CVaR99_kWh', ...
    'EENS_CVaR995_kWh','maximum_EENS_kWh','mean_unserved_cost_yuan', ...
    'mean_economic_total_yuan','mean_electricity_service_rate', ...
    'zero_shortage_service_share','mean_secondary_service_distance', ...
    'primary_runtime_sec','secondary_runtime_sec','maximum_mechanical_residual', ...
    'solver_status','validation_pass'};
summary=cell2table(summaryRows,'VariableNames',names);
audit=cell2table(auditRows,'VariableNames',{'validation_id','dataset_label', ...
    'decision_id','decision_label','eta','primary_status','secondary_status', ...
    'shortage_preservation_error_kg','primary_objective_preservation_error_yuan', ...
    'max_demand_balance_error','max_site_capacity_violation', ...
    'primary_reconstruction_error_yuan','secondary_reconstruction_error', ...
    'maximum_mechanical_residual','C_y_in_primary_objective', ...
    'C_y_in_Pearson_loss','validation_reoptimized_T','lexicographic_pass'});
writetable(summary,fullfile(caseDir,'fixed_T_summary.csv'));
writetable(audit,fullfile(caseDir,'lexicographic_audit.csv'));
if any(~summary.validation_pass)||any(~audit.lexicographic_pass)
    error('Fixed-T output acceptance gate failed.');
end
fid=fopen(fullfile(caseDir,'mechanical_audit.txt'),'w');cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'status=PASS\nvalidation_id=%d\ndataset_label=%s\n',validationId,meta.dataset_label);
fprintf(fid,'source_step=%s\nsample_count=%d\ndecision_count=3\n',meta.source_step,R);
fprintf(fid,'weighting_interpretation=%s\n',meta.weighting_interpretation);
fprintf(fid,'TerminalLOH_optimization_calls=0\nchi2_adversary_calls=0\n');
fprintf(fid,'maximum_mechanical_residual=%.15g\n',max(audit.maximum_mechanical_residual));
fprintf('STEP04CC5B_VALIDATION_PROCESS_COMPLETE|validation=%d|runtime=%.3f\n', ...
    validationId,toc(started));
end

function decisions=read_new_decisions(workDir)
rows=cell(3,1);
for ii=1:3
    path=fullfile(workDir,'optimization_cases',sprintf('case-%03d',ii),'optimization_result.csv');
    certPath=fullfile(workDir,'optimization_cases',sprintf('case-%03d',ii),'solver_certificate.csv');
    if ~isfile(path)||~isfile(certPath),error('Optimization output missing before validation.');end
    rows{ii}=readtable(path);cert=readtable(certPath);
    if height(rows{ii})~=1||height(cert)~=1||~logical(cert.certificate_pass)
        error('Optimization certificate failed before validation.');
    end
end
decisions=vertcat(rows{:});decisions=sortrows(decisions,'case_id');
if max(abs(double(decisions.eta)-[0;0.003;0.01]))>1e-14
    error('New decision eta identity failed.');
end
end

function [D,A,C,meta]=load_dataset(rootDir,id)
c1=fullfile(rootDir,'results','task-002-stage2b-b3-smoke', ...
    '46-flat-chi2-eta-calibration','run-003');
if id==1||id==26
    path=fullfile(c1,'prepared_inputs.mat');
    if sha256_file(path)~="5914afb37254ae908c5a8b10f24bc0ae01520e56b35b928a1afc13cf4602f19b"
        error('C1 prepared input hash gate failed.');
    end
    if id==1
        S=load(path,'Dnominal','Anominal','Cnominal');D=S.Dnominal;A=S.Anominal;C=S.Cnominal;
        meta=make_meta("C1","state19-nominal","nominal",NaN,NaN,"nominal", ...
            "EMPIRICAL_EQUAL_WEIGHT_PROBABILITY_1_OVER_15000");
    else
        S=load(path,'Dstress','Astress','Cstress','stressIdentity');
        D=S.Dstress;A=S.Astress;C=S.Cstress;
        if size(D,1)~=135||numel(unique(double(S.stressIdentity.unique_path_id)))~=27
            error('State19 pressure-set identity gate failed.');
        end
        meta=make_meta("A2","fixed-pressure","state19-27-path-135-replica",NaN,NaN, ...
            "fixed-pressure","DESCRIPTIVE_EQUAL_REPLICA_SUMMARY_NO_EMPIRICAL_PROBABILITY");
    end
elseif id>=2&&id<=4
    datasetId=id-1;c2=fullfile(rootDir,'results','task-002-stage2b-b3-smoke', ...
        '47-flat-chi2-independent-path-validation','run-002');
    manifest=readtable(fullfile(c2,'independent_dataset_manifest.csv'));
    row=manifest(double(manifest.dataset_id)==datasetId,:);
    path=string(row.local_mat_path);
    if height(row)~=1||~isfile(path)||sha256_file(path)~=string(row.local_mat_sha256)
        error('C2 dataset hash gate failed.');
    end
    S=load(path,'Dperiod','Aperiod','Cperiod');D=S.Dperiod;A=S.Aperiod;C=S.Cperiod;
    meta=make_meta("C2","independent-path",string(row.dataset_role),datasetId,NaN, ...
        "independent-path-nominal","SEPARATE_EMPIRICAL_PROBABILITY_1_OVER_15000");
else
    datasetIndex=id-4;c3=fullfile(rootDir,'results','task-002-stage2b-b3-smoke', ...
        '48-markov-transition-perturbation','run-001');
    manifest=readtable(fullfile(c3,'dataset_manifest.csv'));row=manifest(datasetIndex,:);
    path=string(row.local_mat_path);
    if height(row)~=1||~isfile(path)||sha256_file(path)~=string(row.local_mat_sha256)
        error('C3 dataset hash gate failed.');
    end
    S=load(path,'Dperiod','Aperiod','Cperiod');D=S.Dperiod;A=S.Aperiod;C=S.Cperiod;
    meta=make_meta("C3","markov-perturbation", ...
        "seed"+sprintf('%03d',row.seed_id)+"-"+string(row.distribution_label), ...
        double(row.seed_id),double(row.distribution_id),string(row.distribution_label), ...
        "SEPARATE_DISTRIBUTION_AND_SEED_PROBABILITY_1_OVER_15000");
end
if size(D,1)~=size(A,1)||size(D,1)~=size(C,1)||size(D,2)~=3||size(A,3)~=4
    error('Loaded validation D/A/C structure failed.');
end
end

function meta=make_meta(source,scope,label,seedId,distId,distLabel,weighting)
meta=struct('source_step',string(source),'dataset_scope',string(scope), ...
    'dataset_label',string(label),'seed_id',double(seedId), ...
    'distribution_id',double(distId),'distribution_label',string(distLabel), ...
    'weighting_interpretation',string(weighting));
end
function P=read_parameters(rootDir)
raw=load(fullfile(rootDir,'data','yuanqi','near_stage_msp_input.mat'),'NearStageInput');n=raw.NearStageInput;
prices=double(n.Cost.electricity_price_yuan_per_kWh(:));P.eta_FC=double(n.HydrogenDevice.eta_FC);
P.LHV=double(n.HydrogenDevice.h2_lhv_kWh_per_kg);P.k_H2=double(n.HydrogenDevice.k_H2_kg_per_kWh);
P.electricity_per_kg=P.eta_FC*P.LHV;P.M_H2=70*P.electricity_per_kg;
P.c_H2=mean(prices)/P.k_H2;
end
function value=pct(x,p),x=sort(double(x(:)));x=x(isfinite(x));value=x(max(1,min(numel(x),ceil(p*numel(x)))));end
function value=tail_mean(x,p),x=double(x(:));threshold=pct(x,p);value=mean(x(x>=threshold));end
function assert_git_gate(expectedBranch,expectedHead)
[s1,b]=system('git branch --show-current');[s2,h]=system('git rev-parse HEAD');[s3,u]=system('git rev-parse @{upstream}');
if s1~=0||s2~=0||s3~=0||strtrim(string(b))~=expectedBranch||strtrim(string(h))~=expectedHead||strtrim(string(u))~=expectedHead,error('Step-04C-C5B validation Git gate failed.');end
end
function add_gurobi_path()
for candidate={fullfile(getenv('GUROBI_HOME'),'matlab'),'D:\gurobi1201\win64\matlab','C:\gurobi1201\win64\matlab'}
    if ~isempty(candidate{1})&&isfolder(candidate{1}),addpath(candidate{1});end
end
end
function hash=sha256_file(fileName)
fid=fopen(fileName,'rb');if fid<0,error('Could not open %s.',fileName);end;cleanup=onCleanup(@()fclose(fid));
md=java.security.MessageDigest.getInstance('SHA-256');while true,bytes=fread(fid,1024*1024,'*uint8');if isempty(bytes),break;end;md.update(typecast(bytes,'int8'));end
digest=typecast(md.digest(),'uint8');hash=lower(string(reshape(dec2hex(digest,2).',1,[])));
end
