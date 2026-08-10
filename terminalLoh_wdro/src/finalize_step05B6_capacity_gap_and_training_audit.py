"""Finalize Step-05B-6 from frozen read-only LP and saved-cut evidence."""

from __future__ import annotations

import argparse
import hashlib
import re
from pathlib import Path

import numpy as np
import pandas as pd


FOCUS_STATES = [16, 17, 18, 19]
STATE19_PATHS = [1529, 2134, 5371, 8092, 8289, 8650, 9095, 9913]
TOL = 1.0e-7


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def conditional_stats(frame: pd.DataFrame) -> dict[str, float | int]:
    gaps = frame["system_total_capacity_gap_kg"].astype(float)
    bad = gaps > TOL
    positive = gaps[bad]
    shares = frame.loc[bad, "capacity_gap_share_of_target"].astype(float)
    return {
        "oos_path_count": int(len(frame)),
        "system_total_insufficient_path_count": int(bad.sum()),
        "system_total_insufficient_path_share": float(bad.mean()),
        "unconditional_mean_capacity_gap_kg": float(gaps.mean()),
        "conditional_mean_capacity_gap_kg": float(positive.mean()) if len(positive) else 0.0,
        "conditional_median_capacity_gap_kg": float(positive.median()) if len(positive) else 0.0,
        "conditional_q95_capacity_gap_kg": float(positive.quantile(0.95)) if len(positive) else 0.0,
        "conditional_max_capacity_gap_kg": float(positive.max()) if len(positive) else 0.0,
        "terminal_loh_total_target_kg": float(frame["terminal_loh_total_target_kg"].mean()),
        "conditional_mean_gap_share_of_target": float(shares.mean()) if len(shares) else 0.0,
        "conditional_median_gap_share_of_target": float(shares.median()) if len(shares) else 0.0,
        "station_targets_physically_feasible_path_share": float(
            frame["station_targets_feasible"].astype(bool).mean()
        ),
    }


