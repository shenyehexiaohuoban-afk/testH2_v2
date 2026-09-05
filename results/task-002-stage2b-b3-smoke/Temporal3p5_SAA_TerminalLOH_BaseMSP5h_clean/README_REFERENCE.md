PACKAGE_ROLE =
CANONICAL_STAGE89Q_BASE_EXPERIMENT_REFERENCE

MODEL =
Stage89Q Base

BASE_PMAX_KW =
[300,200,120,150]

CANONICAL_BASE_K_INIT =
81

K_INIT_SOURCE =
RUN_CONFIG.txt K_INIT, propagated by START_TRAINING.ps1/START_OOS.ps1;
the common-path bank first-state identity is checked against checkpoint params.k_init.

TERMINAL_MODE =
DIRECT_GAP

TERMINAL_REDISTRIBUTION =
OFF

TERMINAL_GAP_PENALTY =
1000

OPERATING_ARCHITECTURE =
6 x 8 h hourly FA-MSP

TERMINALLOH =
current adopted Stage89K / Stage89M lineage

PURPOSE =
This directory is a complete clean runnable experiment template. It contains the canonical program, launch/config framework, testing rule gate, analysis source templates, and empty output areas.

PROGRAM_INCLUDED =
YES

TRAINING_FRAMEWORK_INCLUDED =
YES

OOS_FRAMEWORK_INCLUDED =
YES

ANALYSIS_FRAMEWORK_INCLUDED =
YES

HISTORICAL_TRAINING_RESULTS_INCLUDED =
NO

HISTORICAL_OOS_RESULTS_INCLUDED =
NO

HISTORICAL_ANALYSIS_RESULTS_INCLUDED =
NO

CHECKPOINTS_INCLUDED =
NO

CANONICAL_OOS_RULE =
<project-root>/codex_rule/OOS_rule.md

Pmax, terminal mode, penalty, and Stage90 state are explicit in RUN_CONFIG.txt and are checked by the Base training entry.
Testing applies a candidate-agnostic checkpoint/path-bank compatibility gate before eval_h2. It requires a unique bank first-state identity, matching checkpoint params.k_init, a struct model at modelLib.models{1,k_init}, and valid beq/rowMap.inventory_eq fields. Incompatibilities are recorded as CHECKPOINT_PATHBANK_COMPATIBILITY_QA=FAIL with FAILURE_CLASS=CHECKPOINT_PATHBANK_INITIAL_STATE_MISMATCH before any path solve.
Future experiments should clone this directory, keep program/ unchanged, and write all training, OOS, analysis, checkpoints, logs, and manifests inside the clone.

## Standard candidate lifecycle

```text
BASE reference
    | clone
candidate package
    | configure RUN_CONFIG.txt
training/ -> results/formal_training/
testing/  -> results/oos/
analysis/ -> results/analysis/
```

Set `CANDIDATE_ID`, `PMAX_KW`, checkpoint and common-path-bank inputs in the
clone's `RUN_CONFIG.txt`.  The canonical program remains unchanged; candidate
variation belongs in configuration and runtime metadata.  Historical runs may
remain at their original legacy locations.  Do not move historical outputs
solely to make directory structure prettier.
