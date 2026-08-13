function data = load_hourly_grid_data_h2(rootDir, overrides)
%LOAD_HOURLY_GRID_DATA_H2 Load the frozen Stage-79 hourly grid inputs.

% This module deliberately keeps road anchors and electrical buses as
% separate fields.  The equal integer values are a synthetic benchmark
% coupling assumption, not a GIS identity.

if nargin < 1 || isempty(rootDir)
    rootDir = fileparts(fileparts(mfilename('fullpath')));
end
if nargin < 2 || isempty(overrides)
    overrides = struct();
end

baseFile = fullfile(rootDir, 'data', 'yuanqi', 'near_stage_msp_input.mat');
h02SaaFile = fullfile(rootDir, 'results', 'task-002-stage2b-b3-smoke', ...
    '73-htt-transport-cost-sensitivity', 'run-001', 'H02', ...
    'case-saa', 'sensitivity_input.mat');
h02DroFile = fullfile(rootDir, 'results', 'task-002-stage2b-b3-smoke', ...
    '73-htt-transport-cost-sensitivity', 'run-001', 'H02', ...
    'case-chi2_eta003', 'sensitivity_input.mat');

requiredFiles = {baseFile, h02SaaFile, h02DroFile};
for k = 1:numel(requiredFiles)
    if ~isfile(requiredFiles{k})
        error('load_hourly_grid_data_h2:MissingInput', ...
            'Missing frozen input: %s', requiredFiles{k});
    end
end

baseRaw = load(baseFile, 'NearStageInput');
saaRaw = load(h02SaaFile, 'NearStageInput');
droRaw = load(h02DroFile, 'NearStageInput');
base = baseRaw.NearStageInput;
saa = saaRaw.NearStageInput;
dro = droRaw.NearStageInput;

lambda24 = [ ...
    0.783042, 0.737820, 0.723015, 0.707941, 0.698789, 0.677793, ...
    0.662719, 0.707941, 0.801077, 0.801077, 0.843338, 0.873486, ...
    0.888560, 0.915747, 0.888560, 0.888560, 0.879408, 0.843338, ...
    0.864334, 0.975774, 1.000000, 0.975774, 0.963930, 0.888560];
phi24 = [ ...
    0, 0, 0, 0, 0, 0, 0, 0, 0.014969, 0.043234, 0.094988, ...
    0.174421, 0.219728, 0.335005, 0.385584, 0.332415, 0.273062, ...
    0.177524, 0.052788, 0, 0, 0, 0, 0];

grid = base.Grid;
activeRows = double(grid.branch_indices(:));
edges = double(grid.power_edges(activeRows, 1:2));

data = struct();
data.root_dir = rootDir;
data.base_input_file = baseFile;
data.h02_saa_input_file = h02SaaFile;
data.h02_dro_input_file = h02DroFile;
data.base_input = base;
data.h02_saa_input = saa;
data.h02_dro_input = dro;

data.n_bus = 33;
data.n_branch = 32;
data.branch_from = edges(:, 1);
data.branch_to = edges(:, 2);
data.r_ohm = double(grid.r_ohm(activeRows));
data.x_ohm = double(grid.x_ohm(activeRows));
data.base_kv = 12.66;
data.base_mva = 10;
data.slack_bus = 1;
data.slack_v_sq = 1;
data.vmin_pu = get_override(overrides, 'vmin_pu', 0.95);
data.vmax_pu = get_override(overrides, 'vmax_pu', 1.05);
data.branch_smax_mva = 6;
data.branch_octagon_a = 0.9238795325;
data.branch_octagon_b = 1.3065629649;
data.p_substation_max_kw = double(grid.P_substation_max_kw);
data.p_load_base_kw = double(grid.P_load_base_kw(:));
data.q_load_base_kvar = double(grid.Q_load_base_kVAr(:));

data.stage_dt_h = 8;
data.n_operating_stages = 6;
data.hours_per_stage = 8;
data.lambda24 = lambda24(:);
data.lambda48 = repmat(lambda24(:), 2, 1);
data.phi24 = phi24(:);
data.phi48 = repmat(phi24(:), 2, 1);
data.tariff24 = double(base.Cost.electricity_price_yuan_per_kWh(:));
data.tariff48 = repmat(data.tariff24, 2, 1);
data.tariff_source = [baseFile, ...
    '::NearStageInput.Cost.electricity_price_yuan_per_kWh'];

data.site_id = (1:4).';
data.road_site_node = [24; 14; 18; 31];
data.site_elec_bus = map_site_to_electrical_bus_h2();
data.mapping_class = 'SYNTHETIC_BENCHMARK_COUPLING_ASSUMPTION';
data.pv_cap_kw = 200 * ones(4, 1);
data.pmax_kw = double(saa.HydrogenDevice.el_cap_kw(:));
data.k_h2_kg_per_kwh = double(saa.HydrogenDevice.k_H2_kg_per_kWh);
data.tank_cap_kg = double(saa.HydrogenDevice.tank_cap_kg(:));
data.x0_kg = double(saa.InitialState.x0_h2_kg(:));
data.htt_capacity_kg_per_stage = double(saa.HTT.base_capacity_kg_per_stage);
data.beta_transport_multiplier = double(saa.HTT.beta_transport_multiplier);
data.transport_distance_coefficient = infer_cd(saa);
data.normal_demand_stage_kg = double(saa.NormalDemand.stage_template_kg);
data.el_om_yuan_per_kwh = double(saa.Cost.el_om_yuan_per_kWh);
end

function value = get_override(overrides, name, defaultValue)
if isfield(overrides, name)
    value = double(overrides.(name));
else
    value = defaultValue;
end
if ~isscalar(value) || ~isfinite(value)
    error('load_hourly_grid_data_h2:BadOverride', ...
        'Override %s must be a finite scalar.', name);
end
end

function cd = infer_cd(near)
road = double(near.Spatial.site_to_site_road_km);
cost = double(near.HTT.site_to_site_base_cost_yuan_per_kg);
mask = road > 0;
ratios = cost(mask) ./ road(mask);
cd = mean(ratios);
if max(abs(ratios - cd)) > 1e-12
    error('load_hourly_grid_data_h2:TransportCostIdentity', ...
        'H02 transport cost is not a scalar multiple of road distance.');
end
end
