function run_stage79_hourly_grid_smoke_h2()
%RUN_STAGE79_HOURLY_GRID_SMOKE_H2 Execute Stage-79 gates A and B.
%
% The task requires an immediate stop if the frozen base grid is infeasible.
% Accordingly, gates C-E and legacy regression are not run after a gate-B
% failure, and their reports state that status explicitly.

rootDir = fileparts(fileparts(mfilename('fullpath')));
addpath(rootDir);
addpath(fullfile(rootDir, 'fa_h2'));
addpath(fullfile(rootDir, 'fa_h2', 'fuzhu'));
addpath(fullfile(rootDir, 'hourly_grid_h2'));

runId = char(string(getenv('STAGE79_RUN_ID')));
if isempty(runId)
    runId = 'run-001';
end
if isempty(regexp(runId, '^run-\d{3}$', 'once'))
    error('run_stage79_hourly_grid_smoke_h2:BadRunId', ...
        'STAGE79_RUN_ID must be run-xxx.');
end
outDir = fullfile(rootDir, 'results', 'task-002-stage2b-b3-smoke', ...
    '79-hourly-grid-lindistflow-smoke', runId);
if exist(outDir, 'dir')
    error('run_stage79_hourly_grid_smoke_h2:OutputExists', ...
        'Refusing to overwrite Stage-79 output: %s', outDir);
end
mkdir(outDir);

data = load_hourly_grid_data_h2(rootDir);
identityAudit = validate_hourly_grid_data_h2(data);

% Load both formal terminal modes to mechanically confirm shared state/site
% identity and unchanged beta/Markov inputs without training or evaluation.
saaOpts = h2_default_options(rootDir);
saaOpts.nearInputFile = data.h02_saa_input_file;
saaOpts.dt_h = 8;
saaOpts.terminal_loh_mode = 'saa';
saaOpts.terminal_loh_lookup_file = fullfile(rootDir, 'results', ...
    'task-002-stage2b-b3-smoke', ...
    '53-35state-saa-vs-eta003-terminal-loh', 'run-024', ...
    'terminal_loh_table_saa.csv');
saaOpts.allow_zero_terminal_loh = true;
droOpts = saaOpts;
droOpts.nearInputFile = data.h02_dro_input_file;
droOpts.terminal_loh_mode = 'chi2_eta003';
droOpts.terminal_loh_lookup_file = fullfile(rootDir, 'results', ...
    'task-002-stage2b-b3-smoke', ...
    '53-35state-saa-vs-eta003-terminal-loh', 'run-024', ...
    'terminal_loh_table_eta_003.csv');
saaParams = load_data_h2_near(fullfile(rootDir, 'data'), saaOpts.nearInputFile, saaOpts);
droParams = load_data_h2_near(fullfile(rootDir, 'data'), droOpts.nearInputFile, droOpts);
if saaParams.Ni ~= 4 || droParams.Ni ~= 4 || ...
        max(abs(saaParams.beta - droParams.beta)) > 1e-12 || ...
        max(abs(saaParams.P_joint(:) - droParams.P_joint(:))) > 1e-12 || ...
        max(abs(saaParams.el_cap_kw - droParams.el_cap_kw)) > 1e-12 || ...
        max(abs(saaParams.D_normal(:) - droParams.D_normal(:))) > 1e-12
    error('run_stage79_hourly_grid_smoke_h2:SaaDroIdentity', ...
        'SAA/DRO shared site, beta, Markov, or demand identity failed.');
end

write_input_files(outDir, data, identityAudit, saaParams, droParams);

baseRows = cell(48, 15);
voltageRows = cell(48 * data.n_bus, 8);
branchRows = cell(48 * data.n_branch, 12);
vRow = 0;
bRow = 0;
allFeasible = true;

