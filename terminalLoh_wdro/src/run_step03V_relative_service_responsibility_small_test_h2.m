function result = run_step03V_relative_service_responsibility_small_test_h2()
%RUN_STEP03V_RELATIVE_SERVICE_RESPONSIBILITY_SMALL_TEST_H2 Frozen-pair audit.

taskTic = tic;
thisDir = fileparts(mfilename('fullpath'));
moduleDir = fileparts(thisDir);
rootDir = fileparts(moduleDir);
resultRoot = fullfile(rootDir, 'results', 'task-002-stage2b-b3-smoke');
outputDir = fullfile(resultRoot, ...
    '22-relative-service-responsibility-small-test', 'run-001');
tempDir = outputDir + ".tmp";
if isfolder(outputDir)
    error('Step-03V final output directory already exists.');
end
if isfolder(tempDir)
    rmdir(tempDir, 's');
end
mkdir(tempDir);

config = build_config();
stepUDir = fullfile(resultRoot, ...
    '21-service-feature-small-weight-test', 'run-001');
pairPath = fullfile(stepUDir, 'step03U_pair_components.csv');
stepUSummaryPath = fullfile(stepUDir, 'step03U_summary.txt');
checkpointDir = fullfile(moduleDir, 'output', ...
    'stage3s_state_distribution_tail_regret_audit', 'run-001', ...
    'checkpoints');
nominalPath = fullfile(moduleDir, 'output', ...
    'stage3j_wdro_input_freeze', 'run-001', ...
    'wdro_nominal_input_DAC.mat');
stepPHistory = fullfile(resultRoot, ...
    '16-dac-transport-cost-audit', 'run-001');
required = [string(pairPath); string(stepUSummaryPath); string(nominalPath)];
for ii = 1:numel(required)
    if ~isfile(required(ii))
        error('Step-03V missing required input: %s', required(ii));
    end
end
if ~isfolder(checkpointDir) || ~isfolder(stepPHistory)
    error('Step-03V checkpoints or preserved Step-03P history missing.');
end
if sha256_file(pairPath) ~= config.pairHash || ...
        sha256_file(stepUSummaryPath) ~= config.stepUSummaryHash || ...
        sha256_file(nominalPath) ~= config.nominalHash
    error('Step-03V frozen input SHA-256 mismatch.');
end

checkpointPaths = strings(numel(config.states), 1);
for ss = 1:numel(config.states)
    checkpointPaths(ss) = fullfile(checkpointDir, sprintf( ...
        'neighbors_state_%02d.mat', config.states(ss)));
end
protectedFiles = [string(pairPath); string(stepUSummaryPath); ...
    string(nominalPath); checkpointPaths; ...
    string(fullfile(thisDir, 'run_step03U_service_feature_small_weight_test_h2.m')); ...
    string(fullfile(thisDir, 'step03S_distance_block_h2.m')); ...
    string(fullfile(thisDir, 'build_step03Q_distance_matrix_h2.m')); ...
    string(fullfile(thisDir, 'solve_wdro_terminal_loh_lp_h2.m')); ...
    string(fullfile(rootDir, 'main_msp_h2_near.m')); ...
    string(fullfile(rootDir, 'fa_h2', 'build_stage_model_h2.m')); ...
    string(fullfile(rootDir, 'fa_h2', 'solve_stage_model_h2.m'))];
protectedBefore = hash_files(protectedFiles);
stepPBefore = directory_hash(stepPHistory);
peakMemory = memory_snapshot();

frozen = readtable(pairPath, 'TextType', 'string');
validate_frozen_pairs(frozen, config);
[pairTbl, diagnosticTbl, replayAudit] = replay_pairs( ...
    frozen, nominalPath, checkpointDir, config);
writetable(pairTbl, fullfile(tempDir, 'step03V_pair_results.csv'));
writetable(diagnosticTbl, fullfile(tempDir, ...
    'step03V_structure_diagnostics.csv'));
peakMemory = max(peakMemory, memory_snapshot());

