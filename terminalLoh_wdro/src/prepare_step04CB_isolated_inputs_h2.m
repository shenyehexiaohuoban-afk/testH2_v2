function prepare_step04CB_isolated_inputs_h2(workDir)
%PREPARE_STEP04CB_ISOLATED_INPUTS_H2 Freeze shared inputs for isolated cases.

started=tic;workDir=string(workDir);thisDir=fileparts(mfilename('fullpath'));
moduleDir=fileparts(thisDir);rootDir=fileparts(moduleDir);
addpath(rootDir);addpath(thisDir);add_gurobi_path();
assert_git_gate("task/002-stage2b-b3-smoke", ...
    "2661960674675b2b15c9ca81cf1827d0dd0df1f6");
if ~isfolder(workDir),mkdir(workDir);end
diaryFile=fullfile(workDir,'prepare_matlab_diary.txt');diary(diaryFile);cleanupDiary=onCleanup(@()diary('off')); %#ok<NASGU>

a2Dir=fullfile(rootDir,'results','task-002-stage2b-b3-smoke', ...
    '44-extreme-formal-consequence-freeze','run-003');
a2Mat=fullfile(a2Dir,'extreme_formal_DAC_and_damage.mat');
step04BFile=fullfile(rootDir,'results','task-002-stage2b-b3-smoke', ...
    '42-flat-chi2-dro-production-solver','run-003','saa_vs_dro_terminalLOH.csv');
if ~isfile(a2Mat)||~isfile(step04BFile),error('Required frozen Step-04B/A2 input is missing.');end

fprintf('PREPARE_STEP04CB|recover_state19_nominal_R15000\n');
[nominal,context]=recover_step03Y_prefix_entries_h2(rootDir,19,15000,false);
if ~nominal.audit.all_final_DAC_exact||~nominal.audit.all_stream_hashes_match||nominal.audit.max_DAC_error~=0
    error('Frozen nominal state19 replay failed.');
end
aggregation=aggregate_exact_period_scenarios_h2(nominal.Dperiod,nominal.Aperiod,nominal.Cperiod);

fprintf('PREPARE_STEP04CB|load_state19_extreme_subset\n');
S=load(a2Mat,'identity','Dperiod','Aperiod','Cperiod');
state19Mask=double(S.identity.a0)==4&double(S.identity.loc0)==5&double(S.identity.lfw0)==0;
extIdentity=S.identity(state19Mask,:);Dext=S.Dperiod(state19Mask,:,:);
Aext=S.Aperiod(state19Mask,:,:,:);Cext=S.Cperiod(state19Mask,:,:,:);clear S;
pathId=double(extIdentity.unique_path_id);replicaRank=double(extIdentity.consequence_replica_rank);
pathValues=unique(pathId,'sorted');[~,~,pathGroup]=unique(pathId,'sorted');
replicaCounts=accumarray(pathGroup,1);nPaths=numel(pathValues);nReplicas=numel(pathId);
if nPaths~=27||nReplicas~=135||any(replicaCounts~=5)|| ...
        any(double(extIdentity.a0)~=4)||any(double(extIdentity.loc0)~=5)||any(double(extIdentity.lfw0)~=0)
    error('State19-only extreme identity gate failed.');
end
k5=max(1,ceil(0.05*nPaths));k10=max(1,ceil(0.10*nPaths));

baseTable=readtable(step04BFile);baseRow=baseTable(baseTable.initial_state_id==19& ...
    baseTable.R==15000&abs(baseTable.eta-0.01)<1e-12,:);
if height(baseRow)~=1,error('Formal Step-04B state19 baseline is missing.');end
baseT=[baseRow.SAA_T1_kg,baseRow.SAA_T2_kg,baseRow.SAA_T3_kg,baseRow.SAA_T4_kg; ...
    baseRow.DRO_T1_kg,baseRow.DRO_T2_kg,baseRow.DRO_T3_kg,baseRow.DRO_T4_kg];
Cap=context.Cap(:).';M=context.M;gamma=context.gamma;q=aggregation.nominal_probability;
if max(abs(Cap-[300,200,100,150]))>1e-12,error('Formal capacity trace failed.');end

etas=[0,0.01];design=["R1_MAX","R2_TOPK_5PCT","R2_TOPK_10PCT"];
riskType=["R1_MAX","R2_TOPK","R2_TOPK"];topKs=[1,k5,k10];
kappas=[0,0.001,0.005,0.01,0.05];baseJ=zeros(2,1);baseR=zeros(2,3);
solverConfig=struct('gurobiOutputFlag',0,'gurobiFeasibilityTol',1e-9, ...
    'gurobiOptimalityTol',1e-9,'gurobiThreads',1,'objectiveScale',1e5, ...
    'gurobiTimeLimit',1800);
fprintf('PREPARE_STEP04CB|compute_beta_scales\n');
for ee=1:2
    T=baseT(ee,:);
    nom=evaluate_terminal_loh_period_fixed_T_sparse_h2(aggregation.Dperiod, ...
        aggregation.Aperiod,aggregation.Cperiod,repmat(T,aggregation.group_count,1),M,solverConfig);
    ext=evaluate_terminal_loh_period_fixed_T_sparse_h2(Dext,Aext,Cext,repmat(T,nReplicas,1),M,solverConfig);
    assert_optimal(nom,'baseline nominal');assert_optimal(ext,'baseline extreme');
    baseJ(ee)=gamma*sum(T)+nominal_risk(q,nom.operating_loss,etas(ee));
    for dd=1:3
        baseR(ee,dd)=extreme_risk(ext.operating_loss,pathId,riskType(dd),topKs(dd));
    end
