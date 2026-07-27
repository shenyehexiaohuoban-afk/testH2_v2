function [dMat, detail] = compose_step03P_transport_cost_h2(components, weights)
%COMPOSE_STEP03P_TRANSPORT_COST_H2 Compose and median-normalize audit cost.

required = {'D','A','C'};
for ii = 1:numel(required)
    if ~isfield(weights, required{ii}) || ~isscalar(weights.(required{ii})) || ...
            ~isfinite(weights.(required{ii})) || weights.(required{ii}) < 0
        error('compose_step03P_transport_cost_h2:BadWeight', ...
            'D, A, and C weights must be finite nonnegative scalars.');
    end
end

weightedD = weights.D .* components.normD;
weightedA = weights.A .* components.normA;
weightedC = weights.C .* components.normC;
dMat = weightedD + weightedA + weightedC;
dMat = 0.5 .* (dMat + dMat.');
R = size(dMat, 1);
dMat(1:R + 1:end) = 0;

upperValues = dMat(triu(true(R), 1));
positiveValues = upperValues(upperValues > 1e-12);
if isempty(positiveValues)
    error('compose_step03P_transport_cost_h2:ZeroCost', ...
        'The composed transport cost has no nonzero scenario pairs.');
end
medianPositive = median(positiveValues);
dMat = dMat ./ medianPositive;
weightedD = weightedD ./ medianPositive;
weightedA = weightedA ./ medianPositive;
weightedC = weightedC ./ medianPositive;

detail = struct();
detail.weights = weights;
detail.median_before_rescale = medianPositive;
detail.median_positive_after_rescale = median(dMat(dMat > 1e-12));
detail.weightedD = weightedD;
detail.weightedA = weightedA;
detail.weightedC = weightedC;
detail.nonzero_pair_count = numel(positiveValues);
detail.max_cost = max(dMat, [], 'all');
detail.min_positive_cost = min(dMat(dMat > 1e-12));
end
