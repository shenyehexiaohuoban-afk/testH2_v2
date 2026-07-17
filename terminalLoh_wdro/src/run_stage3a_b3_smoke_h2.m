clear; clc;

thisDir=fileparts(mfilename('fullpath'));
moduleDir=fileparts(thisDir);
rootDir=fileparts(moduleDir);
addpath(rootDir);addpath(thisDir);
addpath(fullfile(rootDir,'fa_h2','fuzhu','terminalLoh_windmc'));

config=struct();
config.rootDir=rootDir;config.moduleDir=moduleDir;
config.outputDir=fullfile(moduleDir,'output','stage3a_b3_smoke','run-001');
config.mainSampleFile=fullfile(moduleDir,'output','stage2a2_W3_path_sampling', ...
    'run-002','main_path_samples.csv');
config.candidatePoolFile=fullfile(moduleDir,'output', ...
    'stage2b_tail_candidate_design','run-005','unique_tail_paths.csv');
config.candidatePoolArchiveFile=fullfile(rootDir,'results', ...
    'task-001-stage2a2-path-prob','03-stage2b-tail-candidate-design', ...
    'run-005','unique_tail_paths.csv');
config.warningSweepDir=fullfile(moduleDir,'output', ...
    'stage2_foundation_warning100_Rmax30_40_50_Wstep_sweep');
config.warningSolutionFile=fullfile(config.warningSweepDir,'warning_y_base_solution.csv');
config.warningGeometryFile=fullfile(config.warningSweepDir,'warning_geometry_by_loc.csv');
config.warningRankingFile=fullfile(config.warningSweepDir,'Wstep_candidate_ranking.csv');
config.warningStageSummaryFile=fullfile(config.warningSweepDir,'Rmax_Wstep_stage_summary.csv');
config.warningDiagnosticsFile=fullfile(config.warningSweepDir,'diagnostics_summary.txt');
config.warningRankingSourceFile=fullfile(thisDir,'rank_Wstep_candidates_h2.m');
config.locCoordinateFile=fullfile(moduleDir,'output','stage2_foundation_audit', ...
    'loc_lf_coordinate_table.csv');
config.nearInputFile=fullfile(rootDir,'data','yuanqi','near_stage_msp_input.mat');
config.roadEdgeFile=fullfile(rootDir,'data','yuanqi','stage1_road_edges.csv');
config.siteNodeFile=fullfile(rootDir,'data','yuanqi','stage1_site_nodes.csv');

config.expectedMainRows=525000;
config.expectedMainHash= ...
    "972a8c58620c09ac19cfcfb29e8d6a3ed2819ef1a22dbd522043436418eb805d";
config.expectedCandidateRows=1126;
config.representativeStateCount=5;config.pathsPerSource=2;
config.mainPathsPerInitialState=15000;config.resistanceRepeats=20;
config.rngSeed=20260717;config.Rmax=40;config.Wstep=40;
config.WstepValues=40;config.recommendedWstep=40;config.comparisonWstep=45;
config.stageNames=["lf7","W1","W2","W3"];config.stageOffsets=[0,1,2,3];
config.sliceDurationH=1;config.HresTotalH=3;
config.warningDistanceKmEq=100;config.windDecayB=0.6;
config.designWindSpeedVN=25;config.roadDesignWindVN=30;
config.roadSlowdownLambda=1.0;config.slowRoadThreshold=1e-6;
config.sourceNode=1;config.distanceMethod="point_to_segment";
config.CDefinition="masked_dist(n)_if_A1_else_0";
config.probabilityTolerance=1e-12;

requiredFiles={config.mainSampleFile,config.candidatePoolFile, ...
    config.candidatePoolArchiveFile,config.warningSolutionFile, ...
    config.warningGeometryFile,config.warningRankingFile, ...
    config.warningStageSummaryFile,config.warningDiagnosticsFile, ...
    config.warningRankingSourceFile,config.locCoordinateFile, ...
    config.nearInputFile,config.roadEdgeFile,config.siteNodeFile};
