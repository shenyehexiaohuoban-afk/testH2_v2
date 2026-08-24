# Stage-89Q-G2：S4_125 电压约束下的后期追产能力闭环

## 先说结论

1. 前一轮 S4_125 在氢侧救回 **48 个 path-checkpoint events**，涉及 44 条路径。
2. 冻结 Base 电气背景下，电压 hosting 后保留 **39/48**。
3. -16h 保留 **27/31**。
4. -8h 保留 **9/9**。
5. -4h 保留 **3/8**。
6. 总体/-16h/-8h/-4h retention 分别为 **81.250% / 87.097% / 100.000% / 37.500%**。
7. 18.608% full-increment 不可承载小时并不都导致 recovery loss；事件必须按完整剩余窗口重算。
8. 95/131 个 unique clipped path-hours 位于仍成功保留恢复支持的事件窗口内；对应 **26 个部分裁剪但仍受支持事件**。小时本身不能单独宣称“完成恢复”。
9. 真正被 voltage clipping 移除支持的事件为 **9**。
10. 这些 loss 的 checkpoint 分布为：4h:5; 16h:4。
11. 被移除事件的 failure type 为：mixed:7; pure_quantity:2。pure-location 氢侧恢复事件仍为 0。
12. normal95 没有 S4_125 氢侧 recovered event，retention 不定义；difficult4 retention 为 **80.488%**；extreme1 retention 为 **85.714%**。
13. bus18 是全部 131 个 full-increment 裁剪小时以及全部 9 个真正 recovery-loss events 的 critical bus；小时频次仍不能替代事件判据。
14. 电压受限小时缺失 headroom 平均 37.500 kW，中位数 37.500 kW，q95 37.500 kW，最大 37.500 kW。
15. >20 kW 的严重缺失小时为 131/131；所以不是“只差几 kW”，但整段剩余窗口仍可在多数事件中补足所需累计能力。
16. S4_125 氢侧 late-production physical flexibility gain 经电网后保留程度为 `STRONG`，数值为 39/48。
17. 当前 **不能**说 fresh S4_125 policy 一定能利用这些能力。
18. 当前 **不能**说 Stage1 production 会下降。
19. 当前 **不能**说 terminal shortfall 会改善；这仍需要 fresh training 和 fresh OOS。
20. workflow gate 给出的下一步是 `RECOMMEND_FRESH_S4_125_ZERO_CUT_SMOKE=YES`。这只决定是否值得做工程 smoke，不代表采用候选。

## 核心判据

Stage-89Q-G 的 hourly headroom 从 realized `P_EL4` 起算。本轮先重构 `P4_effective_max=min(187.5, realized_P_EL4+DeltaP_from_realized)`，再将每个真实剩余小时的 `P4_effective_max` 放回 Stage-89Q 原 evaluator：

`current_end_inventory + k_H2 * [remaining_hours*(300+200+120) + sum_h P4_effective_max(h)] - TerminalLOH_total`

结果不小于 `-1e-7 kg` 才记为 `GRID_AWARE_RECOVERY_SUPPORTED=YES`。`grid_hostable_extra_H2 >= required_extra_H2` 只作为交叉检查；两者必须一致。

`required_extra_H2` 不是 final gap。它由同一 evaluator 的 Base margin 解析得到；`required_alpha` 是使 `Pmax4=150+alpha*37.5` 刚好从 `PHYSICALLY_UNRECOVERABLE` 进入 `NOT_RULED_OUT_BY_OPTIMISTIC_BOUND` 的最小比例。

## 解释边界

本轮是 **FROZEN-BASE-BACKGROUND GRID-AWARE PHYSICAL RECOVERABILITY DIAGNOSTIC**，不是 **FRESH-POLICY COUNTERFACTUAL**。

fresh S4_125 policy 重新训练后，其他站 P_EL、inventory、HTT、ordinary service 以及各小时 grid state 都可能变化。因此本轮 YES 只表示存在充分物理依据值得进入训练；本轮 NO 也不等于 fresh policy 严格不可能成功。

本轮没有重跑 grid LP，没有训练 FA-MSP，没有 forward/backward/cut，没有重跑 OOS，没有修改 Pmax、TerminalLOH、HTT、电压/线路/变电站限制或任何 raw/MAT/checkpoint。

## 文件导航

- `01_baseline_reproduction/`：两轮 baseline 与路径身份闭合；
- `02_effective_pmax/`：704 个真实 path-hour 的 effective Pmax 定义与明细；
- `03_grid_aware_recoverability/`：48 个事件主表及 checkpoint/failure/path-window 汇总；
- `04_voltage_clipping_severity/`：18.608% 小时的缺失 kW 分布；
- `05_bus18_mechanism/`：bus18 与真正 event loss；
- `06_tail_analysis/`：normal95/difficult4/extreme1 retention；
- `07_workflow_gate/`：预冻结门槛、门禁评价和最终标签；
- `09_qa/`：主 QA、独立 QA、视觉 QA 与 manifest。
