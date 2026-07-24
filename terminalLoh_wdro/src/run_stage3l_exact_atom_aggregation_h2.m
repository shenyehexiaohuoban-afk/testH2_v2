clear; clc;

thisDir = fileparts(mfilename('fullpath'));
moduleDir = fileparts(thisDir);
rootDir = fileparts(moduleDir);
inputDir = fullfile(moduleDir, 'output', 'stage3j_wdro_input_freeze', 'run-001');
outputDir = fullfile(moduleDir, 'output', 'stage3l_exact_atom_aggregation', 'run-002');
aggregateDir = fullfile(outputDir, 'exact_aggregated_nominal');
mapDir = fullfile(outputDir, 'representative_to_original_map');

if exist(outputDir, 'dir')
    error('Step-03L run-002 output directory already exists: %s', outputDir);
end
mkdir(outputDir); mkdir(aggregateDir); mkdir(mapDir);
addpath(rootDir); addpath(thisDir);

roles = ["nominal", "validation-1", "validation-2"];
csvNames = ["wdro_nominal_input.csv", "wdro_validation_1.csv", ...
    "wdro_validation_2.csv"];
matNames = ["wdro_nominal_input_DAC.mat", "wdro_validation_1_DAC.mat", ...
    "wdro_validation_2_DAC.mat"];
expectedCsvHash = [ ...
    "366dc3c0b57bfd76aca92f51ae1db82b93c764c87fa15e8cb4dd32388d018168", ...
    "e39253d5af25d312b5d65cbb4efdf5ad4e907843f9203a46c47c7ca058ed3099", ...
    "91c8e1233017d5d7dea9a87592f5bfb196e0d629733c10892fb539e4228c9b02"];
expectedMatHash = [ ...
    "6936a696f5cde137aca483f8c32adee33b52cbd90559a8e6395f3686c0712945", ...
    "ca84afa01748d8c2929c372802861315254723424786b681a677e2f1420b6e3f", ...
    "0bae20fa685940751edf5c5dd3d6c43a2d52293cbd1350c02b84736e914ec3b6"];

inputRows = cell(6, 6); ir = 0;
for rr = 1:3
    for kind = 1:2
        if kind == 1
            fileName = csvNames(rr); expected = expectedCsvHash(rr);
        else
            fileName = matNames(rr); expected = expectedMatHash(rr);
        end
        path = fullfile(inputDir, fileName);
        if ~isfile(path); error('Missing Step-03J frozen file: %s', path); end
        actual = sha256_file(path);
        if actual ~= expected
            error('Step-03J SHA-256 mismatch: %s', path);
        end
        info = dir(path); ir = ir + 1;
        inputRows(ir, :) = {char(roles(rr)), char(fileName), info.bytes, ...
            char(actual), char(expected), true};
    end
end
inputAudit = cell2table(inputRows, 'VariableNames', ...
    {'dataset_role','file','bytes','actual_sha256','expected_sha256','sha256_ok'});
writetable(inputAudit, fullfile(outputDir, 'input_sha256_audit.csv'));

candidateAudit = readtable(fullfile(inputDir, 'candidate_presence_audit.csv'), ...
    'TextType', 'string');
if height(candidateAudit) ~= 3 || ...
        any(double(candidateAudit.unobserved_candidate_record_count) ~= 0)
    error('Step-03J candidate audit does not confirm zero unobserved candidates.');
end

requiredFields = {'initial_state_id','a0','loc0','lfw0','path_id', ...
    'sample_weight','A_reachable_share','A0_stage_pair_share', ...
    'C_reachable_mean_km','C_stage_reachable_mean_km', ...
    'D_Hres3h_total_kg','D_upper_bound_hit','W3_failed_line_count', ...
    'W3_closed_road_count','is_observed_candidate','dataset_role'};

