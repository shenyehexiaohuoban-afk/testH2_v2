# 全项目版本谱系审计

当前登记截至：2026-08-23（Asia/Shanghai）。Stage89M 仅运行 loader / model construction / Stage7 / cut / forward minimal integration regression；未运行 FA-MSP training、OOS、W bank 或 TerminalLOH 优化，也未生成 checkpoint。

## 一页结论

当前识别并登记 **91 个重要版本节点**。节点按“实际改变模型、数据、参数、接口、runner/checkpoint/OOS 流程，或形成重要诊断结论”筛选；纯图片重排和无独立语义的临时 run 没有强行拆成版本。完整字段见 `version_registry.csv`，多父继承见 `version_lineage.csv`。

1. **当前 W / TerminalLOH 主线**已由 Stage89M 正式提升为 Stage89J accepted W + Stage89K accepted TerminalLOH，Stage89L 是 adoption evidence；唯一入口是 `terminalLoh_wdro/current_w_mainline_stage89/`。Stage88 仍原位保留为 superseded historical reproducible predecessor。
2. **当前 FA-MSP 模型入口**是 Stage89F 建立的 `fa_msp/current_hourly_stage88_candidate/`：6 个运行阶段 × 8h，每阶段内部 8×1h；hourly IEEE33、original hourly H2 demand、hourly HTT；Stage7 为解析 TerminalLOH，Stage8 为零吸收边界；容量 `[300,200,100,200] kg`，Pmax `[300,200,120,150] kW`。
3. **训练/OOS runner 的主要历史母版**应以 Stage85R 为主：它已具备 8h、hourly IEEE33、original hourly demand、hourly HTT、fresh fixed-budget training、checkpoint、clean reload、common-bank 10k OOS。Stage89G 是针对 Stage89F/Stage88 输入和 loc1/4/7 三地 OOS 新写的适配 runner，不是 Stage85R checkpoint 的续跑。
4. **checkpoint clean-process 机制来源**是 Stage85H-A：训练进程 save-and-exit，随后新 MATLAB 进程只加载一次 modelLib，并在 reload PASS 后才进入诊断/OOS。Stage89G run-002 明确复用了这个机制。
5. **最容易误调用的淘汰入口**是 Stage89C/89D（实际 6h、90.09 kg 上限）、Stage85I（block-uniform demand remap）、Stage57 名为 `converged` 但并无收敛证明、legacy aggregate `main_msp_h2_near.m` 默认入口，以及 Stage89G run-001 的同进程 reload 路径。
6. **不能当正式版本的 sensitivity**包括 Stage71 的 8h 容量敏感性、Stage73 HTT 成本敏感性、Stage85N/O/P/Q 的经济参数/机制分支、Stage88B Site1=350、Stage88C Site4=250、Stage89D penalty=1500/1000，以及 Stage87D-B 的 H1/H2 工程参数候选含义（H2 被计算主线采用，但不等同工程设计定值）。
7. **已发生或重现的回归**包括：Stage7/8 终端语义、checkpoint 同进程 reload 内存问题、finalizer/schema 缺陷、6h 元数据被误当 active runtime、legacy TerminalLOH wiring、Site4 150/200 不一致。详见 `problem_fix_registry.csv`。
8. **当前最危险的混线位置**有三处：MAT 中 `NormalDemand.stage_dt_h=6` 与运行时 `params.dt_h=8`；Stage53 与 Stage88 TerminalLOH 同时存在；Stage89G/Stage85H/Stage85R 关键源文件均未被当前 Git HEAD 跟踪，`STAGE89G_FROZEN_COMMIT` 只校验 HEAD，不能冻结这些 untracked 文件。
9. **以后新增 Stage**：模型与输入从 Stage89F 的 current candidate bundle 继续；正式训练/OOS 以 Stage85R 的工程门禁为母版，同时保留 Stage85H-A clean-process 机制；只有 Stage89G run-002 完整 OOS 与 final QA 完成后，才可把它提升为新的 accepted runner。
10. **Stage89H single-loc4 candidate 已完成**：实验设计恢复原 FA-MSP 的单一已知初始状态语义，采用 Stage85R runner mother、Stage85H-A checkpoint lifecycle、Stage89F current 8h model 和 Stage88 DRO CAP200，在 loc4、terminal-gap penalty=1000 下 fresh 训练10轮并完成10000条同状态 OOS。Stage1仍为120.12 kg满产，Stage1-3 mean inventory为247.747/288.280/299.423 kg，mean cost/ordinary shortage/terminal gap为68445.650 yuan、6.140 kg、6.351 kg。它是 `CANDIDATE` diagnostic，不是最终 penalty 选择，也不是 Stage89G successor。
11. **D01 W outage/reconfiguration 诊断已完成**：复用 Stage87C-A exact failure realization 与 Stage88 current table，确认 a3-a6 mean lost load=`2.049/10.231/25.697/44.424%`、mean D=`12.457/62.200/156.230/270.082 kg`。a5/a6 DRO TerminalLOH 为 mean D 的 `3.60x/2.38x`，主要来自 terminal reserve redundancy；五条 tie-line 理想 connectivity 上界使 a5/a6 mean D 降低 `33.934%/25.918%`。它是 `DIAGNOSTIC_ONLY`，不改变 W 主线，也不是含潮流/开关/抢修约束的工程方案。
12. **D02 五点暴露/重构/定向加固 preview 已完成**：对 a3-a6 全部 420000 条冻结 trajectory exact replay 同一 line-resistance threshold。五点相对三点重构使 a5/a6 mean D 增加 `7.831%/4.162%`，但 q95/q99 D 不变；1-2/2-3 +10 m/s sensitivity 使 a5/a6 q95 D 降低 `28.400%/7.537%`、full-blackout probability 降低 `7.239/13.560 pp`，价值判为 `HIGH`。再对 3-4/4-5/5-6 +5 m/s 的增量 q95 D 降幅为 `6.890%/2.620%` 且不再降低 full blackout，保守总体判为 `LOW`。它是 `METHOD_PREVIEW`，道路保持三点，未修改 W/TerminalLOH 主线。
13. **D03 topology-based H2 island diagnostic 已完成**：复用 D02 G1 五点候选的 a3-a6 冻结轨迹与 D01 五条联络线，把 tie 明确作为 binary switch，并用固定 MAT 顺序 Kruskal 最大生成森林选择一个等价径向解。173520 个唯一故障拓扑全部通过无环、`edges=33-islands` 和 source 最大连通检查。对重构前原始失电节点，H2 站所在非源分量的 D 加权候选占比为 a3-a6 `20.740/34.222/39.474/41.947%`，a5/a6 黑岛占比为 `18.419/25.107%`。该结果是 `DIAGNOSTIC_ONLY` 的拓扑候选池；没有 FC dispatch、H2-to-power、grid-forming 或服务能力结论，也没有修改 current W/Stage88/FA-MSP。
14. **D04 双通道最小模型语义已冻结**：`D_res`、`A_elec`、静态 FC 等价切片容量与 road/electrical 共用一份累计 `T` 已在 9 个真实身份、54 个连续 LP 与 7/7 单元测试中通过。它仍是 `METHOD_PREVIEW / DIAGNOSTIC_ONLY`，不是正式 TerminalLOH。
15. **Stage89I 支持集与计算量审计已完成**：全量 35×15000 冻结身份的 OLD `(D,Aroad,C)` byte-exact 计数逐 state 复现 Stage88 manifest。NEW `(Dres,Aroad,Aelec,C)` 总支持由 `457414` 增至 `457431`，倍率 median/q90/max 为 `1/1.000040/1.000868`；保守 LP 结构倍率 `1.126051`，风险 `LOW`，继续 exact grouping 并进入隔离 Stage89J candidate-bank construction 的建议均为 `YES`。该节点不是 current W、accepted TerminalLOH 或 formal W candidate。
16. **Stage89J 正式隔离 candidate bank 已完成**：严格复用 35×15000 冻结身份、G1 五点电网 exposure、D03 确定性径向重构及 Stage88 三点 `Aroad/C`，生成 35 个 MATLAB-readable grouped bank。NEW `(Dres,Aroad,Aelec,C)` 总支持严格为 `457431`，160862 个唯一 topology 只分类一次；所有 `multiplicity/q_g`、Dres、Aelec、随机性 replay 与输出 SHA 门禁通过。它登记为 `FORMAL_W_CANDIDATE`，但仍是 `NOT CURRENT_W_MAINLINE`、`NOT ACCEPTED_TERMINALLOH`、`NOT MSP-ACCEPTED`。
17. **Stage89O common-path 机制后处理已完成**：Stage89H/N accepted run 使用 byte-identical 10000-path manifest 和同一 bank；首事件 cohort 为 Stage7/a1/lf8=`6124/3497/379`。Stage89N reserve level 强下降且为 `LEVEL_REDUCTION`；Stage85U-D canonical PCR/WES 给出 `WAIT_AND_SEE_EFFECT_SIZE=WEAKENED`，same-intensity/different-loc 4D L1 response 亦减弱。mean TerminalLOH gap proxy 改善，但 S5/Stage6 arrival 与 q99 tail 恶化，worst1% 全为 Stage7 且集中 a4/a5。无 actual W recourse closure，禁止宣称 realized resilience improvement。
18. **Stage89P 原论文风格主结果呈现已完成**：只读分析 Stage89N accepted run-003，并将 Stage89H 作为旧 TerminalLOH 辅助对照、Stage89O 仅作为 cohort/机制补充。Stage1–6 active-path mean production 为 `109.980/8.859/28.232/64.684/23.738/38.222 kg`；观察强度与制氢总体正相关但存在局部回摆，严格标为 `MODERATE_POSITIVE`。mean actual operating cost 为 `56182.450 yuan/path`（95% CI `55707.324–56657.576`）；真正进入 Stage7 的 6124 条路径 mean gap 为 `9.117 kg`。数据仅为 stage aggregate，10 轮不称收敛。

