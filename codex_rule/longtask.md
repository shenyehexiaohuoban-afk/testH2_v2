# longtask.md

## 0. 文件用途

本文件记录项目长期目标、已实现阶段、当前阶段状态、架构快照、建模口径、开放问题和阶段变化。

本文件不是本次任务文件。  
本次具体任务由用户在 Codex 当前聊天框中给出。

本文件主要由用户更新。  
Codex 默认不要直接修改本文件。  
如果 Codex 认为本文件需要更新，应在最终回复中提出建议，等待用户确认。

---

## 1. 长期研究目标

当前长期目标：

构建台风不确定性下制氢-储氢-HTT-MFCV 支援建模框架。

当前重点不是完整灾后 MFCV 路径优化，而是临灾阶段四氢站 LOH 预布局。

长期路线大致为：

1. 复现原论文 FA-MSP / SDDP 框架；
2. 迁移到 H2 临灾 LOH 预布局；
3. 稳定主 MSP `node_load` / legacy TerminalLOH baseline；
4. 完成 `wind_mc / roadSoft / RiskCap-Mean` 等离线 TerminalLOH 预览和历史距离型 WDRO 诊断；
5. 转向 finite-support SAA 与 flat Pearson chi-square probability DRO，建立统一经济口径和 35 状态 TerminalLOH 表；
6. 通过独立 options/launcher 将 SAA 和 eta=0.03 两张表最小接入同一 H2 FA-MSP 主链；
7. 在冻结 10000 条共样本 OOS 上完成一小时固定预算 A/B、逐路径性能和机制审计；
8. 后续根据明确研究问题决定是否开展正式收敛训练、针对性 cut/训练覆盖测试或主入口默认模式调整；
9. 更长期再考虑灾后响应 recourse、配电网运行约束、MFCV / 路径 / 修复 / 滚动优化等扩展。

---

## 2. 已实现阶段

### 2.1 原论文 FA-MSP 复现 baseline 阶段

已实现内容：

- 基于原论文 random case 复现 FA-MSP / SDDP 式训练流程；
- 完成 MATLAB/Gurobi 版本主体转换；
- 保留 forward pass、backward pass、Benders cuts、OOS evaluation；
- 输出作者兼容结果、可读结果、OOS path costs 和 workspace；
- 明确 OOS mean / CI 用于 policy 比较，LB 只作为训练内部指标。

当前意义：

该阶段作为算法正确性和复现实验 baseline，不应被 H2 应用开发破坏式修改。

---

### 2.2 H2 主 MSP 初始迁移阶段

已实现内容：

- 将原 FA-MSP 结构迁移到四氢站临灾 LOH 预布局问题；
- 保留主 MSP 训练和 OOS 评估框架；
- 将四个氢站 LOH 作为主要跨期状态；
- 引入制氢、储氢、正常供氢、HTT 调拨和 TerminalLOH 检查等 H2 应用元素。

当前意义：

该阶段形成 H2 MSP 主模型骨架。

---

### 2.3 lf=7 / lf=8 口径统一阶段

已实现内容：

- 明确 `lf=1~6` 是普通临灾准备阶段；
- 明确 `lf=7` 是 TerminalLOH demand/check stage；
- 明确 `lf=8` 是零成本吸收状态；
- 普通阶段不再加入每期 TargetLOH 约束；
- TerminalLOH 只在 `lf=7` 检查，不作为普通阶段库存出库量。

当前意义：

该阶段统一了论文叙述、模型逻辑和程序逻辑。

---

### 2.4 H2 主版本 node_load 口径阶段

已实现内容：

- 主 MSP 默认 TerminalLOH 使用 `node_load + impact_weight + A_site_node`；
- 使用节点总有功负荷折算节点需氢量；
- 主程序仍保持稳定 baseline 口径；
- `wind_mc / roadSoft / RiskCap-Mean` 尚未接入主 MSP。

当前意义：

该阶段是当前 H2 MSP 主版本 baseline。

---

### 2.5 配置层与对照实验层整理阶段

已实现内容：

- `main_msp_h2_near.m` 作为日常主入口；
- `h2_default_options.m` 统一默认参数；
- `run_h2_with_options.m` 用于按 opts 运行一次实验；
- `run_h2_ablation_suite.m` 用于对照实验。

