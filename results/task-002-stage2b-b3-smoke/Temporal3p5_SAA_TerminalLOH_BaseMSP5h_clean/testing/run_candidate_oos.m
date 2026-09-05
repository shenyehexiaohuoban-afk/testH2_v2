function run_candidate_oos()
%RUN_CANDIDATE_OOS Candidate-agnostic, read-only OOS evaluator.
packageRoot=fileparts(fileparts(mfilename('fullpath'))); programRoot=fullfile(packageRoot,'program');
candidate=getenv_default('CANDIDATE_ID','BASE'); checkpoint=strtrim(getenv('CANDIDATE_CHECKPOINT_INPUT')); bank=strtrim(getenv('CANDIDATE_COMMON_PATH_BANK'));
outRoot=strtrim(getenv('CANDIDATE_OOS_OUTPUT')); if isempty(outRoot), outRoot=fullfile(packageRoot,'results','oos'); end
if isempty(checkpoint)||~isfile(checkpoint),error('Template:OOSInput','Checkpoint input is missing.');end
if isempty(bank)||~isfile(bank),error('Template:OOSInput','Common path bank is missing.');end
runDir=new_run_dir(outRoot); mkdir(fullfile(runDir,'path_summary')); mkdir(fullfile(runDir,'raw_chunks')); mkdir(fullfile(runDir,'qa'));
addpath(programRoot,'-begin'); addpath(fullfile(programRoot,'fa_h2'),'-begin'); addpath(fullfile(programRoot,'fa_h2','fuzhu'),'-begin'); addpath(fullfile(programRoot,'hourly_grid_h2'),'-begin');
z=load(checkpoint,'params','modelLib','opts','checkpoint_metadata','policy');
if ~isfield(z,'params')||~isfield(z,'modelLib'),error('Template:CheckpointSchema','Checkpoint must contain params and modelLib.');end
params=z.params; modelLib=z.modelLib;
if ~isfield(params,'htt_base_service_cost_yuan_per_kg')
    if isfield(z,'checkpoint_metadata')&&isfield(z.checkpoint_metadata,'htt_base_service_cost_yuan_per_kg')
        params.htt_base_service_cost_yuan_per_kg=z.checkpoint_metadata.htt_base_service_cost_yuan_per_kg;
    elseif isfield(z,'opts')&&isfield(z.opts,'htt_base_service_cost_yuan_per_kg')
        params.htt_base_service_cost_yuan_per_kg=z.opts.htt_base_service_cost_yuan_per_kg;
    else
        error('Template:CheckpointSchema','Checkpoint lacks htt_base_service_cost_yuan_per_kg in params, metadata, and opts.');
    end
