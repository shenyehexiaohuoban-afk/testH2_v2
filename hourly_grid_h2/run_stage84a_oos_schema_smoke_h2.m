function run_stage84a_oos_schema_smoke_h2()
%RUN_STAGE84A_OOS_SCHEMA_SMOKE_H2 Validate frozen-policy OOS serialization on three paths.

rootDir=fileparts(fileparts(mfilename('fullpath')));
addpath(rootDir);addpath(fullfile(rootDir,'fa_h2'));
addpath(fullfile(rootDir,'fa_h2','fuzhu'));addpath(fullfile(rootDir,'utils'));
addpath(fullfile(rootDir,'hourly_grid_h2'));

trainingCommit="cd7084300b0a50ade053e6b45ea7a1701d52c307";
formalDir=fullfile(rootDir,'results','task-002-stage2b-b3-smoke', ...
    '84-hourly-grid-formal-training-oos','run-001');
runDir=fullfile(rootDir,'results','task-002-stage2b-b3-smoke', ...
    '84A-oos-hourly-schema-fix','run-002');
auditFile=fullfile(rootDir,'results','task-002-stage2b-b3-smoke', ...
    '84A-oos-hourly-schema-fix','run-001','schema_audit_before_fix.txt');
preflightFile=fullfile(runDir,'launch_preflight.txt');
if ~isfile(auditFile)||~isfile(preflightFile)
    error('Stage84A:MissingAudit','Required schema audit or run-002 preflight is missing.');
end

saaDir=fullfile(runDir,'saa-oos');droDir=fullfile(runDir,'dro-oos');
if exist(saaDir,'dir')||exist(droDir,'dir')||isfile(fullfile(runDir,'FAILURE.txt'))|| ...
        isfile(fullfile(runDir,'final_judgment.txt'))
    error('Stage84A:OutputExists','Refusing to overwrite an existing smoke attempt.');
end
mkdir(saaDir);mkdir(droDir);mkdir(fullfile(runDir,'logs'));
diaryFile=fullfile(runDir,'logs','matlab_diary.txt');diary(diaryFile);

saaCp=fullfile(formalDir,'checkpoints','saa','checkpoint_final.mat');
droCp=fullfile(formalDir,'checkpoints','chi2_eta003','checkpoint_final.mat');
bankFile=fullfile(formalDir,'03-common-oos-paths','oos_path_bank.mat');
manifestFile=fullfile(formalDir,'03-common-oos-paths','oos_path_manifest.csv');
pid=feature('getpid');

