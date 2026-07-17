%% Step-03B run-001: expanded fixed-resistance B3 candidate validation.
clear;clc;

thisFile=mfilename('fullpath');thisDir=fileparts(thisFile);
moduleDir=fileparts(thisDir);rootDir=fileparts(moduleDir);
addpath(rootDir);addpath(thisDir);
addpath(fullfile(rootDir,'fa_h2','fuzhu','terminalLoh_windmc'));

config=struct();config.rootDir=rootDir;config.moduleDir=moduleDir;
config.outputDir=fullfile(moduleDir,'output','stage3b_b3_candidate_validation','run-001');
config.mainSampleFile=fullfile(moduleDir,'output','stage2a2_W3_path_sampling', ...
    'run-002','main_path_samples.csv');
config.candidatePoolFile=fullfile(moduleDir,'output', ...
    'stage2b_tail_candidate_design','run-005','unique_tail_paths.csv');
config.stage3AAuditFile=fullfile(moduleDir,'output','stage3a_b3_smoke', ...
    'run-001','automatic_audit.csv');
config.stage3AManifestFile=fullfile(moduleDir,'output','stage3a_b3_smoke', ...
    'run-001','run_manifest.txt');
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

config.expectedMainRows=525000;
config.expectedMainHash="972a8c58620c09ac19cfcfb29e8d6a3ed2819ef1a22dbd522043436418eb805d";
config.expectedCandidateRows=1126;config.expectedObservedCandidates=268;
config.expectedUnobservedCandidates=858;config.mainPathsPerInitialState=15000;
config.resistanceRepeats=20;config.rngSeed=20260718;
config.Rmax=40;config.Wstep=40;config.sliceDurationH=1;config.HresTotalH=3;
config.WstepValues=40;config.recommendedWstep=40;config.comparisonWstep=45;
config.stageNames=["lf7","W1","W2","W3"];config.stageOffsets=[0,1,2,3];
config.warningDistanceKmEq=100;config.distanceMethod="point_to_segment";
config.windDecayB=0.6;config.designWindSpeedVN=25;
config.roadDesignWindVN=30;config.roadSlowdownLambda=1.0;
config.slowRoadThreshold=1e-6;config.sourceNode=1;
config.CDefinition="masked_dist(n)_if_A1_else_0";
config.probabilityTolerance=1e-12;config.upperBoundTolerance=1e-9;

requiredFiles={config.mainSampleFile,config.candidatePoolFile, ...
    config.stage3AAuditFile,config.stage3AManifestFile, ...
    config.warningSolutionFile,config.warningGeometryFile, ...
    config.warningRankingFile,config.warningStageSummaryFile, ...
    config.warningDiagnosticsFile,config.warningRankingSourceFile, ...
    config.locCoordinateFile,config.nearInputFile,config.roadEdgeFile, ...
    config.siteNodeFile,fullfile(thisDir,'build_foundation_fix_coordinates_h2.m'), ...
    fullfile(rootDir,'fa_h2','fuzhu','terminalLoh_windmc', ...
    'compute_wind_speed_radial_h2.m'), ...
    fullfile(rootDir,'fa_h2','fuzhu','terminalLoh_windmc', ...
    'compute_line_failure_prob_h2.m'), ...
    fullfile(thisDir,'compute_Hres3h_node_demand_h2.m'), ...
    fullfile(thisDir,'select_b3_candidate_validation_paths_h2.m'), ...
    fullfile(thisDir,'evaluate_b3_candidate_validation_h2.m')};
for ii=1:numel(requiredFiles)
    if ~isfile(requiredFiles{ii})
        error('run_stage3b_b3_candidate_validation_h2:MissingInput', ...
            'Required input is missing: %s',requiredFiles{ii});
    end
end
if isfolder(config.outputDir)
    existing=dir(config.outputDir);existing=existing(~ismember({existing.name},{'.','..'}));
    if ~isempty(existing)
        error('run_stage3b_b3_candidate_validation_h2:OutputExists', ...
            'Refusing to overwrite nonempty output directory: %s',config.outputDir);
    end
else
    mkdir(config.outputDir);
end

inputHashesBefore=strings(numel(requiredFiles),1);inputBytesBefore=zeros(numel(requiredFiles),1);
for ii=1:numel(requiredFiles)
    inputHashesBefore(ii)=sha256_file(requiredFiles{ii});
    info=dir(requiredFiles{ii});inputBytesBefore(ii)=info.bytes;
