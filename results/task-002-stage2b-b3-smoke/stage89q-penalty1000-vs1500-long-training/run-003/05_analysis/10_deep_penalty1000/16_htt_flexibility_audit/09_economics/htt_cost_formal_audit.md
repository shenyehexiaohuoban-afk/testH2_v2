# HTT cost只读审计

- `c0 = 0.000000 yuan/kg`，来自Stage89Q训练摘要和正式launcher checkpoint metadata。
- `c_d = 0.800000 yuan/(kg km)`，由保存的OD距离、beta与逐kg成本机械反算；最大绝对偏差 `6.000e-01`。
- beta成本倍率为 `1 + 2*beta`；容量倍率为 `1-beta`。
- 成本是纯逐kg变量成本：`c0 + 0.2*distance*(1+2*beta)`；没有fixed dispatch fee。
- 保存结果没有逐小时cut边际值或完整决策KKT归因，因此 `HTT_MARGINAL_ECONOMIC_CAUSALITY_NOT_IDENTIFIABLE`。
- 不能仅因HTT有正成本就断言“成本太高导致未运输”。
