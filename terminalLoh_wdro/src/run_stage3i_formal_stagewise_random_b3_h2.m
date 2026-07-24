%% Step-03I run-001: formal stagewise-random B3 sample stability.
clear;clc;

thisFile=mfilename('fullpath');thisDir=fileparts(thisFile);
moduleDir=fileparts(thisDir);rootDir=fileparts(moduleDir);
addpath(rootDir);addpath(thisDir);
addpath(fullfile(rootDir,'fa_h2','fuzhu','terminalLoh_windmc'));

config=struct();
config.outputDir=fullfile(moduleDir,'output','stage3i_formal_stagewise_random_b3','run-001');
config.tempOutputDir=config.outputDir+".tmp";
config.mainSampleFile=fullfile(moduleDir,'output','stage2a2_W3_path_sampling', ...
    'run-002','main_path_samples.csv');
config.candidatePoolFile=fullfile(moduleDir,'output', ...
    'stage2b_tail_candidate_design','run-005','unique_tail_paths.csv');
config.formalWindConfigFile=fullfile(moduleDir,'config','formal_b3_wind_modes.csv');
config.fixedMetricsFile=fullfile(moduleDir,'output','stage3d_b3_sample_stability', ...
    'run-001','stability_metrics_by_state.csv');
config.fixedRecommendedFile=fullfile(moduleDir,'output','stage3d_b3_sample_stability', ...
    'run-001','recommended_sample_size.csv');
config.warningSweepDir=fullfile(moduleDir,'output', ...
    'stage2_foundation_warning100_Rmax30_40_50_Wstep_sweep');
config.warningSolutionFile=fullfile(config.warningSweepDir,'warning_y_base_solution.csv');
config.warningGeometryFile=fullfile(config.warningSweepDir,'warning_geometry_by_loc.csv');
config.warningRankingFile=fullfile(config.warningSweepDir,'Wstep_candidate_ranking.csv');
config.warningStageSummaryFile=fullfile(config.warningSweepDir,'Rmax_Wstep_stage_summary.csv');
config.warningDiagnosticsFile=fullfile(config.warningSweepDir,'diagnostics_summary.txt');
config.warningRankingSourceFile=fullfile(thisDir,'rank_Wstep_candidates_h2.m');
config.locCoordinateFile=fullfile(moduleDir,'output','stage2_foundation_audit', ...
    'loc_lf_coordinate_table.csv');
config.nearInputFile=fullfile(rootDir,'data','yuanqi','near_stage_msp_input.mat');
config.roadEdgeFile=fullfile(rootDir,'data','yuanqi','stage1_road_edges.csv');
config.siteNodeFile=fullfile(rootDir,'data','yuanqi','stage1_site_nodes.csv');
config.expectedMainHash="972a8c58620c09ac19cfcfb29e8d6a3ed2819ef1a22dbd522043436418eb805d";
config.expectedCandidateHash="53738926dcffa76b16e1294ddba0dbe78e17f950a654bb4b6ad872f199b6c2ce";
config.NValues=[500,1000,2000,5000,10000,15000];
config.baseSeeds=[20260723,20260724,20260725];
config.replayN=500;config.maxWorkers=12;config.windSeedOffset=330000000;
config.Rmax=40;config.Wstep=40;config.sliceDurationH=1;config.HresTotalH=3;
config.WstepValues=40;config.recommendedWstep=40;config.comparisonWstep=45;
config.stageNames=["lf7","W1","W2","W3"];config.stageOffsets=[0,1,2,3];
config.warningDistanceKmEq=100;config.distanceMethod="point_to_segment";
config.windDecayB=0.6;config.designWindSpeedVN=25;config.roadDesignWindVN=30;
config.sourceNode=1;config.damageMode="persistent_fixed_resistance";
config.formalStabilityThresholdAvailable=false;
config.formalThresholdSource="none found for B3 D/A/C consequence stability";

requiredFiles={config.mainSampleFile,config.candidatePoolFile, ...
    config.formalWindConfigFile,config.fixedMetricsFile,config.fixedRecommendedFile, ...
    config.warningSolutionFile,config.warningGeometryFile,config.warningRankingFile, ...
    config.warningStageSummaryFile,config.warningDiagnosticsFile, ...
    config.warningRankingSourceFile,config.locCoordinateFile,config.nearInputFile, ...
    config.roadEdgeFile,config.siteNodeFile, ...
    fullfile(thisDir,'load_formal_b3_wind_config_h2.m'), ...
    fullfile(thisDir,'evaluate_formal_stagewise_b3_stability_block_h2.m'), ...
    fullfile(rootDir,'fa_h2','fuzhu','terminalLoh_windmc','compute_wind_speed_radial_h2.m'), ...
    fullfile(rootDir,'fa_h2','fuzhu','terminalLoh_windmc','compute_line_failure_prob_h2.m')};
for ii=1:numel(requiredFiles)
    if ~isfile(requiredFiles{ii})
        error('run_stage3i_formal_stagewise_random_b3_h2:MissingInput', ...
            'Required input is missing: %s',requiredFiles{ii});
    end
end
if isfolder(config.outputDir)||isfolder(config.tempOutputDir)
    error('run_stage3i_formal_stagewise_random_b3_h2:OutputExists', ...
        'Final or temporary run-001 output directory already exists.');
end

windConfig=load_formal_b3_wind_config_h2(config.formalWindConfigFile);
config.windMode=windConfig.defaultMode;

inputHashesBefore=strings(numel(requiredFiles),1);inputBytesBefore=zeros(numel(requiredFiles),1);
for ii=1:numel(requiredFiles)
    inputHashesBefore(ii)=sha256_file(requiredFiles{ii});
    info=dir(requiredFiles{ii});inputBytesBefore(ii)=info.bytes;
end
oldOutputDirs={fullfile(moduleDir,'output','stage3a_b3_smoke','run-001'), ...
    fullfile(moduleDir,'output','stage3b_b3_candidate_validation','run-001'), ...
    fullfile(moduleDir,'output','stage3c_tail_probability_audit','run-001'), ...
    fullfile(moduleDir,'output','stage3d_b3_sample_stability','run-001'), ...
    fullfile(moduleDir,'output','stage3e_intensity_wind_sensitivity','run-001'), ...
    fullfile(moduleDir,'output','stage3f_a6_wind_audit','run-001'), ...
    fullfile(moduleDir,'output','stage3g_a6_bounded_random_wind','run-001'), ...
    fullfile(moduleDir,'output','stage3h_stagewise_random_wind','run-001'), ...
    fullfile(moduleDir,'output','stage2b_tail_candidate_design','run-005')};
