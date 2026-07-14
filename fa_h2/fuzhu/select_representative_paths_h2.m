function selected = select_representative_paths_h2(evalInfo, params, OS_paths, opts)
%SELECT_REPRESENTATIVE_PATHS_H2 Pick typical OOS paths for diagnostics.
%
% This function only reads OOS evaluation results. It does not change the
% trained policy, transition paths, costs, cuts, or model logic.

if nargin < 4 || isempty(opts)
    opts = struct();
end

numTarget = getOpt(opts, 'numDiagnosticPaths', 6);
nbOS = min(size(OS_paths, 1), numel(evalInfo.pathCost));
T = params.T;

pathType = strings(0, 1);
pathId = zeros(0, 1);
notes = strings(0, 1);

terminalShortage = sum(evalInfo.terminal_reserve_shortage, 2);
terminalCost = sum(evalInfo.terminal_cost, 2);
transportTotal = sum(evalInfo.transport_amount, 2);
productionTotal = sum(evalInfo.production_amount, 2);
normalShortageTotal = sum(evalInfo.normal_shortage, 2);
finalLOHTotal = sum(evalInfo.final_loh, 2);
ordinaryCost = evalInfo.pathCost(:) - terminalCost(:);

hitDemand = evalInfo.hit_loh_demand(:);
firstDemand = evalInfo.first_loh_demand_stage(:);
maxBetaBeforeDemand = zeros(nbOS, 1);
aAtDemand = nan(nbOS, 1);
locAtDemand = nan(nbOS, 1);
lfAtDemand = nan(nbOS, 1);

for s = 1:nbOS
    if hitDemand(s)
        td = firstDemand(s);
        k = OS_paths(s, td);
        aAtDemand(s) = params.S(k, 1);
        locAtDemand(s) = params.S(k, 2);
        lfAtDemand(s) = params.S(k, 3);
        maxBetaBeforeDemand(s) = max(evalInfo.beta_path(s, 1:td));
    else
        maxBetaBeforeDemand(s) = max(evalInfo.beta_path(s, 1:T));
    end
end

    function add_candidate(typeName, candidateIds, noteText)
        candidateIds = candidateIds(:);
        candidateIds = candidateIds(candidateIds >= 1 & candidateIds <= nbOS);
        candidateIds = candidateIds(~ismember(candidateIds, pathId));
        if isempty(candidateIds)
            warning('select_representative_paths_h2:NoCandidate', ...
                'No candidate found for %s.', typeName);
            return;
        end
        keep = candidateIds(1:min(2, numel(candidateIds)));
        for cc = 1:numel(keep)
            pathId(end + 1, 1) = keep(cc); %#ok<AGROW>
            pathType(end + 1, 1) = string(typeName); %#ok<AGROW>
            notes(end + 1, 1) = string(noteText); %#ok<AGROW>
        end
    end

add_candidate("no_loh_demand_path", find(~hitDemand & terminalCost == 0, 1, 'first'), ...
    "No lf=Nc-1 LOH demand/check stage was reached.");

lowCandidates = find(hitDemand);
if ~isempty(lowCandidates)
    [~, ord] = sort(terminalShortage(lowCandidates), 'ascend');
    add_candidate("low_shortage_path", lowCandidates(ord), ...
        "LOH demand stage reached with low terminal shortage.");
else
    add_candidate("low_shortage_path", [], "No LOH demand path exists.");
end

highCandidates = find(hitDemand);
if ~isempty(highCandidates)
    [~, ord] = sort(terminalShortage(highCandidates), 'descend');
    add_candidate("high_shortage_path", highCandidates(ord), ...
        "LOH demand stage reached with high terminal shortage.");
else
    add_candidate("high_shortage_path", [], "No LOH demand path exists.");
end

[~, ordBeta] = sort(maxBetaBeforeDemand, 'descend');
add_candidate("high_beta_path", ordBeta, "High beta before absorption/demand.");

[~, ordTransport] = sort(transportTotal, 'descend');
add_candidate("high_transport_path", ordTransport, "High total HTT transport.");

strongCandidates = find(hitDemand & aAtDemand >= min(5, params.Na));
if ~isempty(strongCandidates)
    [~, ord] = sort(aAtDemand(strongCandidates), 'descend');
    add_candidate("strong_typhoon_path", strongCandidates(ord), ...
        "LOH demand reached under high intensity.");
else
    add_candidate("strong_typhoon_path", [], "No high-intensity LOH demand path found.");
end

% Loc contrast: same or close intensity, different terminal locations.
demandIds = find(hitDemand);
if numel(demandIds) >= 2
    bestPair = [];
    bestScore = -inf;
    for ii = 1:numel(demandIds)
        for jj = ii+1:numel(demandIds)
            p1 = demandIds(ii);
            p2 = demandIds(jj);
            locDiff = abs(locAtDemand(p1) - locAtDemand(p2));
            aDiff = abs(aAtDemand(p1) - aAtDemand(p2));
            score = locDiff * 100 - aDiff;
            if locDiff > 0 && score > bestScore
                bestScore = score;
                bestPair = [p1; p2]; %#ok<AGROW>
            end
        end
    end
    add_candidate("loc_contrast_path", bestPair, ...
        "Similar intensity but different location at LOH demand stage.");
else
    add_candidate("loc_contrast_path", [], "Not enough LOH demand paths for loc contrast.");
end

% Cap the final set without dropping earlier high-priority rows if possible.
if numel(pathId) > numTarget
    pathId = pathId(1:numTarget);
    pathType = pathType(1:numTarget);
    notes = notes(1:numTarget);
end

selected = table();
selected.path_id = pathId;
selected.path_type = pathType;
selected.first_loh_demand_time = firstDemand(pathId);
selected.a_at_demand = aAtDemand(pathId);
selected.loc_at_demand = locAtDemand(pathId);
selected.lf_at_demand = lfAtDemand(pathId);
selected.max_beta_before_demand = maxBetaBeforeDemand(pathId);
selected.total_cost = evalInfo.pathCost(pathId);
selected.ordinary_cost = ordinaryCost(pathId);
selected.loh_demand_cost = terminalCost(pathId);
selected.normal_shortage_total = normalShortageTotal(pathId);
selected.terminal_reserve_shortage_total = terminalShortage(pathId);
selected.production_total = productionTotal(pathId);
selected.htt_transport_total = transportTotal(pathId);
selected.final_loh_total = finalLOHTotal(pathId);
selected.notes = notes;
end

function val = getOpt(opts, fieldName, defaultVal)
if isfield(opts, fieldName)
    val = opts.(fieldName);
else
    val = defaultVal;
end
end
