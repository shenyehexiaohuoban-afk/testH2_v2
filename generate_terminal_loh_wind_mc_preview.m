clear; clc;

rootDir = fileparts(mfilename('fullpath'));
if isempty(rootDir)
    rootDir = pwd;
end

addpath(rootDir);
addpath(fullfile(rootDir, 'fa_h2'));
addpath(fullfile(rootDir, 'fa_h2', 'fuzhu'));
addpath(fullfile(rootDir, 'fa_h2', 'fuzhu', 'terminalLoh_windmc'));
addpath(fullfile(rootDir, 'fa_h2', 'fuzhu', 'terminalLoh_windmc', 'draw'));
addpath(fullfile(rootDir, 'utils'));

opts = h2_default_options(rootDir);
opts.support_hours = 2;
params = load_data_h2_near(opts.dataDir, opts.nearInputFile, opts);

optsWind = struct();
optsWind.previewMode = 'joint10';
optsWind.jointNmc = 10;
optsWind.Nmc = 10;
optsWind.seed = 20260513;
optsWind.supportHours = opts.support_hours;
optsWind.outputDir = fullfile(rootDir, 'output_h2', 'wind_terminal_loh_preview');
optsWind.roadDataDir = fullfile(rootDir, 'data', 'yuanqi');
optsWind.elecGridDir = fullfile(optsWind.outputDir, 'elec_grid');
optsWind.roadDir = fullfile(optsWind.outputDir, 'road');
optsWind.riskCapMeanDir = fullfile(optsWind.outputDir, 'riskcap_mean');
optsWind.elecFigureDir = fullfile(optsWind.outputDir, 'figures', 'elec_grid');
optsWind.roadFigureDir = fullfile(optsWind.outputDir, 'figures', 'road');
optsWind.riskCapMeanFigureDir = fullfile(optsWind.outputDir, 'figures', 'riskcap_mean');
optsWind.retiredMethodDir = fullfile(optsWind.outputDir, ['riskcap' '_ot']);
optsWind.retiredMethodFigureDir = fullfile(optsWind.outputDir, 'figures', ['riskcap' '_ot']);
optsWind.windDecayB = 0.6;
optsWind.designWindSpeedVN = 25;

optsWind.roadEnabled = true;
optsWind.roadNmc = 10;
optsWind.roadSeed = 20260513;
optsWind.roadDesignWindVN = 30;
optsWind.roadSlowdownLambda = 1.0;
optsWind.roadTau = 10;
optsWind.serviceTimeLimit = 60;
optsWind.serviceRadiusPenalty = 1.0;
optsWind.capacityAttractionEta = 0.5;

optsWind.riskCapMeanEnabled = true;
optsWind.riskCapMeanCapacityMode = 'reserve_fraction';
optsWind.riskCapMeanReserveFraction = 0.8;
optsWind.riskCapMeanPriorityModes = {'uniform', 'key_load_demo'};
optsWind.riskCapMeanDefaultPriority = 1;
optsWind.riskCapMeanKeyNodePriority = 5;
optsWind.riskCapMeanManualKeyNodes = [];
optsWind.riskCapMeanCostWeights = struct( ...
    'baseDistance', 0.30, ...
    'roadUnreliability', 0.40, ...
    'travelTime', 0.30);
optsWind.riskCapMeanLowReachabilityThreshold = 0.5;
optsWind.riskCapMeanHighRiskThreshold = 0.75;
optsWind.riskCapMeanPenaltyMultiplier = 1e6;
optsWind.riskCapMeanEpsilon = 1e-9;
optsWind.riskCapMeanBindingToleranceKg = 1e-5;
optsWind.riskCapMeanMaxIterations = 1000;
optsWind.riskCapMeanMaxFunctionEvaluations = 20000;
optsWind = apply_preview_mode(optsWind);

[windMC, diagTables] = build_terminal_loh_wind_mc_preview_h2( ...
    params, params.NearStageInput, optsWind);

ensure_preview_dirs(optsWind);
cleanup_legacy_preview_outputs(optsWind.outputDir);
cleanup_retired_method_outputs(optsWind);

writetable(diagTables.by_state, fullfile(optsWind.elecGridDir, 'terminal_loh_wind_mc_by_state.csv'));
writetable(diagTables.by_state_rmax, fullfile(optsWind.elecGridDir, 'terminal_loh_wind_mc_by_state_rmax.csv'));
writetable(diagTables.line_failure, fullfile(optsWind.elecGridDir, 'terminal_loh_wind_mc_line_failure.csv'));
writetable(diagTables.node_outage, fullfile(optsWind.elecGridDir, 'terminal_loh_wind_mc_node_outage.csv'));
writetable(diagTables.layout, fullfile(optsWind.elecGridDir, 'terminal_loh_wind_mc_layout.csv'));

[jointPreview, jointTables] = build_joint_mc_preview(params, windMC, optsWind);
currentATbl = build_currentA_terminal_table_from_joint(params, jointTables.state_node);
[roadPreview, roadTables] = build_road_soft_preview_from_joint(params, jointTables, windMC, optsWind);
compareTbl = build_currentA_vs_roadSoft_table(currentATbl, roadTables.terminal_by_state);
[riskCapMeanPreview, riskCapMeanTables] = build_riskcap_mean_preview(params, roadTables, optsWind);
compareRiskCapMeanTbl = build_currentA_roadSoft_RiskCapMean_compare( ...
    currentATbl, roadTables.terminal_by_state, riskCapMeanTables.terminal_by_state);

writetable(currentATbl, fullfile(optsWind.outputDir, 'terminal_loh_by_state_currentA.csv'));
writetable(roadTables.terminal_by_state, fullfile(optsWind.outputDir, 'terminal_loh_by_state_roadSoft.csv'));
writetable(compareTbl, fullfile(optsWind.outputDir, 'terminal_loh_by_state_currentA_vs_roadSoft.csv'));
writetable(roadTables.allocation, fullfile(optsWind.outputDir, 'terminal_loh_allocation_roadSoft.csv'));

writetable(roadTables.network, fullfile(optsWind.roadDir, 'terminal_loh_preview_road_network.csv'));
writetable(roadTables.site_node_shortest_path_distance, ...
    fullfile(optsWind.roadDir, 'site_node_shortest_path_distance.csv'));
writetable(roadTables.edge_risk, fullfile(optsWind.roadDir, 'terminal_loh_road_edge_risk.csv'));
writetable(roadTables.access, fullfile(optsWind.roadDir, 'terminal_loh_road_access_site_node.csv'));

writetable(jointTables.scenario_summary, fullfile(optsWind.riskCapMeanDir, 'joint_scenario_summary.csv'));
writetable(jointTables.scenario_site_node, fullfile(optsWind.riskCapMeanDir, 'joint_scenario_site_node.csv'));
write_riskcap_mean_tables(optsWind, riskCapMeanTables, compareRiskCapMeanTbl);

write_wind_mc_preview_readme(optsWind, roadPreview);
write_riskcap_mean_readme(optsWind, riskCapMeanPreview);
save(fullfile(optsWind.outputDir, 'terminal_loh_wind_mc_preview.mat'), ...
    'windMC', 'diagTables', 'jointPreview', 'jointTables', ...
    'roadPreview', 'roadTables', 'riskCapMeanPreview', ...
    'riskCapMeanTables', 'compareRiskCapMeanTbl', 'optsWind', '-v7.3');

export_terminal_loh_wind_mc_figures_h2(diagTables, windMC, optsWind);
export_road_soft_figures(roadTables, currentATbl, diagTables, windMC, optsWind);
export_riskcap_mean_figures(currentATbl, roadTables, riskCapMeanTables, jointTables, optsWind);

fprintf('\n终端储氢需求离线预览根目录:\n%s\n', optsWind.outputDir);
fprintf('电网输出目录:\n%s\n', optsWind.elecGridDir);
fprintf('道路输出目录:\n%s\n', optsWind.roadDir);
fprintf('风险容量均值分配输出目录:\n%s\n', optsWind.riskCapMeanDir);
fprintf('电网图片输出目录:\n%s\n', optsWind.elecFigureDir);
fprintf('道路图片输出目录:\n%s\n', optsWind.roadFigureDir);
fprintf('风险容量均值分配图片输出目录:\n%s\n', optsWind.riskCapMeanFigureDir);
fprintf('道路输入数据目录:\n%s\n', optsWind.roadDataDir);
fprintf('support_hours = %.6g h\n', params.terminal_load_info.support_hours);
fprintf('previewMode = %s; jointNmc=%d, Nmc=%d, roadNmc=%d\n', ...
    optsWind.previewMode, optsWind.jointNmc, optsWind.Nmc, optsWind.roadNmc);
fprintf('风险容量均值分配容量模式 = %s; reserve_fraction = %.6g\n', ...
    optsWind.riskCapMeanCapacityMode, optsWind.riskCapMeanReserveFraction);
fprintf('stage1 道路边数量 = %d\n', height(roadTables.network));
fprintf('道路边风场坐标来源: windMC.layout.nodes\n');
fprintf('联合场景行数 = %d\n', height(jointTables.scenario_summary));

fprintf('原始分配终端储氢需求总量 kg min/mean/max = %.6f / %.6f / %.6f\n', ...
    min(currentATbl.TerminalLOH_total_currentA_kg), ...
    mean(currentATbl.TerminalLOH_total_currentA_kg), ...
    max(currentATbl.TerminalLOH_total_currentA_kg));
fprintf('道路软分配终端储氢需求总量 kg min/mean/max = %.6f / %.6f / %.6f\n', ...
    min(roadTables.terminal_by_state.TerminalLOH_total_roadSoft_kg), ...
    mean(roadTables.terminal_by_state.TerminalLOH_total_roadSoft_kg), ...
    max(roadTables.terminal_by_state.TerminalLOH_total_roadSoft_kg));
fprintf('风险容量均值分配终端储氢需求总量 kg min/mean/max = %.6f / %.6f / %.6f\n', ...
    min(riskCapMeanTables.terminal_by_state.TerminalLOH_total_RiskCapMean_kg), ...
    mean(riskCapMeanTables.terminal_by_state.TerminalLOH_total_RiskCapMean_kg), ...
    max(riskCapMeanTables.terminal_by_state.TerminalLOH_total_RiskCapMean_kg));
fprintf('风险容量均值分配未覆盖量 kg min/mean/max = %.6f / %.6f / %.6f\n', ...
    min(riskCapMeanTables.terminal_by_state.uncovered_total_kg), ...
    mean(riskCapMeanTables.terminal_by_state.uncovered_total_kg), ...
    max(riskCapMeanTables.terminal_by_state.uncovered_total_kg));
fprintf('风险容量均值分配失败状态数 = %d\n', ...
    sum(~startsWith(string(riskCapMeanTables.terminal_by_state.solve_status), "solved") & ...
    string(riskCapMeanTables.terminal_by_state.solve_status) ~= "zero_demand_direct"));
fprintf('fallback 节点总数 = %d\n', sum(roadTables.terminal_by_state.fallback_node_count));

fprintf('\n电网诊断输出保存在 elec_grid/ 下。\n');
fprintf('expected_failed_lines min/mean/max = %.6f / %.6f / %.6f\n', ...
    min(diagTables.by_state.expected_failed_lines), ...
    mean(diagTables.by_state.expected_failed_lines), ...
    max(diagTables.by_state.expected_failed_lines));
fprintf('expected_lost_load_kw min/mean/max = %.6f / %.6f / %.6f\n', ...
    min(diagTables.by_state.expected_lost_load_kw), ...
    mean(diagTables.by_state.expected_lost_load_kw), ...
    max(diagTables.by_state.expected_lost_load_kw));

function ensure_preview_dirs(optsWind)
dirs = {optsWind.outputDir, optsWind.elecGridDir, optsWind.roadDir, ...
    optsWind.riskCapMeanDir, optsWind.elecFigureDir, optsWind.roadFigureDir, ...
    optsWind.riskCapMeanFigureDir};
for ii = 1:numel(dirs)
    if ~exist(dirs{ii}, 'dir')
        mkdir(dirs{ii});
    end
end
end

function optsWind = apply_preview_mode(optsWind)
switch string(optsWind.previewMode)
    case "joint10"
        optsWind.jointNmc = 10;
        optsWind.Nmc = 10;
        optsWind.roadNmc = 10;
    case "joint50"
        optsWind.jointNmc = 50;
        optsWind.Nmc = 50;
        optsWind.roadNmc = 50;
    case "joint200"
        optsWind.jointNmc = 200;
        optsWind.Nmc = 200;
        optsWind.roadNmc = 200;
    case "quick10"
        optsWind.jointNmc = 10;
        optsWind.Nmc = 10;
        optsWind.roadNmc = 10;
    otherwise
        error('generate_terminal_loh_wind_mc_preview:BadPreviewMode', ...
            'Unsupported previewMode: %s. Use joint10, joint50, joint200, or quick10.', optsWind.previewMode);
end
end

