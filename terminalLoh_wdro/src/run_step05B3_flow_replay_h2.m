function run_step05B3_flow_replay_h2(runId)
%RUN_STEP05B3_FLOW_REPLAY_H2 Deterministic fixed-policy flow replay.
% This function never trains or changes the saved policies. It evaluates both
% saved model libraries on the exact frozen 10000-row OOS path table and keeps
% only selected aggregate flow/binding diagnostics.

if nargin < 1 || strlength(string(runId)) == 0
    runId = "run-001";
end

rootDir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(rootDir);
addpath(fullfile(rootDir, 'fa_h2'));
addpath(fullfile(rootDir, 'fa_h2', 'fuzhu'));
addpath(fullfile(rootDir, 'utils'));

sourceRun = fullfile(rootDir, 'results', 'task-002-stage2b-b3-smoke', ...
    '57-main-msp-converged-terminal-loh-ab', 'run-003');
outDir = fullfile(rootDir, 'results', 'task-002-stage2b-b3-smoke', ...
    '60-terminal-loh-required-extra-and-flow-audit', char(runId));
classificationFile = fullfile(outDir, 'path_station_abcd_classification.csv');
selectedFile = fullfile(outDir, 'selected_pair_manifest.csv');
flowFile = fullfile(outDir, 'selected_state_flow_trace.csv');
bindingFile = fullfile(outDir, 'selected_state_constraint_binding.csv');
state7MethodFile = fullfile(outDir, 'state7_spillover_method_trace.csv');
integrityFile = fullfile(outDir, 'replay_integrity_audit.txt');

require_file(classificationFile);
require_file(selectedFile);
if isfile(flowFile) || isfile(bindingFile) || isfile(state7MethodFile) || isfile(integrityFile)
    error('run_step05B3_flow_replay_h2:OutputExists', ...
        'Replay output already exists in %s.', outDir);
end

classification = readtable(classificationFile, 'TextType', 'string');
selected = readtable(selectedFile, 'TextType', 'string');
if height(classification) ~= 6053 * 4
    error('run_step05B3_flow_replay_h2:BadClassificationRows', ...
        'Expected 24212 path-site rows, got %d.', height(classification));
end
if any(~ismember(classification.abcd_class, ["A","B","C","D"]))
    error('run_step05B3_flow_replay_h2:BadClass', 'Unexpected A/B/C/D class.');
end

saaWorkspace = fullfile(sourceRun, 'case-saa', 'native_output', 'h2_workspace.mat');
droWorkspace = fullfile(sourceRun, 'case-chi2_eta003', 'native_output', 'h2_workspace.mat');
require_file(saaWorkspace);
require_file(droWorkspace);

[flowSaa, bindSaa, state7Saa, auditSaa, oosFileSaa] = replay_one( ...
    saaWorkspace, "saa", classification, selected);
[flowDro, bindDro, state7Dro, auditDro, oosFileDro] = replay_one( ...
    droWorkspace, "chi2_eta003", classification, selected);

if ~strcmpi(char(oosFileSaa), char(oosFileDro))
    error('run_step05B3_flow_replay_h2:OOSMismatch', ...
        'The saved policies reference different OOS files.');
end

flow = [flowSaa; flowDro];
binding = [bindSaa; bindDro];
state7 = [state7Saa; state7Dro];
writetable(flow, flowFile);
writetable(binding, bindingFile);
writetable(state7, state7MethodFile);

fid = fopen(integrityFile, 'w');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, 'Step-05B-3 deterministic replay integrity audit\n\n');
fprintf(fid, 'No training was performed. eval_h2 was called with each saved modelLib and the unchanged params.oosFile.\n');
fprintf(fid, 'Common OOS file: %s\n', oosFileSaa);
fprintf(fid, 'OOS SHA-256: %s\n', sha256_file(char(oosFileSaa)));
fprintf(fid, 'Selected state-site pairs: %d\n', height(selected));
fprintf(fid, 'SAA replay elapsed seconds: %.12g\n', auditSaa.elapsed);
fprintf(fid, 'DRO replay elapsed seconds: %.12g\n', auditDro.elapsed);
fprintf(fid, 'SAA max errors: saved_final=%.12g, B1_final=%.12g, normal=%.12g, production=%.12g, HTT=%.12g, terminal_state=%d\n', ...
    auditSaa.saved_final_error, auditSaa.b1_final_error, auditSaa.normal_error, ...
    auditSaa.production_error, auditSaa.htt_error, auditSaa.terminal_state_mismatch_count);
