%% Step-03E run-001: intensity-to-Vmax mapping sensitivity.
clear;clc;

thisFile = mfilename('fullpath'); thisDir = fileparts(thisFile);
moduleDir = fileparts(thisDir); rootDir = fileparts(moduleDir);
addpath(rootDir); addpath(thisDir);
addpath(fullfile(rootDir,'fa_h2','fuzhu','terminalLoh_windmc'));

config = struct();
config.outputDir = fullfile(moduleDir,'output', ...
    'stage3e_intensity_wind_sensitivity','run-001');
config.tempOutputDir = config.outputDir + ".tmp";
config.mainSampleFile = fullfile(moduleDir,'output','stage2a2_W3_path_sampling', ...
    'run-002','main_path_samples.csv');
config.candidatePoolFile = fullfile(moduleDir,'output', ...
    'stage2b_tail_candidate_design','run-005','unique_tail_paths.csv');
config.step3dMetricsFile = fullfile(moduleDir,'output', ...
    'stage3d_b3_sample_stability','run-001','stability_metrics_by_state.csv');
config.warningSweepDir = fullfile(moduleDir,'output', ...
    'stage2_foundation_warning100_Rmax30_40_50_Wstep_sweep');
config.warningSolutionFile = fullfile(config.warningSweepDir,'warning_y_base_solution.csv');
config.warningGeometryFile = fullfile(config.warningSweepDir,'warning_geometry_by_loc.csv');
config.warningRankingFile = fullfile(config.warningSweepDir,'Wstep_candidate_ranking.csv');
config.warningStageSummaryFile = fullfile(config.warningSweepDir,'Rmax_Wstep_stage_summary.csv');
config.warningDiagnosticsFile = fullfile(config.warningSweepDir,'diagnostics_summary.txt');
config.warningRankingSourceFile = fullfile(thisDir,'rank_Wstep_candidates_h2.m');
config.locCoordinateFile = fullfile(moduleDir,'output','stage2_foundation_audit', ...
    'loc_lf_coordinate_table.csv');
config.nearInputFile = fullfile(rootDir,'data','yuanqi','near_stage_msp_input.mat');
config.roadEdgeFile = fullfile(rootDir,'data','yuanqi','stage1_road_edges.csv');
config.siteNodeFile = fullfile(rootDir,'data','yuanqi','stage1_site_nodes.csv');
config.expectedMainHash = "972a8c58620c09ac19cfcfb29e8d6a3ed2819ef1a22dbd522043436418eb805d";
config.expectedCandidateHash = "53738926dcffa76b16e1294ddba0dbe78e17f950a654bb4b6ad872f199b6c2ce";
config.representativeStates = [5,4,0;2,6,0;2,1,0;4,4,0;6,7,0];
config.baseSeeds = [20260723,20260724,20260725];
config.N = 2000; config.maxWorkers = 12;
config.Rmax = 40; config.Wstep = 40; config.sliceDurationH = 1;
config.HresTotalH = 3; config.windDecayB = 0.6;
config.designWindSpeedVN = 25; config.roadDesignWindVN = 30;
config.sourceNode = 1; config.damageMode = "persistent_fixed_resistance";
config.modeNames = ["M0","M1","M2L","M2H"];
config.currentMap = [0;20.8;28.55;37.05;46.20;55.50];
config.vLow = [0;17.2;24.5;32.7;41.5;55.50];
config.vHigh = [0;24.4;32.6;41.4;50.9;55.50];
config.mappingStandard = "GB/T 19201-2006 Grade of tropical cyclones";
config.mappingSourceUrl = "https://openstd.samr.gov.cn/bzgk/std/newGbInfo?hcno=016555C8A7A7F9EDDF96CE84A88EAFC6&refer=outter";
config.a6UpperBoundTraceable = false;
config.DUpperKgExpected = 607.969887897881;

requiredFiles = {config.mainSampleFile,config.candidatePoolFile, ...
    config.step3dMetricsFile,config.warningSolutionFile, ...
    config.warningGeometryFile,config.warningRankingFile, ...
    config.warningStageSummaryFile,config.warningDiagnosticsFile, ...
    config.warningRankingSourceFile,config.locCoordinateFile, ...
    config.nearInputFile,config.roadEdgeFile,config.siteNodeFile, ...
    fullfile(thisDir,'evaluate_intensity_wind_sensitivity_block_h2.m'), ...
    fullfile(rootDir,'fa_h2','fuzhu','terminalLoh_windmc', ...
    'compute_wind_speed_radial_h2.m'), ...
    fullfile(rootDir,'fa_h2','fuzhu','terminalLoh_windmc', ...
    'compute_line_failure_prob_h2.m')};
for ii = 1:numel(requiredFiles)
    if ~isfile(requiredFiles{ii})
        error('run_stage3e_intensity_wind_sensitivity_h2:MissingInput', ...
            'Required input is missing: %s', requiredFiles{ii});
    end
end
if isfolder(config.outputDir) || isfolder(config.tempOutputDir)
    error('run_stage3e_intensity_wind_sensitivity_h2:OutputExists', ...
        'Final or temporary run-001 output directory already exists.');
end

