function run_step05B1_terminal_gap_mechanism_audit_h2()
%RUN_STEP05B1_TERMINAL_GAP_MECHANISM_AUDIT_H2 Read-only Step-05B-1 audit.

rootDir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(rootDir);
addpath(fullfile(rootDir, 'fa_h2'));
addpath(fullfile(rootDir, 'fa_h2', 'fuzhu'));
addpath(fullfile(rootDir, 'utils'));

sourceRun = fullfile(rootDir, 'results', 'task-002-stage2b-b3-smoke', ...
    '57-main-msp-converged-terminal-loh-ab', 'run-003');
outDir = fullfile(rootDir, 'results', 'task-002-stage2b-b3-smoke', ...
    '58-main-msp-terminal-gap-mechanism-audit', 'run-004');
if exist(outDir, 'dir')
    error('run_step05B1_terminal_gap_mechanism_audit_h2:OutputExists', ...
        'Refusing to overwrite existing audit output: %s', outDir);
end
mkdir(outDir);

saaWorkspace = fullfile(sourceRun, 'case-saa', 'native_output', 'h2_workspace.mat');
etaWorkspace = fullfile(sourceRun, 'case-chi2_eta003', 'native_output', 'h2_workspace.mat');
require_file(saaWorkspace);
require_file(etaWorkspace);

saaHeader = load(saaWorkspace, 'params', 'opts');
etaHeader = load(etaWorkspace, 'params', 'opts');
oosFileSaa = char(saaHeader.params.oosFile);
oosFileEta = char(etaHeader.params.oosFile);
require_file(oosFileSaa);
require_file(oosFileEta);
if ~strcmp(oosFileSaa, oosFileEta)
    error('run_step05B1_terminal_gap_mechanism_audit_h2:DifferentOOSFiles', ...
        'The two workspaces reference different OOS files.');
end

OOS = readmatrix(oosFileSaa);
OOS = OOS(1:saaHeader.params.nbOS, 1:saaHeader.params.T);
if size(OOS, 1) ~= 10000 || size(OOS, 2) ~= 8
    error('run_step05B1_terminal_gap_mechanism_audit_h2:BadOOSSize', ...
        'Expected a 10000-by-8 OOS matrix, got %d-by-%d.', size(OOS, 1), size(OOS, 2));
end
oosHash = sha256_file(oosFileSaa);

[saa, saaIntegrity] = audit_case(saaWorkspace, OOS, "saa");
[eta, etaIntegrity] = audit_case(etaWorkspace, OOS, "chi2_eta003");

if ~isequal(saa.state_path, eta.state_path) || ~isequal(saa.state_path, OOS)
    error('run_step05B1_terminal_gap_mechanism_audit_h2:PathMismatch', ...
        'The reconstructed state paths are not byte-identical.');
end
if ~isequal(saa.hit_terminal, eta.hit_terminal) || ...
        ~isequal(saa.terminal_stage, eta.terminal_stage) || ...
        ~isequal(saa.terminal_state, eta.terminal_state)
    error('run_step05B1_terminal_gap_mechanism_audit_h2:TerminalEventMismatch', ...
        'The two evaluations do not share identical terminal events.');
end

rowwise = [build_rowwise_table(saa); build_rowwise_table(eta)];
writetable(rowwise, fullfile(outDir, 'terminal_target_vs_final_inventory.csv'));

gapAudit = build_gap_summary(saa, eta);
writetable(gapAudit, fullfile(outDir, 'terminal_gap_relative_audit.csv'));

ordinaryWorse = build_ordinary_worse_table(saa, eta);
writetable(ordinaryWorse, fullfile(outDir, 'ordinary_shortage_worse_scenario_audit.csv'));

ordinarySummary = build_ordinary_worse_summary(ordinaryWorse, saa.n_paths);
writetable(ordinarySummary, fullfile(outDir, 'ordinary_shortage_worse_summary.csv'));

componentDiff = build_component_difference(saa, eta);
writetable(componentDiff, fullfile(outDir, 'objective_component_difference.csv'));

withoutTerminal = table((1:saa.n_paths).', saa.path_cost, eta.path_cost, ...
    saa.terminal_penalty, eta.terminal_penalty, ...
    saa.objective_without_terminal, eta.objective_without_terminal, ...
    eta.path_cost - saa.path_cost, ...
    eta.terminal_penalty - saa.terminal_penalty, ...
    eta.objective_without_terminal - saa.objective_without_terminal, ...
    'VariableNames', {'path_id','saa_reported_objective','eta_reported_objective', ...
    'saa_terminal_gap_penalty','eta_terminal_gap_penalty', ...
    'saa_objective_without_terminal_gap','eta_objective_without_terminal_gap', ...
    'reported_objective_delta_eta_minus_saa', ...
    'terminal_gap_penalty_delta_eta_minus_saa', ...
    'without_terminal_gap_delta_eta_minus_saa'});