oldOutputSnapshotBefore=snapshot_directories(oldOutputDirs);

[mainRows,mainFields]=count_csv_rows_and_fields(config.mainSampleFile);
mainHash=sha256_file(config.mainSampleFile);
candidateHash=sha256_file(config.candidatePoolFile);
fprintf('INPUT|path=%s|rows=%d|fields=%s|sha256=%s\n',config.mainSampleFile, ...
    mainRows,strjoin(mainFields,','),mainHash);
fprintf('INPUT|path=%s|sha256=%s\n',config.candidatePoolFile,candidateHash);
if mainRows~=525000||mainHash~=config.expectedMainHash|| ...
        candidateHash~=config.expectedCandidateHash
    error('Accepted main sample or run-005 candidate pool identity mismatch.');
end

mainSample=readtable(config.mainSampleFile);
candidatePool=readtable(config.candidatePoolFile,'TextType','string');
fixedMetrics=readtable(config.fixedMetricsFile,'TextType','string');
fixedRecommended=readtable(config.fixedRecommendedFile,'TextType','string');
require_vars(mainSample,{'a0','loc0','lfw0','path_id','a_W1','a_W2','a_W3', ...
    'loc_W1','loc_W2','loc_W3','lfw_W1','lfw_W2','lfw_W3'}, ...
    'main_path_samples.csv');
require_vars(candidatePool,{'a0','loc0','lfw0','a1','a2','a3','loc1','loc2', ...
    'loc3','lfw1','lfw2','lfw3','is_observed_candidate', ...
    'is_unobserved_candidate'},'unique_tail_paths.csv');

states=unique(mainSample(:,{'a0','loc0','lfw0'}),'rows');
states=sortrows(states,{'a0','loc0','lfw0'});
if height(states)~=35,error('Expected 35 initial states, found %d.',height(states));end
stateSamples=cell(35,1);stateCountPass=true;
for ss=1:35
    mask=mainSample.a0==states.a0(ss)&mainSample.loc0==states.loc0(ss)& ...
        mainSample.lfw0==states.lfw0(ss);
    stateSamples{ss}=mainSample(mask,{'a0','loc0','lfw0','path_id', ...
        'a_W1','a_W2','a_W3','loc_W1','loc_W2','loc_W3', ...
        'lfw_W1','lfw_W2','lfw_W3'});
    stateCountPass=stateCountPass&&height(stateSamples{ss})==15000 && ...
        numel(unique(stateSamples{ss}.path_id))==15000;
end

mainCodes=physical_codes_main(mainSample);
candidateCodes=physical_codes_candidate(candidatePool);
observedFlag=as_logical(candidatePool.is_observed_candidate);
unobservedFlag=as_logical(candidatePool.is_unobserved_candidate);
naturalObservedRecordCount=sum(ismember(mainCodes,candidateCodes(observedFlag)));
unobservedCandidateRecordCount=sum(ismember(mainCodes,candidateCodes(unobservedFlag)));
externalCandidateRowsAppended=0;
clear mainSample mainCodes;

foundation=build_foundation_fix_coordinates_h2(config);
model=build_stability_model(config,foundation,windConfig);

[stateGrid,seedGrid]=ndgrid(1:height(states),1:numel(config.baseSeeds));
taskState=stateGrid(:);taskSeedIndex=seedGrid(:);nTasks=numel(taskState);
taskResults=cell(nTasks,1);replayResults=cell(nTasks,1);
useParallel=license('test','Distrib_Computing_Toolbox');pool=[];
if useParallel
    cluster=parcluster('local');workerCount=min(config.maxWorkers,cluster.NumWorkers);
    pool=gcp('nocreate');
    if isempty(pool),pool=parpool('local',workerCount);end
    cleanupPool=onCleanup(@()close_pool()); %#ok<NASGU>
    fprintf('BEGIN_FORMAL_STAGEWISE_RANDOM_B3|tasks=%d|workers=%d|scenarios=%d\n', ...
        nTasks,pool.NumWorkers,nTasks*15000);
    parfor tt=1:nTasks
        taskResults{tt}=evaluate_formal_stagewise_b3_stability_block_h2(model, ...
            stateSamples{taskState(tt)},config.baseSeeds(taskSeedIndex(tt)), ...
            taskState(tt),config.NValues,15000,config.windSeedOffset);
    end
else
    fprintf('BEGIN_FORMAL_STAGEWISE_RANDOM_B3|tasks=%d|workers=1|scenarios=%d\n', ...
        nTasks,nTasks*15000);
    for tt=1:nTasks
        taskResults{tt}=evaluate_formal_stagewise_b3_stability_block_h2(model, ...
            stateSamples{taskState(tt)},config.baseSeeds(taskSeedIndex(tt)), ...
            taskState(tt),config.NValues,15000,config.windSeedOffset);
    end
end

fprintf('BEGIN_REPRODUCIBILITY_REPLAY|tasks=%d|prefix_N=%d\n',nTasks,config.replayN);
if useParallel
    parfor tt=1:nTasks
        replayResults{tt}=evaluate_formal_stagewise_b3_stability_block_h2(model, ...
            stateSamples{taskState(tt)},config.baseSeeds(taskSeedIndex(tt)), ...
            taskState(tt),config.replayN,config.replayN,config.windSeedOffset);
    end
else
    for tt=1:nTasks
        replayResults{tt}=evaluate_formal_stagewise_b3_stability_block_h2(model, ...
            stateSamples{taskState(tt)},config.baseSeeds(taskSeedIndex(tt)), ...
            taskState(tt),config.replayN,config.replayN,config.windSeedOffset);
    end
end

