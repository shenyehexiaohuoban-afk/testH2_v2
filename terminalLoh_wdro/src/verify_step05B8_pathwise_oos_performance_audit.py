"""Independent verification of the accepted Step-05B-8 pathwise audit."""

from __future__ import annotations

import hashlib
import math
import subprocess
from pathlib import Path

import numpy as np
import pandas as pd


TOL = 1.0e-8
EXPECTED_OOS_SHA256 = "6e4ed488423e3cbb838c4a6f8b45019cf4ecf32a82850880399a08aafc7aff85"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def main() -> None:
    repo = Path(__file__).resolve().parents[2]
    out = repo / "results/task-002-stage2b-b3-smoke/65-oos-pathwise-saa-dro-performance-audit/run-002"
    source_path = repo / "results/task-002-stage2b-b3-smoke/58-main-msp-terminal-gap-mechanism-audit/run-004/terminal_target_vs_final_inventory.csv"
    required = [
        "README.md",
        "pathwise_saa_dro_comparison.csv",
        "pathwise_performance_summary.csv",
        "paired_difference_ci.csv",
        "operating_cost_decomposition.csv",
        "inventory_change_distribution.csv",
        "high_inventory_gain_paths.csv",
        "terminal_hit_deltaT_deltaI.csv",
        "state_mechanism_summary.csv",
        "step05b8_judgment.txt",
        "LARGE_FILE_MANIFEST.md",
        "common_oos_pairing_audit.txt",
    ]
    missing = [name for name in required if not (out / name).is_file()]
    require(not missing, f"Missing required output files: {missing}")

    master = pd.read_csv(out / "pathwise_saa_dro_comparison.csv")
    source = pd.read_csv(source_path)
    summary = pd.read_csv(out / "pathwise_performance_summary.csv")
    ci = pd.read_csv(out / "paired_difference_ci.csv")
    component = pd.read_csv(out / "operating_cost_decomposition.csv")
    inventory = pd.read_csv(out / "inventory_change_distribution.csv")
    high = pd.read_csv(out / "high_inventory_gain_paths.csv")
    terminal = pd.read_csv(out / "terminal_hit_deltaT_deltaI.csv")
    state = pd.read_csv(out / "state_mechanism_summary.csv")

    require(len(master) == 10000 and master.path_id.to_list() == list(range(1, 10001)),
            "Master table is not exactly path IDs 1..10000.")
    require(int(master.terminal_hit.sum()) == 6053 and len(terminal) == 6053,
            "Terminal-hit count is not 6053.")
    require(len(high) == 1000, "High-inventory-gain table is not the top 1000 paths.")
    require(len(state) == 32, "State summary must contain 31 reached states plus no-terminal-hit.")

    hit = master.terminal_hit == 1
    mapped = (master.loc[hit, "a"] - 2) * 7 + master.loc[hit, "loc"]
    mapping_error = float(np.max(np.abs(mapped - master.loc[hit, "terminal_state"])))
    require(mapping_error == 0.0, "35-state mapping identity failed.")
    require(master.loc[hit, "terminal_state"].between(1, 35).all(),
            "Mapped state ID outside 1..35.")
    require(master.loc[~hit, "terminal_state"].isna().all(),
            "Non-terminal paths have a mapped terminal state.")

    saa = source[source.method == "saa"].sort_values("path_id")
    dro = source[source.method == "chi2_eta003"].sort_values("path_id")
    require(saa.path_id.to_list() == master.path_id.to_list() == dro.path_id.to_list(),
            "Source/master path IDs are not identical.")
    reproduction_checks = {
        "saa_production": saa.production_amount,
        "dro_production": dro.production_amount,
        "saa_htt": saa.htt_amount,
        "dro_htt": dro.htt_amount,
        "saa_ordinary_shortage": saa.ordinary_shortage,
        "dro_ordinary_shortage": dro.ordinary_shortage,
        "saa_final_inventory": saa.final_total,
        "dro_final_inventory": dro.final_total,
        "saa_operating_cost": saa.objective_without_terminal_gap,
        "dro_operating_cost": dro.objective_without_terminal_gap,
        "saa_reported_objective": saa.reported_objective,
        "dro_reported_objective": dro.reported_objective,
    }
    max_source_error = 0.0
    for column, values in reproduction_checks.items():
        error = float(np.max(np.abs(master[column].to_numpy() - values.to_numpy())))
        max_source_error = max(max_source_error, error)
        require(error < 1e-9, f"Source reproduction failed for {column}: {error}")

    inventory_delta = master.dro_final_inventory - master.saa_final_inventory
    require(float(np.max(np.abs(inventory_delta - master.delta_final_inventory))) < 1e-9,
            "Inventory delta identity failed.")
    require(int((inventory_delta > TOL).sum()) == 5600, "Inventory-increase count changed.")
    require(int((inventory_delta.abs() <= TOL).sum()) == 4397, "Inventory-equal count changed.")
    require(int((inventory_delta < -TOL).sum()) == 3, "Inventory-decrease count changed.")
    require(int((master.delta_ordinary_shortage > TOL).sum()) == 280,
            "Ordinary-shortage-worse count changed.")
    require(int((master.delta_ordinary_shortage.abs() <= TOL).sum()) == 9718,
            "Ordinary-shortage-equal count changed.")
    require(int((master.delta_ordinary_shortage < -TOL).sum()) == 2,
            "Ordinary-shortage-improved count changed.")

    metric_map = {
        "production_kg": "delta_production",
        "htt_kg": "delta_htt",
        "ordinary_shortage_kg": "delta_ordinary_shortage",
        "final_inventory_kg": "delta_final_inventory",
        "operating_cost_yuan": "delta_operating_cost",
        "reported_objective_yuan": "delta_reported_objective",
        "terminal_gap_kg": "delta_terminal_gap",
    }
    max_summary_error = 0.0
    for metric, column in metric_map.items():
        row = summary[summary.metric == metric].iloc[0]
        values = master[column].dropna()
        for archived, recomputed in [
            (row.mean_delta, values.mean()),
            (row.median_delta, values.median()),
            (row.q5_delta, values.quantile(0.05)),
            (row.q95_delta, values.quantile(0.95)),
        ]:
            error = abs(float(archived) - float(recomputed))
            max_summary_error = max(max_summary_error, error)
            require(error < 1e-9, f"Summary recomputation failed for {metric}.")

    max_ci_error = 0.0
    for _, row in ci.iterrows():
        values = master[metric_map[row.metric]].dropna()
        mean = float(values.mean())
        se = float(values.std(ddof=1) / math.sqrt(len(values)))
        low = mean - float(row.critical_value) * se
        high_ci = mean + float(row.critical_value) * se
        error = max(abs(mean - row.mean_delta), abs(low - row.ci95_low), abs(high_ci - row.ci95_high))
        max_ci_error = max(max_ci_error, error)
        require(error < 1e-9, f"Paired CI recomputation failed for {row.metric}.")

    components = component[component.component != "operating_cost_total_excluding_terminal_gap_penalty"]
    operating_delta = float(master.delta_operating_cost.mean())
    component_error = abs(float(components.dro_minus_saa.sum()) - operating_delta)
    require(component_error < 1e-8, "Operating-cost decomposition does not close.")

    top1000 = master.nlargest(1000, "delta_final_inventory")
    require(set(high.path_id) == set(top1000.path_id), "High-inventory table is not the true top 10%.")
    top10_gain_share = float(top1000.delta_final_inventory.clip(lower=0).sum() / master.delta_final_inventory.clip(lower=0).sum())
    archived_top10 = inventory[inventory.group == "top_10_percent_inventory_gain"].iloc[0]
    require(abs(top10_gain_share - archived_top10.share_of_total_positive_inventory_gain) < 1e-12,
            "Top-10-percent gain share changed.")

    oos_hash = sha256_file(repo / "output_h2/details/h2_OOS.csv")
    require(oos_hash == EXPECTED_OOS_SHA256, "Frozen OOS SHA-256 changed.")
    protected = [
        "main_msp_h2_near.m", "h2_default_options.m", "run_h2_with_options.m",
        "load_data_h2_near.m", "data/yuanqi/near_stage_msp_input.mat",
        "fa_h2/build_stage_model_h2.m", "fa_h2/update_rhs_h2.m",
        "fa_h2/solve_stage_model_h2.m", "fa_h2/forward_pass_h2.m",
        "fa_h2/backward_pass_h2.m", "fa_h2/add_cut_h2.m",
        "fa_h2/train_models_h2.m", "fa_h2/eval_h2.m",
        "codex_rule/core.md", "codex_rule/longtask.md",
    ]
    protected_diff = subprocess.run(
        ["git", "diff", "--name-only", "--", *protected],
        cwd=repo, check=True, capture_output=True, text=True,
    ).stdout.strip()
    require(not protected_diff, f"Protected tracked files changed: {protected_diff}")

    audit = [
        "Step-05B-8 independent mechanical audit",
        "",
        "paired_paths: 10000",
        "common_terminal_hits: 6053",
        "reached_terminal_states: 31",
        f"max_source_reproduction_error: {max_source_error:.12g}",
        f"max_state_mapping_error: {mapping_error:.12g}",
        f"max_summary_recompute_error: {max_summary_error:.12g}",
        f"max_paired_ci_recompute_error: {max_ci_error:.12g}",
        f"operating_component_closure_error_yuan: {component_error:.12g}",
        "inventory_increase_equal_decrease: 5600/4397/3",
        "ordinary_shortage_improve_equal_worse: 2/9718/280",
        f"top10_positive_inventory_gain_share: {top10_gain_share:.12g}",
        f"frozen_oos_sha256: {oos_hash}",
        "required_outputs_present: PASS",
        "independent_mechanical_audit_PASS: 1",
    ]
    (out / "independent_mechanical_audit.txt").write_text("\n".join(audit) + "\n", encoding="utf-8")

    source_audit = [
        "Step-05B-8 source integrity audit",
        "",
        "Protected MSP/model/data/rule tracked files differ from frozen HEAD: no",
        f"Frozen Step-05B-1 source SHA-256: {sha256_file(source_path)}",
        f"Frozen OOS SHA-256: {oos_hash}",
        "MATLAB/Gurobi invoked: no",
        "Training/resampling/cut generation/W-stage evaluation: no",
        "TerminalLOH and 200/2000 modified: no",
        "Source integrity PASS: 1",
    ]
    (out / "source_integrity_audit.txt").write_text("\n".join(source_audit) + "\n", encoding="utf-8")
    print("Step-05B-8 independent verification PASS")


if __name__ == "__main__":
    main()
