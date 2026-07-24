# Step-03J Large File Manifest

The files below remain under `terminalLoh_wdro/output/stage3j_wdro_input_freeze/run-001/` and are not uploaded to Git because each exceeds 50 MiB.

| Dataset role | File | Rows / dimensions | Bytes | SHA-256 |
|---|---|---:|---:|---|
| nominal | `wdro_nominal_input.csv` | 525000 rows | 122068355 | `366dc3c0b57bfd76aca92f51ae1db82b93c764c87fa15e8cb4dd32388d018168` |
| nominal | `wdro_nominal_input_DAC.mat` | D: 525000x33; A/C: 525000x4x33 | 188959741 | `6936a696f5cde137aca483f8c32adee33b52cbd90559a8e6395f3686c0712945` |
| validation-1 | `wdro_validation_1.csv` | 525000 rows | 124697225 | `e39253d5af25d312b5d65cbb4efdf5ad4e907843f9203a46c47c7ca058ed3099` |
| validation-1 | `wdro_validation_1_DAC.mat` | D: 525000x33; A/C: 525000x4x33 | 188919247 | `ca84afa01748d8c2929c372802861315254723424786b681a677e2f1420b6e3f` |
| validation-2 | `wdro_validation_2.csv` | 525000 rows | 124701276 | `91c8e1233017d5d7dea9a87592f5bfb196e0d629733c10892fb539e4228c9b02` |
| validation-2 | `wdro_validation_2_DAC.mat` | D: 525000x33; A/C: 525000x4x33 | 188936785 | `0bae20fa685940751edf5c5dd3d6c43a2d52293cbd1350c02b84736e914ec3b6` |

The scenario CSV and DAC sidecar for a role are row-aligned by `initial_state_id` and `path_id`. Use `load_frozen_b3_wdro_dataset_h2.m` to restore the existing WDRO `samples.D`, `samples.A`, and `samples.C_raw` array contract for one initial state.
