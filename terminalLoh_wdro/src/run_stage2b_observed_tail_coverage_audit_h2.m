clear; clc;

thisDir=fileparts(mfilename('fullpath'));
moduleDir=fileparts(thisDir);
rootDir=fileparts(moduleDir);
addpath(rootDir);
addpath(thisDir);
addpath(fullfile(rootDir,'fa_h2','fuzhu','terminalLoh_windmc'));

taskId="task-001";
stepId="03-stage2b-tail-candidate-design";
runId="run-001";
runCommand="cd('C:/Users/chaos/Desktop/biye/test/testH2_v2'); " + ...
    "run('terminalLoh_wdro/src/run_stage2b_observed_tail_coverage_audit_h2.m');";

sampleFile=fullfile(moduleDir,'output','stage2a2_W3_path_sampling', ...
    'run-002','main_path_samples.csv');
outputDir=fullfile(moduleDir,'output','stage2b_tail_candidate_design','run-001');
configDir=fullfile(moduleDir,'config');
intensityFile=fullfile(configDir,'lookahead_intensity_postlandfall_W3.csv');
locationFile=fullfile(configDir,'lookahead_location_postlandfall_W3.csv');
lfwFile=fullfile(configDir,'lookahead_lfw_postlandfall_W3.csv');
nearInputFile=fullfile(rootDir,'data','yuanqi','near_stage_msp_input.mat');
roadEdgeFile=fullfile(rootDir,'data','yuanqi','stage1_road_edges.csv');
foundationParameterFile=fullfile(moduleDir,'output', ...
    'stage2_foundation_fix_Hres3h_Wstep40_reaudit', ...
    'foundation_fix_parameter_snapshot.csv');
foundationRunFile=fullfile(thisDir,'run_stage2_foundation_fix_Hres3h_h2.m');
foundationEvaluatorFile=fullfile(thisDir,'evaluate_foundation_fix_chain_h2.m');

expectedRows=525000;
expectedRowsPerInitial=15000;
expectedInitialCount=35;
expectedSampleHash= ...
    "972a8c58620c09ac19cfcfb29e8d6a3ed2819ef1a22dbd522043436418eb805d";
lineThreshold=25;
roadThreshold=30;
rowTolerance=1e-10;
probabilityTolerance=1e-12;
metricNames=["grid_max_wind_mps","grid_cumulative_excess_mps", ...
    "road_max_wind_mps","road_cumulative_excess_mps", ...
    "grid_longest_consecutive_exceedance_windows", ...
    "road_longest_consecutive_exceedance_windows"];
quantileLevels=[0.95,0.99,0.995];

requiredFiles={sampleFile,intensityFile,locationFile,lfwFile,nearInputFile, ...
    roadEdgeFile,foundationParameterFile,foundationRunFile,foundationEvaluatorFile};
for ii=1:numel(requiredFiles)
    if ~isfile(requiredFiles{ii})
        error('run_stage2b_observed_tail_coverage_audit_h2:MissingInput', ...
            'Missing required input: %s',requiredFiles{ii});
    end
end
if isfolder(outputDir)
    existing=dir(outputDir);
    existing=existing(~ismember({existing.name},{'.','..'}));
    if ~isempty(existing)
        error('run_stage2b_observed_tail_coverage_audit_h2:OutputExists', ...
            'Refusing to overwrite nonempty output directory: %s',outputDir);
    end
else
    mkdir(outputDir);
end

sampleInfoBefore=dir(sampleFile);
sampleHashBefore=sha256_file(sampleFile);
matrixFiles={intensityFile,locationFile,lfwFile};
matrixHashBefore=strings(3,1);
for ii=1:3,matrixHashBefore(ii)=sha256_file(matrixFiles{ii});end

intensityTbl=readtable(intensityFile);
locationTbl=readtable(locationFile);
lfwTbl=readtable(lfwFile);
samples=readtable(sampleFile);
requiredSampleVars={'a0','loc0','lfw0','path_id','a_W1','a_W2','a_W3', ...
    'loc_W1','loc_W2','loc_W3','lfw_W1','lfw_W2','lfw_W3', ...
    'x_W1','x_W2','x_W3','y_W1','y_W2','y_W3','path_probability'};
require_vars(samples,requiredSampleVars,sampleFile);

aStates=(1:6).';locStates=(-2:10).';lfwStates=(0:3).';
[PA,aRowError]=build_transition_matrix(intensityTbl,'from_a','to_a', ...
    aStates,rowTolerance);
[PLoc,locRowError]=build_transition_matrix(locationTbl, ...
    'from_loc_id','to_loc_id',locStates,rowTolerance);
[PLfw,lfwRowError]=build_transition_matrix(lfwTbl, ...
    'from_lfw','to_lfw',lfwStates,rowTolerance);

parameterTbl=read_key_value_strings(foundationParameterFile);
require_vars(parameterTbl,{'key','value'},foundationParameterFile);
RmaxRef=get_numeric_parameter(parameterTbl,"Rmax_ref");
foundationRunText=string(fileread(foundationRunFile));
windDecayB=parse_source_assignment(foundationRunText,"config.windDecayB");
evaluatorText=regexprep(string(fileread(foundationEvaluatorFile)),'\s+','');
expectedMapText="map=[0;20.8;28.55;37.05;46.20;55.50];";
if ~contains(evaluatorText,expectedMapText)
    error('run_stage2b_observed_tail_coverage_audit_h2:VmaxMapMismatch', ...
        'Could not verify the accepted intensity-to-Vmax map.');
