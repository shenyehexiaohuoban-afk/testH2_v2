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
3. 稳定主 MSP `node_load` 版本；
4. 稳定 `wind_mc / roadSoft / RiskCap-Mean` 离线 TerminalLOH 预览；
5. 研究基于 `lf=7` 终端状态条件灾后场景的 TerminalLOH 生成机制；
6. 在离线结果和生成口径稳定后，再讨论是否新增 `terminal_load_mode` 并小规模接入 MSP；
7. 后续再考虑风险规避、灾后响应 recourse、配电网运行约束、MFCV / 路径 / 修复 / 滚动优化等扩展。

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

## 3. 当前阶段定位

当前阶段：

**wind_mc / roadSoft / RiskCap-Mean 离线 TerminalLOH 预览稳定阶段。**

当前阶段目标：

1. 保持主 MSP `node_load` 版本稳定；
2. 不急于把 `wind_mc / roadSoft / RiskCap-Mean` 接入主 MSP；
3. 先验证离线 TerminalLOH 输出是否合理；
4. 重点检查坐标统一、总量守恒、空间分配、未覆盖量、服务风险和容量利用率；
5. 中期研究基于 `lf=7` 终端状态的条件灾后场景生成机制，增强 TerminalLOH 生成逻辑；
6. 如果离线结果和生成口径稳定，再讨论是否新增新的 `terminal_load_mode` 并小规模接入 MSP。

当前阶段不做：

1. 不做 CVaR-MSP；
2. 不做真实 MFCV 路径优化；
3. 不做车辆路径 MILP；
4. 不做电池 SOC；
5. 不做配电网潮流；
6. 不把 roadSoft 或 RiskCap-Mean 直接接入正式 MSP；
7. 不把阶段 LP 改成 MILP；
8. 不把 `lf>7` 灾后影响立即扩展为主 MSP 新阶段；
9. 不转向完整灾后运营调度模型。

---

## 4. 当前程序架构快照

### 4.1 主 MSP 入口层

- `main_msp_h2_near.m`：日常 H2 MSP 主入口。
- `h2_default_options.m`：默认参数。
- `run_h2_with_options.m`：单次实验包装。
- `run_h2_ablation_suite.m`：对照实验入口。

当前状态：

主 MSP 日常入口仍是 `main_msp_h2_near.m`。

---

### 4.2 H2 FA-MSP 主体层

- `fa_h2/build_stage_model_h2.m`
- `fa_h2/update_rhs_h2.m`
- `fa_h2/solve_stage_model_h2.m`
- `fa_h2/forward_pass_h2.m`
- `fa_h2/backward_pass_h2.m`
- `fa_h2/add_cut_h2.m`
- `fa_h2/train_models_h2.m`
- `fa_h2/eval_h2.m`

当前状态：

这些文件实现 H2 MSP 的阶段模型、forward/backward、cut、训练和 OOS 评估。

---

### 4.3 数据与参数层

- `load_data_h2_near.m`
- `data/yuanqi/near_stage_msp_input.mat`
- `data/yuanqi/near_stage_msp_README.txt`
- `data/yuanqi/stage1_road_edges.csv`
- `data/yuanqi/stage1_site_nodes.csv`

当前状态：

`load_data_h2_near.m` 负责主 MSP 参数构造。  
`stage1_road_edges.csv` 和 `stage1_site_nodes.csv` 主要服务离线 TerminalLOH 预览中的道路拓扑和氢站道路锚点。

---

### 4.4 wind_mc / roadSoft / RiskCap-Mean 离线预览层

- `generate_terminal_loh_wind_mc_preview.m`
- `fa_h2/fuzhu/terminalLoh_windmc/*.m`
- `fa_h2/fuzhu/terminalLoh_windmc/draw/*.m`

当前状态：

`generate_terminal_loh_wind_mc_preview.m` 是离线 TerminalLOH 预览入口。  
当前用于生成电网侧节点需氢量、roadSoft 分配、RiskCap-Mean 分配、CSV、MAT 和中文标注 figures，不接入主 MSP。

---

### 4.5 输出结构

离线预览输出目录：

