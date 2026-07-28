function result = run_step03W_fixed_decision_loss_consistency_h2()
%RUN_STEP03W_FIXED_DECISION_LOSS_CONSISTENCY_H2 Frozen-pair loss audit.

taskTic = tic;
thisDir = fileparts(mfilename('fullpath'));
moduleDir = fileparts(thisDir);
rootDir = fileparts(moduleDir);
resultRoot = fullfile(rootDir, 'results', 'task-002-stage2b-b3-smoke');
outputDir = fullfile(resultRoot, ...
    '23-fixed-decision-loss-consistency', 'run-001');
tempDir = outputDir + ".tmp";
if isfolder(outputDir)
    error('Step-03W final output directory already exists.');
end
if isfolder(tempDir)
    rmdir(tempDir, 's');
end
mkdir(tempDir);

config = build_config();
stepSDir = fullfile(resultRoot, ...
    '19-state-distribution-tail-regret-audit', 'run-001');
stepTDir = fullfile(resultRoot, ...
    '20-ctilde-tier1-structural-diagnosis', 'run-001');
stepUDir = fullfile(resultRoot, ...
    '21-service-feature-small-weight-test', 'run-001');
stepVDir = fullfile(resultRoot, ...
    '22-relative-service-responsibility-small-test', 'run-001');
crossPath = fullfile(stepSDir, 'step03S_tail_cross_regret.csv');
selectedPath = fullfile(stepTDir, 'step03T_selected_pairs.csv');
replayPath = fullfile(stepTDir, 'step03T_cross_recourse_detail.csv');
pairUPath = fullfile(stepUDir, 'step03U_pair_components.csv');
pairVPath = fullfile(stepVDir, 'step03V_pair_results.csv');
nominalPath = fullfile(moduleDir, 'output', ...
    'stage3j_wdro_input_freeze', 'run-001', 'wdro_nominal_input_DAC.mat');
nearPath = fullfile(rootDir, 'data', 'yuanqi', 'near_stage_msp_input.mat');
stepPHistory = fullfile(resultRoot, ...
    '16-dac-transport-cost-audit', 'run-001');
required = [string(crossPath); string(selectedPath); string(replayPath); ...
    string(pairUPath); string(pairVPath); string(nominalPath); string(nearPath)];
for ii = 1:numel(required)
    if ~isfile(required(ii))
        error('Step-03W missing required input: %s', required(ii));
    end
end
if ~isfolder(stepPHistory)
    error('Step-03W preserved Step-03P history is missing.');
end
verify_expected_hashes(crossPath, selectedPath, replayPath, pairUPath, ...
    pairVPath, nominalPath, nearPath, config);

protectedFiles = [required; ...
    string(fullfile(thisDir, 'evaluate_step03T_fixed_T_recourse_h2.m')); ...
    string(fullfile(thisDir, 'run_step03T_ctilde_tier1_structural_diagnosis_h2.m')); ...
    string(fullfile(thisDir, 'step03S_distance_block_h2.m')); ...
    string(fullfile(thisDir, 'build_step03Q_distance_matrix_h2.m')); ...
    string(fullfile(thisDir, 'solve_wdro_terminal_loh_lp_h2.m')); ...
    string(fullfile(rootDir, 'main_msp_h2_near.m')); ...
    string(fullfile(rootDir, 'fa_h2', 'build_stage_model_h2.m')); ...
    string(fullfile(rootDir, 'fa_h2', 'solve_stage_model_h2.m'))];
protectedBefore = hash_files(protectedFiles);
stepPBefore = directory_hash(stepPHistory);
peakMemory = memory_snapshot();

pairU = readtable(pairUPath, 'TextType', 'string');
pairV = readtable(pairVPath, 'TextType', 'string');
selected = readtable(selectedPath, 'TextType', 'string');
replay = readtable(replayPath, 'TextType', 'string');
cross = readtable(crossPath, 'TextType', 'string');
inputAudit = validate_inputs(pairU, pairV, selected, replay, cross, config);
peakMemory = max(peakMemory, memory_snapshot());

rawNear = load(nearPath, 'NearStageInput');
ni = rawNear.NearStageInput;
if isfield(ni.Cost, 'reserve_shortage_penalty_yuan_per_kg')
    M = double(ni.Cost.reserve_shortage_penalty_yuan_per_kg);
elseif isfield(ni.Cost, 'cost_reserve_shortage')
    M = double(ni.Cost.cost_reserve_shortage);
else
    error('Step-03W cannot trace the shortage penalty.');
end
gamma = 0.001 * M;
if abs(M - config.expectedM) > 1e-12 || abs(gamma - 2) > 1e-12
    error('Step-03W frozen operating-cost constants changed.');
end

[pairTbl, replayAudit] = build_pair_results(pairU, selected, replay, ...
    cross, nominalPath, M, gamma, config);
positiveDistances = pairTbl.d_new(pairTbl.d_new > config.zeroTolerance);
if isempty(positiveDistances)
    error('Step-03W frozen pairs have no positive d_new.');
end
smallThreshold = quantile(positiveDistances, 0.25);
pairTbl.small_distance_q25 = pairTbl.d_new <= smallThreshold;
pairTbl.small_distance_high_fixed_loss = pairTbl.small_distance_q25 & ...
    pairTbl.large_fixed_loss_mismatch;
writetable(pairTbl, fullfile(tempDir, 'step03W_pair_results.csv'));

