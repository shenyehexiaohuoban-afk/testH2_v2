function prepare_step04CC5C_eta_response_inputs_h2(workDir)
%PREPARE_STEP04CC5C_ETA_RESPONSE_INPUTS_H2 Frozen-input gate for C5C.

started=tic;workDir=string(workDir);
thisDir=fileparts(mfilename('fullpath'));rootDir=fileparts(fileparts(thisDir));
addpath(rootDir);addpath(thisDir);
assert_git_gate("task/002-stage2b-b3-smoke", ...
    "309639d5d9c18a8951227fd5cfa04d5eeb20e9ef");
if ~isfolder(workDir),mkdir(workDir);end
for name=["eta_grid_spec.csv","frozen_input_manifest.csv","prepare_summary.csv"]
    if isfile(fullfile(workDir,name)),error('Refusing to overwrite %s.',name);end
end
diary(fullfile(workDir,'prepare_matlab_diary.txt'));
cleanupDiary=onCleanup(@()diary('off')); %#ok<NASGU>

c1=fullfile(rootDir,'results','task-002-stage2b-b3-smoke', ...
    '46-flat-chi2-eta-calibration','run-003');
c2=fullfile(rootDir,'results','task-002-stage2b-b3-smoke', ...
    '47-flat-chi2-independent-path-validation','run-002');
c3=fullfile(rootDir,'results','task-002-stage2b-b3-smoke', ...
    '48-markov-transition-perturbation','run-001');
c5b=fullfile(rootDir,'results','task-002-stage2b-b3-smoke', ...
    '51-unified-economic-terminal-loh','run-003');
nearFile=fullfile(rootDir,'data','yuanqi','near_stage_msp_input.mat');
c1Prepared=fullfile(c1,'prepared_inputs.mat');
c2Manifest=readtable(fullfile(c2,'independent_dataset_manifest.csv'));
c3Manifest=readtable(fullfile(c3,'dataset_manifest.csv'));
if height(c2Manifest)~=3||height(c3Manifest)~=21,error('C2/C3 manifest row gate failed.');end
c3Keep=ismember(string(c3Manifest.distribution_label),["combined-medium","combined-strong"]);
if sum(c3Keep)~=6,error('C3 combined-medium/strong selection gate failed.');end

paths=[string(nearFile);string(c1Prepared); ...
    string(fullfile(c1,'eta_solver_certificate.csv')); ...
    string(fullfile(c5b,'terminal_loh_decision_comparison.csv')); ...
    string(fullfile(c5b,'solver_certificate.csv')); ...
    string(c2Manifest.local_mat_path);string(c3Manifest.local_mat_path(c3Keep))];
labels=["near_stage_msp_input";"C1_prepared_inputs";"C1_certificate"; ...
    "C5B_decisions";"C5B_certificate"; ...
    "C2_dataset_001";"C2_dataset_002";"C2_dataset_003"; ...
    "C3_combined_dataset_001";"C3_combined_dataset_002"; ...
    "C3_combined_dataset_003";"C3_combined_dataset_004"; ...
    "C3_combined_dataset_005";"C3_combined_dataset_006"];
expected=["536b25868e6d7cc812a331c0d3e0ffbd5f6958e6883bd39bcae3901c372abf24"; ...
    "5914afb37254ae908c5a8b10f24bc0ae01520e56b35b928a1afc13cf4602f19b"; ...
    "63e8b8316aafd73284a087a6af10a5dcf257a87ddf739bf70b4d5171574a3769"; ...
    "";"";string(c2Manifest.local_mat_sha256); ...
    string(c3Manifest.local_mat_sha256(c3Keep))];
actual=strings(size(paths));bytes=zeros(size(paths));
for ii=1:numel(paths)
    if ~isfile(paths(ii)),error('Missing frozen input: %s',paths(ii));end
    actual(ii)=sha256_file(paths(ii));info=dir(paths(ii));bytes(ii)=info.bytes;
    if strlength(expected(ii))>0&&actual(ii)~=expected(ii)
        error('Frozen input hash mismatch: %s',labels(ii));
    end
