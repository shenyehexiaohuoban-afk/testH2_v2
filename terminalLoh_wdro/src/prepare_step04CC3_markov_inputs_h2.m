function prepare_step04CC3_markov_inputs_h2(workDir)
%PREPARE_STEP04CC3_MARKOV_INPUTS_H2 Freeze Markov-shift state19 datasets.

started = tic;
workDir = string(workDir);
thisDir = fileparts(mfilename('fullpath'));
moduleDir = fileparts(thisDir);
rootDir = fileparts(moduleDir);
addpath(rootDir); addpath(thisDir);
assert_git_gate("task/002-stage2b-b3-smoke", ...
    "2468b931f8c2c57b82f8bc7605564c011c34762a");
if ~isfolder(workDir), mkdir(workDir); end
if isfile(fullfile(workDir,'prepare_mechanical_audit.txt'))
    error('prepare_step04CC3_markov_inputs_h2:OutputExists', ...
        'Refusing to overwrite an existing C3 preparation.');
end
diary(fullfile(workDir,'prepare_matlab_diary.txt'));
cleanupDiary = onCleanup(@()diary('off')); %#ok<NASGU>

c1File = fullfile(rootDir,'results','task-002-stage2b-b3-smoke', ...
    '46-flat-chi2-eta-calibration','run-003','eta_full_results.csv');
c2Dir = fullfile(rootDir,'results','task-002-stage2b-b3-smoke', ...
    '47-flat-chi2-independent-path-validation','run-002');
c2Readme = fullfile(c2Dir,'README.md');
c2Results = fullfile(c2Dir,'fixed_T_full_results.csv');
c2SeedAuditFile = fullfile(c2Dir,'independent_seed_and_collision_audit.csv');
c2ManifestFile = fullfile(c2Dir,'independent_dataset_manifest.csv');
mainPathFile = fullfile(moduleDir,'output','stage2a2_W3_path_sampling', ...
    'run-002','main_path_samples.csv');
seedMapFile = fullfile(moduleDir,'output','stage3j_wdro_input_freeze', ...
    'run-001','dataset_role_and_seed_map.csv');
a2ManifestFile = fullfile(rootDir,'results','task-002-stage2b-b3-smoke', ...
    '44-extreme-formal-consequence-freeze','run-003', ...
    'extreme_consequence_identity_manifest.csv');
geometryFile = fullfile(moduleDir,'output', ...
    'stage2_foundation_fix_Hres3h_Wstep40_reaudit', ...
    'foundation_fix_geometry_by_loc.csv');
configDir = fullfile(moduleDir,'config');
matrixFiles = [string(fullfile(configDir,'lookahead_intensity_postlandfall_W3.csv')); ...
    string(fullfile(configDir,'lookahead_location_postlandfall_W3.csv')); ...
    string(fullfile(configDir,'lookahead_lfw_postlandfall_W3.csv'))];

inputPaths = [string(c1File);string(c2Readme);string(c2Results); ...
    string(c2SeedAuditFile);string(c2ManifestFile);string(geometryFile); ...
    matrixFiles;string(mainPathFile);string(seedMapFile);string(a2ManifestFile)];
inputLabels = ["C1_eta_full_results";"C2_README";"C2_fixed_T_full_results"; ...
    "C2_seed_audit";"C2_dataset_manifest";"accepted_Wstep40_geometry"; ...
    "intensity_transition";"location_transition";"lfw_transition"; ...
    "accepted_main_paths";"Step03J_seed_map";"Step04CA2_identity_manifest"];
expectedHashes = [ ...
    "16947d17fc2a3ff4a30bb966e14b5b76a0bf19a27dec48722ab405b930c6daf0"; ...
    "dda0a47e8a00e5823aa7efe085519804a0920387f9864acb94902e136cf9d74e"; ...
    "d5684b4640f965850d4c2341e06290b56d9c04a19af452375316723bfb17ad74"; ...
    "23c26980cebae6c6565e6d0d83ce1d297e9a92070b1bafd561e29ef416a84baa"; ...
    "508397c130b45039a991e37d94890a52fb6039fea4e257e5e3967ae059b92452"; ...
    "d78a81b0e950abac717c454a297f4aa38131ea5ad090d4a6a9a7f48dd348ea9f"; ...
    "ea6c71ed9765a57577940560f45e9ad6003a69ef4bb9abae54b9deaaf78889e5"; ...
    "42d167a61478e05e2ff4eb9012e6c25d92a53060d2f00fb7ff60ee45f0139ca1"; ...
    "45cf74286b0aec48fe4a0ba77c66ab0847c2227402740bcc18a376da0eff6c29"; ...
    "972a8c58620c09ac19cfcfb29e8d6a3ed2819ef1a22dbd522043436418eb805d"; ...
    "1ffab8c48894c991b27dc440a419e38f2ff29d6b612f18605e65bea57fc7ae64"; ...
    "ec009c64f7533d599963609cb1b3b6505ba85451cfe4a8c250315966c834132e"];
