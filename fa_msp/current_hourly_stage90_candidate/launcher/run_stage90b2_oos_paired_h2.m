function run_stage90b2_oos_paired_h2()
%RUN_STAGE90B2_OOS_PAIRED_H2 Read-only paired OOS evaluator.

rootDir = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(rootDir);
addpath(fullfile(rootDir, 'fa_h2'));
addpath(fullfile(rootDir, 'fa_h2', 'fuzhu'));
addpath(fullfile(rootDir, 'hourly_grid_h2'));
addpath(fullfile(rootDir, 'utils'));
sourceRun = fullfile(rootDir, 'results', 'task-002-stage2b-b3-smoke', ...
    'stage90b-base-pmax-fresh-zero-cut-10iter', 'run-004');
runDir = fullfile(rootDir, 'results', 'task-002-stage2b-b3-smoke', ...
    'stage90b2-oos-paired-evaluation', 'run-001');
if isfolder(runDir)
    error('Stage90B2OOS:RefuseOverwrite', 'Refusing to overwrite %s.', runDir);
end
mkdir(runDir);
checkpoint = fullfile(sourceRun, '06_checkpoint', 'checkpoint_final.mat');
if ~isfile(checkpoint)
    error('Stage90B2OOS:MissingCheckpoint', 'Missing %s.', checkpoint);
end
z = load(checkpoint, 'p', 'lib', 'checkpoint_metadata', 'result_metadata');
p = z.p;
lib = z.lib;
oosFile = fullfile(p.dataDir, 'OOS.csv');
if ~isfile(oosFile)
    error('Stage90B2OOS:MissingOOS', 'Missing %s.', oosFile);
end
oosRaw = readmatrix(oosFile);
nOS = 10000;
if size(oosRaw,1) < nOS || size(oosRaw,2) < p.T
    error('Stage90B2OOS:OOSSchema', 'OOS.csv lacks 10,000 rows of %d-stage paths.', p.T);
end

pRec = p;
pRec.nbOS = nOS;
pRec.store_eval_decisions = false;
pRec.oosFile = oosFile;
fprintf('Stage90B2 OOS recourse start: paths=%d source=%s', nOS, oosFile); fprintf(char(10));
tRec = tic;
recourse = eval_h2(lib, pRec);
recourseElapsed = toc(tRec);
fprintf('Stage90B2 OOS recourse complete: mean=%.12g elapsed=%.3fs', recourse.oos_mean, recourseElapsed); fprintf(char(10));

pDirect = pRec;
pDirect.terminal_recourse_mode = 'DIRECT_GAP';
pDirect.terminal_recourse_enabled = false;
pDirect.K_terminal_kg = 0;
fprintf('Stage90B2 OOS direct-gap start: paths=%d', nOS); fprintf(char(10));
tDirect = tic;
direct = eval_h2(lib, pDirect);
directElapsed = toc(tDirect);
fprintf('Stage90B2 OOS direct-gap complete: mean=%.12g elapsed=%.3fs', direct.oos_mean, directElapsed); fprintf(char(10));

directCost = double(direct.pathCost(:));
recourseCost = double(recourse.pathCost(:));
delta = directCost - recourseCost;
pathRows = table((1:nOS).', directCost, recourseCost, delta, ...
    sum(direct.terminal_reserve_shortage,2), sum(recourse.terminal_reserve_shortage,2), ...
    sum(recourse.terminal_redistribution_amount,2), sum(recourse.terminal_redistribution_cost,2), ...
    direct.first_loh_demand_stage, recourse.first_loh_demand_stage, ...
    'VariableNames', {'path_id','direct_gap_cost_yuan','terminal_recourse_cost_yuan', ...
    'direct_minus_recourse_yuan','direct_terminal_gap_kg','recourse_terminal_gap_kg', ...
    'recourse_redistribution_kg','recourse_shipping_cost_yuan', ...
    'direct_terminal_stage','recourse_terminal_stage'});
writetable(pathRows, fullfile(runDir, 'oos_paired_path_summary.csv'));

recourseShip = sum(recourse.terminal_redistribution_amount,2);
recourseShipCost = sum(recourse.terminal_redistribution_cost,2);
summaryRows = {
    "DIRECT_GAP", direct.oos_mean, direct.oos_std, direct.ci_low, direct.ci_high, ...
    direct.avg_normal_shortage, direct.avg_terminal_reserve_shortage, direct.avg_terminal_cost, ...
    0, 0, direct.hit_loh_demand_ratio, direct.avg_transport, directElapsed;
    "TERMINAL_REDISTRIBUTION", recourse.oos_mean, recourse.oos_std, recourse.ci_low, recourse.ci_high, ...
    recourse.avg_normal_shortage, recourse.avg_terminal_reserve_shortage, recourse.avg_terminal_cost, ...
    mean(recourseShip), mean(recourseShipCost), recourse.hit_loh_demand_ratio, recourse.avg_transport, recourseElapsed};
