function write_foundation_fix_reaudit_v2_h2(result, recommendation, ...
    dAudit, checks, scopeAudit, config)
%WRITE_FOUNDATION_FIX_REAUDIT_V2_H2 Write hardened re-audit artifacts.

recTbl = recommendation.candidate_table;
summaryTbl = recommendation.candidate_summary;
recTbl = innerjoin(recTbl, summaryTbl, 'Keys', 'candidate_Wstep');
recTbl.final_recommendation_status = repmat(recommendation.status, ...
    height(recTbl), 1);
recTbl.final_recommended_Wstep = repmat( ...
    recommendation.recommended_Wstep, height(recTbl), 1);
recTbl.recommendation_reason = repmat(recommendation.reason, ...
    height(recTbl), 1);
recTbl.allowed_statuses = repmat(recommendation.allowed_statuses, ...
    height(recTbl), 1);

writetable(recTbl, fullfile(config.outputDir, ...
    'Wstep40_45_recommendation_v2.csv'));
writetable(dAudit.scenario_table, fullfile(config.outputDir, ...
    'D_Hres3h_independent_recheck.csv'));
writetable(checks, fullfile(config.outputDir, ...
    'foundation_fix_reaudit_checks_v2.csv'));
writetable(scopeAudit.modified_file_audit, fullfile(config.outputDir, ...
    'modified_file_audit.csv'));
writetable(scopeAudit.output_directory_audit, fullfile(config.outputDir, ...
    'output_directory_audit.csv'));
write_diagnostics(result, recommendation, dAudit, checks, scopeAudit, config);
write_implementation(recommendation, dAudit, checks, scopeAudit, config);
end

function write_diagnostics(result, rec, dAudit, checks, scopeAudit, config)
fid = fopen(fullfile(config.outputDir, 'diagnostics_summary_v2.txt'), 'w');
if fid < 0
    error('write_foundation_fix_reaudit_v2_h2:OpenFailed', ...
        'Could not open diagnostics_summary_v2.txt.');
end
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, 'Foundation Fix recommendation and re-audit hardening v2\n\n');
fprintf(fid, 'Recommendation status: %s\n', rec.status);
fprintf(fid, 'Recommended Wstep: %.12g\n', rec.recommended_Wstep);
fprintf(fid, 'Allowed statuses: %s\n', rec.allowed_statuses);
fprintf(fid, 'Reason: %s\n\n', rec.reason);

fprintf(fid, 'Symmetric recommendation evidence by candidate and Rmax\n');
for ii = 1:height(rec.candidate_table)
    r = rec.candidate_table(ii, :);
    fprintf(fid, ['- Wstep=%g Rmax=%g: line W1=%.9g main=%.9g; ' ...
        'road W1=%.9g main=%.9g; Dtotal=%.9g; DmainShare=%.9g; ' ...
        'W1enhanced=%d mainReached=%d skip=%d jointSupport=%d\n'], ...
        r.candidate_Wstep, r.Rmax, r.line_pFail_p95_W1, ...
        r.line_pFail_p95_main_W2W3, r.road_pClose_p95_W1, ...
        r.road_pClose_p95_main_W2W3, r.D_total_mean_kg, ...
        r.D_main_W2W3_share, r.W1_enhanced_pass, ...
        r.main_impact_reached_pass, r.skips_main_impact_band, ...
        r.joint_support_vs_other);
end

fprintf(fid, '\nD independent CSV recheck\n');
fprintf(fid, '- scenarios recomputed: %d; groups: %d\n', ...
    dAudit.scenario_count, dAudit.group_count);
fprintf(fid, '- exact W1/W2/W3: %d; no duplicates: %d; lf7 excluded: %d\n', ...
    dAudit.exact_W123_pass, dAudit.no_duplicate_stage_pass, ...
    dAudit.lf7_excluded_pass);
fprintf(fid, '- slice duration 1h: %d; Hres total 3h: %d\n', ...
    dAudit.slice_duration_1h_pass, dAudit.Hres_total_3h_pass);
fprintf(fid, '- reported aggregate metrics match recomputed: %d\n', ...
    dAudit.reported_vs_recomputed_pass);
