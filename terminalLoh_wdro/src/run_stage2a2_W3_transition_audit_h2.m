clear; clc;

thisDir = fileparts(mfilename('fullpath'));
moduleDir = fileparts(thisDir);
rootDir = fileparts(moduleDir);
configDir = fullfile(moduleDir, 'config');
outputDir = fullfile(moduleDir, 'output', ...
    'stage2a2_W3_transition_audit', 'run-001');

taskId = "task-001";
stepId = "01-w3-transition-audit";
runId = "run-001";
runCommand = "cd('C:/Users/chaos/Desktop/biye/test/testH2_v2'); " + ...
    "run('terminalLoh_wdro/src/run_stage2a2_W3_transition_audit_h2.m');";
rowTolerance = 1e-10;
yTolerance = 1e-9;
yBase = -89.9999703886;
Wstep = 40;

legacyFiles = {
    fullfile(configDir, 'lookahead_intensity_W3.csv'), ...
    fullfile(configDir, 'lookahead_location_W3.csv'), ...
    fullfile(configDir, 'lookahead_window_W3.csv')};
candidateFiles = {
    fullfile(configDir, 'lookahead_intensity_postlandfall_W3.csv'), ...
    fullfile(configDir, 'lookahead_location_postlandfall_W3.csv'), ...
    fullfile(configDir, 'lookahead_lfw_postlandfall_W3.csv'), ...
    fullfile(configDir, 'lookahead_window_postlandfall_W3.csv')};

for ii = 1:numel(legacyFiles)
    if ~isfile(legacyFiles{ii})
        error('run_stage2a2_W3_transition_audit_h2:MissingLegacy', ...
            'Missing required legacy configuration: %s', legacyFiles{ii});
    end
end
for ii = 1:numel(candidateFiles)
    if ~isfile(candidateFiles{ii})
        error('run_stage2a2_W3_transition_audit_h2:MissingCandidate', ...
            'Expected existing candidate configuration for re-audit: %s', ...
            candidateFiles{ii});
    end
end
if ~isfolder(outputDir)
    mkdir(outputDir);
end

legacyHashBefore = strings(numel(legacyFiles), 1);
legacyBytesBefore = cell(numel(legacyFiles), 1);
for ii = 1:numel(legacyFiles)
    legacyHashBefore(ii) = sha256_file(legacyFiles{ii});
    legacyBytesBefore{ii} = read_file_bytes(legacyFiles{ii});
end

legacyIntensity = readtable(legacyFiles{1});
legacyLocation = readtable(legacyFiles{2});
legacyWindow = read_key_value_strings(legacyFiles{3});
require_vars(legacyIntensity, {'from_a','to_a','prob'}, legacyFiles{1});
require_vars(legacyLocation, {'from_loc_id','to_loc_id','prob'}, legacyFiles{2});
require_vars(legacyWindow, {'key','value'}, legacyFiles{3});

%% Generate intensity candidate from the legacy matrix.
intFrom = [];
intTo = [];
intProb = [];
intFrom(end+1,1) = 1;
intTo(end+1,1) = 1;
intProb(end+1,1) = 1;
for a = 2:5
    pDownLegacy = find_prob(legacyIntensity, 'from_a', a, 'to_a', a-1);
    pStayLegacy = find_prob(legacyIntensity, 'from_a', a, 'to_a', a);
    pUpLegacy = find_prob(legacyIntensity, 'from_a', a, 'to_a', a+1);
    pUpNew = 0.2 * pUpLegacy;
    removed = pUpLegacy - pUpNew;
    pDownNew = pDownLegacy + (2/3) * removed;
    pStayNew = pStayLegacy + (1/3) * removed;
    intFrom = [intFrom; a; a; a]; %#ok<AGROW>
    intTo = [intTo; a-1; a; a+1]; %#ok<AGROW>
    intProb = [intProb; pDownNew; pStayNew; pUpNew]; %#ok<AGROW>
end
intFrom = [intFrom; 6; 6];
intTo = [intTo; 5; 6];
intProb = [intProb; 0.60; 0.40];
intensityCandidate = table(intFrom, intTo, intProb, 'VariableNames', ...
    {'from_a','to_a','prob'});

%% Generate loc candidate by truncating and renormalizing the fixed kernel.
locDelta = (-3:3).';
locKernelProb = [0.04; 0.10; 0.22; 0.18; 0.28; 0.13; 0.05];
locationKernel = table(locDelta, locKernelProb, 'VariableNames', ...
    {'delta_loc','prob'});