当前意义：

该阶段把日常运行、单次实验和对照实验分层，减少主入口混乱。

---

### 2.6 wind_mc / roadSoft 离线预览阶段

已实现内容：

- 新增 `generate_terminal_loh_wind_mc_preview.m` 作为 TerminalLOH 物理化离线预览入口；
- 电网侧通过风场、线路故障概率、MC 断线、节点停电概率和失负荷生成节点需氢量；
- 路网侧通过道路拓扑、道路边风风险、可达性和通行距离描述氢站到电网节点的服务条件；
- roadSoft 使用路网可达性和现场重算的基础服务距离做预部署软分配；
- RiskCap-Mean 使用联合场景均值、容量约束、可达性和服务风险成本做状态级离线分配；
- 输出 CSV、MAT 和中文标注 figures；
- 当前不训练 MSP，不调用 forward/backward/cut，不覆盖 `params.TerminalLOH`。

当前意义：

该阶段用于验证更物理化 TerminalLOH 的候选生成方式，仍是独立离线模块，尚未接入主 MSP。

---

### 2.7 road / windMC 坐标统一阶段

已实现内容：

- `data/yuanqi/stage1_road_edges.csv` 提供道路拓扑；
- `data/yuanqi/stage1_site_nodes.csv` 提供氢站道路锚点 `site_id / grid_node`；
- 电网节点和道路节点坐标统一使用 `windMC.layout.nodes`；
- 氢站坐标统一使用 `windMC.layout.sites`；
- road edge midpoint、road wind speed、road close probability 和 road figures 使用统一的 `windMC.layout` 坐标；
- site-node 基础服务距离由程序基于当前道路拓扑、统一节点坐标和氢站锚点现场重算。

当前意义：

该阶段统一了离线预览中的电网、道路、氢站和台风风场坐标口径，并使 roadSoft / RiskCap-Mean 的基础服务距离来自同一套现场重算最短路。

---

### 2.8 probability DRO 主线建立阶段

已实现内容：

- 历史 Wasserstein ground-cost、DAC/Ctilde、Dscale/Cscale 路线完成审计并停止继续调参；
- 建立 finite-support SAA 与 flat Pearson chi-square probability DRO；
- 概率扰动直接作用于有限经验场景概率，不再依赖场景对距离；
- 建立 R=15000 的分解求解、最坏概率、强对偶、LB/UB 和固定决策复核机制；
- `terminalLoh_wdro/docs/PROBABILITY_DRO_MAINLINE_HANDOVER.md` 记录方法主线和历史边界。

当前意义：

当前 TerminalLOH 风险方法主线是 flat Pearson chi-square probability DRO。旧 Wasserstein 与距离调参代码继续保留作为历史证据，但不再作为当前两张正式查表的来源。

---

### 2.9 统一经济 TerminalLOH 与 eta 响应阶段

已实现内容：

- 在 state19 上统一制氢准备成本、VOLL 等效缺氢损失和 EENS 换算；
- 保持 `C*y` 仅为严格词典序二级 tie-break，不进入人民币一级目标；
- 完成 eta 网格 `[0,0.0003,0.001,0.003,0.01,0.03]` 的响应与饱和审计；
- 识别大部分场景原本无缺氢、可服务缺氢场景较少、道路/服务不可达形成物理平台等边界；
- eta=0.03 被保留为高保障比较候选，但 eta 未被统计意义正式冻结。

当前意义：

SAA 是统一经济参考，eta=0.03 是当前 35 状态 FA-MSP 对照使用的代表性高保障 Pearson chi-square 候选。不得写成 eta=0.03 唯一最优或已正式校准。

---

### 2.10 35 状态 SAA / eta=0.03 TerminalLOH 阶段

已实现内容：

- 35 个初始状态分别使用自己的 15000 条 nominal 三期记录；
- 完成 35 个 SAA 与 35 个 eta=0.03 独立优化，共 70 个隔离求解组合；
- 生成两张完整 35x4 TerminalLOH 查表；
- state19 reproduction、概率、强对偶、LB/UB、映射、EENS 和词典序审计全部通过；
- 文件名 token `eta003` 在当前 C6/FA-MSP 语义中明确表示 `eta=0.03`，不是 `0.003`。

