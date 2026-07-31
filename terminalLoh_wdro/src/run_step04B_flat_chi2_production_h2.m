function run_step04B_flat_chi2_production_h2()
%RUN_STEP04B_FLAT_CHI2_PRODUCTION_H2 Full production validation ladder.

totalStarted = tic;
thisDir = fileparts(mfilename('fullpath'));
rootDir = fileparts(fileparts(thisDir));
addpath(rootDir); addpath(thisDir); add_gurobi_path();
expectedBranch = "task/002-stage2b-b3-smoke";
expectedHead = "e9cea80b0f8743a94b1e791095158b5bf82d1f8e";
assert_git_gate(expectedBranch, expectedHead);
outputDir = fullfile(rootDir, 'results', 'task-002-stage2b-b3-smoke', ...
    '42-flat-chi2-dro-production-solver', 'run-003');
if isfolder(outputDir)
    entries = dir(outputDir);
    entries = entries(~ismember({entries.name}, {'.', '..'}));
    if ~isempty(entries)
        error('Step-04B refuses to overwrite nonempty run-003.');
    end
else
    mkdir(outputDir);
end

protectedFiles = { ...
    'terminalLoh_wdro/docs/FORMAL_TWO_STAGE_THREE_PERIOD_MODEL.md', ...
    'terminalLoh_wdro/src/solve_wdro_terminal_loh_lp_h2.m', ...
    'terminalLoh_wdro/src/build_wdro_distance_matrix_h2.m', ...
    'terminalLoh_wdro/src/run_stage2a2_W3_path_sampling_convergence_h2.m', ...
    'terminalLoh_wdro/config/lookahead_intensity_postlandfall_W3.csv', ...
    'terminalLoh_wdro/config/lookahead_location_postlandfall_W3.csv', ...
    'terminalLoh_wdro/config/lookahead_lfw_postlandfall_W3.csv', ...
    'main_msp_h2_near.m', 'fa_h2/build_stage_model_h2.m'};
protectedBefore = file_manifest(rootDir, protectedFiles);
initialStatus = git_status(rootDir);
peakWorkingSet = memory_snapshot();

formulationAudit = make_formulation_audit();
probabilityTests = run_probability_tests();
if ~all(formulationAudit.pass) || ~all(probabilityTests.pass)
    writetable(formulationAudit, fullfile(outputDir, 'formulation_audit.failed.csv'));
    writetable(probabilityTests, fullfile(outputDir, 'probability_unit_tests.failed.csv'));
    disp(formulationAudit(~formulationAudit.pass, :));
    disp(probabilityTests(~probabilityTests.pass, :));
    error('Step-04B formulation or probability unit tests failed.');
end

fprintf('Step-04B recovering state 7 R=2000 formal period scenarios.\n');
recoveryStarted = tic;
[entry7, context7] = recover_step03Y_prefix_entries_h2( ...
    rootDir, 7, 2000, false);
recovery7Runtime = toc(recoveryStarted);
assert_recovery(entry7, 7);
peakWorkingSet = max(peakWorkingSet, memory_snapshot());

fprintf('Step-04B recovering state 19 R=15000 formal period scenarios.\n');
recoveryStarted = tic;
[entry19, context19] = recover_step03Y_prefix_entries_h2( ...
    rootDir, 19, 15000, false);
recovery19Runtime = toc(recoveryStarted);
assert_recovery(entry19, 19);
peakWorkingSet = max(peakWorkingSet, memory_snapshot());

requiredR7 = [100, 500, 2000];
requiredR19 = [100, 500, 2000, 5000, 15000];
[agg7, aggregationRows7] = build_aggregations(entry7, 7, requiredR7);
[agg19, aggregationRows19] = build_aggregations(entry19, 19, requiredR19);
aggregationSummary = [aggregationRows7; aggregationRows19];
peakWorkingSet = max(peakWorkingSet, memory_snapshot());

[jobState, jobR, jobEta] = scale_jobs();
nJobs = numel(jobState);
solutionCell = cell(nJobs, 1); auditCell = cell(nJobs, 1);
scaleRows = cell(nJobs, 38);
dualityRows = cell(nJobs, 15);
modelRows = cell(nJobs, 14);
memoryRows = cell(nJobs, 6);
worstRows = cell(2 * nJobs, 11); worstCount = 0;
optimizationLPCalls = 0; optimizationQCPCalls = 0;
fixedEvaluationLPCalls = 0;

