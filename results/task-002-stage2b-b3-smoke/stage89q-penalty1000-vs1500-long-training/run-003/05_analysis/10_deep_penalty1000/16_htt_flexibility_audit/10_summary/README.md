# Stage-89Q penalty=1000：HTT空间灵活性与wait-and-see专项审计

## 先说结论

当前HTT有真实的系统总运力约束，但保存的10000路径小时证据并不支持把203条pure-location failure主要归因于160*(1-beta) kg/h。全部真实普通决策小时利用率均值/中位数/q99为 **0.21%/0.00%/6.15%**，精确绑定比例 **0.0000%**。无限aggregate cap在-16/-8/-4h相对当前cap新增的“上界未排除”路径数（pure-location+mixed合计）为 **0/0/0**。这只是固定已实现制氢和普通服务轨迹的乐观容量包络，不是新policy或反事实最优解。

## 1. 当前HTT到底受哪些正式约束？

每小时有连续4x4有向OD流，`f_ii=0`；系统总流量不超过`(1-beta)*160`；每站outflow不超过当小时生产和普通服务结算后的`I_pre`；`I_pre`和`I_end`均受罐容限制。beta同时降低容量并提高距离变量成本。详见`01_model_audit/htt_formal_constraint_audit.md`。

## 2. 160*(1-beta) kg/h总运力是否经常绑定？

不经常。>=80/90/95/99%利用率小时数为 **1/0/0/0**，相对于285888个真实小时。

## 3. 203条pure-location failure主要是不是总HTT运力不足？

不是主要证据。`HTT有总运力约束`不等于`总运力约束是当前pure-location failure的主要原因`。路径-时点级严格aggregate-capacity flag共 **0** 次。

## 4. 98条candidate under-dispatch重新分类后分别是什么？

NO_MOVABLE_SURPLUS=0；SURPLUS_APPEARED_TOO_LATE=0；AGGREGATE_HTT_CAPACITY_LIMITED=0；DESTINATION_TANK_HEADROOM_LIMITED=0；INFORMATION_NOT_YET_REVEALED=63；EX_POST_MISALIGNED_BUT_INFORMATION_CONSISTENT=11；CAPACITY_AVAILABLE_BUT_NOT_USED=22；MULTIPLE_LIMITS=0；NOT_IDENTIFIABLE=2。

## 5. 有多少路径根本没有可搬库存？

在98条严格重分类中为 **0**；完整pure-location三时点物理表另行保留origin inventory flag，不能把不同分母混报。

## 6. 有多少是库存出现得太晚？

98条中严格分类为 **0**。

## 7. 有多少是真正aggregate capacity limited？

98条中为 **0**；物理表的路径-时点flag总数为 **0**。

## 8. 有多少是destination tank headroom问题？

98条中为 **0**。最终缺口本身通常小于对应站最终headroom，因此不能把罐容存在误写成罐容正在阻断。

## 9. 有多少是当时信息尚未揭示？

98条中为 **63**。这里使用Markov转移与Stage89K 35x4表的无条件`E[T_i|当前state]`代理，不使用最终目标。

## 10. 29.50%为什么不能叫“HTT正确率”？

它按最终Stage7目标事后回看，而且只是逐OD流量截断口径；当时决策尚不知道最终目标，也不是二元对错分类。pure-location事后aligned比例复算为 **29.5032%**。

## 11. 有多少ex-post non-aligned HTT在当时信息代理下合理？

pure-location中严格“事后aligned=0但信息代理aligned>0”的路径数为 **43**，保守可确认流量为 **885.012 kg**。代理不是continuation value、DRO cut或正式最优target。

## 12. cap提高到200/240/320 kg/h物理上多救多少？

pure-location在-16/-8/-4h的上界可恢复数分别为：160=`203/203/203`，200=`203/203/203`，240=`203/203/203`，320=`203/203/203`。分母和边际增量见`04_cap_sensitivity`。

## 13. infinite aggregate capacity又能多救多少？

相对当前cap，pure-location+mixed在-16/-8/-4h分别新增 **0/0/0** 条上界可恢复路径。

## 14. 如果infinite cap改善很小，真正瓶颈是什么？

更可能是起点可搬库存、库存出现时点、最终位置尚未揭示，以及未能从保存数据严格恢复的continuation-value空间信号，而不是系统总运力一个参数。

## 15. HTT主要缺容量，还是缺时间/信息/空间价值信号？

当前证据更偏向时间、信息和空间价值信号的组合；aggregate容量不是主导信号。

## 16. Pmax与HTT分别限制哪种wait-and-see灵活性？

Pmax限制后期新增氢的时间生产灵活性；HTT限制已有氢的空间重配置灵活性。473条分类中production-dominated=80，redistribution-dominated=278，both=76，neither/not identifiable=39。

## 17. 当前有证据支持下一步正式扩大HTT capacity吗？

状态为 **NO**。只有当上界敏感性显示稳定且明显的新增路径，同时真实小时利用率也显示容量压力，才值得fresh retraining验证。

## 18. 如果有，建议测试什么candidate？

若后续证据转为YES，优先测试200 kg/h，再决定是否240 kg/h；不建议直接跳到320或无限容量。

## 19. 为什么不应为了结果漂亮直接扩大HTT？

因为扩大cap会改变正式策略、训练cuts和成本权衡；当前只读上界不能证明新参数会改善OOS，更不能排除库存、信息和价值近似才是主因。

## 20. 哪些结论需要fresh retraining验证？

容量变化后的真实非预见性policy、HTT时序、普通缺氢、TerminalLOH gap、成本、tail风险和wait-and-see行为都必须fresh training加同一路径OOS验证。本轮没有运行任何这些工作。

```text
HTT_AGGREGATE_CAPACITY_BOTTLENECK = NO
HTT_TIMING_BOTTLENECK = NO
HTT_INFORMATION_LIMIT_SIGNAL = YES
HTT_SPATIAL_VALUE_SIGNAL = WEAK
RECOMMEND_HTT_CAPACITY_SENSITIVITY = NO
FULLY_CONVERGED = NO
PENALTY1500_STARTED = NO
NO_REOPTIMIZATION = YES
NO_RANDOM_DRAW = YES
```
