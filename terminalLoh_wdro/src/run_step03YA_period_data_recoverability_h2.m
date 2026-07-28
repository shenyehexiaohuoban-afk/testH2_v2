%% Step-03Y-A: audit deterministic recovery of W1/W2/W3 D/A/C data.
% This is a read-only replay audit. It does not call Gurobi, WDRO, MSP, or
% any TerminalLOH/Q/distance optimization.
clear; clc;

started = tic;
thisFile = mfilename('fullpath');
thisDir = fileparts(thisFile);
moduleDir = fileparts(thisDir);
rootDir = fileparts(moduleDir);
addpath(rootDir);
addpath(thisDir);
addpath(fullfile(rootDir, 'fa_h2', 'fuzhu', 'terminalLoh_windmc'));

expectedBranch = "task/002-stage2b-b3-smoke";
expectedHead = "2ae3d68a52c044086f37d21fd264005e796e1c9e";
states = [7; 11; 18; 21; 30; 31];
rowsPerState = 15000;
baseSeed = 20260723;
windSeedOffset = 330000000;
demandToleranceKg = 1e-10;
csvSummaryTolerance = 1e-12;
runName = "run-002";
outputDir = fullfile(rootDir, 'results', 'task-002-stage2b-b3-smoke', ...
    '27-period-data-recoverability', runName);
tempDir = outputDir + ".tmp";
if isfolder(outputDir) || isfolder(tempDir)
    error('Step-03Y-A output path already exists: %s', runName);
end

[status, branch] = system('git branch --show-current');
if status ~= 0, error('Could not read current branch.'); end
[status, head] = system('git rev-parse HEAD');
if status ~= 0, error('Could not read local HEAD.'); end
[status, upstream] = system('git rev-parse "@{upstream}"');
if status ~= 0, error('Could not read upstream HEAD.'); end
branch = string(strtrim(branch));
head = string(strtrim(head));
upstream = string(strtrim(upstream));
if branch ~= expectedBranch || head ~= expectedHead || upstream ~= expectedHead
    error('Frozen Git baseline mismatch: branch=%s HEAD=%s upstream=%s.', ...
        branch, head, upstream);
end
[status, trackedDiff] = system('git status --porcelain --untracked-files=no');
if status ~= 0 || strlength(strtrim(string(trackedDiff))) > 0
    error('Tracked or staged worktree changes are present; stopping.');
end

protectedRelative = [ ...
    "results/task-002-stage2b-b3-smoke/16-dac-transport-cost-audit/run-001"; ...
    "results/task-002-stage2b-b3-smoke/23-fixed-decision-loss-consistency/run-001.failed-001"; ...
    "results/task-002-stage2b-b3-smoke/24-old-vs-ctilde-fixed-loss"; ...
    "results/task-002-stage2b-b3-smoke/25-old-cost-evidence-trace"; ...
    "results/task-002-stage2b-b3-smoke/26-old-ground-cost-recompute"; ...
    "results/task-002-stage2b-b3-smoke/27-period-data-recoverability/run-001.failed-001"; ...
    "terminalLoh_wdro/src/run_step03XB_old_ground_cost_recompute.py"; ...
    "terminalLoh_wdro/src/run_step03X_old_vs_ctilde_fixed_loss.py"];
protectedBefore = strings(numel(protectedRelative), 1);
for ii = 1:numel(protectedRelative)
    protectedBefore(ii) = path_digest(fullfile(rootDir, protectedRelative(ii)));
    if protectedBefore(ii) == "MISSING"
        error('Protected pre-existing path is missing: %s', protectedRelative(ii));
    end
end

config = build_config(rootDir, moduleDir, thisDir);
inputPaths = [ ...
    string(config.mainSampleFile); string(config.nominalCsv); ...
    string(config.nominalMat); string(config.seedMapFile); ...
    string(config.stepWPairFile); string(config.formalWindConfigFile); ...
    string(config.warningSolutionFile); string(config.locCoordinateFile); ...
    string(config.nearInputFile); string(config.roadEdgeFile); ...
    string(config.siteNodeFile); ...
    string(fullfile(thisDir, 'evaluate_frozen_wdro_dataset_block_h2.m')); ...
    string(fullfile(thisDir, 'run_stage3j_wdro_input_freeze_h2.m'))];
for ii = 1:numel(inputPaths)
    if ~isfile(inputPaths(ii)), error('Required input missing: %s', inputPaths(ii)); end
end
inputHashBefore = strings(numel(inputPaths), 1);
for ii = 1:numel(inputPaths), inputHashBefore(ii) = sha256_file(inputPaths(ii)); end
if inputHashBefore(1) ~= "972a8c58620c09ac19cfcfb29e8d6a3ed2819ef1a22dbd522043436418eb805d"
    error('Main path sample SHA-256 mismatch.');
end
if inputHashBefore(2) ~= "366dc3c0b57bfd76aca92f51ae1db82b93c764c87fa15e8cb4dd32388d018168"
    error('Nominal scenario CSV SHA-256 mismatch.');
end
if inputHashBefore(3) ~= "6936a696f5cde137aca483f8c32adee33b52cbd90559a8e6395f3686c0712945"
    error('Nominal D/A/C MAT SHA-256 mismatch.');
end

nominalOptions = detectImportOptions(config.nominalCsv);
nominalOptions = setvartype(nominalOptions, 'initial_state', 'string');
nominal = readtable(config.nominalCsv, nominalOptions);
if any(string(nominal.dataset_role) ~= "nominal")
    error('Nominal CSV contains a non-nominal dataset role.');
end
mainSample = readtable(config.mainSampleFile);
seedMap = readtable(config.seedMapFile, 'TextType', 'string');
seedMap = seedMap(seedMap.dataset_role == "nominal" & ...
    ismember(double(seedMap.initial_state_id), states), :);
if height(seedMap) ~= numel(states)
    error('Nominal seed map does not contain exactly the six requested states.');
end

matFields = string(who('-file', config.nominalMat));
expectedMatFields = sort(["D_node_kg"; "A_site_node"; "C_site_node_km"; ...
    "path_id"; "initial_state_id"]);
directMatPeriodAvailable = any(contains(lower(matFields), ...
    ["period", "stage", "w1", "w2", "w3", "d1", "d2", "d3"]));
csvFields = string(nominal.Properties.VariableNames(:));
periodDataFieldCandidates = ["d1"; "d2"; "d3"; "reachtau"; "costtau"; ...
    "d_period_kg"; "a_period"; "c_period_km"; ...
    "d_node_w1"; "d_node_w2"; "d_node_w3"; ...
    "a_site_node_w1"; "a_site_node_w2"; "a_site_node_w3"; ...
    "c_site_node_w1"; "c_site_node_w2"; "c_site_node_w3"];
