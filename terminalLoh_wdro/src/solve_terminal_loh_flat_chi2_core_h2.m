function sol = solve_terminal_loh_flat_chi2_core_h2( ...
        Dperiod, Aperiod, Cperiod, q, Cap, M, gamma, eta, config)
%SOLVE_TERMINAL_LOH_FLAT_CHI2_CORE_H2 Sparse formal SAA/chi-square model.
%
% Eta zero builds the weighted SAA LP directly. Positive eta builds the
% exact Pearson chi-square single-level convex QCP. Only positive-demand,
% reachable service arcs are created; no scenario-pair matrix is used.

if nargin < 9 || isempty(config), config = struct(); end
config = fill_defaults(config);
[G, K, N] = size(Dperiod);
I = size(Aperiod, 3);
q = double(q(:)); Cap = double(Cap(:)); eta = double(eta);
validate_inputs(Dperiod, Aperiod, Cperiod, q, Cap, M, gamma, eta, G, K, I, N);
q = q ./ sum(q);
if eta <= config.etaZeroTolerance
    mode = "SAA";
    eta = 0;
else
    mode = "FLAT_CHI2_DRO";
end
if ~ismember(exist('gurobi', 'file'), [2, 3])
    error('solve_terminal_loh_flat_chi2_core_h2:MissingGurobi', ...
        'The Gurobi MATLAB interface is required.');
end

buildStarted = tic;
scale = config.objectiveScale;
Ceff = Cperiod;
Ceff(~isfinite(Ceff) | Aperiod <= 0.5) = 0;
demandMask = Dperiod > 0;
yMask = Aperiod > 0.5 & reshape(demandMask, [G, K, 1, N]);
demandLinear = find(demandMask);
yLinear = find(yMask);
nU = numel(demandLinear);
nY = numel(yLinear);
[gU, kU, nUsub] = ind2sub([G, K, N], demandLinear);
[gY, kY, iY, nYsub] = ind2sub([G, K, I, N], yLinear);

next = 1;
idx.T = next:(next + I - 1); next = next + I;
idx.y = next:(next + nY - 1); next = next + nY;
idx.u = next:(next + nU - 1); next = next + nU;
if mode == "FLAT_CHI2_DRO"
    idx.z = next:(next + G - 1); next = next + G;
    idx.nu = next; next = next + 1;
    idx.lambda = next; next = next + 1;
    idx.t = next:(next + G - 1); next = next + G;
    idx.h = next:(next + G - 1); next = next + G;
else
    idx.z = []; idx.nu = []; idx.lambda = []; idx.t = []; idx.h = [];
end
nvar = next - 1;

obj = zeros(nvar, 1);
obj(idx.T) = gamma / scale;
if mode == "SAA"
    obj(idx.y) = q(gY) .* Ceff(yLinear) ./ scale;
    obj(idx.u) = q(gU) .* M ./ scale;
else
    obj(idx.nu) = 1;
    obj(idx.lambda) = eta - 1;
    obj(idx.h) = q;
end
lb = zeros(nvar, 1); ub = inf(nvar, 1);
ub(idx.T) = Cap;
if mode == "FLAT_CHI2_DRO", lb(idx.nu) = -inf; end

demandRow = zeros(G, K, N, 'uint32');
demandRow(demandLinear) = uint32(1:nU);
yDemandLinear = sub2ind([G, K, N], gY, kY, nYsub);
yDemandRows = double(demandRow(yDemandLinear));
nDemandRows = nU;
nCapacityRows = G * I;
nLossRows = double(mode == "FLAT_CHI2_DRO") * G;
nRiskRows = double(mode == "FLAT_CHI2_DRO") * G;
nRows = nDemandRows + nCapacityRows + nLossRows + nRiskRows;

nnzEstimate = nU + 2 * nY + nCapacityRows;
if mode == "FLAT_CHI2_DRO"
    nnzEstimate = nnzEstimate + nY + nU + G + 4 * G;
end
rowIndex = zeros(nnzEstimate, 1);
colIndex = zeros(nnzEstimate, 1);
value = zeros(nnzEstimate, 1);
nz = 0;

positions = nz + (1:nU); rowIndex(positions) = 1:nU;
colIndex(positions) = idx.u; value(positions) = 1; nz = nz + nU;
positions = nz + (1:nY); rowIndex(positions) = yDemandRows;
colIndex(positions) = idx.y; value(positions) = 1; nz = nz + nY;

capacityRowsForY = nDemandRows + (gY - 1) * I + iY;
positions = nz + (1:nY); rowIndex(positions) = capacityRowsForY;
colIndex(positions) = idx.y; value(positions) = 1; nz = nz + nY;
for ii = 1:I
    rows = nDemandRows + (0:(G - 1)) * I + ii;
    positions = nz + (1:G); rowIndex(positions) = rows;
    colIndex(positions) = idx.T(ii); value(positions) = -1; nz = nz + G;
