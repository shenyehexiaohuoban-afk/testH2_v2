function result = evaluate_b3_candidate_validation_h2( ...
    config, foundation, selection, repeatIndices)
%EVALUATE_B3_CANDIDATE_VALIDATION_H2 Streamed fixed-resistance B3 summaries.

near = foundation.raw_near;
if ~isfield(near.Grid,'P_load_base_kw') || ...
        ~isfield(near.HydrogenDevice,'eta_FC') || ...
        ~isfield(near.HydrogenDevice,'h2_lhv_kWh_per_kg')
    error('evaluate_b3_candidate_validation_h2:MissingPhysicalInput', ...
        'NearStageInput load and hydrogen conversion fields are required.');
end
Pnode = double(near.Grid.P_load_base_kw(:));
etaFC = double(near.HydrogenDevice.eta_FC);
lhv = double(near.HydrogenDevice.h2_lhv_kWh_per_kg);
gridSeg = foundation.grid_segments;roadSeg = foundation.road_segments;
siteNodes = readtable(config.siteNodeFile);
require_vars(siteNodes,{'site_id','grid_node'},'stage1_site_nodes.csv');
siteNodes = sortrows(siteNodes,'site_id');

nPaths = height(selection);nLines = height(gridSeg);nRoad = height(roadSeg);
nNodes = numel(Pnode);nSites = height(siteNodes);W = 3;
if nPaths~=2*config.expectedCandidateRows || nNodes~=33 || nSites~=4
    error('evaluate_b3_candidate_validation_h2:UnexpectedDimensions', ...
        'Expected %d paths, 33 nodes, and 4 sites; found %d/%d/%d.', ...
        2*config.expectedCandidateRows,nPaths,nNodes,nSites);
