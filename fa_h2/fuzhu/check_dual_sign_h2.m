function report = check_dual_sign_h2(modelLib, params)
%CHECK_DUAL_SIGN_H2 Check ordinary inventory RHS duals and terminal gradient.

delta = 1e-4;
if isfield(params, 'dual_check_delta')
    delta = params.dual_check_delta;
end

report = struct();
report.inventory_checked = false;
report.terminal_checked = false;

for t = 2:params.T
    for k = 1:params.K
        if params.is_absorbing(k) || isempty(modelLib.models{t, k})
            continue;
        end

        prev_x = min(params.x_cap(:) * 0.5, max(params.x_0(:), params.x_min(:)));
        model0 = update_rhs_h2(modelLib.models{t, k}, params, k, t, prev_x);
        sol0 = solve_stage_model_h2(model0);
        [~, site] = max(abs(sol0.lambda.inventory_eq));
        if abs(sol0.lambda.inventory_eq(site)) < 1e-8
            site = 1;
        end

        model1 = model0;
        model1.beq(model1.rowMap.inventory_eq(site)) = ...
            model1.beq(model1.rowMap.inventory_eq(site)) + delta;
        sol1 = solve_stage_model_h2(model1);

        finiteDiff = (sol1.obj - sol0.obj) / delta;
        extractedDual = sol0.lambda.inventory_eq(site);
        report.inventory_checked = true;
        report.inventory_finiteDiff = finiteDiff;
        report.inventory_extractedDual = extractedDual;
        fprintf('H2 inventory RHS finiteDiff = %.12g\n', finiteDiff);
        fprintf('H2 inventory extractedDual = %.12g\n', extractedDual);
        break;
    end
    if report.inventory_checked
        break;
    end
end

terminalStates = find(params.is_loh_demand_stage, 1, 'first');
if ~isempty(terminalStates)
    k = terminalStates;
    x0 = max(0, params.TerminalLOH(:, k) - 1);
    [value0, grad] = terminal_value_and_subgradient_h2(x0, params, k);
    site = find(grad < 0, 1, 'first');
    if ~isempty(site)
        x1 = x0;
        x1(site) = x1(site) + delta;
        value1 = terminal_value_and_subgradient_h2(x1, params, k);
        finiteDiff = (value1 - value0) / delta;
        report.terminal_checked = true;
        report.terminal_finiteDiff = finiteDiff;
        report.terminal_grad = grad(site);
        fprintf('H2 terminal finiteDiff = %.12g\n', finiteDiff);
        fprintf('H2 terminal subgradient = %.12g\n', grad(site));
    end
end
end