end

rhs = zeros(nRows, 1);
sense = repmat('<', nRows, 1);
rhs(1:nDemandRows) = Dperiod(demandLinear);
sense(1:nDemandRows) = '=';

if mode == "FLAT_CHI2_DRO"
    lossStart = nDemandRows + nCapacityRows;
    lossRows = lossStart + (1:G);
    positions = nz + (1:G); rowIndex(positions) = lossRows;
    colIndex(positions) = idx.z; value(positions) = 1; nz = nz + G;
    positions = nz + (1:nY); rowIndex(positions) = lossStart + gY;
    colIndex(positions) = idx.y; value(positions) = -Ceff(yLinear) ./ scale; nz = nz + nY;
    positions = nz + (1:nU); rowIndex(positions) = lossStart + gU;
    colIndex(positions) = idx.u; value(positions) = -M ./ scale; nz = nz + nU;
    sense(lossRows) = '=';

    riskStart = lossStart + G;
    riskRows = riskStart + (1:G);
    positions = nz + (1:G); rowIndex(positions) = riskRows;
    colIndex(positions) = idx.z; value(positions) = 1; nz = nz + G;
    positions = nz + (1:G); rowIndex(positions) = riskRows;
    colIndex(positions) = idx.nu; value(positions) = -1; nz = nz + G;
    positions = nz + (1:G); rowIndex(positions) = riskRows;
    colIndex(positions) = idx.lambda; value(positions) = 2; nz = nz + G;
    positions = nz + (1:G); rowIndex(positions) = riskRows;
    colIndex(positions) = idx.t; value(positions) = -1; nz = nz + G;
end
if nz ~= nnzEstimate
    error('solve_terminal_loh_flat_chi2_core_h2:Construction', ...
        'Sparse nonzero count mismatch.');
end

model = struct('A', sparse(rowIndex, colIndex, value, nRows, nvar), ...
    'obj', obj, 'rhs', rhs, 'sense', sense, 'lb', lb, 'ub', ub, ...
    'modelsense', 'min', 'modelname', char(mode));
if mode == "FLAT_CHI2_DRO"
    quadcon = repmat(struct('Qc', [], 'q', [], 'rhs', 0, ...
        'sense', '<', 'name', ''), G, 1);
    for gg = 1:G
        Q = sparse(nvar, nvar);
        Q(idx.t(gg), idx.t(gg)) = 1;
        Q(idx.lambda, idx.h(gg)) = -2;
        Q(idx.h(gg), idx.lambda) = -2;
        quadcon(gg).Qc = Q;
        quadcon(gg).q = sparse(nvar, 1);
        quadcon(gg).rhs = 0;
        quadcon(gg).sense = '<';
        quadcon(gg).name = sprintf('pearson_rotated_%d', gg);
    end
    model.quadcon = quadcon;
end
buildRuntime = toc(buildStarted);

params = struct('OutputFlag', config.gurobiOutputFlag, ...
    'FeasibilityTol', config.gurobiFeasibilityTol, ...
    'OptimalityTol', config.gurobiOptimalityTol, ...
    'TimeLimit', config.gurobiTimeLimit, 'InfUnbdInfo', 1, ...
    'Threads', config.gurobiThreads);
if mode == "FLAT_CHI2_DRO"
    params.BarConvTol = config.gurobiBarConvTol;
    params.BarQCPConvTol = config.gurobiBarQCPConvTol;
    params.Method = 2;
end
if strlength(string(config.resultFile)) > 0
    params.ResultFile = char(config.resultFile);
end
solveStarted = tic;
result = gurobi(model, params);
solveRuntime = toc(solveStarted);

sol = empty_solution(mode, G, I, eta, buildRuntime, solveRuntime, ...
    nvar, nRows, nnz(model.A), nY, nU, config);
sol.status = string(result.status);
if ~strcmp(result.status, 'OPTIMAL')
    if isfield(result, 'objval'), sol.objective_value = result.objval * scale; end
    return;
end

x = result.x;
yValue = x(idx.y); uValue = x(idx.u);
serviceCost = accumarray(gY, Ceff(yLinear) .* yValue, [G, 1]);
shortageKg = accumarray(gU, uValue, [G, 1]);
operatingLoss = serviceCost + M .* shortageKg;
siteService = accumarray([gY, iY], yValue, [G, I]);
demandService = accumarray(yDemandRows, yValue, [nU, 1]);
demandResidual = max(abs(demandService + uValue - Dperiod(demandLinear)), ...
    [], 'omitnan');
