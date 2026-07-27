clear; clc;

thisDir = fileparts(mfilename('fullpath'));
moduleDir = fileparts(thisDir);
rootDir = fileparts(moduleDir);
inputDir = fullfile(moduleDir, 'output', 'stage3j_wdro_input_freeze', 'run-001');
outputDir = fullfile(rootDir, 'results', 'task-002-stage2b-b3-smoke', ...
    '16-dac-transport-cost-audit', 'run-002');
if exist(outputDir, 'dir')
    error('Step-03P run-002 already exists; do not overwrite old runs.');
end
addpath(rootDir);
addpath(thisDir);
for candidate = {fullfile(getenv('GUROBI_HOME'), 'matlab'), ...
        'D:\gurobi1201\win64\matlab', 'C:\gurobi1201\win64\matlab'}
    if ~isempty(candidate{1}) && exist(candidate{1}, 'dir')
        addpath(candidate{1});
    end
end
if ~ismember(exist('gurobi', 'file'), [2, 3])
    error('Step-03P requires the existing Gurobi MATLAB interface.');
end

expectedHead = "79fabedbe82f02578d10f3fbe3c3095c555278d5";
[headStatus, headText] = system('git rev-parse HEAD');
if headStatus ~= 0 || lower(strtrim(string(headText))) ~= expectedHead
    error('Step-03P must start from baseline commit %s.', expectedHead);
end

roleDefs = table( ...
    ["nominal";"validation-1";"validation-2"], ...
    ["wdro_nominal_input.csv";"wdro_validation_1.csv";"wdro_validation_2.csv"], ...
    ["wdro_nominal_input_DAC.mat";"wdro_validation_1_DAC.mat";"wdro_validation_2_DAC.mat"], ...
    ["366dc3c0b57bfd76aca92f51ae1db82b93c764c87fa15e8cb4dd32388d018168"; ...
     "e39253d5af25d312b5d65cbb4efdf5ad4e907843f9203a46c47c7ca058ed3099"; ...
     "91c8e1233017d5d7dea9a87592f5bfb196e0d629733c10892fb539e4228c9b02"], ...
    ["6936a696f5cde137aca483f8c32adee33b52cbd90559a8e6395f3686c0712945"; ...
     "ca84afa01748d8c2929c372802861315254723424786b681a677e2f1420b6e3f"; ...
     "0bae20fa685940751edf5c5dd3d6c43a2d52293cbd1350c02b84736e914ec3b6"], ...
    'VariableNames', {'role','csv_name','mat_name','csv_sha256','mat_sha256'});
for rr = 1:height(roleDefs)
    csvPath = fullfile(inputDir, roleDefs.csv_name(rr));
    matPath = fullfile(inputDir, roleDefs.mat_name(rr));
    if sha256_file(csvPath) ~= roleDefs.csv_sha256(rr) || ...
            sha256_file(matPath) ~= roleDefs.mat_sha256(rr)
        error('Step-03J frozen input hash mismatch for %s.', roleDefs.role(rr));
    end
end

protectedFiles = [ ...
    string(fullfile(thisDir, 'build_wdro_distance_matrix_h2.m')); ...
    string(fullfile(thisDir, 'solve_wdro_terminal_loh_lp_h2.m')); ...
    string(fullfile(thisDir, 'solve_wdro_terminal_loh_lp_constraint_generation_h2.m')); ...
    string(fullfile(thisDir, 'load_frozen_b3_wdro_dataset_h2.m')); ...
    string(fullfile(rootDir, 'main_msp_h2_near.m')); ...
    string(fullfile(rootDir, 'h2_default_options.m')); ...
    string(fullfile(rootDir, 'run_h2_with_options.m')); ...
    string(fullfile(rootDir, 'fa_h2', 'build_stage_model_h2.m')); ...
    string(fullfile(rootDir, 'fa_h2', 'update_rhs_h2.m')); ...
    string(fullfile(rootDir, 'fa_h2', 'solve_stage_model_h2.m'))];
protectedBefore = hash_files(protectedFiles);
step03JBefore = directory_hash(inputDir);
step03NDir = fullfile(rootDir, 'results', 'task-002-stage2b-b3-smoke', ...
    '14-wdro-constraint-generation-scale', 'run-001');
step03ODir = fullfile(rootDir, 'results', 'task-002-stage2b-b3-smoke', ...
    '15-terminal-loh-rationality-audit', 'run-001');
step03NBefore = directory_hash(step03NDir);
step03OBefore = directory_hash(step03ODir);

raw = load(fullfile(rootDir, 'data', 'yuanqi', 'near_stage_msp_input.mat'), ...
    'NearStageInput');
ni = raw.NearStageInput;
Cap = double(ni.HydrogenDevice.tank_cap_kg(:));
expectedCap = [300;200;100;150];
if max(abs(Cap - expectedCap)) > 1e-12
    error('Step-03P full capacity vector is not [300,200,100,150].');
end
if isfield(ni.Cost, 'reserve_shortage_penalty_yuan_per_kg')
    M = double(ni.Cost.reserve_shortage_penalty_yuan_per_kg);
    penaltySource = "NearStageInput.Cost.reserve_shortage_penalty_yuan_per_kg";
elseif isfield(ni.Cost, 'cost_reserve_shortage')
    M = double(ni.Cost.cost_reserve_shortage);
    penaltySource = "NearStageInput.Cost.cost_reserve_shortage";
else
    error('Step-03P cannot trace the shortage penalty source.');
end

config = struct();
config.gamma = 0.001 * M;
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
config.pairSampleCount = 200000;
config.triangleSampleCount = 200000;
config.transferMass = 0.5 / 2000;
baseWeights = struct('D', 0.6, 'A', 0.25, 'C', 0.15);

states = table([7;18;30], [2;4;6], [7;4;2], [0;0;0], ...
    ["simple";"medium";"complex"], ...
    'VariableNames', {'initial_state_id','a0','loc0','lfw0','complexity_label'});
R = 2000;
rhoValues = [0, 0.02];
uniformWeights = ones(R, 1) / R;
regionMap = build_static_service_regions(rootDir);

ablationRecords = cell(0, 1);
granularityRecords = cell(0, 1);
weightRecords = cell(0, 1);
fullCapacityRecords = cell(0, 1);
metricRecords = cell(0, 1);
componentRecords = cell(0, 1);
consistencyRecords = cell(0, 1);
decisionRecords = cell(0, 1);
allSolverPass = true;
allEvaluationPass = true;
maxIndependentViolation = 0;
rho0ReferenceT = containers.Map('KeyType', 'char', 'ValueType', 'any');

