# W_OOS/V1-B4C 电氢耦合取证与最小修正

## 一句话结论

原 B4 不是单纯序列化问题，而是缺少真实电源 dispatch、PF 和 H2 绑定的模型错误。本轮只修正 B4 本地 runner，保留 `run-001` 和此前的 superseded 初版，最终真实冻结库存证据写入指定的 `run-002-coupling-correction`。

## 四个疑点的证据结论

1. 原 `MFCV_H2_ledger.csv:P_MFCV_kW` 是活动车辆数乘 `220 kW` 的**可用容量**，不是 actual dispatch；原 `H2_use_kg=0` 是 MODEL_BUG，因为没有 dispatch-to-H2 变量绑定。
2. 原 fixed FC 没有 actual dispatch 变量，`FC_P` 常量没有进入 P/Q balance，station ledger 也恒为零；因此原 Pmax 并未约束实际出力。
3. CASE-3 的 `420 kW` 来自 bus24 的负荷复制：root 存在即把该岛全部负荷标成 served。修正后该岛只有 fixed FC，实际 `P_FC<=300 kW`，并受 `|Q|<=0.484322104837853*P` 约束。
4. root ledger 现在拆成 `eligible_real_roots`、`selected_topological_root`、`actual_injecting_sources`；一个 topological root 不再代表无限电源。

## 修正后的耦合

fixed FC 使用 `P*duration/(0.55*33.33)` 从同站 inventory 扣除；MFCV 只有在 SERVICE、在 bus、非 MOVING 且 onboard H2>0 时 dispatch，同样按区间扣减车载库存。每个 island 通过显式 LinDistFlow LP 约束 served P/Q、source P/Q、branch P/Q、平方电压、PF、Pmax、H2 和 branch octagon；root 本身不注入功率。CASE-4 在 `t=1.2166666666667 h` 前为零，到达后的区间出现实际 MFCV dispatch 与正 H2 消耗；ledger 同时记录 available 220 kW 和 actual P。

system H2 identity 最大误差为浮点舍入级残差；frozen realization 完整通过。B3、event-driven grid、LinDistFlow 接口回归在本地 QA 中保留，未运行 rolling mobility。

- `B4C_FORENSIC_AUDIT = PASS`
- `B4_COUPLING_CORRECTION = PASS`
- `H2_ELECTRICAL_COUPLING = VERIFIED`
- `FIXED_FC_CAPACITY_COUPLING = VERIFIED`
- `ROOT_SEMANTICS = VERIFIED`
- `B4_EVENT_DRIVEN_RESTORATION_SMOKE = PASS`
- `READY_FOR_ROLLING_MOBILITY_DISPATCH = NO`
