function [summaryTbl, httTbl] = evaluate_stage73_policy_detailed_h2(modelLib, params, scheme, terminalMode, nPaths)
%EVALUATE_STAGE73_POLICY_DETAILED_H2 Frozen-OOS evaluator with directed HTT.

if nargin < 5 || isempty(nPaths); nPaths = 10000; end

raw = readtable(params.oosFile);
names = string(raw.Properties.VariableNames);
needed = "k_t" + (1:params.T);
if ~all(ismember(needed, names)) || height(raw) < nPaths
    error('evaluate_stage73_policy_detailed_h2:BadOOS', ...
        'Frozen OOS must contain k_t1..k_t%d and at least 10000 rows.', params.T);
end
OS = table2array(raw(1:nPaths, cellstr(needed)));
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
terminalState = nan(n, 1);
target = nan(n, params.Ni);
gap = nan(n, params.Ni);

maxRows = n * 6 * params.Ni * (params.Ni - 1);
pathCol = zeros(maxRows, 1); stageCol = zeros(maxRows, 1);
kCol = zeros(maxRows, 1); betaCol = zeros(maxRows, 1);
capCol = zeros(maxRows, 1); totalCol = zeros(maxRows, 1);
utilCol = zeros(maxRows, 1); originCol = zeros(maxRows, 1);
destCol = zeros(maxRows, 1); flowCol = zeros(maxRows, 1);
distanceCol = zeros(maxRows, 1); baseUnitCol = zeros(maxRows, 1);
actualUnitCol = zeros(maxRows, 1); costCol = zeros(maxRows, 1);
row = 0;

for s = 1:n
    prevX = params.x_0(:);
    absorbed = false;
    for t = 1:params.T
        k = OS(s, t);
        if absorbed; continue; end
        if params.is_dissipated(k) || params.is_absorbing(k) && ~params.is_loh_demand_stage(k)
            absorbed = true; continue;
        end
        if params.is_loh_demand_stage(k)
            target(s, :) = params.TerminalLOH(:, k).';
            gap(s, :) = max(0, target(s, :) - prevX.');
            terminalGapPenalty(s) = params.cost_reserve_shortage * sum(gap(s, :));
            terminalHit(s) = true; terminalStage(s) = t; terminalK(s) = k;
            terminalState(s) = (params.S(k,1)-2)*7 + params.S(k,2);
            absorbed = true; continue;
        end

        modelLib.models{t, k} = update_rhs_h2(modelLib.models{t, k}, params, k, t, prevX);
        sol = solve_stage_model_h2(modelLib.models{t, k});
        beta = params.beta(k);
        available = params.htt_capacity_base;
        if params.use_beta_capacity; available = max(0, (1-beta)*available); end
        costMat = params.cost_transport_base;
        if params.use_beta_cost
            costMat = costMat * (1 + params.beta_transport_multiplier * beta);
        end
        totalFlow = sum(sol.fval, 'all');
        util = totalFlow / available;
        cHolding = params.cost_holding * sum(sol.xval);
        cProduction = (params.cost_electricity_stage(t) + params.cost_el_om) * params.dt_h * sum(sol.eval);
        cTransport = sum(costMat .* sol.fval, 'all');
        cShortage = params.cost_normal_shortage * sum(sol.z_normal);
        rebuiltStage = cHolding + cProduction + cTransport + cShortage;
        modelStage = sol.obj - sol.theta;
        if abs(rebuiltStage - modelStage) > 1e-6 * max(1, abs(modelStage))
            error('evaluate_stage73_policy_detailed_h2:CostIdentity', ...
                'Path %d stage %d cost reconstruction failed.', s, t);
        end
        if util > 1 + 1e-7
            error('evaluate_stage73_policy_detailed_h2:CapacityViolation', ...
                'Path %d stage %d utilization exceeds one.', s, t);
        end

        for i = 1:params.Ni
            for j = 1:params.Ni
                if i == j; continue; end
                row = row + 1;
                pathCol(row)=s; stageCol(row)=t; kCol(row)=k; betaCol(row)=beta;
                capCol(row)=available; totalCol(row)=totalFlow; utilCol(row)=util;
                originCol(row)=i; destCol(row)=j; flowCol(row)=sol.fval(i,j);
                distanceCol(row)=params.site_to_site_road_km(i,j);
                baseUnitCol(row)=params.cost_transport_base(i,j);
                actualUnitCol(row)=costMat(i,j);
                costCol(row)=costMat(i,j)*sol.fval(i,j);
            end
        end

        holdingCost(s)=holdingCost(s)+cHolding;
        productionCost(s)=productionCost(s)+cProduction;
        transportCost(s)=transportCost(s)+cTransport;
        ordinaryShortageCost(s)=ordinaryShortageCost(s)+cShortage;
        production(s)=production(s)+sum(sol.rval);
        htt(s)=htt(s)+totalFlow;
        ordinaryShortage(s)=ordinaryShortage(s)+sum(sol.z_normal);
        prevX=sol.xval;
    end
    finalInventory(s,:)=prevX.';
    operatingCost(s)=holdingCost(s)+productionCost(s)+transportCost(s)+ordinaryShortageCost(s);
    reportedObjective(s)=operatingCost(s)+terminalGapPenalty(s);
end

pathId=(1:n).'; finalTotal=sum(finalInventory,2); targetTotal=sum(target,2); gapTotal=sum(gap,2);
summaryTbl=table(pathId,double(terminalHit),terminalStage,terminalK,terminalState, ...
    production,htt,ordinaryShortage,finalTotal, ...
    finalInventory(:,1),finalInventory(:,2),finalInventory(:,3),finalInventory(:,4), ...
    targetTotal,target(:,1),target(:,2),target(:,3),target(:,4), ...
    gapTotal,gap(:,1),gap(:,2),gap(:,3),gap(:,4), ...
    operatingCost,reportedObjective,terminalGapPenalty,productionCost,transportCost,holdingCost,ordinaryShortageCost, ...
    repmat(string(scheme),n,1),repmat(string(terminalMode),n,1), ...
    'VariableNames', {'path_id','terminal_hit','terminal_stage','terminal_state_k','terminal_state', ...
    'production','htt','ordinary_shortage','final_inventory', ...
    'final_site1','final_site2','final_site3','final_site4', ...
    'terminal_loh_target','target_site1','target_site2','target_site3','target_site4', ...
    'terminal_gap','gap_site1','gap_site2','gap_site3','gap_site4', ...
    'operating_cost','reported_objective','terminal_gap_penalty','production_cost', ...
    'transport_cost','holding_cost','ordinary_shortage_cost','scheme','terminal_mode'});

keep=1:row;
httTbl=table(repmat(string(scheme),row,1),repmat(string(terminalMode),row,1), ...
    pathCol(keep),stageCol(keep),kCol(keep),betaCol(keep),capCol(keep), ...
    totalCol(keep),utilCol(keep),originCol(keep),destCol(keep),flowCol(keep), ...
    distanceCol(keep),baseUnitCol(keep),actualUnitCol(keep),costCol(keep), ...
    'VariableNames', {'scheme','terminal_mode','path_id','stage','state_k','beta', ...
    'effective_htt_capacity_kg','total_htt_stage_kg','htt_utilization', ...
    'origin_site','destination_site','flow_kg','distance_km', ...
    'base_unit_cost_yuan_per_kg','actual_unit_cost_yuan_per_kg','transport_cost_yuan'});
end
