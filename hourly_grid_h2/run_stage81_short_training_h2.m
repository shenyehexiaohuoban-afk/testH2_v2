function run_stage81_short_training_h2()
%RUN_STAGE81_SHORT_TRAINING_H2 Execute frozen 600 s SAA/DRO hourly-grid training.

rootDir = fileparts(fileparts(mfilename('fullpath')));
addpath(rootDir);
addpath(fullfile(rootDir, 'fa_h2'));
addpath(fullfile(rootDir, 'fa_h2', 'fuzhu'));
addpath(fullfile(rootDir, 'utils'));
addpath(fullfile(rootDir, 'hourly_grid_h2'));

runId = char(string(getenv('STAGE81_RUN_ID')));
if isempty(runId), runId = 'run-002'; end
if isempty(regexp(runId, '^run-\d{3}$', 'once'))
    error('run_stage81_short_training_h2:BadRunId', 'STAGE81_RUN_ID must be run-xxx.');
end
method = lower(string(getenv('STAGE81_METHOD')));
if ~ismember(method, ["saa", "chi2_eta003"])
    error('run_stage81_short_training_h2:BadMethod', ...
        'STAGE81_METHOD must be saa or chi2_eta003.');
end

runDir = fullfile(rootDir, 'results', 'task-002-stage2b-b3-smoke', ...
    '81-hourly-grid-short-training', runId);
caseDir = fullfile(runDir, "case-" + method);
if ~exist(runDir, 'dir'), mkdir(runDir); end
if exist(caseDir, 'dir')
    error('run_stage81_short_training_h2:OutputExists', ...
        'Refusing to overwrite %s.', caseDir);
end
mkdir(caseDir);
diary(fullfile(caseDir, 'matlab_diary.txt'));

opts = frozen_options(rootDir, method, caseDir);
write_identity(caseDir, opts, method);

try
    rng(opts.seed, 'twister');
    params = load_data_h2_near(opts.dataDir, opts.nearInputFile, opts);
    assert_identity(params, opts, method);
    modelLib = define_models_h2(params);
    assert_model_library(modelLib, params);
    [modelLib, trainInfo, monitor] = train_monitored(modelLib, params);
    checkpointPath = fullfile(caseDir, 'stage81_trained_policy_checkpoint.mat');
    rngStateAfterTraining = rng;
    % Persist the complete trained policy before any post-training
    % diagnostic.  Clear the in-memory copy and reload it so diagnostics
    % mechanically exercise the independently recoverable checkpoint.
    save(checkpointPath, 'params', 'modelLib', 'trainInfo', 'monitor', ...
        'opts', 'rngStateAfterTraining', '-v7.3');
    clear params modelLib trainInfo monitor opts rngStateAfterTraining
    checkpoint = load(checkpointPath);
    [checkpointPass, checkpointAudit] = verify_checkpoint(checkpoint, method);
    write_checkpoint_audit(caseDir, checkpointPath, checkpointAudit);
    if ~checkpointPass
        error('run_stage81_short_training_h2:CheckpointReloadFailure', ...
            'The saved trained-policy checkpoint failed reload verification.');
    end
    params = checkpoint.params;
    modelLib = checkpoint.modelLib;
    trainInfo = checkpoint.trainInfo;
    monitor = checkpoint.monitor;
    opts = checkpoint.opts;
    diagnosis = diagnostic_forward(modelLib, params, opts.seed + 1000);
    [cutCount, cutDimensionPass] = cut_inventory(modelLib, params);
    terminalPass = monitor.stage7_hourly_calls == 0 && ...
        monitor.stage8_hourly_calls == 0 && ...
        all(cellfun(@isempty, modelLib.models(7:8, :)), 'all');
    structuralPass = trainInfo.stop_flag == 2 && monitor.solver_errors == 0 && ...
        monitor.invalid_duals == 0 && monitor.balance_violations == 0 && ...
        monitor.grid_violations == 0 && cutDimensionPass && terminalPass;

    write_outputs(caseDir, method, trainInfo, monitor, diagnosis, ...
        cutCount, cutDimensionPass, terminalPass, structuralPass);
    save(fullfile(caseDir, 'stage81_diagnostic_workspace.mat'), ...
        'diagnosis', 'cutCount', 'cutDimensionPass', 'terminalPass', ...
        'structuralPass', '-v7');
    if ~structuralPass
        error('run_stage81_short_training_h2:StructuralFailure', ...
            'Training completed but failed a frozen structural health check.');
    end
