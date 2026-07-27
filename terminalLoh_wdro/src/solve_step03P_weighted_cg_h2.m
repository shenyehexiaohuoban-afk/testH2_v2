function sol = solve_step03P_weighted_cg_h2( ...
        D, A, C, Cap, M, rho, dMat, sampleWeights, config)
%SOLVE_STEP03P_WEIGHTED_CG_H2 Audit-only exact CG with supplied cost matrix.

if nargin < 9 || isempty(config)
    config = struct();
end
config = fill_defaults(config, M);

if ~ismember(exist('gurobi', 'file'), [2, 3])
    error('solve_step03P_weighted_cg_h2:MissingGurobi', ...
        'The existing Gurobi MATLAB interface is required.');
end

[R, N] = size(D);
I = numel(Cap);
if ~isequal(size(A), [R, I, N]) || ~isequal(size(C), [R, I, N])
    error('solve_step03P_weighted_cg_h2:BadArraySize', ...
        'Expected A and C to have size R x I x N.');
end
if ~isequal(size(dMat), [R, R]) || any(~isfinite(dMat), 'all') || ...
        any(dMat < -1e-12, 'all')
    error('solve_step03P_weighted_cg_h2:BadTransportCost', ...
        'dMat must be a finite nonnegative R x R matrix.');
