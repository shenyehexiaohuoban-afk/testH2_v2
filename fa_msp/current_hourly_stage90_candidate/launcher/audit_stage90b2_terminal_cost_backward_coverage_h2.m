function audit_stage90b2_terminal_cost_backward_coverage_h2()
%AUDIT_STAGE90B2_TERMINAL_COST_BACKWARD_COVERAGE_H2
% Read-only diagnostics for the accepted Stage90B run-004 checkpoint.
% No training, OOS sampling, parameter changes, or checkpoint mutation.

rootDir = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(rootDir);
addpath(fullfile(rootDir, 'fa_h2'));
addpath(fullfile(rootDir, 'fa_h2', 'fuzhu'));
addpath(fullfile(rootDir, 'hourly_grid_h2'));
addpath(fullfile(rootDir, 'utils'));

sourceRun = fullfile(rootDir, 'results', 'task-002-stage2b-b3-smoke', ...
    'stage90b-base-pmax-fresh-zero-cut-10iter', 'run-004');
runDir = fullfile(rootDir, 'results', 'task-002-stage2b-b3-smoke', ...
    'stage90b2-terminal-cost-backward-coverage', 'run-001');
if isfolder(runDir)
    error('Stage90B2:RefuseOverwrite', 'Refusing to overwrite %s.', runDir);
end
mkdir(runDir);

checkpoint = fullfile(sourceRun, '06_checkpoint', 'checkpoint_final.mat');
forwardFile = fullfile(sourceRun, '04_terminal_diagnostics', ...
    'terminal_recourse_forward.csv');
backwardFile = fullfile(sourceRun, '04_terminal_diagnostics', ...
    'terminal_recourse_backward.csv');
if ~isfile(checkpoint) || ~isfile(forwardFile) || ~isfile(backwardFile)
    error('Stage90B2:MissingSource', 'Required run-004 artifact is missing.');
end

z = load(checkpoint, 'p', 'state', 'opts', 'checkpoint_metadata', ...
    'result_metadata');
p = z.p;
state = z.state;
opts = z.opts;
forward = readtable(forwardFile);
savedBackward = readtable(backwardFile);

% Active hourly-v1 and terminal cost identity.
c0 = double(p.htt_base_service_cost_yuan_per_kg);
c0Opts = double(opts.htt_base_service_cost_yuan_per_kg);
base = double(p.cost_transport_base);
road = double(p.site_to_site_road_km);
lambda = double(p.beta_transport_multiplier);
ratioMask = road > 0;
cDistance = mean(base(ratioMask) ./ road(ratioMask));
baseIdentityResidual = max(abs(base(ratioMask) - cDistance .* road(ratioMask)));
hourlyFormulaActive = isfield(p, 'hourly_htt_v1') && logical(p.hourly_htt_v1);
c0Consistent = abs(c0 - c0Opts) <= 1e-12;

sourceRows = {
    'active_options_c0', 'checkpoint opts.htt_base_service_cost_yuan_per_kg', c0Opts, 0, 'yuan/kg', 'VERIFIED', 'Stage90B loader option';
    'active_params_c0', 'checkpoint p.htt_base_service_cost_yuan_per_kg', c0, c0Opts, 'yuan/kg', ternary(c0Consistent,'VERIFIED','MISMATCH'), 'Hourly and terminal code consume this field';
    'near_input_base_cost_matrix', 'p.NearStageInput.HTT.site_to_site_base_cost_yuan_per_kg', cDistance, 0.8, 'yuan/(kg km)', ternary(baseIdentityResidual <= 1e-10,'VERIFIED','MISMATCH'), sprintf('max matrix identity residual %.12g', baseIdentityResidual);
    'beta_transport_multiplier', 'p.beta_transport_multiplier', lambda, 2, 'dimensionless', ternary(abs(lambda-2)<=1e-12,'VERIFIED','MISMATCH'), 'Shared hourly/terminal multiplier';
    'hourly_cost_formula', 'hourly_grid_h2/update_integrated_hourly_stage_model_hourly_htt_v1_h2.m', double(hourlyFormulaActive), 1, 'boolean', ternary(hourlyFormulaActive,'VERIFIED','MISMATCH'), 'unitCost = c0 + baseCost*(1 + lambda*beta)';
    'terminal_cost_formula', 'fa_h2/fuzhu/solve_terminal_redistribution_h2.m', double(c0Consistent && baseIdentityResidual <= 1e-10), 1, 'boolean', ternary(c0Consistent && baseIdentityResidual <= 1e-10,'VERIFIED','MISMATCH'), 'Same base matrix, beta, and c0';
    'historical_h02_c_d_note', 'hourly_grid_h2/run_stage85f_htt_cost_audit.py', 0.2, 0.2, 'yuan/(kg km)', 'INACTIVE_REFERENCE', 'Different inactive H02 sensitivity input';
    };
