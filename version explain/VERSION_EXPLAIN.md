# 主要版本人话解释

本文件讲“为什么有这个版本”；逐字段与细粒度节点见 `version_registry.csv`。状态只使用任务规定词汇。

## W / TerminalLOH 的早期方法线

### legacy W 与 W3 B1/B2/B3

**基于：** 早期 `wind_mc/roadSoft/RiskCap-Mean` 与 W1-W3 后登陆模拟。**为什么做：** 把风、电网、道路后果转成 TerminalLOH 可用的 D/A/C。**改了什么：** B1/B2 增加 lookahead 与 D/A/C samples，后续 stagewise-random B3 冻结正式随机风输入。**新增能力：** 后果样本、原子聚合与 Wasserstein ground-cost 试验。**结果：** 建立了后续概率 DRO 的数据基础，但旧 ground-cost 结论已被替代。**后续：** three-period 与 Step04A/B。**状态：** `SUPERSEDED`。

### Step03Z three-period

**基于：** formal random B3。**为什么做：** 判断 aggregate D/A/C 是否丢失 W1-W3 时序信息。**改了什么：** 冻结 three-period consequence representation，并校正 D scaling。**新增能力：** period-vs-aggregate 独立 LP cross-check。**结果：** 明确三期信息结构与尺度。**后续：** Step04A。**状态：** `HISTORICAL`。

### Step04A / Step04B

**基于：** three-period consequence 与概率分布。**为什么做：** 旧 Wasserstein ground metric 很难稳定解释决策，转向 probability ambiguity。**改了什么：** Step04A 验证概率 DRO feasibility；Step04B 实现 flat Pearson chi-square production solver。**新增能力：** 在有限支持上直接扰动概率、`eta` 可解释。**结果：** flat Pearson 成为后续 TerminalLOH 的 accepted DRO 方法。**后续：** C5B/C5C/Stage53/Stage88。**状态：** Step04A `HISTORICAL`，Step04B 方法 `ACCEPTED`。

### C5B / C5C / Stage53

**基于：** Step04B。**为什么做：** 统一 fixed-T recourse 经济口径并选择 eta。**改了什么：** C5B 统一 `c_H2/M_H2`；C5C 审计 eta response；Stage53 生成 35-state SAA 与 eta=.03 TerminalLOH 表。**新增能力：** 可被 FA-MSP lookup loader 使用的 35×4 表。**结果：** Stage53 长期成为 legacy lookup 主线。**后续：** Stage55–57；最终被 Stage88 CAP200 替代。**状态：** 方法 `ACCEPTED`，数据 `SUPERSEDED`。

## legacy FA-MSP 与 hourly 电网

### Stage55 / Stage56 / Stage57

**基于：** legacy aggregate FA-MSP + Stage53 table。**为什么做：** 先验证 native main 可运行，再接 SAA/DRO dual TerminalLOH，最后做固定预算训练。**改了什么：** Stage55 是安全 smoke；Stage56 是 loader/interface；Stage57 运行 SAA/DRO A/B。**新增能力：** 解析 Stage7 lookup 与 checkpoint/pilot 结果。**结果：** 证明接入可行，但 Stage57 stop flag 不构成收敛证书。**后续：** Stage71/73 与 hourly-grid 线。**状态：** `HISTORICAL`；Stage55/56 另为 `SMOKE_ONLY`。

### Stage71 / Stage73

**基于：** Stage57/legacy aggregate。**为什么做：** 分别测试 8h effective capacity 与 HTT transport cost。**改了什么：** 只改 stage duration/capacity 或 HTT cost 参数。**新增能力：** 参数敏感性解释。**结果：** 8h 有效容量与 HTT 行为被量化，但没有替换主线。**后续：** 为 hourly 模型设计提供证据。**状态：** `SENSITIVITY_ONLY`。

### Stage79 / Stage80

**基于：** legacy FA-MSP。**为什么做：** 在每个运行 stage 内接入 IEEE33 LinDistFlow。**改了什么：** 增加 8 个 hourly grid slots、branch flow、voltage 与 PV/grid coupling；Stage79 用 0.95–1.05 pu，Stage80 改为 0.90–1.10 pu。**新增能力：** 6×8h hourly 电网。**结果：** Stage79 不可行，Stage80 smoke 通过。**后续：** Stage81/82/84。**状态：** Stage79 `FAILED`，Stage80 `ACCEPTED`（结构）。

### Stage81 / Stage82

**基于：** Stage80。**为什么做：** 做短训练/checkpoint 后发现 Stage7/8 仍错误走 hourly operating builder。**改了什么：** Stage82 把 Stage1–6 限定为 operating，Stage7 恢复解析 TerminalLOH，Stage8 为 zero absorbing。**新增能力：** 正确的 terminal semantics。**结果：** 终端边界回归被修复；Stage81 policy wrapper 可保留，但失败路径不可复用。**后续：** Stage84。**状态：** Stage81 `FAILED/PARTIAL`，Stage82 `ACCEPTED`。

### Stage84 / 84A / 84B / 84C–E

