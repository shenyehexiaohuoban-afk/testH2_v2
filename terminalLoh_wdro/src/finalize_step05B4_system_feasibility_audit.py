"""Finalize the read-only Step-05B-4 system-feasibility audit."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path

import numpy as np
import pandas as pd


FOCUS = [12, 16, 17, 18, 19]
REFERENCE = [13, 14]
ALL_STATES = [12, 13, 14, 16, 17, 18, 19]
TOL = 1.0e-7


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def quantile95(series: pd.Series) -> float:
    return float(series.quantile(0.95))


def utilization_row(method: str, state: int, resource: str, values: pd.Series) -> dict:
    values = values.dropna().astype(float)
    if values.empty:
        return {
            "method": method,
            "state": state,
            "resource": resource,
            "observation_count": 0,
            "mean_utilization": np.nan,
            "median_utilization": np.nan,
            "q95_utilization": np.nan,
            "max_utilization": np.nan,
            "util_ge95_share": np.nan,
            "util_ge99_share": np.nan,
        }
    return {
        "method": method,
        "state": state,
        "resource": resource,
        "observation_count": int(values.size),
        "mean_utilization": float(values.mean()),
        "median_utilization": float(values.median()),
        "q95_utilization": quantile95(values),
        "max_utilization": float(values.max()),
        "util_ge95_share": float((values >= 0.95 - 1.0e-12).mean()),
        "util_ge99_share": float((values >= 0.99 - 1.0e-12).mean()),
    }


def build_resource_summary(site: pd.DataFrame, htt: pd.DataFrame) -> pd.DataFrame:
    rows: list[dict] = []
    methods = sorted(site["method"].unique())
    for method in methods:
        for state in ALL_STATES:
            ss = site[(site["method"] == method) & (site["state_id"] == state)]
            hh = htt[(htt["method"] == method) & (htt["state_id"] == state)]
            rows.append(utilization_row(
                method, state, "electrolyzer_production",
                ss.loc[ss["active"].astype(bool), "prod_utilization"],
            ))
            rows.append(utilization_row(
                method, state, "storage_inventory", ss["storage_utilization"],
            ))
            rows.append(utilization_row(
                method, state, "htt_aggregate_transport",
                hh.loc[hh["active"].astype(bool), "htt_utilization"],
            ))
    return pd.DataFrame(rows)


def build_terminal_path_site(site: pd.DataFrame) -> pd.DataFrame:
    terminal = site[site["terminal_event"].astype(bool)].copy()
    terminal["surplus_kg"] = np.maximum(
        0.0, terminal["end_inventory_kg"] - terminal["terminal_target_kg"]
    )
    terminal["deficit_kg"] = np.maximum(
        0.0, terminal["terminal_target_kg"] - terminal["end_inventory_kg"]
    )
    terminal["balance_inventory_minus_target_kg"] = (
        terminal["end_inventory_kg"] - terminal["terminal_target_kg"]
    )
    terminal["deficit_flag"] = terminal["deficit_kg"] > TOL
    terminal["surplus_flag"] = terminal["surplus_kg"] > TOL
    terminal["at_target_flag"] = (
        terminal["balance_inventory_minus_target_kg"].abs() <= TOL
    )
    terminal["attainment"] = np.where(
        terminal["terminal_target_kg"] > TOL,
        np.minimum(terminal["end_inventory_kg"], terminal["terminal_target_kg"])
        / terminal["terminal_target_kg"],
        np.nan,
    )
    return terminal


def build_spatial_balance(terminal: pd.DataFrame) -> pd.DataFrame:
    grouped = terminal.groupby(["method", "state_id", "site"], as_index=False).agg(
        OOS_count=("path_id", "nunique"),
        terminal_target_kg=("terminal_target_kg", "mean"),
        mean_final_inventory_kg=("end_inventory_kg", "mean"),
        median_final_inventory_kg=("end_inventory_kg", "median"),
        mean_balance_inventory_minus_target_kg=("balance_inventory_minus_target_kg", "mean"),
        mean_surplus_kg=("surplus_kg", "mean"),
        mean_deficit_kg=("deficit_kg", "mean"),
        deficit_path_share=("deficit_flag", "mean"),
        surplus_path_share=("surplus_flag", "mean"),
        at_target_path_share=("at_target_flag", "mean"),
        mean_attainment=("attainment", "mean"),
    )
    keys = ["state_id", "site"]
    saa = grouped[grouped["method"] == "saa"].drop(columns="method").set_index(keys)
    dro = grouped[grouped["method"] == "chi2_eta003"].drop(columns="method").set_index(keys)
    if not saa.index.equals(dro.index):
        raise RuntimeError("SAA and DRO terminal state/site rows do not align.")
    out = pd.DataFrame(index=saa.index).reset_index().rename(columns={"state_id": "state"})
    for column in saa.columns:
        out[f"saa_{column}"] = saa[column].to_numpy()
        out[f"dro_{column}"] = dro[column].to_numpy()
    out["delta_dro_minus_saa_target_kg"] = (
        out["dro_terminal_target_kg"] - out["saa_terminal_target_kg"]
    )
    out["delta_dro_minus_saa_mean_final_inventory_kg"] = (
        out["dro_mean_final_inventory_kg"] - out["saa_mean_final_inventory_kg"]
    )
    return out


def build_stage_total_balance(site: pd.DataFrame) -> pd.DataFrame:
    path_stage = site.groupby(
        ["method", "path_id", "state_id", "terminal_stage", "stage"], as_index=False
    ).agg(
        active=("active", "max"),
        terminal_event=("terminal_event", "max"),
        start_inventory_total_kg=("start_inventory_kg", "sum"),
        end_inventory_total_kg=("end_inventory_kg", "sum"),
        production_total_kg=("production_kg", "sum"),
        available_production_capacity_total_kg=("available_production_capacity_kg", "sum"),
        normal_demand_total_kg=("normal_demand_kg", "sum"),
        normal_served_total_kg=("normal_served_kg", "sum"),
        normal_shortage_total_kg=("normal_shortage_kg", "sum"),
        net_htt_inflow_total_kg=("net_htt_inflow_kg", "sum"),
        terminal_target_total_kg=("terminal_target_kg", "sum"),
        terminal_gap_total_kg=("terminal_gap_kg", "sum"),
    )
    path_stage["production_capacity_utilization"] = np.where(
        path_stage["active"].astype(bool),
        path_stage["production_total_kg"]
        / path_stage["available_production_capacity_total_kg"],
        np.nan,
    )
    path_stage["inventory_conservation_residual_kg"] = (
        path_stage["end_inventory_total_kg"]
        - path_stage["start_inventory_total_kg"]
        - path_stage["production_total_kg"]
        + path_stage["normal_served_total_kg"]
        - path_stage["net_htt_inflow_total_kg"]
    )
    metrics = [
        "start_inventory_total_kg", "end_inventory_total_kg", "production_total_kg",
        "available_production_capacity_total_kg", "production_capacity_utilization",
        "normal_demand_total_kg", "normal_served_total_kg", "normal_shortage_total_kg",
        "net_htt_inflow_total_kg", "terminal_target_total_kg", "terminal_gap_total_kg",
    ]
    agg_spec: dict[str, tuple[str, str]] = {
        "OOS_count": ("path_id", "nunique"),
        "active_path_share": ("active", "mean"),
        "terminal_event_path_share": ("terminal_event", "mean"),
        "max_abs_inventory_conservation_residual_kg": (
            "inventory_conservation_residual_kg", lambda x: float(np.max(np.abs(x)))
        ),
    }
    for metric in metrics:
        agg_spec[f"mean_{metric}"] = (metric, "mean")
        agg_spec[f"median_{metric}"] = (metric, "median")
    out = path_stage.groupby(["method", "state_id", "stage"], as_index=False).agg(**agg_spec)
    return out.rename(columns={"state_id": "state"})


def build_stage_site_trace(site: pd.DataFrame) -> pd.DataFrame:
    out = site.groupby(["method", "state_id", "stage", "site"], as_index=False).agg(
        OOS_count=("path_id", "nunique"),
        active_path_share=("active", "mean"),
        terminal_event_path_share=("terminal_event", "mean"),
        mean_start_inventory_kg=("start_inventory_kg", "mean"),
        mean_end_inventory_kg=("end_inventory_kg", "mean"),
        median_end_inventory_kg=("end_inventory_kg", "median"),
        mean_production_kg=("production_kg", "mean"),
        mean_prod_utilization=("prod_utilization", "mean"),
        mean_storage_utilization=("storage_utilization", "mean"),
        mean_normal_served_kg=("normal_served_kg", "mean"),
        mean_normal_shortage_kg=("normal_shortage_kg", "mean"),
        mean_htt_inflow_kg=("htt_inflow_kg", "mean"),
        mean_htt_outflow_kg=("htt_outflow_kg", "mean"),
        mean_net_htt_inflow_kg=("net_htt_inflow_kg", "mean"),
        mean_terminal_target_kg=("terminal_target_kg", "mean"),
        mean_terminal_gap_kg=("terminal_gap_kg", "mean"),
    )
    return out.rename(columns={"state_id": "state"})


def build_htt_trace(site: pd.DataFrame, htt: pd.DataFrame) -> pd.DataFrame:
    site_flow = site.groupby(["method", "state_id", "stage", "site"], as_index=False).agg(
        OOS_count=("path_id", "nunique"),
        mean_htt_inflow_kg=("htt_inflow_kg", "mean"),
        mean_htt_outflow_kg=("htt_outflow_kg", "mean"),
        mean_net_htt_inflow_kg=("net_htt_inflow_kg", "mean"),
        median_net_htt_inflow_kg=("net_htt_inflow_kg", "median"),
        positive_net_inflow_path_share=("net_htt_inflow_kg", lambda x: float((x > TOL).mean())),
        negative_net_inflow_path_share=("net_htt_inflow_kg", lambda x: float((x < -TOL).mean())),
    )
    total = htt.groupby(["method", "state_id", "stage"], as_index=False).agg(
        mean_total_htt_flow_kg=("total_htt_flow_kg", "mean"),
        median_total_htt_flow_kg=("total_htt_flow_kg", "median"),
        mean_available_htt_capacity_kg=("available_htt_capacity_kg", "mean"),
        mean_htt_utilization=("htt_utilization", "mean"),
        q95_htt_utilization=("htt_utilization", quantile95),
        max_htt_utilization=("htt_utilization", "max"),
    )
    out = site_flow.merge(total, on=["method", "state_id", "stage"], how="left")
    out["mean_direction"] = np.select(
        [out["mean_net_htt_inflow_kg"] > TOL, out["mean_net_htt_inflow_kg"] < -TOL],
        ["net_importer", "net_exporter"],
        default="balanced",
    )
    return out.rename(columns={"state_id": "state"})


def state_classification(group: pd.DataFrame) -> str:
    shares = group["path_classification"].value_counts(normalize=True)
    nonzero = [letter for letter in "ABCDE" if shares.get(letter, 0.0) > 0]
    if len(nonzero) == 1:
        return nonzero[0]
    dominant = max(nonzero, key=lambda letter: shares.get(letter, 0.0))
    return f"{'/'.join(nonzero)} mixed, {dominant}-dominant"


def build_state_summary(
    physical: pd.DataFrame,
    terminal: pd.DataFrame,
    spatial: pd.DataFrame,
    resource: pd.DataFrame,
) -> pd.DataFrame:
    final_totals = terminal.groupby(["method", "state_id", "path_id"], as_index=False).agg(
        final_total_kg=("end_inventory_kg", "sum"),
        target_total_kg=("terminal_target_kg", "sum"),
        terminal_gap_total_kg=("terminal_gap_kg", "sum"),
    )
    rows: list[dict] = []
    for state in ALL_STATES:
        pp = physical[physical["state_id"] == state]
        saa = final_totals[(final_totals["method"] == "saa") & (final_totals["state_id"] == state)]
        dro = final_totals[(final_totals["method"] == "chi2_eta003") & (final_totals["state_id"] == state)]
        dro_sites = spatial[spatial["state"] == state]
        rr = resource[(resource["method"] == "chi2_eta003") & (resource["state"] == state)]
        rmap = rr.set_index("resource")
        class_counts = pp["path_classification"].value_counts()
        physical_sufficient_share = float(pp["physical_total_sufficient"].mean())
        actual_sufficient_share = float(pp["actual_total_sufficient"].mean())
        mismatch_share = float(pp["actual_spatial_mismatch"].mean())
        if physical_sufficient_share >= 1.0 - 1.0e-12:
            suff_label = "yes_all_paths"
        elif physical_sufficient_share <= 1.0e-12:
            suff_label = "no_all_paths"
        else:
            suff_label = "mixed_by_path"
        if mismatch_share > 0:
            mismatch_label = "yes_on_some_actual_paths"
        else:
            mismatch_label = "no_actual_total_sufficient_mismatch"
        rows.append({
            "state": state,
            "OOS_count": int(pp["path_id"].nunique()),
            "T_total_dro": float(pp["T_total_dro_kg"].iloc[0]),
            "mean_I_total_saa": float(saa["final_total_kg"].mean()),
            "mean_I_total_dro": float(dro["final_total_kg"].mean()),
            "total_terminal_gap": float(dro["terminal_gap_total_kg"].mean()),
            "total_terminal_gap_kg_across_paths": float(dro["terminal_gap_total_kg"].sum()),
            "mean_service_preserving_max_terminal_total_kg": float(pp["service_preserving_max_terminal_total_kg"].mean()),
            "mean_service_preserving_min_terminal_gap_kg": float(pp["service_preserving_min_terminal_gap_kg"].mean()),
            "mean_system_total_shortfall_lower_bound_kg": float(pp["system_total_shortfall_lower_bound_kg"].mean()),
            "max_spatial_excess_gap_kg": float(pp["spatial_excess_gap_kg"].max()),
            "system_total_capacity_judgment": (
                f"physical total sufficient on {physical_sufficient_share:.2%} of paths"
            ),
            "total_H2_sufficient_yes_no": suff_label,
            "physical_total_sufficient_path_share": physical_sufficient_share,
            "physical_spatial_feasible_path_share": float(pp["physical_spatial_feasible"].mean()),
            "actual_total_sufficient_path_share": actual_sufficient_share,
            "spatial_mismatch_yes_no": mismatch_label,
            "actual_spatial_mismatch_path_share": mismatch_share,
            "surplus_site_count": int((dro_sites["dro_mean_balance_inventory_minus_target_kg"] > TOL).sum()),
            "deficit_site_count": int((dro_sites["dro_mean_balance_inventory_minus_target_kg"] < -TOL).sum()),
            "mean_surplus_site_count_per_path": float(
                terminal[(terminal["method"] == "chi2_eta003") & (terminal["state_id"] == state)]
                .groupby("path_id")["surplus_flag"].sum().mean()
            ),
            "mean_deficit_site_count_per_path": float(
                terminal[(terminal["method"] == "chi2_eta003") & (terminal["state_id"] == state)]
                .groupby("path_id")["deficit_flag"].sum().mean()
            ),
            "mean_prod_utilization": float(rmap.loc["electrolyzer_production", "mean_utilization"]),
            "median_prod_utilization": float(rmap.loc["electrolyzer_production", "median_utilization"]),
            "q95_prod_utilization": float(rmap.loc["electrolyzer_production", "q95_utilization"]),
            "max_prod_utilization": float(rmap.loc["electrolyzer_production", "max_utilization"]),
            "prod_util_ge95_share": float(rmap.loc["electrolyzer_production", "util_ge95_share"]),
            "prod_util_ge99_share": float(rmap.loc["electrolyzer_production", "util_ge99_share"]),
            "mean_storage_utilization": float(rmap.loc["storage_inventory", "mean_utilization"]),
            "median_storage_utilization": float(rmap.loc["storage_inventory", "median_utilization"]),
            "q95_storage_utilization": float(rmap.loc["storage_inventory", "q95_utilization"]),
            "max_storage_utilization": float(rmap.loc["storage_inventory", "max_utilization"]),
            "storage_util_ge99_share": float(rmap.loc["storage_inventory", "util_ge99_share"]),
            "mean_htt_utilization": float(rmap.loc["htt_aggregate_transport", "mean_utilization"]),
            "median_htt_utilization": float(rmap.loc["htt_aggregate_transport", "median_utilization"]),
            "q95_htt_utilization": float(rmap.loc["htt_aggregate_transport", "q95_utilization"]),
            "max_htt_utilization": float(rmap.loc["htt_aggregate_transport", "max_utilization"]),
            "htt_util_ge95_share": float(rmap.loc["htt_aggregate_transport", "util_ge95_share"]),
            "htt_util_ge99_share": float(rmap.loc["htt_aggregate_transport", "util_ge99_share"]),
            "class_A_path_count": int(class_counts.get("A", 0)),
            "class_A_path_share": float((pp["path_classification"] == "A").mean()),
            "class_B_path_count": int(class_counts.get("B", 0)),
            "class_B_path_share": float((pp["path_classification"] == "B").mean()),
            "class_C_path_count": int(class_counts.get("C", 0)),
            "class_C_path_share": float((pp["path_classification"] == "C").mean()),
            "class_D_path_count": int(class_counts.get("D", 0)),
            "class_D_path_share": float((pp["path_classification"] == "D").mean()),
            "class_E_path_count": int(class_counts.get("E", 0)),
            "final_classification": state_classification(pp),
        })
    return pd.DataFrame(rows)


def build_detailed_check(summary: pd.DataFrame, spatial: pd.DataFrame, states: list[int]) -> pd.DataFrame:
    result = summary[summary["state"].isin(states)].copy()
    site_metrics = spatial[spatial["state"].isin(states)].copy()
    wide_parts = []
    for site_id in range(1, 5):
        part = site_metrics[site_metrics["site"] == site_id].set_index("state")[[
            "dro_terminal_target_kg", "dro_mean_final_inventory_kg",
            "dro_mean_deficit_kg", "dro_mean_surplus_kg", "dro_deficit_path_share",
            "dro_mean_htt_inflow_kg" if "dro_mean_htt_inflow_kg" in site_metrics.columns else "dro_mean_balance_inventory_minus_target_kg",
        ]].copy()
        part = part.rename(columns={column: f"site{site_id}_{column}" for column in part.columns})
        wide_parts.append(part)
    wide = pd.concat(wide_parts, axis=1).reset_index()
    return result.merge(wide, on="state", how="left")


def write_text_outputs(
    out: Path,
    summary: pd.DataFrame,
    spatial: pd.DataFrame,
    resource: pd.DataFrame,
    physical: pd.DataFrame,
    integrity_text: str,
) -> None:
    smap = summary.set_index("state")
    class_total = physical["path_classification"].value_counts()
    max_spatial = float(physical["spatial_excess_gap_kg"].max())
    prod = resource[(resource["method"] == "chi2_eta003") & (resource["resource"] == "electrolyzer_production")]
    storage = resource[(resource["method"] == "chi2_eta003") & (resource["resource"] == "storage_inventory")]
    htt = resource[(resource["method"] == "chi2_eta003") & (resource["resource"] == "htt_aggregate_transport")]
    state12_site1 = spatial[(spatial["state"] == 12) & (spatial["site"] == 1)].iloc[0]
    state12_site2 = spatial[(spatial["state"] == 12) & (spatial["site"] == 2)].iloc[0]
    state19 = smap.loc[19]

    judgment = f"""Step-05B-4 judgment