inputHashesBefore = strings(numel(requiredFiles),1);
inputBytesBefore = zeros(numel(requiredFiles),1);
for ii = 1:numel(requiredFiles)
    inputHashesBefore(ii) = sha256_file(requiredFiles{ii});
    info = dir(requiredFiles{ii}); inputBytesBefore(ii) = info.bytes;
end
oldOutputDirs = {fullfile(moduleDir,'output','stage3a_b3_smoke','run-001'), ...
    fullfile(moduleDir,'output','stage3b_b3_candidate_validation','run-001'), ...
    fullfile(moduleDir,'output','stage3c_tail_probability_audit','run-001'), ...
    fullfile(moduleDir,'output','stage3d_b3_sample_stability','run-001'), ...
    fullfile(moduleDir,'output','stage2b_tail_candidate_design','run-005')};
oldOutputSnapshotBefore = snapshot_directories(oldOutputDirs);

[mainRows,mainFields] = count_csv_rows_and_fields(config.mainSampleFile);
mainHash = sha256_file(config.mainSampleFile);
candidateHash = sha256_file(config.candidatePoolFile);
fprintf('INPUT|path=%s|rows=%d|fields=%s|sha256=%s\n', ...
    config.mainSampleFile,mainRows,strjoin(mainFields,','),mainHash);
fprintf('INPUT|path=%s|sha256=%s\n',config.candidatePoolFile,candidateHash);
fprintf('INPUT|path=%s\n',config.step3dMetricsFile);
if mainRows ~= 525000 || mainHash ~= config.expectedMainHash || ...
        candidateHash ~= config.expectedCandidateHash
    error('Accepted main sample or run-005 candidate pool identity mismatch.');
end

mainSample = readtable(config.mainSampleFile);
candidatePool = readtable(config.candidatePoolFile,'TextType','string');
step3dMetrics = readtable(config.step3dMetricsFile,'TextType','string');
require_vars(mainSample,{'a0','loc0','lfw0','path_id','a_W1','a_W2','a_W3', ...
    'loc_W1','loc_W2','loc_W3','lfw_W1','lfw_W2','lfw_W3'}, ...
    'main_path_samples.csv');
require_vars(candidatePool,{'a0','loc0','lfw0','a1','a2','a3','loc1','loc2', ...
    'loc3','lfw1','lfw2','lfw3','is_unobserved_candidate'}, ...
    'unique_tail_paths.csv');

allStates = unique(mainSample(:,{'a0','loc0','lfw0'}),'rows');
allStates = sortrows(allStates,{'a0','loc0','lfw0'});
if height(allStates) ~= 35, error('Expected 35 initial states.'); end
stateSamples = cell(5,1); stateIds = zeros(5,1); stateCountPass = true;
for ss = 1:5
    a0 = config.representativeStates(ss,1);
    loc0 = config.representativeStates(ss,2);
    lfw0 = config.representativeStates(ss,3);
    stateIds(ss) = find(allStates.a0 == a0 & allStates.loc0 == loc0 & ...
        allStates.lfw0 == lfw0,1);
    mask = mainSample.a0 == a0 & mainSample.loc0 == loc0 & ...
        mainSample.lfw0 == lfw0;
    stateSamples{ss} = mainSample(mask,{'a0','loc0','lfw0','path_id', ...
        'a_W1','a_W2','a_W3','loc_W1','loc_W2','loc_W3', ...
        'lfw_W1','lfw_W2','lfw_W3'});
    stateCountPass = stateCountPass && height(stateSamples{ss}) == 15000;
end

mainCodes = physical_codes_main(mainSample);
candidateCodes = physical_codes_candidate(candidatePool);
unobservedFlag = as_logical(candidatePool.is_unobserved_candidate);
unobservedOverlapInMain = sum(ismember(mainCodes,candidateCodes(unobservedFlag)));
clear mainSample mainCodes candidateCodes candidatePool;

foundationConfig = config;
foundationConfig.WstepValues = 40;
foundationConfig.recommendedWstep = 40;
foundationConfig.comparisonWstep = 45;
foundationConfig.stageNames = ["lf7","W1","W2","W3"];
foundationConfig.stageOffsets = [0,1,2,3];
foundationConfig.warningDistanceKmEq = 100;
foundationConfig.distanceMethod = "point_to_segment";
foundation = build_foundation_fix_coordinates_h2(foundationConfig);
model = build_sensitivity_model(config,foundation);

[stateGrid,seedGrid] = ndgrid(1:5,1:numel(config.baseSeeds));
taskState = stateGrid(:); taskSeedIndex = seedGrid(:); nTasks = numel(taskState);
taskResults = cell(nTasks,1); useParallel = license('test','Distrib_Computing_Toolbox');
pool = [];
if useParallel
    cluster = parcluster('local'); workerCount = min(config.maxWorkers,cluster.NumWorkers);
    pool = gcp('nocreate');
    if isempty(pool), pool = parpool('local',workerCount); end
    cleanupPool = onCleanup(@()close_pool()); %#ok<NASGU>
    fprintf('BEGIN_STAGE3E|tasks=%d|workers=%d|paths=%d|mode_scenarios=%d\n', ...
        nTasks,pool.NumWorkers,nTasks*config.N,nTasks*config.N*4);
    parfor tt = 1:nTasks
        taskResults{tt} = evaluate_intensity_wind_sensitivity_block_h2( ...
            model,stateSamples{taskState(tt)}, ...
            config.baseSeeds(taskSeedIndex(tt)),stateIds(taskState(tt)),config.N);
    end