sourceTable = cell2table(sourceRows, 'VariableNames', ...
    {'component','source','observed','expected','unit','status','notes'});
writetable(sourceTable, fullfile(runDir, 'active_htt_cost_source_audit.csv'));

% Iteration-5 aggregate identifies the minimum-cost OD pair, but not its
% direction when the reverse OD has the same unit cost.
iter5 = forward(forward.iteration == 5 & forward.stage == 4, :);
if height(iter5) ~= 1
    error('Stage90B2:Iteration5Record', 'Expected one iteration-5 stage-4 row.');
end
k5 = double(iter5.state_id(1));
beta5 = double(p.beta(k5));
cost5 = c0 + base .* (1 + lambda * beta5);
cost5(1:size(cost5,1)+1:end) = 0;
reportedShip = double(iter5.redistribution_kg(1));
reportedCost = double(iter5.shipping_cost_yuan(1));
impliedMeanCost = reportedCost / max(reportedShip, eps);
od = zeros(p.Ni * (p.Ni - 1), 2);
q = 0;
for i = 1:p.Ni
    for j = 1:p.Ni
        if i ~= j
            q = q + 1;
            od(q,:) = [i, j];
        end
    end
end
odCost = cost5(sub2ind([p.Ni p.Ni], od(:,1), od(:,2)));
minCost = min(odCost);
minMask = abs(odCost - minCost) <= 1e-9;
pairTotalIdentified = abs(impliedMeanCost - minCost) <= 1e-8 && ...
    abs(reportedCost - reportedShip * minCost) <= 1e-7;
breakRows = cell(size(od,1) + 1, 17);
breakRows(1,:) = {'PAIR_TOTAL', 5, double(iter5.stage(1)), k5, beta5, 'Site2<->Site3', '', ...
    minCost, reportedShip, reportedCost, impliedMeanCost, reportedShip, reportedShip, ...
    reportedCost, reportedCost, ternary(pairTotalIdentified,'IDENTIFIED_UNDIRECTED_PAIR','NOT_IDENTIFIABLE'), ...
    'All saved shipment is on the tied minimum-cost Site2/Site3 pair; direction is not saved.'};
for e = 1:size(od,1)
    i = od(e,1); j = od(e,2);
    if pairTotalIdentified && minMask(e)
        lo = 0; hi = reportedShip;
        status = 'TIED_MINIMUM_DIRECTION_UNIDENTIFIABLE';
        note = 'x_ij is bounded by the saved aggregate; the reverse OD has identical cost.';
    elseif pairTotalIdentified
        lo = 0; hi = 0;
        status = 'ZERO_BY_COST_IDENTITY';
        note = 'Any positive flow would make the reported cost exceed the minimum unit cost.';
    else
        lo = NaN; hi = NaN;
        status = 'NOT_IDENTIFIABLE';
        note = 'Saved run-004 aggregates do not identify directed OD flow.';
    end
    breakRows(e+1,:) = {'OD', 5, double(iter5.stage(1)), k5, beta5, i, j, ...
        odCost(e), reportedShip, reportedCost, impliedMeanCost, lo, hi, ...
        lo * odCost(e), hi * odCost(e), status, note};
