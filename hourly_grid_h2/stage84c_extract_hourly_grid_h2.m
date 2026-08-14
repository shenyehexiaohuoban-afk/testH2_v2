function stage84c_extract_hourly_grid_h2(runDir,outDir)
%STAGE84C_EXTRACT_HOURLY_GRID_H2 Aggregate closed Stage-84B hourly batches.

if nargin<1 || isempty(runDir)
    rootDir=fileparts(fileparts(mfilename('fullpath')));
    runDir=fullfile(rootDir,'results','task-002-stage2b-b3-smoke', ...
        '84B-full-common-oos-paired-analysis','run-001');
end
if nargin<2 || isempty(outDir)
    outDir=fullfile(runDir,'03-analysis');
end
if ~isfolder(runDir),error('Stage84C:MissingRun','Stage-84B run directory is missing.');end
if ~isfolder(outDir),mkdir(outDir);end

methods=["saa","chi2_eta003"];
methodDirs={fullfile(runDir,'01-saa-oos'),fullfile(runDir,'02-dro-oos')};
audit=cell(0,8);
for im=1:2
    method=methods{im};batchDir=fullfile(methodDirs{im},'hourly-batches');
    files=dir(fullfile(batchDir,'oos_hourly_grid_response_batch_*.mat'));
    [~,ord]=sort({files.name});files=files(ord);
    if numel(files)~=400,error('Stage84C:BatchCount','%s has %d hourly batches, expected 400.',method,numel(files));end
    if ~isempty(dir(fullfile(batchDir,'*.tmp*'))),error('Stage84C:OpenBatch','Temporary hourly files remain.');end

    nSlots=10000*48;
    pEl=nan(nSlots,4);pvAvail=nan(nSlots,1);pvUsed=nan(nSlots,1);pvCurt=nan(nSlots,1);
    gridImport=nan(nSlots,1);vMin=nan(nSlots,1);vMinBus=nan(nSlots,1);
    branchS=nan(nSlots,1);branchIdx=nan(nSlots,1);branchUtil=nan(nSlots,1);
    site3Limited=false(nSlots,1);vBus=nan(nSlots,33);sBranch=nan(nSlots,32);
    recordCount=0;hourSamples=0;expectedFields=hour_fields();branchFrom=nan(32,1);branchTo=nan(32,1);
    for ib=1:numel(files)
        path=fullfile(files(ib).folder,files(ib).name);
        x=load(path,'hourly_response','metadata');
        if string(x.metadata.schema_version)~="stage84b-hourly-v1" || ...
                string(x.metadata.method)~=method
            error('Stage84C:HourlyMetadata','Hourly batch identity mismatch: %s.',path);
        end
        if ib==1
            branchFrom=x.metadata.branch_from(:);branchTo=x.metadata.branch_to(:);
        elseif ~isequal(branchFrom,x.metadata.branch_from(:)) || ~isequal(branchTo,x.metadata.branch_to(:))
            error('Stage84C:BranchIdentity','Branch metadata changed between hourly batches.');
        end
        rows=x.hourly_response;recordCount=recordCount+numel(rows);
        for ir=1:numel(rows)
            r=rows(ir);if ~isequal(fieldnames(r),expectedFields(:))
                error('Stage84C:HourlySchema','Hourly field order mismatch: %s record %d.',path,ir);end
            H=numel(r.global_hour);if H==0,continue;end
            ids=(r.path_id-1)*48+r.global_hour(:);hourSamples=hourSamples+H;
            pEl(ids,:)=r.p_el_kw.';
            pvAvail(ids)=sum(r.pv_available_kw,1).';pvUsed(ids)=sum(r.pv_utilized_kw,1).';
            pvCurt(ids)=sum(r.pv_curtailed_kw,1).';gridImport(ids)=r.grid_import_kw(:);
            [vv,bb]=min(r.bus_voltage_pu,[],1);vMin(ids)=vv(:);vMinBus(ids)=bb(:);
            [ss,ee]=max(r.branch_true_s_mva,[],1);branchS(ids)=ss(:);branchIdx(ids)=ee(:);
            branchUtil(ids)=branchS(ids)/6;
            vBus(ids,:)=r.bus_voltage_pu.';sBranch(ids,:)=r.branch_true_s_mva.';
            bus18=r.bus_voltage_pu(18,:).';
            site3Limited(ids)=r.p_el_kw(3,:).' < 120*ones(H,1)-1e-6 & ...
                (bus18<=0.9000001 | max(r.branch_true_s_mva,[],1).' / 6>=0.999);
        end
        clear x rows
    end
    valid=~isnan(vMin);validCount=sum(valid);
    write_hour_summary(outDir,method,pEl,pvAvail,pvUsed,pvCurt,gridImport,vMin,vMinBus, ...
        branchS,branchIdx,branchUtil,site3Limited,valid);
    write_bus_summary(outDir,method,vBus,vMinBus,valid);
    write_branch_summary(outDir,method,sBranch,branchFrom,branchTo,valid);
    audit(end+1,:)={method,numel(files),recordCount,hourSamples,validCount, ...
        sum(site3Limited(valid)),sum(valid),"stage84b-hourly-v1"}; %#ok<AGROW>
    clear pEl pvAvail pvUsed pvCurt gridImport vMin vMinBus branchS branchIdx branchUtil site3Limited vBus sBranch
end
auditTable=cell2table(audit,'VariableNames',{'method','hourly_batch_count','hourly_struct_records', ...
    'operating_hour_records','valid_path_hour_slots','site3_limited_hour_records', ...
    'valid_slots','schema_version'});
write_safe(auditTable,fullfile(outDir,'hourly_extract_audit.csv'));
write_terminal_target_lookup(runDir,outDir);
end

function write_hour_summary(outDir,method,pEl,pvAvail,pvUsed,pvCurt,gridImport,vMin,vMinBus,branchS,branchIdx,branchUtil,site3Limited,valid)
rows=cell(0,22);
for h=1:48
    ids=h:48:numel(valid);ok=valid(ids);ids=ids(ok);if isempty(ids),continue;end
    rows(end+1,:)={method,h,numel(ids),mean(sum(pEl(ids,:),2)),mean(pEl(ids,1)),mean(pEl(ids,2)), ...
        mean(pEl(ids,3)),mean(pEl(ids,4)),mean(pvAvail(ids)),mean(pvUsed(ids)),mean(pvCurt(ids)), ...
        mean(gridImport(ids)),mean(vMin(ids)),min(vMin(ids)),mean(branchS(ids)),max(branchS(ids)), ...
        mean(branchUtil(ids)),max(branchUtil(ids)),mode(vMinBus(ids)),mode(branchIdx(ids)), ...
        sum(site3Limited(ids))/numel(ids),"p.u./kW/kWh/MVA"}; %#ok<AGROW>
end
names={'method','global_hour','path_hour_count','total_p_el_mean_kw','site1_p_el_mean_kw','site2_p_el_mean_kw', ...
    'site3_p_el_mean_kw','site4_p_el_mean_kw','pv_available_mean_kwh','pv_used_mean_kwh','pv_curtailed_mean_kwh', ...
    'grid_import_mean_kwh','minimum_voltage_mean_pu','minimum_voltage_min_pu','max_branch_mva_mean', ...
    'max_branch_mva_max','max_branch_utilization_mean','max_branch_utilization_max','mode_min_voltage_bus', ...
    'mode_max_loading_branch_index','site3_hourly_grid_limited_frequency','unit_note'};
write_safe(cell2table(rows,'VariableNames',names),fullfile(outDir,sprintf('%s_hour48_grid_summary.csv',method)));
rows=cell(0,5);
for h=1:48
    ids=h:48:numel(valid);ok=valid(ids);ids=ids(ok);if isempty(ids),continue;end
    rows(end+1,:)={method,h,numel(ids),sum(site3Limited(ids)),sum(site3Limited(ids))/numel(ids)}; %#ok<AGROW>
end
write_safe(cell2table(rows,'VariableNames',{'method','global_hour','denominator_hour_records','limited_hour_records','hourly_grid_limited_frequency'}), ...
    fullfile(outDir,sprintf('%s_site3_hourly_grid_limited.csv',method)));
end

function write_bus_summary(outDir,method,vBus,vMinBus,valid)
rows=cell(0,12);
for b=1:33
    x=vBus(valid,b);x=x(isfinite(x));if isempty(x),continue;end
    rows(end+1,:)={method,b,numel(x),mean(x),prctile(x,1),prctile(x,5), ...
        median(x),min(x),sum(x<=0.9000001)/numel(x),sum(x<=0.9000001), ...
        sum(vMinBus(valid)==b)/sum(valid),"p.u."}; %#ok<AGROW>
end
names={'method','bus','observed_hour_records','mean_voltage_pu','q01_voltage_pu','q05_voltage_pu', ...
    'q50_voltage_pu','minimum_voltage_pu','lower_bound_hit_frequency','lower_bound_hit_count', ...
    'minimum_bus_frequency','unit_note'};
write_safe(cell2table(rows,'VariableNames',names),fullfile(outDir,sprintf('%s_bus_voltage_summary.csv',method)));
rows=cell(0,12);
for b=1:33
    for h=1:48
        ids=h:48:size(vBus,1);x=vBus(ids,b);x=x(isfinite(x));if isempty(x),continue;end
        rows(end+1,:)={method,b,h,numel(x),mean(x),prctile(x,1),prctile(x,5),median(x),min(x),sum(x<=0.9000001)/numel(x),sum(x<=0.9000001),"p.u."}; %#ok<AGROW>
    end
end
write_safe(cell2table(rows,'VariableNames',{'method','bus','global_hour','observed_records','mean_voltage_pu', ...
    'q01_voltage_pu','q05_voltage_pu','q50_voltage_pu','minimum_voltage_pu','lower_bound_hit_frequency', ...
    'lower_bound_hit_count','unit_note'}),fullfile(outDir,sprintf('%s_bus_hour_voltage_summary.csv',method)));
end

function write_branch_summary(outDir,method,sBranch,branchFrom,branchTo,valid)
rows=cell(0,16);
for b=1:32
    x=sBranch(valid,b);x=x(isfinite(x));if isempty(x),continue;end
    rows(end+1,:)={method,b,branchFrom(b),branchTo(b),numel(x),mean(x),prctile(x,95),prctile(x,99),prctile(x,99.5), ...
        max(x),mean(x/6),prctile(x/6,95),prctile(x/6,99),prctile(x/6,99.5),max(x/6),"MVA/MVA"}; %#ok<AGROW>
end
write_safe(cell2table(rows,'VariableNames',{'method','branch_index','from_bus','to_bus','observed_hour_records','true_mva_mean', ...
    'true_mva_q95','true_mva_q99','true_mva_q995','true_mva_max','utilization_mean','utilization_q95', ...
    'utilization_q99','utilization_q995','utilization_max','unit_note'}),fullfile(outDir,sprintf('%s_branch_loading_summary.csv',method)));
end

function write_safe(t,path)
[folder,name,ext]=fileparts(path);temp=fullfile(folder,[name '.tmp' ext]);writetable(t,temp);movefile(temp,path,'f');
end

function write_terminal_target_lookup(runDir,outDir)
rootDir=fileparts(fileparts(fileparts(fileparts(runDir))));
formalDir=fullfile(rootDir,'results','task-002-stage2b-b3-smoke','84-hourly-grid-formal-training-oos','run-001');
methods=["saa","chi2_eta003"];subdirs={'saa','chi2_eta003'};rows=cell(0,4);
for im=1:2
    cp=fullfile(formalDir,'checkpoints',subdirs{im},'checkpoint_final.mat');
    x=load(cp,'params');target=x.params.TerminalLOH;
    for k=1:size(target,2)
        for site=1:size(target,1),rows(end+1,:)={methods(im),k,site,target(site,k)};end %#ok<AGROW>
    end
    clear x target
end
write_safe(cell2table(rows,'VariableNames',{'method','terminal_state_k','site','target_loh_kg'}), ...
    fullfile(outDir,'terminal_target_lookup.csv'));
end

function f=hour_fields()
f={'method','path_id','state_sequence','global_hour','stage','markov_state','p_el_kw', ...
    'h2_production_kg','pv_available_kw','pv_utilized_kw','pv_curtailed_kw','grid_import_kw', ...
    'bus_voltage_pu','branch_p_kw','branch_q_kvar','branch_true_s_mva','site_electrical_bus','branch_from','branch_to'};
end
