%% Step-03J run-001: freeze formal B3 datasets for the WDRO interface.
clear;clc;
thisFile=mfilename('fullpath');thisDir=fileparts(thisFile);
moduleDir=fileparts(thisDir);rootDir=fileparts(moduleDir);
addpath(rootDir);addpath(thisDir);
addpath(fullfile(rootDir,'fa_h2','fuzhu','terminalLoh_windmc'));

config=struct();
config.outputDir=fullfile(moduleDir,'output','stage3j_wdro_input_freeze','run-001');
config.tempOutputDir=config.outputDir+".tmp";
config.mainSampleFile=fullfile(moduleDir,'output','stage2a2_W3_path_sampling', ...
    'run-002','main_path_samples.csv');
config.candidatePoolFile=fullfile(moduleDir,'output', ...
    'stage2b_tail_candidate_design','run-005','unique_tail_paths.csv');
config.formalWindConfigFile=fullfile(moduleDir,'config','formal_b3_wind_modes.csv');
config.step3iMetricsFile=fullfile(moduleDir,'output', ...
    'stage3i_formal_stagewise_random_b3','run-001','stability_metrics_by_state.csv');
config.step3iAuditFile=fullfile(moduleDir,'output', ...
    'stage3i_formal_stagewise_random_b3','run-001','automatic_audit.csv');
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
config.baseSeeds=[20260723,20260724,20260725];
config.datasetRoles=["nominal","validation-1","validation-2"];
config.csvNames=["wdro_nominal_input.csv","wdro_validation_1.csv","wdro_validation_2.csv"];
config.matNames=["wdro_nominal_input_DAC.mat","wdro_validation_1_DAC.mat", ...
    "wdro_validation_2_DAC.mat"];
config.windSeedOffset=330000000;config.maxWorkers=12;
config.Rmax=40;config.Wstep=40;config.sliceDurationH=1;config.HresTotalH=3;
config.WstepValues=40;config.recommendedWstep=40;config.comparisonWstep=45;
config.stageNames=["lf7","W1","W2","W3"];config.stageOffsets=[0,1,2,3];
config.warningDistanceKmEq=100;config.distanceMethod="point_to_segment";
config.windDecayB=0.6;config.designWindSpeedVN=25;config.roadDesignWindVN=30;
config.sourceNode=1;config.damageMode="persistent_fixed_resistance";
config.demandToleranceKg=1e-10;

requiredFiles={config.mainSampleFile,config.candidatePoolFile, ...
    config.formalWindConfigFile,config.step3iMetricsFile,config.step3iAuditFile, ...
    config.warningSolutionFile,config.warningGeometryFile,config.warningRankingFile, ...
    config.warningStageSummaryFile,config.warningDiagnosticsFile, ...
    config.warningRankingSourceFile,config.locCoordinateFile,config.nearInputFile, ...
    config.roadEdgeFile,config.siteNodeFile, ...
    fullfile(thisDir,'load_formal_b3_wind_config_h2.m'), ...
    fullfile(thisDir,'evaluate_frozen_wdro_dataset_block_h2.m'), ...
    fullfile(thisDir,'load_frozen_b3_wdro_dataset_h2.m'), ...
    fullfile(rootDir,'fa_h2','fuzhu','terminalLoh_windmc','compute_wind_speed_radial_h2.m'), ...
    fullfile(rootDir,'fa_h2','fuzhu','terminalLoh_windmc','compute_line_failure_prob_h2.m')};
for ii=1:numel(requiredFiles),if ~isfile(requiredFiles{ii}),error('Missing input: %s',requiredFiles{ii});end,end
if isfolder(config.outputDir)||isfolder(config.tempOutputDir),error('Step-03J run-001 output already exists.');end
windConfig=load_formal_b3_wind_config_h2(config.formalWindConfigFile);
if windConfig.defaultMode~="stagewise_random_triangular",error('Formal B3 wind default mismatch.');end

inputHashesBefore=strings(numel(requiredFiles),1);inputBytesBefore=zeros(numel(requiredFiles),1);
for ii=1:numel(requiredFiles),inputHashesBefore(ii)=sha256_file(requiredFiles{ii});q=dir(requiredFiles{ii});inputBytesBefore(ii)=q.bytes;end
oldOutputDirs={fullfile(moduleDir,'output','stage3d_b3_sample_stability','run-001'), ...
    fullfile(moduleDir,'output','stage3i_formal_stagewise_random_b3','run-001'), ...
    fullfile(moduleDir,'output','stage3h_stagewise_random_wind','run-001'), ...
    fullfile(moduleDir,'output','stage3b_b3_candidate_validation','run-001')};
