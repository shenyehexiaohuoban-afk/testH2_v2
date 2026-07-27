%% Step-03Q run-001: audit a strict D + Ctilde ground metric candidate.
clear; clc;

thisDir = fileparts(mfilename('fullpath'));
moduleDir = fileparts(thisDir);
rootDir = fileparts(moduleDir);
addpath(rootDir);
addpath(thisDir);
addpath(fullfile(rootDir, 'fa_h2', 'fuzhu', 'terminalLoh_windmc'));
for candidate = {fullfile(getenv('GUROBI_HOME'), 'matlab'), ...
        'D:\gurobi1201\win64\matlab', 'C:\gurobi1201\win64\matlab'}
    if ~isempty(candidate{1}) && exist(candidate{1}, 'dir')
        addpath(candidate{1});
    end
end
if ~ismember(exist('gurobi', 'file'), [2, 3])
    error('Step-03Q requires the existing Gurobi MATLAB interface.');
end

outputDir = fullfile(rootDir, 'results', 'task-002-stage2b-b3-smoke', ...
    '17-dctilde-strict-metric-audit', 'run-001');
tempDir = outputDir + ".tmp";
if isfolder(outputDir) || isfolder(tempDir)
    error('Step-03Q run-001 output or temporary directory already exists.');
end

expectedHead = "e6d735446ab47bbc6b379128b653ad96deb3ed1b";
[headStatus, headText] = system('git rev-parse HEAD');
if headStatus ~= 0 || lower(strtrim(string(headText))) ~= expectedHead
    error('Step-03Q must start from baseline commit %s.', expectedHead);
end

inputDir = fullfile(moduleDir, 'output', 'stage3j_wdro_input_freeze', 'run-001');
roleDefs = table( ...
    ["nominal";"validation-1";"validation-2"], ...
    ["wdro_nominal_input_DAC.mat";"wdro_validation_1_DAC.mat";"wdro_validation_2_DAC.mat"], ...
    ["6936a696f5cde137aca483f8c32adee33b52cbd90559a8e6395f3686c0712945"; ...
     "ca84afa01748d8c2929c372802861315254723424786b681a677e2f1420b6e3f"; ...
     "0bae20fa685940751edf5c5dd3d6c43a2d52293cbd1350c02b84736e914ec3b6"], ...
    'VariableNames', {'role','mat_name','mat_sha256'});
for rr = 1:height(roleDefs)
    path = fullfile(inputDir, roleDefs.mat_name(rr));
    if sha256_file(path) ~= roleDefs.mat_sha256(rr)
        error('Step-03J frozen MAT hash mismatch for %s.', roleDefs.role(rr));
    end
end

protectedFiles = [ ...
    string(fullfile(thisDir, 'build_wdro_distance_matrix_h2.m')); ...
    string(fullfile(thisDir, 'solve_wdro_terminal_loh_lp_h2.m')); ...
    string(fullfile(thisDir, 'solve_wdro_terminal_loh_lp_constraint_generation_h2.m')); ...
    string(fullfile(thisDir, 'solve_step03P_weighted_cg_h2.m')); ...
    string(fullfile(rootDir, 'main_msp_h2_near.m')); ...
    string(fullfile(rootDir, 'h2_default_options.m')); ...
    string(fullfile(rootDir, 'run_h2_with_options.m')); ...
    string(fullfile(rootDir, 'fa_h2', 'build_stage_model_h2.m')); ...
    string(fullfile(rootDir, 'fa_h2', 'update_rhs_h2.m')); ...
    string(fullfile(rootDir, 'fa_h2', 'solve_stage_model_h2.m'))];
protectedBefore = hash_files(protectedFiles);
step03JBefore = directory_hash(inputDir);
step03PDir = fullfile(rootDir, 'results', 'task-002-stage2b-b3-smoke', ...
    '16-dac-transport-cost-audit', 'run-002');
step03PFailedDir = fullfile(rootDir, 'results', 'task-002-stage2b-b3-smoke', ...
    '16-dac-transport-cost-audit', 'run-001');
step03PBefore = directory_hash(step03PDir);
step03PFailedBefore = directory_hash(step03PFailedDir);

config = struct();
config.gamma = 2;
config.gurobiOutputFlag = 0;
config.gurobiFeasibilityTol = 1e-9;
config.gurobiOptimalityTol = 1e-9;
config.gurobiTimeLimit = 300;
config.violationTolerance = 1e-8;
config.maxIterations = 200;
config.blockSize = 100;
config.independentScanBlockSize = 73;
config.epsDistance = 1e-9;
config.scaleTolerance = 1e-12;
config.triangleTolerance = 1e-10;
config.triangleSampleCount = 200000;
config.pairSampleCount = 200000;
config.transferMass = 0.5 / 2000;
config.CoverageBlockSize = 5000;

[Cbound, roadAudit] = derive_C_bound(rootDir);
config.C_bound = Cbound;
coverageTbl = scan_C_coverage(roleDefs, inputDir, Cbound, config.CoverageBlockSize);
if any(coverageTbl.bound_violation_count > 0)
    error('Step-03Q reachable C exceeds the deterministic C_bound.');
end

raw = load(fullfile(rootDir, 'data', 'yuanqi', 'near_stage_msp_input.mat'), ...
    'NearStageInput');
ni = raw.NearStageInput;
Cap = double(ni.HydrogenDevice.tank_cap_kg(:));
expectedCap = [300;200;100;150];
if max(abs(Cap - expectedCap)) > 1e-12
    error('Step-03Q full capacity vector is not [300,200,100,150].');
end
if isfield(ni.Cost, 'reserve_shortage_penalty_yuan_per_kg')
    M = double(ni.Cost.reserve_shortage_penalty_yuan_per_kg);
    penaltySource = "NearStageInput.Cost.reserve_shortage_penalty_yuan_per_kg";
elseif isfield(ni.Cost, 'cost_reserve_shortage')
    M = double(ni.Cost.cost_reserve_shortage);
    penaltySource = "NearStageInput.Cost.cost_reserve_shortage";
else
    error('Step-03Q cannot trace the shortage penalty source.');
end
config.gamma = 0.001 * M;

states = table([7;18;30], [2;4;6], [7;4;2], [0;0;0], ...
    ["simple";"medium";"complex"], ...
    'VariableNames', {'initial_state_id','a0','loc0','lfw0','complexity_label'});
R = 2000;
uniformWeights = ones(R, 1) / R;
kappaValues = [0.5,1.0,1.5];
methodDefs = table(["old";"ctilde";"ctilde";"ctilde"], ...
    [NaN;0.5;1.0;1.5], ...
    ["old_D_A_maskedC";"new_Ctilde_k0p5";"new_Ctilde_k1p0";"new_Ctilde_k1p5"], ...
    'VariableNames', {'method','kappa','label'});

