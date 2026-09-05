function diag = evaluate_hourly_grid_constraints_h2(data, model, xraw)
%EVALUATE_HOURLY_GRID_CONSTRAINTS_H2 Recompute physical LP diagnostics.

idx = model.idx;
p = xraw(idx.p_branch);
q = xraw(idx.q_branch);
vSq = xraw(idx.v_sq);
vPu = sqrt(max(vSq, 0));
sMva = hypot(p, q) / 1000;

eqResidual = model.Aeq * xraw - model.beq;
ineqResidual = model.A * xraw - model.b;

[minVoltage, minBus] = min(vPu);
[maxVoltage, maxBus] = max(vPu);
[maxS, maxBranch] = max(sMva);
diag = struct();
diag.p_branch_kw = p;
diag.q_branch_kvar = q;
diag.v_sq = vSq;
diag.v_pu = vPu;
diag.true_s_mva = sMva;
diag.min_voltage_pu = minVoltage;
diag.min_voltage_bus = minBus;
diag.max_voltage_pu = maxVoltage;
diag.max_voltage_bus = maxBus;
diag.max_true_s_mva = maxS;
diag.max_true_s_branch = maxBranch;
diag.max_true_s_utilization = maxS / data.branch_smax_mva;
diag.slack_p_kw = xraw(idx.p_grid);
diag.slack_q_kvar = xraw(idx.q_grid);
diag.p_pv_kw = xraw(idx.p_pv);
diag.max_p_balance_error_kw = max(abs(eqResidual(model.rowMap.p_balance)));
diag.max_q_balance_error_kvar = max(abs(eqResidual(model.rowMap.q_balance)));
diag.max_voltage_drop_error = max(abs(eqResidual(model.rowMap.voltage_drop)));
diag.slack_voltage_error = abs(eqResidual(model.rowMap.slack_voltage));
diag.max_octagon_violation = max([0; ineqResidual]);
diag.true_circle_violation_mva = max([0; sMva - data.branch_smax_mva]);
diag.voltage_lower_violation_pu = max([0; data.vmin_pu - vPu]);
diag.voltage_upper_violation_pu = max([0; vPu - data.vmax_pu]);
end
