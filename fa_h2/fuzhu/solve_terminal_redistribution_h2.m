function [value, grad, info] = solve_terminal_redistribution_h2(I, T, params, k)
%SOLVE_TERMINAL_REDISTRIBUTION_H2 Solve the Stage-7 direct redistribution LP.
%
% Variables are [x_ij (i ~= j); g_i].  Donor availability is bounded by
% inventory entering Stage 7, so an inbound shipment cannot be retransmitted
% in the same terminal action.

I = I(:);
T = T(:);
Ni = params.Ni;
if numel(I) ~= Ni || numel(T) ~= Ni
    error('solve_terminal_redistribution_h2:BadDimension', ...
        'I and T must both have params.Ni entries.');
end
if any(~isfinite(I)) || any(~isfinite(T)) || any(I < -1e-9) || any(T < -1e-9)
    error('solve_terminal_redistribution_h2:BadState', ...
        'Inventory and TerminalLOH target must be finite and nonnegative.');
end
I = max(I, 0);
T = max(T, 0);
if ~isfield(params, 'K_terminal_kg') || isempty(params.K_terminal_kg)
    error('solve_terminal_redistribution_h2:MissingCapacity', ...
        'K_terminal_kg is required; terminal duration is not implicit.');
end
K = double(params.K_terminal_kg);
if ~isscalar(K) || ~isfinite(K) || K < 0
    error('solve_terminal_redistribution_h2:BadCapacity', ...
        'K_terminal_kg must be a finite nonnegative scalar.');
end
penalty = double(params.cost_reserve_shortage);
if ~isscalar(penalty) || ~isfinite(penalty) || penalty < 0
    error('solve_terminal_redistribution_h2:BadPenalty', ...
        'cost_reserve_shortage must be a finite nonnegative scalar.');
end
cost = terminal_cost_matrix_h2(params, k, Ni);

% Stable OD ordering: (1,2),(1,3),(1,4),(2,1),... with diagonal omitted.
od = zeros(Ni * (Ni - 1), 2);
q = 0;
for i = 1:Ni
    for j = 1:Ni
        if i ~= j
            q = q + 1;
            od(q,:) = [i,j];
        end
    end
end
nOD = size(od, 1);
Aout = zeros(Ni, nOD);
Agap = zeros(Ni, nOD);
for e = 1:nOD
    i = od(e,1); j = od(e,2);
    Aout(i,e) = 1;
    Agap(i,e) = Agap(i,e) + 1;
    Agap(j,e) = Agap(j,e) - 1;
end

donorRows = 1:Ni;
gapRows = Ni + (1:Ni);
capacityRow = 2 * Ni + 1;
A = zeros(capacityRow, nOD + Ni);
b = zeros(capacityRow, 1);
A(donorRows,1:nOD) = Aout;
b(donorRows) = I;
A(gapRows,1:nOD) = Agap;
A(gapRows,nOD + (1:Ni)) = -eye(Ni);
b(gapRows) = I - T;
A(capacityRow,1:nOD) = 1;
b(capacityRow) = K;

odCost = cost(sub2ind([Ni,Ni], od(:,1), od(:,2)));
grb = struct('A',sparse(A),'obj',[odCost; penalty * ones(Ni,1)], ...
    'rhs',b,'sense',repmat('<',capacityRow,1), ...
    'lb',zeros(nOD + Ni,1),'ub',inf(nOD + Ni,1),'modelsense','min');
grbParams = struct('OutputFlag',0,'InfUnbdInfo',1);
result = gurobi(grb, grbParams);
if ~isfield(result,'status') || ~strcmp(result.status,'OPTIMAL')
    status = '<unknown>';
    if isfield(result,'status'); status = result.status; end
    error('solve_terminal_redistribution_h2:GurobiFailure', ...
        'Terminal LP failed at state %d with status %s.', k, status);
end

z = result.x(:);
x = z(1:nOD);
g = z(nOD + (1:Ni));
pi = result.pi(:);
piDonor = pi(donorRows);
piGap = pi(gapRows);
grad = piDonor + piGap;
value = result.objval;

out = Aout * x;
in = zeros(Ni,1);
for e = 1:nOD
    in(od(e,2)) = in(od(e,2)) + x(e);
end
Ihat = I - out + in;
shortage = max(0, T - Ihat);
slack = b - A * z;
primalResidual = max([0; A * z - b]);
dualResidual = NaN;
if isfield(result,'rc')
    dualResidual = max(abs(result.rc(:) .* z));
end
complementarityResidual = max(abs(pi .* slack));

info = struct();
info.status = result.status;
info.k = k;
info.inventory = I;
info.target = T;
info.x_ij = x;
info.g = g;
info.od_pairs = od;
info.outbound = out;
info.inbound = in;
info.Ihat = Ihat;
info.shortage = shortage;
info.cost_matrix = cost;
info.shipping_cost = odCost.' * x;
info.shortage_cost = penalty * sum(g);
info.capacity_kg = K;
info.total_ship_kg = sum(x);
info.capacity_slack_kg = K - sum(x);
info.capacity_binding = abs(info.capacity_slack_kg) <= 1e-7;
info.donor_binding = abs(I - out) <= 1e-7;
info.dual_donor = piDonor;
info.dual_gap = piGap;
info.dual_capacity = pi(capacityRow);
info.dual_inventory_subgradient = grad;
info.primal_residual = primalResidual;
info.dual_residual = dualResidual;
info.complementarity_residual = complementarityResidual;
info.nvars = nOD + Ni;
info.nineq = capacityRow;
info.pairwise_road_mask_used = false;
info.transshipment_allowed = false;
info.terminal_recourse_mode = 'TERMINAL_REDISTRIBUTION';
end

function cost = terminal_cost_matrix_h2(params, k, Ni)
if isfield(params,'cost_transport_base')
    cost = double(params.cost_transport_base);
elseif isfield(params,'transport_cost_base')
    cost = double(params.transport_cost_base);
else
    error('solve_terminal_redistribution_h2:MissingTransportCost', ...
        'No formal HTT OD cost matrix was found in params.');
end
if ~isequal(size(cost),[Ni,Ni]) || any(~isfinite(cost(:))) || any(cost(:) < 0)
    error('solve_terminal_redistribution_h2:BadTransportCost', ...
        'Formal HTT OD cost matrix must be finite and nonnegative.');
end
if isfield(params,'use_beta_cost') && logical(params.use_beta_cost)
    beta = 0;
    if isfield(params,'beta') && ~isempty(params.beta); beta = params.beta(k); end
    multiplier = 0;
    if isfield(params,'beta_transport_multiplier')
        multiplier = params.beta_transport_multiplier;
    end
    cost = cost * (1 + multiplier * beta);
end
if isfield(params,'htt_base_service_cost_yuan_per_kg')
    serviceCost = double(params.htt_base_service_cost_yuan_per_kg);
    if ~isscalar(serviceCost) || ~isfinite(serviceCost) || serviceCost < 0
        error('solve_terminal_redistribution_h2:BadServiceCost', ...
            'HTT base service cost must be finite and nonnegative.');
    end
    cost = cost + serviceCost;
end
cost(1:Ni + 1:end) = 0;
end
