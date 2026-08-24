# Stage-89Q penalty=1000：Electrolyzer Pmax 后期追产灵活性审计

结论先说：当前 Pmax 明显压缩了总量不足路径在最后 8–16 小时的严格乐观追产窗口。Base 严格复现 `70/156/167`；`ALL_150` 将其降为 `7/66/122`。这只证明更大 Pmax 扩大事后乐观物理上界，不证明既有 policy 或重新训练后的 policy 已经改善。

## 1. 当前 Pmax 是否限制最后 8–16h 的追产能力？

是，物理上界信号为 `STRONG`。`ALL_150` 在 -16h 和 -8h 分别让 63 和 90 条 Base 已可证追不上的路径重新变为“未被乐观上界排除”。

## 2. Base 70/156/167 是否成功复现？

成功。-16/-8/-4h 的不可恢复路径数及路径集合都与 `15_mechanism_deep_dive` 逐条一致。

## 3. Pmax 增加后三个数字变成多少？

平衡推荐 targeted `S4_125` 为 `39/147/159`；`ALL_125` 为 `18/110/147`；`ALL_150` 为 `7/66/122`。

## 4. 哪个时点改善最大？

对 `ALL_150`，绝对改善最大的是 -8h，共救回 90 条；-16h 和 -4h 分别为 63 和 45 条。

## 5. 哪个站扩容最有效？

综合单位新增 kW 的三检查点恢复效率、当前缺口频率、near-max 证据和 grid 风险筛查，`BEST_TARGETED_CANDIDATE = S4_125`。这不是经济最优容量。

## 6. 为什么是这个站？

Site4 +25% 只增加 37.5 kW，却产生 48 个检查点恢复事件，效率为 1.280 事件/kW；且 Site4 当前终端缺口发生率和 near-max 比例都最高。

## 7. 它是否也是最常缺、最常顶满的站？

是。Site4 在 473 条不足路径中的缺口发生率为 67.23%，最后16小时 near-max 比例为 75.17%，均为四站最高。

## 8. +25% 和 +50% 哪个边际效果更高？

Site4 的 +25% 为 1.280 事件/kW，+50% 为 0.800 事件/kW；+25% 的边际诊断效率更高。

## 9. Uniform expansion 是否比 targeted expansion 更有效？

Uniform 在绝对恢复数上更强，但单位新增 kW 效率不一定更高。`BEST_UNIFORM_CANDIDATE = ALL_125`，选择依据是两档 uniform 中更高的单位 kW 恢复效率，而非自动采用。

## 10. Pure quantity 118 条改善多少？

`ALL_150` 在 -16/-8/-4h 分别恢复 32/25/11 条，效应标签为 `STRONG`。

## 11. Mixed 152 条改善多少？

`ALL_150` 在 -16/-8/-4h 分别恢复 31/65/34 条，效应标签为 `STRONG`。

## 12. Pure-location 203 条是否基本不受影响？

是。三个检查点的 Base 严格总量不可恢复数均为 0，所有 Pmax 候选新增恢复也均为 0；效应为 `NONE`。本审计不重复 HTT capacity 研究。

## 13. Difficult 5% 是否得到明显帮助？

有，但主要集中在 difficult4。`ALL_150` 在 -16/-8/-4h 对 difficult4 恢复 36/86/44 条；对 extreme1 为 27/3/0 条。最极端尾部仍有明显剩余压力。

## 14. 不可恢复临界点是否向 Stage7 推迟？

是。270 条具有总量不可恢复临界点的路径中，`ALL_150` 有 212 条后移，平均后移 4.80 小时，最大 19 小时。203 条 pure-location 只有“未被总量上界排除”，没有可识别的总量临界点。

## 15. 能否支持未来模型可能更敢等的物理机制？

可以作为物理依据：更大 Pmax 扩大 late-stage recovery capability，使晚确认后仍未被上界排除的路径增多。但等待价值是否真正进入 policy，必须由 fresh zero-cut retraining 验证。

## 16. 当前能否说 Stage1 production 会下降？

不能。只有 fresh retraining 才能知道。

## 17. 当前 grid 是否允许候选站真正使用新增 Pmax？

不能确认。`GRID_HOSTING_FOR_SELECTED_CANDIDATE = NOT_IDENTIFIABLE`；保存的固定-policy OOS 不能识别新增 Pmax 的增量 hosting headroom。

## 18. 哪些站存在 voltage hosting 风险？

Site3/bus18 为 `POTENTIALLY_VOLTAGE_LIMITED`：当前 OOS 中 bus18 已达到 0.90 pu 下限。Site1/2/4 为 `NOT_IDENTIFIABLE`，不能因当前没有同类触底就写成 CLEAR。线路热容量在当前 OOS 中未绑定，但也不构成增量 hosting 证明。

## 19. 推荐下一步测试哪个 targeted candidate？

诊断推荐 `S4_125`，但不得自动采用。它的氢侧物理增益存在，电气 hosting 尚未确认。

## 20. 是否值得进入 fresh zero-cut FA-MSP Pmax pilot？

`RECOMMEND_FRESH_PMAX_POLICY_PILOT = NEEDS_GRID_CHECK`。先完成候选站增量 grid hosting 检查，再决定是否启动 fresh zero-cut pilot；本任务没有训练、求解路径或运行 OOS。

本审计的严格语义为 `EX_POST_OPTIMISTIC_PHYSICAL_REACHABILITY`：检查点使用真实期末库存；剩余小时只使用真实存在的 hourly history；普通需求虽报告但因可软缺供而不从严格上界扣除；tank/HTT/grid 不用于收紧这一总量上界。`NOT_RULED_OUT_BY_OPTIMISTIC_BOUND` 不等于 policy 一定能完成，也不等于电气或逐站可行。