[stateTbl, comparison, decision] = evaluate_features(pairTbl, config);
writetable(stateTbl, fullfile(tempDir, 'step03V_state_results.csv'));

protectedAfter = hash_files(protectedFiles);
stepPAfter = directory_hash(stepPHistory);
runnerPath = string(mfilename('fullpath'));
if ~endsWith(runnerPath, ".m")
    runnerPath = runnerPath + ".m";
end
codeMessages = checkcode(runnerPath, '-id');
runtimeSec = toc(taskTic);
peakMemory = max(peakMemory, memory_snapshot());
[acceptanceTbl, pass] = build_acceptance(pairTbl, diagnosticTbl, ...
    stateTbl, replayAudit, comparison, protectedBefore, protectedAfter, ...
    stepPBefore, stepPAfter, codeMessages, runtimeSec, peakMemory, config);
writetable(acceptanceTbl, fullfile(tempDir, ...
    'step03V_acceptance_tests.csv'));

resourceTbl = table(runtimeSec, peakMemory, height(pairTbl), ...
    height(diagnosticTbl), height(stateTbl), string(pairPath), ...
    config.pairHash, string(nominalPath), config.nominalHash, ...
    'VariableNames', {'runtime_sec', 'peak_working_set_bytes', ...
    'pair_count', 'diagnostic_row_count', 'state_result_count', ...
    'frozen_pair_path', 'frozen_pair_sha256', 'nominal_input_path', ...
    'nominal_input_sha256'});
writetable(resourceTbl, fullfile(tempDir, 'step03V_resource_report.csv'));
write_summary(fullfile(tempDir, 'step03V_summary.txt'), pairTbl, ...
    comparison, decision, replayAudit, runtimeSec, peakMemory, pass, config);
if ~pass
    error('Step-03V acceptance failed; results remain in temporary output.');
end
movefile(tempDir, outputDir);
result = struct('output_dir', string(outputDir), ...
    'conclusion', decision.conclusion, 'runtime_sec', runtimeSec, ...
    'peak_working_set_bytes', peakMemory, 'pass', pass);
fprintf('Step-03V PASS: %s, runtime %.3f s.\n', ...
    decision.conclusion, runtimeSec);
end

function config = build_config()
config = struct('states', [7; 18; 30; 31; 11; 21], ...
    'rowsPerState', 15000, 'siteCount', 4, 'nodeCount', 33, ...
    'C_bound', 357.1526447416079, 'epsDistance', 1e-9, ...
    'distanceTolerance', 1e-8, 'zeroTolerance', 1e-12, ...
    'correlationReductionRequired', 0.10, ...
    'originalDSDCorrelation', 0.846074646075, ...
    'runtimeLimitSec', 300, 'validationInputUsed', false, ...
    'optimizationUsed', false, ...
    'pairHash', ...
    "bfb81ad32c2c94dbb462c27740405cbe28a06787f50aae5b873a3e1b5ca3db74", ...
    'stepUSummaryHash', ...
    "75249a24fe0480a702ccaee8a9c2d57750ff9406a56613caee5af95f183b6e65", ...
    'nominalHash', ...
    "6936a696f5cde137aca483f8c32adee33b52cbd90559a8e6395f3686c0712945");
end

function validate_frozen_pairs(tbl, config)
required = {'evaluation_pair_id', 'pair_group', 'initial_state_id', ...
    'scenario_r', 'scenario_s', 'path_id_r', 'path_id_s', 'D_scale', ...
    'd_D', 'd_Ctilde', 'd_S', 'baseline_d_new', ...
    'relative_regret_obj_r_to_s', 'relative_regret_obj_s_to_r'};
if ~all(ismember(required, tbl.Properties.VariableNames))
    error('Step-03V frozen Step-03U schema mismatch.');
end
groups = string(tbl.pair_group);
expectedCounts = [sum(groups == "STEP03T_TIER1"), ...
    sum(groups == "STEP03T_CONTROL"), ...
    sum(groups == "HOLDOUT_TIER1"), ...
    sum(groups == "HOLDOUT_CONTROL")];
