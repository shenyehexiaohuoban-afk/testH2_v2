clear; clc;

thisDir = fileparts(mfilename('fullpath'));
moduleDir = fileparts(thisDir);
rootDir = fileparts(moduleDir);

taskId = "task-001";
stepId = "02-w3-main-path-sampling-fixed-seed-audit";
runId = "run-003";
runCommand = "cd('C:/Users/chaos/Desktop/biye/test/testH2_v2'); " + ...
    "run('terminalLoh_wdro/src/run_stage2a2_W3_fixed_seed_sample_audit_h2.m');";

sourceSampleFile = fullfile(moduleDir,'output', ...
    'stage2a2_W3_path_sampling','run-002','main_path_samples.csv');
outputDir = fullfile(moduleDir,'output', ...
    'stage2a2_W3_path_sampling','run-003');
configDir = fullfile(moduleDir,'config');
intensityFile = fullfile(configDir,'lookahead_intensity_postlandfall_W3.csv');
locationFile = fullfile(configDir,'lookahead_location_postlandfall_W3.csv');
lfwFile = fullfile(configDir,'lookahead_lfw_postlandfall_W3.csv');

expectedSeed = 20260706;
expectedPerInitial = 15000;
expectedInitialCount = 35;
expectedTotalRows = expectedPerInitial*expectedInitialCount;
expectedSampleHash = ...
    "972a8c58620c09ac19cfcfb29e8d6a3ed2819ef1a22dbd522043436418eb805d";
empiricalWeight = 1/expectedPerInitial;
p95Threshold = 0.02;
worstThreshold = 0.05;
meanJointTvThreshold = 0.03;
probabilityTolerance = 1e-12;
rowTolerance = 1e-10;
stageNames = ["W1","W2","W3"];

requiredFiles = {sourceSampleFile,intensityFile,locationFile,lfwFile};
for ii=1:numel(requiredFiles)
    if ~isfile(requiredFiles{ii})
        error('run_stage2a2_W3_fixed_seed_sample_audit_h2:MissingInput', ...
            'Missing required input: %s',requiredFiles{ii});
    end
end
if isfolder(outputDir)
    existing=dir(outputDir);
    existing=existing(~ismember({existing.name},{'.','..'}));
    if ~isempty(existing)
        error('run_stage2a2_W3_fixed_seed_sample_audit_h2:OutputExists', ...
            'Refusing to overwrite nonempty output directory: %s',outputDir);
    end
else
    mkdir(outputDir);
end

sourceInfoBefore=dir(sourceSampleFile);
sourceHashBefore=sha256_file(sourceSampleFile);
matrixFiles={intensityFile,locationFile,lfwFile};
matrixHashBefore=strings(3,1);
for ii=1:3
    matrixHashBefore(ii)=sha256_file(matrixFiles{ii});
end

intensityTbl=readtable(intensityFile);
locationTbl=readtable(locationFile);
lfwTbl=readtable(lfwFile);
samples=readtable(sourceSampleFile);

requiredSampleVars={'a0','loc0','lfw0','lf','path_id', ...
    'base_random_seed','derived_seed','a_W1','a_W2','a_W3', ...
    'loc_W1','loc_W2','loc_W3','lfw_W1','lfw_W2','lfw_W3', ...
    'path_probability'};
require_vars(samples,requiredSampleVars,sourceSampleFile);

aStates=(1:6).';
locStates=(-2:10).';
lfwStates=(0:3).';
[PA,aRowError]=build_transition_matrix(intensityTbl,'from_a','to_a', ...
    aStates,rowTolerance);
[PLoc,locRowError]=build_transition_matrix(locationTbl, ...
    'from_loc_id','to_loc_id',locStates,rowTolerance);
[PLfw,lfwRowError]=build_transition_matrix(lfwTbl, ...
    'from_lfw','to_lfw',lfwStates,rowTolerance);

