# Stage-89Q-G：Pmax 候选增量 Grid Hosting 专项审计

本轮只做独立 IEEE33 小时级 grid-hosting LP。没有训练、没有 forward/backward/cut、没有重跑 OOS、没有重优化 H2 policy，也没有写回 Pmax 或任何正式参数。285,888 个真实小时被精确归并为 1,244 个 `(global_hour,P_EL1..4)` 唯一电气 profile；hourly 输出保留 `occurrence_count`，权重和严格等于 285,888，关键窗口表仍保留逐 path-hour 身份。

## 1. S4_125 新增 37.5 kW 在当前电网中能不能实际用？

全体真实小时中，把 Site4 从已实现功率提高到 187.5 kW 的可承载率为 `98.585%`；最小可增加 headroom 为 `0.000 kW`。标签为 `MIXED`。

## 2. 它在真正需要 late production 的关键小时能不能用？

在 `S4_125` 被上一轮物理上界救回路径的最后 16 个真实小时中，完整提升到 187.5 kW 的小时比例为 `81.392%`，平均 grid-hosting ratio 为 `81.392%`。

## 3. S4_125 最常受什么限制？

关键 late-recovery 小时的 voltage/branch limited 比例分别为 `18.608%/0.000%`。分类严格使用运行前冻结在脚本和 `hosting_label_thresholds.csv` 中的阈值。

## 4. 是 voltage 还是 branch？

`VOLTAGE_INCREMENTAL_HOSTING = POTENTIALLY_LIMITED`，`BRANCH_INCREMENTAL_HOSTING = CLEAR`。全体 `ALL_125` joint 小时的两者 limited ratio 为 `14.654%/0.000%`。

## 5. ALL_125 的新增容量整体能不能使用？

相对已实现功率，joint LP 的全小时平均 hosting ratio 为 `96.302%`，所有站同时达到 candidate Pmax 的小时比例为 `85.346%`；标签为 `MIXED`。

## 6. 哪个站是 ALL_125 最主要的 hosting bottleneck？

按更重要的 `ALL_125` 物理救回路径最后16小时口径，最低的是 Site3；Site1-4 分别为 `84.091%/83.965%/83.902%/84.091%`。全小时单站比例最低的是 Site2，但四站全小时比例非常接近；系统 joint 解的临界低电压 bus 始终集中在 bus18。

## 7. Site3 / bus18 的历史 voltage 风险是否在当前数据中重现？

Site3 +30 kW 的全小时 voltage-limited ratio 为 `1.468%`，严格标签为 `POTENTIALLY_LIMITED`。该结论只来自当前 penalty=1000 OOS 和当前正式 grid 模型，不使用旧实验替代。

## 8. Site1/Site2/Site4 是否存在明显 hosting 风险？

关键窗口 Site1/Site2/Site4 的完整提升率为 `84.091%/83.965%/84.091%`，都存在与低电压小时重合的部分受限信号，但 Site3 最低。是否“明显”按同一预冻结阈值判断，不因历史经验预判；全小时逐站 voltage/branch 比例和最小 headroom 保存在 `04_all_125/all_125_summary.csv`。

## 9. 是否存在“铭牌扩容很多，但真正可用 headroom 很少”的情况？

`ALL_125` 名牌新增 192.5 kW；全小时从已实现功率到 candidate 的平均 requested/feasible 分别为 `611.945/591.580 kW`。因此必须同时看名牌、joint hosting ratio 和 stress，而不能把名牌值当成可用值。

## 10. candidate 全站同时满功率 stress 是否可行？

`ALL_125` full-candidate-stress 可行率为 `85.346%`，失败率为 `14.654%`。`S4_125` 的“全同时”只涉及唯一扩容站 Site4，其对应比例为 `98.585%`。

## 11. stress FAIL 是否意味着 candidate policy 一定不可行？

不一定。FAIL 只表示该小时不能保证所有扩容站同时满功率运行；真实重新训练后的 policy 未必要求这种同时满功率状态。

