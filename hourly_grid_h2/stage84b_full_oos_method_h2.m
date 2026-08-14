function out = stage84b_full_oos_method_h2(checkpointFile,pathBank,outDir,method,runDir,lineage,pid)
%STAGE84B_FULL_OOS_METHOD_H2 Evaluate one frozen policy on every supplied path.

c=load(checkpointFile,'params','modelLib','policy','checkpoint_metadata');
p=c.params;lib=c.modelLib;
assert_identity(c,method,lineage.training_commit,size(pathBank,1));
checkpointBefore=dir(checkpointFile);checkpointHashBefore=sha256_file(checkpointFile);
cutsBefore=cut_count(lib,p);
if cutsBefore~=c.checkpoint_metadata.cumulative_cuts
    error('Stage84B:CutIdentity','Loaded cut count differs from checkpoint metadata.');
end

dirs={fullfile(outDir,'path-batches'),fullfile(outDir,'stage-site-batches'), ...
    fullfile(outDir,'hourly-batches')};
for i=1:numel(dirs),mkdir(dirs{i});end
pathNames=path_names();stageNames=stage_names();
pathRows=cell(0,numel(pathNames));stageRows=cell(0,numel(stageNames));
hourTemplate=empty_hour(NaN,method,zeros(1,p.T),p);hourBatch=hourTemplate([]);
pathBatch=0;hourBatchId=0;completed=0;pure=0;manifest=empty_manifest();trace=empty_trace();
nPaths=size(pathBank,1);write_status(runDir,'RUNNING',phase_name(method),method,0,0,0,pid,lineage);

for q=1:nPaths
    t0=tic;
    [pr,sr,hr]=evaluate_one(lib,p,pathBank(q,:),q,method);
    elapsed=toc(t0);pure=pure+elapsed;completed=q;
    pathRows(end+1,:)=pr; %#ok<AGROW>
    stageRows=[stageRows;sr]; %#ok<AGROW>
    hourBatch(end+1)=hr; %#ok<AGROW>

    if numel(hourBatch)==25||q==nPaths
        hourBatchId=hourBatchId+1;
        firstId=hourBatch(1).path_id;lastId=hourBatch(end).path_id;
        file=fullfile(dirs{3},sprintf('oos_hourly_grid_response_batch_%04d.mat',hourBatchId));
        save_hour_batch(file,hourBatch,p,method,lineage);
        manifest=add_manifest(manifest,file,method,firstId,lastId,numel(hourBatch), ...
            sprintf('struct[%d] with 19-field hourly schema',numel(hourBatch)),runDir);
        hourBatch=hourBatch([]);
    end

    if size(pathRows,1)==100||q==nPaths
        pathBatch=pathBatch+1;firstId=pathRows{1,2};lastId=pathRows{end,2};
        pathFile=fullfile(dirs{1},sprintf('oos_path_batch_%04d.csv',pathBatch));
        stageFile=fullfile(dirs{2},sprintf('oos_stage_site_batch_%04d.csv',pathBatch));
        write_table_safe(cell2table(pathRows,'VariableNames',pathNames),pathFile);
        write_table_safe(cell2table(stageRows,'VariableNames',stageNames),stageFile);
        manifest=add_manifest(manifest,pathFile,method,firstId,lastId,size(pathRows,1), ...
            sprintf('CSV path schema v1: %d columns',numel(pathNames)),runDir);
        manifest=add_manifest(manifest,stageFile,method,firstId,lastId,size(stageRows,1), ...
            sprintf('CSV stage-site schema v1: %d columns',numel(stageNames)),runDir);
        pathRows=cell(0,numel(pathNames));stageRows=cell(0,numel(stageNames));
    end

    if mod(q,25)==0||q==nPaths
        trace=[trace;table(method,q,pure,elapsed,pathBatch,hourBatchId, ...
            'VariableNames',trace.Properties.VariableNames)]; %#ok<AGROW>
        write_table_safe(trace,fullfile(outDir,'progress_trace.csv'));
        write_table_safe(manifest,fullfile(outDir,'file_manifest.csv'));
        closedAllLayers=min(q,pathBatch*100);
        write_status(runDir,'RUNNING',phase_name(method),method,q,pure,closedAllLayers,pid,lineage);
    end
end

if completed~=nPaths
    error('Stage84B:IncompleteMethod','%s completed %d/%d paths.',method,completed,nPaths);
