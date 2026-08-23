# Stage89Q experiment definition

- Arm-A: terminal-gap penalty 1000 yuan/kg.
- Arm-B: terminal-gap penalty 1500 yuan/kg.
- Training: fresh, zero cuts, no warm start, seed 20260513, maximum compute budget 18000 seconds per arm.
- Order: Arm-A training, exit/hash; Arm-B training, exit/hash; Arm-A clean-load OOS; Arm-B clean-load OOS.
- OOS bank: accepted Stage89H loc4 ordered 10000-path bank, SHA-256 `6bf3d1190a402ded052b8d3d08ed369042236e151f562bdd9fd4db7b8ff386c6`.
- Model: Stage89J adopted W identity, Stage89K DRO TerminalLOH, eta 0.03, loc4, correct 6x8h hourly FA-MSP.
- Ordinary shortage penalty: 200 yuan/kg.
- Full mathematical convergence is not claimed from the fixed wall-clock budget.
