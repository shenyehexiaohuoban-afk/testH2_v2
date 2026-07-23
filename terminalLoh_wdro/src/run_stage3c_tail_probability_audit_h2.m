%% Step-03C run-001: candidate probability mass and path-level B3 audit.
clear;clc;

thisFile=mfilename('fullpath');thisDir=fileparts(thisFile);
moduleDir=fileparts(thisDir);rootDir=fileparts(moduleDir);

config=struct();
config.outputDir=fullfile(moduleDir,'output','stage3c_tail_probability_audit','run-001');
config.candidatePoolFile=fullfile(moduleDir,'output', ...
    'stage2b_tail_candidate_design','run-005','unique_tail_paths.csv');
config.b3Dir=fullfile(moduleDir,'output','stage3b_b3_candidate_validation','run-001');
config.b3CandidateFile=fullfile(config.b3Dir,'b3_candidate_paths.csv');
config.b3ReferenceFile=fullfile(config.b3Dir,'b3_reference_paths.csv');
config.b3ScenarioFile=fullfile(config.b3Dir,'b3_scenario_results.csv');
config.b3DACFile=fullfile(config.b3Dir,'b3_DAC_results.csv');
config.b3AutomaticAuditFile=fullfile(config.b3Dir,'automatic_audit.csv');
config.b3UpperBoundFile=fullfile(config.b3Dir,'D_upper_bound_audit.csv');
config.b3ProbabilityAuditFile=fullfile(config.b3Dir,'probability_identity_audit.csv');
config.mainSampleFile=fullfile(moduleDir,'output','stage2a2_W3_path_sampling', ...
    'run-002','main_path_samples.csv');
config.intensityMatrixFile=fullfile(moduleDir,'config', ...
    'lookahead_intensity_postlandfall_W3.csv');
config.locationMatrixFile=fullfile(moduleDir,'config', ...
    'lookahead_location_postlandfall_W3.csv');
config.lfwMatrixFile=fullfile(moduleDir,'config', ...
    'lookahead_lfw_postlandfall_W3.csv');
config.expectedCandidateHash="53738926dcffa76b16e1294ddba0dbe78e17f950a654bb4b6ad872f199b6c2ce";
config.expectedB3CandidateHash="41b90acbdb19eec839f099b092b5cd619e4bad14255df5ed6a9b36d31b192426";
config.expectedB3ReferenceHash="0b3f5592fcd176e0cf6501f329b78e3b060d353a2979add64275879bdca6e3e6";
config.expectedB3ScenarioHash="d5c983474c006678580c1334d9bf9febe3ccc37bec06b8cfa6809e52fa7e35b4";
config.expectedB3DACHash="85dedb10a8f393d0eb955c7b068bb4151b2d5243bf391d4d229c0612dde037af";
config.expectedMainHash="972a8c58620c09ac19cfcfb29e8d6a3ed2819ef1a22dbd522043436418eb805d";
config.expectedCandidateRows=1126;config.expectedObserved=268;
config.expectedUnobserved=858;config.expectedScenarios=45040;
config.expectedStageRows=135120;config.repeatsPerPath=20;
config.DUpperKg=607.969887897881;config.probabilityTolerance=1e-12;
config.DBinKg=1;config.CBinKm=1;

requiredFiles={config.candidatePoolFile,config.b3CandidateFile, ...
    config.b3ReferenceFile,config.b3ScenarioFile,config.b3DACFile, ...
    config.b3AutomaticAuditFile,config.b3UpperBoundFile, ...
    config.b3ProbabilityAuditFile,config.mainSampleFile, ...
    config.intensityMatrixFile,config.locationMatrixFile,config.lfwMatrixFile};
for ii=1:numel(requiredFiles)
    if ~isfile(requiredFiles{ii})
        error('run_stage3c_tail_probability_audit_h2:MissingInput', ...
            'Required input is missing: %s',requiredFiles{ii});
    end
end
if isfolder(config.outputDir)
    existing=dir(config.outputDir);existing=existing(~ismember({existing.name},{'.','..'}));
    if ~isempty(existing)
        error('run_stage3c_tail_probability_audit_h2:OutputExists', ...
            'Refusing to overwrite nonempty output directory: %s',config.outputDir);
    end
end

inputHashesBefore=strings(numel(requiredFiles),1);inputBytesBefore=zeros(numel(requiredFiles),1);
for ii=1:numel(requiredFiles)
    inputHashesBefore(ii)=sha256_file(requiredFiles{ii});
    info=dir(requiredFiles{ii});inputBytesBefore(ii)=info.bytes;
end

[mainRows,mainFields]=count_csv_rows_and_fields(config.mainSampleFile);
candidatePool=readtable(config.candidatePoolFile,'TextType','string');
b3Candidates=readtable(config.b3CandidateFile,'TextType','string');
b3References=readtable(config.b3ReferenceFile,'TextType','string');
b3Scenarios=readtable(config.b3ScenarioFile,'TextType','string');
b3DAC=readtable(config.b3DACFile,'TextType','string');
b3Automatic=readtable(config.b3AutomaticAuditFile,'TextType','string');
b3Upper=readtable(config.b3UpperBoundFile,'TextType','string');
b3Probability=readtable(config.b3ProbabilityAuditFile,'TextType','string');
intensityMatrix=readtable(config.intensityMatrixFile);
locationMatrix=readtable(config.locationMatrixFile);
lfwMatrix=readtable(config.lfwMatrixFile);