if height(tbl) ~= 36 || ~isequal(expectedCounts, [18, 6, 6, 6])
    error('Step-03V frozen pair counts mismatch.');
end
if numel(unique(tbl.evaluation_pair_id)) ~= 36 || ...
        ~isequal(sort(unique(double(tbl.initial_state_id))), ...
        sort(config.states))
    error('Step-03V frozen pair identity or state set mismatch.');
end
keys = string(tbl.initial_state_id) + ":" + ...
    string(min(double(tbl.scenario_r), double(tbl.scenario_s))) + ":" + ...
    string(max(double(tbl.scenario_r), double(tbl.scenario_s)));
if numel(unique(keys)) ~= 36
    error('Step-03V frozen pair list contains duplicates.');
end
end

function [pairTbl, diagnostics, audit] = replay_pairs(frozen, matPath, ...
        checkpointDir, config)
m = matfile(matPath);
scales = load_scales(checkpointDir, config);
P = height(frozen);
pairRecords = cell(P, 1);
diagnosticRecords = cell(P, 1);
distanceErrors = zeros(P, 4);
pathPass = true(P, 1);
for pp = 1:P
    stateId = double(frozen.initial_state_id(pp));
    r = double(frozen.scenario_r(pp));
    s = double(frozen.scenario_s(pp));
    globalR = (stateId - 1) * config.rowsPerState + r;
    globalS = (stateId - 1) * config.rowsPerState + s;
    Dr = double(m.D_node_kg(globalR, :));
    Ds = double(m.D_node_kg(globalS, :));
    Ar = reshape(logical(m.A_site_node(globalR, :, :)), ...
        config.siteCount, config.nodeCount);
    As = reshape(logical(m.A_site_node(globalS, :, :)), ...
        config.siteCount, config.nodeCount);
    Cr = reshape(double(m.C_site_node_km(globalR, :, :)), ...
        config.siteCount, config.nodeCount);
    Cs = reshape(double(m.C_site_node_km(globalS, :, :)), ...
        config.siteCount, config.nodeCount);
    pathR = double(m.path_id(globalR, 1));
    pathS = double(m.path_id(globalS, 1));
    pathPass(pp) = pathR == double(frozen.path_id_r(pp)) && ...
        pathS == double(frozen.path_id_s(pp));
    Dscale = scales(config.states == stateId);
    [dNew, dD, dC] = step03S_distance_block_h2( ...
        Dr, reshape(Ar, 1, 4, 33), reshape(Cr, 1, 4, 33), ...
        Ds, reshape(As, 1, 4, 33), reshape(Cs, 1, 4, 33), ...
        Dscale, config);
    [dS, Sr, Ss] = service_distance( ...
        Dr, Ar, Cr, Ds, As, Cs, Dscale, config);
    [dG, Gr, Gs, Pr, Ps] = responsibility_distance( ...
        Dr, Ar, Cr, Ds, As, Cs, Dscale, config);
    distanceErrors(pp, :) = abs([dD - double(frozen.d_D(pp)), ...
        dC - double(frozen.d_Ctilde(pp)), ...
        dS - double(frozen.d_S(pp)), ...
        dNew - double(frozen.baseline_d_new(pp))]);
    category = regret_category(frozen, pp);
    pairRecords{pp} = struct('evaluation_pair_id', ...
        double(frozen.evaluation_pair_id(pp)), ...
        'pair_group', string(frozen.pair_group(pp)), ...
        'regret_category', category, 'initial_state_id', stateId, ...
        'scenario_r', r, 'scenario_s', s, 'path_id_r', pathR, ...
        'path_id_s', pathS, 'D_scale', Dscale, 'd_D', dD, ...
        'd_Ctilde', dC, 'd_S', dS, 'd_G', dG, ...
        'baseline_d_new', dNew, ...
        'relative_regret_obj_r_to_s', ...
            double(frozen.relative_regret_obj_r_to_s(pp)), ...
        'relative_regret_obj_s_to_r', ...
            double(frozen.relative_regret_obj_s_to_r(pp)), ...
        'bidirectional_severity', min( ...
            double(frozen.relative_regret_obj_r_to_s(pp)), ...
            double(frozen.relative_regret_obj_s_to_r(pp))));
    diagnosticRecords{pp} = structure_diagnostic( ...
        double(frozen.evaluation_pair_id(pp)), string(frozen.pair_group(pp)), ...
        stateId, r, s, Ar, As, Pr, Ps, Gr, Gs, Sr, Ss);