**基于：** Stage80+82。**为什么做：** 从 smoke 升级到 formal hourly-grid training 和 common-path OOS。**改了什么：** Stage84 建 launcher/checkpoint/OOS；84A 修 typed-empty hourly response schema；84B 完成 full common-path paired analysis；84C–E 做机制与论文图。**新增能力：** hourly grid policy 的可审计训练/OOS。**结果：** 工程骨架成熟，但 H2/HTT 仍是 stage-level。**后续：** Stage85A。**状态：** Stage84/84B `ACCEPTED`（历史 runner），修复 `ACCEPTED`，图表 `DIAGNOSTIC_ONLY`。

## 完整 hourly H2 / HTT / demand

### Stage85A

**基于：** Stage84。**为什么做：** 审计“hourly grid”是否意味着整个 H2 模型都 hourly。**改了什么：** 不改模型，只追踪 P_EL、demand、inventory、HTT 的时间尺度。**新增能力：** 识别混合尺度。**结果：** 电力 hourly，但 H2 demand/inventory 与 HTT 仍 stage-level；旧 6h metadata 仍在。**后续：** Stage85B/G/J/K。**状态：** `DIAGNOSTIC_ONLY`。

### Stage85B / 85C / 85D

**基于：** Stage85A + Stage82。**为什么做：** 最小化实现 hourly H2 balance，并验证单路径和批量稳定性。**改了什么：** 增加 hourly production/service/inventory，interstage state 保持 4D；需求先用 stage total/8。**新增能力：** hourly H2 动态。**结果：** smoke/stress 通过，数据仍非 original-hourly。**后续：** Stage85G/I/K。**状态：** 85B `ACCEPTED`（结构），85C/D `SMOKE_ONLY`。

### Stage85E / 85E-A

**基于：** Stage85B。**为什么做：** 做短训练 pilot；driver 的 eager LB(0) 访问引发工程失败。**改了什么：** 85E 增强 training logging；85E-A 只修 driver 的初始化/访问次序。**新增能力：** 可持续写 training summaries。**结果：** 模型本身未被否定，失败是 runner 工程缺陷。**后续：** Stage85H。**状态：** 85E `HISTORICAL`，85E-A `ACCEPTED`（runner fix）。

### Stage85F / Stage85G

**基于：** Stage85B。**为什么做：** 先审计 HTT 成本/时序，再把运输从 stage-level 变成 hourly。**改了什么：** Stage85G 增加每小时 flow、1h trip 假设与 end-of-hour arrival。**新增能力：** hourly HTT。**结果：** 完整 hourly-H2/hourly-HTT schema 成立。**后续：** Stage85H/K/R。**状态：** 85F `DIAGNOSTIC_ONLY`，85G `ACCEPTED`（结构）。

### Stage85H

**基于：** Stage85G + Stage84 runner 工程。**为什么做：** 对 hourly-H2/hourly-HTT 模型做 fresh SAA/DRO smoke、10-iteration pilot、checkpoint reload 与 80-path directed-OD diagnostic。**改了什么：** 新写 staged training/checkpoint/diagnostic runner。**新增能力：** fresh cuts、checkpoint schema、pilot policy reload。**结果：** training/checkpoint 写出成功，但 run-001 同进程 reload 显示压缩约 300 MB、展开约 28.5 GB并内存失败；run-002 science 完成后 finalizer 又失败。**后续：** 85H-A/B。**状态：** `HISTORICAL`，失败 runs 单列 `FAILED`。

### Stage85H-A

**基于：** Stage85H。**为什么做：** 解决 checkpoint reload 内存峰值。**改了什么：** 不改模型、训练或 checkpoint schema；训练 save 后退出，clean MATLAB 单次 load，检查变量/hash/cuts/state-only/schema/fresh identity，PASS 才进入下一 phase。**新增能力：** 进程边界内存隔离。**结果：** clean reload 约 40.096s，独立回归通过。**后续：** Stage85R 与 Stage89G run-002。**状态：** `ACCEPTED`。

### Stage85H-B

**基于：** Stage85H run-002。**为什么做：** 已完成训练/诊断，但 finalizer schema 失败。**改了什么：** report-only recovery，不训练、不 reload checkpoint。**新增能力：** 从已完成 artifact 生成最终报告。**结果：** 恢复 SAA/DRO 10 iterations、10510 cuts 的 science output。**后续：** finalizer 设计经验进入后续 runner。**状态：** `RECOVERY_ONLY`。

### Stage85I / 85J / 85K

**基于：** Stage85G。**为什么做：** 解决 hourly 模型仍使用块状 demand 的问题。**改了什么：** 85I 把 6h totals 均匀摊到小时；85J 追溯 `hourly_kg -> stage_template` 来源；85K 改为直接使用原始 24h hourly_kg 并重复到 48h。**新增能力：** original-hourly demand。**结果：** 85I 被 85K 淘汰；85J 是来源审计。**后续：** Stage85L/R/89F。**状态：** 85I `SUPERSEDED`，85J `DIAGNOSTIC_ONLY`，85K `ACCEPTED`。

### Stage85L / 85L-A