end
vmaxMap=[0;20.8;28.55;37.05;46.20;55.50];

raw=load(nearInputFile,'NearStageInput');
if ~isfield(raw,'NearStageInput')
    error('run_stage2b_observed_tail_coverage_audit_h2:MissingNearInput', ...
        'NearStageInput is missing from %s.',nearInputFile);
end
layout=build_h2_spatial_layout_preview(raw.NearStageInput);
[gridSeg,roadSeg]=build_segments(layout,roadEdgeFile);
[xByLoc,xCoordinateOk]=build_coordinate_map( ...
    [samples.loc_W1;samples.loc_W2;samples.loc_W3], ...
    [samples.x_W1;samples.x_W2;samples.x_W3],locStates);
[yByLfw,yCoordinateOk]=build_coordinate_map( ...
    [samples.lfw_W1;samples.lfw_W2;samples.lfw_W3], ...
    [samples.y_W1;samples.y_W2;samples.y_W3],lfwStates);

keyVars={'a0','loc0','lfw0','a_W1','a_W2','a_W3', ...
    'loc_W1','loc_W2','loc_W3','lfw_W1','lfw_W2','lfw_W3'};
[pathGroup,uniqueKeys]=findgroups(samples(:,keyVars));
frequency=splitapply(@numel,samples.path_id,pathGroup);
reportedProbabilityMin=splitapply(@min,samples.path_probability,pathGroup);
reportedProbabilityMax=splitapply(@max,samples.path_probability,pathGroup);
uniquePaths=[uniqueKeys,table(frequency,reportedProbabilityMin, ...
    reportedProbabilityMax)];
uniquePaths=sortrows(uniquePaths,keyVars);
initialGroup=findgroups(uniquePaths(:,{'a0','loc0','lfw0'}));
uniquePathId=zeros(height(uniquePaths),1);
for gg=1:max(initialGroup)
    mask=initialGroup==gg;
    uniquePathId(mask)=(1:sum(mask)).';
end
uniquePaths=addvars(uniquePaths,uniquePathId,'After','lfw0', ...
    'NewVariableNames','unique_path_id');
uniquePaths.empirical_mass=uniquePaths.frequency/expectedRowsPerInitial;
uniquePaths.path_probability=recompute_path_probability(uniquePaths, ...
    PA,PLoc,PLfw,locStates);
uniquePaths.path_probability_reported_range= ...
    uniquePaths.reportedProbabilityMax-uniquePaths.reportedProbabilityMin;
uniquePaths.path_probability_recomputed_error=max( ...
    abs(uniquePaths.path_probability-uniquePaths.reportedProbabilityMin), ...
    abs(uniquePaths.path_probability-uniquePaths.reportedProbabilityMax));

nA=numel(aStates);nLoc=numel(locStates);nLfw=numel(lfwStates);
nJoint=nA*nLoc*nLfw;
nGrid=height(gridSeg);nRoad=height(roadSeg);
lineWindByState=zeros(nJoint,nGrid);
roadWindByState=zeros(nJoint,nRoad);
stateRows=cell(nJoint,12);
for iw=1:nLfw
    for il=1:nLoc
        for ia=1:nA
            stateIndex=sub2ind([nA,nLoc,nLfw],ia,il,iw);
            x=xByLoc(il);y=yByLfw(iw);Vmax=vmaxMap(ia);
            lineDistance=compute_point_to_segment_distance_h2(x,y, ...
                gridSeg.x1,gridSeg.y1,gridSeg.x2,gridSeg.y2);
            roadDistance=compute_point_to_segment_distance_h2(x,y, ...
                roadSeg.x1,roadSeg.y1,roadSeg.x2,roadSeg.y2);
            lineWind=compute_wind_speed_radial_h2(lineDistance,Vmax, ...
                RmaxRef,windDecayB);
            roadWind=compute_wind_speed_radial_h2(roadDistance,Vmax, ...
                RmaxRef,windDecayB);
            lineWindByState(stateIndex,:)=lineWind(:).';
            roadWindByState(stateIndex,:)=roadWind(:).';
            stateRows(stateIndex,:)={ia,locStates(il),lfwStates(iw),x,y, ...
                Vmax,max(lineWind),sum(max(0,lineWind-lineThreshold)), ...
                max(roadWind),sum(max(0,roadWind-roadThreshold)), ...
                RmaxRef,windDecayB};
        end
    end
end
windRiskByState=cell2table(stateRows,'VariableNames', ...
    {'a','loc','lfw','x_coord','y_coord','Vmax_mps', ...
    'grid_max_wind_mps','grid_excess_sum_mps', ...
    'road_max_wind_mps','road_excess_sum_mps','Rmax_ref','wind_decay_B'});

idxW1=joint_state_index(uniquePaths.a_W1,uniquePaths.loc_W1, ...
    uniquePaths.lfw_W1,nA,nLoc,nLfw,locStates);
idxW2=joint_state_index(uniquePaths.a_W2,uniquePaths.loc_W2, ...
    uniquePaths.lfw_W2,nA,nLoc,nLfw,locStates);
idxW3=joint_state_index(uniquePaths.a_W3,uniquePaths.loc_W3, ...
    uniquePaths.lfw_W3,nA,nLoc,nLfw,locStates);