for ii=1:numel(requiredFiles)
    if ~isfile(requiredFiles{ii})
        error('run_stage3a_b3_smoke_h2:MissingInput', ...
            'Missing required input: %s',requiredFiles{ii});
    end
end
if isfolder(config.outputDir)
    existing=dir(config.outputDir);
    existing=existing(~ismember({existing.name},{'.','..'}));
    if ~isempty(existing)
        error('run_stage3a_b3_smoke_h2:OutputExists', ...
            'Refusing to overwrite nonempty output directory: %s',config.outputDir);
    end
else
    mkdir(config.outputDir);
end

inputHashesBefore=strings(numel(requiredFiles),1);
inputBytesBefore=zeros(numel(requiredFiles),1);
for ii=1:numel(requiredFiles)
    inputHashesBefore(ii)=sha256_file(requiredFiles{ii});
    info=dir(requiredFiles{ii});inputBytesBefore(ii)=info.bytes;
end

[mainRows,mainFields]=count_csv_rows_and_fields(config.mainSampleFile);
mainHash=inputHashesBefore(1);
candidatePool=readtable(config.candidatePoolFile,'TextType','string');
candidateArchive=readtable(config.candidatePoolArchiveFile,'TextType','string');
candidateHash=inputHashesBefore(2);candidateArchiveHash=inputHashesBefore(3);
fprintf('INPUT|path=%s|rows=%d|fields=%s|sha256=%s\n', ...
    config.mainSampleFile,mainRows,strjoin(mainFields,','),mainHash);
print_table_input(config.candidatePoolFile,candidatePool,candidateHash);
print_table_input(config.candidatePoolArchiveFile,candidateArchive,candidateArchiveHash);
for ii=4:numel(requiredFiles)
    fprintf('INPUT|path=%s|bytes=%d|sha256=%s\n',requiredFiles{ii}, ...
        inputBytesBefore(ii),inputHashesBefore(ii));
end

if mainRows~=config.expectedMainRows||mainHash~=config.expectedMainHash
    error('run_stage3a_b3_smoke_h2:MainSampleVersionMismatch', ...
        'Main sample row count or SHA-256 is not the accepted version.');
end
if height(candidatePool)~=config.expectedCandidateRows || ...
        candidateHash~=candidateArchiveHash || ...
        ~isequaln(candidatePool,candidateArchive)
    error('run_stage3a_b3_smoke_h2:CandidatePoolVersionMismatch', ...
        'Local and Git run-005 candidate pools must be identical with 1126 rows.');
end

mainSample=readtable(config.mainSampleFile);
selectionResult=select_b3_smoke_paths_h2(candidatePool,mainSample,config);
selection=selectionResult.selection;
foundation=build_foundation_fix_coordinates_h2(config);

fprintf('BEGIN_B3_FIXED_RESISTANCE_SMOKE\n');
primary=evaluate_b3_smoke_fixed_resistance_h2(config,foundation,selection,true);
replay=evaluate_b3_smoke_fixed_resistance_h2(config,foundation,selection,false);

reproducibilityAudit=build_reproducibility_audit(primary,replay);
[scenarioWithNovelty,novelPatterns]=build_novel_patterns(primary.scenario_results);
comparison=compare_sources(scenarioWithNovelty,primary.DAC);

inputHashesAfter=strings(numel(requiredFiles),1);
inputBytesAfter=zeros(numel(requiredFiles),1);
for ii=1:numel(requiredFiles)
    inputHashesAfter(ii)=sha256_file(requiredFiles{ii});
    info=dir(requiredFiles{ii});inputBytesAfter(ii)=info.bytes;
end
inputsUnchanged=isequal(inputHashesBefore,inputHashesAfter) && ...
    isequal(inputBytesBefore,inputBytesAfter);