end
if max(abs(diag(dMat))) > 1e-10 || max(abs(dMat - dMat.'), [], 'all') > 1e-10
    error('solve_step03P_weighted_cg_h2:BadTransportCostStructure', ...
        'dMat must be symmetric with zero diagonal.');
end
sampleWeights = double(sampleWeights(:));
if numel(sampleWeights) ~= R || any(~isfinite(sampleWeights)) || ...
        any(sampleWeights < -1e-14) || abs(sum(sampleWeights) - 1) > 1e-12
    error('solve_step03P_weighted_cg_h2:BadWeights', ...
        'Sample weights must be nonnegative and sum to one.');
end

[baseModel, idx, modelInfo] = build_base_model( ...
    D, A, C, Cap, M, rho, sampleWeights, config);
activeMask = sparse(1:R, 1:R, true, R, R);
activeR = (1:R).';
activeS = (1:R).';
historyRows = cell(0, 12);
converged = false;
lastResult = struct();
lastScan = struct();
totalModelTime = 0;
totalSolveTime = 0;
totalSeparationTime = 0;

for iteration = 1:config.maxIterations
    activeBefore = numel(activeR);
    modelTic = tic;
    grb = append_pair_constraints(baseModel, idx, activeR, activeS, dMat);
    modelTime = toc(modelTic);
    totalModelTime = totalModelTime + modelTime;

    params = struct('OutputFlag', config.gurobiOutputFlag, ...
        'InfUnbdInfo', 1, ...
        'FeasibilityTol', config.gurobiFeasibilityTol, ...
        'OptimalityTol', config.gurobiOptimalityTol);
    if ~isempty(config.gurobiTimeLimit)
        params.TimeLimit = config.gurobiTimeLimit;
    end
    solveTic = tic;
    result = gurobi(grb, params);
    solveTime = toc(solveTic);
    totalSolveTime = totalSolveTime + solveTime;
    if ~strcmp(result.status, 'OPTIMAL')
        lastResult = result;
        historyRows(end + 1, :) = {iteration, activeBefore, activeBefore, ...
            NaN, string(result.status), modelTime, solveTime, 0, NaN, ...
            NaN, 0, false}; %#ok<AGROW>
        break;
    end

    x = result.x;
    scanTic = tic;
    scan = scan_all_pairs(dMat, x(idx.L), x(idx.lambda), ...
        x(idx.alpha), config.blockSize, config.violationTolerance);
    separationTime = toc(scanTic);
    totalSeparationTime = totalSeparationTime + separationTime;

    addR = scan.violatedR;
    addS = scan.worstS(addR);
    keep = false(size(addR));
    for kk = 1:numel(addR)
        keep(kk) = ~logical(activeMask(addR(kk), addS(kk)));
    end
    addR = addR(keep);
    addS = addS(keep);
    if ~isempty(addR)
        activeMask = activeMask + sparse(addR, addS, true, R, R);
        activeR = [activeR; addR(:)]; %#ok<AGROW>
        activeS = [activeS; addS(:)]; %#ok<AGROW>
    end

    activeAfter = numel(activeR);
    convergedNow = scan.maxViolation <= config.violationTolerance;
    historyRows(end + 1, :) = {iteration, activeBefore, activeAfter, ...
        result.objval, string(result.status), modelTime, solveTime, ...
        separationTime, scan.maxViolation, numel(scan.violatedR), ...
        numel(addR), convergedNow}; %#ok<AGROW>
    lastResult = result;
    lastScan = scan;
    if convergedNow
        converged = true;
        break;
    end
    if isempty(addR)
        error('solve_step03P_weighted_cg_h2:SeparationStall', ...
            'Complete separation found a violation but no new pair.');
    end
end

history = cell2table(historyRows, 'VariableNames', ...
    {'iteration','active_constraints_before','active_constraints_after', ...
    'objective_value','solve_status','modeling_time_sec','solve_time_sec', ...
    'separation_time_sec','max_violation','violated_r_count', ...
    'constraints_added','converged'});

sol = struct('status', "NOT_SOLVED", 'exitflag', 0, ...
    'objective_value', NaN, 'T', NaN(I, 1), 'y', [], 'u', [], ...
    'L', [], 'lambda', NaN, 'alpha', [], 'history', history, ...
    'converged', converged, 'activeMask', activeMask, ...
    'activeR', activeR, 'activeS', activeS, ...
    'final_active_constraints', numel(activeR), ...
    'active_constraint_ratio', numel(activeR) / (R * R), ...
    'total_modeling_time_sec', totalModelTime, ...
    'total_solve_time_sec', totalSolveTime, ...
    'total_separation_time_sec', totalSeparationTime, ...
    'final_independent_scan_time_sec', NaN, ...
    'final_independent_scan_max_violation', NaN);
if isempty(fieldnames(lastResult))
    return;
end
sol.status = string(lastResult.status);
sol.raw = lastResult;
if ~strcmp(lastResult.status, 'OPTIMAL') || ~converged
    return;
end

x = lastResult.x;
sol.exitflag = 1;
sol.objective_value = modelInfo.originalObj.' * x;
sol.T = x(idx.T);
sol.y = x(idx.y);
sol.u = x(idx.u);
sol.L = x(idx.L);
sol.lambda = x(idx.lambda);
sol.alpha = x(idx.alpha);
sol.last_scan_max_violation = lastScan.maxViolation;

scanTic = tic;
finalScan = scan_all_pairs(dMat, sol.L, sol.lambda, sol.alpha, ...
    config.independentScanBlockSize, config.violationTolerance);
sol.final_independent_scan_time_sec = toc(scanTic);
sol.final_independent_scan_max_violation = finalScan.maxViolation;
sol.final_independent_violated_r_count = numel(finalScan.violatedR);

serviceByScenario = reshape(sum(modelInfo.Ceff .* sol.y, [2, 3]), [], 1);
shortageKgByScenario = sum(sol.u, 2);
sol.terminal_cost = config.gamma * sum(sol.T);
sol.lambda_rho_cost = rho * sol.lambda;
sol.alpha_weighted_cost = sampleWeights.' * sol.alpha;
sol.robust_dual_loss = sol.lambda_rho_cost + sol.alpha_weighted_cost;
sol.empirical_loss_weighted = sampleWeights.' * sol.L;
sol.mean_service_cost = mean(serviceByScenario);
sol.mean_shortage_kg = mean(shortageKgByScenario);
sol.mean_shortage_penalty = M * sol.mean_shortage_kg;
sol.upper_bound_active = abs(sol.T - Cap(:)) <= 1e-7;
sol.lower_bound_active = sol.T <= 1e-7;
sol.sampleWeights = sampleWeights;
end

function config = fill_defaults(config, M)
defaults = struct('gamma', 0.001 * M, 'gurobiOutputFlag', 0, ...
    'gurobiFeasibilityTol', 1e-9, 'gurobiOptimalityTol', 1e-9, ...
    'gurobiTimeLimit', 300, 'violationTolerance', 1e-8, ...
    'maxIterations', 200, 'blockSize', 100, ...
    'independentScanBlockSize', 73);
names = fieldnames(defaults);
for ii = 1:numel(names)
    if ~isfield(config, names{ii}) || isempty(config.(names{ii}))
        config.(names{ii}) = defaults.(names{ii});
    end
end
end

function [base, idx, info] = build_base_model( ...
        D, A, C, Cap, M, rho, sampleWeights, config)
[R, N] = size(D);
I = numel(Cap);
Ceff = C;
Ceff(~isfinite(Ceff) | A <= 0.5) = 0;

next = 1;
idx.T = next:(next + I - 1); next = next + I;
idx.y = reshape(next:(next + R * I * N - 1), [R, I, N]); next = next + R * I * N;
idx.u = reshape(next:(next + R * N - 1), [R, N]); next = next + R * N;
idx.L = next:(next + R - 1); next = next + R;
idx.lambda = next; next = next + 1;
idx.alpha = next:(next + R - 1);
nvar = next + R - 1;

obj = zeros(nvar, 1);
obj(idx.T) = config.gamma;
obj(idx.lambda) = rho;
obj(idx.alpha) = sampleWeights;
lb = zeros(nvar, 1);
ub = inf(nvar, 1);
ub(idx.T) = Cap(:);
lb(idx.alpha) = -inf;
yUb = A .* reshape(D, [R, 1, N]);
ub(idx.y(:)) = yUb(:);

nRows = R * N + R * I + R;
maxNnz = R * N * (I + 1) + R * I * (N + 1) + ...
    R * (I * N + N + 1);
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
        add_term(rr, idx.T(ii), -1);
    end
end
for ss = 1:R
    rr = rr + 1;
    for ii = 1:I
        for nn = 1:N
            coeff = Ceff(ss, ii, nn);
            if coeff ~= 0
                add_term(rr, idx.y(ss, ii, nn), coeff);
            end
        end
    end
    for nn = 1:N
        add_term(rr, idx.u(ss, nn), M);
    end
    add_term(rr, idx.L(ss), -1);
end
if rr ~= nRows
    error('solve_step03P_weighted_cg_h2:BaseRowCount', ...
        'Internal base-model row count mismatch.');
end

base = struct('A', sparse(rowIdx(1:kk), colIdx(1:kk), val(1:kk), nRows, nvar), ...
    'obj', obj, 'rhs', rhs, 'sense', sense, 'lb', lb, 'ub', ub, ...
    'modelsense', 'min');
info = struct('Ceff', Ceff, 'originalObj', obj);
end

function grb = append_pair_constraints(base, idx, activeR, activeS, dMat)
K = numel(activeR);
nvar = numel(base.obj);
rowIdx = repelem((1:K).', 3, 1);
colIdx = zeros(3 * K, 1);
val = zeros(3 * K, 1);
colIdx(1:3:end) = idx.L(activeS);
val(1:3:end) = 1;
colIdx(2:3:end) = idx.lambda;
val(2:3:end) = -dMat(sub2ind(size(dMat), activeR, activeS));
colIdx(3:3:end) = idx.alpha(activeR);
val(3:3:end) = -1;
extra = sparse(rowIdx, colIdx, val, K, nvar);
grb = base;
grb.A = [base.A; extra];
grb.rhs = [base.rhs; zeros(K, 1)];
grb.sense = [base.sense; repmat('<', K, 1)];
end

function scan = scan_all_pairs(dMat, L, lambda, alpha, blockSize, tol)
R = size(dMat, 1);
worstViolation = -inf(R, 1);
worstS = ones(R, 1);
for rStart = 1:blockSize:R
    rIdx = rStart:min(R, rStart + blockSize - 1);
    localMax = -inf(numel(rIdx), 1);
    localS = ones(numel(rIdx), 1);
    for sStart = 1:blockSize:R
        sIdx = sStart:min(R, sStart + blockSize - 1);
        violation = reshape(L(sIdx), 1, []) - ...
            lambda .* dMat(rIdx, sIdx) - alpha(rIdx);
        [blockMax, blockPos] = max(violation, [], 2);
        improve = blockMax > localMax;
        localMax(improve) = blockMax(improve);
        localS(improve) = sIdx(blockPos(improve));
    end
    worstViolation(rIdx) = localMax;
    worstS(rIdx) = localS;
end
scan = struct('maxViolation', max(worstViolation), ...
    'worstViolation', worstViolation, 'worstS', worstS, ...
    'violatedR', find(worstViolation > tol), ...
    'checkedPairCount', R * R);
end