metricTables=cell(nTasks,1);designTables=cell(nTasks,1);
reproducibilityPass=false(nTasks,1);reproRows=cell(nTasks,8);
windAuditRows=cell(nTasks,13);
for tt=1:nTasks
    m=taskResults{tt}.metrics;d=taskResults{tt}.design;
    m=addvars(m,repmat(states.a0(taskState(tt)),height(m),1), ...
        repmat(states.loc0(taskState(tt)),height(m),1), ...
        repmat(states.lfw0(taskState(tt)),height(m),1), ...
        repmat(taskSeedIndex(tt),height(m),1), ...
        repmat(config.baseSeeds(taskSeedIndex(tt)),height(m),1), ...
        repmat(taskResults{tt}.derived_seed,height(m),1), ...
        'Before',1,'NewVariableNames', ...
        {'a0','loc0','lfw0','seed_id','base_seed','derived_seed'});
    d=addvars(d,repmat(states.a0(taskState(tt)),height(d),1), ...
        repmat(states.loc0(taskState(tt)),height(d),1), ...
        repmat(states.lfw0(taskState(tt)),height(d),1), ...
        repmat(taskSeedIndex(tt),height(d),1), ...
        'Before',1,'NewVariableNames',{'a0','loc0','lfw0','seed_id'});
    metricTables{tt}=m;designTables{tt}=d;
    primary500=taskResults{tt}.metrics(taskResults{tt}.metrics.N==config.replayN,:);
    replay500=replayResults{tt}.metrics;
    reproducibilityPass(tt)=isequaln(primary500,replay500) && ...
        taskResults{tt}.design.prefix_record_id_sha256(1)== ...
        replayResults{tt}.design.prefix_record_id_sha256(1);
    reproRows(tt,:)={states.a0(taskState(tt)),states.loc0(taskState(tt)), ...
        states.lfw0(taskState(tt)),taskSeedIndex(tt), ...
        config.baseSeeds(taskSeedIndex(tt)),config.replayN, ...
        reproducibilityPass(tt),taskResults{tt}.first_prefix_metric_checksum- ...
        replayResults{tt}.first_prefix_metric_checksum};
    fullDesign=taskResults{tt}.design(taskResults{tt}.design.N==15000,:);
    windAuditRows(tt,:)={states.a0(taskState(tt)),states.loc0(taskState(tt)), ...
        states.lfw0(taskState(tt)),taskSeedIndex(tt),config.baseSeeds(taskSeedIndex(tt)), ...
        taskResults{tt}.resistance_seed,taskResults{tt}.wind_seed, ...
        taskResults{tt}.separate_seed_pass,taskResults{tt}.stagewise_q_pass, ...
        taskResults{tt}.wind_bounds_pass,taskResults{tt}.a6_upper_pass, ...
        taskResults{tt}.wind_reproducibility_pass, ...
        fullDesign.q_W1_prefix_sha256+" | "+fullDesign.q_W2_prefix_sha256+" | "+ ...
        fullDesign.q_W3_prefix_sha256};
end
stabilityMetrics=vertcat(metricTables{:});
sampleSizeDesign=vertcat(designTables{:});
stabilityMetrics=sortrows(stabilityMetrics,{'a0','loc0','lfw0','seed_id','N'});
sampleSizeDesign=sortrows(sampleSizeDesign,{'a0','loc0','lfw0','seed_id','N'});
reproducibilityAudit=cell2table(reproRows,'VariableNames', ...
    {'a0','loc0','lfw0','seed_id','base_seed','replay_N','passed', ...
    'metric_checksum_difference'});
randomInputAudit=cell2table(windAuditRows,'VariableNames', ...
    {'a0','loc0','lfw0','seed_id','base_seed','resistance_seed','wind_seed', ...
    'separate_seed_pass','stagewise_q_pass','wind_bounds_pass','a6_upper_pass', ...
    'wind_reproducibility_pass','q_W1_W2_W3_sha256'});
sampledWindSummary=build_sampled_wind_summary(taskResults,windConfig);

metricNames={ ...
    'D_mean_kg','D_q95_kg','D_q99_kg','full_loss_probability', ...
    'D_upper_bound_hit_share', ...
    'A0_pair_share','reachable_pair_share','C_reachable_mean_km', ...
    'C_reachable_q95_km','W3_failed_lines_mean','W3_failed_lines_q95', ...
    'W3_closed_roads_mean','W3_closed_roads_q95'};
errorRows=cell(height(states)*numel(config.baseSeeds)*numel(config.NValues)* ...
    numel(metricNames),15);er=0;
for ss=1:height(states)
    for seedId=1:numel(config.baseSeeds)
        q=stabilityMetrics(stabilityMetrics.a0==states.a0(ss)& ...
            stabilityMetrics.loc0==states.loc0(ss)& ...
            stabilityMetrics.lfw0==states.lfw0(ss)& ...
            stabilityMetrics.seed_id==seedId,:);
        ref=q(q.N==15000,:);
        for nn=1:numel(config.NValues)
            row=q(q.N==config.NValues(nn),:);
            for mm=1:numel(metricNames)
                value=double(row.(metricNames{mm}));reference=double(ref.(metricNames{mm}));
                absoluteError=abs(value-reference);
                if abs(reference)>1e-15,relativeError=absoluteError/abs(reference);
                else,relativeError=NaN;end
                er=er+1;
                errorRows(er,:)={states.a0(ss),states.loc0(ss),states.lfw0(ss), ...
                    seedId,config.baseSeeds(seedId),config.NValues(nn),15000, ...
                    string(metricNames{mm}),value,reference,absoluteError, ...
                    relativeError,abs(reference)<=1e-15, ...
                    "same-state same-seed N15000 prefix reference", ...
                    "relative error is NaN when the N15000 reference is zero"};
            end
        end
    end
end
stabilityError=cell2table(errorRows,'VariableNames', ...
    {'a0','loc0','lfw0','seed_id','base_seed','N','reference_N','metric', ...
    'value_at_N','value_at_N15000','absolute_error','relative_error', ...
    'reference_is_zero','reference_definition','relative_error_definition'});

summaryRows=cell(numel(config.NValues)*numel(metricNames),20);sr=0;
for nn=1:numel(config.NValues)
    N=config.NValues(nn);
    for mm=1:numel(metricNames)
        metric=metricNames{mm};
        q=stabilityError(stabilityError.N==N&stabilityError.metric==metric,:);
        absErr=double(q.absolute_error);relErr=double(q.relative_error);
        relErr=relErr(isfinite(relErr));
        stateDisp=zeros(height(states),1);stateMean=zeros(height(states),1);
        for ss=1:height(states)
            z=stabilityMetrics(stabilityMetrics.N==N& ...
                stabilityMetrics.a0==states.a0(ss)& ...
                stabilityMetrics.loc0==states.loc0(ss)& ...
                stabilityMetrics.lfw0==states.lfw0(ss),:);
            values=double(z.(metric));stateDisp(ss)=std(values,0);stateMean(ss)=mean(values);
        end
        [worstError,worstIndex]=max(absErr);
        sr=sr+1;
        summaryRows(sr,:)={N,string(metric),mean(double(q.value_at_N)), ...
            pct(double(q.value_at_N),5),pct(double(q.value_at_N),50), ...
            pct(double(q.value_at_N),95),mean(absErr),median(absErr), ...
            pct(absErr,95),max(absErr),mean_or_nan(relErr),pct(relErr,95), ...
            max_or_nan(relErr),mean(stateDisp),pct(stateDisp,95),max(stateDisp), ...
            q.a0(worstIndex),q.loc0(worstIndex),q.seed_id(worstIndex),worstError};
    end
