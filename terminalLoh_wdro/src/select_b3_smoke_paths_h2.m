function result = select_b3_smoke_paths_h2(candidatePool, mainSample, config)
%SELECT_B3_SMOKE_PATHS_H2 Deterministic 5-state, 30-path smoke selection.

candidateVars = {'unique_path_id','a0','loc0','lfw0','a1','loc1','lfw1', ...
    'a2','loc2','lfw2','a3','loc3','lfw3','path_probability', ...
    'is_observed_candidate','is_unobserved_candidate','observed_frequency', ...
    'observed_empirical_mass','listed_level_count','source_record_count'};
mainVars = {'a0','loc0','lfw0','a_W1','loc_W1','lfw_W1','a_W2', ...
    'loc_W2','lfw_W2','a_W3','loc_W3','lfw_W3','path_probability'};
require_vars(candidatePool,candidateVars,'unique_tail_paths.csv');
require_vars(mainSample,mainVars,'main_path_samples.csv');

stateSummary = build_candidate_state_summary(candidatePool);
eligible = stateSummary(stateSummary.observed_count >= 2 & ...
    stateSummary.unobserved_count >= 2,:);
if height(eligible) < config.representativeStateCount
    error('select_b3_smoke_paths_h2:InsufficientEligibleStates', ...
        'Need %d states with at least two observed and two unobserved candidates.', ...
        config.representativeStateCount);
end

selectedStates = table();
selectedStates = append_state(selectedStates,sortrows(eligible, ...
    {'candidate_count','a0','loc0'}),"minimum_candidate_count");
maxWork = eligible;maxWork.neg_count = -maxWork.candidate_count;
selectedStates = append_state(selectedStates,sortrows(maxWork, ...
    {'neg_count','a0','loc0'}),"maximum_candidate_count");
lowWork = eligible;lowWork.rank_a = lowWork.a0;lowWork.rank_loc = lowWork.loc0;
selectedStates = append_state(selectedStates,sortrows(lowWork, ...
    {'rank_a','rank_loc'}),"low_intensity_left_location");
midWork = eligible;
midWork.center_distance = abs(midWork.a0-4)+abs(midWork.loc0-4);
selectedStates = append_state(selectedStates,sortrows(midWork, ...
    {'center_distance','a0','loc0'}),"medium_intensity_center_location");
highWork = eligible;highWork.neg_a = -highWork.a0;highWork.neg_loc = -highWork.loc0;
selectedStates = append_state(selectedStates,sortrows(highWork, ...
    {'neg_a','neg_loc'}),"high_intensity_right_location");
if height(selectedStates) ~= config.representativeStateCount
    error('select_b3_smoke_paths_h2:StateSelectionMismatch', ...
        'Selected %d representative states, expected %d.', ...
        height(selectedStates),config.representativeStateCount);
end
selectedStates.state_selection_id = (1:height(selectedStates)).';
selectedStates = movevars(selectedStates,'state_selection_id','Before',1);

