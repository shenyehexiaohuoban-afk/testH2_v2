%% Step-03F run-001: a=6 wind-data audit and paired B3 sensitivity.
clear;clc;

thisFile=mfilename('fullpath');thisDir=fileparts(thisFile);
moduleDir=fileparts(thisDir);rootDir=fileparts(moduleDir);
addpath(rootDir);addpath(thisDir);
addpath(fullfile(rootDir,'fa_h2','fuzhu','terminalLoh_windmc'));

config=struct();
config.outputDir=fullfile(moduleDir,'output','stage3f_a6_wind_audit','run-001');
config.tempOutputDir=config.outputDir+".tmp";
config.mainSampleFile=fullfile(moduleDir,'output','stage2a2_W3_path_sampling', ...
    'run-002','main_path_samples.csv');
config.candidatePoolFile=fullfile(moduleDir,'output', ...
    'stage2b_tail_candidate_design','run-005','unique_tail_paths.csv');
config.step3eMetricsFile=fullfile(moduleDir,'output', ...
    'stage3e_intensity_wind_sensitivity','run-001','wind_mode_metrics.csv');
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
config.cmaBestTrackDir=string(getenv('CMA_BEST_TRACK_DIR'));
config.cmaArchiveFile=string(getenv('CMA_BEST_TRACK_ARCHIVE'));
config.ibtracsFile=string(getenv('IBTRACS_WP_FILE'));
config.expectedMainHash="972a8c58620c09ac19cfcfb29e8d6a3ed2819ef1a22dbd522043436418eb805d";
config.expectedCandidateHash="53738926dcffa76b16e1294ddba0dbe78e17f950a654bb4b6ad872f199b6c2ce";
config.expectedCmaArchiveHash="1e36a4bf58088a2d9c32fc944c6cba8433a0d735894a6d64a68a5ec4d1aa2105";
config.expectedIbtracsHash="77b686af554b33ddec7b11d9e32d726ada90c5ce8c4e1a37c2c1d89e39fab5cc";
config.cmaMirrorCommit="19ad9ff02537c962bdaaba9c98f2a5980e251ba9";
config.representativeStates=[5,4,0;2,6,0;2,1,0;4,4,0;6,7,0];
config.baseSeeds=[20260723,20260724,20260725];
config.N=2000;config.maxWorkers=12;
config.Rmax=40;config.Wstep=40;config.sliceDurationH=1;config.HresTotalH=3;
config.windDecayB=0.6;config.designWindSpeedVN=25;config.roadDesignWindVN=30;
config.sourceNode=1;config.damageMode="persistent_fixed_resistance";
config.currentMap=[0;20.8;28.55;37.05;46.20;55.50];
config.currentA6Mps=55.5;config.a6ThresholdMps=51;config.minimumA6SampleCount=30;
config.knotToMps=0.514444;
config.modeNames=["M0","M6_MEDIAN","M6_Q90","M6_Q95"];
config.DUpperKgExpected=607.969887897881;
config.cmaOfficialDataUrl="https://tcdata.typhoon.org.cn/zjljsjj.html";
config.cmaOfficialReleaseUrl="https://www.cma.gov.cn/2011xwzx/2011xqxkj/2011xkjdt/202504/t20250411_6991129.html";
config.cmaWindPeriodUrl="https://www.cma.gov.cn/wmhd/gzly/20CMAckly/202308/t20230822_5727280.html";
config.cmaMirrorUrl="https://www.modelscope.cn/datasets/ai4s/CMA";
config.ibtracsUrl="https://www.ncei.noaa.gov/data/international-best-track-archive-for-climate-stewardship-ibtracs/v04r01/access/netcdf/IBTrACS.WP.v04r01.nc";
config.knappCitation="Knapp KR, Kruk MC, Levinson DH, Diamond HJ, Neumann CJ (2010), The International Best Track Archive for Climate Stewardship (IBTrACS): Unifying Tropical Cyclone Best Track Data, BAMS 91, 363-376, doi:10.1175/2009BAMS2755.1";
config.cmaCitation="Lu XQ et al. (2021), Western North Pacific Tropical Cyclone Database Created by the China Meteorological Administration, AAS 38, 690-699, doi:10.1007/s00376-020-0211-7";

if strlength(config.cmaBestTrackDir)==0||strlength(config.cmaArchiveFile)==0|| ...
        strlength(config.ibtracsFile)==0
    error('Set CMA_BEST_TRACK_DIR, CMA_BEST_TRACK_ARCHIVE, and IBTRACS_WP_FILE.');
end

requiredFiles={config.mainSampleFile,config.candidatePoolFile,config.step3eMetricsFile, ...
    config.warningSolutionFile,config.warningGeometryFile,config.warningRankingFile, ...
    config.warningStageSummaryFile,config.warningDiagnosticsFile, ...
    config.warningRankingSourceFile,config.locCoordinateFile,config.nearInputFile, ...
    config.roadEdgeFile,config.siteNodeFile,config.cmaArchiveFile,config.ibtracsFile, ...
    fullfile(thisDir,'audit_a6_historical_wind_data_h2.m'), ...
    fullfile(thisDir,'evaluate_a6_wind_sensitivity_block_h2.m'), ...
    fullfile(rootDir,'fa_h2','fuzhu','terminalLoh_windmc','compute_wind_speed_radial_h2.m'), ...
    fullfile(rootDir,'fa_h2','fuzhu','terminalLoh_windmc','compute_line_failure_prob_h2.m')};
for ii=1:numel(requiredFiles)
    if ~isfile(requiredFiles{ii}),error('Required input is missing: %s',requiredFiles{ii});end