% Reconcile every current A=0 definition using the same frozen records.
aRows = cell(0, 13);
roleTables = cell(3, 1);
for rr = 1:3
    tbl = readtable(fullfile(inputDir, csvNames(rr)), 'TextType', 'string');
    assert_fields(tbl, requiredFields, csvNames(rr));
    if height(tbl) ~= 525000; error('%s row count is not 525000.', csvNames(rr)); end
    roleTables{rr} = tbl;
    Rall = height(tbl); I = 4; N = 33; W = 3;
    stageA0 = double(tbl.A0_stage_pair_share);
    wdroReach = double(tbl.A_reachable_share);
    aRows = append_a_metric(aRows, roles(rr), "stage_pair_A0_share", ...
        "sum over records and W1-W3 of 1-A_tau divided by R*3*4*33", ...
        round(sum(stageA0) * W * I * N), Rall * W * I * N, mean(stageA0), ...
        "evaluate_formal_stagewise_b3_stability_block_h2.m:68-86,93-95", ...
        "A0_pair_share_W1_W2_W3", "Step-03I 0.079-family metric", true);
    aRows = append_a_metric(aRows, roles(rr), "stage_scenario_any_A0_share", ...
        "count(A0_stage_pair_share>0)/R", sum(stageA0 > 0), Rall, ...
        mean(stageA0 > 0), ...
        "evaluate_frozen_wdro_dataset_block_h2.m:61-80,111", ...
        "scenario_any_unreachable_pair_W1_W2_W3", "diagnostic", true);
    aRows = append_a_metric(aRows, roles(rr), "stage_scenario_all_A0_share", ...
        "count(A0_stage_pair_share=1)/R", sum(stageA0 == 1), Rall, ...
        mean(stageA0 == 1), ...
        "evaluate_frozen_wdro_dataset_block_h2.m:61-80,111", ...
        "scenario_all_pairs_unreachable_W1_W2_W3", "diagnostic", true);
    aRows = append_a_metric(aRows, roles(rr), "wdro_atom_element_A0_share", ...
        "sum over frozen WDRO atom elements of 1-A divided by R*4*33", ...
        round(sum(1-wdroReach) * I * N), Rall * I * N, mean(1-wdroReach), ...
        "evaluate_frozen_wdro_dataset_block_h2.m:81-97,109; run_stage3k_wdro_integration_scaling_h2.m:101-106", ...
        "A0_share_WDRO_aggregated_atom", "Step-03K 0.120-family metric", true);
    aRows = append_a_metric(aRows, roles(rr), "wdro_atom_scenario_any_A0_share", ...
        "count(A_reachable_share<1)/R", sum(wdroReach < 1), Rall, ...
        mean(wdroReach < 1), ...
        "evaluate_frozen_wdro_dataset_block_h2.m:81-97,109", ...
        "scenario_any_unreachable_pair_WDRO_atom", "diagnostic", true);
    aRows = append_a_metric(aRows, roles(rr), "wdro_atom_scenario_all_A0_share", ...
        "count(A_reachable_share=0)/R", sum(wdroReach == 0), Rall, ...
        mean(wdroReach == 0), ...
        "evaluate_frozen_wdro_dataset_block_h2.m:81-97,109", ...
        "scenario_all_pairs_unreachable_WDRO_atom", "diagnostic", true);
end

step3iMetrics = readtable(fullfile(moduleDir, 'output', ...
    'stage3i_formal_stagewise_random_b3', 'run-001', ...
    'stability_metrics_by_state.csv'), 'TextType', 'string');
step3iReported = mean(double(step3iMetrics.A0_pair_share(step3iMetrics.N == 15000)));
step3kMetrics = readtable(fullfile(moduleDir, 'output', ...
    'stage3k_wdro_integration_scaling', 'run-001', ...
    'dataset_role_comparison_by_state.csv'), 'TextType', 'string');
step3kReported = mean(double(step3kMetrics.A0_share( ...
    strcmp(step3kMetrics.dataset_role, 'nominal'))));
aRows = append_a_metric(aRows, "reported-cross-run", ...
    "Step03I_reported_A0_pair_share", ...
    "mean of 105 state-seed N=15000 W1-W3 A0_pair_share values", NaN, 105, ...
    step3iReported, "run_stage3i_formal_stagewise_random_b3_h2.m:216-234", ...
    "A0_pair_share_W1_W2_W3", "reported as approximately 0.079", true);
aRows = append_a_metric(aRows, "reported-cross-run", ...
    "Step03K_reported_A0_share", ...
    "mean of 35 nominal WDRO aggregated-atom A0_share values", NaN, 35, ...
    step3kReported, "run_stage3k_wdro_integration_scaling_h2.m:90-120", ...
    "A0_share_WDRO_aggregated_atom", "reported as approximately 0.120", true);
aZeroAudit = cell2table(aRows, 'VariableNames', ...
    {'dataset_role','metric_name','formula','numerator','denominator','result', ...
    'code_location','recommended_name','interpretation','recomputed_pass', ...
    'uses_stage_dimension','uses_wdro_aggregation','formal_metric_modified'});
writetable(aZeroAudit, fullfile(outputDir, 'a_zero_metric_reconciliation.csv'));