end
pairTbl = records_to_table(pairRecords);
diagnostics = records_to_table(diagnosticRecords);
audit = struct('max_distance_error', max(distanceErrors, [], 'all'), ...
    'path_identity_pass', all(pathPass), ...
    'd_G_min', min(pairTbl.d_G), 'd_G_max', max(pairTbl.d_G), ...
    'd_G_finite_nonnegative', all(isfinite(pairTbl.d_G)) && ...
        all(pairTbl.d_G >= 0), ...
    'fixed_scale_pass', max(abs(pairTbl.D_scale - ...
        frozen.D_scale)) <= config.distanceTolerance);
end

function category = regret_category(tbl, row)
group = string(tbl.pair_group(row));
if contains(group, "TIER1")
    category = "TIER1_BIDIRECTIONAL_REGRET_GE_10PCT";
else
    category = "LOW_REGRET_CONTROL_BOTH_LT_1PCT";
end
end

function scales = load_scales(checkpointDir, config)
scales = NaN(numel(config.states), 1);
for ss = 1:numel(config.states)
    loaded = load(fullfile(checkpointDir, sprintf( ...
        'neighbors_state_%02d.mat', config.states(ss))), 'Dscale');
    scales(ss) = double(loaded.Dscale);
end
if any(~isfinite(scales) | scales <= 0)
    error('Step-03V invalid frozen Step-03S Dscale.');
end
end

function [dS, Sr, Ss] = service_distance(Dr, Ar, Cr, Ds, As, Cs, ...
        Dscale, config)
DbarR = Dr ./ (Dscale + config.epsDistance);
DbarS = Ds ./ (Dscale + config.epsDistance);
CbarR = Cr ./ config.C_bound;
CbarS = Cs ./ config.C_bound;
CbarR(~Ar | ~isfinite(CbarR)) = 0;
CbarS(~As | ~isfinite(CbarS)) = 0;
Sr = Ar .* DbarR ./ (1 + CbarR);
Ss = As .* DbarS ./ (1 + CbarS);
dS = mean(abs(Sr - Ss), 'all');
end

function [dG, Gr, Gs, Pr, Ps] = responsibility_distance( ...
        Dr, Ar, Cr, Ds, As, Cs, Dscale, config)
[Gr, Pr] = responsibility_feature(Dr, Ar, Cr, Dscale, config);
[Gs, Ps] = responsibility_feature(Ds, As, Cs, Dscale, config);
dG = sum(abs(Gr - Gs), 'all') / (2 * config.nodeCount);
end

function [G, P] = responsibility_feature(D, A, C, Dscale, config)
Cbar = C ./ config.C_bound;
Q = zeros(config.siteCount, config.nodeCount);
reachable = A & isfinite(Cbar);
Q(reachable) = 1 ./ (1 + Cbar(reachable));
denominator = sum(Q, 1);
P = zeros(config.siteCount, config.nodeCount);
covered = denominator > 0;
P(:, covered) = Q(:, covered) ./ denominator(covered);
Dbar = D ./ (Dscale + config.epsDistance);
G = P .* Dbar;
end

function rec = structure_diagnostic(pairId, pairGroup, stateId, r, s, ...
        Ar, As, Pr, Ps, Gr, Gs, Sr, Ss)