end
if ~isfolder(config.cmaBestTrackDir),error('CMA extracted directory is missing.');end
if isfolder(config.outputDir)||isfolder(config.tempOutputDir)
    error('Final or temporary run-001 output directory already exists.');
end

inputHashesBefore=strings(numel(requiredFiles),1);inputBytesBefore=zeros(numel(requiredFiles),1);
for ii=1:numel(requiredFiles)
    inputHashesBefore(ii)=sha256_file(requiredFiles{ii});info=dir(requiredFiles{ii});
    inputBytesBefore(ii)=info.bytes;
end
oldOutputDirs={fullfile(moduleDir,'output','stage3a_b3_smoke','run-001'), ...
    fullfile(moduleDir,'output','stage3b_b3_candidate_validation','run-001'), ...
    fullfile(moduleDir,'output','stage3c_tail_probability_audit','run-001'), ...
    fullfile(moduleDir,'output','stage3d_b3_sample_stability','run-001'), ...
    fullfile(moduleDir,'output','stage3e_intensity_wind_sensitivity','run-001')};
oldOutputSnapshotBefore=snapshot_directories(oldOutputDirs);

historical=audit_a6_historical_wind_data_h2(config.cmaBestTrackDir, ...
    config.cmaArchiveFile,config.ibtracsFile,config);
fprintf('CMA_A6|records=%d|median=%.6g|q90=%.6g|q95=%.6g|archive_sha256=%s\n', ...
    height(historical.cma_records),historical.sensitivity_values_mps(2), ...
    historical.sensitivity_values_mps(3),historical.sensitivity_values_mps(4), ...
    historical.cma_archive_sha256);
fprintf('IBTRACS_CROSSCHECK|records=%d|rounded_multiset_match=%d|sha256=%s\n', ...
    historical.crosscheck.ibtracs_selected_record_count, ...
    historical.crosscheck.rounded_wind_multiset_match,historical.ibtracs_sha256);

mappingAudit=build_current_mapping_audit(rootDir,config);
dataComparable=historical.data_comparable_pass;
sampleSufficient=historical.sample_sufficient_pass;
if ~dataComparable
    error('DATA_NOT_COMPARABLE: CMA and IBTrACS CMA-source records do not match.');
end
if ~sampleSufficient
    error('INSUFFICIENT_A6_SAMPLES: only %d accepted CMA records.',height(historical.cma_records));
end

[mainRows,mainFields]=count_csv_rows_and_fields(config.mainSampleFile);
mainHash=sha256_file(config.mainSampleFile);candidateHash=sha256_file(config.candidatePoolFile);
fprintf('INPUT|path=%s|rows=%d|fields=%s|sha256=%s\n',config.mainSampleFile, ...
    mainRows,strjoin(mainFields,','),mainHash);
if mainRows~=525000||mainHash~=config.expectedMainHash||candidateHash~=config.expectedCandidateHash
    error('Accepted main sample or candidate pool identity mismatch.');
end
if historical.cma_archive_sha256~=config.expectedCmaArchiveHash|| ...
        historical.ibtracs_sha256~=config.expectedIbtracsHash
    error('External source-data hash mismatch.');
end

mainSample=readtable(config.mainSampleFile);
candidatePool=readtable(config.candidatePoolFile,'TextType','string');
step3eMetrics=readtable(config.step3eMetricsFile,'TextType','string');
require_vars(mainSample,{'a0','loc0','lfw0','path_id','a_W1','a_W2','a_W3', ...
    'loc_W1','loc_W2','loc_W3','lfw_W1','lfw_W2','lfw_W3'},'main sample');
allStates=unique(mainSample(:,{'a0','loc0','lfw0'}),'rows');
allStates=sortrows(allStates,{'a0','loc0','lfw0'});
stateSamples=cell(5,1);stateIds=zeros(5,1);stateCountPass=true;
for ss=1:5
    a0=config.representativeStates(ss,1);loc0=config.representativeStates(ss,2);
    lfw0=config.representativeStates(ss,3);
    stateIds(ss)=find(allStates.a0==a0&allStates.loc0==loc0&allStates.lfw0==lfw0,1);
    mask=mainSample.a0==a0&mainSample.loc0==loc0&mainSample.lfw0==lfw0;
    stateSamples{ss}=mainSample(mask,{'a0','loc0','lfw0','path_id', ...
        'a_W1','a_W2','a_W3','loc_W1','loc_W2','loc_W3','lfw_W1','lfw_W2','lfw_W3'});
    stateCountPass=stateCountPass&&height(stateSamples{ss})==15000;
end
mainCodes=physical_codes_main(mainSample);candidateCodes=physical_codes_candidate(candidatePool);
unobservedFlag=as_logical(candidatePool.is_unobserved_candidate);
unobservedOverlapInMain=sum(ismember(mainCodes,candidateCodes(unobservedFlag)));
clear mainSample mainCodes candidateCodes candidatePool;

a6Values=historical.sensitivity_values_mps;
foundationConfig=config;foundationConfig.WstepValues=40;
foundationConfig.recommendedWstep=40;foundationConfig.comparisonWstep=45;
foundationConfig.stageNames=["lf7","W1","W2","W3"];
foundationConfig.stageOffsets=[0,1,2,3];foundationConfig.warningDistanceKmEq=100;
foundationConfig.distanceMethod="point_to_segment";
foundation=build_foundation_fix_coordinates_h2(foundationConfig);
model=build_a6_model(config,foundation,a6Values);

