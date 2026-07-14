function diagInfo = diagnose_selected_paths_h2(selected, modelLib, params, OS_paths, opts, evalInfo)
%DIAGNOSE_SELECTED_PATHS_H2 Re-run selected OOS paths and build diagnostics.
%
% The function follows the fixed policy only. It does not add cuts, retrain,
% or change the model library used by the caller.

if nargin < 5 || isempty(opts)
    opts = struct();
end
if nargin < 6
    evalInfo = struct();
end

tol = getOpt(opts, 'diagnosticBalanceTol', 1e-5);
Ni = params.Ni;
T = params.T;

summary = selected;
timeseriesRows = {};
siteRows = {};
edgeRows = {};
costRows = {};
lohRows = {};
transitionRows = {};
transitionSummaryRows = {};
cutRows = {};

for rr = 1:height(selected)
    pathId = selected.path_id(rr);
    pathType = string(selected.path_type(rr));
    prev_x = params.x_0;
    absorbed = false;
    recomputedStageCost = zeros(1, T);

    for t = 1:T
        k = OS_paths(pathId, t);
        Srow = params.S(k, :);
        a = Srow(1);
        loc = Srow(2);
        lf = Srow(3);
        beta = params.beta(k);
        xBefore = prev_x(:);
        xAfter = xBefore;
        status = "normal";

        thetaValue = 0;
        ordinaryStageCost = 0;
        lohDemandCost = 0;
        stageCost = 0;
        production = zeros(Ni, 1);
        ePower = zeros(Ni, 1);
        uNormal = zeros(Ni, 1);
        zNormal = zeros(Ni, 1);
        f = zeros(Ni, Ni);
        terminalTarget = zeros(Ni, 1);
        terminalShortage = zeros(Ni, 1);

        if absorbed
            status = "post_absorb";
        elseif params.is_dissipated(k)
            status = "dissipated_absorb";
            absorbed = true;
        elseif params.is_loh_demand_stage(k)
            status = "loh_demand_stage";
            [lohDemandCost, terminalInfo] = eval_terminal_loh_h2(xBefore, params, k);
            terminalTarget = terminalInfo.target;
            terminalShortage = terminalInfo.shortage;
            stageCost = lohDemandCost;
            absorbed = true;
        elseif params.is_absorbing(k)
            status = "absorbing_lfNc";
            absorbed = true;
        else
            localModel = update_rhs_h2(modelLib.models{t, k}, params, k, t, xBefore);
            sol = solve_stage_model_h2(localModel);
            xAfter = sol.xval;
            thetaValue = sol.theta;
            stageCost = sol.obj - sol.theta;
            ordinaryStageCost = stageCost;
            production = sol.rval;
            ePower = sol.eval;
            uNormal = sol.u_normal;
            zNormal = sol.z_normal;
            f = sol.fval;
            prev_x = xAfter;

            [newTransRows, newTransSummary] = build_transition_expectation_rows( ...
                pathId, pathType, t, k, params);
            transitionRows = [transitionRows; newTransRows]; %#ok<AGROW>
            transitionSummaryRows = [transitionSummaryRows; newTransSummary]; %#ok<AGROW>

            cutRows = [cutRows; build_cut_marginal_rows( ...
                pathId, pathType, t, k, a, loc, lf, iif_empty(localModel, modelLib.models{t, k}), ...
                xAfter, thetaValue, params.Ni)]; %#ok<AGROW>
        end

        if status ~= "normal"
            xAfter = xBefore;
        end
        recomputedStageCost(t) = stageCost;

        transportIn = sum(f, 1).';
        transportOut = sum(f, 2);
        terminalSurplus = max(0, xBefore - terminalTarget);
        deltaX = xAfter - xBefore;
        balanceResidual = xAfter - (xBefore + production + transportIn - transportOut - uNormal);

        if any(abs(balanceResidual) > tol) && status == "normal"
            warning('diagnose_selected_paths_h2:BalanceResidual', ...
                'Path %d stage %d balance residual max %.3g.', ...
                pathId, t, max(abs(balanceResidual)));
        end
        if (status == "absorbing_lfNc" || status == "post_absorb") && abs(stageCost) > 1e-8
            warning('diagnose_selected_paths_h2:AbsorbingCost', ...
                'Path %d stage %d has nonzero absorbing/post-absorb cost %.6g.', ...
                pathId, t, stageCost);
        end
        if status == "loh_demand_stage" && sum(terminalTarget) <= 1e-9 && a > 1
            warning('diagnose_selected_paths_h2:ZeroTerminalLOH', ...
                'Path %d stage %d is LOH demand but TerminalLOH is zero.', pathId, t);
        end

        timeseriesRows(end + 1, :) = {pathId, pathType, t, k, a, loc, lf, status, beta, ...
            stageCost, ordinaryStageCost, lohDemandCost, thetaValue, ...
            sum(xBefore), sum(xAfter), sum(deltaX), sum(production), ...
            sum(uNormal), sum(zNormal), sum(transportIn), sum(transportOut), ...
            sum(f(:)), sum(terminalTarget), sum(terminalShortage), ...
            sum(terminalSurplus)}; %#ok<AGROW>

        if status == "normal"
            [holdingCost, elecCost, omCost, transportCost, normalShortCost] = ...
                compute_cost_breakdown(params, t, k, xAfter, ePower, f, zNormal);
        else
            holdingCost = 0;
            elecCost = 0;
            omCost = 0;
            transportCost = 0;
            normalShortCost = 0;
        end
        costRows(end + 1, :) = {pathId, pathType, t, k, a, loc, lf, status, ...
            holdingCost, elecCost, omCost, transportCost, normalShortCost, ...
            lohDemandCost, thetaValue, stageCost, stageCost + thetaValue}; %#ok<AGROW>

        for i = 1:Ni
            siteRows(end + 1, :) = {pathId, pathType, t, k, a, loc, lf, status, i, ...
                xBefore(i), production(i), ePower(i), params.D_normal(i, t), ...
                uNormal(i), zNormal(i), transportIn(i), transportOut(i), ...
                xAfter(i), deltaX(i), balanceResidual(i), terminalTarget(i), ...
                terminalShortage(i), terminalSurplus(i)}; %#ok<AGROW>

            if status == "loh_demand_stage"
                lohRows(end + 1, :) = {pathId, pathType, t, k, a, loc, lf, i, ...
                    xBefore(i), terminalTarget(i), terminalShortage(i), terminalSurplus(i), ...
                    sum(xBefore), sum(terminalTarget), sum(terminalShortage), ...
                    sum(terminalSurplus)}; %#ok<AGROW>
            end
        end

        for i = 1:Ni
            for j = 1:Ni
                if i == j
                    continue;
                end
                baseCost = params.cost_transport_base(i, j);
                betaCost = baseCost * (1 + params.beta_transport_multiplier * beta);
                edgeFlow = f(i, j);
                edgeRows(end + 1, :) = {pathId, pathType, t, k, a, loc, lf, status, ...
                    i, j, edgeFlow, params.site_to_site_road_km(i, j), ...
                    baseCost, beta, betaCost, betaCost * edgeFlow}; %#ok<AGROW>
            end
        end
    end

    if isfield(evalInfo, 'pathCost') && pathId <= numel(evalInfo.pathCost)
        diffVal = abs(sum(recomputedStageCost) - evalInfo.pathCost(pathId));
        if diffVal > 1e-4
            warning('diagnose_selected_paths_h2:PathCostMismatch', ...
                'Path %d diagnostic cost differs from evalInfo by %.6g.', pathId, diffVal);
        end
    end
