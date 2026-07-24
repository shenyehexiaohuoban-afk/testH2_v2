function result = evaluate_formal_stagewise_b3_stability_block_h2( ...
    model,stateSample,baseSeed,stateId,NValues,evaluationCount,windSeedOffset)
%EVALUATE_FORMAL_STAGEWISE_B3_STABILITY_BLOCK_H2 Evaluate one nested block.

nRecords=height(stateSample);NValues=double(NValues(:).');
if nRecords~=15000||evaluationCount<max(NValues)||evaluationCount>nRecords
    error('State sample must have 15000 rows and cover every requested N.');
end
if model.windMode~="stagewise_random_triangular"
    error('This evaluator requires the formal stagewise_random_triangular mode.');
end
required={'a_W1','a_W2','a_W3','loc_W1','loc_W2','loc_W3', ...
    'lfw_W1','lfw_W2','lfw_W3','path_id'};
for ii=1:numel(required)
    if ~ismember(required{ii},stateSample.Properties.VariableNames)
        error('State sample missing %s.',required{ii});
    end
end

resistanceSeed=double(baseSeed)+100003*double(stateId);
rng(resistanceSeed,'twister');
permutation=randperm(nRecords).';
fixedLineU=rand(nRecords,model.nLines);
fixedRoadU=rand(nRecords,model.nRoads);
selected=stateSample(permutation(1:evaluationCount),:);
lineU=fixedLineU(1:evaluationCount,:);roadU=fixedRoadU(1:evaluationCount,:);

windSeed=double(windSeedOffset)+double(baseSeed)+100019*double(stateId);
windStream=RandStream('mt19937ar','Seed',windSeed);
qAll=rand(windStream,nRecords,3);q=qAll(1:evaluationCount,:);
replayStream=RandStream('mt19937ar','Seed',windSeed);
qReplay=rand(replayStream,nRecords,3);

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
P1=double(outage1)*model.Pnode_kW;P2=double(outage2)*model.Pnode_kW;
P3=double(outage3)*model.Pnode_kW;
Dtotal=(P1+P2+P3)*model.DFactorKgPerKWh;
fullLoss=abs(Dtotal-model.DUpperKg)<=1e-9;W3Failed=sum(failed3,2);

closed1=roadU<=pClose{1};closed2=closed1|(roadU<=pClose{2});
closed3=closed2|(roadU<=pClose{3});
slow1=pClose{1};slow2=max(slow1,pClose{2});slow3=max(slow2,pClose{3});
W3Closed=sum(closed3,2);

A0Share=zeros(evaluationCount,1);reachableShare=zeros(evaluationCount,1);
CScenarioMean=zeros(evaluationCount,1);invalidA=0;invalidC=0;
for rr=1:evaluationCount
    unreachableTotal=0;reachableTotal=0;Csum=0;
    for ss=1:3
        if ss==1,closed=closed1(rr,:).';slow=slow1(rr,:).';
        elseif ss==2,closed=closed2(rr,:).';slow=slow2(rr,:).';
        else,closed=closed3(rr,:).';slow=slow3(rr,:).';end
        edgeCost=model.roadLength.*(1+slow);edgeCost(closed)=Inf;
        [reachableCount,stageCsum,stageInvalid]=road_metrics( ...
            model.nNodes,model.roadFrom,model.roadTo,edgeCost,model.siteNodes);
        invalidC=invalidC+stageInvalid;reachableTotal=reachableTotal+reachableCount;
        unreachableTotal=unreachableTotal+(model.nSites*model.nNodes-reachableCount);
        Csum=Csum+stageCsum;
    end
    pairTotal=3*model.nSites*model.nNodes;
    A0Share(rr)=unreachableTotal/pairTotal;reachableShare(rr)=reachableTotal/pairTotal;
    if reachableTotal<=0,invalidA=invalidA+1;CScenarioMean(rr)=NaN;
    else,CScenarioMean(rr)=Csum/reachableTotal;end
end

metricsRows=cell(numel(NValues),26);designRows=cell(numel(NValues),24);
for nn=1:numel(NValues)
    N=NValues(nn);prefix=1:N;
    metricsRows(nn,:)={N,mean(Dtotal(prefix)),pct(Dtotal(prefix),95), ...
        pct(Dtotal(prefix),99),mean(fullLoss(prefix)),mean(fullLoss(prefix)), ...
        mean(A0Share(prefix)),mean(reachableShare(prefix)), ...
        mean(CScenarioMean(prefix)),pct(CScenarioMean(prefix),95), ...
        mean(W3Failed(prefix)),pct(W3Failed(prefix),95),mean(W3Closed(prefix)), ...
        pct(W3Closed(prefix),95),min(Dtotal(prefix)),max(Dtotal(prefix)), ...
        min(A0Share(prefix)),max(A0Share(prefix)),min(CScenarioMean(prefix)), ...
        max(CScenarioMean(prefix)),sum(~isfinite(Dtotal(prefix))), ...
        sum(~isfinite(CScenarioMean(prefix))),sum(Dtotal(prefix)<0), ...
        sum(CScenarioMean(prefix)<0),invalidA,invalidC};
    if nn<numel(NValues)
        nestedPass=all(ismember(permutation(1:N),permutation(1:NValues(nn+1))));
        parentN=NValues(nn+1);
    else,nestedPass=true;parentN=NaN;end
    designRows(nn,:)={N,parentN,1,N,1/N,sum(repmat(1/N,N,1)),nestedPass, ...
        resistanceSeed,windSeed,stateId,baseSeed,permutation_checksum(permutation(1:N)), ...
        sha256_uint32(permutation(1:N)),min(permutation(1:N)),max(permutation(1:N)), ...
        numel(unique(permutation(1:N))),sha256_double(q(1:N,1)), ...
        sha256_double(q(1:N,2)),sha256_double(q(1:N,3)),windBoundsPass, ...
        windSeed~=resistanceSeed,"main_sample_record_prefix", ...
        "each selected record has weight 1/N","path_probability_not_reused"};
end
metrics=cell2table(metricsRows,'VariableNames', ...
    {'N','D_mean_kg','D_q95_kg','D_q99_kg','full_loss_probability', ...
    'D_upper_bound_hit_share','A0_pair_share','reachable_pair_share', ...
    'C_reachable_mean_km','C_reachable_q95_km','W3_failed_lines_mean', ...
    'W3_failed_lines_q95','W3_closed_roads_mean','W3_closed_roads_q95', ...
    'D_min_kg','D_max_kg','A0_min','A0_max','C_mean_min_km','C_mean_max_km', ...
    'D_nonfinite_count','C_nonfinite_count','D_negative_count','C_negative_count', ...
    'A_invalid_scenario_count','C_invalid_value_count'});
design=cell2table(designRows,'VariableNames', ...
    {'N','nested_parent_N','prefix_start','prefix_end','record_weight', ...
    'record_weight_sum','nested_in_parent_pass','resistance_seed','wind_seed', ...
    'state_id','base_seed','permutation_checksum','prefix_record_id_sha256', ...
    'selected_record_id_min','selected_record_id_max','selected_record_id_unique_count', ...
    'q_W1_prefix_sha256','q_W2_prefix_sha256','q_W3_prefix_sha256', ...
    'wind_bounds_pass','separate_wind_resistance_seed_pass','sampling_unit', ...
    'weight_definition','path_probability_weighting'});

windByLevel=cell(6,1);
for level=1:6
    values=[];
    for ss=1:3,values=[values;vmax{ss}(aStage{ss}==level)];end %#ok<AGROW>
    windByLevel{level}=values;
end
sameLevelRedrawPass=true;
for ss=1:2
    mask=aStage{ss}==aStage{ss+1}&aStage{ss}>=2;
    sameLevelRedrawPass=sameLevelRedrawPass&&all(q(mask,ss)~=q(mask,ss+1));
end

result=struct();result.metrics=metrics;result.design=design;
result.first_prefix_metric_checksum=metric_checksum(metrics(1,:));
result.evaluated_record_count=evaluationCount;result.resistance_seed=resistanceSeed;
result.derived_seed=resistanceSeed;
result.wind_seed=windSeed;result.wind_values_by_level=windByLevel;
result.wind_bounds_pass=windBoundsPass;
result.a6_upper_pass=all(windByLevel{6}<=60);
result.stagewise_q_pass=~isequal(q(:,1),q(:,2))&&~isequal(q(:,1),q(:,3))&& ...
    ~isequal(q(:,2),q(:,3))&&sameLevelRedrawPass;
result.wind_reproducibility_pass=isequal(qAll,qReplay);
result.separate_seed_pass=windSeed~=resistanceSeed;
end

function vmax=triangular_by_level(a,q,vLow,vMode,vHigh)
a=double(a(:));q=double(q(:));vmax=zeros(size(a));
for level=2:6
    mask=a==level;
    if any(mask),vmax(mask)=triangular_inverse(q(mask),vLow(level),vMode(level),vHigh(level));end
end
end
function x=triangular_inverse(q,a,c,b)
fc=(c-a)/(b-a);x=zeros(size(q));left=q<=fc;
x(left)=a+sqrt(q(left)*(b-a)*(c-a));
x(~left)=b-sqrt((1-q(~left))*(b-a)*(b-c));
end
function idx=state_indices(model,a,loc,lfw)
a=double(a(:));loc=double(loc(:));lfw=double(lfw(:));
if any(a<1|a>6|loc<model.locMin|loc>model.locMax|lfw<0|lfw>3)
    error('Sample contains a joint state outside the accepted support.');
end
linear=sub2ind(size(model.stateIndex),a,loc-model.locMin+1,lfw+1);
idx=model.stateIndex(linear);if any(idx<=0),error('Joint state is absent from wind cache.');end
end
function [reachableCount,Csum,invalidCount]=road_metrics(nNodes,fromNode,toNode,edgeCost,sources)
adj=inf(nNodes,nNodes);adj(1:(nNodes+1):end)=0;
for ee=1:numel(edgeCost)
    if ~isfinite(edgeCost(ee)),continue;end
    i=fromNode(ee);j=toNode(ee);
    if edgeCost(ee)<adj(i,j),adj(i,j)=edgeCost(ee);adj(j,i)=edgeCost(ee);end
end
reachableCount=0;Csum=0;invalidCount=0;
for ii=1:numel(sources)
    dist=inf(1,nNodes);visited=false(1,nNodes);dist(sources(ii))=0;
    for iter=1:nNodes
        candidate=dist;candidate(visited)=Inf;[best,u]=min(candidate);
        if ~isfinite(best),break;end
        visited(u)=true;dist=min(dist,best+adj(u,:));
    end
    finite=isfinite(dist);values=dist(finite);
    if any(values<0|~isfinite(values)),invalidCount=invalidCount+1;end
    reachableCount=reachableCount+sum(finite);Csum=Csum+sum(values);
end
end
function value=pct(x,p),x=sort(double(x(:)));x=x(isfinite(x));if isempty(x),value=NaN;else,value=x(max(1,min(numel(x),ceil(p/100*numel(x)))));end,end
function value=permutation_checksum(x),x=double(x(:));value=sum(x.*(1:numel(x)).');end
function hash=sha256_uint32(x),md=java.security.MessageDigest.getInstance('SHA-256');bytes=typecast(uint32(x(:)),'uint8');md.update(typecast(bytes,'int8'));digest=typecast(md.digest(),'uint8');hash=lower(string(reshape(dec2hex(digest,2).',1,[])));end
function hash=sha256_double(x),md=java.security.MessageDigest.getInstance('SHA-256');bytes=typecast(double(x(:)),'uint8');md.update(typecast(bytes,'int8'));digest=typecast(md.digest(),'uint8');hash=lower(string(reshape(dec2hex(digest,2).',1,[])));end
function value=metric_checksum(T)
names={'D_mean_kg','D_q95_kg','D_q99_kg','full_loss_probability', ...
    'D_upper_bound_hit_share','A0_pair_share','reachable_pair_share', ...
    'C_reachable_mean_km','C_reachable_q95_km','W3_failed_lines_mean', ...
    'W3_closed_roads_mean'};
x=zeros(numel(names),1);for ii=1:numel(names),x(ii)=double(T.(names{ii}));end
value=sum(x.*(1:numel(x)).');
end
