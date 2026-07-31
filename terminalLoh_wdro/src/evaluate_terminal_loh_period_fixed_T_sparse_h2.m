function out = evaluate_terminal_loh_period_fixed_T_sparse_h2( ...
        Dperiod, Aperiod, Cperiod, Trows, M, config)
%EVALUATE_TERMINAL_LOH_PERIOD_FIXED_T_SPARSE_H2 Formal fixed-T evaluator.
%
% Builds only positive-demand, reachable service arcs. Each scenario is
% still an independent copy of the frozen three-period recourse LP.

if nargin < 6 || isempty(config), config = struct(); end
config = fill_defaults(config);
[R, K, N] = size(Dperiod); I = size(Aperiod, 3);
if R < 1 || K ~= 3 || I ~= 4 || ...
        ~isequal(size(Aperiod), [R, K, I, N]) || ...
        ~isequal(size(Cperiod), [R, K, I, N]) || ...
        ~isequal(size(Trows), [R, I]) || any(~isfinite(Dperiod), 'all') || ...
        any(Dperiod < 0, 'all') || ...
        any(Aperiod > 0.5 & ~isfinite(Cperiod), 'all') || ...
        any(~isfinite(Trows), 'all') || any(Trows < -1e-10, 'all') || ...
        ~isscalar(M) || ~isfinite(M) || M <= 0
    error('evaluate_terminal_loh_period_fixed_T_sparse_h2:BadInput', ...
        'Formal D/A/C, Trows, or M is invalid.');
end
if ~ismember(exist('gurobi', 'file'), [2, 3])
    error('evaluate_terminal_loh_period_fixed_T_sparse_h2:MissingGurobi', ...
        'The Gurobi MATLAB interface is required.');
end

buildStarted = tic;
Ceff = Cperiod; Ceff(~isfinite(Ceff) | Aperiod <= 0.5) = 0;
demandMask = Dperiod > 0;
yMask = Aperiod > 0.5 & reshape(demandMask, [R, K, 1, N]);
demandLinear = find(demandMask); yLinear = find(yMask);
nU = numel(demandLinear); nY = numel(yLinear);
[gU, ~, ~] = ind2sub([R, K, N], demandLinear);
[gY, ~, iY, nYsub] = ind2sub([R, K, I, N], yLinear);

out = empty_output(R, I, nY, nU);
if nU == 0
    out.status = "OPTIMAL_ZERO_DEMAND"; out.exitflag = 1;
    out.operating_loss = zeros(R, 1); out.service_cost = zeros(R, 1);
    out.shortage_kg = zeros(R, 1); out.site_service_total = zeros(R, I);
    out.build_runtime_sec = toc(buildStarted); out.solve_runtime_sec = 0;
    out.max_demand_balance_error = 0; out.max_site_capacity_violation = 0;
    return;
end

idx.y = 1:nY; idx.u = nY + (1:nU); nvar = nY + nU;
obj = zeros(nvar, 1);
obj(idx.y) = Ceff(yLinear) ./ config.objectiveScale;
obj(idx.u) = M ./ config.objectiveScale;
lb = zeros(nvar, 1); ub = inf(nvar, 1);

demandRow = zeros(R, K, N, 'uint32');
demandRow(demandLinear) = uint32(1:nU);
[~, kY, ~, ~] = ind2sub([R, K, I, N], yLinear);
yDemandLinear = sub2ind([R, K, N], gY, kY, nYsub);
yDemandRows = double(demandRow(yDemandLinear));
nRows = nU + R * I;
nnzCount = nU + 2 * nY;
rowIndex = zeros(nnzCount, 1); colIndex = zeros(nnzCount, 1);
value = ones(nnzCount, 1); nz = 0;
positions = nz + (1:nU); rowIndex(positions) = 1:nU;
colIndex(positions) = idx.u; nz = nz + nU;
positions = nz + (1:nY); rowIndex(positions) = yDemandRows;
colIndex(positions) = idx.y; nz = nz + nY;
positions = nz + (1:nY); rowIndex(positions) = nU + (gY - 1) * I + iY;
colIndex(positions) = idx.y; nz = nz + nY;

