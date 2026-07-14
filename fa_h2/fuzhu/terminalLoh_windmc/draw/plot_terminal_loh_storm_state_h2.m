function plot_terminal_loh_storm_state_h2(diagTables, windMC, a, loc, outFile)
%PLOT_TERMINAL_LOH_STORM_STATE_H2 Plot representative storm center and Rmax rings.

layout = windMC.layout;
stateRow = select_state_row(diagTables.by_state, a, loc);
rmaxRows = select_rmax_rows(diagTables.by_state_rmax, a, loc);
center = select_loc_center(layout, loc);

fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100, 100, 920, 680]);
set_chinese_figure_font(fig);
ax = axes(fig);
hold(ax, 'on');
plot_grid(ax, layout, [0.7 0.7 0.7], 1);
scatter(ax, layout.nodes.x_km, layout.nodes.y_km, 28, [0.45 0.45 0.45], 'filled', ...
    'DisplayName', '电网节点');
scatter(ax, layout.sites.x_km, layout.sites.y_km, 80, '^', 'filled', ...
    'MarkerFaceColor', [0.85 0.2 0.1], 'DisplayName', '氢站');
plot(ax, [-65, 65], [0, 0], 'k-', 'LineWidth', 1.3, 'DisplayName', '海岸线 y=0');
scatter(ax, center(1), center(2), 110, 'v', 'filled', ...
    'MarkerFaceColor', [0.1 0.45 0.85], 'DisplayName', '台风中心');

colors = [0.2 0.55 0.9; 0.9 0.55 0.1; 0.75 0.2 0.75];
for rr = 1:height(rmaxRows)
    draw_circle(ax, center, rmaxRows.Rmax_km(rr), colors(rr, :), ...
        sprintf('%s风圈 %.0f km', rmax_type_cn(rmaxRows.Rmax_type(rr)), rmaxRows.Rmax_km(rr)));
end

xlabel(ax, '沿海岸方向 x（km）');
ylabel(ax, '向内陆方向 y（km）');
title(ax, sprintf('台风状态（强度=%d，位置=%d，终端阶段，最大风速=%.2f m/s）', ...
    a, loc, stateRow.Vmax_mps));
subtitle(ax, '风圈表示候选最大风速半径尺度，不是损毁边界');
axis(ax, 'equal');
xlim(ax, [-70, 70]);
ylim(ax, [-45, 85]);
legend(ax, 'Location', 'northoutside', 'NumColumns', 3);
grid(ax, 'on');
save_png(fig, outFile);
end

function txt = rmax_type_cn(rmaxType)
switch string(rmaxType)
    case "small"
        txt = "小";
    case "mid"
        txt = "中等";
    case "large"
        txt = "大";
    otherwise
        txt = string(rmaxType);
end
end

function set_chinese_figure_font(fig)
set(fig, 'DefaultAxesFontName', 'Microsoft YaHei');
set(fig, 'DefaultTextFontName', 'Microsoft YaHei');
end

function row = select_state_row(tbl, a, loc)
require_vars(tbl, {'a','loc','Vmax_mps'});
rows = tbl.a == a & tbl.loc == loc;
if nnz(rows) ~= 1
    error('plot_terminal_loh_storm_state_h2:MissingState', ...
        'Expected one by_state row for a=%d, loc=%d.', a, loc);
end
row = tbl(rows, :);
end

function rows = select_rmax_rows(tbl, a, loc)
require_vars(tbl, {'a','loc','Rmax_type','Rmax_km'});
rows = tbl(tbl.a == a & tbl.loc == loc, :);
if height(rows) ~= 3
    error('plot_terminal_loh_storm_state_h2:MissingRmaxRows', ...
        'Expected three Rmax rows for a=%d, loc=%d.', a, loc);
end
end

function center = select_loc_center(layout, loc)
rows = layout.locs.loc == loc;
if nnz(rows) ~= 1
    error('plot_terminal_loh_storm_state_h2:MissingLoc', ...
        'Expected one loc center for loc=%d.', loc);
end
center = [layout.locs.center_x_km(rows), layout.locs.center_y_km(rows)];
end

function plot_grid(ax, layout, color, width)
for ll = 1:height(layout.lines)
    i = layout.lines.from_node(ll);
    j = layout.lines.to_node(ll);
    plot(ax, [layout.nodes.x_km(i), layout.nodes.x_km(j)], ...
        [layout.nodes.y_km(i), layout.nodes.y_km(j)], '-', ...
        'Color', color, 'LineWidth', width, 'HandleVisibility', 'off');
end
end

function draw_circle(ax, center, radius, color, labelText)
theta = linspace(0, 2*pi, 240);
plot(ax, center(1) + radius*cos(theta), center(2) + radius*sin(theta), ...
    '--', 'Color', color, 'LineWidth', 1.4, 'DisplayName', labelText);
end

function require_vars(tbl, names)
for ii = 1:numel(names)
    if ~ismember(names{ii}, tbl.Properties.VariableNames)
        error('plot_terminal_loh_storm_state_h2:MissingField', ...
            'Required field missing: %s.', names{ii});
    end
end
end

function save_png(fig, outFile)
print(fig, outFile, '-dpng', '-r180');
close(fig);
end