actualHashes = strings(size(inputPaths)); inputBytes = zeros(size(inputPaths));
for ii = 1:numel(inputPaths)
    if ~isfile(inputPaths(ii)), error('Missing frozen input: %s',inputPaths(ii)); end
    actualHashes(ii) = sha256_file(inputPaths(ii)); info = dir(inputPaths(ii));
    inputBytes(ii) = info.bytes;
end
hashPass = actualHashes == expectedHashes;
if ~all(hashPass), error('Step-04C-C3 frozen-input hash gate failed.'); end
writetable(table(inputLabels,inputPaths,inputBytes,actualHashes,expectedHashes,hashPass, ...
    'VariableNames',{'input_label','path','bytes','sha256','expected_sha256','hash_pass'}), ...
    fullfile(workDir,'frozen_input_manifest.csv'));

decisions = read_frozen_decisions(c1File);
writetable(decisions,fullfile(workDir,'fixed_decision_source_audit.csv'));

intensityStates = (1:6).'; locationStates = (-2:10).'; lfwStates = (0:3).';
PA = build_transition_matrix(readtable(matrixFiles(1)),'from_a','to_a',intensityStates);
PLoc = build_transition_matrix(readtable(matrixFiles(2)), ...
    'from_loc_id','to_loc_id',locationStates);
PLfw = build_transition_matrix(readtable(matrixFiles(3)), ...
    'from_lfw','to_lfw',lfwStates);
[locationRisk,locationRanking] = build_location_risk(geometryFile,locationStates);
writetable(locationRanking,fullfile(workDir,'location_geometry_risk_ranking.csv'));

scenarioId = (1:7).';
scenarioLabel = ["nominal";"intensity-only";"location-only";"lfw-only"; ...
    "combined-mild";"combined-medium";"combined-strong"];
deltaIntensity = [0;0.05;0;0;0.02;0.05;0.10];
deltaLocation = [0;0;0.05;0;0.02;0.05;0.10];
deltaLfw = [0;0;0;0.05;0.02;0.05;0.10];
spec = table(scenarioId,scenarioLabel,deltaIntensity,deltaLocation,deltaLfw, ...
    repmat("P_delta=(1-delta)*P_nominal+delta*P_stress",7,1), ...
    repmat("existing_positive_support_only",7,1), ...
    repmat("location risk=-equal-weight mean Wstep40 d_system_min over lfw 0:3",7,1), ...
    'VariableNames',{'distribution_id','distribution_label','intensity_delta', ...
    'location_delta','lfw_delta','contamination_rule','support_rule','location_risk_rule'});
writetable(spec,fullfile(workDir,'markov_perturbation_spec.csv'));

nominalMatrices = {PA,PLoc,PLfw};
matrixNames = ["intensity","location","lfw"];
matrixStates = {intensityStates,locationStates,lfwStates};
riskValues = {double(intensityStates),locationRisk,double(lfwStates)};
allMatrices = cell(7,3); matrixRows = {}; auditRows = {};
for dd = 1:7
    deltas = [deltaIntensity(dd),deltaLocation(dd),deltaLfw(dd)];
    for mm = 1:3
        [Pdelta,Pstress,stressMask] = perturb_matrix(nominalMatrices{mm}, ...
            riskValues{mm},deltas(mm));
        allMatrices{dd,mm} = Pdelta;
        states = matrixStates{mm}; Pnom = nominalMatrices{mm};
        for rr = 1:numel(states)
            support = Pnom(rr,:) > 0; deterministic = sum(support) == 1;
            rowSumError = abs(sum(Pdelta(rr,:))-1);
            minProbability = min(Pdelta(rr,:));
            supportViolation = max([0,Pdelta(rr,~support)]);
            formulaError = max(abs(Pdelta(rr,:) - ...
                ((1-deltas(mm))*Pnom(rr,:) + deltas(mm)*Pstress(rr,:))));
            unchangedError = double(deterministic) * max(abs(Pdelta(rr,:)-Pnom(rr,:)));
            rowPass = rowSumError<=1e-12 && minProbability>=-1e-14 && ...
                supportViolation<=1e-14 && formulaError<=1e-12 && unchangedError<=1e-12;
            auditRows(end+1,:) = {dd,scenarioLabel(dd),matrixNames(mm),states(rr), ...
                deltas(mm),sum(support),deterministic,rowSumError,minProbability, ...
                supportViolation,formulaError,unchangedError, ...
                sum(abs(Pdelta(rr,:)-Pnom(rr,:))),rowPass}; %#ok<AGROW>
            for cc = find(support)
                matrixRows(end+1,:) = {dd,scenarioLabel(dd),matrixNames(mm), ...
                    states(rr),states(cc),deltas(mm),Pnom(rr,cc),Pstress(rr,cc), ...
                    Pdelta(rr,cc),riskValues{mm}(cc),stressMask(rr,cc), ...
                    deterministic}; %#ok<AGROW>
            end
        end
    end
end
matrixTable = cell2table(matrixRows,'VariableNames',{'distribution_id', ...
    'distribution_label','matrix_name','from_state','to_state','delta', ...
    'nominal_probability','stress_probability','perturbed_probability', ...
    'successor_risk_score','selected_highest_risk_successor','deterministic_row'});
