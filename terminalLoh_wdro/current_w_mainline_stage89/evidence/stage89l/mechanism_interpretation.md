# Stage-89L mechanism interpretation

## Strict attribution boundary

`Stage88 -> Case B` is only auxiliary **MAIN-GRID RECONFIGURATION EFFECT** context and still mixes five-point exposure plus G1. `Case B -> Case C` is the strict **H2 ELECTRICAL-ISLAND INCREMENTAL EFFECT** evaluated here. The Stage88-to-Stage89K full change is not called an H2-island effect.

As auxiliary context only, Stage88-to-Case-B mean T_total changes are SAA `344.707198 -> 235.950296 kg` (`-31.550517%`) and DRO `382.034556 -> 274.804682 kg` (`-28.068109%`). These large changes remain confounded by five-point exposure, G1, radial reconstruction, main-grid recovery, and `Dres`; they are not H2-island attribution.

## Incremental classifications

| scope | mode | incremental_effect |
| --- | --- | --- |
| overall | DRO | MIXED |
| a3 | DRO | INCREASES_T |
| a4 | DRO | INCREASES_T |
| a5 | DRO | INCREASES_T |
| a6 | DRO | MIXED |
| overall | SAA | MIXED |
| a3 | SAA | MAINLY_REALLOCATES_T |
| a4 | SAA | INCREASES_T |
| a5 | SAA | INCREASES_T |
| a6 | SAA | MIXED |

## Mean service changes (dual minus road-only)

| mode | road_service_change_kg | electrical_service_change_kg | shortage_change_kg | total_service_change_kg | T_total_change_kg |
| --- | --- | --- | --- | --- | --- |
| DRO | -7.81126290647806 | 9.357688763380459 | -1.5464258569023996 | 1.5464258569023988 | 2.4062613058067948 |
| SAA | -7.638841110085028 | 9.186865959323201 | -1.5480248492381703 | 1.5480248492381743 | 1.9734960509037944 |

## Formal judgment

- `H2_ISLAND_INCREMENTAL_EFFECT = MIXED` for both SAA and DRO overall: mean T_total rises by less than 1%, a3-a5 generally rise, while a6 mean falls and statewise signs are heterogeneous.
- `H2_ISLAND_MECHANISM_VALUE = MODERATE`: about 9.27 kg of electrical service mainly replaces about 7.73 kg of road service and additionally reduces shortage by about 1.55 kg; FC binding is observed, and site3/site4 reallocation is material despite the small total-T effect.
- `RECOMMEND_ADOPT_STAGE89J_89K = YES`: all 70 Case-B cases and accepted 70 Case-C cases pass, attribution is internally consistent, and no double counting or numerical anomaly is present. Formal promotion remains reserved for Stage-89M.

## Adoption gate

All Case-B cases are optimal; Case C is read-only reused; shared inventory is unchanged and electrical service is mechanically zero in Case B. FA-MSP and OOS were not run.
