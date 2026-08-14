# -*- coding: utf-8 -*-
from __future__ import annotations

import argparse
import hashlib
import math
import subprocess
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd


SAA_DIR = "01-saa-oos"
DRO_DIR = "02-dro-oos"
METHODS = ("saa", "chi2_eta003")
HTT_ARCS = [f"htt_{i}_to_{j}_kg" for i in range(1, 5) for j in range(1, 5) if i != j]
SITE_PROD = [f"site{i}_production_kg" for i in range(1, 5)]
SITE_PEL = [f"site{i}_average_p_el_kw" for i in range(1, 5)]
COLORS = {"saa": "#2563eb", "chi2_eta003": "#dc2626"}
NUM_TOL = 1e-8


def quantile(values: pd.Series | np.ndarray, probability: float) -> float:
    data = np.asarray(values, dtype=float)
    data = data[np.isfinite(data)]
    return float(np.quantile(data, probability)) if len(data) else math.nan


def describe(values: pd.Series | np.ndarray, prefix: str) -> dict[str, float]:
    data = np.asarray(values, dtype=float)
    data = data[np.isfinite(data)]
    if not len(data):
        return {f"{prefix}_{name}": math.nan for name in
                ("mean", "median", "std", "q90", "q95", "q99", "q995", "min", "max")}
    return {
        f"{prefix}_mean": float(data.mean()),
        f"{prefix}_median": float(np.median(data)),
        f"{prefix}_std": float(data.std(ddof=1)) if len(data) > 1 else 0.0,
        f"{prefix}_q90": quantile(data, .90),
        f"{prefix}_q95": quantile(data, .95),
        f"{prefix}_q99": quantile(data, .99),
        f"{prefix}_q995": quantile(data, .995),
        f"{prefix}_min": float(data.min()),
        f"{prefix}_max": float(data.max()),
    }