matrixAudit = cell2table(auditRows,'VariableNames',{'distribution_id', ...
    'distribution_label','matrix_name','from_state','delta','nominal_support_size', ...
    'deterministic_row','row_sum_error','minimum_probability','support_violation', ...
    'contamination_formula_error','deterministic_unchanged_error','row_L1_change', ...
    'audit_pass'});
writetable(matrixTable,fullfile(workDir,'perturbed_transition_matrices.csv'));
writetable(matrixAudit,fullfile(workDir,'transition_matrix_audit.csv'));
if any(~matrixAudit.audit_pass), error('Perturbed transition matrix audit failed.'); end

namespace = "markov-perturbation-C3"; R = 15000;
pathSeeds=zeros(3,1); windSeeds=zeros(3,1); resistanceSeeds=zeros(3,1);
for ss=1:3
    pathSeeds(ss)=derive_seed(namespace,ss,"path");
    windSeeds(ss)=derive_seed(namespace,ss,"wind");
    resistanceSeeds(ss)=derive_seed(namespace,ss,"resistance");
end
expectedSeedMatrix=[1113527767,664410789,1303781022; ...
    326796064,69348633,697256691;1029622182,840401885,272840227];
if ~isequal([pathSeeds,windSeeds,resistanceSeeds],expectedSeedMatrix)
    error('Deterministic C3 seed derivation does not match the pre-run freeze.');
end
[seedAudit,seedPass] = audit_seeds(namespace,pathSeeds,windSeeds, ...
    resistanceSeeds,mainPathFile,seedMapFile,a2ManifestFile,c2SeedAuditFile);
writetable(seedAudit,fullfile(workDir,'seed_and_collision_audit.csv'));
if ~seedPass, error('C3 seed collision audit failed.'); end

nominalRaw=readtable(mainPathFile);
nominal=nominalRaw(double(nominalRaw.a0)==4 & double(nominalRaw.loc0)==5 & ...
    double(nominalRaw.lfw0)==0,:); clear nominalRaw;
if height(nominal)~=R || any(double(nominal.derived_seed)~=20279706)
    error('Accepted nominal state19 path gate failed.');
end
historicalKeys=cell(4,1); historicalLabels=["accepted_nominal"; ...
    "C2_dataset_001";"C2_dataset_002";"C2_dataset_003"];
historicalKeys{1}=[double(nominal.a_W1),double(nominal.loc_W1),double(nominal.lfw_W1), ...
    double(nominal.a_W2),double(nominal.loc_W2),double(nominal.lfw_W2), ...
    double(nominal.a_W3),double(nominal.loc_W3),double(nominal.lfw_W3)]; clear nominal;
c2Manifest=readtable(c2ManifestFile);
for ss=1:3
    row=c2Manifest(double(c2Manifest.dataset_id)==ss,:);
    if height(row)~=1||~isfile(string(row.local_mat_path))|| ...
            sha256_file(string(row.local_mat_path))~=string(row.local_mat_sha256)
        error('C2 local MAT hash gate failed for dataset %d.',ss);
    end
    C2=load(string(row.local_mat_path),'identity');
    historicalKeys{ss+1}=identity_key(C2.identity); clear C2;
end

