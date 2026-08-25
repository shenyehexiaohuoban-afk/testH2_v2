# FA-MSP OOS 四级检测与 A/B/C/D 运行模式规范

版本：V1.1
日期：2026-08-25
适用对象：FA-MSP 小时级电氢模型及其参数、策略、候选方案和新增机制的样本外（OOS）评估
核心目的：保留统一、可复核的完整检测框架，同时根据研究问题灵活选择分析深度，避免重复运行和过度分析。

文档结构：

- 第一部分：总体框架；
- 第二部分：运行模式、训练状态和证据等级；
- 第三部分：硬规则、默认规则与执行弹性；
- 第四部分：四级完整检测规则；
- 第五部分：模式控制与执行弹性；
- 第六部分：分析控制卡；
- 第七部分：数据保留、输出与采用条件。

---

# 第一部分：总体框架

## 1.1 核心定位

本规范同时管理两个彼此独立的维度：

1. **A/B/C/D 运行模式**：决定本次分析做多深、做多少；
2. **训练状态与证据等级**：决定本次结果有多可信、最多能下多强的结论。

运行模式不等于证据等级。

- 短训练、长训练、稳定训练、未收敛训练，都可以选择 A、B、C 或 D 模式；
- 短训练可以执行 C 或 D 级深度分析，但结论仍须按探索性证据处理；
- 长训练也可以只执行 B 模式，用于快速筛查；
- 分析做得更深，不会自动提高训练结果本身的可信度；
- 最终结论强度由训练可信度、数据完整性、分析深度和统计支持共同决定。

原则上：

$$
\text{结论可信度}
=
\min\left\{
\text{训练可信度},
\text{数据完整性},
\text{分析深度},
\text{统计支持}
\right\}.
$$

---

## 1.2 总体原则

完整检测分为四级：

1. 第一级：结果可信性检测；
2. 第二级：氢准备合理性检测；
3. 第三级：机制、瓶颈和副作用检测；
4. 第四级：完整验证与独立证据。

每次任务采用 A、B、C、D 四种运行模式之一。

| 运行模式 | 名称 | 默认分析范围 | 主要用途 |
| --- | --- | --- | --- |
| A | 工程检查模式 | 工程身份、求解、参数传播、数据保存 | 新结构、新约束、新入口、短训练和 evaluator 检查 |
| B | 快速分析模式 | 第一级 + 第二级快速筛查 | 快速判断改善、恶化或异常信号 |
| C | 深度机制分析模式 | 第一、二、三级 | 解释路径迁移、时间形成、瓶颈和副作用 |
| D | 完整验证模式 | 四级全部执行 | 全面比较、基准验证、敏感性和独立样本评估 |

默认顺序为：

> A 工程检查 → B 快速分析 → C 深度分析 → D 完整验证。

这只是推荐顺序，不是强制顺序。若已有可靠数据或研究问题明确，可以直接选择 B、C 或 D。

四级规则始终保留。未执行的等级或指标统一标记为：

- `DEFERRED`：本次有意暂缓；
- `NOT_APPLICABLE`：本次研究问题不适用；
- `NOT_AVAILABLE`：保存数据不支持；
- `NOT_IDENTIFIABLE`：现有证据不足以判断。

不得把未执行或无法识别的结果推断为改善、恶化或无变化。

---

# 第二部分：运行模式、训练状态和证据等级

## 2.1 A 模式：工程检查模式

### 2.1.1 适用场景

- 新模型结构接入；
- 新约束或新变量；
- 新参数入口或参数覆盖；
- 新候选机制；
- 短训练 smoke；
- 单路径或少量路径 evaluator sanity check；
- checkpoint、runner、loader、forward、backward 或数据结构修改。

### 2.1.2 默认检查项目

- branch、HEAD、runner lineage 和正式入口；
- 模型、policy 和参数身份；
- 参数是否正确传播到 forward、backward、checkpoint 和 OOS；
- 是否出现 infeasibility、NaN、Inf 或异常退出；
- cut、dual、checkpoint 和 clean reload 是否正常；
- OOS 是否调用预定 evaluator；
- 原始数据是否按预定 schema 保存；
- 回归测试是否通过；
- 是否产生未授权的模型、参数或数据修改。

### 2.1.3 默认结论边界

A 模式主要回答工程是否可运行，不宜单独用于判断：

- 自适应性是否增强；
- 终端可靠性是否改善；
- 候选是否优于 Base；
- 候选是否可以采用。

若 A 模式同时使用了充分 OOS 数据并执行了额外分析，结论强度仍由证据等级和实际完成的分析范围决定，不由“A”标签单独决定。

### 2.1.4 建议输出标签

- `ENGINEERING_PASS`
- `ENGINEERING_FAIL`
- `ENGINEERING_MIXED`
- `PERFORMANCE_NOT_EVALUATED`
- `MECHANISM_NOT_EVALUATED`

---

## 2.2 B 模式：快速分析模式

### 2.2.1 适用场景

