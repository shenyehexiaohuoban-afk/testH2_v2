clear; clc;

thisDir = fileparts(mfilename('fullpath'));
moduleDir = fileparts(thisDir);
rootDir = fileparts(moduleDir);
inputDir = fullfile(moduleDir, 'output', 'stage3j_wdro_input_freeze', 'run-001');
step3nDir = fullfile(rootDir, 'results', 'task-002-stage2b-b3-smoke', ...
    '14-wdro-constraint-generation-scale', 'run-001');
outputDir = fullfile(rootDir, 'results', 'task-002-stage2b-b3-smoke', ...
    '15-terminal-loh-rationality-audit', 'run-001');

if exist(outputDir, 'dir')
    error('Step-03O output directory already exists; use a new run number.');
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
    error('Step-03O requires the existing Gurobi MATLAB interface.');
end

expectedHead = "96449fa9e66c545b3ea7ba0de3882c57b94297f1";
[gitStatus, gitHead] = system('git rev-parse HEAD');
if gitStatus ~= 0 || lower(strtrim(string(gitHead))) ~= expectedHead
    error('Step-03O must start from baseline commit %s.', expectedHead);
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
    string(fullfile(thisDir, 'solve_wdro_terminal_loh_lp_constraint_generation_h2.m')); ...
    string(fullfile(thisDir, 'load_frozen_b3_wdro_dataset_h2.m'))];
protectedBefore = strings(numel(protectedFiles), 1);
for ii = 1:numel(protectedFiles)
    protectedBefore(ii) = sha256_file(char(protectedFiles(ii)));
end
step3nPath = fullfile(step3nDir, 'step03N_R2000_case_results.csv');
step3nHashBefore = sha256_file(step3nPath);
step3nCases = readtable(step3nPath, 'TextType', 'string');

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
    error('Step-03O requires the accepted reserve-shortage penalty source.');
end
capacityFraction = 0.8;
Cap = capacityFraction .* tankCap;
expectedCap = [240; 160; 80; 120];
if max(abs(Cap - expectedCap)) > 1e-12
    error('Accepted TerminalLOH capacity bounds are not [240,160,80,120].');
end

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

states = table([7;18;30], [2;4;6], [7;4;2], [0;0;0], ...
    ["simple";"medium";"complex"], ...
    'VariableNames', {'initial_state_id','a0','loc0','lfw0','complexity_label'});
rhoSweepValues = [0, 0.001, 0.005, 0.01, 0.02];
R = 2000;
breakRecords = cell(0, 1);
sweepRecords = cell(0, 1);
mediumPrimary = struct();
primaryCount = 0;

for stateRow = 1:height(states)
    state = states(stateRow, :);
    fprintf('\nStep-03O loading %s state %d.\n', ...
        char(state.complexity_label), state.initial_state_id);
    [samples, metadata] = load_frozen_b3_wdro_dataset_h2( ...
        nominalCsv, nominalMat, state.a0, state.loc0, state.lfw0);
    if any(double(metadata.initial_state_id) ~= state.initial_state_id)
        error('Frozen loader state identity differs from Step-03N.');
    end
    D = samples.D(1:R, :);
    A = samples.A(1:R, :, :);
    C = samples.C_raw(1:R, :, :);
    if state.complexity_label == "simple"
        rhoList = [0, 0.02];
    else
        rhoList = rhoSweepValues;
    end

    for rho = rhoList
        primaryCount = primaryCount + 1;
        fprintf('Primary %d: state=%s rho=%.3f\n', ...
            primaryCount, char(state.complexity_label), rho);
        sol = solve_wdro_terminal_loh_audit_cg_h2( ...
            D, A, C, Cap, M, rho, config, struct());
        require_optimal(sol, sprintf('%s rho %.3f', state.complexity_label, rho));
        oldObjErr = NaN;
        oldTErr = NaN;
        if abs(rho) <= 1e-12 || abs(rho - 0.02) <= 1e-12
            old = step3nCases(double(step3nCases.initial_state_id) == state.initial_state_id & ...
                double(step3nCases.R) == R & abs(double(step3nCases.rho) - rho) <= 1e-12, :);
            if height(old) ~= 1
                error('Step-03N endpoint row is missing.');
            end
            oldObjErr = abs(sol.original_objective_value - double(old.cg_objective));
            oldT = [double(old.cg_T1); double(old.cg_T2); ...
                double(old.cg_T3); double(old.cg_T4)];
            oldTErr = max(abs(sol.T - oldT));
            breakRecords{end + 1, 1} = solution_record( ...
                state, rho, sol, Cap, oldObjErr, oldTErr); %#ok<SAGROW>
        end
        if state.complexity_label ~= "simple"
            sweepRecords{end + 1, 1} = solution_record( ...
                state, rho, sol, Cap, oldObjErr, oldTErr); %#ok<SAGROW>
        end
        if state.complexity_label == "medium" && ...
                (abs(rho) <= 1e-12 || abs(rho - 0.02) <= 1e-12)
            key = rho_key(rho);
            mediumPrimary.(key) = struct( ...
                'T', sol.T, 'objective', sol.original_objective_value, ...
                'lambda', sol.lambda);
        end
        clear sol;
    end
    clear samples metadata D A C;
