# OOS framework

`run_candidate_oos.m` is the generic candidate evaluator. It loads a supplied
checkpoint and common-path bank, calls the canonical policy evaluator, writes
path summaries, metadata and QA markers under the candidate's `results/oos`
root, and leaves checkpoint/model files read-only. `START_OOS.ps1
VALIDATE_RULE` only resolves the single project-level `codex_rule/OOS_rule.md`;
no second rule copy is stored in this package. No OOS bank or historical
evaluation is shipped in this template.
