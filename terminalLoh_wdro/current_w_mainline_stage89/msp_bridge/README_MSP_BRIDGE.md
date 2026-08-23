# Stage89 adopted TerminalLOH → FA-MSP bridge

The default bridge loads the adopted Stage89K **DRO** table (`eta=0.03`) into the accepted Stage89F six-stage, eight-hour-per-stage hourly model. SAA is available only by an explicit `"saa"` request. Both tables are locked by version metadata, state/site ordering, capacity checks, and hard-coded SHA-256 identities.

The bridge keeps tank capacity `[300,200,100,200] kg`, electrolyzer Pmax `[300,200,120,150] kW`, and the accepted initial inventory `[58.04455704486949,50.30813793862475,25.262133442309338,33.02358084624278] kg`. Site4 is therefore **200 kg tank capacity** and **150 kW Pmax**. Initial inventory is not rescaled.

`NormalDemand.stage_dt_h=6` remains source-demand metadata only. Active runtime is `params.dt_h=8`; each of operating Stage1–6 contains eight one-hour IEEE33, P_EL, original H2 demand, production, inventory, directed continuous HTT, and PV blocks. Stage7 is analytic TerminalLOH; Stage8 is zero-cost absorbing.

Stage89M performs loader/model/cut/evaluation regression only. It does not train, evaluate OOS, generate a checkpoint, use Stage89G multi-location adaptation, or modify forward/backward mathematics.