fprintf(fid, 'DRO max errors: saved_final=%.12g, B1_final=%.12g, normal=%.12g, production=%.12g, HTT=%.12g, terminal_state=%d\n', ...
    auditDro.saved_final_error, auditDro.b1_final_error, auditDro.normal_error, ...
    auditDro.production_error, auditDro.htt_error, auditDro.terminal_state_mismatch_count);
fprintf(fid, 'Replay PASS: %d\n', auditSaa.pass && auditDro.pass);
fprintf(fid, '\nConstraint interpretation:\n');
fprintf(fid, '- tank binding: end inventory reaches params.x_cap within scaled tolerance.\n');
fprintf(fid, '- electrolyzer binding: e reaches params.el_cap_kw within scaled tolerance.\n');
fprintf(fid, '- HTT binding: aggregate flow reaches max(0,(1-beta)*htt_capacity_base).\n');
fprintf(fid, '- the main MSP has no pairwise hard road-reachability constraint on f(i,j); road stress enters the ordinary LP through beta-dependent aggregate capacity and cost.\n');
clear cleaner;

fprintf('Step-05B-3 deterministic flow replay completed: %s\n', outDir);
end


function [flowTable, bindingTable, state7Table, audit, oosFile] = replay_one( ...
        workspaceFile, method, classification, selected)
loaded = load(workspaceFile, 'params', 'modelLib', 'evalInfo', 'trainInfo');
required = {'params','modelLib','evalInfo','trainInfo'};
for ii = 1:numel(required)
    if ~isfield(loaded, required{ii})
        error('replay_one:MissingWorkspaceField', ...
            'Workspace %s lacks %s.', workspaceFile, required{ii});
    end
end
if loaded.trainInfo.stop_flag ~= 2
    error('replay_one:UnexpectedStopFlag', ...
        'Expected fixed-budget stop_flag=2 in %s.', workspaceFile);
end

p = loaded.params;
if p.nbOS ~= 10000 || p.T ~= 8 || p.Ni ~= 4
    error('replay_one:UnexpectedDimensions', ...
        'Unexpected nbOS/T/Ni in %s.', workspaceFile);
end
p.store_eval_decisions = true;
oosFile = string(p.oosFile);
OOS = readmatrix(oosFile);
OOS = OOS(1:p.nbOS, 1:p.T);

detailed = eval_h2(loaded.modelLib, p);
if detailed.nbOS_used ~= 10000
    error('replay_one:BadReplayRows', 'Replay did not use 10000 paths.');
end

[trace, derived] = build_complete_trace(detailed, p, OOS);
methodRows = classification;

if method == "saa"
    expectedFinalColumns = "I_saa_kg";
    expectedNormal = methodRows.saa_ordinary_shortage_total_kg;
    expectedProduction = methodRows.saa_production_total_kg;
    expectedHtt = methodRows.saa_htt_total_kg;
else
    expectedFinalColumns = "I_dro_kg";
    expectedNormal = methodRows.dro_ordinary_shortage_total_kg;
    expectedProduction = methodRows.dro_production_total_kg;
    expectedHtt = methodRows.dro_htt_total_kg;
end

hitBase = methodRows(methodRows.site == 1, :);
hitPathIds = double(hitBase.path_id);
expectedFinal = nan(numel(hitPathIds), p.Ni);
for site = 1:p.Ni
    rowsSite = methodRows(methodRows.site == site, :);
    [~, order] = ismember(hitPathIds, double(rowsSite.path_id));
    expectedColumn = rowsSite.(char(expectedFinalColumns));
    expectedFinal(:, site) = double(expectedColumn(order));
end

savedFinalError = max(abs(detailed.final_loh(:) - loaded.evalInfo.final_loh(:)));
b1FinalError = max(abs(detailed.final_loh(hitPathIds, :) - expectedFinal), [], 'all');
normalByPath = sum(detailed.normal_shortage, 2);
productionByPath = sum(detailed.production_amount, 2);
httByPath = sum(detailed.transport_amount, 2);
normalError = max(abs(normalByPath(hitPathIds) - double(expectedNormal(methodRows.site == 1))));
productionError = max(abs(productionByPath(hitPathIds) - double(expectedProduction(methodRows.site == 1))));
httError = max(abs(httByPath(hitPathIds) - double(expectedHtt(methodRows.site == 1))));