function cleanup_retired_method_outputs(optsWind)
targets = {optsWind.retiredMethodDir, optsWind.retiredMethodFigureDir};
allowedRoots = {optsWind.outputDir, fullfile(optsWind.outputDir, 'figures')};
for ii = 1:numel(targets)
    target = char(targets{ii});
    if exist(target, 'dir')
        safe = false;
        for rr = 1:numel(allowedRoots)
            root = char(allowedRoots{rr});
            safe = safe || startsWith(lower(target), lower(root));
        end
        if ~safe
            error('generate_terminal_loh_wind_mc_preview:UnsafeRetiredOTCleanup', ...
                'Refusing to remove path outside preview output roots: %s', target);
        end
        rmdir(target, 's');
    end
end
end

function cleanup_legacy_preview_outputs(outDir)
legacyFiles = {'terminal_loh_wind_mc_by_state.csv', ...
    'terminal_loh_wind_mc_by_state_rmax.csv', ...
    'terminal_loh_wind_mc_line_failure.csv', ...
    'terminal_loh_wind_mc_node_outage.csv', ...
    'terminal_loh_wind_mc_layout.csv'};
for ii = 1:numel(legacyFiles)
    f = fullfile(outDir, legacyFiles{ii});
    if isfile(f)
        delete(f);
    end
end
legacyFigureDirs = {'layout', 'storm_states', 'line_maps', 'node_maps', ...
    'terminal_loh', 'summary'};
for ii = 1:numel(legacyFigureDirs)
    d = fullfile(outDir, 'figures', legacyFigureDirs{ii});
    if exist(d, 'dir')
        rmdir(d, 's');
    end
end
end

function currentATbl = build_currentA_terminal_table_from_joint(params, stateNodeTbl)
stateTbl = unique(stateNodeTbl(:, {'a', 'loc', 'lf'}), 'rows', 'stable');
rows = {};
for ss = 1:height(stateTbl)
    a = stateTbl.a(ss);
    loc = stateTbl.loc(ss);
    lf = stateTbl.lf(ss);
    Hbar = zeros(params.Nj, 1);
    for n = 1:params.Nj
        nRows = stateNodeTbl.a == a & stateNodeTbl.loc == loc & ...
            stateNodeTbl.lf == lf & stateNodeTbl.node_id == n;
        if nnz(nRows) ~= 1
            error('generate_terminal_loh_wind_mc_preview:MissingJointHbarNode', ...
                'Missing Hbar node row for a=%d, loc=%d, lf=%d, node=%d.', a, loc, lf, n);
        end
        Hbar(n) = stateNodeTbl.Hbar_node_kg(nRows);
    end
    terminalSite = params.A_site_node * Hbar;
    rows(end + 1, :) = {a, loc, lf, terminalSite(1), terminalSite(2), ...
        terminalSite(3), terminalSite(4), sum(terminalSite)}; %#ok<AGROW>
end
currentATbl = cell_rows_to_table(rows, {'a', 'loc', 'lf', ...
    'TerminalLOH_site1_currentA_kg', 'TerminalLOH_site2_currentA_kg', ...
    'TerminalLOH_site3_currentA_kg', 'TerminalLOH_site4_currentA_kg', ...
    'TerminalLOH_total_currentA_kg'});
end

function compareTbl = build_currentA_vs_roadSoft_table(currentATbl, roadTbl)
compareTbl = join(currentATbl, roadTbl, 'Keys', {'a', 'loc', 'lf'});
for i = 1:4
    cName = sprintf('TerminalLOH_site%d_currentA_kg', i);
    rName = sprintf('TerminalLOH_site%d_roadSoft_kg', i);
    dName = sprintf('diff_site%d_kg', i);
    compareTbl.(dName) = compareTbl.(rName) - compareTbl.(cName);
end
compareTbl.diff_total_kg = compareTbl.TerminalLOH_total_roadSoft_kg - ...
    compareTbl.TerminalLOH_total_currentA_kg;
end

function [jointPreview, jointTables] = build_joint_mc_preview(params, windMC, optsWind)
rng(optsWind.seed, 'twister');
layout = windMC.layout;
stage1Road = load_stage1_road_data(optsWind.roadDataDir, params, layout);
roadNetwork = stage1Road.network;
PNodeLoadKw = params.P_node_load_kw(:);
supportHours = get_terminal_scalar_preview(params, 'support_hours');
etaFC = get_terminal_scalar_preview(params, 'eta_FC');
lhv = get_terminal_scalar_preview(params, 'h2_lhv_kWh_per_kg');
lfDemand = params.Nc - 1;

scenarioRows = {};
siteNodeRows = {};
stateNodeRows = {};
stateSiteNodeRows = {};
edgeRows = {};

for a = 2:params.Na
    Vmax = windMC.Vmax_by_a(a);
    for loc = 1:height(layout.locs)
        center = select_loc_center(layout, loc);
        Hsum = zeros(params.Nj, 1);
        reachCount = zeros(params.Ni, params.Nj);
        travelSum = zeros(params.Ni, params.Nj);
        travelCount = zeros(params.Ni, params.Nj);
        edgeWindSum = zeros(height(roadNetwork), 1);
        edgePCloseSum = zeros(height(roadNetwork), 1);
        edgeClosedCount = zeros(height(roadNetwork), 1);

        for ss = 1:optsWind.jointNmc
            rIdx = sample_discrete(windMC.Rmax_prob);
            Rmax = windMC.Rmax_by_a(a, rIdx);
            rmaxType = windMC.Rmax_type(rIdx);

            lineDist = hypot(layout.lines.line_mid_x_km - center(1), ...
                layout.lines.line_mid_y_km - center(2));
            lineWind = compute_wind_speed_radial_h2(lineDist, Vmax, Rmax, optsWind.windDecayB);
            pFail = compute_line_failure_prob_h2(lineWind, optsWind.designWindSpeedVN);
            failedLine = rand(height(layout.lines), 1) < pFail(:);
            connected = connected_to_source_preview(params.Nj, layout.lines.from_node, ...
                layout.lines.to_node, ~failedLine);
            outage = ~connected(:);
            outage(1) = false;
            lostLoadKw = double(outage) .* PNodeLoadKw;
            Hnode = lostLoadKw * supportHours / (etaFC * lhv);
            Hsum = Hsum + Hnode;

            roadDist = hypot(roadNetwork.edge_mid_x_km - center(1), ...
                roadNetwork.edge_mid_y_km - center(2));
            roadWind = compute_wind_speed_radial_h2(roadDist, Vmax, Rmax, optsWind.windDecayB);
            pClose = compute_line_failure_prob_h2(roadWind, optsWind.roadDesignWindVN);
            riskFactor = pClose;
            baseEdgeTime = roadNetwork.edge_length_km(:) .* ...
                (1 + optsWind.roadSlowdownLambda .* riskFactor(:));
            closedRoad = rand(height(roadNetwork), 1) < pClose(:);
            edgeTime = baseEdgeTime;
            edgeTime(closedRoad) = Inf;
            edgeWindSum = edgeWindSum + roadWind(:);
            edgePCloseSum = edgePCloseSum + pClose(:);
            edgeClosedCount = edgeClosedCount + double(closedRoad(:));

            scenarioReach = false(params.Ni, params.Nj);
            scenarioTravel = inf(params.Ni, params.Nj);
            for i = 1:params.Ni
                dist = dijkstra_preview(params.Nj, ...
                    roadNetwork, edgeTime, stage1Road.site_anchor_node(i));
                for n = 1:params.Nj
                    scenarioReach(i, n) = isfinite(dist(n));
                    if scenarioReach(i, n)
                        scenarioTravel(i, n) = dist(n);
                        reachCount(i, n) = reachCount(i, n) + 1;
                        travelSum(i, n) = travelSum(i, n) + dist(n);
                        travelCount(i, n) = travelCount(i, n) + 1;
                    end
                end
            end

            finiteTravel = scenarioTravel(isfinite(scenarioTravel));
            if isempty(finiteTravel)
                meanTravel = NaN;
            else
                meanTravel = mean(finiteTravel);
            end
            scenarioRows(end + 1, :) = {a, loc, lfDemand, ss, char(rmaxType), ...
                Rmax, sum(Hnode), sum(failedLine), sum(lostLoadKw), ...
                sum(closedRoad), mean(double(scenarioReach(:))), meanTravel}; %#ok<AGROW>

            for i = 1:params.Ni
                for n = 1:params.Nj
                    if scenarioReach(i, n)
                        scenCost = stage1Road.site_to_node_road_km(i, n) + scenarioTravel(i, n);
                    else
                        scenCost = Inf;
                    end
                    siteNodeRows(end + 1, :) = {a, loc, lfDemand, ss, i, n, ...
                        Hnode(n), scenarioReach(i, n), scenarioTravel(i, n), scenCost}; %#ok<AGROW>
                end
            end
        end

        Hbar = Hsum ./ optsWind.jointNmc;
        for n = 1:params.Nj
            stateNodeRows(end + 1, :) = {a, loc, lfDemand, n, Hbar(n)}; %#ok<AGROW>
        end
        reachProb = reachCount ./ optsWind.jointNmc;
        avgTravel = inf(params.Ni, params.Nj);
        positiveTravel = travelCount > 0;
        avgTravel(positiveTravel) = travelSum(positiveTravel) ./ travelCount(positiveTravel);
        for i = 1:params.Ni
            for n = 1:params.Nj
                stateSiteNodeRows(end + 1, :) = {a, loc, lfDemand, i, n, ...
                    stage1Road.site_to_node_road_km(i, n), reachProb(i, n), ...
                    avgTravel(i, n)}; %#ok<AGROW>
            end
        end
        for ee = 1:height(roadNetwork)
            edgeRows(end + 1, :) = {a, loc, lfDemand, roadNetwork.road_edge_id(ee), ...
                roadNetwork.from_node(ee), roadNetwork.to_node(ee), ...
                edgeWindSum(ee) ./ optsWind.jointNmc, ...
                edgePCloseSum(ee) ./ optsWind.jointNmc, ...
                edgeClosedCount(ee) ./ optsWind.jointNmc, ...
                roadNetwork.edge_length_km(ee)}; %#ok<AGROW>
        end
    end
end

jointTables = struct();
jointTables.scenario_summary = cell_rows_to_table(scenarioRows, ...
    {'a', 'loc', 'lf', 'scenario_id', 'Rmax_type', 'Rmax_km', ...
    'total_H_node_kg', 'failed_line_count', 'lost_load_kw', ...
    'closed_road_edge_count', 'mean_reachability', ...
    'mean_travel_time_or_distance'});
jointTables.scenario_site_node = cell_rows_to_table(siteNodeRows, ...
    {'a', 'loc', 'lf', 'scenario_id', 'site_id', 'node_id', ...
    'H_node_kg_s', 'reachable', 'travel_time_or_distance', ...
    'scenario_service_cost'});
jointTables.state_node = cell_rows_to_table(stateNodeRows, ...
    {'a', 'loc', 'lf', 'node_id', 'Hbar_node_kg'});
jointTables.state_site_node = cell_rows_to_table(stateSiteNodeRows, ...
    {'a', 'loc', 'lf', 'site_id', 'node_id', ...
    'base_site_to_node_road_km', 'reachability_probability', ...
    'avg_travel_time_or_distance'});
jointTables.road_edge_state = cell_rows_to_table(edgeRows, ...
    {'a', 'loc', 'lf', 'road_edge_id', 'from_node', 'to_node', ...
    'wind_speed_mps', 'road_close_probability', ...
    'observed_close_frequency', 'edge_length_km'});
jointTables.network = roadNetwork;
jointTables.node_positions = stage1Road.node_positions;
jointTables.site_nodes = stage1Road.site_nodes;
jointTables.site_anchor_node = stage1Road.site_anchor_node;
jointTables.site_node_shortest_path_distance = stage1Road.site_to_node_road_km_table;

jointPreview = struct();
jointPreview.jointNmc = optsWind.jointNmc;
jointPreview.seed = optsWind.seed;
jointPreview.description = "Each joint scenario samples grid line failures and road edge closures under the same terminal typhoon state.";
jointPreview.RmaxProb = windMC.Rmax_prob;
jointPreview.RmaxType = windMC.Rmax_type;
end

function idx = sample_discrete(prob)
prob = prob(:) ./ sum(prob(:));
cdf = cumsum(prob);
u = rand();
idx = find(u <= cdf, 1, 'first');
if isempty(idx)
    idx = numel(prob);
end
end

function connected = connected_to_source_preview(Nj, fromNode, toNode, activeLine)
adj = false(Nj, Nj);
for ll = 1:numel(fromNode)
    if activeLine(ll)
        i = fromNode(ll);
        j = toNode(ll);
        if i <= Nj && j <= Nj
            adj(i, j) = true;
            adj(j, i) = true;
        end
    end
end
connected = false(Nj, 1);
queue = zeros(Nj, 1);
head = 1;
tail = 1;
queue(tail) = 1;
connected(1) = true;
while head <= tail
    cur = queue(head);
    head = head + 1;
    nbrs = find(adj(cur, :));
    for nn = nbrs
        if ~connected(nn)
            connected(nn) = true;
            tail = tail + 1;
            queue(tail) = nn;
        end
    end
