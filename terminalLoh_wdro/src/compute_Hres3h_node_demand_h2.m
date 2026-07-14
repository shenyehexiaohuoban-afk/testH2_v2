function DnodeKg = compute_Hres3h_node_demand_h2( ...
    P_loss_node_kW, sliceDurationH, etaFC, lhvKWhPerKg)
%COMPUTE_HRES3H_NODE_DEMAND_H2 Convert one slice lost load to kg-H2.

if sliceDurationH <= 0 || ~isscalar(sliceDurationH)
    error('compute_Hres3h_node_demand_h2:BadDuration', ...
        'sliceDurationH must be a positive scalar.');
end
if etaFC <= 0 || lhvKWhPerKg <= 0
    error('compute_Hres3h_node_demand_h2:BadConversion', ...
        'etaFC and lhvKWhPerKg must be positive.');
end
P_loss_node_kW = double(P_loss_node_kW);
if any(~isfinite(P_loss_node_kW(:))) || any(P_loss_node_kW(:) < 0)
    error('compute_Hres3h_node_demand_h2:BadLostLoad', ...
        'P_loss_node_kW must be finite and nonnegative.');
end

DnodeKg = P_loss_node_kW .* sliceDurationH ./ (etaFC .* lhvKWhPerKg);
end
