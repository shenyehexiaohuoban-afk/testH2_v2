function run_stage89q_run002_checkpoint_recovery_audit_h2()
%RUN_STAGE89Q_RUN002_CHECKPOINT_RECOVERY_AUDIT_H2 One-load, read-only audit.

rootDir=fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(rootDir);addpath(fullfile(rootDir,'fa_h2'));addpath(fullfile(rootDir,'fa_h2','fuzhu'));
addpath(fullfile(rootDir,'hourly_grid_h2'));addpath(fullfile(rootDir,'utils'));
checkpoint=string(getenv('STAGE89Q_RECOVERY_CHECKPOINT'));
expectedSha=lower(string(getenv('STAGE89Q_RECOVERY_SHA256')));
auditFile=string(getenv('STAGE89Q_RECOVERY_AUDIT_FILE'));
if checkpoint==""||expectedSha==""||auditFile==""
    error('Stage89QRecovery:Environment','Recovery environment is incomplete.');
end

rows=cell(0,5);
add('checkpoint_load_count','1','1',true,'load is called exactly once in this process');
loaded=load(checkpoint); % Exactly one checkpoint load in this recovery process.
required={'params','modelLib','state','policy','opts','rng_state','checkpoint_metadata'};
present=fieldnames(loaded);
add('required_checkpoint_variables',strjoin(sort(string(present)),','),strjoin(sort(string(required)),','),all(ismember(required,present)),'top-level checkpoint structure');
if ~all(ismember(required,present)),finish(false);return;end

p=loaded.params;lib=loaded.modelLib;state=loaded.state;opts=loaded.opts;m=loaded.checkpoint_metadata;
add('stage_identity',string(m.stage),'89Q',string(m.stage)=="89Q",'checkpoint metadata');
add('arm_identity',string(m.arm_label),'Arm-A',string(m.arm_label)=="Arm-A",'checkpoint metadata');
add('terminal_gap_penalty',num(m.terminal_gap_penalty_yuan_per_kg),'1000',m.terminal_gap_penalty_yuan_per_kg==1000,'checkpoint metadata');
add('ordinary_shortage_penalty',num(m.shortage_penalty_yuan_per_kg),'200',m.shortage_penalty_yuan_per_kg==200,'checkpoint metadata');
add('training_seed_metadata',num(m.training_seed),'20260513',m.training_seed==20260513,'checkpoint metadata');
add('training_seed_options',num(opts.seed),'20260513',opts.seed==20260513,'checkpoint options');
add('completed_iterations',num(m.completed_iterations),'346',m.completed_iterations==346,'checkpoint metadata');
add('state_LB_length',num(numel(state.LB)),'346',numel(state.LB)==346,'checkpoint state');
add('final_LB_identity',num(state.LB(end)),num(m.final_LB),abs(state.LB(end)-m.final_LB)<=1e-9,'state versus metadata');
add('cumulative_cuts_metadata',num(m.cumulative_cuts),'363646',m.cumulative_cuts==363646,'checkpoint metadata');
add('fresh_initial_cut_count',num(m.fresh_initial_cut_count),'0',m.fresh_initial_cut_count==0,'checkpoint metadata');
add('warm_start_checkpoint',string(m.warm_start_checkpoint),'NONE',string(m.warm_start_checkpoint)=="NONE",'checkpoint metadata');
add('source_freeze_commit',string(m.frozen_commit),'cfa789f262b323de1775e5e2376a2d23978753ef',string(m.frozen_commit)=="cfa789f262b323de1775e5e2376a2d23978753ef",'checkpoint metadata');
add('terminal_table_sha256',string(m.terminal_lookup_sha256),'2fa1958944110701239a109ebf46d959324a351f2f27c1c3fbd62f333066eaa8',string(m.terminal_lookup_sha256)=="2fa1958944110701239a109ebf46d959324a351f2f27c1c3fbd62f333066eaa8",'Stage89K DRO table');
add('eta',num(m.eta),'0.03',abs(m.eta-0.03)<=1e-12,'checkpoint metadata');
add('model_schema',string(m.model_schema),'hourly-h2-hourly-htt-v1',string(m.model_schema)=="hourly-h2-hourly-htt-v1",'checkpoint metadata');
add('params_penalty',num(p.cost_reserve_shortage),'1000',p.cost_reserve_shortage==1000,'checkpoint params');
add('params_runtime',num(6*p.dt_h),'48',p.dt_h==8&&p.T==8,'six operating stages by eight hours');
add('params_initial_loc',num(p.S(p.k_init,2)),'4',p.S(p.k_init,2)==4,'checkpoint params');
add('params_site4_tank',num(p.x_cap(4)),'200',p.x_cap(4)==200,'checkpoint params');
add('params_site4_pmax',num(p.el_cap_kw(4)),'150',p.el_cap_kw(4)==150,'checkpoint params');
add('state_x_shape',mat2str(size(state.x)),'[4 8]',isequal(size(state.x),[4 8]),'checkpoint state');
add('state_theta_shape',mat2str(size(state.theta)),'[8 1]',isequal(size(state.theta),[8 1]),'checkpoint state');
add('state_values_finite',string(all(isfinite([state.x(:);state.theta(:);state.LB(:)]))),'true',all(isfinite([state.x(:);state.theta(:);state.LB(:)])),'checkpoint state');

