function prepare_step04CC5B_unified_economic_inputs_h2(workDir)
%PREPARE_STEP04CC5B_UNIFIED_ECONOMIC_INPUTS_H2 Read-only frozen-input gate.

started=tic;workDir=string(workDir);
thisDir=fileparts(mfilename('fullpath'));rootDir=fileparts(fileparts(thisDir));
addpath(rootDir);addpath(thisDir);
assert_git_gate("task/002-stage2b-b3-smoke", ...
    "bb298d52ee5143bc2c60e2f2fc1e31e8d1c3d1a2");
if ~isfolder(workDir),mkdir(workDir);end
for name=["effective_electricity_price_audit.csv","unified_parameter_table.csv", ...
        "unified_objective_spec.txt","frozen_input_manifest.csv"]
    if isfile(fullfile(workDir,name)),error('Refusing to overwrite %s.',name);end
end
diary(fullfile(workDir,'prepare_matlab_diary.txt'));
cleanupDiary=onCleanup(@()diary('off')); %#ok<NASGU>

c1=fullfile(rootDir,'results','task-002-stage2b-b3-smoke', ...
    '46-flat-chi2-eta-calibration','run-003');
c2=fullfile(rootDir,'results','task-002-stage2b-b3-smoke', ...
    '47-flat-chi2-independent-path-validation','run-002');
c3=fullfile(rootDir,'results','task-002-stage2b-b3-smoke', ...
    '48-markov-transition-perturbation','run-001');
c4=fullfile(rootDir,'results','task-002-stage2b-b3-smoke', ...
    '49-parameter-provenance-resilience-audit','run-004');
nearFile=fullfile(rootDir,'data','yuanqi','near_stage_msp_input.mat');
c1Prepared=fullfile(c1,'prepared_inputs.mat');
fixedPaths=[string(nearFile);string(c1Prepared); ...
    string(fullfile(c1,'eta_solver_certificate.csv')); ...
    string(fullfile(c2,'fixed_T_process_certificate.csv')); ...
    string(fullfile(c3,'fixed_T_process_certificate.csv')); ...
    string(fullfile(c4,'README.md'))];
fixedLabels=["near_stage_msp_input";"C1_prepared_inputs";"C1_certificate"; ...
    "C2_certificate";"C3_certificate";"C4_accepted_README"];
expected=["536b25868e6d7cc812a331c0d3e0ffbd5f6958e6883bd39bcae3901c372abf24"; ...
    "5914afb37254ae908c5a8b10f24bc0ae01520e56b35b928a1afc13cf4602f19b"; ...
    "63e8b8316aafd73284a087a6af10a5dcf257a87ddf739bf70b4d5171574a3769"; ...
    "";"";"7fb07a03f58108eb9a0222b28a5f0f91ee4f387650d49c64baebdfeb13fe9471"];
actual=strings(size(fixedPaths));bytes=zeros(size(fixedPaths));
for ii=1:numel(fixedPaths)
    if ~isfile(fixedPaths(ii)),error('Missing frozen input: %s',fixedPaths(ii));end
    actual(ii)=sha256_file(fixedPaths(ii));info=dir(fixedPaths(ii));bytes(ii)=info.bytes;
    if strlength(expected(ii))>0&&actual(ii)~=expected(ii)
        error('Frozen input hash mismatch: %s',fixedLabels(ii));
    end
end
for certPath=fixedPaths(3:5).'
    cert=readtable(certPath);
    variableNames=string(cert.Properties.VariableNames);
    passName=variableNames(contains(lower(variableNames),'pass'));
    if isempty(passName)||~all(logical(cert.(passName(end))))
        error('Accepted certificate is not fully PASS: %s',certPath);
    end
end

c2Manifest=readtable(fullfile(c2,'independent_dataset_manifest.csv'));
c3Manifest=readtable(fullfile(c3,'dataset_manifest.csv'));
if height(c2Manifest)~=3||height(c3Manifest)~=21,error('C2/C3 manifest row gate failed.');end
extraPaths=strings(24,1);extraLabels=strings(24,1);extraExpected=strings(24,1);
for ii=1:3
    extraPaths(ii)=string(c2Manifest.local_mat_path(ii));
    extraLabels(ii)="C2_dataset_"+sprintf('%03d',ii);
    extraExpected(ii)=string(c2Manifest.local_mat_sha256(ii));
