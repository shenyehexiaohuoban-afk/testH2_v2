#!/usr/bin/env python3
"""Build the lightweight Stage-89M adoption bundle from accepted artifacts.

This script never solves W or TerminalLOH.  It verifies accepted Stage89J/K/L
artifacts, re-hashes the 35 large Stage89J banks in place, and then creates the
single lightweight navigation bundle plus pre-integration audit files.
"""

from __future__ import annotations

import csv
import hashlib
import json
import shutil
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RESULT = ROOT / "results/task-002-stage2b-b3-smoke/stage89m-formal-adoption-and-8h-integration/run-001"
BUNDLE = ROOT / "terminalLoh_wdro/current_w_mainline_stage89"
J = ROOT / "results/task-002-stage2b-b3-smoke/stage89j-topology-h2-dual-channel-w-candidate/run-001"
K = ROOT / "results/task-002-stage2b-b3-smoke/stage89k-terminalLoh-dual-channel-candidate/run-002"
L = ROOT / "results/task-002-stage2b-b3-smoke/stage89l-h2-island-incremental-ablation/run-001"


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        while block := handle.read(1024 * 1024):
            h.update(block)
    return h.hexdigest()


def rows(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def write_csv(path: Path, fieldnames: list[str], data: list[dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, lineterminator="\n")
        writer.writeheader()
        writer.writerows(data)


def copy(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def validate_prerequisites() -> tuple[list[dict[str, object]], str]:
    require("FORMAL_W_CANDIDATE" in (J / "README.md").read_text(encoding="utf-8"), "Stage89J status mismatch")
    require("FORMAL_TERMINALLOH_CANDIDATE" in (K / "README.md").read_text(encoding="utf-8"), "Stage89K status mismatch")
    require("FORMAL_MECHANISM_ABLATION" in (L / "README.md").read_text(encoding="utf-8"), "Stage89L status mismatch")

    j_manifest = rows(J / "candidate_bank_manifest.csv")
    require(len(j_manifest) == 35, "Stage89J bank manifest must contain 35 states")
    require(sum(int(r["n_draws"]) for r in j_manifest) == 525000, "Stage89J frozen draw count mismatch")
    require(sum(int(r["n_exact_groups"]) for r in j_manifest) == 457431, "Stage89J exact support mismatch")
    require(all(r["signature"] == "(Dres,Aroad,Aelec,C)" and r["gate"] == "PASS" for r in j_manifest), "Stage89J signature/gate mismatch")

    bank_identity_lines: list[str] = []
    total_bank_bytes = 0
    for item in j_manifest:
        path = ROOT / item["candidate_bank_path"]
        require(path.is_file(), f"Missing Stage89J bank: {path}")
        actual_size = path.stat().st_size
        actual_sha = sha256(path)
        require(actual_size == int(item["candidate_bank_bytes"]), f"Stage89J bank byte mismatch: {path}")
        require(actual_sha == item["candidate_bank_sha256"], f"Stage89J bank SHA mismatch: {path}")
        total_bank_bytes += actual_size
        bank_identity_lines.append(f"{item['state_id']},{item['candidate_bank_path']},{actual_size},{actual_sha}\n")
    bank_set_sha = hashlib.sha256("".join(bank_identity_lines).encode("utf-8")).hexdigest()
    require(total_bank_bytes == 1104251473, "Stage89J aggregate bank byte count mismatch")

    for filename, gate_col in (("dres_qa.csv", "gate"), ("aelec_qa.csv", "gate"), ("qg_probability_qa.csv", "gate")):
        audit = rows(J / filename)
        require(len(audit) == 35 and all(r[gate_col] == "PASS" for r in audit), f"Stage89J {filename} failed")
    replay = (J / "frozen_randomness_replay_qa.md").read_text(encoding="utf-8")
    for token in ("Status: **PASS**", "W_TRAJECTORY_RESAMPLED = NO", "W_TRANSITION_MATRIX_MODIFIED = NO"):
        require(token in replay, f"Stage89J replay token missing: {token}")

    k_status = rows(K / "solver_status_by_state.csv")
    require(len(k_status) == 70, "Stage89K solver row count mismatch")
    require({r["mode"] for r in k_status} == {"SAA", "DRO"}, "Stage89K modes mismatch")
    require(all(r["solver_status"] == "OPTIMAL" and r["case_pass"] == "1" for r in k_status), "Stage89K solver gate failed")
    require(sum(r["mode"] == "SAA" for r in k_status) == 35 and sum(r["mode"] == "DRO" for r in k_status) == 35, "Stage89K per-mode count mismatch")
    for filename, gate_col in (("inventory_qa.csv", "inventory_qa"), ("fc_capacity_qa.csv", "fc_capacity_qa"), ("probability_dro_qa.csv", "probability_qa")):
        audit = rows(K / filename)
        require(len(audit) == 70 and all(r[gate_col] == "PASS" for r in audit), f"Stage89K {filename} failed")
    k_bank = rows(K / "candidate_bank_input_qa.csv")
    require(len(k_bank) == 35 and all(r["input_gate"] == "PASS" and r["sha_pass"] == "1" for r in k_bank), "Stage89K bank input identity failed")
    require("FULL CANDIDATE EFFECT" in (K / "README.md").read_text(encoding="utf-8"), "Stage89K attribution boundary missing")
    require("FA-MSP and OOS were not run" in (K / "README.md").read_text(encoding="utf-8"), "Stage89K scope gate missing")

    l_status = rows(L / "solver_status_by_state.csv")
    require(len(l_status) == 70 and all(r["solver_status"] == "OPTIMAL" and r["case_pass"] == "1" for r in l_status), "Stage89L road-only solver gate failed")
    for filename, gate_col in (("inventory_qa.csv", "inventory_qa"), ("probability_dro_qa.csv", "probability_qa")):
        audit = rows(L / filename)
        require(len(audit) == 70 and all(r[gate_col] == "PASS" for r in audit), f"Stage89L {filename} failed")
    interpretation = (L / "mechanism_interpretation.md").read_text(encoding="utf-8")
    for token in ("H2_ISLAND_INCREMENTAL_EFFECT = MIXED", "H2_ISLAND_MECHANISM_VALUE = MODERATE", "RECOMMEND_ADOPT_STAGE89J_89K = YES", "0.875626"):
        require(token in interpretation or token == "0.875626" and "0.875626" in (L / "README.md").read_text(encoding="utf-8"), f"Stage89L adoption token missing: {token}")

    audit_rows = [
        {"prerequisite": "Stage89J", "accepted_run": rel(J), "expected_status": "FORMAL_W_CANDIDATE", "mechanical_result": "PASS", "evidence": "README; 35 bank hashes; Dres/Aelec/q_g/replay QA"},
        {"prerequisite": "Stage89K", "accepted_run": rel(K), "expected_status": "FORMAL_TERMINALLOH_CANDIDATE", "mechanical_result": "PASS", "evidence": "70 OPTIMAL; inventory/FC/probability/bank SHA QA"},
        {"prerequisite": "Stage89L", "accepted_run": rel(L), "expected_status": "FORMAL_MECHANISM_ABLATION", "mechanical_result": "PASS", "evidence": "70 road-only OPTIMAL; Case C reuse; MIXED/MODERATE; adoption YES"},
        {"prerequisite": "Stage89J large bank", "accepted_run": "terminalLoh_wdro/output/stage89j_topology_h2_dual_channel_w_candidate/run-001", "expected_status": "35 files; 1104251473 bytes", "mechanical_result": "PASS", "evidence": bank_set_sha},
    ]
    return audit_rows, bank_set_sha


def terminal_table(mode: str) -> list[dict[str, object]]:
    accepted = [r for r in rows(K / "solver_status_by_state.csv") if r["mode"] == mode]
    accepted.sort(key=lambda r: int(r["state"]))
    require([int(r["state"]) for r in accepted] == list(range(1, 36)), f"Stage89K {mode} state ordering failed")
    result: list[dict[str, object]] = []
    eta = "0" if mode == "SAA" else "0.03"
    for r in accepted:
        result.append({
            "state_id": r["state"], "intensity": r["intensity"], "loc": r["loc"], "lfw": "0", "eta": eta,
            "T1_kg": r["T1"], "T2_kg": r["T2"], "T3_kg": r["T3"], "T4_kg": r["T4"],
            "TerminalLOH_total_kg": r["T_total"], "TERMINALLOH_VERSION": "Stage89K", "MODE": mode,
            "STATE_COUNT": "35", "SITE_COUNT": "4", "ADOPTED_DRO_ETA": "0.03", "TANK_CAP_KG": "[300,200,100,200]",
            "SOURCE_STAGE": "Stage89K", "SOURCE_RUN": "run-002",
        })
    return result


def build() -> None:
    require(not RESULT.exists(), f"Refusing to overwrite existing Stage89M result: {RESULT}")
    require(not BUNDLE.exists(), f"Refusing to create competing Stage89 bundle: {BUNDLE}")
    prerequisite_rows, bank_set_sha = validate_prerequisites()

    for directory in (
        RESULT, BUNDLE, BUNDLE / "config", BUNDLE / "src_snapshot", BUNDLE / "w_candidate",
        BUNDLE / "terminal_tables", BUNDLE / "evidence/stage89j", BUNDLE / "evidence/stage89k",
        BUNDLE / "evidence/stage89l", BUNDLE / "msp_bridge", BUNDLE / "manifests",
        BUNDLE / "large_data_manifest",
    ):
        directory.mkdir(parents=True, exist_ok=False if directory in (RESULT, BUNDLE) else True)

    table_fields = ["state_id", "intensity", "loc", "lfw", "eta", "T1_kg", "T2_kg", "T3_kg", "T4_kg", "TerminalLOH_total_kg", "TERMINALLOH_VERSION", "MODE", "STATE_COUNT", "SITE_COUNT", "ADOPTED_DRO_ETA", "TANK_CAP_KG", "SOURCE_STAGE", "SOURCE_RUN"]
    saa_path = BUNDLE / "terminal_tables/terminal_loh_stage89k_saa_adopted.csv"
    dro_path = BUNDLE / "terminal_tables/terminal_loh_stage89k_dro_eta003_adopted.csv"
    write_csv(saa_path, table_fields, terminal_table("SAA"))
    write_csv(dro_path, table_fields, terminal_table("DRO"))

    table_identity = [
        {"mode": "SAA", "path": rel(saa_path), "sha256": sha256(saa_path), "TERMINALLOH_VERSION": "Stage89K", "state_count": 35, "site_count": 4, "eta": 0, "tank_cap_kg": "[300,200,100,200]"},
        {"mode": "DRO", "path": rel(dro_path), "sha256": sha256(dro_path), "TERMINALLOH_VERSION": "Stage89K", "state_count": 35, "site_count": 4, "eta": 0.03, "tank_cap_kg": "[300,200,100,200]"},
    ]
    write_csv(BUNDLE / "terminal_tables/terminal_table_identity.csv", list(table_identity[0]), table_identity)

    evidence = {
        "stage89j": ["README.md", "candidate_schema.md", "candidate_bank_manifest.csv", "candidate_state_summary.csv", "candidate_intensity_summary.csv", "dres_qa.csv", "aelec_qa.csv", "qg_probability_qa.csv", "topology_cache_summary.csv", "fc_static_capacity_metadata.csv", "frozen_randomness_replay_qa.md", "source_manifest.csv"],
        "stage89k": ["README.md", "terminalLoh_old_vs_new_by_state.csv", "terminalLoh_intensity_summary.csv", "dual_channel_service_diagnostics.csv", "solver_status_by_state.csv", "inventory_qa.csv", "fc_capacity_qa.csv", "probability_dro_qa.csv", "candidate_bank_input_qa.csv", "stage88_terminalLoh_semantics_audit.md", "source_manifest.csv"],
        "stage89l": ["README.md", "h2_island_ablation_by_state.csv", "h2_island_ablation_by_intensity.csv", "h2_island_service_mechanism.csv", "mechanism_interpretation.md", "inventory_qa.csv", "probability_dro_qa.csv", "accepted_input_qa.csv", "source_manifest.csv"],
    }
    source_dirs = {"stage89j": J, "stage89k": K, "stage89l": L}
    for stage, filenames in evidence.items():
        for filename in filenames:
            copy(source_dirs[stage] / filename, BUNDLE / f"evidence/{stage}/{filename}")

    for filename in ("candidate_schema.md", "candidate_state_summary.csv", "candidate_intensity_summary.csv", "dres_qa.csv", "aelec_qa.csv", "qg_probability_qa.csv", "topology_cache_summary.csv", "fc_static_capacity_metadata.csv", "frozen_randomness_replay_qa.md", "source_manifest.csv"):
        copy(J / filename, BUNDLE / f"w_candidate/{filename}")
    exact = J / "exact_group_summary.csv"
    write_csv(BUNDLE / "w_candidate/exact_group_summary.csv", ["copied_or_referenced", "original_path", "size_bytes", "sha256", "reason"], [{"copied_or_referenced": "REFERENCED", "original_path": rel(exact), "size_bytes": exact.stat().st_size, "sha256": sha256(exact), "reason": "19.3 MB exact-group index remains in accepted historical result"}])

    terminal_copies = {
        "state_ordering_metadata.csv": K / "solver_status_by_state.csv",
        "site_ordering_metadata.csv": J / "fc_static_capacity_metadata.csv",
        "terminalLoh_old_vs_new_by_state.csv": K / "terminalLoh_old_vs_new_by_state.csv",
        "terminalLoh_intensity_summary.csv": K / "terminalLoh_intensity_summary.csv",
        "solver_status_summary.csv": K / "solver_status_by_state.csv",
        "inventory_qa.csv": K / "inventory_qa.csv",
        "fc_qa.csv": K / "fc_capacity_qa.csv",
        "probability_qa.csv": K / "probability_dro_qa.csv",
    }
    for name, source in terminal_copies.items():
        copy(source, BUNDLE / f"terminal_tables/{name}")

    snapshots = [
        (J / "build_candidate_bank.py", "stage89j/build_candidate_bank.py", "W bank construction, Dres/Aroad/Aelec/C grouping and q_g"),
        (ROOT / "results/task-002-stage2b-b3-smoke/w-5point-reconfig-hardening-preview/run-003/run_preview.py", "stage89j/run_five_point_g1_replay.py", "five-point exposure and frozen G1 replay"),
        (ROOT / "results/task-002-stage2b-b3-smoke/topology-based-h2-island-diagnostic/run-001/run_diagnostic.py", "stage89j/run_radial_topology_reconstruction.py", "deterministic radial reconstruction"),
        (K / "run_stage89k_terminal_loh.py", "stage89k/run_stage89k_terminal_loh.py", "SAA/Pearson DRO dual-channel shared-T LP and QA"),
        (ROOT / "terminalLoh_wdro/current_w_mainline_stage88/src_snapshot/terminalLoh_wdro/src/run_step04CC6_35state_case.py", "stage89k/run_step04CC6_35state_case.py", "accepted Stage88 solver/economic mother"),
        (L / "run_stage89l_ablation.py", "stage89l/run_stage89l_ablation.py", "road-only ablation and mechanism summary"),
    ]
    snapshot_manifest: list[dict[str, object]] = []
    for source, target_rel, role in snapshots:
        target = BUNDLE / "src_snapshot" / target_rel
        copy(source, target)
        snapshot_manifest.append({"original_path": rel(source), "snapshot_path": rel(target), "size_bytes": target.stat().st_size, "sha256": sha256(target), "role": role, "stage_run_identity": target_rel.split("/")[0]})
    write_csv(BUNDLE / "manifests/source_manifest.csv", list(snapshot_manifest[0]), snapshot_manifest)
    write_csv(RESULT / "stage89_source_snapshot_manifest.csv", list(snapshot_manifest[0]), snapshot_manifest)

    parameter_rows = [
        ("scenario_signature", "(Dres,Aroad,Aelec,C)", "Stage89J candidate_schema.md"), ("sample_count_per_state", "15000", "Stage89J candidate manifest"),
        ("terminal_starting_states", "35", "Stage89J/Stage89K"), ("q_g", "multiplicity/15000", "Stage89J candidate_schema.md"),
        ("pearson_eta", "0.03", "Stage89K semantics audit"), ("tank_capacity_kg", "[300,200,100,200]", "Stage89K semantics audit"),
        ("electrolyzer_pmax_kw", "[300,200,120,150]", "Stage89F accepted input"), ("initial_inventory_kg", "[58.04455704486949,50.30813793862475,25.262133442309338,33.02358084624278]", "Stage89F accepted input"),
        ("hydrogen_conversion_kg_per_kWh", "0.0195", "accepted NearStageInput"), ("fc_static_capacity", "per-site one-hour slice metadata", "Stage89J fc_static_capacity_metadata.csv"),
        ("c_H2_yuan_per_kg", "32.5213675213675", "Stage89K semantics audit"), ("M_H2_yuan_per_kg", "1283.205", "Stage89K semantics audit"),
        ("terminal_gap_penalty_in_TerminalLOH", "ABSENT", "Stage89K semantics audit"), ("ordinary_shortage_penalty_in_TerminalLOH", "ABSENT", "Stage89K semantics audit"),
        ("solver", "gurobipy 12.0.1; Threads=1", "Stage89K semantics audit"), ("feasibility_tolerance", "1e-9", "Stage89K semantics audit"),
        ("optimality_tolerance", "1e-9", "Stage89K semantics audit"), ("decomposition_gap", "abs<=1e-4 yuan or relative<=1e-8", "Stage89K semantics audit"),
        ("active_msp_dt_h", "8", "Stage89F model"), ("source_demand_stage_dt_h", "6 (historical/source metadata only)", "NearStageInput.NormalDemand"),
        ("operating_stage_count", "6", "Stage89F model"), ("hours_per_operating_stage", "[8,8,8,8,8,8]", "Stage89F model"),
        ("W1_W3_slice_semantics", "three official one-hour post-landfall service slices; five hazard observations do not add time weight", "Stage89J README"),
        ("exact_grouping", "raw-byte equality; no rounding/tolerance/clustering/quantization", "Stage89J candidate_schema.md"),
    ]
    write_csv(BUNDLE / "config/accepted_parameter_manifest.csv", ["parameter", "accepted_value", "mechanical_source"], [{"parameter": a, "accepted_value": b, "mechanical_source": c} for a, b, c in parameter_rows])
    config_sources = [
        ROOT / "terminalLoh_wdro/current_w_mainline_stage88/manifests/active_config_manifest.csv",
        ROOT / "terminalLoh_wdro/current_w_mainline_stage88/config/terminalLoh_wdro/config/formal_b3_wind_modes.csv",
        ROOT / "terminalLoh_wdro/current_w_mainline_stage88/config/terminalLoh_wdro/config/stage87b_candidate1/README.md",
        ROOT / "terminalLoh_wdro/current_w_mainline_stage88/config/data/yuanqi/stage1_road_edges.csv",
        ROOT / "terminalLoh_wdro/current_w_mainline_stage88/config/data/yuanqi/stage1_site_nodes.csv",
        J / "fc_static_capacity_metadata.csv",
        K / "stage88_terminalLoh_semantics_audit.md",
    ]
    config_manifest = [{"path": rel(p), "size_bytes": p.stat().st_size, "sha256": sha256(p), "copied_or_referenced": "REFERENCED", "role": "accepted Stage89J/K configuration source"} for p in config_sources]
    write_csv(BUNDLE / "config/config_source_manifest.csv", list(config_manifest[0]), config_manifest)

    large_rows = [
        {"file_or_directory": "Stage89J grouped candidate banks", "role": "adopted W bank body", "source_stage": "Stage89J", "source_run": "run-001", "relative_path": "terminalLoh_wdro/output/stage89j_topology_h2_dual_channel_w_candidate/run-001", "path_hint": "repository-relative", "size_bytes": 1104251473, "file_count": 35, "sha256_or_aggregate_identity": bank_set_sha, "required_for_rebuild": "YES", "git_tracked": "NO"},
        {"file_or_directory": "Stage89K formal case arrays/checkpoints", "role": "accepted TerminalLOH solve evidence", "source_stage": "Stage89K", "source_run": "run-002", "relative_path": "terminalLoh_wdro/output/stage89k_terminalLoh_dual_channel_candidate/run-002", "path_hint": "repository-relative", "size_bytes": sum(int(r["bytes"]) for r in rows(K / "large_output_manifest.csv")), "file_count": len(rows(K / "large_output_manifest.csv")), "sha256_or_aggregate_identity": sha256(K / "large_output_manifest.csv"), "required_for_rebuild": "NO", "git_tracked": "NO"},
        {"file_or_directory": "Stage89L road-only case arrays/checkpoints", "role": "accepted mechanism ablation evidence", "source_stage": "Stage89L", "source_run": "run-001", "relative_path": "terminalLoh_wdro/output/stage89l_h2_island_incremental_ablation/run-001", "path_hint": "repository-relative", "size_bytes": sum(int(r["bytes"]) for r in rows(L / "large_output_manifest.csv")), "file_count": len(rows(L / "large_output_manifest.csv")), "sha256_or_aggregate_identity": sha256(L / "large_output_manifest.csv"), "required_for_rebuild": "NO", "git_tracked": "NO"},
    ]
    write_csv(BUNDLE / "large_data_manifest/large_data_manifest.csv", list(large_rows[0]), large_rows)
    write_csv(RESULT / "stage89_large_data_manifest.csv", list(large_rows[0]), large_rows)
    write_csv(RESULT / "prerequisite_identity_audit.csv", list(prerequisite_rows[0]), prerequisite_rows)

    adoption = [
        {"stage": "Stage89J", "accepted_run": rel(J), "previous_identity": "FORMAL_W_CANDIDATE", "adopted_identity": "CURRENT_ADOPTED_W_MAINLINE", "status": "PASS"},
        {"stage": "Stage89K", "accepted_run": rel(K), "previous_identity": "FORMAL_TERMINALLOH_CANDIDATE", "adopted_identity": "CURRENT_ADOPTED_TERMINALLOH", "status": "PASS"},
        {"stage": "Stage89L", "accepted_run": rel(L), "previous_identity": "FORMAL_MECHANISM_ABLATION", "adopted_identity": "FORMAL_MECHANISM_ABLATION", "status": "PASS"},
        {"stage": "Stage88", "accepted_run": "terminalLoh_wdro/current_w_mainline_stage88", "previous_identity": "CURRENT W/TERMINALLOH CANDIDATE", "adopted_identity": "SUPERSEDED_HISTORICAL_REPRODUCIBLE_PREDECESSOR", "status": "PASS"},
    ]
    write_csv(RESULT / "stage89_adoption_audit.csv", list(adoption[0]), adoption)

    source_manifest = [
        {"path": rel(Path(__file__)), "role": "Stage89M bundle builder and prerequisite auditor", "size_bytes": Path(__file__).stat().st_size, "sha256": sha256(Path(__file__))},
        *[{"path": row["snapshot_path"], "role": row["role"], "size_bytes": row["size_bytes"], "sha256": row["sha256"]} for row in snapshot_manifest],
    ]
    write_csv(RESULT / "source_manifest.csv", list(source_manifest[0]), source_manifest)
    print(json.dumps({"status": "PREPARED", "bundle": rel(BUNDLE), "result": rel(RESULT), "saa_sha256": table_identity[0]["sha256"], "dro_sha256": table_identity[1]["sha256"], "stage89j_bank_set_sha256": bank_set_sha}, indent=2))


if __name__ == "__main__":
    build()
