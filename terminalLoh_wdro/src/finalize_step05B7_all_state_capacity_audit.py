"""Finalize the read-only Step-05B-7 all-state capacity-gap audit."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path

import numpy as np
import pandas as pd


FOCUS = [16, 17, 18, 19]
TOL = 1.0e-7


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def method_state_summary(frame: pd.DataFrame) -> pd.DataFrame:
    rows: list[dict[str, object]] = []
    for (method, state), group in frame.groupby(["method", "state_id"]):
        gaps = group.system_capacity_gap_kg.astype(float)
        positive = gaps[gaps > TOL]
        rows.append(
            {
                "method": method,
                "state": int(state),
                "a": int(group.a.iloc[0]),
                "loc": int(group["loc"].iloc[0]),
                "lf": int(group.lf.iloc[0]),
                "oos_count": int(len(group)),
                "terminal_loh_total_target_kg": float(group.terminal_loh_total_target_kg.mean()),
                "actual_final_inventory_total_mean_kg": float(group.actual_final_inventory_total_kg.mean()),
                "actual_station_gap_total_mean_kg": float(group.actual_station_gap_total_kg.mean()),
                "max_feasible_terminal_inventory_total_mean_kg": float(
                    group.max_feasible_terminal_inventory_total_kg.mean()
                ),
                "capacity_headroom_mean_kg": float(group.capacity_headroom_kg.mean()),
                "infeasible_path_count": int((gaps > TOL).sum()),
                "infeasible_path_share": float((gaps > TOL).mean()),
                "unconditional_mean_capacity_gap_kg": float(gaps.mean()),
                "conditional_mean_capacity_gap_kg": float(positive.mean()) if len(positive) else 0.0,
                "conditional_median_capacity_gap_kg": float(positive.median()) if len(positive) else 0.0,
                "conditional_q95_capacity_gap_kg": float(positive.quantile(0.95)) if len(positive) else 0.0,
                "conditional_max_capacity_gap_kg": float(positive.max()) if len(positive) else 0.0,
                "initial_inventory_total_mean_kg": float(group.initial_inventory_total_kg.mean()),
                "inventory_entering_last_preterminal_stage_mean_kg": float(
                    group.inventory_entering_last_preterminal_stage_kg.mean()
                ),
                "cumulative_normal_h2_service_mean_kg": float(
                    group.cumulative_normal_h2_service_kg.mean()
                ),
                "cumulative_production_mean_kg": float(group.cumulative_production_kg.mean()),
                "cumulative_available_production_capacity_mean_kg": float(
                    group.cumulative_available_production_capacity_kg.mean()
                ),
                "path_production_utilization_mean": float(group.path_production_utilization.mean()),
                "path_storage_utilization_mean": float(group.path_mean_storage_utilization.mean()),
                "path_htt_utilization_mean": float(group.path_mean_htt_utilization.mean()),
            }
        )
    return pd.DataFrame(rows).sort_values(["state", "method"])


def build_paired_paths(raw: pd.DataFrame) -> pd.DataFrame:
    keys = ["path_id", "state_id", "a", "loc", "lf"]
    fields = [
        "terminal_loh_total_target_kg",
        "actual_final_inventory_total_kg",
        "actual_station_gap_total_kg",
        "max_feasible_terminal_inventory_total_kg",
        "system_capacity_gap_kg",
        "capacity_headroom_kg",
        "system_total_sufficient",
        "cumulative_normal_h2_service_kg",
        "cumulative_production_kg",
        "cumulative_available_production_capacity_kg",
    ]
    left = raw[raw.method == "saa"][keys + fields].copy()
    right = raw[raw.method == "chi2_eta003"][keys + fields].copy()
    paired = left.merge(right, on=keys, suffixes=("_saa", "_dro"), validate="one_to_one")
    if len(paired) != 6053:
        raise RuntimeError("Expected 6053 paired terminal-hit paths.")
    saa_feasible = paired.system_total_sufficient_saa.astype(int) == 1
    dro_feasible = paired.system_total_sufficient_dro.astype(int) == 1
    paired["feasibility_class"] = np.select(
        [saa_feasible & dro_feasible, saa_feasible & ~dro_feasible,
         ~saa_feasible & ~dro_feasible, ~saa_feasible & dro_feasible],
        ["A_both_feasible", "B_SAA_feasible_DRO_infeasible",
         "C_both_infeasible", "D_SAA_infeasible_DRO_feasible"],
        default="ERROR",
    )
    paired["delta_target_kg"] = (
        paired.terminal_loh_total_target_kg_dro - paired.terminal_loh_total_target_kg_saa
    )
    paired["delta_actual_inventory_kg"] = (
        paired.actual_final_inventory_total_kg_dro - paired.actual_final_inventory_total_kg_saa
    )
    paired["delta_max_feasible_inventory_kg"] = (
        paired.max_feasible_terminal_inventory_total_kg_dro
        - paired.max_feasible_terminal_inventory_total_kg_saa
    )
    paired["delta_capacity_gap_kg"] = (
        paired.system_capacity_gap_kg_dro - paired.system_capacity_gap_kg_saa
    )
    paired["saa_gap_greater_than_dro"] = (
        paired.system_capacity_gap_kg_saa > paired.system_capacity_gap_kg_dro + TOL
    )
    paired["reverse_feasibility_flag"] = paired.feasibility_class.eq(
        "D_SAA_infeasible_DRO_feasible"
    )
    return paired.sort_values("path_id")


def build_wide_state(summary: pd.DataFrame, paired: pd.DataFrame) -> pd.DataFrame:
    rows: list[dict[str, object]] = []
    for state in sorted(summary.state.unique()):
        saa = summary[(summary.state == state) & (summary.method == "saa")].iloc[0]
        dro = summary[(summary.state == state) & (summary.method == "chi2_eta003")].iloc[0]
        paths = paired[paired.state_id == state]
        rows.append(
            {
                "state": int(state), "a": int(saa.a), "loc": int(saa["loc"]), "lf": int(saa.lf),
                "oos_count": int(saa.oos_count),
                "saa_infeasible_path_count": int(saa.infeasible_path_count),
                "dro_infeasible_path_count": int(dro.infeasible_path_count),
                "saa_infeasible_share": float(saa.infeasible_path_share),
                "dro_infeasible_share": float(dro.infeasible_path_share),
                "saa_conditional_mean_capacity_gap_kg": float(saa.conditional_mean_capacity_gap_kg),
                "dro_conditional_mean_capacity_gap_kg": float(dro.conditional_mean_capacity_gap_kg),
                "saa_unconditional_mean_capacity_gap_kg": float(saa.unconditional_mean_capacity_gap_kg),
                "dro_unconditional_mean_capacity_gap_kg": float(dro.unconditional_mean_capacity_gap_kg),
                "saa_actual_final_inventory_mean_kg": float(saa.actual_final_inventory_total_mean_kg),
                "dro_actual_final_inventory_mean_kg": float(dro.actual_final_inventory_total_mean_kg),
                "delta_actual_inventory_kg": float(
                    dro.actual_final_inventory_total_mean_kg - saa.actual_final_inventory_total_mean_kg
                ),
                "saa_target_total_kg": float(saa.terminal_loh_total_target_kg),
                "dro_target_total_kg": float(dro.terminal_loh_total_target_kg),
                "delta_target_kg": float(dro.terminal_loh_total_target_kg - saa.terminal_loh_total_target_kg),
                "saa_max_feasible_inventory_mean_kg": float(
                    saa.max_feasible_terminal_inventory_total_mean_kg
                ),
                "dro_max_feasible_inventory_mean_kg": float(
                    dro.max_feasible_terminal_inventory_total_mean_kg
                ),
                "delta_max_feasible_inventory_kg": float(
                    dro.max_feasible_terminal_inventory_total_mean_kg
                    - saa.max_feasible_terminal_inventory_total_mean_kg
                ),
                "delta_unconditional_capacity_gap_kg": float(
                    dro.unconditional_mean_capacity_gap_kg
                    - saa.unconditional_mean_capacity_gap_kg
                ),
                "saa_gap_greater_than_dro_path_count": int(paths.saa_gap_greater_than_dro.sum()),
                "saa_infeasible_dro_feasible_path_count": int(paths.reverse_feasibility_flag.sum()),
            }
        )
    return pd.DataFrame(rows).sort_values("state")


def build_focus_table(wide: pd.DataFrame) -> pd.DataFrame:
    focus = wide[wide.state.isin(FOCUS)].copy()
    return focus[
        [
            "state", "saa_target_total_kg", "dro_target_total_kg", "delta_target_kg",
            "saa_actual_final_inventory_mean_kg", "dro_actual_final_inventory_mean_kg",
            "delta_actual_inventory_kg", "saa_max_feasible_inventory_mean_kg",
            "dro_max_feasible_inventory_mean_kg", "delta_max_feasible_inventory_kg",
            "saa_unconditional_mean_capacity_gap_kg",
            "dro_unconditional_mean_capacity_gap_kg",
            "delta_unconditional_capacity_gap_kg",
        ]
    ]


def build_resource_output(resource: pd.DataFrame, reached: set[int]) -> pd.DataFrame:
    out = resource[resource.state_id.isin(reached) & (resource.observation_count > 0)].copy()
    out = out.rename(columns={"state_id": "state"})
    return out.sort_values(["state", "method", "resource"])


def attach_resource_and_ranks(
    repo: Path, wide: pd.DataFrame, summary: pd.DataFrame, resource_out: pd.DataFrame
) -> tuple[pd.DataFrame, pd.DataFrame]:
    saa_table = pd.read_csv(
        repo / "results/task-002-stage2b-b3-smoke/53-35state-saa-vs-eta003-terminal-loh/run-024/terminal_loh_table_saa.csv"
    )
    dro_table = pd.read_csv(
        repo / "results/task-002-stage2b-b3-smoke/53-35state-saa-vs-eta003-terminal-loh/run-024/terminal_loh_table_eta_003.csv"
    )
    targets = saa_table[["state_id", "intensity", "loc", "TerminalLOH_total_kg"]].rename(
        columns={"state_id": "state", "intensity": "a", "TerminalLOH_total_kg": "saa_target_total_kg"}
    )
    targets["dro_target_total_kg"] = dro_table.TerminalLOH_total_kg
    targets["delta_target_kg"] = targets.dro_target_total_kg - targets.saa_target_total_kg
    targets["saa_target_rank_desc_35"] = targets.saa_target_total_kg.rank(
        method="min", ascending=False
    ).astype(int)
    targets["dro_target_rank_desc_35"] = targets.dro_target_total_kg.rank(
        method="min", ascending=False
    ).astype(int)
    target_headroom = targets.merge(wide, on=["state", "a", "loc"], how="left", suffixes=("", "_reached"))
    target_headroom["oos_reached"] = target_headroom.oos_count.fillna(0).astype(int) > 0
    target_headroom["saa_headroom_mean_kg"] = (
        target_headroom.saa_max_feasible_inventory_mean_kg - target_headroom.saa_target_total_kg
    )
    target_headroom["dro_headroom_mean_kg"] = (
        target_headroom.dro_max_feasible_inventory_mean_kg - target_headroom.dro_target_total_kg
    )
    reached_mask = target_headroom.oos_reached
    target_headroom.loc[reached_mask, "saa_headroom_rank_ascending_reached"] = (
        target_headroom.loc[reached_mask, "saa_headroom_mean_kg"].rank(method="min", ascending=True)
    )
    target_headroom.loc[reached_mask, "dro_headroom_rank_ascending_reached"] = (
        target_headroom.loc[reached_mask, "dro_headroom_mean_kg"].rank(method="min", ascending=True)
    )

    driver = wide.copy()
    for method in ["saa", "chi2_eta003"]:
        prefix = "saa" if method == "saa" else "dro"
        sub = summary[summary.method == method].copy()
        cols = [
            "state", "inventory_entering_last_preterminal_stage_mean_kg",
            "cumulative_normal_h2_service_mean_kg", "cumulative_production_mean_kg",
            "cumulative_available_production_capacity_mean_kg", "initial_inventory_total_mean_kg",
        ]
        sub = sub[cols].rename(columns={c: f"{prefix}_{c}" for c in cols if c != "state"})
        driver = driver.merge(sub, on="state", validate="one_to_one")
        for resource_name, short in [
            ("electrolyzer_production", "production"), ("storage", "storage"), ("htt", "htt")
        ]:
            res = resource_out[(resource_out.method == method) & (resource_out.resource == resource_name)][
                ["state", "mean_utilization", "q95_utilization", "util_ge99_share"]
            ].rename(columns={
                "mean_utilization": f"{prefix}_{short}_mean_utilization",
                "q95_utilization": f"{prefix}_{short}_q95_utilization",
                "util_ge99_share": f"{prefix}_{short}_util_ge99_share",
            })
            driver = driver.merge(res, on="state", validate="one_to_one")
    driver = driver.merge(
        targets[["state", "saa_target_rank_desc_35", "dro_target_rank_desc_35"]],
        on="state", validate="one_to_one"
    )
    driver["delta_normal_service_kg"] = (
        driver.dro_cumulative_normal_h2_service_mean_kg
        - driver.saa_cumulative_normal_h2_service_mean_kg
    )
    driver["delta_production_kg"] = (
        driver.dro_cumulative_production_mean_kg - driver.saa_cumulative_production_mean_kg
    )
    return target_headroom.sort_values("state"), driver.sort_values("state")


def top_state_text(wide: pd.DataFrame) -> dict[str, pd.Series]:
    return {
        "saa_largest_conditional": wide.loc[wide.saa_conditional_mean_capacity_gap_kg.idxmax()],
        "dro_largest_conditional": wide.loc[wide.dro_conditional_mean_capacity_gap_kg.idxmax()],
        "largest_gap_increase": wide.loc[wide.delta_unconditional_capacity_gap_kg.idxmax()],
        "largest_gap_decrease": wide.loc[wide.delta_unconditional_capacity_gap_kg.idxmin()],
        "largest_actual_increase": wide.loc[wide.delta_actual_inventory_kg.idxmax()],
    }


def write_text_outputs(
    out: Path, focus: pd.DataFrame, wide: pd.DataFrame, driver: pd.DataFrame,
    paired: pd.DataFrame, reverse: pd.DataFrame, raw_file: Path, resource_file: Path
) -> None:
    d = driver.set_index("state")
    lines = ["Step-05B-7 state16/17/18/19 driver audit", ""]
    for row in focus.itertuples():
        drv = d.loc[row.state]
        lines.extend([
            f"State {row.state} (a={int(drv.a)}, loc={int(drv['loc'])}, lf={int(drv.lf)})",
            f"- Target: SAA {row.saa_target_total_kg:.6f}, DRO {row.dro_target_total_kg:.6f}, delta {row.delta_target_kg:+.6f} kg.",
            f"- Actual final inventory: SAA {row.saa_actual_final_inventory_mean_kg:.6f}, DRO {row.dro_actual_final_inventory_mean_kg:.6f}, delta {row.delta_actual_inventory_kg:+.6f} kg.",
            f"- Maximum feasible inventory: SAA {row.saa_max_feasible_inventory_mean_kg:.6f}, DRO {row.dro_max_feasible_inventory_mean_kg:.6f}, delta {row.delta_max_feasible_inventory_kg:+.6f} kg.",
            f"- Unconditional capacity gap: SAA {row.saa_unconditional_mean_capacity_gap_kg:.6f}, DRO {row.dro_unconditional_mean_capacity_gap_kg:.6f}, delta {row.delta_unconditional_capacity_gap_kg:+.6f} kg.",
            f"- Target ranks among 35 states: SAA {int(drv.saa_target_rank_desc_35)}, DRO {int(drv.dro_target_rank_desc_35)}.",
            f"- Normal service delta DRO-SAA: {drv.delta_normal_service_kg:+.6f} kg; production delta: {drv.delta_production_kg:+.6f} kg.",
            f"- DRO utilization: production mean {100*drv.dro_production_mean_utilization:.3f}% (>=99% stages {100*drv.dro_production_util_ge99_share:.3f}%), storage mean {100*drv.dro_storage_mean_utilization:.3f}%, HTT mean {100*drv.dro_htt_mean_utilization:.3f}%.",
            "",
        ])
    lines.extend([
        "Bounded cause interpretation",
        "- All four focus states share intensity index a=4 and locations 2 through 5; this is a mapping commonality, not by itself a causal mechanism.",
        "- Their TerminalLOH totals rank 15th through 19th among 35 states rather than being the global maxima. Their targets nevertheless exceed the pathwise achievable terminal reserve on many paths while electrolyzer production is already near its available capacity.",
        "- The full-state scan shows that states15, 22, and 33 have still larger conditional mean gaps, but they have only 34, 9, and 1 reached OOS paths. State16-19 are prominent partly because they combine persistent shortfall with materially larger path counts.",
        "- DRO actual inventory and maximum feasible inventory both increase in every focus state, but by much less than the target increase. The larger gap is therefore target growth outrunning achievable reserve growth, not inventory falling.",
        "- Ordinary-service differences and production changes affect the exact maximum feasible inventory, but the comparison is descriptive and does not prove a single causal driver.",
    ])
    (out / "state16_19_driver_audit.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")

    tops = top_state_text(wide)
    actual_pos = int((wide.delta_actual_inventory_kg > TOL).sum())
    actual_zero = int((wide.delta_actual_inventory_kg.abs() <= TOL).sum())
    actual_neg = int((wide.delta_actual_inventory_kg < -TOL).sum())
    target_pos = int((wide.delta_target_kg > TOL).sum())
    target_zero = int((wide.delta_target_kg.abs() <= TOL).sum())
    classes = paired.feasibility_class.value_counts()
    reverse_lines = []
    for row in reverse.sort_values("delta_capacity_gap_kg").itertuples():
        reverse_lines.append(
            f"- path {int(row.path_id)}, state{int(row.state_id)}, {row.feasibility_class}: "
            f"target delta {row.delta_target_kg:+.6f} kg, maximum-feasible-inventory delta "
            f"{row.delta_max_feasible_inventory_kg:+.6f} kg, capacity-gap delta "
            f"{row.delta_capacity_gap_kg:+.6f} kg, ordinary-service delta "
            f"{row.cumulative_normal_h2_service_kg_dro-row.cumulative_normal_h2_service_kg_saa:+.6f} kg, "
            f"production delta {row.cumulative_production_kg_dro-row.cumulative_production_kg_saa:+.6f} kg."
        )
    reverse_text = "\n".join(reverse_lines) if reverse_lines else "- No reverse path was found."
    negative_state_changes = int((wide.delta_unconditional_capacity_gap_kg < -TOL).sum())
    judgment = f"""Step-05B-7 judgment