[slopeTbl, groupAudit] = summarize_groups(pairTbl, config);
writetable(slopeTbl, fullfile(tempDir, 'step03W_loss_slope_results.csv'));
[stateTbl, stateAudit] = summarize_states(pairTbl, config);
writetable(stateTbl, fullfile(tempDir, 'step03W_state_results.csv'));
[zeroTbl, zeroAudit] = audit_zero_distance_cross_rows(cross, gamma, config);
writetable(zeroTbl, fullfile(tempDir, 'step03W_zero_distance_audit.csv'));
peakMemory = max(peakMemory, memory_snapshot());

decision = choose_conclusion(groupAudit, stateAudit, pairTbl, ...
    replayAudit, inputAudit, config);
protectedAfter = hash_files(protectedFiles);
stepPAfter = directory_hash(stepPHistory);
runnerPath = string(mfilename('fullpath'));
if ~endsWith(runnerPath, ".m")
    runnerPath = runnerPath + ".m";
end
codeMessages = checkcode(runnerPath, '-id');
runtimeSec = toc(taskTic);
peakMemory = max(peakMemory, memory_snapshot());
[acceptanceTbl, pass] = build_acceptance(pairTbl, slopeTbl, stateTbl, ...
    inputAudit, replayAudit, zeroAudit, protectedBefore, protectedAfter, ...
    stepPBefore, stepPAfter, codeMessages, runtimeSec, peakMemory, config);
writetable(acceptanceTbl, fullfile(tempDir, ...
    'step03W_acceptance_tests.csv'));

resourceTbl = table(runtimeSec, peakMemory, replayAudit.newReplayCount, ...
    replayAudit.reusedReplayCount, replayAudit.gurobiInvocationCount, ...
    height(pairTbl), height(cross), string(nominalPath), config.nominalHash, ...
    'VariableNames', {'runtime_sec', 'peak_working_set_bytes', ...
    'new_fixed_T_recourse_evaluations', 'reused_fixed_T_recourse_rows', ...
    'new_gurobi_batch_invocations', 'frozen_pair_count', ...
    'step03S_cross_row_count', 'nominal_input_path', ...
    'nominal_input_sha256'});
writetable(resourceTbl, fullfile(tempDir, 'step03W_resource_report.csv'));
write_summary(fullfile(tempDir, 'step03W_summary.txt'), pairTbl, ...
    slopeTbl, groupAudit, stateAudit, zeroAudit, replayAudit, ...
    decision, smallThreshold, runtimeSec, peakMemory, pass, config);
if ~pass
    error('Step-03W acceptance failed; results remain in temporary output.');
end
movefile(tempDir, outputDir);
result = struct('output_dir', string(outputDir), ...
    'conclusion', decision, ...
    'new_recourse_evaluations', replayAudit.newReplayCount, ...
    'runtime_sec', runtimeSec, 'peak_working_set_bytes', peakMemory, ...
    'pass', pass);
fprintf('Step-03W PASS: %s, new evaluations %d, runtime %.3f s.\n', ...
    decision, replayAudit.newReplayCount, runtimeSec);
end

function config = build_config()
config = struct('states', [7; 18; 30; 31; 11; 21], ...
    'rowsPerState', 15000, 'largeMismatchThreshold', 0.10, ...
    'zeroTolerance', 1e-12, 'chainTolerance', 1e-8, ...
    'distanceTolerance', 1e-8, 'runtimeLimitSec', 600, ...
    'expectedM', 2000, 'validationInputUsed', false, ...
    'formalWdroUsed', false, 'mspUsed', false, ...
    'crossHash', ...
    "7aa137c4e233b3e2f59b92287fc70ba2bf33151fb8607bf0e3ba20c2c4b79be6", ...
    'selectedHash', ...
    "4ce8acbd3291c3742301c4a13bde09f3f7fd4922eada546565c78a8d97a22f24", ...
    'replayHash', ...
    "34795db89e29c7796339c20521bbc0fe8414a1155041bbae1f5d824231968a5a", ...
    'pairUHash', ...
    "bfb81ad32c2c94dbb462c27740405cbe28a06787f50aae5b873a3e1b5ca3db74", ...
    'pairVHash', ...
    "3609466d5177b90538e7c9eb95f548039820a74808ba86cc3f7f147a5f739052", ...
    'nominalHash', ...
    "6936a696f5cde137aca483f8c32adee33b52cbd90559a8e6395f3686c0712945", ...
    'nearHash', ...
    "536b25868e6d7cc812a331c0d3e0ffbd5f6958e6883bd39bcae3901c372abf24");
end

function verify_expected_hashes(crossPath, selectedPath, replayPath, ...
        pairUPath, pairVPath, nominalPath, nearPath, config)
paths = [string(crossPath); string(selectedPath); string(replayPath); ...
    string(pairUPath); string(pairVPath); string(nominalPath); string(nearPath)];
expected = [config.crossHash; config.selectedHash; config.replayHash; ...
    config.pairUHash; config.pairVHash; config.nominalHash; config.nearHash];
actual = hash_files(paths);
if ~isequal(actual, expected)
    error('Step-03W frozen input SHA-256 mismatch.');
end
end