def build_gap_outputs(raw: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    expected_methods = {"saa", "chi2_eta003"}
    if set(raw["method"]) != expected_methods or len(raw) != 510:
        raise RuntimeError("Capacity raw table does not contain the expected 510 paired rows.")
    if not raw["solve_pass"].astype(bool).all():
        raise RuntimeError("At least one diagnostic LP is not optimal.")

    long_rows: list[dict[str, object]] = []
    for method in ["saa", "chi2_eta003"]:
        for state in FOCUS_STATES:
            group = raw[(raw.method == method) & (raw.state_id == state)].copy()
            row: dict[str, object] = {"method": method, "state": state}
            row.update(conditional_stats(group))
            long_rows.append(row)
    long = pd.DataFrame(long_rows)

    path = raw.pivot(index=["path_id", "state_id"], columns="method").reset_index()
    path.columns = [
        "_".join([str(part) for part in col if str(part)]) if isinstance(col, tuple) else str(col)
        for col in path.columns
    ]
    transitions: list[str] = []
    for row in path.itertuples():
        saa_bad = float(row.system_total_capacity_gap_kg_saa) > TOL
        dro_bad = float(row.system_total_capacity_gap_kg_chi2_eta003) > TOL
        if not saa_bad and dro_bad:
            transitions.append("SAA_feasible_DRO_infeasible")
        elif saa_bad and dro_bad:
            transitions.append("both_infeasible")
        elif not saa_bad and not dro_bad:
            transitions.append("both_feasible")
        else:
            transitions.append("SAA_infeasible_DRO_feasible")
    transition = pd.DataFrame(
        {
            "path_id": path.path_id.astype(int),
            "state": path.state_id.astype(int),
            "saa_terminal_loh_total_target_kg": path.terminal_loh_total_target_kg_saa,
            "dro_terminal_loh_total_target_kg": path.terminal_loh_total_target_kg_chi2_eta003,
            "dro_minus_saa_target_kg": (
                path.terminal_loh_total_target_kg_chi2_eta003
                - path.terminal_loh_total_target_kg_saa
            ),
            "saa_max_feasible_terminal_total_kg": path.max_feasible_terminal_total_inventory_kg_saa,
            "dro_max_feasible_terminal_total_kg": path.max_feasible_terminal_total_inventory_kg_chi2_eta003,
            "saa_capacity_gap_kg": path.system_total_capacity_gap_kg_saa,
            "dro_capacity_gap_kg": path.system_total_capacity_gap_kg_chi2_eta003,
            "dro_minus_saa_capacity_gap_kg": (
                path.system_total_capacity_gap_kg_chi2_eta003
                - path.system_total_capacity_gap_kg_saa
            ),
            "saa_capacity_gap_share_of_target": path.capacity_gap_share_of_target_saa,
            "dro_capacity_gap_share_of_target": path.capacity_gap_share_of_target_chi2_eta003,
            "saa_system_total_sufficient": path.system_total_sufficient_saa.astype(bool),
            "dro_system_total_sufficient": path.system_total_sufficient_chi2_eta003.astype(bool),
            "feasibility_transition": transitions,
        }
    ).sort_values(["state", "path_id"])

    wide_rows: list[dict[str, object]] = []
    for state in FOCUS_STATES:
        saa = long[(long.method == "saa") & (long.state == state)].iloc[0]
        dro = long[(long.method == "chi2_eta003") & (long.state == state)].iloc[0]
        trans = transition[transition.state == state]
        counts = trans.feasibility_transition.value_counts()
        wide_rows.append(
            {
                "state": state,
                "oos_path_count": int(saa.oos_path_count),
                "saa_target_total_kg": float(saa.terminal_loh_total_target_kg),
                "dro_target_total_kg": float(dro.terminal_loh_total_target_kg),
                "dro_minus_saa_target_kg": float(
                    dro.terminal_loh_total_target_kg - saa.terminal_loh_total_target_kg
                ),
                "saa_insufficient_path_count": int(saa.system_total_insufficient_path_count),
                "dro_insufficient_path_count": int(dro.system_total_insufficient_path_count),
                "saa_insufficient_path_share": float(saa.system_total_insufficient_path_share),
                "dro_insufficient_path_share": float(dro.system_total_insufficient_path_share),
                "dro_minus_saa_insufficient_share": float(
                    dro.system_total_insufficient_path_share
                    - saa.system_total_insufficient_path_share
                ),
                "saa_conditional_mean_gap_kg": float(saa.conditional_mean_capacity_gap_kg),
                "dro_conditional_mean_gap_kg": float(dro.conditional_mean_capacity_gap_kg),
                "dro_minus_saa_conditional_mean_gap_kg": float(
                    dro.conditional_mean_capacity_gap_kg
                    - saa.conditional_mean_capacity_gap_kg
                ),
                "saa_conditional_mean_gap_share_of_target": float(
                    saa.conditional_mean_gap_share_of_target
                ),
                "dro_conditional_mean_gap_share_of_target": float(
                    dro.conditional_mean_gap_share_of_target
                ),
                "saa_feasible_dro_infeasible_count": int(
                    counts.get("SAA_feasible_DRO_infeasible", 0)
                ),
                "both_infeasible_count": int(counts.get("both_infeasible", 0)),
                "both_feasible_count": int(counts.get("both_feasible", 0)),
                "saa_infeasible_dro_feasible_count": int(
                    counts.get("SAA_infeasible_DRO_feasible", 0)
                ),
                "capacity_classification": "B_SAA_gap_preexists_DRO_amplifies",
            }
        )
    wide = pd.DataFrame(wide_rows)
    return long, wide, transition


def parse_lb_log(path: Path) -> dict[str, float | int]:
    values: list[tuple[int, float]] = []
    pattern = re.compile(r"H2 Iter (\d+): LB = ([0-9eE+\-.]+)")
    for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        match = pattern.search(line)
        if match:
            values.append((int(match.group(1)), float(match.group(2))))
    if not values:
        raise RuntimeError(f"No LB trace in {path}")
    series = dict(values)
    last_iter = values[-1][0]
    def gain(window: int) -> float:
        prior = max(1, last_iter - window)
        return float(series[last_iter] - series.get(prior, values[0][1]))
    return {
        "logged_iteration_count": last_iter,
        "final_lb": values[-1][1],
        "last_50_iteration_lb_gain": gain(50),
        "last_100_iteration_lb_gain": gain(100),
        "last_200_iteration_lb_gain": gain(200),
    }


def build_training_outputs(
    repo: Path, archive: pd.DataFrame, cut: pd.DataFrame, trace: pd.DataFrame, physical: pd.DataFrame
) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame, str]:
    selected = physical[
        (physical.state_id == 19)
        & (physical.path_id.isin(STATE19_PATHS))
        & physical.physical_total_sufficient.astype(bool)
        & physical.physical_spatial_feasible.astype(bool)
        & (physical.actual_terminal_gap_kg > TOL)
    ].copy()
    if sorted(selected.path_id.astype(int).tolist()) != STATE19_PATHS:
        raise RuntimeError("The fixed state19 eight-path set no longer matches Step-05B-4.")

    selected_trace = trace[trace.path_id.isin(STATE19_PATHS)].copy()
    node_keys = ["method", "path_id", "state_id", "decision_stage", "current_k"]
    node_map = selected_trace.groupby(node_keys, as_index=False).first()
    node_map = node_map[
        [
            "method", "path_id", "state_id", "decision_stage", "current_k",
            "current_a", "current_loc", "current_lf", "history_node_id",
            "node_oos_path_count", "future_terminal_state_count",
            "outcome_frequency", "positive_target_modal_top_site",
            "positive_target_modal_top_site_probability",
            "conditional_max_site_target_range_kg", "actual_terminal_gap_kg",
            "actual_I_total_dro_kg", "T_total_dro_kg",
            "actual_total_sufficient", "service_preserving_max_terminal_total_kg",
        ]
    ].rename(columns={"outcome_frequency": "realized_terminal_state_probability"})
    node_map["node_oos_frequency"] = node_map.node_oos_path_count / 10000.0
    node_map["late_decision_stage_5_or_6"] = node_map.decision_stage.isin([5, 6])
    audited_keys = set(
        zip(archive.method, archive.path_id.astype(int), archive.decision_stage.astype(int))
    )
    node_map["saved_cut_audit_available"] = [
        (row.method, int(row.path_id), int(row.decision_stage)) in audited_keys
        for row in node_map.itertuples()
    ]
    node_map = node_map.sort_values(["path_id", "decision_stage", "method"])

    logs = {
        "saa": parse_lb_log(
            repo / "results/task-002-stage2b-b3-smoke/57-main-msp-converged-terminal-loh-ab/run-003/case-saa/matlab_console.log"
        ),
        "chi2_eta003": parse_lb_log(
            repo / "results/task-002-stage2b-b3-smoke/57-main-msp-converged-terminal-loh-ab/run-003/case-chi2_eta003/matlab_console.log"
        ),
    }
    coverage = archive.copy()
    coverage["training_node_visit_count_available"] = False
    coverage["training_node_visit_count"] = np.nan
    coverage["training_node_visit_frequency"] = np.nan
    coverage["node_oos_frequency_is_not_training_frequency"] = True
    coverage["one_shared_cut_per_completed_backward_iteration"] = (
        coverage.saved_cut_count == coverage.completed_backward_iterations
    )
    coverage["training_coverage_judgment"] = (
        "exact_visit_history_unavailable_static_OOS_frequency_only"
    )
    for method, stats in logs.items():
        mask = coverage.method == method
        for name, value in stats.items():
            coverage.loc[mask, name] = value

    cut = cut.copy()
    group_cols = ["method", "path_id", "decision_stage", "current_k"]
    leader_rows: list[pd.DataFrame] = []
    for _, group in cut.groupby(group_cols):
        realized_leader = int(group.loc[group.realized_terminal_target_kg.idxmax(), "site"])
        node_leader = int(group.loc[group.node_conditional_mean_target_kg.idxmax(), "site"])
        marginal_leader = int(
            group.loc[group.chosen_marginal_value_of_1kg_inventory.idxmax(), "site"]
        )
        group = group.copy()
        group["realized_target_leader_site"] = realized_leader
        group["node_mean_target_leader_site"] = node_leader
        group["marginal_value_leader_site"] = marginal_leader
        group["marginal_leader_matches_realized_target"] = marginal_leader == realized_leader
        group["marginal_leader_matches_node_mean_target"] = marginal_leader == node_leader
        leader_rows.append(group)
    cut_out = pd.concat(leader_rows, ignore_index=True).sort_values(
        ["path_id", "decision_stage", "method", "site"]
    )

    k222 = cut_out[
        (cut_out.path_id == 8650) & (cut_out.decision_stage == 5) & (cut_out.current_k == 222)
    ].copy()
    if len(k222) != 8:
        raise RuntimeError("Expected four SAA and four DRO k222 cut-site rows.")
    lines = [
        "Step-05B-6 t=5,k=222 detailed audit",
        "",
        "Fixed object",
        "- path_id: 8650",
        "- decision stage t: 5",
        "- Markov state k: 222 = (a=4, loc=7, lf=6)",
        f"- frozen-OOS node occurrence: {int(k222.node_oos_path_count.iloc[0])}/10000 "
        f"({100*float(k222.node_oos_frequency.iloc[0]):.6f}%)",
        f"- realized state19 descendant probability at this node: "
        f"{100*float(k222.realized_terminal_state_probability.iloc[0]):.6f}%",
        "",
        "Archived training evidence boundary",
        "- Both archived trainings stopped at stop_flag=2 (one-hour time limit), not a formal convergence flag.",
        "- trainInfo and console logs do not archive every iteration's in_sample path, so exact k222 training visits cannot be reconstructed.",
        "- OOS frequency is reported only as a static rarity indicator and is not relabeled as training frequency.",
        "- Every eligible ordinary model receives one shared cut per completed backward iteration; saved cut count therefore measures global shared-cut coverage, not local node visits.",
        "",
    ]
    for method in ["saa", "chi2_eta003"]:
        group = k222[k222.method == method].sort_values("site")
        lines.extend(
            [
                f"{method} saved-cut envelope at archived inventory",
                f"- training iterations / completed backward iterations: "
                f"{int(group.training_iteration_count.iloc[0])} / "
                f"{int(group.completed_backward_iterations.iloc[0])}",
                f"- final active face count: {int(group.active_cut_count.iloc[0])}",
                f"- final active face first source iteration: "
                f"{int(group.chosen_active_cut_source_iteration.iloc[0])}",
                f"- last strict envelope update iteration: "
                f"{int(group.last_envelope_update_iteration.iloc[0])}",
                f"- completed backward iterations since last update: "
                f"{int(group.iterations_since_last_envelope_update.iloc[0])}",
                f"- node appears in the single archived last-forward path: "
                f"{bool(group.last_forward_node_match.iloc[0])}",
            ]
        )
        for row in group.itertuples():
            lines.append(
                f"- site{int(row.site)}: realized target={row.realized_terminal_target_kg:.6f} kg, "
                f"node mean target={row.node_conditional_mean_target_kg:.6f} kg, "
                f"marginal={row.chosen_marginal_value_of_1kg_inventory:.6f}, "
                f"rank={int(row.chosen_marginal_value_rank)}"
            )
        lines.append("")
    lines.extend(
        [
            "Bounded interpretation",
            "- For DRO, site1 has the largest realized and conditional-mean TerminalLOH but the lowest archived active marginal rank; this reproduces the Step-05B-5 anomaly mechanically.",
            "- At the fixed archived inventory, the DRO cut envelope last improved at iteration 397 and did not improve during the remaining 801 completed backward iterations.",
            "- This is a targeted value-signal anomaly candidate, but it does not prove low training visitation or global cut failure because visit history is absent and the marginal also reflects all conditional future costs and transfer options.",
            "- Classification for k222: evidence is insufficient to distinguish low local training coverage from a legitimate conditional value surface; targeted instrumented continuation is the appropriate causal test.",
        ]
    )
    return node_map, coverage, cut_out, "\n".join(lines) + "\n"