metricRecords = cell(0, 1);
distanceRecords = cell(0, 1);
wdroRecords = cell(0, 1);
validationRecords = cell(0, 1);
consistencyRecords = cell(0, 1);
decisionRecords = cell(0, 1);
allSolverPass = true;
allEvaluationPass = true;
maxIndependentViolation = 0;

for stateRow = 1:height(states)
    state = states(stateRow, :);
    fprintf('\nStep-03Q state %s (%d): loading frozen D/A/C.\n', ...
        char(state.complexity_label), state.initial_state_id);
    roleData = struct();
    for roleRow = 1:height(roleDefs)
        roleData.(role_field(roleDefs.role(roleRow))) = load_frozen_state( ...
            fullfile(inputDir, roleDefs.mat_name(roleRow)), ...
            state.initial_state_id, R);
    end
    if ~isequal(roleData.nominal.path_id, roleData.validation_1.path_id) || ...
            ~isequal(roleData.nominal.path_id, roleData.validation_2.path_id)
        error('Step-03Q path order differs across dataset roles.');
    end
    D = roleData.nominal.D;
    A = roleData.nominal.A;
    C = roleData.nominal.C;
    components = build_step03P_distance_components_h2(D, A, C, config);
    [oldDistance, oldInfo] = build_wdro_distance_matrix_h2( ...
        D, A, C, 'DAC_maskedC', config);
    oldPositive = oldDistance(triu(true(R), 1) & oldDistance > 1e-12);
    oldMedian = median(oldPositive);
    fprintf('  accepted weights D/A/C = %.6g/%.6g/%.6g; old median %.6g.\n', ...
        oldInfo.weights.D, oldInfo.weights.A, oldInfo.weights.C, oldMedian);

    distanceByMethod = containers.Map('KeyType', 'char', 'ValueType', 'any');
    detailByMethod = containers.Map('KeyType', 'char', 'ValueType', 'any');
    infoByMethod = containers.Map('KeyType', 'char', 'ValueType', 'any');
    solveByMethod = containers.Map('KeyType', 'char', 'ValueType', 'any');
    evalByMethod = containers.Map('KeyType', 'char', 'ValueType', 'any');

    directed = deterministic_triples(R, config.triangleSampleCount, ...
        20261727 + state.initial_state_id);
    oldMaskedViolation = triple_violation(components.normC, directed);
    directedMask = oldMaskedViolation > config.triangleTolerance;
    randomTriples = deterministic_triples(R, config.triangleSampleCount, ...
        20262727 + state.initial_state_id);

    for mm = 1:height(methodDefs)
        label = methodDefs.label(mm);
        buildConfig = config;
        buildConfig.components = components;
        buildConfig.oldDistance = oldDistance;
        buildConfig.oldInfo = oldInfo;
        buildConfig.matchOldMedian = methodDefs.method(mm) == "ctilde";
        if methodDefs.method(mm) == "ctilde"
            buildConfig.kappa = methodDefs.kappa(mm);
        end
        [dMat, distanceInfo, distanceDetail] = ...
            build_step03Q_distance_matrix_h2(D, A, C, ...
            methodDefs.method(mm), buildConfig);
        distanceByMethod(char(label)) = dMat;
        detailByMethod(char(label)) = distanceDetail;
        infoByMethod(char(label)) = distanceInfo;
        distanceRecords{end + 1, 1} = distance_record( ...
            state, label, distanceInfo, distanceDetail); %#ok<SAGROW>

        if methodDefs.method(mm) == "old"
            metricRecords{end + 1, 1} = metric_record(state, label, ...
                "old_total", dMat, components, randomTriples, directed, ...
                directedMask, config); %#ok<SAGROW>
        else
            metricRecords{end + 1, 1} = metric_record(state, label, ...
                "Ctilde_component", distanceDetail.d_Ctilde, components, ...
                randomTriples, directed, directedMask, config); %#ok<SAGROW>
            metricRecords{end + 1, 1} = metric_record(state, label, ...
                "D_plus_Ctilde_total", dMat, components, randomTriples, ...
                directed, directedMask, config); %#ok<SAGROW>
        end

        for rho = [0,0.02]
            fprintf('  solve %s rho=%.3g\n', label, rho);
            [memBefore, ~] = memory_snapshot();
            callTic = tic;
            sol = solve_step03P_weighted_cg_h2( ...
                D, A, C, Cap, M, rho, dMat, uniformWeights, config);
            totalTime = toc(callTic);
            [memAfter, ~] = memory_snapshot();
            observedMemory = max(memBefore, memAfter) / 1024^2;
            allSolverPass = allSolverPass && sol.exitflag == 1 && sol.converged;
            maxIndependentViolation = max(maxIndependentViolation, ...
                sol.final_independent_scan_max_violation);
            nominalEval = evaluate_step03P_fixed_T_losses_h2( ...
                D, A, C, sol.T, M, config);
            allEvaluationPass = allEvaluationPass && nominalEval.exitflag == 1;
            key = solve_key(label, rho);
            solveByMethod(key) = sol;
            evalByMethod(key) = nominalEval;
            wdroRecords{end + 1, 1} = wdro_record(state, label, ...
                methodDefs.method(mm), methodDefs.kappa(mm), rho, sol, ...
                nominalEval, Cap, totalTime, observedMemory, distanceInfo, config); %#ok<SAGROW>
            for roleRow = 2:height(roleDefs)
                role = roleDefs.role(roleRow);
                data = roleData.(role_field(role));
                ev = evaluate_step03P_fixed_T_losses_h2( ...
                    data.D, data.A, data.C, sol.T, M, config);
                allEvaluationPass = allEvaluationPass && ev.exitflag == 1;
                validationRecords{end + 1, 1} = validation_record( ...
                    state, label, methodDefs.method(mm), methodDefs.kappa(mm), ...
                    rho, role, sol, ev, data, config); %#ok<SAGROW>
            end
        end
    end

    pairSample = deterministic_pairs(R, config.pairSampleCount, ...
        20263727 + state.initial_state_id);
    for mm = 1:height(methodDefs)
        label = methodDefs.label(mm);
        dMat = distanceByMethod(char(label));
        baseSol = solveByMethod(solve_key(label, 0.02));
        baseEval = evalByMethod(solve_key(label, 0.02));
        consistencyRecords{end + 1, 1} = consistency_record( ...
            state, label, methodDefs.method(mm), methodDefs.kappa(mm), ...
            dMat, baseEval.loss, pairSample); %#ok<SAGROW>
        selected = select_near_far_pairs(dMat, baseEval.loss, pairSample);
        for category = ["near","far"]
            pair = selected.(char(category));
            source = pair(1); destination = pair(2);
            if baseEval.loss(destination) < baseEval.loss(source)
                swap = source; source = destination; destination = swap;
            end
            shiftedWeights = uniformWeights;
            shiftedWeights(source) = shiftedWeights(source) - config.transferMass;
            shiftedWeights(destination) = shiftedWeights(destination) + config.transferMass;
            shifted = solve_step03P_weighted_cg_h2( ...
                D, A, C, Cap, M, 0.02, dMat, shiftedWeights, config);
            allSolverPass = allSolverPass && shifted.exitflag == 1 && shifted.converged;
            maxIndependentViolation = max(maxIndependentViolation, ...
                shifted.final_independent_scan_max_violation);
            decisionRecords{end + 1, 1} = decision_record( ...
                state, label, methodDefs.method(mm), methodDefs.kappa(mm), ...
                category, source, destination, selected, dMat, ...
                baseEval.loss, baseSol, shifted, config.transferMass); %#ok<SAGROW>
        end
    end
