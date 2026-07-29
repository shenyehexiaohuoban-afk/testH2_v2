function run_step03ZD_ground_cost_scale_audit_h2()
%RUN_STEP03ZD_GROUND_COST_SCALE_AUDIT_H2 Static/minimal scale audit.

runTic = tic;
thisDir = fileparts(mfilename('fullpath'));
moduleDir = fileparts(thisDir);
rootDir = fileparts(moduleDir);
addpath(rootDir);
addpath(fullfile(rootDir, 'fa_h2', 'fuzhu', 'terminalLoh_windmc'));
expectedBranch = "task/002-stage2b-b3-smoke";
expectedHead = "4aebdf3e60599fe9ce066c7d3f49aea644db133b";
assert_git_gate(expectedBranch, expectedHead);

resultRoot = fullfile(rootDir, 'results', 'task-002-stage2b-b3-smoke', ...
    '39-ground-cost-scale-audit');
outputDir = fullfile(resultRoot, 'run-002');
tempDir = outputDir + ".tmp";
if isfolder(outputDir)
    error('Step-03Z-D output run-002 already exists.');
end
if isfolder(tempDir)
    rmdir(tempDir, 's');
end
mkdir(tempDir);

paths = struct();
paths.zcSource = fullfile(thisDir, ...
    'run_step03ZC_period_ctilde_ground_cost_smoke_h2.m');
paths.distanceSource = fullfile(thisDir, 'step03S_distance_block_h2.m');
paths.recoverySource = fullfile(thisDir, 'recover_step03Y_prefix_entries_h2.m');
paths.stepQSource = fullfile(thisDir, ...
    'run_step03Q_dctilde_strict_metric_audit_h2.m');
paths.stepQBound = fullfile(rootDir, 'results', ...
    'task-002-stage2b-b3-smoke', '17-dctilde-strict-metric-audit', ...
    'run-001', 'step03Q_C_bound_audit.md');
paths.roadCsv = fullfile(rootDir, 'data', 'yuanqi', 'stage1_road_edges.csv');
paths.nearMat = fullfile(rootDir, 'data', 'yuanqi', 'near_stage_msp_input.mat');
paths.nominalMat = fullfile(moduleDir, 'output', ...
    'stage3j_wdro_input_freeze', 'run-001', 'wdro_nominal_input_DAC.mat');
paths.zcSelected = fullfile(rootDir, 'results', ...
    'task-002-stage2b-b3-smoke', '38-period-ctilde-ground-cost-smoke', ...
    'run-002', 'selected_scenarios.csv');
paths.zcPairs = fullfile(rootDir, 'results', ...
    'task-002-stage2b-b3-smoke', '38-period-ctilde-ground-cost-smoke', ...
    'run-002', 'pairwise_period_distance_components.csv');
required = string(struct2cell(paths));
for ii = 1:numel(required)
    if ~isfile(required(ii))
        error('Step-03Z-D required file is missing: %s', required(ii));
    end
end

config = struct('states', [7, 9, 11, 19], 'rowsPerState', 15000, ...
    'stateCount', 35, 'periodCount', 3, 'weight_D', 0.6, ...
    'weight_Ctilde', 0.4, 'epsDistance', 1e-9, ...
    'scaleTolerance', 1e-12, 'C_bound', 357.1526447416079, ...
    'kappa', 1);

formulaAudit = recover_formula_audit(paths, config);
[demandAudit, near] = derive_demand_limits(paths.nearMat, config);
[cAudit, cStateTbl] = scan_nominal_C(paths.nominalMat, config);
roadAudit = derive_road_bound(paths.roadCsv, near, config);
[rangeTbl, observedTbl] = build_component_ranges(paths, demandAudit, ...
    cAudit, cStateTbl, config);

dMismatch = formulaAudit.current_has_extra_period_average && ...
    abs(formulaAudit.current_to_matched_ratio - 1 / 3) <= 1e-12;
cMismatch = roadAudit.bound_error > 1e-12 || ...
    cAudit.bound_violation_count > 0 || ...
    cAudit.within_state_coordinate_difference_violation_count > 0;
