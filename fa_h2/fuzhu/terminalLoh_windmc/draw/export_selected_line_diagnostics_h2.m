function selectedTbl = export_selected_line_diagnostics_h2(diagTables, a, loc, rmaxType, csvFile, pngFile)
%EXPORT_SELECTED_LINE_DIAGNOSTICS_H2 Export representative line diagnostics.

lineRows = select_line_rows(diagTables.line_failure, a, loc, rmaxType);
selectedIdx = zeros(0, 1);
reasons = strings(0, 1);

[~, ordDist] = sort(lineRows.distance_to_typhoon_center_km, 'ascend');
[selectedIdx, reasons] = append_first_unique(selectedIdx, reasons, ordDist, "nearest_to_typhoon_center");

[~, ordFail] = sort(lineRows.failure_probability, 'descend');
[selectedIdx, reasons] = append_first_unique(selectedIdx, reasons, ordFail, "highest_failure_probability");

[~, ordWind] = sort(lineRows.wind_speed_mps, 'descend');
[selectedIdx, reasons] = append_first_unique(selectedIdx, reasons, ordWind, "highest_wind_speed");

rows = lineRows(selectedIdx, :);
selectedTbl = table(reasons(:), rows.line_id, rows.from_node, rows.to_node, ...
    rows.distance_to_typhoon_center_km, rows.wind_speed_mps, rows.failure_probability, ...
    'VariableNames', {'selection_reason', 'line_id', 'from_node', 'to_node', ...
    'distance_to_typhoon_center_km', 'wind_speed_mps', 'failure_probability'});
writetable(selectedTbl, csvFile);

fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100, 100, 880, 760]);
set_chinese_figure_font(fig);
tiledlayout(fig, 3, 1, 'TileSpacing', 'compact');
x = categorical(compose('线路%d', selectedTbl.line_id));
x = reordercats(x, cellstr(compose('线路%d', selectedTbl.line_id)));

nexttile;
bar(x, selectedTbl.distance_to_typhoon_center_km, 'FaceColor', [0.25 0.45 0.8]);
ylabel('km');
title('到台风中心距离');
grid on;

nexttile;
bar(x, selectedTbl.wind_speed_mps, 'FaceColor', [0.85 0.35 0.15]);
ylabel('m/s');
title('风速');
grid on;

nexttile;
bar(x, selectedTbl.failure_probability, 'FaceColor', [0.25 0.6 0.25]);
ylabel('概率');
ylim([0, 0.85]);
title('故障概率');
grid on;

save_png(fig, pngFile);
end

function set_chinese_figure_font(fig)
set(fig, 'DefaultAxesFontName', 'Microsoft YaHei');
set(fig, 'DefaultTextFontName', 'Microsoft YaHei');
end

function rows = select_line_rows(tbl, a, loc, rmaxType)
needed = {'a','loc','Rmax_type','line_id','from_node','to_node', ...
    'distance_to_typhoon_center_km','wind_speed_mps','failure_probability'};
for ii = 1:numel(needed)
    if ~ismember(needed{ii}, tbl.Properties.VariableNames)
        error('export_selected_line_diagnostics_h2:MissingField', ...
            'Required field missing: %s.', needed{ii});
    end
end
rows = tbl(tbl.a == a & tbl.loc == loc & string(tbl.Rmax_type) == string(rmaxType), :);
if isempty(rows)
    error('export_selected_line_diagnostics_h2:MissingRows', ...
        'No line rows for a=%d, loc=%d, Rmax_type=%s.', a, loc, string(rmaxType));
end
end

function [selectedIdx, reasons] = append_first_unique(selectedIdx, reasons, orderedIdx, reason)
for ii = 1:numel(orderedIdx)
    idx = orderedIdx(ii);
    if ~ismember(idx, selectedIdx)
        selectedIdx(end + 1, 1) = idx; %#ok<AGROW>
        reasons(end + 1, 1) = reason; %#ok<AGROW>
        return;
    end
end
error('export_selected_line_diagnostics_h2:InsufficientUniqueLines', ...
    'Could not find a unique line for reason %s.', reason);
end

function save_png(fig, outFile)
print(fig, outFile, '-dpng', '-r180');
close(fig);
end
