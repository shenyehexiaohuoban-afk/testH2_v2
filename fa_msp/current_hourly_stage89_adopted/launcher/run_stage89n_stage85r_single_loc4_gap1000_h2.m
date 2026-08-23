function run_stage89n_stage85r_single_loc4_gap1000_h2()
%RUN_STAGE89N_STAGE85R_SINGLE_LOC4_GAP1000_H2 Stage85R-derived Stage89K run.

rootDir=fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(rootDir);addpath(fullfile(rootDir,'fa_h2'));
addpath(fullfile(rootDir,'fa_h2','fuzhu'));addpath(fullfile(rootDir,'utils'));
addpath(fullfile(rootDir,'hourly_grid_h2'));
addpath(fullfile(rootDir,'fa_msp','current_hourly_stage88_candidate','config'));
addpath(fullfile(rootDir,'fa_msp','current_hourly_stage88_candidate','input'));
addpath(fullfile(rootDir,'terminalLoh_wdro','current_w_mainline_stage89','msp_bridge'));
runId=char(string(getenv('STAGE89N_RUN_ID')));if isempty(runId),runId='run-001';end
commit=strtrim(string(getenv('STAGE89N_FROZEN_COMMIT')));
phase=upper(strtrim(string(getenv('STAGE89N_PHASE'))));
if commit==""||phase=="",error('Stage85R:Environment','Frozen commit and phase are required.');end
[st,head]=system('git rev-parse HEAD');head=strtrim(string(head));
if st~=0||head~=commit,error('Stage85R:Commit','HEAD %s != frozen %s.',head,commit);end
outDir=run_dir(rootDir,runId);
try
    run_phase(rootDir,outDir,commit,phase);
catch ME
    if isfolder(outDir)
        write_text(fullfile(outDir,'FAILURE.txt'),string(getReport(ME,'extended','hyperlinks','off')));
        write_status(outDir,'FAILED',phase,0,0,feature('getpid'),commit);
    end
    rethrow(ME);
end
end

function run_phase(rootDir,outDir,commit,phase)
pid=feature('getpid');
if phase=="INIT"
    if isfolder(outDir),error('Stage85R:OutputExists','Refusing to overwrite %s.',outDir);end
    make_dirs(outDir);audit_accepted_evidence(rootDir,outDir);preflight_gate(rootDir,outDir);
    write_status(outDir,'RUNNING','INITIALIZED',0,0,pid,commit);return
end
if ~isfolder(outDir),error('Stage85R:NotInitialized','Run is not initialized.');end
logFile=fullfile(outDir,'logs',char(lower(phase)+".txt"));
diary(logFile);cleanup=onCleanup(@()diary('off')); %#ok<NASGU>
if phase=="TRAIN",train_policy(rootDir,outDir,commit,pid);return;end
if phase=="RELOAD_OOS",reload_audit_and_oos(rootDir,outDir,commit,pid);return;end
error('Stage85R:Phase','Unknown phase %s.',phase);
end