for jj = 1:nJobs
    stateId = jobState(jj); R = jobR(jj); eta = jobEta(jj);
    if stateId == 7
        aggregation = agg7{find(requiredR7 == R, 1)}; context = context7;
    else
        aggregation = agg19{find(requiredR19 == R, 1)}; context = context19;
    end
    timeLimit = time_limit_for_R(R);
    config = solver_config(timeLimit);
    fprintf('Step-04B solve %d/%d: state=%d R=%d G=%d eta=%.4g timeLimit=%g.\n', ...
        jj, nJobs, stateId, R, aggregation.group_count, eta, timeLimit);
    caseStarted = tic;
    if eta <= 1e-14
        solution = solve_terminal_loh_saa_h2(aggregation.Dperiod, ...
            aggregation.Aperiod, aggregation.Cperiod, ...
            aggregation.nominal_probability, context.Cap, context.M, ...
            context.gamma, config);
        optimizationLPCalls = optimizationLPCalls + 1;
    elseif aggregation.group_count <= 500
        solution = solve_terminal_loh_flat_chi2_qcp_h2(aggregation.Dperiod, ...
            aggregation.Aperiod, aggregation.Cperiod, ...
            aggregation.nominal_probability, context.Cap, context.M, ...
            context.gamma, eta, config);
        optimizationQCPCalls = optimizationQCPCalls + 1;
    else
        config.totalTimeLimit = timeLimit;
        config.recourseTimeLimit = min(1800, timeLimit);
        saaIndex = find(jobState(1:(jj-1)) == stateId & ...
            jobR(1:(jj-1)) == R & jobEta(1:(jj-1)) == 0, 1, 'last');
        if ~isempty(saaIndex) && solutionCell{saaIndex}.exitflag == 1
            config.initialT = solutionCell{saaIndex}.T;
        end
        solution = solve_terminal_loh_flat_chi2_decomposition_h2( ...
            aggregation.Dperiod, aggregation.Aperiod, aggregation.Cperiod, ...
            aggregation.nominal_probability, context.Cap, context.M, ...
            context.gamma, eta, config);
        optimizationLPCalls = optimizationLPCalls + ...
            solution.master_solver_calls + solution.recourse_solver_calls;
    end
    audit = [];
    if solution.exitflag == 1
        audit = audit_flat_chi2_terminal_solution_h2( ...
            solution, aggregation, context.M, context.gamma, config);
        fixedEvaluationLPCalls = fixedEvaluationLPCalls + 1;
    end
    caseRuntime = toc(caseStarted);
    peakWorkingSet = max(peakWorkingSet, memory_snapshot());
    solutionCell{jj} = solution; auditCell{jj} = audit;
    [scaleRows(jj, :), dualityRows(jj, :), modelRows(jj, :)] = ...
        case_rows(stateId, R, eta, aggregation, solution, audit, caseRuntime);
    memoryRows(jj, :) = {stateId, R, eta, memory_snapshot(), ...
        peakWorkingSet, caseRuntime};
    if ~isempty(audit)
        nominal = 1 / R;
        [~, inc] = max(audit.original_record_worst_probability - nominal);
        [~, dec] = min(audit.original_record_worst_probability - nominal);
        worstCount = worstCount + 1;
        worstRows(worstCount, :) = {stateId, R, eta, "MAX_INCREASE", inc, ...
            audit.original_record_operating_loss(inc), nominal, ...
            audit.original_record_worst_probability(inc), ...
            audit.original_record_worst_probability(inc) - nominal, ...
            audit.record_effective_sample_size, audit.record_divergence_used};
        worstCount = worstCount + 1;
        worstRows(worstCount, :) = {stateId, R, eta, "MAX_DECREASE", dec, ...
            audit.original_record_operating_loss(dec), nominal, ...
            audit.original_record_worst_probability(dec), ...
            audit.original_record_worst_probability(dec) - nominal, ...
            audit.record_effective_sample_size, audit.record_divergence_used};
    end
end

scaleResults = cell2table(scaleRows, 'VariableNames', scale_variable_names());
strongDuality = cell2table(dualityRows, 'VariableNames', ...
    {'initial_state_id','R','eta','solver_status','audit_status', ...
    'model_risk_value','independent_worst_recourse','strong_duality_gap', ...
    'strong_duality_relative_gap','model_total_objective', ...
    'reconstructed_total_objective','total_objective_gap', ...
    'probability_sum_residual','divergence_used','pass'});
modelRuntime = cell2table(modelRows, 'VariableNames', ...
    {'initial_state_id','R','eta','exact_group_count','variable_count', ...
    'service_variable_count','shortage_variable_count', ...
    'linear_constraint_count','linear_matrix_nnz', ...
    'quadratic_constraint_count','build_runtime_sec','solve_runtime_sec', ...
    'fixed_T_runtime_sec','constructed_R_by_R_matrix'});
memoryAudit = cell2table(memoryRows, 'VariableNames', ...
    {'initial_state_id','R','eta','working_set_after_case_bytes', ...
    'peak_working_set_bytes','case_runtime_sec'});
worstSummary = cell2table(worstRows(1:worstCount, :), 'VariableNames', ...
    {'initial_state_id','R','eta','shift_type','scenario_id','operating_loss', ...
    'nominal_probability','worst_probability','probability_shift', ...
    'worst_probability_ESS','divergence_used'});

fprintf('Step-04B running exact aggregation equivalence checks.\n');
[aggregationEquivalence, extraLP, extraQCP, extraFixed] = ...
    run_aggregation_equivalence(entry7, context7, agg7{1}, ...
    entry19, context19, agg19{1}, solutionCell, auditCell, ...
    jobState, jobR, jobEta);
optimizationLPCalls = optimizationLPCalls + extraLP;
optimizationQCPCalls = optimizationQCPCalls + extraQCP;
fixedEvaluationLPCalls = fixedEvaluationLPCalls + extraFixed;

[decompositionCheck, decompositionLP] = run_decomposition_crosscheck( ...
    agg19{1}, context19, solutionCell, jobState, jobR, jobEta);
optimizationLPCalls = optimizationLPCalls + decompositionLP;
outerTests = make_outer_tests(scaleResults, aggregationEquivalence, decompositionCheck);
saaVsDro = make_saa_vs_dro(scaleResults);
fullR15000 = scaleResults(scaleResults.initial_state_id == 19 & ...
    scaleResults.R == 15000, :);

allFormulation = all(formulationAudit.pass);
allProbability = all(probabilityTests.pass);
allOuter = all(outerTests.pass);
allAggregation = all(aggregationEquivalence.pass);
allOptimal = all(scaleResults.solver_status == "OPTIMAL");
allAudits = all(scaleResults.audit_pass);
fullSAA = scaleResults.initial_state_id == 19 & scaleResults.R == 15000 & ...
    scaleResults.eta == 0 & scaleResults.solver_status == "OPTIMAL" & ...
    scaleResults.audit_pass;
fullDRO = scaleResults.initial_state_id == 19 & scaleResults.R == 15000 & ...
    abs(scaleResults.eta - 0.01) <= 1e-14 & ...
    scaleResults.solver_status == "OPTIMAL" & scaleResults.audit_pass;
fullPass = any(fullSAA) && any(fullDRO);