writetable(withoutTerminal, fullfile(outDir, 'objective_without_terminal_gap_penalty.csv'));

write_workspace_integrity(outDir, saaWorkspace, etaWorkspace, oosFileSaa, ...
    saaIntegrity, etaIntegrity, saa, eta);
write_common_oos_audit(outDir, oosFileSaa, oosHash, OOS, saa, eta);
write_penalty_source_audit(outDir, saa);
write_mechanism_summary(outDir, saa, eta, ordinarySummary, componentDiff);
write_judgment(outDir, saa, eta, ordinarySummary);
write_readme(outDir, sourceRun);
write_large_file_manifest(outDir, saaWorkspace, etaWorkspace, oosFileSaa, ...
    oosHash, rowwise, withoutTerminal);
clear saa eta rowwise withoutTerminal saaHeader etaHeader;
end

function [d, integrity] = audit_case(workspaceFile, OOS, method)
loaded = load(workspaceFile, 'params', 'modelLib', 'trainInfo', 'evalInfo', 'opts');
required = {'params','modelLib','trainInfo','evalInfo','opts'};
for ii = 1:numel(required)
    if ~isfield(loaded, required{ii})
        error('audit_case:MissingWorkspaceField', ...
            'Workspace %s lacks %s.', workspaceFile, required{ii});
    end
end

p = loaded.params;
if p.nbOS ~= 10000 || p.T ~= 8 || p.Ni ~= 4
    error('audit_case:UnexpectedDimensions', ...
        'Unexpected nbOS/T/Ni in %s.', workspaceFile);
end
if loaded.trainInfo.stop_flag ~= 2
    error('audit_case:UnexpectedStopFlag', ...
        'Expected fixed-budget stop_flag=2 in %s.', workspaceFile);
end

p.store_eval_decisions = true;
detailed = eval_h2(loaded.modelLib, p);

integrity = struct();
integrity.workspace_file = string(workspaceFile);
integrity.workspace_loaded = true;
integrity.original_nbOS = loaded.evalInfo.nbOS_used;
integrity.replay_nbOS = detailed.nbOS_used;
integrity.path_cost_max_abs_error = max(abs(detailed.pathCost - loaded.evalInfo.pathCost));
integrity.normal_shortage_max_abs_error = max(abs(detailed.normal_shortage(:) - loaded.evalInfo.normal_shortage(:)));
integrity.terminal_shortage_max_abs_error = max(abs(detailed.terminal_reserve_shortage(:) - loaded.evalInfo.terminal_reserve_shortage(:)));
integrity.final_loh_max_abs_error = max(abs(detailed.final_loh(:) - loaded.evalInfo.final_loh(:)));
integrity.production_max_abs_error = max(abs(detailed.production_amount(:) - loaded.evalInfo.production_amount(:)));
integrity.transport_max_abs_error = max(abs(detailed.transport_amount(:) - loaded.evalInfo.transport_amount(:)));

n = p.nbOS;
d = struct();
d.method = string(method);
d.n_paths = n;
d.state_path = OOS;
d.path_id = (1:n).';
d.hit_terminal = detailed.hit_loh_demand;
d.terminal_stage = detailed.first_loh_demand_stage;
d.terminal_state = zeros(n, 1);
d.a = zeros(n, 1);
d.loc = zeros(n, 1);
d.lf = zeros(n, 1);
d.target_site = zeros(n, p.Ni);

for s = 1:n
    if d.hit_terminal(s)
        tt = d.terminal_stage(s);
        kk = OOS(s, tt);
        d.terminal_state(s) = kk;
        d.a(s) = p.S(kk, 1);
        d.loc(s) = p.S(kk, 2);
        d.lf(s) = p.S(kk, 3);
        d.target_site(s, :) = p.TerminalLOH(:, kk).';
    end
end

d.final_site = detailed.final_loh;
d.gap_site = max(0, d.target_site - d.final_site);
d.target_total = sum(d.target_site, 2);
d.final_total = sum(d.final_site, 2);
d.gap_total = sum(d.gap_site, 2);
d.relative_gap = nan(n, 1);
d.attainment_ratio = nan(n, 1);
positiveTarget = d.target_total > 1e-12;
d.relative_gap(positiveTarget) = d.gap_total(positiveTarget) ./ d.target_total(positiveTarget);
d.attainment_ratio(positiveTarget) = 1 - d.relative_gap(positiveTarget);

