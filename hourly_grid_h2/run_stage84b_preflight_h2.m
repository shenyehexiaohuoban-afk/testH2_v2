function run_stage84b_preflight_h2()
%RUN_STAGE84B_PREFLIGHT_H2 Read-only identity/storage preflight without Gurobi.

rootDir=fileparts(fileparts(mfilename('fullpath')));
baseDir=fullfile(rootDir,'results','task-002-stage2b-b3-smoke','84B-full-common-oos-paired-analysis');
if exist(fullfile(baseDir,'run-001'),'dir')
    error('Stage84BPreflight:RunExists','Stage-84B run-001 already exists.');
end
id=1;outDir=fullfile(baseDir,sprintf('preflight-run-%03d',id));
while exist(outDir,'dir'),id=id+1;outDir=fullfile(baseDir,sprintf('preflight-run-%03d',id));end
mkdir(outDir);

trainingCommit="cd7084300b0a50ade053e6b45ea7a1701d52c307";
oosFixCommit="4935f227c23010e2afd79475744da212ba4232a4";
formalDir=fullfile(rootDir,'results','task-002-stage2b-b3-smoke','84-hourly-grid-formal-training-oos','run-001');
saaCp=fullfile(formalDir,'checkpoints','saa','checkpoint_final.mat');
droCp=fullfile(formalDir,'checkpoints','chi2_eta003','checkpoint_final.mat');
bankFile=fullfile(formalDir,'03-common-oos-paths','oos_path_bank.mat');
manifestFile=fullfile(formalDir,'03-common-oos-paths','oos_path_manifest.csv');
accepted=fullfile(rootDir,'results','task-002-stage2b-b3-smoke','84A-oos-hourly-schema-fix','run-002','final_judgment.txt');
files={saaCp,droCp,bankFile,manifestFile,accepted, ...
    fullfile(rootDir,'hourly_grid_h2','stage84b_full_oos_method_h2.m'), ...
    fullfile(rootDir,'hourly_grid_h2','run_stage84b_full_oos_analysis_h2.m'), ...
    fullfile(rootDir,'hourly_grid_h2','analyze_stage84b_full_oos.py'), ...
    fullfile(rootDir,'hourly_grid_h2','launch_stage84b_full_oos.ps1')};
inputsExist=all(cellfun(@isfile,files));
if ~inputsExist,error('Stage84BPreflight:MissingFile','A required input or runner file is missing.');end

s=load(saaCp,'checkpoint_metadata','policy');d=load(droCp,'checkpoint_metadata','policy');
checkpointPass=string(s.checkpoint_metadata.method)=="saa"&& ...
    string(d.checkpoint_metadata.method)=="chi2_eta003"&& ...
    string(s.checkpoint_metadata.frozen_commit)==trainingCommit&& ...
    string(d.checkpoint_metadata.frozen_commit)==trainingCommit&& ...
    s.checkpoint_metadata.cumulative_cuts==645314&&d.checkpoint_metadata.cumulative_cuts==643212&& ...
    string(s.policy.state_order)=="I1,I2,I3,I4"&&string(d.policy.state_order)=="I1,I2,I3,I4";