正式查表：

- `results/task-002-stage2b-b3-smoke/53-35state-saa-vs-eta003-terminal-loh/run-024/terminal_loh_table_saa.csv`
- `results/task-002-stage2b-b3-smoke/53-35state-saa-vs-eta003-terminal-loh/run-024/terminal_loh_table_eta_003.csv`

当前意义：

这两张表是当前 SAA/DRO FA-MSP 实验的唯一正式 TerminalLOH lookup 来源。

---

### 2.11 SAA / eta=0.03 FA-MSP 接入与固定预算 A/B 阶段

已实现内容：

- 建立安全、输出隔离的原生 FA-MSP smoke 入口；
- 建立 `terminal_loh_mode='saa'|'chi2_eta003'` 和 `terminal_loh_lookup_file` 双表接口；
- 35 状态表被严格映射到 `params.TerminalLOH[4x336]` 的 35 个 `lf=7` 列；
- 双表均已验证进入 terminal value/subgradient、backward cuts 和后续 forward；
- 使用相同 seed、模型、参数、2000 元/kg TerminalLOH gap penalty 和冻结 10000x8 OOS 数据完成一小时固定预算 A/B。

重要状态：

- accepted policy source 是 `results/task-002-stage2b-b3-smoke/57-main-msp-converged-terminal-loh-ab/run-003/`；
- 尽管目录名含 `converged`，两套策略实际均由 3600 秒时间上限停止，`stop_flag=2`；
- SAA 完成 1113 次 forward 迭代，DRO 完成 1199 次；
- 当前不得把这两套策略称为正式收敛策略。

当前意义：

主算法未分叉。SAA 与 DRO 只在 TerminalLOH 表输入上不同，forward/backward/cut/eval 共用同一套核心代码。

---

### 2.12 共样本 OOS 与机制审计阶段

已实现内容：

- Step-05B-1 至 B7 完成 TerminalLOH gap penalty、目标兑现、必要新增库存、系统总量、信息逐步揭示、capacity gap 和 state19 训练证据审计；
- Step-05B-8 对 10000 条完全共样本 OOS 路径完成 SAA/DRO 逐路径配对；
- Step-05B-9 完成终端库存增量固定分档与累计覆盖统计；
- Step-05B-11 使用独立路径风险、SAA 基准压力和正式离线 state 风险完成库存增量关联审计；
- Step-05B-11A 对 6053 条共同 terminal-hit 路径完成 SAA/DRO own-target attainment 对称审计，并按实际 preparation-stage count 及固定 terminal state 检查 target、actual inventory 和逐站 terminal gap；
- 机制审计不修改策略、TerminalLOH、200/2000 或核心 FA-MSP。

当前主要结果：

- DRO 平均多制氢 `15.270633318 kg/path`，平均多 HTT `8.763033783 kg/path`，平均最终总库存增加 `15.514788166 kg/path`；
- 最终库存增加/不变/下降路径数为 `5600/4397/3`；
- 普通 shortage 改善/不变/恶化路径数为 `2/9718/280`；
- 去掉历史 terminal-gap penalty 后，平均 modeled operating cost 增加 `809.155643307 yuan/path`；
- `51.05%` 路径库存增加超过 10 kg，`40.12%` 超过 20 kg，`1.79%` 超过 50 kg，未出现超过 100 kg 的路径；
- 20–50 kg 高增量路径并未表现出更高的独立台风风险；实际准备/生产机会数与库存增量的 Spearman 相关为 `0.746`，而 `Delta TerminalLOH` 仅为 `-0.062`；
- SAA/DRO 全 terminal-hit 样本中 prep count 与 raw gap 的相关均较弱，但固定正 target terminal state 后，SAA `18/18`、DRO `19/19` 个可评价 state 均为负向 prep-gap 关联；TerminalLOH 向实际库存的转化对准备机会具有共同依赖性，不能简单归因于 Pearson-DRO；
- 结果应解释为“部分路径明显提高、较大一部分基本不变”，不能只报告总体平均或高增量子集。

当前意义：

DRO 表现为更高储备、带有运行成本溢价且路径响应异质的策略。现有证据不支持宣称其在所有物理服务指标上全面优于 SAA，也不支持立即修改 200/2000。

