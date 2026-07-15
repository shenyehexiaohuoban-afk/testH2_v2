clear; clc;

thisDir = fileparts(mfilename('fullpath'));
moduleDir = fileparts(thisDir);
rootDir = fileparts(moduleDir);
addpath(thisDir);
addpath(rootDir);
addpath(fullfile(rootDir, 'fa_h2', 'fuzhu', 'terminalLoh_windmc'));

taskId = "task-001";
stepId = "02-w3-main-path-sampling";
runId = "run-002";
runCommand = "cd('C:/Users/chaos/Desktop/biye/test/testH2_v2'); " + ...
    "run('terminalLoh_wdro/src/run_stage2a2_W3_path_sampling_convergence_h2.m');";
outputDir = fullfile(moduleDir, 'output', ...
    'stage2a2_W3_path_sampling', 'run-002');
run001Dir = fullfile(moduleDir, 'output', ...
    'stage2a2_W3_path_sampling', 'run-001');
run001SummaryFile = fullfile(run001Dir, 'convergence_summary.csv');
configDir = fullfile(moduleDir, 'config');
intensityFile = fullfile(configDir, ...
    'lookahead_intensity_postlandfall_W3.csv');
locationFile = fullfile(configDir, ...
    'lookahead_location_postlandfall_W3.csv');
lfwFile = fullfile(configDir, ...
    'lookahead_lfw_postlandfall_W3.csv');
windowFile = fullfile(configDir, ...
    'lookahead_window_postlandfall_W3.csv');
nearInputFile = fullfile(rootDir, 'data', 'yuanqi', ...
    'near_stage_msp_input.mat');

NValues = [15000, 20000, 30000];
baseSeeds = 20260721:20260725;
mainSeed = 20260706;
aInitialValues = 2:6;
locInitialValues = 1:7;
lfwInitial = 0;
stageNames = ["W1","W2","W3"];
W = 3;
rowTolerance = 1e-10;
p95Threshold = 0.02;
worstThreshold = 0.05;
meanJointTvThreshold = 0.03;

requiredFiles = {intensityFile, locationFile, lfwFile, windowFile, ...
    nearInputFile, run001SummaryFile};
for ii = 1:numel(requiredFiles)
    if ~isfile(requiredFiles{ii})
        error('run_stage2a2_W3_path_sampling_convergence_h2:MissingInput', ...
            'Missing required input: %s', requiredFiles{ii});
    end
end

run001SnapshotBefore = snapshot_directory(run001Dir);
if isfolder(outputDir)
    existing = dir(outputDir);
    existing = existing(~ismember({existing.name},{'.','..'}));
    if ~isempty(existing)
        error('run_stage2a2_W3_path_sampling_convergence_h2:OutputExists', ...
            'Refusing to overwrite nonempty output directory: %s', outputDir);
    end
else
    mkdir(outputDir);
end

matrixFiles = {intensityFile, locationFile, lfwFile};
matrixHashBefore = strings(3,1);
matrixBytesBefore = cell(3,1);
for ii=1:3
    matrixHashBefore(ii)=sha256_file(matrixFiles{ii});
    matrixBytesBefore{ii}=read_file_bytes(matrixFiles{ii});
end

intensityTbl = readtable(intensityFile);
locationTbl = readtable(locationFile);
lfwTbl = readtable(lfwFile);
windowTbl = read_key_value_strings(windowFile);
require_vars(intensityTbl,{'from_a','to_a','prob'},intensityFile);
require_vars(locationTbl,{'from_loc_id','to_loc_id','prob'},locationFile);
require_vars(lfwTbl,{'from_lfw','to_lfw','prob'},lfwFile);
require_vars(windowTbl,{'key','value'},windowFile);

aStates = (1:6).';
locStates = (-2:10).';
lfwStates = (0:3).';
[PA,aRowError] = build_transition_matrix(intensityTbl,'from_a','to_a', ...
    aStates,rowTolerance);
[PLoc,locRowError] = build_transition_matrix(locationTbl, ...
    'from_loc_id','to_loc_id',locStates,rowTolerance);
[PLfw,lfwRowError] = build_transition_matrix(lfwTbl, ...
    'from_lfw','to_lfw',lfwStates,rowTolerance);

yBase = str2double(get_window_value(windowTbl,"y_base"));
Wstep = str2double(get_window_value(windowTbl,"Wstep"));
if ~isfinite(yBase) || ~isfinite(Wstep)
    error('run_stage2a2_W3_path_sampling_convergence_h2:BadWindowCoordinates', ...
        'y_base and Wstep must be finite numeric values.');
end

raw = load(nearInputFile,'NearStageInput');
if ~isfield(raw,'NearStageInput')
    error('run_stage2a2_W3_path_sampling_convergence_h2:MissingNearInput', ...
        'NearStageInput is missing from %s.',nearInputFile);