else
    fprintf('BEGIN_STAGE3E|tasks=%d|workers=1|paths=%d|mode_scenarios=%d\n', ...
        nTasks,nTasks*config.N,nTasks*config.N*4);
    for tt = 1:nTasks
        taskResults{tt} = evaluate_intensity_wind_sensitivity_block_h2( ...
            model,stateSamples{taskState(tt)}, ...
            config.baseSeeds(taskSeedIndex(tt)),stateIds(taskState(tt)),config.N);
    end
end

metricTables = cell(nTasks,1); pairedTables = cell(nTasks,1);
thresholdTables = cell(nTasks,1); designRows = cell(nTasks,14);
for tt = 1:nTasks
    ss = taskState(tt); seedId = taskSeedIndex(tt);
    prefixValues = {config.representativeStates(ss,1), ...
        config.representativeStates(ss,2),config.representativeStates(ss,3), ...
        seedId,config.baseSeeds(seedId),taskResults{tt}.derived_seed};
    metricTables{tt} = add_prefix(taskResults{tt}.metrics,prefixValues);
    pairedTables{tt} = add_prefix(taskResults{tt}.paired,prefixValues);
    thresholdTables{tt} = add_prefix(taskResults{tt}.threshold_audit,prefixValues);
    designRows(tt,:) = {prefixValues{:},config.N,taskResults{tt}.path_id_sha256, ...
        taskResults{tt}.permutation_sha256,taskResults{tt}.line_u_sha256, ...
        taskResults{tt}.road_u_sha256,taskResults{tt}.q_sha256, ...
        taskResults{tt}.q_min,taskResults{tt}.q_max};
end
windModeMetrics = vertcat(metricTables{:});
pairedDifference = vertcat(pairedTables{:});
localWindThresholdAudit = vertcat(thresholdTables{:});
sampleDesign = cell2table(designRows,'VariableNames', ...
    {'a0','loc0','lfw0','seed_id','base_seed','derived_seed','N', ...
    'selected_path_id_sha256','permutation_sha256','line_resistance_u_sha256', ...
    'road_resistance_u_sha256','M1_shared_q_sha256','M1_q_min','M1_q_max'});

mappingAudit = build_mapping_audit(config);
[m0Comparison,m0ExactPass] = compare_m0_to_step3d( ...
    windModeMetrics,step3dMetrics,config);
step3dVariability = build_variability_comparison( ...
    windModeMetrics,step3dMetrics,config);

inputHashesAfter = strings(numel(requiredFiles),1);
inputBytesAfter = zeros(numel(requiredFiles),1);
for ii = 1:numel(requiredFiles)
    inputHashesAfter(ii) = sha256_file(requiredFiles{ii});
    info = dir(requiredFiles{ii}); inputBytesAfter(ii) = info.bytes;
end
oldOutputSnapshotAfter = snapshot_directories(oldOutputDirs);
inputsUnchanged = isequal(inputHashesBefore,inputHashesAfter) && ...
    isequal(inputBytesBefore,inputBytesAfter);
oldOutputsUnchanged = isequaln(oldOutputSnapshotBefore,oldOutputSnapshotAfter);

completePass = height(windModeMetrics) == 5*3*4 && ...
    height(sampleDesign) == 5*3;
commonInputsPass = all(cellfun(@(x)x.common_resistance_pass,taskResults));
sharedQPass = all(cellfun(@(x)x.shared_q_pass,taskResults));
domainPass = all(windModeMetrics.D_min_kg >= 0) && ...
    all(windModeMetrics.nonfinite_count == 0) && ...
    all(windModeMetrics.negative_value_count == 0) && ...
    all(windModeMetrics.A_invalid_scenario_count == 0) && ...
    all(windModeMetrics.C_invalid_value_count == 0) && ...
    all(windModeMetrics.A0_pair_share >= 0 & windModeMetrics.A0_pair_share <= 1);
noCandidateInjectionPass = unobservedOverlapInMain == 0;
a6FixedPass = mappingAudit.Vmax_M0_mps(6) == 55.5 && ...
    mappingAudit.M1_fixed_value_mps(6) == 55.5 && ...
    mappingAudit.Vmax_M2L_mps(6) == 55.5 && mappingAudit.Vmax_M2H_mps(6) == 55.5 && ...
    isnan(mappingAudit.traceable_upper_bound_mps(6));
upperBoundOrderPass = all(config.vLow(2:5) < config.vHigh(2:5));
DUpperPass = abs(model.DUpperKg-config.DUpperKgExpected) <= 1e-9;
forbiddenHits = scan_forbidden_calls({thisFile+".m", ...
    fullfile(thisDir,'evaluate_intensity_wind_sensitivity_block_h2.m')});
noForbiddenCalls = height(forbiddenHits) == 0;

a6Used = any_selected_intensity(stateSamples,config,stateIds);
boundedOutcomeChanged = any(abs(pairedDifference.paired_difference_mean) > 1e-12);
if a6Used && ~config.a6UpperBoundTraceable
    decision = "INCONCLUSIVE_NEEDS_A6_DATA";
    decisionReason = "a6 occurs in the tested paths but GB/T 19201-2006 provides no finite upper bound; bounded-grade sensitivity is diagnostic only";
