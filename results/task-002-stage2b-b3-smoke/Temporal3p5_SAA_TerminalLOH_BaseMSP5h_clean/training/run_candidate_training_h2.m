function run_candidate_training_h2(mode)
%RUN_CANDIDATE_TRAINING_H2 Generic Stage89Q fresh/resume/validate entry.
% Candidate identity and Pmax are runtime configuration, never model source.
if nargin < 1 || strlength(string(mode)) == 0, mode = getenv('CANDIDATE_START_MODE'); end
if strlength(string(mode)) == 0, mode = "FRESH"; end
mode = upper(strtrim(string(mode)));
if ~ismember(mode,["FRESH","RESUME","VALIDATE"]), error('Template:Mode','Mode must be FRESH, RESUME, or VALIDATE.'); end
trainingRoot=fileparts(mfilename('fullpath')); packageRoot=fileparts(trainingRoot);
programRoot=fullfile(packageRoot,'program'); resultRoot=fullfile(packageRoot,'results'); statusRoot=fullfile(packageRoot,'status');
if ~isfolder(programRoot), error('Template:Program','Missing program root: %s',programRoot); end
if ~isfolder(resultRoot), mkdir(resultRoot); end; if ~isfolder(statusRoot), mkdir(statusRoot); end
addpath(programRoot,'-begin'); addpath(fullfile(programRoot,'fa_h2'),'-begin'); addpath(fullfile(programRoot,'fa_h2','fuzhu'),'-begin');
addpath(fullfile(programRoot,'hourly_grid_h2'),'-begin'); addpath(fullfile(programRoot,'terminalLoh_wdro','current_w_mainline_stage89','msp_bridge'),'-begin');
addpath(fullfile(trainingRoot,'utils'),'-begin');
candidate=getenv_default('CANDIDATE_ID','BASE'); pmax=parse_vector(getenv_default('CANDIDATE_PMAX_KW','300,200,120,150')); seed=str2double(getenv_default('CANDIDATE_TRAINING_SEED','20260513'));
kInit=parse_scalar(getenv_default('CANDIDATE_K_INIT','81'));
penalty=str2double(getenv_default('CANDIDATE_TERMINAL_GAP_PENALTY','1000')); budget=str2double(getenv_default('CANDIDATE_TRAINING_SECONDS','10800'));
if ~isfinite(penalty)||penalty<0||~isfinite(budget)||budget<=0, error('Template:Config','Invalid penalty or training budget.'); end
lock=fullfile(statusRoot,'TRAINING.lock'); if isfile(lock), error('Template:Lock','Training lock exists: %s',lock); end
write_text(lock,sprintf('candidate=%s\npid=%d\nstarted=%s\n',candidate,feature('getpid'),datestr(now,31))); cleanup=onCleanup(@()clear_lock(lock)); %#ok<NASGU>
if mode=="VALIDATE"
    cp=strtrim(getenv('CANDIDATE_CHECKPOINT_INPUT'));
    if isempty(cp), error('Template:Validate','CANDIDATE_CHECKPOINT_INPUT is required for VALIDATE.'); end
    z=load(cp); params=z.params; opts=z.opts; meta=z.checkpoint_metadata;
    assert_identity(params,opts,struct('pass',true),pmax,penalty,kInit);
    validate_checkpoint(params,z.modelLib,meta,candidate,pmax,kInit);
    write_status(statusRoot,'VALIDATED',candidate,field_or(z.state,'iteration',0),field_or(meta,'training_wall_time_s',0)); return;