totalRows=height(samples);
initialStates=unique(samples(:,{'a0','loc0','lfw0'}),'rows');
initialStates=sortrows(initialStates,{'a0','loc0','lfw0'});
initialCount=height(initialStates);
[groupId,groupA,groupLoc,groupLfw]=findgroups( ...
    samples.a0,samples.loc0,samples.lfw0);
groupCounts=splitapply(@numel,samples.path_id,groupId);
initialStateCounts=table(groupA,groupLoc,groupLfw,groupCounts, ...
    groupCounts==expectedPerInitial, ...
    'VariableNames',{'a0','loc0','lfw0','sample_count', ...
    'has_expected_sample_count'});
initialStateCounts=sortrows(initialStateCounts,{'a0','loc0','lfw0'});

stateSupportOk=all(ismember(samples.a0,2:6)) && ...
    all(ismember(samples.loc0,1:7)) && all(samples.lfw0==0) && ...
    all(ismember(samples.a_W1,aStates)) && ...
    all(ismember(samples.a_W2,aStates)) && ...
    all(ismember(samples.a_W3,aStates)) && ...
    all(ismember(samples.loc_W1,locStates)) && ...
    all(ismember(samples.loc_W2,locStates)) && ...
    all(ismember(samples.loc_W3,locStates)) && ...
    all(ismember(samples.lfw_W1,lfwStates)) && ...
    all(ismember(samples.lfw_W2,lfwStates)) && ...
    all(ismember(samples.lfw_W3,lfwStates));

