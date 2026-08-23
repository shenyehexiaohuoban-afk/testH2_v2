# Stage-89P: Stage89N 10-iteration policy in original-paper result style

Status: **PASS**. This is read-only postprocessing of the accepted Stage89N run-003. Stage89P analyzes the FA-MSP policy generated using the adopted Stage89K Pearson probability-DRO TerminalLOH table. Stage89P did not perform DRO training, new FA-MSP training, OOS, checkpoint loading, or model modification.

## Plain-language result

This controlled 10-iteration policy produces most hydrogen in Stage1, Stage4, Stage6. Stage1 is large at 109.98 kg, but production does not stay high: Stage2 falls to 8.86 kg, followed by path-dependent later adjustments. Inventory is built immediately, then drawn down through the middle stages before later surviving paths adjust again. The direct intensity-conditioned response is **MODERATE_POSITIVE**: stronger observed intensity does not produce a uniformly monotone response at every stage, so a single “risk rises -> always produce more” claim is not supported by this 10-iteration diagnostic.

Paths that remain physically active longer generally accumulate more production before physical dissipation, and paths entering Stage7 later generally accumulate more production before the reserve check. For the 6124 true Stage7 paths, the mean TerminalLOH gap is 9.117 kg (95% CI 8.328-9.905); this is conditional on actually entering Stage7, not diluted by assigning zero gaps to other paths. Mean actual operating cost is 56182.45 yuan/path (95% CI 55707.32-56657.58). Ordinary shortage averages 1.542 kg/path and occurs on 5.34% of all paths.

Compared with the old Stage89H TerminalLOH control, Stage89N's clearest change is a lower reserve/production level rather than an equal shift of production to later stages: mean production falls from 322.677 to 186.005 kg/path, while mean ordinary shortage and mean Stage7-conditional gap also improve. The q99 objective and gap move slightly in the opposite direction; those tail reversals are secondary signals and should not be overinterpreted before longer paired training.

## Identity and scope

- Source policy: Stage89N accepted `run-003`, loc4, correct 6x8h architecture, 10 fresh iterations, no warm start.
- Ordinary shortage penalty: 200 yuan/kg. Terminal-gap soft penalty: 1000 yuan/kg.
- TerminalLOH: adopted Stage89K DRO, eta=0.03.
- OOS: 10000 accepted common paths shared byte-for-byte with Stage89H.
- Data resolution: `STAGE_AGGREGATE`; accepted Stage89N has no hourly detail. No interpolation, eightfold replication, failed-run hourly data, or post-termination zeros are used.
- The current state `a_t, loc_t, lf_t` is sampled/read before the Stage-t model is updated and solved; conditional action tables therefore use information available to the policy, not future information.
- `FULLY_CONVERGED = NO`. Ten iterations are a controlled diagnostic policy only.

## Q1. Stage1-Stage6 production

Primary means are conditional on paths that truly operate in that stage:

- Stage 1: 109.980 kg（active paths N=10000，95% CI 109.980-109.980）
- Stage 2: 8.859 kg（active paths N=8922，95% CI 8.264-9.453）
- Stage 3: 28.232 kg（active paths N=7905，95% CI 27.521-28.943）
- Stage 4: 64.684 kg（active paths N=5854，95% CI 63.776-65.591）
- Stage 5: 23.738 kg（active paths N=2581，95% CI 22.084-25.391）
- Stage 6: 38.222 kg（active paths N=474，95% CI 34.749-41.695）

Figure 3 additionally shows an unconditional per-initial-path contribution so that early termination is visible without pretending that a terminated path made a zero decision.

## Q2. Inventory and the joint production-service balance

Pattern: Stage1建立较高库存，Stage2-3明显回落，Stage4-6随仍活跃路径的风险历史而再调整.

- Stage 1: production 109.98, served 39.01, inventory 166.64->237.61 kg；PRODUCTION_EXCEEDS_ORDINARY_SERVICE; HTT_REALLOCATES_ONLY.
- Stage 2: production 8.86, served 59.49, inventory 237.61->186.97 kg；ORDINARY_SERVICE_EXCEEDS_PRODUCTION; HTT_REALLOCATES_ONLY.
- Stage 3: production 28.23, served 45.06, inventory 187.96->171.13 kg；ORDINARY_SERVICE_EXCEEDS_PRODUCTION; HTT_REALLOCATES_ONLY.
- Stage 4: production 64.68, served 37.84, inventory 174.77->201.62 kg；PRODUCTION_EXCEEDS_ORDINARY_SERVICE; HTT_REALLOCATES_ONLY.
- Stage 5: production 23.74, served 57.88, inventory 218.77->184.63 kg；ORDINARY_SERVICE_EXCEEDS_PRODUCTION; HTT_REALLOCATES_ONLY.
- Stage 6: production 38.22, served 43.44, inventory 203.93->198.71 kg；ORDINARY_SERVICE_EXCEEDS_PRODUCTION; HTT_REALLOCATES_ONLY.