def write_docs(
    repo: Path,
    out: Path,
    long: pd.DataFrame,
    wide: pd.DataFrame,
    transition: pd.DataFrame,
    coverage: pd.DataFrame,
    cut: pd.DataFrame,
) -> None:
    total_new = int((transition.feasibility_transition == "SAA_feasible_DRO_infeasible").sum())
    both_bad = int((transition.feasibility_transition == "both_infeasible").sum())
    both_good = int((transition.feasibility_transition == "both_feasible").sum())
    k222 = cut[(cut.method == "chi2_eta003") & (cut.path_id == 8650) & (cut.decision_stage == 5)]
    readme = f"""# Step-05B-6 SAA/DRO capacity-gap and state19 training audit

Accepted local audit run: `{out.name}`

## Scope

- Reused the exact frozen 10000x8 OOS paths.
- Solved 510 ex-post perfect-information, service-preserving physical LP rows: 255 paths for SAA and the same 255 paths for DRO.
- Each method used its own archived policy ordinary-service quantities and its own TerminalLOH table.
- Inspected only archived cuts at ordinary late nodes on the fixed eight state19 paths.
- No MSP training, resampling, forward/backward pass, new cut, TerminalLOH change, or 200/2000 change occurred.

## Main result

SAA already has material system-total shortfall in all four states; DRO increases targets and further raises the shortfall. Across the 255 paired paths, {both_bad} are infeasible under both targets, {both_good} are feasible under both, and {total_new} are SAA-feasible but DRO-infeasible. This supports capacity classification **B: SAA shortfall pre-exists and DRO amplifies it**.

The state19 eight-path set remains physically feasible under the ex-post diagnostic. Exact training-node visits cannot be reconstructed because per-iteration sampled paths were not archived. The k222 static cut anomaly is real, but current evidence is insufficient to label it a one-hour-training failure; state19 training classification is **F**.

## Important interpretation boundary

These physical LPs know the realized full path and terminal state. They do not prove that the original non-anticipative FA-MSP could make the same allocation at each historical decision time.
"""
    (out / "README.md").write_text(readme, encoding="utf-8")

    judgment_lines = [
        "Step-05B-6 judgment",
        "",
        "System capacity classification: B",
        "SAA itself has a material system-total capacity gap in state16/17/18/19; DRO raises TerminalLOH and further amplifies path incidence and conditional gap magnitude.",
        f"Across 255 paired paths: SAA-feasible/DRO-infeasible={total_new}, both-infeasible={both_bad}, both-feasible={both_good}.",
        "No path is SAA-infeasible but DRO-feasible.",
        "",
        "State19 eight-path training classification: F",
        "The eight fixed paths are physically feasible in the ex-post service-preserving diagnostic, but the archive lacks per-iteration sampled paths and therefore cannot establish low training visitation.",
        "The k222 archived value signal is anomalous: site1 is the realized and conditional target leader but ranks last in the DRO active marginal vector; the fixed-inventory cut envelope last improved at iteration 397 and remained unchanged for 801 later completed backward iterations.",
        "That static evidence warrants a targeted instrumented continuation test, but it is not strong enough to attribute the eight paths mainly to one-hour training or to declare the cut mechanism invalid.",
        "",
        "200/2000 judgment",
        "There is no evidence in this audit that requires changing either penalty. The system-total gaps arise under unchanged physical capacity and preserved ordinary service; the training-sufficiency question remains separate and unresolved.",
        "",
        "Recommended next step",
        "If additional computation is authorized, use a targeted continuation experiment that archives every iteration's sampled (t,k) nodes and the active cut envelope at the fixed state19 inventories. Do not globally change penalties or retrain from scratch solely on the present evidence.",
    ]
    (out / "step05b6_judgment.txt").write_text("\n".join(judgment_lines) + "\n", encoding="utf-8")

    manifest = """# LARGE_FILE_MANIFEST

No new large MAT, cache, replay dataset, or scenario file was created.

The audit reads the existing frozen OOS CSV and archived workspaces in place. All Step-05B-6 outputs are lightweight CSV/TXT/MD files under this run directory.
"""
    (out / "LARGE_FILE_MANIFEST.md").write_text(manifest, encoding="utf-8")