- 新参数或新机制的初步筛选；
- 长训练或短训练结果的快速评估；
- 多个候选的快速比较；
- 判断是否值得进行深度机制分析；
- 对异常结果进行第一轮定位。

### 2.2.2 默认执行范围

B 模式默认执行：

- 第一级全部核心规则；
- 第二级快速筛查；
- 明显工程风险和性能风险扫描。

第二级快速筛查建议至少包括：

- zero-target、low-target、medium-target、high-target；
- 低目标路径制氢与 surplus；
- 高目标路径 adequate 与 shortfall；
- `PURE_QUANTITY`、`PURE_LOCATION`、`MIXED`；
- Base 与候选的路径迁移；
- ordinary shortage；
- 主要尾部路径组；
- paired KPI、效应量和置信区间。

### 2.2.3 可暂缓项目

- 全路径详细时间线；
- 每个 HTT OD 的完整机制分析；
- 全部物理可恢复性检查；
- 全部站点和小时电压追踪；
- 完美信息基准；
- 固定式、非自适应或 Rolling Horizon 基准；
- 全参数敏感性；
- fresh holdout OOS。

### 2.2.4 建议输出标签

- `PROMISING_SIGNAL`
- `NEUTRAL_SIGNAL`
- `NEGATIVE_SIGNAL`
- `UNEXPECTED_SIGNAL`
- `NOT_IDENTIFIABLE`

上述标签表示观察信号，不自动表示正式采用或淘汰。

---

## 2.3 C 模式：深度机制分析模式

### 2.3.1 适用场景

- B 模式发现重要改善、恶化、矛盾或异常；
- 需要解释结果形成机制；
- 需要定位容量、信息、运输、电网或储罐瓶颈；
- 需要分析路径迁移、时间形成和副作用；
- 需要在多个候选中形成阶段性判断；
- 需要对短训练、长训练、稳定或不稳定结果进行深入诊断。

C 模式不要求必须完成长训练，也不要求训练必须通过正式验收。

### 2.3.2 默认执行范围

C 模式默认完整执行：

- 第一级：结果可信性检测；
- 第二级：氢准备合理性检测；
- 第三级：机制、瓶颈和副作用检测。

### 2.3.3 核心产出

- 低目标路径是否过量准备；
- 高目标路径是否保障不足；
- quantity、location、mixed 问题如何迁移；
- surplus 和 shortfall 如何沿时间形成；
- 自适应决策的方向和效应量；
- Pmax、HTT、电网、储罐和 ordinary demand 等机制证据；
- 是否出现新的副作用；
- 尾部路径和经济性；
- 历史问题状态表；
- 已识别机制、未识别项和后续实验建议。

### 2.3.4 结论边界

C 模式只决定分析深度，不单独决定结论强度。

- 若证据等级为 `EXPLORATORY`，只能形成探索性机制信号；
- 若证据等级为 `FORMAL`，可以形成阶段性候选机制结论；
- 若训练不稳定、字段缺失或统计支持不足，必须降低结论强度；
- C 模式本身不能自动产生 `FINAL_ADOPTED`。

### 2.3.5 建议输出标签

- `EXPLORATORY_MECHANISM_SIGNAL`
- `FORMAL_MECHANISM_SUPPORTED`
- `MIXED`
- `REQUIRE_ADDITIONAL_EXPERIMENT`
- `NOT_IDENTIFIABLE`

---

## 2.4 D 模式：完整验证模式

### 2.4.1 适用场景

- 需要执行四级全部检测；
- 需要进行完整的候选比较；
- 需要加入独立策略基准、敏感性和 fresh holdout；
- 需要评估结果是否具备最终采用或论文证据价值；
- 需要对尚不成熟的结果进行完整诊断。

D 模式可以用于任何训练状态，但只有足够高的证据等级才能形成最终结论。

### 2.4.2 默认执行范围

- 第一、二、三级全部检测；
- 完美信息基准；
- 固定式或非自适应策略基准；
- 条件允许时的 Rolling Horizon 基准；
- 关键参数敏感性；
- fresh holdout OOS；
- 最终图表、证据链和身份冻结检查。

### 2.4.3 建议输出标签

- `COMPREHENSIVE_EXPLORATORY_RESULT`
- `FINAL_ADOPTED`
- `FINAL_REJECTED`
- `HOLDOUT_NOT_SUPPORTED`
- `SENSITIVITY_NOT_ROBUST`
- `FINAL_NOT_IDENTIFIABLE`

`FINAL_ADOPTED` 和 `FINAL_REJECTED` 仅适用于正式、稳定、独立且完整的证据；短训练或不稳定训练即使执行 D 模式，也不能使用这两个标签。

---

## 2.5 训练状态

每次分析必须记录训练状态，建议使用：

- `NOT_APPLICABLE`：本次不涉及训练；
- `SHORT`：短训练或 smoke；
- `LONG_NOT_ASSESSED`：已长训练，但尚未完成稳定性判断；
- `CONVERGED_PASS`：满足预先规定的收敛和稳定性标准；
- `UNSTABLE`：部分指标未稳定；
- `FAILED`：训练、求解或验收失败。

