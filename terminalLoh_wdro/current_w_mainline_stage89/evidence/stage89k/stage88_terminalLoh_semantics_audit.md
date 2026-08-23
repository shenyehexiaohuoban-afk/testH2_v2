# Stage88 formal TerminalLOH semantics audit for Stage-89K

Audit status: **PASS**. This document was completed before the Stage-89K solver was written.

## Accepted identity

- Current accepted TerminalLOH source: Stage88A CAP200 SAA/DRO, version node `W24` for the current DRO table and `W23` for the accepted SAA comparator.
- Accepted result: `results/task-002-stage2b-b3-smoke/88A-h2-bank-terminal-loh-site4-capacity-sensitivity/run-001/`.
- Frozen solver snapshot: `terminalLoh_wdro/current_w_mainline_stage88/src_snapshot/terminalLoh_wdro/src/run_step04CC6_35state_case.py`.
- Accepted solver SHA-256: `7f18983c6211dd6de10ab242fa94627eaded32d4401ba6ec920f809cd3ec2aab`.
- Stage88 case adapter SHA-256: `0d4813e85e05cbdb741f65f4e51cb423551029254e11c686ea4106a556c8c77f`.

## Mechanical semantics

| Item | Accepted Stage88 meaning | Stage-89K freeze |
|---|---|---|
| Decision `T` | Four nonnegative first-stage site inventories, one value per site, shared by all scenarios | unchanged |
| Tank caps | `[300, 200, 100, 200]` kg | unchanged |
| Demand balance | Reachable service plus shortage equals each positive `(scenario,slice,node)` demand | only service is split into road and electrical channels |
| Inventory | For every scenario and site, total service over all 3 slices and nodes is at most `T_i` | one shared constraint for road plus electrical service |
| First-stage cost | `c_H2 * sum_i T_i` | unchanged |
| `c_H2` | `32.5213675213675 yuan/kg` | unchanged |
| Shortage loss | `M_H2 * shortage` | unchanged |
| `M_H2` | `1283.205 yuan/kg` | unchanged |
| SAA weighting | Exact-group probability `q_g=multiplicity/15000`, normalized to sum one | unchanged |
| Pearson set | `p>=0`, `sum p=1`, `sum_g (p_g-q_g)^2/q_g <= eta` | unchanged |
| `eta` | `0.03` | unchanged |
| DRO implementation | Certified cutting-plane/decomposition master in `T`, fixed-`T` recourse LP, analytic active-set worst probability, LB/UB gate | unchanged architecture |
| Road `C` | Excluded from primary SAA objective and Pearson scenario loss; used only after optimal `T` in a strict secondary service-impedance solve that preserves scenario shortage | unchanged; applies only to road variables |
| `q_g` | Exact-group empirical mass, also used to reconstruct per-record mass in Stage88 diagnostics | unchanged |
| Solver | gurobipy 12.0.1, LPs, `Threads=1`, `FeasibilityTol=1e-9`, `OptimalityTol=1e-9` | unchanged |
| SAA method | Gurobi barrier (`Method=2`), time limit 1800 s | unchanged |
| DRO master | Gurobi LP, 60 s per master; max 150 iterations; total 7200 s | unchanged |
| Optimality gate | absolute gap `<=1e-4 yuan` or relative gap `<=1e-8` | unchanged |

`C` is not an RMB service cost in the primary objective and is not part of the Pearson loss. The FA-MSP terminal-gap penalty `1000` and ordinary shortage penalty `200` are absent from this accepted TerminalLOH solver and are therefore absent from Stage-89K.

## Authorized structural delta

Stage-89K changes only the recourse signature and service arcs from `(D,Aroad,C)` to the frozen Stage-89J `(Dres,Aroad,Aelec,C)` bank. Road and electrical variables are distinct; they share the same `T_i`; electrical service additionally obeys the static per-site/per-slice FC hydrogen cap read from Stage-89J metadata. No binary variable, nonlinear constraint, dynamic FC variable, power-flow constraint, probability change, economic change, or solver-tolerance change is authorized.