At the system-total level HTT cancels exactly between origin and destination; it changes the four-site distribution, not total inventory. The maximum site-level balance residual in the accepted stage tables is 6.224e-12 kg, so the system decomposition is complete rather than guessed.

## Q3-Q4. Response after observing intensity

`RISK_INTENSITY_PRODUCTION_RESPONSE = MODERATE_POSITIVE`.

- Stage 2: grouped-mean slope 115.017 kg per intensity level, rank correlation 1.000.
- Stage 3: grouped-mean slope 73.835 kg per intensity level, rank correlation 1.000.
- Stage 4: grouped-mean slope 38.116 kg per intensity level, rank correlation 0.200.
- Stage 5: grouped-mean slope 47.404 kg per intensity level, rank correlation 0.400.
- Stage 6: grouped-mean slope 25.982 kg per intensity level, rank correlation 0.400.

These are descriptive conditional means, not causal estimates: current intensity, location, prior inventory, and history co-move. The full sample counts and 95% intervals are in `production_by_observed_intensity_and_stage.csv`. Location-conditioned results are in `production_inventory_by_observed_loc.csv`; location effects are not promoted to a main conclusion unless their stagewise differences are large and stable.

The strongest direct contrast is between `a=2` and `a>=3`: production rises sharply after the higher state is observed. Within `a=3..5`, however, several stages contain reversals, so the evidence is moderate rather than a globally monotone response. Conversely, a weakening back toward `a=2` is associated with much lower production in these descriptive groups, but not every one-step weakening has a uniform response.

Location differences are visible, especially at later stages where loc7 groups tend to produce less than loc1-loc3 groups. Figure 12 reports those category differences, but `loc` is a spatial category rather than an ordered risk score, and history/inventory composition differs across groups.

## Q5-Q8. Random termination and when risk becomes known

- Physical `a=1` dissipation is reported separately from true Stage7 arrival and from `lf=8` absorption.
- 累计制氢随更晚消散总体增加. The relevant cohort means and intervals are in `production_by_termination_timing.csv` and Figure 7.
- 累计制氢随更晚进入Stage7总体增加. Figure 8 uses only true Stage7 paths.
- `same_terminal_state_different_arrival_time.csv` holds final intensity/location fixed and reports arrival-specific means plus earliest-versus-latest descriptive contrasts. Some cells are marked `DESCRIPTIVE_ONLY` when N<30.

The results answer a process question, not a perfect-information counterfactual: later resolution gives more operating opportunities and is associated with more cumulative preparation, but histories and selection also differ.

## Q9-Q11. Economic, ordinary-service, and reserve results

- Mean actual operating cost: 56182.45 yuan/path; 95% CI [55707.32, 56657.58].
- Mean ordinary shortage: 1.542 kg/path; 95% CI [1.391, 1.693]. Any-shortage probability: 0.0534, Wilson 95% CI [0.0492, 0.0580].
- Among 6124 true Stage7 paths, mean TerminalLOH gap: 9.117 kg; 95% CI [8.328, 9.905]. Positive-gap probability: 0.1479, Wilson 95% CI [0.1393, 0.1571].

`primary_cost_decomposition.csv` separates electricity/grid, production O&M, ordinary shortage, HTT, holding/other actual cost, the TerminalLOH soft-target penalty, and reported objective. The terminal penalty is an optimization incentive, not a claimed cash payment and not realized disaster shortage.

## Q12. Stage89H to Stage89N

The old control and Stage89N share loc4, correct 8h architecture, penalties, training/OOS seeds, physical parameters, and all 10000 OOS paths. Their expected controlled input difference is Stage88 versus adopted Stage89K TerminalLOH provenance. Stage89N lowers Stage1 production from 120.12 to 109.98 kg and sharply lowers middle-stage inventory. Its mean actual operating cost changes from 62094.59 to 56182.45 yuan/path; ordinary shortage changes from 6.140 to 1.542 kg/path. This is an old-TerminalLOH control, not a definitive benchmark.

## Q13. What longer training must verify