locRows = {};
locCheckRows = {};
for fromLoc = -2:10
    toLoc = fromLoc + locDelta;
    valid = toLoc >= -2 & toLoc <= 10;
    normalizationMass = sum(locKernelProb(valid));
    normalizedProb = locKernelProb(valid) ./ normalizationMass;
    validTo = toLoc(valid);
    for jj = 1:numel(validTo)
        locRows(end+1,:) = {fromLoc, validTo(jj), normalizedProb(jj)}; %#ok<AGROW>
    end
    selfProb = normalizedProb(validTo == fromLoc);
    locCheckRows(end+1,:) = {fromLoc, sum(normalizedProb), ...
        normalizationMass, min(validTo-fromLoc), max(validTo-fromLoc), ...
        selfProb, fromLoc < 1 || fromLoc > 7}; %#ok<AGROW>
end
locationCandidate = cell2table(locRows, 'VariableNames', ...
    {'from_loc_id','to_loc_id','prob'});
locationRowChecks = cell2table(locCheckRows, 'VariableNames', ...
    {'from_loc_id','row_sum','retained_kernel_mass','min_delta', ...
    'max_delta','self_loop_prob','is_boundary_affected'});

%% Generate lfw candidate on states 0:3.
lfwDelta = [-1; 0; 1];
lfwKernelProb = [0.10; 0.20; 0.70];
lfwRows = {};
lfwCheckRows = {};
for fromLfw = 0:3
    toLfw = fromLfw + lfwDelta;
    valid = toLfw >= 0 & toLfw <= 3;
    retainedMass = sum(lfwKernelProb(valid));
    normalizedProb = lfwKernelProb(valid) ./ retainedMass;
    validTo = toLfw(valid);
    for jj = 1:numel(validTo)
        lfwRows(end+1,:) = {fromLfw, validTo(jj), normalizedProb(jj)}; %#ok<AGROW>
    end
    lfwCheckRows(end+1,:) = {fromLfw, sum(normalizedProb), retainedMass, ...
        min(validTo-fromLfw), max(validTo-fromLfw), ...
        normalizedProb(validTo == fromLfw)}; %#ok<AGROW>
end
lfwCandidate = cell2table(lfwRows, 'VariableNames', ...
    {'from_lfw','to_lfw','prob'});
lfwTransitionChecks = cell2table(lfwCheckRows, 'VariableNames', ...
    {'from_lfw','row_sum','retained_kernel_mass','min_delta', ...
    'max_delta','self_loop_prob'});

%% Generate window candidate.
windowKeys = ["W"; "slice_duration_h"; "Hres_total_h"; ...
    "lfw_initial"; "lfw_min"; "lfw_max"; "y_base"; "Wstep"; ...
    "P"; "P_role"; "loc_min"; "loc_max"; "halo_width"; ...
    "lf_terminal"];
windowValues = ["3"; "1"; "3"; "0"; "0"; "3"; ...
    string(sprintf('%.13f', yBase)); "40"; "20"; ...
    "legacy_diagnostic_sample_count"; "1"; "7"; "3"; "7"];
windowCandidate = table(windowKeys, windowValues, 'VariableNames', ...
    {'key','value'});

%% Read generated files back and audit their serialized contents.
intensityRead = readtable(candidateFiles{1});
locationRead = readtable(candidateFiles{2});
lfwRead = readtable(candidateFiles{3});
windowRead = read_key_value_strings(candidateFiles{4});
checkRows = {};
checkRows = add_check(checkRows, "FILE-01", "files", ...
    "legacy intensity required fields", ...
    has_vars(legacyIntensity, {'from_a','to_a','prob'}), "present", "present");
checkRows = add_check(checkRows, "FILE-02", "files", ...
    "legacy location required fields", ...
    has_vars(legacyLocation, {'from_loc_id','to_loc_id','prob'}), "present", "present");
checkRows = add_check(checkRows, "FILE-03", "files", ...
    "legacy window required fields", ...
    has_vars(legacyWindow, {'key','value'}), "present", "present");
checkRows = add_check(checkRows, "FILE-04", "files", ...
    "candidate required fields", ...
    has_vars(intensityRead, {'from_a','to_a','prob'}) && ...
    has_vars(locationRead, {'from_loc_id','to_loc_id','prob'}) && ...
    has_vars(lfwRead, {'from_lfw','to_lfw','prob'}) && ...
    has_vars(windowRead, {'key','value'}), "present", "present");