datasetCount=21; datasetRows=cell(datasetCount,33); reproRows=cell(datasetCount,19);
frequencyRows={}; crnRows={}; allPathKeys=cell(3,7); rrDataset=0;
for ss=1:3
    rng(pathSeeds(ss),'twister');
    uniformA=rand(R,3); uniformLocation=rand(R,3); uniformLfw=rand(R,3);
    uniformHashes=[sha256_double(uniformA),sha256_double(uniformLocation),sha256_double(uniformLfw)];
    seedCrnHashes=strings(7,3);
    for dd=1:7
        rrDataset=rrDataset+1; datasetStarted=tic;
        fprintf('STEP04CC3_PREPARE_DATASET_START|seed=%d|distribution=%s|R=%d\n', ...
            ss,scenarioLabel(dd),R);
        matrices=allMatrices(dd,:);
        identity1=make_identity(ss,dd,R,namespace,pathSeeds(ss),windSeeds(ss), ...
            resistanceSeeds(ss),matrices{1},matrices{2},matrices{3}, ...
            locationStates,lfwStates,uniformA,uniformLocation,uniformLfw);
        identity2=make_identity(ss,dd,R,namespace,pathSeeds(ss),windSeeds(ss), ...
            resistanceSeeds(ss),matrices{1},matrices{2},matrices{3}, ...
            locationStates,lfwStates,uniformA,uniformLocation,uniformLfw);
        pathKey1=identity_key(identity1); pathKey2=identity_key(identity2);
        pathHash1=sha256_double(pathKey1); pathHash2=sha256_double(pathKey2);
        pathReplayPass=isequal(pathKey1,pathKey2)&&pathHash1==pathHash2;
        if ~pathReplayPass,error('Path replay failed for seed %d distribution %d.',ss,dd);end
        allPathKeys{ss,dd}=pathKey1;
        frequencyRows=[frequencyRows; transition_frequency_rows(dd,scenarioLabel(dd),ss, ...
            identity1,allMatrices(dd,:),matrixNames,matrixStates)]; %#ok<AGROW>

        formal1=generate_step04CA2_formal_consequences_h2(rootDir,identity1);
        firstHashes=collect_formal_hashes(formal1);
        firstScenarioHash=sha256_strings(formal1.scenario_sha256);
        firstDamageHash=sha256_strings(formal1.damage_sha256);
        qHash=sha256_double(formal1.wind_q);
        lineUHash=sha256_double(formal1.line_resistance_u);
        roadUHash=sha256_double(formal1.road_resistance_u);
        seedCrnHashes(dd,:)=[qHash,lineUHash,roadUHash];
        matPath=fullfile(workDir,sprintf('dataset_seed%03d_dist%03d.mat',ss,dd));
        if isfile(matPath),error('Refusing to overwrite %s.',matPath);end
        identity=formal1.identity;Dperiod=formal1.Dperiod;Aperiod=formal1.Aperiod;
        Cperiod=formal1.Cperiod;failed_line=formal1.failed_line;closed_road=formal1.closed_road;
        wind_mps=formal1.wind_mps;wind_q=formal1.wind_q;
        scenario_sha256=formal1.scenario_sha256;damage_sha256=formal1.damage_sha256;
        line_resistance_u=formal1.line_resistance_u;road_resistance_u=formal1.road_resistance_u;
        save(matPath,'identity','Dperiod','Aperiod','Cperiod','failed_line','closed_road', ...
            'wind_mps','wind_q','scenario_sha256','damage_sha256','line_resistance_u', ...
            'road_resistance_u','-v7.3');
        clear identity Dperiod Aperiod Cperiod failed_line closed_road wind_mps wind_q ...
            scenario_sha256 damage_sha256 line_resistance_u road_resistance_u formal1;

        formal2=generate_step04CA2_formal_consequences_h2(rootDir,identity2);
        secondHashes=collect_formal_hashes(formal2);
        secondScenarioHash=sha256_strings(formal2.scenario_sha256);
        secondDamageHash=sha256_strings(formal2.damage_sha256);
        formalReplayPass=all(firstHashes==secondHashes)&& ...
            firstScenarioHash==secondScenarioHash&&firstDamageHash==secondDamageHash&& ...
            qHash==sha256_double(formal2.wind_q)&& ...
            lineUHash==sha256_double(formal2.line_resistance_u)&& ...
            roadUHash==sha256_double(formal2.road_resistance_u);
        if ~formalReplayPass,error('Formal replay failed for seed %d distribution %d.',ss,dd);end
        clear formal2 identity1 identity2 pathKey2;

        info=dir(matPath); matHash=sha256_file(matPath); runtime=toc(datasetStarted);
        datasetRows(rrDataset,:)={rrDataset,ss,dd,scenarioLabel(dd),namespace, ...
            pathSeeds(ss),windSeeds(ss),resistanceSeeds(ss),R,1/R,1, ...
            deltaIntensity(dd),deltaLocation(dd),deltaLfw(dd),pathHash1, ...
            uniformHashes(1),uniformHashes(2),uniformHashes(3),qHash,lineUHash,roadUHash, ...
            firstHashes(1),firstHashes(2),firstHashes(3),firstHashes(4),firstHashes(5), ...
            firstHashes(6),firstScenarioHash,firstDamageHash,string(matPath),info.bytes,matHash,runtime};
        reproRows(rrDataset,:)={rrDataset,ss,dd,scenarioLabel(dd),pathHash1,pathHash2, ...
            pathReplayPass,firstHashes(1),secondHashes(1),firstHashes(2),secondHashes(2), ...
            firstHashes(3),secondHashes(3),firstScenarioHash,secondScenarioHash, ...
            firstDamageHash,secondDamageHash,formalReplayPass,runtime};
        fprintf('STEP04CC3_PREPARE_DATASET_COMPLETE|seed=%d|distribution=%s|runtime=%.3f\n', ...
            ss,scenarioLabel(dd),runtime);
    end
    for dd=1:7
        crnRows(end+1,:)={ss,dd,scenarioLabel(dd),uniformHashes(1),uniformHashes(2), ...
            uniformHashes(3),seedCrnHashes(dd,1),seedCrnHashes(dd,2),seedCrnHashes(dd,3), ...
            seedCrnHashes(dd,1)==seedCrnHashes(1,1), ...
            seedCrnHashes(dd,2)==seedCrnHashes(1,2), ...
            seedCrnHashes(dd,3)==seedCrnHashes(1,3)}; %#ok<AGROW>
    end
end

manifest=cell2table(datasetRows,'VariableNames',{'dataset_id','seed_id', ...
    'distribution_id','distribution_label','namespace','path_seed','wind_seed', ...
    'resistance_seed','sample_count','sample_weight','weight_sum','intensity_delta', ...
    'location_delta','lfw_delta','physical_path_sequence_sha256','path_uniform_A_sha256', ...
    'path_uniform_location_sha256','path_uniform_lfw_sha256','wind_uniform_sha256', ...
    'line_resistance_uniform_sha256','road_resistance_uniform_sha256','full_D_sha256', ...
    'full_A_sha256','full_C_sha256','full_failed_line_sha256','full_closed_road_sha256', ...
    'full_wind_mps_sha256','scenario_hash_sequence_sha256','damage_hash_sequence_sha256', ...
    'local_mat_path','local_mat_bytes','local_mat_sha256','generation_and_replay_runtime_sec'});