---

## 3. 当前阶段定位

当前阶段：

**35 状态 SAA / eta=0.03 TerminalLOH 接入后的 H2 FA-MSP 共样本 OOS 解释与决策阶段。**

当前阶段目标：

1. 保留已验收的 35 状态 SAA 与 Pearson chi-square `eta=0.03` TerminalLOH 表及其机械映射；
2. 以相同的 10000 条冻结 OOS 路径解释两套一小时固定预算策略的库存、制氢、HTT、shortage 和运行成本差异；
3. 区分 TerminalLOH 目标差异、系统总量能力、信息逐步揭示、cut 价值近似和固定训练预算的作用；
4. 决定是否需要正式收敛训练或只针对 state19 等节点做有仪表的延长训练；
5. 保持日常入口 `main_msp_h2_near.m` 的 legacy 默认不变，SAA/DRO 仍通过独立 launcher/options 显式切换；
6. 为论文形成可复核、不过度外推的共同样本 OOS 结论。

当前阶段不做：

1. 不把 Stage-57 `run-003` 写成正式收敛结果；两套策略均由 3600 秒时间上限停止，`stop_flag=2`；
2. 不修改普通 shortage 的 200 元/kg 或 TerminalLOH gap 的 2000 元/kg 历史惩罚；
3. 不把 `eta=0.03` 宣称为统计意义已校准、唯一最优或正式冻结半径；
4. 不把 lookup 模式自动改为日常主入口默认值；
5. 不恢复 Wasserstein、DAC/Ctilde、Dscale/Cscale 为当前主线；
6. 未经单独授权，不扩展 CVaR、MFCV、真实车辆路径、道路修复、配电网潮流或灾后 recourse；
7. 不把事后完全信息诊断 LP 的可行性等同于原 FA-MSP 在非预见性约束下应当实现；
8. 不因局部异常节点直接宣布 Pearson DRO 或整个 cut 机制成功或失败。

---

## 4. 当前程序架构快照

### 4.1 日常入口与实验 launcher

- 日常原生入口：`main_msp_h2_near.m`；
- 默认 options：`h2_default_options.m`，其中 `terminal_loh_mode='legacy'`、seed=`20260513`；
- 统一执行包装：`run_h2_with_options.m`；
- 安全 smoke：`run_main_msp_h2_native_smoke.m`；
- accepted 一小时固定预算 A/B：`run_main_msp_h2_fixed_budget_ab.m`；
- 正式收敛 launcher：`run_main_msp_h2_converged_ab.m`，但当前没有 accepted 的正式收敛 A/B；
- `run_h2_ablation_suite.m` 是对照入口，不是日常主入口。

日常 `main_msp_h2_near.m` 没有自动切到 SAA/DRO lookup；它仍使用 `terminal_impact_template.csv -> build_terminal_loh_h2`。实验 launcher 只在 options 层设置 `terminal_loh_mode` 和 lookup 文件，继续调用同一正式主链。

### 4.2 H2 FA-MSP 正式调用链

```text
main_msp_h2_near
  -> h2_default_options
  -> run_h2_with_options
       -> load_data_h2_near
       -> fa_h2/define_models_h2
       -> fa_h2/train_models_h2
            -> fa_h2/forward_pass_h2
            -> fa_h2/backward_pass_h2
                 -> fa_h2/add_cut_h2
       -> fa_h2/eval_h2
```

阶段模型公共组件包括：

- `fa_h2/build_stage_model_h2.m`
- `fa_h2/update_rhs_h2.m`
- `fa_h2/solve_stage_model_h2.m`
- `fa_h2/forward_pass_h2.m`
- `fa_h2/backward_pass_h2.m`
- `fa_h2/add_cut_h2.m`
- `fa_h2/train_models_h2.m`
- `fa_h2/eval_h2.m`

SAA 与 DRO 不存在两套复制的 forward/backward/cut/model/eval 代码。

### 4.3 TerminalLOH 接口层

