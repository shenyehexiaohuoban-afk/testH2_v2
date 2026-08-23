function run_stage89q_penalty1000_vs1500_5h_hourly_h2()
%RUN_STAGE89Q_PENALTY1000_VS1500_5H_HOURLY_H2 Strict paired Stage89Q workflow.

rootDir=fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(rootDir);addpath(fullfile(rootDir,'fa_h2'));
addpath(fullfile(rootDir,'fa_h2','fuzhu'));addpath(fullfile(rootDir,'utils'));
addpath(fullfile(rootDir,'hourly_grid_h2'));
addpath(fullfile(rootDir,'fa_msp','current_hourly_stage88_candidate','config'));
addpath(fullfile(rootDir,'fa_msp','current_hourly_stage88_candidate','input'));
addpath(fullfile(rootDir,'terminalLoh_wdro','current_w_mainline_stage89','msp_bridge'));
runId=char(string(getenv('STAGE89Q_RUN_ID')));if isempty(runId),runId='run-001';end
commit=strtrim(string(getenv('STAGE89Q_FROZEN_COMMIT')));
phase=upper(strtrim(string(getenv('STAGE89Q_PHASE'))));
arm=upper(strtrim(string(getenv('STAGE89Q_ARM'))));
if commit==""||phase=="",error('Stage89Q:Environment','Frozen commit and phase are required.');end
[st,head]=system('git rev-parse HEAD');head=strtrim(string(head));
if st~=0||head~=commit,error('Stage89Q:Commit','HEAD %s != frozen %s.',head,commit);end
outDir=run_dir(rootDir,runId);
try
    run_phase(rootDir,outDir,commit,phase,arm);
catch ME
    if isfolder(outDir)
        write_text(fullfile(outDir,'FAILURE.txt'),string(getReport(ME,'extended','hyperlinks','off')));
        write_status(outDir,'FAILED',phase,arm,0,0,feature('getpid'),commit);
    end
    rethrow(ME);
end
end

function run_phase(rootDir,outDir,commit,phase,arm)
pid=feature('getpid');
if phase=="INIT"
    if isfolder(outDir),error('Stage89Q:OutputExists','Refusing to overwrite %s.',outDir);end
    make_dirs(rootDir,outDir,run_id(outDir));audit_accepted_evidence(rootDir,outDir);preflight_gate(rootDir,outDir);
    write_status(outDir,'RUNNING','INITIALIZED','NONE',0,0,pid,commit);return
end
if ~isfolder(outDir),error('Stage89Q:NotInitialized','Run is not initialized.');end
if ismember(phase,["TRAIN","OOS"])
    assert_arm(arm);logFile=fullfile(outDir,'logs',char(lower(phase)+"-"+lower(arm)+".txt"));
else
    logFile=fullfile(outDir,'logs',char(lower(phase)+".txt"));
end
diary(logFile);cleanup=onCleanup(@()diary('off')); %#ok<NASGU>
if phase=="TRAIN",train_arm(rootDir,outDir,arm,commit,pid);return;end
if phase=="BANK",build_oos_bank(rootDir,outDir,commit,pid);return;end
if phase=="OOS",evaluate_arm_oos(rootDir,outDir,arm,commit,pid);return;end
if phase=="SERIALIZER_SMOKE",serializer_smoke(rootDir,outDir,commit,pid);return;end
error('Stage89Q:Phase','Unknown phase %s.',phase);
end

function train_arm(rootDir,outDir,arm,commit,pid)
[label,penalty]=arm_spec(arm);shortage=200;caseDir=training_dir(outDir,arm);checkpoint=checkpoint_path(rootDir,outDir,arm);
if isfile(checkpoint)||isfile(fullfile(caseDir,'training_progress.csv'))
    error('Stage89Q:TrainingExists','Refusing to overwrite training for %s.',label);
end
[p,opts]=load_params(rootDir,penalty);rng(opts.seed,'twister');
lib=define_models_h2(p);assert_library(lib,p);initialCuts=cut_count(lib,p);
if initialCuts~=0,error('Stage89Q:WarmStart','%s did not start with zero cuts.',label);end
x=zeros(p.Ni,p.T);theta=zeros(p.T,1);lb=0;LB=zeros(0,1);rows=cell(0,29);
budget=18000;started=tic;iter=0;totalForward=0;totalBackward=0;warningCount=0;
write_status(outDir,'RUNNING','TRAIN',arm,0,0,pid,commit);
while iter==0||toc(started)<budget
    iter=iter+1;iterStart=tic;beforeRows=model_row_counts(lib,p);before=sum(max(0,beforeRows-base_rows(p)),'all');
    lastwarn('');f0=tic;[lib,x,theta,lb,path,fwd]=forward_pass_h2(lib,p,lb,x,theta);forwardTime=toc(f0);
    valid=all(ismember(fwd.status,["normal","loh_demand_stage","absorbing_lfNc","dissipated_absorb","post_absorb"]));
    if ~valid||~isfinite(lb)||any(~isfinite(x),'all'),error('Stage89Q:Forward','%s iteration %d failed.',label,iter);end
    b0=tic;[lib,cutFlag]=backward_pass_h2(lib,p,x,theta,path);backwardTime=toc(b0);
    afterRows=model_row_counts(lib,p);after=sum(max(0,afterRows-base_rows(p)),'all');
    newAudit=audit_new_cuts(lib,p,beforeRows,afterRows);
    if ~newAudit.pass||after<=before,error('Stage89Q:Cuts','%s iteration %d cut audit failed.',label,iter);end
    LB(iter,1)=lb;if iter==1,delta=NaN;else,delta=LB(iter)-LB(iter-1);end
    [warningMessage,warningId]=lastwarn;if strlength(string(warningId))>0,warningCount=warningCount+1;end
    totalForward=totalForward+nnz(fwd.status=="normal");totalBackward=totalBackward+(after-before);
    policyModel=update_rhs_h2(modelLib_at(lib,1,p.k_init),p,p.k_init,1,p.x_0);policySol=solve_stage_model_h2(policyModel);
    stage1SiteProd=sum(policySol.h2_production_hourly_kg,2);stage1Prod=sum(stage1SiteProd);
    rows(end+1,:)={label,penalty,iter,budget,toc(started),lb,delta,sum(fwd.stageCost),before,after,after-before, ...
        nnz(fwd.status=="normal"),after-before,forwardTime,backwardTime,toc(iterStart),cutFlag, ...
        string(warningId),string(warningMessage),"FIXED_5H_BUDGET_TRAINING","NOT_CONVERGENCE_CERTIFICATE", ...
        stage1Prod,stage1SiteProd(1),stage1SiteProd(2),stage1SiteProd(3),stage1SiteProd(4),sum(x(:,1)),sum(x(:,2)),sum(x(:,3))}; %#ok<AGROW>
    writetable(cell2table(rows,'VariableNames',training_names()),fullfile(caseDir,'training_progress.csv'));
    write_status(outDir,'RUNNING','TRAIN',arm,iter,toc(started),pid,commit);
    fprintf('Stage89Q %s iter=%d elapsed=%.3f LB=%.12g cuts=%d\n',label,iter,toc(started),lb,after);
