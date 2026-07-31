function audit = audit_flat_chi2_terminal_solution_h2( ...
        solution, aggregation, M, gamma, config)
%AUDIT_FLAT_CHI2_TERMINAL_SOLUTION_H2 Independent fixed-T/probability audit.

if nargin < 5 || isempty(config), config = struct(); end
config = fill_defaults(config);
if solution.exitflag ~= 1
    error('audit_flat_chi2_terminal_solution_h2:BadSolution', ...
        'Only an OPTIMAL TerminalLOH solution can be audited.');
end
G = aggregation.group_count;
Trows = repmat(solution.T(:).', G, 1);
fixed = evaluate_terminal_loh_period_fixed_T_sparse_h2( ...
    aggregation.Dperiod, aggregation.Aperiod, aggregation.Cperiod, ...
    Trows, M, config);
if fixed.exitflag ~= 1
    error('audit_flat_chi2_terminal_solution_h2:FixedTEvaluation', ...
        'Independent fixed-T recourse evaluation failed: %s', fixed.status);
end
adversary = solve_flat_chi2_worst_probability_h2( ...
    aggregation.nominal_probability, fixed.operating_loss, solution.eta);
if adversary.solver_status ~= "OPTIMAL"
    error('audit_flat_chi2_terminal_solution_h2:ProbabilityAdversary', ...
        'Independent probability adversary failed.');
end

groupProbability = adversary.worst_probability;
recordProbability = groupProbability(aggregation.group_id) ./ ...
    aggregation.multiplicity(aggregation.group_id);
recordLoss = fixed.operating_loss(aggregation.group_id);
qRecord = ones(aggregation.original_R, 1) ./ aggregation.original_R;
recordDivergence = sum((recordProbability - qRecord).^2 ./ qRecord);
recordProbabilitySumResidual = abs(sum(recordProbability) - 1);
nominalExpected = sum(aggregation.nominal_probability .* fixed.operating_loss);
worstExpected = sum(recordProbability .* recordLoss);
firstStage = gamma * sum(solution.T);
robustTotal = firstStage + worstExpected;
modelRiskGap = abs(solution.model_risk_value - worstExpected);
modelTotalGap = abs(solution.objective_value - robustTotal);

[increase, increaseIndex] = max(recordProbability - qRecord);
[decrease, decreaseIndex] = min(recordProbability - qRecord);
audit = struct();
audit.status = "PASS";
audit.fixed_T = fixed;
audit.adversary = adversary;
audit.group_operating_loss = fixed.operating_loss;
audit.original_record_operating_loss = recordLoss;
audit.group_worst_probability = groupProbability;
audit.original_record_worst_probability = recordProbability;
audit.nominal_expected_recourse = nominalExpected;
audit.worst_expected_recourse = worstExpected;
audit.first_stage_cost = firstStage;
audit.robust_total_objective = robustTotal;
audit.strong_duality_gap = modelRiskGap;
audit.strong_duality_relative_gap = modelRiskGap / max(1, abs(worstExpected));
audit.total_objective_reconstruction_gap = modelTotalGap;
audit.total_objective_reconstruction_relative_gap = modelTotalGap / ...
    max(1, abs(robustTotal));
audit.record_probability_sum_residual = recordProbabilitySumResidual;
audit.record_minimum_probability = min(recordProbability);
audit.record_divergence_used = recordDivergence;
audit.record_effective_sample_size = 1 / sum(recordProbability.^2);
audit.maximum_probability_increase = increase;
audit.maximum_probability_increase_record = increaseIndex;
audit.maximum_probability_decrease = decrease;
audit.maximum_probability_decrease_record = decreaseIndex;
residualTerms = [ ...
    fixed.max_demand_balance_error, ...
    max(0, fixed.max_site_capacity_violation), ...
    recordProbabilitySumResidual, max(0, -min(recordProbability)), ...
    max(0, recordDivergence - solution.eta), ...
    max(0, solution.qcp_residual), ...
    max(0, solution.maximum_risk_linear_violation), ...
    solution.objective_reconstruction_error];
audit.maximum_mechanical_residual = max(residualTerms, [], 'omitnan');
audit.pass = modelRiskGap <= config.strongDualityTolerance && ...
    audit.strong_duality_relative_gap <= ...
    config.strongDualityRelativeTolerance && ...
    modelTotalGap <= config.objectiveReconstructionTolerance && ...
    audit.total_objective_reconstruction_relative_gap <= ...
    config.objectiveReconstructionRelativeTolerance && ...
    recordProbabilitySumResidual <= config.probabilityTolerance && ...
    min(recordProbability) >= -config.probabilityTolerance && ...
    recordDivergence <= solution.eta + config.divergenceTolerance && ...
    fixed.max_demand_balance_error <= config.recourseTolerance && ...
    fixed.max_site_capacity_violation <= config.recourseTolerance;
if ~audit.pass, audit.status = "FAIL"; end
end

function config = fill_defaults(config)
defaults = struct('strongDualityTolerance', 1e-3, ...
    'strongDualityRelativeTolerance', 5e-6, ...
    'objectiveReconstructionTolerance', 1e-3, ...
    'objectiveReconstructionRelativeTolerance', 5e-6, ...
    'probabilityTolerance', 1e-10, 'divergenceTolerance', 1e-8, ...
    'recourseTolerance', 1e-7);
names = fieldnames(defaults);
for ii = 1:numel(names)
    if ~isfield(config, names{ii}) || isempty(config.(names{ii}))
        config.(names{ii}) = defaults.(names{ii});
    end
end
end