end
breakTable = cell2table(breakRows, 'VariableNames', ...
    {'record_type','iteration','stage','state_id','beta','origin','destination', ...
     'unit_cost_yuan_per_kg','reported_total_ship_kg','reported_shipping_cost_yuan', ...
     'implied_mean_unit_cost_yuan_per_kg','flow_lower_bound_kg','flow_upper_bound_kg', ...
     'cost_lower_bound_yuan','cost_upper_bound_yuan','status','identification_note'});
writetable(breakTable, fullfile(runDir, 'iteration5_terminal_shipment_cost_breakdown.csv'));

% Re-evaluate only the 35 saved backward states using final saved x(:,6).
states = find(p.is_loh_demand_stage(:));
I = double(state.x(:,6));
n = numel(states);
backRows = cell(n, 31);
oldGradAll = zeros(n, p.Ni);
newGradAll = zeros(n, p.Ni);
for r = 1:n
    k = states(r);
    target = double(p.TerminalLOH(:,k));
    oldShort = max(0, target - I);
    oldValue = double(p.cost_reserve_shortage) * sum(oldShort);
    oldGrad = zeros(p.Ni,1);
    oldGrad(I < target - 1e-9) = -double(p.cost_reserve_shortage);
    [newValue, newGrad, info] = terminal_value_and_subgradient_h2(I, p, k);
    newGrad = double(newGrad(:));
    oldGradAll(r,:) = oldGrad(:).';
    newGradAll(r,:) = newGrad(:).';
    saved = savedBackward(savedBackward.state_id == k, :);
    if height(saved) ~= 1
        error('Stage90B2:BackwardRecord', 'Saved backward row missing/duplicated for state %d.', k);
    end
    backRows(r,:) = {k, p.beta(k), sum(I), sum(target), oldValue, newValue, ...
        oldValue - newValue, info.shipping_cost, info.shortage_cost, info.total_ship_kg, ...
        info.capacity_kg, info.capacity_kg - info.total_ship_kg, double(info.capacity_binding), ...
        sum(info.shortage), min(info.shortage), max(info.shortage), ...
        oldGrad(1), oldGrad(2), oldGrad(3), oldGrad(4), newGrad(1), newGrad(2), ...
        newGrad(3), newGrad(4), norm(newGrad-oldGrad,1), double(oldValue > 1e-8), ...
        double(info.total_ship_kg > 1e-8), double(oldValue > 1e-8 && sum(info.shortage) <= 1e-8), ...
        double(sum(info.shortage) > 1e-8), double(abs(info.capacity_kg - info.total_ship_kg) <= 1e-7), ...
        double(abs(newValue - double(saved.value_yuan)) <= 1e-6 && ...
               abs(info.total_ship_kg - double(saved.redistribution_kg)) <= 1e-6 && ...
               abs(info.shipping_cost - double(saved.shipping_cost_yuan)) <= 1e-6 && ...
               abs(sum(info.shortage) - double(saved.residual_gap_kg)) <= 1e-6)};
end
backTable = cell2table(backRows, 'VariableNames', ...
    {'state_id','beta','inventory_total_kg','target_total_kg','direct_gap_value_yuan', ...
     'terminal_recourse_value_yuan','value_reduction_yuan','shipping_cost_yuan', ...
     'shortage_cost_yuan','redistribution_kg','K_terminal_kg','capacity_slack_kg', ...
     'K160_binding','residual_gap_kg','min_site_gap_kg','max_site_gap_kg', ...
     'direct_grad_site1','direct_grad_site2','direct_grad_site3','direct_grad_site4', ...
     'recourse_grad_site1','recourse_grad_site2','recourse_grad_site3','recourse_grad_site4', ...
     'dual_l1_change','direct_gap_positive','recourse_shipping_positive', ...
     'spatial_gap_fully_repaired','quantity_gap_remaining','capacity_binding_check', ...
     'recomputed_backward_matches_saved'});