## 12. difficult-tail / late-recovery hours 中 hosting 情况如何？

`ALL_125` 在 difficult4/extreme1 最后16小时的完整 stress 可行率为 `78.464%/77.016%`，平均 hosting ratio 为 `87.405%/88.058%`。只计真实存在小时，没有补零。

## 13. branch thermal limit 是否成为新的瓶颈？

全体 `ALL_125` joint 小时 branch-limited ratio 为 `0.000%`，最大 octagon utilization 为 `0.867143`；最终标签为 `CLEAR`。

## 14. voltage 是否是主要限制？

全体 `ALL_125` joint 小时 voltage-limited ratio 为 `14.654%`，最终标签为 `POTENTIALLY_LIMITED`。该比率只在 candidate headroom 未完全承载且电压边界实际绑定时计数。

## 15. S4_125_GRID_HOSTING 最终是什么？

`S4_125_GRID_HOSTING = MIXED`。

## 16. ALL_125_GRID_HOSTING 最终是什么？

`ALL_125_GRID_HOSTING = MIXED`。

## 17. 哪个 candidate 更适合进入 fresh zero-cut policy pilot？

本轮按氢侧物理增益与当前电网 hosting 两道门联合判断：S4_125 建议为 `NEEDS_MORE_GRID_DIAGNOSTIC`，ALL_125 为 `NEEDS_MORE_GRID_DIAGNOSTIC`。这不是自动采用或训练指令。

## 18. 当前能否说扩 Pmax 后 Stage1 会下降？

不能，必须 fresh retraining。

## 19. 当前能否说 terminal shortfall 会下降？

不能，必须 fresh retraining + OOS。

## 20. 是否建议进入 S4_125 fresh-policy pilot？

`RECOMMEND_FRESH_S4_125_POLICY_PILOT = NEEDS_MORE_GRID_DIAGNOSTIC`。本轮在 push 后停止，不自动训练。

## 判级与解释边界

- `CLEAR`：candidate-specific late-recovery 小时 full-hostable ratio 与全小时 ratio 都至少 `95%`，且 voltage/branch/substation systematic-limited ratio 都不高于 `5%`。
- `LIMITED`：关键窗口 full-hostable ratio 或 mean hosting ratio 低于 `50%`，或任一系统性瓶颈比例至少 `50%`。
- 其余为 `MIXED`；数据/语义不足才为 `NOT_IDENTIFIABLE`。
- `NAMEPLATE_EXPANSION`、`GRID_HOSTABLE_INCREMENT`、`FULL_SIMULTANEOUS_STRESS` 与 `POLICY_ACTUAL_USE` 是四个不同概念。
- `POLICY_ACTUAL_USE = NOT_AVAILABLE_BEFORE_FRESH_RETRAINING`。
- `effective_grid_supported_gain_signal` 只是诊断标签；没有把 physical recovery gain 乘 hosting ratio 伪造新的正式路径数。

## 最终标签

```text
S4_125_GRID_HOSTING = MIXED
ALL_125_GRID_HOSTING = MIXED
SITE3_INCREMENTAL_HOSTING = POTENTIALLY_LIMITED
BRANCH_INCREMENTAL_HOSTING = CLEAR
VOLTAGE_INCREMENTAL_HOSTING = POTENTIALLY_LIMITED
RECOMMEND_FRESH_S4_125_POLICY_PILOT = NEEDS_MORE_GRID_DIAGNOSTIC
RECOMMEND_FRESH_ALL_125_POLICY_PILOT = NEEDS_MORE_GRID_DIAGNOSTIC
GRID_VARIABLES_REOPTIMIZED_FOR_HOSTING = YES
POLICY_ACTUAL_USE = NOT_AVAILABLE_BEFORE_FRESH_RETRAINING
FULLY_CONVERGED = NO
PENALTY1500_STARTED = NO
NO_FA_MSP_TRAINING = YES
NO_OOS_RERUN = YES
NO_PARAMETER_WRITEBACK = YES
GRID_HOSTING_LP_ONLY = YES
```
