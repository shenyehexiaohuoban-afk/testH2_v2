function result = load_foundation_fix_reaudit_inputs_h2(config)
%LOAD_FOUNDATION_FIX_REAUDIT_INPUTS_H2 Read v1 Foundation CSVs only.

files = {config.riskFile, config.sliceFile, config.DSummaryFile};
for ii = 1:numel(files)
    if ~isfile(files{ii})
        error('load_foundation_fix_reaudit_inputs_h2:MissingInput', ...
            'Missing required Foundation v1 output: %s', files{ii});
    end
end

risk = readtable(config.riskFile, 'TextType', 'string');
mc = readtable(config.sliceFile, 'TextType', 'string');
dSummary = readtable(config.DSummaryFile, 'TextType', 'string');
stageRisk = summarize_stage_risk(risk);

result = struct();
result.risk = risk;
result.stage_risk = stageRisk;
result.mc_by_slice = mc;
result.D_Hres3h_summary = dSummary;
result.Rmax_mode = "fixed_support_point_no_probability_no_resampling";
end

function S = summarize_stage_risk(T)
required = {'Rmax', 'Wstep', 'stage', 'stage_index', ...
    'line_pFail_p95', 'line_pFail_max', 'road_pClose_p95', ...
    'road_pClose_max'};
require_vars(T, required);
groups = unique(T(:, {'Rmax', 'Wstep', 'stage', 'stage_index'}), 'rows');
groups = sortrows(groups, {'Rmax', 'Wstep', 'stage_index'});
rows = {};
for gg = 1:height(groups)
    mask = T.Rmax == groups.Rmax(gg) & T.Wstep == groups.Wstep(gg) & ...
        T.stage_index == groups.stage_index(gg);
    sub = T(mask, :);
    rows(end + 1, :) = {groups.Rmax(gg), groups.Wstep(gg), ...
        groups.stage(gg), groups.stage_index(gg), height(sub), ...
        mean(sub.line_pFail_p95), pct(sub.line_pFail_p95, 95), ...
        max(sub.line_pFail_max), mean(sub.road_pClose_p95), ...
        pct(sub.road_pClose_p95, 95), max(sub.road_pClose_max)}; %#ok<AGROW>
end
S = cell2table(rows, 'VariableNames', ...
    {'Rmax', 'Wstep', 'stage', 'stage_index', 'case_count', ...
    'line_pFail_p95_mean', 'line_pFail_p95_across_cases', ...
    'line_pFail_max', 'road_pClose_p95_mean', ...
    'road_pClose_p95_across_cases', 'road_pClose_max'});
end

function require_vars(T, names)
for ii = 1:numel(names)
    if ~ismember(names{ii}, T.Properties.VariableNames)
        error('load_foundation_fix_reaudit_inputs_h2:MissingColumn', ...
            'Input table is missing column %s.', names{ii});
    end
end
end

function value = pct(x, p)
x = sort(double(x(:)));
x = x(isfinite(x));
if isempty(x)
    value = NaN;
else
    idx = max(1, min(numel(x), ceil(p / 100 * numel(x))));
    value = x(idx);
end
end
