function run_step03ZC_period_ctilde_ground_cost_smoke_h2()
%RUN_STEP03ZC_PERIOD_CTILDE_GROUND_COST_SMOKE_H2 Independent Step-03Z-C audit.

runTic = tic;
thisDir = fileparts(mfilename('fullpath'));
moduleDir = fileparts(thisDir);
rootDir = fileparts(moduleDir);
addpath(rootDir); addpath(thisDir);
for candidate = {fullfile(getenv('GUROBI_HOME'), 'matlab'), ...
        'D:\gurobi1201\win64\matlab', 'C:\gurobi1201\win64\matlab'}
    if ~isempty(candidate{1}) && isfolder(candidate{1})
        addpath(candidate{1});
    end
end

expectedBranch = "task/002-stage2b-b3-smoke";
expectedHead = "66b7fb305c3b1926d0ab07ac26b6d32dbb6c538d";
assert_git_gate(expectedBranch, expectedHead);
if ~ismember(exist('gurobi', 'file'), [2, 3])
    error('Step-03Z-C requires Gurobi only for the authorized fixed-T recourse LP.');
end

resultRoot = fullfile(rootDir, 'results', 'task-002-stage2b-b3-smoke', ...
    '38-period-ctilde-ground-cost-smoke');
outputDir = fullfile(resultRoot, 'run-002');
tempDir = outputDir + ".tmp";
if isfolder(outputDir)
    error('Step-03Z-C output run-002 already exists.');
end
if isfolder(tempDir)
    rmdir(tempDir, 's');
end
mkdir(tempDir);

config = struct('states', [7, 9, 11, 19], 'R', 2000, ...
    'C_bound', 357.1526447416079, 'kappa', 1, ...
    'weight_D', 0.6, 'weight_Ctilde', 0.4, ...
    'epsDistance', 1e-9, 'scaleTolerance', 1e-12, ...
    'distanceTolerance', 1e-12, 'triangleTolerance', 1e-10, ...
    'lossMismatchThreshold', 0.10, 'maxSelectedPerState', 60, ...
    'batchObjectiveReconstructionTolerance', 1e-6, ...
    'gurobiOutputFlag', 0, 'gurobiFeasibilityTol', 1e-9, ...
    'gurobiOptimalityTol', 1e-9, 'gurobiTimeLimit', 300, ...
    'objectiveScale', 1);

nominalMat = fullfile(moduleDir, 'output', 'stage3j_wdro_input_freeze', ...
    'run-001', 'wdro_nominal_input_DAC.mat');
checkpointDir = fullfile(moduleDir, 'output', ...
    'stage3s_state_distribution_tail_regret_audit', 'run-001', 'checkpoints');
tCsv = fullfile(rootDir, 'results', 'task-002-stage2b-b3-smoke', ...
    '35-period-vs-aggregate-saa-r2000', 'run-001', 'terminalLOH_r2000.csv');
requiredFiles = [string(nominalMat); string(tCsv); ...
    string(fullfile(thisDir, 'step03S_distance_block_h2.m')); ...
    string(fullfile(thisDir, 'recover_step03Y_prefix_entries_h2.m')); ...
    string(fullfile(thisDir, 'evaluate_step03Y_period_fixed_T_recourse_h2.m')); ...
    string(fullfile(moduleDir, 'docs', 'FORMAL_TWO_STAGE_THREE_PERIOD_MODEL.md'))];
for ii = 1:numel(requiredFiles)
    if ~isfile(requiredFiles(ii))
        error('Step-03Z-C required file is missing: %s', requiredFiles(ii));
    end
end

peakMemory = memory_snapshot();
[scaleTbl, scaleRuntime] = recover_frozen_scales(nominalMat, checkpointDir, config);
peakMemory = max(peakMemory, memory_snapshot());
Tperiod = read_period_T(tCsv, config.states, config.R);
fixedTTbl = build_fixed_T_table(config.states, Tperiod);

selectedAll = table();
pairAll = table();
lossAll = table();
analysisAll = table();
metricRows = table();
solverCallCount = 0;
replayMaxError = 0;
aggregateReproError = 0;
periodSumMeanError = 0;
stateRuntime = zeros(numel(config.states), 1);

