function out = evaluate_step03P_fixed_T_losses_h2(D, A, C, T, M, config)
%EVALUATE_STEP03P_FIXED_T_LOSSES_H2 Exact independent recourse by scenario.

if nargin < 6 || isempty(config)
    config = struct();
end
if ~isfield(config, 'gurobiOutputFlag') || isempty(config.gurobiOutputFlag)
    config.gurobiOutputFlag = 0;
end
if ~isfield(config, 'gurobiFeasibilityTol') || isempty(config.gurobiFeasibilityTol)
    config.gurobiFeasibilityTol = 1e-9;
end
if ~isfield(config, 'gurobiOptimalityTol') || isempty(config.gurobiOptimalityTol)
    config.gurobiOptimalityTol = 1e-9;
end
if ~isfield(config, 'gurobiTimeLimit') || isempty(config.gurobiTimeLimit)
    config.gurobiTimeLimit = 300;
end

[R, N] = size(D);
I = size(A, 2);
T = double(T(:));
if numel(T) ~= I || any(~isfinite(T)) || any(T < -1e-10)
    error('evaluate_step03P_fixed_T_losses_h2:BadT', ...
        'T must contain one finite nonnegative value per site.');
end
if ~isequal(size(A), [R, I, N]) || ~isequal(size(C), [R, I, N])
    error('evaluate_step03P_fixed_T_losses_h2:BadArraySize', ...
        'Expected A and C to have size R x I x N.');
end
if any(~isfinite(D), 'all') || any(D < 0, 'all') || ...
        any(A > 0.5 & ~isfinite(C), 'all')
    error('evaluate_step03P_fixed_T_losses_h2:BadInput', ...
        'D must be finite/nonnegative and reachable C must be finite.');
end

if max(T) <= 1e-14
    shortageKg = sum(D, 2);
    out = make_output("ANALYTIC_ZERO_T", 1, zeros(R, 1), ...
        shortageKg, M .* shortageKg, 0);
    return;
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
yUb = A .* reshape(D, [R, 1, N]);
ub(idx.y(:)) = yUb(:);

nRows = R * N + R * I;
maxNnz = R * N * (I + 1) + R * I * N;
rowIdx = zeros(maxNnz, 1);
colIdx = zeros(maxNnz, 1);
val = zeros(maxNnz, 1);
rhs = zeros(nRows, 1);
sense = repmat('<', nRows, 1);
rr = 0;
kk = 0;

    function add_term(row, col, value)
        kk = kk + 1;
        rowIdx(kk) = row;
        colIdx(kk) = col;
        val(kk) = value;
    end

for ss = 1:R
    for nn = 1:N
        rr = rr + 1;
        for ii = 1:I
            add_term(rr, idx.y(ss, ii, nn), 1);
        end
        add_term(rr, idx.u(ss, nn), 1);
        rhs(rr) = D(ss, nn);
        sense(rr) = '=';
    end
end
for ss = 1:R
    for ii = 1:I
        rr = rr + 1;
        for nn = 1:N
            add_term(rr, idx.y(ss, ii, nn), 1);
        end
        rhs(rr) = T(ii);
    end
end
if rr ~= nRows
    error('evaluate_step03P_fixed_T_losses_h2:InternalRows', ...
        'Internal recourse row count mismatch.');
end

model = struct();
model.A = sparse(rowIdx(1:kk), colIdx(1:kk), val(1:kk), nRows, nvar);
model.obj = obj;
model.rhs = rhs;
model.sense = sense;
model.lb = lb;
model.ub = ub;
model.modelsense = 'min';
params = struct('OutputFlag', config.gurobiOutputFlag, ...
    'FeasibilityTol', config.gurobiFeasibilityTol, ...
    'OptimalityTol', config.gurobiOptimalityTol, ...
    'TimeLimit', config.gurobiTimeLimit, 'InfUnbdInfo', 1);
solveTic = tic;
result = gurobi(model, params);
runtime = toc(solveTic);
if ~strcmp(result.status, 'OPTIMAL')
    out = make_output(string(result.status), 0, NaN(R, 1), ...
        NaN(R, 1), NaN(R, 1), runtime);
    out.raw = result;
    return;
end

x = result.x;
y = x(idx.y);
u = x(idx.u);
serviceCost = reshape(sum(Ceff .* y, [2, 3]), [], 1);
shortageKg = sum(u, 2);
loss = serviceCost + M .* shortageKg;
out = make_output(string(result.status), 1, serviceCost, shortageKg, loss, runtime);
out.objective_reconstruction_abs_error = abs(sum(loss) - result.objval);
out.max_demand_balance_error = max(abs( ...
    reshape(sum(y, 2), R, N) + u - D), [], 'all');
out.max_site_capacity_violation = max(reshape(sum(y, 3), R, I) - T.', [], 'all');
out.raw_status = string(result.status);
end

function out = make_output(status, exitflag, serviceCost, shortageKg, loss, runtime)
out = struct();
out.status = status;
out.exitflag = exitflag;
out.service_cost = serviceCost;
out.shortage_kg = shortageKg;
out.shortage_penalty = loss - serviceCost;
out.loss = loss;
out.runtime_sec = runtime;
out.objective_reconstruction_abs_error = 0;
out.max_demand_balance_error = 0;
out.max_site_capacity_violation = 0;
end
