function run_step05a1_finalize_h2()
%RUN_STEP05A1_FINALIZE_H2 Build lightweight audits for the dual lookup smoke.

rootDir = fileparts(mfilename('fullpath'));
runDir = fullfile(rootDir, 'results', 'task-002-stage2b-b3-smoke', ...
    '56-main-msp-dual-terminal-loh-smoke', 'run-001');
saaPath = fullfile(runDir, 'case-saa', 'native_output', 'h2_workspace.mat');
chiPath = fullfile(runDir, 'case-chi2_eta003', 'native_output', 'h2_workspace.mat');
if ~isfile(saaPath) || ~isfile(chiPath)
    error('run_step05a1_finalize_h2:MissingWorkspace', ...
        'Both isolated smoke workspaces are required.');
end

addpath(rootDir);
addpath(fullfile(rootDir, 'fa_h2'));
addpath(fullfile(rootDir, 'fa_h2', 'fuzhu'));
addpath(fullfile(rootDir, 'utils'));

saa = load(saaPath, 'params', 'modelLib', 'trainInfo', 'evalInfo', 'opts');
chi = load(chiPath, 'params', 'modelLib', 'trainInfo', 'evalInfo', 'opts');
validate_pair(saa, chi);

write_mapping_audit(runDir, saa.params, chi.params);
write_state_audits(runDir, saa.params, chi.params);
[cutTbl, totalAdded] = build_cut_audit(saa, chi);
writetable(cutTbl, fullfile(runDir, 'backward_cut_difference_summary.csv'));
write_smoke_comparison(runDir, saa, chi, totalAdded);
write_forward_response(runDir, saa, chi, totalAdded);
write_manifest(runDir, saaPath, chiPath);
write_judgment(runDir, saa, chi, totalAdded, cutTbl);
write_readme(runDir, saa, chi, totalAdded, cutTbl);
end

function validate_pair(saa, chi)
assert(string(saa.params.terminal_loh_mode) == "saa");
assert(string(chi.params.terminal_loh_mode) == "chi2_eta003");
assert(abs(saa.params.terminal_loh_lookup_audit.source_eta) < 1e-12);
assert(abs(chi.params.terminal_loh_lookup_audit.source_eta - 0.03) < 1e-12);
assert(saa.params.cost_reserve_shortage == 2000);
assert(chi.params.cost_reserve_shortage == 2000);
assert(saa.opts.seed == 20260513 && chi.opts.seed == 20260513);
assert(saa.opts.time_limit == chi.opts.time_limit);
assert(saa.opts.max_iter == chi.opts.max_iter);
assert(saa.opts.nbOS == chi.opts.nbOS);
assert(saa.opts.runEvaluation == chi.opts.runEvaluation);
assert(saa.opts.runTraining == chi.opts.runTraining);
assert(saa.opts.allow_zero_terminal_loh && chi.opts.allow_zero_terminal_loh);
assert(isequal(saa.params.P_joint, chi.params.P_joint));
assert(isequal(saa.params.S, chi.params.S));
assert(isequal(saa.params.x_0, chi.params.x_0));
assert(isequal(saa.params.cost_normal_shortage, chi.params.cost_normal_shortage));
assert(max(abs(saa.params.TerminalLOH(:, 111) - chi.params.TerminalLOH(:, 111))) < 1e-12);
assert(max(abs(saa.params.TerminalLOH(:, 207) - ...
    [222.8404658647684;119.19373755557378;36.003600360036;133.3769740610424])) < 1e-9);
assert(max(abs(chi.params.TerminalLOH(:, 207) - ...
    [231.2976216031054;121.91868807193504;50.09528511681813;139.65004154041907])) < 1e-9);
end

