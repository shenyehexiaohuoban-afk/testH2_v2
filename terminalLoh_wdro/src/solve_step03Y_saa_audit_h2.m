function sol = solve_step03Y_saa_audit_h2( ...
        mode, D, A, C, Cap, M, gamma, config)
%SOLVE_STEP03Y_SAA_AUDIT_H2 Independent aggregate/period SAA audit LP.

if nargin < 8 || isempty(config)
    config = struct();
end
config = fill_defaults(config);
mode = upper(string(mode));
if mode == "AGGREGATE"
    sol = solve_aggregate(D, A, C, Cap, M, gamma, config);
elseif mode == "PERIOD"
    sol = solve_period(D, A, C, Cap, M, gamma, config);
else
    error('solve_step03Y_saa_audit_h2:BadMode', ...
        'Mode must be AGGREGATE or PERIOD.');
end
sol.mode = mode;
end

function sol = solve_aggregate(D, A, C, Cap, M, gamma, config)
[R, N] = size(D);
I = numel(Cap);
if ~isequal(size(A), [R, I, N]) || ~isequal(size(C), [R, I, N])
    error('solve_step03Y_saa_audit_h2:AggregateSize', ...
        'Aggregate arrays do not have compatible dimensions.');
end
Ceff = C;
Ceff(~isfinite(Ceff) | A <= 0.5) = 0;

next = 1;
idx.T = next:(next + I - 1);
next = next + I;
idx.y = reshape(next:(next + R * I * N - 1), [R, I, N]);
next = next + R * I * N;
idx.u = reshape(next:(next + R * N - 1), [R, N]);
nvar = next + R * N - 1;

obj = zeros(nvar, 1);
obj(idx.T) = gamma;
obj(idx.y(:)) = Ceff(:) / R;
obj(idx.u(:)) = M / R;
lb = zeros(nvar, 1);
ub = inf(nvar, 1);
ub(idx.T) = Cap(:);
yUpper = A .* reshape(D, [R, 1, N]);
ub(idx.y(:)) = yUpper(:);

nRows = R * N + R * I;
maxNnz = R * N * (I + 1) + R * I * (N + 1);
rowIdx = zeros(maxNnz, 1);
colIdx = zeros(maxNnz, 1);
val = zeros(maxNnz, 1);
rhs = zeros(nRows, 1);
sense = repmat('<', nRows, 1);
row = 0;
nz = 0;
for scenario = 1:R
    for node = 1:N
        row = row + 1;
        cols = [reshape(idx.y(scenario, :, node), 1, []), ...
            idx.u(scenario, node)];
        positions = nz + (1:numel(cols));
        rowIdx(positions) = row;
        colIdx(positions) = cols;
        val(positions) = 1;
        nz = nz + numel(cols);
        rhs(row) = D(scenario, node);
        sense(row) = '=';
    end
    for site = 1:I
        row = row + 1;
        cols = [reshape(idx.y(scenario, site, :), 1, []), idx.T(site)];
        positions = nz + (1:numel(cols));
        rowIdx(positions) = row;
        colIdx(positions) = cols;
        val(positions) = [ones(1, N), -1];
        nz = nz + numel(cols);
    end
end
model = struct('A', sparse(rowIdx(1:nz), colIdx(1:nz), ...
    val(1:nz), nRows, nvar), 'obj', obj, 'rhs', rhs, ...
    'sense', sense, 'lb', lb, 'ub', ub, 'modelsense', 'min');
result = call_gurobi(model, config);
sol = unpack_aggregate(result, idx, D, Ceff, Cap, M, gamma, R, I, N);
sol.objective_weight_per_scenario = 1 / R;
sol.objective_weight_sum = 1;
sol.T_objective_coefficient = gamma;
sol.shortage_objective_coefficient = M / R;
sol.max_service_coefficient_reconstruction_error = ...
    max(abs(obj(idx.y(:)) .* R - Ceff(:)), [], 'all');
end