end
end

function val = get_terminal_scalar_preview(params, fieldName)
if isfield(params, 'terminal_load_info') && isfield(params.terminal_load_info, fieldName)
    val = double(params.terminal_load_info.(fieldName));
elseif isfield(params, fieldName)
    val = double(params.(fieldName));
else
    error('generate_terminal_loh_wind_mc_preview:MissingTerminalScalar', ...
        'Missing required scalar params.%s or params.terminal_load_info.%s.', ...
        fieldName, fieldName);
end
end

function [roadPreview, roadTables] = build_road_soft_preview_from_joint(params, jointTables, windMC, optsWind)
stateTbl = unique(jointTables.state_node(:, {'a', 'loc', 'lf'}), 'rows', 'stable');
accessRows = {};
allocRows = {};
terminalRows = {};
capacityWeight = get_capacity_weight(params, optsWind);

for ss = 1:height(stateTbl)
    a = stateTbl.a(ss);
    loc = stateTbl.loc(ss);
    lf = stateTbl.lf(ss);
    stateSiteRows = jointTables.state_site_node(jointTables.state_site_node.a == a & ...
        jointTables.state_site_node.loc == loc & jointTables.state_site_node.lf == lf, :);
    if height(stateSiteRows) ~= params.Ni * params.Nj
        error('generate_terminal_loh_wind_mc_preview:BadJointRoadAccessRows', ...
            'Expected %d state-site-node rows for a=%d, loc=%d, lf=%d.', ...
            params.Ni * params.Nj, a, loc, lf);
    end
    Hbar = zeros(params.Nj, 1);
    for n = 1:params.Nj
        hRows = jointTables.state_node.a == a & jointTables.state_node.loc == loc & ...
            jointTables.state_node.lf == lf & jointTables.state_node.node_id == n;
        Hbar(n) = jointTables.state_node.Hbar_node_kg(hRows);
    end
    baseDist = inf(params.Ni, params.Nj);
    reachProb = zeros(params.Ni, params.Nj);
    avgTravel = inf(params.Ni, params.Nj);
    for rr = 1:height(stateSiteRows)
        i = stateSiteRows.site_id(rr);
        n = stateSiteRows.node_id(rr);
        baseDist(i, n) = stateSiteRows.base_site_to_node_road_km(rr);
        reachProb(i, n) = stateSiteRows.reachability_probability(rr);
        avgTravel(i, n) = stateSiteRows.avg_travel_time_or_distance(rr);
    end
    roadServiceCost = inf(size(baseDist));
    reachable = reachProb > 0;
    roadServiceCost(reachable) = baseDist(reachable) ./ max(reachProb(reachable), 1e-6) + ...
        optsWind.serviceRadiusPenalty .* max(0, baseDist(reachable) - optsWind.serviceTimeLimit);

    for i = 1:params.Ni
        for n = 1:params.Nj
            accessRows(end + 1, :) = {a, loc, lf, i, n, baseDist(i, n), ...
                reachProb(i, n), avgTravel(i, n), roadServiceCost(i, n)}; %#ok<AGROW>
        end
    end

    terminalSite = zeros(params.Ni, 1);
    fallbackNodeCount = 0;
    for n = 1:params.Nj
        Hnode = Hbar(n);
        score = zeros(params.Ni, 1);
        for i = 1:params.Ni
            if isfinite(roadServiceCost(i, n)) && reachProb(i, n) > 0
                score(i) = capacityWeight(i) * reachProb(i, n) * ...
                    exp(-roadServiceCost(i, n) / optsWind.roadTau);
            end
        end
        fallbackUsed = sum(score) <= 0;
        if fallbackUsed
            share = params.A_site_node(:, n);
            if Hnode > 0
                fallbackNodeCount = fallbackNodeCount + 1;
            end
        else
            share = score / sum(score);
        end
        allocated = share * Hnode;
        terminalSite = terminalSite + allocated;
        for i = 1:params.Ni
            allocRows(end + 1, :) = {a, loc, lf, i, n, Hnode, share(i), ...
                allocated(i), reachProb(i, n), roadServiceCost(i, n), fallbackUsed}; %#ok<AGROW>
        end
    end
    terminalRows(end + 1, :) = {a, loc, lf, terminalSite(1), terminalSite(2), ...
        terminalSite(3), terminalSite(4), sum(terminalSite), fallbackNodeCount}; %#ok<AGROW>
end

roadTables = struct();
roadTables.network = jointTables.network;
roadTables.node_positions = jointTables.node_positions;
roadTables.site_nodes = jointTables.site_nodes;
roadTables.site_node_shortest_path_distance = jointTables.site_node_shortest_path_distance;
roadTables.edge_risk = jointTables.road_edge_state;
roadTables.access = cell_rows_to_table(accessRows, ...
    {'a', 'loc', 'lf', 'site_id', 'node_id', 'base_site_to_node_road_km', ...
    'reachability_probability', 'expected_travel_time_or_distance', 'road_service_cost'});
roadTables.terminal_by_state = cell_rows_to_table(terminalRows, ...
    {'a', 'loc', 'lf', 'TerminalLOH_site1_roadSoft_kg', ...
    'TerminalLOH_site2_roadSoft_kg', 'TerminalLOH_site3_roadSoft_kg', ...
    'TerminalLOH_site4_roadSoft_kg', 'TerminalLOH_total_roadSoft_kg', ...
    'fallback_node_count'});
roadTables.allocation = cell_rows_to_table(allocRows, ...
    {'a', 'loc', 'lf', 'site_id', 'node_id', 'H_node_kg', ...
    'allocation_share_roadSoft', 'allocated_H2_kg', ...
    'reachability_probability', 'road_service_cost', 'fallback_used'});

roadPreview = struct();
roadPreview.capacityWeight = capacityWeight;
roadPreview.capacityWeightSource = capacity_weight_source(params);
roadPreview.roadTau = optsWind.roadTau;
roadPreview.jointMeanSource = "joint_scenario_state_summaries";
roadPreview.RmaxTypePolicy = "sampled jointly per scenario";
roadPreview.siteAnchorNode = jointTables.site_anchor_node;
roadPreview.layout = windMC.layout;
end

function stage1Road = load_stage1_road_data(roadDataDir, params, windLayout)
requiredFiles = {'stage1_road_edges.csv', 'stage1_site_nodes.csv'};
for ii = 1:numel(requiredFiles)
    f = fullfile(roadDataDir, requiredFiles{ii});
    if ~isfile(f)
        error('generate_terminal_loh_wind_mc_preview:MissingStage1RoadFile', ...
            'Missing required stage1 road file: %s', f);
    end
end

roadEdgesRaw = readtable(fullfile(roadDataDir, 'stage1_road_edges.csv'));
siteNodes = readtable(fullfile(roadDataDir, 'stage1_site_nodes.csv'));

require_table_vars(roadEdgesRaw, {'road_edge_id', 'from_node', 'to_node'}, 'stage1_road_edges.csv');
require_table_vars(siteNodes, {'site_id', 'grid_node'}, 'stage1_site_nodes.csv');