catch ME
    write_failure(caseDir, method, ME);
    rethrow(ME);
end
end

function [pass, audit] = verify_checkpoint(c, expectedMethod)
required = {'params','modelLib','trainInfo','monitor','opts','rngStateAfterTraining'};
hasRequired = all(isfield(c, required));
if ~hasRequired
    audit = struct('has_required_fields', false, 'method_match', false, ...
        'stop_flag', NaN, 'iterations', NaN, 'cut_count', NaN, ...
        'cut_dimension_pass', false, 'stage7_8_empty', false, ...
        'state_dimension', NaN);
    pass = false;
    return;
end
[cuts, cutPass] = cut_inventory(c.modelLib, c.params);
stageEmpty = all(cellfun(@isempty, c.modelLib.models(7:8, :)), 'all');
methodMatch = string(c.params.terminal_loh_mode) == expectedMethod;
audit = struct('has_required_fields', true, 'method_match', methodMatch, ...
    'stop_flag', c.trainInfo.stop_flag, 'iterations', c.trainInfo.iter, ...
    'cut_count', cuts, 'cut_dimension_pass', cutPass, ...
    'stage7_8_empty', stageEmpty, 'state_dimension', c.params.Ni);
pass = methodMatch && c.trainInfo.stop_flag == 2 && ...
    c.trainInfo.iter >= 1 && cuts > 0 && cutPass && stageEmpty && ...
    c.params.Ni == 4 && c.monitor.state_dimension == 4;
end

function write_checkpoint_audit(caseDir, checkpointPath, a)
info = dir(checkpointPath);
fid = fopen(fullfile(caseDir, 'checkpoint_reload_audit.txt'), 'w');
fprintf(fid, 'checkpoint=%s\ncheckpoint_bytes=%d\n', checkpointPath, info.bytes);
fprintf(fid, 'has_required_fields=%d\nmethod_match=%d\n', ...
    a.has_required_fields, a.method_match);
fprintf(fid, 'stop_flag=%g\niterations=%g\ncut_count=%g\n', ...
    a.stop_flag, a.iterations, a.cut_count);
fprintf(fid, 'cut_dimension=%g\ncut_dimension_pass=%d\n', ...
    a.state_dimension, a.cut_dimension_pass);
fprintf(fid, 'stage7_8_models_empty=%d\nreload_pass=%d\n', ...
    a.stage7_8_empty, a.has_required_fields && a.method_match && ...
    a.stop_flag == 2 && a.iterations >= 1 && a.cut_count > 0 && ...
    a.cut_dimension_pass && a.stage7_8_empty && a.state_dimension == 4);
fclose(fid);
end

function opts = frozen_options(rootDir, method, caseDir)
opts = h2_default_options(rootDir);
inputRoot = fullfile(rootDir, 'results', 'task-002-stage2b-b3-smoke', ...
    '73-htt-transport-cost-sensitivity', 'run-001', 'H02');
lookupRoot = fullfile(rootDir, 'results', 'task-002-stage2b-b3-smoke', ...
    '53-35state-saa-vs-eta003-terminal-loh', 'run-024');
opts.nearInputFile = fullfile(inputRoot, "case-" + method, 'sensitivity_input.mat');
opts.dt_h = 8;
opts.time_limit = 600;
opts.max_iter = 100000;
opts.stall = 100000;
opts.cutviol_maxiter = 100000;
opts.eps_tol = 1e-5;
opts.enable_hourly_grid = true;
opts.hourly_grid_vmin_pu = 0.90;
opts.hourly_grid_vmax_pu = 1.10;
opts.outputDir = fullfile(caseDir, 'native_output');
opts.runTraining = true;
opts.runEvaluation = false;
opts.regenOOS = false;
opts.runSelectedPathDiagnostics = false;
opts.store_eval_decisions = false;
opts.seed = 20260513;
opts.allow_zero_terminal_loh = true;
opts.terminal_loh_mode = char(method);
if method == "saa"
    opts.terminal_loh_lookup_file = fullfile(lookupRoot, 'terminal_loh_table_saa.csv');
else
    opts.terminal_loh_lookup_file = fullfile(lookupRoot, 'terminal_loh_table_eta_003.csv');
