# log.md

## 0. 文件用途

这是 Codex 执行记录文件。

每次 Codex 完成任务后，都应更新本文件。

不要删除历史记录。  
不要伪造运行结果。  
如果没有实际运行成功，不要填写虚假的统计结果。

---

## 1. 最近一次任务

- 日期：2026-07-10
- 任务标题：补充更详细的 pre 合并汇报图汇报稿
- 本次读取规则文件：`codex_rule/core.md`、`codex_rule/longtask.md`、`codex_rule/log.md`
- 是否成功运行：是；只读规则文件并补充更详细的 `pre_fig01_02_cost_shortage_summary` 汇报语句
- 运行命令：PowerShell `Get-Content`
- 修改文件：`codex_rule/log.md`
- 新增文件：无
- 删除文件：无
- 是否更新 core.md：否
- 是否更新 longtask.md：否
- 是否违反禁止项：否

---

## 2. 最近一次关键检查

- 是否未改 MSP 主体层：是
- 是否未改主入口 / 对照实验层：是
- 是否未改 load_data_h2_near.m：是
- 是否未改 near_stage_msp_input.mat：是
- 是否未改任何禁止修改代码文件：是；未修改 `main_msp_h2_near.m`、`fa_h2/` 主流程、MATLAB 主程序或数据加载主逻辑
- 是否未改数据文件：是；仅读取既有结果 CSV，未修改任何 CSV/MAT
- 是否未覆盖已有 output CSV：是
- 是否运行程序：是；仅运行独立 Python 汇报图脚本，未运行 MATLAB/Gurobi/MSP/OOS evaluation
- 是否新增 terminal_load_mode：否
- 是否接入 WDRO / roadSoft / wind_mc 到正式 MSP：否
- 是否覆盖 params.TerminalLOH：否
- 是否改变 lf=7 / lf=8 逻辑：否
- 是否改变 roadSoft / RiskCap-Mean / WDRO 任何离线算法：否
- 是否改变 fallback 逻辑：否
- 是否改变 currentA 定义：否
- 是否改变 MSP 正式 TerminalLOH 口径：否
- 是否修改长期阶段说明：否
- 是否把详细运行结果写入 longtask.md：否，详细运行结果仍保留在 `log.md`

---

## 3. 最近一次输出与指标

- 本次未生成新图片、未修改绘图脚本、未运行 Python/MATLAB/Gurobi/MSP/OOS。
- 补充更详细汇报口径：先说明图的目的和 OOS 样本含义，再依次解释 A 图成本累计分布、右上角指标卡、B 图 TerminalLOH 要求满足率、C 图未满足路径缺口分布，最后给出“多数路径有效、尾部情景仍需改进”的结论。
- 强调汇报时不能只用成本判断策略好坏，应结合 TerminalLOH 要求满足率、最大缺口和成本 CVaR95 一起说明。

---

## 4. 最近一次未完成事项或报错

- 未完成事项：无。
- 报错信息：无。
- 需要用户确认的问题：无阻塞项。

---

## 5. 最近一次对 core.md / longtask.md 的建议

### 是否建议更新 core.md

- 是 / 否：否

如果是，建议内容：

1. 建议更新章节：
2. 建议修改内容：
3. 修改理由：
4. 不修改的影响：

### 是否建议更新 longtask.md

- 是 / 否：否

如果是，建议内容：

1. 建议更新章节：
2. 建议修改内容：
3. 修改理由：
4. 与长期路线的关系：

---

## 6. 历史记录

### 2026-07-10 - 补充更详细的 pre 合并汇报图汇报稿

- 读取规则文件：`codex_rule/core.md`、`codex_rule/longtask.md`、`codex_rule/log.md`。
- 针对用户反馈“汇报不够详细”，补充可直接对老师讲的详细汇报语句。
- 解释顺序包括：图的总体目的、OOS 样本含义、A 图成本累计分布、右上角指标卡、B 图 TerminalLOH 要求满足路径占比、C 图未满足路径缺口分布、总体结论和可能追问回答。
- 本次未修改绘图脚本、未生成新图、未修改 MSP 主体、主入口、数据加载文件、CSV/MAT；未运行 Python/MATLAB/Gurobi/MSP/OOS evaluation。

### 2026-07-10 - 解释 pre 合并汇报图 A/B/C 三个分图

- 读取规则文件：`codex_rule/core.md`、`codex_rule/longtask.md`、`codex_rule/log.md`。
- 解释 `pre_fig01_02_cost_shortage_summary` 中三个分图含义：A 为 OOS 路径总成本累计分布，B 为 TerminalLOH 要求满足路径占比，C 为未满足路径 TerminalLOH 缺口分布。
- 说明该图应按“成本表现 + TerminalLOH 满足率 + 未满足缺口严重程度”的组合口径汇报，不能只用成本判断保护效果。
- 本次未修改绘图脚本、未生成新图、未修改 MSP 主体、主入口、数据加载文件、CSV/MAT；未运行 Python/MATLAB/Gurobi/MSP/OOS evaluation。

### 2026-07-10 - 严谨化 pre 合并汇报图标题表述

- 读取规则文件：`codex_rule/core.md`、`codex_rule/longtask.md`、`codex_rule/log.md`。
- 修改 `scripts/plot_h2_msp_pre_report_figures.py`：将图标题从偏解释型表述调整为更正式的统计口径。
- 主标题改为 `OOS 路径成本与 TerminalLOH 要求满足情况统计汇总`。
- 分图标题改为 `A. OOS 路径总成本累计分布`、`B. TerminalLOH 要求满足路径占比`、`C. TerminalLOH 要求未满足路径的缺口分布`。
- 同步将图例和指标卡中的 `达标` 表述调整为 `要求满足 / 要求未满足`，避免口语化。
- 成功运行 `python scripts\plot_h2_msp_pre_report_figures.py`，重新生成 `output_h2/figures/msp_results/pre/pre_fig01_02_cost_shortage_summary.png` 和 `.svg`。
- 人工查看确认标题无重叠、无挤压；本次未恢复灰色解释性文字。
- 本次未修改 MSP 主体、主入口、数据加载文件、CSV/MAT；未运行 MATLAB/Gurobi/MSP/OOS evaluation。

### 2026-07-09 - 移除 pre 合并汇报图中的灰色解释性文字

- 读取规则文件：`codex_rule/core.md`、`codex_rule/longtask.md`、`codex_rule/log.md`。
- 修改 `scripts/plot_h2_msp_pre_report_figures.py`：移除图内灰色解释性文字，包括顶部说明、右侧说明和底部建议句。
- 将 B 图标题调整为更直接的 `B. 无终端短缺路径占比`，避免在图中放过多解释。
- 成功运行 `python scripts\plot_h2_msp_pre_report_figures.py`，重新生成 `output_h2/figures/msp_results/pre/pre_fig01_02_cost_shortage_summary.png` 和 `.svg`。
- 人工查看确认灰色解释性文字已移除；标题、坐标轴、指标卡、图例和关键数值仍保留。
- 本次未修改 MSP 主体、主入口、数据加载文件、CSV/MAT；未运行 MATLAB/Gurobi/MSP/OOS evaluation。

### 2026-07-09 - 为图1/图2新增合并汇报版展示图

- 读取规则文件：`codex_rule/core.md`、`codex_rule/longtask.md`、`codex_rule/log.md`。
- 新增独立脚本 `scripts/plot_h2_msp_pre_report_figures.py`，只读 `h2_oos_path_costs.csv`、`h2_terminal_summary.csv` 和 `oos_risk_metrics.csv`。
- 生成图1/图2合并汇报版：`output_h2/figures/msp_results/pre/pre_fig01_02_cost_shortage_summary.png`、`.svg`。
- 新图使用 OOS 成本 ECDF、关键指标卡、无终端短缺路径占比和非零短缺尾部分布，避免单独展示成本或短缺导致误读。
- 更新 `output_h2/figures/msp_results/pre/README_pre_selection.txt`，将新图标为推荐替代原始 fig01/fig02 的汇报图。
- 图片检查：PNG 尺寸 3999×2250；人工查看确认中文标签、主要指标、图例和说明可读。
- 本次未修改 MSP 主体、主入口、数据加载文件、CSV/MAT；未运行 MATLAB/Gurobi/MSP/OOS evaluation。

### 2026-07-09 - 向 pre 汇报图文件夹补充成本分布图

- 读取规则文件：`codex_rule/core.md`、`codex_rule/longtask.md`、`codex_rule/log.md`。
- 将 `fig01_oos_cost_distribution.png` 和 `fig01_oos_cost_distribution.svg` 复制到 `output_h2/figures/msp_results/pre/`。
- 更新 `output_h2/figures/msp_results/pre/README_pre_selection.txt`：将 `fig01` 纳入已放入图片，并注明成本图应和 TerminalLOH 短缺图一起讲，不要单独用成本判断保护效果。
- 目录核查确认 `pre` 当前包含 5 组图片，共 10 个图片文件，以及 1 个说明文件。
- 本次未修改绘图脚本、未生成新图、未修改 CSV/MAT、未运行 Python/MATLAB/Gurobi/MSP/OOS evaluation；未修改任何默认保护模块。

### 2026-07-09 - 新建 pre 汇报图文件夹并筛选不易误解图片

- 读取规则文件：`codex_rule/core.md`、`codex_rule/longtask.md`、`codex_rule/log.md`。
- 新建目录：`output_h2/figures/msp_results/pre/`。
- 复制 4 组适合汇报的图片，每组包含 PNG 和 SVG：`fig02_terminal_shortage_distribution`、`fig03_oos_risk_metrics`、`fig05_site_terminal_check`、`fig10_path351_vs_path3_terminal_check`。
- 新增 `output_h2/figures/msp_results/pre/README_pre_selection.txt`，说明已放入图的用途和未放入图的原因。
- 故意未放入容易引起歧义或需要大量解释的图：`fig01`、`fig04`、`fig06`、`fig07`、`fig08`、`fig09`、`fig11`。
- 目录核查确认 `pre` 中包含 8 个图片文件和 1 个说明文件。
- 本次未修改绘图脚本、未生成新图、未修改 CSV/MAT、未运行 Python/MATLAB/Gurobi/MSP/OOS evaluation；未修改任何默认保护模块。

### 2026-07-09 - 确认 MSP 制氢决策是综合考虑未来风险和路径概率

- 读取规则文件：`codex_rule/core.md`、`codex_rule/longtask.md`、`codex_rule/log.md`。
- 解释 MSP/SDDP 决策口径：某阶段制氢不是只服务当前已经看到的 OOS 路径，而是基于当前状态和训练得到的 future-value cuts，对所有可能后续状态/路径的概率加权风险做近似。
- 说明 B/cut 价值综合反映各站库存对未来 TerminalLOH 风险、台风状态转移和后续路径可能性的价值。
- 说明最终制氢还受到当前成本、正常需求、站点库存、储罐容量、电解槽上限、HTT 调拨和 cut 折点共同影响。
- 本次未修改绘图脚本、未生成新图、未运行 MATLAB、未重跑 MSP、未重新评估 OOS；仅更新 `codex_rule/log.md`。

### 2026-07-09 - 解释 B-C 差值与制氢量大小的关系

- 读取规则文件：`codex_rule/core.md`、`codex_rule/longtask.md`、`codex_rule/log.md`。
- 解释 B-C 差值不是制氢量的线性比例系数；它主要表示边际上多制/多存 1kg 是否有利，以及该站点相对其他站点的优先级。
- 说明实际制氢量由 LP 目标和约束共同决定，包括电解槽上限、罐容量、正常需求、HTT/库存耦合、站点级 B 差异和 cut 折点。
- 用 path1 t=5 延续解释：四站平均 B<C 不能判断总制氢，因为实际制氢主要落在 B>C 的站点，且高 B 站点电解槽达到上限。
- 本次未修改绘图脚本、未生成新图、未运行 MATLAB、未重跑 MSP、未重新评估 OOS；仅更新 `codex_rule/log.md`。

### 2026-07-09 - 解释 path1 t=5 平均 B<C 但仍大量制氢并修正 fig11

- 读取规则文件：`codex_rule/core.md`、`codex_rule/longtask.md`、`codex_rule/log.md`。
- 只读核查 `selected_paths_site_balance.csv`、`selected_paths_cut_marginal_value.csv`、`selected_paths_cost_breakdown.csv`、`selected_paths_timeseries.csv`。
- path1 t=5 总制氢为 `59.7502 kg`，单位制氢成本 C 为 `16.6838 元/kg`。
- path1 t=5 站点级 B 为 site1=`3.24`、site2=`18.00`、site3=`23.76`、site4=`18.00` 元/kg；四站简单平均 B=`15.75` 元/kg，小于 C。
- path1 t=5 制氢主要落在 B>C 的 site2/site3/site4，制氢量分别为 `23.4/14.04/17.55 kg`，对应电解槽功率 `200/120/150 kW`，达到各自上限；site1 仅制氢 `4.7602 kg`。
- 计算 path1 t=5 按制氢量加权 B=`18.1776 元/kg`，高于 C，因此原图只看四站平均 B 会误导。
- 修改 `scripts/plot_h2_msp_result_figures.py` 的 `plot_fig11()`：读取 `selected_paths_site_balance.csv`，新增“B：按制氢量加权”紫色虚线，B>C/B<C 标注优先使用加权 B。
- 成功运行 `python scripts\plot_h2_msp_result_figures.py`，重新生成 fig01~fig11 的 PNG/SVG，最终输出 `Skipped or warnings: none`。
- 人工查看新版 `fig11_value_cost_production_diagnostics.png`，确认 path1 t=5 已显示平均 B<C 但加权 B>C。
- 本次未修改 `main_msp_h2_near.m`、`fa_h2/` 主流程、数据加载文件、MAT 数据文件或任何 output CSV；未运行 MATLAB/Gurobi/MSP/OOS evaluation。

### 2026-07-09 - 新增 B/C 与实际制氢量诊断图 fig11

- 读取规则文件：`codex_rule/core.md`、`codex_rule/longtask.md`、`codex_rule/log.md`。
- 修改 `scripts/plot_h2_msp_result_figures.py`：新增 `plot_fig11()`，并在 `main()` 中调用。
- 图11读取现有 `selected_paths_timeseries.csv`、`selected_paths_cost_breakdown.csv`、`selected_paths_cut_marginal_value.csv` 和 `selected_path_summary.csv`，不调用 MATLAB、不运行 MSP、不训练模型、不重新评估 OOS。
- 图11对 path1、path3、path351 分别展示 B=`marginal_value_of_1kg_LOH` 四站平均、B 四站范围、C=单位制氢成本、实际制氢量，帮助解释图6缺少 B/C 时无法判断“制 1kg 是否值得”的问题。
- 第一次运行绘图脚本因 `status` 字段 merge 后缀出现 `KeyError: 'status'`；已修复为只合并成本表必要列后重跑成功。
- 成功运行 `python scripts\plot_h2_msp_result_figures.py`，重新生成 fig01~fig11 的 PNG/SVG，最终输出 `Skipped or warnings: none`。
- 新增输出：`output_h2/figures/msp_results/fig11_value_cost_production_diagnostics.png`、`output_h2/figures/msp_results/fig11_value_cost_production_diagnostics.svg`。
- 图片检查：`fig11` PNG 尺寸 3999×2250；人工查看确认中文标签、B/C 曲线、B>C/B<C 标注、实际制氢柱和 path1“吸收”标注可读。
- 本次未修改 `main_msp_h2_near.m`、`fa_h2/` 主流程、数据加载文件、MAT 数据文件或任何 output CSV；未运行 MATLAB/Gurobi/MSP/OOS evaluation。

### 2026-07-09 - 解释图6中 path1/path3 的 theta 下降及 B/C 缺失问题

- 读取规则文件：`codex_rule/core.md`、`codex_rule/longtask.md`、`codex_rule/log.md`。
- 只读核查 `scripts/plot_h2_msp_result_figures.py` 中 `plot_fig06()`，确认图6彩色柱为实际阶段成本，黑色虚线为 `theta_value` 未来成本近似。
- 只读汇总 `selected_paths_cost_breakdown.csv`、`selected_paths_timeseries.csv`、`selected_paths_cut_marginal_value.csv`。
- 说明 path1/path3 的黑色虚线下降只代表模型估计的剩余未来成本降低，不代表实际成本下降，也不能单独判断制氢是否值得。
- 补充 path1/path3 的平均 B 与单位制氢成本 C 数值，说明判断制氢需要 B/C，而图6本身没有画出 B/C。
- 本次未修改绘图脚本、未生成新图、未运行 MATLAB、未重跑 MSP、未重新评估 OOS；仅更新 `codex_rule/log.md`。

### 2026-07-09 - 解释 B>C 仍制氢但 A 看起来小的原因

- 读取规则文件：`codex_rule/core.md`、`codex_rule/longtask.md`、`codex_rule/log.md`。
- 解释 A=`theta_value` 是当前已选动作/库存状态下的未来近似成本水平，不是不制氢方案下的未来成本。
- 解释 B=`marginal_value_of_1kg_LOH` 是 A 对库存的局部斜率，B>C 表示当前附近多 1kg 库存仍值得；模型可能正因为 B>C 才制氢，使观察到的 A 已经被降下来。
- 本次未修改绘图脚本、未生成新图、未运行 MATLAB、未重跑 MSP、未重新评估 OOS；仅更新 `codex_rule/log.md`。

### 2026-07-09 - 解释 theta_value 未来近似成本总额的作用

- 读取规则文件：`codex_rule/core.md`、`codex_rule/longtask.md`、`codex_rule/log.md`。
- 说明 A=`theta_value` 不是无用量，而是阶段优化目标中用于代表未来成本总额的变量；模型比较的是当前阶段成本加未来近似成本。
- 说明 B=`marginal_value_of_1kg_LOH` 是从 A/cuts 中提取出的单位库存价值诊断量，用于解释“多 1kg 是否值得”，但实际优化仍通过 A 进入目标函数。
- 本次未修改绘图脚本、未生成新图、未运行 MATLAB、未重跑 MSP、未重新评估 OOS；仅更新 `codex_rule/log.md`。

### 2026-07-09 - 确认 A/B/C 三个成本价值口径

- 读取规则文件：`codex_rule/core.md`、`codex_rule/longtask.md`、`codex_rule/log.md`。
- 确认 A=`theta_value` 是未来近似成本总额，B=`marginal_value_of_1kg_LOH` 是单位库存价值/斜率。
- 说明 C 不是一个全局固定量：制氢效率和最大产能为固定参数，实际制氢量是决策变量，单位制氢成本随阶段电价/站点/运维口径变化。
- 本次未修改绘图脚本、未生成新图、未运行 MATLAB、未重跑 MSP、未重新评估 OOS；仅更新 `codex_rule/log.md`。

