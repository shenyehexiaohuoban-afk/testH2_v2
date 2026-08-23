# 当前主线

## 0. Stage89 adopted W / TerminalLOH (CURRENT)

**CURRENT W:** Stage89J accepted run-001, signature `(Dres,Aroad,Aelec,C)`, 35×15000 frozen draws and exact `q_g=multiplicity/15000`.

**CURRENT TERMINALLOH:** Stage89K accepted run-002, 35×4 SAA/DRO tables, Pearson `eta=0.03`, tank `[300,200,100,200] kg`.

**ADOPTION EVIDENCE:** Stage89L accepted run-001 (`MIXED / MODERATE`, `RECOMMEND_ADOPT_STAGE89J_89K=YES`). Stage88 is preserved as the superseded reproducible predecessor. The sole navigation entry is `terminalLoh_wdro/current_w_mainline_stage89/`. Stage89M verified the Stage89F `6×8h=48h` hourly model, 120.12 kg Stage1 sentinel and strict Stage7/cut/forward integration without training/OOS/checkpoint or core changes.

**CURRENT CONTROLLED RETRAINING DIAGNOSTIC:** Stage89N run-003 is the paired single-loc4, penalty1000, fresh 10-iteration test of adopted Stage89K. Stage1 is `109.98 kg` versus Stage89H `120.12 kg`; integrated judgment is `MODERATELY_REDUCED / LEVEL_REDUCTION`. It is not `CURRENT_FINAL_POLICY`, not fully converged, and does not replace the adopted W/TerminalLOH identities above.

## 1. W / TerminalLOH (SUPERSEDED STAGE88 PREDECESSOR)

**SUPERSEDED HISTORICAL VERSION**

Stage89A reproducibility bundle 所指向的 Stage88 CAP200 DRO candidate；实际生成谱系为：

```text
Stage87B kernel/geometry/A-B-C
  -> Stage87C-A formal 35×15000 nominal W bank
  -> Stage87D-B H2 retained hardening candidate
  -> Stage88A CAP200 H2 bank + SAA/DRO TerminalLOH
  -> Stage88A1 capacity post-audit
  -> Stage88D 35-state reconciliation
  -> Stage88E state11/state28 tail diagnostic
  -> Stage89A current_w_mainline_stage88 bundle
```

**ACTIVE INPUT**

`terminalLoh_wdro/current_w_mainline_stage88/terminal_tables/` 中的 CAP200 表，以及给 FA-MSP 的 loader-shaped 副本 `msp_bridge/terminal_loh_stage88_dro_eta003_cap200.csv`。W bank 本体通过 large-data manifest 引用，不复制到 MSP。

**ACTIVE RUNNER / MODEL**

当前 bundle 是静态复现索引，不是可直接启动的新 W runner。生成模型是 Stage87B 的 W1-W3 一小时后登陆后果 kernel、Stage87C-A 的 35×15000 bank、Stage87D-B H2 road hardening、Stage88A 的 fixed-T recourse 与 Pearson probability DRO。

**ACTIVE PARAMETERS**

- 35 初始 W 状态：`a=2..6` × `loc=1..7`，`lfw=0`；每状态 15000 条。
- geometry Position A；Rmax=40；outside-radius exponent=0.6；line design speed 25 m/s。
- Candidate-1 road fragility；H1 对 E33 +5 m/s，H2 进一步对 E29 +2.5 m/s。
- CAP200：tank `[300,200,100,200] kg`；Pmax `[300,200,120,150] kW`。
- SAA nominal support；DRO 为 flat Pearson chi-square，`eta=0.03`。
- `c_H2=32.5213675213675`、`M_H2=1283.205` yuan/kg。

**KNOWN SENSITIVITY-ONLY BRANCHES**

Stage88B Site1=350、Stage88C Site4=250、Stage88A CAP150 arms；Stage87D-A Candidate-1 baseline preview、H1 hardening、Stage87D-C capacity lineage audit。H2 hardening虽被计算主线保留，其阈值仍只是 computational candidate，不是工程最终设计值。

**CURRENT DIAGNOSTIC-ONLY EVIDENCE**

`D01` 使用 Stage87C-A 已有 exact failure realization 与 Stage88 current table，离线分开审计物理失电、灾害氢需求 `D`、TerminalLOH `T`、关键 feeder lines 和五条 IEEE33 normally-open ties 的理想 connectivity 上界。它没有重跑 W/TerminalLOH，也不改变 current chain；理想重构结果不含 AC/DistFlow、电压、热限、开关时序、tie fragility 或抢修约束。证据位于 `results/task-002-stage2b-b3-smoke/w-grid-outage-reconfiguration-diagnostic/run-003/`。