bank=load(bankFile,'pathBank');manifest=readtable(manifestFile);
bankPass=isequal(size(bank.pathBank),[10000,8])&&height(manifest)==10000&& ...
    isequal(manifest.path_id,(1:10000).')&&isequal(manifest{:,2:9},bank.pathBank)&&bank.pathBank(1,1)==65;
fixPass=contains(fileread(accepted),'PASS_READY_TO_FREEZE_OOS_FIX');
fixCode=fileread(fullfile(rootDir,'hourly_grid_h2','stage84_timed_oos_h2.m'));
typedEmptyPass=contains(fixCode,'hourBatch=hourTemplate([])')&&contains(fixCode,'hourBatch=hourBatch([])');
[pythonStatus,pythonText]=system('python -c "import numpy,pandas; print(numpy.__version__, pandas.__version__)"');
pythonPass=pythonStatus==0;

smokeDir=fullfile(rootDir,'results','task-002-stage2b-b3-smoke','84A-oos-hourly-schema-fix','run-002');
components={
    'saa_hourly_mat',fullfile(smokeDir,'saa-oos','oos_hourly_grid_response_batch_0001.mat');
    'dro_hourly_mat',fullfile(smokeDir,'dro-oos','oos_hourly_grid_response_batch_0001.mat');
    'saa_path_csv',fullfile(smokeDir,'saa-oos','oos_path_summary.csv');
    'dro_path_csv',fullfile(smokeDir,'dro-oos','oos_path_summary.csv');
    'saa_stage_csv',fullfile(smokeDir,'saa-oos','oos_stage_site_response.csv');
    'dro_stage_csv',fullfile(smokeDir,'dro-oos','oos_stage_site_response.csv')};
storageRows=cell(size(components,1),4);rawEstimate=0;
for i=1:size(components,1)
    info=dir(components{i,2});estimate=info.bytes/3*10000;rawEstimate=rawEstimate+estimate;
    storageRows(i,:)={components{i,1},info.bytes,estimate,estimate/1024^3};
end
storage=cell2table(storageRows,'VariableNames',{'component','smoke_3path_bytes','estimated_10000path_bytes','estimated_10000path_gib'});
writetable(storage,fullfile(outDir,'storage_estimate.csv'));
analysisReserve=max(1024^3,0.5*rawEstimate);requiredWithSafety=3*(rawEstimate+analysisReserve);
drive=java.io.File(rootDir);freeBytes=drive.getUsableSpace();storagePass=freeBytes>requiredWithSafety&&freeBytes>50*1024^3;
summary=table(rawEstimate,analysisReserve,requiredWithSafety,freeBytes,rawEstimate/1024^3, ...
    requiredWithSafety/1024^3,freeBytes/1024^3,storagePass, ...
    'VariableNames',{'raw_estimated_bytes','analysis_reserve_bytes','required_with_3x_safety_bytes', ...
    'free_bytes','raw_estimated_gib','required_with_3x_safety_gib','free_gib','pass'});
writetable(summary,fullfile(outDir,'storage_gate.csv'));

probe=table("stage84b",true,'VariableNames',{'name','pass'});probeFile=fullfile(outDir,'safe_write_probe.csv');
[folder,name,ext]=fileparts(probeFile);temp=fullfile(folder,[name '.tmp' ext]);
writetable(probe,temp);movefile(temp,probeFile,'f');reloaded=readtable(probeFile);
safeWritePass=height(reloaded)==1&&reloaded.pass;
checks=table(inputsExist,checkpointPass,bankPass,fixPass,typedEmptyPass,pythonPass,storagePass,safeWritePass, ...
    string(strtrim(pythonText)),'VariableNames',{'inputs_exist','checkpoint_identity','common_bank_identity', ...
    'stage84a_accepted','typed_empty_fix_present','python_numpy_pandas','storage_gate','safe_write_reload', ...
    'python_versions'});
writetable(checks,fullfile(outDir,'preflight_checks.csv'));
pass=all(checks{1,1:8});
judgment=ternary(pass,"PREFLIGHT_PASS_READY_TO_FREEZE_RUNNER","PREFLIGHT_FAIL");
txt=sprintf(['FINAL_JUDGMENT=%s\nTRAINING_COMMIT=%s\nOOS_FIX_COMMIT=%s\n' ...
    'FORMAL_OOS_STARTED=false\nGUROBI_SOLVE_STARTED=false\n'],judgment,trainingCommit,oosFixCommit);
write_text(fullfile(outDir,'final_judgment.txt'),txt);
if ~pass,error('Stage84BPreflight:Gate','Stage-84B preflight failed.');end
end

function write_text(path,txt)
fid=fopen(path,'w');if fid<0,error('Cannot write %s.',path);end;c=onCleanup(@()fclose(fid));fprintf(fid,'%s',txt);
end

function y=ternary(test,a,b)
if test,y=a;else,y=b;end
end
