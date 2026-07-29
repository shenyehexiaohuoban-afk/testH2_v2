# Frozen model assumptions

- First stage: one shared `T=[T1,T2,T3,T4]` per initial state.
- T meaning: optimized pre-disaster reserve/service-capacity target.
- Second-stage scenario: `xi_r={D_r^tau,A_r^tau,C_r^tau}_{tau=1,2,3}`.
- Inputs: D, A, and C. Decisions: y and u.
- Full scenario information: W1-W3 recourse is optimized jointly.
- W1 may use W2/W3 information.
- Shared reserve: `sum_{tau,n} y_{r,tau,i,n} <= T_i`.
- No per-period T reset and no physical inventory sharing across alternative scenarios.
- No disaster-time replenishment, recovery, or additional procurement.
- No advance service, shortage backlog, or node-side inter-period inventory.
- No scenario tree, common-history operating variables, or nonanticipativity constraints.
- This is not a strict multistage sequential-revelation model.