end

betaRows=cell(30,10);row=0;
for ee=1:2
    for dd=1:3
        for kk=1:5
            row=row+1;beta=kappas(kk)*baseJ(ee)/baseR(ee,dd);
            betaRows(row,:)={row,etas(ee),design(dd),riskType(dd),topKs(dd),kappas(kk), ...
                baseJ(ee),baseR(ee,dd),beta,"BEHAVIOR_TEST_NOT_CALIBRATED"};
        end
    end
end
betaScale=cell2table(betaRows,'VariableNames',{'case_id','eta','design','risk_type','top_k', ...
    'kappa','J_base_at_baseline','R_ext_at_baseline','beta_ext','scale_status'});
writetable(betaScale,fullfile(workDir,'beta_scale_design.csv'));

manifest=extIdentity(replicaRank==1,{'unique_path_id','support_out_path_rank', ...
    'a0','loc0','lfw0','a1','loc1','lfw1','a2','loc2','lfw2','a3','loc3','lfw3','path_probability'});
manifest.initial_state_id=19*ones(height(manifest),1);manifest.replica_count=5*ones(height(manifest),1);
manifest=movevars(manifest,{'initial_state_id','replica_count'},'After','support_out_path_rank');
writetable(manifest,fullfile(workDir,'state19_extreme_set_manifest.csv'));

DnomRaw=nominal.Dperiod;AnomRaw=nominal.Aperiod;CnomRaw=nominal.Cperiod;
DnomGroup=aggregation.Dperiod;AnomGroup=aggregation.Aperiod;CnomGroup=aggregation.Cperiod;
nominalGroupId=aggregation.group_id;nominalMultiplicity=aggregation.multiplicity; %#ok<NASGU>
preparedFile=fullfile(workDir,'prepared_inputs.mat');
save(preparedFile,'DnomRaw','AnomRaw','CnomRaw','DnomGroup','AnomGroup','CnomGroup', ...
    'nominalGroupId','nominalMultiplicity','q','Dext','Aext','Cext','extIdentity', ...
    'pathId','replicaRank','Cap','M','gamma','etas','design','riskType','topKs','kappas', ...
    'baseT','baseJ','baseR','nPaths','nReplicas','k5','k10','-v7.3');
info=dir(preparedFile);
summary=table(19,15000,aggregation.group_count,aggregation.hash_collision_split_count, ...
    nPaths,nReplicas,k5,k10,Cap(1),Cap(2),Cap(3),Cap(4),M,gamma,info.bytes,toc(started), ...
    'VariableNames',{'initial_state_id','nominal_R','nominal_exact_group_count', ...
    'hash_collision_split_count','extreme_path_count','extreme_replica_count','topk_5pct', ...
    'topk_10pct','capacity_T1','capacity_T2','capacity_T3','capacity_T4', ...
    'shortage_penalty','gamma','prepared_input_bytes','prepare_runtime_sec'});
writetable(summary,fullfile(workDir,'prepare_summary.csv'));
fid=fopen(fullfile(workDir,'prepare_mechanical_audit.txt'),'w');cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'status=PASS\ninitial_state_id=19\nnominal_R=15000\nnominal_exact_groups=%d\n',aggregation.group_count);
fprintf(fid,'extreme_paths=%d\nextreme_replicas=%d\nreplicas_per_path=5\nother_initial_states=0\n',nPaths,nReplicas);
fprintf(fid,'topk_5pct=%d\ntopk_10pct=%d\nhash_collision_splits=%d\n',k5,k10,aggregation.hash_collision_split_count);
fprintf('PREPARE_STEP04CB_COMPLETE|paths=%d|replicas=%d|groups=%d|runtime=%.3f\n', ...
    nPaths,nReplicas,aggregation.group_count,toc(started));
end

function value=nominal_risk(q,loss,eta)
if eta<=1e-14,value=sum(q.*loss);else,out=solve_flat_chi2_worst_probability_h2(q,loss,eta);value=out.worst_value;end
end

function value=extreme_risk(loss,pathId,riskType,topK)
paths=unique(pathId,'sorted');pathLoss=zeros(numel(paths),1);
for pp=1:numel(paths),pathLoss(pp)=max(loss(pathId==paths(pp)));end
if riskType=="R1_MAX",value=max(pathLoss);else,ordered=sort(pathLoss,'descend');value=mean(ordered(1:topK));end
end

function assert_optimal(out,label)
if out.exitflag~=1,error('%s failed: %s',label,out.status);end
end

function assert_git_gate(expectedBranch,expectedHead)
[s1,b]=system('git branch --show-current');[s2,h]=system('git rev-parse HEAD');[s3,u]=system('git rev-parse @{upstream}');
if s1~=0||s2~=0||s3~=0||strtrim(string(b))~=expectedBranch||strtrim(string(h))~=expectedHead||strtrim(string(u))~=expectedHead
    error('Step-04C-B isolated preparation Git gate failed.');
end
end

function add_gurobi_path()
for candidate={fullfile(getenv('GUROBI_HOME'),'matlab'),'D:\gurobi1201\win64\matlab','C:\gurobi1201\win64\matlab'}
    if ~isempty(candidate{1})&&isfolder(candidate{1}),addpath(candidate{1});end
end
end
