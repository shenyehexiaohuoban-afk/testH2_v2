# Stage-89Q-G IEEE33 小时级 Grid Hosting 模型机械审计

## 机械结论

- IEEE33：33 个 bus、32 条启用支路，固定径向拓扑；支路顺序为 `1:1->2, 2:2->3, 3:3->4, 4:4->5, 5:5->6, 6:6->7, 7:7->8, 8:8->9, 9:9->10, 10:10->11, 11:11->12, 12:12->13, 13:13->14, 14:14->15, 15:15->16, 16:16->17, 17:17->18, 18:2->19, 19:19->20, 20:20->21, 21:21->22, 22:3->23, 23:23->24, 24:24->25, 25:6->26, 26:26->27, 27:27->28, 28:28->29, 29:29->30, 30:30->31, 31:31->32, 32:32->33`。
- slack bus：bus 1，`V_1^2 = 1`；`P_grid` 在 `[0, 4883.53] kW`，`Q_grid` 无显式上下界。
- 基准量：`base_kV = 12.66 kV`，`baseMVA = 10 MVA`。当前方程直接使用 kW/kVAr、ohm 与 base kV；baseMVA 作为冻结元数据，不进入该 ohmic LinDistFlow 系数。
- 电压边界：`0.90 <= V <= 1.10 p.u.`，本轮未改动。
- 支路容量：每条支路 `Smax = 6 MVA`；LP 使用冻结 8 面体 `a=0.9238795325`、`b=1.3065629649`，并另外重算真实 `sqrt(P^2+Q^2)`。
- 普通负荷：33-bus 基础有功/无功合计 `3715 kW / 2300 kVAr`，逐小时乘冻结 48h（24h 重复）`lambda`；hosting 时保持同一真实 global hour。
- PV：Site1-4 各 200 kW，availability 为 `200*phi48(tau)`；`P_PV` 是 `[0, availability]` 内可削减的电网决策变量，没有 PV 无功变量。
- 电解槽接入：`Site1 -> bus24`，`Site2 -> bus14`，`Site3 -> bus18`，`Site4 -> bus31`。`P_EL` 以负号进入相应 bus 有功平衡，因此是 nodal active load。
- 网架处理：当前 OOS 所有小时使用同一 32 支路拓扑，没有路径依赖线路开断变量。
- losses：未考虑。节点平衡和电压降是 lossless LinDistFlow。
- reactive adjustment：普通无功负荷冻结；支路 `Q` 和 slack `Q_grid` 为连续电网变量，PV/电解槽没有无功调节。

## 正式方程

对支路 `i -> j`：

```text
sum(incoming P)_j - sum(outgoing P)_j + P_grid(j) + P_PV(j) - P_EL(j) = P_load(j)
sum(incoming Q)_j - sum(outgoing Q)_j + Q_grid(j) = Q_load(j)
V_j^2 - V_i^2 + 2*(r_ij*P_ij + x_ij*Q_ij)/(12.66^2*1000) = 0
```

每条支路使用 `+/-P <= a*Smax`、`+/-Q <= a*Smax`、`+/-(P+Q) <= b*Smax`、`+/-(P-Q) <= b*Smax`。

## Hosting 冻结与重求解边界

- 来自正式 OOS policy、并冻结为 hosting 下界：该 path-hour 已实现 `P_EL_i`。
- 冻结：普通负荷、PV availability、global hour、拓扑、线路参数、电压边界、支路上限、candidate Pmax 上界。
- 重新求解：`Delta P_EL >= 0`、slack 有功/无功、支路 P/Q、bus 电压平方、PV 实际出力/削减。
- 不进入 LP：H2 inventory、ordinary H2 demand/service、HTT、TerminalLOH、cuts、未来价值和任何 policy 决策。
- `GRID_VARIABLES_REOPTIMIZED_FOR_HOSTING = YES`。
- 这是独立 grid-hosting LP，不是 H2 operational reoptimization。
