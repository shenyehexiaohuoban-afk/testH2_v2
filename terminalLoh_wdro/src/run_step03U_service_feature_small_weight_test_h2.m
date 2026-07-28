function result = run_step03U_service_feature_small_weight_test_h2()
%RUN_STEP03U_SERVICE_FEATURE_SMALL_WEIGHT_TEST_H2 Fixed small weight audit.

taskTic = tic;
thisDir = fileparts(mfilename('fullpath'));
moduleDir = fileparts(thisDir);
rootDir = fileparts(moduleDir);
resultRoot = fullfile(rootDir, 'results', 'task-002-stage2b-b3-smoke');
outputDir = fullfile(resultRoot, ...
    '21-service-feature-small-weight-test', 'run-001');
tempDir = outputDir + ".tmp";
if isfolder(outputDir)
    error('Step-03U final output directory already exists.');
end
if isfolder(tempDir)
    rmdir(tempDir, 's');
end
mkdir(tempDir);

config = build_config();
stepSDir = fullfile(resultRoot, ...
    '19-state-distribution-tail-regret-audit', 'run-001');
stepTDir = fullfile(resultRoot, ...
    '20-ctilde-tier1-structural-diagnosis', 'run-001');
checkpointDir = fullfile(moduleDir, 'output', ...
    'stage3s_state_distribution_tail_regret_audit', 'run-001', ...
    'checkpoints');
stepJDir = fullfile(moduleDir, 'output', ...
    'stage3j_wdro_input_freeze', 'run-001');
nominalPath = fullfile(stepJDir, 'wdro_nominal_input_DAC.mat');
stepPHistory = fullfile(resultRoot, ...
    '16-dac-transport-cost-audit', 'run-001');
crossPath = fullfile(stepSDir, 'step03S_tail_cross_regret.csv');
stepTPairPath = fullfile(stepTDir, 'step03T_selected_pairs.csv');
required = [string(crossPath); string(stepTPairPath); string(nominalPath)];
for ii = 1:numel(required)
    if ~isfile(required(ii))
        error('Step-03U missing required input: %s', required(ii));
    end
end
if ~isfolder(checkpointDir) || ~isfolder(stepPHistory)
    error('Step-03U required checkpoints or preserved Step-03P history missing.');
end
if sha256_file(nominalPath) ~= config.nominalHash
    error('Step-03U Step-03J nominal hash mismatch.');
end

stepSBefore = directory_hash(stepSDir);
stepTBefore = directory_hash(stepTDir);
stepJBefore = directory_hash(stepJDir);
stepPBefore = directory_hash(stepPHistory);
protectedFiles = [string(fullfile(thisDir, 'step03S_distance_block_h2.m')); ...
    string(fullfile(thisDir, 'build_step03Q_distance_matrix_h2.m')); ...
    string(fullfile(thisDir, 'solve_wdro_terminal_loh_lp_h2.m')); ...
    string(fullfile(rootDir, 'main_msp_h2_near.m')); ...
    string(fullfile(rootDir, 'fa_h2', 'build_stage_model_h2.m')); ...
    string(fullfile(rootDir, 'fa_h2', 'solve_stage_model_h2.m'))];
protectedBefore = hash_files(protectedFiles);
peakMemory = memory_snapshot();

crossTbl = readtable(crossPath, 'TextType', 'string');
stepTTbl = readtable(stepTPairPath, 'TextType', 'string');
validate_inputs(crossTbl, stepTTbl, config);
[holdoutTbl, selectionAudit] = select_holdout_pairs(crossTbl, stepTTbl, config);
writetable(holdoutTbl, fullfile(tempDir, ...
    'step03U_selected_holdout_pairs.csv'));

evaluationTbl = build_evaluation_table(stepTTbl, holdoutTbl);
[componentTbl, componentAudit] = compute_pair_components( ...
    evaluationTbl, nominalPath, checkpointDir, config);
writetable(componentTbl, fullfile(tempDir, 'step03U_pair_components.csv'));
peakMemory = max(peakMemory, memory_snapshot());

[zeroAudit, zeroComponentTbl] = audit_zero_distance_pairs( ...
    crossTbl, nominalPath, checkpointDir, config);
if ~isempty(zeroComponentTbl)
    writetable(zeroComponentTbl, fullfile(tempDir, ...
        'step03U_zero_distance_audit.csv'));
end

[weightTbl, stateTbl, decision] = evaluate_weights(componentTbl, config);
writetable(weightTbl, fullfile(tempDir, 'step03U_weight_results.csv'));
writetable(stateTbl, fullfile(tempDir, 'step03U_state_results.csv'));
peakMemory = max(peakMemory, memory_snapshot());

stepSAfter = directory_hash(stepSDir);
stepTAfter = directory_hash(stepTDir);
stepJAfter = directory_hash(stepJDir);
stepPAfter = directory_hash(stepPHistory);
protectedAfter = hash_files(protectedFiles);
runnerPath = string(mfilename('fullpath'));
if ~endsWith(runnerPath, ".m")
    runnerPath = runnerPath + ".m";