function audit = validate_inputs(pairU, pairV, selected, replay, cross, config)
requiredPair = {'evaluation_pair_id', 'pair_group', 'initial_state_id', ...
    'scenario_r', 'scenario_s', 'path_id_r', 'path_id_s', ...
    'd_D', 'd_Ctilde', 'baseline_d_new', ...
    'relative_regret_obj_r_to_s', 'relative_regret_obj_s_to_r'};
requiredSelected = {'pair_id', 'initial_state_id', 'scenario_r', ...
    'scenario_s', 'path_id_r', 'path_id_s', 'T_r1', 'T_r2', 'T_r3', ...
    'T_r4', 'T_s1', 'T_s2', 'T_s3', 'T_s4', 'group_type'};
requiredReplay = {'pair_id', 'replay_case', 'operating_loss', ...
    'solver_status'};
requiredCross = [requiredSelected(2:end-1), {'own_operating_loss_r', ...
    'own_operating_loss_s', 'cross_objective_r_to_s', ...
    'cross_objective_s_to_r', 'd_new'}];
if ~all(ismember(requiredPair, pairU.Properties.VariableNames)) || ...
        ~all(ismember(requiredPair, pairV.Properties.VariableNames)) || ...
        ~all(ismember(requiredSelected, selected.Properties.VariableNames)) || ...
        ~all(ismember(requiredReplay, replay.Properties.VariableNames)) || ...
        ~all(ismember(requiredCross, cross.Properties.VariableNames))
    error('Step-03W frozen schema mismatch.');
end
groups = string(pairU.pair_group);
counts = [sum(groups == "STEP03T_TIER1"), ...
    sum(groups == "STEP03T_CONTROL"), ...
    sum(groups == "HOLDOUT_TIER1"), ...
    sum(groups == "HOLDOUT_CONTROL")];
if height(pairU) ~= 36 || ~isequal(counts, [18, 6, 6, 6]) || ...
        height(pairV) ~= 36 || height(selected) ~= 24 || height(replay) ~= 96
    error('Step-03W frozen row counts mismatch.');
end
identityU = pair_identity(pairU);
identityV = pair_identity(pairV);
if ~isequal(identityU, identityV) || max(abs(double(pairU.baseline_d_new) - ...
        double(pairV.baseline_d_new))) > config.distanceTolerance
    error('Step-03W Step-03U and Step-03V frozen pair mismatch.');
end
selectedIdentity = string(selected.initial_state_id) + ":" + ...
    string(selected.scenario_r) + ":" + string(selected.scenario_s) + ":" + ...
    string(selected.path_id_r) + ":" + string(selected.path_id_s);
if ~isequal(identityU(1:24), selectedIdentity)
    error('Step-03W Step-03T pair order does not match frozen 36 pairs.');
end
if any(replay.solver_status ~= "OPTIMAL") || ...
        numel(unique(double(replay.pair_id))) ~= 24
    error('Step-03W Step-03T replay status or pair identity mismatch.');
end
for pp = 1:24
    local = replay(double(replay.pair_id) == pp, :);
    if height(local) ~= 4 || ~isequal(sort(string(local.replay_case)), ...
            sort(["T_R_ON_R"; "T_R_ON_S"; "T_S_ON_R"; "T_S_ON_S"]))
        error('Step-03W incomplete Step-03T replay for pair %d.', pp);
    end
end
if ~isequal(sort(unique(double(pairU.initial_state_id))), sort(config.states))
    error('Step-03W six-state set mismatch.');
end
audit = struct('pairCount', height(pairU), 'stepTCount', height(selected), ...
    'holdoutCount', height(pairU) - height(selected), ...
    'stepTReplayRows', height(replay), 'crossRows', height(cross), ...
    'identityPass', true);
end

function identity = pair_identity(tbl)
identity = string(tbl.initial_state_id) + ":" + ...
    string(tbl.scenario_r) + ":" + string(tbl.scenario_s) + ":" + ...
    string(tbl.path_id_r) + ":" + string(tbl.path_id_s);
end

function [pairTbl, audit] = build_pair_results(pairU, selected, replay, ...
        cross, nominalPath, M, gamma, config)
P = height(pairU);
records = cell(P, 1);
reusedError = zeros(24, 4);
for pp = 1:24
    local = replay(double(replay.pair_id) == pp, :);
    qTrR = replay_value(local, "T_R_ON_R");
    qTrS = replay_value(local, "T_R_ON_S");
    qTsR = replay_value(local, "T_S_ON_R");
    qTsS = replay_value(local, "T_S_ON_S");
    Tr = table_T(selected, pp, "r");
    Ts = table_T(selected, pp, "s");
    records{pp} = pair_record(pairU, pp, Tr, Ts, qTrR, qTrS, ...
        qTsR, qTsS, "STEP03T_REUSED", config);
    frozenCross = find_cross_row(cross, pairU(pp, :));
    expected = frozen_operating_values(frozenCross, gamma);
    reusedError(pp, :) = abs([qTrR, qTrS, qTsR, qTsS] - expected);
end

