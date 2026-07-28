# Step-03Y-B period versus aggregate operating-loss audit

## Scope

The audit uses only the 36 frozen Step-03W pairs, their fixed T_r/T_s layouts, frozen aggregate operating losses, and deterministic Step-03Y-A recovery of the pair endpoints. It does not optimize TerminalLOH or compute a distance.

## Period model

Each W1/W2/W3 demand is balanced separately by period service and period shortage. Period reachTau controls service feasibility and costTau is the service coefficient. For each site, service summed over all three periods and all nodes is bounded by the supplied fixed TerminalLOH. There is no advance service and no shortage carryover. Operating loss remains service cost plus M times shortage, with M=2000.

## Mechanical tests

All required tests pass: T=0 produces shortage equal to total three-period demand; identical period A/C reproduces the static total-demand LP; reachability (1,1,0) serves periods 1 and 2 and forbids period 3; period-3 unreachability does not remove the first two periods' service cost.

## Results

- Fixed-T evaluations: 144 from 36 pairs.
- Relative difference >=10%: 15/144 (0.104167).
- Aggregate overestimate/underestimate/equal: 74/4/66.
- Large differences using service relations hidden by aggregate A/C: 13/15.
- Pair loss-gap changes >=10%: 21/36.

## Interpretation

Aggregate and period losses are not generally close under the 10% diagnostic.
The aggregate model generally overestimates operating loss.
Temporal reachability compression is an important source of the observed loss differences.
A small fixed-sample TerminalLOH comparison is worth performing.

## Boundaries

Only five Gurobi invocations were made: four small mechanical-test calls and one block-diagonal batch of 144 independent fixed-T period LPs. No T variable, WDRO, MSP, validation input, new scenario, Q_agg recomputation, or formal-model modification was used. Existing untracked paths were hash-checked and unchanged.

runtime_sec=17.020104