end

[mainRows,mainFields]=count_csv_rows_and_fields(config.mainSampleFile);
mainHash=sha256_file(config.mainSampleFile);
candidatePool=readtable(config.candidatePoolFile,'TextType','string');
candidateHash=sha256_file(config.candidatePoolFile);
stage3AAudit=readtable(config.stage3AAuditFile,'TextType','string');
stage3AManifest=string(fileread(config.stage3AManifestFile));
fprintf('INPUT|path=%s|rows=%d|fields=%s|sha256=%s\n',config.mainSampleFile, ...
    mainRows,strjoin(mainFields,','),mainHash);
print_table_input(config.candidatePoolFile,candidatePool,candidateHash);
print_table_input(config.stage3AAuditFile,stage3AAudit, ...
    sha256_file(config.stage3AAuditFile));
fprintf('INPUT|path=%s|bytes=%d|sha256=%s\n',config.stage3AManifestFile, ...
    dir(config.stage3AManifestFile).bytes,sha256_file(config.stage3AManifestFile));

if mainRows~=config.expectedMainRows || mainHash~=config.expectedMainHash
    error('Main sample row count or SHA-256 does not match the accepted input.');
end
observedFlag=as_logical(candidatePool.is_observed_candidate);
unobservedFlag=as_logical(candidatePool.is_unobserved_candidate);
if height(candidatePool)~=config.expectedCandidateRows || ...
        sum(observedFlag)~=config.expectedObservedCandidates || ...
        sum(unobservedFlag)~=config.expectedUnobservedCandidates
    error('Candidate pool count or observed/unobserved identity mismatch.');
end
if any(~as_logical(stage3AAudit.passed)) || ...
        ~contains(stage3AManifest,"status=PASS") || ...
        ~contains(stage3AManifest,"damage_mode=persistent_fixed_resistance")
    error('Step-03A accepted result is missing PASS fixed-resistance identity.');
end

mainSample=readtable(config.mainSampleFile);
foundation=build_foundation_fix_coordinates_h2(config);
selectionResult=select_b3_candidate_validation_paths_h2( ...
    candidatePool,mainSample,config,foundation);
selection=selectionResult.selection;
clear mainSample candidatePool;

fprintf('BEGIN_STAGE3B_FIXED_RESISTANCE_VALIDATION\n');
primary=evaluate_b3_candidate_validation_h2(config,foundation,selection,1:20);
replay=evaluate_b3_candidate_validation_h2(config,foundation,selection,1);
reproducibilityAudit=build_reproducibility_audit(primary,replay);

[scenarioWithNovelty,novelPatterns]=build_novelty(primary.scenario_results);
comparison=compare_sources(scenarioWithNovelty,primary.stage_results, ...
    primary.node_d_values,primary.node_d_source,config);
accessibilityAudit=build_accessibility_audit(primary.stage_results);
DUpperAudit=build_D_upper_bound_audit(scenarioWithNovelty,primary,config, ...
    fullfile(thisDir,'evaluate_b3_candidate_validation_h2.m'));

inputHashesAfter=strings(numel(requiredFiles),1);inputBytesAfter=zeros(numel(requiredFiles),1);
for ii=1:numel(requiredFiles)
    inputHashesAfter(ii)=sha256_file(requiredFiles{ii});
    info=dir(requiredFiles{ii});inputBytesAfter(ii)=info.bytes;
end
inputsUnchanged=isequal(inputHashesBefore,inputHashesAfter) && ...
    isequal(inputBytesBefore,inputBytesAfter);

candidatePaths=selectionResult.candidate_paths;
referencePaths=selectionResult.reference_paths;
candidateKeys=physical_keys(candidatePaths);referenceKeys=physical_keys(referencePaths);
candidateCountPass=height(candidatePaths)==1126 && ...
    sum(candidatePaths.source_category=="observed_candidate")==268 && ...
    sum(candidatePaths.source_category=="unobserved_candidate")==858;
referenceCountPass=height(referencePaths)==1126;
stateCountsCandidate=groupsummary(candidatePaths,{'a0','loc0','lfw0'});
stateCountsReference=groupsummary(referencePaths,{'a0','loc0','lfw0'});
stateMatchPass=isequal(stateCountsCandidate(:,1:4),stateCountsReference(:,1:4));
overlapCount=sum(ismember(referenceKeys,candidateKeys));
uniquePass=numel(unique([candidateKeys;referenceKeys]))==2252;