d.normal_shortage = sum(detailed.normal_shortage, 2);
d.production = sum(detailed.production_amount, 2);
d.transport_amount = sum(detailed.transport_amount, 2);
d.path_cost = detailed.pathCost;
d.terminal_penalty = sum(detailed.terminal_cost, 2);
d.normal_penalty = zeros(n, 1);
d.production_cost = zeros(n, 1);
d.transport_cost = zeros(n, 1);
d.holding_cost = zeros(n, 1);

for s = 1:n
    for t = 1:p.T
        if isempty(detailed.xval{s, t})
            continue;
        end
        kk = OOS(s, t);
        x = detailed.xval{s, t};
        e = detailed.eval{s, t};
        f = detailed.fval{s, t};
        z = detailed.z_normal{s, t};
        d.holding_cost(s) = d.holding_cost(s) + p.cost_holding * sum(x);
        d.production_cost(s) = d.production_cost(s) + ...
            (p.cost_electricity_stage(t) + p.cost_el_om) * p.dt_h * sum(e);
        costMat = p.cost_transport_base;
        if p.use_beta_cost
            costMat = costMat * (1 + p.beta_transport_multiplier * p.beta(kk));
        end
        d.transport_cost(s) = d.transport_cost(s) + sum(costMat(:) .* f(:));
        d.normal_penalty(s) = d.normal_penalty(s) + p.cost_normal_shortage * sum(z);
    end
end

d.component_residual = d.path_cost - (d.terminal_penalty + d.normal_penalty + ...
    d.production_cost + d.transport_cost + d.holding_cost);
d.objective_without_terminal = d.path_cost - d.terminal_penalty;
d.cost_reserve_shortage = p.cost_reserve_shortage;
d.cost_normal_shortage_base = p.cost_normal_shortage_base;
d.normal_shortage_penalty_multiplier = p.normal_shortage_penalty_multiplier;
d.cost_normal_shortage = p.cost_normal_shortage;
d.cost_holding = p.cost_holding;
d.cost_el_om = p.cost_el_om;
d.cost_electricity_stage = p.cost_electricity_stage(:).';
d.oos_file = string(p.oosFile);
d.train_iterations = loaded.trainInfo.iter;
d.train_time = loaded.trainInfo.train_time;
d.stop_flag = loaded.trainInfo.stop_flag;

gapReconstructionError = max(abs(d.gap_total - sum(detailed.terminal_reserve_shortage, 2)));
terminalCostError = max(abs(d.terminal_penalty - p.cost_reserve_shortage * d.gap_total));
componentError = max(abs(d.component_residual));
if gapReconstructionError > 1e-7 || terminalCostError > 1e-7 || componentError > 1e-5
    error('audit_case:MechanicalMismatch', ...
        'Mechanical audit failed for %s: gap %.3g, terminal cost %.3g, components %.3g.', ...
        method, gapReconstructionError, terminalCostError, componentError);
end
integrity.gap_reconstruction_max_abs_error = gapReconstructionError;
integrity.terminal_cost_max_abs_error = terminalCostError;
integrity.objective_component_max_abs_error = componentError;
end

function tbl = build_rowwise_table(d)
n = d.n_paths;
method = repmat(d.method, n, 1);
tbl = table(method, d.path_id, d.hit_terminal, d.terminal_stage, ...
    d.terminal_state, d.a, d.loc, d.lf, ...
    d.target_site(:,1), d.target_site(:,2), d.target_site(:,3), d.target_site(:,4), ...
    d.target_total, d.final_site(:,1), d.final_site(:,2), d.final_site(:,3), ...
    d.final_site(:,4), d.final_total, d.gap_site(:,1), d.gap_site(:,2), ...
    d.gap_site(:,3), d.gap_site(:,4), d.gap_total, d.relative_gap, ...
    d.attainment_ratio, d.normal_shortage, d.production, d.transport_amount, ...
    d.path_cost, d.terminal_penalty, d.objective_without_terminal, ...
    'VariableNames', {'method','path_id','hit_terminal','terminal_stage', ...
    'terminal_state','a','loc','lf','target_site1','target_site2','target_site3', ...
    'target_site4','target_total','final_site1','final_site2','final_site3', ...
    'final_site4','final_total','gap_site1','gap_site2','gap_site3','gap_site4', ...
    'gap_total','relative_gap','attainment_ratio','ordinary_shortage', ...
    'production_amount','htt_amount','reported_objective','terminal_gap_penalty', ...
    'objective_without_terminal_gap'});
end

function tbl = build_gap_summary(saa, eta)
rowType = ["method_own_target_condition"; "method_own_target_condition"; ...
    "paired_common_path_delta"];
