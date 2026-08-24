# Stage-89Q Pmax dual 10-iteration engineering smoke

Status: **PASS for both arms**. This is an engineering and early-mechanism smoke only. It is not a performance, convergence, candidate-adoption, wait-and-see, or terminal-reliability result.

1. Formal launcher lineage: `run_stage89q_penalty1000_vs1500_5h_hourly_h2.m`; executed task launcher: `run_stage89q_pmax_dual_10iter_smoke_h2.m`.
2. Full call chain is recorded in `01_preflight/runner_call_chain.md` and ends in the shared define/forward/backward/add-cut/checkpoint core.
3. Formal Base Pmax comes from `NearStageInput.HydrogenDevice.el_cap_kw`; the task-local launcher vector is the only candidate source.
4. Multiple active hard-coded candidate Pmax sources: **No**. Base vectors in gates are identity validation, not independent model inputs.
5. B0001 propagation from launcher through config/loader wrapper/model/bounds/forward/backward/checkpoint/reload: **PASS**.
6. B1011 propagation through the same levels: **PASS**.
7. Risk that config changed while model constraints retained Base values: **No**; every active aggregate and 4x8 hourly variable bound was inspected before and after forward/backward and after reload.
8. Fresh zero-cut start: **Yes for both**.
9. Exactly ten iterations: **Yes, 10/10 for both**, with every iteration retained.
10. Engineering runnable: **Yes for both**.
11. New voltage problem: B0001 `NO`, B1011 `NO` as an engineering diagnostic; this does not establish long-run policy risk.
12. Bus18 minima were `0.911291329` and `0.90895471` p.u.; a formal degradation claim needs a matched long-training/OOS Base comparison.
13. New line/substation problem: B0001 line/substation binding `False/False`; B1011 `False/False`.
14. Tank saturation hits: B0001 `0`, B1011 `0` on the deterministic diagnostic path; long-run prevalence is not identifiable.
15. Ordinary shortage diagnostic totals: B0001 `0` kg, B1011 `0` kg; no final tradeoff claim is made.
16. HTT: no engineering anomaly; maximum utilization `0.027236666/0.019924166` under the retained 160 kg/h beta semantics.
17. Added Pmax used above Base nameplate: B0001 `True`, B1011 `True`.
18. Larger capacity causing earlier heavy production: **not identifiable at 10 iterations**; the saved profiles are early signals only.
19. Production moving later: **not identifiable at 10 iterations**; late shares are `0/0` on one deterministic diagnostic path.
20. Early commitment, wait-and-see, terminal shortfall, 203 pure-location paths, and 118/152 quantity/mixed cohorts still require fresh long training plus formal OOS.
21. New blocking issue: **No for either arm**.
22. B0001 worth long training: **Yes** as an engineering recommendation only.
23. B1011 worth long training: **Yes** as an engineering recommendation only.
24. Both worth long training: **Yes**.
25. Can wait-and-see improvement be claimed now? **No.**
26. Can terminal reliability improvement be claimed now? **No.**

The comparison in `04_comparison/b0001_vs_b1011_smoke_comparison.csv` is `ENGINEERING / EARLY-MECHANISM SIGNAL ONLY` and must not be used for formal performance ranking.

```text
B0001_PMAX_PROPAGATION = PASS
B1011_PMAX_PROPAGATION = PASS
B0001_SMOKE_STATUS = PASS
B1011_SMOKE_STATUS = PASS
NEW_BLOCKING_ISSUE_B0001 = NO
NEW_BLOCKING_ISSUE_B1011 = NO
EARLY_WAIT_AND_SEE_SIGNAL_B0001 = NOT_IDENTIFIABLE
EARLY_WAIT_AND_SEE_SIGNAL_B1011 = NOT_IDENTIFIABLE
NEW_GRID_RISK_B0001 = NO
NEW_GRID_RISK_B1011 = NO
RECOMMEND_LONG_TRAINING = BOTH
FULLY_CONVERGED = NO
OOS_RUN = NO
```
