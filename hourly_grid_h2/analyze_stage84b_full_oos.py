from __future__ import annotations

import argparse
import hashlib
import math
from pathlib import Path

import numpy as np
import pandas as pd


CORE_METRICS = {
    "terminal_inventory": "total_terminal_inventory_kg",
    "terminal_gap": "terminal_gap_kg",
    "ordinary_shortage": "ordinary_shortage_kg",
    "total_production": "total_production_kg",
    "site1_production": "site1_production_kg",
    "site2_production": "site2_production_kg",
    "site3_production": "site3_production_kg",
    "site4_production": "site4_production_kg",
    "total_htt": "total_htt_kg",
    "operating_cost": "operating_cost",
    "total_cost": "total_cost",
    "grid_procurement": "grid_import_kwh",
}

GRID_METRICS = [
    "minimum_voltage_pu",
    "max_true_branch_mva",
    "max_branch_utilization",
    "site1_grid_limited_frequency",
    "site2_grid_limited_frequency",
    "site3_grid_limited_frequency",
    "site4_grid_limited_frequency",
    "site1_average_p_el_kw",
    "site2_average_p_el_kw",
    "site3_average_p_el_kw",
    "site4_average_p_el_kw",
    "grid_import_kwh",
    "pv_available_kwh",
    "pv_utilized_kwh",
    "pv_curtailed_kwh",
]

HTT_ARCS = [f"htt_{i}_to_{j}_kg" for i in range(1, 5) for j in range(1, 5) if i != j]


def q(x: pd.Series | np.ndarray, probability: float) -> float:
    values = np.asarray(x, dtype=float)
    values = values[np.isfinite(values)]
    return float(np.quantile(values, probability)) if len(values) else math.nan


def describe(x: pd.Series | np.ndarray, prefix: str) -> dict[str, float]:
    values = np.asarray(x, dtype=float)
    values = values[np.isfinite(values)]
    if not len(values):
        return {f"{prefix}_{name}": math.nan for name in
                ("mean", "median", "std", "q90", "q95", "q99", "q995", "min", "max")}
    return {
        f"{prefix}_mean": float(np.mean(values)),
        f"{prefix}_median": float(np.median(values)),
        f"{prefix}_std": float(np.std(values, ddof=1)) if len(values) > 1 else 0.0,
        f"{prefix}_q90": q(values, 0.90),
        f"{prefix}_q95": q(values, 0.95),
        f"{prefix}_q99": q(values, 0.99),
        f"{prefix}_q995": q(values, 0.995),
        f"{prefix}_min": float(np.min(values)),
        f"{prefix}_max": float(np.max(values)),
    }


def correlation(x: pd.Series, y: pd.Series) -> float:
    frame = pd.DataFrame({"x": x, "y": y}).replace([np.inf, -np.inf], np.nan).dropna()
    if len(frame) < 2 or frame.x.nunique() < 2 or frame.y.nunique() < 2:
        return math.nan
    return float(frame.x.corr(frame.y))


def safe_csv(frame: pd.DataFrame, path: Path) -> None:
    temp = path.with_suffix(path.suffix + ".tmp")
    frame.to_csv(temp, index=False)
    temp.replace(path)


def validate_inputs(run_dir: Path) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    saa = pd.read_csv(run_dir / "01-saa-oos" / "oos_path_summary.csv")
    dro = pd.read_csv(run_dir / "02-dro-oos" / "oos_path_summary.csv")
    saa_stage = pd.read_csv(run_dir / "01-saa-oos" / "oos_stage_site_response.csv")
    dro_stage = pd.read_csv(run_dir / "02-dro-oos" / "oos_stage_site_response.csv")
    expected = np.arange(1, 10001)
    for name, frame in (("SAA", saa), ("DRO", dro)):
        if len(frame) != 10000 or frame.path_id.duplicated().any() or not np.array_equal(frame.path_id, expected):
            raise RuntimeError(f"{name} path identity is incomplete or duplicated")
    if not np.array_equal(saa.path_id, dro.path_id) or not np.array_equal(saa.state_sequence, dro.state_sequence):
        raise RuntimeError("SAA/DRO common path identity mismatch")
    for name, frame in (("SAA", saa_stage), ("DRO", dro_stage)):
        if len(frame) != 320000 or frame.duplicated(["path_id", "stage", "site"]).any():
            raise RuntimeError(f"{name} stage/site table is incomplete or duplicated")
    for method_dir in (run_dir / "01-saa-oos", run_dir / "02-dro-oos"):
        meta = pd.read_csv(method_dir / "oos_metadata.csv").iloc[0]
        if int(meta.completed_paths) != 10000 or int(meta.constraint_violations) != 0:
            raise RuntimeError(f"Method completion gate failed: {method_dir.name}")
        if len(list((method_dir / "hourly-batches").glob("*.mat"))) != 400:
            raise RuntimeError(f"Hourly batch count is not 400: {method_dir.name}")
    return saa, dro, saa_stage, dro_stage