terminalState = zeros(p.nbOS, 1);
for s = 1:p.nbOS
    if detailed.hit_loh_demand(s)
        terminalState(s) = OOS(s, detailed.first_loh_demand_stage(s));
    end
end
terminalStateMismatch = sum(terminalState(hitPathIds) ~= double(hitBase.terminal_state));

audit = struct();
audit.elapsed = detailed.elapsed;
audit.saved_final_error = savedFinalError;
audit.b1_final_error = b1FinalError;
audit.normal_error = normalError;
audit.production_error = productionError;
audit.htt_error = httError;
audit.terminal_state_mismatch_count = terminalStateMismatch;
audit.pass = max([savedFinalError,b1FinalError,normalError,productionError,httError]) <= 1e-8 ...
    && terminalStateMismatch == 0;
if ~audit.pass
    error('replay_one:ReplayMismatch', ...
        '%s replay failed integrity gates.', method);
end

[flowTable, bindingTable] = aggregate_selected(method, trace, derived, ...
    classification, selected, p);
state7Ids = double(hitBase.path_id(double(hitBase.state_id) == 7));
state7Table = aggregate_state7(method, trace, derived, state7Ids, p);
clear detailed trace derived loaded;
end


function [trace, derived] = build_complete_trace(detailed, p, OOS)
n = p.nbOS;
T = p.T;
Ni = p.Ni;
trace.start_inventory = zeros(n, T, Ni);
trace.end_inventory = zeros(n, T, Ni);
trace.production = zeros(n, T, Ni);
trace.el_power = zeros(n, T, Ni);
trace.served = zeros(n, T, Ni);
trace.shortage = zeros(n, T, Ni);
trace.inflow = zeros(n, T, Ni);
trace.outflow = zeros(n, T, Ni);
trace.active = false(n, T);
trace.terminal_event = false(n, T);
trace.terminal_target = zeros(n, T, Ni);
trace.terminal_gap = zeros(n, T, Ni);
derived.total_htt = zeros(n, T);
derived.htt_capacity = zeros(n, T);
derived.beta = zeros(n, T);
derived.tank_binding = false(n, T, Ni);
derived.el_binding = false(n, T, Ni);
derived.htt_binding = false(n, T);
derived.htt_zero_capacity = false(n, T);

for s = 1:n
    prev = p.x_0(:);
    for t = 1:T
        kk = OOS(s, t);
        beta = p.beta(kk);
        if p.use_beta_capacity
            httCap = max(0, (1 - beta) * p.htt_capacity_base);
        else
            httCap = p.htt_capacity_base;
        end
        derived.beta(s, t) = beta;
        derived.htt_capacity(s, t) = httCap;
        trace.start_inventory(s, t, :) = reshape(prev, 1, 1, []);

        if ~isempty(detailed.xval{s, t})
            x = detailed.xval{s, t}(:);
            e = detailed.eval{s, t}(:);
            r = detailed.rval{s, t}(:);
            f = detailed.fval{s, t};
            u = detailed.u_normal{s, t}(:);
            z = detailed.z_normal{s, t}(:);
            trace.active(s, t) = true;
            trace.end_inventory(s, t, :) = reshape(x, 1, 1, []);
            trace.el_power(s, t, :) = reshape(e, 1, 1, []);
            trace.production(s, t, :) = reshape(r, 1, 1, []);
            trace.served(s, t, :) = reshape(u, 1, 1, []);
            trace.shortage(s, t, :) = reshape(z, 1, 1, []);
            trace.inflow(s, t, :) = reshape(sum(f, 1), 1, 1, []);
            trace.outflow(s, t, :) = reshape(sum(f, 2), 1, 1, []);
            totalFlow = sum(f, 'all');
            derived.total_htt(s, t) = totalFlow;
            for site = 1:Ni
                derived.tank_binding(s, t, site) = is_binding(x(site), p.x_cap(site));
                derived.el_binding(s, t, site) = is_binding(e(site), p.el_cap_kw(site));
            end
            derived.htt_binding(s, t) = is_binding(totalFlow, httCap);
            derived.htt_zero_capacity(s, t) = httCap <= 1e-9;
            prev = x;
        else
            trace.end_inventory(s, t, :) = reshape(prev, 1, 1, []);
            for site = 1:Ni
                derived.tank_binding(s, t, site) = is_binding(prev(site), p.x_cap(site));
            end
        end

        if detailed.hit_loh_demand(s) && detailed.first_loh_demand_stage(s) == t
            trace.terminal_event(s, t) = true;
            target = p.TerminalLOH(:, kk);
            trace.terminal_target(s, t, :) = reshape(target, 1, 1, []);
            trace.terminal_gap(s, t, :) = reshape(max(0, target - prev), 1, 1, []);
        end
    end
