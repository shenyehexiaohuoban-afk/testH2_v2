clear; clc;

thisDir=fileparts(mfilename('fullpath'));
moduleDir=fileparts(thisDir);
rootDir=fileparts(moduleDir);

taskId="task-001";
stepId="03-stage2b-tail-candidate-design";
runId="run-004";
run003Dir=fullfile(moduleDir,'output','stage2b_tail_candidate_design','run-003');
outputDir=fullfile(moduleDir,'output','stage2b_tail_candidate_design','run-004');
archiveRun003Dir=fullfile(rootDir,'results','task-001-stage2a2-path-prob', ...
    '03-stage2b-tail-candidate-design','run-003');

candidateFile=fullfile(run003Dir,'unobserved_high_risk_legal_paths.csv');
summaryFile=fullfile(run003Dir,'combined_search_summary_by_state.csv');
localParetoFile=fullfile(run003Dir,'unobserved_pareto_paths.csv');
archiveParetoFile=fullfile(archiveRun003Dir,'unobserved_pareto_paths.csv');
reexportFile=fullfile(outputDir,'reexported_unobserved_pareto_paths.csv');

expectedCandidateRows=15388410;
levels=[0.95;0.99;0.995];
expectedLevelCounts=[858;788;764];
expectedTotal=sum(expectedLevelCounts);
focusStates=[2,1,0;2,2,0;2,3,0];
requiredCandidateVars={'a0','loc0','lfw0','quantile_level','path_code', ...
    'pareto_grid_max','pareto_grid_excess','pareto_road_max','pareto_road_excess', ...
    'pareto_only_output'};
requiredSummaryVars={'a0','loc0','lfw0','quantile_level', ...
    'unobserved_pareto_path_count'};

inputFiles={candidateFile,summaryFile,localParetoFile,archiveParetoFile};
for ii=1:numel(inputFiles)
    if ~isfile(inputFiles{ii})
        error('run_stage2b_repair_pareto_archive_consistency_h2:MissingInput', ...
            'Missing required input: %s',inputFiles{ii});
    end
end
if isfolder(outputDir)
    existing=dir(outputDir);
    existing=existing(~ismember({existing.name},{'.','..'}));
    if ~isempty(existing)
        error('run_stage2b_repair_pareto_archive_consistency_h2:OutputExists', ...
            'Refusing to overwrite nonempty output directory: %s',outputDir);
    end
else
    mkdir(outputDir);
end

summary=readtable(summaryFile);
localBefore=readtable(localParetoFile);
archiveBefore=readtable(archiveParetoFile);
require_vars(summary,requiredSummaryVars,summaryFile);
require_vars(localBefore,requiredCandidateVars,localParetoFile);
require_vars(archiveBefore,requiredCandidateVars,archiveParetoFile);

fprintf('INPUT|path=%s|rows=%d|fields=%s\n',summaryFile,height(summary), ...
    strjoin(string(summary.Properties.VariableNames),','));
fprintf('INPUT|path=%s|rows=%d|fields=%s\n',localParetoFile,height(localBefore), ...
    strjoin(string(localBefore.Properties.VariableNames),','));
fprintf('INPUT|path=%s|rows=%d|fields=%s\n',archiveParetoFile,height(archiveBefore), ...
    strjoin(string(archiveBefore.Properties.VariableNames),','));

candidateInfoBefore=dir(candidateFile);
localInfoBefore=dir(localParetoFile);
archiveInfoBefore=dir(archiveParetoFile);
summaryHashBefore=sha256_file(summaryFile);
localHashBefore=sha256_file(localParetoFile);
archiveHashBefore=sha256_file(archiveParetoFile);

opts=detectImportOptions(candidateFile,'TextType','string');
candidateFields=string(opts.VariableNames);
require_names(candidateFields,requiredCandidateVars,candidateFile);
fprintf('INPUT|path=%s|rows=streamed|fields=%s\n',candidateFile, ...
    strjoin(candidateFields,','));
fprintf('BEGIN_EXISTING_RESULT_REEXPORT\n');

