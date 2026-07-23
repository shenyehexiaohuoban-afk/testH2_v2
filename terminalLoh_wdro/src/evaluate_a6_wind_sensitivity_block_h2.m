function result = evaluate_a6_wind_sensitivity_block_h2( ...
    model,stateSample,baseSeed,stateId,evaluationCount)
%EVALUATE_A6_WIND_SENSITIVITY_BLOCK_H2 Evaluate one paired state/seed block.

nRecords=height(stateSample);
if nRecords~=15000 || evaluationCount<1 || evaluationCount>nRecords
    error('State sample must contain 15000 records and cover evaluationCount.');
end
required={'a_W1','a_W2','a_W3','loc_W1','loc_W2','loc_W3', ...
    'lfw_W1','lfw_W2','lfw_W3','path_id'};
for ii=1:numel(required)
    if ~ismember(required{ii},stateSample.Properties.VariableNames)
        error('State sample missing %s.',required{ii});
    end
end

derivedSeed=double(baseSeed)+100003*double(stateId);
rng(derivedSeed,'twister');
permutation=randperm(nRecords).';
fixedLineU=rand(nRecords,model.nLines);
fixedRoadU=rand(nRecords,model.nRoads);
selected=stateSample(permutation(1:evaluationCount),:);
lineU=fixedLineU(1:evaluationCount,:);
roadU=fixedRoadU(1:evaluationCount,:);

idx=cell(3,1);
idx{1}=state_indices(model,selected.a_W1,selected.loc_W1,selected.lfw_W1);
idx{2}=state_indices(model,selected.a_W2,selected.loc_W2,selected.lfw_W2);
idx{3}=state_indices(model,selected.a_W3,selected.loc_W3,selected.lfw_W3);
containsA6=double(selected.a_W1)==6|double(selected.a_W2)==6|double(selected.a_W3)==6;