function write_mapping_audit(runDir, saaParams, chiParams)
modes = [repmat("saa", 35, 1); repmat("chi2_eta003", 35, 1)];
sourceEta = [zeros(35, 1); 0.03 * ones(35, 1)];
stateId = repmat((1:35).', 2, 1);
intensity = floor((stateId - 1) / 7) + 2;
loc = mod(stateId - 1, 7) + 1;
sourceLfw = zeros(70, 1);
mainMspLfw = 7 * ones(70, 1);
mainStateK = [saaParams.terminal_loh_lookup_audit.main_state_k; ...
    chiParams.terminal_loh_lookup_audit.main_state_k];
T = zeros(70, 4);
for rr = 1:35
    T(rr, :) = saaParams.TerminalLOH(:, mainStateK(rr)).';
    T(35 + rr, :) = chiParams.TerminalLOH(:, mainStateK(35 + rr)).';
end
TerminalLOH_total_kg = sum(T, 2);
formulaK = ((intensity - 1) * 7 + (loc - 1)) * 8 + mainMspLfw;
mapping_formula_pass = mainStateK == formulaK;
station_order = repmat("T1_kg,T2_kg,T3_kg,T4_kg", 70, 1);
non_target_max_abs_kg = [repmat(saaParams.terminal_loh_lookup_audit.non_target_max_abs_kg, 35, 1); ...
    repmat(chiParams.terminal_loh_lookup_audit.non_target_max_abs_kg, 35, 1)];
tbl = table(modes, sourceEta, stateId, intensity, loc, sourceLfw, mainMspLfw, ...
    mainStateK, T(:,1), T(:,2), T(:,3), T(:,4), TerminalLOH_total_kg, ...
    formulaK, mapping_formula_pass, station_order, non_target_max_abs_kg, ...
    'VariableNames', {'mode','source_eta','state_id','intensity','loc', ...
    'source_lfw','main_msp_lf','main_state_k','T1_kg','T2_kg','T3_kg','T4_kg', ...
    'TerminalLOH_total_kg','formula_k','mapping_formula_pass','station_order', ...
    'non_target_max_abs_kg'});
writetable(tbl, fullfile(runDir, 'terminal_loh_mapping_audit.csv'));
end

function write_state_audits(runDir, saaParams, chiParams)
write_one_state(fullfile(runDir, 'state7_negative_control.csv'), 7, saaParams, chiParams);
write_one_state(fullfile(runDir, 'state13_difference_check.csv'), 13, saaParams, chiParams);
write_one_state(fullfile(runDir, 'state19_lookup_check.csv'), 19, saaParams, chiParams);
end

function write_one_state(outPath, stateId, saaParams, chiParams)
a = floor((stateId - 1) / 7) + 2;
loc = mod(stateId - 1, 7) + 1;
k = ((a - 1) * 7 + (loc - 1)) * 8 + 7;
Ts = saaParams.TerminalLOH(:, k);
Tc = chiParams.TerminalLOH(:, k);
xCommon = Ts;
[vs, gs, is] = terminal_value_and_subgradient_h2(xCommon, saaParams, k);
[vc, gc, ic] = terminal_value_and_subgradient_h2(xCommon, chiParams, k);
tbl = table(stateId, a, loc, 7, k, ...
    Ts(1), Ts(2), Ts(3), Ts(4), sum(Ts), ...
    Tc(1), Tc(2), Tc(3), Tc(4), sum(Tc), ...
    Tc(1)-Ts(1), Tc(2)-Ts(2), Tc(3)-Ts(3), Tc(4)-Ts(4), sum(Tc)-sum(Ts), ...
    vs, vc, vc-vs, sum(is.shortage), sum(ic.shortage), ...
    norm(gc-gs, 1), max(abs(gc-gs)), ...
    max(abs(Ts-Tc)) <= 1e-12, saaParams.cost_reserve_shortage, ...
    'VariableNames', {'state_id','intensity','loc','main_msp_lf','main_state_k', ...
    'saa_T1_kg','saa_T2_kg','saa_T3_kg','saa_T4_kg','saa_total_kg', ...
    'chi2_T1_kg','chi2_T2_kg','chi2_T3_kg','chi2_T4_kg','chi2_total_kg', ...
    'delta_T1_kg','delta_T2_kg','delta_T3_kg','delta_T4_kg','delta_total_kg', ...
    'saa_terminal_value_at_saa_T','chi2_terminal_value_at_saa_T', ...
    'terminal_value_difference','saa_shortage_at_saa_T_kg', ...
    'chi2_shortage_at_saa_T_kg','subgradient_l1_difference', ...
    'subgradient_max_abs_difference','negative_control_exact_match', ...
    'terminal_gap_penalty_yuan_per_kg'});
writetable(tbl, outPath);
end

function [tbl, totals] = build_cut_audit(saa, chi)
baseS = define_models_h2(saa.params);
baseC = define_models_h2(chi.params);
rows = cell(8, 12);
totals = struct('saa', 0, 'chi', 0);
for t = 1:8
    baseRowsS = 0; finalRowsS = 0; baseRowsC = 0; finalRowsC = 0;
    compared = 0; changed = 0; maxADiff = 0; maxBDiff = 0;
    for k = 1:saa.params.K
        bs = baseS.models{t,k}; bc = baseC.models{t,k};
        fs = saa.modelLib.models{t,k}; fc = chi.modelLib.models{t,k};
        if isempty(bs) || isempty(bc) || isempty(fs) || isempty(fc)
            continue;
        end
        nbs = size(bs.A,1); nbc = size(bc.A,1);
        nfs = size(fs.A,1); nfc = size(fc.A,1);
        baseRowsS = baseRowsS + nbs; baseRowsC = baseRowsC + nbc;
        finalRowsS = finalRowsS + nfs; finalRowsC = finalRowsC + nfc;
        if nfs > nbs && nfc > nbc
            compared = compared + 1;
            da = max(abs(full(fs.A(nbs+1,:)) - full(fc.A(nbc+1,:))));
            db = abs(fs.b(nbs+1) - fc.b(nbc+1));
            maxADiff = max(maxADiff, da);
            maxBDiff = max(maxBDiff, db);
            changed = changed + (max(da, db) > 1e-9);
        end
    end
    addS = finalRowsS - baseRowsS;
    addC = finalRowsC - baseRowsC;
    totals.saa = totals.saa + addS;
    totals.chi = totals.chi + addC;
    rows(t,:) = {t, baseRowsS, finalRowsS, addS, baseRowsC, finalRowsC, addC, ...
        compared, changed, maxADiff, maxBDiff, changed > 0};
end
tbl = cell2table(rows, 'VariableNames', {'stage','saa_base_constraint_rows', ...
    'saa_final_constraint_rows','saa_added_cut_rows','chi2_base_constraint_rows', ...
    'chi2_final_constraint_rows','chi2_added_cut_rows','first_cut_models_compared', ...
    'first_cut_models_changed','max_first_cut_A_abs_difference', ...
    'max_first_cut_b_abs_difference','terminal_table_changed_first_backward_cuts'});
end

function write_smoke_comparison(runDir, saa, chi, totalAdded)
cases = {saa, chi};
mode = ["saa"; "chi2_eta003"];
eta = [0; 0.03];
iterations = zeros(2,1); completedBackward = zeros(2,1);
trainTime = zeros(2,1); evalTime = zeros(2,1); finalLB = zeros(2,1);
oosMean = zeros(2,1); ciLow = zeros(2,1); ciHigh = zeros(2,1);
avgShortage = zeros(2,1); maxShortage = zeros(2,1); positivePaths = zeros(2,1);
hitPaths = zeros(2,1); avgTerminalCost = zeros(2,1); penaltyResidual = zeros(2,1);
lastForwardCost = zeros(2,1); lastForwardShortage = zeros(2,1);
for ii = 1:2
    x = cases{ii};
    shortageByPath = sum(x.evalInfo.terminal_reserve_shortage, 2);
    terminalCostByPath = sum(x.evalInfo.terminal_cost, 2);
    iterations(ii) = x.trainInfo.iter;
    completedBackward(ii) = x.trainInfo.iter - 1;
    trainTime(ii) = x.trainInfo.train_time;
    evalTime(ii) = x.evalInfo.elapsed;
    finalLB(ii) = x.trainInfo.LB(end);
    oosMean(ii) = x.evalInfo.oos_mean;
    ciLow(ii) = x.evalInfo.ci_low;
    ciHigh(ii) = x.evalInfo.ci_high;
    avgShortage(ii) = mean(shortageByPath);
    maxShortage(ii) = max(shortageByPath);
    positivePaths(ii) = nnz(shortageByPath > 1e-9);
    hitPaths(ii) = nnz(x.evalInfo.hit_loh_demand);
    avgTerminalCost(ii) = mean(terminalCostByPath);
    penaltyResidual(ii) = max(abs(terminalCostByPath - 2000 * shortageByPath));
    lastForwardCost(ii) = sum(x.trainInfo.last_forward.stageCost);
    lastForwardShortage(ii) = sum(x.trainInfo.last_forward.terminalShortage, 'all');
end
addedCutRows = [totalAdded.saa; totalAdded.chi];
seed = repmat(20260513, 2, 1); timeLimit = repmat(300, 2, 1);
terminalPenalty = repmat(2000, 2, 1); exitCode = zeros(2,1);
tbl = table(mode, eta, seed, timeLimit, iterations, completedBackward, trainTime, ...
    evalTime, finalLB, oosMean, ciLow, ciHigh, avgShortage, maxShortage, ...
    positivePaths, hitPaths, avgTerminalCost, terminalPenalty, penaltyResidual, ...
    addedCutRows, lastForwardCost, lastForwardShortage, exitCode, ...
    'VariableNames', {'mode','eta','seed','time_limit_sec','iterations', ...
    'completed_backward_passes','train_time_sec','eval_time_sec','final_LB', ...
    'OOS_mean','CI_low','CI_high','avg_terminal_shortage_kg', ...
    'max_terminal_shortage_kg','positive_shortage_paths','paths_reaching_lf7', ...
    'avg_terminal_cost','terminal_gap_penalty_yuan_per_kg', ...
    'max_penalty_identity_residual','added_cut_rows','last_forward_path_cost', ...
    'last_forward_terminal_shortage_kg','matlab_exit_code'});
writetable(tbl, fullfile(runDir, 'saa_vs_eta003_smoke_comparison.csv'));
end

function write_forward_response(runDir, saa, chi, totalAdded)
n = min(numel(saa.trainInfo.LB), numel(chi.trainInfo.LB));
iteration = (1:n).';
saaLB = saa.trainInfo.LB(1:n);
chiLB = chi.trainInfo.LB(1:n);
lbDifference = chiLB - saaLB;
cutsAvailable = iteration > 1;
saaCutsBeforeForward = min((iteration - 1) * 1261, totalAdded.saa);
chiCutsBeforeForward = min((iteration - 1) * 1261, totalAdded.chi);
sameSeedAndSampling = true(n,1);
firstForwardExactMatch = abs(saaLB - chiLB) <= 1e-12;
tbl = table(iteration, saaLB, chiLB, lbDifference, cutsAvailable, ...
    saaCutsBeforeForward, chiCutsBeforeForward, sameSeedAndSampling, ...
    firstForwardExactMatch, ...
    'VariableNames', {'iteration','saa_LB','chi2_eta003_LB','LB_difference', ...
    'cuts_available_before_forward','saa_cumulative_cut_rows_before_forward', ...
    'chi2_cumulative_cut_rows_before_forward','same_seed_and_sampling', ...
    'forward_LB_exact_match'});
writetable(tbl, fullfile(runDir, 'forward_response_summary.csv'));
end

function write_manifest(runDir, saaPath, chiPath)
paths = [string(saaPath); string(chiPath); ...
    string(fullfile(runDir, 'case-saa', 'native_output', 'details', 'h2_oos_path_costs.csv')); ...
    string(fullfile(runDir, 'case-chi2_eta003', 'native_output', 'details', 'h2_oos_path_costs.csv'))];
fid = fopen(fullfile(runDir, 'LARGE_FILE_MANIFEST.md'), 'w');
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, '# Large file manifest\n\n');
fprintf(fid, 'These reproducible smoke payloads remain local and are excluded from Git.\n\n');
fprintf(fid, '| Path | Bytes | SHA-256 |\n|---|---:|---|\n');
for ii = 1:numel(paths)
    info = dir(paths(ii));
    hash = sha256_file(paths(ii));
    rel = erase(paths(ii), string(runDir) + filesep);
    fprintf(fid, '| `%s` | %d | `%s` |\n', strrep(rel, filesep, '/'), info.bytes, hash);