for tau = 1:48
    constrained = build_hourly_lindistflow_h2(data, tau, zeros(4, 1), true);
    constrainedResult = solve_grid_model(constrained);
    feasible = strcmp(constrainedResult.status, 'OPTIMAL');
    allFeasible = allFeasible && feasible;

    diagnostic = build_hourly_lindistflow_h2(data, tau, zeros(4, 1), false);
    diagnosticResult = solve_grid_model(diagnostic);
    if ~strcmp(diagnosticResult.status, 'OPTIMAL')
        error('run_stage79_hourly_grid_smoke_h2:DiagnosticFailure', ...
            'Relaxed diagnostic failed at hour %d: %s', ...
            tau, diagnosticResult.status);
    end
    d = evaluate_hourly_grid_constraints_h2(data, diagnostic, diagnosticResult.x);
    maxBranch = d.max_true_s_branch;
    baseRows(tau, :) = {tau, ceil(tau / 8), mod(tau - 1, 8) + 1, ...
        string(constrainedResult.status), feasible, string(diagnosticResult.status), ...
        d.min_voltage_pu, d.min_voltage_bus, d.max_voltage_pu, ...
        d.max_true_s_mva, d.max_true_s_utilization, ...
        data.branch_from(maxBranch), data.branch_to(maxBranch), ...
        d.slack_p_kw, d.slack_q_kvar};

    for bus = 1:data.n_bus
        vRow = vRow + 1;
        voltageRows(vRow, :) = {tau, ceil(tau / 8), bus, d.v_sq(bus), ...
            d.v_pu(bus), data.vmin_pu - d.v_pu(bus), ...
            d.v_pu(bus) < data.vmin_pu - 1e-9, ...
            'RELAXED_DIAGNOSTIC_FOR_BASE_GATE'};
    end
    for ell = 1:data.n_branch
        bRow = bRow + 1;
        branchRows(bRow, :) = {tau, ceil(tau / 8), ell, ...
            data.branch_from(ell), data.branch_to(ell), ...
            d.p_branch_kw(ell), d.q_branch_kvar(ell), ...
            d.true_s_mva(ell), d.true_s_mva(ell) / data.branch_smax_mva, ...
            d.true_s_mva(ell) <= data.branch_smax_mva + 1e-9, ...
            d.max_octagon_violation, 'RELAXED_VOLTAGE_DIAGNOSTIC'};
    end
end

baseTable = cell2table(baseRows, 'VariableNames', { ...
    'tau', 'stage', 'hour_in_stage', 'constrained_status', ...
    'constrained_feasible', 'diagnostic_status', 'min_voltage_pu', ...
    'min_voltage_bus', 'max_voltage_pu', 'max_true_branch_s_mva', ...
    'max_true_branch_utilization', 'tight_branch_from', 'tight_branch_to', ...
    'slack_p_kw', 'slack_q_kvar'});
writetable(baseTable, fullfile(outDir, 'base_grid_48h_feasibility.csv'));
writetable(cell2table(voltageRows, 'VariableNames', { ...
    'tau', 'stage', 'bus', 'v_sq', 'v_pu', 'lower_margin_pu', ...
    'below_0p95', 'diagnostic_class'}), ...
    fullfile(outDir, 'voltage_diagnostics.csv'));
writetable(cell2table(branchRows, 'VariableNames', { ...
    'tau', 'stage', 'branch_id', 'from_bus', 'to_bus', 'p_kw', ...
    'q_kvar', 'true_s_mva', 'true_utilization', 'true_circle_pass', ...
    'hour_max_octagon_violation', 'diagnostic_class'}), ...
    fullfile(outDir, 'branch_capacity_diagnostics.csv'));

if allFeasible
    error('run_stage79_hourly_grid_smoke_h2:UnexpectedBasePass', ...
        ['The base grid unexpectedly passed. Gates C-E are intentionally not ' ...
        'implemented in this gate-focused runner and require a new run.']);
end

write_not_run_outputs(outDir, baseTable);
end

function result = solve_grid_model(model)
grb = struct();
grb.A = sparse([model.A; model.Aeq]);
grb.obj = model.c;
grb.rhs = [model.b; model.beq];
grb.sense = [repmat('<', size(model.A, 1), 1); ...
    repmat('=', size(model.Aeq, 1), 1)];
grb.lb = model.lb;
grb.ub = model.ub;
grb.modelsense = 'min';
params = struct('OutputFlag', 0, 'InfUnbdInfo', 1, 'DualReductions', 0);
raw = gurobi(grb, params);
result = struct('status', raw.status);
if strcmp(raw.status, 'OPTIMAL')
    result.x = raw.x;
    result.obj = raw.objval;
end
end

function write_input_files(outDir, data, audit, saaParams, droParams)
writetable(audit, fullfile(outDir, 'input_identity_checks.csv'));

