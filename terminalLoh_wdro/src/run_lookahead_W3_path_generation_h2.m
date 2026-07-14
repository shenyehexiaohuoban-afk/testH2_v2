clear; clc;

thisDir = fileparts(mfilename('fullpath'));
moduleDir = fileparts(thisDir);
rootDir = fileparts(moduleDir);
if isempty(rootDir) || isempty(moduleDir)
    rootDir = pwd;
    moduleDir = fullfile(rootDir, 'terminalLoh_wdro');
end

addpath(thisDir);
addpath(rootDir);
addpath(fullfile(rootDir, 'fa_h2', 'fuzhu', 'terminalLoh_windmc'));

config = struct();
config.rootDir = rootDir;
config.moduleDir = moduleDir;
config.configDir = fullfile(moduleDir, 'config');
config.outputDir = fullfile(moduleDir, 'output', 'stage2_lookahead_W3');
config.diagnosticDir = fullfile(config.outputDir, 'config_diagnostics');
config.docsDir = fullfile(moduleDir, 'docs');
config.intensityConfigFile = fullfile(config.configDir, ...
    'lookahead_intensity_W3.csv');
config.locationConfigFile = fullfile(config.configDir, ...
    'lookahead_location_W3.csv');
config.windowConfigFile = fullfile(config.configDir, ...
    'lookahead_window_W3.csv');
config.locationFile = fullfile(rootDir, 'data', 'location.csv');
config.intensityFile = fullfile(rootDir, 'data', 'intensity.csv');
config.landfallFile = fullfile(rootDir, 'data', 'landfall_7.csv');
config.nearInputFile = fullfile(rootDir, 'data', 'yuanqi', ...
    'near_stage_msp_input.mat');
config.requestedWindMcScript = fullfile(rootDir, 'fa_h2', 'fuzhu', ...
    'terminalLoh_windmc', 'generate_terminal_loh_wind_mc_preview.m');
config.rootWindMcScript = fullfile(rootDir, ...
    'generate_terminal_loh_wind_mc_preview.m');
config.wdroStage1RunScript = fullfile(moduleDir, 'src', ...
    'run_terminal_loh_wdro_preview_h2.m');

if ~exist(config.configDir, 'dir'); mkdir(config.configDir); end
if ~exist(config.outputDir, 'dir'); mkdir(config.outputDir); end
if ~exist(config.diagnosticDir, 'dir'); mkdir(config.diagnosticDir); end
if ~exist(config.docsDir, 'dir'); mkdir(config.docsDir); end

P_loc = read_transition_matrix(config.locationFile, ...
    'run_lookahead_W3_path_generation_h2:BadLocationMatrix');
P_intensity = read_transition_matrix(config.intensityFile, ...
    'run_lookahead_W3_path_generation_h2:BadIntensityMatrix');
P_landfall = read_transition_matrix(config.landfallFile, ...
    'run_lookahead_W3_path_generation_h2:BadLandfallMatrix');

defaultWindow = struct();
defaultWindow.W = 3;
defaultWindow.P = 20;
defaultWindow.random_seed = 20260706;
defaultWindow.loc_min = 1;
defaultWindow.loc_max = size(P_loc, 1);
defaultWindow.halo_width = 3;
defaultWindow.lf_terminal = size(P_landfall, 1) - 1;
if ~isfile(config.windowConfigFile)
    write_window_config(config.windowConfigFile, defaultWindow);
end
windowConfig = read_window_config(config.windowConfigFile);
config.W = windowConfig.W;
config.P = windowConfig.P;
config.random_seed = windowConfig.random_seed;
config.loc_min = windowConfig.loc_min;
config.loc_max = windowConfig.loc_max;
config.halo_width = windowConfig.halo_width;
config.lf_terminal = windowConfig.lf_terminal;
validate_window_config(config, P_loc, P_landfall);

raw = load(config.nearInputFile, 'NearStageInput');
if ~isfield(raw, 'NearStageInput')
    error('run_lookahead_W3_path_generation_h2:MissingNearStageInput', ...
        'Missing NearStageInput in %s.', config.nearInputFile);
end
NearStageInput = raw.NearStageInput;
layout = build_h2_spatial_layout_preview(NearStageInput);

origLocIds = (config.loc_min:config.loc_max).';
locExtTbl = build_lookahead_location_ext_h2(origLocIds, layout.locs, config);
writetable(locExtTbl, fullfile(config.diagnosticDir, ...
    'lookahead_location_ext.csv'));

