function audit = build_foundation_fix_scope_audit_v2_h2( ...
    config, protectedBefore, mcTbl)
%BUILD_FOUNDATION_FIX_SCOPE_AUDIT_V2_H2 Build automatic scope evidence.

modifiedFileAudit = audit_modified_files(config);
outputAudit = audit_output_directories(config, protectedBefore);
sourceScan = scan_executed_sources(config.executedSourceFiles);
commonRng = audit_common_random_numbers(mcTbl, config.mcSourceFile);
selectorTest = test_three_way_selector();

protectedRows = modifiedFileAudit.category == "protected_MSP";
protectedFilesPass = all(modifiedFileAudit.automatic_check_pass(protectedRows));
oldRows = outputAudit.is_protected_old_output;
oldOutputPass = all(outputAudit.unchanged(oldRows));
newOutputDistinct = all(outputAudit.path_overlap_with_v2_output(oldRows) == 0);

generatedNames = string({dir(config.outputDir).name}.');
generatedNames = generatedNames(~ismember(generatedNames, ["."; ".."])) ;
unexpectedNow = setdiff(generatedNames, config.allowedV2OutputNames(:));
noFormalOutputPattern = ~any(contains(lower(generatedNames), ...
    ["b3", "path_prob", "terminal_loh_by_state", ...
    "lookahead_scenario_site_node"]));

audit = struct();
audit.modified_file_audit = modifiedFileAudit;
audit.output_directory_audit = outputAudit;
audit.source_scan = sourceScan;
audit.common_random_numbers = commonRng;
audit.selector_three_way_test = selectorTest;
audit.no_formal_B3_generated = evidence( ...
    sourceScan.no_B3_call && noFormalOutputPattern && isempty(unexpectedNow), ...
    "automatic_call_chain_and_output_whitelist", ...
    compose("B3 call hits=%d; unexpected v2 files=%d", ...
    sourceScan.B3_call_hit_count, numel(unexpectedNow)), "");
audit.no_WDRO_run = evidence( ...
    sourceScan.no_WDRO_call && noFormalOutputPattern, ...
    "automatic_call_chain_scan", ...
    compose("WDRO/Gurobi call hits in executed Foundation sources=%d", ...
    sourceScan.WDRO_call_hit_count), "");
audit.no_MSP_modified = evidence(protectedFilesPass && sourceScan.no_MSP_call, ...
    "automatic_protected_file_and_call_chain_audit", ...
    compose("protected MSP files unchanged since task start=%d; MSP call hits=%d", ...
    protectedFilesPass, sourceScan.MSP_call_hit_count), "");
audit.no_old_output_overwritten = evidence(oldOutputPass && newOutputDistinct, ...
    "automatic_directory_snapshot", ...
    compose("protected old directories unchanged=%d; v2 path distinct=%d", ...
    oldOutputPass, newOutputDistinct), "");
audit.workspace_complete_change_list = struct('pass', NaN, ...
    'verification_mode', "manual_verification_required", ...
    'evidence', "No .git repository or git executable is available for a complete workspace diff.", ...
    'warning', "manual verification required");
end

function T = audit_modified_files(config)
paths = [string(config.expectedModifiedFiles(:)); ...
    string(config.protectedMSPFiles(:))];
categories = [repmat("expected_task_change", ...
    numel(config.expectedModifiedFiles), 1); ...
    repmat("protected_MSP", numel(config.protectedMSPFiles), 1)];
expectedChange = categories == "expected_task_change";
n = numel(paths);
existsFlag = false(n, 1);
lastWrite = strings(n, 1);
bytes = nan(n, 1);
sha256 = strings(n, 1);
modifiedSinceStart = false(n, 1);
automaticPass = false(n, 1);
verification = strings(n, 1);
for ii = 1:n
    p = char(paths(ii));
    existsFlag(ii) = isfile(p);
    if existsFlag(ii)
        info = dir(p);
        dt = datetime(info.datenum, 'ConvertFrom', 'datenum');
        lastWrite(ii) = string(dt, 'yyyy-MM-dd HH:mm:ss.SSS');
        bytes(ii) = info.bytes;
        sha256(ii) = sha256_file(p);
        modifiedSinceStart(ii) = dt >= config.taskStartTime;
        if expectedChange(ii)
            automaticPass(ii) = modifiedSinceStart(ii);
            verification(ii) = "expected task file modified in task window";
        else
            automaticPass(ii) = ~modifiedSinceStart(ii);
            verification(ii) = "protected file not modified in task window";
        end
    else
        automaticPass(ii) = false;
        verification(ii) = "file missing";
    end
end
T = table(paths, categories, expectedChange, existsFlag, lastWrite, bytes, ...
    sha256, modifiedSinceStart, automaticPass, verification, ...
    'VariableNames', {'path', 'category', 'expected_change', 'exists', ...
    'last_write_time', 'bytes', 'sha256', 'modified_since_task_start', ...
    'automatic_check_pass', 'verification_note'});
manualRow = table(string(config.rootDir), "workspace_diff", false, true, ...
    "", NaN, "", false, false, ...
    "manual verification required: no Git repository/executable", ...
    'VariableNames', T.Properties.VariableNames);
T = [T; manualRow];
end

function T = audit_output_directories(config, before)
after = snapshot_directories(config.protectedOutputDirs);
T = before;
T.Properties.VariableNames = {'path', 'file_count_before', ...
    'latest_datenum_before', 'total_bytes_before'};
T.file_count_after = after.file_count;
T.latest_datenum_after = after.latest_datenum;
T.total_bytes_after = after.total_bytes;
T.unchanged = T.file_count_before == T.file_count_after & ...
    abs(T.latest_datenum_before - T.latest_datenum_after) <= 1e-12 & ...
    T.total_bytes_before == T.total_bytes_after;
T.is_protected_old_output = true(height(T), 1);
T.path_overlap_with_v2_output = startsWith(string(config.outputDir), ...
    T.path + filesep) | startsWith(T.path, string(config.outputDir) + filesep) | ...
    T.path == string(config.outputDir);
T.verification_mode = repmat("automatic_directory_snapshot", height(T), 1);

newRow = table(string(config.outputDir), 0, 0, 0, ...
    count_files(config.outputDir), latest_datenum(config.outputDir), ...
    total_bytes(config.outputDir), true, false, false, ...
    "automatic_new_output_path_check", 'VariableNames', T.Properties.VariableNames);
T = [T; newRow];
end

function scan = scan_executed_sources(files)
wdroPatterns = ["solve_wdro_terminal_loh_lp_h2\\s*\\(", ...
    "gurobi\\s*\\("];
mspPatterns = ["run_h2_with_options\\s*\\(", ...
    "train_models_h2\\s*\\(", "forward_pass_h2\\s*\\(", ...
    "backward_pass_h2\\s*\\(", "main_msp_h2_near\\s*\\("];
b3Patterns = ["build_lookahead_W3_DAC_samples_h2\\s*\\(", ...
    "run_lookahead_W3_B3[^\\n]*\\("];
wdroHits = 0;
mspHits = 0;
b3Hits = 0;
for ii = 1:numel(files)
    p = files{ii};
    if ~isfile(p)
        error('build_foundation_fix_scope_audit_v2_h2:MissingSource', ...
            'Executed source file is missing: %s', p);
    end
    text = strip_matlab_comments(string(fileread(p)));
    wdroHits = wdroHits + count_patterns(text, wdroPatterns);
    mspHits = mspHits + count_patterns(text, mspPatterns);
    b3Hits = b3Hits + count_patterns(text, b3Patterns);
end
scan = struct();
scan.WDRO_call_hit_count = wdroHits;
scan.MSP_call_hit_count = mspHits;
scan.B3_call_hit_count = b3Hits;
scan.no_WDRO_call = wdroHits == 0;
scan.no_MSP_call = mspHits == 0;
scan.no_B3_call = b3Hits == 0;
end

function out = audit_common_random_numbers(T, sourceFile)
required = {'Rmax', 'Wstep', 'a', 'loc', 'stage_index', 'mc_id', ...
    'common_random_seed', 'center_x', 'center_y', 'included_in_Hres3h', ...
    'slice_duration_h', 'eta_FC', 'LHV_H2_kWh_per_kg', 'source_node'};
for ii = 1:numel(required)
    if ~ismember(required{ii}, T.Properties.VariableNames)
        error('build_foundation_fix_scope_audit_v2_h2:MissingRngColumn', ...
            'MC table is missing %s.', required{ii});
    end
end
[G, ~] = findgroups(T(:, {'Rmax', 'a', 'loc', 'stage_index', 'mc_id'}));
pairCountPass = all(splitapply(@numel, T.Wstep, G) == 2);
seedPass = all(splitapply(@(x) max(x) == min(x), ...
    T.common_random_seed, G));
invariantPass = all(splitapply(@check_invariant_pair, T.center_x, ...
    T.included_in_Hres3h, T.slice_duration_h, T.eta_FC, ...
    T.LHV_H2_kWh_per_kg, T.source_node, G));
yPass = all(splitapply(@check_y_pair, T.center_y, T.stage_index, G));

source = string(fileread(sourceFile));
marker = strfind(source, 'function T = run_comparable_smoke_mc');
if isempty(marker)
    sourceOrderPass = false;
else
    mcSource = extractAfter(source, marker(1) - 1);
    uniformPos = strfind(mcSource, 'lineUniform = rand');
    roadUniformPos = strfind(mcSource, 'roadUniform = rand');
    wstepPos = strfind(mcSource, 'for wstep = config.WstepValues');
    sourceOrderPass = ~isempty(uniformPos) && ~isempty(roadUniformPos) && ...
        ~isempty(wstepPos) && uniformPos(1) < wstepPos(1) && ...
        roadUniformPos(1) < wstepPos(1);
end
detail = string(sprintf(['paired=%d; same_seed=%d; invariant_inputs=%d; ' ...
    'only_stage_y_changes=%d; uniforms_before_Wstep_loop=%d'], ...
    pairCountPass, seedPass, invariantPass, yPass, sourceOrderPass));
out = evidence(pairCountPass && seedPass && invariantPass && yPass && ...
    sourceOrderPass, "automatic_table_pair_and_source_order_scan", ...
    detail, "");
end

function tf = check_invariant_pair(x, included, duration, eta, lhv, source)
tf = numel(x) == 2 && max(x) == min(x) && ...
    max(included) == min(included) && max(duration) == min(duration) && ...
    max(eta) == min(eta) && max(lhv) == min(lhv) && ...
    max(source) == min(source);
end

function tf = check_y_pair(y, stageIndex)
if numel(y) ~= 2 || max(stageIndex) ~= min(stageIndex)
    tf = false;
elseif stageIndex(1) == 0
    tf = abs(y(1) - y(2)) <= 1e-10;
else
    tf = abs(y(1) - y(2)) > 1e-10;
end
end

function out = test_three_way_selector()
base = table([40;45], [3;3], [3;0], [3;0], [true;true], ...
    'VariableNames', {'candidate_Wstep', 'Rmax_count', ...
    'joint_support_Rmax_count', 'lower_W1_risk_Rmax_count', ...
    'physically_valid'});
[s40, ~, ~] = select_foundation_Wstep_recommendation_h2(base);
reverse = base;
reverse.joint_support_Rmax_count = [0;3];
reverse.lower_W1_risk_Rmax_count = [0;3];
[s45, ~, ~] = select_foundation_Wstep_recommendation_h2(reverse);
tie = base;
tie.joint_support_Rmax_count = [2;2];
tie.lower_W1_risk_Rmax_count = [2;2];
[sTie, ~, ~] = select_foundation_Wstep_recommendation_h2(tie);
pass = s40 == "recommend_40" && s45 == "recommend_45" && ...
    sTie == "inconclusive_40_45";
out = evidence(pass, "automatic_synthetic_three_case_test", ...
    compose("40_case=%s; 45_case=%s; tie_case=%s", s40, s45, sTie), "");
end

function out = evidence(pass, mode, detail, warningText)
out = struct('pass', logical(pass), 'verification_mode', string(mode), ...
    'evidence', string(detail), 'warning', string(warningText));
end

function T = snapshot_directories(paths)
T = table(strings(numel(paths), 1), zeros(numel(paths), 1), ...
    zeros(numel(paths), 1), zeros(numel(paths), 1), ...
    'VariableNames', {'path', 'file_count', 'latest_datenum', 'total_bytes'});
for ii = 1:numel(paths)
    p = paths{ii};
    T.path(ii) = string(p);
    T.file_count(ii) = count_files(p);
    T.latest_datenum(ii) = latest_datenum(p);
    T.total_bytes(ii) = total_bytes(p);
end
end

function n = count_files(p)
if ~isfolder(p)
    n = -1;
    return;
end
items = dir(fullfile(p, '**', '*'));
n = sum(~[items.isdir]);
end

function value = latest_datenum(p)
if ~isfolder(p)
    value = NaN;
    return;
end
items = dir(fullfile(p, '**', '*'));
items = items(~[items.isdir]);
if isempty(items)
    value = 0;
else
    value = max([items.datenum]);
end
end

function value = total_bytes(p)
if ~isfolder(p)
    value = -1;
    return;
end
items = dir(fullfile(p, '**', '*'));
items = items(~[items.isdir]);
if isempty(items)
    value = 0;
else
    value = sum([items.bytes]);
end
end

function n = count_patterns(text, patterns)
n = 0;
for ii = 1:numel(patterns)
    hits = regexp(text, patterns(ii), 'match', 'ignorecase');
    n = n + numel(hits);
end
end

function text = strip_matlab_comments(text)
lines = splitlines(text);
for ii = 1:numel(lines)
    p = strfind(lines(ii), '%');
    if ~isempty(p)
        lines(ii) = extractBefore(lines(ii), p(1));
    end
end
text = strjoin(lines, newline);
end

function hash = sha256_file(path)
fid = fopen(path, 'r');
if fid < 0
    hash = "";
    return;
end
cleanup = onCleanup(@() fclose(fid));
bytes = fread(fid, Inf, '*uint8');
md = java.security.MessageDigest.getInstance('SHA-256');
md.update(bytes);
digest = typecast(md.digest(), 'uint8');
hash = lower(string(reshape(dec2hex(digest, 2).', 1, [])));
end