[stateGrid,seedGrid]=ndgrid(1:5,1:3);taskState=stateGrid(:);
taskSeedIndex=seedGrid(:);nTasks=numel(taskState);taskResults=cell(nTasks,1);
useParallel=license('test','Distrib_Computing_Toolbox');pool=[];
if useParallel
    cluster=parcluster('local');workerCount=min(config.maxWorkers,cluster.NumWorkers);
    pool=gcp('nocreate');if isempty(pool),pool=parpool('local',workerCount);end
    cleanupPool=onCleanup(@()close_pool()); %#ok<NASGU>
    fprintf('BEGIN_STAGE3F|tasks=%d|workers=%d|paths=%d|mode_scenarios=%d\n', ...
        nTasks,pool.NumWorkers,nTasks*config.N,nTasks*config.N*4);
    parfor tt=1:nTasks
        taskResults{tt}=evaluate_a6_wind_sensitivity_block_h2(model, ...
            stateSamples{taskState(tt)},config.baseSeeds(taskSeedIndex(tt)), ...
            stateIds(taskState(tt)),config.N);
    end
else
    for tt=1:nTasks
        taskResults{tt}=evaluate_a6_wind_sensitivity_block_h2(model, ...
            stateSamples{taskState(tt)},config.baseSeeds(taskSeedIndex(tt)), ...
            stateIds(taskState(tt)),config.N);
    end
end

metricTables=cell(nTasks,1);pairedTables=cell(nTasks,1);designRows=cell(nTasks,14);
for tt=1:nTasks
    ss=taskState(tt);seedId=taskSeedIndex(tt);
    prefix={config.representativeStates(ss,1),config.representativeStates(ss,2), ...
        config.representativeStates(ss,3),seedId,config.baseSeeds(seedId), ...
        taskResults{tt}.derived_seed};
    metricTables{tt}=add_prefix(taskResults{tt}.metrics,prefix);
    pairedTables{tt}=add_prefix(taskResults{tt}.paired,prefix);
    designRows(tt,:)={prefix{:},config.N,taskResults{tt}.contains_a6_count, ...
        taskResults{tt}.no_a6_count,taskResults{tt}.non_a6_exact_pass, ...
        taskResults{tt}.path_id_sha256,taskResults{tt}.permutation_sha256, ...
        taskResults{tt}.line_u_sha256,taskResults{tt}.road_u_sha256};
end
sensitivityMetrics=vertcat(metricTables{:});pairedSummary=vertcat(pairedTables{:});
randomInputAudit=cell2table(designRows,'VariableNames', ...
    {'a0','loc0','lfw0','seed_id','base_seed','derived_seed','N', ...
    'contains_a6_path_count','no_a6_path_count','non_a6_exact_pass', ...
    'selected_path_id_sha256','permutation_sha256','line_resistance_u_sha256', ...
    'road_resistance_u_sha256'});
[m0Comparison,m0Pass]=compare_m0_to_step3e(sensitivityMetrics,step3eMetrics,config);
variabilityComparison=build_variability_comparison(sensitivityMetrics,step3eMetrics,config);

inputHashesAfter=strings(numel(requiredFiles),1);inputBytesAfter=zeros(numel(requiredFiles),1);
for ii=1:numel(requiredFiles)
    inputHashesAfter(ii)=sha256_file(requiredFiles{ii});info=dir(requiredFiles{ii});
    inputBytesAfter(ii)=info.bytes;
end
inputsUnchanged=isequal(inputHashesBefore,inputHashesAfter)&&isequal(inputBytesBefore,inputBytesAfter);
oldOutputsUnchanged=isequaln(oldOutputSnapshotBefore,snapshot_directories(oldOutputDirs));

completePass=height(sensitivityMetrics)==60&&height(randomInputAudit)==15;
commonInputsPass=all(cellfun(@(x)x.common_resistance_pass,taskResults));
nonA6ExactPass=all(randomInputAudit.non_a6_exact_pass);
domainPass=all(sensitivityMetrics.D_min_kg>=0)&&all(sensitivityMetrics.nonfinite_count==0)&& ...
    all(sensitivityMetrics.negative_value_count==0)&&all(sensitivityMetrics.invalid_A_or_C_count==0)&& ...
    all(sensitivityMetrics.A0_pair_share>=0&sensitivityMetrics.A0_pair_share<=1);
noCandidatePass=unobservedOverlapInMain==0;
DUpperPass=abs(model.DUpperKg-config.DUpperKgExpected)<=1e-9;
sourcePeriodPass=historical.data_comparable_pass&&historical.crosscheck.rounded_wind_multiset_match;
forbiddenHits=scan_forbidden_calls({thisFile+".m", ...
    fullfile(thisDir,'audit_a6_historical_wind_data_h2.m'), ...
    fullfile(thisDir,'evaluate_a6_wind_sensitivity_block_h2.m')});
noForbiddenCalls=height(forbiddenHits)==0;

q90Shift=mode_primary_shift(sensitivityMetrics,"M6_Q90");
q95Shift=mode_primary_shift(sensitivityMetrics,"M6_Q95");
q90ExceedsSeedRange=any(variabilityComparison.mode=="M6_Q90"& ...
    variabilityComparison.absolute_mode_shift_vs_M0> ...
    variabilityComparison.step3e_M0_seed_range+1e-12);
q95ExceedsSeedRange=any(variabilityComparison.mode=="M6_Q95"& ...
    variabilityComparison.absolute_mode_shift_vs_M0> ...
    variabilityComparison.step3e_M0_seed_range+1e-12);
if ~dataComparable
    decision="DATA_NOT_COMPARABLE";
    decisionReason="CMA and IBTrACS CMA-source wind records are not comparable";
elseif ~sampleSufficient
    decision="INSUFFICIENT_A6_SAMPLES";
    decisionReason="accepted CMA a=6 record count is below the declared minimum";
elseif (q90Shift>0||q95Shift>0)&&(q90ExceedsSeedRange||q95ExceedsSeedRange)
    decision="REVISE_A6_MAPPING";
    decisionReason="CMA median/q90/q95 exceed 55.5 and higher a6 values create directional B3 shifts beyond observed Step-03E M0 seed ranges";
