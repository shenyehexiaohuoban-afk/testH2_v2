function audit_stage81_pv_diagnostic_shapes_h2()
%AUDIT_STAGE81_PV_DIAGNOSTIC_SHAPES_H2 Validate diagnostic-only PV dimensions.
rootDir = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(rootDir, 'hourly_grid_h2'));
data = load_hourly_grid_data_h2(rootDir, ...
    struct('vmin_pu', 0.90, 'vmax_pu', 1.10));
tauVec = 1:8;
pvCapacityBySite = data.pv_cap_kw(:);
pvProfileByHour = data.phi48(tauVec(:)).';
available = pvCapacityBySite * pvProfileByHour;
assert(isequal(size(pvCapacityBySite), [4, 1]));
assert(isequal(size(pvProfileByHour), [1, 8]));
assert(isequal(size(available), [4, 8]));
assert(max(abs(sum(available, 2) - ...
    data.pv_cap_kw(:) * sum(data.phi48(tauVec)))) <= 1e-12);
fprintf('STATUS=PASS\n');
fprintf('pv_cap_kw_size=%s\n', mat2str(size(pvCapacityBySite)));
fprintf('pv_profile_size=%s\n', mat2str(size(pvProfileByHour)));
fprintf('pv_available_size=%s\n', mat2str(size(available)));
fprintf('semantics=site_by_hour\n');
end
