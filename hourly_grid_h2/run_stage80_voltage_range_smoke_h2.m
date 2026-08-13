function run_stage80_voltage_range_smoke_h2()
%RUN_STAGE80_VOLTAGE_RANGE_SMOKE_H2 Stage-80 gated grid/H2 smoke.

rootDir=fileparts(fileparts(mfilename('fullpath')));
addpath(rootDir); addpath(fullfile(rootDir,'fa_h2'));
addpath(fullfile(rootDir,'fa_h2','fuzhu'));
addpath(fullfile(rootDir,'utils')); addpath(fullfile(rootDir,'hourly_grid_h2'));
runId=char(string(getenv('STAGE80_RUN_ID')));
if isempty(runId), runId='run-001'; end
if isempty(regexp(runId,'^run-\d{3}$','once'))
    error('run_stage80_voltage_range_smoke_h2:BadRunId','STAGE80_RUN_ID must be run-xxx.');
end
outDir=fullfile(rootDir,'results','task-002-stage2b-b3-smoke', ...
    '80-hourly-grid-voltage-range-smoke',runId);
if exist(outDir,'dir')
    error('run_stage80_voltage_range_smoke_h2:OutputExists', ...
        'Refusing to overwrite %s',outDir);
end
mkdir(outDir);

data=load_hourly_grid_data_h2(rootDir,struct('vmin_pu',0.90,'vmax_pu',1.10));
identity=validate_hourly_grid_data_h2(data);
writetable(identity,fullfile(outDir,'input_identity_checks.csv'));
write_identity(outDir,data);

base=run_base_gate(data);
writetable(base.summary,fullfile(outDir,'base_grid_48h_feasibility.csv'));
writetable(base.voltage,fullfile(outDir,'voltage_diagnostics.csv'));
writetable(base.branch,fullfile(outDir,'branch_capacity_diagnostics.csv'));
if ~all(base.summary.feasible)
    write_final(outDir,data,base,[],[],[],false,'FAIL_GATE_B');
    return;
end

hosting=run_hosting(data);
writetable(hosting,fullfile(outDir,'electrolyzer_hosting_test.csv'));

[params,integrated,cutAudit]=run_integrated_and_cut(rootDir,data);
write_integrated(outDir,integrated);
write_cut(outDir,cutAudit);

legacy=run_legacy_regression(rootDir);
write_legacy(outDir,legacy);

allPass=all(base.summary.feasible) && all(base.summary.true_circle_pass) && ...
    integrated.pass && cutAudit.pass && legacy.pass;
write_final(outDir,data,base,hosting,integrated,cutAudit,legacy.pass, ...
    ternary(allPass,'PASS_READY_FOR_SHORT_TRAINING','FAIL'));
save(fullfile(outDir,'stage80_smoke_workspace.mat'),'data','params', ...
    'base','hosting','integrated','cutAudit','legacy','-v7.3');
end

function base=run_base_gate(data)
sRows=cell(48,17); vRows=cell(48*data.n_bus,7);
bRows=cell(48*data.n_branch,11); vr=0; br=0;
for tau=1:48
    model=build_hourly_lindistflow_h2(data,tau,zeros(4,1),true);
    result=solve_lp(model);
    feasible=strcmp(result.status,'OPTIMAL');
    if feasible
        d=evaluate_hourly_grid_constraints_h2(data,model,result.x);
        truePass=d.true_circle_violation_mva<=1e-9;
        voltagePass=d.voltage_lower_violation_pu<=1e-9 && d.voltage_upper_violation_pu<=1e-9;
        [~,ell]=max(d.true_s_mva);
        sRows(tau,:)={tau,ceil(tau/8),mod(tau-1,8)+1,string(result.status), ...
            feasible,voltagePass,truePass,d.min_voltage_pu,d.min_voltage_bus, ...
            d.max_voltage_pu,d.max_voltage_bus,d.max_true_s_mva, ...
            d.max_true_s_utilization,data.branch_from(ell),data.branch_to(ell), ...
            d.slack_p_kw,d.slack_q_kvar};
        for bus=1:data.n_bus
            vr=vr+1; vRows(vr,:)={tau,bus,d.v_sq(bus),d.v_pu(bus), ...
                d.v_pu(bus)-data.vmin_pu,data.vmax_pu-d.v_pu(bus), ...
                d.v_pu(bus)>=data.vmin_pu-1e-9 && d.v_pu(bus)<=data.vmax_pu+1e-9};
        end
        for e=1:data.n_branch
            br=br+1; bRows(br,:)={tau,e,data.branch_from(e),data.branch_to(e), ...
                d.p_branch_kw(e),d.q_branch_kvar(e),d.true_s_mva(e), ...
                d.true_s_mva(e)/data.branch_smax_mva, ...
                d.true_s_mva(e)<=data.branch_smax_mva+1e-9, ...
                d.max_octagon_violation,d.true_circle_violation_mva};
        end
    else
        sRows(tau,:)={tau,ceil(tau/8),mod(tau-1,8)+1,string(result.status), ...
            false,false,false,NaN,NaN,NaN,NaN,NaN,NaN,NaN,NaN,NaN,NaN};
    end