## Stage85H / 85H-A / 85R / 89F / 89G 的精确关系

- **Stage85H**：首次把 hourly-H2 + hourly-HTT 模型接进 fresh SAA/DRO smoke、10-iteration pilot、checkpoint 与独立诊断流程；run-001 暴露同进程 reload 的巨大内存问题。
- **Stage85H-A**：不改模型、训练目标或 checkpoint schema，只把保存、退出、干净进程单次 reload、hash/cut/schema 审计和阶段编排固化。它是 checkpoint 工程修复，不是新科学模型。
- **Stage85R**：在已接受的 8h/hourly IEEE33/hourly H2/hourly HTT/original-hourly-demand 模型上，新写 P150/P200 的 5h 固定预算训练、checkpoint audit、新 10k common Markov bank 和成对 OOS。它继承 Stage85H-A 的分进程思想，但 runner/orchestrator 是 Stage85R 专用实现。
- **Stage89F**：改的是 current 模型/输入入口与 preflight，恢复真正 8h，并接 Stage88 CAP200 DRO；它明确是 smoke-only，没有生成 checkpoint，也没有授权 training/OOS。
- **Stage89G**：新写 formal baseline launcher、Stage89G 身份化 reload audit 与 PowerShell orchestrator；模型从 Stage89F，checkpoint 生命周期机制从 Stage85H-A，正式 training/OOS 工程经验从 Stage85R。run-002 是 fresh 10-iteration（warm start `NONE`），不是复用任何历史 checkpoint。
- **Stage89H**：重新直接以 Stage85R 的 single-`params.k_init` runner semantics 为母版；已知初始状态机械映射为 loc4/internal index 81，training 与 OOS 使用同一状态。模型从 Stage89F、Terminal input 从 Stage88、checkpoint 生命周期从 Stage85H-A；唯一实验性经济变化是 terminal-gap penalty=1000。没有 multi-location Stage1 cuts，也不继承 Stage89G runner。

