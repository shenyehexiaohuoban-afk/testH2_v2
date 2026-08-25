function [terminalCost, terminalInfo] = eval_terminal_loh_h2(prev_x, params, k)
%EVAL_TERMINAL_LOH_H2 Evaluate the shared Stage-7 terminal semantics.

if params.is_loh_demand_stage(k)
    [terminalCost, ~, sharedInfo] = terminal_value_and_subgradient_h2( ...
        prev_x, params, k);
    target = sharedInfo.target;
    shortage = sharedInfo.shortage;
elseif params.is_absorbing(k)
    target = zeros(params.Ni, 1);
    shortage = zeros(params.Ni, 1);
    terminalCost = 0;
    sharedInfo = struct('terminal_recourse_mode','ABSORBING_ZERO', ...
        'x_ij',zeros(params.Ni * (params.Ni - 1),1),'Ihat',prev_x(:), ...
        'shipping_cost',0,'shortage_cost',0,'total_ship_kg',0, ...
        'capacity_kg',0,'primal_residual',0,'dual_residual',0, ...
        'complementarity_residual',0,'pairwise_road_mask_used',false);
else
    error('eval_terminal_loh_h2:NonTerminalState', ...
        'eval_terminal_loh_h2 called on a non-demand, non-absorbing state k=%d.', k);
end

terminalInfo = struct();
terminalInfo.k = k;
terminalInfo.S = params.S(k, :);
terminalInfo.target = target;
terminalInfo.shortage = shortage;
terminalInfo.cost = terminalCost;
terminalInfo.a = params.S(k, 1);
terminalInfo.loc = params.S(k, 2);
terminalInfo.lf = params.S(k, 3);
terminalInfo.terminal_recourse_mode = sharedInfo.terminal_recourse_mode;
terminalInfo.x_ij = sharedInfo.x_ij;
terminalInfo.Ihat = sharedInfo.Ihat;
terminalInfo.shipping_cost = sharedInfo.shipping_cost;
terminalInfo.shortage_cost = sharedInfo.shortage_cost;
terminalInfo.total_ship_kg = sharedInfo.total_ship_kg;
terminalInfo.capacity_kg = sharedInfo.capacity_kg;
terminalInfo.primal_residual = sharedInfo.primal_residual;
terminalInfo.dual_residual = sharedInfo.dual_residual;
terminalInfo.complementarity_residual = sharedInfo.complementarity_residual;
terminalInfo.pairwise_road_mask_used = sharedInfo.pairwise_road_mask_used;
end
