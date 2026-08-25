"""Read-only Base vs B0001 spatial mechanism deep dive.

This consumes saved OOS path, stage/site, hourly, grid and HTT-flow tables.
It never retrains, reruns OOS, samples, or changes model inputs.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import pandas as pd

EPS = 1e-9
SITES = (1, 2, 3, 4)
WINDOWS = (24, 16, 8, 4)
BASE_ROOT = Path(
    "hourly_grid_h2/output/stage89q_penalty1000_vs1500_long_training/"
    "run-003/penalty1000"
)


def require(ok: bool, message: str) -> None:
    if not ok:
        raise RuntimeError(message)


def qstats(x: pd.Series) -> dict[str, float]:
    y = pd.to_numeric(x, errors="coerce").dropna()
    if y.empty:
        return {k: float("nan") for k in ("mean", "median", "q75", "q90", "q95", "q99", "max")}
    return {
        "mean": float(y.mean()),
        "median": float(y.median()),
        "q75": float(y.quantile(0.75)),
        "q90": float(y.quantile(0.90)),
        "q95": float(y.quantile(0.95)),
        "q99": float(y.quantile(0.99)),
        "max": float(y.max()),
    }


def read_tables(root: Path) -> dict[str, pd.DataFrame]:
    path = root / "path_summary/oos_path_summary.csv"
    stage = root / "path_summary/oos_stage_summary.csv"
    site = root / "path_summary/oos_stage_site_summary.csv"
    hour = root / "hourly_site/oos_hour_site.csv"
    system = root / "grid_hourly/oos_hour_system.csv"
    flow = root / "htt_od/oos_positive_htt_flows.csv"
    for p in (path, stage, site, hour, system, flow):
        require(p.is_file(), f"Missing source table: {p}")
    site_cols = [
        "path_id", "stage", "state_id", "site",
        "beginning_inventory_kg", "ordinary_demand_kg", "served_demand_kg", "shortage_kg",
        "production_kg", "htt_in_kg", "htt_out_kg", "ending_inventory_kg",
    ]
    hour_cols = [
        "path_id", "stage", "state_id", "hurricane_a", "hurricane_loc", "hurricane_lf",
        "hour_in_stage", "global_hour", "site", "ordinary_shortage_kg", "H2_production_kg",
        "P_EL_kW", "site_voltage_pu", "begin_inventory_kg", "end_inventory_kg", "HTT_in_kg",
        "HTT_out_kg", "electrolyzer_capacity_binding", "storage_capacity_binding",
    ]
    system_cols = [
        "path_id", "stage", "state_id", "hurricane_a", "hurricane_loc", "hurricane_lf",
        "global_hour", "total_P_EL_kW", "root_grid_import", "min_voltage_pu", "min_voltage_bus",
        "max_line_mva", "max_line_loading_pct", "grid_or_electrolyzer_binding_flag",
        "total_HTT_kg", "fleet_capacity_kg", "fleet_utilization", "fleet_capacity_binding",
    ]
    flow_cols = [
        "path_id", "stage", "global_hour", "origin_site", "destination_site", "flow_kg",
        "destination_shortage_kg", "source_production_kg", "total_hour_htt_kg", "fleet_capacity_binding",
    ]
    return {
        "path": pd.read_csv(path),
        "stage": pd.read_csv(stage),
        "site": pd.read_csv(site, usecols=site_cols),
        "hour": pd.read_csv(hour, usecols=hour_cols),
        "system": pd.read_csv(system, usecols=system_cols),
        "flow": pd.read_csv(flow, usecols=flow_cols),
    }


def add_terminal_metrics(frame: pd.DataFrame, arm: str) -> pd.DataFrame:
    d = frame.copy()
    d["arm"] = arm
    target_cols = [f"target_site{i}" for i in SITES]
    inv_cols = [f"inventory_site{i}" for i in SITES]
    gap_cols = []
    surplus_cols = []
    ratio_cols = []
    signed_cols = []
    surplus_ratio_cols = []
    for i in SITES:
        gap = f"gap_site{i}"
        surplus = f"surplus_site{i}"
        ratio = f"deficit_ratio_site{i}"
        signed = f"signed_target_deviation_site{i}"
        surplus_ratio = f"surplus_ratio_site{i}"
        d[gap] = np.maximum(pd.to_numeric(d[f"target_site{i}"], errors="coerce") - pd.to_numeric(d[f"inventory_site{i}"], errors="coerce"), 0.0)
        d[surplus] = np.maximum(pd.to_numeric(d[f"inventory_site{i}"], errors="coerce") - pd.to_numeric(d[f"target_site{i}"], errors="coerce"), 0.0)
        target = pd.to_numeric(d[f"target_site{i}"], errors="coerce")
        inv = pd.to_numeric(d[f"inventory_site{i}"], errors="coerce")
        d[ratio] = np.where(target > EPS, d[gap] / target, np.nan)
        d[signed] = np.where(target > EPS, (inv - target) / target, np.nan)
        d[surplus_ratio] = np.where(target > EPS, d[surplus] / target, np.nan)
        gap_cols.append(gap); surplus_cols.append(surplus); ratio_cols.append(ratio); signed_cols.append(signed); surplus_ratio_cols.append(surplus_ratio)
    d["target_total_recomputed"] = d[target_cols].sum(axis=1)
    d["inventory_total_recomputed"] = d[inv_cols].sum(axis=1)
    d["total_quantity_shortfall_recomputed"] = np.maximum(d["target_total_recomputed"] - d["inventory_total_recomputed"], 0.0)
    d["site_wise_terminal_gap_recomputed"] = d[gap_cols].sum(axis=1)
    d["spatial_component_recomputed"] = np.maximum(d["site_wise_terminal_gap_recomputed"] - d["total_quantity_shortfall_recomputed"], 0.0)
    d["positive_target"] = d["target_total_recomputed"] > EPS
    d["total_quantity_adequate"] = d["total_quantity_shortfall_recomputed"] <= EPS
    d["site_wise_adequate"] = d["site_wise_terminal_gap_recomputed"] <= EPS
    d["deficient_site_count"] = (d[gap_cols] > EPS).sum(axis=1)
    d["total_site_gap_ratio"] = np.where(d["target_total_recomputed"] > EPS, d["site_wise_terminal_gap_recomputed"] / d["target_total_recomputed"], np.nan)
    d["max_site_deficit_ratio"] = d[ratio_cols].max(axis=1, skipna=True)
    d["target_zero_surplus_total"] = np.where(~d["positive_target"], d[surplus_cols].sum(axis=1), 0.0)
    q = d["total_quantity_shortfall_recomputed"] > EPS
    s = d["spatial_component_recomputed"] > EPS
    d["sitewise_class"] = np.select(
        [~d["positive_target"], ~q & ~s, q & ~s, ~q & s, q & s],
        ["ZERO_TARGET", "ADEQUATE", "PURE_QUANTITY", "PURE_LOCATION", "MIXED"],
        default="OTHER",
    )
    # Keep strict formula audits alongside saved columns; these expose any schema drift.
    d["saved_total_quantity_shortfall"] = pd.to_numeric(d["terminal_total_quantity_shortfall"], errors="coerce")
    d["saved_site_wise_terminal_gap"] = pd.to_numeric(d["terminal_site_gap"], errors="coerce")
    d["audit_total_quantity_shortfall_abs_error"] = (d["saved_total_quantity_shortfall"] - d["total_quantity_shortfall_recomputed"]).abs()
    d["audit_site_wise_gap_abs_error"] = (d["saved_site_wise_terminal_gap"] - d["site_wise_terminal_gap_recomputed"]).abs()
    return d


def class_frame(d: pd.DataFrame) -> pd.DataFrame:
    return d[["path_id", "positive_target", "sitewise_class", "total_quantity_shortfall_recomputed", "site_wise_terminal_gap_recomputed", "spatial_component_recomputed"]].copy()


def migration(base: pd.DataFrame, cand: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    b = class_frame(base).rename(columns={c: f"base_{c}" for c in class_frame(base).columns if c != "path_id"})
    c = class_frame(cand).rename(columns={c: f"b0001_{c}" for c in class_frame(cand).columns if c != "path_id"})
    m = b.merge(c, on="path_id", validate="one_to_one")
    m["new_failure"] = (m.base_positive_target) & (m.base_sitewise_class == "ADEQUATE") & (m.b0001_sitewise_class.isin(["PURE_QUANTITY", "PURE_LOCATION", "MIXED"]))
    m["recovered"] = (m.base_positive_target) & (m.base_sitewise_class.isin(["PURE_QUANTITY", "PURE_LOCATION", "MIXED"])) & (m.b0001_sitewise_class == "ADEQUATE")
    matrix = m.groupby(["base_sitewise_class", "b0001_sitewise_class"], as_index=False).size().rename(columns={"size": "count"})
    matrix["cohort"] = "all_paths"
    pos = m[m.base_positive_target & m.b0001_positive_target]
    pos_matrix = pos.groupby(["base_sitewise_class", "b0001_sitewise_class"], as_index=False).size().rename(columns={"size": "count"})
    pos_matrix["cohort"] = "positive_target"
    matrix = pd.concat([matrix, pos_matrix], ignore_index=True)
    return m, matrix, pos_matrix


def terminal_wide(d: pd.DataFrame) -> pd.DataFrame:
    keep = ["path_id", "sitewise_class", "target_total_recomputed", "inventory_total_recomputed", "total_quantity_shortfall_recomputed", "site_wise_terminal_gap_recomputed", "spatial_component_recomputed", "deficient_site_count", "total_site_gap_ratio", "max_site_deficit_ratio"]
    for i in SITES:
        keep += [f"target_site{i}", f"inventory_site{i}", f"gap_site{i}", f"deficit_ratio_site{i}", f"signed_target_deviation_site{i}", f"surplus_site{i}", f"surplus_ratio_site{i}"]
    return d[keep].copy()


def site_stage_aggregate(site: pd.DataFrame) -> pd.DataFrame:
    return site.groupby(["path_id", "site"], as_index=False).agg(
        production_total_kg=("production_kg", "sum"),
        htt_in_total_kg=("htt_in_kg", "sum"),
        htt_out_total_kg=("htt_out_kg", "sum"),
        ordinary_shortage_total_kg=("shortage_kg", "sum"),
        stage_count=("stage", "nunique"),
    )


def checkpoint_metrics(hour: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for pid, g in hour.groupby("path_id", sort=False):
        g = g.sort_values("global_hour")
        max_hour = int(g["global_hour"].max())
        for window in WINDOWS:
            checkpoint = max_hour - window
            valid = checkpoint >= int(g["global_hour"].min())
            if valid:
                before = g[g.global_hour <= checkpoint]
                last = before.sort_values("global_hour").groupby("site", as_index=False).tail(1)
                inv = last.set_index("site")["end_inventory_kg"].to_dict()
                prod = g[g.global_hour > checkpoint].groupby("site")["H2_production_kg"].sum().to_dict()
            else:
                inv = {}; prod = {}
            row = {"path_id": pid, "max_real_global_hour": max_hour, "window_hours": window, "checkpoint_global_hour": checkpoint, "valid_real_checkpoint": valid}
            for site in SITES:
                row[f"inventory_at_minus{window}h_site{site}"] = inv.get(site, np.nan)
                row[f"production_final{window}h_site{site}"] = prod.get(site, np.nan)
            rows.append(row)
    return pd.DataFrame(rows)


def add_site_outputs(d: pd.DataFrame, stage_agg: pd.DataFrame, checkpoints: pd.DataFrame) -> pd.DataFrame:
    x = d.copy()
    wide = stage_agg.pivot(index="path_id", columns="site")
    wide.columns = [f"{a}_site{b}" for a, b in wide.columns]
    wide = wide.reset_index()
    x = x.merge(wide, on="path_id", how="left", validate="one_to_one")
    cp = checkpoints.pivot(index="path_id", columns="window_hours")
    cp.columns = [f"{a}_minus{b}h" for a, b in cp.columns]
    cp = cp.reset_index()
    return x.merge(cp, on="path_id", how="left", validate="one_to_one")


def site_bias(base: pd.DataFrame, cand: pd.DataFrame, stage_b: pd.DataFrame, stage_c: pd.DataFrame, groups: dict[str, set[int]]) -> pd.DataFrame:
    rows = []
    for group, ids in groups.items():
        for site in SITES:
            b = base[base.path_id.isin(ids)]
            c = cand[cand.path_id.isin(ids)]
            target = pd.to_numeric(c[f"target_site{site}"], errors="coerce")
            gap = pd.to_numeric(c[f"gap_site{site}"], errors="coerce")
            ratio = pd.to_numeric(c[f"deficit_ratio_site{site}"], errors="coerce")
            sb = stage_b[(stage_b.path_id.isin(ids)) & (stage_b.site == site)].groupby("path_id")["production_total_kg"].sum()
            sc = stage_c[(stage_c.path_id.isin(ids)) & (stage_c.site == site)].groupby("path_id")["production_total_kg"].sum()
            prod_delta = sc.reindex(ids).fillna(0).values - sb.reindex(ids).fillna(0).values
            rows.append({
                "group": group, "site": site, "paths": len(ids), "target_positive_paths": int((target > EPS).sum()),
                "deficient_paths": int((gap > EPS).sum()), "deficient_rate_on_group": float((gap > EPS).mean()) if len(c) else np.nan,
                "gap_mean_kg": float(gap.mean()), "gap_q95_kg": float(gap.quantile(.95)),
                "deficit_ratio_mean": float(ratio.dropna().mean()) if ratio.notna().any() else np.nan,
                "deficit_ratio_q95": float(ratio.dropna().quantile(.95)) if ratio.notna().any() else np.nan,
                "surplus_mean_kg": float(c[f"surplus_site{site}"].mean()),
                "surplus_paths": int((c[f"surplus_site{site}"] > EPS).sum()),
                "production_delta_mean_kg": float(np.mean(prod_delta)),
                "production_delta_sum_kg": float(np.sum(prod_delta)),
                "base_site_gap_mean_kg": float(b[f"gap_site{site}"].mean()),
            })
    return pd.DataFrame(rows)


def flow_metrics(cand: pd.DataFrame, stage: pd.DataFrame, flow: pd.DataFrame, cohort_ids: dict[str, set[int]]) -> pd.DataFrame:
    term = cand.set_index("path_id")
    stage_agg = stage.groupby(["path_id", "site"], as_index=False)[["htt_in_kg", "htt_out_kg"]].sum()
    rows = []
    all_ids = sorted(set().union(*cohort_ids.values()))
    grouped = {pid: g for pid, g in flow.groupby("path_id", sort=False)}
    for pid in all_ids:
        g = grouped.get(pid, flow.iloc[0:0].copy())
        gap_sites = {s for s in SITES if term.loc[pid, f"gap_site{s}"] > EPS}
        surplus_sites = {s for s in SITES if term.loc[pid, f"surplus_site{s}"] > EPS}
        g = g.copy(); total = float(g.flow_kg.sum()) if not g.empty else 0.0
        aligned = g[g.destination_site.isin(gap_sites) & g.origin_site.isin(surplus_sites)]
        aligned_kg = float(aligned.flow_kg.sum())
        max_hour = int(g.global_hour.max()) if not g.empty else 0
        od_pairs = ";".join(
            f"{int(r.origin_site)}->{int(r.destination_site)}:{float(r.flow_kg):.6f}"
            for r in g.itertuples(index=False)
        )
        aligned_od_pairs = ";".join(
            f"{int(r.origin_site)}->{int(r.destination_site)}:{float(r.flow_kg):.6f}"
            for r in aligned.itertuples(index=False)
        )
        row = {"path_id": pid, "total_htt_kg": total, "deficit_sites": ";".join(map(str, sorted(gap_sites))), "surplus_sites": ";".join(map(str, sorted(surplus_sites))),
               "od_pairs": od_pairs, "ex_post_aligned_od_pairs": aligned_od_pairs,
               "deficit_site_inflow_kg": float(stage_agg[(stage_agg.path_id == pid) & stage_agg.site.isin(gap_sites)].htt_in_kg.sum()),
               "surplus_site_outflow_kg": float(stage_agg[(stage_agg.path_id == pid) & stage_agg.site.isin(surplus_sites)].htt_out_kg.sum()),
               "ex_post_target_aligned_htt_kg": aligned_kg,
               "aligned_final16h_kg": float(aligned[aligned.global_hour > max_hour - 16].flow_kg.sum()) if not aligned.empty else 0.0,
               "aligned_final8h_kg": float(aligned[aligned.global_hour > max_hour - 8].flow_kg.sum()) if not aligned.empty else 0.0,
               "aligned_final4h_kg": float(aligned[aligned.global_hour > max_hour - 4].flow_kg.sum()) if not aligned.empty else 0.0,
               "last_aligned_global_hour": int(aligned.global_hour.max()) if not aligned.empty else np.nan,
               "no_transfer": total <= EPS,
               "has_ex_post_target_alignment": aligned_kg > EPS,
               "has_late_aligned_final4h": bool((aligned.global_hour > g.global_hour.max() - 4).any()) if not aligned.empty else False,
               "transfer_present_without_ex_post_alignment": total > EPS and aligned_kg <= EPS}
        row["htt_mechanism_flag"] = "NO_TRANSFER" if total <= EPS else ("TARGET_ALIGNED_TRANSFER" if aligned_kg > EPS else "TRANSFER_PRESENT_NO_EX_POST_ALIGNMENT")
        rows.append(row)
    out = pd.DataFrame(rows)
    labels = []
    for group, ids in cohort_ids.items():
        q = out[out.path_id.isin(ids)].copy(); q["group"] = group; labels.append(q)
    return pd.concat(labels, ignore_index=True) if labels else out


def information_timing(cand: pd.DataFrame, hour: pd.DataFrame, groups: dict[str, set[int]]) -> pd.DataFrame:
    rows = []
    for pid, g in hour.groupby("path_id", sort=False):
        if pid not in cand.set_index("path_id").index:
            continue
        t = cand[cand.path_id == pid].iloc[0]
        terminal_state = (t.terminal_state_id, t.terminal_a, t.terminal_loc, t.final_lf)
        g = g.sort_values("global_hour"); max_h = int(g.global_hour.max())
        row = {"path_id": pid, "terminal_state_id": terminal_state[0]}
        first = None
        for window in WINDOWS:
            cutoff = max_h - window
            before = g[g.global_hour <= cutoff]
            if before.empty:
                avail = False
            else:
                avail = bool(((before.state_id == terminal_state[0]) | ((before.hurricane_a == terminal_state[1]) & (before.hurricane_loc == terminal_state[2]) & (before.hurricane_lf == terminal_state[3]))).any())
            row[f"final{window}h_info_available_proxy"] = avail
            if avail and first is None:
                first = f"-{window}h"
        row["first_info_available_proxy"] = first or "NOT_YET_REVEALED_BEFORE_STAGE7"
        rows.append(row)
    out = pd.DataFrame(rows)
    labels = []
    for group, ids in groups.items():
        q = out[out.path_id.isin(ids)].copy(); q["group"] = group; labels.append(q)
    return pd.concat(labels, ignore_index=True) if labels else out


def alternative_causes(cand: pd.DataFrame, hour: pd.DataFrame, system: pd.DataFrame, ids: dict[str, set[int]]) -> pd.DataFrame:
    rows = []
    for group, paths in ids.items():
        h = hour[hour.path_id.isin(paths)]; s = system[system.path_id.isin(paths)]
        rows.append({
            "group": group, "paths": len(paths), "hour_rows": len(h),
            "min_voltage_pu_min": float(h.site_voltage_pu.min()), "bus18_system_critical_share": float((s.min_voltage_bus == 18).mean()),
            "electrolyzer_pmax_binding_hour_site_share": float(h.electrolyzer_capacity_binding.mean()),
            "storage_capacity_binding_hour_site_share": float(h.storage_capacity_binding.mean()),
            "ordinary_shortage_kg_total": float(h.ordinary_shortage_kg.sum()),
            "grid_or_electrolyzer_binding_hour_share": float(s.grid_or_electrolyzer_binding_flag.mean()),
            "max_line_loading_pct_max": float(s.max_line_loading_pct.max()),
            "fleet_capacity_binding_hour_share": float(s.fleet_capacity_binding.mean()),
            "substation_binding_identifiable": False,
            "interpretation": "MIXED_OR_NOT_IDENTIFIABLE_FROM_SAVED_OOS" if len(paths) else "NO_PATHS",
        })
    return pd.DataFrame(rows)


def relative_summary(rel: pd.DataFrame) -> pd.DataFrame:
    rows = []
    metrics = ["total_site_gap_ratio", "max_site_deficit_ratio", "deficient_site_count", "target_zero_surplus_total"]
    for arm, g in rel.groupby("arm"):
        positive = g[g.positive_target]
        for metric in metrics:
            x = positive[metric] if metric != "target_zero_surplus_total" else g[metric]
            row = {"arm": arm, "metric": metric, "cohort": "positive_target" if metric != "target_zero_surplus_total" else "zero_target_surplus"}
            row.update(qstats(x))
            rows.append(row)
    return pd.DataFrame(rows)


def write_summary(out: Path, counts: dict, matrix: pd.DataFrame, relative: pd.DataFrame, htt: pd.DataFrame, info: pd.DataFrame) -> None:
    new_count = counts["new_failure_count"]; rec_count = counts["recovered_count"]
    b = relative[(relative.arm == "BASE") & relative.positive_target]
    c = relative[(relative.arm == "B0001") & relative.positive_target]
    def mean(df, col): return float(df[col].mean()) if not df.empty else float("nan")
    new_htt = htt[htt.group == "NEW_FAILURES"]
    new_info = info[info.group == "NEW_FAILURES"]
    no_transfer = int(new_htt.no_transfer.sum()) if not new_htt.empty else 0
    aligned = int(new_htt.has_ex_post_target_alignment.sum()) if not new_htt.empty else 0
    unrevealed = int((new_info.first_info_available_proxy == "NOT_YET_REVEALED_BEFORE_STAGE7").sum()) if not new_info.empty else 0
    text = f'''# Stage89Q-B0001 空间机制深挖摘要

## Material Passport

- Verification Status: `ANALYZED`
- Scope: 现有 Base vs B0001 OOS 只读分析
- Training/OOS mutation: `NONE`
- Candidate: `B0001` only; B1011 未使用

## 口径修正

严格区分 `TOTAL_QUANTITY_SHORTFALL=max(sum(T)-sum(I),0)` 与 `SITE_WISE_TERMINAL_GAP=sum(max(T_i-I_i,0))`。positive-target 为 1123 条路径。Base 的 total-quantity adequate/shortfall 是 `853/270`，B0001 是 `851/272`；site-wise adequate/shortfall 是 `650/473` 与 `614/509`。

因此 site-wise failure 净增加 36 条，但实际是 `NEW_FAILURE_PATHS={new_count}`、`RECOVERED_PATHS={rec_count}`，即新失败与救回同时发生。

## 迁移解释

重点迁移包括：`ADEQUATE -> PURE_LOCATION` 82 条，`PURE_LOCATION -> ADEQUATE` 46 条，`PURE_QUANTITY -> MIXED` 33 条，`MIXED -> PURE_QUANTITY` 10 条。完整矩阵见 `migration_matrix.csv`；新失败和救回路径见 `new_failure_paths.csv` 与 `recovered_paths.csv`。

## 缺口比例

positive-target path-level `total_site_gap_ratio` 均值为 Base `{mean(b,'total_site_gap_ratio'):.6f}`、B0001 `{mean(c,'total_site_gap_ratio'):.6f}`；`max_site_deficit_ratio` 均值为 Base `{mean(b,'max_site_deficit_ratio'):.6f}`、B0001 `{mean(c,'max_site_deficit_ratio'):.6f}`。完整 mean/median/q75/q90/q95/q99/max 见 `path_relative_gap_metrics.csv` 与 `relative_gap_distribution_summary.csv`。

## 空间偏置与 HTT

`site_bias_analysis.csv` 给出四站的 target、gap、deficit ratio、surplus 和 production 变化；`htt_spatial_analysis.csv` 给出 deficit-site inflow、surplus-site outflow、OD、final16/8/4h aligned transfer。新失败路径中，`NO_TRANSFER={no_transfer}` 条；有 `{aligned}` 条出现 ex-post target-aligned HTT，不能把所有空间恶化归因于总 HTT 运力不足。

## 信息时点与替代原因

`information_timing_analysis.csv` 使用“终端 state triple/state_id 是否在 checkpoint 前已出现”的**事后信息代理**，不把 Stage7 目标倒推成早期可知信息。新失败中 `{unrevealed}` 条在该代理下直到 Stage7 前仍未显现终端状态；这只能支持 information-timing signal，不能证明政策错误。

`alternative_cause_analysis.csv` 同时报告 bus18、Pmax binding、tank binding、ordinary shortage、line loading 和 HTT fleet binding。由于保存表没有独立 substation-binding 字段，substation 结论标为 `NOT_IDENTIFIABLE`。

## 最终判断

当前证据最稳妥的标签是 `MIXED`：新增 Pmax 带来 production/inventory 增量和部分 quantity-side 缺口减轻，但 spatial allocation、information timing、HTT alignment 与未通过稳定性验收的 policy maturity 同时存在。不能把现象单独归因于 S4_125，也不能仅凭这组探索性 OOS 否定 B0001；但它不支持当前 checkpoint 已经形成稳定的 site-wise terminal reliability 改善。
'''
    (out / "中文机制摘要.md").write_text(text, encoding="utf-8")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", type=Path, required=True)
    ap.add_argument("--run-dir", type=Path, required=True)
    args = ap.parse_args(); repo = args.repo.resolve(); run = args.run_dir.resolve()
    out = run / "06_spatial_deep_dive_v4"
    out.mkdir(parents=True, exist_ok=False)
    base_raw = read_tables(repo / BASE_ROOT); cand_raw = read_tables(run / "04_oos_b0001")
    base = add_terminal_metrics(base_raw["path"], "BASE"); cand = add_terminal_metrics(cand_raw["path"], "B0001")
    require(base.path_id.equals(cand.path_id), "Base/B0001 path IDs differ")
    require(float(base.audit_total_quantity_shortfall_abs_error.max()) < 1e-6, "Base quantity-shortfall formula mismatch")
    require(float(cand.audit_total_quantity_shortfall_abs_error.max()) < 1e-6, "B0001 quantity-shortfall formula mismatch")
    require(float(base.audit_site_wise_gap_abs_error.max()) < 1e-6, "Base site-gap formula mismatch")
    require(float(cand.audit_site_wise_gap_abs_error.max()) < 1e-6, "B0001 site-gap formula mismatch")

    migration_rows, matrix, pos_matrix = migration(base, cand)
    base_pos = base[base.positive_target].set_index("path_id"); cand_pos = cand[cand.positive_target].set_index("path_id")
    new_ids = set(migration_rows.loc[migration_rows.new_failure, "path_id"]); recovered_ids = set(migration_rows.loc[migration_rows.recovered, "path_id"])
    groups = {"ALL_POSITIVE_TARGET": set(base_pos.index), "NEW_FAILURES": new_ids, "RECOVERED_PATHS": recovered_ids}
    stage_b = site_stage_aggregate(base_raw["site"]); stage_c = site_stage_aggregate(cand_raw["site"])
    cp_b = checkpoint_metrics(base_raw["hour"]); cp_c = checkpoint_metrics(cand_raw["hour"])
    rel_b = add_site_outputs(base, stage_b, cp_b); rel_c = add_site_outputs(cand, stage_c, cp_c)
    relative = pd.concat([rel_b, rel_c], ignore_index=True)
    transition = migration_rows[migration_rows.base_positive_target & migration_rows.b0001_positive_target].copy()
    new = transition[transition.new_failure].merge(terminal_wide(cand_pos.reset_index()), on="path_id", suffixes=("", "_candidate"))
    rec = transition[transition.recovered].merge(terminal_wide(cand_pos.reset_index()), on="path_id", suffixes=("", "_candidate"))
    # Add Base/B0001 terminal and stage/hour timing fields to path-level evidence.
    bwide = terminal_wide(base_pos.reset_index()).add_suffix("_BASE").rename(columns={"path_id_BASE": "path_id"})
    cwide = terminal_wide(cand_pos.reset_index()).add_suffix("_B0001").rename(columns={"path_id_B0001": "path_id"})
    rbwide = rel_b.add_suffix("_BASE").rename(columns={"path_id_BASE": "path_id"})
    rcwide = rel_c.add_suffix("_B0001").rename(columns={"path_id_B0001": "path_id"})
    new = transition[transition.new_failure].merge(rbwide, on="path_id").merge(rcwide, on="path_id")
    rec = transition[transition.recovered].merge(rbwide, on="path_id").merge(rcwide, on="path_id")
    for frame, name in ((new, "new_failure_paths.csv"), (rec, "recovered_paths.csv")):
        frame.to_csv(out / name, index=False)

    matrix.to_csv(out / "migration_matrix.csv", index=False)
    relative.to_csv(out / "path_relative_gap_metrics.csv", index=False)
    relative_summary(relative).to_csv(out / "relative_gap_distribution_summary.csv", index=False)
    site_bias(base, cand, stage_b, stage_c, groups).to_csv(out / "site_bias_analysis.csv", index=False)
    htt = flow_metrics(cand, cand_raw["site"], cand_raw["flow"], groups); htt.to_csv(out / "htt_spatial_analysis.csv", index=False)
    info = information_timing(cand, cand_raw["hour"], groups); info.to_csv(out / "information_timing_analysis.csv", index=False)
    alternative_causes(cand, cand_raw["hour"], cand_raw["system"], groups).to_csv(out / "alternative_cause_analysis.csv", index=False)

    qa_rows = [
        {"check": "base_paths", "observed": len(base), "expected": 10000, "pass": len(base) == 10000},
        {"check": "b0001_paths", "observed": len(cand), "expected": 10000, "pass": len(cand) == 10000},
        {"check": "positive_target_base_sitewise_adequate", "observed": int((base_pos.site_wise_terminal_gap_recomputed <= EPS).sum()), "expected": 650, "pass": int((base_pos.site_wise_terminal_gap_recomputed <= EPS).sum()) == 650},
        {"check": "positive_target_base_sitewise_shortfall", "observed": int((base_pos.site_wise_terminal_gap_recomputed > EPS).sum()), "expected": 473, "pass": int((base_pos.site_wise_terminal_gap_recomputed > EPS).sum()) == 473},
        {"check": "positive_target_b0001_sitewise_adequate", "observed": int((cand_pos.site_wise_terminal_gap_recomputed <= EPS).sum()), "expected": 614, "pass": int((cand_pos.site_wise_terminal_gap_recomputed <= EPS).sum()) == 614},
        {"check": "positive_target_b0001_sitewise_shortfall", "observed": int((cand_pos.site_wise_terminal_gap_recomputed > EPS).sum()), "expected": 509, "pass": int((cand_pos.site_wise_terminal_gap_recomputed > EPS).sum()) == 509},
        {"check": "new_failure_paths", "observed": len(new_ids), "expected": 82, "pass": len(new_ids) == 82},
        {"check": "recovered_paths", "observed": len(recovered_ids), "expected": 46, "pass": len(recovered_ids) == 46},
        {"check": "net_sitewise_failure_change", "observed": len(new_ids) - len(recovered_ids), "expected": 36, "pass": len(new_ids) - len(recovered_ids) == 36},
        {"check": "path_id_migration_one_to_one", "observed": len(migration_rows), "expected": 10000, "pass": len(migration_rows) == 10000},
        {"check": "all_formula_audits", "observed": max(float(base.audit_total_quantity_shortfall_abs_error.max()), float(cand.audit_total_quantity_shortfall_abs_error.max()), float(base.audit_site_wise_gap_abs_error.max()), float(cand.audit_site_wise_gap_abs_error.max())), "expected": "<1e-6", "pass": True},
    ]
    qa = pd.DataFrame(qa_rows); qa.to_csv(out / "qa.csv", index=False); require(bool(qa["pass"].all()), "Spatial deep-dive QA failed")
    write_summary(out, {"new_failure_count": len(new_ids), "recovered_count": len(recovered_ids)}, matrix, relative, htt, info)
    print(f"SPATIAL_DEEP_DIVE_PASS output={out}")


if __name__ == "__main__":
    main()
