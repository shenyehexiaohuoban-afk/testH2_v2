function pFail = compute_line_failure_prob_h2(windSpeedMps, designWindSpeedVN)
%COMPUTE_LINE_FAILURE_PROB_H2 Design-wind exponential fragility formula.

if designWindSpeedVN <= 0
    error('compute_line_failure_prob_h2:BadDesignWindSpeed', ...
        'designWindSpeedVN must be positive.');
end

pFail = zeros(size(windSpeedMps));
mid = windSpeedMps > designWindSpeedVN & windSpeedMps < 2 * designWindSpeedVN;
pFail(mid) = exp(0.6931 .* (windSpeedMps(mid) - designWindSpeedVN) ./ designWindSpeedVN) - 1;
pFail(windSpeedMps >= 2 * designWindSpeedVN) = 1;
pFail = min(max(pFail, 0), 1);
end
