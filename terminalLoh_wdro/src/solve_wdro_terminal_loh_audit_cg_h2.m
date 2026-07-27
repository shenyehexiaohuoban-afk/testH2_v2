function sol = solve_wdro_terminal_loh_audit_cg_h2( ...
        D, A, C, Cap, M, rho, config, audit)
%SOLVE_WDRO_TERMINAL_LOH_AUDIT_CG_H2 Independent audit-only exchange solver.
%
% This isolated solver supports objective-cap secondary optimization and
% fixed-TerminalLOH experiments. It does not modify the accepted WDRO or
% constraint-generation implementations.

if nargin < 7 || isempty(config)
    config = struct();
end
config = fill_defaults(config, M);
if nargin < 8 || isempty(audit)
    audit = struct();
end
audit = fill_audit_defaults(audit);

if ~ismember(exist('gurobi', 'file'), [2, 3])
    error('solve_wdro_terminal_loh_lp_constraint_generation_h2:MissingGurobi', ...
        'Gurobi MATLAB function was not found on the MATLAB path.');
end

[R, N] = size(D);
I = numel(Cap);
if ~isequal(size(A), [R, I, N]) || ~isequal(size(C), [R, I, N])
    error('solve_wdro_terminal_loh_lp_constraint_generation_h2:BadArraySize', ...
        'Expected A and C to have size R x I x N.');
end
if any(D < 0, 'all') || any(~isfinite(D), 'all')
    error('solve_wdro_terminal_loh_lp_constraint_generation_h2:BadDemand', ...
        'D must be finite and nonnegative.');
end
if any(A > 0.5 & ~isfinite(C), 'all')
    error('solve_wdro_terminal_loh_lp_constraint_generation_h2:InfReachableCost', ...
        'Reachable site-node pairs cannot have Inf/NaN service cost.');
end

contextTic = tic;
distanceContext = prepare_distance_context(D, A, C, config);
distanceContextTime = toc(contextTic);

baseTic = tic;
[baseModel, idx, modelInfo] = build_base_model( ...
    D, A, C, Cap, M, rho, config, audit);
baseModelTime = toc(baseTic);

activeMask = sparse(1:R, 1:R, true, R, R);
activeR = (1:R).';
activeS = (1:R).';
historyRows = cell(0, 12);
converged = false;
lastResult = struct();
lastScan = struct();
totalModelTime = baseModelTime;
totalSolveTime = 0;
totalSeparationTime = 0;

for iteration = 1:config.maxIterations
    activeBefore = numel(activeR);
    modelTic = tic;
    grb = append_pair_constraints(baseModel, idx, activeR, activeS, ...
        distanceContext, config.blockSize);
    modelTime = toc(modelTic);
    totalModelTime = totalModelTime + modelTime;

    params = struct();
    params.OutputFlag = config.gurobiOutputFlag;
    params.InfUnbdInfo = 1;
    params.FeasibilityTol = config.gurobiFeasibilityTol;
    params.OptimalityTol = config.gurobiOptimalityTol;
    if isfield(config, 'gurobiTimeLimit') && ~isempty(config.gurobiTimeLimit)
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
            NaN, 0, false};
        break;
    end

    x = result.x;
    scanTic = tic;
    scan = scan_all_pair_violations(distanceContext, x(idx.L), ...
        x(idx.lambda), x(idx.alpha), config.blockSize, ...
        config.violationTolerance);
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
        numel(addR), convergedNow};
    lastResult = result;
    lastScan = scan;

    if convergedNow
        converged = true;
        break;
    end
    if isempty(addR)
        error('solve_wdro_terminal_loh_lp_constraint_generation_h2:SeparationStall', ...
            ['The complete scan found violation %.12g but no new pair could ' ...
            'be added. Tighten solver feasibility tolerances.'], scan.maxViolation);
    end
end

history = cell2table(historyRows, 'VariableNames', ...
    {'iteration','active_constraints_before','active_constraints_after', ...
    'objective_value','solve_status','modeling_time_sec','solve_time_sec', ...
    'separation_time_sec','max_violation','violated_r_count', ...
    'constraints_added','converged'});

