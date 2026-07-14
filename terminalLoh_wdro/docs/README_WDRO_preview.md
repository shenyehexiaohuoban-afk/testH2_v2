# WDRO-TerminalLOH Offline Preview

This folder is an independent offline prototype for WDRO-TerminalLOH. It is
not part of the MSP main loop, and it does not modify `params.TerminalLOH`,
`forward`, `backward`, or cut generation.

## Scope

The current phase uses the existing single-window joint scenario table:

`output_h2/wind_terminal_loh_preview/riskcap_mean/joint_scenario_site_node.csv`

This input is equivalent to `W=1`. It is only a WDRO-LP and data-interface
prototype. It does not implement the future three-window look-ahead after
`lf=7`, and it does not add any formal `terminal_load_mode`.

## Data Mapping

For each state `k=(a,loc,lf=7)` and scenario `s`:

- `D_n^s(k) = H_node_kg_s`
- `A_{i,n}^s(k) = reachable`
- `C_{i,n}^s(k) = scenario_service_cost`

`D` is the node hydrogen demand vector. `A` is the binary reachability matrix
from 4 hydrogen sites to 33 nodes. `A=1` means a feasible service path exists;
`A=0` means fully unreachable. Do not encode a slow but passable road as
`A=0.3`.

`C` is the service cost, travel impedance, or travel time matrix conditional
on reachability. If a road is still usable but becomes slow because of
flooding, congestion, fallen trees, detours, or speed limits, keep `A=1` and
increase `C`.

`H_node_kg_s` is repeated on the four site rows for the same
`scenario_id,node_id`. The builder checks that these repeated values match and
takes each node demand only once when forming `D`.

The current CSV stores non-finite service cost on unreachable site-node pairs.
The LP sets those coefficients to zero because `y_{i,n}^s` is already forced to
zero by reachability. The main distance does not use `C`.

## Finite Scenario Support

For each state `k`, the Wasserstein ambiguity set is built on the finite
discrete support:

`Xi_k = {xi^1(k), xi^2(k), ..., xi^R(k)}`

Transport moves probability mass between complete consequence atoms. It does
not continuously perturb individual reachability entries. Therefore the model
does not create physically meaningless half-reachable states such as
`A_{i,n}=0.3`.

## Distance Modes

Default run modes:

- `D_only`
- `DA`
- `DAC_maskedC`

`DA` is the main method. It uses:

`xi^s = (D^s, A^s)`

`d_rs = w_D * d_D(r,s) + w_A * d_A(r,s)`

where:

`d_D(r,s) = ||D^r - D^s||_1 / (D_max + eps)`

`d_A(r,s) = ||A^r - A^s||_1 / (A_max + eps)`

Default DA weights are `w_D=0.7` and `w_A=0.3`.

`C` is excluded from the main distance to avoid counting an unreachable event
once through `A` and again through a large or non-finite service cost.

`DAC_maskedC` is an extension:

`xi^s = (D^s, A^s, C^s)`

It compares `C` only on site-node pairs reachable in both scenarios. If one
scenario is reachable and the other is unreachable, that difference is already
represented by the `A` term and is not counted again in the `C` term.
Thus unreachable-side `Inf` or large-M service costs do not enter the masked
`C` distance.

Default `DAC_maskedC` weights are `w_D=0.6`, `w_A=0.25`, and `w_C=0.15`.

`DAC` is retained only as a legacy/unmasked compatibility mode if explicitly
requested. It is not recommended as the formal main method.

## Rho

`rho` is the Wasserstein ball radius. It controls how far the true distribution
may deviate from the empirical distribution on the finite support.

`rho=0` degenerates to the empirical sample average distribution/SAA for the
selected distance mode and support. Larger `rho` allows probability mass to
shift toward higher-loss scenarios and usually makes the model more
conservative, but with the current small `R=10` prototype it does not guarantee
monotone increases in `TerminalLOH_total`.

The radius should be selected by sensitivity analysis and out-of-sample tests,
not only by manual tuning.

## LP

For each state, each `rho`, and each distance mode, the prototype solves one
LP with variables `T_i`, `y_{i,n}^s`, `u_n^s`, `L_s`, `lambda`, and `alpha_r`.

The objective is:

`min gamma * sum_i T_i + lambda * rho + sum_r p_r * alpha_r`, with `p_r=1/R`.

Capacity uses the RiskCap-Mean convention:

`Cap_i = capacity_fraction * tank_cap_kg_i`, default `capacity_fraction=0.8`.

The shortage penalty `M` is read from
`reserve_shortage_penalty_yuan_per_kg` when available. The default `gamma` is
`0.001*M`. This `gamma` is a configurable small TerminalLOH holding weight used
to avoid filling all sites to capacity; it is not the MSP production cost.

## Run

From MATLAB:

```matlab
cd('C:/Users/chaos/Desktop/biye/test/testH2_v2');
run('terminalLoh_wdro/src/run_terminal_loh_wdro_preview_h2.m');
```

The script temporarily adds the project root and this folder to the MATLAB
path for the current session. It also tries `GUROBI_HOME/matlab` and local
Gurobi candidates for the Gurobi MATLAB interface. No permanent MATLAB path
change is made.

## Outputs

New DA-update outputs are written to:

`terminalLoh_wdro/output/stage1_single_window_DA_update/`

Older stage-1 outputs remain under:

`terminalLoh_wdro/output/stage1_single_window/`

Files:

- `terminal_loh_by_state_WDRO.csv`
- `terminal_loh_allocation_WDRO.csv`
- `wdro_distance_matrix_summary.csv`
- `wdro_rho_sensitivity_summary.csv`
- `WDRO_README.txt`

The distance summary records nonnegativity-related diagnostics, diagonal and
symmetry checks, binary reachability checks, unreachable-cost diagnostics, and
the share of scenario pairs whose masked `C` term actually compares common
reachable site-node pairs.

## Current Limits

The current `joint_scenario_site_node.csv` has only `R=10` scenarios per state.
It is suitable for prototype validation only. Formal follow-up should first
generate a `W=3` `lookahead_scenario_site_node.csv`, then rerun this WDRO
module on that look-ahead scenario table and compare `D_only`, `DA`, and
`DAC_maskedC` using out-of-sample tests.