**基于：** Stage85K + hourly HTT。**为什么做：** 在 original-hourly demand 上运行 DRO training/diagnostic。**改了什么：** 新 pilot runner/checkpoint；85L-A 修 finalizer active numeric-index bug。**新增能力：** hourly-demand/hourly-HTT DRO policy 报告。**结果：** 训练可用，原 finalizer 失败由 recovery 修复。**后续：** N/O/P/Q/R。**状态：** 85L `HISTORICAL`，85L-A `RECOVERY_ONLY`。

### Stage85N / O / P / Q

**基于：** Stage85L/K。**为什么做：** 分辨普通 shortage penalty、`c0`、`c_d` 与 fragmentation 机制。**改了什么：** 分别测试 shortage=100/150、c0=5 等，不替换模型结构。**新增能力：** 经济校准和 P150 fragmentation 诊断。**结果：** 支持 Stage85R 选择 P150/P200 正式比较。**后续：** Stage85R。**状态：** `SENSITIVITY_ONLY` 或 `DIAGNOSTIC_ONLY`。

### Stage85R

**基于：** Stage85K 完整 8h hourly model + Stage85H-A clean-process 工程 + N/O/P/Q 参数证据。**为什么做：** 在相同模型/路径下正式比较 P150/P200。**改了什么：** 新写每 arm 5h fixed-budget fresh training、checkpoint audit、新 common 10k Markov bank、paired OOS 与分析 orchestrator。**新增能力：** 8h/hourly IEEE33/original hourly demand/hourly HTT/checkpoint/10k OOS 全链。**结果：** P200 获 `P200_SUPPORTED_BY_5H_10K_OOS`；run 中 native heap/finalizer 问题由分进程与 recovery 处理。**后续：** Stage85S–Y diagnostics；作为 Stage89G 主要 runner 母版。**状态：** `ACCEPTED`。

### Stage85S–Y

**基于：** Stage85R P200。**为什么做：** 生成代表路径图，分析 early reserve、wait-and-see、geometry、W consequence saturation、TerminalLOH tail 和 A/B intervention。**改了什么：** 主要是诊断、分 cohort 或参数干预，不改 accepted training lineage。**新增能力：** 机制解释。**结果：** 补强论文/解释证据，但不能作为正式 policy 入口。**后续：** W geometry 与 Stage89 集成审计。**状态：** `DIAGNOSTIC_ONLY` / `SENSITIVITY_ONLY`。

## 当前 W 重建线

### Stage86 / Stage87A

**基于：** 当前 W 代码与历史图/坐标。**为什么做：** 先审计 W-grid-road-H2 geometry，再预览新候选。**改了什么：** 只做 geometry/source 诊断与 preview。**新增能力：** 识别旧位置、尺度与候选 Position A。**结果：** 为 Stage87B 提供校准。**后续：** Stage87B。**状态：** `DIAGNOSTIC_ONLY`。

### Stage87B

**基于：** Stage86/87A 证据与 existing W generator。**为什么做：** 把 kernel、geometry、A/B/C 定义一次性参数化并冻结。**改了什么：** loc/lfw/intensity kernels、25-km geometry、A/B/C shifts、Rmax/decay、Candidate-1 config。**新增能力：** 可复现 W candidate configuration。**结果：** 通过集成 audit，但还不是 full bank。**后续：** Stage87C-A。**状态：** `ACCEPTED`。

### Stage87C-A / 87C-B0

**基于：** Stage87B Position A。**为什么做：** 生成正式大样本 nominal W bank，并独立审计 recourse wind。**改了什么：** 35×15000 trajectories、固定 seeds/random identity、D/A/C exact grouping。**新增能力：** 525000 条正式 consequence bank。**结果：** 成为 Stage88 数据母体。**后续：** 87D/88A。**状态：** 87C-A `ACCEPTED`，87C-B0 `DIAGNOSTIC_ONLY`。

### Stage87D-A / A1 / B / C

**基于：** Stage87C-A。**为什么做：** 分别检查 road fragility、不可达容量与关键边、E33/E29 hardening、tank-capacity cap。**改了什么：** A 预览 Candidate-1；A1/C 只诊断；B 生成 H1/H2 参数分支，H2 在 H1 基础上再 harden E29。**新增能力：** road-hardening candidate bank 选择。**结果：** H2 被 Stage88 采用，但参数仍是 computational sensitivity settings。**后续：** Stage88A。**状态：** H2 `ACCEPTED`（计算候选），其余 `CANDIDATE/DIAGNOSTIC_ONLY`。

### Stage88A / 88A1 / 88D / 88E

**基于：** Stage87C-A random identity + Stage87D-B H2。**为什么做：** 重算 H2 bank，比较 CAP150/CAP200 与 SAA/DRO，并闭环容量与尾部差异。**改了什么：** Site4 tank candidate 200；生成四个 35×4 arms；A1/D/E 做容量、statewise、tail probability 审计。**新增能力：** 当前 Stage88 TerminalLOH。**结果：** CAP200 DRO eta=.03 成为 current table，state11/28 差异得到解释。**后续：** Stage89A/B/F/G。**状态：** CAP200 DRO `CURRENT`，审计 `DIAGNOSTIC_ONLY`。

### Stage88B / Stage88C

**基于：** Stage88A CAP200。**为什么做：** 测 Site1=350 与 Site4=250 的 directed capacity effect。**改了什么：** 只改容量参数。**新增能力：** 容量敏感性。**结果：** 未替代 CAP200。**后续：** 仅作决策参考。**状态：** `SENSITIVITY_ONLY`。