sol = struct();
sol.status = "NOT_SOLVED";
sol.exitflag = 0;
sol.objective_value = NaN;
sol.solver_objective_value = NaN;
sol.original_objective_value = NaN;
sol.T = NaN(I, 1);
sol.y = [];
sol.u = [];
sol.L = [];
sol.lambda = NaN;
sol.alpha = [];
sol.idx = idx;
sol.history = history;
sol.converged = converged;
sol.final_active_constraints = numel(activeR);
sol.active_constraint_ratio = numel(activeR) / (R * R);
sol.distance_context_time_sec = distanceContextTime;
sol.base_model_time_sec = baseModelTime;
sol.total_modeling_time_sec = totalModelTime;
sol.total_solve_time_sec = totalSolveTime;
sol.total_separation_time_sec = totalSeparationTime;
sol.distance_info = distanceContext.info;
sol.last_scan_max_violation = NaN;
sol.final_independent_scan_max_violation = NaN;
sol.final_independent_scan_time_sec = NaN;
sol.audit = audit;

if isempty(fieldnames(lastResult))
    return;
end
sol.status = string(lastResult.status);
sol.raw = lastResult;
if ~strcmp(lastResult.status, 'OPTIMAL') || ~converged
    if ~isempty(fieldnames(lastScan))
        sol.last_scan_max_violation = lastScan.maxViolation;
    end
    return;
end

x = lastResult.x;
sol.exitflag = 1;
sol.solver_objective_value = lastResult.objval;
sol.original_objective_value = modelInfo.originalObj.' * x;
sol.objective_value = sol.original_objective_value;
sol.T = x(idx.T);
sol.y = x(idx.y);
sol.u = x(idx.u);
sol.L = x(idx.L);
sol.lambda = x(idx.lambda);
sol.alpha = x(idx.alpha);
sol.last_scan_max_violation = lastScan.maxViolation;

% This is deliberately a second complete scan, independent of the stopping
% scan above. It again visits every ordered pair in blocks.
independentTic = tic;
independentScan = scan_all_pair_violations(distanceContext, sol.L, ...
    sol.lambda, sol.alpha, config.independentScanBlockSize, ...
    config.violationTolerance);
sol.final_independent_scan_time_sec = toc(independentTic);
sol.final_independent_scan_max_violation = independentScan.maxViolation;
sol.final_independent_violated_r_count = numel(independentScan.violatedR);
serviceByScenario = reshape(sum(modelInfo.Ceff .* sol.y, [2, 3]), [], 1);
shortageByScenario = M .* sum(sol.u, 2);
sol.terminal_cost = config.gamma * sum(sol.T);
sol.lambda_rho_cost = rho * sol.lambda;
sol.alpha_mean_cost = mean(sol.alpha);
sol.other_objective_cost = sol.original_objective_value - ...
    sol.terminal_cost - sol.lambda_rho_cost - sol.alpha_mean_cost;
sol.mean_service_cost = mean(serviceByScenario);
sol.mean_shortage_penalty = mean(shortageByScenario);
sol.mean_scenario_loss = mean(sol.L);
sol.max_scenario_loss = max(sol.L);
sol.max_loss_definition_slack = max(abs(sol.L - serviceByScenario - shortageByScenario));
sol.lower_bound_active = sol.T <= 1e-7;
sol.upper_bound_active = abs(sol.T - Cap(:)) <= 1e-7;
sol.objective_cap_slack = NaN;
if isfinite(audit.originalObjectiveUpperBound)
    sol.objective_cap_slack = audit.originalObjectiveUpperBound - ...
        sol.original_objective_value;
end
end

function config = fill_defaults(config, M)
defaults = struct( ...
    'gamma', 0.001 * M, ...
    'gurobiOutputFlag', 0, ...
    'gurobiFeasibilityTol', 1e-9, ...
    'gurobiOptimalityTol', 1e-9, ...
    'violationTolerance', 1e-8, ...
    'maxIterations', 200, ...
    'blockSize', 100, ...
    'independentScanBlockSize', 73, ...
    'epsDistance', 1e-9, ...
    'scaleTolerance', 1e-12, ...
    'distanceWeightsDACMaskedC', struct('D', 0.6, 'A', 0.25, 'C', 0.15));
names = fieldnames(defaults);
for ii = 1:numel(names)
    name = names{ii};
    if ~isfield(config, name) || isempty(config.(name))
        config.(name) = defaults.(name);
    end
end
end

function audit = fill_audit_defaults(audit)
defaults = struct( ...
    'originalObjectiveUpperBound', Inf, ...
    'secondarySite', 0, ...
    'secondaryDirection', "none", ...
    'fixedT', []);
names = fieldnames(defaults);
for ii = 1:numel(names)
    name = names{ii};
    if ~isfield(audit, name) || isempty(audit.(name))
        audit.(name) = defaults.(name);
    end
