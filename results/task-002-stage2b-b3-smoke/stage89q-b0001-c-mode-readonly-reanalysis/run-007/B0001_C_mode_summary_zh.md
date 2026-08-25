# B0001 C 模式只读重新分析总结

## 身份与 QA

- `RUN_MODE=C`；`TRAINING_STATUS=UNSTABLE`；`EVIDENCE_GRADE=EXPLORATORY`；`ANALYSIS_NATURE=RETROSPECTIVE_DIAGNOSTIC`；`OOS_EXECUTION=READ_ONLY_REUSE`。
- Base 与 B0001 使用同一有序 10000-path bank；终止语义、状态历史、终端公式独立重算均通过，最大终端重算误差为 `1.73e-12` kg。
- 输入、bank 与两个 checkpoint 的 hash 在分析前后不变。没有启动 MATLAB/Gurobi，也没有修改输入、checkpoint 或既有 OOS。

## 事实结果

- B0001 平均总制氢 `197.0474` kg/path，Base 为 `195.4281`，增量 `1.6194` kg/path。站点和小时分解见 `site_time_mechanism_summary.csv`；S4 的新增制氢是主要新增能力信号，但它没有保证同一时段/同一站点可用。
- 平均 terminal site gap 从 `2.1588` 增至 `2.3406` kg/path；总量 shortfall 从 `1.6373` 变为 `1.5210`。这表示总量边际信号与逐站可靠性方向相反。
- positive-target 分母两组均为 `1123`；逐站失败率为 `42.1193%` -> `45.3250%`。新增失败 `82` 条，恢复 `46` 条，完整迁移表见 `terminal_type_transition.csv`。
- 失败类型计数由 Base `{'ADEQUATE': 9527, 'PURE_LOCATION': 203, 'MIXED': 152, 'PURE_QUANTITY': 118}` 变为 B0001 `{'ADEQUATE': 9491, 'PURE_LOCATION': 237, 'MIXED': 177, 'PURE_QUANTITY': 95}`；pure quantity 下降，但 pure location/mixed 上升。

## 机制解释边界

1. **容量空间配置：探索性信号较强。** S4 Pmax 从 150 增至 187.5 kW，新增产量集中在 S4；新增失败/持续失败中可见 S2/S3 终端库存或短缺不匹配。该结果支持“多生产但空间错配”的信号，不能证明放宽 S4 本身造成因果恶化。
2. **制氢时机与信息时机：混合且不可完全识别。** 小时序列显示新增产量的形成时间和终端前库存变化；终端 loc 在早期尚未揭示，事后方向不合适不能直接写成 policy 决策错误。B0001 未通过稳定训练验收，policy 异常本身仍是重要混杂因素。
3. **HTT：未证明为唯一主瓶颈。** 已报告 HTT 流量、方向、到达时机和 fleet 利用率，但没有反事实运输能力/方向放宽，因此 `HTT_DIRECTION_CAUSE=NOT_IDENTIFIABLE`。
4. **电网、储罐和设备：仅观察性证据。** Pmax/storage binding、voltage、line loading、fleet utilization 已保留在机制表；没有放松约束的反事实，不能把相关性升级为因果。

## 结论

已确认的是：B0001 在同一 common-path bank 上多生产，quantity-side 指标略有改善，但逐站 terminal gap、pure-location 和 mixed failure 恶化；新增产量没有稳定转化为目标站点在终端时点的可用库存。最接近的探索性机制是“容量空间配置 + 制氢/HTT 时机”的混合信号，并叠加 B0001 policy 未稳定。尚不可识别的是单独的 Pmax 因果效应、HTT 方向错误、电网/储罐约束的单独贡献，以及任何基于终端结果反推早期决策错误的结论。

下一步应先重新稳定训练 B0001，再在稳定 checkpoint 上测试非均匀功率候选；本 run 不宣布 B0001 优于、劣于 Base，也不淘汰候选。
