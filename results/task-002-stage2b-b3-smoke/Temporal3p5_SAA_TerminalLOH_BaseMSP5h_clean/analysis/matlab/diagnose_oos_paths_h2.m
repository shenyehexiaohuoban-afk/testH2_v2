function diagInfo = diagnose_oos_paths_h2(modelLib, params, pathIds)
%DIAGNOSE_OOS_PATHS_H2 Re-evaluate selected OOS paths with full decisions.

if nargin < 3 || isempty(pathIds)
    pathIds = 1:min(5, params.nbOS);
end
pathIds = unique(pathIds(:).');

if isfield(params, 'oosFile') && ~isempty(params.oosFile)
    oosFile = params.oosFile;
else
    oosFile = fullfile(params.dataDir, 'OOS.csv');
end
OS_paths = readmatrix(oosFile);

if any(pathIds < 1) || any(pathIds > size(OS_paths, 1))
    error('diagnose_oos_paths_h2:BadPathId', ...
        'pathIds must be within 1:%d.', size(OS_paths, 1));
end
if size(OS_paths, 2) < params.T
    error('diagnose_oos_paths_h2:ShortOOSPath', ...
        'OOS file has %d columns, but params.T = %d.', size(OS_paths, 2), params.T);
end

nPaths = numel(pathIds);
diagPaths = repmat(struct( ...
    'path_id', [], 'k_path', [], 'S_path', [], 'beta_path', [], ...
    'terminal_loh', [], 'stage_cost', [], 'x_before', [], 'x_after', [], ...
    'eval', [], 'rval', [], 'fval', [], 'u_normal', [], 'z_normal', [], ...
    'terminal_shortage', [], 'total_cost', []), nPaths, 1);

summaryRows = {};

for pp = 1:nPaths
    s = pathIds(pp);
    kPath = OS_paths(s, 1:params.T);
    prev_x = params.x_0;
    stageCost = zeros(params.T, 1);
    xBefore = cell(params.T, 1);
    xAfter = cell(params.T, 1);
    eStore = cell(params.T, 1);
    rStore = cell(params.T, 1);
    fStore = cell(params.T, 1);
    uStore = cell(params.T, 1);
    zStore = cell(params.T, 1);
    terminalStore = cell(params.T, 1);
    terminalShortageStore = cell(params.T, 1);
    absorbed = false;

    for t = 1:params.T
        k_t = kPath(t);
        xBefore{t} = prev_x;
        status = "normal";
        eSum = 0; rSum = 0; fSum = 0; uSum = 0; zSum = 0;
        terminalCost = 0; terminalShortage = 0;

        if absorbed
            status = "post_absorb";
            xAfter{t} = prev_x;
        elseif params.is_dissipated(k_t)
            status = "dissipated_absorb";
            xAfter{t} = prev_x;
            absorbed = true;
        elseif params.is_loh_demand_stage(k_t)
            status = "loh_demand_stage";
            [terminalCost, tinfo] = eval_terminal_loh_h2(prev_x, params, k_t);
            stageCost(t) = terminalCost;
            terminalShortage = sum(tinfo.shortage);
            terminalStore{t} = tinfo.target;
            terminalShortageStore{t} = tinfo.shortage;
            xAfter{t} = prev_x;
            absorbed = true;
        elseif params.is_absorbing(k_t)
            status = "absorbing_lfNc";
            xAfter{t} = prev_x;
            absorbed = true;
        else
            modelLib.models{t, k_t} = update_rhs_h2(modelLib.models{t, k_t}, params, k_t, t, prev_x);
            sol = solve_stage_model_h2(modelLib.models{t, k_t});
            stageCost(t) = sol.obj - sol.theta;
            prev_x = sol.xval;
            xAfter{t} = sol.xval;
            eStore{t} = sol.eval;
            rStore{t} = sol.rval;
            fStore{t} = sol.fval;
            uStore{t} = sol.u_normal;
            zStore{t} = sol.z_normal;
            eSum = sum(sol.eval);
            rSum = sum(sol.rval);
            fSum = sum(sol.fval(:));
            uSum = sum(sol.u_normal);
            zSum = sum(sol.z_normal);
        end

        summaryRows(end + 1, :) = {s, t, k_t, params.S(k_t, 1), params.S(k_t, 2), ...
            params.S(k_t, 3), params.beta(k_t), status, sum(xBefore{t}), ...
            sum(xAfter{t}), eSum, rSum, fSum, uSum, zSum, stageCost(t), ...
            sum(params.TerminalLOH(:, k_t)), terminalShortage, terminalCost}; %#ok<AGROW>
    end

    diagPaths(pp).path_id = s;
    diagPaths(pp).k_path = kPath;
    diagPaths(pp).S_path = params.S(kPath, :);
    diagPaths(pp).beta_path = params.beta(kPath);
    diagPaths(pp).terminal_loh = terminalStore;
    diagPaths(pp).stage_cost = stageCost;
    diagPaths(pp).x_before = xBefore;
    diagPaths(pp).x_after = xAfter;
    diagPaths(pp).eval = eStore;
    diagPaths(pp).rval = rStore;
    diagPaths(pp).fval = fStore;
    diagPaths(pp).u_normal = uStore;
    diagPaths(pp).z_normal = zStore;
    diagPaths(pp).terminal_shortage = terminalShortageStore;
    diagPaths(pp).total_cost = sum(stageCost);
end

summary = cell2table(summaryRows, 'VariableNames', ...
    {'path_id', 't', 'k', 'a', 'loc', 'lf', 'beta', 'status', ...
    'x_before_total', 'x_after_total', 'e', 'r', 'total_f', ...
    'u_normal', 'z_normal', 'stage_cost', 'TerminalLOH_total', ...
    'terminal_shortage', 'terminal_cost'});

diagInfo = struct();
diagInfo.paths = diagPaths;
diagInfo.summary = summary;

if isfield(params, 'detailsDir') && ~isempty(params.detailsDir)
    if ~exist(params.detailsDir, 'dir')
        mkdir(params.detailsDir);
    end
    writetable(summary, fullfile(params.detailsDir, 'diagnose_paths_h2.csv'));
    save(fullfile(params.detailsDir, 'diagnose_paths_h2.mat'), 'diagInfo', '-v7.3');
end
end
