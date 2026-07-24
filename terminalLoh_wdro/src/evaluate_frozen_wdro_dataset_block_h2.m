function result=evaluate_frozen_wdro_dataset_block_h2( ...
    model,stateSample,baseSeed,stateId,windSeedOffset,demandToleranceKg)
%EVALUATE_FROZEN_WDRO_DATASET_BLOCK_H2 Reproduce one Step-03I full block.

nRecords=height(stateSample);
if nRecords~=15000,error('Each initial-state block must contain 15000 records.');end
required={'a0','loc0','lfw0','path_id','a_W1','a_W2','a_W3', ...
    'loc_W1','loc_W2','loc_W3','lfw_W1','lfw_W2','lfw_W3'};
for ii=1:numel(required)
    if ~ismember(required{ii},stateSample.Properties.VariableNames)
        error('State sample is missing %s.',required{ii});
    end
end

resistanceSeed=double(baseSeed)+100003*double(stateId);
rng(resistanceSeed,'twister');
permutation=randperm(nRecords).';
lineU=rand(nRecords,model.nLines);
roadU=rand(nRecords,model.nRoads);
selected=stateSample(permutation,:);

windSeed=double(windSeedOffset)+double(baseSeed)+100019*double(stateId);
windStream=RandStream('mt19937ar','Seed',windSeed);
q=rand(windStream,nRecords,3);

aStage={double(selected.a_W1),double(selected.a_W2),double(selected.a_W3)};
idx=cell(3,1);vmax=cell(3,1);pFail=cell(3,1);pClose=cell(3,1);
idx{1}=state_indices(model,selected.a_W1,selected.loc_W1,selected.lfw_W1);
idx{2}=state_indices(model,selected.a_W2,selected.loc_W2,selected.lfw_W2);
idx{3}=state_indices(model,selected.a_W3,selected.loc_W3,selected.lfw_W3);
windBoundsPass=true;
for ss=1:3
    vmax{ss}=triangular_by_level(aStage{ss},q(:,ss), ...
        model.windLower,model.windModeValues,model.windUpper);
    lower=model.windLower(aStage{ss});upper=model.windUpper(aStage{ss});
    windBoundsPass=windBoundsPass&&all(vmax{ss}>=lower-1e-12&vmax{ss}<=upper+1e-12);
    lineWind=model.lineFactor(idx{ss},:).*vmax{ss};
    roadWind=model.roadFactor(idx{ss},:).*vmax{ss};
    pFail{ss}=compute_line_failure_prob_h2(lineWind,model.designWindSpeedVN);
    pClose{ss}=compute_line_failure_prob_h2(roadWind,model.roadDesignWindVN);
end