[prefR, secondR, gapR] = responsibility_order(Pr);
[prefS, secondS, gapS] = responsibility_order(Ps);
countR = sum(Ar, 1);
countS = sum(As, 1);
exclusiveR = countR == 1;
exclusiveS = countS == 1;
exclusiveOwnerR = prefR;
exclusiveOwnerS = prefS;
exclusiveOwnerR(~exclusiveR) = 0;
exclusiveOwnerS(~exclusiveS) = 0;
rec = struct('evaluation_pair_id', pairId, 'pair_group', pairGroup, ...
    'initial_state_id', stateId, 'scenario_r', r, 'scenario_s', s, ...
    'preferred_site_change_node_count', sum(prefR ~= prefS), ...
    'second_site_change_node_count', sum(secondR ~= secondS), ...
    'exclusive_coverage_status_change_node_count', ...
        sum(exclusiveR ~= exclusiveS), ...
    'exclusive_owner_change_node_count', ...
        sum(exclusiveOwnerR ~= exclusiveOwnerS), ...
    'service_site_count_change_node_count', sum(countR ~= countS), ...
    'service_site_count_absolute_change', sum(abs(countR - countS)), ...
    'preferred_second_gap_change_node_count', ...
        sum(abs(gapR - gapS) > 1e-12), ...
    'mean_absolute_preferred_second_gap_change', ...
        mean(abs(gapR - gapS)), ...
    'max_absolute_preferred_second_gap_change', ...
        max(abs(gapR - gapS)), ...
    'mean_absolute_G_change', mean(abs(Gr - Gs), 'all'), ...
    'mean_absolute_S_change', mean(abs(Sr - Ss), 'all'));
end

function [preferred, second, gap] = responsibility_order(P)
[sorted, order] = sort(P, 1, 'descend');
preferred = order(1, :);
second = order(2, :);
noService = sorted(1, :) <= 0;
oneService = sorted(2, :) <= 0;
preferred(noService) = 0;
second(noService | oneService) = 0;
gap = sorted(1, :) - sorted(2, :);
end

function [stateTbl, comparison, decision] = evaluate_features(pairTbl, config)
features = ["d_D"; "d_Ctilde"; "d_S"; "d_G"; "baseline_d_new"];
stateRecords = cell(numel(config.states) * numel(features), 1);
pos = 0;
for ss = 1:numel(config.states)
    stateId = config.states(ss);
    local = pairTbl(pairTbl.initial_state_id == stateId, :);
    for ff = 1:numel(features)
        feature = features(ff);
        values = double(local.(feature));
        stats = group_statistics(local, values);
        pos = pos + 1;
        stateRecords{pos} = struct('initial_state_id', stateId, ...
            'feature_name', feature, ...
            'step03T_separation_rate', stats.stepTSeparation, ...
            'holdout_separation_rate', stats.holdoutSeparation, ...
            'combined_separation_rate', stats.combinedSeparation, ...
            'combined_tier1_median', stats.combinedTierMedian, ...
            'combined_control_median', stats.combinedControlMedian);
    end
end
stateTbl = records_to_table(stateRecords);

statsD = group_statistics(pairTbl, pairTbl.d_D);
statsC = group_statistics(pairTbl, pairTbl.d_Ctilde);
statsS = group_statistics(pairTbl, pairTbl.d_S);
statsG = group_statistics(pairTbl, pairTbl.d_G);
statsNew = group_statistics(pairTbl, pairTbl.baseline_d_new);
rhoGD = rank_correlation(pairTbl.d_G, pairTbl.d_D);
rhoGC = rank_correlation(pairTbl.d_G, pairTbl.d_Ctilde);
rhoGS = rank_correlation(pairTbl.d_G, pairTbl.d_S);

gStates = stateTbl(stateTbl.feature_name == "d_G", :);
sStates = stateTbl(stateTbl.feature_name == "d_S", :);
stateDelta = gStates.combined_separation_rate - ...
    sStates.combined_separation_rate;
statesImproved = sum(stateDelta > 1e-12);
statesNotDegraded = sum(stateDelta >= -1e-12);
correlationReduced = abs(rhoGC) <= ...
    abs(config.originalDSDCorrelation) - ...
    config.correlationReductionRequired;
stepTNoWorse = statsG.stepTSeparation >= statsS.stepTSeparation - 1e-12;
holdoutNoWorse = statsG.holdoutSeparation >= ...
    statsS.holdoutSeparation - 1e-12;
