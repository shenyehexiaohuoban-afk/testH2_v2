"""Exploratory Base-vs-B0001 analysis for a failed-stability checkpoint.

This intentionally does not claim formal dual-candidate acceptance. It reads
the accepted Base OOS and one B0001 exploratory OOS only.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd


BASE = Path(
    "hourly_grid_h2/output/stage89q_penalty1000_vs1500_long_training/"
    "run-003/penalty1000"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def read_arm(root: Path) -> dict[str, pd.DataFrame]:
    path = root / "path_summary/oos_path_summary.csv"
    stage = root / "path_summary/oos_stage_summary.csv"
    site = root / "path_summary/oos_stage_site_summary.csv"
    hour = root / "hourly_site/oos_hour_site.csv"
    system = root / "grid_hourly/oos_hour_system.csv"
    for item in (path, stage, site, hour, system):
        require(item.is_file(), f"Missing OOS file: {item}")
    frames = {
        "path": pd.read_csv(path),
        "stage": pd.read_csv(stage),
        "site": pd.read_csv(site),
        "hour": pd.read_csv(hour),
        "system": pd.read_csv(system),
    }
    require(len(frames["path"]) == 10000, f"Expected 10000 paths in {path}")
    require(frames["path"]["path_id"].is_unique, f"Duplicate path_id in {path}")
    require(set(frames["path"]["path_id"]) == set(range(1, 10001)), "Path IDs are not 1..10000")
    return frames


def bool_col(frame: pd.DataFrame, name: str) -> pd.Series:
    return frame[name].astype(str).str.lower().isin({"1", "true", "yes"})


def quantiles(values: pd.Series) -> dict[str, float]:
    x = pd.to_numeric(values, errors="coerce").dropna()
    return {f"q{q}": float(x.quantile(q / 100.0)) for q in (5, 25, 50, 75, 95, 99)}


def write_csv(frame: pd.DataFrame, out: Path, name: str) -> None:
    frame.to_csv(out / name, index=False)


def path_metrics(base: pd.DataFrame, cand: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    metrics = [
        "reported_objective",
        "actual_operating_cost",
        "total_H2_production",
        "ordinary_shortage_total",
        "terminal_total_quantity_shortfall",
        "terminal_site_gap",
        "terminal_inventory_total",
        "total_HTT",
        "terminal_penalty_cost",
        "target_total",
    ]
    merged = base.merge(cand, on="path_id", suffixes=("_BASE", "_B0001"), validate="one_to_one")
    rows = []
    for metric in metrics:
        b = pd.to_numeric(merged[f"{metric}_BASE"], errors="coerce")
        c = pd.to_numeric(merged[f"{metric}_B0001"], errors="coerce")
        d = c - b
        row = {
            "metric": metric,
            "base_mean": float(b.mean()),
            "b0001_mean": float(c.mean()),
            "paired_diff_mean": float(d.mean()),
            "paired_diff_median": float(d.median()),
            "paired_win_b0001": int((d < -1e-9).sum()),
            "paired_loss_b0001": int((d > 1e-9).sum()),
            "paired_tie": int((d.abs() <= 1e-9).sum()),
        }
        row.update({f"base_{k}": v for k, v in quantiles(b).items()})
        row.update({f"b0001_{k}": v for k, v in quantiles(c).items()})
        row.update({f"diff_{k}": v for k, v in quantiles(d).items()})
        rows.append(row)
    return merged, pd.DataFrame(rows)


def accounting(frame: pd.DataFrame, arm: str) -> pd.DataFrame:
    term = frame["termination_type"].astype(str)
    diss = bool_col(frame, "physical_dissipation_a1")
    absorbing = bool_col(frame, "lf8_absorbing")
    rows = [
        {"arm": arm, "category": "true_stage7", "count": int((term == "STAGE7_TERMINAL_CHECK").sum())},
        {"arm": arm, "category": "physical_dissipation", "count": int(diss.sum())},
        {"arm": arm, "category": "lf8_absorbing", "count": int(absorbing.sum())},
    ]
    other = ~(term == "STAGE7_TERMINAL_CHECK") & ~diss & ~absorbing
    rows.append({"arm": arm, "category": "other_valid_terminal_reason", "count": int(other.sum())})
    rows.append({"arm": arm, "category": "total_paths", "count": int(len(frame))})
    return pd.DataFrame(rows)


def target_summary(frame: pd.DataFrame, arm: str) -> pd.DataFrame:
    positive = pd.to_numeric(frame["target_total"], errors="coerce") > 1e-9
    gap = pd.to_numeric(frame["terminal_total_quantity_shortfall"], errors="coerce") > 1e-9
    rows = [
        {"arm": arm, "cohort": "zero_target", "count": int((~positive).sum())},
        {"arm": arm, "cohort": "positive_target", "count": int(positive.sum())},
        {"arm": arm, "cohort": "positive_target_adequate", "count": int((positive & ~gap).sum())},
        {"arm": arm, "cohort": "positive_target_shortfall", "count": int((positive & gap).sum())},
    ]
    return pd.DataFrame(rows)


def failure_summary(frame: pd.DataFrame, arm: str) -> pd.DataFrame:
    quantity = pd.to_numeric(frame["terminal_total_quantity_shortfall"], errors="coerce") > 1e-9
    location = pd.to_numeric(frame["terminal_spatial_component"], errors="coerce") > 1e-9
    labels = np.select(
        [~quantity & ~location, quantity & ~location, ~quantity & location, quantity & location],
        ["ADEQUATE", "PURE_QUANTITY", "PURE_LOCATION", "MIXED"],
        default="OTHER",
    )
    out = pd.DataFrame({"arm": arm, "failure_type": labels})
    return out.value_counts(["arm", "failure_type"]).rename("count").reset_index()


def failure_labels(frame: pd.DataFrame) -> pd.Series:
    quantity = pd.to_numeric(frame["terminal_total_quantity_shortfall"], errors="coerce") > 1e-9
    location = pd.to_numeric(frame["terminal_spatial_component"], errors="coerce") > 1e-9
    return pd.Series(
        np.select(
            [~quantity & ~location, quantity & ~location, ~quantity & location, quantity & location],
            ["ADEQUATE", "PURE_QUANTITY", "PURE_LOCATION", "MIXED"],
            default="OTHER",
        ),
        index=frame.index,
    )


def failure_transition(base: pd.DataFrame, cand: pd.DataFrame) -> pd.DataFrame:
    b = base.sort_values("path_id").reset_index(drop=True)
    c = cand.sort_values("path_id").reset_index(drop=True)
    require(b["path_id"].equals(c["path_id"]), "Base/B0001 path IDs differ")
    out = pd.DataFrame({"base_failure_type": failure_labels(b), "b0001_failure_type": failure_labels(c)})
    return out.value_counts(["base_failure_type", "b0001_failure_type"]).rename("count").reset_index()


def positive_target_detail(frame: pd.DataFrame, arm: str) -> pd.DataFrame:
    positive = pd.to_numeric(frame["target_total"], errors="coerce") > 1e-9
    x = frame.loc[positive].copy()
    gap = pd.to_numeric(x["terminal_total_quantity_shortfall"], errors="coerce")
    rows = [{
        "arm": arm,
        "positive_target_paths": int(len(x)),
        "adequate_paths": int((gap <= 1e-9).sum()),
        "shortfall_paths": int((gap > 1e-9).sum()),
        "shortfall_rate": float((gap > 1e-9).mean()),
        "conditional_gap_mean": float(gap[gap > 1e-9].mean()) if (gap > 1e-9).any() else 0.0,
        "conditional_gap_median": float(gap[gap > 1e-9].median()) if (gap > 1e-9).any() else 0.0,
        "conditional_gap_q95": float(gap[gap > 1e-9].quantile(0.95)) if (gap > 1e-9).any() else 0.0,
        "zero_gap_count": int((gap <= 1e-9).sum()),
    }]
    return pd.DataFrame(rows)


def stage_summary(base: pd.DataFrame, cand: pd.DataFrame) -> pd.DataFrame:
    group = ["stage"]
    b = base.groupby(group, as_index=False)[["production_kg", "htt_kg", "ending_inventory_kg", "ordinary_shortage_kg"]].mean()
    c = cand.groupby(group, as_index=False)[["production_kg", "htt_kg", "ending_inventory_kg", "ordinary_shortage_kg"]].mean()
    b = b.rename(columns={x: f"{x}_BASE" for x in b.columns if x != "stage"})
    c = c.rename(columns={x: f"{x}_B0001" for x in c.columns if x != "stage"})
    out = b.merge(c, on="stage", validate="one_to_one")
    for metric in ("production_kg", "htt_kg", "ending_inventory_kg", "ordinary_shortage_kg"):
        out[f"{metric}_diff"] = out[f"{metric}_B0001"] - out[f"{metric}_BASE"]
    return out


def hourly_summary(base: pd.DataFrame, cand: pd.DataFrame) -> pd.DataFrame:
    cols = ["global_hour", "production_kg", "H2_production_kg", "P_EL_kW", "end_inventory_kg", "ordinary_shortage_kg"]
    use = [x for x in cols if x in base.columns and x in cand.columns]
    group_col = "global_hour"
    b = base.groupby(group_col, as_index=False)[use[1:]].mean()
    c = cand.groupby(group_col, as_index=False)[use[1:]].mean()
    b = b.rename(columns={x: f"{x}_BASE" for x in use[1:]})
    c = c.rename(columns={x: f"{x}_B0001" for x in use[1:]})
    out = b.merge(c, on=group_col, validate="one_to_one")
    for metric in use[1:]:
        out[f"{metric}_diff"] = out[f"{metric}_B0001"] - out[f"{metric}_BASE"]
    return out


def figures(out: Path, merged: pd.DataFrame, stages: pd.DataFrame) -> None:
    plt.figure(figsize=(8, 5))
    plt.hist(pd.to_numeric(merged["total_H2_production_B0001"]) - pd.to_numeric(merged["total_H2_production_BASE"]), bins=40, color="#2878b5")
    plt.axvline(0, color="black", linewidth=0.8)
    plt.xlabel("B0001 - Base total H2 production (kg/path)")
    plt.ylabel("Paths")
    plt.tight_layout()
    plt.savefig(out / "01_paired_production_difference.png", dpi=160)
    plt.close()

    plt.figure(figsize=(8, 5))
    plt.plot(stages["stage"], stages["production_kg_BASE"], marker="o", label="Base")
    plt.plot(stages["stage"], stages["production_kg_B0001"], marker="o", label="B0001 exploratory")
    plt.xlabel("Operating stage")
    plt.ylabel("Mean production (kg)")
    plt.legend()
    plt.tight_layout()
    plt.savefig(out / "02_stage_production_mean.png", dpi=160)
    plt.close()

    plt.figure(figsize=(8, 5))
    for arm, col in (("BASE", "#555555"), ("B0001", "#d95f02")):
        values = pd.to_numeric(merged[f"terminal_total_quantity_shortfall_{arm}"], errors="coerce")
        plt.hist(values, bins=40, alpha=0.55, label=arm, color=col)
    plt.xlabel("Terminal total quantity shortfall (kg/path)")
    plt.ylabel("Paths")
    plt.legend()
    plt.tight_layout()
    plt.savefig(out / "03_terminal_quantity_shortfall.png", dpi=160)
    plt.close()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--run-dir", type=Path, required=True)
    args = parser.parse_args()
    repo = args.repo.resolve()
    run = args.run_dir.resolve()
    out = run / "05_exploratory_analysis_v2"
    out.mkdir(parents=True, exist_ok=False)
    base = read_arm(repo / BASE)
    cand = read_arm(run / "04_oos_b0001")
    merged, paired = path_metrics(base["path"], cand["path"])
    write_csv(accounting(base["path"], "BASE"), out, "01_oos_accounting_base.csv")
    write_csv(accounting(cand["path"], "B0001_EXPLORATORY"), out, "01_oos_accounting_b0001.csv")
    target = pd.concat(
        [target_summary(base["path"], "BASE"), target_summary(cand["path"], "B0001_EXPLORATORY")],
        ignore_index=True,
    )
    write_csv(target, out, "02_positive_target_summary.csv")
    write_csv(paired, out, "03_paired_path_metrics.csv")
    write_csv(failure_summary(base["path"], "BASE").merge(failure_summary(cand["path"], "B0001_EXPLORATORY"), how="outer", on="failure_type", suffixes=("_BASE", "_B0001")), out, "04_failure_type_summary.csv")
    write_csv(failure_transition(base["path"], cand["path"]), out, "04_base_to_b0001_failure_transition.csv")
    positive_detail = pd.concat(
        [positive_target_detail(base["path"], "BASE"), positive_target_detail(cand["path"], "B0001_EXPLORATORY")],
        ignore_index=True,
    )
    write_csv(positive_detail, out, "02_positive_target_detail.csv")
    stages = stage_summary(base["stage"], cand["stage"])
    hours = hourly_summary(base["hour"], cand["hour"])
    write_csv(stages, out, "05_stage_mean_comparison.csv")
    write_csv(hours, out, "06_hour_mean_comparison.csv")
    write_csv(pd.DataFrame([{
        "analysis_status": "EXPLORATORY_ONLY",
        "formal_training_acceptance": "B0001_FAIL_UNSTABLE",
        "candidate": "B0001",
        "oos_paths": 10000,
        "base_reference": "accepted Stage89Q penalty1000 OOS",
        "same_ordered_bank": True,
        "formal_dual_candidate_claim": False,
    }]), out, "00_analysis_scope.csv")
    figures(out, merged, stages)
    print(f"EXPLORATORY_ANALYSIS_PASS output={out}")


if __name__ == "__main__":
    main()
