"""Stage-90A2 read-only terminal redistribution capacity audit.

This script consumes only the saved Base and exploratory B0001 common-path OOS
path summaries.  It computes the analytical spatial-rebalancing requirement
and capacity truncation; it never calls MATLAB, Gurobi, or the formal Stage7
model.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "hourly_grid_h2/output/stage89q_penalty1000_vs1500_long_training/run-003/penalty1000"
B0001 = ROOT / "results/task-002-stage2b-b3-smoke/stage89q-pmax-b0001-exploratory-oos/run-001/04_oos_b0001"
RESULT_ROOT = ROOT / "results/task-002-stage2b-b3-smoke/stage90a2-terminal-capacity-sufficiency"
TOL = 1e-9
PENALTY_YUAN_PER_KG = 1000.0
SITE_IDS = (1, 2, 3, 4)
TARGET_COLS = [f"target_site{i}" for i in SITE_IDS]
INVENTORY_COLS = [f"inventory_site{i}" for i in SITE_IDS]
IDENTITY_NUMERIC_COLS = [
    "path_id", "termination_stage", "termination_state", "operating_stage_count",
    "reached_stage7", "terminal_state_id", "terminal_a", "terminal_loc",
    *TARGET_COLS, "target_total", "final_a", "final_loc", "final_lf",
]
IDENTITY_TEXT_COLS = ["state_sequence", "termination_type"]
CAPACITIES = [("40", 40.0), ("80", 80.0), ("160", 160.0), ("inf", np.inf)]
GROUP_ORDER = [
    "all", "positive_target", "sitewise_failure", "PURE_LOCATION", "PURE_QUANTITY",
    "MIXED", "difficult4", "extreme1",
]


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def add_check(checks: list[dict], check_id: str, passed: bool, detail: str, source: str = "") -> None:
    checks.append({
        "check_id": check_id,
        "status": "PASS" if passed else "FAIL",
        "source": source,
        "detail": detail,
    })


def numeric_diff(left: pd.Series, right: pd.Series) -> tuple[float, bool]:
    a = pd.to_numeric(left, errors="coerce").to_numpy(dtype=float)
    b = pd.to_numeric(right, errors="coerce").to_numpy(dtype=float)
    finite_pair = np.isfinite(a) & np.isfinite(b)
    both_nan = np.isnan(a) & np.isnan(b)
    equal = np.all((finite_pair & np.isclose(a, b, atol=1e-12, rtol=0.0)) | both_nan)
    if np.any(finite_pair):
        diff = float(np.max(np.abs(a[finite_pair] - b[finite_pair])))
    else:
        diff = 0.0
    return diff, bool(equal)


def read_source(label: str, folder: Path, checks: list[dict]) -> tuple[pd.DataFrame, pd.DataFrame]:
    path = folder / "path_summary/oos_path_summary.csv"
    metadata_path = folder / "oos_metadata.csv"
    add_check(checks, f"{label}_path_summary_exists", path.is_file(), str(path), label)
    add_check(checks, f"{label}_metadata_exists", metadata_path.is_file(), str(metadata_path), label)
    if not path.is_file() or not metadata_path.is_file():
        raise FileNotFoundError(f"Missing {label} source: {path} or {metadata_path}")
    frame = pd.read_csv(path)
    metadata = pd.read_csv(metadata_path)
    add_check(checks, f"{label}_rows_10000", len(frame) == 10000, f"rows={len(frame)}", label)
    if len(metadata) != 1:
        add_check(checks, f"{label}_metadata_one_row", False, f"rows={len(metadata)}", label)
        raise RuntimeError(f"Unexpected metadata rows for {label}: {len(metadata)}")
    meta = metadata.iloc[0]
    requested = int(meta["requested_paths"])
    completed = int(meta["completed_paths"])
    passed = int(meta["pass"]) == 1
    add_check(checks, f"{label}_metadata_completion", requested == 10000 and completed == 10000 and passed,
             f"requested={requested}; completed={completed}; pass={int(meta['pass'])}", label)
    return frame, metadata


def verify_identity(base: pd.DataFrame, b0001: pd.DataFrame, base_meta: pd.DataFrame,
                    b0001_meta: pd.DataFrame, checks: list[dict]) -> None:
    base_ids = pd.to_numeric(base["path_id"], errors="coerce").to_numpy()
    b_ids = pd.to_numeric(b0001["path_id"], errors="coerce").to_numpy()
    expected = np.arange(1, 10001)
    add_check(checks, "base_ordered_path_ids", np.array_equal(base_ids, expected),
             f"first={base_ids[0]}; last={base_ids[-1]}", "Base")
    add_check(checks, "b0001_ordered_path_ids", np.array_equal(b_ids, expected),
             f"first={b_ids[0]}; last={b_ids[-1]}", "B0001")
    add_check(checks, "common_ordered_path_ids", np.array_equal(base_ids, b_ids), "max_id_diff=0", "Base/B0001")

    identity_ok = True
    for col in IDENTITY_TEXT_COLS:
        equal = base[col].astype(str).equals(b0001[col].astype(str))
        add_check(checks, f"common_identity_{col}", equal, f"equal={equal}", "Base/B0001")
        identity_ok &= equal
    for col in IDENTITY_NUMERIC_COLS:
        diff, equal = numeric_diff(base[col], b0001[col])
        add_check(checks, f"common_identity_{col}", equal, f"max_abs_diff={diff:.6g}", "Base/B0001")
        identity_ok &= equal

    for col in TARGET_COLS + ["target_total"]:
        diff, equal = numeric_diff(base[col], b0001[col])
        add_check(checks, f"terminal_target_unchanged_{col}", equal, f"max_abs_diff={diff:.6g}", "Base/B0001")
        identity_ok &= equal

    base_bank = str(base_meta.iloc[0]["bank_sha256"])
    b_bank = str(b0001_meta.iloc[0]["bank_sha256"])
    add_check(checks, "common_bank_sha256", base_bank == b_bank, f"Base={base_bank}; B0001={b_bank}", "Base/B0001")
    identity_ok &= base_bank == b_bank

    for label, frame in (("Base", base), ("B0001", b0001)):
        inv = frame[INVENTORY_COLS].to_numpy(dtype=float)
        finite = bool(np.isfinite(inv).all())
        add_check(checks, f"{label.lower()}_final_inventory_available", finite,
                 f"finite_cells={int(np.isfinite(inv).sum())}/{inv.size}", label)
        identity_ok &= finite
        total_diff = np.max(np.abs(inv.sum(axis=1) - pd.to_numeric(frame["terminal_inventory_total"]).to_numpy()))
        add_check(checks, f"{label.lower()}_inventory_total_consistency", total_diff <= 1e-9,
                 f"max_abs_diff={total_diff:.6g}", label)
        identity_ok &= total_diff <= 1e-9
    if not identity_ok:
        raise RuntimeError("Stage-90A2 STOP: common-path identity or final-inventory gate failed")


def tail_ids(base: pd.DataFrame) -> tuple[set[int], set[int]]:
    reached = pd.to_numeric(base["reached_stage7"], errors="coerce").eq(1)
    ordered = base.loc[reached, ["path_id", "terminal_site_gap"]].copy()
    ordered["path_id"] = pd.to_numeric(ordered["path_id"], errors="raise").astype(int)
    ordered["terminal_site_gap"] = pd.to_numeric(ordered["terminal_site_gap"], errors="raise")
    ordered = ordered.sort_values(["terminal_site_gap", "path_id"], ascending=[False, True], kind="mergesort")
    extreme = set(ordered.head(62)["path_id"])
    difficult = set(ordered.iloc[62:307]["path_id"])
    return difficult, extreme


def calculate(policy: str, frame: pd.DataFrame, difficult_ids: set[int], extreme_ids: set[int],
              checks: list[dict]) -> pd.DataFrame:
    target = frame[TARGET_COLS].to_numpy(dtype=float)
    inventory = frame[INVENTORY_COLS].to_numpy(dtype=float)
    deficits = np.maximum(target - inventory, 0.0)
    surpluses = np.maximum(inventory - target, 0.0)
    d_site = deficits.sum(axis=1)
    s_site = surpluses.sum(axis=1)
    q_total = np.maximum(target.sum(axis=1) - inventory.sum(axis=1), 0.0)
    k_formula = d_site - q_total
    k_equiv = np.minimum(d_site, s_site)
    raw_min = float(k_formula.min())
    formula_error = float(np.max(np.abs(k_formula - k_equiv)))
    add_check(checks, f"{policy.lower()}_k_nonnegative", raw_min >= -TOL, f"min_raw_k={raw_min:.12g}", policy)
    add_check(checks, f"{policy.lower()}_k_identity", formula_error <= TOL,
             f"max_abs_error={formula_error:.12g}", policy)
    k_req = np.maximum(k_formula, 0.0)
    saved_gap = pd.to_numeric(frame["terminal_site_gap"], errors="raise").to_numpy(dtype=float)
    saved_spatial = pd.to_numeric(frame["terminal_spatial_component"], errors="raise").to_numpy(dtype=float)
    gap_error = float(np.max(np.abs(saved_gap - d_site)))
    spatial_error = float(np.max(np.abs(saved_spatial - k_req)))
    add_check(checks, f"{policy.lower()}_saved_site_gap_recompute", gap_error <= TOL,
             f"max_abs_error={gap_error:.12g}", policy)
    add_check(checks, f"{policy.lower()}_saved_spatial_component_recompute", spatial_error <= TOL,
             f"max_abs_error={spatial_error:.12g}", policy)

    out = frame.copy()
    out.insert(0, "policy", policy)
    out["D_site_kg"] = d_site
    out["S_site_kg"] = s_site
    out["Q_total_kg"] = q_total
    out["K_req_kg"] = k_req
    out["K_req_formula_minus_equiv_kg"] = k_formula - k_equiv
    out["positive_target"] = pd.to_numeric(out["target_total"]).to_numpy() > TOL
    out["sitewise_failure"] = d_site > TOL
    out["failure_type"] = out["terminal_gap_class"].map({
        "PURE_SPATIAL_MISMATCH": "PURE_LOCATION",
        "PURE_QUANTITY_SHORTFALL": "PURE_QUANTITY",
        "MIXED_QUANTITY_AND_SPATIAL": "MIXED",
        "NO_GAP": "NO_GAP",
    }).fillna("OTHER")
    path_ids = pd.to_numeric(out["path_id"], errors="raise").astype(int)
    out["tail_group"] = "not_stage7_tail"
    out.loc[path_ids.isin(difficult_ids), "tail_group"] = "difficult4"
    out.loc[path_ids.isin(extreme_ids), "tail_group"] = "extreme1"
    return out


def group_masks(frame: pd.DataFrame) -> dict[str, pd.Series]:
    return {
        "all": pd.Series(True, index=frame.index),
        "positive_target": frame["positive_target"],
        "sitewise_failure": frame["sitewise_failure"],
        "PURE_LOCATION": frame["failure_type"].eq("PURE_LOCATION"),
        "PURE_QUANTITY": frame["failure_type"].eq("PURE_QUANTITY"),
        "MIXED": frame["failure_type"].eq("MIXED"),
        "difficult4": frame["tail_group"].eq("difficult4"),
        "extreme1": frame["tail_group"].eq("extreme1"),
    }


def distribution(frame: pd.DataFrame) -> pd.DataFrame:
    rows: list[dict] = []
    thresholds = (20, 40, 80, 120, 160)
    for group in GROUP_ORDER:
        mask = group_masks(frame)[group]
        vals = frame.loc[mask, "K_req_kg"].to_numpy(dtype=float)
        row = {"policy": frame["policy"].iloc[0], "group": group, "n_paths": len(vals)}
        if len(vals):
            for quantile, label in ((0.50, "median"), (0.75, "q75"), (0.90, "q90"),
                                    (0.95, "q95"), (0.99, "q99")):
                row[label + "_kg"] = float(np.quantile(vals, quantile))
            row["mean_kg"] = float(vals.mean())
            row["max_kg"] = float(vals.max())
            for threshold in thresholds:
                count = int(np.sum(vals > threshold + TOL))
                row[f"count_gt{threshold}_kg"] = count
                row[f"rate_gt{threshold}_kg"] = float(count / len(vals))
            row["count_le160_kg"] = int(np.sum(vals <= 160.0 + TOL))
            row["coverage160_rate"] = float(np.mean(vals <= 160.0 + TOL))
        else:
            for label in ("median", "q75", "q90", "q95", "q99", "mean", "max"):
                row[label + "_kg"] = np.nan
            for threshold in thresholds:
                row[f"count_gt{threshold}_kg"] = 0
                row[f"rate_gt{threshold}_kg"] = np.nan
            row["count_le160_kg"] = 0
            row["coverage160_rate"] = np.nan
        rows.append(row)
    return pd.DataFrame(rows)


def saturation(frame: pd.DataFrame) -> pd.DataFrame:
    rows: list[dict] = []
    masks = group_masks(frame)
    policy = frame["policy"].iloc[0]
    for group in GROUP_ORDER:
        subset = frame.loc[masks[group]]
        previous_rebalanced = None
        previous_remaining_penalty = None
        for label, capacity in CAPACITIES:
            k = subset["K_req_kg"].to_numpy(dtype=float)
            d = subset["D_site_kg"].to_numpy(dtype=float)
            rebalanced = k if np.isinf(capacity) else np.minimum(k, capacity)
            remaining_gap = d - rebalanced
            remaining_penalty = PENALTY_YUAN_PER_KG * remaining_gap
            binding = np.zeros(len(k), dtype=bool) if np.isinf(capacity) else k > capacity + TOL
            if previous_rebalanced is None:
                marginal_rebalanced = np.nan
                marginal_penalty_reduction = np.nan
            else:
                marginal_rebalanced = float(np.mean(rebalanced - previous_rebalanced))
                marginal_penalty_reduction = float(np.mean(previous_remaining_penalty - remaining_penalty))
            rows.append({
                "policy": policy,
                "group": group,
                "capacity_label": label,
                "capacity_kg": np.nan if np.isinf(capacity) else capacity,
                "n_paths": len(k),
                "mean_k_req_kg": float(np.mean(k)) if len(k) else np.nan,
                "mean_rebalanced_kg": float(np.mean(rebalanced)) if len(k) else np.nan,
                "mean_remaining_site_gap_kg": float(np.mean(remaining_gap)) if len(k) else np.nan,
                "mean_remaining_terminal_penalty_yuan": float(np.mean(remaining_penalty)) if len(k) else np.nan,
                "total_remaining_terminal_penalty_yuan": float(np.sum(remaining_penalty)) if len(k) else np.nan,
                "capacity_binding_path_count": int(binding.sum()),
                "capacity_binding_rate": float(binding.mean()) if len(k) else np.nan,
                "additional_rebalanced_vs_previous_kg_per_path": marginal_rebalanced,
                "additional_penalty_reduction_vs_previous_yuan_per_path": marginal_penalty_reduction,
                "remaining_site_gap_q95_kg": float(np.quantile(remaining_gap, 0.95)) if len(k) else np.nan,
            })
            previous_rebalanced = rebalanced
            previous_remaining_penalty = remaining_penalty
    return pd.DataFrame(rows)


def base_b0001_comparison(base: pd.DataFrame, b0001: pd.DataFrame) -> pd.DataFrame:
    rows: list[dict] = []
    metric_specs = [
        ("mean_K_req_kg", lambda v: float(np.mean(v))),
        ("q95_K_req_kg", lambda v: float(np.quantile(v, 0.95))),
        ("q99_K_req_kg", lambda v: float(np.quantile(v, 0.99))),
        ("max_K_req_kg", lambda v: float(np.max(v))),
        ("count_K_req_gt80_kg", lambda v: int(np.sum(v > 80.0 + TOL))),
        ("count_K_req_gt160_kg", lambda v: int(np.sum(v > 160.0 + TOL))),
        ("coverage_K_req_le160_rate", lambda v: float(np.mean(v <= 160.0 + TOL))),
    ]
    for group in GROUP_ORDER:
        bvals = base.loc[group_masks(base)[group], "K_req_kg"].to_numpy(dtype=float)
        cvals = b0001.loc[group_masks(b0001)[group], "K_req_kg"].to_numpy(dtype=float)
        for metric, function in metric_specs:
            b_value = function(bvals) if len(bvals) else np.nan
            c_value = function(cvals) if len(cvals) else np.nan
            rows.append({
                "group": group, "metric": metric,
                "base": b_value, "b0001": c_value,
                "delta_b0001_minus_base": c_value - b_value if np.isfinite(b_value) and np.isfinite(c_value) else np.nan,
                "base_n": len(bvals), "b0001_n": len(cvals),
            })
    return pd.DataFrame(rows)


def save_csv(frame: pd.DataFrame, path: Path) -> None:
    frame.to_csv(path, index=False, encoding="utf-8", float_format="%.12g")


def summary_markdown(base: pd.DataFrame, b0001: pd.DataFrame, comparison: pd.DataFrame,
                     saturation_frame: pd.DataFrame, output_dir: Path, source_paths: dict[str, Path]) -> str:
    def stat(frame: pd.DataFrame, group: str, col: str) -> float:
        row = frame[(frame.policy == frame.policy.iloc[0]) & frame.group.eq(group)].iloc[0]
        return float(row[col])

    base_dist = distribution(base)
    b_dist = distribution(b0001)
    base_all = base_dist[base_dist.group.eq("all")].iloc[0]
    b_all = b_dist[b_dist.group.eq("all")].iloc[0]
    pure_base = base_dist[base_dist.group.eq("PURE_LOCATION")].iloc[0]
    pure_b = b_dist[b_dist.group.eq("PURE_LOCATION")].iloc[0]
    mixed_base = base_dist[base_dist.group.eq("MIXED")].iloc[0]
    mixed_b = b_dist[b_dist.group.eq("MIXED")].iloc[0]
    difficult_base = base_dist[base_dist.group.eq("difficult4")].iloc[0]
    difficult_b = b_dist[b_dist.group.eq("difficult4")].iloc[0]
    extreme_base = base_dist[base_dist.group.eq("extreme1")].iloc[0]
    extreme_b = b_dist[b_dist.group.eq("extreme1")].iloc[0]
    coverage_min = min(float(base_all.coverage160_rate), float(b_all.coverage160_rate))
    max_k = max(float(base_all.max_kg), float(b_all.max_kg))
    if max_k <= 160.0 + TOL:
        sufficiency = "STRONG"
        saturation_label = "YES"
    elif coverage_min >= 0.99:
        sufficiency = "MODERATE"
        saturation_label = "MIXED"
    elif coverage_min >= 0.95:
        sufficiency = "WEAK"
        saturation_label = "NO"
    else:
        sufficiency = "INSUFFICIENT"
        saturation_label = "NO"
    freeze = "YES" if sufficiency == "STRONG" else ("NEEDS_MORE_EVIDENCE" if sufficiency == "MODERATE" else "NO")

    sat_all = saturation_frame[saturation_frame.group.eq("all")]
    sat_lines = []
    for policy in ("Base", "B0001"):
        p = sat_all[sat_all.policy.eq(policy)].set_index("capacity_label")
        sat_lines.append(
            f"- {policy}: 40->80 每路径新增消除 {p.loc['80', 'additional_rebalanced_vs_previous_kg_per_path']:.4f} kg，"
            f"80->160 为 {p.loc['160', 'additional_rebalanced_vs_previous_kg_per_path']:.4f} kg，"
            f"160->∞ 为 {p.loc['inf', 'additional_rebalanced_vs_previous_kg_per_path']:.4f} kg；"
            f"160 kg 后剩余 site gap 均值 {p.loc['160', 'mean_remaining_site_gap_kg']:.4f} kg。"
        )
    gt = pd.concat([base.loc[base.K_req_kg > 160 + TOL], b0001.loc[b0001.K_req_kg > 160 + TOL]])
    delta_mean = float(b_all.mean_kg - base_all.mean_kg)
    delta_q99 = float(b_all.q99_kg - base_all.q99_kg)
    delta_max = float(b_all.max_kg - base_all.max_kg)
    increase_text = "增加" if (delta_mean > TOL or delta_q99 > TOL or delta_max > TOL) else "未增加"
    pure_cov = f"Base={pure_base.coverage160_rate:.3%}; B0001={pure_b.coverage160_rate:.3%}"
    mixed_cov = f"Base={mixed_base.coverage160_rate:.3%}; B0001={mixed_b.coverage160_rate:.3%}"
    return f"""# Stage-90A2 Terminal Redistribution Capacity Sufficiency Audit