## Stage89H 最终审计结论

Stage89H run-003 的 preflight、10轮 fresh training、checkpoint save/外部SHA/clean single reload、loc4 10000-path OOS 和 final QA 全部通过。checkpoint save/SHA/reload 分别为81.711/0.794/51.211秒；checkpoint SHA-256为`7c12bb93a25f5833c24e28e10f2c33cceadf33e05f192790fc19443d630d699d`，OOS后不变。上一轮 blockage 记为 `BLOCKAGE_RESOLVED_BY_EXPERIMENT_DESIGN_CORRECTION`：没有修 backward algorithm，而是恢复“one known initial state -> one training -> same-state OOS”。

penalty=1000 下 loc4 Stage1仍四站全满产，early inventory buildup=`CLEAR`，因此本次行为分类为 `AGGRESSIVE`。由于只有10 iterations，下一步应先在相同 single-loc4 语义下补 penalty=1500 和2000 paired baselines；候选 penalty 的更长训练也值得进行。当前 training/OOS 推荐工程母版因此更明确为 Stage85R single-state runner + Stage85H-A lifecycle + Stage89F current input；Stage89H是该组合的当前 single-loc candidate implementation。

## checkpoint “慢/坏”问题判定

静态证据不足以把“checkpoint 写盘慢”定性为历史 OOM 的重现。已能机械分开三件事：