holdoutRows = 25:P;
H = numel(holdoutRows);
D = zeros(4 * H, 33);
A = false(4 * H, 4, 33);
C = NaN(4 * H, 4, 33);
T = zeros(4 * H, 4);
expectedNew = zeros(H, 4);
pathPass = true(H, 1);
m = matfile(nominalPath);
for hh = 1:H
    pp = holdoutRows(hh);
    frozenCross = find_cross_row(cross, pairU(pp, :));
    Tr = table_T(frozenCross, 1, "r");
    Ts = table_T(frozenCross, 1, "s");
    stateId = double(pairU.initial_state_id(pp));
    r = double(pairU.scenario_r(pp));
    s = double(pairU.scenario_s(pp));
    globalR = (stateId - 1) * config.rowsPerState + r;
    globalS = (stateId - 1) * config.rowsPerState + s;
    Dr = double(m.D_node_kg(globalR, :));
    Ds = double(m.D_node_kg(globalS, :));
    Ar = logical(m.A_site_node(globalR, :, :));
    As = logical(m.A_site_node(globalS, :, :));
    Cr = double(m.C_site_node_km(globalR, :, :));
    Cs = double(m.C_site_node_km(globalS, :, :));
    pathPass(hh) = double(m.path_id(globalR, 1)) == ...
        double(pairU.path_id_r(pp)) && double(m.path_id(globalS, 1)) == ...
        double(pairU.path_id_s(pp));
    rows = (hh - 1) * 4 + (1:4);
    D(rows, :) = [Dr; Ds; Ds; Dr];
    A(rows, :, :) = cat(1, Ar, As, As, Ar);
    C(rows, :, :) = cat(1, Cr, Cs, Cs, Cr);
    T(rows, :) = [Tr; Ts; Tr; Ts];
    expectedNew(hh, :) = frozen_operating_values(frozenCross, gamma);
end
ev = evaluate_step03T_fixed_T_recourse_h2(D, A, C, T, M, config);
if ev.exitflag ~= 1 || ev.status ~= "OPTIMAL"
    error('Step-03W holdout fixed-T recourse was not OPTIMAL.');
end
newError = zeros(H, 4);
for hh = 1:H
    pp = holdoutRows(hh);
    rows = (hh - 1) * 4 + (1:4);
    qTrR = ev.operating_loss(rows(1));
    qTsS = ev.operating_loss(rows(2));
    qTrS = ev.operating_loss(rows(3));
    qTsR = ev.operating_loss(rows(4));
    frozenCross = find_cross_row(cross, pairU(pp, :));
    Tr = table_T(frozenCross, 1, "r");
    Ts = table_T(frozenCross, 1, "s");
    records{pp} = pair_record(pairU, pp, Tr, Ts, qTrR, qTrS, ...
        qTsR, qTsS, "NEW_HOLDOUT_REPLAY", config);
    newError(hh, :) = abs([qTrR, qTrS, qTsR, qTsS] - expectedNew(hh, :));
end
pairTbl = records_to_table(records);
toleranceNew = config.chainTolerance + 8 * eps(max(abs(expectedNew), 1));
audit = struct('reusedReplayCount', 96, 'newReplayCount', 48, ...
    'gurobiInvocationCount', 1, ...
    'allNewOptimal', ev.exitflag == 1 && ev.status == "OPTIMAL", ...
    'pathIdentityPass', all(pathPass), ...
    'maxReusedFrozenError', max(reusedError, [], 'all'), ...
    'maxNewFrozenError', max(newError, [], 'all'), ...
    'newFrozenTolerancePass', all(newError <= toleranceNew, 'all'), ...
    'maxBalanceError', ev.max_demand_balance_error, ...
    'maxCapacityViolation', ev.max_site_capacity_violation, ...
    'objectiveReconstructionError', ev.objective_reconstruction_abs_error);
end

function value = replay_value(tbl, label)
row = tbl(tbl.replay_case == label, :);
if height(row) ~= 1
    error('Step-03W replay label %s is not unique.', label);
end
value = double(row.operating_loss);
end

function row = find_cross_row(cross, pair)
mask = double(cross.initial_state_id) == double(pair.initial_state_id) & ...
    double(cross.scenario_r) == double(pair.scenario_r) & ...
    double(cross.scenario_s) == double(pair.scenario_s) & ...
    double(cross.path_id_r) == double(pair.path_id_r) & ...
    double(cross.path_id_s) == double(pair.path_id_s);
row = cross(mask, :);
if height(row) ~= 1
    error('Step-03W frozen Step-03S pair lookup returned %d rows.', height(row));
end
end

function T = table_T(tbl, row, side)
T = zeros(1, 4);
for ii = 1:4
    T(ii) = double(tbl.(sprintf('T_%s%d', side, ii))(row));
end
end

function values = frozen_operating_values(row, gamma)
Tr = table_T(row, 1, "r");
Ts = table_T(row, 1, "s");
qTrR = double(row.own_operating_loss_r);
qTrS = double(row.cross_objective_r_to_s) - gamma * sum(Tr);
qTsR = double(row.cross_objective_s_to_r) - gamma * sum(Ts);
qTsS = double(row.own_operating_loss_s);
values = [qTrR, qTrS, qTsR, qTsS];
end

function rec = pair_record(pairU, pp, Tr, Ts, qTrR, qTrS, qTsR, ...
        qTsS, source, config)
deltaTr = abs(qTrR - qTrS);
deltaTs = abs(qTsR - qTsS);
relTr = deltaTr / max([1, abs(qTrR), abs(qTrS)]);
relTs = deltaTs / max([1, abs(qTsR), abs(qTsS)]);
pairRel = max(relTr, relTs);
dNew = double(pairU.baseline_d_new(pp));
if dNew < config.zeroTolerance
    slope = NaN;
    slopeStatus = "NOT_INTERPRETED_D_NEW_LT_1E12";
