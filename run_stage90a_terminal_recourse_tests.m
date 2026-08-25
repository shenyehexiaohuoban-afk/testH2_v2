function [results, qa] = run_stage90a_terminal_recourse_tests(outputDir)
%RUN_STAGE90A_TERMINAL_RECOURSE_TESTS Deterministic Stage-90A unit tests.
%
% This is a small mechanism test only.  It does not load the MSP dataset,
% train a policy, run OOS paths, or modify any accepted output.

rootDir = fileparts(mfilename('fullpath'));
addpath(fullfile(rootDir, 'fa_h2', 'fuzhu'));
if nargin < 1 || isempty(outputDir); outputDir = rootDir; end
if ~exist(outputDir, 'dir'); mkdir(outputDir); end

rows = cell(9, 15);
rows(1,:) = run_case('A_adequate', @case_a);
rows(2,:) = run_case('B_spatial_mismatch', @case_b);
rows(3,:) = run_case('C_insufficient_total', @case_c);
rows(4,:) = run_case('D_zero_capacity_fallback', @case_d);
rows(5,:) = run_case('E_high_transport_cost', @case_e);
rows(6,:) = run_case('F_capacity_binding', @case_f);
rows(7,:) = run_case('G_dual_finite_difference', @case_g);
rows(8,:) = run_case('H_subcapacity_not_truncated', @case_h);
rows(9,:) = run_case('I_capacity_binding_over160', @case_i);

results = cell2table(rows, 'VariableNames', {'case_id','pass','value', ...
    'expected_value','value_error','total_ship_kg','expected_ship_kg', ...
    'gap_kg','expected_gap_kg','primal_residual','dual_residual', ...
    'complementarity_residual','gradient_error','dual_capacity','notes'});
writetable(results, fullfile(outputDir, 'unit_test_results.csv'));

qa = table(sum(results.pass), height(results), all(results.pass), ...
    max(results.primal_residual), max(results.dual_residual), ...
    max(results.complementarity_residual), max(results.gradient_error), ...
    string(datetime('now','Format','yyyy-MM-dd HH:mm:ss')), ...
    'VariableNames', {'passed','total','all_pass','max_primal_residual', ...
    'max_dual_residual','max_complementarity_residual','max_gradient_error', ...
    'timestamp'});
writetable(qa, fullfile(outputDir, 'qa_summary.csv'));
if ~qa.all_pass
    error('run_stage90a_terminal_recourse_tests:Failure', ...
        '%d of %d Stage-90A unit tests failed.', qa.total - qa.passed, qa.total);
end
end

function row = run_case(caseId, fn)
tol = 1e-6;
value = NaN; expectedValue = NaN; totalShip = NaN; expectedShip = NaN;
gapKg = NaN; expectedGap = NaN; primal = NaN; dual = NaN; comp = NaN;
gradientError = NaN;
dualCapacity = NaN;
passed = false;
try
    out = fn();
    value = out.value; expectedValue = out.expectedValue;
    totalShip = out.totalShip; expectedShip = out.expectedShip;
    gapKg = out.gapKg; expectedGap = out.expectedGap;
    primal = out.primal; dual = out.dual; comp = out.comp;
    gradientError = out.gradientError;
    dualCapacity = out.dualCapacity;
    notes = out.notes;
    passed = out.pass;
catch ME
    notes = [ME.identifier, ': ', ME.message];
end
if isempty(notes); notes = 'passed'; end
row = {caseId, passed, value, expectedValue, abs(value - expectedValue), ...
    totalShip, expectedShip, gapKg, expectedGap, primal, dual, comp, ...
    gradientError, dualCapacity, notes};
if passed && (primal > tol || comp > 1e-5 || (~isnan(dual) && dual > 1e-5))
    error('run_stage90a_terminal_recourse_tests:Residual', ...
        'Case %s has an excessive LP residual.', caseId);
end
end

function out = case_a()
p = base_params([20;20;20;20], [10;10;10;10], 20, 1);
[v,g,info] = terminal_value_and_subgradient_h2(p.I, p, 1);
out = summarize(v,0,info,0,0,g,zeros(4,1),'x=0 and no residual gap');
end

function out = case_b()
p = base_params([20;0;0;0], [0;8;8;0], 20, 1);
[v,g,info] = terminal_value_and_subgradient_h2(p.I, p, 1);
out = summarize(v,16,info,0,16,g,g,'spatially misplaced inventory is rebalanced');
end

function out = case_c()
p = base_params([5;0;0;0], [0;8;8;0], 20, 1);
[v,g,info] = terminal_value_and_subgradient_h2(p.I, p, 1);
out = summarize(v,5,info,11,11005,g,g,'redistribution cannot create hydrogen');
end

