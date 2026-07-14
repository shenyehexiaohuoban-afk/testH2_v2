function plot_terminal_loh_summary_h2(byStateTbl, groupField, outFile)
%PLOT_TERMINAL_LOH_SUMMARY_H2 Plot separate-unit summaries by intensity or loc.

needed = {groupField, 'TerminalLOH_total_kg', 'expected_lost_load_kw', 'expected_failed_lines'};
require_vars(byStateTbl, needed);
grp = unique(byStateTbl.(groupField));
grp = sort(grp(:));
meanTerminal = zeros(numel(grp), 1);
meanLostLoad = zeros(numel(grp), 1);
meanFailed = zeros(numel(grp), 1);
for ii = 1:numel(grp)
    rows = byStateTbl.(groupField) == grp(ii);
    meanTerminal(ii) = mean(byStateTbl.TerminalLOH_total_kg(rows));
    meanLostLoad(ii) = mean(byStateTbl.expected_lost_load_kw(rows));
    meanFailed(ii) = mean(byStateTbl.expected_failed_lines(rows));
end

fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100, 100, 880, 760]);
set_chinese_figure_font(fig);
tiledlayout(fig, 3, 1, 'TileSpacing', 'compact');

nexttile;
plot(grp, meanTerminal, '-o', 'LineWidth', 1.5, 'MarkerFaceColor', [0.2 0.45 0.8]);
grid on;
xlabel(group_label_cn(groupField));
ylabel('kg');
title(sprintf('平均终端需氢量随%s变化', group_label_cn(groupField)));

nexttile;
plot(grp, meanLostLoad, '-s', 'LineWidth', 1.5, 'MarkerFaceColor', [0.85 0.35 0.15]);
grid on;
xlabel(group_label_cn(groupField));
ylabel('kW');
title(sprintf('平均期望失负荷随%s变化', group_label_cn(groupField)));

nexttile;
plot(grp, meanFailed, '-^', 'LineWidth', 1.5, 'MarkerFaceColor', [0.25 0.6 0.25]);
grid on;
xlabel(group_label_cn(groupField));
ylabel('线路数');
title(sprintf('平均期望故障线路数随%s变化', group_label_cn(groupField)));

save_png(fig, outFile);
end

function label = group_label_cn(groupField)
switch string(groupField)
    case "a"
        label = "台风强度等级 a";
    case "loc"
        label = "台风登陆位置";
    otherwise
        label = string(groupField);
end
end

function set_chinese_figure_font(fig)
set(fig, 'DefaultAxesFontName', 'Microsoft YaHei');
set(fig, 'DefaultTextFontName', 'Microsoft YaHei');
end

function require_vars(tbl, names)
for ii = 1:numel(names)
    if ~ismember(names{ii}, tbl.Properties.VariableNames)
        error('plot_terminal_loh_summary_h2:MissingField', ...
            'Required field missing: %s.', names{ii});
    end
end
end

function save_png(fig, outFile)
print(fig, outFile, '-dpng', '-r180');
close(fig);
end
