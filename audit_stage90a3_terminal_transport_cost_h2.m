function [auditTable, summary] = audit_stage90a3_terminal_transport_cost_h2(outputDir)
%AUDIT_STAGE90A3_TERMINAL_TRANSPORT_COST_H2 Audit the formal HTT OD costs.
%
% The terminal LP reuses the ordinary HTT OD matrix. This audit loads the
% formal Stage89Q bridge, records all 12 directed off-diagonal OD costs, and
% reports the conservative maximum over the revealed Stage7 beta states.

rootDir = fileparts(mfilename('fullpath'));
if nargin < 1 || isempty(outputDir)
    outputDir = fullfile(rootDir, 'results', ...
        'task-002-stage2b-b3-smoke', 'stage90a3-terminal-recourse', 'run-001');
end
if ~exist(outputDir, 'dir'); mkdir(outputDir); end

addpath(rootDir);
addpath(fullfile(rootDir, 'fa_h2'));
addpath(fullfile(rootDir, 'fa_h2', 'fuzhu'));
addpath(fullfile(rootDir, 'hourly_grid_h2'));
addpath(fullfile(rootDir, 'fa_msp', 'current_hourly_stage88_candidate', 'config'));
addpath(fullfile(rootDir, 'fa_msp', 'current_hourly_stage88_candidate', 'input'));
addpath(fullfile(rootDir, 'terminalLoh_wdro', 'current_w_mainline_stage89', 'msp_bridge'));

[params, ~, bridgeAudit] = load_current_stage89_hourly_h2(rootDir, "dro");
if ~bridgeAudit.pass
    error('audit_stage90a3:BridgeIdentity', 'Formal Stage89Q bridge identity failed.');
end

Ni = params.Ni;
if Ni ~= 4
    error('audit_stage90a3:SiteCount', 'Expected four terminal sites, found %d.', Ni);
end
baseCost = double(params.cost_transport_base);
distance = double(params.site_to_site_road_km);
if ~isequal(size(baseCost), [Ni Ni]) || ~isequal(size(distance), [Ni Ni])
    error('audit_stage90a3:MatrixShape', 'HTT OD matrices are not 4x4.');
end
if any(~isfinite(baseCost(:))) || any(~isfinite(distance(:))) || ...
        any(baseCost(:) < 0) || any(distance(:) < 0)
    error('audit_stage90a3:BadSource', 'HTT cost source contains invalid values.');
end

terminalStates = find(params.is_loh_demand_stage(:));
if isempty(terminalStates)
    error('audit_stage90a3:NoTerminalStates', 'No Stage7 demand states were found.');
end
beta = double(params.beta(terminalStates));
if any(~isfinite(beta)) || any(beta < -1e-12) || any(beta > 1 + 1e-12)
    error('audit_stage90a3:BadBeta', 'Terminal beta values are invalid.');
end
lambdaBeta = double(params.beta_transport_multiplier);
c0 = double(params.htt_base_service_cost_yuan_per_kg);
if ~isscalar(lambdaBeta) || ~isfinite(lambdaBeta) || lambdaBeta < 0 || ...
        ~isscalar(c0) || ~isfinite(c0) || c0 < 0
    error('audit_stage90a3:BadFormulaParams', 'HTT cost formula parameters are invalid.');
end

rows = cell(Ni * (Ni - 1), 13);
q = 0;
for i = 1:Ni
    for j = 1:Ni
        if i == j; continue; end
        q = q + 1;
        betaCost = c0 + baseCost(i,j) * (1 + lambdaBeta * beta);
        if any(~isfinite(betaCost)) || any(betaCost < 0)
            error('audit_stage90a3:InvalidODCost', ...
                'Invalid terminal unit cost for OD %d->%d.', i, j);
        end
        unitCost = max(betaCost);
        rows(q,:) = {sprintf('Site%d',i), sprintf('Site%d',j), distance(i,j), ...
            unitCost, sprintf('c0 + base_cost(i,j)*(1 + beta_transport_multiplier*beta) = %.12g + %.12g*(1 + %.12g*beta)', ...
                c0, baseCost(i,j), lambdaBeta), ...
            'state-dependent multiplier retained; K_terminal fixed at 160 kg', ...
            min(beta), max(beta), c0, baseCost(i,j), lambdaBeta, ...
            min(betaCost), max(betaCost)};
    end