print_input(config.candidatePoolFile,candidatePool,inputHashesBefore(1));
print_input(config.b3CandidateFile,b3Candidates,inputHashesBefore(2));
print_input(config.b3ReferenceFile,b3References,inputHashesBefore(3));
print_input(config.b3ScenarioFile,b3Scenarios,inputHashesBefore(4));
print_input(config.b3DACFile,b3DAC,inputHashesBefore(5));
fprintf('INPUT|path=%s|rows=%d|fields=%s|sha256=%s\n',config.mainSampleFile, ...
    mainRows,strjoin(mainFields,','),inputHashesBefore(9));

acceptedVersionPass=inputHashesBefore(1)==config.expectedCandidateHash && ...
    inputHashesBefore(2)==config.expectedB3CandidateHash && ...
    inputHashesBefore(3)==config.expectedB3ReferenceHash && ...
    inputHashesBefore(4)==config.expectedB3ScenarioHash && ...
    inputHashesBefore(5)==config.expectedB3DACHash && ...
    inputHashesBefore(9)==config.expectedMainHash;
if ~acceptedVersionPass
    error('Accepted run-005, Step-03B, or main-sample SHA-256 mismatch.');
end
if mainRows~=525000 || height(candidatePool)~=1126 || ...
        height(b3Candidates)~=1126 || height(b3References)~=1126 || ...
        height(b3Scenarios)~=config.expectedScenarios || ...
        height(b3DAC)~=config.expectedStageRows
    error('Accepted input row counts do not match Step-03B.');
end
if any(~as_logical(b3Automatic.passed)) || ...
        abs(double(b3Upper.derived_D_upper_bound_kg(1))-config.DUpperKg)>1e-9
    error('Step-03B audit or D upper-bound identity is not accepted.');
end

require_vars(candidatePool,{'unique_path_id','a0','loc0','lfw0','a1','loc1', ...
    'lfw1','a2','loc2','lfw2','a3','loc3','lfw3','path_probability', ...
    'is_observed_candidate','is_unobserved_candidate'},'unique_tail_paths.csv');
require_vars(b3Candidates,{'selection_path_id','candidate_pool_unique_path_id', ...
    'source_category','path_probability','empirical_weight', ...
    'nominal_inclusion_status'},'b3_candidate_paths.csv');
require_vars(b3Scenarios,{'scenario_id','selection_path_id','resistance_repeat', ...
    'source_category','D_Hres3h_total_kg','failed_lines_W3','closed_roads_W3', ...
    'reachable_pair_share_stage_mean','C_reachable_sum_all_stages_km', ...
    'C_reachable_count_all_stages','joint_line_road_damage_any', ...
    'line_failure_signature','road_closure_signature','accessibility_signature', ...
    'structural_pattern_signature','full_consequence_signature'}, ...
    'b3_scenario_results.csv');
require_vars(b3DAC,{'scenario_id','selection_path_id','stage_index', ...
    'unreachable_pair_count','site_node_pair_count','reachable_pair_count', ...
    'C_reachable_count','C_reachable_sum_km','C_reachable_max_km'}, ...
    'b3_DAC_results.csv');

candidateIds=double(b3Candidates.candidate_pool_unique_path_id);
[poolMatch,poolIndex]=ismember(candidateIds,double(candidatePool.unique_path_id));
if ~all(poolMatch)||numel(unique(poolIndex))~=height(candidatePool)
    error('Step-03B candidate IDs do not map one-to-one to run-005.');
end
poolAligned=candidatePool(poolIndex,:);
physicalKeyPool=physical_keys(poolAligned);physicalKeyB3=physical_keys(b3Candidates);

recomputedProbability=zeros(height(b3Candidates),1);
for ii=1:height(b3Candidates)
    recomputedProbability(ii)=path_probability_from_matrices( ...
        poolAligned(ii,:),intensityMatrix,locationMatrix,lfwMatrix);
end

scenarioCMean=double(b3Scenarios.C_reachable_sum_all_stages_km)./ ...
    double(b3Scenarios.C_reachable_count_all_stages);
[Gdac,dacScenarioIds]=findgroups(double(b3DAC.scenario_id));
dacCMax=splitapply(@max,double(b3DAC.C_reachable_max_km),Gdac);
[scenarioMatch,scenarioIndex]=ismember(double(b3Scenarios.scenario_id),dacScenarioIds);
if ~all(scenarioMatch),error('Scenario rows do not map to DAC stage rows.');end
scenarioCMax=dacCMax(scenarioIndex);

binnedKey=compose('D%.0f|Dmin%.0f|Dmax%.0f|Dnmax%.0f|Dnp95%.0f|Dn%d|Cmean%.0f|Cmax%.0f|Cn%d|A%s', ...
    round(double(b3Scenarios.D_Hres3h_total_kg)/config.DBinKg)*config.DBinKg, ...
    round(double(b3Scenarios.D_stage_min_kg)/config.DBinKg)*config.DBinKg, ...
    round(double(b3Scenarios.D_stage_max_kg)/config.DBinKg)*config.DBinKg, ...
    round(double(b3Scenarios.D_node_Hres3h_max_kg)/config.DBinKg)*config.DBinKg, ...
    round(double(b3Scenarios.D_node_Hres3h_p95_kg)/config.DBinKg)*config.DBinKg, ...
    double(b3Scenarios.D_node_Hres3h_nonzero_count), ...
    round(scenarioCMean/config.CBinKm)*config.CBinKm, ...
    round(scenarioCMax/config.CBinKm)*config.CBinKm, ...
    double(b3Scenarios.C_reachable_count_all_stages), ...
    b3Scenarios.accessibility_signature);