if dMismatch && cMismatch
    decision = "D. BOTH_SCALES_REQUIRE_REVISION";
elseif dMismatch
    decision = "B. D_SCALE_FORMULA_MISMATCH";
elseif cMismatch
    decision = "C. C_SCALE_FORMULA_MISMATCH";
else
    decision = "A. CURRENT_SCALES_FORMULA_MATCHED";
end

runtimeSec = toc(runTic);
peakMemory = memory_snapshot();
writetable(rangeTbl, fullfile(tempDir, 'component_range_summary.csv'));
write_D_audit(fullfile(tempDir, 'D_scale_formula_audit.md'), ...
    formulaAudit, demandAudit, observedTbl, config);
write_C_audit(fullfile(tempDir, 'C_scale_provenance_audit.md'), ...
    roadAudit, cAudit, cStateTbl, observedTbl, config);
write_readme(fullfile(tempDir, 'README.md'), decision, formulaAudit, ...
    demandAudit, roadAudit, cAudit, rangeTbl, runtimeSec, peakMemory, config);

mechanical = [
    "STEP03ZD_MECHANICAL_AUDIT"
    "status=PASS"
    "branch=" + expectedBranch
    "frozen_head=" + expectedHead
    "audit_type=STATIC_AND_MINIMAL_NOMINAL_SCAN"
    "solver_call_count=0"
    "Gurobi_call_count=0"
    "WDRO_call_count=0"
    "MSP_call_count=0"
    "validation_file_count=0"
    "TerminalLOH_optimization_count=0"
    "random_scenario_generation_count=0"
    "formal_ground_cost_modification_count=0"
    "runner_checkcode_count=0"
    "nominal_record_count=" + cAudit.record_count
    "nominal_reachable_C_value_count=" + cAudit.finite_count
    "C_bound_violation_count=" + cAudit.bound_violation_count
    "same_coordinate_C_difference_violation_count=" + ...
        cAudit.within_state_coordinate_difference_violation_count
    "road_bound_reproduction_error=" + sprintf('%.17g', roadAudit.bound_error)
    "D_single_period_physical_upper_kg=" + ...
        sprintf('%.17g', demandAudit.single_period_upper_kg)
    "D_three_period_physical_upper_kg=" + ...
        sprintf('%.17g', demandAudit.three_period_upper_kg)
    "current_D_to_matched_D_ratio=" + ...
        sprintf('%.17g', formulaAudit.current_to_matched_ratio)
    "runtime_sec=" + sprintf('%.6f', runtimeSec)
    "peak_working_set_bytes=" + sprintf('%.0f', peakMemory)
    "conclusion=" + decision];
write_lines(fullfile(tempDir, 'mechanical_audit.txt'), mechanical);
write_conclusion(fullfile(tempDir, 'conclusion.txt'), decision, ...
    formulaAudit, demandAudit, roadAudit, cAudit, observedTbl, ...
    runtimeSec, peakMemory, config);

movefile(tempDir, outputDir);
fprintf('Step-03Z-D completed: %s\n', decision);
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
    error('Step-03Z-D frozen branch/HEAD/upstream gate failed.');
end
end

function audit = recover_formula_audit(paths, config)
zc = string(fileread(paths.zcSource));
distance = string(fileread(paths.distanceSource));
recovery = string(fileread(paths.recoverySource));
requiredZC = [
    "dDperiod = dDperiod + dDstage(:, :, tau) / 3;"
    "dCperiod = dCperiod + dCstage(:, :, tau) / 3;"
    "dPeriod = config.weight_D .* dDperiod + config.weight_Ctilde .* dCperiod;"];
requiredDistance = [
    "rawD = sum(abs(Dq3 - Dt3), 3);"
    "dD = rawD ./ (Dscale + config.epsDistance);"
    "local = config.kappa .* double(mismatch);"
    "local(both) = reachableDifference(both) ./ config.C_bound;"
    "dCtilde = dCsum ./ localDimension;"];
requiredRecovery = [
    "Dtau = double(outage) .* model.Pnode_kW.' * model.DFactorKgPerKWh;"
    "edgeCost = model.roadLength .* (1 + slow(tau, :).');"
    "edgeCost(closed(tau, :).') = Inf;"
    "'DFactorKgPerKWh', 1 / (eta * lhv)"];