windNodePos = windLayout.nodes(:, {'node_id', 'x_km', 'y_km'});
windNodePos = sortrows(windNodePos, 'node_id');
if height(windNodePos) ~= params.Nj || any(windNodePos.node_id(:) ~= (1:params.Nj).')
    error('generate_terminal_loh_wind_mc_preview:BadWindLayoutNodes', ...
        'windMC.layout.nodes must contain node_id 1:%d.', params.Nj);
end
windSitePos = windLayout.sites(:, {'site_id', 'x_km', 'y_km'});
windSitePos = sortrows(windSitePos, 'site_id');
if height(windSitePos) ~= params.Ni || any(windSitePos.site_id(:) ~= (1:params.Ni).')
    error('generate_terminal_loh_wind_mc_preview:BadWindLayoutSites', ...
        'windMC.layout.sites must contain site_id 1:%d.', params.Ni);
end
if height(siteNodes) ~= params.Ni || any(sort(siteNodes.site_id(:)) ~= (1:params.Ni).')
    error('generate_terminal_loh_wind_mc_preview:BadStage1SiteNodes', ...
        'stage1_site_nodes.csv must contain site_id 1:%d.', params.Ni);
end
siteNodes = sortrows(siteNodes, 'site_id');
if any(siteNodes.grid_node(:) < 1 | siteNodes.grid_node(:) > params.Nj)
    error('generate_terminal_loh_wind_mc_preview:BadStage1SiteAnchor', ...
        'stage1_site_nodes.csv contains grid_node outside 1:%d.', params.Nj);
end

fromNode = roadEdgesRaw.from_node;
toNode = roadEdgesRaw.to_node;
if any(fromNode(:) < 1 | fromNode(:) > params.Nj | toNode(:) < 1 | toNode(:) > params.Nj)
    error('generate_terminal_loh_wind_mc_preview:BadStage1RoadEdges', ...
        'stage1_road_edges.csv contains from_node/to_node outside 1:%d.', params.Nj);
end
fromX = windNodePos.x_km(fromNode);
fromY = windNodePos.y_km(fromNode);
toX = windNodePos.x_km(toNode);
toY = windNodePos.y_km(toNode);
edgeMidX = (fromX + toX) / 2;
edgeMidY = (fromY + toY) / 2;
edgeLength = hypot(toX - fromX, toY - fromY);
network = table(roadEdgesRaw.road_edge_id, fromNode, toNode, fromX, fromY, ...
    toX, toY, edgeMidX, edgeMidY, edgeLength, ...
    'VariableNames', {'road_edge_id', 'from_node', 'to_node', ...
    'from_x_km', 'from_y_km', 'to_x_km', 'to_y_km', ...
    'edge_mid_x_km', 'edge_mid_y_km', 'edge_length_km'});

siteToNodeKm = nan(params.Ni, params.Nj);
for i = 1:params.Ni
    dist = dijkstra_preview(params.Nj, network, network.edge_length_km, siteNodes.grid_node(i));
    siteToNodeKm(i, :) = dist(:).';
end
if any(~isfinite(siteToNodeKm), 'all')
    error('generate_terminal_loh_wind_mc_preview:DisconnectedStage1RoadGraph', ...
        'stage1_road_edges.csv does not connect every site anchor to all %d nodes.', params.Nj);
end
distRows = cell(params.Ni * params.Nj, 5);
rr = 0;
for i = 1:params.Ni
    for n = 1:params.Nj
        rr = rr + 1;
        distRows(rr, :) = {i, siteNodes.grid_node(i), n, siteToNodeKm(i, n), ...
            "stage1_road_edges + windMC.layout.nodes"};
    end
end
siteNodeDist = cell2table(distRows, 'VariableNames', ...
    {'site_id', 'site_anchor_grid_node', 'node_id', ...
    'shortest_path_road_km', 'distance_source'});

stage1Road = struct();
stage1Road.node_positions = windNodePos;
stage1Road.site_nodes_raw = siteNodes;
stage1Road.site_nodes = table(siteNodes.site_id, siteNodes.grid_node, ...
    windSitePos.x_km, windSitePos.y_km, ...
    'VariableNames', {'site_id', 'grid_node', 'x_km', 'y_km'});
stage1Road.network = network;
stage1Road.site_anchor_node = siteNodes.grid_node(:);
stage1Road.site_to_node_road_km = siteToNodeKm;
stage1Road.site_to_node_road_km_table = siteNodeDist;
stage1Road.roadDataDir = roadDataDir;
end

function require_table_vars(tbl, names, fileName)
missing = setdiff(names, tbl.Properties.VariableNames);
if ~isempty(missing)
    error('generate_terminal_loh_wind_mc_preview:BadStage1TableHeader', ...
        '%s is missing required field(s): %s. Actual headers: %s', ...
        fileName, strjoin(missing, ', '), strjoin(tbl.Properties.VariableNames, ', '));
end
end

function dist = dijkstra_preview(Ntotal, roadNetwork, edgeTime, sourceNode)
dist = inf(Ntotal, 1);
visited = false(Ntotal, 1);
dist(sourceNode) = 0;
for iter = 1:Ntotal
    candidates = dist;
    candidates(visited) = Inf;
    [bestDist, u] = min(candidates);
    if ~isfinite(bestDist)
        break;
    end
    visited(u) = true;
    for ee = 1:height(roadNetwork)
        if ~isfinite(edgeTime(ee))
            continue;
        end
        from = roadNetwork.from_node(ee);
        to = roadNetwork.to_node(ee);
        v = NaN;
        if from == u
            v = to;
        elseif to == u
            v = from;
        end
        if ~isnan(v) && ~visited(v)
            alt = bestDist + edgeTime(ee);
            if alt < dist(v)
                dist(v) = alt;
            end
        end
    end
end
end

function row = select_mid_rmax_row(tbl, a, loc)
rows = tbl.a == a & tbl.loc == loc & string(tbl.Rmax_type) == "mid";
if nnz(rows) ~= 1
    error('generate_terminal_loh_wind_mc_preview:MissingMidRmax', ...
        'Expected one mid Rmax row for a=%d, loc=%d.', a, loc);
end
row = tbl(rows, :);
end

function center = select_loc_center(layout, loc)
rows = layout.locs.loc == loc;
if nnz(rows) ~= 1
    error('generate_terminal_loh_wind_mc_preview:MissingLocCenter', ...
        'Expected one loc center for loc=%d.', loc);
end
center = [layout.locs.center_x_km(rows), layout.locs.center_y_km(rows)];
end

function capacityWeight = get_capacity_weight(params, optsWind)
if isfield(params, 'x_cap') && numel(params.x_cap) == params.Ni
    capacityWeight = max(params.x_cap(:), 0) .^ optsWind.capacityAttractionEta;
else
    capacityWeight = ones(params.Ni, 1);
end
end

function src = capacity_weight_source(params)
if isfield(params, 'x_cap') && numel(params.x_cap) == params.Ni
    src = "params.x_cap";
else
    src = "none_capacityWeight_all_ones";
end
end

function idx = riskcap_y_index(i, n, Ni)
idx = i + (n - 1) * Ni;
end

function tbl = cell_rows_to_table(rows, variableNames)
if isempty(rows)
    rows = cell(0, numel(variableNames));
end
tbl = cell2table(rows, 'VariableNames', variableNames);
end

function [riskCapMeanPreview, riskCapMeanTables] = build_riskcap_mean_preview(params, roadTables, optsWind)
if ~optsWind.riskCapMeanEnabled
    error('generate_terminal_loh_wind_mc_preview:RiskCapMeanDisabled', ...
        'RiskCap-Mean is disabled, but this preview requires RiskCap-Mean outputs.');
end
if exist('fmincon', 'file') ~= 2
    error('generate_terminal_loh_wind_mc_preview:MissingFmincon', ...
        'RiskCap-Mean requires MATLAB fmincon, but fmincon is not available.');
end

[Cap, xCap, reserveFraction] = get_riskcap_mean_capacity(params, optsWind);
prioritySettings = build_riskcap_mean_priority_settings(params, optsWind);
stateTbl = roadTables.terminal_by_state(:, {'a', 'loc', 'lf'});
priorityModes = string(optsWind.riskCapMeanPriorityModes);
capacityMode = string(optsWind.riskCapMeanCapacityMode);

terminalRows = {};
allocRows = {};
capacityRows = {};
uncoveredRows = {};
serviceRiskRows = {};
costRows = {};

for mm = 1:numel(priorityModes)
    priorityMode = priorityModes(mm);
    priority = priority_vector_from_settings(prioritySettings, priorityMode, params.Nj);
    for ss = 1:height(stateTbl)
        a = stateTbl.a(ss);
        loc = stateTbl.loc(ss);
        lf = stateTbl.lf(ss);
        [Hbar, reachProb, avgTravel, baseDist] = ...
            extract_riskcap_mean_state_inputs(roadTables, params.Ni, params.Nj, a, loc, lf);
        comp = build_riskcap_mean_cost_components(reachProb, avgTravel, baseDist, priority, optsWind);
        result = solve_riskcap_mean_state(Hbar, reachProb, comp.serviceRiskCost, ...
            Cap, priority, optsWind);

        terminalSite = sum(result.y, 2);
        terminalRows(end + 1, :) = {char(priorityMode), char(capacityMode), ...
            a, loc, lf, terminalSite(1), terminalSite(2), terminalSite(3), ...
            terminalSite(4), sum(terminalSite), sum(result.u), ...
            result.priorityWeightedUncovered, result.fullCoverFeasible, ...
            result.uncoveredAllowed, char(result.solve_status)}; %#ok<AGROW>

        roadSoftY = roadsoft_allocation_matrix(roadTables.allocation, ...
            params.Ni, params.Nj, a, loc, lf);
        currentAY = params.A_site_node .* repmat(Hbar(:).', params.Ni, 1);
        serviceRiskRows(end + 1, :) = service_risk_metric_row_mean(priorityMode, ...
            capacityMode, "currentA", a, loc, lf, currentAY, zeros(params.Nj, 1), ...
            priority, reachProb, comp.unweightedCost, comp.serviceRiskCost, Cap, optsWind); %#ok<AGROW>
        serviceRiskRows(end + 1, :) = service_risk_metric_row_mean(priorityMode, ...
            capacityMode, "roadSoft", a, loc, lf, roadSoftY, zeros(params.Nj, 1), ...
            priority, reachProb, comp.unweightedCost, comp.serviceRiskCost, Cap, optsWind); %#ok<AGROW>
        serviceRiskRows(end + 1, :) = service_risk_metric_row_mean(priorityMode, ...
            capacityMode, "RiskCapMean", a, loc, lf, result.y, result.u, ...
            priority, reachProb, comp.unweightedCost, comp.serviceRiskCost, Cap, optsWind); %#ok<AGROW>

        for i = 1:params.Ni
            if Cap(i) > 0
                utilization = terminalSite(i) / Cap(i);
            else
                utilization = NaN;
            end
            binding = terminalSite(i) >= Cap(i) - optsWind.riskCapMeanBindingToleranceKg;
            capacityRows(end + 1, :) = {char(priorityMode), char(capacityMode), ...
                a, loc, lf, i, Cap(i), xCap(i), reserveFraction, terminalSite(i), ...
                utilization, binding}; %#ok<AGROW>
            for n = 1:params.Nj
                if Hbar(n) > optsWind.riskCapMeanEpsilon
                    share = result.y(i, n) / Hbar(n);
                else
                    share = 0;
                end
                allocRows(end + 1, :) = {char(priorityMode), char(capacityMode), ...
                    a, loc, lf, i, n, priority(n), Hbar(n), result.y(i, n), ...
                    share, reachProb(i, n), avgTravel(i, n), baseDist(i, n), ...
                    comp.serviceRiskCost(i, n)}; %#ok<AGROW>
                costRows(end + 1, :) = {char(priorityMode), char(capacityMode), ...
                    a, loc, lf, i, n, priority(n), comp.normBaseDistance(i, n), ...
                    comp.roadUnreliability(i, n), comp.normTravelTime(i, n), ...
                    comp.serviceRadiusViolationDiagnostic(i, n), ...
                    comp.serviceRiskCost(i, n)}; %#ok<AGROW>
            end
        end

        for n = 1:params.Nj
            if result.u(n) > optsWind.riskCapMeanBindingToleranceKg
                if Hbar(n) > optsWind.riskCapMeanEpsilon
                    uncoveredRatio = result.u(n) / Hbar(n);
                else
                    uncoveredRatio = NaN;
                end
                uncoveredRows(end + 1, :) = {char(priorityMode), char(capacityMode), ...
                    a, loc, lf, n, priority(n), Hbar(n), result.u(n), ...
                    uncoveredRatio, priority(n) * result.u(n)}; %#ok<AGROW>
            end
        end
    end
end

riskCapMeanTables = struct();
riskCapMeanTables.terminal_by_state = cell_rows_to_table(terminalRows, ...
    {'priority_mode', 'capacity_mode', 'a', 'loc', 'lf', ...
    'TerminalLOH_site1_RiskCapMean_kg', 'TerminalLOH_site2_RiskCapMean_kg', ...
    'TerminalLOH_site3_RiskCapMean_kg', 'TerminalLOH_site4_RiskCapMean_kg', ...
    'TerminalLOH_total_RiskCapMean_kg', 'uncovered_total_kg', ...
    'priority_weighted_uncovered_kg', 'full_cover_feasible', ...
    'uncovered_allowed', 'solve_status'});
riskCapMeanTables.allocation = cell_rows_to_table(allocRows, ...
    {'priority_mode', 'capacity_mode', 'a', 'loc', 'lf', 'site_id', ...
    'node_id', 'priority_n', 'Hbar_node_kg', 'allocated_H2_kg', ...
    'allocation_share_RiskCapMean', 'reachability_probability', ...
    'avg_travel_time_or_distance', 'base_site_to_node_road_km', ...
    'service_risk_cost'});
riskCapMeanTables.capacity_usage = cell_rows_to_table(capacityRows, ...
    {'priority_mode', 'capacity_mode', 'a', 'loc', 'lf', 'site_id', ...
    'Cap_i', 'x_cap_i', 'reserve_fraction', 'allocated_terminal_loh_kg', ...
    'capacity_utilization_ratio', 'capacity_binding_flag'});
riskCapMeanTables.uncovered_nodes = cell_rows_to_table(uncoveredRows, ...
    {'priority_mode', 'capacity_mode', 'a', 'loc', 'lf', 'node_id', ...
    'priority_n', 'Hbar_node_kg', 'uncovered_H2_kg', 'uncovered_ratio', ...
    'priority_weighted_uncovered_kg'});
riskCapMeanTables.service_risk_metrics = cell_rows_to_table(serviceRiskRows, ...
    {'priority_mode', 'capacity_mode', 'method', 'a', 'loc', 'lf', ...
    'total_terminal_loh_kg', 'total_service_risk', ...
    'priority_weighted_service_risk', 'allocated_weighted_avg_reachability', ...
    'low_reachability_allocated_kg', 'high_risk_allocated_kg', ...
    'max_capacity_utilization', 'capacity_binding_count', ...
    'uncovered_total_kg', 'priority_weighted_uncovered_kg'});
riskCapMeanTables.cost_components = cell_rows_to_table(costRows, ...
    {'priority_mode', 'capacity_mode', 'a', 'loc', 'lf', 'site_id', ...
    'node_id', 'priority_n', 'norm_base_distance', ...
    'road_unreliability', 'norm_travel_time', ...
    'service_radius_violation_diagnostic', 'service_risk_cost'});
riskCapMeanTables.priority_settings = prioritySettings;

riskCapMeanPreview = struct();
riskCapMeanPreview.capacityMode = string(optsWind.riskCapMeanCapacityMode);
riskCapMeanPreview.reserveFraction = reserveFraction;
riskCapMeanPreview.Cap = Cap;
riskCapMeanPreview.xCap = xCap;
riskCapMeanPreview.priorityModes = priorityModes;
riskCapMeanPreview.prioritySettings = prioritySettings;
riskCapMeanPreview.costWeights = optsWind.riskCapMeanCostWeights;
riskCapMeanPreview.objective = "sum(C*y) + M*sum(priority*u)";
riskCapMeanPreview.costDefinition = "priority*(0.30*norm_base_distance + 0.40*road_unreliability + 0.30*norm_travel_time)";
riskCapMeanPreview.fullCoverRule = "force u=0 when full coverage is feasible under Cap_i and reachability";
end

function [Cap, xCap, reserveFraction] = get_riskcap_mean_capacity(params, optsWind)
if ~isfield(params, 'x_cap') || numel(params.x_cap) ~= params.Ni
    error('generate_terminal_loh_wind_mc_preview:MissingRiskCapMeanCapacity', ...
        'RiskCap-Mean requires params.x_cap with one capacity per H2 site.');
end
xCap = params.x_cap(:);
switch string(optsWind.riskCapMeanCapacityMode)
    case "reserve_fraction"
        reserveFraction = optsWind.riskCapMeanReserveFraction;
        if reserveFraction <= 0 || reserveFraction > 1
            error('generate_terminal_loh_wind_mc_preview:BadRiskCapMeanReserveFraction', ...
                'riskCapMeanReserveFraction must be in (0,1].');
        end
        Cap = reserveFraction .* xCap;
    case "x_cap"
        reserveFraction = 1;
        Cap = xCap;
    otherwise
        error('generate_terminal_loh_wind_mc_preview:BadRiskCapMeanCapacityMode', ...
            'Unsupported RiskCap-Mean capacity mode: %s', optsWind.riskCapMeanCapacityMode);
end
end

function prioritySettings = build_riskcap_mean_priority_settings(params, optsWind)
priorityModes = string(optsWind.riskCapMeanPriorityModes);
rows = {};
for mm = 1:numel(priorityModes)
    mode = priorityModes(mm);
    switch mode
        case "uniform"
            for n = 1:params.Nj
                rows(end + 1, :) = {char(mode), n, optsWind.riskCapMeanDefaultPriority, ...
                    false, params.P_node_load_kw(n), "uniform_all_nodes"}; %#ok<AGROW>
            end
        case "key_load_demo"
            keyNodes = select_riskcap_mean_key_nodes(params, optsWind);
            for n = 1:params.Nj
                isKey = ismember(n, keyNodes);
                priority = optsWind.riskCapMeanDefaultPriority;
                reason = "non_key_node";
                if isKey
                    priority = optsWind.riskCapMeanKeyNodePriority;
                    if isempty(optsWind.riskCapMeanManualKeyNodes)
                        reason = "auto_selected_non_top_positive_load_key_node";
                    else
                        reason = "manual_key_node";
                    end
                end
                rows(end + 1, :) = {char(mode), n, priority, isKey, ...
                    params.P_node_load_kw(n), char(reason)}; %#ok<AGROW>
            end
        otherwise
            error('generate_terminal_loh_wind_mc_preview:BadRiskCapMeanPriorityMode', ...
                'Unsupported RiskCap-Mean priority mode: %s', mode);
    end
end
prioritySettings = cell_rows_to_table(rows, ...
    {'priority_mode', 'node_id', 'priority_n', 'is_key_node', ...
    'node_load_kw', 'selection_reason'});
end

function keyNodes = select_riskcap_mean_key_nodes(params, optsWind)
manual = optsWind.riskCapMeanManualKeyNodes;
if ~isempty(manual)
    keyNodes = unique(manual(:).');
    if any(keyNodes < 1) || any(keyNodes > params.Nj)
        error('generate_terminal_loh_wind_mc_preview:BadRiskCapMeanManualKeyNodes', ...
            'riskCapMeanManualKeyNodes must contain node ids in 1:%d.', params.Nj);
    end
    return;
end
loads = params.P_node_load_kw(:);
positiveNodes = find(loads > 0);
[~, order] = sort(loads(positiveNodes), 'descend');
ranked = positiveNodes(order);
if numel(ranked) <= 2
    keyNodes = ranked(:).';
else
    candidate = ranked(2:min(3, numel(ranked)));
    keyNodes = candidate(:).';
end
end

function [Hbar, reachProb, avgTravel, baseDist] = extract_riskcap_mean_state_inputs(roadTables, Ni, Nj, a, loc, lf)
allocRows = roadTables.allocation(roadTables.allocation.a == a & ...
    roadTables.allocation.loc == loc & roadTables.allocation.lf == lf, :);
accessRows = roadTables.access(roadTables.access.a == a & ...
    roadTables.access.loc == loc & roadTables.access.lf == lf, :);
if height(allocRows) ~= Ni * Nj || height(accessRows) ~= Ni * Nj
    error('generate_terminal_loh_wind_mc_preview:BadRiskCapMeanStateRows', ...
        'Expected %d allocation/access rows for a=%d, loc=%d, lf=%d.', ...
        Ni * Nj, a, loc, lf);
end
Hbar = zeros(Nj, 1);
reachProb = zeros(Ni, Nj);
avgTravel = inf(Ni, Nj);
baseDist = inf(Ni, Nj);
for n = 1:Nj
    nAlloc = allocRows(allocRows.node_id == n, :);
    Hvals = nAlloc.H_node_kg;
    if max(abs(Hvals - Hvals(1))) > 1e-8
        error('generate_terminal_loh_wind_mc_preview:InconsistentRiskCapMeanHbar', ...
            'Inconsistent H_node_kg for a=%d, loc=%d, lf=%d, node=%d.', ...
            a, loc, lf, n);
    end
    Hbar(n) = Hvals(1);
end
for rr = 1:height(accessRows)
    i = accessRows.site_id(rr);
    n = accessRows.node_id(rr);
    reachProb(i, n) = accessRows.reachability_probability(rr);
    avgTravel(i, n) = accessRows.expected_travel_time_or_distance(rr);
    baseDist(i, n) = accessRows.base_site_to_node_road_km(rr);
end
end

function comp = build_riskcap_mean_cost_components(reachProb, avgTravel, baseDist, priority, optsWind)
reachable = reachProb > 0;
normBase = normalize_riskcap_component(baseDist, isfinite(baseDist), 1);
normTravel = normalize_riskcap_component(avgTravel, reachable, 1);
roadUnreliability = min(1, max(0, 1 - reachProb));
radiusExcess = max(0, baseDist - optsWind.serviceTimeLimit);
finiteExcess = radiusExcess(isfinite(radiusExcess));
if isempty(finiteExcess) || max(finiteExcess) <= 0
    radiusDiagnostic = zeros(size(baseDist));
else
    radiusDiagnostic = radiusExcess ./ max(finiteExcess);
    radiusDiagnostic(~isfinite(radiusDiagnostic)) = 1;
    radiusDiagnostic = min(1, max(0, radiusDiagnostic));
end
w = optsWind.riskCapMeanCostWeights;
unweightedCost = w.baseDistance .* normBase + ...
    w.roadUnreliability .* roadUnreliability + ...
    w.travelTime .* normTravel;
serviceRiskCost = unweightedCost .* repmat(priority(:).', size(unweightedCost, 1), 1);
comp = struct();
comp.normBaseDistance = normBase;
comp.roadUnreliability = roadUnreliability;
comp.normTravelTime = normTravel;
comp.serviceRadiusViolationDiagnostic = radiusDiagnostic;
comp.unweightedCost = unweightedCost;
comp.serviceRiskCost = serviceRiskCost;
end

function result = solve_riskcap_mean_state(Hbar, reachProb, serviceRiskCost, Cap, priority, optsWind)
Ni = numel(Cap);
Nj = numel(Hbar);
epsVal = optsWind.riskCapMeanEpsilon;
if sum(Hbar) <= epsVal
    result.y = zeros(Ni, Nj);
    result.u = zeros(Nj, 1);
    result.objective = 0;
    result.exitflag = 1;
    result.priorityWeightedUncovered = 0;
    result.fullCoverFeasible = true;
    result.uncoveredAllowed = false;
    result.solve_status = "zero_demand_direct";
    return;
end
reachable = reachProb > 0;
[fullCoverFeasible, fullCoverY] = riskcap_full_cover_feasibility(Hbar, Cap, reachable, epsVal);
uncoveredAllowed = ~fullCoverFeasible;
C = serviceRiskCost;
finiteCost = C(isfinite(C));
if isempty(finiteCost) || max(finiteCost) <= 0
    maxFiniteCost = 1;
else
    maxFiniteCost = max(finiteCost);
end
C(~isfinite(C)) = maxFiniteCost;
penaltyM = optsWind.riskCapMeanPenaltyMultiplier * max(1, maxFiniteCost);

yCount = Ni * Nj;
nVars = yCount + Nj;
Aeq = zeros(Nj, nVars);
for n = 1:Nj
    for i = 1:Ni
        Aeq(n, riskcap_y_index(i, n, Ni)) = 1;
    end
    Aeq(n, yCount + n) = 1;
end
beq = Hbar(:);
A = zeros(Ni, nVars);
for i = 1:Ni
    for n = 1:Nj
        A(i, riskcap_y_index(i, n, Ni)) = 1;
    end
end
b = Cap(:);
lb = zeros(nVars, 1);
ub = inf(nVars, 1);
for n = 1:Nj
    for i = 1:Ni
        idx = riskcap_y_index(i, n, Ni);
        if ~reachable(i, n) || Hbar(n) <= epsVal
            ub(idx) = 0;
        else
            ub(idx) = Hbar(n);
        end
    end
    if uncoveredAllowed
        ub(yCount + n) = Hbar(n);
    else
        ub(yCount + n) = 0;
    end
end
z0Y = zeros(Ni, Nj);
if fullCoverFeasible
    z0Y = fullCoverY;
end
z0 = zeros(nVars, 1);
z0(1:yCount) = z0Y(:);
z0(yCount + (1:Nj)) = Hbar(:) - sum(z0Y, 1).';
objective = @(z) riskcap_mean_objective(z, Ni, Nj, C, penaltyM, priority);
options = optimoptions('fmincon', 'Display', 'off', ...
    'Algorithm', 'sqp', ...
    'SpecifyObjectiveGradient', true, ...
    'MaxIterations', optsWind.riskCapMeanMaxIterations, ...
    'MaxFunctionEvaluations', optsWind.riskCapMeanMaxFunctionEvaluations, ...
    'OptimalityTolerance', 1e-8, ...
    'ConstraintTolerance', 1e-8, ...
    'StepTolerance', 1e-10);
[z, fval, exitflag] = fmincon(objective, z0, A, b, Aeq, beq, lb, ub, [], options);
y = reshape(z(1:yCount), Ni, Nj);
u = z(yCount + (1:Nj));
y(abs(y) < 1e-8) = 0;
u(abs(u) < 1e-8) = 0;
if exitflag > 0
    status = sprintf('solved_exitflag_%d', exitflag);
else
    status = sprintf('failed_exitflag_%d', exitflag);
end
if fullCoverFeasible && sum(u) > optsWind.riskCapMeanBindingToleranceKg
    status = sprintf('abnormal_full_cover_feasible_uncovered_exitflag_%d', exitflag);
end
result.y = y;
result.u = u;
result.objective = fval;
result.exitflag = exitflag;
result.priorityWeightedUncovered = sum(priority(:) .* u(:));
result.fullCoverFeasible = fullCoverFeasible;
result.uncoveredAllowed = uncoveredAllowed;
result.solve_status = string(status);
end

function [f, g] = riskcap_mean_objective(z, Ni, Nj, C, penaltyM, priority)
yCount = Ni * Nj;
y = reshape(z(1:yCount), Ni, Nj);
u = z(yCount + (1:Nj));
f = sum(C(:) .* y(:)) + penaltyM * sum(priority(:) .* u(:));
if nargout > 1
    gy = C;
    gu = penaltyM * priority(:);
    g = [gy(:); gu];
end
end

function row = service_risk_metric_row_mean(priorityMode, capacityMode, method, a, loc, lf, ...
    y, u, priority, reachProb, unweightedCost, serviceRiskCost, Cap, optsWind)
siteAlloc = sum(y, 2);
total = sum(y(:));
if total > optsWind.riskCapMeanEpsilon
    totalServiceRisk = sum(unweightedCost(:) .* y(:));
    priorityWeightedRisk = sum(serviceRiskCost(:) .* y(:));
    weightedReach = sum(reachProb(:) .* y(:)) / total;
else
    totalServiceRisk = 0;
    priorityWeightedRisk = 0;
    weightedReach = NaN;
end
lowReachKg = sum(y(reachProb < optsWind.riskCapMeanLowReachabilityThreshold));
highRiskKg = sum(y(unweightedCost >= optsWind.riskCapMeanHighRiskThreshold));
if any(Cap(:) > 0)
    maxUtil = max(siteAlloc(:) ./ max(Cap(:), optsWind.riskCapMeanEpsilon));
else
    maxUtil = NaN;
end
bindingCount = sum(siteAlloc >= Cap(:) - optsWind.riskCapMeanBindingToleranceKg);
uncoveredTotal = sum(u);
priorityWeightedUncovered = sum(priority(:) .* u(:));
row = {char(priorityMode), char(capacityMode), char(method), a, loc, lf, ...
    total, totalServiceRisk, priorityWeightedRisk, weightedReach, ...
    lowReachKg, highRiskKg, maxUtil, bindingCount, uncoveredTotal, ...
    priorityWeightedUncovered};
end

function compareTbl = build_currentA_roadSoft_RiskCapMean_compare(currentATbl, roadTbl, riskTbl)
rows = {};
for rr = 1:height(riskTbl)
    mode = string(riskTbl.priority_mode(rr));
    a = riskTbl.a(rr);
    loc = riskTbl.loc(rr);
    lf = riskTbl.lf(rr);
    cRows = currentATbl(currentATbl.a == a & currentATbl.loc == loc & currentATbl.lf == lf, :);
    rRows = roadTbl(roadTbl.a == a & roadTbl.loc == loc & roadTbl.lf == lf, :);
    if height(cRows) ~= 1 || height(rRows) ~= 1
        error('generate_terminal_loh_wind_mc_preview:MissingRiskCapMeanCompareRows', ...
            'Missing compare rows for a=%d, loc=%d, lf=%d.', a, loc, lf);
    end
    currentVals = [cRows.TerminalLOH_site1_currentA_kg, cRows.TerminalLOH_site2_currentA_kg, ...
        cRows.TerminalLOH_site3_currentA_kg, cRows.TerminalLOH_site4_currentA_kg];
    roadVals = [rRows.TerminalLOH_site1_roadSoft_kg, rRows.TerminalLOH_site2_roadSoft_kg, ...
        rRows.TerminalLOH_site3_roadSoft_kg, rRows.TerminalLOH_site4_roadSoft_kg];
    riskVals = [riskTbl.TerminalLOH_site1_RiskCapMean_kg(rr), riskTbl.TerminalLOH_site2_RiskCapMean_kg(rr), ...
        riskTbl.TerminalLOH_site3_RiskCapMean_kg(rr), riskTbl.TerminalLOH_site4_RiskCapMean_kg(rr)];
    rows(end + 1, :) = {char(mode), a, loc, lf, currentVals(1), currentVals(2), ...
        currentVals(3), currentVals(4), cRows.TerminalLOH_total_currentA_kg, ...
        roadVals(1), roadVals(2), roadVals(3), roadVals(4), ...
        rRows.TerminalLOH_total_roadSoft_kg, riskVals(1), riskVals(2), ...
        riskVals(3), riskVals(4), riskTbl.TerminalLOH_total_RiskCapMean_kg(rr), ...
        riskVals(1) - roadVals(1), riskVals(2) - roadVals(2), ...
        riskVals(3) - roadVals(3), riskVals(4) - roadVals(4), ...
        riskTbl.TerminalLOH_total_RiskCapMean_kg(rr) - rRows.TerminalLOH_total_roadSoft_kg, ...
        riskVals(1) - currentVals(1), riskVals(2) - currentVals(2), ...
        riskVals(3) - currentVals(3), riskVals(4) - currentVals(4), ...
        riskTbl.TerminalLOH_total_RiskCapMean_kg(rr) - cRows.TerminalLOH_total_currentA_kg, ...
        riskTbl.uncovered_total_kg(rr), riskTbl.priority_weighted_uncovered_kg(rr)}; %#ok<AGROW>
end
compareTbl = cell_rows_to_table(rows, {'priority_mode', 'a', 'loc', 'lf', ...
    'TerminalLOH_site1_currentA_kg', 'TerminalLOH_site2_currentA_kg', ...
    'TerminalLOH_site3_currentA_kg', 'TerminalLOH_site4_currentA_kg', ...
    'TerminalLOH_total_currentA_kg', 'TerminalLOH_site1_roadSoft_kg', ...
    'TerminalLOH_site2_roadSoft_kg', 'TerminalLOH_site3_roadSoft_kg', ...
    'TerminalLOH_site4_roadSoft_kg', 'TerminalLOH_total_roadSoft_kg', ...
    'TerminalLOH_site1_RiskCapMean_kg', 'TerminalLOH_site2_RiskCapMean_kg', ...
    'TerminalLOH_site3_RiskCapMean_kg', 'TerminalLOH_site4_RiskCapMean_kg', ...
    'TerminalLOH_total_RiskCapMean_kg', ...
    'diff_site1_RiskCapMean_minus_roadSoft_kg', ...
    'diff_site2_RiskCapMean_minus_roadSoft_kg', ...
    'diff_site3_RiskCapMean_minus_roadSoft_kg', ...
    'diff_site4_RiskCapMean_minus_roadSoft_kg', ...
    'diff_total_RiskCapMean_minus_roadSoft_kg', ...
    'diff_site1_RiskCapMean_minus_currentA_kg', ...
    'diff_site2_RiskCapMean_minus_currentA_kg', ...
    'diff_site3_RiskCapMean_minus_currentA_kg', ...
    'diff_site4_RiskCapMean_minus_currentA_kg', ...
    'diff_total_RiskCapMean_minus_currentA_kg', ...
    'uncovered_total_kg', 'priority_weighted_uncovered_kg'});
end

function write_riskcap_mean_tables(optsWind, riskCapMeanTables, compareRiskCapMeanTbl)
writetable(riskCapMeanTables.terminal_by_state, ...
    fullfile(optsWind.riskCapMeanDir, 'terminal_loh_by_state_RiskCapMean.csv'));
writetable(riskCapMeanTables.allocation, ...
    fullfile(optsWind.riskCapMeanDir, 'terminal_loh_allocation_RiskCapMean.csv'));
writetable(riskCapMeanTables.capacity_usage, ...
    fullfile(optsWind.riskCapMeanDir, 'riskcapmean_capacity_usage.csv'));
writetable(riskCapMeanTables.uncovered_nodes, ...
    fullfile(optsWind.riskCapMeanDir, 'riskcapmean_uncovered_nodes.csv'));
writetable(compareRiskCapMeanTbl, ...
    fullfile(optsWind.riskCapMeanDir, 'terminal_loh_currentA_roadSoft_RiskCapMean_compare.csv'));
writetable(riskCapMeanTables.service_risk_metrics, ...
    fullfile(optsWind.riskCapMeanDir, 'riskcapmean_service_risk_metrics.csv'));
writetable(riskCapMeanTables.cost_components, ...
    fullfile(optsWind.riskCapMeanDir, 'riskcapmean_cost_components.csv'));
writetable(riskCapMeanTables.priority_settings, ...
    fullfile(optsWind.riskCapMeanDir, 'riskcapmean_priority_settings.csv'));
end

function priority = priority_vector_from_settings(prioritySettings, priorityMode, Nj)
rows = prioritySettings(string(prioritySettings.priority_mode) == string(priorityMode), :);
if height(rows) ~= Nj
    error('generate_terminal_loh_wind_mc_preview:BadPrioritySettings', ...
        'Expected %d priority rows for mode %s.', Nj, priorityMode);
end
rows = sortrows(rows, 'node_id');
priority = rows.priority_n(:);
end

function normVal = normalize_riskcap_component(rawVal, validMask, fallbackValue)
normVal = zeros(size(rawVal));
finiteMask = isfinite(rawVal) & validMask;
finiteVals = rawVal(finiteMask);
if isempty(finiteVals) || max(finiteVals) <= 0
    normVal(~finiteMask) = fallbackValue;
    return;
end
scale = max(finiteVals);
normVal(finiteMask) = min(1, max(0, rawVal(finiteMask) ./ scale));
normVal(~finiteMask) = fallbackValue;
end

function [fullCoverFeasible, yFull] = riskcap_full_cover_feasibility(Hnode, Cap, reachable, epsVal)
Ni = numel(Cap);
Nj = numel(Hnode);
yFull = zeros(Ni, Nj);
totalDemand = sum(Hnode(:));
if totalDemand <= epsVal
    fullCoverFeasible = true;
    return;
end

src = 1;
siteOffset = 1;
nodeOffset = 1 + Ni;
sink = 1 + Ni + Nj + 1;
nGraph = sink;
capacity = zeros(nGraph, nGraph);
for i = 1:Ni
    capacity(src, siteOffset + i) = max(0, Cap(i));
end
for i = 1:Ni
    for n = 1:Nj
        if reachable(i, n) && Hnode(n) > epsVal
            capacity(siteOffset + i, nodeOffset + n) = totalDemand;
        end
    end
end
for n = 1:Nj
    capacity(nodeOffset + n, sink) = max(0, Hnode(n));
end

residual = capacity;
flowValue = 0;
tol = max(1e-8, epsVal * max(1, totalDemand));
while true
    prev = zeros(nGraph, 1);
    pathCap = zeros(nGraph, 1);
    queue = zeros(nGraph, 1);
    head = 1;
    tail = 1;
    queue(tail) = src;
    prev(src) = -1;
    pathCap(src) = inf;
    while head <= tail && prev(sink) == 0
        u = queue(head);
        head = head + 1;
        nextNodes = find(residual(u, :) > tol);
        for kk = 1:numel(nextNodes)
            v = nextNodes(kk);
            if prev(v) == 0
                prev(v) = u;
                pathCap(v) = min(pathCap(u), residual(u, v));
                if v == sink
                    break;
                end
                tail = tail + 1;
                queue(tail) = v;
            end
        end
    end
    if prev(sink) == 0
        break;
    end
    aug = pathCap(sink);
    flowValue = flowValue + aug;
    v = sink;
    while v ~= src
        u = prev(v);
        residual(u, v) = residual(u, v) - aug;
        residual(v, u) = residual(v, u) + aug;
        v = u;
    end
end

fullCoverFeasible = flowValue >= totalDemand - tol;
if fullCoverFeasible
    for i = 1:Ni
        for n = 1:Nj
            sNode = siteOffset + i;
            dNode = nodeOffset + n;
            yFull(i, n) = max(0, capacity(sNode, dNode) - residual(sNode, dNode));
        end
    end
    yFull(yFull < tol) = 0;
end
end

function y = roadsoft_allocation_matrix(allocationTbl, Ni, Nj, a, loc, lf)
rows = allocationTbl(allocationTbl.a == a & allocationTbl.loc == loc & allocationTbl.lf == lf, :);
if height(rows) ~= Ni * Nj
    error('generate_terminal_loh_wind_mc_preview:BadRoadSoftMetricRows', ...
        'Expected %d roadSoft allocation rows for a=%d, loc=%d, lf=%d.', Ni * Nj, a, loc, lf);
end
y = zeros(Ni, Nj);
for rr = 1:height(rows)
    y(rows.site_id(rr), rows.node_id(rr)) = rows.allocated_H2_kg(rr);
end
end

function export_road_soft_figures(roadTables, currentATbl, diagTables, windMC, optsWind)
if ~exist(optsWind.roadFigureDir, 'dir')
    mkdir(optsWind.roadFigureDir);
end
plot_road_network_layout(roadTables.network, roadTables.node_positions, roadTables.site_nodes, ...
    windMC.layout, diagTables.by_state_rmax, 5, 4, ...
    fullfile(optsWind.roadFigureDir, 'road_network_layout.png'));
plot_road_edge_close_probability(roadTables.network, roadTables.edge_risk, ...
    roadTables.node_positions, roadTables.site_nodes, 5, 4, ...
    fullfile(optsWind.roadFigureDir, 'road_edge_closeprob_a5_loc4.png'));
plot_site_node_reachability(roadTables.access, roadTables.node_positions, roadTables.site_nodes, 5, 4, ...
    fullfile(optsWind.roadFigureDir, 'site_node_reachability_a5_loc4.png'));
plot_currentA_vs_roadSoft(currentATbl, roadTables.terminal_by_state, 5, 4, ...
    fullfile(optsWind.roadFigureDir, 'terminal_loh_currentA_vs_roadSoft_a5_loc4.png'));
end

function plot_road_network_layout(roadNetwork, nodePos, siteNodes, layout, rmaxTbl, a, loc, outFile)
fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100, 100, 980, 680]);
set_chinese_figure_font(fig);
ax = axes(fig); hold(ax, 'on');
for ee = 1:height(roadNetwork)
    plot(ax, [roadNetwork.from_x_km(ee), roadNetwork.to_x_km(ee)], ...
        [roadNetwork.from_y_km(ee), roadNetwork.to_y_km(ee)], '-', ...
        'Color', [0.55 0.55 0.55], 'HandleVisibility', 'off');
end
center = select_loc_center(layout, loc);
rmaxRow = select_mid_rmax_row(rmaxTbl, a, loc);
scatter(ax, nodePos.x_km, nodePos.y_km, 28, [0.2 0.45 0.8], 'filled', 'DisplayName', '电网节点');
scatter(ax, siteNodes.x_km, siteNodes.y_km, 90, '^', 'filled', 'DisplayName', '氢站');
plot(ax, [-65 65], [0 0], 'k-', 'LineWidth', 1.2, 'DisplayName', '海岸线 y=0');
draw_circle_local(ax, center, rmaxRow.Rmax_km, [0.9 0.35 0.05], ...
    sprintf('中等风圈 %.0f km', rmaxRow.Rmax_km));
scatter(ax, center(1), center(2), 160, 'p', 'filled', ...
    'MarkerFaceColor', [0.85 0.1 0.08], 'MarkerEdgeColor', 'k', ...
    'DisplayName', sprintf('台风中心 强度=%d，位置=%d', a, loc));
text(ax, center(1) + 2, center(2) + 2, {'台风中心'; sprintf('强度=%d，位置=%d', a, loc)}, ...
    'Color', [0.65 0.05 0.05], 'FontWeight', 'bold', 'FontName', 'Microsoft YaHei');
xlabel(ax, '沿海岸方向 x（km）'); ylabel(ax, '向内陆方向 y（km）');
title(ax, '道路网络与代表性台风位置');
axis(ax, 'equal'); grid(ax, 'on');
legend(ax, 'Location', 'northoutside', 'NumColumns', 3);
save_png(fig, outFile);
end

function plot_road_edge_close_probability(roadNetwork, edgeRisk, nodePos, siteNodes, a, loc, outFile)
rows = edgeRisk(edgeRisk.a == a & edgeRisk.loc == loc, :);
if height(rows) ~= height(roadNetwork)
    error('generate_terminal_loh_wind_mc_preview:BadRoadRiskRows', ...
        'Road edge risk row count does not match road network.');
end
fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100, 100, 920, 680]);
set_chinese_figure_font(fig);
ax = axes(fig); hold(ax, 'on'); colormap(ax, turbo(256)); caxis(ax, [0 1]);
for ee = 1:height(roadNetwork)
    color = value_to_color(rows.road_close_probability(ee), [0 1]);
    plot(ax, [roadNetwork.from_x_km(ee), roadNetwork.to_x_km(ee)], ...
        [roadNetwork.from_y_km(ee), roadNetwork.to_y_km(ee)], '-', ...
        'Color', color, 'LineWidth', 2.8, 'HandleVisibility', 'off');
end
scatter(ax, nodePos.x_km, nodePos.y_km, 22, [0.75 0.75 0.75], 'filled', 'DisplayName', '电网节点');
scatter(ax, siteNodes.x_km, siteNodes.y_km, 80, '^', 'filled', 'DisplayName', '氢站');
plot(ax, [-65 65], [0 0], 'k-', 'LineWidth', 1.2, 'DisplayName', '海岸线 y=0');
cb = colorbar(ax); cb.Label.String = '道路关闭概率'; cb.Label.FontName = 'Microsoft YaHei';
xlabel(ax, '沿海岸方向 x（km）'); ylabel(ax, '向内陆方向 y（km）');
title(ax, sprintf('道路边关闭概率（强度=%d，位置=%d）', a, loc));
axis(ax, 'equal'); grid(ax, 'on');
legend(ax, 'Location', 'northoutside', 'NumColumns', 3);
save_png(fig, outFile);
end

function plot_site_node_reachability(accessTbl, nodePos, siteNodes, a, loc, outFile)
rows = accessTbl(accessTbl.a == a & accessTbl.loc == loc, :);
fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100, 100, 980, 780]);
set_chinese_figure_font(fig);
tiledlayout(fig, 2, 2, 'TileSpacing', 'compact');
for s = 1:4
    ax = nexttile; hold(ax, 'on');
    sRows = rows(rows.site_id == s, :);
    scatter(ax, nodePos.x_km, nodePos.y_km, 55, ...
        sRows.reachability_probability, 'filled');
    scatter(ax, siteNodes.x_km(s), siteNodes.y_km(s), 100, '^', 'filled', ...
        'MarkerFaceColor', [0.9 0.2 0.1]);
    colormap(ax, turbo(256)); caxis(ax, [0 1]);
    cb = colorbar(ax); cb.Label.String = '可达概率'; cb.Label.FontName = 'Microsoft YaHei';
    title(ax, sprintf('氢站%d到各节点可达概率（强度=%d，位置=%d）', s, a, loc));
    xlabel(ax, '沿海岸方向 x（km）'); ylabel(ax, '向内陆方向 y（km）'); axis(ax, 'equal'); grid(ax, 'on');
