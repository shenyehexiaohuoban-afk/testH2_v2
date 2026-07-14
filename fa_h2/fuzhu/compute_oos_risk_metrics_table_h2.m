function riskTbl = compute_oos_risk_metrics_table_h2(evalInfo)
%COMPUTE_OOS_RISK_METRICS_TABLE_H2 Empirical OOS cost risk metrics.
%
% CVaR here is a post-processing top-tail average. It is not part of the
% MSP objective or cut generation.

if ~isfield(evalInfo, 'pathCost') || isempty(evalInfo.pathCost)
    error('compute_oos_risk_metrics_table_h2:MissingPathCost', ...
        'evalInfo.pathCost is required for OOS risk metrics.');
end

pathCost = evalInfo.pathCost(:);
N = numel(pathCost);
terminalShortage = zeros(N, 1);
terminalCost = zeros(N, 1);
hitDemand = false(N, 1);

if isfield(evalInfo, 'terminal_reserve_shortage')
    terminalShortage = sum(evalInfo.terminal_reserve_shortage, 2);
end
if isfield(evalInfo, 'terminal_cost')
    terminalCost = sum(evalInfo.terminal_cost, 2);
end
if isfield(evalInfo, 'hit_loh_demand')
    hitDemand = logical(evalInfo.hit_loh_demand(:));
end

[VaR90, CVaR90] = empirical_var_cvar(pathCost, 0.90);
[VaR95, CVaR95] = empirical_var_cvar(pathCost, 0.95);
[VaR99, CVaR99] = empirical_var_cvar(pathCost, 0.99);

tailN5 = max(1, ceil(0.05 * N));
[~, descOrd] = sort(pathCost, 'descend');
topIdx = descOrd(1:tailN5);

riskTbl = table( ...
    mean(pathCost), std(pathCost), min(pathCost), max(pathCost), ...
    VaR90, CVaR90, VaR95, CVaR95, VaR99, CVaR99, ...
    mean(terminalShortage), max(terminalShortage), ...
    mean(pathCost(topIdx)), mean(terminalShortage(topIdx)), ...
    mean(terminalCost(topIdx)), mean(hitDemand), ...
    'VariableNames', {'mean_cost', 'std_cost', 'min_cost', 'max_cost', ...
    'VaR_90', 'CVaR_90', 'VaR_95', 'CVaR_95', 'VaR_99', 'CVaR_99', ...
    'mean_terminal_shortage', 'max_terminal_shortage', ...
    'top5pct_avg_cost', 'top5pct_avg_terminal_shortage', ...
    'top5pct_avg_terminal_cost', 'hit_loh_demand_ratio'});
end

function [VaR, CVaR] = empirical_var_cvar(pathCost, alpha)
N = numel(pathCost);
asc = sort(pathCost, 'ascend');
varIdx = min(N, max(1, ceil(alpha * N)));
VaR = asc(varIdx);
tailN = max(1, ceil((1 - alpha) * N));
desc = sort(pathCost, 'descend');
CVaR = mean(desc(1:tailN));
end
