# Step-05A1 dual TerminalLOH lookup smoke

Status: **A / PASS**. Accepted run: `run-001`.

The safe native launcher ran the unchanged FA-MSP algorithm twice with seed 20260513 and a 300-second training limit. The only model input difference was the frozen TerminalLOH table: SAA versus Pearson chi-square eta=0.03.

- SAA: 164 iterations, 301.200 s training, final LB 18495.771863561, 205543 added cut rows.
- eta=0.03: 163 iterations, 300.076 s training, final LB 21676.853155633, 204282 added cut rows.
- First-cut stage-state models changed: 1156.
- Terminal gap penalty remained 2000 yuan/kg in both cases.
- `state7` is an intentional exact-zero negative control. Its lookup, terminal value, and subgradient match exactly.
- The zero-state warnings in the SAA selected-path diagnostics are expected and arise from that frozen negative control.
- Native workspaces and detailed OOS tables remain local; only lightweight audits are intended for Git.

This smoke validates data propagation, not policy superiority. A formal one-hour A/B is the next step.