### 2026-07-09 - 解释 theta_value 与 marginal_value_of_1kg_LOH 的关系

- 读取规则文件：`codex_rule/core.md`、`codex_rule/longtask.md`、`codex_rule/log.md`。
- 解释 `theta_value` 是未来成本近似总量，单位为元；`marginal_value_of_1kg_LOH` 是该近似函数对站点库存的单位变化量，单位为元/kg。
- 明确判断是否值得多制/多存 1kg 氢时，应比较 `marginal_value_of_1kg_LOH` 与制氢、持有、运输等单位成本，而不是直接比较 `theta_value`。
- 本次未修改绘图脚本、未生成新图、未运行 MATLAB、未重跑 MSP、未重新评估 OOS；仅更新 `codex_rule/log.md`。

### 2026-07-09 - 解释未来近似成本是否和 2000 元/kg 直接比较

- 读取规则文件：`codex_rule/core.md`、`codex_rule/longtask.md`、`codex_rule/log.md`。
- 解释口径：`theta_value` 是未来总成本近似，不能直接和 `2000 元/kg` 终端罚比较；可比较的是单位库存边际价值 `marginal_value_of_1kg_LOH` 与制氢/持有/运输等边际成本。
- 说明 `2000 元/kg` 作为 TerminalLOH 缺口罚，会通过终端阶段求解和 backward cuts 传导到前面阶段的未来成本近似中。
- 本次未修改绘图脚本、未生成新图、未运行 MATLAB、未重跑 MSP、未重新评估 OOS；仅更新 `codex_rule/log.md`。

### 2026-07-09 - 解释如何判断制 1kg 氢气的价值

- 读取规则文件：`codex_rule/core.md`、`codex_rule/longtask.md`、`codex_rule/log.md`。
- 基于上一轮已核查数据解释：终端检查时短缺站点的 1kg 氢价值可对应避免 `2000 元/kg` 缺口罚；终端前的 1kg 氢价值来自 SDDP/FA-MSP cuts 对未来成本节省的估计，即 `marginal_value_of_1kg_LOH`。
- 明确比较口径：判断是否值得制氢，要比较 `marginal_value_of_1kg_LOH` 与制氢边际成本及持有/运输成本；同时必须按站点看，不能只看系统总量。
- 本次未修改绘图脚本、未生成新图、未运行 MATLAB、未重跑 MSP、未重新评估 OOS；仅更新 `codex_rule/log.md`。

### 2026-07-09 - 通俗解释 path351 为什么总量够但仍短缺

- 读取规则文件：`codex_rule/core.md`、`codex_rule/longtask.md`、`codex_rule/log.md`。
- 基于上一轮已核查结果，用通俗口径解释 path351：模型不是没有制氢，而是已经把总量做够；问题在于站点级空间错配。
- 明确 cut 曲线不是未来总成本，而是单位库存的未来价值信号；因此“曲线看起来不大”和“模型仍满产制氢”不矛盾。
- 本次未修改绘图脚本、未生成新图、未运行 MATLAB、未重跑 MSP、未重新评估 OOS；仅更新 `codex_rule/log.md`。

### 2026-07-09 - 解释 path351 未来成本曲线与满产制氢的关系

- 读取规则文件：`codex_rule/core.md`、`codex_rule/longtask.md`、`codex_rule/log.md`。
- 只读核查 `selected_paths_timeseries.csv`、`selected_paths_site_balance.csv`、`selected_paths_cost_breakdown.csv`、`selected_paths_cut_marginal_value.csv` 和 `selected_paths_transition_expectation_summary.csv`。
- 核查发现 path351 在 `t=1~5` 每期均满产 `90.09 kg`，`t=6` 为 TerminalLOH 检查阶段且制氢为 0。
- 计算得到 path351 普通阶段制氢成本约为 `16.68/35.23/41.13/39.50/16.68 元/kg`，cut 平均边际价值约为 `44.94/177.29/157.88/321.77/491.62 元/kg`。
- 解释口径：cut 曲线是单位库存边际价值，不是未来总成本；其相对终端罚较小，但相对制氢成本仍较大，因此可解释满产制氢。path351 的核心问题不是总量不足，而是站点级空间错配。
- 本次未修改绘图脚本、未生成新图、未运行 MATLAB、未重跑 MSP、未重新评估 OOS；仅更新 `codex_rule/log.md`。

### 2026-07-09 - 新增 path351 综合诊断图

- 读取规则文件：`codex_rule/core.md`、`codex_rule/longtask.md`、`codex_rule/log.md`。
- 修改 `scripts/plot_h2_msp_result_figures.py`：新增 `plot_fig09()`，将 path351 的状态推进、终端站点级检查、关键结论、成本分解、HTT 调拨、cut 边际未来价值和 path3 对照整合到一张综合诊断图中。
- 运行 `python scripts/plot_h2_msp_result_figures.py` 成功，重新生成 fig01~fig09 的 PNG/SVG；脚本输出 `Skipped or warnings: none`。
- 新增输出文件：`output_h2/figures/msp_results/fig09_path351_integrated_diagnostics.png`、`output_h2/figures/msp_results/fig09_path351_integrated_diagnostics.svg`。
- 人工查看新增 PNG，确认中文标签、t=6 终端检查标注、站点级柱状图、成本对比、HTT 调拨、cut 价值和 path3 对照整体可读。
- 本次未运行 MATLAB、未重跑 MSP、未重新评估 OOS；未修改主入口、`fa_h2/` 主流程、数据文件或既有 output CSV。
- 非阻塞报错：尝试执行 `git diff` 时当前 PowerShell 环境找不到 `git` 命令。

### 2026-07-09 - H2-MSP path351 在 t=6 终端检查阶段动作口径解释

- 读取规则文件：`codex_rule/core.md`、`codex_rule/longtask.md`、`codex_rule/log.md`。
- 基于上一轮已核查 path351 轨迹解释：`t=6` 到达 `lf=7` 后不是普通准备阶段，不应解释为仍有有效制氢、HTT 调拨、正常供氢或 cut 未来价值决策。
- 明确图形口径：图4/5/6 在 `t=6` 可显示状态结果、终端检查和罚成本；图7若有 `t=6` 记录应谨慎解释为终端阶段记录；图8只到 `t=5` 是因为只有终端前普通决策阶段才有 cut 边际未来价值。
- 本次未修改主入口、`fa_h2/` 主流程、数据文件或既有输出 CSV；仅更新 `codex_rule/log.md`。

### 2026-07-09 - H2-MSP path351 小概率终端状态与图8时间窗口解释核查

- 读取规则文件：`codex_rule/core.md`、`codex_rule/longtask.md`、`codex_rule/log.md`；实际规则目录为 `testH2_v2/codex_rule/`。
- 只读核查 `output_h2/details` 下现有 CSV，未运行 MATLAB、未重跑 MSP、未重新评估 OOS、未重新生成图片。
- 核查 path351：`t=5` 为 `k=190,a=4,loc=3,lf=6`，`t=6` 到达 `k=271,a=5,loc=6,lf=7` 并触发 TerminalLOH 检查，`t=7/8` 为 `lf=8` 吸收状态。
- 核查 k=271 频次：10000 条 OOS 路径中任意时间出现 9 次，`t=6` 出现 4 次；`k_t5=190` 的 15 条路径中有 2 条转到 `k_t6=271`。模型转移概率表中 `k=190 -> k=271` 概率为 0.02772。
- 核查图5站点级短缺：path351 总库存 495.357 kg，高于总 TerminalLOH 目标 400.107 kg，但站点级短缺仍为 188.676 kg，原因是站1过剩不能抵消站2/3/4短缺。
- 核查图8：cut 边际价值只记录普通决策阶段；path351 在 `t=6` 已进入终端检查，后续 `t=7/8` 为吸收状态，因此图8只到 `t=5`。
- 本次未修改主入口、`fa_h2/` 主流程、数据文件或既有输出 CSV；仅更新 `codex_rule/log.md`。

### 2026-07-09 - H2-MSP 结果图标签中文化与解释口径修正

- 读取规则文件：`codex_rule/core.md`、`codex_rule/longtask.md`、`codex_rule/log.md`。
- 根据用户反馈修正解释口径：不再使用“baseline 失败”表述；强调成本低不等于保护效果好，应结合 TerminalLOH 短缺、站点级检查和服务目标解释。
- 修改 `scripts/plot_h2_msp_result_figures.py`：将图 4/5/6/7/8 的路径标签、图例、坐标轴和注释改为更直观中文表达。
- 重新运行独立 Python 绘图脚本，重新生成 `output_h2/figures/msp_results/` 下 8 组 PNG/SVG 图片；脚本输出无缺文件或缺字段跳过项。
- 本次未修改 Word、未修改 MATLAB 主程序、未修改 `main_msp_h2_near.m`、未修改 `fa_h2/` 主流程、未修改数据文件、未修改已有 output CSV、未重新运行 MSP、未重新训练模型、未重新评估 OOS。

### 2026-07-09 - H2-MSP 现有结果只读分析与 PPT 图片生成

- 读取规则文件：`codex_rule/core.md`、`codex_rule/longtask.md`、`codex_rule/log.md`。
- 使用 Word 交接文档理解 MSP 和 TerminalLOH 口径：任务正文指定的项目内 Word 路径不存在，实际读取用户提供的同名 `Downloads` 文件；未修改、未移动、未覆盖 Word。
- 只读取 `output_h2/details` 下现有 CSV：`h2_oos_path_costs.csv`、`h2_oos_summary_by_path.csv`、`h2_terminal_summary.csv`、`oos_risk_metrics.csv`、`selected_path_summary.csv`、`selected_paths_timeseries.csv`、`selected_paths_cost_breakdown.csv`、`selected_paths_site_balance.csv`、`selected_paths_loh_demand_detail.csv`、`selected_paths_transport_edges.csv`、`selected_paths_cut_marginal_value.csv`、`terminal_load_check.csv`。
- 新增独立绘图脚本 `scripts/plot_h2_msp_result_figures.py`；脚本只读 `details` CSV，检查文件和关键字段，输出 PNG/SVG 到 `output_h2/figures/msp_results/`，不调用 MATLAB，不运行 MSP，不训练模型，不重新评估 OOS。
- 生成 8 组 PPT 用科研风格图片：`fig01_oos_cost_distribution`、`fig02_terminal_shortage_distribution`、`fig03_oos_risk_metrics`、`fig04_representative_path_loh`、`fig05_site_terminal_check`、`fig06_cost_breakdown`、`fig07_htt_transport`、`fig08_cut_marginal_value`，每组含 PNG 和 SVG。
- 图片检查：8 张 PNG 均为 3999×2250、约 300 dpi；脚本输出无缺文件或缺字段跳过项。
- 未修改 Word、未修改 MATLAB 主程序、未修改 `main_msp_h2_near.m`、未修改 `fa_h2/` 主流程、未修改数据文件、未修改已有 output CSV、未重新运行 MSP、未重新训练模型、未重新评估 OOS。
- 图注口径：`theta_value` 仅作为训练未来成本近似虚线显示，不作为样本外实际成本堆叠；未把 `wind_mc`、`roadSoft`、`RiskCap-Mean` 或 `WDRO` 写成当前 MSP 已采用结果。

### 2026-07-06 - WDRO-TerminalLOH 第一阶段目录规范化

- 按用户要求将 WDRO 第一阶段整理为独立模块结构：`terminalLoh_wdro/src/`、`terminalLoh_wdro/output/stage1_single_window/`、`terminalLoh_wdro/checks/stage1_check/`、`terminalLoh_wdro/docs/`、`terminalLoh_wdro/config/`。
- 移动 MATLAB 源码到 `terminalLoh_wdro/src/`：`run_terminal_loh_wdro_preview_h2.m`、`build_terminal_loh_wdro_from_joint_samples_h2.m`、`build_wdro_distance_matrix_h2.m`、`solve_wdro_terminal_loh_lp_h2.m`。
- 移动说明文档到 `terminalLoh_wdro/docs/README_WDRO_preview.md`。
- 复制第一阶段输出到 `terminalLoh_wdro/output/stage1_single_window/`：`terminal_loh_by_state_WDRO.csv`、`terminal_loh_allocation_WDRO.csv`、`wdro_distance_matrix_summary.csv`、`wdro_rho_sensitivity_summary.csv`、`WDRO_README.txt`。
- 新增 `terminalLoh_wdro/checks/stage1_check/README_stage1_check.md`，说明当前是 single-window W=1 原型、每个 lf=7 状态 R=10、未接入 MSP、未实现 W=3 look-ahead、当前结果不作为正式论文数值结果、rho=0 在完整后果距离下可作为 SAA 退化检查、D_only 只是调试/对照口径、R=10 下 rho 增大不必然导致 TerminalLOH 单调增加、后续需要 W=3/R=50/100/OOS。
- 新增 `terminalLoh_wdro/config/README_config.md`，记录 stage1 默认配置和未来 config 目录用途。
- 修改运行脚本路径：以后默认输出写入 `terminalLoh_wdro/output/stage1_single_window/`；旧 `output_h2/wind_terminal_loh_preview/wdro/` 结果保留未删除。
- 修改 `build_terminal_loh_wdro_from_joint_samples_h2.m` 默认路径推断，适配源码位于 `terminalLoh_wdro/src/` 的新结构。
- 未重跑 MATLAB/Gurobi 优化；仅做文件移动、复制和静态检查。
- 未修改禁止文件：`main_msp_h2_near.m`、`run_h2_with_options.m`、`load_data_h2_near.m`、`fa_h2` 主流程文件、`data/yuanqi/near_stage_msp_input.mat`。

### 2026-07-06 - 修订 WDRO rho=0/SAA 表述并新增 rho 敏感性诊断表

- 修改 `terminalLoh_wdro/build_terminal_loh_wdro_from_joint_samples_h2.m`，后续运行 WDRO 离线预览时会额外输出 `wdro_rho_sensitivity_summary.csv`。
- 修改 `terminalLoh_wdro/README_WDRO_preview.md` 和 `output_h2/wind_terminal_loh_preview/wdro/WDRO_README.txt`：将 `rho=0` 表述为“经验分布基准”，不再写成 SAA 退化正确性检查；补充当前 R=10 下 rho 增大不保证 TerminalLOH 单调增加。
- 新增 `output_h2/wind_terminal_loh_preview/wdro/wdro_rho_sensitivity_summary.csv`，按 `distance_mode,rho` 汇总 `TerminalLOH_total_min/mean/max`、`objective_mean`、`lambda_mean` 和相对前一 rho 总 TerminalLOH 下降的状态数。
- 基于已有 `terminal_loh_by_state_WDRO.csv` 生成诊断表，本次未重跑 MATLAB/Gurobi WDRO 求解。
- 诊断结果：D_only 在 rho=0.02/0.05/0.10 相对前一 rho 的下降状态数为 11/12/11；DAC 为 7/11/14。
- 未修改 MSP 主入口、`load_data_h2_near.m`、`near_stage_msp_input.mat`、`fa_h2` 主流程或 `riskcap_mean/` 原输出；未接入 MSP，未新增 `terminal_load_mode`，未覆盖 `params.TerminalLOH`。
- 未完成事项：仍需 W=3 look-ahead 场景、R=50/100 和样本外测试后再判断 rho 敏感性和结果稳健性。

### 2026-07-06 - 第一阶段离线 WDRO-TerminalLOH 原型模块

- 新增独立代码目录 `terminalLoh_wdro/`，未放入 `fa_h2/fuzhu/`，未接入 MSP 主循环。
- 新增文件：`run_terminal_loh_wdro_preview_h2.m`、`build_terminal_loh_wdro_from_joint_samples_h2.m`、`build_wdro_distance_matrix_h2.m`、`solve_wdro_terminal_loh_lp_h2.m`、`README_WDRO_preview.md`。
- 新增输出目录：`output_h2/wind_terminal_loh_preview/wdro/`。
- 新增输出文件：`terminal_loh_by_state_WDRO.csv`、`terminal_loh_allocation_WDRO.csv`、`wdro_distance_matrix_summary.csv`、`WDRO_README.txt`。
- 输入数据使用 `output_h2/wind_terminal_loh_preview/riskcap_mean/joint_scenario_site_node.csv`；未覆盖 `riskcap_mean/` 原结果。
- 容量读取优先使用 `data/yuanqi/near_stage_msp_input.mat` 中 `NearStageInput.HydrogenDevice.tank_cap_kg=[300,200,100,150]`；`Cap_i=0.8*tank_cap_kg_i`；短缺惩罚读取 `reserve_shortage_penalty_yuan_per_kg=2000`；默认 `gamma=0.001*M=2`，可在 config 中修改。
- 支持两种后果距离：`D_only` 与 `DAC`，其中 `DAC` 默认权重为 `w_D=0.6,w_A=0.2,w_C=0.2`；Wasserstein 集合作用于联合后果样本 `xi=(D,A,C)`，不是道路物理距离。
- 当前 CSV 中不可达 pair 的 `scenario_service_cost` 为 `Inf`；LP 通过 `y<=A*D` 禁止不可达服务，并在 LP 系数和 DAC 的 C 分量中将不可达/非有限服务成本置为 0，由 A 分量表达可达性差异。
- 成功运行 MATLAB/Gurobi：`matlab -batch "cd('C:/Users/chaos/Desktop/biye/test/testH2_v2'); run('terminalLoh_wdro/run_terminal_loh_wdro_preview_h2.m');"`。
- 首次运行因 MATLAB path 未包含 Gurobi 接口失败；确认 `D:\gurobi1201\win64\matlab` 后，脚本改为运行期临时加入 `GUROBI_HOME/matlab` 和本机候选路径，不永久修改用户 path。
- 检查结果：35 个 `lf=7` 状态；每状态 R=10；每个 state-scenario 有 33 个节点和 4 个氢站；共 280 个 LP，全部 `OPTIMAL`；`rho=0` 的 70 个经验分布基准运行全部 `OPTIMAL`。
- 输出检查：`terminal_loh_by_state_WDRO.csv` 280 行；`terminal_loh_allocation_WDRO.csv` 369600 行；`wdro_distance_matrix_summary.csv` 280 行；输出无 NaN/Inf；TerminalLOH 无负值，最大容量越界 0。
- 未修改禁止文件：`main_msp_h2_near.m`、`h2_default_options.m`、`run_h2_with_options.m`、`load_data_h2_near.m`、`fa_h2/build_stage_model_h2.m`、`fa_h2/forward_pass_h2.m`、`fa_h2/backward_pass_h2.m`、`fa_h2/add_cut_h2.m`、`fa_h2/eval_h2.m`、`fa_h2/fuzhu/eval_terminal_loh_h2.m`、`fa_h2/fuzhu/terminal_value_and_subgradient_h2.m`、`data/yuanqi/near_stage_msp_input.mat`。
- 未完成事项：按本阶段要求未实现 3 窗口 look-ahead，未接入 MSP，未新增正式 `terminal_load_mode`，未覆盖 `params.TerminalLOH`。
- 建议：后续应先生成 W=3 `lookahead_scenario_site_node.csv` 后再运行 WDRO，并考虑更新 `longtask.md` 记录 WDRO 离线原型阶段。

