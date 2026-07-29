# Formal period scenario definition

For the current period-resolved SAA candidate, the optimization-relevant consequence atom is

`xi_r = {D^tau_r, A^tau_r, C^tau_r}_{tau=1,2,3}`.

`Dperiod` is `R x 3 x 33`, while `Aperiod` and `Cperiod` are `R x 3 x 4 x 33`. The Step-03Y-F PERIOD solve passes these arrays directly to `solve_step03Y_saa_audit_h2`; aggregate D/A/C are used only by the explicit aggregate comparator and cross-evaluation paths.

The recovery chain reconstructs period line failures, road closures, and road slowdown before deriving D/A/C. Failures and closures persist by logical OR, and slowdown uses the running maximum. These damage arrays are intermediate variables: the recovery helper returns `Dperiod/Aperiod/Cperiod` and identity metadata, not `failed/closed/slow` arrays. Thus the formal solver atom can be written using period D/A/C, but it does not separately retain the underlying damage-state arrays as solver inputs.

The deterministic replay previously established that recombining the recovered periods reproduces frozen nominal aggregate D/A/C exactly. This audit reuses that evidence and performs no scenario regeneration.