end
end

function assert_identity(p, opts, method)
expectedPmax = [300; 200; 120; 150];
expectedTank = [300; 200; 100; 150];
expectedBus = [24; 14; 18; 31];
if ~p.enable_hourly_grid || p.T ~= 8 || p.hourly_grid.n_operating_stages ~= 6 || ...
        abs(p.dt_h - 8) > 1e-12 || max(abs(p.el_cap_kw - expectedPmax)) > 1e-12 || ...
        abs(p.k_H2 - 0.0195) > 1e-12 || max(abs(p.x_cap - expectedTank)) > 1e-12 || ...
        abs(p.htt_capacity_base - 160) > 1e-12 || ...
        max(abs(p.hourly_grid.site_elec_bus(:) - expectedBus)) > 0 || ...
        abs(p.hourly_grid.vmin_pu - 0.90) > 1e-12 || ...
        abs(p.hourly_grid.vmax_pu - 1.10) > 1e-12 || ...
        abs(p.hourly_grid.branch_smax_mva - 6) > 1e-12 || ...
        any(abs(p.hourly_grid.pv_cap_kw - 200) > 1e-12) || ...
        abs(p.time_limit - 600) > 1e-12
    error('run_stage81_short_training_h2:IdentityMismatch', ...
        'Runtime parameters differ from the frozen Stage-81 identity.');
end
roadKm = p.site_to_site_road_km;
if max(abs(p.cost_transport_base - 0.2 * roadKm), [], 'all') > 1e-10
    error('run_stage81_short_training_h2:TransportIdentity', 'c_d is not 0.2.');
end
if string(p.terminal_loh_mode) ~= method
    error('run_stage81_short_training_h2:TerminalMode', ...
        'TerminalLOH mode mismatch: expected %s, got %s.', method, p.terminal_loh_mode);
end
if ~isfile(opts.nearInputFile) || ~isfile(opts.terminal_loh_lookup_file)
    error('run_stage81_short_training_h2:MissingFrozenInput', 'Frozen input is missing.');
end
end

function assert_model_library(lib, p)
for t = 1:p.T
    cells = lib.models(t, :);
    if t <= 6
        nonempty = cells(~cellfun(@isempty, cells));
        if isempty(nonempty) || ~all(cellfun(@(m) m.hourly_grid_enabled, nonempty))
            error('run_stage81_short_training_h2:OperatingLibrary', ...
                'Stage %d is not an hourly-grid operating library.', t);
        end
    elseif any(~cellfun(@isempty, cells))
        error('run_stage81_short_training_h2:TerminalLibrary', ...
            'Stage %d must not contain an operating LP.', t);
    end
end
end

function [lib, info, mon] = train_monitored(lib, p)
LB = zeros(0, 1); x = zeros(p.Ni, p.T); theta = zeros(p.T, 1);
lb = 0; iter = 0; cutviolIter = 0; startTime = tic;
mon = initialize_monitor(p);
while true
    iter = iter + 1;
    [lib, x, theta, lb, path, fwd] = forward_pass_h2(lib, p, lb, x, theta);
    mon.forward_passes = mon.forward_passes + 1;
    mon.forward_operating_solves = mon.forward_operating_solves + nnz(fwd.status == "normal");
    mon.terminal_hits = mon.terminal_hits + nnz(fwd.status == "loh_demand_stage");
    mon.absorbing_hits = mon.absorbing_hits + nnz(fwd.status == "absorbing_lfNc");
    LB(end + 1, 1) = lb; %#ok<AGROW>
    elapsed = toc(startTime);
    fprintf('Stage81 H2 Iter %d: LB=%.12g elapsed=%.3fs\n', iter, lb, elapsed);
    if elapsed > p.time_limit
        stopFlag = 2;
        break;
    end
    before = total_model_solves_expected(p);
    [lib, cutFlag] = backward_pass_h2(lib, p, x, theta, path);
    mon.backward_passes = mon.backward_passes + 1;
    mon.backward_operating_solves = mon.backward_operating_solves + before;
    mon.inventory_dual_checks = mon.inventory_dual_checks + before;
    if cutFlag == 1, cutviolIter = 0; else, cutviolIter = cutviolIter + 1; end