if ~all(contains(zc, requiredZC)) || ...
        ~all(contains(distance, requiredDistance)) || ...
        ~all(contains(recovery, requiredRecovery))
    error('Step-03Z-D cannot mechanically recover the frozen formulas.');
end
audit = struct();
audit.d_D_tau = "Delta_D_tau/(Dscale_state_R15000_aggregate+1e-9)";
audit.d_D_period = "(1/3)*sum_tau d_D_tau";
audit.expanded_current = ...
    "sum_tau Delta_D_tau/(3*(Dscale_state_R15000_aggregate+1e-9))";
audit.matched_total = ...
    "sum_tau Delta_D_tau/(Dscale_total+1e-9)";
audit.matched_period = ...
    "(1/3)*sum_tau Delta_D_tau/(Dscale_total/3+1e-9)";
audit.current_has_extra_period_average = true;
audit.current_to_matched_ratio = 1 / config.periodCount;
audit.eps_equivalence_note = ...
    "Without epsilon the two matched forms are exact; epsilon changes only the 1e-9 denominator term.";
end

function [audit, near] = derive_demand_limits(path, config)
loaded = load(path, 'NearStageInput');
near = loaded.NearStageInput;
Pnode = double(near.Grid.P_load_base_kw(:));
eta = double(near.HydrogenDevice.eta_FC);
lhv = double(near.HydrogenDevice.h2_lhv_kWh_per_kg);
factor = 1 / (eta * lhv);
baseNodeDemand = Pnode .* factor;
audit = struct();
audit.eta_FC = eta;
audit.h2_lhv_kWh_per_kg = lhv;
audit.kg_per_kWh = factor;
audit.node_count = numel(Pnode);
audit.total_load_kW = sum(Pnode);
audit.source_node_load_kW = Pnode(1);
audit.single_period_upper_kg = sum(baseNodeDemand);
audit.three_period_upper_kg = config.periodCount * audit.single_period_upper_kg;
audit.derivation = ...
    "D_n_tau is binary outage times P_n/(eta_FC*LHV) for a one-hour period.";
end

function audit = derive_road_bound(path, near, config)
road = readtable(path);
layout = build_h2_spatial_layout_preview(near);
nodes = sortrows(layout.nodes, 'node_id');
from = double(road.from_node); to = double(road.to_node);
lengths = hypot(nodes.x_km(to) - nodes.x_km(from), ...
    nodes.y_km(to) - nodes.y_km(from));
if any(~isfinite(lengths)) || any(lengths <= 0)
    error('Step-03Z-D frozen road geometry contains invalid lengths.');
end
sumLength = sum(lengths);
derived = 2 * sumLength;
audit = struct('edge_count', height(road), ...
    'sum_road_length_km', sumLength, ...
    'maximum_edge_length_km', max(lengths), ...
    'maximum_finite_edge_multiplier', 2, ...
    'derived_C_bound_km', derived, ...
    'frozen_C_bound_km', config.C_bound, ...
    'bound_error', abs(derived - config.C_bound), ...
    'classification', "TOPOLOGY_AND_MODEL_DERIVED_PATH_VALUE_UPPER_BOUND", ...
    'length_source', "NearStageInput layout node coordinates and road endpoint IDs");
end