writetable(manifest,fullfile(workDir,'dataset_manifest.csv'));
repro=cell2table(reproRows,'VariableNames',{'dataset_id','seed_id','distribution_id', ...
    'distribution_label','path_hash_first','path_hash_replay','path_replay_pass', ...
    'D_hash_first','D_hash_replay','A_hash_first','A_hash_replay','C_hash_first', ...
    'C_hash_replay','scenario_hash_first','scenario_hash_replay','damage_hash_first', ...
    'damage_hash_replay','formal_replay_pass','generation_and_replay_runtime_sec'});
writetable(repro,fullfile(workDir,'dataset_reproducibility_audit.csv'));
crn=cell2table(crnRows,'VariableNames',{'seed_id','distribution_id', ...
    'distribution_label','path_uniform_A_sha256','path_uniform_location_sha256', ...
    'path_uniform_lfw_sha256','wind_uniform_sha256','line_resistance_uniform_sha256', ...
    'road_resistance_uniform_sha256','wind_CRN_matches_nominal', ...
    'line_resistance_CRN_matches_nominal','road_resistance_CRN_matches_nominal'});
writetable(crn,fullfile(workDir,'common_random_numbers_audit.csv'));
frequency=cell2table(frequencyRows,'VariableNames',{'distribution_id', ...
    'distribution_label','seed_id','matrix_name','from_state','transition_count', ...
    'maximum_absolute_frequency_error','row_L1_frequency_error', ...
    'six_sigma_plus_floor_tolerance','unobserved_outside_support_count', ...
    'frequency_status','frequency_audit_pass'});
writetable(frequency,fullfile(workDir,'transition_frequency_audit.csv'));

overlap=build_path_overlap(allPathKeys,historicalKeys,historicalLabels);
writetable(overlap,fullfile(workDir,'path_overlap_audit.csv'));
historicalReuse=overlap(startsWith(overlap.comparison_type,"C3_nominal_vs_history"),:);
perturbedReuse=overlap(overlap.comparison_type=="C3_CRN_distribution_vs_nominal",:);
pass=all(hashPass)&&seedPass&&all(matrixAudit.audit_pass)&& ...
    all(repro.path_replay_pass)&&all(repro.formal_replay_pass)&& ...
    all(crn.wind_CRN_matches_nominal)&&all(crn.line_resistance_CRN_matches_nominal)&& ...
    all(crn.road_resistance_CRN_matches_nominal)&&all(frequency.frequency_audit_pass)&& ...
    all(abs(manifest.weight_sum-1)<=1e-14)&& ...
    ~any(historicalReuse.exact_whole_batch_reuse)&& ...
    ~any(perturbedReuse.exact_whole_batch_reuse);
fid=fopen(fullfile(workDir,'prepare_mechanical_audit.txt'),'w');
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'status=%s\nnamespace=%s\nstate_id=19\nseed_count=3\ndistribution_count=7\ndataset_count=21\n',pass_fail(pass),namespace);
fprintf(fid,'rows_per_dataset=15000\nsample_weight=%.17g\nweight_sum_each=1\n',1/R);
fprintf(fid,'C1_decisions_read_directly=1\nTerminalLOH_optimized_on_C3=0\n');
fprintf(fid,'location_perturbation_executed=1\nlocation_risk_source=fixed_Wstep40_geometry_equal_weight_mean_over_lfw\n');
fprintf(fid,'matrix_support_preserved=1\nmatrix_rows_normalized=1\ndeterministic_rows_unchanged=1\n');
fprintf(fid,'common_path_uniforms_within_seed=1\ncommon_wind_uniforms_within_seed=1\ncommon_resistance_uniforms_within_seed=1\n');
fprintf(fid,'path_seed_collision_count=0\nwind_seed_collision_count=0\nresistance_seed_collision_count=0\n');
fprintf(fid,'reproducibility_pass=1\nold_WDRO_called=0\nchi2_probability_adversary_called=0\nextreme_aware_solver_called=0\nMSP_called=0\n');
if ~pass,error('Step-04C-C3 preparation mechanical audit failed.');end
fprintf('STEP04CC3_PREPARE_COMPLETE|datasets=21|R=15000|runtime=%.3f\n',toc(started));
end

