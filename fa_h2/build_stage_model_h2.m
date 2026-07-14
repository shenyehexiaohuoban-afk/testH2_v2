function model = build_stage_model_h2(params, t)
%BUILD_STAGE_MODEL_H2 Build a non-terminal hydrogen stage LP template.
%
% Non-terminal stages do not impose disaster reserve demand. They only model
% normal H2 demand, production, storage, and HTT movement. TerminalLOH is
% evaluated separately when lf=Nc-1; lf=Nc is zero-cost absorbing.

Ni = params.Ni;

idx = struct();
next = 0;

idx.x = next + (1:Ni);                 % end-of-stage station LOH, kg
next = idx.x(end);

idx.e = next + (1:Ni);                 % electrolyzer power, kW
next = idx.e(end);

idx.r = next + (1:Ni);                 % hydrogen production, kg/stage
next = idx.r(end);

idx.f = reshape(next + (1:(Ni * Ni)), Ni, Ni); % HTT transfer i -> j, kg
next = idx.f(end);

idx.u_normal = next + (1:Ni);          % served normal hydrogen load, kg
next = idx.u_normal(end);

idx.z_normal = next + (1:Ni);          % normal load shortage, kg
next = idx.z_normal(end);

idx.theta = next + 1;                  % future cost approximation Theta(x)
nvars = idx.theta;

c = zeros(nvars, 1);
c(idx.x) = params.cost_holding;
c(idx.e) = (params.cost_electricity_stage(t) + params.cost_el_om) * params.dt_h;
c(idx.f(:)) = params.cost_transport_base(:);
c(idx.z_normal) = params.cost_normal_shortage;
c(idx.theta) = 1;

lb = zeros(nvars, 1);
ub = inf(nvars, 1);
ub(idx.x) = params.x_cap(:);
if params.use_tank_min
    lb(idx.x) = params.x_min(:);
end
ub(idx.e) = params.el_cap_kw(:);
for i = 1:Ni
    ub(idx.f(i, i)) = 0;
end

% Equality rows:
% Inventory balance:
%   x_i,t = x_i,t-1 + r_i,t + inflow_i,t - outflow_i,t - u_i,t^normal.
% Normal demand is a real tank withdrawal. TerminalLOH is not withdrawn here.
% Production conversion:
%   r_i,t = k_H2 * e_i,t * dt_h.
nEq = 2 * Ni;
Aeq = zeros(nEq, nvars);
beq = zeros(nEq, 1);
inventoryRows = 1:Ni;
productionRows = Ni + (1:Ni);

for i = 1:Ni
    row = inventoryRows(i);
    Aeq(row, idx.x(i)) = 1;
    Aeq(row, idx.r(i)) = -1;
    Aeq(row, idx.u_normal(i)) = 1;
    for j = 1:Ni
        if j ~= i
            Aeq(row, idx.f(j, i)) = Aeq(row, idx.f(j, i)) - 1;
            Aeq(row, idx.f(i, j)) = Aeq(row, idx.f(i, j)) + 1;
        end
    end

    prow = productionRows(i);
    Aeq(prow, idx.r(i)) = 1;
    Aeq(prow, idx.e(i)) = -params.k_H2 * params.dt_h;
end

% Inequality rows:
% normal_demand: -u_i - z_i <= -D_i,t
% htt_capacity: sum_i sum_j f_ij <= (1-beta(k))*HTT_capacity
nIneq = Ni + 1;
A = zeros(nIneq, nvars);
b = zeros(nIneq, 1);
normalRows = 1:Ni;
httRow = Ni + 1;

for i = 1:Ni
    A(normalRows(i), idx.u_normal(i)) = -1;
    A(normalRows(i), idx.z_normal(i)) = -1;
end
A(httRow, idx.f(:)) = 1;

rowMap = struct();
rowMap.inventory_eq = inventoryRows;
rowMap.production_eq = productionRows;
rowMap.normal_demand = normalRows;
rowMap.htt_capacity = httRow;

model = struct();
model.t = t;
model.nvars = nvars;
model.idx = idx;
model.c = c;
model.base_c = c;
model.lb = lb;
model.ub = ub;
model.A = A;
model.b = b;
model.Aeq = Aeq;
model.beq = beq;
model.rowMap = rowMap;
end
