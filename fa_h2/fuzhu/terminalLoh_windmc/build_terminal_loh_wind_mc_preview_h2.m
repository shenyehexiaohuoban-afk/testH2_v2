function [windMC, diagTables] = build_terminal_loh_wind_mc_preview_h2(params, NearStageInput, optsWind)
%BUILD_TERMINAL_LOH_WIND_MC_PREVIEW_H2 Offline wind/failure TerminalLOH preview.

required = {'Nmc', 'seed', 'windDecayB', 'designWindSpeedVN'};
for ii = 1:numel(required)
    if ~isfield(optsWind, required{ii})
        error('build_terminal_loh_wind_mc_preview_h2:MissingOption', ...
            'optsWind.%s is required.', required{ii});
    end
end

rng(optsWind.seed, 'twister');
layout = build_h2_spatial_layout_preview(NearStageInput);

PNodeLoadKw = params.P_node_load_kw(:);
A = params.A_site_node;
if numel(PNodeLoadKw) ~= params.Nj
    error('build_terminal_loh_wind_mc_preview_h2:BadNodeLoadLength', ...
        'params.P_node_load_kw must have params.Nj entries.');
end

vmaxByA = nan(max(params.Na, 6), 1);
vmaxByA(2:6) = [20.8; 28.55; 37.05; 46.20; 55.50];
rmaxByA = nan(max(params.Na, 6), 3);
rmaxByA(2, :) = [15, 25, 35];
rmaxByA(3, :) = [18, 30, 42];
rmaxByA(4, :) = [20, 35, 50];
rmaxByA(5, :) = [25, 40, 60];
rmaxByA(6, :) = [30, 50, 75];
rmaxProb = [0.3, 0.5, 0.2];
rmaxType = ["small", "mid", "large"];
lfDemand = params.Nc - 1;

TerminalLOHWind = zeros(params.Ni, params.K);
byStateRows = {};
byRmaxRows = {};
lineRows = {};
nodeRows = {};

for a = 2:params.Na
    if a > numel(vmaxByA) || isnan(vmaxByA(a))
        error('build_terminal_loh_wind_mc_preview_h2:MissingIntensityMap', ...
            'No Vmax/Rmax mapping is defined for intensity a=%d.', a);
    end
    for loc = 1:height(layout.locs)
        k = params.state_id(a, loc, lfDemand);
        Vmax = vmaxByA(a);
        centerX = layout.locs.center_x_km(loc);
        centerY = layout.locs.center_y_km(loc);

        weightedTerminal = zeros(params.Ni, 1);
        weightedLostLoad = 0;
        weightedFailedLines = 0;
        weightedOutageNodes = 0;

        for ww = 1:numel(rmaxProb)
            Rmax = rmaxByA(a, ww);
            dx = layout.lines.line_mid_x_km - centerX;
            dy = layout.lines.line_mid_y_km - centerY;
            distKm = hypot(dx, dy);
            windSpeed = compute_wind_speed_radial_h2(distKm, Vmax, Rmax, optsWind.windDecayB);
            pFail = compute_line_failure_prob_h2(windSpeed, optsWind.designWindSpeedVN);

            sim = simulate_grid_outage_mc_h2( ...
                layout.lines, pFail, PNodeLoadKw, A, params, optsWind.Nmc);

            terminalMean = sim.mean_terminal_loh_by_site_kg;
            terminalTotalSamples = sim.terminal_loh_total_samples_kg;
            weightedTerminal = weightedTerminal + rmaxProb(ww) * terminalMean;
            weightedLostLoad = weightedLostLoad + rmaxProb(ww) * sim.expected_lost_load_kw;
            weightedFailedLines = weightedFailedLines + rmaxProb(ww) * sim.expected_failed_lines;
            weightedOutageNodes = weightedOutageNodes + rmaxProb(ww) * sim.expected_outage_nodes;

            byRmaxRows(end + 1, :) = {a, loc, lfDemand, rmaxType(ww), Rmax, ...
                rmaxProb(ww), Vmax, terminalMean(1), terminalMean(2), ...
                terminalMean(3), terminalMean(4), sum(terminalMean), ...
                empirical_percentile(terminalTotalSamples, 75), ...
                empirical_percentile(terminalTotalSamples, 90), ...
                sim.expected_lost_load_kw, sim.expected_failed_lines, ...
                sim.expected_outage_nodes}; %#ok<AGROW>

            for ll = 1:height(layout.lines)
                lineRows(end + 1, :) = {a, loc, lfDemand, rmaxType(ww), ...
                    layout.lines.line_id(ll), layout.lines.from_node(ll), ...
                    layout.lines.to_node(ll), layout.lines.line_mid_x_km(ll), ...
                    layout.lines.line_mid_y_km(ll), distKm(ll), windSpeed(ll), ...
                    pFail(ll)}; %#ok<AGROW>
            end

            for nn = 1:height(layout.nodes)
                nodeRows(end + 1, :) = {a, loc, lfDemand, rmaxType(ww), ...
                    layout.nodes.node_id(nn), layout.nodes.x_km(nn), ...
                    layout.nodes.y_km(nn), PNodeLoadKw(nn), ...
                    sim.outage_probability(nn), ...
                    sim.expected_lost_load_by_node_kw(nn), ...
                    sim.expected_H_lost_by_node_kg(nn)}; %#ok<AGROW>
            end
        end

        TerminalLOHWind(:, k) = weightedTerminal;
        byStateRows(end + 1, :) = {a, loc, lfDemand, Vmax, ...
            weightedTerminal(1), weightedTerminal(2), weightedTerminal(3), ...
            weightedTerminal(4), sum(weightedTerminal), weightedLostLoad, ...
            weightedFailedLines, weightedOutageNodes, optsWind.Nmc, ...
            "small/mid/large Rmax weighted by [0.3,0.5,0.2]"}; %#ok<AGROW>
    end