function out = case_d()
p = base_params([5;0;0;0], [0;8;8;0], 0, 1);
[v,g,info] = terminal_value_and_subgradient_h2(p.I, p, 1);
legacy = p; legacy.terminal_recourse_mode = 'DIRECT_GAP';
[v0,g0] = terminal_value_and_subgradient_h2(p.I, legacy, 1);
    out = summarize(v,0,info,16,16000,g,g0,'K=0 exactly matches direct-gap value and gradient');
out.expectedValue = v0;
out.pass = abs(v-v0) <= 1e-12 && max(abs(g-g0)) <= 1e-12 && ...
    info.total_ship_kg == 0;
end

function out = case_e()
p = base_params([20;0;0;0], [0;10;0;0], 20, 2000);
[v,g,info] = terminal_value_and_subgradient_h2(p.I, p, 1);
out = summarize(v,0,info,10,10000,g,g,'transport cost exceeds shortage penalty');
end

function out = case_f()
p = base_params([20;0;0;0], [0;8;8;0], 5, 1);
[v,g,info] = terminal_value_and_subgradient_h2(p.I, p, 1);
out = summarize(v,5,info,11,11005,g,g,'aggregate capacity binds and dual is reported');
out.pass = out.pass && info.capacity_binding && abs(info.dual_capacity) > 1e-7;
end

function out = case_g()
p = base_params([5;0;0;0], [0;8;8;0], 20, 5);
[v,g,info] = terminal_value_and_subgradient_h2(p.I, p, 1);
h = 1e-4;
pPlus = p; pPlus.I = p.I; pPlus.I(1) = pPlus.I(1) + h;
pMinus = p; pMinus.I = p.I; pMinus.I(1) = pMinus.I(1) - h;
vp = terminal_value_and_subgradient_h2(pPlus.I, pPlus, 1);
vm = terminal_value_and_subgradient_h2(pMinus.I, pMinus, 1);
fd = (vp - vm) / (2*h);
gradientError = abs(fd - g(1));
out = summarize(v,5,info,11,11025,g,g,'finite difference vs terminal dual');
out.gradientError = gradientError;
out.pass = out.pass && gradientError < 1e-4;
end

function out = case_h()
% A feasible spatial mismatch below K=160 must be fully rebalanced.
p = base_params([120;0;0;0], [0;70;50;0], 160, 1);
[v,g,info] = terminal_value_and_subgradient_h2(p.I, p, 1);
out = summarize(v,120,info,0,120,g,g, ...
    'subcapacity mismatch is not artificially truncated');
out.pass = out.pass && ~info.capacity_binding && info.total_ship_kg < p.K_terminal_kg;
end

function out = case_i()
% A mismatch requiring more than K=160 must bind the aggregate capacity.
p = base_params([200;0;0;0], [0;120;100;0], 160, 1);
[v,g,info] = terminal_value_and_subgradient_h2(p.I, p, 1);
out = summarize(v,160,info,60,60160,g,g, ...
    'over160 mismatch binds aggregate terminal capacity');
out.pass = out.pass && info.capacity_binding && abs(info.dual_capacity) > 1e-7;
end

function p = base_params(I, T, K, offDiagCost)
p = struct();
p.Ni = 4;
p.I = I(:);
p.TerminalLOH = T(:);
p.is_loh_demand_stage = true;
p.is_absorbing = false;
p.S = [2,1,6];
p.cost_reserve_shortage = 1000;
p.cost_transport_base = offDiagCost * (ones(4) - eye(4));
p.beta = 0;
p.use_beta_cost = false;
p.beta_transport_multiplier = 0;
p.htt_base_service_cost_yuan_per_kg = 0;
p.terminal_recourse_mode = 'TERMINAL_REDISTRIBUTION';
p.K_terminal_kg = K;
end

function out = summarize(value, expectedShip, info, expectedGap, expectedValue, grad, expectedGrad, note)
out = struct();
out.value = value;
out.expectedValue = expectedValue;
out.totalShip = info.total_ship_kg;
out.expectedShip = expectedShip;
out.gapKg = sum(info.shortage);
out.expectedGap = expectedGap;
out.primal = info.primal_residual;
out.dual = info.dual_residual;
out.comp = info.complementarity_residual;
out.gradientError = max(abs(grad(:) - expectedGrad(:)));
out.dualCapacity = get_field_or_zero(info, 'dual_capacity');
out.notes = note;
out.pass = abs(value - expectedValue) < 1e-5 && ...
    abs(info.total_ship_kg - expectedShip) < 1e-5 && ...
    abs(sum(info.shortage) - expectedGap) < 1e-5 && ...
    out.gradientError < 1e-5;
end

function value = get_field_or_zero(s, name)
if isfield(s, name); value = s.(name); else; value = 0; end
end
