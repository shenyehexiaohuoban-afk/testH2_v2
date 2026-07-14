function aggregated = aggregate_W3_DAC_outcomes_h2(tauOut, baseCost, config)
%AGGREGATE_W3_DAC_OUTCOMES_H2 Aggregate tau-level D/A/C into one scenario.
%
% D is summed over tau. A remains binary. A=1 means every critical demand
% window is reachable; slow but passable roads keep A=1 and appear as larger
% C. C is the current road-state shortest path cost, not baseCost plus
% currentCost. If A=0, C is set to Inf and must be ignored by DAC_maskedC.

D_tau = tauOut.D_tau;
reach_tau = tauOut.reach_tau;
cost_tau = tauOut.cost_tau;
if ~isfield(tauOut, 'cost_before_fix_tau')
    error('aggregate_W3_DAC_outcomes_h2:MissingBeforeFixCost', ...
        'tauOut.cost_before_fix_tau is required for B1 C audit diagnostics.');
end
costBeforeFixTau = tauOut.cost_before_fix_tau;
[W, I, N] = size(reach_tau);

D = sum(D_tau, 1).';
A = zeros(I, N);
C = inf(I, N);
CBeforeFix = inf(I, N);
delay = inf(I, N);

for n = 1:N
    criticalTau = find(D_tau(:, n) > config.demandToleranceKg);
    if isempty(criticalTau)
        criticalTau = (1:W).';
    end
    for i = 1:I
        reachVec = squeeze(reach_tau(criticalTau, i, n));
        if all(reachVec)
            A(i, n) = 1;
            cVals = squeeze(cost_tau(criticalTau, i, n));
            cVals = cVals(isfinite(cVals));
            cBeforeVals = squeeze(costBeforeFixTau(criticalTau, i, n));
            cBeforeVals = cBeforeVals(isfinite(cBeforeVals));
            if isempty(cVals)
                error('aggregate_W3_DAC_outcomes_h2:ReachableWithoutFiniteCost', ...
                    'A=1 but no finite current service cost for site=%d node=%d.', i, n);
            else
                C(i, n) = mean(cVals);
            end
            if isempty(cBeforeVals)
                error('aggregate_W3_DAC_outcomes_h2:ReachableWithoutBeforeFixCost', ...
                    'A=1 but no finite before-fix service cost for site=%d node=%d.', i, n);
            else
                CBeforeFix(i, n) = mean(cBeforeVals);
            end
            delay(i, n) = max(0, C(i, n) - baseCost(i, n));
        else
            A(i, n) = 0;
            C(i, n) = Inf;
            CBeforeFix(i, n) = Inf;
            delay(i, n) = Inf;
        end
    end
end

aggregated = struct();
aggregated.D = D;
aggregated.A = A;
aggregated.C = C;
aggregated.C_before_fix = CBeforeFix;
aggregated.delay = delay;
end
