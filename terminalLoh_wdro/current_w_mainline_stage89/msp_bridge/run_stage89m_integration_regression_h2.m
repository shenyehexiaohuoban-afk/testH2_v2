function run_stage89m_integration_regression_h2()
%RUN_STAGE89M_INTEGRATION_REGRESSION_H2 Minimal Stage89K/8h integration QA.
% No training, OOS, policy generation, or checkpoint is performed.

rootDir = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
bridgeDir = fileparts(mfilename('fullpath'));
outDir = fullfile(rootDir,'results','task-002-stage2b-b3-smoke', ...
    'stage89m-formal-adoption-and-8h-integration','run-001');
addpath(rootDir);
addpath(fullfile(rootDir,'fa_h2'));
addpath(fullfile(rootDir,'fa_h2','fuzhu'));
addpath(fullfile(rootDir,'hourly_grid_h2'));
addpath(bridgeDir);
failureFile = fullfile(outDir,'FAILURE.txt');
if isfile(fullfile(outDir,'MATLAB_INTEGRATION_PASS.txt'))
    error('Stage89M:OutputExists','Refusing to overwrite completed integration regression.');
end
try
    execute(rootDir,bridgeDir,outDir);
catch ME
    write_text(failureFile,string(getReport(ME,'extended','hyperlinks','off')));
    rethrow(ME);
end
end

function execute(rootDir,bridgeDir,outDir)
[pDefault,optsDefault,aDefault] = load_current_stage89_hourly_h2(rootDir);
[pSaa,~,aSaa] = load_current_stage89_hourly_h2(rootDir,"saa");
[pDro,~,aDro] = load_current_stage89_hourly_h2(rootDir,"dro");

loaderRows = {
    "DEFAULT","DRO",aDefault.table_audit.source_file,aDefault.table_audit.source_sha256,"Stage89K",0.03,aDefault.default_mode_is_dro,aDefault.pass;
    "EXPLICIT_SAA","SAA",aSaa.table_audit.source_file,aSaa.table_audit.source_sha256,"Stage89K",0,false,aSaa.pass;
    "EXPLICIT_DRO","DRO",aDro.table_audit.source_file,aDro.table_audit.source_sha256,"Stage89K",0.03,false,aDro.pass};
loaderAudit = cell2table(loaderRows,'VariableNames',{'request','loaded_mode','source_file','source_sha256','table_version','eta','default_mode_selected','pass'});
writetable(loaderAudit,fullfile(outDir,'terminalLoh_loader_identity_audit.csv'));

mappingRows = cell(70,12); row=0;
for modeName = ["SAA","DRO"]
    if modeName=="SAA", p=pSaa; else, p=pDro; end
    for stateId=1:35
        a=floor((stateId-1)/7)+2; loc=mod(stateId-1,7)+1;
        k=p.state_id(a,loc,7); target=p.TerminalLOH(:,k);
        row=row+1;
        mappingRows(row,:)={modeName,stateId,a,loc,k,target(1),target(2),target(3),target(4), ...
            all(target>=-1e-12),all(target<=[300;200;100;200]+1e-7), ...
            k==((a-1)*7+(loc-1))*8+7};
    end
end
mapping = cell2table(mappingRows,'VariableNames',{'mode','state_id','intensity','loc','joint_state_k','T1_kg','T2_kg','T3_kg','T4_kg','nonnegative','within_tank_capacity','mapping_formula_pass'});
mapping.pass = mapping.nonnegative & mapping.within_tank_capacity & mapping.mapping_formula_pass;
writetable(mapping,fullfile(outDir,'terminalLoh_state_mapping_qa.csv'));

counts = zeros(6,1); dimensionRows=cell(8,18);
model6=[];
for t=1:6
    model=build_stage_model_h2(pDro,t);
    model=update_rhs_h2(model,pDro,pDro.k_init,t,pDro.x_0);
    counts(t)=size(model.idx.p_el_hourly,2);
    passRow=model.hourly_grid_enabled && model.hourly_h2_balance_enabled && ...
        model.hourly_htt_enabled && model.operational_stage_duration_h==8 && ...
        model.inner_dt_h==1 && counts(t)==8 && numel(model.idx.p_el_hourly)==32 && ...
        numel(model.idx.h2_inventory_pre_htt)==32 && ...
        numel(unique(model.idx.h2_inventory_hourly))==32 && ...
        numel(model.idx.f_hourly)==128 && numel(model.rowMap.hourly_demand_eq)==32 && ...
        numel(model.idx.p_branch)==256 && numel(model.idx.q_branch)==256 && ...
        numel(model.idx.v_sq)==264 && numel(model.idx.p_pv)==32 && ...
        model.source_hourly_demand_preserved && string(model.demand_schema)=="original-hourly-24h-repeat-v1";
    dimensionRows(t,:)={t,"OPERATING",counts(t),numel(model.idx.p_el_hourly), ...
        numel(model.rowMap.hourly_demand_eq),numel(model.idx.p_el_hourly), ...
        numel(model.idx.h2_inventory_pre_htt),numel(unique(model.idx.h2_inventory_hourly)), ...
        numel(model.idx.f_hourly),numel(model.idx.p_branch),numel(model.idx.q_branch), ...
        numel(model.idx.v_sq),numel(model.idx.p_pv),model.source_hourly_demand_preserved, ...
        model.hourly_grid_enabled,model.hourly_h2_balance_enabled,model.hourly_htt_enabled,passRow};
    if t==6, model6=model; end
