function value = get_htt_base_service_cost_h2(params)
%GET_HTT_BASE_SERVICE_COST_H2 Canonical active HTT base service-cost contract.
if ~isstruct(params) || ~isfield(params, 'htt_base_service_cost_yuan_per_kg')
    error('get_htt_base_service_cost_h2:MissingField', ...
        'params.htt_base_service_cost_yuan_per_kg is required.');
end
value = params.htt_base_service_cost_yuan_per_kg;
if ~isscalar(value) || ~isfinite(value) || value < 0
    error('get_htt_base_service_cost_h2:BadValue', ...
        'HTT base service cost must be a finite nonnegative scalar.');
end
end