必要时同时保存：

- 训练时长；
- 迭代次数；
- cut 数量；
- 最后窗口的 LB 变化；
- Stage1 或其他关键决策的变化；
- checkpoint 重载结果；
- 正式验收项及失败原因。

训练时长不能替代稳定性判断。长训练可能仍然不稳定，短训练也可能提供有价值的工程或机制信号。

---

## 2.6 证据等级

每次任务必须选择一个证据等级：

| 证据等级 | 含义 | 通常允许的结论 |
| --- | --- | --- |
| `ENGINEERING` | 主要用于程序和数据正确性 | 工程通过、失败或混合 |
| `EXPLORATORY` | 短训练、不稳定训练、已使用样本或初步候选 | 改善、恶化、异常和机制信号 |
| `FORMAL` | 训练通过验收，模型身份和统计比较可信 | 阶段性候选结论 |
| `FINAL_INDEPENDENT` | 正式训练、完整分析、独立样本和关键验证均通过 | 最终采用、淘汰或论文结论 |

证据等级不能仅由运行模式决定，也不能仅由训练时间决定。

以下情况通常需要降低证据等级：

- 训练不稳定或未收敛；
- OOS 路径参与过候选筛选或阈值调整；
- 关键字段缺失；
- 模型身份或参数传播存在未闭合问题；
- 只完成少量路径或少量迭代；
- 主要结论依赖事后选定的路径组；
- 效应小且置信区间不支持稳定方向；
- 机制证据与性能结果相互矛盾。

---

# 第三部分：硬规则、默认规则与执行弹性

## 3.1 不可违反的硬规则

以下规则原则上不可省略：

1. 模型、policy、参数、runner、checkpoint 和路径库身份必须明确；
2. 配对比较必须使用相同 path ID、相同路径顺序和相同终止语义；
3. 路径总账必须闭合；
4. OOS 必须只读，不得继续训练或修改 policy；
5. 不得把路径终止后的不存在时段补零后参与平均；
6. 不得使用当时尚未揭示的未来信息评价当时决策是否错误；
7. 系统总量不足与站点空间错配必须分开；
8. 主要指标、分母、阈值和数值容差必须明确；
9. 不得根据候选结果临时选择有利阈值或路径组；
10. 不得超出证据等级下结论；
11. 数据不足时必须标记 `NOT_AVAILABLE` 或 `NOT_IDENTIFIABLE`；
12. 所有规则例外、替代方法和结论折扣必须记录。

若任务确实无法满足某项硬规则，应停止对应正式结论；可以继续进行受限的工程或探索性诊断，但必须明确限制。

---

## 3.2 可调整的默认规则

以下项目可根据研究问题、数据条件和计算成本调整：

- low、medium、high 的具体阈值；
- difficult、extreme、worst 的具体比例；
- 重点时间窗口；
- 主要指标与次要指标数量；
- 是否执行全部 HTT OD 分析；
- 是否追踪全部电压、线路和变电站状态；
- 是否执行全部物理可恢复性检查；
- 置信区间或显著性检验的具体方法；
- 是否执行完美信息、非自适应或 Rolling Horizon 基准；
- 敏感性参数和范围；
- 图表、表格和报告深度。

调整必须满足：

1. 在控制卡中提前声明，或明确标记为事后诊断；
2. Base 和候选使用相同口径；
3. 不改变核心指标定义；
4. 不制造对某个候选有利的不公平比较；
5. 说明调整原因和结论影响。

---

## 3.3 OOS 运行与结果分析分开

一次 OOS 应尽可能完整保存路径级原始数据，但不要求第一次就执行全部深度分析。

推荐流程：

> OOS 运行一次并完整保存数据 → 按研究问题选择 B、C 或 D 深度 → 后续优先只读复用同一批数据。

从较浅分析升级到较深分析时，应优先读取已保存数据：

- 不重新训练；
- 不重新抽取路径；
- 不重新运行 OOS；
- 不增加 cuts；
- 不修改模型或 policy。

只有以下情况才考虑重新运行 OOS：

- 原始字段不足以完成必要检测；
- policy、模型结构或正式参数发生变化；
- OOS 路径库发生变化；
- 需要 fresh holdout；
- 已确认原 OOS 存在执行或数据错误；
- 需要在新日志 schema 下补充不可替代的物理证据。

是否重跑必须单独说明原因，不能因为要“做更深分析”就自动重跑。

---

# 第四部分：四级完整检测规则

## 4.1 第一级：结果可信性检测

本级回答：这批 OOS 数据是否真实、完整，并且可以公平比较？

### 4.1.1 模型与 policy 身份

固定核对：