end
save_png(fig, outFile);
end

function plot_currentA_vs_roadSoft(currentATbl, roadTbl, a, loc, outFile)
cRows = currentATbl(currentATbl.a == a & currentATbl.loc == loc, :);
rRows = roadTbl(roadTbl.a == a & roadTbl.loc == loc, :);
if height(cRows) ~= 1 || height(rRows) ~= 1
    error('generate_terminal_loh_wind_mc_preview:MissingCompareRows', ...
        'Expected one compare row for a=%d, loc=%d.', a, loc);
end
currentVals = [cRows.TerminalLOH_site1_currentA_kg, cRows.TerminalLOH_site2_currentA_kg, ...
    cRows.TerminalLOH_site3_currentA_kg, cRows.TerminalLOH_site4_currentA_kg];
roadVals = [rRows.TerminalLOH_site1_roadSoft_kg, rRows.TerminalLOH_site2_roadSoft_kg, ...
    rRows.TerminalLOH_site3_roadSoft_kg, rRows.TerminalLOH_site4_roadSoft_kg];
fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100, 100, 760, 520]);
set_chinese_figure_font(fig);
bar([currentVals(:), roadVals(:)]);
grid on; xticklabels({'氢站1','氢站2','氢站3','氢站4'});
ylabel('终端储氢需求（kg）');
legend({'原始分配', '道路软分配'}, 'Location', 'northoutside');
title(sprintf('原始分配与道路软分配终端储氢需求（强度=%d，位置=%d）', a, loc));
save_png(fig, outFile);
end

