# W_OOS/V1-B4C Final Detailed Closeout

## Scope and provenance

- Branch: `task/002-stage2b-b3-smoke`
- Pre-closeout HEAD: `580f59e376337f195dd9ca724315c87ee4850210`
- Upstream: `origin/task/002-stage2b-b3-smoke`, ahead/behind `0/0`
- Final evidence run: `run-007-coupling-correction-closeout`
- Historical `run-001`, `run-002-coupling-correction.superseded-001`, and `run-002-coupling-correction` were preserved.
- MATLAB PID `9668` was observed and left untouched; no standalone Gurobi process was observed.
- No BASE2, frozen W, B3 engine, formal W_OOS, 10000-path run, training, or rolling mobility dispatcher was started.

## Source identity

- `W_OOS/V1/src/b4_event_driven_restoration_smoke.py`: 35,602 bytes before the identity-ledger extension; SHA-256 after extension is `93ACC3107036DA09C7E48B0F53941607A62D0F3F80359D2DA9CBDC39F0F72C99`; local B4 runner, currently untracked before checkpoint.
- `W_OOS/V1/src/engine.py`: 13,022 bytes, SHA-256 `435245E9CCDAE96EBF9ED4F6C8444445D7D575DE2145BD778A2DE6D8AAAF8407`; tracked and unchanged.
- The B4 runner reads the existing B3 actual inventory source and the frozen MAT input; no frozen input bytes were changed.

## Forensic answers

1. Original `MFCV_H2_ledger.csv:P_MFCV_kW` was available capacity (`active vehicles * 220 kW`), not actual dispatch.
2. Original `H2_use_kg=0` was a MODEL_BUG: dispatch was not linked to H2. The station zero-use symptom was the same class of missing coupling, not merely CSV formatting.
3. Original fixed-FC actual output was not Pmax-constrained because no actual FC dispatch variable entered P/Q balance. The corrected runner enforces `0 <= P <= Pmax`.
4. CASE-3 `420 kW` was bus24 load copied to served when a root candidate existed; there was no source balance. It is gone after correction.
5. Yes, the original runner treated root existence as an unlimited source. The corrected runner separates eligibility from power capability.
6. Corrected fixed-FC dispatch is bound per interval to the station at the same site: `H2_use = P*duration/(0.55*33.33)` and `station_after = station_before - H2_use`.
7. Corrected MFCV dispatch is bound per interval to its own onboard H2, with SERVICE/non-MOVING/at-bus/onboard-H2 eligibility and `0 <= onboard <= 66.6 kg`.
8. CASE-4 starts consuming H2 exactly at arrival `1.2166666666667 h`; the pre-arrival interval has zero actual P/Q and zero H2 use.
9. Maximum system H2 identity error over 12 mandatory cases, CASE-13 event/delayed, and frozen realization is `1.5987211554602254e-14 kg`.
10. Root ledger explicitly contains `eligible_real_roots`, `selected_topological_root`, and `actual_injecting_sources`; every energized island has one selected topological root, while multiple injectors are allowed.

## CASE-3: fixed-FC island

All rows are from `case3_forensic.csv`; interval duration is in hours.

| interval | island | P_load | Q_load | P_FC/Pmax | Q_FC | P_shed | Q_shed | station H2 before -> after | H2 use |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 0.0-1.0 | [24] | 420.0 | 200.0 | 300.0/300.0 | 145.29663145135575 | 120.0 | 54.70336854864425 | 69.1553559615926 -> 52.79008307066715 | 16.365272890925453 |
| 1.0-2.0 | [24] | 420.0 | 200.0 | 300.0/300.0 | 145.29663145135575 | 120.0 | 54.70336854864425 | 52.79008307066715 -> 36.4248101797417 | 16.365272890925453 |
| 2.0-3.5 | [24] | 420.0 | 200.0 | 300.0/300.0 | 145.29663145135575 | 120.0 | 54.70336854864425 | 36.4248101797417 -> 11.876900843353518 | 24.54790933638818 |

`Q_factor = tan(acos(0.90)) = 0.48432210483785254`; therefore `Q_factor*300 = 145.29663145135575`, exactly matching the reported Q. Every row satisfies `P_FC <= 300`, the PF bound, the interval H2 formula, and station before/after balance. The old full-service `420 kW` report is absent; the island is served only up to the real FC capability.

## CASE-4: MFCV arrival and actual dispatch

Arrival is `1.2166666666667 h`. `P_MFCV_available_kW=220` is capacity only; `P_MFCV_actual_kW` is the optimized dispatch.

| interval | state | available P | actual P | actual Q | onboard H2 before -> after | H2 use | served P / shed P |
|---|---|---:|---:|---:|---:|---:|---:|
| 0.0-1.2166666666667 | NOT_ARRIVED | 220.0 | 0.0 | 0.0 | 10.0 -> 10.0 | 0.0 | 0.0 / 90.0 |
| 1.2166666666667-1.5 | SERVICE | 220.0 | 90.0 | 43.58898943540673 | 10.0 -> 8.6089518042715 | 1.3910481957284995 | 90.0 / 0.0 |
| 1.5-3.5 | SERVICE | 220.0 | 78.9075000000015 | 38.21664648749358 | 8.6089518042715 -> 0.0 | 8.6089518042715 | 78.9075000000015 / 11.092499999998495 |