rhs = zeros(nRows, 1); sense = repmat('<', nRows, 1);
rhs(1:nU) = Dperiod(demandLinear); sense(1:nU) = '=';
rhs(nU + (1:(R * I))) = reshape(Trows.', [], 1);
model = struct('A', sparse(rowIndex, colIndex, value, nRows, nvar), ...
    'obj', obj, 'rhs', rhs, 'sense', sense, 'lb', lb, 'ub', ub, ...
    'modelsense', 'min', 'modelname', 'fixed_T_sparse_period_recourse');
out.build_runtime_sec = toc(buildStarted);
out.variable_count = nvar; out.linear_constraint_count = nRows;
out.linear_matrix_nnz = nnz(model.A);
params = struct('OutputFlag', config.gurobiOutputFlag, ...
    'FeasibilityTol', config.gurobiFeasibilityTol, ...
    'OptimalityTol', config.gurobiOptimalityTol, ...
    'TimeLimit', config.gurobiTimeLimit, 'InfUnbdInfo', 1, ...
    'Threads', config.gurobiThreads);
solveStarted = tic; result = gurobi(model, params); out.solve_runtime_sec = toc(solveStarted);
out.status = string(result.status);
if ~strcmp(result.status, 'OPTIMAL'), return; end

yValue = result.x(idx.y); uValue = result.x(idx.u);
serviceCost = accumarray(gY, Ceff(yLinear) .* yValue, [R, 1]);
shortageKg = accumarray(gU, uValue, [R, 1]);
siteService = accumarray([gY, iY], yValue, [R, I]);
demandService = accumarray(yDemandRows, yValue, [nU, 1]);
out.exitflag = 1;
out.service_cost = serviceCost;
out.shortage_kg = shortageKg;
out.shortage_loss = M .* shortageKg;
out.operating_loss = serviceCost + out.shortage_loss;
out.site_service_total = siteService;
capacityRows = nU + (1:(R * I));
if isfield(result, 'pi') && numel(result.pi) >= max(capacityRows)
    out.site_capacity_dual = reshape(result.pi(capacityRows), [I, R]).' .* ...
        config.objectiveScale;
else
    out.site_capacity_dual = NaN(R, I);
end
out.max_demand_balance_error = max(abs(demandService + uValue - ...
    Dperiod(demandLinear)), [], 'omitnan');
out.max_site_capacity_violation = max(siteService - Trows, [], 'all');
out.objective_reconstruction_abs_error = abs(sum(out.operating_loss) - ...
    result.objval * config.objectiveScale);
end

function config = fill_defaults(config)
defaults = struct('gurobiOutputFlag', 0, 'gurobiFeasibilityTol', 1e-9, ...
    'gurobiOptimalityTol', 1e-9, 'gurobiTimeLimit', 1800, ...
    'gurobiThreads', 0, 'objectiveScale', 1e5);
names = fieldnames(defaults);
for ii = 1:numel(names)
    if ~isfield(config, names{ii}) || isempty(config.(names{ii}))
        config.(names{ii}) = defaults.(names{ii});
    end
end
end

function out = empty_output(R, I, nY, nU)
out = struct('status', "NOT_SOLVED", 'exitflag', 0, ...
    'operating_loss', NaN(R, 1), 'service_cost', NaN(R, 1), ...
    'shortage_kg', NaN(R, 1), 'shortage_loss', NaN(R, 1), ...
    'site_service_total', NaN(R, I), ...
    'site_capacity_dual', NaN(R, I), ...
    'max_demand_balance_error', NaN, ...
    'max_site_capacity_violation', NaN, ...
    'objective_reconstruction_abs_error', NaN, ...
    'build_runtime_sec', NaN, 'solve_runtime_sec', NaN, ...
    'service_variable_count', nY, 'shortage_variable_count', nU, ...
    'variable_count', nY + nU, 'linear_constraint_count', NaN, ...
    'linear_matrix_nnz', NaN, 'constructed_R_by_R_matrix', false);
end