directCsvPeriodDACAvailable = any(ismember(lower(csvFields), periodDataFieldCandidates));
if ~isequal(sort(matFields), expectedMatFields)
    error('Nominal MAT field set changed unexpectedly.');
end

pairs = readtable(config.stepWPairFile, 'TextType', 'string');
testedRows = cell(numel(states) * 3, 26);
selectedScenarioIds = cell(numel(states), 1);
tt = 0;
for ss = 1:numel(states)
    stateId = states(ss);
    local = pairs(double(pairs.initial_state_id) == stateId, :);
    candidates = unique([double(local.scenario_r); double(local.scenario_s)]);
    candidates = sort(candidates);
    if numel(candidates) < 3, error('Too few Step-03W scenarios for state %d.', stateId); end
    selected = candidates([1, floor(numel(candidates) / 2) + 1, end]);
    selectedScenarioIds{ss} = selected(:);
    for kk = 1:3
        row = nominal(double(nominal.initial_state_id) == stateId & ...
            double(nominal.scenario_id_in_state) == selected(kk), :);
        if height(row) ~= 1, error('Nominal scenario identity is not unique.'); end
        tt = tt + 1;
        testedRows(tt, :) = {stateId, selected(kk), double(row.path_id), ...
            double(row.joint_stream_position), double(row.a0), double(row.loc0), ...
            double(row.lfw0), double(row.a_W1), double(row.loc_W1), ...
            double(row.lfw_W1), double(row.a_W2), double(row.loc_W2), ...
            double(row.lfw_W2), double(row.a_W3), double(row.loc_W3), ...
            double(row.lfw_W3), double(row.wind_W1_mps), ...
            double(row.wind_W2_mps), double(row.wind_W3_mps), ...
            double(row.wind_seed), double(row.resistance_seed), ...
            double(row.base_joint_seed), string(row.dataset_role), ...
            "Step-03W frozen pair endpoint", "min/middle/max unique endpoint", ...
            "Step-03J nominal"};
    end
end
testedScenarios = cell2table(testedRows, 'VariableNames', ...
    {'initial_state_id', 'scenario_id', 'path_id', 'joint_stream_position', ...
    'a0', 'loc0', 'lfw0', 'a_W1', 'loc_W1', 'lfw_W1', ...
    'a_W2', 'loc_W2', 'lfw_W2', 'a_W3', 'loc_W3', 'lfw_W3', ...
    'wind_W1_mps', 'wind_W2_mps', 'wind_W3_mps', 'wind_seed', ...
    'resistance_seed', 'base_joint_seed', 'dataset_role', ...
    'selection_pool', 'selection_rule', 'data_source'});

model = build_replay_model(config);
nTest = height(testedScenarios);
D_period_kg = zeros(nTest, 3, model.nNodes);
A_period = false(nTest, 3, model.nSites, model.nNodes);
C_period_km = inf(nTest, 3, model.nSites, model.nNodes);
line_failed_period = false(nTest, 3, model.nLines);
road_closed_period = false(nTest, 3, model.nRoads);
road_slowdown_period = zeros(nTest, 3, model.nRoads);
line_resistance_uniform = zeros(nTest, model.nLines);
road_resistance_uniform = zeros(nTest, model.nRoads);
wind_quantile = zeros(nTest, 3);

comparisonRows = cell(nTest, 37);
streamRows = cell(numel(states), 14);
outRow = 0;
nominalSidecar = matfile(config.nominalMat);
windConfig = load_formal_b3_wind_config_h2(config.formalWindConfigFile);
if windConfig.defaultMode ~= "stagewise_random_triangular"
    error('Formal wind default is not stagewise_random_triangular.');
end