def build_paired(saa: pd.DataFrame, dro: pd.DataFrame) -> pd.DataFrame:
    paired = pd.DataFrame({"path_id": saa.path_id, "state_sequence": saa.state_sequence})
    columns = sorted(set(CORE_METRICS.values()) | set(GRID_METRICS) |
                     set(HTT_ARCS) | {f"final_inventory_site{i}_kg" for i in range(1, 5)})
    for column in columns:
        if column not in saa or column not in dro:
            continue
        paired[f"saa_{column}"] = saa[column]
        paired[f"dro_{column}"] = dro[column]
        paired[f"delta_{column}"] = dro[column] - saa[column]
    return paired


def overall_summary(saa: pd.DataFrame, dro: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for metric, column in CORE_METRICS.items():
        delta = dro[column] - saa[column]
        row: dict[str, object] = {"metric": metric, "source_column": column, "n": len(delta)}
        row.update(describe(saa[column], "saa"))
        row.update(describe(dro[column], "dro"))
        row.update(describe(delta, "delta"))
        se = float(delta.std(ddof=1) / math.sqrt(len(delta)))
        row["paired_mean_difference"] = float(delta.mean())
        row["paired_mean_ci95_low"] = float(delta.mean() - 1.96 * se)
        row["paired_mean_ci95_high"] = float(delta.mean() + 1.96 * se)
        row["paired_median_difference"] = float(delta.median())
        equal = np.isclose(delta, 0.0, atol=1e-9, rtol=0)
        row["dro_gt_saa_count"] = int((delta > 1e-9).sum())
        row["dro_eq_saa_count"] = int(equal.sum())
        row["dro_lt_saa_count"] = int((delta < -1e-9).sum())
        row["dro_gt_saa_ratio"] = row["dro_gt_saa_count"] / len(delta)
        row["dro_eq_saa_ratio"] = row["dro_eq_saa_count"] / len(delta)
        row["dro_lt_saa_ratio"] = row["dro_lt_saa_count"] / len(delta)
        rows.append(row)
    return pd.DataFrame(rows)


def difference_bins(saa: pd.DataFrame, dro: pd.DataFrame) -> pd.DataFrame:
    rows = []
    kg_edges = [-np.inf, -100, -50, -20, -10, -1, 1, 10, 20, 50, 100, np.inf]
    cost_edges = [-np.inf, -100000, -50000, -10000, -1000, -1, 1, 1000, 10000, 50000, 100000, np.inf]
    grid_edges = [-np.inf, -10000, -5000, -1000, -100, -1, 1, 100, 1000, 5000, 10000, np.inf]
    for metric, column in CORE_METRICS.items():
        delta = dro[column] - saa[column]
        edges = cost_edges if "cost" in metric else grid_edges if metric == "grid_procurement" else kg_edges
        for low, high in zip(edges[:-1], edges[1:]):
            selected = (delta > low) & (delta <= high)
            rows.append({"metric": metric, "lower_exclusive": low, "upper_inclusive": high,
                         "count": int(selected.sum()), "proportion": float(selected.mean())})
    return pd.DataFrame(rows)


def tail_summary(saa: pd.DataFrame, dro: pd.DataFrame) -> pd.DataFrame:
    specs = [
        ("high_terminal_gap", "terminal_gap_kg", "high"),
        ("high_total_cost", "total_cost", "high"),
        ("high_ordinary_shortage", "ordinary_shortage_kg", "high"),
        ("lowest_voltage", "minimum_voltage_pu", "low"),
        ("highest_branch_loading", "max_branch_utilization", "high"),
        ("highest_site3_grid_limited", "site3_grid_limited_frequency", "high"),
    ]
    rows = []
    for method, frame in (("saa", saa), ("chi2_eta003", dro)):
        for label, column, direction in specs:
            threshold = q(frame[column], 0.05 if direction == "low" else 0.95)
            selected = frame[frame[column] <= threshold] if direction == "low" else frame[frame[column] >= threshold]
            ordered = selected.nsmallest(20, column) if direction == "low" else selected.nlargest(20, column)
            rows.append({"tail": label, "method": method, "column": column, "direction": direction,
                         "threshold": threshold, "path_count": len(selected),
                         "tail_mean": float(selected[column].mean()),
                         "tail_extreme": float(selected[column].min() if direction == "low" else selected[column].max()),
                         "top_path_ids": ";".join(map(str, ordered.path_id.astype(int)))})
    return pd.DataFrame(rows)


def grid_summaries(saa: pd.DataFrame, dro: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    rows = []
    location_rows = []
    for method, frame in (("saa", saa), ("chi2_eta003", dro)):
        for column in GRID_METRICS:
            row = {"method": method, "metric": column, "n": int(frame[column].notna().sum())}
            row.update(describe(frame[column], "value")); rows.append(row)
        voltage = frame.groupby(["min_voltage_bus", "min_voltage_hour"], dropna=False).size().reset_index(name="count")
        voltage["method"] = method;voltage["binding_type"] = "minimum_voltage"
        voltage = voltage.rename(columns={"min_voltage_bus": "location_1", "min_voltage_hour": "hour"})
        voltage["location_2"] = np.nan
        branch = frame.groupby(["max_branch_from", "max_branch_to", "max_branch_hour"], dropna=False).size().reset_index(name="count")
        branch["method"] = method;branch["binding_type"] = "maximum_branch_utilization"
        branch = branch.rename(columns={"max_branch_from": "location_1", "max_branch_to": "location_2", "max_branch_hour": "hour"})
        location_rows.extend([voltage, branch])
    return pd.DataFrame(rows), pd.concat(location_rows, ignore_index=True)[
        ["method", "binding_type", "location_1", "location_2", "hour", "count"]]


def add_htt_net(frame: pd.DataFrame) -> pd.DataFrame:
    out = frame.copy()
    for site in range(1, 5):
        incoming = sum((out[f"htt_{other}_to_{site}_kg"] for other in range(1, 5) if other != site))
        outgoing = sum((out[f"htt_{site}_to_{other}_kg"] for other in range(1, 5) if other != site))
        out[f"site{site}_net_htt_kg"] = incoming - outgoing
    return out


def site3_summaries(saa: pd.DataFrame, dro: pd.DataFrame,
                    saa_stage: pd.DataFrame, dro_stage: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    group_rows = []
    stage_rows = []
    corr_rows = []
    metrics = ["site3_average_p_el_kw", "site3_production_kg", "final_inventory_site3_kg",
               "other_site_production_kg", "other_site_inventory_kg", "total_htt_kg",
               "site3_net_htt_kg", "terminal_gap_kg", "ordinary_shortage_kg", "total_cost"]
    for method, original, stages in (("saa", saa, saa_stage), ("chi2_eta003", dro, dro_stage)):
        frame = add_htt_net(original)
        frame["other_site_production_kg"] = frame.total_production_kg - frame.site3_production_kg
        frame["other_site_inventory_kg"] = frame.total_terminal_inventory_kg - frame.final_inventory_site3_kg
        frame["site3_limited_group"] = np.where(frame.site3_grid_limited_count > 0, "limited", "non_limited")
        for group, selected in frame.groupby("site3_limited_group"):
            row: dict[str, object] = {"method": method, "group": group, "path_count": len(selected)}
            for metric in metrics:
                row[f"{metric}_mean"] = float(selected[metric].mean())
                row[f"{metric}_median"] = float(selected[metric].median())
            group_rows.append(row)
        pairs = [
            ("site3_min_voltage_to_p_el", "site3_min_voltage_pu", "site3_average_p_el_kw"),
            ("site3_limit_to_production", "site3_grid_limited_frequency", "site3_production_kg"),
            ("site3_limit_to_inventory", "site3_grid_limited_frequency", "final_inventory_site3_kg"),
            ("site3_limit_to_other_production", "site3_grid_limited_frequency", "other_site_production_kg"),
            ("site3_limit_to_total_htt", "site3_grid_limited_frequency", "total_htt_kg"),
            ("site3_limit_to_terminal_gap", "site3_grid_limited_frequency", "terminal_gap_kg"),
        ]
        for label, x, y in pairs:
            corr_rows.append({"method": method, "relationship": label, "x": x, "y": y,
                              "pearson_correlation": correlation(frame[x], frame[y])})
        site3 = stages[(stages.site == 3) & (stages.status == "normal")].copy()
        limited_map = frame.set_index("path_id")["site3_limited_group"]
        site3["path_group"] = site3.path_id.map(limited_map)
        stage_metrics = ["site_min_voltage_pu", "average_p_el_kw", "production_kg", "ending_inventory_kg",
                         "htt_in_kg", "htt_out_kg", "net_htt_kg", "shortage_kg"]
        for (stage, group), selected in site3.groupby(["stage", "path_group"]):
            row = {"method": method, "stage": int(stage), "path_group": group, "records": len(selected)}
            for metric in stage_metrics:
                row[f"{metric}_mean"] = float(selected[metric].mean())
            stage_rows.append(row)
    return pd.DataFrame(group_rows), pd.DataFrame(stage_rows), pd.DataFrame(corr_rows)


def htt_summaries(saa: pd.DataFrame, dro: pd.DataFrame,
                  saa_stage: pd.DataFrame, dro_stage: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    direction_rows = []
    state_rows = []
    for method, frame, stages in (("saa", saa, saa_stage), ("chi2_eta003", dro, dro_stage)):
        frame = add_htt_net(frame)
        for column in ["total_htt_kg", *HTT_ARCS, *[f"site{i}_net_htt_kg" for i in range(1, 5)]]:
            row = {"method": method, "flow": column};row.update(describe(frame[column], "value"));direction_rows.append(row)
        normal = stages[stages.status == "normal"]
        grouped = normal.groupby(["stage", "markov_state", "site"], as_index=False).agg(
            records=("path_id", "size"), htt_in_mean=("htt_in_kg", "mean"),
            htt_out_mean=("htt_out_kg", "mean"), net_htt_mean=("net_htt_kg", "mean"),
            inventory_mean=("ending_inventory_kg", "mean"), production_mean=("production_kg", "mean"))
        grouped.insert(0, "method", method);state_rows.append(grouped)
    return pd.DataFrame(direction_rows), pd.concat(state_rows, ignore_index=True)


def pv_summary(saa: pd.DataFrame, dro: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for method, frame in (("saa", saa), ("chi2_eta003", dro)):
        row: dict[str, object] = {"method": method, "paths": len(frame)}
        for column in ("pv_available_kwh", "pv_utilized_kwh", "pv_curtailed_kwh",
                       "pv_utilization_ratio", "grid_import_kwh"):
            row.update(describe(frame[column], column))
        row["corr_pv_used_grid_import"] = correlation(frame.pv_utilized_kwh, frame.grid_import_kwh)
        row["corr_pv_used_min_voltage"] = correlation(frame.pv_utilized_kwh, frame.minimum_voltage_pu)
        row["corr_pv_used_total_production"] = correlation(frame.pv_utilized_kwh, frame.total_production_kg)
        rows.append(row)
    return pd.DataFrame(rows)


def representatives(saa: pd.DataFrame, dro: pd.DataFrame) -> pd.DataFrame:
    candidates: list[dict[str, object]] = []

    def select(reason: str, method: str, frame: pd.DataFrame, column: str, largest: bool = True) -> None:
        idx = frame[column].idxmax() if largest else frame[column].idxmin()
        candidates.append({"path_id": int(frame.loc[idx, "path_id"]), "reason": reason,
                           "method": method, "metric": column, "metric_value": float(frame.loc[idx, column])})

    for method, frame in (("saa", saa), ("chi2_eta003", dro)):
        select("highest_total_cost", method, frame, "total_cost")
        select("highest_terminal_gap", method, frame, "terminal_gap_kg")
        select("highest_ordinary_shortage", method, frame, "ordinary_shortage_kg")
        select("lowest_voltage", method, frame, "minimum_voltage_pu", False)
        select("highest_branch_utilization", method, frame, "max_branch_utilization")
        select("highest_site3_grid_limited_frequency", method, frame, "site3_grid_limited_frequency")
        select("highest_htt", method, frame, "total_htt_kg")
    paired_specs = [
        ("largest_dro_minus_saa_production", "total_production_kg", "max"),
        ("largest_dro_minus_saa_final_inventory", "total_terminal_inventory_kg", "max"),
        ("largest_dro_minus_saa_htt", "total_htt_kg", "max"),
        ("largest_terminal_gap_improvement", "terminal_gap_kg", "min"),
        ("largest_terminal_gap_deterioration", "terminal_gap_kg", "max"),
        ("largest_absolute_cost_difference", "total_cost", "abs"),
    ]
    for reason, column, mode in paired_specs:
        delta = dro[column] - saa[column]
        idx = delta.idxmin() if mode == "min" else delta.abs().idxmax() if mode == "abs" else delta.idxmax()
        candidates.append({"path_id": int(saa.loc[idx, "path_id"]), "reason": reason, "method": "paired",
                           "metric": f"delta_{column}", "metric_value": float(delta.loc[idx])})
    selected = pd.DataFrame(candidates)
    rows = []
    for path_id, group in selected.groupby("path_id", sort=False):
        i = int(path_id) - 1
        rows.append({"path_id": int(path_id), "state_sequence": saa.loc[i, "state_sequence"],
                     "selection_reasons": ";".join(group.reason),
                     "selection_methods": ";".join(group.method),
                     "selection_metrics": ";".join(group.metric),
                     "selection_values": ";".join(f"{v:.12g}" for v in group.metric_value),
                     "saa_total_cost": saa.loc[i, "total_cost"], "dro_total_cost": dro.loc[i, "total_cost"],
                     "saa_terminal_gap_kg": saa.loc[i, "terminal_gap_kg"],
                     "dro_terminal_gap_kg": dro.loc[i, "terminal_gap_kg"]})
    return pd.DataFrame(rows)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def line_count(path: Path) -> int:
    with path.open("rb") as stream:
        return max(0, sum(chunk.count(b"\n") for chunk in iter(lambda: stream.read(1024 * 1024), b"")) - 1)


def build_manifest(run_dir: Path) -> pd.DataFrame:
    metadata: dict[str, dict[str, object]] = {}
    for method_dir in (run_dir / "01-saa-oos", run_dir / "02-dro-oos"):
        table = pd.read_csv(method_dir / "file_manifest.csv")
        for row in table.to_dict("records"):
            metadata[str(row["relative_path"]).replace("\\", "/")] = row
    rows = []
    excluded = {"RUNNING_STATUS.txt", "README.md", "final_judgment.txt", "large_file_manifest.csv"}
    for path in sorted(run_dir.rglob("*")):
        if not path.is_file() or path.name.endswith(".tmp") or "logs" in path.parts or path.name in excluded:
            continue
        relative = path.relative_to(run_dir).as_posix()
        local = metadata.get(relative, {})
        method = "saa" if relative.startswith("01-saa-oos/") else "chi2_eta003" if relative.startswith("02-dro-oos/") else "analysis"
        records = local.get("record_count", line_count(path) if path.suffix.lower() == ".csv" else math.nan)
        rows.append({"relative_path": relative, "method": method,
                     "first_path_id": local.get("first_path_id", math.nan),
                     "last_path_id": local.get("last_path_id", math.nan),
                     "record_count_or_dimensions": records, "bytes": path.stat().st_size,
                     "sha256": sha256(path), "schema": local.get("schema", path.suffix.lower().lstrip(".")),
                     "completed_closed": True})
    return pd.DataFrame(rows)


def write_readme(run_dir: Path, commits: dict[str, str]) -> None:
    text = f"""# Stage-84B 全量共路径 OOS 与逐路径分析

- 状态：已完成并通过机械核验
- 正式训练 commit：`{commits['training']}`
- OOS schema 修复 commit：`{commits['fix']}`
- OOS runner commit：`{commits['run']}`
- 样本：SAA 与 Pearson chi-square DRO eta=0.03 各10000条，共用冻结路径
- 小时输出：每25条路径一个安全关闭的 MATLAB v7.3 batch

本目录评价的是主 FA-MSP policy 的库存、TerminalLOH gap、正常供氢、生产、HTT、成本和电网响应。
这里没有执行 W1-W3 灾后 recourse，因此不得把任何尾部结果解释为真实灾后 EENS 或 EENS tail。
"""
    temp = run_dir / "README.md.tmp"
    temp.write_text(text, encoding="utf-8")
    temp.replace(run_dir / "README.md")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-dir", required=True, type=Path)
    parser.add_argument("--training-commit", required=True)
    parser.add_argument("--oos-fix-commit", required=True)
    parser.add_argument("--oos-run-commit", required=True)
    args = parser.parse_args()
    run_dir = args.run_dir.resolve();analysis_dir = run_dir / "03-analysis"
    saa, dro, saa_stage, dro_stage = validate_inputs(run_dir)
    paired = build_paired(saa, dro)
    safe_csv(paired, analysis_dir / "paired_path_comparison.csv")
    safe_csv(overall_summary(saa, dro), analysis_dir / "overall_paired_summary.csv")
    safe_csv(difference_bins(saa, dro), analysis_dir / "paired_difference_bins.csv")
    safe_csv(tail_summary(saa, dro), analysis_dir / "tail_summary.csv")
    grid, locations = grid_summaries(saa, dro)
    safe_csv(grid, analysis_dir / "grid_h2_summary.csv")
    safe_csv(locations, analysis_dir / "grid_binding_location_summary.csv")
    site3, site3_stage, site3_corr = site3_summaries(saa, dro, saa_stage, dro_stage)
    safe_csv(site3, analysis_dir / "site3_mechanism_summary.csv")
    safe_csv(site3_stage, analysis_dir / "site3_stage_mechanism_summary.csv")
    safe_csv(site3_corr, analysis_dir / "site3_mechanism_correlations.csv")
    htt, htt_stage = htt_summaries(saa, dro, saa_stage, dro_stage)
    safe_csv(htt, analysis_dir / "htt_direction_summary.csv")
    safe_csv(htt_stage, analysis_dir / "htt_stage_state_summary.csv")
    safe_csv(pv_summary(saa, dro), analysis_dir / "pv_grid_summary.csv")
    safe_csv(representatives(saa, dro), analysis_dir / "representative_path_index.csv")
    integrity = pd.DataFrame([{
        "saa_paths": len(saa), "dro_paths": len(dro), "common_paths": len(paired),
        "path_ids_identical": True, "state_sequences_identical": True,
        "saa_stage_site_rows": len(saa_stage), "dro_stage_site_rows": len(dro_stage),
        "saa_hourly_batches": 400, "dro_hourly_batches": 400,
        "failed_paths": 0, "skipped_paths": 0, "pass": True,
    }])
    safe_csv(integrity, analysis_dir / "sample_integrity_audit.csv")
    manifest = build_manifest(run_dir)
    safe_csv(manifest, run_dir / "large_file_manifest.csv")
    commits = {"training": args.training_commit, "fix": args.oos_fix_commit, "run": args.oos_run_commit}
    write_readme(run_dir, commits)
    judgment = (
        "FINAL_JUDGMENT=PASS_COMPLETE_10000_PAIRED_OOS\n"
        f"TRAINING_COMMIT={args.training_commit}\n"
        f"OOS_FIX_COMMIT={args.oos_fix_commit}\n"
        f"OOS_RUN_COMMIT={args.oos_run_commit}\n"
        "N_SAA=10000\nN_DRO=10000\nN_COMMON=10000\n"
        "FAILED_PATHS=0\nSKIPPED_PATHS=0\n"
        "FORMAL_W1_W3_RECOURSE_RUN=false\n"
    )
    temp = run_dir / "final_judgment.txt.tmp"
    temp.write_text(judgment, encoding="utf-8")
    temp.replace(run_dir / "final_judgment.txt")


if __name__ == "__main__":
    main()
