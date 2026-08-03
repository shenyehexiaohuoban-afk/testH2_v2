# Step-04C-C5C eta response and resilience saturation audit

Status: **ACCEPTED**
Run: `run-003`
Judgment: **B**

Six independent state19 nominal optimizations used the frozen grid `[0, 0.0003, 0.001, 0.003, 0.01, 0.03]` and the C5B yuan-consistent objective. C5B eta `0`, `0.003`, and `0.01` decisions, nominal EENS, economic totals, and LB/UB certificates reproduced with zero recorded difference.

| eta | TerminalLOH `[T1,T2,T3,T4]` kg | total kg | nominal EENS kWh | nominal economic total yuan |
|---:|---|---:|---:|---:|
| 0 | `[222.840466,119.193738,36.003600,133.376974]` | 511.414778 | 113.420000 | 24571.307946 |
| 0.0003 | `[223.658694,121.102598,36.549315,135.832335]` | 517.142941 | 110.821526 | 24575.702492 |
| 0.001 | `[223.659165,121.377845,36.550298,137.467569]` | 519.054877 | 109.995741 | 24580.076249 |
| 0.003 | `[225.290753,121.925712,41.462553,137.464508]` | 526.143526 | 107.057013 | 24604.897890 |
| 0.01 | `[226.659148,121.966077,44.414041,139.650355]` | 532.689620 | 104.504173 | 24639.087053 |
| 0.03 | `[231.297622,121.918688,50.095285,139.650042]` | 542.961636 | 101.135544 | 24737.343000 |

No station reaches capacity. Validation covers state19 nominal, three separate C2 independent-path datasets, three C3 combined-medium seeds, three C3 combined-strong seeds, and the descriptive 27-path/135-replica pressure set. Each C2/C3 dataset retains its own `1/15000` probability law. The pressure set has no empirical probability and was not used for optimization.

For the adjacent `0.01 -> 0.03` segment, inventory increases by `10.272016 kg` and preparation cost by `334.060016 yuan`. Mean EENS decreases by `3.368630 kWh` nominally, `3.220111 kWh` across the three C2 sets, `6.972566 kWh` under combined-medium, `10.897538 kWh` under combined-strong, and `27.558841 kWh` on the pressure set. Pressure q95 shortage decreases by `3.045250 kg`, while pressure q99.5 and maximum shortage remain unchanged.

Actual Pearson probability movement, total variation, ESS, top-loss probability masses, serviceable-shortage mass, and all-unreachable mass are reported from the optimized adversarial probabilities.
At eta `0.03`, the optimized adversary uses divergence `0.03`, TV distance `0.0385846`, ESS `14563.1068`, and a maximum probability `3.60231` times the nominal mass. The top-loss `0.1%/0.5%/1%/5%` masses move from `0.001/0.005/0.01/0.05` to `0.0031754/0.0129436/0.0227819/0.0811626`.

Scenario categories are frozen from SAA shortage and structural reachability: A no SAA shortage, `12799/15000`; B reachable inventory-responsive shortage, `214/15000`; C partial road-limited shortage, `252/15000`; D fully unreachable or road-floor shortage invariant through eta `0.03`, `1735/15000`. The global maximum-shortage scenario is category C. The stricter diagnostic for an entirely unreachable scenario is zero-mass; this is distinct from category D, which also includes road-floor inventory-invariant cases.

Development `run-001` failed at eta `0.0003` with MATLAB native heap corruption during decomposition. `run-002` completed eta `0.001` and wrote passing case outputs but returned the same nonzero native teardown exit. Both are preserved locally and excluded from Git. The C5C-only copied decomposition driver applies the frozen single-thread setting to both master and recourse LPs; no C5B or formal solver was modified. All 19 isolated `run-003` processes exited zero.

Judgment B is bounded: eta `0.03` may be carried as an additional high-guarantee 35-state candidate because it retains measurable value under strong probability shifts and in pressure-set mean/q95 outcomes. It is not universally superior, pressure q99.5 and maximum shortage are flat, and the marginal nominal EENS gain per added kilogram decreases. No MSP, 35-state solve, Wasserstein model, CVaR objective, station-to-station transport model, or validation reoptimization was executed. `C*y` remains a strict secondary tie-break only. Eta remains unfrozen.