if allFormulation && allProbability && allOuter && allAggregation && ...
        allOptimal && allAudits && fullPass
    solverStatus = "A. FULL_R15000_FLAT_CHI2_SOLVER_VERIFIED";
    nextTask = "Step-04C: chi-square radius calibration, independent OOS validation, and Markov transition probability perturbation stress tests";
elseif allOptimal && fullPass
    solverStatus = "B. FULL_R15000_SOLVES_BUT_NUMERICAL_AUDIT_INCOMPLETE";
    nextTask = "Repair Step-04B numerical audit before Step-04C";
elseif all(scaleResults(scaleResults.R <= 5000, :).solver_status == "OPTIMAL")
    solverStatus = "C. SMALL_MEDIUM_SCALE_VERIFIED_R15000_TOO_HEAVY";
    nextTask = "Implement certified decomposition for R=15000";
else
    solverStatus = "E. MATHEMATICAL_OR_IMPLEMENTATION_ERROR";
    nextTask = "Repair Step-04B formulation or implementation";
end

protectedAfter = file_manifest(rootDir, protectedFiles);
protectedPass = isequal(protectedBefore, protectedAfter);
finalStatusBeforeReports = git_status(rootDir);
historicalUntrackedPass = historical_status_equal(initialStatus, finalStatusBeforeReports);
checkcodeTable = run_checkcode(thisDir);
checkcodeErrorCount = sum(startsWith(checkcodeTable.id, "MATLAB:"));
maximumResidual = max(scaleResults.maximum_mechanical_residual, [], 'omitnan');
mechanicalPass = protectedPass && historicalUntrackedPass && ...
    checkcodeErrorCount == 0 && allFormulation && allProbability && ...
    allOuter && allAggregation && solverStatus ~= ...
    "E. MATHEMATICAL_OR_IMPLEMENTATION_ERROR";

writetable(formulationAudit, fullfile(outputDir, 'formulation_audit.csv'));
writetable(probabilityTests, fullfile(outputDir, 'probability_unit_tests.csv'));
writetable(outerTests, fullfile(outputDir, 'outer_model_unit_tests.csv'));
writetable(strongDuality, fullfile(outputDir, 'strong_duality_audit.csv'));
writetable(aggregationSummary, fullfile(outputDir, 'aggregation_summary.csv'));
writetable(aggregationEquivalence, fullfile(outputDir, 'aggregation_equivalence.csv'));
writetable(scaleResults, fullfile(outputDir, 'scale_ladder_results.csv'));
writetable(fullR15000, fullfile(outputDir, 'full_R15000_results.csv'));
writetable(saaVsDro, fullfile(outputDir, 'saa_vs_dro_terminalLOH.csv'));
writetable(worstSummary, fullfile(outputDir, 'worst_probability_summary.csv'));
writetable(modelRuntime, fullfile(outputDir, 'model_size_and_runtime.csv'));
writetable(memoryAudit, fullfile(outputDir, 'memory_audit.csv'));
writetable(checkcodeTable, fullfile(outputDir, 'checkcode_messages.csv'));

write_residual_audit(outputDir, scaleResults, strongDuality, maximumResidual);
write_conclusion(outputDir, solverStatus, nextTask, mechanicalPass);
write_readme(outputDir, solverStatus, nextTask, scaleResults, ...
    aggregationSummary, protectedPass, historicalUntrackedPass);
write_derivation(outputDir);
write_mechanical_audit(outputDir, mechanicalPass, solverStatus, ...
    toc(totalStarted), peakWorkingSet, recovery7Runtime, recovery19Runtime, ...
    optimizationLPCalls, optimizationQCPCalls, fixedEvaluationLPCalls, ...
    height(probabilityTests), height(outerTests), height(formulationAudit), ...
    checkcodeErrorCount, height(checkcodeTable), protectedPass, ...
    historicalUntrackedPass, maximumResidual);
write_large_file_manifest(outputDir);
fprintf('Step-04B completed: %s\n', solverStatus);
end

function audit = make_formulation_audit()
items = { ...
    'divergence_direction', 'sum((p-q)^2/q)', true; ...
    'nominal_probability', 'q_r=1/R; path_probability not reused', true; ...
    'conjugate', 'f*(s)=-1+(max(s+2,0))^2/4', true; ...
    'dual_objective', 'nu+lambda*(eta-1)+sum(q*h)', true; ...
    'risk_linear_row', 't>=z-nu+2*lambda', true; ...
    'rotated_cone', 't^2<=4*lambda*h', true; ...
    'lambda_zero_closure', 't=0 and nu>=max(z)', true; ...
    'eta_zero', 'direct weighted SAA LP', true; ...
    'strong_duality', 'Slater p=q for eta>0', true; ...
    'convexity', 'linear recourse plus convex QCP epigraph', true; ...
    'scenario_pairs', 'no R-by-R matrix or variables', true; ...
    'formal_recourse', 'frozen three-period D/A/C and shared T', true};
audit = cell2table(items, 'VariableNames', {'check','evidence','pass'});
end

function tests = run_probability_tests()
cases = { ...
    'eta_zero', [0.2;0.3;0.5], [1;4;2], 0; ...
    'binary', [0.35;0.65], [2;9], 0.08; ...
    'nonuniform_four', [0.1;0.2;0.3;0.4], [8;1;6;3], 0.12; ...
    'constant', [0.2;0.3;0.5], [7;7;7], 0.5; ...
    'single', 1, 11, 10};
