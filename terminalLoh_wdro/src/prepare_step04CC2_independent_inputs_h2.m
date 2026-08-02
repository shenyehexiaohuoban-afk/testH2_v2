function prepare_step04CC2_independent_inputs_h2(workDir)
%PREPARE_STEP04CC2_INDEPENDENT_INPUTS_H2 Freeze three independent state19 sets.

started = tic;
workDir = string(workDir);
thisDir = fileparts(mfilename('fullpath'));
moduleDir = fileparts(thisDir);
rootDir = fileparts(moduleDir);
addpath(rootDir); addpath(thisDir);
assert_git_gate("task/002-stage2b-b3-smoke", ...
    "dbdb728961c623e976cb1a749310ebbeb5f32810");
if ~isfolder(workDir), mkdir(workDir); end
if isfile(fullfile(workDir,'prepare_mechanical_audit.txt'))
    error('prepare_step04CC2_independent_inputs_h2:OutputExists', ...
        'Refusing to overwrite an existing C2 preparation.');
end
diary(fullfile(workDir,'prepare_matlab_diary.txt'));
cleanupDiary = onCleanup(@()diary('off'));

c1File = fullfile(rootDir,'results','task-002-stage2b-b3-smoke', ...
    '46-flat-chi2-eta-calibration','run-003','eta_full_results.csv');
mainPathFile = fullfile(moduleDir,'output','stage2a2_W3_path_sampling', ...
    'run-002','main_path_samples.csv');
seedMapFile = fullfile(moduleDir,'output','stage3j_wdro_input_freeze', ...
    'run-001','dataset_role_and_seed_map.csv');
a2Dir = fullfile(rootDir,'results','task-002-stage2b-b3-smoke', ...
    '44-extreme-formal-consequence-freeze','run-003');
a2MatFile = fullfile(a2Dir,'extreme_formal_DAC_and_damage.mat');
a2ManifestFile = fullfile(a2Dir,'extreme_consequence_identity_manifest.csv');
configDir = fullfile(moduleDir,'config');
matrixFiles = [string(fullfile(configDir,'lookahead_intensity_postlandfall_W3.csv')); ...
    string(fullfile(configDir,'lookahead_location_postlandfall_W3.csv')); ...
    string(fullfile(configDir,'lookahead_lfw_postlandfall_W3.csv'))];

inputPaths = [string(c1File);matrixFiles;string(mainPathFile); ...
    string(seedMapFile);string(a2ManifestFile);string(a2MatFile)];
inputLabels = ["C1_eta_full_results";"intensity_transition"; ...
    "location_transition";"lfw_transition";"accepted_main_paths"; ...
    "Step03J_seed_map";"Step04CA2_identity_manifest";"Step04CA2_formal_MAT"];
expectedHashes = [ ...
    "16947d17fc2a3ff4a30bb966e14b5b76a0bf19a27dec48722ab405b930c6daf0"; ...
    "ea6c71ed9765a57577940560f45e9ad6003a69ef4bb9abae54b9deaaf78889e5"; ...
    "42d167a61478e05e2ff4eb9012e6c25d92a53060d2f00fb7ff60ee45f0139ca1"; ...
    "45cf74286b0aec48fe4a0ba77c66ab0847c2227402740bcc18a376da0eff6c29"; ...
    "972a8c58620c09ac19cfcfb29e8d6a3ed2819ef1a22dbd522043436418eb805d"; ...
    "1ffab8c48894c991b27dc440a419e38f2ff29d6b612f18605e65bea57fc7ae64"; ...
    "ec009c64f7533d599963609cb1b3b6505ba85451cfe4a8c250315966c834132e"; ...
    "be530c72d92386f37ca4d4690d05d2907a1a03bf7fbc1d63eb25c1dce1b283e8"];
actualHashes = strings(size(inputPaths)); inputBytes = zeros(size(inputPaths));
for ii=1:numel(inputPaths)
    if ~isfile(inputPaths(ii)), error('Missing frozen input: %s',inputPaths(ii)); end
    actualHashes(ii)=sha256_file(inputPaths(ii)); info=dir(inputPaths(ii));
    inputBytes(ii)=info.bytes;
