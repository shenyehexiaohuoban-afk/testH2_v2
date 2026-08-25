function run_stage89q_pmax_dual_2p5h_10k_oos_h2()
%RUN_STAGE89Q_PMAX_DUAL_2P5H_10K_OOS_H2 Fresh candidate training and OOS.

rootDir=fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(rootDir);addpath(fullfile(rootDir,'fa_h2'));
addpath(fullfile(rootDir,'fa_h2','fuzhu'));addpath(fullfile(rootDir,'utils'));
addpath(fullfile(rootDir,'hourly_grid_h2'));
addpath(fullfile(rootDir,'fa_msp','current_hourly_stage88_candidate','config'));
addpath(fullfile(rootDir,'fa_msp','current_hourly_stage88_candidate','input'));
addpath(fullfile(rootDir,'terminalLoh_wdro','current_w_mainline_stage89','msp_bridge'));
outDir=char(strtrim(string(getenv('STAGE89Q_PMAX_LONG_RUN_DIR'))));
commit=strtrim(string(getenv('STAGE89Q_PMAX_LONG_FROZEN_COMMIT')));
phase=upper(strtrim(string(getenv('STAGE89Q_PMAX_LONG_PHASE'))));
arm=upper(strtrim(string(getenv('STAGE89Q_PMAX_LONG_ARM'))));
pmaxText=strtrim(string(getenv('STAGE89Q_PMAX_LONG_VECTOR')));
if commit==""||phase=="",error('Stage89Q:Environment','Frozen commit and phase are required.');end
[st,head]=system('git rev-parse HEAD');head=strtrim(string(head));
if st~=0||head~=commit,error('Stage89Q:Commit','HEAD %s != frozen %s.',head,commit);end
if isempty(outDir),error('Stage89Q:Environment','Run directory is required.');end
try
    run_phase(rootDir,outDir,commit,phase,arm,pmaxText);
catch ME
    if isfolder(outDir)
        write_text(fullfile(outDir,'FAILURE.txt'),string(getReport(ME,'extended','hyperlinks','off')));
        write_status(outDir,'FAILED',phase,arm,0,0,feature('getpid'),commit);
    end
    rethrow(ME);
end
end

function run_phase(rootDir,outDir,commit,phase,arm,pmaxText)
pid=feature('getpid');
if ~isfolder(outDir),error('Stage89Q:NotInitialized','Run is not initialized.');end
if ismember(phase,["BASE_IDENTITY","BANK"])
    logFile=fullfile(outDir,'01_preflight',char(lower(phase)+"_matlab.log"));
else
    assert_arm(arm);[~,~,trainDir,oosDir]=arm_spec(outDir,arm,pmaxText);
    if phase=="OOS",logFile=fullfile(oosDir,'qa','oos_matlab.log');
    else,logFile=fullfile(trainDir,'monitor',char(lower(phase)+"_matlab.log"));end
end
diary(logFile);cleanup=onCleanup(@()diary('off')); %#ok<NASGU>
if phase=="BASE_IDENTITY",run_base_identity(rootDir,outDir,commit);return;end
if phase=="CONFIG",run_config(rootDir,outDir,arm,pmaxText,commit);return;end
if phase=="TRAIN",train_arm(rootDir,outDir,arm,pmaxText,commit,pid);return;end
if phase=="RELOAD",run_reload(rootDir,outDir,arm,pmaxText,commit);return;end
if phase=="BANK",build_oos_bank(rootDir,outDir,commit,pid);return;end
if phase=="OOS",evaluate_arm_oos(rootDir,outDir,arm,pmaxText,commit,pid);return;end
error('Stage89Q:Phase','Unknown phase %s.',phase);
end

