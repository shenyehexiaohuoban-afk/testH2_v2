# W_OOS/V1-B4D given-action HTT physics smoke

## 一句话结论

B4D 的 2x80 kg HTT given-action movement、货载转移、精确到站事件和 B4C station-H2 接口均通过 14 个 hand cases；这是工程 smoke，不是救援优化或正式 W_OOS 性能结论。

## Precheck

branch=`task/002-stage2b-b3-smoke`；HEAD=`eeaeb65493bb844b86b4e3a1521eaf6ae6567069`；upstream=`origin/task/002-stage2b-b3-smoke`；ahead/behind=`0/0`；staged files=`0`；tracked dirty files=`31`；untracked status entries=`783`（untracked files=`23473`）。MATLAB/Gurobi 状态见 `precheck.json`；既有 dirty/untracked 内容均保留。

## 实现范围

- movement 直接调用未修改的 B3 `Simulator`；没有新的 road-physics 分支。
- transfer 使用同一时间戳原子批处理；不可行 given action 整批拒绝，不 clip。
- electrical/H2 consequence 直接调用 B4C `dispatch_interval`，HTT 仅通过 station H2 影响 fixed FC/既有 MFCV。
- HTT 始终 `P=Q=0`，traction energy 未建模，direct HTT->MFCV flag 严格为 false。

## CASE-1 至 CASE-14

- **CASE-1**: empty HTT load; system H2 unchanged；`{"station_delta_kg": -30.0, "cargo_delta_kg": 30.0, "duration_h": 0.0}`
- **CASE-2**: infeasible capacity request rejected without clipping；`{"cargo_before_kg": 70.0, "requested_kg": 20.0, "capacity_kg": 80.0}`
- **CASE-3**: infeasible station request rejected; no negative inventory；`{"station_before_kg": 15.0, "requested_kg": 30.0}`
- **CASE-4**: target inventory changes only at exact B3 arrival；`{"arrival_h": 0.325, "target_before_arrival_kg": 0.0, "target_after_unload_kg": 40.0}`
- **CASE-5**: partial unload retained cargo；`{"cargo_before_kg": 80.0, "unload_kg": 30.0, "cargo_after_kg": 50.0}`
- **CASE-6**: A->B->C multi-stop verified；`{"arrival_B_h": 0.325, "arrival_C_h": 0.55, "B_unload_kg": 30.0, "C_unload_kg": 20.0, "final_cargo_kg": 30.0}`
- **CASE-7**: two vehicle states/routes/cargo remain independent；`{"HTT1_arrival_h": 0.325, "HTT2_arrival_h": 0.25, "HTT1_final_cargo_kg": 0.0, "HTT2_final_cargo_kg": 0.0}`
- **CASE-8**: whole timestamp batch rejected atomically；`{"available_kg": 100.0, "total_requested_kg": 130.0, "final_station_kg": 100.0}`
- **CASE-9**: entered edge completed, then B3 rerouted without re-entering closed edge；`{"entered_edges": [1, 2, 3], "first_edge_closed_at_h": 1.5, "final_node": 24}`
- **CASE-10**: B4C recomputes at exact arrival; synthetic EENS decreases；`{"arrival_h": 1.2166666666667, "target_before_arrival_kg": 0.0, "unload_kg": 40.0, "event_EENS_kWh": 785.00000000001, "no_delivery_EENS_kWh": 1470.0, "EENS_reduction_kWh": 684.99999999999, "fixed_FC_H2_use_kg": 37.367373100945905}`
- **CASE-11**: HTT absent from roots, injectors, and P/Q dispatch；`{"P_HTT_kW": 0.0, "Q_HTT_kvar": 0.0, "electrical_source_rows": 0}`
- **CASE-12**: direct-refuel schema exercised with flag OFF；`{"colocation_bus": 1, "requested_direct_kg": 5.0, "actual_direct_kg": 0.0, "MFCV_final_kg": 0.0}`
- **CASE-13**: station-mediated refuel recorded as two transfers；`{"arrival_h": 0.325, "HTT_to_station_kg": 10.0, "station_to_MFCV_kg": 6.0, "direct_kg": 0.0}`
- **CASE-14**: no-op HTT framework equals B4C baseline；`{"max_interval_diff": 0.0, "max_station_diff": 0.0, "max_MFCV_diff": 0.0, "max_final_station_diff": 0.0}`

## Multi-stop 时间线

CASE-6 在 site24 装 80 kg，`t=0.325 h` 到 site14 卸 30 kg，`t=0.55 h` 到 site18 卸 20 kg，最终 cargo 30 kg；全程不返回固定 depot。

## Fixed-FC integration

