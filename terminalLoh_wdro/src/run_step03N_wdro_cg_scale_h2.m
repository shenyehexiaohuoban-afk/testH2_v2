clear; clc;

thisDir = fileparts(mfilename('fullpath'));
moduleDir = fileparts(thisDir);
rootDir = fileparts(moduleDir);
inputDir = fullfile(moduleDir, 'output', 'stage3j_wdro_input_freeze', 'run-001');
oldResultDir = fullfile(rootDir, 'results', ...
    'task-002-stage2b-b3-smoke', '13-wdro-constraint-generation', 'run-001');
outputDir = fullfile(rootDir, 'results', ...
    'task-002-stage2b-b3-smoke', '14-wdro-constraint-generation-scale', 'run-001');
localOutputDir = fullfile(moduleDir, 'output', ...
    'stage2_foundation_step03N_wdro_constraint_generation_scale', 'run-001');

if exist(outputDir, 'dir') || exist(localOutputDir, 'dir')
    error('Step-03N output directory already exists; use a new run number.');
end
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
    error('Step-03N requires the existing Gurobi MATLAB interface.');
end

expectedHead = "dbbd04f7c261a018fb248247966e557424b05824";
[gitStatus, gitHead] = system('git rev-parse HEAD');
if gitStatus ~= 0 || lower(strtrim(string(gitHead))) ~= expectedHead
    error('Step-03N must start from baseline commit %s.', expectedHead);
end

nominalCsv = fullfile(inputDir, 'wdro_nominal_input.csv');
nominalMat = fullfile(inputDir, 'wdro_nominal_input_DAC.mat');
expectedCsvHash = "366dc3c0b57bfd76aca92f51ae1db82b93c764c87fa15e8cb4dd32388d018168";
expectedMatHash = "6936a696f5cde137aca483f8c32adee33b52cbd90559a8e6395f3686c0712945";
csvHashBefore = sha256_file(nominalCsv);
matHashBefore = sha256_file(nominalMat);
if csvHashBefore ~= expectedCsvHash || matHashBefore ~= expectedMatHash
    error('Step-03J nominal frozen-file SHA-256 mismatch.');
end

protectedFiles = [ ...
    string(fullfile(thisDir, 'build_wdro_distance_matrix_h2.m')); ...
    string(fullfile(thisDir, 'solve_wdro_terminal_loh_lp_h2.m')); ...
    string(fullfile(thisDir, 'load_frozen_b3_wdro_dataset_h2.m')); ...
    string(fullfile(thisDir, 'run_terminal_loh_wdro_preview_h2.m'))];
expectedProtectedHashes = [ ...
    "e1dd61fe85f0ea9cc6e0919b713b2ddee1af46271cc52ecf4941ce4f5998a0fe"; ...
    "2393abcb1627ef77564402843779d38b7a0c2b5dc0d6521629f9bf1dad253b00"; ...
    "0ee23259dfe3393860e0d916efad59cc22aa6cd1ed33cba656ea5864981a7c83"; ...
    "ef895fa5833906de56a9f9dce6b6335417bd0b276688166bbedeFC19A8C3D34D"];
expectedProtectedHashes = lower(expectedProtectedHashes);
protectedBefore = strings(numel(protectedFiles), 1);
for ii = 1:numel(protectedFiles)
    protectedBefore(ii) = sha256_file(char(protectedFiles(ii)));
end
if any(protectedBefore ~= expectedProtectedHashes)
    error('A protected WDRO source hash differs from the accepted baseline.');
end

if ~isfile(fullfile(oldResultDir, 'step03M_full_vs_constraint_generation.csv'))
    error('Step-03M archived regression result is missing.');
end
oldCases = readtable(fullfile(oldResultDir, ...
    'step03M_full_vs_constraint_generation.csv'), 'TextType', 'string');
oldCasesHashBefore = sha256_file(fullfile(oldResultDir, ...
    'step03M_full_vs_constraint_generation.csv'));