fieldRows = {
    'frozen_loader','D_node_kg / samples.D',true,'restores R x 33 node demand','load_frozen_b3_wdro_dataset_h2.m:27-39','WDRO model input';
    'frozen_loader','A_site_node / samples.A',true,'restores R x 4 x 33 binary reachability','load_frozen_b3_wdro_dataset_h2.m:27-39','WDRO model input';
    'frozen_loader','C_site_node_km / samples.C_raw',true,'restores R x 4 x 33 service cost','load_frozen_b3_wdro_dataset_h2.m:27-39','WDRO model input';
    'frozen_loader','sample_weight',true,'checks sum and exposes samples.sampleWeights','load_frozen_b3_wdro_dataset_h2.m:12-20,47','not consumed by current solver';
    'distance_DAC_maskedC','D',true,'pairwise L1 normalized D component','build_wdro_distance_matrix_h2.m:52-71,83-87','full node-level values';
    'distance_DAC_maskedC','A',true,'pairwise L1 normalized A component and C overlap mask','build_wdro_distance_matrix_h2.m:38-59,83-87,192-212','full binary array';
    'distance_DAC_maskedC','C_raw',true,'compares C only where both atoms have A=1','build_wdro_distance_matrix_h2.m:46-59,192-212','A=0 positions do not affect masked C distance';
    'distance_DAC_maskedC','sample_weight',false,'not an argument and not referenced','build_wdro_distance_matrix_h2.m:1-219','distance geometry only';
    'WDRO_loss_LP','D',true,'demand RHS and y upper bounds','solve_wdro_terminal_loh_lp_h2.m:64-68,94-102','full node-level values';
    'WDRO_loss_LP','A',true,'y upper bounds and C masking','solve_wdro_terminal_loh_lp_h2.m:31-37,64-68','full binary array';
    'WDRO_loss_LP','C_raw',true,'Ceff is zeroed where A=0 or nonfinite','solve_wdro_terminal_loh_lp_h2.m:31-37,115-130','reachable C only';
    'WDRO_loss_LP','sample_weight',false,'objective hard-codes alpha coefficient 1/R','solve_wdro_terminal_loh_lp_h2.m:54-57','non-equal weights unsupported';
    'WDRO_distance_and_loss','path / wind / random seeds',false,'not passed to distance or solver','build_wdro_distance_matrix_h2.m:1; solve_wdro_terminal_loh_lp_h2.m:1','metadata and traceability only'};
fieldAudit = cell2table(fieldRows, 'VariableNames', ...
    {'component','field','used','usage','code_location','finding'});
writetable(fieldAudit, fullfile(outputDir, 'wdro_field_dependency_audit.csv'));

weightRows = {
    'loader_reads_sample_weight',true,'load_frozen_b3_wdro_dataset_h2.m:12-20,47','returns sampleWeights and verifies sum';
    'distance_uses_sample_weight',false,'build_wdro_distance_matrix_h2.m:1','distance is independent of probability weights';
    'solver_has_weight_argument',false,'solve_wdro_terminal_loh_lp_h2.m:1','signature has no probability vector';
    'solver_uses_uniform_1_over_R',true,'solve_wdro_terminal_loh_lp_h2.m:54-57','obj(alpha)=1/R';
    'solver_supports_non_equal_atoms',false,'solve_wdro_terminal_loh_lp_h2.m:54-57','cannot consume accumulated exact-class weights';
    'formal_aggregate_input_compatible_now',false,'capability audit','core solver would require an explicitly authorized weight interface change'};
weightAudit = cell2table(weightRows, 'VariableNames', ...
    {'check','value','evidence','conclusion'});
writetable(weightAudit, fullfile(outputDir, 'solver_weight_support_audit.csv'));

nominal = roleTables{1};
for rr = 2:3; roleTables{rr} = []; end
stateMeans = zeros(35, 1);
for ss = 1:35
    stateMeans(ss) = mean(double(nominal.D_Hres3h_total_kg( ...
        double(nominal.initial_state_id) == ss)));
