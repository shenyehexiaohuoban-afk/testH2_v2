function [demandHourly,demandStage,demand48,meta] = map_normal_demand_48h_h2(params,t)
%MAP_NORMAL_DEMAND_48H_H2 Map the 24 h demand source to six 8 h stages.

if t<1 || t>6 || t~=floor(t)
    error('map_normal_demand_48h_h2:BadStage','Operating stage must be an integer in 1..6.');
end
if ~isfield(params,'NearStageInput') || ~isfield(params.NearStageInput,'NormalDemand')
    error('map_normal_demand_48h_h2:MissingSource','NearStageInput.NormalDemand is required.');
end
source=params.NearStageInput.NormalDemand;
required={'stage_dt_h','stage_template_kg','hourly_kg','daily_total_by_site_kg'};
for q=1:numel(required)
    if ~isfield(source,required{q})
        error('map_normal_demand_48h_h2:MissingField','Missing NormalDemand.%s.',required{q});
    end
end
sourceDt=double(source.stage_dt_h);
template=double(source.stage_template_kg);
sourceHourly=double(source.hourly_kg);
daily=double(source.daily_total_by_site_kg(:));
if sourceDt~=6 || ~isequal(size(template),[params.Ni,4]) || ...
        ~isequal(size(sourceHourly),[params.Ni,24]) || numel(daily)~=params.Ni
    error('map_normal_demand_48h_h2:BadSourceShape', ...
        'Expected dt=6, template Ni-by-4, hourly Ni-by-24, and Ni daily totals.');
end
if any(~isfinite(template),'all') || any(template<0,'all') || ...
        any(~isfinite(sourceHourly),'all') || any(sourceHourly<0,'all')
    error('map_normal_demand_48h_h2:BadSourceValue','Demand data must be finite and nonnegative.');
end

sourceBlockSums=zeros(params.Ni,4);
for block=1:4
    sourceBlockSums(:,block)=sum(sourceHourly(:,(block-1)*6+(1:6)),2);
end
blockError=max(abs(sourceBlockSums-template),[],'all');
dailyError=max(abs(sum(sourceHourly,2)-daily));
if blockError>1e-10 || dailyError>1e-10
    error('map_normal_demand_48h_h2:SourceConservation', ...
        'Hourly source does not reconstruct the four 6 h totals or daily totals.');
end
if size(params.D_normal,2)<8 || ...
        max(abs(params.D_normal(:,1:4)-template),[],'all')>1e-10 || ...
        max(abs(params.D_normal(:,5:8)-template),[],'all')>1e-10
    error('map_normal_demand_48h_h2:ActiveTemplateIdentity', ...
        'Active D_normal does not preserve the repeated four-column source template.');
end

if isfield(params,'demand_schema')
    demandSchema=string(params.demand_schema);
else
    demandSchema="original-hourly-24h-repeat-v1";
end
switch demandSchema
    case "original-hourly-24h-repeat-v1"
        profile24=sourceHourly;
        mapping='ORIGINAL_HOURLY_24H_REPEAT';
        policy='use_original_hourly_kg_24h_repeat';
        hourlySplit=NaN;
        sourceHourlyPreserved=true;
    case "six-hour-block-uniform-24h-repeat-v1"
        profile24=zeros(params.Ni,24);
        for block=1:4
            profile24(:,(block-1)*6+(1:6))=repmat(template(:,block)/6,1,6);
        end
        mapping='SIX_HOUR_BLOCK_DIVIDE_BY_6_24H_REPEAT';
        policy='compatibility_uniform_within_6h_block';
        hourlySplit=1/6;
        sourceHourlyPreserved=false;
    otherwise
        error('map_normal_demand_48h_h2:BadSchema', ...
            'Unsupported demand_schema %s.',demandSchema);
end
demand48=repmat(profile24,1,2);
globalHours=(t-1)*8+(1:8);
demandHourly=demand48(:,globalHours);
demandStage=sum(demandHourly,2);
meta=struct('source_stage_dt_h',sourceDt,'source_block_count',4, ...
    'source_hourly_available',true,'source_hourly_preserved',sourceHourlyPreserved, ...
    'demand_schema',char(demandSchema),'mapping',mapping,'demand_policy',policy, ...
    'global_hours',globalHours,'source_block_sum_max_error_kg',blockError, ...
    'source_daily_sum_max_error_kg',dailyError, ...
    'hourly_split_within_source_block',hourlySplit);
end