function run_base_identity(rootDir,outDir,commit)
[p,opts]=load_params(rootDir);assert_base_identity(p,opts);
lib=define_models_h2(p);assert_library(lib,p);assert_model_pmax(lib,p.el_cap_kw,p,'Base identity');
rows={
    'dt_h',string(p.dt_h),'8',p.dt_h==8;
    'operating_stages',string(p.hourly_grid.n_operating_stages),'6',p.hourly_grid.n_operating_stages==6;
    'hours_per_stage',string(p.hourly_grid.hours_per_stage),'8',p.hourly_grid.hours_per_stage==8;
    'stage7_count',string(nnz(p.is_loh_demand_stage)),'35',nnz(p.is_loh_demand_stage)==35;
    'stage8_absorbing',string(all(p.is_absorbing(p.S(:,3)==8))),'true',all(p.is_absorbing(p.S(:,3)==8));
    'tank_capacity',string(mat2str(p.x_cap.')),'[300 200 100 200]',isequal(p.x_cap(:).',[300 200 100 200]);
    'ordinary_demand',string(p.demand_schema),'original-hourly-24h-repeat-v1',string(p.demand_schema)=="original-hourly-24h-repeat-v1";
    'htt_capacity',string(p.htt_capacity_base),'160',p.htt_capacity_base==160;
    'terminal_gap_penalty',string(p.cost_reserve_shortage),'1000',p.cost_reserve_shortage==1000;
    'base_pmax',string(mat2str(p.el_cap_kw.')),'[300 200 120 150]',isequal(p.el_cap_kw(:).',[300 200 120 150]);
    'training_seed',string(opts.seed),'20260513',opts.seed==20260513;
    'terminal_loh_sha256',string(p.terminal_loh_lookup_audit.source_sha256),'2fa195...eaa8',string(p.terminal_loh_lookup_audit.source_sha256)=="2fa1958944110701239a109ebf46d959324a351f2f27c1c3fbd62f333066eaa8";
    'voltage_bounds',string(sprintf('%.2f..%.2f',p.hourly_grid.vmin_pu,p.hourly_grid.vmax_pu)),'0.90..1.10',p.hourly_grid.vmin_pu==0.90&&p.hourly_grid.vmax_pu==1.10;
    'branch_limit_mva',string(p.hourly_grid.branch_smax_mva),'6',p.hourly_grid.branch_smax_mva==6;
    'source_commit',string(commit),string(commit),true};
T=cell2table(rows,'VariableNames',{'check','observed','expected','pass'});
safe_writetable(T,fullfile(outDir,'01_preflight','current_model_identity_gate.csv'));
if ~all(T.pass),error('Stage89Q:Identity','Base identity gate failed.');end
write_text(fullfile(outDir,'01_preflight','BASE_IDENTITY_PASS.txt'),sprintf('status=PASS\nhead=%s\n',commit));
clear lib p
end

function run_config(rootDir,outDir,arm,pmaxText,commit)
[candidate,pmax,trainDir,~]=arm_spec(outDir,arm,pmaxText);
[p,opts,baseP,baseOpts]=load_candidate(rootDir,candidate,pmax);
lib=define_models_h2(p);assert_library(lib,p);assert_zero_cuts(lib,p);assert_model_pmax(lib,pmax,p,'config');
assert_parameter_isolation(baseP,baseOpts,p,opts,candidate,pmax,trainDir);
write_propagation(trainDir,candidate,pmax,p,lib,[],"CONFIG_PASS");
T=table(candidate,string(mat2str(pmax.')),1000,opts.seed,9000,string(commit),string(p.terminal_loh_lookup_audit.source_sha256), ...
    'VariableNames',{'candidate_id','Pmax_kw','terminal_gap_penalty','training_seed','budget_s','source_commit','TerminalLOH_sha256'});
safe_writetable(T,fullfile(trainDir,'config','candidate_config.csv'));
write_text(fullfile(trainDir,'config','CONFIG_PASS.txt'),sprintf('candidate=%s\npmax=%s\nfresh_initial_cuts=0\n',candidate,mat2str(pmax.')));
clear lib p baseP
end

function run_reload(~,outDir,arm,pmaxText,commit)
[candidate,pmax,trainDir,~]=arm_spec(outDir,arm,pmaxText);checkpoint=fullfile(trainDir,'checkpoint','checkpoint_final.mat');
expectedSha=lower(strtrim(string(getenv('STAGE89Q_PMAX_LONG_CHECKPOINT_SHA256'))));
if strlength(expectedSha)~=64||sha256_file(checkpoint)~=expectedSha,error('Stage89Q:ReloadHash','External checkpoint hash failed.');end
v=whos('-file',checkpoint);required={'params','modelLib','state','policy','opts','rng_state','checkpoint_metadata'};
if ~all(ismember(required,{v.name})),error('Stage89Q:CheckpointSchema','Checkpoint variables missing.');end
z=load(checkpoint);p=z.params;lib=z.modelLib;m=z.checkpoint_metadata;
checks=[string(m.stage)=="89Q-Pmax-LONG";string(m.arm_label)==candidate;isequal(m.candidate_pmax_kw(:),pmax); ...
    isequal(p.el_cap_kw(:),pmax);isequal(p.hourly_grid.pmax_kw(:),pmax);m.terminal_gap_penalty_yuan_per_kg==1000; ...
    m.training_seed==20260513;m.training_budget_s==9000;m.training_wall_time_s>=9000;m.fresh_initial_cut_count==0; ...
    string(m.warm_start_checkpoint)=="NONE";string(m.frozen_commit)==string(commit);cut_count(lib,p)==m.cumulative_cuts];
assert_model_pmax(lib,pmax,p,'clean reload');pm=update_rhs_h2(lib.models{1,p.k_init},p,p.k_init,1,p.x_0);s=solve_stage_model_h2(pm);
checks(end+1)=all(isfinite(s.xraw));names={'stage','candidate','metadata_pmax','params_pmax','grid_pmax','penalty','seed','budget','wallclock','zero_cuts','no_warm_start','commit','cut_count','minimal_solve'};
T=table(string(names(:)),checks(:),repmat(expectedSha,numel(checks),1),'VariableNames',{'check','pass','checkpoint_sha256'});
safe_writetable(T,fullfile(trainDir,'acceptance','checkpoint_reload_audit.csv'));
if ~all(checks),error('Stage89Q:ReloadIdentity','Reload identity failed.');end
write_propagation(trainDir,candidate,pmax,p,lib,m,"RELOAD_PASS");
write_text(fullfile(trainDir,'acceptance','RELOAD_PASS.txt'),sprintf('candidate=%s\nsha256=%s\nstatus=PASS\n',candidate,expectedSha));
clear z lib p
end

function train_arm(rootDir,outDir,arm,pmaxText,commit,pid)
[label,pmax,caseDir,~]=arm_spec(outDir,arm,pmaxText);shortage=200;checkpoint=fullfile(caseDir,'checkpoint','checkpoint_final.mat');
tracePath=fullfile(caseDir,'iteration_trace','training_progress.csv');
if isfile(checkpoint)||isfile(tracePath)
    error('Stage89Q:TrainingExists','Refusing to overwrite training for %s.',label);
end
[p,opts]=load_candidate(rootDir,label,pmax);rng(opts.seed,'twister');
lib=define_models_h2(p);assert_library(lib,p);initialCuts=cut_count(lib,p);
if initialCuts~=0,error('Stage89Q:WarmStart','%s did not start with zero cuts.',label);end
x=zeros(p.Ni,p.T);theta=zeros(p.T,1);lb=0;LB=zeros(0,1);rows=cell(0,29);
budget=9000;started=tic;iter=0;totalForward=0;totalBackward=0;warningCount=0;
write_status(outDir,'RUNNING','TRAIN',arm,0,0,pid,commit);
while iter==0||toc(started)<budget
    iter=iter+1;iterStart=tic;beforeRows=model_row_counts(lib,p);before=sum(max(0,beforeRows-base_rows(p)),'all');
    lastwarn('');f0=tic;[lib,x,theta,lb,path,fwd]=forward_pass_h2(lib,p,lb,x,theta);forwardTime=toc(f0);
    assert_model_pmax(lib,pmax,p,sprintf('forward iteration %d',iter));
    valid=all(ismember(fwd.status,["normal","loh_demand_stage","absorbing_lfNc","dissipated_absorb","post_absorb"]));
    if ~valid||~isfinite(lb)||any(~isfinite(x),'all'),error('Stage89Q:Forward','%s iteration %d failed.',label,iter);end
    b0=tic;[lib,cutFlag]=backward_pass_h2(lib,p,x,theta,path);backwardTime=toc(b0);
    assert_model_pmax(lib,pmax,p,sprintf('backward iteration %d',iter));
    afterRows=model_row_counts(lib,p);after=sum(max(0,afterRows-base_rows(p)),'all');
    newAudit=audit_new_cuts(lib,p,beforeRows,afterRows);
    if ~newAudit.pass||after<=before,error('Stage89Q:Cuts','%s iteration %d cut audit failed.',label,iter);end
    LB(iter,1)=lb;if iter==1,delta=NaN;else,delta=LB(iter)-LB(iter-1);end
    [warningMessage,warningId]=lastwarn;if strlength(string(warningId))>0,warningCount=warningCount+1;end
    totalForward=totalForward+nnz(fwd.status=="normal");totalBackward=totalBackward+(after-before);
    policyModel=update_rhs_h2(modelLib_at(lib,1,p.k_init),p,p.k_init,1,p.x_0);policySol=solve_stage_model_h2(policyModel);
    stage1SiteProd=sum(policySol.h2_production_hourly_kg,2);stage1Prod=sum(stage1SiteProd);
    rows(end+1,:)={label,1000,iter,budget,toc(started),lb,delta,sum(fwd.stageCost),before,after,after-before, ...
        nnz(fwd.status=="normal"),after-before,forwardTime,backwardTime,toc(iterStart),cutFlag, ...
        string(warningId),string(warningMessage),"FIXED_2P5H_BUDGET_TRAINING","NOT_CONVERGENCE_CERTIFICATE", ...
        stage1Prod,stage1SiteProd(1),stage1SiteProd(2),stage1SiteProd(3),stage1SiteProd(4),sum(x(:,1)),sum(x(:,2)),sum(x(:,3))}; %#ok<AGROW>
    safe_writetable(cell2table(rows,'VariableNames',training_names()),tracePath);
    write_status(outDir,'RUNNING','TRAIN',arm,iter,toc(started),pid,commit);
    fprintf('Stage89Q %s iter=%d elapsed=%.3f LB=%.12g cuts=%d\n',label,iter,toc(started),lb,after);
end
trainingWall=toc(started);fullAudit=audit_all_cuts(lib,p);
if ~fullAudit.pass,error('Stage89Q:FinalCutAudit','%s full cut audit failed.',label);end
[stageT,siteT,hourT,gridT,diagSummary]=diagnose_reference_path(lib,p,label);
safe_writetable(stageT,fullfile(caseDir,'stage_site','stage_diagnostics.csv'));
safe_writetable(siteT,fullfile(caseDir,'stage_site','stage_site_diagnostics.csv'));
safe_writetable(hourT,fullfile(caseDir,'stage_site','hour_site_diagnostics.csv'));
safe_writetable(gridT,fullfile(caseDir,'grid','hour_grid_diagnostics.csv'));
safe_writetable(diagSummary,fullfile(caseDir,'stage_site','reference_path_summary.csv'));
model=first_operating_model(lib,p);finalCuts=cut_count(lib,p);
checkpoint_metadata=struct('stage','89Q-Pmax-LONG','arm',char(arm),'arm_label',char(label), ...
    'candidate_pmax_kw',pmax(:),'terminal_gap_penalty_yuan_per_kg',1000,'shortage_penalty_yuan_per_kg',shortage, ...
    'htt_c0_yuan_per_kg',p.htt_base_service_cost_yuan_per_kg,'htt_cost_base_matrix',p.cost_transport_base, ...
    'beta_multiplier',2,'fleet_cap_kg_per_h',160,'eta',0.03, ...
    'demand_schema','original-hourly-24h-repeat-v1','training_seed',opts.seed, ...
    'training_budget_s',budget,'training_wall_time_s',trainingWall,'completed_iterations',iter, ...
    'final_LB',LB(end),'fresh_initial_cut_count',initialCuts,'cumulative_cuts',finalCuts, ...
    'state_dimension',4,'state_order','Site1,Site2,Site3,Site4','variable_count',model.nvars, ...
    'base_inequality_count',base_rows(p),'equality_count',size(model.Aeq,1),'integer_count',0, ...
    'terminal_lookup_sha256',char(opts.terminal_loh_expected_sha256),'model_schema','hourly-h2-hourly-htt-v1', ...
    'training_identity','FIXED_2P5H_BUDGET_TRAINING','convergence_scope','NOT_CONVERGENCE_CERTIFICATE', ...
    'warm_start_checkpoint','NONE','cross_arm_cut_source','NONE','frozen_commit',char(commit));
params=p;modelLib=lib;state=struct('x',x,'theta',theta,'lb',lb,'LB',LB); %#ok<NASGU>
policy=struct('representation','modelLib_with_embedded_cuts','state_order','Site1,Site2,Site3,Site4', ...
    'classification','STAGE89Q_PMAX_FIXED_2P5H_POLICY','candidate_id',char(label),'candidate_pmax_kw',pmax(:));rng_state=rng; %#ok<NASGU>
save_checkpoint_safe(checkpoint,params,modelLib,state,policy,opts,rng_state,checkpoint_metadata);
info=dir(checkpoint);summary=table(label,1000,shortage,p.htt_base_service_cost_yuan_per_kg,2,0.03,opts.seed,budget,trainingWall,iter, ...
    LB(end),finalCuts,totalForward,totalBackward,warningCount,0,initialCuts,string(checkpoint), ...
    info.bytes,fullAudit.pass,"FIXED_2P5H_BUDGET_TRAINING","NOT_CONVERGENCE_CERTIFICATE",stage1Prod,string(mat2str(pmax.')), ...
    'VariableNames',{'arm','terminal_gap_penalty_yuan_per_kg','shortage_penalty_yuan_per_kg','c0_yuan_per_kg', ...
    'beta_multiplier','eta','training_seed','budget_s','actual_training_wall_time_s','completed_iterations', ...
    'final_LB','cumulative_cuts','forward_operating_solves','backward_cut_solves','warning_count','error_count', ...
    'fresh_initial_cuts','checkpoint_path','checkpoint_bytes','full_cut_audit_pass', ...
    'training_identity','convergence_scope','final_stage1_production_kg','Pmax_kw'});
safe_writetable(summary,fullfile(caseDir,'acceptance','training_summary.csv'));
write_propagation(caseDir,label,pmax,p,lib,checkpoint_metadata,"TRAIN_PASS");
write_text(fullfile(caseDir,'acceptance','TRAINING_FINISHED.txt'),sprintf('%s_TRAINING_FINISHED=true\n',label));
write_status(outDir,'RUNNING','TRAIN_FINISHED',arm,iter,trainingWall,pid,commit);
clear modelLib lib params p
end

function build_oos_bank(rootDir,outDir,commit,pid,requireBothTraining)
if nargin<5,requireBothTraining=true;end
if requireBothTraining && ~exploratory_b0001_oos_enabled()
    assert_both_training_gate(outDir);
elseif requireBothTraining
    write_text(fullfile(outDir,'EXPLORATORY_B0001_OOS_OVERRIDE.txt'), ...
        "Exploratory B0001-only OOS: formal both-training acceptance gate intentionally bypassed."+newline);
end
bankDir=fullfile(outDir,'01_preflight','common_bank');
bankFile=accepted_bank_path(rootDir);expectedSha="6bf3d1190a402ded052b8d3d08ed369042236e151f562bdd9fd4db7b8ff386c6";
if sha256_file(bankFile)~=expectedSha,error('Stage89Q:BankIdentity','Accepted bank SHA mismatch.');end
[p,~]=load_params(rootDir);b=load(bankFile,'pathBank','seed');pathBank=double(b.pathBank);seed=double(b.seed);n=size(pathBank,1);
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

function evaluate_arm_oos(rootDir,outDir,arm,pmaxText,commit,pid)
if ~(arm=="B0001" && exploratory_b0001_oos_enabled())
    assert_both_training_gate(outDir);
else
    write_text(fullfile(outDir,'EXPLORATORY_B0001_OOS_OVERRIDE.txt'), ...
        "Exploratory B0001-only OOS: B0001 training stability acceptance was not passed."+newline);
end
[label,pmax,trainDir,oosDir]=arm_spec(outDir,arm,pmaxText);penalty=1000;shortage=200;
if isfile(fullfile(oosDir,'oos_metadata.csv')),error('Stage89Q:OOSExists','OOS exists for %s.',label);end
bankFile=accepted_bank_path(rootDir);bankIdentity=readtable(fullfile(outDir,'01_preflight','common_bank','bank_identity.csv'),'TextType','string');
if ~isfile(bankFile)||height(bankIdentity)~=1||bankIdentity.path_count~=10000||sha256_file(bankFile)~=bankIdentity.bank_sha256
    error('Stage89Q:BankGate','Locked common bank failed for %s.',label);
end
b=load(bankFile,'pathBank');pathBank=double(b.pathBank);
checkpoint=fullfile(trainDir,'checkpoint','checkpoint_final.mat');
checkpointHashBefore=lower(strtrim(string(getenv('STAGE89Q_PMAX_LONG_CHECKPOINT_SHA256'))));
if strlength(checkpointHashBefore)~=64,error('Stage89Q:ExternalHash','External checkpoint SHA-256 is required.');end
if sha256_file(checkpoint)~=checkpointHashBefore,error('Stage89Q:ExternalHash','Checkpoint SHA mismatch before clean load.');end
loaded=load(checkpoint);p=loaded.params;lib=loaded.modelLib;m=loaded.checkpoint_metadata;clear loaded
if string(m.stage)~="89Q-Pmax-LONG"||string(m.arm_label)~=label||~isequal(m.candidate_pmax_kw(:),pmax)|| ...
        m.terminal_gap_penalty_yuan_per_kg~=penalty||m.shortage_penalty_yuan_per_kg~=shortage|| ...
        m.training_seed~=20260513||m.training_budget_s~=9000||m.training_wall_time_s<9000|| ...
        m.fresh_initial_cut_count~=0||string(m.warm_start_checkpoint)~="NONE"|| ...
        m.cumulative_cuts~=cut_count(lib,p)||p.cost_reserve_shortage~=penalty||p.cost_normal_shortage~=200|| ...
        ~isequal(p.el_cap_kw(:),pmax)||~isequal(p.hourly_grid.pmax_kw(:),pmax)
    error('Stage89Q:PolicyIdentity','Policy identity failed for %s.',label);
end
assert_model_pmax(lib,pmax,p,'OOS policy identity');
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
cutsAfter=cut_count(lib,p);write_propagation(trainDir,label,pmax,p,lib,m,"OOS_PASS");clear lib p pathBank
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

function [stageT,siteT,hourT,gridT,summaryT]=diagnose_reference_path(lib,p,candidate)
prev=p.x_0(:);stageRows=cell(6,15);siteRows=cell(24,20);hourRows=cell(192,24);gridRows=cell(48,18);
sr=0;rr=0;hr=0;gr=0;
for t=1:6
    k=p.k_init;m=update_rhs_h2(lib.models{t,k},p,k,t,prev);s=solve_stage_model_h2(m);
    eq=max(abs(m.Aeq*s.xraw-m.beq));ineq=max([0;m.A*s.xraw-m.b]);
    if any(~isfinite(s.xraw))||eq>1e-6||ineq>1e-6,error('Stage89Q:Diagnostic','Reference diagnostic failed.');end
    v=sqrt(max(s.v_sq,0));trueS=hypot(s.p_branch_kw,s.q_branch_kvar)/1000;
    production=sum(s.h2_production_hourly_kg,'all');shortage=sum(s.z_normal_hourly_kg,'all');flow=s.f_hourly_kg;
    sr=sr+1;stageRows(sr,:)={candidate,t,k,sum(prev),sum(s.xval),production,shortage,sum(flow,'all'), ...
        sum(s.p_el_hourly_kw,'all')/(8*sum(p.el_cap_kw)),mean(s.xval./p.x_cap),min(v,[],'all'), ...
        max(trueS,[],'all')/p.hourly_grid.branch_smax_mva,max(s.p_grid_kw)/p.hourly_grid.p_substation_max_kw, ...
        sum(s.p_el_hourly_kw(:,1:4),'all')/max(sum(s.p_el_hourly_kw,'all'),eps), ...
        sum(s.p_el_hourly_kw(:,5:8),'all')/max(sum(s.p_el_hourly_kw,'all'),eps)};
    for i=1:4
        rr=rr+1;pel=s.p_el_hourly_kw(i,:);inv=s.h2_inventory_hourly_kg(i,:);
        siteRows(rr,:)={candidate,t,i,p.el_cap_kw(i),sum(pel),mean(pel)/p.el_cap_kw(i),max(pel), ...
            sum(pel>=0.90*p.el_cap_kw(i)),sum(pel>=0.95*p.el_cap_kw(i)),sum(pel>=0.99*p.el_cap_kw(i)), ...
            sum(s.h2_production_hourly_kg(i,:)),prev(i),s.xval(i),sum(s.z_normal_hourly_kg(i,:)), ...
            sum(s.htt_in_hourly_kg(i,:)),sum(s.htt_out_hourly_kg(i,:)),p.x_cap(i)-s.xval(i), ...
            sum(inv>=p.x_cap(i)-1e-6),sum(inv>=0.99*p.x_cap(i)),std(pel)};
        for h=1:8
            hr=hr+1;beginInv=prev(i);if h>1,beginInv=s.h2_inventory_hourly_kg(i,h-1);end
            hourRows(hr,:)={candidate,t,h,8*(t-1)+h,i,p.hourly_grid.site_elec_bus(i),p.el_cap_kw(i), ...
                s.p_el_hourly_kw(i,h),s.p_el_hourly_kw(i,h)/p.el_cap_kw(i),s.h2_production_hourly_kg(i,h), ...
                beginInv,s.h2_inventory_pre_htt_kg(i,h),s.h2_inventory_hourly_kg(i,h),p.x_cap(i), ...
                p.x_cap(i)-s.h2_inventory_hourly_kg(i,h),s.h2_demand_hourly_kg(i,h), ...
                s.u_normal_hourly_kg(i,h),s.z_normal_hourly_kg(i,h),s.htt_in_hourly_kg(i,h), ...
                s.htt_out_hourly_kg(i,h),sqrt(max(s.v_sq(p.hourly_grid.site_elec_bus(i),h),0)), ...
                s.p_el_hourly_kw(i,h)>=0.90*p.el_cap_kw(i),s.p_el_hourly_kw(i,h)>=0.99*p.el_cap_kw(i), ...
                s.h2_inventory_hourly_kg(i,h)>=p.x_cap(i)-1e-6};
        end
    end
    for h=1:8
        gr=gr+1;[vmin,bus]=min(v(:,h));[lineMva,line]=max(trueS(:,h));grFlow=sum(flow(:,:,h),'all');cap=max(0,(1-p.beta(k))*p.htt_capacity_base);
        gridRows(gr,:)={candidate,t,h,8*(t-1)+h,vmin,bus,v(18,h),vmin<=p.hourly_grid.vmin_pu+1e-6, ...
            lineMva,line,lineMva/p.hourly_grid.branch_smax_mva,lineMva>=p.hourly_grid.branch_smax_mva-1e-6, ...
            s.p_grid_kw(h),s.p_grid_kw(h)/p.hourly_grid.p_substation_max_kw,s.p_grid_kw(h)>=p.hourly_grid.p_substation_max_kw-1e-6, ...
            grFlow,cap,ternary(cap>0,grFlow/cap,0)};
    end
    prev=s.xval;
end
stageT=cell2table(stageRows,'VariableNames',{'candidate','stage','state_id','begin_inventory_kg','end_inventory_kg','production_kg','ordinary_shortage_kg','HTT_kg','Pmax_utilization','tank_fill_mean','Vmin_pu','max_line_utilization','max_substation_utilization','first4h_production_share','last4h_production_share'});
siteT=cell2table(siteRows,'VariableNames',{'candidate','stage','site','Pmax_kW','P_EL_kWh','mean_Pmax_utilization','max_P_EL_kW','hours_ge90pct','hours_ge95pct','hours_ge99pct','production_kg','begin_inventory_kg','end_inventory_kg','ordinary_shortage_kg','HTT_in_kg','HTT_out_kg','tank_headroom_kg','tank_capacity_hits','near_tank_capacity_hours','P_EL_std_kW'});
hourT=cell2table(hourRows,'VariableNames',{'candidate','stage','hour_in_stage','global_hour','site','bus','Pmax_kW','P_EL_kW','Pmax_utilization','production_kg','begin_inventory_kg','inventory_pre_HTT_kg','end_inventory_kg','tank_capacity_kg','tank_headroom_kg','ordinary_demand_kg','ordinary_served_kg','ordinary_shortage_kg','HTT_in_kg','HTT_out_kg','site_voltage_pu','P_EL_ge90pct','P_EL_ge99pct','tank_binding'});
gridT=cell2table(gridRows,'VariableNames',{'candidate','stage','hour_in_stage','global_hour','Vmin_pu','critical_bus','bus18_voltage_pu','voltage_binding','max_line_mva','critical_line','line_utilization','branch_binding','substation_import_kW','substation_utilization','substation_binding','HTT_kg','HTT_capacity_kg','HTT_utilization'});
summaryT=table(candidate,sum(stageT.production_kg),sum(stageT.ordinary_shortage_kg),sum(stageT.HTT_kg),sum(stageT.production_kg(stageT.stage>=5))/sum(stageT.production_kg),min(gridT.Vmin_pu),min(gridT.bus18_voltage_pu),max(gridT.line_utilization),max(gridT.substation_utilization),max(gridT.HTT_utilization), ...
    'VariableNames',{'candidate','stage1_6_production_kg','ordinary_shortage_kg','HTT_kg','late_stage5_6_share','Vmin_pu','bus18_Vmin_pu','max_line_utilization','max_substation_utilization','max_HTT_utilization'});
end

function [p,opts]=load_params(rootDir)
[p,opts,candidateAudit]=load_current_stage89_hourly_h2(rootDir,"dro");opts.seed=20260513;
opts.terminal_loh_lookup_file=char(p.terminal_loh_source);
opts.terminal_loh_expected_sha256=char(p.terminal_loh_lookup_audit.source_sha256);
p.cost_reserve_shortage=1000;p.NearStageInput.Cost.reserve_shortage_penalty_yuan_per_kg=1000;
baseState=p.k_init;initialA=p.S(baseState,1);initialLf=p.S(baseState,3);p.k_init=p.state_id(initialA,4,initialLf);
expectedX0=[58.04455704486949;50.30813793862475;25.262133442309338;33.02358084624278];
if ~candidateAudit.pass||~p.enable_hourly_grid||p.dt_h~=8||p.T~=8||p.Ni~=4|| ...
        p.S(p.k_init,1)~=initialA||p.S(p.k_init,2)~=4||p.S(p.k_init,3)~=initialLf|| ...
        p.cost_normal_shortage~=200||p.cost_reserve_shortage~=1000|| ...
        string(p.terminal_loh_mode)~="stage89k_dro"||string(p.terminal_loh_lookup_audit.table_version)~="Stage89K"|| ...
        string(p.terminal_loh_lookup_audit.source_sha256)~="2fa1958944110701239a109ebf46d959324a351f2f27c1c3fbd62f333066eaa8"|| ...
        abs(p.terminal_loh_lookup_audit.eta-0.03)>1e-12||string(p.demand_schema)~="original-hourly-24h-repeat-v1"|| ...
        p.NearStageInput.NormalDemand.stage_dt_h~=6||~isequal(p.x_cap(:).',[300 200 100 200])|| ...
        ~isequal(p.el_cap_kw(:).',[300 200 120 150])||max(abs(p.x_0-expectedX0))>1e-12|| ...
        abs(p.k_H2-0.0195)>1e-12||abs(8*p.k_H2*sum(p.el_cap_kw)-120.12)>1e-10
    error('Stage89Q:Identity','Frozen Stage89K single-loc4 parameter identity mismatch.');
end
end

function [p,opts,baseP,baseOpts]=load_candidate(rootDir,candidate,pmax)
[baseP,baseOpts]=load_params(rootDir);assert_base_identity(baseP,baseOpts);
p=baseP;opts=baseOpts;p.el_cap_kw=pmax(:);p.hourly_grid.pmax_kw=pmax(:);
p.stage89q_pmax_candidate_id=char(candidate);p.stage89q_pmax_source='launcher_environment_override';
opts.stage89q_pmax_candidate_id=char(candidate);opts.stage89q_pmax_kw=pmax(:);
if ~isequal(p.el_cap_kw(:),pmax)||~isequal(p.hourly_grid.pmax_kw(:),pmax)
    error('Stage89Q:PmaxOverride','Candidate Pmax propagation failed.');
end
end

function assert_base_identity(p,opts)
expectedX0=[58.04455704486949;50.30813793862475;25.262133442309338;33.02358084624278];
pass=p.dt_h==8&&p.T==8&&p.Ni==4&&p.hourly_grid.n_operating_stages==6&&p.hourly_grid.hours_per_stage==8&& ...
    isequal(p.x_cap(:).',[300 200 100 200])&&isequal(p.el_cap_kw(:).',[300 200 120 150])&& ...
    max(abs(p.x_0-expectedX0))<=1e-12&&string(p.demand_schema)=="original-hourly-24h-repeat-v1"&& ...
    p.hourly_h2_balance_v1&&p.hourly_htt_v1&&p.htt_capacity_base==160&&p.cost_reserve_shortage==1000&& ...
    p.cost_normal_shortage==200&&p.S(p.k_init,2)==4&&p.hourly_grid.vmin_pu==0.90&& ...
    p.hourly_grid.vmax_pu==1.10&&p.hourly_grid.branch_smax_mva==6&&opts.seed==20260513&& ...
    string(p.terminal_loh_mode)=="stage89k_dro"&&string(p.terminal_loh_lookup_audit.source_sha256)== ...
    "2fa1958944110701239a109ebf46d959324a351f2f27c1c3fbd62f333066eaa8";
if ~pass,error('Stage89Q:FormalIdentity','Formal Stage89Q Base identity mismatch.');end
end

function assert_parameter_isolation(baseP,baseOpts,p,opts,candidate,pmax,trainDir)
fields={'P_joint','P_intensity','P_location','P_landfall','S','D_normal','x_0','x_cap','beta','TerminalLOH', ...
    'cost_reserve_shortage','cost_normal_shortage','cost_holding','cost_el_om','cost_transport_base', ...
    'htt_capacity_base','beta_transport_multiplier','site_to_site_road_km'};
rows=cell(0,6);
for i=1:numel(fields)
    f=fields{i};same=isequaln(baseP.(f),p.(f));rows(end+1,:)={f,'UNCHANGED',same,'formal Base','candidate',ternary(same,'PASS','UNEXPECTED_DIFF')}; %#ok<AGROW>
end
gridFields={'tariff48','lambda48','phi48','p_load_base_kw','q_load_base_kvar','r_ohm','x_ohm', ...
    'branch_smax_mva','p_substation_max_kw','pv_cap_kw','vmin_pu','vmax_pu'};
for i=1:numel(gridFields)
    f=gridFields{i};same=isequaln(baseP.hourly_grid.(f),p.hourly_grid.(f));rows(end+1,:)={"hourly_grid."+f,'UNCHANGED',same,'formal Base','candidate',ternary(same,'PASS','UNEXPECTED_DIFF')}; %#ok<AGROW>
end
rows(end+1,:)={'Pmax','ALLOWED',isequal(p.el_cap_kw(:),pmax),mat2str(baseP.el_cap_kw.'),mat2str(pmax.'),'PASS'};
rows(end+1,:)={'training_wall_clock_budget','ALLOWED',true,'18000','9000','PASS'};
rows(end+1,:)={'output_path','ALLOWED',true,'Base accepted unchanged',trainDir,'PASS'};
rows(end+1,:)={'arm_identity','ALLOWED',string(opts.stage89q_pmax_candidate_id)==candidate,'Base',candidate,'PASS'};
T=cell2table(rows,'VariableNames',{'parameter','expected_change','pass','base','candidate','status'});
safe_writetable(T,fullfile(trainDir,'config','parameter_diff.csv'));
if ~all(T.pass)||baseOpts.seed~=opts.seed,error('Stage89Q:Isolation','Unexpected active parameter change.');end
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

function assert_zero_cuts(lib,p)
if cut_count(lib,p)~=0,error('Stage89Q:WarmStart','Fresh library contains cuts.');end
end
function assert_model_pmax(lib,pmax,p,where)
count=0;pass=true;
for t=1:6
    for k=1:p.K
        m=lib.models{t,k};if isempty(m),continue;end;count=count+1;
        pass=pass&&isequal(m.ub(m.idx.e),pmax(:))&& ...
            isequal(reshape(m.ub(m.idx.p_el_hourly),4,8),repmat(pmax(:),1,8));
    end
end
if ~pass||count==0,error('Stage89Q:ModelPmax','Pmax mismatch at %s.',where);end
end
function write_propagation(trainDir,candidate,pmax,p,lib,metadata,status)
expected=mat2str(pmax.');assert_model_pmax(lib,pmax,p,status);
rows={
    '1_long_training_launcher_override',expected,expected,true,'STAGE89Q_PMAX_LONG_VECTOR';
    '2_options_config',mat2str(opts_pmax(p,pmax).'),expected,isequal(opts_pmax(p,pmax),pmax),'candidate options';
    '3_loader_output',mat2str(p.el_cap_kw.'),expected,isequal(p.el_cap_kw(:),pmax),'formal loader then isolated override';
    '4_params_hourly_grid_pmax',mat2str(p.hourly_grid.pmax_kw.'),expected,isequal(p.hourly_grid.pmax_kw(:),pmax),'derived identity copy';
    '5_model_struct',mat2str(p.el_cap_kw.'),expected,isequal(p.el_cap_kw(:),pmax),'params model data';
    '6_actual_P_EL_upper_bounds',expected,expected,true,'all active aggregate and 4x8 hourly bounds';
    '7_forward_model',expected,expected,true,'asserted after every forward pass';
    '8_backward_model',expected,expected,true,'asserted after every backward pass';
    '9_checkpoint_metadata','PENDING',expected,false,'available after training';
    '10_result_metadata','PENDING',expected,false,'checkpoint policy metadata';
    '11_OOS_loader','PENDING',expected,false,'asserted in fresh OOS process';
    '12_OOS_policy_identity','PENDING',expected,false,'asserted in fresh OOS process'};
if ~isempty(metadata)
    rows{9,2}=mat2str(metadata.candidate_pmax_kw.');rows{9,4}=isequal(metadata.candidate_pmax_kw(:),pmax);
    rows{10,2}=expected;rows{10,4}=true;
end
if status=="OOS_PASS",rows{11,2}=expected;rows{11,4}=true;rows{12,2}=expected;rows{12,4}=true;end
T=cell2table(rows,'VariableNames',{'level','observed_Pmax_kw','expected_Pmax_kw','pass','evidence'});
safe_writetable(T,fullfile(trainDir,'qa','pmax_propagation.csv'));
if status=="OOS_PASS"&&~all(T.pass),error('Stage89Q:PmaxPropagation','Full Pmax propagation failed.');end
end
function v=opts_pmax(p,pmax),v=p.el_cap_kw(:);if ~isequal(v,pmax),error('Stage89Q:Pmax','Options Pmax mismatch.');end,end

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
function assert_arm(arm),if ~ismember(arm,["B0001","B1011"]),error('Stage89Q:Arm','Arm must be B0001 or B1011.');end,end
function [label,pmax,trainDir,oosDir]=arm_spec(outDir,arm,pmaxText)
assert_arm(arm);
if arm=="B0001",label="ARM-B0001";expected=[300;200;120;187.5];trainFolder='02_training_b0001';oosFolder='04_oos_b0001';
else,label="ARM-B1011";expected=[375;200;150;187.5];trainFolder='03_training_b1011';oosFolder='05_oos_b1011';end
pmax=str2double(split(pmaxText,','));pmax=pmax(:);
if numel(pmax)~=4||any(~isfinite(pmax))||~isequal(pmax,expected)
    error('Stage89Q:ArmPmax','Arm %s expected %s, got %s.',arm,mat2str(expected.'),pmaxText);
end
trainDir=fullfile(outDir,trainFolder);oosDir=fullfile(outDir,oosFolder);
end
function assert_both_training_gate(outDir)
file=fullfile(outDir,'BOTH_TRAININGS_COMPLETE.txt');if ~isfile(file)||~contains(string(fileread(file)),"BOTH_TRAININGS_COMPLETE=true")
    error('Stage89Q:TrainingGate','Both training completion gate is not true.');end
end
function tf=exploratory_b0001_oos_enabled()
tf=strcmpi(strtrim(getenv('STAGE89Q_PMAX_EXPLORATORY_B0001_OOS')),'1') && ...
    strcmpi(strtrim(getenv('STAGE89Q_PMAX_LONG_ARM')),'B0001');
end
function p=accepted_bank_path(rootDir),p=fullfile(rootDir,'results','task-002-stage2b-b3-smoke','89H-stage85r-single-loc4-stage88-dro-gap1000-10iter-oos10000','run-003','oos','loc4','oos_path_bank.mat');end
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