repeatCounts=groupsummary(primary.scenario_results,'selection_path_id');
repeatPass=height(primary.scenario_results)==45040 && ...
    all(repeatCounts.GroupCount==config.resistanceRepeats);
resistancePass=all(primary.resistance_audit.fixed_resistance_pass==1) && ...
    all(primary.resistance_audit.line_threshold_draws_per_component==1) && ...
    all(primary.resistance_audit.road_threshold_draws_per_component==1) && ...
    all(primary.resistance_audit.line_threshold_reuse_max_abs_error==0) && ...
    all(primary.resistance_audit.road_threshold_reuse_max_abs_error==0);
persistencePass=all(primary.failure_audit.line_persistence_pass==1) && ...
    all(primary.failure_audit.road_persistence_pass==1) && ...
    all(primary.failure_audit.slowdown_persistence_pass==1);
DPass=all(primary.stage_results.D_total_kg>=0) && ...
    all(primary.stage_results.D_node_max_kg>=0) && ...
    all(primary.stage_results.D_unit=="kg-H2");
APass=all(primary.stage_results.reachable_pair_count>=0) && ...
    all(primary.stage_results.reachable_pair_count<= ...
    primary.stage_results.site_node_pair_count) && ...
    all(mod(primary.stage_results.reachable_pair_count,1)==0);
CPass=all(isfinite(primary.stage_results.C_reachable_mean_km)) && ...
    all(primary.stage_results.C_reachable_mean_km>=0) && ...
    all(primary.stage_results.C_reachable_min_km>=0) && ...
    all(primary.stage_results.C_reachable_max_km>=0);
reproPass=all(reproducibilityAudit.passed);
probabilityPass=all(selectionResult.probability_audit.probability_identity_pass) && ...
    all(selectionResult.probability_audit.traceability_pass) && ...
    all(candidatePaths.empirical_weight( ...
    candidatePaths.source_category=="unobserved_candidate")==0) && ...
    all(candidatePaths.nominal_inclusion_status( ...
    candidatePaths.source_category=="unobserved_candidate")=="pending_after_B3");
referenceRiskPass=all(selectionResult.reference_strata_audit.selected_low_count>0) && ...
    all(selectionResult.reference_strata_audit.selected_medium_count>0) && ...
    all(selectionResult.reference_strata_audit.selected_high_count>0);
durationPass=all(primary.stage_results.slice_duration_h==1) && config.HresTotalH==3;
pathIdentityPass=check_stage_path_identity(primary.stage_results,selection);
upperBoundPass=all(DUpperAudit.passed);
sourceScenarioCounts=groupsummary(primary.scenario_results,'source_category');
sourceCountPass=get_group_count(sourceScenarioCounts,"main_reference")==22520 && ...
    get_group_count(sourceScenarioCounts,"observed_candidate")==5360 && ...
    get_group_count(sourceScenarioCounts,"unobserved_candidate")==17160;

executedFiles={thisFile+".m", ...
    fullfile(thisDir,'select_b3_candidate_validation_paths_h2.m'), ...
    fullfile(thisDir,'evaluate_b3_candidate_validation_h2.m')};
forbiddenHits=scan_forbidden_calls(executedFiles);
noForbiddenCalls=height(forbiddenHits)==0;