oldOutputSnapshotBefore=snapshot_directories(oldOutputDirs);

[mainRows,mainFields]=count_csv_rows_and_fields(config.mainSampleFile);
mainHash=sha256_file(config.mainSampleFile);candidateHash=sha256_file(config.candidatePoolFile);
fprintf('INPUT|path=%s|rows=%d|fields=%s|sha256=%s\n',config.mainSampleFile, ...
    mainRows,strjoin(mainFields,','),mainHash);
if mainRows~=525000||mainHash~=config.expectedMainHash||candidateHash~=config.expectedCandidateHash
    error('Accepted main sample or candidate pool identity mismatch.');
end
step3iAudit=readtable(config.step3iAuditFile,'TextType','string');
if any(~as_logical(step3iAudit.passed)),error('Accepted Step-03I audit contains FAIL rows.');end

mainSample=readtable(config.mainSampleFile);
candidatePool=readtable(config.candidatePoolFile,'TextType','string');
step3iMetrics=readtable(config.step3iMetricsFile,'TextType','string');
states=sortrows(unique(mainSample(:,{'a0','loc0','lfw0'}),'rows'),{'a0','loc0','lfw0'});
if height(states)~=35,error('Expected 35 initial states.');end
stateSamples=cell(35,1);stateCountPass=true;
for ss=1:35
    mask=mainSample.a0==states.a0(ss)&mainSample.loc0==states.loc0(ss)& ...
        mainSample.lfw0==states.lfw0(ss);
    stateSamples{ss}=mainSample(mask,{'a0','loc0','lfw0','path_id','a_W1','a_W2','a_W3', ...
        'loc_W1','loc_W2','loc_W3','lfw_W1','lfw_W2','lfw_W3'});
    stateCountPass=stateCountPass&&height(stateSamples{ss})==15000;
end
observedCodes=physical_codes_candidate(candidatePool(as_logical(candidatePool.is_observed_candidate),:));
unobservedCodes=physical_codes_candidate(candidatePool(as_logical(candidatePool.is_unobserved_candidate),:));
clear mainSample candidatePool;

foundation=build_foundation_fix_coordinates_h2(config);
model=build_freeze_model(config,foundation,windConfig);
mkdir(config.tempOutputDir);
useParallel=license('test','Distrib_Computing_Toolbox');pool=[];
if useParallel
    cluster=parcluster('local');workerCount=min(config.maxWorkers,cluster.NumWorkers);
    pool=gcp('nocreate');if isempty(pool),pool=parpool('local',workerCount);end
    cleanupPool=onCleanup(@()close_pool()); %#ok<NASGU>
end

