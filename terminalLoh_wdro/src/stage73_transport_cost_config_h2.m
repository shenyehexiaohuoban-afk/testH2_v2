function cfg = stage73_transport_cost_config_h2(rootDir, experimentId)
%STAGE73_TRANSPORT_COST_CONFIG_H2 Isolated E1-8h HTT cost sensitivity.

sourceFile = fullfile(rootDir, 'data', 'yuanqi', 'near_stage_msp_input.mat');
raw = load(sourceFile, 'NearStageInput');
NearStageInput = raw.NearStageInput;

experimentId = upper(char(string(experimentId)));
switch experimentId
    case 'REFERENCE_08'
        cd = 0.8;
        outputName = 'Reference_08';
    case 'H04'
        cd = 0.4;
        outputName = 'H04';
    case 'H02'
        cd = 0.2;
        outputName = 'H02';
    case 'H01'
        cd = 0.1;
        outputName = 'H01';
    otherwise
        error('stage73_transport_cost_config_h2:BadExperiment', ...
            'Unknown Stage-73 experiment: %s', experimentId);
end

roadKm = double(NearStageInput.Spatial.site_to_site_road_km);
NearStageInput.HTT.site_to_site_base_cost_yuan_per_kg = cd * roadKm;
dtH = 8;
pmax = double(NearStageInput.HydrogenDevice.el_cap_kw(:)).';
kH2 = double(NearStageInput.HydrogenDevice.k_H2_kg_per_kWh);
rmax = pmax * kH2 * dtH;

cfg = struct();
cfg.experiment_id = experimentId;
cfg.output_name = outputName;
cfg.transport_distance_coefficient = cd;
cfg.dt_h = dtH;
cfg.NearStageInput = NearStageInput;
cfg.source_file = sourceFile;
cfg.road_km = roadKm;
cfg.transport_base_cost = cd * roadKm;
cfg.pmax_kw = pmax;
cfg.k_H2_kg_per_kWh = kH2;
cfg.rmax_kg_per_stage = rmax;
cfg.htt_capacity_kg_per_stage = double(NearStageInput.HTT.base_capacity_kg_per_stage);
cfg.beta_transport_multiplier = double(NearStageInput.HTT.beta_transport_multiplier);
cfg.normal_demand_template_kg = double(NearStageInput.NormalDemand.stage_template_kg);
cfg.holding_cost_yuan_per_kg_stage = double(NearStageInput.Cost.h2_holding_cost_yuan_per_kg);
cfg.normal_shortage_penalty_yuan_per_kg = double(NearStageInput.Cost.normal_shortage_penalty_yuan_per_kg);
cfg.terminal_gap_penalty_yuan_per_kg = double(NearStageInput.Cost.reserve_shortage_penalty_yuan_per_kg);

if cfg.dt_h ~= 8 || abs(cfg.htt_capacity_kg_per_stage - 160) > 1e-12
    error('stage73_transport_cost_config_h2:BaseIdentity', ...
        'Stage-73 must retain E1 dt=8 and HTT capacity=160 kg/stage.');
end
if max(abs(diag(cfg.transport_base_cost))) > 1e-12
    error('stage73_transport_cost_config_h2:DiagonalCost', ...
        'Within-site HTT cost diagonal must remain zero.');
end
if max(abs(cfg.transport_base_cost - cd * roadKm), [], 'all') > 1e-12
    error('stage73_transport_cost_config_h2:CostIdentity', ...
        'Base transport cost does not equal c_d * road distance.');
end
end
