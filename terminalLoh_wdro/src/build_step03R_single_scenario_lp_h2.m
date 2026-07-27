function [model, idx, info] = build_step03R_single_scenario_lp_h2( ...
        D, A, C, Cap, M, config)
%BUILD_STEP03R_SINGLE_SCENARIO_LP_H2 Build independent deterministic atoms.

if nargin < 6 || isempty(config)
    config = struct();
end
if ~isfield(config, 'gamma') || isempty(config.gamma)
    config.gamma = 0.001 * M;
end

[R, N] = size(D);
I = numel(Cap);
Cap = double(Cap(:));
if ~isequal(size(A), [R, I, N]) || ~isequal(size(C), [R, I, N])
    error('build_step03R_single_scenario_lp_h2:BadArraySize', ...
        'Expected A and C to have size R x I x N.');
end
if any(~isfinite(D), 'all') || any(D < 0, 'all') || ...
        any(A > 0.5 & ~isfinite(C), 'all') || ...
        any(~isfinite(Cap)) || any(Cap < 0) || ...
        ~isscalar(M) || ~isfinite(M) || M <= 0
    error('build_step03R_single_scenario_lp_h2:BadInput', ...
        'D, reachable C, capacities, and the shortage penalty are invalid.');
end

Ceff = C;
Ceff(~isfinite(Ceff) | A <= 0.5) = 0;
next = 1;
idx.T = reshape(next:(next + R * I - 1), [R, I]);
next = next + R * I;
idx.y = reshape(next:(next + R * I * N - 1), [R, I, N]);
next = next + R * I * N;
idx.u = reshape(next:(next + R * N - 1), [R, N]);
nvar = next + R * N - 1;

obj = zeros(nvar, 1);
obj(idx.T(:)) = config.gamma;
obj(idx.y(:)) = Ceff(:);
obj(idx.u(:)) = M;
lb = zeros(nvar, 1);
ub = inf(nvar, 1);
ub(idx.T(:)) = repmat(Cap.', R, 1);
yUb = A .* reshape(D, [R, 1, N]);
ub(idx.y(:)) = yUb(:);

nRows = R * N + R * I;
maxNnz = R * N * (I + 1) + R * I * (N + 1);
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
        add_term(rr, idx.T(ss, ii), -1);
    end
end
if rr ~= nRows
    error('build_step03R_single_scenario_lp_h2:InternalRows', ...
        'Internal row count mismatch.');
end

primaryNnz = R * (I + I * N + N);
primaryRow = zeros(primaryNnz, 1);
primaryCol = zeros(primaryNnz, 1);
primaryVal = zeros(primaryNnz, 1);
offset = 0;
for ss = 1:R
    cols = [idx.T(ss, :), reshape(idx.y(ss, :, :), 1, []), idx.u(ss, :)];
    coeffs = [repmat(config.gamma, 1, I), ...
        reshape(Ceff(ss, :, :), 1, []), repmat(M, 1, N)];
    positions = offset + (1:numel(cols));
    primaryRow(positions) = ss;
    primaryCol(positions) = cols;
    primaryVal(positions) = coeffs;
    offset = offset + numel(cols);
end
primaryRows = sparse(primaryRow, primaryCol, primaryVal, R, nvar);

model = struct();
model.A = sparse(rowIdx(1:kk), colIdx(1:kk), val(1:kk), nRows, nvar);
model.obj = obj;
model.rhs = rhs;
model.sense = sense;
model.lb = lb;
model.ub = ub;
model.modelsense = 'min';
info = struct('primaryRows', primaryRows, 'Ceff', Ceff, ...
    'scenario_count', R, 'site_count', I, 'node_count', N);
end
