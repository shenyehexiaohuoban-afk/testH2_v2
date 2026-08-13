function run_stage84_formal_training_oos_h2()
%RUN_STAGE84_FORMAL_TRAINING_OOS_H2 Frozen long training and timed OOS.

rootDir=fileparts(fileparts(mfilename('fullpath')));
addpath(rootDir); addpath(fullfile(rootDir,'fa_h2'));
addpath(fullfile(rootDir,'fa_h2','fuzhu')); addpath(fullfile(rootDir,'utils'));
addpath(fullfile(rootDir,'hourly_grid_h2'));
if strcmp(getenv('STAGE84_PREFLIGHT'),'1')
    run_preflight(rootDir); return;
end
runId=char(string(getenv('STAGE84_RUN_ID'))); if isempty(runId),runId='run-001';end
frozenCommit=strtrim(string(getenv('STAGE84_FROZEN_COMMIT')));
if frozenCommit=="",error('Stage84:MissingFrozenCommit','STAGE84_FROZEN_COMMIT is required.');end
[st,head]=system('git rev-parse HEAD'); head=strtrim(string(head));
if st~=0 || head~=frozenCommit,error('Stage84:CommitMismatch','HEAD %s != frozen %s.',head,frozenCommit);end
runDir=fullfile(rootDir,'results','task-002-stage2b-b3-smoke', ...
    '84-hourly-grid-formal-training-oos',runId);
if exist(runDir,'dir'),error('Stage84:OutputExists','Refusing to overwrite %s.',runDir);end
make_run_dirs(runDir); diary(fullfile(runDir,'logs','stage84_matlab_diary.txt'));
pid=feature('getpid'); write_status(runDir,'RUNNING','PREPARING','NONE',0,0,0,"",pid,frozenCommit);
try
    identity=build_identity(rootDir,frozenCommit);
    save_identity(runDir,identity);
    saa=train_one(rootDir,runDir,"saa",22200,identity,pid,frozenCommit);
    if ~saa.pass,error('Stage84:SAAFailure','SAA structural gate failed.');end
    dro=train_one(rootDir,runDir,"chi2_eta003",22200,identity,pid,frozenCommit);
    if ~dro.pass,error('Stage84:DROFailure','DRO structural gate failed.');end
    write_status(runDir,'RUNNING','BUILDING_OOS_PATH_BANK','BOTH',0,0,0,"",pid,frozenCommit);
    [pathBank,pathManifest]=build_path_bank(saa.params,10000,20260513+2000);
    oosDir=fullfile(runDir,'03-common-oos-paths');
    writetable(pathManifest,fullfile(oosDir,'oos_path_manifest.csv'));
    save(fullfile(oosDir,'oos_path_bank.mat'),'pathBank','-v7.3');
    write_oos_manifest(oosDir,saa.params,identity,20260513+2000);
    clear pathManifest
    saaOos=stage84_timed_oos_h2(saa.checkpoint,pathBank,1800, ...
        fullfile(runDir,'04-saa-oos'),"saa",runDir,pid,frozenCommit);
    droOos=stage84_timed_oos_h2(dro.checkpoint,pathBank,1800, ...
        fullfile(runDir,'05-dro-oos'),"chi2_eta003",runDir,pid,frozenCommit);
    write_status(runDir,'RUNNING','FINALIZING','BOTH',0,0,0,"",pid,frozenCommit);
    final=finalize_run(runDir,saa,dro,saaOos,droOos,frozenCommit);
    write_status(runDir,ternary(final.pass,'COMPLETE','FAILED'), ...
        ternary(final.pass,'COMPLETE','FAILED'),'BOTH',0,0,final.n_common,"",pid,frozenCommit);
catch ME
    write_failure(runDir,ME); write_status(runDir,'FAILED','FAILED','NONE',0,0,0,"",pid,frozenCommit);
    diary off; rethrow(ME);
end
diary off;
end

function run_preflight(rootDir)
assert_accepted_gate(rootDir);
baseDir=fullfile(rootDir,'results','task-002-stage2b-b3-smoke','84-hourly-grid-formal-training-oos');
preflightId=1;outDir=fullfile(baseDir,sprintf('preflight-run-%03d',preflightId));
while exist(outDir,'dir')
    preflightId=preflightId+1;outDir=fullfile(baseDir,sprintf('preflight-run-%03d',preflightId));