## Stage89 集成与当前 runner

### Stage89A

**基于：** Stage87B/C/D 与 Stage88A/A1/D/E。**为什么做：** 解析唯一 W 主线并审计 FA-MSP 是否已接入。**改了什么：** 只读打包 source/config/table/result manifests。**新增能力：** current W bundle 与 bridge 导航。**结果：** W 主线清楚，但当时 FA-MSP 仍用 Stage53/legacy capacity。**后续：** Stage89B。**状态：** `CURRENT`（索引）/`DIAGNOSTIC_ONLY`（动作）。

### Stage89B

**基于：** Stage89A bundle。**为什么做：** 最小接入 Stage88 DRO CAP200。**改了什么：** 生成 candidate MAT，将 Site4 tank 从 150 同步到 200，严格校验 35×4 table；Stage7 penalty 保持 2000。**新增能力：** Stage88 loader bridge。**结果：** mapping/cut smoke 通过，但未规定 8h runtime。**后续：** 错误分支 89C/D 与正确分支 89F。**状态：** `ACCEPTED`（bridge）。

### Stage89C / Stage89D

**基于：** Stage89B + legacy default runner。**为什么做：** 做 10-iteration、三地 OOS 与 penalty 2000/1500/1000 sensitivity。**改了什么：** runner 与 penalty；模型却仍是 aggregate 6h。**新增能力：** 仅有 legacy-6h 诊断比较。**结果：** Stage1 ceiling 90.09，不能代表当前 8h。**后续：** Stage89E 诊断。**状态：** 89C `HISTORICAL`，89D `SENSITIVITY_ONLY`。

### Stage89E

**基于：** Stage89C/D artifacts 与 source chain。**为什么做：** 查明 90.09 kg。**改了什么：** 不改模型，只核对 defaults、MAT、params、builder 和公式。**新增能力：** 6h 回归的完整根因链。**结果：** 证实没有 scalar cap，错误是 active 6h aggregate entry。**后续：** Stage89F。**状态：** `DIAGNOSTIC_ONLY`。

### Stage89F

**基于：** Stage89B bridge + Stage80/82/85B/85G/85K accepted model components。**为什么做：** 恢复真正 8h hourly Stage88 candidate。**改了什么：** 新 isolated options/loader/smoke bundle，强制 dt=8、hourly flags、original-hourly demand 与 CAP200 table。**新增能力：** 120.12 kg capacity preflight 和 current model navigation。**结果：** smoke 证明模型入口正确；没有训练/checkpoint/OOS。**后续：** Stage89G。**状态：** `CURRENT`（模型入口）。

### Stage89G run-001 failures

**基于：** Stage89F model。**为什么做：** 首次 formal 10-iteration + loc1/4/7×10k OOS。**改了什么：** 新 monolithic runner。**新增能力：** fresh training/final checkpoint/OOS 目标。**结果：** 一个 run 因 training table 重复列名失败；另一个训练和 checkpoint 写出后在同进程 `load` 内存不足。**后续：** run-002 staged rewrite。**状态：** `FAILED`。

### Stage89G run-002

**基于：** Stage89F model + Stage85H-A checkpoint mechanism + Stage85R runner engineering。**为什么做：** 避免 run-001 schema 与 reload 内存回归，并完成 formal three-location OOS。**改了什么：** 新 phase orchestrator、fresh 10-iteration training、safe checkpoint、training exit、Stage89G reload adapter、SHA/cut/schema/parameter gate、三地独立 OOS、finalizer/QA。**新增能力：** Stage88 current candidate 的完整 formal workflow。**结果：** 审计只确认源码与静态门禁；发现外部 MATLAB 仍在运行，未读高频日志，故不提前宣告 OOS/final QA。**后续：** 完成且 QA PASS 后才可评估是否提升。**状态：** `CANDIDATE`。

### Stage89H

**基于：** Stage85R accepted single-initial-state runner + Stage85H-A clean-process checkpoint lifecycle + Stage89F current formal 8h model/input + Stage88 DRO CAP200 TerminalLOH。

**为什么做：** 验证不使用 Stage89G runner 的情况下，历史 accepted Stage85R workflow 能否以原 FA-MSP 的 one-known-initial-state 语义驱动当前模型，并检查 loc4、terminal-gap penalty=1000 时的满产和提前库存行为。上一轮 multiloc 要求与 Stage85R 单 `params.k_init` Stage1 cut 语义冲突；本次通过实验设计修正消除冲突，不修改 backward algorithm。

**改了什么：** 新增 Stage85R-derived thin launcher/orchestrator；当前 input 改接 Stage89F/Stage88；机械设置 `params.k_init=81`（loc4）；terminal-gap penalty只改为1000；fresh 10 iterations；Stage85R-style seed 20260817 的 loc4 10000-path OOS；独立结果路径、source manifest和reporting。

**没有改什么：** `forward_pass_h2`、`backward_pass_h2`、cut formula/update、Stage1 single-initial-state cut semantics、Stage2-6 logic、四库存 state、hourly stage solve和OOS path evaluation mathematics均未修改；没有 multi-location Stage1 cuts，没有读取历史 checkpoint。

