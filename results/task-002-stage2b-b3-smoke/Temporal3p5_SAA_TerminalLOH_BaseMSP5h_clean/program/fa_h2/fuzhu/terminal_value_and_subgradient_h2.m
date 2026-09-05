function [value, grad, info] = terminal_value_and_subgradient_h2(x_trial, params, k)
%TERMINAL_VALUE_AND_SUBGRADIENT_H2 LOH demand-stage value and subgradient.
%
% Terminal value is a convex piecewise-linear penalty for insufficient LOH:
%   V(x) = p * sum_i max(0, TerminalLOH_i(k) - x_i).
% Its subgradient is used in the SDDP/FA cut. Cost information is propagated
% from lf=Nc-1 demand-stage value; lf=Nc contributes zero future value as
% the absorbing boundary. At equality we choose 0 to avoid an unnecessarily
% steep cut.

if params.is_loh_demand_stage(k)
    target = params.TerminalLOH(:, k);
    x_trial = x_trial(:);
    shortage = max(0, target - x_trial);
    value = params.cost_reserve_shortage * sum(shortage);
    grad = zeros(params.Ni, 1);
    grad(x_trial < target - 1e-9) = -params.cost_reserve_shortage;
elseif params.is_absorbing(k)
    target = zeros(params.Ni, 1);
    shortage = zeros(params.Ni, 1);
    value = 0;
    grad = zeros(params.Ni, 1);
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
end