checks={};
checks=add_check(checks,"AUDIT-01","all 1126 candidates completed",candidateCountPass,height(candidatePaths),1126);
checks=add_check(checks,"AUDIT-02","1126 matched references selected",referenceCountPass,height(referencePaths),1126);
checks=add_check(checks,"AUDIT-03","candidate/reference count matches in all 35 states",stateMatchPass,stateMatchPass,true);
checks=add_check(checks,"AUDIT-04","reference and candidate physical paths do not overlap",overlapCount==0,overlapCount,0);
checks=add_check(checks,"AUDIT-05","2252 selected physical paths are unique",uniquePass,numel(unique([candidateKeys;referenceKeys])),2252);
checks=add_check(checks,"AUDIT-06","20 repeats per path and 45040 scenarios",repeatPass,height(primary.scenario_results),45040);
checks=add_check(checks,"AUDIT-07","fixed resistance reused W1-W3",resistancePass,resistancePass,true);
checks=add_check(checks,"AUDIT-08","failure closure and slowdown persist",persistencePass,persistencePass,true);
checks=add_check(checks,"AUDIT-09","D is nonnegative kg-H2",DPass,min(primary.stage_results.D_total_kg),0);
checks=add_check(checks,"AUDIT-10","A counts are binary-derived and bounded",APass,APass,true);
checks=add_check(checks,"AUDIT-11","reachable-only C is finite and nonnegative",CPass,min(primary.stage_results.C_reachable_min_km),0);
checks=add_check(checks,"AUDIT-12","same-seed repeat-1 replay is identical",reproPass,sum(~reproducibilityAudit.passed),0);
checks=add_check(checks,"AUDIT-13","all source inputs unchanged",inputsUnchanged,inputsUnchanged,true);
checks=add_check(checks,"AUDIT-14","probability identity and pending status preserved",probabilityPass,probabilityPass,true);
checks=add_check(checks,"AUDIT-15","reference paths cover low medium high risk",referenceRiskPass,referenceRiskPass,true);
checks=add_check(checks,"AUDIT-16","W1-W3 each 1 h and Hres is 3 h",durationPass,config.HresTotalH,3);
checks=add_check(checks,"AUDIT-17","stage rows use selected path states",pathIdentityPass,pathIdentityPass,true);
checks=add_check(checks,"AUDIT-18","607.970 kg upper bound is physical and unclipped",upperBoundPass,upperBoundPass,true);
checks=add_check(checks,"AUDIT-19","scenario counts match source path counts",sourceCountPass,sourceCountPass,true);
checks=add_check(checks,"AUDIT-20","Step-03A accepted fixed-resistance input verified",true,true,true);
checks=add_check(checks,"AUDIT-21","no WDRO Gurobi optimization or MSP calls",noForbiddenCalls,height(forbiddenHits),0);
automaticAudit=cell2table(checks,'VariableNames', ...
    {'check_id','description','passed','observed','expected'});
passCount=sum(automaticAudit.passed);failCount=sum(~automaticAudit.passed);
status="PASS";if failCount>0,status="FAIL";end

writetable(candidatePaths,fullfile(config.outputDir,'b3_candidate_paths.csv'));
writetable(referencePaths,fullfile(config.outputDir,'b3_reference_paths.csv'));
writetable(primary.stage_results,fullfile(config.outputDir,'b3_DAC_results.csv'));
writetable(scenarioWithNovelty,fullfile(config.outputDir,'b3_scenario_results.csv'));
writetable(DUpperAudit,fullfile(config.outputDir,'D_upper_bound_audit.csv'));
writetable(comparison,fullfile(config.outputDir,'consequence_comparison_by_source.csv'));
writetable(accessibilityAudit,fullfile(config.outputDir,'accessibility_and_C_audit.csv'));
writetable(novelPatterns,fullfile(config.outputDir,'novel_consequence_patterns.csv'));
writetable(selectionResult.probability_audit,fullfile(config.outputDir,'probability_identity_audit.csv'));
writetable(selectionResult.reference_strata_audit,fullfile(config.outputDir,'reference_risk_strata_audit.csv'));
writetable(primary.resistance_audit,fullfile(config.outputDir,'resistance_persistence_audit.csv'));
writetable(primary.failure_audit,fullfile(config.outputDir,'failure_persistence_audit.csv'));
writetable(reproducibilityAudit,fullfile(config.outputDir,'reproducibility_audit.csv'));
writetable(automaticAudit,fullfile(config.outputDir,'automatic_audit.csv'));
write_manifest(fullfile(config.outputDir,'run_manifest.txt'),config,status, ...
    passCount,failCount,mainHash,candidateHash,comparison,DUpperAudit,novelPatterns);
write_readme(fullfile(config.outputDir,'README.txt'),config,status,passCount, ...
    failCount,comparison,DUpperAudit,novelPatterns);

fprintf('\nStage3B candidate validation finished.\n');
fprintf('Status: %s; PASS=%d; FAIL=%d\n',status,passCount,failCount);
fprintf('Candidate paths: %d; reference paths: %d; B3 scenarios: %d\n', ...
    height(candidatePaths),height(referencePaths),height(primary.scenario_results));
fprintf('Derived D upper bound: %.12f kg; observed hits: %d\n', ...
    DUpperAudit.derived_D_upper_bound_kg(1),DUpperAudit.hit_count(1));
