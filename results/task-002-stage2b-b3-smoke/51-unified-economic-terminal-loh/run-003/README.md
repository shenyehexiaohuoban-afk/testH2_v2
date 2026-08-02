# Step-04C-C5B unified-economic TerminalLOH recalculation

Status: **ACCEPTED**
Run: `run-003`
Frozen Git HEAD/upstream/remote before execution: `bb298d52ee5143bc2c60e2f2fc1e31e8d1c3d1a2`

## Frozen economic units

- Live MSP 24-hour price vector: min `0.3`, max `0.98`, arithmetic mean `0.634166666666667 yuan/kWh`.
- `SEC_H2=1/0.0195=51.2820512821 kWh/kg`; no additional electrolyzer-efficiency multiplication was made.
- Local production coefficient: `c_H2=32.5213675214 yuan/kg`.
- `LHV*eta_FC=33.33*0.55=18.3315 kWh/kg-H2`.
- `M_H2=70*18.3315=1283.205 yuan/kg-H2`.
- Primary objective contains only local preparation cost and shortage/VOLL loss. `C*y` is excluded from currency and Pearson scenario loss.

## New decisions and nominal replay

- SAA: T=[222.840465865, 119.193737556, 36.003600360, 133.376974061] kg, total=511.414777841 kg, nominal mean EENS=113.420000000 kWh, nominal mean economic total=24571.307946039 yuan.
- ETA_0.003: T=[225.290752999, 121.925712142, 41.462552723, 137.464508020] kg, total=526.143525884 kg, nominal mean EENS=107.057013081 kWh, nominal mean economic total=24604.897889964 yuan.
- ETA_0.01: T=[226.659147502, 121.966076720, 44.414041094, 139.650354720] kg, total=532.689620037 kg, nominal mean EENS=104.504173496 kWh, nominal mean economic total=24639.087052759 yuan.

## Lexicographic rule and validation

Every fixed-T replay first minimizes shortage. A second LP then fixes each scenario's primary-optimal shortage with an equality and minimizes `sum(C*y)`. The secondary stage does not change T or primary shortage. Validation covers nominal, three separate C2 independent-path sets, all 21 C3 distribution-seed cells, and the isolated 27-path/135-replica state19 pressure set. The pressure set remains descriptive and has no empirical probability.

## Bounded interpretation

3. 两个 DRO 方案分别代表不同保障等级，均保留. SAA remains the economic reference; eta is not frozen. See `candidate_positioning.txt` and the complete CSV tables for the economic-resilience tradeoff. This prototype excludes electrolyzer O&M, depreciation, water, holding, losses, salvage, external hydrogen, and station-to-station transport. It does not run the MSP or 35 states.

## Mechanical acceptance

- optimization cases: 3/3 OPTIMAL and certified
- fixed-decision validation cells: 26/26 complete, 78/78 method rows PASS
- eta=0 direct SAA identity: PASS
- Pearson nonnegativity, probability sum, divergence, strong duality, LB/UB: PASS
- `EENS=shortage*18.3315`: PASS
- `C*y` primary/currency/Pearson inclusion: zero
- R-by-R matrix, old Wasserstein, extreme-aware objective, MSP, and validation reoptimization: zero