[defaultLocTransTbl, ~, locKernelTbl] = ...
    build_lookahead_transition_loc_h2(P_loc, locExtTbl, config);
if ~isfile(config.locationConfigFile)
    writetable(defaultLocTransTbl, config.locationConfigFile);
end
locTransTbl = readtable(config.locationConfigFile);
locTransTbl = normalize_loc_transition_table(locTransTbl);
locCheckTbl = build_loc_transition_check(locTransTbl, locExtTbl);
writetable(locCheckTbl, fullfile(config.outputDir, ...
    'lookahead_transition_loc_check.csv'));
writetable(locTransTbl, fullfile(config.diagnosticDir, ...
    'lookahead_transition_loc_W3.csv'));
writetable(locKernelTbl, fullfile(config.diagnosticDir, ...
    'lookahead_transition_loc_delta_kernel_W3.csv'));

[defaultIntTransTbl, ~] = build_lookahead_transition_intensity_h2( ...
    P_intensity, config);
if ~isfile(config.intensityConfigFile)
    writetable(defaultIntTransTbl, config.intensityConfigFile);
end
intTransTbl = readtable(config.intensityConfigFile);
intTransTbl = normalize_intensity_transition_table(intTransTbl);
intCheckTbl = build_intensity_transition_check(intTransTbl, ...
    size(P_intensity, 1));
writetable(intCheckTbl, fullfile(config.outputDir, ...
    'lookahead_transition_intensity_check.csv'));
writetable(intTransTbl, fullfile(config.diagnosticDir, ...
    'lookahead_transition_intensity_W3.csv'));

write_legacy_stage2_config(config, P_loc, P_intensity, P_landfall);

write_input_inspection(config, P_loc, P_intensity, P_landfall, ...
    NearStageInput, layout, locExtTbl, locKernelTbl);

pathTbl = sample_lookahead_paths_W3_h2(locTransTbl, intTransTbl, ...
    locExtTbl, config);
writetable(pathTbl, fullfile(config.outputDir, ...
    'lookahead_path_table.csv'));

summaryTbl = write_lookahead_path_diagnostics_h2(pathTbl, locExtTbl, config);
writetable(summaryTbl, fullfile(config.outputDir, ...
    'lookahead_path_summary.csv'));

write_lookahead_docs(config, locExtTbl, locKernelTbl);

fprintf('\nStage 2A W=3 look-ahead typhoon path generation finished.\n');
fprintf('Config directory:\n%s\n', config.configDir);
fprintf('Output directory:\n%s\n', config.outputDir);
fprintf('Path table rows = %d\n', height(pathTbl));

function X = read_transition_matrix(fileName, errId)
if ~isfile(fileName)
    error(errId, 'Missing transition file: %s', fileName);
end
X = table2array(readtable(fileName));
X = double(X);
if ~ismatrix(X) || isempty(X)
    error(errId, 'Transition file %s did not produce a numeric matrix.', fileName);
end
rowSums = sum(X, 2);
if any(rowSums <= 0)
    error(errId, 'Transition file %s has a row with non-positive sum.', fileName);
end
end

function write_window_config(fileName, windowConfig)
key = ["W"; "P"; "random_seed"; "loc_min"; "loc_max"; ...
    "halo_width"; "lf_terminal"];
value = string([windowConfig.W; windowConfig.P; ...
    windowConfig.random_seed; windowConfig.loc_min; ...
    windowConfig.loc_max; windowConfig.halo_width; ...
    windowConfig.lf_terminal]);
tbl = table(key, value, 'VariableNames', {'key', 'value'});
writetable(tbl, fileName);
end

function windowConfig = read_window_config(fileName)
if ~isfile(fileName)
    error('run_lookahead_W3_path_generation_h2:MissingWindowConfig', ...
        'Missing look-ahead window config: %s', fileName);
end
tbl = readtable(fileName, 'TextType', 'string');
if ~all(ismember({'key', 'value'}, tbl.Properties.VariableNames))
    error('run_lookahead_W3_path_generation_h2:BadWindowConfig', ...
        'Window config must contain key,value columns: %s', fileName);
end
windowConfig = struct();
windowConfig.W = get_window_number(tbl, "W");
windowConfig.P = get_window_number(tbl, "P");
windowConfig.random_seed = get_window_number(tbl, "random_seed");
windowConfig.loc_min = get_window_number(tbl, "loc_min");
windowConfig.loc_max = get_window_number(tbl, "loc_max");
windowConfig.halo_width = get_window_number(tbl, "halo_width");
windowConfig.lf_terminal = get_window_number(tbl, "lf_terminal");
end

