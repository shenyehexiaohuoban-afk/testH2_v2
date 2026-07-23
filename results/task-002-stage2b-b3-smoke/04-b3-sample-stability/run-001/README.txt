Step-03D run-001: nominal B3 sample-size stability

status=PASS; PASS=15; FAIL=0
35 states x 15000 main records x 3 seeds were evaluated with persistent fixed resistance.
Nested N values: 500, 1000, 2000, 5000, 10000, 15000. Smaller N is an exact prefix of larger N.
Each prefix record has weight 1/N; path_probability is not used as a second weight.
Natural observed-tail paths remain only at their main-sample frequency (268 records); no candidate rows are appended and no unobserved candidate appears.
No accepted B3 D/A/C stability threshold exists, so no pass threshold is invented.
The conservative diagnostic recommendation is N=15000, the largest tested/reference sample.
- N=500: largest metric p95 relative error 1 (full_loss_probability); largest p95 seed std 53.0568944911.
- N=1000: largest metric p95 relative error 1 (full_loss_probability); largest p95 seed std 46.6083176244.
- N=2000: largest metric p95 relative error 1.5 (full_loss_probability); largest p95 seed std 33.8219305782.
- N=5000: largest metric p95 relative error 1.25 (full_loss_probability); largest p95 seed std 41.3691718586.
- N=10000: largest metric p95 relative error 0.5 (full_loss_probability); largest p95 seed std 16.2771480439.
- N=15000: largest metric p95 relative error 0 (D_mean_kg); largest p95 seed std 8.27904785957.
No WDRO, Gurobi optimization, MSP, candidate augmentation, or nominal-probability change.