end
mkdir(outDir); mkdir(fullfile(outDir,'oos-output-probe'));
methods=["saa","chi2_eta003"]; rows=cell(2,8);
for j=1:2
    opts=frozen_options(rootDir,methods(j),22200);
    rng(opts.seed,'twister'); p=load_data_h2_near(opts.dataDir,opts.nearInputFile,opts);
    assert_identity(p,opts,methods(j)); lib=define_models_h2(p); assert_library(lib,p);
    initialCuts=cut_count(lib,p); fresh=initialCuts==0;
    probe=struct('method',methods(j),'initial_cuts',initialCuts,'fresh_model',fresh, ...
        'trace_writable',false,'status_writable',false);
    trace=table(methods(j),1,0,0,NaN,NaN,NaN,0,0,0,0,0,0,0,"NONE", ...
        'VariableNames',trace_names());
    traceFile=fullfile(outDir,char(methods(j)+"_training_trace_probe.csv")); writetable(trace,traceFile);
    statusFile=fullfile(outDir,char(methods(j)+"_status_probe.txt")); write_text(statusFile,"STATUS=PASS"+newline);
    probe.trace_writable=isfile(traceFile); probe.status_writable=isfile(statusFile);
    temp=fullfile(outDir,char(methods(j)+"_checkpoint_probe.tmp.mat"));
    final=fullfile(outDir,char(methods(j)+"_checkpoint_probe.mat"));
    save(temp,'probe'); vars=whos('-file',temp); movefile(temp,final);
    checkpointPass=isfile(final) && any(strcmp({vars.name},'probe'));
    rows(j,:)={methods(j),p.enable_hourly_grid,p.dt_h,initialCuts,fresh, ...
        all(cellfun(@isempty,lib.models(7:8,:)),'all'),checkpointPass,probe.trace_writable&&probe.status_writable};
    clear lib p
end
tbl=cell2table(rows,'VariableNames',{'method','hourly_grid','dt_h','initial_cuts', ...
    'fresh_model','stage7_8_empty','checkpoint_write_reload','trace_status_write'});
writetable(tbl,fullfile(outDir,'preflight_checks.csv'));
pass=all(tbl.hourly_grid)&all(tbl.dt_h==8)&all(tbl.fresh_model)& ...
    all(tbl.stage7_8_empty)&all(tbl.checkpoint_write_reload)&all(tbl.trace_status_write);
write_text(fullfile(outDir,'final_judgment.txt'),"PREFLIGHT="+ternary(pass,"PASS","FAIL")+newline+ ...
    "long_training_started=false"+newline+"gurobi_solve_started=false"+newline);
if ~pass,error('Stage84:PreflightFailure','Preflight failed.');end
end

function result=train_one(rootDir,runDir,method,budget,identity,pid,frozenCommit)
if method=="saa",caseDir=fullfile(runDir,'01-saa-training'); phase="SAA_TRAINING";
else,caseDir=fullfile(runDir,'02-dro-training');phase="DRO_TRAINING";end
opts=frozen_options(rootDir,method,budget); rng(opts.seed,'twister');
p=load_data_h2_near(opts.dataDir,opts.nearInputFile,opts); assert_identity(p,opts,method);
lib=define_models_h2(p); assert_library(lib,p);
if cut_count(lib,p)~=0,error('Stage84:NotFresh','%s did not start from zero cuts.',method);end
write_status(runDir,'RUNNING',phase,method,0,0,0,"",pid,frozenCommit);
traceFile=fullfile(caseDir,'training_trace.csv'); trace=empty_trace(); writetable(trace,traceFile);
state=struct('x',zeros(p.Ni,p.T),'theta',zeros(p.T,1),'lb',0,'cutviol_iter',0, ...
    'iteration',0,'pure_time_s',0,'forward_count',0,'backward_count',0, ...
    'forward_solves',0,'backward_solves',0,'latest_checkpoint',"NONE", ...
    'latest_checkpoint_time',"",'next_checkpoint_s',1800,'stop_flag',0);