seedRows=cell(105,18);weightRows=cell(105,10);candidateRows=cell(3,8);
metricRows=cell(35*3*13,12);mr=0;sr=0;wr=0;
roleSummaryRows=cell(3,8);pathOrderSignatures=strings(3,1);
for roleId=1:3
    role=config.datasetRoles(roleId);baseSeed=config.baseSeeds(roleId);
    fprintf('BEGIN_FREEZE_ROLE|role=%s|seed=%d|states=35|records=525000\n',role,baseSeed);
    blockResults=cell(35,1);
    if useParallel
        parfor ss=1:35
            blockResults{ss}=evaluate_frozen_wdro_dataset_block_h2(model, ...
                stateSamples{ss},baseSeed,ss,config.windSeedOffset,config.demandToleranceKg);
        end
    else
        for ss=1:35
            blockResults{ss}=evaluate_frozen_wdro_dataset_block_h2(model, ...
                stateSamples{ss},baseSeed,ss,config.windSeedOffset,config.demandToleranceKg);
        end
    end

    csvFile=fullfile(config.tempOutputDir,config.csvNames(roleId));
    matFile=fullfile(config.tempOutputDir,config.matNames(roleId));
    sidecar=matfile(matFile,'Writable',true);totalRows=525000;
    sidecar.D_node_kg(totalRows,model.nNodes)=0;
    sidecar.A_site_node(totalRows,model.nSites,model.nNodes)=false;
    sidecar.C_site_node_km(totalRows,model.nSites,model.nNodes)=0;
    sidecar.path_id(totalRows,1)=uint32(0);sidecar.initial_state_id(totalRows,1)=uint8(0);
    blockOrderHashes=strings(35,1);observedCount=0;unobservedCount=0;
    for ss=1:35
        result=blockResults{ss};scenario=result.scenario;
        [scenario,order]=sortrows(scenario,'path_id');
        codes=physical_codes_main(scenario);
        observed=ismember(codes,observedCodes);unobserved=ismember(codes,unobservedCodes);
        observedCount=observedCount+sum(observed);unobservedCount=unobservedCount+sum(unobserved);
        scenario.scenario_id_in_state=(1:15000).';
        scenario.base_joint_seed=repmat(baseSeed,15000,1);
        scenario.dataset_role=repmat(role,15000,1);
        scenario.is_observed_candidate=observed;
        vars={'initial_state_id','initial_state','a0','loc0','lfw0','path_id', ...
            'scenario_id_in_state','joint_stream_position','a_W1','loc_W1','lfw_W1', ...
            'a_W2','loc_W2','lfw_W2','a_W3','loc_W3','lfw_W3', ...
            'wind_W1_mps','wind_W2_mps','wind_W3_mps','wind_seed','resistance_seed', ...
            'base_joint_seed','D_Hres3h_total_kg','A_reachable_share', ...
            'C_reachable_mean_km','A0_stage_pair_share','C_stage_reachable_mean_km', ...
            'W3_failed_line_count','W3_closed_road_count','D_upper_bound_hit', ...
            'sample_weight','is_observed_candidate','dataset_role'};
        out=scenario(:,vars);
        if ss==1,writetable(out,csvFile);else,writetable(out,csvFile,'WriteMode','append','WriteVariableNames',false);end
        rows=(ss-1)*15000+(1:15000);
        sidecar.D_node_kg(rows,:)=result.D_node_kg(order,:);
        sidecar.A_site_node(rows,:,:)=result.A_site_node(order,:,:);
        sidecar.C_site_node_km(rows,:,:)=result.C_site_node_km(order,:,:);
        sidecar.path_id(rows,1)=uint32(scenario.path_id);
        sidecar.initial_state_id(rows,1)=uint8(ss);
        key=double([scenario.a0,scenario.loc0,scenario.lfw0,scenario.path_id, ...
            scenario.a_W1,scenario.loc_W1,scenario.lfw_W1,scenario.a_W2, ...
            scenario.loc_W2,scenario.lfw_W2,scenario.a_W3,scenario.loc_W3,scenario.lfw_W3]);
        blockOrderHashes(ss)=sha256_double(key);
        sr=sr+1;seedRows(sr,1:14)={role,roleId,baseSeed,ss,states.a0(ss),states.loc0(ss), ...
            states.lfw0(ss),result.wind_seed,result.resistance_seed,result.permutation_sha256, ...
            result.q_W1_sha256,result.q_W2_sha256,result.q_W3_sha256,blockOrderHashes(ss)};
        seedRows(sr,15:18)={result.stagewise_q_pass,result.wind_bounds_pass, ...
            result.a6_upper_pass,result.domain_pass};
        wr=wr+1;weightRows(wr,:)={role,ss,states.a0(ss),states.loc0(ss),states.lfw0(ss), ...
            15000,min(out.sample_weight),max(out.sample_weight),sum(out.sample_weight), ...
            abs(sum(out.sample_weight)-1)<=1e-12};
        metricNames=result.metrics.Properties.VariableNames;
        ref=step3iMetrics(double(step3iMetrics.a0)==states.a0(ss)& ...
            double(step3iMetrics.loc0)==states.loc0(ss)&double(step3iMetrics.lfw0)==states.lfw0(ss)& ...
            double(step3iMetrics.seed_id)==roleId&double(step3iMetrics.N)==15000,:);
        if height(ref)~=1,error('Missing Step-03I N15000 reference.');end
        for mm=1:numel(metricNames)
            metric=metricNames{mm};observedValue=double(result.metrics.(metric));
            expectedValue=double(ref.(metric));mr=mr+1;
            metricRows(mr,:)={role,ss,states.a0(ss),states.loc0(ss),states.lfw0(ss), ...
                roleId,baseSeed,string(metric),observedValue,expectedValue, ...
                abs(observedValue-expectedValue),abs(observedValue-expectedValue)<=1e-12};
        end
    end
    pathOrderSignatures(roleId)=sha256_text(strjoin(blockOrderHashes,"|"));
    [csvRows,~]=count_csv_rows_and_fields(csvFile);
    csvInfo=dir(csvFile);matInfo=dir(matFile);
    roleSummaryRows(roleId,:)={role,baseSeed,csvRows,35,csvInfo.bytes, ...
        matInfo.bytes,sha256_file(csvFile),sha256_file(matFile)};
    candidateRows(roleId,:)={role,csvRows,observedCount,unobservedCount, ...
        0,observedCount==268,unobservedCount==0,"candidate identity follows canonical main records"};
    clear blockResults sidecar;
