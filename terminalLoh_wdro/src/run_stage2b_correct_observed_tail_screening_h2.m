clear; clc;

thisDir=fileparts(mfilename('fullpath'));
moduleDir=fileparts(thisDir);
rootDir=fileparts(moduleDir);

taskId="task-001";
stepId="03-stage2b-tail-candidate-design";
runId="run-002";
runCommand="cd('C:/Users/chaos/Desktop/biye/test/testH2_v2'); " + ...
    "run('terminalLoh_wdro/src/run_stage2b_correct_observed_tail_screening_h2.m');";
run001Dir=fullfile(moduleDir,'output','stage2b_tail_candidate_design','run-001');
outputDir=fullfile(moduleDir,'output','stage2b_tail_candidate_design','run-002');
uniquePathFile=fullfile(run001Dir,'observed_unique_path_risk.csv');
quantileFile=fullfile(run001Dir,'tail_quantiles_by_initial_state.csv');
coverageFile=fullfile(run001Dir,'initial_state_coverage_summary.csv');
overallCoverageFile=fullfile(run001Dir,'overall_equal_state_coverage_summary.csv');
overallTailFile=fullfile(run001Dir,'overall_equal_state_tail_summary.csv');
inputFiles={uniquePathFile,quantileFile,coverageFile, ...
    overallCoverageFile,overallTailFile};

expectedUniqueRows=256884;
expectedInitialStates=35;
expectedRowsPerInitial=15000;
expectedUniquePathHash= ...
    "95be36b0cfbd6981ed76b6d03f62eb80f427a913024af193abe1a20d1b1e31b0";
expectedQuantileHash= ...
    "b23de2697da1715eb849cc684cd443ec64bc5ee68ae8a2c2729123e64c6bced2";
riskMetrics=["grid_max_wind_mps","grid_cumulative_excess_mps", ...
    "road_max_wind_mps","road_cumulative_excess_mps"];
metricShort=["grid_max","grid_excess","road_max","road_excess"];
levelValues=[0.95,0.99,0.995];
levelColumns=["weighted_q95","weighted_q99","weighted_q995"];
equalityRelativeTolerance=1e-12;

for ii=1:numel(inputFiles)
    if ~isfile(inputFiles{ii})
        error('run_stage2b_correct_observed_tail_screening_h2:MissingInput', ...
            'Missing required run-001 input: %s',inputFiles{ii});
    end