lineMaxByState=max(lineWindByState,[],2);
roadMaxByState=max(roadWindByState,[],2);
lineExcessByState=sum(max(0,lineWindByState-lineThreshold),2);
roadExcessByState=sum(max(0,roadWindByState-roadThreshold),2);
uniquePaths.grid_max_wind_mps=max([lineMaxByState(idxW1), ...
    lineMaxByState(idxW2),lineMaxByState(idxW3)],[],2);
uniquePaths.grid_cumulative_excess_mps=lineExcessByState(idxW1)+ ...
    lineExcessByState(idxW2)+lineExcessByState(idxW3);
uniquePaths.road_max_wind_mps=max([roadMaxByState(idxW1), ...
    roadMaxByState(idxW2),roadMaxByState(idxW3)],[],2);
uniquePaths.road_cumulative_excess_mps=roadExcessByState(idxW1)+ ...
    roadExcessByState(idxW2)+roadExcessByState(idxW3);

uniquePaths.grid_longest_consecutive_exceedance_windows=zeros(height(uniquePaths),1);
uniquePaths.road_longest_consecutive_exceedance_windows=zeros(height(uniquePaths),1);
chunkSize=20000;
for first=1:chunkSize:height(uniquePaths)
    last=min(height(uniquePaths),first+chunkSize-1);
    rows=first:last;
    uniquePaths.grid_longest_consecutive_exceedance_windows(rows)= ...
        longest_consecutive_exceedance(lineWindByState,idxW1(rows), ...
        idxW2(rows),idxW3(rows),lineThreshold);
    uniquePaths.road_longest_consecutive_exceedance_windows(rows)= ...
        longest_consecutive_exceedance(roadWindByState,idxW1(rows), ...
        idxW2(rows),idxW3(rows),roadThreshold);
end

initialStates=unique(samples(:,{'a0','loc0','lfw0'}),'rows');
initialStates=sortrows(initialStates,{'a0','loc0','lfw0'});
tailRows=cell(expectedInitialCount*numel(metricNames),11);
coverageRows=cell(expectedInitialCount,13);
highIndices=[];highMetrics=strings(0,1);highLevels=zeros(0,1); ...
    highThresholds=zeros(0,1);highValues=zeros(0,1);
paretoIndices=[];paretoMetrics=strings(0,1);paretoValues=zeros(0,1);
anyHigh99=false(height(uniquePaths),1);
anyHigh995=false(height(uniquePaths),1);
anyPareto=false(height(uniquePaths),1);
tr=0;
for gg=1:height(initialStates)
    a0=initialStates.a0(gg);loc0=initialStates.loc0(gg);lfw0=initialStates.lfw0(gg);
    sampleMask=samples.a0==a0 & samples.loc0==loc0 & samples.lfw0==lfw0;
    pathMask=uniquePaths.a0==a0 & uniquePaths.loc0==loc0 & ...
        uniquePaths.lfw0==lfw0;
    pathRows=find(pathMask);
    q=uniquePaths(pathMask,:);
    weights=q.empirical_mass;
    observedMass=sum(q.path_probability);
    legalA=count_legal_sequences(PA,a0,3);
    legalLoc=count_legal_sequences(PLoc,loc0-locStates(1)+1,3);
    legalLfw=count_legal_sequences(PLfw,lfw0+1,3);
    legalCombined=legalA*legalLoc*legalLfw;

    for mm=1:numel(metricNames)
        values=q.(char(metricNames(mm)));
        quantiles=weighted_quantile(values,weights,quantileLevels);
        tr=tr+1;
        tailRows(tr,:)={a0,loc0,lfw0,metricNames(mm),quantiles(1), ...
            quantiles(2),quantiles(3),sum(weights),height(q), ...
            expectedRowsPerInitial,"frequency/15000"};

        mask99=values>=quantiles(2);
        mask995=values>=quantiles(3);
        selected99=pathRows(mask99);selected995=pathRows(mask995);
        highIndices=[highIndices;selected99;selected995]; %#ok<AGROW>
        highMetrics=[highMetrics;repmat(metricNames(mm),sum(mask99)+sum(mask995),1)]; %#ok<AGROW>
        highLevels=[highLevels;repmat(0.99,sum(mask99),1); ...
            repmat(0.995,sum(mask995),1)]; %#ok<AGROW>
        highThresholds=[highThresholds;repmat(quantiles(2),sum(mask99),1); ...
            repmat(quantiles(3),sum(mask995),1)]; %#ok<AGROW>
        highValues=[highValues;values(mask99);values(mask995)]; %#ok<AGROW>
        anyHigh99(selected99)=true;anyHigh995(selected995)=true;

        paretoLocal=pareto_low_probability_high_risk(q.path_probability,values);
        selectedPareto=pathRows(paretoLocal);
        paretoIndices=[paretoIndices;selectedPareto]; %#ok<AGROW>
        paretoMetrics=[paretoMetrics;repmat(metricNames(mm),numel(selectedPareto),1)]; %#ok<AGROW>
        paretoValues=[paretoValues;values(paretoLocal)]; %#ok<AGROW>
        anyPareto(selectedPareto)=true;
    end

    coverageRows(gg,:)={a0,loc0,lfw0,sum(sampleMask),height(q), ...
        legalCombined,height(q)/legalCombined,observedMass,1-observedMass, ...
        sum(anyHigh99(pathRows)),sum(anyHigh995(pathRows)), ...
        sum(anyPareto(pathRows)),sum(weights)};