end
info = struct('LB', LB, 'train_time', elapsed, 'iter', iter, ...
    'terminate_flag', stopFlag, 'stop_flag', stopFlag, ...
    'relative_gap', inf, 'last_xval', x, 'last_thetaval', theta, ...
    'last_forward', fwd, 'cutviol_iter', cutviolIter);
mon.wall_time_s = elapsed;
mon.stage7_hourly_calls = 0;
mon.stage8_hourly_calls = 0;
end

function n = total_model_solves_expected(p)
n = 0;
for t = 2:p.hourly_grid.n_operating_stages
    n = n + nnz(~p.is_absorbing & ~p.is_loh_demand_stage);
end
end

function mon = initialize_monitor(p)
mon = struct('forward_passes', 0, 'backward_passes', 0, ...
    'forward_operating_solves', 0, 'backward_operating_solves', 0, ...
    'inventory_dual_checks', 0, 'terminal_hits', 0, 'absorbing_hits', 0, ...
    'solver_errors', 0, 'invalid_duals', 0, 'balance_violations', 0, ...
    'grid_violations', 0, 'stage7_hourly_calls', 0, ...
    'stage8_hourly_calls', 0, 'wall_time_s', 0, 'state_dimension', p.Ni);
end

function d = diagnostic_forward(lib, p, seed)
rng(seed, 'twister');
nPaths = 40;
siteProd = zeros(nPaths, 4); siteEndInv = zeros(nPaths, 4);
sitePelSum = zeros(nPaths, 4); sitePelN = zeros(nPaths, 4);
siteFull = zeros(nPaths, 4); siteGridLimited = zeros(nPaths, 4);
siteHttIn = zeros(nPaths, 4); siteHttOut = zeros(nPaths, 4);
siteShortage = zeros(nPaths, 4);
htt = zeros(nPaths, 1); shortage = zeros(nPaths, 1);
pvAvail = zeros(nPaths, 1); pvUsed = zeros(nPaths, 1);
minV = inf; minBus = NaN; minTau = NaN; maxV = -inf;
maxUtil = -inf; maxTrueS = -inf;
tightFrom = NaN; tightTo = NaN; tightTau = NaN;
nearV = 0; nearBranch = 0; maxEq = 0; maxIneq = 0;
maxInv = 0; maxHtt = 0;
maxPVIdentityError = 0; maxPVBoundViolation = 0;
terminalBad = 0; operatingSolves = 0;
for q = 1:nPaths
    prev = p.x_0; k = p.k_init; absorbed = false;
    siteEndInv(q, :) = prev.';
    for t = 1:p.T
        if t > 1, k = mc_sample(k, p.P_joint); end
        if absorbed, continue; end
        if p.is_dissipated(k) || p.is_absorbing(k)
            absorbed = true; continue;
        end
        if p.is_loh_demand_stage(k)
            absorbed = true; continue;
        end
        if t > 6
            terminalBad = terminalBad + 1; continue;
        end
        m = update_rhs_h2(lib.models{t, k}, p, k, t, prev);
        s = solve_stage_model_h2(m); operatingSolves = operatingSolves + 1;
        eq = m.Aeq * s.xraw - m.beq; ineq = m.A * s.xraw - m.b;
        v = sqrt(max(s.v_sq, 0)); trueS = hypot(s.p_branch_kw, s.q_branch_kvar) / 1000;
        maxEq = max(maxEq, max(abs(eq)));
        maxIneq = max(maxIneq, max([0; ineq]));
        maxV = max(maxV, max(v, [], 'all'));
        invRes = eq(m.rowMap.inventory_eq); maxInv = max(maxInv, max(abs(invRes)));
        maxHtt = max(maxHtt, max([0; ineq(m.rowMap.htt_capacity)]));
        [v0, ix] = min(v(:)); [bus, h] = ind2sub(size(v), ix);
        tau = 8 * (t - 1) + h;
        if v0 < minV, minV = v0; minBus = bus; minTau = tau; end
        [u0, ix] = max(trueS(:) / p.hourly_grid.branch_smax_mva);
        [ell, h2] = ind2sub(size(trueS), ix);
        if u0 > maxUtil
            maxUtil = u0; maxTrueS = trueS(ell, h2);
            tightFrom = p.hourly_grid.branch_from(ell);
            tightTo = p.hourly_grid.branch_to(ell); tightTau = 8 * (t - 1) + h2;
        end
        nearV = nearV + nnz(v <= p.hourly_grid.vmin_pu + 1e-5);
        nearBranch = nearBranch + nnz(trueS / p.hourly_grid.branch_smax_mva >= 0.999);
        siteProd(q, :) = siteProd(q, :) + s.rval.';
        siteEndInv(q, :) = s.xval.';
        htt(q) = htt(q) + sum(s.fval, 'all');
        shortage(q) = shortage(q) + sum(s.z_normal);
        siteHttIn(q, :) = siteHttIn(q, :) + sum(s.fval, 1);
        siteHttOut(q, :) = siteHttOut(q, :) + sum(s.fval, 2).';
        siteShortage(q, :) = siteShortage(q, :) + s.z_normal.';
        sitePelSum(q, :) = sitePelSum(q, :) + sum(s.p_el_hourly_kw, 2).';
        sitePelN(q, :) = sitePelN(q, :) + size(s.p_el_hourly_kw, 2);
        siteFull(q, :) = siteFull(q, :) + sum(s.p_el_hourly_kw >= p.el_cap_kw - 1e-6, 2).';
        for site = 1:p.Ni
            bus = p.hourly_grid.site_elec_bus(site);
            for hSite = 1:8
                belowPmax = s.p_el_hourly_kw(site, hSite) < p.el_cap_kw(site) - 1e-6;
                voltageTight = v(bus, hSite) <= p.hourly_grid.vmin_pu + 1e-5;
                branchTight = max(trueS(:, hSite)) / ...
                    p.hourly_grid.branch_smax_mva >= 0.999;
                siteGridLimited(q, site) = siteGridLimited(q, site) + ...
                    double(belowPmax && (voltageTight || branchTight));
            end
        end
        tauVec = 8 * (t - 1) + (1:8);
        pvCapacityBySite = p.hourly_grid.pv_cap_kw(:);
        pvProfileByHour = p.hourly_grid.phi48(tauVec(:)).';
        if ~isequal(size(pvCapacityBySite), [p.Ni, 1]) || ...
                ~isequal(size(pvProfileByHour), [1, 8])
            error('run_stage81_short_training_h2:PVDiagnosticShape', ...
                ['PV diagnostic expects a site column (%d-by-1) and an ' ...
                'hour row (1-by-8); got %s and %s.'], p.Ni, ...
                mat2str(size(pvCapacityBySite)), mat2str(size(pvProfileByHour)));
        end
        avail = pvCapacityBySite * pvProfileByHour;
        if ~isequal(size(avail), size(s.p_pv_kw))
            error('run_stage81_short_training_h2:PVDiagnosticSemanticMismatch', ...
                'PV available and utilized arrays must share site-by-hour size.');
        end
        curtailed = avail - s.p_pv_kw;
        maxPVIdentityError = max(maxPVIdentityError, ...
            max(abs(avail - s.p_pv_kw - curtailed), [], 'all'));
        maxPVBoundViolation = max(maxPVBoundViolation, ...
            max([0; s.p_pv_kw(:) - avail(:); -s.p_pv_kw(:)]));
        pvAvail(q) = pvAvail(q) + sum(avail, 'all');
        pvUsed(q) = pvUsed(q) + sum(s.p_pv_kw, 'all');
        prev = s.xval;
    end