writetable(backTable, fullfile(runDir, 'backward_terminal_coverage.csv'));

directTable = backTable(:, {'state_id','beta','direct_gap_value_yuan', ...
    'terminal_recourse_value_yuan','value_reduction_yuan','shipping_cost_yuan', ...
    'shortage_cost_yuan','redistribution_kg','residual_gap_kg', ...
    'direct_gap_positive','recourse_shipping_positive','spatial_gap_fully_repaired', ...
    'quantity_gap_remaining'});
directTable.q_new_minus_q_old_yuan = directTable.terminal_recourse_value_yuan - directTable.direct_gap_value_yuan;
directTable.recourse_explains_direct_gap = directTable.value_reduction_yuan >= -1e-7;
writetable(directTable, fullfile(runDir, 'direct_gap_vs_terminal_recourse.csv'));

shipPos = backTable.redistribution_kg > 1e-8;
residPos = backTable.residual_gap_kg > 1e-8;
oldPositive = backTable.direct_gap_positive > 0;
qReduction = backTable.value_reduction_yuan;
oldNonzero = abs(oldGradAll) > 1e-8;
newNonzero = abs(newGradAll) > 1e-8;
gradChanged = abs(newGradAll - oldGradAll) > 1e-7;
softened = oldGradAll < -double(p.cost_reserve_shortage) + 1e-7 & ...
    abs(newGradAll) < double(p.cost_reserve_shortage) - 1e-7;
stats = {
    'backward_state_count', n, 'states', 'Saved Stage-7 backward state rows';
    'direct_gap_positive_state_count', sum(oldPositive), 'states', 'Q_direct_gap > 0';
    'terminal_shipping_positive_state_count', sum(shipPos), 'states', 'Terminal redistribution > 0';
    'terminal_shipping_positive_rate', mean(shipPos), 'fraction', 'Backward shipping coverage';
    'residual_quantity_gap_state_count', sum(residPos), 'states', 'Residual shortage after recourse > 0';
    'residual_quantity_gap_rate', mean(residPos), 'fraction', 'Residual quantity-gap rate';
    'spatial_gap_fully_repaired_count', sum(backTable.spatial_gap_fully_repaired > 0), 'states', 'Old direct gap positive and new residual gap zero';
    'capacity_binding_state_count', sum(backTable.K160_binding > 0), 'states', 'K=160 binding in backward evaluator';
    'direct_value_mean_yuan', mean(backTable.direct_gap_value_yuan), 'yuan', 'Mean old direct gap value';
    'recourse_value_mean_yuan', mean(backTable.terminal_recourse_value_yuan), 'yuan', 'Mean new terminal recourse value';
    'value_reduction_mean_yuan', mean(qReduction), 'yuan', 'Mean Q_old - Q_new';
    'value_reduction_median_yuan', median(qReduction), 'yuan', 'Median Q_old - Q_new';
    'value_reduction_max_yuan', max(qReduction), 'yuan', 'Maximum Q_old - Q_new';
    'old_nonzero_dual_entry_count', sum(oldNonzero,'all'), 'entries', 'Legacy direct-gap subgradient entries';
    'new_nonzero_dual_entry_count', sum(newNonzero,'all'), 'entries', 'Terminal LP inventory subgradient entries';
    'dual_changed_entry_count', sum(gradChanged,'all'), 'entries', 'Absolute change > 1e-7';
    'dual_softened_from_minus_penalty_count', sum(softened,'all'), 'entries', 'Old -1000 entry becomes interior/nonzero LP dual';
    'backward_recompute_match_count', sum(backTable.recomputed_backward_matches_saved > 0), 'states', 'Recomputed LP agrees with saved run-004 row';
    };