- policy 的训练状态和验收状态；
- OOS 是否只读执行；
- Base 与候选是否只改变允许改变的参数或结构；
- TerminalLOH、penalty、随机过程、HTT、储罐、电网及其他冻结输入身份；
- checkpoint 是否正确加载；
- OOS 结果是否对应正确 policy；
- launcher、runner、loader、forward、backward 和 OOS 是否属于预定 lineage；
- 候选新增参数是否传播到全部相关层级；
- 保存结果是否包含模型和路径库身份。

未通过正式训练验收不自动禁止探索性分析，但必须降低证据等级，并禁止形成正式采用或淘汰结论。

### 4.1.2 Common-path 与路径总账

配对比较的 Base 和候选必须使用：

- 同一批 OOS 路径；
- 相同 path ID；
- 相同路径顺序；
- 相同状态历史和外生实现；
- 相同终止语义。

全部路径必须拆分并闭合，例如：

- 到达终端评价阶段；
- 提前消散；
- 进入吸收状态；
- 其他合法终止。

终端评价路径继续拆分为：

- zero-target；
- positive-target。

positive-target 继续拆分为：

- adequate；
- shortfall。

禁止对终止后的不存在时段补零后再计算阶段或小时平均值。

### 4.1.3 统计可信度

主要连续指标建议报告：

- 均值；
- 中位数；
- q95、q99；
- 候选减 Base 的同路径配对差值；
- paired win、loss、tie；
- 效应量；
- 95% 置信区间。

主要比例指标建议报告：

- 分子和分母；
- 比例；
- 候选减 Base 的配对差；
- 路径迁移数量；
- 95% 置信区间。

默认统计建议：

- 连续指标优先使用 path-level paired bootstrap；
- 失败率差优先按同路径二元结果计算配对区间；
- failure/adequate 迁移同时报告完整迁移矩阵；
- 必要时使用 McNemar 检验辅助判断配对比例变化；
- bootstrap 次数、随机种子、tie 容差和缺失值处理必须保存；
- 若采用其他方法，应在控制卡中说明。

### 4.1.4 第一级硬停止条件

出现以下任一情况，停止对应正式比较：

- 模型或 policy 身份无法确认；
- common-path 不一致且任务要求配对比较；
- 路径总账不闭合；
- OOS 继续训练或修改 policy；
- 关键字段错位或无法恢复；
- 存在不能解释的 NaN、Inf 或非法状态；
- 终止后补零污染统计结果；
- Base 与候选改变了未授权的参数。

在保留明确错误边界的前提下，可以继续进行工程排错或受限探索，但不得形成正式性能结论。

---

## 4.2 终端氢量统计口径

设站点目标为 $T_i$，终端库存为 $I_i$。

### 4.2.1 逐站缺口

$$
G_{\mathrm{site}}
=
\sum_i\max(T_i-I_i,0).
$$

它表示按照站点目标逐站考核后的总缺口。

### 4.2.2 系统总量缺口

$$
G_{\mathrm{quantity}}
=
\max\left(\sum_iT_i-\sum_iI_i,0\right).
$$

它只判断系统总库存是否足够，不考虑空间位置。

### 4.2.3 空间错配分量

$$
G_{\mathrm{location}}
=
G_{\mathrm{site}}-G_{\mathrm{quantity}}.
$$

### 4.2.4 逐站剩余量

$$
S_{\mathrm{site}}
=
\sum_i\max(I_i-T_i,0).
$$

### 4.2.5 统一分类

设数值容差为 $\varepsilon$，默认建议为 $10^{-6}$ kg；如求解容差不同，可在控制卡中修改。

- `ADEQUATE`：$G_{\mathrm{site}}\le\varepsilon$；
- `PURE_QUANTITY`：$G_{\mathrm{quantity}}>\varepsilon$ 且 $G_{\mathrm{location}}\le\varepsilon$；
- `PURE_LOCATION`：$G_{\mathrm{quantity}}\le\varepsilon$ 且 $G_{\mathrm{location}}>\varepsilon$；
- `MIXED`：$G_{\mathrm{quantity}}>\varepsilon$ 且 $G_{\mathrm{location}}>\varepsilon$。

分类必须通过库存恒等关系复核，确保不重叠、不遗漏。

positive-target shortfall rate 的默认分母为 positive-target 终端评价路径数，不得使用全部 OOS 路径或全部终端路径代替。若报告其他分母，必须明确名称和用途。

---

## 4.3 第二级：氢准备合理性检测

本级回答：应该少准备的路径有没有准备过多，应该多准备的路径有没有准备不足？

### 4.3.1 按最终目标分组

终端评价路径可分为：

- zero-target；
- low-target；
- medium-target；
- high-target。

分组阈值必须：

- 在控制卡中给出定义或来源；
- 对所有 Base 和候选保持一致；
- 原则上在查看候选比较结果前冻结；
- 若为事后设置，标记为 `RETROSPECTIVE_GROUPING`；
- 对阈值变化敏感时，补充稳健性检查。

每组建议比较：

- 最终目标；
- 初始库存；
- 总制氢量；
- ordinary demand 实际供氢量；
- ordinary shortage；
- 最终库存；
- site surplus；
- site gap；
- quantity gap；
- 实际运行成本。