function export_riskcap_mean_figures(currentATbl, roadTables, riskCapMeanTables, jointTables, optsWind)
if ~exist(optsWind.riskCapMeanFigureDir, 'dir')
    mkdir(optsWind.riskCapMeanFigureDir);
end
modes = unique(string(riskCapMeanTables.terminal_by_state.priority_mode), 'stable');
for mm = 1:numel(modes)
    mode = modes(mm);
    modeFile = sanitize_file_token(mode);
    plot_currentA_roadSoft_RiskCapMean_compare(currentATbl, roadTables.terminal_by_state, ...
        riskCapMeanTables.terminal_by_state, mode, 5, 4, ...
        fullfile(optsWind.riskCapMeanFigureDir, ...
        sprintf('terminal_loh_currentA_roadSoft_RiskCapMean_%s_a5_loc4.png', modeFile)));
    plot_riskcapmean_capacity_usage(riskCapMeanTables.capacity_usage, mode, 5, 4, ...
        fullfile(optsWind.riskCapMeanFigureDir, ...
        sprintf('riskcapmean_capacity_usage_%s_a5_loc4.png', modeFile)));
end
plot_joint_scenario_total_H(jointTables.scenario_summary, 5, 4, ...
    fullfile(optsWind.riskCapMeanFigureDir, 'joint_scenario_total_H_a5_loc4.png'));