## 审计边界

本审计只读复用已保存的 Base penalty=1000 和 exploratory B0001 共样本 OOS path summary。两者均为 10000 条有序路径，共用 bank SHA-256；terminal target 与 path identity 门禁已通过。未训练、未重跑 OOS、未调用 MATLAB/Gurobi、未修改 Stage7 正式模型。

`K_req` 的物理含义是：在 TerminalLOH 已完全揭示、只允许一次四站 direct redistribution、且不新增制氢的假设下，为消除逐站空间错配所需的理论最小 H2 调拨量。它等于 `D_site-Q_total`，并机械验证等于 `min(D_site,S_site)`；它不是正式 Stage7 LP 的实际流量、运输成本或非预见性策略结果。

尾部 cohort 严格复用既有定义：`reached_stage7=1` 的 Base 路径按 `terminal_site_gap` 降序、`path_id` 升序排序，前 62 条为 `extreme1`，接续 245 条为 `difficult4`；B0001 使用相同 path_id。

## 分布结果

| cohort | Base mean | Base q95 | Base q99 | Base max | B0001 mean | B0001 q95 | B0001 q99 | B0001 max |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| all 10000 | {base_all.mean_kg:.4f} | {base_all.q95_kg:.4f} | {base_all.q99_kg:.4f} | {base_all.max_kg:.4f} | {b_all.mean_kg:.4f} | {b_all.q95_kg:.4f} | {b_all.q99_kg:.4f} | {b_all.max_kg:.4f} |
| PURE_LOCATION | {pure_base.mean_kg:.4f} | {pure_base.q95_kg:.4f} | {pure_base.q99_kg:.4f} | {pure_base.max_kg:.4f} | {pure_b.mean_kg:.4f} | {pure_b.q95_kg:.4f} | {pure_b.q99_kg:.4f} | {pure_b.max_kg:.4f} |
| MIXED | {mixed_base.mean_kg:.4f} | {mixed_base.q95_kg:.4f} | {mixed_base.q99_kg:.4f} | {mixed_base.max_kg:.4f} | {mixed_b.mean_kg:.4f} | {mixed_b.q95_kg:.4f} | {mixed_b.q99_kg:.4f} | {mixed_b.max_kg:.4f} |

