function run_step04CA2_extreme_formal_consequence_freeze_h2()
%RUN_STEP04CA2_EXTREME_FORMAL_CONSEQUENCE_FREEZE_H2 Step-04C-A2 execution.

started=tic;thisFile=mfilename('fullpath');thisDir=fileparts(thisFile);
moduleDir=fileparts(thisDir);rootDir=fileparts(moduleDir);
addpath(rootDir);addpath(thisDir);add_gurobi_path();
expectedHead="efb1b2d2cdee7baa900ad02ce1b639fc0e8adbbb";
assert_git_gate("task/002-stage2b-b3-smoke",expectedHead);

outBase=fullfile(rootDir,'results','task-002-stage2b-b3-smoke', ...
    '44-extreme-formal-consequence-freeze');
outDir=fullfile(outBase,'run-003');tmpDir=outDir+".tmp";
if isfolder(outDir)||isfolder(tmpDir),error('Step-04C-A2 run-003 output already exists.');end
mkdir(tmpDir);cleanupTmp=onCleanup(@() preserve_failed_tmp(tmpDir)); %#ok<NASGU>
stageRows={};solverCalls=0;scenarioEvaluations=0;

extremeFile=fullfile(rootDir,'results','task-002-stage2b-b3-smoke', ...
    '43-extreme-path-integration-feasibility','run-001','extreme_path_manifest.csv');
overlapFile=fullfile(rootDir,'results','task-002-stage2b-b3-smoke', ...
    '43-extreme-path-integration-feasibility','run-001','extreme_nominal_overlap_audit.csv');
proxyFile=fullfile(rootDir,'results','task-002-stage2b-b3-smoke', ...
    '43-extreme-path-integration-feasibility','run-001','extreme_proxy_vs_actual_loss.csv');
nominalCsv=fullfile(moduleDir,'output','stage3j_wdro_input_freeze','run-001','wdro_nominal_input.csv');
nominalMat=fullfile(moduleDir,'output','stage3j_wdro_input_freeze','run-001','wdro_nominal_input_DAC.mat');
seedMapFile=fullfile(moduleDir,'output','stage3j_wdro_input_freeze','run-001','dataset_role_and_seed_map.csv');
allStateTFile=fullfile(rootDir,'results','task-002-stage2b-b3-smoke', ...
    '33-all-state-period-vs-aggregate-saa','run-001','all_state_cross_evaluation.csv');
state19TFile=fullfile(rootDir,'results','task-002-stage2b-b3-smoke', ...
    '42-flat-chi2-dro-production-solver','run-003','saa_vs_dro_terminalLOH.csv');
required={extremeFile,overlapFile,proxyFile,nominalCsv,nominalMat,seedMapFile,allStateTFile,state19TFile};
for ii=1:numel(required),if ~isfile(required{ii}),error('Missing input: %s',required{ii});end,end