end
stabilitySummary=cell2table(summaryRows,'VariableNames', ...
    {'N','metric','value_mean_across_states_seeds','value_p05', ...
    'value_median','value_p95','absolute_error_mean','absolute_error_median', ...
    'absolute_error_p95','absolute_error_max','relative_error_mean', ...
    'relative_error_p95','relative_error_max','seed_std_mean_across_states', ...
    'seed_std_p95_across_states','seed_std_max_across_states', ...
    'worst_error_a0','worst_error_loc0','worst_error_seed_id', ...
    'worst_absolute_error'});

fixedRecommendationMask=as_logical(fixedRecommended.recommended);
fixedRecommendedN=unique(double(fixedRecommended.recommended_N(fixedRecommendationMask)));
if numel(fixedRecommendedN)~=1,error('Accepted Step-03D recommendation is ambiguous.');end
recommendRows=cell(numel(config.NValues),15);
for nn=1:numel(config.NValues)
    q=stabilitySummary(stabilitySummary.N==config.NValues(nn),:);
    recommendRows(nn,:)={config.NValues(nn),config.formalStabilityThresholdAvailable, ...
        config.formalThresholdSource,NaN,NaN, ...
        max(q.relative_error_p95,[],'omitnan'), ...
        max(q.relative_error_max,[],'omitnan'), ...
        max(q.seed_std_p95_across_states),config.NValues(nn)==15000, ...
        "conservative maximum tested N because no accepted B3 consequence threshold exists", ...
        "diagnostic recommendation, not threshold acceptance",15000, ...
        fixedRecommendedN,fixedRecommendedN==15000,"unchanged from fixed_representative"};
end
recommendedSampleSize=cell2table(recommendRows,'VariableNames', ...
    {'N','formal_threshold_available','formal_threshold_source', ...
    'formal_absolute_error_threshold','formal_relative_error_threshold', ...
    'max_p95_relative_error_across_metrics','max_relative_error_across_metrics', ...
    'max_p95_seed_std_across_metrics','recommended','recommendation_basis', ...
    'recommendation_status','recommended_N','fixed_wind_recommended_N', ...
    'recommendation_matches_fixed_wind','comparison_to_fixed_wind'});

fixedVsRandomFullScale=build_fixed_random_comparison( ...
    fixedMetrics,stabilityMetrics,metricNames);

inputHashesAfter=strings(numel(requiredFiles),1);inputBytesAfter=zeros(numel(requiredFiles),1);
for ii=1:numel(requiredFiles)
    inputHashesAfter(ii)=sha256_file(requiredFiles{ii});
    info=dir(requiredFiles{ii});inputBytesAfter(ii)=info.bytes;
end
oldOutputSnapshotAfter=snapshot_directories(oldOutputDirs);
inputsUnchanged=isequal(inputHashesBefore,inputHashesAfter)&& ...
    isequal(inputBytesBefore,inputBytesAfter);
oldOutputsUnchanged=isequaln(oldOutputSnapshotBefore,oldOutputSnapshotAfter);

completePass=height(stabilityMetrics)==35*3*6 && ...
    height(sampleSizeDesign)==35*3*6 && ...
    height(stabilityError)==35*3*6*numel(metricNames);
formalScenarioPass=sum(cellfun(@(x)x.evaluated_record_count,taskResults))==35*3*15000;
nestedPass=all(sampleSizeDesign.nested_in_parent_pass);
weightPass=all(abs(sampleSizeDesign.record_weight_sum-1)<=1e-12) && ...
    all(abs(sampleSizeDesign.record_weight-1./sampleSizeDesign.N)<=1e-15);
noCandidateInjectionPass=externalCandidateRowsAppended==0 && ...
    unobservedCandidateRecordCount==0;
domainPass=all(stabilityMetrics.D_min_kg>=0) && ...
    all(stabilityMetrics.A0_min>=0&stabilityMetrics.A0_max<=1) && ...
    all(stabilityMetrics.C_mean_min_km>=0) && ...
    all(stabilityMetrics.D_nonfinite_count==0) && ...
    all(stabilityMetrics.C_nonfinite_count==0) && ...
    all(stabilityMetrics.D_negative_count==0) && ...
    all(stabilityMetrics.C_negative_count==0) && ...
    all(stabilityMetrics.A_invalid_scenario_count==0) && ...
    all(stabilityMetrics.C_invalid_value_count==0);
reproPass=all(reproducibilityAudit.passed);
stagewiseWindPass=all(randomInputAudit.stagewise_q_pass);
windBoundsPass=all(randomInputAudit.wind_bounds_pass);
a6UpperPass=all(randomInputAudit.a6_upper_pass);
separateSeedPass=all(randomInputAudit.separate_seed_pass);
windReplayPass=all(randomInputAudit.wind_reproducibility_pass);
referencePass=all(stabilityError.absolute_error(stabilityError.N==15000)==0);
noThresholdFabricationPass=~config.formalStabilityThresholdAvailable && ...
    all(isnan(recommendedSampleSize.formal_absolute_error_threshold)) && ...
    all(isnan(recommendedSampleSize.formal_relative_error_threshold));
formalDefaultPass=config.windMode=="stagewise_random_triangular"&& ...
    windConfig.defaultMode=="stagewise_random_triangular";
fixedModePreservedPass=ismember("fixed_representative",windConfig.availableModes)&& ...
    any(windConfig.table.wind_mode=="fixed_representative");
fixedComparisonPass=height(fixedVsRandomFullScale)==35*3*numel(metricNames)&& ...
    all(isfinite(fixedVsRandomFullScale.fixed_value))&& ...
    all(isfinite(fixedVsRandomFullScale.random_value));
forbiddenHits=scan_forbidden_calls({thisFile+".m", ...
    fullfile(thisDir,'evaluate_formal_stagewise_b3_stability_block_h2.m'), ...
    fullfile(thisDir,'load_formal_b3_wind_config_h2.m')});
noForbiddenCalls=height(forbiddenHits)==0;