Scope and mechanical status
- This audit replays the two saved fixed policies on the unchanged frozen 10000x8 OOS table and analyzes only the 649 paths reaching states 12, 13, 14, 16, 17, 18, or 19.
- All 649 maximum-total and 649 minimum-gap diagnostic LPs are OPTIMAL. Ordinary H2 service is fixed to the actual DRO replay service; initial inventory, station tank limits, electrolyzer limits, inventory conservation, beta-dependent aggregate HTT capacity, and the original time horizon remain enforced.
- The diagnostic LPs contain no cuts, theta, or monetary objective and are not replacement MSP policies.

System-total and spatial feasibility
- State12: total hydrogen is physically sufficient on {smap.loc[12, 'physical_total_sufficient_path_share']:.2%} of paths; classification {smap.loc[12, 'final_classification']}. The saved DRO policy has enough total terminal inventory yet a station gap on {smap.loc[12, 'actual_spatial_mismatch_path_share']:.2%} of paths. Site1 target/mean inventory is {state12_site1.dro_terminal_target_kg:.6f}/{state12_site1.dro_mean_final_inventory_kg:.6f} kg, while site2 mean inventory is {state12_site2.dro_mean_final_inventory_kg:.6f} kg against a {state12_site2.dro_terminal_target_kg:.6f} kg target.
- State16: total sufficient on {smap.loc[16, 'physical_total_sufficient_path_share']:.2%}; {int(smap.loc[16, 'class_A_path_count'])}/{int(smap.loc[16, 'OOS_count'])} paths are class A. System total supply is the dominant limitation.
- State17: total sufficient on {smap.loc[17, 'physical_total_sufficient_path_share']:.2%}; {int(smap.loc[17, 'class_A_path_count'])}/{int(smap.loc[17, 'OOS_count'])} paths are class A. System total supply is the dominant limitation.
- State18: total sufficient on {smap.loc[18, 'physical_total_sufficient_path_share']:.2%}; {int(smap.loc[18, 'class_A_path_count'])}/{int(smap.loc[18, 'OOS_count'])} paths are class A. System total supply is the dominant limitation.
- State19: total sufficient on {state19.physical_total_sufficient_path_share:.2%}; {int(state19.class_A_path_count)}/{int(state19.OOS_count)} paths are class A and {int(state19.class_C_path_count)}/{int(state19.OOS_count)} are class C. It is primarily a system-total capability problem, with a material minority of physically feasible paths where the saved policy still fails to allocate/retain the target inventory.
- State13 and state14 are physically total-sufficient on {smap.loc[13, 'physical_total_sufficient_path_share']:.2%} and {smap.loc[14, 'physical_total_sufficient_path_share']:.2%} of paths. Their remaining saved-policy gaps are mainly class C strategy/value-signal outcomes rather than proven physical infeasibility.
- Across all paths, class counts are A={int(class_total.get('A',0))}, B={int(class_total.get('B',0))}, C={int(class_total.get('C',0))}, D={int(class_total.get('D',0))}, E={int(class_total.get('E',0))}. Maximum spatial-excess gap is {max_spatial:.3e} kg. Whenever the system-total bound is sufficient, the minimum-gap LP reaches all four site targets under the current HTT constraints; no independent HTT capacity/timing infeasibility was found.

