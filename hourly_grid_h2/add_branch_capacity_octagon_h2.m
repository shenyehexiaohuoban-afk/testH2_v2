function [A, b, rowInfo] = add_branch_capacity_octagon_h2(nvars, idx, data)
%ADD_BRANCH_CAPACITY_OCTAGON_H2 Add the frozen conservative LP octagon.

nL = data.n_branch;
A = zeros(8 * nL, nvars);
b = zeros(8 * nL, 1);
smax = data.branch_smax_mva * 1000; % kVA, matching kW/kVAr variables
a = data.branch_octagon_a;
bb = data.branch_octagon_b;

for ell = 1:nL
    rows = (ell - 1) * 8 + (1:8);
    p = idx.p_branch(ell);
    q = idx.q_branch(ell);
    A(rows(1), p) = 1;                  b(rows(1)) = a * smax;
    A(rows(2), p) = -1;                 b(rows(2)) = a * smax;
    A(rows(3), q) = 1;                  b(rows(3)) = a * smax;
    A(rows(4), q) = -1;                 b(rows(4)) = a * smax;
    A(rows(5), [p, q]) = [1, 1];        b(rows(5)) = bb * smax;
    A(rows(6), [p, q]) = [-1, -1];      b(rows(6)) = bb * smax;
    A(rows(7), [p, q]) = [1, -1];       b(rows(7)) = bb * smax;
    A(rows(8), [p, q]) = [-1, 1];       b(rows(8)) = bb * smax;
end

rowInfo = reshape(1:(8 * nL), 8, nL).';
end