function decisions=read_frozen_decisions(c1File)
t=readtable(c1File);etaWanted=[0;0.003;0.01];labels=["SAA";"ETA_0.003";"ETA_0.01"];
rows=zeros(3,1);for ii=1:3,hit=find(abs(double(t.eta)-etaWanted(ii))<=1e-14);if numel(hit)~=1,error('C1 eta row missing.');end;rows(ii)=hit;end
s=t(rows,:);T=[s.T1_kg,s.T2_kg,s.T3_kg,s.T4_kg];expected=[294.589913536808,138.832065024684,93.0093009300931,150;299.211738691929,137.483280118695,94.3580963878466,150;300,143.468150246686,100,150];
sourceError=max(abs(T-expected),[],2);
if any(sourceError>1e-10)||any(string(s.solver_status)~="OPTIMAL")||any(string(s.audit_status)~="PASS")||any(~logical(s.case_pass)),error('C1 frozen decision audit failed.');end
decisions=table((1:3).',labels,etaWanted,T(:,1),T(:,2),T(:,3),T(:,4),sum(T,2), ...
    s.T1_capacity_binding,s.T2_capacity_binding,s.T3_capacity_binding,s.T4_capacity_binding, ...
    s.capacity_binding_count,sourceError,repmat(string(c1File),3,1), ...
    repmat("C1_NOMINAL_OPTIMIZATION_FIXED_FOR_C3",3,1), ...
    'VariableNames',{'decision_id','decision_label','eta','T1_kg','T2_kg','T3_kg','T4_kg', ...
    'TerminalLOH_total_kg','T1_capacity_binding','T2_capacity_binding','T3_capacity_binding', ...
    'T4_capacity_binding','capacity_binding_count','source_max_abs_error','source_file','C3_usage'});
end

