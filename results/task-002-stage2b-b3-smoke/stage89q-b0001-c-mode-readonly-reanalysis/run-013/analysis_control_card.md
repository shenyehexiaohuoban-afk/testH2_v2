# B0001 C-mode closeout control card

RUN_MODE = C
TRAINING_STATUS = UNSTABLE
EVIDENCE_GRADE = EXPLORATORY
ANALYSIS_NATURE = RETROSPECTIVE_DIAGNOSTIC
OOS_EXECUTION = READ_ONLY_REUSE
ALLOWED_CHANGE = ANALYZER_AND_NEW_ANALYSIS_OUTPUT_ONLY

ANALYSIS_QA = PASS
C_MODE_COVERAGE = COMPLETE
C_MODE_EVIDENCE = MIXED
B0001_CANDIDATE_JUDGMENT = EXPLORATORY_SIGNAL_ONLY

CI_METHOD = paired normal 95% CI for path-level B0001-minus-Base differences; no fresh holdout claim.
TARGET_GROUP_RULE = ZERO target <= 0; LOW/MEDIUM/HIGH are Base positive-target tertiles, applied identically to both arms.
TAIL_RULE = retrospective Base terminal_site_gap rank: DIFFICULT4 = 95-99%, EXTREME1 = top 1%, WORST_PATH = maximum with path_id tie break.
FAILURE_STOP_GATE = common path, identity, terminal formula and input hash checks passed.
LIMITATIONS = no optimistic recoverability LP, no counterfactual grid/tank/HTT relaxation, no stable B0001 policy, no terminal redistribution.