**新增能力：** 把 Stage85R runner mother、Stage85H-A lifecycle和Stage89F/Stage88 current input组合成可核验的single-loc candidate；checkpoint save/SHA/reload分段计时并冻结实际源码字节。

**结果：** run-003全部QA通过。Stage1=`120.12 kg`，Sites1-4=`[46.8,31.2,18.72,23.4] kg`，100% utilization；Stage1/2/3 mean end inventory=`247.747481/288.280075/299.423409 kg`，early buildup=`CLEAR`。loc4 OOS mean total cost=`68445.650352 yuan`，mean ordinary shortage=`6.140345 kg`，mean terminal gap=`6.351063 kg`；terminal-gap component占mean cost=`9.279%`。10 iterations不构成收敛或最终penalty选择。

**后续：** 在同一single-loc4语义下分别补 penalty=1500 和2000 paired baselines，再决定候选penalty的更长训练。

**当前状态：** `CANDIDATE`。

### D01：W 失电严重度与 IEEE33 理想重构诊断

**基于：** Stage87C-A exact failure realization、Stage88 CAP200 SAA/DRO TerminalLOH 与 Stage89A current W index。**为什么做：** 把物理失电、灾害氢需求 `D` 和 TerminalLOH `T` 分层，判断 a5/a6 的高 `T` 是否来自实际平均需求，并估计当前 IEEE33 五条 normally-open ties 的潜在价值。**改了什么：** 仅增加 Python 离线后处理、CSV、图与来源清单；未重跑或修改 W bank、TerminalLOH、MATLAB、Gurobi、training、OOS。**结果：** a3-a6 mean lost load=`2.049/10.231/25.697/44.424%`，mean D=`12.457/62.200/156.230/270.082 kg`；a5/a6 DRO T=`562.891/641.539 kg`，分别为 mean D 的 `3.60x/2.38x`，主要解释为 terminal reserve redundancy。理想 tie-line connectivity 上界令 a5/a6 mean D 降低 `33.934%/25.918%`，但不包含潮流、电压、热限、开关时间、tie fragility 或抢修约束。

**当前状态：** `DIAGNOSTIC_ONLY`；只作为 current W 的解释证据，不替代 Stage88/89A 主线，也不是工程重构方案。

### D02：五点 hazard exposure + 理想重构 + 定向关键线加固 preview

**基于：** Stage87C-A frozen a3-a6 bank、D01 connectivity-only reconfiguration 与 Stage89A current W index。**为什么做：** 判断 W1/W2/W3 之间的风峰是否漏检，并分开评估 1-2/2-3 强加固和 3-4/4-5/5-6 追加中等加固的极端尾部价值。**改了什么：** 只增加独立 Python paired postprocessor；M12/M23 使用 endpoint center 与实际 sampled Vmax 的 midpoint，重新计算 asset local wind；同一 trajectory/line 复用正式 MT19937 resistance threshold。M12/M23 只更新持久故障，不各乘 1h；D 仍为 W1/W2/W3 三个 1h slice。道路保持三点。

**结果：** 28 states、420000 trajectories 的正式故障位 exact replay mismatch=`0`。B2 vs B1 令 a5/a6 mean D 增加 `7.831%/4.162%`，q95/q99 D 不变，full blackout 增加 `0.532/0.849 pp`。G1 vs B2 令 a5/a6 mean D 降低 `28.352%/23.645%`、q95 D 降低 `28.400%/7.537%`、full blackout 降低 `7.239/13.560 pp`；`STRONG_HARDENING_1_2_2_3_VALUE=HIGH`。G2 vs G1 的 q95 D 仅再降 `6.890%/2.620%`，full blackout 不变；按 a5/a6 保守规则，`ADDITIONAL_MODERATE_HARDENING_3_4_4_5_5_6_VALUE=LOW`。1-2 对所有 full-blackout observation 的 counterfactual attributable share 为 `100%`，仍是 extreme tail 主来源。

**没有改什么：** 没有 W bank/TerminalLOH/SAA/DRO/FA-MSP/MATLAB/Gurobi/OOS 重算；没有 road midpoint stochastic extension；+10/+5 m/s 只是 mechanism sensitivity，不是工程 retrofit 保证。

**当前状态：** `METHOD_PREVIEW / DIAGNOSTIC_ONLY`；建议正式 W 升级前先明确 road midpoint semantics，并把 tie fragility/电气可行性作为后续独立层。

### D03：基于拓扑的 H2 岛候选诊断

**基于：** D02 G1 五点候选的冻结 a3-a6 轨迹、D01 的 IEEE33 五条 normally-open ties、Stage79/80 冻结的 synthetic benchmark 站点母线映射。

**为什么做：** 判断故障线删除、tie binary switching 和严格辐射状重构后，原始失电节点中有多少回到 source component、进入含 H2 站的非源 component，或仍位于 black component。

**改了什么：** 只新增静态 Python 后处理与结果表。每个失败掩码保留未故障常闭支路，按 MAT tie 顺序执行 Kruskal branch addition，仅当两个端点属于不同分量时闭合 tie；该固定顺序记录一个等价最大生成森林。没有修改或重跑 W、D/A/C、TerminalLOH、Stage88、FA-MSP、SAA/DRO 或 OOS。

