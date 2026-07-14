function write_damage_persistence_diagnostics_h2(bySlice, summaryTbl, ...
    comparisonTbl, checksTbl, diagnostics, config)
%WRITE_DAMAGE_PERSISTENCE_DIAGNOSTICS_H2 Write smoke comparison artifacts.

writetable(bySlice, fullfile(config.outputDir, ...
    'damage_persistence_by_slice.csv'));
writetable(summaryTbl, fullfile(config.outputDir, ...
    'damage_persistence_Hres3h_summary.csv'));
writetable(comparisonTbl, fullfile(config.outputDir, ...
    'independent_vs_persistent_comparison.csv'));
writetable(checksTbl, fullfile(config.outputDir, ...
    'damage_persistence_checks.csv'));
write_summary(summaryTbl, diagnostics, checksTbl, config);
write_audit(diagnostics, checksTbl, config);
write_figures(diagnostics.stage_aggregate, summaryTbl, config);
end

function write_summary(S, diagnostics, checks, config)
fid=fopen(fullfile(config.outputDir,'diagnostics_summary.txt'),'w');
if fid<0,error('write_damage_persistence_diagnostics_h2:OpenFailed', ...
        'Could not open diagnostics_summary.txt.');end
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'W1-W3 damage persistence smoke test\n\n');
fprintf(fid,'Parameters: Wstep=40, Rmax=30|40|50, a=4|6, loc=0|3|10, Nmc=%d, seed=%d.\n',config.Nmc,config.rngSeed);
fprintf(fid,'Modes: independent_snapshot and persistent_damage. No repair is modeled.\n\n');
fprintf(fid,'Common random numbers pass: %d\n',diagnostics.common_random_numbers_pass);
fprintf(fid,'Evidence: %s\n',diagnostics.common_random_numbers_evidence);
fprintf(fid,'Independent scenarios with a later failed/closed count decrease: %d\n\n',diagnostics.independent_recovery_scenario_count);

for rmax=config.RmaxValues(:).'
    fprintf(fid,'Rmax=%g aggregate means across a/loc/scenarios\n',rmax);
    for mode=config.damageModes(:).'
        q=diagnostics.stage_aggregate(diagnostics.stage_aggregate.Rmax==rmax & ...
            diagnostics.stage_aggregate.damage_mode==mode,:);
        q=sortrows(q,'stage_index');
        fprintf(fid,['- %s: failed=[%s], closed=[%s], slow=[%s], ' ...
            'P_loss_kW=[%s], D_kg=[%s]\n'],mode,vec(q.failed_line_mean), ...
            vec(q.closed_road_mean),vec(q.slow_road_mean), ...
            vec(q.P_loss_mean_kW),vec(q.D_mean_kg));
    end
end

fprintf(fid,'\nPersistent monotonicity: line=%d, road=%d, slowdown=%d.\n', ...
    diagnostics.persistent_line_monotonic_pass, ...
    diagnostics.persistent_road_monotonic_pass, ...
    diagnostics.persistent_slowdown_monotonic_pass);
fprintf(fid,'Maximum aggregate persistent saturation share: %.12g.\n', ...
    diagnostics.max_persistent_saturation_share);
fprintf(fid,'Mass saturation detected at threshold %.3g: %d.\n', ...
    config.massSaturationThreshold,diagnostics.mass_saturation_detected);
fprintf(fid,'Wstep=40 persistent stage distinction pass: %d.\n', ...
    diagnostics.stage_distinction_pass);
fprintf(fid,'Formal-B3 recommendation: %s.\n\n',diagnostics.B3_recommendation);

auto=checks.passed(~isnan(checks.passed));
fprintf(fid,'Automatic checks passed: %d/%d; failures=%d; warnings=%d.\n', ...
    sum(auto==1),numel(auto),sum(auto==0),sum(strlength(checks.warning)>0));
fprintf(fid,'No Stage2A2, path_prob, formal B3, Stage2C, WDRO, Gurobi, or MSP run was performed.\n');
end

function write_audit(diagnostics, checks, config)
fid=fopen(fullfile(config.outputDir,'implementation_audit.md'),'w');
if fid<0,error('write_damage_persistence_diagnostics_h2:AuditOpenFailed', ...
        'Could not open implementation_audit.md.');end
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'# Damage persistence smoke implementation audit\n\n');
fprintf(fid,'- Scope: small W1-W3 state-inheritance comparison only.\n');
fprintf(fid,'- `independent_snapshot`: each stage uses the current raw Bernoulli line/road draw and current wind-driven slowdown. Later recovery is allowed.\n');
fprintf(fid,'- `persistent_damage`: failed and closed states use cumulative OR; slowdown severity uses cumulative max. No repair mechanism is included.\n');
fprintf(fid,'- Both modes share the same wind probabilities, random seed, line uniforms, and road uniforms for each Rmax/a/loc/stage/scenario. CRN pass=%d.\n',diagnostics.common_random_numbers_pass);
fprintf(fid,'- Spatial/risk functions reused read-only: `build_foundation_fix_coordinates_h2`, `compute_point_to_segment_distance_h2`, `compute_wind_speed_radial_h2`, and `compute_line_failure_prob_h2`.\n');
fprintf(fid,'- D conversion reused read-only: `compute_Hres3h_node_demand_h2`, with one hour per W slice and three hours total.\n');
fprintf(fid,'- Persistent monotonic checks: line=%d, closed road=%d, slowdown severity=%d.\n', ...
    diagnostics.persistent_line_monotonic_pass, ...
    diagnostics.persistent_road_monotonic_pass, ...
    diagnostics.persistent_slowdown_monotonic_pass);
