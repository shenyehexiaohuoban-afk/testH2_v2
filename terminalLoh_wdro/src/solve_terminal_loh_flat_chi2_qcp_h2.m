function sol = solve_terminal_loh_flat_chi2_qcp_h2( ...
        Dperiod, Aperiod, Cperiod, q, Cap, M, gamma, eta, config)
%SOLVE_TERMINAL_LOH_FLAT_CHI2_QCP_H2 Production flat chi-square interface.
if nargin < 9, config = struct(); end
if eta <= 1e-14
    sol = solve_terminal_loh_saa_h2( ...
        Dperiod, Aperiod, Cperiod, q, Cap, M, gamma, config);
    sol.mode = "FLAT_CHI2_ETA_ZERO_DIRECT_SAA";
    return;
end
sol = solve_terminal_loh_flat_chi2_core_h2( ...
    Dperiod, Aperiod, Cperiod, q, Cap, M, gamma, eta, config);
end