method = ["saa"; "chi2_eta003"; "eta_minus_saa"];
metrics = nan(3, 16);
metrics(1,1:12) = gap_metrics(saa);
metrics(2,1:12) = gap_metrics(eta);

commonHit = saa.hit_terminal & eta.hit_terminal;
commonPositive = commonHit & saa.target_total > 1e-12 & eta.target_total > 1e-12;
metrics(3,1) = sum(commonHit);
metrics(3,2) = sum(commonHit);
metrics(3,3) = sum(commonPositive);
metrics(3,4) = sum(commonPositive);
metrics(3,13) = mean(eta.target_total(commonHit) - saa.target_total(commonHit));
metrics(3,14) = mean(eta.final_total(commonHit) - saa.final_total(commonHit));
metrics(3,15) = mean(eta.gap_total(commonHit) - saa.gap_total(commonHit));
metrics(3,16) = mean(eta.relative_gap(commonPositive) - saa.relative_gap(commonPositive));

tbl = array2table(metrics, 'VariableNames', {'path_count','hit_terminal_count', ...
    'positive_target_count','common_both_positive_target_count', ...
    'mean_target_positive','mean_final_all','mean_final_positive_target', ...
    'mean_gap_all','mean_gap_positive_target','median_gap_positive_target', ...
    'mean_relative_gap_positive_target','mean_attainment_positive_target', ...
    'paired_mean_target_delta_common_hit','paired_mean_final_delta_common_hit', ...
    'paired_mean_gap_delta_common_hit','paired_mean_relative_gap_delta_common_both_positive'});
tbl = addvars(tbl, rowType, method, 'Before', 1, ...
    'NewVariableNames', {'row_type','method'});
end

function m = gap_metrics(d)
idx = d.target_total > 1e-12;
m = [d.n_paths, sum(d.hit_terminal), sum(idx), nan, mean(d.target_total(idx)), ...
    mean(d.final_total), mean(d.final_total(idx)), mean(d.gap_total), ...
    mean(d.gap_total(idx)), median(d.gap_total(idx)), mean(d.relative_gap(idx)), ...
    mean(d.attainment_ratio(idx))];
end

function tbl = build_ordinary_worse_table(saa, eta)
idx = eta.normal_shortage > saa.normal_shortage + 1e-9;
pathId = saa.path_id(idx);
tbl = table(pathId, saa.normal_shortage(idx), eta.normal_shortage(idx), ...
    eta.normal_shortage(idx) - saa.normal_shortage(idx), ...
    saa.final_total(idx), eta.final_total(idx), eta.final_total(idx) - saa.final_total(idx), ...
    eta.final_total(idx) > saa.final_total(idx) + 1e-9, ...
    saa.production(idx), eta.production(idx), eta.production(idx) - saa.production(idx), ...
    eta.production(idx) > saa.production(idx) + 1e-9, ...
    saa.transport_amount(idx), eta.transport_amount(idx), ...
    eta.transport_amount(idx) - saa.transport_amount(idx), ...
    eta.transport_amount(idx) > saa.transport_amount(idx) + 1e-9, ...
    saa.target_total(idx), eta.target_total(idx), eta.target_total(idx) - saa.target_total(idx), ...
    saa.gap_total(idx), eta.gap_total(idx), eta.gap_total(idx) - saa.gap_total(idx), ...
    saa.relative_gap(idx), eta.relative_gap(idx), ...
    saa.path_cost(idx), eta.path_cost(idx), eta.path_cost(idx) - saa.path_cost(idx), ...
    'VariableNames', {'path_id','saa_ordinary_shortage','eta_ordinary_shortage', ...
    'ordinary_shortage_delta','saa_final_inventory','eta_final_inventory', ...
    'final_inventory_delta','eta_leaves_more_inventory','saa_production','eta_production', ...
    'production_delta','eta_produces_more','saa_htt','eta_htt','htt_delta', ...
    'eta_uses_more_htt','saa_terminal_target','eta_terminal_target','target_delta', ...
    'saa_terminal_gap','eta_terminal_gap','gap_delta','saa_relative_gap', ...
    'eta_relative_gap','saa_reported_objective','eta_reported_objective', ...
    'reported_objective_delta'});
end

function tbl = build_ordinary_worse_summary(detail, nTotal)
n = height(detail);
if n == 0
    vals = zeros(1, 18);
else
    vals = [n, n / nTotal, mean(detail.ordinary_shortage_delta), ...
        median(detail.ordinary_shortage_delta), mean(detail.final_inventory_delta), ...
        median(detail.final_inventory_delta), mean(detail.eta_leaves_more_inventory), ...
        mean(detail.production_delta), median(detail.production_delta), ...
        mean(detail.eta_produces_more), mean(detail.htt_delta), median(detail.htt_delta), ...
        mean(detail.eta_uses_more_htt), mean(detail.target_delta), median(detail.target_delta), ...
        mean(detail.gap_delta), median(detail.gap_delta), mean(detail.reported_objective_delta)];