end
end


function [flowTable, bindingTable] = aggregate_selected(method, trace, derived, ...
        classification, selected, p)
flowRows = cell(0, 28);
bindingRows = cell(0, 15);
for q = 1:height(selected)
    pairId = double(selected.selected_pair_id(q));
    stateId = double(selected.state_id(q));
    focalSite = double(selected.site(q));
    reason = string(selected.selection_reason(q));
    mask = double(classification.state_id) == stateId & ...
        double(classification.site) == focalSite & ...
        ismember(classification.abcd_class, ["C","D"]);
    pairRows = classification(mask, :);
    pathIds = double(pairRows.path_id);
    cCount = sum(pairRows.abcd_class == "C");
    dCount = sum(pairRows.abcd_class == "D");
    if isempty(pathIds)
        error('aggregate_selected:EmptyPair', ...
            'Selected pair state%d/site%d has no C/D paths.', stateId, focalSite);
    end

    for t = 1:p.T
        active = trace.active(pathIds, t);
        terminalEvent = trace.terminal_event(pathIds, t);
        for site = 1:p.Ni
            startInv = trace.start_inventory(pathIds, t, site);
            endInv = trace.end_inventory(pathIds, t, site);
            production = trace.production(pathIds, t, site);
            elPower = trace.el_power(pathIds, t, site);
            served = trace.served(pathIds, t, site);
            shortage = trace.shortage(pathIds, t, site);
            inflow = trace.inflow(pathIds, t, site);
            outflow = trace.outflow(pathIds, t, site);
            target = trace.terminal_target(pathIds, t, site);
            terminalGap = trace.terminal_gap(pathIds, t, site);
            flowRows(end+1, :) = {pairId,stateId,focalSite,reason,method,numel(pathIds), ...
                cCount,dCount,t,site,sum(active),mean(active),sum(terminalEvent), ...
                mean(terminalEvent),mean(startInv),mean(endInv),mean(production), ...
                mean(elPower),mean(served),mean(shortage),mean(inflow),mean(outflow), ...
                mean(inflow-outflow),mean(derived.total_htt(pathIds,t)), ...
                mean(derived.htt_capacity(pathIds,t)),mean(derived.beta(pathIds,t)), ...
                mean(target),mean(terminalGap)}; %#ok<AGROW>

            bindingRows(end+1, :) = make_binding_row(pairId,stateId,focalSite,reason, ...
                method,t,site,"tank_capacity",numel(pathIds), ...
                derived.tank_binding(pathIds,t,site), ...
                p.x_cap(site)-endInv,false(size(endInv))); %#ok<AGROW>
            bindingRows(end+1, :) = make_binding_row(pairId,stateId,focalSite,reason, ...
                method,t,site,"electrolyzer_capacity",numel(pathIds), ...
                derived.el_binding(pathIds,t,site) & active, ...
                p.el_cap_kw(site)-elPower,~active); %#ok<AGROW>
            bindingRows(end+1, :) = make_binding_row(pairId,stateId,focalSite,reason, ...
                method,t,site,"ordinary_shortage_positive",numel(pathIds), ...
                shortage > 1e-9 & active,-shortage,~active); %#ok<AGROW>
        end
        httSlack = derived.htt_capacity(pathIds,t)-derived.total_htt(pathIds,t);
        bindingRows(end+1, :) = make_binding_row(pairId,stateId,focalSite,reason, ...
            method,t,0,"htt_aggregate_capacity",numel(pathIds), ...
            derived.htt_binding(pathIds,t) & active,httSlack,~active); %#ok<AGROW>
    end
end