else
    slope = max(deltaTr, deltaTs) / max(dNew, config.zeroTolerance);
    slopeStatus = "FINITE_POSITIVE_DISTANCE";
end
rec = struct('evaluation_pair_id', double(pairU.evaluation_pair_id(pp)), ...
    'pair_group', string(pairU.pair_group(pp)), ...
    'initial_state_id', double(pairU.initial_state_id(pp)), ...
    'scenario_r', double(pairU.scenario_r(pp)), ...
    'scenario_s', double(pairU.scenario_s(pp)), ...
    'path_id_r', double(pairU.path_id_r(pp)), ...
    'path_id_s', double(pairU.path_id_s(pp)), ...
    'replay_source', source, 'd_D', double(pairU.d_D(pp)), ...
    'd_Ctilde', double(pairU.d_Ctilde(pp)), 'd_new', dNew, ...
    'T_r1', Tr(1), 'T_r2', Tr(2), 'T_r3', Tr(3), 'T_r4', Tr(4), ...
    'T_s1', Ts(1), 'T_s2', Ts(2), 'T_s3', Ts(3), 'T_s4', Ts(4), ...
    'Q_Tr_xi_r', qTrR, 'Q_Tr_xi_s', qTrS, ...
    'Q_Ts_xi_r', qTsR, 'Q_Ts_xi_s', qTsS, ...
    'DeltaQ_Tr', deltaTr, 'DeltaQ_Ts', deltaTs, ...
    'RelDeltaQ_Tr', relTr, 'RelDeltaQ_Ts', relTs, ...
    'PairRelDeltaQ', pairRel, ...
    'large_fixed_loss_mismatch', ...
        pairRel >= config.largeMismatchThreshold, ...
    'LossSlope', slope, 'loss_slope_status', slopeStatus, ...
    'relative_regret_obj_r_to_s', ...
        double(pairU.relative_regret_obj_r_to_s(pp)), ...
    'relative_regret_obj_s_to_r', ...
        double(pairU.relative_regret_obj_s_to_r(pp)), ...
    'bidirectional_regret_severity', min( ...
        double(pairU.relative_regret_obj_r_to_s(pp)), ...
        double(pairU.relative_regret_obj_s_to_r(pp))));
end

function [tbl, audit] = summarize_groups(pairs, config)
groups = ["STEP03T_TIER1"; "STEP03T_CONTROL"; ...
    "HOLDOUT_TIER1"; "HOLDOUT_CONTROL"; "ALL"];
records = cell(numel(groups), 1);
for gg = 1:numel(groups)
    if groups(gg) == "ALL"
        local = pairs;
    else
        local = pairs(pairs.pair_group == groups(gg), :);
    end
    slopes = local.LossSlope(isfinite(local.LossSlope));
    records{gg} = struct('pair_group', groups(gg), ...
        'pair_count', height(local), ...
        'PairRelDeltaQ_median', median(local.PairRelDeltaQ), ...
        'PairRelDeltaQ_q90', quantile(local.PairRelDeltaQ, 0.90), ...
        'PairRelDeltaQ_max', max(local.PairRelDeltaQ), ...
        'large_mismatch_count', sum(local.large_fixed_loss_mismatch), ...
        'large_mismatch_share', mean(local.large_fixed_loss_mismatch), ...
        'LossSlope_interpretable_count', numel(slopes), ...
        'LossSlope_median', finite_quantile(slopes, 0.50), ...
        'LossSlope_q90', finite_quantile(slopes, 0.90), ...
        'LossSlope_max', finite_quantile(slopes, 1), ...
        'spearman_dnew_DeltaQ_Tr', ...
            rank_correlation(local.d_new, local.DeltaQ_Tr), ...
        'spearman_dnew_DeltaQ_Ts', ...
            rank_correlation(local.d_new, local.DeltaQ_Ts), ...
        'spearman_regret_PairRelDeltaQ', ...
            rank_correlation(local.bidirectional_regret_severity, ...
            local.PairRelDeltaQ));
end
tbl = records_to_table(records);
stepTier = tbl(tbl.pair_group == "STEP03T_TIER1", :);
stepControl = tbl(tbl.pair_group == "STEP03T_CONTROL", :);
holdTier = tbl(tbl.pair_group == "HOLDOUT_TIER1", :);
holdControl = tbl(tbl.pair_group == "HOLDOUT_CONTROL", :);
audit = struct('stepTDifference', stepTier.large_mismatch_share - ...
    stepControl.large_mismatch_share, ...
    'holdoutDifference', holdTier.large_mismatch_share - ...
    holdControl.large_mismatch_share, ...
    'stepTTierShare', stepTier.large_mismatch_share, ...
    'stepTControlShare', stepControl.large_mismatch_share, ...
    'holdoutTierShare', holdTier.large_mismatch_share, ...
    'holdoutControlShare', holdControl.large_mismatch_share, ...
    'threshold', config.largeMismatchThreshold);
end

function value = finite_quantile(values, probability)
if isempty(values)
    value = NaN;
else
    value = quantile(values, probability);
end
end