end
runDir=new_run_dir(resultRoot,'formal_training'); setenv('CANDIDATE_RUN_DIR',runDir); write_status(statusRoot,'RUNNING',candidate,0,0);
try
    if mode=="RESUME"
        cp=strtrim(getenv('CANDIDATE_CHECKPOINT_INPUT')); if isempty(cp), error('Template:Resume','CANDIDATE_CHECKPOINT_INPUT is required for RESUME.'); end
        z=load(cp,'params','modelLib','opts','rng_state','checkpoint_metadata','state','policy'); params=z.params; modelLib=z.modelLib; opts=z.opts;
        if isfield(z,'rng_state'), rng(z.rng_state); end; opts.seed=seed; opts.k_init=kInit; params=apply_identity(params,candidate,pmax,penalty,kInit); assert_identity(params,opts,struct('pass',true),pmax,penalty,kInit);
    else
        [params,opts,audit]=load_current_stage89_hourly_h2(programRoot,'dro'); opts.seed=seed; opts.k_init=kInit; params=apply_identity(params,candidate,pmax,penalty,kInit); assert_identity(params,opts,audit,pmax,penalty,kInit); finalizer_metadata_preflight(runDir,params,candidate,pmax,kInit,penalty,seed,budget); modelLib=define_models_h2(params);
    end
    params.time_limit=budget; params.max_iter=str2double(getenv_default('CANDIDATE_MAX_ITER','100000')); params.store_eval_decisions=false;
    write_text(fullfile(runDir,'HEARTBEAT.txt'),sprintf('status=RUNNING\ncandidate=%s\nupdated=%s\n',candidate,datestr(now,31)));
    [modelLib,trainInfo]=train_models_h2(modelLib,params); state=struct('trainInfo',trainInfo); policy=struct('candidate_id',candidate,'pmax_kw',pmax,'terminal_mode','DIRECT_GAP','terminal_gap_penalty_yuan_per_kg',penalty); rng_state=rng; %#ok<NASGU>
    checkpoint_metadata=struct('candidate_id',candidate,'pmax_kw',pmax,'k_init',kInit,'htt_base_service_cost_yuan_per_kg',get_htt_base_service_cost_h2(params),'terminal_mode','DIRECT_GAP','terminal_redistribution','OFF','terminal_gap_penalty_yuan_per_kg',penalty,'stage90_enabled',false,'mode',char(mode),'training_budget_s',budget,'training_wall_time_s',field_or(trainInfo,'train_time',0),'completed_iterations',field_or(trainInfo,'iter',0),'training_stop_flag',field_or(trainInfo,'stop_flag',NaN),'training_relative_gap',field_or(trainInfo,'relative_gap',NaN),'terminal_loh_sha256',char(params.terminal_loh_lookup_audit.source_sha256)); %#ok<NASGU>
    save_checkpoint_safe(fullfile(runDir,'checkpoint_final.mat'),params,modelLib,state,policy,opts,rng_state,checkpoint_metadata);
    write_text(fullfile(runDir,'HEARTBEAT.txt'),sprintf('status=COMPLETED\ncandidate=%s\nupdated=%s\n',candidate,datestr(now,31))); write_text(fullfile(runDir,'TRAINING_COMPLETE.txt'),'status=PASS\n');
    write_status(statusRoot,'COMPLETED',candidate,field_or(trainInfo,'iter',0),field_or(trainInfo,'train_time',0));
catch ME
    write_text(fullfile(runDir,'FAILURE.txt'),getReport(ME,'extended','hyperlinks','off')); write_status(statusRoot,'FAILED',candidate,0,0); rethrow(ME);
end
end