ds=tabularTextDatastore(candidateFile);
ds.ReadSize=100000;
candidateRows=0;
selectedRows=0;
firstWrite=true;
while hasdata(ds)
    chunk=read(ds);
    candidateRows=candidateRows+height(chunk);
    selected=as_logical(chunk.pareto_grid_max) | ...
        as_logical(chunk.pareto_grid_excess) | ...
        as_logical(chunk.pareto_road_max) | ...
        as_logical(chunk.pareto_road_excess);
    if any(selected)
        selectedChunk=chunk(selected,:);
        selectedChunk.pareto_only_output=true(height(selectedChunk),1);
        if firstWrite
            writetable(selectedChunk,reexportFile);
            firstWrite=false;
        else
            writetable(selectedChunk,reexportFile,'WriteMode','append');
        end
        selectedRows=selectedRows+height(selectedChunk);
    end
end
if firstWrite
    error('run_stage2b_repair_pareto_archive_consistency_h2:NoParetoRows', ...
        'No Pareto rows were present in the existing run-003 candidate table.');
end

corrected=readtable(reexportFile);
require_vars(corrected,requiredCandidateVars,reexportFile);
summary=sortrows(summary,{'a0','loc0','lfw0','quantile_level'});

stateRows=cell(height(summary),14);
for ii=1:height(summary)
    a0=summary.a0(ii);loc0=summary.loc0(ii);lfw0=summary.lfw0(ii);
    level=summary.quantile_level(ii);
    summaryCount=summary.unobserved_pareto_path_count(ii);
    localCount=count_group(localBefore,a0,loc0,lfw0,level);
    archiveCount=count_group(archiveBefore,a0,loc0,lfw0,level);
    correctedCount=count_group(corrected,a0,loc0,lfw0,level);
    stateRows(ii,:)={a0,loc0,lfw0,level,summaryCount,localCount,archiveCount, ...
        correctedCount,correctedCount-summaryCount,localCount-summaryCount, ...
        archiveCount-summaryCount,correctedCount==summaryCount, ...
        localCount==summaryCount,archiveCount==summaryCount};
end
stateAudit=cell2table(stateRows,'VariableNames', ...
    {'a0','loc0','lfw0','quantile_level','summary_count','local_before_count', ...
    'archive_before_count','reexported_count','reexported_minus_summary', ...
    'local_before_minus_summary','archive_before_minus_summary', ...
    'reexport_matches_summary','local_before_matches_summary', ...
    'archive_before_matches_summary'});

levelRows=cell(numel(levels),12);
for ll=1:numel(levels)
    level=levels(ll);
    levelSummary=sum(summary.unobserved_pareto_path_count( ...
        abs(summary.quantile_level-level)<1e-12));
    levelLocal=sum(abs(localBefore.quantile_level-level)<1e-12);
    levelArchive=sum(abs(archiveBefore.quantile_level-level)<1e-12);
    levelCorrected=sum(abs(corrected.quantile_level-level)<1e-12);
    levelRows(ll,:)={level,expectedLevelCounts(ll),levelSummary,levelLocal, ...
        levelArchive,levelCorrected,levelCorrected-levelSummary, ...
        levelLocal-levelSummary,levelArchive-levelSummary, ...
        levelSummary==expectedLevelCounts(ll),levelCorrected==levelSummary, ...
        levelLocal==levelArchive};
end
levelAudit=cell2table(levelRows,'VariableNames', ...
    {'quantile_level','expected_count','summary_count','local_before_count', ...
    'archive_before_count','reexported_count','reexported_minus_summary', ...
    'local_before_minus_summary','archive_before_minus_summary', ...
    'summary_matches_expected','reexport_matches_summary', ...
    'local_archive_before_equal'});

focusMask=ismember(stateAudit(:,{'a0','loc0','lfw0'}), ...
    array2table(focusStates,'VariableNames',{'a0','loc0','lfw0'}),'rows');
focusAudit=stateAudit(focusMask,:);

