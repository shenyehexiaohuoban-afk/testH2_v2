function out = solve_flat_chi2_worst_probability_h2(q, loss, eta, tolerance)
%SOLVE_FLAT_CHI2_WORST_PROBABILITY_H2 Exact Pearson chi-square adversary.
%
% Solves max p'*loss subject to p>=0, sum(p)=1, and
% sum((p-q).^2./q)<=eta by the KKT active-set formula. No R-by-R matrix is
% constructed. Eta zero directly returns q.

if nargin < 4 || isempty(tolerance), tolerance = 1e-12; end
started = tic;
q = double(q(:));
loss = double(loss(:));
if isempty(q) || numel(q) ~= numel(loss) || any(~isfinite(q)) || ...
        any(q <= 0) || any(~isfinite(loss)) || ~isscalar(eta) || ...
        ~isfinite(eta) || eta < -tolerance
    error('solve_flat_chi2_worst_probability_h2:BadInput', ...
        'q/loss must be finite equal-length vectors, q>0, eta>=0.');
end
q = q ./ sum(q);
eta = max(0, double(eta));
R = numel(q);

if R == 1
    p = 1;
    method = "single_scenario_degenerate";
elseif eta <= tolerance
    p = q;
    method = "eta_zero_direct_saa";
elseif max(loss) - min(loss) <= tolerance * max(1, max(abs(loss)))
    p = q;
    method = "constant_loss_degenerate";
else
    maximum = max(loss);
    maximumMask = abs(loss - maximum) <= ...
        tolerance * max(1, abs(maximum));
    qMaximum = sum(q(maximumMask));
    etaToMaximumFace = 1 / qMaximum - 1;
    if eta >= etaToMaximumFace - tolerance
        p = zeros(R, 1);
        p(maximumMask) = q(maximumMask) ./ qMaximum;
        method = "maximum_loss_face";
    else
        active = true(R, 1);
        converged = false;
        for iteration = 1:(R + 1)
            qa = q(active);
            va = loss(active);
            qsum = sum(qa);
            minimumDivergence = 1 / qsum - 1;
            remaining = eta - minimumDivergence;
            if remaining < -100 * tolerance
                error('solve_flat_chi2_worst_probability_h2:ActiveSet', ...
                    'Active-set minimum divergence exceeded eta.');
            end
            meanValue = sum(qa .* va) / qsum;
            varianceNumerator = sum(qa .* (va - meanValue).^2);
            if varianceNumerator <= tolerance
                pa = qa ./ qsum;
            else
                scale = sqrt(max(0, remaining) / varianceNumerator);
                pa = qa ./ qsum + scale .* qa .* (va - meanValue);
            end
            bad = pa < -100 * tolerance;
            if ~any(bad)
                p = zeros(R, 1);
                ids = find(active);
                p(ids) = max(pa, 0);
                p = p ./ sum(p);
                converged = true;
                break;
            end
            ids = find(active);
            active(ids(bad)) = false;
        end
        if ~converged
            error('solve_flat_chi2_worst_probability_h2:NoConvergence', ...
                'KKT active-set solver did not converge.');
        end
        method = "kkt_active_set";
    end
end

divergence = sum((p - q).^2 ./ q);
sumResidual = abs(sum(p) - 1);
minimumProbability = min(p);
feasible = sumResidual <= 1e-10 && minimumProbability >= -1e-10 && ...
    divergence <= eta + 1e-9;
out = struct('worst_value', sum(p .* loss), ...
    'worst_probability', p, 'nominal_probability', q, 'eta', eta, ...
    'divergence_used', divergence, ...
    'probability_sum_residual', sumResidual, ...
    'minimum_probability', minimumProbability, ...
    'effective_sample_size', 1 / sum(p.^2), ...
    'solver_status', string(ternary(feasible, 'OPTIMAL', ...
    'NUMERICAL_FAILURE')), 'runtime_sec', toc(started), ...
    'method_used', method, 'active_probability_count', sum(p > 0));
end

function value = ternary(condition, yesValue, noValue)
if condition, value = yesValue; else, value = noValue; end
end