Mechanical scope
- 6053 common terminal-hit OOS paths, 31 reached terminal states, two archived policies.
- 12106/12106 service-preserving maximum-terminal-inventory LPs are OPTIMAL.
- The diagnostic is ex-post perfect-information physical feasibility, not non-anticipative policy attainability.

Main focus-state answer
- State16/17/18/19 DRO actual inventory changes are {focus.iloc[0].delta_actual_inventory_kg:+.6f}, {focus.iloc[1].delta_actual_inventory_kg:+.6f}, {focus.iloc[2].delta_actual_inventory_kg:+.6f}, and {focus.iloc[3].delta_actual_inventory_kg:+.6f} kg.
- Actual inventory increases in all four states, and maximum feasible inventory also increases. Capacity gaps grow because targets rise much faster than either actual or maximum feasible inventory.

All-state direction
- Reached states with positive/zero/negative DRO actual-inventory change: {actual_pos}/{actual_zero}/{actual_neg} of {len(wide)}.
- Reached states with positive/zero target change: {target_pos}/{target_zero} of {len(wide)}.
- Path feasibility classes: A both feasible={int(classes.get('A_both_feasible',0))}, B SAA feasible/DRO infeasible={int(classes.get('B_SAA_feasible_DRO_infeasible',0))}, C both infeasible={int(classes.get('C_both_infeasible',0))}, D SAA infeasible/DRO feasible={int(classes.get('D_SAA_infeasible_DRO_feasible',0))}.
- Paths with SAA capacity gap greater than DRO: {int(paired.saa_gap_greater_than_dro.sum())}.
- Reverse-gap output rows: {len(reverse)}.