end
tailQuantiles=cell2table(tailRows,'VariableNames', ...
    {'a0','loc0','lfw0','risk_proxy','weighted_q95','weighted_q99', ...
    'weighted_q995','empirical_mass_sum','observed_unique_path_count', ...
    'sample_rows','weighting_mode'});
coverageSummary=cell2table(coverageRows,'VariableNames', ...
    {'a0','loc0','lfw0','sample_rows','observed_unique_path_count', ...
    'legal_path_count','path_count_coverage_share', ...
    'observed_theoretical_probability_mass', ...
    'unobserved_theoretical_probability_mass','high_exposure_any_q99_count', ...
    'high_exposure_any_q995_count','pareto_any_proxy_count', ...
    'empirical_mass_sum'});

highExposurePaths=uniquePaths(highIndices,:);
highExposurePaths=addvars(highExposurePaths,highMetrics,highLevels, ...
    highThresholds,highValues,'Before','a0','NewVariableNames', ...
    {'risk_proxy','quantile_level','quantile_threshold','risk_value'});
paretoCandidates=uniquePaths(paretoIndices,:);
paretoCandidates=addvars(paretoCandidates,paretoMetrics,paretoValues, ...
    'Before','a0','NewVariableNames',{'risk_proxy','risk_value'});

overallTailRows=cell(numel(metricNames),10);
for mm=1:numel(metricNames)
    q=tailQuantiles(tailQuantiles.risk_proxy==metricNames(mm),:);
    overallTailRows(mm,:)={metricNames(mm),height(q),mean(q.weighted_q95), ...
        min(q.weighted_q95),max(q.weighted_q95),mean(q.weighted_q99), ...
        min(q.weighted_q99),max(q.weighted_q99),mean(q.weighted_q995), ...
        mean(q.weighted_q995)};
end
overallTailSummary=cell2table(overallTailRows,'VariableNames', ...
    {'risk_proxy','initial_state_count','equal_state_mean_q95', ...
    'state_min_q95','state_max_q95','equal_state_mean_q99', ...
    'state_min_q99','state_max_q99','equal_state_mean_q995', ...
    'equal_state_mean_q995_check'});
overallTailSummary.equal_state_mean_q995_check=[];
overallTailSummary.state_min_q995=zeros(height(overallTailSummary),1);
overallTailSummary.state_max_q995=zeros(height(overallTailSummary),1);
for mm=1:numel(metricNames)
    q=tailQuantiles(tailQuantiles.risk_proxy==metricNames(mm),:);
    overallTailSummary.state_min_q995(mm)=min(q.weighted_q995);
    overallTailSummary.state_max_q995(mm)=max(q.weighted_q995);
end
overallTailSummary=movevars(overallTailSummary, ...
    {'state_min_q995','state_max_q995'},'After','equal_state_mean_q995');

overallCoverageSummary=table(expectedInitialCount,sum(coverageSummary.sample_rows), ...
    sum(coverageSummary.observed_unique_path_count), ...
    mean(coverageSummary.observed_unique_path_count), ...
    min(coverageSummary.observed_unique_path_count), ...
    max(coverageSummary.observed_unique_path_count), ...
    mean(coverageSummary.path_count_coverage_share), ...
    min(coverageSummary.path_count_coverage_share), ...
    max(coverageSummary.path_count_coverage_share), ...
    mean(coverageSummary.observed_theoretical_probability_mass), ...
    min(coverageSummary.observed_theoretical_probability_mass), ...
    max(coverageSummary.observed_theoretical_probability_mass), ...
    mean(coverageSummary.unobserved_theoretical_probability_mass), ...
    sum(anyHigh99),sum(anyHigh995),sum(anyPareto), ...
    "equal_weight_35_initial_states", ...
    'VariableNames',{'initial_state_count','sample_rows', ...
    'observed_unique_path_count_total','observed_unique_path_count_state_mean', ...
    'observed_unique_path_count_state_min','observed_unique_path_count_state_max', ...
    'path_count_coverage_equal_state_mean','path_count_coverage_state_min', ...
    'path_count_coverage_state_max', ...
    'theoretical_mass_coverage_equal_state_mean', ...
    'theoretical_mass_coverage_state_min','theoretical_mass_coverage_state_max', ...
    'unobserved_mass_equal_state_mean','high_exposure_any_q99_count_total', ...
    'high_exposure_any_q995_count_total','pareto_any_proxy_count_total', ...
    'overall_aggregation_mode'});

sampleInfoAfter=dir(sampleFile);
sampleHashAfter=sha256_file(sampleFile);
matrixHashAfter=strings(3,1);
for ii=1:3,matrixHashAfter(ii)=sha256_file(matrixFiles{ii});end
sampleUnchanged=sampleInfoBefore.bytes==sampleInfoAfter.bytes && ...
    sampleHashBefore==sampleHashAfter;
matricesUnchanged=isequal(matrixHashBefore,matrixHashAfter);
scriptFile=mfilename('fullpath');if ~endsWith(scriptFile,'.m'),scriptFile=scriptFile+".m";end
scriptText=fileread(scriptFile);
samplingCallHits=regexp(scriptText,'\<(rand|randn|randi|rng|sample_chain)\s*\(', ...
    'match');