**结果：** a3-a6 共 1260000 个 topology observations 无损压缩为 173520 个 `(intensity,failure_mask)` 场景；全部通过无 cycle、`active_edges=33-islands` 与 source-connected node set maximal 检查。按重构前原始失电节点的 D 权重，`H2_ISLAND_CANDIDATE` 占比为 `20.740/34.222/39.474/41.947%`，a5/a6 `BLACK_ISLAND` 为 `18.419/25.107%`。

**解释边界：** `H2_SUPPORTED_ISLAND` 只表示 component 含 Site1-4 的 benchmark bus，不表示已经通电。当前没有 FC dispatch、H2-to-electric balance、库存扣减、grid-forming/black-start、电压或热限；因此结果支持未来加入该语义，但不能直接减少 D 或宣称负荷已恢复。

**当前状态：** `DIAGNOSTIC_ONLY`；`RECOMMEND_ADD_H2_ISLAND_SEMANTICS=YES` 是对未来建模优先级的建议，不是对当前服务能力的接受。

### D04：Topology-based H2 双通道最小模型冻结

**基于：** D03 的确定性辐射状重构与 H2 站点分量、D02 G1 冻结故障身份、Stage88 current H2 road A/C 与 DRO CAP200 `T`、候选 MAT 的 `fc_cap_kw/eta_FC/LHV`。

**为什么做：** D03 只能识别“含 H2 站的非源分量”，尚不能说明负荷如何被服务、燃料电池每切片能服务多少、以及电气/道路两通道如何避免重复消费同一份 H2 库存。

**改了什么：** 仅在隔离 Python 诊断中定义重构后的 `D_res`、同分量 `A_elec`、`fc_cap_kw*1h/(eta_FC*LHV)` 静态上限，以及 `sum(y_elec+y_road)<=T_i`。从 a3-a6/loc4 的 180000 个真实观测确定性选择 9 个身份，评估 T0/Tcurrent/Tlarge 与 R/ER 共 54 个连续 LP。

**结果：** 7/7 单元测试 PASS；27/27 所选切片拓扑径向且 source-maximal；FC 最大利用率为 1；共享库存最大超额为 0；`A_elec=0` 时与 road-only 最大差 `8.88e-15 kg`；14 行出现正 electrical service，6 个 scenario/T 组合出现严格 ER shortage 改善。

**边界：** 无 grid-forming、black-start、OPF、电压、无功、热限、动态 FC、制氢或车辆调度；Tlarge 只是非绑定单调性测试；正式 D/A/C、TerminalLOH、W、Stage88/89 与 FA-MSP 均未修改或重跑。

**当前状态：** `METHOD_PREVIEW / DIAGNOSTIC_ONLY`；不是 CURRENT W，也不是 ACCEPTED TERMINALLOH。

### Stage89I：双通道 W 支持集扩张与计算量审计

**基于：** D04 冻结的 `D_res/A_elec/shared-T/static-FC` 语义、D03 确定性径向重构、D02 G1 冻结 threshold replay，以及 Stage88 正式 D/Aroad/C bank、exact grouping source 与 current solver schema。

**为什么做：** D04 证明机制可表达，但没有回答从 `(D,Aroad,C)` 改为 `(Dres,Aroad,Aelec,C)` 后 exact support、压缩率、LP 结构、Pearson DRO support/probability vector 和存储规模是否失控。

**改了什么：** 只新增隔离 Python 静态后处理。对 35×15000 个冻结 path 全量重放 G1，按唯一 failure mask 缓存 160862 个 topology result，并按当前 MATLAB 字段顺序、数据类型与 raw-byte equality 分别统计 OLD/NEW；无 rounding、tolerance、quantization、clustering 或 scenario reduction。run-001 因本机旧 Matplotlib 绘图参数不兼容在结论文件生成前失败并保留，run-002 只加兼容包装后完整重跑。

**结果：** 35 个 OLD count 全部逐 state 等于 Stage88 manifest。OLD/NEW 总支持为 `457414/457431`，仅增加 17；state multiplier median/q90/max 为 `1/1.000040/1.000868`，a2-a5 聚合倍率均为 1，a6 为 `1.000162`。正向增长来源按披露的可加分解以 `A_ELEC` 为主。DRO support multiplier 为 `1.000037`；静态 SAA-equivalent 变量因 `D_res` 减少而降至 `0.576829x`，约束因 12×G FC caps 增至 `1.126051x`，故保守 projected size multiplier 为 `1.126051`。风险为 `LOW`，继续 exact grouping 与进入 Stage89J 隔离 formal candidate construction 均建议 `YES`。

**当前状态：** `DIAGNOSTIC_ONLY / METHOD_PREVIEW`；`NOT CURRENT_W_MAINLINE`、`NOT ACCEPTED_TERMINALLOH`、`NOT FORMAL_W_CANDIDATE`。没有正式 bank、SAA/DRO/TerminalLOH、FA-MSP 或 OOS 运行。

### Stage89J：正式 topology-based H2 双通道 W candidate bank