monitor=init_monitor(p); checkpointIndex=0; LB=[]; startWall=datetime('now');
while true
    state.iteration=state.iteration+1; f0=tic;
    [lib,state.x,state.theta,state.lb,path,fwd]=forward_pass_h2(lib,p,state.lb,state.x,state.theta);
    ftime=toc(f0); state.pure_time_s=state.pure_time_s+ftime; state.forward_count=state.forward_count+1;
    fsolves=nnz(fwd.status=="normal"); state.forward_solves=state.forward_solves+fsolves;
    if ~isfinite(state.lb)||any(~isfinite(state.x),'all'),error('Stage84:NonFinite','Nonfinite forward state/LB.');end
    LB(end+1,1)=state.lb; btime=0; added=0; backwardDone=false;
    beforeCuts=cut_count(lib,p);
    if state.pure_time_s<budget
        b0=tic; [lib,cutFlag]=backward_pass_h2(lib,p,state.x,state.theta,path); btime=toc(b0);
        state.pure_time_s=state.pure_time_s+btime; state.backward_count=state.backward_count+1;
        state.backward_solves=state.backward_solves+expected_backward_solves(p); backwardDone=true;
        if cutFlag==1,state.cutviol_iter=0;else,state.cutviol_iter=state.cutviol_iter+1;end
        added=cut_count(lib,p)-beforeCuts;
    end
    totalCuts=beforeCuts+added; inc=NaN; rel=NaN;
    if numel(LB)>1,inc=LB(end)-LB(end-1);rel=inc/max(1,abs(LB(end-1)));end
    cycle=ftime+btime;
    row=table(method,state.iteration,state.pure_time_s,cycle,LB(end),inc,rel,totalCuts,added, ...
        state.forward_count,state.backward_count,ftime,btime,fsolves+double(backwardDone)*expected_backward_solves(p), ...
        state.latest_checkpoint,'VariableNames',trace_names());
    trace=[trace;row]; writetable(trace,traceFile);
    write_status(runDir,'RUNNING',phase,method,state.iteration,state.pure_time_s,0,state.latest_checkpoint,pid,frozenCommit);
    fprintf('Stage84 %s iter=%d pure=%.3f LB=%.12g cuts=%d\n',method,state.iteration,state.pure_time_s,LB(end),totalCuts);
    if backwardDone && state.pure_time_s>=state.next_checkpoint_s
        checkpointIndex=checkpointIndex+1; checkpointId=sprintf('checkpoint_%03d.mat',checkpointIndex);
        cp=fullfile(runDir,'checkpoints',char(method),checkpointId);
        checkpoint_metadata=make_cp_metadata(method,budget,frozenCommit,identity,opts,state,LB,totalCuts,"PERIODIC");
        save_checkpoint_safe(cp,p,lib,state,LB,monitor,opts,checkpoint_metadata);
        state.latest_checkpoint=string(checkpointId);
        state.latest_checkpoint_time=string(datetime('now','Format','yyyy-MM-dd HH:mm:ss'));
        state.next_checkpoint_s=state.next_checkpoint_s+1800;
        write_status(runDir,'RUNNING',phase,method,state.iteration,state.pure_time_s,0,state.latest_checkpoint,pid,frozenCommit);
    end
    if state.pure_time_s>=budget,break;end
end
monitor.forward_passes=state.forward_count;monitor.backward_passes=state.backward_count;
monitor.forward_operating_solves=state.forward_solves;monitor.backward_operating_solves=state.backward_solves;
monitor.wall_time_s=state.pure_time_s;
finalCp=fullfile(runDir,'checkpoints',char(method),'checkpoint_final.mat'); totalCuts=cut_count(lib,p);
state.stop_flag=2;
checkpoint_metadata=make_cp_metadata(method,budget,frozenCommit,identity,opts,state,LB,totalCuts,"FINAL");
save_checkpoint_safe(finalCp,p,lib,state,LB,monitor,opts,checkpoint_metadata);
clear lib p
loaded=load(finalCp); [reloadPass,reloadAudit]=verify_final_checkpoint(loaded,method);
writetable(struct2table(reloadAudit),fullfile(caseDir,'checkpoint_reload_audit.csv'));
if ~reloadPass,error('Stage84:FinalCheckpointReload','%s final checkpoint reload failed.',method);end
diagPhase=ternary(method=="saa",'SAA_DIAGNOSTIC','DRO_DIAGNOSTIC');
write_status(runDir,'RUNNING',diagPhase,method,loaded.state.iteration,loaded.state.pure_time_s,0,"checkpoint_final.mat",pid,frozenCommit);
diagnosis=stage84_lightweight_diagnostic_h2(loaded.modelLib,loaded.params,20260513+1000,40);
diagPass=diagnosis.pass; save(fullfile(caseDir,'lightweight_diagnostic.mat'),'diagnosis');
writetable(struct2table(rmfield(diagnosis,{'site_average_p_el_kw','site_grid_limited_frequency'})), ...
    fullfile(caseDir,'lightweight_diagnostic_summary.csv'));
