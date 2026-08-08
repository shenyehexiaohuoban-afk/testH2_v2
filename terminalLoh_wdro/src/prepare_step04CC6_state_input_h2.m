function prepare_step04CC6_state_input_h2(workDir,stateId)
%PREPARE_STEP04CC6_STATE_INPUT_H2 Recover one C6 state in an isolated process.

started=tic;workDir=string(workDir);stateId=double(stateId);
thisDir=fileparts(mfilename('fullpath'));rootDir=fileparts(fileparts(thisDir));
addpath(rootDir);addpath(thisDir);
assert_git_gate("task/002-stage2b-b3-smoke", ...
    "6840dccd995cf87d9e348ce8090003c6a74b773d");
if ~isscalar(stateId)||stateId<1||stateId>35||stateId~=round(stateId)
    error('stateId must be an integer in 1:35.');
end

required=["frozen_input_manifest.csv";"frozen_parameter_table.csv"; ...
    "state_mapping_audit.csv";"solve_case_grid.csv"];
for ii=1:numel(required)
    if ~isfile(fullfile(workDir,required(ii))),error('Missing C6 initialization file: %s',required(ii));end
end
preparedDir=fullfile(workDir,'prepared_inputs');
rowDir=fullfile(workDir,'prepared_state_rows');
if ~isfolder(preparedDir)||~isfolder(rowDir),error('C6 preparation directories are missing.');end
payload=fullfile(preparedDir,sprintf('state-%03d-period-input.mat',stateId));
rowFile=fullfile(rowDir,sprintf('state-%03d.csv',stateId));
if isfile(payload)||isfile(rowFile),error('Refusing to overwrite prepared state %d.',stateId);end

inputManifest=readtable(fullfile(workDir,'frozen_input_manifest.csv'),'TextType','string');
if height(inputManifest)~=19||~all(inputManifest.hash_pass)
    error('Frozen input manifest is incomplete or failed.');
end
for ii=1:height(inputManifest)
    if sha256_file(inputManifest.path(ii))~=lower(inputManifest.expected_sha256(ii))
        error('Frozen input changed after initialization: %s',inputManifest.input_label(ii));
    end
end

parameters=readtable(fullfile(workDir,'frozen_parameter_table.csv'),'TextType','string');
cH2=get_parameter(parameters,"c_H2");M=get_parameter(parameters,"M_H2");
electricityPerKg=get_parameter(parameters,"electricity_per_kg_H2");
if abs(cH2-32.5213675213675)>1e-10||abs(M-1283.205)>1e-9|| ...
        abs(electricityPerKg-18.3315)>1e-12
    error('Frozen economic parameter gate failed.');
end

mapping=readtable(fullfile(workDir,'state_mapping_audit.csv'),'TextType','string');
row=mapping(double(mapping.state_id)==stateId,:);
if height(row)~=1||double(row.mapping_order)~=stateId||double(row.scenario_count)~=15000|| ...
        abs(double(row.nominal_weight)-1/15000)>1e-15||logical(row.path_probability_used)
    error('State mapping gate failed for state %d.',stateId);
end

nearFile=fullfile(rootDir,'data','yuanqi','near_stage_msp_input.mat');
raw=load(nearFile,'NearStageInput');Cap=double(raw.NearStageInput.HydrogenDevice.tank_cap_kg(:));
if max(abs(Cap(:).'-[300,200,100,150]))>1e-12,error('Capacity gate failed.');end

fprintf('STEP04CC6_PREPARE_STATE_START|state=%d\n',stateId);
[entry,context]=recover_step03Y_prefix_entries_c6_nojvm_h2(rootDir,stateId,15000,false,"nominal");
if ~entry.audit.all_final_DAC_exact||~entry.audit.all_stream_identity_replay_match|| ...
        entry.audit.max_DAC_error~=0||height(entry.identity)~=15000|| ...
        any(double(entry.identity.initial_state_id)~=stateId)|| ...
        max(abs(double(entry.identity.frozen_nominal_weight)-1/15000))>1e-15
    error('Formal period recovery gate failed for state %d.',stateId);
end
aggregation=aggregate_exact_period_scenarios_c6_nojvm_h2(entry.Dperiod,entry.Aperiod,entry.Cperiod);
if aggregation.original_R~=15000||~aggregation.exact_verification_pass|| ...
        abs(sum(aggregation.nominal_probability)-1)>1e-12|| ...
        max(abs(aggregation.nominal_probability-aggregation.multiplicity/15000))>1e-15|| ...
        max(abs(double(context.Cap(:))-Cap))>1e-12
    error('Exact aggregation gate failed for state %d.',stateId);
end

DperiodGroup=aggregation.Dperiod;AperiodGroup=aggregation.Aperiod;
CperiodGroup=aggregation.Cperiod;qGroup=aggregation.nominal_probability;
groupId=aggregation.group_id;multiplicity=aggregation.multiplicity;
groupCount=aggregation.group_count;originalR=aggregation.original_R;
a0=double(row.intensity);loc0=double(row.loc);lfw0=double(row.lfw);
stateLabel=string(row.state_label);
save(payload,'DperiodGroup','AperiodGroup','CperiodGroup','qGroup', ...
    'groupId','multiplicity','groupCount','originalR','Cap','stateId', ...
    'a0','loc0','lfw0','stateLabel','cH2','M','electricityPerKg','-v7');
payloadHash=sha256_file(payload);info=dir(payload);
state_id=stateId;state_label=stateLabel;intensity=a0;loc=loc0;lfw=lfw0;
local_payload_path=string(payload);payload_bytes=info.bytes;payload_sha256=payloadHash;
original_R=15000;exact_group_count=groupCount;
duplicate_record_count=aggregation.duplicate_record_count;
maximum_multiplicity=aggregation.maximum_multiplicity;prepare_runtime_sec=toc(started);
result=table(state_id,state_label,intensity,loc,lfw,local_payload_path, ...
    payload_bytes,payload_sha256,original_R,exact_group_count, ...
    duplicate_record_count,maximum_multiplicity,prepare_runtime_sec);
writetable(result,rowFile);
fprintf('STEP04CC6_PREPARE_STATE_COMPLETE|state=%d|groups=%d|runtime=%.3f\n', ...
    stateId,groupCount,toc(started));
end

function value=get_parameter(parameters,name)
row=parameters(parameters.parameter_name==name,:);
if height(row)~=1,error('Missing or duplicate frozen parameter: %s',name);end
value=double(row.value);
end
function assert_git_gate(expectedBranch,expectedHead)
[s1,b]=system('git branch --show-current');[s2,h]=system('git rev-parse HEAD');
[s3,u]=system('git rev-parse @{upstream}');
if s1~=0||s2~=0||s3~=0||strtrim(string(b))~=expectedBranch|| ...
        strtrim(string(h))~=expectedHead||strtrim(string(u))~=expectedHead
    error('Step-04C-C6 state preparation Git gate failed.');
end
end
function hash=sha256_file(fileName)
stream=System.IO.File.OpenRead(char(fileName));cleanup=onCleanup(@()stream.Dispose()); %#ok<NASGU>
md=System.Security.Cryptography.SHA256Managed;digest=uint8(md.ComputeHash(stream));md.Dispose();
hash=lower(string(reshape(dec2hex(digest,2).',1,[])));
end