roadDisconnectKey=b3Scenarios.road_closure_signature+"|"+ ...
    b3Scenarios.accessibility_signature+"|"+string(b3Scenarios.road_disconnection_any);
lineRoadKey=b3Scenarios.line_failure_signature+"|"+b3Scenarios.road_closure_signature;

signatureDefinitions=["exact_full_DAC";"binned_DAC_1kg_1km";"A_pattern"; ...
    "line_failure_combination";"road_disconnect_combination"; ...
    "line_road_joint_structure";"full_structural_pattern"];
signatureKeys={b3Scenarios.full_consequence_signature;binnedKey; ...
    b3Scenarios.accessibility_signature;b3Scenarios.line_failure_signature; ...
    roadDisconnectKey;lineRoadKey;b3Scenarios.structural_pattern_signature};
signatureDescriptions=[ ...
    "Step-03B exact full D/A/C signature with deterministic 1e-6 serialization"; ...
    "D rounded to 1 kg and reachable C rounded to 1 km, retaining A pattern"; ...
    "binary site-node accessibility pattern across W1-W3"; ...
    "failed-line combination across W1-W3"; ...
    "closed-road plus accessibility/disconnection pattern across W1-W3"; ...
    "joint failed-line and closed-road structure across W1-W3"; ...
    "line road outage-node and A structure from Step-03B"];

referenceMask=b3Scenarios.source_category=="main_reference";
observedScenarioMask=b3Scenarios.source_category=="observed_candidate";
unobservedScenarioMask=b3Scenarios.source_category=="unobserved_candidate";
candidateScenarioMask=observedScenarioMask|unobservedScenarioMask;

signatureRows=cell(numel(signatureDefinitions)*3,13);sigCursor=0;
scenarioNovelFlags=false(height(b3Scenarios),numel(signatureDefinitions));
for dd=1:numel(signatureDefinitions)
    keys=string(signatureKeys{dd});refUnique=unique(keys(referenceMask));
    scenarioNovelFlags(:,dd)=candidateScenarioMask&~ismember(keys,refUnique);
    sourceNames=["observed_candidate";"unobserved_candidate";"all_candidates"];
    sourceMasks={observedScenarioMask,unobservedScenarioMask,candidateScenarioMask};
    for gg=1:3
        mask=sourceMasks{gg};novelMask=mask&~ismember(keys,refUnique);
        sigCursor=sigCursor+1;
        signatureRows(sigCursor,:)={signatureDefinitions(dd),sourceNames(gg), ...
            signatureDescriptions(dd),config.DBinKg,config.CBinKm, ...
            numel(refUnique),sum(mask),numel(unique(keys(mask))),sum(novelMask), ...
            numel(unique(keys(novelMask))),sum(novelMask)/sum(mask), ...
            numel(unique(double(b3Scenarios.selection_path_id(novelMask)))), ...
            "comparison is against all 22520 matched-reference scenarios"};
    end
end
consequenceSignatureAudit=cell2table(signatureRows,'VariableNames', ...
    {'signature_definition','candidate_source','definition','D_bin_kg', ...
    'C_bin_km','reference_unique_signature_count','candidate_scenario_count', ...
    'candidate_unique_signature_count','novel_candidate_scenario_count', ...
    'novel_candidate_unique_signature_count','novel_candidate_scenario_share', ...
    'candidate_path_with_novel_signature_count','comparison_scope'});

pathLevel=b3Candidates;
nPaths=height(pathLevel);
Dmean=zeros(nPaths,1);Dmax=zeros(nPaths,1);Dq95=zeros(nPaths,1);
upperShare=zeros(nPaths,1);A0Share=zeros(nPaths,1);reachableMean=zeros(nPaths,1);
Cmean=zeros(nPaths,1);Cmax=zeros(nPaths,1);W3LineMean=zeros(nPaths,1);
W3LineMax=zeros(nPaths,1);W3RoadMean=zeros(nPaths,1);W3RoadMax=zeros(nPaths,1);
jointShare=zeros(nPaths,1);roadDisconnectShare=zeros(nPaths,1);
scenarioCount=zeros(nPaths,1);stageCount=zeros(nPaths,1);
novelShares=zeros(nPaths,numel(signatureDefinitions));
for ii=1:nPaths
    sid=double(pathLevel.selection_path_id(ii));
    q=b3Scenarios(double(b3Scenarios.selection_path_id)==sid,:);
    z=b3DAC(double(b3DAC.selection_path_id)==sid,:);
    scenarioCount(ii)=height(q);stageCount(ii)=height(z);
    D=double(q.D_Hres3h_total_kg);
    Dmean(ii)=mean(D);Dmax(ii)=max(D);Dq95(ii)=pct(D,95);
    upperShare(ii)=mean(abs(D-config.DUpperKg)<=1e-9);
    A0Share(ii)=sum(double(z.unreachable_pair_count))/sum(double(z.site_node_pair_count));
    reachableMean(ii)=sum(double(z.reachable_pair_count))/sum(double(z.site_node_pair_count));
    Cmean(ii)=sum(double(z.C_reachable_sum_km))/sum(double(z.C_reachable_count));
    Cmax(ii)=max(double(z.C_reachable_max_km));
    W3LineMean(ii)=mean(double(q.failed_lines_W3));W3LineMax(ii)=max(double(q.failed_lines_W3));
    W3RoadMean(ii)=mean(double(q.closed_roads_W3));W3RoadMax(ii)=max(double(q.closed_roads_W3));
    jointShare(ii)=mean(double(q.joint_line_road_damage_any));
    roadDisconnectShare(ii)=mean(double(q.road_disconnection_any));
    qIndex=find(double(b3Scenarios.selection_path_id)==sid);
    novelShares(ii,:)=mean(scenarioNovelFlags(qIndex,:),1);