for ss = 1:numel(states)
    stateId = states(ss);
    stateMeta = nominal(double(nominal.initial_state_id) == stateId, :);
    if height(stateMeta) ~= rowsPerState
        error('State %d nominal block does not contain 15000 rows.', stateId);
    end
    a0 = double(stateMeta.a0(1)); loc0 = double(stateMeta.loc0(1));
    lfw0 = double(stateMeta.lfw0(1));
    stateSample = mainSample(double(mainSample.a0) == a0 & ...
        double(mainSample.loc0) == loc0 & double(mainSample.lfw0) == lfw0, :);
    if height(stateSample) ~= rowsPerState
        error('State %d main-sample block does not contain 15000 rows.', stateId);
    end

    resistanceSeed = baseSeed + 100003 * stateId;
    rng(resistanceSeed, 'twister');
    permutation = randperm(rowsPerState).';
    lineU = rand(rowsPerState, model.nLines);
    roadU = rand(rowsPerState, model.nRoads);
    selectedSample = stateSample(permutation, :);

    windSeed = windSeedOffset + baseSeed + 100019 * stateId;
    windStream = RandStream('mt19937ar', 'Seed', windSeed);
    qAll = rand(windStream, rowsPerState, 3);
    seedRow = seedMap(double(seedMap.initial_state_id) == stateId, :);
    permutationHash = sha256_uint32(permutation);
    q1Hash = sha256_double(qAll(:, 1)); q2Hash = sha256_double(qAll(:, 2));
    q3Hash = sha256_double(qAll(:, 3));
    streamRows(ss, :) = {stateId, a0, loc0, lfw0, resistanceSeed, windSeed, ...
        permutationHash, string(seedRow.step3i_permutation_sha256), ...
        q1Hash, string(seedRow.q_W1_sha256), q2Hash, ...
        string(seedRow.q_W2_sha256), q3Hash, string(seedRow.q_W3_sha256)};
    if resistanceSeed ~= double(seedRow.resistance_seed) || ...
            windSeed ~= double(seedRow.wind_seed) || ...
            permutationHash ~= string(seedRow.step3i_permutation_sha256) || ...
            q1Hash ~= string(seedRow.q_W1_sha256) || ...
            q2Hash ~= string(seedRow.q_W2_sha256) || ...
            q3Hash ~= string(seedRow.q_W3_sha256)
        error('State %d random-stream identity does not match Step-03J.', stateId);
    end

    testMask = testedScenarios.initial_state_id == stateId;
    localTests = testedScenarios(testMask, :);
    localOutputIndices = find(testMask);
    for kk = 1:height(localTests)
        outRow = outRow + 1;
        scenarioId = localTests.scenario_id(kk);
        pathId = localTests.path_id(kk);
        streamPosition = localTests.joint_stream_position(kk);
        sampleRow = selectedSample(streamPosition, :);
        if double(sampleRow.path_id) ~= pathId
            error('State %d scenario %d stream-position/path mapping failed.', ...
                stateId, scenarioId);
        end
        if any(double([sampleRow.a_W1, sampleRow.loc_W1, sampleRow.lfw_W1, ...
                sampleRow.a_W2, sampleRow.loc_W2, sampleRow.lfw_W2, ...
                sampleRow.a_W3, sampleRow.loc_W3, sampleRow.lfw_W3]) ~= ...
                double([localTests.a_W1(kk), localTests.loc_W1(kk), localTests.lfw_W1(kk), ...
                localTests.a_W2(kk), localTests.loc_W2(kk), localTests.lfw_W2(kk), ...
                localTests.a_W3(kk), localTests.loc_W3(kk), localTests.lfw_W3(kk)]))
            error('State %d scenario %d W-path identity mismatch.', stateId, scenarioId);
        end

        aStage = double([sampleRow.a_W1, sampleRow.a_W2, sampleRow.a_W3]);
        locStage = double([sampleRow.loc_W1, sampleRow.loc_W2, sampleRow.loc_W3]);
        lfwStage = double([sampleRow.lfw_W1, sampleRow.lfw_W2, sampleRow.lfw_W3]);
        vmax = zeros(1, 3); pFail = cell(3, 1); pClose = cell(3, 1);
        for tau = 1:3
            vmax(tau) = triangular_by_level(aStage(tau), qAll(streamPosition, tau), ...
                windConfig.randomLower, windConfig.randomMode, windConfig.randomUpper);
            idx = state_index(model, aStage(tau), locStage(tau), lfwStage(tau));
            lineWind = model.lineFactor(idx, :) .* vmax(tau);
            roadWind = model.roadFactor(idx, :) .* vmax(tau);
            pFail{tau} = compute_line_failure_prob_h2(lineWind, model.designWindSpeedVN);
            pClose{tau} = compute_line_failure_prob_h2(roadWind, model.roadDesignWindVN);
        end
        windError = max(abs(vmax - double([localTests.wind_W1_mps(kk), ...
            localTests.wind_W2_mps(kk), localTests.wind_W3_mps(kk)])));
        if windError > 1e-12
            error('State %d scenario %d wind replay mismatch.', stateId, scenarioId);
        end

        uLine = lineU(streamPosition, :);
        uRoad = roadU(streamPosition, :);
        failed = false(3, model.nLines); closed = false(3, model.nRoads);
        slow = zeros(3, model.nRoads); outage = false(3, model.nNodes);
        failed(1, :) = uLine <= pFail{1};
        failed(2, :) = failed(1, :) | (uLine <= pFail{2});
        failed(3, :) = failed(2, :) | (uLine <= pFail{3});
        closed(1, :) = uRoad <= pClose{1};
        closed(2, :) = closed(1, :) | (uRoad <= pClose{2});
        closed(3, :) = closed(2, :) | (uRoad <= pClose{3});
        slow(1, :) = pClose{1};
        slow(2, :) = max(slow(1, :), pClose{2});
        slow(3, :) = max(slow(2, :), pClose{3});
        for tau = 1:3
            outage(tau, :) = (double(failed(tau, :)) * model.nodePathIncidence.') > 0;
            outage(tau, model.sourceNode) = false;
        end
        Dtau = double(outage) .* model.Pnode_kW.' * model.DFactorKgPerKWh;

        reachTau = false(3, model.nSites, model.nNodes);
        costTau = inf(3, model.nSites, model.nNodes);
        reachableTotal = 0; stageCsum = 0;
        for tau = 1:3
            edgeCost = model.roadLength .* (1 + slow(tau, :).');
            edgeCost(closed(tau, :).') = Inf;
            [reach, cost] = road_state(model.nNodes, model.roadFrom, ...
                model.roadTo, edgeCost, model.siteNodes);
            reachTau(tau, :, :) = reach;
            costTau(tau, :, :) = cost;
            reachableTotal = reachableTotal + sum(reach, 'all');
            stageCsum = stageCsum + sum(cost(reach));
        end

        Dagg = sum(Dtau, 1);
        Aagg = false(model.nSites, model.nNodes);
        Cagg = inf(model.nSites, model.nNodes);
        for nn = 1:model.nNodes
            critical = find(Dtau(:, nn) > demandToleranceKg);
            if isempty(critical), critical = (1:3).'; end
            for site = 1:model.nSites
                reach = squeeze(reachTau(critical, site, nn));
                if all(reach)
                    Aagg(site, nn) = true;
                    costs = squeeze(costTau(critical, site, nn));
                    Cagg(site, nn) = mean(costs);
                end
            end
        end

        globalRow = (stateId - 1) * rowsPerState + scenarioId;
        nominalPath = double(nominalSidecar.path_id(globalRow, 1));
        nominalState = double(nominalSidecar.initial_state_id(globalRow, 1));
        Dnominal = double(nominalSidecar.D_node_kg(globalRow, :));
        Anominal = logical(squeeze(nominalSidecar.A_site_node(globalRow, :, :)));
        Cnominal = double(squeeze(nominalSidecar.C_site_node_km(globalRow, :, :)));
        if nominalPath ~= pathId || nominalState ~= stateId
            error('State %d scenario %d sidecar identity mismatch.', stateId, scenarioId);
        end
        dError = max(abs(Dagg - Dnominal));
        aMismatch = sum(Aagg ~= Anominal, 'all');
        cInfMismatch = sum(isinf(Cagg) ~= isinf(Cnominal), 'all');
        finiteBoth = isfinite(Cagg) & isfinite(Cnominal);
        if any(finiteBoth, 'all')
            cError = max(abs(Cagg(finiteBoth) - Cnominal(finiteBoth)));
        else
            cError = 0;
        end
        dExact = isequal(Dagg, Dnominal);
        aExact = isequal(Aagg, Anominal);
        cExact = isequaln(Cagg, Cnominal);

        nominalRow = nominal(double(nominal.initial_state_id) == stateId & ...
            double(nominal.scenario_id_in_state) == scenarioId, :);
        dTotalError = abs(sum(Dagg) - double(nominalRow.D_Hres3h_total_kg));
        aShareError = abs(mean(Aagg, 'all') - double(nominalRow.A_reachable_share));
        cMeanError = abs(mean(Cagg(Aagg)) - double(nominalRow.C_reachable_mean_km));
        a0StageError = abs(1 - reachableTotal / (3 * model.nSites * model.nNodes) - ...
            double(nominalRow.A0_stage_pair_share));
        cStageError = abs(stageCsum / reachableTotal - ...
            double(nominalRow.C_stage_reachable_mean_km));
        failedCountError = abs(sum(failed(3, :)) - double(nominalRow.W3_failed_line_count));
        closedCountError = abs(sum(closed(3, :)) - double(nominalRow.W3_closed_road_count));
        mergeExact = dExact && aExact && cExact && ...
            dTotalError <= csvSummaryTolerance && ...
            aShareError <= csvSummaryTolerance && ...
            cMeanError <= csvSummaryTolerance && ...
            a0StageError <= csvSummaryTolerance && ...
            cStageError <= csvSummaryTolerance && ...
            failedCountError == 0 && closedCountError == 0;
        if ~mergeExact
            error(['State %d scenario %d final D/A/C replay is not exact: ' ...
                'dError=%.17g dExact=%d aMismatch=%d aExact=%d ' ...
                'cError=%.17g cInfMismatch=%d cExact=%d ' ...
                'dTotal=%.17g aShare=%.17g cMean=%.17g ' ...
                'a0Stage=%.17g cStage=%.17g failedCount=%.17g closedCount=%.17g.'], ...
                stateId, scenarioId, dError, dExact, aMismatch, aExact, ...
                cError, cInfMismatch, cExact, dTotalError, aShareError, ...
                cMeanError, a0StageError, cStageError, failedCountError, closedCountError);
        end

        targetIndex = localOutputIndices(kk);
        D_period_kg(targetIndex, :, :) = Dtau;
        A_period(targetIndex, :, :, :) = reachTau;
        C_period_km(targetIndex, :, :, :) = costTau;
        line_failed_period(targetIndex, :, :) = failed;
        road_closed_period(targetIndex, :, :) = closed;
        road_slowdown_period(targetIndex, :, :) = slow;
        line_resistance_uniform(targetIndex, :) = uLine;
        road_resistance_uniform(targetIndex, :) = uRoad;
        wind_quantile(targetIndex, :) = qAll(streamPosition, :);

        comparisonRows(targetIndex, :) = {stateId, scenarioId, pathId, streamPosition, ...
            sum(Dtau(1, :)), sum(Dtau(2, :)), sum(Dtau(3, :)), sum(Dagg), ...
            sum(Dnominal), dError, dExact, sum(squeeze(reachTau(1, :, :)), 'all'), ...
            sum(squeeze(reachTau(2, :, :)), 'all'), ...
            sum(squeeze(reachTau(3, :, :)), 'all'), sum(Aagg, 'all'), ...
            sum(Anominal, 'all'), aMismatch, aExact, ...
            mean_or_nan(squeeze(costTau(1, :, :)), squeeze(reachTau(1, :, :))), ...
            mean_or_nan(squeeze(costTau(2, :, :)), squeeze(reachTau(2, :, :))), ...
            mean_or_nan(squeeze(costTau(3, :, :)), squeeze(reachTau(3, :, :))), ...
            mean(Cagg(Aagg)), mean(Cnominal(Anominal)), cError, cInfMismatch, ...
            cExact, dTotalError, aShareError, cMeanError, a0StageError, ...
            cStageError, failedCountError, closedCountError, windError, ...
            all(failed(1, :) <= failed(2, :) & failed(2, :) <= failed(3, :)), ...
            all(closed(1, :) <= closed(2, :) & closed(2, :) <= closed(3, :)), ...
            mergeExact};
    end
end

reproductionComparison = cell2table(comparisonRows, 'VariableNames', ...
    {'initial_state_id', 'scenario_id', 'path_id', 'joint_stream_position', ...
    'D_W1_total_kg', 'D_W2_total_kg', 'D_W3_total_kg', ...
    'D_remerged_total_kg', 'D_nominal_total_kg', 'D_max_abs_error_kg', ...
    'D_exact_match', 'A_W1_reachable_count', 'A_W2_reachable_count', ...
    'A_W3_reachable_count', 'A_remerged_reachable_count', ...
    'A_nominal_reachable_count', 'A_mismatch_count', 'A_exact_match', ...
    'C_W1_reachable_mean_km', 'C_W2_reachable_mean_km', ...
    'C_W3_reachable_mean_km', 'C_remerged_reachable_mean_km', ...
    'C_nominal_reachable_mean_km', 'C_reachable_max_abs_error_km', ...
    'C_inf_pattern_mismatch_count', 'C_exact_match', ...
    'D_total_summary_abs_error', 'A_share_summary_abs_error', ...
    'C_mean_summary_abs_error', 'A0_stage_share_abs_error', ...
    'C_stage_mean_abs_error', 'W3_failed_count_abs_error', ...
    'W3_closed_count_abs_error', 'saved_wind_max_abs_error_mps', ...
    'persistent_line_damage_pass', 'persistent_road_damage_pass', ...
    'final_DAC_exact_match'});
randomStreamAudit = cell2table(streamRows, 'VariableNames', ...
    {'initial_state_id', 'a0', 'loc0', 'lfw0', 'resistance_seed', ...
    'wind_seed', 'permutation_sha256_replayed', 'permutation_sha256_frozen', ...
    'q_W1_sha256_replayed', 'q_W1_sha256_frozen', ...
    'q_W2_sha256_replayed', 'q_W2_sha256_frozen', ...
    'q_W3_sha256_replayed', 'q_W3_sha256_frozen'});

variableRows = [ ...
    "permutation", "evaluate_frozen_wdro_dataset_block_h2.m", "15-20", "15000x1", "original main-sample row permutation; maps stream position to path record", "not saved directly; SHA-256 saved"; ...
    "lineU / roadU", "evaluate_frozen_wdro_dataset_block_h2.m", "15-24", "15000 x component", "persistent line and road resistance uniform thresholds", "not saved; deterministically replayed from resistance_seed after randperm"; ...
    "q", "evaluate_frozen_wdro_dataset_block_h2.m", "22-24", "15000x3", "independent W1/W2/W3 triangular-wind quantiles", "not saved; per-stage SHA-256 and wind_seed saved"; ...
    "vmax{1..3}", "evaluate_frozen_wdro_dataset_block_h2.m", "26-40", "15000x1 per period", "actual maximum wind speed in W1/W2/W3", "saved as wind_W1_mps..wind_W3_mps"; ...
    "pFail{1..3}", "evaluate_frozen_wdro_dataset_block_h2.m", "37-44", "15000 x grid line", "period line-failure probability before fixed resistance threshold", "not saved"; ...
    "failed1 / failed2 / failed3", "evaluate_frozen_wdro_dataset_block_h2.m", "43-47", "15000 x grid line", "persistent failed-line status in W1/W2/W3", "only W3 failed count saved"; ...
    "outage1 / outage2 / outage3", "evaluate_frozen_wdro_dataset_block_h2.m", "45-52", "15000x33", "node outage implied by persistent radial line failures", "not saved"; ...
    "D1 / D2 / D3", "evaluate_frozen_wdro_dataset_block_h2.m", "50-53", "15000x33 kg-H2", "node hydrogen demand generated in each one-hour period", "not saved"; ...
    "Dnode", "evaluate_frozen_wdro_dataset_block_h2.m", "53", "15000x33 kg-H2", "three-period merged demand D1+D2+D3", "saved as D_node_kg"; ...
    "pClose{1..3}", "evaluate_frozen_wdro_dataset_block_h2.m", "37-40,56-58", "15000 x road edge", "period road closure probability and slowdown input", "not saved"; ...
    "closed1 / closed2 / closed3", "evaluate_frozen_wdro_dataset_block_h2.m", "56-59", "15000 x road edge", "persistent closed-road status in W1/W2/W3", "only W3 closed count saved"; ...
    "slow1 / slow2 / slow3", "evaluate_frozen_wdro_dataset_block_h2.m", "58", "15000 x road edge", "persistent maximum road slowdown in W1/W2/W3", "not saved"; ...
    "reachTau", "evaluate_frozen_wdro_dataset_block_h2.m", "65-80", "3x4x33 per scenario", "period site-to-node reachability", "not saved"; ...
    "costTau", "evaluate_frozen_wdro_dataset_block_h2.m", "65-80", "3x4x33 km per scenario", "period shortest-path service impedance; Inf when unreachable", "not saved"; ...
    "dTau / critical", "evaluate_frozen_wdro_dataset_block_h2.m", "81-95", "3x33 / period index", "period demands and demand-positive periods used by the merge rule", "not saved"; ...
    "Aagg", "evaluate_frozen_wdro_dataset_block_h2.m", "82-96", "4x33", "reachable in every demand-critical period; all three periods used if node demand is zero", "saved as A_site_node"; ...
    "Cagg", "evaluate_frozen_wdro_dataset_block_h2.m", "82-96", "4x33 km", "mean period cost over demand-critical periods when all are reachable", "saved as C_site_node_km"; ...
    "joint_stream_position", "evaluate_frozen_wdro_dataset_block_h2.m / Step-03J CSV", "100-107 / 147-154", "integer", "row in selected=stateSample(permutation,:) and in lineU/roadU/q streams", "saved directly"];
actualVariableMapping = array2table(variableRows, 'VariableNames', ...
    {'actual_variable_name', 'source_file', 'source_lines', 'shape_or_unit', ...
    'physical_meaning', 'storage_status'});

mkdir(tempDir);
writetable(actualVariableMapping, fullfile(tempDir, 'actual_variable_mapping.csv'));
writetable(testedScenarios, fullfile(tempDir, 'tested_scenarios.csv'));
writetable(reproductionComparison, fullfile(tempDir, 'reproduction_comparison.csv'));
writetable(randomStreamAudit, fullfile(tempDir, 'random_stream_audit.csv'));
save(fullfile(tempDir, 'recovered_period_data.mat'), 'testedScenarios', ...
    'D_period_kg', 'A_period', 'C_period_km', 'line_failed_period', ...
    'road_closed_period', 'road_slowdown_period', ...
    'line_resistance_uniform', 'road_resistance_uniform', 'wind_quantile');

searched = [ ...
    "Code and configuration:"; ...
    "- terminalLoh_wdro/src/evaluate_frozen_wdro_dataset_block_h2.m"; ...
    "- terminalLoh_wdro/src/evaluate_formal_stagewise_b3_stability_block_h2.m"; ...
    "- terminalLoh_wdro/src/run_stage3i_formal_stagewise_random_b3_h2.m"; ...
    "- terminalLoh_wdro/src/run_stage3j_wdro_input_freeze_h2.m"; ...
    "- terminalLoh_wdro/src/load_frozen_b3_wdro_dataset_h2.m"; ...
    "- terminalLoh_wdro/src/build_foundation_fix_coordinates_h2.m"; ...
    "- terminalLoh_wdro/src/load_formal_b3_wind_config_h2.m"; ...
    "- terminalLoh_wdro/config/formal_b3_wind_modes.csv"; ...
    "Frozen data and metadata:"; ...
    "- terminalLoh_wdro/output/stage3j_wdro_input_freeze/run-001/wdro_nominal_input.csv"; ...
    "- terminalLoh_wdro/output/stage3j_wdro_input_freeze/run-001/wdro_nominal_input_DAC.mat"; ...
    "- terminalLoh_wdro/output/stage3j_wdro_input_freeze/run-001/dataset_role_and_seed_map.csv"; ...
    "- terminalLoh_wdro/output/stage3j_wdro_input_freeze/run-001/wdro_schema_description.csv"; ...
    "- terminalLoh_wdro/output/stage2a2_W3_path_sampling/run-002/main_path_samples.csv"; ...
    "- results/task-002-stage2b-b3-smoke/23-fixed-decision-loss-consistency/run-001/step03W_pair_results.csv"; ...
    "MAT fields found: " + strjoin(matFields.', ', '); ...
    "Nominal CSV fields found: " + strjoin(csvFields.', ', '); ...
    "Validation paths read: NONE"];
write_lines(fullfile(tempDir, 'searched_paths.txt'), searched);

protectedAfter = strings(numel(protectedRelative), 1);
for ii = 1:numel(protectedRelative)
    protectedAfter(ii) = path_digest(fullfile(rootDir, protectedRelative(ii)));
end
inputHashAfter = strings(numel(inputPaths), 1);
for ii = 1:numel(inputPaths), inputHashAfter(ii) = sha256_file(inputPaths(ii)); end

checks = { ...
    "branch_matches_frozen", branch == expectedBranch, branch; ...
    "local_HEAD_matches_frozen", head == expectedHead, head; ...
    "upstream_matches_frozen", upstream == expectedHead, upstream; ...
    "tracked_worktree_clean", strlength(strtrim(string(trackedDiff))) == 0, strtrim(string(trackedDiff)); ...
    "nominal_MAT_has_no_period_DAC", ~directMatPeriodAvailable, strjoin(matFields.', ','); ...
    "nominal_CSV_has_no_period_DAC", ~directCsvPeriodDACAvailable, "only path/wind/seeds plus final summaries"; ...
    "six_requested_states_only", isequal(sort(unique(testedScenarios.initial_state_id)), states), mat2str(sort(unique(testedScenarios.initial_state_id)).'); ...
    "three_scenarios_per_state", height(testedScenarios) == 18, string(height(testedScenarios)); ...
    "all_stream_hashes_match", all(randomStreamAudit.permutation_sha256_replayed == randomStreamAudit.permutation_sha256_frozen) && all(randomStreamAudit.q_W1_sha256_replayed == randomStreamAudit.q_W1_sha256_frozen) && all(randomStreamAudit.q_W2_sha256_replayed == randomStreamAudit.q_W2_sha256_frozen) && all(randomStreamAudit.q_W3_sha256_replayed == randomStreamAudit.q_W3_sha256_frozen), "six state streams"; ...
    "saved_winds_within_CSV_precision", all(reproductionComparison.saved_wind_max_abs_error_mps <= csvSummaryTolerance), string(max(reproductionComparison.saved_wind_max_abs_error_mps)); ...
    "D_remerge_exact", all(reproductionComparison.D_exact_match) && all(reproductionComparison.D_total_summary_abs_error <= csvSummaryTolerance), string(max(reproductionComparison.D_max_abs_error_kg)); ...
    "A_remerge_exact", all(reproductionComparison.A_exact_match) && all(reproductionComparison.A_share_summary_abs_error <= csvSummaryTolerance), string(max(reproductionComparison.A_mismatch_count)); ...
    "C_remerge_exact", all(reproductionComparison.C_exact_match) && all(reproductionComparison.C_mean_summary_abs_error <= csvSummaryTolerance), string(max(reproductionComparison.C_reachable_max_abs_error_km)); ...
    "stage_summaries_within_CSV_precision", all(reproductionComparison.A0_stage_share_abs_error <= csvSummaryTolerance) && all(reproductionComparison.C_stage_mean_abs_error <= csvSummaryTolerance), string(max([reproductionComparison.A0_stage_share_abs_error; reproductionComparison.C_stage_mean_abs_error])); ...
    "W3_damage_summaries_exact", all(reproductionComparison.W3_failed_count_abs_error == 0) && all(reproductionComparison.W3_closed_count_abs_error == 0), string(max([reproductionComparison.W3_failed_count_abs_error; reproductionComparison.W3_closed_count_abs_error])); ...
    "persistent_damage_pass", all(reproductionComparison.persistent_line_damage_pass) && all(reproductionComparison.persistent_road_damage_pass), "18 scenarios"; ...
    "all_final_DAC_exact", all(reproductionComparison.final_DAC_exact_match), string(sum(reproductionComparison.final_DAC_exact_match)); ...
    "input_files_unchanged", isequal(inputHashBefore, inputHashAfter), string(sum(inputHashBefore == inputHashAfter)); ...
    "protected_untracked_paths_unchanged", isequal(protectedBefore, protectedAfter), string(sum(protectedBefore == protectedAfter)); ...
    "solver_call_count_zero", true, "0"; ...
    "validation_file_count_zero", true, "0"; ...
    "other_state_count_zero", true, "0"};
allPass = all(cell2mat(checks(:, 2)));
if allPass
    conclusion = "B. PERIOD_DATA_DETERMINISTICALLY_RECOVERABLE";
else
    conclusion = "C. PERIOD_DATA_NOT_RECOVERABLE";
end

auditLines = [ ...
    "Step-03Y-A mechanical audit"; ...
    "status=" + string(ternary(allPass, 'PASS', 'FAIL')); ...
    "conclusion=" + conclusion; ...
    "solver_call_count=0"; ...
    "gurobi_call_count=0"; ...
    "wdro_call_count=0"; ...
    "msp_call_count=0"; ...
    "validation_file_count=0"; ...
    "other_state_count=0"; ...
    "tested_scenario_count=" + string(height(testedScenarios)); ...
    ""; "Checks:"];
for ii = 1:size(checks, 1)
    auditLines(end + 1) = string(checks{ii, 1}) + "|" + ...
        string(ternary(checks{ii, 2}, 'PASS', 'FAIL')) + ...
        "|observed=" + string(checks{ii, 3}); %#ok<SAGROW>
end
write_lines(fullfile(tempDir, 'mechanical_audit.txt'), auditLines);

conclusionLines = [ ...
    conclusion; ...
    "The nominal files do not directly store period D/A/C arrays."; ...
    "The original path order, path_id, joint_stream_position, W1-W3 path states, base/resistance/wind seeds, full random-stream hashes, and formal model inputs are sufficient for deterministic replay without drawing a replacement scenario."; ...
    "All 18 replayed scenarios reproduce final D, A, and C exactly after applying the original merge rule."; ...
    "solver_call_count=0"; ...
    "validation_file_count=0"];
write_lines(fullfile(tempDir, 'conclusion.txt'), conclusionLines);

readmeLines = [ ...
    "# Step-03Y-A period-data recoverability audit"; ""; ...
    "## Result"; ""; ...
    "- Mechanical audit: `" + string(ternary(allPass, 'PASS', 'FAIL')) + "`."; ...
    "- Conclusion: `" + conclusion + "`."; ...
    "- Solver calls: 0."; ...
    "- Validation inputs read: 0."; ""; ...
    "## Direct storage check"; ""; ...
    "The Step-03J D/A/C sidecar contains only `D_node_kg`, `A_site_node`, `C_site_node_km`, `path_id`, and `initial_state_id`. The nominal CSV contains W1-W3 path states and actual winds, seeds, stream position, final D/A/C summaries, and W3 damage counts, but no period D/A/C arrays. Therefore conclusion A does not apply."; ""; ...
    "## Deterministic recovery"; ""; ...
    "The original generator first applies `permutation=randperm(15000)`, then generates persistent `lineU` and `roadU` resistance thresholds from `resistance_seed`. A separate `wind_seed` generates the 15000x3 matrix `q`. The saved `joint_stream_position` identifies the exact row in all three streams. Full permutation and q-column SHA-256 values match the Step-03J seed map for all six states."; ""; ...
    "The period variables are `D1/D2/D3`, `reachTau`, and `costTau`. Persistent line states are `failed1/failed2/failed3`; persistent road states are `closed1/closed2/closed3` with `slow1/slow2/slow3`. For each node, the final A/C merge uses periods where `D1/D2/D3` exceed `1e-10 kg`; if no period has demand, all three periods are used. A is true only when the site reaches the node in every selected period, and C is the mean selected-period shortest-path impedance."; ""; ...
    "## Replay evidence"; ""; ...
    "Three existing Step-03W endpoint scenarios were selected per state by the deterministic min/middle/max scenario-id rule, for 18 scenarios total. Random-stream hashes and final D/A/C match exactly; winds and scalar CSV summaries match within 1e-12 CSV serialization precision. `recovered_period_data.mat` stores the audited period arrays and resistance/damage evidence for these 18 scenarios only; it is not a replacement scenario set."; ""; ...
    "## Boundaries"; ""; ...
    "No TerminalLOH optimization, Q evaluation, distance computation, Gurobi, WDRO, or MSP call was made. No validation file or other initial state was processed. Existing untracked outputs were hash-checked before and after and were not modified. Git add, commit, push, and `codex_rule/log.md` updates were not performed."; ""; ...
    "runtime_sec=" + string(sprintf('%.6f', toc(started)))];
write_lines(fullfile(tempDir, 'README.md'), readmeLines);

if ~allPass
    error('Step-03Y-A mechanical audit failed; temporary output retained.');
end
movefile(tempDir, outputDir);
fprintf('Step-03Y-A PASS: %s\n', conclusion);
fprintf('Output: %s\n', outputDir);
fprintf('Runtime: %.6f s\n', toc(started));
fprintf('solver_call_count=0\nvalidation_file_count=0\n');

function config = build_config(rootDir, moduleDir, thisDir)
config.mainSampleFile = fullfile(moduleDir, 'output', 'stage2a2_W3_path_sampling', 'run-002', 'main_path_samples.csv');
config.nominalCsv = fullfile(moduleDir, 'output', 'stage3j_wdro_input_freeze', 'run-001', 'wdro_nominal_input.csv');
config.nominalMat = fullfile(moduleDir, 'output', 'stage3j_wdro_input_freeze', 'run-001', 'wdro_nominal_input_DAC.mat');
config.seedMapFile = fullfile(moduleDir, 'output', 'stage3j_wdro_input_freeze', 'run-001', 'dataset_role_and_seed_map.csv');
config.stepWPairFile = fullfile(rootDir, 'results', 'task-002-stage2b-b3-smoke', '23-fixed-decision-loss-consistency', 'run-001', 'step03W_pair_results.csv');
config.formalWindConfigFile = fullfile(moduleDir, 'config', 'formal_b3_wind_modes.csv');
config.warningSweepDir = fullfile(moduleDir, 'output', 'stage2_foundation_warning100_Rmax30_40_50_Wstep_sweep');
config.warningSolutionFile = fullfile(config.warningSweepDir, 'warning_y_base_solution.csv');
config.locCoordinateFile = fullfile(moduleDir, 'output', 'stage2_foundation_audit', 'loc_lf_coordinate_table.csv');
config.nearInputFile = fullfile(rootDir, 'data', 'yuanqi', 'near_stage_msp_input.mat');
config.roadEdgeFile = fullfile(rootDir, 'data', 'yuanqi', 'stage1_road_edges.csv');
config.siteNodeFile = fullfile(rootDir, 'data', 'yuanqi', 'stage1_site_nodes.csv');
config.Rmax = 40; config.Wstep = 40; config.windDecayB = 0.6;
config.designWindSpeedVN = 25; config.roadDesignWindVN = 30;
config.sourceNode = 1; config.thisDir = thisDir;
end

function model = build_replay_model(config)
warning = readtable(config.warningSolutionFile);
if height(warning) ~= 1, error('Warning y-base file must contain one row.'); end
yBase = double(warning.y_base(1));
locRaw = readtable(config.locCoordinateFile);
locTable = unique(locRaw(:, {'loc', 'x_coord'}), 'rows', 'stable');
locTable = sortrows(locTable, 'loc');
raw = load(config.nearInputFile, 'NearStageInput');
layout = build_h2_spatial_layout_preview(raw.NearStageInput);
nodes = sortrows(layout.nodes, 'node_id');
lines = sortrows(layout.lines, 'line_id');
grid = table(lines.line_id, lines.source_edge_id, lines.from_node, lines.to_node, ...
    nodes.x_km(lines.from_node), nodes.y_km(lines.from_node), ...
    nodes.x_km(lines.to_node), nodes.y_km(lines.to_node), ...
    'VariableNames', {'line_id', 'source_edge_id', 'from_node', 'to_node', 'x1', 'y1', 'x2', 'y2'});
roadRaw = readtable(config.roadEdgeFile);
road = table(double(roadRaw.road_edge_id), double(roadRaw.from_node), ...
    double(roadRaw.to_node), nodes.x_km(double(roadRaw.from_node)), ...
    nodes.y_km(double(roadRaw.from_node)), nodes.x_km(double(roadRaw.to_node)), ...
    nodes.y_km(double(roadRaw.to_node)), 'VariableNames', ...
    {'road_edge_id', 'from_node', 'to_node', 'x1', 'y1', 'x2', 'y2'});
site = sortrows(readtable(config.siteNodeFile), 'site_id');
Pnode = double(raw.NearStageInput.Grid.P_load_base_kw(:));
eta = double(raw.NearStageInput.HydrogenDevice.eta_FC);
lhv = double(raw.NearStageInput.HydrogenDevice.h2_lhv_kWh_per_kg);
locValues = sort(double(locTable.loc));
lineFactor = zeros(6 * numel(locValues) * 4, height(grid));
roadFactor = zeros(6 * numel(locValues) * 4, height(road));
stateIndex = zeros(6, numel(locValues), 4); rr = 0;
for a = 1:6
    for loc = locValues(:).'
        locRow = locTable(locTable.loc == loc, :);
        for lfw = 0:3
            rr = rr + 1; x = double(locRow.x_coord); y = yBase + lfw * config.Wstep;
            lineDist = compute_point_to_segment_distance_h2(x, y, grid.x1, grid.y1, grid.x2, grid.y2);
            roadDist = compute_point_to_segment_distance_h2(x, y, road.x1, road.y1, road.x2, road.y2);
            lineFactor(rr, :) = compute_wind_speed_radial_h2(lineDist, 1, config.Rmax, config.windDecayB).';
            roadFactor(rr, :) = compute_wind_speed_radial_h2(roadDist, 1, config.Rmax, config.windDecayB).';
            stateIndex(a, loc - min(locValues) + 1, lfw + 1) = rr;
        end
    end
end
model.lineFactor = lineFactor; model.roadFactor = roadFactor;
model.stateIndex = stateIndex; model.locMin = min(locValues); model.locMax = max(locValues);
model.nLines = height(grid); model.nRoads = height(road); model.nNodes = numel(Pnode);
model.nSites = height(site); model.sourceNode = config.sourceNode;
model.Pnode_kW = Pnode; model.nodePathIncidence = radial_node_path_incidence(model.nNodes, grid.from_node, grid.to_node, config.sourceNode);
model.roadFrom = double(road.from_node); model.roadTo = double(road.to_node);
model.roadLength = hypot(road.x2 - road.x1, road.y2 - road.y1);
model.siteNodes = double(site.grid_node); model.DFactorKgPerKWh = 1 / (eta * lhv);
model.designWindSpeedVN = config.designWindSpeedVN; model.roadDesignWindVN = config.roadDesignWindVN;
end

function incidence = radial_node_path_incidence(nNodes, fromNode, toNode, sourceNode)
nLines = numel(fromNode); adj = cell(nNodes, 1); edgeAdj = cell(nNodes, 1);
for ll = 1:nLines
    i = fromNode(ll); j = toNode(ll);
    adj{i}(end + 1) = j; edgeAdj{i}(end + 1) = ll;
    adj{j}(end + 1) = i; edgeAdj{j}(end + 1) = ll;
end
parent = zeros(nNodes, 1); parentEdge = zeros(nNodes, 1); visited = false(nNodes, 1);
queue = zeros(nNodes, 1); head = 1; tail = 1; queue(1) = sourceNode; visited(sourceNode) = true;
while head <= tail
    u = queue(head); head = head + 1;
    for kk = 1:numel(adj{u})
        v = adj{u}(kk); if visited(v), continue; end
        visited(v) = true; parent(v) = u; parentEdge(v) = edgeAdj{u}(kk);
        tail = tail + 1; queue(tail) = v;
    end
end
incidence = false(nNodes, nLines);
for node = 1:nNodes
    cur = node;
    while cur ~= sourceNode
        incidence(node, parentEdge(cur)) = true; cur = parent(cur);
    end
end
end

function idx = state_index(model, a, loc, lfw)
linear = sub2ind(size(model.stateIndex), a, loc - model.locMin + 1, lfw + 1);
idx = model.stateIndex(linear);
if idx <= 0, error('Joint state missing from replay wind cache.'); end
end

function vmax = triangular_by_level(a, q, vLow, vMode, vHigh)
if a == 1, vmax = 0; return; end
lo = vLow(a); mode = vMode(a); hi = vHigh(a); fc = (mode - lo) / (hi - lo);
if q <= fc
    vmax = lo + sqrt(q * (hi - lo) * (mode - lo));
else
    vmax = hi - sqrt((1 - q) * (hi - lo) * (hi - mode));
end
end

function [reach, cost] = road_state(nNodes, fromNode, toNode, edgeCost, sources)
adj = inf(nNodes, nNodes); adj(1:(nNodes + 1):end) = 0;
for ee = 1:numel(edgeCost)
    if ~isfinite(edgeCost(ee)), continue; end
    i = fromNode(ee); j = toNode(ee);
    if edgeCost(ee) < adj(i, j), adj(i, j) = edgeCost(ee); adj(j, i) = edgeCost(ee); end
end
reach = false(numel(sources), nNodes); cost = inf(numel(sources), nNodes);
for ii = 1:numel(sources)
    dist = inf(1, nNodes); visited = false(1, nNodes); dist(sources(ii)) = 0;
    for iter = 1:nNodes
        candidate = dist; candidate(visited) = Inf; [best, u] = min(candidate);
        if ~isfinite(best), break; end
        visited(u) = true; dist = min(dist, best + adj(u, :));
    end
    reach(ii, :) = isfinite(dist); cost(ii, :) = dist;
end
end

function value = mean_or_nan(cost, reach)
values = cost(logical(reach));
if isempty(values), value = NaN; else, value = mean(values); end
end

function hash = sha256_file(fileName)
fid = fopen(fileName, 'rb'); if fid < 0, error('Could not open %s.', fileName); end
cleanup = onCleanup(@() fclose(fid)); md = java.security.MessageDigest.getInstance('SHA-256');
while true
    bytes = fread(fid, 1024 * 1024, '*uint8'); if isempty(bytes), break; end
    md.update(typecast(bytes, 'int8'));
end
digest = typecast(md.digest(), 'uint8'); hash = lower(string(reshape(dec2hex(digest, 2).', 1, [])));
end

function hash = sha256_uint32(x)
md = java.security.MessageDigest.getInstance('SHA-256'); bytes = typecast(uint32(x(:)), 'uint8');
md.update(typecast(bytes, 'int8')); digest = typecast(md.digest(), 'uint8');
hash = lower(string(reshape(dec2hex(digest, 2).', 1, [])));
end

function hash = sha256_double(x)
md = java.security.MessageDigest.getInstance('SHA-256'); bytes = typecast(double(x(:)), 'uint8');
md.update(typecast(bytes, 'int8')); digest = typecast(md.digest(), 'uint8');
hash = lower(string(reshape(dec2hex(digest, 2).', 1, [])));
end

function digest = path_digest(pathName)
if isfile(pathName), digest = sha256_file(pathName); return; end
if ~isfolder(pathName), digest = "MISSING"; return; end
files = dir(fullfile(pathName, '**', '*')); files = files(~[files.isdir]);
relative = strings(numel(files), 1);
for ii = 1:numel(files)
    fullName = fullfile(files(ii).folder, files(ii).name);
    relative(ii) = string(erase(fullName, [char(pathName), filesep]));
end
[relative, order] = sort(relative); files = files(order);
md = java.security.MessageDigest.getInstance('SHA-256');
for ii = 1:numel(files)
    fullName = fullfile(files(ii).folder, files(ii).name);
    token = relative(ii) + "|" + string(files(ii).bytes) + "|" + sha256_file(fullName) + newline;
    md.update(typecast(unicode2native(char(token), 'UTF-8'), 'int8'));
end
raw = typecast(md.digest(), 'uint8'); digest = lower(string(reshape(dec2hex(raw, 2).', 1, [])));
end

function write_lines(fileName, lines)
fid = fopen(fileName, 'w'); if fid < 0, error('Could not write %s.', fileName); end
cleanup = onCleanup(@() fclose(fid));
for ii = 1:numel(lines), fprintf(fid, '%s\n', lines(ii)); end
end

function value = ternary(condition, whenTrue, whenFalse)
if condition, value = whenTrue; else, value = whenFalse; end
end
