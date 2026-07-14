# Accepted Research Baseline

Baseline date: 2026-07-14

This document records the currently accepted foundation state. It is a status
record, not permission to run the next modeling stage automatically.

## Foundation Fix

- The Foundation coordinate and risk-chain fix has been completed and re-audited.
- Typhoon-center coordinates feed the point-to-segment distance, local wind,
  line failure, road closure, connectivity, load-loss, D, A, and C chains.
- The v2 recommendation logic evaluates Wstep candidates symmetrically and can
  return 40, 45, or an inconclusive result; it is not hard-coded to prefer 40.

## Hres Time Convention

- W1, W2, and W3 each represent one hour.
- `Hres_total_h = 3`.
- Hres demand is `D_W1 + D_W2 + D_W3`.
- The lf=7 reference slice is not included in the three-hour demand total.

## Spatial Step

- The accepted recommendation is `Wstep=40`.
- `Wstep=45` remains the documented comparison case.
- The recommendation is supported by line-failure, road-closure, and D direction
  checks across `Rmax=30/40/50`.

## Damage Persistence Convention

- For a future formal B3 run without repair, the selected primary convention is
  `persistent_fixed_resistance`.
- Each component/scenario receives one fixed uniform resistance threshold shared
  by W1-W3.
- A line or road first fails when the stage probability crosses its threshold;
  the failed state then persists. Road slowdown retains the historical maximum.
- `independent_snapshot` and `persistent_independent_draws` remain comparison or
  ablation conventions, not the preferred formal no-repair convention.

## Not Yet Executed

The following remain pending and must not be inferred from this baseline:

- Stage2A2;
- formal Stage2B3 scenario generation;
- Stage2C DA-WDRO;
- integration of the offline result into the MSP main model.

The detailed execution history and verified numerical evidence remain in
`codex_rule/log.md`. Generated outputs are intentionally excluded from Git.