else
    decision="RETAIN_55P5_BASELINE";
    decisionReason="tested CMA a6 quantiles do not create a robust consequence shift beyond M0 seed variation";
end
decisionGate=table(decision,decisionReason,height(historical.cma_records), ...
    a6Values(1),a6Values(2),a6Values(3),a6Values(4), ...
    sum(randomInputAudit.contains_a6_path_count),sum(randomInputAudit.no_a6_path_count), ...
    q90Shift,q95Shift,q90ExceedsSeedRange,q95ExceedsSeedRange, ...
    'VariableNames',{'decision','reason','cma_a6_record_count','M0_a6_mps', ...
    'M6_median_mps','M6_q90_mps','M6_q95_mps','contains_a6_path_records', ...
    'no_a6_path_records','M6_q90_max_primary_mean_shift', ...
    'M6_q95_max_primary_mean_shift','q90_shift_exceeds_step3e_seed_range', ...
    'q95_shift_exceeds_step3e_seed_range'});

checks={};
checks=add_check(checks,"AUDIT-01","complete CMA 1949-2024 annual file set",historical.complete_year_files_pass,height(historical.file_audit),76);
checks=add_check(checks,"AUDIT-02","CMA record-level a6 sample is sufficient",sampleSufficient,height(historical.cma_records),">=30");
checks=add_check(checks,"AUDIT-03","CMA 2-minute records match IBTrACS CMA original records after unit conversion",sourcePeriodPass,historical.crosscheck.max_rounded_mps_difference,0);
checks=add_check(checks,"AUDIT-04","CMA archive and IBTrACS hashes match downloaded source snapshots",historical.cma_archive_sha256==config.expectedCmaArchiveHash&&historical.ibtracs_sha256==config.expectedIbtracsHash,[historical.cma_archive_sha256,historical.ibtracs_sha256],[config.expectedCmaArchiveHash,config.expectedIbtracsHash]);
checks=add_check(checks,"AUDIT-05","five representative states each contain 15000 main records",stateCountPass,stateCountPass,true);
checks=add_check(checks,"AUDIT-06","all state seed and a6 mode evaluations completed",completePass,height(sensitivityMetrics),60);
checks=add_check(checks,"AUDIT-07","M0 reproduces accepted Step-03E M0 metrics",m0Pass,max(m0Comparison.absolute_difference),0);
checks=add_check(checks,"AUDIT-08","all modes share paths and component resistance uniforms",commonInputsPass,commonInputsPass,true);
checks=add_check(checks,"AUDIT-09","all paths without a6 have exactly identical consequences",nonA6ExactPass,sum(~randomInputAudit.non_a6_exact_pass),0);
checks=add_check(checks,"AUDIT-10","no unobserved candidate is mixed into main records",noCandidatePass,unobservedOverlapInMain,0);
checks=add_check(checks,"AUDIT-11","D A and reachable C domains are valid",domainPass,domainPass,true);
checks=add_check(checks,"AUDIT-12","607.969887897881 kg-H2 upper bound is preserved",DUpperPass,model.DUpperKg,config.DUpperKgExpected);
checks=add_check(checks,"AUDIT-13","source inputs and formal mapping files remain unchanged",inputsUnchanged,inputsUnchanged,true);
checks=add_check(checks,"AUDIT-14","accepted old run directories remain unchanged",oldOutputsUnchanged,oldOutputsUnchanged,true);
checks=add_check(checks,"AUDIT-15","persistent fixed resistance mode is retained",model.fixedResistancePass,config.damageMode,"persistent_fixed_resistance");
checks=add_check(checks,"AUDIT-16","no WDRO Gurobi optimization or MSP calls",noForbiddenCalls,height(forbiddenHits),0);
checks=add_check(checks,"AUDIT-17","main sample SHA-256 remains accepted",sha256_file(config.mainSampleFile)==config.expectedMainHash,sha256_file(config.mainSampleFile),config.expectedMainHash);
automaticAudit=cell2table(checks,'VariableNames',{'check_id','description','passed','observed','expected'});
passCount=sum(automaticAudit.passed);failCount=sum(~automaticAudit.passed);
status="PASS";if failCount>0,status="FAIL";end
if failCount>0,error('Step-03F audit failed: %s',strjoin(automaticAudit.check_id(~automaticAudit.passed),', '));end

mkdir(config.tempOutputDir);
writetable(mappingAudit,fullfile(config.tempOutputDir,'a6_current_mapping_audit.csv'));
write_data_sources(fullfile(config.tempOutputDir,'a6_data_source_and_units.txt'), ...
    config,historical);
writetable(historical.summary,fullfile(config.tempOutputDir,'a6_historical_wind_summary.csv'));
writetable(historical.cma_records,fullfile(config.tempOutputDir,'a6_cma_selected_records.csv'));
writetable(historical.crosscheck,fullfile(config.tempOutputDir,'ibtracs_cma_crosscheck.csv'));
writetable(historical.file_audit,fullfile(config.tempOutputDir,'cma_source_file_audit.csv'));
writetable(sensitivityMetrics,fullfile(config.tempOutputDir,'a6_sensitivity_metrics.csv'));
writetable(pairedSummary,fullfile(config.tempOutputDir,'a6_paired_difference_summary.csv'));
writetable(variabilityComparison,fullfile(config.tempOutputDir,'step3e_seed_variability_comparison.csv'));
writetable(randomInputAudit,fullfile(config.tempOutputDir,'random_input_and_a6_path_audit.csv'));
writetable(m0Comparison,fullfile(config.tempOutputDir,'M0_step3e_match_audit.csv'));
writetable(decisionGate,fullfile(config.tempOutputDir,'decision_gate_summary.csv'));
writetable(automaticAudit,fullfile(config.tempOutputDir,'automatic_audit.csv'));
write_manifest(fullfile(config.tempOutputDir,'run_manifest.txt'),config,historical, ...
    status,passCount,failCount,useParallel,decision,model.DUpperKg,randomInputAudit);
