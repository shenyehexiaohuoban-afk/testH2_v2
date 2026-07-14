function result = build_terminal_loh_wdro_from_joint_samples_h2(config)
%BUILD_TERMINAL_LOH_WDRO_FROM_JOINT_SAMPLES_H2 Run offline WDRO preview.

if nargin < 1 || isempty(config)
    config = struct();
end
config = apply_default_config(config);

if ~isfile(config.inputCsv)
    error('build_terminal_loh_wdro_from_joint_samples_h2:MissingInputCsv', ...
        'Missing joint scenario CSV: %s', config.inputCsv);
end
if ~exist(config.outputDir, 'dir')
    mkdir(config.outputDir);
end

[tankCap, M, sourceInfo] = read_capacity_and_penalty(config);
Cap = config.capacity_fraction .* tankCap(:);
if isempty(config.gamma)
    config.gamma = 0.001 * M;
end
if ~isscalar(config.gamma) || config.gamma < 0
    error('build_terminal_loh_wdro_from_joint_samples_h2:BadGamma', ...
        'config.gamma must be a nonnegative scalar.');
end

jointTbl = readtable(config.inputCsv);
validate_joint_table(jointTbl);

stateTbl = unique(jointTbl(:, {'a', 'loc', 'lf'}), 'rows', 'stable');
numStates = height(stateTbl);
numModes = numel(config.distance_modes);
numRho = numel(config.rho_list);

terminalRows = cell(numStates * numModes * numRho, 19);
distanceRows = cell(numStates * numModes, 31);
terminalRow = 0;
distanceRow = 0;

if config.saveAllocation
    maxAllocRows = height(jointTbl) * numModes * numRho;
    allocationRows = cell(maxAllocRows, 13);
else
    allocationRows = cell(0, 13);
end
allocationRow = 0;

stateSampleCounts = zeros(numStates, 1);
failedSolves = 0;

for st = 1:numStates
    a = stateTbl.a(st);
    loc = stateTbl.loc(st);
    lf = stateTbl.lf(st);
    rows = jointTbl(jointTbl.a == a & jointTbl.loc == loc & jointTbl.lf == lf, :);
    samples = build_state_samples(rows, tankCap);
    stateSampleCounts(st) = samples.R;

    for mm = 1:numModes
        distanceMode = config.distance_modes{mm};
        [dMat, distanceInfo] = build_wdro_distance_matrix_h2( ...
            samples.D, samples.A, samples.C_raw, distanceMode, config);
        distSummary = summarize_distance(samples, dMat, distanceInfo);

        distanceRow = distanceRow + 1;
        distanceRows(distanceRow, :) = build_distance_row( ...
            distanceInfo.distance_mode, a, loc, lf, samples.R, ...
            distSummary, distanceInfo);

        for rrho = 1:numRho
            rho = config.rho_list(rrho);
            sol = solve_wdro_terminal_loh_lp_h2(samples.D, samples.A, ...
                samples.C_raw, Cap, M, rho, dMat, config);

            if sol.exitflag ~= 1
                failedSolves = failedSolves + 1;
            end

            terminalRow = terminalRow + 1;
            terminalRows(terminalRow, :) = build_terminal_row( ...
                distanceInfo.distance_mode, rho, a, loc, lf, samples.R, ...
                config.capacity_fraction, config.gamma, M, Cap, sol);

            if config.saveAllocation && sol.exitflag == 1
                [allocationRows, allocationRow] = append_allocation_rows( ...
                    allocationRows, allocationRow, distanceInfo.distance_mode, rho, ...
                    a, loc, lf, samples, sol);
            end
        end
    end
end

terminalTbl = cell_rows_to_table(terminalRows(1:terminalRow, :), ...
    {'distance_mode', 'rho', 'a', 'loc', 'lf', 'R', ...
    'capacity_fraction', 'gamma', 'M', ...
    'TerminalLOH_site1_WDRO_kg', 'TerminalLOH_site2_WDRO_kg', ...
    'TerminalLOH_site3_WDRO_kg', 'TerminalLOH_site4_WDRO_kg', ...
    'TerminalLOH_total_WDRO_kg', 'lambda', 'objective_value', ...
    'solve_status', 'runtime_sec', 'max_capacity_violation_kg'});