- Stage85H 与 Stage89G run-001 的明确故障是**同进程额外 reload 导致内存不足**；Stage89G run-001 的错误点是 `loaded=load(...)`，不是 `save(...)`。
- Stage89G run-002 的 298 MB checkpoint 使用 `-v7.3` 临时文件、`whos` 校验、原子 move，随后还做 SHA-256；保存和哈希本身可能耗时，但没有静态证据证明其异常或是旧 OOM。
- 若现场看到长时间停在 checkpoint 边界，优先区分 `save -v7.3`、全文件 SHA-256、干净 reload 三段；不得仅凭等待时间归类为模型回归。当前登记为 **UNCERTAIN / 需阶段耗时证据**。

## 证据边界与文档冲突

- Git HEAD 为 `db532c4cd661d6e3514abbbe5764c1ced5355c56`；origin 同步到该提交。Stage85H/85R/89F/89G 和 current W bundle 的关键文件在审计时均为 untracked 或依赖 dirty 工作树，因此“accepted/current”是项目结果与 README 层面的状态，不是 Git 可复现提交状态。
- `fa_msp/current_hourly_stage88_candidate/CURRENT_MSP_MAINLINE.md` 仍写“Stage89F smoke-only、无训练/OOS”，但同目录已存在 Stage89G formal runner/orchestrator。登记为 `DOCUMENTATION_CODE_MISMATCH`：前者正确描述 Stage89F，不能描述新增的 Stage89G runner。
- Stage89G orchestrator 校验 frozen HEAD，但 Stage89G 源文件本身 untracked。登记为 `DOCUMENTATION_CODE_MISMATCH / REPRODUCIBILITY_GAP`，不能声称 commit 单独锁住 runner 字节。
- 审计快照发现两个 MATLAB 进程（PID 4132、24612，启动时间 2026-08-20 23:07:30）。按任务约束仅记录存在，没有终止、干预或读取其高频日志；因此 Stage89G run-002 的最终结果不在本次审计中提前判定。

## 文件导航

