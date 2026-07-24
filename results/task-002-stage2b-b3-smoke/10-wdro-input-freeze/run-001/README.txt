Step-03J run-001: frozen formal B3 datasets for WDRO

PASS=18; FAIL=0
Seed group 1 (20260723) is nominal; groups 2 and 3 (20260724, 20260725) are independent validation-1 and validation-2. They are not pooled into a 45000-record nominal state sample.
Each role has 525000 rows: 35 initial states x 15000 canonical main records. Each conditional state uses weight 1/15000 and sums to one.
The scenario CSVs retain path states, actual W1-W3 winds, seeds, D/A/C summaries, W3 damage counts, weight, and role. DAC MAT sidecars retain exact R x 33 D and R x 4 x 33 A/C arrays for the existing WDRO algorithm contract.
nominal: seed 20260723, rows 525000, CSV bytes 122068355, DAC bytes 188959741, CSV SHA 366dc3c0b57bfd76aca92f51ae1db82b93c764c87fa15e8cb4dd32388d018168, DAC SHA 6936a696f5cde137aca483f8c32adee33b52cbd90559a8e6395f3686c0712945.
validation-1: seed 20260724, rows 525000, CSV bytes 124697225, DAC bytes 188919247, CSV SHA e39253d5af25d312b5d65cbb4efdf5ad4e907843f9203a46c47c7ca058ed3099, DAC SHA ca84afa01748d8c2929c372802861315254723424786b681a677e2f1420b6e3f.
validation-2: seed 20260725, rows 525000, CSV bytes 124701276, DAC bytes 188936785, CSV SHA 91c8e1233017d5d7dea9a87592f5bfb196e0d629733c10892fb539e4228c9b02, DAC SHA 0bae20fa685940751edf5c5dd3d6c43a2d52293cbd1350c02b84736e914ec3b6.
The loader load_frozen_b3_wdro_dataset_h2 restores samples.D, samples.A, samples.C_raw, and sampleWeights without changing WDRO algorithms.
Observed candidates occur only through 268 natural main records per role. No unobserved candidate is present.
No WDRO, Gurobi optimization, or MSP execution was performed.