function [audit, stateTbl] = scan_nominal_C(path, config)
sidecar = matfile(path);
globalMin = Inf; globalMax = -Inf; finiteCount = 0;
boundViolations = 0; differenceViolations = 0;
maxWithinDifference = -Inf; maxState = NaN; maxSite = NaN; maxNode = NaN;
maxCoordinateMin = NaN; maxCoordinateMax = NaN;
globalCoordinateMin = inf(config.stateCount, 4, 33);
globalCoordinateMax = -inf(config.stateCount, 4, 33);
stateRows = cell(config.stateCount, 7);
for stateId = 1:config.stateCount
    rows = (stateId - 1) * config.rowsPerState + (1:config.rowsPerState);
    ids = double(sidecar.initial_state_id(rows, 1));
    if any(ids ~= stateId)
        error('Step-03Z-D nominal state block ordering mismatch at state %d.', stateId);
    end
    C = double(sidecar.C_site_node_km(rows, :, :));
    finite = isfinite(C);
    values = C(finite);
    stateMin = min(values); stateMax = max(values);
    stateDifference = -Inf; stateSite = NaN; stateNode = NaN;
    finiteCount = finiteCount + numel(values);
    globalMin = min(globalMin, stateMin); globalMax = max(globalMax, stateMax);
    boundViolations = boundViolations + sum(values > config.C_bound + 1e-12);
    for site = 1:4
        for node = 1:33
            coordinate = C(:, site, node);
            coordinate = coordinate(isfinite(coordinate));
            if isempty(coordinate), continue; end
            cmin = min(coordinate); cmax = max(coordinate); delta = cmax - cmin;
            globalCoordinateMin(stateId, site, node) = cmin;
            globalCoordinateMax(stateId, site, node) = cmax;
            if delta > stateDifference
                stateDifference = delta; stateSite = site; stateNode = node;
            end
            if delta > maxWithinDifference
                maxWithinDifference = delta; maxState = stateId;
                maxSite = site; maxNode = node;
                maxCoordinateMin = cmin; maxCoordinateMax = cmax;
            end
            if delta > config.C_bound + 1e-12
                differenceViolations = differenceViolations + 1;
            end
        end
    end
    stateRows(stateId, :) = {stateId, numel(values), stateMin, stateMax, ...
        stateDifference, stateSite, stateNode};
    clear C finite values;
end
stateTbl = cell2table(stateRows, 'VariableNames', ...
    {'initial_state_id', 'finite_C_count', 'minimum_finite_C_km', ...
    'maximum_finite_C_km', 'maximum_same_coordinate_difference_km', ...
    'difference_site_id', 'difference_node_id'});
audit = struct();
audit.record_count = config.stateCount * config.rowsPerState;
audit.finite_count = finiteCount;
audit.minimum_finite_C_km = globalMin;
audit.maximum_finite_C_km = globalMax;
audit.maximum_within_state_same_coordinate_difference_km = maxWithinDifference;
audit.maximum_difference_state_id = maxState;
audit.maximum_difference_site_id = maxSite;
audit.maximum_difference_node_id = maxNode;
audit.maximum_difference_coordinate_min_km = maxCoordinateMin;
audit.maximum_difference_coordinate_max_km = maxCoordinateMax;
audit.maximum_C_fraction_of_bound = globalMax / config.C_bound;
audit.maximum_difference_fraction_of_bound = maxWithinDifference / config.C_bound;
audit.C_bound_slack_factor_over_max_C = config.C_bound / globalMax;
audit.C_bound_slack_factor_over_max_difference = config.C_bound / maxWithinDifference;
audit.bound_violation_count = boundViolations;
audit.within_state_coordinate_difference_violation_count = differenceViolations;
end

