function sol = solve_step03R_single_scenario_batch_h2( ...
        D, A, C, Cap, M, config)
%SOLVE_STEP03R_SINGLE_SCENARIO_BATCH_H2 Two-stage deterministic tie break.

if nargin < 6 || isempty(config)
    config = struct();
end
config = fill_defaults(config);
if ~ismember(exist('gurobi', 'file'), [2, 3])
    error('solve_step03R_single_scenario_batch_h2:MissingGurobi', ...
        'The existing Gurobi MATLAB interface is required.');
end

[model, idx, info] = build_step03R_single_scenario_lp_h2( ...
    D, A, C, Cap, M, config);
params = gurobi_params(config);
firstTic = tic;
first = gurobi(model, params);
firstTime = toc(firstTic);
sol = empty_solution(size(D, 1), numel(Cap));
sol.primary_status = string(first.status);
sol.primary_runtime_sec = firstTime;
if ~strcmp(first.status, 'OPTIMAL')
    sol.raw_primary = first;
    return;
end

objStar = full(info.primaryRows * first.x);
second = model;
second.A = [model.A; info.primaryRows];
second.rhs = [model.rhs; objStar + config.primaryObjectiveTolerance];
second.sense = [model.sense; repmat('<', size(D, 1), 1)];
second.obj = zeros(size(model.obj));
tieWeights = 1:numel(Cap);
for ii = 1:numel(Cap)
    second.obj(idx.T(:, ii)) = tieWeights(ii);
end
secondTic = tic;
result = gurobi(second, params);
secondTime = toc(secondTic);
sol.secondary_status = string(result.status);
sol.secondary_runtime_sec = secondTime;
sol.obj_star = objStar;
if ~strcmp(result.status, 'OPTIMAL')
    sol.raw_primary = first;
    sol.raw_secondary = result;
    return;
end

sol.exitflag = 1;
sol.T = reshape(result.x(idx.T(:)), size(idx.T));
sol.primary_objective_at_representative = full(info.primaryRows * result.x);
sol.primary_objective_slack = objStar + ...
    config.primaryObjectiveTolerance - sol.primary_objective_at_representative;
sol.max_capacity_violation = max(sol.T - reshape(Cap, 1, []), [], 'all');
sol.min_T = min(sol.T, [], 'all');
sol.raw_primary_status = string(first.status);
sol.raw_secondary_status = string(result.status);
end

function config = fill_defaults(config)
defaults = struct('gurobiOutputFlag', 0, 'gurobiFeasibilityTol', 1e-9, ...
    'gurobiOptimalityTol', 1e-9, 'gurobiTimeLimit', 300, ...
    'primaryObjectiveTolerance', 1e-8);
names = fieldnames(defaults);
for ii = 1:numel(names)
    if ~isfield(config, names{ii}) || isempty(config.(names{ii}))
        config.(names{ii}) = defaults.(names{ii});
    end
end
end

function params = gurobi_params(config)
params = struct('OutputFlag', config.gurobiOutputFlag, ...
    'FeasibilityTol', config.gurobiFeasibilityTol, ...
    'OptimalityTol', config.gurobiOptimalityTol, ...
    'TimeLimit', config.gurobiTimeLimit, 'InfUnbdInfo', 1);
end

function sol = empty_solution(R, I)
sol = struct('exitflag', 0, 'T', NaN(R, I), ...
    'obj_star', NaN(R, 1), ...
    'primary_objective_at_representative', NaN(R, 1), ...
    'primary_objective_slack', NaN(R, 1), ...
    'primary_status', "NOT_SOLVED", 'secondary_status', "NOT_SOLVED", ...
    'primary_runtime_sec', NaN, 'secondary_runtime_sec', NaN, ...
    'max_capacity_violation', NaN, 'min_T', NaN);
end