- `CURRENT_MAINLINES.md`：三条当前主线、active input/runner/model/parameters 与禁止入口。
- `VERSION_EXPLAIN.md`：主要版本的人话解释。
- `VERSION_TREE.md`：模型、数据、runner 三套非单链谱系。
- `6h_to_8h_history.md`：6h/8h 与 90.09/120.12 kg 的来龙去脉。
- `version_registry.csv`：91 个版本节点的完整登记。
- `version_lineage.csv`：多父继承关系。
- `version_feature_matrix.csv`：主要版本功能矩阵。
- `problem_fix_registry.csv`：历史问题、修复与回归。

```text
VERSION_LINEAGE_RESOLVED = PARTIAL
CURRENT_W_MAINLINE_RESOLVED = YES
CURRENT_MSP_MAINLINE_RESOLVED = YES
CURRENT_TRAINING_RUNNER_LINEAGE_RESOLVED = YES
CHECKPOINT_LINEAGE_RESOLVED = YES
LEGACY_6H_LINEAGE_RESOLVED = YES
KNOWN_REGRESSIONS_REGISTERED = YES
```

`PARTIAL` 只针对部分早期试验节点父关系和未纳入 Git 的 Stage85+ 字节级复现边界；当前三条主线本身已经解析。

## D04 方法预览登记（2026-08-22）

D04 在隔离目录冻结 topology-based H2 electrical service 与现有 road service 的最小双通道模型。它读取 D02 G1、D03 径向重构、Stage88 H2 A/C 与当前 DRO CAP200 `T`，从候选 MAT 机械推导一小时 FC 等价 H2 上限；9 个真实冻结情景、54 个小 LP 与 7/7 单元测试通过。D04 是 `METHOD_PREVIEW / DIAGNOSTIC_ONLY`，不是 CURRENT W、Stage88/89 修改或 accepted TerminalLOH。

## Stage89I 支持集审计登记（2026-08-22）

Stage89I `run-002` 对 35 个正式 state 的 525000 个冻结 path 做 deterministic G1 replay、唯一 failure-mask/topology cache 与 raw-byte exact support counting。OLD `457414` 个 support 逐 state 复现 Stage88；NEW 为 `457431`，只多 17，增长集中在 a6 的 4 个 state。DRO support/probability-vector 倍率为 `1.000037`；考虑 `D_res` 减少变量与每 support 新增 12 条 FC 约束后，保守 TerminalLOH 结构倍率为 `1.126051`。`SUPPORT_EXPANSION_RISK=LOW`，但该结论只允许下一阶段隔离构建 candidate bank，不构成 current W 或 accepted TerminalLOH 的提升。

## Stage89J 正式隔离 candidate 登记（2026-08-22）

Stage89J `run-001` 在任何 bank 写出前先全量重计 35×15000 frozen identities，逐 state 与总计均严格复现 Stage89I；随后生成 35 个 grouped MAT bank、457431 行 exact-group index、state/intensity 统计、160862-topology cache QA、FC 静态 metadata 与 source/output SHA manifests。大型本体位于 `terminalLoh_wdro/output/stage89j_topology_h2_dual_channel_w_candidate/run-001/`，总计 `1104251473` bytes。当前 W mainline、Stage88、Stage89H 与所有 solver 未修改；Stage89J 仅是供 Stage89K 使用的 `FORMAL_W_CANDIDATE`。

## Stage89K 正式 TerminalLOH candidate 登记（2026-08-22）

Stage89K `run-002` 直接读取 Stage89J 的 35 个 frozen grouped banks，在完全沿用 Stage88 `c_H2/M_H2`、CAP200、exact `q_g`、eta=0.03 Pearson 集、LP/decomposition 架构与 tolerances 的条件下，仅将 recourse 升级为 `Dres/Aroad/Aelec/C`、共享 `T` 与静态 FC slice cap。35 个 SAA 和 35 个 DRO 全部 OPTIMAL，inventory/FC/q/p/Pearson QA 全部 PASS。全 state mean T_total 从 Stage88 的 SAA/DRO `344.707/382.035 kg` 降至 `237.924/277.211 kg`（`-30.978%/-27.438%`）。该变化只可解释为 `FULL CANDIDATE EFFECT`。状态为 `FORMAL_TERMINALLOH_CANDIDATE`，并明确 `NOT CURRENT_TERMINALLOH`、`NOT CURRENT_W_MAINLINE`、`NOT MSP-ACCEPTED`。