for stateRow = 1:height(states)
    state = states(stateRow, :);
    fprintf('\nStep-03P state %s (%d): loading frozen D/A/C.\n', ...
        char(state.complexity_label), state.initial_state_id);
    roleData = struct();
    for roleRow = 1:height(roleDefs)
        field = role_field(roleDefs.role(roleRow));
        roleData.(field) = load_frozen_mat_state( ...
            fullfile(inputDir, roleDefs.mat_name(roleRow)), ...
            state.initial_state_id, R);
    end
    if ~isequal(roleData.nominal.path_id, roleData.validation_1.path_id) || ...
            ~isequal(roleData.nominal.path_id, roleData.validation_2.path_id)
        error('Step-03P path order differs across frozen dataset roles.');
    end
    D = roleData.nominal.D;
    A = roleData.nominal.A;
    C = roleData.nominal.C;

    Dregion = zeros(R, 4);
    for site = 1:4
        Dregion(:, site) = sum(D(:, regionMap == site), 2);
    end
    Dtotal = sum(D, 2);
    fprintf('Building full pairwise components for 33-node D.\n');
    components33 = build_step03P_distance_components_h2(D, A, C, config);
    fprintf('Building full pairwise components for 4-region D.\n');
    componentsRegion = build_step03P_distance_components_h2(Dregion, A, C, config);
    fprintf('Building full pairwise components for total D.\n');
    componentsTotal = build_step03P_distance_components_h2(Dtotal, A, C, config);

    [baselineDistance, baselineDetail] = compose_step03P_transport_cost_h2( ...
        components33, baseWeights);
    metricRowsNow = metric_property_records(state, components33, ...
        baselineDistance, config);
    metricRecords = [metricRecords; metricRowsNow]; %#ok<AGROW>
    componentRecords{end + 1, 1} = component_contribution_record( ...
        state, components33, baselineDetail); %#ok<SAGROW>

    solveCache = containers.Map('KeyType', 'char', 'ValueType', 'any');
    evalCache = containers.Map('KeyType', 'char', 'ValueType', 'any');

    ablationDefs = {
        'D_only', struct('D',0.6,'A',0,'C',0);
        'D_plus_A', struct('D',0.6,'A',0.25,'C',0);
        'D_plus_C', struct('D',0.6,'A',0,'C',0.15);
        'D_plus_A_plus_C', baseWeights};
    for vv = 1:size(ablationDefs, 1)
        label = string(ablationDefs{vv, 1});
        weights = ablationDefs{vv, 2};
        [dMat, distanceDetail] = compose_step03P_transport_cost_h2( ...
            components33, weights);
        for rho = rhoValues
            solveKey = solve_key(label, "D33", weights, rho);
            [sol, solveCache] = cached_solve(solveCache, solveKey, ...
                D, A, C, Cap, M, rho, dMat, uniformWeights, config);
            [allSolverPass, maxIndependentViolation] = update_solver_audit( ...
                allSolverPass, maxIndependentViolation, sol, config);
            if abs(rho) <= 1e-12
                rho0ReferenceT(char(state.complexity_label)) = sol.T;
            end
            for roleRow = 1:height(roleDefs)
                role = roleDefs.role(roleRow);
                field = role_field(role);
                [ev, evalCache] = cached_evaluation(evalCache, role, ...
                    roleData.(field), sol.T, M, config);
                allEvaluationPass = allEvaluationPass && evaluation_ok(ev);
                rec = result_record(state, label, "D33", rho, role, ...
                    weights, distanceDetail, sol, ev, roleData.(field), Cap, config);
                ablationRecords{end + 1, 1} = rec; %#ok<SAGROW>
                if label == "D_plus_A_plus_C"
                    fullCapacityRecords{end + 1, 1} = rec; %#ok<SAGROW>
                end
            end
        end
    end

    granularityDefs = {
        'D33_node', components33;
        'D4_service_region', componentsRegion;
        'D1_total', componentsTotal};
    for gg = 1:size(granularityDefs, 1)
        granularity = string(granularityDefs{gg, 1});
        componentsNow = granularityDefs{gg, 2};
        [dMat, distanceDetail] = compose_step03P_transport_cost_h2( ...
            componentsNow, baseWeights);
        for rho = rhoValues
            solveKey = solve_key("DAC", granularity, baseWeights, rho);
            [sol, solveCache] = cached_solve(solveCache, solveKey, ...
                D, A, C, Cap, M, rho, dMat, uniformWeights, config);
            [allSolverPass, maxIndependentViolation] = update_solver_audit( ...
                allSolverPass, maxIndependentViolation, sol, config);
            for roleRow = 1:height(roleDefs)
                role = roleDefs.role(roleRow);
                field = role_field(role);
                [ev, evalCache] = cached_evaluation(evalCache, role, ...
                    roleData.(field), sol.T, M, config);
                allEvaluationPass = allEvaluationPass && evaluation_ok(ev);
                granularityRecords{end + 1, 1} = result_record( ...
                    state, "D_plus_A_plus_C", granularity, rho, role, ...
                    baseWeights, distanceDetail, sol, ev, roleData.(field), Cap, config); %#ok<SAGROW>
            end
        end
    end

    weightDefs = {
        'D',0.5; 'D',1.0; 'D',1.5;
        'A',0.5; 'A',1.0; 'A',1.5;
        'C',0.5; 'C',1.0; 'C',1.5};
    for ww = 1:size(weightDefs, 1)
        component = string(weightDefs{ww, 1});
        multiplier = weightDefs{ww, 2};
        weights = baseWeights;
        weights.(char(component)) = multiplier .* weights.(char(component));
        [dMat, distanceDetail] = compose_step03P_transport_cost_h2( ...
            components33, weights);
        solveKey = solve_key("weight_" + component + "_" + string(multiplier), ...
            "D33", weights, 0.02);
        if abs(multiplier - 1) <= 1e-12
            solveKey = solve_key("D_plus_A_plus_C", "D33", baseWeights, 0.02);
        end
        [sol, solveCache] = cached_solve(solveCache, solveKey, ...
            D, A, C, Cap, M, 0.02, dMat, uniformWeights, config);
        [allSolverPass, maxIndependentViolation] = update_solver_audit( ...
            allSolverPass, maxIndependentViolation, sol, config);
        for roleRow = 1:height(roleDefs)
            role = roleDefs.role(roleRow);
            field = role_field(role);
            [ev, evalCache] = cached_evaluation(evalCache, role, ...
                roleData.(field), sol.T, M, config);
            allEvaluationPass = allEvaluationPass && evaluation_ok(ev);
            rec = result_record(state, "weight_sensitivity", "D33", 0.02, ...
                role, weights, distanceDetail, sol, ev, roleData.(field), Cap, config);
            rec.changed_component = component;
            rec.weight_multiplier = multiplier;
            weightRecords{end + 1, 1} = rec; %#ok<SAGROW>
        end
    end

    baselineKey = solve_key("D_plus_A_plus_C", "D33", baseWeights, 0.02);
    baselineSol = solveCache(baselineKey);
    capacityLabels = ["T_0pct";"T_50pct";"T_100pct";"T_optimal"];
    capacityValues = {zeros(4,1),0.5.*Cap,Cap,baselineSol.T};
    pairSample = deterministic_pair_sample(R, config.pairSampleCount, ...
        20260727 + state.initial_state_id);
    selectedPairData = struct();
    for tt = 1:numel(capacityLabels)
        label = capacityLabels(tt);
        Tnow = capacityValues{tt};
        [ev, evalCache] = cached_evaluation(evalCache, "nominal", ...
            roleData.nominal, Tnow, M, config);
        allEvaluationPass = allEvaluationPass && evaluation_ok(ev);
        consistencyRecords{end + 1, 1} = distance_loss_record( ...
            state, label, Tnow, pairSample, baselineDetail, ...
            baselineDistance, ev.loss); %#ok<SAGROW>
        if label == "T_optimal"
            selectedPairData = choose_representative_pairs( ...
                pairSample, baselineDistance, ev.loss);
        end
    end

    categories = ["near";"middle";"far";"small_distance_large_loss"];
    for cc = 1:numel(categories)
        category = categories(cc);
        pair = selectedPairData.(char(category));
        source = pair(1);
        destination = pair(2);
        baselineEval = evalCache(evaluation_key("nominal", baselineSol.T));
        if baselineEval.loss(destination) < baselineEval.loss(source)
            swap = source; source = destination; destination = swap;
        end
        shiftedWeights = uniformWeights;
        shiftedWeights(source) = shiftedWeights(source) - config.transferMass;
        shiftedWeights(destination) = shiftedWeights(destination) + config.transferMass;
        shiftedSol = solve_step03P_weighted_cg_h2( ...
            D, A, C, Cap, M, 0.02, baselineDistance, shiftedWeights, config);
        [allSolverPass, maxIndependentViolation] = update_solver_audit( ...
            allSolverPass, maxIndependentViolation, shiftedSol, config);
        decisionRecords{end + 1, 1} = decision_record(state, category, ...
            source, destination, config.transferMass, baselineDistance, ...
            baselineEval.loss, baselineSol, shiftedSol); %#ok<SAGROW>
    end

    clear roleData components33 componentsRegion componentsTotal baselineDistance;
    clear baselineDetail solveCache evalCache;
