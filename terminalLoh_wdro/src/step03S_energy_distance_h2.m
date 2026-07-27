function value = step03S_energy_distance_h2(X, Y, blockSize)
%STEP03S_ENERGY_DISTANCE_H2 Compute empirical energy distance by blocks.

if nargin < 3 || isempty(blockSize)
    blockSize = 250;
end
if size(X, 2) ~= size(Y, 2) || any(~isfinite(X), 'all') || ...
        any(~isfinite(Y), 'all')
    error('step03S_energy_distance_h2:BadInput', ...
        'Energy-distance inputs must be finite and share a feature dimension.');
end
crossMean = mean_pair_distance(X, Y, blockSize);
withinX = mean_pair_distance(X, X, blockSize);
withinY = mean_pair_distance(Y, Y, blockSize);
value = max(0, 2 .* crossMean - withinX - withinY);
end

function value = mean_pair_distance(X, Y, blockSize)
total = 0;
count = 0;
for xStart = 1:blockSize:size(X, 1)
    xIdx = xStart:min(size(X, 1), xStart + blockSize - 1);
    for yStart = 1:blockSize:size(Y, 1)
        yIdx = yStart:min(size(Y, 1), yStart + blockSize - 1);
        Xb = reshape(X(xIdx, :), [numel(xIdx), 1, size(X, 2)]);
        Yb = reshape(Y(yIdx, :), [1, numel(yIdx), size(Y, 2)]);
        distances = sqrt(sum((Xb - Yb) .^ 2, 3));
        total = total + sum(distances, 'all');
        count = count + numel(distances);
    end
end
value = total ./ count;
end
