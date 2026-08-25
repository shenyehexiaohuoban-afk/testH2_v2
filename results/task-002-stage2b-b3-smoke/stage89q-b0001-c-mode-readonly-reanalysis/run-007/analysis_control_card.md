# Analysis Control Card

OOS_ANALYSIS_PROTOCOL = FOUR_LEVEL_ABCD_V1_1
RUN_MODE = C
ACTIVE_LEVELS = LEVEL_1_FULL + LEVEL_2_FULL + LEVEL_3_MECHANISM
TRAINING_STATUS = UNSTABLE
EVIDENCE_GRADE = EXPLORATORY
ANALYSIS_NATURE = RETROSPECTIVE_DIAGNOSTIC
OOS_EXECUTION = READ_ONLY_REUSE
ALLOWED_CHANGE = ANALYZER_AND_NEW_ANALYSIS_OUTPUT_ONLY

RESEARCH_QUESTION = 为什么 B0001 增加 S4 Pmax 后总制氢量增加，但逐站 TerminalLOH 可靠性恶化？
BASE_POLICY = Stage89Q long-training Arm-A penalty1000 OOS; checkpoint SHA b6533668...9328
CANDIDATE_POLICY = Stage89Q B0001 S4-Pmax187.5 exploratory checkpoint; SHA 3c604ad...46ca
OOS_PATH_BANK = Stage89H loc4 seed 20260817, ordered 10000 paths, SHA 6bf3d119...386c
PRIMARY_METRICS = site-wise terminal gap, total quantity shortfall, location component, positive-target failure rate, path transitions, production timing
SPECIAL_COHORTS = NEW_FAILURES, RECOVERED_PATHS, PERSISTENT_FAILURE, PERSISTENT_ADEQUATE
NUMERICAL_TOLERANCE = 1e-7 kg for terminal recomputation; finite numeric checks required
STATISTICAL_METHOD = paired path means/medians/quantiles; no independent holdout claim
UPGRADE_PERMISSION = NO
STOP_CONDITION = stop on identity, common-path, ledger, terminal-formula, or data-integrity failure
DEFERRED_LEVELS = LEVEL_4 fresh holdout/perfect-information/sensitivity
DATA_LIMITATIONS = no counterfactual dispatch, no terminal redistribution, and no decision-time future terminal location
CONCLUSION_DISCOUNT = all B0001 mechanism claims remain exploratory because training stability failed
HARD_QA_STATUS = PASS

The analyzer uses only persisted CSV/MAT artifacts and preserves all input/checkpoint hashes in source_manifest.csv.
