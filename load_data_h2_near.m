function params = load_data_h2_near(dataDir, nearInputFile, opts)
%LOAD_DATA_H2_NEAR Load TerminalLOH-version hydrogen FA-MSP data.
%
% Inputs:
%   dataDir       Data root containing Markov CSVs and the yuanqi folder.
%   nearInputFile MAT file containing NearStageInput from long-term planning.
%   opts          Explicit configuration for template files and prototype flags.
%
% Output:
%   params        Hydrogen FA-MSP parameter structure.
%
% V2 modeling convention:
%   Non-terminal stages do not impose disaster reserve demand. They only
%   model normal H2 demand, production, storage, and HTT movement. Disaster
%   reserve adequacy is evaluated at lf=Nc-1, matching the original FA-MSP
%   demand realization stage. lf=Nc is a zero-cost absorbing state.

if nargin < 1 || isempty(dataDir)
    dataDir = fullfile(fileparts(mfilename('fullpath')), 'data');
end
if nargin < 2 || isempty(nearInputFile)
    nearInputFile = fullfile(dataDir, 'yuanqi', 'near_stage_msp_input.mat');
end
if nargin < 3 || isempty(opts)
    opts = struct();
end

if ~isfile(nearInputFile)
    error('load_data_h2_near:MissingNearInput', ...
        'Missing NearStageInput file: %s', nearInputFile);
end
raw = load(nearInputFile, 'NearStageInput');
if ~isfield(raw, 'NearStageInput')
    error('load_data_h2_near:MissingStruct', ...
        'File %s does not contain NearStageInput.', nearInputFile);
end
NearStageInput = raw.NearStageInput;

P_intensity = table2array(readtable(fullfile(dataDir, 'intensity.csv')));
P_location  = table2array(readtable(fullfile(dataDir, 'location.csv')));
P_landfall  = table2array(readtable(fullfile(dataDir, 'landfall_7.csv')));

Na = size(P_intensity, 1);
Nb = size(P_location, 1);
Nc = size(P_landfall, 1);
T = Nc;
K = Na * Nb * Nc;

P_joint = zeros(K, K);
S = zeros(K, 3);
state_id = zeros(Na, Nb, Nc);
is_dissipated = false(K, 1);
is_terminal_landfall = false(K, 1);
is_loh_demand_stage = false(K, 1);

% Joint state order is unchanged from the paper replication:
% k = (intensity a, location loc, landfall process lf).
k1 = 0;
for a = 1:Na
    for loc = 1:Nb
        for lf = 1:Nc
            k1 = k1 + 1;
            S(k1, :) = [a, loc, lf];
            state_id(a, loc, lf) = k1;

            k2 = 0;
            for a2 = 1:Na
                for loc2 = 1:Nb
                    for lf2 = 1:Nc
                        k2 = k2 + 1;
                        P_joint(k1, k2) = P_intensity(a, a2) * ...
                            P_location(loc, loc2) * P_landfall(lf, lf2);
                    end
                end
            end

            is_dissipated(k1) = (a == 1);
            % This is the H2 LOH demand/check stage, corresponding to the
            % original FA-MSP lf=Nc-1 demand realization stage.
            is_loh_demand_stage(k1) = (a > 1 && lf == Nc - 1);
            % This is a zero-cost absorbing state. It does not create new
            % LOH demand.
            is_terminal_landfall(k1) = (lf == Nc);
        end
    end
end
P_joint = row_normalize_h2(P_joint);

P_terminals = cell(T, 1);
for t = 1:T
    P_terminals{t} = row_normalize_h2(P_joint^(T - t));
end

Ni = get_required_scalar(NearStageInput.Sets, 'num_sites');
Nj = get_required_scalar(NearStageInput.Sets, 'num_nodes');

x_0 = get_required_vector(NearStageInput.InitialState, 'x0_h2_kg', Ni);
x_cap = get_required_vector(NearStageInput.HydrogenDevice, 'tank_cap_kg', Ni);
x_min = get_required_vector(NearStageInput.HydrogenDevice, 'tank_min_kg', Ni);
el_cap_kw = get_required_vector(NearStageInput.HydrogenDevice, 'el_cap_kw', Ni);
el_ramp_up_kw = get_required_vector(NearStageInput.HydrogenDevice, 'el_ramp_up_kw', Ni);
el_ramp_down_kw = get_required_vector(NearStageInput.HydrogenDevice, 'el_ramp_down_kw', Ni);