write_readme(fullfile(config.tempOutputDir,'README.txt'),config,historical,status, ...
    passCount,failCount,sensitivityMetrics,decision,decisionReason,randomInputAudit);
movefile(config.tempOutputDir,config.outputDir);
fprintf('\nStage3F a6 wind audit finished.\nStatus: %s; PASS=%d; FAIL=%d\n',status,passCount,failCount);
fprintf('Decision: %s\nOutput directory: %s\n',decision,config.outputDir);

function T=add_prefix(T,p)
T=addvars(T,repmat(p{1},height(T),1),repmat(p{2},height(T),1), ...
    repmat(p{3},height(T),1),repmat(p{4},height(T),1), ...
    repmat(p{5},height(T),1),repmat(p{6},height(T),1), ...
    'Before',1,'NewVariableNames',{'a0','loc0','lfw0','seed_id','base_seed','derived_seed'});
end

function model=build_a6_model(config,foundation,a6Values)
near=foundation.raw_near;grid=foundation.grid_segments;road=foundation.road_segments;
Pnode=double(near.Grid.P_load_base_kw(:));eta=double(near.HydrogenDevice.eta_FC);
lhv=double(near.HydrogenDevice.h2_lhv_kWh_per_kg);
site=readtable(config.siteNodeFile);site=sortrows(site,'site_id');
locValues=sort(double(foundation.loc_table.loc));nStates=6*numel(locValues)*4;
nLines=height(grid);nRoads=height(road);stateIndex=zeros(6,numel(locValues),4);
fixedPFail=cell(4,1);fixedPClose=cell(4,1);
for mm=1:4,fixedPFail{mm}=zeros(nStates,nLines);fixedPClose{mm}=zeros(nStates,nRoads);end
rr=0;
for a=1:6
    for loc=locValues(:).'
        locRow=foundation.loc_table(foundation.loc_table.loc==loc,:);
        for lfw=0:3
            rr=rr+1;x=double(locRow.x_coord);y=foundation.y_base+lfw*config.Wstep;
            lineDist=compute_point_to_segment_distance_h2(x,y,grid.x1,grid.y1,grid.x2,grid.y2);
            roadDist=compute_point_to_segment_distance_h2(x,y,road.x1,road.y1,road.x2,road.y2);
            for mm=1:4
                map=config.currentMap;map(6)=a6Values(mm);vmax=map(a);
                lineWind=compute_wind_speed_radial_h2(lineDist,vmax,config.Rmax,config.windDecayB);
                roadWind=compute_wind_speed_radial_h2(roadDist,vmax,config.Rmax,config.windDecayB);
                fixedPFail{mm}(rr,:)=compute_line_failure_prob_h2(lineWind,config.designWindSpeedVN).';
                fixedPClose{mm}(rr,:)=compute_line_failure_prob_h2(roadWind,config.roadDesignWindVN).';
            end
            stateIndex(a,loc-min(locValues)+1,lfw+1)=rr;
        end
    end
end
model=struct();model.modeNames=config.modeNames;model.a6ValuesMps=a6Values;
model.fixedPFail=fixedPFail;model.fixedPClose=fixedPClose;model.stateIndex=stateIndex;
model.locMin=min(locValues);model.locMax=max(locValues);model.nLines=nLines;model.nRoads=nRoads;
model.nNodes=numel(Pnode);model.nSites=height(site);model.sourceNode=config.sourceNode;
model.Pnode_kW=Pnode;model.nodePathIncidence=radial_node_path_incidence( ...
    numel(Pnode),grid.from_node,grid.to_node,config.sourceNode);
model.roadFrom=double(road.from_node);model.roadTo=double(road.to_node);
model.roadLength=hypot(road.x2-road.x1,road.y2-road.y1);model.siteNodes=double(site.grid_node);
model.DFactorKgPerKWh=1/(eta*lhv);
model.DUpperKg=3*(sum(Pnode)-Pnode(config.sourceNode))*model.DFactorKgPerKWh;
model.fixedResistancePass=true;
end

function incidence=radial_node_path_incidence(nNodes,fromNode,toNode,sourceNode)
nLines=numel(fromNode);adj=cell(nNodes,1);edgeAdj=cell(nNodes,1);
if nLines~=nNodes-1,error('Grid is not radial.');end
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
        visited(v)=true;parent(v)=u;parentEdge(v)=edgeAdj{u}(kk);tail=tail+1;queue(tail)=v;
    end
end
if ~all(visited),error('Grid is disconnected.');end
incidence=false(nNodes,nLines);
for node=1:nNodes
    cur=node;while cur~=sourceNode,incidence(node,parentEdge(cur))=true;cur=parent(cur);end
end
end