end
codeMessages = checkcode(runnerPath, '-id');
runtimeSec = toc(taskTic);
peakMemory = max(peakMemory, memory_snapshot());

[acceptanceTbl, pass] = build_acceptance(holdoutTbl, componentTbl, ...
    weightTbl, stateTbl, selectionAudit, componentAudit, zeroAudit, ...
    stepSBefore, stepSAfter, stepTBefore, stepTAfter, stepJBefore, ...
    stepJAfter, stepPBefore, stepPAfter, protectedBefore, ...
    protectedAfter, codeMessages, runtimeSec, peakMemory, config);
writetable(acceptanceTbl, fullfile(tempDir, ...
    'step03U_acceptance_tests.csv'));
resourceTbl = table(runtimeSec, peakMemory, height(componentTbl), ...
    height(holdoutTbl), height(weightTbl), height(stateTbl), ...
    string(nominalPath), config.nominalHash, ...
    'VariableNames', {'runtime_sec', 'peak_working_set_bytes', ...
    'evaluated_pair_count', 'holdout_pair_count', 'weight_count', ...
    'state_result_count', 'nominal_input_path', 'nominal_input_sha256'});
writetable(resourceTbl, fullfile(tempDir, 'step03U_resource_report.csv'));
write_summary(fullfile(tempDir, 'step03U_summary.txt'), componentTbl, ...
    weightTbl, stateTbl, decision, componentAudit, zeroAudit, ...
    runtimeSec, peakMemory, pass, config);
if ~pass
    error('Step-03U acceptance failed; results remain in temporary output.');
end
movefile(tempDir, outputDir);
result = struct('output_dir', string(outputDir), 'conclusion', ...
    decision.conclusion, 'candidate_weights', decision.candidateText, ...
    'runtime_sec', runtimeSec, 'peak_working_set_bytes', peakMemory, ...
    'pass', pass);
fprintf('Step-03U PASS: %s, runtime %.3f s.\n', ...
    decision.conclusion, runtimeSec);
end

function config = build_config()
weights = [0.6, 0.4, 0.0; 0.6, 0.3, 0.1; ...
    0.5, 0.3, 0.2; 0.5, 0.2, 0.3; ...
    0.4, 0.3, 0.3; 0.4, 0.2, 0.4; ...
    0.3, 0.3, 0.4; 0.3, 0.2, 0.5];
config = struct('states', [7; 18; 30; 31; 11; 21], ...
    'rowsPerState', 15000, 'weights', weights, ...
    'C_bound', 357.1526447416079, 'kappa', 1, ...
    'epsDistance', 1e-9, 'distanceTolerance', 1e-8, ...
    'zeroTolerance', 1e-12, 'lowRegretThreshold', 0.01, ...
    'runtimeLimitSec', 600, 'validationInputUsed', false, ...
    'nominalHash', ...
    "6936a696f5cde137aca483f8c32adee33b52cbd90559a8e6395f3686c0712945");
end

function validate_inputs(crossTbl, stepTTbl, config)
requiredCross = {'initial_state_id', 'scenario_r', 'scenario_s', ...
    'path_id_r', 'path_id_s', 'nearest_all_rank', 'd_D', ...
    'd_Ctilde', 'd_new', 'relative_regret_obj_r_to_s', ...
    'relative_regret_obj_s_to_r', 'tier_1'};
if ~all(ismember(requiredCross, crossTbl.Properties.VariableNames))
    error('Step-03U frozen Step-03S schema mismatch.');
end
if height(crossTbl) ~= 125755 || sum(as_logical(crossTbl.tier_1)) ~= 7733
    error('Step-03U frozen Step-03S row or Tier-1 count mismatch.');
end
if height(stepTTbl) ~= 24 || sum(stepTTbl.group_type == "TIER1") ~= 18 || ...
        sum(stepTTbl.group_type == "CONTROL") ~= 6
    error('Step-03U Step-03T selected-pair counts mismatch.');
end
if ~isequal(sort(unique(double(stepTTbl.initial_state_id))), ...
        sort(config.states))
    error('Step-03U Step-03T state set mismatch.');
end
if ~isequal(config.weights, [0.6, 0.4, 0.0; 0.6, 0.3, 0.1; ...
        0.5, 0.3, 0.2; 0.5, 0.2, 0.3; 0.4, 0.3, 0.3; ...
        0.4, 0.2, 0.4; 0.3, 0.3, 0.4; 0.3, 0.2, 0.5]) || ...
        any(abs(sum(config.weights, 2) - 1) > 1e-12)
    error('Step-03U fixed eight-weight design changed.');
end
end

