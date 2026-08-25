# Stage-90B2 中文总结

本次仅读取 Stage90B run-004 的 checkpoint、forward/backward CSV，并对保存的最终策略状态做 35 个终端 LP 复核；没有 retrain、没有 10000-path OOS、没有修改 K=160、罚值、Pmax 或 checkpoint。

## 结论标签

- HOURLY_HTT_COST_SEMANTICS = VERIFIED
- TERMINAL_COST_SEMANTICS = VERIFIED
- REPORTED_SHIPPING_COST_EXPLAINED = YES
- C0_IDENTITY = CONSISTENT
- BACKWARD_TERMINAL_RECOURSE_COVERAGE = MODERATE
- TERMINAL_VALUE_GEOMETRY_CHANGED = YES
- K160_BINDING_SIGNAL = NONE（保存的 forward/backward 行合计 binding=0）
- COST_SEMANTICS_BUG = NO
- READY_FOR_STAGE90_LONG_TRAINING = YES（成本语义已解释；iteration-5 有向 OD 仍需未来运行时保存 x_ij 才能完全识别）

## 活跃 hourly HTT 成本

当前 Stage90B 使用 Stage88 candidate MAT 的 HTT base cost，恒等式为 baseCost=0.8*road_distance；beta 乘数为 2，active c0=0 yuan/kg。hourly 和 terminal recourse 都使用 c0 + baseCost*(1+lambda*beta)。历史 Stage85F/H02 文档中的 0.2*distance 不是本次运行的活跃输入。

## iteration-5 shipment

iteration=5、stage=4、state index=199、beta=0.424285714286：总运输 12.0568855824 kg，shipping cost 142.643290913 yuan，平均 11.8308571429 yuan/kg。该平均值精确等于 state-199 的最低 OD 单价，因此所有运输都能确定落在 Site2-Site3 无向 pair；但两个方向单价相同，run-004 没有保存 x_ij，所以有向拆分只能给出上下界 [0, 12.0568855824] kg，没有编造方向。

## backward coverage

35 个保存的 Stage-7 状态中，正 redistribution 比例为 0.314286，仍有 residual quantity gap 的比例为 0.514286；因此标签为 MODERATE。该标签只描述保存的 backward 状态覆盖，不是 OOS 性能结论。

详细数值见 active_htt_cost_source_audit.csv、iteration5_terminal_shipment_cost_breakdown.csv、backward_terminal_coverage.csv、direct_gap_vs_terminal_recourse.csv、terminal_dual_change_summary.csv 和 qa_summary.csv。
