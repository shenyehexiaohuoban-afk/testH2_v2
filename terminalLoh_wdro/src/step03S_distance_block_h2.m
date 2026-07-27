function [dNew, dD, dCtilde, localDetail] = step03S_distance_block_h2( ...
        Dq, Aq, Cq, Dt, At, Ct, Dscale, config)
%STEP03S_DISTANCE_BLOCK_H2 Exact cross-block D + Ctilde distances.

if nargin < 8 || isempty(config)
    config = struct();
end
if ~isfield(config, 'C_bound') || isempty(config.C_bound)
    config.C_bound = 357.1526447416079;
end
if ~isfield(config, 'kappa') || isempty(config.kappa)
    config.kappa = 1;
end
if ~isfield(config, 'epsDistance') || isempty(config.epsDistance)
    config.epsDistance = 1e-9;
end
if ~isfield(config, 'weight_D') || isempty(config.weight_D)
    config.weight_D = 0.6;
end
if ~isfield(config, 'weight_Ctilde') || isempty(config.weight_Ctilde)
    config.weight_Ctilde = 0.4;
end

nq = size(Dq, 1);
nt = size(Dt, 1);
if size(Dq, 2) ~= size(Dt, 2) || size(Aq, 1) ~= nq || ...
        size(At, 1) ~= nt || ~isequal(size(Aq), size(Cq)) || ...
        ~isequal(size(At), size(Ct)) || size(Aq, 2) ~= size(At, 2) || ...
        size(Aq, 3) ~= size(At, 3)
    error('step03S_distance_block_h2:BadArraySize', ...
        'Query and target D/A/C blocks do not share the same feature shape.');
end
if ~isscalar(Dscale) || ~isfinite(Dscale) || Dscale < 0
    error('step03S_distance_block_h2:BadDScale', ...
        'Dscale must be a finite nonnegative scalar.');
end

Dq3 = reshape(double(Dq), [nq, 1, size(Dq, 2)]);
Dt3 = reshape(double(Dt), [1, nt, size(Dt, 2)]);
rawD = sum(abs(Dq3 - Dt3), 3);
if Dscale <= 1e-12
    dD = zeros(nq, nt);
else
    dD = rawD ./ (Dscale + config.epsDistance);
end

AqFlat = double(reshape(Aq, nq, [])) > 0.5;
AtFlat = double(reshape(At, nt, [])) > 0.5;
CqFlat = double(reshape(Cq, nq, []));
CtFlat = double(reshape(Ct, nt, []));
CqFlat(~AqFlat | ~isfinite(CqFlat)) = 0;
CtFlat(~AtFlat | ~isfinite(CtFlat)) = 0;
localDimension = size(AqFlat, 2);
dCsum = zeros(nq, nt);
maxLocal = zeros(nq, nt);
changedLocalCount = zeros(nq, nt);
for kk = 1:localDimension
    aq = AqFlat(:, kk);
    at = AtFlat(:, kk).';
    mismatch = xor(aq, at);
    both = aq & at;
    local = config.kappa .* double(mismatch);
    if any(both, 'all')
        cq = CqFlat(:, kk);
        ct = CtFlat(:, kk).';
        reachableDifference = abs(cq - ct);
        local(both) = reachableDifference(both) ./ config.C_bound;
    end
    dCsum = dCsum + local;
    maxLocal = max(maxLocal, local);
    changedLocalCount = changedLocalCount + (local > 1e-12);
end
dCtilde = dCsum ./ localDimension;
dNew = config.weight_D .* dD + config.weight_Ctilde .* dCtilde;
localDetail = struct('raw_D_l1', rawD, ...
    'max_local_Ctilde', maxLocal, ...
    'changed_local_count', changedLocalCount, ...
    'local_dimension', localDimension);
end