end
for ii=1:21
    extraPaths(3+ii)=string(c3Manifest.local_mat_path(ii));
    extraLabels(3+ii)="C3_dataset_"+sprintf('%03d',ii);
    extraExpected(3+ii)=string(c3Manifest.local_mat_sha256(ii));
end
extraActual=strings(24,1);extraBytes=zeros(24,1);
for ii=1:24
    if ~isfile(extraPaths(ii)),error('Missing frozen dataset: %s',extraPaths(ii));end
    extraActual(ii)=sha256_file(extraPaths(ii));info=dir(extraPaths(ii));extraBytes(ii)=info.bytes;
    if extraActual(ii)~=extraExpected(ii),error('Frozen dataset hash mismatch: %s',extraLabels(ii));end
end
allLabels=[fixedLabels;extraLabels];allPaths=[fixedPaths;extraPaths];
allBytes=[bytes;extraBytes];allActual=[actual;extraActual];
allExpected=[expected;extraExpected];hashPass=(strlength(allExpected)==0)|(allActual==allExpected);
manifest=table(allLabels,allPaths,allBytes,allActual,allExpected,hashPass, ...
    'VariableNames',{'input_label','path','bytes','sha256','expected_sha256','hash_pass'});
writetable(manifest,fullfile(workDir,'frozen_input_manifest.csv'));

raw=load(nearFile,'NearStageInput');near=raw.NearStageInput;
prices=double(near.Cost.electricity_price_yuan_per_kWh(:));
etaFC=double(near.HydrogenDevice.eta_FC);
lhv=double(near.HydrogenDevice.h2_lhv_kWh_per_kg);
kH2=double(near.HydrogenDevice.k_H2_kg_per_kWh);
if numel(prices)~=24||abs(etaFC-0.55)>1e-14||abs(lhv-33.33)>1e-14|| ...
        abs(kH2-0.0195)>1e-14
    error('Frozen economic/physical parameter gate failed.');
end
averagePrice=mean(prices);sec=1/kH2;cH2=sec*averagePrice;
electricityPerKg=lhv*etaFC;voll=70;shortagePenalty=voll*electricityPerKg;
if abs(shortagePenalty-1283.205)>1e-9,error('VOLL conversion identity failed.');end
priceAudit=table((1:24).',prices,repmat(min(prices),24,1), ...
    repmat(max(prices),24,1),repmat(averagePrice,24,1), ...
    repmat(averagePrice,24,1),repmat("arithmetic_mean_of_live_MSP_24h_vector",24,1), ...
    'VariableNames',{'hour_index','electricity_price_yuan_per_kWh', ...
    'vector_min_yuan_per_kWh','vector_max_yuan_per_kWh', ...
    'arithmetic_mean_yuan_per_kWh','price_used_yuan_per_kWh','selection_rule'});
writetable(priceAudit,fullfile(workDir,'effective_electricity_price_audit.csv'));
parameter=["LHV";"eta_FC";"electricity_per_kg_H2";"k_H2";"SEC_H2"; ...
    "average_electricity_price";"c_H2";"VOLL";"M_H2";"historical_gamma"; ...
    "historical_M"];
value=[lhv;etaFC;electricityPerKg;kH2;sec;averagePrice;cH2;voll; ...
    shortagePenalty;2;2000];
unit=["kWh/kg";"dimensionless";"kWh/kg";"kg/kWh";"kWh/kg"; ...
    "yuan/kWh";"yuan/kg";"yuan/kWh";"yuan/kg-H2"; ...
    "historical_objective_units/kg";"historical_penalty_units/kg"];
role=["active_physical";"active_physical";"active_conversion";"active_MSP_balance"; ...
    "active_derived";"active_live_MSP_price";"active_primary_inventory_cost"; ...
    "user_frozen_literature_benchmark";"active_primary_shortage_penalty"; ...
    "comparison_only";"comparison_only"];
