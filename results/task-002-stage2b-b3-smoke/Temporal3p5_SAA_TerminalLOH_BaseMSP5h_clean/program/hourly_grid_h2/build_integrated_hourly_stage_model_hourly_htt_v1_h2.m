function model = build_integrated_hourly_stage_model_hourly_htt_v1_h2(params, t)
%BUILD_INTEGRATED_HOURLY_STAGE_MODEL_HOURLY_HTT_V1_H2 Hourly H2+HTT LP.
%
% Each hour first forms I_pre after production and ordinary service, then
% settles directed HTT before I_end. Only hour-8 I_end (idx.x) crosses stages.

if t < 1 || t > 6
    error('build_integrated_hourly_stage_model_hourly_htt_v1_h2:NonOperatingStage', ...
        'Hourly H2/HTT operation is defined only for ordinary stages 1..6.');
end
if params.dt_h ~= 8 || params.Ni ~= 4 || params.use_tank_min || ...
        ~isfield(params,'hourly_h2_balance_v1') || ~params.hourly_h2_balance_v1
    error('build_integrated_hourly_stage_model_hourly_htt_v1_h2:FrozenIdentity', ...
        'Hourly-HTT v1 requires dt_h=8, four sites, hourly H2, and no tank minimum.');
end

data = params.hourly_grid;
Ni = params.Ni;
nH = 8;
nB = data.n_bus;
nL = data.n_branch;
idx = struct();
next = 0;

idx.x = next + (1:Ni); next = idx.x(end);
idx.e = next + (1:Ni); next = idx.e(end);
idx.r = next + (1:Ni); next = idx.r(end);
idx.f = reshape(next + (1:Ni*Ni*nH), Ni, Ni, nH); next = idx.f(end);
idx.f_hourly = idx.f;
idx.u_normal = next + (1:Ni); next = idx.u_normal(end);
idx.z_normal = next + (1:Ni); next = idx.z_normal(end);
idx.theta = next + 1; next = idx.theta;

idx.u_normal_hourly = reshape(next + (1:Ni*nH), Ni, nH);
next = idx.u_normal_hourly(end);
idx.z_normal_hourly = reshape(next + (1:Ni*nH), Ni, nH);
next = idx.z_normal_hourly(end);
idx.h2_inventory_pre_htt = reshape(next + (1:Ni*nH), Ni, nH);
next = idx.h2_inventory_pre_htt(end);
hour1to7 = reshape(next + (1:Ni*(nH-1)), Ni, nH-1);
next = hour1to7(end);
idx.h2_inventory_hourly = [hour1to7, idx.x(:)];

idx.p_el_hourly = reshape(next + (1:Ni*nH), Ni, nH); next = idx.p_el_hourly(end);
idx.p_branch = reshape(next + (1:nL*nH), nL, nH); next = idx.p_branch(end);
idx.q_branch = reshape(next + (1:nL*nH), nL, nH); next = idx.q_branch(end);
idx.v_sq = reshape(next + (1:nB*nH), nB, nH); next = idx.v_sq(end);
idx.p_grid = next + (1:nH); next = idx.p_grid(end);
idx.q_grid = next + (1:nH); next = idx.q_grid(end);
idx.p_pv = reshape(next + (1:Ni*nH), Ni, nH); next = idx.p_pv(end);
nvars = next;

c = zeros(nvars, 1);
c(idx.x) = params.cost_holding;
c(idx.e) = params.cost_el_om * params.dt_h;
serviceCost = get_htt_base_service_cost(params);
c(idx.f_hourly(:)) = repmat(serviceCost + params.cost_transport_base(:), nH, 1);
c(idx.z_normal_hourly(:)) = params.cost_normal_shortage;
c(idx.theta) = 1;
tau = nH*(t-1) + (1:nH);
c(idx.p_grid) = data.tariff48(tau);