function [tbl, audit] = summarize_states(pairs, config)
records = cell(numel(config.states), 1);
directionCount = 0;
for ss = 1:numel(config.states)
    stateId = config.states(ss);
    local = pairs(pairs.initial_state_id == stateId, :);
    stepTier = local(local.pair_group == "STEP03T_TIER1", :);
    stepControl = local(local.pair_group == "STEP03T_CONTROL", :);
    holdTier = local(local.pair_group == "HOLDOUT_TIER1", :);
    holdControl = local(local.pair_group == "HOLDOUT_CONTROL", :);
    tier = [stepTier; holdTier];
    control = [stepControl; holdControl];
    combinedDifference = mean(tier.large_fixed_loss_mismatch) - ...
        mean(control.large_fixed_loss_mismatch);
    consistent = combinedDifference > 1e-12;
    directionCount = directionCount + consistent;
    records{ss} = struct('initial_state_id', stateId, ...
        'pair_count', height(local), ...
        'step03T_tier_large_share', mean(stepTier.large_fixed_loss_mismatch), ...
        'step03T_control_large_share', ...
            mean(stepControl.large_fixed_loss_mismatch), ...
        'step03T_tier_minus_control_pp', 100 * ( ...
            mean(stepTier.large_fixed_loss_mismatch) - ...
            mean(stepControl.large_fixed_loss_mismatch)), ...
        'holdout_tier_large_share', mean(holdTier.large_fixed_loss_mismatch), ...
        'holdout_control_large_share', ...
            mean(holdControl.large_fixed_loss_mismatch), ...
        'holdout_tier_minus_control_pp', 100 * ( ...
            mean(holdTier.large_fixed_loss_mismatch) - ...
            mean(holdControl.large_fixed_loss_mismatch)), ...
        'combined_tier_large_share', mean(tier.large_fixed_loss_mismatch), ...
        'combined_control_large_share', ...
            mean(control.large_fixed_loss_mismatch), ...
        'combined_tier_minus_control_pp', 100 * combinedDifference, ...
        'tier_higher_direction', consistent, ...
        'small_distance_high_loss_count', ...
            sum(local.small_distance_high_fixed_loss), ...
        'PairRelDeltaQ_median', median(local.PairRelDeltaQ), ...
        'PairRelDeltaQ_max', max(local.PairRelDeltaQ), ...
        'spearman_dnew_DeltaQ_Tr', ...
            rank_correlation(local.d_new, local.DeltaQ_Tr), ...
        'spearman_dnew_DeltaQ_Ts', ...
            rank_correlation(local.d_new, local.DeltaQ_Ts));
end
tbl = records_to_table(records);
audit = struct('directionConsistentStateCount', directionCount);
end

function [tbl, audit] = audit_zero_distance_cross_rows(cross, gamma, config)
zero = cross(double(cross.d_new) < config.zeroTolerance, :);
if isempty(zero)
    rec = struct('zero_distance_pair_count', 0, ...
        'PairRelDeltaQ_median', NaN, 'PairRelDeltaQ_q99', NaN, ...
        'PairRelDeltaQ_max', NaN, 'DeltaQ_max', NaN, ...
        'large_mismatch_count', 0, 'distinct_state_count', 0);
    tbl = struct2table(rec);
    audit = struct('count', 0, 'maxPairRel', NaN, 'maxDelta', NaN, ...
        'nearNumericalZero', true);
    return;
end
Tr = [double(zero.T_r1), double(zero.T_r2), ...
    double(zero.T_r3), double(zero.T_r4)];
Ts = [double(zero.T_s1), double(zero.T_s2), ...
    double(zero.T_s3), double(zero.T_s4)];
qTrR = double(zero.own_operating_loss_r);
qTrS = double(zero.cross_objective_r_to_s) - gamma .* sum(Tr, 2);
qTsR = double(zero.cross_objective_s_to_r) - gamma .* sum(Ts, 2);
qTsS = double(zero.own_operating_loss_s);
deltaTr = abs(qTrR - qTrS);
deltaTs = abs(qTsR - qTsS);
relTr = deltaTr ./ max([ones(height(zero), 1), abs(qTrR), abs(qTrS)], [], 2);
relTs = deltaTs ./ max([ones(height(zero), 1), abs(qTsR), abs(qTsS)], [], 2);
pairRel = max(relTr, relTs);
maxDelta = max([deltaTr; deltaTs]);
rec = struct('zero_distance_pair_count', height(zero), ...
    'PairRelDeltaQ_median', median(pairRel), ...
    'PairRelDeltaQ_q99', quantile(pairRel, 0.99), ...
    'PairRelDeltaQ_max', max(pairRel), 'DeltaQ_max', maxDelta, ...
    'large_mismatch_count', sum(pairRel >= config.largeMismatchThreshold), ...
    'distinct_state_count', numel(unique(double(zero.initial_state_id))));
tbl = struct2table(rec);
audit = struct('count', height(zero), 'maxPairRel', max(pairRel), ...
    'maxDelta', maxDelta, ...
    'nearNumericalZero', maxDelta <= config.chainTolerance + ...
        8 * eps(max([abs(qTrR); abs(qTrS); abs(qTsR); abs(qTsS); 1])));
end

function conclusion = choose_conclusion(group, states, pairs, replay, input, ~)
smallRows = pairs.small_distance_q25;
smallHigh = pairs.small_distance_high_fixed_loss;
smallCount = sum(smallRows);
smallHighCount = sum(smallHigh);
smallHighStates = numel(unique(pairs.initial_state_id(smallHigh)));
widespreadSmallHigh = smallHighStates >= 2 && ...
    smallHighCount >= max(3, ceil(0.25 * smallCount));