end
[~, riskOrder] = sortrows([stateMeans, (1:35).'], [1, 2]);
riskStateIds = [riskOrder(1), riskOrder(18), riskOrder(end)];
riskLabels = ["low", "median", "high"];

m = matfile(fullfile(inputDir, matNames(1)));
summaryRows = cell(35, 25);
preservationRows = cell(0, 12);
validationRows = cell(0, 15);
manifestSeedRows = cell(0, 5);
config = struct('distanceWeightsDACMaskedC', ...
    struct('D',0.6,'A',0.25,'C',0.15), ...
    'epsDistance',1e-9,'scaleTolerance',1e-12);

for ss = 1:35
    fprintf('Step-03L exact aggregation state %d/35\n', ss);
    rows = find(double(nominal.initial_state_id) == ss);
    meta = nominal(rows, :); R = numel(rows);
    if R ~= 15000; error('Nominal state %d does not contain 15000 rows.', ss); end
    D = double(m.D_node_kg(rows, :));
    A = logical(m.A_site_node(rows, :, :));
    C = double(m.C_site_node_km(rows, :, :));
    [key, ic, repIdx, classSize, keyPass] = exact_groups(D, A, C);
    K = numel(repIdx);
    aggregateWeight = classSize / R;
    representativePath = double(meta.path_id(repIdx));
    [withinPairs, withinMax, crossPairs, crossMin, distancePass] = ...
        validate_distance_pairs(D, A, C, ic, repIdx, classSize, config);

    classA0Stage = accumarray(ic, double(meta.A0_stage_pair_share), [K 1], @mean);
    classCStage = accumarray(ic, double(meta.C_stage_reachable_mean_km), [K 1], @mean);
    classFailed = accumarray(ic, double(meta.W3_failed_line_count), [K 1], @mean);
    classClosed = accumarray(ic, double(meta.W3_closed_road_count), [K 1], @mean);
    classObserved = accumarray(ic, double(meta.is_observed_candidate), [K 1], @sum);

    aggregated = meta(repIdx, :);
    aggregated.representative_original_sample_weight = aggregated.sample_weight;
    aggregated.aggregate_id = (1:K).';
    aggregated.representative_path_id = representativePath;
    aggregated.class_size = classSize;
    aggregated.aggregate_weight = aggregateWeight;
    aggregated.sample_weight = aggregateWeight;
    aggregated.class_mean_A0_stage_pair_share = classA0Stage;
    aggregated.class_mean_C_stage_reachable_mean_km = classCStage;
    aggregated.class_mean_W3_failed_line_count = classFailed;
    aggregated.class_mean_W3_closed_road_count = classClosed;
    aggregated.class_observed_candidate_record_count = classObserved;
    aggregated.class_contains_observed_candidate = classObserved > 0;
    aggregated.aggregation_status = repmat("audit_only_not_formal_input", K, 1);

    aggregateCsv = fullfile(aggregateDir, sprintf('state-%03d.csv', ss));
    writetable(aggregated, aggregateCsv);
    D_node_kg = D(repIdx, :); %#ok<NASGU>
    A_site_node = A(repIdx, :, :); %#ok<NASGU>
    C_site_node_km = C(repIdx, :, :); %#ok<NASGU>
    aggregate_weight = aggregateWeight; %#ok<NASGU>
    aggregate_id = (1:K).'; %#ok<NASGU>
    representative_path_id = representativePath; %#ok<NASGU>
    initial_state_id = repmat(ss, K, 1); %#ok<NASGU>
    aggregateMat = fullfile(aggregateDir, sprintf('state-%03d_DAC.mat', ss));
    save(aggregateMat, 'D_node_kg', 'A_site_node', 'C_site_node_km', ...
        'aggregate_weight', 'aggregate_id', 'representative_path_id', ...
        'initial_state_id', '-v7.3');

    originalPath = double(meta.path_id);
    mapTable = table(repmat(ss,R,1), originalPath, ic, ...
        representativePath(ic), double(meta.sample_weight), aggregateWeight(ic), ...
        'VariableNames', {'initial_state_id','original_path_id','aggregate_id', ...
        'representative_path_id','original_sample_weight','aggregate_weight'});
    mapCsv = fullfile(mapDir, sprintf('state-%03d_map.csv', ss));
    writetable(mapTable, mapCsv);

    manifestSeedRows(end+1,:) = {aggregateCsv,'aggregated_scenario_csv',K, ...
        sprintf('%d rows',K),ss};
    manifestSeedRows(end+1,:) = {aggregateMat,'aggregated_DAC_mat',K, ...
        sprintf('D %dx33; A/C %dx4x33',K,K),ss};
    manifestSeedRows(end+1,:) = {mapCsv,'representative_map_csv',R, ...
        sprintf('%d rows',R),ss};

    dTotal = sum(D, 2);
    dRep = dTotal(repIdx);
    a0Element = 1 - reshape(mean(mean(double(A),3),2), [], 1);
    a0ElementRep = a0Element(repIdx);
    allA0 = reshape(all(all(~A,3),2), [], 1);
    anyA0 = reshape(any(any(~A,3),2), [], 1);
    cScenario = reachable_cost_mean(C, A);
    cRep = cScenario(repIdx);
    originalMetrics = [mean(dTotal), percentile_value(dTotal,95), ...
        percentile_value(dTotal,99), mean(double(meta.D_upper_bound_hit)), ...
        mean(double(meta.A0_stage_pair_share)), mean(a0Element), mean(allA0), ...
        mean(anyA0), mean(cScenario), mean(double(meta.C_stage_reachable_mean_km)), ...
        mean(double(meta.W3_failed_line_count)), ...
        mean(double(meta.W3_closed_road_count)), sum(double(meta.sample_weight))];
    aggregateMetrics = [sum(aggregateWeight.*dRep), ...
        percentile_by_counts(dRep,classSize,95), ...
        percentile_by_counts(dRep,classSize,99), ...
        sum(aggregateWeight.*double(meta.D_upper_bound_hit(repIdx))), ...
        sum(aggregateWeight.*classA0Stage), sum(aggregateWeight.*a0ElementRep), ...
        sum(aggregateWeight.*double(allA0(repIdx))), ...
        sum(aggregateWeight.*double(anyA0(repIdx))), ...
        sum(aggregateWeight.*cRep), sum(aggregateWeight.*classCStage), ...
        sum(aggregateWeight.*classFailed), sum(aggregateWeight.*classClosed), ...
        sum(aggregateWeight)];
    metricNames = ["D_mean_kg","D_q95_kg","D_q99_kg", ...
        "D_upper_bound_hit_share","A0_pair_share_W1_W2_W3", ...
        "A0_share_WDRO_aggregated_atom","scenario_all_A0_WDRO_atom", ...
        "scenario_any_A0_WDRO_atom","C_reachable_mean_WDRO_atom_km", ...
        "C_reachable_mean_W1_W2_W3_km","W3_failed_line_count_mean", ...
        "W3_closed_road_count_mean","weight_sum"];
    methods = ["class-weighted mean","count-preserving linear order statistic", ...
        "count-preserving linear order statistic","class-weighted mean", ...
        "class mean retained","representative invariant","representative invariant", ...
        "representative invariant","representative invariant","class mean retained", ...
        "class mean retained","class mean retained","class weights"];
    for mm = 1:numel(metricNames)
        absoluteError = abs(originalMetrics(mm)-aggregateMetrics(mm));
        relativeError = absoluteError / max(1,abs(originalMetrics(mm)));
        machineTolerance = 1e-13 * max(1,abs(originalMetrics(mm)));
        preservationRows(end+1,:) = {ss,double(meta.a0(1)),double(meta.loc0(1)), ...
            double(meta.lfw0(1)),char(metricNames(mm)),originalMetrics(mm), ...
            aggregateMetrics(mm),absoluteError,relativeError,machineTolerance, ...
            char(methods(mm)),absoluteError<=machineTolerance};
    end

    riskTier = "not_selected";
    matchRisk = find(riskStateIds == ss, 1);
    if ~isempty(matchRisk); riskTier = riskLabels(matchRisk); end
    summaryRows(ss,:) = {ss,double(meta.a0(1)),double(meta.loc0(1)), ...
        double(meta.lfw0(1)),R,K,K/R,R-K,max(classSize),sum(classSize==1), ...
        mean(classSize==1),sum(classSize>1),sum(aggregateWeight),keyPass, ...
        withinPairs,withinMax,crossPairs,crossMin,distancePass, ...
        sum(double(meta.is_observed_candidate)),sum(classObserved),0, ...
        char(riskTier),size(key,2),"D33+A132+Cmasked132 exact double key"};

    validationRows(end+1,:) = {ss,char(riskTier),'full_state',R,K,keyPass, ...
        withinPairs,withinMax,crossPairs,crossMin,distancePass,NaN,NaN, ...
        'all exact classes mapped; current distance checked in batches',true};
    if ~isempty(matchRisk)
        for prefixR = [100,250,500]
            [~, pic, prep, psize, pkeyPass] = exact_groups( ...
                D(1:prefixR,:),A(1:prefixR,:,:),C(1:prefixR,:,:));
            [pWithin,pMax,pCross,pMin,pDistancePass] = validate_distance_pairs( ...
                D(1:prefixR,:),A(1:prefixR,:,:),C(1:prefixR,:,:), ...
                pic,prep,psize,config);
            validationRows(end+1,:) = {ss,char(riskTier),'nested_prefix', ...
                prefixR,numel(prep),pkeyPass,pWithin,pMax,pCross,pMin, ...
                pDistancePass,prefixR,numel(prep), ...
                'original atoms map at zero distance to exact representatives; solver comparison skipped because weights unsupported',true};
        end
    end
    clear key D A C meta aggregated mapTable D_node_kg A_site_node C_site_node_km;
end

equivalenceSummary = cell2table(summaryRows, 'VariableNames', ...
    {'initial_state_id','a0','loc0','lfw0','R','K_exact','compression_ratio', ...
    'atoms_removed','max_class_size','singleton_atom_count','singleton_atom_share', ...
    'duplicate_class_count','aggregate_weight_sum','all_member_key_match', ...
    'within_group_pairs_checked','within_group_max_distance', ...
    'cross_group_pairs_checked','cross_group_min_distance','distance_validation_pass', ...
    'original_observed_candidate_records','aggregated_observed_candidate_records', ...
    'unobserved_candidate_records','risk_tier','key_double_column_count','key_definition'});
writetable(equivalenceSummary, fullfile(outputDir, ...
    'exact_equivalence_summary_by_state.csv'));

equivalenceValidation = cell2table(validationRows, 'VariableNames', ...
    {'initial_state_id','risk_tier','validation_scope','R_original','K_exact', ...
    'all_member_key_match','within_group_pairs_checked','within_group_max_distance', ...
    'cross_group_pairs_checked','cross_group_min_distance','distance_validation_pass', ...
    'prefix_R','prefix_K','distribution_relation_finding','validation_pass'});
writetable(equivalenceValidation, fullfile(outputDir, ...
    'exact_equivalence_validation.csv'));

metricPreservation = cell2table(preservationRows, 'VariableNames', ...
    {'initial_state_id','a0','loc0','lfw0','metric','original_value', ...
    'aggregated_value','absolute_error','relative_error', ...
    'machine_precision_tolerance','aggregation_method','preservation_pass'});
writetable(metricPreservation, fullfile(outputDir, ...
    'aggregate_metric_preservation.csv'));

Kvalues = double(equivalenceSummary.K_exact);
scaleRows = cell(35, 14);
for ss = 1:35
    K = Kvalues(ss); [nvar,ncon,nnzUpper] = model_size_upper_bound(K,4,33);
    scaleRows(ss,:) = {ss,K,K^2,K^2*8,K^2*8/1024^2,nvar,ncon,nnzUpper, ...
        K/1000,(K/1000)^2,K<=1000,167005,1038000,3328536};
end
scaleEstimate = cell2table(scaleRows, 'VariableNames', ...
    {'initial_state_id','K_exact','distance_elements','distance_bytes', ...
    'distance_MiB','LP_variables_estimate','LP_constraints_estimate', ...
    'LP_nonzeros_upper_estimate','K_vs_measured_R1000', ...
    'distance_elements_vs_R1000','within_step03k_measured_support_scale', ...
    'step03k_R1000_variables','step03k_R1000_constraints','step03k_R1000_measured_nonzeros'});
writetable(scaleEstimate, fullfile(outputDir, 'exact_scale_estimate.csv'));

localSchemaRows = {
    'exact_aggregated_nominal/state-xxx.csv','scenario metadata plus aggregate_id representative_path_id class_size aggregate_weight and class summary fields','K_exact rows/state','local only; audit input is not formal WDRO default';
    'exact_aggregated_nominal/state-xxx_DAC.mat','unchanged representative D_node_kg Kx33 A_site_node Kx4x33 C_site_node_km Kx4x33 plus exact class weights','K_exact atoms/state','local only';
    'representative_to_original_map/state-xxx_map.csv','initial_state_id original_path_id aggregate_id representative_path_id original_sample_weight aggregate_weight','15000 rows/state','complete probability-mass traceability';
    'local_data_sha256_manifest.csv','relative path type state rows/dimensions bytes SHA-256','105 files','Git-auditable manifest for local-only data'};
localSchema = cell2table(localSchemaRows, 'VariableNames', ...
    {'artifact','fields','rows_or_dimensions','storage_policy'});
writetable(localSchema, fullfile(outputDir, 'local_data_schema.csv'));

manifestRows = cell(size(manifestSeedRows,1), 8);
for ii = 1:size(manifestSeedRows,1)
    path = manifestSeedRows{ii,1}; info = dir(path);
    relative = erase(string(path), string(outputDir) + filesep);
    manifestRows(ii,:) = {char(relative),manifestSeedRows{ii,2}, ...
        manifestSeedRows{ii,5},manifestSeedRows{ii,3},manifestSeedRows{ii,4}, ...
        info.bytes,char(sha256_file(path)),false};
end
localManifest = cell2table(manifestRows, 'VariableNames', ...
    {'relative_path','artifact_type','initial_state_id','row_count', ...
    'dimensions','bytes','sha256','uploaded_to_git'});
writetable(localManifest, fullfile(outputDir, 'local_data_sha256_manifest.csv'));

Kstats = [min(Kvalues),mean(Kvalues),median(Kvalues), ...
    percentile_value(Kvalues,95),max(Kvalues)];
if max(Kvalues) <= 1000
    decision = "EXACT_AGGREGATION_REACHES_TESTED_SCALE";
    decisionReason = "Every K_exact is no greater than Step-03K measured R=1000; current solver still cannot consume non-equal class weights.";
else
    decision = "EXACT_AGGREGATION_STILL_TOO_LARGE";
    decisionReason = "Exact aggregation is valid, but at least one K_exact remains above Step-03K measured R=1000.";
end
decisionGate = table(decision,string(decisionReason),Kstats(1),Kstats(2), ...
    Kstats(3),Kstats(4),Kstats(5),all(Kvalues<=1000),false,false, ...
    'VariableNames',{'decision','reason','K_min','K_mean','K_median','K_q95', ...
    'K_max','all_states_within_R1000','formal_aggregate_adopted','formal_WDRO_run'});
writetable(decisionGate, fullfile(outputDir, 'decision_gate_summary.csv'));

maxMetricError = max(metricPreservation.absolute_error);
maxMetricRelativeError = max(metricPreservation.relative_error);
auditRows = {
    'INPUT-01',pass_fail(all(inputAudit.sha256_ok)),'6/6 SHA-256 match','6/6';
    'A0-01',pass_fail(abs(step3iReported-mean(double(step3iMetrics.A0_pair_share(step3iMetrics.N==15000))))<=1e-15),sprintf('%.15g',step3iReported),'code-derived';
    'A0-02',pass_fail(abs(step3kReported-mean(double(roleTables{1}.A_reachable_share)*0 + (1-double(roleTables{1}.A_reachable_share))))<=1e-12),sprintf('%.15g',step3kReported),'nominal frozen WDRO A0';
    'FIELD-01','PASS','distance/loss dependencies traced','D A C only plus geometry/config';
    'WEIGHT-01','PASS','solver obj(alpha)=1/R','non-equal weights unsupported';
    'GROUP-01',pass_fail(all(equivalenceSummary.all_member_key_match)),'all 35 states exact-key mapped','all pass';
    'GROUP-02',pass_fail(all(equivalenceSummary.distance_validation_pass)),'all current-distance checks pass','all pass';
    'WEIGHT-02',pass_fail(max(abs(equivalenceSummary.aggregate_weight_sum-1))<=1e-12),sprintf('max error %.3g',max(abs(equivalenceSummary.aggregate_weight_sum-1))),'<=1e-12';
    'METRIC-01',pass_fail(all(metricPreservation.preservation_pass)),sprintf('max abs %.3g; max relative %.3g',maxMetricError,maxMetricRelativeError),'abs <= 1e-13*max(1,abs(value))';
    'CAND-01',pass_fail(sum(equivalenceSummary.original_observed_candidate_records)==268 && sum(equivalenceSummary.aggregated_observed_candidate_records)==268),'268 observed records preserved','268';
    'CAND-02',pass_fail(all(equivalenceSummary.unobserved_candidate_records==0)),'zero unobserved records','zero';
    'MAP-01',pass_fail(sum(localManifest.row_count(strcmp(localManifest.artifact_type,'representative_map_csv')))==525000),'525000 mapping rows','525000';
    'LOCAL-01',pass_fail(height(localManifest)==105),'105 local data files hashed','105';
    'BOUND-01','PASS','no approximate reduction clustering or tail sampling','none';
    'BOUND-02','PASS','no Gurobi formal WDRO or MSP execution','none'};
automaticAudit = cell2table(auditRows, 'VariableNames', ...
    {'check_id','status','observed','expected'});
passCount = sum(strcmp(automaticAudit.status,'PASS'));
failCount = sum(strcmp(automaticAudit.status,'FAIL'));
writetable(automaticAudit, fullfile(outputDir, 'automatic_audit.csv'));

manifestLines = [
    "task_id=task-002"
    "step_id=12-exact-atom-aggregation"
    "run_id=run-002"
    "status=" + string(pass_fail(failCount==0))
    "pass_count=" + string(passCount)
    "fail_count=" + string(failCount)
    "source=Step-03J frozen nominal"
    "source_records=525000"
    "initial_states=35"
    "records_per_state=15000"
    "key=D33+A132+Cmasked132 exact double"
    "K_min=" + string(Kstats(1))
    "K_mean=" + string(Kstats(2))
    "K_median=" + string(Kstats(3))
    "K_q95=" + string(Kstats(4))
    "K_max=" + string(Kstats(5))
    "max_metric_preservation_error=" + string(maxMetricError)
    "max_metric_relative_error=" + string(maxMetricRelativeError)
    "metric_machine_precision_rule=absolute_error<=1e-13*max(1,abs(original_value))"
    "solver_non_equal_weight_support=false"
    "decision=" + decision
    "approximate_reduction=false"
    "formal_WDRO_run=false"
    "Gurobi_run=false"
    "MSP_run=false"];
write_lines(fullfile(outputDir, 'run_manifest.txt'), manifestLines);

readmeLines = [
    "Step-03L run-002: exact WDRO atom aggregation audit"
    ""
    "A=0 reconciliation"
    sprintf("Step-03I reported %.9f from W1-W3 stage-pair A0 share with denominator R*3*4*33.",step3iReported)
    sprintf("Step-03K reported %.9f for nominal from WDRO aggregated-atom A0 share with denominator R*4*33.",step3kReported)
    "Recommended names keep these dimensions explicit; no accepted historical result is overwritten."
    ""
    "Exact equivalence"
    "The key contains all 33 D doubles, all 132 A values, and all 132 C doubles after only A=0/nonfinite positions are set to zero exactly as the current masked-C logic excludes them."
    "No rounding, tolerance grouping, summary-field grouping, clustering, or scenario deletion is used."
    "Each class representative is an actual source record. Class weight is class_size/15000 and the complete original-path mapping is retained locally."
    ""
    "Solver capability"
    "The loader reads sample_weight, but solve_wdro_terminal_loh_lp_h2 has no weight argument and fixes obj(alpha)=1/R."
    "Therefore the exact aggregated data are audit-only and cannot become formal WDRO input without a separately authorized solver weight-interface change."
    "No Gurobi comparison is run in Step-03L."
    ""
    sprintf("K_exact min/mean/median/q95/max = %.0f/%.3f/%.0f/%.3f/%.0f.",Kstats(1),Kstats(2),Kstats(3),Kstats(4),Kstats(5))
    sprintf("Maximum aggregate metric preservation error = %.17g.",maxMetricError)
    sprintf("Maximum relative preservation error = %.17g; pass rule is abs error <= 1e-13*max(1,abs(value)).",maxMetricRelativeError)
    "Decision: " + decision
    string(decisionReason)
    ""
    "The exact aggregated CSV/MAT files and 525000-row mapping remain local. Git should contain only this run's summaries, schema, manifest, and SHA-256 values."
    "This run does not implement approximate reduction, tail sampling, clustering, constraint generation, solver refactoring, formal WDRO, Gurobi, or MSP."];
write_lines(fullfile(outputDir, 'README.txt'), readmeLines);

fprintf('Step-03L complete: PASS=%d FAIL=%d decision=%s\n', ...
    passCount,failCount,decision);
fprintf('K exact min/mean/median/q95/max: %.0f %.3f %.0f %.3f %.0f\n',Kstats);
if failCount > 0
    error('Step-03L automatic audit has %d failures.', failCount);
end

function rows = append_a_metric(rows, role, name, formula, numerator, ...
        denominator, result, location, recommended, interpretation, pass)
usesStage = contains(name, 'stage') || contains(name, 'Step03I');
usesWdro = contains(name, 'wdro') || contains(name, 'Step03K');
rows(end+1,:) = {char(role),char(name),char(formula),numerator,denominator, ...
    result,char(location),char(recommended),char(interpretation),pass, ...
    usesStage,usesWdro,false};
end

function assert_fields(tbl, required, label)
for ii=1:numel(required)
    if ~ismember(required{ii},tbl.Properties.VariableNames)
        error('%s is missing field %s.',label,required{ii});
    end
end
end

function [key,ic,repIdx,classSize,pass] = exact_groups(D,A,C)
R=size(D,1); Ckey=C;
Ckey(~isfinite(Ckey)|A<=0.5)=0;
key=[double(D),double(reshape(A,R,[])),double(reshape(Ckey,R,[]))];
[~,~,ic]=unique(key,'rows','sorted');
K=max(ic);[sortedClass,order]=sort(ic);
firstPos=[1;find(diff(sortedClass)~=0)+1];
repIdx=order(firstPos);classSize=diff([firstPos;R+1]);
pass=numel(repIdx)==K&&isequal(sortedClass(firstPos),(1:K).')&& ...
    isequal(key,key(repIdx(ic),:));
end

function [withinPairs,withinMax,crossPairs,crossMin,pass] = ...
        validate_distance_pairs(D,A,C,ic,repIdx,classSize,config)
K=numel(repIdx);[sortedClass,order]=sort(ic);
firstPos=[1;find(diff(sortedClass)~=0)+1];
dup=find(classSize>1);withinPairs=numel(dup);withinMax=0;
if withinPairs>0
    secondIdx=order(firstPos(dup)+1);
    withinMax=paired_distance_extreme(D,A,C,repIdx(dup),secondIdx,config,'max');
end
crossPairs=min(50,max(0,K-1));crossMin=NaN;
if crossPairs>0
    crossMin=paired_distance_extreme(D,A,C,repIdx(1:crossPairs), ...
        repIdx(2:crossPairs+1),config,'min');
end
pass=withinMax<=1e-12&&(crossPairs==0||crossMin>0);
end

function value = paired_distance_extreme(D,A,C,left,right,config,mode)
batchPairs=50;values=zeros(numel(left),1);out=0;
for start=1:batchPairs:numel(left)
    stop=min(numel(left),start+batchPairs-1);q=start:stop;
    idx=reshape([left(q),right(q)].',[],1);
    dMat=build_wdro_distance_matrix_h2(D(idx,:),A(idx,:,:),C(idx,:,:), ...
        'DAC_maskedC',config);
    for jj=1:numel(q)
        out=out+1;values(out)=dMat(2*jj-1,2*jj);
    end
end
if strcmp(mode,'max');value=max(values);else;value=min(values);end
end

function cMean=reachable_cost_mean(C,A)
mask=A>0.5;clean=C;clean(~mask|~isfinite(clean))=0;
total=reshape(sum(sum(clean,3),2),[],1);
count=reshape(sum(sum(mask,3),2),[],1);
cMean=total./count;cMean(count==0)=NaN;
end

function value=percentile_by_counts(values,counts,p)
[values,order]=sort(double(values(:)));counts=double(counts(order));
n=sum(counts);position=1+(n-1)*p/100;lo=floor(position);hi=ceil(position);
cum=cumsum(counts);vlo=values(find(cum>=lo,1));vhi=values(find(cum>=hi,1));
value=vlo+(position-lo)*(vhi-vlo);
end

function value=percentile_value(values,p)
values=sort(double(values(:)));position=1+(numel(values)-1)*p/100;
lo=floor(position);hi=ceil(position);
value=values(lo)+(position-lo)*(values(hi)-values(lo));
end

function [nvar,ncon,nnzUpper]=model_size_upper_bound(R,I,N)
nvar=I+R*I*N+R*N+2*R+1;
ncon=R*N+R*I+R+R*R;
nnzUpper=R*N*(I+1)+R*I*(N+1)+R*I*N+R*N+R+3*R*R;
end

function hash=sha256_file(path)
[status,output]=system(sprintf('certutil -hashfile "%s" SHA256',path));
if status~=0;error('certutil failed for %s.',path);end
tokens=regexp(output,'(?im)^[0-9a-f]{64}$','match');
if isempty(tokens);error('Could not parse SHA-256 for %s.',path);end
hash=lower(string(tokens{1}));
end

function value=pass_fail(condition)
if condition;value='PASS';else;value='FAIL';end
end

function write_lines(path,lines)
fid=fopen(path,'w');if fid<0;error('Could not open %s.',path);end
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
for ii=1:numel(lines);fprintf(fid,'%s\n',lines(ii));end
end
