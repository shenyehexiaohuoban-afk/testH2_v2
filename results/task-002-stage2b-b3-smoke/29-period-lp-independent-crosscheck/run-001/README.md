# Step-03Y-B-A independent three-period LP cross-check

The 144 frozen fixed-T evaluations from Step-03Y-B were deterministically recovered again. W1-W3 were concatenated into 99 time-node slots and passed directly to evaluate_step03T_fixed_T_recourse_h2.

Both helpers used the same four-site T row, M=2000, objectiveScale=1, FeasibilityTol=1e-09, and OptimalityTol=1e-09.
The comparison uses operating_loss only. The static helper's holding_cost and full_objective were not used as target quantities.
costTau values were concatenated without averaging or rescaling.

status=FAIL
maximum_required_error=22.653628999268584
solver_tolerance=1.0000000000000001e-09
solver_call_count=2; WDRO=0; MSP=0; validation=0.
runtime_sec=9.854287
