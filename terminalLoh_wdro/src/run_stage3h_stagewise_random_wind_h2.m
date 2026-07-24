%% Step-03H run-001: full-intensity stagewise random wind sensitivity.
clear;clc;

thisFile=mfilename('fullpath');thisDir=fileparts(thisFile);
moduleDir=fileparts(thisDir);rootDir=fileparts(moduleDir);
addpath(rootDir);addpath(thisDir);
addpath(fullfile(rootDir,'fa_h2','fuzhu','terminalLoh_windmc'));

config=struct();
config.outputDir=fullfile(moduleDir,'output','stage3h_stagewise_random_wind','run-001');
config.tempOutputDir=config.outputDir+".tmp";
config.mainSampleFile=fullfile(moduleDir,'output','stage2a2_W3_path_sampling', ...
    'run-002','main_path_samples.csv');
config.candidatePoolFile=fullfile(moduleDir,'output', ...
    'stage2b_tail_candidate_design','run-005','unique_tail_paths.csv');
config.step3eMetricsFile=fullfile(moduleDir,'output', ...
    'stage3e_intensity_wind_sensitivity','run-001','wind_mode_metrics.csv');
config.step3fRandomAuditFile=fullfile(moduleDir,'output', ...
    'stage3f_a6_wind_audit','run-001','random_input_and_a6_path_audit.csv');
config.step3dSummaryFile=fullfile(moduleDir,'output', ...
    'stage3d_b3_sample_stability','run-001','stability_summary_overall.csv');
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
config.representativeStates=[5,4,0;2,6,0;2,1,0;4,4,0;6,7,0];
config.baseSeeds=[20260723,20260724,20260725];config.windSeedOffset=320000000;
config.N=2000;config.useParallel=false;
config.Rmax=40;config.Wstep=40;config.sliceDurationH=1;config.HresTotalH=3;
config.windDecayB=0.6;config.designWindSpeedVN=25;config.roadDesignWindVN=30;
config.sourceNode=1;config.damageMode="persistent_fixed_resistance";
config.currentMap=[0;20.8;28.55;37.05;46.2;55.5];
config.vLow=[0;17.2;24.5;32.7;41.5;51];
config.vMode=config.currentMap;
config.vHigh=[0;24.4;32.6;41.4;50.9;60];
config.modeNames=["M0_FIXED","M1_STAGEWISE_RANDOM"];
config.DUpperKgExpected=607.969887897881;

requiredFiles={config.mainSampleFile,config.candidatePoolFile,config.step3eMetricsFile, ...
    config.step3fRandomAuditFile,config.step3dSummaryFile,config.warningSolutionFile, ...
    config.warningGeometryFile,config.warningRankingFile,config.warningStageSummaryFile, ...
    config.warningDiagnosticsFile,config.warningRankingSourceFile,config.locCoordinateFile, ...
    config.nearInputFile,config.roadEdgeFile,config.siteNodeFile, ...
    fullfile(thisDir,'evaluate_stagewise_random_wind_block_h2.m'), ...
    fullfile(rootDir,'fa_h2','fuzhu','terminalLoh_windmc','build_terminal_loh_wind_mc_preview_h2.m'), ...
    fullfile(rootDir,'fa_h2','fuzhu','terminalLoh_windmc','compute_wind_speed_radial_h2.m'), ...
    fullfile(rootDir,'fa_h2','fuzhu','terminalLoh_windmc','compute_line_failure_prob_h2.m')};
for ii=1:numel(requiredFiles)
    if ~isfile(requiredFiles{ii}),error('Missing input: %s',requiredFiles{ii});end
end
if isfolder(config.outputDir)||isfolder(config.tempOutputDir)
    error('Step-03H run-001 output already exists.');
end

inputHashesBefore=strings(numel(requiredFiles),1);inputBytesBefore=zeros(numel(requiredFiles),1);
for ii=1:numel(requiredFiles)
    inputHashesBefore(ii)=sha256_file(requiredFiles{ii});q=dir(requiredFiles{ii});
    inputBytesBefore(ii)=q.bytes;
end
oldOutputDirs={fullfile(moduleDir,'output','stage3a_b3_smoke','run-001'), ...
    fullfile(moduleDir,'output','stage3b_b3_candidate_validation','run-001'), ...
    fullfile(moduleDir,'output','stage3c_tail_probability_audit','run-001'), ...
    fullfile(moduleDir,'output','stage3d_b3_sample_stability','run-001'), ...
    fullfile(moduleDir,'output','stage3e_intensity_wind_sensitivity','run-001'), ...
    fullfile(moduleDir,'output','stage3f_a6_wind_audit','run-001'), ...
    fullfile(moduleDir,'output','stage3g_a6_bounded_random_wind','run-001')};
