"""Static contract audit between the candidate Mode C serializer and analyzer."""
from __future__ import annotations

import ast
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MATLAB = ROOT / "testing" / "run_temporal3p5_oos_mode_c.m"
ANALYZER = ROOT / "analysis" / "python" / "run_temporal3p5_mode_c_analysis.py"
OUTPUT = ROOT / "diagnostics" / "MODE_C_SCHEMA_CONTRACT_QA.json"


def matlab_names(text: str, function_name: str) -> set[str]:
    match = re.search(
        rf"function n={re.escape(function_name)}\(\),n=\{{(?P<body>.*?)\}};end",
        text,
        flags=re.DOTALL,
    )
    if not match:
        raise RuntimeError(f"Cannot find MATLAB schema function {function_name}")
    return set(re.findall(r"'([^']+)'", match.group("body")))


class CsvContractVisitor(ast.NodeVisitor):
    def __init__(self) -> None:
        self.by_key: dict[str, set[str]] = {key: set() for key in ("path", "stage", "site", "hour_site", "hour_system", "htt", "metadata")}

    def visit_Call(self, node: ast.Call) -> None:
        if isinstance(node.func, ast.Attribute) and node.func.attr == "read_csv" and node.args:
            key = self.file_key(node.args[0])
            if key:
                for keyword in node.keywords:
                    if keyword.arg == "usecols":
                        self.by_key[key].update(self.literal_strings(keyword.value))
        self.generic_visit(node)

    @staticmethod
    def literal_strings(node: ast.AST) -> set[str]:
        if isinstance(node, (ast.List, ast.Tuple, ast.Set)):
            return {value.value for value in node.elts if isinstance(value, ast.Constant) and isinstance(value.value, str)}
        return set()

    @staticmethod
    def file_key(node: ast.AST) -> str | None:
        # Recognize files["key"], base_files["key"], candidate_files["key"].
        if isinstance(node, ast.Subscript) and isinstance(node.slice, ast.Constant) and isinstance(node.slice.value, str):
            return node.slice.value if node.slice.value in {"path", "stage", "site", "hour_site", "hour_system", "htt", "metadata"} else None
        return None


def main() -> None:
    matlab = MATLAB.read_text(encoding="utf-8", errors="replace")
    schemas = {
        "path": matlab_names(matlab, "path_names"),
        "stage": matlab_names(matlab, "stage_names"),
        "site": matlab_names(matlab, "stage_site_names"),
        "hour_site": matlab_names(matlab, "hour_site_names"),
        "hour_system": matlab_names(matlab, "hour_system_names"),
        "htt": matlab_names(matlab, "flow_names"),
        "metadata": {
            "policy", "requested_paths", "completed_paths", "operating_solves", "wall_time_s", "cuts_before", "cuts_after",
            "cuts_unchanged", "checkpoint_path", "checkpoint_sha256_before", "checkpoint_sha256_after", "checkpoint_unchanged",
            "bank_path", "bank_sha256", "max_eq_residual", "max_ineq_violation", "pass",
        },
    }
    visitor = CsvContractVisitor()
    visitor.visit(ast.parse(ANALYZER.read_text(encoding="utf-8")))

    # Direct path/metadata loads do not use usecols; list their required columns explicitly.
    visitor.by_key["path"].update({
        "path_id", "state_sequence", "termination_type", "operating_stage_count", "terminal_state_id", "target_total",
        "reported_objective", "actual_operating_cost", "holding_cost", "production_cost", "electricity_cost", "production_om_cost",
        "ordinary_shortage_total", "ordinary_shortage_cost", "total_H2_production", "total_HTT", "HTT_cost", "terminal_inventory_total",
        "terminal_site_gap", "terminal_total_quantity_shortfall", "terminal_spatial_component", "terminal_penalty_cost",
        *[f"target_site{i}" for i in range(1, 5)], *[f"inventory_site{i}" for i in range(1, 5)],
    })
    visitor.by_key["metadata"].update({
        "completed_paths", "bank_sha256", "pass", "checkpoint_sha256_before", "checkpoint_sha256_after", "cuts_before", "cuts_after",
        "max_eq_residual", "max_ineq_violation",
    })
    visitor.by_key["htt"].update({"path_id", "origin_site", "destination_site", "global_hour", "flow_kg"})
    # The analyzer also passes named list variables to read_csv(usecols=...). Keep
    # those indirect dependencies explicit so the audit cannot silently undercount.
    visitor.by_key["site"].update({"path_id", "stage", "site", "beginning_inventory_kg"})
    visitor.by_key["hour_site"].update({
        "path_id", "stage", "global_hour", "site", "H2_production_kg", "P_EL_kW", "end_inventory_kg",
        "HTT_in_kg", "HTT_out_kg", "ordinary_shortage_kg", "electrolyzer_capacity_binding", "storage_capacity_binding",
    })
    visitor.by_key["hour_system"].update({
        "path_id", "stage", "global_hour", "total_P_EL_kW", "root_grid_import", "min_voltage_pu",
        "max_line_loading_pct", "total_HTT_kg", "fleet_utilization", "fleet_capacity_binding",
    })

    rows = []
    passed = True
    for key in schemas:
        required = sorted(visitor.by_key[key])
        available = sorted(schemas[key])
        missing = sorted(set(required) - schemas[key])
        passed = passed and not missing
        rows.append({"table": key, "required": required, "available": available, "missing": missing, "pass": not missing})
    payload = {
        "qa": "PASS" if passed else "FAIL",
        "serializer": str(MATLAB),
        "analyzer": str(ANALYZER),
        "tables": rows,
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"MODE_C_SCHEMA_CONTRACT_QA={payload['qa']}")
    if not passed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