### 2026-06-05 - 更新 longtask.md 中长期研究路线

- 修改文件：`codex_rule/longtask.md`、`codex_rule/log.md`。
- 未修改任何代码文件、数据文件、输出文件或 `codex_rule/core.md`。
- 未运行 MATLAB、Gurobi、MSP 或离线预览程序。
- `longtask.md` 已明确当前主 MSP 仍保持 `node_load + impact_weight + A_site_node` baseline。
- `longtask.md` 已明确 `wind_mc / roadSoft / RiskCap-Mean` 仍是离线 TerminalLOH 预览模块，尚未接入主 MSP。
- `longtask.md` 已加入“TerminalLOH 条件灾后场景生成”作为中期研究方向：在给定 `lf=7` terminal state 条件下研究 post-impact / 灾后影响场景生成，并将累计节点需氢量、道路可达性和服务风险转化为氢站层面的 TerminalLOH。
- CVaR / 风险规避、终端灾后响应 LP recourse、MFCV / 路径 / 修复 / 灾后滚动优化、配电网运行约束与电解槽接入已作为中长期扩展方向记录。
- 当前近期主线仍是稳定离线 TerminalLOH 预览；详细运行结果仍以 `log.md` 为准，不写入 `longtask.md`。

### 2026-05-28 - 微调 longtask.md 2.4 离线预览接入口径

- 修改文件：`codex_rule/longtask.md`、`codex_rule/log.md`。
- 将 `longtask.md` 2.4 中 “`wind_mc / roadSoft` 尚未接入主 MSP” 改为 “`wind_mc / roadSoft / RiskCap-Mean` 尚未接入主 MSP”。
- 未修改代码、数据文件、输出文件或 `codex_rule/core.md`。
- 未运行程序。

### 2026-05-28 - 更新 longtask.md 当前离线 TerminalLOH 预览阶段和架构口径

- 修改文件：`codex_rule/longtask.md`、`codex_rule/log.md`。
- 未修改代码文件、数据文件、输出文件或 `codex_rule/core.md`。
- 未运行 MATLAB、Gurobi、MSP 或任何离线预览程序。
- `longtask.md` 已按当前阶段和架构口径更新：离线 TerminalLOH 预览仍不接入主 MSP；电网侧用于生成状态级节点失负荷和节点需氢量；路网侧用于描述道路可达性、通行风险和服务成本；roadSoft 与 RiskCap-Mean 使用现场重算 site-node 最短路基础服务距离；离线预览图片采用中文标注。
- `longtask.md` 只保留长期阶段、架构快照和建模口径，不写入具体运行行数、图片数量、exit code 或抽查结果；详细运行结果仍以 `log.md` 历史记录为准。

### 2026-05-28 - 清理离线 TerminalLOH 预览路网输入口径、旧数据文件和图片文字

- 读取规则文件：`codex_rule/core.md`、`codex_rule/longtask.md`、`codex_rule/log.md`。
- 修改 `generate_terminal_loh_wind_mc_preview.m`：`load_stage1_road_data` 只读取 `stage1_road_edges.csv` 与 `stage1_site_nodes.csv`，并从 `windMC.layout.nodes` / `windMC.layout.sites` 取统一坐标；删除旧输入表读取、校验、保存字段；现场使用完整道路图 Dijkstra 重算 4×33 site-node 最短路矩阵。
- 新增输出表：`output_h2/wind_terminal_loh_preview/road/site_node_shortest_path_distance.csv`，132 行。
- roadSoft 与风险容量均值分配使用的 `base_site_to_node_road_km` 已统一来自现场重算最短路；抽查状态 a=2 loc=1 与新最短路表最大差异为 0。
- 删除数据文件：`data/yuanqi/stage1_site_to_node_road_km.csv`、`data/yuanqi/stage1_node_positions.csv`、`data/yuanqi/stage1_service_weight_site_node.csv`、`data/yuanqi/stage1_site_to_site_road_km.csv`。
- 清理未调用 local functions：`build_currentA_terminal_table`、`build_road_soft_preview`、`build_weighted_h_node_table`、`simulate_road_access_mc`。
- 修改图片文字：入口文件中的道路图、原始分配/道路软分配对比图、风险容量均值分配对比图、容量利用图和联合场景图改为中文；电网绘图函数中的剩余 `IEEE33节点`、英文坐标轴和命令行图片输出提示改为中文。
- 更新 `data/yuanqi/near_stage_msp_README.txt`，删除旧 stage1 路网参考表说明，改为当前两个输入表和现场最短路输出口径。
- 成功运行 MATLAB joint10 离线预览；未运行 Gurobi / MSP；未修改默认保护模块；未新增 `terminal_load_mode`；未接入 roadSoft、currentA 或风险容量均值分配到主 MSP。
- 运行结果：`joint_scenario_summary.csv` 为 350 行；`joint_scenario_site_node.csv` 为 46200 行；风险容量均值分配状态输出为 70 行；失败状态 0；fallback 节点总数 1。
- 图片输出：重新生成 29 张 PNG；抽查 `road_network_layout.png`、`site_node_reachability_a5_loc4.png`、`terminal_loh_currentA_roadSoft_RiskCapMean_uniform_a5_loc4.png`，可见文字已中文化；静态搜索未发现指定英文标签或乱码残留。
- 旧输出检查：旧 OT 输出目录和旧 OT 图片目录均不存在；生成 README 与命令行输出不再包含本次删除的旧输入表名。
- MATLAB 警告：仍有用户偏好文件/工具箱缓存/无效路径/图形初始化警告，包括 `migratePref.txt` 与 `matlabprefs.mat` 权限或内容警告；脚本最终完成并写出输出。
- 未完成事项或待确认：无阻塞事项；建议用户确认是否同步更新 `longtask.md` 的旧路网口径快照。

### 2026-05-15 - 清理 RiskCap-OT 主线并新增 RiskCap-Mean joint10 原型

- 修改 `generate_terminal_loh_wind_mc_preview.m`，将主线从 RiskCap-OT 切换为 RiskCap-Mean；RiskCap-Mean 不使用 KL、tau、reference 或 entropy regularization。
- 新增电网-路网联合 MC：每个终端状态 `(a,loc,lf=7)` 生成 `jointNmc=10` 个 joint scenario，每个 scenario 同时抽电网线路故障和道路边关闭；输出 `joint_scenario_summary.csv` 和 `joint_scenario_site_node.csv`。
- currentA 改为使用 joint MC 汇总后的 `Hbar_node`；roadSoft 改为使用 joint MC 汇总后的 reachability、平均通行代价和 base distance。
- RiskCap-Mean 每个状态每个 priority mode 只求解一次状态级容量分配，生成状态级 TerminalLOH 查表；保留 full-cover-first 逻辑。
- RiskCap-Mean 主成本为 `priority * (0.30*norm_base_distance + 0.40*road_unreliability + 0.30*norm_travel_time)`；服务半径仅作为诊断字段输出。
- 清理旧输出目录 `output_h2/wind_terminal_loh_preview/riskcap_ot/` 和 `output_h2/wind_terminal_loh_preview/figures/riskcap_ot/`；新增 `riskcap_mean/` 和 `figures/riskcap_mean/`。
- 成功运行 MATLAB joint10 原型；未运行 Gurobi / MSP；未修改默认保护模块，未接入主 MSP，未新增正式 `terminal_load_mode`。
- 当前运行参数：`support_hours=2`，`previewMode=joint10`，`jointNmc=10`，`Nmc=10`，`roadNmc=10`，`designWindSpeedVN=25`，`roadDesignWindVN=30`，`riskCapMeanCapacityMode=reserve_fraction`，`riskCapMeanReserveFraction=0.8`，priority modes 为 `uniform` / `key_load_demo`。
- 运行结果：350 行 joint scenario summary，35 个状态每个 10 个 joint scenario；RiskCap-Mean state-priority 输出 70 行，`full_cover_feasible=1` 为 68 行，`uncovered_allowed=1` 为 2 行，失败状态 0。
- uncovered 只出现在 a=6 loc=6 的 node 22，四站 reachability 均为 0，因此是道路可达性不可行导致；RiskCap-Mean uncovered_total min/mean/max 为 0.000000 / 0.280548 / 9.819164 kg。
- currentA 和 roadSoft TerminalLOH_total min/mean/max 均为 0.000000 / 156.855686 / 389.057088 kg；RiskCap-Mean TerminalLOH_total min/mean/max 为 0.000000 / 156.575138 / 379.237924 kg。
- 容量绑定 0 行，最大容量利用率约 0.916088。
- 服务风险指标：全部状态 roadSoft 平均 total_service_risk 为 32.855396；RiskCapMean 在 uniform 下为 26.883651，在 key_load_demo 下为 27.803997。a=5 loc=4 下 roadSoft/RiskCapMean 分别为 65.139491/52.018964（uniform）和 65.139491/55.078429（key_load_demo）。
- 生成 6 张 RiskCap-Mean 图：两张 currentA/roadSoft/RiskCapMean 对比图、两张容量利用图、`joint_scenario_total_H_a5_loc4.png` 和 `joint_scenario_road_closed_edges_a5_loc4.png`。
- MATLAB 仍有用户偏好文件和图形初始化 warning，但 exit code 为 0，输出已生成。
- 后续建议：提高到 `joint50` / `joint200` 做 MC 敏感性；可新增独立 RiskCap-Backup 诊断版观察备用覆盖逻辑。

### 2026-05-15 - RiskCap-OT full-cover-first、generalized KL 与独立 tau 修正

- 在 `generate_terminal_loh_wind_mc_preview.m` 的 RiskCap-OT final-candidate 路径中新增 full-cover-first 逻辑：每个终端状态、每个 priority mode 求解前先做容量/可达性最大流全覆盖可行性检查；全覆盖可行时强制 `u_n=0`；只有不可行时才允许 uncovered。
- 将 RiskCap-OT KL 项从 `tau * sum(y*log((y+eps)/(reference+eps)))` 改为 generalized KL：`tau * sum(y*log((y+eps)/(reference+eps)) - y + reference)`，并同步修改梯度为 `logRatio + y/(y+eps) - 1`。
- 将 `optsWind.riskCapOTTau` 从继承 `optsWind.roadTau=10` 改为独立参数 `0.2`；roadSoft 仍使用 `roadTau`。
- 在 `terminal_loh_by_state_RiskCapOT.csv` 新增 `full_cover_feasible`、`uncovered_allowed`；在 `riskcapot_penalty_by_state.csv` 新增 `full_cover_feasible`、`uncovered_allowed`、`tau_used`、`kl_form`。
- 更新 `RiskCapOT_README.txt` 输出文案，说明 full-cover-first、generalized KL、独立 tau、`u_n` 离线诊断口径和 fast50 原型验证口径。
- 成功运行 MATLAB 离线预览；未运行 Gurobi / MSP；未修改 `main_msp_h2_near.m`、`h2_default_options.m`、`run_h2_with_options.m`、`run_h2_ablation_suite.m`、H2 FA-MSP 主体文件、`load_data_h2_near.m` 或 `near_stage_msp_input.mat`。
- 当前运行参数：`support_hours=2`，`previewMode=fast50`，`Nmc=50`，`roadNmc=50`，`designWindSpeedVN=25`，`roadDesignWindVN=30`，`riskCapOTCapacityMode=reserve_fraction`，`riskCapOTReserveFraction=0.8`，priority modes 为 `uniform` / `key_load_demo`。
- 运行结果：70 行 RiskCap-OT state-priority 输出中 `full_cover_feasible=1` 为 70 行，`uncovered_allowed=1` 为 0 行，`uncovered_total_kg > 0` 为 0 行；`riskcapot_uncovered_nodes.csv` 为 0 行。
- RiskCap-OT TerminalLOH_total min/mean/max 为 0.000000 / 156.518218 / 392.125031 kg；uncovered_total min/mean/max 为 0.000000 / 0.000000 / 0.000000 kg。
- 容量绑定 0 行，最大容量利用率约 0.925551。
- 生成 RiskCap-OT 四张图：`terminal_loh_currentA_roadSoft_RiskCapOT_uniform_a5_loc4.png`、`terminal_loh_currentA_roadSoft_RiskCapOT_key_load_demo_a5_loc4.png`、`riskcapot_capacity_usage_uniform_a5_loc4.png`、`riskcapot_capacity_usage_key_load_demo_a5_loc4.png`。
- MATLAB 仍有用户偏好文件和图形初始化 warning，但 exit code 为 0，输出已生成。

### 2026-05-15 - support_hours 调整为 2h

- 在 `generate_terminal_loh_wind_mc_preview.m` 中显式设置 `opts.support_hours = 2`，位置在 `load_data_h2_near` 调用之前。
- 未修改 `near_stage_msp_input.mat`、`h2_default_options.m`、`load_data_h2_near.m` 或 MSP 保护模块。
- 更新 `terminal_loh_wind_mc_README.txt` 和 `RiskCapOT_README.txt` 输出文案，记录本次离线预览使用 `support_hours=2 h`。
- 重新运行 `generate_terminal_loh_wind_mc_preview.m`；未运行 Gurobi / MSP。
- 运行输出：currentA / roadSoft / RiskCap-OT TerminalLOH_total min/mean/max 均为 0.000000 / 156.518218 / 392.125031 kg；RiskCap-OT uncovered_total min/mean/max 为 0.000000 / 0.000000 / 0.000000 kg；RiskCap-OT failed state count = 0；fallback_node_count total = 0。
- RiskCap-OT 容量绑定 0 行，最大容量利用率约 0.769。
- MATLAB 仍有用户偏好文件访问、工具箱路径缓存和无效路径 warning，但 exit code 为 0，输出已生成。

### 2026-05-15 - RiskCap-OT 第一版离线原型

- 在 `generate_terminal_loh_wind_mc_preview.m` 中加入 RiskCap-OT 第一版离线模块，保留旧入口文件名，未新建独立 RiskCap-OT 主程序。
- 当前预览统一输出 wind_mc 电网侧节点失负荷、currentA TerminalLOH、roadSoft TerminalLOH、RiskCap-OT TerminalLOH，以及 currentA / roadSoft / RiskCap-OT 对比表。
- RiskCap-OT 模型口径：`C_i,n = road_service_cost_i,n`，`Cap_i = x_cap_i`，`priority_n=1`，KL-style 项为 `tau*y*log((y+eps)/(reference+eps))`，`reference` 基于 `H_node * capacityWeight * reachability` 构造，`M=10*max finite road_service_cost`。
- 不可达 `reachability=0` 的 site-node 对强制 `y_i,n=0`；全不可达或容量不足的节点需求进入 `u_n`，不 fallback 到 currentA。
- 为 RiskCap-OT 原型验证将 `optsWind.Nmc` 从 200 临时改为 50，将 `optsWind.roadNmc` 从 200 临时改为 50；`roadDesignWindVN=30`，电网侧 `designWindSpeedVN=25`。
- 输出目录新增 `output_h2/wind_terminal_loh_preview/riskcap_ot/`，生成 RiskCap-OT 五个要求 CSV、`RiskCapOT_README.txt` 和一个额外 `riskcapot_penalty_by_state.csv` 诊断表；未新增 RiskCap-OT figure。
- 成功运行 MATLAB 离线预览；未运行 Gurobi / MSP。
- 运行结果：35 个状态全部成功或直接零需求处理，失败状态 0；RiskCap-OT TerminalLOH_total min/mean/max 为 0.000000 / 440.199906 / 750.000000 kg；uncovered_total min/mean/max 为 0.000000 / 185.872967 / 818.500123 kg。
- uncovered 出现在 16 个状态；最大为 a=6, loc=5，818.500123 kg。`riskcapot_uncovered_nodes.csv` 共 371 行，涉及节点 2-33。
- 容量绑定出现在 19 个状态；a=5/6 所有 loc 均四站容量绑定，a=4 的 loc=1/2/3/4/5 出现部分或全部站点绑定。
- RiskCap-OT 与 roadSoft 差异明显：最大总量差异为 818.500123 kg，平均总量差异为 -185.872967 kg；`RiskCapOT + uncovered` 与 roadSoft 总量最大平衡误差约 `1e-08` kg。
- 未修改默认保护模块，未新增正式 `terminal_load_mode`，未接入主 MSP，未改变 currentA 定义、roadSoft 分配公式、wind_mc 电网故障率公式、MSP 当前正式 TerminalLOH 口径或 fallback 逻辑。
- 由于 MC 次数临时降低，本次结果只能作为 RiskCap-OT 程序原型验证，不应作为正式论文高精度结果；建议后续恢复 `Nmc=200`、`roadNmc=200` 或更高 MC 次数重跑。

### 2026-05-14 - figure 中文化覆盖 road 与电网图

- 修改 `generate_terminal_loh_wind_mc_preview.m` 的 road figure 输出逻辑：`road_network_layout.png` 保持新增 a=5、位置=4 的台风中心和中等风圈，road 可达图坐标轴补为中文方向描述，road 对比图将可见 `TerminalLOH` 文案改为“终端需氢量”。
- 修改 `fa_h2/fuzhu/terminalLoh_windmc/draw` 下电网 figure 绘图函数，将 layout、storm state、line metric、node outage、site bar、summary、selected line diagnostics 的标题、坐标轴、图例、色条和必要注释改为中文。
- 重新运行 `generate_terminal_loh_wind_mc_preview.m`，刷新 `figures/road` 4 张 road PNG 和 `figures/elec_grid` 19 张电网 PNG；未运行 Gurobi / MSP。
- 抽查 `layout_overview.png`、`storm_state_a5_loc4.png`、`line_failureprob_a5_loc4_rmid.png`、`node_outage_prob_a5_loc4_rmid.png`、`terminal_loh_bar_a5_loc4.png`、`selected_lines_diagnostics_a5_loc4_rmid.png`、`summary_by_a.png`、`site_node_reachability_a5_loc4.png`、`terminal_loh_currentA_vs_roadSoft_a5_loc4.png`，图内主要可见文本已中文化。
- 未修改默认保护模块，未新增 `terminal_load_mode`，未接入 roadSoft / wind_mc 到正式 MSP，未改变 TerminalLOH 主程序口径、roadSoft 分配公式、wind_mc 电网侧故障率公式或 fallback 逻辑。
- 本次运行输出：currentA 和 roadSoft TerminalLOH_total min/mean/max 均为 0.000000 / 627.622960 / 1575.229523 kg，fallback_node_count total = 0。
- MATLAB 运行存在用户偏好文件访问警告、工具箱路径缓存警告和一个无效路径警告，但 exit code 为 0，输出文件已生成。