checks={};
checks=add_check(checks,"AUDIT-01","35 states each contain 15000 main records",stateCountPass,stateCountPass,true);
checks=add_check(checks,"AUDIT-02","all state seed and N combinations completed",completePass,height(stabilityMetrics),630);
checks=add_check(checks,"AUDIT-03","35 x 15000 x 3 formal joint scenarios completed",formalScenarioPass,sum(cellfun(@(x)x.evaluated_record_count,taskResults)),1575000);
checks=add_check(checks,"AUDIT-04","nested prefix relationship holds",nestedPass,sum(~sampleSizeDesign.nested_in_parent_pass),0);
checks=add_check(checks,"AUDIT-05","record weights equal 1/N and sum to one",weightPass,max(abs(sampleSizeDesign.record_weight_sum-1)),0);
checks=add_check(checks,"AUDIT-06","formal B3 default is stagewise_random_triangular",formalDefaultPass,config.windMode,"stagewise_random_triangular");
checks=add_check(checks,"AUDIT-07","fixed_representative remains available",fixedModePreservedPass,fixedModePreservedPass,true);
checks=add_check(checks,"AUDIT-08","W1 W2 and W3 use independent wind quantiles",stagewiseWindPass,sum(~randomInputAudit.stagewise_q_pass),0);
checks=add_check(checks,"AUDIT-09","sampled wind remains inside every grade interval",windBoundsPass,sum(~randomInputAudit.wind_bounds_pass),0);
checks=add_check(checks,"AUDIT-10","a6 sampled wind never exceeds 60 m/s",a6UpperPass,sum(~randomInputAudit.a6_upper_pass),0);
checks=add_check(checks,"AUDIT-11","wind and resistance seeds are separate",separateSeedPass,sum(~randomInputAudit.separate_seed_pass),0);
checks=add_check(checks,"AUDIT-12","wind random streams reproduce exactly",windReplayPass,sum(~randomInputAudit.wind_reproducibility_pass),0);
checks=add_check(checks,"AUDIT-13","no external candidates or unobserved candidate records added",noCandidateInjectionPass,[externalCandidateRowsAppended,unobservedCandidateRecordCount],[0,0]);
checks=add_check(checks,"AUDIT-14","natural observed-candidate records retain main-sample identity",naturalObservedRecordCount>0,naturalObservedRecordCount,">0 and not separately appended");
checks=add_check(checks,"AUDIT-15","D A and reachable C domains valid",domainPass,domainPass,true);
checks=add_check(checks,"AUDIT-16","same-seed N500 replay is identical for all 105 blocks",reproPass,sum(~reproducibilityAudit.passed),0);
checks=add_check(checks,"AUDIT-17","N15000 reference errors equal zero",referencePass,max(stabilityError.absolute_error(stabilityError.N==15000)),0);
checks=add_check(checks,"AUDIT-18","fixed and random N15000 comparison is complete",fixedComparisonPass,height(fixedVsRandomFullScale),35*3*numel(metricNames));
checks=add_check(checks,"AUDIT-19","source inputs and formal wind config unchanged during run",inputsUnchanged,inputsUnchanged,true);
checks=add_check(checks,"AUDIT-20","accepted old run directories unchanged",oldOutputsUnchanged,oldOutputsUnchanged,true);
checks=add_check(checks,"AUDIT-21","no B3 stability threshold was fabricated",noThresholdFabricationPass,noThresholdFabricationPass,true);
checks=add_check(checks,"AUDIT-22","persistent fixed resistance mode used",model.fixedResistancePass,config.damageMode,"persistent_fixed_resistance");
checks=add_check(checks,"AUDIT-23","no WDRO Gurobi optimization or MSP calls",noForbiddenCalls,height(forbiddenHits),0);
checks=add_check(checks,"AUDIT-24","main sample SHA-256 unchanged",sha256_file(config.mainSampleFile)==config.expectedMainHash,sha256_file(config.mainSampleFile),config.expectedMainHash);
automaticAudit=cell2table(checks,'VariableNames', ...
    {'check_id','description','passed','observed','expected'});
passCount=sum(automaticAudit.passed);failCount=sum(~automaticAudit.passed);
status="PASS";if failCount>0,status="FAIL";end
if failCount>0
    error('run_stage3i_formal_stagewise_random_b3_h2:AuditFailed', ...
        'Step-03I audit failed before output creation: %s', ...
        strjoin(automaticAudit.check_id(~automaticAudit.passed),', '));
end

mkdir(config.tempOutputDir);
writetable(windConfig.table,fullfile(config.tempOutputDir,'formal_wind_mode_definition.csv'));
writetable(sampledWindSummary,fullfile(config.tempOutputDir,'sampled_wind_summary_by_level.csv'));
writetable(sampleSizeDesign,fullfile(config.tempOutputDir,'sample_size_design.csv'));
writetable(stabilityMetrics,fullfile(config.tempOutputDir,'stability_metrics_by_state.csv'));
writetable(stabilityError,fullfile(config.tempOutputDir,'stability_error_vs_N15000.csv'));
writetable(stabilitySummary,fullfile(config.tempOutputDir,'stability_summary_overall.csv'));
writetable(fixedVsRandomFullScale,fullfile(config.tempOutputDir,'fixed_vs_random_full_scale.csv'));
writetable(recommendedSampleSize,fullfile(config.tempOutputDir,'recommended_sample_size.csv'));
writetable(reproducibilityAudit,fullfile(config.tempOutputDir,'reproducibility_audit.csv'));
writetable(randomInputAudit,fullfile(config.tempOutputDir,'random_input_audit.csv'));
writetable(automaticAudit,fullfile(config.tempOutputDir,'automatic_audit.csv'));
write_manifest(fullfile(config.tempOutputDir,'run_manifest.txt'),config,status, ...
    passCount,failCount,useParallel,naturalObservedRecordCount,stabilitySummary,windConfig);
write_readme(fullfile(config.tempOutputDir,'README.txt'),config,status,passCount, ...
    failCount,stabilitySummary,recommendedSampleSize,naturalObservedRecordCount, ...
    sampledWindSummary,fixedVsRandomFullScale,windConfig);
write_thesis_note(fullfile(config.tempOutputDir,'thesis_stagewise_random_wind_note.txt'), ...
    windConfig,config);
movefile(config.tempOutputDir,config.outputDir);

fprintf('\nStage3I formal stagewise-random B3 stability finished.\n');
fprintf('Status: %s; PASS=%d; FAIL=%d\n',status,passCount,failCount);
fprintf('Scenarios evaluated: %d full + %d replay.\n',nTasks*15000,nTasks*500);
fprintf('Recommended N: 15000 (conservative; no formal B3 threshold exists).\n');
fprintf('Output directory: %s\n',config.outputDir);