k_H2 = get_required_scalar(NearStageInput.HydrogenDevice, 'k_H2_kg_per_kWh');
eta_EL = get_required_scalar(NearStageInput.HydrogenDevice, 'eta_EL');
fc_cap_kw = get_required_vector(NearStageInput.HydrogenDevice, 'fc_cap_kw', Ni);
eta_FC = get_required_scalar(NearStageInput.HydrogenDevice, 'eta_FC');
h2_lhv_kWh_per_kg = get_required_scalar(NearStageInput.HydrogenDevice, 'h2_lhv_kWh_per_kg');

dt_h = getOpt(opts, 'dt_h', get_required_scalar(NearStageInput.NormalDemand, 'stage_dt_h'));
D_template = get_required_matrix(NearStageInput.NormalDemand, 'stage_template_kg');
if size(D_template, 1) ~= Ni
    error('load_data_h2_near:BadNormalDemandRows', ...
        'NormalDemand.stage_template_kg must have %d rows.', Ni);
end
D_normal = expand_normal_demand_h2(D_template, T, opts);

site_positions = get_required_matrix(NearStageInput.Spatial, 'site_positions');
node_positions = get_required_matrix(NearStageInput.Spatial, 'node_positions');
site_to_site_road_km = get_required_matrix(NearStageInput.Spatial, 'site_to_site_road_km');
site_to_node_road_km = get_required_matrix(NearStageInput.Spatial, 'site_to_node_road_km');
A_site_node = get_required_matrix(NearStageInput.Spatial, 'service_weight_site_node');

H_node_kg = get_required_vector(NearStageInput.CriticalLoad, 'H_node_kg', Nj);
base_target_loh_by_site_kg = get_required_vector( ...
    NearStageInput.CriticalLoad, 'base_target_loh_by_site_kg', Ni);

N_HTT = get_required_scalar(NearStageInput.HTT, 'N_HTT');
Q_HTT_kg = get_required_scalar(NearStageInput.HTT, 'Q_HTT_kg');
htt_capacity_base = get_required_scalar(NearStageInput.HTT, 'base_capacity_kg_per_stage');
htt_cost_base = get_required_matrix(NearStageInput.HTT, 'site_to_site_base_cost_yuan_per_kg');
beta_transport_multiplier = get_required_scalar(NearStageInput.HTT, 'beta_transport_multiplier');

[beta, betaMode] = build_beta_h2(S, NearStageInput, opts);
[TerminalLOH, terminalMode, terminalTemplateUsed, terminalLoadInfo] = build_terminal_loh_h2( ...
    S, NearStageInput, opts);

cost_electricity_stage = build_electricity_cost_h2( ...
    get_required_value(NearStageInput.Cost, 'electricity_price_yuan_per_kWh'), ...
    T, dt_h, opts);

params = struct();
params.dataDir = dataDir;
params.nearInputFile = nearInputFile;
params.NearStageInput = NearStageInput;
params.rootDir = fileparts(dataDir);

params.Ni = Ni;
params.Nj = Nj;
params.T = T;
params.K = K;
params.Na = Na;
params.Nb = Nb;
params.Nc = Nc;
params.S = S;
params.state_id = state_id;
params.P_intensity = P_intensity;
params.P_location = P_location;
params.P_landfall = P_landfall;
params.P_joint = P_joint;
params.P_terminals = P_terminals;
params.is_dissipated = is_dissipated;
params.is_terminal_landfall = is_terminal_landfall;
params.is_loh_demand_stage = is_loh_demand_stage;
params.is_absorbing = is_dissipated | is_terminal_landfall;
params.absorbing_states = find(params.is_absorbing);
params.transient_states = find(~params.is_absorbing);
params.ordinary_states = find(~params.is_absorbing & ~params.is_loh_demand_stage);

params.k_init = getOpt(opts, 'k_init', 65);
params.nbOS = getOpt(opts, 'nbOS', 10000);
params.max_iter = getOpt(opts, 'max_iter', 100000);
params.stall = getOpt(opts, 'stall', 500);
params.cutviol_maxiter = getOpt(opts, 'cutviol_maxiter', 100000);
params.time_limit = getOpt(opts, 'time_limit', 3600);
params.eps_tol = getOpt(opts, 'eps_tol', 1e-5);