end

diagInfo = struct();
diagInfo.selected_summary = enrich_selected_summary_h2(summary, lohRows, params);
diagInfo.timeseries = cell2table_or_empty(timeseriesRows, ...
    {'path_id', 'path_type', 't', 'k', 'a', 'loc', 'lf', 'status', 'beta', ...
    'stage_cost', 'ordinary_stage_cost', 'loh_demand_cost', 'theta_value', ...
    'x_total_before', 'x_total_after', 'delta_x_total', 'production_total', ...
    'normal_served_total', 'normal_shortage_total', 'htt_in_total', ...
    'htt_out_total', 'htt_transport_total', 'TerminalLOH_total', ...
    'terminal_shortage_total', 'terminal_surplus_total'});
diagInfo.site_balance = cell2table_or_empty(siteRows, ...
    {'path_id', 'path_type', 't', 'k', 'a', 'loc', 'lf', 'status', 'site_id', ...
    'x_before', 'production_r', 'electrolyzer_power_e', 'normal_demand', ...
    'normal_served', 'normal_shortage', 'transport_in', 'transport_out', ...
    'x_after', 'delta_x', 'balance_residual', 'TerminalLOH_site', ...
    'terminal_shortage_site', 'terminal_surplus_site'});
diagInfo.transport_edges = cell2table_or_empty(edgeRows, ...
    {'path_id', 'path_type', 't', 'k', 'a', 'loc', 'lf', 'status', ...
    'from_site', 'to_site', 'f_ij', 'distance_km', 'base_cost_per_kg', ...
    'beta', 'beta_adjusted_cost_per_kg', 'edge_transport_cost'});
