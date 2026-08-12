# Stage-71 cross-experiment analysis

Status: PASS after independent mechanical verification and visual QA.

Baseline is the frozen accepted Stage-57/65 result. E1/E2/E3 use isolated one-hour fixed-budget policies and the exact frozen 10000x8 common OOS paths. Every sensitivity policy stopped at the 3600-second budget with `stop_flag=2`; none is described as formally converged. Reported objective remains separate from modeled operating cost.

The accepted interpretation is recorded in `stage71_judgment.txt`. The evidence is descriptive: E1/E2/E3 are separate fixed-budget learned policies, so differences are not treated as causal identification of stage duration, Pmax, or HTT capacity.
