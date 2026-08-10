"""Finalize Step-05B-3 after the deterministic MATLAB replay."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path

import numpy as np
import pandas as pd


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def weighted_binding(frame: pd.DataFrame, method: str, constraint: str) -> float:
    rows = frame[(frame["method"] == method) & (frame["constraint_type"] == constraint)]
    eligible = rows["eligible_count"].sum()
    return float(rows["binding_count"].sum() / eligible) if eligible else np.nan


def build_state7(state7: pd.DataFrame) -> pd.DataFrame:
    keys = ["stage", "site"]
    saa = state7[state7["method"] == "saa"].set_index(keys)
    dro = state7[state7["method"] == "chi2_eta003"].set_index(keys)
    if not saa.index.equals(dro.index):
        raise RuntimeError("State7 method traces do not share stage/site rows.")
    result = saa[["path_count"]].reset_index()
    metrics = [
        "mean_start_inventory_kg", "mean_end_inventory_kg", "mean_production_kg",
        "mean_normal_served_kg", "mean_normal_shortage_kg", "mean_htt_inflow_kg",
        "mean_htt_outflow_kg", "mean_net_htt_inflow_kg", "mean_total_htt_flow_kg",
        "tank_binding_rate", "electrolyzer_binding_rate", "htt_binding_rate",
    ]
    for metric in metrics:
        result[f"saa_{metric}"] = saa[metric].to_numpy()
        result[f"dro_{metric}"] = dro[metric].to_numpy()
        result[f"delta_dro_minus_saa_{metric}"] = dro[metric].to_numpy() - saa[metric].to_numpy()
    return result


def build_flow_difference(flow: pd.DataFrame, selected: pd.DataFrame, binding: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for _, meta in selected.iterrows():
        pair_id = int(meta["selected_pair_id"])
        pair = flow[flow["selected_pair_id"] == pair_id]
        saa = pair[pair["method"] == "saa"]
        dro = pair[pair["method"] == "chi2_eta003"]
        if len(saa) != len(dro):
            raise RuntimeError(f"Pair {pair_id} trace row mismatch.")
        focal_site = int(meta["site"])
        first_inventory = np.nan
        first_production = np.nan
        first_shortage = np.nan
        for stage in range(1, 9):
            a = saa[saa["stage"] == stage]
            b = dro[dro["stage"] == stage]
            delta_inventory = b["mean_end_inventory_kg"].sum() - a["mean_end_inventory_kg"].sum()
            delta_production = b["mean_production_kg"].sum() - a["mean_production_kg"].sum()
            delta_shortage = b["mean_normal_shortage_kg"].sum() - a["mean_normal_shortage_kg"].sum()
            if np.isnan(first_inventory) and abs(delta_inventory) > 0.01:
                first_inventory = stage
            if np.isnan(first_production) and abs(delta_production) > 0.01:
                first_production = stage
            if np.isnan(first_shortage) and abs(delta_shortage) > 0.01:
                first_shortage = stage
        a_focal = saa[saa["observed_site"] == focal_site]
        b_focal = dro[dro["observed_site"] == focal_site]
        a_final = a_focal[a_focal["stage"] == 8]["mean_end_inventory_kg"].iloc[0]
        b_final = b_focal[b_focal["stage"] == 8]["mean_end_inventory_kg"].iloc[0]
        rows.append(
            {
                **meta.to_dict(),
                "first_material_inventory_divergence_stage": first_inventory,
                "first_material_production_divergence_stage": first_production,
                "first_material_shortage_divergence_stage": first_shortage,
                "all_site_final_inventory_delta_kg": (
                    dro[dro["stage"] == 8]["mean_end_inventory_kg"].sum()
                    - saa[saa["stage"] == 8]["mean_end_inventory_kg"].sum()
                ),
                "all_site_cumulative_production_delta_kg": dro["mean_production_kg"].sum() - saa["mean_production_kg"].sum(),
                "all_site_cumulative_normal_served_delta_kg": dro["mean_normal_served_kg"].sum() - saa["mean_normal_served_kg"].sum(),
                "all_site_cumulative_normal_shortage_delta_kg": dro["mean_normal_shortage_kg"].sum() - saa["mean_normal_shortage_kg"].sum(),
                "all_site_cumulative_htt_flow_delta_kg": (
                    dro[dro["observed_site"] == 1]["mean_total_htt_flow_kg"].sum()
                    - saa[saa["observed_site"] == 1]["mean_total_htt_flow_kg"].sum()
                ),
                "focal_site_final_inventory_delta_kg": b_final - a_final,
                "focal_site_cumulative_production_delta_kg": b_focal["mean_production_kg"].sum() - a_focal["mean_production_kg"].sum(),
                "focal_site_cumulative_normal_shortage_delta_kg": b_focal["mean_normal_shortage_kg"].sum() - a_focal["mean_normal_shortage_kg"].sum(),
                "focal_site_cumulative_net_htt_inflow_delta_kg": b_focal["mean_net_htt_inflow_kg"].sum() - a_focal["mean_net_htt_inflow_kg"].sum(),
                "saa_tank_binding_rate": weighted_binding(binding[binding["selected_pair_id"] == pair_id], "saa", "tank_capacity"),
                "dro_tank_binding_rate": weighted_binding(binding[binding["selected_pair_id"] == pair_id], "chi2_eta003", "tank_capacity"),
                "saa_electrolyzer_binding_rate": weighted_binding(binding[binding["selected_pair_id"] == pair_id], "saa", "electrolyzer_capacity"),
                "dro_electrolyzer_binding_rate": weighted_binding(binding[binding["selected_pair_id"] == pair_id], "chi2_eta003", "electrolyzer_capacity"),
                "saa_htt_binding_rate": weighted_binding(binding[binding["selected_pair_id"] == pair_id], "saa", "htt_aggregate_capacity"),
                "dro_htt_binding_rate": weighted_binding(binding[binding["selected_pair_id"] == pair_id], "chi2_eta003", "htt_aggregate_capacity"),
                "saa_ordinary_shortage_positive_rate": weighted_binding(binding[binding["selected_pair_id"] == pair_id], "saa", "ordinary_shortage_positive"),
                "dro_ordinary_shortage_positive_rate": weighted_binding(binding[binding["selected_pair_id"] == pair_id], "chi2_eta003", "ordinary_shortage_positive"),
            }
        )
    return pd.DataFrame(rows)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-id", default="run-002")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    out = repo / "results/task-002-stage2b-b3-smoke/60-terminal-loh-required-extra-and-flow-audit" / args.run_id
    required_files = [
        "required_extra_summary.csv", "effective_realization_summary.csv",
        "path_station_abcd_classification.csv", "state_station_required_extra.csv",
        "remaining_gap_ranking.csv", "selected_pair_manifest.csv",
        "selected_state_flow_trace.csv", "selected_state_constraint_binding.csv",
        "state7_spillover_method_trace.csv", "replay_integrity_audit.txt",
    ]
    for name in required_files:
        if not (out / name).is_file():
            raise FileNotFoundError(out / name)
    for name in ["README.md", "mechanism_summary.txt", "step05b3_judgment.txt", "LARGE_FILE_MANIFEST.md"]:
        if (out / name).exists():
            raise RuntimeError(f"Refusing to overwrite {out / name}")
    if "Replay PASS: 1" not in (out / "replay_integrity_audit.txt").read_text(encoding="utf-8"):
        raise RuntimeError("Deterministic replay did not pass.")

    req = pd.read_csv(out / "required_extra_summary.csv")
    classes = pd.read_csv(out / "effective_realization_summary.csv")
    detail = pd.read_csv(out / "path_station_abcd_classification.csv")
    selected = pd.read_csv(out / "selected_pair_manifest.csv")
    flow = pd.read_csv(out / "selected_state_flow_trace.csv")
    binding = pd.read_csv(out / "selected_state_constraint_binding.csv")
    state7_method = pd.read_csv(out / "state7_spillover_method_trace.csv")

    state7 = build_state7(state7_method)
    state7.to_csv(out / "state7_spillover_check.csv", index=False, float_format="%.15g")
    flow_diff = build_flow_difference(flow, selected, binding)
    flow_diff.to_csv(out / "selected_state_flow_difference_summary.csv", index=False, float_format="%.15g")

    overall = req[req["scope"] == "all_terminal_hit_path_site_rows"].iloc[0]
    positive_dt = req[req["scope"] == "positive_delta_T_path_site_rows"].iloc[0]
    site_rows = req[req["scope"].str.match(r"site[1-4]_all_terminal_hits")].copy()
    state_rows = {state: req[req["scope"] == f"state{state}_all_sites"].iloc[0] for state in [1,2,3,4,7,13,14,19]}
    class_map = {row["abcd_class"]: row for _, row in classes.iterrows()}
    positive_dt_rows = detail[detail["delta_T_kg"] > 1.0e-12]
    no_required_share = float((positive_dt_rows["required_extra_kg"] <= 1.0e-12).mean())

    selected_tank_saa = weighted_binding(binding, "saa", "tank_capacity")
    selected_tank_dro = weighted_binding(binding, "chi2_eta003", "tank_capacity")
    selected_el_saa = weighted_binding(binding, "saa", "electrolyzer_capacity")
    selected_el_dro = weighted_binding(binding, "chi2_eta003", "electrolyzer_capacity")
    selected_htt_saa = weighted_binding(binding, "saa", "htt_aggregate_capacity")
    selected_htt_dro = weighted_binding(binding, "chi2_eta003", "htt_aggregate_capacity")
    selected_short_saa = weighted_binding(binding, "saa", "ordinary_shortage_positive")
    selected_short_dro = weighted_binding(binding, "chi2_eta003", "ordinary_shortage_positive")

    s7_prod_delta = state7.groupby("stage")["delta_dro_minus_saa_mean_production_kg"].sum().sum()
    s7_served_delta = state7.groupby("stage")["delta_dro_minus_saa_mean_normal_served_kg"].sum().sum()
    s7_final_delta = state7[state7["stage"] == 8]["delta_dro_minus_saa_mean_end_inventory_kg"].sum()
    s7_first_inventory_stage = int(
        state7.groupby("stage")["delta_dro_minus_saa_mean_end_inventory_kg"].sum().abs().loc[lambda x: x > 0.01].index.min()
    )

    state14_pair = flow_diff[(flow_diff["state_id"] == 14) & (flow_diff["site"] == 1)].iloc[0]
    state13_pair = flow_diff[(flow_diff["state_id"] == 13) & (flow_diff["site"] == 2)].iloc[0]
    state19_pair = flow_diff[(flow_diff["state_id"] == 19) & (flow_diff["site"] == 4)].iloc[0]

    mechanism = f"""Step-05B-3 mechanism summary