function [holdout, audit] = select_holdout_pairs(crossTbl, stepTTbl, config)
usedKeys = unordered_pair_key(stepTTbl);
records = cell(2 * numel(config.states), 1);
rr = 0;
for ss = 1:numel(config.states)
    stateId = config.states(ss);
    local = crossTbl(double(crossTbl.initial_state_id) == stateId, :);
    localKeys = unordered_pair_key(local);
    tierMask = as_logical(local.tier_1) & ~ismember(localKeys, usedKeys);
    tier = local(tierMask, :);
    if isempty(tier)
        error('Step-03U state %d has no unused Tier-1 holdout.', stateId);
    end
    [~, order] = sortrows([double(tier.d_new), double(tier.scenario_r), ...
        double(tier.scenario_s)], [1, 2, 3]);
    tierRow = tier(order(1), :);
    rr = rr + 1;
    records{rr} = holdout_record(tierRow, "HOLDOUT_TIER1", ...
        "UNUSED_MINIMUM_D_NEW_TIER1");
    tierKey = unordered_pair_key(tierRow);

    controlMask = double(local.nearest_all_rank) <= 10 & ...
        double(local.d_new) > config.zeroTolerance & ...
        double(local.relative_regret_obj_r_to_s) < config.lowRegretThreshold & ...
        double(local.relative_regret_obj_s_to_r) < config.lowRegretThreshold & ...
        ~ismember(localKeys, usedKeys) & ~ismember(localKeys, tierKey);
    controls = local(controlMask, :);
    if isempty(controls)
        error('Step-03U state %d has no unused low-regret control.', stateId);
    end
    target = double(tierRow.d_new);
    matchScore = abs(log(max(double(controls.d_new), eps) ./ max(target, eps)));
    [~, controlOrder] = sortrows([matchScore, double(controls.d_new), ...
        double(controls.scenario_r), double(controls.scenario_s)], ...
        [1, 2, 3, 4]);
    rr = rr + 1;
    records{rr} = holdout_record(controls(controlOrder(1), :), ...
        "HOLDOUT_CONTROL", "UNUSED_LOW_REGRET_DISTANCE_MATCHED");
end
holdout = records_to_table(records);
holdout.holdout_pair_id = (1:height(holdout)).';
holdout = movevars(holdout, 'holdout_pair_id', 'Before', 1);
holdoutKeys = unordered_pair_key(holdout);
audit = struct('count', height(holdout), ...
    'unique_count', numel(unique(holdoutKeys)), ...
    'overlap_with_step03T', sum(ismember(holdoutKeys, usedKeys)), ...
    'tier_count', sum(holdout.pair_group == "HOLDOUT_TIER1"), ...
    'control_count', sum(holdout.pair_group == "HOLDOUT_CONTROL"), ...
    'states', unique(double(holdout.initial_state_id)));
end

function rec = holdout_record(row, pairGroup, rule)
rec = table2struct(row);
rec.pair_group = pairGroup;
rec.selection_rule = rule;
end

function key = unordered_pair_key(tbl)
state = double(tbl.initial_state_id);
r = double(tbl.scenario_r);
s = double(tbl.scenario_s);
key = string(state) + ":" + string(min(r, s)) + ":" + string(max(r, s));
end

function evaluation = build_evaluation_table(stepTTbl, holdoutTbl)
stepT = stepTTbl;
stepT.pair_group = strings(height(stepT), 1);
stepT.pair_group(stepT.group_type == "TIER1") = "STEP03T_TIER1";
stepT.pair_group(stepT.group_type == "CONTROL") = "STEP03T_CONTROL";
keep = {'initial_state_id', 'scenario_r', 'path_id_r', 'scenario_s', ...
    'path_id_s', 'd_D', 'd_Ctilde', 'd_new', ...
    'relative_regret_obj_r_to_s', 'relative_regret_obj_s_to_r', ...
    'pair_group'};
evaluation = [stepT(:, keep); holdoutTbl(:, keep)];
evaluation.evaluation_pair_id = (1:height(evaluation)).';
evaluation = movevars(evaluation, 'evaluation_pair_id', 'Before', 1);
end

function [tbl, audit] = compute_pair_components(evaluation, matPath, ...
        checkpointDir, config)
