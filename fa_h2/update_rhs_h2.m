function model = update_rhs_h2(model, params, k_t, t, prev_x)
%UPDATE_RHS_H2 Update one non-terminal hydrogen stage LP.
%
% Updates only previous LOH, normal demand, beta-dependent HTT capacity, and
% optional beta cost amplification. It does not use TargetLOH/TerminalLOH;
% terminal reserve adequacy is handled outside the ordinary LP.

if isempty(model)
    error('update_rhs_h2:MissingModel', ...
        'No non-terminal H2 model exists for stage %d and state %d.', t, k_t);
end

if t == 1
    rhs_x = params.x_0(:);
else
    if nargin < 5 || isempty(prev_x)
        error('update_rhs_h2:MissingInventory', ...
            'prev_x is required when updating stage %d.', t);
    end
    rhs_x = prev_x(:);
end
if numel(rhs_x) ~= params.Ni
    error('update_rhs_h2:BadInventorySize', ...
        'Expected prev_x to have %d entries, got %d.', params.Ni, numel(rhs_x));
end

model.beq(model.rowMap.inventory_eq) = rhs_x;

D = params.D_normal(:, t);
model.b(model.rowMap.normal_demand) = -D;
model.ub(model.idx.u_normal) = D;

% beta(k) is transport friction/risk. It reduces HTT capacity and/or
% increases transport cost. It is not an absorbing-state flag.
beta = params.beta(k_t);
if params.use_beta_capacity
    model.b(model.rowMap.htt_capacity) = max(0, (1 - beta) * params.htt_capacity_base);
else
    model.b(model.rowMap.htt_capacity) = params.htt_capacity_base;
end

model.c = model.base_c;
if params.use_beta_cost
    model.c(model.idx.f(:)) = params.cost_transport_base(:) * ...
        (1 + params.beta_transport_multiplier * beta);
end
end