`D02` 在 D01 定义上对 Stage87C-A 的 a3-a6 全部 420000 条冻结 trajectory exact replay 同一 MT19937 line-resistance threshold，插入 M12/M23 hazard-update points，并比较 B0/B1/B2/G1/G2。M12/M23 不增加时间权重，D 仍为 W1/W2/W3 各 1h；roads 保持三点。1-2/2-3 strong shift 的极端尾部价值判为 `HIGH`，3-4/4-5/5-6 moderate shift 的保守增量价值判为 `LOW`。它是 `METHOD_PREVIEW / DIAGNOSTIC_ONLY`，不改变 current W、Stage88 TerminalLOH 或任何 FA-MSP 输入。证据位于 `results/task-002-stage2b-b3-smoke/w-5point-reconfig-hardening-preview/run-003/`。

`D03` 继续把 D02 G1 作为“current five-point candidate”做静态拓扑诊断，但不把它提升为 current W mainline。五条 tie 以 binary switch 处理，固定 MAT 顺序只闭合连接不同分量的 tie，得到 source 连通节点最大、全图无环的最大生成森林。a3-a6 的 H2-site-containing non-source component 候选 D 占原始失电 D 的 `20.740/34.222/39.474/41.947%`；这些是拓扑候选，不是已供电孤岛，因为没有 FC dispatch、grid-forming 或电气/库存耦合。证据位于 `results/task-002-stage2b-b3-smoke/topology-based-h2-island-diagnostic/run-001/`。

**SUPERSEDED / DO NOT USE**

pre-Stage87 geometry preview、旧 wind_mc/roadSoft/RiskCap-Mean、旧 Wasserstein D/A/C ground-cost 主线、Stage53 TerminalLOH 表、CAP150 表均不得替代当前 bundle。

**EVIDENCE**

`terminalLoh_wdro/current_w_mainline_stage88/CURRENT_W_MAINLINE.md`、`README.md`、`manifests/`、Stage87B/87C-A/87D-B/88A/88A1/88D/88E 各 result README、D01/D02 run-003 README，以及 `codex_rule/log.md` 的 Stage89A/D01/D02 条目。

## 2. FA-MSP 模型

**CURRENT VERSION**

Stage89F 建立的 isolated candidate entry：`fa_msp/current_hourly_stage88_candidate/`。它组合了 Stage80 hourly IEEE33、Stage82 Stage7/8 终端语义、Stage85B hourly H2、Stage85G hourly HTT、Stage85K original-hourly demand、Stage89B Stage88 CAP200 bridge。

**ANCESTRY**

```text
legacy aggregate FA-MSP
  -> Stage80 hourly IEEE33 (0.90–1.10 pu)
  -> Stage82 Stage1–6 operating / Stage7 analytic / Stage8 absorbing
  -> Stage85B hourly H2 balance
  -> Stage85G hourly HTT
  -> Stage85K original hourly demand
  + Stage89B Stage88 DRO CAP200 bridge
  -> Stage89F current candidate entry
```

**ACTIVE INPUT**

- `terminalLoh_wdro/current_w_mainline_stage88/msp_bridge/near_stage_msp_input_stage88_cap200_candidate.mat`
- `terminalLoh_wdro/current_w_mainline_stage88/msp_bridge/terminal_loh_stage88_dro_eta003_cap200.csv`

MAT 里的 `NormalDemand.stage_dt_h=6` 只记录四个原始 6h demand block 的来源；active stage duration 由 options 强制为 8h。

**ACTIVE RUNNER / ACTIVE MODEL**

- 静态验证入口：`fa_msp/current_hourly_stage88_candidate/launcher/run_current_hourly_stage88_candidate_smoke_h2.m`
- formal candidate runner：`fa_msp/current_hourly_stage88_candidate/launcher/run_current_hourly_stage88_dro_baseline_h2.m`（Stage89G；审计时尚不能据运行中目录宣告最终 accepted）
- options：`config/current_hourly_stage88_candidate_options_h2.m`
- loader：`input/load_current_hourly_stage88_candidate_h2.m`
- model builder：`build_integrated_hourly_stage_model_hourly_htt_v1_h2.m` 及 update dispatcher chain。

**ACTIVE PARAMETERS**