end
d = struct();
d.n_paths = nPaths; d.operating_solves = operatingSolves;
d.production_mean = mean(siteProd, 1); d.inventory_mean = mean(siteEndInv, 1);
d.htt_in_mean = mean(siteHttIn, 1); d.htt_out_mean = mean(siteHttOut, 1);
d.shortage_site_mean = mean(siteShortage, 1);
d.htt_mean = mean(htt); d.shortage_mean = mean(shortage);
d.p_el_mean_kw = sum(sitePelSum, 1) ./ max(1, sum(sitePelN, 1));
d.full_power_frequency = sum(siteFull, 1) ./ max(1, sum(sitePelN, 1));
d.grid_limited_frequency = sum(siteGridLimited, 1) ./ max(1, sum(sitePelN, 1));
d.pv_available_mean_kwh = mean(pvAvail); d.pv_used_mean_kwh = mean(pvUsed);
d.pv_curtailed_mean_kwh = mean(pvAvail - pvUsed);
d.pv_utilization = sum(pvUsed) / max(eps, sum(pvAvail));
d.pv_identity_max_error_kwh = maxPVIdentityError;
d.pv_bound_max_violation_kw = maxPVBoundViolation;
d.min_voltage_pu = minV; d.min_voltage_bus = minBus; d.min_voltage_hour = minTau;
d.max_voltage_pu = maxV;
d.max_true_s_mva = maxTrueS;
d.max_branch_utilization = maxUtil; d.tight_from = tightFrom; d.tight_to = tightTo;
d.tight_hour = tightTau; d.voltage_near_binding_count = nearV;
d.branch_near_binding_count = nearBranch; d.max_eq_error = maxEq;
d.max_ineq_violation = maxIneq;
d.max_inventory_error = maxInv; d.max_htt_violation = maxHtt;
d.terminal_semantics_errors = terminalBad;
end