m = matfile(matPath);
P = height(evaluation);
records = cell(P, 1);
distanceError = zeros(P, 3);
pathPass = true(P, 1);
scales = load_scales(checkpointDir, config);
for pp = 1:P
    stateId = double(evaluation.initial_state_id(pp));
    r = double(evaluation.scenario_r(pp));
    s = double(evaluation.scenario_s(pp));
    globalR = (stateId - 1) * config.rowsPerState + r;
    globalS = (stateId - 1) * config.rowsPerState + s;
    Dr = double(m.D_node_kg(globalR, :));
    Ds = double(m.D_node_kg(globalS, :));
    Ar = logical(m.A_site_node(globalR, :, :));
    As = logical(m.A_site_node(globalS, :, :));
    Cr = double(m.C_site_node_km(globalR, :, :));
    Cs = double(m.C_site_node_km(globalS, :, :));
    pathR = double(m.path_id(globalR, 1));
    pathS = double(m.path_id(globalS, 1));
    pathPass(pp) = pathR == double(evaluation.path_id_r(pp)) && ...
        pathS == double(evaluation.path_id_s(pp));
    Dscale = scales(config.states == stateId);
    [dNew, dD, dC] = step03S_distance_block_h2( ...
        Dr, Ar, Cr, Ds, As, Cs, Dscale, config);
    dS = service_distance(Dr, Ar, Cr, Ds, As, Cs, Dscale, config);
    distanceError(pp, :) = abs([dD - double(evaluation.d_D(pp)), ...
        dC - double(evaluation.d_Ctilde(pp)), ...
        dNew - double(evaluation.d_new(pp))]);
    records{pp} = struct('evaluation_pair_id', ...
        evaluation.evaluation_pair_id(pp), ...
        'pair_group', evaluation.pair_group(pp), ...
        'initial_state_id', stateId, 'scenario_r', r, 'scenario_s', s, ...
        'path_id_r', pathR, 'path_id_s', pathS, 'D_scale', Dscale, ...
        'd_D', dD, 'd_Ctilde', dC, 'd_S', dS, ...
        'baseline_d_new', dNew, ...
        'relative_regret_obj_r_to_s', ...
            double(evaluation.relative_regret_obj_r_to_s(pp)), ...
        'relative_regret_obj_s_to_r', ...
            double(evaluation.relative_regret_obj_s_to_r(pp)), ...
        'bidirectional_severity', min( ...
            double(evaluation.relative_regret_obj_r_to_s(pp)), ...
            double(evaluation.relative_regret_obj_s_to_r(pp))));
end
tbl = records_to_table(records);
[rhoDSD, rhoDSC] = component_correlations(tbl);
audit = struct('max_distance_error', max(distanceError, [], 'all'), ...
    'path_identity_pass', all(pathPass), ...
    'd_D_min', min(tbl.d_D), 'd_D_max', max(tbl.d_D), ...
    'd_C_min', min(tbl.d_Ctilde), 'd_C_max', max(tbl.d_Ctilde), ...
    'd_S_min', min(tbl.d_S), 'd_S_max', max(tbl.d_S), ...
    'spearman_dS_dD', rhoDSD, 'spearman_dS_dCtilde', rhoDSC);
end

function scales = load_scales(checkpointDir, config)
scales = NaN(numel(config.states), 1);
for ss = 1:numel(config.states)
    loaded = load(fullfile(checkpointDir, ...
        sprintf('neighbors_state_%02d.mat', config.states(ss))), 'Dscale');
    scales(ss) = loaded.Dscale;
end
if any(~isfinite(scales) | scales <= 0)
    error('Step-03U invalid frozen Step-03S Dscale.');
end
end

function dS = service_distance(Dr, Ar3, Cr3, Ds, As3, Cs3, Dscale, config)
Ar = reshape(logical(Ar3), 4, 33);
As = reshape(logical(As3), 4, 33);
Cr = reshape(double(Cr3), 4, 33);
Cs = reshape(double(Cs3), 4, 33);
DbarR = Dr ./ (Dscale + config.epsDistance);
DbarS = Ds ./ (Dscale + config.epsDistance);
CbarR = Cr ./ config.C_bound;
CbarS = Cs ./ config.C_bound;
CbarR(~Ar | ~isfinite(CbarR)) = 0;
CbarS(~As | ~isfinite(CbarS)) = 0;
Sr = Ar .* DbarR ./ (1 + CbarR);
Ss = As .* DbarS ./ (1 + CbarS);
dS = mean(abs(Sr - Ss), 'all');
end

function [rhoD, rhoC] = component_correlations(tbl)
rhoD = rank_correlation(tbl.d_S, tbl.d_D);
rhoC = rank_correlation(tbl.d_S, tbl.d_Ctilde);
end

function rho = rank_correlation(x, y)
rx = tied_rank(double(x(:)));
ry = tied_rank(double(y(:)));
if std(rx) <= eps || std(ry) <= eps
    rho = NaN;
else
    rho = corr(rx, ry);
end
end

function ranks = tied_rank(x)
[sorted, order] = sort(x);
ranks = zeros(size(x));
start = 1;
while start <= numel(x)
    finish = start;
    while finish < numel(x) && sorted(finish + 1) == sorted(start)
        finish = finish + 1;
    end
    ranks(order(start:finish)) = mean(start:finish);
    start = finish + 1;
end
end

function [audit, tbl] = audit_zero_distance_pairs(crossTbl, matPath, ...
        checkpointDir, config)
