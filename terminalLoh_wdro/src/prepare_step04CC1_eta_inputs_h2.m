function prepare_step04CC1_eta_inputs_h2(workDir)
%PREPARE_STEP04CC1_ETA_INPUTS_H2 Freeze state19 inputs for eta screening.

started = tic;
workDir = string(workDir);
thisDir = fileparts(mfilename('fullpath'));
moduleDir = fileparts(thisDir);
rootDir = fileparts(moduleDir);
addpath(rootDir); addpath(thisDir);
assert_git_gate("task/002-stage2b-b3-smoke", ...
    "175c26f5ecefefef541b0769a28a3ab1972b804e");
if ~isfolder(workDir), mkdir(workDir); end
preparedFile = fullfile(workDir, 'prepared_inputs.mat');
if isfile(preparedFile)
    error('prepare_step04CC1_eta_inputs_h2:OutputExists', ...
        'Refusing to overwrite prepared inputs.');
end
diaryFile = fullfile(workDir, 'prepare_matlab_diary.txt');
diary(diaryFile); cleanupDiary = onCleanup(@()diary('off')); %#ok<NASGU>

stepJDir = fullfile(moduleDir, 'output', 'stage3j_wdro_input_freeze', 'run-001');
a2Mat = fullfile(rootDir, 'results', 'task-002-stage2b-b3-smoke', ...
    '44-extreme-formal-consequence-freeze', 'run-003', ...
    'extreme_formal_DAC_and_damage.mat');
inputPaths = [ ...
    string(fullfile(stepJDir, 'wdro_nominal_input.csv')); ...
    string(fullfile(stepJDir, 'wdro_nominal_input_DAC.mat')); ...
    string(fullfile(stepJDir, 'wdro_validation_1.csv')); ...
    string(fullfile(stepJDir, 'wdro_validation_1_DAC.mat')); ...
    string(fullfile(stepJDir, 'wdro_validation_2.csv')); ...
    string(fullfile(stepJDir, 'wdro_validation_2_DAC.mat')); ...
    string(a2Mat)];
expectedHashes = [ ...
    "366dc3c0b57bfd76aca92f51ae1db82b93c764c87fa15e8cb4dd32388d018168"; ...
    "6936a696f5cde137aca483f8c32adee33b52cbd90559a8e6395f3686c0712945"; ...
    "e39253d5af25d312b5d65cbb4efdf5ad4e907843f9203a46c47c7ca058ed3099"; ...
    "ca84afa01748d8c2929c372802861315254723424786b681a677e2f1420b6e3f"; ...
    "91c8e1233017d5d7dea9a87592f5bfb196e0d629733c10892fb539e4228c9b02"; ...
    "0bae20fa685940751edf5c5dd3d6c43a2d52293cbd1350c02b84736e914ec3b6"; ...
    "be530c72d92386f37ca4d4690d05d2907a1a03bf7fbc1d63eb25c1dce1b283e8"];
labels = ["nominal_csv";"nominal_DAC";"validation_1_csv"; ...
    "validation_1_DAC";"validation_2_csv";"validation_2_DAC"; ...
    "state19_extreme_formal_DAC"];
actualHashes = strings(size(inputPaths)); inputBytes = zeros(size(inputPaths));
for ii = 1:numel(inputPaths)
    if ~isfile(inputPaths(ii)), error('Missing frozen input: %s', inputPaths(ii)); end
    actualHashes(ii) = sha256_file(inputPaths(ii));
    info = dir(inputPaths(ii)); inputBytes(ii) = info.bytes;
end
hashPass = actualHashes == expectedHashes;
if ~all(hashPass), error('Frozen Step-03J/A2 input hash gate failed.'); end
inputManifest = table(labels, inputPaths, inputBytes, actualHashes, ...
    expectedHashes, hashPass, 'VariableNames', {'input_label','path', ...
    'bytes','sha256','expected_sha256','hash_pass'});
writetable(inputManifest, fullfile(workDir, 'frozen_input_manifest.csv'));

fprintf('PREPARE_STEP04CC1|recover_nominal_state19_R15000\n');
nominalStarted = tic;
[nominal, context] = recover_step03Y_prefix_entries_h2( ...
    rootDir, 19, 15000, false, "nominal");
nominalRuntime = toc(nominalStarted);
assert_replay(nominal, "nominal");

