# Stage-89Q-G3：ALL_125 联合电网可恢复性闭环

## 先说结论

1. `ALL_125` 在纯氢侧救回 **118** 个 checkpoint events。
2. 涉及 **99** 条 unique paths。
3. 加入四站联合 IEEE33 hosting 后保留 **104** 个 events、89 条 paths。
4. Overall retention 为 **88.14%**。
5. `-16h` retention 为 **96.15%**（50/52）。
6. `-8h` retention 为 **91.30%**（42/46）。
7. `-4h` retention 为 **60.00%**（12/20）。
8. 虽有 full-candidate stress FAIL，仍保留 recovery 的是 **83 个 events**；这些支持窗口内共有 **230 个 event-hours** 被剪切但不致失效。
9. 真正被 grid clipping 消掉 **14** 个 recovery events。
10. Loss 构成为 pure quantity 2、mixed 12、pure location 0。
11. `difficult4` retention 为 **86.14%**。
12. `extreme1` retention 为 **100.00%**。
13. bus18 在 lost-event 剪切小时中为关键母线的频率是 **56/56**；它仍是主要电压瓶颈，但没有 branch/substation structural bottleneck。
14. Site3 `+30 kW` 对 lost recoveries 中 **5/14** 个是同一氢侧 evaluator 下的必要贡献；不能预设所有 loss 都由 Site3 导致。
15. 按逐站回退会使 recovery 消失的事件数，贡献最大的是 **Site1**（35 events）。
16. 按 `essential events / added kW`，单位新增 kW 最有效的是 **Site4**（0.587 events/kW）。
17. ALL_125 比 S4 多保留 **65** 个 grid-aware recovered events。
18. 单位 kW 效率：ALL_125 为 0.540，S4 为 1.040 events/kW；因此 **S4更高**。
19. S4 overall retention 是 81.25%，ALL_125 是 88.14%。
20. 当前 short smoke 工程优先级为 **S4_125**。
21. 是否两个都值得 smoke：**否**；这只是工程 gate。
22. 当前不能判断哪一个最终 policy 更好。
23. 当前不能判断 Stage1 production 会下降。
24. 当前不能判断 terminal shortfall 会下降。
25. 下一步应为 **S4_125** 对应的 fresh zero-cut short smoke；本轮不自动启动。

## 方法与边界

本轮是 `FROZEN-BASE-BACKGROUND JOINT GRID-AWARE PHYSICAL RECOVERABILITY DIAGNOSTIC`，不是 `FRESH ALL_125 POLICY COUNTERFACTUAL`。G 保存表没有四站联合分配，所以本轮只对相关唯一 profile 重放同一个独立小时 IEEE33 LP，并保留四站联合可行见证。这是 `THIS_IS_NOT_FA_MSP_REOPTIMIZATION`、`THIS_IS_PHYSICAL_FEASIBILITY_DIAGNOSTIC_ONLY`。

G 阶段机械复现为：全小时 joint mean hosting 96.3017%、full-candidate stress 85.3457%；ALL recovered final16 full stress 76.7677%、Site3 independent hostability 83.9015%，关键母线为 bus18，branch/substation limited ratio 均为 0。精确值及硬断言见 `01_baseline_reproduction/baseline_cross_audit.csv`。

Stage-89Q 的 physical evaluator 是 aggregate optimistic upper bound：`current inventory + k_H2 * remaining-hour electrolyzer nameplate - target_total`。它没有给出唯一的站点最小需求向量，因此按任务约定使用统一缩放 `alpha_required_uniform`，并用 B1-B4 逐站回退做 diagnostic necessity。`PARTIALLY_SUBSTITUTABLE` 表示回退该站后事件仍恢复、但 Base 本身不恢复；它不是唯一投资解。四站独立 headroom 从未相加。

`GRID_AWARE_SUPPORTED=YES` 只说明在当前 Base 电气背景下存在足够的 joint-feasible late-production upper-bound 轨迹；`NO` 只说明这条 frozen-background 上界不足，不能写成 fresh policy 严格不可能恢复。Fresh retraining 会改变 P_EL、inventory、ordinary service、HTT、voltage background 与站点结构。

## Gate 与文件

`RECOMMEND_FRESH_ALL_125_ZERO_CUT_SMOKE = NEEDS_MORE_GRID_DIAGNOSTIC`。唯一未通过项是严重 headroom 缺失 path-hour 占比 **23.23%**，超过同口径 **20%** 门槛；事件级 loss share 为 11.86%，其余七项 gate 均通过。门槛是工程 smoke gate，不是 adoption threshold。`GRID_AWARE_PILOT_PRIORITY = S4_125`。

- `01_baseline_reproduction/`：输入、分支和 recovered event identity；
- `02_joint_effective_capacity/`：site-resolved joint LP 见证；
- `03_grid_aware_recoverability/`：事件、检查点、failure type、消融；
- `04_bus18_site3/`：Site3/bus18 lost-event 明细；
- `05_candidate_comparison/`：机械读取的 S4 公平比较；
- `06_tail_analysis/`：normal95/difficult4/extreme1；
- `07_workflow_gate/`：固定门槛、评价和标签；
- `09_qa/`：主 QA、独立 QA、视觉 QA、manifest。