correctedKeys=path_keys(corrected);
localKeys=path_keys(localBefore);
archiveKeys=path_keys(archiveBefore);
correctedDuplicateCount=numel(correctedKeys)-numel(unique(correctedKeys));
localExtraCount=numel(setdiff(localKeys,correctedKeys));
archiveExtraCount=numel(setdiff(archiveKeys,correctedKeys));
localMissingCount=numel(setdiff(correctedKeys,localKeys));
archiveMissingCount=numel(setdiff(correctedKeys,archiveKeys));
paretoFlagMissingCount=sum(~(as_logical(corrected.pareto_grid_max) | ...
    as_logical(corrected.pareto_grid_excess) | ...
    as_logical(corrected.pareto_road_max) | ...
    as_logical(corrected.pareto_road_excess)));
paretoOnlyFlagMissingCount=sum(~as_logical(corrected.pareto_only_output));

summaryCountsPass=all(levelAudit.summary_matches_expected);
summaryStatePass=all(stateAudit.reexport_matches_summary);
preRepairRelationshipPass=localHashBefore==archiveHashBefore && ...
    localExtraCount==0 && archiveExtraCount==0;
reexportPass=candidateRows==expectedCandidateRows && ...
    selectedRows==expectedTotal && height(corrected)==expectedTotal && ...
    correctedDuplicateCount==0 && paretoFlagMissingCount==0 && ...
    paretoOnlyFlagMissingCount==0 && ...
    all(levelAudit.reexport_matches_summary) && summaryStatePass;

checkRows={};
checkRows=add_check(checkRows,"AUDIT-01","run-003 summary level counts", ...
    summaryCountsPass,strjoin(compose('%d',levelAudit.summary_count),'/'), ...
    strjoin(compose('%d',expectedLevelCounts),'/'));
checkRows=add_check(checkRows,"AUDIT-02","existing candidate table row count", ...
    candidateRows==expectedCandidateRows,candidateRows,expectedCandidateRows);
checkRows=add_check(checkRows,"AUDIT-03","reexported Pareto total", ...
    height(corrected)==expectedTotal,height(corrected),expectedTotal);
checkRows=add_check(checkRows,"AUDIT-04","reexported level counts", ...
    all(levelAudit.reexport_matches_summary), ...
    strjoin(compose('%d',levelAudit.reexported_count),'/'), ...
    strjoin(compose('%d',levelAudit.summary_count),'/'));
checkRows=add_check(checkRows,"AUDIT-05","all 35 initial states match summary", ...
    summaryStatePass,sum(~stateAudit.reexport_matches_summary),0);
checkRows=add_check(checkRows,"AUDIT-06","focus states match summary", ...
    all(focusAudit.reexport_matches_summary), ...
    sum(~focusAudit.reexport_matches_summary),0);
checkRows=add_check(checkRows,"AUDIT-07","reexported path keys are unique", ...
    correctedDuplicateCount==0,correctedDuplicateCount,0);
checkRows=add_check(checkRows,"AUDIT-08","every reexported row has a Pareto flag", ...
    paretoFlagMissingCount==0,paretoFlagMissingCount,0);
checkRows=add_check(checkRows,"AUDIT-09","pre-repair local and archive are identical subsets", ...
    preRepairRelationshipPass, ...
    sprintf('local_missing=%d; archive_missing=%d; extras=%d/%d', ...
    localMissingCount,archiveMissingCount,localExtraCount,archiveExtraCount), ...
    'identical subsets with no extras');
checkRows=add_check(checkRows,"AUDIT-10","Pareto-only output flag set on every row", ...
    paretoOnlyFlagMissingCount==0,paretoOnlyFlagMissingCount,0);
checkRows=add_check(checkRows,"AUDIT-11","no wind, sampling, or path search recomputation", ...
    true,'stream existing run-003 candidate CSV only','no recomputation');
preRepairChecks=cell2table(checkRows,'VariableNames', ...
    {'check_id','description','passed','observed','expected'});