dataPass = input.identityPass && replay.allNewOptimal && ...
    replay.pathIdentityPass && replay.newFrozenTolerancePass;
if ~dataPass
    conclusion = "D. DATA_OR_REPLAY_INCONSISTENT";
elseif abs(group.stepTDifference) <= 0.10 + 1e-12 && ...
        abs(group.holdoutDifference) <= 0.10 + 1e-12 && ...
        ~widespreadSmallHigh
    conclusion = "A. CURRENT_DISTANCE_FIXED_LOSS_CONSISTENT";
elseif group.stepTDifference >= 0.20 - 1e-12 && ...
        group.holdoutDifference >= 0.20 - 1e-12 && ...
        states.directionConsistentStateCount >= 4
    conclusion = "C. CURRENT_DISTANCE_FIXED_LOSS_MISALIGNED";
else
    conclusion = "B. MIXED_FIXED_LOSS_EVIDENCE";
end
end

function [tbl, pass] = build_acceptance(pairs, slopes, states, input, ...
        replay, zeroAudit, protectedBefore, protectedAfter, stepPBefore, ...
        stepPAfter, codeMessages, runtimeSec, peakMemory, config)
checks = cell(21, 1);
checks{1} = check_record(1, input.pairCount == 36, input.pairCount, 36);
checks{2} = check_record(2, input.stepTCount == 24 && ...
    input.holdoutCount == 12, sprintf('%d/%d', input.stepTCount, ...
    input.holdoutCount), "24/12");
checks{3} = check_record(3, input.stepTReplayRows == 96, ...
    input.stepTReplayRows, 96);
checks{4} = check_record(4, replay.reusedReplayCount == 96, ...
    replay.reusedReplayCount, 96);
checks{5} = check_record(5, replay.newReplayCount == 48, ...
    replay.newReplayCount, 48);
checks{6} = check_record(6, replay.gurobiInvocationCount == 1, ...
    replay.gurobiInvocationCount, "1 batched recourse invocation");
checks{7} = check_record(7, replay.allNewOptimal, ...
    replay.allNewOptimal, true);
checks{8} = check_record(8, replay.pathIdentityPass, ...
    replay.pathIdentityPass, true);
checks{9} = check_record(9, replay.maxReusedFrozenError <= ...
    config.chainTolerance + 1e-7, replay.maxReusedFrozenError, ...
    "machine-aware frozen replay tolerance");
checks{10} = check_record(10, replay.newFrozenTolerancePass, ...
    replay.maxNewFrozenError, "machine-aware frozen replay tolerance");
checks{11} = check_record(11, replay.maxBalanceError <= ...
    config.chainTolerance, replay.maxBalanceError, config.chainTolerance);
checks{12} = check_record(12, replay.maxCapacityViolation <= ...
    config.chainTolerance, replay.maxCapacityViolation, config.chainTolerance);
checks{13} = check_record(13, height(pairs) == 36 && ...
    all(isfinite(pairs.PairRelDeltaQ)) && all(pairs.PairRelDeltaQ >= 0), ...
    height(pairs), "36 finite nonnegative pair rows");
checks{14} = check_record(14, height(slopes) == 5, height(slopes), 5);
checks{15} = check_record(15, height(states) == 6, height(states), 6);
checks{16} = check_record(16, zeroAudit.nearNumericalZero, ...
    zeroAudit.maxDelta, "near numerical zero");
checks{17} = check_record(17, isequal(protectedBefore, protectedAfter), ...
    "frozen inputs and protected source unchanged", "unchanged");
checks{18} = check_record(18, stepPBefore == stepPAfter, ...
    "Step-03P history unchanged", "unchanged");
checks{19} = check_record(19, isempty(codeMessages), numel(codeMessages), 0);
checks{20} = check_record(20, runtimeSec <= config.runtimeLimitSec, ...
    runtimeSec, config.runtimeLimitSec);
checks{21} = check_record(21, peakMemory > 0 && ...
    ~config.validationInputUsed && ~config.formalWdroUsed && ~config.mspUsed, ...
    peakMemory, "finite memory and no validation/formal WDRO/MSP");
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

function write_summary(path, pairs, slopeTbl, group, states, zeroAudit, ...
        replay, conclusion, smallThreshold, runtimeSec, peakMemory, pass, ~)
if pass
    status = "PASS";
else
    status = "FAIL";