end

ablationTbl = records_to_table(ablationRecords);
granularityTbl = records_to_table(granularityRecords);
weightTbl = records_to_table(weightRecords);
fullCapacityTbl = records_to_table(fullCapacityRecords);
metricTbl = records_to_table(metricRecords);
componentTbl = records_to_table(componentRecords);
consistencyTbl = records_to_table(consistencyRecords);
decisionTbl = records_to_table(decisionRecords);

rho0Consistent = rho0_consistency(ablationTbl, granularityTbl);
inputHashesAfter = verify_role_hashes(roleDefs, inputDir);
protectedAfter = hash_files(protectedFiles);
protectedUnchanged = all(protectedAfter == protectedBefore);
oldRunsUnchanged = directory_hash(step03NDir) == step03NBefore && ...
    directory_hash(step03ODir) == step03OBefore;
step03JUnchanged = directory_hash(inputDir) == step03JBefore && inputHashesAfter;
fullCapacityExact = all(abs(fullCapacityTbl.capacity_upper_T1 - 300) <= 1e-12 & ...
    abs(fullCapacityTbl.capacity_upper_T2 - 200) <= 1e-12 & ...
    abs(fullCapacityTbl.capacity_upper_T3 - 100) <= 1e-12 & ...
    abs(fullCapacityTbl.capacity_upper_T4 - 150) <= 1e-12);
metricMechanical = all(metricTbl.nonnegative_pass) && ...
    all(metricTbl.zero_diagonal_pass) && all(metricTbl.symmetry_pass);
noInvalidNumbers = table_finite_core(ablationTbl) && ...
    table_finite_core(granularityTbl) && table_finite_core(weightTbl) && ...
    table_finite_core(fullCapacityTbl);

totalMetricRows = metricTbl(metricTbl.cost_component == "DAC_total", :);
strictTrianglePass = all(totalMetricRows.triangle_violation_count == 0);
identityPass = all(totalMetricRows.identity_violation_count == 0);
zeroDistanceLossCounterexample = any(consistencyTbl.zero_distance_positive_loss_count > 0);
AIndependent = sum(componentTbl.A_positive_C_zero_pair_count) > 0 && ...
    ablation_component_effect(ablationTbl, "A");
CIndependent = sum(componentTbl.C_positive_A_zero_pair_count) > 0 && ...
    ablation_component_effect(ablationTbl, "C");
reweightingDominance = weight_reweighting_dominance(weightTbl);
CmaskTriangleViolation = any(metricTbl.cost_component == "C_masked_component" & ...
    metricTbl.triangle_violation_count > 0);

if zeroDistanceLossCounterexample || ~identityPass || ~AIndependent || ~CIndependent
    decision = "D. DAC_REPRESENTATION_REQUIRES_REVISION";
elseif reweightingDominance
    decision = "C. DAC_REWEIGHTING_REQUIRED";
elseif CmaskTriangleViolation || ~strictTrianglePass
    decision = "B. DAC_VALID_AS_KANTOROVICH_COST_NOT_STRICT_METRIC";
else
    decision = "A. DAC_VALID_FOR_CURRENT_TERMINALLOH";
end

