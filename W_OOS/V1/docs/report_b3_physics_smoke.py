# -*- coding: utf-8 -*-
from pathlib import Path
import json
import pandas as pd

V1=Path(__file__).resolve().parents[1]
ROOT=V1.parents[1]
OUT=V1/'results/b3-physics-smoke/run-001'

def main():
    qa=json.loads((OUT/'physics_QA.json').read_text())
    cases=pd.read_csv(OUT/'smoke_cases.csv')
    report=f'''# W_OOS/V1-B3 continuous-time vehicle physics engine smoke

本次是 `RESTRICTED_SCOPE` 工程 smoke，只验证确定性车辆状态推进、路网事件、共享氢守恒和 B2 路网回归；没有优化器、训练、MSP_OOS/W_OOS/ALL_OOS，也没有修改 BASE2 或 frozen W。输出中的人工道路夹具仅用于用户指定的单元案例，不是研究样本。

## 机械状态

**VERIFIED_EXISTING：** 当前目录为 `testH2_v2`；branch `{qa['HEAD']}` 对应的当前 HEAD，MATLAB PID 9668 保持不动；未启动 Gurobi。B2 保留的道路源码和 frozen W 输入均通过哈希检查。

**PROVISIONAL_PARAMETER：** 六车；每车 `Pmax=220 kW`、`Hcap=66.6 kg`；`eta_FC=0.55`、`LHV=33.33 kWh/kg`；`v0=40 km/h`。这些值只作为 B3 smoke nominal，不是最终论文参数。

## Physics contract

**B2_VERIFIED：** OPEN 边使用既有 `w=L*(1+s)`；`tau=w/v0`；CLOSED 边不可新进入。B3 没有第二套 slowdown factor，也没有把灾后速度再次乘到 C 上。

**PROJECT_ASSUMPTION_FOR_B3：** 车辆在 OPEN 时进入一条边后，即使下一状态关闭该边，仍完成当前边；到达节点后按新状态重规划，新关闭边禁止进入。该规则不是历史事实。

**VERIFIED_EXISTING + PROJECT_SIMPLIFICATION：** 车辆状态互斥为 PARKED/SERVICE、MOVING、REFUEL_EVENT；MOVING 时 `P_MFCV=0`。车辆牵引氢耗 OFF，是本 B3 的项目简化。

**NONBINDING_REFUELING_V1_ASSUMPTION：** REFUEL_EVENT 仅在四个 H2 anchor 零时长原子转移；无速率、枪数或排队约束。超罐或站存不足时本实现拒绝，不截断、不产生负库存。

## Cases and evidence

共执行 `{qa['cases']}` 个案例（含10个必需案例、附加耗尽/非站点/边界/horizon/并发案例），共 `{qa['checks']}` 项检查。

| QA | result |
|---|---|
| CONTINUOUS_TIME_PROGRESS_QA | {qa['CONTINUOUS_TIME_PROGRESS_QA']} |
| ROAD_STATE_BOUNDARY_QA | {qa['ROAD_STATE_BOUNDARY_QA']} |
| CURRENT_EDGE_CLOSURE_RULE_QA | {qa['CURRENT_EDGE_CLOSURE_RULE_QA']} |
| REROUTE_QA | {qa['REROUTE_QA']} |
| MOVING_NO_GENERATION_QA | {qa['MOVING_NO_GENERATION_QA']} |
| H2_MASS_CONSERVATION_QA | {qa['H2_MASS_CONSERVATION_QA']} |
| OPTION_A_INITIAL_SPLIT_QA | {qa['OPTION_A_INITIAL_SPLIT_QA']} |
| NONBINDING_REFUEL_QA | {qa['NONBINDING_REFUEL_QA']} |
| TANK_CAPACITY_QA | {qa['TANK_CAPACITY_QA']} |
| SERVICE_ENERGY_IDENTITY_QA | {qa['SERVICE_ENERGY_IDENTITY_QA']} |
| B2_C_REGRESSION_QA | {qa['B2_C_REGRESSION_QA']} |

**VERIFIED：** CASE-1 精确13分钟到达；CASE-2 的12+1分钟跨 accounting boundary 后在第31分钟到达；CASE-3/4/5分别验证跨状态保留当前边进度、关闭后完成已入边、下一边关闭后禁止进入并重规划/UNREACHABLE；CASE-6 验证每站 `station + onboard = I^MSP`；CASE-7 零时长10kg转移；CASE-8 拒绝超罐和站存不足；CASE-9 验证 `220×18/60=66 kWh` 与 `66/(0.55×33.33)` kg；CASE-10 验证同站两车不能重复占用同一库存。

**VERIFIED：** 最大全局氢质量误差 `{qa['max_mass_error_kg']:.3e} kg`；每条事件ledger均切分到动作结束、边到达、road-state/accounting boundary或燃料耗尽；B2 回归示例最大 C 差异 `{qa['max_C_diff_km']:.3e} km`。

## Limits

**NOT_ESTABLISHED：** 该 engine 尚未验证需求服务、配电网 EENS、车辆优化、真实 refueling duration、枪数/队列、牵引氢耗、途中封路等待/回撤/重规划策略、并发资源限制或正式 OOS 性能。`COMMUNICATION_QA` 在 closeout 后置为 PASS；本 smoke 不代表 W_OOS solver 已实现。

事件级结果见 `event_ledger.csv`、`action_events.csv`、`mass_balance_ledger.csv`；输入夹具和真实 frozen 路径身份见 `case_inputs.json` 与 `frozen_input_identity.json`。`physics_QA.json`、`B2_C_regression_gate.json` 和 source/output manifest 用于复核。
'''
    (OUT/'report_b3_physics_smoke.md').write_text(report,encoding='utf-8')
    summary=dict(qa,report='report_b3_physics_smoke.md',status_labels=['VERIFIED_EXISTING','B2_VERIFIED','PROJECT_ASSUMPTION_FOR_B3','PROVISIONAL_PARAMETER','NOT_ESTABLISHED'],case_names=cases.case.tolist(),engine_files=['W_OOS/V1/src/engine.py','W_OOS/V1/src/road.py'],config='W_OOS/V1/config/b3_nominal.json',solver_written=False,formal_oos_run=False)
    (OUT/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
    print('report generated')

if __name__=='__main__':main()