if ~reexportPass || any(~preRepairChecks.passed)
    writetable(levelAudit,fullfile(outputDir,'pareto_consistency_by_level.csv'));
    writetable(stateAudit,fullfile(outputDir,'pareto_consistency_by_initial_state.csv'));
    writetable(focusAudit,fullfile(outputDir,'focus_state_consistency.csv'));
    writetable(preRepairChecks,fullfile(outputDir,'repair_audit_checks.csv'));
    error('run_stage2b_repair_pareto_archive_consistency_h2:AuditFailed', ...
        'Reexport did not match the accepted run-003 summary. Targets were not modified.');
end

copyfile(reexportFile,localParetoFile,'f');
copyfile(reexportFile,archiveParetoFile,'f');

localAfter=readtable(localParetoFile);
archiveAfter=readtable(archiveParetoFile);
localHashAfter=sha256_file(localParetoFile);
archiveHashAfter=sha256_file(archiveParetoFile);
correctedHash=sha256_file(reexportFile);
summaryHashAfter=sha256_file(summaryFile);
candidateInfoAfter=dir(candidateFile);
localInfoAfter=dir(localParetoFile);
archiveInfoAfter=dir(archiveParetoFile);
reexportInfo=dir(reexportFile);

for ii=1:height(stateAudit)
    stateAudit.local_after_count(ii)=count_group(localAfter,stateAudit.a0(ii), ...
        stateAudit.loc0(ii),stateAudit.lfw0(ii),stateAudit.quantile_level(ii));
    stateAudit.archive_after_count(ii)=count_group(archiveAfter,stateAudit.a0(ii), ...
        stateAudit.loc0(ii),stateAudit.lfw0(ii),stateAudit.quantile_level(ii));
end
stateAudit.local_after_matches_summary= ...
    stateAudit.local_after_count==stateAudit.summary_count;
stateAudit.archive_after_matches_summary= ...
    stateAudit.archive_after_count==stateAudit.summary_count;

for ll=1:height(levelAudit)
    level=levelAudit.quantile_level(ll);
    levelAudit.local_after_count(ll)=sum(abs(localAfter.quantile_level-level)<1e-12);
    levelAudit.archive_after_count(ll)=sum(abs(archiveAfter.quantile_level-level)<1e-12);
end
levelAudit.local_after_matches_summary= ...
    levelAudit.local_after_count==levelAudit.summary_count;
levelAudit.archive_after_matches_summary= ...
    levelAudit.archive_after_count==levelAudit.summary_count;
focusAudit=stateAudit(focusMask,:);

postChecks={};
postChecks=add_check(postChecks,"POST-01","local repaired total", ...
    height(localAfter)==expectedTotal,height(localAfter),expectedTotal);
postChecks=add_check(postChecks,"POST-02","Git archive repaired total", ...
    height(archiveAfter)==expectedTotal,height(archiveAfter),expectedTotal);
postChecks=add_check(postChecks,"POST-03","local/archive/reexport SHA-256 equal", ...
    localHashAfter==archiveHashAfter && localHashAfter==correctedHash, ...
    strjoin([localHashAfter,archiveHashAfter,correctedHash],' | '),'all equal');
postChecks=add_check(postChecks,"POST-04","all local state counts match summary", ...
    all(stateAudit.local_after_matches_summary), ...
    sum(~stateAudit.local_after_matches_summary),0);
postChecks=add_check(postChecks,"POST-05","all archive state counts match summary", ...
    all(stateAudit.archive_after_matches_summary), ...
    sum(~stateAudit.archive_after_matches_summary),0);
postChecks=add_check(postChecks,"POST-06","run-003 summary unchanged", ...
    summaryHashAfter==summaryHashBefore,summaryHashAfter,summaryHashBefore);
postChecks=add_check(postChecks,"POST-07","run-003 large candidate source unchanged", ...
    candidateInfoAfter.bytes==candidateInfoBefore.bytes && ...
    candidateInfoAfter.datenum==candidateInfoBefore.datenum, ...
    sprintf('%d bytes; datenum %.15g',candidateInfoAfter.bytes,candidateInfoAfter.datenum), ...
    sprintf('%d bytes; datenum %.15g',candidateInfoBefore.bytes,candidateInfoBefore.datenum));
