# Stage-89Q-G4-Lite：16 种 Pmax 子集只读筛选

1. 四站如果只能扩一个，**Site4 / B0001** 最值：保留 39 个 events，效率 1.040 events/kW。
2. Site1/2/3/4 单独扩 25% 分别保留 **55/45/18/39** 个 recovery events。
3. 单站每增加 1 kW 最有效的是 **Site4**；四站完整 subset-pair 平均边际效率见 `04_site_value/site_expansion_signals.csv`。
4. Site3 的 +30 kW **有实际价值**：单独保留 18 个 events，在 8 个配对中有 8 个产生正增量，信号为 `MODERATE`；bus18 clipping 没有被当成“无价值”的先验。
5. ALL_125 去掉 Site3 得到 B1101，节省 30.0 kW，仅少保留 7 个 events。
6. ALL_125 去掉 Site4 得到 B1110，节省 37.5 kW，少保留 20 个 events。
7. 最好的两站组合是 **B1100**：新增 125.0 kW，保留 78 个 events。
8. 最好的三站组合是 **B1101**：新增 162.5 kW，保留 97 个 events。
9. ALL_125 是否被更小组合支配：**NO**。判定只使用 added kW 与 retained events 的严格 Pareto 定义。
10. ALL_125 的 80% gain 至少需要 **142.5 kW / B1011**；90% 至少需要 **162.5 kW / B1101**。相对 192.5 kW 是否显著更少由这两个机械阈值直接判断。
11. Site1/2/3/4 信号分别为 **STRONG / STRONG / MODERATE / STRONG**。
12. 是否支持非均匀扩容：**是**；最佳可进入工程比较的非均匀候选为 `B1011`，但没有自动采用。
13. 当前不能确定最终最优连续 Pmax。本轮只有 Base/1.25x 两档、冻结 Base 电气背景和 optimistic physical evaluator，不是 fresh-policy counterfactual。
14. 下一步建议：`RECOMMEND_NEXT=S4_AND_ASYMMETRIC_SMOKE`。若包含 asymmetric smoke，对应候选为 `B1011`；本轮没有启动 smoke、训练、OOS 或 penalty1500。