end
trainingWall=toc(started);fullAudit=audit_all_cuts(lib,p);
if ~fullAudit.pass,error('Stage89Q:FinalCutAudit','%s full cut audit failed.',label);end
model=first_operating_model(lib,p);finalCuts=cut_count(lib,p);
checkpoint_metadata=struct('stage','89Q','arm',char(arm),'arm_label',char(label), ...
    'terminal_gap_penalty_yuan_per_kg',penalty,'shortage_penalty_yuan_per_kg',shortage, ...
    'htt_c0_yuan_per_kg',p.htt_base_service_cost_yuan_per_kg,'htt_cost_base_matrix',p.cost_transport_base, ...
    'beta_multiplier',2,'fleet_cap_kg_per_h',160,'eta',0.03, ...
    'demand_schema','original-hourly-24h-repeat-v1','training_seed',opts.seed, ...
    'training_budget_s',budget,'training_wall_time_s',trainingWall,'completed_iterations',iter, ...
    'final_LB',LB(end),'fresh_initial_cut_count',initialCuts,'cumulative_cuts',finalCuts, ...
    'state_dimension',4,'state_order','Site1,Site2,Site3,Site4','variable_count',model.nvars, ...
    'base_inequality_count',base_rows(p),'equality_count',size(model.Aeq,1),'integer_count',0, ...
    'terminal_lookup_sha256',char(opts.terminal_loh_expected_sha256),'model_schema','hourly-h2-hourly-htt-v1', ...
    'training_identity','FIXED_5H_BUDGET_TRAINING','convergence_scope','NOT_CONVERGENCE_CERTIFICATE', ...
    'warm_start_checkpoint','NONE','cross_arm_cut_source','NONE','frozen_commit',char(commit));
params=p;modelLib=lib;state=struct('x',x,'theta',theta,'lb',lb,'LB',LB); %#ok<NASGU>
policy=struct('representation','modelLib_with_embedded_cuts','state_order','Site1,Site2,Site3,Site4', ...
    'classification','STAGE89Q_FIXED_5H_POLICY');rng_state=rng; %#ok<NASGU>
save_checkpoint_safe(checkpoint,params,modelLib,state,policy,opts,rng_state,checkpoint_metadata);
info=dir(checkpoint);summary=table(label,penalty,shortage,p.htt_base_service_cost_yuan_per_kg,2,0.03,opts.seed,budget,trainingWall,iter, ...
    LB(end),finalCuts,totalForward,totalBackward,warningCount,0,initialCuts,string(checkpoint), ...
    info.bytes,fullAudit.pass,"FIXED_5H_BUDGET_TRAINING","NOT_CONVERGENCE_CERTIFICATE",stage1Prod, ...
    'VariableNames',{'arm','terminal_gap_penalty_yuan_per_kg','shortage_penalty_yuan_per_kg','c0_yuan_per_kg', ...
    'beta_multiplier','eta','training_seed','budget_s','actual_training_wall_time_s','completed_iterations', ...
    'final_LB','cumulative_cuts','forward_operating_solves','backward_cut_solves','warning_count','error_count', ...
    'fresh_initial_cuts','checkpoint_path','checkpoint_bytes','full_cut_audit_pass', ...
    'training_identity','convergence_scope','final_stage1_production_kg'});
safe_writetable(summary,fullfile(caseDir,'training_summary.csv'));
write_text(fullfile(caseDir,'TRAINING_FINISHED.txt'),sprintf('%s_TRAINING_FINISHED=true\n',label));
write_status(outDir,'RUNNING','TRAIN_FINISHED',arm,iter,trainingWall,pid,commit);
clear modelLib lib params p
end

function build_oos_bank(rootDir,outDir,commit,pid)
assert_both_training_gate(outDir);bankDir=fullfile(outDir,'03_oos','common');
bankFile=accepted_bank_path(rootDir);expectedSha="6bf3d1190a402ded052b8d3d08ed369042236e151f562bdd9fd4db7b8ff386c6";
if sha256_file(bankFile)~=expectedSha,error('Stage89Q:BankIdentity','Accepted bank SHA mismatch.');end
[p,~]=load_params(rootDir,1000);b=load(bankFile,'pathBank','seed');pathBank=double(b.pathBank);seed=double(b.seed);n=size(pathBank,1);
ids=(1:n).';vars=arrayfun(@(t)sprintf('k_t%d',t),1:p.T,'UniformOutput',false);
manifest=[table(ids,'VariableNames',{'path_id'}),array2table(pathBank,'VariableNames',vars)];
safe_writetable(manifest,fullfile(bankDir,'oos_path_manifest.csv'));
identity=table(seed,n,p.T,p.k_init,string(bankFile),expectedSha,sha256_file(fullfile(bankDir,'oos_path_manifest.csv')), ...
    "REUSE_ACCEPTED_STAGE89H_LOC4_BANK","COMMON_ORDERED_PATHS", ...
    'VariableNames',{'seed','path_count','stage_count','initial_state','bank_path','bank_sha256', ...
    'manifest_sha256','sampling_identity','pairing_identity'});