end

metricTbl = records_to_table(metricRecords);
distanceTbl = records_to_table(distanceRecords);
wdroTbl = records_to_table(wdroRecords);
validationTbl = records_to_table(validationRecords);
consistencyTbl = records_to_table(consistencyRecords);
decisionTbl = records_to_table(decisionRecords);
kappaTbl = build_kappa_comparison(wdroTbl, validationTbl, kappaValues);

newMetric = metricTbl(metricTbl.component ~= "old_total", :);
metricPass = all(newMetric.nonnegative_pass) && all(newMetric.zero_diagonal_pass) && ...
    all(newMetric.symmetry_pass) && all(newMetric.identity_violation_count == 0) && ...
    all(newMetric.random_triangle_violation_count == 0) && ...
    all(newMetric.directed_triangle_violation_count == 0) && ...
    max(newMetric.random_triangle_max_violation) <= config.triangleTolerance && ...
    max(newMetric.directed_triangle_max_violation) <= config.triangleTolerance;
zeroDistanceLossPass = all(consistencyTbl.zero_distance_positive_loss_count == 0);
[rho0TError, rho0ObjectiveError] = rho0_consistency(wdroTbl);
rho0Pass = rho0TError <= 1e-8 && rho0ObjectiveError <= 1e-8;
rhoPositivePass = all(wdroTbl.solve_status(wdroTbl.rho > 0) == "OPTIMAL");
independentScanPass = maxIndependentViolation <= config.violationTolerance;
nearCounterexample = severe_near_counterexample(decisionTbl);
validationMainWorse = validation_uniformly_worse(validationTbl, "new_Ctilde_k1p0");
coveragePass = all(coverageTbl.bound_violation_count == 0) && ...
    all(coverageTbl.reachable_C_min >= -1e-12) && Cbound > 0;

protectedAfter = hash_files(protectedFiles);
protectedPass = all(protectedAfter == protectedBefore);
step03JPass = directory_hash(inputDir) == step03JBefore && ...
    verify_role_hashes(roleDefs, inputDir);
oldRunsPass = directory_hash(step03PDir) == step03PBefore && ...
    directory_hash(step03PFailedDir) == step03PFailedBefore;
domainPass = table_finite(wdroTbl, ...
    {'T1','T2','T3','T4','objective_value','loss_mean','loss_q95','loss_q99'}) && ...
    table_finite(validationTbl, {'loss_mean','loss_q95','loss_q99','loss_max'});

if ~metricPass
    decision = "D. CTILDE_NOT_STRICT_METRIC";
elseif validationMainWorse
    decision = "C. CTILDE_METRIC_VALID_BUT_DECISION_PERFORMANCE_WORSE";
elseif ~rho0Pass || ~rhoPositivePass || ~independentScanPass || ...
        nearCounterexample || ~coveragePass || ~zeroDistanceLossPass
    decision = "E. CTILDE_AUDIT_INCONCLUSIVE";
else
    decision = "A. CTILDE_STRICT_METRIC_RECOMMENDED";
end

auditRows = {
    'BASE-01', pass_fail(lower(strtrim(string(headText))) == expectedHead), strtrim(string(headText)), expectedHead;
    'CBOUND-01', pass_fail(coveragePass), max(coverageTbl.reachable_C_max), Cbound;
    'PROOF-01', pass_fail(all(kappaValues >= 0.5)), mat2str(kappaValues), 'all kappa >= 0.5';
    'METRIC-01', pass_fail(metricPass), max(newMetric.random_triangle_max_violation), '<=1e-10 and no true violations';
    'IDENTITY-01', pass_fail(zeroDistanceLossPass), sum(consistencyTbl.zero_distance_positive_loss_count), '0';
    'RHO0-01', pass_fail(rho0Pass), max(rho0TError, rho0ObjectiveError), '<=1e-8';
    'SOLVE-01', pass_fail(allSolverPass && rhoPositivePass), allSolverPass && rhoPositivePass, 'all OPTIMAL and converged';
    'SOLVE-02', pass_fail(independentScanPass), maxIndependentViolation, '<=1e-8';
    'EVAL-01', pass_fail(allEvaluationPass), allEvaluationPass, 'all fixed-T evaluations OPTIMAL';
    'NEAR-01', pass_fail(~nearCounterexample), nearCounterexample, 'false';
    'VALID-01', pass_fail(~validationMainWorse), validationMainWorse, 'main candidate not uniformly worse';
    'CORE-01', pass_fail(protectedPass), protectedPass, 'formal WDRO/MSP unchanged';
    'DATA-01', pass_fail(step03JPass), step03JPass, 'Step-03J unchanged';
    'OLD-01', pass_fail(oldRunsPass), oldRunsPass, 'Step-03P run-001/run-002 unchanged';
    'DOMAIN-01', pass_fail(domainPass), domainPass, 'finite reported results';
    'SCOPE-01', 'PASS', '3 states and R=2000', 'no R=5000/R=15000/all-35-state run';
    'MSP-01', 'PASS', 'not run', 'MSP and formal distance not modified'};
acceptanceTbl = cell2table(auditRows, 'VariableNames', ...
    {'check_id','status','observed','expected'});
failCount = sum(strcmp(acceptanceTbl.status, 'FAIL'));
if failCount > 0
    error('Step-03Q audit has %d failures; no result archive or Git write.', failCount);
end

