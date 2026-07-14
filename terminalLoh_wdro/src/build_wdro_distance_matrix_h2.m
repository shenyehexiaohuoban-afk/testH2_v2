function [dMat, info] = build_wdro_distance_matrix_h2(D, A, C, distanceMode, config)
%BUILD_WDRO_DISTANCE_MATRIX_H2 Build consequence-space Wasserstein distances.
%
% DA is the main distance metric. A is treated as binary reachability in
% finite discrete scenario atoms. Wasserstein transport moves probability
% mass between complete scenarios; it does not continuously perturb
% reachability entries, so states such as A_in=0.3 are not generated.
% DA does not use C. A=1 means a feasible service path exists; A=0 means
% fully unreachable. If a road remains usable but becomes slow because of
% flooding, congestion, debris, detours, or speed limits, keep A=1 and
% represent the degradation through a larger C rather than a fractional A.
%
% DAC_maskedC compares service cost only on site-node pairs that are
% reachable in both scenarios. This avoids counting one unreachable event
% once through A and again through a large or infinite C value.

if nargin < 5 || isempty(config)
    config = struct();
end
if ~isfield(config, 'epsDistance') || isempty(config.epsDistance)
    config.epsDistance = 1e-9;
end
if ~isfield(config, 'scaleTolerance') || isempty(config.scaleTolerance)
    config.scaleTolerance = 1e-12;
end

mode = lower(strtrim(string(distanceMode)));
[R, ~] = size(D);
if size(A, 1) ~= R || size(C, 1) ~= R
    error('build_wdro_distance_matrix_h2:BadSampleCount', ...
        'D, A, and C must have the same scenario dimension.');
end
if ~isequal(size(A), size(C))
    error('build_wdro_distance_matrix_h2:BadArraySize', ...
        'A and C must have the same R x I x N size.');
end

Aflat = double(reshape(A, R, []));
Avals = unique(Aflat(:));
AisBinary = all(abs(Avals) <= 1e-10 | abs(Avals - 1) <= 1e-10);
if ~AisBinary
    warning('build_wdro_distance_matrix_h2:NonBinaryA', ...
        'Reachability A contains values other than 0/1. Distances will use the supplied values without rounding.');
end

badReachableCost = A > 0.5 & ~isfinite(C);
if any(badReachableCost(:))
    error('build_wdro_distance_matrix_h2:InfReachableCost', ...
        'Reachable site-node pairs cannot have Inf/NaN scenario_service_cost.');
end

Dflat = double(D);
Clegacy = clean_unreachable_cost_for_legacy(C, A);
ClegacyFlat = double(reshape(Clegacy, R, []));

Ddelta = pairwise_l1(Dflat);
Adelta = pairwise_l1(Aflat);
CdeltaLegacy = pairwise_l1(ClegacyFlat);
[CdeltaMasked, maskedPairCount, maskedPairShare] = pairwise_masked_cost_l1(C, A);

epsVal = config.epsDistance;
tol = config.scaleTolerance;
Dscale = max(Ddelta(:));
Ascale = max(Adelta(:));
CscaleLegacy = max(CdeltaLegacy(:));
CscaleMasked = max(CdeltaMasked(:));

Dnorm = normalize_component(Ddelta, Dscale, epsVal, tol);
Anorm = normalize_component(Adelta, Ascale, epsVal, tol);
CnormLegacy = normalize_component(CdeltaLegacy, CscaleLegacy, epsVal, tol);
CnormMasked = normalize_component(CdeltaMasked, CscaleMasked, epsVal, tol);

weights = get_distance_weights(mode, config);
switch mode
    case "d_only"
        dMat = Dnorm;
        label = "D_only";
        CscaleUsed = 0;
    case "da"
        dMat = weights.D .* Dnorm + weights.A .* Anorm;
        label = "DA";
        CscaleUsed = 0;
    case "dac_maskedc"
        dMat = weights.D .* Dnorm + weights.A .* Anorm + ...
            weights.C .* CnormMasked;
        label = "DAC_maskedC";
        CscaleUsed = CscaleMasked;
    case "dac"
        dMat = weights.D .* Dnorm + weights.A .* Anorm + ...
            weights.C .* CnormLegacy;
        label = "DAC_legacy_unmasked";
        CscaleUsed = CscaleLegacy;
    otherwise
        error('build_wdro_distance_matrix_h2:BadDistanceMode', ...
            ['Unsupported distance_mode: %s. Use D_only, DA, ' ...
            'DAC_maskedC, or legacy DAC.'], distanceMode);