end

pathLevel.theoretical_path_probability=double(poolAligned.path_probability);
pathLevel.run005_unique_path_id=double(poolAligned.unique_path_id);
pathLevel.B3_scenario_count=scenarioCount;pathLevel.B3_stage_row_count=stageCount;
pathLevel.D_Hres3h_mean_kg=Dmean;pathLevel.D_Hres3h_max_kg=Dmax;
pathLevel.D_Hres3h_q95_kg=Dq95;pathLevel.full_loss_upper_hit_share=upperShare;
pathLevel.A0_pair_share=A0Share;pathLevel.reachable_pair_share=reachableMean;
pathLevel.C_reachable_mean_km=Cmean;pathLevel.C_reachable_max_km=Cmax;
pathLevel.failed_lines_W3_mean=W3LineMean;pathLevel.failed_lines_W3_max=W3LineMax;
pathLevel.closed_roads_W3_mean=W3RoadMean;pathLevel.closed_roads_W3_max=W3RoadMax;
pathLevel.joint_line_road_damage_share=jointShare;
pathLevel.road_disconnection_share=roadDisconnectShare;
pathLevel.exact_full_DAC_novel_share=novelShares(:,1);
pathLevel.binned_DAC_novel_share=novelShares(:,2);
pathLevel.A_pattern_novel_share=novelShares(:,3);
pathLevel.line_failure_novel_share=novelShares(:,4);
pathLevel.road_disconnect_novel_share=novelShares(:,5);
pathLevel.line_road_joint_novel_share=novelShares(:,6);
pathLevel.structural_novel_share=novelShares(:,7);
pathLevel.raw_probability_weighted_D_contribution= ...
    pathLevel.theoretical_path_probability.*pathLevel.D_Hres3h_mean_kg;
pathLevel.raw_probability_weighted_full_loss_contribution= ...
    pathLevel.theoretical_path_probability.*pathLevel.full_loss_upper_hit_share;
pathLevel.raw_probability_weighted_A0_contribution= ...
    pathLevel.theoretical_path_probability.*pathLevel.A0_pair_share;
pathLevel.probability_renormalized=false(nPaths,1);

states=unique(pathLevel(:,{'a0','loc0','lfw0'}),'rows');
states=sortrows(states,{'a0','loc0','lfw0'});
massRows=cell(height(states),20);
contributionRows=cell(height(states)*3+3,15);contributionCursor=0;
for ss=1:height(states)
    stateMask=pathLevel.a0==states.a0(ss)&pathLevel.loc0==states.loc0(ss)& ...
        pathLevel.lfw0==states.lfw0(ss);
    obs=stateMask&pathLevel.source_category=="observed_candidate";
    unobs=stateMask&pathLevel.source_category=="unobserved_candidate";
    allMask=obs|unobs;
    p=pathLevel.theoretical_path_probability;
    massRows(ss,:)={states.a0(ss),states.loc0(ss),states.lfw0(ss), ...
        sum(obs),sum(unobs),sum(allMask),sum(p(obs)),sum(p(unobs)),sum(p(allMask)), ...
        min_or_nan(p(obs)),median_or_nan(p(obs)),max_or_nan(p(obs)), ...
        min_or_nan(p(unobs)),median_or_nan(p(unobs)),max_or_nan(p(unobs)), ...
        min(p(allMask)),median(p(allMask)),max(p(allMask)),sum(p(allMask))<=1+1e-12, ...
        "conditional on this initial state; no renormalization"};
    groups=["observed_candidate";"unobserved_candidate";"all_candidates"];
    masks={obs,unobs,allMask};
    for gg=1:3
        contributionCursor=contributionCursor+1;
        contributionRows(contributionCursor,:)=contribution_row( ...
            "initial_state",states.a0(ss),states.loc0(ss),states.lfw0(ss), ...
            groups(gg),masks{gg},pathLevel);
    end
end
probabilityMassByState=cell2table(massRows,'VariableNames', ...
    {'a0','loc0','lfw0','observed_candidate_count','unobserved_candidate_count', ...
    'all_candidate_count','observed_theoretical_probability_mass', ...
    'unobserved_theoretical_probability_mass','all_candidate_theoretical_probability_mass', ...
    'observed_probability_min','observed_probability_median','observed_probability_max', ...
    'unobserved_probability_min','unobserved_probability_median','unobserved_probability_max', ...
    'all_candidate_probability_min','all_candidate_probability_median', ...
    'all_candidate_probability_max','mass_not_above_one','probability_scope'});