params.x0 = x_0;
params.x_0 = x_0;
params.x_cap = x_cap;
params.x_min = x_min;
params.use_tank_min = getOpt(opts, 'use_tank_min', false);

params.el_cap_kw = el_cap_kw;
params.el_ramp_up_kw = el_ramp_up_kw;
params.el_ramp_down_kw = el_ramp_down_kw;
params.k_H2 = k_H2;
params.k_H2_kg_per_kWh = k_H2;
params.eta_EL = eta_EL;
params.fc_cap_kw = fc_cap_kw;
params.eta_FC = eta_FC;
params.h2_lhv_kWh_per_kg = h2_lhv_kWh_per_kg;
params.dt_h = dt_h;

params.D_normal = D_normal;
params.H_node_kg = H_node_kg;
params.P_node_load_kw = terminalLoadInfo.P_node_load_kw;
params.H_node_load_kg = terminalLoadInfo.H_node_load_kg;
params.P_critical_base_kw = terminalLoadInfo.P_critical_base_kw;
params.H_node_critical_kg = terminalLoadInfo.H_node_critical_kg;
params.terminal_load_mode = terminalLoadInfo.mode;
params.terminal_load_info = terminalLoadInfo;
params.A_site_node = A_site_node;
params.base_target_loh_by_site_kg = base_target_loh_by_site_kg;
params.TerminalLOH = TerminalLOH;
params.terminal_loh_mode = terminalMode;
params.terminal_impact_template_used = terminalTemplateUsed;
params.use_nonterminal_targetloh = false;
% Deprecated compatibility fields. They are intentionally zero and are not
% used by the v2 non-terminal LP, forward pass, evaluation, or cuts.
params.TargetLOH = zeros(Ni, K);
params.TargetLOH_array = params.TargetLOH;
params.alpha = zeros(K, 1);
params.target_loh_mode = "deprecated_nonterminal_targetloh_disabled";

params.site_positions = site_positions;
params.node_positions = node_positions;
params.site_to_site_road_km = site_to_site_road_km;
params.site_to_node_road_km = site_to_node_road_km;

params.N_HTT = N_HTT;
params.Q_HTT_kg = Q_HTT_kg;
params.htt_capacity_base = htt_capacity_base;
params.transport_cost_base = htt_cost_base;
params.htt_cost_base = htt_cost_base;
params.beta_original = beta;
params.beta = beta;
params.beta_source_mode = betaMode;
params.beta_transport_multiplier = beta_transport_multiplier;
params.beta_enabled = getOpt(opts, 'beta_enabled', true);
if ~islogical(params.beta_enabled) && ~(isnumeric(params.beta_enabled) && isscalar(params.beta_enabled))
    error('load_data_h2_near:BadBetaEnabled', 'opts.beta_enabled must be true or false.');
end
params.beta_enabled = logical(params.beta_enabled);
if ~params.beta_enabled
    params.beta = zeros(K, 1);
    params.beta_mode = "disabled_all_zero";
    params.use_beta_capacity = false;
    params.use_beta_cost = false;
else
    params.beta_mode = "enabled";
    params.use_beta_capacity = getOpt(opts, 'use_beta_capacity', true);
    params.use_beta_cost = getOpt(opts, 'use_beta_cost', true);
end

params.cost_electricity_stage = cost_electricity_stage;
params.cost_electricity = cost_electricity_stage;
params.cost_el_om = get_required_scalar(NearStageInput.Cost, 'el_om_yuan_per_kWh');
params.cost_holding = get_required_scalar(NearStageInput.Cost, 'h2_holding_cost_yuan_per_kg');
baseNormalPenalty = get_required_scalar(NearStageInput.Cost, 'normal_shortage_penalty_yuan_per_kg');
normalPenaltyMultiplier = getOpt(opts, 'normal_shortage_penalty_multiplier', 1);
if ~isscalar(normalPenaltyMultiplier) || normalPenaltyMultiplier <= 0
    error('load_data_h2_near:BadNormalShortagePenaltyMultiplier', ...
        'opts.normal_shortage_penalty_multiplier must be a positive scalar.');