### 2026-05-14 - road 图中文化与代表性台风位置

- 修改 `generate_terminal_loh_wind_mc_preview.m` 的 road figure 输出逻辑。
- `road_network_layout.png` 新增 a=5、位置=4 的台风中心，并绘制当前 road baseline 使用的中等风圈。
- `road_network_layout.png`、`road_edge_closeprob_a5_loc4.png`、`site_node_reachability_a5_loc4.png`、`terminal_loh_currentA_vs_roadSoft_a5_loc4.png` 的图标题、坐标轴、图例和 colorbar 标题改为中文。
- 保持 `road_edge_closeprob_a5_loc4.png`、`site_node_reachability_a5_loc4.png`、`terminal_loh_currentA_vs_roadSoft_a5_loc4.png` 的信息重点不变，未强制添加台风元素。
- 运行 `generate_terminal_loh_wind_mc_preview.m` 重新生成离线预览输出和 road figures；未运行 Gurobi / MSP。
- 未修改默认保护模块，未新增 `terminal_load_mode`，未改变 TerminalLOH 主程序口径、roadSoft 分配公式、wind_mc 电网侧故障率公式或 fallback 逻辑。
- 本次运行输出：currentA 和 roadSoft TerminalLOH_total min/mean/max 均为 0.000000 / 627.622960 / 1575.229523 kg，fallback_node_count total = 0。
- MATLAB 运行存在用户偏好文件访问警告，但 exit code 为 0，输出文件已生成。

### 2026-05-14 - 删除敏感性诊断脚本并设置道路 VN=30

- 删除 `diagnose_roadsoft_fault_rate_sensitivity.m`。
- 修改 `generate_terminal_loh_wind_mc_preview.m`，将 `optsWind.roadDesignWindVN` 从 25 改为 30，并同步更新 README 文案中的道路 VN 描述。
- 保持 `optsWind.roadNmc = 200` 不变。
- 未修改 `main_msp_h2_near.m`、`h2_default_options.m`、`run_h2_with_options.m`、`run_h2_ablation_suite.m`、H2 FA-MSP 主体文件、`load_data_h2_near.m`、`near_stage_msp_input.mat`。
- 未新增 `terminal_load_mode`，未接入 roadSoft / wind_mc 到正式 MSP，未改变 TerminalLOH 主程序口径、roadSoft 分配公式、wind_mc 电网侧故障率公式或 fallback 逻辑。
- 未运行 MATLAB / Gurobi / MSP；仅做文件存在性和 `rg` 只读校验。
- 注意：现有 `output_h2/wind_terminal_loh_preview` 输出尚未重新生成，仍不代表本次 VN=30 默认值的新运行结果。

### 2026-05-14 - roadSoft 道路故障率参数敏感性诊断

- 新增独立脚本 `diagnose_roadsoft_fault_rate_sensitivity.m`。
- 运行 MATLAB 离线诊断脚本，roadNmc 固定为 200，测试 roadDesignWindVN=25/30/35/40，只关注 a=6 loc=5/6。
- 新增 `output_h2/wind_terminal_loh_preview/road/fault_rate_sensitivity_a6_loc5_loc6.csv`。
- 新增 `output_h2/wind_terminal_loh_preview/road/fault_rate_sensitivity_README.txt`。
- 未修改 `main_msp_h2_near.m`、`h2_default_options.m`、`run_h2_with_options.m`、`run_h2_ablation_suite.m`、H2 FA-MSP 主体文件、`load_data_h2_near.m`、`near_stage_msp_input.mat`。
- 未新增 `terminal_load_mode`，未接入 roadSoft / wind_mc 到正式 MSP，未改变 TerminalLOH 主程序口径、roadSoft 分配公式或 wind_mc 电网侧故障率公式。
- 主要结果：a=6 loc=5 fallback_node_count 从 VN=25 的 12 降为 VN=30/35/40 的 0；a=6 loc=6 fallback_node_count 从 VN=25 的 17 降为 VN=30/35/40 的 0。
- pClose 结果：loc5 mean 从 0.848162 降至 0.532455/0.304716/0.159442；loc6 mean 从 0.916964 降至 0.592357/0.348922/0.191208。VN=25 下 pClose=1 边数 loc5=21、loc6=22；VN=30/35/40 下均为 0。
- 解释：当前程序中 `riskFactor=pClose`，因此调高 roadDesignWindVN 不仅降低道路关闭概率，也同步降低未关闭道路的 slowdown。fallback 明显下降说明 VN=25 对道路侧偏保守。
- 后续建议：可单独评估更高 roadDesignWindVN；也可考虑把 slowdown 风险因子从 pClose 中解耦。当前仅提出建议，未接入 MSP。

### 2026-05-14 - 诊断 a=6 loc=5/6 roadSoft fallback 偏高

- 基于已有离线预览 CSV 做静态诊断，未运行 MATLAB / Gurobi / MSP。
- 新增 `output_h2/wind_terminal_loh_preview/road/fallback_diagnostics_a6_loc5_loc6.csv`。
- 新增 `output_h2/wind_terminal_loh_preview/road/fallback_diagnostics_README.txt`。
- 未修改 `main_msp_h2_near.m`、`h2_default_options.m`、`run_h2_with_options.m`、`run_h2_ablation_suite.m`、H2 FA-MSP 主体文件、`load_data_h2_near.m`、`near_stage_msp_input.mat`。
- 未新增 `terminal_load_mode`，未接入 roadSoft / wind_mc 到正式 MSP，未改变 TerminalLOH、roadSoft、wind_mc、fallback 公式或含义。
- 主要结论：a=6 loc=5 的计数 fallback 节点为 2,3,4,5,6,19,21,22,23,26,27,29；a=6 loc=6 的计数 fallback 节点为 5,6,7,8,9,10,11,12,13,15,16,17,28,29,30,32,33。所有计数 fallback 节点对四站 reachability_probability 均为 0。
- 原因判断：主要是极端 road close probability 导致 road accessibility collapse。loc5 更像 pClose=1 边造成的拓扑割裂；loc6 多数节点被 pClose=1 边割裂，少数节点存在理论可通路径但路径开通概率极低，200 次 MC 中观测为 0。不是 service cost 公式本身触发。
- 后续建议：可在后续单独尝试 small/mid/large Rmax 加权 road accessibility，作为可达性平滑和鲁棒性检查；本次未实现。

### 2026-05-14 - 初始化 log.md

- 创建 `log.md`。
- 用于记录 Codex 每次执行后的真实修改、运行结果、指标、报错和建议。

### 2026-05-15 - 清理 generate_terminal_loh_wind_mc_preview.m 中停用的 RiskCap-OT 死代码

- 修改文件：`generate_terminal_loh_wind_mc_preview.m`；`codex_rule/log.md`。
- 新增文件：无。
- 删除/清理的旧 local functions：`build_riskcap_ot_preview`、`get_riskcap_ot_capacity`、`extract_riskcap_state_inputs`、`solve_riskcap_ot_state`、`build_riskcap_reference`、`riskcap_ot_objective`、`build_currentA_roadSoft_RiskCapOT_compare`、`write_riskcap_ot_tables`、`build_riskcap_ot_preview_final`、`get_riskcap_ot_capacity_final`、`build_riskcap_priority_settings`、`select_riskcap_key_nodes`、`extract_riskcap_state_inputs_final`、`build_riskcap_cost_components_final`、`solve_riskcap_ot_state_final`、`build_riskcap_reference_final`、`riskcap_ot_objective_final`、`service_risk_metric_row`、`build_currentA_roadSoft_RiskCapOT_compare_final`、`write_riskcap_ot_tables_final`、`export_riskcap_ot_figures`、`plot_currentA_roadSoft_RiskCapOT_compare`、`plot_riskcap_capacity_usage`、`write_riskcap_ot_readme_final`、`write_riskcap_ot_readme`。
- 保留的通用函数：`riskcap_y_index`、`riskcap_full_cover_feasibility`、`normalize_riskcap_component`、`roadsoft_allocation_matrix`、`cell_rows_to_table`、`priority_vector_from_settings`。
- 是否修改默认保护模块：否；未修改 `main_msp_h2_near.m`、`h2_default_options.m`、`run_h2_with_options.m`、`run_h2_ablation_suite.m`、H2 FA-MSP 主体文件、`load_data_h2_near.m` 或 `near_stage_msp_input.mat`。
- 是否接入 MSP：否。
- 是否改变 RiskCap-Mean 模型：否；仍为 joint10、full-cover-first、`Cap_i=0.8*x_cap_i`、三项线性服务风险成本。
- 是否改变 joint10 联合 MC 逻辑：否。
- 是否改变 currentA / roadSoft：否。
- 是否清理旧输出目录：是；运行后 `output_h2/wind_terminal_loh_preview/riskcap_ot/` 与 `output_h2/wind_terminal_loh_preview/figures/riskcap_ot/` 均不存在。
- 关键词残留检查：`generate_terminal_loh_wind_mc_preview.m` 中 `RiskCapOT`、`riskCapOT`、`generalized_KL`、`riskCapOTTau`、`riskCapOTPenaltyM`、`build_riskcap_ot`、`solve_riskcap_ot`、`write_riskcap_ot`、`RiskCapOT_README`、`KL`、`tau`、`entropy`、`reference_i,n`、`roadSoft reference` 均无残留；仅保留两个 `riskcap_ot` 字面量，用于按任务要求删除旧输出目录。
- 是否运行 MATLAB：是；命令 `matlab -batch "cd('C:/Users/chaos/Desktop/biye/test/testH2_v2'); generate_terminal_loh_wind_mc_preview"` exit code 为 0。
- MATLAB 运行警告：仍有用户偏好文件/工具箱缓存/无效路径/图形初始化警告，包括 `migratePref.txt` 与 `matlabprefs.mat` 权限或内容警告；脚本最终完成并写出输出。
- 主要输出检查：`riskcap_mean` 输出目录存在；`figures/riskcap_mean` 图目录存在；`terminal_loh_by_state_RiskCapMean.csv`、`terminal_loh_allocation_RiskCapMean.csv`、`riskcapmean_capacity_usage.csv`、`riskcapmean_uncovered_nodes.csv`、`terminal_loh_currentA_roadSoft_RiskCapMean_compare.csv`、`riskcapmean_service_risk_metrics.csv`、`riskcapmean_cost_components.csv`、`riskcapmean_priority_settings.csv`、`joint_scenario_summary.csv`、`joint_scenario_site_node.csv`、`RiskCapMean_README.txt` 均存在。
- 图输出检查：6 张 RiskCap-Mean 图均存在，包括两张 currentA/roadSoft/RiskCapMean 对比图、两张容量利用图、`joint_scenario_total_H_a5_loc4.png`、`joint_scenario_road_closed_edges_a5_loc4.png`。
- 关键结果：`joint_scenario_summary.csv` 为 350 行，a=5 loc=4 有 10 个 scenario；RiskCap-Mean 状态输出 70 行，`full_cover_feasible=1` 为 68 行，`uncovered_allowed=1` 为 2 行，失败状态 0；`uncovered_total_kg` mean/max 为 0.280547535273008 / 9.81916373455527；`riskcapmean_uncovered_nodes.csv` 为 2 行；容量绑定 0 行，最大容量利用率 0.916088276387058。
- service risk 检查：uniform 下 currentA/roadSoft/RiskCapMean 平均 total_service_risk 为 32.6121895286346 / 32.8553964291865 / 26.8836514614153；key_load_demo 下为 32.6121895286346 / 32.8553964291865 / 27.8039971221159。
- 未完成事项或真实报错：无阻塞报错；首次重跑曾因脚本编码导致第 1623 行文本字符错误，已修正为 MATLAB 可解析文本后重新运行成功。
- 是否建议更新 core.md：否。
- 是否建议更新 longtask.md：否；本次只是死代码清理，不改变阶段路线。

### 2026-07-06 - WDRO-TerminalLOH 第二阶段 A：W=3 look-ahead 台风路径生成器

- 本次只在 `terminalLoh_wdro/` 下新增和修改文件，未修改 MSP 主模型、`fa_h2/` 主流程、`load_data_h2_near.m`、`h2_default_options.m`、`near_stage_msp_input.mat` 或原始 `data/` 转移表。
- 新增代码文件：`terminalLoh_wdro/src/run_lookahead_W3_path_generation_h2.m`、`build_lookahead_location_ext_h2.m`、`build_lookahead_transition_loc_h2.m`、`build_lookahead_transition_intensity_h2.m`、`sample_lookahead_paths_W3_h2.m`、`write_lookahead_path_diagnostics_h2.m`。
- 新增文档：`terminalLoh_wdro/docs/README_lookahead_W3_path_generation.md`。
- 新增配置输出：`terminalLoh_wdro/config/lookahead_location_ext.csv`、`lookahead_transition_loc_W3.csv`、`lookahead_transition_loc_delta_kernel_W3.csv`、`lookahead_transition_intensity_W3.csv`、`lookahead_stage2_config_W3.csv`。
- 新增 Stage 2A 输出：`terminalLoh_wdro/output/stage2_lookahead_W3/lookahead_input_inspection.txt`、`lookahead_transition_loc_check.csv`、`lookahead_transition_intensity_check.csv`、`lookahead_path_table.csv`、`lookahead_path_summary.csv`、`lookahead_path_readme.txt`。
- 输入检查结果：`data/location.csv` 为 7 x 7 转移矩阵，原始 `loc_id=1:7`；`data/intensity.csv` 为 6 x 6；`data/landfall_7.csv` 为 8 x 8；lf=7 源状态集合为 `a=2:6, loc=1:7, lf=7`，共 35 个状态。
- 原始 `data/location.csv` 没有坐标字段；loc 坐标来自现有 windmc 的 `build_h2_spatial_layout_preview.m`，原始 x 坐标为 `[-50,-33,-17,0,17,33,50]`，y 坐标均为 0。
- W=3 扩展后 `loc_id=-2:10`，已建立 `loc_id,row_id` 映射；`loc_id` 可为负数或 0，MATLAB 内部索引使用连续正整数 `row_id`。
- loc 转移表未改原始 `data/location.csv`；本模块为 halo loc 构造 look-ahead 专用位移核，输出到 `lookahead_transition_loc_delta_kernel_W3.csv`，并在扩展 loc 线上应用；越过最外侧 halo 的概率保留在边界 halo loc。
- 转移概率检查：13 个扩展 loc 的 loc 转移概率和均为 1，6 个强度状态的强度转移概率和均为 1，诊断状态均为 OK。
- 运行方式：`cd('C:/Users/chaos/Desktop/biye/test/testH2_v2'); run('terminalLoh_wdro/src/run_lookahead_W3_path_generation_h2.m');`
- 运行结果：W=3，P=20，random_seed=20260706；35 个 lf=7 状态各生成 20 条路径，共 700 条路径；`lookahead_path_table.csv` 为 2100 行。
- 路径诊断：左侧 halo 访问次数 238，右侧 halo 访问次数 418；终端 loc 最小值 -2，最大值 10。
- 本阶段未抽电网故障、未抽道路故障、未生成 D/A/C 后果样本、未运行 WDRO-LP、未接入 MSP、未修改原 MSP 状态空间，且未使用人工影响衰减系数。
- 未完成事项：下一步需要在 W=3 台风路径条件下进行电网/道路灾害抽样，并把多窗口后果聚合成 WDRO 所需的 D、A、C 样本表。

### 2026-07-07 - 整理 WDRO look-ahead W=3 配置为三主表

- 本次只修改 `terminalLoh_wdro/` 下文件，并更新 `codex_rule/log.md`；未修改 `main_msp_h2_near.m`、`run_h2_with_options.m`、`load_data_h2_near.m`、`h2_default_options.m`、`fa_h2/` 主流程文件、`data/location.csv`、`data/intensity.csv`、`data/landfall_7.csv` 或 `data/yuanqi/near_stage_msp_input.mat`。
- config 简化前根目录文件包括：`lookahead_location_ext.csv`、`lookahead_stage2_config_W3.csv`、`lookahead_transition_intensity_W3.csv`、`lookahead_transition_loc_delta_kernel_W3.csv`、`lookahead_transition_loc_W3.csv`、`README_config.md`。
- config 简化后根目录只保留三个主配置 CSV 和 README：`lookahead_intensity_W3.csv`、`lookahead_location_W3.csv`、`lookahead_window_W3.csv`、`README_config.md`。
- 新主表字段：`lookahead_intensity_W3.csv` 为 `from_a,to_a,prob`；`lookahead_location_W3.csv` 为 `from_loc_id,to_loc_id,prob`；`lookahead_window_W3.csv` 为 `key,value`。
- 中间表和历史诊断表已移动或写入 `terminalLoh_wdro/output/stage2_lookahead_W3/config_diagnostics/`：`lookahead_location_ext.csv`、`lookahead_stage2_config_W3.csv`、`lookahead_transition_intensity_W3.csv`、`lookahead_transition_loc_delta_kernel_W3.csv`、`lookahead_transition_loc_W3.csv`。
- 修改脚本：`terminalLoh_wdro/src/run_lookahead_W3_path_generation_h2.m` 改为创建/读取三主表，并将 row_id/坐标映射和 delta kernel 只写入 `config_diagnostics/`；`terminalLoh_wdro/src/sample_lookahead_paths_W3_h2.m` 改为使用 `config.lf_terminal`、`config.loc_min`、`config.loc_max` 和新主表；`terminalLoh_wdro/src/build_lookahead_location_ext_h2.m` 改为使用 `config.halo_width` 作为 loc halo 宽度。
- 更新 `terminalLoh_wdro/config/README_config.md`，说明三主表对应 MSP 阶段 intensity/location/landfall-window 思路，但只服务于 WDRO look-ahead，不修改原 MSP 状态空间和原始概率表，W 继续用 `tau` 表示。
- 已重新运行路径生成器两次：第一次生成新三主表，第二次在旧命名 config 根目录文件移出后确认脚本可完全依赖三主表运行。
- 运行命令：`cd('C:/Users/chaos/Desktop/biye/test/testH2_v2'); run('terminalLoh_wdro/src/run_lookahead_W3_path_generation_h2.m');`
- 重新运行结果：`lookahead_path_table.csv` 为 2100 行，`lookahead_path_summary.csv` 为 35 行；左侧 halo 访问 238 次，右侧 halo 访问 418 次；终端 loc 范围为 -2 到 10。
- 概率检查：13 个 loc from 状态全部通过，prob sum 范围约 0.999999999999999 到 1；6 个 intensity from 状态全部通过，prob sum 均为 1。
- 本次未抽电网/道路灾害、未生成 D/A/C、未运行 WDRO-LP、未接入 MSP。