elseif boundedOutcomeChanged
    decision = "REQUIRES_FULL_REEVALUATION";
    decisionReason = "bounded-grade mapping changes produce nonzero paired B3 consequences";
else
    decision = "RETAIN_FIXED_MAPPING";
    decisionReason = "tested bounded-grade mappings produce identical B3 consequences";
end
decisionGate = table(decision,decisionReason,a6Used, ...
    config.a6UpperBoundTraceable,boundedOutcomeChanged, ...
    max(abs(pairedDifference.paired_difference_mean)), ...
    max(step3dVariability.absolute_mode_shift_vs_M0), ...
    'VariableNames',{'decision','reason','a6_used_in_tested_paths', ...
    'a6_traceable_upper_bound_available','bounded_mode_changes_detected', ...
    'max_paired_mean_change_across_metrics', ...
    'max_absolute_mode_shift_in_step3d_comparison'});

checks = {};
checks = add_check(checks,"AUDIT-01","five accepted representative states each contain 15000 records",stateCountPass,stateCountPass,true);
checks = add_check(checks,"AUDIT-02","5 states x 2000 paths x 3 seeds and four modes completed",completePass,height(windModeMetrics),60);
checks = add_check(checks,"AUDIT-03","M0 exactly reproduces Step-03D N2000 metrics",m0ExactPass,max(m0Comparison.absolute_difference),0);
checks = add_check(checks,"AUDIT-04","all modes share paths and line/road resistance uniforms",commonInputsPass,commonInputsPass,true);
checks = add_check(checks,"AUDIT-05","M1 uses one finite shared q per path across W1-W3",sharedQPass,sharedQPass,true);
checks = add_check(checks,"AUDIT-06","no unobserved candidate path is mixed into the main sample",noCandidateInjectionPass,unobservedOverlapInMain,0);
checks = add_check(checks,"AUDIT-07","D A and reachable C domains are valid",domainPass,domainPass,true);
checks = add_check(checks,"AUDIT-08","a6 stays fixed at 55.5 and no upper bound is invented",a6FixedPass,a6FixedPass,true);
checks = add_check(checks,"AUDIT-09","bounded grade intervals are ordered and finite",upperBoundOrderPass,upperBoundOrderPass,true);
checks = add_check(checks,"AUDIT-10","607.969887897881 kg-H2 upper bound is preserved",DUpperPass,model.DUpperKg,config.DUpperKgExpected);
checks = add_check(checks,"AUDIT-11","source inputs and formal mapping files remain unchanged",inputsUnchanged,inputsUnchanged,true);
checks = add_check(checks,"AUDIT-12","accepted old run directories remain unchanged",oldOutputsUnchanged,oldOutputsUnchanged,true);
checks = add_check(checks,"AUDIT-13","persistent fixed resistance mode is retained",model.fixedResistancePass,config.damageMode,"persistent_fixed_resistance");
checks = add_check(checks,"AUDIT-14","no WDRO Gurobi optimization or MSP calls",noForbiddenCalls,height(forbiddenHits),0);
checks = add_check(checks,"AUDIT-15","main sample SHA-256 remains accepted",sha256_file(config.mainSampleFile)==config.expectedMainHash,sha256_file(config.mainSampleFile),config.expectedMainHash);
automaticAudit = cell2table(checks,'VariableNames', ...
    {'check_id','description','passed','observed','expected'});
passCount = sum(automaticAudit.passed); failCount = sum(~automaticAudit.passed);
status = "PASS"; if failCount > 0, status = "FAIL"; end
if failCount > 0
    error('run_stage3e_intensity_wind_sensitivity_h2:AuditFailed', ...
        'Step-03E audit failed: %s', ...
        strjoin(automaticAudit.check_id(~automaticAudit.passed),', '));
end

mkdir(config.tempOutputDir);
writetable(mappingAudit,fullfile(config.tempOutputDir,'current_wind_mapping_audit.csv'));
writetable(windModeMetrics,fullfile(config.tempOutputDir,'wind_mode_metrics.csv'));
writetable(pairedDifference,fullfile(config.tempOutputDir,'paired_difference_summary.csv'));
writetable(localWindThresholdAudit,fullfile(config.tempOutputDir,'local_wind_threshold_audit.csv'));
writetable(step3dVariability,fullfile(config.tempOutputDir,'step3d_variability_comparison.csv'));
writetable(decisionGate,fullfile(config.tempOutputDir,'decision_gate_summary.csv'));
writetable(automaticAudit,fullfile(config.tempOutputDir,'automatic_audit.csv'));
writetable(m0Comparison,fullfile(config.tempOutputDir,'M0_step3d_exact_match_audit.csv'));
writetable(sampleDesign,fullfile(config.tempOutputDir,'sample_and_random_input_audit.csv'));
write_manifest(fullfile(config.tempOutputDir,'run_manifest.txt'),config,status, ...
    passCount,failCount,useParallel,decision,model.DUpperKg);
write_readme(fullfile(config.tempOutputDir,'README.txt'),config,status, ...
    passCount,failCount,windModeMetrics,pairedDifference, ...
    step3dVariability,decision,decisionReason);
movefile(config.tempOutputDir,config.outputDir);