end
cutsAfter=cut_count(lib,p);checkpointAfter=dir(checkpointFile);checkpointHashAfter=sha256_file(checkpointFile);
checkpointUnchanged=checkpointBefore.bytes==checkpointAfter.bytes&& ...
    checkpointBefore.datenum==checkpointAfter.datenum&&checkpointHashBefore==checkpointHashAfter;
if cutsAfter~=cutsBefore||~checkpointUnchanged
    error('Stage84B:PolicyMutation','Policy/cut/checkpoint identity changed during %s OOS.',method);
end

pathFile=fullfile(outDir,'oos_path_summary.csv');stageFile=fullfile(outDir,'oos_stage_site_response.csv');
merge_csv_batches(dirs{1},'oos_path_batch_*.csv',pathFile);
merge_csv_batches(dirs{2},'oos_stage_site_batch_*.csv',stageFile);
pathTable=readtable(pathFile);stageTable=readtable(stageFile);
if height(pathTable)~=nPaths||height(stageTable)~=nPaths*p.T*4|| ...
        ~isequal(pathTable.path_id,(1:nPaths).')
    error('Stage84B:ReloadCount','Reloaded %s row counts or path IDs are invalid.',method);
end
for q=1:nPaths
    if string(pathTable.state_sequence(q))~=strjoin(string(pathBank(q,:)),'-')
        error('Stage84B:ReloadPathIdentity','Reloaded path sequence mismatch at %s path %d.',method,q);
    end
end
manifest=add_manifest(manifest,pathFile,method,1,nPaths,height(pathTable), ...
    sprintf('CSV path schema v1: %d columns',width(pathTable)),runDir);
manifest=add_manifest(manifest,stageFile,method,1,nPaths,height(stageTable), ...
    sprintf('CSV stage-site schema v1: %d columns',width(stageTable)),runDir);

metadata=table(method,nPaths,completed,pure,0,string(checkpointFile),checkpointHashBefore, ...
    cutsBefore,cutsAfter,checkpointUnchanged,lineage.training_commit,lineage.oos_fix_commit, ...
    lineage.oos_run_commit,"ALL_PATHS_COMPLETED", ...
    'VariableNames',{'method','requested_paths','completed_paths','pure_evaluation_time_s', ...
    'constraint_violations','checkpoint','checkpoint_sha256','cuts_before','cuts_after', ...
    'checkpoint_unchanged','training_commit','oos_fix_commit','oos_run_commit','stop_reason'});
write_table_safe(metadata,fullfile(outDir,'oos_metadata.csv'));
write_table_safe(manifest,fullfile(outDir,'file_manifest.csv'));
write_status(runDir,'RUNNING',phase_name(method)+"_COMPLETE",method,nPaths,pure,nPaths,pid,lineage);
out=struct('method',method,'completed_paths',completed,'pure_time_s',pure, ...
    'constraint_violations',0,'cuts_before',cutsBefore,'cuts_after',cutsAfter, ...
    'checkpoint_unchanged',checkpointUnchanged,'path_file',pathFile,'stage_file',stageFile);
clear lib c
end

function [pr,srows,hour]=evaluate_one(lib,p,kpath,pathId,method)
prev=p.x_0;absorbed=false;operatingCost=0;terminalValue=0;terminalGap=0;shortage=0;
prod=zeros(4,1);htt=zeros(4);finalInv=prev;minV=inf;minBus=NaN;minHour=NaN;
maxS=0;maxUtil=0;maxFrom=NaN;maxTo=NaN;maxHour=NaN;limited=zeros(4,1);
pvAvail=0;pvUsed=0;gridImport=0;terminalK=0;terminalStage=0;srows={};
pElEnergy=zeros(4,1);siteMinV=inf(4,1);siteBind=zeros(4,1);operatingHours=0;
hour=empty_hour(pathId,method,kpath,p);

for t=1:p.T
    k=kpath(t);beginInv=prev;status="post_absorb";
    r=zeros(4,1);f=zeros(4);u=zeros(4,1);z=zeros(4,1);ending=prev;
    pElMean=nan(4,1);stageSiteMinV=nan(4,1);stageSiteBind=zeros(4,1);
    stagePvAvail=0;stagePvUsed=0;stageGridImport=0;stageMaxUtil=NaN;
    if ~absorbed
        if p.is_dissipated(k),status="dissipated_absorb";absorbed=true;
        elseif p.is_absorbing(k),status="absorbing_lfNc";absorbed=true;
        elseif p.is_loh_demand_stage(k)
            [tc,ti]=eval_terminal_loh_h2(prev,p,k);terminalValue=tc;terminalGap=sum(ti.shortage);
            terminalK=k;terminalStage=t;status="loh_demand_stage";absorbed=true;
        else
            if t>6,error('Stage84B:NonOperatingStage','Ordinary state at path %d stage %d.',pathId,t);end
            m=update_rhs_h2(lib.models{t,k},p,k,t,prev);s=solve_stage_model_h2(m);status="normal";
            if any(~isfinite(s.xraw))||any(~isfinite(s.lambda.inventory_eq))
                error('Stage84B:NonFinite','Nonfinite solution/dual at path %d stage %d.',pathId,t);
            end
            eq=m.Aeq*s.xraw-m.beq;ineq=m.A*s.xraw-m.b;v=sqrt(max(s.v_sq,0));
            trueS=hypot(s.p_branch_kw,s.q_branch_kvar)/1000;
            if max(abs(eq))>1e-6||max([0;ineq])>1e-6|| ...
                    min(v,[],'all')<p.hourly_grid.vmin_pu-1e-7|| ...
                    max(v,[],'all')>p.hourly_grid.vmax_pu+1e-7|| ...
                    max(trueS,[],'all')>p.hourly_grid.branch_smax_mva+1e-7
                error('Stage84B:ConstraintViolation','Constraint violation at path %d stage %d.',pathId,t);
            end
            stageCost=s.obj-s.theta;
            if ~isfinite(stageCost),error('Stage84B:NonFiniteCost','Nonfinite cost at path %d stage %d.',pathId,t);end
            operatingCost=operatingCost+stageCost;r=s.rval;f=s.fval;u=s.u_normal;z=s.z_normal;ending=s.xval;
            prod=prod+r;htt=htt+f;shortage=shortage+sum(z);gridImport=gridImport+sum(s.p_grid_kw);
            operatingHours=operatingHours+8;pElEnergy=pElEnergy+sum(s.p_el_hourly_kw,2);
            [vv,ix]=min(v(:));[bb,hh]=ind2sub(size(v),ix);tau=8*(t-1)+hh;
            if vv<minV,minV=vv;minBus=bb;minHour=tau;end
            [ss,ix]=max(trueS(:));[ell,hh]=ind2sub(size(trueS),ix);util=ss/p.hourly_grid.branch_smax_mva;
            if util>maxUtil,maxS=ss;maxUtil=util;maxFrom=p.hourly_grid.branch_from(ell); ...
                    maxTo=p.hourly_grid.branch_to(ell);maxHour=8*(t-1)+hh;end
            tauVec=8*(t-1)+(1:8);avail=p.hourly_grid.pv_cap_kw(:)*p.hourly_grid.phi48(tauVec(:)).';
            stagePvAvail=sum(avail,'all');stagePvUsed=sum(s.p_pv_kw,'all');stageGridImport=sum(s.p_grid_kw);
            stageMaxUtil=max(trueS,[],'all')/p.hourly_grid.branch_smax_mva;
            pvAvail=pvAvail+stagePvAvail;pvUsed=pvUsed+stagePvUsed;
            for site=1:4
                bus=p.hourly_grid.site_elec_bus(site);siteV=v(bus,:);pElMean(site)=mean(s.p_el_hourly_kw(site,:));
                stageSiteMinV(site)=min(siteV);stageSiteBind(site)=sum(siteV<=p.hourly_grid.vmin_pu+1e-5);
                siteMinV(site)=min(siteMinV(site),stageSiteMinV(site));siteBind(site)=siteBind(site)+stageSiteBind(site);
                for h=1:8
                    below=s.p_el_hourly_kw(site,h)<p.el_cap_kw(site)-1e-6;
                    limited(site)=limited(site)+double(below&&(siteV(h)<=p.hourly_grid.vmin_pu+1e-5|| ...
                        max(trueS(:,h))/p.hourly_grid.branch_smax_mva>=0.999));
                end
            end
            hour=store_hour(hour,t,k,s,v,trueS,avail,p.k_H2);prev=ending;finalInv=ending;
        end
    end
    for site=1:4
        srows(end+1,:)={method,pathId,t,k,p.S(k,1),p.S(k,2),p.S(k,3),status,site, ...
            beginInv(site),r(site),ending(site),p.D_normal(site,t),u(site),z(site), ...
            sum(f(:,site)),sum(f(site,:)),sum(f(:,site))-sum(f(site,:)),pElMean(site), ...
            stageSiteMinV(site),stageSiteBind(site),stagePvAvail,stagePvUsed,stagePvAvail-stagePvUsed, ...
            stageGridImport,stageMaxUtil}; %#ok<AGROW>
    end
end
if isinf(minV),minV=NaN;end
siteMinV(isinf(siteMinV))=NaN;freq=limited/48;meanPEl=pElEnergy/max(1,operatingHours);
seq=strjoin(string(kpath),'-');totalCost=operatingCost+terminalValue;
pr={method,pathId,seq,totalCost,operatingCost,terminalValue,terminalGap,shortage,sum(prod), ...
    prod(1),prod(2),prod(3),prod(4),sum(htt,'all'), ...
    htt(1,2),htt(1,3),htt(1,4),htt(2,1),htt(2,3),htt(2,4),htt(3,1),htt(3,2), ...
    htt(3,4),htt(4,1),htt(4,2),htt(4,3),finalInv(1),finalInv(2),finalInv(3),finalInv(4), ...
    sum(finalInv),minV,minBus,minHour,maxS,maxUtil,maxFrom,maxTo,maxHour, ...
    limited(1),limited(2),limited(3),limited(4),freq(1),freq(2),freq(3),freq(4),operatingHours, ...
    meanPEl(1),meanPEl(2),meanPEl(3),meanPEl(4),siteMinV(1),siteMinV(2),siteMinV(3),siteMinV(4), ...
    siteBind(1),siteBind(2),siteBind(3),siteBind(4),pvAvail,pvUsed,pvAvail-pvUsed, ...
    pvUsed/max(eps,pvAvail),gridImport,terminalK,terminalStage,p.S(kpath(end),1),p.S(kpath(end),2),p.S(kpath(end),3)};
end

function hour=empty_hour(pathId,method,kpath,p)
hour=struct('method',method,'path_id',pathId,'state_sequence',kpath(:).','global_hour',[], ...
    'stage',[],'markov_state',[],'p_el_kw',[],'h2_production_kg',[],'pv_available_kw',[], ...
    'pv_utilized_kw',[],'pv_curtailed_kw',[],'grid_import_kw',[],'bus_voltage_pu',[], ...
    'branch_p_kw',[],'branch_q_kvar',[],'branch_true_s_mva',[], ...
    'site_electrical_bus',p.hourly_grid.site_elec_bus(:).','branch_from',p.hourly_grid.branch_from(:).', ...
    'branch_to',p.hourly_grid.branch_to(:).');
end

function hour=store_hour(hour,t,k,s,v,trueS,avail,kH2)
tau=8*(t-1)+(1:8);hour.global_hour=[hour.global_hour,tau];hour.stage=[hour.stage,repmat(t,1,8)];
hour.markov_state=[hour.markov_state,repmat(k,1,8)];hour.p_el_kw=[hour.p_el_kw,s.p_el_hourly_kw];
hour.h2_production_kg=[hour.h2_production_kg,kH2*s.p_el_hourly_kw];
hour.pv_available_kw=[hour.pv_available_kw,avail];hour.pv_utilized_kw=[hour.pv_utilized_kw,s.p_pv_kw];
hour.pv_curtailed_kw=[hour.pv_curtailed_kw,avail-s.p_pv_kw];hour.grid_import_kw=[hour.grid_import_kw,s.p_grid_kw(:).'];
hour.bus_voltage_pu=[hour.bus_voltage_pu,v];hour.branch_p_kw=[hour.branch_p_kw,s.p_branch_kw];
hour.branch_q_kvar=[hour.branch_q_kvar,s.q_branch_kvar];hour.branch_true_s_mva=[hour.branch_true_s_mva,trueS];
end

function save_hour_batch(path,hourly_response,p,method,lineage)
metadata=struct('method',method,'schema_version','stage84b-hourly-v1','training_commit',lineage.training_commit, ...
    'oos_fix_commit',lineage.oos_fix_commit,'oos_run_commit',lineage.oos_run_commit, ...
    'site_order','Site1,Site2,Site3,Site4','state_order','I1,I2,I3,I4', ...
    'site_electrical_bus',p.hourly_grid.site_elec_bus,'branch_from',p.hourly_grid.branch_from, ...
    'branch_to',p.hourly_grid.branch_to,'voltage_unit','p.u.','power_unit','kW/kVAr','h2_unit','kg');
temp=[path '.tmp.mat'];save(temp,'hourly_response','metadata','-v7.3');
vars=whos('-file',temp);
if ~all(ismember({'hourly_response','metadata'},{vars.name}))
    error('Stage84B:BatchWrite','Incomplete hourly batch %s.',temp);
end
movefile(temp,path,'f');
reloaded=load(path,'hourly_response','metadata');
if numel(reloaded.hourly_response)~=numel(hourly_response)|| ...
        string(reloaded.metadata.schema_version)~="stage84b-hourly-v1"
    error('Stage84B:BatchReload','Hourly batch reload count/metadata mismatch: %s.',path);
end
expected=hour_fields();
for i=1:numel(reloaded.hourly_response)
    r=reloaded.hourly_response(i);H=numel(r.global_hour);
    if ~isequal(fieldnames(r),expected(:))||mod(H,8)~=0||H>48|| ...
            any(r.stage<1|r.stage>6)||~isequal(size(r.p_el_kw),[4,H])|| ...
            ~isequal(size(r.h2_production_kg),[4,H])||~isequal(size(r.pv_available_kw),[4,H])|| ...
            ~isequal(size(r.pv_utilized_kw),[4,H])||~isequal(size(r.pv_curtailed_kw),[4,H])|| ...
            ~isequal(size(r.grid_import_kw),[1,H])||~isequal(size(r.bus_voltage_pu),[33,H])|| ...
            ~isequal(size(r.branch_p_kw),[32,H])||~isequal(size(r.branch_q_kvar),[32,H])|| ...
            ~isequal(size(r.branch_true_s_mva),[32,H])
        error('Stage84B:BatchSchema','Hourly batch schema/dimension mismatch: %s record %d.',path,i);
    end
end
end

function fields=hour_fields()
fields={'method','path_id','state_sequence','global_hour','stage','markov_state','p_el_kw', ...
    'h2_production_kg','pv_available_kw','pv_utilized_kw','pv_curtailed_kw','grid_import_kw', ...
    'bus_voltage_pu','branch_p_kw','branch_q_kvar','branch_true_s_mva', ...
    'site_electrical_bus','branch_from','branch_to'};
end

function names=path_names()
names={'method','path_id','state_sequence','total_cost','operating_cost','terminal_value','terminal_gap_kg', ...
    'ordinary_shortage_kg','total_production_kg','site1_production_kg','site2_production_kg', ...
    'site3_production_kg','site4_production_kg','total_htt_kg','htt_1_to_2_kg','htt_1_to_3_kg', ...
    'htt_1_to_4_kg','htt_2_to_1_kg','htt_2_to_3_kg','htt_2_to_4_kg','htt_3_to_1_kg', ...
    'htt_3_to_2_kg','htt_3_to_4_kg','htt_4_to_1_kg','htt_4_to_2_kg','htt_4_to_3_kg', ...
    'final_inventory_site1_kg','final_inventory_site2_kg','final_inventory_site3_kg', ...
    'final_inventory_site4_kg','total_terminal_inventory_kg','minimum_voltage_pu','min_voltage_bus', ...
    'min_voltage_hour','max_true_branch_mva','max_branch_utilization','max_branch_from','max_branch_to', ...
    'max_branch_hour','site1_grid_limited_count','site2_grid_limited_count','site3_grid_limited_count', ...
    'site4_grid_limited_count','site1_grid_limited_frequency','site2_grid_limited_frequency', ...
    'site3_grid_limited_frequency','site4_grid_limited_frequency','operating_hours', ...
    'site1_average_p_el_kw','site2_average_p_el_kw','site3_average_p_el_kw','site4_average_p_el_kw', ...
    'site1_min_voltage_pu','site2_min_voltage_pu','site3_min_voltage_pu','site4_min_voltage_pu', ...
    'site1_voltage_binding_hours','site2_voltage_binding_hours','site3_voltage_binding_hours', ...
    'site4_voltage_binding_hours','pv_available_kwh','pv_utilized_kwh','pv_curtailed_kwh', ...
    'pv_utilization_ratio','grid_import_kwh','terminal_state_k','terminal_stage','final_a','final_loc','final_lf'};
end

function names=stage_names()
names={'method','path_id','stage','markov_state','a','loc','lf','status','site', ...
    'beginning_inventory_kg','production_kg','ending_inventory_kg','ordinary_demand_kg', ...
    'ordinary_demand_served_kg','shortage_kg','htt_in_kg','htt_out_kg','net_htt_kg', ...
    'average_p_el_kw','site_min_voltage_pu','site_voltage_binding_hours','pv_available_kwh', ...
    'pv_utilized_kwh','pv_curtailed_kwh','grid_import_kwh','max_branch_utilization'};
end

function assert_identity(c,method,trainingCommit,nPaths)
m=c.checkpoint_metadata;
if string(m.method)~=method||string(m.frozen_commit)~=trainingCommit|| ...
        string(c.policy.state_order)~="I1,I2,I3,I4"||c.params.Ni~=4|| ...
        c.params.T~=8||c.params.hourly_grid.n_operating_stages~=6||nPaths~=10000|| ...
        any(~cellfun(@isempty,c.modelLib.models(7:8,:)),'all')
    error('Stage84B:CheckpointIdentity','Frozen checkpoint identity mismatch for %s.',method);
end
end

function n=cut_count(lib,p)
n=0;base=5+8*8*p.hourly_grid.n_branch;
for t=1:6,for k=1:p.K,m=lib.models{t,k};if ~isempty(m),n=n+max(0,size(m.A,1)-base);end,end,end
end

function manifest=empty_manifest()
manifest=table(strings(0,1),strings(0,1),zeros(0,1),zeros(0,1),zeros(0,1), ...
    zeros(0,1),strings(0,1),strings(0,1),true(0,1), ...
    'VariableNames',{'relative_path','method','first_path_id','last_path_id','record_count', ...
    'bytes','sha256','schema','completed_closed'});
end

function manifest=add_manifest(manifest,path,method,firstId,lastId,records,schema,runDir)
info=dir(path);rel=string(strrep(path,[runDir filesep],''));
row=table(rel,method,firstId,lastId,records,info.bytes,sha256_file(path),string(schema),true, ...
    'VariableNames',manifest.Properties.VariableNames);manifest=[manifest;row];
end

function trace=empty_trace()
trace=table(strings(0,1),zeros(0,1),zeros(0,1),zeros(0,1),zeros(0,1),zeros(0,1), ...
    'VariableNames',{'method','completed_paths','pure_evaluation_time_s','last_path_time_s', ...
    'closed_path_stage_batches','closed_hourly_batches'});
end

function merge_csv_batches(dirPath,pattern,finalPath)
files=dir(fullfile(dirPath,pattern));[~,order]=sort({files.name});files=files(order);
if isempty(files),error('Stage84B:NoBatches','No batches found for %s.',finalPath);end
temp=[finalPath '.tmp.csv'];
for i=1:numel(files)
    t=readtable(fullfile(files(i).folder,files(i).name));
    if i==1,writetable(t,temp);else,writetable(t,temp,'WriteMode','append','WriteVariableNames',false);end
end
movefile(temp,finalPath,'f');
end

function write_table_safe(t,path)
[folder,name,ext]=fileparts(path);temp=fullfile(folder,[name '.tmp' ext]);
writetable(t,temp);movefile(temp,path,'f');
end

function write_status(runDir,status,phase,method,pathId,pure,closed,pid,lineage)
txt=sprintf(['STATUS=%s\nPHASE=%s\nMETHOD=%s\nCURRENT_PATH_ID=%d\nCLOSED_COMPLETED_PATHS=%d\n' ...
    'PURE_EVALUATION_TIME_S=%.12g\nMATLAB_PID=%d\nTRAINING_COMMIT=%s\nOOS_FIX_COMMIT=%s\n' ...
    'OOS_RUN_COMMIT=%s\nLAST_UPDATE_TIME=%s\n'],status,phase,method,pathId,closed,pure,pid, ...
    lineage.training_commit,lineage.oos_fix_commit,lineage.oos_run_commit, ...
    char(datetime('now','Format','yyyy-MM-dd HH:mm:ss')));
write_text_safe(fullfile(runDir,'RUNNING_STATUS.txt'),txt);
end

function phase=phase_name(method)
if method=="saa",phase="SAA_FULL_OOS";else,phase="DRO_FULL_OOS";end
end

function write_text_safe(path,txt)
temp=[path '.tmp'];fid=fopen(temp,'w');if fid<0,error('Stage84B:Write','Cannot write %s.',temp);end
c=onCleanup(@()fclose(fid));fprintf(fid,'%s',char(txt));clear c;movefile(temp,path,'f');
end

function hex=sha256_file(path)
md=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(path,'r');
if fid<0,error('Stage84B:Hash','Cannot hash %s.',path);end
c=onCleanup(@()fclose(fid));
while true,data=fread(fid,1024*1024,'*uint8');if isempty(data),break;end;md.update(data);end
hex=lower(string(reshape(dec2hex(typecast(md.digest(),'uint8'),2).',1,[])));
end