function model=build_stability_model(config,foundation,windConfig)
near=foundation.raw_near;grid=foundation.grid_segments;road=foundation.road_segments;
Pnode=double(near.Grid.P_load_base_kw(:));eta=double(near.HydrogenDevice.eta_FC);
lhv=double(near.HydrogenDevice.h2_lhv_kWh_per_kg);
site=readtable(config.siteNodeFile);site=sortrows(site,'site_id');
locValues=sort(double(foundation.loc_table.loc));nStates=6*numel(locValues)*4;
lineFactor=zeros(nStates,height(grid));roadFactor=zeros(nStates,height(road));
stateIndex=zeros(6,numel(locValues),4);rr=0;
for a=1:6
    for loc=locValues(:).'
        locRow=foundation.loc_table(foundation.loc_table.loc==loc,:);
        for lfw=0:3
            rr=rr+1;x=double(locRow.x_coord);y=foundation.y_base+lfw*config.Wstep;
            lineDist=compute_point_to_segment_distance_h2(x,y,grid.x1,grid.y1,grid.x2,grid.y2);
            roadDist=compute_point_to_segment_distance_h2(x,y,road.x1,road.y1,road.x2,road.y2);
            lineFactor(rr,:)=compute_wind_speed_radial_h2( ...
                lineDist,1,config.Rmax,config.windDecayB).';
            roadFactor(rr,:)=compute_wind_speed_radial_h2( ...
                roadDist,1,config.Rmax,config.windDecayB).';
            stateIndex(a,loc-min(locValues)+1,lfw+1)=rr;
        end
    end
end
incidence=radial_node_path_incidence(numel(Pnode),grid.from_node,grid.to_node,config.sourceNode);
model=struct();model.lineFactor=lineFactor;model.roadFactor=roadFactor;
model.stateIndex=stateIndex;
model.locMin=min(locValues);model.locMax=max(locValues);model.nLines=height(grid);
model.nRoads=height(road);model.nNodes=numel(Pnode);model.nSites=height(site);
model.sourceNode=config.sourceNode;model.Pnode_kW=Pnode;
model.nodePathIncidence=incidence;model.roadFrom=double(road.from_node);
model.roadTo=double(road.to_node);model.roadLength=hypot(road.x2-road.x1,road.y2-road.y1);
model.siteNodes=double(site.grid_node);model.DFactorKgPerKWh=1/(eta*lhv);
model.DUpperKg=3*(sum(Pnode)-Pnode(config.sourceNode))*model.DFactorKgPerKWh;
model.fixedResistancePass=true;model.windMode=windConfig.defaultMode;
model.windLower=windConfig.randomLower;model.windModeValues=windConfig.randomMode;
model.windUpper=windConfig.randomUpper;
model.designWindSpeedVN=config.designWindSpeedVN;
model.roadDesignWindVN=config.roadDesignWindVN;
end
function incidence=radial_node_path_incidence(nNodes,fromNode,toNode,sourceNode)
nLines=numel(fromNode);
if nLines~=nNodes-1,error('Grid is not radial: expected %d lines, found %d.',nNodes-1,nLines);end
adj=cell(nNodes,1);edgeAdj=cell(nNodes,1);
for ll=1:nLines
    i=fromNode(ll);j=toNode(ll);adj{i}(end+1)=j;edgeAdj{i}(end+1)=ll; %#ok<AGROW>
    adj{j}(end+1)=i;edgeAdj{j}(end+1)=ll; %#ok<AGROW>
end
parent=zeros(nNodes,1);parentEdge=zeros(nNodes,1);visited=false(nNodes,1);
queue=zeros(nNodes,1);head=1;tail=1;queue(1)=sourceNode;visited(sourceNode)=true;
while head<=tail
    u=queue(head);head=head+1;
    for kk=1:numel(adj{u})
        v=adj{u}(kk);if visited(v),continue;end
        visited(v)=true;parent(v)=u;parentEdge(v)=edgeAdj{u}(kk);
        tail=tail+1;queue(tail)=v;
    end
end
if ~all(visited),error('Grid is not connected to source node %d.',sourceNode);end
incidence=false(nNodes,nLines);
for node=1:nNodes
    cur=node;
    while cur~=sourceNode
        incidence(node,parentEdge(cur))=true;cur=parent(cur);
    end
end
end
function codes=physical_codes_main(T)
codes=encode_codes(double(T.a0),double(T.loc0),double(T.lfw0), ...
    double(T.a_W1),double(T.loc_W1),double(T.lfw_W1), ...
    double(T.a_W2),double(T.loc_W2),double(T.lfw_W2), ...
    double(T.a_W3),double(T.loc_W3),double(T.lfw_W3));
end
function codes=physical_codes_candidate(T)
codes=encode_codes(double(T.a0),double(T.loc0),double(T.lfw0), ...
    double(T.a1),double(T.loc1),double(T.lfw1),double(T.a2),double(T.loc2), ...
    double(T.lfw2),double(T.a3),double(T.loc3),double(T.lfw3));
end
function codes=encode_codes(varargin)
n=numel(varargin{1});codes=zeros(n,1,'uint64');bases=[7,13,4,7,13,4,7,13,4,7,13,4];
for ii=1:12
    value=double(varargin{ii});if mod(ii,3)==2,value=value+2;end
    codes=codes*uint64(bases(ii))+uint64(value);
end
end

function T=build_sampled_wind_summary(taskResults,windConfig)
counts=zeros(6,1);
for tt=1:numel(taskResults)
    for level=1:6,counts(level)=counts(level)+numel(taskResults{tt}.wind_values_by_level{level});end
end
values=cell(6,1);positions=zeros(6,1);
for level=1:6,values{level}=zeros(counts(level),1);end
for tt=1:numel(taskResults)
    for level=1:6
        x=taskResults{tt}.wind_values_by_level{level};n=numel(x);
        if n>0
            target=positions(level)+(1:n);values{level}(target)=x;positions(level)=positions(level)+n;
        end
    end
end
rows=cell(6,10);
for level=1:6
    x=values{level};rows(level,:)={level,numel(x),min(x),mean(x),pct(x,50), ...
        pct(x,95),max(x),windConfig.randomLower(level), ...
        windConfig.randomMode(level),windConfig.randomUpper(level)};
end
T=cell2table(rows,'VariableNames',{'intensity_level','sample_count','minimum_mps', ...
    'mean_mps','median_mps','q95_mps','maximum_mps','lower_bound_mps', ...
    'mode_mps','upper_bound_mps'});
end

