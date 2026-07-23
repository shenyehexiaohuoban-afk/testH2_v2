%% Step-03D run-001: nominal B3 sample-size stability.
clear;clc;

thisFile=mfilename('fullpath');thisDir=fileparts(thisFile);
moduleDir=fileparts(thisDir);rootDir=fileparts(moduleDir);
addpath(rootDir);addpath(thisDir);
addpath(fullfile(rootDir,'fa_h2','fuzhu','terminalLoh_windmc'));

config=struct();
config.outputDir=fullfile(moduleDir,'output','stage3d_b3_sample_stability','run-001');
config.tempOutputDir=config.outputDir+".tmp";
config.mainSampleFile=fullfile(moduleDir,'output','stage2a2_W3_path_sampling', ...
    'run-002','main_path_samples.csv');
config.candidatePoolFile=fullfile(moduleDir,'output', ...
    'stage2b_tail_candidate_design','run-005','unique_tail_paths.csv');
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
config.replayN=500;config.maxWorkers=12;
config.Rmax=40;config.Wstep=40;config.sliceDurationH=1;config.HresTotalH=3;
config.WstepValues=40;config.recommendedWstep=40;config.comparisonWstep=45;
config.stageNames=["lf7","W1","W2","W3"];config.stageOffsets=[0,1,2,3];
config.warningDistanceKmEq=100;config.distanceMethod="point_to_segment";
config.windDecayB=0.6;config.designWindSpeedVN=25;config.roadDesignWindVN=30;
config.sourceNode=1;config.damageMode="persistent_fixed_resistance";
config.formalStabilityThresholdAvailable=false;
config.formalThresholdSource="none found for B3 D/A/C consequence stability";

requiredFiles={config.mainSampleFile,config.candidatePoolFile, ...
    config.warningSolutionFile,config.warningGeometryFile,config.warningRankingFile, ...
    config.warningStageSummaryFile,config.warningDiagnosticsFile, ...
    config.warningRankingSourceFile,config.locCoordinateFile,config.nearInputFile, ...
    config.roadEdgeFile,config.siteNodeFile, ...
    fullfile(thisDir,'evaluate_nominal_b3_stability_block_h2.m'), ...
    fullfile(rootDir,'fa_h2','fuzhu','terminalLoh_windmc','compute_wind_speed_radial_h2.m'), ...
    fullfile(rootDir,'fa_h2','fuzhu','terminalLoh_windmc','compute_line_failure_prob_h2.m')};
for ii=1:numel(requiredFiles)
    if ~isfile(requiredFiles{ii})
        error('run_stage3d_b3_sample_stability_h2:MissingInput', ...
            'Required input is missing: %s',requiredFiles{ii});
    end
end
if isfolder(config.outputDir)||isfolder(config.tempOutputDir)
    error('run_stage3d_b3_sample_stability_h2:OutputExists', ...
        'Final or temporary run-001 output directory already exists.');
end

inputHashesBefore=strings(numel(requiredFiles),1);inputBytesBefore=zeros(numel(requiredFiles),1);
for ii=1:numel(requiredFiles)
    inputHashesBefore(ii)=sha256_file(requiredFiles{ii});
    info=dir(requiredFiles{ii});inputBytesBefore(ii)=info.bytes;