zero = crossTbl(double(crossTbl.d_new) <= config.zeroTolerance, :);
records = cell(numel(config.states), 1);
recordCount = 0;
scales = load_scales(checkpointDir, config);
m = matfile(matPath);
for ss = 1:numel(config.states)
    stateId = config.states(ss);
    local = zero(double(zero.initial_state_id) == stateId, :);
    if isempty(local)
        continue;
    end
    local = sortrows(local, {'scenario_r', 'scenario_s'});
    row = local(1, :);
    r = double(row.scenario_r);
    s = double(row.scenario_s);
    globalR = (stateId - 1) * config.rowsPerState + r;
    globalS = (stateId - 1) * config.rowsPerState + s;
    dS = service_distance(double(m.D_node_kg(globalR, :)), ...
        logical(m.A_site_node(globalR, :, :)), ...
        double(m.C_site_node_km(globalR, :, :)), ...
        double(m.D_node_kg(globalS, :)), ...
        logical(m.A_site_node(globalS, :, :)), ...
        double(m.C_site_node_km(globalS, :, :)), ...
        scales(config.states == stateId), config);
    recordCount = recordCount + 1;
    records{recordCount} = struct('initial_state_id', stateId, ...
        'scenario_r', r, 'scenario_s', s, ...
        'frozen_d_new', double(row.d_new), 'recomputed_d_S', dS);
end
tbl = records_to_table(records(1:recordCount));
if isempty(tbl)
    maxDS = NaN;
else
    maxDS = max(tbl.recomputed_d_S);
end
audit = struct('frozen_zero_pair_count', height(zero), ...
    'checked_state_count', height(tbl), 'maximum_zero_pair_d_S', maxDS, ...
    'pass', ~isempty(tbl) && maxDS <= config.zeroTolerance);
end

function [weightTbl, stateTbl, decision] = evaluate_weights(pairTbl, config)
W = config.weights;
K = size(W, 1);
records = cell(K, 1);
stateRecords = cell(K * numel(config.states), 1);
statePos = 0;
baselineDistances = W(1, 1) .* pairTbl.d_D + ...
    W(1, 2) .* pairTbl.d_Ctilde + W(1, 3) .* pairTbl.d_S;
baseStats = group_statistics(pairTbl, baselineDistances);
candidateMask = false(K, 1);
for kk = 1:K
    distances = W(kk, 1) .* pairTbl.d_D + ...
        W(kk, 2) .* pairTbl.d_Ctilde + W(kk, 3) .* pairTbl.d_S;
    stats = group_statistics(pairTbl, distances);
    stateImproved = 0;
    stateNotDegraded = 0;
    for ss = 1:numel(config.states)
        stateId = config.states(ss);
        mask = pairTbl.initial_state_id == stateId;
        local = pairTbl(mask, :);
        localDistances = distances(mask);
        localStats = group_statistics(local, localDistances);
        baseLocal = group_statistics(local, baselineDistances(mask));
        statePos = statePos + 1;
        stateRecords{statePos} = struct('weight_id', kk, ...
            'w_D', W(kk, 1), 'w_C', W(kk, 2), 'w_S', W(kk, 3), ...
            'initial_state_id', stateId, ...
            'step03T_separation_rate', localStats.stepTSeparation, ...
            'holdout_separation_rate', localStats.holdoutSeparation, ...
            'combined_separation_rate', localStats.combinedSeparation, ...
            'baseline_combined_separation_rate', baseLocal.combinedSeparation, ...
            'combined_separation_change', localStats.combinedSeparation - ...
                baseLocal.combinedSeparation, ...
            'tier1_median_distance', localStats.combinedTierMedian, ...
            'control_median_distance', localStats.combinedControlMedian);
        if localStats.combinedSeparation > baseLocal.combinedSeparation + 1e-12
            stateImproved = stateImproved + 1;
        end
        if localStats.combinedSeparation >= baseLocal.combinedSeparation - 1e-12
            stateNotDegraded = stateNotDegraded + 1;
        end
    end
    tierAmplification = stats.combinedTierMedian / ...
        max(baseStats.combinedTierMedian, 1e-12);
    controlAmplification = stats.combinedControlMedian / ...
        max(baseStats.combinedControlMedian, 1e-12);
    representativeImproved = stats.stepTSeparation > ...
        baseStats.stepTSeparation + 1e-12;
    holdoutImproved = stats.holdoutSeparation > ...
        baseStats.holdoutSeparation + 1e-12;
    noRelativeControlOverpull = controlAmplification <= ...
        tierAmplification + 1e-12;
    candidateMask(kk) = kk > 1 && representativeImproved && ...
        holdoutImproved && stateImproved >= 4 && noRelativeControlOverpull;
    records{kk} = struct('weight_id', kk, 'w_D', W(kk, 1), ...
        'w_C', W(kk, 2), 'w_S', W(kk, 3), ...
        'step03T_tier1_median', stats.stepTTierMedian, ...
        'step03T_control_median', stats.stepTControlMedian, ...
        'holdout_tier1_median', stats.holdoutTierMedian, ...
        'holdout_control_median', stats.holdoutControlMedian, ...
        'combined_tier1_median', stats.combinedTierMedian, ...
        'combined_control_median', stats.combinedControlMedian, ...
        'step03T_separation_rate', stats.stepTSeparation, ...
        'holdout_separation_rate', stats.holdoutSeparation, ...
        'combined_separation_rate', stats.combinedSeparation, ...
        'step03T_separation_change_vs_baseline', ...
            stats.stepTSeparation - baseStats.stepTSeparation, ...
        'holdout_separation_change_vs_baseline', ...
            stats.holdoutSeparation - baseStats.holdoutSeparation, ...
        'tier1_median_amplification_vs_baseline', tierAmplification, ...
        'control_median_amplification_vs_baseline', controlAmplification, ...
        'states_improved_count', stateImproved, ...
        'states_not_degraded_count', stateNotDegraded, ...
        'representative_and_holdout_improved', ...
            representativeImproved && holdoutImproved, ...
        'no_relative_control_overpull', noRelativeControlOverpull, ...
        'worth_next_small_validation', candidateMask(kk));