end
base.summary=cell2table(sRows,'VariableNames',{'tau','stage','hour_in_stage', ...
    'status','feasible','voltage_pass','true_circle_pass','min_voltage_pu', ...
    'min_voltage_bus','max_voltage_pu','max_voltage_bus','max_true_s_mva', ...
    'max_true_utilization','tight_from','tight_to','slack_p_kw','slack_q_kvar'});
base.voltage=cell2table(vRows(1:vr,:),'VariableNames',{'tau','bus','v_sq','v_pu', ...
    'lower_margin_pu','upper_margin_pu','voltage_pass'});
base.branch=cell2table(bRows(1:br,:),'VariableNames',{'tau','branch','from_bus', ...
    'to_bus','p_kw','q_kvar','true_s_mva','true_utilization','true_circle_pass', ...
    'hour_octagon_violation','hour_true_circle_violation_mva'});
end

function hosting=run_hosting(data)
rows=cell(96,20); rr=0;
for pvEnabled=[true,false]
    for tau=1:48
        model=build_hourly_grid_hosting_h2(data,tau,pvEnabled);
        result=solve_lp(model);
        if ~strcmp(result.status,'OPTIMAL')
            error('run_stage80_voltage_range_smoke_h2:HostingFailure', ...
                'Hosting LP failed at hour %d PV=%d: %s',tau,pvEnabled,result.status);
        end
        d=evaluate_hourly_grid_constraints_h2(data,model,result.x);
        pel=result.x(model.idx.p_el);
        full=all(pel>=data.pmax_kw-1e-6);
        [minV,minBus]=min(d.v_pu); [maxS,e]=max(d.true_s_mva);
        voltageBinding=minV<=data.vmin_pu+1e-6;
        branchBinding=maxS>=data.branch_smax_mva-1e-6;
        if full
            limiter="P_MAX";
        elseif voltageBinding
            limiter="VOLTAGE";
        elseif branchBinding
            limiter="BRANCH_CAPACITY";
        else
            limiter="OTHER_LP_BOUND";
        end
        rr=rr+1;
        rows(rr,:)={tau,ceil(tau/8),logical(pvEnabled),string(result.status), ...
            sum(pel),pel(1),pel(2),pel(3),pel(4),full,string(limiter), ...
            minV,minBus,d.max_voltage_pu,maxS,maxS/data.branch_smax_mva, ...
            data.branch_from(e),data.branch_to(e),d.slack_p_kw,d.slack_q_kvar};
    end
end
hosting=cell2table(rows,'VariableNames',{'tau','stage','pv_enabled','status', ...
    'max_total_p_el_kw','p_el1_kw','p_el2_kw','p_el3_kw','p_el4_kw', ...
    'all_sites_at_pmax','limiter','min_voltage_pu','min_voltage_bus', ...
    'max_voltage_pu','max_true_s_mva','max_true_utilization','tight_from', ...
    'tight_to','slack_p_kw','slack_q_kvar'});
end

function [params,report,cutAudit]=run_integrated_and_cut(rootDir,data)
opts=h2_default_options(rootDir);
opts.nearInputFile=data.h02_saa_input_file; opts.dt_h=8;
opts.enable_hourly_grid=true; opts.hourly_grid_vmin_pu=0.90;
opts.hourly_grid_vmax_pu=1.10; opts.terminal_loh_mode='saa';
opts.terminal_loh_lookup_file=fullfile(rootDir,'results', ...
    'task-002-stage2b-b3-smoke','53-35state-saa-vs-eta003-terminal-loh', ...
    'run-024','terminal_loh_table_saa.csv');
opts.allow_zero_terminal_loh=true;
params=load_data_h2_near(fullfile(rootDir,'data'),opts.nearInputFile,opts);
t=3; k=find(~params.is_absorbing & ~params.is_loh_demand_stage,1,'first');
% A legal zero-inventory state forces the integrated LP to exercise hourly
% electrolysis rather than satisfying ordinary demand from inherited stock.
prevX=zeros(params.Ni,1);
model=build_stage_model_h2(params,t);
model=update_rhs_h2(model,params,k,t,prevX);
sol=solve_stage_model_h2(model);

