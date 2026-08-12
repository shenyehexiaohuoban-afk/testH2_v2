function cfg = stage71_experiment_config_h2(rootDir, experimentId)
%STAGE71_EXPERIMENT_CONFIG_H2 Build isolated Stage-71 sensitivity inputs.

sourceFile = fullfile(rootDir, 'data', 'yuanqi', 'near_stage_msp_input.mat');
raw = load(sourceFile, 'NearStageInput');
NearStageInput = raw.NearStageInput;

experimentId = char(string(experimentId));
switch experimentId
    case 'E1_8h'
        dtH = 8;
        outputName = 'E1_8h';
    case 'E2_6h_pmax_4over3'
        dtH = 6;
        outputName = 'E2_6h_pmax_4over3';
        NearStageInput.HydrogenDevice.el_cap_kw = ...
            double(NearStageInput.HydrogenDevice.el_cap_kw) * (4 / 3);
    case 'E3_8h_htt_4over3'
        dtH = 8;
        outputName = 'E3_8h_htt_4over3';
        NearStageInput.HTT.base_capacity_kg_per_stage = ...
            double(NearStageInput.HTT.base_capacity_kg_per_stage) * (4 / 3);
    otherwise
        error('stage71_experiment_config_h2:BadExperiment', ...
            'Unknown Stage-71 experiment: %s', experimentId);
end

pmax = double(NearStageInput.HydrogenDevice.el_cap_kw(:)).';
kH2 = double(NearStageInput.HydrogenDevice.k_H2_kg_per_kWh);
rmax = pmax * kH2 * dtH;
prices = double(NearStageInput.Cost.electricity_price_yuan_per_kWh(:)).';
needed = 8 * dtH;
prices = repmat(prices, 1, ceil(needed / numel(prices)));
stagePrice = zeros(1, 8);
for t = 1:8
    idx = (t - 1) * dtH + (1:dtH);
    stagePrice(t) = mean(prices(idx));
end

cfg = struct();
cfg.experiment_id = experimentId;
cfg.output_name = outputName;
cfg.dt_h = dtH;
cfg.NearStageInput = NearStageInput;
cfg.source_file = sourceFile;
cfg.pmax_kw = pmax;
cfg.k_H2_kg_per_kWh = kH2;
cfg.rmax_kg_per_stage = rmax;
cfg.htt_capacity_kg_per_stage = ...
    double(NearStageInput.HTT.base_capacity_kg_per_stage);
cfg.N_HTT = double(NearStageInput.HTT.N_HTT);
cfg.Q_HTT_kg = double(NearStageInput.HTT.Q_HTT_kg);
cfg.normal_demand_template_kg = ...
    double(NearStageInput.NormalDemand.stage_template_kg);
cfg.stage_electricity_price_yuan_per_kWh = stagePrice;
cfg.holding_cost_yuan_per_kg_stage = ...
    double(NearStageInput.Cost.h2_holding_cost_yuan_per_kg);
cfg.normal_shortage_penalty_yuan_per_kg = ...
    double(NearStageInput.Cost.normal_shortage_penalty_yuan_per_kg);
cfg.terminal_gap_penalty_yuan_per_kg = ...
    double(NearStageInput.Cost.reserve_shortage_penalty_yuan_per_kg);

baseDemand = double(raw.NearStageInput.NormalDemand.stage_template_kg);
if max(abs(cfg.normal_demand_template_kg - baseDemand), [], 'all') > 1e-12
    error('stage71_experiment_config_h2:DemandDrift', ...
        'Ordinary kg/stage demand changed in %s.', experimentId);
end
if cfg.N_HTT ~= 2 || cfg.Q_HTT_kg ~= 80
    error('stage71_experiment_config_h2:HTTMetadataDrift', ...
        'N_HTT and Q_HTT must remain 2 and 80 kg.');
end
end