groups=["observed_candidate";"unobserved_candidate";"all_candidates"];
for gg=1:3
    stateRows=cell2table(contributionRows(gg:3:height(states)*3,:), ...
        'VariableNames',contribution_names());
    contributionCursor=contributionCursor+1;
    contributionRows(contributionCursor,:)= {"35_state_equal_weight_diagnostic", ...
        NaN,NaN,NaN,groups(gg),sum(stateRows.path_count), ...
        mean(stateRows.theoretical_probability_mass), ...
        mean(stateRows.raw_D_mean_contribution_kg), ...
        mean(stateRows.raw_full_loss_probability_contribution), ...
        mean(stateRows.raw_A0_probability_contribution), ...
        mean(stateRows.raw_road_disconnection_probability_contribution), ...
        mean(stateRows.raw_joint_damage_probability_contribution),false, ...
        "equal-weight mean of 35 conditional-state contributions", ...
        "not a formal nominal expectation"};
end
probabilityWeightedContribution=cell2table( ...
    contributionRows(1:contributionCursor,:),'VariableNames',contribution_names());

probabilityConsistency=table();
probabilityConsistency.selection_path_id=double(b3Candidates.selection_path_id);
probabilityConsistency.run005_unique_path_id=double(poolAligned.unique_path_id);
probabilityConsistency.source_category=b3Candidates.source_category;
probabilityConsistency.run005_theoretical_path_probability=double(poolAligned.path_probability);
probabilityConsistency.step3b_path_probability=double(b3Candidates.path_probability);
probabilityConsistency.matrix_recomputed_path_probability=recomputedProbability;
probabilityConsistency.step3b_minus_run005= ...
    probabilityConsistency.step3b_path_probability- ...
    probabilityConsistency.run005_theoretical_path_probability;
probabilityConsistency.recomputed_minus_run005= ...
    probabilityConsistency.matrix_recomputed_path_probability- ...
    probabilityConsistency.run005_theoretical_path_probability;
probabilityConsistency.physical_key_match=physicalKeyPool==physicalKeyB3;
probabilityConsistency.scenario_count=scenarioCount;
probabilityConsistency.stage_row_count=stageCount;
probabilityConsistency.is_finite_nonnegative=isfinite(recomputedProbability)& ...
    recomputedProbability>=0;
probabilityConsistency.run005_step3b_pass= ...
    abs(probabilityConsistency.step3b_minus_run005)<=config.probabilityTolerance;
probabilityConsistency.matrix_recompute_pass= ...
    abs(probabilityConsistency.recomputed_minus_run005)<=config.probabilityTolerance;
probabilityConsistency.twenty_repeats_pass=scenarioCount==20&stageCount==60;
probabilityConsistency.pending_identity_pass= ...
    b3Candidates.source_category~="unobserved_candidate" | ...
    (double(b3Candidates.empirical_weight)==0 & ...
    b3Candidates.nominal_inclusion_status=="pending_after_B3");

inputHashesAfter=strings(numel(requiredFiles),1);inputBytesAfter=zeros(numel(requiredFiles),1);
for ii=1:numel(requiredFiles)
    inputHashesAfter(ii)=sha256_file(requiredFiles{ii});
    info=dir(requiredFiles{ii});inputBytesAfter(ii)=info.bytes;
end
inputsUnchanged=isequal(inputHashesBefore,inputHashesAfter)&& ...
    isequal(inputBytesBefore,inputBytesAfter);

observedCount=sum(pathLevel.source_category=="observed_candidate");
unobservedCount=sum(pathLevel.source_category=="unobserved_candidate");
pathUniquePass=numel(unique(physicalKeyB3))==1126 && ...
    numel(unique(double(pathLevel.selection_path_id)))==1126;
classificationPass=observedCount==268&&unobservedCount==858;
repeatPass=all(scenarioCount==20)&all(stageCount==60);
probabilityPass=all(probabilityConsistency.run005_step3b_pass)& ...
    all(probabilityConsistency.matrix_recompute_pass)& ...
    all(probabilityConsistency.is_finite_nonnegative);
massPass=all(probabilityMassByState.mass_not_above_one) && ...
    all(probabilityMassByState.all_candidate_theoretical_probability_mass>=0);
finiteConsequencePass=all(isfinite([Dmean;Dmax;Dq95;upperShare;A0Share; ...
    reachableMean;Cmean;Cmax;W3LineMean;W3RoadMean;jointShare])) && ...
    all([Dmean;Dmax;Dq95;upperShare;A0Share;reachableMean;Cmean;Cmax; ...
    W3LineMean;W3RoadMean;jointShare]>=0);
pendingPass=all(probabilityConsistency.pending_identity_pass);
step3BAuditPass=all(as_logical(b3Automatic.passed))&& ...
    all(as_logical(b3Probability.probability_identity_pass));
signaturePass=height(consequenceSignatureAudit)==21 && ...
    all(consequenceSignatureAudit.candidate_scenario_count>0);
forbiddenHits=scan_forbidden_calls(thisFile+".m");
noForbiddenCalls=height(forbiddenHits)==0;