selected = readtable(fullfile(oldResultDir, 'step03M_selected_states.csv'), ...
    'TextType', 'string');
requiredSelected = {'initial_state_id','a0','loc0','lfw0','complexity_label'};
for ii = 1:numel(requiredSelected)
    if ~ismember(requiredSelected{ii}, selected.Properties.VariableNames)
        error('Step-03M selected-state file is missing %s.', requiredSelected{ii});
    end
end
if height(selected) ~= 3 || ~isequal(sort(double(selected.initial_state_id)), [7;18;30])
    error('Step-03M representative states are not the accepted 7/18/30 set.');
end

fprintf('Step-03N nominal CSV: %s\n', nominalCsv);
fprintf('Step-03N nominal DAC: %s\n', nominalMat);
fprintf('Step-03N selected states: %s\n', join(string(selected.initial_state_id.'), ','));

Rtarget = 2000;
I = 4;
N = 33;
[targetVars, targetConstraints, targetNnz, targetEstimateBytes] = ...
    full_model_estimate(Rtarget, I, N);
[memBefore, availableBytes] = memory_snapshot();
safeMemoryLimitBytes = 0.50 * availableBytes;
fullReferenceSafe = targetEstimateBytes <= safeMemoryLimitBytes;
if fullReferenceSafe
    fullReferenceGate = "FULL_R2_REFERENCE_ATTEMPTED";
else
    fullReferenceGate = "FULL_R2_REFERENCE_NOT_RUN_RESOURCE_LIMIT";
end
fprintf('R=2000 estimate: vars=%d constraints=%d nnz=%d conservative_peak_mb=%.3f available_mb=%.3f safe=%d\n', ...
    targetVars, targetConstraints, targetNnz, targetEstimateBytes/1024^2, ...
    availableBytes/1024^2, fullReferenceSafe);

raw = load(fullfile(rootDir, 'data', 'yuanqi', 'near_stage_msp_input.mat'), ...
    'NearStageInput');
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
Cap = 0.8 .* tankCap;
rhoValues = [0, 0.02];
config = struct();
config.gamma = 0.001 * M;
config.gurobiOutputFlag = 0;
config.gurobiTimeLimit = 300;
config.distanceWeightsDACMaskedC = struct('D', 0.6, 'A', 0.25, 'C', 0.15);
config.epsDistance = 1e-9;
config.scaleTolerance = 1e-12;
config.violationTolerance = 1e-8;
config.gurobiFeasibilityTol = 1e-9;
config.gurobiOptimalityTol = 1e-9;
config.blockSize = 100;
config.independentScanBlockSize = 73;
config.maxIterations = 200;

caseRows = cell(0, 58);
historyTables = cell(0, 1);
fullReferenceStillAvailable = fullReferenceSafe;
caseNumber = 0;
for stateRow = 1:height(selected)
    state = selected(stateRow, :);
    fprintf('\nStep-03N loading %s state %d (a0=%d loc0=%d lfw0=%d)\n', ...
        char(state.complexity_label), state.initial_state_id, ...
        state.a0, state.loc0, state.lfw0);
    [samples, metadata] = load_frozen_b3_wdro_dataset_h2( ...
        nominalCsv, nominalMat, state.a0, state.loc0, state.lfw0);
    if any(double(metadata.initial_state_id) ~= state.initial_state_id)
        error('Frozen loader state identity differs from Step-03M selection.');
    end

    for R = [1000, 2000]
        D = samples.D(1:R, :);
        A = samples.A(1:R, :, :);
        C = samples.C_raw(1:R, :, :);
        dMat = [];
        distanceInfo = struct('D_scale', NaN, 'A_scale', NaN, 'C_scale', NaN);
        fullDistanceTime = NaN;
        distanceBytes = NaN;
        if R == Rtarget && fullReferenceStillAvailable
            distanceTic = tic;
            [dMat, distanceInfo] = build_wdro_distance_matrix_h2( ...
                D, A, C, 'DAC_maskedC', config);
            fullDistanceTime = toc(distanceTic);
            distanceBytes = whos_bytes('dMat');
        end

        for rho = rhoValues
            caseNumber = caseNumber + 1;
            isRegression = R == 1000;
            fprintf('Case %d/12: %s R=%d rho=%.2f\n', caseNumber, ...
                char(state.complexity_label), R, rho);

            [mem0, ~] = memory_snapshot();
            cgTic = tic;
            cg = solve_wdro_terminal_loh_lp_constraint_generation_h2( ...
                D, A, C, Cap, M, rho, config);
            cgTotalTime = toc(cgTic);
            [mem1, ~] = memory_snapshot();
            observedCgPeak = max(mem0, mem1);

            fullStatus = "NOT_RUN";
            fullObj = NaN;
            fullT = NaN(4, 1);
            fullViolation = NaN;
            fullTotalTime = NaN;
            fullSolveTime = NaN;
            fullModelTime = NaN;
            fullPeak = NaN;
            objErr = NaN;
            tErr = NaN;
            fullFeasible = false;
            if R == Rtarget && fullReferenceStillAvailable
                [mem2, ~] = memory_snapshot();
                fullTic = tic;
                try
                    full = solve_full_with_tight_env(D, A, C, Cap, M, ...
                        rho, dMat, config);
                    fullTotalTime = toc(fullTic);
                    [mem3, ~] = memory_snapshot();
                    fullPeak = max(mem2, mem3);
                    fullStatus = full.status;
                    if full.exitflag == 1
                        fullObj = full.objective_value;
                        fullT = full.T;
                        fullViolation = full_solution_max_violation(full, dMat, 100);
                        fullSolveTime = full.runtime_sec;
                        fullModelTime = max(0, fullTotalTime - fullSolveTime);
                        fullFeasible = fullViolation <= 1e-8;
                        objErr = abs(fullObj - cg.objective_value);
                        tErr = max(abs(fullT - cg.T));
                    end
                    if full.exitflag ~= 1
                        fullReferenceStillAvailable = false;
                        fullReferenceGate = "FULL_R2_REFERENCE_NOT_RUN_RESOURCE_LIMIT";
                    end
                catch ME
                    fullTotalTime = toc(fullTic);
                    fullStatus = "RESOURCE_ERROR";
                    fullReferenceStillAvailable = false;
                    fullReferenceGate = "FULL_R2_REFERENCE_NOT_RUN_RESOURCE_LIMIT";
                    fprintf('Full R^2 reference stopped: %s\n', ME.message);
                end
            end

            independentViolation = cg.final_independent_scan_max_violation;
            regressionObjErr = NaN;
            regressionTErr = NaN;
            regressionPass = true;
            if isRegression
                old = oldCases(double(oldCases.initial_state_id) == state.initial_state_id & ...
                    double(oldCases.R) == 1000 & abs(double(oldCases.rho) - rho) <= 1e-12, :);
                if height(old) ~= 1
                    error('Step-03M regression row is missing for state %d rho %.2f.', ...
                        state.initial_state_id, rho);
                end
                regressionObjErr = abs(cg.objective_value - double(old.cg_objective));
                oldT = [double(old.cg_T1), double(old.cg_T2), ...
                    double(old.cg_T3), double(old.cg_T4)].';
                regressionTErr = max(abs(cg.T - oldT));
                regressionPass = regressionObjErr <= 1e-8 && regressionTErr <= 1e-7;
            end

            targetPass = cg.exitflag == 1 && cg.converged && ...
                independentViolation <= 1e-8 && ...
                all(isfinite(cg.T)) && all(cg.T >= -1e-8) && ...
                all(cg.T <= Cap + 1e-7) && all(isfinite(cg.objective_value));
            directPass = true;
            if R == Rtarget && ~strcmp(fullStatus, 'NOT_RUN')
                directPass = strcmp(fullStatus, 'OPTIMAL') && fullFeasible && ...
                    objErr <= 1e-8 && tErr <= 1e-7;
            end
            casePass = targetPass && regressionPass && directPass;

            hist = cg.history;
            hist.complexity_label = repmat(state.complexity_label, height(hist), 1);
            hist.initial_state_id = repmat(state.initial_state_id, height(hist), 1);
            hist.a0 = repmat(state.a0, height(hist), 1);
            hist.loc0 = repmat(state.loc0, height(hist), 1);
            hist.lfw0 = repmat(state.lfw0, height(hist), 1);
            hist.R = repmat(R, height(hist), 1);
            hist.rho = repmat(rho, height(hist), 1);
            hist = movevars(hist, {'complexity_label','initial_state_id','a0', ...
                'loc0','lfw0','R','rho'}, 'Before', 1);
            historyTables{end + 1, 1} = hist; %#ok<AGROW>

            caseRows(end + 1, :) = { ...
                char(state.complexity_label), state.initial_state_id, state.a0, ...
                state.loc0, state.lfw0, R, rho, char(fullReferenceGate), ...
                char(fullStatus), char(cg.status), cg.exitflag, ...
                cg.T(1), cg.T(2), cg.T(3), cg.T(4), cg.objective_value, ...
                cg.lambda, height(cg.history), R, cg.final_active_constraints, ...
                cg.active_constraint_ratio, cg.total_modeling_time_sec, ...
                cg.total_solve_time_sec, cg.total_separation_time_sec, ...
                cg.final_independent_scan_time_sec, cgTotalTime, ...
                observedCgPeak / 1024^2, fullPeak / 1024^2, ...
                fullT(1), fullT(2), fullT(3), fullT(4), fullObj, ...
                fullModelTime, fullSolveTime, fullTotalTime, distanceBytes, ...
                fullDistanceTime, fullViolation, objErr, tErr, ...
                independentViolation, regressionObjErr, regressionTErr, ...
                targetPass, regressionPass, directPass, casePass, ...
                targetVars, targetConstraints, targetNnz, ...
                targetEstimateBytes / 1024^2, availableBytes / 1024^2, ...
                fullReferenceSafe, fullReferenceStillAvailable, ...
                cg.final_active_constraints / (R * R), ...
                cg.last_scan_max_violation, cg.final_independent_violated_r_count};

            if ~casePass
                error('Step-03N acceptance failed for state %d R=%d rho=%.2f.', ...
                    state.initial_state_id, R, rho);
            end
        end
        clear dMat D A C;
    end
    clear samples metadata;
end

caseTable = cell2table(caseRows, 'VariableNames', { ...
    'complexity_label','initial_state_id','a0','loc0','lfw0','R','rho', ...
    'full_reference_gate','full_status','cg_status','cg_exitflag', ...
    'cg_T1','cg_T2','cg_T3','cg_T4','cg_objective','cg_lambda', ...
    'cg_iterations','initial_active_constraints','cg_final_active_constraints', ...
    'cg_active_ratio_R2','cg_modeling_time_sec','cg_gurobi_time_sec', ...
    'cg_separation_time_sec','cg_independent_scan_time_sec','cg_total_time_sec', ...
    'cg_observed_peak_memused_mb','full_observed_peak_memused_mb', ...
    'full_T1','full_T2','full_T3','full_T4','full_objective', ...
    'full_modeling_time_sec','full_gurobi_time_sec','full_total_time_sec', ...
    'full_distance_matrix_bytes','full_distance_build_time_sec', ...
    'full_max_constraint_violation','full_vs_cg_objective_abs_error', ...
    'full_vs_cg_TerminalLOH_max_abs_error','cg_independent_scan_max_violation', ...
    'R1000_regression_objective_abs_error','R1000_regression_TerminalLOH_max_abs_error', ...
    'target_pass','R1000_regression_pass','full_direct_comparison_pass','case_pass', ...
    'estimated_full_variables','estimated_full_constraints','estimated_full_nonzeros', ...
    'estimated_full_peak_memory_mb','available_memory_mb','full_reference_safe_by_estimate', ...
    'full_reference_still_available','active_ratio_duplicate_check', ...
    'cg_stopping_scan_max_violation','cg_independent_violated_r_count'});

historyTable = vertcat(historyTables{:});
targetRows = caseTable(caseTable.R == Rtarget, :);
performance = groupsummary(targetRows, {'rho'}, {'min','mean','max'}, ...
    {'cg_iterations','cg_final_active_constraints','cg_active_ratio_R2', ...
    'cg_gurobi_time_sec','cg_separation_time_sec','cg_independent_scan_time_sec', ...
    'cg_total_time_sec','cg_observed_peak_memused_mb'});
performance.full_reference_ran = repmat(fullReferenceStillAvailable || ...
    any(strcmp(targetRows.full_status, 'OPTIMAL')), height(performance), 1);
performance.full_reference_gate = repmat(fullReferenceGate, height(performance), 1);

acceptance = caseTable(:, {'complexity_label','initial_state_id','R','rho', ...
    'full_reference_gate','full_status','cg_status','target_pass', ...
    'R1000_regression_pass','full_direct_comparison_pass','case_pass', ...
    'cg_independent_scan_max_violation','full_max_constraint_violation', ...
    'full_vs_cg_objective_abs_error','full_vs_cg_TerminalLOH_max_abs_error', ...
    'R1000_regression_objective_abs_error', ...
    'R1000_regression_TerminalLOH_max_abs_error'});
acceptance.independent_scan_tolerance = repmat(1e-8, height(acceptance), 1);
acceptance.objective_tolerance = repmat(1e-8, height(acceptance), 1);
acceptance.TerminalLOH_tolerance = repmat(1e-7, height(acceptance), 1);

csvHashAfter = sha256_file(nominalCsv);
matHashAfter = sha256_file(nominalMat);
protectedAfter = strings(numel(protectedFiles), 1);
for ii = 1:numel(protectedFiles)
    protectedAfter(ii) = sha256_file(char(protectedFiles(ii)));
end
oldHashAfter = sha256_file(fullfile(oldResultDir, ...
    'step03M_full_vs_constraint_generation.csv'));
inputUnchanged = csvHashAfter == csvHashBefore && matHashAfter == matHashBefore;
protectedUnchanged = all(protectedAfter == protectedBefore);
oldRegressionUnchanged = oldHashAfter == oldCasesHashBefore;
allPass = all(caseTable.case_pass) && inputUnchanged && ...
    protectedUnchanged && oldRegressionUnchanged;
if ~allPass
    error('Step-03N final audit failed. No results were written or pushed.');
end

targetMaxViolation = max(targetRows.cg_independent_scan_max_violation);
targetActiveMin = min(targetRows.cg_active_ratio_R2);
targetActiveMean = mean(targetRows.cg_active_ratio_R2);
targetActiveMax = max(targetRows.cg_active_ratio_R2);
targetGurobiTime = sum(targetRows.cg_gurobi_time_sec);
targetSeparationTime = sum(targetRows.cg_separation_time_sec) + ...
    sum(targetRows.cg_independent_scan_time_sec);
if targetGurobiTime >= targetSeparationTime
    bottleneck = "GUROBI";
else
    bottleneck = "FULL_SEPARATION_SCAN";
end
r1000 = caseTable(caseTable.R == 1000, :);
r2000 = caseTable(caseTable.R == 2000, :);
r1000MeanTime = mean(r1000.cg_total_time_sec);
r2000MeanTime = mean(r2000.cg_total_time_sec);
growth = r2000MeanTime / r1000MeanTime;
continueR5000 = targetMaxViolation <= 1e-8 && fullReferenceStillAvailable && ...
    targetActiveMax < 0.01 && growth < 10;
if continueR5000
    r5000Decision = "PROCEED_TO_R5000_WITH_RESOURCE_MONITORING";
else
    r5000Decision = "DO_NOT_PROCEED_DIRECTLY; REVIEW_R2000_RESOURCE_GROWTH_FIRST";
end

if ~exist(localOutputDir, 'dir'); mkdir(localOutputDir); end
if ~exist(outputDir, 'dir'); mkdir(outputDir); end
writetable(caseTable, fullfile(localOutputDir, 'step03N_R2000_case_results.csv'));
writetable(historyTable, fullfile(localOutputDir, 'step03N_iteration_history.csv'));
writetable(performance, fullfile(localOutputDir, 'step03N_performance_summary.csv'));
writetable(acceptance, fullfile(localOutputDir, 'step03N_acceptance_tests.csv'));
copy_results(localOutputDir, outputDir);
summaryLines = [ ...
    "Step-03N WDRO constraint-generation R=2000 extension"; ...
    "PASS=12 target/regression cases passed"; ...
    "FAIL=0"; ...
    "target_cases=6"; ...
    "regression_cases=6"; ...
    "states=7,18,30"; ...
    "rho=0,0.02"; ...
    "target_R=2000"; ...
    "full_model_variables=334005"; ...
    "full_model_constraints=4076000"; ...
    "full_model_nonzeros=13262000"; ...
    "full_model_conservative_peak_memory_mb=" + string(sprintf('%.12g', targetEstimateBytes/1024^2)); ...
    "available_memory_mb=" + string(sprintf('%.12g', availableBytes/1024^2)); ...
    "full_reference_gate=" + fullReferenceGate; ...
    "target_max_independent_violation=" + string(sprintf('%.16g', targetMaxViolation)); ...
    "target_active_ratio_min=" + string(sprintf('%.16g', targetActiveMin)); ...
    "target_active_ratio_mean=" + string(sprintf('%.16g', targetActiveMean)); ...
    "target_active_ratio_max=" + string(sprintf('%.16g', targetActiveMax)); ...
    "target_cg_gurobi_time_sec=" + string(sprintf('%.16g', targetGurobiTime)); ...
    "target_complete_separation_time_sec=" + string(sprintf('%.16g', targetSeparationTime)); ...
    "target_bottleneck=" + bottleneck; ...
    "R1000_mean_cg_time_sec=" + string(sprintf('%.16g', r1000MeanTime)); ...
    "R2000_mean_cg_time_sec=" + string(sprintf('%.16g', r2000MeanTime)); ...
    "R2000_to_R1000_time_growth=" + string(sprintf('%.16g', growth)); ...
    "R5000_decision=" + r5000Decision; ...
    "R5000_supported_by_R2000=" + string(continueR5000); ...
    "R5000_tested=false"; ...
    "R15000_tested=false"; ...
    "all_35_states_tested=false"; ...
    "formal_WDRO_run=false"; ...
    "MSP_run=false"; ...
    "Step03J_input_unchanged=" + string(inputUnchanged); ...
    "Step03M_regression_unchanged=" + string(oldRegressionUnchanged)];
write_lines(fullfile(localOutputDir, 'step03N_summary.txt'), summaryLines);
copy_results(localOutputDir, outputDir);

manifest = [ ...
    "task=Step-03N WDRO constraint-generation R=2000 extension"; ...
    "baseline_commit=" + expectedHead; ...
    "nominal_csv_sha256=" + csvHashAfter; ...
    "nominal_mat_sha256=" + matHashAfter; ...
    "selected_states=7,18,30"; ...
    "R_values=1000_regression,2000_target"; ...
    "rho_values=0,0.02"; ...
    "full_reference_gate=" + fullReferenceGate; ...
    "gurobi_time_limit_sec=300"; ...
    "full_reference_not_modified=true"; ...
    "R5000_run=false"; ...
    "R15000_run=false"; ...
    "MSP_run=false"];
write_lines(fullfile(localOutputDir, 'run_manifest.txt'), manifest);
copy_results(localOutputDir, outputDir);

fprintf('\nStep-03N complete. target max violation=%.12g, active ratio min/mean/max=%.8g/%.8g/%.8g\n', ...
    targetMaxViolation, targetActiveMin, targetActiveMean, targetActiveMax);
fprintf('R=2000 mean CG time %.3f s; R=1000 mean %.3f s; growth %.3fx\n', ...
    r2000MeanTime, r1000MeanTime, growth);
fprintf('R5000 decision: %s\n', r5000Decision);

function [nvar, ncon, nnzUpper, estimateBytes] = full_model_estimate(R, I, N)
nvar = 5 + 167 * R;
ncon = R * R + 38 * R;
nnzUpper = 3 * R * R + 631 * R;
triplets = 3 * nnzUpper * 8;
sparseBytes = nnzUpper * (8 + 4) + (ncon + 1) * 8;
baseBytes = ncon * (8 + 1) + nvar * 8 * 4 + R * R * 8;
estimateBytes = 2 * (triplets + sparseBytes) + baseBytes + 256 * 1024^2;
end

function [usedBytes, availableBytes] = memory_snapshot()
try
    [u, ~] = memory;
    usedBytes = double(u.MemUsedMATLAB);
    availableBytes = double(u.MemAvailableAllArrays);
catch
    usedBytes = NaN;
    availableBytes = NaN;
end
end

function value = whos_bytes(name)
info = evalin('caller', sprintf('whos(''%s'')', name));
value = info.bytes;
end

function sol = solve_full_with_tight_env(D, A, C, Cap, M, rho, dMat, config)
oldDir = pwd;
tempDir = tempname;
mkdir(tempDir);
fid = fopen(fullfile(tempDir, 'gurobi.env'), 'w');
fprintf(fid, 'OptimalityTol 1e-9\nFeasibilityTol 1e-9\nNumericFocus 3\n');
fclose(fid);
try
    cd(tempDir);
    sol = solve_wdro_terminal_loh_lp_h2(D, A, C, Cap, M, rho, dMat, config);
    cd(oldDir);
    rmdir(tempDir, 's');
catch ME
    cd(oldDir);
    if exist(tempDir, 'dir'); rmdir(tempDir, 's'); end
    rethrow(ME);
end
end

function maxViolation = full_solution_max_violation(sol, dMat, blockSize)
if sol.exitflag ~= 1
    maxViolation = NaN;
    return;
end
R = numel(sol.L);
maxViolation = -inf;
for start = 1:blockSize:R
    idx = start:min(R, start + blockSize - 1);
    violation = reshape(sol.L, 1, []) - sol.lambda .* dMat(idx, :) - sol.alpha(idx);
    maxViolation = max(maxViolation, max(violation, [], 'all'));
end
end

function copy_results(src, dst)
if ~exist(dst, 'dir'); mkdir(dst); end
files = dir(fullfile(src, '*'));
for ii = 1:numel(files)
    if ~files(ii).isdir
        copyfile(fullfile(src, files(ii).name), fullfile(dst, files(ii).name));
    end
end
end

function hash = sha256_file(path)
if ~isfile(path)
    error('SHA-256 input file is missing: %s', path);
end
[status, output] = system(sprintf('certutil -hashfile "%s" SHA256', path));
if status ~= 0
    error('certutil failed for %s: %s', path, output);
end
tokens = regexp(output, '[0-9A-Fa-f]{64}', 'match');
if isempty(tokens)
    error('Could not parse SHA-256 for %s.', path);
end
hash = lower(string(tokens{1}));
end

function write_lines(path, lines)
fid = fopen(path, 'w');
if fid < 0
    error('Cannot write %s.', path);
end
cleanup = onCleanup(@() fclose(fid));
for ii = 1:numel(lines)
    fprintf(fid, '%s\n', char(lines(ii)));
end
end
