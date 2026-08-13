function run_stage82_terminal_semantics_smoke_h2()
%RUN_STAGE82_TERMINAL_SEMANTICS_SMOKE_H2 Verify stage1-6/7/8 semantics.

rootDir=fileparts(fileparts(mfilename('fullpath')));
addpath(rootDir); addpath(genpath(fullfile(rootDir,'fa_h2')));
addpath(fullfile(rootDir,'utils')); addpath(fullfile(rootDir,'hourly_grid_h2'));

runId=char(string(getenv('STAGE82_RUN_ID')));
if isempty(runId), runId='run-001'; end
if isempty(regexp(runId,'^run-\d{3}$','once'))
    error('run_stage82_terminal_semantics_smoke_h2:BadRunId', ...
        'STAGE82_RUN_ID must be run-xxx.');
end
outDir=fullfile(rootDir,'results','task-002-stage2b-b3-smoke', ...
    '82-hourly-grid-terminal-semantics-fix',runId);
if exist(outDir,'dir')
    error('run_stage82_terminal_semantics_smoke_h2:OutputExists', ...
        'Refusing to overwrite %s',outDir);
end
mkdir(outDir);

hourlyOpts=build_opts(rootDir,true);
legacyOpts=build_opts(rootDir,false);
hourly=load_data_h2_near(hourlyOpts.dataDir,hourlyOpts.nearInputFile,hourlyOpts);
legacy=load_data_h2_near(legacyOpts.dataDir,legacyOpts.nearInputFile,legacyOpts);
hourlyLib=define_models_h2(hourly);
legacyLib=define_models_h2(legacy);

identity=check_identity(hourly,legacy,hourlyLib,legacyLib);
writetable(identity.stage_table,fullfile(outDir,'stage_model_library_audit.csv'));
write_identity(outDir,identity);

terminal=check_terminal_semantics(hourly,legacy);
write_terminal(outDir,terminal);

seed=find_terminal_forward_seed(hourly,20260513,10000);
rng(seed,'twister');
x=zeros(hourly.Ni,hourly.T); theta=zeros(hourly.T,1);
[hourlyLib,x,theta,lb,path,forwardInfo]=forward_pass_h2( ...
    hourlyLib,hourly,0,x,theta);