end
if isfolder(outputDir)
    existing=dir(outputDir);
    existing=existing(~ismember({existing.name},{'.','..'}));
    if ~isempty(existing)
        error('run_stage2b_correct_observed_tail_screening_h2:OutputExists', ...
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

uniquePaths=readtable(uniquePathFile);
quantiles=readtable(quantileFile,'TextType','string');
coverageRun001=readtable(coverageFile);
overallCoverageRun001=readtable(overallCoverageFile,'TextType','string');
overallTailRun001=readtable(overallTailFile,'TextType','string');
requiredPathVars={'a0','loc0','lfw0','unique_path_id','frequency', ...
    'empirical_mass','path_probability'};
require_vars(uniquePaths,[requiredPathVars,cellstr(riskMetrics)],uniquePathFile);
require_vars(quantiles,{'a0','loc0','lfw0','risk_proxy', ...
    'weighted_q95','weighted_q99','weighted_q995'},quantileFile);

quantiles=quantiles(ismember(quantiles.risk_proxy,riskMetrics),:);
initialStates=unique(uniquePaths(:,{'a0','loc0','lfw0'}),'rows');
initialStates=sortrows(initialStates,{'a0','loc0','lfw0'});
nStates=height(initialStates);nMetrics=numel(riskMetrics);nLevels=numel(levelValues);

summaryRows=cell(nStates*nMetrics*nLevels,15);
combinedRows=cell(nStates*nLevels,1);
combinedSummaryRows=cell(nStates*nLevels,11);
candidateSets=cell(nStates,nMetrics,nLevels);
paretoSets=cell(nStates,nMetrics,nLevels);
combinedSets=cell(nStates,nLevels);
paretoLongIndices=[];paretoLongMetrics=strings(0,1); ...
    paretoLongLevels=zeros(0,1);paretoLongThresholds=zeros(0,1); ...
    paretoLongValues=zeros(0,1);
rr=0;cr=0;

for ss=1:nStates
    a0=initialStates.a0(ss);loc0=initialStates.loc0(ss);lfw0=initialStates.lfw0(ss);
    stateMask=uniquePaths.a0==a0 & uniquePaths.loc0==loc0 & ...
        uniquePaths.lfw0==lfw0;
    stateGlobalRows=find(stateMask);
    statePaths=uniquePaths(stateMask,:);
    stateQuantiles=quantiles(quantiles.a0==a0 & quantiles.loc0==loc0 & ...
        quantiles.lfw0==lfw0,:);
    if height(stateQuantiles)~=nMetrics
        error('run_stage2b_correct_observed_tail_screening_h2:MissingThreshold', ...
            'Expected four risk thresholds for a0=%g loc0=%g.',a0,loc0);
    end

    for ll=1:nLevels
        selectedFlags=false(height(statePaths),nMetrics);
        boundaryFlags=false(height(statePaths),nMetrics);
        paretoFlags=false(height(statePaths),nMetrics);
        for mm=1:nMetrics
            thresholdRow=stateQuantiles(stateQuantiles.risk_proxy==riskMetrics(mm),:);
            threshold=double(thresholdRow.(char(levelColumns(ll))));
            values=double(statePaths.(char(riskMetrics(mm))));
            equalityTolerance=equalityRelativeTolerance*max(1,abs(threshold));
            positive=values>0;
            strictlyAbove=positive & values>threshold+equalityTolerance;
            boundaryTie=positive & abs(values-threshold)<=equalityTolerance;
            selected=strictlyAbove|boundaryTie;
            paretoLocal=pareto_low_probability_high_risk( ...
                statePaths.path_probability(selected),values(selected));
            selectedLocalRows=find(selected);
            paretoLocalRows=selectedLocalRows(paretoLocal);
            paretoMask=false(height(statePaths),1);paretoMask(paretoLocalRows)=true;

            selectedFlags(:,mm)=selected;
            boundaryFlags(:,mm)=boundaryTie;
            paretoFlags(:,mm)=paretoMask;
            candidateSets{ss,mm,ll}=stateGlobalRows(selected);
            paretoSets{ss,mm,ll}=stateGlobalRows(paretoMask);
            rr=rr+1;
            summaryRows(rr,:)={a0,loc0,lfw0,riskMetrics(mm),levelValues(ll), ...
                threshold,equalityTolerance,sum(strictlyAbove),sum(boundaryTie), ...
                sum(selected),sum(statePaths.empirical_mass(selected)), ...
                sum(paretoMask),sum(statePaths.empirical_mass(paretoMask)), ...
                "frequency/15000","path_probability_min_risk_max"};

            globalPareto=stateGlobalRows(paretoMask);
            paretoLongIndices=[paretoLongIndices;globalPareto]; %#ok<AGROW>
            paretoLongMetrics=[paretoLongMetrics; ...
                repmat(riskMetrics(mm),numel(globalPareto),1)]; %#ok<AGROW>
            paretoLongLevels=[paretoLongLevels; ...
                repmat(levelValues(ll),numel(globalPareto),1)]; %#ok<AGROW>
            paretoLongThresholds=[paretoLongThresholds; ...
                repmat(threshold,numel(globalPareto),1)]; %#ok<AGROW>
            paretoLongValues=[paretoLongValues;values(paretoMask)]; %#ok<AGROW>
        end

        combinedSelected=any(selectedFlags,2);
        combinedPareto=any(paretoFlags,2);
        combinedSets{ss,ll}=stateGlobalRows(combinedSelected);
        cr=cr+1;
        combinedSummaryRows(cr,:)={a0,loc0,lfw0,levelValues(ll), ...
            sum(combinedSelected),sum(statePaths.empirical_mass(combinedSelected)), ...
            sum(combinedPareto),sum(statePaths.empirical_mass(combinedPareto)), ...
            sum(any(boundaryFlags,2)),height(statePaths),"four_proxy_union"};

        base=statePaths(combinedSelected,:);
        base=addvars(base,repmat(levelValues(ll),height(base),1), ...
            selectedFlags(combinedSelected,1),selectedFlags(combinedSelected,2), ...
            selectedFlags(combinedSelected,3),selectedFlags(combinedSelected,4), ...
            boundaryFlags(combinedSelected,1),boundaryFlags(combinedSelected,2), ...
            boundaryFlags(combinedSelected,3),boundaryFlags(combinedSelected,4), ...
            paretoFlags(combinedSelected,1),paretoFlags(combinedSelected,2), ...
            paretoFlags(combinedSelected,3),paretoFlags(combinedSelected,4), ...
            combinedPareto(combinedSelected),'Before','a0','NewVariableNames', ...
            {'quantile_level','selected_grid_max','selected_grid_excess', ...
            'selected_road_max','selected_road_excess','boundary_grid_max', ...
            'boundary_grid_excess','boundary_road_max','boundary_road_excess', ...
            'pareto_grid_max','pareto_grid_excess','pareto_road_max', ...
            'pareto_road_excess','pareto_any_proxy'});
        combinedRows{cr}=base;
    end
end

screeningSummary=cell2table(summaryRows,'VariableNames', ...
    {'a0','loc0','lfw0','risk_proxy','quantile_level','risk_threshold', ...
    'equality_tolerance','strictly_above_count','boundary_tie_count', ...
    'high_risk_unique_path_count','high_risk_empirical_mass', ...
    'high_risk_pareto_count','pareto_empirical_mass', ...
    'empirical_weighting_mode','pareto_objectives'});
combinedSummary=cell2table(combinedSummaryRows,'VariableNames', ...
    {'a0','loc0','lfw0','quantile_level','combined_high_risk_path_count', ...
    'combined_high_risk_empirical_mass','combined_pareto_path_count', ...
    'combined_pareto_empirical_mass','combined_boundary_path_count', ...
    'observed_unique_path_count','combination_mode'});
combinedCandidatePaths=vertcat(combinedRows{:});
paretoCandidatePaths=uniquePaths(paretoLongIndices,:);
paretoCandidatePaths=addvars(paretoCandidatePaths,paretoLongMetrics, ...
    paretoLongLevels,paretoLongThresholds,paretoLongValues,'Before','a0', ...
    'NewVariableNames',{'risk_proxy','quantile_level','risk_threshold','risk_value'});

proxyOverallRows=cell(nMetrics*nLevels,10);or=0;
for mm=1:nMetrics
    for ll=1:nLevels
        q=screeningSummary(screeningSummary.risk_proxy==riskMetrics(mm) & ...
            screeningSummary.quantile_level==levelValues(ll),:);
        or=or+1;
        proxyOverallRows(or,:)={riskMetrics(mm),levelValues(ll),height(q), ...
            sum(q.high_risk_unique_path_count),mean(q.high_risk_unique_path_count), ...
            mean(q.high_risk_empirical_mass),sum(q.strictly_above_count), ...
            sum(q.boundary_tie_count),sum(q.high_risk_pareto_count), ...
            mean(q.high_risk_pareto_count)};
    end
end
overallByProxy=cell2table(proxyOverallRows,'VariableNames', ...
    {'risk_proxy','quantile_level','initial_state_count', ...
    'high_risk_count_total','equal_state_mean_high_risk_count', ...
    'equal_state_mean_high_risk_empirical_mass','strictly_above_count_total', ...
    'boundary_tie_count_total','pareto_count_total','equal_state_mean_pareto_count'});

overallLevelRows=cell(nLevels,9);
for ll=1:nLevels
    q=combinedSummary(combinedSummary.quantile_level==levelValues(ll),:);
    overallLevelRows(ll,:)={levelValues(ll),height(q), ...
        sum(q.combined_high_risk_path_count),mean(q.combined_high_risk_path_count), ...
        mean(q.combined_high_risk_empirical_mass), ...
        sum(q.combined_boundary_path_count),sum(q.combined_pareto_path_count), ...
        mean(q.combined_pareto_path_count),"equal_weight_35_initial_states"};
end
overallByLevel=cell2table(overallLevelRows,'VariableNames', ...
    {'quantile_level','initial_state_count','combined_high_risk_path_count_total', ...
    'equal_state_mean_combined_high_risk_count', ...
    'equal_state_mean_combined_high_risk_empirical_mass', ...
    'combined_boundary_path_count_total','combined_pareto_path_count_total', ...
    'equal_state_mean_combined_pareto_count','overall_aggregation_mode'});

thresholdOrderPass=true;candidateNestedPass=true;combinedNestedPass=true;
for ss=1:nStates
    for mm=1:nMetrics
        q=screeningSummary(screeningSummary.a0==initialStates.a0(ss) & ...
            screeningSummary.loc0==initialStates.loc0(ss) & ...
            screeningSummary.risk_proxy==riskMetrics(mm),:);
        q=sortrows(q,'quantile_level');
        thresholdOrderPass=thresholdOrderPass && ...
            all(diff(q.risk_threshold)>=-max(q.equality_tolerance));
        candidateNestedPass=candidateNestedPass && ...
            all(ismember(candidateSets{ss,mm,3},candidateSets{ss,mm,2})) && ...
            all(ismember(candidateSets{ss,mm,2},candidateSets{ss,mm,1}));
    end
    combinedNestedPass=combinedNestedPass && ...
        all(ismember(combinedSets{ss,3},combinedSets{ss,2})) && ...
        all(ismember(combinedSets{ss,2},combinedSets{ss,1}));
end

zeroRiskSelectedCount=0;paretoOutsideCandidateCount=0;
for ss=1:nStates
    for mm=1:nMetrics
        for ll=1:nLevels
            selectedRows=candidateSets{ss,mm,ll};
            zeroRiskSelectedCount=zeroRiskSelectedCount+sum( ...
                uniquePaths.(char(riskMetrics(mm)))(selectedRows)<=0);
            paretoOutsideCandidateCount=paretoOutsideCandidateCount+sum( ...
                ~ismember(paretoSets{ss,mm,ll},selectedRows));
        end
    end
end

inputHashesAfter=strings(numel(inputFiles),1);inputBytesAfter=zeros(numel(inputFiles),1);
for ii=1:numel(inputFiles)
    info=dir(inputFiles{ii});inputBytesAfter(ii)=info.bytes;
    inputHashesAfter(ii)=sha256_file(inputFiles{ii});
end
run001Unchanged=isequal(inputHashesBefore,inputHashesAfter) && ...
    isequal(inputBytesBefore,inputBytesAfter);
scriptFile=mfilename('fullpath');if ~endsWith(scriptFile,'.m'),scriptFile=scriptFile+".m";end
scriptText=string(fileread(scriptFile));
samplingHits=regexp(char(scriptText),'\<(rand|randn|randi|rng|sample_chain)\s*\(', ...
    'match');
windHits=regexp(char(scriptText), ...
    '\<(compute_wind_speed_radial_h2|compute_point_to_segment_distance_h2|build_h2_spatial_layout_preview)\s*\(', ...
    'match');
fullPathSearchHits=regexp(char(scriptText), ...
    '\<(count_legal_sequences|enumerate_legal_paths|build_transition_matrix)\s*\(', ...
    'match');
quantileRecomputeHits=regexp(char(scriptText), ...
    '\<(weighted_quantile|prctile|quantile)\s*\(','match');

countIdentityPass=all(screeningSummary.strictly_above_count+ ...
    screeningSummary.boundary_tie_count==screeningSummary.high_risk_unique_path_count);
empiricalMassPass=all(abs(uniquePaths.empirical_mass- ...
    uniquePaths.frequency/expectedRowsPerInitial)<=1e-15);
paretoSubsetPass=paretoOutsideCandidateCount==0;
positiveRiskPass=zeroRiskSelectedCount==0;

checkRows={};
checkRows=add_check(checkRows,"AUDIT-01","run-001 unique path SHA-256", ...
    inputHashesBefore(1)==expectedUniquePathHash,inputHashesBefore(1),expectedUniquePathHash);
checkRows=add_check(checkRows,"AUDIT-02","run-001 quantile SHA-256", ...
    inputHashesBefore(2)==expectedQuantileHash,inputHashesBefore(2),expectedQuantileHash);
checkRows=add_check(checkRows,"AUDIT-03","256884 observed unique paths", ...
    height(uniquePaths)==expectedUniqueRows,height(uniquePaths),expectedUniqueRows);
checkRows=add_check(checkRows,"AUDIT-04","35 initial states", ...
    nStates==expectedInitialStates,nStates,expectedInitialStates);
checkRows=add_check(checkRows,"AUDIT-05","four risk proxies and three levels", ...
    height(screeningSummary)==nStates*nMetrics*nLevels, ...
    height(screeningSummary),nStates*nMetrics*nLevels);
checkRows=add_check(checkRows,"AUDIT-06","run-001 thresholds ordered", ...
    thresholdOrderPass,thresholdOrderPass,true);
checkRows=add_check(checkRows,"AUDIT-07","strict plus boundary equals selected", ...
    countIdentityPass,countIdentityPass,true);
checkRows=add_check(checkRows,"AUDIT-08","zero-risk paths excluded", ...
    positiveRiskPass,zeroRiskSelectedCount,0);
checkRows=add_check(checkRows,"AUDIT-09","Pareto candidates are high-risk subset", ...
    paretoSubsetPass,paretoOutsideCandidateCount,0);
checkRows=add_check(checkRows,"AUDIT-10","per-proxy candidate sets nested", ...
    candidateNestedPass,candidateNestedPass,true);
checkRows=add_check(checkRows,"AUDIT-11","combined candidate sets nested", ...
    combinedNestedPass,combinedNestedPass,true);
checkRows=add_check(checkRows,"AUDIT-12","empirical mass remains frequency/15000", ...
    empiricalMassPass,"frequency/15000","frequency/15000");
checkRows=add_check(checkRows,"AUDIT-13","path_probability not empirical weight", ...
    all(screeningSummary.empirical_weighting_mode=="frequency/15000"), ...
    "frequency/15000","frequency/15000");
checkRows=add_check(checkRows,"AUDIT-14","no artificial combined score", ...
    ~any(contains(combinedCandidatePaths.Properties.VariableNames,'score')), ...
    "no score","no score");
checkRows=add_check(checkRows,"AUDIT-15","no resampling calls", ...
    isempty(samplingHits),strjoin(string(samplingHits),','),"none");
checkRows=add_check(checkRows,"AUDIT-16","no wind recomputation calls", ...
    isempty(windHits),strjoin(string(windHits),','),"none");
checkRows=add_check(checkRows,"AUDIT-17","no full legal-path search", ...
    isempty(fullPathSearchHits),strjoin(string(fullPathSearchHits),','),"none");
checkRows=add_check(checkRows,"AUDIT-18","run-001 quantiles not recomputed", ...
    isempty(quantileRecomputeHits),strjoin(string(quantileRecomputeHits),','),"none");
checkRows=add_check(checkRows,"AUDIT-19","run-001 inputs unchanged", ...
    run001Unchanged,strjoin(inputHashesAfter,' | '),strjoin(inputHashesBefore,' | '));
checkRows=add_check(checkRows,"AUDIT-20","35-state equal aggregation", ...
    all(overallByLevel.overall_aggregation_mode=="equal_weight_35_initial_states"), ...
    "equal_weight_35_initial_states","equal_weight_35_initial_states");
auditChecklist=cell2table(checkRows,'VariableNames', ...
    {'check_id','description','passed','observed','expected','required'});
passCount=sum(auditChecklist.passed);failCount=sum(~auditChecklist.passed);
auditStatus="PASS";if failCount>0,auditStatus="FAIL";end

writetable(screeningSummary,fullfile(outputDir,'screening_summary_by_state_proxy.csv'));
writetable(combinedSummary,fullfile(outputDir, ...
    'combined_screening_summary_by_state.csv'));
writetable(overallByProxy,fullfile(outputDir,'overall_screening_summary_by_proxy.csv'));
writetable(overallByLevel,fullfile(outputDir,'overall_screening_summary_by_level.csv'));
writetable(combinedCandidatePaths,fullfile(outputDir,'combined_tail_candidate_paths.csv'));
writetable(paretoCandidatePaths,fullfile(outputDir,'tail_pareto_candidate_paths.csv'));
writetable(auditChecklist,fullfile(outputDir,'audit_checklist.csv'));
write_input_manifest(fullfile(outputDir,'run001_input_manifest.txt'), ...
    inputFiles,inputBytesAfter,inputHashesAfter);
write_audit_summary(fullfile(outputDir,'audit_summary.md'),taskId,stepId,runId, ...
    runCommand,auditStatus,passCount,failCount,overallByLevel,overallByProxy);
write_implementation_audit(fullfile(outputDir,'implementation_audit.md'), ...
    equalityRelativeTolerance,run001Unchanged,candidateNestedPass, ...
    combinedNestedPass,positiveRiskPass,paretoSubsetPass);
write_run_manifest(fullfile(outputDir,'run_manifest.txt'),taskId,stepId,runId, ...
    runCommand,auditStatus,passCount,failCount,outputDir,height(uniquePaths), ...
    overallByLevel,run001Unchanged);

fprintf('\nCorrected observed tail candidate screening finished.\n');
fprintf('Status: %s; PASS=%d; FAIL=%d\n',auditStatus,passCount,failCount);
for ll=1:nLevels
    q=overallByLevel(overallByLevel.quantile_level==levelValues(ll),:);
    fprintf('q%.1f: high-risk=%d, Pareto=%d\n',100*levelValues(ll), ...
        q.combined_high_risk_path_count_total,q.combined_pareto_path_count_total);
end
fprintf('Nested candidate sets: %d\n',candidateNestedPass&&combinedNestedPass);
fprintf('Output directory: %s\n',outputDir);
if failCount>0
    error('run_stage2b_correct_observed_tail_screening_h2:AuditFailed', ...
        'Audit failed: %s',strjoin(auditChecklist.check_id(~auditChecklist.passed),', '));
end

function selected=pareto_low_probability_high_risk(probability,risk)
p=double(probability(:));r=double(risk(:));selected=false(numel(p),1);
if isempty(p),return;end
[~,order]=sortrows([p,-r],[1,2]);sortedP=p(order);sortedR=r(order);
maxRiskBefore=-Inf;first=1;
while first<=numel(order)
    last=first;
    while last<numel(order)&&sortedP(last+1)==sortedP(first),last=last+1;end
    groupRisk=sortedR(first:last);groupMax=max(groupRisk);
    if groupMax>maxRiskBefore
        chosen=order(first-1+find(groupRisk==groupMax));selected(chosen)=true;
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

function write_input_manifest(fileName,files,bytes,hashes)
fid=fopen(fileName,'w');if fid<0,error('Input manifest open failed.');end
cleanup=onCleanup(@()fclose(fid));
for ii=1:numel(files)
    fprintf(fid,'input_%d=%s\ninput_%d_bytes=%d\ninput_%d_sha256=%s\n', ...
        ii,files{ii},ii,bytes(ii),ii,hashes(ii));
end
fprintf(fid,'run001_inputs_preserved=true\nresampling=false\nwind_recomputation=false\n');
end

function write_audit_summary(fileName,taskId,stepId,runId,runCommand,status, ...
    passCount,failCount,overallByLevel,overallByProxy)
fid=fopen(fileName,'w');if fid<0,error('Audit summary open failed.');end
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'# Corrected Observed W3 Tail Candidate Screening\n\n');
fprintf(fid,'- task_id: `%s`\n- step_id: `%s`\n- run_id: `%s`\n',taskId,stepId,runId);
fprintf(fid,'- status: `%s`; PASS=%d; FAIL=%d.\n',status,passCount,failCount);
fprintf(fid,'- MATLAB command: `%s`\n\n',runCommand);
fprintf(fid,'## Four-Proxy Combined Candidates\n\n');
for ii=1:height(overallByLevel)
    fprintf(fid,['- q%.1f: high-risk paths=%d; boundary paths=%d; ' ...
        'Pareto paths=%d; equal-state mean empirical mass=%.9g.\n'], ...
        100*overallByLevel.quantile_level(ii), ...
        overallByLevel.combined_high_risk_path_count_total(ii), ...
        overallByLevel.combined_boundary_path_count_total(ii), ...
        overallByLevel.combined_pareto_path_count_total(ii), ...
        overallByLevel.equal_state_mean_combined_high_risk_empirical_mass(ii));