end
weightTbl = records_to_table(records);
stateTbl = records_to_table(stateRecords);
candidateIds = find(candidateMask);
nonbaseline = weightTbl.weight_id > 1;
anyBothImproved = any(weightTbl.representative_and_holdout_improved(nonbaseline));
bestStateCount = max(weightTbl.states_improved_count(nonbaseline));
separationSpread = max(weightTbl.combined_separation_rate(nonbaseline)) - ...
    min(weightTbl.combined_separation_rate(nonbaseline));
if numel(candidateIds) >= 2 && separationSpread <= 0.15
    conclusion = "A. SERVICE_FEATURE_SMALL_TEST_PROMISING";
elseif anyBothImproved && bestStateCount >= 3
    conclusion = "B. SERVICE_FEATURE_PROMISING_BUT_WEIGHT_SENSITIVE";
else
    conclusion = "C. SERVICE_FEATURE_NOT_SUPPORTED";
end
if isempty(candidateIds)
    candidateText = "NONE";
else
    labels = strings(numel(candidateIds), 1);
    for ii = 1:numel(candidateIds)
        id = candidateIds(ii);
        labels(ii) = sprintf('(%.1f,%.1f,%.1f)', W(id, 1), W(id, 2), W(id, 3));
    end
    candidateText = join(labels, ";");
end
decision = struct('conclusion', conclusion, 'candidateIds', candidateIds, ...
    'candidateText', candidateText, 'separationSpread', separationSpread, ...
    'anyBothImproved', anyBothImproved, 'bestStateCount', bestStateCount);
end

function stats = group_statistics(tbl, distances)
g = string(tbl.pair_group);
stepTTier = distances(g == "STEP03T_TIER1");
stepTControl = distances(g == "STEP03T_CONTROL");
holdTier = distances(g == "HOLDOUT_TIER1");
holdControl = distances(g == "HOLDOUT_CONTROL");
combinedTier = [stepTTier; holdTier];
combinedControl = [stepTControl; holdControl];
stats = struct('stepTTierMedian', median(stepTTier), ...
    'stepTControlMedian', median(stepTControl), ...
    'holdoutTierMedian', median(holdTier), ...
    'holdoutControlMedian', median(holdControl), ...
    'combinedTierMedian', median(combinedTier), ...
    'combinedControlMedian', median(combinedControl), ...
    'stepTSeparation', separation_rate(stepTTier, stepTControl), ...
    'holdoutSeparation', separation_rate(holdTier, holdControl), ...
    'combinedSeparation', separation_rate(combinedTier, combinedControl));
end

function rate = separation_rate(tier, control)
if isempty(tier) || isempty(control)
    rate = NaN;
    return;
end
rate = mean(reshape(tier, [], 1) > reshape(control, 1, []), 'all');
end

function [tbl, pass] = build_acceptance(holdout, components, weights, states, ...
        selection, componentAudit, zeroAudit, stepSBefore, stepSAfter, ...
        stepTBefore, stepTAfter, stepJBefore, stepJAfter, stepPBefore, ...
        stepPAfter, protectedBefore, protectedAfter, codeMessages, ...
        runtimeSec, peakMemory, config)
checks = cell(18, 1);
checks{1} = check_record(1, height(holdout) == 12, height(holdout), 12);
checks{2} = check_record(2, selection.tier_count == 6 && ...
    selection.control_count == 6, ...
    sprintf('%d/%d', selection.tier_count, selection.control_count), "6/6");
checks{3} = check_record(3, selection.unique_count == 12 && ...
    selection.overlap_with_step03T == 0, ...
    sprintf('unique=%d,overlap=%d', selection.unique_count, ...
    selection.overlap_with_step03T), "unique=12,overlap=0");
