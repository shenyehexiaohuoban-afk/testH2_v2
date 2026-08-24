# 当前正式FA-MSP的HTT约束审计

## 结论

当前Stage89Q使用 `hourly-h2-hourly-htt-v1` 连续LP。每个普通阶段有8个独立小时OD流量 `f(i,j,h)`。每小时先由期初库存、当小时制氢和普通供氢形成 `I_pre`，再结算HTT形成 `I_end`；仅第8小时 `I_end` 跨阶段。

`PRE_DISASTER_HTT_PAIRWISE_ROAD_HARD_CONSTRAINT = NO`

Stage89K灾后 `A_road` 不进入灾前hourly HTT OD可达性约束。当前site-to-site道路距离只进入每kg运输成本。

## 机械定位

| 项目 | 正式语义 | 源码/函数 | 变量或参数 |
|---|---|---|---|
| 变量 | 4x4x8非负连续OD流；`f(i,i,h)=0` | `hourly_grid_h2/build_integrated_hourly_stage_model_hourly_htt_v1_h2.m`, `build_integrated_hourly_stage_model_hourly_htt_v1_h2` | `idx.f_hourly`, `lb`, `ub` |
| 目标系数 | `c0 + c_d(i,j)*(1+2*beta)`，逐kg变量成本 | builder及`update_integrated_hourly_stage_model_hourly_htt_v1_h2.m` | `model.c`, `base_c`, `beta_transport_multiplier=2` |
| 当前c0 | `0.000000 yuan/kg` | Stage89Q `training_summary.csv` / launcher metadata | `htt_base_service_cost_yuan_per_kg` |
| 当前c_d | `0.2*distance_km yuan/kg` | `load_data_h2_near.m`与Stage89Q launcher identity | `cost_transport_base` |
| 库存先后 | `I_pre=I_begin+production-served`; `I_end=I_pre+in-out` | builder `preHttRows`, `endingRows` | `h2_inventory_pre_htt`, `h2_inventory_hourly` |
| 起点出流 | `sum_j f(i,j,h) <= I_pre(i,h)` | builder `httOutflowRows` | `htt_outflow_availability` |
| 系统总运力 | `sum_ij f(i,j,h) <= (1-beta)*160` kg/h | builder `httRows`; updater `hourlyCapacity` | `htt_capacity_base=160` |
| beta容量 | 启用时乘 `1-beta` | updater | `use_beta_capacity=true` |
| beta成本 | 启用时距离成本乘 `1+2*beta` | updater | `use_beta_cost=true` |
| 储罐 | `I_pre`和`I_end`逐小时均不超过 `[300,200,100,200]` kg | builder upper bounds | `x_cap` |
| 同小时普通需求 | incoming在需求结算之后到达，不能服务当小时已结算需求 | builder equality order | `preHttRows` before `endingRows` |
| 同小时再次转运 | 不允许；outflow只受本小时 `I_pre` 支撑，incoming只进入 `I_end` | builder origin row/end balance | `htt_outflow_availability` |
| 运输时延 | 语义为1小时末到达，无大于1小时路线时延 | builder model metadata | `htt_trip_time_assumption_h=1` |

## 真实存在

- 每小时系统aggregate capacity；
- 每站每小时origin inventory availability；
- 每小时起点/终点储罐上限；
- beta同时影响系统容量和距离变量成本；
- 完整有向OD连续流，禁止自运。

## 不存在

- pairwise OD hard capacity；
- pairwise road accessibility hard constraint；
- truck integer或dispatch binary；
- minimum shipment；
- fixed dispatch cost；
- site-specific fleet；
- route-specific travel time或大于1小时行程；
- 同小时incoming再转运或服务已结算普通需求。

输入物理来源仍记录为 `N_HTT=2`, `Q_HTT=80 kg`，但LP只使用乘积形成的aggregate `160 kg/h`，没有显式车辆变量。
