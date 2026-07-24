Step-03H run-001: full-intensity stagewise random wind sensitivity

status=PASS; PASS=20; FAIL=0
M1 draws independent q1/q2/q3 within each path-resistance scenario. Wind randomness remains in the second-layer joint B3 realization.
a=1 samples=9660 min=0 mean=0 median=0 q95=0 max=0 m/s.
a=2 samples=27519 min=17.2294701 mean=20.7934025 median=20.7900967 q95=23.2650918 max=24.3728694 m/s.
a=3 samples=6483 min=24.6028681 mean=28.5230312 median=28.5173173 q95=31.289488 max=32.4979119 m/s.
a=4 samples=18033 min=32.7376118 mean=37.0595943 median=37.0557378 q95=40.0741899 max=41.3704015 m/s.
a=5 samples=24593 min=41.5259039 mean=46.1784005 median=46.1708087 q95=49.3649877 max=50.8577701 m/s.
a=6 samples=3712 min=51.206942 mean=55.5386034 median=55.4991719 q95=58.6817507 max=59.9292271 m/s.
M0_FIXED: D mean/q95/q99 153.849821/341.21594/390.002637 kg-H2; full loss 0.0346333333; A0 0.059838468; reachable C 20.0351872 km; W3 failed 4.48506667; W3 closed 2.32696667.
M1_STAGEWISE_RANDOM: D mean/q95/q99 155.874769/342.506978/392.22104 kg-H2; full loss 0.0353666667; A0 0.0612824074; reachable C 20.0497247 km; W3 failed 4.5695; W3 closed 2.39303333.
M1 threshold crossings versus M0: grid >25 up/down 54438/50866; grid >50 up/down 471/214; road >30 up/down 47656/56483; road >60 up/down 0/0.
Primary shifts exceeding Step-03D N2000 p95 errors: 0 of 5.
Decision: NEED_MORE_VALIDATION. stagewise random wind changes outcomes, but directions or magnitudes are not uniformly beyond existing N2000 stability-error benchmarks.
The formal fixed wind mapping is unchanged. No candidate paths, full B3 rerun, WDRO, Gurobi, or MSP.
