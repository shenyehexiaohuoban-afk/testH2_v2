function out = evaluate_step03T_fixed_T_recourse_h2(D, A, C, Trows, M, config)
%EVALUATE_STEP03T_FIXED_T_RECOURSE_H2 Replay fixed layouts with full detail.

if nargin < 6 || isempty(config)
    config = struct();
end
config = fill_defaults(config);
[R, N] = size(D);
I = size(A, 2);
if ~isequal(size(A), [R, I, N]) || ~isequal(size(C), [R, I, N]) || ...
        ~isequal(size(Trows), [R, I])
    error('evaluate_step03T_fixed_T_recourse_h2:BadArraySize', ...
        'Expected D=R x N, A/C=R x I x N, and Trows=R x I.');
end
if any(~isfinite(D), 'all') || any(D < 0, 'all') || ...
        any(A > 0.5 & ~isfinite(C), 'all') || ...
        any(~isfinite(Trows), 'all') || any(Trows < -1e-10, 'all')
    error('evaluate_step03T_fixed_T_recourse_h2:BadInput', ...
        'D, reachable C, and fixed T must satisfy the recourse domains.');
end
if ~ismember(exist('gurobi', 'file'), [2, 3])
    error('evaluate_step03T_fixed_T_recourse_h2:MissingGurobi', ...
        'The existing Gurobi MATLAB interface is required.');
end

Ceff = C;
Ceff(~isfinite(Ceff) | A <= 0.5) = 0;
next = 1;
idx.y = reshape(next:(next + R * I * N - 1), [R, I, N]);
next = next + R * I * N;
idx.u = reshape(next:(next + R * N - 1), [R, N]);
nvar = next + R * N - 1;
obj = zeros(nvar, 1);
obj(idx.y(:)) = Ceff(:) ./ config.objectiveScale;
obj(idx.u(:)) = M ./ config.objectiveScale;
lb = zeros(nvar, 1);
ub = inf(nvar, 1);
yUpper = A .* reshape(D, [R, 1, N]);
ub(idx.y(:)) = yUpper(:);

nRows = R * N + R * I;
maxNnz = R * N * (I + 1) + R * I * N;
rowIdx = zeros(maxNnz, 1);
colIdx = zeros(maxNnz, 1);
val = zeros(maxNnz, 1);
rhs = zeros(nRows, 1);
sense = repmat('<', nRows, 1);
rr = 0;
kk = 0;
for ss = 1:R
    for nn = 1:N
        rr = rr + 1;
        cols = [reshape(idx.y(ss, :, nn), 1, []), idx.u(ss, nn)];
        pos = kk + (1:numel(cols));
        rowIdx(pos) = rr;
        colIdx(pos) = cols;
        val(pos) = 1;
        kk = kk + numel(cols);
        rhs(rr) = D(ss, nn);
        sense(rr) = '=';
    end
    for ii = 1:I
        rr = rr + 1;
        cols = reshape(idx.y(ss, ii, :), 1, []);
        pos = kk + (1:numel(cols));
        rowIdx(pos) = rr;
        colIdx(pos) = cols;
        val(pos) = 1;
        kk = kk + numel(cols);
        rhs(rr) = Trows(ss, ii);
    end
end

model = struct('A', sparse(rowIdx(1:kk), colIdx(1:kk), ...
    val(1:kk), nRows, nvar), 'obj', obj, 'rhs', rhs, ...
    'sense', sense, 'lb', lb, 'ub', ub, 'modelsense', 'min');
params = struct('OutputFlag', config.gurobiOutputFlag, ...
    'FeasibilityTol', config.gurobiFeasibilityTol, ...
    'OptimalityTol', config.gurobiOptimalityTol, ...
    'TimeLimit', config.gurobiTimeLimit, 'InfUnbdInfo', 1);
solveTic = tic;
result = gurobi(model, params);
runtime = toc(solveTic);
out = empty_output(R, I, N, runtime, string(result.status));
if ~strcmp(result.status, 'OPTIMAL')
    return;
end

y = reshape(result.x(idx.y(:)), [R, I, N]);
u = reshape(result.x(idx.u(:)), [R, N]);
transportByRelation = Ceff .* y;
out.exitflag = 1;
out.y = y;
out.u = u;
out.site_service = reshape(sum(y, 3), [R, I]);
out.unused_T = Trows - out.site_service;
out.node_service = reshape(sum(y, 2), [R, N]);
out.transport_by_relation = transportByRelation;
out.transport_by_node = reshape(sum(transportByRelation, 2), [R, N]);
out.transport_by_site = reshape(sum(transportByRelation, 3), [R, I]);
out.shortage_loss_by_node = M .* u;
out.node_operating_loss = out.transport_by_node + out.shortage_loss_by_node;
out.service_cost = sum(out.transport_by_node, 2);
out.shortage_kg = sum(u, 2);
out.shortage_loss = M .* out.shortage_kg;
out.operating_loss = out.service_cost + out.shortage_loss;
out.holding_cost = config.gamma .* sum(Trows, 2);
out.full_objective = out.operating_loss + out.holding_cost;
out.objective_reconstruction_abs_error = ...
    abs(sum(out.operating_loss) - result.objval .* config.objectiveScale);
out.max_demand_balance_error = max(abs(out.node_service + u - D), [], 'all');
out.max_site_capacity_violation = max(out.site_service - Trows, [], 'all');
end

function config = fill_defaults(config)
defaults = struct('gamma', 2, 'gurobiOutputFlag', 0, ...
    'gurobiFeasibilityTol', 1e-9, 'gurobiOptimalityTol', 1e-9, ...
    'gurobiTimeLimit', 300, 'objectiveScale', 1);
names = fieldnames(defaults);
for ii = 1:numel(names)
    if ~isfield(config, names{ii}) || isempty(config.(names{ii}))
        config.(names{ii}) = defaults.(names{ii});
    end
end
end

function out = empty_output(R, I, N, runtime, status)
out = struct('status', status, 'exitflag', 0, 'runtime_sec', runtime, ...
    'y', NaN(R, I, N), 'u', NaN(R, N), ...
    'site_service', NaN(R, I), 'unused_T', NaN(R, I), ...
    'node_service', NaN(R, N), ...
    'transport_by_relation', NaN(R, I, N), ...
    'transport_by_node', NaN(R, N), ...
    'transport_by_site', NaN(R, I), ...
    'shortage_loss_by_node', NaN(R, N), ...
    'node_operating_loss', NaN(R, N), ...
    'service_cost', NaN(R, 1), 'shortage_kg', NaN(R, 1), ...
    'shortage_loss', NaN(R, 1), 'operating_loss', NaN(R, 1), ...
    'holding_cost', NaN(R, 1), 'full_objective', NaN(R, 1), ...
    'objective_reconstruction_abs_error', NaN, ...
    'max_demand_balance_error', NaN, ...
    'max_site_capacity_violation', NaN);
end