plot_joint_scenario_road_closed_edges(jointTables.scenario_summary, 5, 4, ...
    fullfile(optsWind.riskCapMeanFigureDir, 'joint_scenario_road_closed_edges_a5_loc4.png'));
end

function plot_currentA_roadSoft_RiskCapMean_compare(currentATbl, roadTbl, riskTbl, priorityMode, a, loc, outFile)
cRows = currentATbl(currentATbl.a == a & currentATbl.loc == loc, :);
rRows = roadTbl(roadTbl.a == a & roadTbl.loc == loc, :);
oRows = riskTbl(riskTbl.a == a & riskTbl.loc == loc & ...
    string(riskTbl.priority_mode) == string(priorityMode), :);
if height(cRows) ~= 1 || height(rRows) ~= 1 || height(oRows) ~= 1
    error('generate_terminal_loh_wind_mc_preview:MissingRiskCapMeanFigureRows', ...
        'Expected one currentA, roadSoft, and RiskCap-Mean row for a=%d loc=%d mode=%s.', ...
        a, loc, priorityMode);
end
currentVals = [cRows.TerminalLOH_site1_currentA_kg, cRows.TerminalLOH_site2_currentA_kg, ...
    cRows.TerminalLOH_site3_currentA_kg, cRows.TerminalLOH_site4_currentA_kg];
roadVals = [rRows.TerminalLOH_site1_roadSoft_kg, rRows.TerminalLOH_site2_roadSoft_kg, ...
    rRows.TerminalLOH_site3_roadSoft_kg, rRows.TerminalLOH_site4_roadSoft_kg];
riskVals = [oRows.TerminalLOH_site1_RiskCapMean_kg, oRows.TerminalLOH_site2_RiskCapMean_kg, ...
    oRows.TerminalLOH_site3_RiskCapMean_kg, oRows.TerminalLOH_site4_RiskCapMean_kg];
fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100, 100, 900, 520]);
set_chinese_figure_font(fig);
bar(categorical({'氢站1','氢站2','氢站3','氢站4'}), [currentVals(:), roadVals(:), riskVals(:)]);
ylabel('终端储氢需求（kg）');
title(sprintf('三类分配方法终端储氢需求对比（%s，强度=%d，位置=%d）', priority_mode_cn(priorityMode), a, loc));
legend({'原始分配', '道路软分配', '风险容量均值分配'}, 'Location', 'northoutside', 'NumColumns', 3);
grid on;
save_png(fig, outFile);
end

function plot_riskcapmean_capacity_usage(capacityTbl, priorityMode, a, loc, outFile)
rows = capacityTbl(capacityTbl.a == a & capacityTbl.loc == loc & ...
    string(capacityTbl.priority_mode) == string(priorityMode), :);
if height(rows) ~= 4
    error('generate_terminal_loh_wind_mc_preview:MissingRiskCapMeanCapacityRows', ...
        'Expected four RiskCap-Mean capacity rows for a=%d loc=%d mode=%s.', ...
        a, loc, priorityMode);
end
fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100, 100, 820, 480]);
set_chinese_figure_font(fig);
bar(categorical(compose('氢站%d', rows.site_id)), rows.capacity_utilization_ratio);
hold on;
yline(1, '--r', '容量上限', 'LabelHorizontalAlignment', 'left');
ylim([0, max(1.05, max(rows.capacity_utilization_ratio) * 1.15)]);
ylabel('容量利用率');
title(sprintf('风险容量均值分配容量利用率（%s，强度=%d，位置=%d）', priority_mode_cn(priorityMode), a, loc));
grid on;
save_png(fig, outFile);
end

function plot_joint_scenario_total_H(scenarioTbl, a, loc, outFile)
rows = scenarioTbl(scenarioTbl.a == a & scenarioTbl.loc == loc, :);
if isempty(rows)
    error('generate_terminal_loh_wind_mc_preview:MissingJointScenarioRows', ...
        'Missing joint scenario rows for a=%d loc=%d.', a, loc);
end
fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100, 100, 820, 460]);
set_chinese_figure_font(fig);
bar(rows.scenario_id, rows.total_H_node_kg);
xlabel('联合场景编号');
ylabel('终端储氢需求（kg）');
title(sprintf('联合蒙特卡洛总节点需氢量（强度=%d，位置=%d，场景数=%d）', a, loc, height(rows)));
grid on;
save_png(fig, outFile);
end

function plot_joint_scenario_road_closed_edges(scenarioTbl, a, loc, outFile)
rows = scenarioTbl(scenarioTbl.a == a & scenarioTbl.loc == loc, :);
if isempty(rows)
    error('generate_terminal_loh_wind_mc_preview:MissingJointScenarioRows', ...
        'Missing joint scenario rows for a=%d loc=%d.', a, loc);
end
fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100, 100, 820, 460]);
set_chinese_figure_font(fig);
bar(rows.scenario_id, rows.closed_road_edge_count);
xlabel('联合场景编号');
ylabel('关闭道路边数量');
title(sprintf('联合蒙特卡洛道路关闭边数量（强度=%d，位置=%d，场景数=%d）', a, loc, height(rows)));
grid on;
save_png(fig, outFile);
end

function token = sanitize_file_token(value)
token = regexprep(char(value), '[^A-Za-z0-9_]+', '_');
end

function label = priority_mode_cn(priorityMode)
switch string(priorityMode)
    case "uniform"
        label = '均匀优先级';
    case "key_load_demo"
        label = '关键负荷示例优先级';
    otherwise
        label = char(priorityMode);
end
end

function set_chinese_figure_font(fig)
set(fig, 'DefaultAxesFontName', 'Microsoft YaHei');
set(fig, 'DefaultTextFontName', 'Microsoft YaHei');
end

function draw_circle_local(ax, center, radius, color, labelText)
theta = linspace(0, 2 * pi, 240);
plot(ax, center(1) + radius * cos(theta), center(2) + radius * sin(theta), '--', ...
    'Color', color, 'LineWidth', 1.6, 'DisplayName', labelText);
end

function color = value_to_color(value, cLim)
cmap = turbo(256);
frac = (value - cLim(1)) / max(eps, cLim(2) - cLim(1));
idx = min(256, max(1, round(1 + frac * 255)));
color = cmap(idx, :);
end

function save_png(fig, outFile)
print(fig, outFile, '-dpng', '-r180');
close(fig);
end

