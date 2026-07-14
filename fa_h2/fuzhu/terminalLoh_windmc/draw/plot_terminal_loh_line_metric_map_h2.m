function plot_terminal_loh_line_metric_map_h2(diagTables, windMC, a, loc, rmaxType, metricName, colorbarLabel, fixedCLim, outFile)
%PLOT_TERMINAL_LOH_LINE_METRIC_MAP_H2 Plot line wind speed or failure probability.

layout = windMC.layout;
lineRows = select_line_rows(diagTables.line_failure, a, loc, rmaxType);
rmaxRow = select_rmax_row(diagTables.by_state_rmax, a, loc, rmaxType);
center = select_loc_center(layout, loc);
require_vars(lineRows, {metricName});

values = lineRows.(metricName);
if isempty(fixedCLim)
    cLim = [min(values), max(values)];
    if cLim(1) == cLim(2)
        cLim = [cLim(1), cLim(1) + 1];
    end
else
    cLim = fixedCLim;
end

fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100, 100, 920, 680]);
set_chinese_figure_font(fig);
ax = axes(fig);
hold(ax, 'on');
colormap(ax, turbo(256));
caxis(ax, cLim);
scatter(ax, layout.nodes.x_km, layout.nodes.y_km, 22, [0.75 0.75 0.75], 'filled', ...
    'DisplayName', '电网节点');
plot(ax, [-65, 65], [0, 0], 'k-', 'LineWidth', 1.2, 'DisplayName', '海岸线 y=0');

for rr = 1:height(lineRows)
    lineId = lineRows.line_id(rr);
    lineLayout = layout.lines(layout.lines.line_id == lineId, :);
    if height(lineLayout) ~= 1
        error('plot_terminal_loh_line_metric_map_h2:MissingLineLayout', ...
            'Missing layout row for line_id=%d.', lineId);
    end
    color = value_to_color(values(rr), cLim);
    i = lineLayout.from_node;
    j = lineLayout.to_node;
    plot(ax, [layout.nodes.x_km(i), layout.nodes.x_km(j)], ...
        [layout.nodes.y_km(i), layout.nodes.y_km(j)], '-', ...
        'Color', color, 'LineWidth', 3.0, 'HandleVisibility', 'off');
end

scatter(ax, center(1), center(2), 110, 'v', 'filled', ...
    'MarkerFaceColor', [0.1 0.45 0.85], 'DisplayName', '台风中心');
draw_circle(ax, center, rmaxRow.Rmax_km, [0.9 0.45 0.1], ...
    sprintf('%s风圈 %.0f km', rmax_type_cn(rmaxType), rmaxRow.Rmax_km));

cb = colorbar(ax);
cb.Label.String = colorbarLabel;
cb.Label.FontName = 'Microsoft YaHei';
xlabel(ax, '沿海岸方向 x（km）');
ylabel(ax, '向内陆方向 y（km）');
title(ax, sprintf('%s图（强度=%d，位置=%d，%s风圈 %.0f km）', ...
    metric_title_cn(metricName), a, loc, rmax_type_cn(rmaxType), rmaxRow.Rmax_km));
axis(ax, 'equal');
xlim(ax, [-70, 70]);
ylim(ax, [-45, 85]);
legend(ax, 'Location', 'northoutside', 'NumColumns', 3);
grid(ax, 'on');
save_png(fig, outFile);
end

function txt = metric_title_cn(metricName)
switch string(metricName)
    case "wind_speed_mps"
        txt = "线路风速";
    case "failure_probability"
        txt = "线路故障概率";
    otherwise
        txt = string(metricName);
end
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

function rows = select_line_rows(tbl, a, loc, rmaxType)
require_vars(tbl, {'a','loc','Rmax_type','line_id'});
rows = tbl(tbl.a == a & tbl.loc == loc & string(tbl.Rmax_type) == string(rmaxType), :);
if isempty(rows)
    error('plot_terminal_loh_line_metric_map_h2:MissingRows', ...
        'No line rows for a=%d, loc=%d, Rmax_type=%s.', a, loc, string(rmaxType));
end
end

function row = select_rmax_row(tbl, a, loc, rmaxType)
require_vars(tbl, {'a','loc','Rmax_type','Rmax_km'});
rows = tbl.a == a & tbl.loc == loc & string(tbl.Rmax_type) == string(rmaxType);
if nnz(rows) ~= 1
    error('plot_terminal_loh_line_metric_map_h2:MissingRmaxRow', ...
        'Expected one Rmax row for a=%d, loc=%d, Rmax_type=%s.', a, loc, string(rmaxType));
end
row = tbl(rows, :);
end

function center = select_loc_center(layout, loc)
rows = layout.locs.loc == loc;
if nnz(rows) ~= 1
    error('plot_terminal_loh_line_metric_map_h2:MissingLoc', ...
        'Expected one loc center for loc=%d.', loc);
end
center = [layout.locs.center_x_km(rows), layout.locs.center_y_km(rows)];
end

function color = value_to_color(value, cLim)
cmap = turbo(256);
frac = (value - cLim(1)) / max(eps, cLim(2) - cLim(1));
idx = min(256, max(1, round(1 + frac * 255)));
color = cmap(idx, :);
end

function draw_circle(ax, center, radius, color, labelText)
theta = linspace(0, 2*pi, 240);
plot(ax, center(1) + radius*cos(theta), center(2) + radius*sin(theta), ...
    '--', 'Color', color, 'LineWidth', 1.4, 'DisplayName', labelText);
end

function require_vars(tbl, names)
for ii = 1:numel(names)
    if ~ismember(names{ii}, tbl.Properties.VariableNames)
        error('plot_terminal_loh_line_metric_map_h2:MissingField', ...
            'Required field missing: %s.', names{ii});
    end
end
end

function save_png(fig, outFile)
print(fig, outFile, '-dpng', '-r180');
close(fig);
end
