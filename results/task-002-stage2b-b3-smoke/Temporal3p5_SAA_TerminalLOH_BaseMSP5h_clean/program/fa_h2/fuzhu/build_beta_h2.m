function [beta, mode] = build_beta_h2(S, NearStageInput, opts)
%BUILD_BETA_H2 Map beta(a,loc,lf) to all Markov states.
%
% beta(k) is transport friction/risk. It reduces HTT capacity and/or
% increases transport cost. It is not an absorbing-state flag.
%
% Default behavior is strict: the beta template must cover every state in S.
% Only explicit opts.allow_incomplete_beta_template = true enables fallback.

if isfield(opts, 'beta_template_file') && ~isempty(opts.beta_template_file)
    if ~isfile(opts.beta_template_file)
        error('build_beta_h2:MissingBetaFile', ...
            'Missing beta template file: %s', opts.beta_template_file);
    end
    tbl = readtable(opts.beta_template_file);
    mode = "file:" + string(opts.beta_template_file);
elseif isfield(NearStageInput.HTT, 'beta_template') && istable(NearStageInput.HTT.beta_template)
    tbl = NearStageInput.HTT.beta_template;
    mode = "NearStageInput.HTT.beta_template";
elseif isfield(opts, 'allow_default_beta') && opts.allow_default_beta
    beta = default_beta_h2(S);
    mode = "explicit_default_beta";
    warning('build_beta_h2:DefaultBeta', ...
        'Using explicit toy default beta. This is for sensitivity tests only.');
    return;
else
    error('build_beta_h2:MissingBetaTemplate', ...
        'Provide opts.beta_template_file or NearStageInput.HTT.beta_template.');
end

if ismember('loc', tbl.Properties.VariableNames)
    locCol = 'loc';
elseif ismember('loc_group', tbl.Properties.VariableNames)
    locCol = 'loc_group';
    mode = mode + " (loc_group mapping)";
else
    error('build_beta_h2:MissingLocationColumn', ...
        'beta_template must contain loc or loc_group.');
end

requiredCols = {'intensity_a', 'lf', 'beta_transport_risk'};
for c = 1:numel(requiredCols)
    if ~ismember(requiredCols{c}, tbl.Properties.VariableNames)
        error('build_beta_h2:MissingColumn', ...
            'beta_template is missing required column %s.', requiredCols{c});
    end
end

K = size(S, 1);
beta = zeros(K, 1);
fallbackCount = 0;
availA = unique(tbl.intensity_a);
availLoc = unique(tbl.(locCol));
availLf = unique(tbl.lf);

for k = 1:K
    aKey = S(k, 1);
    locKey = S(k, 2);
    lfKey = S(k, 3);
    rows = tbl.intensity_a == aKey & tbl.(locCol) == locKey & tbl.lf == lfKey;

    if ~any(rows)
        if isfield(opts, 'allow_incomplete_beta_template') && opts.allow_incomplete_beta_template
            aKey = clamp_to_available(S(k, 1), availA);
            locKey = map_loc_to_group(S(k, 2), availLoc);
            lfKey = clamp_to_available(S(k, 3), availLf);
            rows = tbl.intensity_a == aKey & tbl.(locCol) == locKey & tbl.lf == lfKey;
            fallbackCount = fallbackCount + 1;
        else
            error('build_beta_h2:NoStateMatch', ...
                'beta_template does not cover state (a,loc,lf)=(%d,%d,%d).', ...
                S(k, 1), S(k, 2), S(k, 3));
        end
    end

    if nnz(rows) ~= 1
        error('build_beta_h2:BadStateMatch', ...
            'beta_template must have exactly one row for mapped state (%d,%d,%d).', ...
            aKey, locKey, lfKey);
    end
    beta(k) = tbl.beta_transport_risk(rows);
end

if any(beta < -1e-10 | beta > 1 + 1e-10)
    error('build_beta_h2:BetaOutOfRange', 'beta values must be within [0,1].');
end
beta = min(1, max(0, beta));

if fallbackCount > 0
    warning('build_beta_h2:IncompleteTemplateFallback', ...
        'beta_template fallback mapped %d missing states. Use only for debugging/grouped beta models.', ...
        fallbackCount);
    mode = mode + sprintf(" (fallback mapped %d states)", fallbackCount);
end
end

function y = clamp_to_available(x, available)
[~, idx] = min(abs(available - x));
y = available(idx);
end

function g = map_loc_to_group(loc, availableGroups)
% Explicit grouped-location beta model. The template's loc_group values are
% treated as ordered bins, not as the original full location states.
g = clamp_to_available(loc, availableGroups);
end

function beta = default_beta_h2(S)
K = size(S, 1);
Na = max(S(:, 1));
Nc = max(S(:, 3));
beta = zeros(K, 1);
for k = 1:K
    if S(k, 1) == 1
        beta(k) = 0;
    else
        intensity = (S(k, 1) - 1) / max(1, Na - 1);
        approach = (S(k, 3) - 1) / max(1, Nc - 1);
        beta(k) = min(0.95, intensity * approach);
    end
end
end
