function modelLib = define_models_h2(params)
%DEFINE_MODELS_H2 Build ordinary non-terminal stage-state LP templates.
%
% Ordinary LPs are created only for states with a>1 and lf<Nc-1. Dissipated
% states, lf=Nc-1 LOH demand/check states, and lf=Nc zero-cost absorbing
% states are not ordinary production/transport LPs.

models = cell(params.T, params.K);

for t = 1:params.T
    baseModel = build_stage_model_h2(params, t);

    if t == 1
        if params.is_absorbing(params.k_init)
            error('define_models_h2:AbsorbingInitialState', ...
                'k_init = %d is absorbing.', params.k_init);
        end
        models{t, params.k_init} = baseModel;
        continue;
    end

    for k = 1:params.K
        if ~params.is_absorbing(k) && ~params.is_loh_demand_stage(k)
            models{t, k} = baseModel;
        end
    end
end

modelLib = struct();
modelLib.models = models;
end