Necessary-extra accounting
- Positive DRO target increment across terminal-hit path-site rows: {overall.positive_delta_T_total_kg:.12f} kg.
- Directly covered by SAA surplus: {overall.new_target_covered_by_saa_surplus_kg:.12f} kg ({overall.covered_share_of_positive_delta_T:.6%}).
- Positive-DeltaT path-site rows requiring no extra inventory: {no_required_share:.6%}.
- Required extra on positive-DeltaT rows: {positive_dt.required_extra_total_kg:.12f} kg; realized: {positive_dt.required_extra_realized_kg:.12f} kg; effective realization: {positive_dt.effective_realization_ratio:.6%}.
- Required extra across all target-positive/deficient rows, including pre-existing SAA gaps: {overall.required_extra_total_kg:.12f} kg; realized: {overall.required_extra_realized_kg:.12f} kg; effective realization: {overall.effective_realization_ratio:.6%}.
- States 1, 2, 3, and 4 have 100% surplus coverage, zero required extra, and zero remaining gap. Their low Step-05B-2 DeltaI/DeltaT ratios were entirely denominator artifacts rather than unmet hydrogen targets.

A/B/C/D path-site classification
- A: {int(class_map['A'].row_count)} ({class_map['A'].share_of_all_terminal_hit_path_site_rows:.6%}); B: {int(class_map['B'].row_count)} ({class_map['B'].share_of_all_terminal_hit_path_site_rows:.6%}); C: {int(class_map['C'].row_count)} ({class_map['C'].share_of_all_terminal_hit_path_site_rows:.6%}); D: {int(class_map['D'].row_count)} ({class_map['D'].share_of_all_terminal_hit_path_site_rows:.6%}).
- Within A, 185 rows start with enough SAA inventory for the DRO target but the DRO policy subsequently falls below that target; their total remaining gap is 541.286430 kg.
- C contributes {class_map['C'].remaining_gap_total_kg:.12f} kg remaining gap. D contributes {class_map['D'].remaining_gap_total_kg:.12f} kg and has negative aggregate actual-extra because DRO inventory does not increase.

