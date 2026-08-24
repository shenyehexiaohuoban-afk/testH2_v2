function run_stage89q_pmax_dual_10iter_smoke_h2()
%RUN_STAGE89Q_PMAX_DUAL_10ITER_SMOKE_H2 Isolated Stage89Q Pmax smoke phases.

rootDir = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(rootDir); addpath(fullfile(rootDir,'fa_h2'));
addpath(fullfile(rootDir,'fa_h2','fuzhu')); addpath(fullfile(rootDir,'utils'));
addpath(fullfile(rootDir,'hourly_grid_h2'));
addpath(fullfile(rootDir,'fa_msp','current_hourly_stage88_candidate','config'));
addpath(fullfile(rootDir,'fa_msp','current_hourly_stage88_candidate','input'));
addpath(fullfile(rootDir,'terminalLoh_wdro','current_w_mainline_stage89','msp_bridge'));

runDir = char(strtrim(string(getenv('STAGE89Q_PMAX_RUN_DIR'))));
phase = upper(strtrim(string(getenv('STAGE89Q_PMAX_PHASE'))));
arm = upper(strtrim(string(getenv('STAGE89Q_PMAX_ARM'))));
commit = strtrim(string(getenv('STAGE89Q_PMAX_FROZEN_COMMIT')));
pmaxText = strtrim(string(getenv('STAGE89Q_PMAX_VECTOR')));
checkpointSha = lower(strtrim(string(getenv('STAGE89Q_PMAX_CHECKPOINT_SHA256'))));
if runDir=="" || phase=="" || commit==""
    error('Stage89QPmax:Environment','Required phase environment is missing.');
end
[st,head] = system('git rev-parse HEAD'); head = strtrim(string(head));
if st~=0 || head~=commit
    error('Stage89QPmax:Commit','HEAD %s does not match frozen %s.',head,commit);
end

if phase=="BASE_IDENTITY"
    run_base_identity(rootDir,runDir,commit);
    return;
end
[candidateId,pmax,armDir] = arm_spec(runDir,arm,pmaxText);
logDir = fullfile(armDir,'02_training');
if phase=="CONFIG", logDir=fullfile(armDir,'01_config'); end
if phase=="RELOAD", logDir=fullfile(armDir,'06_checkpoint'); end
diary(fullfile(logDir,char(lower(phase))+"_matlab.log"));
cleanup = onCleanup(@()diary('off')); %#ok<NASGU>
try
    if phase=="CONFIG"
        run_config(rootDir,runDir,armDir,candidateId,pmax,commit);
    elseif phase=="TRAIN"
        run_training(rootDir,armDir,candidateId,pmax,commit);
    elseif phase=="RELOAD"
        run_reload(rootDir,armDir,candidateId,pmax,commit,checkpointSha);
    else
        error('Stage89QPmax:Phase','Unknown phase %s.',phase);
    end
catch ME
    write_text(fullfile(logDir,char(lower(phase))+"_failure.txt"), ...
        string(getReport(ME,'extended','hyperlinks','off')));
    rethrow(ME);
end
end