end
hashPass = actualHashes == expectedHashes;
if ~all(hashPass), error('Step-04C-C2 frozen-input hash gate failed.'); end
writetable(table(inputLabels,inputPaths,inputBytes,actualHashes,expectedHashes,hashPass, ...
    'VariableNames',{'input_label','path','bytes','sha256','expected_sha256','hash_pass'}), ...
    fullfile(workDir,'frozen_input_manifest.csv'));

decisions = read_frozen_decisions(c1File);
writetable(decisions,fullfile(workDir,'fixed_decision_source_audit.csv'));

intensityTbl=readtable(matrixFiles(1)); locationTbl=readtable(matrixFiles(2));
lfwTbl=readtable(matrixFiles(3));
PA=build_transition_matrix(intensityTbl,'from_a','to_a',(1:6).');
locStates=(-2:10).'; PLoc=build_transition_matrix(locationTbl, ...
    'from_loc_id','to_loc_id',locStates);
lfwStates=(0:3).'; PLfw=build_transition_matrix(lfwTbl, ...
    'from_lfw','to_lfw',lfwStates);

namespace = "independent-path-C2"; datasetIds=(1:3).'; R=15000;
pathSeeds=zeros(3,1); windSeeds=zeros(3,1); resistanceSeeds=zeros(3,1);
for dd=1:3
    pathSeeds(dd)=derive_seed(namespace,dd,"path");
    windSeeds(dd)=derive_seed(namespace,dd,"wind");
    resistanceSeeds(dd)=derive_seed(namespace,dd,"resistance");
end
expectedSeedMatrix=[98661732,59333257,1707588495; ...
    341739613,1254046069,1872944571; ...
    1766178367,619431891,538665406];
if ~isequal([pathSeeds,windSeeds,resistanceSeeds],expectedSeedMatrix)
    error('Deterministic C2 seed derivation does not match the pre-run freeze.');
end

[seedAudit,allSeedPass]=audit_seeds(namespace,pathSeeds, ...
    windSeeds,resistanceSeeds,mainPathFile,seedMapFile,a2ManifestFile);
writetable(seedAudit,fullfile(workDir,'independent_seed_and_collision_audit.csv'));
if ~allSeedPass, error('C2 random-stream collision audit failed.'); end

nominalRaw=readtable(mainPathFile);
nominal=nominalRaw(double(nominalRaw.a0)==4 & double(nominalRaw.loc0)==5 & ...
    double(nominalRaw.lfw0)==0,:); clear nominalRaw;
if height(nominal)~=R || any(double(nominal.derived_seed)~=20279706)
    error('Accepted nominal state19 path gate failed.');
end
nominalKey=[double(nominal.a_W1),double(nominal.loc_W1),double(nominal.lfw_W1), ...
    double(nominal.a_W2),double(nominal.loc_W2),double(nominal.lfw_W2), ...
    double(nominal.a_W3),double(nominal.loc_W3),double(nominal.lfw_W3)];
clear nominal;

A2=load(a2MatFile,'identity'); a2Identity=A2.identity; clear A2;
a2Mask=double(a2Identity.a0)==4 & double(a2Identity.loc0)==5 & ...
    double(a2Identity.lfw0)==0;
a2Identity=a2Identity(a2Mask,:);
[~,firstA2]=unique(double(a2Identity.unique_path_id),'stable');
a2Paths=a2Identity(firstA2,:);
if height(a2Paths)~=27, error('State19 A2 path gate failed.'); end
a2Key=identity_key(a2Paths); clear a2Identity a2Paths;

pathKeys=cell(3,1); pathHashes=strings(3,1); datasetMatPaths=strings(3,1);
datasetMatBytes=zeros(3,1); datasetMatHashes=strings(3,1);
fullDHash=strings(3,1); fullAHash=strings(3,1); fullCHash=strings(3,1);
fullWindHash=strings(3,1); fullFailedHash=strings(3,1); fullClosedHash=strings(3,1);
scenarioSequenceHash=strings(3,1); damageSequenceHash=strings(3,1);
reproRows=cell(3,15); generationRuntime=zeros(3,1);