### 4.3.2 低目标路径过量制氢

对 zero-target 和 low-target 路径检查：

- 最终只需要很少氢时，模型是否仍大量制氢；
- 扣除 ordinary demand 后，为终端储备增加了多少氢；
- 最终库存超过目标多少；
- 多余氢是什么时候生产的；
- 风险降低以后是否仍继续制氢；
- 候选是否更及时停止不必要的生产。

解释时必须区分：

- 风险揭示前的多制氢：可能属于合理保险型准备；
- 低风险基本明确后的持续制氢：过量准备信号更强。

### 4.3.3 高目标路径保障能力

对 high-target 路径检查：

- adequacy；
- shortfall rate；
- conditional site gap；
- quantity 和 location 分量；
- 最后若干小时或阶段的制氢量；
- 新增能力是否真正投入使用；
- 是否因等待过久而无法追上；
- ordinary demand 是否因此恶化。

时间窗口可根据实际时段结构选择，并在控制卡中说明。

### 4.3.4 不足类型分类

所有 shortfall 路径统一使用第4.2节的定义分为：

- `PURE_QUANTITY`；
- `PURE_LOCATION`；
- `MIXED`。

不得使用“总量充足率”替代逐站可靠性，也不得把逐站缺口全部解释为总量不足。

### 4.3.5 路径迁移

使用相同 path ID，逐条比较 Base 与候选：

- failure → adequate；
- adequate → failure；
- quantity → adequate；
- location → adequate；
- mixed → adequate；
- adequate → quantity/location/mixed；
- quantity、location、mixed 之间的相互迁移；
- persistent failure；
- persistent adequate。

不能只比较净失败数量。必须同时报告：

- 新增失败；
- 恢复路径；
- 持续失败；
- 失败类型变化；
- 各迁移组对总 gap 变化的贡献。

### 4.3.6 制氢与库存形成时间

以终端评价时点为0，向前选择适合本模型的时间窗口。建议观察：

- 小时和阶段制氢量；
- 累计制氢量；
- 系统总库存；
- 各站库存；
- HTT；
- ordinary shortage；
- 电解槽利用率；
- 当时已揭示的风险状态。

只使用真实存在时点，不对不存在时段补零。

重点回答：

- surplus 是什么时候建立的；
- shortfall 是什么时候开始落后的；
- 低目标路径在风险下降后有没有及时停产；
- 高目标路径在风险升高后有没有及时追产；
- 生产是前移还是后移；
- 新增能力何时、何地被实际使用。

### 4.3.7 自适应与 wait-and-see 检测

不能只看 Stage1 或第一阶段制氢量。建议同时检查：

- 信息分叉前准备量；
- shared-prefix 下决策一致性；
- 信息分叉后高风险与低风险路径的决策差异；
- 低风险路径是否减少制氢；
- 高风险路径是否及时增加制氢；
- 后期制氢占比；
- 达到并维持目标的时间；
- large surplus 是否减少；
- terminal protection 是否恶化；
- 分叉后的适应方向和效应量。

真正的 wait-and-see 通常表现为：

> 信息分叉前减少不必要的统一准备；信息分叉后低风险路径少生产，高风险路径及时增加生产。

不得使用最终信息事后要求早期决策“本应知道”未来结果。

---

## 4.4 第三级：机制、瓶颈和副作用检测

本级回答：为什么会准备过多或不足，解决旧问题以后是否制造了新问题？

### 4.4.1 物理可恢复性

对 shortfall 路径，在若干终端前时间窗口检查：即使后续尽可能行动，该路径是否仍可能达到目标？

统一分类：

- `PHYSICALLY_UNRECOVERABLE`；
- `OPTIMISTICALLY_RECOVERABLE`；
- `NOT_IDENTIFIABLE`。

该检测用于区分：

- policy 未充分行动；
- 设备能力不足；
- 风险揭示过晚；
- 电网、储罐、运输或空间限制导致无法追赶。

乐观上界证明追不上是强证据；未被证明追不上，不代表实际一定能追上。

### 4.4.2 机制瓶颈

根据研究问题选择并记录检查顺序。默认可包括：

1. 电解槽 Pmax；
2. 电压；
3. 线路容量；
4. 变电站容量；
5. 储罐容量和 headroom；
6. HTT 总运力；
7. HTT 道路、OD 和方向；
8. HTT 调拨时机与到达时机；
9. 站点空间配置；
10. ordinary demand；
11. 候选新增机制及其约束。

每个机制结论尽量给出：

- 对应路径或路径组；
- 阶段或小时；
- 站点、节点或 OD；
- 数值证据；
- 对照组；
- 证据边界。

必须区分：

- 最终事后看行动方向不理想；
- 当时已有信息下能够证明行动不合理。

保存数据不足时标记 `NOT_IDENTIFIABLE`，不得强行归因。

### 4.4.3 新问题与副作用

即使主要指标改善，也建议检查：

