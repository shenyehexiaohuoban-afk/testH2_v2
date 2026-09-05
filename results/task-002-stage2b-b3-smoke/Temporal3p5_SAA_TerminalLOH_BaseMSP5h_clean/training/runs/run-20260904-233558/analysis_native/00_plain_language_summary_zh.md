# Temporal3p5-SAA BaseMSP5h Mode C summary

候选与 accepted Stage89Q Formal Base 使用相同的 10,000 条有序等权 OOS 路径。本报告比较的是 temporal-refinement TerminalLOH 输入改变后形成的新策略，不把结果解释为系统物理可靠性自然提高或降低。

- Base 正目标路径为 1123/10000，候选为 1019/10000。
- 正目标路径中，至少一个站未完全达到目标的情景由 446/1123 (39.715049%) 变为 318/1019 (31.207066%)。
- 按目标氢质量逐站 capped 后计算的服务率由 92.777010% 变为 90.966282%，变化 -1.810728%。
- 同路径迁移中，新增未完全达标 33 条，恢复完全达标 161 条；两方向均已保留，不能只用净值解释。
- 平均总制氢由 166.925147 kg/path 变为 116.441951 kg/path，配对变化 -50.483196 kg/path。
- 平均逐站终端缺口由 1.528601 kg/path 变为 1.274284 kg/path，配对变化 -0.254317 kg/path。

完整的终止类型、PURE_QUANTITY/PURE_LOCATION/MIXED、逐站质量服务、逐小时制氢/库存/HTT、电网、运输 OD、成本与 ordinary shortage 结果见同目录 CSV。机制结果是同路径描述性证据；没有独立反事实放松时，不把 Pmax、HTT、电网或储罐相关性写成单一因果结论。

候选身份仍为 `TEMPORAL3P5_SAA_BASEMSP5H_CANDIDATE`，`NOT YET FORMALLY ADOPTED`。