The Stage1 decision is identical in iterations 8-10, but it changes between iterations 7 and 8; the lower bound also makes a material move at iteration 9 before a small iteration-10 increment. Therefore `TEN_ITERATION_POLICY_STABILITY = MIXED` and never `CONVERGED`. Longer paired 1000/1500 training is needed to test the mixed intensity response, late Stage7/tail reversals, spatial response, and same-terminal-state timing contrasts.

## Original-paper structure and benchmark boundary

The paper mapping is documented in `paper_analysis_mapping.md`. The original paper reports OOS mean/95% CI, action by time, response to risk/cost settings, and random landfall timing. Stage89P adopts that order while explicitly retaining this project's different physics and semantics.

`PERFECT_INFORMATION_BENCHMARK = FUTURE_OPTION`: a future benchmark could solve a deterministic 48h operating problem with each complete OOS hurricane path known in advance. It is not implemented here.

```text
TASK_ID = Stage-89P
STAGE89P_STATUS = PASS
SOURCE_POLICY = Stage89N accepted run-003
TERMINALLOH_MODE = DRO
TERMINALLOH_ETA = 0.03
TERMINAL_GAP_PENALTY = 1000
TRAINING_ITERATIONS = 10
FULLY_CONVERGED = NO
TEN_ITERATION_POLICY_STABILITY = MIXED
NEW_TRAINING_RUN = NO
NEW_OOS_RUN = NO
CHECKPOINT_LOADED = NO
MODEL_MODIFIED = NO
PENALTY_1500_RUN = NO
LONGER_TRAINING_RUN = NO
DATA_TIME_RESOLUTION = STAGE_AGGREGATE
HOURLY_POLICY_CURVE_AVAILABLE = NO
STAGE1_MEAN_PRODUCTION_KG = 109.98
STAGE2_MEAN_PRODUCTION_KG = 8.8587685659
STAGE3_MEAN_PRODUCTION_KG = 28.2318002828
STAGE4_MEAN_PRODUCTION_KG = 64.6835801025
STAGE5_MEAN_PRODUCTION_KG = 23.7375380168
STAGE6_MEAN_PRODUCTION_KG = 38.2216744343
DOMINANT_PRODUCTION_STAGES = Stage1, Stage4, Stage6
INVENTORY_BUILD_PATTERN = Stage1建立较高库存，Stage2-3明显回落，Stage4-6随仍活跃路径的风险历史而再调整
RISK_INTENSITY_PRODUCTION_RESPONSE = MODERATE_POSITIVE
EARLY_DISSIPATION_PREPARATION_PATTERN = 累计制氢随更晚消散总体增加
STAGE7_ARRIVAL_TIMING_PATTERN = 累计制氢随更晚进入Stage7总体增加
MEAN_ACTUAL_OPERATING_COST = 56182.4504173
MEAN_ACTUAL_OPERATING_COST_95CI = [55707.3244717,56657.5763629]
MEAN_ORDINARY_SHORTAGE_KG = 1.54182380137
ORDINARY_SHORTAGE_PROBABILITY = 0.0534
MEAN_TERMINAL_GAP_KG = 9.11663437969
TERMINAL_GAP_PROBABILITY = 0.147942521228
TERMINAL_GAP_DENOMINATOR = CONDITIONAL_ON_6124_TRUE_STAGE7_PATHS
STAGE89H_CONTROL_USED = YES
PRIMARY_STAGE89H_TO_STAGE89N_CHANGE = LOWER_RESERVE_AND_PRODUCTION_LEVEL_WITH_LOWER_MEAN_COST_SHORTAGE_AND_STAGE7_CONDITIONAL_GAP
STAGE89O_USED_AS_SECONDARY_EVIDENCE = YES
PERFECT_INFORMATION_BENCHMARK_RUN = NO
NEW_BENCHMARK_SOLVE_RUN = NO
READY_FOR_LONGER_1000_AND_1500_EXPERIMENT = YES
RECOMMEND_NEXT_STAGE = LONGER_1000_AND_1500_PAIRED_TRAINING
```

## Output map

Tables 1-7 correspond respectively to `policy_identity_audit.csv`, `training_progress_10iter.csv`, `production_inventory_stage_summary.csv`, `production_by_observed_intensity_and_stage.csv`, `production_by_termination_timing.csv`, `primary_oos_results.csv`, and `stage89h_vs_stage89n_primary_results.csv`. Every formal figure is listed with its machine-readable CSV and SHA-256 in `figure_manifest.csv`.
