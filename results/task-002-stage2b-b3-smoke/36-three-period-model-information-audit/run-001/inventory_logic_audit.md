# Inventory and temporal logic audit

## TerminalLOH

`idx.T` is allocated once as an `I=4` vector before scenario and period recourse variables. It is nonnegative, has upper bounds `[300,200,100,150] kg`, and enters the objective through `gamma*sum(T)`. There is no `T_r` or `T_tau`; each initial-state SAA solve returns one four-site vector.

The code therefore treats T as the common pre-event reserve/service-capacity decision. It is not a post-event remaining-inventory state, not reset by period, and not independently produced for each scenario.

## Shared three-period use

For every scenario r and site i, one row contains all `K*N` service variables and `-T_i`, implementing `sum_{tau,n} y_{r,tau,i,n} <= T_i`. W1 service consumes part of the same capacity available to W2 and W3. There is no per-period capacity reset.

Each scenario has its own recourse flows constrained by the common design T. There is no physical inventory transfer across alternative scenarios. No disaster-time replenishment, recovery, or inventory transition variable exists.

## Advance service and backlog

Each equality uses only `y_{r,tau,:,n}`, `u_{r,tau,n}`, and `D_{r,tau,n}`. A W1 service variable cannot satisfy W2 or W3 demand, so advance service is not allowed. Shortage `u_{r,tau,n}` is charged in its own period and never appears in a later balance, so shortage carryover/backlog is not allowed. There is no node-side storage variable.
