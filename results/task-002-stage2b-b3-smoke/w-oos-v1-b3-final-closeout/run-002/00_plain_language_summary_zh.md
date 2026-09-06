# W_OOS/V1-B3 Final Closeout

已有 B3 结果的详细核查通过。B3 PASS 仅证明保留案例中，给定动作序列下 physics engine 的状态推进、时间和氢质量守恒符合 B3 contract。本次限定范围交付不运行 B3、不实现优化器、不进入 B4。

## 1. Repo mechanical precheck

- Branch: `task/002-stage2b-b3-smoke`。
- HEAD: `ad6eddf873010096aebb29f34338ccbc0eadccb4`。
- Upstream: `origin/task/002-stage2b-b3-smoke`；ahead/behind `0/0`。`git ls-remote` 另行确认远端当前分支仍为此 SHA。
- 18 个 tracked 修改、13 个 tracked 删除、23014 个 untracked 文件；初始暂存区为空。逐路径 tracked 状态和哈希见 `repo_precheck.json`。
- MATLAB PID 9668 已存在，命令行不可读；未观察到独立 Gurobi 进程。不据此推断 MATLAB 内部是否正在求解；本次未启动或控制这两个软件。
- `codex_rule/log.md` 已 dirty。本次用户明确禁止修改既有 dirty 文件，故保留其全部字节，使用本目录 `execution_log.md` 记录任务。此显式用户约束优先于默认日志追加规则。

## 2. CASE-2: 12 min + 1 min

以下为原 `W_OOS/V1/results/b3-physics-smoke/run-001/event_ledger.csv` 实际行，时间单位 h，距离单位 km。

| CSV 行 | 车辆/状态 | time_start | time_end | progress_before | progress_after |
|---|---|---|---|---|---|
|20|1/MOVING|0.3|0.5|0|8.000000000000002|
|26|1/MOVING|0.5|0.5166666666666666|8.000000000000002|8.666666666666666|
|32|1/PARKED, ARRIVED|0.5166666666666666|0.6|0|0|

第18分钟出发，先行驶12分钟，accounting interval 从0变为1后保留8 km进度，再行驶1分钟。到达时间为30.999999999999996 min，即数值容差内第31分钟；总旅行时间13分钟，没有向上取整为30分钟。ARRIVED 行的局部 edge progress 为0，但累计 move progress仍为8.666666666666666 km。

## 3. CASE-4: current-edge closure

`case_inputs.json` 中 edge1 为24→1，W1时OPEN，M12及后续为CLOSED。车辆在1.4 h进入，1.5 h切换到M12，当前边进度4.000000000000005 km被保留；在1.6166666666666665 h完成8.666666666666666 km当前边。

原 `action_events.csv` 的实际记录：

| CSV 行 | time_h | event | road_state | edge/node/route |
|---|---|---|---|---|
|17|1.4|EDGE_ENTER|W1|edge1, 24→1, route=[1]|
|18|1.6166666666666665|EDGE_ARRIVAL|M12|edge1, node1|
|19|1.6166666666666665|MOVE_COMPLETE|M12|node1|
|21|1.6166666666666665|EDGE_ENTER|M12|edge2, 1→14, route=[2,3]|
|23|1.7666666666666664|EDGE_ENTER|M12|edge3, 14→24, route=[3]|
|25|1.9166666666666663|MOVE_COMPLETE|M12|node24|

到达node1后，顺序执行返程MOVE并按M12路网重规划；未在当前边中途改道，CLOSED edge1也未再次进入。源码 `_instant` 在到达后调用 `_enter`，`_enter` 使用当前 road state 并拒绝closed入边；此处只读核查源码和保存事件。

## 4. CASE-6: Option-A initial split

实际来源为 BASE2-DRO path2，字段 `inventory_site1..4`。逐值连接既有 recovered inventory CSV，并复核其SHA-256；此路径是机械选择的测试输入，不是新OOS样本。

| Site | original I_MSP (kg) | station_H2(0) (kg) | sum onboard (kg) | error (kg) |
|---|---|---|---|---|
|1|84.1553559615926|69.1553559615926|15|0|
|2|58.5009093832021|55.5009093832021|3|0|
|3|35.3376415005701|33.3376415005701|2|0|
|4|45.9373084666148|37.9373084666148|8|0|

六车 initial_sites=[1,1,2,3,4,4]，initial_onboard=[10,5,3,2,4,4] kg。逐站 station+onboard=original，max error=0 kg。事件账本逐站初值与分账表一致，没有额外赠送H2。

