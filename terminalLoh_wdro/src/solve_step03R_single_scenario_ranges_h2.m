function sol = solve_step03R_single_scenario_ranges_h2( ...
        D, A, C, Cap, M, objStar, config)
%SOLVE_STEP03R_SINGLE_SCENARIO_RANGES_H2 Exact T ranges at primary optimum.

if nargin < 7 || isempty(config)
    config = struct();
end
config = fill_defaults(config);
if ~ismember(exist('gurobi', 'file'), [2, 3])
    error('solve_step03R_single_scenario_ranges_h2:MissingGurobi', ...
        'The existing Gurobi MATLAB interface is required.');
end
objStar = double(objStar(:));
if numel(objStar) ~= size(D, 1) || any(~isfinite(objStar))
    error('solve_step03R_single_scenario_ranges_h2:BadObjective', ...
        'objStar must contain one finite value per scenario.');
end

[base, idx, info] = build_step03R_single_scenario_lp_h2( ...
    D, A, C, Cap, M, config);
base.A = [base.A; info.primaryRows];
base.rhs = [base.rhs; objStar + config.primaryObjectiveTolerance];
base.sense = [base.sense; repmat('<', size(D, 1), 1)];
params = struct('OutputFlag', config.gurobiOutputFlag, ...
    'FeasibilityTol', config.gurobiFeasibilityTol, ...
    'OptimalityTol', config.gurobiOptimalityTol, ...
    'TimeLimit', config.gurobiTimeLimit, 'InfUnbdInfo', 1);
I = numel(Cap);
R = size(D, 1);
sol = struct('exitflag', 1, 'T_min', NaN(R, I), 'T_max', NaN(R, I), ...
    'min_status', strings(I, 1), 'max_status', strings(I, 1), ...
    'min_runtime_sec', zeros(I, 1), 'max_runtime_sec', zeros(I, 1));
for ii = 1:I
    model = base;
    model.obj = zeros(size(base.obj));
    model.obj(idx.T(:, ii)) = 1;
    model.modelsense = 'min';
    solveTic = tic;
    result = gurobi(model, params);
    sol.min_runtime_sec(ii) = toc(solveTic);
    sol.min_status(ii) = string(result.status);
    if ~strcmp(result.status, 'OPTIMAL')
        sol.exitflag = 0;
        continue;
    end
    sol.T_min(:, ii) = result.x(idx.T(:, ii));

    model.modelsense = 'max';
    solveTic = tic;
    result = gurobi(model, params);
    sol.max_runtime_sec(ii) = toc(solveTic);
    sol.max_status(ii) = string(result.status);
    if ~strcmp(result.status, 'OPTIMAL')
        sol.exitflag = 0;
        continue;
    end
    sol.T_max(:, ii) = result.x(idx.T(:, ii));
end
sol.range_width = sol.T_max - sol.T_min;
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