for dd=1:3
    fprintf('STEP04CC2_PREPARE_DATASET_START|dataset=%d|R=%d\n',dd,R);
    datasetStarted=tic;
    identity1=make_identity(dd,R,namespace,pathSeeds(dd),windSeeds(dd), ...
        resistanceSeeds(dd),PA,PLoc,PLfw,locStates,lfwStates);
    identity2=make_identity(dd,R,namespace,pathSeeds(dd),windSeeds(dd), ...
        resistanceSeeds(dd),PA,PLoc,PLfw,locStates,lfwStates);
    pathHash1=sha256_double(identity_key(identity1));
    pathHash2=sha256_double(identity_key(identity2));
    pathReplayPass=pathHash1==pathHash2 && isequal(identity_key(identity1),identity_key(identity2));
    if ~pathReplayPass, error('Dataset %d path reproducibility failed.',dd); end
    pathKeys{dd}=identity_key(identity1); pathHashes(dd)=pathHash1;

    formal1=generate_step04CA2_formal_consequences_h2(rootDir,identity1);
    firstHashes=collect_formal_hashes(formal1);
    firstScenarioHash=sha256_strings(formal1.scenario_sha256);
    firstDamageHash=sha256_strings(formal1.damage_sha256);
    matPath=fullfile(workDir,sprintf('independent_dataset_%03d.mat',dd));
    if isfile(matPath), error('Refusing to overwrite %s.',matPath); end
    identity=formal1.identity; Dperiod=formal1.Dperiod; Aperiod=formal1.Aperiod;
    Cperiod=formal1.Cperiod; failed_line=formal1.failed_line;
    closed_road=formal1.closed_road; wind_mps=formal1.wind_mps; wind_q=formal1.wind_q;
    scenario_sha256=formal1.scenario_sha256; damage_sha256=formal1.damage_sha256;
    line_resistance_u=formal1.line_resistance_u; road_resistance_u=formal1.road_resistance_u;
    save(matPath,'identity','Dperiod','Aperiod','Cperiod','failed_line', ...
        'closed_road','wind_mps','wind_q','scenario_sha256','damage_sha256', ...
        'line_resistance_u','road_resistance_u','-v7.3');
    clear identity Dperiod Aperiod Cperiod failed_line closed_road wind_mps wind_q ...
        scenario_sha256 damage_sha256 line_resistance_u road_resistance_u formal1;

    formal2=generate_step04CA2_formal_consequences_h2(rootDir,identity2);
    secondHashes=collect_formal_hashes(formal2);
    secondScenarioHash=sha256_strings(formal2.scenario_sha256);
    secondDamageHash=sha256_strings(formal2.damage_sha256);
    formalReplayPass=all(firstHashes==secondHashes) && ...
        firstScenarioHash==secondScenarioHash && firstDamageHash==secondDamageHash;
    if ~formalReplayPass, error('Dataset %d formal consequence reproducibility failed.',dd); end
    clear formal2 identity1 identity2;

    info=dir(matPath); datasetMatPaths(dd)=string(matPath); datasetMatBytes(dd)=info.bytes;
    datasetMatHashes(dd)=sha256_file(matPath);
    fullDHash(dd)=firstHashes(1); fullAHash(dd)=firstHashes(2); fullCHash(dd)=firstHashes(3);
    fullFailedHash(dd)=firstHashes(4); fullClosedHash(dd)=firstHashes(5); fullWindHash(dd)=firstHashes(6);
    scenarioSequenceHash(dd)=firstScenarioHash; damageSequenceHash(dd)=firstDamageHash;
    generationRuntime(dd)=toc(datasetStarted);
    reproRows(dd,:)={dd,pathHash1,pathHash2,pathReplayPass,firstHashes(1),secondHashes(1), ...
        firstHashes(2),secondHashes(2),firstHashes(3),secondHashes(3), ...
        firstScenarioHash,secondScenarioHash,firstDamageHash,secondDamageHash,formalReplayPass};
    fprintf('STEP04CC2_PREPARE_DATASET_COMPLETE|dataset=%d|runtime=%.3f\n', ...
        dd,generationRuntime(dd));
