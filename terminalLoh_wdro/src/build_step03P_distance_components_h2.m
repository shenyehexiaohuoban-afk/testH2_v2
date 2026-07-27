function components = build_step03P_distance_components_h2(Drep, A, C, config)
%BUILD_STEP03P_DISTANCE_COMPONENTS_H2 Build full audit-only D/A/C components.

if nargin < 4 || isempty(config)
    config = struct();
end
if ~isfield(config, 'blockSize') || isempty(config.blockSize)
    config.blockSize = 100;
end
if ~isfield(config, 'epsDistance') || isempty(config.epsDistance)
    config.epsDistance = 1e-9;
end
if ~isfield(config, 'scaleTolerance') || isempty(config.scaleTolerance)
    config.scaleTolerance = 1e-12;
end

R = size(Drep, 1);
if size(A, 1) ~= R || size(C, 1) ~= R || ~isequal(size(A), size(C))
    error('build_step03P_distance_components_h2:BadArraySize', ...
        'D representation, A, and C must have the same scenario count.');
end
if any(~isfinite(Drep), 'all') || any(Drep < 0, 'all')
    error('build_step03P_distance_components_h2:BadDemand', ...
        'The D representation must be finite and nonnegative.');
end
if any(A > 0.5 & ~isfinite(C), 'all')
    error('build_step03P_distance_components_h2:BadReachableCost', ...
        'Reachable site-node pairs require finite C.');
end

Dflat = double(Drep);
Aflat = double(reshape(A, R, []));
Cflat = double(reshape(C, R, []));
Cflat(~isfinite(Cflat) | Aflat <= 0.5) = 0;

dD = zeros(R, R);
dA = zeros(R, R);
dC = zeros(R, R);
blockSize = config.blockSize;
for rStart = 1:blockSize:R
    rIdx = rStart:min(R, rStart + blockSize - 1);
    for sStart = rStart:blockSize:R
        sIdx = sStart:min(R, sStart + blockSize - 1);
        [blockD, blockA, blockC] = component_block( ...
            Dflat, Aflat, Cflat, rIdx, sIdx);
        dD(rIdx, sIdx) = blockD;
        dA(rIdx, sIdx) = blockA;
        dC(rIdx, sIdx) = blockC;
        if sStart ~= rStart
            dD(sIdx, rIdx) = blockD.';
            dA(sIdx, rIdx) = blockA.';
            dC(sIdx, rIdx) = blockC.';
        end
    end
end
dD(1:R + 1:end) = 0;
dA(1:R + 1:end) = 0;
dC(1:R + 1:end) = 0;

scaleD = max(dD, [], 'all');
scaleA = max(dA, [], 'all');
scaleC = max(dC, [], 'all');

components = struct();
components.R = R;
components.rawD = dD;
components.rawA = dA;
components.rawC = dC;
components.normD = normalize_component(dD, scaleD, config);
components.normA = normalize_component(dA, scaleA, config);
components.normC = normalize_component(dC, scaleC, config);
components.scaleD = scaleD;
components.scaleA = scaleA;
components.scaleC = scaleC;
components.D_dimension = size(Drep, 2);
components.A_dimension = size(Aflat, 2);
components.C_dimension = size(Cflat, 2);
components.A_binary = all(abs(Aflat(:)) <= 1e-10 | ...
    abs(Aflat(:) - 1) <= 1e-10);
end

function [dD, dA, dC] = component_block(D, A, C, rIdx, sIdx)
Dr = reshape(D(rIdx, :), [numel(rIdx), 1, size(D, 2)]);
Ds = reshape(D(sIdx, :), [1, numel(sIdx), size(D, 2)]);
dD = sum(abs(Dr - Ds), 3);

Ar = reshape(A(rIdx, :), [numel(rIdx), 1, size(A, 2)]);
As = reshape(A(sIdx, :), [1, numel(sIdx), size(A, 2)]);
dA = sum(abs(Ar - As), 3);

Cr = reshape(C(rIdx, :), [numel(rIdx), 1, size(C, 2)]);
Cs = reshape(C(sIdx, :), [1, numel(sIdx), size(C, 2)]);
dC = sum(abs(Cr - Cs) .* (Ar > 0.5 & As > 0.5), 3);
end

function out = normalize_component(delta, scale, config)
if scale <= config.scaleTolerance
    out = zeros(size(delta));
else
    out = delta ./ (scale + config.epsDistance);
end
end
