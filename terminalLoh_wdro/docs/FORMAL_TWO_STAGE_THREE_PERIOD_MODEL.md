# Formal Two-Stage Three-Period Operational Model

## Frozen Name

中文正式名称：**两阶段、完整场景信息下的三时间段运行模型**。

English formal name: **two-stage three-period operational model under full scenario information**.

This modeling decision was explicitly confirmed for Step-03Z-B on 2026-07-29. The verified implementation baseline is commit `68635008b3431f1806fafb932bf17d4b349ebf28`.

The three operational periods are physical periods inside second-stage recourse. They are not three sequential stochastic-programming stages.

## First Stage

For each initial state, the first stage optimizes one four-site TerminalLOH vector:

`T = [T_1, T_2, T_3, T_4]`.

- `T_i` is the pre-disaster hydrogen reserve or service-capacity target at site `i`.
- `T` is an optimization variable obtained from the complete SAA or WDRO problem; it is not manually fixed by the model definition.
- All consequence scenarios under the same initial state share the same `T`.
- A scenario cannot have its own independent TerminalLOH vector.
- `T` is not realized post-disaster remaining inventory and is not reset by operational period.
- The frozen upper bounds are `[300, 200, 100, 150] kg`.

## Second Stage

Each consequence scenario is represented by

`xi_r = {D_r^tau, A_r^tau, C_r^tau}_{tau=1,2,3}`.

- `D_r^tau(n)` is node `n` hydrogen demand in period `tau`. It is scenario input data, not a decision variable.
- `A_r^tau(i,n)` is the period-specific reachability indicator from site `i` to node `n`.
- `C_r^tau(i,n)` is the period-specific reachable service impedance or service cost.
- `y_r^tau(i,n)` is the optimized hydrogen service from site `i` to node `n` in period `tau`.
- `u_r^tau(n)` is optimized unmet demand at node `n` in period `tau`.

For a fixed complete scenario, all W1-W3 `y` and `u` variables are optimized jointly in one recourse LP. W1 operating decisions may therefore use the scenario's W2 and W3 demand, reachability, and service-cost information.

## Frozen Constraints

Period demand balance:

`sum_i y_r^tau(i,n) + u_r^tau(n) = D_r^tau(n)`.

Reachability service bound:

`0 <= y_r^tau(i,n) <= A_r^tau(i,n) D_r^tau(n)`.

Shared three-period TerminalLOH:

`sum_{tau=1}^3 sum_n y_r^tau(i,n) <= T_i`.

The shared-capacity row is scenario-specific in its recourse flow but uses the one common first-stage `T_i`. Alternative scenarios do not physically share realized inventory with one another.

## Frozen Time And Inventory Logic

- W1, W2, and W3 jointly consume one `T_i`; no period receives a fresh copy.
- Hydrogen supplied in an earlier period consumes the reserve available to later periods.
- No disaster-time hydrogen replenishment, inventory recovery, or additional procurement is modeled.
- Period `tau` service can satisfy only period `tau` demand.
- Advance service for future-period demand is not allowed.
- Unmet demand is charged in its current period and is not carried to a later period.
- No node-side inter-period hydrogen inventory variable exists.

## Frozen Information Structure

The model uses full scenario information in second-stage recourse:

- all three periods of one scenario are available when its recourse is optimized;
- no scenario tree is constructed;
- no nonanticipativity constraints are imposed;
- scenarios with a common partial history are not required to share operating decisions;
- only the first-stage `T` vector is shared across scenarios.

Accordingly, this model must not be described as a three-stage stochastic program, a strict multistage sequential-revelation model, or a model with period-specific TerminalLOH decisions.

## Objective And Verified Parameters

The verified SAA objective is

`gamma * sum_i T_i + (1/R) * sum_r Q(T, xi_r)`,

where `Q` contains reachable service cost and shortage loss. The Step-03Y-F verified parameters remain:

- `gamma = 2`;
- equal empirical scenario weight `1/R`;
- shortage penalty `M = 2000`;
- capacity upper bounds `[300, 200, 100, 150] kg`;
- period-specific `C_r^tau` is used without temporal averaging in the period model.

This freeze records model meaning and terminology only. It does not modify SAA, WDRO, MSP, scenario generation, distance, rho, data, parameters, or any prior result.