function [risk,ranking]=build_location_risk(geometryFile,states)
g=readtable(geometryFile);g=g(double(g.Wstep)==40,:);
if height(g)~=numel(states)*4||~isequal(sort(unique(double(g.stage_index))),(0:3).')
    error('Accepted Wstep40 geometry coverage gate failed.');
end
meanDistance=zeros(numel(states),1);minDistance=zeros(numel(states),1);maxDistance=zeros(numel(states),1);
for ii=1:numel(states)
    sub=g(double(g.loc)==states(ii),:);
    if height(sub)~=4||numel(unique(double(sub.stage_index)))~=4,error('Location geometry row gate failed.');end
    d=double(sub.d_system_min);meanDistance(ii)=mean(d);minDistance(ii)=min(d);maxDistance(ii)=max(d);
end
risk=-meanDistance;[~,order]=sort(meanDistance,'ascend');rank=zeros(numel(states),1);rank(order)=(1:numel(states)).';
ranking=table(states,meanDistance,minDistance,maxDistance,risk,rank, ...
    repmat("Wstep40 d_system_min equal-weight mean over lfw 0:3; lower distance is higher exposure",numel(states),1), ...
    repmat(string(geometryFile),numel(states),1), ...
    'VariableNames',{'location_state','mean_d_system_min','minimum_d_system_min', ...
    'maximum_d_system_min','risk_score_negative_mean_distance','exposure_rank', ...
    'ranking_rule','source_file'});
end

function [Pdelta,Pstress,selected]=perturb_matrix(Pnom,risk,delta)
Pstress=zeros(size(Pnom));selected=false(size(Pnom));
for rr=1:size(Pnom,1)
    support=find(Pnom(rr,:)>0);
    if numel(support)==1
        Pstress(rr,support)=1;selected(rr,support)=true;continue;
    end
    maxRisk=max(risk(support));ties=support(abs(risk(support)-maxRisk)<=1e-12);
    weights=Pnom(rr,ties);if sum(weights)>0,weights=weights/sum(weights);else,weights=ones(size(weights))/numel(weights);end
    Pstress(rr,ties)=weights;selected(rr,ties)=true;
end
Pdelta=(1-delta)*Pnom+delta*Pstress;
end

function identity=make_identity(seedId,distributionId,R,namespace,pathSeed,windSeed,resistanceSeed,PA,PLoc,PLfw,locStates,lfwStates,uA,uLoc,uLfw)
aPath=sample_chain(PA,4,uA);locPath=sample_chain(PLoc,5-locStates(1)+1,uLoc);lfwPath=sample_chain(PLfw,1,uLfw);
probability=path_probability(PA,PLoc,PLfw,4,5-locStates(1)+1,1,aPath,locPath,lfwPath);scenario=(1:R).';
identity=table(repmat(seedId,R,1),repmat(distributionId,R,1),repmat(namespace,R,1),scenario, ...
    repmat(4,R,1),repmat(5,R,1),zeros(R,1),aPath(:,1),locStates(locPath(:,1)),lfwStates(lfwPath(:,1)), ...
    aPath(:,2),locStates(locPath(:,2)),lfwStates(lfwPath(:,2)),aPath(:,3),locStates(locPath(:,3)),lfwStates(lfwPath(:,3)), ...
    repmat(pathSeed,R,1),repmat(windSeed,R,1),scenario,repmat(resistanceSeed,R,1),scenario, ...
    repmat("namespace_direct_position",R,1),probability,repmat(1/R,R,1), ...
    'VariableNames',{'seed_id','distribution_id','namespace','scenario_id','a0','loc0','lfw0', ...
    'a1','loc1','lfw1','a2','loc2','lfw2','a3','loc3','lfw3','path_seed','wind_seed', ...
    'wind_stream_position','resistance_seed','resistance_stream_position','resistance_stream_rule', ...
    'physical_path_probability','sample_weight'});
end

function rows=transition_frequency_rows(distributionId,label,seedId,identity,matrices,names,states)
rows={};currentFields={{'a0','a1','a2'},{'loc0','loc1','loc2'},{'lfw0','lfw1','lfw2'}};
nextFields={{'a1','a2','a3'},{'loc1','loc2','loc3'},{'lfw1','lfw2','lfw3'}};
for mm=1:3
    P=matrices{mm};s=states{mm};current=[];next=[];
    for tt=1:3,current=[current;double(identity.(currentFields{mm}{tt}))];next=[next;double(identity.(nextFields{mm}{tt}))];end %#ok<AGROW>
    for rr=1:numel(s)
        mask=current==s(rr);n=sum(mask);outside=0;
        if n==0,maxErr=NaN;l1=NaN;tol=NaN;status="NOT_VISITED";pass=true;
        else
            counts=zeros(1,numel(s));for cc=1:numel(s),counts(cc)=sum(next(mask)==s(cc));end
            freq=counts/n;maxErr=max(abs(freq-P(rr,:)));l1=sum(abs(freq-P(rr,:)));
            outside=sum(counts(P(rr,:)==0));sigma=sqrt(P(rr,:).*(1-P(rr,:))/n);
            tol=max(0.02,6*max(sigma)+1/n);pass=outside==0&&maxErr<=tol;status=pass_fail(pass);
        end
        rows(end+1,:)={distributionId,label,seedId,names(mm),s(rr),n,maxErr,l1,tol,outside,status,pass}; %#ok<AGROW>
    end
end
end

function overlap=build_path_overlap(keys,historical,historicalLabels)
rows={};
for ss=1:3
    for hh=1:numel(historical)
        rows(end+1,:)=comparison_row("C3_nominal_vs_history_"+historicalLabels(hh),ss,1,0,0,keys{ss,1},historical{hh},true); %#ok<AGROW>
    end
end
for pair=[1,2;1,3;2,3].'
    rows(end+1,:)=comparison_row("C3_nominal_seed_pairwise",pair(1),1,pair(2),1,keys{pair(1),1},keys{pair(2),1},true); %#ok<AGROW>
end
for ss=1:3
    for dd=2:7
        rows(end+1,:)=comparison_row("C3_CRN_distribution_vs_nominal",ss,dd,ss,1,keys{ss,dd},keys{ss,1},true); %#ok<AGROW>
    end
end
overlap=cell2table(rows,'VariableNames',{'comparison_type','left_seed_id','left_distribution_id', ...
    'right_seed_id','right_distribution_id','left_row_count','right_row_count', ...
    'same_row_position_count','same_row_position_share','exact_whole_batch_reuse', ...
    'left_unique_path_count','right_unique_path_count','unique_path_overlap_count', ...
    'left_rows_whose_path_occurs_in_right_share'});
end
function row=comparison_row(type,leftSeed,leftDist,rightSeed,rightDist,left,right,positionComparable)
lt=path_text(left);rt=path_text(right);if positionComparable&&size(left,1)==size(right,1),same=sum(all(left==right,2));else,same=0;end
exact=positionComparable&&isequal(left,right);ul=unique(lt);ur=unique(rt);inter=intersect(ul,ur);share=mean(ismember(lt,ur));
row={type,leftSeed,leftDist,rightSeed,rightDist,size(left,1),size(right,1),same,same/size(left,1),exact,numel(ul),numel(ur),numel(inter),share};
end

function [audit,pass]=audit_seeds(namespace,pathSeeds,windSeeds,resistanceSeeds,mainPathFile,seedMapFile,a2ManifestFile,c2SeedAuditFile)
main=readtable(mainPathFile);stepJ=readtable(seedMapFile);a2=readtable(a2ManifestFile);c2=readtable(c2SeedAuditFile);
historicalPath=unique([double(main.base_random_seed);double(main.derived_seed);(20260721:20260725).';reshape((20260721:20260725)+1000*(1:35).',[],1);double(c2.seed(string(c2.stream_type)=="path"))]);
historicalWind=unique([double(stepJ.base_joint_seed);double(stepJ.wind_seed);double(a2.wind_seed);double(c2.seed(string(c2.stream_type)=="wind"))]);
historicalResistance=unique([double(stepJ.base_joint_seed);double(stepJ.resistance_seed);double(a2.resistance_seed);double(c2.seed(string(c2.stream_type)=="resistance"))]);
historicalAll=unique([historicalPath;historicalWind;historicalResistance]);allC3=[pathSeeds;windSeeds;resistanceSeeds];rows=cell(9,12);rr=0;
for ss=1:3
    types=["path","wind","resistance"];seeds=[pathSeeds(ss),windSeeds(ss),resistanceSeeds(ss)];
    for tt=1:3
        rr=rr+1;seed=seeds(tt);type=types(tt);if type=="path",same=sum(historicalPath==seed);elseif type=="wind",same=sum(historicalWind==seed);else,same=sum(historicalResistance==seed);end
        internal=sum(allC3==seed)-1;anyHistorical=sum(historicalAll==seed);status=pass_fail(internal==0&&same==0&&anyHistorical==0);
        rows(rr,:)={ss,namespace,type,namespace+"|dataset_id="+ss+"|stream="+type,seed,1,15000,internal,same,anyHistorical, ...
            "historical main/convergence + Step03J + Step04CA2 + Step04CC2",status};
    end