distanceTbl = cell_rows_to_table(distanceRows(1:distanceRow, :), ...
    {'distance_mode', 'a', 'loc', 'lf', 'R', ...
    'd_min', 'd_mean', 'd_max', 'd_diag_max_abs', ...
    'd_symmetry_max_abs', 'D_total_min', 'D_total_mean', ...
    'D_total_max', 'A_binary_ok', 'A_min', 'A_max', ...
    'A_unique_values', 'A_total_reachable_min', ...
    'A_total_reachable_mean', 'A_total_reachable_max', ...
    'C_unreachable_min', 'C_unreachable_mean', 'C_unreachable_max', ...
    'C_masked_pair_count', 'C_masked_pair_share', ...
    'D_weight', 'A_weight', 'C_weight', ...
    'D_scale', 'A_scale', 'C_scale'});

if config.saveAllocation
    allocationTbl = cell_rows_to_table(allocationRows(1:allocationRow, :), ...
        {'distance_mode', 'rho', 'a', 'loc', 'lf', 'scenario_id', ...
        'site_id', 'node_id', 'D_node_kg_s', 'reachable', ...
        'scenario_service_cost', 'allocated_H2_kg', 'uncovered_H2_kg'});
else
    allocationTbl = cell_rows_to_table(cell(0, 13), ...
        {'distance_mode', 'rho', 'a', 'loc', 'lf', 'scenario_id', ...
        'site_id', 'node_id', 'D_node_kg_s', 'reachable', ...
        'scenario_service_cost', 'allocated_H2_kg', 'uncovered_H2_kg'});
end

writetable(terminalTbl, fullfile(config.outputDir, ...
    'terminal_loh_by_state_WDRO.csv'));
if config.saveAllocation
    writetable(allocationTbl, fullfile(config.outputDir, ...
        'terminal_loh_allocation_WDRO.csv'));
end
writetable(distanceTbl, fullfile(config.outputDir, ...
    'wdro_distance_matrix_summary.csv'));
rhoSummaryTbl = build_rho_sensitivity_summary(terminalTbl);
writetable(rhoSummaryTbl, fullfile(config.outputDir, ...
    'wdro_rho_sensitivity_summary.csv'));

write_wdro_readme_txt(config, sourceInfo, numStates, stateSampleCounts, ...
    failedSolves, terminalTbl, rhoSummaryTbl, distanceTbl);

result = struct();
result.config = config;
result.sourceInfo = sourceInfo;
result.terminal_by_state = terminalTbl;
result.allocation = allocationTbl;
result.distance_summary = distanceTbl;
result.rho_sensitivity_summary = rhoSummaryTbl;
result.numStates = numStates;
result.stateSampleCounts = stateSampleCounts;
result.failedSolves = failedSolves;
end

function config = apply_default_config(config)
srcDir = fileparts(mfilename('fullpath'));
moduleDir = fileparts(srcDir);
rootDir = fileparts(moduleDir);
if ~isfield(config, 'rootDir') || isempty(config.rootDir)
    config.rootDir = rootDir;
end
if ~isfield(config, 'moduleDir') || isempty(config.moduleDir)
    config.moduleDir = moduleDir;
end
if ~isfield(config, 'inputCsv') || isempty(config.inputCsv)
    config.inputCsv = fullfile(config.rootDir, 'output_h2', ...
        'wind_terminal_loh_preview', 'riskcap_mean', ...
        'joint_scenario_site_node.csv');
end
if ~isfield(config, 'outputDir') || isempty(config.outputDir)
    config.outputDir = fullfile(config.moduleDir, 'output', ...
        'stage1_single_window_DA_update');
end
if ~isfield(config, 'nearInputFile') || isempty(config.nearInputFile)
    config.nearInputFile = fullfile(config.rootDir, 'data', 'yuanqi', ...
        'near_stage_msp_input.mat');
end
if ~isfield(config, 'siteInputCsv') || isempty(config.siteInputCsv)
    config.siteInputCsv = fullfile(config.rootDir, 'data', 'yuanqi', ...
        'near_stage_msp_site_input.csv');
end
if ~isfield(config, 'rho_list') || isempty(config.rho_list)
    config.rho_list = [0, 0.02, 0.05, 0.10];