function run_base_identity(rootDir,runDir,commit)
outDir = fullfile(runDir,'01_preflight');
diary(fullfile(outDir,'base_identity_matlab.log'));
cleanup = onCleanup(@()diary('off')); %#ok<NASGU>
[p,opts,audit] = load_formal_stage89q_base(rootDir);
assert_base_identity(p,opts,audit);
lib = define_models_h2(p); modelAudit = inspect_model_pmax(lib,p.el_cap_kw,p);
if ~modelAudit.pass, error('Stage89QPmax:BaseModel','Base model Pmax bound audit failed.'); end
rows = {
    'resolved_orchestrator','fa_msp/current_hourly_stage89_adopted/launcher/orchestrate_stage89q_pmax_dual_10iter_smoke.ps1','Stage89Q derived orchestrator';
    'resolved_matlab_launcher','fa_msp/current_hourly_stage89_adopted/launcher/run_stage89q_pmax_dual_10iter_smoke_h2.m','new isolated thin phase runner';
    'resolved_config_entry','fa_msp/current_hourly_stage88_candidate/config/current_hourly_stage88_candidate_options_h2.m','formal Stage89Q config';
    'resolved_model_entry','terminalLoh_wdro/current_w_mainline_stage89/msp_bridge/load_current_stage89_hourly_h2.m','formal Stage89Q loader';
    'resolved_pmax_source',char(string(opts.nearInputFile))+"::NearStageInput.HydrogenDevice.el_cap_kw",mat2str(p.el_cap_kw(:).');
    'resolved_terminalloh_source',char(string(p.terminal_loh_source)),char(string(p.terminal_loh_lookup_audit.source_sha256));
    'resolved_output_root',runDir,'isolated smoke output';
    'source_commit',char(commit),'mechanically verified HEAD'};
    safe_writetable(cell2table(rows,'VariableNames',{'key','value','notes'}),fullfile(outDir,'resolved_entries.csv'));
idRows = {
    'dt_h',p.dt_h,'8',p.dt_h==8;
    'operating_stages',p.hourly_grid.n_operating_stages,'6',p.hourly_grid.n_operating_stages==6;
    'hours_per_operating_stage',p.hourly_grid.hours_per_stage,'8',p.hourly_grid.hours_per_stage==8;
    'stage7_semantics',double(nnz(p.is_loh_demand_stage)),'35 non-dissipated analytic TerminalLOH states', ...
        nnz(p.is_loh_demand_stage)==35&&all(p.is_loh_demand_stage(p.S(:,3)==7&~p.is_dissipated));
    'stage8_semantics',double(all(p.is_absorbing(p.S(:,3)==8))),'absorbing',all(p.is_absorbing(p.S(:,3)==8));
    'tank_capacity',NaN,'[300 200 100 200]',isequal(p.x_cap(:).',[300 200 100 200]);
    'ordinary_demand_schema',NaN,'original-hourly-24h-repeat-v1',string(p.demand_schema)=="original-hourly-24h-repeat-v1";
    'htt_hourly_capacity_benchmark',p.htt_capacity_base,'160',p.htt_capacity_base==160;
    'terminal_gap_penalty',p.cost_reserve_shortage,'1000',p.cost_reserve_shortage==1000;
    'base_pmax',NaN,'[300 200 120 150]',isequal(p.el_cap_kw(:).',[300 200 120 150]);
    'training_seed',opts.seed,'20260513',opts.seed==20260513;
    'grid_bus_count',p.hourly_grid.n_bus,'33',p.hourly_grid.n_bus==33;
    'voltage_min',p.hourly_grid.vmin_pu,'0.90',p.hourly_grid.vmin_pu==0.90;
    'voltage_max',p.hourly_grid.vmax_pu,'1.10',p.hourly_grid.vmax_pu==1.10;
    'branch_limit_mva',p.hourly_grid.branch_smax_mva,'6',p.hourly_grid.branch_smax_mva==6;
    'model_pmax_bounds',double(modelAudit.pass),'PASS',modelAudit.pass};
T = cell2table(idRows,'VariableNames',{'check','observed_numeric','expected','pass'});
safe_writetable(T,fullfile(outDir,'current_model_identity_gate.csv'));
if ~all(T.pass), error('Stage89QPmax:BaseIdentity','Current formal model identity gate failed.'); end
write_text(fullfile(outDir,'BASE_IDENTITY_PASS.txt'),sprintf('status=PASS\nhead=%s\nseed=%d\n',commit,opts.seed));
clear lib p opts
end

function run_config(rootDir,runDir,armDir,candidateId,pmax,commit)
[p,opts,baseP,baseOpts] = load_candidate(rootDir,candidateId,pmax);
lib = define_models_h2(p); a = inspect_model_pmax(lib,pmax,p);
if ~a.pass, error('Stage89QPmax:Propagation','Candidate model Pmax propagation failed.'); end
assert_zero_cuts(lib,p);
write_candidate_config(armDir,candidateId,pmax,p,opts,commit,a);
assert_parameter_isolation(baseP,baseOpts,p,opts,candidateId,pmax,armDir);
write_propagation(armDir,candidateId,pmax,p,lib,[],[],"CONFIG_PASS");
write_text(fullfile(armDir,'01_config','CONFIG_PASS.txt'),sprintf( ...
    'candidate=%s\npmax=%s\ninitial_cuts=0\n',candidateId,mat2str(pmax.')));
clear lib p baseP
end

function run_training(rootDir,armDir,candidateId,pmax,commit)
if ~isfile(fullfile(armDir,'01_config','CONFIG_PASS.txt'))
    error('Stage89QPmax:ConfigGate','CONFIG_PASS is missing.');
end
[p,opts] = load_candidate(rootDir,candidateId,pmax);
rng(opts.seed,'twister'); lib = define_models_h2(p);
assert_library(lib,p); assert_zero_cuts(lib,p); assert_model_pmax(lib,pmax,p,'fresh forward/backward library');
x=zeros(p.Ni,p.T); theta=zeros(p.T,1); lb=0; LB=zeros(10,1);
rows=cell(10,numel(training_names())); started=tic; lastPath=[];
for iter=1:10
    iterStart=tic; before=cut_count(lib,p); beforeRows=model_row_counts(lib,p);
    lastwarn(''); f0=tic;
    [lib,x,theta,lb,path,fwd]=forward_pass_h2(lib,p,lb,x,theta);
    forwardTime=toc(f0); assert_model_pmax(lib,pmax,p,sprintf('forward iteration %d',iter));
    valid=all(ismember(fwd.status,["normal","loh_demand_stage","absorbing_lfNc","dissipated_absorb","post_absorb"]));
    if ~valid || ~isfinite(lb) || any(~isfinite(x),'all')
        error('Stage89QPmax:Forward','Invalid forward pass at iteration %d.',iter);
    end
    b0=tic; [lib,cutFlag]=backward_pass_h2(lib,p,x,theta,path); backwardTime=toc(b0);
    assert_model_pmax(lib,pmax,p,sprintf('backward iteration %d',iter));
    after=cut_count(lib,p); afterRows=model_row_counts(lib,p);
    if after<=before || any(afterRows(beforeRows>0)<beforeRows(beforeRows>0))
        error('Stage89QPmax:Cuts','Cut generation failed at iteration %d.',iter);
    end
    policyModel=update_rhs_h2(lib.models{1,p.k_init},p,p.k_init,1,p.x_0);
    s=solve_stage_model_h2(policyModel); assert_solution(s,policyModel,iter,1);
    siteProd=sum(s.h2_production_hourly_kg,2); LB(iter)=lb;
    if iter==1,delta=NaN;else,delta=LB(iter)-LB(iter-1);end
    [warnMsg,warnId]=lastwarn;
    rows(iter,:)={candidateId,iter,10,lb,"NOT_FORMALLY_AVAILABLE",delta,sum(fwd.stageCost), ...
        toc(started),toc(iterStart),forwardTime,backwardTime,before,after,after-before, ...
        sum(siteProd),siteProd(1),siteProd(2),siteProd(3),siteProd(4),sum(s.xval), ...
        s.xval(1),s.xval(2),s.xval(3),s.xval(4),"OPTIMAL",string(warnId),string(warnMsg), ...
        double(all(isfinite([lb;x(:);theta(:)]))),cutFlag,"FIXED_10_ITER_ENGINEERING_SMOKE"};
    safe_writetable(cell2table(rows(1:iter,:),'VariableNames',training_names()), ...
        fullfile(armDir,'03_iteration_records','training_iteration_trace.csv'));
    lastPath=path;
    fprintf('Stage89Q-Pmax %s iteration=%d/10 LB=%.12g cuts=%d\n',candidateId,iter,lb,after);
end
trainingWall=toc(started);
[stageT,siteT,hourT,gridT,diagSummary] = diagnose_reference_path(lib,p,candidateId);
safe_writetable(stageT,fullfile(armDir,'04_stage_site_diagnostics','stage_diagnostics.csv'));
safe_writetable(siteT,fullfile(armDir,'04_stage_site_diagnostics','stage_site_diagnostics.csv'));
safe_writetable(hourT,fullfile(armDir,'04_stage_site_diagnostics','hour_site_diagnostics.csv'));
safe_writetable(gridT,fullfile(armDir,'05_grid_diagnostics','hour_grid_diagnostics.csv'));
safe_writetable(diagSummary,fullfile(armDir,'04_stage_site_diagnostics','reference_path_summary.csv'));
state=struct('x',x,'theta',theta,'LB',LB,'lb',lb,'last_training_path',lastPath);
policy=struct('stage1_x',s.xval,'stage1_production_site',siteProd);
rng_state=rng;
checkpoint_metadata=struct('stage','89Q-Pmax-SMOKE','candidate_id',candidateId, ...
    'candidate_pmax_kw',pmax(:),'source_freeze_commit',char(commit),'terminal_gap_penalty',1000, ...
    'training_seed',opts.seed,'terminal_loh_identity',char(p.terminal_loh_lookup_audit.source_sha256), ...
    'completed_iterations',10,'fresh_initial_cut_count',0,'cumulative_cuts',cut_count(lib,p), ...
    'training_wall_time_s',trainingWall,'model_schema',char(p.h2_timescale_schema), ...
    'termination_reason','EXACT_ITERATION_BUDGET_REACHED','convergence_scope','ENGINEERING_SMOKE_ONLY');
result_metadata=struct('candidate_id',candidateId,'candidate_pmax_kw',pmax(:), ...
    'completed_iterations',10,'final_lb',lb,'cut_count',cut_count(lib,p), ...
    'stage1_production_kg',sum(siteProd),'stage1_site_production_kg',siteProd(:), ...
    'stage1_end_inventory_kg',s.xval(:),'diagnostic_reference','FIXED_INITIAL_STATE_SIX_STAGE_PATH');
params=p; modelLib=lib; checkpoint=fullfile(armDir,'06_checkpoint','checkpoint_final.mat');
save_checkpoint_safe(checkpoint,params,modelLib,state,policy,opts,rng_state,checkpoint_metadata,result_metadata);
summary=table(string(candidateId),10,trainingWall,lb,cut_count(lib,p),sum(siteProd), ...
    siteProd(1),siteProd(2),siteProd(3),siteProd(4),sum(s.xval),0,string(mat2str(pmax.')), ...
    'VariableNames',{'candidate','completed_iterations','runtime_s','final_LB','cut_count', ...
    'Stage1_production_kg','Stage1_site1_kg','Stage1_site2_kg','Stage1_site3_kg','Stage1_site4_kg', ...
    'Stage1_end_inventory_kg','fresh_initial_cuts','Pmax_kw'});
safe_writetable(summary,fullfile(armDir,'02_training','training_summary.csv'));
write_propagation(armDir,candidateId,pmax,p,lib,checkpoint_metadata,result_metadata,"TRAIN_PASS");
write_text(fullfile(armDir,'02_training','TRAINING_FINISHED.txt'),sprintf( ...
    'candidate=%s\ncompleted_iterations=10\nfresh_initial_cuts=0\n',candidateId));
clear lib modelLib params p
end

function run_reload(~,armDir,candidateId,pmax,commit,checkpointSha)
checkpoint=fullfile(armDir,'06_checkpoint','checkpoint_final.mat');
if checkpointSha=="" || strlength(checkpointSha)~=64
    error('Stage89QPmax:ReloadHash','External checkpoint SHA256 is required.');
end
v=whos('-file',checkpoint); required={'params','modelLib','state','policy','opts','rng_state','checkpoint_metadata','result_metadata'};
if ~all(ismember(required,{v.name})), error('Stage89QPmax:CheckpointSchema','Checkpoint variables missing.'); end
z=load(checkpoint); p=z.params; lib=z.modelLib; m=z.checkpoint_metadata; r=z.result_metadata;
checks = [string(m.candidate_id)==candidateId; isequal(m.candidate_pmax_kw(:),pmax); ...
    isequal(p.el_cap_kw(:),pmax); isequal(p.hourly_grid.pmax_kw(:),pmax); ...
    m.terminal_gap_penalty==1000; m.training_seed==20260513; m.completed_iterations==10; ...
    m.fresh_initial_cut_count==0; string(m.source_freeze_commit)==string(commit); ...
    string(m.terminal_loh_identity)=="2fa1958944110701239a109ebf46d959324a351f2f27c1c3fbd62f333066eaa8"; ...
    string(r.candidate_id)==candidateId; isequal(r.candidate_pmax_kw(:),pmax); ...
    numel(z.state.LB)==10; all(isfinite(z.state.LB)); cut_count(lib,p)==m.cumulative_cuts];
assert_model_pmax(lib,pmax,p,'clean reload');
pm=update_rhs_h2(lib.models{1,p.k_init},p,p.k_init,1,p.x_0); s=solve_stage_model_h2(pm);
assert_solution(s,pm,0,1); checks(end+1)=all(isfinite(s.xraw));
names={'candidate_id','metadata_pmax','params_pmax','grid_copy_pmax','penalty','seed','iterations', ...
    'fresh_zero_cuts','source_commit','terminal_identity','result_candidate','result_pmax', ...
    'state_LB_length','state_LB_finite','cut_count','minimal_solve'};
T=table(string(names(:)),checks(:),repmat(string(checkpointSha),numel(checks),1), ...
    'VariableNames',{'check','pass','external_checkpoint_sha256'});
safe_writetable(T,fullfile(armDir,'06_checkpoint','checkpoint_reload_audit.csv'));
if ~all(checks), error('Stage89QPmax:ReloadIdentity','Clean reload identity gate failed.'); end
write_propagation(armDir,candidateId,pmax,p,lib,m,r,"RELOAD_PASS");
write_text(fullfile(armDir,'06_checkpoint','RELOAD_PASS.txt'),sprintf( ...
    'candidate=%s\npmax=%s\nsha256=%s\nstatus=PASS\n',candidateId,mat2str(pmax.'),checkpointSha));
clear z lib p
end

function [p,opts,baseP,baseOpts] = load_candidate(rootDir,candidateId,pmax)
[baseP,baseOpts,audit]=load_formal_stage89q_base(rootDir);
assert_base_identity(baseP,baseOpts,audit);
p=baseP; opts=baseOpts;
% The launcher vector is the sole candidate source; hourly_grid.pmax_kw is a derived identity copy.
p.el_cap_kw=pmax(:); p.hourly_grid.pmax_kw=pmax(:);
p.stage89q_pmax_candidate_id=char(candidateId); p.stage89q_pmax_source='launcher_environment_override';
opts.stage89q_pmax_candidate_id=char(candidateId); opts.stage89q_pmax_kw=pmax(:);
if ~isequal(p.el_cap_kw(:),pmax) || ~isequal(p.hourly_grid.pmax_kw(:),pmax)
    error('Stage89QPmax:Override','Candidate override did not propagate to loader output.');
end
end

function [p,opts,audit] = load_formal_stage89q_base(rootDir)
[p,opts,audit]=load_current_stage89_hourly_h2(rootDir,"dro");
% Reproduce the accepted Stage89Q load_params layer before any Pmax candidate override.
opts.seed=20260513;
opts.terminal_loh_lookup_file=char(p.terminal_loh_source);
opts.terminal_loh_expected_sha256=char(p.terminal_loh_lookup_audit.source_sha256);
p.cost_reserve_shortage=1000;
p.NearStageInput.Cost.reserve_shortage_penalty_yuan_per_kg=1000;
baseState=p.k_init; initialA=p.S(baseState,1); initialLf=p.S(baseState,3);
p.k_init=p.state_id(initialA,4,initialLf);
end

function assert_base_identity(p,opts,audit)
expectedX0=[58.04455704486949;50.30813793862475;25.262133442309338;33.02358084624278];
pass=audit.pass && p.dt_h==8 && p.T==8 && p.Ni==4 && p.hourly_grid.n_operating_stages==6 && ...
    p.hourly_grid.hours_per_stage==8 && isequal(p.x_cap(:).',[300 200 100 200]) && ...
    isequal(p.el_cap_kw(:).',[300 200 120 150]) && max(abs(p.x_0-expectedX0))<=1e-12 && ...
    string(p.demand_schema)=="original-hourly-24h-repeat-v1" && p.hourly_h2_balance_v1 && p.hourly_htt_v1 && ...
    p.htt_capacity_base==160 && p.cost_reserve_shortage==1000 && p.cost_normal_shortage==200 && ...
    p.S(p.k_init,2)==4 && ...
    p.hourly_grid.vmin_pu==0.90 && p.hourly_grid.vmax_pu==1.10 && p.hourly_grid.branch_smax_mva==6 && ...
    opts.seed==20260513 && string(p.terminal_loh_mode)=="stage89k_dro" && ...
    string(p.terminal_loh_lookup_audit.source_sha256)=="2fa1958944110701239a109ebf46d959324a351f2f27c1c3fbd62f333066eaa8";
if ~pass, error('Stage89QPmax:FormalIdentity','Formal Stage89Q Base identity mismatch.'); end
end

function assert_parameter_isolation(baseP,baseOpts,p,opts,candidateId,pmax,armDir)
fields={'P_joint','P_intensity','P_location','P_landfall','S','D_normal','x_0','x_cap','beta', ...
    'TerminalLOH','cost_reserve_shortage','cost_normal_shortage','cost_holding','cost_el_om', ...
    'cost_transport_base','htt_capacity_base','beta_transport_multiplier','site_to_site_road_km'};
rows=cell(numel(fields)+12,6); q=0;
for i=1:numel(fields)
    f=fields{i}; q=q+1; same=isequaln(baseP.(f),p.(f));
    rows(q,:)={f,'UNCHANGED',same,'formal params','candidate params',ternary(same,'PASS','UNEXPECTED_DIFF')};
end
gridFields={'tariff48','lambda48','phi48','p_load_base_kw','q_load_base_kvar','r_ohm','x_ohm', ...
    'branch_smax_mva','p_substation_max_kw','pv_cap_kw','vmin_pu','vmax_pu'};
for i=1:numel(gridFields)
    f=gridFields{i}; q=q+1; same=isequaln(baseP.hourly_grid.(f),p.hourly_grid.(f));
    rows(q,:)={"hourly_grid."+f,'UNCHANGED',same,'formal grid','candidate grid',ternary(same,'PASS','UNEXPECTED_DIFF')};
end
rows=rows(1:q,:); T=cell2table(rows,'VariableNames',{'parameter','expected_change','pass','base','candidate','status'});
extra=cell2table({ 'Pmax','ALLOWED',isequal(p.el_cap_kw(:),pmax),mat2str(baseP.el_cap_kw.'),mat2str(pmax.'),'PASS'; ...
    'max_iterations','ALLOWED',true,'Stage89Q wall clock','10','PASS'; 'output_path','ALLOWED',true,'Base output unchanged',armDir,'PASS'; ...
    'candidate_identity','ALLOWED',string(opts.stage89q_pmax_candidate_id)==candidateId,'Base',candidateId,'PASS'; ...
    'diagnostic_logging','ALLOWED',true,'formal logging','smoke diagnostics','PASS'},'VariableNames',T.Properties.VariableNames);
T=[T;extra]; safe_writetable(T,fullfile(armDir,'01_config','parameter_diff.csv'));
if ~all(T.pass) || baseOpts.seed~=opts.seed, error('Stage89QPmax:Isolation','Unexpected parameter diff.'); end
end

function write_candidate_config(armDir,candidateId,pmax,p,opts,commit,a)
T=table(string(candidateId),string(mat2str(pmax.')),1000,opts.seed,10,string(commit), ...
    string(p.terminal_loh_lookup_audit.source_sha256),p.dt_h,p.hourly_grid.n_operating_stages, ...
    p.hourly_grid.hours_per_stage,string(mat2str(p.x_cap.')),string(p.demand_schema),p.htt_capacity_base, ...
    p.hourly_grid.vmin_pu,p.hourly_grid.vmax_pu,p.hourly_grid.branch_smax_mva,a.model_count,a.pass, ...
    'VariableNames',{'candidate_id','Pmax_kw','terminal_gap_penalty','training_seed','max_iterations', ...
    'source_commit','TerminalLOH_sha256','dt_h','operating_stages','hours_per_stage','tank_capacity_kg', ...
    'ordinary_demand_schema','HTT_hourly_capacity_kg','voltage_min_pu','voltage_max_pu', ...
    'branch_limit_mva','active_model_count','model_bound_audit_pass'});
safe_writetable(T,fullfile(armDir,'01_config','candidate_config.csv'));
end

function write_propagation(armDir,candidateId,pmax,p,lib,checkpointMetadata,resultMetadata,status)
observed=mat2str(pmax.'); expected=observed; a=inspect_model_pmax(lib,pmax,p);
rows={
    '1_launcher_override',observed,expected,true,'STAGE89Q_PMAX_VECTOR';
    '2_options_config',mat2str(p.el_cap_kw.'),expected,isequal(p.el_cap_kw(:),pmax),'candidate wrapper output';
    '3_loader_output',mat2str(p.el_cap_kw.'),expected,isequal(p.el_cap_kw(:),pmax),'formal loader then isolated override';
    '4_data_model_struct',mat2str(p.hourly_grid.pmax_kw.'),expected,isequal(p.hourly_grid.pmax_kw(:),pmax),'derived grid identity copy';
    '5_variable_upper_bound',a.hourly_bound_vector,expected,a.pass,'all active model idx.p_el_hourly bounds';
    '6_hourly_constraint_rhs',a.hourly_bound_vector,expected,a.pass,'P_EL limit encoded as variable upper bound, not b RHS';
    '7_forward_model',a.hourly_bound_vector,expected,a.pass,'same modelLib passed to forward_pass_h2';
    '8_backward_model',a.hourly_bound_vector,expected,a.pass,'same modelLib passed to backward_pass_h2';
    '9_checkpoint_metadata','PENDING',expected,false,'available after training';
    '10_result_metadata','PENDING',expected,false,'available after training';
    '11_qa_identity',observed,expected,true,char(status)};
if ~isempty(checkpointMetadata)
    rows{9,2}=mat2str(checkpointMetadata.candidate_pmax_kw.'); rows{9,4}=isequal(checkpointMetadata.candidate_pmax_kw(:),pmax);
end
if ~isempty(resultMetadata)
    rows{10,2}=mat2str(resultMetadata.candidate_pmax_kw.'); rows{10,4}=isequal(resultMetadata.candidate_pmax_kw(:),pmax);
end
T=cell2table(rows,'VariableNames',{'level','observed_Pmax_kw','expected_Pmax_kw','pass','evidence'});
safe_writetable(T,fullfile(armDir,'09_qa','pmax_propagation.csv'));
if status=="RELOAD_PASS" && ~all(T.pass), error('Stage89QPmax:PropagationFinal','Final propagation table failed.'); end
end

function a=inspect_model_pmax(lib,pmax,p)
count=0; pass=true; aggregate=true; hourly=true;
for t=1:6
    for k=1:p.K
        m=lib.models{t,k}; if isempty(m),continue;end; count=count+1;
        aggregate=aggregate&&isequal(m.ub(m.idx.e),pmax(:));
        hourly=hourly&&isequal(reshape(m.ub(m.idx.p_el_hourly),4,8),repmat(pmax(:),1,8));
    end
end
pass=aggregate&&hourly&&count>0;
a=struct('model_count',count,'aggregate_bounds_pass',aggregate,'hourly_bounds_pass',hourly, ...
    'hourly_bound_vector',mat2str(pmax.'),'pass',pass);
end

function assert_model_pmax(lib,pmax,p,where)
a=inspect_model_pmax(lib,pmax,p);
if ~a.pass,error('Stage89QPmax:ModelPmax','Pmax mismatch at %s.',where);end
end

function [stageT,siteT,hourT,gridT,summaryT]=diagnose_reference_path(lib,p,candidateId)
prev=p.x_0(:); stageRows=cell(6,15); siteRows=cell(24,20); hourRows=cell(192,24); gridRows=cell(48,18);
sr=0; rr=0; hr=0; gr=0;
for t=1:6
    k=p.k_init; m=update_rhs_h2(lib.models{t,k},p,k,t,prev); s=solve_stage_model_h2(m); assert_solution(s,m,0,t);
    v=sqrt(max(s.v_sq,0)); trueS=hypot(s.p_branch_kw,s.q_branch_kvar)/1000;
    production=sum(s.h2_production_hourly_kg,'all'); shortage=sum(s.z_normal_hourly_kg,'all'); flow=s.f_hourly_kg;
    sr=sr+1; stageRows(sr,:)={candidateId,t,k,sum(prev),sum(s.xval),production,shortage,sum(flow,'all'), ...
        sum(s.p_el_hourly_kw,'all')/(8*sum(p.el_cap_kw)),mean(s.xval./p.x_cap), ...
        min(v,[],'all'),max(trueS,[],'all')/p.hourly_grid.branch_smax_mva, ...
        max(s.p_grid_kw)/p.hourly_grid.p_substation_max_kw,sum(s.p_el_hourly_kw(:,1:4),'all')/max(sum(s.p_el_hourly_kw,'all'),eps), ...
        sum(s.p_el_hourly_kw(:,5:8),'all')/max(sum(s.p_el_hourly_kw,'all'),eps)};
    for i=1:4
        rr=rr+1; pel=s.p_el_hourly_kw(i,:); inv=s.h2_inventory_hourly_kg(i,:);
        siteRows(rr,:)={candidateId,t,i,p.el_cap_kw(i),sum(pel),mean(pel)/p.el_cap_kw(i),max(pel), ...
            sum(pel>=0.90*p.el_cap_kw(i)),sum(pel>=0.95*p.el_cap_kw(i)),sum(pel>=0.99*p.el_cap_kw(i)), ...
            sum(s.h2_production_hourly_kg(i,:)),prev(i),s.xval(i),sum(s.z_normal_hourly_kg(i,:)), ...
            sum(s.htt_in_hourly_kg(i,:)),sum(s.htt_out_hourly_kg(i,:)),p.x_cap(i)-s.xval(i), ...
            sum(inv>=p.x_cap(i)-1e-6),sum(inv>=0.99*p.x_cap(i)),std(pel)};
        for h=1:8
            hr=hr+1; beginInv=prev(i); if h>1,beginInv=s.h2_inventory_hourly_kg(i,h-1);end
            hourRows(hr,:)={candidateId,t,h,8*(t-1)+h,i,p.hourly_grid.site_elec_bus(i),p.el_cap_kw(i), ...
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
        gr=gr+1; [vmin,bus]=min(v(:,h)); [lineMva,line]=max(trueS(:,h));
        grFlow=sum(flow(:,:,h),'all'); cap=max(0,(1-p.beta(k))*p.htt_capacity_base);
        gridRows(gr,:)={candidateId,t,h,8*(t-1)+h,vmin,bus,v(18,h),vmin<=p.hourly_grid.vmin_pu+1e-6, ...
            lineMva,line,lineMva/p.hourly_grid.branch_smax_mva,lineMva>=p.hourly_grid.branch_smax_mva-1e-6, ...
            s.p_grid_kw(h),s.p_grid_kw(h)/p.hourly_grid.p_substation_max_kw, ...
            s.p_grid_kw(h)>=p.hourly_grid.p_substation_max_kw-1e-6,grFlow,cap,ternary(cap>0,grFlow/cap,0)};
    end
    prev=s.xval;
end
stageT=cell2table(stageRows,'VariableNames',{'candidate','stage','state_id','begin_inventory_kg','end_inventory_kg', ...
    'production_kg','ordinary_shortage_kg','HTT_kg','Pmax_utilization','tank_fill_mean', ...
    'Vmin_pu','max_line_utilization','max_substation_utilization','first4h_production_share','last4h_production_share'});
siteT=cell2table(siteRows,'VariableNames',{'candidate','stage','site','Pmax_kW','P_EL_kWh','mean_Pmax_utilization', ...
    'max_P_EL_kW','hours_ge90pct','hours_ge95pct','hours_ge99pct','production_kg','begin_inventory_kg', ...
    'end_inventory_kg','ordinary_shortage_kg','HTT_in_kg','HTT_out_kg','tank_headroom_kg', ...
    'tank_capacity_hits','near_tank_capacity_hours','P_EL_std_kW'});
hourT=cell2table(hourRows,'VariableNames',{'candidate','stage','hour_in_stage','global_hour','site','bus','Pmax_kW', ...
    'P_EL_kW','Pmax_utilization','production_kg','begin_inventory_kg','inventory_pre_HTT_kg','end_inventory_kg', ...
    'tank_capacity_kg','tank_headroom_kg','ordinary_demand_kg','ordinary_served_kg','ordinary_shortage_kg', ...
    'HTT_in_kg','HTT_out_kg','site_voltage_pu','P_EL_ge90pct','P_EL_ge99pct','tank_binding'});
gridT=cell2table(gridRows,'VariableNames',{'candidate','stage','hour_in_stage','global_hour','Vmin_pu','critical_bus', ...
    'bus18_voltage_pu','voltage_binding','max_line_mva','critical_line','line_utilization','branch_binding', ...
    'substation_import_kW','substation_utilization','substation_binding','HTT_kg','HTT_capacity_kg','HTT_utilization'});
summaryT=table(string(candidateId),sum(stageT.production_kg),sum(stageT.ordinary_shortage_kg),sum(stageT.HTT_kg), ...
    sum(stageT.production_kg(stageT.stage>=5))/sum(stageT.production_kg),min(gridT.Vmin_pu),min(gridT.bus18_voltage_pu), ...
    max(gridT.line_utilization),max(gridT.substation_utilization),max(gridT.HTT_utilization), ...
    'VariableNames',{'candidate','stage1_6_production_kg','ordinary_shortage_kg','HTT_kg','late_stage5_6_share', ...
    'Vmin_pu','bus18_Vmin_pu','max_line_utilization','max_substation_utilization','max_HTT_utilization'});
end

function assert_solution(s,m,iter,t)
eq=max(abs(m.Aeq*s.xraw-m.beq)); ineq=max([0;m.A*s.xraw-m.b]);
if any(~isfinite(s.xraw)) || eq>1e-6 || ineq>1e-6
    error('Stage89QPmax:Numerical','Invalid solve at iteration %d stage %d: eq=%g ineq=%g.',iter,t,eq,ineq);
end
end

function [candidateId,pmax,armDir]=arm_spec(runDir,arm,pmaxText)
if arm=="B0001",candidateId="ARM-B0001";expected=[300;200;120;187.5];folder='02_arm_b0001';
elseif arm=="B1011",candidateId="ARM-B1011";expected=[375;200;150;187.5];folder='03_arm_b1011';
else,error('Stage89QPmax:Arm','Unknown arm %s.',arm);end
tokens=str2double(split(pmaxText,','));pmax=tokens(:);
if numel(pmax)~=4||any(~isfinite(pmax))||~isequal(pmax,expected)
    error('Stage89QPmax:ArmPmax','Arm %s expected %s, got %s.',arm,mat2str(expected.'),pmaxText);
end
armDir=fullfile(runDir,folder);
end

function assert_library(lib,p)
for t=1:6
    present=lib.models(t,:);present=present(~cellfun(@isempty,present));
    if isempty(present)||~all(cellfun(@(m)m.hourly_grid_enabled&&m.hourly_h2_balance_enabled&&m.hourly_htt_enabled&&m.nvars==1129,present))
        error('Stage89QPmax:Library','Invalid Stage89Q model library at stage %d.',t);
    end
end
end
function assert_zero_cuts(lib,p),if cut_count(lib,p)~=0,error('Stage89QPmax:WarmStart','Fresh library contains cuts.');end,end
function n=cut_count(lib,p),r=model_row_counts(lib,p);n=sum(max(0,r-base_rows(p)),'all');end
function rows=model_row_counts(lib,p),rows=zeros(6,p.K);for t=1:6,for k=1:p.K,m=lib.models{t,k};if ~isempty(m),rows(t,k)=size(m.A,1);end,end,end,end
function n=base_rows(p),n=8+4*8+8*8*p.hourly_grid.n_branch;end

function save_checkpoint_safe(path,params,modelLib,state,policy,opts,rng_state,checkpoint_metadata,result_metadata)
tmp=[path '.tmp.mat'];save(tmp,'params','modelLib','state','policy','opts','rng_state','checkpoint_metadata','result_metadata','-v7.3');
v=whos('-file',tmp);required={'params','modelLib','state','policy','opts','rng_state','checkpoint_metadata','result_metadata'};
if ~all(ismember(required,{v.name})),error('Stage89QPmax:CheckpointWrite','Incomplete checkpoint.');end
movefile(tmp,path,'f');
end
function safe_writetable(T,path),[d,n,e]=fileparts(path);tmp=fullfile(d,[n '.tmp' e]);writetable(T,tmp);movefile(tmp,path,'f');end
function write_text(path,value),fid=fopen(path,'w');if fid<0,error('Stage89QPmax:Write','Cannot write %s.',path);end;c=onCleanup(@()fclose(fid));fprintf(fid,'%s',char(value));end %#ok<NASGU>
function value=ternary(condition,a,b),if condition,value=a;else,value=b;end,end
function n=training_names(),n={'candidate','iteration_id','iteration_budget','LB','UB_estimate','LB_increment', ...
    'forward_sampled_objective','elapsed_seconds','iteration_runtime_s','forward_runtime_s','backward_runtime_s', ...
    'cuts_before','cut_count','cuts_added','Stage1_production_kg','Stage1_site1_production_kg', ...
    'Stage1_site2_production_kg','Stage1_site3_production_kg','Stage1_site4_production_kg', ...
    'Stage1_end_inventory_kg','Stage1_site1_inventory_kg','Stage1_site2_inventory_kg', ...
    'Stage1_site3_inventory_kg','Stage1_site4_inventory_kg','solver_status','warning_id','warning_message', ...
    'numerical_finite','cut_violation_flag','scope'};end