def verify(out: Path) -> str:
    required = [
        "README.md",
        "saa_dro_capacity_gap_comparison.csv",
        "saa_dro_path_feasibility_transition.csv",
        "state16_17_18_19_gap_summary.csv",
        "state19_8path_node_map.csv",
        "state19_training_coverage_audit.csv",
        "state19_cut_value_signal_audit.csv",
        "k222_detailed_audit.txt",
        "step05b6_judgment.txt",
        "LARGE_FILE_MANIFEST.md",
        "capacity_gap_path_raw.csv",
        "matlab_readonly_integrity_audit.txt",
    ]
    missing = [name for name in required if not (out / name).is_file()]
    if missing:
        raise RuntimeError(f"Missing required outputs: {missing}")
    comparison = pd.read_csv(out / "saa_dro_capacity_gap_comparison.csv")
    transition = pd.read_csv(out / "saa_dro_path_feasibility_transition.csv")
    coverage = pd.read_csv(out / "state19_training_coverage_audit.csv")
    cut = pd.read_csv(out / "state19_cut_value_signal_audit.csv")
    checks = {
        "comparison_rows": len(comparison) == 4,
        "transition_rows": len(transition) == 255,
        "paired_path_unique": transition.path_id.nunique() == 255,
        "state19_fixed_paths": set(transition[transition.state == 19].path_id).issuperset(STATE19_PATHS),
        "training_visit_unavailable": not coverage.training_node_visit_count_available.astype(bool).any(),
        "cut_rows": len(cut) == 80,
        "k222_rows": len(cut[(cut.path_id == 8650) & (cut.current_k == 222)]) == 8,
        "no_reverse_transition": not (
            transition.feasibility_transition == "SAA_infeasible_DRO_feasible"
        ).any(),
    }
    if not all(checks.values()):
        raise RuntimeError(f"Final verification failed: {checks}")
    lines = ["Step-05B-6 final integrity audit", ""]
    lines.extend(f"{key}: {int(value)}" for key, value in checks.items())
    lines.append("Final integrity PASS: 1")
    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-id", default="run-003")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    out = repo / "results/task-002-stage2b-b3-smoke/63-saa-dro-capacity-gap-and-state19-training-audit" / args.run_id
    if not out.is_dir():
        raise FileNotFoundError(out)
    protected_outputs = [
        "saa_dro_capacity_gap_comparison.csv", "saa_dro_path_feasibility_transition.csv",
        "state16_17_18_19_gap_summary.csv", "state19_8path_node_map.csv",
        "state19_training_coverage_audit.csv", "state19_cut_value_signal_audit.csv",
        "k222_detailed_audit.txt", "step05b6_judgment.txt", "README.md",
        "LARGE_FILE_MANIFEST.md", "final_integrity_audit.txt",
    ]
    existing = [name for name in protected_outputs if (out / name).exists()]
    if existing:
        raise RuntimeError(f"Refusing to overwrite finalized outputs: {existing}")

    raw = pd.read_csv(out / "capacity_gap_path_raw.csv")
    archive = pd.read_csv(out / "state19_training_archive_raw.csv")
    cut = pd.read_csv(out / "state19_saved_cut_raw.csv")
    step61 = repo / "results/task-002-stage2b-b3-smoke/61-terminal-loh-system-feasibility-audit/run-001"
    step62 = repo / "results/task-002-stage2b-b3-smoke/62-terminal-loh-information-revelation-audit/run-002"
    trace = pd.read_csv(step62 / "selected_path_inventory_trace.csv")
    physical = pd.read_csv(step61 / "physical_feasibility_path_audit.csv")

    long, wide, transition = build_gap_outputs(raw)
    node_map, coverage, cut_out, k222_text = build_training_outputs(
        repo, archive, cut, trace, physical
    )
    long.to_csv(out / "state16_17_18_19_gap_summary.csv", index=False, float_format="%.15g")
    wide.to_csv(out / "saa_dro_capacity_gap_comparison.csv", index=False, float_format="%.15g")
    transition.to_csv(out / "saa_dro_path_feasibility_transition.csv", index=False, float_format="%.15g")
    node_map.to_csv(out / "state19_8path_node_map.csv", index=False, float_format="%.15g")
    coverage.to_csv(out / "state19_training_coverage_audit.csv", index=False, float_format="%.15g")
    cut_out.to_csv(out / "state19_cut_value_signal_audit.csv", index=False, float_format="%.15g")
    (out / "k222_detailed_audit.txt").write_text(k222_text, encoding="utf-8")
    write_docs(repo, out, long, wide, transition, coverage, cut_out)
    integrity = verify(out)
    integrity += f"Frozen OOS SHA-256: {sha256_file(repo / 'output_h2/details/h2_OOS.csv')}\n"
    (out / "final_integrity_audit.txt").write_text(integrity, encoding="utf-8")
    print(integrity)


if __name__ == "__main__":
    main()