flowNames = {'selected_pair_id','focal_state_id','focal_site','selection_reason', ...
    'method','path_count','C_count','D_count','stage','observed_site', ...
    'active_decision_count','active_decision_rate','terminal_event_count', ...
    'terminal_event_rate','mean_start_inventory_kg','mean_end_inventory_kg', ...
    'mean_production_kg','mean_electrolyzer_power_kw','mean_normal_served_kg', ...
    'mean_normal_shortage_kg','mean_htt_inflow_kg','mean_htt_outflow_kg', ...
    'mean_net_htt_inflow_kg','mean_total_htt_flow_kg','mean_htt_capacity_kg', ...
    'mean_beta','mean_terminal_target_kg','mean_terminal_gap_kg'};
flowTable = cell2table(flowRows, 'VariableNames', flowNames);

bindingNames = {'selected_pair_id','focal_state_id','focal_site','selection_reason', ...
    'method','stage','observed_site','constraint_type','path_count', ...
    'eligible_count','binding_count','binding_rate','mean_slack','min_slack', ...
    'max_slack'};
bindingTable = cell2table(bindingRows, 'VariableNames', bindingNames);
end


function row = make_binding_row(pairId,stateId,focalSite,reason,method,t,site, ...
        constraintType,pathCount,binding,slack,ineligible)
eligible = ~ineligible;
eligibleCount = sum(eligible);
if eligibleCount > 0
    eligibleBinding = binding(eligible);
    eligibleSlack = slack(eligible);
    bindCount = sum(eligibleBinding);
    bindRate = mean(eligibleBinding);
    meanSlack = mean(eligibleSlack);
    minSlack = min(eligibleSlack);
    maxSlack = max(eligibleSlack);
else
    bindCount = 0;
    bindRate = NaN;
    meanSlack = NaN;
    minSlack = NaN;
    maxSlack = NaN;
end
row = {pairId,stateId,focalSite,reason,method,t,site,constraintType, ...
    pathCount,eligibleCount,bindCount,bindRate,meanSlack,minSlack,maxSlack};
end


function state7Table = aggregate_state7(method, trace, derived, pathIds, p)
rows = cell(0, 19);
for t = 1:p.T
    active = trace.active(pathIds, t);
    for site = 1:p.Ni
        startInv = trace.start_inventory(pathIds,t,site);
        endInv = trace.end_inventory(pathIds,t,site);
        prod = trace.production(pathIds,t,site);
        served = trace.served(pathIds,t,site);
        shortage = trace.shortage(pathIds,t,site);
        inflow = trace.inflow(pathIds,t,site);
        outflow = trace.outflow(pathIds,t,site);
        rows(end+1,:) = {method,numel(pathIds),t,site,sum(active),mean(active), ...
            mean(startInv),mean(endInv),mean(prod),mean(served),mean(shortage), ...
            mean(inflow),mean(outflow),mean(inflow-outflow), ...
            mean(derived.total_htt(pathIds,t)),mean(derived.htt_capacity(pathIds,t)), ...
            mean(derived.tank_binding(pathIds,t,site)), ...
            mean(derived.el_binding(pathIds,t,site) & active), ...
            mean(derived.htt_binding(pathIds,t) & active)}; %#ok<AGROW>
    end
end
names = {'method','path_count','stage','site','active_decision_count', ...
    'active_decision_rate','mean_start_inventory_kg','mean_end_inventory_kg', ...
    'mean_production_kg','mean_normal_served_kg','mean_normal_shortage_kg', ...
    'mean_htt_inflow_kg','mean_htt_outflow_kg','mean_net_htt_inflow_kg', ...
    'mean_total_htt_flow_kg','mean_htt_capacity_kg','tank_binding_rate', ...
    'electrolyzer_binding_rate','htt_binding_rate'};
state7Table = cell2table(rows, 'VariableNames', names);
end


function tf = is_binding(value, capacity)
tol = 1e-7 * max(1, abs(capacity));
tf = value >= capacity - tol;
end


function require_file(path)
if ~isfile(path)
    error('run_step05B3_flow_replay_h2:MissingFile', ...
        'Missing required file: %s', path);
end
end


function hash = sha256_file(path)
md = java.security.MessageDigest.getInstance('SHA-256');
fid = fopen(path, 'r');
if fid < 0
    error('sha256_file:OpenFailed', 'Could not open %s.', path);
end
cleaner = onCleanup(@() fclose(fid));
while true
    data = fread(fid, 1024*1024, '*uint8');
    if isempty(data)
        break;
    end
    md.update(data);
end
raw = typecast(md.digest(), 'uint8');
hash = lower(reshape(dec2hex(raw,2).',1,[]));
clear cleaner;
end
