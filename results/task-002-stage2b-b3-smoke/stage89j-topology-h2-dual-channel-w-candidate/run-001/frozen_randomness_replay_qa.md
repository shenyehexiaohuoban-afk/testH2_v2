# Frozen randomness replay QA

Status: **PASS**.

- W_TRAJECTORY_RESAMPLED = NO. All 35 frozen Stage87 trajectory and nominal scenario files match `checkpoint_completion_manifest.csv` SHA-256 values.
- W_TRANSITION_MATRIX_MODIFIED = NO. No trajectory generator or aw/locw/lfw probability code is called; existing frozen identities are consumed read-only.
- GRID_FAILURE_RANDOMNESS_RESAMPLED = NO. State-specific `resistance_seed` plus `joint_stream_position` replay the accepted MT19937 thresholds; aggregate B2 mismatch bits = 0.
- ROAD_FAILURE_RANDOMNESS_RESAMPLED = NO. Aroad and C are read from the 35 Stage88 banks, and every full-bank SHA-256 matches `h2_bank_manifest.csv`.
- Frozen draws = 35 x 15000 = 525000; official failure observations = 1575000.

Deterministic combined identities:

- W trajectory/scenario source set SHA-256: `9ed8324e6a705fcdfadcbfdd795ff8ded0baafd8fb71857f210b03914724e5a2`
- fixed line-resistance uniform replay SHA-256: `302f8a79753f513f976784f5ce8bbeb3286c2eb7946790e57186ffc4d7c7742d`
- G1 official-slice failure-mask identity SHA-256: `3313e5e412e4fb8c187e8ffdf01105a9df80ca10556c57638e29beb755635269`
- Stage88 road-bank source set SHA-256: `9b23b4da3ea11a3e7b9cc43eb3db0211258a3bf1b2731d5e4f31338ed3c32425`
- deterministic topology classification SHA-256: `4b3d73b4a10200e87456b52d2b58379c96e0f88c7ae2485d5d9baaadc1fcf798`

These are replay identities, not new random seeds.