- 低目标路径是否生产更多；
- surplus 是否增加；
- 初期生产是否重新接近满负荷；
- ordinary shortage 是否恶化；
- 电压是否形成新瓶颈；
- tank saturation 是否增加；
- HTT 是否异常增加或重新分配；
- line/substation 是否由非瓶颈变成瓶颈；
- 实际成本是否明显增加；
- 数值稳定性是否恶化；
- 候选是否只改善平均值而恶化尾部。

禁止只因单一 gap 或成本下降就宣布成功。

### 4.4.4 尾部路径

可根据任务选择 normal、difficult、extreme、worst 或其他尾部路径组。

尾部组必须：

- 使用预先冻结的定义；
- Base 和候选使用同一组 path ID；
- 说明是按风险、目标、Base 结果还是其他外生标准定义；
- 若为事后选取，明确标记 retrospective；
- 不得为各候选分别重新选择最差路径后直接比较。

建议比较：

- site gap 和 quantity gap；
- surplus；
- ordinary shortage；
- 制氢量；
- 电压和设备利用率；
- HTT；
- 实际运行成本。

重点判断：

- 改善是否只出现在普通路径；
- 主要困难路径是否真正受益；
- 极端路径是否恶化；
- 尾部路径对总缺口的贡献是否下降。

### 4.4.5 经济性

根据模型实际结构分开报告：

- 制氢和购电成本；
- 储氢成本；
- HTT 成本；
- ordinary shortage 成本；
- 候选新增机制成本；
- terminal gap penalty；
- 剩余氢价值或处置成本；
- 不包含惩罚项的实际运行成本。

必须回答：

> 指标改善来自更合理的自适应决策，还是单纯投入更多容量、提前生产更多氢或支付更多成本？

建模惩罚项与实际物理运行成本必须分开，不能把 penalty 的下降直接解释为实际经济收益。

### 4.4.6 历史问题状态表

根据项目历史和本次研究问题维护状态表。默认可跟踪：

- early commitment；
- weak wait-and-see effect；
- low-target overproduction；
- large surplus；
- pure quantity shortage；
- pure location shortage；
- mixed shortage；
- HTT aggregate capacity；
- HTT information limitation；
- HTT spatial value；
- electrolyzer Pmax bottleneck；
- voltage、line、substation；
- tank saturation；
- ordinary shortage；
- tail concentration；
- actual cost；
- training stability；
- checkpoint reliability；
- 新增问题。

统一建议标签：

- `IMPROVED`
- `WORSE`
- `UNCHANGED`
- `MIXED`
- `RESOLVED_ENGINEERING`
- `NOT_IDENTIFIABLE`
- `NEW_RISK`
- `NOT_APPLICABLE`

每个标签应链接到具体表格、路径、数值或图件证据。

---

## 4.5 第四级：完整验证与独立证据

本级回答：在更严格的基准、敏感性和独立样本下，主要结论是否仍然成立？

### 4.5.1 完美信息基准

对同一条路径，在明确的信息假设下求得理想结果，并与 FA-MSP 比较：

- 制氢量；
- surplus；
- site gap 和 quantity gap；
- ordinary shortage；
- 实际成本。

完美信息只应包含模型中真实存在但尚未提前揭示的不确定信息。已知确定参数不应被重复视作未来信息。

该检测用于衡量未来信息未知带来的保险成本和适应性损失。

### 4.5.2 不同策略基准

根据研究问题选择：

- FA-MSP；
- 固定式提前准备策略；
- 非自适应策略；
- 完美信息策略；
- 条件允许时的 Rolling Horizon。

比较目的应在控制卡中说明，避免为了增加结果数量而设置无关基准。

### 4.5.3 敏感性分析

对少量关键参数进行预先设计的敏感性检查，例如：

- penalty；
- Pmax；
- 电价或时间成本；
- 储氢成本；
- HTT 成本或能力；
- 初始风险状态；
- 到达时间或终止阶段；
- 候选机制关键参数。

检查主要结论是否稳定：

- 低目标路径是否仍能减少过量准备；
- 高目标路径是否仍有保障；
- wait-and-see 是否仍存在；
- 空间错配是否仍受控制；
- 尾部和成本是否可接受。

### 4.5.4 Fresh holdout OOS

若当前 OOS 路径已经参与参数调整、候选筛选、阈值选择或机制判断，则不能单独作为最终独立证据。

最终候选确定后，应在条件允许时生成一批未参与上述过程的新 OOS 路径。只有 fresh holdout 仍支持相同结论，才具备：

- 最终采用；
- 写入论文主要结论；
- 冻结最终参数和模型版本。

若因计算或数据限制无法执行 fresh holdout，应明确降低证据等级，不能用旧样本冒充独立验证。

---

# 第五部分：模式控制与执行弹性

## 5.1 模式选择与升级

模式升级不是必须步骤。可以根据任务直接选择最合适的深度。

通常值得从 B 升级到 C 的信号包括：