writetable(table((1:4).',diagnosis.site_average_p_el_kw(:),diagnosis.site_grid_limited_frequency(:), ...
    'VariableNames',{'site','average_p_el_kw','grid_limited_frequency'}),fullfile(caseDir,'site_diagnostic.csv'));
metadata=write_training_metadata(caseDir,method,budget,startWall,loaded.state,loaded.LB,totalCuts,frozenCommit,opts,finalCp,reloadPass,diagPass);
pass=reloadPass&&diagPass&&loaded.state.pure_time_s>=budget&&loaded.params.Ni==4;
completePhase=ternary(method=="saa",'SAA_COMPLETE','DRO_COMPLETE');
write_status(runDir,ternary(pass,'RUNNING','FAILED'),completePhase,method,loaded.state.iteration,loaded.state.pure_time_s,0,"checkpoint_final.mat",pid,frozenCommit);
result=struct('pass',pass,'checkpoint',finalCp,'params',loaded.params,'metadata',metadata);
clear loaded
end

function opts=frozen_options(rootDir,method,budget)
opts=h2_default_options(rootDir); inputRoot=fullfile(rootDir,'results','task-002-stage2b-b3-smoke', ...
    '73-htt-transport-cost-sensitivity','run-001','H02'); lookupRoot=fullfile(rootDir,'results', ...
    'task-002-stage2b-b3-smoke','53-35state-saa-vs-eta003-terminal-loh','run-024');
opts.nearInputFile=fullfile(inputRoot,"case-"+method,'sensitivity_input.mat');opts.dt_h=8;
opts.time_limit=budget;opts.max_iter=1000000;opts.stall=1000000;opts.cutviol_maxiter=1000000;
opts.enable_hourly_grid=true;opts.hourly_grid_vmin_pu=0.90;opts.hourly_grid_vmax_pu=1.10;
opts.seed=20260513;opts.allow_zero_terminal_loh=true;opts.terminal_loh_mode=char(method);
if method=="saa",opts.terminal_loh_lookup_file=fullfile(lookupRoot,'terminal_loh_table_saa.csv');
else,opts.terminal_loh_lookup_file=fullfile(lookupRoot,'terminal_loh_table_eta_003.csv');end
end

function assert_identity(p,opts,method)
if ~p.enable_hourly_grid||p.T~=8||p.hourly_grid.n_operating_stages~=6||p.dt_h~=8|| ...
 max(abs(p.el_cap_kw-[300;200;120;150]))>1e-12||abs(p.k_H2-0.0195)>1e-12|| ...
 max(abs(p.x_cap-[300;200;100;150]))>1e-12||abs(p.htt_capacity_base-160)>1e-12|| ...
 max(abs(p.hourly_grid.site_elec_bus-[24;14;18;31]))>0||p.hourly_grid.vmin_pu~=0.90|| ...
 p.hourly_grid.vmax_pu~=1.10||p.hourly_grid.branch_smax_mva~=6|| ...
 any(abs(p.hourly_grid.pv_cap_kw-200)>1e-12)||string(p.terminal_loh_mode)~=method|| ...
 max(abs(p.cost_transport_base-0.2*p.site_to_site_road_km),[],'all')>1e-10|| ...
 ~isfile(opts.nearInputFile)||~isfile(opts.terminal_loh_lookup_file)
 error('Stage84:IdentityMismatch','Frozen identity mismatch for %s.',method);end
