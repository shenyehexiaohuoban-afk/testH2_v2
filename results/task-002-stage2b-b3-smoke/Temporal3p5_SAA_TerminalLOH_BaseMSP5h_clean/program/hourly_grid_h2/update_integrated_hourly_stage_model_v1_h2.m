function model = update_integrated_hourly_stage_model_v1_h2( ...
        model, params, k_t, t, prev_x)
%UPDATE_INTEGRATED_HOURLY_STAGE_MODEL_V1_H2 Update Stage-85 hourly H2 RHS.

if t == 1
    rhs = params.x_0(:);
else
    rhs = prev_x(:);
end
if numel(rhs) ~= params.Ni
    error('update_integrated_hourly_stage_model_v1_h2:BadInventory', ...
        'Expected four beginning inventories.');
end

model.beq(model.rowMap.inventory_eq) = rhs;
[demandHourly,demandStage,~,demandMeta] = map_normal_demand_48h_h2(params,t);
model.beq(model.rowMap.hourly_demand_eq(:)) = demandHourly(:);
model.hourly_h2_demand_kg = demandHourly;
model.stage_h2_demand_kg = demandStage;
model.source_demand_stage_dt_h = demandMeta.source_stage_dt_h;
model.operational_stage_dt_h = 8;
model.demand_rescaling_factor = 1;
model.demand_hourly_split = demandMeta.hourly_split_within_source_block;
model.demand_schema = demandMeta.demand_schema;
model.demand_policy = demandMeta.demand_policy;
model.demand_mapping = demandMeta.mapping;
model.demand_global_hours = demandMeta.global_hours;
model.source_hourly_demand_available = demandMeta.source_hourly_available;
model.source_hourly_demand_preserved = demandMeta.source_hourly_preserved;

beta = params.beta(k_t);
if params.use_beta_capacity
    model.b(model.rowMap.htt_capacity) = ...
        max(0,(1-beta)*params.htt_capacity_base);
else
    model.b(model.rowMap.htt_capacity) = params.htt_capacity_base;
end
model.c = model.base_c;
if params.use_beta_cost
    model.c(model.idx.f(:)) = params.cost_transport_base(:) * ...
        (1+params.beta_transport_multiplier*beta);
end
end