riskFinite=all(isfinite(uniquePaths{:,cellstr(metricNames)}),'all') && ...
    all(uniquePaths{:,cellstr(metricNames)}>=0,'all');
coverageBounds=all(coverageSummary.path_count_coverage_share>=0 & ...
    coverageSummary.path_count_coverage_share<=1+rowTolerance) && ...
    all(coverageSummary.observed_theoretical_probability_mass>=0 & ...
    coverageSummary.observed_theoretical_probability_mass<=1+probabilityTolerance);
probabilityMassIdentity=max(abs(coverageSummary.observed_theoretical_probability_mass+ ...
    coverageSummary.unobserved_theoretical_probability_mass-1));

checkRows={};
checkRows=add_check(checkRows,"AUDIT-01","source sample row count", ...
    height(samples)==expectedRows,height(samples),expectedRows);
checkRows=add_check(checkRows,"AUDIT-02","source sample SHA-256", ...
    sampleHashBefore==expectedSampleHash,sampleHashBefore,expectedSampleHash);
checkRows=add_check(checkRows,"AUDIT-03","35 initial states", ...
    height(initialStates)==expectedInitialCount,height(initialStates),expectedInitialCount);
checkRows=add_check(checkRows,"AUDIT-04","15000 rows per initial state", ...
    all(coverageSummary.sample_rows==expectedRowsPerInitial), ...
    min(coverageSummary.sample_rows),expectedRowsPerInitial);
checkRows=add_check(checkRows,"AUDIT-05","unique frequencies preserve sample rows", ...
    sum(uniquePaths.frequency)==expectedRows,sum(uniquePaths.frequency),expectedRows);
checkRows=add_check(checkRows,"AUDIT-06","empirical mass sums to one by state", ...
    max(abs(coverageSummary.empirical_mass_sum-1))<=rowTolerance, ...
    max(abs(coverageSummary.empirical_mass_sum-1)),rowTolerance);
checkRows=add_check(checkRows,"AUDIT-07","path probability recomputation", ...
    max(uniquePaths.path_probability_recomputed_error)<=probabilityTolerance, ...
    max(uniquePaths.path_probability_recomputed_error),probabilityTolerance);
checkRows=add_check(checkRows,"AUDIT-08","legal path count covers observed paths", ...
    all(coverageSummary.legal_path_count>=coverageSummary.observed_unique_path_count), ...
    min(coverageSummary.legal_path_count-coverageSummary.observed_unique_path_count),0);
checkRows=add_check(checkRows,"AUDIT-09","coverage and theoretical mass bounded", ...
    coverageBounds,coverageBounds,true);
checkRows=add_check(checkRows,"AUDIT-10","observed plus unobserved mass equals one", ...
    probabilityMassIdentity<=probabilityTolerance,probabilityMassIdentity, ...
    probabilityTolerance);
checkRows=add_check(checkRows,"AUDIT-11","risk proxies finite and nonnegative", ...
    riskFinite,riskFinite,true);
checkRows=add_check(checkRows,"AUDIT-12","coordinates uniquely mapped", ...
    xCoordinateOk&&yCoordinateOk,xCoordinateOk&&yCoordinateOk,true);
checkRows=add_check(checkRows,"AUDIT-13","accepted risk parameters loaded", ...
    RmaxRef==40 && abs(windDecayB-0.6)<=eps,RmaxRef+windDecayB,40.6);
checkRows=add_check(checkRows,"AUDIT-14","transition matrices row-stochastic", ...
    max([aRowError,locRowError,lfwRowError])<=rowTolerance, ...
    max([aRowError,locRowError,lfwRowError]),rowTolerance);
checkRows=add_check(checkRows,"AUDIT-15","overall aggregation uses 35 equal states", ...
    overallCoverageSummary.overall_aggregation_mode== ...
    "equal_weight_35_initial_states", ...
    overallCoverageSummary.overall_aggregation_mode, ...
    "equal_weight_35_initial_states");
checkRows=add_check(checkRows,"AUDIT-16","no path_probability empirical weighting", ...
    all(uniquePaths.empirical_mass==uniquePaths.frequency/expectedRowsPerInitial), ...
    "frequency/15000","frequency/15000");
checkRows=add_check(checkRows,"AUDIT-17","no combined artificial risk score", ...
    ~any(contains(uniquePaths.Properties.VariableNames,'combined_score')), ...
    "no combined score","no combined score");
checkRows=add_check(checkRows,"AUDIT-18","audit script has no sampling calls", ...
    isempty(samplingCallHits),strjoin(string(samplingCallHits),','),"none");
checkRows=add_check(checkRows,"AUDIT-19","source sample unchanged", ...
    sampleUnchanged,sampleHashAfter,sampleHashBefore);
checkRows=add_check(checkRows,"AUDIT-20","candidate matrices unchanged", ...
    matricesUnchanged,strjoin(matrixHashAfter,' | '),strjoin(matrixHashBefore,' | '));
auditChecklist=cell2table(checkRows,'VariableNames', ...
    {'check_id','description','passed','observed','expected','required'});
passCount=sum(auditChecklist.passed);failCount=sum(~auditChecklist.passed);
auditStatus="PASS";if failCount>0,auditStatus="FAIL";end

