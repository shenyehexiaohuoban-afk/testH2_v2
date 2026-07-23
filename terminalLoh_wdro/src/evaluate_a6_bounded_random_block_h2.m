function result = evaluate_a6_bounded_random_block_h2( ...
    model,stateSample,baseSeed,stateId,evaluationCount,windSeedOffset)
%EVALUATE_A6_BOUNDED_RANDOM_BLOCK_H2 Paired fixed versus triangular a=6 wind.

nRecords=height(stateSample);
if nRecords~=15000||evaluationCount<1||evaluationCount>nRecords
    error('State sample must contain 15000 records and cover evaluationCount.');
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
q=rand(windStream,evaluationCount,1);
windReplayStream=RandStream('mt19937ar','Seed',windSeed);
qReplay=rand(windReplayStream,evaluationCount,1);
sampledA6Wind=triangular_inverse(q,model.a6LowerMps, ...
    model.a6ModeMps,model.a6UpperMps);

idx=cell(3,1);aStage=cell(3,1);
aStage{1}=double(selected.a_W1);aStage{2}=double(selected.a_W2);aStage{3}=double(selected.a_W3);
idx{1}=state_indices(model,selected.a_W1,selected.loc_W1,selected.lfw_W1);
idx{2}=state_indices(model,selected.a_W2,selected.loc_W2,selected.lfw_W2);
idx{3}=state_indices(model,selected.a_W3,selected.loc_W3,selected.lfw_W3);
containsA6=aStage{1}==6|aStage{2}==6|aStage{3}==6;

pFail0=cell(3,1);pClose0=cell(3,1);
for ss=1:3
    pFail0{ss}=model.pFailM0(idx{ss},:);pClose0{ss}=model.pCloseM0(idx{ss},:);
end
baseline=evaluate_outcomes(model,pFail0,pClose0,lineU,roadU);
randomMode=baseline;

if any(containsA6)
    subset=find(containsA6);pFail1=cell(3,1);pClose1=cell(3,1);
    for ss=1:3
        pFail1{ss}=pFail0{ss}(subset,:);pClose1{ss}=pClose0{ss}(subset,:);
        stageA6=aStage{ss}(subset)==6;
        if any(stageA6)
            stateRows=idx{ss}(subset(stageA6));wind=sampledA6Wind(subset(stageA6));
            lineWind=model.lineFactor(stateRows,:).*wind;
            roadWind=model.roadFactor(stateRows,:).*wind;
            pFail1{ss}(stageA6,:)=compute_line_failure_prob_h2( ...
                lineWind,model.designWindSpeedVN);
            pClose1{ss}(stageA6,:)=compute_line_failure_prob_h2( ...
                roadWind,model.roadDesignWindVN);
        end
    end
    changed=evaluate_outcomes(model,pFail1,pClose1,lineU(subset,:),roadU(subset,:));
    randomMode(subset,:)=changed;
end

metricsAll=[build_metrics("M0_FIXED",model.a6ModeMps,baseline,true(evaluationCount,1)); ...
    build_metrics("M1_A6_TRIANGULAR",NaN,randomMode,true(evaluationCount,1))];
metricsA6=[build_metrics("M0_FIXED",model.a6ModeMps,baseline,containsA6); ...
    build_metrics("M1_A6_TRIANGULAR",NaN,randomMode,containsA6)];

metricNames=["Dtotal","fullLoss","A0Share","reachableShare", ...
    "CScenarioMean","W3Failed","W3Closed"];
groupNames=["all_records","contains_a6","no_a6"];
groupMasks={true(evaluationCount,1),containsA6,~containsA6};
pairedRows=cell(numel(metricNames)*numel(groupNames),12);rr=0;
for gg=1:numel(groupNames)
    mask=groupMasks{gg};
    for kk=1:numel(metricNames)
        name=metricNames(kk);b=double(baseline.(name)(mask));x=double(randomMode.(name)(mask));
        d=x-b;rr=rr+1;
        if isempty(d)
            values=num2cell(nan(1,8));nonzero=NaN;
        else
            values={mean(b),mean(x),mean(d),mean(abs(d)),pct(d,5), ...
                pct(d,50),pct(d,95),max(abs(d))};
            nonzero=mean(abs(d)>1e-12);
        end
        pairedRows(rr,:)={groupNames(gg),sum(mask),name,values{:},nonzero};
    end