**基于：** Stage89I 的 457431 support 门禁、D04 的 `Dres/Aelec/static-FC` 语义、D03 的确定性径向重构、D02 G1 frozen failure replay，以及 Stage88 正式三点 `Aroad/C` bank。

**为什么做：** Stage89I 只证明 support expansion 可控，没有生成 Stage89K 能读取的正式 grouped scenario bank。

**改了什么：** 在隔离目录先全量重计 35×15000 frozen draws，逐 state 和总 support 全部匹配后才写出 35 个 MATLAB-readable MAT。exact signature 固定为 `(Dres,Aroad,Aelec,C)`；representative 为首次 frozen path，`q_g=multiplicity/15000`。FC capacity 仅作为 site-level 静态 metadata，不进入 signature。

**结果：** 525000 draws、457431 exact groups、160862 cached topologies；bank 本体 `1104251473` bytes。所有 source SHA、B2 zero-mismatch replay、G1 failure identity、radial/source/component、Dres/Aelec、multiplicity 与 machine-precision q 门禁 PASS。a3-a6 H2 island candidate D share 机械复现为 `20.740/34.222/39.474/41.947%`；该指标不是 restored-load share。

**当前状态：** `FORMAL_W_CANDIDATE`；明确 `NOT CURRENT_W_MAINLINE`、`NOT ACCEPTED_TERMINALLOH`、`NOT MSP-ACCEPTED`。未运行 SAA/DRO、TerminalLOH、FA-MSP 或 OOS；建议下一阶段为 Stage89K。

### Stage89K：双通道 W candidate 的正式 TerminalLOH SAA / Pearson DRO

**基于：** Stage89J 的 35 个 frozen `(Dres,Aroad,Aelec,C)` grouped banks、D04 的 shared-T/static-FC 连续 LP 语义，以及 Stage88 CAP200 SAA/Pearson eta=0.03 正式经济、概率、master/decomposition 与 solver tolerance。

**为什么做：** Stage89J 只建立了 formal W candidate bank，没有求该 bank 对应的 TerminalLOH 决策，也没有与 Stage88 当前 35-state tables 做正式逐 state 比较。

**改了什么：** 只把 Stage88 recourse 的 `D/Aroad/C` 升级为分离的 road/electrical service channels。两通道共同消耗同一 `T_i`，electrical channel 逐 site/slice 受 Stage89J 静态 FC kg cap 限制，road `C` 仍只用于固定最优 T 后的二级 service-impedance tie-break。未改变 `c_H2=32.5213675213675`、`M_H2=1283.205`、tank cap `[300,200,100,200]`、`q_g`、eta、Pearson 定义、Threads/tolerances 或 gap gates；没有新增 binary/nonlinear 结构。

**结果：** run-001 因 post-solve Pandas 字段序列化错误在首个 smoke 后停止并保留；run-002 从 35-bank SHA/schema QA 和 6-case smoke 重新开始。run-002 的 35 SAA + 35 DRO 全部 OPTIMAL，inventory/FC/q/p/Pearson/objective gates 全部 PASS。Stage88 到 Stage89K 的全 state mean T_total 变化为：SAA `344.707 -> 237.924 kg`（`-30.978%`），DRO `382.035 -> 277.211 kg`（`-27.438%`）。a3/a4/a5/a6 DRO mean 变化分别为 `-58.806/-33.503/-20.792/-16.182%`。70 个 mode-state 诊断的平均 q-weighted road/electrical/shortage 为 `37.300/9.272/7.084 kg`，且观测到 FC-cap binding。

**解释边界：** Stage88 到 Stage89K 同时包含 five-point grid exposure、G1、radial reconstruction、Dres 与 Aelec，因此只报告 `FULL CANDIDATE EFFECT`；没有运行 ablation、FA-MSP 或 OOS。

**当前状态：** `FORMAL_TERMINALLOH_CANDIDATE`；明确 `NOT CURRENT_TERMINALLOH`、`NOT CURRENT_W_MAINLINE`、`NOT MSP-ACCEPTED`。Stage88 仍是 current TerminalLOH；建议下一阶段为 Stage89L adoption / mechanism review。

### Stage89L：H2 electrical-island 严格增量消融与采用审查

**基于：** Stage89J frozen grouped bank、Stage89K accepted runner/results，以及 Stage88/89K 完全冻结的 CAP200、经济、q、Pearson eta=0.03、shared-T 与 solver tolerance。

**为什么做：** Stage88 到 Stage89K 同时改变 five-point exposure、G1、radial reconstruction、Dres 和 electrical channel，不能把全量下降归因于 H2 island。

**改了什么：** Case B 只在 Stage89K 建模入口把 `Aelec` 换为同形状全零，其他输入和求解函数不变；Case C 只读 Stage89K run-002，不重复求解。road-only smoke 覆盖 a3/a5/a6 的 SAA+DRO，随后完成 35 SAA + 35 DRO checkpoint/resume formal cases。

