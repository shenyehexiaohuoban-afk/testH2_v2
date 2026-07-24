function result = evaluate_stagewise_random_wind_block_h2( ...
    model,stateSample,baseSeed,stateId,evaluationCount,windSeedOffset)
%EVALUATE_STAGEWISE_RANDOM_WIND_BLOCK_H2 Paired fixed and hourly random wind.

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
lineU=fixedLineU(1:evaluationCount,:);
roadU=fixedRoadU(1:evaluationCount,:);

windSeed=double(windSeedOffset)+double(baseSeed)+100019*double(stateId);
windStream=RandStream('mt19937ar','Seed',windSeed);
q=rand(windStream,evaluationCount,3);
windReplayStream=RandStream('mt19937ar','Seed',windSeed);
qReplay=rand(windReplayStream,evaluationCount,3);

aStage={double(selected.a_W1),double(selected.a_W2),double(selected.a_W3)};
idx=cell(3,1);sampledVmax=cell(3,1);
idx{1}=state_indices(model,selected.a_W1,selected.loc_W1,selected.lfw_W1);
idx{2}=state_indices(model,selected.a_W2,selected.loc_W2,selected.lfw_W2);
idx{3}=state_indices(model,selected.a_W3,selected.loc_W3,selected.lfw_W3);
for ss=1:3
    sampledVmax{ss}=triangular_by_level(aStage{ss},q(:,ss), ...
        model.vLow,model.vMode,model.vHigh);
end

pFail0=cell(3,1);pClose0=cell(3,1);pFail1=cell(3,1);pClose1=cell(3,1);
lineWind0=cell(3,1);roadWind0=cell(3,1);lineWind1=cell(3,1);roadWind1=cell(3,1);
for ss=1:3
    pFail0{ss}=model.pFailM0(idx{ss},:);
    pClose0{ss}=model.pCloseM0(idx{ss},:);
    lineWind0{ss}=model.lineWindM0(idx{ss},:);
    roadWind0{ss}=model.roadWindM0(idx{ss},:);
    lineWind1{ss}=model.lineFactor(idx{ss},:).*sampledVmax{ss};
    roadWind1{ss}=model.roadFactor(idx{ss},:).*sampledVmax{ss};
    pFail1{ss}=compute_line_failure_prob_h2( ...
        lineWind1{ss},model.designWindSpeedVN);
    pClose1{ss}=compute_line_failure_prob_h2( ...
        roadWind1{ss},model.roadDesignWindVN);
end

baseline=evaluate_outcomes(model,pFail0,pClose0,lineU,roadU);
randomMode=evaluate_outcomes(model,pFail1,pClose1,lineU,roadU);
metrics=[build_metrics("M0_FIXED",baseline); ...
    build_metrics("M1_STAGEWISE_RANDOM",randomMode)];
paired=build_paired_summary(baseline,randomMode);
thresholdAudit=build_threshold_audit(lineWind0,roadWind0,lineWind1,roadWind1);

stageNames=["W1","W2","W3"];
windTables=cell(3,1);
for ss=1:3
    windTables{ss}=table(double(selected.path_id), ...
        repmat(stageNames(ss),evaluationCount,1),aStage{ss},q(:,ss), ...
        sampledVmax{ss},repmat(windSeed,evaluationCount,1), ...
        'VariableNames',{'path_id','stage','intensity_level','wind_quantile_q', ...
        'sampled_vmax_mps','wind_seed'});
end
windSamples=vertcat(windTables{:});

boundsPass=true;
for ss=1:3
    lower=model.vLow(aStage{ss});upper=model.vHigh(aStage{ss});
    boundsPass=boundsPass&&all(sampledVmax{ss}>=lower-1e-12& ...
        sampledVmax{ss}<=upper+1e-12);
end
sameLevelRedrawPass=true;
for ss=1:2
    sameLevel=aStage{ss}==aStage{ss+1}&aStage{ss}>=2;
    sameLevelRedrawPass=sameLevelRedrawPass&&all(q(sameLevel,ss)~=q(sameLevel,ss+1));
end

result=struct();result.metrics=metrics;result.paired=paired;
result.threshold_audit=thresholdAudit;result.wind_samples=windSamples;
result.stagewise_q_pass=all(isfinite(q),'all')&&all(q>=0&q<=1,'all')&& ...
    ~isequal(q(:,1),q(:,2))&&~isequal(q(:,1),q(:,3))&&~isequal(q(:,2),q(:,3));