checkRows = add_check(checkRows, "FILE-05", "files", ...
    "candidate primary keys unique", ...
    height(unique(intensityRead(:,{'from_a','to_a'}),'rows')) == height(intensityRead) && ...
    height(unique(locationRead(:,{'from_loc_id','to_loc_id'}),'rows')) == height(locationRead) && ...
    height(unique(lfwRead(:,{'from_lfw','to_lfw'}),'rows')) == height(lfwRead) && ...
    numel(unique(windowRead.key)) == height(windowRead), "unique", "unique");
numericWindowKeys = ["W"; "slice_duration_h"; "Hres_total_h"; "P"; ...
    "random_seed"; "loc_min"; "loc_max"; "halo_width"; ...
    "lf_terminal"; "lfw_initial"; "lfw_min"; "lfw_max"; ...
    "y_base"; "Wstep"];
numericWindowMask = ismember(windowRead.key, numericWindowKeys);
numericWindowValues = str2double(windowRead.value(numericWindowMask));
knownWindowKeyPass = all(ismember(windowRead.key, ...
    [numericWindowKeys; "P_role"]));
checkRows = add_check(checkRows, "FILE-06", "files", ...
    "all candidate numeric values finite", ...
    all(isfinite(intensityRead{:,:}),'all') && ...
    all(isfinite(locationRead{:,:}),'all') && ...
    all(isfinite(lfwRead{:,:}),'all') && ...
    all(isfinite(numericWindowValues)) && knownWindowKeyPass, ...
    "finite numeric whitelist; P_role checked as text", ...
    "finite numeric whitelist; no numeric check on P_role");

checkRows = add_probability_checks(checkRows, intensityRead, 'from_a', ...
    "INT-PROB", rowTolerance);
checkRows = add_probability_checks(checkRows, locationRead, 'from_loc_id', ...
    "LOC-PROB", rowTolerance);
checkRows = add_probability_checks(checkRows, lfwRead, 'from_lfw', ...
    "LFW-PROB", rowTolerance);

%% Intensity-specific checks and comparison output.
intensityComparisonRows = cell(6, 10);
intensityMassPass = true;
upReducedPass = true;
upPositivePass = true;
downIncreasedPass = true;
for a = 1:6
    legacyDown = optional_prob(legacyIntensity, 'from_a', a, 'to_a', a-1);
    legacyStay = optional_prob(legacyIntensity, 'from_a', a, 'to_a', a);
    legacyUp = optional_prob(legacyIntensity, 'from_a', a, 'to_a', a+1);
    newDown = optional_prob(intensityRead, 'from_a', a, 'to_a', a-1);
    newStay = optional_prob(intensityRead, 'from_a', a, 'to_a', a);
    newUp = optional_prob(intensityRead, 'from_a', a, 'to_a', a+1);
    removed = legacyUp - newUp;
    intensityComparisonRows(a,:) = {a, legacyDown, legacyStay, legacyUp, ...
        newDown, newStay, newUp, removed, newDown-legacyDown, ...
        newStay-legacyStay};
    if a >= 2 && a <= 5
        intensityMassPass = intensityMassPass && ...
            abs(newUp - 0.2*legacyUp) <= rowTolerance && ...
            abs((newDown-legacyDown) - (2/3)*removed) <= rowTolerance && ...
            abs((newStay-legacyStay) - (1/3)*removed) <= rowTolerance;
        upReducedPass = upReducedPass && newUp < legacyUp;
        upPositivePass = upPositivePass && (legacyUp <= 0 || newUp > 0);
        downIncreasedPass = downIncreasedPass && newDown > legacyDown;
    end
end
intensityComparison = cell2table(intensityComparisonRows, 'VariableNames', ...
    {'a','legacy_down','legacy_stay','legacy_up','candidate_down', ...
    'candidate_stay','candidate_up','removed_up_mass', ...
    'down_mass_added','stay_mass_added'});
checkRows = add_check(checkRows, "INT-01", "intensity", ...
    "a=1 is absorbing", height(intensityRead(intensityRead.from_a==1,:)) == 1 && ...
    intensityRead.to_a(intensityRead.from_a==1) == 1 && ...
    abs(intensityRead.prob(intensityRead.from_a==1)-1) <= rowTolerance, ...
    "1->1", "1->1 with probability 1");
checkRows = add_check(checkRows, "INT-02", "intensity", ...
    "only adjacent intensity transitions", ...
    all(abs(intensityRead.to_a-intensityRead.from_a) <= 1), ...
    max(abs(intensityRead.to_a-intensityRead.from_a)), "<=1");