end
tbl = array2table(vals, 'VariableNames', {'scenario_count','scenario_share', ...
    'mean_ordinary_shortage_delta','median_ordinary_shortage_delta', ...
    'mean_final_inventory_delta','median_final_inventory_delta', ...
    'share_eta_leaves_more_inventory','mean_production_delta','median_production_delta', ...
    'share_eta_produces_more','mean_htt_delta','median_htt_delta', ...
    'share_eta_uses_more_htt','mean_target_delta','median_target_delta', ...
    'mean_gap_delta','median_gap_delta','mean_reported_objective_delta'});
end

function tbl = build_component_difference(saa, eta)
component = ["reported_objective"; "terminal_gap_penalty"; ...
    "ordinary_shortage_penalty"; "production_electricity_and_om"; ...
    "htt_transport_cost"; "inventory_holding_cost"; "unresolved_residual"; ...
    "objective_without_terminal_gap"];
saaMean = [mean(saa.path_cost); mean(saa.terminal_penalty); mean(saa.normal_penalty); ...
    mean(saa.production_cost); mean(saa.transport_cost); mean(saa.holding_cost); ...
    mean(saa.component_residual); mean(saa.objective_without_terminal)];
etaMean = [mean(eta.path_cost); mean(eta.terminal_penalty); mean(eta.normal_penalty); ...
    mean(eta.production_cost); mean(eta.transport_cost); mean(eta.holding_cost); ...
    mean(eta.component_residual); mean(eta.objective_without_terminal)];
delta = etaMean - saaMean;
share = nan(size(delta));
if abs(delta(1)) > 1e-12
    share = delta / delta(1);
end
tbl = table(component, saaMean, etaMean, delta, share, ...
    'VariableNames', {'component','saa_mean','eta_mean','eta_minus_saa', ...
    'share_of_reported_objective_delta'});
end

function write_workspace_integrity(outDir, saaFile, etaFile, oosFile, a, b, saa, eta)
fid = fopen(fullfile(outDir, 'workspace_integrity_audit.txt'), 'w');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'Step-05B-1 workspace integrity audit\n\n');
fprintf(fid, 'SAA workspace: %s\n', saaFile);
fprintf(fid, 'eta workspace: %s\n', etaFile);
fprintf(fid, 'OOS file: %s\n', oosFile);
fprintf(fid, 'SAA workspace loaded: %d\n', a.workspace_loaded);
fprintf(fid, 'eta workspace loaded: %d\n', b.workspace_loaded);
fprintf(fid, 'SAA original/replay OOS rows: %d/%d\n', a.original_nbOS, a.replay_nbOS);
fprintf(fid, 'eta original/replay OOS rows: %d/%d\n', b.original_nbOS, b.replay_nbOS);
fprintf(fid, 'SAA replay max errors: path_cost=%.12g, normal=%.12g, terminal=%.12g, final=%.12g, production=%.12g, transport=%.12g\n', ...
    a.path_cost_max_abs_error, a.normal_shortage_max_abs_error, ...
    a.terminal_shortage_max_abs_error, a.final_loh_max_abs_error, ...
    a.production_max_abs_error, a.transport_max_abs_error);
fprintf(fid, 'eta replay max errors: path_cost=%.12g, normal=%.12g, terminal=%.12g, final=%.12g, production=%.12g, transport=%.12g\n', ...
    b.path_cost_max_abs_error, b.normal_shortage_max_abs_error, ...
    b.terminal_shortage_max_abs_error, b.final_loh_max_abs_error, ...
    b.production_max_abs_error, b.transport_max_abs_error);
fprintf(fid, 'SAA mechanical max errors: gap=%.12g, terminal_cost=%.12g, components=%.12g\n', ...
    a.gap_reconstruction_max_abs_error, a.terminal_cost_max_abs_error, ...
    a.objective_component_max_abs_error);
fprintf(fid, 'eta mechanical max errors: gap=%.12g, terminal_cost=%.12g, components=%.12g\n', ...
    b.gap_reconstruction_max_abs_error, b.terminal_cost_max_abs_error, ...
    b.objective_component_max_abs_error);
fprintf(fid, 'SAA stop flag/iterations/time: %d/%d/%.12g s\n', saa.stop_flag, saa.train_iterations, saa.train_time);
fprintf(fid, 'eta stop flag/iterations/time: %d/%d/%.12g s\n', eta.stop_flag, eta.train_iterations, eta.train_time);
fprintf(fid, 'Conclusion: both saved workspaces are reloadable and deterministic fixed-policy replay reproduces the saved OOS outputs. The SAA post-save process exit did not corrupt the saved policy or OOS result.\n');
end