end
audit.secondaryDirection = lower(string(audit.secondaryDirection));
if audit.secondarySite < 0 || audit.secondarySite > 4 || ...
        audit.secondarySite ~= floor(audit.secondarySite)
    error('solve_wdro_terminal_loh_audit_cg_h2:BadSecondarySite', ...
        'secondarySite must be 0 or one of the four site indices.');
end
if audit.secondarySite > 0 && ...
        ~ismember(audit.secondaryDirection, ["min", "max"])
    error('solve_wdro_terminal_loh_audit_cg_h2:BadSecondaryDirection', ...
        'Secondary direction must be min or max.');
end
end

function context = prepare_distance_context(D, A, C, config)
R = size(D, 1);
Aflat = double(reshape(A, R, []));
Cflat = double(reshape(C, R, []));
Cflat(~isfinite(Cflat) | Aflat <= 0.5) = 0;

context = struct();
context.R = R;
context.D = double(D);
context.A = Aflat;
context.C = Cflat;
context.weights = config.distanceWeightsDACMaskedC;
context.epsDistance = config.epsDistance;
context.scaleTolerance = config.scaleTolerance;

Dscale = 0;
Ascale = 0;
Cscale = 0;
blockSize = config.blockSize;
for rStart = 1:blockSize:R
    rIdx = rStart:min(R, rStart + blockSize - 1);
    for sStart = 1:blockSize:R
        sIdx = sStart:min(R, sStart + blockSize - 1);
        [dD, dA, dC] = component_distance_block(context, rIdx, sIdx);
        Dscale = max(Dscale, max(dD, [], 'all'));
        Ascale = max(Ascale, max(dA, [], 'all'));
        Cscale = max(Cscale, max(dC, [], 'all'));
    end
end
context.Dscale = Dscale;
context.Ascale = Ascale;
context.Cscale = Cscale;
context.info = struct( ...
    'distance_mode', "DAC_maskedC", ...
    'D_scale', Dscale, ...
    'A_scale', Ascale, ...
    'C_scale', Cscale, ...
    'distance_matrix_stored', false, ...
    'scale_scan_pair_count', R * R);
end

function [base, idx, modelInfo] = build_base_model( ...
        D, A, C, Cap, M, rho, config, audit)
[R, N] = size(D);
I = numel(Cap);
Ceff = C;
Ceff(~isfinite(Ceff) | A <= 0.5) = 0;

idx = struct();
next = 1;
idx.T = next:(next + I - 1); next = next + I;
idx.y = reshape(next:(next + R * I * N - 1), [R, I, N]); next = next + R * I * N;
idx.u = reshape(next:(next + R * N - 1), [R, N]); next = next + R * N;
idx.L = next:(next + R - 1); next = next + R;
idx.lambda = next; next = next + 1;
idx.alpha = next:(next + R - 1);
nvar = next + R - 1;

originalObj = zeros(nvar, 1);
originalObj(idx.T) = config.gamma;
originalObj(idx.lambda) = rho;
originalObj(idx.alpha) = 1 / R;
obj = originalObj;
if audit.secondarySite > 0
    obj = zeros(nvar, 1);
    if audit.secondaryDirection == "min"
        obj(idx.T(audit.secondarySite)) = 1;
    else
        obj(idx.T(audit.secondarySite)) = -1;
    end
end
lb = zeros(nvar, 1);
ub = inf(nvar, 1);
ub(idx.T) = Cap(:);
lb(idx.alpha) = -inf;
if ~isempty(audit.fixedT)
    fixedT = double(audit.fixedT(:));
    if numel(fixedT) ~= I || any(~isfinite(fixedT)) || ...
            any(fixedT < -1e-9) || any(fixedT > Cap(:) + 1e-9)
        error('solve_wdro_terminal_loh_audit_cg_h2:BadFixedT', ...
            'fixedT must contain four finite values within the accepted bounds.');
    end
    lb(idx.T) = fixedT;
    ub(idx.T) = fixedT;
end
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
    error('solve_wdro_terminal_loh_lp_constraint_generation_h2:BaseRowCount', ...
        'Internal base-row count mismatch.');
end