`K_req > 80 kg`：Base {int(base_all.count_gt80_kg)} ({base_all.rate_gt80_kg:.3%})，B0001 {int(b_all.count_gt80_kg)} ({b_all.rate_gt80_kg:.3%})。`K_req > 160 kg`：Base {int(base_all.count_gt160_kg)} ({base_all.rate_gt160_kg:.3%})，B0001 {int(b_all.count_gt160_kg)} ({b_all.rate_gt160_kg:.3%})。

Base 与 B0001 的 mean/q99/max 变化分别为 `{delta_mean:+.4f}` / `{delta_q99:+.4f}` / `{delta_max:+.4f}` kg；按这些总体尾部指标，B0001 对 terminal redistribution requirement **{increase_text}**，但这是 exploratory checkpoint 的容量压力信号，不是正式策略优劣结论。

## 160 kg 覆盖

- `CAPACITY_160_COVERAGE_RATE`：Base {base_all.coverage160_rate:.3%}；B0001 {b_all.coverage160_rate:.3%}。
- `PURE_LOCATION` 覆盖：{pure_cov}。
- `MIXED` 空间部分覆盖：{mixed_cov}。
- difficult4 >160：Base {int(difficult_base.count_gt160_kg)}，B0001 {int(difficult_b.count_gt160_kg)}；extreme1 >160：Base {int(extreme_base.count_gt160_kg)}，B0001 {int(extreme_b.count_gt160_kg)}。
- `K_req` 最大值（两策略合并）：{max_k:.4f} kg。

