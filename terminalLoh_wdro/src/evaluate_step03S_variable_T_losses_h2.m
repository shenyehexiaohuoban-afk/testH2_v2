function out = evaluate_step03S_variable_T_losses_h2( ...
        D, A, C, Trows, M, config)
%EVALUATE_STEP03S_VARIABLE_T_LOSSES_H2 Evaluate one T vector per scenario.

if nargin < 6 || isempty(config)
    config = struct();
end
config = fill_defaults(config);
[R, N] = size(D);
I = size(A, 2);
if ~isequal(size(A), [R, I, N]) || ~isequal(size(C), [R, I, N]) || ...
        ~isequal(size(Trows), [R, I])
    error('evaluate_step03S_variable_T_losses_h2:BadArraySize', ...
        'Expected D=R x N, A/C=R x I x N, and Trows=R x I.');
end
if any(~isfinite(D), 'all') || any(D < 0, 'all') || ...
        any(A > 0.5 & ~isfinite(C), 'all') || ...
        any(~isfinite(Trows), 'all') || any(Trows < -1e-10, 'all')
    error('evaluate_step03S_variable_T_losses_h2:BadInput', ...
        'D, reachable C, and per-row T must satisfy the model domains.');
end

Ceff = C;
Ceff(~isfinite(Ceff) | A <= 0.5) = 0;
next = 1;
idx.y = reshape(next:(next + R * I * N - 1), [R, I, N]);
next = next + R * I * N;
idx.u = reshape(next:(next + R * N - 1), [R, N]);
nvar = next + R * N - 1;
obj = zeros(nvar, 1);
obj(idx.y(:)) = Ceff(:);
obj(idx.u(:)) = M;
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
        positions = kk + (1:numel(cols));
        rowIdx(positions) = rr;
        colIdx(positions) = cols;
        val(positions) = 1;
        kk = kk + numel(cols);
        rhs(rr) = D(ss, nn);
        sense(rr) = '=';
    end
    for ii = 1:I
        rr = rr + 1;
        cols = reshape(idx.y(ss, ii, :), 1, []);
        positions = kk + (1:numel(cols));
        rowIdx(positions) = rr;
        colIdx(positions) = cols;
        val(positions) = 1;
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
out = struct('status', string(result.status), 'exitflag', 0, ...
    'service_cost', NaN(R, 1), 'shortage_kg', NaN(R, 1), ...
    'loss', NaN(R, 1), 'runtime_sec', runtime, ...
    'objective_reconstruction_abs_error', NaN, ...
    'max_demand_balance_error', NaN, ...
    'max_site_capacity_violation', NaN);
if ~strcmp(result.status, 'OPTIMAL')
    return;
end
y = result.x(idx.y);
u = result.x(idx.u);
out.exitflag = 1;
out.service_cost = reshape(sum(Ceff .* y, [2, 3]), [], 1);
out.shortage_kg = sum(u, 2);
out.loss = out.service_cost + M .* out.shortage_kg;
out.objective_reconstruction_abs_error = abs(sum(out.loss) - result.objval);
out.max_demand_balance_error = max(abs( ...
    reshape(sum(y, 2), R, N) + u - D), [], 'all');
out.max_site_capacity_violation = max( ...
    reshape(sum(y, 3), R, I) - Trows, [], 'all');
end

function config = fill_defaults(config)
defaults = struct('gurobiOutputFlag', 0, 'gurobiFeasibilityTol', 1e-9, ...
    'gurobiOptimalityTol', 1e-9, 'gurobiTimeLimit', 300);
names = fieldnames(defaults);
for ii = 1:numel(names)
    if ~isfield(config, names{ii}) || isempty(config.(names{ii}))
        config.(names{ii}) = defaults.(names{ii});
    end
end
end
