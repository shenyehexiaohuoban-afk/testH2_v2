function config = load_formal_b3_wind_config_h2(fileName,requestedMode)
%LOAD_FORMAL_B3_WIND_CONFIG_H2 Load and validate formal B3 wind modes.

if nargin<1||strlength(string(fileName))==0
    thisDir=fileparts(mfilename('fullpath'));
    fileName=fullfile(fileparts(thisDir),'config','formal_b3_wind_modes.csv');
end
if ~isfile(fileName),error('Formal B3 wind configuration is missing: %s',fileName);end
T=readtable(fileName,'TextType','string');
required={'wind_mode','is_default','intensity_level','distribution','lower_mps', ...
    'mode_mps','upper_mps','stage_quantile_rule','random_layer','upper_bound_role'};
for ii=1:numel(required)
    if ~ismember(required{ii},T.Properties.VariableNames)
        error('Formal B3 wind configuration is missing field %s.',required{ii});
    end
end

expectedModes=["fixed_representative","stagewise_random_triangular"];
if ~isequal(sort(unique(T.wind_mode)),sort(expectedModes(:)))
    error('Formal B3 wind configuration must contain exactly the two accepted modes.');
end
for mode=expectedModes
    q=sortrows(T(T.wind_mode==mode,:),'intensity_level');
    if height(q)~=6||~isequal(double(q.intensity_level),(1:6).')
        error('Wind mode %s must define intensity levels 1 through 6 exactly once.',mode);
    end
    if numel(unique(logical(q.is_default)))~=1
        error('Wind mode %s has inconsistent default flags.',mode);
    end
    if any(~isfinite(q.lower_mps)|~isfinite(q.mode_mps)|~isfinite(q.upper_mps))|| ...
            any(q.lower_mps>q.mode_mps|q.mode_mps>q.upper_mps)
        error('Wind mode %s has invalid distribution parameters.',mode);
    end
end

defaultModes=unique(T.wind_mode(logical(T.is_default)));
if numel(defaultModes)~=1||defaultModes~="stagewise_random_triangular"
    error('Exactly one formal default mode is required: stagewise_random_triangular.');
end
if nargin<2||strlength(string(requestedMode))==0,requestedMode=defaultModes;end
requestedMode=string(requestedMode);
if ~ismember(requestedMode,expectedModes),error('Unsupported formal B3 wind mode: %s',requestedMode);end

selected=sortrows(T(T.wind_mode==requestedMode,:),'intensity_level');
fixed=sortrows(T(T.wind_mode=="fixed_representative",:),'intensity_level');
random=sortrows(T(T.wind_mode=="stagewise_random_triangular",:),'intensity_level');
if any(fixed.distribution~="fixed")||any(fixed.lower_mps~=fixed.mode_mps|fixed.mode_mps~=fixed.upper_mps)
    error('fixed_representative must retain deterministic representative values.');
end
if random.distribution(1)~="fixed"||any(random.distribution(2:6)~="triangular")|| ...
        any(random.stage_quantile_rule~="independent_q_each_W_stage")|| ...
        any(random.random_layer~="second_layer_B3_joint_consequence")
    error('stagewise_random_triangular does not match the accepted sampling definition.');
end
if random.lower_mps(6)~=51||random.mode_mps(6)~=55.5||random.upper_mps(6)~=60|| ...
        random.upper_bound_role(6)~="project_computational_limit_not_official_or_physical_upper_bound"
    error('The a=6 project-bounded triangular definition is invalid.');
end

config=struct();config.file=string(fileName);config.table=T;
config.defaultMode=defaultModes;config.activeMode=requestedMode;
config.availableModes=expectedModes;config.selected=selected;
config.fixedRepresentative=double(fixed.mode_mps);
config.randomLower=double(random.lower_mps);
config.randomMode=double(random.mode_mps);
config.randomUpper=double(random.upper_mps);
config.stagewiseIndependent=true;config.randomLayer="second_layer_B3_joint_consequence";
config.a6UpperRole=string(random.upper_bound_role(6));
end