**结果：** Case B 70/70 OPTIMAL；inventory、demand balance、q/p、Pearson、gap、nonnegative 与 no-electrical-service 全部 PASS。dual-minus-road-only mean T_total 为 SAA `235.950296 -> 237.923792 kg`（`+0.836403%`），DRO `274.804682 -> 277.210943 kg`（`+0.875626%`）。a3/a4/a5/a6 DRO 变化为 `+2.551228/+2.267563/+1.164791/-0.426636%`。SAA/DRO 平均 road service 分别减少 `7.638841/7.811263 kg`，electrical service增加 `9.186866/9.357689 kg`，shortage 分别减少 `1.548025/1.546426 kg`。Site3 增储、Site4 减储最明显，FC binding 仍被观测。

**解释与采用：** Stage88-to-Case-B 的 SAA/DRO `-31.550517/-28.068109%` 只作含 five-point+G1 等混杂的 main-grid-reconfiguration 背景。严格 Case-B-to-C 结论为 `H2_ISLAND_INCREMENTAL_EFFECT=MIXED`、`H2_ISLAND_MECHANISM_VALUE=MODERATE`。`RECOMMEND_ADOPT_STAGE89J_89K=YES` 只表示建议进入 Stage89M formal adoption + FA-MSP retraining preparation；本阶段未运行 FA-MSP/OOS，也不提升任何 current/accepted 标记。

**当前状态：** `FORMAL_MECHANISM_ABLATION`；`NOT CURRENT_TERMINALLOH`、`NOT CURRENT_W_MAINLINE`、`NOT MSP-ACCEPTED`。

## Git 与文档状态说明

当前 Git HEAD 只到 Stage84C (`db532c4`)；Stage85+、current W bundle、Stage89F/G runner 位于 dirty/untracked 工作树。所有这些节点的“accepted/current”来自 result README、bundle manifest、launcher chain 与 `codex_rule/log.md`，并不等同“已提交”。Stage89G frozen-commit 门禁无法冻结 untracked runner 字节，是明确的 `DOCUMENTATION_CODE_MISMATCH / REPRODUCIBILITY_GAP`。


### Stage89M：Stage89J/K 正式采用、单一 bundle 与正确 8h integration

**基于：** Stage89J accepted W candidate、Stage89K accepted TerminalLOH candidate、Stage89L adoption evidence、Stage89F resolved 8h model；Stage85R/Stage85H-A 只作为未来 runner/checkpoint engineering lineage。

**改了什么：** 将 Stage89J 提升为 CURRENT/ADOPTED W，将 Stage89K 提升为 CURRENT/ADOPTED TerminalLOH；Stage89L 保持 FORMAL_MECHANISM_ABLATION；Stage88 保留为 superseded historical predecessor。建立唯一 `current_w_mainline_stage89` 轻量 bundle、严格 Stage89K hash/version/capacity loader 和只读 integration regression。

**结果：** J/K/L prerequisite、35 个大 bank SHA、SAA/DRO 35-state mapping、Site4 200 kg tank/150 kW Pmax、未缩放初始库存全部 PASS。Stage1–6 各有 8 个 hourly periods，IEEE33/P_EL/original demand/production/inventory/HTT/PV active，Stage7 analytic、Stage8 absorbing；理论产能 120.12 kg，legacy 90.09 未触发。Stage7 value/subgradient、backward terminal cut、forward terminal evaluation 与五个 negative gates PASS。

**边界：** Stage88→Stage89K 仍是 FULL CANDIDATE EFFECT，不是 H2 island-only effect。未训练、未 OOS、未建 checkpoint、未使用 multi-location adaptation、未改 forward/backward/cut mathematics。状态 `FORMAL_ADOPTION_AND_INTEGRATION / PASS`，ready for Stage89N single-loc4 fresh correct-8h training。

### Stage89N：adopted Stage89K single-loc4 fresh 8h retraining

**固定语义：** Stage85R mother runner、Stage85H-A clean lifecycle、Stage89F correct `6×8h`、Stage89K DRO eta=0.03、loc4、ordinary shortage 200、terminal gap 1000、seed 20260513、zero cuts、10 iterations；OOS 严格复用 Stage89H accepted seed 20260817 的 10000 条路径。

**结果：** Stage1 `120.12 -> 109.98 kg`（`-8.4416%`），站点变化为 `[0,-7.8,-2.34,0] kg`；Stage1/2/3 mean ending inventory 分别下降 `10.14/95.848/120.297 kg`。Stage2+3 production 未上移而是合计下降 `122.468 kg`，所以机制为 `LEVEL_REDUCTION`，不是 wait-and-see temporal shift。mean ordinary shortage `6.1403 -> 1.5418 kg`，mean terminal gap `6.3511 -> 5.5830 kg`，mean HTT `24.8328 -> 22.5113 kg`。综合判断 `EARLY_COMMITMENT_EFFECT=MODERATELY_REDUCED`。

**工程边界：** run-001 为 adopted-audit 字段名 preflight 失败；run-002 在 path 6700 原生 heap corruption；run-003 完成全部 10000 OOS 和 `OOS_COMPLETE` 后在 MATLAB 退出阶段复现 `0xc0000374`。最终只做 external SHA 与 Python report-only recovery，没有再次加载 checkpoint。状态 `FORMAL_CONTROLLED_RETRAINING_DIAGNOSTIC / PASS`，`FULLY_CONVERGED=NO`，不是最终策略。
