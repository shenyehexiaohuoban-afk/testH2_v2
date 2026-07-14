# W3 Transition Candidate Audit

- task_id: `task-001`
- step_id: `01-w3-transition-audit`
- run_id: `run-001`
- status: `PASS`
- MATLAB command: `cd('C:/Users/chaos/Desktop/biye/test/testH2_v2'); run('terminalLoh_wdro/src/run_stage2a2_W3_transition_audit_h2.m');`
- PASS count: 44
- FAIL count: 0

## Intensity Candidate

- a=2: enhancement 0.06 -> 0.012; weakening 0.11 -> 0.142; stay 0.83 -> 0.846.
- a=3: enhancement 0.25 -> 0.05; weakening 0.15 -> 0.283333333333; stay 0.6 -> 0.666666666667.
- a=4: enhancement 0.28 -> 0.056; weakening 0.04 -> 0.189333333333; stay 0.68 -> 0.754666666667.
- a=5: enhancement 0.03 -> 0.006; weakening 0.18 -> 0.196; stay 0.79 -> 0.798.
- a=6: 6->5=0.60 and 6->6=0.40.

## Location Candidate

- delta kernel: -3:0.04, -2:0.10, -1:0.22, +0:0.18, +1:0.28, +2:0.13, +3:0.05
- maximum self-loop probability: 0.333333333333 at loc=10.
- boundary targets are deleted and remaining mass is renormalized; no clamping is used.

## Lfw Candidate

- base backward/stay/forward probabilities: 0.10/0.20/0.70.
- lfw backward motion is spatial trajectory variation, not time reversal or damage recovery.
- y = -89.9999703886000 + lfw * 40.

## Window and Scope

- W1/W2/W3 are three one-hour time windows; Hres=3 h.
- loc determines x and lfw determines y; W does not replace lfw.
- P=20 is only the legacy diagnostic sample count, not the full path count.
- legacy files unchanged: 1.
- candidate probabilities are transparent engineering candidates and are not calibrated to real typhoon observations or finalized by the user.
- formal path generation is not connected.
- B3, WDRO, Gurobi, MSP, Foundation, and Persistence were not run.
