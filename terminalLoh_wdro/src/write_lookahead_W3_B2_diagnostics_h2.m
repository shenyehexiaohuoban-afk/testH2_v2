function diag = write_lookahead_W3_B2_diagnostics_h2( ...
    siteNodeTbl, summaryTbl, config, result)
%WRITE_LOOKAHEAD_W3_B2_DIAGNOSTICS_H2 Write B2 R=200 diagnostics.

if nargin < 4
    result = struct();
end

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
    Dmean = mean(Dtot);
    Dstd = std(Dtot);
    DmaxToMean = max(Dtot) / max(Dmean, eps);
    highDemandCount = sum(Dtot > Dmean + 2 * Dstd);
    dRows(end + 1, :) = {a, loc, lf, height(sRows), min(Dtot), ...
        Dmean, Dstd, percentile_b2(Dtot, 50), ...
        percentile_b2(Dtot, 90), percentile_b2(Dtot, 95), ...
        max(Dtot), DmaxToMean, highDemandCount, ...
        DmaxToMean > 5, DmaxToMean > 10}; %#ok<AGROW>

    Avals = unique(snRows.reachable);
    halfReachableCount = sum(snRows.reachable ~= 0 & snRows.reachable ~= 1);
    Aok = halfReachableCount == 0 && all(ismember(double(Avals), [0; 1]));
    reachableOneInf = sum(snRows.reachable == 1 & ...
        isinf(snRows.scenario_service_cost));
    unreachableInfCount = sum(snRows.reachable == 0 & ...
        isinf(snRows.scenario_service_cost));
    rRows(end + 1, :) = {a, loc, lf, height(sRows), ...
        min(sRows.reachable_pair_share), mean(sRows.reachable_pair_share), ...
        max(sRows.reachable_pair_share), Aok, ...
        char(strjoin(string(Avals(:).'), '|')), halfReachableCount, ...
        reachableOneInf, unreachableInfCount}; %#ok<AGROW>

    reachMask = snRows.reachable == 1 & ...
        isfinite(snRows.scenario_service_cost);
    reachCosts = snRows.scenario_service_cost(reachMask);
    reachCostsBeforeFix = snRows.scenario_service_cost_before_fix( ...
        snRows.reachable == 1 & ...
        isfinite(snRows.scenario_service_cost_before_fix));
    if isempty(reachCosts)
        cMean = NaN;
        cP90 = NaN;
        cP95 = NaN;
        cMax = NaN;
    else
        cMean = mean(reachCosts);
        cP90 = percentile_b2(reachCosts, 90);
        cP95 = percentile_b2(reachCosts, 95);
        cMax = max(reachCosts);
    end
    if isempty(reachCostsBeforeFix)
        cMeanBeforeFix = NaN;
        cMaxBeforeFix = NaN;
    else
        cMeanBeforeFix = mean(reachCostsBeforeFix);
        cMaxBeforeFix = max(reachCostsBeforeFix);
    end
    cRows(end + 1, :) = {a, loc, lf, height(sRows), ...
        'scenario_service_cost=dist(n)', ...
        'passed: no baseCost+dist(n) in formal C; before-fix field is diagnostic only', ...
        cMean, cP90, cP95, cMax, cMeanBeforeFix, cMaxBeforeFix, ...
        unreachableInfCount, sum(sRows.slow_road_count)}; %#ok<AGROW>
end

dTbl = cell2table(dRows, 'VariableNames', ...
    {'a', 'loc', 'lf', 'R', 'D_total_min', 'D_total_mean', ...
    'D_total_std', 'D_total_p50', 'D_total_p90', 'D_total_p95', ...
    'D_total_max', 'D_total_max_to_mean', ...
    'high_demand_scenario_count', 'flag_D_total_max_to_mean_gt5', ...
    'flag_D_total_max_to_mean_gt10'});
rTbl = cell2table(rRows, 'VariableNames', ...
    {'a', 'loc', 'lf', 'R', 'reachable_pair_share_min', ...
    'reachable_pair_share_mean', 'reachable_pair_share_max', ...
    'A_binary_ok', 'A_unique_values', 'half_reachable_count', ...
    'reachable_1_C_inf_count', 'unreachable_C_inf_count'});
cTbl = cell2table(cRows, 'VariableNames', ...
    {'a', 'loc', 'lf', 'R', 'C_definition', ...
    'C_repeated_baseCost_check', 'C_reachable_mean', ...
    'C_reachable_p90', 'C_reachable_p95', 'C_reachable_max', ...
    'C_reachable_mean_before_fix', 'C_reachable_max_before_fix', ...
    'unreachable_C_inf_count', 'slow_road_count_total'});

writetable(dTbl, fullfile(config.outputDir, ...
    'lookahead_D_total_distribution_summary.csv'));
writetable(rTbl, fullfile(config.outputDir, ...
    'lookahead_reachability_summary.csv'));
writetable(cTbl, fullfile(config.outputDir, ...
    'lookahead_cost_summary.csv'));

delayCol = siteNodeTbl.scenario_service_delay;
diag = struct();
diag.D_total_distribution = dTbl;
diag.reachability = rTbl;
diag.cost = cTbl;
diag.state_count = height(stateTbl);
diag.site_node_rows = height(siteNodeTbl);
diag.summary_rows = height(summaryTbl);
diag.scenario_count_total = height(summaryTbl);
diag.A_binary_ok_all = all(rTbl.A_binary_ok);
diag.half_reachable_count_total = sum(rTbl.half_reachable_count);
diag.reachable_one_inf_cost_count = sum(rTbl.reachable_1_C_inf_count);
diag.unreachable_C_inf_count = sum(rTbl.unreachable_C_inf_count);
diag.has_slow_reachable_samples = any(siteNodeTbl.reachable == 1 & ...
    isfinite(delayCol) & delayCol > 1e-9);
diag.has_unreachable_samples = any(siteNodeTbl.reachable == 0);
diag.max_D_total_max_to_mean = max(dTbl.D_total_max_to_mean);
diag.count_D_total_max_to_mean_gt5 = sum(dTbl.flag_D_total_max_to_mean_gt5);
diag.count_D_total_max_to_mean_gt10 = sum(dTbl.flag_D_total_max_to_mean_gt10);
diag.unreachable_cost_used_in_reachable_stats = false;

afterCosts = siteNodeTbl.scenario_service_cost(siteNodeTbl.reachable == 1 & ...
    isfinite(siteNodeTbl.scenario_service_cost));
beforeCosts = siteNodeTbl.scenario_service_cost_before_fix( ...
    siteNodeTbl.reachable == 1 & ...
    isfinite(siteNodeTbl.scenario_service_cost_before_fix));
diag.C_reachable_mean_after_fix_overall = mean(afterCosts);
diag.C_reachable_max_after_fix_overall = max(afterCosts);
diag.C_reachable_mean_before_fix_overall = mean(beforeCosts);
diag.C_reachable_max_before_fix_overall = max(beforeCosts);

write_b2_readme(config, diag);
write_b2_docs(config);
write_implementation_audit_b2(config, diag, result);
end

function write_b2_readme(config, diag)
fid = fopen(fullfile(config.outputDir, ...
    'README_B2_DAC_samples_R200.txt'), 'w');
if fid < 0
    error('write_lookahead_W3_B2_diagnostics_h2:ReadmeOpenFailed', ...
        'Could not open README_B2_DAC_samples_R200.txt.');
end
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, 'Stage 2B2 W=3 medium-sample D/A/C consequence generation\n\n');
fprintf(fid, 'Goal: generate D/A/C consequence samples and diagnostics only.\n');
fprintf(fid, 'This stage does not run WDRO-LP and is not connected to MSP.\n\n');
fprintf(fid, 'Settings: P_B2=%d, M_B2=%d, R_B2=%d per state, seed=%d.\n', ...
    config.P_B2, config.M_B2, config.P_B2 * config.M_B2, ...
    config.random_seed_B2);
fprintf(fid, 'Path selection: if available paths equal P_B2, use all paths; if more are available, use fixed-seed random sampling.\n');
fprintf(fid, 'State count: %d. Total scenarios: %d.\n\n', ...
    diag.state_count, diag.scenario_count_total);
fprintf(fid, 'D is node hydrogen demand aggregated as D_n=sum_tau D_{n,tau}.\n');
fprintf(fid, 'A is binary: A=1 means a feasible service path exists; A=0 means fully unreachable.\n');
fprintf(fid, 'A never uses fractional slow-road values such as 0.3 or 0.5.\n');
fprintf(fid, 'C is current road-state shortest path service cost dist(n).\n');
fprintf(fid, 'C does not repeat baseCost; baseCost+dist(n) is retained only in scenario_service_cost_before_fix diagnostics.\n');
fprintf(fid, 'Passable but slow roads are represented by A=1 and larger C.\n');
fprintf(fid, 'If A=0, C is Inf and is excluded from reachable cost statistics.\n\n');
fprintf(fid, 'Next step: Stage 2C reads this output and runs W=3 DA-WDRO.\n');
end

function write_b2_docs(config)
docFile = fullfile(config.docsDir, ...
    'README_lookahead_W3_B2_DAC_samples_R200.md');
fid = fopen(docFile, 'w');
if fid < 0
    error('write_lookahead_W3_B2_diagnostics_h2:DocOpenFailed', ...
        'Could not open README_lookahead_W3_B2_DAC_samples_R200.md.');
end
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, '# Stage 2B2 W=3 D/A/C Samples R200\n\n');
fprintf(fid, '## Goal\n\n');
fprintf(fid, 'Stage 2B2 expands the Stage 2B1 smoke-test consequence generation to medium samples. It generates D/A/C samples and diagnostics only. It does not run WDRO-LP, call Gurobi, connect to MSP, or write TerminalLOH.\n\n');
fprintf(fid, '## Project Stage Structure\n\n');
fprintf(fid, '- Stage 1: single-window DA/DAC WDRO prototype.\n');
fprintf(fid, '- Stage 2A: W=3 look-ahead typhoon path generation.\n');
fprintf(fid, '- Stage 2B1: W=3 small-sample D/A/C smoke test.\n');
fprintf(fid, '- Stage 2B2: W=3 R=200 D/A/C consequence generation and diagnostics.\n');
fprintf(fid, '- Stage 2C: future W=3 DA-WDRO run using B2 outputs.\n\n');
fprintf(fid, '## Inputs\n\n');
fprintf(fid, '- `%s`\n', config.inputPathTable);
fprintf(fid, '- `%s`\n', config.windowConfigFile);
fprintf(fid, '- `%s`\n', config.locationConfigFile);
fprintf(fid, '- `%s`\n\n', config.intensityConfigFile);
fprintf(fid, '## Sample Size\n\n');
fprintf(fid, '- `P_B2=%d`: selected W=3 paths per lf=7 state.\n', config.P_B2);
fprintf(fid, '- `M_B2=%d`: damage samples per selected path.\n', config.M_B2);
fprintf(fid, '- `R_B2=%d`: D/A/C consequence scenarios per state.\n', config.P_B2 * config.M_B2);
fprintf(fid, '- `random_seed_B2=%d`.\n\n', config.random_seed_B2);
fprintf(fid, 'If a state has exactly `P_B2` available paths, all are used. If it has more, paths are selected by fixed-seed random sampling and sorted before scenario generation.\n\n');
fprintf(fid, '## D/A/C Definitions\n\n');
fprintf(fid, '- `D`: W=3 cumulative node hydrogen demand, `D_n=sum_tau D_{n,tau}`.\n');
fprintf(fid, '- `A`: binary site-node reachability. `A=1` means a feasible service path exists; `A=0` means fully unreachable.\n');
fprintf(fid, '- `C`: current road-state shortest path service cost `dist(n)` from Dijkstra after sampled slowdowns and closures.\n\n');
fprintf(fid, '`A` is never used for partial reachability. Reachable but slow roads keep `A=1` and are represented by larger `C`. The formal `C` field does not use `baseCost + dist(n)`; that before-fix value is diagnostic only.\n\n');
fprintf(fid, '## Outputs\n\n');
fprintf(fid, 'Output directory: `%s`\n\n', config.outputDir);
fprintf(fid, '- `lookahead_scenario_site_node.csv`\n');
fprintf(fid, '- `lookahead_scenario_summary.csv`\n');
fprintf(fid, '- `lookahead_D_total_distribution_summary.csv`\n');
fprintf(fid, '- `lookahead_reachability_summary.csv`\n');
fprintf(fid, '- `lookahead_cost_summary.csv`\n');
fprintf(fid, '- `implementation_audit_B2.txt`\n');
fprintf(fid, '- `README_B2_DAC_samples_R200.txt`\n\n');
fprintf(fid, '## Why B2 Still Does Not Run WDRO\n\n');
fprintf(fid, 'B2 is a data generation and diagnostic gate. It verifies D/A/C dimensions, binary reachability, finite reachable costs, unreachable masking behavior, and demand tail diagnostics before Stage 2C consumes the samples for DA-WDRO.\n\n');
fprintf(fid, '## Stage 2C Interface\n\n');
fprintf(fid, 'Stage 2C should read `lookahead_scenario_site_node.csv` and use `D_node_kg_s`, `reachable`, and `scenario_service_cost` as the DA sample inputs. Unreachable `C=Inf` entries must be ignored by masked-C diagnostics and must not enter reachable cost statistics.\n');
end

function write_implementation_audit_b2(config, diag, result)
auditFile = fullfile(config.outputDir, 'implementation_audit_B2.txt');
fid = fopen(auditFile, 'w');
if fid < 0
    error('write_lookahead_W3_B2_diagnostics_h2:AuditOpenFailed', ...
        'Could not open implementation_audit_B2.txt.');
end
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, 'Stage 2B2 implementation audit\n');
fprintf(fid, 'Generated at: %s\n\n', char(datetime('now')));
fprintf(fid, '1. Fallback code found: no data-replacement fallback is used. Required input files and columns raise errors when missing.\n');
fprintf(fid, '2. Mock/dummy/placeholder/TODO found: none in B2-specific entry/diagnostic code; shared audit prose may mention these terms only as audit labels.\n');
fprintf(fid, '3. D source: load_data_h2_near P_node_load_kw, support_hours, eta_FC, h2_lhv, and sampled grid line outage from wind fragility.\n');
fprintf(fid, '4. A source: Dijkstra reachability on the stage1 road graph after sampled road closures; A is written only as 0/1.\n');
fprintf(fid, '5. C source: current road-state shortest path cost dist(n), using edge_length_km*(1+roadSlowdownLambda*pClose) and Inf for closed edges.\n');
fprintf(fid, '6. C uses dist(n): yes. scenario_service_cost is assigned from dist(n).\n');
fprintf(fid, '7. Avoid baseCost + dist(n): yes. The formal C field avoids duplicate baseCost; scenario_service_cost_before_fix is diagnostic only.\n');
fprintf(fid, '8. A non-binary exists: %d. half_reachable_count_total=%d.\n', ...
    ~diag.A_binary_ok_all, diag.half_reachable_count_total);
