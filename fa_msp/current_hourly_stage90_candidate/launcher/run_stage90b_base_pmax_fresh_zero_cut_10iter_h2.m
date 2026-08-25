function run_stage90b_base_pmax_fresh_zero_cut_10iter_h2()
%RUN_STAGE90B_BASE_PMAX_FRESH_ZERO_CUT_10ITER_H2 Stage90B engineering smoke.
%
% Each phase is launched by a separate fresh MATLAB process. The candidate is
% the formal Stage89Q Base Pmax vector with Stage90A terminal recourse enabled
% at the frozen aggregate K_terminal=160 kg. This is exactly ten iterations,
% zero cuts at launch, and no warm start or historical checkpoint.

rootDir = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
runDir = char(strtrim(string(getenv('STAGE90B_RUN_DIR'))));
phase = upper(strtrim(string(getenv('STAGE90B_PHASE'))));
commit = char(strtrim(string(getenv('STAGE90B_SOURCE_COMMIT'))));
if isempty(runDir) || isempty(phase) || isempty(commit)
    error('Stage90B:Environment', 'STAGE90B_RUN_DIR/PHASE/SOURCE_COMMIT are required.');
end

addpath(rootDir); addpath(fullfile(rootDir, 'fa_h2'));
addpath(fullfile(rootDir, 'fa_h2', 'fuzhu'));
addpath(fullfile(rootDir, 'utils'));
addpath(fullfile(rootDir, 'hourly_grid_h2'));
addpath(fullfile(rootDir, 'fa_msp', 'current_hourly_stage88_candidate', 'config'));
addpath(fullfile(rootDir, 'fa_msp', 'current_hourly_stage88_candidate', 'input'));
addpath(fullfile(rootDir, 'terminalLoh_wdro', 'current_w_mainline_stage89', 'msp_bridge'));

switch phase
    case "CONFIG"
        run_config(rootDir, runDir, commit);
    case "TRAIN"
        run_train(rootDir, runDir, commit);
    case "RELOAD"
        run_reload(runDir, commit);
    otherwise
        error('Stage90B:Phase', 'Unknown phase %s.', phase);
end
end

function [p, opts] = load_candidate(rootDir)
[p, opts, audit] = load_current_stage89_hourly_h2(rootDir, "dro");
if ~audit.pass
    error('Stage90B:FormalIdentity', 'Stage89Q formal bridge identity failed.');
