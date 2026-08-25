# Stage90B2 paired OOS 中文总结

本次 OOS 使用 run-004 保存的同一个策略和同一个 `data/OOS.csv` 前 10,000 条路径，分别调用 `TERMINAL_REDISTRIBUTION(K=160)` 与 `DIRECT_GAP(K=0)` evaluator。没有 retrain、没有重新抽样、没有修改 checkpoint。

## 数值结果

- `DIRECT_GAP` 平均路径成本：`59,623.5679412 yuan/path`
- `TERMINAL_REDISTRIBUTION` 平均路径成本：`58,253.5557392 yuan/path`
- paired 平均差：`1,370.0122020 yuan/path`，正值表示 recourse 降低成本
- recourse 更优：`530/10,000 = 5.3%`
- 两者相同：`9,470/10,000 = 94.7%`
- recourse 更差：`0/10,000`
- recourse 平均运输量：`1.4175689681 kg/path`
- recourse 平均物理运输成本：`47.5567661382 yuan/path`
- recourse 平均 residual terminal gap：`1.6554848329 kg/path`

成本差可以机械分解为：平均 terminal gap 减少约 `1.4175689681 kg/path * 1000 yuan/kg = 1417.5689680 yuan/path`，减去平均运输成本 `47.5567661 yuan/path`，净降低约 `1370.0122020 yuan/path`。

## 如何理解

这是一个有意义的机制信号：terminal recourse 没有让所有路径都改变，而是在少数出现 terminal shortage 的路径上用运输替代了一部分 1000 yuan/kg 的缺口罚值；使用 recourse 的路径没有出现成本变差。

但这不是“recourse policy 相对 DIRECT_GAP policy 的正式性能比较”，因为没有重新训练一个 DIRECT_GAP baseline。这里比较的是同一份 run-004 策略在两个 terminal evaluator 下的 paired cost。因此该结果可以支持进入下一步正式实验，但不能单独作为候选策略最终采用结论。

另外，recourse 的平均 terminal gap 仍为 `1.6555 kg/path`，说明它主要是部分修复，而不是普遍完全消除 terminal gap。