oldOutputSnapshotBefore=snapshot_directories(oldOutputDirs);

[mainRows,mainFields]=count_csv_rows_and_fields(config.mainSampleFile);
mainHash=sha256_file(config.mainSampleFile);candidateHash=sha256_file(config.candidatePoolFile);
fprintf('INPUT|path=%s|rows=%d|fields=%s|sha256=%s\n',config.mainSampleFile, ...
    mainRows,strjoin(mainFields,','),mainHash);
if mainRows~=525000||mainHash~=config.expectedMainHash||candidateHash~=config.expectedCandidateHash
    error('Accepted main sample or candidate pool identity mismatch.');
end

mainSample=readtable(config.mainSampleFile);
candidatePool=readtable(config.candidatePoolFile,'TextType','string');
step3eMetrics=readtable(config.step3eMetricsFile,'TextType','string');
step3fAudit=readtable(config.step3fRandomAuditFile,'TextType','string');
step3dSummary=readtable(config.step3dSummaryFile,'TextType','string');
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
    stateSamples{ss}=mainSample(mask,{'a0','loc0','lfw0','path_id','a_W1','a_W2','a_W3', ...
        'loc_W1','loc_W2','loc_W3','lfw_W1','lfw_W2','lfw_W3'});
    stateCountPass=stateCountPass&&height(stateSamples{ss})==15000;
end
mainCodes=physical_codes_main(mainSample);candidateCodes=physical_codes_candidate(candidatePool);
unobservedFlag=as_logical(candidatePool.is_unobserved_candidate);
unobservedOverlapInMain=sum(ismember(mainCodes,candidateCodes(unobservedFlag)));
clear mainSample mainCodes candidateCodes candidatePool;

foundationConfig=config;foundationConfig.WstepValues=40;foundationConfig.recommendedWstep=40;
foundationConfig.comparisonWstep=45;foundationConfig.stageNames=["lf7","W1","W2","W3"];
foundationConfig.stageOffsets=[0,1,2,3];foundationConfig.warningDistanceKmEq=100;
foundationConfig.distanceMethod="point_to_segment";
foundation=build_stagewise_coordinates(foundationConfig);
model=build_stagewise_model(config,foundation);

[stateGrid,seedGrid]=ndgrid(1:5,1:3);taskState=stateGrid(:);taskSeedIndex=seedGrid(:);
nTasks=numel(taskState);taskResults=cell(nTasks,1);
fprintf('BEGIN_STAGE3H|tasks=%d|execution=serial|base_scenarios=%d|reported_mode_consequences=%d\n', ...
    nTasks,nTasks*config.N,nTasks*config.N*2);
for tt=1:nTasks
    taskResults{tt}=evaluate_stagewise_random_wind_block_h2(model, ...
        stateSamples{taskState(tt)},config.baseSeeds(taskSeedIndex(tt)), ...
        stateIds(taskState(tt)),config.N,config.windSeedOffset);
end

metricTables=cell(nTasks,1);pairedTables=cell(nTasks,1);
thresholdTables=cell(nTasks,1);sampleTables=cell(nTasks,1);auditRows=cell(nTasks,20);
for tt=1:nTasks
    ss=taskState(tt);seedId=taskSeedIndex(tt);
    prefix={config.representativeStates(ss,1),config.representativeStates(ss,2), ...
        config.representativeStates(ss,3),seedId,config.baseSeeds(seedId)};
    metricTables{tt}=add_prefix(taskResults{tt}.metrics,prefix);
    pairedTables{tt}=add_prefix(taskResults{tt}.paired,prefix);
    thresholdTables{tt}=add_prefix(taskResults{tt}.threshold_audit,prefix);
    sampleTables{tt}=add_prefix(taskResults{tt}.wind_samples,prefix);
    auditRows(tt,:)={prefix{:},config.N,taskResults{tt}.resistance_seed, ...
        taskResults{tt}.wind_seed,taskResults{tt}.separate_seed_pass, ...
        taskResults{tt}.wind_reproducibility_pass,taskResults{tt}.stagewise_q_pass, ...
        taskResults{tt}.same_level_redraw_pass,taskResults{tt}.wind_bounds_pass, ...
        taskResults{tt}.path_id_sha256,taskResults{tt}.permutation_sha256, ...
        taskResults{tt}.line_u_sha256,taskResults{tt}.road_u_sha256, ...
        taskResults{tt}.q_W1_sha256,taskResults{tt}.q_W2_sha256,taskResults{tt}.q_W3_sha256};
