# Stage-89Q run-002 stop record

Status: **STOPPED after Arm-A training because the clean-process checkpoint boundary failed**.

The restarted environment preflight passed with zero MATLAB, MATLAB-worker, and Gurobi processes. The Stage89Q local draft was re-audited. The serializer smoke used explicit serialization OFF and ON solves on the same ordered path; objective, production, inventory, ordinary shortage, HTT, and every reached-stage total matched exactly. All four hourly physical-closure residuals were zero. Source commit `cfa789f262b323de1775e5e2376a2d23978753ef` was then pushed before formal training.

Arm-A (`penalty=1000`) started fresh with zero cuts, no warm start, and training seed `20260513`. It completed the current legal iteration after the 18000-second budget boundary:

- training wall time: `18005.0706891 s`;
- completed iterations: `346`;
- final lower bound: `57955.8974092764`;
- cumulative cuts: `363646`;
- final Stage1 production: `113.88 kg`;
- training warnings/errors reported by the MATLAB loop: `0/0`.

The training function wrote `training_summary.csv`, `TRAINING_FINISHED.txt`, and a `332032355`-byte checkpoint. During normal MATLAB shutdown, however, MATLAB returned native exit status `0xc0000374` (`Heap corruption`). Windows then continued to enumerate orphan `MATLAB.exe` PID `9668` with absent parent PID `30756`, no executable path or command line, and a 32 KB working set. The process remained after a 30-second recheck.

Because `MATLAB_PROCESS_COUNT = 1`, the required sequence `training -> save -> MATLAB fully exits -> process count 0 -> external SHA256` cannot be proven. The checkpoint is therefore **not accepted**, and any diagnostic hash observed while PID 9668 remained is not a formal Stage89Q checkpoint identity. No checkpoint was loaded.

Arm-B training, the common OOS-bank phase, both OOS evaluations, result QA, analysis, figures, and Phase-B result commit/push were not started. The source-freeze commit remains valid and pushed; this failed run and its large checkpoint remain local and uncommitted.

```text
TASK_ID = Stage-89Q
RUN_ID = run-002
STAGE89Q_STATUS = STOPPED
STOP_CONDITION = 11
STOP_REASON = MATLAB_NATIVE_EXIT_LEFT_ORPHAN_PROCESS_AFTER_ARM_A_CHECKPOINT
MATLAB_NATIVE_EXIT = 0xc0000374
BLOCKING_PID = 9668
MATLAB_PROCESS_COUNT = 1
HOURLY_SERIALIZER_REGRESSION = PASS
STAGE89Q_SOURCE_FREEZE_COMMIT = cfa789f262b323de1775e5e2376a2d23978753ef
SOURCE_PUSH_STATUS = PASS
ARM_A_TRAINING_COMPUTE_COMPLETE = YES
ARM_A_CHECKPOINT_ACCEPTED = NO
ARM_B_TRAINING_RUN = NO
OOS_RUN = NO
FORMAL_ANALYSIS_RUN = NO
STAGE89Q_RESULT_COMMIT_CREATED = NO
STAGE89Q_RESULT_PUSH_ATTEMPTED = NO
```