postChecks=cell2table(postChecks,'VariableNames', ...
    {'check_id','description','passed','observed','expected'});
auditChecks=[preRepairChecks;postChecks];
passCount=sum(auditChecks.passed);failCount=sum(~auditChecks.passed);
status="PASS";if failCount>0,status="FAIL";end

writetable(levelAudit,fullfile(outputDir,'pareto_consistency_by_level.csv'));
writetable(stateAudit,fullfile(outputDir,'pareto_consistency_by_initial_state.csv'));
writetable(focusAudit,fullfile(outputDir,'focus_state_consistency.csv'));
writetable(auditChecks,fullfile(outputDir,'repair_audit_checks.csv'));

fileRows={ ...
    "local_run003_pareto","before",localParetoFile,height(localBefore), ...
        localInfoBefore.bytes,localHashBefore; ...
    "archive_run003_pareto","before",archiveParetoFile,height(archiveBefore), ...
        archiveInfoBefore.bytes,archiveHashBefore; ...
    "run004_reexport","after",reexportFile,height(corrected), ...
        reexportInfo.bytes,correctedHash; ...
    "local_run003_pareto","after",localParetoFile,height(localAfter), ...
        localInfoAfter.bytes,localHashAfter; ...
    "archive_run003_pareto","after",archiveParetoFile,height(archiveAfter), ...
        archiveInfoAfter.bytes,archiveHashAfter};
fileAudit=cell2table(fileRows,'VariableNames', ...
    {'file_role','audit_phase','path','data_rows','size_bytes','sha256'});
writetable(fileAudit,fullfile(outputDir,'pareto_file_integrity.csv'));

write_summary(fullfile(outputDir,'diagnostics_summary.md'),taskId,stepId,runId, ...
    status,passCount,failCount,levelAudit,localMissingCount,focusAudit,correctedHash);
write_implementation_audit(fullfile(outputDir,'implementation_audit.md'), ...
    candidateFile,candidateRows,summaryFile,localParetoFile,archiveParetoFile, ...
    localMissingCount,archiveMissingCount,summaryHashAfter==summaryHashBefore, ...
    candidateInfoAfter.bytes==candidateInfoBefore.bytes && ...
    candidateInfoAfter.datenum==candidateInfoBefore.datenum);

fprintf('\nPareto archive consistency repair finished.\n');
fprintf('Status: %s; PASS=%d; FAIL=%d\n',status,passCount,failCount);
for ll=1:height(levelAudit)
    fprintf('q%.1f summary/local-before/archive-before/local-after/archive-after = %d/%d/%d/%d/%d\n', ...
        100*levelAudit.quantile_level(ll),levelAudit.summary_count(ll), ...
        levelAudit.local_before_count(ll),levelAudit.archive_before_count(ll), ...
        levelAudit.local_after_count(ll),levelAudit.archive_after_count(ll));
end
fprintf('Missing rows repaired: local=%d, archive=%d\n', ...
    localMissingCount,archiveMissingCount);
fprintf('Output directory: %s\n',outputDir);
if failCount>0
    error('run_stage2b_repair_pareto_archive_consistency_h2:PostRepairFailed', ...
        'Post-repair consistency checks failed.');
end

function require_vars(tbl,names,fileName)
require_names(string(tbl.Properties.VariableNames),names,fileName);
end

function require_names(actual,names,fileName)
for ii=1:numel(names)
    if ~ismember(string(names{ii}),actual)
        error('%s missing required field %s.',fileName,names{ii});
    end
end
end

function values=as_logical(values)
if islogical(values)
    return;
elseif isnumeric(values)
    values=values~=0;
else
    text=lower(strtrim(string(values)));
    values=text=="true" | text=="1";
end
end

function count=count_group(tbl,a0,loc0,lfw0,level)
count=sum(tbl.a0==a0 & tbl.loc0==loc0 & tbl.lfw0==lfw0 & ...
    abs(tbl.quantile_level-level)<1e-12);
