function summaryTbl = evaluate_stage71_policy_h2(modelLib, params)
%EVALUATE_STAGE71_POLICY_H2 Common-OOS evaluator with cost decomposition.

OS = readmatrix(params.oosFile);
if size(OS, 1) < 10000 || size(OS, 2) < params.T
    error('evaluate_stage71_policy_h2:BadOOS', ...
        'Frozen OOS must contain at least 10000 rows and params.T columns.');
end
OS = OS(1:10000, 1:params.T);
n = size(OS, 1);

reportedObjective = zeros(n, 1);
operatingCost = zeros(n, 1);
productionCost = zeros(n, 1);
transportCost = zeros(n, 1);
holdingCost = zeros(n, 1);
ordinaryShortageCost = zeros(n, 1);
terminalGapPenalty = zeros(n, 1);
production = zeros(n, 1);
htt = zeros(n, 1);
ordinaryShortage = zeros(n, 1);
finalInventory = zeros(n, params.Ni);
terminalHit = false(n, 1);
terminalStage = nan(n, 1);
terminalK = nan(n, 1);
terminalA = nan(n, 1);
terminalLoc = nan(n, 1);
terminalLf = nan(n, 1);
terminalState = nan(n, 1);
target = nan(n, params.Ni);
gap = nan(n, params.Ni);

for s = 1:n
    prevX = params.x_0(:);
    absorbed = false;
    for t = 1:params.T
        k = OS(s, t);
        if absorbed
            continue;
        end
        if params.is_dissipated(k)
            absorbed = true;
            continue;
        end
        if params.is_loh_demand_stage(k)
            target(s, :) = params.TerminalLOH(:, k).';
            gap(s, :) = max(0, target(s, :) - prevX.');
            terminalGapPenalty(s) = params.cost_reserve_shortage * sum(gap(s, :));
            terminalHit(s) = true;
            terminalStage(s) = t;
            terminalK(s) = k;
            terminalA(s) = params.S(k, 1);
            terminalLoc(s) = params.S(k, 2);
            terminalLf(s) = params.S(k, 3);
            terminalState(s) = (terminalA(s) - 2) * 7 + terminalLoc(s);
            absorbed = true;
            continue;
        end
        if params.is_absorbing(k)
            absorbed = true;
            continue;
        end

        modelLib.models{t, k} = update_rhs_h2( ...
            modelLib.models{t, k}, params, k, t, prevX);
        sol = solve_stage_model_h2(modelLib.models{t, k});
        beta = params.beta(k);
        if params.use_beta_cost
            costMat = params.cost_transport_base * ...
                (1 + params.beta_transport_multiplier * beta);
        else
            costMat = params.cost_transport_base;
        end
        cHolding = params.cost_holding * sum(sol.xval);
        cProduction = (params.cost_electricity_stage(t) + params.cost_el_om) * ...
            params.dt_h * sum(sol.eval);
        cTransport = sum(costMat .* sol.fval, 'all');
        cShortage = params.cost_normal_shortage * sum(sol.z_normal);
        rebuiltStage = cHolding + cProduction + cTransport + cShortage;
        modelStage = sol.obj - sol.theta;
        if abs(rebuiltStage - modelStage) > 1e-6 * max(1, abs(modelStage))
            error('evaluate_stage71_policy_h2:CostIdentity', ...
                'Path %d stage %d cost reconstruction failed.', s, t);
        end

        holdingCost(s) = holdingCost(s) + cHolding;
        productionCost(s) = productionCost(s) + cProduction;
        transportCost(s) = transportCost(s) + cTransport;
        ordinaryShortageCost(s) = ordinaryShortageCost(s) + cShortage;
        production(s) = production(s) + sum(sol.rval);
        htt(s) = htt(s) + sum(sol.fval, 'all');
        ordinaryShortage(s) = ordinaryShortage(s) + sum(sol.z_normal);
        prevX = sol.xval;
    end
    finalInventory(s, :) = prevX.';
    operatingCost(s) = holdingCost(s) + productionCost(s) + ...
        transportCost(s) + ordinaryShortageCost(s);
    reportedObjective(s) = operatingCost(s) + terminalGapPenalty(s);
end

pathId = (1:n).';
targetTotal = sum(target, 2);
gapTotal = sum(gap, 2);
finalTotal = sum(finalInventory, 2);
summaryTbl = table(pathId, double(terminalHit), terminalStage, terminalK, ...
    terminalA, terminalLoc, terminalLf, terminalState, ...
    production, htt, ordinaryShortage, finalTotal, ...
    finalInventory(:,1), finalInventory(:,2), finalInventory(:,3), finalInventory(:,4), ...
    targetTotal, target(:,1), target(:,2), target(:,3), target(:,4), ...
    gapTotal, gap(:,1), gap(:,2), gap(:,3), gap(:,4), ...
    operatingCost, reportedObjective, terminalGapPenalty, ...
    productionCost, transportCost, holdingCost, ordinaryShortageCost, ...
    'VariableNames', {'path_id','terminal_hit','terminal_stage','terminal_state_k', ...
    'a','loc','lf','terminal_state','production','htt','ordinary_shortage', ...
    'final_inventory','final_site1','final_site2','final_site3','final_site4', ...
    'terminal_loh_target','target_site1','target_site2','target_site3','target_site4', ...
    'terminal_gap','gap_site1','gap_site2','gap_site3','gap_site4', ...
    'operating_cost','reported_objective','terminal_gap_penalty', ...
    'production_cost','transport_cost','holding_cost','ordinary_shortage_cost'});
end
