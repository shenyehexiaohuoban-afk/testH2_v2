function [modelLib, xval, thetaval, lb, in_sample, forwardInfo] = forward_pass_h2(modelLib, params, lb, xval, thetaval)
%FORWARD_PASS_H2 Run one sampled forward pass for TerminalLOH H2 FA-MSP.

in_sample = zeros(params.T, 1);
stageCost = zeros(params.T, 1);
terminalShortage = zeros(params.Ni, params.T);
status = strings(params.T, 1);
k_t = params.k_init;
in_sample(1) = k_t;
absorbed = false;

for t = 1:params.T
    if t > 1
        k_t = mc_sample(in_sample(t - 1), params.P_joint);
        in_sample(t) = k_t;
        prev_x = xval(:, t - 1);
    else
        prev_x = params.x_0;
    end

    if absorbed
        xval(:, t) = prev_x;
        status(t) = "post_absorb";
        continue;
    end

    if params.is_dissipated(k_t)
        xval(:, t) = prev_x;
        absorbed = true;
        status(t) = "dissipated_absorb";
        continue;
    end

    if params.is_loh_demand_stage(k_t)
        [terminalCost, terminalInfo] = eval_terminal_loh_h2(prev_x, params, k_t);
        stageCost(t) = terminalCost;
        terminalShortage(:, t) = terminalInfo.shortage;
        xval(:, t) = prev_x;
        absorbed = true;
        status(t) = "loh_demand_stage";
        continue;
    end

    if params.is_absorbing(k_t)
        xval(:, t) = prev_x;
        absorbed = true;
        status(t) = "absorbing_lfNc";
        continue;
    end

    modelLib.models{t, k_t} = update_rhs_h2( ...
        modelLib.models{t, k_t}, params, k_t, t, prev_x);
    sol = solve_stage_model_h2(modelLib.models{t, k_t});

    xval(:, t) = sol.xval;
    thetaval(t) = sol.theta;
    stageCost(t) = sol.obj - sol.theta;
    status(t) = "normal";

    if t == 1
        lb = sol.obj;
    end
end

forwardInfo = struct();
forwardInfo.stageCost = stageCost;
forwardInfo.terminalShortage = terminalShortage;
forwardInfo.status = status;
forwardInfo.in_sample = in_sample;
end