### 2026-07-07 - 补充 lookahead_location_W3 配置说明

- 更新 `terminalLoh_wdro/config/README_config.md`，补充说明 `lookahead_location_W3.csv` 不是原 MSP 位置转移矩阵的逐行复制，而是从 `data/location.csv` 提取经验位移核并应用到扩展位置集合 `loc=-2:10`。
- 说明该处理用于避免边界位置被截断，使 W=3 look-ahead 路径能够进入左右 halo 区域。
- 未修改 MSP 主模型、原始 `data/` 概率表、未生成 D/A/C、未运行 WDRO-LP。

### 2026-07-07 - WDRO 距离主方法改为 DA，并新增 DAC_maskedC

- 本次只修改 `terminalLoh_wdro/` 下文件，并更新 `codex_rule/log.md`；未修改 `main_msp_h2_near.m`、`run_h2_with_options.m`、`load_data_h2_near.m`、`h2_default_options.m`、`fa_h2/` 主流程文件、`data/` 原始概率表或 `data/yuanqi/near_stage_msp_input.mat`。
- 修改 `terminalLoh_wdro/src/build_wdro_distance_matrix_h2.m`：新增主距离 `DA`，定义为 `w_D*d_D + w_A*d_A`，默认权重 `w_D=0.7`、`w_A=0.3`；A 作为有限离散场景原子中的二进制可达性矩阵，不做连续扰动。
- 修改 `build_wdro_distance_matrix_h2.m`：新增扩展距离 `DAC_maskedC`，默认权重 `w_D=0.6`、`w_A=0.25`、`w_C=0.15`；C 只在两个场景共同可达的 site-node 对上比较，避免 unreachable 事件被 A 和 C 重复计量。
- 原 `DAC` 保留为 legacy/unmasked compatibility mode，输出标签为 `DAC_legacy_unmasked`，默认运行不再包含该模式。
- 修改 `terminalLoh_wdro/src/run_terminal_loh_wdro_preview_h2.m`：默认 `distance_modes={'D_only','DA','DAC_maskedC'}`，默认输出目录改为 `terminalLoh_wdro/output/stage1_single_window_DA_update/`。
- 修改 `terminalLoh_wdro/src/build_terminal_loh_wdro_from_joint_samples_h2.m`：扩展 `wdro_distance_matrix_summary.csv` 字段，新增 `d_diag_max_abs`、`d_symmetry_max_abs`、`A_binary_ok`、`A_unique_values`、`A_total_reachable_*`、`C_unreachable_*`、`C_masked_pair_count/share` 和各距离权重；`wdro_distance_matrix_summary.csv` 现在每个状态/距离模式一行，不再按 rho 重复。
- 修复 `build_rho_sensitivity_summary` 中 MATLAB `innerjoin` 自动列名导致的汇总错误，改为按排序后的状态直接比较相邻 rho。
- 新增文档 `terminalLoh_wdro/docs/README_WDRO_distance_DA.md`，说明 DA 主距离、有限离散支持集、不会产生 `A=0.3` 半可达状态、为什么 C 不进入主距离、`DAC_maskedC` 和 rho 选择。
- 更新 `terminalLoh_wdro/docs/README_WDRO_preview.md` 和新输出目录下 `WDRO_README.txt`，明确 DA 是主方法，`DAC_maskedC` 是扩展敏感性方法，legacy DAC 不推荐作为正式主方法。
- 已完整运行 35 个 lf=7 状态、3 个距离模式、4 个 rho，共 420 个 LP；首次运行在所有 LP 后的 rho 汇总阶段因旧 `innerjoin` 列名报错，修复后完整重跑成功。
- 新输出文件位于 `terminalLoh_wdro/output/stage1_single_window_DA_update/`：`terminal_loh_by_state_WDRO.csv`、`terminal_loh_allocation_WDRO.csv`、`wdro_distance_matrix_summary.csv`、`wdro_rho_sensitivity_summary.csv`、`WDRO_README.txt`。
- 运行检查：`terminal_loh_by_state_WDRO.csv` 为 420 行，`D_only`/`DA`/`DAC_maskedC` 各 140 行；求解状态 `OPTIMAL=420`；负 TerminalLOH 行数 0，容量超限行数 0。
- 距离检查：`wdro_distance_matrix_summary.csv` 为 105 行，三种模式各 35 行；最大对角线绝对值 0，最大对称误差 0，最小距离 0，最大距离约 0.999999999997533。
- A 检查：`A_binary_ok=1` 为 105/105 行，`A_unique_values=1`，未发现 A 非二进制异常。
- C 诊断：48/105 行没有 unreachable C 条目，57/105 行的 unreachable C 诊断含 `Inf`；DA 不使用 C，`DAC_maskedC` 只在共同可达位置比较 C，未让 unreachable 的 `Inf` 进入 masked cost 差异。
- `DAC_maskedC` 的 `C_masked_pair_share` 在本次 R=10 样本中为 1，表示每个状态的 scenario pair 都存在至少一个共同可达 site-node 对参与 masked C 比较。
- DA 的 rho 汇总：rho=0/0.02/0.05/0.1 时 TerminalLOH_total_mean 分别约为 264.733819 / 258.765318 / 251.882985 / 236.345482 kg；对应 `states_with_total_decrease_vs_previous_rho` 为 0 / 9 / 13 / 15。当前 R=10 下 rho 增大不保证 TerminalLOH 单调增加，需在 W=3、R=50/100 和样本外测试中继续判断。
- 本次未接入 MSP、未修改原 MSP TerminalLOH、未生成电网/道路新灾害样本、未生成 D/A/C look-ahead 样本、未新增 CVaR。

### 2026-07-07 - 补充 WDRO 距离中道路可达但变慢的说明

- 仅修改 `terminalLoh_wdro/` 下文档、`build_wdro_distance_matrix_h2.m` 顶部代码注释，以及 `codex_rule/log.md`；未修改 MSP 主流程、原始 `data/` 文件或 TerminalLOH 接口。
- 更新 `terminalLoh_wdro/docs/README_WDRO_distance_DA.md`、`README_WDRO_preview.md`、`README_lookahead_W3_path_generation.md`、`terminalLoh_wdro/config/README_config.md` 和 `terminalLoh_wdro/output/stage1_single_window_DA_update/WDRO_README.txt`。
- 补充说明：`A` 只能表示二进制可达性，`A=1` 为存在可行服务路径，`A=0` 为完全不可达，不允许用 `A=0.3` 表示半可达。
- 补充说明：道路因积水、拥堵、倒树、绕行、限速等仍可通行但变慢时，应保持 `A=1`，并通过更大的 `C` 表示服务成本、通行阻抗或通行时间增加。
- 补充说明：DA 主距离 `xi=(D,A)` 不使用 C；`DAC_maskedC` 只比较两个场景共同可达位置的 C，一个可达、一个不可达时差异只由 A 表达，unreachable 侧的 `Inf` 或大 M 不进入 masked C 距离。
- 本次未改变距离计算逻辑，未重跑 LP，未生成新 D/A/C 样本，未新增 CVaR，未接入 MSP。

### 2026-07-07 - Stage 2B1 W=3 小样本 D/A/C 后果生成与诊断

- 本次只在 `terminalLoh_wdro/` 下新增/修改文件，并更新 `codex_rule/log.md`；未修改 `main_msp_h2_near.m`、`run_h2_with_options.m`、`load_data_h2_near.m`、`h2_default_options.m`、`fa_h2/` 主流程文件、`fa_h2/fuzhu/eval_terminal_loh_h2.m`、`fa_h2/fuzhu/terminal_value_and_subgradient_h2.m`、原始 `data/` 文件或 `data/yuanqi/near_stage_msp_input.mat`。
- 新增代码文件：`terminalLoh_wdro/src/run_lookahead_W3_B1_build_DAC_samples_h2.m`、`build_lookahead_W3_DAC_samples_h2.m`、`aggregate_W3_DAC_outcomes_h2.m`、`write_lookahead_W3_B1_diagnostics_h2.m`。
- 新增文档：`terminalLoh_wdro/docs/README_lookahead_W3_B1_DAC_samples.md`。
- 新输出目录：`terminalLoh_wdro/output/stage2_lookahead_W3_B1_DAC_samples/`。
- 输出文件：`lookahead_scenario_site_node.csv`、`lookahead_scenario_summary.csv`、`lookahead_D_total_distribution_summary.csv`、`lookahead_reachability_summary.csv`、`lookahead_cost_summary.csv`、`README_B1_DAC_samples.txt`。
- 输入：读取 `terminalLoh_wdro/output/stage2_lookahead_W3/lookahead_path_table.csv`，以及 `terminalLoh_wdro/config/lookahead_window_W3.csv`、`lookahead_location_W3.csv`、`lookahead_intensity_W3.csv`；只读复用 `fa_h2/fuzhu/terminalLoh_windmc` 的风速/脆弱性函数和现有道路/电网口径。
- 样本设置：`P_B1=10`、`M_B1=3`、`R_B1=30`，`random_seed_B1=20260707`；每个 lf=7 状态取 Stage 2A 路径表中前 10 条路径，每条路径抽 3 个 damage 样本。
- 生成口径：每个 tau 抽 Rmax、电网线路故障、道路关闭和道路慢行；`D_n=sum_tau D_{n,tau}`；`A` 保持 0/1，`A=1` 表示存在可行服务路径，`A=0` 表示完全不可达；道路可达但变慢通过更大的 `C` 表达，不使用 `A=0.3` 等半可达值。
- W=3 聚合口径：对节点有需求的关键窗口，若站点到节点始终可达则 `A_i,n=1`，否则 `A_i,n=0`；若 `A_i,n=1`，`C_i,n` 为可达窗口平均服务成本/通行阻抗；若 `A_i,n=0`，`C_i,n=Inf`，供后续 masked C 距离跳过。
- 运行方式：`cd('C:/Users/chaos/Desktop/biye/test/testH2_v2'); run('terminalLoh_wdro/src/run_lookahead_W3_B1_build_DAC_samples_h2.m');`
- 已运行 B1 脚本两次确认当前代码可运行；未运行 WDRO-LP，未调用 Gurobi，未接入 MSP，未新增 CVaR。
- 输出规模检查：识别 35 个 lf=7 状态；`lookahead_scenario_summary.csv` 为 1050 行；每个状态 R=30；`lookahead_scenario_site_node.csv` 为 138600 行，等于 `35*30*4*33`。
- A 检查：`reachable` 只有 0/1，计数为 `0:30911`、`1:107689`；半可达值计数 0；`lookahead_reachability_summary.csv` 中 `A_binary_ok` 全部通过。
- 道路/电网诊断：含慢行道路的 scenario 数 668；含完全不可达 site-node 对的 scenario 数 517；最大 blocked road count 为 69，最大 slow road count 为 104，最大 failed power line count 为 81；`slow_road_count_total=32448`。
- C 诊断：不可达位置 `C=Inf` 计数总计 30911；可达但变慢由 `A=1` 和更大的 `C` 表示。
- D 诊断：`D_total_max_to_mean` 最大值为 30；超过 5 的状态 7 个，超过 10 的状态 5 个。需要人工关注的高比值状态包括 `(a,loc,lf)=(2,5,7)`、`(2,6,7)`、`(2,1,7)`、`(2,3,7)`、`(2,4,7)`、`(3,6,7)`、`(3,1,7)`，主要是低强度状态均值较小但偶发故障造成比值偏高。
- 最近写入范围检查未发现禁止文件被修改；仅观察到项目根目录已有 `terminalLoh_wdro (3).zip`、`terminalLoh_wdro (4).zip` 在近 3 小时内有时间戳，但本任务未处理这些 zip。
- 后续建议：Stage 2B2 扩大样本规模到 R=200 或 R=500，并在确认 D/A/C 诊断稳定后再进入 W=3 WDRO 求解。

### 2026-07-07 - Stage 2B1 C 定义修正与实现忠实性审计

- 本次只修改 `terminalLoh_wdro/` 下 B1 相关代码、文档、输出诊断，并更新 `codex_rule/log.md`；未修改 MSP 主流程文件、`fa_h2/` 主模型文件、原始 `data/` 文件或 MSP TerminalLOH 接口。
- 审计发现旧 B1 中 `scenario_service_cost` 使用 `stage1Road.site_to_node_road_km(i,n) + dist(n)`，其中 `dist(n)` 已经是当前道路状态下从站点锚点到节点的 Dijkstra 最短路成本，`stage1Road.site_to_node_road_km` 是基准最短路成本，因此存在基准距离重复计量。
- 已修正 C 定义：`scenario_service_cost = dist(n)`；旧口径 `baseCost + dist(n)` 仅保留为诊断字段 `scenario_service_cost_before_fix`，新增 `scenario_service_delay=max(0, C-baseCost)` 用于延误诊断。
- 修改代码：`terminalLoh_wdro/src/build_lookahead_W3_DAC_samples_h2.m`、`aggregate_W3_DAC_outcomes_h2.m`、`write_lookahead_W3_B1_diagnostics_h2.m`。
- 修改文档/输出诊断：`terminalLoh_wdro/docs/README_lookahead_W3_B1_DAC_samples.md`、`terminalLoh_wdro/output/stage2_lookahead_W3_B1_DAC_samples/README_B1_DAC_samples.txt`、`implementation_audit_B1.txt`、`lookahead_cost_summary.csv`。
- 重新运行 B1：是；运行 `run('terminalLoh_wdro/src/run_lookahead_W3_B1_build_DAC_samples_h2.m')` 成功完成。未运行 WDRO-LP，未调用 Gurobi，未接入 MSP，未新增 CVaR。
- 修正后输出规模保持不变：`lookahead_scenario_site_node.csv` 为 138600 行，`lookahead_scenario_summary.csv` 为 1050 行，35 个 lf=7 状态每个 R=30。
- C 修正前后诊断：reachable 有限 site-node 样本的总体均值由 38.8012592789 降至 20.3585021511；总体最大值由 123.584066233 降至 105.456376083。
- A 检查：`reachable` 仍全部为 0/1；半可达值计数 0；`reachable=1` 且 `C=Inf` 的计数为 0；unreachable 的 `C=Inf` 未进入 reachable 成本统计。
- D 来源：基于 `load_data_h2_near` 的节点负荷、供电失效、`support_hours`、燃料电池效率和氢低位热值计算；未用随机需求替代。
- A 来源：基于 sampled road closure 后的道路图 Dijkstra 可达性；`A=1` 表示存在可行服务路径，`A=0` 表示完全不可达。
- C 来源：基于当前道路状态下的最短路服务成本/通行阻抗；道路慢行通过边成本放大进入 `dist(n)`，不可达时 `C=Inf`。
- 兜底/placeholder 审计：未发现找不到数据后用随机数、常数、全 1 可达、全 0 故障或默认距离替代的兜底实现；未发现 `mock`、`dummy`、`placeholder`、`TODO`、`fake` 等未实现标记，关键词命中仅来自审计文本本身。
- smoke-test 限制：B1 仍使用前 `P_B1=10` 条路径、`M_B1=3`、`R_B1=30`，只用于小样本诊断，不能作为正式论文数值结果；B2 应改用固定随机种子抽样或分层抽样，并扩大到 R=200/R=500。
- 最近写入范围检查未发现禁止文件被修改；仅观察到项目根目录已有 `terminalLoh_wdro (3).zip`、`terminalLoh_wdro (4).zip`、`terminalLoh_wdro (5).zip` 有时间戳记录，但本任务未处理这些 zip。

### 2026-07-08 - Stage 2B2 W=3 中等样本 D/A/C 后果生成与诊断

- 本次只修改 `terminalLoh_wdro/` 下离线代码/文档/输出，并更新 `codex_rule/log.md`；未修改 `main_msp_h2_near.m`、`run_h2_with_options.m`、`load_data_h2_near.m`、`h2_default_options.m`、`fa_h2/` 主模型文件或原始 `data/` 文件。
- 修改公共生成器：`terminalLoh_wdro/src/build_lookahead_W3_DAC_samples_h2.m`，保留 B1 默认行为，同时新增通用 `P/M/random_seed/pathSelectionMode` 支持；当可用路径数等于 `P` 时使用全部路径，当可用路径数大于 `P` 时按固定随机种子随机抽样。
- 新增代码文件：`terminalLoh_wdro/src/run_lookahead_W3_B2_build_DAC_samples_h2.m`、`terminalLoh_wdro/src/write_lookahead_W3_B2_diagnostics_h2.m`。
- 新增文档：`terminalLoh_wdro/docs/README_lookahead_W3_B2_DAC_samples_R200.md`。
- 新输出目录：`terminalLoh_wdro/output/stage2_lookahead_W3_B2_DAC_samples_R200/`。
- 输出文件：`lookahead_scenario_site_node.csv`、`lookahead_scenario_summary.csv`、`lookahead_D_total_distribution_summary.csv`、`lookahead_reachability_summary.csv`、`lookahead_cost_summary.csv`、`implementation_audit_B2.txt`、`README_B2_DAC_samples_R200.txt`。
- B2 参数：`P_B2=20`、`M_B2=10`、`R_B2=200`，`random_seed_B2=20260708`；当前 Stage 2A 每状态正好 20 条路径，因此 B2 每状态使用全部路径，每条路径抽 10 个 damage 样本。
- 已运行：`cd('C:/Users/chaos/Desktop/biye/test/testH2_v2'); run('terminalLoh_wdro/src/run_lookahead_W3_B2_build_DAC_samples_h2.m');`。MATLAB 输出显示 B2 脚本完成并写出输出目录；命令工具随后返回超时状态，且残留 MATLAB 进程因权限拒绝未能停止。
- 输出规模检查：识别 35 个 lf=7 状态；`lookahead_scenario_summary.csv` 为 7000 行；每个状态 R=200；`lookahead_scenario_site_node.csv` 为 924000 行，等于 `35*200*4*33`。
- A/C 检查：`reachable` 只有 `0|1`；`half_reachable_count=0`；`reachable=1` 且 `C=Inf` 的计数为 0；不可达行数 206878；可达但变慢行数 293277。
- C 口径：正式 `scenario_service_cost=dist(n)`，未恢复 `baseCost + dist(n)`；`scenario_service_cost_before_fix` 仅作为诊断字段保留；unreachable 的 `C=Inf` 未进入 reachable 成本统计。
- D 诊断：`D_total_max_to_mean` 最大值为 149.496981891348；超过 5 的状态 11 个，超过 10 的状态 8 个，需要人工检查低均值状态下的尾部比值。
- 本次未运行 WDRO-LP，未调用 Gurobi，未接入 MSP，未生成 TerminalLOH，未新增 CVaR。

