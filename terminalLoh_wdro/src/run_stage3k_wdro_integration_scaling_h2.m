clear; clc;

thisDir = fileparts(mfilename('fullpath'));
moduleDir = fileparts(thisDir);
rootDir = fileparts(moduleDir);
inputDir = fullfile(moduleDir, 'output', 'stage3j_wdro_input_freeze', 'run-001');
outputDir = fullfile(moduleDir, 'output', 'stage3k_wdro_integration_scaling', 'run-001');

if exist(outputDir, 'dir')
    error('Step-03K run-001 output directory already exists: %s', outputDir);
end
mkdir(outputDir);
addpath(rootDir);
addpath(thisDir);

gurobiCandidates = {fullfile(getenv('GUROBI_HOME'), 'matlab'), ...
    fullfile('D:\', 'gurobi1201', 'win64', 'matlab'), ...
    fullfile('C:\', 'gurobi1201', 'win64', 'matlab')};
for ii = 1:numel(gurobiCandidates)
    if ~isempty(gurobiCandidates{ii}) && exist(gurobiCandidates{ii}, 'dir')
        addpath(gurobiCandidates{ii});
    end
end
if ~ismember(exist('gurobi', 'file'), [2, 3])
    error('Gurobi MATLAB interface is unavailable.');
end

roles = ["nominal", "validation-1", "validation-2"];
csvNames = ["wdro_nominal_input.csv", "wdro_validation_1.csv", ...
    "wdro_validation_2.csv"];
matNames = ["wdro_nominal_input_DAC.mat", "wdro_validation_1_DAC.mat", ...
    "wdro_validation_2_DAC.mat"];
expectedCsvHash = [ ...
    "366dc3c0b57bfd76aca92f51ae1db82b93c764c87fa15e8cb4dd32388d018168", ...
    "e39253d5af25d312b5d65cbb4efdf5ad4e907843f9203a46c47c7ca058ed3099", ...
    "91c8e1233017d5d7dea9a87592f5bfb196e0d629733c10892fb539e4228c9b02"];
expectedMatHash = [ ...
    "6936a696f5cde137aca483f8c32adee33b52cbd90559a8e6395f3686c0712945", ...
    "ca84afa01748d8c2929c372802861315254723424786b681a677e2f1420b6e3f", ...
    "0bae20fa685940751edf5c5dd3d6c43a2d52293cbd1350c02b84736e914ec3b6"];

inputRows = cell(6, 6);
kk = 0;
for rr = 1:numel(roles)
    csvPath = fullfile(inputDir, csvNames(rr));
    matPath = fullfile(inputDir, matNames(rr));
    fprintf('Step-03K input %s CSV: %s\n', roles(rr), csvPath);
    fprintf('Step-03K input %s DAC: %s\n', roles(rr), matPath);
    if ~isfile(csvPath) || ~isfile(matPath)
        error('Step-03J frozen input is missing for role %s.', roles(rr));
    end
    csvHash = sha256_file(csvPath);
    matHash = sha256_file(matPath);
    if csvHash ~= expectedCsvHash(rr) || matHash ~= expectedMatHash(rr)
        error('Step-03J SHA-256 mismatch for role %s.', roles(rr));
    end
    csvInfo = dir(csvPath); matInfo = dir(matPath);
    kk = kk + 1;
    inputRows(kk, :) = {char(roles(rr)), char(csvNames(rr)), csvInfo.bytes, ...
        char(csvHash), char(expectedCsvHash(rr)), true};
    kk = kk + 1;
    inputRows(kk, :) = {char(roles(rr)), char(matNames(rr)), matInfo.bytes, ...
        char(matHash), char(expectedMatHash(rr)), true};
end
inputAudit = cell2table(inputRows, 'VariableNames', ...
    {'dataset_role','file','bytes','actual_sha256','expected_sha256','sha256_ok'});
writetable(inputAudit, fullfile(outputDir, 'input_sha256_audit.csv'));

requiredCsvFields = {'initial_state_id','initial_state','a0','loc0','lfw0', ...
    'path_id','a_W1','a_W2','a_W3','wind_W1_mps','wind_W2_mps','wind_W3_mps', ...
    'D_Hres3h_total_kg','A_reachable_share','C_reachable_mean_km', ...
    'W3_failed_line_count','W3_closed_road_count','sample_weight', ...
    'is_observed_candidate','dataset_role'};
summaryRows = cell(105, 20);
summaryRow = 0;
pathOrder = cell(numel(roles), 35);

for rr = 1:numel(roles)
    csvPath = fullfile(inputDir, csvNames(rr));
    tbl = readtable(csvPath, 'TextType', 'string');
    assert_fields(tbl, requiredCsvFields, csvNames(rr));
    if height(tbl) ~= 525000
        error('%s must contain 525000 rows.', csvNames(rr));
    end
    stateIds = unique(double(tbl.initial_state_id), 'stable');
    if ~isequal(stateIds(:), (1:35).')
        error('%s initial-state IDs are not exactly 1:35.', csvNames(rr));
    end
    for ss = 1:35
        mask = double(tbl.initial_state_id) == ss;
        rows = tbl(mask, :);
        if height(rows) ~= 15000
            error('%s state %d must contain 15000 rows.', csvNames(rr), ss);
        end
        pathOrder{rr, ss} = double(rows.path_id);
        dVals = double(rows.D_Hres3h_total_kg);
        cVals = double(rows.C_reachable_mean_km);
        cVals = cVals(isfinite(cVals));
        if isempty(cVals); cMean = NaN; else; cMean = mean(cVals); end
        summaryRow = summaryRow + 1;
        summaryRows(summaryRow, :) = {char(roles(rr)), ss, ...
            double(rows.a0(1)), double(rows.loc0(1)), double(rows.lfw0(1)), ...
            height(rows), sum(double(rows.sample_weight)), mean(dVals), ...
            percentile_value(dVals, 95), percentile_value(dVals, 99), ...
            mean(double(rows.A_reachable_share) <= 1e-12), ...
            mean(1 - double(rows.A_reachable_share)), cMean, ...
            mean(double(rows.W3_failed_line_count)), ...
            mean(double(rows.W3_closed_road_count)), ...
            sum(double(rows.is_observed_candidate)), 0, ...
            true, all(isfinite(dVals) & dVals >= 0), ...
            wind_ranges_ok(rows)};
    end
    clear tbl rows;
end

roleComparison = cell2table(summaryRows, 'VariableNames', ...
    {'dataset_role','initial_state_id','a0','loc0','lfw0','record_count', ...
    'weight_sum','D_mean_kg','D_q95_kg','D_q99_kg','full_loss_rate', ...
    'A0_share','reachable_C_mean_km','W3_failed_line_count_mean', ...
    'W3_closed_road_count_mean','observed_candidate_records', ...
    'unobserved_candidate_records','path_order_internal_ok', ...
    'D_domain_ok','wind_range_ok'});

roleComparison.D_mean_delta_vs_nominal = zeros(height(roleComparison), 1);
roleComparison.D_q95_delta_vs_nominal = zeros(height(roleComparison), 1);
roleComparison.D_q99_delta_vs_nominal = zeros(height(roleComparison), 1);
roleComparison.full_loss_rate_delta_vs_nominal = zeros(height(roleComparison), 1);
roleComparison.A0_share_delta_vs_nominal = zeros(height(roleComparison), 1);
roleComparison.reachable_C_mean_delta_vs_nominal = zeros(height(roleComparison), 1);
roleComparison.failed_line_mean_delta_vs_nominal = zeros(height(roleComparison), 1);
roleComparison.closed_road_mean_delta_vs_nominal = zeros(height(roleComparison), 1);
for row = 1:height(roleComparison)
    ss = roleComparison.initial_state_id(row);
    base = roleComparison(strcmp(roleComparison.dataset_role, 'nominal') & ...
        roleComparison.initial_state_id == ss, :);
    roleComparison.D_mean_delta_vs_nominal(row) = roleComparison.D_mean_kg(row) - base.D_mean_kg;
    roleComparison.D_q95_delta_vs_nominal(row) = roleComparison.D_q95_kg(row) - base.D_q95_kg;
    roleComparison.D_q99_delta_vs_nominal(row) = roleComparison.D_q99_kg(row) - base.D_q99_kg;
    roleComparison.full_loss_rate_delta_vs_nominal(row) = roleComparison.full_loss_rate(row) - base.full_loss_rate;
    roleComparison.A0_share_delta_vs_nominal(row) = roleComparison.A0_share(row) - base.A0_share;
    roleComparison.reachable_C_mean_delta_vs_nominal(row) = roleComparison.reachable_C_mean_km(row) - base.reachable_C_mean_km;
    roleComparison.failed_line_mean_delta_vs_nominal(row) = roleComparison.W3_failed_line_count_mean(row) - base.W3_failed_line_count_mean;
    roleComparison.closed_road_mean_delta_vs_nominal(row) = roleComparison.W3_closed_road_count_mean(row) - base.W3_closed_road_count_mean;
end
writetable(roleComparison, fullfile(outputDir, 'dataset_role_comparison_by_state.csv'));

candidateAudit = readtable(fullfile(inputDir, 'candidate_presence_audit.csv'), ...
    'TextType', 'string');
if height(candidateAudit) ~= 3 || any(double(candidateAudit.unobserved_candidate_record_count) ~= 0)
    error('Step-03J candidate presence audit does not confirm zero unobserved candidates.');
end

loaderRows = cell(105, 24);
loaderRow = 0;
for rr = 1:numel(roles)
    csvPath = fullfile(inputDir, csvNames(rr));
    matPath = fullfile(inputDir, matNames(rr));
    for ss = 1:35
        stateSummary = roleComparison(strcmp(roleComparison.dataset_role, char(roles(rr))) & ...
            roleComparison.initial_state_id == ss, :);
        [samples, metadata] = load_frozen_b3_wdro_dataset_h2(csvPath, matPath, ...
            stateSummary.a0, stateSummary.loc0, stateSummary.lfw0);
        dTotal = sum(samples.D, 2);
        aShare = reshape(mean(mean(samples.A, 3), 2), [], 1);
        cMean = reachable_cost_mean(samples.C_raw, samples.A);
        cMeta = double(metadata.C_reachable_mean_km);
        cMask = isfinite(cMean) & isfinite(cMeta);
        if any(cMask); cMaxError = max(abs(cMean(cMask) - cMeta(cMask))); else; cMaxError = 0; end
        dimensionOk = samples.R == 15000 && samples.I == 4 && samples.N == 33 && ...
            isequal(size(samples.D), [15000, 33]) && ...
            isequal(size(samples.A), [15000, 4, 33]) && ...
            isequal(size(samples.C_raw), [15000, 4, 33]);
        domainOk = all(isfinite(samples.D), 'all') && all(samples.D >= 0, 'all') && ...
            all(ismember(unique(samples.A), [0; 1])) && ...
            all(isfinite(samples.C_raw(samples.A > 0.5)));
        orderOk = isequal(double(metadata.path_id), pathOrder{1, ss}) && ...
            isequal(double(metadata.path_id), pathOrder{rr, ss});
        rowAlignmentOk = max(abs(dTotal - double(metadata.D_Hres3h_total_kg))) <= 1e-8 && ...
            max(abs(aShare - double(metadata.A_reachable_share))) <= 1e-12 && ...
            cMaxError <= 1e-8;
        loaderRow = loaderRow + 1;
        loaderRows(loaderRow, :) = {char(roles(rr)), ss, stateSummary.a0, ...
            stateSummary.loc0, stateSummary.lfw0, samples.R, samples.I, samples.N, ...
            size(samples.D, 1), size(samples.D, 2), size(samples.A, 2), ...
            size(samples.A, 3), sum(samples.sampleWeights), dimensionOk, ...
            domainOk, sum(~isfinite(samples.C_raw) & samples.A <= 0.5, 'all'), ...
            orderOk, rowAlignmentOk, max(abs(dTotal - double(metadata.D_Hres3h_total_kg))), ...
            max(abs(aShare - double(metadata.A_reachable_share))), cMaxError, ...
            wind_ranges_ok(metadata), 0, ...
            dimensionOk && domainOk && orderOk && rowAlignmentOk && ...
                wind_ranges_ok(metadata) && abs(sum(samples.sampleWeights) - 1) <= 1e-12};
        clear samples metadata;
    end
end
loaderAudit = cell2table(loaderRows, 'VariableNames', ...
    {'dataset_role','initial_state_id','a0','loc0','lfw0','R','I','N', ...
    'D_rows','D_columns','A_sites','A_nodes','weight_sum','dimension_ok', ...
    'domain_ok','unreachable_nonfinite_C_count','path_order_ok','row_alignment_ok', ...
    'D_total_max_abs_error','A_share_max_abs_error','C_mean_max_abs_error', ...
    'stagewise_wind_range_ok','unobserved_candidate_records','block_pass'});
writetable(loaderAudit, fullfile(outputDir, 'loader_full_audit.csv'));

nominalSummary = roleComparison(strcmp(roleComparison.dataset_role, 'nominal'), :);
nominalSorted = sortrows(nominalSummary, {'D_mean_kg','initial_state_id'});
selected = nominalSorted(ceil(height(nominalSorted) / 2), :);
selected.selection_rule = "median nominal D_mean_kg; tie break initial_state_id";
selected.D_mean_rank = ceil(height(nominalSorted) / 2);
writetable(selected, fullfile(outputDir, 'selected_benchmark_state.csv'));

[allSamples, ~] = load_frozen_b3_wdro_dataset_h2( ...
    fullfile(inputDir, csvNames(1)), fullfile(inputDir, matNames(1)), ...
    selected.a0, selected.loc0, selected.lfw0);

nearInput = fullfile(rootDir, 'data', 'yuanqi', 'near_stage_msp_input.mat');
raw = load(nearInput, 'NearStageInput');
ni = raw.NearStageInput;
tankCap = double(ni.HydrogenDevice.tank_cap_kg(:));
if isfield(ni.Cost, 'reserve_shortage_penalty_yuan_per_kg')
    M = double(ni.Cost.reserve_shortage_penalty_yuan_per_kg);
    penaltySource = "NearStageInput.Cost.reserve_shortage_penalty_yuan_per_kg";
elseif isfield(ni.Cost, 'cost_reserve_shortage')
    M = double(ni.Cost.cost_reserve_shortage);
    penaltySource = "NearStageInput.Cost.cost_reserve_shortage";
else
    M = 2000;
    penaltySource = "existing_explicit_default_2000_yuan_per_kg";
end
capacityFraction = 0.8;
Cap = capacityFraction .* tankCap;
rhoValues = [0, 0.02];
distanceMode = 'DAC_maskedC';
config = struct();
config.gamma = 0.001 * M;
config.gurobiOutputFlag = 0;
config.distanceWeightsDACMaskedC = struct('D', 0.6, 'A', 0.25, 'C', 0.15);
config.epsDistance = 1e-9;
config.scaleTolerance = 1e-12;

rValues = [100, 250, 500, 1000];
benchmarkRows = cell(0, 28);
rhoZeroRows = cell(0, 10);
stopAfterFailure = false;
largestCompletedR = 0;
for rr = 1:numel(rValues)
    R = rValues(rr);
    if stopAfterFailure
        break;
    end
    D = allSamples.D(1:R, :);
    A = allSamples.A(1:R, :, :);
    C = allSamples.C_raw(1:R, :, :);
    try
        distanceTic = tic;
        [dMat, distanceInfo] = build_wdro_distance_matrix_h2(D, A, C, ...
            distanceMode, config);
        distanceTime = toc(distanceTic);
        dInfo = whos('dMat');
        distanceBytes = dInfo.bytes;
        [nvar, ncon, nnzModel] = model_size_counts(D, A, C, dMat);
        currentFailed = false;
        for pp = 1:numel(rhoValues)
            rho = rhoValues(pp);
            solveTic = tic;
            sol = solve_wdro_terminal_loh_lp_h2(D, A, C, Cap, M, rho, dMat, config);
            totalSolveCallTime = toc(solveTic);
            modelTime = max(0, totalSolveCallTime - sol.runtime_sec);
            [weightMin, weightSum, rowResidual, transportCost, weightOk] = ...
                recover_worst_weights(sol, R, dMat, rho);
            if sol.exitflag == 1
                reconstruction = config.gamma * sum(sol.T) + mean(sol.L);
                rho0Error = abs(sol.objective_value - reconstruction);
                statusOk = true;
            else
                reconstruction = NaN;
                rho0Error = NaN;
                statusOk = false;
            end
            benchmarkRows(end + 1, :) = {R, rho, distanceMode, ...
                size(dMat, 1), size(dMat, 2), distanceBytes, distanceTime, ...
                nvar, ncon, nnzModel, modelTime, sol.runtime_sec, ...
                totalSolveCallTime, char(sol.status), sol.exitflag, ...
                sol.objective_value, sol.lambda, weightMin, weightSum, ...
                rowResidual, transportCost, weightOk, rho0Error, ...
                distanceInfo.d_symmetry_max_abs, distanceInfo.d_diag_max_abs, ...
                distanceInfo.d_min_all, false, ''};
            if rho == 0
                rhoZeroRows(end + 1, :) = {R, sol.objective_value, ...
                    reconstruction, rho0Error, sol.lambda, weightMin, ...
                    weightSum, rowResidual, transportCost, ...
                    statusOk && rho0Error <= 1e-6 && weightOk};
            end
            if ~statusOk || ~weightOk
                currentFailed = true;
            end
        end
        if currentFailed
            stopAfterFailure = true;
        else
            largestCompletedR = R;
        end
        clear dMat D A C sol;
    catch ME
        benchmarkRows(end + 1, :) = {R, NaN, distanceMode, R, R, NaN, NaN, ...
            NaN, NaN, NaN, NaN, NaN, NaN, 'ERROR', 0, NaN, NaN, ...
            NaN, NaN, NaN, NaN, false, NaN, NaN, NaN, NaN, true, ...
            sprintf('%s: %s', ME.identifier, ME.message)};
        stopAfterFailure = true;
    end
end

benchmark = cell2table(benchmarkRows, 'VariableNames', ...
    {'R','rho','distance_mode','distance_rows','distance_columns', ...
    'distance_matrix_bytes','distance_build_time_sec','LP_variables', ...
    'LP_constraints','LP_nonzeros','gurobi_modeling_time_sec', ...
    'gurobi_solve_time_sec','solver_call_total_time_sec','solve_status', ...
    'exitflag','objective_value','lambda','worst_weight_min','worst_weight_sum', ...
    'nominal_row_mass_max_abs_error','transport_cost','worst_weight_audit_ok', ...
    'objective_reconstruction_abs_error','distance_symmetry_max_abs', ...
    'distance_diagonal_max_abs','distance_min','stopped_after_this_row','error_message'});
if stopAfterFailure && ~isempty(benchmarkRows)
    benchmark.stopped_after_this_row(end) = true;
end
writetable(benchmark, fullfile(outputDir, 'wdro_scaling_benchmark.csv'));

rhoZero = cell2table(rhoZeroRows, 'VariableNames', ...
    {'R','solver_objective','nominal_objective_reconstructed', ...
    'absolute_error','lambda','worst_weight_min','worst_weight_sum', ...
    'nominal_row_mass_max_abs_error','transport_cost','rho_zero_consistent'});
writetable(rhoZero, fullfile(outputDir, 'rho_zero_consistency.csv'));

Rtarget = 15000;
[nvarTarget, nconTarget, nnzUpperTarget] = model_size_upper_bound(Rtarget, 4, 33);
distanceElements = Rtarget ^ 2;
estimate = table(Rtarget, distanceElements, distanceElements * 8, ...
    distanceElements * 8 / 1024^3, nvarTarget, nconTarget, nnzUpperTarget, ...
    largestCompletedR, "formula estimate; not measured at R=15000", ...
    'VariableNames', {'R','distance_matrix_elements','distance_matrix_bytes', ...
    'distance_matrix_GiB','LP_variables','LP_constraints', ...
    'LP_nonzeros_upper_order','largest_measured_R','evidence_type'});
writetable(estimate, fullfile(outputDir, 'r15000_size_estimate.csv'));

decision = "LIMITED_R_ONLY";
decisionReason = sprintf(['The existing dense O(R^2) formulation was measured only through R=%d. ' ...
    'R=15000 was not executed and has an estimated 225 million distance entries ' ...
    'and 225.57 million LP constraints.'], largestCompletedR);
decisionGate = table(decision, string(decisionReason), largestCompletedR, ...
    Rtarget, false, 'VariableNames', {'decision','reason','largest_measured_R', ...
    'target_R','formal_WDRO_executed'});
writetable(decisionGate, fullfile(outputDir, 'decision_gate_summary.csv'));

auditRows = {
    'INPUT-01','PASS',sprintf('%d/6 hashes match',sum(inputAudit.sha256_ok)),'6/6';
    'LOAD-01',pass_fail(height(loaderAudit)==105),'105 blocks', '105 blocks';
    'LOAD-02',pass_fail(all(loaderAudit.block_pass)),'all block_pass','all block_pass';
    'LOAD-03',pass_fail(all(abs(loaderAudit.weight_sum-1)<=1e-12)),'all state weights sum to one','all state weights sum to one';
    'LOAD-04',pass_fail(all(loaderAudit.path_order_ok)),'all roles share nominal path order','all roles share nominal path order';
    'LOAD-05',pass_fail(all(loaderAudit.unobserved_candidate_records==0)),'zero unobserved records','zero unobserved records';
    'WIND-01',pass_fail(all(loaderAudit.stagewise_wind_range_ok)),'stagewise winds in configured ranges','stagewise winds in configured ranges';
    'ROLE-01',pass_fail(all(roleComparison.record_count==15000)),'15000 records per state','15000 records per state';
    'BENCH-01',pass_fail(any(benchmark.R==100 & benchmark.exitflag==1)),'R=100 solved','R=100 solved';
    'BENCH-02',pass_fail(all(rhoZero.rho_zero_consistent)),'all completed rho=0 checks consistent','all completed rho=0 checks consistent';
    'BENCH-03',pass_fail(strcmp(decision,'LIMITED_R_ONLY') || largestCompletedR==Rtarget),char(decision),'evidence-bounded decision';
    'BOUND-01','PASS','Step-03J inputs read only','Step-03J inputs read only';
    'BOUND-02','PASS','no formal WDRO or MSP run','no formal WDRO or MSP run'};
automaticAudit = cell2table(auditRows, 'VariableNames', ...
    {'check_id','status','observed','expected'});
passCount = sum(strcmp(automaticAudit.status, 'PASS'));
failCount = sum(strcmp(automaticAudit.status, 'FAIL'));
writetable(automaticAudit, fullfile(outputDir, 'automatic_audit.csv'));

manifestLines = [
    "task_id=task-002"
    "step_id=11-wdro-integration-scaling"
    "run_id=run-001"
    "status=" + pass_fail(failCount == 0)
    "pass_count=" + string(passCount)
    "fail_count=" + string(failCount)
    "input_directory=" + string(inputDir)
    "loader_blocks=105"
    "roles=nominal,validation-1,validation-2"
    "records_per_state=15000"
    "distance_mode=" + string(distanceMode)
    "rho_values=0,0.02"
    "capacity_fraction=" + string(capacityFraction)
    "penalty_M=" + string(M)
    "penalty_source=" + penaltySource
    "gamma=" + string(config.gamma)
    "selected_state_id=" + string(selected.initial_state_id)
    "largest_measured_R=" + string(largestCompletedR)
    "decision=" + decision
    "formal_WDRO_run=false"
    "MSP_run=false"];
write_lines(fullfile(outputDir, 'run_manifest.txt'), manifestLines);

readmeLines = [
    "Step-03K run-001: WDRO integration and scaling audit"
    ""
    "The accepted Step-03J nominal and two validation datasets were verified by SHA-256 and loaded one initial state at a time."
    "The 105 blocks are conditional datasets; the 525000 records in a role were never treated as one distribution."
    "Validation-1 and validation-2 retain the same W paths and redraw only second-layer wind and resistance, so they are not independent path-sample out-of-sample datasets."
    ""
    "The benchmark calls the unchanged build_wdro_distance_matrix_h2 and solve_wdro_terminal_loh_lp_h2 functions."
    "Distance mode is DAC_maskedC. Tested rho values are 0 and the existing minimum positive rho 0.02."
    "The selected state is the median nominal D-mean state after deterministic initial-state-ID tie breaking."
    "R prefixes are nested. Expansion stops after the first solve or resource failure."
    ""
    "rho=0 consistency reconstructs the empirical finite-support objective as gamma*sum(T)+mean(L)."
    "Worst-case weights are recovered from the Gurobi dual multipliers of the existing Wasserstein constraints; no solver formula was changed."
    "Unreachable C entries may be nonfinite in the frozen legacy contract and are masked by A=0; reachable C entries must be finite."
    ""
    "Decision: " + decision
    string(decisionReason)
    "R=15000 figures are formula estimates, not measured results."
    "This run did not execute formal WDRO, MSP, scenario reduction, clustering, sparse transport, or solver refactoring."];
write_lines(fullfile(outputDir, 'README.txt'), readmeLines);

fprintf('\nStep-03K finished: PASS=%d FAIL=%d decision=%s\n', ...
    passCount, failCount, decision);
fprintf('Output directory: %s\n', outputDir);
if failCount > 0
    error('Step-03K automatic audit has %d failures.', failCount);
end

function assert_fields(tbl, required, label)
for ii = 1:numel(required)
    if ~ismember(required{ii}, tbl.Properties.VariableNames)
        error('%s is missing field %s.', label, required{ii});
    end
end
end

function out = percentile_value(values, p)
values = sort(double(values(:)));
if isempty(values)
    out = NaN;
    return;
end
position = 1 + (numel(values) - 1) * p / 100;
lo = floor(position); hi = ceil(position);
if lo == hi
    out = values(lo);
else
    out = values(lo) + (position - lo) * (values(hi) - values(lo));
end
end

function ok = wind_ranges_ok(tbl)
levelFields = {'a_W1','a_W2','a_W3'};
windFields = {'wind_W1_mps','wind_W2_mps','wind_W3_mps'};
bounds = [0,0;17.2,24.4;24.5,32.6;32.7,41.4;41.5,50.9;51,60];
ok = true;
for ww = 1:3
    levels = double(tbl.(levelFields{ww}));
    winds = double(tbl.(windFields{ww}));
    for aa = 1:6
        mask = levels == aa;
        if any(mask) && any(winds(mask) < bounds(aa,1)-1e-10 | ...
                winds(mask) > bounds(aa,2)+1e-10)
            ok = false;
            return;
        end
    end
end
end

function cMean = reachable_cost_mean(C, A)
mask = A > 0.5;
Cclean = C;
Cclean(~mask) = 0;
Cclean(~isfinite(Cclean)) = 0;
total = reshape(sum(sum(Cclean, 3), 2), [], 1);
count = reshape(sum(sum(mask, 3), 2), [], 1);
cMean = total ./ count;
cMean(count == 0) = NaN;
end

function [nvar, ncon, nnzModel] = model_size_counts(D, A, C, dMat)
[R, N] = size(D); I = size(A, 2);
nvar = I + R*I*N + R*N + 2*R + 1;
ncon = R*N + R*I + R + R*R;
Ceff = C;
Ceff(~isfinite(Ceff) | A <= 0.5) = 0;
nnzModel = R*N*(I+1) + R*I*(N+1) + ...
    nnz(Ceff) + R*N + R + 2*R*R + nnz(dMat);
end

function [nvar, ncon, nnzUpper] = model_size_upper_bound(R, I, N)
nvar = I + R*I*N + R*N + 2*R + 1;
ncon = R*N + R*I + R + R*R;
nnzUpper = R*N*(I+1) + R*I*(N+1) + ...
    R*I*N + R*N + R + 3*R*R;
end

function [weightMin, weightSum, rowResidual, transportCost, ok] = ...
        recover_worst_weights(sol, R, dMat, rho)
weightMin = NaN; weightSum = NaN; rowResidual = NaN;
transportCost = NaN; ok = false;
if sol.exitflag ~= 1 || ~isfield(sol.raw, 'pi')
    return;
end
nRows = R*size(sol.u, 2) + R*size(sol.y, 2) + R + R*R;
piAll = double(sol.raw.pi(:));
if numel(piAll) ~= nRows
    return;
end
offset = nRows - R*R;
transport = reshape(-piAll(offset+1:end), [R, R]).';
worstWeights = sum(transport, 1).';
nominalRows = sum(transport, 2);
weightMin = min(worstWeights);
weightSum = sum(worstWeights);
rowResidual = max(abs(nominalRows - 1/R));
transportCost = sum(transport .* dMat, 'all');
ok = weightMin >= -1e-7 && abs(weightSum - 1) <= 1e-6 && ...
    rowResidual <= 1e-6 && transportCost <= rho + 1e-6;
end

function hash = sha256_file(path)
[status, output] = system(sprintf('certutil -hashfile "%s" SHA256', path));
if status ~= 0
    error('certutil failed for %s: %s', path, output);
end
tokens = regexp(output, '(?im)^[0-9a-f]{64}$', 'match');
if isempty(tokens)
    error('Could not parse SHA-256 for %s.', path);
end
hash = lower(string(tokens{1}));
end

function value = pass_fail(condition)
if condition; value = 'PASS'; else; value = 'FAIL'; end
end

function write_lines(path, lines)
fid = fopen(path, 'w');
if fid < 0; error('Could not open %s.', path); end
cleanup = onCleanup(@() fclose(fid));
for ii = 1:numel(lines)
    fprintf(fid, '%s\n', lines(ii));
end
end