- positive-target shortfall 出现实质变化；
- low-target 制氢或 surplus 出现实质变化；
- quantity、location 或 mixed 路径发生明显迁移；
- 出现较多新的 adequate → failure；
- ordinary shortage 明显变化；
- 尾部路径明显恶化；
- 平均指标与路径迁移相互矛盾；
- 结果与理论预期相反；
- 需要解释候选机制。

“实质变化”的判断标准应尽量在控制卡中提前定义。若属于事后异常诊断，应明确标记 retrospective，不得伪装成预设检验。

通常值得进入 D 的情况包括：

- 需要完整基准和敏感性；
- 候选接近最终决策；
- 需要检验结果能否在 fresh holdout 上复现；
- 需要形成最终论文证据；
- 需要对重要但不成熟的结果进行完整诊断。

进入 D 不代表证据自动达到最终等级。

---

## 5.2 停止规则

默认情况下，每种模式完成预定范围后停止，不自动升级、不自动训练、不自动重新运行 OOS，也不自动修改模型。

遇到以下情况应立即停止对应正式结论：

- 身份或 common-path 失败；
- 路径总账不闭合；
- 数据污染或字段错位；
- 未授权参数变化；
- 关键公式或分母不一致；
- 结果依赖未来信息泄漏；
- 训练状态不足以支撑拟下结论；
- 主要证据相互矛盾且无法解释。

停止正式结论后，仍可在授权范围内进行工程排错或探索性诊断。

---

## 5.3 弹性执行原则

本规范提供默认框架，不要求每次机械执行全部条目。

允许根据研究问题：

- 增减非核心指标；
- 调整分组阈值和尾部比例；
- 缩小或扩大时间窗口；
- 选择重点站点、节点、OD 或路径组；
- 使用适合数据分布的统计方法；
- 跳过不适用或无法识别的机制；
- 增加新的针对性诊断。

但所有弹性必须满足：

1. 不违反第3.1节硬规则；
2. 在控制卡或报告中说明；
3. Base 和候选保持公平；
4. 结论强度同步调整；
5. 不把缺失分析解释为没有问题。

---

# 第六部分：分析控制卡

## 6.1 标准控制卡模板

每次任务不需要重复粘贴本文件，只需引用本规范版本并填写控制卡。

```text
OOS_ANALYSIS_PROTOCOL = FOUR_LEVEL_ABCD_V1_1

RUN_MODE =
A / B / C / D

ACTIVE_LEVELS =
本次实际执行的等级和范围

TRAINING_STATUS =
NOT_APPLICABLE / SHORT / LONG_NOT_ASSESSED /
CONVERGED_PASS / UNSTABLE / FAILED

EVIDENCE_GRADE =
ENGINEERING / EXPLORATORY / FORMAL / FINAL_INDEPENDENT

ANALYSIS_NATURE =
PREDECLARED / RETROSPECTIVE_DIAGNOSTIC / MIXED

RESEARCH_QUESTION =
本次唯一或主要研究问题

BASE_POLICY =
基准 policy 身份

CANDIDATE_POLICY =
候选 policy 身份

ALLOWED_CHANGE =
本次唯一允许改变的模型参数或结构

FROZEN_IDENTITIES =
本次必须保持不变的模型、输入和参数身份

OOS_PATH_BANK =
路径库身份、路径数量、是否 common-path、是否 holdout

PRIMARY_METRICS =
本次最重要的 3 至 6 个指标

SECONDARY_METRICS =
辅助指标

SPECIAL_COHORTS =
重点路径组及其冻结定义

GROUPING_RULES =
zero/low/medium/high、tail 等分组方法

NUMERICAL_TOLERANCE =
gap、tie、可行性等数值容差

STATISTICAL_METHOD =
配对区间、bootstrap、检验及随机种子

MATERIAL_CHANGE_THRESHOLDS =
预先设定的实质变化标准；若无则说明

OPTIONAL_ANALYSES =
本次选择执行的附加分析

UPGRADE_PERMISSION =
NO / ALLOW_A_TO_B / ALLOW_B_TO_C / ALLOW_C_TO_D

DEEP_ANALYSIS_TRIGGER =
出现哪些结果才建议或允许升级

STOP_CONDITION =
在哪一级结束；出现哪些异常立即停止

DEFERRED_LEVELS =
本次不执行的等级或项目

RULE_EXCEPTIONS =
本次未执行或调整的默认规则

EXCEPTION_REASON =
调整原因

DATA_LIMITATIONS =
保存数据无法支持的检测

CONCLUSION_DISCOUNT =
由于训练、数据或统计限制需要怎样降低结论强度

FINAL_ALLOWED_CONCLUSION =
本次最多允许形成什么程度的结论
```

---

## 6.2 通用 B 模式示例