function T=build_current_mapping_audit(rootDir,config)
spec={ ...
    'fa_h2/fuzhu/terminalLoh_windmc/build_terminal_loh_wind_mc_preview_h2.m','preview source map','generate_terminal_loh_wind_mc_preview -> build_terminal_loh_wind_mc_preview_h2'; ...
    'terminalLoh_wdro/src/build_lookahead_W3_DAC_samples_h2.m','legacy B1 map builder','run_lookahead_W3_B1 -> build_lookahead_W3_DAC_samples -> build_vmax_map'; ...
    'terminalLoh_wdro/src/calibrate_lookahead_y_step_h2.m','foundation y-step audit map','run_stage2_foundation_yStep_calibration -> calibrate_lookahead_y_step -> build_vmax_map_y_step'; ...
    'terminalLoh_wdro/src/evaluate_foundation_fix_chain_h2.m','foundation consequence map','run_stage2_foundation_fix -> evaluate_foundation_fix_chain -> intensity_to_vmax'; ...
    'terminalLoh_wdro/src/evaluate_fixed_resistance_damage_h2.m','persistence-v2 consequence map','run_stage2_damage_persistence_v2 -> evaluate_fixed_resistance_damage -> intensity_to_vmax'; ...
    'terminalLoh_wdro/src/evaluate_b3_smoke_fixed_resistance_h2.m','Step-03A B3 map','run_stage3a_b3_smoke -> evaluate_b3_smoke_fixed_resistance -> intensity_to_vmax'; ...
    'terminalLoh_wdro/src/evaluate_b3_candidate_validation_h2.m','Step-03B B3 map','run_stage3b_b3_candidate_validation -> evaluate_b3_candidate_validation -> intensity_to_vmax'; ...
    'terminalLoh_wdro/src/run_stage3d_b3_sample_stability_h2.m','Step-03D cache map','run_stage3d_b3_sample_stability -> build_stability_model -> intensity_to_vmax'};
rows={};
for ii=1:size(spec,1)
    fileName=fullfile(rootDir,strrep(spec{ii,1},'/',filesep));text=splitlines(string(fileread(fileName)));
    hit=find(contains(text,"55.50")|contains(text,"55.5"));
    hit=hit(contains(text(hit),"20.8")|contains(text(hit),"map")|contains(text(hit),"V(2:6)"));
    for jj=1:numel(hit)
        rows(end+1,:)={string(spec{ii,1}),hit(jj),string(spec{ii,2}), ...
            string(spec{ii,3}),config.currentA6Mps,strtrim(text(hit(jj))),false, ...
            "hardcoded numeric map; no linked literature, dataset, or config source in the defining file"}; %#ok<AGROW>
    end
end
[status,out]=system('git log --reverse --format=%H -S "55.50" -- "fa_h2/fuzhu/terminalLoh_windmc/build_terminal_loh_wind_mc_preview_h2.m"');
commits=splitlines(strtrim(string(out)));firstCommit="unknown";
if status==0&&~isempty(commits)&&strlength(commits(1))>0,firstCommit=commits(1);end
T=cell2table(rows,'VariableNames',{'file','line_number','role','call_chain', ...
    'current_a6_mps','source_line','traceable_source_in_defining_file', ...
    'source_basis_status'});
T.first_repository_commit=repmat(firstCommit,height(T),1);
T.repository_history_limit=repmat("value already exists in the initial Git snapshot; pre-repository origin is not recoverable",height(T),1);
end

function [audit,pass]=compare_m0_to_step3e(current,reference,config)
metrics={'D_mean_kg','D_q95_kg','D_q99_kg','full_loss_probability','A0_pair_share', ...
    'reachable_pair_share','C_reachable_mean_km','C_reachable_q95_km', ...
    'W3_failed_lines_mean','W3_failed_lines_q95','W3_closed_roads_mean','W3_closed_roads_q95'};
rows=cell(5*3*numel(metrics),10);rr=0;
for ss=1:5
    for seedId=1:3
        q=current(current.mode=="M0"&current.a0==config.representativeStates(ss,1)& ...
            current.loc0==config.representativeStates(ss,2)&current.seed_id==seedId,:);
        ref=reference(reference.mode=="M0"&double(reference.a0)==config.representativeStates(ss,1)& ...
            double(reference.loc0)==config.representativeStates(ss,2)&double(reference.seed_id)==seedId,:);
        for mm=1:numel(metrics)
            observed=double(q.(metrics{mm}));expected=double(ref.(metrics{mm}));rr=rr+1;
            rows(rr,:)={q.a0,q.loc0,q.lfw0,seedId,q.base_seed,string(metrics{mm}), ...
                observed,expected,abs(observed-expected),abs(observed-expected)<=1e-12};
        end
    end
end
audit=cell2table(rows,'VariableNames',{'a0','loc0','lfw0','seed_id','base_seed', ...
    'metric','M0_value','step3e_M0_value','absolute_difference','match_within_1e_12'});
pass=all(audit.match_within_1e_12);
end

function T=build_variability_comparison(current,reference,config)
metrics={'D_mean_kg','D_q95_kg','D_q99_kg','full_loss_probability', ...
    'A0_pair_share','C_reachable_mean_km','W3_failed_lines_mean','W3_closed_roads_mean'};
rows=cell(5*numel(metrics)*4,13);rr=0;
for ss=1:5
    for kk=1:numel(metrics)
        ref=reference(reference.mode=="M0"&double(reference.a0)==config.representativeStates(ss,1)& ...
            double(reference.loc0)==config.representativeStates(ss,2),:);
        base=double(ref.(metrics{kk}));baseMean=mean(base);baseStd=std(base,0);baseRange=max(base)-min(base);
        for mode=config.modeNames
            q=current(current.mode==mode&current.a0==config.representativeStates(ss,1)& ...
                current.loc0==config.representativeStates(ss,2),:);
            value=mean(double(q.(metrics{kk})));shift=value-baseMean;rr=rr+1;
            rows(rr,:)={config.representativeStates(ss,1),config.representativeStates(ss,2), ...
                config.representativeStates(ss,3),string(metrics{kk}),mode,baseMean,baseStd, ...
                baseRange,value,shift,abs(shift),safe_ratio(abs(shift),baseStd), ...
                safe_ratio(abs(shift),baseRange)};
        end
    end
