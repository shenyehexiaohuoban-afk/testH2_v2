# 版本树

Stage 编号不是继承证据。下列树只画有 README、launcher、路径、参数/hash 或 log 支持的关系；交叉来源用 `+`，不确定早期关系标 `UNCERTAIN`。

## W / TerminalLOH 模型与数据

```text
legacy wind_mc / roadSoft / RiskCap-Mean                         [SUPERSEDED]
└─ early W3 B1/B2 D-A-C + Wasserstein ground-cost experiments   [HISTORICAL]
   └─ formal stagewise-random B3 freeze                         [HISTORICAL]
      └─ three-period consequence model                         [HISTORICAL]
         └─ Step04A probability-DRO feasibility                 [HISTORICAL]
            └─ Step04B flat Pearson chi-square solver           [ACCEPTED METHOD]
               └─ C5B unified TerminalLOH economics
                  └─ C5C eta-response
                     └─ Stage53 35-state SAA / eta=.03 tables    [SUPERSEDED INPUT]

Stage86 current-W geometry audit                                [DIAGNOSTIC]
└─ Stage87A candidate preview                                   [DIAGNOSTIC]
   └─ Stage87B W kernel + geometry + A/B/C integration           [ACCEPTED]
      ├─ Stage87C-A 35×15000 formal nominal bank                [ACCEPTED DATA]
      │  ├─ Stage87C-B0 recourse wind audit                     [DIAGNOSTIC]
      │  ├─ Stage87D-A Candidate-1 fragility preview            [CANDIDATE]
      │  │  └─ Stage87D-A1 unreachable/edge criticality         [DIAGNOSTIC]
      │  └─ Stage87D-B H1
      │     └─ Stage87D-B H2 retained hardening                 [ACCEPTED COMPUTATIONAL]
      │        └─ Stage88A new H2 consequence bank
      │           ├─ CAP150 SAA / DRO                           [HISTORICAL ARM]
      │           ├─ CAP200 SAA                                 [ACCEPTED COMPARATOR]
      │           └─ CAP200 DRO eta=.03                         [SUPERSEDED PREDECESSOR]
      │              ├─ Stage88A1 all-site capacity post-audit  [DIAGNOSTIC]
      │              ├─ Stage88D 35-state reconciliation        [DIAGNOSTIC]
      │              └─ Stage88E state11/28 tail diagnostic     [DIAGNOSTIC]
      │                 └─ Stage89A Stage88 bundle               [HISTORICAL INDEX]
      └─ Stage87D-C capacity lineage audit                      [DIAGNOSTIC]

Stage88A CAP200
├─ Stage88B Site1=350                                           [SENSITIVITY ONLY]
└─ Stage88C Site4=250                                           [SENSITIVITY ONLY]
```

## FA-MSP 模型结构

```text
legacy aggregate FA-MSP (6h defaults)
├─ Stage55 native smoke
│  └─ Stage56 dual TerminalLOH loader
│     └─ Stage57 Stage53 fixed-budget A/B                       [HISTORICAL]
│        ├─ Stage71 8h capacity sensitivity                     [SENSITIVITY]
│        └─ Stage73 HTT-cost sensitivity                        [SENSITIVITY]
└─ Stage79 hourly IEEE33 0.95–1.05                              [FAILED]
   └─ Stage80 hourly IEEE33 0.90–1.10                           [ACCEPTED STRUCTURE]
      ├─ Stage81 short-training/checkpoint pilot                [FAILED/PARTIAL]
      └─ Stage82 Stage7/8 semantics fix                         [ACCEPTED STRUCTURE]
         └─ Stage84 formal hourly-grid training/OOS
            ├─ Stage84A typed-empty OOS schema fix
            ├─ Stage84B common-path OOS
            └─ Stage84C–E mechanism/figure diagnostics
               └─ Stage85A H2 time-scale audit                  [DIAGNOSTIC]
                  └─ Stage85B hourly H2 balance
                     ├─ Stage85C representative smoke
                     ├─ Stage85D batch stress
                     └─ Stage85G hourly HTT
                        └─ Stage85H training pilot
                           ├─ Stage85H-A checkpoint fix          [RUNNER, not model]
                           └─ Stage85H-B finalizer recovery      [RECOVERY]
                        └─ Stage85I block-uniform demand         [SUPERSEDED DATA]
                           └─ Stage85J demand source audit       [DIAGNOSTIC]
                              └─ Stage85K original hourly demand [ACCEPTED DATA/MODEL]
                                 └─ Stage85L DRO pilot
                                    └─ Stage85L-A finalizer fix
                                       ├─ Stage85N/O/P/Q parameter/mechanism branches
                                       └─ Stage85R P150/P200 5h + 10k OOS [ACCEPTED RUNNER]
```

## Stage88 接入与 6h/8h 分叉