end
dimensionRows(7,:)={7,"ANALYTIC_TERMINAL_LOH",0,0,0,0,0,0,0,0,0,0,0,true,false,false,false,true};
dimensionRows(8,:)={8,"ZERO_ABSORBING",0,0,0,0,0,0,0,0,0,0,0,true,false,false,false,true};
dimensions=cell2table(dimensionRows,'VariableNames',{'stage','role','hourly_period_count','p_el_variables','hourly_demand_equalities','h2_production_values','inventory_pre_htt_values','inventory_end_values','directed_htt_variables','p_branch_variables','q_branch_variables','voltage_variables','pv_variables','original_hourly_demand_active','hourly_grid_active','hourly_h2_active','hourly_htt_active','pass'});
writetable(dimensions,fullfile(outDir,'hourly_variable_count_by_stage.csv'));
runtimeAudit=validate_stage89_8h_runtime_h2(pDro,counts);

archRows={
    "FORMAL_8H_MAINLINE_USED","YES",runtimeAudit.pass;
    "LEGACY_6H_PATH_USED","NO",runtimeAudit.pass;
    "OPERATING_STAGE_COUNT","6",runtimeAudit.operating_stage_count==6;
    "HOURS_PER_OPERATING_STAGE","[8,8,8,8,8,8]",all(runtimeAudit.hours_per_operating_stage==8);
    "TOTAL_OPERATING_HOURS","48",runtimeAudit.total_operating_hours==48;
    "HOURLY_IEEE33","ACTIVE",all(dimensions.hourly_grid_active(1:6));
    "HOURLY_P_EL","ACTIVE",all(dimensions.p_el_variables(1:6)==32);
    "HOURLY_ORIGINAL_H2_DEMAND","ACTIVE",all(dimensions.original_hourly_demand_active(1:6));
    "HOURLY_H2_PRODUCTION","ACTIVE",all(dimensions.h2_production_values(1:6)==32);
    "HOURLY_INVENTORY","ACTIVE",all(dimensions.inventory_end_values(1:6)==32);
    "HOURLY_DIRECTED_CONTINUOUS_HTT","ACTIVE",all(dimensions.directed_htt_variables(1:6)==128);
    "PV","ACTIVE",all(dimensions.pv_variables(1:6)==32);
    "ELECTRICITY_GRID_CONSTRAINTS","ACTIVE",all(dimensions.p_branch_variables(1:6)==256);
    "STAGE7","ANALYTIC_TERMINAL_LOH",dimensions.pass(7);
    "STAGE8","ZERO_COST_ABSORBING",dimensions.pass(8)};
architecture=cell2table(archRows,'VariableNames',{'gate','observed','pass'});
writetable(architecture,fullfile(outDir,'formal_8h_architecture_audit.csv'));

theory8=pDro.el_cap_kw(:)*pDro.k_H2*8;
legacy6=pDro.el_cap_kw(:)*pDro.k_H2*6;
expected8=[46.8;31.2;18.72;23.4];
prodRows=cell(5,7);
for i=1:4
    prodRows(i,:)={"Site"+i,pDro.el_cap_kw(i),pDro.k_H2,8,theory8(i),legacy6(i),abs(theory8(i)-expected8(i))<=1e-10};
end
prodRows(5,:)={"TOTAL",sum(pDro.el_cap_kw),pDro.k_H2,8,sum(theory8),sum(legacy6),abs(sum(theory8)-120.12)<=1e-10 && abs(sum(theory8)-90.09)>1};
production=cell2table(prodRows,'VariableNames',{'scope','pmax_kw','conversion_kg_per_kWh','active_hours','theoretical_max_kg','legacy_6h_sentinel_kg','pass'});
writetable(production,fullfile(outDir,'stage1_production_cap_sentinel.csv'));