- `output_h2/wind_terminal_loh_preview/`
- `output_h2/wind_terminal_loh_preview/elec_grid/`
- `output_h2/wind_terminal_loh_preview/road/`
- `output_h2/wind_terminal_loh_preview/riskcap_mean/`
- `output_h2/wind_terminal_loh_preview/figures/elec_grid/`
- `output_h2/wind_terminal_loh_preview/figures/road/`
- `output_h2/wind_terminal_loh_preview/figures/riskcap_mean/`

正式 MSP 输出目录：

- `output_h2/benchmark/`
- `output_h2/details/`

### 4.6 GitHub 任务分支与结果归档

当前协作结构：

- `main` 仅保存已验收稳定版本；开发在用户指定的 `task/...` 分支完成；
- Codex 默认不执行 Git 写操作，只有任务明确授权且审计全部通过后，才 Commit 和
  Push 当前任务分支；
- Codex 不修改 `main`，不创建或合并 PR，不删除分支，不 force push；
- 小型审计结果归档到 `results/task-xxx/step-xx/run-xxx/`；
- 大型结果保留在 `terminalLoh_wdro/output/`，Git 记录路径、行数、字节数和 SHA-256；
- 同一步重跑使用新 run 编号，旧 run 不覆盖；
- GitHub 只能看到已 Push 内容，本地未 Push 内容必须明确标记为本地状态；
- 审计失败或任务与固定规则冲突时停止，不执行 Commit 或 Push。

后续任务提示词只需明确任务目标、允许修改文件、验收条件、输出/run 编号以及是否授权
Commit 和 Push；固定 Git 安全规则由 `core.md` 和 `AGENTS.md` 持续生效。

---

## 5. 当前建模口径

### 5.1 当前 MSP 跨期状态

当前 H2 MSP 的主要跨期状态是四个氢站的 LOH：

- `x = [x1, x2, x3, x4]`

当前 Benders cuts 主要关于 `x`。

---

### 5.2 lf=7 / lf=8 当前解释

当前解释：

- `lf=1~6`：普通临灾准备阶段；
- `lf=7`：TerminalLOH demand/check stage；
- `lf=8`：零成本吸收状态。

`lf=8` 不是新的物理决策阶段。

---

### 5.3 当前主程序 TerminalLOH 口径

当前主 MSP 程序默认 TerminalLOH 使用：

- `node_load`；
- `impact_weight`；
- `A_site_node`。

TerminalLOH 只在 `lf=7` 检查。  
TerminalLOH 不是普通阶段库存出库量。  
普通阶段不应重新加入每期 TargetLOH 约束。

---

### 5.4 beta 当前口径

`beta(k)` 表示台风状态下 HTT 调拨风险、摩擦或成本增大。

`beta` 高不等于吸收。  
`beta` 高不等于 TerminalLOH 已触发。

---

### 5.5 roadSoft 当前口径

roadSoft 当前只是离线预览中的预部署软分配方法。

roadSoft 是：

- 临灾预部署软分配；
- 考虑路网可达性；
- 用于把节点需氢量柔性分配给四个氢站。

roadSoft 不是：

- 灾后 MFCV 路径优化；
- 节点硬指派；
- 道路修复模型；
- 车辆路径 MILP。

当前坐标口径：

- `data/yuanqi/stage1_road_edges.csv` 提供道路拓扑；
- `data/yuanqi/stage1_site_nodes.csv` 提供氢站道路锚点 `site_id / grid_node`；
- 电网节点和道路节点坐标统一使用 `windMC.layout.nodes`；
- 氢站坐标统一使用 `windMC.layout.sites`；
- road edge midpoint、road wind speed、road close probability 和 road figures 使用 `windMC.layout` 坐标。

当前服务距离口径：

- site-node 基础服务距离由程序基于道路拓扑、统一节点坐标和氢站锚点现场重算；
- roadSoft 中的 `base_site_to_node_road_km` 使用现场重算的 site-node 最短路距离；
- roadSoft 的 road service cost 在基础服务距离、可达概率和通行风险基础上形成；
- 当前离线预览图片输出采用中文标注。

当前守恒要求：

roadSoft 应该只改变节点需氢量在四个氢站之间的分配，不改变总节点需氢量。

应满足：

`currentA TerminalLOH_total ≈ roadSoft TerminalLOH_total`

---

### 5.6 RiskCap-Mean 当前口径