fprintf('Output directory: %s\n',config.outputDir);
if failCount>0
    error('run_stage3b_b3_candidate_validation_h2:AuditFailed', ...
        'Step-03B audit failed: %s', ...
        strjoin(automaticAudit.check_id(~automaticAudit.passed),', '));
end

function T=build_reproducibility_audit(primary,replay)
stagePrimary=primary.stage_results(primary.stage_results.resistance_repeat==1,:);
scenarioPrimary=primary.scenario_results(primary.scenario_results.resistance_repeat==1,:);
resistancePrimary=primary.resistance_audit(primary.resistance_audit.resistance_repeat==1,:);
failurePrimary=primary.failure_audit(primary.failure_audit.resistance_repeat==1,:);
names=["stage_results";"scenario_results";"resistance_audit";"failure_audit"];
passed=[isequaln(stagePrimary,replay.stage_results); ...
    isequaln(scenarioPrimary,replay.scenario_results); ...
    isequaln(resistancePrimary,replay.resistance_audit); ...
    isequaln(failurePrimary,replay.failure_audit)];
T=table(names,passed,repmat("same-seed repeat-1 replay across all 2252 paths",4,1), ...
    'VariableNames',{'comparison','passed','method'});
end

function [S,N]=build_novelty(S)
reference=S.source_category=="main_reference";candidate=~reference;
refLine=unique(S.line_failure_signature(reference));
refRoad=unique(S.road_closure_signature(reference));
refAccess=unique(S.accessibility_signature(reference));
refStructural=unique(S.structural_pattern_signature(reference));
refFull=unique(S.full_consequence_signature(reference));
S.novel_line_failure_vs_reference=candidate&~ismember(S.line_failure_signature,refLine);
S.novel_road_closure_vs_reference=candidate&~ismember(S.road_closure_signature,refRoad);
S.novel_accessibility_vs_reference=candidate&~ismember(S.accessibility_signature,refAccess);
S.novel_structural_vs_reference=candidate&~ismember(S.structural_pattern_signature,refStructural);
S.novel_full_DAC_vs_reference=candidate&~ismember(S.full_consequence_signature,refFull);
refD=S.D_Hres3h_total_kg(reference);
q95=pct(refD,95);q99=pct(refD,99);refMax=max(refD);
S.above_reference_D_p95=candidate&S.D_Hres3h_total_kg>q95;
S.above_reference_D_p99=candidate&S.D_Hres3h_total_kg>q99;
S.above_reference_D_max=candidate&S.D_Hres3h_total_kg>refMax+1e-12;
N=S(candidate,{'scenario_id','selection_path_id','resistance_repeat', ...
    'source_category','D_Hres3h_total_kg','line_failure_signature', ...
    'road_closure_signature','accessibility_signature', ...
    'structural_pattern_signature','full_consequence_signature', ...
    'novel_line_failure_vs_reference','novel_road_closure_vs_reference', ...
    'novel_accessibility_vs_reference','novel_structural_vs_reference', ...
    'novel_full_DAC_vs_reference','above_reference_D_p95', ...
    'above_reference_D_p99','above_reference_D_max'});
N.reference_D_p95_kg=repmat(q95,height(N),1);
N.reference_D_p99_kg=repmat(q99,height(N),1);
N.reference_D_max_kg=repmat(refMax,height(N),1);
end

function C=compare_sources(S,stage,nodeD,nodeSource,config)
sources=["main_reference";"observed_candidate";"unobserved_candidate"];
rows=cell(3,34);
for ii=1:3
    q=S(S.source_category==sources(ii),:);z=stage(stage.source_category==sources(ii),:);
    d=nodeD(nodeSource==ii);
    Cmean=sum(z.C_reachable_sum_km)/sum(z.C_reachable_count);
    rows(ii,:)={sources(ii),numel(unique(q.selection_path_id)),height(q), ...
        min(q.D_Hres3h_total_kg),mean(q.D_Hres3h_total_kg),pct(q.D_Hres3h_total_kg,95), ...
        pct(q.D_Hres3h_total_kg,99),max(q.D_Hres3h_total_kg),min(d),mean(d), ...
        pct(d,95),pct(d,99),max(d),sum(z.reachable_pair_count)/sum(z.site_node_pair_count), ...
        sum(z.unreachable_pair_count)/sum(z.site_node_pair_count), ...
        Cmean,pct(z.C_reachable_p95_km,95),max(z.C_reachable_max_km), ...
        mean(z.nodes_unreachable_from_every_site),max(z.nodes_unreachable_from_every_site), ...
        mean(q.failed_lines_W3),max(q.failed_lines_W3),mean(q.closed_roads_W3), ...
        max(q.closed_roads_W3),mean(q.joint_line_road_damage_any), ...
        mean(q.multi_line_failure_any),mean(q.road_disconnection_any), ...
        sum(q.novel_line_failure_vs_reference),sum(q.novel_road_closure_vs_reference), ...
        sum(q.novel_accessibility_vs_reference),sum(q.novel_structural_vs_reference), ...
        sum(q.novel_full_DAC_vs_reference),sum(q.above_reference_D_p99), ...
        sum(q.D_Hres3h_total_kg==0)};