selectionKeys=physical_keys(selection);
sourceCounts=count_sources(selection.source_category);
scenarioCounts=count_sources(primary.scenario_results.source_category);
repeatCounts=groupsummary(primary.scenario_results,'selection_path_id');
selectionPass=height(selection)==30 && numel(unique(selectionKeys))==30 && ...
    all(sourceCounts.count==10);
observedTracePass=all(selectionResult.probability_audit.traceability_pass( ...
    selectionResult.probability_audit.source_category=="observed_candidate"));
unobservedOverlap=sum(selectionResult.probability_audit.main_sample_overlap( ...
    selectionResult.probability_audit.source_category=="unobserved_candidate"));
repeatPass=height(primary.scenario_results)==600 && ...
    all(repeatCounts.GroupCount==config.resistanceRepeats) && ...
    all(scenarioCounts.count==200);
resistancePass=all(primary.resistance_audit.fixed_resistance_pass) && ...
    all(primary.resistance_audit.line_threshold_draws_per_component==1) && ...
    all(primary.resistance_audit.road_threshold_draws_per_component==1) && ...
    all(primary.resistance_audit.line_threshold_reuse_max_abs_error==0) && ...
    all(primary.resistance_audit.road_threshold_reuse_max_abs_error==0);
failurePersistencePass=all(primary.failure_audit.line_persistence_pass) && ...
    all(primary.failure_audit.road_persistence_pass) && ...
    all(primary.failure_audit.slowdown_persistence_pass);
DPass=all(primary.DAC.D_node_kg>=0) && ...
    all(primary.DAC.D_unit=="kg-H2");
APass=all(primary.DAC.A_reachable==0|primary.DAC.A_reachable==1);
CPass=all(isfinite(primary.DAC.C_service_cost_km)) && ...
    all(primary.DAC.C_service_cost_km>=0);
reproPass=all(reproducibilityAudit.passed);
probabilityPass=all(selectionResult.probability_audit.probability_identity_pass) && ...
    all(selection.empirical_weight(selection.source_category~="unobserved_candidate")>0) && ...
    all(selection.empirical_weight(selection.source_category=="unobserved_candidate")==0) && ...
    all(selection.nominal_inclusion_status( ...
    selection.source_category=="unobserved_candidate")=="pending_after_B3");
stagePathPass=check_stage_path_identity(primary.stage_results,selection);
rowCountPass=height(primary.stage_results)==1800 && ...
    height(primary.line_states)==1800*primary.n_lines && ...
    height(primary.road_states)==1800*primary.n_roads && ...
    height(primary.DAC)==1800*primary.n_sites*primary.n_nodes;
durationPass=all(primary.stage_results.slice_duration_h==1) && ...
    config.HresTotalH==3;

executedFiles={mfilename('fullpath')+".m", ...
    fullfile(thisDir,'select_b3_smoke_paths_h2.m'), ...
    fullfile(thisDir,'evaluate_b3_smoke_fixed_resistance_h2.m')};
forbiddenHits=scan_forbidden_calls(executedFiles);
noForbiddenCalls=height(forbiddenHits)==0;

checks={};
checks=add_check(checks,"AUDIT-01","30 unique paths; 10 per source", ...
    selectionPass,height(selection),30);
checks=add_check(checks,"AUDIT-02","observed candidates trace to main sample", ...
    observedTracePass,observedTracePass,true);
checks=add_check(checks,"AUDIT-03","unobserved candidates overlap main sample", ...
    unobservedOverlap==0,unobservedOverlap,0);
checks=add_check(checks,"AUDIT-04","20 repeats per path and 600 scenarios", ...
    repeatPass,height(primary.scenario_results),600);
checks=add_check(checks,"AUDIT-05","fixed resistance reused W1-W3", ...
    resistancePass,resistancePass,true);
checks=add_check(checks,"AUDIT-06","failure/closure/slowdown persistence", ...
    failurePersistencePass,failurePersistencePass,true);
checks=add_check(checks,"AUDIT-07","D nonnegative with kg-H2 unit", ...
    DPass,min(primary.DAC.D_node_kg),0);