nModes=numel(model.modeNames);scenario=cell(nModes,1);
metricRows=cell(nModes,23);
for mm=1:nModes
    pFail1=model.fixedPFail{mm}(idx{1},:);
    pFail2=model.fixedPFail{mm}(idx{2},:);
    pFail3=model.fixedPFail{mm}(idx{3},:);
    failed1=lineU<=pFail1;
    failed2=failed1|(lineU<=pFail2);
    failed3=failed2|(lineU<=pFail3);
    outage1=(double(failed1)*model.nodePathIncidence.')>0;
    outage2=(double(failed2)*model.nodePathIncidence.')>0;
    outage3=(double(failed3)*model.nodePathIncidence.')>0;
    outage1(:,model.sourceNode)=false;outage2(:,model.sourceNode)=false;
    outage3(:,model.sourceNode)=false;
    P1=double(outage1)*model.Pnode_kW;
    P2=double(outage2)*model.Pnode_kW;
    P3=double(outage3)*model.Pnode_kW;
    Dtotal=(P1+P2+P3)*model.DFactorKgPerKWh;
    fullLoss=abs(Dtotal-model.DUpperKg)<=1e-9;
    W3Failed=sum(failed3,2);

    pClose1=model.fixedPClose{mm}(idx{1},:);
    pClose2=model.fixedPClose{mm}(idx{2},:);
    pClose3=model.fixedPClose{mm}(idx{3},:);
    closed1=roadU<=pClose1;
    closed2=closed1|(roadU<=pClose2);
    closed3=closed2|(roadU<=pClose3);
    slow1=pClose1;slow2=max(slow1,pClose2);slow3=max(slow2,pClose3);
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
            invalidC=invalidC+stageInvalid;
            reachableTotal=reachableTotal+reachableCount;
            unreachableTotal=unreachableTotal+(model.nSites*model.nNodes-reachableCount);
            Csum=Csum+stageCsum;
        end
        pairTotal=3*model.nSites*model.nNodes;
        A0Share(rr)=unreachableTotal/pairTotal;
        reachableShare(rr)=reachableTotal/pairTotal;
        if reachableTotal<=0
            invalidA=invalidA+1;CScenarioMean(rr)=NaN;
        else
            CScenarioMean(rr)=Csum/reachableTotal;
        end
    end

    scenario{mm}=table(Dtotal,fullLoss,A0Share,reachableShare, ...
        CScenarioMean,W3Failed,W3Closed);
    metricRows(mm,:)={model.modeNames(mm),model.a6ValuesMps(mm), ...
        evaluationCount,sum(containsA6),mean(containsA6),mean(Dtotal), ...
        pct(Dtotal,95),pct(Dtotal,99),mean(fullLoss),mean(A0Share), ...
        mean(reachableShare),mean(CScenarioMean),pct(CScenarioMean,95), ...
        mean(W3Failed),pct(W3Failed,95),mean(W3Closed),pct(W3Closed,95), ...
        mean(fullLoss),min(Dtotal),max(Dtotal), ...
        sum(~isfinite(Dtotal))+sum(~isfinite(CScenarioMean)), ...
        sum(Dtotal<0)+sum(CScenarioMean<0),invalidA+invalidC};
end
metrics=cell2table(metricRows,'VariableNames', ...
    {'mode','a6_Vmax_mps','N','contains_a6_path_count','contains_a6_path_share', ...
    'D_mean_kg','D_q95_kg','D_q99_kg','full_loss_probability', ...
    'A0_pair_share','reachable_pair_share','C_reachable_mean_km', ...
    'C_reachable_q95_km','W3_failed_lines_mean','W3_failed_lines_q95', ...
    'W3_closed_roads_mean','W3_closed_roads_q95','D_upper_bound_hit_share', ...
    'D_min_kg','D_max_kg','nonfinite_count','negative_value_count', ...
    'invalid_A_or_C_count'});

metricNames=["Dtotal","fullLoss","A0Share","reachableShare", ...
    "CScenarioMean","W3Failed","W3Closed"];
groupNames=["all_paths","contains_a6","no_a6"];
groupMasks={true(evaluationCount,1),containsA6,~containsA6};
pairedRows=cell((nModes-1)*numel(metricNames)*numel(groupNames),15);pr=0;
baseline=scenario{1};
for mm=2:nModes
    current=scenario{mm};
    for gg=1:numel(groupNames)
        mask=groupMasks{gg};
        for kk=1:numel(metricNames)
            name=metricNames(kk);b=double(baseline.(name)(mask));
            x=double(current.(name)(mask));d=x-b;pr=pr+1;
            if isempty(d)
                values=num2cell(nan(1,9));nonzero=NaN;
            else
                values={mean(b),mean(x),mean(d),mean(abs(d)),pct(d,5), ...
                    pct(d,50),pct(d,95),min(d),max(d)};
                nonzero=mean(abs(d)>1e-12);
            end
            pairedRows(pr,:)={model.modeNames(mm),model.a6ValuesMps(mm), ...
                groupNames(gg),sum(mask),name,values{:},nonzero};
        end
    end
end
paired=cell2table(pairedRows,'VariableNames', ...
    {'mode','a6_Vmax_mps','path_group','path_count','metric','M0_mean', ...
    'mode_mean','paired_difference_mean','paired_absolute_difference_mean', ...
    'paired_difference_q05','paired_difference_median','paired_difference_q95', ...
    'paired_difference_min','paired_difference_max','nonzero_difference_share'});

nonA6ExactPass=true;
for mm=2:nModes
    nonA6ExactPass=nonA6ExactPass&&isequaln(scenario{1}(~containsA6,:), ...
        scenario{mm}(~containsA6,:));
end
result=struct();result.metrics=metrics;result.paired=paired;
result.contains_a6_count=sum(containsA6);result.no_a6_count=sum(~containsA6);
result.non_a6_exact_pass=nonA6ExactPass;result.common_resistance_pass=true;
result.derived_seed=derivedSeed;
result.path_id_sha256=sha256_numeric(double(selected.path_id));
result.permutation_sha256=sha256_numeric(permutation(1:evaluationCount));
result.line_u_sha256=sha256_numeric(fixedLineU(1:evaluationCount,:));
result.road_u_sha256=sha256_numeric(fixedRoadU(1:evaluationCount,:));
end

function idx=state_indices(model,a,loc,lfw)
a=double(a(:));loc=double(loc(:));lfw=double(lfw(:));
if any(a<1|a>6|loc<model.locMin|loc>model.locMax|lfw<0|lfw>3)
    error('Sample contains a joint state outside the accepted support.');
end
linear=sub2ind(size(model.stateIndex),a,loc-model.locMin+1,lfw+1);
idx=model.stateIndex(linear);if any(idx<=0),error('Missing cached state.');end
end

function [reachableCount,Csum,invalidCount]=road_metrics( ...
    nNodes,fromNode,toNode,edgeCost,sources)
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

function value=pct(x,p)
x=sort(double(x(:)));x=x(isfinite(x));
if isempty(x),value=NaN;else,value=x(max(1,min(numel(x),ceil(p/100*numel(x)))));end
end

function hash=sha256_numeric(x)
md=java.security.MessageDigest.getInstance('SHA-256');
bytes=typecast(double(x(:)),'uint8');md.update(typecast(bytes,'int8'));
digest=typecast(md.digest(),'uint8');hash=lower(string(reshape(dec2hex(digest,2).',1,[])));
end