end
C=cell2table(rows,'VariableNames',{'source_category','path_count','scenario_count', ...
    'D_Hres3h_min_kg','D_Hres3h_mean_kg','D_Hres3h_p95_kg','D_Hres3h_p99_kg', ...
    'D_Hres3h_max_kg','D_node_min_kg','D_node_mean_kg','D_node_p95_kg', ...
    'D_node_p99_kg','D_node_max_kg','reachable_pair_share','A0_pair_share', ...
    'C_reachable_mean_km','C_reachable_stage_p95_p95_km','C_reachable_max_km', ...
    'unreachable_nodes_per_stage_mean','unreachable_nodes_per_stage_max', ...
    'failed_lines_W3_mean','failed_lines_W3_max','closed_roads_W3_mean', ...
    'closed_roads_W3_max','joint_line_road_damage_share', ...
    'multi_line_failure_share','road_disconnection_share', ...
    'novel_line_failure_scenarios','novel_road_closure_scenarios', ...
    'novel_accessibility_scenarios','novel_structural_scenarios', ...
    'novel_full_DAC_scenarios','above_reference_D_p99_scenarios', ...
    'diagnostic_zero_D_scenarios'});
end

function A=build_accessibility_audit(stage)
sources=["main_reference";"observed_candidate";"unobserved_candidate"];
rows=cell(9,17);rr=0;
for ii=1:3
    for ss=1:3
        q=stage(stage.source_category==sources(ii)&stage.stage_index==ss,:);rr=rr+1;
        reachable=sum(q.reachable_pair_count);total=sum(q.site_node_pair_count);
        cCount=sum(q.C_reachable_count);cSum=sum(q.C_reachable_sum_km);
        rows(rr,:)={sources(ii),ss,"W"+string(ss),height(q),reachable,total, ...
            reachable/total,total-reachable,(total-reachable)/total, ...
            sum(q.nodes_unreachable_from_every_site), ...
            mean(q.nodes_unreachable_from_every_site), ...
            max(q.nodes_unreachable_from_every_site),cCount,cSum,cSum/cCount, ...
            pct(q.C_reachable_p95_km,95),max(q.C_reachable_max_km)};
    end
end
A=cell2table(rows,'VariableNames',{'source_category','stage_index','stage', ...
    'scenario_stage_count','reachable_pair_count','site_node_pair_count', ...
    'reachable_pair_share','unreachable_pair_count','A0_pair_share', ...
    'nodes_unreachable_from_every_site_sum','nodes_unreachable_from_every_site_mean', ...
    'nodes_unreachable_from_every_site_max','C_reachable_observation_count', ...
    'C_reachable_sum_km','C_reachable_mean_km','C_reachable_stage_p95_p95_km', ...
    'C_reachable_max_km'});
end