lb = zeros(nvars, 1);
ub = inf(nvars, 1);
lb(idx.p_branch(:)) = -inf;
lb(idx.q_branch(:)) = -inf;
lb(idx.q_grid) = -inf;
ub(idx.x) = params.x_cap(:);
ub(idx.h2_inventory_hourly(:,1:7)) = repmat(params.x_cap(:), 1, 7);
ub(idx.h2_inventory_pre_htt) = repmat(params.x_cap(:), 1, nH);
ub(idx.e) = params.el_cap_kw(:);
ub(idx.p_el_hourly) = repmat(params.el_cap_kw(:), 1, nH);
lb(idx.v_sq) = data.vmin_pu^2;
ub(idx.v_sq) = data.vmax_pu^2;
ub(idx.p_grid) = data.p_substation_max_kw;
for h = 1:nH
    ub(idx.p_pv(:,h)) = data.pv_cap_kw .* data.phi48(tau(h));
    for i = 1:Ni
        ub(idx.f_hourly(i,i,h)) = 0;
    end
end

% Aggregate links, hourly demand, pre-HTT inventory, and post-arrival ending inventory.
nH2Eq = 4*Ni + 3*Ni*nH;
nGridEq = nH*(2*nB+nL+1);
Aeq = zeros(nH2Eq+nGridEq, nvars);
beq = zeros(size(Aeq,1), 1);
row = 0;
servedAggregateRows = row + (1:Ni); row = row+Ni;
shortageAggregateRows = row + (1:Ni); row = row+Ni;
productionRows = row + (1:Ni); row = row+Ni;
hourlyLinkRows = row + (1:Ni); row = row+Ni;
hourlyDemandRows = reshape(row + (1:Ni*nH), Ni, nH); row = row+Ni*nH;
preHttRows = reshape(row + (1:Ni*nH), Ni, nH); row = row+Ni*nH;
endingRows = reshape(row + (1:Ni*nH), Ni, nH); row = row+Ni*nH;

for i = 1:Ni
    Aeq(servedAggregateRows(i), idx.u_normal(i)) = 1;
    Aeq(servedAggregateRows(i), idx.u_normal_hourly(i,:)) = -1;
    Aeq(shortageAggregateRows(i), idx.z_normal(i)) = 1;
    Aeq(shortageAggregateRows(i), idx.z_normal_hourly(i,:)) = -1;
    Aeq(productionRows(i), idx.r(i)) = 1;
    Aeq(productionRows(i), idx.e(i)) = -params.k_H2*params.dt_h;
    Aeq(hourlyLinkRows(i), idx.e(i)) = params.dt_h;
    Aeq(hourlyLinkRows(i), idx.p_el_hourly(i,:)) = -1;

    for h = 1:nH
        Aeq(hourlyDemandRows(i,h), idx.u_normal_hourly(i,h)) = 1;
        Aeq(hourlyDemandRows(i,h), idx.z_normal_hourly(i,h)) = 1;

        Aeq(preHttRows(i,h), idx.h2_inventory_pre_htt(i,h)) = 1;
        if h > 1
            Aeq(preHttRows(i,h), idx.h2_inventory_hourly(i,h-1)) = -1;
        end
        Aeq(preHttRows(i,h), idx.p_el_hourly(i,h)) = -params.k_H2;
        Aeq(preHttRows(i,h), idx.u_normal_hourly(i,h)) = 1;

        Aeq(endingRows(i,h), idx.h2_inventory_hourly(i,h)) = 1;
        Aeq(endingRows(i,h), idx.h2_inventory_pre_htt(i,h)) = -1;
        for j = 1:Ni
            if j ~= i
                Aeq(endingRows(i,h), idx.f_hourly(j,i,h)) = -1;
                Aeq(endingRows(i,h), idx.f_hourly(i,j,h)) = 1;
            end
        end
    end
end

