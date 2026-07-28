function out = evaluate_step03Y_period_fixed_T_recourse_h2( ...
        Dperiod, Aperiod, Cperiod, Trows, M, config)
%EVALUATE_STEP03Y_PERIOD_FIXED_T_RECOURSE_H2 Fixed-T three-period LP.

if nargin < 6 || isempty(config), config = struct(); end
config = fill_defaults(config);
[R, K, N] = size(Dperiod);
I = size(Aperiod, 3);
if size(Aperiod, 1) ~= R || size(Aperiod, 2) ~= K || ...
        size(Aperiod, 3) ~= I || size(Aperiod, 4) ~= N || ...
        size(Cperiod, 1) ~= R || size(Cperiod, 2) ~= K || ...
        size(Cperiod, 3) ~= I || size(Cperiod, 4) ~= N || ...
        size(Trows, 1) ~= R || size(Trows, 2) ~= I
    error('evaluate_step03Y_period_fixed_T_recourse_h2:BadArraySize', ...
        'Expected D=R x K x N, A/C=R x K x I x N, and T=R x I.');
end
if any(~isfinite(Dperiod), 'all') || any(Dperiod < 0, 'all') || ...
        any(Aperiod > 0.5 & ~isfinite(Cperiod), 'all') || ...
        any(~isfinite(Trows), 'all') || any(Trows < -1e-10, 'all') || ...
        ~isscalar(M) || ~isfinite(M) || M <= 0
    error('evaluate_step03Y_period_fixed_T_recourse_h2:BadInput', ...
        'Period D, reachable C, fixed T, and shortage penalty are invalid.');
end
if ~ismember(exist('gurobi', 'file'), [2, 3])
    error('evaluate_step03Y_period_fixed_T_recourse_h2:MissingGurobi', ...
        'The Gurobi MATLAB interface is required for this fixed-T audit LP.');
end

Ceff = Cperiod;
Ceff(~isfinite(Ceff) | Aperiod <= 0.5) = 0;
next = 1;
idx.y = reshape(next:(next + R * K * I * N - 1), [R, K, I, N]);
next = next + R * K * I * N;
idx.u = reshape(next:(next + R * K * N - 1), [R, K, N]);
nvar = next + R * K * N - 1;
obj = zeros(nvar, 1);
obj(idx.y(:)) = Ceff(:) ./ config.objectiveScale;
obj(idx.u(:)) = M ./ config.objectiveScale;
lb = zeros(nvar, 1); ub = inf(nvar, 1);
yUpper = Aperiod .* reshape(Dperiod, [R, K, 1, N]);
ub(idx.y(:)) = yUpper(:);

nRows = R * K * N + R * I;
maxNnz = R * K * N * (I + 1) + R * I * K * N;
rowIdx = zeros(maxNnz, 1); colIdx = zeros(maxNnz, 1);
val = zeros(maxNnz, 1); rhs = zeros(nRows, 1);
sense = repmat('<', nRows, 1); rr = 0; nz = 0;
for ss = 1:R
    for tau = 1:K
        for nn = 1:N
            rr = rr + 1;
            cols = [reshape(idx.y(ss, tau, :, nn), 1, []), idx.u(ss, tau, nn)];
            pos = nz + (1:numel(cols)); rowIdx(pos) = rr;
            colIdx(pos) = cols; val(pos) = 1; nz = nz + numel(cols);
            rhs(rr) = Dperiod(ss, tau, nn); sense(rr) = '=';
        end
    end
    for ii = 1:I
        rr = rr + 1;
        cols = reshape(idx.y(ss, :, ii, :), 1, []);
        pos = nz + (1:numel(cols)); rowIdx(pos) = rr;
        colIdx(pos) = cols; val(pos) = 1; nz = nz + numel(cols);
        rhs(rr) = Trows(ss, ii);
    end
end
if rr ~= nRows, error('Period LP row construction mismatch.'); end
model = struct('A', sparse(rowIdx(1:nz), colIdx(1:nz), val(1:nz), ...
    nRows, nvar), 'obj', obj, 'rhs', rhs, 'sense', sense, ...
    'lb', lb, 'ub', ub, 'modelsense', 'min');
params = struct('OutputFlag', config.gurobiOutputFlag, ...
    'FeasibilityTol', config.gurobiFeasibilityTol, ...
    'OptimalityTol', config.gurobiOptimalityTol, ...
    'TimeLimit', config.gurobiTimeLimit, 'InfUnbdInfo', 1);
solveTic = tic; result = gurobi(model, params); runtime = toc(solveTic);
out = empty_output(R, K, I, N, runtime, string(result.status));
if ~strcmp(result.status, 'OPTIMAL'), return; end

y = reshape(result.x(idx.y(:)), [R, K, I, N]);
u = reshape(result.x(idx.u(:)), [R, K, N]);
transport = Ceff .* y;
out.exitflag = 1; out.y = y; out.u = u;
out.stage_site_service = reshape(sum(y, 4), [R, K, I]);
out.site_service_total = reshape(sum(y, [2, 4]), [R, I]);
out.unused_T = Trows - out.site_service_total;
out.stage_node_service = reshape(sum(y, 3), [R, K, N]);
out.stage_service_kg = reshape(sum(y, [3, 4]), [R, K]);
out.stage_shortage_kg = reshape(sum(u, 3), [R, K]);
out.stage_service_cost = reshape(sum(transport, [3, 4]), [R, K]);
out.stage_shortage_loss = M .* out.stage_shortage_kg;
out.stage_operating_loss = out.stage_service_cost + out.stage_shortage_loss;
out.service_cost = sum(out.stage_service_cost, 2);
out.shortage_kg = sum(out.stage_shortage_kg, 2);
out.shortage_loss = M .* out.shortage_kg;
out.operating_loss = out.service_cost + out.shortage_loss;
out.objective_reconstruction_abs_error = ...
    abs(sum(out.operating_loss) - result.objval .* config.objectiveScale);
out.max_demand_balance_error = max(abs(out.stage_node_service + u - Dperiod), [], 'all');
out.max_site_capacity_violation = max(out.site_service_total - Trows, [], 'all');
end

function config = fill_defaults(config)
defaults = struct('gurobiOutputFlag', 0, 'gurobiFeasibilityTol', 1e-9, ...
    'gurobiOptimalityTol', 1e-9, 'gurobiTimeLimit', 300, 'objectiveScale', 1);
names = fieldnames(defaults);
for ii = 1:numel(names)
    if ~isfield(config, names{ii}) || isempty(config.(names{ii}))
        config.(names{ii}) = defaults.(names{ii});
    end
end
end

function out = empty_output(R, K, I, N, runtime, status)
out = struct('status', status, 'exitflag', 0, 'runtime_sec', runtime, ...
    'y', NaN(R, K, I, N), 'u', NaN(R, K, N), ...
    'stage_site_service', NaN(R, K, I), ...
    'site_service_total', NaN(R, I), 'unused_T', NaN(R, I), ...
    'stage_node_service', NaN(R, K, N), ...
    'stage_service_kg', NaN(R, K), 'stage_shortage_kg', NaN(R, K), ...
    'stage_service_cost', NaN(R, K), 'stage_shortage_loss', NaN(R, K), ...
    'stage_operating_loss', NaN(R, K), 'service_cost', NaN(R, 1), ...
    'shortage_kg', NaN(R, 1), 'shortage_loss', NaN(R, 1), ...
    'operating_loss', NaN(R, 1), ...
    'objective_reconstruction_abs_error', NaN, ...
    'max_demand_balance_error', NaN, 'max_site_capacity_violation', NaN);
end