[cutCount,modelCount,structurePass,cutFinite,cutStateOnly,thetaCoefficientPass]=audit_library(lib,p);
add('operating_model_count',num(modelCount),'>0',modelCount>0,'nonempty Stage1-6 modelLib cells');
add('model_structure_complete',string(structurePass),'true',structurePass,'hourly grid/H2/HTT flags, indices, dimensions');
add('recomputed_cut_count',num(cutCount),'363646',cutCount==363646,'sum of rows beyond immutable base models');
add('all_cut_coefficients_finite',string(cutFinite),'true',cutFinite,'all persisted cut x/theta/RHS coefficients');
add('all_cuts_state_theta_only',string(cutStateOnly),'true',cutStateOnly,'no persisted cut coefficient outside x/theta');
add('all_cut_theta_coefficients',string(thetaCoefficientPass),'true',thetaCoefficientPass,'theta coefficient equals -1');

beforeRows=model_rows(lib,p);model=update_rhs_h2(lib.models{1,p.k_init},p,p.k_init,1,p.x_0);sol=solve_stage_model_h2(model);
afterRows=model_rows(lib,p);stage1Production=sum(sol.h2_production_hourly_kg,'all');
eqResidual=max(abs(model.Aeq*sol.xraw-model.beq));ineqViolation=max([0;model.A*sol.xraw-model.b]);
add('minimal_solve_status',string(sol.status),'OPTIMAL_OR_NORMAL',strcmpi(sol.status,'OPTIMAL')||strcmpi(sol.status,'normal'),'one read-only Stage1 policy solve');
add('minimal_solve_stage1_production_kg',num(stage1Production),'113.88',abs(stage1Production-113.88)<=1e-8,'same frozen policy and initial state');
add('minimal_solve_eq_residual',num(eqResidual),'<=1e-6',eqResidual<=1e-6,'one read-only Stage1 solve');
add('minimal_solve_ineq_violation',num(ineqViolation),'<=1e-6',ineqViolation<=1e-6,'one read-only Stage1 solve');
add('model_rows_unchanged',string(isequal(beforeRows,afterRows)),'true',isequal(beforeRows,afterRows),'no training or cut mutation');
add('checkpoint_sha256_external',expectedSha,'64 lowercase hex',strlength(expectedSha)==64&&~isempty(regexp(expectedSha,'^[0-9a-f]{64}$','once')),'computed by PowerShell before MATLAB launch');
finish(all(cell2mat(rows(:,4))));

    function add(name,observed,expected,pass,evidence)
        rows(end+1,:)={string(name),string(observed),string(expected),logical(pass),string(evidence)};
    end
    function finish(pass)
        add('matlab_internal_recovery_audit',string(pass),'true',pass,'all MATLAB-side identity, structure, cut, and solve checks');
        T=cell2table(rows,'VariableNames',{'check','observed','expected','pass','evidence'});
        writetable(T,auditFile);
        if ~pass,error('Stage89QRecovery:Rejected','Checkpoint recovery audit failed.');end
    end
end

function [cutCount,modelCount,structurePass,cutFinite,stateOnly,thetaOk]=audit_library(lib,p)
cutCount=0;modelCount=0;structurePass=true;cutFinite=true;stateOnly=true;thetaOk=true;base=base_rows(p);
structurePass=structurePass&&isstruct(lib)&&isfield(lib,'models')&&iscell(lib.models)&&size(lib.models,1)>=6&&size(lib.models,2)==p.K;
if ~structurePass,return;end
for t=1:6
    for k=1:p.K
        model=lib.models{t,k};if isempty(model),continue;end
        modelCount=modelCount+1;
        required={'A','b','Aeq','beq','idx','nvars','hourly_grid_enabled','hourly_h2_balance_enabled','hourly_htt_enabled'};
        structurePass=structurePass&&all(isfield(model,required))&&model.nvars==1129&&size(model.A,1)>=base&& ...
            model.hourly_grid_enabled&&model.hourly_h2_balance_enabled&&model.hourly_htt_enabled&& ...
            isfield(model.idx,'x')&&isfield(model.idx,'theta')&&numel(model.idx.x)==4;
        if ~structurePass,continue;end
        for r=base+1:size(model.A,1)
            cutCount=cutCount+1;values=[full(model.A(r,model.idx.x)),full(model.A(r,model.idx.theta)),model.b(r)];
            cutFinite=cutFinite&&all(isfinite(values));allowed=false(1,model.nvars);allowed(model.idx.x)=true;allowed(model.idx.theta)=true;
            stateOnly=stateOnly&&nnz(model.A(r,~allowed))==0;thetaOk=thetaOk&&abs(model.A(r,model.idx.theta)+1)<=1e-12;
        end
    end
end
end

function rows=model_rows(lib,p)
rows=zeros(6,p.K);for t=1:6,for k=1:p.K,model=lib.models{t,k};if ~isempty(model),rows(t,k)=size(model.A,1);end,end,end
end
function n=base_rows(p),n=8+4*8+8*8*p.hourly_grid.n_branch;end
function value=num(value),value=string(sprintf('%.15g',double(value)));end