end

function assert_library(lib,p)
for t=1:p.T
 c=lib.models(t,:);if t<=6,n=c(~cellfun(@isempty,c));
  if isempty(n)||~all(cellfun(@(m)m.hourly_grid_enabled,n)),error('Stage84:Library','Bad stage %d.',t);end
 elseif any(~cellfun(@isempty,c)),error('Stage84:TerminalLibrary','Stage %d must be empty.',t);end
end
end

function save_checkpoint_safe(path,p,modelLib,state,LB,monitor,opts,checkpoint_metadata)
params=p;policy=struct('representation','modelLib_with_embedded_cuts','state_order','I1,I2,I3,I4');
rng_state=rng; temp=[char(path) '.tmp.mat']; save(temp,'params','modelLib','policy','state','LB','monitor','opts', ...
    'rng_state','checkpoint_metadata','-v7.3'); vars=whos('-file',temp);
required={'params','modelLib','policy','state','LB','monitor','opts','rng_state','checkpoint_metadata'};
if ~all(ismember(required,{vars.name})),error('Stage84:CheckpointWrite','Incomplete temp checkpoint %s.',temp);end
movefile(temp,char(path),'f');
end

function [pass,a]=verify_final_checkpoint(c,method)
req={'params','modelLib','policy','state','LB','monitor','opts','rng_state','checkpoint_metadata'};
has=all(isfield(c,req)); cuts=cut_count(c.modelLib,c.params); [dimPass,terminalPass]=cut_dimension(c.modelLib,c.params);
iterPass=c.state.iteration==numel(c.LB)&&c.state.iteration==c.checkpoint_metadata.iteration;
lbPass=abs(c.LB(end)-c.checkpoint_metadata.final_LB)<=1e-10;methodPass=string(c.checkpoint_metadata.method)==method;
pass=has&&cuts==c.checkpoint_metadata.cumulative_cuts&&dimPass&&terminalPass&&iterPass&&lbPass&&methodPass;
a=struct('has_required_fields',has,'cut_count',cuts,'cut_dimension_pass',dimPass, ...
 'stage7_8_empty',terminalPass,'iteration_match',iterPass,'LB_match',lbPass,'method_match',methodPass,'reload_pass',pass);
end

function m=make_cp_metadata(method,budget,commit,identity,opts,state,LB,cuts,kind)
m=struct('method',method,'eta',ternary(method=="saa",0,0.03),'kind',kind,'requested_budget_s',budget, ...
 'iteration',state.iteration,'cumulative_training_time_s',state.pure_time_s,'final_LB',LB(end), ...
 'cumulative_cuts',cuts,'seed',opts.seed,'frozen_commit',commit,'input_identity',identity, ...
 'saved_at',string(datetime('now','Format','yyyy-MM-dd HH:mm:ss')),'stop_state',ternary(kind=="FINAL",2,0));
end

function [pass,terminalPass]=cut_dimension(lib,p)
pass=true;terminalPass=all(cellfun(@isempty,lib.models(7:8,:)),'all');base=5+8*8*p.hourly_grid.n_branch;
for t=1:6,for k=1:p.K,m=lib.models{t,k};if isempty(m),continue;end
 allowed=false(1,m.nvars);allowed(m.idx.x)=true;allowed(m.idx.theta)=true;
 for r=base+1:size(m.A,1),pass=pass&&numel(m.idx.x)==4&&nnz(m.A(r,~allowed))==0;end
end,end
end

function n=cut_count(lib,p)
n=0;base=5+8*8*p.hourly_grid.n_branch;
for t=1:6,for k=1:p.K,m=lib.models{t,k};if ~isempty(m),n=n+max(0,size(m.A,1)-base);end,end,end
end
function n=expected_backward_solves(p),n=5*nnz(~p.is_absorbing&~p.is_loh_demand_stage);end
function m=init_monitor(p),m=struct('forward_passes',0,'backward_passes',0,'forward_operating_solves',0, ...
 'backward_operating_solves',0,'solver_errors',0,'invalid_duals',0,'balance_violations',0, ...
 'grid_violations',0,'stage7_hourly_calls',0,'stage8_hourly_calls',0,'wall_time_s',0,'state_dimension',p.Ni);end

