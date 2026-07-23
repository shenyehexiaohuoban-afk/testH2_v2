function result = evaluate_intensity_wind_sensitivity_block_h2( ...
    model, stateSample, baseSeed, stateId, evaluationCount)
%EVALUATE_INTENSITY_WIND_SENSITIVITY_BLOCK_H2 Evaluate one state/seed block.

nRecords = height(stateSample);
if nRecords ~= 15000 || evaluationCount < 1 || evaluationCount > nRecords
    error('evaluate_intensity_wind_sensitivity_block_h2:BadSampleSize', ...
        'State sample must contain 15000 rows and cover evaluationCount.');
end
required = {'a_W1','a_W2','a_W3','loc_W1','loc_W2','loc_W3', ...
    'lfw_W1','lfw_W2','lfw_W3','path_id'};
for ii = 1:numel(required)
    if ~ismember(required{ii}, stateSample.Properties.VariableNames)
        error('State sample missing %s.', required{ii});
    end
end

derivedSeed = double(baseSeed) + 100003 * double(stateId);
rng(derivedSeed, 'twister');
permutation = randperm(nRecords).';
fixedLineU = rand(nRecords, model.nLines);
fixedRoadU = rand(nRecords, model.nRoads);
qAll = rand(nRecords, 1);

selected = stateSample(permutation(1:evaluationCount), :);
lineU = fixedLineU(1:evaluationCount, :);
roadU = fixedRoadU(1:evaluationCount, :);
sharedQ = qAll(1:evaluationCount);

idx = cell(3,1);
idx{1} = state_indices(model, selected.a_W1, selected.loc_W1, selected.lfw_W1);
idx{2} = state_indices(model, selected.a_W2, selected.loc_W2, selected.lfw_W2);
idx{3} = state_indices(model, selected.a_W3, selected.loc_W3, selected.lfw_W3);
aByStage = {double(selected.a_W1), double(selected.a_W2), double(selected.a_W3)};

nModes = numel(model.modeNames);
scenario = cell(nModes,1);
lineWindByMode = cell(nModes,3);
roadWindByMode = cell(nModes,3);
metricRows = cell(nModes, 21);

