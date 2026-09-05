function validate_h2_params(params)
%VALIDATE_H2_PARAMS Validate TerminalLOH-version hydrogen FA-MSP parameters.

Ni = params.Ni;
K = params.K;
T = params.T;

must_have_length(params.x_0, Ni, 'x_0');
must_have_length(params.x_cap, Ni, 'x_cap');
must_have_length(params.x_min, Ni, 'x_min');
must_have_length(params.el_cap_kw, Ni, 'el_cap_kw');

if any(params.x_cap <= 0)
    error('validate_h2_params:BadTankCap', 'All tank capacities must be positive.');
end
if any(params.x_0 < -1e-8 | params.x_0 > params.x_cap + 1e-8)
    error('validate_h2_params:BadInitialLOH', 'x_0 must be within [0, tank_cap].');
end
if params.use_tank_min && any(params.x_min > params.x_cap)
    error('validate_h2_params:BadTankMin', 'tank_min_kg cannot exceed tank_cap_kg.');
end

if ~isequal(size(params.D_normal), [Ni, T])
    error('validate_h2_params:BadNormalDemandSize', ...
        'D_normal must be %d-by-%d.', Ni, T);
end

must_have_length(params.beta, K, 'beta');
if any(params.beta < -1e-10 | params.beta > 1 + 1e-10)
    error('validate_h2_params:BadBeta', 'beta must be within [0,1].');
end

if ~isequal(size(params.TerminalLOH), [Ni, K])
    error('validate_h2_params:BadTerminalLOHSize', ...
        'TerminalLOH must be %d-by-%d.', Ni, K);
end
if any(abs(params.TerminalLOH(:, params.is_dissipated)) > 1e-9, 'all')
    error('validate_h2_params:BadDissipatedTerminalLOH', ...
        'TerminalLOH must be zero for a=1 dissipated states.');
end
expectedDemand = params.S(:, 1) > 1 & params.S(:, 3) == params.Nc - 1;
if ~isfield(params, 'is_loh_demand_stage') || any(params.is_loh_demand_stage ~= expectedDemand)
    error('validate_h2_params:BadLOHDemandStage', ...
        'is_loh_demand_stage must be true exactly for a>1 and lf=Nc-1.');
end
expectedAbsorb = params.S(:, 1) == 1 | params.S(:, 3) == params.Nc;
if any(params.is_absorbing ~= expectedAbsorb)
    error('validate_h2_params:BadAbsorbingStates', ...
        'is_absorbing must be true exactly for a=1 or lf=Nc.');
end
notDemandStage = ~params.is_loh_demand_stage;
if any(abs(params.TerminalLOH(:, notDemandStage)) > 1e-9, 'all')
    error('validate_h2_params:BadNonDemandTerminalLOH', ...
        'TerminalLOH must be zero outside lf=Nc-1 LOH demand states.');
end
if any(abs(params.TerminalLOH(:, params.is_terminal_landfall)) > 1e-9, 'all')
    error('validate_h2_params:BadAbsorbingTerminalLOH', ...
        'TerminalLOH must be zero for lf=Nc absorbing states.');
end
if any(sum(params.TerminalLOH(:, params.is_loh_demand_stage), 1) <= 1e-9) && ~params.allow_zero_terminal_loh
    error('validate_h2_params:ZeroTerminalLOH', ...
        'Some lf=Nc-1,a>1 demand states have zero TerminalLOH. Set allow_zero_terminal_loh only if intended.');
end

rowErr = max(abs(sum(params.P_joint, 2) - 1));
if rowErr >= 1e-8
    error('validate_h2_params:BadPJoint', ...
        'P_joint row sums are not close to 1. Max error = %.3g.', rowErr);
end

if params.k_init < 1 || params.k_init > K
    error('validate_h2_params:BadInitialState', ...
        'k_init = %d is outside 1:%d.', params.k_init, K);
end
if params.is_absorbing(params.k_init)
    error('validate_h2_params:AbsorbingInitialState', ...
        'k_init = %d is absorbing.', params.k_init);
end
if params.is_loh_demand_stage(params.k_init)
    error('validate_h2_params:DemandStageInitialState', ...
        'k_init = %d is already an LOH demand stage.', params.k_init);
end

if params.cost_reserve_shortage <= params.cost_normal_shortage
    warning('validate_h2_params:WeakReservePenalty', ...
        'reserve_shortage_penalty is not larger than normal_shortage_penalty.');
end
end

function must_have_length(x, n, name)
if numel(x) ~= n
    error('validate_h2_params:BadLength', ...
        '%s must have %d entries, got %d.', name, n, numel(x));
end
end