end
if ~isfield(config, 'distance_modes') || isempty(config.distance_modes)
    config.distance_modes = {'D_only', 'DA', 'DAC_maskedC'};
end
if ~isfield(config, 'capacity_fraction') || isempty(config.capacity_fraction)
    config.capacity_fraction = 0.8;
end
if ~isfield(config, 'gamma')
    config.gamma = [];
end
if ~isfield(config, 'saveAllocation') || isempty(config.saveAllocation)
    config.saveAllocation = true;
end
if ~isfield(config, 'distanceWeights') || isempty(config.distanceWeights)
    config.distanceWeights = struct('D', 0.6, 'A', 0.2, 'C', 0.2);
end
if ~isfield(config, 'distanceWeightsDA') || isempty(config.distanceWeightsDA)
    config.distanceWeightsDA = struct('D', 0.7, 'A', 0.3, 'C', 0);
end
if ~isfield(config, 'distanceWeightsDACMaskedC') || isempty(config.distanceWeightsDACMaskedC)
    config.distanceWeightsDACMaskedC = struct('D', 0.6, 'A', 0.25, 'C', 0.15);
end
if ~isfield(config, 'epsDistance') || isempty(config.epsDistance)
    config.epsDistance = 1e-9;
end
if ~isfield(config, 'scaleTolerance') || isempty(config.scaleTolerance)
    config.scaleTolerance = 1e-12;
end
if ~isfield(config, 'gurobiOutputFlag') || isempty(config.gurobiOutputFlag)
    config.gurobiOutputFlag = 0;
end
end

function [tankCap, M, sourceInfo] = read_capacity_and_penalty(config)
tankCap = [];
M = [];
sourceInfo = struct();
sourceInfo.capacity_source = "";
sourceInfo.penalty_source = "";

if isfile(config.nearInputFile)
    raw = load(config.nearInputFile, 'NearStageInput');
    if isfield(raw, 'NearStageInput')
        ni = raw.NearStageInput;
        if isfield(ni, 'HydrogenDevice') && ...
                isfield(ni.HydrogenDevice, 'tank_cap_kg')
            tankCap = double(ni.HydrogenDevice.tank_cap_kg(:));
            sourceInfo.capacity_source = "near_stage_msp_input.mat:NearStageInput.HydrogenDevice.tank_cap_kg";
        end
        if isfield(ni, 'Cost') && ...
                isfield(ni.Cost, 'reserve_shortage_penalty_yuan_per_kg')
            M = double(ni.Cost.reserve_shortage_penalty_yuan_per_kg);
            sourceInfo.penalty_source = "near_stage_msp_input.mat:NearStageInput.Cost.reserve_shortage_penalty_yuan_per_kg";
        elseif isfield(ni, 'Cost') && isfield(ni.Cost, 'cost_reserve_shortage')
            M = double(ni.Cost.cost_reserve_shortage);
            sourceInfo.penalty_source = "near_stage_msp_input.mat:NearStageInput.Cost.cost_reserve_shortage";
        end
    end
end

if isempty(tankCap) && isfile(config.siteInputCsv)
    siteTbl = readtable(config.siteInputCsv);
    if ismember('tank_cap_kg', siteTbl.Properties.VariableNames)
        tankCap = double(siteTbl.tank_cap_kg(:));
        sourceInfo.capacity_source = "near_stage_msp_site_input.csv:tank_cap_kg";
    end
end
if isempty(tankCap)
    error('build_terminal_loh_wdro_from_joint_samples_h2:MissingTankCapacity', ...
        'Could not read tank_cap_kg from MAT or site CSV.');
end
if isempty(M)
    M = 2000;
    sourceInfo.penalty_source = "explicit_default_2000_yuan_per_kg";
    warning('build_terminal_loh_wdro_from_joint_samples_h2:DefaultPenaltyM', ...
        'Reserve shortage penalty was not found. Using M = %.6g.', M);
end
if ~isscalar(M) || M <= 0
    error('build_terminal_loh_wdro_from_joint_samples_h2:BadPenaltyM', ...
        'Penalty M must be a positive scalar.');
end
end

