function evalInfo = eval_h2(modelLib, params)
%EVAL_H2 Evaluate TerminalLOH-version H2 FA-MSP policy on OOS paths.

start_time = tic;
storeDecisions = isfield(params, 'store_eval_decisions') && params.store_eval_decisions;

if isfield(params, 'oosFile') && ~isempty(params.oosFile)
    oosFile = params.oosFile;
else
    oosFile = fullfile(params.dataDir, 'OOS.csv');
end

OS_paths = readmatrix(oosFile);
if size(OS_paths, 1) < params.nbOS
    error('eval_h2:InsufficientOOSRows', ...
        'OOS file has %d rows, but params.nbOS = %d.', size(OS_paths, 1), params.nbOS);
end
if size(OS_paths, 2) < params.T
    error('eval_h2:ShortOOSPath', ...
        'OOS file has %d columns, but params.T = %d.', size(OS_paths, 2), params.T);
end

nbOS = params.nbOS;
OS_paths = OS_paths(1:nbOS, 1:params.T);

stageCost = zeros(nbOS, params.T);
normalShortage = zeros(nbOS, params.T);
terminalReserveShortage = zeros(nbOS, params.T);
terminalCost = zeros(nbOS, params.T);
hitLOHDemand = false(nbOS, 1);
firstLOHDemandStage = zeros(nbOS, 1);
transportAmount = zeros(nbOS, params.T);
productionAmount = zeros(nbOS, params.T);
betaPath = zeros(nbOS, params.T);
terminalLOHTotal = zeros(nbOS, params.T);
finalLOH = zeros(nbOS, params.Ni);

if storeDecisions
    xval_store = cell(nbOS, params.T);
    eval_store = cell(nbOS, params.T);
    rval_store = cell(nbOS, params.T);
    fval_store = cell(nbOS, params.T);
    u_store = cell(nbOS, params.T);
    z_store = cell(nbOS, params.T);
end

for s = 1:nbOS
    xval = zeros(params.Ni, params.T);
    prev_x = params.x_0;
    absorbed = false;

    for t = 1:params.T
        k_t = OS_paths(s, t);
        betaPath(s, t) = params.beta(k_t);
        terminalLOHTotal(s, t) = sum(params.TerminalLOH(:, k_t));

        if absorbed
            xval(:, t) = prev_x;
            continue;
        end

        if params.is_dissipated(k_t)
            xval(:, t) = prev_x;
            absorbed = true;
            continue;
        end

        if params.is_loh_demand_stage(k_t)
            [tcost, tinfo] = eval_terminal_loh_h2(prev_x, params, k_t);
            stageCost(s, t) = tcost;
            terminalCost(s, t) = tcost;
            terminalReserveShortage(s, t) = sum(tinfo.shortage);
            xval(:, t) = prev_x;
            absorbed = true;
            hitLOHDemand(s) = true;
            firstLOHDemandStage(s) = t;
            continue;
        end

        if params.is_absorbing(k_t)
            xval(:, t) = prev_x;
            absorbed = true;
            continue;
        end

        modelLib.models{t, k_t} = update_rhs_h2( ...
            modelLib.models{t, k_t}, params, k_t, t, prev_x);
        sol = solve_stage_model_h2(modelLib.models{t, k_t});

        xval(:, t) = sol.xval;
        prev_x = sol.xval;
        stageCost(s, t) = sol.obj - sol.theta;
        normalShortage(s, t) = sum(sol.z_normal);
        transportAmount(s, t) = sum(sol.fval(:));
        productionAmount(s, t) = sum(sol.rval);

        if storeDecisions
            xval_store{s, t} = sol.xval;
            eval_store{s, t} = sol.eval;
            rval_store{s, t} = sol.rval;
            fval_store{s, t} = sol.fval;
            u_store{s, t} = sol.u_normal;
            z_store{s, t} = sol.z_normal;
        end
    end

    finalLOH(s, :) = xval(:, params.T).';
end

pathCost = sum(stageCost, 2);
oosMean = mean(pathCost);
oosStd = std(pathCost);
ciHalfWidth = 1.96 * oosStd / sqrt(nbOS);
ciLow = oosMean - ciHalfWidth;
ciHigh = oosMean + ciHalfWidth;

evalInfo = struct();
evalInfo.stageCost = stageCost;
evalInfo.objs = stageCost;
evalInfo.pathCost = pathCost;
evalInfo.oos_mean = oosMean;
evalInfo.fa_bar = oosMean;
evalInfo.ci_low = ciLow;
evalInfo.ci_high = ciHigh;
evalInfo.fa_low = ciLow;
evalInfo.fa_high = ciHigh;
evalInfo.oos_std = oosStd;
evalInfo.fa_std = oosStd;
evalInfo.ci_half_width = ciHalfWidth;
evalInfo.elapsed = toc(start_time);
evalInfo.nbOS_used = nbOS;

evalInfo.normal_shortage = normalShortage;
evalInfo.reserve_shortage = terminalReserveShortage;
evalInfo.terminal_reserve_shortage = terminalReserveShortage;
evalInfo.terminal_cost = terminalCost;
evalInfo.transport_amount = transportAmount;
evalInfo.production_amount = productionAmount;
evalInfo.final_loh = finalLOH;
evalInfo.beta_path = betaPath;
evalInfo.terminal_loh_path = terminalLOHTotal;

evalInfo.avg_normal_shortage = mean(sum(normalShortage, 2));
evalInfo.avg_reserve_shortage = mean(sum(terminalReserveShortage, 2));
evalInfo.avg_terminal_reserve_shortage = evalInfo.avg_reserve_shortage;
evalInfo.avg_terminal_cost = mean(sum(terminalCost, 2));
evalInfo.hit_loh_demand = hitLOHDemand;
evalInfo.hit_loh_demand_ratio = mean(hitLOHDemand);
evalInfo.first_loh_demand_stage = firstLOHDemandStage;
if any(hitLOHDemand)
    evalInfo.first_loh_demand_stage_distribution = accumarray( ...
        firstLOHDemandStage(hitLOHDemand), 1, [params.T, 1], @sum, 0);
else
    evalInfo.first_loh_demand_stage_distribution = zeros(params.T, 1);
end
evalInfo.avg_transport = mean(sum(transportAmount, 2));
evalInfo.avg_production = mean(sum(productionAmount, 2));
evalInfo.avg_final_loh_by_site = mean(finalLOH, 1);
evalInfo.avg_final_loh_total = mean(sum(finalLOH, 2));

if storeDecisions
    evalInfo.xval = xval_store;
    evalInfo.eval = eval_store;
    evalInfo.rval = rval_store;
    evalInfo.fval = fval_store;
    evalInfo.u_normal = u_store;
    evalInfo.z_normal = z_store;
end
end