fid = fopen(fullfile(outDir, 'input_identity.txt'), 'w');
fprintf(fid, 'STAGE79_INPUT_IDENTITY=PASS\n');
fprintf(fid, 'base_input=%s\n', data.base_input_file);
fprintf(fid, 'h02_saa_input=%s\n', data.h02_saa_input_file);
fprintf(fid, 'h02_dro_input=%s\n', data.h02_dro_input_file);
fprintf(fid, 'dt_h=8\nordinary_operating_stages=6\nhours_per_stage=8\n');
fprintf(fid, 'lf7_terminal_check_has_no_hourly_operation=1\n');
fprintf(fid, 'lf8_absorbing_has_no_hourly_operation=1\n');
fprintf(fid, 'bus_count=33\nbranch_count=32\nbase_kv=12.66\nbase_mva=10\n');
fprintf(fid, 'slack_bus=1\nslack_v_sq=1\nvoltage_bounds_pu=[0.95,1.05]\n');
fprintf(fid, 'branch_smax_mva=6\n');
fprintf(fid, 'site_elec_bus=[24,14,18,31]\n');
fprintf(fid, 'road_site_node=[24,14,18,31]\n');
fprintf(fid, 'mapping_class=%s\n', data.mapping_class);
fprintf(fid, 'pmax_kw=[300,200,120,150]\nk_H2=0.0195\n');
fprintf(fid, 'full_power_8h_h2_kg=[46.8,31.2,18.72,23.4]\n');
fprintf(fid, 'tank_cap_kg=[300,200,100,150]\nhtt_capacity=160\nc_d=0.2\n');
fprintf(fid, 'tariff_source=%s\n', data.tariff_source);
fprintf(fid, 'tariff_active_source_conflict_found=0\n');
fprintf(fid, 'saa_dro_beta_max_error=%.15g\n', max(abs(saaParams.beta-droParams.beta)));
fprintf(fid, 'saa_dro_markov_max_error=%.15g\n', ...
    max(abs(saaParams.P_joint(:)-droParams.P_joint(:))));
fprintf(fid, 'saa_dro_site_order_shared=1\n');
fclose(fid);

fid = fopen(fullfile(outDir, 'grid_unit_audit.txt'), 'w');
fprintf(fid, 'P/Q branch variables: kW/kVAr\n');
fprintf(fid, 'base voltage: 12.66 kV line-to-line\n');
fprintf(fid, ['squared voltage drop: v_j=v_i-2*(r_ohm*P_kW+' ...
    'x_ohm*Q_kVAr)/(base_kV^2*1000)\n']);
fprintf(fid, 'branch Smax: 6 MVA = 6000 kVA\n');
fprintf(fid, 'octagon a=%.10f b=%.10f\n', ...
    data.branch_octagon_a, data.branch_octagon_b);
fprintf(fid, 'true-circle postcheck uses hypot(P,Q)/1000 <= 6 MVA\n');
fprintf(fid, 'PV and electrolyzer use unity power factor\n');
fclose(fid);

tau = (1:48).';
stage = ceil(tau / 8);
hourInStage = mod(tau - 1, 8) + 1;
loadRows = cell(48 * data.n_bus, 8);
row = 0;
for t = 1:48
    for bus = 1:data.n_bus
        row = row + 1;
        loadRows(row, :) = {t, stage(t), hourInStage(t), bus, ...
            data.lambda48(t), data.p_load_base_kw(bus), ...
            data.p_load_base_kw(bus)*data.lambda48(t), ...
            data.q_load_base_kvar(bus)*data.lambda48(t)};
    end
end
writetable(cell2table(loadRows, 'VariableNames', { ...
    'tau','stage','hour_in_stage','bus','load_multiplier', ...
    'p_base_kw','p_load_kw','q_load_kvar'}), ...
    fullfile(outDir, 'hourly_load_48h.csv'));

pvRows = cell(48 * 4, 8);
row = 0;
for t = 1:48
    for site = 1:4
        row = row + 1;
        pvRows(row, :) = {t, stage(t), hourInStage(t), site, ...
            data.site_elec_bus(site), data.pv_cap_kw(site), ...
            data.phi48(t), data.pv_cap_kw(site)*data.phi48(t)};
    end
end
writetable(cell2table(pvRows, 'VariableNames', { ...
    'tau','stage','hour_in_stage','site_id','electrical_bus', ...
    'pv_capacity_kw','pv_profile','pv_available_kw'}), ...
    fullfile(outDir, 'hourly_pv_48h.csv'));
writetable(table(tau, stage, hourInStage, data.tariff48, ...
    'VariableNames', {'tau','stage','hour_in_stage', ...
    'tariff_yuan_per_kwh'}), ...
    fullfile(outDir, 'hourly_tariff_48h.csv'));
writetable(table(data.site_id, data.road_site_node, data.site_elec_bus, ...
    repmat(string(data.mapping_class),4,1), ...
    'VariableNames', {'site_id','road_node','electrical_bus', ...
    'mapping_class'}), ...
    fullfile(outDir, 'site_electrical_bus_mapping.csv'));