syncRows={
    "tank_capacity_kg",mat2str(pDro.x_cap(:).'),"[300 200 100 200]",isequal(pDro.x_cap(:).',[300 200 100 200]);
    "pmax_kw",mat2str(pDro.el_cap_kw(:).'),"[300 200 120 150]",isequal(pDro.el_cap_kw(:).',[300 200 120 150]);
    "site4_tank_kg",string(pDro.x_cap(4)),"200",pDro.x_cap(4)==200;
    "site4_pmax_kw",string(pDro.el_cap_kw(4)),"150",pDro.el_cap_kw(4)==150;
    "initial_inventory_kg",mat2str(pDro.x_0(:).',17),mat2str([58.04455704486949 50.30813793862475 25.262133442309338 33.02358084624278],17),~aDro.initial_inventory_rescaled;
    "initial_inventory_rescaled","NO","NO",~aDro.initial_inventory_rescaled;
    "active_dt_h",string(pDro.dt_h),"8",pDro.dt_h==8;
    "source_demand_stage_dt_h",string(pDro.NearStageInput.NormalDemand.stage_dt_h),"6_METADATA_ONLY",pDro.NearStageInput.NormalDemand.stage_dt_h==6;
    "terminal_version",pDro.terminal_loh_lookup_audit.table_version,"Stage89K",pDro.terminal_loh_lookup_audit.table_version=="Stage89K";
    "default_bridge_mode",upper(pDefault.terminal_loh_lookup_audit.mode),"DRO",upper(pDefault.terminal_loh_lookup_audit.mode)=="DRO"};
sync=cell2table(syncRows,'VariableNames',{'parameter','observed','expected','pass'});
writetable(sync,fullfile(outDir,'msp_parameter_sync_audit.csv'));

stage7Rows=cell(6,14); row=0; sentinel=[13 19 35];
for modeName=["SAA","DRO"]
    if modeName=="SAA", p=pSaa; else, p=pDro; end
    for s=sentinel
        a=floor((s-1)/7)+2; loc=mod(s-1,7)+1; k=p.state_id(a,loc,7);
        target=p.TerminalLOH(:,k); x=0.5*target;
        [value,grad,info]=terminal_value_and_subgradient_h2(x,p,k);
        expectedValue=p.cost_reserve_shortage*sum(max(0,target-x));
        expectedGrad=-p.cost_reserve_shortage*double(x<target-1e-9);
        pass=abs(value-expectedValue)<=1e-8 && numel(grad)==4 && ...
            max(abs(grad-expectedGrad))<=1e-12 && all(grad<=0) && ...
            all(grad>=-p.cost_reserve_shortage) && max(abs(info.shortage-max(0,target-x)))<=1e-12;
        row=row+1;
        stage7Rows(row,:)={modeName,s,a,loc,k,sum(target),sum(x),value,grad(1),grad(2),grad(3),grad(4),numel(grad),pass};
    end
end
stage7=cell2table(stage7Rows,'VariableNames',{'mode','state_id','intensity','loc','joint_state_k','target_total_kg','trial_inventory_total_kg','terminal_value_yuan','g1','g2','g3','g4','subgradient_dimension','pass'});
writetable(stage7,fullfile(outDir,'stage7_value_subgradient_smoke.csv'));

xTrial=zeros(pDro.Ni,1); Q=zeros(pDro.K,1); gState=zeros(pDro.K,pDro.Ni);
for k=1:pDro.K
    if pDro.is_loh_demand_stage(k)
        [Q(k),g]=terminal_value_and_subgradient_h2(xTrial,pDro,k);
        gState(k,:)=g(:).';
    end
end
predecessor=pDro.state_id(2,2,6); weights=pDro.P_joint(predecessor,:).';
expectedQ=weights.'*Q; expectedG=gState.'*weights; alpha=expectedQ-expectedG.'*xTrial;
baseRows=size(model6.A,1); modelCut=add_cut_h2(model6,expectedG,alpha); cutRow=modelCut.A(end,:);
allowed=false(1,modelCut.nvars); allowed(modelCut.idx.x)=true; allowed(modelCut.idx.theta)=true;
cutError=max(abs([cutRow(modelCut.idx.x).'-expectedG;cutRow(modelCut.idx.theta)+1;-modelCut.b(end)-alpha]));
cutPass=expectedQ>0 && any(abs(expectedG)>0) && size(modelCut.A,1)==baseRows+1 && ...
    nnz(cutRow(~allowed))==0 && numel(modelCut.idx.x)==4 && cutError<=1e-8;
cutTable=table(predecessor,expectedQ,expectedG(1),expectedG(2),expectedG(3),expectedG(4),alpha,baseRows,size(modelCut.A,1),cutError,cutPass, ...
    'VariableNames',{'predecessor_k','expected_terminal_value','g1','g2','g3','g4','alpha','rows_before','rows_after','max_cut_error','pass'});
writetable(cutTable,fullfile(outDir,'backward_terminal_cut_smoke.csv'));

s=35;a=6;loc=7;k=pDro.state_id(a,loc,7);target=pDro.TerminalLOH(:,k);xForward=0.25*target;
[forwardValue,forwardInfo]=eval_terminal_loh_h2(xForward,pDro,k);
[analyticValue,~,analyticInfo]=terminal_value_and_subgradient_h2(xForward,pDro,k);
forwardPass=abs(forwardValue-analyticValue)<=1e-10 && max(abs(forwardInfo.shortage-analyticInfo.shortage))<=1e-12;
forwardTable=table(s,a,loc,k,sum(target),sum(xForward),forwardValue,analyticValue,sum(forwardInfo.shortage),forwardPass, ...
    'VariableNames',{'state_id','intensity','loc','joint_state_k','target_total_kg','inventory_total_kg','forward_terminal_value','analytic_terminal_value','gap_total_kg','pass'});
writetable(forwardTable,fullfile(outDir,'forward_terminal_eval_smoke.csv'));

droFile=pDro.terminal_loh_lookup_audit.source_file;
stage88File=fullfile(rootDir,'terminalLoh_wdro','current_w_mainline_stage88','msp_bridge','terminal_loh_stage88_dro_eta003_cap200.csv');
stage53File=fullfile(rootDir,'results','task-002-stage2b-b3-smoke','53-35state-saa-vs-eta003-terminal-loh','run-024','terminal_loh_table_eta_003.csv');
badInput=pDro.NearStageInput; badInput.HydrogenDevice.tank_cap_kg(4)=150;
negativeRows=cell(5,5);
negativeRows(1,:)=negative_case("Stage89K table + Site4 tank=150","Stage89M:CapacityMismatch",@()load_stage89_adopted_terminal_loh_h2(pDro.S,badInput,"dro",droFile));
negativeRows(2,:)=negative_case("Stage88 hash masquerading as Stage89K","Stage89M:SourceHashMismatch",@()load_stage89_adopted_terminal_loh_h2(pDro.S,pDro.NearStageInput,"dro",stage88File));
negativeRows(3,:)=negative_case("Stage53 legacy table","Stage89M:SourceHashMismatch",@()load_stage89_adopted_terminal_loh_h2(pDro.S,pDro.NearStageInput,"dro",stage53File));
p6=pDro;p6.dt_h=6;
negativeRows(4,:)=negative_case("legacy 6h runtime","Stage89M:Formal8hGate",@()validate_stage89_8h_runtime_h2(p6,counts));
badCounts=counts;badCounts(4)=7;
negativeRows(5,:)=negative_case("hourly variable count not equal to 8","Stage89M:Formal8hGate",@()validate_stage89_8h_runtime_h2(pDro,badCounts));
negative=cell2table(negativeRows,'VariableNames',{'test','expected_identifier','observed_identifier','rejected','pass'});
writetable(negative,fullfile(outDir,'negative_gate_tests.csv'));

allPass=all(loaderAudit.pass) && all(mapping.pass) && all(dimensions.pass) && ...
    all(architecture.pass) && all(production.pass) && all(sync.pass) && ...
    all(stage7.pass) && cutPass && forwardPass && all(negative.pass) && ...
    strcmp(optsDefault.stage89_bundle_id,'current_w_mainline_stage89_v1');
if ~allPass
    error('Stage89M:RegressionFailed','One or more formal integration gates failed.');
end
write_text(fullfile(outDir,'MATLAB_INTEGRATION_PASS.txt'), ...
    "STAGE89M_INTEGRATION_REGRESSION=PASS"+newline+ ...
    "FORMAL_8H_MAINLINE_USED=YES"+newline+"LEGACY_6H_PATH_USED=NO"+newline+ ...
    "STAGE1_THEORETICAL_MAX_KG=120.12"+newline+"FA_MSP_TRAINING_RUN=NO"+newline+ ...
    "OOS_RUN=NO"+newline+"CHECKPOINT_CREATED=NO"+newline);
end

function out=negative_case(name,expectedIdentifier,callable)
observed="";rejected=false;
try
    callable();
catch ME
    observed=string(ME.identifier);rejected=true;
end
pass=rejected && observed==expectedIdentifier;
out={name,expectedIdentifier,observed,rejected,pass};
end

function write_text(path,text)
fid=fopen(path,'w');
if fid<0,error('Stage89M:WriteFailure','Cannot write %s.',path);end
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s',text);
end