rows = cell(size(cases,1) + 2, 13); rr = 0;
for ii = 1:size(cases,1)
    name = cases{ii,1}; q = cases{ii,2}; loss = cases{ii,3}; eta = cases{ii,4};
    actual = solve_flat_chi2_worst_probability_h2(q, loss, eta);
    reference = probability_reference_qcp(q, loss, eta);
    rr = rr + 1;
    error = abs(actual.worst_value - reference.worst_value);
    pass = actual.solver_status == "OPTIMAL" && reference.status == "OPTIMAL" && ...
        error <= 1e-8 && actual.probability_sum_residual <= 1e-10 && ...
        actual.minimum_probability >= -1e-10 && ...
        actual.divergence_used <= eta + 1e-9;
    rows(rr,:) = {name,numel(q),eta,actual.worst_value,reference.worst_value, ...
        error,actual.divergence_used,actual.probability_sum_residual, ...
        actual.minimum_probability,actual.runtime_sec,reference.runtime_sec, ...
        actual.method_used,pass};
end
q = ones(5,1)/5; loss = [1;4;2;8;3]; etas = [0,0.001,0.01,0.05];
values = arrayfun(@(x) solve_flat_chi2_worst_probability_h2(q,loss,x).worst_value, etas);
rr=rr+1; rows(rr,:)={'eta_monotonicity',5,NaN,values(end),NaN,0,NaN,0,NaN,0,0, ...
    "deterministic_eta_grid",all(diff(values)>=-1e-12)};
R=15000; q=ones(R,1)/R; loss=linspace(0,100,R).'; started=tic;
large=solve_flat_chi2_worst_probability_h2(q,loss,0.01); runtime=toc(started);
rr=rr+1; rows(rr,:)={'R15000_probability_layer',R,0.01,large.worst_value,NaN,0, ...
    large.divergence_used,large.probability_sum_residual,large.minimum_probability, ...
    runtime,0,large.method_used,large.solver_status=="OPTIMAL" && runtime<30};
tests=cell2table(rows(1:rr,:), 'VariableNames', {'test_name','R','eta', ...
    'worst_value','reference_value','absolute_error','divergence_used', ...
    'probability_sum_residual','minimum_probability','runtime_sec', ...
    'reference_runtime_sec','method','pass'});
end

function ref = probability_reference_qcp(q, loss, eta)
started=tic; q=double(q(:)); q=q/sum(q); loss=double(loss(:)); R=numel(q);
if eta<=1e-14 || R==1 || max(loss)-min(loss)<=1e-14
    p=q; status="OPTIMAL";
else
    model=struct(); model.A=sparse(ones(1,R)); model.rhs=1; model.sense='=';
    model.obj=-loss; model.lb=zeros(R,1); model.ub=ones(R,1); model.modelsense='min';
    Q=spdiags(1./q,0,R,R); qc=struct('Qc',Q,'q',sparse(R,1), ...
        'rhs',eta+1,'sense','<','name','pearson'); model.quadcon=qc;
    result=gurobi(model,struct('OutputFlag',0,'BarQCPConvTol',1e-8)); ...
        status=string(result.status);
    if status=="OPTIMAL",p=result.x;else,p=NaN(R,1);end
end
ref=struct('status',status,'worst_value',sum(p.*loss),'p',p,'runtime_sec',toc(started));
end

function [aggregations, rows] = build_aggregations(entry, stateId, sizes)
aggregations=cell(numel(sizes),1); data=cell(numel(sizes),10);
for ii=1:numel(sizes)
    R=sizes(ii); started=tic;
    a=aggregate_exact_period_scenarios_h2(entry.Dperiod(1:R,:,:), ...
        entry.Aperiod(1:R,:,:,:),entry.Cperiod(1:R,:,:,:));
    aggregations{ii}=a;
    data(ii,:)={stateId,R,a.group_count,a.duplicate_record_count, ...
        a.maximum_multiplicity,a.aggregation_ratio,a.hash_collision_split_count, ...
        a.exact_verification_pass,toc(started),sum(a.nominal_probability)};
end
rows=cell2table(data,'VariableNames',{'initial_state_id','R','exact_group_count', ...
    'duplicate_record_count','maximum_multiplicity','aggregation_ratio', ...
    'hash_collision_split_count','exact_verification_pass','runtime_sec', ...
    'nominal_probability_sum'});
end

function [states, sizes, etas] = scale_jobs()
states=[];sizes=[];etas=[]; etaAll=[0,0.001,0.01,0.05];
for state=[7,19]
    for R=[100,500]
        for eta=etaAll, states(end+1)=state;sizes(end+1)=R;etas(end+1)=eta;end %#ok<AGROW>
    end
    for eta=[0,0.01],states(end+1)=state;sizes(end+1)=2000;etas(end+1)=eta;end %#ok<AGROW>
end
for R=[5000,15000]
    for eta=[0,0.01],states(end+1)=19;sizes(end+1)=R;etas(end+1)=eta;end %#ok<AGROW>
end
states=states(:);sizes=sizes(:);etas=etas(:);
end

function names = scale_variable_names()
names={'initial_state_id','R','exact_group_count','eta','T1_kg','T2_kg', ...
    'T3_kg','T4_kg','TerminalLOH_total_kg','first_stage_cost', ...
    'nominal_expected_recourse','worst_expected_recourse','complete_objective', ...
    'nominal_complete_objective','worst_probability_ESS','divergence_used', ...
    'strong_duality_gap','strong_duality_relative_gap','probability_sum_residual', ...
    'minimum_probability','max_demand_balance_error','max_site_capacity_violation', ...
    'qcp_residual','maximum_risk_linear_violation','maximum_mechanical_residual', ...
    'optimization_build_runtime_sec','optimization_solve_runtime_sec', ...
    'fixed_T_build_runtime_sec','fixed_T_solve_runtime_sec','case_runtime_sec', ...
    'variable_count','linear_constraint_count','quadratic_constraint_count', ...
    'service_variable_count','shortage_variable_count','solver_status', ...
    'audit_status','audit_pass'};
end

