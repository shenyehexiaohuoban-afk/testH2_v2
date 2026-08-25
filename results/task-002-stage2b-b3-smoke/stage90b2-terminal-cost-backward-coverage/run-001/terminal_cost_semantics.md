# Stage90B2 terminal cost semantics

- Scope: read-only audit of Stage90B run-004.
- Active source: terminalLoh_wdro\current_w_mainline_stage88\msp_bridge\near_stage_msp_input_stage88_cap200_candidate.mat; active checkpoint c0=0.
- Base-cost identity: baseCost(i,j)=0.8*roadDistance(i,j), max residual 3.5527136788e-15.
- Hourly objective: c0 + baseCost(i,j)*(1 + beta_transport_multiplier*beta), multiplier 2, hourly-v1=1.
- Terminal LP objective uses the same base matrix, beta multiplier, and c0 plus 1000*sum(g_i).

- Historical Stage85F/H02 0.2*distance and c0=5 references are inactive provenance.

## Iteration 5

- Saved record: iteration 5, stage 4, state index 199, beta 0.424285714286.
- Physical shipment 12.0568855824 kg; reported physical shipping cost 142.643290913 yuan; mean unit cost 11.8308571429 yuan/kg.
- The mean unit cost equals the minimum state-199 OD cost. It identifies the undirected Site2/Site3 pair and proves zero flow on every higher-cost OD. The two directions tie, so x_ij direction is not identifiable because run-004 did not save x_ij.
- value_yuan is physical shipping plus reserve-shortage penalty, not a probability-weighted shipping cost.

## Backward and geometry

- Backward coverage label: MODERATE on 35 saved Stage-7 states.
- Terminal value geometry changed relative to DIRECT_GAP: YES. K=160 binding signal: NONE.
- c0 identity: CONSISTENT; no active cost-semantics bug was found.