Reverse cases and mechanism
{reverse_text}
- In the observed reverse cases, DRO preserves substantially more hydrogen by serving less ordinary H2 while cumulative production is unchanged. The maximum feasible inventory therefore rises more than the TerminalLOH target, reducing the system gap. This is a path-specific service/reserve tradeoff, not evidence that the DRO target is lower.

Ranked states
- Largest SAA conditional mean gap: state{int(tops['saa_largest_conditional'].state)} ({tops['saa_largest_conditional'].saa_conditional_mean_capacity_gap_kg:.6f} kg).
- Largest DRO conditional mean gap: state{int(tops['dro_largest_conditional'].state)} ({tops['dro_largest_conditional'].dro_conditional_mean_capacity_gap_kg:.6f} kg).
- Largest unconditional gap increase: state{int(tops['largest_gap_increase'].state)} ({tops['largest_gap_increase'].delta_unconditional_capacity_gap_kg:+.6f} kg).
- State-level mean gap decreases: {negative_state_changes}; minimum state-level change is state{int(tops['largest_gap_decrease'].state)} ({tops['largest_gap_decrease'].delta_unconditional_capacity_gap_kg:+.6f} kg).
- Largest actual inventory increase: state{int(tops['largest_actual_increase'].state)} ({tops['largest_actual_increase'].delta_actual_inventory_kg:+.6f} kg).