end
% The formal bridge may carry the historical source penalty. Stage90B's
% candidate value is explicit and local to this run.
p.cost_reserve_shortage = 1000;
p.NearStageInput.Cost.reserve_shortage_penalty_yuan_per_kg = 1000;
p.terminal_recourse_mode = 'TERMINAL_REDISTRIBUTION';
p.terminal_recourse_enabled = true;
p.K_terminal_kg = 160;
p.terminal_capacity_mapping = 'FROZEN_AGGREGATE_160_KG';
p.stage90b_candidate_id = 'BASE-PMAX-STAGE90B';
opts.seed = 20260513;
if ~isequal(p.el_cap_kw(:).', [300 200 120 150]) || ...
        ~isequal(p.hourly_grid.pmax_kw(:).', [300 200 120 150])
    error('Stage90B:Pmax', 'Base Pmax identity is not [300 200 120 150] kW.');
end
if p.cost_reserve_shortage ~= 1000 || p.K_terminal_kg ~= 160 || ...
        ~strcmp(p.terminal_recourse_mode, 'TERMINAL_REDISTRIBUTION')
    error('Stage90B:CandidateIdentity', 'Stage90B terminal candidate identity failed.');
end
end

function run_config(rootDir, runDir, commit)
[p, opts] = load_candidate(rootDir); %#ok<ASGLU>
lib = define_models_h2(p);
baselineRows = model_row_counts(lib, p);
if cut_count(lib, baselineRows, p) ~= 0
    error('Stage90B:WarmStart', 'CONFIG phase did not start with zero cuts.');
end
rows = {
    'candidate_id', p.stage90b_candidate_id, true;
    'terminal_recourse_mode', p.terminal_recourse_mode, strcmp(p.terminal_recourse_mode, 'TERMINAL_REDISTRIBUTION');
    'K_terminal_kg', p.K_terminal_kg, p.K_terminal_kg == 160;
    'terminal_penalty_yuan_per_kg', p.cost_reserve_shortage, p.cost_reserve_shortage == 1000;
    'Pmax_kw', mat2str(p.el_cap_kw(:).'), isequal(p.el_cap_kw(:).', [300 200 120 150]);
    'training_seed', opts.seed, opts.seed == 20260513;
    'operating_stages', p.hourly_grid.n_operating_stages, p.hourly_grid.n_operating_stages == 6;
    'hours_per_stage', p.hourly_grid.hours_per_stage, p.hourly_grid.hours_per_stage == 8;
    'fresh_initial_cuts', cut_count(lib, baselineRows, p), cut_count(lib, baselineRows, p) == 0;
    'source_commit', commit, true};
T = cell2table(rows, 'VariableNames', {'check','observed','pass'});
safe_writetable(T, fullfile(runDir, '02_config', 'config_identity.csv'));
if ~all(T.pass); error('Stage90B:Config', 'CONFIG identity gate failed.'); end
write_text(fullfile(runDir, '02_config', 'CONFIG_PASS.txt'), ...
    sprintf('status=PASS\ninitial_cuts=0\nK_terminal_kg=160\n'));
end

function run_train(rootDir, runDir, commit)
[p, opts] = load_candidate(rootDir);
rng(opts.seed, 'twister');
lib = define_models_h2(p);
baselineRows = model_row_counts(lib, p);
if cut_count(lib, baselineRows, p) ~= 0
    error('Stage90B:WarmStart', 'TRAIN phase did not start with zero cuts.');
end

x = zeros(p.Ni, p.T); theta = zeros(p.T, 1); lb = 0;
trace = cell(10, 20); terminalRows = cell(10 * p.T, 16); terminalCount = 0;
started = tic; lastPath = zeros(p.T, 1); lastForward = struct();
for iter = 1:10
    iterStart = tic; lastwarn('');
    beforeCuts = cut_count(lib, baselineRows, p);
    [lib, x, theta, lb, path, fwd] = forward_pass_h2(lib, p, lb, x, theta);
    lastPath = path; lastForward = fwd;
    forwardTerminal = collect_forward_terminal_rows(iter, fwd, x, p);
    for rr = 1:size(forwardTerminal, 1)
        terminalCount = terminalCount + 1;
        terminalRows(terminalCount, :) = forwardTerminal(rr, :);
    end
    [lib, cutFlag] = backward_pass_h2(lib, p, x, theta, path); %#ok<ASGLU>
    afterCuts = cut_count(lib, baselineRows, p);
    if afterCuts <= beforeCuts || ~isfinite(lb) || any(~isfinite(x), 'all')
        error('Stage90B:Training', 'Invalid forward/backward result at iteration %d.', iter);
    end
    [stage1, stage1Diag] = solve_reference_stage1(lib, p);
    [warningMessage, warningId] = lastwarn;
    terminalUsed = size(forwardTerminal, 1) > 0;
    terminalShip = sum_numeric_column(forwardTerminal, 7);
    terminalCost = sum_numeric_column(forwardTerminal, 8);
    terminalGap = sum_numeric_column(forwardTerminal, 9);
    terminalBinding = sum_numeric_column(forwardTerminal, 10);
    trace(iter, :) = {'BASE-PMAX-STAGE90B', iter, 10, lb, afterCuts, afterCuts-beforeCuts, ...
        sum(fwd.stageCost), toc(started), toc(iterStart), stage1.production_kg, ...
        terminalUsed, terminalShip, terminalCost, terminalGap, terminalBinding, ...
        stage1Diag.min_voltage_pu, stage1Diag.max_line_utilization, ...
        stage1Diag.max_substation_utilization, stage1Diag.max_htt_utilization, ...
        string(warningId) + ":" + string(warningMessage)};
    safe_writetable(cell2table(trace(1:iter,:), 'VariableNames', trace_names()), ...
        fullfile(runDir, '03_training', 'training_iteration_trace.csv'));
    safe_writetable(cell2table(terminalRows(1:terminalCount,:), ...
        'VariableNames', terminal_names()), ...
        fullfile(runDir, '04_terminal_diagnostics', 'terminal_recourse_forward.csv'));
    safe_writetable(stage1Diag.table, fullfile(runDir, '05_stage_site', ...
        sprintf('stage1_diagnostic_iter%02d.csv', iter)));
    fprintf('Stage90B iteration=%d/10 LB=%.12g cuts=%d terminal_used=%d ship=%.6g\n', ...
        iter, lb, afterCuts, terminalUsed, terminalShip);
end

backwardRows = collect_terminal_state_audit(x(:,6), p);
safe_writetable(backwardRows, fullfile(runDir, '04_terminal_diagnostics', ...
    'terminal_recourse_backward.csv'));

% A one-path OOS call exercises the shared evaluator without turning this
% fixed-budget engineering smoke into a performance experiment.
pOOS = p; pOOS.nbOS = 1; pOOS.store_eval_decisions = false;
oos = eval_h2(lib, pOOS);
oosMode = string(oos.terminal_recourse_mode);
oosRows = table(oosMode, oos.K_terminal_kg, ...
    sum(oos.terminal_redistribution_amount, 'all'), ...
    sum(oos.terminal_redistribution_cost, 'all'), ...
    sum(oos.terminal_reserve_shortage, 'all'), oos.oos_mean, ...
    'VariableNames', {'terminal_recourse_mode','K_terminal_kg', ...
    'redistribution_kg','redistribution_cost_yuan','residual_gap_kg','oos_path_cost'});
safe_writetable(oosRows, fullfile(runDir, '04_terminal_diagnostics', 'oos_terminal_evaluator.csv'));

state = struct('x', x, 'theta', theta, 'LB', cell2mat(trace(:,4)), ...
    'last_training_path', lastPath, 'last_forward_info', lastForward);
[stage1, stage1Diag] = solve_reference_stage1(lib, p);
policy = struct('stage1_x', stage1.xval, 'stage1_production_site', stage1.production_site_kg);
checkpoint_metadata = struct('stage90b_candidate_id', p.stage90b_candidate_id, ...
    'terminal_recourse_mode', p.terminal_recourse_mode, 'K_terminal_kg', p.K_terminal_kg, ...
    'terminal_penalty_yuan_per_kg', p.cost_reserve_shortage, 'candidate_pmax_kw', p.el_cap_kw(:), ...
    'training_seed', opts.seed, 'completed_iterations', 10, 'fresh_initial_cut_count', 0, ...
    'cumulative_cuts', cut_count(lib, baselineRows, p), 'training_wall_time_s', toc(started), ...
    'terminal_forward_records', terminalCount, 'terminal_forward_used', terminalCount > 0, ...
    'oos_terminal_redistribution_kg', sum(oos.terminal_redistribution_amount, 'all'), ...
    'oos_terminal_residual_gap_kg', sum(oos.terminal_reserve_shortage, 'all'), ...
    'source_commit', commit, 'terminal_loh_source_sha256', char(p.terminal_loh_lookup_audit.source_sha256));
result_metadata = struct('final_lb', lb, 'cut_count', cut_count(lib, baselineRows, p), ...
    'stage1_production_kg', stage1.production_kg, ...
    'stage1_end_inventory_kg', stage1.xval(:), 'completed_iterations', 10);
checkpoint = fullfile(runDir, '06_checkpoint', 'checkpoint_final.mat');
save(checkpoint, 'p', 'lib', 'state', 'policy', 'opts', 'checkpoint_metadata', ...
    'result_metadata', '-v7.3');
write_text(fullfile(runDir, '03_training', 'TRAINING_FINISHED.txt'), ...
    sprintf('status=PASS\niterations=10\ninitial_cuts=0\nfinal_cuts=%d\n', ...
    checkpoint_metadata.cumulative_cuts));
write_smoke_readme(runDir, checkpoint_metadata, stage1Diag, trace, oosRows);
end

function run_reload(runDir, commit)
checkpoint = fullfile(runDir, '06_checkpoint', 'checkpoint_final.mat');
if ~isfile(checkpoint); error('Stage90B:Reload', 'Checkpoint is missing.'); end
z = load(checkpoint);
required = {'p','lib','state','policy','opts','checkpoint_metadata','result_metadata'};
names = fieldnames(z);
if ~all(ismember(required, names)); error('Stage90B:ReloadSchema', 'Checkpoint schema is incomplete.'); end
p = z.p; m = z.checkpoint_metadata;
checks = [strcmp(p.terminal_recourse_mode, 'TERMINAL_REDISTRIBUTION'); ...
    p.K_terminal_kg == 160; p.cost_reserve_shortage == 1000; ...
    isequal(p.el_cap_kw(:), [300;200;120;150]); ...
    isequal(p.hourly_grid.pmax_kw(:), [300;200;120;150]); ...
    m.completed_iterations == 10; m.fresh_initial_cut_count == 0; ...
    m.K_terminal_kg == 160; m.terminal_penalty_yuan_per_kg == 1000; ...
    strcmp(m.source_commit, commit); all(isfinite(z.state.LB)); numel(z.state.LB) == 10];
names = {'terminal_mode','K_terminal_160','penalty_1000','params_Pmax', ...
    'hourly_grid_Pmax','iterations_10','fresh_zero_cuts','metadata_K160', ...
    'metadata_penalty1000','source_commit','finite_LB','LB_length_10'};
T = table(string(names(:)), checks(:), 'VariableNames', {'check','pass'});
safe_writetable(T, fullfile(runDir, '07_reload', 'reload_identity.csv'));
if ~all(checks); error('Stage90B:ReloadIdentity', 'Clean reload identity failed.'); end
% One clean post-reload terminal LP call confirms the mode remains active.
k = find(p.is_loh_demand_stage, 1, 'first');
[value, ~, info] = terminal_value_and_subgradient_h2(p.x_0, p, k);
reloadTerminal = table(string(p.terminal_recourse_mode), p.K_terminal_kg, value, ...
    info.total_ship_kg, sum(info.shortage), info.capacity_binding, ...
    'VariableNames', {'terminal_recourse_mode','K_terminal_kg','value_yuan', ...
    'redistribution_kg','residual_gap_kg','capacity_binding'});
safe_writetable(reloadTerminal, fullfile(runDir, '07_reload', 'reload_terminal_identity.csv'));
write_text(fullfile(runDir, '07_reload', 'RELOAD_PASS.txt'), ...
    'status=PASS\nclean_fresh_matlab_reload=YES\nterminal_mode=TERMINAL_REDISTRIBUTION\nK_terminal_kg=160\n');
end

function rows = collect_forward_terminal_rows(iter, fwd, x, p)
rows = cell(0, 16);
for t = 1:p.T
    if string(fwd.status(t)) ~= "loh_demand_stage"; continue; end
    if t == 1; prev = p.x_0; else; prev = x(:, t-1); end
    k = fwd.in_sample(t);
    [value, ~, info] = terminal_value_and_subgradient_h2(prev, p, k);
    rows(end+1,:) = {'BASE-PMAX-STAGE90B', iter, t, k, value, ...
        string(info.terminal_recourse_mode), info.total_ship_kg, info.shipping_cost, ...
        sum(info.shortage), double(info.capacity_binding), info.dual_capacity, ...
        min(info.shortage), max(info.shortage), info.primal_residual, ...
        info.dual_residual, info.complementarity_residual}; %#ok<AGROW>
end
end

function T = collect_terminal_state_audit(xTrial, p)
states = find(p.is_loh_demand_stage(:));
rows = cell(numel(states), 12);
for q = 1:numel(states)
    k = states(q);
    [value, grad, info] = terminal_value_and_subgradient_h2(xTrial, p, k);
    rows(q,:) = {k, value, string(info.terminal_recourse_mode), info.total_ship_kg, ...
        info.shipping_cost, sum(info.shortage), double(info.capacity_binding), ...
        info.dual_capacity, grad(1), grad(2), grad(3), grad(4)};
end
T = cell2table(rows, 'VariableNames', {'state_id','value_yuan','mode', ...
    'redistribution_kg','shipping_cost_yuan','residual_gap_kg','K160_binding', ...
    'dual_capacity','dual_inventory_site1','dual_inventory_site2', ...
    'dual_inventory_site3','dual_inventory_site4'});
end

function [s, diag] = solve_reference_stage1(lib, p)
m = update_rhs_h2(lib.models{1,p.k_init}, p, p.k_init, 1, p.x_0);
s = solve_stage_model_h2(m);
eq = max(abs(m.Aeq*s.xraw-m.beq)); ineq = max([0; m.A*s.xraw-m.b]);
if any(~isfinite(s.xraw)) || eq > 1e-6 || ineq > 1e-6
    error('Stage90B:Stage1QA', 'Stage1 solve failed: eq=%g ineq=%g.', eq, ineq);
end
if isfield(s, 'h2_production_hourly_kg'); siteProd = sum(s.h2_production_hourly_kg,2); else; siteProd = sum(s.rval,2); end
if isfield(s, 'f_hourly_kg'); htt = sum(s.f_hourly_kg, 'all'); else; htt = sum(s.fval(:)); end
v = sqrt(max(s.v_sq,0)); line = hypot(s.p_branch_kw,s.q_branch_kvar)/1000;
diag = struct();
diag.min_voltage_pu = min(v,[],'all');
diag.max_line_utilization = max(line,[],'all')/p.hourly_grid.branch_smax_mva;
diag.max_substation_utilization = max(s.p_grid_kw)/p.hourly_grid.p_substation_max_kw;
diag.max_htt_utilization = htt/max(p.htt_capacity_base,eps);
diag.eq_residual = eq; diag.ineq_residual = ineq;
diag.table = table((1:4).', p.el_cap_kw(:), siteProd(:), s.xval(:), ...
    'VariableNames', {'site','Pmax_kW','production_kg','end_inventory_kg'});
s.production_kg = sum(siteProd); s.production_site_kg = siteProd;
end

function rows = model_row_counts(lib,p)
rows = zeros(6,p.K);
for t = 1:6
    for k = 1:p.K
        if ~isempty(lib.models{t,k}); rows(t,k) = size(lib.models{t,k}.A,1); end
    end
end
end
function n = cut_count(lib, baselineRows, p)
n = sum(max(0, model_row_counts(lib,p)-baselineRows), 'all');
end
function value = sum_numeric_column(rows, col)
if isempty(rows); value = 0; return; end
value = sum(cell2mat(rows(:,col)));
end
function names = trace_names()
names = {'candidate','iteration','iteration_budget','LB','cut_count','cuts_added', ...
    'forward_objective','elapsed_s','iteration_runtime_s','stage1_production_kg', ...
    'terminal_recourse_used','terminal_redistribution_kg','terminal_cost_yuan', ...
    'terminal_residual_gap_kg','K160_binding_count','min_voltage_pu', ...
    'max_line_utilization','max_substation_utilization','max_htt_utilization','warning'};
end
function names = terminal_names()
names = {'candidate','iteration','stage','state_id','value_yuan','mode', ...
    'redistribution_kg','shipping_cost_yuan','residual_gap_kg','K160_binding', ...
    'dual_capacity','min_site_gap_kg','max_site_gap_kg','primal_residual', ...
    'dual_residual','complementarity_residual'};
end
function write_smoke_readme(runDir,m,diag,trace,oos)
used = any(cell2mat(trace(:,11))) || oos.redistribution_kg > 0;
binding = sum(cell2mat(trace(:,15)));
if binding == 0; signal = 'NONE'; elseif binding <= 1; signal = 'LOW'; ...
elseif binding <= 5; signal = 'MODERATE'; else; signal = 'HIGH'; end
fid = fopen(fullfile(runDir,'README.md'),'w'); if fid < 0; error('Stage90B:Write','README'); end
c = onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'# Stage90B Base-Pmax fresh zero-cut 10-iteration smoke\n\n');
fprintf(fid,'- Candidate: Pmax=[300,200,120,150] kW, penalty 1000 yuan/kg, terminal redistribution ON, K_terminal=160 kg.\n');
fprintf(fid,'- Freshness: separate CONFIG/TRAIN/RELOAD MATLAB processes; initial cut count 0; exactly 10 iterations.\n');
fprintf(fid,'- Terminal LP was exercised by forward records, backward state evaluations, and one-path OOS through the shared evaluator.\n');
fprintf(fid,'- TERMINAL_RECOURSE_USED = %s; K160_BINDING_SIGNAL = %s.\n', ternary(used,'YES','NO'), signal);
fprintf(fid,'- Early mechanism signals only: binding count %d; no performance, wait-and-see, or reliability claim is made.\n', binding);
fprintf(fid,'- Stage1 QA: min voltage %.9g, max line utilization %.9g, max substation utilization %.9g, max HTT utilization %.9g.\n', ...
    diag.min_voltage_pu, diag.max_line_utilization, diag.max_substation_utilization, diag.max_htt_utilization);
fprintf(fid,'- NEW_BLOCKING_ISSUE = NO if CONFIG/TRAIN/RELOAD markers and all finite QA files pass.\n');
fprintf(fid,'- Source commit: %s; terminal lookup SHA-256: %s.\n', m.source_commit, m.terminal_loh_source_sha256);
end
function value = ternary(c,a,b); if c; value=a; else; value=b; end; end
function safe_writetable(T,path)
[d,n,e] = fileparts(path); if ~exist(d,'dir'); mkdir(d); end
tmp = fullfile(d,[n,'.tmp',e]); writetable(T,tmp); movefile(tmp,path,'f');
end
function write_text(path,value)
[d,~,~] = fileparts(path); if ~exist(d,'dir'); mkdir(d); end
fid=fopen(path,'w'); if fid<0; error('Stage90B:Write','Cannot write %s.',path); end
c=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s',value);
end