fprintf('PREPARE_STEP04CC1|recover_validation_1_state19_R15000\n');
validation1Started = tic;
[validation1, context1] = recover_step03Y_prefix_entries_h2( ...
    rootDir, 19, 15000, false, "validation-1");
validation1Runtime = toc(validation1Started);
assert_replay(validation1, "validation-1");

fprintf('PREPARE_STEP04CC1|recover_validation_2_state19_R15000\n');
validation2Started = tic;
[validation2, context2] = recover_step03Y_prefix_entries_h2( ...
    rootDir, 19, 15000, false, "validation-2");
validation2Runtime = toc(validation2Started);
assert_replay(validation2, "validation-2");
if max(abs([context1.Cap(:);context2.Cap(:)] - repmat(context.Cap(:),2,1))) > 0 || ...
        context1.M ~= context.M || context2.M ~= context.M || ...
        context1.gamma ~= context.gamma || context2.gamma ~= context.gamma
    error('Frozen role contexts are inconsistent.');
end
samePathOrder = isequal(double(nominal.identity.path_id), ...
    double(validation1.identity.path_id)) && ...
    isequal(double(nominal.identity.path_id), double(validation2.identity.path_id));
if ~samePathOrder
    error('Validation roles do not preserve the nominal typhoon path order.');
end

aggregation = aggregate_exact_period_scenarios_h2( ...
    nominal.Dperiod, nominal.Aperiod, nominal.Cperiod);
if aggregation.original_R ~= 15000 || aggregation.group_count ~= 7334 || ...
        aggregation.hash_collision_split_count ~= 0
    error('Formal nominal exact-aggregation gate failed.');
end

fprintf('PREPARE_STEP04CC1|load_state19_stress_subset\n');
S = load(a2Mat, 'identity', 'Dperiod', 'Aperiod', 'Cperiod');
state19Mask = double(S.identity.a0) == 4 & ...
    double(S.identity.loc0) == 5 & double(S.identity.lfw0) == 0;
stressIdentity = S.identity(state19Mask, :);
Dstress = S.Dperiod(state19Mask, :, :);
Astress = S.Aperiod(state19Mask, :, :, :);
Cstress = S.Cperiod(state19Mask, :, :, :); clear S;
stressPathId = double(stressIdentity.unique_path_id);
stressReplicaRank = double(stressIdentity.consequence_replica_rank);
pathValues = unique(stressPathId, 'sorted');
[~,~,pathGroup] = unique(stressPathId, 'sorted');
replicaCounts = accumarray(pathGroup, 1);
if numel(pathValues) ~= 27 || numel(stressPathId) ~= 135 || ...
        any(replicaCounts ~= 5) || any(double(stressIdentity.a0) ~= 4) || ...
        any(double(stressIdentity.loc0) ~= 5) || ...
        any(double(stressIdentity.lfw0) ~= 0)
    error('State19-only 27-path/135-replica stress gate failed.');
end

etaGrid = [0, 1e-4, 3e-4, 1e-3, 3e-3, 1e-2, 3e-2, 1e-1];
Cap = context.Cap(:).'; M = context.M; gamma = context.gamma;
if max(abs(Cap - [300,200,100,150])) > 1e-12
    error('Formal TerminalLOH capacity trace failed.');
end
DnominalGroup = aggregation.Dperiod;
AnominalGroup = aggregation.Aperiod;
CnominalGroup = aggregation.Cperiod;
qNominalGroup = aggregation.nominal_probability;
nominalGroupId = aggregation.group_id;
nominalMultiplicity = aggregation.multiplicity;
Dnominal = nominal.Dperiod; Anominal = nominal.Aperiod; Cnominal = nominal.Cperiod;
Dvalidation1 = validation1.Dperiod; Avalidation1 = validation1.Aperiod; Cvalidation1 = validation1.Cperiod;
Dvalidation2 = validation2.Dperiod; Avalidation2 = validation2.Aperiod; Cvalidation2 = validation2.Cperiod;
save(preparedFile, 'DnominalGroup','AnominalGroup','CnominalGroup', ...
    'qNominalGroup','nominalGroupId','nominalMultiplicity', ...
    'Dnominal','Anominal','Cnominal','Dvalidation1','Avalidation1', ...
    'Cvalidation1','Dvalidation2','Avalidation2','Cvalidation2', ...
    'Dstress','Astress','Cstress','stressIdentity','stressPathId', ...
    'stressReplicaRank','Cap','M','gamma','etaGrid','-v7.3');