end
modeMetrics=vertcat(metricTables{:});pairedSummary=vertcat(pairedTables{:});
localWindThresholdAudit=vertcat(thresholdTables{:});sampledValues=vertcat(sampleTables{:});
randomAudit=cell2table(auditRows,'VariableNames', ...
    {'a0','loc0','lfw0','seed_id','base_seed','N','resistance_seed','wind_seed', ...
    'separate_seed_pass','wind_reproducibility_pass','stagewise_q_pass', ...
    'same_level_redraw_pass','wind_bounds_pass','selected_path_id_sha256', ...
    'permutation_sha256','line_resistance_u_sha256','road_resistance_u_sha256', ...
    'q_W1_sha256','q_W2_sha256','q_W3_sha256'});
windDefinition=build_stagewise_definition(config);
sampledSummary=build_sampled_summary_by_level(sampledValues,config);
[m0Comparison,m0Pass]=compare_m0_to_step3e(modeMetrics,step3eMetrics,config);
[resistanceIdentity,resistanceIdentityPass]=compare_resistance_to_step3f(randomAudit,step3fAudit);
stabilityComparison=build_stability_comparison(modeMetrics,step3dSummary,config);

inputHashesAfter=strings(numel(requiredFiles),1);inputBytesAfter=zeros(numel(requiredFiles),1);
for ii=1:numel(requiredFiles)
    inputHashesAfter(ii)=sha256_file(requiredFiles{ii});q=dir(requiredFiles{ii});
    inputBytesAfter(ii)=q.bytes;
end
oldOutputSnapshotAfter=snapshot_directories(oldOutputDirs);
inputsUnchanged=isequal(inputHashesBefore,inputHashesAfter)&&isequal(inputBytesBefore,inputBytesAfter);
oldOutputsUnchanged=isequaln(oldOutputSnapshotBefore,oldOutputSnapshotAfter);

baseCount=sum(randomAudit.N);reportedCount=sum(modeMetrics.record_count);
completePass=height(modeMetrics)==30&&baseCount==30000&&reportedCount==60000;
sampleCountPass=height(sampledValues)==90000;
thresholdCompletePass=height(localWindThresholdAudit)==360;
stagewiseQPass=all(randomAudit.stagewise_q_pass)&all(randomAudit.same_level_redraw_pass);
windBoundsPass=all(randomAudit.wind_bounds_pass)&&all(sampledValues.sampled_vmax_mps>=-1e-12);
separateSeedPass=all(randomAudit.separate_seed_pass);
windReplayPass=all(randomAudit.wind_reproducibility_pass);
domainPass=all(modeMetrics.nonfinite_count==0)&all(modeMetrics.negative_value_count==0)& ...
    all(modeMetrics.A0_pair_share>=0&modeMetrics.A0_pair_share<=1);
noCandidatePass=unobservedOverlapInMain==0;
definitionPass=height(windDefinition)==6&&all(windDefinition.M0_fixed_mps==config.currentMap)& ...
    all(windDefinition.M1_lower_mps==config.vLow)&all(windDefinition.M1_mode_mps==config.vMode)& ...
    all(windDefinition.M1_upper_mps==config.vHigh)& ...
    windDefinition.distribution(1)=="fixed"&&all(windDefinition.distribution(2:6)=="triangular");
DUpperPass=abs(model.DUpperKg-config.DUpperKgExpected)<=1e-9;
forbiddenHits=scan_forbidden_calls({thisFile+".m", ...
    fullfile(thisDir,'evaluate_stagewise_random_wind_block_h2.m')});
noForbiddenCalls=height(forbiddenHits)==0;

primary=stabilityComparison(stabilityComparison.metric~="C_reachable_mean_km",:);
outcomeChanged=any(abs(primary.mode_shift_vs_M0)>1e-12);
allPrimaryDirectional=all(primary.mode_shift_vs_M0>=-1e-12);
allPrimaryExceed=all(primary.shift_exceeds_existing_error);
if ~outcomeChanged
    decision="RETAIN_FIXED_WIND";
    decisionReason="stagewise triangular wind produces identical tested consequences";
elseif allPrimaryDirectional&&allPrimaryExceed
    decision="ADOPT_STAGEWISE_RANDOM_WIND";
    decisionReason="all primary risk shifts are nonnegative and exceed existing Step-03D N2000 p95 sampling-error benchmarks";
else
    decision="NEED_MORE_VALIDATION";
    decisionReason="stagewise random wind changes outcomes, but directions or magnitudes are not uniformly beyond existing N2000 stability-error benchmarks";
end
decisionGate=table(decision,decisionReason,allPrimaryDirectional,allPrimaryExceed, ...
    sum(primary.shift_exceeds_existing_error),height(primary), ...
    'VariableNames',{'decision','reason','all_primary_risk_shifts_nonnegative', ...
    'all_primary_shifts_exceed_existing_error','primary_comparisons_exceeding_existing_error', ...
    'primary_comparison_count'});

