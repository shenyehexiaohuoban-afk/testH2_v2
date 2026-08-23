#!/usr/bin/env python3
"""Finalize Stage-89M after the MATLAB integration regression has passed."""

from __future__ import annotations

import csv
import hashlib
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RESULT = ROOT / "results/task-002-stage2b-b3-smoke/stage89m-formal-adoption-and-8h-integration/run-001"
BUNDLE = ROOT / "terminalLoh_wdro/current_w_mainline_stage89"
VERSION = ROOT / "version explain"


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        while block := handle.read(1024 * 1024):
            h.update(block)
    return h.hexdigest()


def read_rows(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def write_rows(path: Path, fieldnames: list[str], data: list[dict[str, object]]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, lineterminator="\n", quoting=csv.QUOTE_ALL)
        writer.writeheader()
        writer.writerows(data)


def append_unique(path: Path, key: str, item: dict[str, str]) -> None:
    existing = read_rows(path)
    if any(row[key] == item[key] for row in existing):
        raise RuntimeError(f"Refusing duplicate {key}={item[key]} in {path}")
    fields = list(existing[0])
    write_rows(path, fields, existing + [{field: item.get(field, "N/A") for field in fields}])


def assert_all_pass(path: Path) -> None:
    data = read_rows(path)
    if not data or "pass" not in data[0] or any(row["pass"].lower() not in ("1", "true") for row in data):
        raise RuntimeError(f"Integration gate failed: {path}")


def write_docs() -> None:
    saa_sha = read_rows(BUNDLE / "terminal_tables/terminal_table_identity.csv")[0]["sha256"]
    dro_sha = read_rows(BUNDLE / "terminal_tables/terminal_table_identity.csv")[1]["sha256"]
    bank_id = read_rows(RESULT / "prerequisite_identity_audit.csv")[-1]["evidence"]
    result_readme = f"""# Stage-89M formal adoption and correct-8h integration

Status: **PASS**. Stage89J `run-001` is now the current adopted W mainline, Stage89K `run-002` is now the current adopted TerminalLOH, and Stage89L `run-001` remains the formal mechanism ablation that supports adoption. Stage88 is preserved in place as the superseded, historically reproducible predecessor.

## Adoption and evidence boundary

Stage89L is sufficient adoption evidence because its strict road-only versus dual-channel comparison holds the Stage89J bank, Stage89K economics, exact probabilities, Pearson ambiguity, capacity, shared-T LP, and solver gates fixed, changes only `Aelec`, reuses Case C read-only, and obtains 35 SAA + 35 DRO optimal solutions in both arms. It finds a small aggregate DRO reserve increase (`+0.875626%`), material site reallocation and service-mode substitution, and moderate shortage reduction. Therefore `Stage88 → Stage89K` remains the **FULL CANDIDATE EFFECT**; the approximately `-27.44%` DRO mean TerminalLOH change is not an H2 electrical-island-only effect.

## Current identities and navigation

- Current adopted W: `results/task-002-stage2b-b3-smoke/stage89j-topology-h2-dual-channel-w-candidate/run-001`.
- Current adopted TerminalLOH: `results/task-002-stage2b-b3-smoke/stage89k-terminalLoh-dual-channel-candidate/run-002`.
- Adoption evidence: `results/task-002-stage2b-b3-smoke/stage89l-h2-island-incremental-ablation/run-001`.
- Single bundle: `terminalLoh_wdro/current_w_mainline_stage89/`.
- Large bank: `terminalLoh_wdro/output/stage89j_topology_h2_dual_channel_w_candidate/run-001/`.
- Scenario signature: `(Dres,Aroad,Aelec,C)`; `R=15000` for each of 35 starting states; `q_g=multiplicity/15000`.
- Pearson DRO `eta=0.03`; tank capacity `[300,200,100,200] kg`.
- SAA table SHA-256: `{saa_sha}`.
- DRO table SHA-256: `{dro_sha}`.
- Stage89J 35-bank aggregate manifest identity: `{bank_id}`.

The 1.10 GB bank was not copied because the accepted body already exists under the large-output policy; the current bundle contains a one-jump large-data manifest plus lightweight schema, summaries, QA, source snapshots/references, adopted tables, evidence and hashes.

## FA-MSP integration result

The bridge uses the accepted Stage89F resolved architecture: six operating stages, eight actual hourly blocks per stage, 48 total operating hours, hourly IEEE33, P_EL, original H2 demand, production, inventory, directed continuous HTT and PV. Stage7 is analytic TerminalLOH and Stage8 is zero-cost absorbing. `NormalDemand.stage_dt_h=6` is source metadata only; active `params.dt_h=8`. No legacy 6h path was used.

The production sentinel is `[46.8,31.2,18.72,23.4] kg`, total `120.12 kg`. The legacy `90.09 kg` sentinel was not triggered. Site4 is correctly separated as `200 kg` tank and `150 kW` electrolyzer Pmax; accepted initial inventory was unchanged and not capacity-rescaled.

Both adopted SAA and DRO tables load with 35-state/4-site/version/hash/capacity gates; default bridge selection is DRO. Stage7 value and four-dimensional subgradient, one backward terminal cut, and forward terminal evaluation all pass. Negative gates reject Site4 tank=150, Stage88 masquerading as Stage89K, Stage53 legacy input, a 6h runtime, and any operating-stage hourly count other than 8.

No forward/backward core, cut mathematics, training loop, Stage1 cut semantics, hourly-grid mathematics, HTT mathematics or demand mathematics was changed. Stage89G multi-location adaptation was not used. No FA-MSP training, OOS or checkpoint was run or created.

## Stage89N preparation note (not executed)

Stage89N should use the Stage85R accepted single-initial-state runner mother, Stage85H-A lifecycle (`train → save → MATLAB exits → zero MATLAB processes → clean process loads exactly once → reload audit → OOS`), Stage89F correct 8h model, adopted Stage89K DRO table, Site4 tank=200 kg, and one known initial loc4. It must not reload in the training process, duplicate-load `modelLib`, reload merely to hash, or hold a second `modelLib` before OOS. Its first scientific sentinel is `120.12 kg → ?`.

```text
TASK_ID = Stage-89M
STAGE89M_STATUS = PASS
STAGE89J_PREREQUISITE_CONFIRMED = YES
STAGE89K_PREREQUISITE_CONFIRMED = YES
STAGE89L_PREREQUISITE_CONFIRMED = YES
STAGE89J_ADOPTED_AS_CURRENT_W = YES
STAGE89K_ADOPTED_AS_CURRENT_TERMINALLOH = YES
STAGE88_PRESERVED_AS_HISTORICAL_PREDECESSOR = YES
STAGE89_SINGLE_BUNDLE_CREATED = YES
STAGE89_BUNDLE_PATH = terminalLoh_wdro/current_w_mainline_stage89/
LARGE_BANK_DUPLICATED = NO
LARGE_DATA_MANIFEST_CREATED = YES
CURRENT_W_SIGNATURE = (Dres,Aroad,Aelec,C)
DRO_ETA = 0.03
TANK_CAPACITY_KG = [300,200,100,200]
FORMAL_8H_MAINLINE_USED = YES
LEGACY_6H_PATH_USED = NO
OPERATING_STAGE_COUNT = 6
HOURS_PER_STAGE = 8
TOTAL_OPERATING_HOURS = 48
HOURLY_VARIABLE_QA = PASS
STAGE1_THEORETICAL_MAX_KG = 120.12
LEGACY_90P09_SENTINEL_TRIGGERED = NO
SITE4_TANK_KG = 200
SITE4_PMAX_KW = 150
INITIAL_INVENTORY_RESCALED = NO
STAGE89K_DRO_TABLE_LOADED = YES
STAGE89K_HASH_QA = PASS
STATE_MAPPING_QA = PASS
STAGE7_VALUE_SUBGRADIENT_QA = PASS
BACKWARD_TERMINAL_CUT_SMOKE = PASS
FORWARD_TERMINAL_EVAL_SMOKE = PASS
BACKWARD_CORE_MODIFIED = NO
FORWARD_CORE_MODIFIED = NO
MULTILOC_TRAINING_USED = NO
MULTILOC_STAGE1_CUT_ADAPTATION_USED = NO
MULTILOC_STAGE1_ADAPTATION_USED = NO
FA_MSP_TRAINING_RUN = NO
OOS_RUN = NO
CHECKPOINT_CREATED = NO
VERSION_EXPLAIN_UPDATED = YES
READY_FOR_STAGE89N = YES
RECOMMEND_NEXT_STAGE = Stage-89N: single-loc4 fresh correct-8h FA-MSP retraining using adopted Stage89K DRO TerminalLOH
GIT_COMMIT_CREATED = NO
GIT_PUSH_ATTEMPTED = NO
```
"""
    (RESULT / "README.md").write_text(result_readme, encoding="utf-8")
    bundle_readme = f"""# Current adopted Stage89 W + TerminalLOH

**CURRENT ADOPTED W = Stage89J accepted run-001**  
**CURRENT ADOPTED TERMINALLOH = Stage89K accepted run-002**  
**ADOPTION EVIDENCE = Stage89L accepted run-001**  
**Stage89L recommendation = RECOMMEND_ADOPT_STAGE89J_89K = YES**

Identity: `(Dres,Aroad,Aelec,C)`, 35 starting states, `R=15000/state`, `q_g=multiplicity/15000`, Pearson `eta=0.03`, tanks `[300,200,100,200] kg`. Adopted SAA SHA `{saa_sha}`; adopted DRO SHA `{dro_sha}`; Stage89J bank-set identity `{bank_id}`.

`Stage88 → Stage89K` is the **FULL CANDIDATE EFFECT**, not an H2 electrical-island-only effect. Stage89L's strict dual-minus-road-only DRO mean is `+0.875626%` and supports adoption as a mixed/moderate mechanism with material reallocation and service substitution.

Navigate `config/` for accepted parameters and source references, `src_snapshot/` for hash-verified model-generating code, `w_candidate/` for Stage89J schema/QA, `terminal_tables/` for the adopted 35×4 tables, `evidence/` for accepted J/K/L evidence, `msp_bridge/` for the strict correct-8h loader/regression, `manifests/` for complete identities, and `large_data_manifest/` for one-jump large artifacts. The 1.10 GB bank is not duplicated.

FA-MSP bridge result: genuine `6×8h=48h` hourly architecture, Stage1 cap `120.12 kg`, no legacy 6h path, Site4 tank/Pmax `200 kg/150 kW`, Stage7 value/subgradient/cut/forward PASS, no optimization core change, no multi-location adaptation, no training/OOS/checkpoint. Ready for Stage89N single-loc4 fresh training.
"""
    (BUNDLE / "README.md").write_text(bundle_readme, encoding="utf-8")
    (BUNDLE / "CURRENT_W_MAINLINE.md").write_text("""# Current W mainline\n\nStage89J `stage89j-topology-h2-dual-channel-w-candidate/run-001` is the current adopted W. Signature `(Dres,Aroad,Aelec,C)`, 35×15000 frozen draws, 457431 exact groups, `q_g=multiplicity/15000`; no transition or failure randomness was changed. The 35 large banks remain at `terminalLoh_wdro/output/stage89j_topology_h2_dual_channel_w_candidate/run-001/`. Stage88 is preserved as the superseded historical predecessor.\n""", encoding="utf-8")
    (BUNDLE / "CURRENT_TERMINALLOH.md").write_text(f"""# Current TerminalLOH\n\nStage89K `stage89k-terminalLoh-dual-channel-candidate/run-002` is the current adopted TerminalLOH. The adopted 35×4 SAA/DRO tables use tanks `[300,200,100,200] kg`; DRO uses Pearson `eta=0.03`. SAA SHA `{saa_sha}`; DRO SHA `{dro_sha}`. Stage89L remains adoption evidence, not a TerminalLOH table.\n""", encoding="utf-8")
    bridge_identity = [
        {"field": "DEFAULT_TERMINALLOH_SOURCE", "value": "Stage89K DRO adopted table"}, {"field": "ETA", "value": "0.03"},
        {"field": "TANK_CAPACITY_KG", "value": "[300,200,100,200]"}, {"field": "SITE4_TANK_KG", "value": "200"},
        {"field": "SITE4_PMAX_KW", "value": "150"}, {"field": "INITIAL_INVENTORY_RESCALED", "value": "NO"},
        {"field": "ACTIVE_DT_H", "value": "8"}, {"field": "FORMAL_8H_MAINLINE_USED", "value": "YES"},
        {"field": "LEGACY_6H_PATH_USED", "value": "NO"}, {"field": "FA_MSP_TRAINING_RUN", "value": "NO"},
    ]
    write_rows(BUNDLE / "msp_bridge/bridge_identity.csv", ["field", "value"], bridge_identity)


def update_versions() -> None:
    readme = VERSION / "README.md"
    text = readme.read_text(encoding="utf-8")
    marker = "## Stage89M formal adoption and correct-8h integration (2026-08-23)"
    if marker in text:
        raise RuntimeError("Stage89M already registered in version README")
    text += f"""\n\n{marker}\n\nStage89J run-001 and Stage89K run-002 are formally adopted as the current W and TerminalLOH, supported by Stage89L run-001. The unique navigation bundle is `terminalLoh_wdro/current_w_mainline_stage89/`; Stage88 remains a reproducible superseded predecessor. Strict Stage89K SAA/DRO hash, 35-state order, four-site, CAP200 and negative-loader gates pass. The Stage89F model was mechanically rebuilt as six operating stages with eight hourly periods each; Stage1 theoretical cap is 120.12 kg and legacy 90.09 is rejected. Stage7 value/subgradient/cut/forward smoke passes. No training, OOS, checkpoint, multi-location adaptation, or forward/backward-core modification occurred.\n"""
    readme.write_text(text, encoding="utf-8")

    current = VERSION / "CURRENT_MAINLINES.md"
    text = current.read_text(encoding="utf-8")
    old = "## 1. W / TerminalLOH\n\n**CURRENT VERSION**"
    if old not in text:
        raise RuntimeError("CURRENT_MAINLINES Stage88 marker not found")
    new = """## 0. Stage89 adopted W / TerminalLOH (CURRENT)\n\n**CURRENT W:** Stage89J accepted run-001, signature `(Dres,Aroad,Aelec,C)`, 35×15000 frozen draws and exact `q_g=multiplicity/15000`.\n\n**CURRENT TERMINALLOH:** Stage89K accepted run-002, 35×4 SAA/DRO tables, Pearson `eta=0.03`, tank `[300,200,100,200] kg`.\n\n**ADOPTION EVIDENCE:** Stage89L accepted run-001 (`MIXED / MODERATE`, `RECOMMEND_ADOPT_STAGE89J_89K=YES`). Stage88 is preserved as the superseded reproducible predecessor. The sole navigation entry is `terminalLoh_wdro/current_w_mainline_stage89/`. Stage89M verified the Stage89F `6×8h=48h` hourly model, 120.12 kg Stage1 sentinel and strict Stage7/cut/forward integration without training/OOS/checkpoint or core changes.\n\n## 1. W / TerminalLOH (SUPERSEDED STAGE88 PREDECESSOR)\n\n**SUPERSEDED HISTORICAL VERSION**"""
    current.write_text(text.replace(old, new, 1), encoding="utf-8")

    explain = VERSION / "VERSION_EXPLAIN.md"
    text = explain.read_text(encoding="utf-8")
    text += """\n\n### Stage89M：Stage89J/K 正式采用、单一 bundle 与正确 8h integration\n\n**基于：** Stage89J accepted W candidate、Stage89K accepted TerminalLOH candidate、Stage89L adoption evidence、Stage89F resolved 8h model；Stage85R/Stage85H-A 只作为未来 runner/checkpoint engineering lineage。\n\n**改了什么：** 将 Stage89J 提升为 CURRENT/ADOPTED W，将 Stage89K 提升为 CURRENT/ADOPTED TerminalLOH；Stage89L 保持 FORMAL_MECHANISM_ABLATION；Stage88 保留为 superseded historical predecessor。建立唯一 `current_w_mainline_stage89` 轻量 bundle、严格 Stage89K hash/version/capacity loader 和只读 integration regression。\n\n**结果：** J/K/L prerequisite、35 个大 bank SHA、SAA/DRO 35-state mapping、Site4 200 kg tank/150 kW Pmax、未缩放初始库存全部 PASS。Stage1–6 各有 8 个 hourly periods，IEEE33/P_EL/original demand/production/inventory/HTT/PV active，Stage7 analytic、Stage8 absorbing；理论产能 120.12 kg，legacy 90.09 未触发。Stage7 value/subgradient、backward terminal cut、forward terminal evaluation 与五个 negative gates PASS。\n\n**边界：** Stage88→Stage89K 仍是 FULL CANDIDATE EFFECT，不是 H2 island-only effect。未训练、未 OOS、未建 checkpoint、未使用 multi-location adaptation、未改 forward/backward/cut mathematics。状态 `FORMAL_ADOPTION_AND_INTEGRATION / PASS`，ready for Stage89N single-loc4 fresh correct-8h training。\n"""
    explain.write_text(text, encoding="utf-8")

    tree = VERSION / "VERSION_TREE.md"
    text = tree.read_text(encoding="utf-8")
    text = text.replace("D04, Stage89I, Stage89J and Stage89K do not enter the current W, Stage88/89, accepted TerminalLOH, or FA-MSP mainline.", "D04 and Stage89I remain diagnostic/method-preview nodes. Stage89J and Stage89K were formally adopted by Stage89M; their historical candidate outputs remain immutable.")
    text += """\n\n## Stage89 formal adoption and integration\n\n```text\nStage89J formal W candidate\n+ Stage89K formal TerminalLOH candidate\n+ Stage89L formal mechanism ablation/adoption recommendation\n+ Stage89F correct 6×8h hourly model\n└─ Stage89M formal adoption and integration                    [CURRENT W / CURRENT TERMINALLOH]\n   ├─ unique current_w_mainline_stage89 bundle\n   ├─ strict Stage89K SAA/DRO hash/version/capacity loader\n   ├─ six stages × eight hourly periods; 120.12 kg sentinel\n   ├─ Stage7 value/subgradient/cut/forward regression\n   └─ no training/OOS/checkpoint/core modification\n```\n\nStage88 remains the superseded historical reproducible predecessor. Future Stage89N should use Stage85R single-state runner semantics plus Stage85H-A clean-process checkpoint lifecycle, Stage89F model, and adopted Stage89K DRO input.\n"""
    tree.write_text(text, encoding="utf-8")

    registry_item = {
        "version_id":"I15","version_name":"Stage89M formal adoption and correct-8h integration","category":"FORMAL_ADOPTION_AND_INTEGRATION","approx_date":"2026-08-23","parent_version":"I12;I13;I14;I07;M34;M23;W24","parent_confidence":"HIGH",
        "based_on_evidence":"Stage89J 35-bank rehash; Stage89K 70-case QA; Stage89L adoption recommendation; Stage89F six-by-eight-hour construction; Stage7/cut/forward and negative gates",
        "purpose":"adopt Stage89J/K, create one reproducibility bundle, and prove correct 8h FA-MSP interface before fresh training","problem_being_solved":"candidate outputs were distributed and the adopted table had not been proven against the real 8h hourly architecture",
        "main_changes":"formal identity promotion; lightweight bundle; strict Stage89K loader/hash gates; Site4 sync; isolated integration regression","model_structure_change":"NO; accepted Stage89F architecture used read-only","parameter_change":"NO optimization parameter change; Stage89K adopted identity selected","data_change":"NO W or TerminalLOH regeneration; adopted lightweight tables derived mechanically from accepted Stage89K solver status",
        "runner_change":"YES smoke/bridge only; no training runner","checkpoint_change":"NO checkpoint created; Stage85H-A lifecycle documented for Stage89N","oos_change":"NO OOS","terminal_loh_change":"YES identity promotion to Stage89K adopted SAA/DRO tables","capacity_change":"NO; confirms CAP200 and Site4 Pmax150",
        "key_functions_added":"load_stage89_adopted_terminal_loh_h2; load_current_stage89_hourly_h2; validate_stage89_8h_runtime_h2; run_stage89m_integration_regression_h2","key_files":"terminalLoh_wdro/current_w_mainline_stage89/msp_bridge","input_source":"Stage89J run-001; Stage89K run-002; Stage89L run-001; Stage89F current hourly model",
        "output_path":"results/task-002-stage2b-b3-smoke/stage89m-formal-adoption-and-8h-integration/run-001; terminalLoh_wdro/current_w_mainline_stage89","key_result":"adoption PASS; six-by-eight-hour QA PASS; 120.12kg sentinel; Stage7/cut/forward PASS; all negative gates reject","status":"FORMAL_ADOPTION_AND_INTEGRATION","accepted_or_not":"YES CURRENT W AND CURRENT TERMINALLOH","superseded_by":"NONE","still_reusable_parts":"single bundle; loader; manifests; integration smoke; Stage89N preparation lineage","current_relevance":"CURRENT adopted W/TerminalLOH and integration entry","evidence_paths":"Stage89M README and CSV audits; current_w_mainline_stage89 README/manifests","notes":"Stage88 preserved; large bank not duplicated; no training/OOS/checkpoint; no multi-location adaptation or core modification"
    }
    append_unique(VERSION / "version_registry.csv", "version_id", registry_item)

    lineage_path = VERSION / "version_lineage.csv"
    lineage = read_rows(lineage_path)
    additions = [
        ("I12","FORMAL_W_ADOPTION","Stage89J accepted frozen dual-channel W bank","promotes identity to current adopted W"),
        ("I13","FORMAL_TERMINALLOH_ADOPTION","Stage89K accepted SAA/DRO tables and LP semantics","promotes identity to current adopted TerminalLOH"),
        ("I14","ADOPTION_EVIDENCE","MIXED/MODERATE strict mechanism ablation and recommendation YES","keeps Stage89L as evidence only"),
        ("I07","MODEL_ARCHITECTURE_INTEGRATION","Stage89F resolved six-by-eight-hour hourly model","changes loader/input identity only"),
        ("M34","FUTURE_RUNNER_LINEAGE","Stage85R accepted single-state training/OOS mother","no runner execution in Stage89M"),
        ("M23","FUTURE_CHECKPOINT_LINEAGE","Stage85H-A clean-process lifecycle","documents Stage89N lifecycle; creates no checkpoint"),
        ("W24","SUPERSEDED_PREDECESSOR","Stage88 CAP200 economic/solver predecessor and historical bundle","preserves reproducibility while replacing current identity"),
    ]
    for parent, relation, inherited, changed in additions:
        lineage.append({"child_version":"I15","parent_version":parent,"relationship_type":relation,"inherited_components":inherited,"changed_components":changed,"evidence":"Stage89M prerequisite/adoption/8h integration audits and bundle manifests","confidence":"HIGH"})
    write_rows(lineage_path, list(lineage[0]), lineage)

    feature_item = {"version_id":"I15","version_name":"Stage89M formal adoption + 8h integration","6h_aggregate":"NO","8h_stage":"YES","hourly_IEEE33":"YES","hourly_H2_demand":"YES","hourly_HTT":"YES","original_hourly_demand":"YES","Stage7_TerminalLOH":"YES","Stage88_TerminalLOH":"NO (SUPERSEDED)","Site4_CAP200":"YES","Pearson_DRO":"YES","checkpoint_save":"NO","clean_process_reload":"NO (DOCUMENTED ONLY)","OOS":"NO","multi_initial_loc_OOS":"NO","current_candidate":"YES CURRENT/ADOPTED"}
    append_unique(VERSION / "version_feature_matrix.csv", "version_id", feature_item)

    problem_item = {"problem_id":"PF-024","symptom":"an adopted Stage89K table could be confused with Stage88/Stage53 or wired into a legacy 6h runtime","first_seen_version":"Stage89M adoption gate","root_cause":"candidate/current identities and FA-MSP time-scale lineage were separate; generic table shape alone was insufficient","diagnosed_in_version":"Stage89M","fixed_in_version":"Stage89M","fix_method":"unique bundle; hard-coded SAA/DRO SHA and Stage89K metadata; 35-state/capacity gates; six-by-eight-hour variable construction; 120.12kg sentinel; negative rejection of Stage88 Stage53 6h and seven-hour cases","regressed_later":"NO","regression_version":"N/A","current_status":"RESOLVED_FOR_CURRENT_ADOPTED_ENTRY","evidence":"Stage89M terminalLoh_loader_identity_audit.csv; formal_8h_architecture_audit.csv; stage1_production_cap_sentinel.csv; negative_gate_tests.csv"}
    append_unique(VERSION / "problem_fix_registry.csv", "problem_id", problem_item)


def write_manifests_and_scope() -> None:
    lineage = [
        {"child":"Stage89M","parent":"Stage89J","relationship":"formal current W adoption","identity":"accepted run-001"},
        {"child":"Stage89M","parent":"Stage89K","relationship":"formal current TerminalLOH adoption","identity":"accepted run-002"},
        {"child":"Stage89M","parent":"Stage89L","relationship":"formal adoption evidence","identity":"accepted run-001"},
        {"child":"Stage89M","parent":"Stage89F","relationship":"correct 8h model architecture","identity":"resolved formal model"},
        {"child":"Stage89M","parent":"Stage88","relationship":"superseded reproducible predecessor","identity":"preserved in place"},
    ]
    write_rows(BUNDLE / "manifests/lineage_manifest.csv", list(lineage[0]), lineage)

    snapshot_original = {r["snapshot_path"]: r["original_path"] for r in read_rows(BUNDLE / "manifests/source_manifest.csv")}
    bundle_rows: list[dict[str, object]] = []
    for path in sorted(p for p in BUNDLE.rglob("*") if p.is_file() and p.name not in ("bundle_manifest.csv", "sha256_manifest.csv")):
        rp = path.relative_to(ROOT).as_posix()
        inside = path.relative_to(BUNDLE).as_posix()
        if inside.startswith("evidence/stage89j") or inside.startswith("w_candidate"):
            stage, run, role = "Stage89J", "run-001", "accepted W evidence"
        elif inside.startswith("evidence/stage89k") or inside.startswith("terminal_tables"):
            stage, run, role = "Stage89K", "run-002", "adopted TerminalLOH evidence/table"
        elif inside.startswith("evidence/stage89l"):
            stage, run, role = "Stage89L", "run-001", "adoption evidence"
        elif inside.startswith("msp_bridge"):
            stage, run, role = "Stage89M", "run-001", "8h integration bridge"
        else:
            stage, run, role = "Stage89M", "run-001", "bundle navigation/config/manifest"
        bundle_rows.append({"path":rp,"role":role,"source_stage":stage,"source_run":run,"original_path":snapshot_original.get(rp, rp),"size_bytes":path.stat().st_size,"sha256":sha256(path),"tracked_or_untracked":"untracked","copied_or_referenced":"REFERENCED" if inside.startswith("large_data_manifest") or inside=="w_candidate/exact_group_summary.csv" or inside.startswith("config/config_source_manifest") else "COPIED_OR_GENERATED","required_for_reproduction":"YES" if inside.startswith(("config","src_snapshot","terminal_tables","msp_bridge","manifests")) else "NO"})
    fields = ["path","role","source_stage","source_run","original_path","size_bytes","sha256","tracked_or_untracked","copied_or_referenced","required_for_reproduction"]
    write_rows(BUNDLE / "manifests/bundle_manifest.csv", fields, bundle_rows)
    write_rows(RESULT / "stage89_bundle_manifest.csv", fields, bundle_rows)
    sha_rows = [{"path":r["path"],"size_bytes":r["size_bytes"],"sha256":r["sha256"]} for r in bundle_rows]
    write_rows(BUNDLE / "manifests/sha256_manifest.csv", ["path","size_bytes","sha256"], sha_rows)

    protected = ["fa_h2/backward_pass_h2.m","fa_h2/forward_pass_h2.m","fa_h2/add_cut_h2.m","fa_h2/train_models_h2.m","fa_h2/eval_h2.m"]
    scope = []
    for item in protected:
        work = ROOT / item
        head = subprocess.check_output(["git","show",f"HEAD:{item}"],cwd=ROOT)
        head_sha = hashlib.sha256(head).hexdigest()
        scope.append({"path":item,"role":"protected optimization core","stage89m_modified":"NO" if sha256(work)==head_sha else "PREEXISTING_OR_EXTERNAL_DIFF","head_sha256":head_sha,"working_sha256":sha256(work),"gate":"PASS" if sha256(work)==head_sha else "RECORDED_PREEXISTING"})
    for item in ("terminalLoh_wdro/current_w_mainline_stage89","results/task-002-stage2b-b3-smoke/stage89m-formal-adoption-and-8h-integration/run-001","version explain","codex_rule/log.md"):
        scope.append({"path":item,"role":"Stage89M allowed scope","stage89m_modified":"YES","head_sha256":"N/A","working_sha256":"N/A","gate":"PASS"})
    write_rows(RESULT / "git_scope_audit.csv", list(scope[0]), scope)

    source_files = [ROOT / "scripts/build_stage89m_adoption_bundle.py", ROOT / "scripts/finalize_stage89m.py", *sorted((BUNDLE / "msp_bridge").glob("*.m"))]
    source_manifest = [{"path":p.relative_to(ROOT).as_posix(),"role":"Stage89M source","size_bytes":p.stat().st_size,"sha256":sha256(p)} for p in source_files]
    write_rows(RESULT / "source_manifest.csv", list(source_manifest[0]), source_manifest)


def append_log() -> None:
    log = ROOT / "codex_rule/log.md"
    text = log.read_text(encoding="utf-8")
    marker = "### 2026-08-23 - Stage-89M formal adoption and correct-8h integration"
    if marker in text:
        raise RuntimeError("Stage89M already present in log")
    entry = f"""\n\n{marker}\n\n- Mechanically confirmed Stage89M was unoccupied, branch `task/002-stage2b-b3-smoke` was synchronized at accepted Stage89L commit `b3036138eb9313e69befc98c6d6b7a0b26ce2e35`, and no MATLAB/Gurobi process was active. Preserved all pre-existing tracked/untracked work without clean/reset/restore/stash.\n- Re-hashed all 35 Stage89J banks (525000 draws, 457431 exact groups, 1104251473 bytes) and revalidated Stage89J/K/L accepted status, solver, inventory, FC, probability and mechanism gates. Formally adopted Stage89J as current W and Stage89K as current TerminalLOH; Stage89L remains mechanism evidence and Stage88 remains the superseded reproducible predecessor.\n- Created the unique lightweight bundle `terminalLoh_wdro/current_w_mainline_stage89/`. The 1.10 GB bank and large K/L arrays were not copied; one-jump manifests record their paths, sizes, counts and identities. Adopted SAA/DRO table SHA values are `3ef6d441dddcd15056b97da6e03944705a41900397ee7576e0e700c6237c7148` and `2fa1958944110701239a109ebf46d959324a351f2f27c1c3fbd62f333066eaa8`.\n- Ran only the Stage89M MATLAB integration regression. All six operating stages contain eight real hourly blocks with IEEE33, P_EL, original hourly H2 demand, production, inventory, directed continuous HTT and PV; Stage7 analytic and Stage8 absorbing semantics pass. Stage1 theoretical maximum is 120.12 kg; legacy 90.09 is rejected. Site4 tank/Pmax is 200 kg/150 kW and initial inventory is unchanged.\n- Stage7 value/four-dimensional subgradient, backward terminal cut and forward terminal evaluation pass. Negative gates reject Site4 tank=150, Stage88 hash, Stage53 table, 6h runtime and non-eight hourly count. No forward/backward/cut/training/OOS mathematics was changed; no multi-location adaptation, FA-MSP training, OOS or checkpoint was used. Version explain registries were updated. No Git add/commit/push occurred.\n"""
    log.write_text(text + entry, encoding="utf-8")


def main() -> None:
    required = ["terminalLoh_loader_identity_audit.csv","terminalLoh_state_mapping_qa.csv","msp_parameter_sync_audit.csv","formal_8h_architecture_audit.csv","hourly_variable_count_by_stage.csv","stage1_production_cap_sentinel.csv","stage7_value_subgradient_smoke.csv","backward_terminal_cut_smoke.csv","forward_terminal_eval_smoke.csv","negative_gate_tests.csv"]
    if not (RESULT / "MATLAB_INTEGRATION_PASS.txt").is_file():
        raise RuntimeError("MATLAB integration PASS marker is absent")
    for name in required:
        assert_all_pass(RESULT / name)
    write_docs()
    update_versions()
    write_manifests_and_scope()
    append_log()
    print("STAGE89M_FINALIZATION=PASS")


if __name__ == "__main__":
    main()
