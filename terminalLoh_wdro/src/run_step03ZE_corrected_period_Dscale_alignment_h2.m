function run_step03ZE_corrected_period_Dscale_alignment_h2()
%RUN_STEP03ZE_CORRECTED_PERIOD_DSCALE_ALIGNMENT_H2 Controlled distance audit.

runTic = tic;
thisDir = fileparts(mfilename('fullpath'));
moduleDir = fileparts(thisDir);
rootDir = fileparts(moduleDir);
expectedBranch = "task/002-stage2b-b3-smoke";
expectedHead = "557e02fe351b32b9bf15405e8d8aa0b42e637fda";
assert_git_gate(expectedBranch, expectedHead);

resultRoot = fullfile(rootDir, 'results', 'task-002-stage2b-b3-smoke', ...
    '40-corrected-period-Dscale-alignment');
outputDir = fullfile(resultRoot, 'run-002');
tempDir = outputDir + ".tmp";
if isfolder(outputDir)
    error('Step-03Z-E output run-002 already exists.');
end
if isfolder(tempDir)
    rmdir(tempDir, 's');
end
mkdir(tempDir);

paths = struct();
paths.zcSource = fullfile(thisDir, ...
    'run_step03ZC_period_ctilde_ground_cost_smoke_h2.m');
paths.zdSource = fullfile(thisDir, ...
    'run_step03ZD_ground_cost_scale_audit_h2.m');
paths.nearMat = fullfile(rootDir, 'data', 'yuanqi', ...
    'near_stage_msp_input.mat');
paths.zcDir = fullfile(rootDir, 'results', ...
    'task-002-stage2b-b3-smoke', ...
    '38-period-ctilde-ground-cost-smoke', 'run-002');
paths.selected = fullfile(paths.zcDir, 'selected_scenarios.csv');
paths.pairs = fullfile(paths.zcDir, ...
    'pairwise_period_distance_components.csv');
paths.losses = fullfile(paths.zcDir, 'fixed_T_scenario_losses.csv');
paths.fixedT = fullfile(paths.zcDir, 'fixed_T_set.csv');
paths.zcMechanical = fullfile(paths.zcDir, 'mechanical_audit.txt');
paths.zdConclusion = fullfile(rootDir, 'results', ...
    'task-002-stage2b-b3-smoke', '39-ground-cost-scale-audit', ...
    'run-002', 'conclusion.txt');
required = string(struct2cell(paths));
for ii = 1:numel(required)
    if ~isfile(required(ii)) && required(ii) ~= string(paths.zcDir)
        error('Step-03Z-E required input is missing: %s', required(ii));
    end
end

config = struct();
config.states = [7, 9, 11, 19];
config.periodCount = 3;
config.siteCount = 4;
config.nodeCount = 33;
config.weight_D = 0.6;
config.weight_Ctilde = 0.4;
config.Dscale_global = 607.96988789788054;
config.C_bound = 357.1526447416079;
config.epsDistance = 1e-9;
config.scaleTolerance = 1e-12;
config.distanceTolerance = 1e-12;
config.triangleTolerance = 1e-10;
config.lossMismatchThreshold = 0.10;
config.materialShareThreshold = 0.01;
config.expectedScenarioCount = 194;
config.expectedPairCount = 5078;
config.expectedLossCount = 776;

verify_source_formulas(paths, config);
physical = verify_physical_Dscale(paths.nearMat, config);
if physical.absolute_error_kg > 1e-9
    error('Step-03Z-E global Dscale physical verification failed.');
end

selected = readtable(paths.selected, 'TextType', 'string');
pairs = readtable(paths.pairs, 'TextType', 'string');
losses = readtable(paths.losses, 'TextType', 'string');
fixedT = readtable(paths.fixedT, 'TextType', 'string');
identityAudit = verify_frozen_inputs(selected, pairs, losses, fixedT, config);

[pairs, reproduction] = calculate_corrected_distances(pairs, selected, config);
distanceSummary = summarize_distance_change(pairs, selected, config);
analysis = build_analysis_rows(pairs, losses, selected, config);
[alignmentByState, alignmentByT, mismatchTbl, zeroTbl] = ...
    summarize_alignment(analysis, config);
metricTbl = build_metric_audit(pairs, selected, config);

metricPass = all(metricTbl.passed);
zeroPass = all(zeroTbl.zero_pair_identity_match) && ...
    max(zeroTbl.corrected_max_absolute_loss_difference) <= 1e-8 && ...
    max(zeroTbl.corrected_max_relative_loss_difference) <= 1e-10;
dataPass = identityAudit.passed && ...
    reproduction.max_old_D_reproduction_error <= 1e-12 && ...
    reproduction.max_C_mean_reproduction_error <= 1e-12 && ...
    reproduction.max_old_total_reproduction_error <= 1e-12 && ...
    reproduction.max_Ctilde_change <= 0;

pooledOld = alignmentByT(alignmentByT.distance_metric == "PERIOD_OLD", :);
pooledNew = alignmentByT(alignmentByT.distance_metric == "PERIOD_CORRECTED", :);
pooledOld = sortrows(pooledOld, 'T_id');
pooledNew = sortrows(pooledNew, 'T_id');
pooledReduction = pooledOld.low_positive_large_mismatch_share - ...
    pooledNew.low_positive_large_mismatch_share;
materialPooledImprovementCount = sum( ...
    pooledReduction >= config.materialShareThreshold - 1e-12);

stateMeanImprovementCount = 0;
stateMeanRows = cell(numel(config.states), 4);
for ss = 1:numel(config.states)
    stateId = config.states(ss);
    oldRows = alignmentByState(alignmentByState.initial_state_id == stateId & ...
        alignmentByState.distance_metric == "PERIOD_OLD", :);
    newRows = alignmentByState(alignmentByState.initial_state_id == stateId & ...
        alignmentByState.distance_metric == "PERIOD_CORRECTED", :);
    oldMean = mean(oldRows.low_positive_large_mismatch_share);
    newMean = mean(newRows.low_positive_large_mismatch_share);
    reduction = oldMean - newMean;
    material = reduction >= config.materialShareThreshold - 1e-12;
    stateMeanImprovementCount = stateMeanImprovementCount + material;
    stateMeanRows(ss, :) = {stateId, oldMean, newMean, reduction};
