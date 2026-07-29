# C Scale Provenance Audit

## What C represents

The period recovery uses `edgeCost=roadLength*(1+slowdown)` and sets closed edges to `Inf`, then runs the current-road-state shortest path. C therefore includes both open-road slowdown and detours caused by closures. It is not a baseline distance.

## Exact C bound

Road failure probability/slowdown is clipped to [0,1], so every finite edge cost is at most twice its road length. Positive edge costs imply a finite shortest path can be selected simple and use each of the 41 edges at most once. Therefore:

`C_bound=2*sum(all road lengths)=2*178.57632237080395=357.1526447416079 km`. The lengths are recomputed from the frozen `NearStageInput` layout node coordinates and the CSV road endpoint IDs, exactly as in Step-03Q; the CSV `length_km` column is not the frozen bound source.

This is a topology/model-derived upper bound on any finite post-disaster shortest-path C value. It is not the observed maximum shortest path, not the observed maximum C difference, and not merely the unmultiplied road-network total length.

Because finite C is nonnegative and bounded by C_bound, `abs(C1-C2)<=C_bound`; the denominator is therefore formula-compatible with the numerator. It is conservative rather than invalid.

## Nominal full scan

The scan reads all 525000 stored nominal aggregate D/A/C records in state blocks. It does not read validation. For the numerator, the exact maximum pair difference at a fixed state/site/node coordinate is computed as finite max minus finite min, without constructing a pair matrix.

- finite reachable C values: 60963033
- minimum finite C: 0 km
- maximum finite C: 129.02475211610735 km
- maximum same-state, same-coordinate finite abs difference: 117.808534620188 km
- maximum difference identity: state 29, site 1, node 23
- maximum C / C_bound: 0.36125940551120356
- maximum finite difference / C_bound: 0.32985485717295998
- C_bound violations: 0
- same-coordinate difference violations: 0

The bound is 3.03164 times the largest observed nominal same-coordinate finite difference. This reduces the numerical size of the continuous reachable-reachable term, but reachability mismatch remains exactly 1 and the theoretical Ctilde weighted contribution remains at most 0.4.

## Selected Step-03Z-C period ranges

| state | observed max d_Ctilde_period | weighted max at 0.4 | nominal max C | nominal max same-coordinate difference |
|---:|---:|---:|---:|---:|
| 7 | 0.171787579093577 | 0.068715031637430798 | 71.343830628173805 | 61.208282586916923 |
| 9 | 0.63285658177159898 | 0.25314263270863963 | 97.735895010832351 | 95.428202703140045 |
| 11 | 0.519116464424347 | 0.20764658576973882 | 114.51612781986431 | 102.67612573123905 |
| 19 | 0.88482824881252897 | 0.35393129952501162 | 101.39114567558673 | 89.999880545605208 |

Assessment: Cscale is matched to the finite-value difference numerator but is conservative. No C scale formula mismatch is found, and this task does not change C_bound or the 0.4 weight.
