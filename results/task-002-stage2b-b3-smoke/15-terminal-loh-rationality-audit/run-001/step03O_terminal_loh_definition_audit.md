# Step-03O TerminalLOH Definition Audit

## Confirmed mathematical variable

The four variables `T_i` are created as the first four LP variables in `terminalLoh_wdro/src/solve_wdro_terminal_loh_lp_h2.m:40-42`. They are nonnegative because the common lower-bound vector is initialized to zero at lines 59-60.

For each consequence atom s and site i, `sum_n y^s_{i,n} <= T_i` is implemented at lines 103-113. Therefore T_i is the site-level TerminalLOH reserve/service-volume limit available to that atom. It is not a realized shortage and is not automatically the final MSP inventory state.

Increasing T_i enlarges the feasible served-hydrogen volume at site i. Served flow is also bounded by reachability and node demand through `y^s_{i,n} <= A^s_{i,n} D^s_n` at lines 63-69. Demand balance `sum_i y^s_{i,n}+u^s_n=D^s_n` is at lines 90-101, so useful additional T can reduce unmet demand u.

## Bounds and source

The accepted tank capacities are [300 200 100 150] kg from `data/yuanqi/near_stage_msp_input.mat:NearStageInput.HydrogenDevice.tank_cap_kg`, loaded in `run_stage3k_wdro_integration_scaling_h2.m:214-217` and `build_terminal_loh_wdro_from_joint_samples_h2.m:222-228`.

The WDRO capacity fraction is 0.8 (`run_stage3k_wdro_integration_scaling_h2.m:228-229`; default at `build_terminal_loh_wdro_from_joint_samples_h2.m:185-186`). Thus `Cap=fraction*tank_capacity=[240 160 80 120]` kg.

The solver applies `ub(T)=Cap` at `solve_wdro_terminal_loh_lp_h2.m:59-62`. Therefore `[240,160,80,120]` is exactly the four-site upper-bound vector, not an incidental interior solution.

## Objective and loss coupling

The objective is `gamma*sum_i T_i + rho*lambda + (1/R)*sum_r alpha_r`, implemented at `solve_wdro_terminal_loh_lp_h2.m:53-57`.

Here gamma=2 and M=2000 from `NearStageInput.Cost.reserve_shortage_penalty_yuan_per_kg`. The project documentation explicitly describes gamma as a small TerminalLOH holding weight used to avoid filling every site to capacity (`build_terminal_loh_wdro_from_joint_samples_h2.m:588`).

Scenario loss satisfies `L_s >= sum_{i,n} Ceff^s_{i,n} y^s_{i,n} + M*sum_n u^s_n` at `solve_wdro_terminal_loh_lp_h2.m:115-131`. Wasserstein dual rows `alpha_r + lambda*d(r,s) >= L_s` are created at lines 133-144.

Consequently, larger T can reduce shortage loss only when additional reachable service is useful, while every additional kg of T incurs gamma. No constraint requires T to increase with rho. The optimal value is expected to be nondecreasing in rho, but the optimizer T itself may move in either direction as the dual tradeoff changes.

## Scope

This audit reads the accepted formulation and runs isolated secondary/fixed-T experiments. It does not modify the formal solver, constraint-generation algorithm, MSP, or frozen data.