```text
OOS_ANALYSIS_PROTOCOL = FOUR_LEVEL_ABCD_V1_1

RUN_MODE = B

ACTIVE_LEVELS =
LEVEL_1_FULL
+
LEVEL_2_SCREEN

TRAINING_STATUS =
按实际填写

EVIDENCE_GRADE =
按实际填写

ANALYSIS_NATURE =
PREDECLARED 或 RETROSPECTIVE_DIAGNOSTIC

RESEARCH_QUESTION =
候选是否改善主要目标，同时避免新的副作用

BASE_POLICY =
基准 policy 身份

CANDIDATE_POLICY =
候选 policy 身份

ALLOWED_CHANGE =
本次唯一允许变化的参数或结构

OOS_PATH_BANK =
冻结的 common-path bank

PRIMARY_METRICS =
positive-target shortfall rate
site gap
quantity gap
ordinary shortage
surplus
actual cost

SPECIAL_COHORTS =
根据研究问题填写

MATERIAL_CHANGE_THRESHOLDS =
运行前填写；事后诊断则明确标记 retrospective

UPGRADE_PERMISSION =
NO

STOP_CONDITION =
LEVEL_2_SCREEN 完成后停止

DEFERRED_LEVELS =
LEVEL_3_DEFERRED
LEVEL_4_DEFERRED

FINAL_ALLOWED_CONCLUSION =
按证据等级填写，不得超出证据支持范围
```

---

# 第七部分：数据保留、输出与采用条件

## 7.1 OOS 原始数据保留

只要运行了有研究价值的 OOS，应尽可能保存：

- path ID；
- 外生状态与信息历史；
- 到达阶段和终止原因；
- TerminalLOH 总量与站点目标；
- 小时和阶段制氢；
- 电解槽功率与利用率；
- 系统和站点库存；
- ordinary demand、served demand 与 shortage；
- HTT 总量、方向、OD 流和到达时间；
- 道路可达性和能力；
- 电压、线路和变电站状态；
- 储罐状态与 headroom；
- 候选新增决策变量和状态；
- site gap、quantity gap、location component 和 surplus；
- 实际成本分项与 penalty；
- policy、模型、参数和路径库身份；
- 训练状态、checkpoint 和 cut 身份。

数据应尽量支持后续只读升级分析，而无需重新运行 OOS。

---

## 7.2 C 模式建议结果结构

深度分析报告建议包括：

1. 分析控制卡；
2. 结果是否可信；
3. OOS 总账与统计可信度；
4. 总体 paired performance；
5. 按目标分组的表现；
6. 低目标过量准备；
7. 高目标保障能力；
8. quantity、location、mixed；
9. 路径迁移；
10. 时间形成与 wait-and-see；
11. 物理可恢复性；
12. Pmax、HTT、电网、储罐等机制；
13. ordinary demand 和其他副作用；
14. 尾部路径；
15. 经济性；
16. 历史问题状态表；
17. 新问题扫描；
18. 证据等级、限制和结论折扣；
19. 后续实验建议。

若某项不适用或数据不足，应保留标题并标记 `NOT_APPLICABLE`、`NOT_AVAILABLE`、`DEFERRED` 或 `NOT_IDENTIFIABLE`，避免静默删除。

---

## 7.3 候选进入最终独立验证的参考条件

以下是参考条件，不是机械的一票否决表。应结合研究目标、效应量和证据等级判断。

候选通常应尽量满足：

- 主要目标指标出现有意义的改善；
- 低目标路径不过度增加生产和 surplus；
- 高目标路径保障能力不下降；
- 旧失败有明确路径被救回；
- 没有大量产生新的空间错配；
- 改善不只是重新提前满产；
- ordinary shortage、电压、储罐、尾部和实际成本没有不可接受的恶化；
- paired 结果支持稳定方向；
- 机制证据与物理审计相互一致；
- 未发现尚未处理的新硬问题。

最终采用通常还需要：

- 合适的策略基准；
- 关键敏感性分析；
- fresh holdout OOS；
- 稳定、可复核的模型和参数身份；
- 结论能够在独立证据上复现。

如果研究目标本身允许某些指标进行权衡，应在控制卡中提前规定接受标准，不要求所有指标同时改善。

---

## 7.4 一句话执行规则

> A 查工程，B 快速看信号，C 深入解释机制，D 做完整验证；模式只决定分析深度，训练状态和证据等级决定结论可信度；硬规则必须遵守，默认规则可以在记录理由后灵活调整。

---

## 7.5 方法来源说明

本规范综合：

- FA-MSP 小时级电氢项目中 OOS、TerminalLOH、HTT、Pmax、wait-and-see、路径迁移和物理可恢复性分析经验；
- 多阶段随机规划中 common random numbers、paired comparison、完美信息基准、非自适应基准、Rolling Horizon、敏感性分析和 fresh holdout 的一般评估思路；
- Siddig 与 Song 关于 FA-MSP OOS 评估、策略比较、阶段准备量和敏感性分析的方法框架。

参考文献：

Murwan Siddig and Yongjia Song, “Multistage stochastic programming with a random number of stages: Applications in hurricane disaster relief logistics planning,” *European Journal of Operational Research*, 2025, 321(3): 925–941. DOI: 10.1016/j.ejor.2024.10.004.