controlsNotBroadlyDisplaced = ...
    statsG.stepTTierMedian >= statsG.stepTControlMedian - 1e-12 && ...
    statsG.holdoutTierMedian >= statsG.holdoutControlMedian - 1e-12;
crossStateStable = statesImproved >= 2 && statesNotDegraded >= 4;
if correlationReduced && stepTNoWorse && holdoutNoWorse && ...
        crossStateStable && controlsNotBroadlyDisplaced
    conclusion = "A. RELATIVE_SERVICE_RESPONSIBILITY_PROMISING";
elseif correlationReduced && (stepTNoWorse || holdoutNoWorse) && ...
        statesImproved >= 1
    conclusion = "B. PROMISING_BUT_STATE_DEPENDENT";
else
    conclusion = "C. NOT_BETTER_THAN_ORIGINAL_SERVICE_FEATURE";
end
comparison = struct('statsD', statsD, 'statsC', statsC, ...
    'statsS', statsS, 'statsG', statsG, 'statsNew', statsNew, ...
    'rhoGD', rhoGD, 'rhoGC', rhoGC, 'rhoGS', rhoGS, ...
    'statesImprovedVsS', statesImproved, ...
    'statesNotDegradedVsS', statesNotDegraded, ...
    'correlationReduced', correlationReduced, ...
    'stepTNoWorse', stepTNoWorse, 'holdoutNoWorse', holdoutNoWorse, ...
    'controlsNotBroadlyDisplaced', controlsNotBroadlyDisplaced, ...
    'crossStateStable', crossStateStable);
decision = struct('conclusion', conclusion);
end

function stats = group_statistics(tbl, values)
g = string(tbl.pair_group);
stepTTier = values(g == "STEP03T_TIER1");
stepTControl = values(g == "STEP03T_CONTROL");
holdTier = values(g == "HOLDOUT_TIER1");
holdControl = values(g == "HOLDOUT_CONTROL");
combinedTier = [stepTTier; holdTier];
combinedControl = [stepTControl; holdControl];
stats = struct('stepTTierMedian', median(stepTTier), ...
    'stepTControlMedian', median(stepTControl), ...
    'holdoutTierMedian', median(holdTier), ...
    'holdoutControlMedian', median(holdControl), ...
    'combinedTierMedian', median(combinedTier), ...
    'combinedControlMedian', median(combinedControl), ...
    'stepTSeparation', separation_rate(stepTTier, stepTControl), ...
    'holdoutSeparation', separation_rate(holdTier, holdControl), ...
    'combinedSeparation', separation_rate(combinedTier, combinedControl));
end

function rate = separation_rate(tier, control)
if isempty(tier) || isempty(control)
    rate = NaN;
else
    rate = mean(reshape(tier, [], 1) > reshape(control, 1, []), 'all');
end
end

function rho = rank_correlation(x, y)
rx = tied_rank(double(x(:)));
ry = tied_rank(double(y(:)));
if std(rx) <= eps || std(ry) <= eps
    rho = NaN;
else
    rho = corr(rx, ry);
end
end

function ranks = tied_rank(x)
[sorted, order] = sort(x);
ranks = zeros(size(x));
start = 1;
while start <= numel(x)
    finish = start;
    while finish < numel(x) && sorted(finish + 1) == sorted(start)
        finish = finish + 1;
    end
    ranks(order(start:finish)) = mean(start:finish);
    start = finish + 1;
end
end

function [tbl, pass] = build_acceptance(pairs, diagnostics, states, audit, ...
        comparison, protectedBefore, protectedAfter, stepPBefore, ...
        stepPAfter, codeMessages, runtimeSec, peakMemory, config)
groups = string(pairs.pair_group);
checks = cell(19, 1);
checks{1} = check_record(1, height(pairs) == 36, height(pairs), 36);
checks{2} = check_record(2, sum(groups == "STEP03T_TIER1") == 18 && ...
    sum(groups == "STEP03T_CONTROL") == 6, ...
    sprintf('%d/%d', sum(groups == "STEP03T_TIER1"), ...
    sum(groups == "STEP03T_CONTROL")), "18/6");