diagInfo.cost_breakdown = cell2table_or_empty(costRows, ...
    {'path_id', 'path_type', 't', 'k', 'a', 'loc', 'lf', 'status', ...
    'holding_cost', 'production_electricity_cost', 'electrolyzer_om_cost', ...
    'transport_cost', 'normal_shortage_cost', 'loh_demand_cost', ...
    'theta_value', 'stage_cost_without_theta', 'stage_cost_with_theta_if_available'});

if isempty(lohRows)
    diagInfo.loh_demand_detail = cell2table(cell(0, 16), 'VariableNames', ...
        {'path_id', 'path_type', 'demand_time', 'k', 'a', 'loc', 'lf', 'site_id', ...
        'x_before_demand', 'TerminalLOH_site', 'terminal_shortage_site', ...
        'terminal_surplus_site', 'x_total_before_demand', 'TerminalLOH_total', ...
        'terminal_shortage_total', 'terminal_surplus_total'});
else
    diagInfo.loh_demand_detail = cell2table(lohRows, 'VariableNames', ...
        {'path_id', 'path_type', 'demand_time', 'k', 'a', 'loc', 'lf', 'site_id', ...
        'x_before_demand', 'TerminalLOH_site', 'terminal_shortage_site', ...
        'terminal_surplus_site', 'x_total_before_demand', 'TerminalLOH_total', ...
        'terminal_shortage_total', 'terminal_surplus_total'});
end

diagInfo.transition_expectation = cell2table_or_empty(transitionRows, ...
    {'path_id', 'path_type', 't', 'current_k', 'current_a', 'current_loc', ...
    'current_lf', 'next_k', 'next_a', 'next_loc', 'next_lf', ...
    'transition_probability', 'is_loh_demand_stage_next', ...
    'TerminalLOH_site1_next', 'TerminalLOH_site2_next', ...
    'TerminalLOH_site3_next', 'TerminalLOH_site4_next', ...
    'TerminalLOH_total_next', 'weighted_TerminalLOH_site1', ...
    'weighted_TerminalLOH_site2', 'weighted_TerminalLOH_site3', ...
    'weighted_TerminalLOH_site4', 'weighted_TerminalLOH_total'});
diagInfo.transition_expectation_summary = cell2table_or_empty(transitionSummaryRows, ...
    {'path_id', 'path_type', 't', 'current_k', 'current_a', 'current_loc', ...
    'current_lf', 'P_next_loh_demand_stage', ...
    'E_TerminalLOH_site1_next', 'E_TerminalLOH_site2_next', ...
    'E_TerminalLOH_site3_next', 'E_TerminalLOH_site4_next', ...
    'E_TerminalLOH_total_next'});
diagInfo.cut_marginal_value = cell2table_or_empty(cutRows, ...
    {'path_id', 'path_type', 't', 'k', 'a', 'loc', 'lf', 'site_id', ...
    'x_site', 'theta_value', 'active_cut_id', 'active_cut_rhs', ...
    'approx_future_value_gradient', 'marginal_value_of_1kg_LOH', ...
    'active_cut_count'});
end

function [detailRows, summaryRows] = build_transition_expectation_rows(pathId, pathType, t, k, params)
Srow = params.S(k, :);
probs = params.P_joint(k, :).';
nextIds = find(probs > 1e-12);
detailRows = cell(numel(nextIds), 23);
expected = zeros(4, 1);
probDemand = 0;

for rr = 1:numel(nextIds)
    nk = nextIds(rr);
    p = probs(nk);
    nS = params.S(nk, :);
    target4 = site_vector4(params.TerminalLOH(:, nk));
    weighted4 = p * target4;
    expected = expected + weighted4;
    if params.is_loh_demand_stage(nk)
        probDemand = probDemand + p;
    end
    detailRows(rr, :) = {pathId, pathType, t, k, Srow(1), Srow(2), Srow(3), ...
        nk, nS(1), nS(2), nS(3), p, params.is_loh_demand_stage(nk), ...
        target4(1), target4(2), target4(3), target4(4), sum(target4), ...
        weighted4(1), weighted4(2), weighted4(3), weighted4(4), sum(weighted4)};
end

summaryRows = {pathId, pathType, t, k, Srow(1), Srow(2), Srow(3), ...
    probDemand, expected(1), expected(2), expected(3), expected(4), sum(expected)};