function t=empty_trace()
t=table(strings(0,1),zeros(0,1),zeros(0,1),zeros(0,1),zeros(0,1),zeros(0,1), ...
    zeros(0,1),zeros(0,1),zeros(0,1),zeros(0,1),zeros(0,1),zeros(0,1), ...
    zeros(0,1),zeros(0,1),strings(0,1),'VariableNames',trace_names());
end
function n=trace_names(),n={'method','iteration','cumulative_training_time_s','cycle_time_s','LB','LB_increment', ...
 'relative_LB_increment','cumulative_cuts','cuts_added','forward_count','backward_count','forward_wall_time_s', ...
 'backward_wall_time_s','number_of_stage_solves','latest_checkpoint_id'};end

function [bank,manifest]=build_path_bank(p,n,seed)
rng(seed,'twister');bank=zeros(n,p.T);bank(:,1)=p.k_init;
for s=1:n,for t=2:p.T,bank(s,t)=mc_sample(bank(s,t-1),p.P_joint);end,end
ids=(1:n).'; vars=arrayfun(@(t)sprintf('k_t%d',t),1:p.T,'UniformOutput',false);
manifest=[table(ids,'VariableNames',{'path_id'}),array2table(bank,'VariableNames',vars)];
end

function final=finalize_run(runDir,saa,dro,so,do,commit)
n=min(so.completed_paths,do.completed_paths);s=readtable(fullfile(runDir,'04-saa-oos','oos_path_summary.csv'));
d=readtable(fullfile(runDir,'05-dro-oos','oos_path_summary.csv'));s=s(1:n,:);d=d(1:n,:);
comp=table(s.path_id,s.total_cost,d.total_cost,d.total_cost-s.total_cost,s.total_production_kg,d.total_production_kg, ...
 d.total_production_kg-s.total_production_kg,s.total_htt_kg,d.total_htt_kg,d.total_htt_kg-s.total_htt_kg, ...
 sum(s{:,{'final_inventory_site1_kg','final_inventory_site2_kg','final_inventory_site3_kg','final_inventory_site4_kg'}},2), ...
 sum(d{:,{'final_inventory_site1_kg','final_inventory_site2_kg','final_inventory_site3_kg','final_inventory_site4_kg'}},2), ...
 'VariableNames',{'path_id','saa_cost','dro_cost','delta_cost','saa_production','dro_production','delta_production', ...
 'saa_htt','dro_htt','delta_htt','saa_final_inventory','dro_final_inventory'});
writetable(comp,fullfile(runDir,'06-comparison','common_path_comparison.csv'));
idx=representatives(s,d,comp);writetable(idx,fullfile(runDir,'07-representative-path-index','representative_path_index.csv'));
viol=so.constraint_violations+do.constraint_violations;pass=n>0&&viol==0&&saa.pass&&dro.pass;
txt=sprintf(['FINAL_JUDGMENT=%s\nFORMAL_FROZEN_COMMIT=%s\nN_SAA_completed=%d\nN_DRO_completed=%d\n' ...
 'N_common=%d\nSAA_OOS_pure_time_s=%.12g\nDRO_OOS_pure_time_s=%.12g\nconstraint_violations=%d\n'], ...
 ternary(pass,'PASS_READY_FOR_FORMAL_OOS_ANALYSIS','FAIL'),commit,so.completed_paths,do.completed_paths,n,so.pure_time_s,do.pure_time_s,viol);
write_text(fullfile(runDir,'final_judgment.txt'),txt); final=struct('pass',pass,'n_common',n);
end

function idx=representatives(s,d,c)
rows={}; rows(end+1,:)={'highest_cost_saa','saa',s.path_id(argmax(s.total_cost)),max(s.total_cost)};
rows(end+1,:)={'highest_cost_dro','chi2_eta003',d.path_id(argmax(d.total_cost)),max(d.total_cost)};
metrics={'terminal_gap_kg','ordinary_shortage_kg','total_htt_kg','max_branch_utilization','site3_grid_limited_count'};
labels={'highest_terminal_gap','highest_ordinary_shortage','highest_htt','highest_branch_utilization','highest_site3_grid_limited'};
for j=1:numel(metrics),for q=1:2,if q==1,x=s;m='saa';else,x=d;m='chi2_eta003';end
 v=x.(metrics{j});ii=argmax(v);rows(end+1,:)={labels{j},m,x.path_id(ii),v(ii)};end,end