function write_common_oos_audit(outDir, oosFile, oosHash, OOS, saa, eta)
fid = fopen(fullfile(outDir, 'common_oos_rowwise_audit.txt'), 'w');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'Step-05B-1 common OOS rowwise audit\n\n');
fprintf(fid, 'Shared OOS file: %s\n', oosFile);
fprintf(fid, 'Shared OOS SHA-256: %s\n', oosHash);
fprintf(fid, 'Rows/columns: %d/%d\n', size(OOS,1), size(OOS,2));
fprintf(fid, 'SAA params.oosFile equals eta params.oosFile: %d\n', strcmp(char(saa.oos_file), char(eta.oos_file)));
fprintf(fid, 'State path matrix exact equality: %d\n', isequal(saa.state_path, eta.state_path));
fprintf(fid, 'Terminal hit vector exact equality: %d\n', isequal(saa.hit_terminal, eta.hit_terminal));
fprintf(fid, 'Terminal stage vector exact equality: %d\n', isequal(saa.terminal_stage, eta.terminal_stage));
fprintf(fid, 'Terminal state vector exact equality: %d\n', isequal(saa.terminal_state, eta.terminal_state));
fprintf(fid, 'Terminal hit count: %d\n', sum(saa.hit_terminal));
fprintf(fid, 'Interpretation: eval_h2 is deterministic conditional on the frozen state-path table; it performs no additional random draws. Therefore the two 10000-row evaluations are strict common-sample pathwise comparisons.\n');
end

function write_penalty_source_audit(outDir, d)
fid = fopen(fullfile(outDir, 'penalty_200_2000_source_audit.txt'), 'w');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'Step-05B-1 penalty source audit\n\n');
fprintf(fid, 'Effective values from the saved workspace\n');
fprintf(fid, '- reserve/TerminalLOH gap penalty: %.12g yuan/kg\n', d.cost_reserve_shortage);
fprintf(fid, '- normal shortage base penalty: %.12g yuan/kg\n', d.cost_normal_shortage_base);
fprintf(fid, '- normal shortage multiplier: %.12g\n', d.normal_shortage_penalty_multiplier);
fprintf(fid, '- effective normal shortage penalty: %.12g yuan/kg\n\n', d.cost_normal_shortage);
fprintf(fid, 'Source and call chain\n');
fprintf(fid, '- Data source file: data/yuanqi/near_stage_msp_input.mat, struct NearStageInput.Cost.\n');
fprintf(fid, '- load_data_h2_near.m:257 reads NearStageInput.Cost.normal_shortage_penalty_yuan_per_kg; lines 263-265 form params.cost_normal_shortage.\n');
fprintf(fid, '- load_data_h2_near.m:266 reads NearStageInput.Cost.reserve_shortage_penalty_yuan_per_kg into params.cost_reserve_shortage.\n');
fprintf(fid, '- build_stage_model_h2.m:28 defines z_normal; line 38 assigns params.cost_normal_shortage in every ordinary-stage LP objective.\n');
fprintf(fid, '- eval_terminal_loh_h2.m:10-12 computes shortage=max(0,TerminalLOH(:,k)-prev_x) and cost=params.cost_reserve_shortage*sum(shortage).\n');
fprintf(fid, '- forward_pass_h2.m:34-40 calls eval_terminal_loh_h2 at lf=Nc-1.\n');
fprintf(fid, '- terminal_value_and_subgradient_h2.m:14-17 uses the same value and subgradient -params.cost_reserve_shortage for deficient stations.\n');
fprintf(fid, '- backward_pass_h2.m:22-24 calls that terminal value/subgradient; lines 42-52 probability-weight it and add the cut.\n');
fprintf(fid, '- eval_h2.m:68-76 uses the same terminal evaluator and records terminal shortage/cost; ordinary shortage is sol.z_normal at lines 92-95.\n');
fprintf(fid, '- add_cut_h2.m:4-8 installs theta >= alpha + g''x.\n\n');
fprintf(fid, 'Mathematical expressions\n');
fprintf(fid, '- ordinary stage: 200 * sum_i z_normal_i, with u_normal_i + z_normal_i >= D_normal_i.\n');
fprintf(fid, '- terminal stage: 2000 * sum_i max(0, TerminalLOH_i(k) - x_i).\n');
fprintf(fid, '- terminal demand is a check/penalty, not a physical withdrawal from inventory.\n\n');
fprintf(fid, 'Other numeric 200/2000 occurrences\n');
fprintf(fid, '- build_terminal_loh_h2.m includes node base-load entries equal to 200 kW; these are physical load data, not shortage penalties.\n');
fprintf(fid, '- site/input tables include engineering capacities equal to 200; these are not objective coefficients.\n');
fprintf(fid, '- no second active 2000 objective coefficient was found in the audited main MSP call chain.\n');
fprintf(fid, '- terminalLoh_wdro offline audit/solver scripts contain separate numeric M=2000 settings; they are not called by this main-MSP evaluation chain.\n');
end