baseSeedOk=all(samples.base_random_seed==expectedSeed);
expectedInitIndex=(samples.a0-2)*7+samples.loc0;
derivedSeedOk=all(samples.derived_seed==expectedSeed+1000*expectedInitIndex);
pathIdOk=true;
for ii=1:initialCount
    q=samples(groupId==ii,:);
    pathIdOk=pathIdOk && height(q)==expectedPerInitial && ...
        isequal(sort(q.path_id),(1:expectedPerInitial).');
end

nA=numel(aStates);nLoc=numel(locStates);nLfw=numel(lfwStates);
errorRows=cell(expectedInitialCount*3*4,12);
rr=0;
for initIdx=1:initialCount
    a0=initialStates.a0(initIdx);
    loc0=initialStates.loc0(initIdx);
    lfw0=initialStates.lfw0(initIdx);
    q=samples(samples.a0==a0 & samples.loc0==loc0 & ...
        samples.lfw0==lfw0,:);
    N=height(q);

    pA=zeros(1,nA);pA(a0)=1;
    pLoc=zeros(1,nLoc);pLoc(loc0-locStates(1)+1)=1;
    pLfw=zeros(1,nLfw);pLfw(lfw0+1)=1;
    for ss=1:3
        pA=pA*PA;pLoc=pLoc*PLoc;pLfw=pLfw*PLfw;
        exactJoint=reshape(reshape(pA,[],1,1).*reshape(pLoc,1,[],1).* ...
            reshape(pLfw,1,1,[]),[],1);

        aValues=q.(sprintf('a_W%d',ss));
        locValues=q.(sprintf('loc_W%d',ss));
        lfwValues=q.(sprintf('lfw_W%d',ss));
        aIndex=aValues;
        locIndex=locValues-locStates(1)+1;
        lfwIndex=lfwValues+1;
        empiricalA=accumarray(aIndex,1,[nA,1])/N;
        empiricalLoc=accumarray(locIndex,1,[nLoc,1])/N;
        empiricalLfw=accumarray(lfwIndex,1,[nLfw,1])/N;
        jointIndex=sub2ind([nA,nLoc,nLfw],aIndex,locIndex,lfwIndex);
        empiricalJoint=accumarray(jointIndex,1,[nA*nLoc*nLfw,1])/N;

        names=["intensity","loc","lfw","joint"];
        empirical={empiricalA,empiricalLoc,empiricalLfw,empiricalJoint};
        exact={pA(:),pLoc(:),pLfw(:),exactJoint};
        supports=[nA,nLoc,nLfw,nA*nLoc*nLfw];
        for dd=1:4
            [maxError,tv]=distribution_error(empirical{dd},exact{dd});
            rr=rr+1;
            errorRows(rr,:)={a0,loc0,lfw0,N,stageNames(ss),ss, ...
                names(dd),maxError,tv,supports(dd), ...
                empiricalWeight,"uniform_count_not_path_probability"};
        end
    end
end
samplingError=cell2table(errorRows,'VariableNames', ...
    {'a0','loc0','lfw0','N','stage','stage_index', ...
    'distribution_type','max_abs_error','total_variation_distance', ...
    'support_size','empirical_weight','weighting_mode'});

p95MaxError=percentile_nearest(samplingError.max_abs_error,95);
worstMaxError=max(samplingError.max_abs_error);
jointRows=samplingError(samplingError.distribution_type=="joint",:);
meanJointTv=mean(jointRows.total_variation_distance);

aPaths=[samples.a_W1,samples.a_W2,samples.a_W3];
locPaths=[samples.loc_W1,samples.loc_W2,samples.loc_W3];
lfwPaths=[samples.lfw_W1,samples.lfw_W2,samples.lfw_W3];
transitionRows=cell(9,6);
tr=0;
nonconfiguredStageRecordCount=0;
nonconfiguredComponentCount=0;
recomputedPathProbability=ones(totalRows,1);
previousA=samples.a0;
previousLoc=samples.loc0-locStates(1)+1;
previousLfw=samples.lfw0+1;
for ss=1:3
    currentA=aPaths(:,ss);
    currentLoc=locPaths(:,ss)-locStates(1)+1;
    currentLfw=lfwPaths(:,ss)+1;
    [configuredA,probA]=configured_transitions(PA,previousA,currentA);
    [configuredLoc,probLoc]=configured_transitions(PLoc,previousLoc,currentLoc);
    [configuredLfw,probLfw]=configured_transitions(PLfw,previousLfw,currentLfw);
    configuredAll=configuredA & configuredLoc & configuredLfw;
    nonconfiguredStageRecordCount=nonconfiguredStageRecordCount+sum(~configuredAll);
    nonconfiguredComponentCount=nonconfiguredComponentCount+ ...
        sum(~configuredA)+sum(~configuredLoc)+sum(~configuredLfw);
    recomputedPathProbability=recomputedPathProbability.*probA.*probLoc.*probLfw;

    names=["intensity","loc","lfw"];
    masks={configuredA,configuredLoc,configuredLfw};
    for dd=1:3
        tr=tr+1;
        transitionRows(tr,:)={stageNames(ss),ss,names(dd),totalRows, ...
            sum(~masks{dd}),sum(masks{dd})};
    end
    previousA=currentA;previousLoc=currentLoc;previousLfw=currentLfw;
end
transitionAudit=cell2table(transitionRows,'VariableNames', ...
    {'stage','stage_index','matrix','transition_record_count', ...
    'nonconfigured_transition_count','configured_transition_count'});

pathProbabilityAbsError=abs(samples.path_probability-recomputedPathProbability);
pathProbabilityMaxAbsError=max(pathProbabilityAbsError);
pathProbabilityAudit=table(expectedSeed,expectedPerInitial,empiricalWeight, ...
    min(samples.path_probability),max(samples.path_probability), ...
    pathProbabilityMaxAbsError,false, ...
    "audit_only_uniform_empirical_weight", ...
    'VariableNames',{'fixed_seed','samples_per_initial_state', ...
    'empirical_weight','reported_path_probability_min', ...
    'reported_path_probability_max','recomputed_max_abs_error', ...
    'path_probability_used_for_empirical_weighting','weighting_rule'});

sourceInfoAfter=dir(sourceSampleFile);
sourceHashAfter=sha256_file(sourceSampleFile);
matrixHashAfter=strings(3,1);
for ii=1:3
    matrixHashAfter(ii)=sha256_file(matrixFiles{ii});
end
sourceUnchanged=sourceHashBefore==sourceHashAfter && ...
    sourceInfoBefore.bytes==sourceInfoAfter.bytes;
matricesUnchanged=isequal(matrixHashBefore,matrixHashAfter);

scriptFile=mfilename('fullpath');
if ~endsWith(scriptFile,'.m'),scriptFile=scriptFile+".m";end
scriptText=fileread(scriptFile);
samplingCallHits=regexp(scriptText, ...
    '\<(rand|randn|randi|rng|sample_chain)\s*\(','match');
noSamplingCalls=isempty(samplingCallHits);

summary=table(expectedSeed,totalRows,initialCount,expectedPerInitial, ...
    empiricalWeight,p95MaxError,worstMaxError,meanJointTv, ...
    nonconfiguredStageRecordCount,nonconfiguredComponentCount, ...
    sourceInfoAfter.bytes,sourceHashAfter, ...
    p95MaxError<=p95Threshold,worstMaxError<=worstThreshold, ...
    meanJointTv<=meanJointTvThreshold,nonconfiguredStageRecordCount==0, ...
    'VariableNames',{'fixed_seed','total_rows','initial_state_count', ...
    'samples_per_initial_state','empirical_weight', ...
    'p95_max_abs_error','worst_max_abs_error','mean_joint_state_tv', ...
    'nonconfigured_stage_record_count', ...
    'nonconfigured_component_transition_count','source_size_bytes', ...
    'source_sha256','criterion_p95_pass','criterion_worst_pass', ...
    'criterion_mean_joint_tv_pass','criterion_nonconfigured_pass'});

checkRows={};
checkRows=add_check(checkRows,"AUDIT-01","source SHA-256 matches accepted hash", ...
    sourceHashBefore==expectedSampleHash,sourceHashBefore,expectedSampleHash);
checkRows=add_check(checkRows,"AUDIT-02","source total row count", ...
    totalRows==expectedTotalRows,totalRows,expectedTotalRows);
checkRows=add_check(checkRows,"AUDIT-03","all 35 initial states present", ...
    initialCount==expectedInitialCount,initialCount,expectedInitialCount);
checkRows=add_check(checkRows,"AUDIT-04","15000 rows per initial state", ...
    all(initialStateCounts.has_expected_sample_count), ...
    min(initialStateCounts.sample_count),expectedPerInitial);
checkRows=add_check(checkRows,"AUDIT-05","fixed base seed is 20260706", ...
    baseSeedOk,unique(samples.base_random_seed),expectedSeed);
checkRows=add_check(checkRows,"AUDIT-06","derived seeds match initial states", ...
    derivedSeedOk,derivedSeedOk,true);
checkRows=add_check(checkRows,"AUDIT-07","sample states are within supports", ...
    stateSupportOk,stateSupportOk,true);
checkRows=add_check(checkRows,"AUDIT-08","path ids are complete per state", ...
    pathIdOk,pathIdOk,true);
checkRows=add_check(checkRows,"AUDIT-09","p95 maximum absolute error", ...
    p95MaxError<=p95Threshold,p95MaxError,p95Threshold);
checkRows=add_check(checkRows,"AUDIT-10","worst maximum absolute error", ...
    worstMaxError<=worstThreshold,worstMaxError,worstThreshold);
checkRows=add_check(checkRows,"AUDIT-11","mean joint-state TV", ...
    meanJointTv<=meanJointTvThreshold,meanJointTv,meanJointTvThreshold);
checkRows=add_check(checkRows,"AUDIT-12","no nonconfigured stage transitions", ...
    nonconfiguredStageRecordCount==0,nonconfiguredStageRecordCount,0);
checkRows=add_check(checkRows,"AUDIT-13","path probability recomputes from matrices", ...
    pathProbabilityMaxAbsError<=probabilityTolerance, ...
    pathProbabilityMaxAbsError,probabilityTolerance);
checkRows=add_check(checkRows,"AUDIT-14", ...
    "empirical distribution weight is uniform 1/15000", ...
    empiricalWeight==1/expectedPerInitial,empiricalWeight,1/expectedPerInitial);
checkRows=add_check(checkRows,"AUDIT-15","audit script has no sampling calls", ...
    noSamplingCalls,strjoin(string(samplingCallHits),','),"none");
checkRows=add_check(checkRows,"AUDIT-16","source sample unchanged by audit", ...
    sourceUnchanged,sourceHashAfter,sourceHashBefore);
checkRows=add_check(checkRows,"AUDIT-17","candidate matrices unchanged", ...
    matricesUnchanged,strjoin(matrixHashAfter,' | '), ...
    strjoin(matrixHashBefore,' | '));
checkRows=add_check(checkRows,"AUDIT-18","transition matrices row-stochastic", ...
    max([aRowError,locRowError,lfwRowError])<=rowTolerance, ...
    max([aRowError,locRowError,lfwRowError]),rowTolerance);
auditChecklist=cell2table(checkRows,'VariableNames', ...
    {'check_id','description','passed','observed','expected','required'});
passCount=sum(auditChecklist.passed);
failCount=sum(~auditChecklist.passed);
auditStatus="PASS";
if failCount>0,auditStatus="FAIL";end

writetable(samplingError,fullfile(outputDir, ...
    'fixed_seed_sampling_error_by_initial_state.csv'));
writetable(summary,fullfile(outputDir,'fixed_seed_audit_summary.csv'));
writetable(transitionAudit,fullfile(outputDir, ...
    'fixed_seed_transition_audit.csv'));
writetable(initialStateCounts,fullfile(outputDir, ...
    'initial_state_sample_counts.csv'));
writetable(pathProbabilityAudit,fullfile(outputDir, ...
    'path_probability_audit.csv'));
writetable(auditChecklist,fullfile(outputDir,'audit_checklist.csv'));
write_source_manifest(fullfile(outputDir,'source_sample_manifest.txt'), ...
    sourceSampleFile,totalRows,sourceInfoAfter.bytes,sourceHashAfter, ...
    expectedSeed,expectedPerInitial,empiricalWeight);
write_audit_summary(fullfile(outputDir,'audit_summary.md'),taskId,stepId, ...
    runId,runCommand,auditStatus,passCount,failCount,summary, ...
    pathProbabilityMaxAbsError,sourceUnchanged,matricesUnchanged);
write_run_manifest(fullfile(outputDir,'run_manifest.txt'),taskId,stepId, ...
    runId,runCommand,auditStatus,passCount,failCount,sourceSampleFile, ...
    sourceHashBefore,sourceHashAfter,totalRows,sourceInfoAfter.bytes, ...
    empiricalWeight,p95MaxError,worstMaxError,meanJointTv, ...
    nonconfiguredStageRecordCount,pathProbabilityMaxAbsError,outputDir);

fprintf('\nFixed-seed W3 main path sample audit finished.\n');
fprintf('Status: %s; PASS=%d; FAIL=%d\n',auditStatus,passCount,failCount);
fprintf('p95 max error: %.12g\n',p95MaxError);
fprintf('worst max error: %.12g\n',worstMaxError);
fprintf('mean joint-state TV: %.12g\n',meanJointTv);
fprintf('nonconfigured transition records: %d\n', ...
    nonconfiguredStageRecordCount);
fprintf('Output directory: %s\n',outputDir);
if failCount>0
    error('run_stage2a2_W3_fixed_seed_sample_audit_h2:AuditFailed', ...
        'Audit failed: %s',strjoin(auditChecklist.check_id( ...
        ~auditChecklist.passed),', '));
end

function [P,maxRowError]=build_transition_matrix(tbl,fromName,toName,states,tol)
require_vars(tbl,{fromName,toName,'prob'},'transition table');
if height(unique(tbl(:,{fromName,toName}),'rows'))~=height(tbl)
    error('run_stage2a2_W3_fixed_seed_sample_audit_h2:DuplicateTransition', ...
        'Duplicate transition keys in %s/%s.',fromName,toName);
end
if any(~isfinite(tbl.prob)) || any(tbl.prob<0) || any(tbl.prob>1)
    error('run_stage2a2_W3_fixed_seed_sample_audit_h2:BadProbability', ...
        'Transition probabilities must be finite and in [0,1].');
end
P=zeros(numel(states));
for ii=1:height(tbl)
    fromIdx=find(states==tbl.(fromName)(ii),1);
    toIdx=find(states==tbl.(toName)(ii),1);
    if isempty(fromIdx)||isempty(toIdx)
        error('run_stage2a2_W3_fixed_seed_sample_audit_h2:UnknownState', ...
            'Transition references a state outside the configured support.');
    end
    P(fromIdx,toIdx)=tbl.prob(ii);
end
maxRowError=max(abs(sum(P,2)-1));
if maxRowError>tol || any(sum(P,2)==0)
    error('run_stage2a2_W3_fixed_seed_sample_audit_h2:BadRowSum', ...
        'Transition row sum error %.12g exceeds tolerance.',maxRowError);
end
end

function [configured,probability]=configured_transitions(P,previous,current)
configured=false(size(previous));
probability=zeros(size(previous));
valid=previous>=1 & previous<=size(P,1) & ...
    current>=1 & current<=size(P,2) & ...
    previous==fix(previous) & current==fix(current);
indices=sub2ind(size(P),previous(valid),current(valid));
probability(valid)=P(indices);
configured(valid)=probability(valid)>0;
end

function [maxError,tv]=distribution_error(empirical,exact)
delta=abs(double(empirical(:))-double(exact(:)));
maxError=max(delta);
tv=0.5*sum(delta);
end

function value=percentile_nearest(x,p)
x=sort(double(x(:)));
idx=max(1,min(numel(x),ceil((p/100)*numel(x))));
value=x(idx);
end

function rows=add_check(rows,id,description,passed,observed,expected)
rows(end+1,:)={string(id),string(description),logical(passed), ...
    scalar_text(observed),scalar_text(expected),true};
end

function s=scalar_text(value)
if isstring(value),s=strjoin(value(:).',' | ');
elseif ischar(value),s=string(value);
elseif islogical(value)&&isscalar(value),s=string(double(value));
elseif isnumeric(value)&&isscalar(value),s=string(sprintf('%.15g',value));
elseif isnumeric(value),s=strjoin(compose('%.15g',value(:).'),' | ');
else,s=string(value);end
end

function require_vars(tbl,names,fileName)
for ii=1:numel(names)
    if ~ismember(names{ii},tbl.Properties.VariableNames)
        error('run_stage2a2_W3_fixed_seed_sample_audit_h2:MissingColumn', ...
            '%s is missing %s.',fileName,names{ii});
    end
end
end

function hash=sha256_file(fileName)
fid=fopen(fileName,'rb');
if fid<0,error('run_stage2a2_W3_fixed_seed_sample_audit_h2:OpenFailed', ...
        'Could not open %s.',fileName);end
cleanup=onCleanup(@()fclose(fid));
md=java.security.MessageDigest.getInstance('SHA-256');
while true
    bytes=fread(fid,1024*1024,'*uint8');
    if isempty(bytes),break;end
    md.update(typecast(bytes,'int8'));
end
digest=typecast(md.digest(),'uint8');
hash=lower(string(reshape(dec2hex(digest,2).',1,[])));
end

function write_source_manifest(fileName,sourceFile,rowCount,fileBytes,fileHash, ...
    seed,samplesPerInitial,empiricalWeight)
fid=fopen(fileName,'w');if fid<0,error('source manifest open failed');end
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'source_file=%s\n',sourceFile);
fprintf(fid,'source_rows=%d\nsource_size_bytes=%d\n',rowCount,fileBytes);
fprintf(fid,'source_sha256=%s\nfixed_seed=%d\n',fileHash,seed);
fprintf(fid,'samples_per_initial_state=%d\n',samplesPerInitial);
fprintf(fid,'empirical_weight=%.15g\n',empiricalWeight);
fprintf(fid,'path_probability_role=audit_only\n');
fprintf(fid,'path_probability_used_for_empirical_weighting=false\n');
fprintf(fid,'source_copied_to_git=false\nsource_preserved=true\n');
end

function write_audit_summary(fileName,taskId,stepId,runId,runCommand,status, ...
    passCount,failCount,summary,pathProbabilityError,sourceUnchanged, ...
    matricesUnchanged)
fid=fopen(fileName,'w');if fid<0,error('audit summary open failed');end
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'# Fixed-Seed W3 Main Path Sample Audit\n\n');
fprintf(fid,'- task_id: `%s`\n- step_id: `%s`\n- run_id: `%s`\n', ...
    taskId,stepId,runId);
fprintf(fid,'- status: `%s`\n- MATLAB command: `%s`\n',status,runCommand);
fprintf(fid,'- PASS count: %d\n- FAIL count: %d\n\n',passCount,failCount);
fprintf(fid,'## Fixed Sample\n\n');
fprintf(fid,'- seed: %d; rows: %d; initial states: %d.\n', ...
    summary.fixed_seed,summary.total_rows,summary.initial_state_count);
fprintf(fid,'- samples per initial state: %d; empirical weight: %.15g.\n', ...
    summary.samples_per_initial_state,summary.empirical_weight);
fprintf(fid,'- path_probability is audit-only and is not used as an empirical weight.\n\n');
fprintf(fid,'## Acceptance Metrics\n\n');
fprintf(fid,'- p95 maximum absolute error: %.12g.\n',summary.p95_max_abs_error);
fprintf(fid,'- worst maximum absolute error: %.12g.\n',summary.worst_max_abs_error);
fprintf(fid,'- mean joint-state TV: %.12g.\n',summary.mean_joint_state_tv);
fprintf(fid,'- nonconfigured stage transition records: %d.\n', ...
    summary.nonconfigured_stage_record_count);
fprintf(fid,'- path_probability recomputation max error: %.12g.\n\n', ...
    pathProbabilityError);
fprintf(fid,'## Integrity and Scope\n\n');
fprintf(fid,'- source sample unchanged: %d.\n',sourceUnchanged);
fprintf(fid,'- candidate matrices unchanged: %d.\n',matricesUnchanged);
fprintf(fid,'- no resampling, B3, tail supplementation, WDRO, Gurobi, or MSP.\n');
end

function write_run_manifest(fileName,taskId,stepId,runId,runCommand,status, ...
    passCount,failCount,sourceFile,hashBefore,hashAfter,rowCount,fileBytes, ...
    empiricalWeight,p95Error,worstError,meanJointTv,nonconfiguredCount, ...
    pathProbabilityError,outputDir)
fid=fopen(fileName,'w');if fid<0,error('run manifest open failed');end
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'task_id=%s\nstep_id=%s\nrun_id=%s\n',taskId,stepId,runId);
fprintf(fid,'run_time=%s\n',char(datetime('now','Format','yyyy-MM-dd HH:mm:ss Z')));
fprintf(fid,'MATLAB_command=%s\nstatus=%s\n',runCommand,status);
fprintf(fid,'pass_count=%d\nfail_count=%d\n',passCount,failCount);
fprintf(fid,'output_directory=%s\nsource_file=%s\n',outputDir,sourceFile);
fprintf(fid,'source_rows=%d\nsource_size_bytes=%d\n',rowCount,fileBytes);
fprintf(fid,'source_sha256_before=%s\nsource_sha256_after=%s\n', ...
    hashBefore,hashAfter);
fprintf(fid,'empirical_weight=%.15g\n',empiricalWeight);
fprintf(fid,'p95_max_abs_error=%.15g\n',p95Error);
fprintf(fid,'worst_max_abs_error=%.15g\n',worstError);
fprintf(fid,'mean_joint_state_tv=%.15g\n',meanJointTv);
fprintf(fid,'nonconfigured_transition_records=%d\n',nonconfiguredCount);
fprintf(fid,'path_probability_recomputed_max_error=%.15g\n', ...
    pathProbabilityError);
fprintf(fid,'resampling=false\npath_probability_weighting=false\n');
fprintf(fid,'B3_run=false\ntail_supplementation=false\n');
fprintf(fid,'WDRO_run=false\nGurobi_run=false\nMSP_run=false\n');
end