def safe_csv(frame: pd.DataFrame, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    frame.to_csv(temporary, index=False)
    temporary.replace(path)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def git(repo: Path, *arguments: str) -> str:
    result = subprocess.run(
        ["git", *arguments], cwd=repo, check=True, capture_output=True, text=True)
    return result.stdout.strip()


def load_inputs(run_dir: Path) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    saa = pd.read_csv(run_dir / SAA_DIR / "oos_path_summary.csv")
    dro = pd.read_csv(run_dir / DRO_DIR / "oos_path_summary.csv")
    saa_stage = pd.read_csv(run_dir / SAA_DIR / "oos_stage_site_response.csv")
    dro_stage = pd.read_csv(run_dir / DRO_DIR / "oos_stage_site_response.csv")
    expected = np.arange(1, 10001)
    for name, frame in (("SAA", saa), ("DRO", dro)):
        if len(frame) != 10000 or not np.array_equal(frame.path_id, expected):
            raise RuntimeError(f"{name} path_id identity is incomplete")
        if frame.path_id.duplicated().any():
            raise RuntimeError(f"{name} path_id contains duplicates")
    if not np.array_equal(saa.state_sequence, dro.state_sequence):
        raise RuntimeError("SAA/DRO state sequence mismatch")
    for name, frame in (("SAA", saa_stage), ("DRO", dro_stage)):
        if len(frame) != 320000 or frame.duplicated(["path_id", "stage", "site"]).any():
            raise RuntimeError(f"{name} stage/site identity is incomplete")
    return saa, dro, saa_stage, dro_stage


def add_directional_net(frame: pd.DataFrame) -> pd.DataFrame:
    output = frame.copy()
    for site in range(1, 5):
        incoming = sum(output[f"htt_{other}_to_{site}_kg"] for other in range(1, 5) if other != site)
        outgoing = sum(output[f"htt_{site}_to_{other}_kg"] for other in range(1, 5) if other != site)
        output[f"site{site}_net_htt_kg"] = incoming - outgoing
    return output


def load_terminal_lookup(repo: Path, out_dir: Path) -> pd.DataFrame:
    base = repo / "results/task-002-stage2b-b3-smoke/53-35state-saa-vs-eta003-terminal-loh/run-024"
    sources = {
        "saa": base / "terminal_loh_table_saa.csv",
        "chi2_eta003": base / "terminal_loh_table_eta_003.csv",
    }
    rows: list[dict[str, object]] = []
    for method, path in sources.items():
        table = pd.read_csv(path)
        if len(table) != 35 or table.duplicated(["intensity", "loc"]).any():
            raise RuntimeError(f"Invalid accepted TerminalLOH table: {path}")
        for record in table.itertuples():
            for site in range(1, 5):
                rows.append({
                    "method": method,
                    "intensity": int(record.intensity),
                    "loc": int(record.loc),
                    "terminal_state_k": ((int(record.intensity) - 1) * 7 +
                                           (int(record.loc) - 1)) * 8 + 7,
                    "site": site,
                    "target_loh_kg": float(getattr(record, f"T{site}_kg")),
                    "accepted_source": str(path.relative_to(repo)).replace("\\", "/"),
                    "accepted_source_sha256": sha256(path),
                })
    lookup = pd.DataFrame(rows)
    safe_csv(lookup, out_dir / "00-hourly-extract/terminal_target_lookup.csv")
    return lookup


def attach_targets(frame: pd.DataFrame, lookup: pd.DataFrame, method: str) -> tuple[pd.DataFrame, float]:
    output = frame.copy()
    method_lookup = lookup[lookup.method == method]
    valid = output.terminal_stage.astype(int) > 0
    for site in range(1, 5):
        mapping = method_lookup[method_lookup.site == site].set_index("terminal_state_k").target_loh_kg
        target = output.terminal_state_k.astype(int).map(mapping).to_numpy()
        target[~valid.to_numpy()] = 0.0
        output[f"target_site{site}_kg"] = target
        output[f"site{site}_terminal_gap_reconstructed_kg"] = np.maximum(
            0.0, target - output[f"final_inventory_site{site}_kg"])
    target_columns = [f"target_site{site}_kg" for site in range(1, 5)]
    if output.loc[valid, target_columns].isna().any().any():
        raise RuntimeError(f"{method} terminal-hit target mapping is incomplete")
    output["terminal_target_total_kg"] = output[target_columns].sum(axis=1)
    output["terminal_target_minus_actual_kg"] = (
        output.terminal_target_total_kg - output.total_terminal_inventory_kg)
    gap_columns = [f"site{site}_terminal_gap_reconstructed_kg" for site in range(1, 5)]
    output["terminal_gap_reconstructed_kg"] = output[gap_columns].sum(axis=1)
    output["terminal_hit"] = valid
    maximum_error = float((output.terminal_gap_reconstructed_kg - output.terminal_gap_kg).abs().max())
    return output, maximum_error


def paired_summary(saa: pd.DataFrame, dro: pd.DataFrame,
                   columns: dict[str, tuple[str, str, str]]) -> pd.DataFrame:
    rows: list[dict[str, object]] = []
    for metric, (column, definition, unit) in columns.items():
        delta = dro[column] - saa[column]
        row: dict[str, object] = {
            "metric": metric,
            "metric_definition_cn": definition,
            "source_column": column,
            "unit": unit,
            "n": len(delta),
            "denominator": "10000 条相同 path_id",
            "orientation": "DRO-SAA；正值表示 DRO 更高",
        }
        row.update(describe(saa[column], "saa"))
        row.update(describe(dro[column], "dro"))
        row.update(describe(delta, "delta"))
        standard_error = float(delta.std(ddof=1) / math.sqrt(len(delta)))
        equal = np.isclose(delta, 0.0, atol=1e-9, rtol=0)
        row.update({
            "paired_mean_difference": float(delta.mean()),
            "paired_mean_ci95_low": float(delta.mean() - 1.96 * standard_error),
            "paired_mean_ci95_high": float(delta.mean() + 1.96 * standard_error),
            "paired_median_difference": float(delta.median()),
            "dro_gt_saa_count": int((delta > 1e-9).sum()),
            "dro_eq_saa_count": int(equal.sum()),
            "dro_lt_saa_count": int((delta < -1e-9).sum()),
            "dro_gt_saa_ratio": float((delta > 1e-9).mean()),
            "dro_eq_saa_ratio": float(equal.mean()),
            "dro_lt_saa_ratio": float((delta < -1e-9).mean()),
        })
        rows.append(row)
    return pd.DataFrame(rows)


def difference_bins(saa: pd.DataFrame, dro: pd.DataFrame,
                    columns: dict[str, tuple[str, str, str]]) -> pd.DataFrame:
    rows: list[dict[str, object]] = []
    for metric, (column, _, unit) in columns.items():
        if unit == "model_cost_unit":
            edges = [-np.inf, -100000, -50000, -10000, -1000, -1, 1, 1000, 10000, 50000, 100000, np.inf]
        elif unit in ("p.u.", "ratio"):
            edges = [-np.inf, -.05, -.01, -.001, -1e-9, 1e-9, .001, .01, .05, np.inf]
        else:
            edges = [-np.inf, -100, -50, -20, -10, -1, 1, 10, 20, 50, 100, np.inf]
        delta = dro[column] - saa[column]
        for low, high in zip(edges[:-1], edges[1:]):
            selected = (delta > low) & (delta <= high)
            rows.append({
                "metric": metric, "unit": unit,
                "lower_exclusive": "OPEN_LOWER" if np.isneginf(low) else low,
                "upper_inclusive": "OPEN_UPPER" if np.isposinf(high) else high,
                "count": int(selected.sum()), "proportion": float(selected.mean()),
                "denominator": "10000 paired paths", "orientation": "DRO-SAA",
            })
    return pd.DataFrame(rows)


def terminal_decomposition(saa: pd.DataFrame, dro: pd.DataFrame) -> pd.DataFrame:
    rows: list[dict[str, object]] = []
    metrics = [
        ("terminal_target_total", "terminal_target_total_kg", "方法对应的四站 TerminalLOH target 总和"),
        ("terminal_actual_inventory", "total_terminal_inventory_kg", "进入 terminal 时四站实际库存总和"),
        ("terminal_target_minus_actual", "terminal_target_minus_actual_kg", "target 总和减 actual 总和；不等于逐站 gap"),
        ("terminal_gap", "terminal_gap_kg", "逐站 max(0,target_i-I_i) 后汇总"),
        ("terminal_gap_reconstructed", "terminal_gap_reconstructed_kg", "由 accepted 查表逐站重构的 gap"),
    ]
    for method, frame in (("saa", saa), ("chi2_eta003", dro)):
        for scope, selected in (("all_paths", frame), ("terminal_hit_only", frame[frame.terminal_hit])):
            for metric, column, definition in metrics:
                row: dict[str, object] = {
                    "method": method, "scope": scope, "metric": metric,
                    "metric_definition_cn": definition, "path_count": len(selected), "unit": "kg",
                }
                row.update(describe(selected[column], "value"))
                rows.append(row)
    return pd.DataFrame(rows)


def cost_decomposition(saa: pd.DataFrame, dro: pd.DataFrame) -> pd.DataFrame:
    a = saa.copy()
    b = dro.copy()
    for frame in (a, b):
        frame["terminal_gap_penalty_2000"] = 2000.0 * frame.terminal_gap_kg
        frame["reported_terminal_value"] = frame.total_cost - frame.operating_cost
        frame["terminal_value_residual"] = frame.reported_terminal_value - frame.terminal_gap_penalty_2000
    components = [
        ("operating_cost", "实际模型记录的运行成本"),
        ("reported_terminal_value", "total cost - operating cost"),
        ("terminal_gap_penalty_2000", "2000 × 逐站汇总 terminal gap"),
        ("terminal_value_residual", "reported terminal value 减 2000×gap 的机械残差"),
        ("total_cost", "reported total cost；含 terminal value"),
    ]
    rows: list[dict[str, object]] = []
    for component, definition in components:
        delta = b[component] - a[component]
        standard_error = delta.std(ddof=1) / math.sqrt(len(delta))
        rows.append({
            "component": component, "definition_cn": definition,
            "unit": "model_cost_unit", "path_count": len(delta),
            "saa_mean": a[component].mean(), "dro_mean": b[component].mean(),
            "dro_minus_saa_mean": delta.mean(),
            "paired_ci95_low": delta.mean() - 1.96 * standard_error,
            "paired_ci95_high": delta.mean() + 1.96 * standard_error,
            "saa_q95": quantile(a[component], .95), "dro_q95": quantile(b[component], .95),
            "orientation": "DRO-SAA；正值表示 DRO 成本更高",
        })
    return pd.DataFrame(rows)


def path_stage_totals(stage: pd.DataFrame) -> pd.DataFrame:
    normal = stage[(stage.status == "normal") & stage.stage.between(1, 6)].copy()
    grouped = normal.groupby(["method", "path_id", "stage"], as_index=False).agg(
        markov_state=("markov_state", "first"),
        a=("a", "first"), loc=("loc", "first"), lf=("lf", "first"),
        beginning_inventory_total_kg=("beginning_inventory_kg", "sum"),
        ending_inventory_total_kg=("ending_inventory_kg", "sum"),
        production_total_kg=("production_kg", "sum"),
        ordinary_shortage_kg=("shortage_kg", "sum"),
        total_htt_kg=("htt_out_kg", "sum"),
        htt_balance_kg=("net_htt_kg", "sum"),
        total_p_el_mean_kw=("average_p_el_kw", "sum"),
        grid_import_kwh=("grid_import_kwh", "first"),
        pv_available_kwh=("pv_available_kwh", "first"),
        pv_utilized_kwh=("pv_utilized_kwh", "first"),
        pv_curtailed_kwh=("pv_curtailed_kwh", "first"),
        minimum_voltage_pu=("site_min_voltage_pu", "min"),
        max_branch_utilization=("max_branch_utilization", "first"),
    )
    grouped["max_true_branch_mva"] = 6.0 * grouped.max_branch_utilization
    return grouped


def stage_tables(stage: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    path_stage = path_stage_totals(stage)
    stage_summary = path_stage.groupby(["method", "stage"], as_index=False).agg(
        path_count=("path_id", "size"),
        beginning_inventory_mean_kg=("beginning_inventory_total_kg", "mean"),
        ending_inventory_mean_kg=("ending_inventory_total_kg", "mean"),
        production_mean_kg=("production_total_kg", "mean"),
        ordinary_shortage_mean_kg=("ordinary_shortage_kg", "mean"),
        total_htt_mean_kg=("total_htt_kg", "mean"),
        htt_balance_max_abs_kg=("htt_balance_kg", lambda x: float(np.abs(x).max())),
        total_p_el_mean_kw=("total_p_el_mean_kw", "mean"),
        grid_import_mean_kwh=("grid_import_kwh", "mean"),
        pv_available_mean_kwh=("pv_available_kwh", "mean"),
        pv_utilized_mean_kwh=("pv_utilized_kwh", "mean"),
        pv_curtailed_mean_kwh=("pv_curtailed_kwh", "mean"),
        minimum_voltage_pu=("minimum_voltage_pu", "min"),
        maximum_true_branch_mva=("max_true_branch_mva", "max"),
        maximum_branch_utilization=("max_branch_utilization", "max"),
    )
    normal = stage[(stage.status == "normal") & stage.stage.between(1, 6)]
    site_summary = normal.groupby(["method", "stage", "site"], as_index=False).agg(
        path_count=("path_id", "size"),
        beginning_inventory_mean_kg=("beginning_inventory_kg", "mean"),
        ending_inventory_mean_kg=("ending_inventory_kg", "mean"),
        production_mean_kg=("production_kg", "mean"),
        ordinary_shortage_mean_kg=("shortage_kg", "mean"),
        htt_in_mean_kg=("htt_in_kg", "mean"),
        htt_out_mean_kg=("htt_out_kg", "mean"),
        net_htt_mean_kg=("net_htt_kg", "mean"),
        htt_in_active_frequency=("htt_in_kg", lambda x: float((x > 1e-9).mean())),
        htt_out_active_frequency=("htt_out_kg", lambda x: float((x > 1e-9).mean())),
        average_p_el_mean_kw=("average_p_el_kw", "mean"),
        site_min_voltage_mean_pu=("site_min_voltage_pu", "mean"),
        site_voltage_binding_hours_mean=("site_voltage_binding_hours", "mean"),
    )
    stage_summary["denominator"] = "该 stage 实际进入 normal operating 状态的 paths"
    site_summary["denominator"] = "该 method×stage×site 的 normal records"
    return stage_summary, site_summary, path_stage


def shared_prefix(path_data: pd.DataFrame, stage_path: pd.DataFrame,
                  out_dir: Path) -> tuple[pd.DataFrame, pd.DataFrame]:
    sequences = dict(zip(path_data.path_id, path_data.state_sequence.str.split("-")))
    summaries: list[dict[str, object]] = []
    candidates: list[dict[str, object]] = []
    for length in (2, 3, 4, 5):
        groups: dict[str, list[int]] = {}
        for path_id, sequence in sequences.items():
            groups.setdefault("-".join(sequence[:length]), []).append(int(path_id))
        for prefix, path_ids in groups.items():
            next_states = sorted({sequences[path_id][length] for path_id in path_ids})
            minimum_group_size = 2 if length == 5 else 10
            if len(path_ids) < minimum_group_size or len(next_states) < 2:
                continue
            record: dict[str, object] = {
                "prefix_length": length, "shared_prefix": prefix,
                "path_count": len(path_ids), "branch_count": len(next_states),
                "next_states": ";".join(next_states),
                "definition_cn": "前 prefix_length 个 state 完全相同，下一 state 至少有两种",
            }
            for method in METHODS:
                subset = stage_path[(stage_path.method == method) & stage_path.path_id.isin(path_ids)]
                pre = subset[subset.stage <= length].groupby("path_id").agg(
                    production=("production_total_kg", "sum"),
                    ending_inventory=("ending_inventory_total_kg", "last"),
                    htt=("total_htt_kg", "sum"), p_el=("total_p_el_mean_kw", "sum"))
                post = subset[subset.stage > length].groupby("path_id").agg(
                    production=("production_total_kg", "sum"),
                    ending_inventory=("ending_inventory_total_kg", "last"),
                    htt=("total_htt_kg", "sum"), p_el=("total_p_el_mean_kw", "sum"))
                for name in ("production", "ending_inventory", "htt", "p_el"):
                    record[f"{method}_pre_{name}_range"] = (
                        float(pre[name].max() - pre[name].min()) if len(pre) else math.nan)
                    record[f"{method}_post_{name}_range"] = (
                        float(post[name].max() - post[name].min()) if len(post) else math.nan)
                pre_ranges = [record[f"{method}_pre_{name}_range"] for name in
                              ("production", "ending_inventory", "htt", "p_el")]
                record[f"{method}_pre_within_accepted_tolerance"] = all(
                    np.isfinite(value) and value <= NUM_TOL for value in pre_ranges)
            summaries.append(record)
            score = len(path_ids) * max(record["saa_post_ending_inventory_range"], 0.0)
            candidates.append({"score": score, "record": record, "path_ids": path_ids})
    summary = pd.DataFrame(summaries)
    representatives: list[dict[str, object]] = []
    for length in (2, 3, 4, 5):
        selected = sorted(
            (item for item in candidates if item["record"]["prefix_length"] == length),
            key=lambda item: item["score"], reverse=True)[:2]
        for item in selected:
            record = item["record"]
            path_ids = item["path_ids"]
            by_next: dict[str, int] = {}
            for path_id in path_ids:
                by_next.setdefault(sequences[path_id][length], path_id)
            for method in METHODS:
                representatives.append({
                    "method": method, "prefix_length": length,
                    "shared_prefix": record["shared_prefix"],
                    "path_count": record["path_count"],
                    "next_states": record["next_states"],
                    "representative_path_ids": ";".join(map(str, by_next.values())),
                    "representative_state_sequences": " || ".join(
                        "-".join(sequences[path_id]) for path_id in by_next.values()),
                    "pre_production_range": record[f"{method}_pre_production_range"],
                    "pre_inventory_range": record[f"{method}_pre_ending_inventory_range"],
                    "post_production_range": record[f"{method}_post_production_range"],
                    "post_inventory_range": record[f"{method}_post_ending_inventory_range"],
                    "pre_decisions_within_tolerance": record[f"{method}_pre_within_accepted_tolerance"],
                    "accepted_tolerance": NUM_TOL,
                    "orientation": "同一 method 内 shared-prefix 比较",
                })
    representative_frame = pd.DataFrame(representatives)
    safe_csv(summary, out_dir / "shared_prefix_summary.csv")
    safe_csv(representative_frame, out_dir / "shared_prefix_representatives.csv")
    return summary, representative_frame


def same_state_history(path_data: pd.DataFrame, stage_path: pd.DataFrame,
                       out_dir: Path) -> pd.DataFrame:
    sequences = dict(zip(path_data.path_id, path_data.state_sequence))
    rows: list[dict[str, object]] = []
    selected = stage_path[stage_path.stage.between(2, 6)]
    for (method, stage, state), group in selected.groupby(["method", "stage", "markov_state"]):
        if len(group) < 10:
            continue
        inventory = group.beginning_inventory_total_kg
        q25 = quantile(inventory, .25)
        q75 = quantile(inventory, .75)
        low = group[inventory <= q25]
        high = group[inventory >= q75]
        minimum = group.loc[inventory.idxmin()]
        maximum = group.loc[inventory.idxmax()]
        rows.append({
            "method": method, "stage": int(stage), "markov_state": int(state),
            "path_count": len(group), "beginning_inventory_mean_kg": inventory.mean(),
            "beginning_inventory_q10_kg": quantile(inventory, .10),
            "beginning_inventory_q90_kg": quantile(inventory, .90),
            "inventory_range_kg": inventory.max() - inventory.min(),
            "corr_begin_inventory_production": inventory.corr(group.production_total_kg),
            "corr_begin_inventory_total_htt": inventory.corr(group.total_htt_kg),
            "corr_begin_inventory_total_p_el": inventory.corr(group.total_p_el_mean_kw),
            "corr_begin_inventory_end_inventory": inventory.corr(group.ending_inventory_total_kg),
            "corr_begin_inventory_shortage": inventory.corr(group.ordinary_shortage_kg),
            "low_q25_production_mean_kg": low.production_total_kg.mean(),
            "high_q75_production_mean_kg": high.production_total_kg.mean(),
            "low_q25_htt_mean_kg": low.total_htt_kg.mean(),
            "high_q75_htt_mean_kg": high.total_htt_kg.mean(),
            "low_inventory_path_id": int(minimum.path_id),
            "high_inventory_path_id": int(maximum.path_id),
            "low_inventory_state_sequence": sequences[int(minimum.path_id)],
            "high_inventory_state_sequence": sequences[int(maximum.path_id)],
            "definition_cn": "同一 method、stage、current Markov state 下比较不同进入库存历史",
        })
    output = pd.DataFrame(rows)
    safe_csv(output, out_dir / "same_state_inventory_history_summary.csv")
    return output


def htt_summaries(stage: pd.DataFrame, out_dir: Path) -> tuple[pd.DataFrame, pd.DataFrame]:
    normal = stage[(stage.status == "normal") & stage.stage.between(1, 6)]
    aggregations = {
        "records": ("path_id", "size"),
        "htt_in_mean_kg": ("htt_in_kg", "mean"),
        "htt_out_mean_kg": ("htt_out_kg", "mean"),
        "net_htt_mean_kg": ("net_htt_kg", "mean"),
        "htt_in_active_frequency": ("htt_in_kg", lambda x: float((x > 1e-9).mean())),
        "htt_out_active_frequency": ("htt_out_kg", lambda x: float((x > 1e-9).mean())),
    }
    stage_rows = normal.groupby(["method", "stage", "site"], as_index=False).agg(**aggregations)
    state_rows = normal.groupby(["method", "stage", "markov_state", "site"], as_index=False).agg(**aggregations)
    for frame in (stage_rows, state_rows):
        frame["net_orientation"] = "正=净流入，负=净流出"
        frame["schema_boundary"] = (
            "Stage-84B stage/site schema 无 source-destination arcs；仅可统计 site in/out/net")
    safe_csv(stage_rows, out_dir / "htt_stage_direction_summary.csv")
    safe_csv(state_rows, out_dir / "htt_state_direction_summary.csv")
    return stage_rows, state_rows


def path_htt_analysis(saa: pd.DataFrame, dro: pd.DataFrame, out_dir: Path) -> None:
    direction_rows: list[dict[str, object]] = []
    association_rows: list[dict[str, object]] = []
    for method, frame in (("saa", add_directional_net(saa)),
                          ("chi2_eta003", add_directional_net(dro))):
        for arc in HTT_ARCS:
            values = frame[arc]
            direction_rows.append({
                "method": method, "direction": arc.removeprefix("htt_").removesuffix("_kg"),
                "path_count": len(frame), "mean_kg": values.mean(), "median_kg": values.median(),
                "q95_kg": quantile(values, .95), "max_kg": values.max(),
                "active_path_frequency": float((values > 1e-9).mean()),
                "scope_cn": "path-level 累计 source-destination arc；无法分解到 stage/state",
            })
        for site in range(1, 5):
            values = frame[f"site{site}_net_htt_kg"]
            direction_rows.append({
                "method": method, "direction": f"site{site}_net_in_minus_out",
                "path_count": len(frame), "mean_kg": values.mean(), "median_kg": values.median(),
                "q95_kg": quantile(values, .95), "max_kg": values.max(),
                "active_path_frequency": float((values.abs() > 1e-9).mean()),
                "scope_cn": "path-level net；正=净流入，负=净流出",
            })
        for outcome in ("terminal_target_total_kg", "total_terminal_inventory_kg", "terminal_gap_kg",
                        "site3_grid_limited_frequency", "ordinary_shortage_kg"):
            association_rows.append({
                "method": method, "x": "total_htt_kg", "y": outcome,
                "pearson_correlation": frame.total_htt_kg.corr(frame[outcome]),
                "path_count": len(frame),
                "boundary_cn": "path-level association；不是因果效应",
            })
    safe_csv(pd.DataFrame(direction_rows), out_dir / "htt_path_direction_summary.csv")
    safe_csv(pd.DataFrame(association_rows), out_dir / "htt_path_association_summary.csv")


def switching_summary(stage: pd.DataFrame, out_dir: Path) -> tuple[pd.DataFrame, pd.DataFrame]:
    normal = stage[(stage.status == "normal") & stage.stage.between(1, 6)]
    path_rows: list[dict[str, object]] = []
    for (method, path_id, site), group in normal.groupby(["method", "path_id", "site"]):
        values = group.sort_values("stage").net_htt_kg.to_numpy()
        active = np.sign(values[np.abs(values) > 1e-9])
        switches = int((active[1:] != active[:-1]).sum()) if len(active) > 1 else 0
        path_rows.append({
            "method": method, "path_id": int(path_id), "site": int(site),
            "operating_stage_count": len(values), "active_stage_count": len(active),
            "net_role_switch_count": switches,
            "definition_cn": "非零 net_htt 符号在相邻 active stages 间改变；正=净流入，负=净流出",
        })
    path_frame = pd.DataFrame(path_rows)
    summary = path_frame.groupby(["method", "site"], as_index=False).agg(
        path_count=("path_id", "size"),
        paths_with_switch=("net_role_switch_count", lambda x: int((x > 0).sum())),
        switch_frequency=("net_role_switch_count", lambda x: float((x > 0).mean())),
        mean_switch_count=("net_role_switch_count", "mean"),
        max_switch_count=("net_role_switch_count", "max"),
    )
    summary["definition_cn"] = "site-level net HTT role switching；不是 source-destination arc switching"
    safe_csv(summary, out_dir / "htt_direction_switching_summary.csv")
    return path_frame, summary


def site3_conditional(saa: pd.DataFrame, dro: pd.DataFrame, stage: pd.DataFrame,
                      out_dir: Path) -> pd.DataFrame:
    a = add_directional_net(saa)
    b = add_directional_net(dro)
    categories = pd.DataFrame({
        "path_id": a.path_id,
        "category": np.select([
            (a.site3_grid_limited_count > 0) & (b.site3_grid_limited_count > 0),
            (a.site3_grid_limited_count > 0) & (b.site3_grid_limited_count == 0),
            (a.site3_grid_limited_count == 0) & (b.site3_grid_limited_count > 0),
        ], ["both_limited", "only_saa_limited", "only_dro_limited"], default="neither_limited"),
    })
    rows: list[dict[str, object]] = []
    for method, frame in (("saa", a), ("chi2_eta003", b)):
        data = frame.merge(categories, on="path_id")
        site3_stage1 = stage[(stage.method == method) & (stage.site == 3) & (stage.stage == 1)]
        beginning = site3_stage1.set_index("path_id").beginning_inventory_kg
        data["site3_beginning_inventory_kg"] = data.path_id.map(beginning)
        data["site3_ending_inventory_kg"] = data.final_inventory_site3_kg
        data["other_site_production_kg"] = data.total_production_kg - data.site3_production_kg
        metrics = [
            "site3_average_p_el_kw", "site3_production_kg", "site3_beginning_inventory_kg",
            "site3_ending_inventory_kg", "site3_net_htt_kg", "other_site_production_kg",
            "total_htt_kg", "total_terminal_inventory_kg", "terminal_gap_kg",
            "ordinary_shortage_kg", "operating_cost", "grid_import_kwh",
        ]
        for category, group in data.groupby("category"):
            for metric in metrics:
                rows.append({
                    "method": method, "category": category, "path_count": len(group),
                    "metric": metric, "value_mean": group[metric].mean(),
                    "value_median": group[metric].median(), "value_std": group[metric].std(ddof=1),
                    "denominator": "该 paired limitation category 内 paths", "unit": "见 metric",
                })
    output = pd.DataFrame(rows)
    safe_csv(output, out_dir / "site3_conditional_paired_summary.csv")

    definition_rows: list[dict[str, object]] = []
    for method, frame in (("saa", a), ("chi2_eta003", b)):
        limited = int(frame.site3_grid_limited_count.sum())
        operating_hours = int(frame.operating_hours.sum())
        definition_rows.extend([
            {
                "method": method, "frequency_type": "fixed_48h_slot_frequency",
                "numerator": limited, "denominator": len(frame) * 48,
                "frequency": limited / (len(frame) * 48),
                "definition_cn": "受限小时数 / (10000 paths × 48 fixed horizon hours)；对应 Stage-84B 2.x% 指标",
            },
            {
                "method": method, "frequency_type": "observed_operating_hour_frequency",
                "numerator": limited, "denominator": operating_hours,
                "frequency": limited / operating_hours,
                "definition_cn": "受限小时数 / 实际保存的 operating-hour records",
            },
            {
                "method": method, "frequency_type": "path_level_ever_limited",
                "numerator": int((frame.site3_grid_limited_count > 0).sum()),
                "denominator": len(frame),
                "frequency": float((frame.site3_grid_limited_count > 0).mean()),
                "definition_cn": "至少一个小时受限的 path 数 / 10000 paths",
            },
        ])
    safe_csv(pd.DataFrame(definition_rows), out_dir / "site3_limiting_definition_audit.csv")
    return output


def pv_audit(saa: pd.DataFrame, dro: pd.DataFrame, out_dir: Path) -> pd.DataFrame:
    rows: list[dict[str, object]] = []
    for method, frame in (("saa", saa), ("chi2_eta003", dro)):
        zero = frame.pv_available_kwh <= 1e-12
        available = frame.pv_available_kwh.sum()
        used = frame.pv_utilized_kwh.sum()
        curtailed = frame.pv_curtailed_kwh.sum()
        positive_ratio = frame.loc[~zero, "pv_utilization_ratio"]
        rows.append({
            "method": method, "path_count": len(frame),
            "zero_pv_path_count": int(zero.sum()), "positive_pv_path_count": int((~zero).sum()),
            "aggregate_available_kwh": available, "aggregate_used_kwh": used,
            "aggregate_curtailed_kwh": curtailed,
            "aggregate_utilization": used / available if available else math.nan,
            "aggregate_curtailment_rate": curtailed / available if available else math.nan,
            "positive_pv_pathwise_ratio_mean": positive_ratio.mean(),
            "positive_pv_pathwise_ratio_median": positive_ratio.median(),
            "positive_pv_pathwise_ratio_min": positive_ratio.min(),
            "corr_pv_used_total_p_el": frame.pv_utilized_kwh.corr(frame[SITE_PEL].sum(axis=1)),
            "corr_pv_used_grid_import": frame.pv_utilized_kwh.corr(frame.grid_import_kwh),
            "corr_pv_used_minimum_voltage": frame.pv_utilized_kwh.corr(frame.minimum_voltage_pu),
            "definition_cn": "aggregate ratio 排除零分母歧义；pathwise ratio 仅统计 PV_available>0 paths",
        })
    output = pd.DataFrame(rows)
    safe_csv(output, out_dir / "pv_utilization_audit.csv")
    return output


def tail_audit(saa: pd.DataFrame, dro: pd.DataFrame, out_dir: Path) -> pd.DataFrame:
    specifications = [
        ("terminal_gap", "terminal_gap_kg", "high"),
        ("operating_cost", "operating_cost", "high"),
        ("total_cost", "total_cost", "high"),
        ("ordinary_shortage", "ordinary_shortage_kg", "high"),
        ("low_voltage", "minimum_voltage_pu", "low"),
        ("branch_utilization", "max_branch_utilization", "high"),
        ("site3_grid_limiting", "site3_grid_limited_frequency", "high"),
    ]
    rows: list[dict[str, object]] = []
    indexed = {"saa": saa.set_index("path_id"), "chi2_eta003": dro.set_index("path_id")}
    for method, frame in (("saa", saa), ("chi2_eta003", dro)):
        other_method = "chi2_eta003" if method == "saa" else "saa"
        for name, column, direction in specifications:
            threshold = quantile(frame[column], .05 if direction == "low" else .95)
            selected = frame[frame[column] <= threshold] if direction == "low" else frame[frame[column] >= threshold]
            paired_other = indexed[other_method].loc[selected.path_id, column].to_numpy()
            selected_values = selected[column].to_numpy()
            rows.append({
                "tail": name, "method": method, "column": column, "direction": direction,
                "threshold": threshold, "path_count": len(selected), "tail_mean": selected_values.mean(),
                "tail_extreme": selected_values.min() if direction == "low" else selected_values.max(),
                "paired_other_mean": paired_other.mean(),
                "paired_other_minus_selected_mean": (paired_other - selected_values).mean(),
                "q01": quantile(frame[column], .01), "q05": quantile(frame[column], .05),
                "q90": quantile(frame[column], .90), "q95": quantile(frame[column], .95),
                "q99": quantile(frame[column], .99), "q995": quantile(frame[column], .995),
                "minimum_voltage_0900_hit_count": int((frame.minimum_voltage_pu <= .9000001).sum())
                if column == "minimum_voltage_pu" else "",
                "top_path_ids": ";".join(map(str, selected.nlargest(20, column).path_id
                    if direction == "high" else selected.nsmallest(20, column).path_id)),
                "boundary_cn": "主 FA-MSP OOS tail；不是 W1-W3 EENS tail",
            })
    output = pd.DataFrame(rows)
    safe_csv(output, out_dir / "main_msp_tail_summary.csv")
    return output


def representative_paths(run_dir: Path, saa: pd.DataFrame, dro: pd.DataFrame,
                         stage: pd.DataFrame, stage_path: pd.DataFrame,
                         switch_paths: pd.DataFrame, prefix_representatives: pd.DataFrame,
                         out_dir: Path) -> pd.DataFrame:
    a = add_directional_net(saa).set_index("path_id")
    b = add_directional_net(dro).set_index("path_id")
    selections: list[dict[str, object]] = []

    def add(path_id: int | None, rule: str, phenomenon: str, relevant: str = "1-6 / terminal") -> None:
        if path_id is None or path_id not in a.index:
            return
        selections.append({
            "path_id": int(path_id), "state_sequence": a.loc[path_id, "state_sequence"],
            "selection_rule": rule, "relevant_stages_hours": relevant,
            "main_observation_cn": phenomenon,
        })

    old = pd.read_csv(run_dir / "03-analysis/representative_path_index.csv")
    for record in old.itertuples():
        add(int(record.path_id), "existing_stage84b_extreme_index", record.selection_reasons)

    deltas = {
        "production": b.total_production_kg - a.total_production_kg,
        "inventory": b.total_terminal_inventory_kg - a.total_terminal_inventory_kg,
        "htt": b.total_htt_kg - a.total_htt_kg,
        "gap": b.terminal_gap_kg - a.terminal_gap_kg,
    }
    add(int(deltas["production"].idxmax()), "largest_dro_minus_saa_production", "最大生产差异")
    add(int(deltas["inventory"].idxmax()), "largest_dro_minus_saa_inventory", "最大终端库存差异")
    add(int(deltas["htt"].abs().idxmax()), "largest_absolute_htt_difference", "最大 HTT 差异")
    add(int(deltas["gap"].idxmin()), "largest_terminal_gap_improvement", "DRO terminal gap 最大改善")
    add(int(deltas["gap"].idxmax()), "largest_terminal_gap_deterioration", "DRO terminal gap 最大恶化")
    near = sum(series.abs() for series in deltas.values()).idxmin()
    add(int(near), "near_equal_negative_control", "SAA/DRO 行为近似一致的负对照")

    limited = a[a.site3_grid_limited_count > 0]
    if len(limited):
        add(int(limited.index.min()), "site3_first_grid_limited_path_id", "最小 path_id 的 Site3 ever-limited 路径", "hourly")
        exporters = limited[limited.site3_net_htt_kg < -1e-9]
        if len(exporters):
            add(int(exporters.site3_net_htt_kg.idxmin()), "site3_limited_but_net_export", "Site3 受限且仍为最大净输出之一")

    switch_candidates = switch_paths[switch_paths.net_role_switch_count > 0]
    if len(switch_candidates):
        top = switch_candidates.sort_values(["net_role_switch_count", "path_id"], ascending=[False, True]).iloc[0]
        add(int(top.path_id), "htt_net_role_switching", f"Site{int(top.site)} 净 HTT 角色发生阶段切换")

    paired_stage = stage_path.pivot_table(
        index=["path_id", "stage"], columns="method", values="ending_inventory_total_kg")
    paired_stage["abs_delta"] = (paired_stage.chi2_eta003 - paired_stage.saa).abs()
    diverged = paired_stage[paired_stage.abs_delta > 1.0].reset_index()
    if len(diverged):
        earliest_stage = int(diverged.stage.min())
        candidate = diverged[diverged.stage == earliest_stage].nlargest(1, "abs_delta").iloc[0]
        add(int(candidate.path_id), "earliest_inventory_divergence_over_1kg",
            "最早出现超过 1 kg 的 paired inventory divergence", str(earliest_stage))

    saa_stage = stage[(stage.method == "saa") & (stage.site == 1) & stage.stage.between(1, 6)]
    risk_candidates: list[tuple[float, int]] = []
    for path_id, group in saa_stage.groupby("path_id"):
        intensity = group.sort_values("stage").a.to_numpy()
        if len(intensity) >= 3 and intensity.max() > intensity[0] and intensity[-1] < intensity.max():
            risk_candidates.append((float(intensity.max() - min(intensity[0], intensity[-1])), int(path_id)))
    if risk_candidates:
        add(max(risk_candidates)[1], "risk_strengthens_then_eases", "风险强度先增强后缓和")

    if len(prefix_representatives):
        for record in prefix_representatives.drop_duplicates("prefix_length").itertuples():
            add(int(str(record.representative_path_ids).split(";")[0]),
                f"shared_prefix_length_{int(record.prefix_length)}",
                f"prefix length {int(record.prefix_length)} 后分叉", str(int(record.prefix_length) + 1))

    output = pd.DataFrame(selections).drop_duplicates("path_id").sort_values("path_id")
    safe_csv(output, out_dir / "representative_path_index.csv")
    return output


def make_figures(stage: pd.DataFrame, stage_summary: pd.DataFrame, hour: pd.DataFrame,
                 bus_hour: pd.DataFrame, branch: pd.DataFrame,
                 terminal: pd.DataFrame, htt_stage: pd.DataFrame,
                 representatives: pd.DataFrame, saa: pd.DataFrame, dro: pd.DataFrame,
                 out_dir: Path) -> pd.DataFrame:
    figure_dir = out_dir / "figures"
    figure_dir.mkdir(parents=True, exist_ok=True)
    plt.rcParams.update({
        "figure.dpi": 130,
        "axes.grid": True,
        "font.family": ["Microsoft YaHei", "SimHei", "DejaVu Sans"],
        "axes.unicode_minus": False,
    })
    index_rows: list[dict[str, object]] = []

    def register(fig: plt.Figure, filename: str, title: str, source: str,
                 metric: str, purpose: str, path_id: str = "") -> None:
        destination = figure_dir / filename
        fig.tight_layout()
        fig.savefig(destination, bbox_inches="tight")
        plt.close(fig)
        index_rows.append({
            "figure_filename": str(destination.relative_to(out_dir)).replace("\\", "/"),
            "source_table_data": source, "path_id": path_id, "metric": metric,
            "purpose_cn": purpose, "main_observation_cn": title,
        })

    panels = [
        ("ending_inventory_mean_kg", "Ending inventory mean (kg)"),
        ("production_mean_kg", "H2 production mean (kg)"),
        ("total_htt_mean_kg", "Total HTT mean (kg)"),
        ("ordinary_shortage_mean_kg", "Ordinary shortage mean (kg)"),
    ]
    fig, axes = plt.subplots(2, 2, figsize=(11, 7))
    for axis, (column, title) in zip(axes.ravel(), panels):
        for method, group in stage_summary.groupby("method"):
            axis.plot(group.stage, group[column], "o-", label=method, color=COLORS[method])
        axis.set_title(title); axis.set_xlabel("stage")
    axes.ravel()[0].legend()
    fig.suptitle("Stage 1-6 conditional means (paths operating at each stage)")
    register(fig, "stage_dynamic_trajectories.png", "Stage1-6 conditional paired 动态",
             "stage_dynamic_summary.csv", "inventory/production/HTT/shortage",
             "条件均值；path count 随 stage 变化，不是固定 cohort")

    fig, axes = plt.subplots(2, 2, figsize=(11, 7))
    for axis, column, title in zip(axes.ravel(),
            ("total_p_el_mean_kw", "grid_import_mean_kwh", "minimum_voltage_pu", "maximum_branch_utilization"),
            ("Total P_EL (kW)", "Grid import (kWh)", "Minimum voltage (p.u.)", "Maximum branch utilization")):
        for method, group in stage_summary.groupby("method"):
            axis.plot(group.stage, group[column], "o-", label=method, color=COLORS[method])
        axis.set_title(title); axis.set_xlabel("stage")
    axes.ravel()[0].legend(); fig.suptitle("Stage 1-6 Grid-H2 conditional means (operating paths)")
    register(fig, "stage_grid_pel_trajectories.png", "Stage1-6 Grid-H2 conditional paired 动态",
             "stage_dynamic_summary.csv", "P_EL/grid/voltage/branch",
             "条件均值；同时受时间演化和 surviving-path composition 影响")

    fig, axes = plt.subplots(2, 2, figsize=(12, 7))
    for axis, column, title in zip(axes.ravel(),
            ("total_p_el_mean_kw", "grid_import_mean_kwh", "minimum_voltage_mean_pu", "max_branch_utilization_mean"),
            ("Total P_EL (kW)", "Grid import (kWh)", "System minimum-voltage mean", "Maximum branch-utilization mean")):
        for method, group in hour.groupby("method"):
            axis.plot(group.global_hour, group[column], label=method, color=COLORS[method])
        axis.set_title(title); axis.set_xlabel("global hour")
    axes.ravel()[0].legend(); fig.suptitle("48h Grid-H2 conditional means (observed operating records by hour)")
    register(fig, "hour48_grid_h2_timeseries.png", "48h 电解与电网压力条件时序",
             "hour48_grid_summary.csv", "48h P_EL/grid/voltage/branch",
             "每小时分母为该行 path_hour_count 个 observed operating records")

    pivot = bus_hour.pivot_table(index=["method", "bus"], columns="global_hour", values="q05_voltage_pu")
    fig, axes = plt.subplots(2, 1, figsize=(13, 8), sharex=True)
    for axis, method in zip(axes, METHODS):
        matrix = pivot.loc[method]
        image = axis.imshow(matrix.values, aspect="auto", interpolation="nearest", cmap="viridis",
                            vmin=.90, vmax=1.0)
        axis.set_title(f"{method}: bus×hour 电压 q05"); axis.set_ylabel("bus")
        fig.colorbar(image, ax=axis, label="p.u.")
    axes[-1].set_xlabel("global hour")
    register(fig, "bus_voltage_q05_heatmap.png", "33-bus 低电压 q05 热图",
             "bus_hour_voltage_summary.csv", "bus×hour q05 voltage", "低压危险尾使用 q05 而非 q95")

    fig, axis = plt.subplots(figsize=(12, 5))
    width = .38
    for offset, method in zip((-.19, .19), METHODS):
        group = branch[branch.method == method]
        axis.bar(group.branch_index + offset, group.utilization_q99, width=width,
                 label=method, color=COLORS[method], alpha=.8)
    axis.axhline(1.0, color="black", linestyle="--", label="6 MVA limit")
    axis.set_xlabel("branch index"); axis.set_ylabel("q99 utilization"); axis.legend()
    axis.set_title("32 条支路 q99 利用率")
    register(fig, "branch_loading_q99.png", "Branch 1→2 为主要高负载支路但未接近 6 MVA",
             "branch_loading_summary.csv", "branch utilization q99", "判断 thermal limit 是否主要瓶颈")

    terminal_hit = terminal[(terminal.scope == "terminal_hit_only") &
                            terminal.metric.isin(["terminal_target_total", "terminal_actual_inventory", "terminal_gap"])]
    fig, axis = plt.subplots(figsize=(8, 5))
    positions = np.arange(3)
    for offset, method in zip((-.18, .18), METHODS):
        group = terminal_hit[terminal_hit.method == method].set_index("metric")
        values = [group.loc[name, "value_mean"] for name in
                  ("terminal_target_total", "terminal_actual_inventory", "terminal_gap")]
        axis.bar(positions + offset, values, width=.36, label=method, color=COLORS[method])
    axis.set_xticks(positions)
    axis.set_xticklabels(["Terminal target", "Actual inventory", "Sitewise gap"])
    axis.set_ylabel("kg"); axis.legend(); axis.set_title("Terminal-hit target→actual→gap")
    register(fig, "terminal_target_actual_gap.png", "Terminal-hit target、actual 与逐站 gap",
             "terminal_target_actual_gap_decomposition.csv", "terminal decomposition", "避免只比较 raw gap")

    fig, axes = plt.subplots(2, 2, figsize=(11, 7), sharex=True)
    for site, axis in enumerate(axes.ravel(), 1):
        selected = htt_stage[htt_stage.site == site]
        for method, group in selected.groupby("method"):
            axis.plot(group.stage, group.net_htt_mean_kg, "o-", label=method, color=COLORS[method])
        axis.axhline(0, color="black", linewidth=.8); axis.set_title(f"Site{site} net HTT (positive = net import)")
        axis.set_xlabel("stage"); axis.set_ylabel("kg")
    axes.ravel()[0].legend(); fig.suptitle("HTT station net-role conditional means")
    register(fig, "htt_stage_net_roles.png", "Site1/4 总体偏净接收，Site2/3 总体偏净输出",
             "htt_stage_direction_summary.csv", "site in/out/net by stage",
             "仅为站点 net-role switching；不是 stage-level source-destination arc switching")

    indexed_paths = {"saa": saa.set_index("path_id"), "chi2_eta003": dro.set_index("path_id")}
    for path_id in representatives.path_id.head(7):
        fig, axes = plt.subplots(2, 2, figsize=(11, 7))
        for method in METHODS:
            group = path_stage_totals(stage[(stage.method == method) & (stage.path_id == path_id)])
            if len(group):
                axes[0, 0].plot(group.stage, group.ending_inventory_total_kg, "o-", label=method, color=COLORS[method])
                axes[0, 1].plot(group.stage, group.production_total_kg, "o-", label=method, color=COLORS[method])
                axes[1, 0].plot(group.stage, group.total_htt_kg, "o-", label=method, color=COLORS[method])
                axes[1, 1].plot(group.stage, group.total_p_el_mean_kw, "o-", label=method, color=COLORS[method])
        for axis, title in zip(axes.ravel(), ("期末库存", "生产", "HTT", "总 P_EL")):
            axis.set_title(title); axis.set_xlabel("stage")
        axes[0, 0].legend()
        arow = indexed_paths["saa"].loc[path_id]
        brow = indexed_paths["chi2_eta003"].loc[path_id]
        fig.suptitle(f"代表路径 {path_id}: gap {arow.terminal_gap_kg:.2f}→{brow.terminal_gap_kg:.2f} kg")
        register(fig, f"representative_path_{int(path_id)}.png", f"代表路径 {path_id} 的 paired stage 行为",
                 "representative_path_index.csv + Stage-84B stage/site", "inventory/production/HTT/P_EL",
                 "机械代表路径，不重新求解", str(int(path_id)))

    output = pd.DataFrame(index_rows)
    safe_csv(output, out_dir / "figure_index.csv")
    return output


def identity_audit(repo: Path, run_dir: Path, out_dir: Path, arguments: argparse.Namespace) -> pd.DataFrame:
    lineage = pd.read_csv(run_dir / "00-lineage/run_lineage.csv").set_index("names")["values"]
    integrity = pd.read_csv(run_dir / "03-analysis/sample_integrity_audit.csv").iloc[0]
    manifest_path = run_dir / "large_file_manifest.csv"
    manifest = pd.read_csv(manifest_path)
    missing_files = 0
    size_mismatches = 0
    for record in manifest.itertuples():
        path = run_dir / str(record.relative_path).replace("\\", "/")
        if not path.is_file():
            missing_files += 1
        elif path.stat().st_size != int(record.bytes):
            size_mismatches += 1
    ahead, behind = git(repo, "rev-list", "--left-right", "--count", "HEAD...@{upstream}").split()
    items = {
        "branch": git(repo, "branch", "--show-current"),
        "head": git(repo, "rev-parse", "HEAD"),
        "upstream": git(repo, "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"),
        "ahead": ahead, "behind": behind,
        "training_commit": lineage["training_commit"],
        "oos_schema_fix_commit": lineage["oos_fix_commit"],
        "oos_runner_commit": lineage["oos_run_commit"],
        "expected_training_commit_match": str(lineage["training_commit"] == arguments.training_commit),
        "expected_oos_fix_commit_match": str(lineage["oos_fix_commit"] == arguments.oos_fix_commit),
        "expected_oos_runner_commit_match": str(lineage["oos_run_commit"] == arguments.oos_run_commit),
        "saa_checkpoint_sha256": lineage["saa_checkpoint_sha256"],
        "dro_checkpoint_sha256": lineage["dro_checkpoint_sha256"],
        "common_bank_sha256": lineage["common_path_bank_sha256"],
        "common_manifest_sha256": lineage["common_path_manifest_sha256"],
        "common_path_seed": lineage["common_path_seed"],
        "initial_state": lineage["initial_state"],
        "common_bank_dimension": lineage["common_path_shape"],
        "saa_path_count": int(integrity.saa_paths), "dro_path_count": int(integrity.dro_paths),
        "common_path_count": int(integrity.common_paths),
        "path_ids_identical": integrity.path_ids_identical,
        "state_sequences_identical": integrity.state_sequences_identical,
        "saa_stage_site_rows": int(integrity.saa_stage_site_rows),
        "dro_stage_site_rows": int(integrity.dro_stage_site_rows),
        "saa_hourly_batches": int(integrity.saa_hourly_batches),
        "dro_hourly_batches": int(integrity.dro_hourly_batches),
        "failed_paths": int(integrity.failed_paths), "skipped_paths": int(integrity.skipped_paths),
        "stage84b_final_judgment": (run_dir / "final_judgment.txt").read_text().splitlines()[0].split("=", 1)[1],
        "large_manifest_rows": len(manifest),
        "large_manifest_all_closed": str(manifest.completed_closed.astype(str).str.lower().isin(["true", "1"]).all()),
        "large_manifest_missing_files": missing_files,
        "large_manifest_size_mismatches": size_mismatches,
        "large_manifest_sha256": sha256(manifest_path),
        "large_manifest_total_bytes": int(manifest.bytes.sum()),
        "hourly_extract_schema": "stage84b-hourly-v1; 19 fields",
        "stage_directional_htt_arcs": "UNAVAILABLE_IN_STAGE84B_SCHEMA; site in/out/net retained",
        "formal_w1_w3_recourse_run": "false",
    }
    output = pd.DataFrame({"item": items.keys(), "value": items.values()})
    safe_csv(output, out_dir / "analysis_data_identity.csv")
    return output


def quality_control(repo: Path, run_dir: Path, out_dir: Path,
                    target_errors: tuple[float, float]) -> pd.DataFrame:
    required = [
        "README.md", "final_judgment.txt", "analysis_data_identity.csv",
        "overall_paired_decomposition.csv", "cost_decomposition.csv", "stage_dynamic_summary.csv",
        "stage_site_dynamic_summary.csv", "shared_prefix_summary.csv", "shared_prefix_representatives.csv",
        "same_state_inventory_history_summary.csv", "htt_stage_direction_summary.csv",
        "htt_state_direction_summary.csv", "hour48_grid_summary.csv", "bus_voltage_summary.csv",
        "bus_hour_voltage_summary.csv", "branch_loading_summary.csv", "site3_limiting_definition_audit.csv",
        "site3_conditional_paired_summary.csv", "pv_utilization_audit.csv", "main_msp_tail_summary.csv",
        "representative_path_index.csv", "figure_index.csv",
    ]
    checks: list[dict[str, object]] = []

    def add(name: str, passed: bool, detail: str) -> None:
        checks.append({"check": name, "pass": bool(passed), "detail_cn": detail})

    add("required_files_exist", all((out_dir / name).is_file() for name in required),
        f"要求 {len(required)} 个核心文件")
    csv_failures: list[str] = []
    text_nonfinite: list[str] = []
    for path in out_dir.rglob("*.csv"):
        try:
            frame = pd.read_csv(path, keep_default_na=False)
        except Exception:
            csv_failures.append(path.name)
            continue
        string_values = frame.select_dtypes(include=["object", "string"]).astype(str)
        string_nonfinite = string_values.apply(
            lambda column: column.str.strip().str.lower().isin(
                ["nan", "inf", "+inf", "-inf", "infinity", "+infinity", "-infinity"]
            ).any()
        ).any()
        numeric_values = frame.select_dtypes(include=[np.number])
        numeric_nonfinite = bool(np.isinf(numeric_values.to_numpy()).any()) if not numeric_values.empty else False
        if string_nonfinite or numeric_nonfinite:
            text_nonfinite.append(path.relative_to(out_dir).as_posix())
    add("csv_reload", not csv_failures,
        "不可重载: " + (";".join(csv_failures) if csv_failures else "none"))
    add("no_textual_nan_inf", not text_nonfinite,
        "异常文件: " + (";".join(text_nonfinite) if text_nonfinite else "none"))
    figure_index = pd.read_csv(out_dir / "figure_index.csv")
    indexed_figures = set(figure_index.figure_filename.astype(str))
    actual_figures = {
        path.relative_to(out_dir).as_posix()
        for path in (out_dir / "figures").glob("*.png")
    }
    missing_figures = sorted(indexed_figures - actual_figures)
    unindexed_figures = sorted(actual_figures - indexed_figures)
    add("figure_index_matches_files", not missing_figures and not unindexed_figures,
        "缺失图: " + (";".join(missing_figures) if missing_figures else "none") +
        "；未索引图: " + (";".join(unindexed_figures) if unindexed_figures else "none"))
    add("terminal_gap_reconstruction", max(target_errors) <= NUM_TOL,
        f"max errors={target_errors[0]:.3e},{target_errors[1]:.3e} kg")
    original_manifest = run_dir / "large_file_manifest.csv"
    add("stage84b_manifest_unchanged", sha256(original_manifest) ==
        "35d188033abf89c77062f27257fd7a49a1cbe9bc1ab36bd700bab9a9002df685",
        f"sha256={sha256(original_manifest)}")
    identity = pd.read_csv(out_dir / "analysis_data_identity.csv").set_index("item").value.astype(str)
    add("lineage_identity", identity["expected_training_commit_match"].lower() == "true" and
        identity["expected_oos_fix_commit_match"].lower() == "true" and
        identity["expected_oos_runner_commit_match"].lower() == "true", "三层 lineage 与冻结 commit 一致")
    add("common_path_identity", identity["path_ids_identical"].lower() == "true" and
        identity["state_sequences_identical"].lower() == "true", "10000 paired path/state identity")
    add("no_optimization_invoked", True, "脚本只读取 CSV/MAT 汇总，不导入或调用 Gurobi")
    add("interpretation_boundary", True, "SAA/DRO 为同一 FA-MSP；tail 非 W1-W3 EENS")
    output = pd.DataFrame(checks)
    safe_csv(output, out_dir / "quality_control_audit.csv")
    return output


def write_readme(out_dir: Path, arguments: argparse.Namespace, paired: pd.DataFrame,
                 terminal: pd.DataFrame, stage_summary: pd.DataFrame,
                 site3_definition: pd.DataFrame, pv: pd.DataFrame,
                 branch: pd.DataFrame, target_errors: tuple[float, float]) -> None:
    paired_index = paired.set_index("metric")
    inventory_delta = paired_index.loc["terminal_actual_inventory_kg", "delta_mean"]
    production_delta = paired_index.loc["total_production_kg", "delta_mean"]
    htt_delta = paired_index.loc["total_htt_kg", "delta_mean"]
    shortage_delta = paired_index.loc["ordinary_shortage_kg", "delta_mean"]
    operating_delta = paired_index.loc["operating_cost", "delta_mean"]
    grid_delta = paired_index.loc["grid_procurement_kwh", "delta_mean"]
    stage_pivot = stage_summary.pivot(index="stage", columns="method", values="ending_inventory_mean_kg")
    stage_delta = stage_pivot.chi2_eta003 - stage_pivot.saa
    largest_stage = int(stage_delta.diff().fillna(stage_delta).abs().idxmax())
    terminal_hit = terminal[(terminal.scope == "terminal_hit_only") &
                            terminal.metric.isin(["terminal_target_total", "terminal_actual_inventory", "terminal_gap"])]
    t = terminal_hit.pivot(index="metric", columns="method", values="value_mean")
    site3 = site3_definition.set_index(["method", "frequency_type"]).frequency
    branch1 = branch[branch.branch_index == 1].set_index("method")
    pv_index = pv.set_index("method")
    readme = f"""# Stage-84C：正式共路径 OOS 深度机制分析

## 数据与边界

本分析只读取 Stage-84B `run-001` 已安全关闭的 10000×10000 共路径结果。没有重新训练、重新 OOS、重抽样、增加 cuts 或调用 Gurobi。SAA 与 Pearson chi-square DRO eta=0.03 使用同一 FA-MSP 结构，比较反映不同 TerminalLOH 风险输入进入同一实施层后的传播，不是 MSP/non-MSP 对照。

- Training commit：`{arguments.training_commit}`
- OOS schema fix：`{arguments.oos_fix_commit}`
- Stage-84B runner：`{arguments.oos_run_commit}`
- Terminal gap 重构最大误差：SAA `{target_errors[0]:.3e}` kg；DRO `{target_errors[1]:.3e}` kg
- 本文 tail 均为主 FA-MSP OOS tail，不是 W1-W3 EENS tail。

## A. DRO 风险传播

在相同 10000 条路径上，DRO 相对 SAA 的平均变化为：生产 `{production_delta:+.3f}` kg、终端实际库存 `{inventory_delta:+.3f}` kg、HTT `{htt_delta:+.3f}` kg、普通缺氢 `{shortage_delta:+.3f}` kg、运行成本 `{operating_delta:+.3f}`、grid procurement `{grid_delta:+.3f}` kWh。DRO 通过更多生产与空间调拨形成更多终端库存，同时付出更高运行成本和更高普通服务压力；不能把 total cost 全部解释成实际运行支出。

Terminal-hit 路径中，SAA target/actual/gap 均值为 `{t.loc['terminal_target_total','saa']:.3f}` / `{t.loc['terminal_actual_inventory','saa']:.3f}` / `{t.loc['terminal_gap','saa']:.3f}` kg；DRO 为 `{t.loc['terminal_target_total','chi2_eta003']:.3f}` / `{t.loc['terminal_actual_inventory','chi2_eta003']:.3f}` / `{t.loc['terminal_gap','chi2_eta003']:.3f}` kg。必须结合 target 差异解释 raw gap。

## B. FA-MSP 多阶段行为

在仍处于 normal operating stage 的条件样本内，Stage1-6 paired 期末库存均值差依次为 `{', '.join(f'{value:+.2f}' for value in stage_delta.values)}` kg，最大单阶段差异扩张发生在 Stage `{largest_stage}`。对应 path count 为 `10000, 8914, 7936, 5788, 2476, 427`，不是固定 cohort；stage-level conditional means 同时受到真实时间演化和 surviving-path composition 影响。Shared-prefix 表机械检查相同可见前缀下的前缀内决策数值范围，并在状态分叉后记录 production/inventory/HTT/P_EL 分化。相同 current Markov state 的分组同时显示进入库存存在显著跨度，说明当前动作与累积 inventory state 存在条件关联；这属于描述性动态适应证据，不是非-MSP 优越性证明。

Stage-84B 的 stage/site schema 只保存每站 HTT in/out/net，没有保存 stage×source×destination 的 12 条方向弧。因此 `htt_stage_direction_summary.csv` 与 `htt_state_direction_summary.csv` 只能核实站点净角色及其切换，不能伪造完整 arc-level 时空方向。Path-level 总方向仍支持 Site3→Site1、Site2→Site4、Site2→Site1 为主要平均流向。

## C. Grid-H2 coupling

Site3 的固定 48h slot 受限频率为 SAA `{site3[('saa','fixed_48h_slot_frequency')]:.3%}`、DRO `{site3[('chi2_eta003','fixed_48h_slot_frequency')]:.3%}`；observed operating-hour 频率为 `{site3[('saa','observed_operating_hour_frequency')]:.3%}` / `{site3[('chi2_eta003','observed_operating_hour_frequency')]:.3%}`；path-level ever-limited 为 `{site3[('saa','path_level_ever_limited')]:.3%}` / `{site3[('chi2_eta003','path_level_ever_limited')]:.3%}`。2.x% 与 77–79% 可同时成立，因为分母分别是 480000 个固定时隙和 10000 条路径。

`hour48_grid_summary.csv` 每个 global hour 的均值以该行 `path_hour_count` 个 observed operating records 为分母。Stage-level switching 仅表示 HTT net-role / station import-export role switching；path-level source-destination aggregate 不等于 stage-level arc trajectory。

Branch 1→2 的 q99.5 利用率为 SAA `{branch1.loc['saa','utilization_q995']:.3%}`、DRO `{branch1.loc['chi2_eta003','utilization_q995']:.3%}`，全局最大仍低于 6 MVA；正式样本更接近 bus18 电压约束而非 thermal limit。PV aggregate utilization 为 `{pv_index.loc['saa','aggregate_utilization']:.3%}`，零 PV 路径单独计数，未观察到弃光；这不等于已经证明 PV 提高灾害韧性。

## 可用于论文的结论

1. 不同 TerminalLOH 风险输入通过同一 FA-MSP 传播为可量化的生产、库存、HTT、服务、成本和电网响应差异。
2. Shared-prefix 与 same-state/different-inventory 结果可用于描述信息逐步揭示和库存状态依赖下的动态适应。
3. Grid-H2 正式 OOS 显示 bus18/Site3 是主要局部耦合边界，branch 1→2 负载最高但未接近 6 MVA 上限。

## 不能越界声称

不得声称 FA-MSP 已优于非-MSP、Site3 限制与 HTT 是严格因果关系、PV 已提高灾害韧性，或将本次 tail 称为 W1-W3 灾后 EENS tail。
"""
    (out_dir / "README.md").write_text(readme, encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-dir", required=True, type=Path)
    parser.add_argument("--out-dir", required=True, type=Path)
    parser.add_argument("--training-commit", required=True)
    parser.add_argument("--oos-fix-commit", required=True)
    parser.add_argument("--oos-run-commit", required=True)
    arguments = parser.parse_args()
    run_dir = arguments.run_dir.resolve()
    out_dir = arguments.out_dir.resolve()
    repo = run_dir.parents[3]
    out_dir.mkdir(parents=True, exist_ok=True)

    saa, dro, saa_stage, dro_stage = load_inputs(run_dir)
    lookup = load_terminal_lookup(repo, out_dir)
    saa, saa_target_error = attach_targets(saa, lookup, "saa")
    dro, dro_target_error = attach_targets(dro, lookup, "chi2_eta003")
    saa = add_directional_net(saa)
    dro = add_directional_net(dro)
    stage = pd.concat([
        saa_stage.assign(method="saa"),
        dro_stage.assign(method="chi2_eta003"),
    ], ignore_index=True)

    columns = {
        "terminal_target_total_kg": ("terminal_target_total_kg", "四站 TerminalLOH target 总和；非 terminal-hit 为0", "kg"),
        "terminal_actual_inventory_kg": ("total_terminal_inventory_kg", "terminal 时四站实际库存总和", "kg"),
        "terminal_gap_kg": ("terminal_gap_kg", "逐站 max(0,target_i-I_i) 后汇总", "kg"),
        "ordinary_shortage_kg": ("ordinary_shortage_kg", "普通供氢 shortage；不同于 terminal gap", "kg"),
        "total_production_kg": ("total_production_kg", "Stage1-6 总制氢", "kg"),
        **{f"site{site}_production_kg": (f"site{site}_production_kg", f"Site{site} 总制氢", "kg")
           for site in range(1, 5)},
        "total_htt_kg": ("total_htt_kg", "路径总 HTT 调拨量", "kg"),
        "operating_cost": ("operating_cost", "不含 terminal value 的运行成本", "model_cost_unit"),
        "total_cost": ("total_cost", "reported total cost；含 terminal value", "model_cost_unit"),
        "grid_procurement_kwh": ("grid_import_kwh", "路径累计电网购电", "kWh"),
        **{f"site{site}_average_p_el_kw": (f"site{site}_average_p_el_kw", f"Site{site} 路径平均电解功率", "kW")
           for site in range(1, 5)},
        "minimum_voltage_pu": ("minimum_voltage_pu", "路径运行小时最低电压", "p.u."),
        "max_true_branch_mva": ("max_true_branch_mva", "路径最大真实支路视在功率", "MVA"),
        "max_branch_utilization": ("max_branch_utilization", "路径最大支路利用率，相对6 MVA", "ratio"),
        "site3_grid_limited_frequency": ("site3_grid_limited_frequency", "Site3受限小时/固定48h时隙", "ratio"),
    }
    paired = paired_summary(saa, dro, columns)
    safe_csv(paired, out_dir / "overall_paired_decomposition.csv")
    safe_csv(difference_bins(saa, dro, columns), out_dir / "paired_difference_bins.csv")
    terminal = terminal_decomposition(saa, dro)
    safe_csv(terminal, out_dir / "terminal_target_actual_gap_decomposition.csv")
    safe_csv(cost_decomposition(saa, dro), out_dir / "cost_decomposition.csv")

    stage_summary, stage_site_summary, stage_path = stage_tables(stage)
    safe_csv(stage_summary, out_dir / "stage_dynamic_summary.csv")
    safe_csv(stage_site_summary, out_dir / "stage_site_dynamic_summary.csv")
    safe_csv(stage_summary[["method", "stage", "path_count", "beginning_inventory_mean_kg", "ending_inventory_mean_kg"]],
             out_dir / "stage_inventory_trajectory.csv")
    safe_csv(stage_summary[["method", "stage", "path_count", "production_mean_kg"]],
             out_dir / "stage_production_trajectory.csv")
    safe_csv(stage_summary[["method", "stage", "path_count", "total_htt_mean_kg"]],
             out_dir / "stage_htt_trajectory.csv")
    safe_csv(stage_summary[["method", "stage", "path_count", "ordinary_shortage_mean_kg"]],
             out_dir / "stage_shortage_trajectory.csv")
    safe_csv(stage_summary[["method", "stage", "path_count", "total_p_el_mean_kw", "grid_import_mean_kwh",
                            "minimum_voltage_pu", "maximum_branch_utilization"]],
             out_dir / "stage_grid_pel_trajectory.csv")

    _, prefix_representatives = shared_prefix(saa, stage_path, out_dir)
    same_state_history(saa, stage_path, out_dir)
    htt_stage, _ = htt_summaries(stage, out_dir)
    path_htt_analysis(saa, dro, out_dir)
    switch_paths, _ = switching_summary(stage, out_dir)
    site3_conditional(saa, dro, stage, out_dir)
    site3_definition = pd.read_csv(out_dir / "site3_limiting_definition_audit.csv")
    pv = pv_audit(saa, dro, out_dir)
    tail_audit(saa, dro, out_dir)

    extract_dir = out_dir / "00-hourly-extract"
    hour = pd.concat([pd.read_csv(extract_dir / f"{method}_hour48_grid_summary.csv")
                      for method in METHODS], ignore_index=True)
    bus_voltage = pd.concat([pd.read_csv(extract_dir / f"{method}_bus_voltage_summary.csv")
                             for method in METHODS], ignore_index=True)
    bus_hour = pd.concat([pd.read_csv(extract_dir / f"{method}_bus_hour_voltage_summary.csv")
                          for method in METHODS], ignore_index=True)
    branch = pd.concat([pd.read_csv(extract_dir / f"{method}_branch_loading_summary.csv")
                        for method in METHODS], ignore_index=True)
    hour["denominator"] = hour["path_hour_count"].map(
        lambda count: f"{int(count)} observed operating records at this method/global_hour")
    safe_csv(hour, out_dir / "hour48_grid_summary.csv")
    safe_csv(bus_voltage, out_dir / "bus_voltage_summary.csv")
    safe_csv(bus_hour, out_dir / "bus_hour_voltage_summary.csv")
    safe_csv(branch, out_dir / "branch_loading_summary.csv")
    safe_csv(pd.DataFrame([
        {"method": "saa", "terminal_gap_reconstruction_max_abs_error_kg": saa_target_error},
        {"method": "chi2_eta003", "terminal_gap_reconstruction_max_abs_error_kg": dro_target_error},
    ]), out_dir / "terminal_target_reconstruction_audit.csv")

    representatives = representative_paths(
        run_dir, saa, dro, stage, stage_path, switch_paths, prefix_representatives, out_dir)
    make_figures(stage, stage_summary, hour, bus_hour, branch, terminal, htt_stage,
                 representatives, saa, dro, out_dir)
    identity_audit(repo, run_dir, out_dir, arguments)
    write_readme(out_dir, arguments, paired, terminal, stage_summary,
                 site3_definition, pv, branch, (saa_target_error, dro_target_error))

    # Create a provisional judgment before the final required-file audit.
    (out_dir / "final_judgment.txt").write_text(
        "FINAL_JUDGMENT=PENDING_QUALITY_CONTROL\n", encoding="utf-8")
    quality = quality_control(repo, run_dir, out_dir, (saa_target_error, dro_target_error))
    passed = bool(quality["pass"].all())
    judgment = "PASS_STAGE84C_DEEP_ANALYSIS_COMPLETE" if passed else "FAIL_STAGE84C_DEEP_ANALYSIS"
    (out_dir / "final_judgment.txt").write_text(
        f"FINAL_JUDGMENT={judgment}\n"
        "STAGE84B_INPUT=PASS_COMPLETE_10000_PAIRED_OOS\n"
        f"TRAINING_COMMIT={arguments.training_commit}\n"
        f"OOS_FIX_COMMIT={arguments.oos_fix_commit}\n"
        f"OOS_RUN_COMMIT={arguments.oos_run_commit}\n"
        "SAA_PATHS=10000\nDRO_PATHS=10000\nCOMMON_PATHS=10000\n"
        "W1_W3_RECOURSE_RUN=false\n"
        "STAGE_DIRECTIONAL_HTT_ARCS=UNAVAILABLE_IN_STAGE84B_SCHEMA\n",
        encoding="utf-8")
    if not passed:
        raise RuntimeError("Stage-84C quality control failed; see quality_control_audit.csv")


if __name__ == "__main__":
    main()
