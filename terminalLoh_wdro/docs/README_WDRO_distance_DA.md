# WDRO Distance Update: DA Main Metric

## Why DA Replaces DAC

The main WDRO-TerminalLOH distance now uses demand and reachability:

`xi = (D, A)`

This avoids double-counting unavailable service. Reachability loss is already
captured by `A`; adding service cost `C` for unreachable site-node pairs can
count the same disruption again, especially when unreachable costs are stored
as very large values or `Inf`.

## Consequence Vector

- `D`: 33-node hydrogen demand vector.
- `A`: 4-site by 33-node binary reachability matrix.

`A_{i,n}=1` means site `i` can serve node `n`; `A_{i,n}=0` means it cannot.
`A` is not a slowdown factor and should never be encoded as a fractional
value such as `0.3`.

`C` represents the service cost, travel impedance, or travel time conditional
on reachability. If a typhoon causes flooding, congestion, fallen trees,
detours, or speed limits but the route is still usable, the scenario should
keep `A=1` and increase `C`. Do not use `A=0.3` to represent a road that is
reachable but slow.

## DA Distance

For a fixed state `k=(a,loc,lf=7)` and scenarios `r,s`:

`d_rs = w_D * d_D(r,s) + w_A * d_A(r,s)`

with:

`d_D(r,s) = ||D^r - D^s||_1 / (D_max + eps)`

`d_A(r,s) = ||A^r - A^s||_1 / (A_max + eps)`

`D_max = max_{r,s} ||D^r - D^s||_1`

`A_max = max_{r,s} ||A^r - A^s||_1`

Default weights:

- `w_D = 0.7`
- `w_A = 0.3`

If a component scale is numerically zero, that component is set to zero.

## Finite Discrete Support

For each state `k`, the support is the finite scenario set:

`Xi_k = {xi^1(k), xi^2(k), ..., xi^R(k)}`

The Wasserstein transport problem moves probability mass between complete
scenario atoms. It does not continuously perturb one component of `A`.

Therefore the ambiguity set does not generate values such as:

`A_{i,n}=0.3`

Reachability remains a binary scenario attribute.

## Why C Is Not in the Main Distance

`C` is a service-cost consequence. It is useful after reachability is known,
but using it in the main scenario distance can duplicate the effect of
unreachability:

- `A` already records whether service is possible.
- Unreachable rows may store `C=Inf` or a very large penalty-like value.
- Comparing that `C` directly would make one unreachable event appear in both
  the reachability term and the cost term.

For this reason, the main method is `DA`.

Slow but passable roads are still represented in the data interface: they have
`A=1` and a larger `C`. The main `DA` distance deliberately ignores that cost
variation, while `DAC_maskedC` can be used as the cost-aware sensitivity
extension.

## DAC_maskedC Extension

`DAC_maskedC` is retained as a sensitivity extension:

`xi = (D, A, C)`

For each scenario pair `r,s`, the cost mask is:

`mask_{i,n}^{rs}=1` only if `A_{i,n}^r=1` and `A_{i,n}^s=1`.

Only those commonly reachable entries contribute to the cost difference:

`cost_diff_masked(r,s) = sum_{mask=1} |C_{i,n}^r - C_{i,n}^s|`

If the common-reachable mask is empty, the masked cost difference is zero.
If one scenario is reachable and the other is unreachable, that difference is
expressed only by `A`; the unreachable-side `Inf` or large-M service cost does
not enter the masked `C` term.

Default weights:

- `w_D = 0.6`
- `w_A = 0.25`
- `w_C = 0.15`

This keeps cost variation available for sensitivity analysis without letting
unreachable large costs dominate the distance.

## Legacy DAC

The old `DAC` mode is a legacy/unmasked compatibility mode. It is not the
recommended main method because it can mix reachability loss and service-cost
effects for the same unavailable site-node pair.

## Rho Selection

`rho` is the Wasserstein ball radius. It controls how far the true
distribution may deviate from the empirical distribution on the finite support.

- `rho=0`: empirical sample average/SAA.
- Larger `rho`: permits more mass to move toward high-loss scenarios.

`rho` should be selected through sensitivity analysis and out-of-sample tests.
The current single-window `R=10` data are only for prototype validation, so
formal comparison should be repeated after generating W=3 look-ahead samples
with larger scenario counts such as `R=50/100`.

## Recommended Comparison

Future experiments should compare:

- `D_only`: baseline/debugging distance.
- `DA`: main method.
- `DAC_maskedC`: cost-aware sensitivity extension.

The comparison should be based on out-of-sample service loss and TerminalLOH
performance, not only in-sample objective values.
