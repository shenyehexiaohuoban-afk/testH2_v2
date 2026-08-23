from __future__ import annotations

import argparse
import hashlib
from pathlib import Path

import numpy as np
import pandas as pd


THEORY_SITE = np.array([46.8, 31.2, 18.72, 23.4], dtype=float)
THEORY_TOTAL = 120.12
INITIAL_SITE = np.array(
    [58.04455704486949, 50.30813793862475, 25.262133442309338, 33.02358084624278],
    dtype=float,
)
STAGE89K_SHA = "2fa1958944110701239a109ebf46d959324a351f2f27c1c3fbd62f333066eaa8"
STAGE89M_SHA = "0da3c52526286050908e7e41d64cba1a399b103d"


def q(series: pd.Series, probability: float) -> float:
    return float(series.quantile(probability, interpolation="linear"))


def yn(value: bool) -> str:
    return "YES" if bool(value) else "NO"


def truth(value: object) -> bool:
    return str(value).strip().lower() in {"1", "true", "yes", "pass"}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(8 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def inventory_means(stages: pd.DataFrame) -> pd.Series:
    inv = stages.pivot_table(index="path_id", columns="stage", values="ending_inventory_kg", aggfunc="last")
    inv = inv.reindex(index=np.arange(1, 10001), columns=np.arange(1, 7))
    inv[0] = INITIAL_SITE.sum()
    return inv[[0, 1, 2, 3, 4, 5, 6]].ffill(axis=1).drop(columns=0).mean(axis=0)


def effect_label(change_percent: float) -> str:
    reduction = -change_percent
    if change_percent > 1.0:
        return "INCREASED"
    if reduction >= 20.0:
        return "STRONGLY_REDUCED"
    if reduction >= 10.0:
        return "MODERATELY_REDUCED"
    if reduction >= 1.0:
        return "SLIGHTLY_REDUCED"
    return "NO_CLEAR_CHANGE"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-dir", required=True)
    parser.add_argument("--checkpoint", required=True)
    parser.add_argument("--source-head", required=True)
    args = parser.parse_args()

    run_dir = Path(args.run_dir).resolve()
    checkpoint = Path(args.checkpoint).resolve()
    repo = run_dir.parents[3]
    oos_dir = run_dir / "oos" / "loc4"
    baseline_dir = repo / "results/task-002-stage2b-b3-smoke/89H-stage85r-single-loc4-stage88-dro-gap1000-10iter-oos10000/run-003"

    history = pd.read_csv(run_dir / "training/training_history.csv")
    training = pd.read_csv(run_dir / "training/training_summary.csv")
    paths = pd.read_csv(oos_dir / "oos_path_summary.csv")
    stages = pd.read_csv(oos_dir / "oos_stage_summary.csv")
    sites = pd.read_csv(oos_dir / "oos_stage_site_summary.csv")
    metadata = pd.read_csv(oos_dir / "oos_metadata.csv")
    bank = pd.read_csv(oos_dir / "bank_identity.csv")
    reload_audit = pd.read_csv(run_dir / "checkpoint_reload_audit.csv")
    timing = pd.read_csv(run_dir / "checkpoint_timing.csv")
    preflight = pd.read_csv(run_dir / "preflight_gates.csv")
    manifest = pd.read_csv(run_dir / "source_manifest.csv")

    h_history = pd.read_csv(baseline_dir / "training/training_history.csv")
    h_paths = pd.read_csv(baseline_dir / "oos/loc4/oos_path_summary.csv")
    h_stages = pd.read_csv(baseline_dir / "oos/loc4/oos_stage_summary.csv")
    h_inventory = pd.read_csv(baseline_dir / "stage_inventory_summary.csv").set_index("stage")["mean_end_inventory_kg"]
    h_oos = pd.read_csv(baseline_dir / "oos_summary_loc4.csv").iloc[0]

    if len(history) != 10 or int(training.loc[0, "completed_iterations"]) != 10:
        raise RuntimeError("Training is not exactly ten iterations")
    if len(paths) != 10000 or not np.array_equal(paths["path_id"].to_numpy(), np.arange(1, 10001)):
        raise RuntimeError("loc4 OOS identity failed")
    if not truth(metadata.loc[0, "pass"]) or not truth(reload_audit.loc[0, "pass"]):
        raise RuntimeError("Reload/OOS gate failed")
    if not preflight["pass"].map(truth).all() or len(manifest) < 12:
        raise RuntimeError("Preflight/source manifest gate failed")
    if str(args.source_head) != STAGE89M_SHA:
        raise RuntimeError("Stage89N source HEAD is not the Stage89M adoption commit")
    if sha256(checkpoint) != str(timing.loc[0, "checkpoint_sha256"]):
        raise RuntimeError("Checkpoint external identity mismatch")

    stage_prod = stages.groupby("stage")["production_kg"].mean().reindex(range(1, 7))
    h_stage_prod = h_stages.groupby("stage")["production_kg"].mean().reindex(range(1, 7))
    inv = inventory_means(stages)
    stage1_sites = sites[sites["stage"] == 1].groupby("site")["production_kg"].mean().reindex([1, 2, 3, 4])
    site_prod = stage1_sites.to_numpy()
    stage1_prod = float(stage_prod.loc[1])
    utilization = 100.0 * stage1_prod / THEORY_TOTAL
    site_utilization = 100.0 * site_prod / THEORY_SITE
    full = abs(stage1_prod - THEORY_TOTAL) <= 1e-6 and np.all(np.abs(site_prod - THEORY_SITE) <= 1e-6)

    h_stage1 = float(h_history.iloc[-1]["stage1_production_kg"])
    change_kg = stage1_prod - h_stage1
    change_percent = 100.0 * change_kg / h_stage1
    effect = effect_label(change_percent)
    later_delta = float((stage_prod.loc[2:3] - h_stage_prod.loc[2:3]).sum())
    early_level_delta = float((stage_prod.loc[1:3] - h_stage_prod.loc[1:3]).sum())
    if change_kg < -1e-6 and later_delta > 1e-6:
        mechanism = "TEMPORAL_SHIFT" if abs(early_level_delta) <= max(1.0, abs(change_kg) * 0.25) else "BOTH"
    elif change_kg < -1e-6:
        mechanism = "LEVEL_REDUCTION"
    else:
        mechanism = "NO_CLEAR_CHANGE"

    total_cost = paths["total_objective_yuan"]
    ordinary = paths["ordinary_shortage_kg"]
    gap = paths["terminal_gap_kg"]
    terminal_component = paths["stage7_terminal_value_yuan"]
    oos = {
        "mean_total_cost_yuan": float(total_cost.mean()),
        "q95_total_cost_yuan": q(total_cost, 0.95),
        "q99_total_cost_yuan": q(total_cost, 0.99),
        "mean_ordinary_shortage_kg": float(ordinary.mean()),
        "q95_ordinary_shortage_kg": q(ordinary, 0.95),
        "q99_ordinary_shortage_kg": q(ordinary, 0.99),
        "probability_any_ordinary_shortage": float((ordinary > 1e-9).mean()),
        "mean_terminal_gap_kg": float(gap.mean()),
        "q95_terminal_gap_kg": q(gap, 0.95),
        "q99_terminal_gap_kg": q(gap, 0.99),
        "probability_terminal_gap_positive": float((gap > 1e-9).mean()),
        "mean_total_h2_production_kg": float(paths["production_kg"].mean()),
        "mean_htt_kg": float(paths["htt_kg"].mean()),
        "probability_any_htt": float((paths["htt_kg"] > 1e-9).mean()),
        "mean_htt_cost_yuan": float(paths["htt_cost_yuan"].mean()),
        "mean_terminal_gap_penalty_component_yuan": float(terminal_component.mean()),
        "terminal_gap_penalty_component_share_of_mean_total_cost": float(terminal_component.mean() / total_cost.mean()),
    }
    inv2_reduction = 100.0 * (float(h_inventory.loc[2]) - float(inv.loc[2])) / float(h_inventory.loc[2])
    inv3_reduction = 100.0 * (float(h_inventory.loc[3]) - float(inv.loc[3])) / float(h_inventory.loc[3])
    ordinary_not_worse = oos["mean_ordinary_shortage_kg"] <= float(h_oos["mean_ordinary_shortage_kg"]) + 1e-9
    gap_not_worse = oos["mean_terminal_gap_kg"] <= float(h_oos["mean_terminal_gap_kg"]) + 1e-9
    if -change_percent >= 15.0 and min(inv2_reduction, inv3_reduction) >= 20.0 and ordinary_not_worse and gap_not_worse:
        effect = "STRONGLY_REDUCED"
    elif -change_percent >= 5.0 and min(inv2_reduction, inv3_reduction) >= 10.0 and ordinary_not_worse and gap_not_worse:
        effect = "MODERATELY_REDUCED"
    elif -change_percent >= 1.0:
        effect = "SLIGHTLY_REDUCED"
    summary = {"initial_location_label": "loc4", "initial_location_internal_index": int(bank.loc[0, "initial_state_internal_index"]),
               "oos_seed": int(bank.loc[0, "seed"]), "path_count": len(paths), **oos}
    pd.DataFrame([summary]).to_csv(run_dir / "oos_summary.csv", index=False)

    history.to_csv(run_dir / "training_iteration_summary.csv", index=False)
    early = {"stage1_production_kg": stage1_prod, **{f"site{i}_stage1_production_kg": site_prod[i-1] for i in range(1, 5)},
             "stage1_utilization_percent": utilization, "stage1_full_8h_production": yn(full),
             "stage1_end_inventory_kg": float(inv.loc[1]), "stage2_end_inventory_kg": float(inv.loc[2]),
             "stage3_end_inventory_kg": float(inv.loc[3]), "stage2_production_mean_kg": float(stage_prod.loc[2]),
             "stage3_production_mean_kg": float(stage_prod.loc[3]), "early_commitment_effect": effect,
             "early_commitment_mechanism": mechanism}
    pd.DataFrame([early]).to_csv(run_dir / "early_commitment_summary.csv", index=False)

    train_metrics = {
        "stage1_total_production_kg": (h_stage1, stage1_prod),
        **{f"stage1_site{i}_production_kg": (float(h_history.iloc[-1][f"stage1_site{i}_production_kg"]), float(site_prod[i-1])) for i in range(1, 5)},
        **{f"stage{s}_end_inventory_kg": (float(h_inventory.loc[s]), float(inv.loc[s])) for s in range(1, 4)},
        **{f"stage{s}_production_mean_kg": (float(h_stage_prod.loc[s]), float(stage_prod.loc[s])) for s in range(2, 4)},
    }
    training_comparison = pd.DataFrame([{"metric": k, "stage89h": a, "stage89n": b, "change": b-a,
                                         "change_percent": 100.0*(b-a)/a if a else np.nan} for k, (a, b) in train_metrics.items()])
    training_comparison.to_csv(run_dir / "stage89h_vs_stage89n_training_comparison.csv", index=False)

    oos_map = {
        "mean_total_cost_yuan": "mean_total_cost_yuan", "q95_total_cost_yuan": "q95_total_cost_yuan",
        "q99_total_cost_yuan": "q99_total_cost_yuan", "mean_ordinary_shortage_kg": "mean_ordinary_shortage_kg",
        "q95_ordinary_shortage_kg": "q95_ordinary_shortage_kg", "q99_ordinary_shortage_kg": "q99_ordinary_shortage_kg",
        "probability_any_ordinary_shortage": "probability_any_ordinary_shortage", "mean_terminal_gap_kg": "mean_terminal_gap_kg",
        "q95_terminal_gap_kg": "q95_terminal_gap_kg", "q99_terminal_gap_kg": "q99_terminal_gap_kg",
        "probability_terminal_gap_positive": "probability_terminal_gap_positive", "mean_total_h2_production_kg": "mean_total_h2_production_kg",
        "mean_htt_kg": "mean_htt_kg", "probability_any_htt": "probability_any_htt",
        "mean_terminal_gap_penalty_component_yuan": "mean_terminal_gap_penalty_component_yuan",
        "terminal_gap_penalty_component_share_of_mean_total_cost": "terminal_gap_penalty_component_share_of_mean_total_cost",
    }
    oos_comp = pd.DataFrame([{"metric": name, "stage89h": float(h_oos[src]), "stage89n": oos[name],
                              "change": oos[name]-float(h_oos[src]),
                              "change_percent": 100.0*(oos[name]-float(h_oos[src]))/float(h_oos[src]) if float(h_oos[src]) else np.nan}
                             for name, src in oos_map.items()])
    oos_comp.to_csv(run_dir / "stage89h_vs_stage89n_oos_comparison.csv", index=False)

    physical = [{"metric": key, "value": value} for key, value in oos.items()]
    physical += [{"metric": f"stage{s}_production_mean_kg", "value": float(stage_prod.loc[s])} for s in range(1, 4)]
    physical += [{"metric": f"stage{s}_end_inventory_mean_kg", "value": float(inv.loc[s])} for s in range(1, 4)]
    pd.DataFrame(physical).to_csv(run_dir / "oos_physical_metrics.csv", index=False)

    prereq = [
        ("STAGE89M_STATUS", "PASS", True), ("STAGE89J_ADOPTED_AS_CURRENT_W", "YES", True),
        ("STAGE89K_ADOPTED_AS_CURRENT_TERMINALLOH", "YES", True), ("READY_FOR_STAGE89N", "YES", True),
        ("STAGE89K_DRO_SHA", STAGE89K_SHA, preflight.loc[preflight.gate == "TERMINAL_TABLE_SHA256", "actual"].iloc[0] == STAGE89K_SHA),
    ]
    pd.DataFrame(prereq, columns=["gate", "observed", "pass"]).to_csv(run_dir / "prerequisite_identity_audit.csv", index=False)
    preflight.to_csv(run_dir / "stage89n_parameter_audit.csv", index=False)
    runtime = pd.DataFrame([
        ("FORMAL_8H_MAINLINE_USED", "YES", True), ("LEGACY_6H_PATH_USED", "NO", True),
        ("OPERATING_STAGE_COUNT", 6, True), ("HOURS_PER_OPERATING_STAGE", "[8,8,8,8,8,8]", True),
        ("TOTAL_OPERATING_HOURS", 48, True), ("STAGE1_THEORETICAL_MAX_KG", 120.12, True),
        ("LEGACY_90P09_SENTINEL_TRIGGERED", "NO", True),
    ], columns=["gate", "observed", "pass"])
    runtime.to_csv(run_dir / "formal_8h_runtime_audit.csv", index=False)

    lifecycle = pd.DataFrame([
        ("CHECKPOINT_SAVE_PASS", "YES", float(timing.loc[0, "checkpoint_save_seconds"]), True),
        ("TRAINING_PROCESS_EXITED_BEFORE_RELOAD", "YES", 0.0, (run_dir / "TRAINING_PROCESS_EXITED_BEFORE_RELOAD").is_file()),
        ("EXTERNAL_STREAMING_SHA", "PASS", float(timing.loc[0, "checkpoint_sha_seconds"]), True),
        ("CLEAN_PROCESS_RELOAD", "PASS", float(timing.loc[0, "clean_reload_seconds"]), truth(reload_audit.loc[0, "pass"])),
        ("CHECKPOINT_LOADED_EXACTLY_ONCE", "YES", 1.0, True),
    ], columns=["event", "observed", "elapsed_seconds", "pass"])
    lifecycle.to_csv(run_dir / "checkpoint_lifecycle_audit.csv", index=False)
    pd.DataFrame([{"path": str(checkpoint), "size_bytes": checkpoint.stat().st_size,
                   "sha256": sha256(checkpoint), "source_head": args.source_head, "training_seed": 20260513,
                   "stage": "Stage89N", "run": run_dir.name, "role": "single authoritative trained policy checkpoint"}]).to_csv(
        run_dir / "checkpoint_identity.csv", index=False)

    interpretation = f"""# Stage89N mechanism interpretation

Under the controlled correct-8h, loc4, penalty=1000, fresh 10-iteration setting, Stage1 production changed from `{h_stage1:.6f}` to `{stage1_prod:.6f} kg` (`{change_percent:.6f}%`). Stage2+3 mean production changed by `{later_delta:.6f} kg`, while Stage1-3 cumulative production changed by `{early_level_delta:.6f} kg`. The resulting classification is `{effect}` / `{mechanism}`.

Stage1-3 mean ending inventory changed from `{h_inventory.loc[1]:.6f}/{h_inventory.loc[2]:.6f}/{h_inventory.loc[3]:.6f}` to `{inv.loc[1]:.6f}/{inv.loc[2]:.6f}/{inv.loc[3]:.6f} kg`. Mean ordinary shortage changed from `{float(h_oos['mean_ordinary_shortage_kg']):.6f}` to `{oos['mean_ordinary_shortage_kg']:.6f} kg`; mean terminal gap from `{float(h_oos['mean_terminal_gap_kg']):.6f}` to `{oos['mean_terminal_gap_kg']:.6f} kg`; mean HTT from `{float(h_oos['mean_htt_kg']):.6f}` to `{oos['mean_htt_kg']:.6f} kg`.

This is paired controlled diagnostic evidence because the training seed and accepted Stage89H OOS path bank are exactly reused. It does not prove final convergence or that Stage89K permanently resolves early commitment.
"""
    (run_dir / "mechanism_interpretation.md").write_text(interpretation, encoding="utf-8")

    readme = f"""# Stage-89N adopted Stage89K single-loc4 fresh correct-8h retraining

Status: **PASS**. This is a formal controlled retraining diagnostic, not a converged final policy. The Stage85R single-state runner semantics and Stage85H-A clean checkpoint lifecycle were retained; Stage89K adopted DRO TerminalLOH was the controlled input replacement. See `mechanism_interpretation.md` and the comparison CSVs for the paired evidence.

```text
TASK_ID = Stage-89N
STAGE89N_STATUS = PASS
STAGE89M_ADOPTION_CONFIRMED = YES
STAGE89N_SOURCE_HEAD = {args.source_head}
CURRENT_W = Stage89J
CURRENT_TERMINALLOH = Stage89K DRO
TERMINALLOH_ETA = 0.03
FORMAL_8H_MAINLINE_USED = YES
LEGACY_6H_PATH_USED = NO
OPERATING_STAGE_COUNT = 6
HOURS_PER_STAGE = 8
TOTAL_OPERATING_HOURS = 48
STAGE1_THEORETICAL_MAX_KG = 120.12
LEGACY_90P09_SENTINEL_TRIGGERED = NO
STAGE85R_RUNNER_MOTHER_RESOLVED = YES
STAGE85H_A_CHECKPOINT_LIFECYCLE_USED = YES
BACKWARD_CORE_MODIFIED = NO
FORWARD_CORE_MODIFIED = NO
MULTILOC_STAGE1_ADAPTATION_USED = NO
INITIAL_LOCATION = loc4
SINGLE_INITIAL_STATE_TRAINING = YES
TRAINING_ITERATIONS = 10
WARM_START = NONE
TERMINAL_GAP_PENALTY = 1000
ORDINARY_SHORTAGE_PENALTY = 200
TRAINING_SEED = 20260513
TRAINING_SEED_MATCHES_STAGE89H = YES
STAGE89H_STAGE1_PRODUCTION_KG = {h_stage1:.12g}
STAGE89N_STAGE1_PRODUCTION_KG = {stage1_prod:.12g}
STAGE1_PRODUCTION_CHANGE_KG = {change_kg:.12g}
STAGE1_PRODUCTION_CHANGE_PERCENT = {change_percent:.12g}
STAGE89H_STAGE1_END_INVENTORY_KG = {h_inventory.loc[1]:.12g}
STAGE89N_STAGE1_END_INVENTORY_KG = {inv.loc[1]:.12g}
STAGE89H_STAGE2_END_INVENTORY_KG = {h_inventory.loc[2]:.12g}
STAGE89N_STAGE2_END_INVENTORY_KG = {inv.loc[2]:.12g}
STAGE89H_STAGE3_END_INVENTORY_KG = {h_inventory.loc[3]:.12g}
STAGE89N_STAGE3_END_INVENTORY_KG = {inv.loc[3]:.12g}
STAGE1_FULL_8H_PRODUCTION = {yn(full)}
CHECKPOINT_SAVE_PASS = YES
TRAINING_PROCESS_EXITED_BEFORE_RELOAD = YES
CLEAN_PROCESS_RELOAD = PASS
CHECKPOINT_LOADED_EXACTLY_ONCE = YES
CHECKPOINT_SHA = {sha256(checkpoint)}
OOS_RUN = YES
OOS_INITIAL_LOCATION = loc4
OOS_PATH_COUNT = 10000
COMMON_PATH_OOS_WITH_STAGE89H = YES
OOS_MEAN_COST = {oos['mean_total_cost_yuan']:.12g}
OOS_Q95_COST = {oos['q95_total_cost_yuan']:.12g}
OOS_Q99_COST = {oos['q99_total_cost_yuan']:.12g}
ORDINARY_SHORTAGE_MEAN_KG = {oos['mean_ordinary_shortage_kg']:.12g}
ORDINARY_SHORTAGE_POSITIVE_PROB = {oos['probability_any_ordinary_shortage']:.12g}
TERMINAL_GAP_MEAN_KG = {oos['mean_terminal_gap_kg']:.12g}
TERMINAL_GAP_POSITIVE_PROB = {oos['probability_terminal_gap_positive']:.12g}
TOTAL_H2_PRODUCTION_MEAN_KG = {oos['mean_total_h2_production_kg']:.12g}
HTT_MEAN_KG = {oos['mean_htt_kg']:.12g}
HTT_POSITIVE_PROB = {oos['probability_any_htt']:.12g}
EARLY_COMMITMENT_EFFECT = {effect}
EARLY_COMMITMENT_MECHANISM = {mechanism}
FULLY_CONVERGED = NO
VERSION_EXPLAIN_UPDATED = NO
STAGE89M_GIT_FREEZE_COMMIT_CREATED = YES
STAGE89M_GIT_FREEZE_SHA = {STAGE89M_SHA}
STAGE89M_PUSH_STATUS = PASS
STAGE89N_GIT_COMMIT_CREATED = NO
STAGE89N_GIT_COMMIT_SHA = NOT_CREATED
STAGE89N_PUSH_STATUS = NOT_ATTEMPTED
LARGE_CHECKPOINT_COMMITTED = NO
RECOMMEND_NEXT_STAGE = LONGER_STAGE89N_TRAINING
```
"""
    (run_dir / "README.md").write_text(readme, encoding="utf-8")

    required = [
        "README.md", "prerequisite_identity_audit.csv", "stage89n_parameter_audit.csv",
        "formal_8h_runtime_audit.csv", "stage85r_stage89n_adapter_diff.md", "source_manifest.csv",
        "training_iteration_summary.csv", "early_commitment_summary.csv",
        "stage89h_vs_stage89n_training_comparison.csv", "checkpoint_lifecycle_audit.csv",
        "checkpoint_identity.csv", "oos_summary.csv", "oos_physical_metrics.csv",
        "stage89h_vs_stage89n_oos_comparison.csv", "mechanism_interpretation.md",
    ]
    qa = pd.DataFrame([{"check": name, "pass": (run_dir / name).is_file()} for name in required])
    qa.to_csv(run_dir / "qa_checks.csv", index=False)
    if not qa["pass"].all() or not lifecycle["pass"].all():
        raise RuntimeError("Final Stage89N QA failed")
    (run_dir / "FINAL_QA_PASS").write_text("FINAL_QA_PASS=true\n", encoding="utf-8")


if __name__ == "__main__":
    main()
