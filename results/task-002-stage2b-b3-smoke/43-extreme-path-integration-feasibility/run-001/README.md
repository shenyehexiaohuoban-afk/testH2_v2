
# Step-04C-A support-out extreme-path feasibility audit

历史“858 条”经现场数据重算仍为 **858 条支持外唯一物理路径**。来源共 4005 条代理/分位标签记录，按完整 12 字段离散路径精确去重后为 1126 条，其中支持内 268 条、支持外 858 条；路径键重复为 0。

全部 1126 条路径都在正式状态空间内，三期所有强度、位置和 lfw 转移概率均为正。保存的 `path_probability` 与 Markov 矩阵重算一致，最大绝对误差为 `1.016e-20`。这些概率只能解释为各初始状态下“被定向选中的路径子集”的理论概率，不能称为完整极端事件概率，也不能代替主体样本的经验权重。

本轮无法确认“确实小概率且正式大危害”。原因不是路径非法，而是正式三期 D/A/C 还没有定义：冻结流程要求 `path_id + joint_stream_position + wind_seed + resistance_seed`。支持内 268 条已有对应主体记录；支持外 858 条均没有冻结随机流身份。历史 B3 使用固定代表风速，只保存汇总和 6 位小数签名，不能用于字节级正式 D/A/C 审计。

当前 chi-square DRO 只能在 15000 条主体记录的现有支持上重分配概率，所以不会自动覆盖这 858 条支持外路径。数学上推荐在正式输入冻结后使用“主体 chi-square 风险 + epsilon × 极端最大损失”；epsilon 只作保护强度，不解释为概率。等权追加和直接用 `path_probability` 追加均不推荐。

state19 小规模增强模型按门槛正确跳过：没有正式支持外 recourse 函数就无法生成可信 LB/UB 证书。

- extreme_set_status: `E-D. INPUT_OR_PROVENANCE_UNRESOLVED`
- integration_status: `I-B. FIXED_T_ONLY_FULL_INTEGRATION_UNRESOLVED`
- overall_conclusion: `C. RESOLVE_EXTREME_INPUT_OR_PROBABILITY_FIRST`
- 下一步唯一任务：冻结支持外路径的非随机、可审计正式 D/A/C 身份，再做固定 T 危害与增强原型。