function [count, dimensionPass] = cut_inventory(lib, p)
count = 0; dimensionPass = true;
for t = 1:p.T
    for k = 1:p.K
        m = lib.models{t, k};
        if isempty(m), continue; end
        baseRows = p.Ni + 1;
        if isfield(m, 'hourly_grid_enabled') && m.hourly_grid_enabled
            baseRows = baseRows + 8 * 8 * p.hourly_grid.n_branch;
        end
        count = count + max(0, size(m.A, 1) - baseRows);
        for r = (baseRows + 1):size(m.A, 1)
            allowed = false(1, m.nvars); allowed(m.idx.x) = true;
            allowed(m.idx.theta) = true;
            dimensionPass = dimensionPass && numel(m.idx.x) == 4 && ...
                nnz(m.A(r, ~allowed)) == 0;
        end
    end
end
end

function write_identity(caseDir, opts, method)
fid = fopen(fullfile(caseDir, 'training_identity.txt'), 'w');
fprintf(fid, 'method=%s\nrequested_budget_s=600\nseed=20260513\n', method);
[status, sourceCommit] = system('git rev-parse HEAD');
if status ~= 0, sourceCommit = 'UNKNOWN'; end
fprintf(fid, 'source_commit=%s\n', strtrim(sourceCommit));
fprintf(fid, 'input=%s\nterminal_lookup=%s\n', opts.nearInputFile, opts.terminal_loh_lookup_file);
fprintf(fid, 'enable_hourly_grid=true\ndt_h=8\noperating_stages=1-6\n');
fprintf(fid, 'stage7=TerminalLOH_analytic\nstage8=absorbing_zero\n');
fprintf(fid, 'voltage_pu=[0.90,1.10]\nbranch_smax_mva=6\n');
fprintf(fid, 'site_bus=[24,14,18,31]\nc_d=0.2\n');
fclose(fid);
end

function write_outputs(dirName, method, ti, m, d, cuts, cutPass, terminalPass, pass)
diagnosticPass = d.min_voltage_pu >= 0.90 - 1e-8 && ...
    d.max_voltage_pu <= 1.10 + 1e-8 && ...
    d.max_branch_utilization <= 1 + 1e-8 && ...
    d.max_eq_error <= 1e-6 && d.max_ineq_violation <= 1e-8 && ...
    d.max_inventory_error <= 1e-6 && ...
    d.max_htt_violation <= 1e-8 && d.pv_bound_max_violation_kw <= 1e-8 && ...
    d.pv_identity_max_error_kwh <= 1e-8 && ...
    d.terminal_semantics_errors == 0;
pass = pass && diagnosticPass && cutPass && terminalPass;
summary = table(method, 600, ti.train_time, ti.iter, m.forward_passes, ...
    m.backward_passes, cuts, m.forward_operating_solves, ...
    m.backward_operating_solves, ti.LB(end), ti.stop_flag, ...
    m.solver_errors, pass, 'VariableNames', {'method','requested_budget_s', ...
    'actual_wall_time_s','iterations','forward_passes','backward_passes', ...
    'cut_count','forward_operating_solves','backward_operating_solves', ...
    'final_LB','stop_flag','solver_errors','structural_pass'});
writetable(summary, fullfile(dirName, 'training_summary.csv'));
lbTrace = table((1:numel(ti.LB)).', ti.LB(:), ...
    'VariableNames', {'iteration','LB'});