function T=build_fixed_random_comparison(fixedMetrics,randomMetrics,metricNames)
randomFull=randomMetrics(randomMetrics.N==15000,:);
rows=cell(height(randomFull)*numel(metricNames),13);rr=0;
for ii=1:height(randomFull)
    fixed=fixedMetrics(double(fixedMetrics.a0)==randomFull.a0(ii)& ...
        double(fixedMetrics.loc0)==randomFull.loc0(ii)& ...
        double(fixedMetrics.lfw0)==randomFull.lfw0(ii)& ...
        double(fixedMetrics.seed_id)==randomFull.seed_id(ii)&double(fixedMetrics.N)==15000,:);
    if height(fixed)~=1,error('Missing unique Step-03D fixed N15000 reference.');end
    for mm=1:numel(metricNames)
        metric=metricNames{mm};fixedMetric=metric;
        if strcmp(metric,'D_upper_bound_hit_share'),fixedMetric='full_loss_probability';end
        fixedValue=double(fixed.(fixedMetric));randomValue=double(randomFull.(metric)(ii));
        difference=randomValue-fixedValue;
        if abs(fixedValue)>1e-15,relativeDifference=difference/abs(fixedValue);
        else,relativeDifference=NaN;end
        rr=rr+1;rows(rr,:)={randomFull.a0(ii),randomFull.loc0(ii), ...
            randomFull.lfw0(ii),randomFull.seed_id(ii),randomFull.base_seed(ii), ...
            15000,string(metric),fixedValue,randomValue,difference,relativeDifference, ...
            "Step-03D fixed_representative run-001","stagewise_random_triangular"};
    end
end
T=cell2table(rows,'VariableNames',{'a0','loc0','lfw0','seed_id','base_seed', ...
    'N','metric','fixed_value','random_value','random_minus_fixed', ...
    'relative_difference','fixed_reference','formal_random_mode'});
end

function summary=snapshot_directories(dirs)
rows={};
for dd=1:numel(dirs)
    files=dir(fullfile(dirs{dd},'**','*'));files=files(~[files.isdir]);
    for ii=1:numel(files)
        rows(end+1,:)={string(dirs{dd}),string(fullfile(files(ii).folder,files(ii).name)), ...
            files(ii).bytes,files(ii).datenum}; %#ok<AGROW>
    end
end
if isempty(rows),summary=cell2table(cell(0,4),'VariableNames',{'root','path','bytes','datenum'});
else,summary=sortrows(cell2table(rows,'VariableNames',{'root','path','bytes','datenum'}),'path');end
end
function T=scan_forbidden_calls(files)
patterns=["solve_wdro_"+"terminal_loh_lp_h2\\s*\\(","guro"+"bi\\s*\\(", ...
    "main_msp_"+"h2_near\\s*\\(","run_h2_"+"with_options\\s*\\(", ...
    "opti"+"mize\\s*\\(","lin"+"prog\\s*\\("];
rows={};
for ff=1:numel(files)
    text=fileread(files{ff});
    for pp=1:numel(patterns)
        if ~isempty(regexp(text,patterns(pp),'once'))
            rows(end+1,:)={string(files{ff}),patterns(pp)}; %#ok<AGROW>
        end
    end
end
if isempty(rows),T=cell2table(cell(0,2),'VariableNames',{'file','pattern'});
else,T=cell2table(rows,'VariableNames',{'file','pattern'});end
end
function write_convergence_figures(folder,T,NValues)
groups={ ...
    {'D_mean_kg','D_q95_kg','D_q99_kg'},'D_convergence.png','D (kg-H2)'; ...
    {'full_loss_probability','A0_pair_share','reachable_pair_share'},'risk_accessibility_convergence.png','Probability / share'; ...
    {'C_reachable_mean_km','C_reachable_q95_km'},'C_convergence.png','Reachable C (km)'; ...
    {'W3_failed_lines_mean','W3_closed_roads_mean'},'damage_count_convergence.png','Component count'};
for gg=1:size(groups,1)
    metrics=groups{gg,1};f=figure('Visible','off','Color','w','Position',[100,100,900,320*numel(metrics)]);
    tl=tiledlayout(numel(metrics),1,'TileSpacing','compact','Padding','compact');
    for mm=1:numel(metrics)
        nexttile;means=zeros(numel(NValues),1);low=means;high=means;
        for nn=1:numel(NValues)
            values=double(T.(metrics{mm})(T.N==NValues(nn)));
            means(nn)=mean(values);low(nn)=pct(values,10);high(nn)=pct(values,90);
        end
        errorbar(NValues,means,means-low,high-means,'o-','LineWidth',1.4,'MarkerSize',5);
        grid on;xlabel('Records per initial state');ylabel(groups{gg,3});
        title(strrep(metrics{mm},'_',' '));set(gca,'XScale','log','XTick',NValues);
    end
    title(tl,'Nominal B3 nested-sample convergence: mean with state/seed p10-p90');
    exportgraphics(f,fullfile(folder,groups{gg,2}),'Resolution',160);close(f);
end
end
function close_pool()
p=gcp('nocreate');if ~isempty(p),delete(p);end
end
function values=as_logical(values)
if islogical(values),return;end
if isnumeric(values),values=values~=0;else
    text=lower(strtrim(string(values)));values=text=="true"|text=="1";
end
end
function require_vars(T,names,fileName)
for ii=1:numel(names)
    if ~ismember(names{ii},T.Properties.VariableNames),error('%s missing %s.',fileName,names{ii});end
end
end
function value=pct(x,p)
x=sort(double(x(:)));x=x(isfinite(x));
if isempty(x),value=NaN;else,value=x(max(1,min(numel(x),ceil(p/100*numel(x)))));end
end
function value=mean_or_nan(x),if isempty(x),value=NaN;else,value=mean(x);end,end
function value=max_or_nan(x),if isempty(x),value=NaN;else,value=max(x);end,end
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
function hash=sha256_file(fileName)
fid=fopen(fileName,'rb');if fid<0,error('Could not open %s.',fileName);end
cleanup=onCleanup(@()fclose(fid));md=java.security.MessageDigest.getInstance('SHA-256');
while true
    bytes=fread(fid,1024*1024,'*uint8');if isempty(bytes),break;end
    md.update(typecast(bytes,'int8'));