function value = get_window_number(tbl, keyName)
keys = string(tbl.key);
idx = find(keys == keyName, 1, 'first');
if isempty(idx)
    error('run_lookahead_W3_path_generation_h2:MissingWindowKey', ...
        'Missing key %s in lookahead_window_W3.csv.', keyName);
end
rawValue = string(tbl.value(idx));
value = str2double(rawValue);
if ~isfinite(value)
    error('run_lookahead_W3_path_generation_h2:BadWindowValue', ...
        'Window key %s has nonnumeric value %s.', keyName, rawValue);
end
end

function validate_window_config(config, P_loc, P_landfall)
if config.W <= 0 || config.P <= 0 || config.halo_width < 0
    error('run_lookahead_W3_path_generation_h2:BadWindowConfig', ...
        'W and P must be positive, and halo_width must be nonnegative.');
end
if any(abs([config.W, config.P, config.random_seed, config.loc_min, ...
        config.loc_max, config.halo_width, config.lf_terminal] - ...
        round([config.W, config.P, config.random_seed, config.loc_min, ...
        config.loc_max, config.halo_width, config.lf_terminal])) > 0)
    error('run_lookahead_W3_path_generation_h2:NonIntegerWindowConfig', ...
        'All lookahead_window_W3 values must be integers.');
end
if config.loc_min < 1 || config.loc_max > size(P_loc, 1) || ...
        config.loc_min > config.loc_max
    error('run_lookahead_W3_path_generation_h2:BadLocRange', ...
        'loc_min/loc_max are outside data/location.csv bounds.');
end
expectedLf = size(P_landfall, 1) - 1;
if config.lf_terminal ~= expectedLf
    error('run_lookahead_W3_path_generation_h2:BadLfTerminal', ...
        'lf_terminal=%d does not match landfall_7.csv terminal state %d.', ...
        config.lf_terminal, expectedLf);
end
end

function tbl = normalize_loc_transition_table(tbl)
required = {'from_loc_id', 'to_loc_id', 'prob'};
if ~all(ismember(required, tbl.Properties.VariableNames))
    error('run_lookahead_W3_path_generation_h2:BadLocConfig', ...
        'lookahead_location_W3.csv must contain from_loc_id,to_loc_id,prob.');
end
tbl = tbl(:, required);
tbl.from_loc_id = double(tbl.from_loc_id);
tbl.to_loc_id = double(tbl.to_loc_id);
tbl.prob = double(tbl.prob);
if any(~isfinite(tbl.from_loc_id) | ~isfinite(tbl.to_loc_id) | ...
        ~isfinite(tbl.prob) | tbl.prob < 0)
    error('run_lookahead_W3_path_generation_h2:BadLocConfigValue', ...
        'lookahead_location_W3.csv contains invalid numeric values.');
end
end

function tbl = normalize_intensity_transition_table(tbl)
required = {'from_a', 'to_a', 'prob'};
if ~all(ismember(required, tbl.Properties.VariableNames))
    error('run_lookahead_W3_path_generation_h2:BadIntensityConfig', ...
        'lookahead_intensity_W3.csv must contain from_a,to_a,prob.');
end
tbl = tbl(:, required);
tbl.from_a = double(tbl.from_a);
tbl.to_a = double(tbl.to_a);
tbl.prob = double(tbl.prob);
if any(~isfinite(tbl.from_a) | ~isfinite(tbl.to_a) | ...
        ~isfinite(tbl.prob) | tbl.prob < 0)
    error('run_lookahead_W3_path_generation_h2:BadIntensityConfigValue', ...
        'lookahead_intensity_W3.csv contains invalid numeric values.');
end
end

function checkTbl = build_loc_transition_check(transTbl, locExtTbl)
locIds = double(locExtTbl.loc_id(:));
checkRows = {};
for ff = 1:numel(locIds)
    fromLoc = locIds(ff);
    rowsF = transTbl(transTbl.from_loc_id == fromLoc, :);
    if isempty(rowsF)
        checkRows(end + 1, :) = {fromLoc, 0, 0, NaN, NaN, ...
            'MISSING_FROM_LOC'}; %#ok<AGROW>
        continue;
    end
    probSum = sum(rowsF.prob);
    if abs(probSum - 1) <= 1e-8
        status = 'OK';
    else
        status = 'BAD_PROB_SUM';
    end
    checkRows(end + 1, :) = {fromLoc, probSum, height(rowsF), ...
        min(rowsF.to_loc_id), max(rowsF.to_loc_id), status}; %#ok<AGROW>
