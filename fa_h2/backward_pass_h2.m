function [modelLib, cutviolFlag] = backward_pass_h2(modelLib, params, xval, thetaval, in_sample)
%BACKWARD_PASS_H2 Add shared cuts with lf=Nc-1 LOH demand-stage values.
%
% Ordinary non-terminal states use the inventory balance RHS dual. Terminal
% LOH demand states use the analytic subgradient of the TerminalLOH shortage
% penalty. lf=Nc is only the zero-cost absorbing boundary.

cutviolFlag = 0;

for t = params.T:-1:2
    Q = zeros(params.K, 1);
    gState = zeros(params.K, params.Ni);
    sample_n = in_sample(t - 1);
    x_trial = xval(:, t - 1);

    for k = 1:params.K
        if params.is_dissipated(k)
            continue;
        elseif params.is_absorbing(k)
            % lf=Nc contributes Q=0,g=0; it does not create new LOH demand.
            continue;
        elseif params.is_loh_demand_stage(k)
            [Q(k), grad] = terminal_value_and_subgradient_h2(x_trial, params, k);
            gState(k, :) = grad(:).';
        else
            modelLib.models{t, k} = update_rhs_h2( ...
                modelLib.models{t, k}, params, k, t, x_trial);
            sol = solve_stage_model_h2(modelLib.models{t, k});
            Q(k) = sol.obj;
            gState(k, :) = sol.lambda.inventory_eq(:).';
        end
    end

    for n = 1:params.K
        if params.is_absorbing(n) || params.is_loh_demand_stage(n)
            continue;
        end
        if t - 1 == 1 && n ~= params.k_init
            continue;
        end

        weights = params.P_joint(n, :).';
        Qvalue = weights.' * Q;
        g = gState.' * weights;

        denom = max(1e-10, abs(thetaval(t - 1)));
        if n == sample_n && (Qvalue - thetaval(t - 1)) / denom > params.eps_tol
            cutviolFlag = 1;
        end

        alpha = Qvalue - g.' * x_trial;
        modelLib.models{t - 1, n} = add_cut_h2(modelLib.models{t - 1, n}, g, alpha);
    end
end
end