gridP = zeros(nH,nB); gridQ = zeros(nH,nB);
gridV = zeros(nH,nL); slackV = zeros(nH,1);
for h = 1:nH
    gridP(h,:) = row + (1:nB); row = row+nB;
    gridQ(h,:) = row + (1:nB); row = row+nB;
    gridV(h,:) = row + (1:nL); row = row+nL;
    slackV(h) = row+1; row = row+1;
    for ell = 1:nL
        from = data.branch_from(ell); to = data.branch_to(ell);
        Aeq(gridP(h,from),idx.p_branch(ell,h)) = -1;
        Aeq(gridP(h,to),idx.p_branch(ell,h)) = 1;
        Aeq(gridQ(h,from),idx.q_branch(ell,h)) = -1;
        Aeq(gridQ(h,to),idx.q_branch(ell,h)) = 1;
        factor = 2/(data.base_kv^2*1000);
        Aeq(gridV(h,ell),idx.v_sq(to,h)) = 1;
        Aeq(gridV(h,ell),idx.v_sq(from,h)) = -1;
        Aeq(gridV(h,ell),idx.p_branch(ell,h)) = factor*data.r_ohm(ell);
        Aeq(gridV(h,ell),idx.q_branch(ell,h)) = factor*data.x_ohm(ell);
    end
    Aeq(gridP(h,data.slack_bus),idx.p_grid(h)) = 1;
    Aeq(gridQ(h,data.slack_bus),idx.q_grid(h)) = 1;
    for site = 1:Ni
        bus = data.site_elec_bus(site);
        Aeq(gridP(h,bus),idx.p_pv(site,h)) = 1;
        Aeq(gridP(h,bus),idx.p_el_hourly(site,h)) = -1;
    end
    beq(gridP(h,:)) = data.p_load_base_kw*data.lambda48(tau(h));
    beq(gridQ(h,:)) = data.q_load_base_kvar*data.lambda48(tau(h));
    Aeq(slackV(h),idx.v_sq(data.slack_bus,h)) = 1;
    beq(slackV(h)) = 1;
end
if row ~= size(Aeq,1)
    error('build_integrated_hourly_stage_model_hourly_htt_v1_h2:RowCount', ...
        'Built %d equality rows but allocated %d.', row, size(Aeq,1));
end

% One fleet-capacity row per hour and one origin-availability row per site-hour.
nBaseIneq = nH + Ni*nH;
A = zeros(nBaseIneq + nH*8*nL, nvars);
b = zeros(size(A,1),1);
httRows = 1:nH;
httOutflowRows = reshape(nH + (1:Ni*nH), Ni, nH);
for h = 1:nH
    A(httRows(h),idx.f_hourly(:,:,h)) = 1;
    for i = 1:Ni
        A(httOutflowRows(i,h),idx.f_hourly(i,:,h)) = 1;
        A(httOutflowRows(i,h),idx.h2_inventory_pre_htt(i,h)) = -1;
    end
end
octRows = zeros(nH,nL,8);
offset = nBaseIneq;
for h = 1:nH
    localIdx = struct('p_branch',idx.p_branch(:,h), ...
        'q_branch',idx.q_branch(:,h));
    [Ah,bh,rows] = add_branch_capacity_octagon_h2(nvars,localIdx,data);
    rr = offset+(1:size(Ah,1));
    A(rr,:) = Ah; b(rr) = bh;
    octRows(h,:,:) = reshape(rows+offset,1,nL,8);
    offset = offset+size(Ah,1);
end

model = struct('t',t,'nvars',nvars,'idx',idx,'c',c,'base_c',c, ...
    'lb',lb,'ub',ub,'A',A,'b',b,'Aeq',Aeq,'beq',beq, ...
    'hourly_grid_enabled',true,'hourly_tau',tau, ...
    'hourly_h2_balance_enabled',true,'hourly_htt_enabled',true, ...
    'h2_timescale_schema','hourly-h2-hourly-htt-v1', ...
    'operational_stage_duration_h',8,'inner_dt_h',1, ...
    'demand_policy','preserve_stage_total_uniform_hourly_split', ...
    'htt_timing','hourly_end_of_hour_arrival', ...
    'htt_resolution','hourly','htt_trip_time_assumption_h',1, ...
    'htt_hourly_base_capacity_kg',160,'tank_min_active',false, ...
    'h2_k_H2',params.k_H2);
model.rowMap = struct('inventory_eq',preHttRows(:,1), ...
    'production_eq',productionRows,'hourly_power_link_eq',hourlyLinkRows, ...
    'served_aggregate_eq',servedAggregateRows, ...
    'shortage_aggregate_eq',shortageAggregateRows, ...
    'hourly_demand_eq',hourlyDemandRows, ...
    'pre_htt_inventory_eq',preHttRows,'hourly_inventory_eq',endingRows, ...
    'post_htt_inventory_eq',endingRows(:,8), ...
    'htt_capacity',httRows,'htt_outflow_availability',httOutflowRows, ...
    'grid_p_balance',gridP,'grid_q_balance',gridQ, ...
    'grid_voltage_drop',gridV,'grid_slack_voltage',slackV, ...
    'branch_octagon',octRows);
end

function value = get_htt_base_service_cost(params)
value = get_htt_base_service_cost_h2(params);
end
