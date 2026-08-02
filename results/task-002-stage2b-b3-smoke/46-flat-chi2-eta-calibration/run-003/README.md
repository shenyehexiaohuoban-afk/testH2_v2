# Step-04C-C1 run

- Status: PASS; accepted as the formal Step-04C-C1 run after the final protection and Git-scope audit.
- Scope: state19 only; pure flat Pearson chi-square DRO eta initial screening.
- Eta grid: `[0.0, 0.0001, 0.0003, 0.001, 0.003, 0.01, 0.03, 0.1]`. The grid was not changed after results were observed.
- validation-1/2 are second-layer wind-speed and resistance redraws on the same typhoon paths. They are not independent-path out-of-sample validation.
- The 27 state19 extreme paths and 135 frozen consequence replicas are used only as a fixed, reproducible, isolated stress set. They are not assigned empirical probability and are not included in the optimization objective.
- q95/q99/q99.5 and CVaR95/CVaR99/CVaR99.5 in the validation table refer to operating loss. Mean total cost adds the fixed first-stage inventory cost to mean operating loss.
- Recommendation status: `PRELIMINARY_TWO_POINT_CANDIDATE_SET_FOR_INDEPENDENT_PATH_VALIDATION`.
- Preliminary eta candidates for the next different-path-seed validation: `0.003, 0.01`.
- Candidate roles: `0.003` is the upper edge of the low-inventory plateau; `0.01` is the first capacity-binding structural jump and is retained as an upper-bound validation point.
- Eta `0.03` and `0.1` are excluded from the shortlist because they add substantial inventory while the state19 stress q95 and maximum loss remain unchanged.
- No formal eta is frozen. Different-path-seed validation and Markov transition-probability perturbation remain required.
- Step-04C-A/A2 frozen inputs and established interpretation are reused; their full results are not repeated here.