for q=1:2,if q==1,x=s;m='saa';else,x=d;m='chi2_eta003';end,v=x.minimum_voltage_pu;ii=argmin(v);rows(end+1,:)={'lowest_voltage',m,x.path_id(ii),v(ii)};end
[v,i]=max(abs(c.delta_production));rows(end+1,:)={'largest_saa_dro_production_difference','paired',c.path_id(i),v};
[v,i]=max(abs(c.delta_htt));rows(end+1,:)={'largest_saa_dro_htt_difference','paired',c.path_id(i),v};
[v,i]=max(abs(c.dro_final_inventory-c.saa_final_inventory));rows(end+1,:)={'largest_saa_dro_final_inventory_difference','paired',c.path_id(i),v};
idx=cell2table(rows,'VariableNames',{'selection_type','method','path_id','metric_value'});
end
function i=argmax(x),[~,i]=max(x);end
function i=argmin(x),[~,i]=min(x);end

function metadata=write_training_metadata(dir,method,budget,startWall,state,LB,cuts,commit,opts,cp,reload,diag)
metadata=struct('method',method,'eta',ternary(method=="saa",0,0.03),'start_time',string(startWall), ...
 'end_time',string(datetime('now')),'requested_budget_s',budget,'actual_pure_training_time_s',state.pure_time_s, ...
 'iterations',state.iteration,'forward_count',state.forward_count,'backward_count',state.backward_count, ...
 'final_cuts',cuts,'final_LB',LB(end),'stop_flag',2,'frozen_commit',commit,'seed',opts.seed, ...
 'final_checkpoint',string(cp),'checkpoint_reload_pass',reload,'diagnostic_pass',diag, ...
 'LB_gain_last20',tail_gain(LB,20),'LB_gain_last30',tail_gain(LB,30),'LB_gain_last50',tail_gain(LB,50));
writetable(struct2table(metadata),fullfile(dir,'training_metadata.csv'));
end
function v=tail_gain(x,n),if numel(x)>n,v=x(end)-x(end-n);else,v=NaN;end,end

function identity=build_identity(rootDir,commit)
identity=struct('frozen_commit',commit,'base_input',fullfile(rootDir,'data','yuanqi','near_stage_msp_input.mat'), ...
 'saa_input',fullfile(rootDir,'results','task-002-stage2b-b3-smoke','73-htt-transport-cost-sensitivity','run-001','H02','case-saa','sensitivity_input.mat'), ...
 'dro_input',fullfile(rootDir,'results','task-002-stage2b-b3-smoke','73-htt-transport-cost-sensitivity','run-001','H02','case-chi2_eta003','sensitivity_input.mat'), ...
 'saa_terminal',fullfile(rootDir,'results','task-002-stage2b-b3-smoke','53-35state-saa-vs-eta003-terminal-loh','run-024','terminal_loh_table_saa.csv'), ...
 'dro_terminal',fullfile(rootDir,'results','task-002-stage2b-b3-smoke','53-35state-saa-vs-eta003-terminal-loh','run-024','terminal_loh_table_eta_003.csv'));
paths={identity.base_input,identity.saa_input,identity.dro_input,identity.saa_terminal,identity.dro_terminal};
labels={'base_input','saa_input','dro_input','saa_terminal','dro_terminal'};
for i=1:numel(paths)
    if ~isfile(paths{i}),error('Stage84:MissingIdentityFile','Missing frozen input %s.',paths{i});end
    identity.([labels{i} '_sha256'])=sha256_file(paths{i});
    info=dir(paths{i});identity.([labels{i} '_size_bytes'])=info.bytes;