end
stepTier = slopeTbl(slopeTbl.pair_group == "STEP03T_TIER1", :);
stepControl = slopeTbl(slopeTbl.pair_group == "STEP03T_CONTROL", :);
holdTier = slopeTbl(slopeTbl.pair_group == "HOLDOUT_TIER1", :);
holdControl = slopeTbl(slopeTbl.pair_group == "HOLDOUT_CONTROL", :);
smallHigh = pairs(pairs.small_distance_high_fixed_loss, :);
lines = [
    "Step-03W fixed-decision loss consistency audit"
    "status=" + status
    "conclusion=" + conclusion
    "fixed_operating_loss_definition=transport/service cost + shortage penalty; TerminalLOH holding cost excluded"
    "frozen_pair_count=" + height(pairs)
    "Step03T_reused_fixed_T_rows=" + replay.reusedReplayCount
    "new_holdout_fixed_T_recourse_evaluations=" + replay.newReplayCount
    "new_gurobi_batch_invocations=" + replay.gurobiInvocationCount
    sprintf('step03T_large_mismatch_share_tier1=%.9f', ...
        stepTier.large_mismatch_share)
    sprintf('step03T_large_mismatch_share_control=%.9f', ...
        stepControl.large_mismatch_share)
    sprintf('step03T_tier_minus_control_pp=%.6f', ...
        100 * group.stepTDifference)
    sprintf('holdout_large_mismatch_share_tier1=%.9f', ...
        holdTier.large_mismatch_share)
    sprintf('holdout_large_mismatch_share_control=%.9f', ...
        holdControl.large_mismatch_share)
    sprintf('holdout_tier_minus_control_pp=%.6f', ...
        100 * group.holdoutDifference)
    sprintf('states_with_tier_higher_large_mismatch=%d', ...
        states.directionConsistentStateCount)
    sprintf('small_distance_q25_threshold=%.15g', smallThreshold)
    sprintf('small_distance_high_fixed_loss_pair_count=%d', height(smallHigh))
    "small_distance_high_fixed_loss_states=" + ...
        join(string(unique(smallHigh.initial_state_id).'), ";")
    sprintf('zero_distance_cross_rows=%d', zeroAudit.count)
    sprintf('zero_distance_max_fixed_loss_difference=%.15g', ...
        zeroAudit.maxDelta)
    "1_close_distance_same_T_loss_close=" + ...
        interpret_close_loss(pairs, smallThreshold)
    "2_high_cross_regret_implies_fixed_loss_mismatch=" + ...
        interpret_regret(group)
    "3_representative_and_holdout_consistent=" + ...
        directional_consistency_text(group)
    "4_evidence_interpretation=" + evidence_text(conclusion)
    "5_reason_to_continue_distance_redesign=" + ...
        yes_no(conclusion ~= "A. CURRENT_DISTANCE_FIXED_LOSS_CONSISTENT")
    "6_reason_to_doubt_Wasserstein_framework_itself=NO; this audit tests the chosen ground cost against fixed-decision loss, not the optimal-transport framework."
    sprintf('max_reused_frozen_error=%.15g', replay.maxReusedFrozenError)
    sprintf('max_new_frozen_error=%.15g', replay.maxNewFrozenError)
    sprintf('runtime_sec=%.6f', runtimeSec)
    sprintf('peak_working_set_bytes=%.0f', peakMemory)
    "formal_distance_modified=NO"
    "formal_WDRO_MSP_validation_used=NO"
    ];
write_lines(path, lines);
end

function textValue = interpret_close_loss(pairs, threshold)
local = pairs(pairs.d_new <= threshold, :);
share = mean(local.large_fixed_loss_mismatch);
if share <= 0.10
    textValue = "YES; lowest-positive-distance quartile large-mismatch share=" + ...
        sprintf('%.6f', share);
elseif share >= 0.50
    textValue = "NO; lowest-positive-distance quartile large-mismatch share=" + ...
        sprintf('%.6f', share);
else
    textValue = "MIXED; lowest-positive-distance quartile large-mismatch share=" + ...
        sprintf('%.6f', share);
end
end

function textValue = interpret_regret(group)
if group.stepTDifference >= 0.20 && group.holdoutDifference >= 0.20
    textValue = "YES_IN_BOTH_SETS";
elseif group.stepTDifference > 0 || group.holdoutDifference > 0
    textValue = "PARTIAL_OR_SET_DEPENDENT";
else
    textValue = "NO_SYSTEMATIC_LINK";
end
end

function textValue = directional_consistency_text(group)
sameDirection = sign(group.stepTDifference) == sign(group.holdoutDifference);
bothStrong = group.stepTDifference >= 0.20 && group.holdoutDifference >= 0.20;
if sameDirection && bothStrong
    textValue = "YES_DIRECTIONALLY; both Tier-1 minus control gaps are at least 20 percentage points, although their magnitudes differ.";
elseif sameDirection
    textValue = "YES_DIRECTIONALLY_BUT_WEAK; the signs agree but at least one gap is below 20 percentage points.";
else
    textValue = "NO; representative and holdout directions differ.";
end
end

function textValue = evidence_text(conclusion)
if conclusion == "A. CURRENT_DISTANCE_FIXED_LOSS_CONSISTENT"
    textValue = "fixed-loss evidence supports the current distance; earlier cross-regret gate may be stronger than fixed-decision loss consistency.";
elseif conclusion == "B. MIXED_FIXED_LOSS_EVIDENCE"
    textValue = "evidence is mixed across frozen sets or states; neither a clean distance failure nor a clean consistency result is supported.";
elseif conclusion == "C. CURRENT_DISTANCE_FIXED_LOSS_MISALIGNED"
    textValue = "the chosen distance is systematically misaligned with fixed-decision operating-loss changes in both frozen sets.";
else
    textValue = "frozen data or replay consistency failed.";
end
end

function value = yes_no(flag)
if flag
    value = "YES";
else
    value = "NO";
end
end

function rho = rank_correlation(x, y)
rx = tied_rank(double(x(:)));
ry = tied_rank(double(y(:)));
if numel(rx) < 2 || std(rx) <= eps || std(ry) <= eps
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
    error('Step-03W cannot open %s.', path);
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
        error('Step-03W protected file missing: %s', paths(ii));
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
    error('Step-03W cannot open file for SHA-256: %s', path);
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