function write_wind_mc_preview_readme(optsWind, roadPreview)
txt = [
"终端储氢需求风场蒙特卡洛离线预览"
""
"本模块只做离线诊断，不进入 MSP 优化，不修改 main_msp_h2_near.m，也不改变 node_load 或 critical_load 口径。"
""
"目录结构:"
"- elec_grid/: 电网风场、线路故障、节点停电、节点需氢量与原始分配诊断。"
"- road/: 道路网络、道路边风风险、site-node 可达性与最短路距离诊断。"
"- riskcap_mean/: 风险容量均值分配离线联合场景均值结果表。"
"- figures/elec_grid/: 电网诊断图片。"
"- figures/road/: 道路软分配和可达性图片。"
"- figures/riskcap_mean/: 风险容量均值分配对比、容量利用和联合场景图片。"
"- 根目录: 最终终端储氢需求表、README 和 MAT 工作区。"
""
"Prototype run settings:"
sprintf("- support_hours = %.6g h for kW-to-kg H2 conversion in this offline preview.", optsWind.supportHours)
sprintf("- previewMode = %s; this RiskCap-Mean run uses jointNmc=%d, Nmc=%d, and roadNmc=%d.", optsWind.previewMode, optsWind.jointNmc, optsWind.Nmc, optsWind.roadNmc)
"- joint10 is only a quick prototype validation setting, not a formal paper-grade result."
"- Formal results should test larger joint MC counts such as joint50 or joint200."
""
"Final root-level TerminalLOH files:"
"- terminal_loh_by_state_currentA.csv: final state TerminalLOH using the current A_site_node allocation."
"- terminal_loh_by_state_roadSoft.csv: final state TerminalLOH using road-aware soft allocation."
"- terminal_loh_by_state_currentA_vs_roadSoft.csv: direct comparison of currentA and roadSoft allocations."
"- terminal_loh_allocation_roadSoft.csv: node-to-site roadSoft allocation details."
"- riskcap_mean/terminal_loh_by_state_RiskCapMean.csv: state-level RiskCap-Mean TerminalLOH lookup table."
"- riskcap_mean/terminal_loh_currentA_roadSoft_RiskCapMean_compare.csv: currentA, roadSoft, and RiskCap-Mean comparison table."
"- riskcap_mean/riskcapmean_service_risk_metrics.csv: service-risk quality comparison across currentA, roadSoft, and RiskCap-Mean."
"- riskcap_mean/riskcapmean_cost_components.csv: normalized component costs and final priority-weighted service-risk costs."
"- riskcap_mean/riskcapmean_priority_settings.csv: priority mode and key-node settings."
"- riskcap_mean/joint_scenario_summary.csv and joint_scenario_site_node.csv: joint grid-road MC scenario diagnostics."
""
"Electric-grid scope:"
"- Only lf=7 terminal demand-check states with a>1 are evaluated."
"- Current layout contains one IEEE33 grid placed on the left side of a future two-grid coordinate frame."
"- Coordinates use x along coastline, y inland, coastline y=0, and units of km."
"- loc centers are fixed at x=[-50,-33,-17,0,17,33,50] km, y=0."
"- Rmax uses small/mid/large candidates with probabilities [0.3,0.5,0.2]."
"- Electric-grid line outage is Monte Carlo Bernoulli sampling from a design-wind exponential fragility formula."
"- Current fragility formula: Pf=0 for v<=VN; Pf=exp(0.6931*(v-VN)/VN)-1 for VN<v<2VN; Pf=1 for v>=2VN."
"- VN = 25 m/s. The old failureV0/failureV1/failurePmax piecewise-linear parameters are not used by the current formula."
"- Connectivity loss to source node 1 is used as lost load; no power flow, voltage, capacity, repair, or cross-period persistence is modeled."
""
"Road-aware preview:"
"- stage1_road_edges.csv 只提供道路图拓扑 from_node / to_node。"
"- data/yuanqi/stage1_site_nodes.csv 只提供氢站道路锚点 site_id / grid_node，坐标列不参与当前计算。"
"- 电网节点和道路节点坐标统一来自 windMC.layout.nodes；氢站坐标统一来自 windMC.layout.sites。"
"- site-node 基础服务距离由 stage1_road_edges.csv、stage1_site_nodes.csv 和 windMC.layout.nodes 现场重算完整道路图最短路得到。"
"- 现场重算结果写入 road/site_node_shortest_path_distance.csv，该表是输出结果，不是输入数据。"
"- stage1 道路网络是抽象 stage1 拓扑，不一定是真实详细道路网络。"
"- 联合 MC 每个场景抽取一个 Rmax 类型，并在同一场景中同时用于电网和道路损伤。"
"- 道路关闭概率使用同一设计风速指数脆弱性公式，roadDesignWindVN = 30 m/s。"
"- 道路软分配是指数评分软分配，不是硬指派，也不是灾后路径规划。"
"- road_service_cost = base_site_to_node_road_km / max(reachability_probability,1e-6) + serviceRadiusPenalty * max(0, base_site_to_node_road_km - serviceTimeLimit)."
"- serviceTimeLimit is a distance-scale preview threshold, not strict minutes."
"- score_i,n = capacityWeight_i * reachability_probability_i,n * exp(-road_service_cost_i,n / roadTau)."
"- The current implementation does not solve strict capacity-constrained optimization."
sprintf("- capacityWeight source: %s. If no explicit capacity exists, capacityWeight_i=1.", roadPreview.capacityWeightSource)
""
"RiskCap-Mean preview:"
"- RiskCap-Mean is the current main offline TerminalLOH allocation method for finite terminal typhoon states; it is not connected to MSP forward/backward/cut logic."
"- RiskCap-Mean uses joint scenario means from simultaneous grid and road sampling."
"- RiskCap-Mean uses only the three-term linear service-risk cost; no retired regularization/reference term is active."
"- Default uses Cap_i = reserve_fraction * x_cap_i with reserve_fraction = 0.8."
"- Priority modes are uniform and key_load_demo; key_load_demo assigns higher priority to selected non-top-load key nodes."
"- Cost uses priority-weighted normalized base distance, road unreliability, and normalized travel time. Service radius is diagnostic only."
"- 当前主线只保留风险容量均值分配离线预览。"
""
"Figures:"
"- figures/elec_grid/layout/layout_overview.png: coastline, current IEEE33 grid, H2 sites, loc centers, and future-grid placeholder."
"- figures/elec_grid/storm_states/storm_state_a5_loc4.png: representative storm center with small/mid/large Rmax circles."
"- figures/elec_grid/line_maps/line_failureprob_a5_loc4_rmid.png: electric-grid line failure probability map."
"- figures/elec_grid/node_maps/node_outage_prob_a5_loc4_rmid.png: electric-grid node outage probability map."
"- figures/road/road_network_layout.png: 简化道路网络。"
"- figures/road/road_edge_closeprob_a5_loc4.png: 道路边关闭概率。"
"- figures/road/site_node_reachability_a5_loc4.png: 各氢站到节点可达性。"
"- figures/road/terminal_loh_currentA_vs_roadSoft_a5_loc4.png: 原始分配与道路软分配对比。"
"- figures/riskcap_mean/terminal_loh_currentA_roadSoft_RiskCapMean_uniform_a5_loc4.png: 均匀优先级下三类方法终端储氢需求对比。"
"- figures/riskcap_mean/terminal_loh_currentA_roadSoft_RiskCapMean_key_load_demo_a5_loc4.png: three-method TerminalLOH comparison under key-load-demo priority."
"- figures/riskcap_mean/riskcapmean_capacity_usage_uniform_a5_loc4.png: 均匀优先级下风险容量均值分配容量利用率。"
"- figures/riskcap_mean/riskcapmean_capacity_usage_key_load_demo_a5_loc4.png: RiskCap-Mean capacity utilization under key-load-demo priority."
"- figures/riskcap_mean/joint_scenario_total_H_a5_loc4.png: joint scenario total node hydrogen demand."
"- figures/riskcap_mean/joint_scenario_road_closed_edges_a5_loc4.png: joint scenario road closed edge count."
""
"Interpretation notes:"
"- The future second-grid placeholder is only a coordinate reference and is not used in current calculation."
"- Rmax circles are candidate maximum-wind-radius scales, not damage boundaries. Wind can decay outside the circles and failure is probabilistic."
"- TerminalLOH allocation still remains a pre-deployment reserve preview. It is not disaster-time delivery."
];
fid = fopen(fullfile(optsWind.outputDir, 'terminal_loh_wind_mc_README.txt'), 'w');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', txt);
end

function write_riskcap_mean_readme(optsWind, riskCapMeanPreview)
keyRows = riskCapMeanPreview.prioritySettings( ...
    string(riskCapMeanPreview.prioritySettings.priority_mode) == "key_load_demo" & ...
    logical(riskCapMeanPreview.prioritySettings.is_key_node), :);
if height(keyRows) > 0
    keyNodeText = strtrim(sprintf('%d ', keyRows.node_id));
    keyLoadText = strtrim(sprintf('%.6g ', keyRows.node_load_kw));
else
    keyNodeText = 'none';
    keyLoadText = 'none';
end
w = optsWind.riskCapMeanCostWeights;
txt = [
"RiskCap-Mean offline TerminalLOH preview"
""
"Scope:"
"- RiskCap-Mean is an offline TerminalLOH allocation model for finite terminal typhoon states."
"- It does not enter MSP optimization, forward pass, backward pass, cuts, OOS evaluation, or params.TerminalLOH."
"- The generated TerminalLOH_i^RiskCapMean(k) is a state-level lookup-table candidate for later analysis."
"- 当前主线只保留风险容量均值分配，历史停用 local functions 已清理。"
""
"Joint MC settings:"
sprintf("- support_hours = %.6g h.", optsWind.supportHours)
sprintf("- previewMode = %s.", optsWind.previewMode)
sprintf("- jointNmc = %d.", optsWind.jointNmc)
sprintf("- Nmc = %d.", optsWind.Nmc)
sprintf("- roadNmc = %d.", optsWind.roadNmc)
sprintf("- electric-grid designWindSpeedVN = %.6g m/s.", optsWind.designWindSpeedVN)
sprintf("- roadDesignWindVN = %.6g m/s.", optsWind.roadDesignWindVN)
"- Each joint scenario samples electric-grid line failures and road edge closures under the same typhoon state."
"- State-level Hbar_node, reachability, and average travel time are means over the joint scenarios."
"- joint10 is a quick prototype validation setting, not a formal high-precision paper result."
"- Future runs should test joint50, joint200, or a separately justified larger MC setting."
""
"Capacity mode:"
sprintf("- Default capacity mode: %s.", riskCapMeanPreview.capacityMode)
sprintf("- reserve_fraction = %.6g.", riskCapMeanPreview.reserveFraction)
"- Cap_i = 0.8 * x_cap_i in the default mode."
"- Cap_i is a RiskCap-Mean capacity constraint, not the MSP dynamic inventory state x_i,t."
sprintf("- x_cap_i kg: [%s].", strtrim(sprintf('%.6g ', riskCapMeanPreview.xCap)))
sprintf("- Cap_i kg: [%s].", strtrim(sprintf('%.6g ', riskCapMeanPreview.Cap)))
""
"Priority modes:"
"- uniform: priority_n = 1 for all nodes."
"- key_load_demo: selected non-top-load key nodes use priority_n = 5, other nodes use priority_n = 1."
sprintf("- key_load_demo selected node_id: %s.", keyNodeText)
sprintf("- selected node_load_kw: %s.", keyLoadText)
"- The selected key nodes are recorded in riskcapmean_priority_settings.csv together with selection_reason."
""
"Optimization model:"
"- Decision y_i,n(k): node n average hydrogen demand assigned as TerminalLOH pre-deployment responsibility to site i."
"- Decision u_n(k): node n average demand not covered under capacity and reachability limits."
"- Full-cover-first logic is used before each RiskCap-Mean solve."
"- If full coverage is feasible under capacity and reachability, RiskCap-Mean forces u_n(k)=0 and uses sum_i y_i,n(k) = Hbar_node_n(k)."
"- Only if full coverage is infeasible may the model use sum_i y_i,n(k) + u_n(k) = Hbar_node_n(k) with u_n(k) >= 0."
"- Capacity: sum_n y_i,n(k) <= Cap_i."
"- Unreachable pairs with reachability_i,n(k) == 0 are forced to y_i,n(k) = 0."
"- u_n is a RiskCap-Mean offline diagnostic uncovered amount. It is not the MSP terminal shortage variable or penalty."
""
"Cost function:"
"- RiskCap-Mean uses only the three-term linear service-risk cost; no retired regularization/reference term is active."
"- RiskCap-Mean does not use road_service_cost as the main objective cost."
"- C_i,n(k) = priority_n * [alpha*norm_base_distance_i,n + beta*road_unreliability_i,n + gamma*norm_travel_time_i,n]."
sprintf("- alpha baseDistance = %.6g.", w.baseDistance)
sprintf("- beta roadUnreliability = %.6g.", w.roadUnreliability)
sprintf("- gamma travelTime = %.6g.", w.travelTime)
"- road_unreliability_i,n(k) = 1 - reachability_probability_i,n(k)."
"- service_radius_violation_diagnostic is written for diagnostics only and does not enter the RiskCap-Mean main objective."
"- This avoids double-counting base distance and service-radius excess in the main objective."
""
"Baselines:"
"- currentA uses the joint-MC Hbar_node and fixed A_site_node allocation."
"- roadSoft uses joint-MC reachability, average travel time, and base distance as a road-aware soft allocation baseline."
"- roadSoft is a comparison baseline and is not a RiskCap-Mean reference."
""
"Outputs:"
"- terminal_loh_by_state_RiskCapMean.csv: state-level RiskCap-Mean TerminalLOH lookup table."
"- terminal_loh_allocation_RiskCapMean.csv: state-site-node allocation details."
"- riskcapmean_capacity_usage.csv: state-site capacity use and binding flags."
"- riskcapmean_uncovered_nodes.csv: only node rows with uncovered_H2_kg > 0; if none, the file keeps headers and has zero rows."
"- terminal_loh_currentA_roadSoft_RiskCapMean_compare.csv: currentA, roadSoft, and RiskCap-Mean comparison."
"- riskcapmean_service_risk_metrics.csv: service-risk quality metrics for currentA, roadSoft, and RiskCap-Mean."
"- riskcapmean_cost_components.csv: normalized cost components and service risk cost."
"- riskcapmean_priority_settings.csv: priority settings and key-node selection."
"- joint_scenario_summary.csv: one row per state and joint scenario."
"- joint_scenario_site_node.csv: one row per state, scenario, site, and node."
""
"Figures:"
"- figures/riskcap_mean/terminal_loh_currentA_roadSoft_RiskCapMean_uniform_a5_loc4.png."
"- figures/riskcap_mean/terminal_loh_currentA_roadSoft_RiskCapMean_key_load_demo_a5_loc4.png."
"- figures/riskcap_mean/riskcapmean_capacity_usage_uniform_a5_loc4.png."
"- figures/riskcap_mean/riskcapmean_capacity_usage_key_load_demo_a5_loc4.png."
"- figures/riskcap_mean/joint_scenario_total_H_a5_loc4.png."
"- figures/riskcap_mean/joint_scenario_road_closed_edges_a5_loc4.png."
""
"Interpretation:"
"- RiskCap-Mean is a state-level pre-deployment lookup method. It does not solve separate final TerminalLOH for each scenario and then average decisions."
"- Current joint10 output is a prototype sanity check only."
"- Suggested next steps: joint50 / joint200 sensitivity, and a separate RiskCap-Backup diagnostic variant if backup coverage behavior needs to be studied."
sprintf("- Objective: %s.", char(riskCapMeanPreview.objective))
sprintf("- Cost definition: %s.", char(riskCapMeanPreview.costDefinition))
sprintf("- Full-cover rule: %s.", char(riskCapMeanPreview.fullCoverRule))
];
fid = fopen(fullfile(optsWind.riskCapMeanDir, 'RiskCapMean_README.txt'), 'w');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', txt);
end