- legacy 构造：`fa_h2/fuzhu/build_terminal_loh_h2.m`；
- 35×4 lookup 到 4×336 映射：`fa_h2/fuzhu/load_terminal_loh_lookup_h2.m`；
- `lf=7` forward/eval 检查：`fa_h2/fuzhu/eval_terminal_loh_h2.m`；
- backward 终端值和次梯度：`fa_h2/fuzhu/terminal_value_and_subgradient_h2.m`。

两张正式 lookup 表位于：

- `results/task-002-stage2b-b3-smoke/53-35state-saa-vs-eta003-terminal-loh/run-024/terminal_loh_table_saa.csv`
- `results/task-002-stage2b-b3-smoke/53-35state-saa-vs-eta003-terminal-loh/run-024/terminal_loh_table_eta_003.csv`

`load_data_h2_near.m` 负责组装 Markov/H2 参数并将最终 4×336 数组写入 `params.TerminalLOH`。

### 4.4 当前输入、OOS 与离线 probability-DRO 层

- 主 H2/MSP 输入：`data/yuanqi/near_stage_msp_input.mat`；
- daily legacy 表：`data/yuanqi/terminal_impact_template.csv`；
- accepted A/B 冻结共同 OOS：`output_h2/details/h2_OOS.csv`，10000×8 路径；
- 离线 TerminalLOH 研究模块：`terminalLoh_wdro/`；
- 当前 probability-DRO 交接：`terminalLoh_wdro/docs/PROBABILITY_DRO_MAINLINE_HANDOVER.md`；
- 当前有限支撑求解主线：`terminalLoh_wdro/src/solve_terminal_loh_saa_c6_h2.m` 与 `solve_terminal_loh_flat_chi2_*`；
- 35 状态表生产：`terminalLoh_wdro/src/run_step04CC6_*`；
- Step-05B-1 至 B11A 为读取既有策略/OOS 的机制、分布、独立风险特征与对称 TerminalLOH attainment 审计。

### 4.5 当前结果阶段地图

- Stage 53 `run-024`：35 状态正式 SAA / eta=0.03 TerminalLOH；
- Stage 55 `run-001`：原生安全 smoke；
- Stage 56 `run-001`：双 lookup 映射和 cut 传播 smoke；
- Stage 57 `run-003`：一小时固定预算 SAA/DRO A/B 策略和共同 OOS，不是正式收敛结果；
- Stage 58–64：Step-05B-1 至 B7 机制、兑现、能力、信息和训练充分性审计；
- Stage 65 `run-002`：Step-05B-8 的 10000 条 OOS 逐路径配对主结果；
- Stage 66 `run-001`：Step-05B-9 的终端库存增量分档与累计覆盖；
- Stage 67 `run-001`：当前项目架构、调用链、接口和结果索引。
- Stage 68 `run-004`：Step-05B-11 的 10000 条共样本库存增量与独立路径风险特征关联审计。
- Stage 69 `run-003`：Step-05B-11A 的 SAA/DRO 对称 TerminalLOH 实现性与准备机会审计。

### 4.6 本地存储、保护与 Git 归档边界

- `output_h2/` 保存原生 MSP/OOS/benchmark 等本地受保护内容；
- `terminalLoh_wdro/output/` 保存大型离线研究数据；
- `results/` 同时包含可提交轻量证据和按 `LARGE_FILE_MANIFEST.md` 留在本地的 MAT、workspace、raw/replay/process 子树；
- accepted、failed 和重跑 run 均原位保留，同一步重跑必须新建 `run-xxx`；
- 不执行 `reset`、`clean`、覆盖、移动或删除来整理这些目录；
- 只在用户明确授权且门禁通过后精确暂存本任务文件，Push 当前任务分支；不修改 `main`，不创建/合并 PR，不 force push。

完整任务导航以 `results/task-002-stage2b-b3-smoke/67-current-project-architecture-audit/run-001/` 为当前架构快照。

---

## 5. 当前建模口径

### 5.1 当前 MSP 跨期状态

当前 H2 MSP 的主要跨期状态是四个氢站的 LOH：

- `x = [x1, x2, x3, x4]`

当前 Benders cuts 主要关于四站库存 `x` 的未来价值。SAA 与 DRO 共享相同的物理模型、Markov 模型、forward/backward/cut/eval 代码；已验收 A/B 的模型输入差异仅为 TerminalLOH lookup 表。

---