preparedInfo = dir(preparedFile);

role = ["nominal";"validation-1";"validation-2"];
baseSeed = [20260723;20260724;20260725];
recoveryRuntimeSec = [nominalRuntime;validation1Runtime;validation2Runtime];
replayPass = true(3,1); maxDACError = [nominal.audit.max_DAC_error; ...
    validation1.audit.max_DAC_error;validation2.audit.max_DAC_error];
sameTyphoonPathOrder = true(3,1); sameTyphoonPathOrder(1) = true;
roleSummary = table(role,baseSeed,recoveryRuntimeSec,replayPass,maxDACError, ...
    sameTyphoonPathOrder,'VariableNames',{'dataset_role','base_joint_seed', ...
    'recovery_runtime_sec','replay_pass','max_DAC_error', ...
    'same_typhoon_path_order_as_nominal'});
writetable(roleSummary, fullfile(workDir, 'role_recovery_summary.csv'));
etaTable = table((1:numel(etaGrid)).', etaGrid(:), ...
    repmat("USER_FROZEN_INITIAL_SCREENING_GRID",numel(etaGrid),1), ...
    'VariableNames', {'case_id','eta','grid_status'});
writetable(etaTable, fullfile(workDir, 'eta_grid.csv'));
summary = table(19,15000,aggregation.group_count, ...
    aggregation.hash_collision_split_count,27,135,5, ...
    preparedInfo.bytes,sha256_file(preparedFile),toc(started), ...
    'VariableNames', {'initial_state_id','nominal_R','nominal_exact_group_count', ...
    'hash_collision_split_count','stress_path_count','stress_replica_count', ...
    'replicas_per_path','prepared_input_bytes','prepared_input_sha256', ...
    'prepare_runtime_sec'});
writetable(summary, fullfile(workDir, 'prepare_summary.csv'));

fid = fopen(fullfile(workDir, 'prepare_mechanical_audit.txt'), 'w');
cleanup = onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid, 'status=PASS\ninitial_state_id=19\nnominal_R=15000\n');
fprintf(fid, 'nominal_exact_groups=%d\nhash_collision_splits=%d\n', ...
    aggregation.group_count, aggregation.hash_collision_split_count);
fprintf(fid, 'validation_interpretation=same_typhoon_paths_second_layer_wind_and_resistance_redraw\n');
fprintf(fid, 'same_typhoon_path_order=1\nstress_empirical_probability_assigned=0\n');
fprintf(fid, 'stress_paths=27\nstress_replicas=135\nreplicas_per_path=5\nother_initial_states=0\n');
fprintf(fid, 'eta_grid=0,0.0001,0.0003,0.001,0.003,0.01,0.03,0.1\n');
fprintf(fid, 'R_by_R_matrix_constructed=0\nold_WDRO_called=0\nextreme_aware_solver_called=0\nMSP_called=0\n');
fprintf('PREPARE_STEP04CC1_COMPLETE|groups=%d|stress=27/135|runtime=%.3f\n', ...
    aggregation.group_count, toc(started));
end

function assert_replay(entry, role)
if ~entry.audit.all_final_DAC_exact || ...
        ~entry.audit.all_stream_hashes_match || entry.audit.max_DAC_error ~= 0
    error('Frozen %s state19 three-period replay failed.', role);
end
end

function assert_git_gate(expectedBranch, expectedHead)
[s1,b] = system('git branch --show-current');
[s2,h] = system('git rev-parse HEAD');
[s3,u] = system('git rev-parse @{upstream}');
if s1 ~= 0 || s2 ~= 0 || s3 ~= 0 || ...
        strtrim(string(b)) ~= expectedBranch || ...
        strtrim(string(h)) ~= expectedHead || strtrim(string(u)) ~= expectedHead
    error('Step-04C-C1 preparation Git gate failed.');
end
end

function hash = sha256_file(fileName)
fid = fopen(fileName, 'rb');
if fid < 0, error('Could not open %s.', fileName); end
cleanup = onCleanup(@()fclose(fid)); %#ok<NASGU>
md = java.security.MessageDigest.getInstance('SHA-256');
while true
    bytes = fread(fid, 1024*1024, '*uint8');
    if isempty(bytes), break; end
    md.update(typecast(bytes, 'int8'));
end
digest = typecast(md.digest(), 'uint8');
hash = lower(string(reshape(dec2hex(digest, 2).', 1, [])));
end