end

seedMap=cell2table(seedRows,'VariableNames',{'dataset_role','seed_group','base_joint_seed', ...
    'initial_state_id','a0','loc0','lfw0','wind_seed','resistance_seed', ...
    'step3i_permutation_sha256','q_W1_sha256','q_W2_sha256','q_W3_sha256', ...
    'canonical_path_order_block_sha256','stagewise_q_pass','wind_bounds_pass', ...
    'a6_upper_pass','DAC_domain_pass'});
stateWeightAudit=cell2table(weightRows,'VariableNames',{'dataset_role', ...
    'initial_state_id','a0','loc0','lfw0','record_count','minimum_weight', ...
    'maximum_weight','weight_sum','passed'});
candidatePresenceAudit=cell2table(candidateRows,'VariableNames',{'dataset_role', ...
    'record_count','observed_candidate_record_count','unobserved_candidate_record_count', ...
    'external_candidate_rows_appended','observed_count_matches_268', ...
    'unobserved_count_is_zero','definition'});
step3iReproductionAudit=cell2table(metricRows,'VariableNames',{'dataset_role', ...
    'initial_state_id','a0','loc0','lfw0','seed_group','base_joint_seed','metric', ...
    'frozen_value','step3i_value','absolute_difference','passed'});
roleSummary=cell2table(roleSummaryRows,'VariableNames',{'dataset_role', ...
    'base_joint_seed','record_count','initial_state_count','csv_bytes','dac_mat_bytes', ...
    'csv_sha256','dac_mat_sha256'});
schemaDescription=build_schema_description();

loaderRows=cell(3,7);
for roleId=1:3
    csvFile=fullfile(config.tempOutputDir,config.csvNames(roleId));
    matFile=fullfile(config.tempOutputDir,config.matNames(roleId));
    [samples,meta]=load_frozen_b3_wdro_dataset_h2(csvFile,matFile, ...
        states.a0(1),states.loc0(1),states.lfw0(1));
    loaderRows(roleId,:)={config.datasetRoles(roleId),samples.R,samples.I,samples.N, ...
        sum(samples.sampleWeights),all(isfinite(samples.C_raw(samples.A>0.5))), ...
        height(meta)==15000};
end
loaderCompatibilityAudit=cell2table(loaderRows,'VariableNames',{'dataset_role', ...
    'R','I','N','weight_sum','finite_reachable_C','metadata_row_count_pass'});

