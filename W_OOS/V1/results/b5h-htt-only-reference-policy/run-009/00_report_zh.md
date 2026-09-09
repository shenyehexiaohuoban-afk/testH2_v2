# W_OOS/V1-B5H-A HTT-only reference policy smoke

## 一句话结论

HTT-only arm 已在 3 个隔离的 synthetic/integration fixture 和 13 个 synthetic case 中通过；这些 fixture 复用 B3/B4C/B4D 接口，但不代表历史 W 路径重放；MFCV 全程关闭。该结果是行为 smoke，不是正式 W_OOS 性能结论。

## 策略规则

每个决策事件先用隔离的 no-new-HTT、MFCV-off probe 估计四个 fixed FC 到 3.5h 的 H2 需求，再计算 station surplus/deficit。空载 HTT 只从当前所在站点向可达 deficit 站运输；loaded HTT 不重新装载，直接前往 deficit 站。数量同时受 80 kg、source surplus、destination deficit、到站后剩余时间和 fixed-FC Pmax 限制。两辆 HTT 按 ID 顺序执行并立即扣减 residual surplus/deficit。

无运输条件包括：没有本地 surplus、没有可达 deficit、到站不早于 3.5h、当前不在 H2 station，或需要跨站 reposition；最后一种在 B5H-A 明确保持 STAY。

## Smoke 结果

                    fixture  EENS_OFF_kWh  EENS_ON_kWh  delta_ON_minus_OFF_kWh  HTT_transport_ON_kg  fixed_FC_H2_use_OFF_kg  fixed_FC_H2_use_ON_kg  fixed_FC_H2_exhaustion_OFF  fixed_FC_H2_exhaustion_ON  no_source_island_load_OFF_kWh  no_source_island_load_ON_kWh  source_backed_island_load_OFF_kWh  source_backed_island_load_ON_kWh          arrival_value  runtime_OFF_s  runtime_ON_s
      FIXTURE-1_NO_TRANSFER           0.0          0.0                     0.0             0.000000                     0.0               0.000000                       False                      False                            0.0                           0.0                            13002.5                           13002.5 NO_OR_NOT_IDENTIFIABLE       0.025097      0.020799
FIXTURE-2_DEFICIT_REACHABLE        1470.0        517.5                  -952.5            51.959741                     0.0              51.959741                       False                       True                         1470.0                         136.5                            11532.5                           12866.0                    YES       0.011543      0.041554
 FIXTURE-3_ROAD_CONSTRAINED        1470.0       1470.0                     0.0             0.000000                     0.0               0.000000                       False                      False                         1470.0                        1470.0                            11532.5                           11532.5 NO_OR_NOT_IDENTIFIABLE       0.019906      0.052082

EENS ON/OFF 只作为同一 fixture、同一 W/road/mask/inventory 的行为比较。正式论文不得据此写 resilience improvement percentage。

## QA 标签

B5H_A_HTT_ONLY_POLICY_SMOKE = PASS
HTT_ONLY_ARM = YES
MFCV_ENABLED = NO
MFCV_DISPATCHER_IMPLEMENTED = NO
HTT_NEED_PROBE = VERIFIED
HTT_SURPLUS_DEFICIT_POLICY = VERIFIED
HTT_CAPACITY = VERIFIED
HTT_ROAD_REACHABILITY = VERIFIED
HTT_PARTIAL_UNLOAD = VERIFIED
HTT_NO_DOUBLE_SPEND = VERIFIED
HTT_SYSTEM_H2_IDENTITY = VERIFIED
HTT_PQ_ZERO = VERIFIED
HTT_TO_MFCV_DIRECT_REFUEL = OFF
EMPTY_HTT_REPOSITION_POLICY = NOT_ESTABLISHED_IN_B5H_A
DETERMINISTIC_REPLAY = PASS
HTT_POLICY_NONDEGRADATION_CONCERN = NO
B3_REGRESSION = PASS
B4C_REGRESSION = PASS
B4D_REGRESSION = PASS
B5A_SNAPSHOT_REGRESSION = PASS
sources = {'B3': 'W_OOS/V1/results/b3-physics-smoke/run-005/physics_QA.json', 'B4C': 'W_OOS/V1/results/b4-event-driven-restoration/run-008-b4d-regression/QA_closeout.json', 'B4D': 'W_OOS/V1/results/b4d-htt-given-action/run-005/QA_closeout.json', 'B5A': 'W_OOS/V1/results/b5a-snapshot-interface/run-006/final_summary.json'}
FORMAL_W_OOS = NO
ALL_OOS = NO
MSP_OOS_INTEGRATION = NOT_RUN
SAA_DRO_W_COMPARISON = NOT_RUN
HTT_REFERENCE_POLICY_OPTIMALITY = NOT_ESTABLISHED
READY_FOR_B5H_B_REAL_PATH_PILOT = YES

没有运行正式 W_OOS、ALL_OOS、MSP_OOS、SAA/DRO 或 MFCV dispatcher；没有 commit/push。