mkdir(tempDir);
writetable(metricTbl, fullfile(tempDir, 'step03Q_metric_property_tests.csv'));
writetable(kappaTbl, fullfile(tempDir, 'step03Q_kappa_comparison.csv'));
writetable(distanceTbl, fullfile(tempDir, 'step03Q_old_new_distance_statistics.csv'));
writetable(wdroTbl, fullfile(tempDir, 'step03Q_wdro_results.csv'));
writetable(validationTbl, fullfile(tempDir, 'step03Q_validation_results.csv'));
writetable(consistencyTbl, fullfile(tempDir, 'step03Q_distance_loss_consistency.csv'));
writetable(decisionTbl, fullfile(tempDir, 'step03Q_distance_decision_consistency.csv'));
writetable(acceptanceTbl, fullfile(tempDir, 'step03Q_acceptance_tests.csv'));
write_C_bound_audit(fullfile(tempDir, 'step03Q_C_bound_audit.md'), ...
    Cbound, roadAudit, coverageTbl);
write_Ctilde_definition(fullfile(tempDir, 'step03Q_Ctilde_definition.md'), ...
    Cbound, oldInfo.weights, Cap, penaltySource);
write_metric_proof(fullfile(tempDir, 'step03Q_metric_proof.md'), Cbound, kappaValues);
write_summary(fullfile(tempDir, 'step03Q_summary.txt'), decision, Cbound, ...
    metricTbl, kappaTbl, wdroTbl, validationTbl, consistencyTbl, ...
    decisionTbl, maxIndependentViolation, failCount);
movefile(tempDir, outputDir);

fprintf('\nStep-03Q completed: %s PASS=%d FAIL=%d\n', ...
    decision, height(acceptanceTbl), failCount);
fprintf('C_bound=%.12g km; max reachable C=%.12g km.\n', ...
    Cbound, max(coverageTbl.reachable_C_max));
fprintf('Maximum independent violation %.12g.\n', maxIndependentViolation);

function field = role_field(role)
field = char(replace(string(role), '-', '_'));
end

function key = solve_key(label, rho)
key = char(label + "|rho=" + string(sprintf('%.12g', rho)));
end

function data = load_frozen_state(path, stateId, R)
rows = (stateId - 1) * 15000 + (1:R);
m = matfile(path);
data = struct();
data.D = double(m.D_node_kg(rows, :));
data.A = double(m.A_site_node(rows, :, :));
data.C = double(m.C_site_node_km(rows, :, :));
data.path_id = double(m.path_id(rows, 1));
if any(double(m.initial_state_id(rows, 1)) ~= stateId) || ...
        ~isequal(size(data.A), [R,4,33]) || ~isequal(size(data.C), size(data.A))
    error('Step-03Q frozen state layout mismatch.');
end
end

function [bound, audit] = derive_C_bound(rootDir)
raw = load(fullfile(rootDir, 'data', 'yuanqi', 'near_stage_msp_input.mat'), ...
    'NearStageInput');
layout = build_h2_spatial_layout_preview(raw.NearStageInput);
nodes = sortrows(layout.nodes, 'node_id');
roadPath = fullfile(rootDir, 'data', 'yuanqi', 'stage1_road_edges.csv');
road = readtable(roadPath);
from = double(road.from_node); to = double(road.to_node);
lengths = hypot(nodes.x_km(to) - nodes.x_km(from), ...
    nodes.y_km(to) - nodes.y_km(from));
if any(~isfinite(lengths)) || any(lengths <= 0)
    error('Step-03Q road lengths must be finite and positive.');
end
bound = 2 * sum(lengths);
audit = struct('road_file', string(roadPath), 'edge_count', height(road), ...
    'sum_road_length_km', sum(lengths), 'max_edge_length_km', max(lengths), ...
    'slowdown_multiplier_upper', 2, 'C_bound_km', bound);
end

function tbl = scan_C_coverage(roleDefs, inputDir, bound, blockSize)
rows = cell(height(roleDefs), 1);
for rr = 1:height(roleDefs)
    path = fullfile(inputDir, roleDefs.mat_name(rr));
    m = matfile(path);
    sz = size(m, 'C_site_node_km');
    minValue = inf; maxValue = -inf; count = 0; violations = 0;
    for start = 1:blockSize:sz(1)
        idx = start:min(sz(1), start + blockSize - 1);
        A = double(m.A_site_node(idx, :, :));
        C = double(m.C_site_node_km(idx, :, :));
        values = C(A > 0.5);
        minValue = min(minValue, min(values));
        maxValue = max(maxValue, max(values));
        count = count + numel(values);
        violations = violations + sum(values > bound + 1e-12 | values < -1e-12);
    end
    rows{rr} = struct('dataset_role', roleDefs.role(rr), ...
        'record_count', sz(1), 'reachable_C_count', count, ...
        'reachable_C_min', minValue, 'reachable_C_max', maxValue, ...
        'C_bound_km', bound, 'bound_margin_km', bound - maxValue, ...
        'bound_violation_count', violations);
end
tbl = records_to_table(rows);
end

function rec = distance_record(state, label, info, detail)
if isempty(detail.d_Ctilde)
    cMin = NaN; cMedian = NaN; cMax = NaN;
else
    upper = triu(true(size(detail.d_Ctilde)), 1);
    values = detail.d_Ctilde(upper & detail.d_Ctilde > 1e-12);
    cMin = min(values); cMedian = median(values); cMax = max(values);
end
rec = struct('complexity_label', state.complexity_label, ...
    'initial_state_id', state.initial_state_id, 'distance_label', label, ...
    'requested_method', info.requested_method, 'kappa', info.kappa, ...
    'C_bound_km', info.C_bound, 'weight_D', info.weight_D, ...
    'weight_A_old', info.weight_A_old, 'weight_C_old', info.weight_C_old, ...
    'weight_Ctilde', info.weight_Ctilde, ...
    'unscaled_min', info.unscaled_min, ...
    'unscaled_nonzero_median', info.unscaled_nonzero_median, ...
    'unscaled_max', info.unscaled_max, ...
    'fair_scale_factor', info.fair_comparison_scale_factor, ...
    'old_nonzero_median', info.old_nonzero_median, ...
    'scaled_nonzero_median', info.scaled_nonzero_median, ...
    'scaled_max', info.scaled_max, 'Ctilde_min_positive', cMin, ...
    'Ctilde_nonzero_median', cMedian, 'Ctilde_max', cMax);
end

function rec = metric_record(state, label, component, d, components, ...
        randomTriples, directedTriples, directedMask, config)
R = size(d, 1);
randomViolation = triple_violation(d, randomTriples);
if any(directedMask)
    directed = subset_triples(directedTriples, directedMask);
    directedViolation = triple_violation(d, directed);
else
    directedViolation = 0;