```text
Stage89A W bundle/integration audit
└─ Stage89B CAP200 candidate MAT + Stage88 DRO table bridge
   ├─ legacy defaults + aggregate builder
   │  └─ Stage89C 10iter/3loc OOS                               [HISTORICAL 6h]
   │     └─ Stage89D penalty 2000/1500/1000                     [SENSITIVITY 6h]
   │        └─ Stage89E 90.09 source audit                      [DIAGNOSTIC]
   └─ Stage80 + Stage82 + Stage85B + Stage85G + Stage85K
      └─ Stage89F isolated current 8h model entry               [CURRENT MODEL]
         └─ Stage89G formal runner adaptation                   [CANDIDATE RUNNER]
```

## Training / checkpoint / OOS 工程（多父节点）

```text
Stage84 formal runner groundwork
└─ Stage85H fresh SAA/DRO pilot + checkpoint + diagnostics
   ├─ run-001 same-process reload OOM                           [FAILED]
   └─ Stage85H-A
      ├─ temp -v7.3 -> whos schema -> atomic move
      ├─ training process exits
      ├─ clean process loads once
      └─ hash/cut/schema PASS gates next phase                  [ACCEPTED MECHANISM]

Stage85K complete 8h hourly model
+ Stage85H-A process boundaries
└─ Stage85R P150/P200 5h fixed-budget training
   ├─ fresh checkpoint per arm
   ├─ clean checkpoint audit
   ├─ new common 10k path bank
   └─ paired OOS + recovery finalizer                           [ACCEPTED RUNNER MOTHER]

Stage89F current 8h model/input
+ Stage85H-A clean-process mechanism
+ Stage85R formal training/OOS engineering pattern
└─ Stage89G new adaptation
   ├─ run-001 duplicate training-table name                    [FAILED SCHEMA]
   ├─ run-001 monolithic same-process reload                    [FAILED OOM]
   └─ run-002 staged orchestrator
      ├─ INIT
      ├─ TRAIN -> save -> exit
      ├─ clean reload adapter -> PASS
      ├─ OOS loc1/4/7 × 10000
      └─ FINALIZE/QA                                            [CANDIDATE]

Stage85R accepted single-state runner
+ Stage85H-A clean checkpoint lifecycle
+ Stage89F current 8h model/input
+ Stage88 DRO CAP200 TerminalLOH
└─ Stage89H single loc4, gap penalty1000
   ├─ params.k_init = loc4 / internal index 81
   ├─ fresh 10 iterations; zero initial cuts
   ├─ TRAIN -> save -> exit -> external SHA
   ├─ clean process single load -> audit PASS
   └─ loc4 10000-path same-state OOS                           [CANDIDATE]
```

Stage89G 的代码复用不是“文件原样复制”：safe-save 与 clean-reload 行为模式来自 Stage85H-A，Stage89G 的 identity checks、三地 OOS、SHA/cut-coefficient audit、finalizer 和 orchestrator 是新写适配；Stage85R 提供正式 runner 设计母版而不是 checkpoint 父节点。

Stage89H 与 Stage89G 是不同实验语义的并列候选，不存在 Stage89G -> Stage89H 继承边。Stage89H保留Stage85R单一`params.k_init`的Stage1 cut行为；上一轮multiloc阻塞通过实验设计修正解决，未修改backward core。

## 参数与诊断旁支

```text
Stage85K/85L model
├─ Stage85N shortage=100, c0=5                                [DIAGNOSTIC]
├─ Stage85O economic calibration                              [SENSITIVITY]
├─ Stage85P shortage=150                                      [SENSITIVITY]
├─ Stage85Q P150 fragmentation                                [DIAGNOSTIC]
└─ Stage85R P150 vs P200                                      [ACCEPTED COMPARISON]
   ├─ Stage85S/T/U figures and wait-and-see audits             [DIAGNOSTIC]
   ├─ Stage85V/W/X geometry/consequence/tail diagnostics       [DIAGNOSTIC]
   └─ Stage85Y A/B/C mechanism interventions                   [SMOKE/SENSITIVITY]

Stage88A CAP200
├─ Stage88B Site1=350                                         [SENSITIVITY]
└─ Stage88C Site4=250                                         [SENSITIVITY]

Stage89C legacy-6h penalty=2000
└─ Stage89D penalty=1500 / 1000                               [SENSITIVITY, DO NOT ADOPT]

Stage87C-A exact W failure realizations
+ Stage88 CAP200 SAA/DRO TerminalLOH
+ Stage89A current W index
└─ D01 outage/D/T/tie-line offline audit                       [DIAGNOSTIC ONLY]
   ├─ physical lost load and D distributions
   ├─ D versus TerminalLOH separation
   ├─ critical feeder-line ranking
   ├─ five-tie connectivity-only restoration upper bound
   └─ D02 five-point + paired G1/G2 hardening preview           [METHOD PREVIEW]
      ├─ same frozen resistance threshold; M12/M23 hazard updates
      ├─ 3 h D retained on W1/W2/W3; roads retained at three points
      ├─ 1-2/2-3 strong sensitivity value = HIGH
      ├─ 3-4/4-5/5-6 additional moderate value = LOW
      └─ D03 topology-based H2 island candidate diagnostic       [DIAGNOSTIC ONLY]
         ├─ tie lines are binary switches; MAT-order Kruskal forest
         ├─ all unique failure topologies radial and source-maximal
         ├─ H2-site component is topology candidate only
         └─ no FC dispatch, grid-forming, inventory coupling or model change
```