function T=build_D_upper_bound_audit(S,result,config,evaluatorFile)
Pupper=sum(result.Pnode_kW)-result.Pnode_kW(config.sourceNode);
derived=Pupper*config.HresTotalH/(result.eta_FC*result.LHV_H2_kWh_per_kg);
observedMax=max(S.D_Hres3h_total_kg);tol=config.upperBoundTolerance;
source=["overall";"main_reference";"observed_candidate";"unobserved_candidate"];
rows=cell(4,18);text=fileread(evaluatorFile);
clipHits=numel(regexp(text,'Dnode\s*=\s*min|min\s*\(\s*Dnode\s*,','match'));
for ii=1:4
    if source(ii)=="overall",q=S;else,q=S(S.source_category==source(ii),:);end
    hit=abs(q.D_Hres3h_total_kg-derived)<=tol;
    rows(ii,:)={source(ii),Pupper,result.eta_FC,result.LHV_H2_kWh_per_kg, ...
        config.sliceDurationH,config.HresTotalH,derived,max(q.D_Hres3h_total_kg), ...
        max(q.D_Hres3h_total_kg)-derived,sum(hit),height(q),mean(hit), ...
        sum(q.D_Hres3h_total_kg>derived+tol),clipHits,false, ...
        "full non-source load outage over three 1 h slices", ...
        "P_loss*1h/(eta_FC*LHV_H2), summed over W1-W3", ...
        max(q.D_Hres3h_total_kg)<=derived+tol && clipHits==0};
end
T=cell2table(rows,'VariableNames',{'source_category','P_loss_upper_kW','eta_FC', ...
    'LHV_H2_kWh_per_kg','slice_duration_h','Hres_total_h', ...
    'derived_D_upper_bound_kg','observed_D_max_kg','observed_minus_bound_kg', ...
    'hit_count','scenario_count','hit_share','above_bound_count', ...
    'clipping_assignment_scan_hits','clipping_applied','upper_bound_origin', ...
    'D_formula','passed'});
end

function pass=check_stage_path_identity(stage,selection)
pass=true;
for pp=1:height(selection)
    q=stage(stage.selection_path_id==selection.selection_path_id(pp),:);
    for ss=1:3
        z=q(q.stage_index==ss,:);
        pass=pass&&all(z.a==selection.("a"+string(ss))(pp)) && ...
            all(z.loc==selection.("loc"+string(ss))(pp)) && ...
            all(z.lfw==selection.("lfw"+string(ss))(pp));
    end
end
end

function count=get_group_count(T,name)
idx=find(T.source_category==name);if numel(idx)~=1,count=NaN;else,count=T.GroupCount(idx);end
end

function hits=scan_forbidden_calls(files)
patterns=["solve_wdro_terminal_loh_lp_h2\\s*\\(","gurobi\\s*\\(", ...
    "main_msp_h2_near\\s*\\(","run_h2_with_options\\s*\\(", ...
    "optimize\\s*\\(","linprog\\s*\\("];
rows={};
for ii=1:numel(files)
    text=fileread(files{ii});
    for pp=1:numel(patterns)
        if ~isempty(regexp(text,patterns(pp),'once'))
            rows(end+1,:)={string(files{ii}),patterns(pp)}; %#ok<AGROW>
        end
    end
end
if isempty(rows),hits=cell2table(cell(0,2),'VariableNames',{'file','pattern'});
else,hits=cell2table(rows,'VariableNames',{'file','pattern'});end
end

function rows=add_check(rows,id,description,passed,observed,expected)
rows(end+1,:)={string(id),string(description),logical(passed), ...
    scalar_text(observed),scalar_text(expected)};