end
end
function save_identity(runDir,id)
names=fieldnames(id);vals=cellfun(@(n)string(id.(n)),names,'UniformOutput',false);
writetable(table(string(names),vertcat(vals{:}),'VariableNames',{'item','value'}),fullfile(runDir,'00-input-manifest','input_identity.csv'));
end
function write_oos_manifest(dir,p,id,seed)
txt=sprintf(['seed=%d\npaths=10000\nstages=%d\nk_init=%d\ncommon_path_order=true\n' ...
 'second_layer_consequence_sampling=NOT_APPLICABLE_CURRENT_H2_MODEL\nfrozen_commit=%s\n'],seed,p.T,p.k_init,id.frozen_commit);
write_text(fullfile(dir,'oos_manifest.txt'),txt);
end
function make_run_dirs(runDir)
dirs={'00-input-manifest','01-saa-training','02-dro-training','03-common-oos-paths','04-saa-oos', ...
 '05-dro-oos','06-comparison','07-representative-path-index','checkpoints/saa','checkpoints/chi2_eta003','logs'};
mkdir(runDir);for i=1:numel(dirs),mkdir(fullfile(runDir,dirs{i}));end
end
function write_status(runDir,status,phase,method,iter,elapsed,oos,cp,pid,commit)
cpTime="";
if string(cp)~="" && any(string(method)==["saa","chi2_eta003"])
    cpPath=fullfile(runDir,'checkpoints',char(method),char(cp));
    if isfile(cpPath)
        cpInfo=dir(cpPath);cpTime=string(datetime(cpInfo.datenum,'ConvertFrom','datenum', ...
            'Format','yyyy-MM-dd HH:mm:ss'));
    end
end
txt=sprintf(['STATUS=%s\nPHASE=%s\nMETHOD=%s\nITERATION=%d\nTRAINING_ELAPSED_S=%.12g\n' ...
 'OOS_COMPLETED_PATHS=%d\nLATEST_CHECKPOINT=%s\nLAST_CHECKPOINT_TIME=%s\nLAST_UPDATE_TIME=%s\n' ...
 'MATLAB_PID=%d\nFORMAL_FROZEN_COMMIT=%s\n'],status,phase,method,iter,elapsed,oos,cp, ...
 char(cpTime),char(datetime('now','Format','yyyy-MM-dd HH:mm:ss')),pid,commit);
tmp=fullfile(runDir,'RUNNING_STATUS.tmp');write_text(tmp,txt);movefile(tmp,fullfile(runDir,'RUNNING_STATUS.txt'),'f');
end
function write_failure(runDir,ME)
txt=string(sprintf('STATUS=FAIL\nidentifier=%s\nmessage=%s\n',ME.identifier,ME.message));
for i=1:numel(ME.stack),txt=txt+string(sprintf('stack_%d=%s:%d\n',i,ME.stack(i).name,ME.stack(i).line));end
write_text(fullfile(runDir,'FAILURE.txt'),txt);
end
function assert_accepted_gate(rootDir)
s81=fullfile(rootDir,'results','task-002-stage2b-b3-smoke','81-hourly-grid-short-training','run-004','final_judgment.txt');
s83=fullfile(rootDir,'results','task-002-stage2b-b3-smoke','83-hourly-grid-unit-powerflow-audit','run-004','final_judgment.txt');
if ~isfile(s81)||~contains(fileread(s81),'PASS_READY_FOR_FORMAL_TRAINING')
    error('Stage84:Stage81Gate','Stage-81 run-004 accepted gate is missing or not PASS.');
end
if ~isfile(s83)||~contains(fileread(s83),'PASS_WITH_WARNING')
    error('Stage84:Stage83Gate','Stage-83 run-004 accepted gate is missing or not PASS_WITH_WARNING.');
end
end
function hex=sha256_file(path)
md=java.security.MessageDigest.getInstance('SHA-256');
fid=fopen(path,'r');if fid<0,error('Cannot hash %s.',path);end
c=onCleanup(@()fclose(fid));
while true
    data=fread(fid,1024*1024,'*uint8');if isempty(data),break;end
    md.update(data);
end
hex=lower(reshape(dec2hex(typecast(md.digest(),'uint8'),2).',1,[]));
end
function write_text(path,txt),fid=fopen(path,'w');if fid<0,error('Cannot open %s.',path);end;c=onCleanup(@()fclose(fid));fprintf(fid,'%s',char(txt));end
function y=ternary(test,a,b),if test,y=a;else,y=b;end,end