end
paired=cell2table(pairedRows,'VariableNames', ...
    {'record_group','record_count','metric','M0_mean','M1_mean', ...
    'paired_difference_mean','paired_absolute_difference_mean', ...
    'paired_difference_q05','paired_difference_median','paired_difference_q95', ...
    'maximum_absolute_difference','nonzero_difference_share'});

used=find(containsA6);
windSamples=table(double(selected.path_id(used)),q(used),sampledA6Wind(used), ...
    repmat(windSeed,numel(used),1),'VariableNames', ...
    {'path_id','wind_quantile_q','sampled_a6_wind_mps','wind_seed'});

nonA6ExactPass=isequaln(baseline(~containsA6,:),randomMode(~containsA6,:));
result=struct();result.metrics_all=metricsAll;result.metrics_a6=metricsA6;
result.paired=paired;result.wind_samples=windSamples;
result.contains_a6_count=sum(containsA6);result.no_a6_count=sum(~containsA6);
result.non_a6_exact_pass=nonA6ExactPass;
result.q_shared_across_stages_pass=numel(q)==evaluationCount;
result.wind_bounds_pass=all(sampledA6Wind>=model.a6LowerMps&sampledA6Wind<=model.a6UpperMps);
result.wind_reproducibility_pass=isequal(q,qReplay);
result.separate_seed_pass=windSeed~=resistanceSeed;
result.resistance_seed=resistanceSeed;result.wind_seed=windSeed;
result.path_id_sha256=sha256_numeric(double(selected.path_id));
result.permutation_sha256=sha256_numeric(permutation(1:evaluationCount));
result.line_u_sha256=sha256_numeric(fixedLineU(1:evaluationCount,:));
result.road_u_sha256=sha256_numeric(fixedRoadU(1:evaluationCount,:));
result.q_sha256=sha256_numeric(q);
end