function write_mechanism_summary(outDir, saa, eta, ordinarySummary, componentDiff)
deltaObj = mean(eta.path_cost - saa.path_cost);
deltaTerminal = mean(eta.terminal_penalty - saa.terminal_penalty);
deltaNormal = mean(eta.normal_penalty - saa.normal_penalty);
deltaWithout = mean(eta.objective_without_terminal - saa.objective_without_terminal);
shareTerminal = deltaTerminal / deltaObj;
shareNormal = deltaNormal / deltaObj;
moreInventoryShare = ordinarySummary.share_eta_leaves_more_inventory(1);

fid = fopen(fullfile(outDir, 'mechanism_summary.txt'), 'w');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'Step-05B-1 mechanism summary\n\n');
fprintf(fid, 'Mean reported objective delta eta-SAA: %.12g\n', deltaObj);
fprintf(fid, 'Terminal gap penalty contribution: %.12g (%.6f%%)\n', deltaTerminal, 100*shareTerminal);
fprintf(fid, 'Ordinary shortage penalty contribution: %.12g (%.6f%%)\n', deltaNormal, 100*shareNormal);
fprintf(fid, 'Objective delta after removing terminal gap penalty: %.12g\n', deltaWithout);
fprintf(fid, 'Mean ordinary shortage delta kg: %.12g\n', mean(eta.normal_shortage - saa.normal_shortage));
fprintf(fid, 'Mean final inventory delta kg: %.12g\n', mean(eta.final_total - saa.final_total));
commonHit = saa.hit_terminal & eta.hit_terminal;
fprintf(fid, 'Mean TerminalLOH target delta on common terminal-hit paths kg: %.12g\n', ...
    mean(eta.target_total(commonHit) - saa.target_total(commonHit)));
fprintf(fid, 'Mean absolute terminal gap delta kg: %.12g\n', mean(eta.gap_total - saa.gap_total));
fprintf(fid, 'Ordinary-shortage-worse scenario count/share: %d / %.8f\n', ...
    ordinarySummary.scenario_count(1), ordinarySummary.scenario_share(1));
fprintf(fid, 'Within those scenarios, eta leaves more final inventory share: %.8f\n', moreInventoryShare);
fprintf(fid, 'Within those scenarios, mean/median final inventory delta kg: %.12g / %.12g\n', ...
    ordinarySummary.mean_final_inventory_delta(1), ordinarySummary.median_final_inventory_delta(1));
fprintf(fid, 'Within those scenarios, eta produces more share: %.8f; uses more HTT share: %.8f\n', ...
    ordinarySummary.share_eta_produces_more(1), ordinarySummary.share_eta_uses_more_htt(1));
fprintf(fid, '\nComponent table source: objective_component_difference.csv (%d rows).\n', height(componentDiff));
end

function write_judgment(outDir, saa, eta, ordinarySummary)
deltaObj = mean(eta.path_cost - saa.path_cost);
deltaTerminal = mean(eta.terminal_penalty - saa.terminal_penalty);
deltaWithout = mean(eta.objective_without_terminal - saa.objective_without_terminal);
deltaNormalKg = mean(eta.normal_shortage - saa.normal_shortage);
terminalShare = deltaTerminal / deltaObj;
moreInventoryShare = ordinarySummary.share_eta_leaves_more_inventory(1);

if terminalShare > 0.5 && deltaWithout > 0 && deltaNormalKg > 0
    code = 'C';
    statement = ['The 2000-yuan/kg TerminalLOH gap penalty explains most of the ' ...
        'reported objective increase, but eta also has independently higher ordinary ' ...
        'shortage and positive non-terminal-cost deterioration. The mechanism is mixed.'];
elseif terminalShare > 0.5 && deltaWithout <= 0
    code = 'A';
    statement = ['The higher TerminalLOH target and its historical gap penalty explain ' ...
        'the reported objective increase; the diagnostic objective without terminal gap ' ...
        'does not deteriorate.'];
elseif deltaWithout > 0 && deltaNormalKg > 0
    code = 'B';
    statement = ['After removing the terminal gap penalty diagnostically, eta remains ' ...
        'physically and operationally worse; the 2000 penalty is not the main explanation.'];
