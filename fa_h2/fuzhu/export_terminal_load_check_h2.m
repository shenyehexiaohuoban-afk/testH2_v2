function export_terminal_load_check_h2(params, outDir)
%EXPORT_TERMINAL_LOAD_CHECK_H2 Write node-load vs critical-load check table.

if nargin < 2 || isempty(outDir)
    outDir = params.detailsDir;
end
if ~exist(outDir, 'dir')
    mkdir(outDir);
end

info = params.terminal_load_info;
Nj = params.Nj;
node = (1:Nj).';
Pcritical = nan_vector(info.P_critical_base_kw, Nj);
Hcritical = nan_vector(info.H_node_critical_kg, Nj);
ratio = Pcritical ./ info.P_node_load_kw;
ratio(info.P_node_load_kw == 0) = NaN;

detail = table( ...
    node, info.P_node_load_kw(:), Pcritical, ratio, ...
    info.H_node_load_kg(:), Hcritical, ...
    repmat(string(info.mode), Nj, 1), ...
    'VariableNames', {'node', 'P_node_load_kw', ...
    'P_critical_base_kw_if_available', 'critical_to_node_ratio', ...
    'H_node_load_kg', 'H_node_critical_kg_if_available', ...
    'terminal_load_mode'});

summary = table( ...
    NaN, info.total_P_node_load_kw, info.total_P_critical_base_kw, ...
    info.total_P_critical_base_kw / info.total_P_node_load_kw, ...
    info.total_H_node_load_kg, info.total_H_node_critical_kg, ...
    "summary", ...
    'VariableNames', detail.Properties.VariableNames);

writetable([detail; summary], fullfile(outDir, 'terminal_load_check.csv'));
end

function x = nan_vector(x, n)
if isempty(x)
    x = nan(n, 1);
else
    x = x(:);
end
end