end

objectiveBreakdown = struct2table(vertcat(breakRecords{:}));
rhoSweep = struct2table(vertcat(sweepRecords{:}));
rhoSweep.objective_change_from_previous = NaN(height(rhoSweep), 1);
rhoSweep.T_max_change_from_previous = NaN(height(rhoSweep), 1);
rhoSweep.objective_nondecreasing = true(height(rhoSweep), 1);
for stateId = [18, 30]
    idxRows = find(rhoSweep.initial_state_id == stateId);
    [~, order] = sort(rhoSweep.rho(idxRows));
    idxRows = idxRows(order);
    for kk = 2:numel(idxRows)
        now = idxRows(kk);
        prev = idxRows(kk - 1);
        rhoSweep.objective_change_from_previous(now) = ...
            rhoSweep.total_objective(now) - rhoSweep.total_objective(prev);
        rhoSweep.T_max_change_from_previous(now) = max(abs( ...
            [rhoSweep.T1(now),rhoSweep.T2(now),rhoSweep.T3(now),rhoSweep.T4(now)] - ...
            [rhoSweep.T1(prev),rhoSweep.T2(prev),rhoSweep.T3(prev),rhoSweep.T4(prev)]));
        rhoSweep.objective_nondecreasing(now) = ...
            rhoSweep.objective_change_from_previous(now) >= -1e-8;
    end
end

fprintf('\nStep-03O multiple-optimality audit for medium state.\n');
[mediumSamples, ~] = load_frozen_b3_wdro_dataset_h2( ...
    nominalCsv, nominalMat, 4, 4, 0);
Dmed = mediumSamples.D(1:R, :);
Amed = mediumSamples.A(1:R, :, :);
Cmed = mediumSamples.C_raw(1:R, :, :);
objectiveCapTolerance = 1e-6;
rangeWidthThreshold = 1e-5;
rangeRecords = cell(0, 1);
rangeIndex = 0;
for rho = [0, 0.02]
    primary = mediumPrimary.(rho_key(rho));
    for site = 1:4
        auditMin = struct('originalObjectiveUpperBound', ...
            primary.objective + objectiveCapTolerance, ...
            'secondarySite', site, 'secondaryDirection', "min");
        solMin = solve_wdro_terminal_loh_audit_cg_h2( ...
            Dmed, Amed, Cmed, Cap, M, rho, config, auditMin);
        require_optimal(solMin, sprintf('range min rho %.2f site %d', rho, site));
        auditMax = auditMin;
        auditMax.secondaryDirection = "max";
        solMax = solve_wdro_terminal_loh_audit_cg_h2( ...
            Dmed, Amed, Cmed, Cap, M, rho, config, auditMax);
        require_optimal(solMax, sprintf('range max rho %.2f site %d', rho, site));
        rangeIndex = rangeIndex + 1;
        width = solMax.T(site) - solMin.T(site);
        rangeRecords{rangeIndex, 1} = struct( ...
            'initial_state_id', 18, 'rho', rho, 'site_id', site, ...
            'primary_objective', primary.objective, ...
            'objective_cap_tolerance', objectiveCapTolerance, ...
            'T_min', solMin.T(site), 'T_max', solMax.T(site), ...
            'T_range_width', width, ...
            'min_original_objective', solMin.original_objective_value, ...
            'max_original_objective', solMax.original_objective_value, ...
            'min_cap_slack', solMin.objective_cap_slack, ...
            'max_cap_slack', solMax.objective_cap_slack, ...
            'min_scan_violation', solMin.final_independent_scan_max_violation, ...
            'max_scan_violation', solMax.final_independent_scan_max_violation, ...
            'multiple_optimal_interval', width > rangeWidthThreshold);
        clear solMin solMax;
    end
