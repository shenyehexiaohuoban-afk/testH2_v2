function sol = solve_wdro_terminal_loh_lp_h2(D, A, C, Cap, M, rho, dMat, config)
%SOLVE_WDRO_TERMINAL_LOH_LP_H2 Solve one state/mode/rho WDRO TerminalLOH LP.

if nargin < 8 || isempty(config)
    config = struct();
end
if ~isfield(config, 'gamma') || isempty(config.gamma)
    config.gamma = 0.001 * M;
end
if ~isfield(config, 'gurobiOutputFlag') || isempty(config.gurobiOutputFlag)
    config.gurobiOutputFlag = 0;
end

if ~ismember(exist('gurobi', 'file'), [2, 3])
    error('solve_wdro_terminal_loh_lp_h2:MissingGurobi', ...
        ['Gurobi MATLAB function was not found on the MATLAB path. ' ...
        'This prototype does not implement a linprog fallback.']);
end

[R, N] = size(D);
I = numel(Cap);
if ~isequal(size(A), [R, I, N]) || ~isequal(size(C), [R, I, N])
    error('solve_wdro_terminal_loh_lp_h2:BadArraySize', ...
        'Expected A and C to have size R x I x N.');
end
if ~isequal(size(dMat), [R, R])
    error('solve_wdro_terminal_loh_lp_h2:BadDistanceSize', ...
        'dMat must be R x R.');
end

Ceff = C;
badReachableCost = A > 0.5 & ~isfinite(Ceff);
if any(badReachableCost(:))
    error('solve_wdro_terminal_loh_lp_h2:InfReachableCost', ...
        'Reachable site-node pairs cannot have Inf/NaN scenario_service_cost.');
end
Ceff(~isfinite(Ceff) | A <= 0.5) = 0;

idx = struct();
next = 1;
idx.T = next:(next + I - 1);
next = next + I;
idx.y = reshape(next:(next + R * I * N - 1), [R, I, N]);
next = next + R * I * N;
idx.u = reshape(next:(next + R * N - 1), [R, N]);
next = next + R * N;
idx.L = next:(next + R - 1);
next = next + R;
idx.lambda = next;
next = next + 1;
idx.alpha = next:(next + R - 1);
nvar = next + R - 1;

obj = zeros(nvar, 1);
obj(idx.T) = config.gamma;
obj(idx.lambda) = rho;
obj(idx.alpha) = 1 / R;

lb = zeros(nvar, 1);
ub = inf(nvar, 1);
ub(idx.T) = Cap(:);
lb(idx.alpha) = -inf;

for ss = 1:R
    for ii = 1:I
        for nn = 1:N
            ub(idx.y(ss, ii, nn)) = double(A(ss, ii, nn) > 0.5) * D(ss, nn);
        end
    end
end

nRows = R * N + R * I + R + R * R;
maxNnz = R * N * (I + 1) + R * I * (N + 1) + ...
    R * (I * N + N + 1) + R * R * 3;
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

% Demand coverage: sum_i y_i,n^s + u_n^s = D_n^s.
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

% Scenario service volume cannot exceed TerminalLOH.
for ss = 1:R
    for ii = 1:I
        rr = rr + 1;
        for nn = 1:N
            add_term(rr, idx.y(ss, ii, nn), 1);
        end
        add_term(rr, idx.T(ii), -1);
        rhs(rr) = 0;
    end
end

% L_s >= service cost + shortage penalty.
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
    rhs(rr) = 0;
end

% Wasserstein dual constraints: alpha_r + lambda*d_rs >= L_s.
for ar = 1:R
    for ss = 1:R
        rr = rr + 1;
        add_term(rr, idx.L(ss), 1);
        if dMat(ar, ss) ~= 0
            add_term(rr, idx.lambda, -dMat(ar, ss));
        end
        add_term(rr, idx.alpha(ar), -1);
        rhs(rr) = 0;
    end
end

if rr ~= nRows
    error('solve_wdro_terminal_loh_lp_h2:InternalRowCount', ...
        'Internal row count mismatch.');
end

grb = struct();
grb.A = sparse(rowIdx(1:kk), colIdx(1:kk), val(1:kk), nRows, nvar);
grb.obj = obj;
grb.rhs = rhs;
grb.sense = sense;
grb.lb = lb;
grb.ub = ub;
grb.modelsense = 'min';

grbParams = struct();
grbParams.OutputFlag = config.gurobiOutputFlag;
grbParams.InfUnbdInfo = 1;
if isfield(config, 'gurobiTimeLimit') && ~isempty(config.gurobiTimeLimit)
    grbParams.TimeLimit = config.gurobiTimeLimit;
end

tic;
result = gurobi(grb, grbParams);
runtime = toc;

sol = struct();
sol.status = string(result.status);
sol.exitflag = double(strcmp(result.status, 'OPTIMAL'));
sol.runtime_sec = runtime;
sol.objective_value = NaN;
sol.T = NaN(I, 1);
sol.y = [];
sol.u = [];
sol.L = [];
sol.lambda = NaN;
sol.alpha = [];
sol.idx = idx;

if sol.exitflag ~= 1
    sol.raw = result;
    return;
end

x = result.x;
sol.objective_value = result.objval;
sol.T = x(idx.T);
sol.y = x(idx.y);
sol.u = x(idx.u);
sol.L = x(idx.L);
sol.lambda = x(idx.lambda);
sol.alpha = x(idx.alpha);
sol.raw = result;
end