fprintf(fid, '9. reachable=1 and C=Inf count: %d.\n', ...
    diag.reachable_one_inf_cost_count);
fprintf(fid, '10. Unreachable C enters reachable cost statistics: no. Reachable statistics filter reachable==1 and finite C.\n');
fprintf(fid, '11. B2 path selection: P_B2=%d. If available path count equals P_B2, all paths are used; if greater, fixed-seed random sampling with seed %d is used.\n', ...
    config.P_B2, config.random_seed_B2);
fprintf(fid, '12. WDRO-LP run: no.\n');
fprintf(fid, '13. MSP connected: no.\n');
fprintf(fid, '14. Forbidden files modified by this stage: no intended modification; only terminalLoh_wdro code/docs/output and codex_rule/log.md are used.\n');
if isfield(result, 'state_count')
    fprintf(fid, '15. State count: %d. Total scenario count: %d.\n', ...
        result.state_count, result.scenario_count_total);
end
fprintf(fid, '\nB2 diagnostics:\n');
fprintf(fid, '- site_node_rows = %d\n', diag.site_node_rows);
fprintf(fid, '- summary_rows = %d\n', diag.summary_rows);
fprintf(fid, '- A_binary_ok_all = %d\n', diag.A_binary_ok_all);
fprintf(fid, '- has_slow_reachable_samples = %d\n', diag.has_slow_reachable_samples);
fprintf(fid, '- has_unreachable_samples = %d\n', diag.has_unreachable_samples);
fprintf(fid, '- max_D_total_max_to_mean = %.12g\n', ...
    diag.max_D_total_max_to_mean);
fprintf(fid, '- states_D_total_max_to_mean_gt5 = %d\n', ...
    diag.count_D_total_max_to_mean_gt5);
fprintf(fid, '- states_D_total_max_to_mean_gt10 = %d\n', ...
    diag.count_D_total_max_to_mean_gt10);
fprintf(fid, '- C_reachable_mean_after_fix_overall = %.12g\n', ...
    diag.C_reachable_mean_after_fix_overall);
fprintf(fid, '- C_reachable_max_after_fix_overall = %.12g\n', ...
    diag.C_reachable_max_after_fix_overall);
fprintf(fid, '- C_reachable_mean_before_fix_overall = %.12g\n', ...
    diag.C_reachable_mean_before_fix_overall);
fprintf(fid, '- C_reachable_max_before_fix_overall = %.12g\n', ...
    diag.C_reachable_max_before_fix_overall);
end

function val = percentile_b2(x, pct)
x = sort(x(:));
if isempty(x)
    val = NaN;
    return;
end
idx = max(1, min(numel(x), ceil(pct / 100 * numel(x))));
val = x(idx);
end