### 5.2 lf=7 / lf=8 当前解释

当前解释：

- `lf=1~6`：普通临灾准备阶段；
- `lf=7`：TerminalLOH demand/check stage；
- `lf=8`：零成本吸收状态。

`lf=8` 不是新的物理决策阶段。

---

### 5.3 35 状态 lookup 与主 MSP 状态映射

两张正式表均为 35 行、四站目标列 `T1_kg` 至 `T4_kg`。映射严格为：

```text
state_id = (intensity - 2) * 7 + loc
k = ((a - 1) * 7 + (loc - 1)) * 8 + 7
```

其中 `a=intensity=2..6`、`loc=1..7`，只写入 35 个 `lf=7` 列；其他列保持零。站点顺序固定为 site1、site2、site3、site4。

### 5.4 TerminalLOH 值函数、次梯度与 cut

对 `lf=7` 状态 `k`：

```text
gap_i = max(0, TerminalLOH_i(k) - x_i)
V_k(x) = 2000 * sum_i gap_i
g_i = -2000,  当 x_i < TerminalLOH_i(k) - 1e-9
g_i = 0,      其他情况
```

`eval_terminal_loh_h2.m` 用同一 gap 口径评价 forward/OOS；`terminal_value_and_subgradient_h2.m` 将值和次梯度交给 `backward_pass_h2.m`，经 Markov 概率加权后由 `add_cut_h2.m` 写入未来价值 cut，并在后续 forward 中使用。TerminalLOH 是终端储备充足性检查，不是 `lf=7` 的实际库存出库。

### 5.5 200、2000 与 reported objective

- 200 元/kg：普通 H2 shortage 的当前有效惩罚；
- 2000 元/kg：`cost_reserve_shortage`，只惩罚 `lf=7` 的 TerminalLOH gap；
- 离线统一经济 TerminalLOH 中的 1283.205 元/kg 不进入当前主 MSP；
- 主 MSP reported objective 包含 2000×terminal gap，因此不能仅凭 reported objective 判断 SAA/DRO 的物理服务优劣；
- Step-05B-1 的去 terminal-gap 指标仅用于机制诊断，不是新的正式优化目标。

这两个惩罚当前冻结。现有机制审计没有给出立即修改 200/2000 的充分证据。

### 5.6 eta=0.03 与策略状态

- 文件名 `terminal_loh_table_eta_003.csv` 和 mode `chi2_eta003` 中的 `eta003` 明确表示 `eta=0.03`，不是 `0.003`；
- 证据来自 C6 README、CSV 的 `eta=0.03` 列及 loader 的 `expectedEta=0.03` 运行时断言；
- `eta=0.03` 是当前 Pearson chi-square 高保障对照候选，仍未统计校准或正式冻结；
- Stage-57 `run-003` 的 SAA/DRO 都是一小时固定预算策略，`stop_flag=2`，不是正式收敛策略；
- 两套策略的正式解释使用同一冻结 10000 条 OOS 路径做逐行配对。

### 5.7 系统能力、信息与 HTT 解释边界

- 事后完全信息诊断 LP 只证明给定整条已实现路径后，在现有物理约束下是否可重配；它不能证明非预见性 FA-MSP 在当时信息下必然应做到；
- 总库存足够不能抵消逐站 terminal gap，仍需逐站计算 `max(0,T_i-I_i)`；
- 当前 HTT 是阶段内进入库存平衡的站间调拨，不包含真实车辆位置和逐路段运输时间过程；
- 资源诊断统一使用连续利用率和接近容量上限的阶段比例，不使用“绑定率”混代平均利用率；
- 对总量可行但兑现不足的路径，应依次区分信息未揭示、库存价值/cut 近似、训练覆盖和固定预算，而不是预设为 2000 惩罚或 HTT 物理瓶颈。

### 5.8 当前主线与长期扩展边界

当前主线是有限支撑 SAA、Pearson chi-square probability DRO、35 状态 TerminalLOH、H2 FA-MSP 和共同样本 OOS。Wasserstein ground-cost、DAC/Ctilde、Dscale/Cscale、extreme-aware candidate、wind_mc/roadSoft/RiskCap-Mean 均保留为历史模块或早期预览，不是当前正式表源。

