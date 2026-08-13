function run_stage73_parameter_smoke_h2()
%RUN_STAGE73_PARAMETER_SMOKE_H2 Load-only identity smoke; no training/solver.

rootDir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(rootDir);
addpath(fullfile(rootDir, 'fa_h2'));
addpath(fullfile(rootDir, 'fa_h2', 'fuzhu'));
addpath(fullfile(rootDir, 'terminalLoh_wdro', 'src'));

runId = char(string(getenv('STAGE73_RUN_ID')));
if isempty(regexp(runId, '^run-\d{3}$', 'once'))
    error('run_stage73_parameter_smoke_h2:BadRunId', ...
        'STAGE73_RUN_ID must be run-xxx.');
end
outDir = fullfile(rootDir, 'results', 'task-002-stage2b-b3-smoke', ...
    '73-htt-transport-cost-sensitivity', runId, 'config_smoke');
if exist(outDir, 'dir')
    error('run_stage73_parameter_smoke_h2:OutputExists', ...
        'Refusing to overwrite smoke output: %s', outDir);
end
mkdir(outDir);

ids = {'REFERENCE_08','H04','H02','H01'};
rows = cell(numel(ids), 1);
reference = [];
for ii = 1:numel(ids)
    cfg = stage73_transport_cost_config_h2(rootDir, ids{ii});
    inputFile = fullfile(outDir, [ids{ii} '_input.mat']);
    inputStruct = struct('NearStageInput', cfg.NearStageInput);
    save(inputFile, '-struct', 'inputStruct', '-v7');
    opts = h2_default_options(rootDir);
    opts.nearInputFile = inputFile;
    opts.dt_h = 8;
    opts.terminal_loh_mode = 'saa';
    opts.terminal_loh_lookup_file = fullfile(rootDir, 'results', ...
        'task-002-stage2b-b3-smoke', ...
        '53-35state-saa-vs-eta003-terminal-loh', 'run-024', ...
        'terminal_loh_table_saa.csv');
    opts.allow_zero_terminal_loh = true;
    p = load_data_h2_near(opts.dataDir, inputFile, opts);
    if isempty(reference)
        reference = p;
    end
    expectedCost = cfg.transport_distance_coefficient * p.site_to_site_road_km;
    if max(abs(p.cost_transport_base - expectedCost), [], 'all') > 1e-10
        error('run_stage73_parameter_smoke_h2:CostMismatch', ...
            'Runtime c_d identity failed for %s.', ids{ii});
    end
    if p.dt_h ~= 8 || abs(p.htt_capacity_base - 160) > 1e-12 || ...
            ~p.use_beta_capacity || ~p.use_beta_cost || ...
            max(abs(p.el_cap_kw - reference.el_cap_kw)) > 1e-12 || ...
            max(abs(p.D_normal - reference.D_normal), [], 'all') > 1e-12 || ...
            max(abs(p.TerminalLOH - reference.TerminalLOH), [], 'all') > 1e-12 || ...
            abs(p.cost_holding - reference.cost_holding) > 1e-12 || ...
            abs(p.cost_normal_shortage - reference.cost_normal_shortage) > 1e-12 || ...
            abs(p.cost_reserve_shortage - reference.cost_reserve_shortage) > 1e-12
        error('run_stage73_parameter_smoke_h2:ProtectedParameterDrift', ...
            'A protected E1 parameter changed for %s.', ids{ii});
    end
    positive = expectedCost(expectedCost > 0);
    rows{ii} = table(string(ids{ii}), cfg.transport_distance_coefficient, ...
        p.dt_h, p.htt_capacity_base, p.beta_transport_multiplier, ...
        min(positive), max(positive), sum(p.D_normal, 'all'), ...
        p.cost_holding, p.cost_normal_shortage, p.cost_reserve_shortage, ...
        'VariableNames', {'experiment','transport_distance_coefficient', ...
        'dt_h','htt_capacity_kg_per_stage','beta_transport_multiplier', ...
        'min_base_transport_cost','max_base_transport_cost', ...
        'expanded_ordinary_demand_total_kg','holding_cost', ...
        'ordinary_shortage_penalty','terminal_gap_penalty'});
end
writetable(vertcat(rows{:}), fullfile(outDir, 'parameter_smoke_summary.csv'));
fid = fopen(fullfile(outDir, 'PARAMETER_SMOKE_PASS.txt'), 'w');
fprintf(fid, 'status=PASS\n');
fprintf(fid, 'scope=load_only_no_training_no_solver\n');
fprintf(fid, 'coefficients=0.8,0.4,0.2,0.1\n');
fprintf(fid, 'protected_E1_identity=PASS\n');
fprintf(fid, 'completed_at=%s\n', datestr(now, 31));
fclose(fid);
end