- `params.dt_h=8`，6×8h=48h，inner dt=1h。
- 6 个 operating stages；Stage7 analytic TerminalLOH；Stage8 zero absorbing。
- original hourly demand：24h source 直接使用并重复到 48h。
- hourly IEEE33、hourly H2 inventory/service、hourly end-of-hour HTT arrival。
- interstage state 只有 `[I1,I2,I3,I4]`；W 的 D/A/C、road/grid failure 和 post-landfall kernel 仅通过 TerminalLOH 间接进入。
- tank `[300,200,100,200]`；Pmax `[300,200,120,150]`；普通 shortage penalty 200；terminal gap penalty 2000。
- Stage1 理论 8h production ceiling = `0.0195 × 8 × (300+200+120+150) = 120.12 kg`。

**KNOWN SENSITIVITY-ONLY BRANCHES**

Stage71 8h sensitivity、Stage73 HTT cost、Stage85N/O/P/Q penalties/c0/cd、Stage89D 1500/1000、Stage88B/C capacities。

**SUPERSEDED / DO NOT USE**

- Stage89C/89D：继承 legacy aggregate loader，active dt=6，90.09 kg；只保留作诊断。
- Stage85I：block-uniform demand，不是 original-hourly data。
- Stage57：Stage53 fixed-budget historical pilot；目录名 `converged` 不能作为收敛证据。
- legacy `main_msp_h2_near.m` 默认入口：仍是历史 aggregate main，不自动等于 current Stage88 candidate。

**DOCUMENTATION_CODE_MISMATCH**

`CURRENT_MSP_MAINLINE.md` 正确说明 Stage89F 本身 smoke-only，但尚未加入同目录后来出现的 Stage89G formal runner；因此用它判断“目前没有 formal runner”已经过时。

## 3. Training / checkpoint / OOS 工程

**CURRENT VERSION**

已接受的历史母版是 Stage85R，checkpoint process boundary 来源是 Stage85H-A，模型/input主线是 Stage89F。Stage89H run-003 是这三者加 Stage88 DRO CAP200 的当前 single-known-initial-state candidate implementation：loc4、penalty=1000、fresh 10 iterations、same-state 10000-path OOS，状态为 `CANDIDATE`。Stage89G 是不同的 multi-initial-location runner adaptation，不是 Stage89H 的父节点，也不与 Stage89H 做直接 paired scientific comparison。

**ANCESTRY / COMPONENT SOURCES**

| 组件 | 主要来源 | Stage89G 的做法 |
|---|---|---|
| 模型与输入 | Stage89F + Stage89B + Stage88 | 直接调用 current candidate loader/preflight |
| fresh 训练与 formal OOS 工程母版 | Stage85R | 重写为单个 DRO arm、10 iterations、loc1/4/7 各 10k |
| checkpoint safe save | Stage85H / 85H-A | `-v7.3` temp、`whos` schema、atomic move |
| save-exit-clean-reload | Stage85H-A | 训练 MATLAB 退出；新进程单次 load；PASS gate |
| Stage7/8 / hourly model schema | Stage82 + 85B + 85G | 断言 `hourly-h2-hourly-htt-v1` 与 4D state |
| original hourly demand | Stage85K | 断言 `original-hourly-24h-repeat-v1` |
| finalizer/orchestrator | Stage89G 新写 | 新增三地汇总、plots、QA、phase gates、frozen HEAD check |

**ACTIVE RUNNER**

- MATLAB: `fa_msp/current_hourly_stage88_candidate/launcher/run_current_hourly_stage88_dro_baseline_h2.m`
- clean reload adapter: `run_current_hourly_stage88_run002_reload_audit_h2.m`
- orchestration: `orchestrate_current_hourly_stage88_dro_run002.ps1`
- single-state Stage89H candidate: `run_stage89h_stage85r_single_loc4_gap1000_h2.m`
- Stage89H orchestration: `orchestrate_stage89h_stage85r_single_loc4_gap1000.ps1`

Stage89H 保留 Stage85R 的原生 Stage1 cut 语义：只为 `params.k_init` 生成 Stage1 cuts。对于 one-known-initial-state 研究设计，这是 expected behavior，不是缺陷。Stage89H 的 `params.k_init` 为 loc4/internal index 81，且只做 loc4 OOS。

**CHECKPOINT IDENTITY**

Stage89G run-002 checkpoint 名为 `checkpoints/stage89g_final_policy_checkpoint.mat`，fresh training、warm start `NONE`、10 iterations、预期 10540 cuts、schema `hourly-h2-hourly-htt-v1`。SHA-256、byte size、cut-coefficient hash 与 reload memory snapshot 是 Stage89G 新增/扩展的审计输出；历史 Stage85R checkpoint 不被复用。

**OOS**

Stage85R 是 P150/P200 共用同一新 10k Markov bank 的 paired OOS。Stage89G 改为 loc1/4/7 各自独立 seed、每地 10k，共 30k；训练 seed 与 OOS seeds 分离。此差异是 runner 语义变化，不是薄路径包装。