CASE-10 arrival 为 `1.2166666666667 h`。到达前 target station H2 和 fixed-FC dispatch 均为 0；同一事件时刻卸 40 kg 后，下一事件区间 fixed FC 立即可用。EENS 从无送达的 `1470 kWh` 降至 `785 kWh`，减少 `685 kWh`。该数值仅证明接口 physics。

## System H2 identity

14 个 case 的 `station + MFCV onboard + HTT cargo` 总账最大绝对误差为 `2.1316282072803006e-14 kg`。load/unload/refuel 均只改变位置，系统消耗仅含 fixed FC 与 MFCV 实际使用。

## Direct-refuel OFF 与 no-op

CASE-12 普通 bus 共址直接请求 5 kg、实际转移 0 kg。CASE-13 允许 `HTT -> station` 10 kg 后再 `station -> MFCV` 6 kg，并保留两条独立记录。CASE-14 的 HTT no-op framework 与旧 B4C interval/topology/dispatch/H2/EENS 一致。

## Regression

- B3: `3883` checks PASS，最大质量误差 `2.8421709430404007e-14 kg`，road C diff `0 km`。
- B4C: `23` QA PASS，H2 identity 最大误差 `1.5987211554602254e-14 kg`；CASE-3 fixed FC cap 与 CASE-4 actual-dispatch/H2 coupling 均 PASS。

## 取证问题

1. HTT movement 是否真正复用了 B3 semantics？ 是；直接调用未修改的 B3 Simulator。
2. 是否出现新的独立 road-physics 分支？ 否；B4D 没有路径权重、闭路或重路由的第二套实现。
3. 两辆 HTT 是否具有独立 state / route / cargo？ 是；CASE-7 已验证。
4. 80 kg capacity 是否在所有 transfer 中机械生效？ 是；CASE-2 的 70+20 kg 请求被原子拒绝。
5. HTT 是否只能在 H2 station 装/卸？ 是；站点映射机械确认是 24/14/18/31。
6. partial unloading 是否 VERIFIED？ 是；CASE-5 从 80 kg 卸 30 kg 后保留 50 kg。
7. multi-stop 是否 VERIFIED？ 是；CASE-6 在 0.325 h 和 0.55 h 连续服务两站。
8. 共享 station inventory 是否会 double-spend？ 不会；CASE-8 的 130 kg 总请求对 100 kg 库存整批拒绝。
9. cargo 在 arrival 前是否不可被目标站使用？ 是；CASE-4/10 到达前目标站增量和相关 FC 使用均为 0。
10. arrival 是否在精确 continuous event time 生效？ 是；CASE-10 为 1.2166666666667 h。
11. arrival 后 station H2 是否立即进入下一 interval？ 是；卸载后从同一时间戳开始的新区间使用更新库存。
12. fixed FC 是否能使用已卸载 H2？ 是；CASE-10 到达后 fixed FC 正出力且产生正 H2 消耗。
13. HTT 是否始终 P=Q=0？ 是；全部状态和总账字段均为 0。
14. HTT 是否从未成为 electrical root/source？ 是；B4C root/source ledger 中不存在 HTT。
15. direct-refuel flag 是否严格 false？ 是。
16. 普通 bus 共址时是否仍为零直接转移？ 是；CASE-12 请求 5 kg、实际 0 kg。
17. 是否允许 HTT -> station -> MFCV？ 是；CASE-13 以两条独立 transfer 记录完成。
18. system H2 identity 最大误差是多少？ 2.1316282072803006e-14 kg。
19. B3/B4C regression 是否 PASS？ 是；两项均重新运行并通过。
20. no-op framework 是否保持 B4C consequence？ 是；CASE-14 最大差值为 0 或浮点容差内。

## Final status

`B4D_HTT_GIVEN_ACTION_PHYSICS_SMOKE = PASS`

`HTT_CONTINUOUS_TIME_MOBILITY = VERIFIED`

`HTT_STATION_H2_LOGISTICS = VERIFIED`

`HTT_PARTIAL_UNLOAD = VERIFIED`

`HTT_MULTISTOP = VERIFIED`

`HTT_EVENT_DRIVEN_INTERFACE = VERIFIED`

`HTT_SYSTEM_H2_IDENTITY = VERIFIED`

`HTT_TO_MFCV_DIRECT_REFUEL = OFF`

`HTT_TO_MFCV_INTERFACE_RESERVED = YES`

`B3_REGRESSION = PASS`

`B4C_REGRESSION = PASS`

`READY_FOR_REFERENCE_RESCUE_POLICY_DESIGN = YES`

该 READY 标签只表示 given-action physics 接口已可供后续单独设计任务使用；本轮未实现 optimizer、rolling dispatcher、formal W_OOS、fleet optimality 或 direct-refuel physics。