end

diagTables = struct();
diagTables.by_state = cell2table(byStateRows, 'VariableNames', ...
    {'a', 'loc', 'lf', 'Vmax_mps', 'TerminalLOH_site1_kg', ...
    'TerminalLOH_site2_kg', 'TerminalLOH_site3_kg', ...
    'TerminalLOH_site4_kg', 'TerminalLOH_total_kg', ...
    'expected_lost_load_kw', 'expected_failed_lines', ...
    'expected_outage_nodes', 'Nmc', 'Rmax_weighted_mode_description'});
diagTables.by_state_rmax = cell2table(byRmaxRows, 'VariableNames', ...
    {'a', 'loc', 'lf', 'Rmax_type', 'Rmax_km', 'Rmax_prob', ...
    'Vmax_mps', 'TerminalLOH_site1_mean_kg', ...
    'TerminalLOH_site2_mean_kg', 'TerminalLOH_site3_mean_kg', ...
    'TerminalLOH_site4_mean_kg', 'TerminalLOH_total_mean_kg', ...
    'TerminalLOH_total_p75_kg', 'TerminalLOH_total_p90_kg', ...
    'expected_lost_load_kw', 'expected_failed_lines', ...
    'expected_outage_nodes'});
diagTables.line_failure = cell2table(lineRows, 'VariableNames', ...
    {'a', 'loc', 'lf', 'Rmax_type', 'line_id', 'from_node', 'to_node', ...
    'line_mid_x_km', 'line_mid_y_km', 'distance_to_typhoon_center_km', ...
    'wind_speed_mps', 'failure_probability'});
diagTables.node_outage = cell2table(nodeRows, 'VariableNames', ...
    {'a', 'loc', 'lf', 'Rmax_type', 'node_id', 'node_x_km', 'node_y_km', ...
    'P_node_load_kw', 'outage_probability', 'expected_lost_load_kw', ...
    'expected_H_lost_kg'});
diagTables.layout = layout.combined;

windMC = struct();
windMC.TerminalLOH = TerminalLOHWind;
windMC.layout = layout;
windMC.Nmc = optsWind.Nmc;
windMC.seed = optsWind.seed;
windMC.Vmax_by_a = vmaxByA;
windMC.Rmax_by_a = rmaxByA;
windMC.Rmax_prob = rmaxProb;
windMC.Rmax_type = rmaxType;
windMC.windDecayB = optsWind.windDecayB;
windMC.fragility_formula = "design_wind_exp";
windMC.designWindSpeedVN_mps = optsWind.designWindSpeedVN;
end

function val = empirical_percentile(x, pct)
x = sort(x(:));
if isempty(x)
    val = NaN;
    return;
end
idx = max(1, min(numel(x), ceil(pct / 100 * numel(x))));
val = x(idx);
end