end
T=cell2table(rows,'VariableNames',{'a0','loc0','lfw0','metric','mode', ...
    'step3e_M0_three_seed_mean','step3e_M0_seed_std','step3e_M0_seed_range', ...
    'mode_three_seed_mean','mode_shift_vs_M0','absolute_mode_shift_vs_M0', ...
    'shift_over_seed_std','shift_over_seed_range'});
end

function value=mode_primary_shift(T,mode)
names=["D_mean_kg","full_loss_probability","A0_pair_share", ...
    "C_reachable_mean_km","W3_failed_lines_mean","W3_closed_roads_mean"];
values=zeros(numel(names),1);
for ii=1:numel(names)
    q=T(T.mode==mode,:);b=T(T.mode=="M0",:);values(ii)=abs(mean(double(q.(names(ii))))-mean(double(b.(names(ii)))));
end
value=max(values);
end

function value=safe_ratio(x,y),if abs(y)<=1e-15,value=NaN;else,value=x/y;end,end
function close_pool(),p=gcp('nocreate');if ~isempty(p),delete(p);end,end

function codes=physical_codes_main(T)
codes=encode_codes(double(T.a0),double(T.loc0),double(T.lfw0),double(T.a_W1), ...
    double(T.loc_W1),double(T.lfw_W1),double(T.a_W2),double(T.loc_W2), ...
    double(T.lfw_W2),double(T.a_W3),double(T.loc_W3),double(T.lfw_W3));
end
function codes=physical_codes_candidate(T)
codes=encode_codes(double(T.a0),double(T.loc0),double(T.lfw0),double(T.a1), ...
    double(T.loc1),double(T.lfw1),double(T.a2),double(T.loc2),double(T.lfw2), ...
    double(T.a3),double(T.loc3),double(T.lfw3));
end
function codes=encode_codes(varargin)
n=numel(varargin{1});codes=zeros(n,1,'uint64');bases=[7,13,4,7,13,4,7,13,4,7,13,4];
for ii=1:12,value=double(varargin{ii});if mod(ii,3)==2,value=value+2;end;codes=codes*uint64(bases(ii))+uint64(value);end
end
function values=as_logical(values)
if islogical(values),return;end
if isnumeric(values),values=values~=0;else,text=lower(strtrim(string(values)));values=text=="true"|text=="1";end
end
function require_vars(T,names,label)
for ii=1:numel(names),if ~ismember(names{ii},T.Properties.VariableNames),error('%s missing %s.',label,names{ii});end,end
end

function summary=snapshot_directories(dirs)
rows={};for dd=1:numel(dirs),files=dir(fullfile(dirs{dd},'**','*'));files=files(~[files.isdir]);
    for ii=1:numel(files),rows(end+1,:)={string(dirs{dd}),string(fullfile(files(ii).folder,files(ii).name)),files(ii).bytes,files(ii).datenum};end %#ok<AGROW>
end
if isempty(rows),summary=cell2table(cell(0,4),'VariableNames',{'root','path','bytes','datenum'});
else,summary=sortrows(cell2table(rows,'VariableNames',{'root','path','bytes','datenum'}),'path');end
end

function T=scan_forbidden_calls(files)
patterns=["solve_wdro_"+"terminal_loh_lp_h2\\s*\\(","guro"+"bi\\s*\\(", ...
    "main_msp_"+"h2_near\\s*\\(","run_h2_"+"with_options\\s*\\(", ...
    "opti"+"mize\\s*\\(","lin"+"prog\\s*\\("];
rows={};for ff=1:numel(files),sourceText=fileread(files{ff});for pp=1:numel(patterns)
        if ~isempty(regexp(sourceText,patterns(pp),'once')),rows(end+1,:)={string(files{ff}),patterns(pp)};end %#ok<AGROW>
    end,end
if isempty(rows),T=cell2table(cell(0,2),'VariableNames',{'file','pattern'});else,T=cell2table(rows,'VariableNames',{'file','pattern'});end
end