function sol = solve_period(D, A, C, Cap, M, gamma, config)
[R, K, N] = size(D);
I = numel(Cap);
if ~isequal(size(A), [R, K, I, N]) || ...
        ~isequal(size(C), [R, K, I, N])
    error('solve_step03Y_saa_audit_h2:PeriodSize', ...
        'Period arrays do not have compatible dimensions.');
end
Ceff = C;
Ceff(~isfinite(Ceff) | A <= 0.5) = 0;

next = 1;
idx.T = next:(next + I - 1);
next = next + I;
idx.y = reshape(next:(next + R * K * I * N - 1), [R, K, I, N]);
next = next + R * K * I * N;
idx.u = reshape(next:(next + R * K * N - 1), [R, K, N]);
nvar = next + R * K * N - 1;

obj = zeros(nvar, 1);
obj(idx.T) = gamma;
obj(idx.y(:)) = Ceff(:) / R;
obj(idx.u(:)) = M / R;
lb = zeros(nvar, 1);
ub = inf(nvar, 1);
ub(idx.T) = Cap(:);
yUpper = A .* reshape(D, [R, K, 1, N]);
ub(idx.y(:)) = yUpper(:);

nRows = R * K * N + R * I;
maxNnz = R * K * N * (I + 1) + R * I * (K * N + 1);
rowIdx = zeros(maxNnz, 1);
colIdx = zeros(maxNnz, 1);
val = zeros(maxNnz, 1);
rhs = zeros(nRows, 1);
sense = repmat('<', nRows, 1);
row = 0;
nz = 0;
for scenario = 1:R
    for period = 1:K
        for node = 1:N
            row = row + 1;
            cols = [reshape(idx.y(scenario, period, :, node), 1, []), ...
                idx.u(scenario, period, node)];
            positions = nz + (1:numel(cols));
            rowIdx(positions) = row;
            colIdx(positions) = cols;
            val(positions) = 1;
            nz = nz + numel(cols);
            rhs(row) = D(scenario, period, node);
            sense(row) = '=';
        end
    end
    for site = 1:I
        row = row + 1;
        cols = [reshape(idx.y(scenario, :, site, :), 1, []), idx.T(site)];
        positions = nz + (1:numel(cols));
        rowIdx(positions) = row;
        colIdx(positions) = cols;
        val(positions) = [ones(1, K * N), -1];
        nz = nz + numel(cols);
    end
end
model = struct('A', sparse(rowIdx(1:nz), colIdx(1:nz), ...
    val(1:nz), nRows, nvar), 'obj', obj, 'rhs', rhs, ...
    'sense', sense, 'lb', lb, 'ub', ub, 'modelsense', 'min');
result = call_gurobi(model, config);
sol = unpack_period(result, idx, D, Ceff, Cap, M, gamma, R, K, I, N);
sol.objective_weight_per_scenario = 1 / R;
sol.objective_weight_sum = 1;
sol.T_objective_coefficient = gamma;
sol.shortage_objective_coefficient = M / R;
sol.max_service_coefficient_reconstruction_error = ...
    max(abs(obj(idx.y(:)) .* R - Ceff(:)), [], 'all');
end

function result = call_gurobi(model, config)
if ~ismember(exist('gurobi', 'file'), [2, 3])
    error('solve_step03Y_saa_audit_h2:MissingGurobi', ...
        'Gurobi MATLAB interface is required for this audit LP.');
end
params = struct('OutputFlag', config.gurobiOutputFlag, ...
    'FeasibilityTol', config.gurobiFeasibilityTol, ...
    'OptimalityTol', config.gurobiOptimalityTol, ...
    'TimeLimit', config.gurobiTimeLimit, 'InfUnbdInfo', 1);
solveStarted = tic;
result = gurobi(model, params);
result.audit_runtime_sec = toc(solveStarted);
end

function sol = unpack_aggregate( ...
        result, idx, D, Ceff, Cap, M, gamma, R, I, N)
sol = empty_solution(result, I, R);
if sol.status ~= "OPTIMAL"
    return;