end
hashPass=(strlength(expected)==0)|(actual==expected);
manifest=table(labels,paths,bytes,actual,expected,hashPass, ...
    'VariableNames',{'input_label','path','bytes','sha256','expected_sha256','hash_pass'});
writetable(manifest,fullfile(workDir,'frozen_input_manifest.csv'));

raw=load(nearFile,'NearStageInput');n=raw.NearStageInput;
prices=double(n.Cost.electricity_price_yuan_per_kWh(:));
etaFC=double(n.HydrogenDevice.eta_FC);lhv=double(n.HydrogenDevice.h2_lhv_kWh_per_kg);
kH2=double(n.HydrogenDevice.k_H2_kg_per_kWh);averagePrice=mean(prices);
sec=1/kH2;cH2=sec*averagePrice;electricityPerKg=etaFC*lhv;M=70*electricityPerKg;
if numel(prices)~=24||abs(averagePrice-0.634166666666667)>1e-14|| ...
        abs(cH2-32.5213675213675)>1e-10||abs(M-1283.205)>1e-9
    error('C5B economic parameter reproduction gate failed.');
end

eta=[0;0.0003;0.001;0.003;0.01;0.03];
label=["SAA";"ETA_0.0003";"ETA_0.001";"ETA_0.003";"ETA_0.01";"ETA_0.03"];
role=["economic_baseline";"small_radius_reference";"transition_point"; ...
    "existing_mild_candidate";"existing_safety_candidate";"saturation_probe"];
grid=table((1:6).',eta,label,role,repmat(19,6,1),repmat(15000,6,1), ...
    repmat(cH2,6,1),repmat(M,6,1),repmat(electricityPerKg,6,1), ...
    'VariableNames',{'case_id','eta','decision_label','grid_role','state_id', ...
    'nominal_R','c_H2_yuan_per_kg','M_H2_yuan_per_kg','electricity_per_kg_H2_kWh'});
writetable(grid,fullfile(workDir,'eta_grid_spec.csv'));

summary=table(19,15000,6,3,6,135,averagePrice,cH2,M,electricityPerKg, ...
    height(manifest),all(hashPass),toc(started), ...
    'VariableNames',{'state_id','nominal_R','eta_count','C2_dataset_count', ...
    'C3_combined_dataset_count','pressure_replica_count','average_price', ...
    'c_H2','M_H2','electricity_per_kg_H2','frozen_input_count', ...
    'all_hash_pass','prepare_runtime_sec'});
writetable(summary,fullfile(workDir,'prepare_summary.csv'));
fid=fopen(fullfile(workDir,'prepare_mechanical_audit.txt'),'w');cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'status=PASS\neta_grid=0,0.0003,0.001,0.003,0.01,0.03\n');
fprintf(fid,'all_frozen_input_hashes_pass=1\nC5B_economic_parameters_reproduced=1\n');
fprintf(fid,'MSP_called=0\nC5B_solver_modified=0\nvalidation_reoptimization=0\n');
fprintf('STEP04CC5C_PREPARE_COMPLETE|inputs=%d|runtime=%.3f\n',height(manifest),toc(started));
end

function assert_git_gate(expectedBranch,expectedHead)
[s1,b]=system('git branch --show-current');[s2,h]=system('git rev-parse HEAD');
[s3,u]=system('git rev-parse @{upstream}');
if s1~=0||s2~=0||s3~=0||strtrim(string(b))~=expectedBranch|| ...
        strtrim(string(h))~=expectedHead||strtrim(string(u))~=expectedHead
    error('Step-04C-C5C frozen Git gate failed.');
end
end
function hash=sha256_file(fileName)
fid=fopen(fileName,'rb');if fid<0,error('Could not open %s.',fileName);end
cleanup=onCleanup(@()fclose(fid));md=java.security.MessageDigest.getInstance('SHA-256');
while true,bytes=fread(fid,1024*1024,'*uint8');if isempty(bytes),break;end;md.update(typecast(bytes,'int8'));end
digest=typecast(md.digest(),'uint8');hash=lower(string(reshape(dec2hex(digest,2).',1,[])));
end