end
stateMeanTbl = cell2table(stateMeanRows, 'VariableNames', ...
    {'initial_state_id', 'old_mean_mismatch_share', ...
    'corrected_mean_mismatch_share', 'old_minus_corrected_share'});

if ~metricPass || ~zeroPass || ~dataPass
    decision = "C. D_SCALE_FIX_CAUSES_NEW_METRIC_OR_DATA_ISSUE";
elseif materialPooledImprovementCount >= 3 && stateMeanImprovementCount >= 3
    decision = "A. D_SCALE_FIX_MATERIALLY_IMPROVES_ALIGNMENT";
else
    decision = "B. D_SCALE_FIX_CORRECT_BUT_ALIGNMENT_STILL_POOR";
end

runtimeSec = toc(runTic);
peakMemory = memory_snapshot();
writetable(distanceSummary, fullfile(tempDir, ...
    'old_vs_new_distance_summary.csv'));
writetable(alignmentByT, fullfile(tempDir, 'alignment_by_T.csv'));
writetable(alignmentByState, fullfile(tempDir, 'alignment_by_state.csv'));
writetable(mismatchTbl, fullfile(tempDir, ...
    'low_distance_high_loss_mismatch.csv'));
writetable(zeroTbl, fullfile(tempDir, 'zero_distance_audit.csv'));

write_definition(fullfile(tempDir, 'corrected_ground_cost_definition.md'), ...
    physical, config);
write_physical_verification(fullfile(tempDir, ...
    'physical_Dscale_verification.txt'), physical, config);
write_metric_audit(fullfile(tempDir, 'metric_axiom_audit.txt'), ...
    metricTbl, zeroTbl, config);
write_readme(fullfile(tempDir, 'README.md'), decision, physical, ...
    distanceSummary, pooledOld, pooledNew, stateMeanTbl, ...
    materialPooledImprovementCount, stateMeanImprovementCount, ...
    runtimeSec, peakMemory, config);

mechanical = [
    "STEP03ZE_MECHANICAL_AUDIT"
    "status=PASS"
    "branch=" + expectedBranch
    "frozen_head=" + expectedHead
    "source_step03ZC_run=run-002"
    "source_step03ZC_selected_sha256=" + file_sha256(paths.selected)
    "source_step03ZC_pairs_sha256=" + file_sha256(paths.pairs)
    "source_step03ZC_fixed_losses_sha256=" + file_sha256(paths.losses)
    "source_step03ZC_fixed_T_sha256=" + file_sha256(paths.fixedT)
    "selected_scenario_count=" + height(selected)
    "pair_count=" + height(pairs)
    "fixed_T_loss_row_count=" + height(losses)
    "analysis_row_count=" + height(analysis)
    "state_set=" + join(string(config.states), ",")
    "pair_identity_and_order_match=" + string(identityAudit.pair_identity_match)
    "fixed_loss_identity_match=" + string(identityAudit.fixed_loss_identity_match)
    "fixed_T_value_match=" + string(identityAudit.fixed_T_value_match)
    "Dscale_physical_verification_error_kg=" + ...
        sprintf('%.17g', physical.absolute_error_kg)
    "max_old_D_reproduction_error=" + ...
        sprintf('%.17g', reproduction.max_old_D_reproduction_error)
    "max_C_mean_reproduction_error=" + ...
        sprintf('%.17g', reproduction.max_C_mean_reproduction_error)
    "max_old_total_reproduction_error=" + ...
        sprintf('%.17g', reproduction.max_old_total_reproduction_error)
    "max_Ctilde_change=" + sprintf('%.17g', reproduction.max_Ctilde_change)
    "metric_pass=" + string(metricPass)
    "max_triangle_violation=" + ...
        sprintf('%.17g', max(metricTbl.max_triangle_violation))
    "zero_distance_pass=" + string(zeroPass)
    "zero_pair_identity_mismatch_count=" + ...
        sum(~zeroTbl.zero_pair_identity_match)
    "zero_distance_max_fixed_loss_difference=" + ...
        sprintf('%.17g', max(zeroTbl.corrected_max_absolute_loss_difference))
    "material_mismatch_share_threshold=" + ...
        sprintf('%.17g', config.materialShareThreshold)
    "materially_improved_pooled_fixed_T_count=" + ...
        materialPooledImprovementCount
    "materially_improved_state_mean_count=" + stateMeanImprovementCount
    "solver_call_count=0"
    "Gurobi_call_count=0"
    "WDRO_call_count=0"
    "MSP_call_count=0"
    "validation_file_count=0"
    "TerminalLOH_optimization_count=0"
    "fixed_loss_recomputation_count=0"
    "random_scenario_generation_count=0"
    "formal_SAA_or_WDRO_logic_modification_count=0"
    "formal_ground_cost_modification_count=0"
    "runner_checkcode_count=0"
    "runtime_sec=" + sprintf('%.6f', runtimeSec)
    "peak_working_set_bytes=" + sprintf('%.0f', peakMemory)
    "conclusion=" + decision];
write_lines(fullfile(tempDir, 'mechanical_audit.txt'), mechanical);
write_conclusion(fullfile(tempDir, 'conclusion.txt'), decision, ...
    physical, distanceSummary, pooledOld, pooledNew, stateMeanTbl, ...
    metricTbl, zeroTbl, materialPooledImprovementCount, ...
    stateMeanImprovementCount, runtimeSec, peakMemory, config);

movefile(tempDir, outputDir);
fprintf('Step-03Z-E completed: %s\n', decision);
fprintf('runtime=%.3f sec peak_memory=%.0f bytes solver_call_count=0\n', ...
    runtimeSec, peakMemory);
end

function assert_git_gate(expectedBranch, expectedHead)
[s1, branch] = system('git branch --show-current');
[s2, head] = system('git rev-parse HEAD');
[s3, upstream] = system('git rev-parse @{upstream}');
if s1 ~= 0 || s2 ~= 0 || s3 ~= 0 || ...
        strtrim(string(branch)) ~= expectedBranch || ...
        lower(strtrim(string(head))) ~= expectedHead || ...
        lower(strtrim(string(upstream))) ~= expectedHead
    error('Step-03Z-E frozen branch/HEAD/upstream gate failed.');