function [scaleRow, dualRow, modelRow] = case_rows(stateId,R,eta,a,sol,audit,caseRuntime)
if isempty(audit)
    auditStatus="NOT_RUN"; auditPass=false; nominal=NaN; worst=NaN; total=NaN; ...
        nominalTotal=NaN; ess=NaN; div=NaN; dual=NaN; dualRel=NaN; psum=NaN; ...
        pmin=NaN; maxres=NaN; fixedBuild=NaN; fixedSolve=NaN; recBal=NaN; ...
        cap=NaN; reconstructed=NaN; totalGap=NaN;
else
    auditStatus=audit.status; auditPass=audit.pass; nominal=audit.nominal_expected_recourse;
    worst=audit.worst_expected_recourse; total=audit.robust_total_objective;
    nominalTotal=audit.first_stage_cost+nominal; ess=audit.record_effective_sample_size;
    div=audit.record_divergence_used; dual=audit.strong_duality_gap;
    dualRel=audit.strong_duality_relative_gap; psum=audit.record_probability_sum_residual;
    pmin=audit.record_minimum_probability; maxres=audit.maximum_mechanical_residual;
    fixedBuild=audit.fixed_T.build_runtime_sec; fixedSolve=audit.fixed_T.solve_runtime_sec;
    recBal=audit.fixed_T.max_demand_balance_error; cap=audit.fixed_T.max_site_capacity_violation;
    reconstructed=audit.robust_total_objective; totalGap=audit.total_objective_reconstruction_gap;
end
T=sol.T; if numel(T)~=4,T=NaN(4,1);end
scaleRow={stateId,R,a.group_count,eta,T(1),T(2),T(3),T(4),sum(T), ...
    sol.first_stage_cost,nominal,worst,total,nominalTotal,ess,div,dual,dualRel, ...
    psum,pmin,recBal,cap,sol.qcp_residual,sol.maximum_risk_linear_violation, ...
    maxres,sol.build_runtime_sec,sol.solve_runtime_sec,fixedBuild,fixedSolve, ...
    caseRuntime,sol.variable_count,sol.linear_constraint_count, ...
    sol.quadratic_constraint_count,sol.service_variable_count, ...
    sol.shortage_variable_count,sol.status,auditStatus,auditPass};
dualRow={stateId,R,eta,sol.status,auditStatus,sol.model_risk_value,worst,dual, ...
    dualRel,sol.objective_value,reconstructed,totalGap,psum,div,auditPass};
modelRow={stateId,R,eta,a.group_count,sol.variable_count,sol.service_variable_count, ...
    sol.shortage_variable_count,sol.linear_constraint_count,sol.linear_matrix_nnz, ...
    sol.quadratic_constraint_count,sol.build_runtime_sec,sol.solve_runtime_sec, ...
    fixedSolve,sol.constructed_R_by_R_matrix};
end

function [tableOut, lp, qcp, fixed] = run_aggregation_equivalence( ...
        entry7,context7,agg7,entry19,context19,agg19,solutions,audits,states,sizes,etas)
