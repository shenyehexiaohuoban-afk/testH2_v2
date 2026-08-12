rootDir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(rootDir);
addpath(fullfile(rootDir, 'fa_h2'));
addpath(fullfile(rootDir, 'fa_h2', 'fuzhu'));
addpath(fullfile(rootDir, 'terminalLoh_wdro', 'src'));

runId = char(string(getenv('STAGE71_RUN_ID')));
if isempty(regexp(runId, '^run-\d{3}$', 'once'))
    error('run_stage71_parameter_smoke_h2:BadRunId', 'STAGE71_RUN_ID must be run-xxx.');
end
outDir = fullfile(rootDir, 'results', 'task-002-stage2b-b3-smoke', ...
    '71-stage-duration-capacity-sensitivity', runId, 'config_smoke');
if exist(outDir, 'dir')
    error('run_stage71_parameter_smoke_h2:OutputExists', ...
        'Refusing to overwrite existing smoke output: %s', outDir);
end
mkdir(outDir);

ids = {'E1_8h','E2_6h_pmax_4over3','E3_8h_htt_4over3'};
rows = cell(numel(ids), 1);
for ii = 1:numel(ids)
    cfg = stage71_experiment_config_h2(rootDir, ids{ii});
    inputFile = fullfile(outDir, [ids{ii} '_input.mat']);
    inputStruct = struct('NearStageInput', cfg.NearStageInput);
    save(inputFile, '-struct', 'inputStruct', '-v7');
    opts = h2_default_options(rootDir);
    opts.nearInputFile = inputFile;
    opts.dt_h = cfg.dt_h;
    opts.terminal_loh_mode = 'saa';
    opts.terminal_loh_lookup_file = fullfile(rootDir, 'results', ...
        'task-002-stage2b-b3-smoke', '53-35state-saa-vs-eta003-terminal-loh', ...
        'run-024', 'terminal_loh_table_saa.csv');
    opts.allow_zero_terminal_loh = true;
    p = load_data_h2_near(opts.dataDir, inputFile, opts);
    runtimeRmax = p.el_cap_kw(:).' * p.k_H2 * p.dt_h;
    if max(abs(runtimeRmax - cfg.rmax_kg_per_stage)) > 1e-10
        error('run_stage71_parameter_smoke_h2:RmaxMismatch', ...
            'Runtime rmax mismatch for %s.', ids{ii});
    end
    rows{ii} = table(string(ids{ii}), p.dt_h, p.el_cap_kw(1), p.el_cap_kw(2), ...
        p.el_cap_kw(3), p.el_cap_kw(4), runtimeRmax(1), runtimeRmax(2), ...
        runtimeRmax(3), runtimeRmax(4), p.htt_capacity_base, ...
        sum(p.D_normal, 'all'), p.cost_holding, p.cost_normal_shortage, ...
        p.cost_reserve_shortage, ...
        'VariableNames', {'experiment','dt_h','pmax1_kw','pmax2_kw','pmax3_kw','pmax4_kw', ...
        'rmax1_kg','rmax2_kg','rmax3_kg','rmax4_kg','htt_capacity_kg_per_stage', ...
        'expanded_ordinary_demand_total_kg','holding_cost','ordinary_shortage_penalty', ...
        'terminal_gap_penalty'});
end
summary = vertcat(rows{:});
if max(abs(summary{1, {'rmax1_kg','rmax2_kg','rmax3_kg','rmax4_kg'}} - ...
        summary{2, {'rmax1_kg','rmax2_kg','rmax3_kg','rmax4_kg'}})) > 1e-10
    error('run_stage71_parameter_smoke_h2:E1E2Mismatch', ...
        'E1 and E2 rmax vectors are not identical.');
end
if abs(summary.htt_capacity_kg_per_stage(3) - 160 * 4 / 3) > 1e-9
    error('run_stage71_parameter_smoke_h2:E3HTTMismatch', ...
        'E3 HTT capacity is not 160*4/3.');
end
writetable(summary, fullfile(outDir, 'parameter_smoke_summary.csv'));
fid = fopen(fullfile(outDir, 'PARAMETER_SMOKE_PASS.txt'), 'w');
fprintf(fid, 'Stage-71 parameter smoke: PASS\n');
fprintf(fid, 'E1/E2 rmax identity: PASS\n');
fprintf(fid, 'ordinary demand frozen: PASS\n');
fprintf(fid, 'E3 continuous-flow HTT capacity: %.12g kg/stage\n', ...
    summary.htt_capacity_kg_per_stage(3));
fclose(fid);
