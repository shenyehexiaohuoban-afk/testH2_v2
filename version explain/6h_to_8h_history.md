# 6h 到 8h 的演化

## 1. 6h 最早从哪里来

legacy near-stage FA-MSP 将 24h normal-demand profile 整理为四个 6h block，并把 `NormalDemand.stage_dt_h=6` 写进 MAT。旧 `h2_default_options -> run_h2_with_options -> load_data_h2_near` 调用链默认关闭 hourly grid，因此 `params.dt_h` 也落在 6h，运行阶段采用 aggregate stage model。

这个 `6` 最初同时扮演“来源数据块宽度”和“运行阶段持续时间”并不矛盾；问题出现在 hourly 模型已经发展到 8h，而旧 MAT 元数据与旧 loader 仍可被新 launcher 继承时。

证据：`fa_h2/h2_default_options.m`、`fa_h2/fuzhu/load_data_h2_near.m`、Stage85A/85J/89E README、Stage89F current input README、`codex_rule/log.md`。

## 2. 90.09 kg 为什么出现

四站电解槽 Pmax 为 `[300,200,120,150] kW`，合计 770 kW；电解转换系数 `k_H2=0.0195 kg/kWh`。当 active duration 为 6h 时：

```text
0.0195 × 6 × 770 = 90.09 kg
```

所以 90.09 不是人为写死的 cap，也不是 Stage88 TerminalLOH 造成的；它是“6h aggregate runtime × 全站 Pmax”的物理上限。Stage89E 通过 MAT metadata、runtime params、aggregate builder 和这一等式把来源闭环。

## 3. 8h 何时出现、何时真正实现

- **Stage71** 首次系统比较 6h/8h effective capacity，但只是 sensitivity，未替换 legacy main。
- **Stage79/80** 引入每 stage 8 个 hourly IEEE33 slots；Stage79 的 0.95–1.05 pu 不可行，Stage80 放宽到 0.90–1.10 后接受 hourly grid 结构。
- **Stage82** 修复终端语义：Stage1–6 才是 operating stages，Stage7 解析 TerminalLOH，Stage8 零吸收边界。
- **Stage84** 建立 formal hourly-grid training/OOS，但 H2 demand/inventory/HTT 仍未完全 hourly 化。
- **Stage85A** 明确发现“电力 hourly、H2 与 HTT 仍 stage-level”的混合尺度。
- **Stage85B** 将 H2 balance/inventory/service 改为 hourly；最初使用 stage total/8 的映射。
- **Stage85G** 将 HTT 改为 hourly end-of-hour arrival。
- **Stage85I** 做过 block-uniform demand remap，只是中间版本。
- **Stage85J** 追溯发现原始 `hourly_kg` 被汇总成 6h `stage_template`，且生成脚本不可恢复。
- **Stage85K** 直接使用原始 24h `hourly_kg` 并重复到 48h。至此“6×8h、内部 1h IEEE33 + H2 + HTT + original hourly demand”的模型结构真正闭合。
- **Stage85R** 已在这一结构上完成 fresh P150/P200 fixed-5h training、clean reload 与 10k common-bank OOS，因此它是首个成熟的 8h training/OOS 工程母版。

这里“首次真正实现”需要分两层理解：Stage80 首次实现 6×8h hourly **电网**；Stage85K 首次实现当前意义上的完整 6×8h hourly **电网+H2需求+HTT+原始小时数据**。

## 4. 为什么 Stage89C/89D 又回到 6h

Stage89B 只构造 Stage88 CAP200 candidate MAT 与 TerminalLOH bridge，没有把 old default launcher 的 active time-grid 全部切换到 hourly 8h。Stage89C/89D runner 继承旧 defaults：

- `enable_hourly_grid=false`
- runtime `params.dt_h=6`
- MAT `NormalDemand.stage_dt_h=6`
- aggregate stage builder

因此 Stage89C 的 10-iteration / loc1,4,7 OOS，以及 Stage89D 的 penalty 2000/1500/1000 比较，虽然流程运行了，却属于 legacy-6h model lineage。它们的 checkpoint 和数值不能作为当前 8h policy 来源。

## 5. Stage89E 发现了什么

Stage89E 是 read-only source/parameter diagnostic。它排除了“代码里有 90.09 scalar cap”这一猜测，并确认四个相互一致的证据：旧 launcher/default、`enable_hourly_grid=false`、runtime `params.dt_h=6`、aggregate builder。`90.09=0.0195×6×770` 是结果，不是根因。

Stage89E 的价值是把问题从“生产量看起来异常”提升为“模型入口混线”：Stage88 TerminalLOH 输入是新的，但 FA-MSP 运行时仍是旧 6h。

## 6. Stage89F 如何恢复 8h

Stage89F 没有训练，而是建立 isolated current candidate bundle：

- `opts.dt_h=8`
- `enable_hourly_grid=true`
- `n_operating_stages=6`、`hours_per_stage=8`
- `hourly_h2_balance_v1=true`
- `hourly_htt_v1=true`
- `demand_schema=original-hourly-24h-repeat-v1`
- Stage88 DRO eta=0.03 CAP200 table
- Site4 tank=200，Pmax 仍为 150 kW

它把 MAT 中 `NormalDemand.stage_dt_h=6` 明确降级为 provenance-only metadata，并通过 loader/preflight 证明 active runtime 使用 8h。capacity smoke 的理论上限恢复为：

```text
0.0195 × 8 × 770 = 120.12 kg
```

证据：`fa_msp/current_hourly_stage88_candidate/config/current_hourly_stage88_candidate_options_h2.m`、`input/load_current_hourly_stage88_candidate_h2.m`、`input/README.md`、Stage89F README。

## 7. 当前 active runtime

当前模型入口的 active runtime 是：

```text
6 operating stages × 8 h/stage = 48 h
inner resolution = 1 h
hourly IEEE33 = ON
hourly H2 = ON
hourly HTT = ON
original hourly demand = 24 h source repeated to 48 h
Stage7 = analytic TerminalLOH
Stage8 = zero absorbing boundary
```

必须始终保留下面这条区分：

```text
NormalDemand.stage_dt_h = 6  -> source data metadata / provenance
params.dt_h = 8              -> active runtime stage duration
```

任何新 launcher 若再次让 `params.dt_h` 从 MAT 或 legacy defaults 隐式获得，都应直接视为 6h 回归风险。Stage89G 的 preflight 已对 `p.dt_h==8`、6×8h、hourly flags、1129 variables 和 120.12 kg 上限逐项断言。

## 8. 版本使用边界

- **可作为当前模型入口**：Stage89F bundle。
- **可作为历史 8h runner 母版**：Stage85R，并继承 Stage85H-A clean reload。
- **当前 formal candidate**：Stage89G run-002；完成 final QA 前不提升为 accepted。
- **不可作为 8h checkpoint 来源**：Stage89C、Stage89D、Stage89G run-001 旧 monolithic reload path。
- **不可把 6h metadata 删除或伪改成 8h**：它仍是原始 demand block 的真实来源信息；应由 runtime options 显式覆盖并审计。

Stage89N run-003 是当前 adopted Stage89K 在正确 8h runtime 上的受控训练证据：六个 operating stage 均为 8 个 hourly blocks，Stage1 theoretical cap 120.12 kg 且实际 policy 为 109.98 kg；`NormalDemand.stage_dt_h=6` 仍只作 source metadata。该结果不改变 Stage89F 模型入口，也不构成 fully converged policy。