## D04 方法预览旁支

```text
D02 G1 frozen five-point candidate
+ D03 deterministic radial topology and H2-site components
+ Stage88 current road A/C and DRO CAP200 T (read-only)
+ candidate MAT FC power/efficiency/LHV fields
└─ D04 topology-based H2 dual-channel minimal model              [METHOD PREVIEW]
   ├─ D_res after tie reconstruction
   ├─ topology-derived A_elec
   ├─ static one-slice FC-equivalent H2 cap
   ├─ electrical + road channels debit one shared T
   ├─ 9 real scenarios × 3 T cases × 2 service cases; 7/7 tests PASS
   └─ Stage89I full frozen exact-support/cost audit               [DIAGNOSTIC ONLY]
      ├─ OLD 457414 -> NEW 457431; median/max 1/1.000868
      ├─ topology cache 160862; exact grouping reproduced 35/35
      ├─ DRO support 1.000037x; conservative LP structure 1.126051x
      └─ Stage89J formal isolated grouped candidate bank          [FORMAL W CANDIDATE]
         ├─ 35×15000 frozen draws; no W/grid/road redraw
         ├─ NEW support 457431; q=multiplicity/15000
         ├─ 35 MATLAB-readable MAT banks; 1104251473 bytes
         ├─ NOT current W / accepted TerminalLOH / MSP-accepted
         └─ Stage89K formal TerminalLOH evaluation              [FORMAL TERMINALLOH CANDIDATE]
            ├─ Stage88 economics/Pearson/LP/tolerances frozen
            ├─ separate road/electrical service; shared T; static FC caps
            ├─ 35 SAA + 35 DRO OPTIMAL; all QA PASS
            ├─ mean T: SAA -30.978%; DRO -27.438% vs Stage88
            └─ NOT current TerminalLOH / current W / MSP-accepted
```

D04 and Stage89I remain diagnostic/method-preview nodes. Stage89J and Stage89K were formally adopted by Stage89M; their historical candidate outputs remain immutable. D04 runs 001-005, Stage89I run-001 and Stage89K run-001 are preserved failures; D04 run-006, Stage89I run-002 and Stage89K run-002 are successful evidence/candidate nodes, while Stage89J run-001 is the isolated formal bank construction.

## 未解析边界

- 部分早期 result 目录只说明审计顺序，没有明确 `based on`；它们在 CSV 中用 `UNCERTAIN` 或较低 confidence，而没有按 Stage 号强制串联。
- Stage85+ 关键源文件不属于当前 Git HEAD；谱系能通过路径、README、source markers 与 hash 解析，但不能用 commit 单独复现字节。
- Stage89G run-002 在审计快照有外部 MATLAB 进程运行。本审计没有读取其高频日志，故树只登记 runner candidate，不登记最终科学结果。


## Stage89 formal adoption and integration

```text
Stage89J formal W candidate
+ Stage89K formal TerminalLOH candidate
+ Stage89L formal mechanism ablation/adoption recommendation
+ Stage89F correct 6×8h hourly model
└─ Stage89M formal adoption and integration                    [CURRENT W / CURRENT TERMINALLOH]
   ├─ unique current_w_mainline_stage89 bundle
   ├─ strict Stage89K SAA/DRO hash/version/capacity loader
   ├─ six stages × eight hourly periods; 120.12 kg sentinel
   ├─ Stage7 value/subgradient/cut/forward regression
   └─ no training/OOS/checkpoint/core modification
```

Stage88 remains the superseded historical reproducible predecessor.

```text
Stage89M adopted W/TerminalLOH + correct-8h bridge
+ Stage85R single-state runner mother
+ Stage85H-A clean checkpoint lifecycle
+ Stage89H paired loc4 baseline and OOS bank
└─ Stage89N run-003 controlled retraining diagnostic          [PASS / NOT FINAL]
   ├─ Stage1 120.12 -> 109.98 kg
   ├─ Stage1-3 inventory materially lower; no later-production shift
   ├─ ordinary shortage / mean terminal gap / HTT lower
   ├─ MODERATELY_REDUCED / LEVEL_REDUCTION
   └─ 10 iterations, loc4 only, fully converged = NO

Stage89H accepted common-path baseline
+ Stage89N accepted common-path candidate
+ Stage85U-C/D shared-prefix and PCR/WES definitions
└─ Stage89O run-005 read-only mechanism diagnostic            [PASS]
   ├─ reserve level strongly reduced / level reduction
   ├─ canonical wait-and-see effect size weakened
   ├─ same-intensity different-loc spatial response weakened
   ├─ mean adequacy proxy improves but late/q99 tail worsens
   └─ actual W recourse closure = NO
```