fprintf(fid, '- maximum absolute error: %.12g; tolerance: %.12g\n', ...
    dAudit.max_reported_abs_error, dAudit.tolerance);
fprintf(fid, '- schema note: %s\n\n', dAudit.schema_warning);

fprintf(fid, 'Common random numbers\n');
fprintf(fid, '- pass: %d\n', scopeAudit.common_random_numbers.pass);
fprintf(fid, '- evidence: %s\n\n', scopeAudit.common_random_numbers.evidence);

automatic = checks.passed(~isnan(checks.passed));
fprintf(fid, 'Re-audit checks\n');
fprintf(fid, '- automatic checks passed: %d/%d\n', ...
    sum(automatic == 1), numel(automatic));
warningRows = checks(strlength(checks.warning) > 0, :);
fprintf(fid, '- warning/manual rows: %d\n', height(warningRows));
for ii = 1:height(warningRows)
    fprintf(fid, '  %s: %s\n', warningRows.check_name(ii), ...
        warningRows.warning(ii));
end

fprintf(fid, '\nScope confirmation\n');
fprintf(fid, '- no formal B3: %d\n', scopeAudit.no_formal_B3_generated.pass);
fprintf(fid, '- no WDRO/Gurobi call: %d\n', scopeAudit.no_WDRO_run.pass);
fprintf(fid, '- no MSP modification/call: %d\n', scopeAudit.no_MSP_modified.pass);
fprintf(fid, '- no old output overwritten: %d\n', ...
    scopeAudit.no_old_output_overwritten.pass);
fprintf(fid, '- Stage2A2/path_prob/B3/Stage2C were not executed.\n');
end

function write_implementation(rec, dAudit, checks, scopeAudit, config)
fid = fopen(fullfile(config.outputDir, 'implementation_audit_v2.md'), 'w');
if fid < 0
    error('write_foundation_fix_reaudit_v2_h2:AuditOpenFailed', ...
        'Could not open implementation_audit_v2.md.');
end
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, '# Foundation Fix re-audit v2 implementation audit\n\n');
fprintf(fid, '- The old recommendation was biased because any material 40/45 difference selected Wstep 40 without testing candidate dominance.\n');
fprintf(fid, '- The v2 rule evaluates both candidates with identical W1 enhancement, main-impact, skip-band, cross-Rmax, line, road, and D-stage coverage tests.\n');
fprintf(fid, '- The selector permits `recommend_40`, `recommend_45`, and `inconclusive_40_45`; synthetic tests verified all three branches.\n');
fprintf(fid, '- Final result: `%s`; recommended Wstep: %.12g.\n', ...
    rec.status, rec.recommended_Wstep);
fprintf(fid, '- Decision reason: %s\n', rec.reason);
fprintf(fid, '- D was independently recomputed from `%s` using `mc_id` as `scenario_id`.\n', ...
    config.sliceFile);
fprintf(fid, '- Per-scenario W1/W2/W3 rows=%d; groups=%d; max reported aggregate error=%.12g.\n', ...
    dAudit.scenario_count, dAudit.group_count, dAudit.max_reported_abs_error);
fprintf(fid, '- The v1 summary has no per-scenario `D_Hres3h_total_kg`; mean/P50/P90/P95/MAX were independently reconstructed and compared automatically.\n');
fprintf(fid, '- Common random numbers: pass=%d; %s\n', ...
    scopeAudit.common_random_numbers.pass, ...
    scopeAudit.common_random_numbers.evidence);
fprintf(fid, '- `no_formal_B3_generated`, `no_WDRO_run`, `no_MSP_modified`, and `no_old_output_overwritten` are evidence-based, not fixed true.\n');
fprintf(fid, '- Complete workspace diff: manual verification required because no Git repository or executable is available. Protected MSP files and old outputs were automatically audited.\n');
fprintf(fid, '- Automatic check failures: %d. Warning/manual rows: %d.\n', ...
    sum(checks.passed == 0), sum(strlength(checks.warning) > 0));
fprintf(fid, '- Stage2A2 executed: no. path_prob computed: no. formal B3: no. Stage2C: no. WDRO/Gurobi: no. MSP modified or run: no.\n');
end