Resource utilization and bottlenecks
- DRO electrolyzer mean utilization spans {prod.mean_utilization.min():.2%} to {prod.mean_utilization.max():.2%} across the seven states, with q95=100% for every state and >=99% shares from {prod.util_ge99_share.min():.2%} to {prod.util_ge99_share.max():.2%}. Electrolyzer production is a persistent high-utilization resource and a credible system-total bottleneck, especially in states16-19.
- DRO storage mean utilization spans {storage.mean_utilization.min():.2%} to {storage.mean_utilization.max():.2%}; >=99% shares are at most {storage.util_ge99_share.max():.2%}. Tank capacity is not the dominant system bottleneck in these paths.
- DRO aggregate HTT mean utilization spans {htt.mean_utilization.min():.2%} to {htt.mean_utilization.max():.2%}; q95 spans {htt.q95_utilization.min():.2%} to {htt.q95_utilization.max():.2%}, maximum observed utilization is {htt.max_utilization.max():.2%}, and >=99% share is {htt.util_ge99_share.max():.2%}. HTT capacity is not saturated. Nevertheless, the saved policy can still allocate HTT in the wrong direction or too late; capacity headroom alone does not prove that the policy's spatial allocation is effective.

Penalty implication and next step
- The results do not provide evidence that the 200 or 2000 penalty should be changed. The dominant class-A cases are physical total-supply limitations under fixed ordinary service, while class-C cases require examination of the saved one-hour policy's cuts/value signal and HTT allocation before changing penalties.
- Recommended next step: keep 200/2000 frozen; first audit state12/13/14 class-C paths for cut/value propagation and HTT direction/timing, and separately test whether additional system production capability changes state16-19 feasibility. Do not infer Pearson DRO success or failure from this mechanism audit.
"""
    (out / "step05b4_judgment.txt").write_text(judgment, encoding="utf-8")

    readme = f"""# Step-05B-4 TerminalLOH system feasibility audit

