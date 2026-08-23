# Stage-89O：Stage89H vs Stage89N 全面政策机制后处理

状态：**PASS**。本任务只读取两个 accepted run 的既有 CSV；没有训练、OOS、checkpoint load、优化求解或模型修改。

## 研究故事

1. **总体储备水平。** mean total production 从 322.677 降到 186.005 kg/path（-42.36%）；Stage1 为 120.12→109.98 kg。Stage2/3 没有补回该下降，因此是 `LEVEL_REDUCTION`，不是仅凭 Stage1 判断 wait-and-see。
2. **提前消散。** 所有 A1 路径在风险解除前的 mean cumulative production 为 233.599→132.546 kg；风险解除时 residual preventive inventory 为 112.666→11.213 kg。该量只表示解除风险后的预防性剩余库存，不称“浪费”。
3. **进入 Stage7 的风险路径。** Stage7 reserve-adequacy proxy 的加权 mean terminal gap 为 10.371→9.117 kg，判断 `IMPROVED_MEAN_PROXY`；但按到达时间拆开后，S2/S3/S4→Stage7 分别改善 4.132/4.121/2.224 kg，S5 与 Stage6→Stage7 却恶化 1.036/2.920 kg。平均改善没有覆盖晚到达尾部，实际 W recourse 仍未闭合。
4. **shared-prefix 后适应。** 严格继承 Stage85U-D 的 canonical A1-vs-Stage7 PCR/WES 定义，共 390 组。Production PCR median 0.876→0.903，WES production median 0.124→0.097；综合 `WEAKENED`。这不否认 834 组 different-intensity pairs 中 high-minus-low post-divergence production mean 从 64.632 增至 84.538 kg：强度条件响应增强与 a1-vs-Stage7 的整体 post-divergence share 变弱是两个不同问题。
5. **空间 loc response。** 1,535 组 same-intensity/different-loc pairs 将 total inventory difference 与 4D inventory L1 分开报告；4D L1 mean 从 65.061 降至 51.223 kg（paired mean -13.838 kg），综合 `WEAKENED`。L1 衡量空间分离，不能解释成总储备增加。
6. **经济机制。** mean actual operating cost 为 62,094.59→56,182.45 yuan/path，reported objective 下降 9.76%。在 1,386 条 shortage 改善路径中，1,383 条同时具有更低 terminal inventory；因此 reserve-hoarding/service-competition 证据等级为 `MODERATE_SIGNAL`。它是很强的配对共现但仍非单因果证明；terminal-gap penalty 是 soft reserve incentive，不是现实运行支出。
7. **尾部。** q99 cost 变化 3.29%，q99 terminal gap 变化 3.64%。DeltaCost worst1% 的 100 条路径全部真正进入 Stage7，其中 a4/a5 为 51/49 条，Stage6→Stage7 enrichment=5.44。其 mean operating cost 仍下降 8,713.51 yuan，但 terminal-gap penalty 增加 85,982.49 yuan，最终 DeltaCost 增加 77,268.98 yuan；主驱动为 `REDUCED_EXTREME_RESERVE_BUFFER_PLUS_TERMINALLOH_GAP`。
8. **韧性边界。** 当前最多支持 preparedness + TerminalLOH adequacy proxy；没有 actual terminal inventory→W1-W3 recourse 的 paired output，不能声称 realized EENS、道路/电力服务或实际灾害韧性改善。

## RQ1–RQ15

- RQ1–RQ2：production/inventory 显著下降；`RESERVE_LEVEL_EFFECT=STRONGLY_REDUCED`，`AGGREGATE_TIMING_MECHANISM=LEVEL_REDUCTION`。
- RQ3–RQ4：EARLY_A1 的风险解除前制氢与 residual preventive inventory 均由 common-path paired 数据给出，Stage89N mean 变化分别 -101.053 和 -101.452 kg/path。
- RQ5：Stage7 terminal-gap adequacy proxy 的 mean 改善；按 arrival time、a、loc、(a,loc) 的异质性见对应 CSV。它不是 actual resilience。
- RQ6：a、loc 与 35-state cell 的结果见 `stage7_by_final_intensity.csv`、`stage7_by_final_loc.csv`、`stage7_by_terminal_state.csv`。
- RQ7：shared-prefix pre-divergence physical decisions 在两政策内均通过数值容差检查。
- RQ8–RQ10：different-intensity pairs 中 high-risk child 仍产生更多后续 production/build，且 level-response mean 增强；但 canonical a1-vs-Stage7 的 PCR/WES 综合显示 post-divergence effect share 变弱，因此总体 wait-and-see effect size 判断 `WEAKENED`。
- RQ11：空间 response 判断 `WEAKENED`。
- RQ12：lower inventory + higher served/lower shortage 的配对共现支持 `MODERATE_SIGNAL`，但不足以把所有改善归于 reserve hoarding。
- RQ13–RQ14：mean cost 改善与 q99 cost/gap 恶化并存；共同路径 tail attribution 与 enrichment 见对应 CSV。
- RQ15：**NO**。`ACTUAL_W_RECOURSE_CLOSURE=NO`。

