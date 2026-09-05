# Training Metadata Correction

ORIGINAL_VALUE = 0.03
CORRECTED_VALUE = 0
FIELD = eta
CANDIDATE = TEMPORAL3P5_SAA_BASEMSP5H_CANDIDATE
CORRECTION_CLASS = STALE_REPORTING_METADATA_ONLY
SCIENTIFIC_IMPACT = NONE

The old value was present only in `training_summary.csv` reporting metadata. The active SAA science path uses direct empirical SAA (`q_g = multiplicity / 15000`, `eta = 0`), the checkpoint metadata records `eta = 0.0`, and the reconstructed 35-state SAA reproduction passed with `eta = 0`.

- active TerminalLOH: unchanged
- 35x4 TerminalLOH: unchanged
- checkpoint: unchanged
- cuts: unchanged
- training rerun: no
- OOS rerun: no
- OOS raw: unchanged
- deep-analysis numerical values: unchanged

SHA-256 before correction: `737775ace102e76f87f7d760ff036ab063f6c92aa6d3d83701a66887c46b37e9`

SHA-256 after correction: `b36f2c5d530927b6975c9f8f150ef63be73ee199918d0683cfcdfa38420495c3`