end
repeatIndices = double(repeatIndices(:).');
if any(repeatIndices<1|repeatIndices>config.resistanceRepeats| ...
        floor(repeatIndices)~=repeatIndices)
    error('Invalid resistance repeat indices.');
end

roadLength = hypot(roadSeg.x2-roadSeg.x1,roadSeg.y2-roadSeg.y1);
if any(~isfinite(roadLength)|roadLength<=0)
    error('Road lengths must be finite and positive.');
end
stateCache = build_damage_state_cache(config,foundation);

nScenarios = nPaths*numel(repeatIndices);nStageRows = nScenarios*W;
stageNum = zeros(nStageRows,50);stageSource = strings(nStageRows,1);
stageStatus = strings(nStageRows,1);stageName = strings(nStageRows,1);
scenarioNum = zeros(nScenarios,29);scenarioSource = strings(nScenarios,1);
scenarioStatus = strings(nScenarios,1);
lineSignature = strings(nScenarios,1);roadSignature = strings(nScenarios,1);
accessSignature = strings(nScenarios,1);structuralSignature = strings(nScenarios,1);
fullSignature = strings(nScenarios,1);
resistanceNum = zeros(nScenarios,13);resistanceSource = strings(nScenarios,1);
failureNum = zeros(nScenarios,19);failureSource = strings(nScenarios,1);
nodeDValues = zeros(nStageRows*nNodes,1);nodeDSource = zeros(nStageRows*nNodes,1,'uint8');
sr=0;cr=0;nr=0;

for pp=1:nPaths
    path = selection(pp,:);
    stateIndex = zeros(1,W);
    for ss=1:W
        stateIndex(ss) = lookup_state(stateCache,path.("a"+string(ss)), ...
            path.("loc"+string(ss)),path.("lfw"+string(ss)));
    end
    sourceCode = source_code(path.source_category);
    for repeat = repeatIndices
        scenarioId = (double(path.selection_path_id)-1)* ...
            config.resistanceRepeats+repeat;
        seed = config.rngSeed+1000*double(path.selection_path_id)+repeat;
        rng(seed,'twister');
        fixedLineU = rand(nLines,1);fixedRoadU = rand(nRoad,1);
        failedPrevious=false(nLines,1);closedPrevious=false(nRoad,1);
        slowdownPrevious=zeros(nRoad,1);
        failedHistory=false(nLines,W);closedHistory=false(nRoad,W);
        slowdownHistory=zeros(nRoad,W);outageHistory=false(nNodes,W);
        AHistory=false(nSites,nNodes,W);DHistory=zeros(nNodes,W);
        stageD=zeros(1,W);stagePLoss=zeros(1,W);stageFailed=zeros(1,W);
        stageClosed=zeros(1,W);stageReachShare=zeros(1,W);
        stageUnreachableNodes=zeros(1,W);stageCReachSum=zeros(1,W);
        stageCReachCount=zeros(1,W);jointDamage=false;multiLine=false;
        lineText="";roadText="";accessText="";structuralText="";fullText="";

        for ss=1:W
            d = stateCache(stateIndex(ss),:);
            pFail = d.pFail{1};pClose = d.pClose{1};
            rawFailed = fixedLineU<=pFail;rawClosed = fixedRoadU<=pClose;
            newlyFailed = rawFailed&~failedPrevious;
            newlyClosed = rawClosed&~closedPrevious;
            failed = failedPrevious|rawFailed;closed = closedPrevious|rawClosed;
            slowdownNew = config.roadSlowdownLambda.*pClose;
            slowdown = max(slowdownPrevious,slowdownNew);
            failedPrevious=failed;closedPrevious=closed;slowdownPrevious=slowdown;

            connected = connected_to_source(nNodes,gridSeg.from_node, ...
                gridSeg.to_node,~failed,config.sourceNode);
            outage = ~connected(:);outage(config.sourceNode)=false;
            P_loss_node = double(outage).*Pnode;
            Dnode = compute_Hres3h_node_demand_h2(P_loss_node, ...
                config.sliceDurationH,etaFC,lhv);

            edgeCost = roadLength.*(1+slowdown);edgeCost(closed)=Inf;
            rawC = road_shortest_paths(nNodes,roadSeg.from_node,roadSeg.to_node, ...
                edgeCost,double(siteNodes.grid_node));
            A = isfinite(rawC);C=rawC;C(~A)=0;
            reachableC=C(A);
            if any(~isfinite(C(:)))||any(C(:)<0)||any(Dnode<0)
                error('D and masked C must be finite and nonnegative.');
            end
            slowRoad = ~closed&slowdown>config.slowRoadThreshold;
            unreachableEverySite = sum(all(~A,1));

            failedHistory(:,ss)=failed;closedHistory(:,ss)=closed;
            slowdownHistory(:,ss)=slowdown;outageHistory(:,ss)=outage;
            AHistory(:,:,ss)=A;DHistory(:,ss)=Dnode;
            stageD(ss)=sum(Dnode);stagePLoss(ss)=sum(P_loss_node);
            stageFailed(ss)=sum(failed);stageClosed(ss)=sum(closed);
            stageReachShare(ss)=sum(A(:))/numel(A);
            stageUnreachableNodes(ss)=unreachableEverySite;
            stageCReachSum(ss)=sum(reachableC);
            stageCReachCount(ss)=numel(reachableC);
            jointDamage=jointDamage||(any(failed)&&any(closed));
            multiLine=multiLine||(sum(failed)>=2);

            linePart=logical_text(failed);roadPart=logical_text(closed);
            outagePart=logical_text(outage);accessPart=logical_text(A(:));
            lineText=lineText+"|"+linePart;roadText=roadText+"|"+roadPart;
            accessText=accessText+"|"+accessPart;
            structuralText=structuralText+"|"+linePart+"|"+roadPart+ ...
                "|"+outagePart+"|"+accessPart;
            fullText=fullText+"|"+linePart+"|"+roadPart+"|"+outagePart+ ...
                "|"+accessPart+"|"+numeric_text(Dnode,6)+"|"+numeric_text(C(:),6);

            sr=sr+1;
            stageNum(sr,:)=[scenarioId,path.selection_path_id,repeat,seed, ...
                path.empirical_weight,path.path_probability,ss,d.a,d.loc,d.lfw, ...
                d.x,d.y,d.Vmax,d.line_wind_mean,d.line_wind_p95,d.line_wind_max, ...
                d.road_wind_mean,d.road_wind_p95,d.road_wind_max,d.pFail_mean, ...
                d.pFail_p95,d.pFail_max,d.pClose_mean,d.pClose_p95,d.pClose_max, ...
                sum(rawFailed),sum(newlyFailed),sum(failed),sum(rawClosed), ...
                sum(newlyClosed),sum(closed),sum(slowRoad),sum(outage), ...
                sum(P_loss_node),sum(Dnode),max(Dnode),pct(Dnode,95), ...
                sum(Dnode>0),sum(A(:)),numel(A),sum(A(:))/numel(A), ...
                sum(~A(:)),unreachableEverySite,numel(reachableC), ...
                sum(reachableC),min_or_zero(reachableC),mean_or_zero(reachableC), ...
                pct_or_zero(reachableC,95),max_or_zero(reachableC), ...
                config.sliceDurationH];
            stageSource(sr)=path.source_category;stageStatus(sr)=path.nominal_inclusion_status;
            stageName(sr)="W"+string(ss);
            range=nr+(1:nNodes);nodeDValues(range)=Dnode;nodeDSource(range)=sourceCode;
            nr=nr+nNodes;
        end

        lineViolations=sum(failedHistory(:,1)&~failedHistory(:,2))+ ...
            sum(failedHistory(:,2)&~failedHistory(:,3));
        roadViolations=sum(closedHistory(:,1)&~closedHistory(:,2))+ ...
            sum(closedHistory(:,2)&~closedHistory(:,3));
        slowdownViolations=sum(slowdownHistory(:,2)+1e-15<slowdownHistory(:,1))+ ...
            sum(slowdownHistory(:,3)+1e-15<slowdownHistory(:,2));
        nodeD3h=sum(DHistory,2);

        cr=cr+1;
        scenarioNum(cr,:)=[scenarioId,path.selection_path_id,repeat,seed, ...
            path.empirical_weight,path.path_probability,sum(stageD),min(stageD), ...
            max(stageD),sum(stagePLoss),max(stagePLoss),max(nodeD3h), ...
            pct(nodeD3h,95),sum(nodeD3h>0),stageFailed,stageClosed, ...
            mean(stageReachShare),min(stageReachShare), ...
            sum(stageUnreachableNodes),max(stageUnreachableNodes), ...
            sum(stageCReachSum),sum(stageCReachCount),jointDamage,multiLine, ...
            any(stageUnreachableNodes>0)];
        scenarioSource(cr)=path.source_category;
        scenarioStatus(cr)=path.nominal_inclusion_status;
        lineSignature(cr)=sha256_text(lineText);roadSignature(cr)=sha256_text(roadText);
        accessSignature(cr)=sha256_text(accessText);
        structuralSignature(cr)=sha256_text(structuralText);
        fullSignature(cr)=sha256_text(fullText);

        resistanceNum(cr,:)=[scenarioId,path.selection_path_id,repeat,seed, ...
            nLines,nRoad,1,1,weighted_checksum(fixedLineU), ...
            weighted_checksum(fixedRoadU),0,0,1];
        resistanceSource(cr)=path.source_category;
        failureNum(cr,:)=[scenarioId,path.selection_path_id,repeat,seed, ...
            stageFailed,stageClosed,max(slowdownHistory(:,1)), ...
            max(slowdownHistory(:,2)),max(slowdownHistory(:,3)), ...
            lineViolations,roadViolations,slowdownViolations, ...
            lineViolations==0,roadViolations==0,slowdownViolations==0];
        failureSource(cr)=path.source_category;
    end
end

stageResults = array2table(stageNum,'VariableNames',stage_numeric_names());
stageResults = addvars(stageResults,stageSource,stageStatus,stageName, ...
    'After','random_seed','NewVariableNames', ...
    {'source_category','nominal_inclusion_status','stage'});
stageResults.D_unit=repmat("kg-H2",height(stageResults),1);
stageResults.C_definition=repmat(config.CDefinition,height(stageResults),1);

scenarioResults = array2table(scenarioNum,'VariableNames',scenario_numeric_names());
scenarioResults = addvars(scenarioResults,scenarioSource,scenarioStatus, ...
    'After','random_seed','NewVariableNames', ...
    {'source_category','nominal_inclusion_status'});
scenarioResults.line_failure_signature=lineSignature;
scenarioResults.road_closure_signature=roadSignature;
scenarioResults.accessibility_signature=accessSignature;
scenarioResults.structural_pattern_signature=structuralSignature;
scenarioResults.full_consequence_signature=fullSignature;

resistanceAudit = array2table(resistanceNum,'VariableNames',resistance_names());
resistanceAudit = addvars(resistanceAudit,resistanceSource,'After','random_seed', ...
    'NewVariableNames','source_category');
failureAudit = array2table(failureNum,'VariableNames',failure_names());
failureAudit = addvars(failureAudit,failureSource,'After','random_seed', ...
    'NewVariableNames','source_category');

result=struct();result.stage_results=stageResults;
result.scenario_results=scenarioResults;result.resistance_audit=resistanceAudit;
result.failure_audit=failureAudit;result.node_d_values=nodeDValues(1:nr);
result.node_d_source=nodeDSource(1:nr);result.eta_FC=etaFC;
result.LHV_H2_kWh_per_kg=lhv;result.Pnode_kW=Pnode;
result.n_lines=nLines;result.n_roads=nRoad;result.n_nodes=nNodes;
result.n_sites=nSites;result.repeat_indices=repeatIndices;
end

function cache=build_damage_state_cache(config,foundation)
locValues=sort(double(foundation.loc_table.loc));rows=cell(6*numel(locValues)*4,22);rr=0;
for a=1:6
    for loc=locValues(:).'
        locRow=foundation.loc_table(foundation.loc_table.loc==loc,:);
        for lfw=0:3
            rr=rr+1;x=double(locRow.x_coord);y=foundation.y_base+lfw*config.Wstep;
            Vmax=intensity_to_vmax(a);
            lineDist=compute_point_to_segment_distance_h2(x,y, ...
                foundation.grid_segments.x1,foundation.grid_segments.y1, ...
                foundation.grid_segments.x2,foundation.grid_segments.y2);
            roadDist=compute_point_to_segment_distance_h2(x,y, ...
                foundation.road_segments.x1,foundation.road_segments.y1, ...
                foundation.road_segments.x2,foundation.road_segments.y2);
            lineWind=compute_wind_speed_radial_h2(lineDist,Vmax,config.Rmax,config.windDecayB);
            roadWind=compute_wind_speed_radial_h2(roadDist,Vmax,config.Rmax,config.windDecayB);
            pFail=compute_line_failure_prob_h2(lineWind,config.designWindSpeedVN);
            pClose=compute_line_failure_prob_h2(roadWind,config.roadDesignWindVN);
            rows(rr,:)={a,loc,lfw,x,y,Vmax,mean(lineWind),pct(lineWind,95), ...
                max(lineWind),mean(roadWind),pct(roadWind,95),max(roadWind), ...
                mean(pFail),pct(pFail,95),max(pFail),mean(pClose), ...
                pct(pClose,95),max(pClose),lineWind,roadWind,pFail,pClose};
        end
    end
end
cache=cell2table(rows,'VariableNames',{'a','loc','lfw','x','y','Vmax', ...
    'line_wind_mean','line_wind_p95','line_wind_max','road_wind_mean', ...
    'road_wind_p95','road_wind_max','pFail_mean','pFail_p95','pFail_max', ...
    'pClose_mean','pClose_p95','pClose_max','lineWind','roadWind','pFail','pClose'});
end

function idx=lookup_state(cache,a,loc,lfw)
idx=find(cache.a==a&cache.loc==loc&cache.lfw==lfw);
if numel(idx)~=1,error('Joint state (%g,%g,%g) not uniquely cached.',a,loc,lfw);end
end

function connected=connected_to_source(Nj,fromNode,toNode,activeLine,sourceNode)
adj=false(Nj,Nj);
for ll=1:numel(fromNode)
    if activeLine(ll),i=fromNode(ll);j=toNode(ll);adj(i,j)=true;adj(j,i)=true;end
end
connected=false(Nj,1);queue=zeros(Nj,1);head=1;tail=1;
queue(1)=sourceNode;connected(sourceNode)=true;
while head<=tail
    cur=queue(head);head=head+1;nbrs=find(adj(cur,:));
    for nn=nbrs
        if ~connected(nn),connected(nn)=true;tail=tail+1;queue(tail)=nn;end
    end
end
end

function D=road_shortest_paths(Nj,fromNode,toNode,edgeCost,sources)
adj=inf(Nj,Nj);adj(1:(Nj+1):end)=0;
for ee=1:numel(edgeCost)
    if ~isfinite(edgeCost(ee)),continue;end
    i=fromNode(ee);j=toNode(ee);
    if edgeCost(ee)<adj(i,j),adj(i,j)=edgeCost(ee);adj(j,i)=edgeCost(ee);end
end
D=inf(numel(sources),Nj);
for ii=1:numel(sources)
    dist=inf(1,Nj);visited=false(1,Nj);dist(sources(ii))=0;
    for iter=1:Nj
        candidate=dist;candidate(visited)=Inf;[best,u]=min(candidate);
        if ~isfinite(best),break;end
        visited(u)=true;dist=min(dist,best+adj(u,:));
    end
    D(ii,:)=dist;
end
end

function names=stage_numeric_names()
names={'scenario_id','selection_path_id','resistance_repeat','random_seed', ...
    'empirical_weight','path_probability','stage_index','a','loc','lfw', ...
    'center_x','center_y','Vmax_mps','line_wind_mean_mps','line_wind_p95_mps', ...
    'line_wind_max_mps','road_wind_mean_mps','road_wind_p95_mps', ...
    'road_wind_max_mps','line_pFail_mean','line_pFail_p95','line_pFail_max', ...
    'road_pClose_mean','road_pClose_p95','road_pClose_max', ...
    'raw_failed_line_count','newly_failed_line_count','failed_line_count', ...
    'raw_closed_road_count','newly_closed_road_count','closed_road_count', ...
    'slow_road_count','outage_node_count','P_loss_total_kW','D_total_kg', ...
    'D_node_max_kg','D_node_p95_kg','D_node_nonzero_count', ...
    'reachable_pair_count','site_node_pair_count','reachable_pair_share', ...
    'unreachable_pair_count','nodes_unreachable_from_every_site', ...
    'C_reachable_count','C_reachable_sum_km','C_reachable_min_km', ...
    'C_reachable_mean_km','C_reachable_p95_km','C_reachable_max_km', ...
    'slice_duration_h'};
end

function names=scenario_numeric_names()
names={'scenario_id','selection_path_id','resistance_repeat','random_seed', ...
    'empirical_weight','path_probability','D_Hres3h_total_kg','D_stage_min_kg', ...
    'D_stage_max_kg','P_loss_stage_sum_kW','P_loss_stage_max_kW', ...
    'D_node_Hres3h_max_kg','D_node_Hres3h_p95_kg','D_node_Hres3h_nonzero_count', ...
    'failed_lines_W1','failed_lines_W2','failed_lines_W3','closed_roads_W1', ...
    'closed_roads_W2','closed_roads_W3','reachable_pair_share_stage_mean', ...
    'reachable_pair_share_stage_min','unreachable_node_stage_sum', ...
    'unreachable_node_stage_max','C_reachable_sum_all_stages_km', ...
    'C_reachable_count_all_stages','joint_line_road_damage_any', ...
    'multi_line_failure_any','road_disconnection_any'};
end

function names=resistance_names()
names={'scenario_id','selection_path_id','resistance_repeat','random_seed', ...
    'line_component_count','road_component_count', ...
    'line_threshold_draws_per_component','road_threshold_draws_per_component', ...
    'fixed_line_threshold_checksum','fixed_road_threshold_checksum', ...
    'line_threshold_reuse_max_abs_error','road_threshold_reuse_max_abs_error', ...
    'fixed_resistance_pass'};
end

function names=failure_names()
names={'scenario_id','selection_path_id','resistance_repeat','random_seed', ...
    'failed_lines_W1','failed_lines_W2','failed_lines_W3','closed_roads_W1', ...
    'closed_roads_W2','closed_roads_W3','slowdown_max_W1','slowdown_max_W2', ...
    'slowdown_max_W3','line_recovery_violation_count', ...
    'road_recovery_violation_count','slowdown_recovery_violation_count', ...
    'line_persistence_pass','road_persistence_pass','slowdown_persistence_pass'};
end

function code=source_code(source)
if source=="main_reference",code=uint8(1);
elseif source=="observed_candidate",code=uint8(2);
elseif source=="unobserved_candidate",code=uint8(3);
else,error('Unknown source category %s.',source);end
end

function Vmax=intensity_to_vmax(a)
map=[0;20.8;28.55;37.05;46.20;55.50];
if a<1||a>numel(map)||floor(a)~=a,error('Unsupported intensity a=%g.',a);end
Vmax=map(a);
end
function value=weighted_checksum(x),value=sum(double(x(:)).*(1:numel(x)).');end
function value=mean_or_zero(x),if isempty(x),value=0;else,value=mean(x);end,end
function value=min_or_zero(x),if isempty(x),value=0;else,value=min(x);end,end
function value=max_or_zero(x),if isempty(x),value=0;else,value=max(x);end,end
function value=pct_or_zero(x,p),if isempty(x),value=0;else,value=pct(x,p);end,end
function value=pct(x,p)
x=sort(double(x(:)));x=x(isfinite(x));
if isempty(x),value=NaN;else,value=x(max(1,min(numel(x),ceil(p/100*numel(x)))));end
end
function text=logical_text(x),text=string(char('0'+double(x(:).')));end
function text=numeric_text(x,digits)
format="%."+string(digits)+"f,";text=string(sprintf(format,double(x(:))));
end
function hash=sha256_text(text)
md=java.security.MessageDigest.getInstance('SHA-256');
bytes=uint8(unicode2native(char(text),'UTF-8'));md.update(typecast(bytes,'int8'));
digest=typecast(md.digest(),'uint8');hash=lower(string(reshape(dec2hex(digest,2).',1,[])));
end
function require_vars(T,names,fileName)
for ii=1:numel(names)
    if ~ismember(names{ii},T.Properties.VariableNames)
        error('%s missing required field %s.',fileName,names{ii});
    end
end
end