checks={};
checks=add_check(checks,"AUDIT-01","accepted input hashes and row counts",acceptedVersionPass,acceptedVersionPass,true);
checks=add_check(checks,"AUDIT-02","1126 candidate paths aggregate to 1126 rows",height(pathLevel)==1126,height(pathLevel),1126);
checks=add_check(checks,"AUDIT-03","268 observed and 858 unobserved classifications",classificationPass,[observedCount,unobservedCount],[268,858]);
checks=add_check(checks,"AUDIT-04","every candidate has 20 scenarios and 60 stage rows",repeatPass,max(abs(scenarioCount-20))+max(abs(stageCount-60)),0);
checks=add_check(checks,"AUDIT-05","physical path and selection IDs are unique",pathUniquePass,pathUniquePass,true);
checks=add_check(checks,"AUDIT-06","Step-03B probability matches run-005",all(probabilityConsistency.run005_step3b_pass),max(abs(probabilityConsistency.step3b_minus_run005)),0);
checks=add_check(checks,"AUDIT-07","matrix recomputation matches run-005",all(probabilityConsistency.matrix_recompute_pass),max(abs(probabilityConsistency.recomputed_minus_run005)),0);
checks=add_check(checks,"AUDIT-08","probabilities finite nonnegative and not row-count weights",probabilityPass,min(recomputedProbability),0);
checks=add_check(checks,"AUDIT-09","each initial-state candidate mass is at most one",massPass,max(probabilityMassByState.all_candidate_theoretical_probability_mass),1);
checks=add_check(checks,"AUDIT-10","path-level consequences finite and nonnegative",finiteConsequencePass,finiteConsequencePass,true);
checks=add_check(checks,"AUDIT-11","858 unobserved paths remain empirical zero and pending",pendingPass,pendingPass,true);
checks=add_check(checks,"AUDIT-12","all source inputs unchanged",inputsUnchanged,inputsUnchanged,true);
checks=add_check(checks,"AUDIT-13","Step-03B automatic and probability audits remain PASS",step3BAuditPass,step3BAuditPass,true);
checks=add_check(checks,"AUDIT-14","seven signature definitions and three source scopes produced",signaturePass,height(consequenceSignatureAudit),21);
checks=add_check(checks,"AUDIT-15","candidate contribution is raw and never renormalized",all(~pathLevel.probability_renormalized),sum(pathLevel.probability_renormalized),0);
checks=add_check(checks,"AUDIT-16","no wind B3 random WDRO Gurobi or MSP calls",noForbiddenCalls,height(forbiddenHits),0);
automaticAudit=cell2table(checks,'VariableNames', ...
    {'check_id','description','passed','observed','expected'});
passCount=sum(automaticAudit.passed);failCount=sum(~automaticAudit.passed);
status="PASS";if failCount>0,status="FAIL";end

if failCount>0
    error('run_stage3c_tail_probability_audit_h2:AuditFailed', ...
        'Step-03C audit failed before output creation: %s', ...
        strjoin(automaticAudit.check_id(~automaticAudit.passed),', '));
end

mkdir(config.outputDir);
writetable(pathLevel,fullfile(config.outputDir,'candidate_path_level_consequences.csv'));
writetable(probabilityMassByState,fullfile(config.outputDir,'probability_mass_by_initial_state.csv'));
writetable(probabilityWeightedContribution,fullfile(config.outputDir,'probability_weighted_contribution.csv'));
writetable(consequenceSignatureAudit,fullfile(config.outputDir,'consequence_signature_audit.csv'));
writetable(probabilityConsistency,fullfile(config.outputDir,'probability_consistency_audit.csv'));
writetable(automaticAudit,fullfile(config.outputDir,'automatic_audit.csv'));
write_manifest(fullfile(config.outputDir,'run_manifest.txt'),config,status, ...
    passCount,failCount,probabilityMassByState,pathLevel,consequenceSignatureAudit);
write_readme(fullfile(config.outputDir,'README.txt'),config,status,passCount, ...
    failCount,probabilityMassByState,pathLevel,probabilityWeightedContribution, ...
    consequenceSignatureAudit);

fprintf('\nStage3C tail probability audit finished.\n');
fprintf('Status: %s; PASS=%d; FAIL=%d\n',status,passCount,failCount);
fprintf('Path-level candidates: %d; observed=%d; unobserved=%d\n', ...
    height(pathLevel),observedCount,unobservedCount);
fprintf('State candidate mass range: [%.12g, %.12g]\n', ...
    min(probabilityMassByState.all_candidate_theoretical_probability_mass), ...
    max(probabilityMassByState.all_candidate_theoretical_probability_mass));
fprintf('Output directory: %s\n',config.outputDir);

function row=contribution_row(scope,a0,loc0,lfw0,group,mask,T)
p=T.theoretical_path_probability(mask);
row={scope,double(a0),double(loc0),double(lfw0),group,sum(mask),sum(p), ...
    sum(p.*T.D_Hres3h_mean_kg(mask)), ...
    sum(p.*T.full_loss_upper_hit_share(mask)), ...
    sum(p.*T.A0_pair_share(mask)), ...
    sum(p.*T.road_disconnection_share(mask)), ...
    sum(p.*T.joint_line_road_damage_share(mask)),false, ...
    "raw contribution within conditional initial state", ...
    "candidate subset only; not renormalized and not a formal expectation"};