fprintf(fid,'- Mass saturation detected=%d; maximum aggregate saturation share=%.12g.\n', ...
    diagnostics.mass_saturation_detected,diagnostics.max_persistent_saturation_share);
fprintf(fid,'- Wstep=40 stage distinction pass=%d.\n',diagnostics.stage_distinction_pass);
fprintf(fid,'- Recommendation for formal B3 design: `%s`. This smoke result does not execute B3.\n',diagnostics.B3_recommendation);
fprintf(fid,'- Protected old outputs unchanged=%d; protected MSP files unchanged=%d.\n', ...
    diagnostics.old_output_pass,diagnostics.msp_file_pass);
fprintf(fid,'- Source call scan: WDRO/Gurobi hits=%d, MSP hits=%d, B3/path_prob hits=%d.\n', ...
    diagnostics.source_scan.WDRO_call_hit_count, ...
    diagnostics.source_scan.MSP_call_hit_count, ...
    diagnostics.source_scan.B3_call_hit_count);
fprintf(fid,'- Automatic check failures=%d; warnings=%d.\n', ...
    sum(checks.passed==0),sum(strlength(checks.warning)>0));
fprintf(fid,'- Stage2A2/path_prob/path screening/formal B3/Stage2C/WDRO/MSP: not executed.\n');
fprintf(fid,'- Existing Foundation v1/v2 source results and output directories were not overwritten.\n');
end

function write_figures(A,S,config)
figDir=fullfile(config.outputDir,'figures');if ~isfolder(figDir),mkdir(figDir);end
plot_stage_metric(A,'failed_line_mean','Mean failed line count', ...
    fullfile(figDir,'failed_line_count_by_stage.png'));
plot_stage_metric(A,'closed_road_mean','Mean closed road count', ...
    fullfile(figDir,'closed_road_count_by_stage.png'));
plot_stage_metric(A,'slow_road_mean','Mean slow road count', ...
    fullfile(figDir,'slow_road_count_by_stage.png'));
plot_stage_metric(A,'P_loss_mean_kW','Mean P loss (kW)', ...
    fullfile(figDir,'P_loss_by_stage.png'));
plot_stage_metric(A,'D_mean_kg','Mean D slice (kg-H2)', ...
    fullfile(figDir,'D_by_stage.png'));
plot_D_total(S,fullfile(figDir,'D_Hres3h_total_by_Rmax.png'));
end

function plot_stage_metric(A,fieldName,yLabel,outFile)
fig=figure('Visible','off','Color','w','Position',[100 100 950 540]);
cleanup=onCleanup(@()close(fig));ax=axes(fig);hold(ax,'on');grid(ax,'on');
colors=lines(3);
for rr=1:3
    rmax=[30,40,50];
    for mm=1:2
        modes=["independent_snapshot","persistent_damage"];
        q=A(A.Rmax==rmax(rr) & A.damage_mode==modes(mm),:);q=sortrows(q,'stage_index');
        style='-';if mm==1,style='--';end
        plot(ax,1:3,q.(fieldName),style,'Color',colors(rr,:), ...
            'Marker','o','LineWidth',1.4,'DisplayName', ...
            sprintf('Rmax=%g %s',rmax(rr),modes(mm)));
    end
end
xticks(ax,1:3);xticklabels(ax,{'W1','W2','W3'});ylabel(ax,yLabel);
title(ax,[yLabel ' by damage mode']);
legend(ax,'Location','eastoutside','Interpreter','none');
exportgraphics(fig,outFile,'Resolution',180);
end

function plot_D_total(S,outFile)
groups=groupsummary(S,{'damage_mode','Rmax'},'mean','D_Hres3h_total_mean_kg');
fig=figure('Visible','off','Color','w','Position',[100 100 850 500]);
cleanup=onCleanup(@()close(fig));ax=axes(fig);hold(ax,'on');grid(ax,'on');
for mm=1:2
    modes=["independent_snapshot","persistent_damage"];
    q=groups(groups.damage_mode==modes(mm),:);q=sortrows(q,'Rmax');
    plot(ax,q.Rmax,q.mean_D_Hres3h_total_mean_kg,'-o','LineWidth',1.5, ...
        'DisplayName',modes(mm));
end
xlabel(ax,'Rmax (km-equivalent)');ylabel(ax,'Mean Hres3h D total (kg-H2)');
title(ax,'Independent versus persistent Hres3h demand');
legend(ax,'Location','best','Interpreter','none');
exportgraphics(fig,outFile,'Resolution',180);
end

function s=vec(x)
s=char(strjoin(compose('%.6g',x.'),','));
end