checks{3} = check_record(3, sum(groups == "HOLDOUT_TIER1") == 6 && ...
    sum(groups == "HOLDOUT_CONTROL") == 6, ...
    sprintf('%d/%d', sum(groups == "HOLDOUT_TIER1"), ...
    sum(groups == "HOLDOUT_CONTROL")), "6/6");
checks{4} = check_record(4, numel(unique(pairs.evaluation_pair_id)) == 36, ...
    numel(unique(pairs.evaluation_pair_id)), 36);
checks{5} = check_record(5, audit.path_identity_pass, ...
    audit.path_identity_pass, true);
checks{6} = check_record(6, audit.max_distance_error <= ...
    config.distanceTolerance, audit.max_distance_error, ...
    config.distanceTolerance);
checks{7} = check_record(7, audit.fixed_scale_pass, ...
    audit.fixed_scale_pass, true);
checks{8} = check_record(8, audit.d_G_finite_nonnegative, ...
    "finite nonnegative d_G", "finite nonnegative d_G");
checks{9} = check_record(9, height(diagnostics) == 36, ...
    height(diagnostics), 36);
checks{10} = check_record(10, height(states) == 30, height(states), 30);
checks{11} = check_record(11, isfinite(comparison.rhoGD) && ...
    isfinite(comparison.rhoGC) && isfinite(comparison.rhoGS), ...
    sprintf('%.12g/%.12g/%.12g', comparison.rhoGD, ...
    comparison.rhoGC, comparison.rhoGS), "finite correlations");
checks{12} = check_record(12, all(isfinite(pairs{:, ...
    {'d_D', 'd_Ctilde', 'd_S', 'd_G', 'baseline_d_new'}}), 'all'), ...
    "finite pair distances", "finite pair distances");
checks{13} = check_record(13, isequal(protectedBefore, protectedAfter), ...
    "frozen inputs and protected code unchanged", "unchanged");
checks{14} = check_record(14, stepPBefore == stepPAfter, ...
    "Step-03P history unchanged", "unchanged");
checks{15} = check_record(15, ~config.validationInputUsed, ...
    "nominal selected rows only", "no validation");
checks{16} = check_record(16, ~config.optimizationUsed, ...
    "no optimization invoked", "no WDRO/Gurobi/MSP/T solve");
checks{17} = check_record(17, isempty(codeMessages), ...
    numel(codeMessages), 0);
checks{18} = check_record(18, runtimeSec <= config.runtimeLimitSec, ...
    runtimeSec, config.runtimeLimitSec);
checks{19} = check_record(19, peakMemory > 0 && isfinite(peakMemory), ...
    peakMemory, ">0 finite");
tbl = records_to_table(checks);
pass = all(tbl.status == "PASS");
end

function rec = check_record(id, passed, observed, expected)
if passed
    status = "PASS";
else
    status = "FAIL";
end
rec = struct('check_id', id, 'status', status, ...
    'observed', string(observed), 'expected', string(expected));
end

function write_summary(path, pairs, comparison, decision, audit, ...
        runtimeSec, peakMemory, pass, config)
if pass
    status = "PASS";
else
    status = "FAIL";
