function [TerminalLOH, mode, templateUsed, loadInfo] = build_terminal_loh_h2(S, NearStageInput, opts)
%BUILD_TERMINAL_LOH_H2 Build TerminalLOH(:,k) for lf=Nc-1 states only.
%
% TerminalLOH is a reserve requirement evaluated at lf=Nc-1, matching the
% original FA-MSP demand realization stage. It is not a normal-stage demand
% and not an inventory withdrawal. lf=Nc remains a zero-cost absorbing state.
%
% terminal_impact_template format:
%   a, loc, node, impact_weight
% impact_weight is a parameterized terminal pressure weight in [0,1], not a
% sampled component failure or road outage.

Ni = double(NearStageInput.Sets.num_sites);
Nj = double(NearStageInput.Sets.num_nodes);
A = double(NearStageInput.Spatial.service_weight_site_node);
[H, loadInfo] = build_terminal_node_load_vector(NearStageInput, opts, Nj);
Nc = max(S(:, 3));
K = size(S, 1);

if isfield(opts, 'terminal_impact_template_file') && ~isempty(opts.terminal_impact_template_file)
    if ~isfile(opts.terminal_impact_template_file)
        error('build_terminal_loh_h2:MissingTemplateFile', ...
            'Missing terminal impact template file: %s', opts.terminal_impact_template_file);
    end
    tbl = readtable(opts.terminal_impact_template_file);
    templateUsed = string(opts.terminal_impact_template_file);
    mode = "terminal_impact_template";
elseif isfield(opts, 'allow_default_terminal_impact') && opts.allow_default_terminal_impact
    tbl = default_terminal_impact_template(S, Nj);
    templateUsed = "explicit_default_terminal_impact";
    mode = "explicit_default_terminal_impact";
    warning('build_terminal_loh_h2:DefaultTerminalImpact', ...
        'Using explicit toy terminal impact template. This is not a failure sample.');
else
    error('build_terminal_loh_h2:MissingTemplate', ...
        'Provide opts.terminal_impact_template_file. TerminalLOH cannot be silently set to zero.');
end

requiredCols = {'a', 'loc', 'node', 'impact_weight'};
for c = 1:numel(requiredCols)
    if ~ismember(requiredCols{c}, tbl.Properties.VariableNames)
        error('build_terminal_loh_h2:MissingColumn', ...
            'terminal_impact_template is missing required column %s.', requiredCols{c});
    end
end
if any(tbl.impact_weight < -1e-10 | tbl.impact_weight > 1 + 1e-10)
    error('build_terminal_loh_h2:BadImpactWeight', ...
        'impact_weight must be within [0,1].');
end

TerminalLOH = zeros(Ni, K);
for k = 1:K
    a = S(k, 1);
    loc = S(k, 2);
    lf = S(k, 3);
    if a == 1 || lf ~= Nc - 1
        continue;
    end

    targetByNode = zeros(Nj, 1);
    for n = 1:Nj
        rows = tbl.a == a & tbl.loc == loc & tbl.node == n;
        if ~any(rows)
            error('build_terminal_loh_h2:MissingImpactRow', ...
                'terminal_impact_template missing row for (a,loc,node)=(%d,%d,%d).', ...
                a, loc, n);
        end
        if nnz(rows) ~= 1
            error('build_terminal_loh_h2:DuplicateImpactRow', ...
                'terminal_impact_template has duplicate rows for (a,loc,node)=(%d,%d,%d).', ...
                a, loc, n);
        end
        targetByNode(n) = tbl.impact_weight(rows) * H(n);
    end
    TerminalLOH(:, k) = A * targetByNode;
end
end

function [H, loadInfo] = build_terminal_node_load_vector(NearStageInput, opts, Nj)
mode = string(getOpt(opts, 'terminal_load_mode', 'node_load'));
mode = lower(strtrim(mode));

Pcritical = optional_vector(NearStageInput.CriticalLoad, 'P_critical_base_kw', Nj);
Hcritical = optional_vector(NearStageInput.CriticalLoad, 'H_node_kg', Nj);

switch mode
    case "critical_load"
        if isempty(Hcritical)
            error('build_terminal_loh_h2:MissingCriticalHNode', ...
                'CriticalLoad.H_node_kg is required when opts.terminal_load_mode = ''critical_load''.');
        end
        Pnode = read_node_load_kw(NearStageInput, Nj);
        Hnode = compute_h_node_load_kg(Pnode, NearStageInput, opts);
        H = Hcritical;
    case "node_load"
        Pnode = read_node_load_kw(NearStageInput, Nj);
        Hnode = compute_h_node_load_kg(Pnode, NearStageInput, opts);
        H = Hnode;
    otherwise
        error('build_terminal_loh_h2:BadTerminalLoadMode', ...
            'opts.terminal_load_mode must be ''node_load'' or ''critical_load'', got %s.', mode);
end

