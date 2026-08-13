# Stage-80 hourly LinDistFlow voltage-range smoke

- `run-001` is a preserved superseded coverage smoke whose inherited inventory made hourly electrolysis unnecessary.
- `run-002` is the accepted Stage-80 result.
- The only changed grid parameter relative to Stage-79 is the voltage range: `0.90-1.10 p.u.` (`v_sq` in `[0.81,1.21]`).
- Gate B passes `48/48`; all true branch apparent-power checks remain below `6 MVA`.
- Hosting, the integrated hourly-grid/H2 stage LP, inventory dual, four-dimensional cut, and `enable_hourly_grid=false` legacy regression all pass.
- Final judgment: `PASS_READY_FOR_SHORT_TRAINING`.

The accepted lightweight evidence is under `run-002`. The MAT workspace and superseded run remain local-only.
