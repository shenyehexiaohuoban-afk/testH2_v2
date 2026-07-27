# Step-03T Pair Selection Rationale

Selection is deterministic and reads only the frozen Step-03S cross-regret table.
Each of states 7, 18, 30, 31, 11, and 21 contributes three distinct Tier-1 representatives and one nonzero-distance low-regret control.
Tier-1 rules are minimum d_new, maximum min(two directional objective regrets), and a category/structural representative preferring tail-tail then non-tail/tail.
Controls are nearest-all pairs with both directional relative objective regrets below 1%, selected closest on a log-distance scale to the state's Tier-1 median distance.
No nearest-neighbor search, scenario optimization, or Step-03S calculation is repeated during selection.

- pair 1: state 7, TIER1, rule=MINIMUM_D_NEW, scenarios 3576-8245, d_new=0.00463618802317, severity=0.282352940623.
- pair 2: state 7, TIER1, rule=MAXIMUM_BIDIRECTIONAL_SEVERITY, scenarios 3576-1, d_new=0.0115904700579, severity=704.882352637.
- pair 3: state 7, TIER1, rule=CATEGORY_REPRESENTATIVE, scenarios 5076-7008, d_new=0.389427652586, severity=4.24368450172.
- pair 4: state 7, CONTROL, rule=LOW_REGRET_DISTANCE_MATCHED, scenarios 224-13663, d_new=0.0445810559108, severity=-8.13209567778e-11.
- pair 5: state 18, TIER1, rule=MINIMUM_D_NEW, scenarios 7951-8139, d_new=0.00295065635262, severity=0.132955682338.
- pair 6: state 18, TIER1, rule=MAXIMUM_BIDIRECTIONAL_SEVERITY, scenarios 5578-6733, d_new=0.0563837193837, severity=24.1188120696.
- pair 7: state 18, TIER1, rule=CATEGORY_REPRESENTATIVE, scenarios 8902-1303, d_new=0.110982872788, severity=5.48143786519.
- pair 8: state 18, CONTROL, rule=LOW_REGRET_DISTANCE_MATCHED, scenarios 4847-6256, d_new=0.0572451443743, severity=0.00292795707745.
- pair 9: state 30, TIER1, rule=MINIMUM_D_NEW, scenarios 3991-5821, d_new=0.00909164734523, severity=0.174375545473.
- pair 10: state 30, TIER1, rule=MAXIMUM_BIDIRECTIONAL_SEVERITY, scenarios 2508-6378, d_new=0.0463704029124, severity=0.471790843232.
- pair 11: state 30, TIER1, rule=CATEGORY_REPRESENTATIVE, scenarios 10710-9931, d_new=0.054942201474, severity=0.405444662779.
- pair 12: state 30, CONTROL, rule=LOW_REGRET_DISTANCE_MATCHED, scenarios 11691-9716, d_new=0.0466577170671, severity=-2.3069311757e-14.
- pair 13: state 31, TIER1, rule=MINIMUM_D_NEW, scenarios 3295-3225, d_new=0.00909147877767, severity=0.10787122659.
- pair 14: state 31, TIER1, rule=MAXIMUM_BIDIRECTIONAL_SEVERITY, scenarios 11336-6188, d_new=0.034395092305, severity=0.398830784416.
- pair 15: state 31, TIER1, rule=CATEGORY_REPRESENTATIVE, scenarios 11578-5253, d_new=0.0515155703547, severity=0.256112252705.
- pair 16: state 31, CONTROL, rule=LOW_REGRET_DISTANCE_MATCHED, scenarios 8102-1750, d_new=0.0344501200355, severity=6.29805408831e-06.
- pair 17: state 11, TIER1, rule=MINIMUM_D_NEW, scenarios 7036-14693, d_new=0.0042429934883, severity=0.111119459822.
- pair 18: state 11, TIER1, rule=MAXIMUM_BIDIRECTIONAL_SEVERITY, scenarios 10407-11668, d_new=0.127954473331, severity=40.4652198099.
- pair 19: state 11, TIER1, rule=CATEGORY_REPRESENTATIVE, scenarios 3520-8359, d_new=0.230241521475, severity=1.21818201415.
- pair 20: state 11, CONTROL, rule=LOW_REGRET_DISTANCE_MATCHED, scenarios 3957-14538, d_new=0.0454450912389, severity=-4.0829875096e-14.
- pair 21: state 21, TIER1, rule=MINIMUM_D_NEW, scenarios 4757-5018, d_new=0.00329656600436, severity=0.141822735397.
- pair 22: state 21, TIER1, rule=MAXIMUM_BIDIRECTIONAL_SEVERITY, scenarios 353-10381, d_new=0.110003131972, severity=37.1033101355.
- pair 23: state 21, TIER1, rule=CATEGORY_REPRESENTATIVE, scenarios 8542-2987, d_new=0.174826705487, severity=0.828821849895.
- pair 24: state 21, CONTROL, rule=LOW_REGRET_DISTANCE_MATCHED, scenarios 4441-11613, d_new=0.0842594895944, severity=4.76665973509e-05.