writetable(lbTrace, fullfile(dirName, 'lb_trace.csv'));
health = struct2table(m); writetable(health, fullfile(dirName, 'solver_health.csv'));
site = (1:4).';
electro = table(site, d.p_el_mean_kw.', d.full_power_frequency.', ...
    d.grid_limited_frequency.', 'VariableNames', {'site','average_p_el_kw', ...
    'full_power_frequency','grid_limited_frequency'});
writetable(electro, fullfile(dirName, 'electrolyzer_site_diagnostics.csv'));
h2 = table(site, d.production_mean.', d.inventory_mean.', ...
    d.htt_in_mean.', d.htt_out_mean.', d.shortage_site_mean.', ...
    repmat(d.htt_mean,4,1), repmat(d.shortage_mean,4,1), ...
    'VariableNames', {'site','production_mean_kg','end_inventory_mean_kg', ...
    'htt_in_mean_kg','htt_out_mean_kg','ordinary_shortage_site_mean_kg', ...
    'total_htt_mean_kg_path','ordinary_shortage_mean_kg_path'});
writetable(h2, fullfile(dirName, 'h2_decision_summary.csv'));
grid = table(d.n_paths, d.operating_solves, d.min_voltage_pu, ...
    d.min_voltage_bus, d.min_voltage_hour, d.max_voltage_pu, ...
    d.voltage_near_binding_count, ...
    d.max_true_s_mva, d.max_branch_utilization, d.tight_from, d.tight_to, d.tight_hour, ...
    d.branch_near_binding_count, d.max_eq_error, d.max_ineq_violation, ...
    d.max_inventory_error, ...
    d.max_htt_violation, d.terminal_semantics_errors, ...
    'VariableNames', {'diagnostic_paths','operating_solves','min_voltage_pu', ...
    'min_voltage_bus','min_voltage_hour','max_voltage_pu', ...
    'voltage_near_binding_count', ...
    'max_true_s_mva','max_branch_utilization','tight_from','tight_to','tight_hour', ...
    'branch_near_binding_count','max_eq_error','max_ineq_violation', ...
    'max_inventory_error', ...
    'max_htt_violation','terminal_semantics_errors'});
writetable(grid, fullfile(dirName, 'hourly_grid_training_diagnostics.csv'));
pv = table(d.pv_available_mean_kwh, d.pv_used_mean_kwh, ...
    d.pv_curtailed_mean_kwh, d.pv_utilization, ...
    d.pv_identity_max_error_kwh, d.pv_bound_max_violation_kw, ...
    'VariableNames', {'available_pv_mean_kwh_path','used_pv_mean_kwh_path', ...
    'curtailed_pv_mean_kwh_path','pv_utilization_ratio', ...
    'available_equals_used_plus_curtailed_max_error_kwh', ...
    'pv_bound_max_violation_kw'});
writetable(pv, fullfile(dirName, 'pv_training_diagnostics.csv'));
fid = fopen(fullfile(dirName, 'cut_dimension_audit.txt'), 'w');
fprintf(fid, 'cut_count=%d\ncut_dimension=4\ncut_dimension_pass=%d\n', cuts, cutPass);
fprintf(fid, 'state_order=[I1,I2,I3,I4]\nstage7_8_terminal_pass=%d\n', terminalPass);
fclose(fid);
fid = fopen(fullfile(dirName, 'TRAIN_DONE.txt'), 'w');
fprintf(fid, 'status=%s\nmethod=%s\nstop_flag=%d\niterations=%d\n', ...
    ternary(pass, 'PASS', 'FAIL'), method, ti.stop_flag, ti.iter);
fprintf(fid, 'train_time_s=%.12g\ncut_count=%d\ncompleted_at=%s\n', ...
    ti.train_time, cuts, datestr(now, 31));
fclose(fid);
end

function write_failure(dirName, method, ME)
fid = fopen(fullfile(dirName, 'TRAIN_FAILED.txt'), 'w');
fprintf(fid, 'status=FAIL\nmethod=%s\nidentifier=%s\nmessage=%s\n', ...
    method, ME.identifier, ME.message);
for i = 1:numel(ME.stack)
    fprintf(fid, 'stack_%d=%s:%d\n', i, ME.stack(i).name, ME.stack(i).line);
end
fclose(fid);
end

function out = ternary(cond, a, b)
if cond, out = a; else, out = b; end
end