end
params.cost_normal_shortage_base = baseNormalPenalty;
params.normal_shortage_penalty_multiplier = normalPenaltyMultiplier;
params.cost_normal_shortage = baseNormalPenalty * normalPenaltyMultiplier;
params.cost_reserve_shortage = get_required_scalar(NearStageInput.Cost, 'reserve_shortage_penalty_yuan_per_kg');
params.cost_transport = htt_cost_base;
params.cost_transport_base = htt_cost_base;

params.store_eval_decisions = getOpt(opts, 'store_eval_decisions', false);
params.allow_zero_terminal_loh = getOpt(opts, 'allow_zero_terminal_loh', false);
params.P_joint_row_sums = sum(P_joint, 2);
params.num_absorbing_states = numel(params.absorbing_states);

validate_h2_params(params);
end

function D_normal = expand_normal_demand_h2(D_template, T, opts)
mode = getOpt(opts, 'normal_demand_mode', 'error');
nCols = size(D_template, 2);
if nCols == T
    D_normal = D_template;
    return;
end
switch lower(mode)
    case 'repeat_template'
        reps = ceil(T / nCols);
        D_normal = repmat(D_template, 1, reps);
        D_normal = D_normal(:, 1:T);
    otherwise
        error('load_data_h2_near:NormalDemandLengthMismatch', ...
            ['NormalDemand.stage_template_kg has %d columns, but T = %d. ' ...
            'Set opts.normal_demand_mode = ''repeat_template'' explicitly if this is intended.'], ...
            nCols, T);
end
end

function cStage = build_electricity_cost_h2(price, T, dt_h, opts)
price = price(:).';
mode = getOpt(opts, 'electricity_price_mode', 'stage_average_from_hourly');
if isscalar(price)
    cStage = repmat(price, T, 1);
elseif numel(price) == T
    cStage = price(:);
elseif strcmpi(mode, 'stage_average_from_hourly') || strcmpi(mode, 'stage_average_repeat_hourly')
    hoursPerStage = max(1, round(dt_h));
    needed = T * hoursPerStage;
    if numel(price) < needed && strcmpi(mode, 'stage_average_repeat_hourly')
        price = repmat(price, 1, ceil(needed / numel(price)));
    end
    if numel(price) < needed
        error('load_data_h2_near:ShortElectricityPrice', ...
            'Need at least %d hourly electricity prices for T=%d and dt_h=%g.', ...
            needed, T, dt_h);
    end
    cStage = zeros(T, 1);
    for t = 1:T
        idx = (t - 1) * hoursPerStage + (1:hoursPerStage);
        cStage(t) = mean(price(idx));
    end
else
    error('load_data_h2_near:BadElectricityPriceLength', ...
        'Electricity price length is %d, but T = %d.', numel(price), T);
end
end

function X = row_normalize_h2(X)
rowSums = sum(X, 2);
if any(rowSums <= 0)
    error('load_data_h2_near:BadTransitionRows', ...
        'Transition matrix contains non-positive row sums.');
end
X = X ./ rowSums;
end

function val = get_required_value(s, fieldName)
if ~isfield(s, fieldName)
    error('load_data_h2_near:MissingField', 'Missing required field: %s.', fieldName);
end
val = s.(fieldName);
end

function val = get_required_scalar(s, fieldName)
val = get_required_value(s, fieldName);
if ~isscalar(val)
    error('load_data_h2_near:ExpectedScalar', 'Field %s must be scalar.', fieldName);
end
val = double(val);
end

function val = get_required_vector(s, fieldName, n)
val = double(get_required_value(s, fieldName));
val = val(:);
if nargin >= 3 && numel(val) ~= n
    error('load_data_h2_near:BadVectorLength', ...
        'Field %s must have %d entries, got %d.', fieldName, n, numel(val));
end
end

function val = get_required_matrix(s, fieldName)
val = double(get_required_value(s, fieldName));
if ~ismatrix(val)
    error('load_data_h2_near:ExpectedMatrix', 'Field %s must be a matrix.', fieldName);
end
end

function val = getOpt(opts, fieldName, defaultVal)
if isfield(opts, fieldName)
    val = opts.(fieldName);
else
    val = defaultVal;
end
end