end

dMat(1:R + 1:end) = 0;
dMat = 0.5 .* (dMat + dMat.');

info = struct();
info.distance_mode = label;
info.requested_distance_mode = string(distanceMode);
info.D_scale = Dscale;
info.A_scale = Ascale;
info.C_scale = CscaleUsed;
info.C_scale_legacy_unmasked = CscaleLegacy;
info.C_scale_masked = CscaleMasked;
info.D_component_active = Dscale > tol;
info.A_component_active = Ascale > tol;
info.C_component_active = CscaleUsed > tol;
info.weights = weights;
info.A_binary_ok = AisBinary;
info.A_min = min(Aflat(:));
info.A_max = max(Aflat(:));
info.A_unique_values = join(string(Avals.'), "|");
info.C_masked_pair_count = maskedPairCount;
info.C_masked_pair_share = maskedPairShare;
info.d_diag_max_abs = max(abs(diag(dMat)));
info.d_symmetry_max_abs = max(abs(dMat - dMat.'), [], 'all');
info.d_min_all = min(dMat(:));
end

function weights = get_distance_weights(mode, config)
switch mode
    case "d_only"
        weights = struct('D', 1, 'A', 0, 'C', 0);
    case "da"
        if isfield(config, 'distanceWeightsDA') && ...
                ~isempty(config.distanceWeightsDA)
            weights = fill_weights(config.distanceWeightsDA, 0.7, 0.3, 0);
        else
            weights = struct('D', 0.7, 'A', 0.3, 'C', 0);
        end
    case "dac_maskedc"
        if isfield(config, 'distanceWeightsDACMaskedC') && ...
                ~isempty(config.distanceWeightsDACMaskedC)
            weights = fill_weights(config.distanceWeightsDACMaskedC, ...
                0.6, 0.25, 0.15);
        else
            weights = struct('D', 0.6, 'A', 0.25, 'C', 0.15);
        end
    case "dac"
        if isfield(config, 'distanceWeightsDACLegacy') && ...
                ~isempty(config.distanceWeightsDACLegacy)
            weights = fill_weights(config.distanceWeightsDACLegacy, ...
                0.6, 0.2, 0.2);
        elseif isfield(config, 'distanceWeights') && ...
                ~isempty(config.distanceWeights)
            weights = fill_weights(config.distanceWeights, 0.6, 0.2, 0.2);
        else
            weights = struct('D', 0.6, 'A', 0.2, 'C', 0.2);
        end
    otherwise
        weights = struct('D', NaN, 'A', NaN, 'C', NaN);
end
end

function weights = fill_weights(in, dDefault, aDefault, cDefault)
weights = struct('D', dDefault, 'A', aDefault, 'C', cDefault);
if isfield(in, 'D') && ~isempty(in.D); weights.D = in.D; end
if isfield(in, 'A') && ~isempty(in.A); weights.A = in.A; end
if isfield(in, 'C') && ~isempty(in.C); weights.C = in.C; end
end

function out = normalize_component(delta, scale, epsVal, tol)
if scale <= tol
    out = zeros(size(delta));
else
    out = delta ./ (scale + epsVal);
end
end

function delta = pairwise_l1(X)
R = size(X, 1);
delta = zeros(R, R);
for rr = 1:R
    for ss = rr + 1:R
        val = sum(abs(X(rr, :) - X(ss, :)));
        delta(rr, ss) = val;
        delta(ss, rr) = val;
    end
end
end

function Cclean = clean_unreachable_cost_for_legacy(C, A)
Cclean = C;
Cclean(~isfinite(Cclean) | A <= 0.5) = 0;
end

function [delta, pairCount, pairShare] = pairwise_masked_cost_l1(C, A)
R = size(C, 1);
delta = zeros(R, R);
pairCount = 0;
pairTotal = R * (R - 1) / 2;
for rr = 1:R
    Cr = squeeze(C(rr, :, :));
    Ar = squeeze(A(rr, :, :)) > 0.5;
    for ss = rr + 1:R
        Cs = squeeze(C(ss, :, :));
        As = squeeze(A(ss, :, :)) > 0.5;
        mask = Ar & As;
        if any(mask(:))
            pairCount = pairCount + 1;
            val = sum(abs(Cr(mask) - Cs(mask)));
        else
            val = 0;
        end
        delta(rr, ss) = val;
        delta(ss, rr) = val;
    end
end
if pairTotal > 0
    pairShare = pairCount / pairTotal;
else
    pairShare = 0;
end
end