try
    required={saaCp,droCp,bankFile,manifestFile};
    if ~all(cellfun(@isfile,required))
        error('Stage84A:MissingFrozenInput','A frozen checkpoint or path-bank input is missing.');
    end
    [gitStatus,head]=system('git rev-parse HEAD');head=strtrim(string(head));
    if gitStatus~=0||head~=trainingCommit
        error('Stage84A:HeadMismatch','HEAD %s does not match training commit %s.',head,trainingCommit);
    end

    saaBefore=dir(saaCp);droBefore=dir(droCp);bankBefore=dir(bankFile);
    saaId=load(saaCp,'checkpoint_metadata','policy');
    droId=load(droCp,'checkpoint_metadata','policy');
    assert_checkpoint_identity(saaId,"saa",trainingCommit,645314);
    assert_checkpoint_identity(droId,"chi2_eta003",trainingCommit,643212);

    bankData=load(bankFile,'pathBank');pathBank=bankData.pathBank;
    if ~isequal(size(pathBank),[10000,8])
        error('Stage84A:PathBankShape','Frozen path bank must be 10000x8.');
    end
    manifest=readtable(manifestFile);
    manifestBank=manifest{:,2:9};
    if height(manifest)~=10000||~isequal(manifest.path_id,(1:10000).')|| ...
            ~isequal(manifestBank,pathBank)
        error('Stage84A:PathManifestMismatch','Frozen path manifest and MAT bank differ.');
    end

    smokeIds=(1:3).';smokeBank=pathBank(smokeIds,:);
    write_status(runDir,'RUNNING',trainingCommit,smokeIds);
    saaOut=stage84_timed_oos_h2(saaCp,smokeBank,Inf,saaDir,"saa",runDir,pid,trainingCommit);
    droOut=stage84_timed_oos_h2(droCp,smokeBank,Inf,droDir,"chi2_eta003",runDir,pid,trainingCommit);

    expectedFields=hour_fields();
    saa=verify_method(saaDir,"saa",smokeIds,smokeBank,expectedFields,saaOut, ...
        saaId.checkpoint_metadata.cumulative_cuts);
    dro=verify_method(droDir,"chi2_eta003",smokeIds,smokeBank,expectedFields,droOut, ...
        droId.checkpoint_metadata.cumulative_cuts);
    flushResetPass=verify_flush_reset(runDir,saaDir,droDir,expectedFields);
    commonPass=compare_method_identity(saaDir,droDir,smokeIds,smokeBank);

    saaAfter=dir(saaCp);droAfter=dir(droCp);bankAfter=dir(bankFile);
    saa.checkpoint_unchanged=same_file(saaBefore,saaAfter);
    dro.checkpoint_unchanged=same_file(droBefore,droAfter);
    bankUnchanged=same_file(bankBefore,bankAfter);
    saa.cut_delta=0;dro.cut_delta=0;
    saa.pass=saa.pass&&saa.checkpoint_unchanged;
    dro.pass=dro.pass&&dro.checkpoint_unchanged;

    summary=struct2table([saa;dro]);
    writetable(summary,fullfile(runDir,'smoke_summary.csv'));
    write_schema_inventory(runDir,saaDir,droDir,expectedFields);
    write_identity(runDir,trainingCommit,saaCp,droCp,bankFile,smokeIds,smokeBank, ...
        saaBefore,droBefore,bankBefore,bankUnchanged,commonPass);
    pass=all(summary.pass)&&commonPass&&bankUnchanged&&flushResetPass;
    reloaded=readtable(fullfile(runDir,'smoke_summary.csv'));
    pass=pass&&height(reloaded)==2&&all(reloaded.pass);
    judgment=ternary(pass,"PASS_READY_TO_FREEZE_OOS_FIX","FAIL_OOS_SCHEMA_FIX");
    write_text_safe(fullfile(runDir,'final_judgment.txt'),compose_judgment( ...
        judgment,trainingCommit,smokeIds,commonPass,bankUnchanged,flushResetPass));
    write_status(runDir,char(judgment),trainingCommit,smokeIds);
    diary off;
    if ~pass,error('Stage84A:SmokeGate','Stage-84A smoke gate failed.');end
catch ME
    write_failure(runDir,ME);write_status(runDir,'FAIL_OOS_SCHEMA_FIX',trainingCommit,(1:3).');
    diary off;rethrow(ME);
end

function pass=verify_flush_reset(runDir,saaDir,droDir,fields)
probeDir=fullfile(runDir,'flush-reset-probe');mkdir(probeDir);
dirs={saaDir,droDir};methods=["saa","chi2_eta003"];
rows=cell(2,7);pass=true;
for j=1:2
    files=dir(fullfile(dirs{j},'oos_hourly_grid_response_batch_*.mat'));
    source=load(fullfile(files(1).folder,files(1).name),'hourly_response');
    records=source.hourly_response;
    batch=records([]);typedEmptyBefore=isempty(batch)&&isequal(fieldnames(batch),fields(:));
    batch(end+1)=records(1);batch(end+1)=records(2);
    firstFile=fullfile(probeDir,char(methods(j)+"_probe_batch_0001.mat"));
    save_probe(firstFile,batch);
    batch=batch([]);typedEmptyAfter=isempty(batch)&&isequal(fieldnames(batch),fields(:));
    batch(end+1)=records(3);
    secondFile=fullfile(probeDir,char(methods(j)+"_probe_batch_0002.mat"));
    save_probe(secondFile,batch);
    a=load(firstFile,'hourly_response');b=load(secondFile,'hourly_response');
    reloadPass=numel(a.hourly_response)==2&&numel(b.hourly_response)==1&& ...
        isequal([a.hourly_response.path_id],[1,2])&&b.hourly_response.path_id==3;
    fieldPass=all(arrayfun(@(r)isequal(fieldnames(r),fields(:)), ...
        [a.hourly_response,b.hourly_response]));
    methodPass=all([a.hourly_response.method]==methods(j))&&b.hourly_response.method==methods(j);
    methodResult=typedEmptyBefore&&typedEmptyAfter&&reloadPass&&fieldPass&&methodPass;
    rows(j,:)={methods(j),typedEmptyBefore,typedEmptyAfter,2,1,reloadPass&&fieldPass,methodResult};
    pass=pass&&methodResult;
end
writetable(cell2table(rows,'VariableNames',{'method','typed_empty_before_append', ...
    'typed_empty_after_reset','records_before_reset','records_after_reset', ...
    'reload_and_schema_pass','pass'}),fullfile(runDir,'flush_reset_probe.csv'));
end

function save_probe(path,hourly_response)
temp=[path '.tmp.mat'];save(temp,'hourly_response','-v7.3');
vars=whos('-file',temp);
if ~any(strcmp({vars.name},'hourly_response'))
    error('Stage84A:ProbeWrite','Incomplete flush/reset probe %s.',temp);
end
movefile(temp,path,'f');
end
end

function assert_checkpoint_identity(c,method,commit,cuts)
m=c.checkpoint_metadata;
if string(m.method)~=method||string(m.frozen_commit)~=commit|| ...
        m.cumulative_cuts~=cuts||string(c.policy.state_order)~="I1,I2,I3,I4"
    error('Stage84A:CheckpointIdentity','Checkpoint identity mismatch for %s.',method);
end
end

function v=verify_method(outDir,method,ids,bank,fields,out,cuts)
pathFile=fullfile(outDir,'oos_path_summary.csv');
stageFile=fullfile(outDir,'oos_stage_site_response.csv');
metaFile=fullfile(outDir,'oos_metadata.csv');
batches=dir(fullfile(outDir,'oos_hourly_grid_response_batch_*.mat'));
if ~isfile(pathFile)||~isfile(stageFile)||~isfile(metaFile)||numel(batches)~=1
    error('Stage84A:MissingOutput','Missing serialized output for %s.',method);
end
p=readtable(pathFile);s=readtable(stageFile);m=readtable(metaFile);
b=load(fullfile(batches(1).folder,batches(1).name),'hourly_response','metadata');
h=b.hourly_response;

requiredPath={'path_id','state_sequence','total_cost','terminal_value','terminal_gap_kg', ...
    'ordinary_shortage_kg','total_production_kg','total_htt_kg', ...
    'final_inventory_site1_kg','final_inventory_site2_kg','final_inventory_site3_kg', ...
    'final_inventory_site4_kg','minimum_voltage_pu','max_true_branch_mva', ...
    'max_branch_utilization','pv_available_kwh','pv_utilized_kwh','pv_curtailed_kwh','grid_import_kwh'};
requiredStage={'path_id','stage','markov_state','site','beginning_inventory_kg', ...
    'production_kg','ordinary_demand_kg','ordinary_demand_served_kg','shortage_kg', ...
    'htt_in_kg','htt_out_kg','ending_inventory_kg'};
schemaPass=numel(h)==numel(ids)&&all(ismember(requiredPath,p.Properties.VariableNames))&& ...
    all(ismember(requiredStage,s.Properties.VariableNames));
identityPass=height(p)==numel(ids)&&isequal(p.path_id,ids);
stagePass=height(s)==numel(ids)*8*4;
timePass=true;terminalHourPass=true;hourSamples=0;
for q=1:numel(h)
    r=h(q);H=numel(r.global_hour);hourSamples=hourSamples+H;
    schemaPass=schemaPass&&isequal(fieldnames(r),fields(:))&&isa(r.method,'string')&& ...
        isscalar(r.method)&&isa(r.path_id,'double')&&isscalar(r.path_id)&& ...
        isequal(size(r.state_sequence),[1,8])&&isequal(r.state_sequence,bank(q,:))&& ...
        isequal(size(r.p_el_kw),[4,H])&&isequal(size(r.h2_production_kg),[4,H])&& ...
        isequal(size(r.pv_available_kw),[4,H])&&isequal(size(r.pv_utilized_kw),[4,H])&& ...
        isequal(size(r.pv_curtailed_kw),[4,H])&&isequal(size(r.grid_import_kw),[1,H])&& ...
        isequal(size(r.bus_voltage_pu),[33,H])&&isequal(size(r.branch_p_kw),[32,H])&& ...
        isequal(size(r.branch_q_kvar),[32,H])&&isequal(size(r.branch_true_s_mva),[32,H])&& ...
        isequal(size(r.site_electrical_bus),[1,4])&&isequal(size(r.branch_from),[1,32])&& ...
        isequal(size(r.branch_to),[1,32])&&mod(H,8)==0&&H<=48;
    identityPass=identityPass&&r.path_id==ids(q)&&r.method==method;
    terminalHourPass=terminalHourPass&&all(r.stage>=1&r.stage<=6);
    stages=unique(r.stage,'stable');
    for j=1:numel(stages)
        t=stages(j);ix=find(r.stage==t);
        timePass=timePass&&numel(ix)==8&&isequal(r.global_hour(ix),8*(t-1)+(1:8))&& ...
            all(r.markov_state(ix)==bank(q,t));
    end
end
for q=1:numel(ids)
    seq=strjoin(string(bank(q,:)),'-');
    identityPass=identityPass&&string(p.state_sequence(q))==seq;
    for t=1:8
        rows=s.path_id==ids(q)&s.stage==t;
        stagePass=stagePass&&nnz(rows)==4&&all(s.markov_state(rows)==bank(q,t));
    end
end
serializationPass=numel(h)==3&&height(p)==3&&height(s)==96&&height(m)==1;
constraintViolations=m.constraint_violations(1);
v=struct('method',method,'training_commit', ...
    "cd7084300b0a50ade053e6b45ea7a1701d52c307",'checkpoint_cuts',cuts, ...
    'smoke_path_ids',strjoin(string(ids.'),','),'completed_paths',out.completed_paths, ...
    'path_records',height(p),'stage_site_records',height(s),'hourly_struct_records',numel(h), ...
    'hourly_samples',hourSamples,'serialization_pass',serializationPass,'reload_pass',true, ...
    'schema_consistency_pass',schemaPass,'path_identity_pass',identityPass, ...
    'stage_identity_pass',stagePass,'time_index_pass',timePass, ...
    'no_stage7_8_hourly_records',terminalHourPass,'constraint_violations',constraintViolations, ...
    'checkpoint_unchanged',false,'cut_delta',NaN,'pass',serializationPass&&schemaPass&& ...
    identityPass&&stagePass&&timePass&&terminalHourPass&&constraintViolations==0&& ...
    out.completed_paths==3&&out.constraint_violations==0);
end

function pass=compare_method_identity(saaDir,droDir,ids,bank)
s=readtable(fullfile(saaDir,'oos_path_summary.csv'));
d=readtable(fullfile(droDir,'oos_path_summary.csv'));
pass=isequal(s.path_id,ids)&&isequal(d.path_id,ids)&& ...
    all(string(s.state_sequence)==string(d.state_sequence));
for q=1:numel(ids)
    pass=pass&&string(s.state_sequence(q))==strjoin(string(bank(q,:)),'-');
end
end

function write_schema_inventory(runDir,saaDir,droDir,fields)
rows=cell(0,4);
dirs={saaDir,droDir};methods={"saa","chi2_eta003"};
for j=1:2
    b=dir(fullfile(dirs{j},'oos_hourly_grid_response_batch_*.mat'));
    x=load(fullfile(b(1).folder,b(1).name),'hourly_response');r=x.hourly_response(1);
    for i=1:numel(fields)
        value=r.(fields{i});rows(end+1,:)={methods{j},i,string(fields{i}), ...
            string(class(value))+" "+string(mat2str(size(value)))}; %#ok<AGROW>
    end
end
writetable(cell2table(rows,'VariableNames',{'method','field_order','field','class_and_first_path_size'}), ...
    fullfile(runDir,'hourly_schema_inventory.csv'));
end

function write_identity(runDir,commit,saaCp,droCp,bankFile,ids,bank,saaInfo,droInfo,bankInfo,bankSame,commonPass)
names=["training_commit";"saa_checkpoint";"saa_checkpoint_bytes";"saa_checkpoint_cuts"; ...
    "dro_checkpoint";"dro_checkpoint_bytes";"dro_checkpoint_cuts";"common_path_bank"; ...
    "common_path_bank_bytes";"common_path_bank_shape";"smoke_path_ids"; ...
    "smoke_state_sequences";"common_path_bank_unchanged";"saa_dro_common_identity_pass"];
seq=join(join(string(bank),'-',2),';');
values=[commit;string(saaCp);string(saaInfo.bytes);"645314";string(droCp); ...
    string(droInfo.bytes);"643212";string(bankFile);string(bankInfo.bytes);"10000x8"; ...
    strjoin(string(ids.'),',');seq;string(bankSame);string(commonPass)];
writetable(table(names,values),fullfile(runDir,'input_and_lineage_identity.csv'));
end

function fields=hour_fields()
fields={'method','path_id','state_sequence','global_hour','stage','markov_state','p_el_kw', ...
    'h2_production_kg','pv_available_kw','pv_utilized_kw','pv_curtailed_kw','grid_import_kw', ...
    'bus_voltage_pu','branch_p_kw','branch_q_kvar','branch_true_s_mva', ...
    'site_electrical_bus','branch_from','branch_to'};
end

function txt=compose_judgment(judgment,commit,ids,commonPass,bankSame,flushResetPass)
txt=sprintf(['FINAL_JUDGMENT=%s\nTRAINING_COMMIT=%s\nSMOKE_PATH_IDS=%s\n' ...
    'SAA_DRO_COMMON_PATH_IDENTITY_PASS=%d\nCOMMON_PATH_BANK_UNCHANGED=%d\n' ...
    'FLUSH_AFTER_TYPED_EMPTY_RESET_PASS=%d\n' ...
    'FORMAL_TIMED_OOS_STARTED=false\nTRAINING_STARTED=false\n'],judgment,commit, ...
    char(strjoin(string(ids.'),',')),commonPass,bankSame,flushResetPass);
end

function pass=same_file(a,b)
pass=a.bytes==b.bytes&&a.datenum==b.datenum;
end

function write_status(runDir,status,commit,ids)
txt=sprintf('STATUS=%s\nTRAINING_COMMIT=%s\nSMOKE_PATH_IDS=%s\nUPDATED=%s\n', ...
    status,commit,char(strjoin(string(ids.'),',')),char(datetime('now','Format','yyyy-MM-dd HH:mm:ss')));
write_text_safe(fullfile(runDir,'SMOKE_STATUS.txt'),txt);
end

function write_failure(runDir,ME)
txt=string(sprintf('STATUS=FAIL\nidentifier=%s\nmessage=%s\n',ME.identifier,ME.message));
for i=1:numel(ME.stack)
    txt=txt+string(sprintf('stack_%d=%s:%d\n',i,ME.stack(i).name,ME.stack(i).line));
end
write_text_safe(fullfile(runDir,'FAILURE.txt'),txt);
end

function write_text_safe(path,txt)
temp=[path '.tmp'];fid=fopen(temp,'w');
if fid<0,error('Stage84A:Write','Cannot open %s.',temp);end
c=onCleanup(@()fclose(fid));fprintf(fid,'%s',char(txt));clear c
movefile(temp,path,'f');
end

function y=ternary(test,a,b)
if test,y=a;else,y=b;end
end
