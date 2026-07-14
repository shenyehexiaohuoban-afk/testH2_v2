function [indicators, rankingTbl] = rank_Wstep_candidates_h2(indicators, config)
%RANK_WSTEP_CANDIDATES_H2 Rank Wstep candidates from diagnostic indicators.

n = height(indicators);
score = zeros(n, 1);
for ii = 1:n
    score(ii) = indicators.Rmax40_main_score(ii) + ...
        0.75 * indicators.Rmax30_robustness(ii) + ...
        0.75 * indicators.Rmax50_robustness(ii) + ...
        min(indicators.stage_separation(ii), 1) + ...
        min(indicators.geometry_coverage(ii), 1);
end
indicators.overall_score = score;

rankWork = indicators(:, {'Wstep', 'overall_score', 'Rmax40_main_score', ...
    'Rmax30_robustness', 'Rmax50_robustness', 'stage_separation', ...
    'geometry_coverage'});
rankWork.neg_score = -rankWork.overall_score;
rankWork = sortrows(rankWork, {'neg_score', 'Wstep'});
recommendedWstep = rankWork.Wstep(1);

rows = {};
for rr = 1:height(rankWork)
    wstep = rankWork.Wstep(rr);
    row = indicators(indicators.Wstep == wstep, :);
    recommended = rr == 1;
    reason = build_reason(row, recommended);
    limitations = build_limitations(row, recommendedWstep, recommended);
    rows(end + 1, :) = {rr, wstep, recommended, reason, limitations, ...
        row.overall_score, row.Rmax40_main_score, ...
        row.Rmax30_robustness, row.Rmax50_robustness, ...
        row.stage_separation, row.geometry_coverage}; %#ok<AGROW>
    indicators.overall_rank(indicators.Wstep == wstep) = rr;
end

rankingTbl = cell2table(rows, 'VariableNames', ...
    {'rank', 'Wstep', 'recommended_flag', 'reason', 'limitations', ...
    'overall_score', 'Rmax40_main_score', 'Rmax30_robustness', ...
    'Rmax50_robustness', 'stage_separation', 'geometry_coverage'});
end

function reason = build_reason(row, recommended)
if recommended
    prefix = 'Recommended: ';
else
    prefix = 'Not recommended: ';
end
reason = sprintf(['%sRmax40_main_score=%.3g, Rmax30_robustness=%.3g, ' ...
    'Rmax50_robustness=%.3g, main_impact_stage=%s, stage_separation=%.3g.'], ...
    prefix, row.Rmax40_main_score, row.Rmax30_robustness, ...
    row.Rmax50_robustness, string(row.main_impact_stage), ...
    row.stage_separation);
end

function limitations = build_limitations(row, recommendedWstep, recommended)
notes = strings(0, 1);
if ~recommended
    if row.Wstep < recommendedWstep
        notes(end + 1) = "lower score than recommended; impact builds more slowly before W2/W3";
    elseif row.Wstep > recommendedWstep
        notes(end + 1) = "lower score than recommended; coarser time slice without robustness gain";
    end
end
if row.lf7_to_W1_line_gain <= 0 && row.lf7_to_W1_road_gain <= 0
    notes(end + 1) = "W1 risk gain is weak or negative";
end
if row.Wstep > recommendedWstep && ...
        (row.Rmax40_W1_line_pFail_p95 > 0.6 || row.Rmax40_W1_road_pClose_p95 > 0.3)
    notes(end + 1) = "W1 is already relatively close to main-impact risk";
end
if row.Wstep < recommendedWstep && row.Rmax40_W1_road_pClose_p95 < 0.25
    notes(end + 1) = "road impact at W1 is weaker than the balanced candidate";
end
if row.Rmax30_robustness < 2
    notes(end + 1) = "Rmax=30 robustness is weak";
end
if row.Rmax50_robustness < 2
    notes(end + 1) = "Rmax=50 robustness is weak";
end
if row.geometry_coverage < 0.15
    notes(end + 1) = "limited geometry coverage near Rmax";
end
if isempty(notes)
    limitations = "No major ranking limitation found by rule set.";
else
    limitations = strjoin(notes, '; ');
end
end
