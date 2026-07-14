function plot_terminal_loh_layout_overview_h2(layout, outFile)
%PLOT_TERMINAL_LOH_LAYOUT_OVERVIEW_H2 Plot coastline, grid, sites, and locs.

require_layout(layout);
fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100, 100, 980, 680]);
set_chinese_figure_font(fig);
ax = axes(fig);
hold(ax, 'on');

plot_grid(ax, layout, [0.65 0.65 0.65], 1.2);
scatter(ax, layout.nodes.x_km, layout.nodes.y_km, 32, [0.15 0.35 0.85], 'filled', ...
    'DisplayName', '电网节点');
scatter(ax, layout.sites.x_km, layout.sites.y_km, 90, '^', 'filled', ...
    'MarkerFaceColor', [0.85 0.2 0.1], 'DisplayName', '氢站');
scatter(ax, layout.locs.center_x_km, layout.locs.center_y_km, 70, 'v', 'filled', ...
    'MarkerFaceColor', [0.15 0.55 0.2], 'DisplayName', '台风登陆位置中心');
plot(ax, [-60, 60], [0, 0], 'k-', 'LineWidth', 1.5, 'DisplayName', '海岸线 y=0');

rectangle(ax, 'Position', [10, 10, 30, 25], 'LineStyle', '--', ...
    'EdgeColor', [0.45 0.45 0.45], 'LineWidth', 1.2);
text(ax, 25, 36.5, '未来电网占位，当前计算未使用', ...
    'HorizontalAlignment', 'center', 'Color', [0.35 0.35 0.35]);

gridCenterX = mean(layout.nodes.x_km);
gridCenterY = mean(layout.nodes.y_km);
scatter(ax, gridCenterX, gridCenterY, 100, 'p', 'filled', ...
    'MarkerFaceColor', [0.95 0.75 0.1], 'DisplayName', '当前电网中心');
text(ax, gridCenterX, gridCenterY + 1.8, '当前电网中心', ...
    'HorizontalAlignment', 'center');

for ii = 1:height(layout.locs)
    text(ax, layout.locs.center_x_km(ii), layout.locs.center_y_km(ii) - 2.2, ...
        sprintf('位置%d', layout.locs.loc(ii)), 'HorizontalAlignment', 'center');
end

xlabel(ax, '沿海岸方向 x（km）');
ylabel(ax, '向内陆方向 y（km）');
title(ax, '风场蒙特卡洛空间布局预览');
axis(ax, 'equal');
xlim(ax, [-62, 62]);
ylim(ax, [-8, 42]);
legend(ax, 'Location', 'northoutside', 'NumColumns', 3);
save_png(fig, outFile);
end

function set_chinese_figure_font(fig)
set(fig, 'DefaultAxesFontName', 'Microsoft YaHei');
set(fig, 'DefaultTextFontName', 'Microsoft YaHei');
end

function plot_grid(ax, layout, color, width)
for ll = 1:height(layout.lines)
    i = layout.lines.from_node(ll);
    j = layout.lines.to_node(ll);
    xi = layout.nodes.x_km(i);
    yi = layout.nodes.y_km(i);
    xj = layout.nodes.x_km(j);
    yj = layout.nodes.y_km(j);
    plot(ax, [xi xj], [yi yj], '-', 'Color', color, 'LineWidth', width, ...
        'HandleVisibility', 'off');
end
end

function require_layout(layout)
needed = {'nodes', 'lines', 'locs', 'sites'};
for ii = 1:numel(needed)
    if ~isfield(layout, needed{ii})
        error('plot_terminal_loh_layout_overview_h2:MissingLayoutField', ...
            'layout.%s is required.', needed{ii});
    end
end
end

function save_png(fig, outFile)
print(fig, outFile, '-dpng', '-r180');
close(fig);
end