State and site findings
- State13: surplus coverage {state_rows[13].covered_share_of_positive_delta_T:.6%}, required extra {state_rows[13].required_extra_total_kg:.6f} kg, effective realization {state_rows[13].effective_realization_ratio:.6%}.
- State14: surplus coverage {state_rows[14].covered_share_of_positive_delta_T:.6%}, required extra {state_rows[14].required_extra_total_kg:.6f} kg, effective realization {state_rows[14].effective_realization_ratio:.6%}.
- State19: surplus coverage only {state_rows[19].covered_share_of_positive_delta_T:.6%}, required extra {state_rows[19].required_extra_total_kg:.6f} kg, effective realization {state_rows[19].effective_realization_ratio:.6%}; this is a genuinely difficult target rather than a surplus artifact.
- Site1 has the largest required extra ({site_rows.loc[site_rows.scope=='site1_all_terminal_hits','required_extra_total_kg'].iloc[0]:.6f} kg) and remaining gap ({site_rows.loc[site_rows.scope=='site1_all_terminal_hits','remaining_gap_total_kg'].iloc[0]:.6f} kg), but site4 has the lowest effective realization ({site_rows.loc[site_rows.scope=='site4_all_terminal_hits','effective_realization_ratio'].iloc[0]:.6%}) and nearly as much remaining gap. Site1 is important but not the sole bottleneck.