存在 `K_req >160` 的路径数为 {len(gt)}；详情见 `capacity_gt160_paths.csv`。若该数为零，则只能表述为当前 frozen scenario bank 的覆盖结论，不能外推为永久或普遍充分。

## 容量饱和

解析截断使用 `rebalanced=min(K_req,capacity)`，剩余 site gap 为 `D_site-rebalanced`，剩余 terminal penalty 为 `1000*remaining_site_gap`；没有调用正式 Stage7 LP。

{chr(10).join(sat_lines)}

160 kg 后是否进入收益饱和区，按“所有路径均已覆盖”判定为 `{saturation_label}`。具体每个 cohort、容量档位的剩余 gap、penalty 和 binding count 见 `terminal_capacity_saturation_40_80_160_inf.csv`。

## 最终标签

```text
K160_SUFFICIENCY = {sufficiency}
K160_ALL_PATH_COVERAGE = {"YES" if max_k <= 160 + TOL else "NO"}
K160_PURE_LOCATION_COVERAGE = {pure_cov}
K160_MIXED_SPATIAL_COVERAGE = {mixed_cov}
CAPACITY_SATURATION_BY_160 = {saturation_label}
RECOMMEND_FREEZE_K_TERMINAL_160 = {freeze}
```

`STRONG/MODERATE/WEAK/INSUFFICIENT` 的审计规则已固定在本摘要对应结果：两策略所有路径均不超过 160 kg 才为 STRONG；最低覆盖率至少 99% 但仍有少数超额路径为 MODERATE；至少 95% 为 WEAK；否则 INSUFFICIENT。以上只支持容量候选的证据分级，不构成 Stage90 adoption 或正式模型变更。