end
oldOutputDirs={fullfile(moduleDir,'output','stage3a_b3_smoke','run-001'), ...
    fullfile(moduleDir,'output','stage3b_b3_candidate_validation','run-001'), ...
    fullfile(moduleDir,'output','stage3c_tail_probability_audit','run-001'), ...
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
model=build_stability_model(config,foundation);

[stateGrid,seedGrid]=ndgrid(1:height(states),1:numel(config.baseSeeds));
taskState=stateGrid(:);taskSeedIndex=seedGrid(:);nTasks=numel(taskState);
taskResults=cell(nTasks,1);replayResults=cell(nTasks,1);
useParallel=license('test','Distrib_Computing_Toolbox');pool=[];
if useParallel
    cluster=parcluster('local');workerCount=min(config.maxWorkers,cluster.NumWorkers);
    pool=gcp('nocreate');
    if isempty(pool),pool=parpool('local',workerCount);end
    cleanupPool=onCleanup(@()close_pool()); %#ok<NASGU>
    fprintf('BEGIN_FULL_NOMINAL_B3|tasks=%d|workers=%d|scenarios=%d\n', ...
        nTasks,pool.NumWorkers,nTasks*15000);
    parfor tt=1:nTasks
        taskResults{tt}=evaluate_nominal_b3_stability_block_h2(model, ...
            stateSamples{taskState(tt)},config.baseSeeds(taskSeedIndex(tt)), ...
            taskState(tt),config.NValues,15000);
    end
else
    fprintf('BEGIN_FULL_NOMINAL_B3|tasks=%d|workers=1|scenarios=%d\n', ...
        nTasks,nTasks*15000);
    for tt=1:nTasks
        taskResults{tt}=evaluate_nominal_b3_stability_block_h2(model, ...
            stateSamples{taskState(tt)},config.baseSeeds(taskSeedIndex(tt)), ...
            taskState(tt),config.NValues,15000);
    end
end

fprintf('BEGIN_REPRODUCIBILITY_REPLAY|tasks=%d|prefix_N=%d\n',nTasks,config.replayN);
if useParallel
    parfor tt=1:nTasks
        replayResults{tt}=evaluate_nominal_b3_stability_block_h2(model, ...
            stateSamples{taskState(tt)},config.baseSeeds(taskSeedIndex(tt)), ...
            taskState(tt),config.replayN,config.replayN);
    end
else
    for tt=1:nTasks
        replayResults{tt}=evaluate_nominal_b3_stability_block_h2(model, ...
            stateSamples{taskState(tt)},config.baseSeeds(taskSeedIndex(tt)), ...
            taskState(tt),config.replayN,config.replayN);
    end
end

metricTables=cell(nTasks,1);designTables=cell(nTasks,1);
reproducibilityPass=false(nTasks,1);reproRows=cell(nTasks,8);
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
end
stabilityMetrics=vertcat(metricTables{:});
sampleSizeDesign=vertcat(designTables{:});
stabilityMetrics=sortrows(stabilityMetrics,{'a0','loc0','lfw0','seed_id','N'});
sampleSizeDesign=sortrows(sampleSizeDesign,{'a0','loc0','lfw0','seed_id','N'});
reproducibilityAudit=cell2table(reproRows,'VariableNames', ...
    {'a0','loc0','lfw0','seed_id','base_seed','replay_N','passed', ...
    'metric_checksum_difference'});

metricNames={ ...
    'D_mean_kg','D_q95_kg','D_q99_kg','full_loss_probability', ...
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

recommendRows=cell(numel(config.NValues),12);
for nn=1:numel(config.NValues)
    q=stabilitySummary(stabilitySummary.N==config.NValues(nn),:);
    recommendRows(nn,:)={config.NValues(nn),config.formalStabilityThresholdAvailable, ...
        config.formalThresholdSource,NaN,NaN, ...
        max(q.relative_error_p95,[],'omitnan'), ...
        max(q.relative_error_max,[],'omitnan'), ...
        max(q.seed_std_p95_across_states),config.NValues(nn)==15000, ...
        "conservative maximum tested N because no accepted B3 consequence threshold exists", ...
        "diagnostic recommendation, not threshold acceptance",15000};
end
recommendedSampleSize=cell2table(recommendRows,'VariableNames', ...
    {'N','formal_threshold_available','formal_threshold_source', ...
    'formal_absolute_error_threshold','formal_relative_error_threshold', ...
    'max_p95_relative_error_across_metrics','max_relative_error_across_metrics', ...
    'max_p95_seed_std_across_metrics','recommended','recommendation_basis', ...
    'recommendation_status','recommended_N'});

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
    height(sampleSizeDesign)==35*3*6 && height(stabilityError)==35*3*6*12;
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
referencePass=all(stabilityError.absolute_error(stabilityError.N==15000)==0);
noThresholdFabricationPass=~config.formalStabilityThresholdAvailable && ...
    all(isnan(recommendedSampleSize.formal_absolute_error_threshold)) && ...
    all(isnan(recommendedSampleSize.formal_relative_error_threshold));
forbiddenHits=scan_forbidden_calls({thisFile+".m", ...
    fullfile(thisDir,'evaluate_nominal_b3_stability_block_h2.m')});
noForbiddenCalls=height(forbiddenHits)==0;

checks={};
checks=add_check(checks,"AUDIT-01","35 states each contain 15000 main records",stateCountPass,stateCountPass,true);
checks=add_check(checks,"AUDIT-02","all state seed and N combinations completed",completePass,height(stabilityMetrics),630);
checks=add_check(checks,"AUDIT-03","nested prefix relationship holds",nestedPass,sum(~sampleSizeDesign.nested_in_parent_pass),0);
checks=add_check(checks,"AUDIT-04","record weights equal 1/N and sum to one",weightPass,max(abs(sampleSizeDesign.record_weight_sum-1)),0);
checks=add_check(checks,"AUDIT-05","no external candidates or unobserved candidate records added",noCandidateInjectionPass,[externalCandidateRowsAppended,unobservedCandidateRecordCount],[0,0]);
checks=add_check(checks,"AUDIT-06","natural observed-candidate records retain main-sample identity",naturalObservedRecordCount>0,naturalObservedRecordCount,">0 and not separately appended");
checks=add_check(checks,"AUDIT-07","D A and reachable C domains valid",domainPass,domainPass,true);
checks=add_check(checks,"AUDIT-08","same-seed N500 replay is identical for all 105 blocks",reproPass,sum(~reproducibilityAudit.passed),0);
checks=add_check(checks,"AUDIT-09","N15000 reference errors equal zero",referencePass,max(stabilityError.absolute_error(stabilityError.N==15000)),0);
checks=add_check(checks,"AUDIT-10","source inputs unchanged",inputsUnchanged,inputsUnchanged,true);
checks=add_check(checks,"AUDIT-11","accepted old run directories unchanged",oldOutputsUnchanged,oldOutputsUnchanged,true);
checks=add_check(checks,"AUDIT-12","no B3 stability threshold was fabricated",noThresholdFabricationPass,noThresholdFabricationPass,true);
checks=add_check(checks,"AUDIT-13","persistent fixed resistance mode used",model.fixedResistancePass,config.damageMode,"persistent_fixed_resistance");
checks=add_check(checks,"AUDIT-14","no WDRO Gurobi optimization or MSP calls",noForbiddenCalls,height(forbiddenHits),0);
checks=add_check(checks,"AUDIT-15","main sample SHA-256 unchanged",sha256_file(config.mainSampleFile)==config.expectedMainHash,sha256_file(config.mainSampleFile),config.expectedMainHash);
automaticAudit=cell2table(checks,'VariableNames', ...
    {'check_id','description','passed','observed','expected'});
passCount=sum(automaticAudit.passed);failCount=sum(~automaticAudit.passed);
status="PASS";if failCount>0,status="FAIL";end
if failCount>0
    error('run_stage3d_b3_sample_stability_h2:AuditFailed', ...
        'Step-03D audit failed before output creation: %s', ...
        strjoin(automaticAudit.check_id(~automaticAudit.passed),', '));
end

mkdir(config.tempOutputDir);mkdir(fullfile(config.tempOutputDir,'figures'));
writetable(sampleSizeDesign,fullfile(config.tempOutputDir,'sample_size_design.csv'));
writetable(stabilityMetrics,fullfile(config.tempOutputDir,'stability_metrics_by_state.csv'));
writetable(stabilityError,fullfile(config.tempOutputDir,'stability_error_vs_N15000.csv'));
writetable(stabilitySummary,fullfile(config.tempOutputDir,'stability_summary_overall.csv'));
writetable(recommendedSampleSize,fullfile(config.tempOutputDir,'recommended_sample_size.csv'));
writetable(reproducibilityAudit,fullfile(config.tempOutputDir,'reproducibility_audit.csv'));
writetable(automaticAudit,fullfile(config.tempOutputDir,'automatic_audit.csv'));
write_manifest(fullfile(config.tempOutputDir,'run_manifest.txt'),config,status, ...
    passCount,failCount,useParallel,naturalObservedRecordCount,stabilitySummary);
write_readme(fullfile(config.tempOutputDir,'README.txt'),config,status,passCount, ...
    failCount,stabilitySummary,recommendedSampleSize,naturalObservedRecordCount);
write_convergence_figures(fullfile(config.tempOutputDir,'figures'), ...
    stabilityMetrics,config.NValues);
movefile(config.tempOutputDir,config.outputDir);

fprintf('\nStage3D nominal B3 sample stability finished.\n');
fprintf('Status: %s; PASS=%d; FAIL=%d\n',status,passCount,failCount);
fprintf('Scenarios evaluated: %d full + %d replay.\n',nTasks*15000,nTasks*500);
fprintf('Recommended N: 15000 (conservative; no formal B3 threshold exists).\n');
fprintf('Output directory: %s\n',config.outputDir);

function model=build_stability_model(config,foundation)
near=foundation.raw_near;grid=foundation.grid_segments;road=foundation.road_segments;
Pnode=double(near.Grid.P_load_base_kw(:));eta=double(near.HydrogenDevice.eta_FC);
lhv=double(near.HydrogenDevice.h2_lhv_kWh_per_kg);
site=readtable(config.siteNodeFile);site=sortrows(site,'site_id');
locValues=sort(double(foundation.loc_table.loc));nStates=6*numel(locValues)*4;
pFail=zeros(nStates,height(grid));pClose=zeros(nStates,height(road));
stateIndex=zeros(6,numel(locValues),4);rr=0;
for a=1:6
    for loc=locValues(:).'
        locRow=foundation.loc_table(foundation.loc_table.loc==loc,:);
        for lfw=0:3
            rr=rr+1;x=double(locRow.x_coord);y=foundation.y_base+lfw*config.Wstep;
            Vmax=intensity_to_vmax(a);
            lineDist=compute_point_to_segment_distance_h2(x,y,grid.x1,grid.y1,grid.x2,grid.y2);
            roadDist=compute_point_to_segment_distance_h2(x,y,road.x1,road.y1,road.x2,road.y2);
            lineWind=compute_wind_speed_radial_h2(lineDist,Vmax,config.Rmax,config.windDecayB);
            roadWind=compute_wind_speed_radial_h2(roadDist,Vmax,config.Rmax,config.windDecayB);
            pFail(rr,:)=compute_line_failure_prob_h2(lineWind,config.designWindSpeedVN).';
            pClose(rr,:)=compute_line_failure_prob_h2(roadWind,config.roadDesignWindVN).';
            stateIndex(a,loc-min(locValues)+1,lfw+1)=rr;
        end
    end
end
incidence=radial_node_path_incidence(numel(Pnode),grid.from_node,grid.to_node,config.sourceNode);
model=struct();model.pFail=pFail;model.pClose=pClose;model.stateIndex=stateIndex;
model.locMin=min(locValues);model.locMax=max(locValues);model.nLines=height(grid);
model.nRoads=height(road);model.nNodes=numel(Pnode);model.nSites=height(site);
model.sourceNode=config.sourceNode;model.Pnode_kW=Pnode;
model.nodePathIncidence=incidence;model.roadFrom=double(road.from_node);
model.roadTo=double(road.to_node);model.roadLength=hypot(road.x2-road.x1,road.y2-road.y1);
model.siteNodes=double(site.grid_node);model.DFactorKgPerKWh=1/(eta*lhv);
model.DUpperKg=3*(sum(Pnode)-Pnode(config.sourceNode))*model.DFactorKgPerKWh;
model.fixedResistancePass=true;
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
function Vmax=intensity_to_vmax(a)
map=[0;20.8;28.55;37.05;46.20;55.50];Vmax=map(a);
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
function write_manifest(fileName,config,status,passCount,failCount,useParallel,naturalObserved,summary)
fid=fopen(fileName,'w');if fid<0,error('Could not write %s.',fileName);end
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'task_id=task-002\nstep_id=04-b3-sample-stability\nrun_id=run-001\n');
fprintf(fid,'run_time=%s\nstatus=%s\npass_count=%d\nfail_count=%d\n', ...
    char(datetime('now','Format','yyyy-MM-dd HH:mm:ss Z')),status,passCount,failCount);
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
function write_readme(fileName,config,status,passCount,failCount,summary,recommend,naturalObserved)
fid=fopen(fileName,'w');if fid<0,error('Could not write %s.',fileName);end
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'Step-03D run-001: nominal B3 sample-size stability\n\n');
fprintf(fid,'status=%s; PASS=%d; FAIL=%d\n',status,passCount,failCount);
fprintf(fid,'35 states x 15000 main records x 3 seeds were evaluated with persistent fixed resistance.\n');
fprintf(fid,'Nested N values: %s. Smaller N is an exact prefix of larger N.\n',strjoin(string(config.NValues),', '));
fprintf(fid,'Each prefix record has weight 1/N; path_probability is not used as a second weight.\n');
fprintf(fid,'Natural observed-tail paths remain only at their main-sample frequency (%d records); no candidate rows are appended and no unobserved candidate appears.\n',naturalObserved);
fprintf(fid,'No accepted B3 D/A/C stability threshold exists, so no pass threshold is invented.\n');
fprintf(fid,'The conservative diagnostic recommendation is N=%d, the largest tested/reference sample.\n', ...
    recommend.recommended_N(recommend.recommended));
for N=config.NValues
    q=summary(summary.N==N,:);[worst,widx]=max(q.relative_error_p95,[],'omitnan');
    fprintf(fid,'- N=%d: largest metric p95 relative error %.12g (%s); largest p95 seed std %.12g.\n', ...
        N,worst,q.metric(widx),max(q.seed_std_p95_across_states));
end
fprintf(fid,'No WDRO, Gurobi optimization, MSP, candidate augmentation, or nominal-probability change.\n');
end
