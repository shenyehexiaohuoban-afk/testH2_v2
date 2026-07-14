function audit = independent_recheck_foundation_D_Hres3h_h2( ...
    sliceFile, summaryFile, tolerance)
%INDEPENDENT_RECHECK_FOUNDATION_D_HRES3H_H2 Recompute totals from CSV.

if nargin < 3 || isempty(tolerance)
    tolerance = 1e-9;
end
if ~isfile(sliceFile) || ~isfile(summaryFile)
    error('independent_recheck_foundation_D_Hres3h_h2:MissingInput', ...
        'Both slice and summary CSV files are required.');
end

T = readtable(sliceFile, 'TextType', 'string');
S = readtable(summaryFile, 'TextType', 'string');
sliceVars = {'Rmax', 'Wstep', 'a', 'loc', 'mc_id', 'stage', ...
    'included_in_Hres3h', 'D_slice_total_kg', 'slice_duration_h'};
summaryVars = {'Rmax', 'Wstep', 'a', 'loc', 'D_total_mean_kg', ...
    'D_total_p50_kg', 'D_total_p90_kg', 'D_total_p95_kg', ...
    'D_total_max_kg', 'Hres_total_h'};
require_vars(T, sliceVars, 'foundation_fix_D_by_slice.csv');
require_vars(S, summaryVars, 'foundation_fix_D_Hres3h_summary.csv');

stage = string(T.stage);
[G, keyTbl] = findgroups(T(:, {'Rmax', 'Wstep', 'a', 'loc', 'mc_id'}));
w1Count = splitapply(@(x) sum(x == "W1"), stage, G);
w2Count = splitapply(@(x) sum(x == "W2"), stage, G);
w3Count = splitapply(@(x) sum(x == "W3"), stage, G);
lf7Count = splitapply(@(x) sum(x == "lf7"), stage, G);
dW1 = splitapply(@sum_stage, T.D_slice_total_kg, stage, ...
    repmat("W1", height(T), 1), G);
dW2 = splitapply(@sum_stage, T.D_slice_total_kg, stage, ...
    repmat("W2", height(T), 1), G);
dW3 = splitapply(@sum_stage, T.D_slice_total_kg, stage, ...
    repmat("W3", height(T), 1), G);
lf7Excluded = splitapply(@check_lf7_excluded, stage, ...
    T.included_in_Hres3h, T.D_slice_total_kg, G);
durationPass = splitapply(@check_duration, stage, ...
    T.included_in_Hres3h, T.slice_duration_h, G);

scenarioTbl = keyTbl;
scenarioTbl.Properties.VariableNames{'mc_id'} = 'scenario_id';
scenarioTbl.D_W1_recomputed_kg = dW1;
scenarioTbl.D_W2_recomputed_kg = dW2;
scenarioTbl.D_W3_recomputed_kg = dW3;
scenarioTbl.D_total_recomputed_kg = dW1 + dW2 + dW3;
scenarioTbl.W1_row_count = w1Count;
scenarioTbl.W2_row_count = w2Count;
scenarioTbl.W3_row_count = w3Count;
scenarioTbl.lf7_row_count = lf7Count;
scenarioTbl.exact_W1_W2_W3_pass = ...
    w1Count == 1 & w2Count == 1 & w3Count == 1;
scenarioTbl.no_duplicate_stage_pass = ...
    w1Count <= 1 & w2Count <= 1 & w3Count <= 1 & lf7Count <= 1;
scenarioTbl.lf7_excluded_pass = lf7Excluded;
scenarioTbl.slice_duration_1h_pass = durationPass;

[G2, groupKeys] = findgroups(scenarioTbl(:, {'Rmax', 'Wstep', 'a', 'loc'}));
groupCheck = groupKeys;
groupCheck.scenario_count = splitapply(@numel, ...
    scenarioTbl.D_total_recomputed_kg, G2);
groupCheck.recomputed_D_total_mean_kg = splitapply(@mean, ...
    scenarioTbl.D_total_recomputed_kg, G2);
groupCheck.recomputed_D_total_p50_kg = splitapply(@(x) pct(x, 50), ...
    scenarioTbl.D_total_recomputed_kg, G2);
groupCheck.recomputed_D_total_p90_kg = splitapply(@(x) pct(x, 90), ...
    scenarioTbl.D_total_recomputed_kg, G2);
groupCheck.recomputed_D_total_p95_kg = splitapply(@(x) pct(x, 95), ...
    scenarioTbl.D_total_recomputed_kg, G2);
groupCheck.recomputed_D_total_max_kg = splitapply(@max, ...
    scenarioTbl.D_total_recomputed_kg, G2);
groupCheck.all_exact_W123_pass = splitapply(@all, ...
    scenarioTbl.exact_W1_W2_W3_pass, G2);
groupCheck.all_no_duplicate_stage_pass = splitapply(@all, ...
    scenarioTbl.no_duplicate_stage_pass, G2);
groupCheck.all_lf7_excluded_pass = splitapply(@all, ...
    scenarioTbl.lf7_excluded_pass, G2);