The island `[23]` has no eligible real root before arrival and uses `VIRTUAL_ROOT` with no injection. After arrival, root `23` injects through `MFCV-1`. Each row satisfies `H2_use=P*duration/18.3315` and onboard before/after balance; the MFCV formula residual is below `1.8e-15 kg`.

## System H2 identity

Initial inventory is station `195.9312153119796 kg` plus onboard `28.0 kg`, total `223.9312153119796 kg`. The corrected `system_H2_identity.csv` has 15 rows: CASE-1..CASE-12, CASE-13 event, CASE-13 delayed, and the frozen realization. It now includes all interval-ledger cases, not only the 12 mandatory fixtures. The maximum absolute residual is `1.5987211554602254e-14 kg`; refuel/transfer is an internal station-to-onboard movement and is not counted as system consumption.

## Root semantics

- CASE-1: eligible `[1,14,18,24,31]`, selected root `1`, injector `UTILITY-BUS-1`.
- CASE-3: main island selects `1` with utility injection; isolated `[24]` selects `24` and injects `FC-1`.
- CASE-4: isolated `[23]` is `VIRTUAL_ROOT` with no source before arrival; it selects `23` and injects `MFCV-1` after arrival.
- CASE-7: selected root remains `1` on the main island while utility, fixed FC, and MFCV inject together; the `[23]` island independently selects `23` and injects `MFCV-2`.
- Frozen realization: selected root is `1`; actual injectors are utility plus fixed FCs before arrival and include `MFCV-1` after arrival.

These rows demonstrate `ROOT_ELIGIBLE != UNLIMITED_POWER` and `ONE_TOPOLOGICAL_ROOT != ONE_GENERATOR_ONLY`.

## Event-driven semantics and CASE-13

The exact event boundaries are `0`, `1`, `1.2166666666667`, `1.5`, `2`, `2.5`, `3`, and `3.5 h`. Arrival/departure and service state transitions split intervals at those times. The CASE-13 comparison is:

- event-driven EENS: `131.68499999999977 kWh`
- half-hour delayed reference: `135.0 kWh`
- delay difference: `3.315000000000225 kWh`

The `109.5 kWh` value is the first pre-arrival interval contribution, not the full event-driven total. Half-hour bins are reporting bins only and are not reconfiguration triggers.

## Frozen realization

`state1/path117/W2`, raw failure mask `16777216`, source `existing five-point HDF5 raw mask`, scope `single frozen realization; no W/OOS`. The event intervals are the exact seven boundaries above. The selected topology is the deterministic radial forest over healthy normal branches plus acyclic ties; no healthy normal branch is opened by this local graph rule, and the ledger records 32 active branches with 32 initial switch operations and zero thereafter. Root/source rows show utility plus fixed FCs before arrival and `MFCV-1` after arrival.

The frozen electrical ledger reports `min_voltage_pu=0.9`, `max_voltage_pu=1.0`, and maximum branch utilization `0.5169798226596908` (minimum across intervals `0.4782968380160979`). EENS is `0 kWh` because active utility/fixed/mobile sources satisfy the modeled real-power demand; reactive shedding remains explicit in the Q ledger. Fixed-FC H2 use is `137.46829228376842 kg`, MFCV H2 use is `10.000000000000254 kg`, final station H2 is `58.46292302821118 kg`, final onboard H2 is `17.999999999999744 kg`, with identity residual `1.7763568394002505e-15 kg`. No moving vehicle generates power, no free H2/power is created, and no legacy Dres/Aelec double counting is used.

Labels remain `RESTRICTED_TIMELINE_SET`, `NOT_GLOBAL_MOBILITY_OPTIMUM`, and `NOT_FORMAL_W_OOS`.

## Regression and status

B3 regression evidence is `3880 checks PASS`, maximum mass error `2.842170943040401e-14 kg`, and `C diff = 0 km`; `W_OOS/V1/src/engine.py` is unchanged. The 23 named B4C QA gates in `QA_closeout.json` are all `PASS`, including capacity, PF, FC/MFCV H2 coupling, station/onboard balance, root semantics, no-free-power, no-double-spend, EENS identity, frozen integration, and data preservation.

`B4C_DETAILED_CLOSEOUT = PASS`

`B4C_ENGINEERING_CHECKPOINT = PASS`

`H2_ELECTRICAL_COUPLING = VERIFIED`

`FIXED_FC_CAPACITY_COUPLING = VERIFIED`

`ROOT_SEMANTICS = VERIFIED`

`EVENT_DRIVEN_GRID_INTERFACE = VERIFIED`

`READY_TO_DESIGN_ROLLING_MOBILITY_DISPATCH = YES`

`ROLLING_MOBILITY_DISPATCH_IMPLEMENTED = NO`