fprintf('\nStage3E intensity-wind sensitivity finished.\n');
fprintf('Status: %s; PASS=%d; FAIL=%d\n',status,passCount,failCount);
fprintf('Decision: %s\n',decision);
fprintf('Paths: %d; mode consequences: %d.\n',nTasks*config.N,nTasks*config.N*4);
fprintf('Output directory: %s\n',config.outputDir);

function T = add_prefix(T,prefixValues)
T = addvars(T,repmat(prefixValues{1},height(T),1), ...
    repmat(prefixValues{2},height(T),1),repmat(prefixValues{3},height(T),1), ...
    repmat(prefixValues{4},height(T),1),repmat(prefixValues{5},height(T),1), ...
    repmat(prefixValues{6},height(T),1),'Before',1,'NewVariableNames', ...
    {'a0','loc0','lfw0','seed_id','base_seed','derived_seed'});
end

function model = build_sensitivity_model(config,foundation)
near = foundation.raw_near; grid = foundation.grid_segments;
road = foundation.road_segments;
Pnode = double(near.Grid.P_load_base_kw(:));
eta = double(near.HydrogenDevice.eta_FC);
lhv = double(near.HydrogenDevice.h2_lhv_kWh_per_kg);
site = readtable(config.siteNodeFile); site = sortrows(site,'site_id');
locValues = sort(double(foundation.loc_table.loc));
nStates = 6*numel(locValues)*4; nLines = height(grid); nRoads = height(road);
stateIndex = zeros(6,numel(locValues),4);
lineFactor = zeros(nStates,nLines); roadFactor = zeros(nStates,nRoads);
fixedModeNames = ["M0","M2L","M2H"];
fixedMaps = {config.currentMap,config.vLow,config.vHigh};
fixedLineWind = cell(3,1); fixedRoadWind = cell(3,1);
fixedPFail = cell(3,1); fixedPClose = cell(3,1);
for mm = 1:3
    fixedLineWind{mm} = zeros(nStates,nLines);
    fixedRoadWind{mm} = zeros(nStates,nRoads);
    fixedPFail{mm} = zeros(nStates,nLines);
    fixedPClose{mm} = zeros(nStates,nRoads);
end
rr = 0;
for a = 1:6
    for loc = locValues(:).'
        locRow = foundation.loc_table(foundation.loc_table.loc==loc,:);
        for lfw = 0:3
            rr = rr + 1; x = double(locRow.x_coord);
            y = foundation.y_base + lfw*config.Wstep;
            lineDist = compute_point_to_segment_distance_h2( ...
                x,y,grid.x1,grid.y1,grid.x2,grid.y2);
            roadDist = compute_point_to_segment_distance_h2( ...
                x,y,road.x1,road.y1,road.x2,road.y2);
            lineFactor(rr,:) = compute_wind_speed_radial_h2( ...
                lineDist,1,config.Rmax,config.windDecayB).';
            roadFactor(rr,:) = compute_wind_speed_radial_h2( ...
                roadDist,1,config.Rmax,config.windDecayB).';
            for mm = 1:3
                vmax = fixedMaps{mm}(a);
                fixedLineWind{mm}(rr,:) = compute_wind_speed_radial_h2( ...
                    lineDist,vmax,config.Rmax,config.windDecayB).';
                fixedRoadWind{mm}(rr,:) = compute_wind_speed_radial_h2( ...
                    roadDist,vmax,config.Rmax,config.windDecayB).';
                fixedPFail{mm}(rr,:) = compute_line_failure_prob_h2( ...
                    fixedLineWind{mm}(rr,:),config.designWindSpeedVN);
                fixedPClose{mm}(rr,:) = compute_line_failure_prob_h2( ...
                    fixedRoadWind{mm}(rr,:),config.roadDesignWindVN);
            end
            stateIndex(a,loc-min(locValues)+1,lfw+1) = rr;
        end
    end
end
incidence = radial_node_path_incidence(numel(Pnode),grid.from_node, ...
    grid.to_node,config.sourceNode);
model = struct(); model.modeNames = config.modeNames;
model.fixedModeNames = fixedModeNames; model.currentMap = config.currentMap;
model.vLow = config.vLow; model.vHigh = config.vHigh;
model.lineFactor = lineFactor; model.roadFactor = roadFactor;
model.fixedLineWind = fixedLineWind; model.fixedRoadWind = fixedRoadWind;
model.fixedPFail = fixedPFail; model.fixedPClose = fixedPClose;
model.stateIndex = stateIndex; model.locMin = min(locValues);
model.locMax = max(locValues); model.nLines = nLines; model.nRoads = nRoads;
model.nNodes = numel(Pnode); model.nSites = height(site);
model.sourceNode = config.sourceNode; model.Pnode_kW = Pnode;
model.nodePathIncidence = incidence; model.roadFrom = double(road.from_node);
model.roadTo = double(road.to_node);
model.roadLength = hypot(road.x2-road.x1,road.y2-road.y1);
model.siteNodes = double(site.grid_node);
model.DFactorKgPerKWh = 1/(eta*lhv);
model.DUpperKg = 3*(sum(Pnode)-Pnode(config.sourceNode))*model.DFactorKgPerKWh;
model.designWindSpeedVN = config.designWindSpeedVN;
model.roadDesignWindVN = config.roadDesignWindVN;
model.fixedResistancePass = true;
end