selectionRows = {};
probabilityRows = {};
selectionId = 0;
for ss = 1:height(selectedStates)
    a0 = selectedStates.a0(ss);loc0 = selectedStates.loc0(ss);
    lfw0 = selectedStates.lfw0(ss);
    statePool = candidatePool(candidatePool.a0==a0 & ...
        candidatePool.loc0==loc0 & candidatePool.lfw0==lfw0,:);
    mainUnique = aggregate_main_paths(mainSample,a0,loc0,lfw0);
    poolKeys = physical_keys(statePool);
    mainUnique.is_candidate_pool_member = ismember(physical_keys(mainUnique),poolKeys);

    ordinary = mainUnique(~mainUnique.is_candidate_pool_member,:);
    ordinary.neg_frequency = -ordinary.frequency;
    ordinary = sortrows(ordinary,{'neg_frequency','a1','loc1','lfw1', ...
        'a2','loc2','lfw2','a3','loc3','lfw3'});
    if height(ordinary) < config.pathsPerSource
        error('select_b3_smoke_paths_h2:InsufficientOrdinaryPaths', ...
            'State (%g,%g,%g) has fewer than %d ordinary paths.', ...
            a0,loc0,lfw0,config.pathsPerSource);
    end
    ordinary = ordinary(1:config.pathsPerSource,:);

    observed = statePool(as_logical(statePool.is_observed_candidate),:);
    observed.neg_frequency = -double(observed.observed_frequency);
    observedCommon = sortrows(observed,{'neg_frequency','a1','loc1','lfw1', ...
        'a2','loc2','lfw2','a3','loc3','lfw3'});
    firstObserved = observedCommon(1,:);
    remainingObserved = observed(observed.unique_path_id~=firstObserved.unique_path_id,:);
    remainingObserved = sortrows(remainingObserved,{'path_probability', ...
        'a1','loc1','lfw1','a2','loc2','lfw2','a3','loc3','lfw3'});
    if isempty(remainingObserved)
        error('select_b3_smoke_paths_h2:InsufficientObservedPaths', ...
            'State (%g,%g,%g) does not have two observed candidates.',a0,loc0,lfw0);
    end
    observedSelected = [firstObserved;remainingObserved(1,:)];

    unobserved = statePool(as_logical(statePool.is_unobserved_candidate),:);
    unobserved.neg_probability = -unobserved.path_probability;
    unobservedLow = sortrows(unobserved,{'path_probability','a1','loc1','lfw1', ...
        'a2','loc2','lfw2','a3','loc3','lfw3'});
    firstUnobserved = unobservedLow(1,:);
    remainingUnobserved = unobserved( ...
        unobserved.unique_path_id~=firstUnobserved.unique_path_id,:);
    remainingUnobserved = sortrows(remainingUnobserved,{'neg_probability', ...
        'a1','loc1','lfw1','a2','loc2','lfw2','a3','loc3','lfw3'});
    if isempty(remainingUnobserved)
        error('select_b3_smoke_paths_h2:InsufficientUnobservedPaths', ...
            'State (%g,%g,%g) does not have two unobserved candidates.',a0,loc0,lfw0);
    end
    unobservedSelected = [firstUnobserved;remainingUnobserved(1,:)];

    for ii = 1:height(ordinary)
        selectionId = selectionId+1;
        row = ordinary(ii,:);
        weight = row.frequency/config.mainPathsPerInitialState;
        selectionRows(end+1,:) = make_selection_row(selectionId,ss, ...
            selectedStates.state_selection_rule(ss),"main_ordinary", ...
            "highest_frequency_non_candidate_rank_"+string(ii),row,NaN, ...
            row.frequency,weight,"included_in_main_empirical_distribution"); %#ok<AGROW>
        probabilityRows(end+1,:) = make_probability_row(selectionId, ...
            "main_ordinary",row.frequency,weight,row.path_probability_min, ...
            row.path_probability_max,false,false,weight,config); %#ok<AGROW>
    end

    observedRules=["highest_observed_frequency_candidate", ...
        "lowest_path_probability_remaining_observed_candidate"];
    for ii = 1:height(observedSelected)
        selectionId = selectionId+1;
        row = observedSelected(ii,:);
        mainMatch = mainUnique(physical_keys(mainUnique)==physical_keys(row),:);
        if height(mainMatch)~=1
            error('select_b3_smoke_paths_h2:ObservedTraceabilityFailure', ...
                'Observed candidate must map to exactly one main-sample physical path.');
        end
        frequency = mainMatch.frequency;
        weight = frequency/config.mainPathsPerInitialState;
        selectionRows(end+1,:) = make_selection_row(selectionId,ss, ...
            selectedStates.state_selection_rule(ss),"observed_candidate", ...
            observedRules(ii),row,row.unique_path_id,frequency,weight, ...
            "included_in_main_empirical_distribution"); %#ok<AGROW>
        probabilityRows(end+1,:) = make_probability_row(selectionId, ...
            "observed_candidate",frequency,weight,mainMatch.path_probability_min, ...
            mainMatch.path_probability_max,true,false, ...
            double(row.observed_empirical_mass),config); %#ok<AGROW>
    end

    unobservedRules=["lowest_path_probability_unobserved_candidate", ...
        "highest_path_probability_remaining_unobserved_candidate"];
    for ii = 1:height(unobservedSelected)
        selectionId = selectionId+1;
        row = unobservedSelected(ii,:);
        mainOverlap = any(physical_keys(mainUnique)==physical_keys(row));
        selectionRows(end+1,:) = make_selection_row(selectionId,ss, ...
            selectedStates.state_selection_rule(ss),"unobserved_candidate", ...
            unobservedRules(ii),row,row.unique_path_id,0,0, ...
            "pending_after_B3"); %#ok<AGROW>
        probabilityRows(end+1,:) = make_probability_row(selectionId, ...
            "unobserved_candidate",0,0,row.path_probability,row.path_probability, ...
            false,mainOverlap,0,config); %#ok<AGROW>
    end
end

selection = cell2table(selectionRows,'VariableNames',selection_variable_names());
probabilityAudit = cell2table(probabilityRows,'VariableNames', ...
    probability_variable_names());

if height(selection) ~= config.representativeStateCount*3*config.pathsPerSource
    error('select_b3_smoke_paths_h2:PathCountMismatch', ...
        'Selected %d paths, expected %d.',height(selection), ...
        config.representativeStateCount*3*config.pathsPerSource);
end

result=struct();
result.selection=selection;
result.probability_audit=probabilityAudit;
result.selected_states=selectedStates;
result.candidate_state_summary=stateSummary;
end

function T = build_candidate_state_summary(pool)
states=unique(pool(:,{'a0','loc0','lfw0'}),'rows');
states=sortrows(states,{'a0','loc0','lfw0'});
n=height(states);candidate=zeros(n,1);observed=zeros(n,1);unobserved=zeros(n,1);
for ii=1:n
    mask=pool.a0==states.a0(ii)&pool.loc0==states.loc0(ii)& ...
        pool.lfw0==states.lfw0(ii);
    candidate(ii)=sum(mask);
    observed(ii)=sum(mask & as_logical(pool.is_observed_candidate));
    unobserved(ii)=sum(mask & as_logical(pool.is_unobserved_candidate));