end
audit=cell2table(rows,'VariableNames',{'seed_id','namespace','stream_type','derivation_text','seed', ...
    'stream_position_start','stream_position_end','C3_internal_collision_count', ...
    'same_stream_historical_collision_count','any_historical_seed_collision_count','historical_scope','status'});
pass=all(audit.status=="PASS");
end

function P=build_transition_matrix(tbl,fromName,toName,states)
P=zeros(numel(states),numel(states));for ii=1:height(tbl),from=find(states==double(tbl.(fromName)(ii)),1);to=find(states==double(tbl.(toName)(ii)),1);if isempty(from)||isempty(to),error('Unknown transition state.');end;P(from,to)=P(from,to)+double(tbl.prob(ii));end
if max(abs(sum(P,2)-1))>1e-10||any(P<0,'all'),error('Transition matrix gate failed.');end
end
function paths=sample_chain(P,initialIndex,u)
[N,W]=size(u);paths=zeros(N,W);current=repmat(initialIndex,N,1);for tt=1:W,next=zeros(N,1);for state=1:size(P,1),mask=current==state;if any(mask),cdf=cumsum(P(state,:));cdf(end)=1;next(mask)=sum(u(mask,tt)>cdf,2)+1;end;end;paths(:,tt)=next;current=next;end
end
function probability=path_probability(PA,PLoc,PLfw,a0,loc0,lfw0,aPath,locPath,lfwPath)
N=size(aPath,1);probability=ones(N,1);ca=repmat(a0,N,1);cl=repmat(loc0,N,1);cf=repmat(lfw0,N,1);for tt=1:3,probability=probability.*PA(sub2ind(size(PA),ca,aPath(:,tt))).*PLoc(sub2ind(size(PLoc),cl,locPath(:,tt))).*PLfw(sub2ind(size(PLfw),cf,lfwPath(:,tt)));ca=aPath(:,tt);cl=locPath(:,tt);cf=lfwPath(:,tt);end
end
function key=identity_key(identity),key=[double(identity.a1),double(identity.loc1),double(identity.lfw1),double(identity.a2),double(identity.loc2),double(identity.lfw2),double(identity.a3),double(identity.loc3),double(identity.lfw3)];end
function text=path_text(key),text=compose('%d|%d|%d|%d|%d|%d|%d|%d|%d',key(:,1),key(:,2),key(:,3),key(:,4),key(:,5),key(:,6),key(:,7),key(:,8),key(:,9));end
function seed=derive_seed(namespace,datasetId,stream),txt=namespace+"|dataset_id="+datasetId+"|stream="+stream;md=java.security.MessageDigest.getInstance('SHA-256');md.update(typecast(unicode2native(char(txt),'UTF-8'),'int8'));digest=typecast(md.digest(),'uint8');hex=lower(string(reshape(dec2hex(digest,2).',1,[])));seed=mod(hex2dec(extractBetween(hex,1,8)),2147483646)+1;end
function hashes=collect_formal_hashes(f),hashes=[string(f.full_D_sha256),string(f.full_A_sha256),string(f.full_C_sha256),string(f.full_failed_line_sha256),string(f.full_closed_road_sha256),string(f.full_wind_sha256)];end
function hash=sha256_strings(values),bytes=unicode2native(char(join(string(values),newline)),'UTF-8');md=java.security.MessageDigest.getInstance('SHA-256');md.update(typecast(bytes,'int8'));hash=digest_text(md);end
function hash=sha256_double(x),md=java.security.MessageDigest.getInstance('SHA-256');bytes=typecast(double(x(:)),'uint8');md.update(typecast(bytes,'int8'));hash=digest_text(md);end
function hash=sha256_file(fileName),fid=fopen(fileName,'rb');if fid<0,error('Could not open %s.',fileName);end;cleanup=onCleanup(@()fclose(fid));md=java.security.MessageDigest.getInstance('SHA-256');while true,bytes=fread(fid,1024*1024,'*uint8');if isempty(bytes),break;end;md.update(typecast(bytes,'int8'));end;hash=digest_text(md);end
function hash=digest_text(md),digest=typecast(md.digest(),'uint8');hash=lower(string(reshape(dec2hex(digest,2).',1,[])));end
function value=pass_fail(passed),if passed,value="PASS";else,value="FAIL";end,end
function assert_git_gate(expectedBranch,expectedHead),[s1,b]=system('git branch --show-current');[s2,h]=system('git rev-parse HEAD');[s3,u]=system('git rev-parse @{upstream}');if s1~=0||s2~=0||s3~=0||strtrim(string(b))~=expectedBranch||strtrim(string(h))~=expectedHead||strtrim(string(u))~=expectedHead,error('Step-04C-C3 preparation Git gate failed.');end,end