checks=add_check(checks,"AUDIT-08","A is binary", ...
    APass,strjoin(compose('%g',unique(primary.DAC.A_reachable)),','),'0,1');
checks=add_check(checks,"AUDIT-09","masked C finite and nonnegative", ...
    CPass,min(primary.DAC.C_service_cost_km),0);
checks=add_check(checks,"AUDIT-10","same-seed replay identical", ...
    reproPass,sum(~reproducibilityAudit.passed),0);
checks=add_check(checks,"AUDIT-11","all source inputs unchanged", ...
    inputsUnchanged,inputsUnchanged,true);
checks=add_check(checks,"AUDIT-12","no WDRO/optimization/MSP calls", ...
    noForbiddenCalls,height(forbiddenHits),0);
checks=add_check(checks,"AUDIT-13","probability identities and pending status", ...
    probabilityPass,probabilityPass,true);
checks=add_check(checks,"AUDIT-14","path stages use selected a/loc/lfw", ...
    stagePathPass,stagePathPass,true);
checks=add_check(checks,"AUDIT-15","detailed output row counts", ...
    rowCountPass,height(primary.DAC),1800*primary.n_sites*primary.n_nodes);
checks=add_check(checks,"AUDIT-16","W1-W3 each 1 h; Hres=3 h", ...
    durationPass,config.HresTotalH,3);
automaticAudit=cell2table(checks,'VariableNames', ...
    {'check_id','description','passed','observed','expected'});
passCount=sum(automaticAudit.passed);failCount=sum(~automaticAudit.passed);
status="PASS";if failCount>0,status="FAIL";end

writetable(selection,fullfile(config.outputDir,'b3_smoke_path_selection.csv'));
writetable(primary.DAC,fullfile(config.outputDir,'b3_smoke_DAC_results.csv'));
writetable(selectionResult.probability_audit,fullfile(config.outputDir, ...
    'probability_identity_audit.csv'));
writetable(primary.resistance_audit,fullfile(config.outputDir, ...
    'resistance_persistence_audit.csv'));
writetable(primary.failure_audit,fullfile(config.outputDir, ...
    'failure_persistence_audit.csv'));
writetable(reproducibilityAudit,fullfile(config.outputDir, ...
    'reproducibility_audit.csv'));
writetable(comparison,fullfile(config.outputDir, ...
    'consequence_comparison_by_source.csv'));
writetable(novelPatterns,fullfile(config.outputDir,'novel_consequence_patterns.csv'));
writetable(automaticAudit,fullfile(config.outputDir,'automatic_audit.csv'));
writetable(selectionResult.selected_states,fullfile(config.outputDir, ...
    'selected_initial_states.csv'));
writetable(primary.stage_results,fullfile(config.outputDir, ...
    'b3_smoke_stage_results.csv'));
writetable(scenarioWithNovelty,fullfile(config.outputDir, ...
    'b3_smoke_scenario_results.csv'));
writetable(primary.line_states,fullfile(config.outputDir,'b3_smoke_line_states.csv'));
writetable(primary.road_states,fullfile(config.outputDir,'b3_smoke_road_states.csv'));
write_run_manifest(fullfile(config.outputDir,'run_manifest.txt'),config,status, ...
    passCount,failCount,mainHash,candidateHash,selection,primary,comparison);
write_readme(fullfile(config.outputDir,'README.txt'),config,status,passCount, ...
    failCount,selectionResult.selected_states,comparison,novelPatterns);

fprintf('\nStage3A B3-smoke finished.\n');
fprintf('Status: %s; PASS=%d; FAIL=%d\n',status,passCount,failCount);
fprintf('Selected paths: %d; B3 scenarios: %d\n',height(selection), ...
    height(primary.scenario_results));
fprintf('D range kg-H2: [%.12g, %.12g]\n',min(primary.DAC.D_node_kg), ...
    max(primary.DAC.D_node_kg));
fprintf('A values: %s\n',strjoin(compose('%g',unique(primary.DAC.A_reachable)),','));
fprintf('C range km: [%.12g, %.12g]\n',min(primary.DAC.C_service_cost_km), ...
    max(primary.DAC.C_service_cost_km));
