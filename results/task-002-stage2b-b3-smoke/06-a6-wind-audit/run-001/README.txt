Step-03F run-001: a=6 wind-data audit and paired B3 sensitivity

status=PASS; PASS=17; FAIL=0
CMA 1949-2024 category-6 records with 2-minute wind >=51 m/s: 4084 records, 454 storms.
CMA record distribution: min 52, mean 62.0872, median 60, q75 65, q90 75, q95 80, q99 90, observed max 110 m/s.
IBTrACS is used only to cross-check original CMA agency records; other agencies and averaging periods are excluded.
M0 (a6 55.5): D mean 153.85, full-loss 0.0346333, A0 0.0598385, C 20.0352, W3 failed 4.48507, W3 closed 2.32697.
M6_MEDIAN (a6 60): D mean 159.459, full-loss 0.0410333, A0 0.0658652, C 20.1045, W3 failed 4.66267, W3 closed 2.49107.
M6_Q90 (a6 75): D mean 168.677, full-loss 0.0627, A0 0.0931472, C 19.9919, W3 failed 5.3786, W3 closed 3.2462.
M6_Q95 (a6 80): D mean 169.93, full-loss 0.0714, A0 0.101821, C 19.7624, W3 failed 5.61047, W3 closed 3.53127.
Contains-a6 path records: 2495; no-a6 records: 27505. No-a6 consequences are exactly identical across modes.
Decision: REVISE_A6_MAPPING. CMA median/q90/q95 exceed 55.5 and higher a6 values create directional B3 shifts beyond observed Step-03E M0 seed ranges.
The historical maximum is not treated as a physical upper bound. The formal 55.5 m/s mapping is unchanged.
No candidate paths, WDRO, Gurobi optimization, or MSP are used.