### 2026-07-08 - Stage2-Foundation-Audit 空间/风场/电网故障/DAC 链条审计

- 本次暂停 Stage2A2、Stage2B3、Stage2C，只做只读审计；未生成新的 D/A/C 样本，未运行 WDRO-LP，未调用 Gurobi，未接入或修改 MSP 主模型，未覆盖 B1/B2 输出。
- 新输出目录：`terminalLoh_wdro/output/stage2_foundation_audit/`。
- 新增审计输出：`spatial_coordinate_audit.txt`、`loc_lf_coordinate_table.csv`、`typhoon_center_coordinate_trace.csv`、`grid_coordinate_summary.csv`、`road_coordinate_summary.csv`、`wind_damage_chain_audit.txt`、`DAC_generation_chain_audit.txt`、`D_time_unit_audit.txt`、`implementation_audit_foundation.txt`。
- 审计文件：Stage2A 路径生成函数、Stage2B2 D/A/C 生成函数、`aggregate_W3_DAC_outcomes_h2.m`、风场/脆弱性函数、`build_terminal_loh_h2.m`、`load_data_h2_near.m`、`near_stage_msp_input.mat`、道路/站点 CSV 和 Stage2A path table。
- 坐标结论：原始 loc 为 `1:7`，扩展 loc 为 `-2:10`；每个扩展 loc 都有 x/y 坐标，path table 中所有扩展 loc 均出现；B2 使用 `pathRows.x_coord/y_coord` 作为台风中心，新增 loc 真实参与电网线路和道路边的风场/故障计算。
- lf/W 结论：当前 `W=3` 由 `tau=1,2,3` 表示，path table 的 `lf` 仍为 7；`y_coord` 全部为 0，当前没有把 lf/tau 映射为纵向空间切片。
- 风场/故障链条结论：B2 计算台风中心到电网线路中点和道路边中点的距离，输入 `compute_wind_speed_radial_h2`，再由 `compute_line_failure_prob_h2` 得到线路/道路故障概率并进行 MC 抽样。
- D 时间口径问题：B2 显式设置 `support_hours=2`，原始 MAT 中 `CriticalLoad.support_hours=8`；`D_tau=P_loss_kW*2h/(eta_FC*LHV_H2)`，再对 `W=3` 求和，因此持续失负荷时等效支撑时长最高为 6h。若目标是 Hres3h，则当前 B2 时间口径不一致。
- 道路链条结论：A 来自道路闭合/慢行后的 Dijkstra 可达性；正式 C 为 `dist(n)`，`baseCost+dist(n)` 仅保留在 before-fix 诊断字段；未恢复重复计量。
- 建议：在明确 Hres3h 时间口径和是否需要 tau/lf 的 y 方向空间推进前，不建议继续 Stage2A2/B3。

### 2026-07-09 - Stage2-Foundation-yStep-Calibration 正 y 方向校准阻断

- 本次只做 y 方向空间推进步长校准前置检查；未生成新的 D/A/C 样本，未运行 Stage2B3/Stage2C，未运行 WDRO-LP，未调用 Gurobi，未接入或修改 MSP 主模型，未覆盖 B1/B2/foundation audit 输出。
- 新增代码文件：`terminalLoh_wdro/src/run_stage2_foundation_yStep_calibration_h2.m`、`terminalLoh_wdro/src/calibrate_lookahead_y_step_h2.m`、`terminalLoh_wdro/src/write_y_step_calibration_diagnostics_h2.m`。
- 运行脚本：`cd('C:/Users/chaos/Desktop/biye/test/testH2_v2'); run('terminalLoh_wdro/src/run_stage2_foundation_yStep_calibration_h2.m');`
- 新输出目录：`terminalLoh_wdro/output/stage2_foundation_yStep_calibration/`。
- 输出文件：`y_step_candidate_diagnostics.csv`、`y_step_by_intensity_summary.csv`、`y_step_by_loc_summary.csv`、`wind_road_decay_by_tau_summary.csv`、`y_step_recommendation.txt`、`implementation_audit_yStep_calibration.txt`。
- 使用数据/函数：`loc_lf_coordinate_table.csv`、`lookahead_path_table.csv`、`near_stage_msp_input.mat`、`stage1_road_edges.csv`、`stage1_site_nodes.csv`、`build_h2_spatial_layout_preview.m`、`compute_wind_speed_radial_h2.m`、`compute_line_failure_prob_h2.m`，并复现 B2 道路边中点坐标构造逻辑。
- 计算得到 `x_loc_step=17`，`y_base=0`，候选 `candidate_y_step=[8.5,17,25.5,34,51,68]`，对应 `[0.5,1,1.5,2,3,4]*x_loc_step`。
- 正 y 方向检查触发阻断：系统对象 y 范围为 `[11.0416666667,33.9583333333]`，`y_base=0` 位于系统下方；按 `y_tau=y_base+tau*y_step` 的正 y 方向推进会让台风中心先靠近/进入电网道路影响区，而不是远离系统。
- 因上述停止条件，本次未继续计算正方向下的风场/故障衰减推荐；CSV 中保留候选 y 坐标行，风险字段为 `NaN`，`meets_W3_decay_rule=0`。
- 推荐 y_step：无，状态为 `blocked_positive_y_moves_toward_system`。建议先进入 Foundation Fix 明确 y 方向符号约定；不要在当前正 y 假设下直接推进 Stage2A2/B3。

### 2026-07-13 - Stage2 Foundation warning100 Rmax/Wstep sweep

- 本次重新设计 Foundation 空间诊断：固定 `warning_distance_km_eq=100`，测试 `Rmax=[30,40,50]` 与 `Wstep=[30,35,40,45,50]`，正 y 方向解释为台风从系统南侧靠近并穿越系统；未沿用旧 yStep 的提前阻断逻辑。
- 本次只做空间/风场/线路故障/道路关闭概率诊断；未生成新的 D/A/C 样本，未运行 Stage2C，未运行 WDRO-LP，未调用 Gurobi，未接入或修改 MSP 主模型，未覆盖旧 B1/B2/foundation 输出，未给 Rmax=30/40/50 赋概率。
- 新增代码文件：`terminalLoh_wdro/src/run_stage2_foundation_warning100_Rmax_Wstep_sweep_h2.m`、`evaluate_warning_Rmax_Wstep_candidate_h2.m`、`compute_point_to_segment_distance_h2.m`、`solve_warning_y_base_h2.m`、`rank_Wstep_candidates_h2.m`、`write_warning_Rmax_Wstep_diagnostics_h2.m`。
- 运行脚本：`cd('C:/Users/chaos/Desktop/biye/test/testH2_v2'); run('terminalLoh_wdro/src/run_stage2_foundation_warning100_Rmax_Wstep_sweep_h2.m');`
- 新输出目录：`terminalLoh_wdro/output/stage2_foundation_warning100_Rmax30_40_50_Wstep_sweep/`。
- 输出文件：`warning_y_base_solution.csv`、`warning_geometry_by_loc.csv`、`Rmax_Wstep_full_risk_table.csv`、`Rmax_Wstep_stage_summary.csv`、`Wstep_candidate_indicators.csv`、`Wstep_candidate_ranking.csv`、`Rmax_sensitivity_summary.csv`、`diagnostics_summary.txt`、`parameter_snapshot.csv`，以及 `figures/` 下 10 张 PNG。
- 使用数据/函数：foundation audit 的 `loc_lf_coordinate_table.csv`、`near_stage_msp_input.mat`、`stage1_road_edges.csv`、`stage1_site_nodes.csv`、`build_h2_spatial_layout_preview.m`、`compute_wind_speed_radial_h2.m`、`compute_line_failure_prob_h2.m`；电网和道路距离均使用点到线段距离。
- 求得 `y_base=-89.9999703886`，最近距离 `99.9999999744` km-equivalent，最近 loc 为 `loc=3`，最近对象为 `grid_line 17`，误差约 `-2.56e-08`。
- 完整风险表规模：`3*5*4*5*13=3900` 行；阶段汇总 60 行；几何表 260 行；候选指标 5 行；Rmax 敏感性 15 行。
- Rmax=40 下 line pFail p95：`Wstep=30` 为 `[0.182477,0.423584,1,1]`，`35` 为 `[0.182477,0.485140,1,1]`，`40` 为 `[0.182477,0.556646,1,1]`，`45` 为 `[0.182477,0.640680,1,1]`，`50` 为 `[0.182477,0.740750,1,1]`，阶段顺序均为 `lf7,W1,W2,W3`。
- Rmax=40 下 road pClose p95：`Wstep=30` 为 `[0.023602,0.184895,0.533059,0.696914]`，`35` 为 `[0.023602,0.222792,0.729328,0.642963]`，`40` 为 `[0.023602,0.265297,0.754902,0.706676]`，`45` 为 `[0.023602,0.313145,0.696914,0.721129]`，`50` 为 `[0.023602,0.374165,0.639195,0.739764]`。
- 推荐 `recommended_Wstep=40`，第二名 `second_best_Wstep=45`。理由：Rmax=40 主评分满分、Rmax=30/50 稳健性均通过，W2 进入主要影响阶段；相较 30/35，40 的 W1/W2 风险建立更充分；相较 45/50，40 更细且没有损失稳健性。
- 异常检查：存在“距离变小但局部风速下降”现象，来源于当前径向风场在 `r<Rmax` 内风速随半径增大的结构；未发现 p95 大量为 0 但 max 很高、道路关闭概率始终为 0、lf7 线路风险饱和、旧 a→Rmax 表误调用或 Rmax 在 W 阶段随机重抽。

### 2026-07-13 - TerminalLOH Foundation Fix 与 Hres3h 重审计

- 本次读取并遵守 `codex_rule/core.md`、`codex_rule/longtask.md`、`codex_rule/log.md`；`core.md` 和 `longtask.md` 保持只读。
- 新增代码文件：`terminalLoh_wdro/src/run_stage2_foundation_fix_Hres3h_h2.m`、`build_foundation_fix_coordinates_h2.m`、`evaluate_foundation_fix_chain_h2.m`、`compute_Hres3h_node_demand_h2.m`、`run_stage2_foundation_reaudit_h2.m`、`compare_Wstep40_45_foundation_h2.m`、`write_foundation_fix_diagnostics_h2.m`。
- 运行脚本：`cd('C:/Users/chaos/Desktop/biye/test/testH2_v2'); run('terminalLoh_wdro/src/run_stage2_foundation_fix_Hres3h_h2.m');`。最终重跑成功；MATLAB 仅报告用户搜索路径中一个既有目录不存在的启动警告，Foundation 计算无报错。
- 新输出目录：`terminalLoh_wdro/output/stage2_foundation_fix_Hres3h_Wstep40_reaudit/`。输出 8 个 CSV、`diagnostics_summary.txt`、`implementation_audit.md` 和 `figures/` 下 8 张 PNG。
- warning 几何复核：从 `warning_y_base_solution.csv` 读取并独立用点到线段距离重算，得到 `y_base=-89.9999703885911`、最小距离 `99.9999999743943`、最近 `loc=3`、最近对象 `grid_line 17`、最近点 `(-16.9230769230769,10)`。`y_base≈-90` 来自该最近点与台风中心约 100 的欧氏距离，不是简单使用系统 `y_min-100`。
- 旧 Wstep 排名核对：`rank_Wstep_candidates_h2.m` 未硬编码推荐 40；旧结果由综合评分和按较小 Wstep 排序得到 40 第一、45 第二。本次不把旧排序当作既定结论。
- Foundation 坐标修正：Wstep=40 的 `[lf7,W1,W2,W3]` y 坐标为 `[-89.9999703886,-49.9999703886,-9.99997038859,30.0000296114]`；Wstep=45 为 `[-89.9999703886,-44.9999703886,0.0000296114,45.0000296114]`。lf7 与 W1 明确为不同位置。
- 风险链条：新 y 坐标真实进入电网线路和道路边的点到线段距离、`compute_wind_speed_radial_h2`、`compute_line_failure_prob_h2`、线路故障 MC、源节点 1 连通性、节点失负荷、`P_loss` 和 D；道路侧同步进入 pClose、关闭和慢行计数。
- Rmax 处理：测试 `Rmax=[30,40,50]`，`a` 只控制 Vmax；Rmax 不使用旧 `a→Rmax` 表、不赋概率、不在阶段间抽样或重抽。同一支持点在 lf7/W1/W2/W3 保持固定。
- Hres3h 修正：节点负荷直接读取真实字段 `NearStageInput.Grid.P_load_base_kw`，总负荷 3715 kW；未使用 IEEE33 fallback、mock、dummy、placeholder 或随机需求。`eta_FC=0.55`、`LHV_H2=33.33 kWh/kg`；W1/W2/W3 各 1 h，lf7 不计入，总 Hres=3 h；`D_total=D_W1+D_W2+D_W3` 最大绝对误差为 0。
- smoke MC：`Nmc=200`、基础种子 `20260713`，代表强度 `a=[4,6]`、位置 `loc=[0,3,10]`；Wstep 40/45 使用共享随机数。该结果仅为 Foundation smoke MC，不是正式 B3。
- Rmax=40、Wstep=40 的阶段风险 `[lf7,W1,W2,W3]`：line pFail p95 为 `[0.182476920,0.556645744,1,1]`，road pClose p95 为 `[0.023601691,0.265297397,0.754901933,0.706675527]`。
- Rmax=40 的代表状态平均 Hres3h 后果：Wstep=40 的 `D_W1/D_W2/D_W3/D_total=[69.391939194,131.562247134,74.295838675,275.250025003] kg`；Wstep=45 为 `[79.400894635,109.545500005,108.039213012,296.985607652] kg`。
- 40/45 对照结论：继续推荐 Wstep=40。Rmax=40 下平均绝对 D_total 差为 `49.0810444681 kg`，相对诊断信号 `0.178314405122`，平均绝对道路关闭计数差 `1.97666666667`；45 的 W1 风险更早升高，40 保留更细的接近/穿越推进，同时 W2/W3 仍进入主要影响。
- 重审计检查：`foundation_fix_reaudit_checks.csv` 共 22 项，22/22 通过；确认 1 h 切片、3 h 总时长、D 求和恒等式、共享随机数、Rmax 固定、旧映射禁用和旧输出未覆盖。
- 明确禁止项：未生成正式 B3，未计算正式 path_prob，未运行 Stage2C/WDRO/Gurobi，未生成正式 TerminalLOH，未运行或修改 MSP 主模型，未覆盖 Stage2A/B1/B2/Foundation audit/yStep/warning sweep 旧输出。

### 2026-07-14 - Foundation Fix 推荐逻辑与 re-audit 加固 v2

- 本次读取并遵守 `codex_rule/core.md`、`codex_rule/longtask.md`、`codex_rule/log.md`；`core.md` 和 `longtask.md` 保持只读。
- 修改代码：`terminalLoh_wdro/src/compare_Wstep40_45_foundation_h2.m`、`run_stage2_foundation_reaudit_h2.m`。
- 新增代码：`select_foundation_Wstep_recommendation_h2.m`、`load_foundation_fix_reaudit_inputs_h2.m`、`independent_recheck_foundation_D_Hres3h_h2.m`、`build_foundation_fix_scope_audit_v2_h2.m`、`run_stage2_foundation_fix_reaudit_v2_h2.m`、`write_foundation_fix_reaudit_v2_h2.m`。
- 旧推荐逻辑问题：只要 Wstep 40/45 的 D 或道路后果差异超过阈值，就固定返回 Wstep 40，没有对 Wstep 45 使用对称候选判据。
- 新推荐逻辑：对 40/45 使用相同的 W1 相比 lf7 增强、W2/W3 主影响、是否跳过影响带、跨 Rmax 稳定性、line pFail、road pClose 和 D 的 W2/W3 占比判据；决策允许 `recommend_40`、`recommend_45`、`inconclusive_40_45`，平局不按较小 Wstep 打破。合成测试已自动验证三个分支均可到达。
- 最终推荐：`recommend_40`。Wstep 40 在 Rmax=30/40/50 的联合支持为 3/3，Wstep 45 为 0/3；两者均通过 W1 增强、W2/W3 主影响和不跳带检查，但 45 的 W1 line/road 风险在三个 Rmax 下都更早、更高。
- Wstep 40 的 Rmax=30/40/50 W1 line pFail p95 分别为 `0.300172898/0.556645744/0.831668246`，W2/W3 主影响均达到 1；W1 road pClose p95 为 `0.0921229024/0.265297397/0.445294702`。Wstep 45 对应 W1 line 为 `0.358986723/0.640679918/0.945145800`，W1 road 为 `0.126771978/0.313145097/0.507946456`。
- Wstep 40 的 Rmax=30/40/50 平均 D_total 为 `233.631545/275.250025/310.652429 kg`，W2/W3 D 占比为 `0.792166/0.747895/0.622919`；Wstep 45 对应为 `279.904581/296.985608/315.460182 kg` 和 `0.812317/0.732644/0.602967`。D_total 较大本身不被当作更优，推荐关注 W1 时序和主影响覆盖。
- D 独立复算：从旧 `foundation_fix_D_by_slice.csv` 重读 28800 行，以 `mc_id` 作为 `scenario_id`，得到 7200 个场景、36 个 Rmax/Wstep/a/loc 组。每个场景恰好各有一个 W1/W2/W3，无重复阶段，lf7 未计入，切片均为 1 h，汇总 Hres 为 3 h。
- 旧 `foundation_fix_D_Hres3h_summary.csv` 没有逐场景 `D_Hres3h_total_kg` 字段，因此自动重构并比较可用的 mean/P50/P90/P95/MAX；最大绝对误差为 `1.02318153949454e-12`，小于容差 `1e-9`。缺少逐场景 reported total 已标记 `manual verification required` warning，不伪造该字段。
- common random numbers 检查通过：匹配的 Rmax/a/loc/stage/scenario 使用相同 seed；非 y 输入一致；lf7 y 相同，W1/W2/W3 只改变阶段 y；源码确认 line/road uniform 在 Wstep 循环外生成。
- re-audit 固定 true 已移除：`no_formal_B3_generated`、`no_WDRO_run`、`no_MSP_modified`、`no_old_output_overwritten` 现在分别由执行源调用扫描、v2 输出白名单、MSP 保护文件审计和旧输出目录前后快照支持。
- 自动检查结果：27/27 通过，0 个自动失败，1 个完整工作区 diff 人工项为 NaN/warning；项目无 `.git` 和 git executable，因此完整未跟踪修改清单注明 `manual verification required`。MSP 保护文件和 7 个旧输出目录均自动验证未变。
- 最终运行命令：`cd('C:/Users/chaos/Desktop/biye/test/testH2_v2'); run('terminalLoh_wdro/src/run_stage2_foundation_fix_reaudit_v2_h2.m');`。最终运行成功；仅有 MATLAB 用户搜索路径中既有目录不存在的启动 warning。
- 新输出目录：`terminalLoh_wdro/output/stage2_foundation_fix_Hres3h_Wstep40_reaudit_v2/`。输出 `Wstep40_45_recommendation_v2.csv`、`foundation_fix_reaudit_checks_v2.csv`、`D_Hres3h_independent_recheck.csv`、`modified_file_audit.csv`、`output_directory_audit.csv`、`diagnostics_summary_v2.txt`、`implementation_audit_v2.md`。
- 中间调试曾出现 cell 维度拼接、缺少 legacy ranking 配置字段、跨行 `compose` 模板和 CSV 0/1 逻辑索引错误；均已修复，最终输出来自完整成功重跑，不使用失败运行结果。
- 明确禁止项：未执行 Stage2A2，未计算 path_prob，未进行路径筛选，未生成正式 B3，未运行 Stage2C/WDRO/Gurobi，未运行或修改 MSP，未覆盖任何旧输出。

