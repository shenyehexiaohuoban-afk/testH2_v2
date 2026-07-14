function plot_terminal_loh_node_outage_map_h2(diagTables, windMC, a, loc, rmaxType, outFile)
%PLOT_TERMINAL_LOH_NODE_OUTAGE_MAP_H2 Plot node outage probabilities.

layout = windMC.layout;
nodeRows = select_node_rows(diagTables.node_outage, a, loc, rmaxType);
rmaxRow = select_rmax_row(diagTables.by_state_rmax, a, loc, rmaxType);
center = select_loc_center(layout, loc);

fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100, 100, 920, 680]);
set_chinese_figure_font(fig);
ax = axes(fig);
hold(ax, 'on');
plot_grid(ax, layout, [0.82 0.82 0.82], 1.0);
plot(ax, [-65, 65], [0, 0], 'k-', 'LineWidth', 1.2, 'DisplayName', '海岸线 y=0');

prob = nodeRows.outage_probability;
markerSize = 35 + 130 * prob;
scatter(ax, nodeRows.node_x_km, nodeRows.node_y_km, markerSize, prob, 'filled', ...
    'MarkerEdgeColor', [0.2 0.2 0.2], 'DisplayName', '停电概率');
colormap(ax, turbo(256));
caxis(ax, [0, 1]);
cb = colorbar(ax);
cb.Label.String = '停电概率';
cb.Label.FontName = 'Microsoft YaHei';

for ii = 1:height(nodeRows)
    if mod(ii, 2) == 1 || nodeRows.outage_probability(ii) > 0.4
        text(ax, nodeRows.node_x_km(ii) + 0.45, nodeRows.node_y_km(ii) + 0.45, ...
            sprintf('%d', nodeRows.node_id(ii)), 'FontSize', 7);
    end
end

scatter(ax, center(1), center(2), 110, 'v', 'filled', ...
    'MarkerFaceColor', [0.1 0.45 0.85], 'DisplayName', '台风中心');
draw_circle(ax, center, rmaxRow.Rmax_km, [0.9 0.45 0.1], ...
    sprintf('%s风圈 %.0f km', rmax_type_cn(rmaxType), rmaxRow.Rmax_km));

xlabel(ax, '沿海岸方向 x（km）');
ylabel(ax, '向内陆方向 y（km）');
title(ax, sprintf('节点停电概率（强度=%d，位置=%d，%s风圈 %.0f km）', ...
    a, loc, rmax_type_cn(rmaxType), rmaxRow.Rmax_km));
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

function rows = select_node_rows(tbl, a, loc, rmaxType)
require_vars(tbl, {'a','loc','Rmax_type','node_id','node_x_km','node_y_km','outage_probability'});
rows = tbl(tbl.a == a & tbl.loc == loc & string(tbl.Rmax_type) == string(rmaxType), :);
if isempty(rows)
    error('plot_terminal_loh_node_outage_map_h2:MissingRows', ...
        'No node rows for a=%d, loc=%d, Rmax_type=%s.', a, loc, string(rmaxType));
end
end

function row = select_rmax_row(tbl, a, loc, rmaxType)
require_vars(tbl, {'a','loc','Rmax_type','Rmax_km'});
rows = tbl.a == a & tbl.loc == loc & string(tbl.Rmax_type) == string(rmaxType);
if nnz(rows) ~= 1
    error('plot_terminal_loh_node_outage_map_h2:MissingRmaxRow', ...
        'Expected one Rmax row for a=%d, loc=%d, Rmax_type=%s.', a, loc, string(rmaxType));
end
row = tbl(rows, :);
end

function center = select_loc_center(layout, loc)
rows = layout.locs.loc == loc;
if nnz(rows) ~= 1
    error('plot_terminal_loh_node_outage_map_h2:MissingLoc', ...
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
        error('plot_terminal_loh_node_outage_map_h2:MissingField', ...
            'Required field missing: %s.', names{ii});
    end
end
end

function save_png(fig, outFile)
print(fig, outFile, '-dpng', '-r180');
close(fig);
end