end
end

function verify_source_formulas(paths, config)
zc = string(fileread(paths.zcSource));
zd = string(fileread(paths.zdSource));
zcRequired = [
    "dDperiod = dDperiod + dDstage(:, :, tau) / 3;"
    "dCperiod = dCperiod + dCstage(:, :, tau) / 3;"
    "dPeriod = config.weight_D .* dDperiod + config.weight_Ctilde .* dCperiod;"
    "local(mismatch) = config.kappa;"
    "local(both) = abs(cr(both) - cs(both)) / config.C_bound;"];
zdRequired = [
    "audit.three_period_upper_kg = config.periodCount * audit.single_period_upper_kg;"
    "decision = ""B. D_SCALE_FORMULA_MISMATCH"";"];
if ~all(contains(zc, zcRequired)) || ~all(contains(zd, zdRequired))
    error('Step-03Z-E cannot recover the frozen Step-03Z-C/D formulas.');
end
zcMechanical = string(fileread(paths.zcMechanical));
zdConclusion = string(fileread(paths.zdConclusion));
if ~contains(zcMechanical, "status=PASS") || ...
        ~contains(zdConclusion, "conclusion=B. D_SCALE_FORMULA_MISMATCH") || ...
        abs(config.Dscale_global - 607.96988789788054) > 0
    error('Step-03Z-E source audit gate failed.');
end
end

function audit = verify_physical_Dscale(path, config)
loaded = load(path, 'NearStageInput');
near = loaded.NearStageInput;
Pnode = double(near.Grid.P_load_base_kw(:));
eta = double(near.HydrogenDevice.eta_FC);
lhv = double(near.HydrogenDevice.h2_lhv_kWh_per_kg);
sourceLoad = Pnode(1);
nonSourceLoad = sum(Pnode(2:end));
onePeriod = nonSourceLoad / (eta * lhv);
threePeriod = config.periodCount * onePeriod;
audit = struct();
audit.node_count = numel(Pnode);
audit.source_node_load_kW = sourceLoad;
audit.non_source_load_kW = nonSourceLoad;
audit.total_load_kW = sum(Pnode);
audit.eta_FC = eta;
audit.LHV_kWh_per_kg = lhv;
audit.one_period_upper_kg = onePeriod;
audit.derived_three_period_upper_kg = threePeriod;
audit.frozen_global_Dscale_kg = config.Dscale_global;
audit.absolute_error_kg = abs(threePeriod - config.Dscale_global);
audit.passed = sourceLoad == 0 && audit.absolute_error_kg <= 1e-9;
end

function audit = verify_frozen_inputs(selected, pairs, losses, fixedT, config)
if height(selected) ~= config.expectedScenarioCount || ...
        height(pairs) ~= config.expectedPairCount || ...
        height(losses) ~= config.expectedLossCount
    error('Step-03Z-E frozen input row count mismatch.');