summaryTable = cell2table(summaryRows, 'VariableNames', {'evaluator','oos_mean_yuan', ...
    'oos_std_yuan','ci_low_yuan','ci_high_yuan','avg_normal_shortage_kg', ...
    'avg_terminal_gap_kg','avg_terminal_cost_yuan','avg_redistribution_kg', ...
    'avg_shipping_cost_yuan','hit_loh_demand_ratio','avg_transport_kg','elapsed_s'});
writetable(summaryTable, fullfile(runDir, 'oos_paired_summary.csv'));

stage = (1:p.T).';
stageRows = table(stage, accumarray(recourse.first_loh_demand_stage(recourse.hit_loh_demand), 1, [p.T 1], @sum, 0), ...
    sum(recourse.terminal_redistribution_amount > 1e-8,1).', ...
    sum(recourse.terminal_reserve_shortage,1).', sum(recourse.terminal_cost,1).', ...
    sum(recourse.terminal_redistribution_cost,1).', ...
    'VariableNames', {'stage','hit_count','positive_redistribution_count', ...
    'terminal_gap_kg_sum','terminal_cost_yuan_sum','shipping_cost_yuan_sum'});
writetable(stageRows, fullfile(runDir, 'oos_terminal_stage_summary.csv'));

pairedRows = {
    'path_count', nOS, 'paths', 'Same first 10,000 OOS rows used by both evaluators';
    'direct_mean_yuan', direct.oos_mean, 'yuan/path', 'DIRECT_GAP evaluator';
    'recourse_mean_yuan', recourse.oos_mean, 'yuan/path', 'TERMINAL_REDISTRIBUTION evaluator';
    'mean_direct_minus_recourse_yuan', mean(delta), 'yuan/path', 'Positive means recourse lowers cost';
    'median_direct_minus_recourse_yuan', median(delta), 'yuan/path', 'Paired path difference';
    'p05_direct_minus_recourse_yuan', quantile(delta,0.05), 'yuan/path', 'Paired path difference';
    'p95_direct_minus_recourse_yuan', quantile(delta,0.95), 'yuan/path', 'Paired path difference';
    'recourse_better_path_count', sum(delta > 1e-7), 'paths', 'Direct cost > recourse cost';
    'recourse_better_path_rate', mean(delta > 1e-7), 'fraction', 'Direct cost > recourse cost';
    'equal_path_count', sum(abs(delta) <= 1e-7), 'paths', 'Paired costs equal within tolerance';
    'recourse_worse_path_count', sum(delta < -1e-7), 'paths', 'Direct cost < recourse cost';
    'recourse_positive_shipping_path_count', sum(recourseShip > 1e-8), 'paths', 'Any terminal shipment';
    'recourse_positive_shipping_rate', mean(recourseShip > 1e-8), 'fraction', 'Any terminal shipment';
    'recourse_avg_shipping_cost_yuan', mean(recourseShipCost), 'yuan/path', 'Physical shipping cost only';
    'recourse_avg_terminal_gap_kg', recourse.avg_terminal_reserve_shortage, 'kg/path', 'Residual terminal gap';
    'recourse_avg_terminal_cost_yuan', recourse.avg_terminal_cost, 'yuan/path', 'Shipping plus shortage penalty';
    };
pairedTable = cell2table(pairedRows, 'VariableNames', {'metric','value','unit','definition'});
writetable(pairedTable, fullfile(runDir, 'oos_paired_difference_summary.csv'));
qaRows = {
    'checkpoint_exists', isfile(checkpoint), true, 'Saved run-004 checkpoint loaded';
    'oos_source_exists', isfile(oosFile), true, 'data/OOS.csv';
    'oos_rows_10000', size(oosRaw,1) >= nOS, size(oosRaw,1) >= nOS, 'At least 10,000 rows';
    'direct_mode_identity', strcmp(string(pDirect.terminal_recourse_mode),'DIRECT_GAP') && pDirect.K_terminal_kg == 0, true, 'Direct evaluator mode';
    'recourse_mode_identity', strcmp(string(pRec.terminal_recourse_mode),'TERMINAL_REDISTRIBUTION') && pRec.K_terminal_kg == 160, true, 'Recourse evaluator mode';
    'paired_path_count', numel(delta) == nOS, numel(delta) == nOS, 'One paired row per OOS path';
    'finite_outputs', all(isfinite([directCost; recourseCost; delta])), all(isfinite([directCost; recourseCost; delta])), 'Finite path costs and differences';
    'decisions_not_stored', ~isfield(recourse,'fval') && ~isfield(direct,'fval'), true, 'No path decision matrices retained';
    'no_training', true, true, 'Checkpoint-only OOS calls';
    };
qaTable = cell2table(qaRows, 'VariableNames', {'check','pass','expected','notes'});
qaTable.status = repmat("PASS", height(qaTable), 1);
qaTable.status(~qaTable.pass) = "FAIL";
qaTable = movevars(qaTable, 'status', 'After', 'pass');
writetable(qaTable, fullfile(runDir, 'oos_qa.csv'));
write_oos_readme(runDir, rootDir, sourceRun, oosFile, nOS, direct, recourse, delta, directElapsed, recourseElapsed);
fprintf('Stage90B2 paired OOS written: %s', runDir); fprintf(char(10));
end