end
T=addvars(states,candidate,observed,unobserved,'NewVariableNames', ...
    {'candidate_count','observed_count','unobserved_count'});
end

function selected = append_state(selected,ordered,reason)
if isempty(selected)
    used=false(height(ordered),1);
else
    used=ismember(ordered(:,{'a0','loc0','lfw0'}), ...
        selected(:,{'a0','loc0','lfw0'}),'rows');
end
idx=find(~used,1);
if isempty(idx),error('Could not find a distinct representative state.');end
row=ordered(idx,{'a0','loc0','lfw0','candidate_count', ...
    'observed_count','unobserved_count'});
row.state_selection_rule=reason;
if width(selected)==0
    selected=row;
else
    selected=[selected;row]; %#ok<AGROW>
end
end

function T = aggregate_main_paths(mainSample,a0,loc0,lfw0)
sub=mainSample(mainSample.a0==a0 & mainSample.loc0==loc0 & ...
    mainSample.lfw0==lfw0,:);
if height(sub)~=15000
    error('Expected 15000 main-sample rows for state (%g,%g,%g).',a0,loc0,lfw0);
end
key=table(double(sub.a0),double(sub.loc0),double(sub.lfw0), ...
    double(sub.a_W1),double(sub.loc_W1),double(sub.lfw_W1), ...
    double(sub.a_W2),double(sub.loc_W2),double(sub.lfw_W2), ...
    double(sub.a_W3),double(sub.loc_W3),double(sub.lfw_W3), ...
    'VariableNames',{'a0','loc0','lfw0','a1','loc1','lfw1', ...
    'a2','loc2','lfw2','a3','loc3','lfw3'});
[G,keyTable]=findgroups(key);
frequency=splitapply(@numel,double(sub.path_probability),G);
pMin=splitapply(@min,double(sub.path_probability),G);
pMax=splitapply(@max,double(sub.path_probability),G);
T=addvars(keyTable,frequency,pMin,pMax,'NewVariableNames', ...
    {'frequency','path_probability_min','path_probability_max'});
T.path_probability=T.path_probability_min;
end

function row = make_selection_row(selectionId,stateId,stateRule,source,rule,T, ...
    candidateId,frequency,weight,status)
row={selectionId,stateId,stateRule,source,rule,double(candidateId), ...
    double(T.a0),double(T.loc0),double(T.lfw0),double(T.a1),double(T.loc1), ...
    double(T.lfw1),double(T.a2),double(T.loc2),double(T.lfw2),double(T.a3), ...
    double(T.loc3),double(T.lfw3),double(T.path_probability),double(frequency), ...
    double(weight),status};
end

function row = make_probability_row(selectionId,source,frequency,weight,pMin,pMax, ...
    shouldTrace,mainOverlap,reportedWeight,config)
if source=="unobserved_candidate"
    tracePass=~mainOverlap;
    identityPass=weight==0 && reportedWeight==0;
else
    tracePass=frequency>0;
    identityPass=abs(weight-reportedWeight)<=config.probabilityTolerance;
end
row={selectionId,source,double(frequency),double(weight),double(reportedWeight), ...
    double(weight-reportedWeight),double(pMin),double(pMax),double(pMax-pMin), ...
    logical(shouldTrace),logical(mainOverlap),logical(tracePass), ...
    logical(identityPass)};
end

function names = selection_variable_names()
names={'selection_path_id','state_selection_id','state_selection_rule', ...
    'source_category','path_selection_rule','candidate_pool_unique_path_id', ...
    'a0','loc0','lfw0','a1','loc1','lfw1','a2','loc2','lfw2', ...
    'a3','loc3','lfw3','path_probability','observed_frequency', ...
    'empirical_weight','nominal_inclusion_status'};
end

function names = probability_variable_names()
names={'selection_path_id','source_category','main_sample_frequency', ...
    'assigned_empirical_weight','reported_empirical_weight', ...
    'empirical_weight_error','path_probability_min','path_probability_max', ...
    'path_probability_range','should_trace_to_main','main_sample_overlap', ...
    'traceability_pass','probability_identity_pass'};
end

function keys=physical_keys(T)
keys=string(compose('%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d', ...
    T.a0,T.loc0,T.lfw0,T.a1,T.loc1,T.lfw1,T.a2,T.loc2,T.lfw2, ...
    T.a3,T.loc3,T.lfw3));
end

function values=as_logical(values)
if islogical(values),return;end
if isnumeric(values),values=values~=0;else
    text=lower(strtrim(string(values)));values=text=="true"|text=="1";
end
end

function require_vars(T,names,fileName)
for ii=1:numel(names)
    if ~ismember(names{ii},T.Properties.VariableNames)
        error('%s missing required field %s.',fileName,names{ii});
    end
end
end