end
lines = [
    "Step-03V relative service responsibility small test"
    "status=" + status
    "conclusion=" + decision.conclusion
    "frozen_pair_count=" + string(height(pairs))
    sprintf('d_G_range=[%.15g, %.15g]', min(pairs.d_G), max(pairs.d_G))
    sprintf('spearman_dG_dD=%.12f', comparison.rhoGD)
    sprintf('spearman_dG_dCtilde=%.12f', comparison.rhoGC)
    sprintf('spearman_dG_dS=%.12f', comparison.rhoGS)
    sprintf('original_spearman_dS_dCtilde=%.12f', ...
        config.originalDSDCorrelation)
    sprintf('step03T_separation_dG=%.9f', ...
        comparison.statsG.stepTSeparation)
    sprintf('step03T_separation_dS=%.9f', ...
        comparison.statsS.stepTSeparation)
    sprintf('step03T_separation_baseline_d_new=%.9f', ...
        comparison.statsNew.stepTSeparation)
    sprintf('holdout_separation_dG=%.9f', ...
        comparison.statsG.holdoutSeparation)
    sprintf('holdout_separation_dS=%.9f', ...
        comparison.statsS.holdoutSeparation)
    sprintf('holdout_separation_baseline_d_new=%.9f', ...
        comparison.statsNew.holdoutSeparation)
    sprintf('states_improved_vs_dS=%d', comparison.statesImprovedVsS)
    sprintf('states_not_degraded_vs_dS=%d', ...
        comparison.statesNotDegradedVsS)
    "1_dG_reduces_Ctilde_duplication=" + ...
        yes_no(comparison.correlationReduced) + ...
        "; Spearman is compared with the frozen d_S value 0.8461."
    "2_dG_identifies_Tier1_better_than_dS=" + ...
        yes_no(comparison.stepTNoWorse && comparison.holdoutNoWorse) + ...
        "; both Step-03T and holdout separation must be no worse."
    "3_low_regret_controls_broadly_overpulled=" + ...
        yes_no(~comparison.controlsNotBroadlyDisplaced) + ...
        "; diagnostics use within-feature Tier-1/control medians."
    "4_cross_state_stable=" + yes_no(comparison.crossStateStable) + ...
        "; improvement must cover >=2 states and >=4 states must not degrade."
    "5_worth_small_weight_test=" + yes_no(startsWith( ...
        decision.conclusion, "A.")) + ...
        "; no weight is selected or adopted in this run."
    "formal_distance_modified=NO"
    "optimization_or_validation_used=NO"
    sprintf('maximum_frozen_distance_replay_error=%.15g', ...
        audit.max_distance_error)
    sprintf('runtime_sec=%.6f', runtimeSec)
    sprintf('peak_working_set_bytes=%.0f', peakMemory)
    ];
write_lines(path, lines);
end

function value = yes_no(flag)
if flag
    value = "YES";
else
    value = "NO";
end
end

function tbl = records_to_table(records)
if isempty(records)
    tbl = table();
else
    tbl = struct2table(vertcat(records{:}), 'AsArray', true);
end
end

function write_lines(path, lines)
fid = fopen(path, 'w');
if fid < 0
    error('Step-03V cannot open %s.', path);
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

function hashes = hash_files(paths)
hashes = strings(numel(paths), 1);
for ii = 1:numel(paths)
    if ~isfile(paths(ii))
        error('Step-03V protected file missing: %s', paths(ii));
    end
    hashes(ii) = sha256_file(paths(ii));
end
end

function digest = directory_hash(folder)
listing = dir(fullfile(folder, '**', '*'));
listing = listing(~[listing.isdir]);
relative = strings(numel(listing), 1);
hashes = strings(numel(listing), 1);
for ii = 1:numel(listing)
    fullPath = fullfile(listing(ii).folder, listing(ii).name);
    relative(ii) = erase(string(fullPath), string(folder) + filesep);
    hashes(ii) = sha256_file(fullPath);
end
[relative, order] = sort(relative);
hashes = hashes(order);
payload = join(relative + "|" + hashes, newline);
md = java.security.MessageDigest.getInstance('SHA-256');
md.update(unicode2native(char(payload), 'UTF-8'));
digest = lower(string(reshape(dec2hex( ...
    typecast(md.digest(), 'uint8'), 2).', 1, [])));
end

function digest = sha256_file(path)
fid = fopen(path, 'rb');
if fid < 0
    error('Step-03V cannot open file for SHA-256: %s', path);
end
cleanup = onCleanup(@() fclose(fid));
md = java.security.MessageDigest.getInstance('SHA-256');
while true
    bytes = fread(fid, 1024 * 1024, '*uint8');
    if isempty(bytes)
        break;
    end
    md.update(bytes);
end
clear cleanup;
digest = lower(string(reshape(dec2hex( ...
    typecast(md.digest(), 'uint8'), 2).', 1, [])));
end