### 2026-07-14 - W1-W3 损坏持续性 smoke test

- 本次读取并遵守 `codex_rule/core.md`、`codex_rule/longtask.md`、`codex_rule/log.md`；`core.md`、`longtask.md` 保持只读。
- 新增代码：`terminalLoh_wdro/src/run_stage2_damage_persistence_smoke_h2.m`、`evaluate_damage_persistence_mode_h2.m`、`compare_independent_persistent_damage_h2.m`、`write_damage_persistence_diagnostics_h2.m`。未修改既有 Foundation v1/v2 代码结果或 MSP 文件。
- 测试参数：`Wstep=40`、`Rmax=[30,40,50]`、`a=[4,6]`、`loc=[0,3,10]`、`W1/W2/W3` 各 1 h、`Hres=3 h`、`Nmc=200`、`rng_seed=20260715`。
- 两种模式：`independent_snapshot` 每阶段直接使用当期线路/道路 Bernoulli 抽样和当期慢行严重度，允许后续恢复；`persistent_damage` 对线路故障和道路关闭做阶段累计 OR，对慢行严重度做累计 max，不包含修复机制。
- common random numbers：同一 Rmax/a/loc/stage/scenario 的 seed、线路 uniform checksum、道路 uniform checksum、原始故障/关闭抽样数和基础 pFail/pClose 均一致；自动检查通过。
- 输出规模：`damage_persistence_by_slice.csv` 为 21600 行，等于 `2 modes * 3 Rmax * 2 a * 3 loc * 200 scenarios * 3 stages`；Hres3h summary 36 行，模式比较 18 行。
- persistent 单调性：线路故障数量递减违例 0，道路关闭数量递减违例 0，慢行严重度递减违例 0。independent 模式中有 1981 个场景出现后续线路故障数或道路关闭数下降，确认恢复行为真实存在。
- 聚合结果，阶段顺序均为 W1/W2/W3。Rmax=30：independent failed=`[2.0483,8.8983,5.0942]`、P_loss=`[890.12,1976.15,1429.97] kW`、D=`[48.5567,107.8008,78.0062] kg`；persistent failed=`[2.0483,9.3942,11.6758]`、P_loss=`[890.12,1980.59,2281.59]`、D=`[48.5567,108.0431,124.4629]`。
- Rmax=40：independent failed=`[4.7575,10.3575,6.3958]`、P_loss=`[1272.06,2455.73,1358.46] kW`、D=`[69.3919,133.9625,74.1051] kg`；persistent failed=`[4.7575,11.8900,13.9725]`、P_loss=`[1272.06,2489.85,2660.37]`、D=`[69.3919,135.8234,145.1254]`。
- Rmax=50：independent failed=`[8.7017,10.0475,6.6158]`、P_loss=`[2147.38,2305.42,1291.87] kW`、D=`[117.1413,125.7626,70.4727] kg`；persistent failed=`[8.7017,14.2733,16.0075]`、P_loss=`[2147.38,2701.15,2767.41]`、D=`[117.1413,147.3500,150.9649] kg`。
- Hres3h D_total 平均值：Rmax 30/40/50 下 independent 分别为 `234.363664/277.459564/313.376565 kg`，persistent 为 `281.062652/350.340716/415.456091 kg`，增量分别为 `46.698988/72.881152/102.079526 kg`，相对增幅 `19.93%/26.27%/32.57%`。
- 饱和诊断：persistent 跨 a/loc/scenario 聚合最大饱和率为 `0.458333`，低于大量饱和阈值 0.5，因此未判为整体大量饱和；部分高风险状态级 summary 的最大饱和率可达到 1，正式 B3 仍需保留分状态饱和诊断。
- Wstep=40 阶段区分度保留：persistent 的 D 阶段 range ratio 在 Rmax 30/40/50 下约为 `0.6099/0.5218/0.2240`，均高于 0.05 阈值；故障数、道路关闭和 P_loss 也保持阶段差异。
- 正式 B3 设计建议：在“3 h 内不考虑修复”的假设下，建议以 `persistent_damage` 为主口径，并保留 `independent_snapshot` 作为消融对照；正式 B3 尚未执行。
- 最终自动检查：14/14 必需项通过，0 失败；2 行饱和和阶段区分度为 NaN 诊断项。保护的 8 个旧输出目录和 14 个 MSP/数据文件均未变化；源调用扫描 WDRO/Gurobi、MSP、B3/path_prob 命中均为 0。
- 输出目录：`terminalLoh_wdro/output/stage2_damage_persistence_smoke/`。输出 `damage_persistence_by_slice.csv`、`damage_persistence_Hres3h_summary.csv`、`independent_vs_persistent_comparison.csv`、`damage_persistence_checks.csv`、`diagnostics_summary.txt`、`implementation_audit.md`，以及 `figures/` 下 6 张阶段对照图。
- 最终运行命令：`cd('C:/Users/chaos/Desktop/biye/test/testH2_v2'); run('terminalLoh_wdro/src/run_stage2_damage_persistence_smoke_h2.m');`。运行成功；仅有 MATLAB 用户搜索路径中既有目录不存在的启动 warning。
- 明确禁止项：未执行 Stage2A2、path_prob、路径筛选、正式 B3、Stage2C、WDRO、Gurobi 或 MSP；未覆盖旧 Foundation 输出；未进入下一阶段。

### 2026-07-14 - W1-W3 损坏持续性 v2：固定抗力阈值对照

- 本次读取并遵守 `codex_rule/core.md`、`codex_rule/longtask.md`、`codex_rule/log.md`；`core.md`、`longtask.md` 保持只读。
- 新增代码：`terminalLoh_wdro/src/run_stage2_damage_persistence_v2_h2.m`、`evaluate_fixed_resistance_damage_h2.m`、`compare_damage_persistence_modes_v2_h2.m`、`write_damage_persistence_v2_diagnostics_h2.m`。未修改上一轮 persistence smoke、Foundation v1/v2 或 MSP 代码。
- 固定参数：`Wstep=40` 由入口配置传入 evaluator，不在阶段推进公式中硬编码；`Rmax=[30,40,50]`、`a=[4,6]`、`loc=[0,3,10]`、`Nmc=200`、`seed=20260716`，W1/W2/W3 各 1 h，Hres=3 h。
- 三种模式：`independent_snapshot` 使用阶段独立抽样并允许恢复；`persistent_independent_draws` 使用阶段独立抽样后累计 OR/max；`persistent_fixed_resistance` 每场景每组件只使用一次 W1 uniform 阈值，W1-W3 共用该阈值，首次损坏后持续，无修复。
- common random numbers 自动检查通过：三种模式共享相同基础 stage-uniform cube、seed、pFail/pClose；W1 线路、道路、P_loss、D、A/C 后果完全一致。固定抗力阈值逐场景跨 W1-W3 精确复用检查通过。
- 道路 A/C：使用 `stage1_road_edges.csv`、`stage1_site_nodes.csv` 和 Foundation 坐标；关闭边不进入最短路，慢行边成本为 `edge_length*(1+slowdown)`；A 为 4×33 二进制可达性，C 为当前最短路 `dist(n)`，没有 `baseCost+dist(n)`。不可达 C 未进入有限成本统计。
- 输出规模：`damage_persistence_v2_by_slice.csv` 32400 行，`damage_persistence_v2_Hres3h_summary.csv` 10800 行，`damage_mode_comparison_v2.csv` 54 行，`state_level_saturation_v2.csv` 162 行，`road_AC_stage_diagnostics_v2.csv` 32400 行，检查表 27 行；另输出诊断摘要、实现审计和 6 张 PNG。
- D_Hres3h 均值，Rmax=30/40/50：independent 为 `232.325051/275.307303/310.597651 kg`；persistent independent draws 为 `279.561138/350.107965/414.789206 kg`；persistent fixed resistance 为 `275.745529/337.679222/393.952122 kg`。
- 累计 OR 相对固定抗力的 D 均值增量，Rmax=30/40/50 分别为 `3.815609/12.428743/20.837084 kg`，相对 `1.38374%/3.68064%/5.28924%`；总体增量 `12.360478 kg`，相对 `3.68099%`。分状态最大有限相对增幅为 `32.4278%`（Rmax=40,a=6,loc=10）；另有低风险状态 Rmax=30,a=6,loc=10 出现 fixed=0、累计 OR=0.343671 kg 的重复机会效应。
- 固定抗力单调性：线路故障递减违例 0、道路关闭递减违例 0、慢行严重度递减违例 0。固定抗力阶段区分度检查通过，最小 D stage range ratio 为 `0.155202`。
- 分状态全失负荷饱和：fixed resistance 的 54 个 state-stage 行中 38 行有正饱和率，14 行不低于 0.5，5 行为 1；但跨 a/loc/scenario 聚合的最大饱和率为 `0.4375`，低于 0.5 大量饱和阈值。输出保留完整 Rmax/a/loc/stage 诊断，不只报告跨状态聚合值。
- 自动检查：24/24 必需项通过，0 失败；3 个诊断项为 NaN pass 状态。独立 MATLAB 输出复核再次确认行数、Wstep、Hres、A 二进制和必需检查全部通过。
- 建议：正式 B3 的无修复主口径采用 `persistent_fixed_resistance`，将 `independent_snapshot` 和 `persistent_independent_draws` 保留为消融对照；本次未执行正式 B3。
- 输出目录：`terminalLoh_wdro/output/stage2_damage_persistence_v2/`。旧 Foundation、B1/B2 和上一轮 persistence smoke 输出目录前后快照一致，受保护 MSP/数据文件前后快照一致。
- 运行说明：正式计算成功完成。首次外层 PowerShell 调用在 5 秒处超时，但 MATLAB 子进程继续并完整写出结果；随后使用独立 MATLAB 命令读取所有 CSV 并通过断言验证。MATLAB 仅报告既有用户搜索路径不存在的启动 warning。
- 明确禁止项：未执行 Stage2A2、path_prob、路径筛选、正式 B3、Stage2C、WDRO、Gurobi 或 MSP；未修改 MSP；未覆盖旧输出；未自动进入下一阶段。

### 2026-07-14 - GitHub 初始基线准备

- 本次读取并遵守 `codex_rule/core.md`、`codex_rule/longtask.md`、`codex_rule/log.md`；`core.md` 和 `longtask.md` 保持只读。
- 本次只准备 GitHub 仓库基础文件；未修改任何 `.m` 源程序、模型、算法、参数、数据或运行结果，未移动、删除或重命名现有文件。
- 新增 `.gitignore`、`README.md`、`AGENTS.md`、`docs/baseline/BASELINE.md`、`docs/baseline/repository_file_audit.md`。
- `.gitignore` 定向忽略 `terminalLoh_wdro/output/`、`output_h2/`、压缩包、视频、MATLAB/Python/notebook 缓存、临时文件、本地日志、许可证和凭据；未使用 `*.m`、`*.csv`、`*.mat` 或 `*.fig` 宽泛规则。
- 仓库预扫描：370 个文件，总大小约 0.294 GB；大于 20 MB 的文件 4 个，大于 50 MB 的文件 1 个，大于 100 MB 的文件 0 个。
- 大文件：94.11 MB B2 `lookahead_scenario_site_node.csv`、29.41 MB Stage1 WDRO 输出、23.89 MB `terminalLoh_wdro (2).zip`、21.48 MB `terminalLoh_wdro.zip`；均属于已忽略输出或压缩包。
- 压缩/视频扫描：发现 ZIP 2 个；RAR、7z 和视频文件均为 0。
- MAT/FIG 扫描：MAT 4 个，其中 `data/yuanqi/near_stage_msp_input.mat` 与 `near_stage_seed_compat.mat` 为必要小型输入并保留上传，另外 2 个位于 `output_h2/`；FIG 文件 0 个。
- 大型 CSV 扫描采用 5 MB 阈值，发现 8 个，全部位于 `terminalLoh_wdro/output/` 或 `output_h2/`，由目录规则忽略。
- 敏感信息扫描：未发现 `.env`、许可证、账号凭据、密码、token、私钥文件名候选；常见私钥头、GitHub/OpenAI/AWS token 和密码赋值内容模式命中 0。当前也没有开源 `LICENSE` 文件。
- 重复/临时项：`terminalLoh_wdro (2).zip` 为明显重复备份命名；两个 18.98 MB `terminal_loh_allocation_WDRO.csv` 字节级完全相同；`data/.ipynb_checkpoints/` 为缓存副本。上述文件未删除，仅通过忽略规则排除。
- 输出目录规模：`terminalLoh_wdro/output/` 120 个文件、约 199.87 MB；`output_h2/` 115 个文件、约 53.15 MB。
- 基线文档明确记录 Foundation Fix、`Hres=3 h`、`Wstep=40`、推荐逻辑 v2、未来正式 B3 无修复主口径 `persistent_fixed_resistance`，以及 Stage2A2、正式 B3、Stage2C 和 MSP 接入尚未执行。
- 明确禁止项：未执行 `git init/add/commit/push/pull`，未创建分支或 PR，未运行 MATLAB、Gurobi、WDRO 或 MSP，未创建 `.git` 元数据，未进入下一任务。

### 2026-07-14 - Foundation + Persistence v2 完整目录备份

- 本次读取并遵守 `codex_rule/core.md`、`codex_rule/longtask.md`、`codex_rule/log.md`；`core.md` 和 `longtask.md` 保持只读。
- 源目录：`C:\Users\chaos\Desktop\biye\test\testH2_v2`。
- 备份父目录：`D:\biye_backup\2026-07-14_foundation-persistence-v2-baseline`；项目目标目录：`D:\biye_backup\2026-07-14_foundation-persistence-v2-baseline\testH2_v2`。执行前父目录和目标目录均不存在，因此未覆盖其他历史备份。
- 使用 `robocopy` 非镜像复制参数：`/E /COPY:DAT /DCOPY:DAT /R:2 /W:2 /XJ`；未使用 `/MIR`。备份包含输出目录、数据、规则文件、ZIP、隐藏文件和空目录。
- 首次命令尝试因 PowerShell `New-Item -LiteralPath` 参数不受支持，父目录未创建，robocopy 无法打开日志并返回 16；该次未开始复制，源目录和目标目录均未变化。修正为 `New-Item -Path` 后复制成功。
- 成功复制的 robocopy 原始退出码为 1；日志显示文件 375/375、失败 0、跳过 0、Mismatch 0、Extras 0，目录 59/59、失败 0。
- 初次完整性核对：源和目标均为 375 个文件、316,215,740 字节、58 个子目录；缺失文件 0、额外文件 0、大小不一致 0、缺失目录 0。
- 关键路径 `.gitignore`、`README.md`、`AGENTS.md`、`codex_rule/core.md`、`codex_rule/longtask.md`、`terminalLoh_wdro/src/run_stage2_damage_persistence_v2_h2.m`、`terminalLoh_wdro/output/stage2_damage_persistence_v2/`、`data/yuanqi/near_stage_msp_input.mat` 全部存在。
- 在备份父目录新增 `VERSION_INFO.txt`，记录版本 `foundation-persistence-v2-baseline`、Foundation + Persistence v2 已验收、`Wstep=40`、`Hres=3 h`、主损坏口径 `persistent_fixed_resistance`、下一阶段 Stage2A2、GitHub 初始建库前完整备份及源/目标目录。
- robocopy 日志位于 `D:\biye_backup\2026-07-14_foundation-persistence-v2-baseline\ROBOCOPY_LOG.txt`。本日志更新后再次使用相同非镜像参数增量同步，并执行最终文件数、字节数、目录和关键路径复核。
- 明确禁止项：未压缩备份，未删除、移动或重命名源项目，未修改模型、代码、参数、数据或输出，未执行 Git、MATLAB、Gurobi、WDRO 或 MSP，未进入 GitHub 建库或 Stage2A2。

### 2026-07-14 - task-001 step-01 W3 候选转移矩阵与审计 run-001