for mm = 1:nModes
    modeName = model.modeNames(mm);
    pFail = cell(3,1); pClose = cell(3,1);
    for ss = 1:3
        if modeName == "M1"
            vmax = sensitivity_vmax(aByStage{ss}, sharedQ, model.vLow, ...
                model.vHigh, model.currentMap);
            lineWindByMode{mm,ss} = model.lineFactor(idx{ss}, :) .* vmax;
            roadWindByMode{mm,ss} = model.roadFactor(idx{ss}, :) .* vmax;
            pFail{ss} = compute_line_failure_prob_h2( ...
                lineWindByMode{mm,ss}, model.designWindSpeedVN);
            pClose{ss} = compute_line_failure_prob_h2( ...
                roadWindByMode{mm,ss}, model.roadDesignWindVN);
        else
            fixedIndex = find(model.fixedModeNames == modeName, 1);
            if isempty(fixedIndex)
                error('No fixed cache is available for mode %s.', modeName);
            end
            lineWindByMode{mm,ss} = model.fixedLineWind{fixedIndex}(idx{ss}, :);
            roadWindByMode{mm,ss} = model.fixedRoadWind{fixedIndex}(idx{ss}, :);
            pFail{ss} = model.fixedPFail{fixedIndex}(idx{ss}, :);
            pClose{ss} = model.fixedPClose{fixedIndex}(idx{ss}, :);
        end
    end

    failed1 = lineU <= pFail{1};
    failed2 = failed1 | (lineU <= pFail{2});
    failed3 = failed2 | (lineU <= pFail{3});
    outage1 = (double(failed1) * model.nodePathIncidence.') > 0;
    outage2 = (double(failed2) * model.nodePathIncidence.') > 0;
    outage3 = (double(failed3) * model.nodePathIncidence.') > 0;
    outage1(:,model.sourceNode) = false;
    outage2(:,model.sourceNode) = false;
    outage3(:,model.sourceNode) = false;
    P1 = double(outage1) * model.Pnode_kW;
    P2 = double(outage2) * model.Pnode_kW;
    P3 = double(outage3) * model.Pnode_kW;
    Dtotal = (P1 + P2 + P3) * model.DFactorKgPerKWh;
    fullLoss = abs(Dtotal - model.DUpperKg) <= 1e-9;
    W3Failed = sum(failed3, 2);

    closed1 = roadU <= pClose{1};
    closed2 = closed1 | (roadU <= pClose{2});
    closed3 = closed2 | (roadU <= pClose{3});
    slow1 = pClose{1};
    slow2 = max(slow1, pClose{2});
    slow3 = max(slow2, pClose{3});
    W3Closed = sum(closed3, 2);

    A0Share = zeros(evaluationCount,1);
    reachableShare = zeros(evaluationCount,1);
    CScenarioMean = zeros(evaluationCount,1);
    invalidA = 0; invalidC = 0;
    for rr = 1:evaluationCount
        unreachableTotal = 0; reachableTotal = 0; Csum = 0;
        for ss = 1:3
            if ss == 1
                closed = closed1(rr,:).'; slow = slow1(rr,:).';
            elseif ss == 2
                closed = closed2(rr,:).'; slow = slow2(rr,:).';
            else
                closed = closed3(rr,:).'; slow = slow3(rr,:).';
            end
            edgeCost = model.roadLength .* (1 + slow);
            edgeCost(closed) = Inf;
            [reachableCount, stageCsum, stageInvalid] = road_metrics( ...
                model.nNodes, model.roadFrom, model.roadTo, edgeCost, ...
                model.siteNodes);
            invalidC = invalidC + stageInvalid;
            reachableTotal = reachableTotal + reachableCount;
            unreachableTotal = unreachableTotal + ...
                (model.nSites * model.nNodes - reachableCount);
            Csum = Csum + stageCsum;
        end
        pairTotal = 3 * model.nSites * model.nNodes;
        A0Share(rr) = unreachableTotal / pairTotal;
        reachableShare(rr) = reachableTotal / pairTotal;
        if reachableTotal <= 0
            invalidA = invalidA + 1;
            CScenarioMean(rr) = NaN;
        else
            CScenarioMean(rr) = Csum / reachableTotal;
        end
    end

    scenario{mm} = table(Dtotal, fullLoss, A0Share, reachableShare, ...
        CScenarioMean, W3Failed, W3Closed);
    metricRows(mm,:) = {modeName, evaluationCount, mean(Dtotal), ...
        pct(Dtotal,95), pct(Dtotal,99), mean(fullLoss), mean(A0Share), ...
        mean(reachableShare), mean(CScenarioMean), pct(CScenarioMean,95), ...
        mean(W3Failed), pct(W3Failed,95), mean(W3Closed), ...
        pct(W3Closed,95), mean(fullLoss), min(Dtotal), max(Dtotal), ...
        sum(~isfinite(Dtotal)) + sum(~isfinite(CScenarioMean)), ...
        sum(Dtotal < 0) + sum(CScenarioMean < 0), invalidA, invalidC};
end

metrics = cell2table(metricRows, 'VariableNames', ...
    {'mode','N','D_mean_kg','D_q95_kg','D_q99_kg', ...
    'full_loss_probability','A0_pair_share','reachable_pair_share', ...
    'C_reachable_mean_km','C_reachable_q95_km', ...
    'W3_failed_lines_mean','W3_failed_lines_q95', ...
    'W3_closed_roads_mean','W3_closed_roads_q95', ...
    'D_upper_bound_hit_share','D_min_kg','D_max_kg','nonfinite_count', ...
    'negative_value_count','A_invalid_scenario_count','C_invalid_value_count'});

pairedMetricNames = ["Dtotal","fullLoss","A0Share","reachableShare", ...
    "CScenarioMean","W3Failed","W3Closed"];
pairedRows = cell((nModes-1)*numel(pairedMetricNames), 12); pr = 0;
baseline = scenario{model.modeNames == "M0"};
for mm = 1:nModes
    if model.modeNames(mm) == "M0", continue; end
    current = scenario{mm};
    for kk = 1:numel(pairedMetricNames)
        name = pairedMetricNames(kk);
        b = double(baseline.(name)); x = double(current.(name)); d = x - b;
        pr = pr + 1;
        pairedRows(pr,:) = {model.modeNames(mm), name, mean(b), mean(x), ...
            mean(d), mean(abs(d)), pct(d,5), pct(d,50), pct(d,95), ...
            min(d), max(d), mean(abs(d) > 1e-12)};
    end
end
paired = cell2table(pairedRows, 'VariableNames', ...
    {'mode','metric','M0_mean','mode_mean','paired_difference_mean', ...
    'paired_absolute_difference_mean','paired_difference_q05', ...
    'paired_difference_median','paired_difference_q95', ...
    'paired_difference_min','paired_difference_max','nonzero_difference_share'});

stageNames = ["W1","W2","W3"];
thresholdRows = cell(nModes*3*4, 12); tr = 0;
for mm = 1:nModes
    for ss = 1:3
        for assetId = 1:2
            if assetId == 1
                asset = "grid_line"; thresholds = [25,50];
                values = lineWindByMode{mm,ss};
                baseValues = lineWindByMode{model.modeNames == "M0",ss};
            else
                asset = "road_edge"; thresholds = [30,60];
                values = roadWindByMode{mm,ss};
                baseValues = roadWindByMode{model.modeNames == "M0",ss};
            end
            for threshold = thresholds
                above = values > threshold; baseAbove = baseValues > threshold;
                tr = tr + 1;
                thresholdRows(tr,:) = {model.modeNames(mm), asset, stageNames(ss), ...
                    threshold, numel(values), sum(above,'all'), mean(above,'all'), ...
                    sum(above & ~baseAbove,'all'), mean(above & ~baseAbove,'all'), ...
                    sum(~above & baseAbove,'all'), mean(~above & baseAbove,'all'), ...
                    max(values,[],'all')};
            end
        end
    end
end
thresholdAudit = cell2table(thresholdRows, 'VariableNames', ...
    {'mode','asset','stage','threshold_mps','observation_count', ...
    'above_count','above_share','crossed_up_vs_M0_count', ...
    'crossed_up_vs_M0_share','crossed_down_vs_M0_count', ...
    'crossed_down_vs_M0_share','local_wind_max_mps'});

result = struct();
result.metrics = metrics;
result.paired = paired;
result.threshold_audit = thresholdAudit;
result.derived_seed = derivedSeed;
result.path_id_sha256 = sha256_numeric(double(selected.path_id));
result.permutation_sha256 = sha256_numeric(permutation(1:evaluationCount));
result.line_u_sha256 = sha256_numeric(fixedLineU(1:evaluationCount,:));
result.road_u_sha256 = sha256_numeric(fixedRoadU(1:evaluationCount,:));
result.q_sha256 = sha256_numeric(sharedQ);
result.q_min = min(sharedQ); result.q_max = max(sharedQ);
result.shared_q_pass = numel(sharedQ) == evaluationCount && ...
    all(isfinite(sharedQ)) && all(sharedQ >= 0 & sharedQ <= 1);
result.common_resistance_pass = true;
end

function vmax = sensitivity_vmax(a, q, vLow, vHigh, currentMap)
a = double(a(:)); q = double(q(:));
if numel(a) ~= numel(q), error('Intensity and q sizes differ.'); end
vmax = currentMap(a);
bounded = a >= 2 & a <= 5;
vmax(bounded) = vLow(a(bounded)) + q(bounded) .* ...
    (vHigh(a(bounded)) - vLow(a(bounded)));
end

function idx = state_indices(model, a, loc, lfw)
a = double(a(:)); loc = double(loc(:)); lfw = double(lfw(:));
if any(a < 1 | a > 6 | loc < model.locMin | loc > model.locMax | ...
        lfw < 0 | lfw > 3)
    error('Sample contains a joint state outside the accepted support.');
end
linear = sub2ind(size(model.stateIndex), a, loc-model.locMin+1, lfw+1);
idx = model.stateIndex(linear);
if any(idx <= 0), error('Sample joint state is absent from the wind cache.'); end
end

function [reachableCount, Csum, invalidCount] = road_metrics( ...
    nNodes, fromNode, toNode, edgeCost, sources)
adj = inf(nNodes,nNodes); adj(1:(nNodes+1):end) = 0;
for ee = 1:numel(edgeCost)
    if ~isfinite(edgeCost(ee)), continue; end
    i = fromNode(ee); j = toNode(ee);
    if edgeCost(ee) < adj(i,j)
        adj(i,j) = edgeCost(ee); adj(j,i) = edgeCost(ee);
    end
end
reachableCount = 0; Csum = 0; invalidCount = 0;
for ii = 1:numel(sources)
    dist = inf(1,nNodes); visited = false(1,nNodes); dist(sources(ii)) = 0;
    for iter = 1:nNodes
        candidate = dist; candidate(visited) = Inf; [best,u] = min(candidate);
        if ~isfinite(best), break; end
        visited(u) = true; dist = min(dist, best + adj(u,:));
    end
    finite = isfinite(dist); values = dist(finite);
    if any(values < 0 | ~isfinite(values)), invalidCount = invalidCount + 1; end
    reachableCount = reachableCount + sum(finite); Csum = Csum + sum(values);
end
end

function value = pct(x, p)
x = sort(double(x(:))); x = x(isfinite(x));
if isempty(x)
    value = NaN;
else
    value = x(max(1,min(numel(x),ceil(p/100*numel(x)))));
end
end

function hash = sha256_numeric(x)
md = java.security.MessageDigest.getInstance('SHA-256');
bytes = typecast(double(x(:)), 'uint8'); md.update(typecast(bytes,'int8'));
digest = typecast(md.digest(), 'uint8');
hash = lower(string(reshape(dec2hex(digest,2).',1,[])));
end