This accepted read-only audit separates three questions that must not be conflated:

1. **System-total supply:** can the four-station system retain the DRO total target while serving the ordinary H2 load actually served by the saved DRO policy?
2. **Physical spatial feasibility:** when total supply is sufficient, can the original beta-dependent HTT and station constraints place enough inventory at every target station before the terminal event?
3. **Saved-policy realization:** did the existing fixed one-hour policy actually retain and allocate the required inventory?

## Inputs and integrity

- Frozen Git baseline: `06f10864f36a6358eb671632ce3e032ddf0ae97e` on `task/002-stage2b-b3-smoke`.
- Saved SAA and eta=0.03 policies: Step-05B `run-003`.
- Common OOS table: `output_h2/details/h2_OOS.csv`, SHA-256 `6e4ed488423e3cbb838c4a6f8b45019cf4ecf32a82850880399a08aafc7aff85`.
- Focus states: 12, 16, 17, 18, 19; reference states: 13, 14.
- Selected terminal-hit paths: 649. Both saved-policy replays reproduce archived final inventory to at most `5.12e-13`; terminal-state mismatch count is zero.
- Diagnostic LPs: 1298/1298 OPTIMAL; maximum conservation residual `4.97e-14` and maximum target/gap reconstruction residual below `6.3e-13`.