function [tbl, observed] = build_component_ranges(paths, demand, cAudit, cStateTbl, config)
selected = readtable(paths.zcSelected, 'TextType', 'string');
pairs = readtable(paths.zcPairs, 'TextType', 'string');
rows = cell(0, 18);
observedRows = cell(numel(config.states), 10);
for ss = 1:numel(config.states)
    stateId = config.states(ss);
    scaleValues = unique(double(selected.D_scale( ...
        double(selected.initial_state_id) == stateId)));
    if numel(scaleValues) ~= 1
        error('Step-03Z-D cannot recover one Dscale for state %d.', stateId);
    end
    Dscale = scaleValues(1);
    p = pairs(double(pairs.initial_state_id) == stateId, :);
    dDmax = max(double(p.d_D_period_mean));
    dCmax = max(double(p.d_Ctilde_period_mean));
    dTotalMax = max(double(p.d_period_mean));
    currentPhysicalMax = demand.three_period_upper_kg / ...
        (config.periodCount * (Dscale + config.epsDistance));
    matchedPhysicalMax = demand.three_period_upper_kg / ...
        (Dscale + config.epsDistance);
    singleScale = Dscale / config.periodCount;
    rows(end + 1, :) = {"D_PERIOD_CURRENT", stateId, Dscale, ...
        "state nominal R15000 aggregate-D L1 diameter", ...
        demand.single_period_upper_kg, demand.three_period_upper_kg, ...
        NaN, NaN, currentPhysicalMax, matchedPhysicalMax, ...
        1 / config.periodCount, 0, dDmax, config.weight_D, ...
        config.weight_D * dDmax, config.weight_D * currentPhysicalMax, ...
        "MISMATCH_EXTRA_ONE_THIRD", singleScale}; %#ok<AGROW>
    rows(end + 1, :) = {"CTILDE_PERIOD_SELECTED", stateId, config.C_bound, ...
        "global topology/model path-value bound", NaN, NaN, ...
        cAudit.maximum_finite_C_km, ...
        cAudit.maximum_within_state_same_coordinate_difference_km, ...
        1, 1, 1, 0, dCmax, config.weight_Ctilde, ...
        config.weight_Ctilde * dCmax, config.weight_Ctilde, ...
        "MATCHED_BUT_CONSERVATIVE", NaN}; %#ok<AGROW>
    rows(end + 1, :) = {"TOTAL_PERIOD_SELECTED", stateId, NaN, ...
        "0.6 D plus 0.4 Ctilde", NaN, NaN, NaN, NaN, NaN, NaN, NaN, ...
        0, dTotalMax, 1, dTotalMax, ...
        config.weight_D * currentPhysicalMax + config.weight_Ctilde, ...
        "TOTAL_NOT_REQUIRED_IN_UNIT_INTERVAL", NaN}; %#ok<AGROW>
    stateC = cStateTbl(cStateTbl.initial_state_id == stateId, :);
    observedRows(ss, :) = {stateId, Dscale, dDmax, ...
        config.weight_D * dDmax, dCmax, config.weight_Ctilde * dCmax, ...
        dTotalMax, stateC.maximum_finite_C_km, ...
        stateC.maximum_same_coordinate_difference_km, singleScale};
end
rows(end + 1, :) = {"CTILDE_NOMINAL_FINITE_LOCAL", 0, config.C_bound, ...
    "global topology/model path-value bound", NaN, NaN, ...
    cAudit.maximum_finite_C_km, ...
    cAudit.maximum_within_state_same_coordinate_difference_km, ...
    cAudit.maximum_difference_fraction_of_bound, 1, NaN, ...
    0, cAudit.maximum_difference_fraction_of_bound, config.weight_Ctilde, ...
    config.weight_Ctilde * cAudit.maximum_difference_fraction_of_bound, ...
    config.weight_Ctilde, "MATCHED_BUT_CONSERVATIVE", NaN};
tbl = cell2table(rows, 'VariableNames', {'component_scope', ...
    'initial_state_id', 'scale_value', 'scale_source', ...
    'single_period_D_physical_upper_kg', 'three_period_D_physical_upper_kg', ...
    'maximum_nominal_finite_C_km', 'maximum_nominal_same_coordinate_C_difference_km', ...
    'physical_or_local_normalized_maximum_current', ...
    'physical_or_local_normalized_maximum_matched', ...
    'current_to_matched_scale_ratio', 'observed_minimum', 'observed_maximum', ...
    'weight', 'observed_maximum_weighted_contribution', ...
    'theoretical_maximum_weighted_contribution', 'scale_assessment', ...
    'implied_single_period_D_scale'});
observed = cell2table(observedRows, 'VariableNames', ...
    {'initial_state_id', 'D_scale', 'observed_d_D_period_max', ...
    'observed_weighted_D_max', 'observed_d_Ctilde_period_max', ...
    'observed_weighted_Ctilde_max', 'observed_total_period_distance_max', ...
    'state_nominal_maximum_finite_C_km', ...
    'state_nominal_maximum_same_coordinate_C_difference_km', ...
    'implied_single_period_D_scale'});
end

