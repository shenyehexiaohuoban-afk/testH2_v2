# B0001 C 模式完整性审计与只读补充分析

## 四个独立结论

```text
ANALYSIS_QA = PASS
C_MODE_COVERAGE = COMPLETE
C_MODE_EVIDENCE = MIXED
B0001_CANDIDATE_JUDGMENT = EXPLORATORY_SIGNAL_ONLY
```

`ANALYSIS_QA=PASS` 只表示程序、输入身份、common-path、终端公式和输出 QA 通过，不表示 B0001 训练通过。

## 结果可信性

Base/B0001 使用相同有序 10000-path bank，`run-007` 结果引用正确且未被覆盖。终端公式 `sum_i max(T_i-I_i,0)` 独立重算通过。两臂均为 `DIRECT_GAP`，没有终端站间配送。

paired 95% CI（B0001 - Base，路径级正态近似 CI）：

- site gap：`0.181821`，95% CI `[0.091384..0.272258]` kg/path；
- quantity gap：`-0.116316`，95% CI `[-0.153557..-0.079076]` kg/path；
- location component：`0.298137`，95% CI `[0.209480..0.386794]` kg/path；
- ordinary shortage：`-0.166934`，95% CI `[-0.237563..-0.096305]` kg/path；
- actual operating cost：`-33.266181`，95% CI `[-48.888260..-17.644103]` yuan/path；terminal penalty：`181.820959`，95% CI `[91.384004..272.257914]` yuan/path。

positive-target 分母两臂均为 1123；site-wise failure rate 为 `42.1193% -> 45.3250%`（配对新增失败 82、恢复 46）。pure quantity 减少，但 pure location/mixed 增加。

## target、时间和尾部

- LOW target 的平均生产为 `327.923298 -> 332.267557`（差 `+4.344259`）kg/path，surplus 为 `208.872307 -> 212.825094`（差 `+3.952787`），site gap 为 `1.375176 -> 1.110272`。这显示相对准备增加，但没有理想策略反事实，不能等同于 policy 错误；四类终端类型见 `target_group_summary.csv`。
- HIGH target 的 observed site-gap 为 Base `50.793684`、B0001 `56.377179` kg/path，site-wise failure 为 `0.8398 -> 0.8694`，adequate count 为 `54` -> `44`。因此高目标保障没有显示改善，且观察上恶化。
- S4 的全路径新增生产为 `+5.462262` kg/path；按阶段为 `stage 1 +3.900238 kg/path; stage 2 -0.270270 kg/path; stage 3 +0.738623 kg/path; stage 4 +1.044448 kg/path; stage 5 +0.029944 kg/path; stage 6 +0.019279 kg/path`。全路径正增量小时为 `h1(stage 1) +0.731250; h2(stage 1) +0.731250; h3(stage 1) +0.731250; h4(stage 1) +0.731250; h5(stage 1) +0.731250; h6(stage 1) +0.731250; h7(stage 1) +0.731250; h10(stage 2) +0.048275; h11(stage 2) +0.048275; h12(stage 2) +0.048275; h13(stage 2) +0.048275; h14(stage 2) +0.048275; h15(stage 2) +0.048275; h16(stage 2) +0.048275; h17(stage 3) +0.086769; h18(stage 3) +0.067219; h19(stage 3) +0.045110; h20(stage 3) +0.041210; h21(stage 3) +0.049094; h22(stage 3) +0.052531; h24(stage 3) +0.618606; h25(stage 4) +0.429199; h26(stage 4) +0.412682; h27(stage 4) +0.558964; h28(stage 4) +0.507485; h29(stage 4) +0.071902; h30(stage 4) +0.336608; h34(stage 5) +0.036458; h35(stage 5) +0.098921; h36(stage 5) +0.111160; h37(stage 5) +0.098327; h38(stage 5) +0.091400; h39(stage 5) +0.099439; h43(stage 6) +0.060069; h44(stage 6) +0.045732; h45(stage 6) +0.075430; h47(stage 6) +0.164164; h48(stage 6) +0.406483`，负增量小时为 `h8(stage 1) -1.218512; h9(stage 2) -0.640848; h23(stage 3) -0.026165; h31(stage 4) -0.279145; h32(stage 4) -0.253533; h33(stage 5) -0.288177; h40(stage 5) -0.131509; h41(stage 6) -0.196768; h42(stage 6) -0.107721; h46(stage 6) -0.040669`；新增失败 cohort 的逐小时值和路径数见 `s4_production_delta.csv`，四站 P_EL、Pmax 利用率、库存、HTT、shortage 和 binding 仍见 `time_formation_summary.csv`。
- 新增失败 cohort 中，S2 的 B0001-Base ending-inventory 均值差首次在 global hour `7`（stage `1`）为 `-3.900000` kg，最低为 hour `23`（stage `3`）`-20.300206` kg；S3 首次在 hour `10`（stage `2`）为 `-0.502946` kg，最低为 hour `48`（stage `6`）`-13.223412` kg。完整轨迹见 `inventory_delta_formation.csv`。这些是 realized ending-inventory 差异，不是反事实缺口形成证明。
- `DIFFICULT4`、`EXTREME1`、`WORST_PATH` 使用同一 Base terminal-site-gap 的事后冻结路径；site-gap 的 B0001-Base 差分别为 `DIFFICULT4 +3.908951 kg/path; EXTREME1 -6.239354 kg/path; WORST_PATH +1.325825 kg/path`，并同时比较 production、inventory、quantity/location gap、ordinary shortage、actual cost、terminal penalty 和 HTT。它们不是 fresh holdout，完整结果见 `tail_and_cost_summary.csv`。

## 机制边界

可确认：S4 Pmax 扩大伴随更多生产，但新增氢未稳定转化为缺口站点的终端可用库存；quantity-side 平均指标略改善，而 site/location reliability 恶化。HTT 总量差为 `+1.609797` kg/path，95% CI `[1.331673..1.887921]`；保存字段支持 OD、方向、小时、源/目的库存和 shortage 的 realized 对齐，但没有 travel-time/direction relaxation 反事实，因此不能把相关性写成 HTT 因果。P_EL、Pmax 利用率、electrolyzer/storage binding 以及 `min_voltage_pu`/`max_line_loading_pct` 可作观测信号；缺少 substation capacity/loading/binding，不能识别变电站瓶颈；储罐有库存和 binding 但无显式 headroom，物理可恢复性也无 optimistic feasibility certificate。

逐项不可识别机制：physical_recoverability, substation_constraint。每项的所需字段、现有缺失字段、已排除内容、是否需要新 OOS 以及最小补充分析均列在 `mechanism_identifiability.csv`，不是统一的“数据不足”标签。

B0001 `UNSTABLE/FAIL` 是所有机制结论的共同折扣：观察到的模式可能来自 Pmax 空间配置、信息/HTT 时机和未稳定 policy 的混合，不能做候选采用、优劣排名或淘汰结论。

下一步建议：先重新稳定训练 B0001；稳定后再测试非均匀功率候选。此 closeout 未训练、未重跑 OOS、未修改模型/checkpoint，也未执行任何 Git 写操作。