failed1=lineU<=pFail{1};failed2=failed1|(lineU<=pFail{2});
failed3=failed2|(lineU<=pFail{3});
outage1=(double(failed1)*model.nodePathIncidence.')>0;
outage2=(double(failed2)*model.nodePathIncidence.')>0;
outage3=(double(failed3)*model.nodePathIncidence.')>0;
outage1(:,model.sourceNode)=false;outage2(:,model.sourceNode)=false;
outage3(:,model.sourceNode)=false;
D1=double(outage1).*model.Pnode_kW.'*model.DFactorKgPerKWh;
D2=double(outage2).*model.Pnode_kW.'*model.DFactorKgPerKWh;
D3=double(outage3).*model.Pnode_kW.'*model.DFactorKgPerKWh;
Dnode=D1+D2+D3;Dtotal=sum(Dnode,2);
fullLoss=abs(Dtotal-model.DUpperKg)<=1e-9;W3Failed=sum(failed3,2);

closed1=roadU<=pClose{1};closed2=closed1|(roadU<=pClose{2});
closed3=closed2|(roadU<=pClose{3});
slow1=pClose{1};slow2=max(slow1,pClose{2});slow3=max(slow2,pClose{3});
W3Closed=sum(closed3,2);

A0StageShare=zeros(nRecords,1);CStageMean=zeros(nRecords,1);
Awdro=false(nRecords,model.nSites,model.nNodes);
Cwdro=inf(nRecords,model.nSites,model.nNodes);
AwdroShare=zeros(nRecords,1);CwdroMean=zeros(nRecords,1);
for rr=1:nRecords
    reachTau=false(3,model.nSites,model.nNodes);
    costTau=inf(3,model.nSites,model.nNodes);
    reachableTotal=0;Csum=0;
    for ss=1:3
        if ss==1,closed=closed1(rr,:).';slow=slow1(rr,:).';
        elseif ss==2,closed=closed2(rr,:).';slow=slow2(rr,:).';
        else,closed=closed3(rr,:).';slow=slow3(rr,:).';end
        edgeCost=model.roadLength.*(1+slow);edgeCost(closed)=Inf;
        [reach,cost]=road_state(model.nNodes,model.roadFrom,model.roadTo, ...
            edgeCost,model.siteNodes);
        reachTau(ss,:,:)=reach;costTau(ss,:,:)=cost;
        reachableTotal=reachableTotal+sum(reach,'all');Csum=Csum+sum(cost(reach));
    end
    A0StageShare(rr)=1-reachableTotal/(3*model.nSites*model.nNodes);
    CStageMean(rr)=Csum/reachableTotal;
    dTau=[D1(rr,:);D2(rr,:);D3(rr,:)];
    Aagg=false(model.nSites,model.nNodes);Cagg=inf(model.nSites,model.nNodes);
    for nn=1:model.nNodes
        critical=find(dTau(:,nn)>demandToleranceKg);
        if isempty(critical),critical=(1:3).';end
        for site=1:model.nSites
            reach=squeeze(reachTau(critical,site,nn));
            if all(reach)
                Aagg(site,nn)=true;
                costs=squeeze(costTau(critical,site,nn));
                if any(~isfinite(costs)),error('Reachable WDRO pair has non-finite cost.');end
                Cagg(site,nn)=mean(costs);
            end
        end
    end
    Awdro(rr,:,:)=Aagg;Cwdro(rr,:,:)=Cagg;
    AwdroShare(rr)=mean(Aagg,'all');CwdroMean(rr)=mean(Cagg(Aagg));
end

scenario=selected;
scenario.initial_state_id=repmat(stateId,nRecords,1);
scenario.initial_state="a0="+string(scenario.a0)+"|loc0="+string(scenario.loc0)+ ...
    "|lfw0="+string(scenario.lfw0);
scenario.joint_stream_position=(1:nRecords).';
scenario.wind_W1_mps=vmax{1};scenario.wind_W2_mps=vmax{2};scenario.wind_W3_mps=vmax{3};
scenario.wind_seed=repmat(windSeed,nRecords,1);
scenario.resistance_seed=repmat(resistanceSeed,nRecords,1);
scenario.D_Hres3h_total_kg=Dtotal;
scenario.A_reachable_share=AwdroShare;
scenario.C_reachable_mean_km=CwdroMean;
scenario.A0_stage_pair_share=A0StageShare;
scenario.C_stage_reachable_mean_km=CStageMean;
scenario.W3_failed_line_count=W3Failed;
scenario.W3_closed_road_count=W3Closed;
scenario.D_upper_bound_hit=fullLoss;
scenario.sample_weight=repmat(1/nRecords,nRecords,1);

metrics=table(mean(Dtotal),pct(Dtotal,95),pct(Dtotal,99),mean(fullLoss), ...
    mean(A0StageShare),1-mean(A0StageShare),mean(CStageMean),pct(CStageMean,95), ...
    mean(W3Failed),pct(W3Failed,95),mean(W3Closed),pct(W3Closed,95), ...
    mean(fullLoss),'VariableNames',{'D_mean_kg','D_q95_kg','D_q99_kg', ...
    'full_loss_probability','A0_pair_share','reachable_pair_share', ...
    'C_reachable_mean_km','C_reachable_q95_km','W3_failed_lines_mean', ...
    'W3_failed_lines_q95','W3_closed_roads_mean','W3_closed_roads_q95', ...
    'D_upper_bound_hit_share'});

result=struct();result.scenario=scenario;
result.D_node_kg=Dnode;result.A_site_node=Awdro;result.C_site_node_km=Cwdro;
result.metrics=metrics;result.resistance_seed=resistanceSeed;result.wind_seed=windSeed;
result.wind_bounds_pass=windBoundsPass;result.a6_upper_pass=all([vmax{1}(aStage{1}==6); ...
    vmax{2}(aStage{2}==6);vmax{3}(aStage{3}==6)]<=60);
result.stagewise_q_pass=~isequal(q(:,1),q(:,2))&&~isequal(q(:,1),q(:,3))&& ...
    ~isequal(q(:,2),q(:,3));
result.domain_pass=all(isfinite(Dnode),'all')&&all(Dnode>=0,'all')&& ...
    all(isfinite(Dtotal))&&all(Dtotal>=0)&&all(isfinite(AwdroShare))&& ...
    all(AwdroShare>=0&AwdroShare<=1)&&all(isfinite(Cwdro(Awdro)))&& ...
    all(Cwdro(Awdro)>=0)&&all(isfinite(CStageMean))&&all(CStageMean>=0);
result.permutation_sha256=sha256_uint32(permutation);
result.path_order_sha256=sha256_uint32(double(selected.path_id));
result.q_W1_sha256=sha256_double(q(:,1));result.q_W2_sha256=sha256_double(q(:,2));
result.q_W3_sha256=sha256_double(q(:,3));
end

function [reach,cost]=road_state(nNodes,fromNode,toNode,edgeCost,sources)
adj=inf(nNodes,nNodes);adj(1:(nNodes+1):end)=0;
for ee=1:numel(edgeCost)
    if ~isfinite(edgeCost(ee)),continue;end
    i=fromNode(ee);j=toNode(ee);
    if edgeCost(ee)<adj(i,j),adj(i,j)=edgeCost(ee);adj(j,i)=edgeCost(ee);end
end
reach=false(numel(sources),nNodes);cost=inf(numel(sources),nNodes);
for ii=1:numel(sources)
    dist=inf(1,nNodes);visited=false(1,nNodes);dist(sources(ii))=0;
    for iter=1:nNodes
        candidate=dist;candidate(visited)=Inf;[best,u]=min(candidate);
        if ~isfinite(best),break;end
        visited(u)=true;dist=min(dist,best+adj(u,:));
    end
    reach(ii,:)=isfinite(dist);cost(ii,:)=dist;
end
end
function vmax=triangular_by_level(a,q,vLow,vMode,vHigh)
a=double(a(:));q=double(q(:));vmax=zeros(size(a));
for level=2:6
    mask=a==level;
    if any(mask),vmax(mask)=triangular_inverse(q(mask),vLow(level),vMode(level),vHigh(level));end
end
end
function x=triangular_inverse(q,a,c,b),fc=(c-a)/(b-a);x=zeros(size(q));left=q<=fc;x(left)=a+sqrt(q(left)*(b-a)*(c-a));x(~left)=b-sqrt((1-q(~left))*(b-a)*(b-c));end
function idx=state_indices(model,a,loc,lfw),a=double(a(:));loc=double(loc(:));lfw=double(lfw(:));linear=sub2ind(size(model.stateIndex),a,loc-model.locMin+1,lfw+1);idx=model.stateIndex(linear);if any(idx<=0),error('Joint state missing from wind cache.');end,end
function value=pct(x,p),x=sort(double(x(:)));x=x(isfinite(x));value=x(max(1,min(numel(x),ceil(p/100*numel(x)))));end
function hash=sha256_uint32(x),md=java.security.MessageDigest.getInstance('SHA-256');bytes=typecast(uint32(x(:)),'uint8');md.update(typecast(bytes,'int8'));digest=typecast(md.digest(),'uint8');hash=lower(string(reshape(dec2hex(digest,2).',1,[])));end
function hash=sha256_double(x),md=java.security.MessageDigest.getInstance('SHA-256');bytes=typecast(double(x(:)),'uint8');md.update(typecast(bytes,'int8'));digest=typecast(md.digest(),'uint8');hash=lower(string(reshape(dec2hex(digest,2).',1,[])));end