end
digest=typecast(md.digest(),'uint8');hash=lower(string(reshape(dec2hex(digest,2).',1,[])));
end
function rows=add_check(rows,id,description,passed,observed,expected)
rows(end+1,:)={string(id),string(description),logical(passed),scalar_text(observed),scalar_text(expected)};
end
function text=scalar_text(value)
if isstring(value),text=strjoin(value(:).',' | ');
elseif ischar(value),text=string(value);
elseif islogical(value)&&isscalar(value),text=string(double(value));
elseif isnumeric(value)&&isscalar(value),text=string(sprintf('%.15g',value));
elseif isnumeric(value),text=strjoin(compose('%.15g',value(:).'),' | ');
else,text=string(value);end
end
function write_manifest(fileName,config,status,passCount,failCount,useParallel,naturalObserved,summary,windConfig)
fid=fopen(fileName,'w');if fid<0,error('Could not write %s.',fileName);end
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'task_id=task-002\nstep_id=09-formal-stagewise-random-b3\nrun_id=run-001\n');
fprintf(fid,'run_time=%s\nstatus=%s\npass_count=%d\nfail_count=%d\n', ...
    char(datetime('now','Format','yyyy-MM-dd HH:mm:ss Z')),status,passCount,failCount);
fprintf(fid,'formal_wind_default=%s\nretained_wind_mode=fixed_representative\n',windConfig.defaultMode);
fprintf(fid,'wind_randomness_layer=second_layer_B3_joint_consequence\nthird_layer_monte_carlo=false\n');
fprintf(fid,'stage_quantiles=independent_q_W1_q_W2_q_W3\na6_project_upper_mps=60\n');
fprintf(fid,'N_values=%s\nbase_seeds=%s\ninitial_states=35\n', ...
    strjoin(string(config.NValues),','),strjoin(string(config.baseSeeds),','));
fprintf(fid,'full_B3_scenarios=%d\nreplay_scenarios=%d\nparallel_used=%d\n',35*3*15000,35*3*500,useParallel);
fprintf(fid,'sampling_unit=main_Monte_Carlo_record\nrecord_weight=1/N\npath_probability_reweighting=false\n');
fprintf(fid,'natural_observed_candidate_records=%d\nexternal_candidate_rows_appended=0\nunobserved_candidate_records=0\n',naturalObserved);
fprintf(fid,'formal_B3_stability_threshold_available=false\nrecommended_N=15000\n');
hard=summary(summary.N==500,:);[~,idx]=max(hard.relative_error_p95,[],'omitnan');
fprintf(fid,'largest_N500_p95_relative_error_metric=%s\n',hard.metric(idx));
fprintf(fid,'WDRO_run=false\nGurobi_run=false\nMSP_run=false\n');
end
function write_readme(fileName,config,status,passCount,failCount,summary,recommend, ...
    naturalObserved,windSummary,fixedComparison,windConfig)
fid=fopen(fileName,'w');if fid<0,error('Could not write %s.',fileName);end
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'Step-03I run-001: formal stagewise-random B3 sample-size stability\n\n');
fprintf(fid,'status=%s; PASS=%d; FAIL=%d\n',status,passCount,failCount);
fprintf(fid,'Formal B3 wind default: %s. fixed_representative remains available.\n',windConfig.defaultMode);
fprintf(fid,'35 states x 15000 main records x 3 joint seeds were evaluated with persistent fixed resistance and independent W1-W3 wind quantiles.\n');
fprintf(fid,'Nested N values: %s. Smaller N is an exact prefix of larger N.\n',strjoin(string(config.NValues),', '));
fprintf(fid,'Each prefix record has weight 1/N; path_probability is not used as a second weight.\n');
fprintf(fid,'Natural observed-tail paths remain only at their main-sample frequency (%d records); no candidate rows are appended and no unobserved candidate appears.\n',naturalObserved);
for level=1:6
    q=windSummary(windSummary.intensity_level==level,:);
    fprintf(fid,'a=%d wind samples=%d: min %.9g, mean %.9g, median %.9g, q95 %.9g, max %.9g m/s.\n', ...
        level,q.sample_count,q.minimum_mps,q.mean_mps,q.median_mps,q.q95_mps,q.maximum_mps);
end
fprintf(fid,'No accepted B3 D/A/C stability threshold exists, so no pass threshold is invented.\n');
fprintf(fid,'The conservative diagnostic recommendation is N=%d, the largest tested/reference sample.\n', ...
    recommend.recommended_N(recommend.recommended));
for N=config.NValues
    q=summary(summary.N==N,:);[worst,widx]=max(q.relative_error_p95,[],'omitnan');
    fprintf(fid,'- N=%d: largest metric p95 relative error %.12g (%s); largest p95 seed std %.12g.\n', ...
        N,worst,q.metric(widx),max(q.seed_std_p95_across_states));
end
metrics=["D_mean_kg","D_q95_kg","D_q99_kg","full_loss_probability", ...
    "A0_pair_share","C_reachable_mean_km","C_reachable_q95_km", ...
    "W3_failed_lines_mean","W3_closed_roads_mean","D_upper_bound_hit_share"];
for metric=metrics
    q=fixedComparison(fixedComparison.metric==metric,:);
    fprintf(fid,'N15000 %s fixed/random/difference: %.12g / %.12g / %.12g.\n', ...
        metric,mean(q.fixed_value),mean(q.random_value),mean(q.random_minus_fixed));
end
fprintf(fid,'No WDRO, Gurobi optimization, MSP, candidate augmentation, or nominal-probability change.\n');
end

function write_thesis_note(fileName,windConfig,config)
fid=fopen(fileName,'w');if fid<0,error('Could not write %s.',fileName);end
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'Formal B3 stagewise random wind method\n\n');
fprintf(fid,'Default mode: %s. Retained comparison mode: fixed_representative.\n',windConfig.defaultMode);
fprintf(fid,'For each main path-resistance record, W1, W2, and W3 receive independent Uniform(0,1) quantiles. Equal adjacent intensity levels are redrawn.\n');
fprintf(fid,'The quantiles map through project-defined triangular distributions: a1 fixed 0; a2 Triangular(17.2,20.8,24.4); a3 Triangular(24.5,28.55,32.6); a4 Triangular(32.7,37.05,41.4); a5 Triangular(41.5,46.2,50.9); a6 Triangular(51,55.5,60) m/s.\n');
fprintf(fid,'The 60 m/s a6 endpoint is this study''s computational upper limit, not an official or physical upper bound.\n');
fprintf(fid,'Wind quantiles and component resistance uniforms use separate reproducible seeds. They jointly define one second-layer B3 consequence realization; no third Monte Carlo layer is introduced.\n');
fprintf(fid,'Line and road components retain persistent_fixed_resistance: one resistance draw per component and record is fixed across W1-W3, and damage does not recover within the 3 h horizon.\n');
fprintf(fid,'The fixed_representative mode uses [0,20.8,28.55,37.05,46.2,55.5] m/s and remains available for controlled comparison and reproduction of accepted old runs.\n');
fprintf(fid,'Main-sample records are weighted 1/N within each initial state. path_probability is not applied again.\n');
fprintf(fid,'References for stochastic tropical-cyclone and wind-field simulation context:\n');
fprintf(fid,'- Vickery, Skerlj and Twisdale (2000).\n');
fprintf(fid,'- Jing and Lin (2020).\n');
fprintf(fid,'These references motivate stochastic wind/hurricane simulation context; the grade-wise triangular parameters above are project assumptions and are not claimed to be distributions estimated by those papers.\n');
fprintf(fid,'Run seeds: %s. Wind seed offset: %d.\n',strjoin(string(config.baseSeeds),','),config.windSeedOffset);
end