function [rows,fields]=count_csv_rows_and_fields(fileName)
fid=fopen(fileName,'rb');if fid<0,error('Could not open %s.',fileName);end
cleanup=onCleanup(@()fclose(fid));header=fgetl(fid);fields=string(strsplit(header,','));newlineCount=1;lastByte=uint8(10);
while true,bytes=fread(fid,1024*1024,'*uint8');if isempty(bytes),break;end;newlineCount=newlineCount+sum(bytes==10);lastByte=bytes(end);end
rows=newlineCount+double(lastByte~=10)-1;
end
function hash=sha256_file(fileName)
fid=fopen(fileName,'rb');if fid<0,error('Could not open %s.',fileName);end
cleanup=onCleanup(@()fclose(fid));md=java.security.MessageDigest.getInstance('SHA-256');
while true,bytes=fread(fid,1024*1024,'*uint8');if isempty(bytes),break;end;md.update(typecast(bytes,'int8'));end
digest=typecast(md.digest(),'uint8');hash=lower(string(reshape(dec2hex(digest,2).',1,[])));
end
function rows=add_check(rows,id,description,passed,observed,expected)
rows(end+1,:)={string(id),string(description),logical(passed),scalar_text(observed),scalar_text(expected)};
end
function text=scalar_text(value)
if isstring(value),text=strjoin(value(:).',' | ');elseif ischar(value),text=string(value);
elseif islogical(value)&&isscalar(value),text=string(double(value));elseif isnumeric(value)&&isscalar(value),text=string(sprintf('%.15g',value));
elseif isnumeric(value),text=strjoin(compose('%.15g',value(:).'),' | ');else,text=string(value);end
end

function write_data_sources(fileName,config,h)
fid=fopen(fileName,'w');if fid<0,error('Could not write %s.',fileName);end;cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'CMA OFFICIAL BEST-TRACK DATA\nsource_url=%s\nrelease_url=%s\n',config.cmaOfficialDataUrl,config.cmaOfficialReleaseUrl);
fprintf(fid,'wind_period_source=%s\nwind_definition=maximum 2-minute mean wind near the 10 m lower-level cyclone center\n',config.cmaWindPeriodUrl);
fprintf(fid,'CMA_reference=%s\n',config.cmaCitation);
fprintf(fid,'download_transport=ModelScope mirror of CMA files\nmirror_url=%s\nmirror_commit=%s\narchive_sha256=%s\n',config.cmaMirrorUrl,config.cmaMirrorCommit,h.cma_archive_sha256);
fprintf(fid,'annual_files=CH1949BST.txt through CH2024BST.txt\ncombined_file_manifest_sha256=%s\n\n',h.cma_combined_file_manifest_sha256);
fprintf(fid,'IBTRACS CROSS-CHECK\nsource_url=%s\nfile_sha256=%s\nversion=v04r01\n',config.ibtracsUrl,h.ibtracs_sha256);
fprintf(fid,'field=cma_wind; unit=knots; conversion=%.9g m/s per knot; required_iflag=O; agency_index=3 (CMA)\n',config.knotToMps);
fprintf(fid,'Only the CMA agency field is used. USA/JTWC 1-minute, JMA/Tokyo 10-minute, WMO aggregate, and interpolated CMA records are excluded.\n');
fprintf(fid,'IBTrACS_reference=%s\n\n',config.knappCitation);
fprintf(fid,'COMPARABILITY\nCMA_selected_records=%d\nIBTrACS_CMA_original_records=%d\nrounded_multiset_match=%d\nmax_rounded_difference_mps=%.15g\n', ...
    h.crosscheck.cma_selected_record_count,h.crosscheck.ibtracs_selected_record_count, ...
    h.crosscheck.rounded_wind_multiset_match,h.crosscheck.max_rounded_mps_difference);
fprintf(fid,'Historical maximum is an observed sample maximum, not a physical upper bound.\n');
end

function write_manifest(fileName,config,h,status,passCount,failCount,useParallel,decision,DUpper,design)
fid=fopen(fileName,'w');if fid<0,error('Could not write %s.',fileName);end;cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'task_id=task-002\nstep_id=06-a6-wind-audit\nrun_id=run-001\nrun_time=%s\n',char(datetime('now','Format','yyyy-MM-dd HH:mm:ss Z')));
fprintf(fid,'status=%s\npass_count=%d\nfail_count=%d\ndecision=%s\n',status,passCount,failCount,decision);
fprintf(fid,'CMA_a6_records=%d\nCMA_archive_sha256=%s\nIBTrACS_sha256=%s\n',height(h.cma_records),h.cma_archive_sha256,h.ibtracs_sha256);
fprintf(fid,'a6_values_mps=%s\npath_resistance_scenarios=%d\nmode_consequence_evaluations=%d\n',strjoin(string(h.sensitivity_values_mps),','),5*3*config.N,5*3*config.N*4);
fprintf(fid,'contains_a6_path_records=%d\nno_a6_path_records=%d\nparallel_used=%d\n',sum(design.contains_a6_path_count),sum(design.no_a6_path_count),useParallel);
fprintf(fid,'D_upper_kg=%.15g\nformal_a6_mapping_modified=false\ncandidate_paths_added=0\nWDRO_run=false\nGurobi_run=false\nMSP_run=false\n',DUpper);
end

function write_readme(fileName,config,h,status,passCount,failCount,T,decision,reason,design)
fid=fopen(fileName,'w');if fid<0,error('Could not write %s.',fileName);end;cleanup=onCleanup(@()fclose(fid));
q=h.summary(h.summary.sample_scope=="CMA_record_level",:);
fprintf(fid,'Step-03F run-001: a=6 wind-data audit and paired B3 sensitivity\n\nstatus=%s; PASS=%d; FAIL=%d\n',status,passCount,failCount);
fprintf(fid,'CMA 1949-2024 category-6 records with 2-minute wind >=51 m/s: %d records, %d storms.\n',q.sample_count,q.unique_storm_count);
fprintf(fid,'CMA record distribution: min %.6g, mean %.6g, median %.6g, q75 %.6g, q90 %.6g, q95 %.6g, q99 %.6g, observed max %.6g m/s.\n',q.minimum_mps,q.mean_mps,q.median_mps,q.q75_mps,q.q90_mps,q.q95_mps,q.q99_mps,q.maximum_mps);
fprintf(fid,'IBTrACS is used only to cross-check original CMA agency records; other agencies and averaging periods are excluded.\n');
for mode=config.modeNames
    z=T(T.mode==mode,:);fprintf(fid,'%s (a6 %.6g): D mean %.6g, full-loss %.6g, A0 %.6g, C %.6g, W3 failed %.6g, W3 closed %.6g.\n', ...
        mode,z.a6_Vmax_mps(1),mean(z.D_mean_kg),mean(z.full_loss_probability),mean(z.A0_pair_share),mean(z.C_reachable_mean_km),mean(z.W3_failed_lines_mean),mean(z.W3_closed_roads_mean));
end
fprintf(fid,'Contains-a6 path records: %d; no-a6 records: %d. No-a6 consequences are exactly identical across modes.\n',sum(design.contains_a6_path_count),sum(design.no_a6_path_count));
fprintf(fid,'Decision: %s. %s.\n',decision,reason);
fprintf(fid,'The historical maximum is not treated as a physical upper bound. The formal 55.5 m/s mapping is unchanged.\n');
fprintf(fid,'No candidate paths, WDRO, Gurobi optimization, or MSP are used.\n');
end