checks{4} = check_record(4, isequal(sort(selection.states), ...
    sort(config.states)), join(string(sort(selection.states).'), ";"), ...
    join(string(sort(config.states).'), ";"));
checks{5} = check_record(5, height(components) == 36, ...
    height(components), 36);
checks{6} = check_record(6, componentAudit.path_identity_pass, ...
    componentAudit.path_identity_pass, true);
checks{7} = check_record(7, componentAudit.max_distance_error <= ...
    config.distanceTolerance, componentAudit.max_distance_error, ...
    config.distanceTolerance);
checks{8} = check_record(8, height(weights) == 8 && ...
    max(abs(sum(config.weights, 2) - 1)) <= 1e-12, height(weights), 8);
checks{9} = check_record(9, height(states) == 48, height(states), 48);
checks{10} = check_record(10, zeroAudit.pass, ...
    zeroAudit.maximum_zero_pair_d_S, config.zeroTolerance);
checks{11} = check_record(11, all(isfinite(components.d_D)) && ...
    all(isfinite(components.d_Ctilde)) && all(isfinite(components.d_S)) && ...
    all(components.d_D >= 0) && all(components.d_Ctilde >= 0) && ...
    all(components.d_S >= 0), "finite nonnegative components", ...
    "finite nonnegative components");
checks{12} = check_record(12, stepSBefore == stepSAfter && ...
    stepTBefore == stepTAfter, "Step-03S/T unchanged", "unchanged");
checks{13} = check_record(13, stepJBefore == stepJAfter && ...
    config.nominalHash == sha256_file(fullfile(fileparts(fileparts( ...
    mfilename('fullpath'))), 'output', 'stage3j_wdro_input_freeze', ...
    'run-001', 'wdro_nominal_input_DAC.mat')), "Step-03J unchanged", ...
    "unchanged");
checks{14} = check_record(14, isequal(protectedBefore, protectedAfter), ...
    "formal distance/model hashes unchanged", "unchanged");
checks{15} = check_record(15, ~config.validationInputUsed, ...
    "nominal selected rows only", "no validation");
checks{16} = check_record(16, isempty(codeMessages), numel(codeMessages), 0);
checks{17} = check_record(17, runtimeSec <= config.runtimeLimitSec, ...
    runtimeSec, config.runtimeLimitSec);
checks{18} = check_record(18, peakMemory > 0 && isfinite(peakMemory) && ...
    stepPBefore == stepPAfter, peakMemory, ">0 and Step-03P unchanged");
tbl = records_to_table(checks);
pass = all(tbl.status == "PASS");
end

function rec = check_record(id, passed, observed, expected)
if passed
    status = "PASS";
else
    status = "FAIL";
end
rec = struct('check_id', id, 'status', status, ...
    'observed', string(observed), 'expected', string(expected));
end

function write_summary(path, pairs, weights, states, decision, audit, ...
        zeroAudit, runtimeSec, peakMemory, pass, config)
base = weights(1, :);
candidate = weights(weights.worth_next_small_validation, :);
if isempty(candidate)
    candidateText = "NONE";
else
    candidateText = decision.candidateText;
end
if pass
    status = "PASS";
else
    status = "FAIL";
end
stepTImprovement = max(weights.step03T_separation_change_vs_baseline(2:end));
holdoutImprovement = max(weights.holdout_separation_change_vs_baseline(2:end));
controlPull = max(weights.control_median_amplification_vs_baseline(2:end));
stateImprovement = max(weights.states_improved_count(2:end));
lines = ["Step-03U service-feature small weight test"; ...
    "status=" + status; "conclusion=" + decision.conclusion; ...
    "D_bar_definition=D_node_kg/(frozen_Step03S_state_Dscale+1e-9)"; ...
    "C_bar_definition=C_site_node_km/357.1526447416079"; ...
    "S_definition=A*D_bar/(1+C_bar), with S=0 when A=0"; ...
    "evaluated_pairs=" + height(pairs); "step03T_pairs=24"; ...
    "holdout_pairs=12"; "weight_count=" + height(weights); ...
    "d_D_range=" + sprintf('[%.12g,%.12g]', audit.d_D_min, audit.d_D_max); ...
    "d_Ctilde_range=" + sprintf('[%.12g,%.12g]', audit.d_C_min, audit.d_C_max); ...
    "d_S_range=" + sprintf('[%.12g,%.12g]', audit.d_S_min, audit.d_S_max); ...
    "spearman_dS_dD=" + sprintf('%.12g', audit.spearman_dS_dD); ...
    "spearman_dS_dCtilde=" + sprintf('%.12g', audit.spearman_dS_dCtilde); ...
    "zero_distance_checked_states=" + zeroAudit.checked_state_count; ...
    "zero_distance_max_d_S=" + sprintf('%.12g', zeroAudit.maximum_zero_pair_d_S); ...
    "baseline_step03T_separation=" + sprintf('%.9g', base.step03T_separation_rate); ...
    "baseline_holdout_separation=" + sprintf('%.9g', base.holdout_separation_rate); ...
    "maximum_step03T_separation_improvement=" + sprintf('%.9g', stepTImprovement); ...
    "maximum_holdout_separation_improvement=" + sprintf('%.9g', holdoutImprovement); ...
    "maximum_control_median_amplification=" + sprintf('%.9g', controlPull); ...
    "maximum_improved_state_count=" + stateImprovement; ...
    "combined_nonbaseline_separation_spread=" + ...
        sprintf('%.9g', decision.separationSpread); ...
    "weights_worth_next_small_validation=" + candidateText; ...
    "answer_1_dS_improves_service_coupling=" + ...
        yes_no(decision.anyBothImproved); ...
    "answer_2_low_regret_neighbors_harmed=" + ...
        yes_no(any(weights.control_median_amplification_vs_baseline(2:end) > ...
        weights.tier1_median_amplification_vs_baseline(2:end) + 1e-12)); ...
    "answer_3_cross_state_stability=" + state_stability_text(stateImprovement); ...
    "answer_4_next_small_validation_weights=" + candidateText; ...
    "answer_5_stop_and_modify_S=" + ...
        yes_no(decision.conclusion == "C. SERVICE_FEATURE_NOT_SUPPORTED"); ...
    "No final weight is adopted. Formal distance, rho, WDRO, Step-03J, MSP, and service constraints are unchanged."; ...
    "No TerminalLOH, cross-regret, nearest-neighbor, validation, or optimization calculation was run."; ...
    "runtime_sec=" + sprintf('%.6f', runtimeSec); ...
    "peak_working_set_bytes=" + sprintf('%.0f', peakMemory); ...
    "state_result_rows=" + height(states); ...
    "fixed_weight_rows=" + size(config.weights, 1)];
write_lines(path, lines);
end

function text = yes_no(value)
if value
    text = "YES";
else
    text = "NO";
end
end

function text = state_stability_text(count)
if count >= 4
    text = "MULTI_STATE";
elseif count >= 2
    text = "LIMITED_STATES";
else
    text = "NOT_STABLE";
end
end

function tf = as_logical(value)
if islogical(value)
    tf = value;
elseif isnumeric(value)
    tf = value ~= 0;
else
    tf = lower(string(value)) == "true" | string(value) == "1";
end
end

function tbl = records_to_table(records)
if isempty(records)
    tbl = table();
    return;
end
tbl = struct2table(vertcat(records{:}), 'AsArray', true);
end

function write_lines(path, lines)
fid = fopen(path, 'w');
if fid < 0
    error('Step-03U cannot open %s.', path);
end
cleanup = onCleanup(@() fclose(fid));
for ii = 1:numel(lines)
    fprintf(fid, '%s\n', lines(ii));
end
clear cleanup;
end

function bytes = memory_snapshot()
try
    process = System.Diagnostics.Process.GetCurrentProcess();
    bytes = double(process.WorkingSet64);
catch
    info = memory;
    bytes = double(info.MemUsedMATLAB);
end
end

function hashes = hash_files(paths)
hashes = strings(numel(paths), 1);
for ii = 1:numel(paths)
    if ~isfile(paths(ii))
        error('Step-03U protected file missing: %s', paths(ii));
    end
    hashes(ii) = sha256_file(paths(ii));
end
end

function digest = directory_hash(folder)
listing = dir(fullfile(folder, '**', '*'));
listing = listing(~[listing.isdir]);
relative = strings(numel(listing), 1);
hashes = strings(numel(listing), 1);
for ii = 1:numel(listing)
    fullPath = fullfile(listing(ii).folder, listing(ii).name);
    relative(ii) = erase(string(fullPath), string(folder) + filesep);
    hashes(ii) = sha256_file(fullPath);
end
[relative, order] = sort(relative);
hashes = hashes(order);
payload = join(relative + "|" + hashes, newline);
md = java.security.MessageDigest.getInstance('SHA-256');
md.update(unicode2native(char(payload), 'UTF-8'));
digest = lower(string(reshape(dec2hex( ...
    typecast(md.digest(), 'uint8'), 2).', 1, [])));
end

function digest = sha256_file(path)
fid = fopen(path, 'rb');
if fid < 0
    error('Step-03U cannot open file for SHA-256: %s', path);
end
cleanup = onCleanup(@() fclose(fid));
md = java.security.MessageDigest.getInstance('SHA-256');
while true
    bytes = fread(fid, 1024 * 1024, '*uint8');
    if isempty(bytes)
        break;
    end
    md.update(bytes);
end
clear cleanup;
digest = lower(string(reshape(dec2hex( ...
    typecast(md.digest(), 'uint8'), 2).', 1, [])));
end