fprintf('Output directory: %s\n',config.outputDir);
if failCount>0
    error('run_stage3a_b3_smoke_h2:AuditFailed', ...
        'B3-smoke audit failed: %s', ...
        strjoin(automaticAudit.check_id(~automaticAudit.passed),', '));
end

function T=build_reproducibility_audit(A,B)
names=["stage_results";"scenario_results";"resistance_audit";"failure_audit"];
passed=[isequaln(A.stage_results,B.stage_results); ...
    isequaln(A.scenario_results,B.scenario_results); ...
    isequaln(A.resistance_audit,B.resistance_audit); ...
    isequaln(A.failure_audit,B.failure_audit)];
T=table(names,passed,repmat("same seed full replay",4,1), ...
    'VariableNames',{'comparison','passed','method'});
end

function [S,P]=build_novel_patterns(S)
ordinary=S.source_category=="main_ordinary";
ordinaryStructural=unique(S.structural_pattern_signature(ordinary));
ordinaryFull=unique(S.full_consequence_signature(ordinary));
S.structural_seen_in_ordinary=ismember(S.structural_pattern_signature,ordinaryStructural);
S.full_seen_in_ordinary=ismember(S.full_consequence_signature,ordinaryFull);
S.novel_structural_vs_ordinary=S.source_category~="main_ordinary" & ...
    ~S.structural_seen_in_ordinary;
S.novel_full_vs_ordinary=S.source_category~="main_ordinary" & ...
    ~S.full_seen_in_ordinary;
keys=unique(S(:,{'structural_pattern_signature','full_consequence_signature'}),'rows');
rows=cell(height(keys),13);rr=0;
for ii=1:height(keys)
    mask=S.structural_pattern_signature==keys.structural_pattern_signature(ii) & ...
        S.full_consequence_signature==keys.full_consequence_signature(ii);
    rr=rr+1;
    rows(rr,:)={keys.structural_pattern_signature(ii), ...
        keys.full_consequence_signature(ii),sum(mask), ...
        sum(mask&S.source_category=="main_ordinary"), ...
        sum(mask&S.source_category=="observed_candidate"), ...
        sum(mask&S.source_category=="unobserved_candidate"), ...
        any(S.structural_seen_in_ordinary(mask)),any(S.full_seen_in_ordinary(mask)), ...
        any(S.novel_structural_vs_ordinary(mask)),any(S.novel_full_vs_ordinary(mask)), ...
        min(S.D_Hres3h_total_kg(mask)),mean(S.D_Hres3h_total_kg(mask)), ...
        max(S.D_Hres3h_total_kg(mask))};
end
P=cell2table(rows,'VariableNames', ...
    {'structural_pattern_signature','full_consequence_signature', ...
    'scenario_count','ordinary_scenario_count','observed_candidate_scenario_count', ...
    'unobserved_candidate_scenario_count','structural_seen_in_ordinary', ...
    'full_seen_in_ordinary','novel_structural_vs_ordinary', ...
    'novel_full_vs_ordinary','D_total_min_kg','D_total_mean_kg','D_total_max_kg'});
P=P(P.observed_candidate_scenario_count>0|P.unobserved_candidate_scenario_count>0,:);
end

