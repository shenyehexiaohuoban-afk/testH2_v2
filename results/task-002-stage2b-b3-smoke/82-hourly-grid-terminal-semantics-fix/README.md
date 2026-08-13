# Stage-82 hourly-grid terminal semantics fix

- `run-001`: first complete smoke; PASS, but the direct terminal-parity probe used a zero-target lf=7 state.
- `run-002`: superseded strengthening run; zero inventory was used, but the same zero-target state still made the direct terminal probe weak.
- `run-003`: accepted. It mechanically selects the lf=7 state with maximum total TerminalLOH, proves nonzero hourly/legacy value and subgradient parity, verifies stage7-to-stage6 cut propagation, forward/backward, four-dimensional inventory cuts, inventory duals, and legacy regression.
- Stage-80 regression is separately archived as `80-hourly-grid-voltage-range-smoke/run-003`; its lightweight accepted diagnostics match Stage-80 `run-002` except that the rerun writes three additional integrated-smoke detail lines already supported by the accepted workspace/log record.

No training, formal OOS, Markov change, TerminalLOH change, commit, or push was performed.