end
optimalRange = struct2table(vertcat(rangeRecords{:}));
multipleOptimal = any(optimalRange.multiple_optimal_interval);
if multipleOptimal
    optimalRangeLabel = "MULTIPLE_OPTIMAL_TERMINALLOH";
else
    optimalRangeLabel = "UNIQUE_WITHIN_AUDIT_TOLERANCE";
end

fprintf('\nStep-03O cross-fixed TerminalLOH experiments.\n');
crossRecords = cell(0, 1);
crossIndex = 0;
crossSpecs = [0, 0.02; 0.02, 0];
for kk = 1:size(crossSpecs, 1)
    sourceRho = crossSpecs(kk, 1);
    targetRho = crossSpecs(kk, 2);
    source = mediumPrimary.(rho_key(sourceRho));
    target = mediumPrimary.(rho_key(targetRho));
    fixedSol = solve_wdro_terminal_loh_audit_cg_h2( ...
        Dmed, Amed, Cmed, Cap, M, targetRho, config, ...
        struct('fixedT', source.T));
    require_optimal(fixedSol, sprintf('cross fixed %.2f to %.2f', sourceRho, targetRho));
    crossIndex = crossIndex + 1;
    crossRecords{crossIndex, 1} = struct( ...
        'initial_state_id', 18, 'source_rho', sourceRho, ...
        'target_rho', targetRho, ...
        'fixed_T1', source.T(1), 'fixed_T2', source.T(2), ...
        'fixed_T3', source.T(3), 'fixed_T4', source.T(4), ...
        'target_optimal_objective', target.objective, ...
        'fixed_objective', fixedSol.original_objective_value, ...
        'objective_difference', fixedSol.original_objective_value - target.objective, ...
        'terminal_cost', fixedSol.terminal_cost, ...
        'lambda_rho_cost', fixedSol.lambda_rho_cost, ...
        'alpha_mean_cost', fixedSol.alpha_mean_cost, ...
        'robust_dual_loss', fixedSol.lambda_rho_cost + fixedSol.alpha_mean_cost, ...
        'mean_service_cost', fixedSol.mean_service_cost, ...
        'mean_shortage_penalty', fixedSol.mean_shortage_penalty, ...
        'lambda', fixedSol.lambda, ...
        'max_independent_violation', fixedSol.final_independent_scan_max_violation, ...
        'feasible', fixedSol.exitflag == 1 && ...
            fixedSol.final_independent_scan_max_violation <= 1e-8);
    clear fixedSol;
end
crossFixed = struct2table(vertcat(crossRecords{:}));
clear mediumSamples Dmed Amed Cmed;

csvHashAfter = sha256_file(nominalCsv);
matHashAfter = sha256_file(nominalMat);
protectedAfter = strings(numel(protectedFiles), 1);
for ii = 1:numel(protectedFiles)
    protectedAfter(ii) = sha256_file(char(protectedFiles(ii)));