end
checkTbl = cell2table(checkRows, 'VariableNames', ...
    {'from_loc_id', 'prob_sum', 'nonzero_to_count', ...
    'min_to_loc_id', 'max_to_loc_id', 'status'});
if any(~strcmp(checkTbl.status, 'OK'))
    error('run_lookahead_W3_path_generation_h2:BadLocProbSum', ...
        'Some lookahead_location_W3.csv rows do not sum to one by from_loc_id.');
end
end

function checkTbl = build_intensity_transition_check(transTbl, nA)
checkRows = {};
for aa = 1:nA
    rowsA = transTbl(transTbl.from_a == aa, :);
    if isempty(rowsA)
        checkRows(end + 1, :) = {aa, 0, 0, NaN, NaN, ...
            'MISSING_FROM_A'}; %#ok<AGROW>
        continue;
    end
    probSum = sum(rowsA.prob);
    if abs(probSum - 1) <= 1e-8
        status = 'OK';
    else
        status = 'BAD_PROB_SUM';
    end
    checkRows(end + 1, :) = {aa, probSum, height(rowsA), ...
        min(rowsA.to_a), max(rowsA.to_a), status}; %#ok<AGROW>
end
checkTbl = cell2table(checkRows, 'VariableNames', ...
    {'from_a', 'prob_sum', 'nonzero_to_count', ...
    'min_to_a', 'max_to_a', 'status'});
if any(~strcmp(checkTbl.status, 'OK'))
    error('run_lookahead_W3_path_generation_h2:BadIntensityProbSum', ...
        'Some lookahead_intensity_W3.csv rows do not sum to one by from_a.');
end
end

function write_legacy_stage2_config(config, P_loc, P_intensity, P_landfall)
legacyTbl = table(config.W, config.P, config.random_seed, ...
    config.loc_min, config.loc_max, config.halo_width, ...
    size(P_loc, 1), size(P_intensity, 1), size(P_landfall, 1) - 1, ...
    string(config.locationFile), string(config.intensityFile), ...
    string(config.landfallFile), ...
    'VariableNames', {'W', 'P', 'random_seed', 'loc_min', 'loc_max', ...
    'halo_width', 'original_loc_count', 'intensity_state_count', ...
    'lf_terminal_state', 'location_file', 'intensity_file', ...
    'landfall_file'});
writetable(legacyTbl, fullfile(config.diagnosticDir, ...
    'lookahead_stage2_config_W3.csv'));
end

function write_input_inspection(config, P_loc, P_intensity, P_landfall, ...
    NearStageInput, layout, locExtTbl, locKernelTbl)
inspectionFile = fullfile(config.outputDir, 'lookahead_input_inspection.txt');
fid = fopen(inspectionFile, 'w');
if fid < 0
    error('run_lookahead_W3_path_generation_h2:InspectionOpenFailed', ...
        'Could not open inspection file: %s', inspectionFile);
end
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, 'Stage 2A look-ahead input inspection\n');
fprintf(fid, 'Generated at: %s\n\n', char(datetime('now')));
fprintf(fid, 'Project root: %s\n', config.rootDir);
fprintf(fid, 'Module root: %s\n\n', config.moduleDir);

fprintf(fid, 'Input file existence:\n');
fprintf(fid, '- data/location.csv: %d (%s)\n', isfile(config.locationFile), config.locationFile);
fprintf(fid, '- data/intensity.csv: %d (%s)\n', isfile(config.intensityFile), config.intensityFile);
fprintf(fid, '- data/landfall_7.csv: %d (%s)\n', isfile(config.landfallFile), config.landfallFile);
fprintf(fid, '- data/yuanqi/near_stage_msp_input.mat: %d (%s)\n', isfile(config.nearInputFile), config.nearInputFile);
fprintf(fid, '- requested fa_h2/fuzhu/terminalLoh_windmc/generate_terminal_loh_wind_mc_preview.m: %d (%s)\n', ...
    isfile(config.requestedWindMcScript), config.requestedWindMcScript);
fprintf(fid, '- root generate_terminal_loh_wind_mc_preview.m: %d (%s)\n', ...
    isfile(config.rootWindMcScript), config.rootWindMcScript);
fprintf(fid, '- terminalLoh_wdro/src/run_terminal_loh_wdro_preview_h2.m: %d (%s)\n\n', ...
    isfile(config.wdroStage1RunScript), config.wdroStage1RunScript);