end
function text=scalar_text(value)
if isstring(value),text=strjoin(value(:).',' | ');
elseif ischar(value),text=string(value);
elseif islogical(value)&&isscalar(value),text=string(double(value));
elseif isnumeric(value)&&isscalar(value),text=string(sprintf('%.15g',value));
elseif isnumeric(value),text=strjoin(compose('%.15g',value(:).'),' | ');
else,text=string(value);end
end
function keys=physical_keys(T)
keys=string(compose('%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d', ...
    T.a0,T.loc0,T.lfw0,T.a1,T.loc1,T.lfw1,T.a2,T.loc2,T.lfw2, ...
    T.a3,T.loc3,T.lfw3));
end
function values=as_logical(values)
if islogical(values),return;end
if isnumeric(values),values=values~=0;else
    text=lower(strtrim(string(values)));values=text=="true"|text=="1";
end
end
function print_table_input(fileName,T,hash)
fprintf('INPUT|path=%s|rows=%d|fields=%s|sha256=%s\n',fileName,height(T), ...
    strjoin(string(T.Properties.VariableNames),','),hash);
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
function hash=sha256_file(fileName)
fid=fopen(fileName,'rb');if fid<0,error('Could not open %s.',fileName);end
cleanup=onCleanup(@()fclose(fid));md=java.security.MessageDigest.getInstance('SHA-256');
while true
    bytes=fread(fid,1024*1024,'*uint8');if isempty(bytes),break;end
    md.update(typecast(bytes,'int8'));
end
digest=typecast(md.digest(),'uint8');hash=lower(string(reshape(dec2hex(digest,2).',1,[])));
end
function value=pct(x,p)
x=sort(double(x(:)));x=x(isfinite(x));
if isempty(x),value=NaN;else,value=x(max(1,min(numel(x),ceil(p/100*numel(x)))));end
end

function write_manifest(fileName,config,status,passCount,failCount,mainHash, ...
    candidateHash,comparison,DUpper,novel)
fid=fopen(fileName,'w');if fid<0,error('Could not write %s.',fileName);end
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'task_id=task-002\nstep_id=02-b3-candidate-validation\nrun_id=run-001\n');
fprintf(fid,'run_time=%s\nstatus=%s\npass_count=%d\nfail_count=%d\n', ...
    char(datetime('now','Format','yyyy-MM-dd HH:mm:ss Z')),status,passCount,failCount);
fprintf(fid,'damage_mode=persistent_fixed_resistance\nRmax=%g\nWstep=%g\n',config.Rmax,config.Wstep);
fprintf(fid,'candidate_paths=1126\nobserved_candidates=268\nunobserved_candidates=858\n');
fprintf(fid,'reference_paths=1126\nresistance_repeats_per_path=20\nB3_scenarios=45040\n');
fprintf(fid,'main_sample_sha256=%s\ncandidate_pool_sha256=%s\n',mainHash,candidateHash);
fprintf(fid,'derived_D_upper_bound_kg=%.15g\nD_upper_hit_count=%d\n', ...
    DUpper.derived_D_upper_bound_kg(1),DUpper.hit_count(1));
for ii=1:height(comparison)
    label=char(comparison.source_category(ii));
    fprintf(fid,'%s_D_range_kg=%.15g,%.15g\n',label, ...
        comparison.D_Hres3h_min_kg(ii),comparison.D_Hres3h_max_kg(ii));
end
fprintf(fid,'candidate_novel_full_DAC_scenarios=%d\n',sum(novel.novel_full_DAC_vs_reference));
fprintf(fid,'unobserved_nominal_inclusion_status=pending_after_B3\n');
fprintf(fid,'formal_nominal_distribution_changed=false\nWDRO_run=false\nGurobi_run=false\nMSP_run=false\n');
end

function write_readme(fileName,config,status,passCount,failCount,comparison,DUpper,novel)
fid=fopen(fileName,'w');if fid<0,error('Could not write %s.',fileName);end
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'Step-03B run-001: expanded fixed-resistance B3 candidate validation\n\n');
fprintf(fid,'status=%s; PASS=%d; FAIL=%d\n',status,passCount,failCount);
fprintf(fid,'All 1126 candidates and 1126 matched non-candidate references were evaluated.\n');
fprintf(fid,'Each path has 20 persistent_fixed_resistance repeats; total scenarios=45040.\n');
fprintf(fid,'W1/W2/W3 each 1 h; Hres=3 h.\n\n');
fprintf(fid,'The %.12f kg maximum is the physical full non-source-load outage over 3 h, not clipping. Hits=%d.\n', ...
    DUpper.derived_D_upper_bound_kg(1),DUpper.hit_count(1));
for ii=1:height(comparison)
    fprintf(fid,'- %s: D=[%.12g, %.12g] kg; reachable share=%.12g; reachable C mean=%.12g km; novel full DAC=%d.\n', ...
        comparison.source_category(ii),comparison.D_Hres3h_min_kg(ii), ...
        comparison.D_Hres3h_max_kg(ii),comparison.reachable_pair_share(ii), ...
        comparison.C_reachable_mean_km(ii),comparison.novel_full_DAC_scenarios(ii));
end
fprintf(fid,'\nCandidate scenarios above the matched-reference D maximum: %d.\n', ...
    sum(novel.above_reference_D_max));
fprintf(fid,'C statistics use only A=1 reachable site-node pairs. A=0 counts are reported separately.\n');
fprintf(fid,'Observed candidates retain main empirical identity. Unobserved candidates keep empirical_weight=0.\n');
fprintf(fid,'All 858 unobserved candidates remain pending_after_B3. No formal expectation was formed.\n');
fprintf(fid,'No WDRO, Gurobi, optimization, or MSP was run.\n');
end