end
step3nHashAfter = sha256_file(step3nPath);
inputUnchanged = csvHashAfter == csvHashBefore && matHashAfter == matHashBefore;
protectedUnchanged = all(protectedAfter == protectedBefore);
step3nUnchanged = step3nHashAfter == step3nHashBefore;
endpointMatch = max(objectiveBreakdown.step3n_objective_abs_error) <= 1e-8 && ...
    max(objectiveBreakdown.step3n_TerminalLOH_max_abs_error) <= 1e-7;
breakdownOk = max(objectiveBreakdown.objective_reconstruction_abs_error) <= 1e-8;
sweepMonotonic = all(rhoSweep.objective_nondecreasing);
sweepScanOk = max(rhoSweep.max_independent_violation) <= 1e-8;
rangeScanOk = max([optimalRange.min_scan_violation; optimalRange.max_scan_violation]) <= 1e-8;
rangeCapOk = min([optimalRange.min_cap_slack; optimalRange.max_cap_slack]) >= -1e-7;
crossOk = all(crossFixed.feasible) && min(crossFixed.objective_difference) >= -1e-7;
domainOk = all(isfinite(objectiveBreakdown.total_objective)) && ...
    all(isfinite(rhoSweep.total_objective)) && ...
    all(isfinite(optimalRange.T_min)) && all(isfinite(optimalRange.T_max));
boundSaturation = any(objectiveBreakdown.upper_bound_count > 0);

if ~sweepMonotonic || ~breakdownOk || ~crossOk
    decision = "D. MODEL_FORMULATION_OR_SIGN_PROBLEM_FOUND";
elseif multipleOptimal
    decision = "B. RESULTS_REASONABLE_BUT_MULTIPLE_OPTIMA";
elseif boundSaturation
    decision = "C. BOUND_SATURATION_REQUIRES_INTERPRETATION";
elseif endpointMatch && sweepScanOk && rangeScanOk
    decision = "A. RESULTS_REASONABLE";
else
    decision = "E. AUDIT_INCONCLUSIVE";
end