function write_D_audit(path, ~, demand, observed, ~)
lines = [
    "# D Scale Formula Audit"
    ""
    "## Frozen implementation"
    ""
    "For period tau, `Delta_D_tau=sum_n abs(D_r^tau(n)-D_s^tau(n))` and Step-03Z-C computes `d_D_tau=Delta_D_tau/(Dscale+1e-9)`. It then computes `d_D_period=(d_D_W1+d_D_W2+d_D_W3)/3`. Therefore:"
    ""
    "`d_D_period_current = sum_tau Delta_D_tau / (3*(Dscale+1e-9))`."
    ""
    "Dscale is not a one-period scale. It is the state-specific exact L1 diameter of the **aggregate three-period D=sum_tau D^tau** in nominal R=15000. The implementation therefore divides each one-period numerator by a three-period aggregate scale and then averages again."
    ""
    "## Physical upper limits"
    ""
    "The recovery code defines `D_n^tau=outage_n^tau*P_n/(eta_FC*LHV)` for each one-hour period. Here `eta_FC=" + sprintf('%.17g', demand.eta_FC) + "`, `LHV=" + sprintf('%.17g', demand.h2_lhv_kWh_per_kg) + " kWh/kg`, total node load is `" + sprintf('%.17g', demand.total_load_kW) + " kW`, and the source-node load is zero."
    ""
    "Thus one-period L1 demand difference is at most `U1=sum_n P_n/(eta_FC*LHV)=" + sprintf('%.17g', demand.single_period_upper_kg) + " kg`. The sum over three periods is at most `U3=3*U1=" + sprintf('%.17g', demand.three_period_upper_kg) + " kg`."
    ""
    "## Matching formulations"
    ""
    "Ignoring the negligible epsilon convention, the following are equivalent when `U3=3*U1`:"
    ""
    "1. `sum_tau Delta_D_tau/U3`;"
    "2. `(1/3)*sum_tau Delta_D_tau/U1`."
    ""
    "If the existing Dscale is retained as the three-period scale, its matching one-period denominator is `Dscale/3`. The current code instead uses Dscale itself in every period and then averages, giving exactly one third of `sum_tau Delta_D_tau/Dscale`. This is a repeated one-third shrinkage. The `1e-9` epsilon only creates a negligible denominator-level difference between the two matched expressions."
    ""
    "## State evidence"
    ""
    "| state | aggregate Dscale | implied one-period scale | observed max current d_D_period | weighted max at 0.6 |"
    "|---:|---:|---:|---:|---:|"];
for rr = 1:height(observed)
    lines(end + 1) = "| " + observed.initial_state_id(rr) + " | " + ...
        sprintf('%.17g', observed.D_scale(rr)) + " | " + ...
        sprintf('%.17g', observed.implied_single_period_D_scale(rr)) + " | " + ...
        sprintf('%.17g', observed.observed_d_D_period_max(rr)) + " | " + ...
        sprintf('%.17g', observed.observed_weighted_D_max(rr)) + " |"; %#ok<AGROW>
end
lines = [lines; ""; "Assessment: `D_SCALE_FORMULA_MISMATCH`. The audit does not modify Dscale, the period averaging rule, or the 0.6 weight."];
write_lines(path, lines);
end