end
upper = triu(true(R), 1);
if component == "Ctilde_component"
    representedDifferent = components.rawA > 1e-12 | components.rawC > 1e-12;
else
    representedDifferent = components.rawD > 1e-12 | ...
        components.rawA > 1e-12 | components.rawC > 1e-12;
end
identityViolation = upper & representedDifferent & d <= 1e-12;
rec = struct('complexity_label', state.complexity_label, ...
    'initial_state_id', state.initial_state_id, 'distance_label', label, ...
    'component', component, 'nonnegative_pass', min(d, [], 'all') >= -1e-12, ...
    'min_distance', min(d, [], 'all'), ...
    'zero_diagonal_pass', max(abs(diag(d))) <= 1e-12, ...
    'max_diagonal_abs', max(abs(diag(d))), ...
    'symmetry_pass', max(abs(d - d.'), [], 'all') <= 1e-12, ...
    'max_symmetry_abs', max(abs(d - d.'), [], 'all'), ...
    'identity_violation_count', nnz(identityViolation), ...
    'random_triangle_test_count', numel(randomViolation), ...
    'random_triangle_violation_count', sum(randomViolation > config.triangleTolerance), ...
    'random_triangle_max_violation', max(randomViolation), ...
    'step03P_maskedC_violation_triple_count', sum(directedMask), ...
    'directed_triangle_violation_count', sum(directedViolation > config.triangleTolerance), ...
    'directed_triangle_max_violation', max(directedViolation));
end

function rec = wdro_record(state, label, method, kappa, rho, sol, ev, ...
        Cap, totalTime, observedMemory, distanceInfo, config)
rec = struct('complexity_label', state.complexity_label, ...
    'initial_state_id', state.initial_state_id, 'distance_label', label, ...
    'method', method, 'kappa', kappa, 'rho', rho, ...
    'T1', sol.T(1), 'T2', sol.T(2), 'T3', sol.T(3), 'T4', sol.T(4), ...
    'T_total', sum(sol.T), 'objective_value', sol.objective_value, ...
    'terminal_holding_cost', config.gamma * sum(sol.T), ...
    'lambda_rho_cost', sol.lambda_rho_cost, ...
    'alpha_weighted_cost', sol.alpha_weighted_cost, ...
    'robust_dual_loss', sol.robust_dual_loss, 'lambda', sol.lambda, ...
    'loss_mean', mean(ev.loss), 'loss_q95', pct(ev.loss,95), ...
    'loss_q99', pct(ev.loss,99), 'loss_max', max(ev.loss), ...
    'service_cost_mean', mean(ev.service_cost), ...
    'shortage_kg_mean', mean(ev.shortage_kg), ...
    'upper_bound_count', sum(abs(sol.T - Cap) <= 1e-7), ...
    'iteration_count', height(sol.history), ...
    'active_constraint_count', sol.final_active_constraints, ...
    'active_constraint_ratio', sol.active_constraint_ratio, ...
    'max_independent_violation', sol.final_independent_scan_max_violation, ...
    'gurobi_time_sec', sol.total_solve_time_sec, ...
    'separation_time_sec', sol.total_separation_time_sec, ...
    'independent_scan_time_sec', sol.final_independent_scan_time_sec, ...
    'total_call_time_sec', totalTime, ...
    'observed_memory_snapshot_peak_mb', observedMemory, ...
    'fair_scale_factor', distanceInfo.fair_comparison_scale_factor, ...
    'solve_status', sol.status);
end

function rec = validation_record(state, label, method, kappa, rho, role, sol, ev, data, config)
unreachable = reshape(any(data.A <= 0.5, [2,3]), [], 1);
rec = struct('complexity_label', state.complexity_label, ...
    'initial_state_id', state.initial_state_id, 'distance_label', label, ...
    'method', method, 'kappa', kappa, 'rho', rho, 'dataset_role', role, ...
    'T1', sol.T(1), 'T2', sol.T(2), 'T3', sol.T(3), 'T4', sol.T(4), ...
    'terminal_holding_cost', config.gamma * sum(sol.T), ...
    'loss_mean', mean(ev.loss), 'loss_q95', pct(ev.loss,95), ...
    'loss_q99', pct(ev.loss,99), 'loss_max', max(ev.loss), ...
    'loss_any_unreachable_mean', conditional_mean(ev.loss, unreachable), ...
    'loss_fully_reachable_mean', conditional_mean(ev.loss, ~unreachable), ...
    'validation_total_cost', config.gamma * sum(sol.T) + mean(ev.loss), ...
    'evaluation_status', ev.status);
end

function rec = consistency_record(state, label, method, kappa, dMat, loss, pairs)
R = size(dMat, 1);
idx = sub2ind([R,R], pairs.i, pairs.j);
d = dMat(idx);
lossDiff = abs(loss(pairs.i) - loss(pairs.j));
smallCut = pct(d, 5); largeCut = pct(lossDiff, 95);
anomaly = d <= smallCut & lossDiff > max(largeCut, 1e-8);
zeroDistance = d <= 1e-12 & lossDiff > 1e-8;
rec = struct('complexity_label', state.complexity_label, ...
    'initial_state_id', state.initial_state_id, 'distance_label', label, ...
    'method', method, 'kappa', kappa, 'pair_sample_count', numel(d), ...
    'spearman_distance_loss_difference', spearman_corr(d, lossDiff), ...
    'small_distance_q05', smallCut, 'large_loss_difference_q95', largeCut, ...
    'small_distance_large_loss_count', sum(anomaly), ...
    'small_distance_large_loss_share', mean(anomaly), ...
    'zero_distance_positive_loss_count', sum(zeroDistance), ...
    'loss_difference_mean', mean(lossDiff), ...
    'loss_difference_q95', pct(lossDiff,95), 'loss_difference_max', max(lossDiff));
end

function selected = select_near_far_pairs(dMat, loss, pairs)
R = size(dMat, 1);
idx = sub2ind([R,R], pairs.i, pairs.j);
d = dMat(idx); lossDiff = abs(loss(pairs.i) - loss(pairs.j));
positive = d > 1e-12;
nearCut = pct(d(positive), 5); farCut = pct(d(positive), 95);
nearCandidates = find(positive & d <= nearCut);
farCandidates = find(positive & d >= farCut);
[~, nearLocal] = max(lossDiff(nearCandidates));
[~, farLocal] = max(lossDiff(farCandidates));
nearIdx = nearCandidates(nearLocal); farIdx = farCandidates(farLocal);
selected = struct('near', [pairs.i(nearIdx),pairs.j(nearIdx)], ...
    'far', [pairs.i(farIdx),pairs.j(farIdx)], ...
    'near_cut', nearCut, 'far_cut', farCut);
end

function rec = decision_record(state, label, method, kappa, category, ...
        source, destination, selected, dMat, loss, base, shifted, transferMass)
rec = struct('complexity_label', state.complexity_label, ...
    'initial_state_id', state.initial_state_id, 'distance_label', label, ...
    'method', method, 'kappa', kappa, 'pair_category', category, ...
    'near_q05_cut', selected.near_cut, 'far_q95_cut', selected.far_cut, ...
    'source_scenario_index', source, 'destination_scenario_index', destination, ...
    'transport_cost', dMat(source,destination), ...
    'absolute_loss_difference', abs(loss(destination)-loss(source)), ...
    'probability_mass_transferred', transferMass, ...
    'baseline_T1', base.T(1), 'baseline_T2', base.T(2), ...
    'baseline_T3', base.T(3), 'baseline_T4', base.T(4), ...
    'shifted_T1', shifted.T(1), 'shifted_T2', shifted.T(2), ...
    'shifted_T3', shifted.T(3), 'shifted_T4', shifted.T(4), ...
    'TerminalLOH_max_abs_change', max(abs(shifted.T-base.T)), ...
    'objective_change', shifted.objective_value-base.objective_value, ...
    'source_to_destination_active_constraint', ...
        logical(shifted.activeMask(source,destination)), ...
    'max_independent_violation', shifted.final_independent_scan_max_violation);
end

function tbl = build_kappa_comparison(wdroTbl, validationTbl, kappaValues)
rows = cell(0, 1);
for stateId = unique(wdroTbl.initial_state_id).'
    old = wdroTbl(wdroTbl.initial_state_id==stateId & ...
        wdroTbl.distance_label=="old_D_A_maskedC" & abs(wdroTbl.rho-0.02)<=1e-12,:);
    oldVal = validationTbl(validationTbl.initial_state_id==stateId & ...
        validationTbl.distance_label=="old_D_A_maskedC" & ...
        abs(validationTbl.rho-0.02)<=1e-12,:);
    for kappa = kappaValues
        label = kappa_label(kappa);
        candidate = wdroTbl(wdroTbl.initial_state_id==stateId & ...
            wdroTbl.distance_label==label & abs(wdroTbl.rho-0.02)<=1e-12,:);
        candidateVal = validationTbl(validationTbl.initial_state_id==stateId & ...
            validationTbl.distance_label==label & abs(validationTbl.rho-0.02)<=1e-12,:);
        candidateVal = sortrows(candidateVal, 'dataset_role');
        oldValNow = sortrows(oldVal, 'dataset_role');
        rows{end+1,1} = struct('complexity_label', old.complexity_label, ...
            'initial_state_id', stateId, 'kappa', kappa, ...
            'TerminalLOH_max_abs_difference_vs_old', max(abs( ...
                [candidate.T1-old.T1,candidate.T2-old.T2, ...
                 candidate.T3-old.T3,candidate.T4-old.T4])), ...
            'objective_difference_vs_old', candidate.objective_value-old.objective_value, ...
            'validation_total_cost_difference_mean', mean( ...
                candidateVal.validation_total_cost-oldValNow.validation_total_cost), ...
            'validation_total_cost_difference_max', max( ...
                candidateVal.validation_total_cost-oldValNow.validation_total_cost), ...
            'validation_q95_difference_max', max(candidateVal.loss_q95-oldValNow.loss_q95), ...
            'validation_q99_difference_max', max(candidateVal.loss_q99-oldValNow.loss_q99)); %#ok<AGROW>
    end
end
tbl = records_to_table(rows);
end

function label = kappa_label(kappa)
if abs(kappa-0.5)<=1e-12
    label = "new_Ctilde_k0p5";
elseif abs(kappa-1)<=1e-12
    label = "new_Ctilde_k1p0";
else
    label = "new_Ctilde_k1p5";
end
end

function [tError, objectiveError] = rho0_consistency(tbl)
rows = tbl(abs(tbl.rho)<=1e-12,:);
tError = 0; objectiveError = 0;
for stateId = unique(rows.initial_state_id).'
    block = rows(rows.initial_state_id==stateId,:);
    T = [block.T1,block.T2,block.T3,block.T4];
    tError = max(tError, max(abs(T-T(1,:)), [], 'all'));
    objectiveError = max(objectiveError, ...
        max(abs(block.objective_value-block.objective_value(1))));
end
end

function value = severe_near_counterexample(tbl)
value = false;
for stateId = unique(tbl.initial_state_id).'
    for label = unique(tbl.distance_label(tbl.initial_state_id==stateId)).'
        block = tbl(tbl.initial_state_id==stateId & tbl.distance_label==label,:);
        near = block.TerminalLOH_max_abs_change(block.pair_category=="near");
        far = block.TerminalLOH_max_abs_change(block.pair_category=="far");
        value = value || near > far + 1e-7;
    end
end
end

function value = validation_uniformly_worse(tbl, label)
newRows = sortrows(tbl(tbl.distance_label==label & abs(tbl.rho-0.02)<=1e-12,:), ...
    {'initial_state_id','dataset_role'});
oldRows = sortrows(tbl(tbl.distance_label=="old_D_A_maskedC" & ...
    abs(tbl.rho-0.02)<=1e-12,:), {'initial_state_id','dataset_role'});
value = height(newRows)==height(oldRows) && ...
    all(newRows.validation_total_cost > oldRows.validation_total_cost + 1e-6) && ...
    all(newRows.loss_q95 >= oldRows.loss_q95 - 1e-8);
end

function triples = deterministic_triples(R, count, seed)
rng(seed, 'twister');
i = randi(R, count, 1); j = randi(R, count, 1); k = randi(R, count, 1);
mask = i==j; while any(mask), j(mask)=randi(R,sum(mask),1); mask=i==j; end
mask = k==i | k==j;
while any(mask), k(mask)=randi(R,sum(mask),1); mask=k==i | k==j; end
triples = struct('i',i,'j',j,'k',k);
end

function out = subset_triples(in, mask)
out = struct('i',in.i(mask),'j',in.j(mask),'k',in.k(mask));
end

function violation = triple_violation(d, triples)
R = size(d,1);
if isempty(triples.i), violation=0; return; end
violation = d(sub2ind([R,R],triples.i,triples.k)) - ...
    d(sub2ind([R,R],triples.i,triples.j)) - ...
    d(sub2ind([R,R],triples.j,triples.k));
end

function pairs = deterministic_pairs(R, count, seed)
rng(seed, 'twister');
i = randi(R,count,1); j = randi(R,count,1);
mask=i==j; while any(mask),j(mask)=randi(R,sum(mask),1);mask=i==j;end
pairs=struct('i',i,'j',j);
end

function value = conditional_mean(x, mask)
if any(mask), value=mean(x(mask)); else, value=NaN; end
end

function value = spearman_corr(x,y)
x=double(x(:));y=double(y(:));mask=isfinite(x)&isfinite(y);x=x(mask);y=y(mask);
if numel(x)<2||all(x==x(1))||all(y==y(1)),value=NaN;return;end
rx=average_rank(x);ry=average_rank(y);rx=rx-mean(rx);ry=ry-mean(ry);
value=sum(rx.*ry)/sqrt(sum(rx.^2)*sum(ry.^2));
end

function ranks = average_rank(x)
[sorted,order]=sort(x);ranksSorted=zeros(size(sorted));start=1;
while start<=numel(sorted)
    stop=start;while stop<numel(sorted)&&sorted(stop+1)==sorted(start),stop=stop+1;end
    ranksSorted(start:stop)=0.5*(start+stop);start=stop+1;
end
ranks=zeros(size(x));ranks(order)=ranksSorted;
end

function value = pct(x,p)
x=sort(double(x(isfinite(x))));if isempty(x),value=NaN;return;end
pos=1+(numel(x)-1)*p/100;lo=floor(pos);hi=ceil(pos);
if lo==hi,value=x(lo);else,value=x(lo)+(pos-lo)*(x(hi)-x(lo));end
end

function tbl = records_to_table(records)
if isempty(records),tbl=table();else,tbl=struct2table(vertcat(records{:}));end
end

function ok = table_finite(tbl,names)
ok=true;for ii=1:numel(names),ok=ok&&all(isfinite(tbl.(names{ii})));end
end

function [usedBytes,availableBytes] = memory_snapshot()
try
    [u,~]=memory;usedBytes=double(u.MemUsedMATLAB);availableBytes=double(u.MemAvailableAllArrays);
catch
    usedBytes=NaN;availableBytes=NaN;
end
end

function ok = verify_role_hashes(roleDefs,inputDir)
ok=true;for rr=1:height(roleDefs),ok=ok&&sha256_file(fullfile(inputDir,roleDefs.mat_name(rr)))==roleDefs.mat_sha256(rr);end
end

function hashes = hash_files(files)
hashes=strings(numel(files),1);for ii=1:numel(files),hashes(ii)=sha256_file(files(ii));end
end

function value = directory_hash(path)
if ~isfolder(path),value="MISSING";return;end
files=dir(fullfile(path,'**','*'));files=files(~[files.isdir]);relative=strings(numel(files),1);
for ii=1:numel(files),relative(ii)=erase(string(fullfile(files(ii).folder,files(ii).name)),string(path)+filesep);end
relative=sort(relative);payload=strings(numel(relative),1);
for ii=1:numel(relative),payload(ii)=relative(ii)+"|"+sha256_file(fullfile(path,relative(ii)));end
value=sha256_text(join(payload,newline));
end

function value = sha256_file(path)
fid=fopen(path,'rb');if fid<0,error('Cannot open file for SHA-256: %s',path);end
cleaner=onCleanup(@()fclose(fid));md=java.security.MessageDigest.getInstance('SHA-256');
while true,bytes=fread(fid,1024*1024,'*uint8');if isempty(bytes),break;end;md.update(bytes);end
value=lower(string(reshape(dec2hex(typecast(md.digest(),'uint8'),2).',1,[])));clear cleaner;
end

function value = sha256_text(textValue)
md=java.security.MessageDigest.getInstance('SHA-256');md.update(unicode2native(char(textValue),'UTF-8'));
value=lower(string(reshape(dec2hex(typecast(md.digest(),'uint8'),2).',1,[])));
end

function value = pass_fail(condition)
if condition,value='PASS';else,value='FAIL';end
end

function write_C_bound_audit(path,bound,road,coverage)
lines=["# Step-03Q C Bound Audit";"";"## Deterministic bound";""; ...
"The formal B3 road cost is `edgeCost = roadLength .* (1 + pClose)` and closed edges are set to `Inf` (`evaluate_formal_stagewise_b3_stability_block_h2.m:47-48,63-76`). `compute_line_failure_prob_h2.m:9-13` clips pClose to [0,1]."; ...
"All finite edge costs therefore satisfy `edgeCost <= 2*roadLength`. Positive edge costs imply a reachable shortest path can be chosen simple, so it uses each road edge at most once. Every possible reachable path cost is bounded by `2*sum(all road lengths)`. A mean across reachable critical W1-W3 windows remains under the same bound (`aggregate_W3_DAC_outcomes_h2.m:23-55`).";""; ...
"Road coordinates are the same `layout.nodes.x_km/y_km` used by the formal B3 model (`build_foundation_fix_coordinates_h2.m:162-184`; `run_stage3i_formal_stagewise_random_b3_h2.m:440-477`).";""; ...
"- road_file: `"+road.road_file+"`";"- edge_count: "+string(road.edge_count); ...
"- sum_road_length_km: "+string(sprintf('%.16g',road.sum_road_length_km)); ...
"- maximum finite edge multiplier: 2";"- C_bound_km: "+string(sprintf('%.16g',bound));"";"## Full frozen-data coverage";""];
for rr=1:height(coverage)
    lines(end+1)="- "+coverage.dataset_role(rr)+": records="+coverage.record_count(rr)+ ...
        ", reachable values="+coverage.reachable_C_count(rr)+", min="+ ...
        string(sprintf('%.12g',coverage.reachable_C_min(rr)))+", max="+ ...
        string(sprintf('%.12g',coverage.reachable_C_max(rr)))+ ...
        ", violations="+coverage.bound_violation_count(rr); %#ok<AGROW>
end
lines(end+1)="";lines(end+1)="This bound is topology- and model-derived, not the R=2000 sample maximum and not a physical upper bound for arbitrary external road networks.";
write_lines(path,lines);
end

function write_Ctilde_definition(path,bound,weights,Cap,penaltySource)
lines=["# Step-03Q Ctilde Definition and Model Scope";""; ...
"`A=1` means every demand-critical W1-W3 window has a feasible road path; `A=0` means at least one critical window is unreachable. Slow but open roads keep A=1 (`aggregate_W3_DAC_outcomes_h2.m:14-55`)."; ...
"`C` is the mean current-road-state shortest-path impedance in km over reachable critical windows. Closures enter as infinite edge costs and slowdown uses `roadLength*(1+pClose)`, so C includes detours and nonclosed-road slowdown.";""; ...
"For one site-node feature, unreachable-unreachable has distance 0, reachable-reachable has `abs(C_r/C_bound-C_s/C_bound)`, and a reachability mismatch has distance kappa. The 132 feature distances are averaged."; ...
"The accepted old weights are read by calling `build_wdro_distance_matrix_h2(...,'DAC_maskedC',...)`, not hard-coded into the candidate: D/A/C="+string(weights.D)+"/"+string(weights.A)+"/"+string(weights.C)+". The new weights are w_D="+string(weights.D)+" and w_Ctilde=w_A+w_C="+string(weights.A+weights.C)+"."; ...
"C_bound="+string(sprintf('%.16g',bound))+" km. Candidate distances are median-matched to the accepted old distance only for this audit; unscaled statistics are retained.";""; ...
"A is removed only as a separate ground-distance component. It remains in the supply model: `y_i,n^s <= A_i,n^s D_n^s` (`solve_wdro_terminal_loh_lp_h2.m:31-52`) and thus A=0 forbids service. C remains the service-cost coefficient (`solve_wdro_terminal_loh_lp_h2.m:82-107`). A has not been deleted from the model."; ...
"Full capacity is ["+join(string(Cap.'),",")+ "] kg. Shortage penalty source: `"+penaltySource+"`.";""; ...
"Selvi, Belbasi, Haugh, and Wiesemann (2022), `Wasserstein Logistic Regression with Mixed Features`, NeurIPS, motivates separate treatment of categorical and continuous feature differences. Step-03Q adapts that idea to binary reachability plus continuous reachable road impedance; it does not change the loss model or write the candidate into the formal WDRO default."];
write_lines(path,lines);
end

function write_metric_proof(path,bound,kappas)
lines=["# Step-03Q Metric Proof";""; ...
"Let U contain one unreachable symbol and reachable values c in [0,1], where c=C/C_bound. Define delta(U,U)=0, delta(c1,c2)=|c1-c2|, and delta(U,c)=delta(c,U)=kappa.";""; ...
"Nonnegativity, symmetry, and identity are immediate. For the triangle inequality:";""; ...
"1. All three reachable: ordinary absolute distance on [0,1] satisfies the triangle inequality."; ...
"2. All three unreachable: every term is zero."; ...
"3. One unreachable and two reachable: the only nontrivial inequality is |c1-c2| <= 2*kappa. Since |c1-c2|<=1, this holds for kappa>=0.5. The other orientations reduce to kappa<=kappa+|c1-c2|."; ...
"4. Two unreachable and one reachable: the nonzero direct distance is kappa and the two-leg alternatives are kappa or 2*kappa, so the inequality holds.";""; ...
"Therefore every local delta is a metric for kappa>=0.5. The mean of 132 local metrics is a metric on the Ctilde representation. The normalized node-demand L1 distance is also a metric under its fixed positive scale. A positive weighted sum with w_D>0 and w_Ctilde>0 is a metric on the joint (D,Ctilde) representation. Positive audit median scaling preserves all metric axioms.";""; ...
"Tested kappa values: "+join(string(kappas),", ")+". C_bound="+string(sprintf('%.16g',bound))+" km ensures every reachable normalized C lies in [0,1]."];
write_lines(path,lines);
end

function write_summary(path,decision,bound,metric,kappa,wdro,validation,consistency,decisionTbl,maxViolation,failCount)
newMetric=metric(metric.component~="old_total",:);main=kappa(abs(kappa.kappa-1)<=1e-12,:);
mainWdro=wdro(wdro.distance_label=="new_Ctilde_k1p0"&abs(wdro.rho-0.02)<=1e-12,:);
oldWdro=wdro(wdro.distance_label=="old_D_A_maskedC"&abs(wdro.rho-0.02)<=1e-12,:);
maxTDiff=max(abs([mainWdro.T1-oldWdro.T1,mainWdro.T2-oldWdro.T2,mainWdro.T3-oldWdro.T3,mainWdro.T4-oldWdro.T4]),[],'all');
mainVal=sortrows(validation(validation.distance_label=="new_Ctilde_k1p0"&abs(validation.rho-0.02)<=1e-12,:),{'initial_state_id','dataset_role'});
oldVal=sortrows(validation(validation.distance_label=="old_D_A_maskedC"&abs(validation.rho-0.02)<=1e-12,:),{'initial_state_id','dataset_role'});
valDelta=mainVal.validation_total_cost-oldVal.validation_total_cost;
near=decisionTbl(decisionTbl.pair_category=="near",:);far=decisionTbl(decisionTbl.pair_category=="far",:);
lines=["Step-03Q D + Ctilde strict metric audit";"PASS="+string(17-failCount);"FAIL="+string(failCount); ...
"decision="+decision;"C_bound_km="+string(sprintf('%.16g',bound));"recommended_kappa=1"; ...
"new_metric_random_triangle_max_violation="+string(sprintf('%.16g',max(newMetric.random_triangle_max_violation))); ...
"new_metric_directed_triangle_max_violation="+string(sprintf('%.16g',max(newMetric.directed_triangle_max_violation))); ...
"zero_distance_positive_loss_count="+string(sum(consistency.zero_distance_positive_loss_count)); ...
"max_independent_constraint_violation="+string(sprintf('%.16g',maxViolation)); ...
"kappa1_max_T_difference_vs_old_kg="+string(sprintf('%.16g',maxTDiff)); ...
"kappa1_validation_total_cost_delta_range="+range_text(valDelta); ...
"near_T_change_range="+range_text(near.TerminalLOH_max_abs_change); ...
"far_T_change_range="+range_text(far.TerminalLOH_max_abs_change); ...
"distance_loss_spearman_range="+range_text(consistency.spearman_distance_loss_difference); ...
"kappa1_state_validation_delta_mean_range="+range_text(main.validation_total_cost_difference_mean); ...
"formal_distance_modified=false";"A_removed_from_loss_model=false";"Step03J_modified=false"; ...
"Step03P_modified=false";"MSP_run=false";"R5000_run=false";"R15000_run=false"; ...
"validation_note=validation roles reuse the same W paths and mainly redraw second-layer wind/resistance"; ...
"rho_note=median matching is audit-only; a formal replacement requires radius recalibration or a frozen permanent scale"];
write_lines(path,lines);
end

function text = range_text(x)
x=double(x(isfinite(x)));if isempty(x),text="NaN";else,text=string(sprintf('%.12g..%.12g',min(x),max(x)));end
end

function write_lines(path,lines)
fid=fopen(path,'w');if fid<0,error('Cannot write %s.',path);end
cleaner=onCleanup(@()fclose(fid));for ii=1:numel(lines),fprintf(fid,'%s\n',char(lines(ii)));end;clear cleaner;
end