riskParameterSnapshot=table(RmaxRef,windDecayB,lineThreshold,roadThreshold, ...
    "foundation_fix_parameter_snapshot.csv", ...
    "run_stage2_foundation_fix_Hres3h_h2.m", ...
    "evaluate_foundation_fix_chain_h2.m", ...
    "compute_point_to_segment_distance_h2", ...
    "compute_wind_speed_radial_h2", ...
    'VariableNames',{'Rmax_ref','wind_decay_B','grid_threshold_mps', ...
    'road_threshold_mps','Rmax_source','wind_decay_source','Vmax_map_source', ...
    'distance_function','wind_function'});

writetable(uniquePaths,fullfile(outputDir,'observed_unique_path_risk.csv'));
writetable(windRiskByState,fullfile(outputDir,'wind_risk_by_joint_state.csv'));
writetable(coverageSummary,fullfile(outputDir,'initial_state_coverage_summary.csv'));
writetable(tailQuantiles,fullfile(outputDir,'tail_quantiles_by_initial_state.csv'));
writetable(overallTailSummary,fullfile(outputDir,'overall_equal_state_tail_summary.csv'));
writetable(overallCoverageSummary,fullfile(outputDir, ...
    'overall_equal_state_coverage_summary.csv'));
writetable(highExposurePaths,fullfile(outputDir,'high_exposure_paths.csv'));
writetable(paretoCandidates,fullfile(outputDir,'pareto_candidate_paths.csv'));
writetable(riskParameterSnapshot,fullfile(outputDir,'risk_model_parameter_snapshot.csv'));
writetable(auditChecklist,fullfile(outputDir,'audit_checklist.csv'));
write_source_manifest(fullfile(outputDir,'source_sample_manifest.txt'), ...
    sampleFile,height(samples),sampleInfoAfter.bytes,sampleHashAfter, ...
    sum(uniquePaths.frequency),height(uniquePaths));
write_audit_summary(fullfile(outputDir,'audit_summary.md'),taskId,stepId,runId, ...
    runCommand,auditStatus,passCount,failCount,overallCoverageSummary, ...
    overallTailSummary,height(highExposurePaths),height(paretoCandidates), ...
    RmaxRef,windDecayB);
write_implementation_audit(fullfile(outputDir,'implementation_audit.md'), ...
    sampleFile,sampleHashAfter,RmaxRef,windDecayB,lineThreshold,roadThreshold, ...
    matricesUnchanged,sampleUnchanged);
write_run_manifest(fullfile(outputDir,'run_manifest.txt'),taskId,stepId,runId, ...
    runCommand,auditStatus,passCount,failCount,outputDir,sampleFile, ...
    sampleHashAfter,height(samples),height(uniquePaths), ...
    min(coverageSummary.observed_theoretical_probability_mass), ...
    max(coverageSummary.observed_theoretical_probability_mass), ...
    sum(anyHigh99),sum(anyHigh995),sum(anyPareto));

fprintf('\nObserved W3 tail-risk coverage audit finished.\n');
fprintf('Status: %s; PASS=%d; FAIL=%d\n',auditStatus,passCount,failCount);
fprintf('Observed unique paths: %d\n',height(uniquePaths));
fprintf('Theoretical mass coverage range: %.12g to %.12g\n', ...
    min(coverageSummary.observed_theoretical_probability_mass), ...
    max(coverageSummary.observed_theoretical_probability_mass));
fprintf('High exposure any q99/q99.5: %d / %d\n',sum(anyHigh99),sum(anyHigh995));
fprintf('Pareto candidates across any proxy: %d\n',sum(anyPareto));
fprintf('Output directory: %s\n',outputDir);
if failCount>0
    error('run_stage2b_observed_tail_coverage_audit_h2:AuditFailed', ...
        'Audit failed: %s',strjoin(auditChecklist.check_id(~auditChecklist.passed),', '));
end

function [P,maxRowError]=build_transition_matrix(tbl,fromName,toName,states,tol)
require_vars(tbl,{fromName,toName,'prob'},'transition table');
P=zeros(numel(states));
for ii=1:height(tbl)
    i=find(states==tbl.(fromName)(ii),1);j=find(states==tbl.(toName)(ii),1);
    if isempty(i)||isempty(j),error('Unknown transition state.');end
    P(i,j)=tbl.prob(ii);
end
if any(~isfinite(tbl.prob))||any(tbl.prob<0)||any(tbl.prob>1)
    error('Transition probabilities must be finite in [0,1].');
end
maxRowError=max(abs(sum(P,2)-1));
if maxRowError>tol,error('Transition rows do not sum to one.');end
end

function value=get_numeric_parameter(tbl,key)
mask=tbl.key==key;
if sum(mask)~=1,error('Expected one parameter %s.',key);end
value=str2double(tbl.value(mask));
if ~isfinite(value),error('Parameter %s is not finite.',key);end
end

function tbl=read_key_value_strings(fileName)
opts=delimitedTextImportOptions('NumVariables',2);
opts.DataLines=[2 Inf];opts.Delimiter=',';
opts.VariableNames={'key','value'};opts.VariableTypes={'string','string'};
opts.ExtraColumnsRule='ignore';opts.EmptyLineRule='read';
tbl=readtable(fileName,opts);
end

function value=parse_source_assignment(sourceText,assignmentName)
escaped=regexptranslate('escape',char(assignmentName));
token=regexp(char(sourceText),[escaped '\s*=\s*([0-9.]+)\s*;'], ...
    'tokens','once');
