# S4_125 小时级有效 Pmax 定义

Stage-89Q-G 的 `max_additional_site4_hosting_kw` 是从冻结的 Base realized `P_EL4` 起算的最大附加负荷，不是从 Base 铭牌 150 kW 起算。

因此本轮先机械重构：

`P4_effective_max(h) = min(187.5, P_EL4_realized(h) + max_additional_site4_hosting_kw(h))`

相对 Base 物理上界的有效扩容能力为：

`DeltaP4_effective_above_Base(h) = P4_effective_max(h) - 150`

累计氢侧扩容收益使用 `sum_h DeltaP4_effective_above_Base(h) * 1h * k_H2`，其中 `k_H2=0.0195 kg/kWh`，由正式 `near_stage_msp_input.mat` 机械读取。主判据仍是将 `P4_effective_max(h)` 逐小时放回 Stage-89Q 的同一乐观 aggregate recoverability evaluator；累计 kg 只做交叉检查。

这一换算避免把 realized `P_EL4` 低于 150 kW 时尚未使用的 Base 铭牌余量重复计为 S4_125 扩容收益。只保留 44 条 S4 recovered union paths 的最后16个真实小时，共 704 行；没有补零小时，也没有重跑 grid LP。