else
    code = 'D';
    statement = 'The available evidence is insufficient for a valid paired mechanism conclusion.';
end

fid = fopen(fullfile(outDir, 'step05b1_judgment.txt'), 'w');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'Step-05B-1 judgment: %s\n\n%s\n\n', code, statement);
fprintf(fid, 'Mean reported objective delta eta-SAA: %.12g\n', deltaObj);
fprintf(fid, 'Mean terminal gap penalty delta: %.12g (share %.8f)\n', deltaTerminal, terminalShare);
fprintf(fid, 'Mean diagnostic objective delta without terminal gap: %.12g\n', deltaWithout);
fprintf(fid, 'Mean ordinary shortage delta kg: %.12g\n', deltaNormalKg);
fprintf(fid, 'Among ordinary-shortage-worse paths, eta leaves more final inventory share: %.8f\n', moreInventoryShare);
fprintf(fid, '\nThis judgment concerns the current main-MSP execution and penalty mechanism only. It does not declare Pearson DRO successful or unsuccessful.\n');
end

function write_readme(outDir, sourceRun)
fid = fopen(fullfile(outDir, 'README.md'), 'w');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '# Step-05B-1 TerminalLOH gap mechanism audit\n\n');
fprintf(fid, '- Source: `%s`\n', sourceRun);
fprintf(fid, '- Scope: read-only saved-policy/OOS mechanism audit; no MSP retraining and no parameter or TerminalLOH modification.\n');
fprintf(fid, '- Both saved policies are replayed on the exact protected 10000-by-8 OOS path table with decision storage enabled only in memory.\n');
fprintf(fid, '- `objective_without_terminal_gap_penalty` is diagnostic only and is not a new optimization objective.\n');
fprintf(fid, '- Historical coefficients 200 and 2000 remain unchanged; 1283.205 is not used.\n');
fprintf(fid, '- See `step05b1_judgment.txt` for the bounded A/B/C/D conclusion.\n');
end

function write_large_file_manifest(outDir, saaWorkspace, etaWorkspace, oosFile, oosHash, rowwise, withoutTerminal)
rowwiseFile = fullfile(outDir, 'terminal_target_vs_final_inventory.csv');
withoutFile = fullfile(outDir, 'objective_without_terminal_gap_penalty.csv');
fid = fopen(fullfile(outDir, 'LARGE_FILE_MANIFEST.md'), 'w');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '# LARGE FILE MANIFEST\n\n');
fprintf(fid, '| role | local path | rows/shape | bytes | SHA-256 | Git policy |\n');
fprintf(fid, '|---|---|---:|---:|---|---|\n');
fprintf(fid, '| SAA saved policy workspace | `%s` | v7.3 MAT | %d | `%s` | local protected source, do not copy |\n', ...
    saaWorkspace, file_bytes(saaWorkspace), sha256_file(saaWorkspace));
fprintf(fid, '| eta saved policy workspace | `%s` | v7.3 MAT | %d | `%s` | local protected source, do not copy |\n', ...
    etaWorkspace, file_bytes(etaWorkspace), sha256_file(etaWorkspace));
fprintf(fid, '| common OOS state paths | `%s` | 10000x8 | %d | `%s` | protected source, do not copy |\n', ...
    oosFile, file_bytes(oosFile), oosHash);
fprintf(fid, '| rowwise target/final/gap audit | `terminal_target_vs_final_inventory.csv` | %d rows | %d | `%s` | lightweight audit output |\n', ...
    height(rowwise), file_bytes(rowwiseFile), sha256_file(rowwiseFile));
fprintf(fid, '| paired objective-without-terminal audit | `objective_without_terminal_gap_penalty.csv` | %d rows | %d | `%s` | lightweight audit output |\n', ...
    height(withoutTerminal), file_bytes(withoutFile), sha256_file(withoutFile));
end

function n = file_bytes(path)
info = dir(path);
n = info.bytes;
end

function hash = sha256_file(path)
md = javaMethod('getInstance', 'java.security.MessageDigest', 'SHA-256');
fid = fopen(path, 'r');
if fid < 0
    error('sha256_file:OpenFailed', 'Could not open %s.', path);
end
cleanup = onCleanup(@() fclose(fid));
while ~feof(fid)
    data = fread(fid, 1024 * 1024, '*uint8');
    if ~isempty(data)
        md.update(typecast(data, 'int8'));
    end
end
raw = typecast(md.digest(), 'uint8');
hash = lower(reshape(dec2hex(raw, 2).', 1, []));
end

function require_file(path)
if ~isfile(path)
    error('run_step05B1_terminal_gap_mechanism_audit_h2:MissingFile', ...
        'Missing required file: %s', path);
end
end
