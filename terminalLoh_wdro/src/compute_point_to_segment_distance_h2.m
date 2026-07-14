function [d, t, cx, cy] = compute_point_to_segment_distance_h2(px, py, x1, y1, x2, y2)
%COMPUTE_POINT_TO_SEGMENT_DISTANCE_H2 Euclidean point-to-segment distance.
%
% Inputs x1/y1/x2/y2 may be vectors. px/py are scalar point coordinates.

vx = double(x2) - double(x1);
vy = double(y2) - double(y1);
wx = double(px) - double(x1);
wy = double(py) - double(y1);
den = vx.^2 + vy.^2;
t = zeros(size(den));
valid = den > 0;
t(valid) = (wx(valid) .* vx(valid) + wy(valid) .* vy(valid)) ./ den(valid);
t = min(max(t, 0), 1);
cx = double(x1) + t .* vx;
cy = double(y1) + t .* vy;
d = hypot(double(px) - cx, double(py) - cy);
end