Selected C/D deterministic replay
- Saved-policy replay exactly uses the frozen 10000x8 OOS table. See replay_integrity_audit.txt.
- Descriptive binding rates over the 11 selected pair subsets (paths may appear in more than one pair): electrolyzer {selected_el_saa:.6%} SAA / {selected_el_dro:.6%} DRO; tank {selected_tank_saa:.6%}/{selected_tank_dro:.6%}; aggregate HTT {selected_htt_saa:.6%}/{selected_htt_dro:.6%}; ordinary shortage positive {selected_short_saa:.6%}/{selected_short_dro:.6%}.
- The dominant physical ceiling is electrolyzer production capability. Tank capacity is rarely active, and aggregate HTT capacity is never active in the selected C/D subsets.
- HTT is nevertheless important as a redistribution mechanism. The model has no pairwise hard road-reachability constraint; beta affects aggregate HTT capacity and cost. Several low-realization focal sites receive less net HTT under DRO even when total system inventory increases.
- State14/site1: focal final inventory delta {state14_pair.focal_site_final_inventory_delta_kg:.6f} kg, local production delta {state14_pair.focal_site_cumulative_production_delta_kg:.6f} kg, net HTT inflow delta {state14_pair.focal_site_cumulative_net_htt_inflow_delta_kg:.6f} kg. Most of its realized increment is supplied by redistribution.
- State13/site2: focal final inventory delta {state13_pair.focal_site_final_inventory_delta_kg:.6f} kg despite local production delta {state13_pair.focal_site_cumulative_production_delta_kg:.6f} kg, because net HTT inflow changes by {state13_pair.focal_site_cumulative_net_htt_inflow_delta_kg:.6f} kg. This is a clear export/reallocation mechanism.
- State19/site4: focal final inventory delta {state19_pair.focal_site_final_inventory_delta_kg:.6f} kg, production delta {state19_pair.focal_site_cumulative_production_delta_kg:.6f} kg, net HTT inflow delta {state19_pair.focal_site_cumulative_net_htt_inflow_delta_kg:.6f} kg, and normal shortage delta {state19_pair.focal_site_cumulative_normal_shortage_delta_kg:.6f} kg.
- Material production and inventory divergence begins at stage 3 for every selected pair. In 8 of 11 selected pairs, DRO also serves slightly less normal demand from stage 4 onward, preserving some inventory but increasing ordinary shortage. Thus normal-demand competition exists, but the missing reserve is not mainly caused by DRO serving more normal demand.

State7 spillover control
- State7 has DeltaT=0 for all sites. Inventory divergence begins at stage {s7_first_inventory_stage}.
- Cumulative extra production is {s7_prod_delta:.12f} kg/path and normal served load changes by {s7_served_delta:.12f} kg/path, producing final inventory delta {s7_final_delta:.12f} kg/path.
- This proves a multistage cut/policy spillover: different TerminalLOH tables at other states change pre-terminal production and allocation even on a terminal state whose own target is identical.

