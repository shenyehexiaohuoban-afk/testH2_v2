clear; clc;

thisDir=fileparts(mfilename('fullpath'));
moduleDir=fileparts(thisDir);
rootDir=fileparts(moduleDir);
addpath(rootDir);
addpath(thisDir);
addpath(fullfile(rootDir,'fa_h2','fuzhu','terminalLoh_windmc'));

taskId="task-001";
stepId="03-stage2b-tail-candidate-design";
runId="run-003";
runCommand="cd('C:/Users/chaos/Desktop/biye/test/testH2_v2'); " + ...
    "run('terminalLoh_wdro/src/run_stage2b_search_unobserved_high_risk_paths_h2.m');";
run001Dir=fullfile(moduleDir,'output','stage2b_tail_candidate_design','run-001');
run002Dir=fullfile(moduleDir,'output','stage2b_tail_candidate_design','run-002');
outputDir=fullfile(moduleDir,'output','stage2b_tail_candidate_design','run-003');
configDir=fullfile(moduleDir,'config');

uniquePathFile=fullfile(run001Dir,'observed_unique_path_risk.csv');
quantileFile=fullfile(run001Dir,'tail_quantiles_by_initial_state.csv');
stateRiskReferenceFile=fullfile(run001Dir,'wind_risk_by_joint_state.csv');
riskParameterFile=fullfile(run001Dir,'risk_model_parameter_snapshot.csv');
observedCandidateFile=fullfile(run002Dir,'combined_tail_candidate_paths.csv');
intensityFile=fullfile(configDir,'lookahead_intensity_postlandfall_W3.csv');
locationFile=fullfile(configDir,'lookahead_location_postlandfall_W3.csv');
lfwFile=fullfile(configDir,'lookahead_lfw_postlandfall_W3.csv');
nearInputFile=fullfile(rootDir,'data','yuanqi','near_stage_msp_input.mat');
roadEdgeFile=fullfile(rootDir,'data','yuanqi','stage1_road_edges.csv');
mainSampleFile=fullfile(moduleDir,'output','stage2a2_W3_path_sampling', ...
    'run-002','main_path_samples.csv');

expectedMainRows=525000;
expectedMainHash= ...
    "972a8c58620c09ac19cfcfb29e8d6a3ed2819ef1a22dbd522043436418eb805d";
expectedUniqueRows=256884;
expectedObservedCandidateRows=35136;
expectedInitialStates=35;
riskMetrics=["grid_max_wind_mps","grid_cumulative_excess_mps", ...
    "road_max_wind_mps","road_cumulative_excess_mps"];
metricShort=["grid_max","grid_excess","road_max","road_excess"];
levelValues=[0.95,0.99,0.995];
levelColumns=["weighted_q95","weighted_q99","weighted_q995"];
equalityRelativeTolerance=1e-12;
riskMatchTolerance=1e-9;
rowTolerance=1e-10;
crosscheckStates=[2,1,0;2,4,0;4,1,0;4,4,0;6,4,0;6,7,0];

inputFiles={uniquePathFile,quantileFile,stateRiskReferenceFile, ...
    riskParameterFile,observedCandidateFile,intensityFile,locationFile, ...
    lfwFile,nearInputFile,roadEdgeFile,mainSampleFile};
for ii=1:numel(inputFiles)
    if ~isfile(inputFiles{ii})
        error('run_stage2b_search_unobserved_high_risk_paths_h2:MissingInput', ...
            'Missing required input: %s',inputFiles{ii});
    end
end
if isfolder(outputDir)
    existing=dir(outputDir);
    existing=existing(~ismember({existing.name},{'.','..'}));
    if ~isempty(existing)
        error('run_stage2b_search_unobserved_high_risk_paths_h2:OutputExists', ...
            'Refusing to overwrite nonempty output directory: %s',outputDir);
    end
else
    mkdir(outputDir);
end

inputHashesBefore=strings(numel(inputFiles),1);
inputBytesBefore=zeros(numel(inputFiles),1);
for ii=1:numel(inputFiles)
    info=dir(inputFiles{ii});inputBytesBefore(ii)=info.bytes;
    inputHashesBefore(ii)=sha256_file(inputFiles{ii});
end

observedUnique=readtable(uniquePathFile);
quantiles=readtable(quantileFile,'TextType','string');
stateRiskReference=readtable(stateRiskReferenceFile);
riskParameters=readtable(riskParameterFile,'TextType','string');
observedCandidates=readtable(observedCandidateFile);
intensityTbl=readtable(intensityFile);
locationTbl=readtable(locationFile);
lfwTbl=readtable(lfwFile);
roadEdges=readtable(roadEdgeFile);
raw=load(nearInputFile,'NearStageInput');
if ~isfield(raw,'NearStageInput')
    error('run_stage2b_search_unobserved_high_risk_paths_h2:MissingNearInput', ...
        'NearStageInput is missing from %s.',nearInputFile);
end
[mainRows,mainFields]=count_csv_rows_and_fields(mainSampleFile);

pathKeyVars={'a0','loc0','lfw0','a_W1','a_W2','a_W3', ...
    'loc_W1','loc_W2','loc_W3','lfw_W1','lfw_W2','lfw_W3'};
require_vars(observedUnique,[pathKeyVars,{'unique_path_id','path_probability'}, ...
    cellstr(riskMetrics)],uniquePathFile);
require_vars(quantiles,{'a0','loc0','lfw0','risk_proxy', ...
    'weighted_q95','weighted_q99','weighted_q995'},quantileFile);
require_vars(stateRiskReference,{'a','loc','lfw','x_coord','y_coord', ...
    'Vmax_mps','grid_max_wind_mps','grid_excess_sum_mps', ...
    'road_max_wind_mps','road_excess_sum_mps'},stateRiskReferenceFile);
require_vars(riskParameters,{'Rmax_ref','wind_decay_B','grid_threshold_mps', ...
    'road_threshold_mps'},riskParameterFile);
require_vars(observedCandidates,[pathKeyVars,{'quantile_level'}], ...
    observedCandidateFile);