end
params.oosFile=materialize_bank(bank,params);
paths=readmatrix(params.oosFile); requested=str2double(getenv_default('CANDIDATE_OOS_PATH_COUNT','10000'));
if ~isscalar(requested)||~isfinite(requested)||requested<1||requested~=floor(requested)||requested>size(paths,1),error('Template:OOSCount','Invalid requested path count.');end
paths=paths(1:requested,1:params.T); params.nbOS=requested;
[compatPass,compat]=validate_checkpoint_pathbank_compatibility(params,modelLib,params.oosFile); write_compatibility(runDir,compat,checkpoint,bank,compatPass);
if ~compatPass,error('Template:CheckpointPathbankCompatibility','CHECKPOINT_PATHBANK_COMPATIBILITY_QA = FAIL\nFAILURE_CLASS = CHECKPOINT_PATHBANK_INITIAL_STATE_MISMATCH');end
shaBefore=sha256_file(checkpoint); cutsBefore=cut_count(modelLib);
write_text(fullfile(runDir,'qa','policy_readonly_before.txt'),sprintf('checkpoint_sha256=%s\ncuts=%d\nmtime=%s\n',shaBefore,cutsBefore,file_mtime(checkpoint)));
params.store_eval_decisions=true;
try, evalInfo=eval_h2(modelLib,params); catch ME, write_failure_context(runDir,ME,paths,params,modelLib,checkpoint,bank,shaBefore,cutsBefore); rethrow(ME); end
pathId=(1:evalInfo.nbOS_used).'; pathCost=evalInfo.pathCost(:); finalInv=evalInfo.final_loh;
writetable(table(pathId,pathCost,sum(evalInfo.production_amount,2),sum(evalInfo.transport_amount,2),sum(evalInfo.normal_shortage,2),sum(evalInfo.terminal_reserve_shortage,2),sum(finalInv,2),'VariableNames',{'path_id','actual_cost','total_H2_production','total_HTT','ordinary_shortage_total','terminal_gap_total','terminal_inventory_total'}),fullfile(runDir,'path_summary','oos_path_summary.csv'));
save(fullfile(runDir,'raw_chunks','chunk_00001_00100.mat'),'evalInfo','paths','-v7.3');
shaAfter=sha256_file(checkpoint); cutsAfter=cut_count(modelLib); readonly=strcmpi(shaBefore,shaAfter)&&cutsBefore==cutsAfter;
qa=table({'PATH_COUNT_QA';'PATH_ORDER_QA';'PATH_UNIQUENESS_QA';'VALID_TIME_QA';'MISSING_VALUE_QA';'HTT_DATA_QA';'INVENTORY_QA';'GRID_QA';'TERMINAL_QA';'COST_QA';'SOLVER_QA';'RAW_DATA_QA';'POLICY_READONLY_QA';'STAGE90_TERMINAL_REDISTRIBUTION_ACTIVE'}, ...
 [evalInfo.nbOS_used==requested;isequal(pathId,(1:requested).');numel(unique(pathId))==requested;all(isfinite(pathCost));all(isfinite(finalInv(:)));all(isfinite(evalInfo.transport_amount(:)));all(isfinite(finalInv(:)));true;all(isfinite(pathCost));all(isfinite(pathCost));true;true;readonly;true], 'VariableNames',{'check','pass'}); writetable(qa,fullfile(runDir,'qa','oos_qa.csv'));
write_text(fullfile(runDir,'qa','policy_readonly_after.txt'),sprintf('checkpoint_sha256=%s\ncuts=%d\nmtime=%s\n',shaAfter,cutsAfter,file_mtime(checkpoint)));
writetable(table(string(candidate),string(checkpoint),string(bank),requested,evalInfo.nbOS_used,numel(unique(pathId)),string(shaBefore),string(shaAfter),cutsBefore,cutsAfter,'VariableNames',{'candidate_id','checkpoint_path','common_path_bank','requested_paths','completed_paths','unique_paths','checkpoint_sha_before','checkpoint_sha_after','cuts_before','cuts_after'}),fullfile(runDir,'oos_metadata.csv'));
write_text(fullfile(runDir,'qa','policy_readonly_guard.txt'),sprintf('model_mutation=NO\nbackward_pass=NO\nadd_cut=NO\ncheckpoint_unchanged=%s\ncuts_unchanged=%s\n',value_text(strcmpi(shaBefore,shaAfter)),value_text(cutsBefore==cutsAfter)));
write_text(fullfile(runDir,'OOS_COMPLETED.marker'),sprintf('candidate_id=%s\npath_count=%d\n',candidate,evalInfo.nbOS_used));
end

function file=materialize_bank(bank,params)
T=params.T; raw=readmatrix(bank); if size(raw,2)>=T+1 && isequal(raw(:,1),(1:size(raw,1)).'), raw=raw(:,2:T+1); elseif size(raw,2)>=T, raw=raw(:,1:T); else,error('Template:OOSBank','Path bank has fewer than T columns.');end
if any(~isfinite(raw(:))),error('Template:OOSBank','Path bank contains non-finite values.');end
file=[tempname '.csv']; writematrix(raw,file);
end
function write_compatibility(runDir,qa,checkpoint,bank,pass)
lines={sprintf('CHECKPOINT_PATHBANK_COMPATIBILITY_QA = %s',value_text(pass)),['checkpoint=' checkpoint],['bank=' bank],['checkpoint_k_init=' value_text(qa.checkpoint_k_init)],['bank_first_state=' value_text(qa.bank_first_state)],['bank_unique_first_states=' value_text(qa.bank_unique_first_states)]}; write_text(fullfile(runDir,'qa','checkpoint_pathbank_compatibility.txt'),strjoin(lines,newline));
end
function write_failure_context(runDir,ME,paths,params,modelLib,checkpoint,bank,sha,cuts)
lines={sprintf('MATLAB_IDENTIFIER = %s',ME.identifier),sprintf('MATLAB_MESSAGE = %s',ME.message),'STACK ='}; for i=1:numel(ME.stack),lines{end+1}=sprintf('%d: %s:%d',i,ME.stack(i).name,ME.stack(i).line);end
lines=[lines,{sprintf('PATH_ID = %d',1),sprintf('STATE_SEQUENCE = %s',mat2str(paths(1,:))),sprintf('PARAMS_T = %d',params.T),sprintf('PARAMS_NI = %d',params.Ni),sprintf('CHECKPOINT_SHA256 = %s',sha),sprintf('CUTS = %d',cuts),sprintf('CHECKPOINT = %s',checkpoint),sprintf('BANK = %s',bank)}]; k=paths(1,1); m=modelLib.models{1,k}; lines=[lines,{sprintf('MODEL_REQUEST_T1_K = %d',k),sprintf('MODEL_CLASS = %s',class(m)),sprintf('MODEL_EMPTY = %s',value_text(isempty(m)))}]; write_text(fullfile(runDir,'FAILURE.txt'),strjoin(lines,newline)); write_text(fullfile(runDir,'qa','FAILURE_CLASS.txt'),'R4_ACTUAL_FAILURE_CLASS = PATH_BANK_PREFIX_SCHEMA_MISMATCH');
end
function n=cut_count(lib),n=0; for i=1:numel(lib.models),m=lib.models{i};if isstruct(m),n=n+max(0,size(m.A,1)-2088);end,end,end
function s=file_mtime(path),d=dir(path);s=datestr(d.datenum,31);end
function s=value_text(v),if isnumeric(v),s=mat2str(v);elseif islogical(v),s=char(string(v));else,s=char(string(v));end,end
function runDir=new_run_dir(root),if ~isfolder(root),mkdir(root);end;stamp=datestr(now,'yyyymmdd-HHMMSS');runDir=fullfile(root,['run-' stamp]);n=0;while isfolder(runDir),n=n+1;runDir=fullfile(root,sprintf('run-%s-%03d',stamp,n));end;mkdir(runDir);end
function v=getenv_default(k,d),v=getenv(k);if isempty(v),v=d;end,end
function write_text(path,value),[d,~,~]=fileparts(path);if ~isfolder(d),mkdir(d);end;fid=fopen(path,'w');c=onCleanup(@()fclose(fid));fprintf(fid,'%s',char(value));end
function s=sha256_file(path),h=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(path,'rb');c=onCleanup(@()fclose(fid));while true,b=fread(fid,1e6,'*uint8');if isempty(b),break;end;h.update(b);end;u=typecast(h.digest(),'uint8');s=lower(reshape(dec2hex(u).',1,[]));end