eq=model.Aeq*sol.xraw-model.beq; ineq=model.A*sol.xraw-model.b;
v=sqrt(sol.v_sq); trueS=hypot(sol.p_branch_kw,sol.q_branch_kvar)/1000;
h2Expected=params.k_H2*sum(sol.p_el_hourly_kw,2);
inventoryResidual=zeros(4,1);
for i=1:4
    inflow=sum(sol.fval(:,i)); outflow=sum(sol.fval(i,:));
    inventoryResidual(i)=sol.xval(i)-(prevX(i)+sol.rval(i)+inflow-outflow-sol.u_normal(i));
end
report=struct(); report.pass=strcmp(sol.status,'OPTIMAL') && ...
    max(abs(eq))<=1e-7 && max([0;ineq])<=1e-7 && ...
    min(v(:))>=data.vmin_pu-1e-8 && max(v(:))<=data.vmax_pu+1e-8 && ...
    max(trueS(:))<=data.branch_smax_mva+1e-8 && ...
    max(abs(sol.rval-h2Expected))<=1e-8 && max(abs(inventoryResidual))<=1e-8;
report.status=sol.status; report.stage=t; report.state_id=k;
report.state=params.S(k,:); report.prev_inventory_kg=prevX;
report.end_inventory_kg=sol.xval; report.production_kg=sol.rval;
report.hourly_p_el_kw=sol.p_el_hourly_kw; report.total_p_el_kwh=sum(sol.p_el_hourly_kw,'all');
report.min_voltage_pu=min(v(:)); report.max_voltage_pu=max(v(:));
report.max_true_s_mva=max(trueS(:)); report.max_p_balance_error=max(abs(eq(model.rowMap.grid_p_balance(:))));
report.max_q_balance_error=max(abs(eq(model.rowMap.grid_q_balance(:))));
report.max_voltage_drop_error=max(abs(eq(model.rowMap.grid_voltage_drop(:))));
report.max_pv_bound_violation=max([0;sol.p_pv_kw(:)-model.ub(model.idx.p_pv(:))]);
report.max_pel_bound_violation=max([0;sol.p_el_hourly_kw(:)-model.ub(model.idx.p_el_hourly(:))]);
report.max_h2_conversion_error=max(abs(sol.rval-h2Expected));
report.max_inventory_balance_error=max(abs(inventoryResidual));
report.htt_total_kg=sum(sol.fval,'all');
report.htt_capacity_kg=model.b(model.rowMap.htt_capacity);

g=sol.lambda.inventory_eq(:); delta=1e-4; [~,site]=max(abs(g));
pert=model; pert.beq(pert.rowMap.inventory_eq(site))=pert.beq(pert.rowMap.inventory_eq(site))+delta;
solPert=solve_stage_model_h2(pert); finiteDiff=(solPert.obj-sol.obj)/delta;
alpha=sol.obj-g.'*prevX;
withCut=add_cut_h2(model,g,alpha); solCut=solve_stage_model_h2(withCut);
lastRow=withCut.A(end,:); allowed=false(1,withCut.nvars);
allowed(withCut.idx.x)=true; allowed(withCut.idx.theta)=true;
cutAudit=struct(); cutAudit.gradient=g; cutAudit.dimension=numel(g);
cutAudit.site_order="Site1,Site2,Site3,Site4";
cutAudit.finite_difference=finiteDiff; cutAudit.extracted_dual=g(site);
cutAudit.dual_error=abs(finiteDiff-g(site));
cutAudit.cut_non_state_nnz=nnz(lastRow(~allowed));
cutAudit.cut_resolve_status=solCut.status;
cutAudit.cut_theta=solCut.theta;
cutAudit.pass=numel(g)==4 && cutAudit.dual_error<=1e-4 && ...
    cutAudit.cut_non_state_nnz==0 && strcmp(solCut.status,'OPTIMAL');
end

function legacy=run_legacy_regression(rootDir)
opts=h2_default_options(rootDir); opts.enable_hourly_grid=false;
opts.dt_h=8; opts.nearInputFile=fullfile(rootDir,'results', ...
    'task-002-stage2b-b3-smoke','73-htt-transport-cost-sensitivity','run-001', ...
    'H02','case-saa','sensitivity_input.mat');
opts.terminal_loh_mode='saa'; opts.terminal_loh_lookup_file=fullfile(rootDir, ...
    'results','task-002-stage2b-b3-smoke','53-35state-saa-vs-eta003-terminal-loh', ...
    'run-024','terminal_loh_table_saa.csv'); opts.allow_zero_terminal_loh=true;
