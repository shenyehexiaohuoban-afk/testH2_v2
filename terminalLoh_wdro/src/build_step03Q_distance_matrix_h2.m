function [dMat, info, detail] = build_step03Q_distance_matrix_h2( ...
        D, A, C, method, config)
%BUILD_STEP03Q_DISTANCE_MATRIX_H2 Build old or audit-only Ctilde distance.

if nargin < 4 || isempty(method)
    method = "old";
end
if nargin < 5 || isempty(config)
    config = struct();
end
if ~isfield(config, 'epsDistance') || isempty(config.epsDistance)
    config.epsDistance = 1e-9;
end
if ~isfield(config, 'scaleTolerance') || isempty(config.scaleTolerance)
    config.scaleTolerance = 1e-12;
end
if ~isfield(config, 'matchOldMedian') || isempty(config.matchOldMedian)
    config.matchOldMedian = false;
end

method = lower(strtrim(string(method)));
R = size(D, 1);
if size(A, 1) ~= R || size(C, 1) ~= R || ~isequal(size(A), size(C))
    error('build_step03Q_distance_matrix_h2:BadArraySize', ...
        'D, A, and C must have the same scenario count and matching A/C size.');
end
if any(~isfinite(D), 'all') || any(D < 0, 'all')
    error('build_step03Q_distance_matrix_h2:BadDemand', ...
        'D must be finite and nonnegative.');
end
Aflat = double(reshape(A, R, []));
if any(abs(Aflat(:)) > 1e-10 & abs(Aflat(:) - 1) > 1e-10)
    error('build_step03Q_distance_matrix_h2:NonBinaryA', ...
        'Step-03Q requires binary A.');
end
if any(A > 0.5 & ~isfinite(C), 'all')
    error('build_step03Q_distance_matrix_h2:BadReachableCost', ...
        'Reachable site-node entries require finite C.');
end

if isfield(config, 'oldDistance') && isfield(config, 'oldInfo') && ...
        ~isempty(config.oldDistance) && ~isempty(config.oldInfo)
    oldDistance = config.oldDistance;
    oldInfo = config.oldInfo;
else
    [oldDistance, oldInfo] = build_wdro_distance_matrix_h2( ...
        D, A, C, 'DAC_maskedC', config);
end
if ~isequal(size(oldDistance), [R, R])
    error('build_step03Q_distance_matrix_h2:BadOldDistance', ...
        'The accepted old distance must be R x R.');
end
weights = oldInfo.weights;
requiredWeights = {'D','A','C'};
for ii = 1:numel(requiredWeights)
    name = requiredWeights{ii};
    if ~isfield(weights, name) || ~isscalar(weights.(name)) || ...
            ~isfinite(weights.(name)) || weights.(name) < 0
        error('build_step03Q_distance_matrix_h2:BadAcceptedWeights', ...
            'The accepted distance returned an invalid %s weight.', name);
    end
end

oldPositive = oldDistance(triu(true(R), 1) & oldDistance > config.scaleTolerance);
if isempty(oldPositive)
    error('build_step03Q_distance_matrix_h2:ZeroOldDistance', ...
        'The accepted old distance has no positive scenario pair.');
end
oldMedian = median(oldPositive);

switch method
    case {"old", "dac_maskedc"}
        unscaled = oldDistance;
        dMat = oldDistance;
        scaleFactor = 1;
        components = [];
        dCtilde = [];
        kappa = NaN;
        cBound = NaN;
        label = "old_D_plus_A_plus_maskedC";
    case {"ctilde", "d_plus_ctilde"}
        if ~isfield(config, 'C_bound') || ~isscalar(config.C_bound) || ...
                ~isfinite(config.C_bound) || config.C_bound <= 0
            error('build_step03Q_distance_matrix_h2:MissingCBound', ...
                'Ctilde requires a finite positive deterministic C_bound.');
        end
        if ~isfield(config, 'kappa') || ~isscalar(config.kappa) || ...
                ~isfinite(config.kappa) || config.kappa < 0.5
            error('build_step03Q_distance_matrix_h2:BadKappa', ...
                'Ctilde requires finite kappa >= 0.5.');
        end
        cBound = double(config.C_bound);
        kappa = double(config.kappa);
        if any(C(A > 0.5) < -config.scaleTolerance) || ...
                any(C(A > 0.5) > cBound + config.scaleTolerance)
            error('build_step03Q_distance_matrix_h2:CBoundViolation', ...
                'A reachable C value lies outside [0,C_bound].');
        end
        if isfield(config, 'components') && ~isempty(config.components)
            components = config.components;
        else
            components = build_step03P_distance_components_h2(D, A, C, config);
        end
        localDimension = size(Aflat, 2);
        dCtilde = (components.rawC ./ cBound + ...
            kappa .* components.rawA) ./ localDimension;
        dCtilde = 0.5 .* (dCtilde + dCtilde.');
        dCtilde(1:R + 1:end) = 0;
        wCtilde = weights.A + weights.C;
        unscaled = weights.D .* components.normD + wCtilde .* dCtilde;
        unscaled = 0.5 .* (unscaled + unscaled.');
        unscaled(1:R + 1:end) = 0;
        newPositive = unscaled(triu(true(R), 1) & ...
            unscaled > config.scaleTolerance);
        if isempty(newPositive)
            error('build_step03Q_distance_matrix_h2:ZeroNewDistance', ...
                'The Ctilde candidate has no positive scenario pair.');
        end
        newMedian = median(newPositive);
        if config.matchOldMedian
            scaleFactor = oldMedian / newMedian;
        else
            scaleFactor = 1;
        end
        dMat = scaleFactor .* unscaled;
        label = "new_D_plus_Ctilde_kappa_" + string(kappa);
    otherwise
        error('build_step03Q_distance_matrix_h2:BadMethod', ...
            'Unsupported method %s. Use old or Ctilde.', method);
end

dMat(1:R + 1:end) = 0;
dMat = 0.5 .* (dMat + dMat.');
positiveScaled = dMat(triu(true(R), 1) & dMat > config.scaleTolerance);
positiveUnscaled = unscaled(triu(true(R), 1) & ...
    unscaled > config.scaleTolerance);

info = struct();
info.method = label;
info.requested_method = method;
info.weights_from_accepted_code = weights;
info.weight_D = weights.D;
info.weight_A_old = weights.A;
info.weight_C_old = weights.C;
info.weight_Ctilde = weights.A + weights.C;
info.kappa = kappa;
info.C_bound = cBound;
info.old_nonzero_median = oldMedian;
info.unscaled_nonzero_median = median(positiveUnscaled);
info.scaled_nonzero_median = median(positiveScaled);
info.fair_comparison_scale_factor = scaleFactor;
info.match_old_median = logical(config.matchOldMedian);
info.unscaled_min = min(unscaled, [], 'all');
info.unscaled_max = max(unscaled, [], 'all');
info.scaled_min = min(dMat, [], 'all');
info.scaled_max = max(dMat, [], 'all');
info.max_diagonal_abs = max(abs(diag(dMat)));
info.max_symmetry_abs = max(abs(dMat - dMat.'), [], 'all');
info.min_all = min(dMat, [], 'all');

detail = struct();
detail.unscaled_distance = unscaled;
detail.old_distance = oldDistance;
detail.d_Ctilde = dCtilde;
detail.components = components;
end