function outcome=evaluate_outcomes(model,pFail,pClose,lineU,roadU)
n=size(lineU,1);
failed1=lineU<=pFail{1};failed2=failed1|(lineU<=pFail{2});
failed3=failed2|(lineU<=pFail{3});
outage1=(double(failed1)*model.nodePathIncidence.')>0;
outage2=(double(failed2)*model.nodePathIncidence.')>0;
outage3=(double(failed3)*model.nodePathIncidence.')>0;
outage1(:,model.sourceNode)=false;outage2(:,model.sourceNode)=false;
outage3(:,model.sourceNode)=false;
Dtotal=(double(outage1)*model.Pnode_kW+double(outage2)*model.Pnode_kW+ ...
    double(outage3)*model.Pnode_kW)*model.DFactorKgPerKWh;
fullLoss=abs(Dtotal-model.DUpperKg)<=1e-9;W3Failed=sum(failed3,2);

closed1=roadU<=pClose{1};closed2=closed1|(roadU<=pClose{2});
closed3=closed2|(roadU<=pClose{3});
slow1=pClose{1};slow2=max(slow1,pClose{2});slow3=max(slow2,pClose{3});
W3Closed=sum(closed3,2);A0Share=zeros(n,1);reachableShare=zeros(n,1);
CScenarioMean=zeros(n,1);
for rr=1:n
    unreachableTotal=0;reachableTotal=0;Csum=0;
    for ss=1:3
        if ss==1,closed=closed1(rr,:).';slow=slow1(rr,:).';
        elseif ss==2,closed=closed2(rr,:).';slow=slow2(rr,:).';
        else,closed=closed3(rr,:).';slow=slow3(rr,:).';end
        edgeCost=model.roadLength.*(1+slow);edgeCost(closed)=Inf;
        [reachableCount,stageCsum]=road_metrics(model.nNodes,model.roadFrom, ...
            model.roadTo,edgeCost,model.siteNodes);
        reachableTotal=reachableTotal+reachableCount;
        unreachableTotal=unreachableTotal+(model.nSites*model.nNodes-reachableCount);
        Csum=Csum+stageCsum;
    end
    pairTotal=3*model.nSites*model.nNodes;A0Share(rr)=unreachableTotal/pairTotal;
    reachableShare(rr)=reachableTotal/pairTotal;
    if reachableTotal<=0,CScenarioMean(rr)=NaN;else,CScenarioMean(rr)=Csum/reachableTotal;end
end
outcome=table(Dtotal,fullLoss,A0Share,reachableShare,CScenarioMean,W3Failed,W3Closed);
end

function T=build_metrics(mode,fixedA6,outcome,mask)
x=outcome(mask,:);N=height(x);
if N==0
    values=num2cell(nan(1,18));values{1}=0;
else
    values={N,mean(x.Dtotal),pct(x.Dtotal,95),pct(x.Dtotal,99), ...
        mean(x.fullLoss),mean(x.A0Share),mean(x.reachableShare), ...
        mean(x.CScenarioMean),pct(x.CScenarioMean,95),mean(x.W3Failed), ...
        pct(x.W3Failed,95),mean(x.W3Closed),pct(x.W3Closed,95), ...
        mean(x.fullLoss),min(x.Dtotal),max(x.Dtotal), ...
        sum(~isfinite(x.Dtotal))+sum(~isfinite(x.CScenarioMean)), ...
        sum(x.Dtotal<0)+sum(x.CScenarioMean<0)};
end
T=cell2table([{mode,fixedA6},values],'VariableNames', ...
    {'mode','fixed_a6_mps','record_count','D_mean_kg','D_q95_kg','D_q99_kg', ...
    'full_loss_probability','A0_pair_share','reachable_pair_share', ...
    'C_reachable_mean_km','C_reachable_q95_km','W3_failed_lines_mean', ...
    'W3_failed_lines_q95','W3_closed_roads_mean','W3_closed_roads_q95', ...
    'D_upper_bound_hit_share','D_min_kg','D_max_kg','nonfinite_count', ...
    'negative_value_count'});
end

function x=triangular_inverse(q,a,c,b)
fc=(c-a)/(b-a);x=zeros(size(q));left=q<=fc;
x(left)=a+sqrt(q(left)*(b-a)*(c-a));
x(~left)=b-sqrt((1-q(~left))*(b-a)*(b-c));
end

function idx=state_indices(model,a,loc,lfw)
a=double(a(:));loc=double(loc(:));lfw=double(lfw(:));
linear=sub2ind(size(model.stateIndex),a,loc-model.locMin+1,lfw+1);
idx=model.stateIndex(linear);if any(idx<=0),error('Missing cached state.');end
end

function [reachableCount,Csum]=road_metrics(nNodes,fromNode,toNode,edgeCost,sources)
adj=inf(nNodes,nNodes);adj(1:(nNodes+1):end)=0;
for ee=1:numel(edgeCost)
    if ~isfinite(edgeCost(ee)),continue;end
    i=fromNode(ee);j=toNode(ee);if edgeCost(ee)<adj(i,j),adj(i,j)=edgeCost(ee);adj(j,i)=edgeCost(ee);end
end
reachableCount=0;Csum=0;
for ii=1:numel(sources)
    dist=inf(1,nNodes);visited=false(1,nNodes);dist(sources(ii))=0;
    for iter=1:nNodes
        candidate=dist;candidate(visited)=Inf;[best,u]=min(candidate);
        if ~isfinite(best),break;end
        visited(u)=true;dist=min(dist,best+adj(u,:));
    end
    finite=isfinite(dist);reachableCount=reachableCount+sum(finite);Csum=Csum+sum(dist(finite));
end
end

function value=pct(x,p)
x=sort(double(x(:)));x=x(isfinite(x));
if isempty(x),value=NaN;else,value=x(max(1,min(numel(x),ceil(p/100*numel(x)))));end
end

function hash=sha256_numeric(x)
md=java.security.MessageDigest.getInstance('SHA-256');bytes=typecast(double(x(:)),'uint8');
md.update(typecast(bytes,'int8'));digest=typecast(md.digest(),'uint8');
hash=lower(string(reshape(dec2hex(digest,2).',1,[])));
end