require_vars(intensityTbl,{'from_a','to_a','prob'},intensityFile);
require_vars(locationTbl,{'from_loc_id','to_loc_id','prob'},locationFile);
require_vars(lfwTbl,{'from_lfw','to_lfw','prob'},lfwFile);
require_vars(roadEdges,{'road_edge_id','from_node','to_node'},roadEdgeFile);

print_table_input(uniquePathFile,observedUnique);
print_table_input(quantileFile,quantiles);
print_table_input(stateRiskReferenceFile,stateRiskReference);
print_table_input(riskParameterFile,riskParameters);
print_table_input(observedCandidateFile,observedCandidates);
print_table_input(intensityFile,intensityTbl);
print_table_input(locationFile,locationTbl);
print_table_input(lfwFile,lfwTbl);
print_table_input(roadEdgeFile,roadEdges);
fprintf('INPUT|path=%s|rows=1|fields=%s\n',nearInputFile, ...
    strjoin(string(fieldnames(raw.NearStageInput)).',','));
fprintf('INPUT|path=%s|rows=%d|fields=%s\n',mainSampleFile,mainRows, ...
    strjoin(mainFields,','));
fprintf('FUNCTION|wind=%s\n',which('compute_wind_speed_radial_h2'));
fprintf('FUNCTION|distance=%s\n',which('compute_point_to_segment_distance_h2'));
fprintf('BEGIN_SEARCH\n');

aStates=(1:6).';locStates=(-2:10).';lfwStates=(0:3).';
[PA,aRowError]=build_transition_matrix(intensityTbl,'from_a','to_a',aStates,rowTolerance);
[PLoc,locRowError]=build_transition_matrix(locationTbl, ...
    'from_loc_id','to_loc_id',locStates,rowTolerance);
[PLfw,lfwRowError]=build_transition_matrix(lfwTbl, ...
    'from_lfw','to_lfw',lfwStates,rowTolerance);
nA=numel(aStates);nLoc=numel(locStates);nLfw=numel(lfwStates);nJoint=nA*nLoc*nLfw;
[outNext,outProb]=build_joint_outgoing(PA,PLoc,PLfw,nA,nLoc,nLfw);
initialStates=unique(observedUnique(:,{'a0','loc0','lfw0'}),'rows');
initialStates=sortrows(initialStates,{'a0','loc0','lfw0'});
initialIndices=joint_index(initialStates.a0,initialStates.loc0, ...
    initialStates.lfw0,nA,nLoc,nLfw,locStates);
reachableMask=reachable_states(initialIndices,outNext,3,nJoint);
reachableStateCount=sum(reachableMask);

RmaxRef=double(riskParameters.Rmax_ref(1));
windDecayB=double(riskParameters.wind_decay_B(1));
gridThreshold=double(riskParameters.grid_threshold_mps(1));
roadThreshold=double(riskParameters.road_threshold_mps(1));
layout=build_h2_spatial_layout_preview(raw.NearStageInput);
[gridSeg,roadSeg]=build_segments(layout,roadEdges);
[stateRisk,stateRiskCache,stateRiskMaxError]=build_state_risk_cache( ...
    stateRiskReference,reachableMask,gridSeg,roadSeg,RmaxRef,windDecayB, ...
    gridThreshold,roadThreshold,nA,nLoc,nLfw,locStates);

[countDP,maxDP,sumDP]=build_backward_bounds(outNext,stateRisk,3);
observedUnique.path_code=encode_path_table(observedUnique,nJoint,nA,nLoc,nLfw,locStates);
observedCandidates.path_code=encode_path_table(observedCandidates,nJoint,nA,nLoc,nLfw,locStates);
quantiles=quantiles(ismember(quantiles.risk_proxy,riskMetrics),:);

stateProxyRows=cell(expectedInitialStates*numel(riskMetrics)*numel(levelValues),17);
combinedStateRows=cell(expectedInitialStates*numel(levelValues),13);
pruningRows=cell(expectedInitialStates,10);
reproductionRows=cell(expectedInitialStates*numel(levelValues),9);
crosscheckRows={};
unobservedFile=fullfile(outputDir,'unobserved_high_risk_legal_paths.csv');
paretoFile=fullfile(outputDir,'unobserved_pareto_paths.csv');
firstUnobservedWrite=true;firstParetoWrite=true;
sr=0;csr=0;pr=0;rr=0;
totalLegalPaths=0;totalExpandedPaths=0;totalPrunedCandidatePaths=0;
totalFullCrosscheckPaths=0;fullEnumerationLeakCount=0;fullEnumerationExtraCount=0;
candidateNestedPass=true;combinedNestedPass=true;

for ss=1:height(initialStates)
    a0=initialStates.a0(ss);loc0=initialStates.loc0(ss);lfw0=initialStates.lfw0(ss);
    initialIndex=initialIndices(ss);
    thresholdMatrix=build_threshold_matrix(quantiles,a0,loc0,lfw0, ...
        riskMetrics,levelColumns);
    search=search_initial_state(initialIndex,thresholdMatrix,outNext,outProb, ...
        stateRisk,maxDP,sumDP,nJoint,true,equalityRelativeTolerance);
    legalPaths=countDP(initialIndex,4);
    observedState=observedUnique(observedUnique.a0==a0 & ...
        observedUnique.loc0==loc0 & observedUnique.lfw0==lfw0,:);
    observedCode=observedState.path_code;
    search.observed=ismember(search.path_code,observedCode);
    search.pareto=false(size(search.target_flags));
    for tt=1:size(search.target_flags,2)
        mask=search.target_flags(:,tt);
        search.pareto(mask,tt)=pareto_low_probability_high_risk( ...
            search.path_probability(mask),search.risk(mask,target_metric(tt)));
    end

    for mm=1:numel(riskMetrics)
        proxyFlags=search.target_flags(:,arrayfun(@(ll)target_column(mm,ll),1:3));
        candidateNestedPass=candidateNestedPass && ...
            all(~proxyFlags(:,3)|proxyFlags(:,2)) && ...
            all(~proxyFlags(:,2)|proxyFlags(:,1));
    end
    combinedFlags=false(size(search.target_flags,1),numel(levelValues));
    for ll=1:numel(levelValues)
        cols=arrayfun(@(mm)target_column(mm,ll),1:numel(riskMetrics));
        combinedFlags(:,ll)=any(search.target_flags(:,cols),2);
    end
    combinedNestedPass=combinedNestedPass && ...
        all(~combinedFlags(:,3)|combinedFlags(:,2)) && ...
        all(~combinedFlags(:,2)|combinedFlags(:,1));

    totalLegalPaths=totalLegalPaths+legalPaths;
    totalExpandedPaths=totalExpandedPaths+search.expanded_paths;
    totalPrunedCandidatePaths=totalPrunedCandidatePaths+size(search.path_states,1);
    pr=pr+1;
    pruningRows(pr,:)={a0,loc0,lfw0,legalPaths,search.expanded_paths, ...
        legalPaths-search.expanded_paths,1-search.expanded_paths/legalPaths, ...
        size(search.path_states,1),sum(search.observed),sum(~search.observed)};

    for mm=1:numel(riskMetrics)
        for ll=1:numel(levelValues)
            tt=target_column(mm,ll);
            candidate=search.target_flags(:,tt);
            pareto=search.pareto(:,tt);
            observed=candidate&search.observed;unobserved=candidate&~search.observed;
            observedPareto=pareto&search.observed;unobservedPareto=pareto&~search.observed;
            sr=sr+1;
            stateProxyRows(sr,:)={a0,loc0,lfw0,riskMetrics(mm),levelValues(ll), ...
                thresholdMatrix(mm,ll),sum(candidate),sum(observed),sum(unobserved), ...
                sum(pareto),sum(observedPareto),sum(unobservedPareto), ...
                sum(search.path_probability(candidate)), ...
                sum(search.path_probability(unobserved)),search.expanded_paths, ...
                legalPaths,"probability_min_risk_max"};
        end
    end

    for ll=1:numel(levelValues)
        cols=arrayfun(@(mm)target_column(mm,ll),1:numel(riskMetrics));
        candidate=any(search.target_flags(:,cols),2);
        pareto=any(search.pareto(:,cols),2);
        unobserved=candidate&~search.observed;
        unobservedPareto=pareto&~search.observed;
        csr=csr+1;
        combinedStateRows(csr,:)={a0,loc0,lfw0,levelValues(ll),sum(candidate), ...
            sum(candidate&search.observed),sum(unobserved),sum(pareto), ...
            sum(pareto&search.observed),sum(unobservedPareto), ...
            sum(search.path_probability(unobserved)),legalPaths,search.expanded_paths};

        run002State=observedCandidates(observedCandidates.a0==a0 & ...
            observedCandidates.loc0==loc0 & observedCandidates.lfw0==lfw0 & ...
            abs(observedCandidates.quantile_level-levelValues(ll))<1e-12,:);
        reproducedCodes=search.path_code(candidate&search.observed);
        missingRun002=setdiff(run002State.path_code,reproducedCodes);
        extraObserved=setdiff(reproducedCodes,run002State.path_code);
        rr=rr+1;
        reproductionRows(rr,:)={a0,loc0,lfw0,levelValues(ll), ...
            height(run002State),numel(reproducedCodes),numel(missingRun002), ...
            numel(extraObserved),isempty(missingRun002)&&isempty(extraObserved)};

        if any(unobserved)
            T=build_path_output_table(search,unobserved,a0,loc0,lfw0, ...
                levelValues(ll),cols,nA,nLoc,nLfw,locStates,false);
            append_table(unobservedFile,T,firstUnobservedWrite);
            firstUnobservedWrite=false;
        end
        if any(unobservedPareto)
            T=build_path_output_table(search,unobservedPareto,a0,loc0,lfw0, ...
                levelValues(ll),cols,nA,nLoc,nLfw,locStates,true);
            append_table(paretoFile,T,firstParetoWrite);
            firstParetoWrite=false;
        end
    end

    if ismember([a0,loc0,lfw0],crosscheckStates,'rows')
        full=search_initial_state(initialIndex,thresholdMatrix,outNext,outProb, ...
            stateRisk,maxDP,sumDP,nJoint,false,equalityRelativeTolerance);
        totalFullCrosscheckPaths=totalFullCrosscheckPaths+full.expanded_paths;
        for mm=1:numel(riskMetrics)
            for ll=1:numel(levelValues)
                tt=target_column(mm,ll);
                prunedCodes=search.path_code(search.target_flags(:,tt));
                fullCodes=full.path_code(full.target_flags(:,tt));
                missing=setdiff(fullCodes,prunedCodes);extra=setdiff(prunedCodes,fullCodes);
                fullEnumerationLeakCount=fullEnumerationLeakCount+numel(missing);
                fullEnumerationExtraCount=fullEnumerationExtraCount+numel(extra);
                crosscheckRows(end+1,:)={a0,loc0,lfw0,riskMetrics(mm), ...
                    levelValues(ll),legalPaths,full.expanded_paths, ...
                    numel(fullCodes),numel(prunedCodes),numel(missing), ...
                    numel(extra),isempty(missing)&&isempty(extra)}; %#ok<AGROW>
            end
        end
    end
end

stateProxySummary=cell2table(stateProxyRows,'VariableNames', ...
    {'a0','loc0','lfw0','risk_proxy','quantile_level','risk_threshold', ...
    'legal_high_risk_path_count','observed_high_risk_path_count', ...
    'unobserved_high_risk_path_count','pareto_path_count', ...
    'observed_pareto_path_count','unobserved_pareto_path_count', ...
    'legal_high_risk_theoretical_mass','unobserved_high_risk_theoretical_mass', ...
    'expanded_path_count','legal_path_count','pareto_objectives'});
combinedStateSummary=cell2table(combinedStateRows,'VariableNames', ...
    {'a0','loc0','lfw0','quantile_level','legal_high_risk_path_count', ...
    'observed_high_risk_path_count','unobserved_high_risk_path_count', ...
    'pareto_path_count','observed_pareto_path_count', ...
    'unobserved_pareto_path_count','unobserved_high_risk_theoretical_mass', ...
    'legal_path_count','expanded_path_count'});
pruningDiagnostics=cell2table(pruningRows,'VariableNames', ...
    {'a0','loc0','lfw0','legal_path_count','expanded_complete_path_count', ...
    'pruned_complete_path_count','pruning_ratio','stored_candidate_path_count', ...
    'stored_observed_candidate_count','stored_unobserved_candidate_count'});
observedCandidateReproduction=cell2table(reproductionRows,'VariableNames', ...
    {'a0','loc0','lfw0','quantile_level','run002_observed_candidate_count', ...
    'search_observed_candidate_count','missing_run002_count', ...
    'extra_observed_count','exact_match'});
enumerationCrosscheck=cell2table(crosscheckRows,'VariableNames', ...
    {'a0','loc0','lfw0','risk_proxy','quantile_level','legal_path_count', ...
    'full_expanded_path_count','full_candidate_count','pruned_candidate_count', ...
    'missing_from_pruned_count','extra_in_pruned_count','exact_match'});

overallLevelRows=cell(numel(levelValues),11);
for ll=1:numel(levelValues)
    q=combinedStateSummary(abs(combinedStateSummary.quantile_level-levelValues(ll))<1e-12,:);
    overallLevelRows(ll,:)={levelValues(ll),height(q),sum(q.legal_high_risk_path_count), ...
        sum(q.observed_high_risk_path_count),sum(q.unobserved_high_risk_path_count), ...
        sum(q.pareto_path_count),sum(q.observed_pareto_path_count), ...
        sum(q.unobserved_pareto_path_count), ...
        mean(q.unobserved_high_risk_theoretical_mass), ...
        "four_proxy_union","equal_weight_35_initial_states"};
end
overallLevelSummary=cell2table(overallLevelRows,'VariableNames', ...
    {'quantile_level','initial_state_count','legal_high_risk_path_count_total', ...
    'observed_high_risk_path_count_total','unobserved_high_risk_path_count_total', ...
    'pareto_path_count_total','observed_pareto_path_count_total', ...
    'unobserved_pareto_path_count_total', ...
    'equal_state_mean_unobserved_theoretical_mass','combination_mode', ...
    'overall_aggregation_mode'});

zeroRiskSelectedCount=count_zero_risk_in_outputs(unobservedFile);
mainHashAfter=sha256_file(mainSampleFile);
mainRowsAfter=count_csv_rows_and_fields(mainSampleFile);mainRowsAfter=mainRowsAfter(1);
inputHashesAfter=strings(numel(inputFiles),1);inputBytesAfter=zeros(numel(inputFiles),1);
for ii=1:numel(inputFiles)
    info=dir(inputFiles{ii});inputBytesAfter(ii)=info.bytes;
    inputHashesAfter(ii)=sha256_file(inputFiles{ii});
end
inputsUnchanged=isequal(inputHashesBefore,inputHashesAfter) && ...
    isequal(inputBytesBefore,inputBytesAfter);
scriptFile=mfilename('fullpath');if ~endsWith(scriptFile,'.m'),scriptFile=scriptFile+".m";end
scriptText=string(fileread(scriptFile));
samplingHits=regexp(char(scriptText),'\<(rand|randn|randi|rng|sample_chain)\s*\(', ...
    'match');

reproductionPass=all(observedCandidateReproduction.exact_match);
crosscheckPass=all(enumerationCrosscheck.exact_match) && ...
    fullEnumerationLeakCount==0 && fullEnumerationExtraCount==0;
riskCachePass=stateRiskMaxError<=riskMatchTolerance;
mainSamplePass=mainRowsAfter==expectedMainRows && mainHashAfter==expectedMainHash;

checkRows={};
checkRows=add_check(checkRows,"AUDIT-01","input files printed and validated", ...
    true,numel(inputFiles),numel(inputFiles));
checkRows=add_check(checkRows,"AUDIT-02","run-001 unique path rows", ...
    height(observedUnique)==expectedUniqueRows,height(observedUnique),expectedUniqueRows);
checkRows=add_check(checkRows,"AUDIT-03","run-002 observed candidate rows", ...
    height(observedCandidates)==expectedObservedCandidateRows, ...
    height(observedCandidates),expectedObservedCandidateRows);
checkRows=add_check(checkRows,"AUDIT-04","35 initial states", ...
    height(initialStates)==expectedInitialStates,height(initialStates),expectedInitialStates);
checkRows=add_check(checkRows,"AUDIT-05","joint-state wind cache matches run-001", ...
    riskCachePass,stateRiskMaxError,riskMatchTolerance);
checkRows=add_check(checkRows,"AUDIT-06","transition matrices row-stochastic", ...
    max([aRowError,locRowError,lfwRowError])<=rowTolerance, ...
    max([aRowError,locRowError,lfwRowError]),rowTolerance);
checkRows=add_check(checkRows,"AUDIT-07","run-002 observed candidates reproduced", ...
    reproductionPass,sum(~observedCandidateReproduction.exact_match),0);
checkRows=add_check(checkRows,"AUDIT-08","q99.5 subset q99 subset q95 by proxy", ...
    candidateNestedPass,candidateNestedPass,true);
checkRows=add_check(checkRows,"AUDIT-09","q99.5 subset q99 subset q95 combined", ...
    combinedNestedPass,combinedNestedPass,true);
checkRows=add_check(checkRows,"AUDIT-10","zero-risk paths excluded", ...
    zeroRiskSelectedCount==0,zeroRiskSelectedCount,0);
checkRows=add_check(checkRows,"AUDIT-11","six-state full enumeration crosscheck", ...
    height(unique(enumerationCrosscheck(:,{'a0','loc0','lfw0'}),'rows'))==6, ...
    height(unique(enumerationCrosscheck(:,{'a0','loc0','lfw0'}),'rows')),6);
checkRows=add_check(checkRows,"AUDIT-12","full enumeration missed paths", ...
    crosscheckPass,fullEnumerationLeakCount,0);
checkRows=add_check(checkRows,"AUDIT-13","full enumeration extra paths", ...
    fullEnumerationExtraCount==0,fullEnumerationExtraCount,0);
checkRows=add_check(checkRows,"AUDIT-14","main sample row count and SHA-256", ...
    mainSamplePass,mainHashAfter,expectedMainHash);
checkRows=add_check(checkRows,"AUDIT-15","all source inputs unchanged", ...
    inputsUnchanged,strjoin(inputHashesAfter,' | '),strjoin(inputHashesBefore,' | '));
checkRows=add_check(checkRows,"AUDIT-16","no empirical path_probability weighting", ...
    true,"path_probability is theoretical/Pareto only","frequency is not used here");
checkRows=add_check(checkRows,"AUDIT-17","no artificial weighted risk score", ...
    ~any(contains(stateProxySummary.Properties.VariableNames,'score')), ...
    "no score","no score");
checkRows=add_check(checkRows,"AUDIT-18","no resampling calls", ...
    isempty(samplingHits),strjoin(string(samplingHits),','),"none");
checkRows=add_check(checkRows,"AUDIT-19","only reachable states cached", ...
    height(stateRiskCache)==reachableStateCount,height(stateRiskCache),reachableStateCount);
checkRows=add_check(checkRows,"AUDIT-20","pruned expansion bounded by legal paths", ...
    totalExpandedPaths<=totalLegalPaths,totalExpandedPaths,totalLegalPaths);
auditChecklist=cell2table(checkRows,'VariableNames', ...
    {'check_id','description','passed','observed','expected','required'});
passCount=sum(auditChecklist.passed);failCount=sum(~auditChecklist.passed);
auditStatus="PASS";if failCount>0,auditStatus="FAIL";end

writetable(stateRiskCache,fullfile(outputDir,'reachable_joint_state_risk_cache.csv'));
writetable(stateProxySummary,fullfile(outputDir,'search_summary_by_state_proxy.csv'));
writetable(combinedStateSummary,fullfile(outputDir,'combined_search_summary_by_state.csv'));
writetable(overallLevelSummary,fullfile(outputDir,'overall_search_summary_by_level.csv'));
writetable(pruningDiagnostics,fullfile(outputDir,'pruning_diagnostics_by_state.csv'));
writetable(observedCandidateReproduction,fullfile(outputDir, ...
    'observed_candidate_reproduction_check.csv'));
writetable(enumerationCrosscheck,fullfile(outputDir,'full_enumeration_crosscheck.csv'));
writetable(auditChecklist,fullfile(outputDir,'audit_checklist.csv'));
write_input_manifest(fullfile(outputDir,'input_manifest.txt'),inputFiles, ...
    inputBytesAfter,inputHashesAfter);
write_audit_summary(fullfile(outputDir,'audit_summary.md'),taskId,stepId,runId, ...
    runCommand,auditStatus,passCount,failCount,reachableStateCount,totalLegalPaths, ...
    totalExpandedPaths,overallLevelSummary,fullEnumerationLeakCount);
write_implementation_audit(fullfile(outputDir,'implementation_audit.md'), ...
    reachableStateCount,RmaxRef,windDecayB,gridThreshold,roadThreshold, ...
    stateRiskMaxError,crosscheckStates,fullEnumerationLeakCount,inputsUnchanged);
write_run_manifest(fullfile(outputDir,'run_manifest.txt'),taskId,stepId,runId, ...
    runCommand,auditStatus,passCount,failCount,outputDir,reachableStateCount, ...
    totalLegalPaths,totalExpandedPaths,totalFullCrosscheckPaths, ...
    overallLevelSummary,fullEnumerationLeakCount);

fprintf('\nUnobserved high-risk legal-path search finished.\n');
fprintf('Status: %s; PASS=%d; FAIL=%d\n',auditStatus,passCount,failCount);
fprintf('Reachable joint states: %d\n',reachableStateCount);
fprintf('Theoretical legal paths: %.0f\n',totalLegalPaths);
fprintf('Expanded complete paths: %.0f\n',totalExpandedPaths);
fprintf('Pruning ratio: %.12g\n',1-totalExpandedPaths/totalLegalPaths);
for ll=1:numel(levelValues)
    q=overallLevelSummary(abs(overallLevelSummary.quantile_level-levelValues(ll))<1e-12,:);
    fprintf('q%.1f unobserved high-risk=%d, unobserved Pareto=%d\n', ...
        100*levelValues(ll),q.unobserved_high_risk_path_count_total, ...
        q.unobserved_pareto_path_count_total);
end
fprintf('Full-enumeration missed paths: %d\n',fullEnumerationLeakCount);
fprintf('Output directory: %s\n',outputDir);
if failCount>0
    error('run_stage2b_search_unobserved_high_risk_paths_h2:AuditFailed', ...
        'Audit failed: %s',strjoin(auditChecklist.check_id(~auditChecklist.passed),', '));
end

function [P,maxRowError]=build_transition_matrix(tbl,fromName,toName,states,tol)
P=zeros(numel(states));
for ii=1:height(tbl)
    i=find(states==tbl.(fromName)(ii),1);j=find(states==tbl.(toName)(ii),1);
    if isempty(i)||isempty(j),error('Unknown transition state.');end
    P(i,j)=tbl.prob(ii);
end
if any(~isfinite(tbl.prob))||any(tbl.prob<0)||any(tbl.prob>1)
    error('Transition probabilities must be finite in [0,1].');
end
maxRowError=max(abs(sum(P,2)-1));if maxRowError>tol,error('Bad row sum.');end
end

function [outNext,outProb]=build_joint_outgoing(PA,PLoc,PLfw,nA,nLoc,nLfw)
nJoint=nA*nLoc*nLfw;outNext=cell(nJoint,1);outProb=cell(nJoint,1);
for iw=1:nLfw
    for il=1:nLoc
        for ia=1:nA
            s=sub2ind([nA,nLoc,nLfw],ia,il,iw);
            aNext=find(PA(ia,:)>0);lNext=find(PLoc(il,:)>0);wNext=find(PLfw(iw,:)>0);
            [AA,LL,WW]=ndgrid(aNext,lNext,wNext);
            next=sub2ind([nA,nLoc,nLfw],AA(:),LL(:),WW(:));
            probability=PA(ia,AA(:)).'.*PLoc(il,LL(:)).'.*PLfw(iw,WW(:)).';
            outNext{s}=next;outProb{s}=probability;
        end
    end
end
end

function mask=reachable_states(initialIndices,outNext,W,nJoint)
mask=false(nJoint,1);frontier=unique(initialIndices(:));
for ss=1:W
    next=[];for ii=1:numel(frontier),next=[next;outNext{frontier(ii)}(:)];end %#ok<AGROW>
    frontier=unique(next);mask(frontier)=true;
end
end

function [gridSeg,roadSeg]=build_segments(layout,roadEdges)
nodes=sortrows(layout.nodes,'node_id');lines=sortrows(layout.lines,'line_id');
gridSeg=table(lines.line_id,nodes.x_km(lines.from_node),nodes.y_km(lines.from_node), ...
    nodes.x_km(lines.to_node),nodes.y_km(lines.to_node), ...
    'VariableNames',{'line_id','x1','y1','x2','y2'});
roadSeg=table(double(roadEdges.road_edge_id), ...
    nodes.x_km(double(roadEdges.from_node)),nodes.y_km(double(roadEdges.from_node)), ...
    nodes.x_km(double(roadEdges.to_node)),nodes.y_km(double(roadEdges.to_node)), ...
    'VariableNames',{'road_edge_id','x1','y1','x2','y2'});
end

function [risk,riskTable,maxError]=build_state_risk_cache(ref,reachable,gridSeg,roadSeg,Rmax,B,gridV,roadV,nA,nLoc,nLfw,locStates)
nJoint=nA*nLoc*nLfw;risk=nan(nJoint,4);rows=cell(sum(reachable),11);rr=0;maxError=0;
for s=find(reachable).'
    [ia,il,iw]=ind2sub([nA,nLoc,nLfw],s);
    q=ref(ref.a==ia & ref.loc==locStates(il) & ref.lfw==iw-1,:);
    if height(q)~=1,error('Ambiguous state coordinate/risk reference.');end
    lineD=compute_point_to_segment_distance_h2(q.x_coord,q.y_coord, ...
        gridSeg.x1,gridSeg.y1,gridSeg.x2,gridSeg.y2);
    roadD=compute_point_to_segment_distance_h2(q.x_coord,q.y_coord, ...
        roadSeg.x1,roadSeg.y1,roadSeg.x2,roadSeg.y2);
    lineW=compute_wind_speed_radial_h2(lineD,q.Vmax_mps,Rmax,B);
    roadW=compute_wind_speed_radial_h2(roadD,q.Vmax_mps,Rmax,B);
    values=[max(lineW),sum(max(0,lineW-gridV)),max(roadW),sum(max(0,roadW-roadV))];
    reference=[q.grid_max_wind_mps,q.grid_excess_sum_mps, ...
        q.road_max_wind_mps,q.road_excess_sum_mps];
    maxError=max(maxError,max(abs(values-reference)));risk(s,:)=values;
    rr=rr+1;rows(rr,:)={s,ia,locStates(il),iw-1,q.x_coord,q.y_coord, ...
        q.Vmax_mps,values(1),values(2),values(3),values(4)};
end
riskTable=cell2table(rows,'VariableNames',{'joint_state_index','a','loc','lfw', ...
    'x_coord','y_coord','Vmax_mps','grid_max_wind_mps', ...
    'grid_cumulative_excess_mps','road_max_wind_mps', ...
    'road_cumulative_excess_mps'});
end

function [countDP,maxDP,sumDP]=build_backward_bounds(outNext,risk,W)
n=size(risk,1);countDP=zeros(n,W+1);countDP(:,1)=1;
maxDP=zeros(n,W+1,2);sumDP=zeros(n,W+1,2);maxMetrics=[1,3];sumMetrics=[2,4];
for rem=1:W
    for s=1:n
        next=outNext{s};countDP(s,rem+1)=sum(countDP(next,rem));
        for kk=1:2
            maxDP(s,rem+1,kk)=max(max(risk(next,maxMetrics(kk)), ...
                maxDP(next,rem,kk)));
            sumDP(s,rem+1,kk)=max(risk(next,sumMetrics(kk))+sumDP(next,rem,kk));
        end
    end
end
end

function thresholds=build_threshold_matrix(Q,a0,loc0,lfw0,metrics,columns)
thresholds=zeros(numel(metrics),numel(columns));
for mm=1:numel(metrics)
    q=Q(Q.a0==a0 & Q.loc0==loc0 & Q.lfw0==lfw0 & Q.risk_proxy==metrics(mm),:);
    if height(q)~=1,error('Ambiguous threshold row.');end
    for ll=1:numel(columns),thresholds(mm,ll)=double(q.(char(columns(ll))));end
end
end

function result=search_initial_state(initialIndex,thresholds,outNext,outProb,risk,maxDP,sumDP,nJoint,usePruning,relativeTol)
stateBlocks={};probBlocks={};riskBlocks={};flagBlocks={};codeBlocks={};bb=0;expanded=0;
next1=outNext{initialIndex};prob1=outProb{initialIndex};
for i1=1:numel(next1)
    s1=next1(i1);r1=risk(s1,:);active1=possible_targets(r1,s1,2,thresholds,maxDP,sumDP,relativeTol);
    if usePruning&&~any(active1,'all'),continue;end
    next2=outNext{s1};prob2=outProb{s1};
    for i2=1:numel(next2)
        s2=next2(i2);r2=[max(r1(1),risk(s2,1)),r1(2)+risk(s2,2), ...
            max(r1(3),risk(s2,3)),r1(4)+risk(s2,4)];
        active2=possible_targets(r2,s2,1,thresholds,maxDP,sumDP,relativeTol);
        if usePruning&&~any(active1&active2,'all'),continue;end
        next3=outNext{s2};prob3=outProb{s2};n3=numel(next3);expanded=expanded+n3;
        finalRisk=[max(r2(1),risk(next3,1)),r2(2)+risk(next3,2), ...
            max(r2(3),risk(next3,3)),r2(4)+risk(next3,4)];
        flags=target_flags(finalRisk,thresholds,relativeTol);
        keep=any(flags,2);
        if any(keep)
            bb=bb+1;kept=next3(keep);
            stateBlocks{bb,1}=[repmat(s1,sum(keep),1),repmat(s2,sum(keep),1),kept]; %#ok<AGROW>
            probBlocks{bb,1}=prob1(i1)*prob2(i2)*prob3(keep); %#ok<AGROW>
            riskBlocks{bb,1}=finalRisk(keep,:);flagBlocks{bb,1}=flags(keep,:); %#ok<AGROW>
            codeBlocks{bb,1}=encode_state_paths(s1,s2,kept,nJoint); %#ok<AGROW>
        end
    end
end
if bb==0
    states=zeros(0,3);prob=zeros(0,1);risks=zeros(0,4);flags=false(0,12);codes=zeros(0,1);
else
    states=vertcat(stateBlocks{:});prob=vertcat(probBlocks{:});
    risks=vertcat(riskBlocks{:});flags=vertcat(flagBlocks{:});codes=vertcat(codeBlocks{:});
end
result=struct('path_states',states,'path_probability',prob,'risk',risks, ...
    'target_flags',flags,'path_code',codes,'expanded_paths',expanded);
end

function active=possible_targets(currentRisk,state,remaining,thresholds,maxDP,sumDP,relativeTol)
upper=[max(currentRisk(1),maxDP(state,remaining+1,1)), ...
    currentRisk(2)+sumDP(state,remaining+1,1), ...
    max(currentRisk(3),maxDP(state,remaining+1,2)), ...
    currentRisk(4)+sumDP(state,remaining+1,2)];
active=false(4,3);
for mm=1:4
    for ll=1:3
        tol=relativeTol*max(1,abs(thresholds(mm,ll)));
        active(mm,ll)=upper(mm)>0 && upper(mm)>=thresholds(mm,ll)-tol;
    end
end
end

function flags=target_flags(risks,thresholds,relativeTol)
flags=false(size(risks,1),12);
for mm=1:4
    for ll=1:3
        tol=relativeTol*max(1,abs(thresholds(mm,ll)));values=risks(:,mm);
        flags(:,target_column(mm,ll))=values>0 & ...
            (values>thresholds(mm,ll)+tol | abs(values-thresholds(mm,ll))<=tol);
    end
end
end

function col=target_column(metric,level),col=(metric-1)*3+level;end
function metric=target_metric(col),metric=ceil(col/3);end

function code=encode_state_paths(s1,s2,s3,nJoint)
code=double(s1)+nJoint*(double(s2)-1)+(nJoint^2)*(double(s3)-1);
end

function code=encode_path_table(T,nJoint,nA,nLoc,nLfw,locStates)
s1=joint_index(T.a_W1,T.loc_W1,T.lfw_W1,nA,nLoc,nLfw,locStates);
s2=joint_index(T.a_W2,T.loc_W2,T.lfw_W2,nA,nLoc,nLfw,locStates);
s3=joint_index(T.a_W3,T.loc_W3,T.lfw_W3,nA,nLoc,nLfw,locStates);
code=encode_state_paths(s1,s2,s3,nJoint);
end

function idx=joint_index(a,loc,lfw,nA,nLoc,nLfw,locStates)
idx=sub2ind([nA,nLoc,nLfw],double(a),double(loc)-locStates(1)+1,double(lfw)+1);
end

function selected=pareto_low_probability_high_risk(probability,risk)
p=double(probability(:));r=double(risk(:));selected=false(numel(p),1);
if isempty(p),return;end
[~,order]=sortrows([p,-r],[1,2]);sortedP=p(order);sortedR=r(order);
maxRiskBefore=-Inf;first=1;
while first<=numel(order)
    last=first;while last<numel(order)&&sortedP(last+1)==sortedP(first),last=last+1;end
    groupRisk=sortedR(first:last);groupMax=max(groupRisk);
    if groupMax>maxRiskBefore
        chosen=order(first-1+find(groupRisk==groupMax));selected(chosen)=true;
    end
    maxRiskBefore=max(maxRiskBefore,groupMax);first=last+1;
end
end

function T=build_path_output_table(search,mask,a0,loc0,lfw0,level,cols,nA,nLoc,nLfw,locStates,paretoOnly)
states=search.path_states(mask,:);[a1,l1,w1]=decode_state(states(:,1),nA,nLoc,nLfw,locStates);
[a2,l2,w2]=decode_state(states(:,2),nA,nLoc,nLfw,locStates);
[a3,l3,w3]=decode_state(states(:,3),nA,nLoc,nLfw,locStates);
flags=search.target_flags(mask,cols);pareto=search.pareto(mask,cols);
T=table(repmat(a0,sum(mask),1),repmat(loc0,sum(mask),1),repmat(lfw0,sum(mask),1), ...
    repmat(level,sum(mask),1),search.path_code(mask),a1,a2,a3,l1,l2,l3,w1,w2,w3, ...
    search.path_probability(mask),search.risk(mask,1),search.risk(mask,2), ...
    search.risk(mask,3),search.risk(mask,4),flags(:,1),flags(:,2),flags(:,3),flags(:,4), ...
    pareto(:,1),pareto(:,2),pareto(:,3),pareto(:,4),repmat(paretoOnly,sum(mask),1), ...
    'VariableNames',{'a0','loc0','lfw0','quantile_level','path_code', ...
    'a_W1','a_W2','a_W3','loc_W1','loc_W2','loc_W3','lfw_W1','lfw_W2','lfw_W3', ...
    'path_probability','grid_max_wind_mps','grid_cumulative_excess_mps', ...
    'road_max_wind_mps','road_cumulative_excess_mps','selected_grid_max', ...
    'selected_grid_excess','selected_road_max','selected_road_excess', ...
    'pareto_grid_max','pareto_grid_excess','pareto_road_max','pareto_road_excess', ...
    'pareto_only_output'});
end

function [a,loc,lfw]=decode_state(idx,nA,nLoc,nLfw,locStates)
[a,il,iw]=ind2sub([nA,nLoc,nLfw],idx);loc=locStates(il);lfw=iw-1;
end

function append_table(fileName,T,firstWrite)
if isempty(T),return;end
if firstWrite,writetable(T,fileName);else,writetable(T,fileName,'WriteMode','append');end
end

function count=count_zero_risk_in_outputs(fileName)
if ~isfile(fileName),count=0;return;end
T=readtable(fileName);
count=sum((T.selected_grid_max&T.grid_max_wind_mps<=0)| ...
    (T.selected_grid_excess&T.grid_cumulative_excess_mps<=0)| ...
    (T.selected_road_max&T.road_max_wind_mps<=0)| ...
    (T.selected_road_excess&T.road_cumulative_excess_mps<=0));
end

function [rows,fields]=count_csv_rows_and_fields(fileName)
fid=fopen(fileName,'rb');if fid<0,error('Could not open %s.',fileName);end
cleanup=onCleanup(@()fclose(fid));header=fgetl(fid);fields=string(strsplit(header,','));
newlineCount=1;lastByte=uint8(10);
while true
    bytes=fread(fid,1024*1024,'*uint8');if isempty(bytes),break;end
    newlineCount=newlineCount+sum(bytes==10);lastByte=bytes(end);
end
totalLines=newlineCount+double(lastByte~=10);rows=totalLines-1;
end

function print_table_input(fileName,T)
fprintf('INPUT|path=%s|rows=%d|fields=%s\n',fileName,height(T), ...
    strjoin(string(T.Properties.VariableNames),','));
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
    if ~ismember(names{ii},tbl.Properties.VariableNames),error('%s missing %s.',fileName,names{ii});end
end
end

function hash=sha256_file(fileName)
fid=fopen(fileName,'rb');if fid<0,error('Could not open %s.',fileName);end
cleanup=onCleanup(@()fclose(fid));md=java.security.MessageDigest.getInstance('SHA-256');
while true
    bytes=fread(fid,1024*1024,'*uint8');if isempty(bytes),break;end
    md.update(typecast(bytes,'int8'));
end
digest=typecast(md.digest(),'uint8');hash=lower(string(reshape(dec2hex(digest,2).',1,[])));
end

function write_input_manifest(fileName,files,bytes,hashes)
fid=fopen(fileName,'w');if fid<0,error('Manifest open failed.');end
cleanup=onCleanup(@()fclose(fid));
for ii=1:numel(files)
    fprintf(fid,'input_%d=%s\ninput_%d_bytes=%d\ninput_%d_sha256=%s\n', ...
        ii,files{ii},ii,bytes(ii),ii,hashes(ii));
end
fprintf(fid,'inputs_preserved=true\n');
end

function write_audit_summary(fileName,taskId,stepId,runId,runCommand,status,passCount,failCount,reachableStates,legalPaths,expandedPaths,summary,missed)
fid=fopen(fileName,'w');if fid<0,error('Summary open failed.');end
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'# Unobserved High-Risk W3 Legal-Path Search\n\n');
fprintf(fid,'- task_id: `%s`\n- step_id: `%s`\n- run_id: `%s`\n',taskId,stepId,runId);
fprintf(fid,'- status: `%s`; PASS=%d; FAIL=%d.\n- MATLAB command: `%s`\n\n',status,passCount,failCount,runCommand);
fprintf(fid,'- reachable joint states: %d.\n- theoretical legal paths: %.0f.\n',reachableStates,legalPaths);
fprintf(fid,'- expanded complete paths: %.0f.\n- pruning ratio: %.12g.\n\n',expandedPaths,1-expandedPaths/legalPaths);
for ii=1:height(summary)
    fprintf(fid,'- q%.1f: unobserved high-risk=%d; unobserved Pareto=%d.\n', ...
        100*summary.quantile_level(ii),summary.unobserved_high_risk_path_count_total(ii), ...
        summary.unobserved_pareto_path_count_total(ii));
end
fprintf(fid,'\n- six-state full-enumeration missed paths: %d.\n',missed);
fprintf(fid,'- no supplemental sampling, B3, WDRO, Gurobi, or MSP.\n');
end

function write_implementation_audit(fileName,reachableStates,Rmax,B,gridV,roadV,riskError,crossStates,missed,inputsUnchanged)
fid=fopen(fileName,'w');if fid<0,error('Implementation audit open failed.');end
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'# Implementation Audit\n\n');
fprintf(fid,'- reachable joint states cached once: %d.\n',reachableStates);
fprintf(fid,'- wind model: Rmax=%g, B=%g, grid/road thresholds=%g/%g m/s.\n',Rmax,B,gridV,roadV);
fprintf(fid,'- maximum risk-cache difference versus run-001: %.15g.\n',riskError);
fprintf(fid,'- reverse-DP upper bounds: max recursion for peak wind, additive recursion for exceedance sums.\n');
fprintf(fid,'- crosscheck states: %s.\n',strjoin(compose('(%g,%g,%g)',crossStates(:,1),crossStates(:,2),crossStates(:,3)),', '));
fprintf(fid,'- full-enumeration missed paths: %d.\n',missed);
fprintf(fid,'- inputs unchanged: %d.\n',inputsUnchanged);
fprintf(fid,'- path_probability is theoretical/Pareto only; no empirical weighting or combined score.\n');
fprintf(fid,'- no supplemental paths, B3, WDRO, Gurobi, or MSP.\n');
end

function write_run_manifest(fileName,taskId,stepId,runId,runCommand,status,passCount,failCount,outputDir,reachableStates,legalPaths,expandedPaths,crosscheckPaths,summary,missed)
fid=fopen(fileName,'w');if fid<0,error('Run manifest open failed.');end
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'task_id=%s\nstep_id=%s\nrun_id=%s\n',taskId,stepId,runId);
fprintf(fid,'run_time=%s\nMATLAB_command=%s\n',char(datetime('now','Format','yyyy-MM-dd HH:mm:ss Z')),runCommand);
fprintf(fid,'status=%s\npass_count=%d\nfail_count=%d\n',status,passCount,failCount);
fprintf(fid,'output_directory=%s\nreachable_joint_states=%d\n',outputDir,reachableStates);
fprintf(fid,'theoretical_legal_paths=%.0f\nexpanded_complete_paths=%.0f\n',legalPaths,expandedPaths);
fprintf(fid,'pruning_ratio=%.15g\nfull_crosscheck_expanded_paths=%.0f\n',1-expandedPaths/legalPaths,crosscheckPaths);
for ii=1:height(summary)
    label=strrep(sprintf('q%.1f',100*summary.quantile_level(ii)),'.','_');
    fprintf(fid,'%s_unobserved_high_risk=%d\n%s_unobserved_pareto=%d\n', ...
        label,summary.unobserved_high_risk_path_count_total(ii),label, ...
        summary.unobserved_pareto_path_count_total(ii));
end
fprintf(fid,'full_enumeration_missed_paths=%d\n',missed);
fprintf(fid,'supplemental_paths=false\nB3_run=false\nWDRO_run=false\nGurobi_run=false\nMSP_run=false\n');
end