groupCheck.all_slice_duration_1h_pass = splitapply(@all, ...
    scenarioTbl.slice_duration_1h_pass, G2);

reported = S(:, summaryVars);
reported.Properties.VariableNames = {'Rmax', 'Wstep', 'a', 'loc', ...
    'reported_D_total_mean_kg', 'reported_D_total_p50_kg', ...
    'reported_D_total_p90_kg', 'reported_D_total_p95_kg', ...
    'reported_D_total_max_kg', 'reported_Hres_total_h'};
groupCheck = innerjoin(groupCheck, reported, ...
    'Keys', {'Rmax', 'Wstep', 'a', 'loc'});
if height(groupCheck) ~= height(S)
    error('independent_recheck_foundation_D_Hres3h_h2:GroupMismatch', ...
        'Independent groups do not match reported summary rows.');
end

groupCheck.mean_abs_error = abs(groupCheck.recomputed_D_total_mean_kg - ...
    groupCheck.reported_D_total_mean_kg);
groupCheck.p50_abs_error = abs(groupCheck.recomputed_D_total_p50_kg - ...
    groupCheck.reported_D_total_p50_kg);
groupCheck.p90_abs_error = abs(groupCheck.recomputed_D_total_p90_kg - ...
    groupCheck.reported_D_total_p90_kg);
groupCheck.p95_abs_error = abs(groupCheck.recomputed_D_total_p95_kg - ...
    groupCheck.reported_D_total_p95_kg);
groupCheck.max_abs_error = abs(groupCheck.recomputed_D_total_max_kg - ...
    groupCheck.reported_D_total_max_kg);
groupCheck.reported_vs_recomputed_pass = ...
    groupCheck.mean_abs_error <= tolerance & ...
    groupCheck.p50_abs_error <= tolerance & ...
    groupCheck.p90_abs_error <= tolerance & ...
    groupCheck.p95_abs_error <= tolerance & ...
    groupCheck.max_abs_error <= tolerance;
groupCheck.Hres_total_3h_pass = ...
    abs(groupCheck.reported_Hres_total_h - 3) <= tolerance;
groupCheck.reported_schema_note = repmat( ...
    "per-scenario D_Hres3h_total_kg absent; aggregate mean/p50/p90/p95/max independently checked", ...
    height(groupCheck), 1);

scenarioTbl = innerjoin(scenarioTbl, groupCheck, ...
    'Keys', {'Rmax', 'Wstep', 'a', 'loc'});
scenarioTbl.source_scenario_id_column = repmat("mc_id", height(scenarioTbl), 1);

audit = struct();
audit.scenario_table = scenarioTbl;
audit.group_table = groupCheck;
audit.scenario_count = height(scenarioTbl);
audit.group_count = height(groupCheck);
audit.exact_W123_pass = all(scenarioTbl.exact_W1_W2_W3_pass);
audit.no_duplicate_stage_pass = all(scenarioTbl.no_duplicate_stage_pass);
audit.lf7_excluded_pass = all(scenarioTbl.lf7_excluded_pass);
audit.slice_duration_1h_pass = all(scenarioTbl.slice_duration_1h_pass);
audit.Hres_total_3h_pass = all(groupCheck.Hres_total_3h_pass);
audit.reported_vs_recomputed_pass = ...
    all(groupCheck.reported_vs_recomputed_pass);
audit.max_reported_abs_error = max([groupCheck.mean_abs_error; ...
    groupCheck.p50_abs_error; groupCheck.p90_abs_error; ...
    groupCheck.p95_abs_error; groupCheck.max_abs_error]);
audit.tolerance = tolerance;
audit.per_scenario_reported_total_available = ...
    ismember('D_Hres3h_total_kg', S.Properties.VariableNames);
audit.schema_warning = ...
    "manual verification required only for absent per-scenario reported total; available aggregate metrics were automatically verified";
end

function value = sum_stage(d, stage, target)
value = sum(d(stage == target(1)));
end

function tf = check_lf7_excluded(stage, included, d)
rows = stage == "lf7";
tf = sum(rows) == 1 && all(included(rows) == 0) && all(abs(d(rows)) <= 1e-12);
end

function tf = check_duration(stage, included, duration)
includedRows = stage == "W1" | stage == "W2" | stage == "W3";
lf7Rows = stage == "lf7";
tf = all(included(includedRows) == 1) && ...
    all(abs(duration(includedRows) - 1) <= 1e-12) && ...
    all(included(lf7Rows) == 0) && all(abs(duration(lf7Rows)) <= 1e-12);
end

function require_vars(T, names, fileName)
for ii = 1:numel(names)
    if ~ismember(names{ii}, T.Properties.VariableNames)
        error('independent_recheck_foundation_D_Hres3h_h2:MissingColumn', ...
            '%s is missing column %s.', fileName, names{ii});
    end
end
end

function value = pct(x, p)
x = sort(double(x(:)));
x = x(isfinite(x));
if isempty(x)
    value = NaN;
else
    idx = max(1, min(numel(x), ceil(p / 100 * numel(x))));
    value = x(idx);
end
end