for ss = 1:numel(config.states)
    stateTic = tic;
    stateId = config.states(ss);
    fprintf('Step-03Z-C state %d: deterministic R=%d replay.\n', stateId, config.R);
    [entry, context] = recover_step03Y_prefix_entries_h2( ...
        rootDir, stateId, config.R, false);
    if ~entry.audit.all_final_DAC_exact || ...
            ~entry.audit.all_stream_hashes_match || height(entry.identity) ~= config.R
        error('Step-03Z-C state %d deterministic replay failed.', stateId);
    end
    replayMaxError = max(replayMaxError, entry.audit.max_DAC_error);
    if any(double(entry.identity.initial_state_id) ~= stateId) || ...
            ~isequal(double(entry.identity.scenario_id), (1:config.R).')
        error('Step-03Z-C state %d identity/order mismatch.', stateId);
    end

    Dscale = scaleTbl.D_scale(scaleTbl.initial_state_id == stateId);
    [scenarioMetrics, selectedIdx] = select_scenarios(entry, config);
    selectedTbl = make_selected_table(entry.identity, scenarioMetrics, ...
        selectedIdx, stateId, Dscale);
    selectedAll = append_table(selectedAll, selectedTbl);

    Dsel = entry.Dperiod(selectedIdx, :, :);
    Asel = entry.Aperiod(selectedIdx, :, :, :);
    Csel = entry.Cperiod(selectedIdx, :, :, :);
    Dagg = entry.Dagg(selectedIdx, :);
    Aagg = entry.Aagg(selectedIdx, :, :);
    Cagg = entry.Cagg(selectedIdx, :, :);
    ids = entry.identity(selectedIdx, :);
    nSel = numel(selectedIdx);

    Tmat = [zeros(1, 4); 150, 100, 50, 75; 300, 200, 100, 150; ...
        Tperiod(stateId == config.states, :)];
    evalScenario = repelem((1:nSel).', 4);
    evalT = repmat((1:4).', nSel, 1);
    evalOut = evaluate_step03Y_period_fixed_T_recourse_h2( ...
        Dsel(evalScenario, :, :), Asel(evalScenario, :, :, :), ...
        Csel(evalScenario, :, :, :), Tmat(evalT, :), context.M, config);
    solverCallCount = solverCallCount + 1;
    if evalOut.status ~= "OPTIMAL" || evalOut.exitflag ~= 1
        error('Step-03Z-C state %d fixed-T recourse is not OPTIMAL.', stateId);
    end
    if evalOut.max_demand_balance_error > 1e-8 || ...
            evalOut.max_site_capacity_violation > 1e-8 || ...
            evalOut.objective_reconstruction_abs_error > ...
            config.batchObjectiveReconstructionTolerance
        error(['Step-03Z-C state %d fixed-T recourse mechanical check failed: ' ...
            'balance=%.17g capacity=%.17g objective_reconstruction=%.17g.'], ...
            stateId, evalOut.max_demand_balance_error, ...
            evalOut.max_site_capacity_violation, ...
            evalOut.objective_reconstruction_abs_error);
    end
    lossMatrix = reshape(evalOut.operating_loss, 4, nSel).';
    lossTbl = make_loss_table(ids, stateId, evalScenario, evalT, evalOut, Tmat);
    lossAll = append_table(lossAll, lossTbl);

    [pairTbl, distanceData, metricTbl, directError, sumMeanError] = ...
        build_state_distances(ids, Dsel, Asel, Csel, Dagg, Aagg, Cagg, ...
        Dscale, stateId, config);
    pairAll = append_table(pairAll, pairTbl);
    metricRows = append_table(metricRows, metricTbl);
    aggregateReproError = max(aggregateReproError, directError);
    periodSumMeanError = max(periodSumMeanError, sumMeanError);
    analysisAll = append_table(analysisAll, make_analysis_rows( ...
        ids, stateId, distanceData, lossMatrix));

    stateRuntime(ss) = toc(stateTic);
    peakMemory = max(peakMemory, memory_snapshot());
    clear entry Dsel Asel Csel Dagg Aagg Cagg evalOut lossMatrix distanceData;
end

[syntheticTbl, syntheticMetricTbl, syntheticSolverCalls, syntheticMaxLossError] = ...
    run_synthetic_cases(context.M, scaleTbl, config);
solverCallCount = solverCallCount + syntheticSolverCalls;
metricRows = append_table(metricRows, syntheticMetricTbl);
peakMemory = max(peakMemory, memory_snapshot());

[byStateTbl, byTTbl, compareTbl, zeroTbl, mismatchTbl] = ...
    summarize_alignment(analysisAll, config);
metricMaxTriangleViolation = max(metricRows.max_triangle_violation);
metricMaxSymmetryError = max(metricRows.max_symmetry_error);
metricMaxDiagonalError = max(metricRows.max_diagonal_error);
periodZero = zeroTbl(zeroTbl.distance_metric == "period", :);
periodZeroLossMax = max([0; periodZero.max_absolute_loss_difference]);

metricPass = metricMaxTriangleViolation <= config.triangleTolerance && ...
    metricMaxSymmetryError <= config.distanceTolerance && ...
    metricMaxDiagonalError <= config.distanceTolerance;
replayPass = replayMaxError == 0;
solverPass = solverCallCount == numel(config.states) + 1 && ...
    all(isfinite(lossAll.operating_loss));
formulaPass = aggregateReproError <= 1e-12 && periodSumMeanError <= 1e-12;
scaleFrozen = false;
if ~(metricPass && replayPass && solverPass && formulaPass)
    decision = "D. GROUND_COST_INVALID_OR_UNRESOLVED";
else
    decision = "C. METRIC_VALID_BUT_SCALE_NOT_FROZEN";
end

writetable(selectedAll, fullfile(tempDir, 'selected_scenarios.csv'));
writetable(fixedTTbl, fullfile(tempDir, 'fixed_T_set.csv'));
writetable(syntheticTbl, fullfile(tempDir, 'synthetic_counterexample_results.csv'));
writetable(pairAll, fullfile(tempDir, 'pairwise_period_distance_components.csv'));
writetable(lossAll, fullfile(tempDir, 'fixed_T_scenario_losses.csv'));
writetable(compareTbl, fullfile(tempDir, 'period_vs_aggregate_distance_summary.csv'));
writetable(byTTbl, fullfile(tempDir, 'distance_loss_alignment_by_T.csv'));
writetable(byStateTbl, fullfile(tempDir, 'distance_loss_alignment_by_state.csv'));
writetable(zeroTbl, fullfile(tempDir, 'zero_distance_audit.csv'));
writetable(mismatchTbl, fullfile(tempDir, 'low_distance_high_loss_mismatch.csv'));

write_definition(fullfile(tempDir, 'recovered_ground_cost_definition.md'), config);
write_scale_audit(fullfile(tempDir, 'scale_provenance_audit.md'), ...
    scaleTbl, scaleRuntime, config);
write_metric_audit(fullfile(tempDir, 'metric_axiom_audit.txt'), ...
    metricRows, metricPass, config);

runtimeSec = toc(runTic);
mechanicalLines = [
    "STEP03ZC_MECHANICAL_AUDIT"
    "status=" + pass_fail(metricPass && replayPass && solverPass && formulaPass)
    "branch=" + expectedBranch
    "frozen_head=" + expectedHead
    "states=7,9,11,19"
    "nominal_prefix_R=2000"
    "selected_scenario_count=" + height(selectedAll)
    "pair_count=" + height(pairAll)
    "fixed_T_evaluation_count=" + height(lossAll)
    "solver_call_count=" + solverCallCount
    "WDRO_call_count=0"
    "MSP_call_count=0"
    "validation_file_count=0"
    "new_T_optimization_count=0"
    "random_scenario_generation_count=0"
    "runner_checkcode_count=0"
    "replay_max_DAC_error=" + sprintf('%.17g', replayMaxError)
    "aggregate_distance_reproduction_max_error=" + sprintf('%.17g', aggregateReproError)
    "period_sum_vs_three_times_mean_max_error=" + sprintf('%.17g', periodSumMeanError)
    "synthetic_objective_reconstruction_error=" + sprintf('%.17g', syntheticMaxLossError)
    "batch_objective_reconstruction_tolerance=" + ...
        sprintf('%.17g', config.batchObjectiveReconstructionTolerance)
    "max_triangle_violation=" + sprintf('%.17g', metricMaxTriangleViolation)
    "max_symmetry_error=" + sprintf('%.17g', metricMaxSymmetryError)
    "max_diagonal_error=" + sprintf('%.17g', metricMaxDiagonalError)
    "period_zero_distance_max_absolute_loss_difference=" + sprintf('%.17g', periodZeroLossMax)
    "D_scale_global_frozen=" + string(scaleFrozen)
    "C_bound_global_frozen=true"
    "standalone_A_component=false"
    "period_alignment=W1-W1,W2-W2,W3-W3"
    "runtime_sec=" + sprintf('%.6f', runtimeSec)
    "peak_working_set_bytes=" + sprintf('%.0f', peakMemory)
    "state_runtime_sec=" + join(compose('%d:%.6f', config.states.', stateRuntime), ';')
    "conclusion=" + decision];
write_lines(fullfile(tempDir, 'mechanical_audit.txt'), mechanicalLines);
write_readme(fullfile(tempDir, 'README.md'), decision, config, ...
    selectedAll, pairAll, lossAll, byTTbl, metricRows, runtimeSec, peakMemory);
write_conclusion(fullfile(tempDir, 'conclusion.txt'), decision, config, ...
    byStateTbl, byTTbl, zeroTbl, metricRows, solverCallCount, runtimeSec, peakMemory);

movefile(tempDir, outputDir);
fprintf('Step-03Z-C completed: %s\n', decision);
fprintf('solver_call_count=%d runtime=%.3f sec peak_memory=%.0f bytes\n', ...
    solverCallCount, runtimeSec, peakMemory);
end

function assert_git_gate(expectedBranch, expectedHead)
[s1, branch] = system('git branch --show-current');
[s2, head] = system('git rev-parse HEAD');
[s3, upstream] = system('git rev-parse @{upstream}');
if s1 ~= 0 || s2 ~= 0 || s3 ~= 0 || ...
        strtrim(string(branch)) ~= expectedBranch || ...
        lower(strtrim(string(head))) ~= expectedHead || ...
        lower(strtrim(string(upstream))) ~= expectedHead
    error('Step-03Z-C frozen branch/HEAD/upstream gate failed.');
end
end

function [tbl, runtime] = recover_frozen_scales(nominalMat, checkpointDir, config)
ticScale = tic;
rows = cell(numel(config.states), 8);
sidecar = matfile(nominalMat);
for ss = 1:numel(config.states)
    stateId = config.states(ss);
    sourceRows = (stateId - 1) * 15000 + (1:15000);
    D = unique(double(sidecar.D_node_kg(sourceRows, :)), 'rows', 'stable');
    Dscale = exact_l1_diameter_unique(D, 250);
    checkpointPath = fullfile(checkpointDir, ...
        sprintf('neighbors_state_%02d.mat', stateId));
    checkpointPresent = isfile(checkpointPath);
    checkpointValue = NaN;
    checkpointError = NaN;
    if checkpointPresent
        frozen = load(checkpointPath, 'Dscale');
        checkpointValue = double(frozen.Dscale);
        checkpointError = abs(checkpointValue - Dscale);
        if checkpointError > 1e-12
            error('Step-03Z-C state %d Dscale differs from Step-03S checkpoint.', stateId);
        end
        provenance = "R15000_EXACT_RECOMPUTE_AND_STEP03S_CHECKPOINT";
    else
        provenance = "R15000_EXACT_RECOMPUTE_SAME_FROZEN_FORMULA";
    end
    rows(ss, :) = {stateId, Dscale, size(D, 1), checkpointPresent, ...
        checkpointValue, checkpointError, provenance, ...
        "state-specific nominal R=15000 exact L1 diameter"};
end
tbl = cell2table(rows, 'VariableNames', {'initial_state_id', 'D_scale', ...
    'unique_D_row_count', 'Step03S_checkpoint_present', ...
    'Step03S_checkpoint_D_scale', 'checkpoint_absolute_error', ...
    'provenance', 'dependency'});
runtime = toc(ticScale);
end

function value = exact_l1_diameter_unique(D, blockSize)
value = 0;
for aa = 1:blockSize:size(D, 1)
    query = D(aa:min(aa + blockSize - 1, size(D, 1)), :);
    for bb = 1:blockSize:size(D, 1)
        target = D(bb:min(bb + blockSize - 1, size(D, 1)), :);
        delta = sum(abs(reshape(query, [size(query, 1), 1, size(D, 2)]) - ...
            reshape(target, [1, size(target, 1), size(D, 2)])), 3);
        value = max(value, max(delta, [], 'all'));
    end
end
end

function Tperiod = read_period_T(path, states, R)
tbl = readtable(path, 'TextType', 'string');
Tperiod = zeros(numel(states), 4);
for ss = 1:numel(states)
    rows = tbl(double(tbl.initial_state_id) == states(ss) & ...
        double(tbl.R) == R, :);
    rows = sortrows(rows, 'site_id');
    if height(rows) ~= 4 || ~isequal(double(rows.site_id), (1:4).') || ...
            any(~isfinite(double(rows.T_period_kg)))
        error('Step-03Z-C cannot recover exact Step-03Y-F period T for state %d.', states(ss));
    end
    Tperiod(ss, :) = double(rows.T_period_kg).';
end
end

function tbl = build_fixed_T_table(states, Tperiod)
names = ["ZERO", "HALF_CAPACITY", "FULL_CAPACITY", "STEP03YF_PERIOD_R2000"];
values = [zeros(1, 4); 150, 100, 50, 75; 300, 200, 100, 150];
rows = cell(3 + numel(states), 7);
for tt = 1:3
    rows(tt, :) = {0, tt, names(tt), values(tt, 1), values(tt, 2), ...
        values(tt, 3), values(tt, 4)};
end
for ss = 1:numel(states)
    rows(3 + ss, :) = {states(ss), 4, names(4), Tperiod(ss, 1), ...
        Tperiod(ss, 2), Tperiod(ss, 3), Tperiod(ss, 4)};
end
tbl = cell2table(rows, 'VariableNames', {'initial_state_id', 'T_id', ...
    'T_label', 'T1_kg', 'T2_kg', 'T3_kg', 'T4_kg'});
end

function [metrics, selected] = select_scenarios(entry, config)
periodDemand = reshape(sum(entry.Dperiod, 3), config.R, 3);
totalDemand = sum(periodDemand, 2);
concentration = zeros(config.R, 1);
positive = totalDemand > 1e-10;
concentration(positive) = max(periodDemand(positive, :), [], 2) ./ totalDemand(positive);
uniformity = inf(config.R, 1);
allPeriodsPositive = all(periodDemand > 1e-10, 2);
uniformity(allPeriodsPositive) = std(periodDemand(allPeriodsPositive, :), 0, 2) ./ ...
    max(mean(periodDemand(allPeriodsPositive, :), 2), 1e-12);
reachChange = reshape(sum(entry.Aperiod(:, 1, :, :) ~= entry.Aperiod(:, 2, :, :), ...
    [3, 4]) + sum(entry.Aperiod(:, 2, :, :) ~= entry.Aperiod(:, 3, :, :), ...
    [3, 4]), config.R, 1);
hidden = entry.Aperiod & ~reshape(entry.Aagg, [config.R, 1, 4, 33]) & ...
    reshape(entry.Dperiod > 1e-10, [config.R, 3, 1, 33]);
hiddenCount = reshape(sum(hidden, [2, 3, 4]), config.R, 1);
scenarioId = double(entry.identity.scenario_id);

positiveValues = totalDemand(positive);
q25 = empirical_quantile(positiveValues, 0.25);
q50 = empirical_quantile(positiveValues, 0.50);
categories = ["ZERO_DEMAND", "LOW_DEMAND", "MEDIUM_DEMAND", ...
    "HIGH_DEMAND", "SINGLE_PERIOD_CONCENTRATED", "THREE_PERIOD_UNIFORM", ...
    "REACHABILITY_CHANGE", "AGGREGATE_SERVICE_DELETION"];
lists = cell(numel(categories), 1);
lists{1} = sort_by_columns(find(~positive), scenarioId(~positive), true);
lists{2} = nearest_target(find(positive), totalDemand, scenarioId, q25);
lists{3} = nearest_target(find(positive), totalDemand, scenarioId, q50);
lists{4} = descending_metric(find(positive), totalDemand, scenarioId);
lists{5} = descending_metric(find(positive), concentration, scenarioId);
lists{6} = ascending_metric(find(allPeriodsPositive), uniformity, scenarioId);
lists{7} = descending_metric(find(reachChange > 0), reachChange, scenarioId);
lists{8} = descending_metric(find(hiddenCount > 0), hiddenCount, scenarioId);
for cc = 1:numel(lists)
    lists{cc} = lists{cc}(1:min(8, numel(lists{cc})));
end

selected = zeros(0, 1);
reason = strings(config.R, 1);
maxRank = max(cellfun(@numel, lists));
for rank = 1:maxRank
    for cc = 1:numel(categories)
        if rank > numel(lists{cc}), continue; end
        idx = lists{cc}(rank);
        if reason(idx) == ""
            reason(idx) = categories(cc);
        elseif ~contains(";" + reason(idx) + ";", ";" + categories(cc) + ";")
            reason(idx) = reason(idx) + ";" + categories(cc);
        end
        if ~ismember(idx, selected) && numel(selected) < config.maxSelectedPerState
            selected(end + 1, 1) = idx; %#ok<AGROW>
        end
    end
    if numel(selected) >= config.maxSelectedPerState, break; end
end
if isempty(selected)
    error('Step-03Z-C deterministic scenario selection returned no rows.');
end
selected = sort(selected);
metrics = table(periodDemand(:, 1), periodDemand(:, 2), periodDemand(:, 3), ...
    totalDemand, concentration, uniformity, reachChange, hiddenCount, reason, ...
    'VariableNames', {'demand_W1_kg', 'demand_W2_kg', 'demand_W3_kg', ...
    'total_demand_kg', 'period_demand_concentration', ...
    'period_demand_uniformity_cv', 'reachability_transition_count', ...
    'aggregate_deleted_service_opportunity_count', 'selection_reason'});
end

function out = sort_by_columns(indices, ids, ascending)
if isempty(indices), out = zeros(0, 1); return; end
if ascending
    [~, order] = sort(ids, 'ascend');
else
    [~, order] = sort(ids, 'descend');
end
out = indices(order);
end

function out = nearest_target(indices, values, ids, target)
if isempty(indices), out = zeros(0, 1); return; end
key = [abs(values(indices) - target), ids(indices)];
[~, order] = sortrows(key, [1, 2]);
out = indices(order);
end

function out = descending_metric(indices, values, ids)
if isempty(indices), out = zeros(0, 1); return; end
key = [-values(indices), ids(indices)];
[~, order] = sortrows(key, [1, 2]);
out = indices(order);
end

function out = ascending_metric(indices, values, ids)
if isempty(indices), out = zeros(0, 1); return; end
key = [values(indices), ids(indices)];
[~, order] = sortrows(key, [1, 2]);
out = indices(order);
end

function value = empirical_quantile(x, probability)
x = sort(double(x(:)));
if isempty(x), value = NaN; return; end
position = 1 + (numel(x) - 1) * probability;
lower = floor(position); upper = ceil(position);
if lower == upper
    value = x(lower);
else
    value = x(lower) + (position - lower) * (x(upper) - x(lower));
end
end

function tbl = make_selected_table(identity, metrics, selected, stateId, Dscale)
id = identity(selected, :);
m = metrics(selected, :);
tbl = table(repmat(stateId, numel(selected), 1), double(id.scenario_id), ...
    double(id.path_id), double(id.joint_stream_position), ...
    double(id.wind_seed), double(id.resistance_seed), ...
    double(id.frozen_nominal_weight), repmat(Dscale, numel(selected), 1), ...
    m.demand_W1_kg, m.demand_W2_kg, m.demand_W3_kg, m.total_demand_kg, ...
    m.period_demand_concentration, m.period_demand_uniformity_cv, ...
    m.reachability_transition_count, ...
    m.aggregate_deleted_service_opportunity_count, m.selection_reason, ...
    'VariableNames', {'initial_state_id', 'sample_id', 'path_id', ...
    'joint_stream_position', 'wind_seed', 'resistance_seed', ...
    'frozen_nominal_weight', 'D_scale', 'demand_W1_kg', 'demand_W2_kg', ...
    'demand_W3_kg', 'total_demand_kg', 'period_demand_concentration', ...
    'period_demand_uniformity_cv', 'reachability_transition_count', ...
    'aggregate_deleted_service_opportunity_count', 'selection_reason'});
end

function tbl = make_loss_table(ids, stateId, evalScenario, evalT, out, Tmat)
n = numel(evalScenario);
labels = ["ZERO", "HALF_CAPACITY", "FULL_CAPACITY", "STEP03YF_PERIOD_R2000"];
tbl = table(repmat(stateId, n, 1), double(ids.scenario_id(evalScenario)), ...
    double(ids.path_id(evalScenario)), evalT, labels(evalT).', ...
    Tmat(evalT, 1), Tmat(evalT, 2), Tmat(evalT, 3), Tmat(evalT, 4), ...
    out.operating_loss, out.service_cost, out.shortage_kg, out.shortage_loss, ...
    out.site_service_total(:, 1), out.site_service_total(:, 2), ...
    out.site_service_total(:, 3), out.site_service_total(:, 4), ...
    repmat(out.runtime_sec, n, 1), repmat(out.max_demand_balance_error, n, 1), ...
    repmat(out.max_site_capacity_violation, n, 1), ...
    'VariableNames', {'initial_state_id', 'sample_id', 'path_id', 'T_id', ...
    'T_label', 'T1_kg', 'T2_kg', 'T3_kg', 'T4_kg', 'operating_loss', ...
    'service_cost', 'shortage_kg', 'shortage_loss', 'site1_service_kg', ...
    'site2_service_kg', 'site3_service_kg', 'site4_service_kg', ...
    'batch_solver_runtime_sec', 'max_demand_balance_error', ...
    'max_site_capacity_violation'});
end

function [tbl, data, metricTbl, directError, sumMeanError] = ...
        build_state_distances(ids, Dperiod, Aperiod, Cperiod, ...
        Dagg, Aagg, Cagg, Dscale, stateId, config)
n = size(Dperiod, 1);
[dAgg, dDAgg, dCAgg, detailAgg] = step03S_distance_block_h2( ...
    Dagg, Aagg, Cagg, Dagg, Aagg, Cagg, Dscale, config);
[dAggManual, ~, ~] = manual_distance_matrix(Dagg, Aagg, Cagg, Dscale, config);
directError = max(abs(dAgg - dAggManual), [], 'all');
dDperiod = zeros(n); dCperiod = zeros(n);
dDstage = zeros(n, n, 3); dCstage = zeros(n, n, 3);
rawDstage = zeros(n, n, 3);
for tau = 1:3
    Dt = reshape(Dperiod(:, tau, :), [n, size(Dperiod, 3)]);
    At = reshape(Aperiod(:, tau, :, :), [n, size(Aperiod, 3), size(Aperiod, 4)]);
    Ct = reshape(Cperiod(:, tau, :, :), [n, size(Cperiod, 3), size(Cperiod, 4)]);
    [~, dDstage(:, :, tau), dCstage(:, :, tau), detail] = ...
        step03S_distance_block_h2(Dt, At, Ct, Dt, At, Ct, Dscale, config);
    rawDstage(:, :, tau) = detail.raw_D_l1;
    dDperiod = dDperiod + dDstage(:, :, tau) / 3;
    dCperiod = dCperiod + dCstage(:, :, tau) / 3;
end
dPeriod = config.weight_D .* dDperiod + config.weight_Ctilde .* dCperiod;
dPeriodSum = 3 .* dPeriod;
sumMeanError = max(abs(dPeriodSum - 3 .* dPeriod), [], 'all');

[ii, jj] = find(triu(true(n), 1));
idx = sub2ind([n, n], ii, jj);
tbl = table(repmat(stateId, numel(ii), 1), double(ids.scenario_id(ii)), ...
    double(ids.path_id(ii)), double(ids.scenario_id(jj)), double(ids.path_id(jj)), ...
    dDAgg(idx), dCAgg(idx), dAgg(idx), detailAgg.raw_D_l1(idx), ...
    rawDstage(sub2ind([n, n, 3], ii, jj, ones(size(ii)))), ...
    rawDstage(sub2ind([n, n, 3], ii, jj, 2 .* ones(size(ii)))), ...
    rawDstage(sub2ind([n, n, 3], ii, jj, 3 .* ones(size(ii)))), ...
    dDstage(sub2ind([n, n, 3], ii, jj, ones(size(ii)))), ...
    dDstage(sub2ind([n, n, 3], ii, jj, 2 .* ones(size(ii)))), ...
    dDstage(sub2ind([n, n, 3], ii, jj, 3 .* ones(size(ii)))), ...
    dCstage(sub2ind([n, n, 3], ii, jj, ones(size(ii)))), ...
    dCstage(sub2ind([n, n, 3], ii, jj, 2 .* ones(size(ii)))), ...
    dCstage(sub2ind([n, n, 3], ii, jj, 3 .* ones(size(ii)))), ...
    dDperiod(idx), dCperiod(idx), dPeriod(idx), dPeriodSum(idx), ...
    'VariableNames', {'initial_state_id', 'sample_id_r', 'path_id_r', ...
    'sample_id_s', 'path_id_s', 'd_D_aggregate', 'd_Ctilde_aggregate', ...
    'd_aggregate', 'raw_D_l1_aggregate_kg', 'raw_D_l1_W1_kg', ...
    'raw_D_l1_W2_kg', 'raw_D_l1_W3_kg', 'd_D_W1', 'd_D_W2', 'd_D_W3', ...
    'd_Ctilde_W1', 'd_Ctilde_W2', 'd_Ctilde_W3', 'd_D_period_mean', ...
    'd_Ctilde_period_mean', 'd_period_mean', 'd_period_sum'});
data = struct('i', ii, 'j', jj, 'd_aggregate', dAgg(idx), ...
    'd_period', dPeriod(idx), 'matrix_aggregate', dAgg, 'matrix_period', dPeriod);
metricTbl = [metric_record("FORMAL_STATE_AGGREGATE", stateId, dAgg, config); ...
    metric_record("FORMAL_STATE_PERIOD", stateId, dPeriod, config)];
end

function [distance, dD, dC] = manual_distance_matrix(D, A, C, Dscale, config)
n = size(D, 1);
dD = zeros(n); dC = zeros(n);
for rr = 1:n
    for ss = rr:n
        raw = sum(abs(double(D(rr, :)) - double(D(ss, :))));
        if Dscale <= config.scaleTolerance, dd = 0; else, dd = raw / (Dscale + config.epsDistance); end
        ar = reshape(A(rr, :, :), [], 1) > 0.5;
        as = reshape(A(ss, :, :), [], 1) > 0.5;
        cr = reshape(C(rr, :, :), [], 1);
        cs = reshape(C(ss, :, :), [], 1);
        local = zeros(numel(ar), 1);
        mismatch = xor(ar, as); both = ar & as;
        local(mismatch) = config.kappa;
        local(both) = abs(cr(both) - cs(both)) / config.C_bound;
        dc = mean(local);
        dD(rr, ss) = dd; dD(ss, rr) = dd;
        dC(rr, ss) = dc; dC(ss, rr) = dc;
    end
end
distance = config.weight_D .* dD + config.weight_Ctilde .* dC;
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
    triangleViolation <= config.triangleTolerance, ...
    'VariableNames', {'audit_scope', 'initial_state_id', 'scenario_count', ...
    'ordered_triple_count', 'max_diagonal_error', 'max_symmetry_error', ...
    'max_nonnegative_violation', 'max_triangle_violation', ...
    'triangle_tolerance', 'passed'});
end

function tbl = make_analysis_rows(ids, stateId, distanceData, lossMatrix)
labels = ["ZERO", "HALF_CAPACITY", "FULL_CAPACITY", "STEP03YF_PERIOD_R2000"];
nPair = numel(distanceData.i);
tbl = table();
for tt = 1:4
    qa = lossMatrix(distanceData.i, tt);
    qb = lossMatrix(distanceData.j, tt);
    absolute = abs(qa - qb);
    relative = absolute ./ max([ones(nPair, 1), abs(qa), abs(qb)], [], 2);
    block = table(repmat(stateId, nPair, 1), ...
        double(ids.scenario_id(distanceData.i)), double(ids.path_id(distanceData.i)), ...
        double(ids.scenario_id(distanceData.j)), double(ids.path_id(distanceData.j)), ...
        repmat(tt, nPair, 1), repmat(labels(tt), nPair, 1), ...
        distanceData.d_aggregate, distanceData.d_period, qa, qb, absolute, relative, ...
        'VariableNames', {'initial_state_id', 'sample_id_r', 'path_id_r', ...
        'sample_id_s', 'path_id_s', 'T_id', 'T_label', 'd_aggregate', ...
        'd_period', 'Q_r', 'Q_s', 'absolute_loss_difference', ...
        'relative_loss_difference'});
    tbl = append_table(tbl, block);
end
end

function [syntheticTbl, metricTbl, calls, maxLossError] = ...
        run_synthetic_cases(M, scaleTbl, config)
[Dr, Ar, Cr, Ds, As, Cs, names] = synthetic_endpoints();
nCase = numel(names); nEndpoint = 2 * nCase;
D = zeros(nEndpoint, 3, 1); A = false(nEndpoint, 3, 4, 1); C = inf(nEndpoint, 3, 4, 1);
for cc = 1:nCase
    D(2 * cc - 1, :, :) = Dr{cc}; D(2 * cc, :, :) = Ds{cc};
    A(2 * cc - 1, :, :, :) = Ar{cc}; A(2 * cc, :, :, :) = As{cc};
    C(2 * cc - 1, :, :, :) = Cr{cc}; C(2 * cc, :, :, :) = Cs{cc};
end
Tmat = [zeros(1, 4); 150, 100, 50, 75; 300, 200, 100, 150; ...
    272.769549682241, 139.377574121048, 90.00900090009, 150];
evalEndpoint = repelem((1:nEndpoint).', 4);
evalT = repmat((1:4).', nEndpoint, 1);
out = evaluate_step03Y_period_fixed_T_recourse_h2(D(evalEndpoint, :, :), ...
    A(evalEndpoint, :, :, :), C(evalEndpoint, :, :, :), Tmat(evalT, :), M, config);
calls = 1;
if out.status ~= "OPTIMAL" || out.exitflag ~= 1
    error('Step-03Z-C synthetic fixed-T recourse failed.');
end
maxLossError = out.objective_reconstruction_abs_error;
loss = reshape(out.operating_loss, 4, nEndpoint).';
Dscale = scaleTbl.D_scale(scaleTbl.initial_state_id == 19);
[distance, dD, dC] = period_distance_matrix(D, A, C, Dscale, config);
metricTbl = metric_record("SYNTHETIC_PERIOD_ENDPOINTS", 0, distance, config);
labels = ["ZERO", "HALF_CAPACITY", "FULL_CAPACITY", "STATE19_PERIOD_R2000"];
rows = cell(nCase * 4, 18);
pos = 0;
for cc = 1:nCase
    r = 2 * cc - 1; s = 2 * cc;
    stageDD = zeros(1, 3); stageDC = zeros(1, 3);
    for tau = 1:3
        [~, stageDD(tau), stageDC(tau)] = step03S_distance_block_h2( ...
            reshape(D(r, tau, :), 1, []), reshape(A(r, tau, :, :), [1, 4, 1]), ...
            reshape(C(r, tau, :, :), [1, 4, 1]), reshape(D(s, tau, :), 1, []), ...
            reshape(A(s, tau, :, :), [1, 4, 1]), reshape(C(s, tau, :, :), [1, 4, 1]), ...
            Dscale, config);
    end
    for tt = 1:4
        pos = pos + 1;
        rows(pos, :) = {cc, names(cc), tt, labels(tt), stageDD(1), stageDD(2), ...
            stageDD(3), stageDC(1), stageDC(2), stageDC(3), dD(r, s), ...
            dC(r, s), distance(r, s), 3 * distance(r, s), loss(r, tt), ...
            loss(s, tt), abs(loss(r, tt) - loss(s, tt)), ...
            synthetic_interpretation(cc, distance(r, s), loss(r, tt), loss(s, tt))};
    end
end
syntheticTbl = cell2table(rows, 'VariableNames', {'case_id', 'case_name', ...
    'T_id', 'T_label', 'd_D_W1', 'd_D_W2', 'd_D_W3', 'd_Ctilde_W1', ...
    'd_Ctilde_W2', 'd_Ctilde_W3', 'd_D_period_mean', ...
    'd_Ctilde_period_mean', 'd_period_mean', 'd_period_sum', ...
    'operating_loss_r', 'operating_loss_s', 'absolute_loss_difference', ...
    'actual_conclusion'});
end

function [distance, dD, dC] = period_distance_matrix(D, A, C, Dscale, config)
n = size(D, 1); dD = zeros(n); dC = zeros(n);
for tau = 1:3
    Dt = reshape(D(:, tau, :), [n, size(D, 3)]);
    At = reshape(A(:, tau, :, :), [n, size(A, 3), size(A, 4)]);
    Ct = reshape(C(:, tau, :, :), [n, size(C, 3), size(C, 4)]);
    [~, dd, dc] = step03S_distance_block_h2(Dt, At, Ct, Dt, At, Ct, Dscale, config);
    dD = dD + dd / 3; dC = dC + dc / 3;
end
distance = config.weight_D .* dD + config.weight_Ctilde .* dC;
end

function [Dr, Ar, Cr, Ds, As, Cs, names] = synthetic_endpoints()
names = ["IDENTICAL", "BOTH_UNREACHABLE_INVALID_C_IGNORED", ...
    "REACHABILITY_MISMATCH", "BOTH_REACHABLE_SAME_C", ...
    "BOTH_REACHABLE_DIFFERENT_C", "PATTERN_110_VS_000", ...
    "PATTERN_110_VS_101", "PATTERN_110_VS_011", ...
    "SAME_TOTAL_DEMAND_333_VS_900", "HIGH_DEMAND_REACHABLE_VS_UNREACHABLE", ...
    "WHOLE_PERIOD_BLOCK_SWAP", "D_ONLY_PERIOD_SWAP"];
Dr = cell(12, 1); Ar = cell(12, 1); Cr = cell(12, 1);
Ds = cell(12, 1); As = cell(12, 1); Cs = cell(12, 1);
baseD = reshape([10, 20, 30], [1, 3, 1]);
baseA = false(1, 3, 4, 1); baseA(1, :, 1, 1) = true;
baseC = inf(1, 3, 4, 1); baseC(1, :, 1, 1) = reshape([10, 20, 30], [1, 3, 1, 1]);
for cc = 1:12
    Dr{cc} = baseD; Ds{cc} = baseD; Ar{cc} = baseA; As{cc} = baseA;
    Cr{cc} = baseC; Cs{cc} = baseC;
end
Ar{2}(:) = false; As{2}(:) = false; Cr{2}(:) = Inf; Cs{2}(:) = 999;
As{3}(1, 2, 1, 1) = false; Cs{3}(1, 2, 1, 1) = Inf;
Cs{5}(1, 2, 1, 1) = 80;
[Ar{6}, Cr{6}] = pattern_scene([1, 1, 0], [10, 20, 30]);
[As{6}, Cs{6}] = pattern_scene([0, 0, 0], [10, 20, 30]);
[Ar{7}, Cr{7}] = pattern_scene([1, 1, 0], [10, 20, 30]);
[As{7}, Cs{7}] = pattern_scene([1, 0, 1], [10, 20, 30]);
[Ar{8}, Cr{8}] = pattern_scene([1, 1, 0], [10, 20, 30]);
[As{8}, Cs{8}] = pattern_scene([0, 1, 1], [10, 20, 30]);
Dr{9} = reshape([30, 30, 30], [1, 3, 1]); Ds{9} = reshape([90, 0, 0], [1, 3, 1]);
Dr{10} = reshape([90, 0, 0], [1, 3, 1]); Ds{10} = reshape([0, 0, 90], [1, 3, 1]);
[Ar{10}, Cr{10}] = pattern_scene([1, 0, 0], [10, 20, 30]);
[As{10}, Cs{10}] = pattern_scene([0, 0, 0], [10, 20, 30]);
Ds{11} = Dr{11}(:, [2, 1, 3], :); As{11} = Ar{11}(:, [2, 1, 3], :, :); Cs{11} = Cr{11}(:, [2, 1, 3], :, :);
Ds{12} = Dr{12}(:, [2, 1, 3], :);
end

function [A, C] = pattern_scene(pattern, costs)
A = false(1, 3, 4, 1); C = inf(1, 3, 4, 1);
for tau = 1:3
    if pattern(tau)
        A(1, tau, 1, 1) = true; C(1, tau, 1, 1) = costs(tau);
    end
end
end

function text = synthetic_interpretation(caseId, distance, q1, q2)
if caseId == 1
    text = "identical effective scenarios have zero distance and equal loss";
elseif caseId == 2
    text = "unreachable C payload is ignored by both distance and recourse";
elseif distance <= 1e-12
    text = "zero effective distance; loss difference=" + sprintf('%.6g', abs(q1 - q2));
else
    text = "fixed W1/W2/W3 comparison gives positive distance; loss difference=" + ...
        sprintf('%.6g', abs(q1 - q2));
end
end

function [byState, byT, compare, zeroTbl, mismatchTbl] = summarize_alignment(data, config)
states = unique(data.initial_state_id).'; Tids = unique(data.T_id).';
metrics = ["aggregate", "period"];
byState = table(); byT = table(); zeroTbl = table(); mismatchTbl = table();
for stateId = states
    for tt = Tids
        block = data(data.initial_state_id == stateId & data.T_id == tt, :);
        for metric = metrics
            [summary, zeroRow, mismatch] = summarize_block(block, metric, ...
                "STATE", stateId, config);
            byState = append_table(byState, summary);
            zeroTbl = append_table(zeroTbl, zeroRow);
            mismatchTbl = append_table(mismatchTbl, mismatch);
        end
    end
end
for tt = Tids
    block = data(data.T_id == tt, :);
    for metric = metrics
        [summary, zeroRow, mismatch] = summarize_block(block, metric, ...
            "POOLED", 0, config);
        byT = append_table(byT, summary);
        zeroTbl = append_table(zeroTbl, zeroRow);
        mismatchTbl = append_table(mismatchTbl, mismatch);
    end
end
compare = table();
scopes = ["POOLED", "STATE"];
for scope = scopes
    source = byT;
    if scope == "STATE", source = byState; end
    keys = unique(source(:, {'scope', 'initial_state_id', 'T_id', 'T_label'}), 'rows');
    for kk = 1:height(keys)
        rows = source(source.scope == keys.scope(kk) & ...
            source.initial_state_id == keys.initial_state_id(kk) & ...
            source.T_id == keys.T_id(kk), :);
        agg = rows(rows.distance_metric == "aggregate", :);
        per = rows(rows.distance_metric == "period", :);
        if height(agg) ~= 1 || height(per) ~= 1, continue; end
        row = table(keys.scope(kk), keys.initial_state_id(kk), keys.T_id(kk), ...
            keys.T_label(kk), agg.pair_count, agg.spearman_distance_abs_loss, ...
            per.spearman_distance_abs_loss, ...
            per.spearman_distance_abs_loss - agg.spearman_distance_abs_loss, ...
            agg.low_positive_large_mismatch_count, per.low_positive_large_mismatch_count, ...
            agg.low_positive_large_mismatch_share, per.low_positive_large_mismatch_share, ...
            per.low_positive_large_mismatch_share - agg.low_positive_large_mismatch_share, ...
            agg.loss_slope_q90, per.loss_slope_q90, ...
            agg.nearest_neighbor_relative_loss_median, ...
            per.nearest_neighbor_relative_loss_median, ...
            'VariableNames', {'scope', 'initial_state_id', 'T_id', 'T_label', ...
            'pair_count', 'aggregate_spearman', 'period_spearman', ...
            'period_minus_aggregate_spearman', 'aggregate_low_mismatch_count', ...
            'period_low_mismatch_count', 'aggregate_low_mismatch_share', ...
            'period_low_mismatch_share', 'period_minus_aggregate_low_mismatch_share', ...
            'aggregate_loss_slope_q90', 'period_loss_slope_q90', ...
            'aggregate_nearest_relative_loss_median', ...
            'period_nearest_relative_loss_median'});
        compare = append_table(compare, row);
    end
end
end

function [summary, zeroRow, mismatch] = summarize_block(block, metric, scope, stateId, config)
distance = block.("d_" + metric);
absolute = block.absolute_loss_difference;
relative = block.relative_loss_difference;
positive = distance > config.distanceTolerance;
zero = ~positive;
lowThreshold = empirical_quantile(distance(positive), 0.25);
low = positive & distance <= lowThreshold + 1e-15;
large = relative >= config.lossMismatchThreshold;
slope = absolute(positive) ./ distance(positive);
rho = spearman_rank(distance, absolute);
nearest = nearest_pair_mask(block, distance);
summary = table(string(scope), stateId, block.T_id(1), block.T_label(1), ...
    string(metric), height(block), sum(zero), sum(positive), rho, lowThreshold, ...
    sum(low), sum(low & large), safe_ratio(sum(low & large), sum(low)), ...
    vector_quantile(slope, 0.50), vector_quantile(slope, 0.90), ...
    vector_quantile(slope, 1.00), sum(nearest), ...
    vector_quantile(relative(nearest), 0.50), vector_quantile(relative(nearest), 0.90), ...
    max([0; relative(nearest)]), ...
    'VariableNames', {'scope', 'initial_state_id', 'T_id', 'T_label', ...
    'distance_metric', 'pair_count', 'zero_distance_pair_count', ...
    'positive_distance_pair_count', 'spearman_distance_abs_loss', ...
    'low_positive_distance_q25', 'low_positive_pair_count', ...
    'low_positive_large_mismatch_count', 'low_positive_large_mismatch_share', ...
    'loss_slope_median', 'loss_slope_q90', 'loss_slope_maximum', ...
    'nearest_neighbor_pair_count', 'nearest_neighbor_relative_loss_median', ...
    'nearest_neighbor_relative_loss_q90', 'nearest_neighbor_relative_loss_maximum'});
zeroRow = table(string(scope), stateId, block.T_id(1), block.T_label(1), ...
    string(metric), sum(zero), max([0; absolute(zero)]), max([0; relative(zero)]), ...
    'VariableNames', {'scope', 'initial_state_id', 'T_id', 'T_label', ...
    'distance_metric', 'zero_distance_pair_count', ...
    'max_absolute_loss_difference', 'max_relative_loss_difference'});

candidate = block(low & large, :);
if isempty(candidate)
    mismatch = empty_mismatch_table();
else
    candidate.distance_metric = repmat(string(metric), height(candidate), 1);
    candidate.distance = candidate.("d_" + metric);
    candidate.low_positive_distance_q25 = repmat(lowThreshold, height(candidate), 1);
    candidate.loss_slope = candidate.absolute_loss_difference ./ candidate.distance;
    candidate = sortrows(candidate, {'relative_loss_difference', 'distance'}, {'descend', 'ascend'});
    candidate = candidate(1:min(20, height(candidate)), :);
    mismatch = candidate(:, {'initial_state_id', 'sample_id_r', 'path_id_r', ...
        'sample_id_s', 'path_id_s', 'T_id', 'T_label', 'distance_metric', ...
        'distance', 'low_positive_distance_q25', 'Q_r', 'Q_s', ...
        'absolute_loss_difference', 'relative_loss_difference', 'loss_slope'});
    mismatch.scope = repmat(string(scope), height(mismatch), 1);
    mismatch = movevars(mismatch, 'scope', 'Before', 1);
end
end

function mask = nearest_pair_mask(block, distance)
samples = unique([block.sample_id_r; block.sample_id_s]);
mask = false(height(block), 1);
for sample = samples.'
    incident = block.sample_id_r == sample | block.sample_id_s == sample;
    values = distance; values(~incident) = Inf;
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

function rho = spearman_rank(x, y)
if numel(x) < 2 || all(x == x(1)) || all(y == y(1))
    rho = NaN; return;
end
rho = corr(average_rank(x), average_rank(y));
end

function ranks = average_rank(x)
[sorted, order] = sort(x(:)); ranks = zeros(size(sorted));
start = 1;
while start <= numel(sorted)
    stop = start;
    while stop < numel(sorted) && sorted(stop + 1) == sorted(start)
        stop = stop + 1;
    end
    ranks(start:stop) = (start + stop) / 2;
    start = stop + 1;
end
inverse = zeros(size(order)); inverse(order) = 1:numel(order);
ranks = ranks(inverse);
end

function value = vector_quantile(x, probability)
if isempty(x), value = NaN; else, value = empirical_quantile(x, probability); end
end

function value = safe_ratio(a, b)
if b == 0, value = NaN; else, value = a / b; end
end

function write_definition(path, config)
lines = [
    "# Recovered D + Ctilde Ground Cost Definition"
    ""
    "Authoritative implementation: `terminalLoh_wdro/src/step03S_distance_block_h2.m`."
    ""
    "## Frozen aggregate definition"
    ""
    "For scenarios r and s, `rawD=sum_n abs(D_r(n)-D_s(n))`. If the state D scale is at most 1e-12, `d_D=0`; otherwise `d_D=rawD/(Dscale+1e-9)`."
    ""
    "For every one of the 4 x 33 site-node relations, Ctilde uses:"
    "- both unreachable: local distance 0; invalid C payloads are ignored"
    "- exactly one reachable: local distance kappa=1"
    "- both reachable: local distance abs(C_r-C_s)/C_bound"
    ""
    "The 132 local values are averaged. `C_bound=" + sprintf('%.16g', config.C_bound) + " km`, `d_new=0.6*d_D+0.4*d_Ctilde`. There is no standalone A component and no truncation."
    ""
    "## Three-period extension audited here"
    ""
    "W1 is compared only with W1, W2 only with W2, and W3 only with W3. Each period uses the frozen aggregate formula and the same state Dscale. The official audit convention is the arithmetic mean of the three period components:"
    ""
    "`d_D_period=(d_D_W1+d_D_W2+d_D_W3)/3`"
    ""
    "`d_Ctilde_period=(d_Ctilde_W1+d_Ctilde_W2+d_Ctilde_W3)/3`"
    ""
    "`d_period=0.6*d_D_period+0.4*d_Ctilde_period`."
    ""
    "Using the sum instead of the mean produces exactly `3*d_period`, so rankings are identical. The mean is used to avoid an unintended threefold scale expansion."];
write_lines(path, lines);
end

function write_scale_audit(path, scaleTbl, runtime, config)
lines = [
    "# Scale Provenance Audit"
    ""
    "`C_bound=" + sprintf('%.16g', config.C_bound) + " km` is global and deterministic: Step-03Q derives it as twice the sum of all road-edge lengths, using the frozen maximum slowdown multiplier 2. It does not depend on state, R, or the selected audit scenarios."
    ""
    "Dscale is not global. Step-03S defines it independently for each initial state as the exact L1 diameter of all 15000 nominal aggregate D rows. Consequently it is state-specific and nominal-sample-specific. It does not change when this audit uses R=2000 because the R=15000 value is reused literally, but it is not a universally frozen ground-cost scale."
    ""
    "The exact scan removes duplicate D rows before blockwise comparison; this is algebraically identical to scanning all 15000 x 15000 pairs. Only the maximum is retained."
    ""
    "| state | Dscale | unique D rows | Step-03S checkpoint | provenance |"
    "|---:|---:|---:|:---:|---|"];
for rr = 1:height(scaleTbl)
    lines(end + 1) = "| " + scaleTbl.initial_state_id(rr) + " | " + ...
        sprintf('%.17g', scaleTbl.D_scale(rr)) + " | " + ...
        scaleTbl.unique_D_row_count(rr) + " | " + ...
        string(scaleTbl.Step03S_checkpoint_present(rr)) + " | " + ...
        scaleTbl.provenance(rr) + " |"; %#ok<AGROW>
end
lines = [lines; ""; "scale_recovery_runtime_sec=" + sprintf('%.6f', runtime); ...
    "classification_effect=METRIC_VALID_BUT_SCALE_NOT_FROZEN if all other checks pass"];
write_lines(path, lines);
end

function write_metric_audit(path, metricRows, pass, config)
lines = [
    "STEP03ZC_METRIC_AXIOM_AUDIT"
    "analytic_nonnegativity=PASS; all local terms and weights are nonnegative"
    "analytic_symmetry=PASS; absolute differences and reachability XOR are symmetric"
    "analytic_identity=PASS_ON_EFFECTIVE_SCENARIO; unreachable C payload is outside the effective representation"
    "analytic_distinguishability=PASS; a different D or effective reachability-aware Ctilde coordinate gives positive distance"
    "analytic_triangle=PASS; D is scaled L1 and each local Ctilde coordinate is a metric on {unreachable} union reachable normalized C"
    "reachability_jump_compatibility=PASS; reachable-reachable distance <=1 because reachable C is in [0,C_bound], matching kappa=1"
    "period_extension=PASS; a positive weighted mean over fixed W1/W2/W3 coordinates preserves the metric"
    "triangle_tolerance=" + sprintf('%.17g', config.triangleTolerance)
    "program_audit_status=" + pass_fail(pass)];
for rr = 1:height(metricRows)
    lines(end + 1) = join([metricRows.audit_scope(rr), ...
        "state=" + metricRows.initial_state_id(rr), ...
        "n=" + metricRows.scenario_count(rr), ...
        "triples=" + metricRows.ordered_triple_count(rr), ...
        "diag=" + sprintf('%.17g', metricRows.max_diagonal_error(rr)), ...
        "sym=" + sprintf('%.17g', metricRows.max_symmetry_error(rr)), ...
        "triangle=" + sprintf('%.17g', metricRows.max_triangle_violation(rr)), ...
        "pass=" + string(metricRows.passed(rr))], ","); %#ok<AGROW>
end
write_lines(path, lines);
end

function write_readme(path, decision, config, selected, pairs, losses, byT, metricRows, runtime, peak)
periodRows = byT(byT.distance_metric == "period", :);
aggregateRows = byT(byT.distance_metric == "aggregate", :);
improvedMismatch = sum(periodRows.low_positive_large_mismatch_share < ...
    aggregateRows.low_positive_large_mismatch_share);
improvedSpearman = sum(periodRows.spearman_distance_abs_loss > ...
    aggregateRows.spearman_distance_abs_loss);
lines = [
    "# Step-03Z-C Three-Period D + Ctilde Ground-Cost Smoke Audit"
    ""
    "Conclusion: **" + decision + "**"
    ""
    "This independent audit extends the frozen aggregate `0.6*d_D+0.4*d_Ctilde` formula by comparing W1-W1, W2-W2, and W3-W3 and averaging the three period components. It does not run WDRO/MSP, optimize TerminalLOH, read validation, add A, tune rho, or scan weights."
    ""
    "- states: " + join(string(config.states), ", ")
    "- nominal prefix per state: R=" + config.R
    "- selected scenarios: " + height(selected)
    "- selected unordered pairs: " + height(pairs)
    "- fixed-T scenario evaluations: " + height(losses)
    "- pooled fixed-T rows with fewer low-distance mismatches under period distance: " + improvedMismatch + "/4"
    "- pooled fixed-T rows with higher Spearman correlation under period distance: " + improvedSpearman + "/4"
    "- maximum program triangle violation: " + sprintf('%.17g', max(metricRows.max_triangle_violation))
    "- runtime_sec: " + sprintf('%.6f', runtime)
    "- peak_working_set_bytes: " + sprintf('%.0f', peak)
    ""
    "The metric audit passes on the effective scenario representation. Formal expansion is nevertheless blocked because Dscale remains state-specific and derived from each state's nominal R=15000 sample maximum."];
categories = ["ZERO_DEMAND", "LOW_DEMAND", "MEDIUM_DEMAND", ...
    "HIGH_DEMAND", "SINGLE_PERIOD_CONCENTRATED", "THREE_PERIOD_UNIFORM", ...
    "REACHABILITY_CHANGE", "AGGREGATE_SERVICE_DELETION"];
lines = [lines; ""; "## Deterministic Selection Coverage"; ""];
for stateId = config.states
    stateRows = selected(selected.initial_state_id == stateId, :);
    lines(end + 1) = "state " + stateId + ": selected=" + height(stateRows); %#ok<AGROW>
    for category = categories
        count = sum(contains(";" + stateRows.selection_reason + ";", ...
            ";" + category + ";"));
        lines(end + 1) = "- " + category + ": " + count; %#ok<AGROW>
    end
end
write_lines(path, lines);
end

function write_conclusion(path, decision, config, byState, byT, zeroTbl, metricRows, calls, runtime, peak)
periodT = byT(byT.distance_metric == "period", :);
aggregateT = byT(byT.distance_metric == "aggregate", :);
lines = [
    "conclusion=" + decision
    "formula=d_period=0.6*mean_tau(d_D_tau)+0.4*mean_tau(d_Ctilde_tau)"
    "Ctilde_both_unreachable=0"
    "Ctilde_reachability_mismatch=1"
    "Ctilde_both_reachable=abs(C1-C2)/357.1526447416079"
    "standalone_A_component=false"
    "period_alignment=W1-W1,W2-W2,W3-W3"
    "D_scale=state-specific exact nominal R15000 aggregate-D L1 diameter"
    "C_bound=global deterministic road-network bound"
    "triangle_inequality_pass=" + string(all(metricRows.passed))
    "max_triangle_violation=" + sprintf('%.17g', max(metricRows.max_triangle_violation))
    "solver_call_count=" + calls
    "WDRO_call_count=0"
    "MSP_call_count=0"
    "validation_file_count=0"
    "runtime_sec=" + sprintf('%.6f', runtime)
    "peak_working_set_bytes=" + sprintf('%.0f', peak)];
for tt = 1:4
    a = aggregateT(aggregateT.T_id == tt, :); p = periodT(periodT.T_id == tt, :);
    lines(end + 1) = "T=" + p.T_label + ...
        ",aggregate_spearman=" + sprintf('%.6g', a.spearman_distance_abs_loss) + ...
        ",period_spearman=" + sprintf('%.6g', p.spearman_distance_abs_loss) + ...
        ",aggregate_low_mismatch_share=" + sprintf('%.6g', a.low_positive_large_mismatch_share) + ...
        ",period_low_mismatch_share=" + sprintf('%.6g', p.low_positive_large_mismatch_share); %#ok<AGROW>
end
periodZero = zeroTbl(zeroTbl.distance_metric == "period", :);
lines(end + 1) = "period_zero_distance_pair_rows=" + sum(periodZero.zero_distance_pair_count);
lines(end + 1) = "period_zero_distance_max_absolute_loss_difference=" + ...
    sprintf('%.17g', max([0; periodZero.max_absolute_loss_difference]));
for stateId = config.states
    rows = byState(byState.initial_state_id == stateId & byState.distance_metric == "period", :);
    lines(end + 1) = "state=" + stateId + ...
        ",period_spearman_range=[" + sprintf('%.6g', min(rows.spearman_distance_abs_loss)) + ...
        "," + sprintf('%.6g', max(rows.spearman_distance_abs_loss)) + "]" + ...
        ",low_mismatch_share_range=[" + sprintf('%.6g', min(rows.low_positive_large_mismatch_share)) + ...
        "," + sprintf('%.6g', max(rows.low_positive_large_mismatch_share)) + "]"; %#ok<AGROW>
end
lines = [lines; ...
    "interpretation=The three-period representation can improve some fixed-loss diagnostics, but this task cannot freeze or expand the ground cost while Dscale remains state/sample dependent."; ...
    "next_gate=Freeze a state-independent D scale in a separately authorized task before any expanded audit or WDRO use."];
write_lines(path, lines);
end

function out = append_table(current, block)
if isempty(current), out = block; else, out = [current; block]; end
end

function value = pass_fail(flag)
if flag, value = "PASS"; else, value = "FAIL"; end
end

function write_lines(path, lines)
fid = fopen(path, 'w');
if fid < 0, error('Cannot open output file: %s', path); end
cleanup = onCleanup(@() fclose(fid));
for ii = 1:numel(lines), fprintf(fid, '%s\n', lines(ii)); end
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