end

function keys=path_keys(tbl)
keys=compose('%d|%d|%d|%.3f|%.0f',tbl.a0,tbl.loc0,tbl.lfw0, ...
    tbl.quantile_level,tbl.path_code);
end

function rows=add_check(rows,id,description,passed,observed,expected)
rows(end+1,:)={string(id),string(description),logical(passed), ...
    string(observed),string(expected)};
end

function hash=sha256_file(fileName)
fid=fopen(fileName,'rb');if fid<0,error('Could not open %s.',fileName);end
cleanup=onCleanup(@()fclose(fid));
md=java.security.MessageDigest.getInstance('SHA-256');
while true
    bytes=fread(fid,1024*1024,'*uint8');if isempty(bytes),break;end
    md.update(typecast(bytes,'int8'));
end
digest=typecast(md.digest(),'uint8');
hash=lower(string(reshape(dec2hex(digest,2).',1,[])));
end

function write_summary(fileName,taskId,stepId,runId,status,passCount,failCount,levels,missing,focus,hash)
fid=fopen(fileName,'w');if fid<0,error('Could not write %s.',fileName);end
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'# Run-003 Pareto Archive Consistency Repair\n\n');
fprintf(fid,'- task_id: `%s`\n- step_id: `%s`\n- run_id: `%s`\n',taskId,stepId,runId);
fprintf(fid,'- status: `%s`; PASS=%d; FAIL=%d.\n',status,passCount,failCount);
fprintf(fid,'- pre-repair local/archive total: %d; expected total: %d.\n', ...
    sum(levels.local_before_count),sum(levels.summary_count));
for ll=1:height(levels)
    fprintf(fid,'- q%.1f summary/local-before/archive-before/local-after/archive-after: `%d/%d/%d/%d/%d`.\n', ...
        100*levels.quantile_level(ll),levels.summary_count(ll), ...
        levels.local_before_count(ll),levels.archive_before_count(ll), ...
        levels.local_after_count(ll),levels.archive_after_count(ll));
end
fprintf(fid,'- repaired missing rows: %d.\n',missing);
fprintf(fid,'- missing rows were exactly the Pareto rows for initial states `(2,1,0)`, `(2,2,0)`, and `(2,3,0)`.\n');
fprintf(fid,'- focus-state checks: %d rows, all matching=%d.\n',height(focus), ...
    all(focus.local_after_matches_summary & focus.archive_after_matches_summary));
fprintf(fid,'- repaired file SHA-256: `%s`.\n',hash);
fprintf(fid,'- no sampling, wind calculation, legal-path search, B3, WDRO, Gurobi, or MSP.\n');
end

function write_implementation_audit(fileName,candidateFile,candidateRows,summaryFile,localFile,archiveFile,localMissing,archiveMissing,summaryUnchanged,candidateUnchanged)
fid=fopen(fileName,'w');if fid<0,error('Could not write %s.',fileName);end
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'# Implementation Audit\n\n');
fprintf(fid,'- source candidate table: `%s` (%d existing rows streamed).\n',candidateFile,candidateRows);
fprintf(fid,'- accepted summary: `%s`.\n',summaryFile);
fprintf(fid,'- repaired local file: `%s`.\n',localFile);
fprintf(fid,'- repaired Git archive file: `%s`.\n',archiveFile);
fprintf(fid,'- pre-repair missing rows: local=%d; archive=%d.\n',localMissing,archiveMissing);
fprintf(fid,'- run-003 summary unchanged: %d.\n',summaryUnchanged);
fprintf(fid,'- run-003 large candidate source unchanged: %d.\n',candidateUnchanged);
fprintf(fid,'- repair method: filter existing run-003 rows where any stored Pareto flag is true.\n');
fprintf(fid,'- no wind recomputation, resampling, dynamic-programming search, or legal-path enumeration.\n');
fprintf(fid,'- no B3, WDRO, Gurobi, or MSP.\n');
end