checks={};
checks=add_check(checks,"AUDIT-01","five states each contain 15000 main records",stateCountPass,stateCountPass,true);
checks=add_check(checks,"AUDIT-02","30000 base path-resistance scenarios completed",baseCount==30000,baseCount,30000);
checks=add_check(checks,"AUDIT-03","two modes report 60000 consequence records",completePass,reportedCount,60000);
checks=add_check(checks,"AUDIT-04","M0 reproduces accepted Step-03E M0 metrics",m0Pass,max(m0Comparison.absolute_difference),0);
checks=add_check(checks,"AUDIT-05","M1 draws independent q values for W1 W2 and W3",stagewiseQPass,stagewiseQPass,true);
checks=add_check(checks,"AUDIT-06","equal consecutive intensity levels still redraw hourly q",all(randomAudit.same_level_redraw_pass),all(randomAudit.same_level_redraw_pass),true);
checks=add_check(checks,"AUDIT-07","all sampled winds stay inside their intensity intervals",windBoundsPass,windBoundsPass,true);
checks=add_check(checks,"AUDIT-08","wind seeds are separate from resistance seeds",separateSeedPass,separateSeedPass,true);
checks=add_check(checks,"AUDIT-09","wind quantile draws reproduce from recorded seeds",windReplayPass,windReplayPass,true);
checks=add_check(checks,"AUDIT-10","paths and component resistance inputs match Step-03F",resistanceIdentityPass,sum(~resistanceIdentity.passed),0);
checks=add_check(checks,"AUDIT-11","90000 stage-level wind draws are recorded",sampleCountPass,height(sampledValues),90000);
checks=add_check(checks,"AUDIT-12","threshold audit covers both modes all stages and assets",thresholdCompletePass,height(localWindThresholdAudit),360);
checks=add_check(checks,"AUDIT-13","no unobserved candidate is mixed into main records",noCandidatePass,unobservedOverlapInMain,0);
checks=add_check(checks,"AUDIT-14","D A and reachable C domains are valid",domainPass,domainPass,true);
checks=add_check(checks,"AUDIT-15","fixed and triangular wind definitions match the task",definitionPass,definitionPass,true);
checks=add_check(checks,"AUDIT-16","607.969887897881 kg-H2 upper bound is preserved",DUpperPass,model.DUpperKg,config.DUpperKgExpected);
checks=add_check(checks,"AUDIT-17","source inputs and formal mapping files remain unchanged",inputsUnchanged,inputsUnchanged,true);
checks=add_check(checks,"AUDIT-18","accepted old run directories remain unchanged",oldOutputsUnchanged,oldOutputsUnchanged,true);
checks=add_check(checks,"AUDIT-19","no WDRO Gurobi optimization or MSP calls",noForbiddenCalls,height(forbiddenHits),0);
checks=add_check(checks,"AUDIT-20","main sample SHA-256 remains accepted",sha256_file(config.mainSampleFile)==config.expectedMainHash,sha256_file(config.mainSampleFile),config.expectedMainHash);
automaticAudit=cell2table(checks,'VariableNames',{'check_id','description','passed','observed','expected'});
passCount=sum(automaticAudit.passed);failCount=sum(~automaticAudit.passed);
status="PASS";if failCount>0,status="FAIL";end
if failCount>0,error('Step-03H audit failed: %s',strjoin(automaticAudit.check_id(~automaticAudit.passed),', '));end

mkdir(config.tempOutputDir);
writetable(windDefinition,fullfile(config.tempOutputDir,'stagewise_wind_definition.csv'));
writetable(sampledSummary,fullfile(config.tempOutputDir,'sampled_wind_summary_by_level.csv'));
writetable(modeMetrics,fullfile(config.tempOutputDir,'mode_metrics.csv'));
writetable(pairedSummary,fullfile(config.tempOutputDir,'paired_difference_summary.csv'));
writetable(localWindThresholdAudit,fullfile(config.tempOutputDir,'local_wind_threshold_audit.csv'));
writetable(stabilityComparison,fullfile(config.tempOutputDir,'step3d_variability_comparison.csv'));
writetable(decisionGate,fullfile(config.tempOutputDir,'decision_gate_summary.csv'));
writetable(automaticAudit,fullfile(config.tempOutputDir,'automatic_audit.csv'));
writetable(sampledValues,fullfile(config.tempOutputDir,'sampled_wind_values.csv'));
writetable(randomAudit,fullfile(config.tempOutputDir,'random_input_and_seed_audit.csv'));
writetable(resistanceIdentity,fullfile(config.tempOutputDir,'step3f_resistance_identity_audit.csv'));
writetable(m0Comparison,fullfile(config.tempOutputDir,'M0_step3e_match_audit.csv'));
write_manifest(fullfile(config.tempOutputDir,'run_manifest.txt'),config,status, ...
    passCount,failCount,decision,baseCount,reportedCount,model.DUpperKg);