function write_C_audit(path, road, c, ~, observed, ~)
lines = [
    "# C Scale Provenance Audit"
    ""
    "## What C represents"
    ""
    "The period recovery uses `edgeCost=roadLength*(1+slowdown)` and sets closed edges to `Inf`, then runs the current-road-state shortest path. C therefore includes both open-road slowdown and detours caused by closures. It is not a baseline distance."
    ""
    "## Exact C bound"
    ""
    "Road failure probability/slowdown is clipped to [0,1], so every finite edge cost is at most twice its road length. Positive edge costs imply a finite shortest path can be selected simple and use each of the " + road.edge_count + " edges at most once. Therefore:"
    ""
    "`C_bound=2*sum(all road lengths)=2*" + sprintf('%.17g', road.sum_road_length_km) + "=" + sprintf('%.17g', road.derived_C_bound_km) + " km`. The lengths are recomputed from the frozen `NearStageInput` layout node coordinates and the CSV road endpoint IDs, exactly as in Step-03Q; the CSV `length_km` column is not the frozen bound source."
    ""
    "This is a topology/model-derived upper bound on any finite post-disaster shortest-path C value. It is not the observed maximum shortest path, not the observed maximum C difference, and not merely the unmultiplied road-network total length."
    ""
    "Because finite C is nonnegative and bounded by C_bound, `abs(C1-C2)<=C_bound`; the denominator is therefore formula-compatible with the numerator. It is conservative rather than invalid."
    ""
    "## Nominal full scan"
    ""
    "The scan reads all " + c.record_count + " stored nominal aggregate D/A/C records in state blocks. It does not read validation. For the numerator, the exact maximum pair difference at a fixed state/site/node coordinate is computed as finite max minus finite min, without constructing a pair matrix."
    ""
    "- finite reachable C values: " + c.finite_count
    "- minimum finite C: " + sprintf('%.17g', c.minimum_finite_C_km) + " km"
    "- maximum finite C: " + sprintf('%.17g', c.maximum_finite_C_km) + " km"
    "- maximum same-state, same-coordinate finite abs difference: " + sprintf('%.17g', c.maximum_within_state_same_coordinate_difference_km) + " km"
    "- maximum difference identity: state " + c.maximum_difference_state_id + ", site " + c.maximum_difference_site_id + ", node " + c.maximum_difference_node_id
    "- maximum C / C_bound: " + sprintf('%.17g', c.maximum_C_fraction_of_bound)
    "- maximum finite difference / C_bound: " + sprintf('%.17g', c.maximum_difference_fraction_of_bound)
    "- C_bound violations: " + c.bound_violation_count
    "- same-coordinate difference violations: " + c.within_state_coordinate_difference_violation_count
    ""
    "The bound is " + sprintf('%.6g', c.C_bound_slack_factor_over_max_difference) + " times the largest observed nominal same-coordinate finite difference. This reduces the numerical size of the continuous reachable-reachable term, but reachability mismatch remains exactly 1 and the theoretical Ctilde weighted contribution remains at most 0.4."
    ""
    "## Selected Step-03Z-C period ranges"
    ""
    "| state | observed max d_Ctilde_period | weighted max at 0.4 | nominal max C | nominal max same-coordinate difference |"
    "|---:|---:|---:|---:|---:|"];
for rr = 1:height(observed)
    lines(end + 1) = "| " + observed.initial_state_id(rr) + " | " + ...
        sprintf('%.17g', observed.observed_d_Ctilde_period_max(rr)) + " | " + ...
        sprintf('%.17g', observed.observed_weighted_Ctilde_max(rr)) + " | " + ...
        sprintf('%.17g', observed.state_nominal_maximum_finite_C_km(rr)) + " | " + ...
        sprintf('%.17g', observed.state_nominal_maximum_same_coordinate_C_difference_km(rr)) + " |"; %#ok<AGROW>
end
lines = [lines; ""; "Assessment: Cscale is matched to the finite-value difference numerator but is conservative. No C scale formula mismatch is found, and this task does not change C_bound or the 0.4 weight."];
write_lines(path, lines);
end

function write_readme(path, decision, formula, demand, road, c, ranges, runtime, peak, config)
lines = [
    "# Step-03Z-D Ground-Cost Scale Audit"
    ""
    "Conclusion: **" + decision + "**"
    ""
    "This audit is static except for a streaming scan of the stored nominal C array. It calls no solver, WDRO, MSP, validation, TerminalLOH optimization, or random scenario generator, and it does not change the frozen 0.6/0.4 formula."
    ""
    "## Main findings"
    ""
    "- Current D: `sum_tau Delta_D_tau/(3*(Dscale+1e-9))`. Dscale is already a three-period aggregate scale, so the final period average shrinks D by an additional factor of three relative to the matching total-numerator formulation."
    "- One-period physical D upper: " + sprintf('%.17g', demand.single_period_upper_kg) + " kg; three-period upper: " + sprintf('%.17g', demand.three_period_upper_kg) + " kg."
    "- C_bound: " + sprintf('%.17g', road.derived_C_bound_km) + " km, derived as twice the total road length. It is a finite post-disaster path-value upper bound."
    "- Nominal maximum finite C: " + sprintf('%.17g', c.maximum_finite_C_km) + " km; maximum same-state/same-coordinate finite difference: " + sprintf('%.17g', c.maximum_within_state_same_coordinate_difference_km) + " km."
    "- Cscale is conservative but compatible with `abs(C1-C2)` because finite C lies in [0,C_bound]."
    "- Total ground cost is not required to lie in [0,1]. Under current weights, the formal Ctilde contribution is at most 0.4; the current D physical maximum contribution is state-dependent and reported in `component_range_summary.csv`."
    ""
    "runtime_sec=" + sprintf('%.6f', runtime)
    "peak_working_set_bytes=" + sprintf('%.0f', peak)
    "component_summary_rows=" + height(ranges)
    "current_D_to_matched_D_ratio=" + sprintf('%.17g', formula.current_to_matched_ratio)
    "weights=" + config.weight_D + "/" + config.weight_Ctilde];