end
layout = build_h2_spatial_layout_preview(raw.NearStageInput);
coordConfig = struct('W',3,'halo_width',3);
locExtTbl = build_lookahead_location_ext_h2((1:7).',layout.locs,coordConfig);
locExtTbl = sortrows(locExtTbl,'loc_id');
if ~isequal(locExtTbl.loc_id,locStates) || any(~isfinite(locExtTbl.x_coord))
    error('run_stage2a2_W3_path_sampling_convergence_h2:BadLocCoordinates', ...
        'Extended loc coordinates must cover -2:10 with finite x values.');
end
xByLocIndex = double(locExtTbl.x_coord(:));

nA = numel(aStates);
nLoc = numel(locStates);
nLfw = numel(lfwStates);
nInitial = numel(aInitialValues)*numel(locInitialValues);
nN = numel(NValues);
nSeeds = numel(baseSeeds);
nStages = 3;
maxN = max(NValues);

initialRows = zeros(nInitial,3);
kk=0;
for a0=aInitialValues
    for loc0=locInitialValues
        kk=kk+1;
        initialRows(kk,:)=[a0,loc0,lfwInitial];
    end
end

%% Exact W1-W3 distributions by matrix multiplication.
exactA = cell(nInitial,nStages);
exactLoc = cell(nInitial,nStages);
exactLfw = cell(nInitial,nStages);
exactJoint = cell(nInitial,nStages);
exactRowCount = nInitial*nStages*(nA+nLoc+nLfw+nA*nLoc*nLfw);
exactRows = cell(exactRowCount,10);
er=0;
exactSumError=0;
for initIdx=1:nInitial
    a0=initialRows(initIdx,1);
    loc0=initialRows(initIdx,2);
    pA=zeros(1,nA); pA(a0)=1;
    pLoc=zeros(1,nLoc); pLoc(loc0-locStates(1)+1)=1;
    pLfw=zeros(1,nLfw); pLfw(lfwInitial+1)=1;
    for ss=1:nStages
        pA=pA*PA;
        pLoc=pLoc*PLoc;
        pLfw=pLfw*PLfw;
        joint=reshape(reshape(pA,[],1,1).*reshape(pLoc,1,[],1).* ...
            reshape(pLfw,1,1,[]),[],1);
        exactA{initIdx,ss}=pA(:);
        exactLoc{initIdx,ss}=pLoc(:);
        exactLfw{initIdx,ss}=pLfw(:);
        exactJoint{initIdx,ss}=joint;
        exactSumError=max(exactSumError,max(abs([sum(pA),sum(pLoc), ...
            sum(pLfw),sum(joint)]-1)));
        for ia=1:nA
            er=er+1;
            exactRows(er,:)={a0,loc0,lfwInitial,stageNames(ss),ss, ...
                "intensity",aStates(ia),NaN,NaN,pA(ia)};
        end
        for il=1:nLoc
            er=er+1;
            exactRows(er,:)={a0,loc0,lfwInitial,stageNames(ss),ss, ...
                "loc",NaN,locStates(il),NaN,pLoc(il)};
        end
        for iw=1:nLfw
            er=er+1;
            exactRows(er,:)={a0,loc0,lfwInitial,stageNames(ss),ss, ...
                "lfw",NaN,NaN,lfwStates(iw),pLfw(iw)};
        end
        for iw=1:nLfw
            for il=1:nLoc
                for ia=1:nA
                    idx=sub2ind([nA,nLoc,nLfw],ia,il,iw);
                    er=er+1;
                    exactRows(er,:)={a0,loc0,lfwInitial,stageNames(ss),ss, ...
                        "joint",aStates(ia),locStates(il),lfwStates(iw), ...
                        joint(idx)};
                end
            end
        end
    end
end
if er~=exactRowCount
    error('run_stage2a2_W3_path_sampling_convergence_h2:ExactRowCount', ...
        'Generated %d exact rows, expected %d.',er,exactRowCount);
end
exactStateDistributions=cell2table(exactRows,'VariableNames', ...
    {'a0','loc0','lfw0','stage','stage_index','distribution_type', ...
    'state_a','state_loc','state_lfw','exact_probability'});

%% Nested-prefix Monte Carlo convergence runs.
empA=cell(nN,nInitial,nStages,nSeeds);
empLoc=cell(nN,nInitial,nStages,nSeeds);
empLfw=cell(nN,nInitial,nStages,nSeeds);
empJoint=cell(nN,nInitial,nStages,nSeeds);
transitionCountsA=repmat({zeros(nA)},nN,1);
transitionCountsLoc=repmat({zeros(nLoc)},nN,1);
transitionCountsLfw=repmat({zeros(nLfw)},nN,1);
errorRows=cell(nN*nInitial*nStages*nSeeds*4,12);
rr=0;
for seedIdx=1:nSeeds
    baseSeed=baseSeeds(seedIdx);
    for initIdx=1:nInitial
        a0=initialRows(initIdx,1);
        loc0=initialRows(initIdx,2);
        derivedSeed=baseSeed+1000*initIdx;
        rng(derivedSeed,'twister');
        aPath=sample_chain(PA,a0,rand(maxN,W));
        locPath=sample_chain(PLoc,loc0-locStates(1)+1,rand(maxN,W));
        lfwPath=sample_chain(PLfw,lfwInitial+1,rand(maxN,W));
        for nIdx=1:nN
            N=NValues(nIdx);
            transitionCountsA{nIdx}=transitionCountsA{nIdx}+ ...
                count_chain_transitions(a0,aPath(1:N,:),nA);
            transitionCountsLoc{nIdx}=transitionCountsLoc{nIdx}+ ...
                count_chain_transitions(loc0-locStates(1)+1, ...
                locPath(1:N,:),nLoc);
            transitionCountsLfw{nIdx}=transitionCountsLfw{nIdx}+ ...
                count_chain_transitions(lfwInitial+1,lfwPath(1:N,:),nLfw);
            for ss=1:nStages
                dA=accumarray(aPath(1:N,ss),1,[nA,1])/N;
                dLoc=accumarray(locPath(1:N,ss),1,[nLoc,1])/N;
                dLfw=accumarray(lfwPath(1:N,ss),1,[nLfw,1])/N;
                jointIdx=sub2ind([nA,nLoc,nLfw],aPath(1:N,ss), ...
                    locPath(1:N,ss),lfwPath(1:N,ss));
                dJoint=accumarray(jointIdx,1,[nA*nLoc*nLfw,1])/N;
                empA{nIdx,initIdx,ss,seedIdx}=dA;
                empLoc{nIdx,initIdx,ss,seedIdx}=dLoc;
                empLfw{nIdx,initIdx,ss,seedIdx}=dLfw;
                empJoint{nIdx,initIdx,ss,seedIdx}=dJoint;
                names=["intensity","loc","lfw","joint"];
                empirical={dA,dLoc,dLfw,dJoint};
                exact={exactA{initIdx,ss},exactLoc{initIdx,ss}, ...
                    exactLfw{initIdx,ss},exactJoint{initIdx,ss}};
                supports=[nA,nLoc,nLfw,nA*nLoc*nLfw];
                for dd=1:4
                    [maxError,tv]=distribution_error(empirical{dd},exact{dd});
                    rr=rr+1;
                    errorRows(rr,:)={N,baseSeed,derivedSeed,a0,loc0,lfwInitial, ...
                        stageNames(ss),ss,names(dd),maxError,tv,supports(dd)};
                end
            end
        end
    end
end
samplingError=cell2table(errorRows,'VariableNames', ...
    {'N','base_seed','derived_seed','a0','loc0','lfw0','stage', ...
    'stage_index','distribution_type','max_abs_error', ...
    'total_variation_distance','support_size'});

%% Stability across the five requested base seeds.
stabilityRows=cell(nN*nInitial*nStages*4,15);
sr=0;
for nIdx=1:nN
    N=NValues(nIdx);
    for initIdx=1:nInitial
        a0=initialRows(initIdx,1);loc0=initialRows(initIdx,2);
        for ss=1:nStages
            names=["intensity","loc","lfw","joint"];
            stores={empA,empLoc,empLfw,empJoint};
            for dd=1:4
                distributions=cell(nSeeds,1);
                for seedIdx=1:nSeeds
                    store=stores{dd};
                    distributions{seedIdx}=store{nIdx,initIdx,ss,seedIdx};
                end
                [meanPairTv,maxPairTv,pairCount]=pairwise_tv(distributions);
                q=samplingError(samplingError.N==N & ...
                    samplingError.a0==a0 & samplingError.loc0==loc0 & ...
                    samplingError.stage_index==ss & ...
                    samplingError.distribution_type==names(dd),:);
                sr=sr+1;
                stabilityRows(sr,:)={N,a0,loc0,lfwInitial,stageNames(ss),ss, ...
                    names(dd),pairCount,meanPairTv,maxPairTv, ...
                    mean(q.max_abs_error),std(q.max_abs_error), ...
                    mean(q.total_variation_distance), ...
                    std(q.total_variation_distance),nSeeds};
            end
        end
    end
end
seedStability=cell2table(stabilityRows,'VariableNames', ...
    {'N','a0','loc0','lfw0','stage','stage_index','distribution_type', ...
    'seed_pair_count','mean_pairwise_tv','max_pairwise_tv', ...
    'mean_max_abs_error','std_max_abs_error','mean_tv_to_exact', ...
    'std_tv_to_exact','seed_count'});

%% Empirical transition frequencies versus the three configured matrices.
[transitionA,transitionSummaryA]=build_transition_frequency_tables( ...
    "intensity",PA,aStates,transitionCountsA,NValues);
[transitionLoc,transitionSummaryLoc]=build_transition_frequency_tables( ...
    "loc",PLoc,locStates,transitionCountsLoc,NValues);
[transitionLfw,transitionSummaryLfw]=build_transition_frequency_tables( ...
    "lfw",PLfw,lfwStates,transitionCountsLfw,NValues);
transitionFrequencyComparison=[transitionA;transitionLoc;transitionLfw];
transitionFrequencySummary=[transitionSummaryA;transitionSummaryLoc; ...
    transitionSummaryLfw];

%% Aggregate recommendation criteria.
summaryRows=cell(nN,13);
recommendedN=NaN;
for nIdx=1:nN
    N=NValues(nIdx);
    q=samplingError(samplingError.N==N,:);
    joint=q(q.distribution_type=="joint",:);
    stab=seedStability(seedStability.N==N,:);
    p95Error=percentile_nearest(q.max_abs_error,95);
    worstError=max(q.max_abs_error);
    meanJointTv=mean(joint.total_variation_distance);
    worstJointTv=max(joint.total_variation_distance);
    p95Pass=p95Error<=p95Threshold;
    worstPass=worstError<=worstThreshold;
    jointPass=meanJointTv<=meanJointTvThreshold;
    meetsAll=p95Pass&&worstPass&&jointPass;
    if isnan(recommendedN)&&meetsAll
        recommendedN=N;
    end
    summaryRows(nIdx,:)={N,height(q),p95Error,worstError,meanJointTv, ...
        worstJointTv,mean(stab.mean_pairwise_tv),max(stab.max_pairwise_tv), ...
        p95Pass,worstPass,jointPass,meetsAll,false};
end
convergenceSummary=cell2table(summaryRows,'VariableNames', ...
    {'N','error_observation_count','p95_max_abs_error', ...
    'worst_max_abs_error','mean_joint_tv','worst_joint_tv', ...
    'mean_seed_pairwise_tv','max_seed_pairwise_tv', ...
    'criterion_p95_pass','criterion_worst_pass', ...
    'criterion_mean_joint_tv_pass','meets_all_criteria','recommended'});
if ~isnan(recommendedN)
    convergenceSummary.recommended(convergenceSummary.N==recommendedN)=true;
end

run001Summary=readtable(run001SummaryFile);
requiredComparisonVars={'N','p95_max_abs_error','worst_max_abs_error', ...
    'mean_joint_tv','meets_all_criteria','recommended'};
require_vars(run001Summary,requiredComparisonVars,run001SummaryFile);
run001RunIds=repmat("run-001",height(run001Summary),1);
run002RunIds=repmat("run-002",height(convergenceSummary),1);
runComparison=table([run001RunIds;run002RunIds], ...
    [double(run001Summary.N);double(convergenceSummary.N)], ...
    [double(run001Summary.p95_max_abs_error); ...
    double(convergenceSummary.p95_max_abs_error)], ...
    [double(run001Summary.worst_max_abs_error); ...
    double(convergenceSummary.worst_max_abs_error)], ...
    [double(run001Summary.mean_joint_tv); ...
    double(convergenceSummary.mean_joint_tv)], ...
    [logical(run001Summary.meets_all_criteria); ...
    logical(convergenceSummary.meets_all_criteria)], ...
    [logical(run001Summary.recommended); ...
    logical(convergenceSummary.recommended)], ...
    'VariableNames',{'run_id','N','p95_max_abs_error', ...
    'worst_max_abs_error','mean_joint_tv','meets_all_criteria', ...
    'recommended'});

if isnan(recommendedN)
    transitionAuditN=max(NValues);
else
    transitionAuditN=recommendedN;
end
transitionAuditRows=transitionFrequencySummary( ...
    transitionFrequencySummary.N==transitionAuditN,:);
transitionMaxError=max(transitionAuditRows.max_abs_error);
transitionFrequencyPass=all(transitionAuditRows.all_from_states_observed) && ...
    all(transitionAuditRows.zero_probability_leak_count==0) && ...
    transitionMaxError<=p95Threshold;

%% Generate the main sample only if a recommendation exists.
mainPathFile=fullfile(outputDir,'main_path_samples.csv');
mainRowCount=0;
mainFileBytes=0;
mainFileHash="";
if ~isnan(recommendedN)
    rowsPerInitial=recommendedN;
    mainRows=zeros(nInitial*rowsPerInitial,23);
    mr=0;
    for initIdx=1:nInitial
        a0=initialRows(initIdx,1);loc0=initialRows(initIdx,2);
        derivedSeed=mainSeed+1000*initIdx;
        rng(derivedSeed,'twister');
        aPath=sample_chain(PA,a0,rand(rowsPerInitial,W));
        locPath=sample_chain(PLoc,loc0-locStates(1)+1, ...
            rand(rowsPerInitial,W));
        lfwPath=sample_chain(PLfw,lfwInitial+1,rand(rowsPerInitial,W));
        probability=path_probability(PA,PLoc,PLfw,a0, ...
            loc0-locStates(1)+1,lfwInitial+1,aPath,locPath,lfwPath);
        idx=(mr+1):(mr+rowsPerInitial);
        mainRows(idx,1)=a0;
        mainRows(idx,2)=loc0;
        mainRows(idx,3)=lfwInitial;
        mainRows(idx,4)=7;
        mainRows(idx,5)=(1:rowsPerInitial).';
        mainRows(idx,6)=mainSeed;
        mainRows(idx,7)=derivedSeed;
        mainRows(idx,8:10)=aPath;
        mainRows(idx,11:13)=locStates(locPath);
        mainRows(idx,14:16)=lfwStates(lfwPath);
        mainRows(idx,17:19)=xByLocIndex(locPath);
        mainRows(idx,20:22)=yBase+lfwStates(lfwPath)*Wstep;
        mainRows(idx,23)=probability;
        mr=mr+rowsPerInitial;
    end
    mainPathSamples=array2table(mainRows,'VariableNames', ...
        {'a0','loc0','lfw0','lf','path_id','base_random_seed', ...
        'derived_seed','a_W1','a_W2','a_W3','loc_W1','loc_W2','loc_W3', ...
        'lfw_W1','lfw_W2','lfw_W3','x_W1','x_W2','x_W3', ...
        'y_W1','y_W2','y_W3','path_probability'});
    writetable(mainPathSamples,mainPathFile);
    mainRowCount=height(mainPathSamples);
    clear mainPathSamples mainRows
    mainFileInfo=dir(mainPathFile);
    mainFileBytes=mainFileInfo.bytes;
    mainFileHash=sha256_file(mainPathFile);
end

%% Matrix protection and audit checklist.
matrixHashAfter=strings(3,1);
matricesUnchanged=true;
for ii=1:3
    matrixHashAfter(ii)=sha256_file(matrixFiles{ii});
    matricesUnchanged=matricesUnchanged && ...
        matrixHashAfter(ii)==matrixHashBefore(ii) && ...
        isequal(read_file_bytes(matrixFiles{ii}),matrixBytesBefore{ii});
end
run001SnapshotAfter=snapshot_directory(run001Dir);
run001Unchanged=isequal(run001SnapshotBefore,run001SnapshotAfter);
checkRows={};
checkRows=add_check(checkRows,"AUDIT-01","three matrices row-stochastic", ...
    max([aRowError,locRowError,lfwRowError])<=rowTolerance, ...
    max([aRowError,locRowError,lfwRowError]),rowTolerance);
checkRows=add_check(checkRows,"AUDIT-02","exact distributions sum to one", ...
    exactSumError<=rowTolerance,exactSumError,rowTolerance);
checkRows=add_check(checkRows,"AUDIT-03","requested N values evaluated", ...
    isequal(convergenceSummary.N,NValues.'), ...
    strjoin(string(convergenceSummary.N).',','),strjoin(string(NValues),','));
checkRows=add_check(checkRows,"AUDIT-04","requested base seeds evaluated", ...
    isequal(sort(unique(samplingError.base_seed)),baseSeeds.'), ...
    strjoin(string(sort(unique(samplingError.base_seed))).',','), ...
    strjoin(string(baseSeeds),','));
checkRows=add_check(checkRows,"AUDIT-05","all 35 initial states evaluated", ...
    height(unique(samplingError(:,{'a0','loc0','lfw0'}),'rows'))==35, ...
    height(unique(samplingError(:,{'a0','loc0','lfw0'}),'rows')),35);
checkRows=add_check(checkRows,"AUDIT-06","sampling errors finite and bounded", ...
    all(isfinite(samplingError.max_abs_error)) && ...
    all(isfinite(samplingError.total_variation_distance)) && ...
    all(samplingError.max_abs_error>=0 & samplingError.max_abs_error<=1) && ...
    all(samplingError.total_variation_distance>=0 & ...
    samplingError.total_variation_distance<=1+rowTolerance), ...
    "finite in [0,1]","finite in [0,1]");
checkRows=add_check(checkRows,"AUDIT-07","seed stability rows complete", ...
    height(seedStability)==nN*nInitial*nStages*4, ...
    height(seedStability),nN*nInitial*nStages*4);
checkRows=add_check(checkRows,"AUDIT-08","candidate matrices unchanged", ...
    matricesUnchanged,strjoin(matrixHashAfter,' | '), ...
    strjoin(matrixHashBefore,' | '));
checkRows=add_check(checkRows,"AUDIT-09","loc x coordinates finite", ...
    all(isfinite(xByLocIndex)),min(xByLocIndex),"all finite");
checkRows=add_check(checkRows,"AUDIT-10","lfw y mapping finite", ...
    all(isfinite(yBase+lfwStates*Wstep)), ...
    strjoin(compose('%.6f',yBase+lfwStates*Wstep).',','),"all finite");
checkRows=add_check(checkRows,"AUDIT-11", ...
    "main sample generated iff recommendation exists", ...
    (isnan(recommendedN)&&~isfile(mainPathFile)) || ...
    (~isnan(recommendedN)&&isfile(mainPathFile)&& ...
    mainRowCount==nInitial*recommendedN),mainRowCount, ...
    conditional_expected_rows(recommendedN,nInitial));
checkRows=add_check(checkRows,"AUDIT-12","run-001 output unchanged", ...
    run001Unchanged,height(run001SnapshotAfter),height(run001SnapshotBefore));
checkRows=add_check(checkRows,"AUDIT-13", ...
    "transition frequencies have no unsupported transitions", ...
    all(transitionAuditRows.zero_probability_leak_count==0), ...
    sum(transitionAuditRows.zero_probability_leak_count),0);
checkRows=add_check(checkRows,"AUDIT-14", ...
    "transition frequencies match configured matrices at audit N", ...
    transitionFrequencyPass,transitionMaxError,p95Threshold);
checkRows=add_check(checkRows,"AUDIT-15","run-001 and run-002 compared", ...
    all(ismember(["run-001","run-002"],unique(runComparison.run_id))) && ...
    height(runComparison)==height(run001Summary)+height(convergenceSummary), ...
    height(runComparison),height(run001Summary)+height(convergenceSummary));
auditChecklist=cell2table(checkRows,'VariableNames', ...
    {'check_id','description','passed','observed','expected','required'});
passCount=sum(auditChecklist.passed);
failCount=sum(~auditChecklist.passed);
auditStatus="PASS";
if failCount>0,auditStatus="FAIL";end

%% Write outputs.
writetable(convergenceSummary,fullfile(outputDir,'convergence_summary.csv'));
writetable(seedStability,fullfile(outputDir,'seed_stability.csv'));
writetable(exactStateDistributions, ...
    fullfile(outputDir,'exact_state_distributions.csv'));
writetable(samplingError, ...
    fullfile(outputDir,'sampling_error_by_initial_state.csv'));
writetable(transitionFrequencyComparison, ...
    fullfile(outputDir,'transition_frequency_comparison.csv'));
writetable(transitionFrequencySummary, ...
    fullfile(outputDir,'transition_frequency_summary.csv'));
writetable(runComparison,fullfile(outputDir,'run001_run002_comparison.csv'));
writetable(auditChecklist,fullfile(outputDir,'audit_checklist.csv'));
write_recommendation(fullfile(outputDir,'recommended_sample_size.txt'), ...
    recommendedN,convergenceSummary,p95Threshold,worstThreshold, ...
    meanJointTvThreshold,mainSeed);
write_main_path_info(fullfile(outputDir,'main_path_file_info.txt'), ...
    mainPathFile,mainRowCount,mainFileBytes,mainFileHash,recommendedN);
write_audit_summary(fullfile(outputDir,'audit_summary.md'),taskId,stepId, ...
    runId,runCommand,auditStatus,passCount,failCount,recommendedN, ...
    convergenceSummary,NValues,baseSeeds,mainSeed,yBase,Wstep, ...
    matricesUnchanged,mainRowCount,transitionAuditN,transitionAuditRows, ...
    run001Unchanged);
write_manifest(fullfile(outputDir,'run_manifest.txt'),taskId,stepId,runId, ...
    runCommand,auditStatus,passCount,failCount,matrixFiles,matrixHashBefore, ...
    matrixHashAfter,recommendedN,mainRowCount,mainFileBytes,mainFileHash, ...
    transitionAuditN,transitionMaxError,run001Unchanged,outputDir);

fprintf('\nStage2A2 W3 main path sampling convergence audit finished.\n');
fprintf('Status: %s; PASS=%d; FAIL=%d\n',auditStatus,passCount,failCount);
if isnan(recommendedN)
    fprintf('Recommended N: none of the tested candidates.\n');
else
    fprintf('Recommended N: %d per initial state.\n',recommendedN);
end
fprintf('Output directory: %s\n',outputDir);
if failCount>0
    error('run_stage2a2_W3_path_sampling_convergence_h2:AuditFailed', ...
        'Audit failed: %s',strjoin(auditChecklist.check_id(~auditChecklist.passed),', '));
end

function [P,maxRowError]=build_transition_matrix(tbl,fromName,toName,states,tol)
if height(unique(tbl(:,{fromName,toName}),'rows'))~=height(tbl)
    error('run_stage2a2_W3_path_sampling_convergence_h2:DuplicateTransition', ...
        'Duplicate transition keys in %s/%s.',fromName,toName);
end
if any(~isfinite(tbl.prob)) || any(tbl.prob<0) || any(tbl.prob>1)
    error('run_stage2a2_W3_path_sampling_convergence_h2:BadProbability', ...
        'Transition probabilities must be finite and in [0,1].');
end
P=zeros(numel(states));
for ii=1:height(tbl)
    i=find(states==tbl.(fromName)(ii),1);
    j=find(states==tbl.(toName)(ii),1);
    if isempty(i)||isempty(j)
        error('run_stage2a2_W3_path_sampling_convergence_h2:UnknownState', ...
            'Transition references a state outside the configured support.');
    end
    P(i,j)=tbl.prob(ii);
end
rowError=abs(sum(P,2)-1);
maxRowError=max(rowError);
if maxRowError>tol || any(sum(P,2)==0)
    error('run_stage2a2_W3_path_sampling_convergence_h2:BadRowSum', ...
        'Transition row sum error %.12g exceeds tolerance.',maxRowError);
end
end

function counts=count_chain_transitions(initialIndex,paths,stateCount)
counts=zeros(stateCount);
previous=repmat(initialIndex,size(paths,1),1);
for ss=1:size(paths,2)
    current=paths(:,ss);
    counts=counts+accumarray([previous,current],1, ...
        [stateCount,stateCount]);
    previous=current;
end
end

function [details,summary]=build_transition_frequency_tables( ...
    matrixName,P,states,countCells,NValues)
nN=numel(NValues);
nStates=numel(states);
detailRows=cell(nN*nStates*nStates,9);
summaryRows=cell(nN,9);
rr=0;
for nIdx=1:nN
    counts=double(countCells{nIdx});
    fromCounts=sum(counts,2);
    empirical=nan(size(P));
    observed=fromCounts>0;
    empirical(observed,:)=counts(observed,:)./fromCounts(observed);
    absError=abs(empirical-P);
    rowTv=0.5*sum(absError,2);
    zeroLeak=(P==0 & counts>0);
    for fromIdx=1:nStates
        for toIdx=1:nStates
            rr=rr+1;
            detailRows(rr,:)={NValues(nIdx),matrixName,states(fromIdx), ...
                states(toIdx),P(fromIdx,toIdx),counts(fromIdx,toIdx), ...
                fromCounts(fromIdx),empirical(fromIdx,toIdx), ...
                absError(fromIdx,toIdx)};
        end
    end
    finiteErrors=absError(isfinite(absError));
    finiteRowTv=rowTv(isfinite(rowTv));
    summaryRows(nIdx,:)={NValues(nIdx),matrixName,max(finiteErrors), ...
        percentile_nearest(finiteErrors,95),mean(finiteRowTv), ...
        max(finiteRowTv),min(fromCounts),all(observed),sum(zeroLeak,'all')};
end
details=cell2table(detailRows,'VariableNames', ...
    {'N','matrix','from_state','to_state','config_probability', ...
    'transition_count','from_count','sample_probability','abs_error'});
summary=cell2table(summaryRows,'VariableNames', ...
    {'N','matrix','max_abs_error','p95_abs_error','mean_row_tv', ...
    'max_row_tv','min_from_count','all_from_states_observed', ...
    'zero_probability_leak_count'});
end

function paths=sample_chain(P,initialIndex,uniforms)
[N,W]=size(uniforms);
paths=zeros(N,W);
current=repmat(initialIndex,N,1);
for ss=1:W
    next=zeros(N,1);
    for state=1:size(P,1)
        mask=current==state;
        if any(mask)
            cdf=cumsum(P(state,:));
            cdf(end)=1;
            next(mask)=sum(uniforms(mask,ss)>cdf,2)+1;
        end
    end
    paths(:,ss)=next;
    current=next;
end
end

function probability=path_probability(PA,PLoc,PLfw,a0,loc0,lfw0, ...
    aPath,locPath,lfwPath)
N=size(aPath,1);
probability=ones(N,1);
prevA=repmat(a0,N,1);prevLoc=repmat(loc0,N,1);prevLfw=repmat(lfw0,N,1);
for ss=1:3
    probability=probability.*PA(sub2ind(size(PA),prevA,aPath(:,ss))).* ...
        PLoc(sub2ind(size(PLoc),prevLoc,locPath(:,ss))).* ...
        PLfw(sub2ind(size(PLfw),prevLfw,lfwPath(:,ss)));
    prevA=aPath(:,ss);prevLoc=locPath(:,ss);prevLfw=lfwPath(:,ss);
end
end

function [maxError,tv]=distribution_error(empirical,exact)
delta=abs(double(empirical(:))-double(exact(:)));
maxError=max(delta);
tv=0.5*sum(delta);
end

function [meanTv,maxTv,count]=pairwise_tv(distributions)
values=[];
for ii=1:numel(distributions)-1
    for jj=ii+1:numel(distributions)
        values(end+1,1)=0.5*sum(abs(distributions{ii}-distributions{jj})); %#ok<AGROW>
    end
end
count=numel(values);meanTv=mean(values);maxTv=max(values);
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
elseif isnumeric(value)&&isscalar(value),s=string(sprintf('%.15g',value));
elseif isnumeric(value),s=strjoin(compose('%.15g',value(:).'),' | ');
else,s=string(value);end
end

function expected=conditional_expected_rows(recommendedN,nInitial)
if isnan(recommendedN),expected="no main sample";
else,expected=string(nInitial*recommendedN);end
end

function require_vars(tbl,names,fileName)
for ii=1:numel(names)
    if ~ismember(names{ii},tbl.Properties.VariableNames)
        error('run_stage2a2_W3_path_sampling_convergence_h2:MissingColumn', ...
            '%s is missing %s.',fileName,names{ii});
    end
end
end

function tbl=read_key_value_strings(fileName)
opts=delimitedTextImportOptions('NumVariables',2);
opts.DataLines=[2 Inf];opts.Delimiter=',';
opts.VariableNames={'key','value'};opts.VariableTypes={'string','string'};
opts.ExtraColumnsRule='ignore';opts.EmptyLineRule='read';
tbl=readtable(fileName,opts);
end

function value=get_window_value(tbl,key)
mask=tbl.key==key;
if sum(mask)~=1
    error('run_stage2a2_W3_path_sampling_convergence_h2:MissingWindowKey', ...
        'Expected exactly one window key %s.',key);
end
value=string(tbl.value(mask));
end

function snapshot=snapshot_directory(folder)
files=dir(fullfile(folder,'**','*'));
files=files(~[files.isdir]);
relativePaths=strings(numel(files),1);
sizes=zeros(numel(files),1);
hashes=strings(numel(files),1);
prefixLength=strlength(string(folder))+1;
for ii=1:numel(files)
    fullName=fullfile(files(ii).folder,files(ii).name);
    relativePaths(ii)=extractAfter(string(fullName),prefixLength);
    sizes(ii)=files(ii).bytes;
    hashes(ii)=sha256_file(fullName);
end
snapshot=table(relativePaths,sizes,hashes, ...
    'VariableNames',{'relative_path','bytes','sha256'});
snapshot=sortrows(snapshot,'relative_path');
end

function bytes=read_file_bytes(fileName)
fid=fopen(fileName,'rb');
if fid<0,error('run_stage2a2_W3_path_sampling_convergence_h2:OpenFailed', ...
        'Could not open %s.',fileName);end
cleanup=onCleanup(@()fclose(fid));
bytes=fread(fid,Inf,'*uint8');
end

function hash=sha256_file(fileName)
fid=fopen(fileName,'rb');
if fid<0,error('run_stage2a2_W3_path_sampling_convergence_h2:OpenFailed', ...
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

function write_main_path_info(fileName,mainPathFile,rowCount,fileBytes, ...
    fileHash,recommendedN)
fid=fopen(fileName,'w');if fid<0,error('main path info open failed');end
cleanup=onCleanup(@()fclose(fid));
if isnan(recommendedN)
    fprintf(fid,'main_path_generated=false\nrecommended_N=NONE\n');
else
    fprintf(fid,'main_path_generated=true\nrecommended_N=%d\n',recommendedN);
    fprintf(fid,'file=%s\nrows=%d\nsize_bytes=%d\nsha256=%s\n', ...
        mainPathFile,rowCount,fileBytes,fileHash);
end
end

function write_recommendation(fileName,recommendedN,summary,p95Limit, ...
    worstLimit,jointLimit,mainSeed)
fid=fopen(fileName,'w');if fid<0,error('recommendation open failed');end
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'Recommendation criteria:\n');
fprintf(fid,'p95_max_abs_error <= %.12g\n',p95Limit);
fprintf(fid,'worst_max_abs_error <= %.12g\n',worstLimit);
fprintf(fid,'mean_joint_tv <= %.12g\n\n',jointLimit);
for ii=1:height(summary)
    fprintf(fid,['N=%d: p95=%.12g, worst=%.12g, mean_joint_tv=%.12g, ' ...
        'meets_all=%d\n'],summary.N(ii),summary.p95_max_abs_error(ii), ...
        summary.worst_max_abs_error(ii),summary.mean_joint_tv(ii), ...
        summary.meets_all_criteria(ii));
end
if isnan(recommendedN)
    fprintf(fid,'\nrecommended_N=NONE\n');
    fprintf(fid,'No tested N satisfies all criteria; thresholds were not relaxed.\n');
else
    fprintf(fid,'\nrecommended_N=%d\n',recommendedN);
    fprintf(fid,'main_sample_seed=%d\n',mainSeed);
end
end

function write_audit_summary(fileName,taskId,stepId,runId,runCommand,status, ...
    passCount,failCount,recommendedN,summary,NValues,seeds,mainSeed,yBase, ...
    Wstep,matricesUnchanged,mainRowCount,transitionAuditN,transitionSummary, ...
    run001Unchanged)
fid=fopen(fileName,'w');if fid<0,error('summary open failed');end
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'# W3 Main Path Sampling Convergence Audit\n\n');
fprintf(fid,'- task_id: `%s`\n- step_id: `%s`\n- run_id: `%s`\n', ...
    taskId,stepId,runId);
fprintf(fid,'- status: `%s`\n- MATLAB command: `%s`\n',status,runCommand);
fprintf(fid,'- PASS count: %d\n- FAIL count: %d\n\n',passCount,failCount);
fprintf(fid,'## Design\n\n');
fprintf(fid,'- initial states: a0=2:6, loc0=1:7, lfw0=0 (35 states).\n');
fprintf(fid,'- N candidates: %s.\n',strjoin(string(NValues),', '));
fprintf(fid,'- convergence seeds: %s.\n',strjoin(string(seeds),', '));
fprintf(fid,'- each seed/state generates %d paths once; N candidates use nested prefixes.\n',max(NValues));
fprintf(fid,'- exact W1-W3 distributions use transition-matrix multiplication.\n\n');
fprintf(fid,'## Convergence\n\n');
for ii=1:height(summary)
    fprintf(fid,['- N=%d: p95 max error %.6g; worst max error %.6g; ' ...
        'mean joint TV %.6g; pass=%d.\n'],summary.N(ii), ...
        summary.p95_max_abs_error(ii),summary.worst_max_abs_error(ii), ...
        summary.mean_joint_tv(ii),summary.meets_all_criteria(ii));
end
fprintf(fid,'\n## Transition Frequency Check\n\n');
fprintf(fid,'- audit N: %d.\n',transitionAuditN);
for ii=1:height(transitionSummary)
    fprintf(fid,['- %s: max probability error %.6g; p95 error %.6g; ' ...
        'mean row TV %.6g; minimum from-state count %d.\n'], ...
        transitionSummary.matrix(ii),transitionSummary.max_abs_error(ii), ...
        transitionSummary.p95_abs_error(ii), ...
        transitionSummary.mean_row_tv(ii), ...
        transitionSummary.min_from_count(ii));
end
if isnan(recommendedN)
    fprintf(fid,'\n- recommended N: none; criteria were not relaxed.\n');
else
    fprintf(fid,'\n- recommended N: %d per initial state.\n',recommendedN);
    fprintf(fid,'- main sample seed: %d; main sample rows: %d.\n',mainSeed,mainRowCount);
end
fprintf(fid,'\n## Coordinates and Scope\n\n');
fprintf(fid,'- y = %.13f + lfw * %g.\n',yBase,Wstep);
fprintf(fid,'- x uses the existing NearStageInput loc layout and halo extrapolation.\n');
fprintf(fid,'- candidate matrices unchanged during run: %d.\n',matricesUnchanged);
fprintf(fid,'- run-001 output unchanged during run: %d.\n',run001Unchanged);
fprintf(fid,'- ordinary probability sampling only; no risk screening or tail enrichment.\n');
fprintf(fid,'- formal path generator, B3, WDRO, Gurobi, MSP, Foundation, and Persistence were not run.\n');
end

function write_manifest(fileName,taskId,stepId,runId,runCommand,status, ...
    passCount,failCount,matrixFiles,hashBefore,hashAfter,recommendedN, ...
    mainRowCount,mainFileBytes,mainFileHash,transitionAuditN, ...
    transitionMaxError,run001Unchanged,outputDir)
fid=fopen(fileName,'w');if fid<0,error('manifest open failed');end
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'task_id=%s\nstep_id=%s\nrun_id=%s\n',taskId,stepId,runId);
fprintf(fid,'run_time=%s\n',char(datetime('now','Format','yyyy-MM-dd HH:mm:ss Z')));
fprintf(fid,'MATLAB_command=%s\nstatus=%s\n',runCommand,status);
fprintf(fid,'pass_count=%d\nfail_count=%d\n',passCount,failCount);
fprintf(fid,'output_directory=%s\n',outputDir);
for ii=1:numel(matrixFiles)
    fprintf(fid,'matrix_file_%d=%s\n',ii,matrixFiles{ii});
    fprintf(fid,'matrix_sha256_before_%d=%s\n',ii,hashBefore(ii));
    fprintf(fid,'matrix_sha256_after_%d=%s\n',ii,hashAfter(ii));
end
if isnan(recommendedN),fprintf(fid,'recommended_N=NONE\n');
else,fprintf(fid,'recommended_N=%d\n',recommendedN);end
fprintf(fid,'main_sample_rows=%d\n',mainRowCount);
fprintf(fid,'main_sample_size_bytes=%d\n',mainFileBytes);
fprintf(fid,'main_sample_sha256=%s\n',mainFileHash);
fprintf(fid,'transition_audit_N=%d\n',transitionAuditN);
fprintf(fid,'transition_max_abs_error=%.15g\n',transitionMaxError);
fprintf(fid,'run001_unchanged=%d\n',run001Unchanged);
fprintf(fid,'risk_screening=false\ntail_enrichment=false\n');
fprintf(fid,'B3_run=false\nWDRO_run=false\nGurobi_run=false\nMSP_run=false\n');
end