## 数据可用性限制

accepted Stage89N run-003 仅保存 path/stage/site-stage CSV，没有小时级 P_EL、I_pre 或 hourly HTT 文件。故三个 `cohort_hourly_*` 文件明确采用 `STAGE_AGGREGATE_ONLY`，`local_hour=NOT_AVAILABLE_PAIRED`；没有借用 failed run-002，也没有把终止后 N/A 小时填成 0。Continuation-value marginal reanalysis 需要 checkpoint cut envelope，而本任务禁止 checkpoint load，故 `CONTINUATION_VALUE_REANALYSIS=NOT_AVAILABLE`。

```text
TASK_ID = Stage-89O
STAGE89O_STATUS = PASS
STAGE89H_ACCEPTED_IDENTITY = 89H-stage85r-single-loc4-stage88-dro-gap1000-10iter-oos10000/run-003
STAGE89N_ACCEPTED_IDENTITY = stage89n-stage89k-adopted-loc4-fresh-8h-retraining/run-003
COMMON_PATH_IDENTITY = PASS
OOS_PATH_COUNT = 10000
NO_TRAINING_RUN = YES
NO_OOS_RERUN = YES
NO_CHECKPOINT_LOAD = YES
MODEL_MODIFIED = NO
TERMINALLOH_MODIFIED = NO
UNEXPECTED_POLICY_INPUT_DIFF = NO
HOURLY_SCHEMA_QA = PASS
HOURLY_CLOSURE_QA = PASS
PATH_COHORT_QA = PASS
EARLY_STAGE7_COUNT = 5683
EARLY_A1_COUNT = 3464
EARLY_LF8_COUNT = 379
STAGE6_TO_STAGE7_COUNT = 441
STAGE6_TO_A1_COUNT = 33
STAGE6_TO_LF8_COUNT = 0
STAGE89H_STAGE1_PRODUCTION_KG = 120.12
STAGE89N_STAGE1_PRODUCTION_KG = 109.98
RESERVE_LEVEL_EFFECT = STRONGLY_REDUCED
AGGREGATE_TIMING_MECHANISM = LEVEL_REDUCTION
EARLY_A1_PREPARATION_EFFECT = REDUCED
RESIDUAL_PREVENTIVE_INVENTORY_EFFECT = REDUCED
STAGE7_RESERVE_ADEQUACY_EFFECT = IMPROVED_MEAN_PROXY
SHARED_PREFIX_NONANTICIPATIVITY = PASS
STAGE89H_PRODUCTION_PCR_MEDIAN = 0.875738788933
STAGE89N_PRODUCTION_PCR_MEDIAN = 0.903494334031
PRODUCTION_PCR_CHANGE = 0.0277555450975
STAGE89H_WES_PROD_MEDIAN = 0.124261211067
STAGE89N_WES_PROD_MEDIAN = 0.0965056659693
WAIT_AND_SEE_EFFECT_SIZE = WEAKENED
SPATIAL_ADAPTATION_EFFECT = WEAKENED
RESERVE_HOARDING_MECHANISM = MODERATE_SIGNAL
MEAN_COST_EFFECT = -9.75982112288%
Q99_COST_EFFECT = 3.28888321339%
Q99_TERMINAL_GAP_EFFECT = 3.63562733772%
TAIL_DEGRADATION_PRIMARY_DRIVER = REDUCED_EXTREME_RESERVE_BUFFER_PLUS_TERMINALLOH_GAP
CONTINUATION_VALUE_REANALYSIS = NOT_AVAILABLE
ACTUAL_W_RECOURSE_CLOSURE = NO
REALIZED_DISASTER_RESILIENCE_CLAIM_ALLOWED = NO
RECOMMEND_NEXT_STAGE = ACTUAL_W_RECOURSE_CLOSURE
```