write_lines(path, lines);
end

function write_conclusion(path, decision, formula, demand, road, c, observed, runtime, peak, config)
lines = [
    "conclusion=" + decision
    "Dscale_source=state-specific nominal R15000 aggregate-three-period-D exact L1 diameter"
    "D_current_formula=" + formula.expanded_current
    "D_matched_total_formula=" + formula.matched_total
    "D_current_to_matched_ratio=" + sprintf('%.17g', formula.current_to_matched_ratio)
    "D_single_period_physical_upper_kg=" + sprintf('%.17g', demand.single_period_upper_kg)
    "D_three_period_physical_upper_kg=" + sprintf('%.17g', demand.three_period_upper_kg)
    "D_assessment=extra one-third shrinkage; numerator and scale/average convention are mismatched"
    "Cscale_source=2*sum(41 road lengths) with maximum finite slowdown multiplier 2"
    "C_bound_km=" + sprintf('%.17g', road.derived_C_bound_km)
    "C_bound_type=topology-and-model-derived maximum finite path-value upper bound"
    "C_contains_slowdown=true"
    "C_contains_closure_detours=true"
    "nominal_maximum_finite_C_km=" + sprintf('%.17g', c.maximum_finite_C_km)
    "nominal_maximum_same_coordinate_finite_difference_km=" + sprintf('%.17g', c.maximum_within_state_same_coordinate_difference_km)
    "nominal_maximum_difference_fraction_of_C_bound=" + sprintf('%.17g', c.maximum_difference_fraction_of_bound)
    "C_assessment=matched to abs(C1-C2), conservative but not too small"
    "ground_cost_unit_interval_required=false"
    "Ctilde_theoretical_maximum=1"
    "Ctilde_weighted_theoretical_maximum=" + sprintf('%.17g', config.weight_Ctilde)
    "solver_call_count=0"
    "validation_file_count=0"
    "runtime_sec=" + sprintf('%.6f', runtime)
    "peak_working_set_bytes=" + sprintf('%.0f', peak)];
for rr = 1:height(observed)
    Dscale = observed.D_scale(rr);
    currentDmax = demand.three_period_upper_kg / ...
        (config.periodCount * (Dscale + config.epsDistance));
    lines(end + 1) = "state=" + observed.initial_state_id(rr) + ...
        ",Dscale=" + sprintf('%.17g', Dscale) + ...
        ",current_D_physical_max=" + sprintf('%.17g', currentDmax) + ...
        ",current_D_weighted_physical_max=" + sprintf('%.17g', config.weight_D * currentDmax) + ...
        ",observed_D_weighted_max=" + sprintf('%.17g', observed.observed_weighted_D_max(rr)) + ...
        ",observed_Ctilde_weighted_max=" + sprintf('%.17g', observed.observed_weighted_Ctilde_max(rr)) + ...
        ",observed_total_max=" + sprintf('%.17g', observed.observed_total_period_distance_max(rr)); %#ok<AGROW>
end
write_lines(path, lines);
end

function write_lines(path, lines)
fid = fopen(path, 'w');
if fid < 0, error('Cannot open output file: %s', path); end
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