end

repro=cell2table(reproRows,'VariableNames',{'dataset_id','path_hash_first', ...
    'path_hash_replay','path_replay_pass','D_hash_first','D_hash_replay', ...
    'A_hash_first','A_hash_replay','C_hash_first','C_hash_replay', ...
    'scenario_sequence_hash_first','scenario_sequence_hash_replay', ...
    'damage_sequence_hash_first','damage_sequence_hash_replay','formal_replay_pass'});
writetable(repro,fullfile(workDir,'independent_reproducibility_audit.csv'));

overlap=audit_path_overlap(pathKeys,nominalKey,a2Key);
writetable(overlap,fullfile(workDir,'independent_path_overlap_audit.csv'));
if any(overlap.exact_whole_batch_reuse) || any(pathHashes==sha256_double(nominalKey)) || ...
        numel(unique(pathHashes))~=3
    error('Independent path whole-batch reuse/hash separation gate failed.');
end

datasetRole="independent-path-C2-dataset-"+string(datasetIds);
sampleCount=repmat(R,3,1); sampleWeight=repmat(1/R,3,1);
weightSum=sampleCount.*sampleWeight;
manifest=table(datasetIds,datasetRole,repmat(namespace,3,1),pathSeeds,windSeeds, ...
    resistanceSeeds,sampleCount,sampleWeight,weightSum,pathHashes,fullDHash, ...
    fullAHash,fullCHash,fullWindHash,fullFailedHash,fullClosedHash, ...
    scenarioSequenceHash,damageSequenceHash,datasetMatPaths,datasetMatBytes, ...
    datasetMatHashes,generationRuntime,repmat(string(actualHashes(1)),3,1), ...
    'VariableNames',{'dataset_id','dataset_role','namespace','path_seed', ...
    'wind_seed','resistance_seed','sample_count','sample_weight','weight_sum', ...
    'physical_path_sequence_sha256','full_D_sha256','full_A_sha256','full_C_sha256', ...
    'full_wind_sha256','full_failed_line_sha256','full_closed_road_sha256', ...
    'scenario_hash_sequence_sha256','damage_hash_sequence_sha256','local_mat_path', ...
    'local_mat_bytes','local_mat_sha256','generation_and_replay_runtime_sec', ...
    'C1_eta_full_results_sha256'});
writetable(manifest,fullfile(workDir,'independent_dataset_manifest.csv'));

pass = all(hashPass) && allSeedPass && all(repro.path_replay_pass) && ...
    all(repro.formal_replay_pass) && all(abs(weightSum-1)<=1e-14) && ...
    all(overlap.exact_whole_batch_reuse==0) && numel(unique(pathHashes))==3;
fid=fopen(fullfile(workDir,'prepare_mechanical_audit.txt'),'w');
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'status=%s\nnamespace=%s\nstate_id=19\ndataset_count=3\n',pass_fail(pass),namespace);
fprintf(fid,'rows_per_dataset=15000\nsample_weight=%.17g\nweight_sum_each=1\n',1/R);
fprintf(fid,'C1_decisions_read_directly=1\nTerminalLOH_optimized_on_C2=0\n');
fprintf(fid,'path_seed_collision_count=0\nwind_seed_collision_count=0\nresistance_seed_collision_count=0\n');
fprintf(fid,'exact_nominal_batch_reuse_count=0\npath_sequence_hashes_distinct=1\n');
fprintf(fid,'reproducibility_pass=1\ntransition_probability_perturbed=0\n');
fprintf(fid,'old_WDRO_called=0\nchi2_probability_adversary_called=0\nextreme_aware_solver_called=0\nMSP_called=0\n');
if ~pass, error('Step-04C-C2 preparation mechanical audit failed.'); end
fprintf('STEP04CC2_PREPARE_COMPLETE|datasets=3|R=15000|runtime=%.3f\n',toc(started));
end