function C=compare_sources(S,DAC)
sources=["main_ordinary";"observed_candidate";"unobserved_candidate"];
rows=cell(3,28);
for ii=1:3
    q=S(S.source_category==sources(ii),:);
    d=DAC(DAC.source_category==sources(ii),:);
    rows(ii,:)={sources(ii),height(q),numel(unique(q.selection_path_id)), ...
        min(q.D_Hres3h_total_kg),mean(q.D_Hres3h_total_kg), ...
        pct(q.D_Hres3h_total_kg,95),max(q.D_Hres3h_total_kg), ...
        min(q.P_loss_stage_sum_kW),mean(q.P_loss_stage_sum_kW), ...
        max(q.P_loss_stage_sum_kW),min(q.reachable_pair_share_stage_mean), ...
        mean(q.reachable_pair_share_stage_mean), ...
        max(q.reachable_pair_share_stage_mean),min(d.C_service_cost_km), ...
        mean(d.C_service_cost_km),max(d.C_service_cost_km), ...
        mean(q.failed_lines_W3),max(q.failed_lines_W3), ...
        mean(q.closed_roads_W3),max(q.closed_roads_W3), ...
        mean(q.joint_line_road_damage_any),mean(q.multi_line_failure_any), ...
        mean(q.road_disconnection_any),sum(q.novel_structural_vs_ordinary), ...
        mean(q.novel_structural_vs_ordinary),sum(q.novel_full_vs_ordinary), ...
        mean(q.novel_full_vs_ordinary), ...
        sum(q.full_seen_in_ordinary)};
end
C=cell2table(rows,'VariableNames', ...
    {'source_category','scenario_count','selected_path_count','D_min_kg', ...
    'D_mean_kg','D_p95_kg','D_max_kg','P_loss_stage_sum_min_kW', ...
    'P_loss_stage_sum_mean_kW','P_loss_stage_sum_max_kW', ...
    'A_stage_mean_min','A_stage_mean_mean','A_stage_mean_max', ...
    'C_masked_min_km','C_masked_mean_km','C_masked_max_km', ...
    'failed_lines_W3_mean','failed_lines_W3_max','closed_roads_W3_mean', ...
    'closed_roads_W3_max','joint_line_road_damage_share', ...
    'multi_line_failure_share','road_disconnection_share', ...
    'novel_structural_scenario_count','novel_structural_scenario_share', ...
    'novel_full_scenario_count','novel_full_scenario_share', ...
    'full_pattern_seen_in_ordinary_count'});
end

function pass=check_stage_path_identity(stage,selection)
pass=true;
for pp=1:height(selection)
    q=stage(stage.selection_path_id==selection.selection_path_id(pp),:);
    for ss=1:3
        z=q(q.stage_index==ss,:);
        pass=pass&&all(z.a==selection.("a"+string(ss))(pp)) && ...
            all(z.loc==selection.("loc"+string(ss))(pp)) && ...
            all(z.lfw==selection.("lfw"+string(ss))(pp));
    end
end
end

function T=count_sources(source)
names=unique(source);count=zeros(numel(names),1);
for ii=1:numel(names),count(ii)=sum(source==names(ii));end
T=table(names,count,'VariableNames',{'source_category','count'});
end

function hits=scan_forbidden_calls(files)
patterns=["solve_wdro_terminal_loh_lp_h2\\s*\\(","gurobi\\s*\\(", ...
    "main_msp_h2_near\\s*\\(","run_h2_with_options\\s*\\(", ...
    "optimize\\s*\\(","linprog\\s*\\("];
rows={};
for ii=1:numel(files)
    text=fileread(files{ii});
    for pp=1:numel(patterns)
        if ~isempty(regexp(text,patterns(pp),'once'))
            rows(end+1,:)={string(files{ii}),patterns(pp)}; %#ok<AGROW>
        end
    end
end
if isempty(rows),hits=cell2table(cell(0,2),'VariableNames',{'file','pattern'});
else,hits=cell2table(rows,'VariableNames',{'file','pattern'});end
end

function keys=physical_keys(T)
keys=string(compose('%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d', ...
    T.a0,T.loc0,T.lfw0,T.a1,T.loc1,T.lfw1,T.a2,T.loc2,T.lfw2, ...
    T.a3,T.loc3,T.lfw3));
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