Bounded interpretation
- Across reached states, DRO generally changes both the target and the policy's actual reserve. It is not a pure target-only change, but target growth is usually larger than reserve growth.
- No evidence from this audit justifies changing 200 or 2000.
- State19 retains the Step-05B-6 training-sufficiency classification F. This all-state audit adds no direct training-history evidence, so further state19 training audit is optional and should only be an instrumented causal test, not a prerequisite for the present capacity conclusion.
"""
    (out / "step05b7_judgment.txt").write_text(judgment, encoding="utf-8")

    readme = f"""# Step-05B-7 all-state target/actual/feasible inventory audit

Accepted run: `{out.name}`

This read-only audit compares SAA and eta=0.03 DRO on the same 6053 terminal-hit paths. Each method keeps its own archived ordinary H2 service quantities and uses its own TerminalLOH target. No training, resampling, cut generation, TerminalLOH change, or 200/2000 change occurred.

The primary result is that state16/17/18/19 all have higher DRO actual inventory, but the DRO target rises faster. Across all reached states, {int(paired.saa_gap_greater_than_dro.sum())} paths have SAA capacity gap greater than DRO, including {int(paired.reverse_feasibility_flag.sum())} path that is SAA-infeasible but DRO-feasible. These exceptions are retained and explained rather than smoothed away.

