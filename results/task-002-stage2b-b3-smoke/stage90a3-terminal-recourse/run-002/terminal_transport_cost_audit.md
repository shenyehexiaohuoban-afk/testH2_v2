# Stage90A3 terminal transport cost audit

- Formal source: `C:\Users\chaos\Desktop\biye\test\testH2_v2\terminalLoh_wdro\current_w_mainline_stage88\msp_bridge\near_stage_msp_input_stage88_cap200_candidate.mat` -> `NearStageInput.HTT.site_to_site_base_cost_yuan_per_kg`.
- Base source semantics: `base_cost(i,j) = 0.2 * site_to_site_road_km(i,j)` yuan/kg.
- Active unit cost: `c0 + base_cost(i,j) * (1 + lambda_beta * beta_k)`, with `c0=0`, `lambda_beta=2`.
- Reported `unit_cost` is the maximum over Stage7 states `[63 71 79 87 95 103 111 119 127 135 143 151 159 167 175 183 191 199 207 215 223 231 239 247 255 263 271 279 287 295 303 311 319 327 335]`; beta range is `[0.111428571429, 0.857142857143]`.
- Terminal capacity is fixed independently at `K_terminal=160 kg`; beta does not block OD and does not degrade K.
- Candidate shortage comparison penalty: `1000 yuan/kg`; all 12 directed OD costs are strictly below it.
- Source lookup SHA-256: `2fa1958944110701239a109ebf46d959324a351f2f27c1c3fbd62f333066eaa8`.
- CSV columns include origin, destination, distance, unit_cost, cost_formula, and beta_role.
- min/mean/max terminal unit cost: `17.3714285714 / 50.2946042215 / 61.2942623543 yuan/kg`.