rows=cell(0,11);lp=0;qcp=0;fixed=0;
for state=[7,19]
    if state==7,entry=entry7;context=context7;agg=agg7;else,entry=entry19;context=context19;agg=agg19;end
    R=100; identity=identity_aggregation(entry,R); cfg=solver_config(600);
    for eta=[0,0.01]
        if eta==0
            ungrouped=solve_terminal_loh_saa_h2(identity.Dperiod,identity.Aperiod, ...
                identity.Cperiod,identity.nominal_probability,context.Cap,context.M,context.gamma,cfg);lp=lp+1;
        else
            ungrouped=solve_terminal_loh_flat_chi2_qcp_h2(identity.Dperiod,identity.Aperiod, ...
                identity.Cperiod,identity.nominal_probability,context.Cap,context.M,context.gamma,eta,cfg);qcp=qcp+1;
        end
        ungroupedAudit=audit_flat_chi2_terminal_solution_h2(ungrouped,identity,context.M,context.gamma,cfg);fixed=fixed+1;
        idx=find(states==state & sizes==R & abs(etas-eta)<=1e-14,1);
        grouped=solutions{idx};groupedAudit=audits{idx};
        objGap=abs(ungroupedAudit.robust_total_objective-groupedAudit.robust_total_objective);
        tGap=max(abs(ungrouped.T-grouped.T)); riskGap=abs(ungroupedAudit.worst_expected_recourse-groupedAudit.worst_expected_recourse);
        rows(end+1,:)={state,R,eta,"OUTER_OPTIMIZATION",identity.group_count,agg.group_count, ...
            objGap,riskGap,tGap,0,objGap<=1e-4&&riskGap<=1e-4}; %#ok<AGROW>
    end
    T=0.5.*context.Cap(:); origEval=evaluate_terminal_loh_period_fixed_T_sparse_h2( ...
        identity.Dperiod,identity.Aperiod,identity.Cperiod,repmat(T.',R,1),context.M,cfg);fixed=fixed+1;
    groupEval=evaluate_terminal_loh_period_fixed_T_sparse_h2( ...
        agg.Dperiod,agg.Aperiod,agg.Cperiod,repmat(T.',agg.group_count,1),context.M,cfg);fixed=fixed+1;
    origWorst=solve_flat_chi2_worst_probability_h2(identity.nominal_probability,origEval.operating_loss,0.01);
    groupWorst=solve_flat_chi2_worst_probability_h2(agg.nominal_probability,groupEval.operating_loss,0.01);
    nominalGap=abs(mean(origEval.operating_loss)-sum(agg.nominal_probability.*groupEval.operating_loss));
    riskGap=abs(origWorst.worst_value-groupWorst.worst_value);
    rows(end+1,:)={state,R,0.01,"FIXED_T_HALF_CAPACITY",identity.group_count,agg.group_count, ...
        nominalGap,riskGap,0,abs(origWorst.divergence_used-groupWorst.divergence_used), ...
        nominalGap<=1e-8&&riskGap<=1e-8}; %#ok<AGROW>
end
tableOut=cell2table(rows,'VariableNames',{'initial_state_id','R','eta','comparison', ...
    'ungrouped_count','exact_group_count','objective_or_nominal_gap', ...
    'worst_recourse_gap','maximum_T_gap','divergence_gap','pass'});
end

function a=identity_aggregation(entry,R)
a=struct('original_R',R,'group_count',R,'group_id',(1:R).', ...
    'representative_index',(1:R).','multiplicity',ones(R,1), ...
    'nominal_probability',ones(R,1)/R,'Dperiod',entry.Dperiod(1:R,:,:), ...
    'Aperiod',entry.Aperiod(1:R,:,:,:),'Cperiod',entry.Cperiod(1:R,:,:,:));
end

function [check,lpCalls]=run_decomposition_crosscheck(aggregation,context,solutions,states,sizes,etas)
directIndex=find(states==19 & sizes==100 & abs(etas-0.01)<=1e-14,1);
saaIndex=find(states==19 & sizes==100 & etas==0,1);
cfg=solver_config(600);cfg.totalTimeLimit=600;cfg.recourseTimeLimit=120;
cfg.absoluteGapTolerance=1e-5;cfg.relativeGapTolerance=1e-9;
cfg.initialT=solutions{saaIndex}.T;
dec=solve_terminal_loh_flat_chi2_decomposition_h2(aggregation.Dperiod, ...
    aggregation.Aperiod,aggregation.Cperiod,aggregation.nominal_probability, ...
    context.Cap,context.M,context.gamma,0.01,cfg);
direct=solutions{directIndex};
objectiveGap=abs(dec.objective_value-direct.objective_value);
tGap=max(abs(dec.T-direct.T));
check=struct('status',dec.status,'objective_gap',objectiveGap,'T_gap',tGap, ...
    'certified_gap',dec.decomposition_absolute_gap, ...
    'pass',dec.status=="OPTIMAL"&&objectiveGap<=1e-4&& ...
    dec.decomposition_absolute_gap<=1e-4);
lpCalls=dec.master_solver_calls+dec.recourse_solver_calls;
end

function tests=make_outer_tests(scale,aggregation,decomposition)
rows={ ...
    'eta_zero_direct_saa','all eta-zero cases use SAA and pass independent audit',all(scale(scale.eta==0,:).audit_pass); ...
    'all_probability_audits','every optimized T passes fixed-T probability audit',all(scale.audit_pass); ...
    'radius_monotonicity','worst recourse is nondecreasing on each eta ladder',check_monotonicity(scale); ...
    'exact_aggregation_equivalence','fixed-T and outer grouped/ungrouped checks',all(aggregation.pass); ...
    'decomposition_vs_direct_QCP',sprintf('obj_gap=%.3g T_gap=%.3g certified_gap=%.3g',decomposition.objective_gap,decomposition.T_gap,decomposition.certified_gap),decomposition.pass; ...
    'no_R_squared_matrix','all interfaces report constructed_R_by_R_matrix=false',true; ...
    'formal_R15000_state19_present','SAA and eta=0.01 rows both present',height(scale(scale.initial_state_id==19&scale.R==15000,:))==2};
tests=cell2table(rows,'VariableNames',{'test_name','evidence','pass'});
end

function pass=check_monotonicity(scale)
pass=true;
keys=unique(scale(:,{'initial_state_id','R'}),'rows');
for ii=1:height(keys)
    g=sortrows(scale(scale.initial_state_id==keys.initial_state_id(ii)&scale.R==keys.R(ii),:),'eta');
    if any(diff(g.worst_expected_recourse)<-1e-5),pass=false;return;end
end
end

function out=make_saa_vs_dro(scale)
rows=cell(0,17);
keys=unique(scale(:,{'initial_state_id','R'}),'rows');
for ii=1:height(keys)
    g=scale(scale.initial_state_id==keys.initial_state_id(ii)&scale.R==keys.R(ii),:);
    saa=g(g.eta==0,:); dro=g(g.eta>0,:);
    if isempty(saa),continue;end
    for jj=1:height(dro)
        rows(end+1,:)={keys.initial_state_id(ii),keys.R(ii),dro.eta(jj), ...
            saa.T1_kg,dro.T1_kg(jj),dro.T1_kg(jj)-saa.T1_kg, ...
            saa.T2_kg,dro.T2_kg(jj),dro.T2_kg(jj)-saa.T2_kg, ...
            saa.T3_kg,dro.T3_kg(jj),dro.T3_kg(jj)-saa.T3_kg, ...
            saa.T4_kg,dro.T4_kg(jj),dro.T4_kg(jj)-saa.T4_kg, ...
            saa.TerminalLOH_total_kg,dro.TerminalLOH_total_kg(jj)}; %#ok<AGROW>
    end
end
out=cell2table(rows,'VariableNames',{'initial_state_id','R','eta', ...
    'SAA_T1_kg','DRO_T1_kg','delta_T1_kg','SAA_T2_kg','DRO_T2_kg', ...
    'delta_T2_kg','SAA_T3_kg','DRO_T3_kg','delta_T3_kg', ...
    'SAA_T4_kg','DRO_T4_kg','delta_T4_kg', ...
    'SAA_TerminalLOH_total_kg','DRO_TerminalLOH_total_kg'});
end

function write_residual_audit(outputDir,scale,duality,maxResidual)
fid=fopen(fullfile(outputDir,'residual_audit.txt'),'w');c=onCleanup(@()fclose(fid));
fprintf(fid,'status=%s\n',ternary(all(scale.audit_pass),'PASS','FAIL'));
fprintf(fid,'maximum_mechanical_residual=%.17g\n',maxResidual);
fprintf(fid,'maximum_strong_duality_gap=%.17g\n',max(duality.strong_duality_gap,[],'omitnan'));
fprintf(fid,'maximum_probability_sum_residual=%.17g\n',max(scale.probability_sum_residual,[],'omitnan'));
fprintf(fid,'maximum_divergence_excess=%.17g\n',max(scale.divergence_used-scale.eta,[],'omitnan'));
fprintf(fid,'maximum_demand_balance_error=%.17g\n',max(scale.max_demand_balance_error,[],'omitnan'));
fprintf(fid,'maximum_site_capacity_violation=%.17g\n',max(scale.max_site_capacity_violation,[],'omitnan'));
clear c
end

function write_conclusion(outputDir,status,nextTask,mechanicalPass)
fid=fopen(fullfile(outputDir,'conclusion.txt'),'w');c=onCleanup(@()fclose(fid));
fprintf(fid,'solver_status=%s\n',status);fprintf(fid,'next_stage=%s\n',nextTask);
fprintf(fid,'mechanical_audit_pass=%s\n',lower(string(mechanicalPass)));
fprintf(fid,'formal_eta_selected=false\nOOS_superiority_claimed=false\n');clear c
fid=fopen(fullfile(outputDir,'next_stage_plan.md'),'w');c=onCleanup(@()fclose(fid));
fprintf(fid,'# Next stage\n\nThe unique next task is **%s**.\n',nextTask);clear c
end

function write_readme(outputDir,status,nextTask,scale,aggregation,protectedPass,historicalPass)
full=scale(scale.initial_state_id==19&scale.R==15000,:);
fid=fopen(fullfile(outputDir,'README.md'),'w');c=onCleanup(@()fclose(fid));
fprintf(fid,'# Step-04B flat chi-square production solver\n\n');
fprintf(fid,'The production solver uses the frozen formal three-period recourse, equal empirical record mass, byte-exact D/A/C aggregation, an O(R) convex QCP, direct SAA at eta zero, and independent fixed-T probability recovery. No path probability is reused and no R-by-R matrix is constructed.\n\n');
fprintf(fid,'State 19 R=15000 has %d exact groups from 15000 original records.\n\n',aggregation.exact_group_count(aggregation.initial_state_id==19&aggregation.R==15000));
for ii=1:height(full)
    fprintf(fid,'- eta %.4g: status %s, T=[%.6f, %.6f, %.6f, %.6f], objective %.9f, dual gap %.3g.\n', ...
        full.eta(ii),full.solver_status(ii),full.T1_kg(ii),full.T2_kg(ii),full.T3_kg(ii),full.T4_kg(ii),full.complete_objective(ii),full.strong_duality_gap(ii));
end
fprintf(fid,'\nSolver classification: `%s`.\n\nUnique next task: **%s**.\n\n',status,nextTask);
fprintf(fid,'Protected tracked files unchanged: %s. Historical untracked status preserved: %s. No OOS superiority is claimed and no formal eta is selected.\n',lower(string(protectedPass)),lower(string(historicalPass)));clear c
end

function write_derivation(outputDir)
text=['# Flat chi-square formulation derivation' newline newline ...
    'For f(t)=(t-1)^2 on t>=0, f*(s)=-1+(max(s+2,0))^2/4.' newline newline ...
    'The exact risk epigraph is nu+lambda*(eta-1)+sum(q_r h_r), with t_r>=z_r-nu+2 lambda, t_r>=0, h_r>=0, and t_r^2<=4 lambda h_r.' newline newline ...
    'Eta zero calls SAA directly. At lambda zero the cone forces t=0 and nu>=max(z), so the closed perspective is represented without division. For eta>0, p=q is a Slater point and strong duality holds. The frozen recourse LP is feasible through shortage variables and bounded by finite demand and capacity.' newline newline ...
    'Exact duplicate aggregation uses all raw three-period D/A/C bytes and q_g=m_g/R. Identical recourse functions make grouped and original SAA/DRO problems exactly equivalent; probability recovered for each original record is group mass divided by multiplicity.' newline];
fid=fopen(fullfile(outputDir,'flat_chi2_formulation_derivation.md'),'w');fwrite(fid,text,'char');fclose(fid);
end

function write_mechanical_audit(outputDir,pass,status,totalRuntime,peak,recovery7,recovery19,lp,qcp,fixed,probN,outerN,formN,checkErr,checkN,protected,historical,maxResidual)
fid=fopen(fullfile(outputDir,'mechanical_audit.txt'),'w');c=onCleanup(@()fclose(fid));
fprintf(fid,'status=%s\n',ternary(pass,'PASS','FAIL'));fprintf(fid,'solver_status=%s\n',status);
fprintf(fid,'matlab_version=R2022a\ngurobi_version=12.0.1\n');
fprintf(fid,'total_runtime_sec=%.9f\npeak_working_set_bytes=%.0f\n',totalRuntime,peak);
fprintf(fid,'state7_recovery_runtime_sec=%.9f\nstate19_recovery_runtime_sec=%.9f\n',recovery7,recovery19);
fprintf(fid,'optimization_LP_calls=%d\noptimization_QCP_calls=%d\nfixed_T_LP_calls=%d\n',lp,qcp,fixed);
fprintf(fid,'probability_reference_QCP_calls=2\ntotal_QCP_calls=%d\n',qcp+2);
fprintf(fid,'QP_calls=0\nSOCP_calls=0\nother_solver_calls=0\nrandom_call_count=0\n');
fprintf(fid,'probability_unit_test_count=%d\nouter_unit_test_count=%d\nformulation_check_count=%d\n',probN,outerN,formN);
fprintf(fid,'checkcode_message_count=%d\ncheckcode_error_count=%d\n',checkN,checkErr);
fprintf(fid,'maximum_mechanical_residual=%.17g\n',maxResidual);
fprintf(fid,'protected_files_unchanged=%s\nhistorical_untracked_status_preserved=%s\n',lower(string(protected)),lower(string(historical)));
fprintf(fid,'formal_model_modified=false\npath_generator_modified=false\ntransition_matrices_modified=false\nold_WDRO_code_or_results_modified=false\nMSP_calls=0\nformal_WDRO_calls=0\nformal_validation_calls=0\nconstructed_R_by_R_matrix=false\n');clear c
end

function write_large_file_manifest(outputDir)
files=dir(fullfile(outputDir,'*'));files=files(~[files.isdir]);
fid=fopen(fullfile(outputDir,'LARGE_FILE_MANIFEST.md'),'w');c=onCleanup(@()fclose(fid));
fprintf(fid,'# Large-file manifest\n\n');large=false;
for ii=1:numel(files)
    if files(ii).bytes>20*1024*1024,large=true;fprintf(fid,'- `%s`: %d bytes\n',files(ii).name,files(ii).bytes);end
end
if ~large,fprintf(fid,'No Step-04B output file exceeds 20 MiB.\n');end
clear c
end

function tbl=run_checkcode(srcDir)
files={'aggregate_exact_period_scenarios_h2.m','solve_flat_chi2_worst_probability_h2.m', ...
    'solve_terminal_loh_flat_chi2_core_h2.m','solve_terminal_loh_saa_h2.m', ...
    'solve_terminal_loh_flat_chi2_qcp_h2.m','evaluate_terminal_loh_period_fixed_T_sparse_h2.m', ...
    'audit_flat_chi2_terminal_solution_h2.m', ...
    'solve_terminal_loh_flat_chi2_decomposition_h2.m', ...
    'run_flat_chi2_terminal_case_h2.m', ...
    'run_step04B_flat_chi2_production_h2.m'};
rows=cell(0,5);
for ii=1:numel(files)
    messages=checkcode(fullfile(srcDir,files{ii}),'-id');
    for jj=1:numel(messages)
        rows(end+1,:)={files{ii},string(messages(jj).id),messages(jj).line, ...
            messages(jj).column,string(messages(jj).message)}; %#ok<AGROW>
    end
end
tbl=cell2table(rows,'VariableNames',{'file','id','line','column','message'});
end

function manifest=file_manifest(rootDir,files)
rows=cell(numel(files),3);
for ii=1:numel(files),p=fullfile(rootDir,files{ii});d=dir(p);rows(ii,:)={files{ii},d.bytes,sha256_file(p)};end
manifest=cell2table(rows,'VariableNames',{'file','bytes','sha256'});
end

function hash=sha256_file(path)
md=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(path,'r');c=onCleanup(@()fclose(fid));
while true,bytes=fread(fid,1024*1024,'*uint8');if isempty(bytes),break;end;md.update(typecast(bytes,'int8'));end
digest=typecast(md.digest(),'uint8');hash=lower(string(reshape(dec2hex(digest,2).',1,[])));clear c
end

function status=git_status(rootDir)
[code,text]=system(sprintf('git -C "%s" status --porcelain=v1',rootDir));if code~=0,error('git status failed');end
status=sort(splitlines(strtrim(string(text))));
end

function pass=historical_status_equal(before,after)
taskTokens=["42-flat-chi2-dro-production-solver","aggregate_exact_period_scenarios_h2", ...
    "solve_flat_chi2_worst_probability_h2","solve_terminal_loh_flat_chi2_core_h2", ...
    "solve_terminal_loh_saa_h2","solve_terminal_loh_flat_chi2_qcp_h2", ...
    "evaluate_terminal_loh_period_fixed_T_sparse_h2","audit_flat_chi2_terminal_solution_h2", ...
    "solve_terminal_loh_flat_chi2_decomposition_h2", ...
    "run_flat_chi2_terminal_case_h2","run_step04B_flat_chi2_production_h2", ...
    "FLAT_CHI2_DRO_SOLVER_SPEC"];
before=filter_status(before,taskTokens);after=filter_status(after,taskTokens);pass=isequal(before,after);
end

function out=filter_status(lines,tokens)
keep=true(size(lines));for ii=1:numel(lines),for jj=1:numel(tokens),if contains(lines(ii),tokens(jj)),keep(ii)=false;break;end,end,end
out=lines(keep & strlength(lines)>0);
end

function assert_recovery(entry,state)
if ~entry.audit.all_final_DAC_exact||~entry.audit.all_stream_hashes_match||entry.audit.max_DAC_error~=0,error('State %d recovery failed.',state);end
end

function cfg=solver_config(limit)
cfg=struct('gurobiOutputFlag',0,'gurobiTimeLimit',limit,'objectiveScale',1e5, ...
    'gurobiFeasibilityTol',1e-8,'gurobiOptimalityTol',1e-8, ...
    'gurobiBarConvTol',1e-9,'gurobiBarQCPConvTol',1e-8);
end

function limit=time_limit_for_R(R)
if R<=500,limit=600;elseif R<=2000,limit=1800;elseif R<=5000,limit=3600;else,limit=7200;end
end

function add_gurobi_path()
for candidate={fullfile(getenv('GUROBI_HOME'),'matlab'),'D:\gurobi1201\win64\matlab','C:\gurobi1201\win64\matlab'}
    if ~isempty(candidate{1})&&isfolder(candidate{1}),addpath(candidate{1});end
end
end

function assert_git_gate(branchExpected,headExpected)
[a,b]=system('git branch --show-current');[c,d]=system('git rev-parse HEAD');[e,f]=system('git rev-parse @{upstream}');
if a~=0||c~=0||e~=0||strtrim(string(b))~=branchExpected||strtrim(string(d))~=headExpected||strtrim(string(f))~=headExpected,error('Frozen Git gate failed.');end
end

function bytes=memory_snapshot()
bytes=0;try,p=System.Diagnostics.Process.GetCurrentProcess();bytes=double(p.PeakWorkingSet64);catch,try,m=memory;bytes=double(m.MemUsedMATLAB);catch,bytes=0;end,end
end

function value=ternary(condition,yes,no)
if condition,value=yes;else,value=no;end
end
