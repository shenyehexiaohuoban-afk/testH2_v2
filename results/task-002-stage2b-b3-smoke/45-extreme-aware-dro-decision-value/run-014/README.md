# Step-04C-B extreme-aware DRO decision-value audit

本轮在新目录 `run-014` 中从头完成 30 个参数组合。每个组合使用一个或多个隔离 MATLAB 切面批次完成优化，并由另一个独立进程执行完整固定 T 复评；所有进程退出码、OPTIMAL 状态、LB/UB、gap、迭代次数和机械残差均通过。

- state19 极端集合：27 条物理路径、135 个冻结后果副本；其他初始状态为 0。
- 主体集合：R=15000，字节严格等价聚合为 7334 组。
- 最大绝对 gap：2.14564e-05；最大相对 gap：1.40207e-09。
- SAA TerminalLOH：[294.589913536808, 138.832065024684, 93.0093009300931, 150] kg。
- 纯 chi-square TerminalLOH：[300, 143.468740452331, 100, 150] kg。
- FULL_CAPACITY 极端平均缺氢：261.512060 kg。
- 最佳观测 ClosedRatio：undefined because FULL_CAPACITY provides zero recoverable-risk denominator。
- FULL_CAPACITY 后的极端风险保留比例范围：1.000000–1.000000。

模型凸性和认证分解已通过。2026-08-02，用户确认 `run-014` 作为 Step-04C-B 首个 accepted 正式运行进入 Git 留档；该接受只确认运行、证书和结果表有效，不自动冻结候选方法结论。求解运行阶段未 Commit、未 Push，Git 归档在全部 PASS 并完成用户复核授权后单独执行。
