# Stage-89M formal adoption and correct-8h integration

Status: **PASS**. Stage89J `run-001` is now the current adopted W mainline, Stage89K `run-002` is now the current adopted TerminalLOH, and Stage89L `run-001` remains the formal mechanism ablation that supports adoption. Stage88 is preserved in place as the superseded, historically reproducible predecessor.

## Adoption and evidence boundary

Stage89L is sufficient adoption evidence because its strict road-only versus dual-channel comparison holds the Stage89J bank, Stage89K economics, exact probabilities, Pearson ambiguity, capacity, shared-T LP, and solver gates fixed, changes only `Aelec`, reuses Case C read-only, and obtains 35 SAA + 35 DRO optimal solutions in both arms. It finds a small aggregate DRO reserve increase (`+0.875626%`), material site reallocation and service-mode substitution, and moderate shortage reduction. Therefore `Stage88 → Stage89K` remains the **FULL CANDIDATE EFFECT**; the approximately `-27.44%` DRO mean TerminalLOH change is not an H2 electrical-island-only effect.

## Current identities and navigation

- Current adopted W: `results/task-002-stage2b-b3-smoke/stage89j-topology-h2-dual-channel-w-candidate/run-001`.
- Current adopted TerminalLOH: `results/task-002-stage2b-b3-smoke/stage89k-terminalLoh-dual-channel-candidate/run-002`.
- Adoption evidence: `results/task-002-stage2b-b3-smoke/stage89l-h2-island-incremental-ablation/run-001`.
- Single bundle: `terminalLoh_wdro/current_w_mainline_stage89/`.
- Large bank: `terminalLoh_wdro/output/stage89j_topology_h2_dual_channel_w_candidate/run-001/`.
- Scenario signature: `(Dres,Aroad,Aelec,C)`; `R=15000` for each of 35 starting states; `q_g=multiplicity/15000`.
- Pearson DRO `eta=0.03`; tank capacity `[300,200,100,200] kg`.
- SAA table SHA-256: `3ef6d441dddcd15056b97da6e03944705a41900397ee7576e0e700c6237c7148`.
- DRO table SHA-256: `2fa1958944110701239a109ebf46d959324a351f2f27c1c3fbd62f333066eaa8`.
- Stage89J 35-bank aggregate manifest identity: `5e6c7e062d557b78a39f4f2cf1deedea6a51fc515f663a9222d97403ae362062`.

The 1.10 GB bank was not copied because the accepted body already exists under the large-output policy; the current bundle contains a one-jump large-data manifest plus lightweight schema, summaries, QA, source snapshots/references, adopted tables, evidence and hashes.

## FA-MSP integration result

The bridge uses the accepted Stage89F resolved architecture: six operating stages, eight actual hourly blocks per stage, 48 total operating hours, hourly IEEE33, P_EL, original H2 demand, production, inventory, directed continuous HTT and PV. Stage7 is analytic TerminalLOH and Stage8 is zero-cost absorbing. `NormalDemand.stage_dt_h=6` is source metadata only; active `params.dt_h=8`. No legacy 6h path was used.

The production sentinel is `[46.8,31.2,18.72,23.4] kg`, total `120.12 kg`. The legacy `90.09 kg` sentinel was not triggered. Site4 is correctly separated as `200 kg` tank and `150 kW` electrolyzer Pmax; accepted initial inventory was unchanged and not capacity-rescaled.

Both adopted SAA and DRO tables load with 35-state/4-site/version/hash/capacity gates; default bridge selection is DRO. Stage7 value and four-dimensional subgradient, one backward terminal cut, and forward terminal evaluation all pass. Negative gates reject Site4 tank=150, Stage88 masquerading as Stage89K, Stage53 legacy input, a 6h runtime, and any operating-stage hourly count other than 8.

No forward/backward core, cut mathematics, training loop, Stage1 cut semantics, hourly-grid mathematics, HTT mathematics or demand mathematics was changed. Stage89G multi-location adaptation was not used. No FA-MSP training, OOS or checkpoint was run or created.

## Stage89N preparation note (not executed)

Stage89N should use the Stage85R accepted single-initial-state runner mother, Stage85H-A lifecycle (`train → save → MATLAB exits → zero MATLAB processes → clean process loads exactly once → reload audit → OOS`), Stage89F correct 8h model, adopted Stage89K DRO table, Site4 tank=200 kg, and one known initial loc4. It must not reload in the training process, duplicate-load `modelLib`, reload merely to hash, or hold a second `modelLib` before OOS. Its first scientific sentinel is `120.12 kg → ?`.

```text
TASK_ID = Stage-89M
STAGE89M_STATUS = PASS
STAGE89J_PREREQUISITE_CONFIRMED = YES
STAGE89K_PREREQUISITE_CONFIRMED = YES
STAGE89L_PREREQUISITE_CONFIRMED = YES
STAGE89J_ADOPTED_AS_CURRENT_W = YES
STAGE89K_ADOPTED_AS_CURRENT_TERMINALLOH = YES
STAGE88_PRESERVED_AS_HISTORICAL_PREDECESSOR = YES
STAGE89_SINGLE_BUNDLE_CREATED = YES
STAGE89_BUNDLE_PATH = terminalLoh_wdro/current_w_mainline_stage89/
LARGE_BANK_DUPLICATED = NO
LARGE_DATA_MANIFEST_CREATED = YES
CURRENT_W_SIGNATURE = (Dres,Aroad,Aelec,C)
DRO_ETA = 0.03
TANK_CAPACITY_KG = [300,200,100,200]
FORMAL_8H_MAINLINE_USED = YES
LEGACY_6H_PATH_USED = NO
OPERATING_STAGE_COUNT = 6
HOURS_PER_STAGE = 8
TOTAL_OPERATING_HOURS = 48
HOURLY_VARIABLE_QA = PASS
STAGE1_THEORETICAL_MAX_KG = 120.12
LEGACY_90P09_SENTINEL_TRIGGERED = NO
SITE4_TANK_KG = 200
SITE4_PMAX_KW = 150
INITIAL_INVENTORY_RESCALED = NO
STAGE89K_DRO_TABLE_LOADED = YES
STAGE89K_HASH_QA = PASS
STATE_MAPPING_QA = PASS
STAGE7_VALUE_SUBGRADIENT_QA = PASS
BACKWARD_TERMINAL_CUT_SMOKE = PASS
FORWARD_TERMINAL_EVAL_SMOKE = PASS
BACKWARD_CORE_MODIFIED = NO
FORWARD_CORE_MODIFIED = NO
MULTILOC_TRAINING_USED = NO
MULTILOC_STAGE1_CUT_ADAPTATION_USED = NO
MULTILOC_STAGE1_ADAPTATION_USED = NO
FA_MSP_TRAINING_RUN = NO
OOS_RUN = NO
CHECKPOINT_CREATED = NO
VERSION_EXPLAIN_UPDATED = YES
READY_FOR_STAGE89N = YES
RECOMMEND_NEXT_STAGE = Stage-89N: single-loc4 fresh correct-8h FA-MSP retraining using adopted Stage89K DRO TerminalLOH
GIT_COMMIT_CREATED = NO
GIT_PUSH_ATTEMPTED = NO
```
