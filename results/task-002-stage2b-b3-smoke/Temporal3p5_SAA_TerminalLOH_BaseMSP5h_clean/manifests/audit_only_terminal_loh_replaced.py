"""Prove the isolated MSP candidate differs from Formal Base only as authorized."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path


PACKAGE = Path(__file__).resolve().parents[1]
PROJECT = PACKAGE.parents[2]
BASE_PACKAGE = PROJECT / "results/task-002-stage2b-b3-smoke/BASE_OOS_TESTING_REPAIR_100PATH_SMOKE"
FORMAL_PACKAGE = PROJECT / "results/task-002-stage2b-b3-smoke/B1011_FORMAL_TRAINING_5H"
FROZEN_TERMINAL = PROJECT / "terminalLoh_wdro/partial_temporal_refinement/dro_3p5h/run-001/frozen_terminal_loh/terminal_loh_temporal3p5_dro_eta003_candidate.csv"
OUTPUT = PACKAGE / "manifests/ONLY_TERMINALLOH_REPLACED_QA.json"

OLD_SHA = "2fa1958944110701239a109ebf46d959324a351f2f27c1c3fbd62f333066eaa8"
NEW_SHA = "70e02fe1b46d09b4cf77fcf1fbfa1f1c4ab98c8200c52b51d6bdd7ac2205dae5"


def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def files(root: Path) -> dict[str, Path]:
    return {str(path.relative_to(root)).replace("\\", "/"): path for path in root.rglob("*") if path.is_file()}


def exact_transform(source: str, replacements: list[tuple[str, str]], name: str) -> str:
    transformed = source
    for old, new in replacements:
        count = transformed.count(old)
        if count != 1:
            raise RuntimeError(f"{name}: expected exactly one occurrence, got {count}: {old[:100]}")
        transformed = transformed.replace(old, new)
    return transformed


def main() -> None:
    candidate_program = PACKAGE / "program"
    base_program = BASE_PACKAGE / "program"
    candidate_files = files(candidate_program)
    base_files = files(base_program)
    expected_changed = {
        "terminalLoh_wdro/current_w_mainline_stage89/msp_bridge/load_current_stage89_hourly_h2.m",
        "terminalLoh_wdro/current_w_mainline_stage89/msp_bridge/load_stage89_adopted_terminal_loh_h2.m",
    }
    expected_added = {
        "terminalLoh_wdro/current_w_mainline_stage89/terminal_tables/terminal_loh_temporal3p5_dro_eta003_candidate.csv",
        "utils/mc_sample.m", "utils/termination_check.m", "utils/create_oos_paths.m",
        "utils/utils/mc_sample.m", "utils/utils/termination_check.m", "utils/utils/create_oos_paths.m",
    }
    common = sorted(set(candidate_files) & set(base_files))
    changed = {name for name in common if sha(candidate_files[name]) != sha(base_files[name])}
    added = set(candidate_files) - set(base_files)
    missing = set(base_files) - set(candidate_files)

    # Loader 1: only the accepted table version identity changes.
    rel = "terminalLoh_wdro/current_w_mainline_stage89/msp_bridge/load_current_stage89_hourly_h2.m"
    source = base_files[rel].read_text(encoding="utf-8")
    expected = exact_transform(source, [
        ('tableAudit.pass && tableAudit.table_version=="Stage89K";',
         'tableAudit.pass && tableAudit.table_version=="TEMPORAL3P5_DRO_BASEMSP5H_CANDIDATE";'),
    ], rel)
    loader_current_exact = expected == candidate_files[rel].read_text(encoding="utf-8")

    # Loader 2: only table file, hash, and provenance/version gates change.
    rel = "terminalLoh_wdro/current_w_mainline_stage89/msp_bridge/load_stage89_adopted_terminal_loh_h2.m"
    source = base_files[rel].read_text(encoding="utf-8")
    expected = exact_transform(source, [
        (f'acceptedSha = "{OLD_SHA}";', f'acceptedSha = "{NEW_SHA}";'),
        ("defaultFile = fullfile(tableDir, 'terminal_loh_stage89k_dro_eta003_adopted.csv');",
         "defaultFile = fullfile(tableDir, 'terminal_loh_temporal3p5_dro_eta003_candidate.csv');"),
        ('any(tbl.TERMINALLOH_VERSION ~= "Stage89K")', 'any(tbl.TERMINALLOH_VERSION ~= "TEMPORAL3P5_DRO_BASEMSP5H_CANDIDATE")'),
        ('any(tbl.SOURCE_STAGE ~= "Stage89K") || any(tbl.SOURCE_RUN ~= "run-002")',
         'any(tbl.SOURCE_STAGE ~= "Temporal3p5_DurationAware_Stage89K_Formulation") || ...\n        any(tbl.SOURCE_RUN ~= "partial_temporal_refinement/dro_3p5h/run-001")'),
        ("error('Stage89M:MetadataMismatch', 'Stage89K adopted table metadata/version/mode gate failed.');",
         "error('Stage89M:MetadataMismatch', 'Temporal3p5 candidate table metadata/version/mode gate failed.');"),
        ("'source_sha256',sourceSha,'table_version',\"Stage89K\", ...\n    'source_stage',\"Stage89K\",'source_run',\"run-002\",'eta',expectedEta, ...",
         "'source_sha256',sourceSha,'table_version',\"TEMPORAL3P5_DRO_BASEMSP5H_CANDIDATE\", ...\n    'source_stage',\"Temporal3p5_DurationAware_Stage89K_Formulation\", ...\n    'source_run',\"partial_temporal_refinement/dro_3p5h/run-001\",'eta',expectedEta, ..."),
    ], rel)
    loader_terminal_exact = expected == candidate_files[rel].read_text(encoding="utf-8")

    # The fixed-5h training source is the formal B1011 loop with only identity,
    # TerminalLOH hash, Base Pmax arm, isolated folder, and status path changes.
    formal_runner = (FORMAL_PACKAGE / "training/run_candidate_formal_h2.m").read_text(encoding="utf-8")
    expected_runner = formal_runner.replace(OLD_SHA, NEW_SHA)
    replacements = [
        ("'2fa195...eaa8'", "'70e02f...dae5'"),
        ('string(p.terminal_loh_lookup_audit.table_version)~="Stage89K"',
         'string(p.terminal_loh_lookup_audit.table_version)~="TEMPORAL3P5_DRO_BASEMSP5H_CANDIDATE"'),
        ('function assert_arm(arm),if ~ismember(arm,["B0001","B1011"]),error(\'Stage89Q:Arm\',\'Arm must be B0001 or B1011.\');end,end',
         'function assert_arm(arm),if arm~="TEMPORAL3P5",error(\'Stage89Q:Arm\',\'Arm must be TEMPORAL3P5.\');end,end'),
        ('if arm=="B0001",label="ARM-B0001";expected=[300;200;120;187.5];trainFolder=\'02_training_b0001\';oosFolder=\'04_oos_b0001\';\nelse,label="ARM-B1011";expected=[375;200;150;187.5];trainFolder=\'03_training_b1011\';oosFolder=\'05_oos_b1011\';end',
         'label="TEMPORAL3P5_DRO_BASEMSP5H_CANDIDATE";expected=[300;200;120;150];trainFolder=\'training\';oosFolder=\'oos_modeC\';'),
        ("fullfile(outDir,'03_training_b1011','checkpoint','checkpoint_final.mat')",
         "fullfile(outDir,'training','checkpoint','checkpoint_final.mat')"),
    ]
    for old, new in replacements:
        if expected_runner.count(old) != 1:
            raise RuntimeError(f"formal runner replacement occurrence mismatch: {old[:100]}")
        expected_runner = expected_runner.replace(old, new)
    candidate_runner = (PACKAGE / "training/run_candidate_formal_h2.m").read_text(encoding="utf-8")
    runner_exact = expected_runner == candidate_runner

    util_names = ["mc_sample.m", "termination_check.m", "create_oos_paths.m"]
    utils = []
    for name in util_names:
        formal = FORMAL_PACKAGE / "program/utils" / name
        active = PACKAGE / "program/utils" / name
        nested = PACKAGE / "program/utils/utils" / name
        utils.append({"file": name, "formal_sha256": sha(formal), "active_sha256": sha(active), "nested_sha256": sha(nested), "pass": sha(formal) == sha(active) == sha(nested)})
    training_text = candidate_runner
    oos_text = (PACKAGE / "testing/run_temporal3p5_oos_mode_c.m").read_text(encoding="utf-8")
    active_utils_path_only = "genpath" not in training_text + oos_text and "addpath(fullfile(rootDir,'utils'));" in training_text and "addpath(fullfile(rootDir,'utils'));" in oos_text

    config = {}
    for line in (PACKAGE / "RUN_CONFIG.txt").read_text(encoding="utf-8").splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            key, value = line.split("=", 1); config[key.strip()] = value.strip()
    config_pass = all([
        config.get("PMAX_KW") == "300,200,120,150", config.get("K_INIT") == "81",
        config.get("TERMINAL_MODE") == "DIRECT_GAP", config.get("TERMINAL_REDISTRIBUTION") == "OFF",
        config.get("TERMINAL_GAP_PENALTY") == "1000", config.get("TRAINING_DURATION_SECONDS") == "18000",
        config.get("TRAINING_SEED") == "20260513", config.get("START_MODE") == "FRESH",
        config.get("RUN_TESTING") == "0",
    ])
    table_path = candidate_program / "terminalLoh_wdro/current_w_mainline_stage89/terminal_tables/terminal_loh_temporal3p5_dro_eta003_candidate.csv"
    terminal_pass = sha(table_path) == sha(FROZEN_TERMINAL) == NEW_SHA

    checks = {
        "canonical_base_exists": BASE_PACKAGE.is_dir(),
        "formal_5h_source_exists": FORMAL_PACKAGE.is_dir(),
        "common_program_files": len(common),
        "byte_identical_common_program_files": len(common) - len(changed),
        "changed_program_files_exact_set": changed == expected_changed,
        "candidate_added_files_exact_set": added == expected_added,
        "base_program_files_missing_from_candidate": sorted(missing),
        "loader_current_exact_authorized_transform": loader_current_exact,
        "loader_terminal_exact_authorized_transform": loader_terminal_exact,
        "formal_5h_runner_exact_authorized_transform": runner_exact,
        "formal_runtime_utils_exact": all(row["pass"] for row in utils),
        "nested_utils_inactive": active_utils_path_only,
        "frozen_terminal_table_exact": terminal_pass,
        "base_config_identity": config_pass,
    }
    pass_value = all(value for key, value in checks.items() if isinstance(value, bool)) and not missing
    payload = {
        "qa": "PASS" if pass_value else "FAIL",
        "base_msp_identity_reused": pass_value,
        "only_terminal_loh_replaced": pass_value,
        "candidate_status": "NOT YET FORMALLY ADOPTED",
        "checks": checks,
        "changed_program_files": sorted(changed),
        "candidate_added_files": sorted(added),
        "runtime_utils": utils,
        "terminal_loh_sha256": NEW_SHA,
    }
    OUTPUT.write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"ONLY_TERMINALLOH_REPLACED_QA={payload['qa']}")
    if not pass_value:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