auditRows = {
    'DEF-01', pass_fail(max(abs(Cap-expectedCap))<=1e-12), mat2str(Cap.'), '[240 160 80 120] upper bounds';
    'OBJ-01', pass_fail(breakdownOk), max(objectiveBreakdown.objective_reconstruction_abs_error), '<=1e-8';
    'END-01', pass_fail(endpointMatch), max(objectiveBreakdown.step3n_objective_abs_error), 'Step-03N endpoint match';
    'RHO-01', pass_fail(sweepMonotonic), min(rhoSweep.objective_change_from_previous,[],'omitnan'), 'worst objective nondecreasing';
    'RHO-02', pass_fail(sweepScanOk), max(rhoSweep.max_independent_violation), '<=1e-8';
    'OPT-01', pass_fail(rangeScanOk), max([optimalRange.min_scan_violation;optimalRange.max_scan_violation]), '<=1e-8';
    'OPT-02', pass_fail(rangeCapOk), min([optimalRange.min_cap_slack;optimalRange.max_cap_slack]), 'objective cap respected';
    'FIX-01', pass_fail(crossOk), min(crossFixed.objective_difference), 'cross-fixed feasible and not better than optimum';
    'DATA-01', pass_fail(inputUnchanged), inputUnchanged, 'Step-03J hashes unchanged';
    'CORE-01', pass_fail(protectedUnchanged), protectedUnchanged, 'formal WDRO and CG core unchanged';
    'OLD-01', pass_fail(step3nUnchanged), step3nUnchanged, 'Step-03N archive unchanged';
    'DOM-01', pass_fail(domainOk), domainOk, 'finite audit outputs';
    'BOUND-01', 'PASS', 'R<=2000 only', 'R=5000/R=15000 not run';
    'MSP-01', 'PASS', 'not run', 'MSP not run'};
acceptance = cell2table(auditRows, 'VariableNames', ...
    {'check_id','status','observed','expected'});
failCount = sum(strcmp(acceptance.status, 'FAIL'));
passCount = sum(strcmp(acceptance.status, 'PASS'));
if failCount > 0
    error('Step-03O audit has %d failed checks; no output or Git write.', failCount);
end

rho0 = mediumPrimary.rho0;
rho002 = mediumPrimary.rho002;
crossTo002 = crossFixed(abs(crossFixed.source_rho) <= 1e-12 & ...
    abs(crossFixed.target_rho - 0.02) <= 1e-12, :);
if height(crossTo002) ~= 1
    error('Medium rho=0 to rho=0.02 cross-fixed result is missing.');
end

mkdir(outputDir);
writetable(objectiveBreakdown, fullfile(outputDir, 'step03O_objective_breakdown.csv'));
writetable(rhoSweep, fullfile(outputDir, 'step03O_rho_sweep.csv'));
writetable(optimalRange, fullfile(outputDir, 'step03O_optimal_range.csv'));
writetable(crossFixed, fullfile(outputDir, 'step03O_cross_fixed_results.csv'));
writetable(acceptance, fullfile(outputDir, 'step03O_acceptance_tests.csv'));
write_definition_audit(fullfile(outputDir, ...
    'step03O_terminal_loh_definition_audit.md'), Cap, tankCap, ...
    capacityFraction, config.gamma, M, penaltySource);
summaryLines = [ ...
    "Step-03O TerminalLOH rationality audit"; ...
    "PASS=" + string(passCount); ...
    "FAIL=" + string(failCount); ...
    "decision=" + decision; ...
    "TerminalLOH_upper_bounds_kg=" + join(string(Cap.'), ","); ...
    "exact_bound_vector_240_160_80_120=true"; ...
    "TerminalLOH_meaning=site-level prepositioned reserve/service-volume limit in each consequence atom"; ...
    "rho_sweep_objective_nondecreasing=" + string(sweepMonotonic); ...
    "max_rho_sweep_independent_violation=" + string(sprintf('%.16g', max(rhoSweep.max_independent_violation))); ...
    "multiple_optimal_terminal_loh=" + string(multipleOptimal); ...
    "optimal_range_label=" + optimalRangeLabel; ...
    "max_optimal_T_range_kg=" + string(sprintf('%.16g', max(optimalRange.T_range_width))); ...
    "medium_rho0_T=" + join(string(rho0.T.'), ","); ...
    "medium_rho002_T=" + join(string(rho002.T.'), ","); ...
    "medium_rho0_T_fixed_in_rho002_objective_gap=" + ...
        string(sprintf('%.16g', crossTo002.objective_difference)); ...
    "rho_increase_explanation=rho changes the tradeoff among gamma*sum(T), rho*lambda, and mean(alpha); T has no monotonicity constraint"; ...
    "R5000_recommendation=may_continue_algorithm_scaling test, but interpret bound-saturated TerminalLOH before substantive use"; ...
    "R5000_tested=false"; ...
    "R15000_tested=false"; ...
    "formal_model_modified=false"; ...
    "constraint_generation_core_modified=false"; ...
    "MSP_run=false"];
write_lines(fullfile(outputDir, 'step03O_summary.txt'), summaryLines);
manifestLines = [ ...
    "task=Step-03O TerminalLOH rationality audit"; ...
    "baseline_commit=" + expectedHead; ...
    "R=2000"; ...
    "states=7,18,30"; ...
    "rho_sweep=0,0.001,0.005,0.01,0.02"; ...
    "objective_cap_tolerance=" + string(objectiveCapTolerance); ...
    "optimal_range_width_threshold=" + string(rangeWidthThreshold); ...
    "decision=" + decision; ...
    "Step03J_csv_sha256=" + csvHashAfter; ...
    "Step03J_mat_sha256=" + matHashAfter; ...
    "R5000_run=false"; ...
    "R15000_run=false"; ...
    "MSP_run=false"];
write_lines(fullfile(outputDir, 'run_manifest.txt'), manifestLines);

fprintf('\nStep-03O completed: PASS=%d FAIL=%d decision=%s\n', ...
    passCount, failCount, decision);
fprintf('Multiple optimum=%d, max T range=%.12g kg\n', ...
    multipleOptimal, max(optimalRange.T_range_width));
fprintf('Medium rho0 T fixed at rho0.02 objective gap=%.12g\n', ...
    crossTo002.objective_difference);

function key = rho_key(rho)
if abs(rho) <= 1e-12
    key = 'rho0';
elseif abs(rho - 0.02) <= 1e-12
    key = 'rho002';
else
    error('Unsupported primary-storage rho.');
end
end

function rec = solution_record(state, rho, sol, Cap, oldObjErr, oldTErr)
rec = struct();
rec.complexity_label = string(state.complexity_label);
rec.initial_state_id = double(state.initial_state_id);
rec.a0 = double(state.a0);
rec.loc0 = double(state.loc0);
rec.lfw0 = double(state.lfw0);
rec.R = numel(sol.alpha);
rec.rho = rho;
rec.total_objective = sol.original_objective_value;
rec.terminal_cost = sol.terminal_cost;
rec.lambda_rho_cost = sol.lambda_rho_cost;
rec.alpha_mean_cost = sol.alpha_mean_cost;
rec.robust_dual_loss = sol.lambda_rho_cost + sol.alpha_mean_cost;
rec.mean_service_cost = sol.mean_service_cost;
rec.mean_shortage_penalty = sol.mean_shortage_penalty;
rec.mean_scenario_loss = sol.mean_scenario_loss;
rec.other_objective_cost = sol.other_objective_cost;
rec.objective_reconstruction_abs_error = abs(sol.original_objective_value - ...
    sol.terminal_cost - sol.lambda_rho_cost - sol.alpha_mean_cost - ...
    sol.other_objective_cost);
rec.T1 = sol.T(1); rec.T2 = sol.T(2); rec.T3 = sol.T(3); rec.T4 = sol.T(4);
rec.T_total = sum(sol.T);
rec.lambda = sol.lambda;
rec.lower_bound_site1 = sol.lower_bound_active(1);
rec.lower_bound_site2 = sol.lower_bound_active(2);
rec.lower_bound_site3 = sol.lower_bound_active(3);
rec.lower_bound_site4 = sol.lower_bound_active(4);
rec.upper_bound_site1 = sol.upper_bound_active(1);
rec.upper_bound_site2 = sol.upper_bound_active(2);
rec.upper_bound_site3 = sol.upper_bound_active(3);
rec.upper_bound_site4 = sol.upper_bound_active(4);
rec.upper_bound_count = sum(sol.upper_bound_active);
rec.capacity_margin_min_kg = min(Cap(:) - sol.T(:));
rec.max_independent_violation = sol.final_independent_scan_max_violation;
rec.iterations = height(sol.history);
rec.final_active_constraints = sol.final_active_constraints;
rec.step3n_objective_abs_error = oldObjErr;
rec.step3n_TerminalLOH_max_abs_error = oldTErr;
end

function require_optimal(sol, label)
if sol.exitflag ~= 1 || ~sol.converged || ...
        sol.final_independent_scan_max_violation > 1e-8 || ...
        any(~isfinite(sol.T)) || ~isfinite(sol.original_objective_value)
    error('Step-03O solve failed: %s, status=%s, violation=%.12g.', ...
        label, sol.status, sol.final_independent_scan_max_violation);
end
end

function write_definition_audit(path, Cap, tankCap, fraction, gamma, M, penaltySource)
lines = [ ...
    "# Step-03O TerminalLOH Definition Audit"; ...
    ""; ...
    "## Confirmed mathematical variable"; ...
    ""; ...
    "The four variables `T_i` are created as the first four LP variables in `terminalLoh_wdro/src/solve_wdro_terminal_loh_lp_h2.m:40-42`. They are nonnegative because the common lower-bound vector is initialized to zero at lines 59-60."; ...
    ""; ...
    "For each consequence atom s and site i, `sum_n y^s_{i,n} <= T_i` is implemented at lines 103-113. Therefore T_i is the site-level TerminalLOH reserve/service-volume limit available to that atom. It is not a realized shortage and is not automatically the final MSP inventory state."; ...
    ""; ...
    "Increasing T_i enlarges the feasible served-hydrogen volume at site i. Served flow is also bounded by reachability and node demand through `y^s_{i,n} <= A^s_{i,n} D^s_n` at lines 63-69. Demand balance `sum_i y^s_{i,n}+u^s_n=D^s_n` is at lines 90-101, so useful additional T can reduce unmet demand u."; ...
    ""; ...
    "## Bounds and source"; ...
    ""; ...
    sprintf("The accepted tank capacities are [%s] kg from `data/yuanqi/near_stage_msp_input.mat:NearStageInput.HydrogenDevice.tank_cap_kg`, loaded in `run_stage3k_wdro_integration_scaling_h2.m:214-217` and `build_terminal_loh_wdro_from_joint_samples_h2.m:222-228`.", strtrim(sprintf('%.12g ', tankCap))); ...
    ""; ...
    sprintf("The WDRO capacity fraction is %.6g (`run_stage3k_wdro_integration_scaling_h2.m:228-229`; default at `build_terminal_loh_wdro_from_joint_samples_h2.m:185-186`). Thus `Cap=fraction*tank_capacity=[%s]` kg.", fraction, strtrim(sprintf('%.12g ', Cap))); ...
    ""; ...
    "The solver applies `ub(T)=Cap` at `solve_wdro_terminal_loh_lp_h2.m:59-62`. Therefore `[240,160,80,120]` is exactly the four-site upper-bound vector, not an incidental interior solution."; ...
    ""; ...
    "## Objective and loss coupling"; ...
    ""; ...
    "The objective is `gamma*sum_i T_i + rho*lambda + (1/R)*sum_r alpha_r`, implemented at `solve_wdro_terminal_loh_lp_h2.m:53-57`."; ...
    ""; ...
    sprintf("Here gamma=%.12g and M=%.12g from `%s`. The project documentation explicitly describes gamma as a small TerminalLOH holding weight used to avoid filling every site to capacity (`build_terminal_loh_wdro_from_joint_samples_h2.m:588`).", gamma, M, penaltySource); ...
    ""; ...
    "Scenario loss satisfies `L_s >= sum_{i,n} Ceff^s_{i,n} y^s_{i,n} + M*sum_n u^s_n` at `solve_wdro_terminal_loh_lp_h2.m:115-131`. Wasserstein dual rows `alpha_r + lambda*d(r,s) >= L_s` are created at lines 133-144."; ...
    ""; ...
    "Consequently, larger T can reduce shortage loss only when additional reachable service is useful, while every additional kg of T incurs gamma. No constraint requires T to increase with rho. The optimal value is expected to be nondecreasing in rho, but the optimizer T itself may move in either direction as the dual tradeoff changes."; ...
    ""; ...
    "## Scope"; ...
    ""; ...
    "This audit reads the accepted formulation and runs isolated secondary/fixed-T experiments. It does not modify the formal solver, constraint-generation algorithm, MSP, or frozen data."];
write_lines(path, lines);
end

function out = pass_fail(condition)
if condition; out = 'PASS'; else; out = 'FAIL'; end
end

function hash = sha256_file(path)
if ~isfile(path); error('Missing SHA-256 input: %s', path); end
[status, output] = system(sprintf('certutil -hashfile "%s" SHA256', path));
if status ~= 0; error('certutil failed for %s.', path); end
tokens = regexp(output, '[0-9A-Fa-f]{64}', 'match');
if isempty(tokens); error('Could not parse SHA-256 for %s.', path); end
hash = lower(string(tokens{1}));
end

function write_lines(path, lines)
fid = fopen(path, 'w');
if fid < 0; error('Cannot write %s.', path); end
cleanup = onCleanup(@() fclose(fid));
for ii = 1:numel(lines); fprintf(fid, '%s\n', char(lines(ii))); end
end
