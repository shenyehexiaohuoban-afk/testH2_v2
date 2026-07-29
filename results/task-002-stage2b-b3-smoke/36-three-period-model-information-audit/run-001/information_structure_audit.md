# Information structure audit

## Implemented classification

The code implements **two-stage full-scenario information with three-period recourse**, not a strict multistage sequential-revelation model.

- Stage 1: one common T vector is shared by all R scenarios.
- Stage 2: after a scenario is selected, all W1-W3 `y` and `u` variables for that complete scenario are optimized in one LP.
- W1 service competes with W2/W3 for the same T and is solved with all future-period D/A/C coefficients already present. It can therefore depend on W2/W3 information.
- No constraint requires two scenarios with the same W1 history to use the same W1 decision.
- No scenario-tree nodes, history-indexed decisions, or nonanticipativity rows exist.
- Only T is scenario-common; all operating variables are complete-scenario-specific.

This is a precise classification of the implemented deterministic equivalent. It does not decide whether full future information is the intended physical assumption.