capacityViolation = max(siteService - x(idx.T).', [], 'all');

sol.exitflag = 1;
sol.T = x(idx.T);
sol.terminal_loh_total = sum(sol.T);
sol.first_stage_cost = gamma * sol.terminal_loh_total;
sol.scenario_operating_loss = operatingLoss;
sol.nominal_expected_recourse = sum(q .* operatingLoss);
sol.site_service_by_scenario = siteService;
sol.max_demand_balance_error = default_zero(demandResidual);
sol.max_site_capacity_violation = default_zero(capacityViolation);
sol.objective_value = result.objval * scale;
if mode == "SAA"
    sol.model_risk_value = sol.nominal_expected_recourse;
    sol.objective_reconstruction_error = abs(sol.objective_value - ...
        (sol.first_stage_cost + sol.nominal_expected_recourse));
    sol.qcp_residual = 0;
else
    sol.nu = x(idx.nu) * scale;
    sol.lambda = x(idx.lambda) * scale;
    sol.t = x(idx.t) * scale;
    sol.h = x(idx.h) * scale;
    sol.model_risk_value = sol.nu + sol.lambda * (eta - 1) + sum(q .* sol.h);
    sol.objective_reconstruction_error = abs(sol.objective_value - ...
        (sol.first_stage_cost + sol.model_risk_value));
    sol.qcp_residual = max((sol.t.^2 - 4 .* sol.lambda .* sol.h) ./ ...
        (scale.^2), [], 'omitnan');
    sol.maximum_risk_linear_violation_raw_cost_units = max( ...
        operatingLoss - sol.nu + 2 .* sol.lambda - sol.t, [], 'omitnan');
    sol.maximum_risk_linear_violation = ...
        sol.maximum_risk_linear_violation_raw_cost_units ./ scale;
end
end

function validate_inputs(D, A, C, q, Cap, M, gamma, eta, G, K, I, N)
if G < 1 || K ~= 3 || I ~= 4 || N < 1 || ...
        ~isequal(size(A), [G, K, I, N]) || ...
        ~isequal(size(C), [G, K, I, N]) || numel(q) ~= G || ...
        numel(Cap) ~= I || any(~isfinite(D), 'all') || any(D < 0, 'all') || ...
        any(A > 0.5 & ~isfinite(C), 'all') || any(~isfinite(q)) || ...
        any(q <= 0) || any(~isfinite(Cap)) || any(Cap < 0) || ...
        ~isscalar(M) || ~isfinite(M) || M <= 0 || ...
        ~isscalar(gamma) || ~isfinite(gamma) || gamma < 0 || ...
        ~isscalar(eta) || ~isfinite(eta) || eta < 0
    error('solve_terminal_loh_flat_chi2_core_h2:BadInput', ...
        'Formal period arrays, probabilities, costs, or eta are invalid.');
end
end

function config = fill_defaults(config)
defaults = struct('gurobiOutputFlag', 0, 'gurobiFeasibilityTol', 1e-8, ...
    'gurobiOptimalityTol', 1e-8, 'gurobiBarConvTol', 1e-9, ...
    'gurobiBarQCPConvTol', 1e-8, 'gurobiTimeLimit', 1800, ...
    'gurobiThreads', 0, 'objectiveScale', 1e5, ...
    'etaZeroTolerance', 1e-14, 'resultFile', "");
names = fieldnames(defaults);
for ii = 1:numel(names)
    if ~isfield(config, names{ii}) || isempty(config.(names{ii}))
        config.(names{ii}) = defaults.(names{ii});
    end
end
end

function sol = empty_solution(mode, G, I, eta, buildRuntime, solveRuntime, ...
        nvar, nRows, matrixNnz, nY, nU, config)
sol = struct('mode', mode, 'status', "NOT_SOLVED", 'exitflag', 0, ...
    'R_model', G, 'eta', eta, 'T', NaN(I, 1), ...
    'terminal_loh_total', NaN, 'first_stage_cost', NaN, ...
    'scenario_operating_loss', NaN(G, 1), ...
    'nominal_expected_recourse', NaN, 'model_risk_value', NaN, ...
    'objective_value', NaN, 'objective_reconstruction_error', NaN, ...
    'max_demand_balance_error', NaN, ...
    'max_site_capacity_violation', NaN, 'qcp_residual', NaN, ...
    'maximum_risk_linear_violation', NaN, ...
    'maximum_risk_linear_violation_raw_cost_units', NaN, ...
    'nu', NaN, 'lambda', NaN, ...
    't', NaN(G, 1), 'h', NaN(G, 1), ...
    'site_service_by_scenario', NaN(G, I), ...
    'build_runtime_sec', buildRuntime, 'solve_runtime_sec', solveRuntime, ...
    'variable_count', nvar, 'linear_constraint_count', nRows, ...
    'linear_matrix_nnz', matrixNnz, ...
    'quadratic_constraint_count', double(mode == "FLAT_CHI2_DRO") * G, ...
    'service_variable_count', nY, 'shortage_variable_count', nU, ...
    'constructed_R_by_R_matrix', false, ...
    'objective_scale', config.objectiveScale);
end

function value = default_zero(value)
if isempty(value) || ~isfinite(value), value = 0; end
end
