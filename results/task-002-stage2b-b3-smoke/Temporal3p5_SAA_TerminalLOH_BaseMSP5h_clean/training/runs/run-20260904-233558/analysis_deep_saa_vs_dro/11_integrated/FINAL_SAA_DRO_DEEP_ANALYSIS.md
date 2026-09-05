# BASE2-SAA vs BASE2-DRO Deep Analysis

This is a read-only paired analysis of the frozen BASE2-SAA and BASE2-DRO Formal Chain. No TerminalLOH solve, training, optimization, or OOS run was executed.

## QA gates
- `SAA_SOLVER_SEMANTIC_AUDIT = PASS`.
- `SAA_ACTIVE_TABLE_VALUE_IDENTITY = PASS`; max absolute T difference `0.000e+00` kg.
- `COMMON_PATH_QA = PASS`; canonical bank SHA `6bf3d1190a402ded052b8d3d08ed369042236e151f562bdd9fd4db7b8ff386c6`, 10000 ordered paths per arm.
- `COST_IDENTITY_QA = PASS`; max absolute identity error SAA/DRO `9.022e-10` / `8.986e-10` yuan.

## TerminalLOH and positivity
- Mean SAA TerminalLOH `196.811888981` kg; DRO `229.053106360` kg; DRO-SAA `32.241217379` kg.
- Positive-target paths: SAA `1019`, DRO `1123`.
- Positivity migration `ZZ/ZP/PZ/PP = 8877/104/0/1019`; common-positive cohort `1019` paths.
- State-level uplift is descriptive; the top-10 state table is not an OOS contribution ranking.

## Common-positive classification
- SAA classes in PP: `{'COMMON_POSITIVE_COUNT': 1019, 'SAA_ADEQUATE': 701, 'SAA_PURE_QUANTITY': 76, 'SAA_PURE_LOCATION': 148, 'SAA_MIXED': 94, 'DRO_ADEQUATE': 573, 'DRO_PURE_QUANTITY': 89, 'DRO_PURE_LOCATION': 211, 'DRO_MIXED': 146, 'SAA_ADEQ_TO_DRO_FAILURE': 161, 'SAA_FAILURE_TO_DRO_ADEQ': 33, 'QUANTITY_COMPONENT_RESOLVED': 22, 'QUANTITY_COMPONENT_NEWLY_INTRODUCED': 87, 'SPATIAL_COMPONENT_RESOLVED': 56, 'SPATIAL_COMPONENT_NEWLY_INTRODUCED': 171}` (see CSV for the full matrix).
- The 4x4 migration matrix compares complete SAA reserve design with complete DRO reserve design; it is not a fixed-target intervention comparison.

## Service and gap decomposition
- Mass-weighted service: SAA `90.966282%`, DRO `92.777010%`, DRO-SAA `+1.810728%`.
- Site/quantity/location gap means, medians, incidence, and total mass are in `05_service/gap_component_summary.csv`. These are paired end-to-end descriptive differences.

## Economics and preparation
- Mean actual operating cost: SAA `54203.474555`, DRO `55266.251774` yuan/path; delta `+1062.777219`.
- Mean reported objective: SAA `55477.759036`, DRO `56794.853155` yuan/path; delta `+1317.094119`.
- Mean terminal penalty delta `+254.316900` yuan/path; mean production delta `+50.483196` kg/path; mean HTT delta `+3.927953` kg/path.
- Largest stage production delta is Stage `1` (`+31.413126` kg/path); largest hourly delta is hour `7` (`+8.775000` kg/path).
- Operating cost and reported objective are kept separate. No claim of overall policy superiority is made from operating cost alone.

## Cohorts and path candidates
- Cohort rows distinguish physical dissipation, other absorption, true Stage7 zero-target, common-positive, ZP, and PZ exposure. For zero-target cohorts, service is reported only where target-positive; realized preparation exposure is not interpreted as knowledge of future outcomes.
- Typical candidates: `10` rows; mechanism candidates: `20` rows. Selection is mechanical median-distance, tail-stress, or ranked paired difference; no manual cherry-picking was used.

## Interpretation boundary
The evidence is consistent with DRO increasing reserve targets and changing end-to-end preparation/recourse exposure. It does not identify a single causal mechanism without a control experiment. Results are descriptive paired evidence under changed TerminalLOH targets, and `FULLY_CONVERGED` remains `NOT_ESTABLISHED`.

`READY_FOR_FORMAL_CASE_STUDY_INTERPRETATION = YES` for descriptive paired case-study drafting, subject to the stated non-causal and fixed-budget limitations.
