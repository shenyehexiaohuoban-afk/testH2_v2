function diag = write_lookahead_W3_B1_diagnostics_h2(siteNodeTbl, summaryTbl, config)
%WRITE_LOOKAHEAD_W3_B1_DIAGNOSTICS_H2 Write B1 state-level diagnostics.

stateTbl = unique(summaryTbl(:, {'a', 'loc', 'lf'}), 'rows', 'stable');
stateTbl = sortrows(stateTbl, {'a', 'loc', 'lf'});

dRows = {};
rRows = {};
cRows = {};

for ss = 1:height(stateTbl)
    a = stateTbl.a(ss);
    loc = stateTbl.loc(ss);
    lf = stateTbl.lf(ss);
    sRows = summaryTbl(summaryTbl.a == a & summaryTbl.loc == loc & ...
        summaryTbl.lf == lf, :);
    snRows = siteNodeTbl(siteNodeTbl.a == a & siteNodeTbl.loc == loc & ...
        siteNodeTbl.lf == lf, :);
    Dtot = sRows.D_total;
    highDemandCount = sum(Dtot > mean(Dtot) + 2 * std(Dtot));
    dRows(end + 1, :) = {a, loc, lf, height(sRows), min(Dtot), ...
        mean(Dtot), std(Dtot), percentile_b1(Dtot, 50), ...
        percentile_b1(Dtot, 90), percentile_b1(Dtot, 95), max(Dtot), ...
        max(Dtot) / max(mean(Dtot), eps), highDemandCount}; %#ok<AGROW>

    Avals = unique(snRows.reachable);
    Aok = all(ismember(double(Avals), [0; 1]));
    rRows(end + 1, :) = {a, loc, lf, height(sRows), ...
        min(sRows.reachable_pair_share), mean(sRows.reachable_pair_share), ...
        max(sRows.reachable_pair_share), Aok, ...
        char(strjoin(string(Avals(:).'), '|'))}; %#ok<AGROW>

    reachMask = snRows.reachable == 1;
    reachCosts = snRows.scenario_service_cost(reachMask & ...
        isfinite(snRows.scenario_service_cost));
    reachCostsBeforeFix = snRows.scenario_service_cost_before_fix( ...
        reachMask & isfinite(snRows.scenario_service_cost_before_fix));
    if isempty(reachCosts)
        cMean = NaN;
        cP90 = NaN;
        cMax = NaN;
    else
        cMean = mean(reachCosts);
        cP90 = percentile_b1(reachCosts, 90);
        cMax = max(reachCosts);
    end
    if isempty(reachCostsBeforeFix)
        cMeanBeforeFix = NaN;
        cMaxBeforeFix = NaN;
    else
        cMeanBeforeFix = mean(reachCostsBeforeFix);
        cMaxBeforeFix = max(reachCostsBeforeFix);
    end
    unreachableInfCount = sum(snRows.reachable == 0 & ...
        isinf(snRows.scenario_service_cost));
    cRows(end + 1, :) = {a, loc, lf, height(sRows), cMean, cP90, cMax, ...
        unreachableInfCount, sum(sRows.slow_road_count), ...
        'current_road_state_shortest_path_cost', ...
        'fixed: previous B1 used baseCost+dist, now scenario_service_cost=dist', ...
        cMeanBeforeFix, cMean, cMaxBeforeFix, cMax}; %#ok<AGROW>
end

dTbl = cell2table(dRows, 'VariableNames', ...
    {'a', 'loc', 'lf', 'R', 'D_total_min', 'D_total_mean', ...
    'D_total_std', 'D_total_p50', 'D_total_p90', 'D_total_p95', ...
    'D_total_max', 'D_total_max_to_mean', 'high_demand_scenario_count'});
rTbl = cell2table(rRows, 'VariableNames', ...
    {'a', 'loc', 'lf', 'R', 'reachable_pair_share_min', ...
    'reachable_pair_share_mean', 'reachable_pair_share_max', ...
    'A_binary_ok', 'A_unique_values'});
cTbl = cell2table(cRows, 'VariableNames', ...
    {'a', 'loc', 'lf', 'R', 'C_reachable_mean', 'C_reachable_p90', ...
    'C_reachable_max', 'unreachable_C_inf_count', 'slow_road_count_total', ...
    'C_definition', 'C_repeated_baseCost_check', ...
    'C_reachable_mean_before_fix', 'C_reachable_mean_after_fix', ...
    'C_reachable_max_before_fix', 'C_reachable_max_after_fix'});

writetable(dTbl, fullfile(config.outputDir, ...
    'lookahead_D_total_distribution_summary.csv'));
writetable(rTbl, fullfile(config.outputDir, ...
    'lookahead_reachability_summary.csv'));
writetable(cTbl, fullfile(config.outputDir, ...
    'lookahead_cost_summary.csv'));

slowReachable = any(summaryTbl.slow_road_count > 0 & ...
    summaryTbl.reachable_pair_count > 0);
diag = struct();
diag.D_total_distribution = dTbl;
diag.reachability = rTbl;
diag.cost = cTbl;
diag.A_binary_ok_all = all(rTbl.A_binary_ok);
diag.has_slow_reachable_samples = slowReachable;
diag.has_unreachable_samples = any(summaryTbl.unreachable_pair_count > 0);
diag.max_D_total_max_to_mean = max(dTbl.D_total_max_to_mean);
diag.state_count = height(stateTbl);
diag.site_node_rows = height(siteNodeTbl);
diag.summary_rows = height(summaryTbl);
diag.reachable_one_inf_cost_count = sum(siteNodeTbl.reachable == 1 & ...
    isinf(siteNodeTbl.scenario_service_cost));
diag.unreachable_cost_used_in_reachable_stats = false;
afterCosts = siteNodeTbl.scenario_service_cost(siteNodeTbl.reachable == 1 & ...
    isfinite(siteNodeTbl.scenario_service_cost));
beforeCosts = siteNodeTbl.scenario_service_cost_before_fix( ...
    siteNodeTbl.reachable == 1 & ...
    isfinite(siteNodeTbl.scenario_service_cost_before_fix));
diag.C_reachable_mean_after_fix_overall = mean(afterCosts);
diag.C_reachable_mean_before_fix_overall = mean(beforeCosts);
diag.C_reachable_max_after_fix_overall = max(afterCosts);
diag.C_reachable_max_before_fix_overall = max(beforeCosts);
end

function val = percentile_b1(x, pct)
x = sort(x(:));
if isempty(x)
    val = NaN;
    return;
end
idx = max(1, min(numel(x), ceil(pct / 100 * numel(x))));
val = x(idx);
end
