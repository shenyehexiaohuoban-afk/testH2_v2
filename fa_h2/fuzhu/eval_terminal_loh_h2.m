function [terminalCost, terminalInfo] = eval_terminal_loh_h2(prev_x, params, k)
%EVAL_TERMINAL_LOH_H2 Evaluate LOH reserve adequacy at lf=Nc-1.
%
% Terminal stage rules:
%   lf=Nc-1 is the H2 LOH demand/check stage, corresponding to the original
%   FA-MSP lf=Nc-1 demand realization stage.
%   lf=Nc is a zero-cost absorbing state and does not create new LOH demand.

if params.is_loh_demand_stage(k)
    target = params.TerminalLOH(:, k);
    shortage = max(0, target - prev_x(:));
    terminalCost = params.cost_reserve_shortage * sum(shortage);
elseif params.is_absorbing(k)
    target = zeros(params.Ni, 1);
    shortage = zeros(params.Ni, 1);
    terminalCost = 0;
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
end
