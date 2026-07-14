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
sol.fval = reshape(xraw(model.idx.f(:)), size(model.idx.f));
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

pi_ineq = result.pi(1:nIneq);
pi_eq = result.pi(nIneq + (1:nEq));

sol.lambda = struct();
% Ordinary H2 cut slopes use only the inventory balance RHS sensitivity.
sol.lambda.inventory_eq = pi_eq(model.rowMap.inventory_eq);
sol.lambda.production_eq = pi_eq(model.rowMap.production_eq);
sol.lambda.raw_ineq = pi_ineq;
sol.lambda.raw_eq = pi_eq;
end