The raw 12106-row LP table is retained locally for reproducibility and listed in `LARGE_FILE_MANIFEST.md`; required lightweight summaries are suitable for Git.
"""
    (out / "README.md").write_text(readme, encoding="utf-8")

    manifest = f"""# LARGE_FILE_MANIFEST

Local-only reproducibility inputs/outputs:

- `{raw_file.name}`: {raw_file.stat().st_size} bytes, SHA-256 `{sha256_file(raw_file)}`. Full 12106-row per-method/path diagnostic table; keep local and do not stage.
- `{resource_file.name}`: {resource_file.stat().st_size} bytes, SHA-256 `{sha256_file(resource_file)}`. Intermediate 210-row resource table; keep local because the finalized required resource table is committed instead.

No MAT, workspace, cache, or new OOS scenario file was created.
"""
    (out / "LARGE_FILE_MANIFEST.md").write_text(manifest, encoding="utf-8")


def verify(out: Path) -> str:
    required = [
        "README.md", "state16_19_target_actual_feasible_inventory.csv",
        "all_state_capacity_gap_summary.csv", "all_path_saa_dro_feasibility_transition.csv",
        "reverse_gap_cases.csv", "state_capacity_driver_comparison.csv",
        "state_target_rank_and_headroom.csv", "resource_utilization_by_state.csv",
        "state16_19_driver_audit.txt", "step05b7_judgment.txt", "LARGE_FILE_MANIFEST.md",
    ]
    missing = [name for name in required if not (out / name).is_file()]
    if missing:
        raise RuntimeError(f"Missing required files: {missing}")
    focus = pd.read_csv(out / required[1])
    state = pd.read_csv(out / required[2])
    paths = pd.read_csv(out / required[3])
    reverse = pd.read_csv(out / required[4])
    checks = {
        "focus_rows": len(focus) == 4,
        "state_rows": len(state) == 31,
        "path_rows": len(paths) == 6053,
        "path_ids_unique": paths.path_id.nunique() == 6053,
        "reverse_rows_match_union": len(reverse) == int(
            (paths.saa_gap_greater_than_dro.astype(bool) | paths.reverse_feasibility_flag.astype(bool)).sum()
        ),
        "reverse_gap_rows_are_strict": (
            reverse.system_capacity_gap_kg_saa > reverse.system_capacity_gap_kg_dro + TOL
        ).all(),
        "reverse_feasibility_is_subset": (
            ~reverse.reverse_feasibility_flag.astype(bool)
            | reverse.feasibility_class.eq("D_SAA_infeasible_DRO_feasible")
        ).all(),
        "focus_actual_inventory_increases": (focus.delta_actual_inventory_kg > TOL).all(),
        "focus_target_increase_exceeds_actual": (
            focus.delta_target_kg > focus.delta_actual_inventory_kg
        ).all(),
    }
    if not all(checks.values()):
        raise RuntimeError(f"Verification failed: {checks}")
    return "\n".join(
        ["Step-05B-7 final integrity audit", ""]
        + [f"{key}: {int(value)}" for key, value in checks.items()]
        + ["Final integrity PASS: 1", ""]
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-id", default="run-001")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    out = repo / "results/task-002-stage2b-b3-smoke/64-terminal-loh-all-state-capacity-gap-audit" / args.run_id
    if not out.is_dir():
        raise FileNotFoundError(out)
    finalized = [
        "README.md", "state16_19_target_actual_feasible_inventory.csv",
        "all_state_capacity_gap_summary.csv", "all_path_saa_dro_feasibility_transition.csv",
        "reverse_gap_cases.csv", "state_capacity_driver_comparison.csv",
        "state_target_rank_and_headroom.csv", "resource_utilization_by_state.csv",
        "state16_19_driver_audit.txt", "step05b7_judgment.txt", "LARGE_FILE_MANIFEST.md",
        "final_integrity_audit.txt",
    ]
    existing = [name for name in finalized if (out / name).exists()]
    if existing:
        raise RuntimeError(f"Refusing to overwrite finalized outputs: {existing}")

    raw_file = out / "all_state_path_capacity_raw.csv"
    resource_file = out / "resource_utilization_state_raw.csv"
    raw = pd.read_csv(raw_file)
    resource = pd.read_csv(resource_file)
    if len(raw) != 12106 or not (raw.lp_status == "OPTIMAL").all():
        raise RuntimeError("MATLAB path audit is incomplete.")
    summary = method_state_summary(raw)
    paired = build_paired_paths(raw)
    wide = build_wide_state(summary, paired)
    focus = build_focus_table(wide)
    resource_out = build_resource_output(resource, set(wide.state.astype(int)))
    target_headroom, driver = attach_resource_and_ranks(repo, wide, summary, resource_out)
    reverse = paired[
        paired.saa_gap_greater_than_dro | paired.reverse_feasibility_flag
    ].copy()

    focus.to_csv(out / "state16_19_target_actual_feasible_inventory.csv", index=False, float_format="%.15g")
    wide.to_csv(out / "all_state_capacity_gap_summary.csv", index=False, float_format="%.15g")
    paired.to_csv(out / "all_path_saa_dro_feasibility_transition.csv", index=False, float_format="%.15g")
    reverse.to_csv(out / "reverse_gap_cases.csv", index=False, float_format="%.15g")
    driver.to_csv(out / "state_capacity_driver_comparison.csv", index=False, float_format="%.15g")
    target_headroom.to_csv(out / "state_target_rank_and_headroom.csv", index=False, float_format="%.15g")
    resource_out.to_csv(out / "resource_utilization_by_state.csv", index=False, float_format="%.15g")
    write_text_outputs(out, focus, wide, driver, paired, reverse, raw_file, resource_file)
    integrity = verify(out)
    integrity += f"Frozen OOS SHA-256: {sha256_file(repo / 'output_h2/details/h2_OOS.csv')}\n"
    (out / "final_integrity_audit.txt").write_text(integrity, encoding="utf-8")
    print(integrity)


if __name__ == "__main__":
    main()
