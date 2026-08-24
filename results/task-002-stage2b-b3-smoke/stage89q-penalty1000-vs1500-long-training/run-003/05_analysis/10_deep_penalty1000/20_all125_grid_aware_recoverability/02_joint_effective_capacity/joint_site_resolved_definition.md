# ALL_125 联合小时可行轨迹定义

Stage-89Q-G 已保存的 `all_125_joint_hosting.csv` 只保留联合最大总量，没有保存四站分配向量，不能单独满足 G3 的 site-resolved 要求。本轮仅对 99 条 ALL_125 氢侧 recovered paths 涉及的 125 个唯一电气 profile，使用相同 frozen Base background、相同 `HourlyGridLP` 和相同 IEEE33 约束重放独立小时 LP，并显式保存 `P_EL1..4` 联合可行见证。

每小时 LP 的目标仍是最大化四站总 P_EL；主判据把这一条实际 joint-feasible 的四站轨迹放回 Stage-89Q 原有 aggregate optimistic recoverability evaluator。该 evaluator 允许站间容量替代，不能严格识别唯一的 `required_extra_H2_by_site`，因此本轮按任务要求报告统一缩放 `alpha_required_uniform` 和逐站回退诊断，不把最终站点缺口冒充本站最小需求。

`THIS_IS_NOT_FA_MSP_REOPTIMIZATION`

`THIS_IS_PHYSICAL_FEASIBILITY_DIAGNOSTIC_ONLY`

没有将四站 independent headroom 相加，没有生成随机数，也没有补零小时。