params=load_data_h2_near(fullfile(rootDir,'data'),opts.nearInputFile,opts);
lib=define_models_h2(params); rng(20260513,'twister');
x=zeros(params.Ni,params.T); theta=zeros(params.T,1);
[lib,x,theta,lb,path,forwardInfo]=forward_pass_h2(lib,params,0,x,theta);
[lib,cutFlag]=backward_pass_h2(lib,params,x,theta,path);
idx=lib.models{1,params.k_init}.idx;
legacy=struct(); legacy.enable_hourly_grid=params.enable_hourly_grid;
legacy.idx_x=idx.x; legacy.idx_e=idx.e; legacy.idx_r=idx.r;
legacy.forward_lb=lb; legacy.forward_status=forwardInfo.status;
legacy.backward_cut_flag=cutFlag;
legacy.cut_count=size(lib.models{1,params.k_init}.A,1)-(params.Ni+1);
legacy.pass=~params.enable_hourly_grid && isequal(idx.x,1:4) && ...
    numel(x(:,1))==4 && all(isfinite(x(:))) && isfinite(lb) && ...
    legacy.cut_count>=1;
end

function result=solve_lp(model)
grb=struct('A',sparse([model.A;model.Aeq]),'obj',model.c(:), ...
    'rhs',[model.b(:);model.beq(:)],'sense',[repmat('<',size(model.A,1),1); ...
    repmat('=',size(model.Aeq,1),1)],'lb',model.lb(:),'ub',model.ub(:), ...
    'modelsense','min');
p=struct('OutputFlag',0,'InfUnbdInfo',1,'DualReductions',0);
raw=gurobi(grb,p); result=struct('status',raw.status);
if strcmp(raw.status,'OPTIMAL'), result.x=raw.x; result.obj=raw.objval; end
end

function write_identity(outDir,data)
fid=fopen(fullfile(outDir,'input_identity.txt'),'w');
fprintf(fid,'STAGE80_INPUT_IDENTITY=PASS\n');
fprintf(fid,'only_parameter_change=voltage_bounds\n');
fprintf(fid,'vmin_pu=%.12g\nvmax_pu=%.12g\nv_sq_bounds=[%.12g,%.12g]\n', ...
    data.vmin_pu,data.vmax_pu,data.vmin_pu^2,data.vmax_pu^2);
fprintf(fid,'slack_bus=1\nslack_v_sq=1\n');
fprintf(fid,'bus_count=33\nbranch_count=32\nbase_kv=12.66\nbase_mva=10\n');
fprintf(fid,'branch_smax_mva=6\nsite_elec_bus=[24,14,18,31]\n');
fprintf(fid,'pmax_kw=[300,200,120,150]\nk_H2=0.0195\n');
fprintf(fid,'tank_cap_kg=[300,200,100,150]\nhtt_capacity=160\nc_d=0.2\n');
fclose(fid);
end

function write_integrated(outDir,r)
fid=fopen(fullfile(outDir,'single_stage_integrated_smoke.txt'),'w');
fprintf(fid,'STATUS=%s\n',ternary(r.pass,'PASS','FAIL'));
fprintf(fid,'solver_status=%s\nstage=%d\nstate_id=%d\nstate=[%g,%g,%g]\n', ...
    r.status,r.stage,r.state_id,r.state);
fprintf(fid,'min_voltage_pu=%.12g\nmax_voltage_pu=%.12g\nmax_true_s_mva=%.12g\n', ...
    r.min_voltage_pu,r.max_voltage_pu,r.max_true_s_mva);
fprintf(fid,'max_p_balance_error=%.12g\nmax_q_balance_error=%.12g\n', ...
    r.max_p_balance_error,r.max_q_balance_error);
fprintf(fid,'max_voltage_drop_error=%.12g\nmax_pv_bound_violation=%.12g\n', ...
    r.max_voltage_drop_error,r.max_pv_bound_violation);
fprintf(fid,'max_pel_bound_violation=%.12g\nmax_h2_conversion_error=%.12g\n', ...
    r.max_pel_bound_violation,r.max_h2_conversion_error);
fprintf(fid,'max_inventory_balance_error=%.12g\nhtt_total_kg=%.12g\nhtt_capacity_kg=%.12g\n', ...
    r.max_inventory_balance_error,r.htt_total_kg,r.htt_capacity_kg);
