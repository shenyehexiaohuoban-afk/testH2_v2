function sol = solve_stage_model_h2(model)
%SOLVE_STAGE_MODEL_H2 Solve one non-terminal hydrogen stage LP with Gurobi.

nIneq = size(model.A, 1);
nEq = size(model.Aeq, 1);

grb = struct();
grb.A = sparse([model.A; model.Aeq]);
grb.obj = model.c(:);
grb.rhs = [model.b(:); model.beq(:)];
grb.sense = [repmat('<', nIneq, 1); repmat('=', nEq, 1)];
grb.lb = model.lb(:);
grb.ub = model.ub(:);
grb.modelsense = 'min';

grbParams = struct();
grbParams.OutputFlag = 0;
grbParams.InfUnbdInfo = 1;

result = gurobi(grb, grbParams);

sol = struct();
sol.status = result.status;
sol.exitflag = double(strcmp(result.status, 'OPTIMAL'));
if sol.exitflag ~= 1
    error('solve_stage_model_h2:GurobiFailure', ...
        'Gurobi failed at stage %d with status %s.', model.t, result.status);
end

xraw = result.x;
sol.xraw = xraw;
sol.raw = xraw;
sol.obj = result.objval;
sol.xval = xraw(model.idx.x);
sol.eval = xraw(model.idx.e);
sol.rval = xraw(model.idx.r);
if isfield(model, 'hourly_htt_enabled') && model.hourly_htt_enabled
    sol.f_hourly_kg = reshape(xraw(model.idx.f_hourly(:)), ...
        size(model.idx.f_hourly));
    sol.fval = sum(sol.f_hourly_kg, 3);
else
    sol.fval = reshape(xraw(model.idx.f(:)), size(model.idx.f));
end
sol.u_normal = xraw(model.idx.u_normal);
sol.z_normal = xraw(model.idx.z_normal);
sol.theta = xraw(model.idx.theta);
sol.s_reserve = zeros(size(sol.xval)); % deprecated; terminal shortage is separate

sol.vars = struct();
sol.vars.x = sol.xval;
sol.vars.e = sol.eval;
sol.vars.r = sol.rval;
sol.vars.f = sol.fval;
sol.vars.u_normal = sol.u_normal;
sol.vars.z_normal = sol.z_normal;
sol.vars.theta = sol.theta;

if isfield(model, 'hourly_grid_enabled') && model.hourly_grid_enabled
    sol.p_el_hourly_kw = reshape(xraw(model.idx.p_el_hourly), ...
        size(model.idx.p_el_hourly));
    sol.p_branch_kw = reshape(xraw(model.idx.p_branch), ...
        size(model.idx.p_branch));
    sol.q_branch_kvar = reshape(xraw(model.idx.q_branch), ...
        size(model.idx.q_branch));
    sol.v_sq = reshape(xraw(model.idx.v_sq), size(model.idx.v_sq));
    sol.p_grid_kw = xraw(model.idx.p_grid);
    sol.q_grid_kvar = xraw(model.idx.q_grid);
    sol.p_pv_kw = reshape(xraw(model.idx.p_pv), size(model.idx.p_pv));
    sol.vars.p_el_hourly_kw = sol.p_el_hourly_kw;
    sol.vars.p_branch_kw = sol.p_branch_kw;
    sol.vars.q_branch_kvar = sol.q_branch_kvar;
    sol.vars.v_sq = sol.v_sq;
    sol.vars.p_grid_kw = sol.p_grid_kw;
    sol.vars.q_grid_kvar = sol.q_grid_kvar;
    sol.vars.p_pv_kw = sol.p_pv_kw;
end

if isfield(model, 'hourly_h2_balance_enabled') && model.hourly_h2_balance_enabled
    sol.u_normal_hourly_kg = reshape(xraw(model.idx.u_normal_hourly), ...
        size(model.idx.u_normal_hourly));
    sol.z_normal_hourly_kg = reshape(xraw(model.idx.z_normal_hourly), ...
        size(model.idx.z_normal_hourly));
    sol.h2_inventory_hourly_kg = reshape( ...
        xraw(model.idx.h2_inventory_hourly), ...
        size(model.idx.h2_inventory_hourly));
    sol.h2_inventory_pre_htt_kg = reshape( ...
        xraw(model.idx.h2_inventory_pre_htt), ...
        size(model.idx.h2_inventory_pre_htt));
    sol.h2_production_hourly_kg = model.h2_k_H2 * sol.p_el_hourly_kw;
    beginning = model.beq(model.rowMap.inventory_eq);
    sol.h2_inventory_begin_hourly_kg = ...
        [beginning(:), sol.h2_inventory_hourly_kg(:,1:7)];
    sol.h2_demand_hourly_kg = model.hourly_h2_demand_kg;
    sol.h2_timescale_schema = model.h2_timescale_schema;
    sol.vars.u_normal_hourly_kg = sol.u_normal_hourly_kg;
    sol.vars.z_normal_hourly_kg = sol.z_normal_hourly_kg;
    sol.vars.h2_inventory_hourly_kg = sol.h2_inventory_hourly_kg;
    sol.vars.h2_inventory_pre_htt_kg = sol.h2_inventory_pre_htt_kg;
    sol.vars.h2_production_hourly_kg = sol.h2_production_hourly_kg;
end

if isfield(model, 'hourly_htt_enabled') && model.hourly_htt_enabled
    nSite = size(sol.f_hourly_kg, 1);
    nHour = size(sol.f_hourly_kg, 3);
    sol.htt_in_hourly_kg = zeros(nSite, nHour);
    sol.htt_out_hourly_kg = zeros(nSite, nHour);
    for h = 1:nHour
        sol.htt_in_hourly_kg(:,h) = sum(sol.f_hourly_kg(:,:,h), 1).';
        sol.htt_out_hourly_kg(:,h) = sum(sol.f_hourly_kg(:,:,h), 2);
    end
    sol.vars.f_hourly_kg = sol.f_hourly_kg;
    sol.vars.htt_in_hourly_kg = sol.htt_in_hourly_kg;
    sol.vars.htt_out_hourly_kg = sol.htt_out_hourly_kg;
end

pi_ineq = result.pi(1:nIneq);
pi_eq = result.pi(nIneq + (1:nEq));

sol.lambda = struct();
% Ordinary H2 cut slopes use only the inventory balance RHS sensitivity.
sol.lambda.inventory_eq = pi_eq(model.rowMap.inventory_eq);
sol.lambda.production_eq = pi_eq(model.rowMap.production_eq);
sol.lambda.raw_ineq = pi_ineq;
sol.lambda.raw_eq = pi_eq;
end