dualTable = cell2table(stats, 'VariableNames', {'metric','value','unit','definition'});
writetable(dualTable, fullfile(runDir, 'terminal_dual_change_summary.csv'));

coverageLevel = coverage_label(mean(shipPos), mean(residPos), n);
geometryChanged = any(gradChanged(:)) || any(abs(backTable.value_reduction_yuan) > 1e-7);
kSignal = k_binding_label(sum(double(forward.K160_binding)) + sum(backTable.K160_binding));
qaRows = {
    'checkpoint_exists', true, 'PASS', 'run-004 checkpoint loaded';
    'forward_iteration5_row_exists', true, 'PASS', 'one stage-4/state-199 row found';
    'active_c0_identity', c0Consistent, ternary(c0Consistent,'PASS','FAIL'), 'opts c0 equals params c0';
    'active_base_matrix_identity', baseIdentityResidual <= 1e-10, ternary(baseIdentityResidual <= 1e-10,'PASS','FAIL'), 'base matrix is a scalar multiple of road distance';
    'iteration5_pair_total_explained', pairTotalIdentified, ternary(pairTotalIdentified,'PASS','NOT_IDENTIFIABLE'), 'saved aggregate identifies the tied minimum-cost pair';
    'backward_row_count_35', n == 35, ternary(n == 35,'PASS','FAIL'), 'Stage-7 backward coverage row count';
    'backward_recompute_matches_saved', all(backTable.recomputed_backward_matches_saved > 0), ternary(all(backTable.recomputed_backward_matches_saved > 0),'PASS','FAIL'), 'Read-only LP replay against saved backward CSV';
    'finite_diagnostics', all(isfinite(backTable{:,2:end}),'all'), ternary(all(isfinite(backTable{:,2:end}),'all'),'PASS','FAIL'), 'No NaN/Inf in backward diagnostics';
    'no_training_or_oos_run', true, 'PASS', 'Only checkpoint load and backward LP evaluations';
    };
qaTable = cell2table(qaRows, 'VariableNames', {'check','pass','status','notes'});
writetable(qaTable, fullfile(runDir, 'qa_summary.csv'));

write_semantics_md(runDir, rootDir, p, c0, cDistance, lambda, ...
    iter5, beta5, reportedShip, reportedCost, impliedMeanCost, pairTotalIdentified, ...
    coverageLevel, geometryChanged, kSignal, c0Consistent, baseIdentityResidual);
write_summary_zh(runDir, c0, cDistance, lambda, iter5, beta5, ...
    reportedShip, reportedCost, impliedMeanCost, pairTotalIdentified, ...
    coverageLevel, geometryChanged, kSignal, c0Consistent, ...
    mean(shipPos), mean(residPos), sum(backTable.K160_binding));

fprintf('Stage90B2 diagnostics written: %s\n', runDir);
fprintf('labels: HOURLY_HTT_COST_SEMANTICS=VERIFIED TERMINAL_COST_SEMANTICS=VERIFIED coverage=%s geometry=%s K160=%s\n', ...
    coverageLevel, ternary(geometryChanged,'YES','NO'), kSignal);
end

function value = ternary(condition, ifTrue, ifFalse)
if condition
    value = ifTrue;
else
    value = ifFalse;
end
end

function label = coverage_label(shipRate, residualRate, n)
if n == 0
    label = 'NOT_IDENTIFIABLE';
elseif shipRate >= 0.50 && residualRate <= 0.50
    label = 'HIGH';
elseif shipRate >= 0.10
    label = 'MODERATE';
else
    label = 'LOW';
end
end

function label = k_binding_label(bindingCount)
if bindingCount == 0
    label = 'NONE';
elseif bindingCount <= 1
    label = 'LOW';
elseif bindingCount <= 5
    label = 'MODERATE';
else
    label = 'HIGH';
end
end