auditRows = {
    'BASE-01', pass_fail(lower(strtrim(string(headText))) == expectedHead), strtrim(string(headText)), expectedHead;
    'DATA-01', pass_fail(step03JUnchanged), step03JUnchanged, 'all Step-03J hashes unchanged';
    'CORE-01', pass_fail(protectedUnchanged), protectedUnchanged, 'formal WDRO/MSP files unchanged';
    'OLD-01', pass_fail(oldRunsUnchanged), oldRunsUnchanged, 'Step-03N and Step-03O unchanged';
    'CAP-01', pass_fail(fullCapacityExact), mat2str(Cap.'), '[300 200 100 150]';
    'SOLVE-01', pass_fail(allSolverPass), allSolverPass, 'all audit CG solves OPTIMAL';
    'SOLVE-02', pass_fail(maxIndependentViolation <= config.violationTolerance), maxIndependentViolation, '<=1e-8';
    'EVAL-01', pass_fail(allEvaluationPass), allEvaluationPass, 'all fixed-T evaluations OPTIMAL';
    'RHO0-01', pass_fail(rho0Consistent), rho0Consistent, 'rho=0 independent of transport geometry';
    'METRIC-01', pass_fail(metricMechanical), metricMechanical, 'nonnegative, zero diagonal, symmetric';
    'DOMAIN-01', pass_fail(noInvalidNumbers), noInvalidNumbers, 'finite reported optimization results';
    'SCOPE-01', 'PASS', '3 states and R=2000', 'no R=5000/R=15000/all-35-state run';
    'MSP-01', 'PASS', 'not run', 'MSP and vehicle scheduling not run'};
acceptanceTbl = cell2table(auditRows, 'VariableNames', ...
    {'check_id','status','observed','expected'});
failCount = sum(strcmp(acceptanceTbl.status, 'FAIL'));
if failCount > 0
    error('Step-03P audit has %d mechanical failures; no output or Git write.', failCount);
end

mkdir(outputDir);
writetable(metricTbl, fullfile(outputDir, 'step03P_metric_property_tests.csv'));
writetable(ablationTbl, fullfile(outputDir, 'step03P_ablation_results.csv'));
writetable(granularityTbl, fullfile(outputDir, 'step03P_D_granularity_results.csv'));
writetable(componentTbl, fullfile(outputDir, 'step03P_component_contribution.csv'));
writetable(consistencyTbl, fullfile(outputDir, 'step03P_distance_loss_consistency.csv'));
writetable(decisionTbl, fullfile(outputDir, 'step03P_distance_decision_consistency.csv'));
writetable(weightTbl, fullfile(outputDir, 'step03P_weight_sensitivity.csv'));
writetable(fullCapacityTbl, fullfile(outputDir, 'step03P_full_capacity_results.csv'));
writetable(acceptanceTbl, fullfile(outputDir, 'step03P_acceptance_tests.csv'));
write_model_scope_audit(fullfile(outputDir, 'step03P_model_scope_audit.md'), ...
    Cap, M, penaltySource);
write_formula_audit(fullfile(outputDir, 'step03P_dac_formula_audit.md'), ...
    baseWeights, regionMap);
write_summary(fullfile(outputDir, 'step03P_summary.txt'), decision, ...
    metricTbl, componentTbl, consistencyTbl, decisionTbl, weightTbl, ...
    ablationTbl, granularityTbl, fullCapacityTbl, maxIndependentViolation, ...
    failCount, config);
write_manifest(fullfile(outputDir, 'run_manifest.txt'), expectedHead, ...
    roleDefs, Cap, config, decision);

fprintf('\nStep-03P completed: decision=%s PASS=%d FAIL=%d\n', ...
    decision, height(acceptanceTbl), failCount);
fprintf('Maximum independent violation: %.12g\n', maxIndependentViolation);
fprintf('Strict triangle property: %d; identity: %d\n', ...
    strictTrianglePass, identityPass);

function field = role_field(role)
field = char(replace(string(role), '-', '_'));
end

function data = load_frozen_mat_state(matPath, stateId, R)
rows = (stateId - 1) * 15000 + (1:R);
m = matfile(matPath);
data = struct();
data.D = double(m.D_node_kg(rows, :));
data.A = double(m.A_site_node(rows, :, :));
data.C = double(m.C_site_node_km(rows, :, :));
data.path_id = double(m.path_id(rows, 1));
actualState = double(m.initial_state_id(rows, 1));
if any(actualState ~= stateId) || size(data.D, 2) ~= 33 || ...
        ~isequal(size(data.A), [R,4,33]) || ~isequal(size(data.A), size(data.C))
    error('Step-03P frozen MAT state layout mismatch.');
end
if any(data.D < 0, 'all') || any(~isfinite(data.D), 'all') || ...
        any(~ismember(unique(data.A), [0;1])) || any(~isfinite(data.C(data.A > 0.5)))
    error('Step-03P frozen D/A/C domain audit failed.');
end
end

function regionMap = build_static_service_regions(rootDir)
edges = readtable(fullfile(rootDir, 'data', 'yuanqi', 'stage1_road_edges.csv'));
sites = sortrows(readtable(fullfile(rootDir, 'data', 'yuanqi', ...
    'stage1_site_nodes.csv')), 'site_id');
G = graph(double(edges.from_node), double(edges.to_node), double(edges.length_km));
baseDistance = distances(G, double(sites.grid_node), 1:33);
[~, regionMap] = min(baseDistance, [], 1);
regionMap = regionMap(:).';
if numel(regionMap) ~= 33 || any(~ismember(regionMap, 1:4))
    error('Step-03P service-region construction failed.');
end
end

function key = solve_key(label, granularity, weights, rho)
if abs(rho) <= 1e-12
    key = 'rho0_common';
else
    key = sprintf('%s|%s|%.17g|%.17g|%.17g|rho=%.17g', ...
        char(label), char(granularity), weights.D, weights.A, weights.C, rho);
end
end

function [sol, cache] = cached_solve(cache, key, D, A, C, Cap, M, rho, dMat, p, config)
key = char(key);
if isKey(cache, key)
    sol = cache(key);
    return;
end
fprintf('  solve %s\n', key);
sol = solve_step03P_weighted_cg_h2(D, A, C, Cap, M, rho, dMat, p, config);
cache(key) = sol;
end

function key = evaluation_key(role, T)
key = char(string(role) + "|" + join(compose('%.17g', double(T(:).')), ','));
end

function [ev, cache] = cached_evaluation(cache, role, data, T, M, config)
key = evaluation_key(role, T);
if isKey(cache, key)
    ev = cache(key);
    return;
end
ev = evaluate_step03P_fixed_T_losses_h2(data.D, data.A, data.C, T, M, config);
cache(key) = ev;
end

function [passNow, maxViolation] = update_solver_audit(passNow, maxViolation, sol, config)
passNow = passNow && sol.exitflag == 1 && sol.converged && ...
    all(isfinite(sol.T)) && all(sol.T >= -1e-8) && ...
    sol.final_independent_scan_max_violation <= config.violationTolerance;
if isfinite(sol.final_independent_scan_max_violation)
    maxViolation = max(maxViolation, sol.final_independent_scan_max_violation);
end
end

function ok = evaluation_ok(ev)
ok = ev.exitflag == 1 && all(isfinite(ev.loss)) && all(ev.loss >= -1e-8) && ...
    all(isfinite(ev.shortage_kg)) && all(ev.shortage_kg >= -1e-8) && ...
    ev.max_demand_balance_error <= 1e-7 && ...
    ev.max_site_capacity_violation <= 1e-7;
end

function rec = result_record(state, variant, granularity, rho, role, weights, ...
        distanceDetail, sol, ev, roleData, Cap, config)
R = numel(ev.loss);
Aflat = reshape(roleData.A, R, []);
anyUnreachable = any(Aflat <= 0.5, 2);
fullyReachable = ~anyUnreachable;
rec = struct();
rec.complexity_label = state.complexity_label;
rec.initial_state_id = state.initial_state_id;
rec.a0 = state.a0;
rec.loc0 = state.loc0;
rec.lfw0 = state.lfw0;
rec.R = R;
rec.distance_variant = string(variant);
rec.D_granularity = string(granularity);
rec.rho = rho;
rec.dataset_role = string(role);
rec.weight_D = weights.D;
rec.weight_A = weights.A;
rec.weight_C = weights.C;
rec.distance_median_before_rescale = distanceDetail.median_before_rescale;
rec.T1 = sol.T(1); rec.T2 = sol.T(2); rec.T3 = sol.T(3); rec.T4 = sol.T(4);
rec.T_total = sum(sol.T);
rec.capacity_upper_T1 = Cap(1); rec.capacity_upper_T2 = Cap(2);
rec.capacity_upper_T3 = Cap(3); rec.capacity_upper_T4 = Cap(4);
rec.upper_bound_count = sum(abs(sol.T - Cap) <= 1e-7);
rec.wdro_objective = sol.objective_value;
rec.terminal_cost = sol.terminal_cost;
rec.lambda_rho_cost = sol.lambda_rho_cost;
rec.alpha_weighted_cost = sol.alpha_weighted_cost;
rec.robust_dual_loss = sol.robust_dual_loss;
rec.lambda = sol.lambda;
rec.active_constraint_count = sol.final_active_constraints;
rec.max_independent_violation = sol.final_independent_scan_max_violation;
rec.loss_mean = mean(ev.loss);
rec.loss_q95 = pct(ev.loss, 95);
rec.loss_q99 = pct(ev.loss, 99);
rec.loss_max = max(ev.loss);
rec.service_cost_mean = mean(ev.service_cost);
rec.shortage_kg_mean = mean(ev.shortage_kg);
rec.shortage_penalty_mean = mean(ev.shortage_penalty);
rec.any_unreachable_scenario_share = mean(anyUnreachable);
rec.loss_any_unreachable_mean = conditional_mean(ev.loss, anyUnreachable);
rec.loss_fully_reachable_mean = conditional_mean(ev.loss, fullyReachable);
rec.validation_total_cost = config.gamma * sum(sol.T) + mean(ev.loss);
rec.solve_status = sol.status;
rec.evaluation_status = ev.status;
end

function value = conditional_mean(x, mask)
if any(mask)
    value = mean(x(mask));
else
    value = NaN;
end
end

function rows = metric_property_records(state, components, totalDistance, config)
names = ["D_component";"A_component";"C_masked_component";"DAC_total"];
mats = {components.normD, components.normA, components.normC, totalDistance};
rows = cell(numel(names), 1);
R = size(totalDistance, 1);
[ti,tj,tk] = deterministic_triples(R, config.triangleSampleCount, ...
    20261727 + state.initial_state_id);
for ii = 1:numel(names)
    d = mats{ii};
    lhs = d(sub2ind([R,R], ti, tk));
    rhs = d(sub2ind([R,R], ti, tj)) + d(sub2ind([R,R], tj, tk));
    violation = lhs - rhs;
    [maxViolation, pos] = max(violation);
    upper = triu(true(R), 1);
    if names(ii) == "DAC_total"
        effectiveDifference = components.rawD > 1e-12 | ...
            components.rawA > 1e-12 | components.rawC > 1e-12;
        identityViolation = upper & effectiveDifference & d <= 1e-12;
    else
        identityViolation = upper & false(R, R);
    end
    rows{ii} = struct( ...
        'complexity_label', state.complexity_label, ...
        'initial_state_id', state.initial_state_id, ...
        'cost_component', names(ii), ...
        'nonnegative_pass', min(d, [], 'all') >= -1e-12, ...
        'min_cost', min(d, [], 'all'), ...
        'zero_diagonal_pass', max(abs(diag(d))) <= 1e-12, ...
        'max_diagonal_abs', max(abs(diag(d))), ...
        'symmetry_pass', max(abs(d-d.'), [], 'all') <= 1e-12, ...
        'max_symmetry_abs', max(abs(d-d.'), [], 'all'), ...
        'identity_violation_count', nnz(identityViolation), ...
        'triangle_test_count', numel(ti), ...
        'triangle_violation_count', sum(violation > 1e-10), ...
        'triangle_max_violation', maxViolation, ...
        'triangle_example_i', ti(pos), ...
        'triangle_example_j', tj(pos), ...
        'triangle_example_k', tk(pos));
end
end

function rec = component_contribution_record(state, components, detail)
R = components.R;
upper = triu(true(R), 1);
dD = components.rawD(upper);
dA = components.rawA(upper);
dC = components.rawC(upper);
wD = detail.weightedD(upper);
wA = detail.weightedA(upper);
wC = detail.weightedC(upper);
total = wD + wA + wC;
positive = total > 1e-12;
rec = struct();
rec.complexity_label = state.complexity_label;
rec.initial_state_id = state.initial_state_id;
rec.pair_count = numel(total);
rec.D_scale_max_L1 = components.scaleD;
rec.A_scale_max_L1 = components.scaleA;
rec.C_scale_max_masked_L1 = components.scaleC;
rec.mean_D_contribution_share = mean(safe_share(wD(positive), total(positive)));
rec.mean_A_contribution_share = mean(safe_share(wA(positive), total(positive)));
rec.mean_C_contribution_share = mean(safe_share(wC(positive), total(positive)));
rec.D_only_signal_pair_count = sum(dD > 1e-12 & dA <= 1e-12 & dC <= 1e-12);
rec.A_only_signal_pair_count = sum(dA > 1e-12 & dD <= 1e-12 & dC <= 1e-12);
rec.C_only_signal_pair_count = sum(dC > 1e-12 & dD <= 1e-12 & dA <= 1e-12);
rec.A_positive_C_zero_pair_count = sum(dA > 1e-12 & dC <= 1e-12);
rec.C_positive_A_zero_pair_count = sum(dC > 1e-12 & dA <= 1e-12);
rec.A_and_C_positive_pair_count = sum(dA > 1e-12 & dC > 1e-12);
rec.A_C_spearman = spearman_corr(dA, dC);
end

function share = safe_share(x, total)
share = zeros(size(x));
mask = total > 0;
share(mask) = x(mask) ./ total(mask);
end

function pairSample = deterministic_pair_sample(R, count, seed)
[iAll, jAll] = find(triu(true(R), 1));
rng(seed, 'twister');
take = randperm(numel(iAll), min(count, numel(iAll)));
pairSample = struct('i', iAll(take), 'j', jAll(take), 'seed', seed);
end

function rec = distance_loss_record(state, label, T, pairs, detail, dTotal, loss)
R = size(dTotal, 1);
idx = sub2ind([R,R], pairs.i, pairs.j);
d = dTotal(idx);
dD = detail.weightedD(idx);
dA = detail.weightedA(idx);
dC = detail.weightedC(idx);
lossDiff = abs(loss(pairs.i) - loss(pairs.j));
smallCut = pct(d, 5);
largeLossCut = pct(lossDiff, 95);
anomaly = d <= smallCut & lossDiff > max(largeLossCut, 1e-8);
zeroDistance = d <= 1e-12 & lossDiff > 1e-8;
dominant = "NONE";
if any(anomaly)
    means = [mean(dD(anomaly)),mean(dA(anomaly)),mean(dC(anomaly))];
    labels = ["D";"A";"C"];
    [~, pos] = max(means);
    dominant = labels(pos);
end
rec = struct( ...
    'complexity_label', state.complexity_label, ...
    'initial_state_id', state.initial_state_id, ...
    'capacity_case', label, ...
    'T1', T(1), 'T2', T(2), 'T3', T(3), 'T4', T(4), ...
    'pair_sample_count', numel(d), ...
    'pair_sample_seed', pairs.seed, ...
    'spearman_total_distance_loss_difference', spearman_corr(d, lossDiff), ...
    'spearman_D_component_loss_difference', spearman_corr(dD, lossDiff), ...
    'spearman_A_component_loss_difference', spearman_corr(dA, lossDiff), ...
    'spearman_C_component_loss_difference', spearman_corr(dC, lossDiff), ...
    'small_distance_q05', smallCut, ...
    'large_loss_difference_q95', largeLossCut, ...
    'small_distance_large_loss_count', sum(anomaly), ...
    'small_distance_large_loss_share', mean(anomaly), ...
    'anomaly_dominant_component', dominant, ...
    'zero_distance_positive_loss_count', sum(zeroDistance), ...
    'loss_difference_mean', mean(lossDiff), ...
    'loss_difference_q95', pct(lossDiff,95), ...
    'loss_difference_max', max(lossDiff));
end

function selected = choose_representative_pairs(pairs, dMat, loss)
R = size(dMat, 1);
idx = sub2ind([R,R], pairs.i, pairs.j);
d = dMat(idx);
lossDiff = abs(loss(pairs.i) - loss(pairs.j));
positive = find(d > 1e-12);
[~, nearPos] = min(d(positive));
nearIdx = positive(nearPos);
medianD = median(d(positive));
[~, middleIdx] = min(abs(d - medianD));
[~, farIdx] = max(d);
smallCut = pct(d,5);
largeCut = pct(lossDiff,95);
candidate = find(d <= smallCut & lossDiff > max(largeCut, 1e-8));
if isempty(candidate)
    score = lossDiff ./ max(d, 1e-12);
    [~, anomalyIdx] = max(score);
else
    score = lossDiff(candidate) ./ max(d(candidate), 1e-12);
    [~, local] = max(score);
    anomalyIdx = candidate(local);
end
indices = [nearIdx,middleIdx,farIdx,anomalyIdx];
labels = ["near";"middle";"far";"small_distance_large_loss"];
selected = struct();
for ii = 1:numel(labels)
    selected.(char(labels(ii))) = [pairs.i(indices(ii)),pairs.j(indices(ii))];
end
end

function rec = decision_record(state, category, source, destination, delta, dMat, loss, base, shifted)
pairSlack = shifted.L(destination) - shifted.lambda * dMat(source,destination) - ...
    shifted.alpha(source);
rec = struct( ...
    'complexity_label', state.complexity_label, ...
    'initial_state_id', state.initial_state_id, ...
    'pair_category', category, ...
    'source_scenario_index', source, ...
    'destination_scenario_index', destination, ...
    'transport_cost', dMat(source,destination), ...
    'baseline_loss_source', loss(source), ...
    'baseline_loss_destination', loss(destination), ...
    'absolute_loss_difference', abs(loss(destination)-loss(source)), ...
    'probability_mass_transferred', delta, ...
    'baseline_T1', base.T(1), 'baseline_T2', base.T(2), ...
    'baseline_T3', base.T(3), 'baseline_T4', base.T(4), ...
    'shifted_T1', shifted.T(1), 'shifted_T2', shifted.T(2), ...
    'shifted_T3', shifted.T(3), 'shifted_T4', shifted.T(4), ...
    'TerminalLOH_max_abs_change', max(abs(shifted.T-base.T)), ...
    'TerminalLOH_total_change', sum(shifted.T)-sum(base.T), ...
    'baseline_objective', base.objective_value, ...
    'shifted_objective', shifted.objective_value, ...
    'objective_change', shifted.objective_value-base.objective_value, ...
    'baseline_worst_loss', max(base.L), ...
    'shifted_worst_loss', max(shifted.L), ...
    'worst_loss_change', max(shifted.L)-max(base.L), ...
    'source_to_destination_active_constraint', logical(shifted.activeMask(source,destination)), ...
    'source_to_destination_constraint_slack', pairSlack, ...
    'max_independent_violation', shifted.final_independent_scan_max_violation);
end

function [i,j,k] = deterministic_triples(R, count, seed)
rng(seed, 'twister');
i = randi(R, count, 1);
j = randi(R, count, 1);
k = randi(R, count, 1);
mask = i == j;
while any(mask), j(mask) = randi(R, sum(mask), 1); mask = i == j; end
mask = k == i | k == j;
while any(mask), k(mask) = randi(R, sum(mask), 1); mask = k == i | k == j; end
end

function value = spearman_corr(x, y)
x = double(x(:)); y = double(y(:));
mask = isfinite(x) & isfinite(y);
x = x(mask); y = y(mask);
if numel(x) < 2 || all(x == x(1)) || all(y == y(1))
    value = NaN;
    return;
end
rx = average_rank(x);
ry = average_rank(y);
rx = rx - mean(rx); ry = ry - mean(ry);
value = sum(rx .* ry) / sqrt(sum(rx.^2) * sum(ry.^2));
end

function ranks = average_rank(x)
[sorted, order] = sort(x);
ranksSorted = zeros(size(sorted));
start = 1;
while start <= numel(sorted)
    stop = start;
    while stop < numel(sorted) && sorted(stop + 1) == sorted(start)
        stop = stop + 1;
    end
    ranksSorted(start:stop) = 0.5 * (start + stop);
    start = stop + 1;
end
ranks = zeros(size(x));
ranks(order) = ranksSorted;
end

function value = pct(x, p)
x = sort(double(x(isfinite(x))));
if isempty(x), value = NaN; return; end
position = 1 + (numel(x)-1) * p / 100;
lo = floor(position); hi = ceil(position);
if lo == hi
    value = x(lo);
else
    value = x(lo) + (position-lo) * (x(hi)-x(lo));
end
end

function tbl = records_to_table(records)
if isempty(records)
    tbl = table();
else
    tbl = struct2table(vertcat(records{:}));
end
end

function ok = rho0_consistency(ablationTbl, granularityTbl)
rows = [ablationTbl(abs(ablationTbl.rho)<=1e-12 & ...
    ablationTbl.dataset_role=="nominal", :); ...
    granularityTbl(abs(granularityTbl.rho)<=1e-12 & ...
    granularityTbl.dataset_role=="nominal", :)];
ok = true;
for stateId = unique(rows.initial_state_id).'
    block = rows(rows.initial_state_id==stateId,:);
    T = [block.T1,block.T2,block.T3,block.T4];
    ok = ok && max(abs(T-T(1,:)), [], 'all') <= 1e-7;
end
end

function ok = table_finite_core(tbl)
names = {'T1','T2','T3','T4','wdro_objective','loss_mean','loss_q95','loss_q99'};
ok = true;
for ii = 1:numel(names)
    ok = ok && all(isfinite(tbl.(names{ii})));
end
end

function dominated = weight_reweighting_dominance(tbl)
validation = tbl(tbl.dataset_role ~= "nominal", :);
baseline = validation(validation.weight_multiplier == 1, :);
baseline = baseline(baseline.changed_component == "D", :);
dominated = false;
components = ["D","A","C"];
multipliers = [0.5,1.5];
for component = components
    for multiplier = multipliers
        candidate = validation(validation.changed_component == component & ...
            abs(validation.weight_multiplier-multiplier)<=1e-12, :);
        if height(candidate) ~= height(baseline)
            continue;
        end
        candidate = sortrows(candidate, {'initial_state_id','dataset_role'});
        reference = sortrows(baseline, {'initial_state_id','dataset_role'});
        weak = candidate.validation_total_cost <= reference.validation_total_cost + 1e-8 & ...
            candidate.loss_q95 <= reference.loss_q95 + 1e-8;
        strict = candidate.validation_total_cost < reference.validation_total_cost - 1e-6 | ...
            candidate.loss_q95 < reference.loss_q95 - 1e-6;
        if all(weak) && any(strict)
            dominated = true;
            return;
        end
    end
end
end

function present = ablation_component_effect(tbl, component)
nominal = tbl(tbl.dataset_role == "nominal" & abs(tbl.rho-0.02)<=1e-12, :);
present = false;
for stateId = unique(nominal.initial_state_id).'
    block = nominal(nominal.initial_state_id==stateId,:);
    if component == "A"
        without = block(block.distance_variant=="D_plus_C",:);
    else
        without = block(block.distance_variant=="D_plus_A",:);
    end
    full = block(block.distance_variant=="D_plus_A_plus_C",:);
    if height(without)==1 && height(full)==1
        change = max(abs([without.T1-full.T1,without.T2-full.T2, ...
            without.T3-full.T3,without.T4-full.T4]));
        if change > 1e-7
            present = true;
            return;
        end
    end
end
end

function ok = verify_role_hashes(roleDefs, inputDir)
ok = true;
for rr = 1:height(roleDefs)
    ok = ok && sha256_file(fullfile(inputDir, roleDefs.csv_name(rr))) == ...
        roleDefs.csv_sha256(rr) && ...
        sha256_file(fullfile(inputDir, roleDefs.mat_name(rr))) == ...
        roleDefs.mat_sha256(rr);
end
end

function hashes = hash_files(files)
hashes = strings(numel(files),1);
for ii=1:numel(files), hashes(ii)=sha256_file(files(ii)); end
end

function value = directory_hash(path)
files = dir(fullfile(path, '**', '*'));
files = files(~[files.isdir]);
relative = strings(numel(files),1);
for ii=1:numel(files)
    relative(ii) = erase(string(fullfile(files(ii).folder,files(ii).name)), ...
        string(path)+filesep);
end
[relative, order] = sort(relative);
payload = strings(numel(files),1);
for ii=1:numel(order)
    filePath = fullfile(path, relative(ii));
    payload(ii) = relative(ii) + "|" + sha256_file(filePath);
end
value = sha256_text(join(payload,newline));
end

function value = sha256_file(path)
fid = fopen(path, 'rb');
if fid < 0, error('Cannot open file for SHA-256: %s', path); end
cleaner = onCleanup(@() fclose(fid));
md = java.security.MessageDigest.getInstance('SHA-256');
while true
    bytes = fread(fid, 1024*1024, '*uint8');
    if isempty(bytes), break; end
    md.update(bytes);
end
value = lower(string(reshape(dec2hex(typecast(md.digest(),'uint8'),2).',1,[])));
clear cleaner;
end

function value = sha256_text(textValue)
md = java.security.MessageDigest.getInstance('SHA-256');
md.update(unicode2native(char(textValue),'UTF-8'));
value = lower(string(reshape(dec2hex(typecast(md.digest(),'uint8'),2).',1,[])));
end

function value = pass_fail(condition)
if condition, value='PASS'; else, value='FAIL'; end
end

function write_model_scope_audit(path, Cap, M, penaltySource)
lines = [
"# Step-03P Model Scope Audit"
""
"## Frozen scenario representation"
""
"`load_frozen_b3_wdro_dataset_h2.m:28-30,45-50` restores each post-disaster atom as complete node demand `D(Rx33)`, binary reachability `A(Rx4x33)`, and conditional service distance `C(Rx4x33)`. Path, wind, resistance seed, line-failure count, and road-closure count remain metadata and are not solver arguments."
""
"`D` is the three-hour node hydrogen requirement produced upstream from grid load loss. `A=1` means that a site can serve a node over every demand-critical window used by the W1-W3 aggregation. `C` is the mean current-road-state shortest-path distance over those critical reachable windows; when `A=0`, `C=Inf` is a sentinel and is masked out."
""
"## Loss and decision scope"
""
"The formal solver signature `solve_wdro_terminal_loh_lp_h2(D,A,C,Cap,M,rho,dMat,config)` contains no other sample-varying consequence argument. Lines 64-69 use `A` and `D` to set service-arc bounds. Lines 90-101 impose `sum_i y^s_{i,n}+u^s_n=D^s_n`. Lines 103-113 impose `sum_n y^s_{i,n}<=T_i`. Lines 115-131 define scenario loss from reachable `C*y` plus shortage penalty `M*u`."
""
"Thus, after the upstream grid-road consequence chain has produced D/A/C, TerminalLOH depends on samples only through D/A/C. Wind, failed-line counts, road-closure counts, path states, and random seeds can change D/A/C upstream but have no additional direct path into the WDRO LP. Fixed model parameters such as M, gamma, rho, and capacity bounds are not sample-varying omitted state."
""
"TerminalLOH is not a result for one atom. For one initial state, all R atoms jointly determine four common T variables through the optimal-transport DRO dual. MSP later uses state-level TerminalLOH for pre-landfall placement; this audit does not run MSP."
""
"This study intentionally excludes site damage, vehicle count, vehicle capacity, repeated trips, and post-disaster vehicle routing."
""
"## Capacity used in this audit"
""
sprintf("Step-03P uses the complete physical upper bound `Cap=[%s] kg`; no 0.8 reduction is applied. Step-03O remains an unchanged historical audit.",strtrim(sprintf('%.12g ',Cap)))
sprintf("Shortage penalty M=%.12g from `%s`.",M,penaltySource)];
write_lines(path, lines);
end

function write_formula_audit(path, weights, regionMap)
lines = [
"# Step-03P D/A/C Formula and Literature Audit"
""
"## Current transport cost"
""
"For atoms r and s, the accepted code computes:"
""
"- `Delta_D(r,s)=sum_n |D_rn-D_sn|`."
"- `Delta_A(r,s)=sum_i sum_n |A_rin-A_sin|`."
"- `Delta_C(r,s)=sum_i sum_n 1(A_rin=1 and A_sin=1)|C_rin-C_sin|`."
"- Each component is divided by its maximum pairwise value plus epsDistance when the maximum exceeds scaleTolerance."
sprintf("- The accepted DAC weights are D/A/C=%.6g/%.6g/%.6g.",weights.D,weights.A,weights.C)
"- The formal code does not median-rescale the completed cost. Step-03P additionally divides every experimental variant by its own nonzero pairwise median so all ablations use the same median cost scale and rho=0.02 is comparable."
""
"A is not duplicated by C. A records loss of service feasibility. C only compares difficulty where both atoms remain reachable. An A mismatch therefore cannot be converted into an ordinary large finite distance, and an unreachable arc cannot carry y in the loss LP."
""
"## Scenario service loss"
""
"For scenario s, the recourse loss is `ell_s(T)=min sum_i,n C_sin*y_sin + M*sum_n u_sn`, subject to demand balance, `sum_n y_sin<=T_i`, and `0<=y_sin<=A_sin*D_sn`. D sets demand and arc bounds; A decides whether service is possible; C ranks the cost of reachable service; u is unmet hydrogen."
""
"## D granularity"
""
"The four-region audit assigns each IEEE-33 node to the site with the shortest undamaged road-network distance, breaking ties by the lower site id. The resulting node-to-region map is:"
join("`node "+string(1:33)+" -> site "+string(regionMap)+"`",", ")
""
"## Mathematical terminology"
""
"D and A L1 components are metrics on their represented arrays. The C mask depends on the compared pair and can violate triangle inequality. Even if D and A happen to offset sampled C violations in a finite weighted matrix, the transport-cost function is not guaranteed to be a metric on the full D/A/C scenario space. Therefore a demonstrated masked-C violation requires the term optimal-transport DRO with a custom Kantorovich transport cost, not a strict Wasserstein metric."
""
"## Literature positioning"
""
"- Blanchet, Kang, Murthy, and Zhang (2019), `Data-Driven Optimal Transport Cost Selection for Distributionally Robust Optimization`, WSC, DOI 10.1109/WSC40007.2019.9004785: transport cost should be validated against data and the downstream task. Step-03P applies this by checking D/A/C weights against loss and TerminalLOH effects."
"- Bertsimas and Mundru (2023), `Optimization-Based Scenario Reduction for Data-Driven Two-Stage Stochastic Optimization`, Operations Research 71(4), DOI 10.1287/opre.2022.2265: scenario differences should preserve optimization-relevant cost and decision effects. Step-03P borrows the diagnostic principle but performs no scenario reduction."
"- Zhang, Yang, and Gao, `A Short and General Duality Proof for Wasserstein Distributionally Robust Optimization`, Operations Research, DOI 10.1287/opre.2023.0135: the duality applies under general transport-cost conditions. Step-03P uses this distinction to separate a general Kantorovich cost from a strict metric claim."];
write_lines(path, lines);
end

function write_summary(path, decision, metricTbl, componentTbl, consistencyTbl, ...
        decisionTbl, weightTbl, ablationTbl, granularityTbl, fullTbl, maxViolation, failCount, config)
totalMetric = metricTbl(metricTbl.cost_component=="DAC_total",:);
valAblation = ablationTbl(ablationTbl.rho==0.02 & ablationTbl.dataset_role~="nominal",:);
valGran = granularityTbl(granularityTbl.rho==0.02 & granularityTbl.dataset_role~="nominal",:);
weightNominal = weightTbl(weightTbl.dataset_role=="nominal",:);
baselineWeight = weightNominal(weightNominal.weight_multiplier==1,:);
maxWeightTChange = 0;
for stateId=unique(weightNominal.initial_state_id).'
    base=baselineWeight(baselineWeight.initial_state_id==stateId,:);
    if isempty(base),continue;end
    rows=weightNominal(weightNominal.initial_state_id==stateId,:);
    change=max(abs([rows.T1-base.T1(1),rows.T2-base.T2(1), ...
        rows.T3-base.T3(1),rows.T4-base.T4(1)]),[],'all');
    maxWeightTChange=max(maxWeightTChange,change);
end
lines = [
"Step-03P D/A/C transport-cost audit"
"PASS="+string(13-failCount)
"FAIL="+string(failCount)
"decision="+decision
"capacity_upper_kg=300,200,100,150"
"R=2000"
"states=7,18,30"
"rho=0,0.02"
"max_independent_constraint_violation="+string(sprintf('%.16g',maxViolation))
"DAC_triangle_violation_count="+string(sum(totalMetric.triangle_violation_count))
"DAC_triangle_max_violation="+string(sprintf('%.16g',max(totalMetric.triangle_max_violation)))
"C_masked_triangle_violation_count="+string(sum(metricTbl.triangle_violation_count(metricTbl.cost_component=="C_masked_component")))
"C_masked_triangle_max_violation="+string(sprintf('%.16g',max(metricTbl.triangle_max_violation(metricTbl.cost_component=="C_masked_component"))))
"DAC_identity_violation_count="+string(sum(totalMetric.identity_violation_count))
"A_independent_from_C_pairs_min_by_state="+string(min(componentTbl.A_positive_C_zero_pair_count))
"C_independent_from_A_pairs_min_by_state="+string(min(componentTbl.C_positive_A_zero_pair_count))
"distance_loss_spearman_range="+range_text(consistencyTbl.spearman_total_distance_loss_difference)
"small_distance_large_loss_share_range="+range_text(consistencyTbl.small_distance_large_loss_share)
"decision_T_change_by_category="+category_text(decisionTbl)
"weight_sensitivity_max_T_change_kg="+string(sprintf('%.16g',maxWeightTChange))
"tested_reweighting_uniformly_dominates_baseline="+string(weight_reweighting_dominance(weightTbl))
"ablation_validation_total_cost_range="+range_text(valAblation.validation_total_cost)
"D_granularity_validation_total_cost_range="+range_text(valGran.validation_total_cost)
"full_capacity_upper_bound_count_range="+range_text(fullTbl.upper_bound_count)
"pair_sample_count_per_state="+string(config.pairSampleCount)
"triangle_sample_count_per_state_and_component="+string(config.triangleSampleCount)
"formal_WDRO_core_modified=false"
"Step03J_modified=false"
"Step03O_modified=false"
"MSP_run=false"
"vehicle_model_added=false"
"R5000_run=false"
"R15000_run=false"];
write_lines(path, lines);
end

function text = range_text(x)
x=double(x(isfinite(x)));
if isempty(x),text="NaN";else,text=string(sprintf('%.12g..%.12g',min(x),max(x)));end
end

function text = category_text(tbl)
parts=strings(0,1);
for category=unique(tbl.pair_category).'
    rows=tbl(tbl.pair_category==category,:);
    parts(end+1)=category+":"+range_text(rows.TerminalLOH_max_abs_change); %#ok<AGROW>
end
text=join(parts,";");
end

function write_manifest(path, expectedHead, roleDefs, Cap, config, decision)
lines=[
"task=Step-03P D/A/C transport-cost audit"
"baseline_commit="+expectedHead
"R=2000"
"states=7,18,30"
"capacity_upper="+join(string(Cap.'),",")
"rho=0,0.02"
"pair_sample_count="+string(config.pairSampleCount)
"triangle_sample_count="+string(config.triangleSampleCount)
"probability_transfer_mass="+string(sprintf('%.16g',config.transferMass))
"decision="+decision
"nominal_csv_sha256="+roleDefs.csv_sha256(1)
"nominal_mat_sha256="+roleDefs.mat_sha256(1)
"validation_1_csv_sha256="+roleDefs.csv_sha256(2)
"validation_1_mat_sha256="+roleDefs.mat_sha256(2)
"validation_2_csv_sha256="+roleDefs.csv_sha256(3)
"validation_2_mat_sha256="+roleDefs.mat_sha256(3)
"R5000_run=false"
"R15000_run=false"
"MSP_run=false"];
write_lines(path,lines);
end

function write_lines(path, lines)
fid=fopen(path,'w');if fid<0,error('Cannot write %s.',path);end
cleaner=onCleanup(@()fclose(fid));
for ii=1:numel(lines),fprintf(fid,'%s\n',char(lines(ii)));end
clear cleaner;
end