function decisions=read_frozen_decisions(c1File)
t=readtable(c1File); etaWanted=[0;0.003;0.01]; labels=["SAA";"ETA_0.003";"ETA_0.01"];
rows=zeros(3,1);
for ii=1:3
    hit=find(abs(double(t.eta)-etaWanted(ii))<=1e-14);
    if numel(hit)~=1,error('C1 eta %.12g row is missing or duplicated.',etaWanted(ii));end
    rows(ii)=hit;
end
s=t(rows,:); expected=[294.589913536808,138.832065024684,93.0093009300931,150; ...
    299.211738691929,137.483280118695,94.3580963878466,150; ...
    300,143.468150246686,100,150];
T=[s.T1_kg,s.T2_kg,s.T3_kg,s.T4_kg]; sourceError=max(abs(T-expected),[],2);
if any(sourceError>1e-10)||any(string(s.solver_status)~="OPTIMAL")|| ...
        any(string(s.audit_status)~="PASS")||any(~logical(s.case_pass))
    error('C1 frozen decision source audit failed.');
end
decisions=table((1:3).',labels,etaWanted,T(:,1),T(:,2),T(:,3),T(:,4),sum(T,2), ...
    s.T1_capacity_binding,s.T2_capacity_binding,s.T3_capacity_binding, ...
    s.T4_capacity_binding,s.capacity_binding_count,sourceError, ...
    repmat(string(c1File),3,1),repmat("C1_NOMINAL_OPTIMIZATION_FIXED_FOR_C2",3,1), ...
    'VariableNames',{'decision_id','decision_label','eta','T1_kg','T2_kg','T3_kg', ...
    'T4_kg','TerminalLOH_total_kg','T1_capacity_binding','T2_capacity_binding', ...
    'T3_capacity_binding','T4_capacity_binding','capacity_binding_count', ...
    'source_max_abs_error','source_file','C2_usage'});
end

function identity=make_identity(datasetId,R,namespace,pathSeed,windSeed,resistanceSeed,PA,PLoc,PLfw,locStates,lfwStates)
rng(pathSeed,'twister');
aPath=sample_chain(PA,4,rand(R,3));
locPath=sample_chain(PLoc,5-locStates(1)+1,rand(R,3));
lfwPath=sample_chain(PLfw,1,rand(R,3));
probability=path_probability(PA,PLoc,PLfw,4,5-locStates(1)+1,1,aPath,locPath,lfwPath);
scenarioId=(1:R).';
identity=table(repmat(datasetId,R,1),repmat(namespace,R,1),scenarioId, ...
    repmat(4,R,1),repmat(5,R,1),zeros(R,1), ...
    aPath(:,1),locStates(locPath(:,1)),lfwStates(lfwPath(:,1)), ...
    aPath(:,2),locStates(locPath(:,2)),lfwStates(lfwPath(:,2)), ...
    aPath(:,3),locStates(locPath(:,3)),lfwStates(lfwPath(:,3)), ...
    repmat(pathSeed,R,1),repmat(windSeed,R,1),scenarioId, ...
    repmat(resistanceSeed,R,1),scenarioId, ...
    repmat("namespace_direct_position",R,1),probability,repmat(1/R,R,1), ...
    'VariableNames',{'dataset_id','namespace','scenario_id','a0','loc0','lfw0', ...
    'a1','loc1','lfw1','a2','loc2','lfw2','a3','loc3','lfw3','path_seed', ...
    'wind_seed','wind_stream_position','resistance_seed', ...
    'resistance_stream_position','resistance_stream_rule', ...
    'physical_path_probability','sample_weight'});
end

function [audit,pass]=audit_seeds(namespace,pathSeeds,windSeeds,resistanceSeeds,mainPathFile,seedMapFile,a2ManifestFile)
main=readtable(mainPathFile); stepJ=readtable(seedMapFile); a2=readtable(a2ManifestFile);
historicalPath=unique([double(main.base_random_seed);double(main.derived_seed); ...
    (20260721:20260725).';reshape((20260721:20260725)+1000*(1:35).',[],1)]);