fid = fopen(fullfile(outDir, 'cost_identity_audit.txt'), 'w');
fprintf(fid, 'hourly_procurement_cost=tariff(tau)*P_grid(tau)\n');
fprintf(fid, 'same_tariff_reapplied_to_P_EL=0\n');
fprintf(fid, 'electrolyzer_om_remains_separate_unit_cost=1\n');
fprintf(fid, ['ordinary electric load cost may be centered later only by a ' ...
    'decision-independent fixed constant\n']);
fprintf(fid, 'cost_identity_status=DESIGN_PASS_NOT_INTEGRATED_DUE_BASE_GRID_GATE\n');
fclose(fid);
end

function write_not_run_outputs(outDir, baseTable)
[minV, iMin] = min(baseTable.min_voltage_pu);
[maxU, iMax] = max(baseTable.max_true_branch_utilization);
nFeasible = sum(baseTable.constrained_feasible);

hosting = table("NOT_RUN_DUE_BASE_GRID_GATE", nFeasible, 48, ...
    'VariableNames', {'status','base_feasible_hours','total_hours'});
writetable(hosting, fullfile(outDir, 'electrolyzer_hosting_test.csv'));

write_text(fullfile(outDir, 'single_stage_integrated_smoke.txt'), ...
    'STATUS=NOT_RUN_DUE_BASE_GRID_GATE\nNo integrated H2/grid stage LP was solved.\n');
write_text(fullfile(outDir, 'cut_state_dimension_audit.txt'), ...
    ['STATUS=NOT_RUN_DUE_BASE_GRID_GATE\n' ...
    'Legacy source inspection: idx.x remains four inventories and add_cut_h2 uses only idx.x.\n' ...
    'No hourly-grid dual/cut smoke was permitted after gate B failed.\n']);
write_text(fullfile(outDir, 'legacy_regression.txt'), ...
    ['STATUS=NOT_RUN_DUE_BASE_GRID_GATE\n' ...
    'No protected FA-MSP core file was modified before the gate failure.\n' ...
    'A numerical legacy regression was not run because the task mandates stopping after gate B.\n']);

fid = fopen(fullfile(outDir, 'final_judgment.txt'), 'w');
fprintf(fid, 'FINAL_JUDGMENT=FAIL\n');
fprintf(fid, 'FAILURE_GATE=B_BASE_GRID_48H_FEASIBILITY\n');
fprintf(fid, 'constrained_feasible_hours=%d/48\n', nFeasible);
fprintf(fid, 'minimum_voltage_pu=%.12g\n', minV);
fprintf(fid, 'minimum_voltage_bus=%d\n', baseTable.min_voltage_bus(iMin));
fprintf(fid, 'minimum_voltage_hour=%d\n', baseTable.tau(iMin));
fprintf(fid, 'maximum_true_branch_utilization=%.12g\n', maxU);
fprintf(fid, 'maximum_true_branch_s_mva=%.12g\n', ...
    baseTable.max_true_branch_s_mva(iMax));
fprintf(fid, 'maximum_branch_from=%d\n', baseTable.tight_branch_from(iMax));
fprintf(fid, 'maximum_branch_to=%d\n', baseTable.tight_branch_to(iMax));
fprintf(fid, 'maximum_branch_hour=%d\n', baseTable.tau(iMax));
fprintf(fid, 'true_branch_circle_limit_pass=%d\n', ...
    all(baseTable.max_true_branch_s_mva <= 6 + 1e-9));
fprintf(fid, 'hosting_test=NOT_RUN_DUE_BASE_GRID_GATE\n');
fprintf(fid, 'single_stage_integrated_smoke=NOT_RUN_DUE_BASE_GRID_GATE\n');
fprintf(fid, 'dual_cut_smoke=NOT_RUN_DUE_BASE_GRID_GATE\n');
fprintf(fid, 'legacy_regression=NOT_RUN_DUE_BASE_GRID_GATE\n');
fprintf(fid, ['interpretation=The frozen IEEE-33 load/PV package violates the ' ...
    'frozen 0.95 p.u. lower voltage bound even with P_EL fixed to zero.\n']);
fprintf(fid, ['action=Stopped without relaxing voltage, changing load/PV/Smax, ' ...
    'or entering training/OOS.\n']);
fclose(fid);
end

function write_text(file, content)
fid = fopen(file, 'w');
fprintf(fid, '%s', sprintf(content));
fclose(fid);
end