end
auditTable = cell2table(rows, 'VariableNames', {'origin','destination','distance', ...
    'unit_cost','cost_formula','beta_role','beta_min_terminal','beta_max_terminal', ...
    'c0_yuan_per_kg','base_unit_cost_yuan_per_kg','beta_transport_multiplier', ...
    'unit_cost_min_terminal','unit_cost_max_terminal'});
% Stage90A3 freezes the candidate shortage penalty at 1000 yuan/kg. The
% formal bridge source may carry a historical penalty, so compare against
% the explicit candidate value rather than silently inheriting that source.
penalty = 1000;
if ~isscalar(penalty) || ~isfinite(penalty) || penalty < 0
    error('audit_stage90a3:BadPenalty', 'Terminal shortage penalty is invalid.');
end
if any(~isfinite(auditTable.unit_cost)) || any(auditTable.unit_cost < 0)
    error('audit_stage90a3:InvalidAudit', 'Audit contains NaN, Inf, or negative cost.');
end
if any(auditTable.unit_cost >= penalty)
    error('audit_stage90a3:CostExceedsPenalty', ...
        'At least one terminal OD cost is >= the 1000 yuan/kg shortage penalty.');
end

summary = table(min(auditTable.unit_cost), mean(auditTable.unit_cost), ...
    max(auditTable.unit_cost), penalty, min(auditTable.unit_cost) < penalty, ...
    max(auditTable.unit_cost) < penalty, string(params.nearInputFile), ...
    string(params.terminal_loh_lookup_audit.source_sha256), ...
    'VariableNames', {'min_unit_cost','mean_unit_cost','max_unit_cost', ...
    'terminal_penalty','all_finite_nonnegative','all_below_penalty', ...
    'htt_source_file','terminal_loh_source_sha256'});
writetable(auditTable, fullfile(outputDir, 'terminal_transport_cost_audit.csv'));
writetable(summary, fullfile(outputDir, 'terminal_transport_cost_summary.csv'));
write_readme(outputDir, params, terminalStates, beta, lambdaBeta, c0, penalty, auditTable);
end

function write_readme(outputDir, params, states, beta, lambdaBeta, c0, penalty, T)
path = fullfile(outputDir, 'terminal_transport_cost_audit.md');
fid = fopen(path, 'w');
if fid < 0; error('audit_stage90a3:Write', 'Cannot write %s.', path); end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, '# Stage90A3 terminal transport cost audit\n\n');
fprintf(fid, '- Formal source: `%s` -> `NearStageInput.HTT.site_to_site_base_cost_yuan_per_kg`.\n', params.nearInputFile);
fprintf(fid, '- Base source semantics: `base_cost(i,j) = 0.2 * site_to_site_road_km(i,j)` yuan/kg.\n');
fprintf(fid, '- Active unit cost: `c0 + base_cost(i,j) * (1 + lambda_beta * beta_k)`, with `c0=%.12g`, `lambda_beta=%.12g`.\n', c0, lambdaBeta);
fprintf(fid, '- Reported `unit_cost` is the maximum over Stage7 states `%s`; beta range is `[%.12g, %.12g]`.\n', mat2str(states.'), min(beta), max(beta));
fprintf(fid, '- Terminal capacity is fixed independently at `K_terminal=160 kg`; beta does not block OD and does not degrade K.\n');
fprintf(fid, '- Candidate shortage comparison penalty: `%.12g yuan/kg`; all 12 directed OD costs are strictly below it.\n', penalty);
fprintf(fid, '- Source lookup SHA-256: `%s`.\n', params.terminal_loh_lookup_audit.source_sha256);
fprintf(fid, '- CSV columns include origin, destination, distance, unit_cost, cost_formula, and beta_role.\n');
fprintf(fid, '- min/mean/max terminal unit cost: `%.12g / %.12g / %.12g yuan/kg`.\n', min(T.unit_cost), mean(T.unit_cost), max(T.unit_cost));
end