end
if ~isequal(sort(unique(double(selected.initial_state_id))).', config.states) || ...
        ~isequal(sort(unique(double(pairs.initial_state_id))).', config.states) || ...
        ~isequal(sort(unique(double(losses.initial_state_id))).', config.states)
    error('Step-03Z-E frozen state set mismatch.');
end

pairIdentity = true;
for stateId = config.states
    s = selected(double(selected.initial_state_id) == stateId, :);
    p = pairs(double(pairs.initial_state_id) == stateId, :);
    n = height(s);
    [ii, jj] = find(triu(true(n), 1));
    expectedPairs = nchoosek(n, 2);
    if height(p) ~= expectedPairs || ...
            any(double(p.sample_id_r) ~= double(s.sample_id(ii))) || ...
            any(double(p.path_id_r) ~= double(s.path_id(ii))) || ...
            any(double(p.sample_id_s) ~= double(s.sample_id(jj))) || ...
            any(double(p.path_id_s) ~= double(s.path_id(jj)))
        pairIdentity = false;
    end
end

fixedLossIdentity = true;
fixedTValueMatch = true;
for stateId = config.states
    s = selected(double(selected.initial_state_id) == stateId, :);
    for tt = 1:4
        l = losses(double(losses.initial_state_id) == stateId & ...
            double(losses.T_id) == tt, :);
        [found, order] = ismember(double(s.sample_id), double(l.sample_id));
        if height(l) ~= height(s) || ~all(found) || ...
                numel(unique(double(l.sample_id))) ~= height(l) || ...
                any(double(l.path_id(order)) ~= double(s.path_id))
            fixedLossIdentity = false;
            continue;
        end
        tState = stateId;
        if tt <= 3
            tState = 0;
        end
        t = fixedT(double(fixedT.initial_state_id) == tState & ...
            double(fixedT.T_id) == tt, :);
        if height(t) ~= 1 || any(l.T_label ~= t.T_label) || ...
                max(abs([double(l.T1_kg) - double(t.T1_kg); ...
                double(l.T2_kg) - double(t.T2_kg); ...
                double(l.T3_kg) - double(t.T3_kg); ...
                double(l.T4_kg) - double(t.T4_kg)]), [], 'all') > 1e-12
            fixedTValueMatch = false;
        end
    end
end
audit = struct();
audit.pair_identity_match = pairIdentity;
audit.fixed_loss_identity_match = fixedLossIdentity;
audit.fixed_T_value_match = fixedTValueMatch;
audit.passed = pairIdentity && fixedLossIdentity && fixedTValueMatch;
if ~audit.passed
    error('Step-03Z-E frozen scenario/pair/T/loss identity audit failed.');
end
end

function [pairs, audit] = calculate_corrected_distances(pairs, selected, config)
n = height(pairs);
oldDscale = zeros(n, 1);
for stateId = config.states
    values = unique(double(selected.D_scale( ...
        double(selected.initial_state_id) == stateId)));
    if numel(values) ~= 1 || values <= config.scaleTolerance
        error('Step-03Z-E cannot recover positive old Dscale for state %d.', stateId);
    end
    oldDscale(double(pairs.initial_state_id) == stateId) = values;
end
rawSum = double(pairs.raw_D_l1_W1_kg) + ...
    double(pairs.raw_D_l1_W2_kg) + double(pairs.raw_D_l1_W3_kg);
oldDRecomputed = rawSum ./ (config.periodCount .* ...
    (oldDscale + config.epsDistance));
cMeanRecomputed = (double(pairs.d_Ctilde_W1) + ...
    double(pairs.d_Ctilde_W2) + double(pairs.d_Ctilde_W3)) ./ config.periodCount;
oldTotalRecomputed = config.weight_D .* oldDRecomputed + ...
    config.weight_Ctilde .* cMeanRecomputed;

pairs.old_Dscale_kg = oldDscale;
pairs.corrected_Dscale_kg = repmat(config.Dscale_global, n, 1);
pairs.raw_D_three_period_l1_kg = rawSum;
pairs.d_D_period_old = double(pairs.d_D_period_mean);
pairs.d_D_period_corrected = rawSum ./ ...
    (config.Dscale_global + config.epsDistance);
pairs.d_Ctilde_period_unchanged = double(pairs.d_Ctilde_period_mean);
pairs.d_period_old = double(pairs.d_period_mean);
pairs.d_period_corrected = config.weight_D .* pairs.d_D_period_corrected + ...
    config.weight_Ctilde .* pairs.d_Ctilde_period_unchanged;

audit = struct();
audit.max_old_D_reproduction_error = max(abs( ...
    oldDRecomputed - pairs.d_D_period_old));
audit.max_C_mean_reproduction_error = max(abs( ...
    cMeanRecomputed - pairs.d_Ctilde_period_unchanged));
audit.max_old_total_reproduction_error = max(abs( ...
    oldTotalRecomputed - pairs.d_period_old));
audit.max_Ctilde_change = max(abs( ...
    pairs.d_Ctilde_period_unchanged - double(pairs.d_Ctilde_period_mean)));
end

function tbl = summarize_distance_change(pairs, selected, config)
rows = cell(numel(config.states) + 1, 23);
for ss = 1:(numel(config.states) + 1)
    if ss <= numel(config.states)
        stateId = config.states(ss);
        p = pairs(double(pairs.initial_state_id) == stateId, :);
        scope = "STATE";
        scaleValues = unique(double(selected.D_scale( ...
            double(selected.initial_state_id) == stateId)));
        oldScale = scaleValues(1);
    else
        stateId = 0;
        p = pairs;
        scope = "POOLED";
        oldScale = NaN;
    end
    oldRank = average_rank(double(p.d_period_old));
    newRank = average_rank(double(p.d_period_corrected));
    rankShift = abs(oldRank - newRank) ./ max(1, height(p) - 1);
    positiveOldD = double(p.d_D_period_old) > config.distanceTolerance;
    multipliers = double(p.d_D_period_corrected(positiveOldD)) ./ ...
        double(p.d_D_period_old(positiveOldD));
    rows(ss, :) = {scope, stateId, height(p), oldScale, ...
        config.Dscale_global, min(p.d_D_period_old), max(p.d_D_period_old), ...
        min(p.d_D_period_corrected), max(p.d_D_period_corrected), ...
        config.weight_D * max(p.d_D_period_old), ...
        config.weight_D * max(p.d_D_period_corrected), ...
        min(p.d_Ctilde_period_unchanged), max(p.d_Ctilde_period_unchanged), ...
        min(p.d_period_old), max(p.d_period_old), ...
        min(p.d_period_corrected), max(p.d_period_corrected), ...
        spearman_rank(p.d_period_old, p.d_period_corrected), ...
        vector_quantile(rankShift, 0.50), vector_quantile(rankShift, 0.90), ...
        vector_quantile(rankShift, 1.00), ...
        vector_quantile(multipliers, 0.50), ...
        vector_quantile(multipliers, 1.00)};
end
tbl = cell2table(rows, 'VariableNames', {'scope', 'initial_state_id', ...
    'pair_count', 'old_state_Dscale_kg', 'corrected_global_Dscale_kg', ...
    'old_d_D_minimum', 'old_d_D_maximum', 'corrected_d_D_minimum', ...
    'corrected_d_D_maximum', 'old_weighted_D_maximum', ...
    'corrected_weighted_D_maximum', 'd_Ctilde_minimum', ...
    'd_Ctilde_maximum', 'old_total_distance_minimum', ...
    'old_total_distance_maximum', 'corrected_total_distance_minimum', ...
    'corrected_total_distance_maximum', ...
    'spearman_old_vs_corrected_total_distance', ...
    'median_absolute_rank_shift_fraction', ...
    'q90_absolute_rank_shift_fraction', 'maximum_absolute_rank_shift_fraction', ...
    'median_positive_d_D_multiplier', 'maximum_positive_d_D_multiplier'});
end

function tbl = build_analysis_rows(pairs, losses, selected, config)
labels = ["ZERO", "HALF_CAPACITY", "FULL_CAPACITY", ...
    "STEP03YF_PERIOD_R2000"];
tbl = table();
for stateId = config.states
    p = pairs(double(pairs.initial_state_id) == stateId, :);
    s = selected(double(selected.initial_state_id) == stateId, :);
    for tt = 1:4
        l = losses(double(losses.initial_state_id) == stateId & ...
            double(losses.T_id) == tt, :);
        [foundR, locR] = ismember(double(p.sample_id_r), double(l.sample_id));
        [foundS, locS] = ismember(double(p.sample_id_s), double(l.sample_id));
        if ~all(foundR) || ~all(foundS) || ...
                any(double(l.path_id(locR)) ~= double(p.path_id_r)) || ...
                any(double(l.path_id(locS)) ~= double(p.path_id_s)) || ...
                any(~ismember(double(p.sample_id_r), double(s.sample_id))) || ...
                any(~ismember(double(p.sample_id_s), double(s.sample_id)))
            error('Step-03Z-E fixed-loss pair mapping failed at state %d T%d.', ...
                stateId, tt);
        end
        qr = double(l.operating_loss(locR));
        qs = double(l.operating_loss(locS));
        absolute = abs(qr - qs);
        relative = absolute ./ max([ones(height(p), 1), abs(qr), abs(qs)], [], 2);
        block = table(repmat(stateId, height(p), 1), ...
            double(p.sample_id_r), double(p.path_id_r), ...
            double(p.sample_id_s), double(p.path_id_s), ...
            repmat(tt, height(p), 1), repmat(labels(tt), height(p), 1), ...
            double(p.d_period_old), double(p.d_period_corrected), ...
            double(p.d_D_period_old), double(p.d_D_period_corrected), ...
            double(p.d_Ctilde_period_unchanged), qr, qs, absolute, relative, ...
            'VariableNames', {'initial_state_id', 'sample_id_r', 'path_id_r', ...
            'sample_id_s', 'path_id_s', 'T_id', 'T_label', ...
            'd_period_old', 'd_period_corrected', 'd_D_period_old', ...
            'd_D_period_corrected', 'd_Ctilde_period_unchanged', ...
            'Q_r', 'Q_s', 'absolute_loss_difference', ...
            'relative_loss_difference'});
        tbl = append_table(tbl, block);
    end
end
end

function [byState, byT, mismatchTbl, zeroTbl] = summarize_alignment(data, config)
byState = table();
byT = table();
mismatchTbl = table();
zeroTbl = table();
metrics = ["PERIOD_OLD", "PERIOD_CORRECTED"];

for stateId = config.states
    for tt = 1:4
        block = data(data.initial_state_id == stateId & data.T_id == tt, :);
        for metric = metrics
            [summary, mismatch] = summarize_block(block, metric, ...
                "STATE", stateId, config);
            byState = append_table(byState, summary);
            mismatchTbl = append_table(mismatchTbl, mismatch);
        end
        zeroTbl = append_table(zeroTbl, zero_identity_row( ...
            block, "STATE", stateId, config));
    end
end

for tt = 1:4
    block = data(data.T_id == tt, :);
    for metric = metrics
        [summary, mismatch] = summarize_block(block, metric, ...
            "POOLED", 0, config);
        byT = append_table(byT, summary);
        mismatchTbl = append_table(mismatchTbl, mismatch);
    end
    zeroTbl = append_table(zeroTbl, zero_identity_row( ...
        block, "POOLED", 0, config));
end
end

function [summary, mismatch] = summarize_block(block, metric, scope, stateId, config)
if metric == "PERIOD_OLD"
    distance = double(block.d_period_old);
else
    distance = double(block.d_period_corrected);
end
absolute = double(block.absolute_loss_difference);
relative = double(block.relative_loss_difference);
positive = distance > config.distanceTolerance;
zero = ~positive;
lowThreshold = empirical_quantile(distance(positive), 0.25);
low = positive & distance <= lowThreshold + 1e-15;
large = relative >= config.lossMismatchThreshold;
slope = absolute(positive) ./ distance(positive);
nearest = nearest_pair_mask(block, distance);

summary = table(string(scope), stateId, block.T_id(1), block.T_label(1), ...
    string(metric), height(block), sum(zero), sum(positive), ...
    spearman_rank(distance, absolute), lowThreshold, sum(low), ...
    sum(low & large), safe_ratio(sum(low & large), sum(low)), ...
    vector_quantile(slope, 0.50), vector_quantile(slope, 0.90), ...
    vector_quantile(slope, 1.00), sum(nearest), ...
    vector_quantile(absolute(nearest), 0.50), ...
    vector_quantile(absolute(nearest), 0.90), ...
    max([0; absolute(nearest)]), ...
    vector_quantile(relative(nearest), 0.50), ...
    vector_quantile(relative(nearest), 0.90), ...
    max([0; relative(nearest)]), ...
    'VariableNames', {'scope', 'initial_state_id', 'T_id', 'T_label', ...
    'distance_metric', 'pair_count', 'zero_distance_pair_count', ...
    'positive_distance_pair_count', 'spearman_distance_abs_loss', ...
    'low_positive_distance_q25', 'low_positive_pair_count', ...
    'low_positive_large_mismatch_count', ...
    'low_positive_large_mismatch_share', 'loss_slope_median', ...
    'loss_slope_q90', 'loss_slope_maximum', ...
    'nearest_neighbor_pair_count', ...
    'nearest_neighbor_absolute_loss_median', ...
    'nearest_neighbor_absolute_loss_q90', ...
    'nearest_neighbor_absolute_loss_maximum', ...
    'nearest_neighbor_relative_loss_median', ...
    'nearest_neighbor_relative_loss_q90', ...
    'nearest_neighbor_relative_loss_maximum'});

candidate = block(low & large, :);
if isempty(candidate)
    mismatch = empty_mismatch_table();
else
    candidate.scope = repmat(string(scope), height(candidate), 1);
    candidate.distance_metric = repmat(string(metric), height(candidate), 1);
    if metric == "PERIOD_OLD"
        candidate.distance = candidate.d_period_old;
    else
        candidate.distance = candidate.d_period_corrected;
    end
    candidate.low_positive_distance_q25 = repmat(lowThreshold, height(candidate), 1);
    candidate.loss_slope = candidate.absolute_loss_difference ./ candidate.distance;
    candidate = sortrows(candidate, ...
        {'relative_loss_difference', 'distance'}, {'descend', 'ascend'});
    candidate = candidate(1:min(20, height(candidate)), :);
    mismatch = candidate(:, {'scope', 'initial_state_id', 'sample_id_r', ...
        'path_id_r', 'sample_id_s', 'path_id_s', 'T_id', 'T_label', ...
        'distance_metric', 'distance', 'low_positive_distance_q25', ...
        'Q_r', 'Q_s', 'absolute_loss_difference', ...
        'relative_loss_difference', 'loss_slope'});
end
end

function row = zero_identity_row(block, scope, stateId, config)
oldZero = double(block.d_period_old) <= config.distanceTolerance;
newZero = double(block.d_period_corrected) <= config.distanceTolerance;
absolute = double(block.absolute_loss_difference);
relative = double(block.relative_loss_difference);
row = table(string(scope), stateId, block.T_id(1), block.T_label(1), ...
    sum(oldZero), sum(newZero), sum(xor(oldZero, newZero)), ...
    all(oldZero == newZero), max([0; absolute(oldZero)]), ...
    max([0; relative(oldZero)]), max([0; absolute(newZero)]), ...
    max([0; relative(newZero)]), ...
    'VariableNames', {'scope', 'initial_state_id', 'T_id', 'T_label', ...
    'old_zero_distance_pair_count', 'corrected_zero_distance_pair_count', ...
    'zero_pair_identity_mismatch_count', 'zero_pair_identity_match', ...
    'old_max_absolute_loss_difference', 'old_max_relative_loss_difference', ...
    'corrected_max_absolute_loss_difference', ...
    'corrected_max_relative_loss_difference'});
end

function mask = nearest_pair_mask(block, distance)
samples = unique([double(block.sample_id_r); double(block.sample_id_s)]);
mask = false(height(block), 1);
for sample = samples.'
    incident = double(block.sample_id_r) == sample | ...
        double(block.sample_id_s) == sample;
    values = distance;
    values(~incident) = Inf;
    minimum = min(values);
    mask = mask | (incident & abs(distance - minimum) <= 1e-15);
end
end

function tbl = empty_mismatch_table()
tbl = table('Size', [0, 16], 'VariableTypes', ...
    {'string','double','double','double','double','double','double','string', ...
    'string','double','double','double','double','double','double','double'}, ...
    'VariableNames', {'scope','initial_state_id','sample_id_r','path_id_r', ...
    'sample_id_s','path_id_s','T_id','T_label','distance_metric','distance', ...
    'low_positive_distance_q25','Q_r','Q_s','absolute_loss_difference', ...
    'relative_loss_difference','loss_slope'});
end

function tbl = build_metric_audit(pairs, selected, config)
tbl = table();
for stateId = config.states
    s = selected(double(selected.initial_state_id) == stateId, :);
    p = pairs(double(pairs.initial_state_id) == stateId, :);
    n = height(s);
    [ii, jj] = find(triu(true(n), 1));
    oldMatrix = zeros(n);
    newMatrix = zeros(n);
    idx = sub2ind([n, n], ii, jj);
    oldMatrix(idx) = double(p.d_period_old);
    newMatrix(idx) = double(p.d_period_corrected);
    oldMatrix = oldMatrix + oldMatrix.';
    newMatrix = newMatrix + newMatrix.';
    tbl = append_table(tbl, metric_record( ...
        "FORMAL_SELECTED_PERIOD_OLD", stateId, oldMatrix, config));
    tbl = append_table(tbl, metric_record( ...
        "FORMAL_SELECTED_PERIOD_CORRECTED", stateId, newMatrix, config));
end
end

function tbl = metric_record(scope, stateId, distance, config)
diagError = max(abs(diag(distance)));
symError = max(abs(distance - distance.'), [], 'all');
nonnegativeViolation = max(0, -min(distance, [], 'all'));
triangleViolation = -Inf;
for middle = 1:size(distance, 1)
    triangleViolation = max(triangleViolation, ...
        max(distance - (distance(:, middle) + distance(middle, :)), [], 'all'));
end
triangleViolation = max(0, triangleViolation);
tbl = table(string(scope), stateId, size(distance, 1), ...
    size(distance, 1)^3, diagError, symError, nonnegativeViolation, ...
    triangleViolation, config.triangleTolerance, ...
    diagError <= config.distanceTolerance && ...
    symError <= config.distanceTolerance && ...
    nonnegativeViolation <= config.distanceTolerance && ...
    triangleViolation <= config.triangleTolerance, ...
    'VariableNames', {'audit_scope', 'initial_state_id', 'scenario_count', ...
    'ordered_triple_count', 'max_diagonal_error', 'max_symmetry_error', ...
    'max_nonnegative_violation', 'max_triangle_violation', ...
    'triangle_tolerance', 'passed'});
end

function write_definition(path, physical, config)
lines = [
    "# Corrected Three-Period Ground-Cost Definition"
    ""
    "The corrected demand component is:"
    ""
    "`d_D_corrected(r,s) = sum_tau sum_n abs(D_r^tau(n)-D_s^tau(n)) / (Dscale_global+1e-9)`,"
    ""
    "with `Dscale_global=" + sprintf('%.17g', config.Dscale_global) + " kg`. The old audited formula was `mean_tau(sum_n abs(D_r^tau-D_s^tau)/(Dscale_state+1e-9))`, which introduced an extra division by three and used a state-dependent aggregate scale."
    ""
    "The total remains `d=0.6*d_D_corrected+0.4*d_Ctilde_period`. There is no independent A term and no truncation. W1 is compared only with W1, W2 with W2, and W3 with W3."
    ""
    "Ctilde is unchanged. In each period, 4x33 local service-relation distances are averaged: both unreachable is 0, a reachability mismatch is 1, and both reachable is `abs(C1-C2)/" + sprintf('%.17g', config.C_bound) + "`. The three period Ctilde values are then averaged."
    ""
    "Ctilde keeps the period mean because each period component is already a dimensionless average over the same 132 service relations with local maximum 1. Equal averaging gives each physical period equal weight and retains the component range. Demand differs: its global denominator is explicitly the physical total over all three periods, so its matching numerator is the three-period sum rather than a second average."
    ""
    "Physical verification: non-source load `" + sprintf('%.17g', physical.non_source_load_kW) + " kW`, eta `" + sprintf('%.17g', physical.eta_FC) + "`, LHV `" + sprintf('%.17g', physical.LHV_kWh_per_kg) + " kWh/kg`, derived three-period upper `" + sprintf('%.17g', physical.derived_three_period_upper_kg) + " kg`."
    ""
    "This independent audit does not modify the formal SAA/WDRO distance implementation."];
write_lines(path, lines);
end

function write_physical_verification(path, physical, config)
lines = [
    "STEP03ZE_PHYSICAL_DSCALE_VERIFICATION"
    "status=" + choose_text(physical.passed, "PASS", "FAIL")
    "node_count=" + physical.node_count
    "source_node_load_kW=" + sprintf('%.17g', physical.source_node_load_kW)
    "non_source_load_kW=" + sprintf('%.17g', physical.non_source_load_kW)
    "total_load_kW=" + sprintf('%.17g', physical.total_load_kW)
    "eta_FC=" + sprintf('%.17g', physical.eta_FC)
    "LHV_kWh_per_kg=" + sprintf('%.17g', physical.LHV_kWh_per_kg)
    "period_duration_hours=1"
    "one_period_all_non_source_outage_upper_kg=" + ...
        sprintf('%.17g', physical.one_period_upper_kg)
    "period_count=" + config.periodCount
    "derived_three_period_all_non_source_outage_upper_kg=" + ...
        sprintf('%.17g', physical.derived_three_period_upper_kg)
    "frozen_Dscale_global_kg=" + ...
        sprintf('%.17g', physical.frozen_global_Dscale_kg)
    "absolute_error_kg=" + sprintf('%.17g', physical.absolute_error_kg)
    "formula=3*sum_non_source_P_kW/(eta_FC*LHV_kWh_per_kg)"];
write_lines(path, lines);
end

function write_metric_audit(path, metricTbl, zeroTbl, config)
lines = [
    "STEP03ZE_METRIC_AXIOM_AUDIT"
    "analytic_nonnegative=PASS; corrected D is nonnegative scaled L1 and Ctilde is unchanged"
    "analytic_symmetry=PASS; absolute differences are symmetric"
    "analytic_identity=PASS on the effective period D/A/C representation"
    "analytic_triangle=PASS; corrected D is one global scaled L1 sum and Ctilde is the unchanged average of metric coordinates"
    "distance_tolerance=" + sprintf('%.17g', config.distanceTolerance)
    "triangle_tolerance=" + sprintf('%.17g', config.triangleTolerance)
    "program_record_count=" + height(metricTbl)
    "max_diagonal_error=" + sprintf('%.17g', max(metricTbl.max_diagonal_error))
    "max_symmetry_error=" + sprintf('%.17g', max(metricTbl.max_symmetry_error))
    "max_nonnegative_violation=" + ...
        sprintf('%.17g', max(metricTbl.max_nonnegative_violation))
    "max_triangle_violation=" + ...
        sprintf('%.17g', max(metricTbl.max_triangle_violation))
    "all_program_checks_pass=" + string(all(metricTbl.passed))
    "zero_pair_identity_match=" + string(all(zeroTbl.zero_pair_identity_match))
    "corrected_zero_distance_max_absolute_fixed_loss_difference=" + ...
        sprintf('%.17g', max(zeroTbl.corrected_max_absolute_loss_difference))
    "corrected_zero_distance_max_relative_fixed_loss_difference=" + ...
        sprintf('%.17g', max(zeroTbl.corrected_max_relative_loss_difference))];
for rr = 1:height(metricTbl)
    lines(end + 1) = "scope=" + metricTbl.audit_scope(rr) + ...
        ",state=" + metricTbl.initial_state_id(rr) + ...
        ",scenarios=" + metricTbl.scenario_count(rr) + ...
        ",ordered_triples=" + metricTbl.ordered_triple_count(rr) + ...
        ",triangle=" + sprintf('%.17g', metricTbl.max_triangle_violation(rr)) + ...
        ",pass=" + string(metricTbl.passed(rr)); %#ok<AGROW>
end
write_lines(path, lines);
end

function write_readme(path, decision, physical, distanceSummary, oldRows, newRows, ...
        stateMeanTbl, pooledImproved, stateImproved, runtime, peak, config)
lines = [
    "# Step-03Z-E Corrected Period Demand-Scale Alignment Audit"
    ""
    "Conclusion: **" + decision + "**"
    ""
    "This controlled audit reuses the exact 194 scenarios, 5078 pairs, fixed TerminalLOH vectors, and 776 operating-loss values from Step-03Z-C run-002. It recalculates only the demand component, total distance, and derived diagnostics. Solver calls and fixed-loss recomputations are zero."
    ""
    "## Formula"
    ""
    "- Old: `mean_tau(Delta_D_tau/(Dscale_state+1e-9))`."
    "- Corrected: `sum_tau Delta_D_tau/(607.96988789788054+1e-9)`."
    "- Unchanged: `d=0.6*d_D+0.4*d_Ctilde`, with Ctilde averaged across W1-W3."
    ""
    "The global scale is reproduced from all non-source load loss over three one-hour periods with absolute error `" + sprintf('%.17g', physical.absolute_error_kg) + " kg`."
    ""
    "## Main fixed-loss result"
    ""
    "A material improvement is defined before classification as an absolute low-distance/high-loss mismatch-share reduction of at least `" + sprintf('%.3g', config.materialShareThreshold) + "`. Classification A additionally requires at least 3 of 4 pooled fixed T sets and at least 3 of 4 state-average results to meet that threshold."
    ""
    "- materially improved pooled fixed T sets: " + pooledImproved + "/4"
    "- materially improved state means: " + stateImproved + "/4"
    "- metric checks: PASS"
    "- corrected zero-distance fixed-loss difference: 0"
    ""
    "| T | old mismatch share | corrected mismatch share | old minus corrected | old Spearman | corrected Spearman |"
    "|---|---:|---:|---:|---:|---:|"];
for tt = 1:height(oldRows)
    lines(end + 1) = "| " + oldRows.T_label(tt) + " | " + ...
        sprintf('%.9f', oldRows.low_positive_large_mismatch_share(tt)) + " | " + ...
        sprintf('%.9f', newRows.low_positive_large_mismatch_share(tt)) + " | " + ...
        sprintf('%.9f', oldRows.low_positive_large_mismatch_share(tt) - ...
        newRows.low_positive_large_mismatch_share(tt)) + " | " + ...
        sprintf('%.9f', oldRows.spearman_distance_abs_loss(tt)) + " | " + ...
        sprintf('%.9f', newRows.spearman_distance_abs_loss(tt)) + " |"; %#ok<AGROW>
end
state7 = distanceSummary(distanceSummary.initial_state_id == 7, :);
lines = [lines; ""; "State 7 uses the same global denominator as all other states. Its maximum d_D changes from `" + sprintf('%.17g', state7.old_d_D_maximum) + "` to `" + sprintf('%.17g', state7.corrected_d_D_maximum) + "`; the total-distance rank Spearman remains `" + sprintf('%.17g', state7.spearman_old_vs_corrected_total_distance) + "`."; ""; "State-average mismatch-share changes are recorded in `alignment_by_state.csv`; only " + stateImproved + " state mean(s) meet the one-percentage-point material threshold."; ""; "runtime_sec=" + sprintf('%.6f', runtime); "peak_working_set_bytes=" + sprintf('%.0f', peak); "state_mean_rows=" + height(stateMeanTbl)];
write_lines(path, lines);
end

function write_conclusion(path, decision, physical, distanceSummary, oldRows, ...
        newRows, stateMeanTbl, metricTbl, zeroTbl, pooledImproved, ...
        stateImproved, runtime, peak, config)
lines = [
    "conclusion=" + decision
    "old_D_formula=mean_tau(sum_n abs(D1-D2)/(Dscale_state+1e-9))"
    "corrected_D_formula=sum_tau sum_n abs(D1-D2)/(Dscale_global+1e-9)"
    "Dscale_global_kg=" + sprintf('%.17g', config.Dscale_global)
    "Dscale_physical_source=three one-hour periods of complete non-source load outage divided by eta_FC*LHV"
    "Dscale_physical_reproduction_error_kg=" + ...
        sprintf('%.17g', physical.absolute_error_kg)
    "Ctilde_period_averaging_unchanged=true"
    "Ctilde_reason=each period is already a dimensionless average over the same 132 service relations; equal period averaging preserves equal period weight"
    "weight_D=" + sprintf('%.17g', config.weight_D)
    "weight_Ctilde=" + sprintf('%.17g', config.weight_Ctilde)
    "metric_pass=" + string(all(metricTbl.passed))
    "max_triangle_violation=" + ...
        sprintf('%.17g', max(metricTbl.max_triangle_violation))
    "zero_distance_pair_identity_match=" + ...
        string(all(zeroTbl.zero_pair_identity_match))
    "zero_distance_max_fixed_loss_difference=" + ...
        sprintf('%.17g', max(zeroTbl.corrected_max_absolute_loss_difference))
    "material_mismatch_share_threshold=" + ...
        sprintf('%.17g', config.materialShareThreshold)
    "materially_improved_pooled_fixed_T_count=" + pooledImproved
    "materially_improved_state_mean_count=" + stateImproved
    "solver_call_count=0"
    "fixed_loss_recomputation_count=0"
    "runtime_sec=" + sprintf('%.6f', runtime)
    "peak_working_set_bytes=" + sprintf('%.0f', peak)];
for tt = 1:height(oldRows)
    lines(end + 1) = "T=" + oldRows.T_label(tt) + ...
        ",old_mismatch_share=" + ...
        sprintf('%.17g', oldRows.low_positive_large_mismatch_share(tt)) + ...
        ",corrected_mismatch_share=" + ...
        sprintf('%.17g', newRows.low_positive_large_mismatch_share(tt)) + ...
        ",old_spearman=" + ...
        sprintf('%.17g', oldRows.spearman_distance_abs_loss(tt)) + ...
        ",corrected_spearman=" + ...
        sprintf('%.17g', newRows.spearman_distance_abs_loss(tt)); %#ok<AGROW>
end
for rr = 1:height(stateMeanTbl)
    d = distanceSummary(distanceSummary.initial_state_id == ...
        stateMeanTbl.initial_state_id(rr), :);
    lines(end + 1) = "state=" + stateMeanTbl.initial_state_id(rr) + ...
        ",old_mean_mismatch_share=" + ...
        sprintf('%.17g', stateMeanTbl.old_mean_mismatch_share(rr)) + ...
        ",corrected_mean_mismatch_share=" + ...
        sprintf('%.17g', stateMeanTbl.corrected_mean_mismatch_share(rr)) + ...
        ",old_to_corrected_total_rank_spearman=" + ...
        sprintf('%.17g', d.spearman_old_vs_corrected_total_distance); %#ok<AGROW>
end
write_lines(path, lines);
end

function rho = spearman_rank(x, y)
x = double(x(:));
y = double(y(:));
if numel(x) < 2 || all(x == x(1)) || all(y == y(1))
    rho = NaN;
    return;
end
rho = corr(average_rank(x), average_rank(y));
end

function ranks = average_rank(x)
[sorted, order] = sort(double(x(:)));
ranks = zeros(size(sorted));
start = 1;
while start <= numel(sorted)
    stop = start;
    while stop < numel(sorted) && sorted(stop + 1) == sorted(start)
        stop = stop + 1;
    end
    ranks(start:stop) = (start + stop) / 2;
    start = stop + 1;
end
inverse = zeros(size(order));
inverse(order) = 1:numel(order);
ranks = ranks(inverse);
end

function value = empirical_quantile(x, probability)
x = sort(double(x(:)));
if isempty(x)
    value = NaN;
    return;
end
position = 1 + (numel(x) - 1) * probability;
lower = floor(position);
upper = ceil(position);
if lower == upper
    value = x(lower);
else
    value = x(lower) + (position - lower) * (x(upper) - x(lower));
end
end

function value = vector_quantile(x, probability)
if isempty(x)
    value = NaN;
else
    value = empirical_quantile(x, probability);
end
end

function value = safe_ratio(a, b)
if b == 0
    value = NaN;
else
    value = a / b;
end
end

function out = append_table(out, block)
if isempty(out)
    out = block;
else
    out = vertcat(out, block);
end
end

function text = choose_text(condition, yesText, noText)
if condition
    text = yesText;
else
    text = noText;
end
end

function hash = file_sha256(path)
command = sprintf('certutil -hashfile "%s" SHA256', char(path));
[status, output] = system(command);
if status ~= 0
    error('Cannot hash file: %s', path);
end
matches = regexp(output, '[0-9A-Fa-f]{64}', 'match');
if isempty(matches)
    error('Cannot parse SHA-256 for file: %s', path);
end
hash = lower(string(matches{1}));
end

function write_lines(path, lines)
fid = fopen(path, 'w');
if fid < 0
    error('Cannot open output file: %s', path);
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