inputHashesAfter=strings(numel(requiredFiles),1);inputBytesAfter=zeros(numel(requiredFiles),1);
for ii=1:numel(requiredFiles),inputHashesAfter(ii)=sha256_file(requiredFiles{ii});q=dir(requiredFiles{ii});inputBytesAfter(ii)=q.bytes;end
oldOutputSnapshotAfter=snapshot_directories(oldOutputDirs);
inputsUnchanged=isequal(inputHashesBefore,inputHashesAfter)&&isequal(inputBytesBefore,inputBytesAfter);
oldOutputsUnchanged=isequaln(oldOutputSnapshotBefore,oldOutputSnapshotAfter);
roleCountPass=all(roleSummary.record_count==525000)&all(roleSummary.initial_state_count==35);
stateWeightPass=height(stateWeightAudit)==105&&all(stateWeightAudit.record_count==15000)&all(stateWeightAudit.passed);
pathOrderPass=numel(unique(pathOrderSignatures))==1;
seedPass=isequal(double(roleSummary.base_joint_seed).',config.baseSeeds);
candidatePass=all(candidatePresenceAudit.unobserved_count_is_zero)& ...
    all(candidatePresenceAudit.observed_count_matches_268);
step3iPass=all(step3iReproductionAudit.passed);
loaderPass=all(loaderCompatibilityAudit.R==15000&loaderCompatibilityAudit.I==4& ...
    loaderCompatibilityAudit.N==33&abs(loaderCompatibilityAudit.weight_sum-1)<=1e-12& ...
    loaderCompatibilityAudit.finite_reachable_C&loaderCompatibilityAudit.metadata_row_count_pass);
windPass=all(seedMap.wind_seed~=seedMap.resistance_seed);
stagewiseQPass=all(seedMap.stagewise_q_pass);
windBoundsPass=all(seedMap.wind_bounds_pass);
a6UpperPass=all(seedMap.a6_upper_pass);
domainPass=all(seedMap.DAC_domain_pass);
forbiddenHits=scan_forbidden_calls({thisFile+".m", ...
    fullfile(thisDir,'evaluate_frozen_wdro_dataset_block_h2.m'), ...
    fullfile(thisDir,'load_frozen_b3_wdro_dataset_h2.m')});

checks={};
checks=add_check(checks,"AUDIT-01","35 source states each contain 15000 records",stateCountPass,stateCountPass,true);
checks=add_check(checks,"AUDIT-02","nominal and both validation datasets each contain 525000 rows",roleCountPass,roleSummary.record_count,[525000;525000;525000]);
checks=add_check(checks,"AUDIT-03","each role contains 35 states with 15000 records",stateWeightPass,height(stateWeightAudit),105);
checks=add_check(checks,"AUDIT-04","each initial-state weight sum equals one",stateWeightPass,max(abs(stateWeightAudit.weight_sum-1)),0);
checks=add_check(checks,"AUDIT-05","all roles use identical canonical path order",pathOrderPass,pathOrderSignatures,pathOrderSignatures(1));
checks=add_check(checks,"AUDIT-06","seed groups map to nominal validation-1 validation-2",seedPass,roleSummary.base_joint_seed,config.baseSeeds);
checks=add_check(checks,"AUDIT-07","frozen consequences exactly reproduce Step-03I N15000",step3iPass,max(step3iReproductionAudit.absolute_difference),0);
checks=add_check(checks,"AUDIT-08","formal wind mode remains stagewise_random_triangular",windConfig.defaultMode=="stagewise_random_triangular",windConfig.defaultMode,"stagewise_random_triangular");
checks=add_check(checks,"AUDIT-09","wind and resistance seeds are separate and recorded",windPass,sum(seedMap.wind_seed==seedMap.resistance_seed),0);
checks=add_check(checks,"AUDIT-10","W1 W2 and W3 wind quantiles are independent",stagewiseQPass,sum(~seedMap.stagewise_q_pass),0);
checks=add_check(checks,"AUDIT-11","sampled winds stay inside grade bounds and a6 is at most 60",windBoundsPass&&a6UpperPass,[sum(~seedMap.wind_bounds_pass),sum(~seedMap.a6_upper_pass)],[0,0]);
checks=add_check(checks,"AUDIT-12","all frozen D A C values satisfy the interface domains",domainPass,sum(~seedMap.DAC_domain_pass),0);
checks=add_check(checks,"AUDIT-13","268 observed candidates occur naturally and 858 unobserved do not enter",candidatePass,candidatePresenceAudit.unobserved_candidate_record_count,[0;0;0]);
checks=add_check(checks,"AUDIT-14","WDRO loader restores D A C array contract",loaderPass,loaderPass,true);
checks=add_check(checks,"AUDIT-15","source inputs and formal configuration remain unchanged",inputsUnchanged,inputsUnchanged,true);
checks=add_check(checks,"AUDIT-16","Step-03I and accepted old runs remain unchanged",oldOutputsUnchanged,oldOutputsUnchanged,true);
checks=add_check(checks,"AUDIT-17","no WDRO Gurobi optimization or MSP calls",height(forbiddenHits)==0,height(forbiddenHits),0);
checks=add_check(checks,"AUDIT-18","main sample SHA-256 remains accepted",sha256_file(config.mainSampleFile)==config.expectedMainHash,sha256_file(config.mainSampleFile),config.expectedMainHash);
automaticAudit=cell2table(checks,'VariableNames',{'check_id','description','passed','observed','expected'});
passCount=sum(automaticAudit.passed);failCount=sum(~automaticAudit.passed);
if failCount>0,error('Step-03J audit failed: %s',strjoin(automaticAudit.check_id(~automaticAudit.passed),', '));end

writetable(seedMap,fullfile(config.tempOutputDir,'dataset_role_and_seed_map.csv'));
writetable(stateWeightAudit,fullfile(config.tempOutputDir,'state_weight_audit.csv'));
writetable(candidatePresenceAudit,fullfile(config.tempOutputDir,'candidate_presence_audit.csv'));
writetable(schemaDescription,fullfile(config.tempOutputDir,'wdro_schema_description.csv'));
writetable(step3iReproductionAudit,fullfile(config.tempOutputDir,'step3i_reproduction_audit.csv'));
writetable(loaderCompatibilityAudit,fullfile(config.tempOutputDir,'loader_compatibility_audit.csv'));
writetable(roleSummary,fullfile(config.tempOutputDir,'large_file_manifest.csv'));
writetable(automaticAudit,fullfile(config.tempOutputDir,'automatic_audit.csv'));
write_manifest(fullfile(config.tempOutputDir,'run_manifest.txt'),config,passCount,failCount,roleSummary,pathOrderSignatures);
write_readme(fullfile(config.tempOutputDir,'README.txt'),config,passCount,failCount,roleSummary);
movefile(config.tempOutputDir,config.outputDir);
fprintf('\nStage3J WDRO input freeze finished. PASS=%d; FAIL=%d.\n',passCount,failCount);
fprintf('Output: %s\n',config.outputDir);

function model=build_freeze_model(config,foundation,windConfig)
near=foundation.raw_near;grid=foundation.grid_segments;road=foundation.road_segments;
Pnode=double(near.Grid.P_load_base_kw(:));eta=double(near.HydrogenDevice.eta_FC);
lhv=double(near.HydrogenDevice.h2_lhv_kWh_per_kg);site=sortrows(readtable(config.siteNodeFile),'site_id');
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
            lineFactor(rr,:)=compute_wind_speed_radial_h2(lineDist,1,config.Rmax,config.windDecayB).';
            roadFactor(rr,:)=compute_wind_speed_radial_h2(roadDist,1,config.Rmax,config.windDecayB).';
            stateIndex(a,loc-min(locValues)+1,lfw+1)=rr;
        end
    end
end
model=struct();model.lineFactor=lineFactor;model.roadFactor=roadFactor;model.stateIndex=stateIndex;
model.locMin=min(locValues);model.locMax=max(locValues);model.nLines=height(grid);model.nRoads=height(road);
model.nNodes=numel(Pnode);model.nSites=height(site);model.sourceNode=config.sourceNode;
model.Pnode_kW=Pnode;model.nodePathIncidence=radial_node_path_incidence(numel(Pnode),grid.from_node,grid.to_node,config.sourceNode);
model.roadFrom=double(road.from_node);model.roadTo=double(road.to_node);
model.roadLength=hypot(road.x2-road.x1,road.y2-road.y1);model.siteNodes=double(site.grid_node);
model.DFactorKgPerKWh=1/(eta*lhv);model.DUpperKg=3*(sum(Pnode)-Pnode(config.sourceNode))*model.DFactorKgPerKWh;
model.windLower=windConfig.randomLower;model.windModeValues=windConfig.randomMode;model.windUpper=windConfig.randomUpper;
model.designWindSpeedVN=config.designWindSpeedVN;model.roadDesignWindVN=config.roadDesignWindVN;
end
function incidence=radial_node_path_incidence(nNodes,fromNode,toNode,sourceNode)
nLines=numel(fromNode);adj=cell(nNodes,1);edgeAdj=cell(nNodes,1);
for ll=1:nLines,i=fromNode(ll);j=toNode(ll);adj{i}(end+1)=j;edgeAdj{i}(end+1)=ll;adj{j}(end+1)=i;edgeAdj{j}(end+1)=ll;end %#ok<AGROW>
parent=zeros(nNodes,1);parentEdge=zeros(nNodes,1);visited=false(nNodes,1);queue=zeros(nNodes,1);head=1;tail=1;queue(1)=sourceNode;visited(sourceNode)=true;
while head<=tail,u=queue(head);head=head+1;for kk=1:numel(adj{u}),v=adj{u}(kk);if visited(v),continue;end;visited(v)=true;parent(v)=u;parentEdge(v)=edgeAdj{u}(kk);tail=tail+1;queue(tail)=v;end,end
incidence=false(nNodes,nLines);for node=1:nNodes,cur=node;while cur~=sourceNode,incidence(node,parentEdge(cur))=true;cur=parent(cur);end,end
end
function T=build_schema_description()
rows={ ...
"scenario_csv","initial_state_id / initial_state","integer / string","initial-state key","groups each role into 35 independent conditional datasets"; ...
"scenario_csv","path_id / scenario_id_in_state","integer","record identity","canonical order shared by all three roles"; ...
"scenario_csv","a_W1..a_W3 loc_W1..loc_W3 lfw_W1..lfw_W3","integer","W path states","formal W1-W3 physical path"; ...
"scenario_csv","wind_W1_mps..wind_W3_mps","m/s","actual sampled wind","stagewise_random_triangular realization"; ...
"scenario_csv","wind_seed / resistance_seed / joint_stream_position","integer","random-input identity","reproduces Step-03I joint stream assignment"; ...
"scenario_csv","D_Hres3h_total_kg","kg-H2","scenario total demand consequence","sum of sidecar D over 33 nodes"; ...
"scenario_csv","A_reachable_share","share","WDRO aggregated reachability summary","mean of binary sidecar A over 4 sites x 33 nodes"; ...
"scenario_csv","C_reachable_mean_km","km","WDRO aggregated reachable cost summary","mean finite sidecar C where A=1"; ...
"scenario_csv","W3_failed_line_count / W3_closed_road_count","count","persistent damage summary","W3 component damage counts"; ...
"scenario_csv","sample_weight","probability","conditional nominal or validation weight","1/15000 within each initial state"; ...
"scenario_csv","dataset_role","string","dataset split","nominal validation-1 or validation-2"; ...
"DAC_sidecar","D_node_kg","kg-H2","R x 33 demand array","maps to existing WDRO samples.D and H_node_kg_s"; ...
"DAC_sidecar","A_site_node","binary","R x 4 x 33 reachability array","maps to existing WDRO samples.A and reachable"; ...
"DAC_sidecar","C_site_node_km","km","R x 4 x 33 service-cost array","maps to existing WDRO samples.C_raw and scenario_service_cost"};
T=cell2table(rows,'VariableNames',{'storage','field','unit_or_type','meaning','legacy_wdro_compatibility'});
end
function codes=physical_codes_main(T),codes=encode_codes(double(T.a0),double(T.loc0),double(T.lfw0),double(T.a_W1),double(T.loc_W1),double(T.lfw_W1),double(T.a_W2),double(T.loc_W2),double(T.lfw_W2),double(T.a_W3),double(T.loc_W3),double(T.lfw_W3));end
function codes=physical_codes_candidate(T),codes=encode_codes(double(T.a0),double(T.loc0),double(T.lfw0),double(T.a1),double(T.loc1),double(T.lfw1),double(T.a2),double(T.loc2),double(T.lfw2),double(T.a3),double(T.loc3),double(T.lfw3));end
function codes=encode_codes(varargin),n=numel(varargin{1});codes=zeros(n,1,'uint64');bases=[7,13,4,7,13,4,7,13,4,7,13,4];for ii=1:12,value=double(varargin{ii});if mod(ii,3)==2,value=value+2;end;codes=codes*uint64(bases(ii))+uint64(value);end,end
function values=as_logical(values),if islogical(values),return;end;if isnumeric(values),values=values~=0;else,text=lower(strtrim(string(values)));values=text=="true"|text=="1";end,end
function summary=snapshot_directories(dirs),rows={};for dd=1:numel(dirs),files=dir(fullfile(dirs{dd},'**','*'));files=files(~[files.isdir]);for ii=1:numel(files),rows(end+1,:)={string(dirs{dd}),string(fullfile(files(ii).folder,files(ii).name)),files(ii).bytes,files(ii).datenum};end,end;if isempty(rows),summary=cell2table(cell(0,4),'VariableNames',{'root','path','bytes','datenum'});else,summary=sortrows(cell2table(rows,'VariableNames',{'root','path','bytes','datenum'}),'path');end,end
function T=scan_forbidden_calls(files),patterns=["solve_wdro_"+"terminal_loh_lp_h2\\s*\\(","guro"+"bi\\s*\\(","main_msp_"+"h2_near\\s*\\(","run_h2_"+"with_options\\s*\\(","opti"+"mize\\s*\\(","lin"+"prog\\s*\\("];rows={};for ff=1:numel(files),text=fileread(files{ff});for pp=1:numel(patterns),if ~isempty(regexp(text,patterns(pp),'once')),rows(end+1,:)={string(files{ff}),patterns(pp)};end,end,end;if isempty(rows),T=cell2table(cell(0,2),'VariableNames',{'file','pattern'});else,T=cell2table(rows,'VariableNames',{'file','pattern'});end,end
function [rows,fields]=count_csv_rows_and_fields(fileName),fid=fopen(fileName,'rb');if fid<0,error('Could not open %s.',fileName);end;cleanup=onCleanup(@()fclose(fid));header=fgetl(fid);fields=string(strsplit(header,','));newlineCount=1;lastByte=uint8(10);while true,bytes=fread(fid,1024*1024,'*uint8');if isempty(bytes),break;end;newlineCount=newlineCount+sum(bytes==10);lastByte=bytes(end);end;rows=newlineCount+double(lastByte~=10)-1;end
function hash=sha256_file(fileName),fid=fopen(fileName,'rb');if fid<0,error('Could not open %s.',fileName);end;cleanup=onCleanup(@()fclose(fid));md=java.security.MessageDigest.getInstance('SHA-256');while true,bytes=fread(fid,1024*1024,'*uint8');if isempty(bytes),break;end;md.update(typecast(bytes,'int8'));end;digest=typecast(md.digest(),'uint8');hash=lower(string(reshape(dec2hex(digest,2).',1,[])));end
function hash=sha256_double(x),md=java.security.MessageDigest.getInstance('SHA-256');bytes=typecast(double(x(:)),'uint8');md.update(typecast(bytes,'int8'));digest=typecast(md.digest(),'uint8');hash=lower(string(reshape(dec2hex(digest,2).',1,[])));end
function hash=sha256_text(x),md=java.security.MessageDigest.getInstance('SHA-256');bytes=unicode2native(char(x),'UTF-8');md.update(typecast(uint8(bytes),'int8'));digest=typecast(md.digest(),'uint8');hash=lower(string(reshape(dec2hex(digest,2).',1,[])));end
function rows=add_check(rows,id,description,passed,observed,expected),rows(end+1,:)={string(id),string(description),logical(passed),scalar_text(observed),scalar_text(expected)};end
function text=scalar_text(value),if isstring(value),text=strjoin(value(:).',' | ');elseif ischar(value),text=string(value);elseif islogical(value)&&isscalar(value),text=string(double(value));elseif isnumeric(value)&&isscalar(value),text=string(sprintf('%.15g',value));elseif isnumeric(value),text=strjoin(compose('%.15g',value(:).'),' | ');else,text=string(value);end,end
function write_manifest(fileName,config,passCount,failCount,roleSummary,pathHashes),fid=fopen(fileName,'w');cleanup=onCleanup(@()fclose(fid));fprintf(fid,'task_id=task-002\nstep_id=10-wdro-input-freeze\nrun_id=run-001\nstatus=PASS\npass_count=%d\nfail_count=%d\n',passCount,failCount);fprintf(fid,'roles=%s\nbase_joint_seeds=%s\nrecords_per_role=525000\nrecords_per_state=15000\n',strjoin(config.datasetRoles,','),strjoin(string(config.baseSeeds),','));fprintf(fid,'formal_wind_mode=stagewise_random_triangular\nweight=1/15000_per_initial_state\npath_probability_reweighting=false\n');for ii=1:height(roleSummary),fprintf(fid,'%s_csv_sha256=%s\n%s_DAC_sha256=%s\n',roleSummary.dataset_role(ii),roleSummary.csv_sha256(ii),roleSummary.dataset_role(ii),roleSummary.dac_mat_sha256(ii));end;fprintf(fid,'canonical_path_order_sha256=%s\nWDRO_run=false\nGurobi_run=false\nMSP_run=false\n',pathHashes(1));end
function write_readme(fileName,config,passCount,failCount,roleSummary),fid=fopen(fileName,'w');cleanup=onCleanup(@()fclose(fid));fprintf(fid,'Step-03J run-001: frozen formal B3 datasets for WDRO\n\nPASS=%d; FAIL=%d\n',passCount,failCount);fprintf(fid,'Seed group 1 (%d) is nominal; groups 2 and 3 (%d, %d) are independent validation-1 and validation-2. They are not pooled into a 45000-record nominal state sample.\n',config.baseSeeds);fprintf(fid,'Each role has 525000 rows: 35 initial states x 15000 canonical main records. Each conditional state uses weight 1/15000 and sums to one.\n');fprintf(fid,'The scenario CSVs retain path states, actual W1-W3 winds, seeds, D/A/C summaries, W3 damage counts, weight, and role. DAC MAT sidecars retain exact R x 33 D and R x 4 x 33 A/C arrays for the existing WDRO algorithm contract.\n');for ii=1:height(roleSummary),fprintf(fid,'%s: seed %d, rows %d, CSV bytes %.0f, DAC bytes %.0f, CSV SHA %s, DAC SHA %s.\n',roleSummary.dataset_role(ii),roleSummary.base_joint_seed(ii),roleSummary.record_count(ii),roleSummary.csv_bytes(ii),roleSummary.dac_mat_bytes(ii),roleSummary.csv_sha256(ii),roleSummary.dac_mat_sha256(ii));end;fprintf(fid,'The loader load_frozen_b3_wdro_dataset_h2 restores samples.D, samples.A, samples.C_raw, and sampleWeights without changing WDRO algorithms.\n');fprintf(fid,'Observed candidates occur only through 268 natural main records per role. No unobserved candidate is present.\n');fprintf(fid,'No WDRO, Gurobi optimization, or MSP execution was performed.\n');end
function close_pool(),p=gcp('nocreate');if ~isempty(p),delete(p);end,end