end
function names=contribution_names()
names={'scope','a0','loc0','lfw0','candidate_source','path_count', ...
    'theoretical_probability_mass','raw_D_mean_contribution_kg', ...
    'raw_full_loss_probability_contribution','raw_A0_probability_contribution', ...
    'raw_road_disconnection_probability_contribution', ...
    'raw_joint_damage_probability_contribution','probability_renormalized', ...
    'aggregation_definition','interpretation'};
end
function p=path_probability_from_matrices(path,intensity,location,lfw)
p=1;
for ss=1:3
    fromA=double(path.("a"+string(ss-1)));toA=double(path.("a"+string(ss)));
    fromLoc=double(path.("loc"+string(ss-1)));toLoc=double(path.("loc"+string(ss)));
    fromLfw=double(path.("lfw"+string(ss-1)));toLfw=double(path.("lfw"+string(ss)));
    p=p*lookup_probability(intensity,'from_a','to_a',fromA,toA)* ...
        lookup_probability(location,'from_loc_id','to_loc_id',fromLoc,toLoc)* ...
        lookup_probability(lfw,'from_lfw','to_lfw',fromLfw,toLfw);
end
end
function p=lookup_probability(T,fromName,toName,fromValue,toValue)
mask=double(T.(fromName))==fromValue&double(T.(toName))==toValue;
if sum(mask)~=1
    error('Transition (%g -> %g) is not uniquely configured in %s/%s.', ...
        fromValue,toValue,fromName,toName);
end
p=double(T.prob(mask));
end
function T=scan_forbidden_calls(fileName)
patterns=["compute_wind_speed_"+"radial_h2\\s*\\(", ...
    "compute_line_failure_"+"prob_h2\\s*\\(", ...
    "evaluate_b3_"+"candidate_validation_h2\\s*\\(", ...
    "rng\\s*\\(","solve_wdro_"+"terminal_loh_lp_h2\\s*\\(", ...
    "gurobi\\s*\\(","main_msp_"+"h2_near\\s*\\(", ...
    "run_h2_"+"with_options\\s*\\("];
text=fileread(fileName);rows={};
for ii=1:numel(patterns)
    if ~isempty(regexp(text,patterns(ii),'once'))
        rows(end+1,:)={string(fileName),patterns(ii)}; %#ok<AGROW>
    end
end
if isempty(rows),T=cell2table(cell(0,2),'VariableNames',{'file','pattern'});
else,T=cell2table(rows,'VariableNames',{'file','pattern'});end
end
function keys=physical_keys(T)
keys=string(compose('%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d', ...
    T.a0,T.loc0,T.lfw0,T.a1,T.loc1,T.lfw1,T.a2,T.loc2,T.lfw2, ...
    T.a3,T.loc3,T.lfw3));
end
function values=as_logical(values)
if islogical(values),return;end
if isnumeric(values),values=values~=0;else
    text=lower(strtrim(string(values)));values=text=="true"|text=="1";
end
end
function value=pct(x,p)
x=sort(double(x(:)));x=x(isfinite(x));
if isempty(x),value=NaN;else,value=x(max(1,min(numel(x),ceil(p/100*numel(x)))));end
end
function value=min_or_nan(x),if isempty(x),value=NaN;else,value=min(x);end,end
function value=max_or_nan(x),if isempty(x),value=NaN;else,value=max(x);end,end
function value=median_or_nan(x),if isempty(x),value=NaN;else,value=median(x);end,end
function require_vars(T,names,fileName)
for ii=1:numel(names)
    if ~ismember(names{ii},T.Properties.VariableNames)
        error('%s missing required field %s.',fileName,names{ii});
    end
end
end
function print_input(fileName,T,hash)
fprintf('INPUT|path=%s|rows=%d|fields=%s|sha256=%s\n',fileName,height(T), ...
    strjoin(string(T.Properties.VariableNames),','),hash);
end
function [rows,fields]=count_csv_rows_and_fields(fileName)
fid=fopen(fileName,'rb');if fid<0,error('Could not open %s.',fileName);end
cleanup=onCleanup(@()fclose(fid));header=fgetl(fid);fields=string(strsplit(header,','));
newlineCount=1;lastByte=uint8(10);
while true
    bytes=fread(fid,1024*1024,'*uint8');if isempty(bytes),break;end
    newlineCount=newlineCount+sum(bytes==10);lastByte=bytes(end);
end
totalLines=newlineCount+double(lastByte~=10);rows=totalLines-1;
end
function hash=sha256_file(fileName)
fid=fopen(fileName,'rb');if fid<0,error('Could not open %s.',fileName);end
cleanup=onCleanup(@()fclose(fid));md=java.security.MessageDigest.getInstance('SHA-256');
while true
    bytes=fread(fid,1024*1024,'*uint8');if isempty(bytes),break;end
    md.update(typecast(bytes,'int8'));