write_readme(fullfile(config.tempOutputDir,'README.txt'),config,status,passCount, ...
    failCount,decision,decisionReason,sampledSummary,modeMetrics, ...
    localWindThresholdAudit,stabilityComparison);
movefile(config.tempOutputDir,config.outputDir);
fprintf('\nStage3H stagewise random wind finished.\nStatus: %s; PASS=%d; FAIL=%d\n', ...
    status,passCount,failCount);
fprintf('Decision: %s\nOutput: %s\n',decision,config.outputDir);

function foundation=build_stagewise_coordinates(config)
foundation=build_foundation_fix_coordinates_h2(config);
end

function model=build_stagewise_model(config,foundation)
near=foundation.raw_near;grid=foundation.grid_segments;road=foundation.road_segments;
Pnode=double(near.Grid.P_load_base_kw(:));eta=double(near.HydrogenDevice.eta_FC);
lhv=double(near.HydrogenDevice.h2_lhv_kWh_per_kg);site=readtable(config.siteNodeFile);
site=sortrows(site,'site_id');locValues=sort(double(foundation.loc_table.loc));
nStates=6*numel(locValues)*4;nLines=height(grid);nRoads=height(road);
stateIndex=zeros(6,numel(locValues),4);pFailM0=zeros(nStates,nLines);
pCloseM0=zeros(nStates,nRoads);lineFactor=zeros(nStates,nLines);roadFactor=zeros(nStates,nRoads);
lineWindM0=zeros(nStates,nLines);roadWindM0=zeros(nStates,nRoads);rr=0;
for a=1:6
    for loc=locValues(:).'
        locRow=foundation.loc_table(foundation.loc_table.loc==loc,:);
        for lfw=0:3
            rr=rr+1;x=double(locRow.x_coord);y=foundation.y_base+lfw*config.Wstep;
            lineDist=compute_point_to_segment_distance_h2(x,y,grid.x1,grid.y1,grid.x2,grid.y2);
            roadDist=compute_point_to_segment_distance_h2(x,y,road.x1,road.y1,road.x2,road.y2);
            lineFactor(rr,:)=compute_wind_speed_radial_h2(lineDist,1,config.Rmax,config.windDecayB).';
            roadFactor(rr,:)=compute_wind_speed_radial_h2(roadDist,1,config.Rmax,config.windDecayB).';
            lineWindM0(rr,:)=lineFactor(rr,:)*config.currentMap(a);
            roadWindM0(rr,:)=roadFactor(rr,:)*config.currentMap(a);
            pFailM0(rr,:)=compute_line_failure_prob_h2(lineWindM0(rr,:).',config.designWindSpeedVN).';
            pCloseM0(rr,:)=compute_line_failure_prob_h2(roadWindM0(rr,:).',config.roadDesignWindVN).';
            stateIndex(a,loc-min(locValues)+1,lfw+1)=rr;
        end
    end
end
model=struct();model.pFailM0=pFailM0;model.pCloseM0=pCloseM0;
model.lineWindM0=lineWindM0;model.roadWindM0=roadWindM0;
model.lineFactor=lineFactor;model.roadFactor=roadFactor;model.stateIndex=stateIndex;
model.locMin=min(locValues);model.locMax=max(locValues);model.nLines=nLines;model.nRoads=nRoads;
model.nNodes=numel(Pnode);model.nSites=height(site);model.sourceNode=config.sourceNode;
model.Pnode_kW=Pnode;model.nodePathIncidence=radial_node_path_incidence(numel(Pnode), ...
    grid.from_node,grid.to_node,config.sourceNode);model.roadFrom=double(road.from_node);
model.roadTo=double(road.to_node);model.roadLength=hypot(road.x2-road.x1,road.y2-road.y1);
model.siteNodes=double(site.grid_node);model.DFactorKgPerKWh=1/(eta*lhv);
model.DUpperKg=3*(sum(Pnode)-Pnode(config.sourceNode))*model.DFactorKgPerKWh;
model.designWindSpeedVN=config.designWindSpeedVN;model.roadDesignWindVN=config.roadDesignWindVN;
model.vLow=config.vLow;model.vMode=config.vMode;model.vHigh=config.vHigh;
end

function incidence=radial_node_path_incidence(nNodes,fromNode,toNode,sourceNode)
nLines=numel(fromNode);adj=cell(nNodes,1);edgeAdj=cell(nNodes,1);
if nLines~=nNodes-1,error('Grid is not radial.');end
for ll=1:nLines
    i=fromNode(ll);j=toNode(ll);adj{i}(end+1)=j;edgeAdj{i}(end+1)=ll;
    adj{j}(end+1)=i;edgeAdj{j}(end+1)=ll;
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
if ~all(visited),error('Grid is disconnected.');end
incidence=false(nNodes,nLines);
for node=1:nNodes
    cur=node;
    while cur~=sourceNode
        incidence(node,parentEdge(cur))=true;cur=parent(cur);
    end
end
end

function T=add_prefix(T,p)
T=addvars(T,repmat(p{1},height(T),1),repmat(p{2},height(T),1), ...
    repmat(p{3},height(T),1),repmat(p{4},height(T),1),repmat(p{5},height(T),1), ...
    'Before',1,'NewVariableNames',{'a0','loc0','lfw0','seed_id','base_seed'});
end

function T=build_stagewise_definition(config)
T=table((1:6).',config.currentMap,config.vLow,config.vMode,config.vHigh, ...
    ["fixed";repmat("triangular",5,1)], ...
    ["fixed zero";repmat("independent q per W stage",5,1)], ...
    false(6,1),'VariableNames',{'intensity_level','M0_fixed_mps','M1_lower_mps', ...
    'M1_mode_mps','M1_upper_mps','distribution','stagewise_sampling_rule', ...
    'formal_mapping_modified'});
end

function T=build_sampled_summary_by_level(S,config)
rows=cell(6,10);
for level=1:6
    q=S(S.intensity_level==level,:);x=double(q.sampled_vmax_mps);
    if isempty(x),stats=nan(1,5);else,stats=[min(x),mean(x),pct(x,50),pct(x,95),max(x)];end
    rows(level,:)={level,numel(x),stats(1),stats(2),stats(3),stats(4),stats(5), ...
        config.vLow(level),config.vMode(level),config.vHigh(level)};
end
T=cell2table(rows,'VariableNames',{'intensity_level','sample_count','minimum_mps', ...
    'mean_mps','median_mps','q95_mps','maximum_mps','lower_bound_mps', ...
    'mode_mps','upper_bound_mps'});
end

function [audit,pass]=compare_m0_to_step3e(current,reference,config)
metrics={'D_mean_kg','D_q95_kg','D_q99_kg','full_loss_probability','A0_pair_share', ...
    'reachable_pair_share','C_reachable_mean_km','C_reachable_q95_km', ...
    'W3_failed_lines_mean','W3_failed_lines_q95','W3_closed_roads_mean','W3_closed_roads_q95'};
rows=cell(5*3*numel(metrics),10);rr=0;
for ss=1:5
    for seedId=1:3
        q=current(current.mode=="M0_FIXED"&current.a0==config.representativeStates(ss,1)& ...
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

function [T,pass]=compare_resistance_to_step3f(current,reference)
names={'selected_path_id_sha256','permutation_sha256','line_resistance_u_sha256', ...
    'road_resistance_u_sha256'};
rows=cell(height(current)*numel(names),8);rr=0;
for ii=1:height(current)
    ref=reference(double(reference.a0)==current.a0(ii)&double(reference.loc0)==current.loc0(ii)& ...
        double(reference.seed_id)==current.seed_id(ii),:);
    for jj=1:numel(names)
        rr=rr+1;observed=string(current.(names{jj})(ii));expected=string(ref.(names{jj})(1));
        rows(rr,:)={current.a0(ii),current.loc0(ii),current.seed_id(ii),string(names{jj}), ...
            observed,expected,observed==expected,"Step-03F accepted random-input identity"};
    end
end
T=cell2table(rows,'VariableNames',{'a0','loc0','seed_id','input','observed_sha256', ...
    'step3f_sha256','passed','reference'});pass=all(T.passed);
end

function T=build_stability_comparison(current,summary,config)
metrics=["D_mean_kg","full_loss_probability","A0_pair_share", ...
    "C_reachable_mean_km","W3_failed_lines_mean","W3_closed_roads_mean"];
rows=cell(numel(metrics),8);
for ii=1:numel(metrics)
    m0=current(current.mode=="M0_FIXED",:);m1=current(current.mode=="M1_STAGEWISE_RANDOM",:);
    shift=mean(double(m1.(metrics(ii))))-mean(double(m0.(metrics(ii))));
    ref=summary(double(summary.N)==config.N&summary.metric==metrics(ii),:);
    rows(ii,:)={metrics(ii),mean(double(m0.(metrics(ii)))),mean(double(m1.(metrics(ii)))), ...
        shift,abs(shift),double(ref.absolute_error_p95), ...
        abs(shift)>double(ref.absolute_error_p95),"Step-03D N2000 p95 absolute error versus N15000"};
end
T=cell2table(rows,'VariableNames',{'metric','M0_mean','M1_mean','mode_shift_vs_M0', ...
    'absolute_mode_shift_vs_M0','step3d_N2000_p95_absolute_error', ...
    'shift_exceeds_existing_error','benchmark_definition'});
end

function value=pct(x,p)
x=sort(double(x(:)));x=x(isfinite(x));
if isempty(x),value=NaN;else,value=x(max(1,min(numel(x),ceil(p/100*numel(x)))));end
end
function codes=physical_codes_main(T),codes=encode_codes(double(T.a0),double(T.loc0),double(T.lfw0),double(T.a_W1),double(T.loc_W1),double(T.lfw_W1),double(T.a_W2),double(T.loc_W2),double(T.lfw_W2),double(T.a_W3),double(T.loc_W3),double(T.lfw_W3));end
function codes=physical_codes_candidate(T),codes=encode_codes(double(T.a0),double(T.loc0),double(T.lfw0),double(T.a1),double(T.loc1),double(T.lfw1),double(T.a2),double(T.loc2),double(T.lfw2),double(T.a3),double(T.loc3),double(T.lfw3));end
function codes=encode_codes(varargin),n=numel(varargin{1});codes=zeros(n,1,'uint64');bases=[7,13,4,7,13,4,7,13,4,7,13,4];for ii=1:12,value=double(varargin{ii});if mod(ii,3)==2,value=value+2;end;codes=codes*uint64(bases(ii))+uint64(value);end,end
function values=as_logical(values),if islogical(values),return;end;if isnumeric(values),values=values~=0;else,text=lower(strtrim(string(values)));values=text=="true"|text=="1";end,end
function require_vars(T,names,label),for ii=1:numel(names),if ~ismember(names{ii},T.Properties.VariableNames),error('%s missing %s.',label,names{ii});end,end,end

function summary=snapshot_directories(dirs)
rows={};
for dd=1:numel(dirs)
    files=dir(fullfile(dirs{dd},'**','*'));files=files(~[files.isdir]);
    for ii=1:numel(files)
        rows(end+1,:)={string(dirs{dd}),string(fullfile(files(ii).folder,files(ii).name)), ...
            files(ii).bytes,files(ii).datenum};
    end
end
if isempty(rows)
    summary=cell2table(cell(0,4),'VariableNames',{'root','path','bytes','datenum'});
else
    summary=sortrows(cell2table(rows,'VariableNames',{'root','path','bytes','datenum'}),'path');
end
end

function T=scan_forbidden_calls(files)
patterns=["solve_wdro_"+"terminal_loh_lp_h2\\s*\\(","guro"+"bi\\s*\\(", ...
    "main_msp_"+"h2_near\\s*\\(","run_h2_"+"with_options\\s*\\(", ...
    "opti"+"mize\\s*\\(","lin"+"prog\\s*\\("];
rows={};
for ff=1:numel(files)
    sourceText=fileread(files{ff});
    for pp=1:numel(patterns)
        if ~isempty(regexp(sourceText,patterns(pp),'once'))
            rows(end+1,:)={string(files{ff}),patterns(pp)};
        end
    end
end
if isempty(rows),T=cell2table(cell(0,2),'VariableNames',{'file','pattern'});
else,T=cell2table(rows,'VariableNames',{'file','pattern'});end
end

function [rows,fields]=count_csv_rows_and_fields(fileName)
fid=fopen(fileName,'rb');if fid<0,error('Could not open %s.',fileName);end
cleanup=onCleanup(@()fclose(fid));header=fgetl(fid);fields=string(strsplit(header,','));
newlineCount=1;lastByte=uint8(10);
while true
    bytes=fread(fid,1024*1024,'*uint8');if isempty(bytes),break;end
    newlineCount=newlineCount+sum(bytes==10);lastByte=bytes(end);
end
rows=newlineCount+double(lastByte~=10)-1;
end
function hash=sha256_file(fileName)
fid=fopen(fileName,'rb');if fid<0,error('Could not open %s.',fileName);end
cleanup=onCleanup(@()fclose(fid));md=java.security.MessageDigest.getInstance('SHA-256');
while true,bytes=fread(fid,1024*1024,'*uint8');if isempty(bytes),break;end;md.update(typecast(bytes,'int8'));end
digest=typecast(md.digest(),'uint8');hash=lower(string(reshape(dec2hex(digest,2).',1,[])));
end
function rows=add_check(rows,id,description,passed,observed,expected),rows(end+1,:)={string(id),string(description),logical(passed),scalar_text(observed),scalar_text(expected)};end
function text=scalar_text(value),if isstring(value),text=strjoin(value(:).',' | ');elseif ischar(value),text=string(value);elseif islogical(value)&&isscalar(value),text=string(double(value));elseif isnumeric(value)&&isscalar(value),text=string(sprintf('%.15g',value));elseif isnumeric(value),text=strjoin(compose('%.15g',value(:).'),' | ');else,text=string(value);end,end

function write_manifest(fileName,config,status,passCount,failCount,decision,baseCount,reportedCount,DUpper)
fid=fopen(fileName,'w');if fid<0,error('Could not write %s.',fileName);end
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'task_id=task-002\nstep_id=08-stagewise-random-wind\nrun_id=run-001\nrun_time=%s\n',char(datetime('now','Format','yyyy-MM-dd HH:mm:ss Z')));
fprintf(fid,'status=%s\npass_count=%d\nfail_count=%d\ndecision=%s\n',status,passCount,failCount,decision);
fprintf(fid,'base_path_resistance_scenarios=%d\nreported_mode_consequences=%d\n',baseCount,reportedCount);
fprintf(fid,'wind_distribution_by_level=triangular_with_independent_q_per_W_stage\nwind_seed_offset=%d\n',config.windSeedOffset);
fprintf(fid,'wind_randomness_layer=second_layer_joint_B3_consequence_sampling\nthird_layer_monte_carlo=false\n');
fprintf(fid,'D_upper_kg=%.15g\nformal_fixed_mapping_modified=false\ncandidate_paths_added=0\nWDRO_run=false\nGurobi_run=false\nMSP_run=false\n',DUpper);
end

function write_readme(fileName,config,status,passCount,failCount,decision,reason,S,M,T,V)
fid=fopen(fileName,'w');if fid<0,error('Could not write %s.',fileName);end
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'Step-03H run-001: full-intensity stagewise random wind sensitivity\n\n');
fprintf(fid,'status=%s; PASS=%d; FAIL=%d\n',status,passCount,failCount);
fprintf(fid,'M1 draws independent q1/q2/q3 within each path-resistance scenario. Wind randomness remains in the second-layer joint B3 realization.\n');
for level=1:6
    q=S(S.intensity_level==level,:);
    fprintf(fid,'a=%d samples=%d min=%.9g mean=%.9g median=%.9g q95=%.9g max=%.9g m/s.\n', ...
        level,q.sample_count,q.minimum_mps,q.mean_mps,q.median_mps,q.q95_mps,q.maximum_mps);
end
for mode=config.modeNames
    q=M(M.mode==mode,:);
    fprintf(fid,'%s: D mean/q95/q99 %.9g/%.9g/%.9g kg-H2; full loss %.9g; A0 %.9g; reachable C %.9g km; W3 failed %.9g; W3 closed %.9g.\n', ...
        mode,mean(q.D_mean_kg),mean(q.D_q95_kg),mean(q.D_q99_kg), ...
        mean(q.full_loss_probability),mean(q.A0_pair_share),mean(q.C_reachable_mean_km), ...
        mean(q.W3_failed_lines_mean),mean(q.W3_closed_roads_mean));
end
m1=T(T.mode=="M1_STAGEWISE_RANDOM",:);
fprintf(fid,'M1 threshold crossings versus M0: grid >25 up/down %d/%d; grid >50 up/down %d/%d; road >30 up/down %d/%d; road >60 up/down %d/%d.\n', ...
    sum(m1.crossed_up_vs_M0_count(m1.asset=="grid_line"&m1.threshold_mps==25)), ...
    sum(m1.crossed_down_vs_M0_count(m1.asset=="grid_line"&m1.threshold_mps==25)), ...
    sum(m1.crossed_up_vs_M0_count(m1.asset=="grid_line"&m1.threshold_mps==50)), ...
    sum(m1.crossed_down_vs_M0_count(m1.asset=="grid_line"&m1.threshold_mps==50)), ...
    sum(m1.crossed_up_vs_M0_count(m1.asset=="road_edge"&m1.threshold_mps==30)), ...
    sum(m1.crossed_down_vs_M0_count(m1.asset=="road_edge"&m1.threshold_mps==30)), ...
    sum(m1.crossed_up_vs_M0_count(m1.asset=="road_edge"&m1.threshold_mps==60)), ...
    sum(m1.crossed_down_vs_M0_count(m1.asset=="road_edge"&m1.threshold_mps==60)));
fprintf(fid,'Primary shifts exceeding Step-03D N2000 p95 errors: %d of %d.\n', ...
    sum(V.shift_exceeds_existing_error(V.metric~="C_reachable_mean_km")), ...
    sum(V.metric~="C_reachable_mean_km"));
fprintf(fid,'Decision: %s. %s.\n',decision,reason);
fprintf(fid,'The formal fixed wind mapping is unchanged. No candidate paths, full B3 rerun, WDRO, Gurobi, or MSP.\n');
end