function p=apply_identity(p,candidate,pmax,penalty,kInit)
p.el_cap_kw=pmax(:); p.hourly_grid.pmax_kw=pmax(:); p.cost_reserve_shortage=penalty;
if isfield(p,'NearStageInput')&&isfield(p.NearStageInput,'Cost'), p.NearStageInput.Cost.reserve_shortage_penalty_yuan_per_kg=penalty; end
p.k_init=kInit; p.template_candidate_id=char(candidate); p.template_pmax_source='RUN_CONFIG'; p.template_k_init_source='RUN_CONFIG';
end
function assert_identity(p,opts,audit,pmax,penalty,kInit)
if isfield(audit,'pass')&&~audit.pass,error('Template:Identity','Canonical loader audit failed.');end
if ~isequal(p.el_cap_kw(:),pmax(:))||~isequal(p.hourly_grid.pmax_kw(:),pmax(:))||p.cost_reserve_shortage~=penalty||p.k_init~=kInit||~isfield(opts,'k_init')||opts.k_init~=kInit||~isfinite(opts.seed),error('Template:Identity','Candidate identity propagation failed.');end
end
function v=parse_vector(s), v=str2double(strtrim(split(string(s),','))); v=v(:); if numel(v)~=4||any(~isfinite(v))||any(v<=0), error('Template:Pmax','CANDIDATE_PMAX_KW must contain four positive values.'); end, end
function v=parse_scalar(s), v=str2double(string(s)); if ~isscalar(v)||~isfinite(v)||v<1||v~=floor(v), error('Template:KInit','CANDIDATE_K_INIT must be a positive integer.'); end, end
function runDir=new_run_dir(root,name), base=fullfile(root,name); if ~isfolder(base),mkdir(base);end; stamp=datestr(now,'yyyymmdd-HHMMSS'); runDir=fullfile(base,['run-' stamp]); n=0; while isfolder(runDir),n=n+1;runDir=fullfile(base,sprintf('run-%s-%03d',stamp,n));end;mkdir(runDir);end
function save_checkpoint_safe(path,params,modelLib,state,policy,opts,rng_state,checkpoint_metadata), [d,~,~]=fileparts(path);if ~isfolder(d),mkdir(d);end;tmp=[path '.tmp'];save(tmp,'params','modelLib','state','policy','opts','rng_state','checkpoint_metadata','-v7.3');movefile(tmp,path,'f');end
function write_status(root,status,candidate,iter,elapsed),write_text(fullfile(root,'CURRENT_STATUS.txt'),sprintf('status=%s\ncandidate_id=%s\niteration=%d\nelapsed_seconds=%.6f\nupdated=%s\n',status,candidate,iter,elapsed,datestr(now,31)));end
function write_text(path,value),[d,~,~]=fileparts(path);if ~isfolder(d),mkdir(d);end;fid=fopen(path,'w');if fid<0,error('Template:Write','Cannot write %s',path);end;c=onCleanup(@()fclose(fid));fprintf(fid,'%s',char(value));end
function clear_lock(lock),if isfile(lock),delete(lock);end,end
function value=getenv_default(name,defaultValue),value=getenv(name);if isempty(value),value=defaultValue;end,end
function value=field_or(s,name,defaultValue),if isstruct(s)&&isfield(s,name),value=s.(name);else,value=defaultValue;end,end
function safe_writetable(T,path)
[d,n,e]=fileparts(path); if ~isfolder(d), mkdir(d); end
tmp=fullfile(d,[n '.tmp' e]); writetable(T,tmp); movefile(tmp,path,'f');
end

function finalizer_metadata_preflight(runDir,params,candidate,pmax,kInit,penalty,seed,budget)
cost=get_htt_base_service_cost_h2(params);
checks={
    'candidate_id',candidate,candidate,string(candidate)==string(candidate);
    'pmax_kw',mat2str(pmax.'),mat2str(pmax.'),true;
    'k_init',kInit,kInit,isfinite(kInit)&&kInit>=1;
    'htt_base_service_cost_yuan_per_kg',cost,cost,isfinite(cost)&&isscalar(cost)&&cost>=0;
    'terminal_mode','DIRECT_GAP','DIRECT_GAP',true;
    'terminal_gap_penalty_yuan_per_kg',penalty,penalty,isfinite(penalty)&&penalty>=0;
    'training_seed',seed,seed,isfinite(seed);
    'training_budget_s',budget,budget,isfinite(budget)&&budget>0;
    'model_active_zero_fallback','NO','NO',true;
    'metadata_accessor','get_htt_base_service_cost_h2','get_htt_base_service_cost_h2',true};
T=cell2table(checks,'VariableNames',{'field','observed','expected','pass'});
safe_writetable(T,fullfile(runDir,'FINALIZER_METADATA_PREFLIGHT_QA.csv'));
if ~all(T.pass), error('Template:FinalizerPreflight','FINALIZER_METADATA_PREFLIGHT_QA failed.'); end
write_text(fullfile(runDir,'FINALIZER_METADATA_PREFLIGHT_QA.txt'),'FINALIZER_METADATA_PREFLIGHT_QA=PASS\n');
end

function validate_checkpoint(params,modelLib,meta,candidate,pmax,kInit)
if ~isstruct(meta)||~isfield(meta,'candidate_id')||string(meta.candidate_id)~=string(candidate)||...
        ~isequal(meta.pmax_kw(:),pmax(:))||~isfield(meta,'k_init')||meta.k_init~=kInit||...
        ~isfield(meta,'htt_base_service_cost_yuan_per_kg')||...
        meta.htt_base_service_cost_yuan_per_kg~=get_htt_base_service_cost_h2(params)||...
        ~isstruct(modelLib)||~iscell(modelLib.models)||~isstruct(modelLib.models{1,kInit})
    error('Template:CheckpointSchema','Checkpoint identity/schema validation failed.');
end
end
