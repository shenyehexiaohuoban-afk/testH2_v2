# Step-03S State Selection Rationale

Selection uses nominal-only risk-decision features and fixed seeds. States 7, 18, and 30 are retained before applying every additional rule.

Selected state count: 6. The preferred cap is eight; any excess is retained because mandatory rules identify distinct states and are not silently dropped.

- state 7: BASE_STATE_7;BULK_CLOSE_TAIL_FAR. Step-03R retained simple reference | pair=7-11, bulk=0.27895, tail95=6.721
- state 18: BASE_STATE_18. Step-03R retained medium reference
- state 30: BASE_STATE_30;BULK_OUTLIER;CVAR995_LOSS_MAX;Q995_UNREACHABLE_D_MAX. Step-03R retained complex reference | largest mean bulk energy distance=4.3638 | highest CVaR99.5 fixed-50%-capacity loss | highest q99.5 unreachable demand
- state 31: Q995_LOSS_MAX. highest q99.5 fixed-50%-capacity loss
- state 11: BULK_CLOSE_TAIL_FAR. pair=7-11, bulk=0.27895, tail95=6.721
- state 21: SPATIAL_TAIL_MODE. distinct q99.5 affected site/node mode=3/7; audited tail rows=1295

The bulk-close/tail-far pair is chosen among the lowest bulk-energy quartile using the largest tail95 energy distance. Spatial selection uses the q99.5 affected-site/node mode and nominal bulk separation; no validation data are read.