function print_table_input(fileName,T,hash)
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
digest=typecast(md.digest(),'uint8');
hash=lower(string(reshape(dec2hex(digest,2).',1,[])));
end

function value=pct(x,p)
x=sort(double(x(:)));x=x(isfinite(x));
if isempty(x),value=NaN;else
    idx=max(1,min(numel(x),ceil(p/100*numel(x))));value=x(idx);
end
end

function write_run_manifest(fileName,config,status,passCount,failCount,mainHash,candidateHash,selection,result,comparison)
fid=fopen(fileName,'w');if fid<0,error('Could not write %s.',fileName);end
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'task_id=task-002\nstep_id=01-b3-smoke\nrun_id=run-001\n');
fprintf(fid,'run_time=%s\nstatus=%s\npass_count=%d\nfail_count=%d\n', ...
    char(datetime('now','Format','yyyy-MM-dd HH:mm:ss Z')),status,passCount,failCount);
fprintf(fid,'damage_mode=persistent_fixed_resistance\nRmax=%g\nWstep=%g\n', ...
    config.Rmax,config.Wstep);
fprintf(fid,'selected_paths=%d\nresistance_repeats_per_path=%d\nB3_scenarios=%d\n', ...
    height(selection),config.resistanceRepeats,height(result.scenario_results));
fprintf(fid,'main_sample_sha256=%s\ncandidate_pool_sha256=%s\n',mainHash,candidateHash);
for ii=1:height(comparison)
    label=char(comparison.source_category(ii));
    fprintf(fid,'%s_D_range_kg=%.15g,%.15g\n',label, ...
        comparison.D_min_kg(ii),comparison.D_max_kg(ii));
    fprintf(fid,'%s_novel_full_scenarios=%d\n',label, ...
        comparison.novel_full_scenario_count(ii));
end
fprintf(fid,'unobserved_nominal_inclusion_status=pending_after_B3\n');
fprintf(fid,'WDRO_run=false\noptimization_run=false\nMSP_run=false\nformal_nominal_distribution_changed=false\n');
end

function write_readme(fileName,config,status,passCount,failCount,states,comparison,patterns)
fid=fopen(fileName,'w');if fid<0,error('Could not write %s.',fileName);end
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'Step-03A run-001: fixed-resistance B3-smoke\n\n');
fprintf(fid,'status=%s; PASS=%d; FAIL=%d\n',status,passCount,failCount);
fprintf(fid,'damage_mode=persistent_fixed_resistance\nRmax=%g\nWstep=%g\n', ...
    config.Rmax,config.Wstep);
fprintf(fid,'W1/W2/W3 each 1 h; Hres=3 h; resistance repeats per path=%d.\n', ...
    config.resistanceRepeats);
fprintf(fid,'Selected initial states:\n');
for ii=1:height(states)
    fprintf(fid,'- (%g,%g,%g): %s; candidate_count=%d.\n',states.a0(ii), ...
        states.loc0(ii),states.lfw0(ii),states.state_selection_rule(ii), ...
        states.candidate_count(ii));
end
fprintf(fid,'\nProbability identity:\n');
fprintf(fid,'- ordinary and observed candidate paths retain frequency/15000.\n');
fprintf(fid,'- unobserved candidates have empirical_weight=0 and status pending_after_B3.\n');
fprintf(fid,'- the 30-path smoke set is not an equal-weight probability distribution.\n\n');
for ii=1:height(comparison)
    fprintf(fid,'- %s: D=[%.12g, %.12g] kg; A mean=%.12g; C=[%.12g, %.12g] km; novel full scenarios=%d.\n', ...
        comparison.source_category(ii),comparison.D_min_kg(ii), ...
        comparison.D_max_kg(ii),comparison.A_stage_mean_mean(ii), ...
        comparison.C_masked_min_km(ii),comparison.C_masked_max_km(ii), ...
        comparison.novel_full_scenario_count(ii));
end
fprintf(fid,'\nCandidate full consequence patterns not seen in ordinary smoke scenarios: %d.\n', ...
    sum(patterns.novel_full_vs_ordinary));
fprintf(fid,'C is masked finite cost: dist(n) when A=1, zero when A=0.\n');
fprintf(fid,'No final representative selection, nominal-distribution change, WDRO, optimization, or MSP.\n');
end