end
x = result.x;
y = reshape(x(idx.y(:)), [R, I, N]);
u = reshape(x(idx.u(:)), [R, N]);
siteService = reshape(sum(y, 3), [R, I]);
nodeService = reshape(sum(y, 2), [R, N]);
serviceCost = reshape(sum(Ceff .* y, [2, 3]), [R, 1]);
shortageKg = sum(u, 2);
sol = fill_solution(sol, result, idx, Cap, M, gamma, serviceCost, ...
    shortageKg, max(abs(nodeService + u - D), [], 'all'), ...
    max(siteService - x(idx.T).', [], 'all'));
end

function sol = unpack_period( ...
        result, idx, D, Ceff, Cap, M, gamma, R, K, I, N)
sol = empty_solution(result, I, R);
if sol.status ~= "OPTIMAL"
    return;
end
x = result.x;
y = reshape(x(idx.y(:)), [R, K, I, N]);
u = reshape(x(idx.u(:)), [R, K, N]);
siteService = reshape(sum(y, [2, 4]), [R, I]);
nodeService = reshape(sum(y, 3), [R, K, N]);
serviceCost = reshape(sum(Ceff .* y, [2, 3, 4]), [R, 1]);
shortageKg = reshape(sum(u, [2, 3]), [R, 1]);
sol = fill_solution(sol, result, idx, Cap, M, gamma, serviceCost, ...
    shortageKg, max(abs(nodeService + u - D), [], 'all'), ...
    max(siteService - x(idx.T).', [], 'all'));
end

function sol = empty_solution(result, I, R)
sol = struct('status', string(result.status), ...
    'runtime_sec', double(result.audit_runtime_sec), ...
    'R', R, 'T', NaN(I, 1), 'T_at_upper_bound', false(I, 1), ...
    'T_reduced_cost', NaN(I, 1), 'holding_cost', NaN, ...
    'mean_service_cost', NaN, 'mean_shortage_kg', NaN, ...
    'mean_shortage_loss', NaN, 'mean_operating_loss', NaN, ...
    'objective_value', NaN, 'objective_reconstruction_error', NaN, ...
    'max_demand_balance_error', NaN, ...
    'max_site_capacity_violation', NaN, ...
    'objective_weight_per_scenario', NaN, ...
    'objective_weight_sum', NaN, 'T_objective_coefficient', NaN, ...
    'shortage_objective_coefficient', NaN, ...
    'max_service_coefficient_reconstruction_error', NaN);
end

function sol = fill_solution(sol, result, idx, Cap, M, gamma, ...
        serviceCost, shortageKg, demandError, capacityViolation)
sol.T = result.x(idx.T);
sol.T_at_upper_bound = abs(sol.T - Cap(:)) <= 1e-7;
if isfield(result, 'rc') && numel(result.rc) >= max(idx.T)
    sol.T_reduced_cost = result.rc(idx.T);
end
sol.holding_cost = gamma * sum(sol.T);
sol.mean_service_cost = mean(serviceCost);
sol.mean_shortage_kg = mean(shortageKg);
sol.mean_shortage_loss = M * sol.mean_shortage_kg;
sol.mean_operating_loss = sol.mean_service_cost + sol.mean_shortage_loss;
sol.objective_value = result.objval;
sol.objective_reconstruction_error = abs(result.objval - ...
    (sol.holding_cost + sol.mean_operating_loss));
sol.max_demand_balance_error = demandError;
sol.max_site_capacity_violation = capacityViolation;
end

function config = fill_defaults(config)
defaults = struct('gurobiOutputFlag', 0, 'gurobiFeasibilityTol', 1e-9, ...
    'gurobiOptimalityTol', 1e-9, 'gurobiTimeLimit', 600);
names = fieldnames(defaults);
for ii = 1:numel(names)
    if ~isfield(config, names{ii}) || isempty(config.(names{ii}))
        config.(names{ii}) = defaults.(names{ii});
    end
end
end
