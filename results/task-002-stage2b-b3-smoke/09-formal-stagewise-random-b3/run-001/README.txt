Step-03I run-001: formal stagewise-random B3 sample-size stability

status=PASS; PASS=24; FAIL=0
Formal B3 wind default: stagewise_random_triangular. fixed_representative remains available.
35 states x 15000 main records x 3 joint seeds were evaluated with persistent fixed resistance and independent W1-W3 wind quantiles.
Nested N values: 500, 1000, 2000, 5000, 10000, 15000. Smaller N is an exact prefix of larger N.
Each prefix record has weight 1/N; path_probability is not used as a second weight.
Natural observed-tail paths remain only at their main-sample frequency (268 records); no candidate rows are appended and no unobserved candidate appears.
a=1 wind samples=325908: min 0, mean 0, median 0, q95 0, max 0 m/s.
a=2 wind samples=1147437: min 17.2087758, mean 20.7987316, median 20.7980444, q95 23.2594763, max 24.3906887 m/s.
a=3 wind samples=754095: min 24.5028858, mean 28.5500907, median 28.5495037, q95 31.3196911, max 32.5962002 m/s.
a=4 wind samples=1003611: min 32.7059811, mean 37.0471972, median 37.0470931, q95 40.0217944, max 41.3993812 m/s.
a=5 wind samples=1296807: min 41.5061052, mean 46.1998374, median 46.1992633, q95 49.4131914, max 50.8944875 m/s.
a=6 wind samples=197142: min 51.0138958, mean 55.5006654, median 55.5062741, q95 58.5679802, max 59.9931348 m/s.
No accepted B3 D/A/C stability threshold exists, so no pass threshold is invented.
The conservative diagnostic recommendation is N=15000, the largest tested/reference sample.
- N=500: largest metric p95 relative error 1.22222222222 (full_loss_probability); largest p95 seed std 76.6849464763.
- N=1000: largest metric p95 relative error 1 (full_loss_probability); largest p95 seed std 51.1616576393.
- N=2000: largest metric p95 relative error 1 (full_loss_probability); largest p95 seed std 47.6938450086.
- N=5000: largest metric p95 relative error 1 (full_loss_probability); largest p95 seed std 42.0855936982.
- N=10000: largest metric p95 relative error 0.5 (full_loss_probability); largest p95 seed std 16.3864734014.
- N=15000: largest metric p95 relative error 0 (D_mean_kg); largest p95 seed std 7.55058949422.
N15000 D_mean_kg fixed/random/difference: 176.407086942 / 178.533574916 / 2.12648797347.
N15000 D_q95_kg fixed/random/difference: 372.865858014 / 379.536654964 / 6.67079694982.
N15000 D_q99_kg fixed/random/difference: 448.959181632 / 451.450339839 / 2.49115820673.
N15000 full_loss_probability fixed/random/difference: 0.0527047619048 / 0.0540228571429 / 0.0013180952381.
N15000 A0_pair_share fixed/random/difference: 0.0772362113195 / 0.0792347603014 / 0.00199854898188.
N15000 C_reachable_mean_km fixed/random/difference: 20.2757960248 / 20.2817838946 / 0.00598786985731.
N15000 C_reachable_q95_km fixed/random/difference: 23.8478256722 / 23.9137269294 / 0.0659012571566.
N15000 W3_failed_lines_mean fixed/random/difference: 5.24629968254 / 5.35440444444 / 0.108104761905.
N15000 W3_closed_roads_mean fixed/random/difference: 2.88746730159 / 2.96533460317 / 0.0778673015873.
N15000 D_upper_bound_hit_share fixed/random/difference: 0.0527047619048 / 0.0540228571429 / 0.0013180952381.
No WDRO, Gurobi optimization, MSP, candidate augmentation, or nominal-probability change.