fprintf(fid, 'Look-ahead config tables:\n');
fprintf(fid, '- lookahead_intensity_W3.csv: %d (%s)\n', ...
    isfile(config.intensityConfigFile), config.intensityConfigFile);
fprintf(fid, '- lookahead_location_W3.csv: %d (%s)\n', ...
    isfile(config.locationConfigFile), config.locationConfigFile);
fprintf(fid, '- lookahead_window_W3.csv: %d (%s)\n', ...
    isfile(config.windowConfigFile), config.windowConfigFile);
fprintf(fid, '- diagnostics directory: %s\n\n', config.diagnosticDir);

fprintf(fid, 'Original transition dimensions:\n');
fprintf(fid, '- location.csv size: %d x %d\n', size(P_loc, 1), size(P_loc, 2));
fprintf(fid, '- intensity.csv size: %d x %d\n', size(P_intensity, 1), size(P_intensity, 2));
fprintf(fid, '- landfall_7.csv size: %d x %d\n\n', size(P_landfall, 1), size(P_landfall, 2));

fprintf(fid, 'Location states:\n');
fprintf(fid, '- Original loc_id range inferred from window config: %d:%d\n', ...
    config.loc_min, config.loc_max);
fprintf(fid, '- Original location.csv has transition probabilities only; it has no coordinate columns.\n');
fprintf(fid, '- loc transition probabilities for look-ahead are read from lookahead_location_W3.csv.\n');
fprintf(fid, '- Extended loc_id range for halo_width=%d: %d:%d\n', ...
    config.halo_width, min(locExtTbl.loc_id), max(locExtTbl.loc_id));
fprintf(fid, '- loc_id may be <=0; MATLAB indexing uses loc_row_id/row_id from config_diagnostics/lookahead_location_ext.csv.\n\n');

fprintf(fid, 'Location coordinates:\n');
fprintf(fid, '- Existing windmc layout builds loc centers in build_h2_spatial_layout_preview.m.\n');
fprintf(fid, '- Original loc center x coordinates: %s\n', ...
    strtrim(sprintf('%.6g ', layout.locs.center_x_km)));
fprintf(fid, '- Original loc center y coordinates: %s\n', ...
    strtrim(sprintf('%.6g ', layout.locs.center_y_km)));
fprintf(fid, '- Existing centers are ordered along x; boundary adjacent spacing is used for halo extrapolation.\n');
fprintf(fid, '- No artificial impact decay coefficients are assigned to halo locs.\n\n');

fprintf(fid, 'Intensity and lf states:\n');
fprintf(fid, '- intensity transition probabilities for look-ahead are read from lookahead_intensity_W3.csv.\n');
fprintf(fid, '- intensity states inferred from intensity.csv: 1:%d\n', size(P_intensity, 1));
fprintf(fid, '- landfall states inferred from landfall_7.csv: 1:%d\n', size(P_landfall, 1));
fprintf(fid, '- lf=%d look-ahead source states are a=2:%d, loc=%d:%d.\n', ...
    config.lf_terminal, size(P_intensity, 1), config.loc_min, ...
    config.loc_max);
fprintf(fid, '- Source lf=%d state count: %d\n\n', config.lf_terminal, ...
    (size(P_intensity, 1) - 1) * (config.loc_max - config.loc_min + 1));

fprintf(fid, 'WindMC effect logic checked:\n');
fprintf(fid, '- Existing windmc obtains typhoon center as layout.locs.center_x_km/center_y_km for each loc.\n');
fprintf(fid, '- Grid line and road edge impacts are later based on distance from spatial objects to typhoon center.\n');
fprintf(fid, '- This Stage 2A task does not calculate wind, grid outage, road outage, D, A, or C.\n\n');

fprintf(fid, 'Look-ahead transition method:\n');
fprintf(fid, '- Original data/location.csv and data/intensity.csv are not modified.\n');
fprintf(fid, '- Config root now contains three main tables: lookahead_intensity_W3.csv, lookahead_location_W3.csv, and lookahead_window_W3.csv.\n');
fprintf(fid, '- Location row_id/coordinate mapping is kept in config_diagnostics/lookahead_location_ext.csv.\n');
fprintf(fid, '- The loc displacement-kernel diagnostic is kept in config_diagnostics/lookahead_transition_loc_delta_kernel_W3.csv.\n');
fprintf(fid, '- Kernel support: %d displacement values; prob sum = %.12g.\n', ...
    height(locKernelTbl), sum(locKernelTbl.prob));

