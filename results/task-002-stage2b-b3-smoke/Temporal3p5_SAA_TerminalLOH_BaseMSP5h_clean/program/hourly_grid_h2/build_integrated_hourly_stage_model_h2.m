function model = build_integrated_hourly_stage_model_h2(params, t)
%BUILD_INTEGRATED_HOURLY_STAGE_MODEL_H2 Build one 8 h grid+H2 stage LP.

if isfield(params, 'hourly_htt_v1') && params.hourly_htt_v1
    model = build_integrated_hourly_stage_model_hourly_htt_v1_h2(params, t);
    return;
end

if isfield(params, 'hourly_h2_balance_v1') && params.hourly_h2_balance_v1
    model = build_integrated_hourly_stage_model_v1_h2(params, t);
    return;
end

if t < 1 || t > 6
    error('build_integrated_hourly_stage_model_h2:NonOperatingStage', ...
        'Hourly grid operation is defined only for ordinary stages 1..6.');
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
idx.f = reshape(next + (1:Ni*Ni), Ni, Ni); next = idx.f(end);
idx.u_normal = next + (1:Ni); next = idx.u_normal(end);
idx.z_normal = next + (1:Ni); next = idx.z_normal(end);
idx.theta = next + 1; next = idx.theta;
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
c(idx.f(:)) = params.cost_transport_base(:);
c(idx.z_normal) = params.cost_normal_shortage;
c(idx.theta) = 1;
tau = 8*(t-1) + (1:8);
c(idx.p_grid) = data.tariff48(tau);

lb = zeros(nvars, 1);
ub = inf(nvars, 1);
lb(idx.p_branch(:)) = -inf;
lb(idx.q_branch(:)) = -inf;
lb(idx.q_grid) = -inf;
ub(idx.x) = params.x_cap(:);
if params.use_tank_min
    lb(idx.x) = params.x_min(:);
end
ub(idx.e) = params.el_cap_kw(:);
ub(idx.p_el_hourly) = repmat(params.el_cap_kw(:), 1, nH);
lb(idx.v_sq) = data.vmin_pu^2;
ub(idx.v_sq) = data.vmax_pu^2;
ub(idx.p_grid) = data.p_substation_max_kw;
for h = 1:nH
    ub(idx.p_pv(:,h)) = data.pv_cap_kw .* data.phi48(tau(h));
end
for i = 1:Ni
    ub(idx.f(i,i)) = 0;
end

nEq = 3*Ni + nH*(2*nB+nL+1);
Aeq = zeros(nEq, nvars);
beq = zeros(nEq, 1);
inventoryRows = 1:Ni;
productionRows = Ni + (1:Ni);
hourlyLinkRows = 2*Ni + (1:Ni);
row = 3*Ni;
gridP = zeros(nH,nB); gridQ = zeros(nH,nB);
gridV = zeros(nH,nL); slackV = zeros(nH,1);

for i = 1:Ni
    Aeq(inventoryRows(i), idx.x(i)) = 1;
    Aeq(inventoryRows(i), idx.r(i)) = -1;
    Aeq(inventoryRows(i), idx.u_normal(i)) = 1;
    for j = 1:Ni
        if j ~= i
            Aeq(inventoryRows(i), idx.f(j,i)) = -1;
            Aeq(inventoryRows(i), idx.f(i,j)) = 1;
        end
    end
    Aeq(productionRows(i), idx.r(i)) = 1;
    Aeq(productionRows(i), idx.e(i)) = -params.k_H2*params.dt_h;
    Aeq(hourlyLinkRows(i), idx.e(i)) = params.dt_h;
    Aeq(hourlyLinkRows(i), idx.p_el_hourly(i,:)) = -1;
end

for h = 1:nH
    gridP(h,:) = row + (1:nB); row = row+nB;
    gridQ(h,:) = row + (1:nB); row = row+nB;
    gridV(h,:) = row + (1:nL); row = row+nL;
    slackV(h) = row+1; row=row+1;
    for ell = 1:nL
        i = data.branch_from(ell); j = data.branch_to(ell);
        Aeq(gridP(h,i),idx.p_branch(ell,h)) = -1;
        Aeq(gridP(h,j),idx.p_branch(ell,h)) = 1;
        Aeq(gridQ(h,i),idx.q_branch(ell,h)) = -1;
        Aeq(gridQ(h,j),idx.q_branch(ell,h)) = 1;
        factor = 2/(data.base_kv^2*1000);
        Aeq(gridV(h,ell),idx.v_sq(j,h)) = 1;
        Aeq(gridV(h,ell),idx.v_sq(i,h)) = -1;
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

nBaseIneq = Ni+1;
A = zeros(nBaseIneq + nH*8*nL, nvars);
b = zeros(size(A,1),1);
normalRows = 1:Ni;
httRow = Ni+1;
for i=1:Ni
    A(normalRows(i),idx.u_normal(i))=-1;
    A(normalRows(i),idx.z_normal(i))=-1;
end
A(httRow,idx.f(:))=1;
octRows = zeros(nH,nL,8);
offset = nBaseIneq;
for h=1:nH
    localIdx=struct('p_branch',idx.p_branch(:,h),'q_branch',idx.q_branch(:,h));
    [Ah,bh,rows]=add_branch_capacity_octagon_h2(nvars,localIdx,data);
    rr=offset+(1:size(Ah,1));
    A(rr,:)=Ah; b(rr)=bh;
    octRows(h,:,:)=reshape(rows+offset,1,nL,8);
    offset=offset+size(Ah,1);
end

model=struct('t',t,'nvars',nvars,'idx',idx,'c',c,'base_c',c, ...
    'lb',lb,'ub',ub,'A',A,'b',b,'Aeq',Aeq,'beq',beq, ...
    'hourly_grid_enabled',true,'hourly_tau',tau);
model.rowMap=struct('inventory_eq',inventoryRows,'production_eq',productionRows, ...
    'hourly_power_link_eq',hourlyLinkRows,'normal_demand',normalRows, ...
    'htt_capacity',httRow,'grid_p_balance',gridP,'grid_q_balance',gridQ, ...
    'grid_voltage_drop',gridV,'grid_slack_voltage',slackV, ...
    'branch_octagon',octRows);
end
