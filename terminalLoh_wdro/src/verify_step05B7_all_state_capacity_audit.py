"""Independent mechanical verification for the accepted Step-05B-7 audit."""

from __future__ import annotations

import hashlib
import subprocess
from pathlib import Path

import numpy as np
import pandas as pd


TOL = 1.0e-7
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
    step_root = repo / "results/task-002-stage2b-b3-smoke/64-terminal-loh-all-state-capacity-gap-audit"
    run1 = step_root / "run-001"
    run2 = step_root / "run-002"
    raw_path = run2 / "all_state_path_capacity_raw.csv"
    paired_path = run2 / "all_path_saa_dro_feasibility_transition.csv"
    state_path = run2 / "all_state_capacity_gap_summary.csv"

    required_outputs = [
        "README.md",
        "state16_19_target_actual_feasible_inventory.csv",
        "all_state_capacity_gap_summary.csv",
        "all_path_saa_dro_feasibility_transition.csv",
        "reverse_gap_cases.csv",
        "state_capacity_driver_comparison.csv",
        "state_target_rank_and_headroom.csv",
        "resource_utilization_by_state.csv",
        "state16_19_driver_audit.txt",
        "step05b7_judgment.txt",
        "LARGE_FILE_MANIFEST.md",
    ]
    missing = [name for name in required_outputs if not (run2 / name).is_file()]
    require(not missing, f"Missing required outputs: {missing}")

    raw = pd.read_csv(raw_path)
    paired = pd.read_csv(paired_path)
    states = pd.read_csv(state_path)
    require(len(raw) == 12106, "Raw LP row count is not 12106.")
    require(raw.path_id.nunique() == 6053, "Paired terminal-hit path count is not 6053.")
    require(raw.state_id.nunique() == 31, "Reached terminal-state count is not 31.")
    require(raw.groupby("method").size().to_dict() == {"chi2_eta003": 6053, "saa": 6053},
            "Method row counts are not 6053/6053.")
    require((raw.lp_status == "OPTIMAL").all(), "At least one diagnostic LP is not OPTIMAL.")

    closed_form = np.minimum(
        860.0,
        raw.initial_inventory_total_kg
        + raw.cumulative_available_production_capacity_kg
        - raw.cumulative_normal_h2_service_kg,
    )
    max_inventory_error = float(
        np.max(np.abs(closed_form - raw.max_feasible_terminal_inventory_total_kg))
    )
    capacity_gap_error = float(
        np.max(
            np.abs(
                np.maximum(
                    0.0,
                    raw.terminal_loh_total_target_kg
                    - raw.max_feasible_terminal_inventory_total_kg,
                )
                - raw.system_capacity_gap_kg
            )
        )
    )
    headroom_error = float(
        np.max(
            np.abs(
                raw.max_feasible_terminal_inventory_total_kg
                - raw.terminal_loh_total_target_kg
                - raw.capacity_headroom_kg
            )
        )
    )
    require(max_inventory_error < 1.0e-9, "Maximum-inventory identity failed.")
    require(capacity_gap_error < 1.0e-9, "Capacity-gap identity failed.")
    require(headroom_error < 1.0e-9, "Capacity-headroom identity failed.")

    c6_root = repo / "results/task-002-stage2b-b3-smoke/53-35state-saa-vs-eta003-terminal-loh/run-024"
    target_errors: dict[str, float] = {}
    for method, filename in [
        ("saa", "terminal_loh_table_saa.csv"),
        ("chi2_eta003", "terminal_loh_table_eta_003.csv"),
    ]:
        table = pd.read_csv(c6_root / filename).set_index("state_id")["TerminalLOH_total_kg"]
        subset = raw[raw.method == method]
        target_error = float(
            np.max(
                np.abs(
                    subset.terminal_loh_total_target_kg.to_numpy()
                    - subset.state_id.map(table).to_numpy()
                )
            )
        )
        require(target_error < 1.0e-9, f"{method} target-table mapping failed.")
        target_errors[method] = target_error

    require(len(paired) == 6053 and paired.path_id.nunique() == 6053,
            "Final paired transition table is not one row per terminal-hit path.")
    class_counts = paired.feasibility_class.value_counts().to_dict()
    expected_classes = {
        "A_both_feasible": 5451,
        "B_SAA_feasible_DRO_infeasible": 175,
        "C_both_infeasible": 426,
        "D_SAA_infeasible_DRO_feasible": 1,
    }
    require(class_counts == expected_classes, "Feasibility transition counts changed.")
    reverse = paired[
        paired.system_capacity_gap_kg_saa
        > paired.system_capacity_gap_kg_dro + TOL
    ]
    require(len(reverse) == 3, "Reverse-gap path count is not 3.")
    reverse_keys = set(zip(reverse.path_id.astype(int), reverse.state_id.astype(int)))
    require(reverse_keys == {(719, 16), (1318, 25), (2154, 15)},
            "Reverse-gap path identities changed.")
    require(int((paired.feasibility_class == "D_SAA_infeasible_DRO_feasible").sum()) == 1,
            "D-class path count is not 1.")
    require(len(states) == 31 and states.state.nunique() == 31,
            "State summary is not one row per reached state.")

    reused_hashes: dict[str, str] = {}
    for filename in [
        "all_state_path_capacity_raw.csv",
        "resource_utilization_state_raw.csv",
        "matlab_readonly_integrity_audit.txt",
    ]:
        source_hash = sha256_file(run1 / filename)
        accepted_hash = sha256_file(run2 / filename)
        require(source_hash == accepted_hash, f"run-001/run-002 hash mismatch for {filename}.")
        reused_hashes[filename] = accepted_hash

    oos_hash = sha256_file(repo / "output_h2/details/h2_OOS.csv")
    require(oos_hash == EXPECTED_OOS_SHA256, "Frozen OOS SHA-256 changed.")

    protected = [
        "main_msp_h2_near.m",
        "h2_default_options.m",
        "run_h2_with_options.m",
        "load_data_h2_near.m",
        "data/yuanqi/near_stage_msp_input.mat",
        "fa_h2/build_stage_model_h2.m",
        "fa_h2/update_rhs_h2.m",
        "fa_h2/solve_stage_model_h2.m",
        "fa_h2/forward_pass_h2.m",
        "fa_h2/backward_pass_h2.m",
        "fa_h2/add_cut_h2.m",
        "fa_h2/train_models_h2.m",
        "fa_h2/eval_h2.m",
        "codex_rule/core.md",
        "codex_rule/longtask.md",
    ]
    diff = subprocess.run(
        ["git", "diff", "--name-only", "--", *protected],
        cwd=repo,
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    require(not diff, f"Protected tracked files have changes: {diff}")

    audit_lines = [
        "Step-05B-7 independent mechanical audit",
        "",
        f"raw_lp_rows: {len(raw)}",
        f"paired_terminal_hit_paths: {raw.path_id.nunique()}",
        f"reached_terminal_states: {raw.state_id.nunique()}",
        f"optimal_lp_rows: {int((raw.lp_status == 'OPTIMAL').sum())}",
        f"max_closed_form_inventory_error_kg: {max_inventory_error:.12g}",
        f"max_capacity_gap_identity_error_kg: {capacity_gap_error:.12g}",
        f"max_headroom_identity_error_kg: {headroom_error:.12g}",
        f"saa_target_table_max_error_kg: {target_errors['saa']:.12g}",
        f"dro_target_table_max_error_kg: {target_errors['chi2_eta003']:.12g}",
        f"feasibility_A_B_C_D: {expected_classes['A_both_feasible']}/"
        f"{expected_classes['B_SAA_feasible_DRO_infeasible']}/"
        f"{expected_classes['C_both_infeasible']}/"
        f"{expected_classes['D_SAA_infeasible_DRO_feasible']}",
        "reverse_gap_paths: 719/state16, 1318/state25, 2154/state15",
        f"frozen_oos_sha256: {oos_hash}",
        "run001_run002_raw_hash_match: PASS",
        "protected_source_diff: none",
        "required_outputs_present: PASS",
        "independent_mechanical_audit_PASS: 1",
    ]
    (run2 / "independent_mechanical_audit.txt").write_text(
        "\n".join(audit_lines) + "\n", encoding="utf-8"
    )

    source_lines = [
        "Step-05B-7 source integrity audit",
        "",
        "Protected tracked MSP/model/data/rule files differ from frozen HEAD: no",
        f"Frozen OOS SHA-256: {oos_hash}",
        "Raw files reused byte-for-byte from mechanically passing run-001:",
    ]
    source_lines.extend(f"- {name}: {digest}" for name, digest in reused_hashes.items())
    source_lines.extend(
        [
            "No MATLAB training process was invoked by this verification.",
            "Source integrity PASS: 1",
        ]
    )
    (run2 / "source_integrity_audit.txt").write_text(
        "\n".join(source_lines) + "\n", encoding="utf-8"
    )
    print("Step-05B-7 independent verification PASS")


if __name__ == "__main__":
    main()