## 5. CASE-7: REFUEL_EVENT

车辆1真实到达node14，即site2后转移。time_start=time_end=0.21666666666666665 h，duration=0。site2库存55.5009093832021→45.5009093832021 kg，减少10 kg；车辆10→20 kg，增加10 kg。总H2转移前后均223.9312153119796 kg，20≤66.6 kg，无超罐，station非负。

## 6. CASE-9: SERVICE then MOVE

实际 SERVICE 行time_start=0，time_end=0.3 h，P_output=220 kW，energy_served=66.0 kWh，与220×18/60=66完全一致。onboard 10→6.3996399639964 kg，实测消耗3.6003600360036003 kg；公式66/(0.55×33.33)=3.6003600360036 kg，差4.440892098500626e-16 kg。

后续MOVING两行是0.3→0.5 h及0.5→0.5166666666666666 h，共13 min；每行P_output=0、energy_served=0，onboard保持6.3996399639964 kg。

## 7. CASE-10: shared station inventory

测试原始四站均20 kg。site1先从同一共享库存分配车辆1的10 kg和车辆2的5 kg，剩5 kg。t=0时车辆1申请4 kg，station1从5→1 kg，onboard1从10→14 kg；随后车辆2申请4 kg被REJECTED_STATION_INVENTORY，station1仍1 kg，onboard2仍5 kg。不存在重复占用；其他站库存为17/18/12 kg，最终station总量48 kg、onboard总量32 kg，总量始终80 kg。

## 8. QA与证据边界

原有17/17案例及3875/3875检查PASS。本次独立只读核查3469/3469检查PASS；全案例max mass error=2.842170943040401e-14 kg，B3保留的15个B2回归示例max C diff=0 km，unreachable mismatch=0。历史source/output/closeout manifest对应207个唯一文件当前身份核对通过，核查前后SHA保持一致。

原始 `physics_QA.json` 中表达和总体状态停留在报告前的PENDING；后置 `summary.json` 和 `final_closeout.json` 才是最终PASS/COMPLETE。历史final_closeout的log_append=PENDING之后，日志实际已追加；其旧SHA对应的原始前缀仍完全匹配。这是原有阶段记录的先后关系，不修改历史文件。

- VERIFIED_EXISTING：上述六案的实际时间、路段、分账、补氢、服务能量、共享库存；源码与原报告身份；17案例保存检查；本次独立数值复核。
- B2_VERIFIED：33×33 C_MFCV、anchors=[24,14,18,31]、正式OPEN equivalent-distance权重w=L×(1+cumulative_consequence)，tau=w/v0，没有第二套slowdown。B2全量历史最大差1.7053025658242404e-13 km，在既有1e-10 km容差内；B3仅复核保留回归示例为0，二者范围不可混淆。
- PROJECT_ASSUMPTION_FOR_B3：已入OPEN边按入边时长完成，封路后在下一节点重规划；Option-A拆分；NONBINDING_REFUELING_V1_ASSUMPTION为零时长、无速率/枪数/排队；HTT OFF、traction H2 OFF。验证了按假设执行，不等于验证假设的现实性。
- PROVISIONAL_PARAMETER：fleet=6、Pmax=220 kW、Hcap=66.6 kg、v0=40 km/h、eta_FC=0.55、LHV=33.33 kWh/kg。此次不升级为论文最终参数。
- NOT_ESTABLISHED：正式W_OOS完成、mobility optimizer、global optimum、六车最优、最终参数冻结、emergency rescue effectiveness、ALL_OOS performance、真实补氢时间及资源约束。B3不能证明这些结论。

ANALYSIS_QA=PASS，COMMUNICATION_QA=PASS，DATA_PRESERVATION_QA=PASS，OVERALL_DELIVERY=COMPLETE，限本次RESTRICTED_SCOPE。性能分析为PERFORMANCE_NOT_EVALUATED。

## 9. Engineering checkpoint scope

精确文件、added/modified、字节数、SHA及用途见 `checkpoint_files.csv`。当前B3的src/config/tests、报告生成源码和全部22个小型原始B3产物原位纳入；新增只读核查脚本及本次compact closeout纳入。没有B1/B2历史复制件、保护目录、缓存、无关results或既有dirty文件。

此checkpoint可回退B3源码和已保存证据；完整smoke runner仍依赖本地受保护历史数据，见 `REPRODUCIBILITY.md`。不宣称新克隆仓库可脱离这些输入重跑完整B3。成功commit/push后可以作为后续B4工作的工程起点；本任务不开始B4。
