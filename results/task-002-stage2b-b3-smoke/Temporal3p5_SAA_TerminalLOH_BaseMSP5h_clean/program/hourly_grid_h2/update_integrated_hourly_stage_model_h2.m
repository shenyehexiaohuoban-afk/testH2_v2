function model = update_integrated_hourly_stage_model_h2(model,params,k_t,t,prev_x)
%UPDATE_INTEGRATED_HOURLY_STAGE_MODEL_H2 Update H2/state-dependent RHS.

if isfield(model, 'hourly_htt_enabled') && model.hourly_htt_enabled
    model = update_integrated_hourly_stage_model_hourly_htt_v1_h2( ...
        model, params, k_t, t, prev_x);
    return;
end

if isfield(model, 'hourly_h2_balance_enabled') && model.hourly_h2_balance_enabled
    model = update_integrated_hourly_stage_model_v1_h2( ...
        model, params, k_t, t, prev_x);
    return;
end

if t==1
    rhs=params.x_0(:);
else
    rhs=prev_x(:);
end
if numel(rhs)~=params.Ni
    error('update_integrated_hourly_stage_model_h2:BadInventory','Expected four inventories.');
end
model.beq(model.rowMap.inventory_eq)=rhs;
D=params.D_normal(:,t);
model.b(model.rowMap.normal_demand)=-D;
model.ub(model.idx.u_normal)=D;
beta=params.beta(k_t);
if params.use_beta_capacity
    model.b(model.rowMap.htt_capacity)=max(0,(1-beta)*params.htt_capacity_base);
else
    model.b(model.rowMap.htt_capacity)=params.htt_capacity_base;
end
model.c=model.base_c;
if params.use_beta_cost
    model.c(model.idx.f(:))=params.cost_transport_base(:)*(1+params.beta_transport_multiplier*beta);
end
end
