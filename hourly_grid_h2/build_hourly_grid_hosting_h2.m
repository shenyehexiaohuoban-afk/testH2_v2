function model = build_hourly_grid_hosting_h2(data, tau, pvEnabled)
%BUILD_HOURLY_GRID_HOSTING_H2 Maximize feasible hourly electrolyzer load.

if nargin < 3
    pvEnabled = true;
end
nB = data.n_bus;
nL = data.n_branch;
idx = struct();
next = 0;
idx.p_branch = next + (1:nL); next = idx.p_branch(end);
idx.q_branch = next + (1:nL); next = idx.q_branch(end);
idx.v_sq = next + (1:nB); next = idx.v_sq(end);
idx.p_grid = next + 1; next = idx.p_grid;
idx.q_grid = next + 1; next = idx.q_grid;
idx.p_pv = next + (1:4); next = idx.p_pv(end);
idx.p_el = next + (1:4); next = idx.p_el(end);
nvars = next;

lb = -inf(nvars, 1);
ub = inf(nvars, 1);
lb(idx.v_sq) = data.vmin_pu^2;
ub(idx.v_sq) = data.vmax_pu^2;
lb(idx.p_grid) = 0;
ub(idx.p_grid) = data.p_substation_max_kw;
lb(idx.p_pv) = 0;
if pvEnabled
    ub(idx.p_pv) = data.pv_cap_kw .* data.phi48(tau);
else
    ub(idx.p_pv) = 0;
end
lb(idx.p_el) = 0;
ub(idx.p_el) = data.pmax_kw;

pLoad = data.p_load_base_kw * data.lambda48(tau);
qLoad = data.q_load_base_kvar * data.lambda48(tau);
nEq = 2 * nB + nL + 1;
Aeq = zeros(nEq, nvars);
beq = zeros(nEq, 1);
pRows = 1:nB;
qRows = nB + (1:nB);
vRows = 2 * nB + (1:nL);
slackRow = nEq;

for ell = 1:nL
    i = data.branch_from(ell);
    j = data.branch_to(ell);
    Aeq(pRows(i), idx.p_branch(ell)) = -1;
    Aeq(pRows(j), idx.p_branch(ell)) = 1;
    Aeq(qRows(i), idx.q_branch(ell)) = -1;
    Aeq(qRows(j), idx.q_branch(ell)) = 1;
    factor = 2 / (data.base_kv^2 * 1000);
    Aeq(vRows(ell), idx.v_sq(j)) = 1;
    Aeq(vRows(ell), idx.v_sq(i)) = -1;
    Aeq(vRows(ell), idx.p_branch(ell)) = factor * data.r_ohm(ell);
    Aeq(vRows(ell), idx.q_branch(ell)) = factor * data.x_ohm(ell);
end
Aeq(pRows(data.slack_bus), idx.p_grid) = 1;
Aeq(qRows(data.slack_bus), idx.q_grid) = 1;
for site = 1:4
    bus = data.site_elec_bus(site);
    Aeq(pRows(bus), idx.p_pv(site)) = 1;
    Aeq(pRows(bus), idx.p_el(site)) = -1;
end
beq(pRows) = pLoad;
beq(qRows) = qLoad;
Aeq(slackRow, idx.v_sq(data.slack_bus)) = 1;
beq(slackRow) = data.slack_v_sq;
[A, b, octRows] = add_branch_capacity_octagon_h2(nvars, idx, data);

c = zeros(nvars, 1);
c(idx.p_el) = -1;
% Tiny deterministic tie-break favors lower grid import without changing
% the maximum total electrolyzer hosting objective at smoke tolerance.
c(idx.p_grid) = 1e-9;

model = struct('tau', tau, 'nvars', nvars, 'idx', idx, 'c', c, ...
    'lb', lb, 'ub', ub, 'A', A, 'b', b, 'Aeq', Aeq, 'beq', beq, ...
    'p_load_kw', pLoad, 'q_load_kvar', qLoad, ...
    'pv_enabled', logical(pvEnabled));
model.rowMap = struct('p_balance', pRows, 'q_balance', qRows, ...
    'voltage_drop', vRows, 'slack_voltage', slackRow, ...
    'branch_octagon', octRows);
end