end

function rows = build_cut_marginal_rows(pathId, pathType, t, k, a, loc, lf, model, xSite, thetaValue, Ni)
if isempty(model)
    rows = cell(0, 15);
    return;
end

[activeCutId, activeCutRhs, grad, activeCutCount] = identify_active_cut(model, xSite, thetaValue);
rows = cell(Ni, 15);
for i = 1:Ni
    rows(i, :) = {pathId, pathType, t, k, a, loc, lf, i, xSite(i), thetaValue, ...
        activeCutId, activeCutRhs, grad(i), -grad(i), activeCutCount};
end
end

function [activeCutId, activeCutRhs, grad, activeCutCount] = identify_active_cut(model, xSite, thetaValue)
Ni = numel(model.idx.x);
grad = nan(Ni, 1);
activeCutId = NaN;
activeCutRhs = NaN;
activeCutCount = 0;

baseRows = max(model.rowMap.htt_capacity);
cutRows = (baseRows + 1):size(model.A, 1);
if isempty(cutRows)
    warning('diagnose_selected_paths_h2:NoCutsForMarginalValue', ...
        'No future-value cuts found for stage %d.', model.t);
    return;
end

slopes = model.A(cutRows, model.idx.x);
rhs = -model.b(cutRows) + slopes * xSite(:);
rhsMax = max(rhs);
tol = 1e-6 * max(1, abs(rhsMax));
candidates = find(abs(rhs - rhsMax) <= tol);
[~, rel] = min(abs(rhs(candidates) - thetaValue));
chosenLocal = candidates(rel);
activeCutId = cutRows(chosenLocal);
activeCutRhs = rhs(chosenLocal);
grad = slopes(chosenLocal, :).';
activeCutCount = numel(candidates);
end

function out = site_vector4(x)
out = zeros(4, 1);
n = min(4, numel(x));
out(1:n) = x(1:n);
end

function summary = enrich_selected_summary_h2(summary, lohRows, params)
n = height(summary);
summary.terminal_load_mode = repmat(string(params.terminal_load_mode), n, 1);
summary.TerminalLOH_total_at_demand = nan(n, 1);
summary.x_total_before_demand = nan(n, 1);
summary.shortage_total_at_demand = nan(n, 1);

if isempty(lohRows)
    return;
end
lohTbl = cell2table(lohRows, 'VariableNames', ...
    {'path_id', 'path_type', 'demand_time', 'k', 'a', 'loc', 'lf', 'site_id', ...
    'x_before_demand', 'TerminalLOH_site', 'terminal_shortage_site', ...
    'terminal_surplus_site', 'x_total_before_demand', 'TerminalLOH_total', ...
    'terminal_shortage_total', 'terminal_surplus_total'});
for rr = 1:n
    rows = lohTbl.path_id == summary.path_id(rr);
    if any(rows)
        first = find(rows, 1, 'first');
        summary.TerminalLOH_total_at_demand(rr) = lohTbl.TerminalLOH_total(first);
        summary.x_total_before_demand(rr) = lohTbl.x_total_before_demand(first);
        summary.shortage_total_at_demand(rr) = lohTbl.terminal_shortage_total(first);
    end
end
end

function tbl = cell2table_or_empty(rows, varNames)
if isempty(rows)
    tbl = cell2table(cell(0, numel(varNames)), 'VariableNames', varNames);
else
    tbl = cell2table(rows, 'VariableNames', varNames);
end
end

function modelOut = iif_empty(candidate, fallback)
if isempty(candidate)
    modelOut = fallback;
else
    modelOut = candidate;
end
end

function [holdingCost, elecCost, omCost, transportCost, normalShortCost] = ...
    compute_cost_breakdown(params, t, k, xAfter, ePower, f, zNormal)
holdingCost = params.cost_holding * sum(xAfter);
elecCost = params.cost_electricity_stage(t) * params.dt_h * sum(ePower);
omCost = params.cost_el_om * params.dt_h * sum(ePower);
beta = params.beta(k);
if params.use_beta_cost
    costMat = params.cost_transport_base * (1 + params.beta_transport_multiplier * beta);
else
    costMat = params.cost_transport_base;
end
transportCost = sum(costMat(:) .* f(:));
normalShortCost = params.cost_normal_shortage * sum(zNormal);
end

function val = getOpt(opts, fieldName, defaultVal)
if isfield(opts, fieldName)
    val = opts.(fieldName);
else
    val = defaultVal;
end
end
