function [value, grad, info] = terminal_value_and_subgradient_h2(x_trial, params, k)
%TERMINAL_VALUE_AND_SUBGRADIENT_H2 Shared Stage-7 value/subgradient evaluator.
%
% DIRECT_GAP retains the legacy analytic value. TERMINAL_REDISTRIBUTION
% delegates to the same LP used by forward evaluation and returns the LP
% dual sensitivity with respect to the inventory state.

x_trial = x_trial(:);
if params.is_loh_demand_stage(k)
    target = params.TerminalLOH(:, k);
    mode = upper(string(get_opt(params, 'terminal_recourse_mode', 'DIRECT_GAP')));
    K = double(get_opt(params, 'K_terminal_kg', 0));
    if mode == "TERMINAL_REDISTRIBUTION" && K > 1e-12
        [value, grad, recourseInfo] = solve_terminal_redistribution_h2( ...
            x_trial, target, params, k);
        shortage = recourseInfo.shortage;
    else
        % Explicit K=0 fallback is required to reproduce the old result.
        shortage = max(0, target - x_trial);
        value = params.cost_reserve_shortage * sum(shortage);
        grad = zeros(params.Ni, 1);
        grad(x_trial < target - 1e-9) = -params.cost_reserve_shortage;
        recourseInfo = direct_gap_info(x_trial, target, shortage, K, ...
            params.cost_reserve_shortage);
    end
elseif params.is_absorbing(k)
    target = zeros(params.Ni, 1);
    shortage = zeros(params.Ni, 1);
    value = 0;
    grad = zeros(params.Ni, 1);
    recourseInfo = direct_gap_info(x_trial, target, shortage, 0, 0);
    recourseInfo.terminal_recourse_mode = 'ABSORBING_ZERO';
else
    error('terminal_value_and_subgradient_h2:NonTerminalState', ...
        'Terminal value requested for invalid non-demand state k=%d.', k);
end

info = struct();
info.k = k;
info.S = params.S(k, :);
info.target = target;
info.shortage = shortage;
info.value = value;
info.grad = grad;
info.recourse = recourseInfo;
info.terminal_recourse_mode = recourseInfo.terminal_recourse_mode;
info.x_ij = recourseInfo.x_ij;
info.Ihat = recourseInfo.Ihat;
info.shipping_cost = recourseInfo.shipping_cost;
info.shortage_cost = recourseInfo.shortage_cost;
info.total_ship_kg = recourseInfo.total_ship_kg;
info.capacity_kg = recourseInfo.capacity_kg;
info.capacity_binding = recourseInfo.capacity_binding;
if isfield(recourseInfo, 'dual_capacity')
    info.dual_capacity = recourseInfo.dual_capacity;
else
    info.dual_capacity = 0;
end
info.primal_residual = recourseInfo.primal_residual;
info.dual_residual = recourseInfo.dual_residual;
info.complementarity_residual = recourseInfo.complementarity_residual;
info.pairwise_road_mask_used = recourseInfo.pairwise_road_mask_used;
end

function info = direct_gap_info(I, T, shortage, K, penalty)
Ni = numel(I);
info = struct();
info.terminal_recourse_mode = 'DIRECT_GAP';
info.inventory = I;
info.target = T;
info.x_ij = zeros(Ni * (Ni - 1), 1);
info.g = shortage;
info.Ihat = I;
info.shortage = shortage;
info.shipping_cost = 0;
info.shortage_cost = penalty * sum(shortage);
info.total_ship_kg = 0;
info.capacity_kg = K;
info.capacity_binding = K <= 1e-12;
info.primal_residual = 0;
info.dual_residual = 0;
info.complementarity_residual = 0;
info.pairwise_road_mask_used = false;
info.transshipment_allowed = false;
end

function value = get_opt(s, name, defaultValue)
if isfield(s, name) && ~isempty(s.(name))
    value = s.(name);
else
    value = defaultValue;
end
end
