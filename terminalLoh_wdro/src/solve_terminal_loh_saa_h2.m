function sol = solve_terminal_loh_saa_h2( ...
        Dperiod, Aperiod, Cperiod, q, Cap, M, gamma, config)
%SOLVE_TERMINAL_LOH_SAA_H2 Production weighted-SAA interface.
if nargin < 8, config = struct(); end
sol = solve_terminal_loh_flat_chi2_core_h2( ...
    Dperiod, Aperiod, Cperiod, q, Cap, M, gamma, 0, config);
end