loadInfo = struct();
loadInfo.mode = mode;
loadInfo.P_node_load_kw = Pnode;
loadInfo.H_node_load_kg = Hnode;
loadInfo.P_critical_base_kw = Pcritical;
loadInfo.H_node_critical_kg = Hcritical;
loadInfo.support_hours = get_terminal_scalar(NearStageInput, opts, ...
    'support_hours', {'CriticalLoad'});
loadInfo.eta_FC = get_terminal_scalar(NearStageInput, opts, ...
    'eta_FC', {'HydrogenDevice'});
loadInfo.h2_lhv_kWh_per_kg = get_terminal_scalar(NearStageInput, opts, ...
    'h2_lhv_kWh_per_kg', {'HydrogenDevice'});
loadInfo.total_P_node_load_kw = sum(Pnode);
loadInfo.total_H_node_load_kg = sum(Hnode);
loadInfo.total_P_critical_base_kw = sum_or_nan(Pcritical);
loadInfo.total_H_node_critical_kg = sum_or_nan(Hcritical);
end

function Pnode = read_node_load_kw(NearStageInput, Nj)
Pnode = [];
if isfield(NearStageInput, 'Grid')
    grid = NearStageInput.Grid;
    candidates = {'P_load_kw', 'Pd_kw', 'P_load_base_kw'};
    for cc = 1:numel(candidates)
        if isfield(grid, candidates{cc})
            val = double(grid.(candidates{cc})(:));
            if numel(val) == Nj
                Pnode = val;
                break;
            end
        end
    end
end

if isempty(Pnode)
    % IEEE33 benchmark active load data, kW. Sum should be 3715 kW.
    Pnode = [
        0;
        100;
        90;
        120;
        60;
        60;
        200;
        200;
        60;
        60;
        45;
        60;
        60;
        120;
        60;
        60;
        60;
        90;
        90;
        90;
        90;
        90;
        90;
        420;
        420;
        60;
        60;
        60;
        120;
        200;
        150;
        210;
        60
    ];
    if numel(Pnode) ~= Nj
        error('build_terminal_loh_h2:NoNodeLoadData', ...
            'No complete Grid node load vector was found and IEEE33 fallback has %d entries, expected %d.', ...
            numel(Pnode), Nj);
    end
end

if abs(sum(Pnode) - 3715) > 1e-6
    warning('build_terminal_loh_h2:UnexpectedIEEE33LoadSum', ...
        'Total P_node_load_kw is %.6g kW; IEEE33 benchmark total is 3715 kW.', sum(Pnode));
end
end

function Hnode = compute_h_node_load_kg(Pnode, NearStageInput, opts)
supportHours = get_terminal_scalar(NearStageInput, opts, 'support_hours', {'CriticalLoad'});
etaFC = get_terminal_scalar(NearStageInput, opts, 'eta_FC', {'HydrogenDevice'});
lhv = get_terminal_scalar(NearStageInput, opts, 'h2_lhv_kWh_per_kg', {'HydrogenDevice'});
if etaFC <= 0 || lhv <= 0 || supportHours < 0
    error('build_terminal_loh_h2:BadHydrogenConversion', ...
        'support_hours, eta_FC, and h2_lhv_kWh_per_kg must be positive except support_hours may be zero.');
end
Hnode = Pnode(:) * supportHours / (etaFC * lhv);
end

function val = get_terminal_scalar(NearStageInput, opts, fieldName, structNames)
if isfield(opts, fieldName)
    val = double(opts.(fieldName));
    if isscalar(val)
        return;
    end
end
for ss = 1:numel(structNames)
    sname = structNames{ss};
    if isfield(NearStageInput, sname) && isfield(NearStageInput.(sname), fieldName)
        val = double(NearStageInput.(sname).(fieldName));
        if isscalar(val)
            return;
        end
    end
end
error('build_terminal_loh_h2:MissingRequiredScalar', ...
    'Missing required scalar %s for TerminalLOH node-load conversion.', fieldName);
end

function val = optional_vector(s, fieldName, n)
val = [];
if isfield(s, fieldName)
    val = double(s.(fieldName)(:));
    if numel(val) ~= n
        error('build_terminal_loh_h2:BadOptionalVectorLength', ...
            'Field %s must have %d entries, got %d.', fieldName, n, numel(val));
    end
end
end

function total = sum_or_nan(x)
if isempty(x)
    total = NaN;
else
    total = sum(x);
end
end

function val = getOpt(opts, fieldName, defaultVal)
if isfield(opts, fieldName)
    val = opts.(fieldName);
else
    val = defaultVal;
end
end

function tbl = default_terminal_impact_template(S, Nj)
% Explicit opt-in toy template for debugging only.
Na = max(S(:, 1));
Nb = max(S(:, 2));
rows = zeros(Na * Nb * Nj, 4);
rr = 0;
for a = 1:Na
    for loc = 1:Nb
        for n = 1:Nj
            rr = rr + 1;
            rows(rr, :) = [a, loc, n, max(0, (a - 1) / max(1, Na - 1))];
        end
    end
end
tbl = array2table(rows, 'VariableNames', {'a', 'loc', 'node', 'impact_weight'});
end