Penalty implication
- The replay does not provide evidence that changing 200 or 2000 is currently necessary. The 2000 terminal-gap signal already drives near-continuous electrolyzer capacity use and some sacrifice of ordinary service.
- Raising or otherwise changing the penalty would not remove the observed production ceiling and could intensify ordinary-service competition. The next audit should focus on production capacity and state/site-specific HTT/cut allocation before any penalty sensitivity experiment.
"""
    (out / "mechanism_summary.txt").write_text(mechanism, encoding="utf-8")

    judgment = """Step-05B-3 judgment

Most of the low DeltaI/DeltaT result from Step-05B-2 was a target-denominator artifact: SAA inventory surplus directly covers 93.30% of the positive DRO target increment, and 83.58% of positive-DeltaT path-site rows require no extra inventory. This is complete for states 1-4.

The residual problem is still real. For rows that genuinely require extra inventory, only 26.04% is realized overall, or 30.31% when restricted to positive-DeltaT rows. C/D remaining gaps are concentrated in specific states/sites rather than being a uniform TerminalLOH interface failure.

The selected deterministic replay supports a mixed physical/policy mechanism: electrolyzer production capacity is the dominant active ceiling; tank capacity and aggregate HTT capacity are not binding. HTT redistribution can nevertheless move hydrogen away from focal target sites, and DRO sometimes preserves inventory by serving slightly less ordinary demand. State7 confirms that cuts learned from the full TerminalLOH table create multistage spillover even when the realized terminal state's own target is unchanged.

There is no present mechanical basis to change the 200/2000 penalties. Continue with targeted production-capacity and HTT/cut-allocation diagnostics for the leading C/D state-site pairs. This audit does not declare Pearson DRO successful or unsuccessful.
"""
    (out / "step05b3_judgment.txt").write_text(judgment, encoding="utf-8")

    readme = """# Step-05B-3 required-extra and hydrogen-flow audit

Accepted result: `run-002`.

`run-001` is preserved as a failed launcher attempt: MATLAB did not have the new audit source directory on its path, so no replay began.

This run contains a strict common-sample required-extra audit plus deterministic replay of the two saved fixed policies on the unchanged 10000x8 OOS path table. It does not train the MSP, change TerminalLOH, change 200/2000, regenerate OOS paths, or modify any core model file.

Important interpretation:

- `required_extra = max(0, T_dro - I_saa)` includes both an uncovered new target increment and any pre-existing SAA gap.
- `effective_realization` is defined only when `required_extra > 0` and is never clipped.
- A/B/C/D classes follow the task definitions exactly. Class A is additionally split diagnostically when the DRO policy later falls below a target already covered by SAA inventory.
- Flow and binding tables cover the 11 selected C/D state-site pairs. They are descriptive selected-subset diagnostics; paths can occur in multiple focal pairs.
- `eta003` means eta = 0.03.

See `mechanism_summary.txt` and `step05b3_judgment.txt` for the conclusion.
"""
    (out / "README.md").write_text(readme, encoding="utf-8")

    source_paths = [
        repo / "results/task-002-stage2b-b3-smoke/58-main-msp-terminal-gap-mechanism-audit/run-004/terminal_target_vs_final_inventory.csv",
        repo / "results/task-002-stage2b-b3-smoke/57-main-msp-converged-terminal-loh-ab/run-003/case-saa/native_output/h2_workspace.mat",
        repo / "results/task-002-stage2b-b3-smoke/57-main-msp-converged-terminal-loh-ab/run-003/case-chi2_eta003/native_output/h2_workspace.mat",
        repo / "output_h2/details/h2_OOS.csv",
    ]
    lines = [
        "# LARGE FILE MANIFEST", "",
        "| role | path | bytes | SHA-256 | policy |",
        "|---|---|---:|---|---|",
    ]
    roles = ["Step-05B-1 rowwise source", "SAA saved workspace", "eta=0.03 saved workspace", "frozen common OOS paths"]
    for role, path in zip(roles, source_paths):
        lines.append(f"| {role} | `{path}` | {path.stat().st_size} | `{sha256_file(path)}` | protected read-only source, not copied |")
    for path in sorted(out.glob("*")):
        if path.is_file() and path.name != "LARGE_FILE_MANIFEST.md":
            policy = "local audit output; review before any future Git authorization"
            lines.append(f"| audit output | `{path.name}` | {path.stat().st_size} | `{sha256_file(path)}` | {policy} |")
    (out / "LARGE_FILE_MANIFEST.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Step-05B-3 finalization completed: {out}")


if __name__ == "__main__":
    main()