- 任务：`task-001-stage2a2-path-prob`；步骤：`01-w3-transition-audit`；运行：`run-001`；代码分支：`task/001-stage2a2-path-prob`。
- MATLAB 实际命令：`cd('C:/Users/chaos/Desktop/biye/test/testH2_v2'); run('terminalLoh_wdro/src/run_stage2a2_W3_transition_audit_h2.m');`。
- 新增配置：`lookahead_intensity_postlandfall_W3.csv`、`lookahead_location_postlandfall_W3.csv`、`lookahead_lfw_postlandfall_W3.csv`、`lookahead_window_postlandfall_W3.csv`。
- 新增审计入口：`terminalLoh_wdro/src/run_stage2a2_W3_transition_audit_h2.m`；修改配置说明：`terminalLoh_wdro/config/README_config.md`。
- 强度候选由 legacy 矩阵自动计算：`a=2:5` 增强概率乘 0.2，被削减质量按 2/3 加到减弱、1/3 加到维持；`a=1` 吸收，`a=6` 使用 0.60/0.40。
- loc 状态为 `-2:10`，基础位移核为 `[-3:0.04,-2:0.10,-1:0.22,0:0.18,+1:0.28,+2:0.13,+3:0.05]`；边界删除无效目标后重新归一化，不进行边界堆积。最大自循环概率为 `0.333333333333`，对应 `loc=10`。
- lfw 状态为 `0:3`，基础后退/停留/前进概率为 `0.10/0.20/0.70`；`y=-89.9999703886+lfw*40`。W1/W2/W3 是连续三个 1 h 时间窗口，不固定对应某个 lfw。
- 首次 run-001 因 Window CSV 回读时 `value` 被自动推断为数值，得到 PASS=41、FAIL=3；仅修复审计脚本的双 string 导入及数值/文本键分离检查，未改变任何候选概率或矩阵内容。
- 最终重审计 PASS=44、FAIL=0；原失败项 `FILE-06`、`WIN-06`、`WIN-07` 全部通过。三个 legacy 配置运行前后字节和 SHA-256 完全一致。
- 本地原始输出目录：`terminalLoh_wdro/output/stage2a2_W3_transition_audit/run-001/`，共 12 个文件、10895 字节。
- 候选概率是透明、可复现的工程候选，尚未经过真实台风数据校准，也尚未被用户接受为最终参数。
- 未接入正式路径生成器；未运行 Foundation、Persistence、B3、WDRO、Gurobi、MSP 或 OOS evaluation；未修改 legacy 配置、Vmax 映射、Rmax 支持点或径向风场公式。

### 2026-07-14 - task-001 step-01 W3 扩展转移审计 run-002

- 当前分支：`task/001-stage2a2-path-prob`。保留 `run-001` 原始输出和 Git 归档，不覆盖、不删除。
- 修改强度候选矩阵：保留 run-001 的相邻转移概率；`a=3:6` 新增 `a->a-2=0.02`，`a=2:4` 新增 `a->a+2=0.005`，新增概率仅从保持分支扣除；`a=1` 继续吸收。
- 修改 lfw 候选矩阵：基础后退/保持/前进一级/前进两级为 `0.05/0.18/0.75/0.02`；边界无效概率并入保持，精确得到用户指定的四行概率。
- loc 和 Window 候选保持 run-001 内容不变；三个 legacy 配置运行前后 SHA-256 完全一致。
- 更新审计入口以允许强度最多变化两级、lfw 变化 `-1/0/+1/+2`，并逐行验证强度跨两级概率、lfw 精确概率及所有行和。
- MATLAB 实际命令：`cd('C:/Users/chaos/Desktop/biye/test/testH2_v2'); run('terminalLoh_wdro/src/run_stage2a2_W3_transition_audit_h2.m');`。
- run-002 最终审计：PASS=48、FAIL=0；最大 loc 自循环概率仍为 `0.333333333333`，对应 `loc=10`。
- 本地输出目录：`terminalLoh_wdro/output/stage2a2_W3_transition_audit/run-002/`；12 个文件、11809 字节，最大文件 `audit_checklist.csv` 为 4626 字节。
- 候选概率仍是未经过真实台风数据校准、尚未被用户接受为最终参数的工程候选；尚未接入正式路径生成。
- 未运行 Foundation、Persistence、B3、WDRO、Gurobi、MSP 或 OOS evaluation；未修改 `.gitignore`、main、legacy 配置、Vmax/Rmax 或径向风场公式。

### 2026-07-15 - task-001 step-02A W3 主体完整路径抽样与收敛审计 run-001

- 当前分支：`task/001-stage2a2-path-prob`；新增审计入口 `terminalLoh_wdro/src/run_stage2a2_W3_path_sampling_convergence_h2.m`。
- 输入为已通过 step-01 run-002 审计的三张 postlandfall 矩阵；运行前后 SHA-256 和文件字节完全一致，未修改候选矩阵、legacy 配置、Window 配置或 `.gitignore`。
- 初始状态为 `a0=2:6`、`loc0=1:7`、`lfw0=0`，共 35 个；测试 `N=[500,1000,2000,5000,10000]` 和种子 `20260721:20260725`。每个种子/初始状态一次生成 10000 条路径，较小 N 使用嵌套前缀。
- 精确基准通过矩阵乘法计算 W1/W2/W3 的强度、loc、lfw 边缘分布和联合 `(a,loc,lfw)` 分布；抽样审计输出最大绝对误差、总变差距离和五个种子的稳定性。
- MATLAB 实际命令：`cd('C:/Users/chaos/Desktop/biye/test/testH2_v2'); run('terminalLoh_wdro/src/run_stage2a2_W3_path_sampling_convergence_h2.m');`。运行成功；除既有 MATLAB 用户搜索路径 warning 外无运行错误。
- 自动审计结果：PASS=11、FAIL=0；三张矩阵行随机、精确分布和为 1、35 个初始状态、全部 N/种子、误差边界、坐标映射和矩阵保护均通过。
- 收敛结果：N=500/1000/2000/5000/10000 的 p95 最大绝对误差分别为 `0.0408/0.03004/0.0205/0.0133/0.0094`；最坏最大绝对误差为 `0.076/0.051/0.036005/0.023497/0.0163`；平均联合状态 TV 为 `0.1567151/0.1119734/0.0795619/0.0508741/0.0359743`。
- 没有候选 N 同时满足 `p95<=0.02`、`worst<=0.05`、`mean_joint_tv<=0.03`。阈值未放宽，`recommended_N=NONE`，因此按任务要求未生成 `main_path_samples.csv`。
- 本地原始结果：`terminalLoh_wdro/output/stage2a2_W3_path_sampling/run-001/`；Git 归档：`results/task-001-stage2a2-path-prob/02-w3-main-path-sampling/run-001/`。两处均为 8 个文件、2354063 字节，最大文件 `exact_state_distributions.csv` 为 1324844 字节，无文件超过 50 MiB。
- 明确禁止项：未运行风险筛查、尾部加密、正式路径筛选、B3、WDRO、Gurobi、MSP、Foundation 或 Persistence；未修改 main、legacy 配置和默认保护模块。

### 2026-07-15 - task-001 step-02A W3 路径抽样收敛审计 run-002

- 当前分支：`task/001-stage2a2-path-prob`；在现有审计脚本中将运行配置切换为 `run-002`，测试 `N=[15000,20000,30000]`，种子保持 `20260721:20260725`，较小 N 使用同一批 30000 条最大样本的嵌套前缀。
- 保持三项标准不变：p95 最大绝对误差不超过 0.02、最坏最大绝对误差不超过 0.05、平均联合状态 TV 不超过 0.03；没有放宽阈值。
- MATLAB 实际命令：`cd('C:/Users/chaos/Desktop/biye/test/testH2_v2'); run('terminalLoh_wdro/src/run_stage2a2_W3_path_sampling_convergence_h2.m');`。运行成功，仅出现既有 MATLAB 用户搜索路径 warning。
- 自动审计结果：PASS=15、FAIL=0；三张候选矩阵运行前后 SHA-256 和字节一致，run-001 的 8 个文件运行前后快照一致。
- 收敛结果：N=15000/20000/30000 的 p95 最大绝对误差分别为 `0.0074/0.0064333333/0.0054961258`；最坏最大绝对误差为 `0.0154716667/0.014045/0.0121283333`；平均联合状态 TV 为 `0.0296189473/0.0256099632/0.0208151364`。三个 N 均通过，按最小通过规则推荐 `N=15000`。
- 新增转移频率诊断：推荐 N 下 intensity/loc/lfw 的最大概率误差分别为 `0.0006246013/0.0020667105/0.0005007707`；所有 from 状态均有样本，配置概率为 0 的转移观测数为 0。
- 使用固定种子 `20260706` 为 35 个初始状态各生成 15000 条主体完整路径，共 525000 行。`main_path_samples.csv` 为 64519633 字节（61.531 MiB），SHA-256 为 `972a8c58620c09ac19cfcfb29e8d6a3ed2819ef1a22dbd522043436418eb805d`。
- 因主体路径单文件超过 50 MiB，只保留在 `terminalLoh_wdro/output/stage2a2_W3_path_sampling/run-002/`；Git 归档 `results/task-001-stage2a2-path-prob/02-w3-main-path-sampling/run-002/` 不包含该 CSV，使用 `LARGE_FILE_MANIFEST.md` 记录行数、大小和哈希。
- 本地 run-002 共 13 个文件、66581362 字节；归档包含其余 12 个诊断文件和 1 个大文件清单。未覆盖 run-001。
- 明确禁止项：未运行尾部补充、风险筛查、B3、WDRO、Gurobi、MSP、Foundation 或 Persistence；未修改三张候选矩阵、legacy 配置、`.gitignore`、main 或默认保护模块。

### 2026-07-15 - task-001 step-02A 固定种子主体路径样本审计 run-003

- 当前分支：`task/001-stage2a2-path-prob`；新增只读审计入口 `terminalLoh_wdro/src/run_stage2a2_W3_fixed_seed_sample_audit_h2.m`。脚本不调用 `rand/rng/sample_chain`，不重新抽样，也不写入或覆盖 run-002 主体样本。
- 审计源文件：`terminalLoh_wdro/output/stage2a2_W3_path_sampling/run-002/main_path_samples.csv`；固定种子 `20260706`，总行数 525000，35 个初始状态各 15000 行，路径编号和 derived seed 均完整一致。
- 源文件大小 64519633 字节；运行前后 SHA-256 均为 `972a8c58620c09ac19cfcfb29e8d6a3ed2819ef1a22dbd522043436418eb805d`，确认审计未修改原文件。
- 固定样本与精确 W1-W3 矩阵分布比较：p95 最大绝对误差 `0.00806666666667`，最坏最大绝对误差 `0.0131333333333`，平均联合状态 TV `0.02954596508`，非配置 stage 转移记录数和 component 转移数均为 0；四项验收标准全部通过。
- `path_probability` 逐行由三张矩阵重算，最大绝对误差 `4.98732999343332e-18`。该字段仅用于审计；经验分布使用未加权计数，每个初始状态内每条记录的经验权重固定为 `1/15000=6.66666666666667e-05`，后续不得再次按 `path_probability` 加权。
- 自动检查：PASS=18、FAIL=0；三张候选矩阵运行前后哈希一致，矩阵行随机检查通过。
- 首次运行在脚本自身 `fileread` 路径处失败，因为 `mfilename('fullpath')` 未包含 `.m` 扩展名；失败发生在结果写出前。仅修正自身文件路径后重跑成功，未改变任何审计口径或输入。
- 本地输出：`terminalLoh_wdro/output/stage2a2_W3_path_sampling/run-003/`；Git 归档：`results/task-001-stage2a2-path-prob/02-w3-main-path-sampling/run-003/`。两处均为 9 个文件、57184 字节，逐文件 SHA-256 一致；归档不包含 `main_path_samples.csv`，由 `source_sample_manifest.txt` 记录源路径、行数、大小和哈希。
- 明确禁止项：未运行 B3、尾部补充、风险筛查、WDRO、Gurobi、MSP、Foundation 或 Persistence；未修改三张转移矩阵、legacy 配置、`.gitignore`、main、core、longtask 或默认保护模块。

### 2026-07-15 - Codex 与 GitHub 工作规则对齐

- 本次仅更新规则文件：`AGENTS.md`、`codex_rule/core.md`、`codex_rule/longtask.md`、`codex_rule/log.md`；未修改模型、程序、配置、数据或结果。
- 固定 `main` 仅保存已验收稳定版本，开发只在用户指定的 `task/...` 分支进行。
- Git 写操作默认禁止；只有任务明确授权且全部审计通过后，才允许 Commit 和 Push 当前任务分支。Codex 不修改 `main`、不创建或合并 PR、不删除分支、不 force push。
- 小型结果统一归档到 `results/task-xxx/step-xx/run-xxx/`；大型结果保留在 `terminalLoh_wdro/output/`，Git 记录路径、行数、字节数和 SHA-256。
- 同一步骤重跑必须使用新 run 编号，不覆盖旧 run；GitHub 只能审查已 Push 内容，本地未 Push 内容必须明确区分。
- 后续任务提示词可只提供任务目标、允许修改文件、验收条件、输出/run 编号和 Commit/Push 授权，不再重复固定 Git 安全规则。
- 审计失败或新任务与固定规则冲突时必须停止，不得 Commit、Push、绕过或自行解释规则。
- 本次未运行 MATLAB、B3、WDRO、Gurobi 或 MSP。

### 2026-07-16 - task-001 Step-02B-1 主体样本风险尾部与概率质量覆盖审计

- 当前分支：`task/001-stage2a2-path-prob`；新增 `terminalLoh_wdro/src/run_stage2b_observed_tail_coverage_audit_h2.m`。
- 审计只读取 run-002 的 525000 行主体样本；未重新抽样、未生成补充路径、未删除或覆盖主体样本。运行前后 SHA-256 均为 `972a8c58620c09ac19cfcfb29e8d6a3ed2819ef1a22dbd522043436418eb805d`。
- 按35个初始状态和完整 W1-W3 状态序列聚合，得到 256884 条观察唯一路径；每个状态唯一路径数范围 5266–8503，均由 `frequency` 汇总回 15000 行。
- 合法路径数由三张矩阵非零支持的三步路径数相乘得到。路径数量覆盖率范围 `0.0101094767–0.0174146284`；观察唯一路径理论概率质量范围 `0.5887886837–0.7892712024`，35状态等权均值 `0.6675433091`，等权平均未观察质量 `0.3324566909`。
- 风险模型复用已验收 Foundation 口径：`Rmax_ref=40`、风速衰减 `B=0.6`、Vmax 映射 `[0,20.8,28.55,37.05,46.20,55.50]`，电网和道路均使用点到线段距离；电网/道路超限阈值为 25/30 m/s。
- 六个风险代理分别为电网最大风速、电网累计超限、道路最大风速、道路累计超限、电网最长连续超限窗口、道路最长连续超限窗口。分位数仅使用 `frequency/15000` 经验质量；`path_probability` 只从三张矩阵重算用于理论覆盖和 Pareto，不作为经验权重；未构造人为组合总分。
- 35状态等权平均 q95/q99/q99.5：电网最大风速 `39.5430/43.1842/47.2252` m/s；电网累计超限 `641.0882/878.5158/989.1357`；道路最大风速 `39.5430/43.1842/47.2252` m/s；道路累计超限 `477.0645/702.8530/811.7075`；电网连续窗口 `2.2/2.57143/2.71429`；道路连续窗口 `1.77143/2.17143/2.37143`。
- 达到任一风险代理状态级 q99 的唯一路径 117412 条，达到任一 q99.5 的 83309 条；任一代理的低理论概率/高风险 Pareto 非支配唯一路径 324 条。详细高暴露长表有 340173 行，Pareto 长表有 895 行。
- 最终自动审计 PASS=20、FAIL=0。首次运行因参数快照混合 value 列自动类型推断导致 `Rmax_ref` 非有限，未写出结果；改为 key/value 显式 string 导入后同一新 run 成功，不改变审计口径。
- 本地输出：`terminalLoh_wdro/output/stage2b_tail_candidate_design/run-001/`，14个文件、128789346字节。`observed_unique_path_risk.csv` 为47387183字节，`high_exposure_paths.csv` 为81135594字节，两张路径级大表只保留本地。
- Git小型归档：`results/task-001-stage2a2-path-prob/03-stage2b-tail-candidate-design/run-001/`，复制其余12个小型结果并新增 `LARGE_FILE_MANIFEST.md` 记录两张大表的路径、行数、大小和 SHA-256。
- 明确禁止项：未运行固定抗力 B3、尾部补充、WDRO、Gurobi、MSP、Foundation 或 Persistence；未修改三张转移矩阵、legacy配置、`.gitignore`、main或旧run。

### 2026-07-16 - task-001 Step-02B-1 run-002 已观察高风险路径筛选修正

- 当前分支：`task/001-stage2a2-path-prob`；新增 `terminalLoh_wdro/src/run_stage2b_correct_observed_tail_screening_h2.m`。
- 只读取 run-001 的 `observed_unique_path_risk.csv`、`tail_quantiles_by_initial_state.csv` 和覆盖摘要；未重新抽样、未重新计算风场、未重算分位数、未搜索全部合法路径。run-001 五个输入文件运行前后 SHA-256 和字节完全一致。
- 仅处理四个风险代理：电网最大风速、电网累计超限、道路最大风速、道路累计超限。候选规则为风险值大于0，且严格高于阈值或在数值容差内等于阈值；阈值为0时零风险路径不入选。
- 四代理合并去重后的高风险唯一路径数：q95=`23510`、q99=`7316`、q99.5=`4310`；对应35状态等权平均经验质量为 `0.0831257143/0.0212114286/0.0107676190`。
- 合并边界并列路径数：q95=`5541`、q99=`2387`、q99.5=`1497`。状态/代理级输出同时分别记录严格高于与边界并列数量及经验质量。
- Pareto 只在同一状态、同一代理、同一分位层的正风险候选内部筛选，目标为更低 `path_probability` 和更高风险；四代理合并去重后的 Pareto 数为 q95=`268`、q99=`239`、q99.5=`215`。
- 每个代理及四代理合并集合均通过 `q99.5 subset q99 subset q95`；零风险误入数0，Pareto越界数0。`path_probability` 未作为经验权重，经验质量仍为 `frequency/15000`，未构造风险加权总分。
- 最终自动审计 PASS=20、FAIL=0；没有风场函数、随机抽样函数、分位重算函数或全路径枚举调用。
- 本地输出：`terminalLoh_wdro/output/stage2b_tail_candidate_design/run-002/`；小型Git归档：`results/task-001-stage2a2-path-prob/03-stage2b-tail-candidate-design/run-002/`。两处均为11个文件、8375561字节，逐文件SHA-256一致。
- 明确禁止项：未运行全路径搜索、固定抗力B3、尾部补充、WDRO、Gurobi、MSP、Foundation或Persistence；未修改run-001、三张矩阵、legacy配置、`.gitignore`、main或旧run。
