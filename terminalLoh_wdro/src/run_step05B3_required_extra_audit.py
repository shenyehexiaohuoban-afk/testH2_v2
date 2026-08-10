"""Build the Step-05B-3 required-extra and A/B/C/D path-site audit.

The script reads accepted lightweight common-sample results only.  It does not
load or run the MSP.  A separate MATLAB replay script consumes the selected
pair manifest written here.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import pandas as pd


EPS = 1.0e-12
CLASS_EPS = 1.0e-9


def validate_and_pair(repo: Path) -> pd.DataFrame:
    source = repo / "results/task-002-stage2b-b3-smoke/58-main-msp-terminal-gap-mechanism-audit/run-004/terminal_target_vs_final_inventory.csv"
    if not source.is_file():
        raise FileNotFoundError(source)
    raw = pd.read_csv(source)
    required = {
        "method", "path_id", "hit_terminal", "terminal_stage", "terminal_state",
        "a", "loc", "lf", "ordinary_shortage", "production_amount", "htt_amount",
    }
    for site in range(1, 5):
        required.update({f"target_site{site}", f"final_site{site}", f"gap_site{site}"})
    missing = required - set(raw.columns)
    if missing:
        raise RuntimeError(f"Missing Step-05B-1 columns: {sorted(missing)}")

    saa = raw[raw["method"] == "saa"].sort_values("path_id").reset_index(drop=True)
    dro = raw[raw["method"] == "chi2_eta003"].sort_values("path_id").reset_index(drop=True)
    if len(saa) != 10000 or len(dro) != 10000:
        raise RuntimeError("Expected 10000 rows per method.")
    common = ["path_id", "hit_terminal", "terminal_stage", "terminal_state", "a", "loc", "lf"]
    if not saa[common].equals(dro[common]):
        raise RuntimeError("The two policies do not have identical path/terminal events.")
    if int(saa["hit_terminal"].sum()) != 6053:
        raise RuntimeError("Expected 6053 terminal-hit paths.")

    hit_mask = saa["hit_terminal"].eq(1)
    saa = saa.loc[hit_mask].reset_index(drop=True)
    dro = dro.loc[hit_mask].reset_index(drop=True)
    paired = saa[common].copy()
    paired["state_id"] = ((paired["a"].astype(int) - 2) * 7 + paired["loc"].astype(int)).astype(int)
    paired["saa_ordinary_shortage_total_kg"] = saa["ordinary_shortage"].to_numpy(float)
    paired["dro_ordinary_shortage_total_kg"] = dro["ordinary_shortage"].to_numpy(float)
    paired["saa_production_total_kg"] = saa["production_amount"].to_numpy(float)
    paired["dro_production_total_kg"] = dro["production_amount"].to_numpy(float)
    paired["saa_htt_total_kg"] = saa["htt_amount"].to_numpy(float)
    paired["dro_htt_total_kg"] = dro["htt_amount"].to_numpy(float)

    rows = []
    for site in range(1, 5):
        part = paired.copy()
        part["site"] = site
        part["T_saa_kg"] = saa[f"target_site{site}"].to_numpy(float)
        part["T_dro_kg"] = dro[f"target_site{site}"].to_numpy(float)
        part["I_saa_kg"] = saa[f"final_site{site}"].to_numpy(float)
        part["I_dro_kg"] = dro[f"final_site{site}"].to_numpy(float)
        rows.append(part)
    detail = pd.concat(rows, ignore_index=True).sort_values(["path_id", "site"]).reset_index(drop=True)

    detail["surplus_saa_kg"] = np.maximum(0.0, detail["I_saa_kg"] - detail["T_saa_kg"])
    detail["preexisting_saa_gap_kg"] = np.maximum(0.0, detail["T_saa_kg"] - detail["I_saa_kg"])
    detail["delta_T_kg"] = detail["T_dro_kg"] - detail["T_saa_kg"]
    detail["positive_delta_T_kg"] = np.maximum(0.0, detail["delta_T_kg"])
    detail["new_target_covered_by_saa_surplus_kg"] = np.minimum(
        detail["positive_delta_T_kg"], detail["surplus_saa_kg"]
    )
    detail["uncovered_new_target_increment_kg"] = (
        detail["positive_delta_T_kg"] - detail["new_target_covered_by_saa_surplus_kg"]
    )
    detail["required_extra_kg"] = np.maximum(0.0, detail["T_dro_kg"] - detail["I_saa_kg"])
    detail["actual_extra_kg"] = detail["I_dro_kg"] - detail["I_saa_kg"]
    detail["positive_actual_extra_kg"] = np.maximum(0.0, detail["actual_extra_kg"])
    detail["required_extra_realized_kg"] = np.minimum(
        detail["positive_actual_extra_kg"], detail["required_extra_kg"]
    )
    detail["unrealized_required_extra_kg"] = detail["required_extra_kg"] - detail["required_extra_realized_kg"]
    detail["remaining_gap_kg"] = np.maximum(0.0, detail["T_dro_kg"] - detail["I_dro_kg"])
    detail["effective_realization"] = np.where(
        detail["required_extra_kg"] > EPS,
        detail["required_extra_realized_kg"] / detail["required_extra_kg"],
        np.nan,
    )

    saa_covers = detail["I_saa_kg"] >= detail["T_dro_kg"] - CLASS_EPS
    dro_satisfies = detail["I_dro_kg"] >= detail["T_dro_kg"] - CLASS_EPS
    dro_increases = detail["I_dro_kg"] > detail["I_saa_kg"] + CLASS_EPS
    detail["abcd_class"] = np.select(
        [
            saa_covers,
            (~saa_covers) & dro_satisfies,
            (~saa_covers) & (~dro_satisfies) & dro_increases,
            (~saa_covers) & (~dro_satisfies) & (~dro_increases),
        ],
        ["A", "B", "C", "D"],
        default="UNCLASSIFIED",
    )
    if (detail["abcd_class"] == "UNCLASSIFIED").any():
        raise RuntimeError("Unclassified path-site rows remain.")
    detail["a_subclass"] = np.where(
        detail["abcd_class"].eq("A"),
        np.where(dro_satisfies, "A_dro_still_satisfies", "A_dro_falls_below_target"),
        "not_A",
    )

    decomp_mask = detail["delta_T_kg"] > EPS
    decomp_error = np.max(
        np.abs(
            detail.loc[decomp_mask, "required_extra_kg"]
            - detail.loc[decomp_mask, "preexisting_saa_gap_kg"]
            - detail.loc[decomp_mask, "uncovered_new_target_increment_kg"]
        )
    )
    if decomp_error > 1.0e-8:
        raise RuntimeError(f"Required-extra decomposition error: {decomp_error}")
    return detail


def aggregate_scope(name: str, frame: pd.DataFrame) -> dict:
    positive_dt = frame["positive_delta_T_kg"].sum()
    covered = frame["new_target_covered_by_saa_surplus_kg"].sum()
    required = frame["required_extra_kg"].sum()
    realized = frame["required_extra_realized_kg"].sum()
    return {
        "scope": name,
        "row_count": len(frame),
        "positive_delta_T_total_kg": positive_dt,
        "new_target_covered_by_saa_surplus_kg": covered,
        "covered_share_of_positive_delta_T": covered / positive_dt if positive_dt > EPS else np.nan,
        "uncovered_new_target_increment_kg": frame["uncovered_new_target_increment_kg"].sum(),
        "preexisting_saa_gap_kg": frame["preexisting_saa_gap_kg"].sum(),
        "required_extra_total_kg": required,
        "positive_actual_extra_total_kg": frame["positive_actual_extra_kg"].sum(),
        "required_extra_realized_kg": realized,
        "effective_realization_ratio": realized / required if required > EPS else np.nan,
        "unrealized_required_extra_kg": frame["unrealized_required_extra_kg"].sum(),
        "remaining_gap_total_kg": frame["remaining_gap_kg"].sum(),
        "A_count": int(frame["abcd_class"].eq("A").sum()),
        "B_count": int(frame["abcd_class"].eq("B").sum()),
        "C_count": int(frame["abcd_class"].eq("C").sum()),
        "D_count": int(frame["abcd_class"].eq("D").sum()),
    }


def build_summaries(detail: pd.DataFrame):
    summary_rows = [aggregate_scope("all_terminal_hit_path_site_rows", detail)]
    summary_rows.append(aggregate_scope("positive_delta_T_path_site_rows", detail[detail["delta_T_kg"] > EPS]))
    summary_rows.append(aggregate_scope("required_extra_positive_rows", detail[detail["required_extra_kg"] > EPS]))
    for site in range(1, 5):
        summary_rows.append(aggregate_scope(f"site{site}_all_terminal_hits", detail[detail["site"] == site]))
    for state in [1, 2, 3, 4, 7, 13, 14, 19]:
        summary_rows.append(aggregate_scope(f"state{state}_all_sites", detail[detail["state_id"] == state]))
    required_summary = pd.DataFrame(summary_rows)

    class_rows = []
    for class_name in ["A", "B", "C", "D"]:
        frame = detail[detail["abcd_class"] == class_name]
        row = aggregate_scope(f"class_{class_name}", frame)
        row["abcd_class"] = class_name
        row["share_of_all_terminal_hit_path_site_rows"] = len(frame) / len(detail)
        row["mean_required_extra_kg"] = frame["required_extra_kg"].mean() if len(frame) else np.nan
        row["mean_actual_extra_kg"] = frame["actual_extra_kg"].mean() if len(frame) else np.nan
        row["mean_remaining_gap_kg"] = frame["remaining_gap_kg"].mean() if len(frame) else np.nan
        class_rows.append(row)
    effective_summary = pd.DataFrame(class_rows)
    return required_summary, effective_summary


def build_state_station(detail: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for (state_id, site), frame in detail.groupby(["state_id", "site"], sort=True):
        first = frame.iloc[0]
        positive_dt = frame["positive_delta_T_kg"].sum()
        covered = frame["new_target_covered_by_saa_surplus_kg"].sum()
        required = frame["required_extra_kg"].sum()
        realized = frame["required_extra_realized_kg"].sum()
        cd = frame[frame["abcd_class"].isin(["C", "D"])]
        rows.append(
            {
                "state_id": int(state_id),
                "terminal_state_k": int(first["terminal_state"]),
                "intensity": int(first["a"]),
                "loc": int(first["loc"]),
                "site": int(site),
                "arrival_count": len(frame),
                "arrival_frequency_full_oos": len(frame) / 10000.0,
                "T_saa_kg": float(first["T_saa_kg"]),
                "T_dro_kg": float(first["T_dro_kg"]),
                "delta_T_kg_per_path": float(first["delta_T_kg"]),
                "positive_delta_T_mass_kg": positive_dt,
                "saa_surplus_total_kg": frame["surplus_saa_kg"].sum(),
                "new_target_covered_by_saa_surplus_kg": covered,
                "covered_share_of_positive_delta_T": covered / positive_dt if positive_dt > EPS else np.nan,
                "uncovered_new_target_increment_kg": frame["uncovered_new_target_increment_kg"].sum(),
                "preexisting_saa_gap_kg": frame["preexisting_saa_gap_kg"].sum(),
                "required_extra_total_kg": required,
                "mean_actual_extra_kg": frame["actual_extra_kg"].mean(),
                "positive_actual_extra_total_kg": frame["positive_actual_extra_kg"].sum(),
                "required_extra_realized_kg": realized,
                "effective_realization_ratio": realized / required if required > EPS else np.nan,
                "unrealized_required_extra_kg": frame["unrealized_required_extra_kg"].sum(),
                "remaining_gap_total_kg": frame["remaining_gap_kg"].sum(),
                "remaining_gap_C_D_total_kg": cd["remaining_gap_kg"].sum(),
                "A_count": int(frame["abcd_class"].eq("A").sum()),
                "A_dro_falls_below_target_count": int(frame["a_subclass"].eq("A_dro_falls_below_target").sum()),
                "B_count": int(frame["abcd_class"].eq("B").sum()),
                "C_count": int(frame["abcd_class"].eq("C").sum()),
                "D_count": int(frame["abcd_class"].eq("D").sum()),
            }
        )
    return pd.DataFrame(rows)


def build_ranking_and_selection(state_station: pd.DataFrame):
    ranking = state_station[
        (state_station["C_count"] + state_station["D_count"] > 0)
        & (state_station["remaining_gap_C_D_total_kg"] > EPS)
    ].copy()
    ranking = ranking.sort_values(
        ["remaining_gap_C_D_total_kg", "required_extra_total_kg"], ascending=[False, False]
    ).reset_index(drop=True)
    ranking.insert(0, "remaining_gap_rank", np.arange(1, len(ranking) + 1))
    total_cd_gap = ranking["remaining_gap_C_D_total_kg"].sum()
    ranking["share_of_C_D_remaining_gap"] = ranking["remaining_gap_C_D_total_kg"] / total_cd_gap
    ranking["cumulative_share_of_C_D_remaining_gap"] = ranking["share_of_C_D_remaining_gap"].cumsum()

    selected = ranking.head(8)[["state_id", "site", "remaining_gap_rank"]].copy()
    selected["selection_reason"] = "top8_C_D_remaining_gap"
    priorities = []
    for state_id, preferred_site, reason in [
        (14, 1, "priority_state14_site1"),
        (13, None, "priority_state13_largest_gap_site"),
        (19, None, "priority_state19_largest_gap_site"),
    ]:
        candidates = ranking[ranking["state_id"] == state_id]
        if preferred_site is not None:
            candidates = candidates[candidates["site"] == preferred_site]
        if len(candidates):
            item = candidates.iloc[0]
            priorities.append(
                {
                    "state_id": int(item["state_id"]),
                    "site": int(item["site"]),
                    "remaining_gap_rank": int(item["remaining_gap_rank"]),
                    "selection_reason": reason,
                }
            )
    selected = pd.concat([selected, pd.DataFrame(priorities)], ignore_index=True)
    selected = (
        selected.groupby(["state_id", "site", "remaining_gap_rank"], as_index=False)["selection_reason"]
        .agg(lambda values: ";".join(sorted(set(values))))
        .sort_values("remaining_gap_rank")
        .reset_index(drop=True)
    )
    selected.insert(0, "selected_pair_id", np.arange(1, len(selected) + 1))
    selected = selected.merge(
        ranking[
            [
                "state_id", "site", "terminal_state_k", "arrival_count", "required_extra_total_kg",
                "required_extra_realized_kg", "effective_realization_ratio", "remaining_gap_C_D_total_kg",
                "C_count", "D_count",
            ]
        ],
        on=["state_id", "site"], how="left", validate="one_to_one",
    )
    return ranking, selected


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-id", default="run-001")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    out_dir = repo / "results/task-002-stage2b-b3-smoke/60-terminal-loh-required-extra-and-flow-audit" / args.run_id
    out_dir.mkdir(parents=True, exist_ok=False)

    detail = validate_and_pair(repo)
    required_summary, effective_summary = build_summaries(detail)
    state_station = build_state_station(detail)
    ranking, selected = build_ranking_and_selection(state_station)

    detail.to_csv(out_dir / "path_station_abcd_classification.csv", index=False, float_format="%.15g")
    required_summary.to_csv(out_dir / "required_extra_summary.csv", index=False, float_format="%.15g")
    effective_summary.to_csv(out_dir / "effective_realization_summary.csv", index=False, float_format="%.15g")
    state_station.to_csv(out_dir / "state_station_required_extra.csv", index=False, float_format="%.15g")
    ranking.to_csv(out_dir / "remaining_gap_ranking.csv", index=False, float_format="%.15g")
    selected.to_csv(out_dir / "selected_pair_manifest.csv", index=False, float_format="%.15g")
    print(f"Step-05B-3 required-extra audit prepared: {out_dir}")


if __name__ == "__main__":
    main()