CVaR、终端灾后 recourse、MFCV/车辆路径/道路修复、灾后滚动优化、配电网潮流与电解槽电网耦合仍是独立中长期扩展，不因本阶段结果自动进入主 MSP。

---

## 6. 当前开放问题

当前开放问题记录的是“这个阶段还需要关注的问题”，不是长期固定规则。

1. 是否需要让 SAA 与 eta=0.03 都运行到正式原生收敛条件，还是一小时固定预算策略已足够支撑当前论文问题；
2. 若继续训练，是否只针对 state19 可行子集、`t=5,k=222,lf=6` 等候选节点增加访问/cut/边际价值仪表并延长预算；
3. 何时以及是否应让日常 `main_msp_h2_near.m` 显式暴露 lookup 模式；在决定前继续保持 legacy 默认；
4. 如何在论文中准确表述 DRO 的“部分路径明显增加终端库存、另一部分基本不变”、准备机会主导的路径异质性、运行成本溢价和普通 shortage 异质性；
5. `eta=0.03` 是否还需结合更多统计或决策标准继续校准，当前不能写成正式冻结；
6. 对剩余未兑现目标，如何进一步区分系统总能力不足、信息逐步揭示、局部 cut 近似和固定训练预算；
7. 根目录 README 是否需要补充当前入口、Stage-67 架构地图及 Stage-65/66 主结果导航；
8. wind_mc/roadSoft、Wasserstein/Dscale、灾后 recourse、CVaR、MFCV/路径/修复、配电网运行约束等保留为历史或中长期独立课题，不与当前解释任务混做。

---

## 7. 阶段变化记录

### 2026-05-28：当前阶段为 wind_mc / roadSoft / RiskCap-Mean 离线 TerminalLOH 预览稳定阶段

当前状态：

- 主 MSP 仍保持 `node_load + impact_weight + A_site_node`；
- `wind_mc / roadSoft / RiskCap-Mean` 仍是离线预览；
- roadSoft 和 RiskCap-Mean 尚未接入正式 MSP；
- 当前重点是验证坐标统一、服务距离重算、roadSoft 分配、RiskCap-Mean 分配、未覆盖量、服务风险和输出解释。

后续可能阶段：

- 阶段 2：开展更高样本规模的离线稳定性验证；
- 阶段 3：研究基于 `lf=7` 终端状态条件灾后场景的 TerminalLOH 生成机制；
- 阶段 4：在离线结果和生成口径稳定后讨论是否新增 `terminal_load_mode`；
- 阶段 5：小规模 MSP 接入验证和对照实验；
- 阶段 6：考虑风险规避、灾后响应 recourse、配电网运行约束、MFCV / 路径 / 修复 / 滚动优化等更长期扩展。

### 2026-08-11：当前阶段更新为 35 状态 Pearson chi-square TerminalLOH 接入后的 FA-MSP 共样本 OOS 解释阶段

当前状态：

- Stage 53 `run-024` 已验收 35 状态 SAA 与 eta=0.03 TerminalLOH 表；
- Stage 55/56 已验证输出隔离、lookup 映射和 `TerminalLOH -> backward -> cuts -> subsequent forward` 传播；
- Stage 57 `run-003` 保存两套一小时固定预算策略及共同 10000 条 OOS 评价，两者均为 `stop_flag=2`，不是正式收敛结果；
- Step-05B-1 至 B11 已完成 penalty、兑现率、required-extra、系统能力、信息逐步揭示、训练充分性、全状态能力、逐路径性能、库存增量分布和独立风险特征关联审计；
- Stage 65 `run-002`、Stage 66 `run-001` 与 Stage 68 `run-004` 是当前逐路径、库存分布和风险特征关联主结果；
- Stage 67 `run-001` 冻结当前仓库架构、真实调用链、TerminalLOH 接口和结果阶段地图；
- 日常 `main_msp_h2_near.m` 仍保持 legacy TerminalLOH 默认，SAA/DRO lookup 仅通过独立 launcher/options 显式接入；
- 历史 Wasserstein、DAC/Ctilde、Dscale/Cscale、extreme-aware、wind_mc/roadSoft/RiskCap-Mean 代码和结果继续保留，但不再代表当前研究主线。
