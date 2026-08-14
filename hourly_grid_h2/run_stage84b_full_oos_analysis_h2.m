function run_stage84b_full_oos_analysis_h2()
%RUN_STAGE84B_FULL_OOS_ANALYSIS_H2 Full common-path OOS followed by offline analysis.

rootDir=fileparts(fileparts(mfilename('fullpath')));
addpath(rootDir);addpath(fullfile(rootDir,'fa_h2'));addpath(fullfile(rootDir,'fa_h2','fuzhu'));
addpath(fullfile(rootDir,'utils'));addpath(fullfile(rootDir,'hourly_grid_h2'));
trainingCommit="cd7084300b0a50ade053e6b45ea7a1701d52c307";
oosFixCommit="4935f227c23010e2afd79475744da212ba4232a4";
oosRunCommit=strtrim(string(getenv('STAGE84B_RUN_COMMIT')));
runId=char(string(getenv('STAGE84B_RUN_ID')));if isempty(runId),runId='run-001';end
if oosRunCommit=="",error('Stage84B:MissingRunCommit','STAGE84B_RUN_COMMIT is required.');end
[gitStatus,head]=system('git rev-parse HEAD');head=strtrim(string(head));
if gitStatus~=0||head~=oosRunCommit,error('Stage84B:HeadMismatch','HEAD %s != run commit %s.',head,oosRunCommit);end

baseDir=fullfile(rootDir,'results','task-002-stage2b-b3-smoke','84B-full-common-oos-paired-analysis');
runDir=fullfile(baseDir,runId);
if exist(runDir,'dir'),error('Stage84B:OutputExists','Refusing to overwrite %s.',runDir);end
make_dirs(runDir);pid=feature('getpid');
lineage=struct('training_commit',trainingCommit,'oos_fix_commit',oosFixCommit,'oos_run_commit',oosRunCommit);
write_status(runDir,'RUNNING','PREPARING','NONE',0,0,pid,lineage);
diary(fullfile(runDir,'logs','matlab_diary.txt'));