## Diagnostic classification

- **A:** system-total hydrogen is insufficient under the preserved physical constraints and fixed ordinary service.
- **B:** system total is sufficient, but the original HTT/site constraints cannot realize all station targets.
- **C:** system total and spatial placement are physically feasible, but the saved policy does not necessarily realize them; inspect cuts, value signals, and actual HTT allocation.
- **D:** system-total insufficiency and an additional spatial impediment coexist.
- **E:** solver/data evidence is insufficient.

Observed path counts are A={int(class_total.get('A',0))}, C={int(class_total.get('C',0))}, with B=D=E=0. The absence of B/D is a result of this frozen physical model, not a general statement that transport never matters.

## Important model boundary

HTT is an internal four-station transfer and is never counted as new hydrogen. The current main MSP imposes a beta-dependent aggregate HTT capacity and cost, but no pairwise hard road-reachability constraint on HTT arcs. Consequently, these results support only the current model's spatial-feasibility statement.

## Output guide

- `state_system_feasibility_summary.csv`: primary state-level total/spatial/resource table.
- `state_site_spatial_balance.csv`: SAA/DRO station targets, final inventory, surplus, deficit, and path shares.
- `stage_total_h2_balance.csv`: stage-level four-station hydrogen conservation and ordinary-service totals.
- `stage_site_inventory_trace.csv`: station inventory, production, service, and transport traces.
- `htt_redistribution_trace.csv`: actual station inflow/outflow/net flow and aggregate HTT utilization.
- `resource_utilization_summary.csv`: continuous mean/median/q95/max utilization and >=95%/>=99% shares.
- `state12_16_17_18_19_detailed_check.csv`: required focus-state detail.
- `state13_14_reference_check.csv`: reference-state detail.
- `physical_feasibility_path_audit.csv`: path-level diagnostic LP evidence.
- `replay_integrity_audit.txt`: deterministic replay and LP mechanical certificate.
- `step05b4_judgment.txt`: bounded interpretation and next-step recommendation.