stageTic=tic;
paths=readtable(extremeFile,'TextType','string');overlap=readtable(overlapFile,'TextType','string');
proxy=readtable(proxyFile,'TextType','string');
supportFlag=aslogical(paths.in_nominal_path_support);
if height(paths)~=1126||sum(supportFlag)~=268||sum(~supportFlag)~=858,error('Frozen path partition mismatch.');end
keyVars={'a0','loc0','lfw0','a1','loc1','lfw1','a2','loc2','lfw2','a3','loc3','lfw3'};
supportOut=sortrows(paths(~supportFlag,:),keyVars);supportOut.support_out_path_rank=(1:height(supportOut)).';
replicas=5;nExtreme=height(supportOut)*replicas;
expanded=supportOut(repelem((1:height(supportOut)).',replicas),:);
expanded.consequence_replica_rank=repmat((1:replicas).',height(supportOut),1);
expanded.consequence_replica_id=compose('SO-P%04d-R%02d',expanded.support_out_path_rank,expanded.consequence_replica_rank);
expanded.namespace=repmat("STEP04CA2_SUPPORT_OUT_V1",nExtreme,1);
expanded.wind_seed=repmat(1704202601,nExtreme,1);
expanded.resistance_seed=repmat(2704202601,nExtreme,1);
expanded.wind_stream_position=(1:nExtreme).';expanded.resistance_stream_position=(1:nExtreme).';
expanded.joint_stream_position=(1:nExtreme).';
expanded.resistance_stream_rule=repmat("namespace_direct_position",nExtreme,1);
expanded=rename_path_columns(expanded);
stageRows(end+1,:)={"identity_design",toc(stageTic),0,0,"PASS"}; %#ok<AGROW>

stageTic=tic;extreme1=generate_step04CA2_formal_consequences_h2(rootDir,expanded);
extreme2=generate_step04CA2_formal_consequences_h2(rootDir,expanded);
replayExact=isequal(extreme1.Dperiod,extreme2.Dperiod)&&isequal(extreme1.Aperiod,extreme2.Aperiod)&& ...
    isequaln(extreme1.Cperiod,extreme2.Cperiod)&&isequal(extreme1.failed_line,extreme2.failed_line)&& ...
    isequal(extreme1.closed_road,extreme2.closed_road)&&isequal(extreme1.wind_mps,extreme2.wind_mps)&& ...
    isequal(extreme1.scenario_sha256,extreme2.scenario_sha256);
if ~replayExact,error('Support-out byte-exact replay failed.');end
stageRows(end+1,:)={"support_out_DAC_generation_and_replay",toc(stageTic),0,0,"PASS"}; %#ok<AGROW>
clear extreme2;

stageTic=tic;
inPaths=paths(supportFlag,:);inRows=innerjoin(inPaths,overlap(:,{'unique_path_id','path_id', ...
    'scenario_id_in_state','joint_stream_position','wind_seed','resistance_seed'}), ...
    'Keys','unique_path_id');
inRows=innerjoin(inRows,proxy(:,{'unique_path_id','grid_max_wind_mps', ...
    'grid_cumulative_excess_mps','road_max_wind_mps','road_cumulative_excess_mps'}), ...
    'Keys','unique_path_id');
if height(inRows)~=268||any(~isfinite(double(inRows.path_id))),error('Support-in identity join failed.');end
inRows.wind_stream_position=double(inRows.joint_stream_position);
inRows.resistance_stream_position=double(inRows.joint_stream_position);
inRows.resistance_stream_rule=repmat("nominal_after_permutation",height(inRows),1);
inRows=rename_path_columns(inRows);
inFormal=generate_step04CA2_formal_consequences_h2(rootDir,inRows);
[nominalReplayPass,nominalReplayError]=audit_nominal_aggregate(inFormal,nominalMat,double(inRows.a0), ...
    double(inRows.path_id),double(inRows.scenario_id_in_state),double(inRows.unique_path_id));
if ~all(nominalReplayPass),error('Support-in nominal aggregate replay failed.');end
stageRows(end+1,:)={"support_in_formal_replay",toc(stageTic),0,0,"PASS"}; %#ok<AGROW>

stageTic=tic;
allT=readtable(allStateTFile,'TextType','string');
allT=allT(double(allT.R)==500&allT.evaluation_model=="PERIOD"&allT.terminalLOH_source=="T_PERIOD",:);
allT=sortrows(allT,'initial_state_id');if height(allT)~=35,error('Expected 35 existing R500 period T rows.');end
state19Table=readtable(state19TFile);s19=state19Table(state19Table.initial_state_id==19&state19Table.R==15000&abs(state19Table.eta-0.01)<1e-12,:);
if height(s19)~=1,error('Missing state19 R15000 SAA/DRO row.');end
saaT=[s19.SAA_T1_kg,s19.SAA_T2_kg,s19.SAA_T3_kg,s19.SAA_T4_kg];
droT=[s19.DRO_T1_kg,s19.DRO_T2_kg,s19.DRO_T3_kg,s19.DRO_T4_kg];
stateT=[double(allT.T1),double(allT.T2),double(allT.T3),double(allT.T4)];stateT(19,:)=saaT;
stageRows(end+1,:)={"fixed_T_recovery",toc(stageTic),0,0,"PASS"}; %#ok<AGROW>

solverConfig=struct('gurobiOutputFlag',0,'gurobiTimeLimit',3600,'objectiveScale',1e5, ...
    'gurobiFeasibilityTol',1e-9,'gurobiOptimalityTol',1e-9,'gurobiThreads',0);
M=2000;
stageTic=tic;Trows=stateT((double(inRows.a0)-2)*7+double(inRows.loc0),:); % states are a0-major, loc-minor
inPrimary=evaluate_step04CA2_period_fixed_T_detailed_h2(inFormal.Dperiod,inFormal.Aperiod,inFormal.Cperiod,Trows,M,solverConfig);
solverCalls=solverCalls+1;scenarioEvaluations=scenarioEvaluations+height(inRows);assert_optimal(inPrimary,'support-in primary');
s19Mask=double(inRows.a0)==4&double(inRows.loc0)==5; % initial_state_id 19
if any(s19Mask)
    inDro=evaluate_step04CA2_period_fixed_T_detailed_h2(inFormal.Dperiod(s19Mask,:,:), ...
        inFormal.Aperiod(s19Mask,:,:,:),inFormal.Cperiod(s19Mask,:,:,:),repmat(droT,sum(s19Mask),1),M,solverConfig);
    solverCalls=solverCalls+1;scenarioEvaluations=scenarioEvaluations+sum(s19Mask);assert_optimal(inDro,'support-in state19 DRO');
else,inDro=[];end
stageRows(end+1,:)={"support_in_fixed_T_recourse",toc(stageTic),solverCalls,scenarioEvaluations,"PASS"}; %#ok<AGROW>

stageTic=tic;
[prefixEntry,prefixContext]=recover_step03Y_prefix_entries_h2(rootDir,1:35,500,false);
assert_recovery(prefixEntry);prefixT=zeros(height(prefixEntry.identity),4);
for rr=1:height(prefixEntry.identity),prefixT(rr,:)=stateT(double(prefixEntry.identity.initial_state_id(rr)),:);end
prefixEval=evaluate_step04CA2_period_fixed_T_detailed_h2(prefixEntry.Dperiod,prefixEntry.Aperiod,prefixEntry.Cperiod,prefixT,prefixContext.M,solverConfig);
solverCalls=solverCalls+1;scenarioEvaluations=scenarioEvaluations+height(prefixEntry.identity);assert_optimal(prefixEval,'R500 baseline');
[state19Entry,state19Context]=recover_step03Y_prefix_entries_h2(rootDir,19,15000,false);assert_recovery(state19Entry);
state19Saa=evaluate_step04CA2_period_fixed_T_detailed_h2(state19Entry.Dperiod,state19Entry.Aperiod,state19Entry.Cperiod,repmat(saaT,15000,1),state19Context.M,solverConfig);
state19Dro=evaluate_step04CA2_period_fixed_T_detailed_h2(state19Entry.Dperiod,state19Entry.Aperiod,state19Entry.Cperiod,repmat(droT,15000,1),state19Context.M,solverConfig);
solverCalls=solverCalls+2;scenarioEvaluations=scenarioEvaluations+30000;assert_optimal(state19Saa,'state19 SAA baseline');assert_optimal(state19Dro,'state19 DRO baseline');
stageRows(end+1,:)={"nominal_loss_reference",toc(stageTic),solverCalls,scenarioEvaluations,"PASS"}; %#ok<AGROW>

inSupport=build_in_support_table(inRows,inFormal,inPrimary,inDro,s19Mask,prefixEntry,prefixEval,state19Saa,state19Dro, ...
    nominalReplayPass,nominalReplayError);
writetable(inSupport,fullfile(tmpDir,'in_support_proxy_validation.csv'));

stageTic=tic;Cap=[300,200,100,150];decisionNames=["HALF_CAPACITY","FULL_CAPACITY","STATE19_SAA","STATE19_DRO"];
decisionT=[0.5*Cap;Cap;saaT;droT];extremeTables=cell(4,1);
for dd=1:4
    ev=evaluate_step04CA2_period_fixed_T_detailed_h2(extreme1.Dperiod,extreme1.Aperiod,extreme1.Cperiod,repmat(decisionT(dd,:),nExtreme,1),M,solverConfig);
    solverCalls=solverCalls+1;scenarioEvaluations=scenarioEvaluations+nExtreme;assert_optimal(ev,decisionNames(dd));
    extremeTables{dd}=build_extreme_recourse_table(expanded,extreme1,ev,decisionNames(dd),decisionT(dd,:),state19Saa,state19Dro);
end
extremeRecourse=vertcat(extremeTables{:});writetable(extremeRecourse,fullfile(tmpDir,'extreme_formal_recourse_results.csv'));
stageRows(end+1,:)={"support_out_fixed_T_recourse",toc(stageTic),solverCalls,scenarioEvaluations,"PASS"}; %#ok<AGROW>

manifest=build_identity_manifest(expanded,extreme1);writetable(manifest,fullfile(tmpDir,'extreme_consequence_identity_manifest.csv'));
dacAudit=build_dac_audit(expanded,extreme1);writetable(dacAudit,fullfile(tmpDir,'extreme_DAC_generation_audit.csv'));
collision=build_collision_audit(expanded,readtable(seedMapFile,'TextType','string'));
writetable(collision,fullfile(tmpDir,'random_stream_collision_audit.csv'));
repro=build_reproducibility_audit(extreme1,replayExact,manifest,dacAudit);
writetable(repro,fullfile(tmpDir,'reproducibility_audit.csv'));

baseline=table((1:35).',zeros(35,1),zeros(35,1),zeros(35,1),zeros(35,1), ...
    'VariableNames',{'initial_state_id','R','loss_q50','loss_q95','loss_q99'});
for ss=1:35
    q=prefixEval.operating_loss(double(prefixEntry.identity.initial_state_id)==ss);baseline.R(ss)=numel(q);
    baseline.loss_q50(ss)=pct(q,50);baseline.loss_q95(ss)=pct(q,95);baseline.loss_q99(ss)=pct(q,99);
end
baseline=[baseline;table(19,15000,pct(state19Saa.operating_loss,50),pct(state19Saa.operating_loss,95),pct(state19Saa.operating_loss,99), ...
    'VariableNames',baseline.Properties.VariableNames)];
writetable(baseline,fullfile(tmpDir,'nominal_loss_reference.csv'));

largeFile=fullfile(tmpDir,'extreme_formal_DAC_and_damage.mat');
identity=expanded;Dperiod=extreme1.Dperiod;Aperiod=extreme1.Aperiod;Cperiod=extreme1.Cperiod; %#ok<NASGU>
failed_line=extreme1.failed_line;closed_road=extreme1.closed_road;wind_mps=extreme1.wind_mps;wind_q=extreme1.wind_q; %#ok<NASGU>
line_resistance_u=extreme1.line_resistance_u;road_resistance_u=extreme1.road_resistance_u; %#ok<NASGU>
save(largeFile,'identity','Dperiod','Aperiod','Cperiod','failed_line','closed_road','wind_mps','wind_q','line_resistance_u','road_resistance_u','-v7.3');
largeInfo=dir(largeFile);largeManifest=table("extreme_formal_DAC_and_damage.mat",nExtreme,largeInfo.bytes,sha256_file(largeFile), ...
    extreme1.full_D_sha256,extreme1.full_A_sha256,extreme1.full_C_sha256, ...
    'VariableNames',{'file','scenario_rows','bytes','file_sha256','D_raw_sha256','A_raw_sha256','C_raw_sha256'});
writetable(largeManifest,fullfile(tmpDir,'large_file_manifest.csv'));

runtime=cell2table(stageRows,'VariableNames',{'stage','runtime_sec','cumulative_solver_calls','cumulative_scenario_evaluations','status'});
runtime=[runtime;{"TOTAL",toc(started),solverCalls,scenarioEvaluations,"PASS"}];
writetable(runtime,fullfile(tmpDir,'runtime_and_solver_calls.csv'));
write_run_metadata(fullfile(tmpDir,'matlab_run_metadata.txt'),expectedHead,nExtreme,replicas,solverCalls,scenarioEvaluations, ...
    replayExact,all(dacAudit.passed),sha256_file(extremeFile),sha256_file(overlapFile));
movefile(tmpDir,outDir);clear cleanupTmp;
fprintf('STEP04CA2_MATLAB_PASS|output=%s|scenarios=%d|solver_calls=%d|runtime=%.6f\n',outDir,nExtreme,solverCalls,toc(started));
end

function T=rename_path_columns(T)
for k=1:3
    old={sprintf('a%d',k),sprintf('loc%d',k),sprintf('lfw%d',k)};
    for j=1:3,if ~ismember(old{j},T.Properties.VariableNames),error('Missing physical path field %s.',old{j});end,end
end
end

function [passed,maxError]=audit_nominal_aggregate(formal,matFile,a0,pathId,scenarioId,uniqueId) %#ok<INUSD>
sidecar=matfile(matFile);R=numel(pathId);passed=false(R,1);maxError=inf(R,1);
for rr=1:R
    stateId=(double(a0(rr))-2)*7+double(formal.identity.loc0(rr));globalRow=(stateId-1)*15000+scenarioId(rr);
    Dtau=squeeze(formal.Dperiod(rr,:,:));Atau=squeeze(formal.Aperiod(rr,:,:,:));Ctau=squeeze(formal.Cperiod(rr,:,:,:));
    Dagg=sum(Dtau,1);Aagg=false(4,size(Dtau,2));Cagg=inf(4,size(Dtau,2));
    for n=1:size(Dtau,2)
        critical=find(Dtau(:,n)>1e-10);if isempty(critical),critical=(1:3).';end
        for i=1:4
            reach=squeeze(Atau(critical,i,n));if all(reach),Aagg(i,n)=true;Cagg(i,n)=mean(squeeze(Ctau(critical,i,n)));end
        end
    end
    Dnom=double(sidecar.D_node_kg(globalRow,:));Anom=logical(squeeze(sidecar.A_site_node(globalRow,:,:)));
    Cnom=double(squeeze(sidecar.C_site_node_km(globalRow,:,:)));finite=isfinite(Cagg)&isfinite(Cnom);cErr=0;
    if any(finite,'all'),cErr=max(abs(Cagg(finite)-Cnom(finite)));end
    maxError(rr)=max([max(abs(Dagg-Dnom)),cErr,sum(Aagg~=Anom,'all'),sum(isinf(Cagg)~=isinf(Cnom),'all')]);
    passed(rr)=isequal(Dagg,Dnom)&&isequal(Aagg,Anom)&&isequaln(Cagg,Cnom)&&double(pathId(rr))==double(formal.identity.path_id(rr));
end
end

function T=build_in_support_table(id,formal,primary,dro,s19Mask,prefixEntry,prefixEval,s19Saa,s19Dro,replayPass,replayError)
R=height(id);stateId=(double(id.a0)-2)*7+double(id.loc0);percentile=zeros(R,1);
for rr=1:R
    if stateId(rr)==19,ref=s19Saa.operating_loss;else,ref=prefixEval.operating_loss(double(prefixEntry.identity.initial_state_id)==stateId(rr));end
    percentile(rr)=100*mean(ref<=primary.operating_loss(rr));
end
droLoss=NaN(R,1);droServiceCost=NaN(R,1);droShort=NaN(R,1);droStage=NaN(R,3);droRate=NaN(R,1);droPct=NaN(R,1);
if any(s19Mask)
    droLoss(s19Mask)=dro.operating_loss;droServiceCost(s19Mask)=dro.service_cost;droShort(s19Mask)=dro.shortage_kg;
    droStage(s19Mask,:)=dro.stage_shortage_kg;droRate(s19Mask)=dro.service_satisfaction_rate;
    for rr=find(s19Mask).',droPct(rr)=100*mean(s19Dro.operating_loss<=droLoss(rr));end
end
T=table(double(id.unique_path_id),stateId,double(id.path_id),double(id.scenario_id_in_state), ...
    double(id.joint_stream_position),double(id.grid_max_wind_mps),double(id.grid_cumulative_excess_mps), ...
    double(id.road_max_wind_mps),double(id.road_cumulative_excess_mps),double(id.path_probability), ...
    formal.scenario_sha256,primary.operating_loss,primary.service_cost,primary.shortage_kg, ...
    primary.stage_shortage_kg(:,1),primary.stage_shortage_kg(:,2),primary.stage_shortage_kg(:,3), ...
    primary.service_satisfaction_rate,percentile,droLoss,droServiceCost,droShort,droStage(:,1),droStage(:,2),droStage(:,3),droRate,droPct,replayPass,replayError, ...
    'VariableNames',{'unique_path_id','initial_state_id','path_id','scenario_id_in_state', ...
    'joint_stream_position','grid_max_wind_mps','grid_cumulative_excess_mps','road_max_wind_mps', ...
    'road_cumulative_excess_mps','path_probability','formal_scenario_sha256','formal_loss', ...
    'service_cost','shortage_kg','shortage_W1_kg','shortage_W2_kg','shortage_W3_kg', ...
    'service_satisfaction_rate','nominal_loss_percentile','state19_DRO_loss','state19_DRO_service_cost', ...
    'state19_DRO_shortage_kg','state19_DRO_shortage_W1_kg','state19_DRO_shortage_W2_kg','state19_DRO_shortage_W3_kg', ...
    'state19_DRO_service_satisfaction_rate','state19_DRO_nominal_loss_percentile', ...
    'nominal_aggregate_replay_pass','nominal_aggregate_max_error'});
end

function T=build_extreme_recourse_table(id,formal,ev,label,Tvec,s19Saa,s19Dro)
R=height(id);if label=="STATE19_SAA",ref=s19Saa.operating_loss;elseif label=="STATE19_DRO",ref=s19Dro.operating_loss;else,ref=[];end
pctile=NaN(R,1);if ~isempty(ref),for rr=1:R,pctile(rr)=100*mean(ref<=ev.operating_loss(rr));end,end
T=table(double(id.unique_path_id),double(id.support_out_path_rank),double(id.consequence_replica_rank), ...
    string(id.consequence_replica_id),double(id.path_probability),repmat(label,R,1),repmat(Tvec(1),R,1), ...
    repmat(Tvec(2),R,1),repmat(Tvec(3),R,1),repmat(Tvec(4),R,1),ev.total_demand_kg, ...
    ev.operating_loss,ev.service_cost,ev.shortage_kg,ev.stage_shortage_kg(:,1),ev.stage_shortage_kg(:,2), ...
    ev.stage_shortage_kg(:,3),ev.service_satisfaction_rate,ev.unreachable_demand_kg, ...
    ev.single_site_demand_kg,ev.unreachable_demand_node_period_count,max(ev.site_capacity_shadow_price,[],2), ...
    pctile,formal.scenario_sha256,repmat(string(ev.status),R,1), ...
    'VariableNames',{'unique_path_id','support_out_path_rank','consequence_replica_rank','consequence_replica_id', ...
    'path_probability','decision_label','T1','T2','T3','T4','total_demand_kg','operating_loss','service_cost', ...
    'shortage_kg','shortage_W1_kg','shortage_W2_kg','shortage_W3_kg','service_satisfaction_rate', ...
    'unreachable_demand_kg','single_site_demand_kg','unreachable_demand_node_period_count', ...
    'max_site_capacity_shadow_price','state19_nominal_loss_percentile','formal_scenario_sha256','solver_status'});
end

function T=build_identity_manifest(id,formal)
R=height(id);failed=reshape(sum(formal.failed_line,3),[R,3]);closed=reshape(sum(formal.closed_road,3),[R,3]);
T=table(double(id.unique_path_id),double(id.support_out_path_rank),double(id.consequence_replica_rank), ...
    string(id.consequence_replica_id),string(id.namespace),double(id.wind_seed),double(id.wind_stream_position), ...
    double(id.resistance_seed),double(id.resistance_stream_position),double(id.joint_stream_position), ...
    formal.wind_q(:,1),formal.wind_q(:,2),formal.wind_q(:,3),formal.wind_mps(:,1),formal.wind_mps(:,2),formal.wind_mps(:,3), ...
    failed(:,1),failed(:,2),failed(:,3),closed(:,1),closed(:,2),closed(:,3),formal.damage_sha256,formal.scenario_sha256, ...
    'VariableNames',{'unique_path_id','support_out_path_rank','consequence_replica_rank','consequence_replica_id', ...
    'namespace','wind_seed','wind_stream_position','resistance_seed','resistance_stream_position', ...
    'joint_stream_position','wind_q_W1','wind_q_W2','wind_q_W3','wind_W1_mps','wind_W2_mps','wind_W3_mps', ...
    'failed_lines_W1','failed_lines_W2','failed_lines_W3','closed_roads_W1','closed_roads_W2','closed_roads_W3', ...
    'damage_sha256','formal_scenario_sha256'});
end

function T=build_dac_audit(id,formal)
R=height(id);D=formal.Dperiod;A=formal.Aperiod;C=formal.Cperiod;failed=formal.failed_line;closed=formal.closed_road;
Dfinite=reshape(all(isfinite(D),[2,3]),[R,1]);Dnonnegative=reshape(all(D>=0,[2,3]),[R,1]);
Cdomain=reshape(all((A&isfinite(C))|(~A&isinf(C)),[2,3,4]),[R,1]);
Dpersistent=reshape(all(diff(D,1,2)>=-1e-12,[2,3]),[R,1]);
Apersistent=reshape(all(diff(double(A),1,2)<=0,[2,3,4]),[R,1]);
failedPersistent=reshape(all(diff(double(failed),1,2)>=0,[2,3]),[R,1]);
closedPersistent=reshape(all(diff(double(closed),1,2)>=0,[2,3]),[R,1]);
sourceZero=reshape(all(D(:,:,1)==0,2),[R,1]);
Cmonotonic=true(R,1);for rr=1:R,for tau=1:2,mask=squeeze(A(rr,tau,:,:)&A(rr,tau+1,:,:));c1=squeeze(C(rr,tau,:,:));c2=squeeze(C(rr,tau+1,:,:));if any(c2(mask)<c1(mask)-1e-10),Cmonotonic(rr)=false;end,end,end
passed=Dfinite&Dnonnegative&Cdomain&Dpersistent&Apersistent&failedPersistent&closedPersistent&sourceZero&Cmonotonic;
T=table(double(id.unique_path_id),double(id.support_out_path_rank),double(id.consequence_replica_rank), ...
    string(id.consequence_replica_id),Dfinite,Dnonnegative,Cdomain,Dpersistent,Apersistent,Cmonotonic, ...
    failedPersistent,closedPersistent,sourceZero,passed,formal.scenario_sha256, ...
    'VariableNames',{'unique_path_id','support_out_path_rank','consequence_replica_rank','consequence_replica_id', ...
    'D_finite','D_nonnegative','C_domain_exact','D_persistent_nondecreasing','A_persistent_nonincreasing', ...
    'C_nondecreasing_while_reachable','failed_line_persistent','closed_road_persistent','source_demand_zero','passed','formal_scenario_sha256'});
end

function T=build_collision_audit(id,seedMap)
roles=["nominal","validation-1","validation-2"];rows=cell(4,7);
for ii=1:3
    q=seedMap(seedMap.dataset_role==roles(ii),:);w=sum(double(q.wind_seed)==double(id.wind_seed(1)));
    r=sum(double(q.resistance_seed)==double(id.resistance_seed(1)));
    rows(ii,:)={"support_out_vs_"+roles(ii),height(id),height(q),w,r,w+r,(w+r)==0};
end
tuple=string(id.wind_seed)+"|"+string(id.wind_stream_position)+"|"+string(id.resistance_seed)+"|"+string(id.resistance_stream_position);
rows(4,:)={"within_support_out_namespace",height(id),height(id),height(id)-numel(unique(tuple)),0,height(id)-numel(unique(tuple)),numel(unique(tuple))==height(id)};
T=cell2table(rows,'VariableNames',{'audit_scope','support_out_identity_count','comparison_identity_count', ...
    'wind_seed_collision_count','resistance_seed_collision_count','total_identity_collision_count','passed'});
end

function T=build_reproducibility_audit(formal,replayExact,manifest,dac)
rows={"full_raw_replay",replayExact,string(replayExact),"true"; ...
    "scenario_hashes_recorded",numel(formal.scenario_sha256)==height(manifest),string(numel(formal.scenario_sha256)),string(height(manifest)); ...
    "replica_identity_unique",numel(unique(manifest.consequence_replica_id))==height(manifest),string(numel(unique(manifest.consequence_replica_id))),string(height(manifest)); ...
    "D_raw_sha256",true,formal.full_D_sha256,formal.full_D_sha256; ...
    "A_raw_sha256",true,formal.full_A_sha256,formal.full_A_sha256; ...
    "C_raw_sha256",true,formal.full_C_sha256,formal.full_C_sha256; ...
    "DAC_business_logic",all(dac.passed),string(sum(dac.passed)),string(height(dac))};
T=cell2table(rows,'VariableNames',{'audit','passed','observed','expected'});
end

function assert_recovery(entry),if ~entry.audit.all_final_DAC_exact||~entry.audit.all_stream_hashes_match||entry.audit.max_DAC_error~=0,error('Frozen prefix recovery failed.');end,end
function assert_optimal(out,label),if out.exitflag~=1||out.status~="OPTIMAL"||out.max_demand_balance_error>1e-7||out.max_site_capacity_violation>1e-7,error('%s recourse failed: %s',label,out.status);end,end
function value=pct(x,p),x=sort(double(x(:)));x=x(isfinite(x));value=x(max(1,min(numel(x),ceil(p/100*numel(x)))));end
function values=aslogical(values),if islogical(values),return;elseif isnumeric(values),values=values~=0;else,s=lower(strtrim(string(values)));values=s=="true"|s=="1";end,end
function add_gurobi_path(),for c={fullfile(getenv('GUROBI_HOME'),'matlab'),'D:\gurobi1201\win64\matlab','C:\gurobi1201\win64\matlab'},if ~isempty(c{1})&&isfolder(c{1}),addpath(c{1});end,end,end
function assert_git_gate(branch,head)
[a,b]=system('git branch --show-current');[c,d]=system('git rev-parse HEAD');[e,f]=system('git rev-parse @{upstream}');
[g,h]=system('git ls-remote --heads origin refs/heads/task/002-stage2b-b3-smoke');remote=extractBefore(strtrim(string(h)),char(9));
if a~=0||c~=0||e~=0||g~=0||strtrim(string(b))~=branch||strtrim(string(d))~=head||strtrim(string(f))~=head||remote~=head,error('Frozen Git gate failed.');end
end
function hash=sha256_file(file),fid=fopen(file,'rb');cleanup=onCleanup(@()fclose(fid));md=java.security.MessageDigest.getInstance('SHA-256');while true,b=fread(fid,1024*1024,'*uint8');if isempty(b),break;end;md.update(typecast(b,'int8'));end;digest=typecast(md.digest(),'uint8');hash=lower(string(reshape(dec2hex(digest,2).',1,[])));end
function preserve_failed_tmp(tmpDir),if isfolder(tmpDir),fprintf(2,'Step-04C-A2 temporary output preserved at %s\n',tmpDir);end,end
function write_run_metadata(file,head,n,replicas,calls,evals,replay,dac,hash1,hash2),fid=fopen(file,'w');cleanup=onCleanup(@()fclose(fid));fprintf(fid,'frozen_head=%s\nscenario_identities=%d\nreplicas_per_path=%d\nsolver_calls=%d\nscenario_evaluations=%d\nbyte_exact_replay=%d\nDAC_audit_pass=%d\nextreme_manifest_sha256=%s\noverlap_sha256=%s\n',head,n,replicas,calls,evals,replay,dac,hash1,hash2);end
