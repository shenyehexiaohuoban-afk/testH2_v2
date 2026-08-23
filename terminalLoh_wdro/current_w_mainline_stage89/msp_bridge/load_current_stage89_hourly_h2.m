function [params, opts, audit] = load_current_stage89_hourly_h2(rootDir, requestedMode)
%LOAD_CURRENT_STAGE89_HOURLY_H2 Load Stage89K into accepted Stage89F 8h model.

if nargin < 1 || isempty(rootDir)
    rootDir = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
end
if nargin < 2 || isempty(requestedMode)
    requestedMode = "dro";
end
addpath(rootDir);
addpath(fullfile(rootDir,'fa_h2'));
addpath(fullfile(rootDir,'fa_h2','fuzhu'));
addpath(fullfile(rootDir,'hourly_grid_h2'));
addpath(fullfile(rootDir,'fa_msp','current_hourly_stage88_candidate','config'));
addpath(fullfile(rootDir,'fa_msp','current_hourly_stage88_candidate','input'));
addpath(fileparts(mfilename('fullpath')));

inputAudit = build_stage88_candidate_msp_input_h2(rootDir);
opts = current_hourly_stage88_candidate_options_h2(rootDir);
opts.terminal_loh_mode = 'legacy';
opts.runTraining = false;
opts.runEvaluation = false;
opts.runSelectedPathDiagnostics = false;
opts.regenOOS = false;
opts.store_eval_decisions = false;
opts.stage89_adopted_terminal_mode = char(lower(string(requestedMode)));
opts.stage89_bundle_id = 'current_w_mainline_stage89_v1';

params = load_data_h2_near(opts.dataDir, opts.nearInputFile, opts);
params.hourly_h2_balance_v1 = true;
params.hourly_htt_v1 = true;
params.h2_timescale_schema = 'hourly-h2-hourly-htt-v1';
params.htt_timing = 'hourly_end_of_hour_arrival';
params.demand_schema = 'original-hourly-24h-repeat-v1';
params.hourly_grid.tank_cap_kg = params.x_cap(:);
params.hourly_grid.pmax_kw = params.el_cap_kw(:);
params.hourly_grid.x0_kg = params.x_0(:);
params.hourly_grid.htt_capacity_kg_per_stage = params.htt_capacity_base;

[TerminalLOH, mode, tableAudit] = load_stage89_adopted_terminal_loh_h2( ...
    params.S, params.NearStageInput, requestedMode);
params.TerminalLOH = TerminalLOH;
params.terminal_loh_mode = "stage89k_" + mode;
params.terminal_loh_source = tableAudit.source_file;
params.terminal_loh_lookup_audit = tableAudit;
params.stage89_bundle_id = string(opts.stage89_bundle_id);

expectedX0 = [58.04455704486949;50.30813793862475;25.262133442309338;33.02358084624278];
pass = params.dt_h==8 && params.enable_hourly_grid && params.T==8 && ...
    params.hourly_grid.n_operating_stages==6 && params.hourly_grid.hours_per_stage==8 && ...
    isequal(params.x_cap(:).',[300,200,100,200]) && ...
    isequal(params.el_cap_kw(:).',[300,200,120,150]) && ...
    max(abs(params.x_0(:)-expectedX0))<=1e-12 && ...
    abs(params.k_H2-0.0195)<=1e-12 && params.hourly_h2_balance_v1 && ...
    params.hourly_htt_v1 && string(params.demand_schema)=="original-hourly-24h-repeat-v1" && ...
    tableAudit.pass && tableAudit.table_version=="Stage89K";
if ~pass
    error('Stage89M:BridgeIdentity', 'Stage89 adopted 8h bridge identity gate failed.');
end
audit = struct('pass',pass,'input_audit',inputAudit,'table_audit',tableAudit, ...
    'default_mode_is_dro',nargin<2||isempty(requestedMode), ...
    'active_stage_dt_h',params.dt_h, ...
    'source_demand_block_dt_h',params.NearStageInput.NormalDemand.stage_dt_h, ...
    'initial_inventory_rescaled',false,'site4_tank_kg',params.x_cap(4), ...
    'site4_pmax_kw',params.el_cap_kw(4));
end
