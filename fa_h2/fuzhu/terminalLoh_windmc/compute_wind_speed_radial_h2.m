function V = compute_wind_speed_radial_h2(rKm, VmaxMps, RmaxKm, B)
%COMPUTE_WIND_SPEED_RADIAL_H2 Simplified radial typhoon wind profile.

if RmaxKm <= 0
    error('compute_wind_speed_radial_h2:BadRmax', 'RmaxKm must be positive.');
end
if VmaxMps < 0
    error('compute_wind_speed_radial_h2:BadVmax', 'VmaxMps must be nonnegative.');
end

rKm = double(rKm);
V = zeros(size(rKm));
inside = rKm <= RmaxKm;
V(inside) = VmaxMps .* rKm(inside) ./ RmaxKm;

outside = ~inside;
safeR = max(rKm(outside), eps);
V(outside) = VmaxMps .* (RmaxKm ./ safeR) .^ B;
end
