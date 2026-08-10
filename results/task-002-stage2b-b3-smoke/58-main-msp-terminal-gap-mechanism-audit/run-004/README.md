# Step-05B-1 TerminalLOH gap mechanism audit

- Source: `C:\Users\chaos\Desktop\biye\test\testH2_v2\results\task-002-stage2b-b3-smoke\57-main-msp-converged-terminal-loh-ab\run-003`
- Scope: read-only saved-policy/OOS mechanism audit; no MSP retraining and no parameter or TerminalLOH modification.
- Both saved policies are replayed on the exact protected 10000-by-8 OOS path table with decision storage enabled only in memory.
- `objective_without_terminal_gap_penalty` is diagnostic only and is not a new optimization objective.
- Historical coefficients 200 and 2000 remain unchanged; 1283.205 is not used.
- See `step05b1_judgment.txt` for the bounded A/B/C/D conclusion.