function validate_joint_table(tbl)
required = {'a', 'loc', 'lf', 'scenario_id', 'site_id', 'node_id', ...
    'H_node_kg_s', 'reachable', 'scenario_service_cost'};
for ii = 1:numel(required)
    if ~ismember(required{ii}, tbl.Properties.VariableNames)
        error('build_terminal_loh_wdro_from_joint_samples_h2:MissingColumn', ...
            'joint_scenario_site_node.csv is missing column %s.', required{ii});
    end
end
if any(tbl.H_node_kg_s < -1e-8)
    error('build_terminal_loh_wdro_from_joint_samples_h2:NegativeDemand', ...
        'H_node_kg_s contains negative values.');
end
if any(~ismember(double(tbl.reachable), [0; 1]))
    warning('build_terminal_loh_wdro_from_joint_samples_h2:NonBinaryReachable', ...
        ['reachable contains values other than 0/1. The distance ' ...
        'diagnostics will record A_binary_ok=false; values are not rounded.']);
end
end

function samples = build_state_samples(tbl, tankCap)
scenarioIds = unique(tbl.scenario_id, 'stable');
siteIds = unique(tbl.site_id, 'stable');
nodeIds = unique(tbl.node_id, 'stable');
R = numel(scenarioIds);
I = numel(siteIds);
N = numel(nodeIds);
if I ~= numel(tankCap)
    error('build_terminal_loh_wdro_from_joint_samples_h2:BadSiteCount', ...
        'State table has %d sites but capacity vector has %d entries.', I, numel(tankCap));