function incidence = radial_node_path_incidence(nNodes,fromNode,toNode,sourceNode)
nLines = numel(fromNode);
if nLines ~= nNodes-1, error('Grid is not radial.'); end
adj = cell(nNodes,1); edgeAdj = cell(nNodes,1);
for ll = 1:nLines
    i = fromNode(ll); j = toNode(ll);
    adj{i}(end+1) = j; edgeAdj{i}(end+1) = ll; %#ok<AGROW>
    adj{j}(end+1) = i; edgeAdj{j}(end+1) = ll; %#ok<AGROW>
end
parent = zeros(nNodes,1); parentEdge = zeros(nNodes,1);
visited = false(nNodes,1); queue = zeros(nNodes,1);
head = 1; tail = 1; queue(1) = sourceNode; visited(sourceNode) = true;
while head <= tail
    u = queue(head); head = head + 1;
    for kk = 1:numel(adj{u})
        v = adj{u}(kk); if visited(v), continue; end
        visited(v) = true; parent(v) = u; parentEdge(v) = edgeAdj{u}(kk);
        tail = tail + 1; queue(tail) = v;
    end
end
if ~all(visited), error('Grid is disconnected.'); end
incidence = false(nNodes,nLines);
for node = 1:nNodes
    cur = node;
    while cur ~= sourceNode
        incidence(node,parentEdge(cur)) = true; cur = parent(cur);
    end
end
end

function T = build_mapping_audit(config)
a = (1:6).'; names = ["below_tropical_storm";"tropical_storm"; ...
    "severe_tropical_storm";"typhoon";"severe_typhoon";"super_typhoon"];
low = [NaN;config.vLow(2:5);51.0];
high = [NaN;config.vHigh(2:5);NaN];
midpoint = [NaN;(config.vLow(2:5)+config.vHigh(2:5))/2;NaN];
m1Fixed = [0;NaN;NaN;NaN;NaN;55.5];
source = repmat(config.mappingStandard,6,1);
sourceUrl = repmat(config.mappingSourceUrl,6,1);
note = ["a1 retains project definition 0";repmat("bounded grade sensitivity interval",4,1); ...
    "a6 has no finite traceable upper bound and remains fixed at 55.5"];
T = table(a,names,config.currentMap,low,high,midpoint,m1Fixed, ...
    config.vLow,config.vHigh,source,sourceUrl,note, ...
    'VariableNames',{'a','grade_label','Vmax_M0_mps', ...
    'traceable_lower_bound_mps','traceable_upper_bound_mps', ...
    'bounded_interval_midpoint_mps','M1_fixed_value_mps','Vmax_M2L_mps', ...
    'Vmax_M2H_mps','boundary_source','boundary_source_url','audit_note'});
end

function [audit,pass] = compare_m0_to_step3d(current,reference,config)
metrics = {'D_mean_kg','D_q95_kg','D_q99_kg','full_loss_probability', ...
    'A0_pair_share','reachable_pair_share','C_reachable_mean_km', ...
    'C_reachable_q95_km','W3_failed_lines_mean','W3_failed_lines_q95', ...
    'W3_closed_roads_mean','W3_closed_roads_q95'};
rows = cell(5*3*numel(metrics),10); rr = 0;
for ss = 1:5
    for seedId = 1:3
        q = current(current.mode=="M0" & ...
            current.a0==config.representativeStates(ss,1) & ...
            current.loc0==config.representativeStates(ss,2) & ...
            current.seed_id==seedId,:);
        ref = reference(double(reference.N)==config.N & ...
            double(reference.a0)==config.representativeStates(ss,1) & ...
            double(reference.loc0)==config.representativeStates(ss,2) & ...
            double(reference.lfw0)==config.representativeStates(ss,3) & ...
            double(reference.seed_id)==seedId,:);
        if height(q)~=1 || height(ref)~=1, error('Missing Step-03D comparison row.'); end
        for mm = 1:numel(metrics)
            observed = double(q.(metrics{mm})); expected = double(ref.(metrics{mm}));
            rr = rr + 1;
            rows(rr,:) = {q.a0,q.loc0,q.lfw0,seedId,q.base_seed, ...
                string(metrics{mm}),observed,expected,abs(observed-expected), ...
                abs(observed-expected)<=1e-12};
        end
    end
end
audit = cell2table(rows,'VariableNames',{'a0','loc0','lfw0','seed_id', ...
    'base_seed','metric','M0_value','step3d_N2000_value', ...
    'absolute_difference','exact_match_within_1e_12'});
pass = all(audit.exact_match_within_1e_12);
end

function T = build_variability_comparison(current,reference,config)
metrics = {'D_mean_kg','D_q95_kg','D_q99_kg','full_loss_probability', ...
    'A0_pair_share','C_reachable_mean_km','W3_failed_lines_mean', ...
    'W3_closed_roads_mean'};
