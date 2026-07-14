function plot_terminal_loh_site_bar_h2(byStateTbl, a, loc, outFile)
%PLOT_TERMINAL_LOH_SITE_BAR_H2 Plot Rmax-weighted TerminalLOH allocation by site.

needed = {'a','loc','TerminalLOH_site1_kg','TerminalLOH_site2_kg', ...
    'TerminalLOH_site3_kg','TerminalLOH_site4_kg','TerminalLOH_total_kg'};
require_vars(byStateTbl, needed);
rows = byStateTbl.a == a & byStateTbl.loc == loc;
if nnz(rows) ~= 1
    error('plot_terminal_loh_site_bar_h2:MissingState', ...
        'Expected one by_state row for a=%d, loc=%d.', a, loc);
end
row = byStateTbl(rows, :);
values = [row.TerminalLOH_site1_kg, row.TerminalLOH_site2_kg, ...
    row.TerminalLOH_site3_kg, row.TerminalLOH_site4_kg];

fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100, 100, 760, 520]);
set_chinese_figure_font(fig);
ax = axes(fig);
bar(ax, 1:4, values, 0.65, 'FaceColor', [0.2 0.45 0.8]);
grid(ax, 'on');
xticks(ax, 1:4);
xticklabels(ax, {'氢站1','氢站2','氢站3','氢站4'});
ylabel(ax, '终端需氢量（kg）');
title(ax, sprintf('各氢站终端需氢量（强度=%d，位置=%d）', a, loc));
subtitle(ax, sprintf('总终端需氢量 = %.2f kg', row.TerminalLOH_total_kg));
for ii = 1:4
    text(ax, ii, values(ii), sprintf('%.1f', values(ii)), ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom');
end
save_png(fig, outFile);
end

function set_chinese_figure_font(fig)
set(fig, 'DefaultAxesFontName', 'Microsoft YaHei');
set(fig, 'DefaultTextFontName', 'Microsoft YaHei');
end

function require_vars(tbl, names)
for ii = 1:numel(names)
    if ~ismember(names{ii}, tbl.Properties.VariableNames)
        error('plot_terminal_loh_site_bar_h2:MissingField', ...
            'Required field missing: %s.', names{ii});
    end
end
end

function save_png(fig, outFile)
print(fig, outFile, '-dpng', '-r180');
close(fig);
end