base = struct();
base.A = sparse(rowIdx(1:kk), colIdx(1:kk), val(1:kk), nRows, nvar);
base.obj = obj;
base.rhs = rhs;
base.sense = sense;
base.lb = lb;
base.ub = ub;
base.modelsense = 'min';
if isfinite(audit.originalObjectiveUpperBound)
    capRow = sparse(1, find(originalObj), ...
        originalObj(originalObj ~= 0), 1, nvar);
    base.A = [base.A; capRow];
    base.rhs = [base.rhs; audit.originalObjectiveUpperBound];
    base.sense = [base.sense; '<'];
end
modelInfo = struct();
modelInfo.originalObj = originalObj;
modelInfo.Ceff = Ceff;
end

function grb = append_pair_constraints(base, idx, activeR, activeS, context, blockSize)
K = numel(activeR);
nvar = numel(base.obj);
rowIdx = repelem((1:K).', 3, 1);
colIdx = zeros(3 * K, 1);
val = zeros(3 * K, 1);
colIdx(1:3:end) = idx.L(activeS);
val(1:3:end) = 1;
colIdx(2:3:end) = idx.lambda;
colIdx(3:3:end) = idx.alpha(activeR);
val(3:3:end) = -1;

for start = 1:blockSize:K
    rows = start:min(K, start + blockSize - 1);
    d = distance_for_pairs(context, activeR(rows), activeS(rows));
    val(3 * rows - 1) = -d;
end
extra = sparse(rowIdx, colIdx, val, K, nvar);
grb = base;
grb.A = [base.A; extra];
grb.rhs = [base.rhs; zeros(K, 1)];
grb.sense = [base.sense; repmat('<', K, 1)];
end

function scan = scan_all_pair_violations(context, L, lambda, alpha, blockSize, tol)
R = context.R;
worstViolation = -inf(R, 1);
worstS = ones(R, 1);
for rStart = 1:blockSize:R
    rIdx = rStart:min(R, rStart + blockSize - 1);
    localMax = -inf(numel(rIdx), 1);
    localS = ones(numel(rIdx), 1);
    for sStart = 1:blockSize:R
        sIdx = sStart:min(R, sStart + blockSize - 1);
        d = distance_block(context, rIdx, sIdx);
        violation = reshape(L(sIdx), 1, []) - lambda .* d - alpha(rIdx);
        [blockMax, blockPos] = max(violation, [], 2);
        improve = blockMax > localMax;
        localMax(improve) = blockMax(improve);
        localS(improve) = sIdx(blockPos(improve));
    end
    worstViolation(rIdx) = localMax;
    worstS(rIdx) = localS;
end
scan = struct();
scan.maxViolation = max(worstViolation);
scan.worstViolation = worstViolation;
scan.worstS = worstS;
scan.violatedR = find(worstViolation > tol);
scan.checkedPairCount = R * R;
end

function d = distance_for_pairs(context, rIdx, sIdx)
count = numel(rIdx);
d = zeros(count, 1);
for kk = 1:count
    d(kk) = distance_block(context, rIdx(kk), sIdx(kk));
end
end

function d = distance_block(context, rIdx, sIdx)
[dD, dA, dC] = component_distance_block(context, rIdx, sIdx);
dD = normalize_component(dD, context.Dscale, context);
dA = normalize_component(dA, context.Ascale, context);
dC = normalize_component(dC, context.Cscale, context);
d = context.weights.D .* dD + context.weights.A .* dA + ...
    context.weights.C .* dC;
same = rIdx(:) == sIdx(:).';
d(same) = 0;
end

function [dD, dA, dC] = component_distance_block(context, rIdx, sIdx)
Dr = reshape(context.D(rIdx, :), [numel(rIdx), 1, size(context.D, 2)]);
Ds = reshape(context.D(sIdx, :), [1, numel(sIdx), size(context.D, 2)]);
dD = sum(abs(Dr - Ds), 3);

Ar = reshape(context.A(rIdx, :), [numel(rIdx), 1, size(context.A, 2)]);
As = reshape(context.A(sIdx, :), [1, numel(sIdx), size(context.A, 2)]);
dA = sum(abs(Ar - As), 3);

Cr = reshape(context.C(rIdx, :), [numel(rIdx), 1, size(context.C, 2)]);
Cs = reshape(context.C(sIdx, :), [1, numel(sIdx), size(context.C, 2)]);
dC = sum(abs(Cr - Cs) .* (Ar > 0.5 & As > 0.5), 3);
end

function out = normalize_component(delta, scale, context)
if scale <= context.scaleTolerance
    out = zeros(size(delta));
else
    out = delta ./ (scale + context.epsDistance);
end
end
