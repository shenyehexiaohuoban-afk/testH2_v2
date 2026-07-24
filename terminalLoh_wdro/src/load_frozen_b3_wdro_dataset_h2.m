function [samples,metadata]=load_frozen_b3_wdro_dataset_h2( ...
    scenarioCsv,dacMat,a0,loc0,lfw0)
%LOAD_FROZEN_B3_WDRO_DATASET_H2 Restore the existing WDRO D/A/C array contract.

if ~isfile(scenarioCsv)||~isfile(dacMat)
    error('Frozen WDRO scenario CSV or DAC sidecar is missing.');
end
metadata=readtable(scenarioCsv,'TextType','string');
required={'a0','loc0','lfw0','path_id','sample_weight','dataset_role', ...
    'D_Hres3h_total_kg','A_reachable_share','C_reachable_mean_km'};
for ii=1:numel(required)
    if ~ismember(required{ii},metadata.Properties.VariableNames)
        error('Frozen WDRO CSV is missing %s.',required{ii});
    end
end
mask=double(metadata.a0)==a0&double(metadata.loc0)==loc0&double(metadata.lfw0)==lfw0;
rows=find(mask);metadata=metadata(mask,:);
if height(metadata)~=15000,error('Requested initial state must contain 15000 rows.');end
if abs(sum(double(metadata.sample_weight))-1)>1e-12
    error('Requested initial-state weights do not sum to one.');
end

m=matfile(dacMat);
info=whos(m);names=string({info.name});
for name=["D_node_kg","A_site_node","C_site_node_km","path_id","initial_state_id"]
    if ~ismember(name,names),error('DAC sidecar is missing %s.',name);end
end
D=double(m.D_node_kg(rows,:));
A=double(m.A_site_node(rows,:,:));
C=double(m.C_site_node_km(rows,:,:));
sidecarPathId=double(m.path_id(rows,1));
sidecarStateId=double(m.initial_state_id(rows,1));
if size(D,2)~=33||size(A,2)~=4||size(A,3)~=33||~isequal(size(A),size(C))
    error('Frozen DAC sidecar does not match the existing 4-site 33-node contract.');
end
if any(D<0,'all')||any(~ismember(unique(A),[0;1]))|| ...
        any(~isfinite(C(A>0.5)))
    error('Frozen D/A/C arrays violate WDRO input domains.');
end
if ~isequal(sidecarPathId,double(metadata.path_id))|| ...
        any(sidecarStateId~=double(metadata.initial_state_id))
    error('Frozen scenario CSV and DAC sidecar row identities do not match.');
end

samples=struct();samples.scenarioIds=double(metadata.path_id);
samples.siteIds=(1:4).';samples.nodeIds=(1:33).';
samples.R=height(metadata);samples.I=4;samples.N=33;
samples.D=D;samples.A=A;samples.C_raw=C;
samples.sampleWeights=double(metadata.sample_weight);
samples.datasetRole=unique(metadata.dataset_role);
end