forwardPass=any(forwardInfo.status=="loh_demand_stage") && ...
    ~any(forwardInfo.status=="normal" & (1:hourly.T).'>6);

[beforeCuts,~]=cut_inventory(hourlyLib,hourly);
[hourlyLib,cutFlag]=backward_pass_h2(hourlyLib,hourly,x,theta,path);
[afterCuts,cutDimensionPass]=cut_inventory(hourlyLib,hourly);
terminalCut=check_stage6_terminal_cut(hourlyLib,hourly,x(:,6));
dual=check_inventory_dual(hourlyLib,hourly);
backwardPass=afterCuts>beforeCuts && cutDimensionPass && ...
    terminalCut.pass && dual.pass;
write_forward_backward(outDir,seed,lb,path,forwardInfo,beforeCuts, ...
    afterCuts,cutFlag,forwardPass,backwardPass,terminalCut,dual);

legacySmoke=run_legacy_regression(legacyLib,legacy);
write_legacy(outDir,legacySmoke);

allPass=identity.pass && terminal.pass && forwardPass && backwardPass && ...
    legacySmoke.pass;
judgment=ternary(allPass,'PASS_READY_TO_RERUN_STAGE81','FAIL');
write_final(outDir,judgment,identity,terminal,forwardPass,backwardPass, ...
    terminalCut,dual,legacySmoke);
end

function opts=build_opts(rootDir,enableGrid)
opts=h2_default_options(rootDir);
opts.nearInputFile=fullfile(rootDir,'results','task-002-stage2b-b3-smoke', ...
    '73-htt-transport-cost-sensitivity','run-001','H02','case-saa', ...
    'sensitivity_input.mat');
opts.dt_h=8; opts.enable_hourly_grid=enableGrid;
opts.hourly_grid_vmin_pu=0.90; opts.hourly_grid_vmax_pu=1.10;
opts.terminal_loh_mode='saa';
opts.terminal_loh_lookup_file=fullfile(rootDir,'results', ...
    'task-002-stage2b-b3-smoke','53-35state-saa-vs-eta003-terminal-loh', ...
    'run-024','terminal_loh_table_saa.csv');
opts.allow_zero_terminal_loh=true;
opts.runTraining=false; opts.runEvaluation=false;
end

function audit=check_identity(hourly,~,hourlyLib,legacyLib)
rows=cell(hourly.T,8);
for t=1:hourly.T
    hModels=hourlyLib.models(t,:); lModels=legacyLib.models(t,:);
    hCount=sum(~cellfun(@isempty,hModels));
    lCount=sum(~cellfun(@isempty,lModels));
    hGrid=all(cellfun(@(m) isempty(m) || ...
        (isfield(m,'hourly_grid_enabled') && m.hourly_grid_enabled),hModels));
    hNoGrid=all(cellfun(@isempty,hModels));
    if t<=6
        expected="HOURLY_OPERATING_LP";
        pass=hCount>0 && hGrid;
    elseif t==7
        expected="TERMINALLOH_ANALYTIC_NO_LP";
        pass=hNoGrid;
    else
        expected="ABSORBING_ZERO_NO_LP";
        pass=hNoGrid;
    end
    rows(t,:)={t,string(expected),hCount,lCount,hGrid,hNoGrid,pass, ...
        t<=hourly.hourly_grid.n_operating_stages};
end
audit.stage_table=cell2table(rows,'VariableNames', ...
    {'stage','expected_semantics','hourly_model_count','legacy_model_count', ...
    'all_hourly_models_have_grid','hourly_models_all_empty','pass', ...
    'within_hourly_operating_horizon'});
audit.stage1_6_pass=all(audit.stage_table.pass(1:6));
audit.stage7_empty=audit.stage_table.hourly_models_all_empty(7);
audit.stage8_empty=audit.stage_table.hourly_models_all_empty(8);
audit.legacy_stage7_models=audit.stage_table.legacy_model_count(7);
audit.legacy_stage8_models=audit.stage_table.legacy_model_count(8);
audit.last_operating_stage=hourlyLib.last_operating_stage;
audit.pass=hourly.T==8 && hourly.hourly_grid.n_operating_stages==6 && ...
    audit.last_operating_stage==6 && all(audit.stage_table.pass);
end

function result=check_terminal_semantics(hourly,legacy)
x7=sum(hourly.TerminalLOH,1);
x7(~hourly.is_loh_demand_stage.')=-inf;
[~,k7]=max(x7);
a7=hourly.S(k7,1); loc7=hourly.S(k7,2);
k8=hourly.state_id(a7,loc7,8);
x=zeros(hourly.Ni,1);
[hc7,hi7]=eval_terminal_loh_h2(x,hourly,k7);
[lc7,li7]=eval_terminal_loh_h2(x,legacy,k7);
[hv7,hg7]=terminal_value_and_subgradient_h2(x,hourly,k7);
[lv7,lg7]=terminal_value_and_subgradient_h2(x,legacy,k7);
[hc8,hi8]=eval_terminal_loh_h2(x,hourly,k8);
[lc8,li8]=eval_terminal_loh_h2(x,legacy,k8);
[hv8,hg8]=terminal_value_and_subgradient_h2(x,hourly,k8);
[lv8,lg8]=terminal_value_and_subgradient_h2(x,legacy,k8);
result=struct('k7',k7,'k8',k8,'inventory',x, ...
    'stage7_hourly_cost',hc7,'stage7_legacy_cost',lc7, ...
    'stage7_hourly_value',hv7,'stage7_legacy_value',lv7, ...
    'stage7_target',hi7.target,'stage7_shortage',hi7.shortage, ...
    'stage7_gradient',hg7,'stage8_hourly_cost',hc8, ...
    'stage8_legacy_cost',lc8,'stage8_hourly_value',hv8, ...
    'stage8_legacy_value',lv8,'stage8_shortage',hi8.shortage, ...
    'stage8_gradient',hg8);
result.stage7_parity=max(abs([hc7-lc7;hv7-lv7;hi7.target-li7.target; ...
    hi7.shortage-li7.shortage;hg7-lg7]))<=1e-12;
result.stage8_zero=max(abs([hc8;lc8;hv8;lv8;hi8.shortage;li8.shortage; ...
    hg8;lg8]))<=1e-12;
result.pass=result.stage7_parity && result.stage8_zero;
end

function seed=find_terminal_forward_seed(params,startSeed,maxAttempts)
for candidate=startSeed:(startSeed+maxAttempts-1)
    rng(candidate,'twister'); k=params.k_init; absorbed=false; hit=false;
    for t=1:params.T
        if t>1, k=mc_sample(k,params.P_joint); end
        if absorbed, continue; end
        if params.is_dissipated(k) || params.is_absorbing(k)
            absorbed=true;
        elseif params.is_loh_demand_stage(k)
            hit=true; absorbed=true;
        end
    end
    if hit, seed=candidate; return; end
end
error('run_stage82_terminal_semantics_smoke_h2:NoTerminalSeed', ...
    'No terminal-hit forward seed found in %d attempts.',maxAttempts);
end

function [count,dimensionPass]=cut_inventory(lib,params)
count=0; dimensionPass=true;
for t=1:params.T
    for k=1:params.K
        m=lib.models{t,k};
        if isempty(m), continue; end
        baseRows=params.Ni+1;
        if isfield(m,'hourly_grid_enabled') && m.hourly_grid_enabled
            baseRows=baseRows+8*8*params.hourly_grid.n_branch;
        end
        count=count+max(0,size(m.A,1)-baseRows);
        for r=(baseRows+1):size(m.A,1)
            allowed=false(1,m.nvars); allowed(m.idx.x)=true;
            allowed(m.idx.theta)=true;
            dimensionPass=dimensionPass && nnz(m.A(r,~allowed))==0 && ...
                numel(m.idx.x)==4;
        end
    end
end
end

function result=check_stage6_terminal_cut(lib,params,xTrial)
n=params.state_id(2,2,6); Q=zeros(params.K,1);
gState=zeros(params.K,params.Ni);
for k=1:params.K
    if params.is_loh_demand_stage(k)
        [Q(k),g]=terminal_value_and_subgradient_h2(xTrial,params,k);
        gState(k,:)=g(:).';
    end
end
w=params.P_joint(n,:).'; expectedQ=w.'*Q;
expectedG=gState.'*w; expectedAlpha=expectedQ-expectedG.'*xTrial;
m=lib.models{6,n}; row=m.A(end,:); actualG=row(m.idx.x).';
allowed=false(1,m.nvars); allowed(m.idx.x)=true; allowed(m.idx.theta)=true;
result=struct('state_id',n,'state',params.S(n,:), ...
    'expected_Q',expectedQ,'expected_gradient',expectedG, ...
    'actual_gradient',actualG,'expected_alpha',expectedAlpha, ...
    'actual_alpha',-m.b(end),'theta_coefficient',row(m.idx.theta), ...
    'non_state_nnz',nnz(row(~allowed)));
result.max_error=max(abs([actualG-expectedG; ...
    (-m.b(end))-expectedAlpha;row(m.idx.theta)+1]));
result.pass=expectedQ>0 && any(abs(expectedG)>0) && ...
    result.max_error<=1e-8 && result.non_state_nnz==0;
end

function result=check_inventory_dual(lib,params)
t=3; k=params.state_id(2,1,1); previous=zeros(params.Ni,1);
m=update_rhs_h2(lib.models{t,k},params,k,t,previous);
s=solve_stage_model_h2(m); g=s.lambda.inventory_eq(:);
[~,site]=max(abs(g)); delta=1e-4; mp=m;
mp.beq(mp.rowMap.inventory_eq(site))= ...
    mp.beq(mp.rowMap.inventory_eq(site))+delta;
sp=solve_stage_model_h2(mp); fd=(sp.obj-s.obj)/delta;
result=struct('stage',t,'state_id',k,'gradient',g, ...
    'finite_difference',fd,'dual',g(site),'error',abs(fd-g(site)));
result.pass=numel(g)==4 && all(isfinite(g)) && result.error<=1e-4;
end

function result=run_legacy_regression(lib,params)
rng(20260513,'twister'); x=zeros(params.Ni,params.T);
theta=zeros(params.T,1);
[lib,x,theta,lb,path,info]=forward_pass_h2(lib,params,0,x,theta);
[lib,flag]=backward_pass_h2(lib,params,x,theta,path);
idx=lib.models{1,params.k_init}.idx;
[cuts,dimPass]=cut_inventory(lib,params);
result=struct('lb',lb,'cut_flag',flag,'cut_count',cuts, ...
    'dimension_pass',dimPass,'idx_x',idx.x,'idx_e',idx.e, ...
    'idx_r',idx.r,'status',info.status);
result.pass=~params.enable_hourly_grid && isequal(idx.x,1:4) && ...
    isequal(idx.e,5:8) && isequal(idx.r,9:12) && isfinite(lb) && ...
    cuts>0 && dimPass;
end

function write_identity(outDir,audit)
fid=fopen(fullfile(outDir,'model_identity.txt'),'w');
fprintf(fid,'STATUS=%s\n',ternary(audit.pass,'PASS','FAIL'));
fprintf(fid,'params_T=8\nhourly_operating_stages=6\n');
fprintf(fid,'hourly_model_library_last_operating_stage=%d\n',audit.last_operating_stage);
fprintf(fid,'stage1_6_hourly_grid_pass=%d\nstage7_model_empty=%d\n', ...
    audit.stage1_6_pass,audit.stage7_empty);
fprintf(fid,'stage8_model_empty=%d\nlegacy_stage7_model_count=%d\n', ...
    audit.stage8_empty,audit.legacy_stage7_models);
fprintf(fid,'legacy_stage8_model_count=%d\n',audit.legacy_stage8_models);
fclose(fid);
end

function write_terminal(outDir,r)
fid=fopen(fullfile(outDir,'terminal_semantics_audit.txt'),'w');
fprintf(fid,'STATUS=%s\nstage7_state_id=%d\nstage8_state_id=%d\n', ...
    ternary(r.pass,'PASS','FAIL'),r.k7,r.k8);
fprintf(fid,'inventory_kg=[%s]\n',num2str(r.inventory.'));
fprintf(fid,'stage7_hourly_cost=%.12g\nstage7_legacy_cost=%.12g\n', ...
    r.stage7_hourly_cost,r.stage7_legacy_cost);
fprintf(fid,'stage7_gradient=[%s]\nstage7_parity=%d\n', ...
    num2str(r.stage7_gradient.'),r.stage7_parity);
fprintf(fid,'stage8_hourly_cost=%.12g\nstage8_legacy_cost=%.12g\n', ...
    r.stage8_hourly_cost,r.stage8_legacy_cost);
fprintf(fid,'stage8_zero_value_pass=%d\n',r.stage8_zero);
fclose(fid);
end

function write_forward_backward(outDir,seed,lb,path,info,before,after,flag, ...
        forwardPass,backwardPass,terminalCut,dual)
fid=fopen(fullfile(outDir,'forward_backward_smoke.txt'),'w');
fprintf(fid,'STATUS=%s\nforward_seed=%d\nforward_lb=%.12g\n', ...
    ternary(forwardPass&&backwardPass,'PASS','FAIL'),seed,lb);
fprintf(fid,'path_state_ids=[%s]\nstatus=[%s]\n',num2str(path.'), ...
    strjoin(cellstr(info.status.'),','));
fprintf(fid,'terminal_hit=%d\nnormal_operation_after_stage6=0\n',forwardPass);
fprintf(fid,'cuts_before=%d\ncuts_after=%d\ncutviol_flag=%d\n',before,after,flag);
fprintf(fid,'terminal_cut_state=%d\nterminal_cut_Q=%.12g\n', ...
    terminalCut.state_id,terminalCut.expected_Q);
fprintf(fid,'terminal_cut_gradient=[%s]\nterminal_cut_max_error=%.12g\n', ...
    num2str(terminalCut.actual_gradient.'),terminalCut.max_error);
fprintf(fid,'terminal_cut_pass=%d\ncut_slope_dimension=4\n',terminalCut.pass);
fprintf(fid,'inventory_dual=[%s]\nfinite_difference=%.12g\n', ...
    num2str(dual.gradient.'),dual.finite_difference);
fprintf(fid,'inventory_dual_error=%.12g\ninventory_dual_pass=%d\n', ...
    dual.error,dual.pass);
fclose(fid);
end

function write_legacy(outDir,r)
fid=fopen(fullfile(outDir,'legacy_regression.txt'),'w');
fprintf(fid,'STATUS=%s\nenable_hourly_grid=0\n',ternary(r.pass,'PASS','FAIL'));
fprintf(fid,'idx_x=[%s]\nidx_e=[%s]\nidx_r=[%s]\n', ...
    num2str(r.idx_x),num2str(r.idx_e),num2str(r.idx_r));
fprintf(fid,'forward_lb=%.12g\ncut_flag=%d\ncut_count=%d\n', ...
    r.lb,r.cut_flag,r.cut_count);
fprintf(fid,'cut_dimension_pass=%d\n',r.dimension_pass);
fclose(fid);
end

function write_final(outDir,judgment,identity,terminal,forwardPass, ...
        backwardPass,terminalCut,dual,legacy)
fid=fopen(fullfile(outDir,'final_judgment.txt'),'w');
fprintf(fid,'FINAL_JUDGMENT=%s\n',judgment);
fprintf(fid,'stage1_6_hourly_grid_pass=%d\n',identity.stage1_6_pass);
fprintf(fid,'stage7_terminal_analytic_no_grid_pass=%d\n', ...
    identity.stage7_empty&&terminal.stage7_parity);
fprintf(fid,'stage8_absorbing_zero_no_grid_pass=%d\n', ...
    identity.stage8_empty&&terminal.stage8_zero);
fprintf(fid,'forward_terminal_pass=%d\nbackward_pass=%d\n',forwardPass,backwardPass);
fprintf(fid,'terminal_value_propagated_to_stage6_cut=%d\n',terminalCut.pass);
fprintf(fid,'inventory_dual_pass=%d\ncut_dimension=4\n',dual.pass);
fprintf(fid,'legacy_regression_pass=%d\n',legacy.pass);
fprintf(fid,'stage80_regression=RUN_SEPARATELY_WITH_ORIGINAL_STAGE80_LAUNCHER\n');
fclose(fid);
end

function out=ternary(cond,a,b)
if cond, out=a; else, out=b; end
end