if isempty(token),error('Could not parse %s.',assignmentName);end
value=str2double(token{1});
end

function [gridSeg,roadSeg]=build_segments(layout,roadEdgeFile)
nodes=sortrows(layout.nodes,'node_id');lines=sortrows(layout.lines,'line_id');
gridSeg=table(lines.line_id,lines.from_node,lines.to_node, ...
    nodes.x_km(lines.from_node),nodes.y_km(lines.from_node), ...
    nodes.x_km(lines.to_node),nodes.y_km(lines.to_node), ...
    'VariableNames',{'line_id','from_node','to_node','x1','y1','x2','y2'});
roadRaw=readtable(roadEdgeFile);
require_vars(roadRaw,{'road_edge_id','from_node','to_node'},roadEdgeFile);
roadSeg=table(double(roadRaw.road_edge_id),double(roadRaw.from_node), ...
    double(roadRaw.to_node),nodes.x_km(double(roadRaw.from_node)), ...
    nodes.y_km(double(roadRaw.from_node)), ...
    nodes.x_km(double(roadRaw.to_node)),nodes.y_km(double(roadRaw.to_node)), ...
    'VariableNames',{'road_edge_id','from_node','to_node','x1','y1','x2','y2'});
end

function [mapping,ok]=build_coordinate_map(states,coordinates,expectedStates)
tbl=unique(table(double(states),double(coordinates), ...
    'VariableNames',{'state','coordinate'}),'rows');
mapping=nan(numel(expectedStates),1);ok=true;
for ii=1:numel(expectedStates)
    q=tbl(tbl.state==expectedStates(ii),:);
    ok=ok&&height(q)==1&&isfinite(q.coordinate);
    if height(q)==1,mapping(ii)=q.coordinate;end
end
ok=ok&&height(tbl)==numel(expectedStates)&&all(isfinite(mapping));
end

function probability=recompute_path_probability(T,PA,PLoc,PLfw,locStates)
probability=ones(height(T),1);prevA=T.a0;
prevLoc=T.loc0-locStates(1)+1;prevLfw=T.lfw0+1;
for ss=1:3
    currA=T.(sprintf('a_W%d',ss));
    currLoc=T.(sprintf('loc_W%d',ss))-locStates(1)+1;
    currLfw=T.(sprintf('lfw_W%d',ss))+1;
    probability=probability.*PA(sub2ind(size(PA),prevA,currA)).* ...
        PLoc(sub2ind(size(PLoc),prevLoc,currLoc)).* ...
        PLfw(sub2ind(size(PLfw),prevLfw,currLfw));
    prevA=currA;prevLoc=currLoc;prevLfw=currLfw;
end
end

function idx=joint_state_index(a,loc,lfw,nA,nLoc,nLfw,locStates)
idx=sub2ind([nA,nLoc,nLfw],a,loc-locStates(1)+1,lfw+1);
end

function longest=longest_consecutive_exceedance(windByState,i1,i2,i3,threshold)
b1=windByState(i1,:)>threshold;b2=windByState(i2,:)>threshold;
b3=windByState(i3,:)>threshold;
has1=any(b1|b2|b3,2);has2=any((b1&b2)|(b2&b3),2);has3=any(b1&b2&b3,2);
longest=double(has1)+double(has2)+double(has3);
end

function count=count_legal_sequences(P,initialIndex,W)
A=double(P>0);start=zeros(1,size(P,1));start(initialIndex)=1;
count=sum(start*(A^W));
end

function q=weighted_quantile(values,weights,levels)
[sortedValues,order]=sort(double(values(:)));sortedWeights=double(weights(order));
total=sum(sortedWeights);if total<=0,error('Nonpositive empirical weight.');end
cum=cumsum(sortedWeights)/total;q=zeros(size(levels));
for ii=1:numel(levels)
    pos=find(cum>=levels(ii),1,'first');q(ii)=sortedValues(pos);
end
end

function selected=pareto_low_probability_high_risk(probability,risk)
p=double(probability(:));r=double(risk(:));
[~,order]=sortrows([p,-r],[1,2]);selected=false(numel(p),1);
sortedP=p(order);sortedR=r(order);maxRiskBefore=-Inf;first=1;
while first<=numel(order)
    last=first;while last<numel(order)&&sortedP(last+1)==sortedP(first),last=last+1;end
    groupRisk=sortedR(first:last);groupMax=max(groupRisk);
    if groupMax>maxRiskBefore
        chosen=order(first-1+find(groupRisk==groupMax));
        selected(chosen)=true;
    end
    maxRiskBefore=max(maxRiskBefore,groupMax);first=last+1;
end
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
        error('%s is missing %s.',fileName,names{ii});
    end
end
end

function hash=sha256_file(fileName)
fid=fopen(fileName,'rb');if fid<0,error('Could not open %s.',fileName);end
cleanup=onCleanup(@()fclose(fid));md=java.security.MessageDigest.getInstance('SHA-256');
while true
    bytes=fread(fid,1024*1024,'*uint8');if isempty(bytes),break;end
    md.update(typecast(bytes,'int8'));
