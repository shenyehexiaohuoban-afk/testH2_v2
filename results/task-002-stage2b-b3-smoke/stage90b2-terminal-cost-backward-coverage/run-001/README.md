# Stage90B2 terminal cost and backward coverage diagnostic

This is a read-only diagnostic run against Stage90B `run-004`:

- source checkpoint run-004 commit: `d968d9319d0f82e1fe8fe9e189691b25119b6c01`;

- active Base-Pmax Stage90B checkpoint, terminal recourse `K=160 kg`, reserve penalty `1000 yuan/kg`;
- no retraining, no 10,000-path OOS, no parameter or model changes;
- active hourly/terminal HTT cost source and `c0` identity audit;
- iteration-5 aggregate shipment-cost reconstruction with explicit directed-OD identifiability bounds;
- 35 saved backward TerminalLOH states re-evaluated with the shared terminal LP;
- old `DIRECT_GAP` value/subgradient paired against terminal recourse value/subgradient.

The directed iteration-5 split is intentionally not fabricated: run-004 saved total shipment and shipping cost, but not the OD vector. The aggregate identifies the tied Site2/Site3 minimum-cost pair; the two symmetric directions are reported with `[0, total_ship_kg]` bounds.

Final labels are recorded in `stage90b2_summary_zh.md` and `terminal_cost_semantics.md`; all QA checks are in `qa_summary.csv`.