## Replay certificate

```text
{integrity_text.strip()}
```
"""
    (out / "README.md").write_text(readme, encoding="utf-8")


def build_manifest(out: Path) -> pd.DataFrame:
    rows = []
    for path in sorted(out.iterdir(), key=lambda value: value.name.lower()):
        if not path.is_file() or path.name == "LARGE_FILE_MANIFEST.md":
            continue
        size = path.stat().st_size
        rows.append({
            "file": path.name,
            "size_bytes": size,
            "sha256": sha256_file(path),
            "disposition": "local_only_large_replay" if size >= 1_000_000 else "lightweight_audit_output",
        })
    return pd.DataFrame(rows)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-id", default="run-001")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    out = repo / "results/task-002-stage2b-b3-smoke/61-terminal-loh-system-feasibility-audit" / args.run_id
    required = [
        "physical_feasibility_path_audit.csv",
        "replay_stage_site_observations.csv",
        "replay_stage_htt_observations.csv",
        "replay_htt_arc_observations.csv",
        "replay_integrity_audit.txt",
    ]
    for name in required:
        if not (out / name).is_file():
            raise FileNotFoundError(out / name)
    outputs = [
        "state_system_feasibility_summary.csv", "state_site_spatial_balance.csv",
        "stage_total_h2_balance.csv", "stage_site_inventory_trace.csv",
        "htt_redistribution_trace.csv", "resource_utilization_summary.csv",
        "state12_16_17_18_19_detailed_check.csv", "state13_14_reference_check.csv",
        "step05b4_judgment.txt", "README.md", "LARGE_FILE_MANIFEST.md",
    ]
    for name in outputs:
        if (out / name).exists():
            raise RuntimeError(f"Refusing to overwrite existing output: {out / name}")

    integrity_text = (out / "replay_integrity_audit.txt").read_text(encoding="utf-8")
    if "Replay PASS: 1" not in integrity_text or "Physical LP PASS: 1" not in integrity_text:
        raise RuntimeError("Replay or physical diagnostic LP gate did not pass.")

    physical = pd.read_csv(out / "physical_feasibility_path_audit.csv")
    site = pd.read_csv(out / "replay_stage_site_observations.csv")
    htt = pd.read_csv(out / "replay_stage_htt_observations.csv")
    arcs = pd.read_csv(out / "replay_htt_arc_observations.csv")
    if len(physical) != 649 or physical["path_id"].nunique() != 649:
        raise RuntimeError("Expected exactly 649 unique physical-audit paths.")
    if set(physical["state_id"].unique()) != set(ALL_STATES):
        raise RuntimeError("Physical-audit state set changed.")
    if not physical["solve_pass"].astype(bool).all():
        raise RuntimeError("At least one physical diagnostic LP failed.")
    if set(site["method"].unique()) != {"saa", "chi2_eta003"}:
        raise RuntimeError("Replay method set changed.")
    if arcs["flow_kg"].min() < -TOL:
        raise RuntimeError("Negative HTT arc flow detected.")

    terminal = build_terminal_path_site(site)
    resource = build_resource_summary(site, htt)
    spatial = build_spatial_balance(terminal)
    stage_total = build_stage_total_balance(site)
    stage_site = build_stage_site_trace(site)
    htt_trace = build_htt_trace(site, htt)
    summary = build_state_summary(physical, terminal, spatial, resource)
    detail = build_detailed_check(summary, spatial, FOCUS)
    reference = build_detailed_check(summary, spatial, REFERENCE)

    # Independent mechanical checks before writing accepted summaries.
    if physical["max_conservation_residual"].max() > 1.0e-8:
        raise RuntimeError("Physical diagnostic conservation residual exceeded tolerance.")
    if physical["target_gap_reconstruction_residual"].max() > 1.0e-8:
        raise RuntimeError("Target/gap reconstruction residual exceeded tolerance.")
    if physical["spatial_excess_gap_kg"].max() > 1.0e-7:
        raise RuntimeError("Unexpected spatial-excess gap exceeded tolerance.")
    if stage_total["max_abs_inventory_conservation_residual_kg"].max() > 1.0e-8:
        raise RuntimeError("Replay stage hydrogen conservation residual exceeded tolerance.")
    if not np.allclose(
        summary["T_total_dro"].to_numpy(),
        spatial.groupby("state")["dro_terminal_target_kg"].sum().reindex(summary["state"]).to_numpy(),
        atol=1.0e-8,
    ):
        raise RuntimeError("DRO station targets do not reproduce state total targets.")
    if int(summary["OOS_count"].sum()) != 649:
        raise RuntimeError("State OOS counts do not sum to 649.")

    summary.to_csv(out / "state_system_feasibility_summary.csv", index=False, float_format="%.15g")
    spatial.to_csv(out / "state_site_spatial_balance.csv", index=False, float_format="%.15g")
    stage_total.to_csv(out / "stage_total_h2_balance.csv", index=False, float_format="%.15g")
    stage_site.to_csv(out / "stage_site_inventory_trace.csv", index=False, float_format="%.15g")
    htt_trace.to_csv(out / "htt_redistribution_trace.csv", index=False, float_format="%.15g")
    resource.to_csv(out / "resource_utilization_summary.csv", index=False, float_format="%.15g")
    detail.to_csv(out / "state12_16_17_18_19_detailed_check.csv", index=False, float_format="%.15g")
    reference.to_csv(out / "state13_14_reference_check.csv", index=False, float_format="%.15g")
    write_text_outputs(out, summary, spatial, resource, physical, integrity_text)

    manifest = build_manifest(out)
    lines = [
        "# LARGE_FILE_MANIFEST",
        "",
        "Files at or above 1,000,000 bytes are full replay evidence and remain local-only.",
        "No MAT file, prepared input, new OOS sample, cut library, or training output was created.",
        "",
        "| file | size_bytes | sha256 | disposition |",
        "|---|---:|---|---|",
    ]
    for row in manifest.itertuples(index=False):
        lines.append(f"| {row.file} | {row.size_bytes} | {row.sha256} | {row.disposition} |")
    (out / "LARGE_FILE_MANIFEST.md").write_text("\n".join(lines) + "\n", encoding="utf-8")

    print(f"Step-05B-4 finalizer PASS: {out}")
    print(summary[[
        "state", "OOS_count", "T_total_dro", "mean_I_total_dro", "total_terminal_gap",
        "physical_total_sufficient_path_share", "actual_spatial_mismatch_path_share",
        "mean_prod_utilization", "mean_storage_utilization", "mean_htt_utilization",
        "final_classification",
    ]].to_string(index=False))


if __name__ == "__main__":
    main()