formalDir=fullfile(rootDir,'results','task-002-stage2b-b3-smoke','84-hourly-grid-formal-training-oos','run-001');
saaCp=fullfile(formalDir,'checkpoints','saa','checkpoint_final.mat');
droCp=fullfile(formalDir,'checkpoints','chi2_eta003','checkpoint_final.mat');
bankFile=fullfile(formalDir,'03-common-oos-paths','oos_path_bank.mat');
manifestFile=fullfile(formalDir,'03-common-oos-paths','oos_path_manifest.csv');
try
    validate_inputs(rootDir,saaCp,droCp,bankFile,manifestFile,lineage);
    bankData=load(bankFile,'pathBank');pathBank=bankData.pathBank;
    pathManifest=readtable(manifestFile);
    if ~isequal(size(pathBank),[10000,8])||height(pathManifest)~=10000|| ...
            ~isequal(pathManifest.path_id,(1:10000).')||~isequal(pathManifest{:,2:9},pathBank)
        error('Stage84B:CommonBankIdentity','Frozen common bank identity mismatch.');
    end
    write_lineage(runDir,saaCp,droCp,bankFile,manifestFile,pathBank,lineage);
    write_readme(runDir,lineage,'RUNNING');

    saa=stage84b_full_oos_method_h2(saaCp,pathBank,fullfile(runDir,'01-saa-oos'), ...
        "saa",runDir,lineage,pid);
    if saa.completed_paths~=10000,error('Stage84B:SAAIncomplete','SAA did not complete 10000 paths.');end
    clear saa
    dro=stage84b_full_oos_method_h2(droCp,pathBank,fullfile(runDir,'02-dro-oos'), ...
        "chi2_eta003",runDir,lineage,pid);
    if dro.completed_paths~=10000,error('Stage84B:DROIncomplete','DRO did not complete 10000 paths.');end
    clear dro pathBank bankData pathManifest

    write_status(runDir,'RUNNING','OFFLINE_PAIRED_ANALYSIS','BOTH',10000,10000,pid,lineage);
    analysisScript=fullfile(rootDir,'hourly_grid_h2','analyze_stage84b_full_oos.py');
    analysisLog=fullfile(runDir,'logs','analysis_stdout.txt');
    command=sprintf('python "%s" --run-dir "%s" --training-commit %s --oos-fix-commit %s --oos-run-commit %s > "%s" 2>&1', ...
        analysisScript,runDir,trainingCommit,oosFixCommit,oosRunCommit,analysisLog);
    [analysisStatus,analysisOutput]=system(command);
    if analysisStatus~=0
        error('Stage84B:AnalysisFailure','Offline analysis failed (%d): %s',analysisStatus,analysisOutput);
    end
    judgmentFile=fullfile(runDir,'final_judgment.txt');
    if ~isfile(judgmentFile)||~contains(fileread(judgmentFile),'PASS_COMPLETE_10000_PAIRED_OOS')
        error('Stage84B:FinalGate','Final analysis judgment is missing or not PASS.');
    end
    write_readme(runDir,lineage,'COMPLETE');
    write_status(runDir,'COMPLETE','COMPLETE','BOTH',10000,10000,pid,lineage);
catch ME
    write_failure(runDir,ME);write_status(runDir,'FAILED','FAILED','NONE',0,0,pid,lineage);
    diary off;rethrow(ME);
end
diary off;
end

function validate_inputs(rootDir,saaCp,droCp,bankFile,manifestFile,lineage)
required={saaCp,droCp,bankFile,manifestFile};
if ~all(cellfun(@isfile,required)),error('Stage84B:MissingInput','A frozen Stage-84 input is missing.');end
accepted=fullfile(rootDir,'results','task-002-stage2b-b3-smoke','84A-oos-hourly-schema-fix', ...
    'run-002','final_judgment.txt');
if ~isfile(accepted)||~contains(fileread(accepted),'PASS_READY_TO_FREEZE_OOS_FIX')
    error('Stage84B:FixGate','Stage-84A run-002 accepted gate is missing.');
end
s=load(saaCp,'checkpoint_metadata','policy');d=load(droCp,'checkpoint_metadata','policy');
if string(s.checkpoint_metadata.method)~="saa"||string(d.checkpoint_metadata.method)~="chi2_eta003"|| ...
        string(s.checkpoint_metadata.frozen_commit)~=lineage.training_commit|| ...
        string(d.checkpoint_metadata.frozen_commit)~=lineage.training_commit|| ...
        s.checkpoint_metadata.cumulative_cuts~=645314||d.checkpoint_metadata.cumulative_cuts~=643212|| ...
        string(s.policy.state_order)~="I1,I2,I3,I4"||string(d.policy.state_order)~="I1,I2,I3,I4"
    error('Stage84B:CheckpointMetadata','Frozen checkpoint metadata mismatch.');
end
end

function write_lineage(runDir,saaCp,droCp,bankFile,manifestFile,pathBank,lineage)
names=["training_commit";"oos_fix_commit";"oos_run_commit";"schema_version"; ...
    "saa_checkpoint";"saa_checkpoint_sha256";"dro_checkpoint";"dro_checkpoint_sha256"; ...
    "common_path_bank";"common_path_bank_sha256";"common_path_manifest"; ...
    "common_path_manifest_sha256";"common_path_shape";"common_path_seed"; ...
    "initial_state";"common_path_order"];
values=[lineage.training_commit;lineage.oos_fix_commit;lineage.oos_run_commit;"stage84b-v1"; ...
    string(saaCp);sha256_file(saaCp);string(droCp);sha256_file(droCp);string(bankFile); ...
    sha256_file(bankFile);string(manifestFile);sha256_file(manifestFile); ...
    string(sprintf('%dx%d',size(pathBank,1),size(pathBank,2)));"20262513"; ...
    string(pathBank(1,1));"true"];
write_table_safe(table(names,values),fullfile(runDir,'00-lineage','run_lineage.csv'));
end

function make_dirs(runDir)
dirs={'00-lineage','01-saa-oos','02-dro-oos','03-analysis','logs'};
mkdir(runDir);for i=1:numel(dirs),mkdir(fullfile(runDir,dirs{i}));end
end

function write_readme(runDir,lineage,status)
txt=sprintf(['# Stage-84B full common-path OOS and paired analysis\n\n' ...
    '- Status: `%s`\n- Training commit: `%s`\n- OOS schema-fix commit: `%s`\n' ...
    '- OOS runner commit: `%s`\n- Frozen common bank: 10000 paths, seed 20262513\n' ...
    '- Methods: SAA and Pearson chi-square DRO eta=0.03\n' ...
    '- This run evaluates the main FA-MSP policy only. It does not evaluate W1-W3 disaster recourse or EENS.\n'], ...
    status,lineage.training_commit,lineage.oos_fix_commit,lineage.oos_run_commit);
write_text_safe(fullfile(runDir,'README.md'),txt);
end

function write_status(runDir,status,phase,method,pathId,closed,pid,lineage)
txt=sprintf(['STATUS=%s\nPHASE=%s\nMETHOD=%s\nCURRENT_PATH_ID=%d\nCLOSED_COMPLETED_PATHS=%d\n' ...
    'MATLAB_PID=%d\nTRAINING_COMMIT=%s\nOOS_FIX_COMMIT=%s\nOOS_RUN_COMMIT=%s\nLAST_UPDATE_TIME=%s\n'], ...
    status,phase,method,pathId,closed,pid,lineage.training_commit,lineage.oos_fix_commit, ...
    lineage.oos_run_commit,char(datetime('now','Format','yyyy-MM-dd HH:mm:ss')));
write_text_safe(fullfile(runDir,'RUNNING_STATUS.txt'),txt);
end

function write_failure(runDir,ME)
txt=string(sprintf('STATUS=FAIL\nidentifier=%s\nmessage=%s\n',ME.identifier,ME.message));
for i=1:numel(ME.stack),txt=txt+string(sprintf('stack_%d=%s:%d\n',i,ME.stack(i).name,ME.stack(i).line));end
statusFile=fullfile(runDir,'RUNNING_STATUS.txt');
if isfile(statusFile)
    txt=txt+"LAST_STATUS_BEFORE_FAILURE_BEGIN"+newline+string(fileread(statusFile))+ ...
        "LAST_STATUS_BEFORE_FAILURE_END"+newline;
end
write_text_safe(fullfile(runDir,'FAILURE.txt'),txt);
end

function write_table_safe(t,path)
[folder,name,ext]=fileparts(path);temp=fullfile(folder,[name '.tmp' ext]);
writetable(t,temp);movefile(temp,path,'f');
end

function write_text_safe(path,txt)
temp=[path '.tmp'];fid=fopen(temp,'w');if fid<0,error('Stage84B:Write','Cannot write %s.',temp);end
c=onCleanup(@()fclose(fid));fprintf(fid,'%s',char(txt));clear c;movefile(temp,path,'f');
end

function hex=sha256_file(path)
md=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(path,'r');
if fid<0,error('Stage84B:Hash','Cannot hash %s.',path);end;c=onCleanup(@()fclose(fid));
while true,data=fread(fid,1024*1024,'*uint8');if isempty(data),break;end;md.update(data);end
hex=lower(string(reshape(dec2hex(typecast(md.digest(),'uint8'),2).',1,[])));
end