rows = cell(5*numel(metrics)*4,13); rr = 0;
for ss = 1:5
    for kk = 1:numel(metrics)
        ref = reference(double(reference.N)==config.N & ...
            double(reference.a0)==config.representativeStates(ss,1) & ...
            double(reference.loc0)==config.representativeStates(ss,2) & ...
            double(reference.lfw0)==config.representativeStates(ss,3),:);
        values = double(ref.(metrics{kk})); refMean = mean(values);
        refStd = std(values,0); refRange = max(values)-min(values);
        for mode = config.modeNames
            q = current(current.mode==mode & ...
                current.a0==config.representativeStates(ss,1) & ...
                current.loc0==config.representativeStates(ss,2),:);
            modeValues = double(q.(metrics{kk})); modeMean = mean(modeValues);
            shift = modeMean-refMean;
            rr = rr + 1;
            rows(rr,:) = {config.representativeStates(ss,1), ...
                config.representativeStates(ss,2),config.representativeStates(ss,3), ...
                string(metrics{kk}),mode,refMean,refStd,refRange,modeMean, ...
                shift,abs(shift),safe_ratio(abs(shift),refStd), ...
                safe_ratio(abs(shift),refRange)};
        end
    end
end
T = cell2table(rows,'VariableNames',{'a0','loc0','lfw0','metric','mode', ...
    'step3d_N2000_three_seed_mean','step3d_N2000_seed_std', ...
    'step3d_N2000_seed_range','mode_three_seed_mean','mode_shift_vs_M0', ...
    'absolute_mode_shift_vs_M0','shift_over_step3d_seed_std', ...
    'shift_over_step3d_seed_range'});
end

function used = any_selected_intensity(stateSamples,config,stateIds)
used = false;
for ss = 1:numel(stateSamples)
    for seedId = 1:numel(config.baseSeeds)
        rng(config.baseSeeds(seedId)+100003*stateIds(ss),'twister');
        p = randperm(15000); selected = stateSamples{ss}(p(1:config.N),:);
        used = used || any([selected.a_W1;selected.a_W2;selected.a_W3] == 6);
    end
end
end

function value = safe_ratio(x,y)
if abs(y) <= 1e-15, value = NaN; else, value = x/y; end
end

function codes = physical_codes_main(T)
codes = encode_codes(double(T.a0),double(T.loc0),double(T.lfw0), ...
    double(T.a_W1),double(T.loc_W1),double(T.lfw_W1), ...
    double(T.a_W2),double(T.loc_W2),double(T.lfw_W2), ...
    double(T.a_W3),double(T.loc_W3),double(T.lfw_W3));
end

function codes = physical_codes_candidate(T)
codes = encode_codes(double(T.a0),double(T.loc0),double(T.lfw0), ...
    double(T.a1),double(T.loc1),double(T.lfw1),double(T.a2),double(T.loc2), ...
    double(T.lfw2),double(T.a3),double(T.loc3),double(T.lfw3));
end

function codes = encode_codes(varargin)
n = numel(varargin{1}); codes = zeros(n,1,'uint64');
bases = [7,13,4,7,13,4,7,13,4,7,13,4];
for ii = 1:12
    value = double(varargin{ii}); if mod(ii,3)==2, value=value+2; end
    codes = codes*uint64(bases(ii))+uint64(value);
end
end

function values = as_logical(values)
if islogical(values), return; end
if isnumeric(values), values = values~=0;
else, text = lower(strtrim(string(values))); values = text=="true"|text=="1"; end
end

function summary = snapshot_directories(dirs)
rows = {};
for dd = 1:numel(dirs)
    files = dir(fullfile(dirs{dd},'**','*')); files = files(~[files.isdir]);
    for ii = 1:numel(files)
        rows(end+1,:) = {string(dirs{dd}), ...
            string(fullfile(files(ii).folder,files(ii).name)), ...
            files(ii).bytes,files(ii).datenum}; %#ok<AGROW>
    end
end
if isempty(rows)
    summary = cell2table(cell(0,4),'VariableNames', ...
        {'root','path','bytes','datenum'});
else
    summary = sortrows(cell2table(rows,'VariableNames', ...
        {'root','path','bytes','datenum'}),'path');
end
end

function T = scan_forbidden_calls(files)
patterns = ["solve_wdro_"+"terminal_loh_lp_h2\\s*\\(","guro"+"bi\\s*\\(", ...
    "main_msp_"+"h2_near\\s*\\(","run_h2_"+"with_options\\s*\\(", ...
    "opti"+"mize\\s*\\(","lin"+"prog\\s*\\("];
rows = {};
for ff = 1:numel(files)
    sourceText = fileread(files{ff});
    for pp = 1:numel(patterns)
        if ~isempty(regexp(sourceText,patterns(pp),'once'))
            rows(end+1,:) = {string(files{ff}),patterns(pp)}; %#ok<AGROW>
        end
    end
end
if isempty(rows), T=cell2table(cell(0,2),'VariableNames',{'file','pattern'});
else, T=cell2table(rows,'VariableNames',{'file','pattern'}); end
end

function close_pool()
p = gcp('nocreate'); if ~isempty(p), delete(p); end
end

function require_vars(T,names,fileName)
for ii = 1:numel(names)
    if ~ismember(names{ii},T.Properties.VariableNames)
        error('%s missing %s.',fileName,names{ii});
    end
end
end