source=["NearStageInput.HydrogenDevice.h2_lhv_kWh_per_kg"; ...
    "NearStageInput.HydrogenDevice.eta_FC";"LHV*eta_FC"; ...
    "NearStageInput.HydrogenDevice.k_H2_kg_per_kWh";"1/k_H2"; ...
    "NearStageInput.Cost.electricity_price_yuan_per_kWh"; ...
    "SEC_H2*average_electricity_price"; ...
    "Wen et al. 2023 DOI 10.19929/j.cnki.nmgdljs.2023.0003"; ...
    "VOLL*LHV*eta_FC";"C1 historical objective";"C1 historical objective"];
params=table(parameter,value,unit,role,source);
writetable(params,fullfile(workDir,'unified_parameter_table.csv'));

fid=fopen(fullfile(workDir,'unified_objective_spec.txt'),'w');cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'status=FROZEN_BEFORE_OPTIMIZATION\nstate_id=19\nR=15000\n');
fprintf(fid,'eta_grid=0,0.003,0.01\nprice_vector_count=24\n');
fprintf(fid,'average_electricity_price_yuan_per_kWh=%.15g\n',averagePrice);
fprintf(fid,'SEC_H2_kWh_per_kg=%.15g\nc_H2_yuan_per_kg=%.15g\n',sec,cH2);
fprintf(fid,'electricity_per_kg_H2_kWh_per_kg=%.15g\nVOLL_yuan_per_kWh=70\n',electricityPerKg);
fprintf(fid,'M_H2_yuan_per_kg=%.15g\n',shortagePenalty);
fprintf(fid,'primary_SAA=c_H2*sum(T)+mean(M_H2*shortage_r(T))\n');
fprintf(fid,'primary_DRO=c_H2*sum(T)+max_p sum(p_r*M_H2*shortage_r(T))\n');
fprintf(fid,'secondary=min sum(C*y) after fixing each scenario primary-optimal shortage exactly\n');
fprintf(fid,'C_y_in_primary_currency_objective=0\nC_y_interpreted_as_transport_cost=0\n');
fprintf(fid,'electrolyzer_efficiency_multiplied_again=0\nO_and_M_included=0\n');
fprintf(fid,'holding_loss_salvage_external_purchase_included=0\nMSP_called=0\n');

summary=table(19,15000,24,min(prices),max(prices),averagePrice,sec,cH2, ...
    shortagePenalty,height(manifest),all(hashPass),toc(started), ...
    'VariableNames',{'initial_state_id','nominal_R','price_count', ...
    'price_min','price_max','price_mean','SEC_H2','c_H2','M_H2', ...
    'frozen_input_count','all_hash_pass','prepare_runtime_sec'});
writetable(summary,fullfile(workDir,'prepare_summary.csv'));
fid2=fopen(fullfile(workDir,'prepare_mechanical_audit.txt'),'w');cleanup2=onCleanup(@()fclose(fid2)); %#ok<NASGU>
fprintf(fid2,'status=PASS\nall_frozen_input_hashes_pass=1\n');
fprintf(fid2,'electricity_price_read_from_live_MSP_vector=1\nprice_count=24\n');
fprintf(fid2,'c_H2=%.15g\nM_H2=%.15g\nC_y_primary=0\nMSP_called=0\n',cH2,shortagePenalty);
fprintf('STEP04CC5B_PREPARE_COMPLETE|cH2=%.12f|M=%.6f|runtime=%.3f\n',cH2,shortagePenalty,toc(started));
end

function assert_git_gate(expectedBranch,expectedHead)
[s1,b]=system('git branch --show-current');[s2,h]=system('git rev-parse HEAD');
[s3,u]=system('git rev-parse @{upstream}');
if s1~=0||s2~=0||s3~=0||strtrim(string(b))~=expectedBranch|| ...
        strtrim(string(h))~=expectedHead||strtrim(string(u))~=expectedHead
    error('Step-04C-C5B frozen Git gate failed.');
end
end

function hash=sha256_file(fileName)
fid=fopen(fileName,'rb');if fid<0,error('Could not open %s.',fileName);end
cleanup=onCleanup(@()fclose(fid));md=java.security.MessageDigest.getInstance('SHA-256');
while true,bytes=fread(fid,1024*1024,'*uint8');if isempty(bytes),break;end;md.update(typecast(bytes,'int8'));end
digest=typecast(md.digest(),'uint8');hash=lower(string(reshape(dec2hex(digest,2).',1,[])));
end