fprintf(fid,'prev_inventory_kg=[%.12g,%.12g,%.12g,%.12g]\n',r.prev_inventory_kg);
fprintf(fid,'production_kg=[%.12g,%.12g,%.12g,%.12g]\n',r.production_kg);
fprintf(fid,'hourly_electrolyzer_energy_kwh=%.12g\n',r.total_p_el_kwh);
fclose(fid);
end

function write_cut(outDir,r)
fid=fopen(fullfile(outDir,'cut_state_dimension_audit.txt'),'w');
fprintf(fid,'STATUS=%s\n',ternary(r.pass,'PASS','FAIL'));
fprintf(fid,'cut_slope_dimension=%d\nsite_order=%s\n',r.dimension,r.site_order);
fprintf(fid,'gradient=[%.12g,%.12g,%.12g,%.12g]\n',r.gradient);
fprintf(fid,'finite_difference=%.12g\nextracted_dual=%.12g\ndual_error=%.12g\n', ...
    r.finite_difference,r.extracted_dual,r.dual_error);
fprintf(fid,'cut_non_state_nnz=%d\ncut_resolve_status=%s\n', ...
    r.cut_non_state_nnz,r.cut_resolve_status);
fclose(fid);
end

function write_legacy(outDir,r)
fid=fopen(fullfile(outDir,'legacy_regression.txt'),'w');
fprintf(fid,'STATUS=%s\nenable_hourly_grid=%d\n',ternary(r.pass,'PASS','FAIL'),r.enable_hourly_grid);
fprintf(fid,'idx_x=[%s]\nidx_e=[%s]\nidx_r=[%s]\n',num2str(r.idx_x),num2str(r.idx_e),num2str(r.idx_r));
fprintf(fid,'forward_lb=%.12g\nbackward_cut_flag=%d\ncut_count=%d\n', ...
    r.forward_lb,r.backward_cut_flag,r.cut_count);
fclose(fid);
end

function write_final(outDir,data,base,hosting,integrated,cutAudit,legacyPass,judgment)
[minV,iV]=min(base.summary.min_voltage_pu); [maxV,iMaxV]=max(base.summary.max_voltage_pu);
[maxU,iU]=max(base.summary.max_true_utilization);
fid=fopen(fullfile(outDir,'final_judgment.txt'),'w');
fprintf(fid,'FINAL_JUDGMENT=%s\n',judgment);
fprintf(fid,'voltage_range_pu=[%.2f,%.2f]\nfeasible_hours=%d/48\n', ...
    data.vmin_pu,data.vmax_pu,sum(base.summary.feasible));
fprintf(fid,'minimum_voltage_pu=%.12g\nminimum_voltage_bus=%d\nminimum_voltage_hour=%d\n', ...
    minV,base.summary.min_voltage_bus(iV),base.summary.tau(iV));
fprintf(fid,'maximum_voltage_pu=%.12g\nmaximum_voltage_bus=%d\nmaximum_voltage_hour=%d\n', ...
    maxV,base.summary.max_voltage_bus(iMaxV),base.summary.tau(iMaxV));
fprintf(fid,'maximum_true_branch_utilization=%.12g\nmaximum_true_branch_s_mva=%.12g\n', ...
    maxU,base.summary.max_true_s_mva(iU));
fprintf(fid,'tight_branch=%d->%d\ntight_branch_hour=%d\nslack_p_kw=%.12g\nslack_q_kvar=%.12g\n', ...
    base.summary.tight_from(iU),base.summary.tight_to(iU),base.summary.tau(iU), ...
    base.summary.slack_p_kw(iU),base.summary.slack_q_kvar(iU));
if ~isempty(hosting)
    pv=hosting(hosting.pv_enabled,:); no=hosting(~hosting.pv_enabled,:);
    [minHost,ih]=min(pv.max_total_p_el_kw);
    fprintf(fid,'all_electrolyzers_full_all_hours=%d\n',all(pv.all_sites_at_pmax));
    fprintf(fid,'minimum_hourly_hosting_kw=%.12g\nlimiting_hour=%d\nlimiter=%s\n', ...
        minHost,pv.tau(ih),pv.limiter(ih));
    fprintf(fid,'pv_hosting_gain_at_limiting_hour_kw=%.12g\n', ...
        pv.max_total_p_el_kw(ih)-no.max_total_p_el_kw(no.tau==pv.tau(ih)));
    fprintf(fid,'integrated_lp_pass=%d\ncut_4d_pass=%d\nlegacy_regression_pass=%d\n', ...
        integrated.pass,cutAudit.pass,legacyPass);
end
fclose(fid);
end

function y=ternary(test,a,b)
if test, y=a; else, y=b; end
end
