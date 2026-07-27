# Step-03S Probability Semantics

## Code and frozen-data findings

- nominal rows: 525000
- initial states: 35
- rows per state: 15000
- empirical mass per row: 1/15000
- empirical mass sum per state: 1
- explicit path, transition, or scenario probability fields: none
- DAC MAT fields: A_site_node, C_site_node_km, D_node_kg, initial_state_id, path_id
- path_id meaning: record identity, not probability

Step-03J assigns every Monte Carlo record equal conditional empirical mass within its initial state. Identical D/A/C outcomes obtain larger empirical mass only by repeated rows, so an outcome repeated k times has empirical mass k/15000. The DAC sidecar has no row-wise probability vector and no one-to-one path-probability field.

Accordingly this audit uses the terms equal-mass empirical sample and empirical high-loss tail. q95, q99, and q99.5 membership is not called a low-probability scenario. Validation-1 and validation-2 are not read for selection, scaling, tuning, or thresholds.
