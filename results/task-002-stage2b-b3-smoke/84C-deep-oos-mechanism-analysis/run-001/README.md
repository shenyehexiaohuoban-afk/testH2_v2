# Stage-84C：正式共路径 OOS 深度机制分析

## 数据与边界

本分析只读取 Stage-84B `run-001` 已安全关闭的 10000×10000 共路径结果。没有重新训练、重新 OOS、重抽样、增加 cuts 或调用 Gurobi。SAA 与 Pearson chi-square DRO eta=0.03 使用同一 FA-MSP 结构，比较反映不同 TerminalLOH 风险输入进入同一实施层后的传播，不是 MSP/non-MSP 对照。

- Training commit：`cd7084300b0a50ade053e6b45ea7a1701d52c307`
- OOS schema fix：`4935f227c23010e2afd79475744da212ba4232a4`
- Stage-84B runner：`c63c3fcbfa9d19ecf726fc60b4406ddc6d2afbeb`
- Terminal gap 重构最大误差：SAA `1.293e-12` kg；DRO `1.208e-12` kg
- 本文 tail 均为主 FA-MSP OOS tail，不是 W1-W3 EENS tail。

## 统计分母与 HTT 口径

- `stage_dynamic_summary.csv` 和 `stage_site_dynamic_summary.csv` 的 Stage1-6 均值，以该 stage 实际仍进入 normal operating 状态的路径为条件样本；对应 path count 为 `10000, 8914, 7936, 5788, 2476, 427`，不是固定 10000-path cohort。stage-level conditional means 同时受到真实时间演化和 surviving-path composition 的影响；若后续论文需要严格固定 cohort 的纵向比较，应另做只读 cohort audit。
- `hour48_grid_summary.csv` 每个 global hour 的均值以该行 `path_hour_count` 个 observed operating-hour records 为分母。Site3 受限频率另严格区分固定 `10000×48=480000` slots、每方法 `284328` 个 observed operating hours，以及 `10000` paths 的 ever-limited 比例，三者不可混用。
- Stage-84B stage/site schema 没有 stage×source×destination arcs。本文的 stage-level switching 仅表示 HTT net-role / station import-export role switching；Site3→Site1 等方向只来自 path-level aggregate direction summary，不是完整 stage-by-stage arc trajectory。

## A. DRO 风险传播

在相同 10000 条路径上，DRO 相对 SAA 的平均变化为：生产 `+24.770` kg、终端实际库存 `+25.792` kg、HTT `+6.676` kg、普通缺氢 `+1.022` kg、运行成本 `+1220.123`、grid procurement `+1270.242` kWh。DRO 通过更多生产与空间调拨形成更多终端库存，同时付出更高运行成本和更高普通服务压力；不能把 total cost 全部解释成实际运行支出。

Terminal-hit 路径中，SAA target/actual/gap 均值为 `97.836` / `411.843` / `2.173` kg；DRO 为 `148.790` / `442.955` / `2.419` kg。必须结合 target 差异解释 raw gap。

## B. FA-MSP 多阶段行为

在仍处于 normal operating stage 的条件样本内，Stage1-6 paired 期末库存均值差依次为 `+0.00, +10.13, +25.36, +32.69, +30.74, +32.42` kg，最大单阶段差异扩张发生在 Stage `3`。这些跨 stage 数值不能解释为同一固定 cohort 的纯时间变化。Shared-prefix 表机械检查相同可见前缀下的前缀内决策数值范围，并在状态分叉后记录 production/inventory/HTT/P_EL 分化。相同 current Markov state 的分组同时显示进入库存存在显著跨度，说明当前动作与累积 inventory state 存在条件关联；这属于描述性动态适应证据，不是非-MSP 优越性证明。

Stage-84B 的 stage/site schema 只保存每站 HTT in/out/net，没有保存 stage×source×destination 的 12 条方向弧。因此 `htt_stage_direction_summary.csv` 与 `htt_state_direction_summary.csv` 只能核实站点净角色及其切换，不能伪造完整 arc-level 时空方向。Path-level 总方向仍支持 Site3→Site1、Site2→Site4、Site2→Site1 为主要平均流向。

## C. Grid-H2 coupling

Site3 的固定 48h slot 受限频率为 SAA `2.481%`、DRO `2.947%`；observed operating-hour 频率为 `4.189%` / `4.975%`；path-level ever-limited 为 `77.100%` / `79.240%`。2.x% 与 77–79% 可同时成立，因为分母分别是 480000 个固定时隙和 10000 条路径。

Branch 1→2 的 q99.5 利用率为 SAA `81.265%`、DRO `81.265%`，全局最大仍低于 6 MVA；正式样本更接近 bus18 电压约束而非 thermal limit。PV aggregate utilization 为 `100.000%`，零 PV 路径单独计数，未观察到弃光；这不等于已经证明 PV 提高灾害韧性。

## 可用于论文的结论

1. 不同 TerminalLOH 风险输入通过同一 FA-MSP 传播为可量化的生产、库存、HTT、服务、成本和电网响应差异。
2. Shared-prefix 与 same-state/different-inventory 结果可用于描述信息逐步揭示和库存状态依赖下的动态适应。
3. Grid-H2 正式 OOS 显示 bus18/Site3 是主要局部耦合边界，branch 1→2 负载最高但未接近 6 MVA 上限。

## 不能越界声称

不得声称 FA-MSP 已优于非-MSP、Site3 限制与 HTT 是严格因果关系、PV 已提高灾害韧性，或将本次 tail 称为 W1-W3 灾后 EENS tail。