historicalWind=unique([double(stepJ.base_joint_seed);double(stepJ.wind_seed);double(a2.wind_seed)]);
historicalResistance=unique([double(stepJ.base_joint_seed);double(stepJ.resistance_seed);double(a2.resistance_seed)]);
historicalAll=unique([historicalPath;historicalWind;historicalResistance]);
allC2=[pathSeeds;windSeeds;resistanceSeeds]; rows=cell(9,12); rr=0;
for dd=1:3
    for ss=1:3
        rr=rr+1; types=["path","wind","resistance"]; seeds=[pathSeeds(dd),windSeeds(dd),resistanceSeeds(dd)];
        seed=seeds(ss); type=types(ss);
        if type=="path"
            sameHistorical=sum(historicalPath==seed);
        elseif type=="wind"
            sameHistorical=sum(historicalWind==seed);
        else
            sameHistorical=sum(historicalResistance==seed);
        end
        internal=sum(allC2==seed)-1; anyHistorical=sum(historicalAll==seed);
        text=namespace+"|dataset_id="+dd+"|stream="+type;
        status=pass_fail(internal==0&&sameHistorical==0&&anyHistorical==0);
        rows(rr,:)={dd,namespace,type,text,seed,1,15000,internal,sameHistorical, ...
            anyHistorical,"historical main/convergence + Step03J + Step04CA2",status};
    end
end
audit=cell2table(rows,'VariableNames',{'dataset_id','namespace','stream_type', ...
    'derivation_text','seed','stream_position_start','stream_position_end', ...
    'C2_internal_collision_count','same_stream_historical_collision_count', ...
    'any_historical_seed_collision_count','historical_scope','status'});
pass=all(audit.status=="PASS");
end

function overlap=audit_path_overlap(pathKeys,nominalKey,a2Key)
rows=cell(9,12); rr=0;
for dd=1:3
    rr=rr+1; rows(rr,:)=comparison_row("C2_vs_nominal",dd,0,pathKeys{dd},nominalKey,true);
end
for pair=[1,2;1,3;2,3].'
    rr=rr+1; rows(rr,:)=comparison_row("C2_pairwise",pair(1),pair(2),pathKeys{pair(1)},pathKeys{pair(2)},true);
end
for dd=1:3
    rr=rr+1; rows(rr,:)=comparison_row("C2_vs_A2_state19_pressure_paths",dd,0,pathKeys{dd},a2Key,false);
end
rows=rows(1:rr,:);
overlap=cell2table(rows,'VariableNames',{'comparison_type','left_dataset_id', ...
    'right_dataset_id','left_row_count','right_row_count','same_row_position_count', ...
    'same_row_position_share','exact_whole_batch_reuse','left_unique_path_count', ...
    'right_unique_path_count','unique_path_overlap_count', ...
    'left_rows_whose_path_occurs_in_right_share'});
end

function row=comparison_row(type,leftId,rightId,left,right,positionComparable)
leftText=path_text(left); rightText=path_text(right);
if positionComparable&&size(left,1)==size(right,1),same=sum(all(left==right,2));else,same=0;end
exact=positionComparable&&isequal(left,right); ul=unique(leftText); ur=unique(rightText);
intersection=intersect(ul,ur); share=mean(ismember(leftText,ur));
row={type,leftId,rightId,size(left,1),size(right,1),same,same/size(left,1), ...
    exact,numel(ul),numel(ur),numel(intersection),share};
end

function key=identity_key(identity)
key=[double(identity.a1),double(identity.loc1),double(identity.lfw1), ...
    double(identity.a2),double(identity.loc2),double(identity.lfw2), ...
    double(identity.a3),double(identity.loc3),double(identity.lfw3)];
end
function text=path_text(key)
text=compose('%d|%d|%d|%d|%d|%d|%d|%d|%d',key(:,1),key(:,2),key(:,3), ...
    key(:,4),key(:,5),key(:,6),key(:,7),key(:,8),key(:,9));
