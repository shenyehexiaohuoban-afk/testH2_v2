Step-03A run-001: fixed-resistance B3-smoke

status=PASS; PASS=16; FAIL=0
damage_mode=persistent_fixed_resistance
Rmax=40
Wstep=40
W1/W2/W3 each 1 h; Hres=3 h; resistance repeats per path=20.
Selected initial states:
- (5,4,0): minimum_candidate_count; candidate_count=19.
- (2,6,0): maximum_candidate_count; candidate_count=53.
- (2,1,0): low_intensity_left_location; candidate_count=35.
- (4,4,0): medium_intensity_center_location; candidate_count=23.
- (6,7,0): high_intensity_right_location; candidate_count=38.

Probability identity:
- ordinary and observed candidate paths retain frequency/15000.
- unobserved candidates have empirical_weight=0 and status pending_after_B3.
- the 30-path smoke set is not an equal-weight probability distribution.

- main_ordinary: D=[0, 607.969887898] kg; A mean=0.953383838384; C=[0, 99.1540622344] km; novel full scenarios=0.
- observed_candidate: D=[18.00180018, 607.969887898] kg; A mean=0.613396464646; C=[0, 102.957518513] km; novel full scenarios=200.
- unobserved_candidate: D=[22.9113820473, 607.969887898] kg; A mean=0.52946969697; C=[0, 90.4382116716] km; novel full scenarios=200.

Candidate full consequence patterns not seen in ordinary smoke scenarios: 400.
C is masked finite cost: dist(n) when A=1, zero when A=0.
No final representative selection, nominal-distribution change, WDRO, optimization, or MSP.