RiskCap-Mean 当前只是离线预览中的状态级 TerminalLOH 分配方法。

RiskCap-Mean 是：

- 离线 TerminalLOH 候选生成方法；
- 使用联合场景均值描述节点需氢量、道路可达性和通行风险；
- 使用容量约束、可达性和服务风险成本生成状态级氢站 TerminalLOH；
- 用于和 currentA、roadSoft 做离线对比。

RiskCap-Mean 不是：

- 主 MSP 的 forward/backward/cut 逻辑；
- 正式 OOS policy evaluation 的组成部分；
- 灾后车辆路径或 MFCV 调度模型；
- 新的 `terminal_load_mode`。

RiskCap-Mean 当前服务距离口径：

- 与 roadSoft 使用同一套现场重算 site-node 最短路基础距离；
- 服务风险成本基于基础距离、道路不可达风险和通行距离等离线诊断量；
- 仍不覆盖 `params.TerminalLOH`，不改变主 MSP 当前 `node_load` 口径。

### 5.7 TerminalLOH 条件灾后场景生成中期方向

当前 TerminalLOH 仍可视为终端状态下的储氢准备目标，但单一 `lf=7` 状态直接生成需求的解释力有限。

后续中期方向是研究基于 `lf=7` terminal state 的条件灾后场景生成机制：

- 给定一个 `lf=7` terminal state；
- 不直接把该单点状态等同于最终需求；
- 在该 terminal state 条件下生成一组 post-impact / 灾后影响场景；
- 在条件灾后场景中考虑台风登陆后继续移动、强度衰减，以及电网和道路继续受影响；
- 统计节点累计需氢量、道路可达性和服务风险；
- 再将统计结果转化为氢站层面的 TerminalLOH。

这一路线定位为增强 TerminalLOH 生成逻辑，不是立即扩展主 MSP 阶段结构。  
`lf>7` 的灾后影响暂时不作为主 MSP 的新阶段，而是作为离线 TerminalLOH 生成中的条件场景处理。  
当前仍保持预部署研究定位，不转向完整灾后运营调度模型。

### 5.8 中长期扩展方向

以下方向属于中长期扩展，不作为当前主 MSP 的立即修改内容：

- CVaR / 风险规避口径：可用于 TerminalLOH 生成、离线评估或未来 MSP 目标函数，当前先作为风险度量扩展方向；
- 终端灾后响应 LP recourse：可将 `lf=7` 的简单 TerminalLOH 检查升级为给定库存 `x` 后的灾后连续分配 recourse，当前只作为长期模型扩展方向；
- MFCV / 路径 / 修复 / 灾后滚动优化：包括 MFCV 配送、车辆路径、道路修复、电网修复和灾后滚动优化，当前不作为预部署主线；
- 配电网运行约束与电解槽接入：当前电网侧主要用于生成节点失负荷和需氢量，后续可考虑 LinDistFlow / DistFlow、电压、线路容量、电解槽接入节点和制氢受电网状态约束。

---

## 6. 当前开放问题

当前开放问题记录的是“这个阶段还需要关注的问题”，不是长期固定规则。

1. `a=6, loc=5` 和 `a=6, loc=6` 的 `fallback_node_count` 偏高，需要看 road close probability 和 reachability；
2. 继续验证 RiskCap-Mean 离线 TerminalLOH 分配结果的稳定性；
3. 比较 currentA、roadSoft、RiskCap-Mean 在总量、空间分配、未覆盖量、服务风险和容量利用率上的差异；
4. `terminal_loh_allocation_roadSoft.csv` 中 `H_node_kg` 会按 site 重复，统计时不能直接 sum 全表 `H_node_kg`；
5. 研究如何在 `lf=7` terminal state 条件下生成 post-impact / 灾后影响场景，并把累计节点需氢量、道路可达性和服务风险转化为氢站层面的 TerminalLOH；
6. 离线结果和生成口径稳定后，再讨论是否新增 `terminal_load_mode` 并小规模接入 MSP；主 MSP 接入仍属于后续阶段；
7. CVaR / 风险规避、终端灾后响应 LP recourse、MFCV / 路径 / 修复 / 灾后滚动优化、配电网运行约束与电解槽接入仍作为中长期扩展方向。

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