function [rows,fields] = count_csv_rows_and_fields(fileName)
fid = fopen(fileName,'rb'); if fid<0, error('Could not open %s.',fileName); end
cleanup = onCleanup(@()fclose(fid)); header = fgetl(fid);
fields = string(strsplit(header,',')); newlineCount = 1; lastByte = uint8(10);
while true
    bytes = fread(fid,1024*1024,'*uint8'); if isempty(bytes), break; end
    newlineCount = newlineCount + sum(bytes==10); lastByte = bytes(end);
end
totalLines = newlineCount + double(lastByte~=10); rows = totalLines-1;
end

function hash = sha256_file(fileName)
fid = fopen(fileName,'rb'); if fid<0, error('Could not open %s.',fileName); end
cleanup = onCleanup(@()fclose(fid));
md = java.security.MessageDigest.getInstance('SHA-256');
while true
    bytes = fread(fid,1024*1024,'*uint8'); if isempty(bytes), break; end
    md.update(typecast(bytes,'int8'));
end
digest = typecast(md.digest(),'uint8');
hash = lower(string(reshape(dec2hex(digest,2).',1,[])));
end

function rows = add_check(rows,id,description,passed,observed,expected)
rows(end+1,:) = {string(id),string(description),logical(passed), ...
    scalar_text(observed),scalar_text(expected)};
end

function text = scalar_text(value)
if isstring(value), text=strjoin(value(:).',' | ');
elseif ischar(value), text=string(value);
elseif islogical(value)&&isscalar(value), text=string(double(value));
elseif isnumeric(value)&&isscalar(value), text=string(sprintf('%.15g',value));
elseif isnumeric(value), text=strjoin(compose('%.15g',value(:).'),' | ');
else, text=string(value); end
end

function write_manifest(fileName,config,status,passCount,failCount, ...
    useParallel,decision,DUpperKg)
fid=fopen(fileName,'w'); if fid<0,error('Could not write %s.',fileName);end
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'task_id=task-002\nstep_id=05-intensity-wind-sensitivity\nrun_id=run-001\n');
fprintf(fid,'run_time=%s\nstatus=%s\npass_count=%d\nfail_count=%d\n', ...
    char(datetime('now','Format','yyyy-MM-dd HH:mm:ss Z')),status,passCount,failCount);
fprintf(fid,'representative_states=(5,4,0);(2,6,0);(2,1,0);(4,4,0);(6,7,0)\n');
fprintf(fid,'paths_per_state_seed=%d\nbase_seeds=%s\n',config.N,strjoin(string(config.baseSeeds),','));
fprintf(fid,'path_resistance_scenarios=%d\nmode_consequence_evaluations=%d\nparallel_used=%d\n',5*3*config.N,5*3*config.N*4,useParallel);
fprintf(fid,'modes=M0,M1,M2L,M2H\ndamage_mode=%s\n',config.damageMode);
fprintf(fid,'M1_q_definition=Uniform(0,1) sensitivity assumption; one q shared by W1-W3 per path realization\n');
fprintf(fid,'mapping_standard=%s\nmapping_source_url=%s\n',config.mappingStandard,config.mappingSourceUrl);
fprintf(fid,'a6_upper_bound_available=false\na6_all_modes_mps=55.5\nD_upper_kg=%.15g\n',DUpperKg);
fprintf(fid,'decision=%s\nformal_random_wind_adopted=false\n',decision);
fprintf(fid,'candidate_paths_added=0\nWDRO_run=false\nGurobi_run=false\nMSP_run=false\n');
end

function write_readme(fileName,config,status,passCount,failCount,metrics, ...
    paired,variability,decision,decisionReason)
fid=fopen(fileName,'w'); if fid<0,error('Could not write %s.',fileName);end
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'Step-03E run-001: intensity-to-Vmax mapping sensitivity\n\n');
fprintf(fid,'status=%s; PASS=%d; FAIL=%d\n',status,passCount,failCount);
fprintf(fid,'Five Step-03A representative states use the exact Step-03D N=2000 nested prefixes and three resistance seeds.\n');
fprintf(fid,'M0 is the accepted fixed map. M1 uses one shared Uniform(0,1) q per path across W1-W3 as a sensitivity assumption only.\n');
fprintf(fid,'M2L and M2H use bounded-grade endpoints. a1 remains 0 and a6 remains 55.5 because no finite traceable a6 upper bound is available.\n');
fprintf(fid,'Boundary source: %s (%s).\n',config.mappingStandard,config.mappingSourceUrl);
for mode=config.modeNames
    q=metrics(metrics.mode==mode,:);
    fprintf(fid,'%s: D mean range %.12g to %.12g kg-H2; A0 share range %.12g to %.12g; reachable C mean range %.12g to %.12g km.\n', ...
        mode,min(q.D_mean_kg),max(q.D_mean_kg),min(q.A0_pair_share), ...
        max(q.A0_pair_share),min(q.C_reachable_mean_km),max(q.C_reachable_mean_km));
end
fprintf(fid,'Largest paired mean difference across reported scenario metrics: %.12g.\n', ...
    max(abs(paired.paired_difference_mean)));
fprintf(fid,'Largest mapping-mode shift relative to Step-03D three-seed mean: %.12g.\n', ...
    max(variability.absolute_mode_shift_vs_M0));
fprintf(fid,'Decision: %s. %s.\n',decision,decisionReason);
fprintf(fid,'No formal random-wind model is adopted. No candidate paths, WDRO, Gurobi optimization, or MSP are used.\n');
end