end
digest=typecast(md.digest(),'uint8');hash=lower(string(reshape(dec2hex(digest,2).',1,[])));
end
function rows=add_check(rows,id,description,passed,observed,expected)
rows(end+1,:)={string(id),string(description),logical(passed), ...
    scalar_text(observed),scalar_text(expected)};
end
function text=scalar_text(value)
if isstring(value),text=strjoin(value(:).',' | ');
elseif ischar(value),text=string(value);
elseif islogical(value)&&isscalar(value),text=string(double(value));
elseif isnumeric(value)&&isscalar(value),text=string(sprintf('%.15g',value));
elseif isnumeric(value),text=strjoin(compose('%.15g',value(:).'),' | ');
else,text=string(value);end
end
function write_manifest(fileName,config,status,passCount,failCount,mass,pathLevel,signature)
fid=fopen(fileName,'w');if fid<0,error('Could not write %s.',fileName);end
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'task_id=task-002\nstep_id=03-tail-probability-audit\nrun_id=run-001\n');
fprintf(fid,'run_time=%s\nstatus=%s\npass_count=%d\nfail_count=%d\n', ...
    char(datetime('now','Format','yyyy-MM-dd HH:mm:ss Z')),status,passCount,failCount);
fprintf(fid,'candidate_paths=%d\nobserved_candidates=%d\nunobserved_candidates=%d\n', ...
    height(pathLevel),sum(pathLevel.source_category=="observed_candidate"), ...
    sum(pathLevel.source_category=="unobserved_candidate"));
fprintf(fid,'observed_state_mass_range=%.15g,%.15g\n', ...
    min(mass.observed_theoretical_probability_mass),max(mass.observed_theoretical_probability_mass));
fprintf(fid,'unobserved_state_mass_range=%.15g,%.15g\n', ...
    min(mass.unobserved_theoretical_probability_mass),max(mass.unobserved_theoretical_probability_mass));
fprintf(fid,'all_candidate_state_mass_range=%.15g,%.15g\n', ...
    min(mass.all_candidate_theoretical_probability_mass),max(mass.all_candidate_theoretical_probability_mass));
row=signature(signature.signature_definition=="binned_DAC_1kg_1km"& ...
    signature.candidate_source=="all_candidates",:);
fprintf(fid,'binned_DAC_novel_scenarios=%d\n',row.novel_candidate_scenario_count);
fprintf(fid,'probability_renormalized=false\nformal_nominal_distribution_changed=false\n');
fprintf(fid,'unobserved_nominal_inclusion_status=pending_after_B3\n');
fprintf(fid,'B3_rerun=false\nwind_rerun=false\nWDRO_run=false\nGurobi_run=false\nMSP_run=false\n');
end
function write_readme(fileName,config,status,passCount,failCount,mass,pathLevel,contribution,signature)
fid=fopen(fileName,'w');if fid<0,error('Could not write %s.',fileName);end
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'Step-03C run-001: candidate probability mass and path-level B3 consequence audit\n\n');
fprintf(fid,'status=%s; PASS=%d; FAIL=%d\n',status,passCount,failCount);
fprintf(fid,'This run only reads accepted run-005 and Step-03B outputs. It does not rerun wind or B3.\n');
fprintf(fid,'Observed/unobserved/all candidate state-mass ranges: %.12g-%.12g / %.12g-%.12g / %.12g-%.12g.\n', ...
    min(mass.observed_theoretical_probability_mass),max(mass.observed_theoretical_probability_mass), ...
    min(mass.unobserved_theoretical_probability_mass),max(mass.unobserved_theoretical_probability_mass), ...
    min(mass.all_candidate_theoretical_probability_mass),max(mass.all_candidate_theoretical_probability_mass));
for source=["observed_candidate","unobserved_candidate"]
    q=pathLevel(pathLevel.source_category==source,:);
    fprintf(fid,'- %s paths: D mean range %.12g-%.12g kg; A0 range %.12g-%.12g; reachable C mean range %.12g-%.12g km.\n', ...
        source,min(q.D_Hres3h_mean_kg),max(q.D_Hres3h_mean_kg), ...
        min(q.A0_pair_share),max(q.A0_pair_share), ...
        min(q.C_reachable_mean_km),max(q.C_reachable_mean_km));
end
eq=contribution(contribution.scope=="35_state_equal_weight_diagnostic",:);
for ii=1:height(eq)
    fprintf(fid,'- %s equal-state raw contribution: mass %.12g; D %.12g kg; full-loss %.12g; A0 %.12g.\n', ...
        eq.candidate_source(ii),eq.theoretical_probability_mass(ii), ...
        eq.raw_D_mean_contribution_kg(ii), ...
        eq.raw_full_loss_probability_contribution(ii), ...
        eq.raw_A0_probability_contribution(ii));
end
exact=signature(signature.signature_definition=="exact_full_DAC"& ...
    signature.candidate_source=="all_candidates",:);
binned=signature(signature.signature_definition=="binned_DAC_1kg_1km"& ...
    signature.candidate_source=="all_candidates",:);
structural=signature(signature.signature_definition=="full_structural_pattern"& ...
    signature.candidate_source=="all_candidates",:);
fprintf(fid,'Exact/binned/structural novel candidate scenarios: %d/%d/%d.\n', ...
    exact.novel_candidate_scenario_count,binned.novel_candidate_scenario_count, ...
    structural.novel_candidate_scenario_count);
fprintf(fid,'Binned D/C uses %.0f kg and %.0f km bins while retaining A. Exact and structural signatures are distinct diagnostics.\n', ...
    config.DBinKg,config.CBinKm);
fprintf(fid,'Theoretical probabilities are raw transition-matrix probabilities and are not renormalized.\n');
fprintf(fid,'All 858 unobserved candidates remain empirical_weight=0 and pending_after_B3.\n');
fprintf(fid,'No formal nominal expectation, WDRO, Gurobi, optimization, or MSP is executed.\n');
end