if isfield(NearStageInput, 'Sets')
    fprintf(fid, '\nNearStageInput.Sets summary:\n');
    if isfield(NearStageInput.Sets, 'num_sites')
        fprintf(fid, '- num_sites = %.0f\n', double(NearStageInput.Sets.num_sites));
    end
    if isfield(NearStageInput.Sets, 'num_nodes')
        fprintf(fid, '- num_nodes = %.0f\n', double(NearStageInput.Sets.num_nodes));
    end
end
end

function write_lookahead_docs(config, locExtTbl, locKernelTbl)
docFile = fullfile(config.docsDir, 'README_lookahead_W3_path_generation.md');
fid = fopen(docFile, 'w');
if fid < 0
    error('run_lookahead_W3_path_generation_h2:DocOpenFailed', ...
        'Could not open doc file: %s', docFile);
end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '# W=3 Look-Ahead Typhoon Path Generation\n\n');
fprintf(fid, 'This Stage 2A module generates W=3 future typhoon paths for WDRO-TerminalLOH.\n\n');
fprintf(fid, '## Scope\n\n');
fprintf(fid, '- It only samples future typhoon intensity and location paths.\n');
fprintf(fid, '- It does not sample grid failures or road failures.\n');
fprintf(fid, '- It does not generate D,A,C consequence samples.\n');
fprintf(fid, '- It does not run WDRO-LP.\n');
fprintf(fid, '- It is not connected to MSP.\n\n');
fprintf(fid, '## Config Tables\n\n');
fprintf(fid, '- `lookahead_intensity_W3.csv`: intensity transition table with `from_a,to_a,prob`.\n');
fprintf(fid, '- `lookahead_location_W3.csv`: location transition table with `from_loc_id,to_loc_id,prob`.\n');
fprintf(fid, '- `lookahead_window_W3.csv`: key-value settings for W, P, seed, original loc range, halo width, and terminal lf.\n');
fprintf(fid, '- Intermediate mapping and kernel tables are under `output/stage2_lookahead_W3/config_diagnostics/`.\n\n');
fprintf(fid, '## Symbols\n\n');
fprintf(fid, '- `W`: look-ahead window count. Current W=%d.\n', config.W);
fprintf(fid, '- `P`: number of sampled paths per source lf=%d state. Current P=%d.\n', ...
    config.lf_terminal, config.P);
fprintf(fid, '- `tau`: look-ahead step, tau=1,...,W. It is not MSP lf.\n');
fprintf(fid, '- `loc_id`: physical look-ahead location identifier; halo ids may be zero or negative.\n');
fprintf(fid, '- `row_id`: positive MATLAB-safe row index for each loc_id.\n\n');
fprintf(fid, '## Location Extension\n\n');
fprintf(fid, '- Original loc range: %d:%d.\n', config.loc_min, config.loc_max);
fprintf(fid, '- Extended loc range: %d:%d.\n', min(locExtTbl.loc_id), max(locExtTbl.loc_id));
fprintf(fid, '- Halo coordinates are extrapolated from the existing windmc loc centers using boundary adjacent spacing.\n');
fprintf(fid, '- No artificial L/R impact decay coefficients are used.\n\n');
fprintf(fid, '## Transition Logic\n\n');
fprintf(fid, '- `data/location.csv`, `data/intensity.csv`, and `data/landfall_7.csv` are not modified.\n');
fprintf(fid, '- `lookahead_location_W3.csv` is the main look-ahead location transition table on the extended loc_id line.\n');
fprintf(fid, '- The current first version uses a displacement kernel inferred from original loc transitions.\n');
fprintf(fid, '- Displacement kernel support count: %d, probability sum %.12g.\n', height(locKernelTbl), sum(locKernelTbl.prob));
fprintf(fid, '- `lookahead_intensity_W3.csv` is the main look-ahead intensity transition table.\n\n');
fprintf(fid, '## Why MSP lf Is Not Changed\n\n');
fprintf(fid, 'The look-ahead horizon is represented by `tau` rather than `lf=8,9,10` because this module is not expanding the MSP state space. It only generates future typhoon path scenarios used later for offline TerminalLOH consequence sampling.\n\n');
fprintf(fid, '## Next Step\n\n');
fprintf(fid, 'The next stage should condition grid and road disaster sampling on each W=3 path, aggregate D,A,C consequence samples, and then run the WDRO-TerminalLOH LP on those consequence samples.\n');
end