checkRows = add_check(checkRows, "INT-03", "intensity", ...
    "a=2:5 enhancement probability reduced", upReducedPass, ...
    "all reduced", "candidate up < legacy up");
checkRows = add_check(checkRows, "INT-04", "intensity", ...
    "legacy positive enhancement remains positive", upPositivePass, ...
    "all positive", ">0 when legacy >0");
checkRows = add_check(checkRows, "INT-05", "intensity", ...
    "a=2:5 weakening probability increased", downIncreasedPass, ...
    "all increased", "candidate down > legacy down");
checkRows = add_check(checkRows, "INT-06", "intensity", ...
    "removed enhancement mass allocated 2/3 and 1/3", intensityMassPass, ...
    "formula match", "exact within tolerance");
a6 = intensityRead(intensityRead.from_a==6,:);
checkRows = add_check(checkRows, "INT-07", "intensity", ...
    "a=6 has only transitions to 5 and 6", ...
    height(a6)==2 && isequal(sort(a6.to_a),[5;6]), ...
    strjoin(string(sort(a6.to_a)).',','), "5,6");
checkRows = add_check(checkRows, "INT-08", "intensity", ...
    "a=6 probabilities are 0.60 and 0.40", ...
    abs(find_prob(intensityRead,'from_a',6,'to_a',5)-0.60)<=rowTolerance && ...
    abs(find_prob(intensityRead,'from_a',6,'to_a',6)-0.40)<=rowTolerance, ...
    "0.60,0.40", "0.60,0.40");

%% Loc-specific checks.
expectedLocation = locationCandidate;
locationExactPass = tables_numeric_equal(locationRead, expectedLocation, rowTolerance);
internalPass = true;
for fromLoc = 1:7
    pM3 = find_prob(locationRead,'from_loc_id',fromLoc,'to_loc_id',fromLoc-3);
    pM2 = find_prob(locationRead,'from_loc_id',fromLoc,'to_loc_id',fromLoc-2);
    pM1 = find_prob(locationRead,'from_loc_id',fromLoc,'to_loc_id',fromLoc-1);
    p0 = find_prob(locationRead,'from_loc_id',fromLoc,'to_loc_id',fromLoc);
    pP1 = find_prob(locationRead,'from_loc_id',fromLoc,'to_loc_id',fromLoc+1);
    pP2 = find_prob(locationRead,'from_loc_id',fromLoc,'to_loc_id',fromLoc+2);
    pP3 = find_prob(locationRead,'from_loc_id',fromLoc,'to_loc_id',fromLoc+3);
    internalPass = internalPass && pP1>pP2 && pP2>pP3 && ...
        pM1>pM2 && pM2>pM3 && pP1>p0 && pM1>p0;
end
locStates = sort(unique(locationRead.from_loc_id));
checkRows = add_check(checkRows, "LOC-01", "location", ...
    "loc states cover -2:10", isequal(locStates,(-2:10).'), ...
    sprintf('%g:%g',min(locStates),max(locStates)), "-2:10");
checkRows = add_check(checkRows, "LOC-02", "location", ...
    "loc jumps do not exceed 3", ...
    all(abs(locationRead.to_loc_id-locationRead.from_loc_id)<=3), ...
    max(abs(locationRead.to_loc_id-locationRead.from_loc_id)), "<=3");
checkRows = add_check(checkRows, "LOC-03", "location", ...
    "internal loc kernel ordering", internalPass, ...
    "all internal states", "near > far and adjacent > stay");
checkRows = add_check(checkRows, "LOC-04", "location", ...
    "loc targets remain in -2:10", ...
    all(locationRead.to_loc_id>=-2 & locationRead.to_loc_id<=10), ...
    sprintf('%g:%g',min(locationRead.to_loc_id),max(locationRead.to_loc_id)), ...
    "-2:10");
checkRows = add_check(checkRows, "LOC-05", "location", ...
    "boundary rows equal deletion plus renormalization", locationExactPass, ...
    "exact generated matrix", "kernel truncation and renormalization");
[maxSelfProb, maxSelfIdx] = max(locationRowChecks.self_loop_prob);
maxSelfLoc = locationRowChecks.from_loc_id(maxSelfIdx);
checkRows = add_check(checkRows, "LOC-06", "location", ...
    "no boundary probability accumulation", locationExactPass, ...
    maxSelfProb, "no clamping; renormalization only");

%% Lfw-specific checks and y mapping.
expectedLfw = lfwCandidate;
lfwExactPass = tables_numeric_equal(lfwRead, expectedLfw, rowTolerance);
lfwStates = sort(unique(lfwRead.from_lfw));
checkRows = add_check(checkRows, "LFW-01", "lfw", ...
    "lfw states cover 0:3", isequal(lfwStates,(0:3).'), ...
    sprintf('%g:%g',min(lfwStates),max(lfwStates)), "0:3");
checkRows = add_check(checkRows, "LFW-02", "lfw", ...
    "lfw transitions are adjacent", ...
    all(abs(lfwRead.to_lfw-lfwRead.from_lfw)<=1), ...
    max(abs(lfwRead.to_lfw-lfwRead.from_lfw)), "<=1");
checkRows = add_check(checkRows, "LFW-03", "lfw", ...
    "internal lfw probabilities are 0.10, 0.20, 0.70", ...
    abs(find_prob(lfwRead,'from_lfw',1,'to_lfw',0)-0.10)<=rowTolerance && ...
    abs(find_prob(lfwRead,'from_lfw',1,'to_lfw',1)-0.20)<=rowTolerance && ...
    abs(find_prob(lfwRead,'from_lfw',1,'to_lfw',2)-0.70)<=rowTolerance && ...
    abs(find_prob(lfwRead,'from_lfw',2,'to_lfw',1)-0.10)<=rowTolerance && ...
    abs(find_prob(lfwRead,'from_lfw',2,'to_lfw',2)-0.20)<=rowTolerance && ...
    abs(find_prob(lfwRead,'from_lfw',2,'to_lfw',3)-0.70)<=rowTolerance, ...
    "0.10,0.20,0.70", "0.10,0.20,0.70");
checkRows = add_check(checkRows, "LFW-04", "lfw", ...
    "lfw boundaries use deletion and renormalization", lfwExactPass, ...
    "exact generated matrix", "renormalized valid kernel");
checkRows = add_check(checkRows, "LFW-05", "lfw", ...
    "lfw targets remain in 0:3", all(lfwRead.to_lfw>=0 & lfwRead.to_lfw<=3), ...
    sprintf('%g:%g',min(lfwRead.to_lfw),max(lfwRead.to_lfw)), "0:3");
lfwValues = (0:3).';
yValues = yBase + lfwValues * Wstep;
expectedY = [-89.9999703886; -49.9999703886; -9.9999703886; 30.0000296114];
lfwYMapping = table(lfwValues, yValues, expectedY, abs(yValues-expectedY), ...
    abs(yValues-expectedY)<=yTolerance, 'VariableNames', ...
    {'lfw','y_coord','expected_y_coord','abs_error','pass'});
checkRows = add_check(checkRows, "LFW-06", "lfw", ...
    "y = y_base + lfw*Wstep", all(lfwYMapping.pass), ...
    max(lfwYMapping.abs_error), sprintf('max error <= %.3g',yTolerance));
checkRows = add_check(checkRows, "LFW-07", "lfw", ...
    "nominal path 0->1->2->3 maps to approximately -90,-50,-10,30", ...
    all(abs(yValues-[-90;-50;-10;30])<1e-3), ...
    strjoin(compose('%.6f',yValues).',','), "approximately -90,-50,-10,30");

%% Window checks.
windowExpectedKeys = ["W";"slice_duration_h";"Hres_total_h"; ...
    "lfw_initial";"lfw_min";"lfw_max";"y_base";"Wstep";"P";"P_role"];
windowCheckRows = cell(numel(windowExpectedKeys),4);
for ii = 1:numel(windowExpectedKeys)
    key = windowExpectedKeys(ii);
    value = get_window_value(windowRead,key);
    expected = get_window_value(windowCandidate,key);
    passed = value == expected;
    if key ~= "P_role"
        passed = abs(str2double(value)-str2double(expected)) <= rowTolerance;
    end
    windowCheckRows(ii,:) = {key,value,expected,passed};
end
windowConfigCheck = cell2table(windowCheckRows,'VariableNames', ...
    {'key','value','expected','pass'});
checkRows = add_check(checkRows, "WIN-01", "window", "W=3", ...
    str2double(get_window_value(windowRead,"W"))==3, ...
    get_window_value(windowRead,"W"), "3");
checkRows = add_check(checkRows, "WIN-02", "window", ...
    "slice duration is 1 hour", ...
    str2double(get_window_value(windowRead,"slice_duration_h"))==1, ...
    get_window_value(windowRead,"slice_duration_h"), "1");
checkRows = add_check(checkRows, "WIN-03", "window", "Hres total is 3 hours", ...
    str2double(get_window_value(windowRead,"Hres_total_h"))==3, ...
    get_window_value(windowRead,"Hres_total_h"), "3");
checkRows = add_check(checkRows, "WIN-04", "window", "lfw initial is 0", ...
    str2double(get_window_value(windowRead,"lfw_initial"))==0, ...
    get_window_value(windowRead,"lfw_initial"), "0");
checkRows = add_check(checkRows, "WIN-05", "window", "Wstep is 40", ...
    str2double(get_window_value(windowRead,"Wstep"))==40, ...
    get_window_value(windowRead,"Wstep"), "40");
checkRows = add_check(checkRows, "WIN-06", "window", ...
    "P role is legacy diagnostic sample count", ...
    get_window_value(windowRead,"P_role")=="legacy_diagnostic_sample_count", ...
    get_window_value(windowRead,"P_role"), "legacy_diagnostic_sample_count");
checkRows = add_check(checkRows, "WIN-07", "window", ...
    "all required window values match", all(windowConfigCheck.pass), ...
    sum(windowConfigCheck.pass), height(windowConfigCheck));

%% Legacy protection check after all generation and audit calculations.
legacyHashAfter = strings(numel(legacyFiles), 1);
legacyUnchanged = true;
for ii = 1:numel(legacyFiles)
    legacyHashAfter(ii) = sha256_file(legacyFiles{ii});
    legacyUnchanged = legacyUnchanged && ...
        legacyHashAfter(ii) == legacyHashBefore(ii) && ...
        isequal(read_file_bytes(legacyFiles{ii}), legacyBytesBefore{ii});
end
checkRows = add_check(checkRows, "PROTECT-01", "protection", ...
    "legacy configurations unchanged by bytes and SHA-256", ...
    legacyUnchanged, strjoin(legacyHashAfter,' | '), ...
    strjoin(legacyHashBefore,' | '));

auditChecklist = cell2table(checkRows, 'VariableNames', ...
    {'check_id','category','description','passed','observed','expected','required'});
passCount = sum(auditChecklist.passed);
failCount = sum(~auditChecklist.passed);
auditStatus = "PASS";
if failCount > 0
    auditStatus = "FAIL";
end

%% Write complete local audit results.
writetable(auditChecklist, fullfile(outputDir,'audit_checklist.csv'));
writetable(intensityComparison, fullfile(outputDir, ...
    'intensity_legacy_vs_candidate.csv'));
writetable(intensityRead, fullfile(outputDir,'intensity_candidate_matrix.csv'));
writetable(locationRead, fullfile(outputDir,'location_candidate_matrix.csv'));
writetable(locationKernel, fullfile(outputDir,'location_delta_kernel.csv'));
writetable(locationRowChecks, fullfile(outputDir,'location_row_checks.csv'));
writetable(lfwRead, fullfile(outputDir,'lfw_candidate_matrix.csv'));
writetable(lfwTransitionChecks, fullfile(outputDir,'lfw_transition_checks.csv'));
writetable(lfwYMapping, fullfile(outputDir,'lfw_y_mapping.csv'));
writetable(windowConfigCheck, fullfile(outputDir,'window_config_check.csv'));

write_audit_summary(fullfile(outputDir,'audit_summary.md'), taskId, stepId, ...
    runId, runCommand, auditStatus, passCount, failCount, intensityComparison, ...
    locationKernel, maxSelfProb, maxSelfLoc, lfwKernelProb, yBase, Wstep, ...
    legacyUnchanged);
write_run_manifest(fullfile(outputDir,'run_manifest.txt'), taskId, stepId, ...
    runId, runCommand, auditStatus, passCount, failCount, legacyFiles, ...
    legacyHashBefore, legacyHashAfter, candidateFiles, outputDir);

fprintf('\nStage2A2 W3 transition audit finished.\n');
fprintf('Status: %s\n', auditStatus);
fprintf('PASS=%d, FAIL=%d\n', passCount, failCount);
fprintf('Maximum loc self-loop probability: %.12g at loc=%g\n', ...
    maxSelfProb, maxSelfLoc);
fprintf('Output directory: %s\n', outputDir);

if failCount > 0
    failedIds = strjoin(auditChecklist.check_id(~auditChecklist.passed), ', ');
    error('run_stage2a2_W3_transition_audit_h2:AuditFailed', ...
        'Required audit checks failed: %s', failedIds);
end

function require_vars(tbl,names,fileName)
for ii=1:numel(names)
    if ~ismember(names{ii},tbl.Properties.VariableNames)
        error('run_stage2a2_W3_transition_audit_h2:MissingColumn', ...
            '%s is missing required column %s.',fileName,names{ii});
    end
end
end

function tbl=read_key_value_strings(fileName)
opts=delimitedTextImportOptions('NumVariables',2);
opts.DataLines=[2 Inf];
opts.Delimiter=',';
opts.VariableNames={'key','value'};
opts.VariableTypes={'string','string'};
opts.ExtraColumnsRule='ignore';
opts.EmptyLineRule='read';
tbl=readtable(fileName,opts);
end

function tf=has_vars(tbl,names)
tf=all(ismember(names,tbl.Properties.VariableNames));
end

function p=find_prob(tbl,fromName,fromValue,toName,toValue)
mask=tbl.(fromName)==fromValue & tbl.(toName)==toValue;
if sum(mask)~=1
    error('run_stage2a2_W3_transition_audit_h2:MissingTransition', ...
        'Expected exactly one transition %g -> %g.',fromValue,toValue);
end
p=double(tbl.prob(mask));
end

function p=optional_prob(tbl,fromName,fromValue,toName,toValue)
mask=tbl.(fromName)==fromValue & tbl.(toName)==toValue;
if sum(mask)>1
    error('run_stage2a2_W3_transition_audit_h2:DuplicateTransition', ...
        'Duplicate transition %g -> %g.',fromValue,toValue);
elseif any(mask)
    p=double(tbl.prob(mask));
else
    p=0;
end
end

function rows=add_probability_checks(rows,tbl,fromName,prefix,tol)
rows=add_check(rows,prefix+"-01","probability", ...
    prefix+" probabilities are nonnegative",all(tbl.prob>=0), ...
    min(tbl.prob),">=0");
rows=add_check(rows,prefix+"-02","probability", ...
    prefix+" probabilities do not exceed 1",all(tbl.prob<=1), ...
    max(tbl.prob),"<=1");
states=unique(tbl.(fromName));
maxError=0;
for ii=1:numel(states)
    maxError=max(maxError,abs(sum(tbl.prob(tbl.(fromName)==states(ii)))-1));
end
rows=add_check(rows,prefix+"-03","probability", ...
    prefix+" row sums equal 1",maxError<=tol,maxError, ...
    sprintf('<=%.3g',tol));
end

function rows=add_check(rows,id,category,description,passed,observed,expected)
rows(end+1,:)={string(id),string(category),string(description),logical(passed), ...
    scalar_text(observed),scalar_text(expected),true};
end

function s=scalar_text(value)
if isstring(value)
    s=strjoin(value(:).',' | ');
elseif ischar(value)
    s=string(value);
elseif islogical(value) && isscalar(value)
    s=string(double(value));
elseif isnumeric(value) && isscalar(value)
    s=string(sprintf('%.15g',value));
elseif isnumeric(value)
    s=strjoin(compose('%.15g',value(:).'),' | ');
else
    s=string(value);
end
end

function tf=tables_numeric_equal(a,b,tol)
tf=isequal(a.Properties.VariableNames,b.Properties.VariableNames) && ...
    height(a)==height(b) && width(a)==width(b);
if tf
    tf=all(abs(double(a{:,:})-double(b{:,:}))<=tol,'all');
end
end

function value=get_window_value(tbl,key)
mask=tbl.key==key;
if sum(mask)~=1
    error('run_stage2a2_W3_transition_audit_h2:MissingWindowKey', ...
        'Expected exactly one window key %s.',key);
end
value=string(tbl.value(mask));
end

function bytes=read_file_bytes(fileName)
fid=fopen(fileName,'rb');
if fid<0
    error('run_stage2a2_W3_transition_audit_h2:OpenFailed', ...
        'Could not open %s.',fileName);
end
cleanup=onCleanup(@()fclose(fid));
bytes=fread(fid,Inf,'*uint8');
end

function hash=sha256_file(fileName)
bytes=read_file_bytes(fileName);
md=java.security.MessageDigest.getInstance('SHA-256');
md.update(typecast(bytes,'int8'));
digest=typecast(md.digest(),'uint8');
hash=lower(string(reshape(dec2hex(digest,2).',1,[])));
end

function write_audit_summary(fileName,taskId,stepId,runId,runCommand, ...
    status,passCount,failCount,intensityComparison,locationKernel, ...
    maxSelfProb,maxSelfLoc,lfwKernelProb,yBase,Wstep,legacyUnchanged)
fid=fopen(fileName,'w');
if fid<0,error('run_stage2a2_W3_transition_audit_h2:SummaryOpenFailed', ...
        'Could not open audit summary.');end
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'# W3 Transition Candidate Audit\n\n');
fprintf(fid,'- task_id: `%s`\n',taskId);
fprintf(fid,'- step_id: `%s`\n',stepId);
fprintf(fid,'- run_id: `%s`\n',runId);
fprintf(fid,'- status: `%s`\n',status);
fprintf(fid,'- MATLAB command: `%s`\n',runCommand);
fprintf(fid,'- PASS count: %d\n',passCount);
fprintf(fid,'- FAIL count: %d\n\n',failCount);
fprintf(fid,'## Intensity Candidate\n\n');
for a=2:5
    q=intensityComparison(intensityComparison.a==a,:);
    fprintf(fid,['- a=%d: enhancement %.12g -> %.12g; weakening ' ...
        '%.12g -> %.12g; stay %.12g -> %.12g.\n'],a,q.legacy_up, ...
        q.candidate_up,q.legacy_down,q.candidate_down,q.legacy_stay, ...
        q.candidate_stay);
end
fprintf(fid,'- a=6: 6->5=0.60 and 6->6=0.40.\n\n');
fprintf(fid,'## Location Candidate\n\n');
fprintf(fid,'- delta kernel: %s\n',strjoin(compose('%+d:%.2f', ...
    locationKernel.delta_loc,locationKernel.prob).',', '));
fprintf(fid,'- maximum self-loop probability: %.12g at loc=%g.\n', ...
    maxSelfProb,maxSelfLoc);
fprintf(fid,'- boundary targets are deleted and remaining mass is renormalized; no clamping is used.\n\n');
fprintf(fid,'## Lfw Candidate\n\n');
fprintf(fid,'- base backward/stay/forward probabilities: %.2f/%.2f/%.2f.\n', ...
    lfwKernelProb(1),lfwKernelProb(2),lfwKernelProb(3));
fprintf(fid,'- lfw backward motion is spatial trajectory variation, not time reversal or damage recovery.\n');
fprintf(fid,'- y = %.13f + lfw * %g.\n\n',yBase,Wstep);
fprintf(fid,'## Window and Scope\n\n');
fprintf(fid,'- W1/W2/W3 are three one-hour time windows; Hres=3 h.\n');
fprintf(fid,'- loc determines x and lfw determines y; W does not replace lfw.\n');
fprintf(fid,'- P=20 is only the legacy diagnostic sample count, not the full path count.\n');
fprintf(fid,'- legacy files unchanged: %d.\n',legacyUnchanged);
fprintf(fid,'- candidate probabilities are transparent engineering candidates and are not calibrated to real typhoon observations or finalized by the user.\n');
fprintf(fid,'- formal path generation is not connected.\n');
fprintf(fid,'- B3, WDRO, Gurobi, MSP, Foundation, and Persistence were not run.\n');
end

function write_run_manifest(fileName,taskId,stepId,runId,runCommand,status, ...
    passCount,failCount,legacyFiles,hashBefore,hashAfter,candidateFiles,outputDir)
fid=fopen(fileName,'w');
if fid<0,error('run_stage2a2_W3_transition_audit_h2:ManifestOpenFailed', ...
        'Could not open run manifest.');end
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'task_id=%s\n',taskId);
fprintf(fid,'step_id=%s\n',stepId);
fprintf(fid,'run_id=%s\n',runId);
fprintf(fid,'run_time=%s\n',char(datetime('now','Format','yyyy-MM-dd HH:mm:ss Z')));
fprintf(fid,'MATLAB_command=%s\n',runCommand);
fprintf(fid,'status=%s\n',status);
fprintf(fid,'pass_count=%d\n',passCount);
fprintf(fid,'fail_count=%d\n',failCount);
fprintf(fid,'output_directory=%s\n',outputDir);
for ii=1:numel(legacyFiles)
    fprintf(fid,'legacy_file_%d=%s\n',ii,legacyFiles{ii});
    fprintf(fid,'legacy_sha256_before_%d=%s\n',ii,hashBefore(ii));
    fprintf(fid,'legacy_sha256_after_%d=%s\n',ii,hashAfter(ii));
end
for ii=1:numel(candidateFiles)
    fprintf(fid,'candidate_file_%d=%s\n',ii,candidateFiles{ii});
end
fprintf(fid,'formal_path_generation_connected=false\n');
fprintf(fid,'B3_run=false\n');
fprintf(fid,'WDRO_run=false\n');
fprintf(fid,'Gurobi_run=false\n');
fprintf(fid,'MSP_run=false\n');
fprintf(fid,'candidate_probabilities_finalized=false\n');
end