## Stage89L H2 electrical-island 增量消融登记（2026-08-22）

Stage89L `run-001` 在同一 Stage89J bank、Stage89K economics/q/Pearson/tank/tolerance/shared-T 口径下，只将 `Aelec` 替换为同形状零数组，并完成 road-only 35 SAA + 35 DRO；Case C 直接只读复用 Stage89K run-002。70 个 Case-B 均 OPTIMAL，所有 inventory/demand/probability/no-electrical gates PASS。dual-minus-road-only mean T_total 为 SAA `+0.836403%`、DRO `+0.875626%`；约 9.27 kg electrical service 主要替代约 7.73 kg road service，并额外减少约 1.55 kg shortage。结论为 `MIXED / MODERATE`，`RECOMMEND_ADOPT_STAGE89J_89K=YES`，但不自动标记 CURRENT W、CURRENT TerminalLOH 或 MSP accepted；正式 adoption 留给 Stage89M。


## Stage89M formal adoption and correct-8h integration (2026-08-23)

Stage89J run-001 and Stage89K run-002 are formally adopted as the current W and TerminalLOH, supported by Stage89L run-001. The unique navigation bundle is `terminalLoh_wdro/current_w_mainline_stage89/`; Stage88 remains a reproducible superseded predecessor. Strict Stage89K SAA/DRO hash, 35-state order, four-site, CAP200 and negative-loader gates pass. The Stage89F model was mechanically rebuilt as six operating stages with eight hourly periods each; Stage1 theoretical cap is 120.12 kg and legacy 90.09 is rejected. Stage7 value/subgradient/cut/forward smoke passes. No training, OOS, checkpoint, multi-location adaptation, or forward/backward-core modification occurred.

## Stage89N controlled single-loc4 retraining diagnostic (2026-08-23)

Stage89N `run-003` uses source HEAD `0da3c525...`, the Stage85R single-state runner mother, Stage85H-A clean-process lifecycle, Stage89F correct `6×8h`, and adopted Stage89K DRO eta=0.03. Training seed `20260513` and the accepted Stage89H run-003 loc4 OOS bank (seed `20260817`, 10000 paths) are exactly paired. Stage1 production moves from `120.12` to `109.98 kg` (`-8.4416%`); Stage1/2/3 mean ending inventory moves from `247.747/288.280/299.423` to `237.607/192.432/179.127 kg`. Mean ordinary shortage, terminal gap and HTT all decrease. The controlled judgment is `MODERATELY_REDUCED / LEVEL_REDUCTION`; this remains a 10-iteration single-location diagnostic, not a converged final policy. OOS completed before a native MATLAB exit fault; report-only recovery used no checkpoint reload.

## Stage89P original-paper-style primary result presentation (2026-08-23)

Stage89P `run-002` is read-only postprocessing of Stage89N accepted run-003, with Stage89H run-003 as the old-TerminalLOH control and Stage89O run-005 used only for validated cohorts and secondary explanation. It reports direct action-by-stage, inventory, observed-intensity/location action, random termination/Stage7 timing, economic/service statistics and 95% intervals in the result-analysis structure of Siddig and Song. The risk-intensity response is `MODERATE_POSITIVE`, not uniformly monotone; longer-lived a=1 and later-Stage7 paths accumulate more production. Mean actual operating cost is `56182.450 yuan/path`, ordinary shortage is `1.542 kg/path`, and the Stage7-conditional gap is `9.117 kg` across 6124 paths. All 12 figures and 16 CSV outputs passed independent hash, closure, parsing and visual QA. No training, OOS, checkpoint load, optimization or model change occurred; accepted data are stage aggregate and the ten-iteration policy is not converged.