safe_writetable(identity,fullfile(bankDir,'bank_identity.csv'));
if n~=10000||size(pathBank,2)~=p.T||seed~=20260817||any(pathBank(:,1)~=p.k_init)||~isequal(ids,(1:10000).')
    error('Stage89Q:BankIdentity','Ordered common OOS identity failed.');
end
write_text(fullfile(bankDir,'BANK_LOCKED.txt'),"COMMON_10000_PATH_BANK_VERIFIED=true"+newline);
write_status(outDir,'RUNNING','BANK_LOCKED','BOTH',0,0,pid,commit);
clear pathBank p
end

function serializer_smoke(rootDir,outDir,commit,pid)
target=fullfile(outDir,'04_qa','hourly_serializer_regression.csv');
if isfile(target),error('Stage89Q:SmokeExists','Serializer smoke output exists.');end
[p,~]=load_params(rootDir,1000);lib=define_models_h2(p);assert_library(lib,p);
b=load(accepted_bank_path(rootDir),'pathBank');seq=double(b.pathBank(1,:));
    [prOff,srOff,~,hrOff,sysOff,frOff,nrOff]=evaluate_path(lib,p,seq,1,"Arm-A",1000,200,false);
    [prOn,srOn,~,hrOn,sysOn,frOn,nrOn]=evaluate_path(lib,p,seq,1,"Arm-A",1000,200,true);
    if ~isempty(hrOff)||~isempty(sysOff)||~isempty(frOff)
        error('Stage89Q:SerializerOff','Serialization OFF unexpectedly emitted hourly rows.');
    end
pathOff=cell2table(prOff,'VariableNames',path_names());pathOn=cell2table(prOn,'VariableNames',path_names());
stageOff=cell2table(srOff,'VariableNames',stage_names());stageOn=cell2table(srOn,'VariableNames',stage_names());
hourOn=cell2table(hrOn,'VariableNames',hour_site_names());systemOn=cell2table(sysOn,'VariableNames',hour_system_names());
flowOn=cell2table(frOn,'VariableNames',flow_names());
    metrics={
        'reported_objective',pathOff.reported_objective,pathOn.reported_objective;
        'total_H2_production',pathOff.total_H2_production,pathOn.total_H2_production;
        'terminal_inventory_total',pathOff.terminal_inventory_total,pathOn.terminal_inventory_total;
        'ordinary_shortage_total',pathOff.ordinary_shortage_total,pathOn.ordinary_shortage_total;
        'total_HTT',pathOff.total_HTT,pathOn.total_HTT};
    rows=cell(0,5);
    for i=1:size(metrics,1)
        d=abs(metrics{i,2}-metrics{i,3});rows(end+1,:)={metrics{i,1},metrics{i,2},metrics{i,3},d,d<=1e-9}; %#ok<AGROW>
    end
    stageMetrics={'stage_objective',stageOff.stage_objective_yuan,stageOn.stage_objective_yuan; ...
        'stage_production',stageOff.production_kg,stageOn.production_kg; ...
        'stage_end_inventory',stageOff.ending_inventory_kg,stageOn.ending_inventory_kg; ...
        'stage_ordinary_shortage',stageOff.ordinary_shortage_kg,stageOn.ordinary_shortage_kg; ...
        'stage_HTT',stageOff.htt_kg,stageOn.htt_kg};
    for i=1:size(stageMetrics,1)
        for j=1:height(stageOff)
            d=abs(stageMetrics{i,2}(j)-stageMetrics{i,3}(j));
            rows(end+1,:)={sprintf('%s_stage%d',stageMetrics{i,1},stageOff.stage(j)), ...
                stageMetrics{i,2}(j),stageMetrics{i,3}(j),d,d<=1e-9}; %#ok<AGROW>
        end
    end
reg=cell2table(rows,'VariableNames',{'metric','serialization_off','serialization_on','absolute_difference','pass'});
prodResidual=max(abs(hourOn.H2_production_kg-p.k_H2*hourOn.P_EL_kW));
serviceResidual=max(abs(hourOn.ordinary_served_kg+hourOn.ordinary_shortage_kg-hourOn.ordinary_demand_kg));
preResidual=max(abs(hourOn.inventory_before_HTT_kg-(hourOn.begin_inventory_kg+hourOn.H2_production_kg-hourOn.ordinary_served_kg)));
endResidual=max(abs(hourOn.end_inventory_kg-(hourOn.inventory_before_HTT_kg-hourOn.HTT_out_kg+hourOn.HTT_in_kg)));
smokePass=all(reg.pass)&&nrOff.max_eq<=1e-6&&nrOn.max_eq<=1e-6&&prodResidual<=1e-9&&serviceResidual<=1e-9&&preResidual<=1e-9&&endResidual<=1e-9;
reg.smoke_pass(:)=smokePass;safe_writetable(reg,target);
safe_writetable(hourOn,fullfile(outDir,'04_qa','serializer_smoke_hour_site.csv'));
safe_writetable(systemOn,fullfile(outDir,'04_qa','serializer_smoke_grid_hour.csv'));
if ~isempty(flowOn),safe_writetable(flowOn,fullfile(outDir,'04_qa','serializer_smoke_htt_od.csv'));end
closure=table(prodResidual,serviceResidual,preResidual,endResidual,smokePass, ...
    'VariableNames',{'production_residual','service_residual','pre_inventory_residual','end_inventory_residual','pass'});
safe_writetable(closure,fullfile(outDir,'04_qa','serializer_smoke_closure.csv'));
if ~smokePass,error('Stage89Q:SerializerRegression','Serializer OFF/ON regression failed.');end
write_status(outDir,'RUNNING','SERIALIZER_SMOKE_PASS','NONE',1,0,pid,commit);
clear lib p
end

function evaluate_arm_oos(rootDir,outDir,arm,commit,pid)
assert_both_training_gate(outDir);[label,penalty]=arm_spec(arm);shortage=200;oosDir=oos_dir(rootDir,outDir,arm);
if isfile(fullfile(oosDir,'oos_metadata.csv')),error('Stage89Q:OOSExists','OOS exists for %s.',label);end
bankFile=accepted_bank_path(rootDir);bankIdentity=readtable(fullfile(outDir,'03_oos','common','bank_identity.csv'),'TextType','string');
if ~isfile(bankFile)||height(bankIdentity)~=1||bankIdentity.path_count~=10000||sha256_file(bankFile)~=bankIdentity.bank_sha256
    error('Stage89Q:BankGate','Locked common bank failed for %s.',label);
end
b=load(bankFile,'pathBank');pathBank=double(b.pathBank);checkpoint=checkpoint_path(rootDir,outDir,arm);
checkpointHashBefore=lower(strtrim(string(getenv('STAGE89Q_CHECKPOINT_SHA256'))));
if strlength(checkpointHashBefore)~=64,error('Stage89Q:ExternalHash','External checkpoint SHA-256 is required.');end
if sha256_file(checkpoint)~=checkpointHashBefore,error('Stage89Q:ExternalHash','Checkpoint SHA mismatch before clean load.');end
loaded=load(checkpoint);p=loaded.params;lib=loaded.modelLib;m=loaded.checkpoint_metadata;clear loaded
if string(m.stage)~="89Q"||string(m.arm_label)~=label||m.terminal_gap_penalty_yuan_per_kg~=penalty|| ...
        m.shortage_penalty_yuan_per_kg~=shortage||m.training_seed~=20260513||m.training_budget_s~=18000|| ...
        m.training_wall_time_s<18000||m.fresh_initial_cut_count~=0||string(m.warm_start_checkpoint)~="NONE"|| ...
        m.cumulative_cuts~=cut_count(lib,p)||p.cost_reserve_shortage~=penalty||p.cost_normal_shortage~=200
    error('Stage89Q:PolicyIdentity','Policy identity failed for %s.',label);
end
cutsBefore=cut_count(lib,p);files=oos_files(oosDir);if any(cellfun(@isfile,struct2cell(files))),error('Stage89Q:OOSOutput','Output files exist.');end
first=true;firstFlow=true;firstBatch=true;totalSolves=0;maxEq=0;maxIneq=0;started=tic;
pathBuffer=cell(0,numel(path_names()));stageBuffer=cell(0,numel(stage_names()));siteBuffer=cell(0,numel(stage_site_names()));
hourBuffer=cell(0,numel(hour_site_names()));systemBuffer=cell(0,numel(hour_system_names()));flowBuffer=cell(0,numel(flow_names()));
write_status(outDir,'RUNNING','OOS',arm,0,0,pid,commit);
for q=1:10000
    [pr,sr,ss,hr,sys,fr,nr]=evaluate_path(lib,p,pathBank(q,:),q,label,penalty,shortage,true);
    totalSolves=totalSolves+nr.solve_count;maxEq=max(maxEq,nr.max_eq);maxIneq=max(maxIneq,nr.max_ineq);
    pathBuffer=[pathBuffer;pr];stageBuffer=[stageBuffer;sr];siteBuffer=[siteBuffer;ss]; %#ok<AGROW>
    hourBuffer=[hourBuffer;hr];systemBuffer=[systemBuffer;sys];flowBuffer=[flowBuffer;fr]; %#ok<AGROW>
    if mod(q,100)==0||q==10000
        nPath=height(cell2table(pathBuffer));nStage=height(cell2table(stageBuffer));nSite=height(cell2table(siteBuffer));
        nHour=height(cell2table(hourBuffer));nSystem=height(cell2table(systemBuffer));nFlow=height(cell2table(flowBuffer));
        append_table(files.path,cell2table(pathBuffer,'VariableNames',path_names()),first);
        append_table(files.stage,cell2table(stageBuffer,'VariableNames',stage_names()),first);
        append_table(files.site,cell2table(siteBuffer,'VariableNames',stage_site_names()),first);
        append_table(files.hour,cell2table(hourBuffer,'VariableNames',hour_site_names()),first);
        append_table(files.system,cell2table(systemBuffer,'VariableNames',hour_system_names()),first);
        if ~isempty(flowBuffer)
            append_table(files.flow,cell2table(flowBuffer,'VariableNames',flow_names()),firstFlow);firstFlow=false;
        end
        first=false;pathBuffer=cell(0,numel(path_names()));stageBuffer=cell(0,numel(stage_names()));
        siteBuffer=cell(0,numel(stage_site_names()));hourBuffer=cell(0,numel(hour_site_names()));
        systemBuffer=cell(0,numel(hour_system_names()));flowBuffer=cell(0,numel(flow_names()));
        batch=table(label,penalty,q-99,q,nPath,nStage,nSite,nHour,nSystem,nFlow,toc(started), ...
            'VariableNames',{'arm','penalty','first_path_id','last_path_id','path_rows','stage_rows','site_rows','hour_site_rows','grid_hour_rows','positive_htt_rows','wall_time_s'});
        append_table(fullfile(oosDir,'batch_completion.csv'),batch,firstBatch);firstBatch=false;
        progress=table(label,penalty,q,toc(started),totalSolves,maxEq,maxIneq, ...
            'VariableNames',{'arm','penalty','completed_paths','wall_time_s','operating_solves','max_eq_residual','max_ineq_violation'});
        safe_writetable(progress,fullfile(oosDir,'progress.csv'));
        write_status(outDir,'RUNNING','OOS',arm,q,toc(started),pid,commit);
    end
end
cutsAfter=cut_count(lib,p);clear lib p pathBank
checkpointHashAfter=sha256_file(checkpoint);paths=readtable(files.path,'TextType','string');
pass=height(paths)==10000&&isequal(double(paths.path_id),(1:10000).')&&cutsBefore==cutsAfter&& ...
    checkpointHashBefore==checkpointHashAfter&&maxEq<=1e-6&&maxIneq<=1e-6;
meta=table(label,10000,height(paths),totalSolves,toc(started),cutsBefore,cutsAfter,cutsBefore==cutsAfter, ...
    string(checkpoint),checkpointHashBefore,checkpointHashAfter,checkpointHashBefore==checkpointHashAfter, ...
    string(bankFile),bankIdentity.bank_sha256,maxEq,maxIneq,pass, ...
    'VariableNames',{'policy','requested_paths','completed_paths','operating_solves','wall_time_s', ...
    'cuts_before','cuts_after','cuts_unchanged','checkpoint_path','checkpoint_sha256_before', ...
    'checkpoint_sha256_after','checkpoint_unchanged','bank_path','bank_sha256','max_eq_residual', ...
    'max_ineq_violation','pass'});
safe_writetable(meta,fullfile(oosDir,'oos_metadata.csv'));
if ~pass,error('Stage89Q:OOSGate','%s OOS completion gate failed.',label);end
write_text(fullfile(oosDir,'OOS_RAW_COMPLETED.marker'),sprintf('%s_10000_OOS_RAW_COMPLETE=true\n',label));
write_status(outDir,'RUNNING','OOS_COMPLETE',arm,10000,toc(started),pid,commit);
end

function [pr,stageRows,siteRows,hourRows,systemRows,flowRows,numerical]=evaluate_path(lib,p,seq,pathId,label,penalty,shortage,serializeHourly)
prev=p.x_0(:);opCost=0;holdCost=0;prodCost=0;gridCost=0;omCost=0;shortKg=0;shortCost=0;
prodKg=0;httKg=0;httCost=0;terminalValue=0;terminalGap=zeros(4,1);terminalTarget=zeros(4,1);terminalState=0;
stageRows=cell(0,numel(stage_names()));siteRows=cell(0,numel(stage_site_names()));
hourRows=cell(0,numel(hour_site_names()));systemRows=cell(0,numel(hour_system_names()));flowRows=cell(0,numel(flow_names()));
solveCount=0;maxEq=0;maxIneq=0;operatingStages=0;
terminationType="NO_TERMINATION";terminationStage=NaN;terminationState=seq(end);
for t=1:p.T
    k=seq(t);a=p.S(k,1);loc=p.S(k,2);lf=p.S(k,3);beta=p.beta(k);
    if p.is_dissipated(k),terminationType="PHYSICAL_DISSIPATION_A1";terminationStage=t;terminationState=k;break;end
    if p.is_absorbing(k),terminationType="LF8_ABSORBING";terminationStage=t;terminationState=k;break;end
    if p.is_loh_demand_stage(k)
        terminationType="STAGE7_TERMINAL_CHECK";terminationStage=t;terminationState=k;
        terminalState=k;terminalTarget=p.TerminalLOH(:,k);terminalGap=max(0,terminalTarget-prev);
        [terminalValue,g]=terminal_value_and_subgradient_h2(prev,p,k);
        if numel(g)~=4||any(~isfinite(g))||~isfinite(terminalValue),error('Stage89Q:Terminal','Bad terminal value.');end
        break
    end
    if t>6,error('Stage89Q:Lifecycle','Ordinary state after Stage6.');end
    operatingStages=operatingStages+1;beginInv=prev;m=update_rhs_h2(lib.models{t,k},p,k,t,prev);s=solve_stage_model_h2(m);solveCount=solveCount+1;
    eq=max(abs(m.Aeq*s.xraw-m.beq));ineq=max([0;m.A*s.xraw-m.b]);maxEq=max(maxEq,eq);maxIneq=max(maxIneq,ineq);
    if ~strcmpi(s.status,'OPTIMAL')&&~strcmpi(s.status,'normal'),error('Stage89Q:Solve','Invalid solve status path %d stage %d.',pathId,t);end
    if eq>1e-6||ineq>1e-6||any(~isfinite(s.xraw))||numel(s.lambda.inventory_eq)~=4||any(~isfinite(s.lambda.inventory_eq))
        error('Stage89Q:Numerical','Numerical gate path %d stage %d.',pathId,t);
    end
    distanceCost=p.cost_transport_base;if p.use_beta_cost,distanceCost=distanceCost*(1+p.beta_transport_multiplier*beta);end
    unit=p.htt_base_service_cost_yuan_per_kg+distanceCost;flow=s.f_hourly_kg;costCube=flow.*repmat(unit,1,1,8);
    if max(abs(m.htt_unit_cost_yuan_per_kg-unit),[],'all')>1e-10
        error('Stage89Q:HTTCost','HTT coefficient gate failed.');
    end
    tau=8*(t-1)+(1:8);stageGrid=sum(p.hourly_grid.tariff48(tau(:)).*s.p_grid_kw(:));stageOm=p.cost_el_om*8*sum(s.eval);
    stageHold=p.cost_holding*sum(s.xval);stageShort=sum(s.z_normal_hourly_kg,'all');stageProd=sum(s.h2_production_hourly_kg,'all');
    stageHtt=sum(flow,'all');stageHttCost=sum(costCube,'all');stageObjective=s.obj-s.theta;
    if abs(stageObjective-(stageGrid+stageOm+stageHold+shortage*stageShort+stageHttCost))>1e-5
        error('Stage89Q:Objective','Objective decomposition failed path %d stage %d.',pathId,t);
    end
    stageRows(end+1,:)={label,penalty,pathId,t,k,a,loc,lf,beta,stageObjective,stageGrid+stageOm,stageGrid,stageOm, ...
        stageHold,stageShort,shortage*stageShort,stageProd,stageHtt,stageHttCost,sum(beginInv),sum(s.xval),s.theta}; %#ok<AGROW>
    for i=1:4
        siteRows(end+1,:)={label,penalty,pathId,t,k,a,loc,lf,beta,i,beginInv(i),sum(s.h2_demand_hourly_kg(i,:)), ...
            sum(s.u_normal_hourly_kg(i,:)),sum(s.z_normal_hourly_kg(i,:)),sum(s.h2_production_hourly_kg(i,:)), ...
            sum(s.htt_in_hourly_kg(i,:)),sum(s.htt_out_hourly_kg(i,:)),s.xval(i)}; %#ok<AGROW>
    end
    v=sqrt(max(s.v_sq,0));trueS=hypot(s.p_branch_kw,s.q_branch_kvar)/1000;
    if serializeHourly
    for h=1:8
        gh=8*(t-1)+h;capacity=max(0,(1-beta)*160);totalFlow=sum(flow(:,:,h),'all');
        [minV,minBus]=min(v(:,h));[maxBranch,ell]=max(trueS(:,h));
        pvAvail=p.hourly_grid.pv_cap_kw(:)*p.hourly_grid.phi48(gh);
        lineUtil=maxBranch/p.hourly_grid.branch_smax_mva;totalPel=sum(s.p_el_hourly_kw(:,h));
        binding=any(abs(s.p_el_hourly_kw(:,h)-p.el_cap_kw(:))<=1e-6)||minV<=p.hourly_grid.vmin_pu+1e-6||lineUtil>=1-1e-6;
        systemRows(end+1,:)={label,penalty,pathId,t,k,a,loc,lf,beta,h,gh,p.hourly_grid.tariff48(gh), ...
            totalPel, ...
            sum(pvAvail),sum(s.p_pv_kw(:,h)),s.p_grid_kw(h),minV,minBus,maxBranch, ...
            ell,p.hourly_grid.branch_from(ell),p.hourly_grid.branch_to(ell),lineUtil, ...
            binding,totalFlow,capacity,ternary(capacity>0,totalFlow/capacity,0),capacity>0&&abs(totalFlow-capacity)<=1e-6}; %#ok<AGROW>
        for i=1:4
            bus=p.hourly_grid.site_elec_bus(i);pre=s.h2_inventory_pre_htt_kg(i,h);ending=s.h2_inventory_hourly_kg(i,h);
            if h==1,beginHour=beginInv(i);else,beginHour=s.h2_inventory_hourly_kg(i,h-1);end
            hourRows(end+1,:)={label,penalty,pathId,t,k,a,loc,lf,beta,h,gh,i,bus,p.hourly_grid.tariff48(gh), ...
                s.h2_demand_hourly_kg(i,h),s.u_normal_hourly_kg(i,h),s.z_normal_hourly_kg(i,h), ...
                s.h2_production_hourly_kg(i,h),s.p_el_hourly_kw(i,h),pvAvail(i),s.p_pv_kw(i,h), ...
                s.p_grid_kw(h),v(bus,h),beginHour,pre,ending,s.htt_in_hourly_kg(i,h),s.htt_out_hourly_kg(i,h), ...
                "RECONSTRUCTED","DIRECT","DIRECT",abs(s.p_el_hourly_kw(i,h)-p.el_cap_kw(i))<=1e-6,abs(ending-p.x_cap(i))<=1e-6}; %#ok<AGROW>
            for j=1:4
                if i==j||flow(i,j,h)<=1e-8,continue;end
                f=flow(i,j,h);flowRows(end+1,:)={label,penalty,pathId,t,k,a,loc,lf,beta,h,gh,i,j,f, ...
                    p.site_to_site_road_km(i,j),unit(i,j),f*unit(i,j),f<5,f<10, ...
                    s.h2_inventory_pre_htt_kg(i,h),s.h2_inventory_hourly_kg(i,h), ...
                    s.h2_inventory_pre_htt_kg(j,h),s.h2_inventory_hourly_kg(j,h), ...
                    s.h2_demand_hourly_kg(j,h),s.u_normal_hourly_kg(j,h),s.z_normal_hourly_kg(j,h), ...
                    s.h2_production_hourly_kg(i,h),capacity,totalFlow,capacity>0&&abs(totalFlow-capacity)<=1e-6}; %#ok<AGROW>
            end
        end
    end
    end
    opCost=opCost+stageObjective;holdCost=holdCost+stageHold;prodCost=prodCost+stageGrid+stageOm;
    gridCost=gridCost+stageGrid;omCost=omCost+stageOm;shortKg=shortKg+stageShort;shortCost=shortCost+shortage*stageShort;
    prodKg=prodKg+stageProd;httKg=httKg+stageHtt;httCost=httCost+stageHttCost;prev=s.xval;
end
surplus=max(prev-terminalTarget,0);gSite=sum(terminalGap);gTotal=max(sum(terminalTarget)-sum(prev),0);gSpatial=gSite-gTotal;
if gSite<=1e-7,gapClass="NO_GAP";elseif gTotal>1e-7&&gSpatial<=1e-7,gapClass="PURE_QUANTITY_SHORTFALL"; ...
elseif gTotal<=1e-7&&gSpatial>1e-7,gapClass="PURE_SPATIAL_MISMATCH";else,gapClass="MIXED_QUANTITY_AND_SPATIAL";end
reachedStage7=terminalState>0;physicalDissipation=terminationType=="PHYSICAL_DISSIPATION_A1";lf8Absorbing=terminationType=="LF8_ABSORBING";
terminalA=NaN;terminalLoc=NaN;if reachedStage7,terminalA=p.S(terminalState,1);terminalLoc=p.S(terminalState,2);end
pr={label,penalty,pathId,strjoin(string(seq),'-'),terminationType,terminationStage,terminationState,operatingStages, ...
    reachedStage7,physicalDissipation,lf8Absorbing,opCost+terminalValue,opCost,holdCost,prodCost,gridCost,omCost, ...
    shortKg,shortKg>1e-7,shortCost,prodKg,httKg,httCost,sum(prev),prev(1),prev(2),prev(3),prev(4),terminalState,terminalA,terminalLoc, ...
    terminalTarget(1),terminalTarget(2),terminalTarget(3),terminalTarget(4),sum(terminalTarget), ...
    terminalGap(1),terminalGap(2),terminalGap(3),terminalGap(4),gSite,gTotal,gSpatial,gSite>1e-7,gapClass, ...
    surplus(1),surplus(2),surplus(3),surplus(4),terminalValue,p.S(terminationState,1),p.S(terminationState,2),p.S(terminationState,3)};
numerical=struct('solve_count',solveCount,'max_eq',maxEq,'max_ineq',maxIneq);
end

function [p,opts]=load_params(rootDir,penalty)
[p,opts,candidateAudit]=load_current_stage89_hourly_h2(rootDir,"dro");opts.seed=20260513;
opts.terminal_loh_lookup_file=char(p.terminal_loh_source);
opts.terminal_loh_expected_sha256=char(p.terminal_loh_lookup_audit.source_sha256);
p.cost_reserve_shortage=penalty;p.NearStageInput.Cost.reserve_shortage_penalty_yuan_per_kg=penalty;
baseState=p.k_init;initialA=p.S(baseState,1);initialLf=p.S(baseState,3);p.k_init=p.state_id(initialA,4,initialLf);
expectedX0=[58.04455704486949;50.30813793862475;25.262133442309338;33.02358084624278];
if ~candidateAudit.pass||~p.enable_hourly_grid||p.dt_h~=8||p.T~=8||p.Ni~=4|| ...
        p.S(p.k_init,1)~=initialA||p.S(p.k_init,2)~=4||p.S(p.k_init,3)~=initialLf|| ...
        p.cost_normal_shortage~=200||p.cost_reserve_shortage~=penalty||~ismember(penalty,[1000 1500])|| ...
        string(p.terminal_loh_mode)~="stage89k_dro"||string(p.terminal_loh_lookup_audit.table_version)~="Stage89K"|| ...
        string(p.terminal_loh_lookup_audit.source_sha256)~="2fa1958944110701239a109ebf46d959324a351f2f27c1c3fbd62f333066eaa8"|| ...
        abs(p.terminal_loh_lookup_audit.eta-0.03)>1e-12||string(p.demand_schema)~="original-hourly-24h-repeat-v1"|| ...
        p.NearStageInput.NormalDemand.stage_dt_h~=6||~isequal(p.x_cap(:).',[300 200 100 200])|| ...
        ~isequal(p.el_cap_kw(:).',[300 200 120 150])||max(abs(p.x_0-expectedX0))>1e-12|| ...
        abs(p.k_H2-0.0195)>1e-12||abs(8*p.k_H2*sum(p.el_cap_kw)-120.12)>1e-10
    error('Stage89Q:Identity','Frozen Stage89K single-loc4 parameter identity mismatch.');
end
end

function audit_accepted_evidence(rootDir,outDir)
base=fullfile(rootDir,'results','task-002-stage2b-b3-smoke');
paths={fullfile(base,'stage89m-formal-adoption-and-8h-integration','run-001','README.md'), ...
    fullfile(base,'stage89n-stage89k-adopted-loc4-fresh-8h-retraining','run-003','README.md'), ...
    fullfile(base,'stage89o-comprehensive-policy-mechanism-analysis','run-005','README.md'), ...
    fullfile(base,'stage89p-original-paper-style-stage89n-analysis','run-002','README.md')};
tokens={"STAGE89M_STATUS = PASS","STAGE89N_STATUS = PASS","STAGE89O_STATUS = PASS","STAGE89P_STATUS = PASS"};rows=cell(numel(paths),5);
for i=1:numel(paths)
    if ~isfile(paths{i}),error('Stage89Q:AcceptedEvidence','Missing %s.',paths{i});end
    tokenPass=tokens{i}==""||contains(string(fileread(paths{i})),tokens{i});
    info=dir(paths{i});rows(i,:)={string(paths{i}),info.bytes,sha256_file(paths{i}),tokens{i},tokenPass};
end
audit=cell2table(rows,'VariableNames',{'path','bytes','sha256','required_token','pass'});
safe_writetable(audit,fullfile(outDir,'accepted_evidence_identity.csv'));
if ~all(audit.pass),error('Stage89Q:AcceptedEvidence','Accepted evidence token gate failed.');end
end

function preflight_gate(rootDir,outDir)
[a,oa]=load_params(rootDir,1000);[b,ob]=load_params(rootDir,1500);
an=a;bn=b;an.cost_reserve_shortage=0;bn.cost_reserve_shortage=0;
an.NearStageInput.Cost.reserve_shortage_penalty_yuan_per_kg=0;
bn.NearStageInput.Cost.reserve_shortage_penalty_yuan_per_kg=0;
libA=define_models_h2(a);libB=define_models_h2(b);assert_library(libA,a);assert_library(libB,b);
rows={
    'terminal_gap_penalty',string(a.cost_reserve_shortage),string(b.cost_reserve_shortage),'EXPECTED_ONLY_DIFF',a.cost_reserve_shortage==1000&&b.cost_reserve_shortage==1500;
    'normalized_parameter_struct',string(isequaln(an,bn)),string(true),'IDENTICAL',isequaln(an,bn);
    'normalized_options_struct',string(isequaln(oa,ob)),string(true),'IDENTICAL',isequaln(oa,ob);
    'training_seed',string(oa.seed),string(ob.seed),'IDENTICAL',oa.seed==ob.seed&&oa.seed==20260513;
    'terminal_table_sha256',string(a.terminal_loh_lookup_audit.source_sha256),string(b.terminal_loh_lookup_audit.source_sha256),'IDENTICAL',string(a.terminal_loh_lookup_audit.source_sha256)==string(b.terminal_loh_lookup_audit.source_sha256);
    'eta',string(a.terminal_loh_lookup_audit.eta),string(b.terminal_loh_lookup_audit.eta),'IDENTICAL',a.terminal_loh_lookup_audit.eta==b.terminal_loh_lookup_audit.eta;
    'initial_state',string(a.k_init),string(b.k_init),'IDENTICAL',a.k_init==b.k_init&&a.S(a.k_init,2)==4;
    'ordinary_shortage_penalty',string(a.cost_normal_shortage),string(b.cost_normal_shortage),'IDENTICAL',a.cost_normal_shortage==b.cost_normal_shortage&&a.cost_normal_shortage==200;
    'runtime_hours',string(6*8),string(6*8),'IDENTICAL',a.dt_h==8&&b.dt_h==8;
    'stage1_theoretical_cap_kg',string(8*a.k_H2*sum(a.el_cap_kw)),string(8*b.k_H2*sum(b.el_cap_kw)),'IDENTICAL',abs(8*a.k_H2*sum(a.el_cap_kw)-120.12)<1e-10&&abs(8*b.k_H2*sum(b.el_cap_kw)-120.12)<1e-10;
    'fresh_initial_cuts',string(cut_count(libA,a)),string(cut_count(libB,b)),'IDENTICAL',cut_count(libA,a)==0&&cut_count(libB,b)==0};
audit=cell2table(rows,'VariableNames',{'parameter','arm_a','arm_b','expected_relation','pass'});
safe_writetable(audit,fullfile(outDir,'00_identity','paired_parameter_identity_audit.csv'));
if ~all(audit.pass),error('Stage89Q:UnexpectedArmDiff','UNEXPECTED_ARM_DIFF = YES');end
clear libA libB a b an bn
end

function assert_library(lib,p)
for t=1:6
    present=lib.models(t,:);present=present(~cellfun(@isempty,present));
    if isempty(present)||~all(cellfun(@(m)m.hourly_grid_enabled&&m.hourly_h2_balance_enabled&&m.hourly_htt_enabled&& ...
            m.nvars==1129&&size(m.A,1)==base_rows(p),present))
        error('Stage89Q:Library','Fresh library invalid at stage %d.',t);
    end
end
end

function rows=model_row_counts(lib,p)
rows=zeros(6,p.K);
for t=1:6
    for k=1:p.K
        m=lib.models{t,k};
        if ~isempty(m),rows(t,k)=size(m.A,1);end
    end
end
end
function a=audit_new_cuts(lib,p,beforeRows,afterRows)
finite=true;stateOnly=true;thetaOk=true;count=0;
for t=1:6
    for k=1:p.K
        m=lib.models{t,k};if isempty(m),continue;end
        for r=beforeRows(t,k)+1:afterRows(t,k)
            count=count+1;v=[full(m.A(r,m.idx.x)),full(m.A(r,m.idx.theta)),m.b(r)];finite=finite&&all(isfinite(v));
            allowed=false(1,m.nvars);allowed(m.idx.x)=true;allowed(m.idx.theta)=true;
            stateOnly=stateOnly&&nnz(m.A(r,~allowed))==0;thetaOk=thetaOk&&abs(m.A(r,m.idx.theta)+1)<=1e-12;
        end
    end
end
a=struct('pass',finite&&stateOnly&&thetaOk&&count==sum(afterRows-beforeRows,'all')&&count>0);
end
function a=audit_all_cuts(lib,p)
base=base_rows(p);before=zeros(6,p.K);after=model_row_counts(lib,p);before(after>0)=base;a=audit_new_cuts(lib,p,before,after);
a.pass=a.pass&&sum(max(0,after-base),'all')==cut_count(lib,p);
end
function n=cut_count(lib,p),r=model_row_counts(lib,p);n=sum(max(0,r-base_rows(p)),'all');end
function n=base_rows(p),n=8+4*8+8*8*p.hourly_grid.n_branch;end
function model=first_operating_model(lib,p)
model=[];
for t=1:6
    for k=1:p.K
        if ~isempty(lib.models{t,k}),model=lib.models{t,k};return;end
    end
end
end
function model=modelLib_at(lib,t,k),model=lib.models{t,k};end

function save_checkpoint_safe(path,params,modelLib,state,policy,opts,rng_state,checkpoint_metadata)
tmp=[path '.tmp.mat'];save(tmp,'params','modelLib','state','policy','opts','rng_state','checkpoint_metadata','-v7.3');
v=whos('-file',tmp);required={'params','modelLib','state','policy','opts','rng_state','checkpoint_metadata'};
if ~all(ismember(required,{v.name})),error('Stage89Q:CheckpointWrite','Incomplete checkpoint.');end
movefile(tmp,path,'f');
end

function f=oos_files(dirPath)
f=struct('path',fullfile(dirPath,'path_summary','oos_path_summary.csv'),'stage',fullfile(dirPath,'path_summary','oos_stage_summary.csv'), ...
    'site',fullfile(dirPath,'path_summary','oos_stage_site_summary.csv'),'hour',fullfile(dirPath,'hourly_site','oos_hour_site.csv'), ...
    'system',fullfile(dirPath,'grid_hourly','oos_hour_system.csv'),'flow',fullfile(dirPath,'htt_od','oos_positive_htt_flows.csv'));
end
function append_table(path,T,first),if isempty(T),return;end;if first,safe_writetable(T,path);else,writetable(T,path,'WriteMode','append','WriteVariableNames',false);end,end
function safe_writetable(T,path),[d,n,e]=fileparts(path);tmp=fullfile(d,[n '.tmp' e]);writetable(T,tmp);movefile(tmp,path,'f');end
function assert_arm(arm),if ~ismember(arm,["P1000","P1500"]),error('Stage89Q:Arm','Arm must be P1000 or P1500.');end,end
function [label,penalty]=arm_spec(arm),assert_arm(arm);if arm=="P1000",label="Arm-A";penalty=1000;else,label="Arm-B";penalty=1500;end,end
function assert_both_training_gate(outDir)
file=fullfile(outDir,'BOTH_TRAININGS_COMPLETE.txt');if ~isfile(file)||~contains(string(fileread(file)),"BOTH_TRAININGS_COMPLETE=true")
    error('Stage89Q:TrainingGate','Both training completion gate is not true.');end
end
function p=run_dir(rootDir,runId),p=fullfile(rootDir,'results','task-002-stage2b-b3-smoke','stage89q-penalty1000-vs1500-long-training',runId);end
function id=run_id(outDir),[~,id]=fileparts(outDir);end
function p=training_dir(outDir,arm),[~,penalty]=arm_spec(arm);p=fullfile(outDir,'02_training',sprintf('penalty%d',penalty));end
function p=oos_dir(rootDir,outDir,arm),[~,penalty]=arm_spec(arm);p=fullfile(large_run_dir(rootDir,run_id(outDir)),sprintf('penalty%d',penalty));end
function p=checkpoint_path(rootDir,outDir,arm),p=fullfile(oos_dir(rootDir,outDir,arm),'checkpoint','checkpoint_final.mat');end
function p=large_run_dir(rootDir,runId),p=fullfile(rootDir,'hourly_grid_h2','output','stage89q_penalty1000_vs1500_long_training',runId);end
function p=accepted_bank_path(rootDir),p=fullfile(rootDir,'results','task-002-stage2b-b3-smoke','89H-stage85r-single-loc4-stage88-dro-gap1000-10iter-oos10000','run-003','oos','loc4','oos_path_bank.mat');end
function make_dirs(rootDir,outDir,runId)
dirs={'00_identity','01_config','02_training/penalty1000','02_training/penalty1500','03_oos/common','03_oos/penalty1000','03_oos/penalty1500','04_qa','05_analysis','06_figures','07_manifests','08_release','logs'};
mkdir(outDir);for i=1:numel(dirs),mkdir(fullfile(outDir,dirs{i}));end
largeRoot=large_run_dir(rootDir,runId);largeDirs={'common','penalty1000/checkpoint','penalty1000/hourly_site','penalty1000/htt_od','penalty1000/grid_hourly','penalty1000/stage7_inventory','penalty1000/path_summary','penalty1500/checkpoint','penalty1500/hourly_site','penalty1500/htt_od','penalty1500/grid_hourly','penalty1500/stage7_inventory','penalty1500/path_summary'};
mkdir(largeRoot);for i=1:numel(largeDirs),mkdir(fullfile(largeRoot,largeDirs{i}));end
end
function h=sha256_file(path)
escaped=strrep(char(path),'"','\"');command=sprintf('certutil -hashfile "%s" SHA256',escaped);
[status,output]=system(command);tokens=regexp(output,'[0-9A-Fa-f]{64}','match');
if status~=0||numel(tokens)~=1,error('Stage89Q:Hash','Cannot hash %s.',path);end
h=lower(string(tokens{1}));
end
function write_status(outDir,status,phase,arm,count,elapsed,pid,commit)
txt=sprintf('STATUS=%s\nPHASE=%s\nARM=%s\nCOUNT=%d\nELAPSED_S=%.12g\nMATLAB_PID=%d\nFROZEN_COMMIT=%s\nUPDATED_AT=%s\n', ...
    status,phase,arm,count,elapsed,pid,commit,string(datetime('now','Format','yyyy-MM-dd HH:mm:ss')));
tmp=fullfile(outDir,'RUNNING_STATUS.tmp');write_text(tmp,txt);movefile(tmp,fullfile(outDir,'RUNNING_STATUS.txt'),'f');
end
function write_text(path,text),fid=fopen(path,'w');if fid<0,error('Stage89Q:Write','%s',path);end;c=onCleanup(@()fclose(fid));fprintf(fid,'%s',char(text));end %#ok<NASGU>
function v=ternary(c,a,b),if c,v=a;else,v=b;end,end

function n=training_names(),n={'arm','penalty','iteration','budget_s','elapsed_seconds','lower_bound','lower_bound_increment','forward_sampled_objective','cuts_before','cut_count','cuts_added','forward_stage_solve_count','backward_cut_solve_count','forward_time_s','backward_time_s','iteration_wall_time_s','cut_violation_flag','warning_id','warning_message','training_identity','convergence_scope','stage1_total_production','stage1_site1_production','stage1_site2_production','stage1_site3_production','stage1_site4_production','stage1_end_inventory_total','stage2_end_inventory_total','stage3_end_inventory_total'};end
function n=path_names(),n={'arm','penalty','path_id','state_sequence','termination_type','termination_stage','termination_state','operating_stage_count','reached_stage7','physical_dissipation_a1','lf8_absorbing','reported_objective','actual_operating_cost','holding_cost','production_cost','electricity_cost','production_om_cost','ordinary_shortage_total','ordinary_shortage_any','ordinary_shortage_cost','total_H2_production','total_HTT','HTT_cost','terminal_inventory_total','inventory_site1','inventory_site2','inventory_site3','inventory_site4','terminal_state_id','terminal_a','terminal_loc','target_site1','target_site2','target_site3','target_site4','target_total','gap_site1','gap_site2','gap_site3','gap_site4','terminal_site_gap','terminal_total_quantity_shortfall','terminal_spatial_component','terminal_gap_any','terminal_gap_class','surplus_site1','surplus_site2','surplus_site3','surplus_site4','terminal_penalty_cost','final_a','final_loc','final_lf'};end
function n=stage_names(),n={'arm','penalty','path_id','stage','state_id','a','loc','lf','beta','stage_objective_yuan','production_electricity_cost_yuan','grid_cost_yuan','production_om_cost_yuan','holding_cost_yuan','ordinary_shortage_kg','ordinary_shortage_cost_yuan','production_kg','htt_kg','htt_cost_yuan','beginning_inventory_kg','ending_inventory_kg','future_value_theta'};end
function n=stage_site_names(),n={'arm','penalty','path_id','stage','state_id','a','loc','lf','beta','site','beginning_inventory_kg','ordinary_demand_kg','served_demand_kg','shortage_kg','production_kg','htt_in_kg','htt_out_kg','ending_inventory_kg'};end
function n=hour_site_names(),n={'arm','penalty','path_id','stage','state_id','hurricane_a','hurricane_loc','hurricane_lf','beta','hour_in_stage','global_hour','site','electrical_bus','tariff_yuan_per_kwh','ordinary_demand_kg','ordinary_served_kg','ordinary_shortage_kg','H2_production_kg','P_EL_kW','pv_available_kw','pv_used_kw','root_grid_import','site_voltage_pu','begin_inventory_kg','inventory_before_HTT_kg','end_inventory_kg','HTT_in_kg','HTT_out_kg','begin_inventory_source','inventory_before_HTT_source','end_inventory_source','electrolyzer_capacity_binding','storage_capacity_binding'};end
function n=hour_system_names(),n={'arm','penalty','path_id','stage','state_id','hurricane_a','hurricane_loc','hurricane_lf','beta','hour_in_stage','global_hour','tariff_yuan_per_kwh','total_P_EL_kW','pv_available_kw','pv_used_kw','root_grid_import','min_voltage_pu','min_voltage_bus','max_line_mva','max_line_id','max_line_from','max_line_to','max_line_loading_pct','grid_or_electrolyzer_binding_flag','total_HTT_kg','fleet_capacity_kg','fleet_utilization','fleet_capacity_binding'};end
function n=flow_names(),n={'arm','penalty','path_id','stage','state_id','hurricane_a','hurricane_loc','hurricane_lf','beta','hour_in_stage','global_hour','origin_site','destination_site','flow_kg','distance_km','unit_cost_yuan_per_kg','htt_cost_yuan','lt5','lt10','source_inventory_pre_htt_kg','source_ending_inventory_kg','destination_inventory_pre_htt_kg','destination_ending_inventory_kg','destination_demand_kg','destination_served_kg','destination_shortage_kg','source_production_kg','fleet_capacity_kg','total_hour_htt_kg','fleet_capacity_binding'};end