end
if any(siteIds(:) ~= (1:I).')
    error('build_terminal_loh_wdro_from_joint_samples_h2:BadSiteIds', ...
        'site_id must be consecutive 1..I for WDRO output columns.');
end

D = zeros(R, N);
A = zeros(R, I, N);
C = zeros(R, I, N);

for ss = 1:R
    sId = scenarioIds(ss);
    scenMask = tbl.scenario_id == sId;
    for nn = 1:N
        nodeId = nodeIds(nn);
        nodeMask = scenMask & tbl.node_id == nodeId;
        if nnz(nodeMask) ~= I
            error('build_terminal_loh_wdro_from_joint_samples_h2:BadScenarioNodeRows', ...
                'Expected %d rows for scenario_id=%d node_id=%d, got %d.', ...
                I, sId, nodeId, nnz(nodeMask));
        end
        vals = double(tbl.H_node_kg_s(nodeMask));
        if max(vals) - min(vals) > 1e-7
            error('build_terminal_loh_wdro_from_joint_samples_h2:RepeatedDemandMismatch', ...
                'H_node_kg_s differs across site rows for scenario_id=%d node_id=%d.', ...
                sId, nodeId);
        end
        D(ss, nn) = vals(1);
    end
    for ii = 1:I
        siteId = siteIds(ii);
        for nn = 1:N
            nodeId = nodeIds(nn);
            rowMask = scenMask & tbl.site_id == siteId & tbl.node_id == nodeId;
            if nnz(rowMask) ~= 1
                error('build_terminal_loh_wdro_from_joint_samples_h2:BadSiteNodeRows', ...
                    'Expected one row for scenario_id=%d site_id=%d node_id=%d, got %d.', ...
                    sId, siteId, nodeId, nnz(rowMask));
            end
            A(ss, ii, nn) = double(tbl.reachable(rowMask));
            C(ss, ii, nn) = double(tbl.scenario_service_cost(rowMask));
        end
    end
end

samples = struct();
samples.scenarioIds = scenarioIds(:);
samples.siteIds = siteIds(:);
samples.nodeIds = nodeIds(:);
samples.R = R;
samples.I = I;
samples.N = N;
samples.D = D;
samples.A = A;
samples.C_raw = C;
end

function row = build_terminal_row(distanceMode, rho, a, loc, lf, R, ...
    capacityFraction, gamma, M, Cap, sol)
T = sol.T(:);
if numel(T) < 4
    T(4) = NaN;
end
if all(isfinite(T(1:4)))
    totalT = sum(T(1:4));
else
    totalT = NaN;
end
maxCapViolation = 0;
if isfield(sol, 'T') && ~isempty(sol.T) && all(isfinite(sol.T))
    maxCapViolation = max(0, max(sol.T(:) - Cap(:)));
end
row = {char(distanceMode), rho, a, loc, lf, R, capacityFraction, ...
    gamma, M, T(1), T(2), T(3), T(4), totalT, sol.lambda, ...
    sol.objective_value, char(sol.status), sol.runtime_sec, maxCapViolation};
end

function row = build_distance_row(distanceMode, a, loc, lf, R, summary, info)
row = {char(distanceMode), a, loc, lf, R, ...
    summary.d_min, summary.d_mean, summary.d_max, ...
    info.d_diag_max_abs, info.d_symmetry_max_abs, ...
    summary.D_total_min, summary.D_total_mean, summary.D_total_max, ...
    info.A_binary_ok, info.A_min, info.A_max, char(info.A_unique_values), ...
    summary.A_total_reachable_min, summary.A_total_reachable_mean, ...
    summary.A_total_reachable_max, summary.C_unreachable_min, ...
    summary.C_unreachable_mean, summary.C_unreachable_max, ...
    info.C_masked_pair_count, info.C_masked_pair_share, ...
    info.weights.D, info.weights.A, info.weights.C, ...
    info.D_scale, info.A_scale, info.C_scale};
end

function summary = summarize_distance(samples, dMat, info)
R = samples.R;
offDiag = ~eye(R);
if R > 1
    dVals = dMat(offDiag);
else
    dVals = dMat(:);
end
Dtotal = sum(samples.D, 2);
ATotalReachable = squeeze(sum(sum(samples.A > 0.5, 3), 2));
CUnreachable = samples.C_raw(samples.A <= 0.5);
if isempty(CUnreachable)
    cUnreachableMin = NaN;
    cUnreachableMean = NaN;
    cUnreachableMax = NaN;
else
    cUnreachableMin = min(CUnreachable);
    cUnreachableMean = mean(CUnreachable);
    cUnreachableMax = max(CUnreachable);
end
if info.d_min_all < -1e-10
    warning('build_terminal_loh_wdro_from_joint_samples_h2:NegativeDistance', ...
        'Distance matrix for %s has a negative entry %.6g.', ...
        info.distance_mode, info.d_min_all);
end
summary = struct();
summary.d_min = min(dVals);
summary.d_mean = mean(dVals);
summary.d_max = max(dVals);
summary.D_total_min = min(Dtotal);
summary.D_total_mean = mean(Dtotal);
summary.D_total_max = max(Dtotal);
summary.A_total_reachable_min = min(ATotalReachable);
summary.A_total_reachable_mean = mean(ATotalReachable);
summary.A_total_reachable_max = max(ATotalReachable);
summary.C_unreachable_min = cUnreachableMin;
summary.C_unreachable_mean = cUnreachableMean;
summary.C_unreachable_max = cUnreachableMax;
end

function [allocationRows, allocationRow] = append_allocation_rows( ...
    allocationRows, allocationRow, distanceMode, rho, a, loc, lf, samples, sol)
for ss = 1:samples.R
    for ii = 1:samples.I
        for nn = 1:samples.N
            allocationRow = allocationRow + 1;
            allocationRows(allocationRow, :) = {char(distanceMode), rho, ...
                a, loc, lf, samples.scenarioIds(ss), samples.siteIds(ii), ...
                samples.nodeIds(nn), samples.D(ss, nn), samples.A(ss, ii, nn), ...
                samples.C_raw(ss, ii, nn), sol.y(ss, ii, nn), sol.u(ss, nn)};
        end
    end
end
end

function tbl = cell_rows_to_table(rows, names)
if isempty(rows)
    rows = cell(0, numel(names));
end
tbl = table();
for jj = 1:numel(names)
    col = rows(:, jj);
    if isempty(col)
        tbl.(names{jj}) = cell(0, 1);
    elseif all(cellfun(@(x) isnumeric(x) && isscalar(x), col))
        tbl.(names{jj}) = cell2mat(col);
    elseif all(cellfun(@(x) islogical(x) && isscalar(x), col))
        tbl.(names{jj}) = cell2mat(col);
    elseif all(cellfun(@(x) ischar(x) || (isstring(x) && isscalar(x)), col))
        tbl.(names{jj}) = string(col);
    else
        tbl.(names{jj}) = col;
    end
end
end

function rhoTbl = build_rho_sensitivity_summary(terminalTbl)
required = {'distance_mode', 'rho', 'a', 'loc', 'lf', ...
    'TerminalLOH_total_WDRO_kg', 'objective_value', 'lambda'};
for ii = 1:numel(required)
    if ~ismember(required{ii}, terminalTbl.Properties.VariableNames)
        error('build_terminal_loh_wdro_from_joint_samples_h2:MissingRhoSummaryColumn', ...
            'terminalTbl is missing required column %s.', required{ii});
    end
end

modes = unique(string(terminalTbl.distance_mode), 'stable');
rows = {};
for mm = 1:numel(modes)
    mode = modes(mm);
    modeRows = terminalTbl(string(terminalTbl.distance_mode) == mode, :);
    rhoVals = unique(modeRows.rho);
    rhoVals = sort(rhoVals(:));
    prevByState = table();
    for rr = 1:numel(rhoVals)
        rho = rhoVals(rr);
        rowsNow = modeRows(abs(modeRows.rho - rho) <= 1e-12, :);
        rowsNow = sortrows(rowsNow, {'a', 'loc', 'lf'});
        totals = rowsNow.TerminalLOH_total_WDRO_kg;
        if rr == 1
            decreaseCount = 0;
        else
            sameStates = isequal(rowsNow(:, {'a', 'loc', 'lf'}), ...
                prevByState(:, {'a', 'loc', 'lf'}));
            if ~sameStates
                error('build_terminal_loh_wdro_from_joint_samples_h2:RhoStateMismatch', ...
                    'State ordering differs across rho values for distance mode %s.', mode);
            end
            decreaseCount = sum(rowsNow.TerminalLOH_total_WDRO_kg < ...
                prevByState.TerminalLOH_total_WDRO_kg - 1e-8);
        end
        rows(end + 1, :) = {char(mode), rho, min(totals), mean(totals), ...
            max(totals), mean(rowsNow.objective_value), ...
            mean(rowsNow.lambda), decreaseCount}; %#ok<AGROW>
        prevByState = rowsNow(:, {'a', 'loc', 'lf', ...
            'TerminalLOH_total_WDRO_kg'});
    end
end

rhoTbl = cell_rows_to_table(rows, {'distance_mode', 'rho', ...
    'TerminalLOH_total_min', 'TerminalLOH_total_mean', ...
    'TerminalLOH_total_max', 'objective_mean', 'lambda_mean', ...
    'states_with_total_decrease_vs_previous_rho'});
end

function write_wdro_readme_txt(config, sourceInfo, numStates, sampleCounts, ...
    failedSolves, terminalTbl, rhoSummaryTbl, distanceTbl)
rhoText = strtrim(sprintf('%.6g ', config.rho_list));
modeText = strjoin(cellstr(string(config.distance_modes)), ', ');
if isempty(terminalTbl)
    rho0Status = "not_available";
else
    rho0Rows = terminalTbl(abs(terminalTbl.rho) <= 1e-12, :);
    rho0Status = string(join(unique(string(rho0Rows.solve_status)), ","));
end
if isempty(rhoSummaryTbl)
    decreaseText = "not_available";
else
    maxDecrease = max(rhoSummaryTbl.states_with_total_decrease_vs_previous_rho);
    decreaseText = sprintf("max states with total decrease vs previous rho = %d", maxDecrease);
end
if isempty(distanceTbl)
    aBinaryText = "not_available";
    cUnreachableText = "not_available";
else
    aBinaryText = sprintf("%d/%d distance rows have A_binary_ok=true", ...
        sum(distanceTbl.A_binary_ok), height(distanceTbl));
    noUnreachableRows = sum(isnan(distanceTbl.C_unreachable_min) & ...
        isnan(distanceTbl.C_unreachable_mean) & ...
        isnan(distanceTbl.C_unreachable_max));
    infUnreachableRows = sum(isinf(distanceTbl.C_unreachable_min) | ...
        isinf(distanceTbl.C_unreachable_mean) | ...
        isinf(distanceTbl.C_unreachable_max));
    cUnreachableText = sprintf("%d/%d rows have no unreachable C entries; %d/%d rows include Inf in unreachable C diagnostics", ...
        noUnreachableRows, height(distanceTbl), ...
        infUnreachableRows, height(distanceTbl));
end
txt = [
"WDRO-TerminalLOH offline preview"
""
"1. This module is an offline WDRO-TerminalLOH prototype."
"2. The current input is single-window joint scenario data, equivalent to W=1."
"3. The current result is not connected to MSP."
"4. No lf=7 three-window look-ahead generator is implemented in this phase."
"5. The main Wasserstein distance is DA, built on consequence atoms xi=(D,A)."
"6. D_n^s is H_node_kg_s; A_in^s is reachable; C_in^s is scenario_service_cost."
"7. A is binary reachability for 4 sites x 33 nodes; probability mass moves only between complete finite scenario atoms."
"8. The model does not continuously perturb reachability entries, so it does not create A_in=0.3 half-reachable states."
"9. DA uses weighted normalized L1 distance of D and A, with default weights w_D=0.7 and w_A=0.3."
"10. C is not included in the main distance to avoid double-counting unreachable events already represented by A."
"11. DAC_maskedC is an extension: it compares C only on site-node pairs reachable in both scenarios."
"12. Legacy DAC, if explicitly requested, is an unmasked compatibility mode and is not recommended as the main method."
"13. rho=0 degenerates to the empirical sample average distribution/SAA on the selected finite support."
"14. The current joint_scenario_site_node.csv has R=10 scenarios per state and is only for prototype validation, not final paper results."
"15. Formal follow-up should generate W=3 lookahead_scenario_site_node.csv and rerun WDRO."
"16. With the current R=10 prototype, increasing rho does not necessarily make TerminalLOH monotone increasing."
"17. The rho sensitivity pattern needs further judgment using W=3, R=50/100, and out-of-sample testing."
"18. D_only is a debugging/comparison distance mode because it ignores reachability A."
""
sprintf("Project root: %s", config.rootDir)
sprintf("Input CSV: %s", config.inputCsv)
sprintf("Output directory: %s", config.outputDir)
sprintf("Capacity source: %s", sourceInfo.capacity_source)
sprintf("Penalty source M: %s", sourceInfo.penalty_source)
sprintf("capacity_fraction: %.6g", config.capacity_fraction)
sprintf("gamma: %.6g", config.gamma)
sprintf("rho_list: %s", rhoText)
sprintf("distance_modes: %s", modeText)
sprintf("state_count: %d", numStates)
sprintf("scenario_count_min_mean_max: %.6g / %.6g / %.6g", ...
    min(sampleCounts), mean(sampleCounts), max(sampleCounts))
sprintf("failed_solve_count: %d", failedSolves)
sprintf("rho0_reference_solve_status: %s", rho0Status)
sprintf("rho_sensitivity: %s", decreaseText)
sprintf("A_binary_check: %s", aBinaryText)
sprintf("C_unreachable_diagnostic: %s", cUnreachableText)
""
"Implementation notes:"
"- Non-finite scenario_service_cost values appear only on unreachable pairs in the current CSV."
"- The LP forces unreachable y_i,n^s to zero through the upper bound y_i,n^s <= A_i,n^s D_n^s."
"- DA distance does not use C."
"- DAC_maskedC excludes C differences unless both compared scenarios are reachable on the same site-node pair."
"- Non-finite or unreachable service costs are set to 0 only in LP coefficients and in the legacy unmasked DAC compatibility component; reachability differences are represented by A."
"- gamma is a small configurable TerminalLOH holding weight used only to avoid filling all sites to capacity; it is not MSP hydrogen production cost."
"- This module does not read or overwrite params.TerminalLOH."
"- This module does not modify forward/backward/cut or Markov transition matrices."
"- wdro_rho_sensitivity_summary.csv summarizes TerminalLOH_total and objective/lambda by distance_mode and rho, including the count of states whose total TerminalLOH decreases relative to the previous rho."
];
fid = fopen(fullfile(config.outputDir, 'WDRO_README.txt'), 'w');
if fid < 0
    error('build_terminal_loh_wdro_from_joint_samples_h2:ReadmeOpenFailed', ...
        'Could not open WDRO_README.txt for writing.');
end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', txt);
end
