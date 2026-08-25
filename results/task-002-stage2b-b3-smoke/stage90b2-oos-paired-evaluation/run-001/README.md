# Stage90B2 paired OOS evaluation

- Read-only evaluation of saved run-004; no retraining or parameter changes.
- Source checkpoint commit: `d968d9319d0f82e1fe8fe9e189691b25119b6c01`.
- Same first 10000 rows of `data\OOS.csv` evaluated under TERMINAL_REDISTRIBUTION and DIRECT_GAP.
- This compares evaluators for the same recourse-trained policy; it is not a separately trained DIRECT_GAP baseline.

DIRECT_GAP mean = 59623.5679412 yuan/path; TERMINAL_REDISTRIBUTION mean = 58253.5557392 yuan/path; paired mean direct-minus-recourse = 1370.01220199 yuan/path.
Recourse-better paths = 530/10000 (0.053000); recourse-worse paths = 0; equal paths = 9470.
Recourse average terminal gap = 1.65548483293 kg/path; average physical shipping = 47.5567661382 yuan/path; recourse elapsed 649.211s; direct elapsed 608.928s.
Source run: `results\task-002-stage2b-b3-smoke\stage90b-base-pmax-fresh-zero-cut-10iter\run-004`.
