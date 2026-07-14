function sim = simulate_grid_outage_mc_h2(lineTbl, pFail, PNodeLoadKw, A_site_node, params, Nmc)
%SIMULATE_GRID_OUTAGE_MC_H2 Monte Carlo line outages and connectivity loss.

if Nmc <= 0 || floor(Nmc) ~= Nmc
    error('simulate_grid_outage_mc_h2:BadNmc', 'Nmc must be a positive integer.');
end

Nj = numel(PNodeLoadKw);
Ni = size(A_site_node, 1);
if size(A_site_node, 2) ~= Nj
    error('simulate_grid_outage_mc_h2:BadServiceWeights', ...
        'A_site_node must have one column per grid node.');
end
if numel(pFail) ~= height(lineTbl)
    error('simulate_grid_outage_mc_h2:BadFailureProbabilityLength', ...
        'pFail length must match line table height.');
end

supportHours = get_required_terminal_scalar(params, 'support_hours');
etaFC = get_required_terminal_scalar(params, 'eta_FC');
lhv = get_required_terminal_scalar(params, 'h2_lhv_kWh_per_kg');

failedSamples = rand(Nmc, height(lineTbl)) < pFail(:).';
outageSamples = false(Nmc, Nj);
lostLoadSamples = zeros(Nmc, Nj);
terminalSamples = zeros(Nmc, Ni);

for mm = 1:Nmc
    connected = connected_to_source(Nj, lineTbl.from_node, lineTbl.to_node, ~failedSamples(mm, :));
    outage = ~connected(:).';
    outage(1) = false;
    outageSamples(mm, :) = outage;
    lostLoad = double(outage) .* PNodeLoadKw(:).';
    lostLoadSamples(mm, :) = lostLoad;
    hLost = lostLoad(:) * supportHours / (etaFC * lhv);
    terminalSamples(mm, :) = (A_site_node * hLost).';
end

sim = struct();
sim.failed_samples = failedSamples;
sim.outage_samples = outageSamples;
sim.lost_load_samples_kw = lostLoadSamples;
sim.terminal_loh_samples_kg = terminalSamples;
sim.outage_probability = mean(outageSamples, 1).';
sim.expected_lost_load_by_node_kw = mean(lostLoadSamples, 1).';
sim.expected_H_lost_by_node_kg = sim.expected_lost_load_by_node_kw * supportHours / (etaFC * lhv);
sim.mean_terminal_loh_by_site_kg = mean(terminalSamples, 1).';
sim.terminal_loh_total_samples_kg = sum(terminalSamples, 2);
sim.expected_failed_lines = mean(sum(failedSamples, 2));
sim.expected_outage_nodes = mean(sum(outageSamples, 2));
sim.expected_lost_load_kw = mean(sum(lostLoadSamples, 2));
end

function connected = connected_to_source(Nj, fromNode, toNode, activeLine)
adj = false(Nj, Nj);
for ll = 1:numel(fromNode)
    if activeLine(ll)
        i = fromNode(ll);
        j = toNode(ll);
        adj(i, j) = true;
        adj(j, i) = true;
    end
end

connected = false(Nj, 1);
queue = zeros(Nj, 1);
head = 1;
tail = 1;
queue(tail) = 1;
connected(1) = true;
while head <= tail
    cur = queue(head);
    head = head + 1;
    nbrs = find(adj(cur, :));
    for nn = nbrs
        if ~connected(nn)
            connected(nn) = true;
            tail = tail + 1;
            queue(tail) = nn;
        end
    end
end
end

function val = get_required_terminal_scalar(params, fieldName)
if isfield(params, 'terminal_load_info') && isfield(params.terminal_load_info, fieldName)
    val = double(params.terminal_load_info.(fieldName));
elseif isfield(params, fieldName)
    val = double(params.(fieldName));
else
    error('simulate_grid_outage_mc_h2:MissingTerminalScalar', ...
        'Missing required scalar params.%s or params.terminal_load_info.%s.', ...
        fieldName, fieldName);
end
if ~isscalar(val)
    error('simulate_grid_outage_mc_h2:BadTerminalScalar', '%s must be scalar.', fieldName);
end
end