end
fprintf(fid,'\n## Per-Proxy Counts\n\n');
for ii=1:height(overallByProxy)
    fprintf(fid,'- %s q%.1f: selected=%d; strict=%d; boundary=%d; Pareto=%d.\n', ...
        overallByProxy.risk_proxy(ii),100*overallByProxy.quantile_level(ii), ...
        overallByProxy.high_risk_count_total(ii), ...
        overallByProxy.strictly_above_count_total(ii), ...
        overallByProxy.boundary_tie_count_total(ii), ...
        overallByProxy.pareto_count_total(ii));
end
fprintf(fid,'\n- q99.5 subset q99 subset q95: required and audited.\n');
fprintf(fid,'- risk must be positive; zero-risk paths are excluded even when q=0.\n');
fprintf(fid,'- empirical mass is frequency/15000; path_probability is Pareto-only.\n');
fprintf(fid,'- no wind recomputation, resampling, full legal-path search, B3, WDRO, Gurobi, or MSP.\n');
end

function write_implementation_audit(fileName,tolerance,run001Unchanged, ...
    proxyNested,combinedNested,positiveRisk,paretoSubset)
fid=fopen(fileName,'w');if fid<0,error('Implementation audit open failed.');end
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'# Implementation Audit\n\n');
fprintf(fid,'- Inputs: run-001 observed unique-path risks and stored quantiles only.\n');
fprintf(fid,'- Equality tolerance: %.15g relative to max(1,abs(q)).\n',tolerance);
fprintf(fid,'- Candidate rule: risk>0 and (risk>q or risk=q within tolerance).\n');
fprintf(fid,'- Pareto domain: candidates at the same state/proxy/quantile only.\n');
fprintf(fid,'- Pareto objectives: lower path_probability and higher risk.\n');
fprintf(fid,'- Empirical weighting: frequency/15000; path_probability is not a weight.\n');
fprintf(fid,'- run-001 unchanged: %d.\n',run001Unchanged);
fprintf(fid,'- proxy nesting pass: %d; combined nesting pass: %d.\n',proxyNested,combinedNested);
fprintf(fid,'- positive-risk pass: %d; Pareto subset pass: %d.\n',positiveRisk,paretoSubset);
fprintf(fid,'- No combined risk score, resampling, wind recomputation, legal-path search, B3, WDRO, Gurobi, or MSP.\n');
end