result.same_level_redraw_pass=sameLevelRedrawPass;
result.wind_bounds_pass=boundsPass;
result.wind_reproducibility_pass=isequal(q,qReplay);
result.separate_seed_pass=windSeed~=resistanceSeed;
result.common_resistance_pass=true;
result.resistance_seed=resistanceSeed;result.wind_seed=windSeed;
result.path_id_sha256=sha256_numeric(double(selected.path_id));
result.permutation_sha256=sha256_numeric(permutation(1:evaluationCount));
result.line_u_sha256=sha256_numeric(fixedLineU(1:evaluationCount,:));
result.road_u_sha256=sha256_numeric(fixedRoadU(1:evaluationCount,:));
result.q_W1_sha256=sha256_numeric(q(:,1));
result.q_W2_sha256=sha256_numeric(q(:,2));
result.q_W3_sha256=sha256_numeric(q(:,3));
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
D_W1=double(outage1)*model.Pnode_kW*model.DFactorKgPerKWh;
D_W2=double(outage2)*model.Pnode_kW*model.DFactorKgPerKWh;
D_W3=double(outage3)*model.Pnode_kW*model.DFactorKgPerKWh;
Dtotal=D_W1+D_W2+D_W3;
fullLoss=abs(Dtotal-model.DUpperKg)<=1e-9;
failed_W1=sum(failed1,2);failed_W2=sum(failed2,2);failed_W3=sum(failed3,2);

closed1=roadU<=pClose{1};closed2=closed1|(roadU<=pClose{2});
closed3=closed2|(roadU<=pClose{3});
slow1=pClose{1};slow2=max(slow1,pClose{2});slow3=max(slow2,pClose{3});
closed_W1=sum(closed1,2);closed_W2=sum(closed2,2);closed_W3=sum(closed3,2);

A0ByStage=zeros(n,3);reachableByStage=zeros(n,3);CByStage=zeros(n,3);
for rr=1:n
    for ss=1:3
        if ss==1,closed=closed1(rr,:).';slow=slow1(rr,:).';
        elseif ss==2,closed=closed2(rr,:).';slow=slow2(rr,:).';
        else,closed=closed3(rr,:).';slow=slow3(rr,:).';end
        edgeCost=model.roadLength.*(1+slow);edgeCost(closed)=Inf;
        [reachableCount,stageCsum]=road_metrics(model.nNodes,model.roadFrom, ...
            model.roadTo,edgeCost,model.siteNodes);
        pairCount=model.nSites*model.nNodes;
        reachableByStage(rr,ss)=reachableCount/pairCount;
        A0ByStage(rr,ss)=1-reachableByStage(rr,ss);
        if reachableCount<=0,CByStage(rr,ss)=NaN;else,CByStage(rr,ss)=stageCsum/reachableCount;end
    end
end
A0Share=mean(A0ByStage,2);reachableShare=mean(reachableByStage,2);
reachableCounts=reachableByStage*(model.nSites*model.nNodes);
CScenarioMean=sum(CByStage.*reachableCounts,2)./sum(reachableCounts,2);

outcome=table(D_W1,D_W2,D_W3,Dtotal,fullLoss, ...
    A0ByStage(:,1),A0ByStage(:,2),A0ByStage(:,3),A0Share, ...
    reachableByStage(:,1),reachableByStage(:,2),reachableByStage(:,3),reachableShare, ...
    CByStage(:,1),CByStage(:,2),CByStage(:,3),CScenarioMean, ...
    failed_W1,failed_W2,failed_W3,closed_W1,closed_W2,closed_W3, ...
    'VariableNames',{'D_W1','D_W2','D_W3','Dtotal','fullLoss', ...
    'A0_W1','A0_W2','A0_W3','A0Share','reachable_W1','reachable_W2', ...
    'reachable_W3','reachableShare','C_W1','C_W2','C_W3','CScenarioMean', ...
    'failed_W1','failed_W2','failed_W3','closed_W1','closed_W2','closed_W3'});
end

function T=build_metrics(mode,outcome)
T=table(string(mode),height(outcome),mean(outcome.Dtotal),pct(outcome.Dtotal,95), ...
    pct(outcome.Dtotal,99),mean(outcome.fullLoss),mean(outcome.A0Share), ...
    mean(outcome.reachableShare),mean(outcome.CScenarioMean), ...
    pct(outcome.CScenarioMean,95),mean(outcome.failed_W3),pct(outcome.failed_W3,95), ...
    mean(outcome.closed_W3),pct(outcome.closed_W3,95),mean(outcome.fullLoss), ...
    min(outcome.Dtotal),max(outcome.Dtotal), ...
    sum(~isfinite(outcome.Dtotal))+sum(~isfinite(outcome.CScenarioMean)), ...
    sum(outcome.Dtotal<0)+sum(outcome.CScenarioMean<0), ...
    'VariableNames',{'mode','record_count','D_mean_kg','D_q95_kg','D_q99_kg', ...
    'full_loss_probability','A0_pair_share','reachable_pair_share', ...
    'C_reachable_mean_km','C_reachable_q95_km','W3_failed_lines_mean', ...
    'W3_failed_lines_q95','W3_closed_roads_mean','W3_closed_roads_q95', ...
    'D_upper_bound_hit_share','D_min_kg','D_max_kg','nonfinite_count', ...
    'negative_value_count'});
