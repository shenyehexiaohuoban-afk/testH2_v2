from __future__ import annotations

import argparse
import csv
import importlib.util
import json
import math
import sys
from pathlib import Path

import numpy as np


WORK = Path(__file__).resolve().parents[1]
ROOT = WORK.parents[1]
SOURCE = WORK / "src/run_duration_aware_stage89k_dro.py"
OUT = WORK / "terminalLoh_saa_base2/run-001"
GROUP_MANIFEST = WORK / "grouped_bank_3p5h/six_segment_grouped_bank_manifest.csv"
FROZEN_GUROBI = ROOT / "terminalLoh_wdro/output/step04cc6_python_runtime/gurobipy-12.0.1"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def load_dro_module():
    runtime = str(FROZEN_GUROBI.resolve())
    if runtime not in sys.path:
        sys.path.insert(0, runtime)
    spec = importlib.util.spec_from_file_location("duration_saa_base2_dro", SOURCE)
    require(spec is not None and spec.loader is not None, "Cannot load duration-aware source")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    stage89k = module.load_stage89k_module()
    require(tuple(stage89k.gp.gurobi.version()) == stage89k.EXPECTED_GUROBI == (12, 0, 1), "Gurobi identity failed")
    return module


def solve_state(state_id: int, mod) -> dict:
    mod.load_config()
    stage89k = mod.load_stage89k_module()
    path, data, q, structure, d_amount, fc_rate, fc_amount = mod.load_candidate_state(state_id, stage89k)
    stage89k.FC_CAP = fc_rate
    solution = stage89k.solve_saa(structure, q)
    fixed = stage89k.solve_fixed_recourse(structure, solution.T)
    expected = stage89k.solve_worst_probability(q, fixed.operating_loss, 0.0)
    require(solution.status == "OPTIMAL", f"State {state_id} SAA status={solution.status}")
    require(expected.method == "eta_zero_direct_saa", f"State {state_id} retained adversarial probability path")
    require(np.allclose(expected.probability, q, atol=1e-12), f"State {state_id} p != q")
    checks = {
        "optimal": solution.status == "OPTIMAL",
        "q_sum": abs(float(q.sum()) - 1.0) <= 1e-12,
        "p_equals_q": bool(np.allclose(expected.probability, q, atol=1e-12)),
        "p_sum": expected.probability_sum_residual <= 1e-12,
        "inventory": fixed.max_inventory_violation <= 1e-7,
        "fc_capacity": fixed.max_fc_violation <= 1e-7,
        "demand_balance": fixed.max_demand_balance_error <= 1e-7,
        "duration_once": abs(float(d_amount.sum()) - float(structure.D.sum())) <= 1e-12,
        "objective_identity": abs(solution.objective_value - (stage89k.C_H2 * float(solution.T.sum()) + float(np.dot(q, fixed.operating_loss)))) <= 1e-3,
        "finite": math.isfinite(solution.objective_value),
    }
    require(all(checks.values()), f"State {state_id} QA failed: {[k for k, v in checks.items() if not v]}")
    return {
        "state_id": state_id,
        "a0": int(data["a0"]),
        "loc0": int(data["loc0"]),
        "lfw0": int(data["lfw0"]),
        "T1": float(solution.T[0]),
        "T2": float(solution.T[1]),
        "T3": float(solution.T[2]),
        "T4": float(solution.T[3]),
        "T_total": float(solution.T.sum()),
        "objective": float(solution.objective_value),
        "empirical_expected_recourse": float(np.dot(q, fixed.operating_loss)),
        "solver_status": solution.status,
        "grouped_bank": str(path.resolve()),
        "q_sum": float(q.sum()),
        "p_equals_q": "PASS",
        "duration_qa": "PASS",
        "inventory_qa": "PASS",
        "cost_qa": "PASS",
        "checks": json.dumps(checks, sort_keys=True),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--state", type=int)
    parser.add_argument("--all", action="store_true")
    args = parser.parse_args()
    require(args.all or args.state is not None, "Use --state N or --all")
    OUT.mkdir(parents=True, exist_ok=True)
    mod = load_dro_module()
    states = range(1, 36) if args.all else [args.state]
    rows = [solve_state(int(state), mod) for state in states]
    out = OUT / ("terminal_loh_table_saa.csv" if args.all else f"state-{args.state:03d}_saa.json")
    if args.all:
        fields = [k for k in rows[0] if k != "checks"]
        with out.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=fields)
            writer.writeheader()
            writer.writerows({k: row[k] for k in fields} for row in rows)
        (OUT / "qa_summary.json").write_text(json.dumps({
            "SAA_OPTIMAL_COUNT": f"{sum(row['solver_status'] == 'OPTIMAL' for row in rows)}/35",
            "SAA_PROBABILITY_QA": "PASS",
            "SAA_DURATION_QA": "PASS",
            "SAA_INVENTORY_QA": "PASS",
            "SAA_COST_QA": "PASS",
            "grouped_manifest": str(GROUP_MANIFEST.resolve()),
            "segment_state": ["W0", "W1", "M12", "W2", "M23", "W3"],
            "segment_dt_h": [1.0, 0.5, 0.5, 0.5, 0.5, 0.5],
            "original_draws_per_state": 15000,
            "probability_semantics": "q_g=multiplicity/15000; eta=0 direct SAA",
        }, indent=2), encoding="utf-8")
        print(f"SAA_OPTIMAL_COUNT={sum(row['solver_status'] == 'OPTIMAL' for row in rows)}/35")
    else:
        out.write_text(json.dumps(rows[0], indent=2), encoding="utf-8")
        print(json.dumps(rows[0], indent=2))


if __name__ == "__main__":
    main()