function write_run_manifest(fileName,taskId,stepId,runId,runCommand,status, ...
    passCount,failCount,outputDir,uniqueRows,overallByLevel,run001Unchanged)
fid=fopen(fileName,'w');if fid<0,error('Run manifest open failed.');end
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'task_id=%s\nstep_id=%s\nrun_id=%s\n',taskId,stepId,runId);
fprintf(fid,'run_time=%s\nMATLAB_command=%s\n',char(datetime('now','Format','yyyy-MM-dd HH:mm:ss Z')),runCommand);
fprintf(fid,'status=%s\npass_count=%d\nfail_count=%d\n',status,passCount,failCount);
fprintf(fid,'output_directory=%s\ninput_unique_path_rows=%d\n',outputDir,uniqueRows);
for ii=1:height(overallByLevel)
    label=strrep(sprintf('q%.1f',100*overallByLevel.quantile_level(ii)),'.','_');
    fprintf(fid,'%s_high_risk=%d\n%s_pareto=%d\n',label, ...
        overallByLevel.combined_high_risk_path_count_total(ii),label, ...
        overallByLevel.combined_pareto_path_count_total(ii));
end
fprintf(fid,'nested_sets_pass=true\nrun001_unchanged=%d\n',run001Unchanged);
fprintf(fid,'resampling=false\nwind_recomputation=false\nfull_legal_path_search=false\n');
fprintf(fid,'B3_run=false\nWDRO_run=false\nGurobi_run=false\nMSP_run=false\n');
end