function preflight_gate(rootDir,outDir)
[p,opts]=load_params(rootDir);lib=define_models_h2(p);assert_library(lib,p);cuts=cut_count(lib,p);
expectedX0=[58.04455704486949;50.30813793862475;25.262133442309338;33.02358084624278];
rows={
    'STAGE85R_RUNNER_MOTHER_RESOLVED','YES','YES',true;
    'SINGLE_INITIAL_STATE_TRAINING','YES','YES',true;
    'INITIAL_LOCATION_LABEL','loc4','loc4',p.S(p.k_init,2)==4;
    'INITIAL_LOCATION_INTERNAL_INDEX',string(p.k_init),string(p.k_init),p.S(p.k_init,2)==4;
    'MULTILOC_STAGE1_CUTS_USED','NO','NO',true;
    'BACKWARD_PASS_CORE_MODIFIED','NO','NO',true;
    'FORMAL_8H_MAINLINE_USED','YES','YES',p.dt_h==8&&p.enable_hourly_grid;
    'LEGACY_6H_PATH_USED','NO','NO',p.dt_h==8&&p.NearStageInput.NormalDemand.stage_dt_h==6;
    'STAGE89M_STATUS','PASS','PASS',stage89m_status_pass(rootDir);
    'STAGE89J_ADOPTED_AS_CURRENT_W','YES','YES',string(p.stage89_bundle_id)=="current_w_mainline_stage89_v1";
    'STAGE89K_ADOPTED_AS_CURRENT_TERMINALLOH','YES','YES',string(p.terminal_loh_lookup_audit.table_version)=="Stage89K";
    'STAGE89K_DRO_TABLE_LOADED','YES','YES',string(p.terminal_loh_mode)=="stage89k_dro";
    'ETA',string(p.terminal_loh_lookup_audit.eta),'0.03',abs(p.terminal_loh_lookup_audit.eta-0.03)<=1e-12;
    'TANK_CAPACITY',string(mat2str(p.x_cap(:).')),'[300 200 100 200]',isequal(p.x_cap(:).',[300 200 100 200]);
    'PMAX_KW',string(mat2str(p.el_cap_kw(:).')),'[300 200 120 150]',isequal(p.el_cap_kw(:).',[300 200 120 150]);
    'INITIAL_INVENTORY',string(mat2str(p.x_0(:).',15)),string(mat2str(expectedX0(:).',15)),max(abs(p.x_0-expectedX0))<=1e-12;
    'ORDINARY_SHORTAGE_PENALTY',string(p.cost_normal_shortage),'200',p.cost_normal_shortage==200;
    'TERMINAL_GAP_PENALTY',string(p.cost_reserve_shortage),'1000',p.cost_reserve_shortage==1000;
    'TRAINING_ITERATIONS','10','10',true;
    'WARM_START','NONE','NONE',cuts==0;
    'TERMINAL_TABLE_SHA256',string(p.terminal_loh_lookup_audit.source_sha256),string(opts.terminal_loh_expected_sha256),string(p.terminal_loh_lookup_audit.source_sha256)==string(opts.terminal_loh_expected_sha256)};
audit=cell2table(rows,'VariableNames',{'gate','actual','expected','pass'});
safe_writetable(audit,fullfile(outDir,'preflight_gates.csv'));
if ~all(audit.pass),error('Stage89N:Preflight','Preflight identity gate failed.');end
clear lib p
end

function train_policy(rootDir,outDir,commit,pid)
label="LOC4_GAP1000";shortage=200;caseDir=training_dir(outDir);checkpoint=checkpoint_path(outDir);
if isfile(checkpoint)||isfile(fullfile(caseDir,'training_history.csv'))
    error('Stage85R:TrainingExists','Refusing to overwrite training for %s.',label);
end
[p,opts]=load_params(rootDir);rng(opts.seed,'twister');
lib=define_models_h2(p);assert_library(lib,p);initialCuts=cut_count(lib,p);
if initialCuts~=0,error('Stage85R:WarmStart','%s did not start with zero cuts.',label);end
x=zeros(p.Ni,p.T);theta=zeros(p.T,1);lb=0;LB=zeros(0,1);rows=cell(0,28);
budget=10;started=tic;iter=0;totalForward=0;totalBackward=0;warningCount=0;
write_status(outDir,'RUNNING','TRAIN',0,0,pid,commit);
while iter<budget
    iter=iter+1;iterStart=tic;beforeRows=model_row_counts(lib,p);before=sum(max(0,beforeRows-base_rows(p)),'all');
    lastwarn('');f0=tic;[lib,x,theta,lb,path,fwd]=forward_pass_h2(lib,p,lb,x,theta);forwardTime=toc(f0);
    valid=all(ismember(fwd.status,["normal","loh_demand_stage","absorbing_lfNc","dissipated_absorb","post_absorb"]));
    if ~valid||~isfinite(lb)||any(~isfinite(x),'all'),error('Stage85R:Forward','%s iteration %d failed.',label,iter);end
    b0=tic;[lib,cutFlag]=backward_pass_h2(lib,p,x,theta,path);backwardTime=toc(b0);
    afterRows=model_row_counts(lib,p);after=sum(max(0,afterRows-base_rows(p)),'all');
    newAudit=audit_new_cuts(lib,p,beforeRows,afterRows);
    if ~newAudit.pass||after<=before,error('Stage85R:Cuts','%s iteration %d cut audit failed.',label,iter);end
    LB(iter,1)=lb;if iter==1,delta=NaN;else,delta=LB(iter)-LB(iter-1);end
    [warningMessage,warningId]=lastwarn;if strlength(string(warningId))>0,warningCount=warningCount+1;end
    totalForward=totalForward+nnz(fwd.status=="normal");totalBackward=totalBackward+(after-before);
    policyModel=update_rhs_h2(modelLib_at(lib,1,p.k_init),p,p.k_init,1,p.x_0);policySol=solve_stage_model_h2(policyModel);
    stage1SiteProd=sum(policySol.h2_production_hourly_kg,2);stage1Prod=sum(stage1SiteProd);
    rows(end+1,:)={label,iter,budget,toc(started),lb,delta,sum(fwd.stageCost),before,after,after-before, ...
        nnz(fwd.status=="normal"),after-before,forwardTime,backwardTime,toc(iterStart),cutFlag, ...
        string(warningId),string(warningMessage),"TEN_ITERATION_CANDIDATE_DIAGNOSTIC","NOT_CONVERGENCE_CERTIFICATE", ...
        stage1Prod,stage1SiteProd(1),stage1SiteProd(2),stage1SiteProd(3),stage1SiteProd(4),sum(x(:,1)),sum(x(:,2)),sum(x(:,3))}; %#ok<AGROW>
    writetable(cell2table(rows,'VariableNames',training_names()),fullfile(caseDir,'training_history.csv'));
    write_status(outDir,'RUNNING','TRAIN',iter,toc(started),pid,commit);
    fprintf('Stage89N %s iter=%d elapsed=%.3f LB=%.12g cuts=%d\n',label,iter,toc(started),lb,after);
end
trainingWall=toc(started);fullAudit=audit_all_cuts(lib,p);
if ~fullAudit.pass,error('Stage85R:FinalCutAudit','%s full cut audit failed.',label);end
model=first_operating_model(lib,p);finalCuts=cut_count(lib,p);
checkpoint_metadata=struct('stage','89N','runner_mother','Stage85R','arm_label',char(label), ...
    'shortage_penalty_yuan_per_kg',shortage,'htt_c0_yuan_per_kg',p.htt_base_service_cost_yuan_per_kg, ...
    'htt_cost_base_matrix',p.cost_transport_base, ...
    'beta_multiplier',2,'fleet_cap_kg_per_h',160,'eta',0.03, ...
    'demand_schema','original-hourly-24h-repeat-v1','training_seed',opts.seed, ...
    'iteration_budget',budget,'training_wall_time_s',trainingWall,'completed_iterations',iter, ...
    'final_LB',LB(end),'fresh_initial_cut_count',initialCuts,'cumulative_cuts',finalCuts, ...
    'state_dimension',4,'state_order','Site1,Site2,Site3,Site4','variable_count',model.nvars, ...
    'base_inequality_count',base_rows(p),'equality_count',size(model.Aeq,1),'integer_count',0, ...
    'terminal_lookup_sha256',char(sha256_file(opts.terminal_loh_lookup_file)), ...
    'model_schema','hourly-h2-hourly-htt-v1','training_type','STAGE89N_FRESH_10ITER', ...
    'method','chi2_eta003','stage85e_checkpoint_loaded',false, ...
    'initial_location_label','loc4','initial_location_internal_index',p.k_init, ...
    'training_identity','TEN_ITERATION_CANDIDATE_DIAGNOSTIC','convergence_scope','NOT_CONVERGENCE_CERTIFICATE', ...
    'warm_start_checkpoint','NONE','cross_arm_cut_source','NONE','frozen_commit',char(commit));
params=p;modelLib=lib;state=struct('x',x,'theta',theta,'lb',lb,'LB',LB); %#ok<NASGU>
policy=struct('representation','modelLib_with_embedded_cuts','state_order','Site1,Site2,Site3,Site4', ...
    'classification','STAGE89N_SINGLE_LOC4_TEN_ITERATION_DIAGNOSTIC');rng_state=rng; %#ok<NASGU>
saveStart=tic;save_checkpoint_safe(checkpoint,params,modelLib,state,LB,policy,opts,rng_state,checkpoint_metadata);
checkpointSaveSeconds=toc(saveStart);
info=dir(checkpoint);summary=table(label,shortage,p.htt_base_service_cost_yuan_per_kg,"CURRENT_MATRIX",2,0.03,opts.seed,budget,trainingWall,iter, ...
    LB(end),finalCuts,totalForward,totalBackward,warningCount,0,initialCuts,string(checkpoint), ...
    info.bytes,checkpointSaveSeconds,fullAudit.pass,"TEN_ITERATION_CANDIDATE_DIAGNOSTIC","NOT_CONVERGENCE_CERTIFICATE", ...
    'VariableNames',{'policy','shortage_penalty_yuan_per_kg','htt_base_service_cost_yuan_per_kg','htt_transport_cost_schema', ...
    'beta_multiplier','eta','training_seed','iteration_budget','actual_training_wall_time_s','completed_iterations', ...
    'final_LB','cumulative_cuts','forward_operating_solves','backward_cut_solves','warning_count','error_count', ...
    'fresh_initial_cuts','checkpoint_path','checkpoint_bytes','checkpoint_save_seconds','full_cut_audit_pass', ...
    'training_identity','convergence_scope'});
safe_writetable(summary,fullfile(caseDir,'training_summary.csv'));
write_text(fullfile(caseDir,'TRAINING_FINISHED.txt'),sprintf('%s_TRAINING_FINISHED=true\n',label));
write_status(outDir,'RUNNING','TRAIN_FINISHED',iter,trainingWall,pid,commit);
clear modelLib lib params p
end

function reload_audit_and_oos(rootDir,outDir,commit,pid)
label="LOC4_GAP1000";shortage=200;oosDir=oos_dir(outDir);checkpoint=checkpoint_path(outDir);
if ~isfile(checkpoint),error('Stage89N:CheckpointMissing','Missing checkpoint.');end
expectedSha=lower(strtrim(string(getenv('STAGE89N_CHECKPOINT_SHA256'))));
if strlength(expectedSha)~=64,error('Stage89N:ExternalHash','External SHA-256 is required.');end
info=dir(checkpoint);reloadStart=tic;loaded=load(checkpoint);reloadSeconds=toc(reloadStart);
required={'params','modelLib','state','LB','policy','opts','rng_state','checkpoint_metadata'};
if ~all(isfield(loaded,required)),error('Stage89N:CheckpointSchema','Required variables missing.');end
p=loaded.params;lib=loaded.modelLib;m=loaded.checkpoint_metadata;clear loaded
cuts=cut_count(lib,p);audit=audit_all_cuts(lib,p);
identity=string(m.stage)=="89N"&&string(m.runner_mother)=="Stage85R"&& ...
    string(m.initial_location_label)=="loc4"&&m.initial_location_internal_index==p.k_init&& ...
    p.S(p.k_init,2)==4&&m.shortage_penalty_yuan_per_kg==200&& ...
    m.training_seed==20260513&&m.iteration_budget==10&&m.completed_iterations==10&& ...
    m.fresh_initial_cut_count==0&&m.cumulative_cuts==cuts&&m.state_dimension==4&& ...
    string(m.warm_start_checkpoint)=="NONE"&&p.dt_h==8&&p.enable_hourly_grid&& ...
    p.cost_normal_shortage==200&&p.cost_reserve_shortage==1000&& ...
    isequal(p.x_cap(:).',[300 200 100 200])&&isequal(p.el_cap_kw(:).',[300 200 120 150])&& ...
    string(p.demand_schema)=="original-hourly-24h-repeat-v1"&& ...
    string(p.terminal_loh_mode)=="stage89k_dro"&&string(p.terminal_loh_lookup_audit.table_version)=="Stage89K"&& ...
    string(p.terminal_loh_lookup_audit.source_sha256)=="2fa1958944110701239a109ebf46d959324a351f2f27c1c3fbd62f333066eaa8"&& ...
    abs(p.terminal_loh_lookup_audit.eta-0.03)<=1e-12;
pass=identity&&audit.pass;
verification=table(string(checkpoint),info.bytes,expectedSha,reloadSeconds,cuts,audit.pass,identity,pass, ...
    'VariableNames',{'checkpoint_path','bytes','external_sha256','clean_reload_seconds', ...
    'cumulative_cuts','cut_structure_pass','identity_pass','pass'});
safe_writetable(verification,fullfile(outDir,'checkpoint_reload_audit.csv'));
if ~pass,error('Stage89N:CheckpointAudit','Clean checkpoint reload audit failed.');end
write_text(fullfile(outDir,'CHECKPOINT_RELOAD_PASS'),"CHECKPOINT_RELOAD_PASS=true"+newline);

sourceBank=fullfile(rootDir,'results','task-002-stage2b-b3-smoke', ...
    '89H-stage85r-single-loc4-stage88-dro-gap1000-10iter-oos10000','run-003','oos','loc4','oos_path_bank.mat');
if sha256_file(sourceBank)~="6bf3d1190a402ded052b8d3d08ed369042236e151f562bdd9fd4db7b8ff386c6"
    error('Stage89N:CommonPathHash','Stage89H accepted common-path bank hash mismatch.');
end
bankLoaded=load(sourceBank,'pathBank','seed');pathBank=bankLoaded.pathBank;seed=bankLoaded.seed;clear bankLoaded
n=size(pathBank,1);
if n~=10000||size(pathBank,2)~=p.T||seed~=20260817||any(pathBank(:,1)~=p.k_init)
    error('Stage89N:CommonPathIdentity','Stage89H accepted common-path bank identity mismatch.');
end
ids=(1:n).';vars=arrayfun(@(t)sprintf('k_t%d',t),1:p.T,'UniformOutput',false);
manifest=[table(ids,'VariableNames',{'path_id'}),array2table(pathBank,'VariableNames',vars)];
safe_writetable(manifest,fullfile(oosDir,'oos_path_manifest.csv'));
bankFile=sourceBank;
bankIdentity=table(seed,n,p.T,p.k_init,string("loc4"),string(bankFile),string("YES"), ...
    'VariableNames',{'seed','path_count','stage_count','initial_state_internal_index','initial_location_label','bank_path','common_path_oos_with_stage89h'});
safe_writetable(bankIdentity,fullfile(oosDir,'bank_identity.csv'));

cutsBefore=cuts;files=oos_files(oosDir);if any(cellfun(@isfile,struct2cell(files))),error('Stage89N:OOSOutput','Output files exist.');end
first=true;totalSolves=0;maxEq=0;maxIneq=0;started=tic;
pathBuffer=cell(0,numel(path_names()));stageBuffer=cell(0,numel(stage_names()));siteBuffer=cell(0,numel(stage_site_names()));
write_status(outDir,'RUNNING','OOS',0,0,pid,commit);
for q=1:10000
    [pr,sr,ss,~,~,~,nr]=evaluate_path(lib,p,pathBank(q,:),q,label,shortage);
    totalSolves=totalSolves+nr.solve_count;maxEq=max(maxEq,nr.max_eq);maxIneq=max(maxIneq,nr.max_ineq);
    pathBuffer=[pathBuffer;pr];stageBuffer=[stageBuffer;sr];siteBuffer=[siteBuffer;ss]; %#ok<AGROW>
    if mod(q,25)==0||q==10000
        append_table(files.path,cell2table(pathBuffer,'VariableNames',path_names()),first);
        append_table(files.stage,cell2table(stageBuffer,'VariableNames',stage_names()),first);
        append_table(files.site,cell2table(siteBuffer,'VariableNames',stage_site_names()),first);
        first=false;pathBuffer=cell(0,numel(path_names()));stageBuffer=cell(0,numel(stage_names()));
        siteBuffer=cell(0,numel(stage_site_names()));
        progress=table(label,q,toc(started),totalSolves,maxEq,maxIneq, ...
            'VariableNames',{'policy','completed_paths','wall_time_s','operating_solves','max_eq_residual','max_ineq_violation'});
        safe_writetable(progress,fullfile(oosDir,'progress.csv'));
        write_status(outDir,'RUNNING','OOS',q,toc(started),pid,commit);
    end
end
cutsAfter=cut_count(lib,p);paths=readtable(files.path,'TextType','string');
pass=height(paths)==10000&&isequal(double(paths.path_id),(1:10000).')&&cutsBefore==cutsAfter&&maxEq<=1e-6&&maxIneq<=1e-6;
meta=table(label,10000,height(paths),totalSolves,toc(started),cutsBefore,cutsAfter,cutsBefore==cutsAfter, ...
    string(checkpoint),expectedSha,string(bankFile),seed,p.k_init,maxEq,maxIneq,pass, ...
    'VariableNames',{'policy','requested_paths','completed_paths','operating_solves','wall_time_s', ...
    'cuts_before','cuts_after','cuts_unchanged','checkpoint_path','checkpoint_sha256', ...
    'bank_path','oos_seed','initial_state_internal_index','max_eq_residual','max_ineq_violation','pass'});
safe_writetable(meta,fullfile(oosDir,'oos_metadata.csv'));
if ~pass,error('Stage89N:OOSGate','loc4 OOS completion gate failed.');end
write_text(fullfile(oosDir,'OOS_COMPLETE.txt'),"LOC4_10000_OOS_COMPLETE=true"+newline);
write_status(outDir,'RUNNING','OOS_COMPLETE',10000,toc(started),pid,commit);
clear lib p pathBank
end

function [pr,stageRows,siteRows,hourRows,systemRows,flowRows,numerical]=evaluate_path(lib,p,seq,pathId,label,shortage)
prev=p.x_0(:);opCost=0;holdCost=0;prodCost=0;gridCost=0;omCost=0;shortKg=0;shortCost=0;
prodKg=0;httKg=0;httCost=0;terminalValue=0;terminalGap=zeros(4,1);terminalTarget=zeros(4,1);terminalState=0;
stageRows=cell(0,numel(stage_names()));siteRows=cell(0,numel(stage_site_names()));
hourRows=cell(0,numel(hour_site_names()));systemRows=cell(0,numel(hour_system_names()));flowRows=cell(0,numel(flow_names()));
solveCount=0;maxEq=0;maxIneq=0;operatingStages=0;
for t=1:p.T
    k=seq(t);a=p.S(k,1);loc=p.S(k,2);lf=p.S(k,3);beta=p.beta(k);
    if p.is_dissipated(k)||p.is_absorbing(k),break;end
    if p.is_loh_demand_stage(k)
        terminalState=k;terminalTarget=p.TerminalLOH(:,k);terminalGap=max(0,terminalTarget-prev);
        [terminalValue,g]=terminal_value_and_subgradient_h2(prev,p,k);
        if numel(g)~=4||any(~isfinite(g))||~isfinite(terminalValue),error('Stage85R:Terminal','Bad terminal value.');end
        break
    end
    if t>6,error('Stage85R:Lifecycle','Ordinary state after Stage6.');end
    operatingStages=operatingStages+1;beginInv=prev;m=update_rhs_h2(lib.models{t,k},p,k,t,prev);s=solve_stage_model_h2(m);solveCount=solveCount+1;
    eq=max(abs(m.Aeq*s.xraw-m.beq));ineq=max([0;m.A*s.xraw-m.b]);maxEq=max(maxEq,eq);maxIneq=max(maxIneq,ineq);
    if ~strcmpi(s.status,'OPTIMAL')&&~strcmpi(s.status,'normal'),error('Stage85R:Solve','Invalid solve status path %d stage %d.',pathId,t);end
    if eq>1e-6||ineq>1e-6||any(~isfinite(s.xraw))||numel(s.lambda.inventory_eq)~=4||any(~isfinite(s.lambda.inventory_eq))
        error('Stage85R:Numerical','Numerical gate path %d stage %d.',pathId,t);
    end
    distanceCost=p.cost_transport_base;if p.use_beta_cost,distanceCost=distanceCost*(1+p.beta_transport_multiplier*beta);end
    unit=p.htt_base_service_cost_yuan_per_kg+distanceCost;flow=s.f_hourly_kg;costCube=flow.*repmat(unit,1,1,8);
    if max(abs(m.htt_unit_cost_yuan_per_kg-unit),[],'all')>1e-10
        error('Stage85R:HTTCost','HTT coefficient gate failed.');
    end
    tau=8*(t-1)+(1:8);stageGrid=sum(p.hourly_grid.tariff48(tau(:)).*s.p_grid_kw(:));stageOm=p.cost_el_om*8*sum(s.eval);
    stageHold=p.cost_holding*sum(s.xval);stageShort=sum(s.z_normal_hourly_kg,'all');stageProd=sum(s.h2_production_hourly_kg,'all');
    stageHtt=sum(flow,'all');stageHttCost=sum(costCube,'all');stageObjective=s.obj-s.theta;
    if abs(stageObjective-(stageGrid+stageOm+stageHold+shortage*stageShort+stageHttCost))>1e-5
        error('Stage85R:Objective','Objective decomposition failed path %d stage %d.',pathId,t);
    end
    stageRows(end+1,:)={label,pathId,t,k,a,loc,lf,beta,stageObjective,stageGrid+stageOm,stageGrid,stageOm, ...
        stageHold,stageShort,shortage*stageShort,stageProd,stageHtt,stageHttCost,sum(beginInv),sum(s.xval),s.theta}; %#ok<AGROW>
    for i=1:4
        siteRows(end+1,:)={label,pathId,t,k,a,loc,lf,beta,i,beginInv(i),sum(s.h2_demand_hourly_kg(i,:)), ...
            sum(s.u_normal_hourly_kg(i,:)),sum(s.z_normal_hourly_kg(i,:)),sum(s.h2_production_hourly_kg(i,:)), ...
            sum(s.htt_in_hourly_kg(i,:)),sum(s.htt_out_hourly_kg(i,:)),s.xval(i)}; %#ok<AGROW>
    end
    v=sqrt(max(s.v_sq,0));trueS=hypot(s.p_branch_kw,s.q_branch_kvar)/1000;
    for h=1:8
        gh=8*(t-1)+h;capacity=max(0,(1-beta)*160);totalFlow=sum(flow(:,:,h),'all');
        [minV,minBus]=min(v(:,h));[maxBranch,ell]=max(trueS(:,h));
        pvAvail=p.hourly_grid.pv_cap_kw(:)*p.hourly_grid.phi48(gh);
        systemRows(end+1,:)={label,pathId,t,k,a,loc,lf,beta,h,gh,p.hourly_grid.tariff48(gh), ...
            sum(pvAvail),sum(s.p_pv_kw(:,h)),s.p_grid_kw(h),minV,minBus,maxBranch, ...
            p.hourly_grid.branch_from(ell),p.hourly_grid.branch_to(ell),maxBranch/p.hourly_grid.branch_smax_mva, ...
            totalFlow,capacity,ternary(capacity>0,totalFlow/capacity,0),capacity>0&&abs(totalFlow-capacity)<=1e-6}; %#ok<AGROW>
        for i=1:4
            bus=p.hourly_grid.site_elec_bus(i);pre=s.h2_inventory_pre_htt_kg(i,h);ending=s.h2_inventory_hourly_kg(i,h);
            hourRows(end+1,:)={label,pathId,t,k,a,loc,lf,beta,h,gh,i,bus,p.hourly_grid.tariff48(gh), ...
                s.h2_demand_hourly_kg(i,h),s.u_normal_hourly_kg(i,h),s.z_normal_hourly_kg(i,h), ...
                s.h2_production_hourly_kg(i,h),s.p_el_hourly_kw(i,h),pvAvail(i),s.p_pv_kw(i,h), ...
                s.p_grid_kw(h),v(bus,h),pre,ending,s.htt_in_hourly_kg(i,h),s.htt_out_hourly_kg(i,h), ...
                abs(s.p_el_hourly_kw(i,h)-p.el_cap_kw(i))<=1e-6,abs(ending-p.x_cap(i))<=1e-6}; %#ok<AGROW>
            for j=1:4
                if i==j||flow(i,j,h)<=1e-8,continue;end
                f=flow(i,j,h);flowRows(end+1,:)={label,pathId,t,k,a,loc,lf,beta,h,gh,i,j,f, ...
                    p.site_to_site_road_km(i,j),unit(i,j),f*unit(i,j),f<5,f<10, ...
                    s.h2_inventory_pre_htt_kg(i,h),s.h2_inventory_hourly_kg(i,h), ...
                    s.h2_inventory_pre_htt_kg(j,h),s.h2_inventory_hourly_kg(j,h), ...
                    s.h2_demand_hourly_kg(j,h),s.u_normal_hourly_kg(j,h),s.z_normal_hourly_kg(j,h), ...
                    s.h2_production_hourly_kg(i,h),capacity,totalFlow,capacity>0&&abs(totalFlow-capacity)<=1e-6}; %#ok<AGROW>
            end
        end
    end
    opCost=opCost+stageObjective;holdCost=holdCost+stageHold;prodCost=prodCost+stageGrid+stageOm;
    gridCost=gridCost+stageGrid;omCost=omCost+stageOm;shortKg=shortKg+stageShort;shortCost=shortCost+shortage*stageShort;
    prodKg=prodKg+stageProd;httKg=httKg+stageHtt;httCost=httCost+stageHttCost;prev=s.xval;
end
pr={label,pathId,strjoin(string(seq),'-'),operatingStages,opCost+terminalValue,opCost,holdCost,prodCost,gridCost,omCost, ...
    shortKg,shortCost,prodKg,httKg,httCost,sum(prev),prev(1),prev(2),prev(3),prev(4),terminalState, ...
    terminalTarget(1),terminalTarget(2),terminalTarget(3),terminalTarget(4),sum(terminalTarget), ...
    terminalGap(1),terminalGap(2),terminalGap(3),terminalGap(4),sum(terminalGap),terminalValue, ...
    p.S(seq(end),1),p.S(seq(end),2),p.S(seq(end),3)};
numerical=struct('solve_count',solveCount,'max_eq',maxEq,'max_ineq',maxIneq);
end

function [p,opts]=load_params(rootDir)
[p,opts,candidateAudit]=load_current_stage89_hourly_h2(rootDir,"dro");opts.seed=20260513;
opts.terminal_loh_lookup_file=char(p.terminal_loh_source);
opts.terminal_loh_expected_sha256=char(p.terminal_loh_lookup_audit.source_sha256);
p.cost_reserve_shortage=1000;
p.NearStageInput.Cost.reserve_shortage_penalty_yuan_per_kg=1000;
baseState=p.k_init;initialA=p.S(baseState,1);initialLf=p.S(baseState,3);
p.k_init=p.state_id(initialA,4,initialLf);
if ~candidateAudit.pass||~p.enable_hourly_grid||p.dt_h~=8||p.T~=8||p.Ni~=4|| ...
        p.S(p.k_init,1)~=initialA||p.S(p.k_init,2)~=4||p.S(p.k_init,3)~=initialLf|| ...
        abs(p.cost_normal_shortage-200)>1e-12||abs(p.cost_reserve_shortage-1000)>1e-12|| ...
        ~isfinite(p.htt_base_service_cost_yuan_per_kg)||p.htt_base_service_cost_yuan_per_kg<0||abs(p.htt_capacity_base-160)>1e-12|| ...
        abs(p.beta_transport_multiplier-2)>1e-12||any(~isfinite(p.cost_transport_base),'all')||any(p.cost_transport_base<0,'all')|| ...
        string(p.terminal_loh_mode)~="stage89k_dro"||string(p.demand_schema)~="original-hourly-24h-repeat-v1"|| ...
        p.NearStageInput.NormalDemand.stage_dt_h~=6||~isequal(p.x_cap(:).',[300 200 100 200])|| ...
        ~isequal(p.el_cap_kw(:).',[300 200 120 150])||abs(p.terminal_loh_lookup_audit.eta-0.03)>1e-12
    error('Stage89N:Identity','Frozen single-loc4 parameter identity mismatch.');
end
end

function audit_accepted_evidence(rootDir,outDir)
base=fullfile(rootDir,'results','task-002-stage2b-b3-smoke');
paths={fullfile(base,'85O-economic-calibration-fresh-short-pilot','run-004','final_judgment.txt'), ...
    fullfile(base,'85O-economic-calibration-fresh-short-pilot','run-004','source_identity_hashes.csv'), ...
    fullfile(base,'85P-shortage150-c0-5-fresh-short-pilot','run-002','final_judgment.txt'), ...
    fullfile(base,'85P-shortage150-c0-5-fresh-short-pilot','run-002','source_identity_hashes.csv'), ...
    fullfile(base,'85Q-p150-fragmentation-mechanism-diagnostic','run-001','final_judgment.txt'), ...
    fullfile(base,'85Q-p150-fragmentation-mechanism-diagnostic','run-001','source_identity_hashes.csv')};
tokens={"PROCEED_WITH_C0_ONLY_CANDIDATE","","NONMONOTONIC_PENALTY_RESPONSE_NEEDS_DIAGNOSTIC","", ...
    "SHORT_TRAINING_ARTIFACT_CANNOT_BE_RULED_OUT",""};rows=cell(numel(paths),5);
for i=1:numel(paths)
    if ~isfile(paths{i}),error('Stage85R:AcceptedEvidence','Missing %s.',paths{i});end
    tokenPass=tokens{i}==""||contains(string(fileread(paths{i})),tokens{i});
    info=dir(paths{i});rows(i,:)={string(paths{i}),info.bytes,sha256_file(paths{i}),tokens{i},tokenPass};
end
audit=cell2table(rows,'VariableNames',{'path','bytes','sha256','required_token','pass'});
safe_writetable(audit,fullfile(outDir,'accepted_evidence_identity.csv'));
if ~all(audit.pass),error('Stage85R:AcceptedEvidence','Accepted evidence token gate failed.');end
end

function assert_library(lib,p)
for t=1:6
    present=lib.models(t,:);present=present(~cellfun(@isempty,present));
    if isempty(present)||~all(cellfun(@(m)m.hourly_grid_enabled&&m.hourly_h2_balance_enabled&&m.hourly_htt_enabled&& ...
            m.nvars==1129&&size(m.A,1)==base_rows(p),present))
        error('Stage85R:Library','Fresh library invalid at stage %d.',t);
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

function save_checkpoint_safe(path,params,modelLib,state,LB,policy,opts,rng_state,checkpoint_metadata)
tmp=[path '.tmp.mat'];save(tmp,'params','modelLib','state','LB','policy','opts','rng_state','checkpoint_metadata','-v7.3');
v=whos('-file',tmp);required={'params','modelLib','state','LB','policy','opts','rng_state','checkpoint_metadata'};
if ~all(ismember(required,{v.name})),error('Stage85R:CheckpointWrite','Incomplete checkpoint.');end
movefile(tmp,path,'f');
end

function f=oos_files(dirPath)
f=struct('path',fullfile(dirPath,'oos_path_summary.csv'),'stage',fullfile(dirPath,'oos_stage_summary.csv'), ...
    'site',fullfile(dirPath,'oos_stage_site_summary.csv'),'hour',fullfile(dirPath,'oos_hour_site.csv'), ...
    'system',fullfile(dirPath,'oos_hour_system.csv'),'flow',fullfile(dirPath,'oos_positive_htt_flows.csv'));
end
function append_table(path,T,first),if isempty(T),return;end;if first,safe_writetable(T,path);else,writetable(T,path,'WriteMode','append','WriteVariableNames',false);end,end
function safe_writetable(T,path),[d,n,e]=fileparts(path);tmp=fullfile(d,[n '.tmp' e]);writetable(T,tmp);movefile(tmp,path,'f');end
function p=run_dir(rootDir,runId),p=fullfile(rootDir,'results','task-002-stage2b-b3-smoke','stage89n-stage89k-adopted-loc4-fresh-8h-retraining',runId);end
function p=training_dir(outDir),p=fullfile(outDir,'training');end
function p=oos_dir(outDir),p=fullfile(outDir,'oos','loc4');end
function p=checkpoint_path(outDir)
[runRoot,runId]=fileparts(outDir);rootDir=fileparts(fileparts(fileparts(runRoot)));
p=fullfile(rootDir,'terminalLoh_wdro','output','stage89n_stage89k_adopted_loc4_fresh_8h_retraining',runId,'checkpoint_final.mat');
end
function make_dirs(outDir)
dirs={'training','oos/loc4','analysis','logs'};
mkdir(outDir);for i=1:numel(dirs),mkdir(fullfile(outDir,dirs{i}));end
checkpoint=checkpoint_path(outDir);mkdir(fileparts(checkpoint));
end
function pass=stage89m_status_pass(rootDir)
path=fullfile(rootDir,'results','task-002-stage2b-b3-smoke','stage89m-formal-adoption-and-8h-integration','run-001','README.md');
if ~isfile(path),pass=false;return;end
text=string(fileread(path));
tokens=["STAGE89M_STATUS = PASS","STAGE89J_ADOPTED_AS_CURRENT_W = YES", ...
    "STAGE89K_ADOPTED_AS_CURRENT_TERMINALLOH = YES","READY_FOR_STAGE89N = YES"];
pass=all(contains(text,tokens));
end
function h=sha256_file(path)
escaped=strrep(char(path),'"','\"');command=sprintf('certutil -hashfile "%s" SHA256',escaped);
[status,output]=system(command);tokens=regexp(output,'[0-9A-Fa-f]{64}','match');
if status~=0||numel(tokens)~=1,error('Stage85R:Hash','Cannot hash %s.',path);end
h=lower(string(tokens{1}));
end
function write_status(outDir,status,phase,count,elapsed,pid,commit)
txt=sprintf('STATUS=%s\nPHASE=%s\nINITIAL_LOCATION=loc4\nCOUNT=%d\nELAPSED_S=%.12g\nMATLAB_PID=%d\nFROZEN_COMMIT=%s\nUPDATED_AT=%s\n', ...
    status,phase,count,elapsed,pid,commit,string(datetime('now','Format','yyyy-MM-dd HH:mm:ss')));
tmp=fullfile(outDir,'RUNNING_STATUS.tmp');write_text(tmp,txt);movefile(tmp,fullfile(outDir,'RUNNING_STATUS.txt'),'f');
end
function write_text(path,text),fid=fopen(path,'w');if fid<0,error('Stage85R:Write','%s',path);end;c=onCleanup(@()fclose(fid));fprintf(fid,'%s',char(text));end %#ok<NASGU>
function v=ternary(c,a,b),if c,v=a;else,v=b;end,end

function n=training_names(),n={'policy','iteration','iteration_budget','cumulative_wall_time_s','LB','LB_increment','forward_cost_UB_like','cuts_before','cumulative_cuts','cuts_added','forward_stage_solve_count','backward_cut_solve_count','forward_time_s','backward_time_s','iteration_wall_time_s','cut_violation_flag','warning_id','warning_message','training_identity','convergence_scope','stage1_production_kg','stage1_site1_production_kg','stage1_site2_production_kg','stage1_site3_production_kg','stage1_site4_production_kg','stage1_inventory_kg','stage2_inventory_kg','stage3_inventory_kg'};end
function n=path_names(),n={'policy','path_id','state_sequence','operating_stage_count','total_objective_yuan','operating_cost_yuan','holding_cost_yuan','production_electricity_cost_yuan','grid_cost_yuan','production_om_cost_yuan','ordinary_shortage_kg','ordinary_shortage_cost_yuan','production_kg','htt_kg','htt_cost_yuan','terminal_inventory_kg','terminal_inventory_site1_kg','terminal_inventory_site2_kg','terminal_inventory_site3_kg','terminal_inventory_site4_kg','terminal_state_id','terminal_target_site1_kg','terminal_target_site2_kg','terminal_target_site3_kg','terminal_target_site4_kg','terminal_target_kg','terminal_gap_site1_kg','terminal_gap_site2_kg','terminal_gap_site3_kg','terminal_gap_site4_kg','terminal_gap_kg','stage7_terminal_value_yuan','final_a','final_loc','final_lf'};end
function n=stage_names(),n={'policy','path_id','stage','state_id','a','loc','lf','beta','stage_objective_yuan','production_electricity_cost_yuan','grid_cost_yuan','production_om_cost_yuan','holding_cost_yuan','ordinary_shortage_kg','ordinary_shortage_cost_yuan','production_kg','htt_kg','htt_cost_yuan','beginning_inventory_kg','ending_inventory_kg','future_value_theta'};end
function n=stage_site_names(),n={'policy','path_id','stage','state_id','a','loc','lf','beta','site','beginning_inventory_kg','ordinary_demand_kg','served_demand_kg','shortage_kg','production_kg','htt_in_kg','htt_out_kg','ending_inventory_kg'};end
function n=hour_site_names(),n={'policy','path_id','stage','state_id','a','loc','lf','beta','local_hour','global_hour','site','electrical_bus','tariff_yuan_per_kwh','ordinary_demand_kg','served_demand_kg','shortage_kg','production_kg','p_el_kw','pv_available_kw','pv_used_kw','grid_import_kw_system','site_voltage_pu','inventory_pre_htt_kg','ending_inventory_kg','htt_in_kg','htt_out_kg','electrolyzer_capacity_binding','storage_capacity_binding'};end
function n=hour_system_names(),n={'policy','path_id','stage','state_id','a','loc','lf','beta','local_hour','global_hour','tariff_yuan_per_kwh','pv_available_kw','pv_used_kw','grid_import_kw','minimum_voltage_pu','minimum_voltage_bus','max_branch_mva','max_branch_from','max_branch_to','max_branch_utilization','total_htt_kg','fleet_capacity_kg','fleet_utilization','fleet_capacity_binding'};end
function n=flow_names(),n={'policy','path_id','stage','state_id','a','loc','lf','beta','local_hour','global_hour','origin','destination','htt_flow_kg','distance_km','unit_cost_yuan_per_kg','htt_cost_yuan','lt5','lt10','source_inventory_pre_htt_kg','source_ending_inventory_kg','destination_inventory_pre_htt_kg','destination_ending_inventory_kg','destination_demand_kg','destination_served_kg','destination_shortage_kg','source_production_kg','fleet_capacity_kg','total_hour_htt_kg','fleet_capacity_binding'};end