end
function P=build_transition_matrix(tbl,fromName,toName,states)
P=zeros(numel(states),numel(states));
for ii=1:height(tbl)
    from=find(states==double(tbl.(fromName)(ii)),1); to=find(states==double(tbl.(toName)(ii)),1);
    if isempty(from)||isempty(to),error('Transition table contains unknown state.');end
    P(from,to)=P(from,to)+double(tbl.prob(ii));
end
if max(abs(sum(P,2)-1))>1e-10||any(P<0,'all'),error('Transition matrix audit failed.');end
end
function paths=sample_chain(P,initialIndex,uniforms)
[N,W]=size(uniforms);paths=zeros(N,W);current=repmat(initialIndex,N,1);
for ss=1:W
    next=zeros(N,1);
    for state=1:size(P,1)
        mask=current==state;if any(mask),cdf=cumsum(P(state,:));cdf(end)=1;next(mask)=sum(uniforms(mask,ss)>cdf,2)+1;end
    end
    paths(:,ss)=next;current=next;
end
end
function probability=path_probability(PA,PLoc,PLfw,a0,loc0,lfw0,aPath,locPath,lfwPath)
N=size(aPath,1);probability=ones(N,1);ca=repmat(a0,N,1);cl=repmat(loc0,N,1);cf=repmat(lfw0,N,1);
for ss=1:3
    probability=probability.*PA(sub2ind(size(PA),ca,aPath(:,ss))).* ...
        PLoc(sub2ind(size(PLoc),cl,locPath(:,ss))).*PLfw(sub2ind(size(PLfw),cf,lfwPath(:,ss)));
    ca=aPath(:,ss);cl=locPath(:,ss);cf=lfwPath(:,ss);
end
end
function seed=derive_seed(namespace,datasetId,stream)
text=namespace+"|dataset_id="+datasetId+"|stream="+stream;
md=java.security.MessageDigest.getInstance('SHA-256');md.update(typecast(unicode2native(char(text),'UTF-8'),'int8'));
digest=typecast(md.digest(),'uint8');hex=lower(string(reshape(dec2hex(digest,2).',1,[])));
seed=mod(hex2dec(extractBetween(hex,1,8)),2147483646)+1;
end
function hashes=collect_formal_hashes(f)
hashes=[string(f.full_D_sha256),string(f.full_A_sha256),string(f.full_C_sha256), ...
    string(f.full_failed_line_sha256),string(f.full_closed_road_sha256),string(f.full_wind_sha256)];
end
function hash=sha256_strings(values)
bytes=unicode2native(char(join(string(values),newline)),'UTF-8');
md=java.security.MessageDigest.getInstance('SHA-256');md.update(typecast(bytes,'int8'));hash=digest_text(md);
end
function hash=sha256_double(x)
md=java.security.MessageDigest.getInstance('SHA-256');bytes=typecast(double(x(:)),'uint8');
md.update(typecast(bytes,'int8'));hash=digest_text(md);
end
function hash=sha256_file(fileName)
fid=fopen(fileName,'rb');if fid<0,error('Could not open %s.',fileName);end
cleanup=onCleanup(@()fclose(fid));md=java.security.MessageDigest.getInstance('SHA-256');
while true,bytes=fread(fid,1024*1024,'*uint8');if isempty(bytes),break;end;md.update(typecast(bytes,'int8'));end
hash=digest_text(md);
end
function hash=digest_text(md),digest=typecast(md.digest(),'uint8');hash=lower(string(reshape(dec2hex(digest,2).',1,[])));end
function value=pass_fail(passed),if passed,value="PASS";else,value="FAIL";end,end
function assert_git_gate(expectedBranch,expectedHead)
[s1,b]=system('git branch --show-current');[s2,h]=system('git rev-parse HEAD');[s3,u]=system('git rev-parse @{upstream}');
if s1~=0||s2~=0||s3~=0||strtrim(string(b))~=expectedBranch||strtrim(string(h))~=expectedHead||strtrim(string(u))~=expectedHead
    error('Step-04C-C2 preparation Git gate failed.');
end
end