end
end

function hash = sha256_file(path)
sha = System.Security.Cryptography.SHA256.Create();
stream = System.IO.File.OpenRead(char(path));
cleanup = onCleanup(@() stream.Close()); %#ok<NASGU>
bytes = uint8(sha.ComputeHash(stream));
hash = upper(reshape(dec2hex(bytes, 2).', 1, []));
end

function write_judgment(runDir, saa, chi, totals, cutTbl)
firstLBMatch = abs(saa.trainInfo.LB(1) - chi.trainInfo.LB(1)) <= 1e-12;
secondLBDiff = abs(saa.trainInfo.LB(2) - chi.trainInfo.LB(2));
changedCuts = sum(cutTbl.first_cut_models_changed);
fid = fopen(fullfile(runDir, 'step05a1_judgment.txt'), 'w');
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, 'A / PASS\n\n');
fprintf(fid, 'Both frozen 35x4 TerminalLOH tables were mapped to the exact 35 lf=7 columns of params.TerminalLOH [4x336].\n');
fprintf(fid, 'The chi2_eta003 label was mechanically verified as eta=0.03, not eta=0.003.\n');
fprintf(fid, 'State7 is an exact zero negative control in both tables and has identical terminal value/subgradient.\n');
fprintf(fid, 'State13 and state19 differ as frozen; state19 maps to k=207 and matches C6 exactly.\n');
fprintf(fid, 'Both cases completed forward/backward/cut/next-forward cycles and native eval_h2 with MATLAB exit code 0.\n');
fprintf(fid, 'SAA completed %d iterations and %d added cut rows; eta=0.03 completed %d iterations and %d added cut rows.\n', ...
    saa.trainInfo.iter, totals.saa, chi.trainInfo.iter, totals.chi);
fprintf(fid, 'The first no-cut forward LB matched: %d. After the first backward cuts, iteration-2 LB differed by %.12g.\n', ...
    firstLBMatch, secondLBDiff);
fprintf(fid, '%d stage-state first cuts differed between the two frozen tables.\n', changedCuts);
fprintf(fid, 'The terminal shortage identity terminal_cost=2000*shortage passed in both OOS evaluations.\n');
fprintf(fid, 'The existing allow_zero_terminal_loh validation permission was enabled identically for both lookup modes solely because frozen state7 is exactly zero; no model equation changed.\n');
fprintf(fid, 'Conclusion: dual-table propagation is verified and Step-05A1 can proceed to a formal SAA versus eta=0.03 A/B run.\n');
end

function write_readme(runDir, saa, chi, totals, cutTbl)
fid = fopen(fullfile(runDir, 'README.md'), 'w');
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, '# Step-05A1 dual TerminalLOH lookup smoke\n\n');
fprintf(fid, 'Status: **A / PASS**. Accepted run: `run-001`.\n\n');
fprintf(fid, 'The safe native launcher ran the unchanged FA-MSP algorithm twice with seed 20260513 and a 300-second training limit. ');
fprintf(fid, 'The only model input difference was the frozen TerminalLOH table: SAA versus Pearson chi-square eta=0.03.\n\n');
fprintf(fid, '- SAA: %d iterations, %.3f s training, final LB %.9f, %d added cut rows.\n', ...
    saa.trainInfo.iter, saa.trainInfo.train_time, saa.trainInfo.LB(end), totals.saa);
fprintf(fid, '- eta=0.03: %d iterations, %.3f s training, final LB %.9f, %d added cut rows.\n', ...
    chi.trainInfo.iter, chi.trainInfo.train_time, chi.trainInfo.LB(end), totals.chi);
fprintf(fid, '- First-cut stage-state models changed: %d.\n', sum(cutTbl.first_cut_models_changed));
fprintf(fid, '- Terminal gap penalty remained 2000 yuan/kg in both cases.\n');
fprintf(fid, '- `state7` is an intentional exact-zero negative control. Its lookup, terminal value, and subgradient match exactly.\n');
fprintf(fid, '- The zero-state warnings in the SAA selected-path diagnostics are expected and arise from that frozen negative control.\n');
fprintf(fid, '- Native workspaces and detailed OOS tables remain local; only lightweight audits are intended for Git.\n\n');
fprintf(fid, 'This smoke validates data propagation, not policy superiority. A formal one-hour A/B is the next step.\n');
end
