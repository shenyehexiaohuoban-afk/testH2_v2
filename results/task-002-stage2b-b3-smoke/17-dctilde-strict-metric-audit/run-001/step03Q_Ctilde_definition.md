# Step-03Q Ctilde Definition and Model Scope

`A=1` means every demand-critical W1-W3 window has a feasible road path; `A=0` means at least one critical window is unreachable. Slow but open roads keep A=1 (`aggregate_W3_DAC_outcomes_h2.m:14-55`).
`C` is the mean current-road-state shortest-path impedance in km over reachable critical windows. Closures enter as infinite edge costs and slowdown uses `roadLength*(1+pClose)`, so C includes detours and nonclosed-road slowdown.

For one site-node feature, unreachable-unreachable has distance 0, reachable-reachable has `abs(C_r/C_bound-C_s/C_bound)`, and a reachability mismatch has distance kappa. The 132 feature distances are averaged.
The accepted old weights are read by calling `build_wdro_distance_matrix_h2(...,'DAC_maskedC',...)`, not hard-coded into the candidate: D/A/C=0.6/0.25/0.15. The new weights are w_D=0.6 and w_Ctilde=w_A+w_C=0.4.
C_bound=357.1526447416079 km. Candidate distances are median-matched to the accepted old distance only for this audit; unscaled statistics are retained.

A is removed only as a separate ground-distance component. It remains in the supply model: `y_i,n^s <= A_i,n^s D_n^s` (`solve_wdro_terminal_loh_lp_h2.m:31-52`) and thus A=0 forbids service. C remains the service-cost coefficient (`solve_wdro_terminal_loh_lp_h2.m:82-107`). A has not been deleted from the model.
Full capacity is [300,200,100,150] kg. Shortage penalty source: `NearStageInput.Cost.reserve_shortage_penalty_yuan_per_kg`.

Selvi, Belbasi, Haugh, and Wiesemann (2022), `Wasserstein Logistic Regression with Mixed Features`, NeurIPS, motivates separate treatment of categorical and continuous feature differences. Step-03Q adapts that idea to binary reachability plus continuous reachable road impedance; it does not change the loss model or write the candidate into the formal WDRO default.