end

function T=build_paired_summary(baseline,current)
rows=cell(20,13);rr=0;
overallNames=["Dtotal","fullLoss","A0Share","reachableShare","CScenarioMean"];
for name=overallNames
    rr=rr+1;rows(rr,:)=paired_row("M1_STAGEWISE_RANDOM","Hres3h",name, ...
        baseline.(name),current.(name));
end
stageNames=["W1","W2","W3"];
prefixes=["D_","A0_","C_","failed_","closed_"];
for ss=1:3
    for pp=1:numel(prefixes)
        name=prefixes(pp)+stageNames(ss);rr=rr+1;
        rows(rr,:)=paired_row("M1_STAGEWISE_RANDOM",stageNames(ss),name, ...
            baseline.(name),current.(name));
    end
end
T=cell2table(rows,'VariableNames',{'mode','stage','metric','M0_mean','M1_mean', ...
    'paired_difference_mean','paired_absolute_difference_mean', ...
    'paired_difference_q05','paired_difference_median','paired_difference_q95', ...
    'paired_difference_min','paired_difference_max','nonzero_difference_share'});
end

function row=paired_row(mode,stage,metric,b,x)
b=double(b);x=double(x);d=x-b;
row={string(mode),string(stage),string(metric),mean(b),mean(x),mean(d), ...
    mean(abs(d)),pct(d,5),pct(d,50),pct(d,95),min(d),max(d), ...
    mean(abs(d)>1e-12)};
end

function T=build_threshold_audit(line0,road0,line1,road1)
modeNames=["M0_FIXED","M1_STAGEWISE_RANDOM"];stageNames=["W1","W2","W3"];
rows=cell(24,12);rr=0;
for mm=1:2
    for ss=1:3
        for assetId=1:2
            if assetId==1
                asset="grid_line";thresholds=[25,50];base=line0{ss};
                if mm==1,values=line0{ss};else,values=line1{ss};end
            else
                asset="road_edge";thresholds=[30,60];base=road0{ss};
                if mm==1,values=road0{ss};else,values=road1{ss};end
            end
            for threshold=thresholds
                above=values>threshold;baseAbove=base>threshold;rr=rr+1;
                rows(rr,:)={modeNames(mm),asset,stageNames(ss),threshold,numel(values), ...
                    sum(above,'all'),mean(above,'all'),sum(above&~baseAbove,'all'), ...
                    mean(above&~baseAbove,'all'),sum(~above&baseAbove,'all'), ...
                    mean(~above&baseAbove,'all'),max(values,[],'all')};
            end
        end
    end
end
T=cell2table(rows,'VariableNames',{'mode','asset','stage','threshold_mps', ...
    'observation_count','above_count','above_share','crossed_up_vs_M0_count', ...
    'crossed_up_vs_M0_share','crossed_down_vs_M0_count', ...
    'crossed_down_vs_M0_share','local_wind_max_mps'});
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
linear=sub2ind(size(model.stateIndex),a,loc-model.locMin+1,lfw+1);
idx=model.stateIndex(linear);if any(idx<=0),error('Missing cached state.');end
end

function [reachableCount,Csum]=road_metrics(nNodes,fromNode,toNode,edgeCost,sources)
adj=inf(nNodes,nNodes);adj(1:(nNodes+1):end)=0;
for ee=1:numel(edgeCost)
    if ~isfinite(edgeCost(ee)),continue;end
    i=fromNode(ee);j=toNode(ee);
    if edgeCost(ee)<adj(i,j),adj(i,j)=edgeCost(ee);adj(j,i)=edgeCost(ee);end
end
reachableCount=0;Csum=0;
for ii=1:numel(sources)
    dist=inf(1,nNodes);visited=false(1,nNodes);dist(sources(ii))=0;
    for iter=1:nNodes
        candidate=dist;candidate(visited)=Inf;[best,u]=min(candidate);
        if ~isfinite(best),break;end
        visited(u)=true;dist=min(dist,best+adj(u,:));
    end
    finite=isfinite(dist);reachableCount=reachableCount+sum(finite);
    Csum=Csum+sum(dist(finite));
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