## 可复核来源

- Base path summary: `{source_paths['Base']}`
- B0001 path summary: `{source_paths['B0001']}`
- 输出目录：`{output_dir}`
"""


def main() -> int:
    checks: list[dict] = []
    base_frame, base_meta = read_source("Base", BASE, checks)
    b0001_frame, b0001_meta = read_source("B0001", B0001, checks)
    verify_identity(base_frame, b0001_frame, base_meta, b0001_meta, checks)
    difficult_ids, extreme_ids = tail_ids(base_frame)
    add_check(checks, "tail_cohort_counts", len(difficult_ids) == 245 and len(extreme_ids) == 62,
             f"difficult4={len(difficult_ids)}; extreme1={len(extreme_ids)}", "Base")

    base_calc = calculate("Base", base_frame, difficult_ids, extreme_ids, checks)
    b0001_calc = calculate("B0001", b0001_frame, difficult_ids, extreme_ids, checks)
    pathwise = pd.concat([base_calc, b0001_calc], ignore_index=True)
    dist = pd.concat([distribution(base_calc), distribution(b0001_calc)], ignore_index=True)
    sat = pd.concat([saturation(base_calc), saturation(b0001_calc)], ignore_index=True)
    comparison = base_b0001_comparison(base_calc, b0001_calc)
    gt160 = pathwise.loc[pathwise["K_req_kg"] > 160.0 + TOL, [
        "policy", "path_id", *TARGET_COLS, *INVENTORY_COLS, "target_total", "terminal_inventory_total",
        "D_site_kg", "S_site_kg", "Q_total_kg", "K_req_kg", "failure_type", "terminal_gap_class",
        "tail_group", "terminal_state_id", "terminal_a", "terminal_loc", "termination_stage", "termination_type",
    ]].copy()
    add_check(checks, "saturation_monotone_rebalanced", bool((sat.groupby(["policy", "group"])["mean_rebalanced_kg"].diff().dropna() >= -TOL).all()),
             "mean rebalanced is nondecreasing across 40/80/160/inf", "derived")
    add_check(checks, "saturation_inf_binding_zero", bool((sat.loc[sat.capacity_label.eq("inf"), "capacity_binding_path_count"] == 0).all()),
             "infinity binding count is zero", "derived")
    penalty_error = np.max(np.abs(sat["mean_remaining_terminal_penalty_yuan"] - PENALTY_YUAN_PER_KG * sat["mean_remaining_site_gap_kg"]))
    add_check(checks, "saturation_penalty_formula", penalty_error <= 1e-7,
             f"max_abs_error={penalty_error:.6g}", "derived")

    run_index = 1
    while (RESULT_ROOT / f"run-{run_index:03d}").exists():
        run_index += 1
    output_dir = RESULT_ROOT / f"run-{run_index:03d}"
    output_dir.mkdir(parents=True, exist_ok=False)
    save_csv(pathwise, output_dir / "terminal_capacity_requirement_pathwise.csv")
    save_csv(dist, output_dir / "terminal_capacity_distribution.csv")
    save_csv(sat, output_dir / "terminal_capacity_saturation_40_80_160_inf.csv")
    save_csv(comparison, output_dir / "base_vs_b0001_terminal_capacity.csv")
    save_csv(gt160, output_dir / "capacity_gt160_paths.csv")
    summary_path = output_dir / "中文容量审计摘要.md"
    summary_path.write_text(summary_markdown(base_calc, b0001_calc, comparison, sat, output_dir, {
        "Base": BASE / "path_summary/oos_path_summary.csv",
        "B0001": B0001 / "path_summary/oos_path_summary.csv",
    }), encoding="utf-8")

    add_check(checks, "pathwise_output_rows", len(pathwise) == 20000, f"rows={len(pathwise)}", "outputs")
    add_check(checks, "distribution_output_rows", len(dist) == 16, f"rows={len(dist)}", "outputs")
    add_check(checks, "saturation_output_rows", len(sat) == 64, f"rows={len(sat)}", "outputs")
    add_check(checks, "comparison_output_rows", len(comparison) == 56, f"rows={len(comparison)}", "outputs")
    add_check(checks, "gt160_output_rows", len(gt160) == int((pathwise.K_req_kg > 160 + TOL).sum()),
             f"rows={len(gt160)}", "outputs")
    add_check(checks, "read_only_scope", True,
             "analytical pandas audit only; no MATLAB/Gurobi/formal Stage7 LP/training/OOS rerun", "scope")
    qa = pd.DataFrame(checks)
    save_csv(qa, output_dir / "qa_summary.csv")
    if not (qa["status"] == "PASS").all():
        raise RuntimeError("Stage-90A2 QA failed:\n" + qa.loc[qa.status != "PASS"].to_string(index=False))
    manifest = []
    for path in sorted(output_dir.iterdir()):
        if path.is_file():
            manifest.append({"file": path.name, "bytes": path.stat().st_size, "sha256": sha256_file(path)})
    pd.DataFrame(manifest).to_csv(output_dir / "audit_manifest.csv", index=False, encoding="utf-8")
    print(json.dumps({
        "run_dir": str(output_dir),
        "qa_pass": int((qa.status == "PASS").sum()),
        "qa_total": len(qa),
        "gt160_rows": len(gt160),
        "base_max_K_req_kg": float(base_calc.K_req_kg.max()),
        "b0001_max_K_req_kg": float(b0001_calc.K_req_kg.max()),
        "base_coverage160": float((base_calc.K_req_kg <= 160 + TOL).mean()),
        "b0001_coverage160": float((b0001_calc.K_req_kg <= 160 + TOL).mean()),
    }, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
