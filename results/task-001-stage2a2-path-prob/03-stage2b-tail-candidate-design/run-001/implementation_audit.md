# Implementation Audit

- source sample: `C:\Users\chaos\Desktop\biye\test\testH2_v2\terminalLoh_wdro\output\stage2a2_W3_path_sampling\run-002\main_path_samples.csv`
- source SHA-256: `972a8c58620c09ac19cfcfb29e8d6a3ed2819ef1a22dbd522043436418eb805d`
- source sample unchanged: 1
- candidate matrices unchanged: 1
- Rmax_ref: 40; wind decay B: 0.6.
- grid/road thresholds: 25/30 m/s.
- geometry: grid and road point-to-segment distance.
- path aggregation: exact W1-W3 state sequence within each initial state.
- empirical mass: frequency/15000.
- path_probability: recomputed theoretical audit field only.
- no artificial combined risk score.
- no resampling, supplemental paths, fixed-resistance B3, WDRO, Gurobi, or MSP.
