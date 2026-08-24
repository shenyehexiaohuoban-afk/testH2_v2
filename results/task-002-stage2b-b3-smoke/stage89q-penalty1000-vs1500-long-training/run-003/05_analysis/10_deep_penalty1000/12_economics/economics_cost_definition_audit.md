# actual_operating_cost 定义审计

本轮机械核对 `oos_path_summary.csv` 与逐阶段 `stage_objective_yuan`。正式口径为：

`actual_operating_cost = holding_cost + production_cost + ordinary_shortage_cost + HTT_cost`

其中 `production_cost = electricity_cost + production_om_cost`。`terminal_penalty_cost = 1000 × terminal_site_gap` 单独列示，不属于 actual operating cost。`reported_objective = actual_operating_cost + terminal_penalty_cost`。

- actual cost 组成闭合最大绝对残差：9.02218744159e-10 元
- reported objective 闭合最大绝对残差：8.73114913702e-10 元
- 普通缺氢惩罚：`MODEL_PENALTY_COMPONENT = 200 × ordinary_shortage_total`
- 终端库存惩罚：`MODEL_PENALTY_COMPONENT = 1000 × terminal_site_gap`
- 以上惩罚是模型内部权重，不称为真实经济损失。