**DO NOT USE**

- Stage85H run-001 failed same-process reload；Stage85H run-002 finalizer failure只可由 85H-B 报告修复。
- Stage85L run-001 finalizer failure；只认 85L-A/后续。
- Stage89G run-001 旧 monolithic 同进程 reload 路径；已出现 OOM。
- Stage89G `run-001-failed-schema-*`；训练表重复列名，属于 runner schema failure。
- Stage89C/89D checkpoint；模型时间尺度错误。

**REPRODUCIBILITY GAP**

上述 Stage85H、85R、89F、89G 关键 runner 当前均未被 `db532c4` 跟踪。Stage89G orchestrator 的 `git rev-parse HEAD` 门禁只能冻结已提交内容；正式接受前应另行建立 source manifest 或提交这些字节。本审计不执行 Git 写操作。

## D04 非主线边界

D04 `topology-h2-dual-channel-minimal-model/run-006` 只冻结候选 `D_res`、`A_elec`、静态 FC 等价切片容量与双通道共享 `T` 的数学语义，并用 9 个真实情景做小 LP sanity check。它没有修改 current W bundle、Stage88/89、FA-MSP 或正式 TerminalLOH，也没有生成可替代当前 D/A/C bank 的输入。状态严格为 `METHOD_PREVIEW / DIAGNOSTIC_ONLY`。

## Stage89I 非主线边界

Stage89I `stage89i-dual-channel-support-expansion-audit/run-002` 只读取 35×15000 冻结身份、Stage88 D/Aroad/C、D02 G1 与 D03/D04 语义，完成 OLD/NEW byte-exact support counting 和静态成本估算。OLD/NEW 总支持为 `457414/457431`，风险为 `LOW`。它没有生成 dual-channel bank、没有运行 SAA/DRO/TerminalLOH/FA-MSP/OOS，也没有修改 current W、Stage88 或 Stage89H；状态严格为 `DIAGNOSTIC_ONLY / METHOD_PREVIEW`，且 `NOT FORMAL W CANDIDATE`。

## Stage89J 隔离 candidate 边界

Stage89J `stage89j-topology-h2-dual-channel-w-candidate/run-001` 已正式生成 `(Dres,Aroad,Aelec,C)` grouped candidate bank：35×15000 frozen draws、457431 exact groups、160862 cached topologies，全部 replay/grouping/q/Dres/Aelec 门禁通过。大型 MAT 本体位于 `terminalLoh_wdro/output/stage89j_topology_h2_dual_channel_w_candidate/run-001/`。它可作为后续 Stage89K 的隔离输入，但没有替换本文件第 1 节的 Stage88 current W/TerminalLOH；状态为 `FORMAL_W_CANDIDATE`、`NOT CURRENT_W_MAINLINE`、`NOT ACCEPTED_TERMINALLOH`、`NOT MSP-ACCEPTED`。

## Stage89K 隔离 TerminalLOH candidate 边界

Stage89K `stage89k-terminalLoh-dual-channel-candidate/run-002` 已在 Stage89J frozen bank 上完成 35 SAA + 35 eta=0.03 Pearson DRO 正式 LP。70/70 cases 为 OPTIMAL，shared-inventory、static-FC、q/p probability 与 ambiguity-radius gates 全部 PASS。Stage88 SAA/DRO 全 state mean `T_total` 为 `344.707/382.035 kg`，Stage89K 为 `237.924/277.211 kg`。这是同时包含 five-point grid exposure、G1、radial reconstruction、Dres 与 Aelec 双通道的 `FULL CANDIDATE EFFECT`，不可单独归因于 H2 island 或 topology reconstruction。Stage89K 是 `FORMAL_TERMINALLOH_CANDIDATE`，不是本文件第 1 节的 current TerminalLOH/W，也未进入 FA-MSP。

## Stage89L mechanism-ablation 非主线边界

Stage89L `stage89l-h2-island-incremental-ablation/run-001` 以 Stage89J/89K 完全相同的 `Dres/Aroad/C/q_g`、CAP200、eta=0.03、shared-T、LP/decomposition 与 tolerances 为基础，仅关闭 `Aelec`，完成 road-only 35 SAA + 35 DRO；accepted Stage89K run-002 仅只读复用。dual-minus-road-only mean T_total 为 SAA `+0.836403%`、DRO `+0.875626%`，机制判断 `MIXED`、价值 `MODERATE`。该建议已由 Stage89M 执行：Stage89J/K 当前身份见本文件第 0 节；Stage89L 仍保持 FORMAL_MECHANISM_ABLATION。