end
digest=typecast(md.digest(),'uint8');
hash=lower(string(reshape(dec2hex(digest,2).',1,[])));
end

function write_source_manifest(fileName,sourceFile,rows,bytes,hash,frequency,uniqueCount)
fid=fopen(fileName,'w');if fid<0,error('Manifest open failed.');end
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'source_file=%s\nsource_rows=%d\nsource_size_bytes=%d\n',sourceFile,rows,bytes);
fprintf(fid,'source_sha256=%s\naggregated_frequency=%d\n',hash,frequency);
fprintf(fid,'observed_unique_path_count=%d\nsource_preserved=true\n',uniqueCount);
fprintf(fid,'source_copied_to_git=false\nresampling=false\n');
fprintf(fid,'empirical_weight=frequency/15000\npath_probability_weighting=false\n');
end

function write_audit_summary(fileName,taskId,stepId,runId,runCommand,status, ...
    passCount,failCount,coverage,tailSummary,highRows,paretoRows,RmaxRef,B)
fid=fopen(fileName,'w');if fid<0,error('Summary open failed.');end
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'# Observed W3 Tail-Risk and Probability-Mass Coverage Audit\n\n');
fprintf(fid,'- task_id: `%s`\n- step_id: `%s`\n- run_id: `%s`\n',taskId,stepId,runId);
fprintf(fid,'- status: `%s`; PASS=%d; FAIL=%d.\n',status,passCount,failCount);
fprintf(fid,'- MATLAB command: `%s`\n\n',runCommand);
fprintf(fid,'## Coverage\n\n');
fprintf(fid,'- observed unique paths: %d.\n',coverage.observed_unique_path_count_total);
fprintf(fid,'- theoretical mass coverage range: %.12g to %.12g.\n', ...
    coverage.theoretical_mass_coverage_state_min,coverage.theoretical_mass_coverage_state_max);
fprintf(fid,'- path-count coverage range: %.12g to %.12g.\n\n', ...
    coverage.path_count_coverage_state_min,coverage.path_count_coverage_state_max);
fprintf(fid,'## Equal-State Tail Quantiles\n\n');
for ii=1:height(tailSummary)
    fprintf(fid,'- %s: q95=%.9g, q99=%.9g, q99.5=%.9g.\n', ...
        tailSummary.risk_proxy(ii),tailSummary.equal_state_mean_q95(ii), ...
        tailSummary.equal_state_mean_q99(ii),tailSummary.equal_state_mean_q995(ii));
end
fprintf(fid,'\n- high-exposure long rows: %d.\n- Pareto long rows: %d.\n',highRows,paretoRows);
fprintf(fid,'- risk model: Rmax_ref=%g, wind decay B=%g, point-to-segment distances.\n',RmaxRef,B);
fprintf(fid,'- empirical weights are frequency/15000; path_probability is not an empirical weight.\n');
fprintf(fid,'- no resampling, supplemental paths, B3, WDRO, Gurobi, or MSP.\n');
end

function write_implementation_audit(fileName,sampleFile,sampleHash,RmaxRef,B,lineV,roadV,matricesUnchanged,sampleUnchanged)
fid=fopen(fileName,'w');if fid<0,error('Implementation audit open failed.');end
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'# Implementation Audit\n\n');
fprintf(fid,'- source sample: `%s`\n- source SHA-256: `%s`\n',sampleFile,sampleHash);
fprintf(fid,'- source sample unchanged: %d\n- candidate matrices unchanged: %d\n',sampleUnchanged,matricesUnchanged);
fprintf(fid,'- Rmax_ref: %g; wind decay B: %g.\n',RmaxRef,B);
fprintf(fid,'- grid/road thresholds: %g/%g m/s.\n',lineV,roadV);
fprintf(fid,'- geometry: grid and road point-to-segment distance.\n');
fprintf(fid,'- path aggregation: exact W1-W3 state sequence within each initial state.\n');
fprintf(fid,'- empirical mass: frequency/15000.\n');
fprintf(fid,'- path_probability: recomputed theoretical audit field only.\n');
fprintf(fid,'- no artificial combined risk score.\n');
fprintf(fid,'- no resampling, supplemental paths, fixed-resistance B3, WDRO, Gurobi, or MSP.\n');
end

function write_run_manifest(fileName,taskId,stepId,runId,runCommand,status,passCount,failCount,outputDir,sampleFile,hash,rows,uniqueCount,massMin,massMax,high99,high995,pareto)
fid=fopen(fileName,'w');if fid<0,error('Run manifest open failed.');end
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'task_id=%s\nstep_id=%s\nrun_id=%s\n',taskId,stepId,runId);
fprintf(fid,'run_time=%s\nMATLAB_command=%s\n',char(datetime('now','Format','yyyy-MM-dd HH:mm:ss Z')),runCommand);
fprintf(fid,'status=%s\npass_count=%d\nfail_count=%d\n',status,passCount,failCount);
fprintf(fid,'output_directory=%s\nsource_file=%s\nsource_sha256=%s\n',outputDir,sampleFile,hash);
fprintf(fid,'source_rows=%d\nobserved_unique_paths=%d\n',rows,uniqueCount);
fprintf(fid,'theoretical_mass_coverage_min=%.15g\n',massMin);
fprintf(fid,'theoretical_mass_coverage_max=%.15g\n',massMax);
fprintf(fid,'high_exposure_any_q99=%d\nhigh_exposure_any_q995=%d\n',high99,high995);
fprintf(fid,'pareto_any_proxy=%d\nresampling=false\nsupplemental_paths=false\n',pareto);
fprintf(fid,'B3_run=false\nWDRO_run=false\nGurobi_run=false\nMSP_run=false\n');
end
