from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import pandas as pd


TOL = 1e-9
SITE_COUNT = 4
PRIMARY_GROUPS = [
    "PHYSICAL_DISSIPATION",
    "OTHER_ABSORPTION",
    "TRUE_STAGE7_ZERO_TARGET",
    "TRUE_STAGE7_POSITIVE_TARGET",
]
CLASSES = ["ADEQUATE", "PURE_QUANTITY", "PURE_LOCATION", "MIXED"]


PACKAGE = Path(
    r"C:\Users\chaos\Desktop\biye\test\testH2_v2\results\task-002-stage2b-b3-smoke"
    r"\Temporal3p5_DRO_TerminalLOH_BaseMSP5h"
)
RUN = PACKAGE / "training/runs/run-20260901-020054"
DEFAULT_MANIFEST = RUN / "oos_analysis/source_manifest.csv"
DEFAULT_OUTPUT = RUN / "mode_c_deep_dive"
STATE_TABLE = Path(
    r"C:\Users\chaos\Desktop\biye\test\testH2_v2\terminalLoh_wdro"
    r"\partial_temporal_refinement\dro_3p5h\run-001\current_vs_new_dro_by_state.csv"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def terminal_components(frame: pd.DataFrame) -> pd.DataFrame:
    target = frame[[f"target_site{i}" for i in range(1, SITE_COUNT + 1)]].to_numpy(float)
    inventory = frame[[f"inventory_site{i}" for i in range(1, SITE_COUNT + 1)]].to_numpy(float)
    site_gap = np.maximum(target - inventory, 0.0).sum(axis=1)
    quantity_gap = np.maximum(target.sum(axis=1) - inventory.sum(axis=1), 0.0)
    spatial_gap = site_gap - quantity_gap
    useful = np.minimum(np.maximum(inventory, 0.0), target).sum(axis=1)
    target_total = target.sum(axis=1)
    service_rate = np.divide(useful, target_total, out=np.ones_like(useful), where=target_total > TOL)
    classification = np.select(
        [
            (quantity_gap <= TOL) & (spatial_gap <= TOL),
            (quantity_gap > TOL) & (spatial_gap <= TOL),
            (quantity_gap <= TOL) & (spatial_gap > TOL),
            (quantity_gap > TOL) & (spatial_gap > TOL),
        ],
        CLASSES,
        default="NOT_IDENTIFIABLE",
    )
    return pd.DataFrame(
        {
            "path_id": frame.path_id.to_numpy(int),
            "target_total_calc": target_total,
            "site_gap_calc": site_gap,
            "quantity_gap_calc": quantity_gap,
            "spatial_gap_calc": spatial_gap,
            "useful_terminal_kg": useful,
            "path_service_rate": np.clip(service_rate, 0.0, 1.0),
            "classification": classification,
        }
    )


def load_manifest(path: Path) -> dict[str, Path]:
    frame = pd.read_csv(path)
    result = {row.role: Path(row.path) for row in frame.itertuples()}
    required = {
        "base_path", "candidate_path", "base_stage", "candidate_stage",
        "base_site", "candidate_site", "base_hour_site", "candidate_hour_site",
    }
    require(required.issubset(result), f"manifest missing roles: {sorted(required - set(result))}")
    for role in required:
        require(result[role].is_file(), f"missing source {role}: {result[role]}")
    return result


def load_path(path: Path) -> pd.DataFrame:
    frame = pd.read_csv(path)
    require(len(frame) == 10000, f"expected 10000 paths in {path}")
    require(frame.path_id.tolist() == list(range(1, 10001)), f"ordered path identity failed: {path}")
    require(frame.path_id.is_unique, f"duplicate path_id: {path}")
    calc = terminal_components(frame)
    for column in calc.columns[1:]:
        frame[column] = calc[column].to_numpy()
    frame["terminal_initial_state"] = np.where(
        frame.termination_type.eq("STAGE7_TERMINAL_CHECK"),
        (pd.to_numeric(frame.terminal_a) - 2) * 7 + pd.to_numeric(frame.terminal_loc),
        np.nan,
    )
    return frame


def assign_groups(base: pd.DataFrame, candidate: pd.DataFrame) -> pd.Series:
    require(base.termination_type.equals(candidate.termination_type), "termination type differs by arm")
    base_positive = base.target_total_calc > TOL
    candidate_positive = candidate.target_total_calc > TOL
    require(base_positive.equals(candidate_positive), "positive-target membership differs by arm")
    group = pd.Series(index=base.index, dtype="object")
    group[base.termination_type.eq("PHYSICAL_DISSIPATION_A1")] = "PHYSICAL_DISSIPATION"
    group[base.termination_type.eq("LF8_ABSORBING")] = "OTHER_ABSORPTION"
    stage7 = base.termination_type.eq("STAGE7_TERMINAL_CHECK")
    group[stage7 & ~base_positive] = "TRUE_STAGE7_ZERO_TARGET"
    group[stage7 & base_positive] = "TRUE_STAGE7_POSITIVE_TARGET"
    require(group.notna().all(), "unclassified path group")
    expected = {
        "PHYSICAL_DISSIPATION": 3497,
        "OTHER_ABSORPTION": 379,
        "TRUE_STAGE7_ZERO_TARGET": 5001,
        "TRUE_STAGE7_POSITIVE_TARGET": 1123,
    }
    require(group.value_counts().to_dict() == expected, f"group count mismatch: {group.value_counts().to_dict()}")
    return group


def load_site_totals(path: Path) -> tuple[pd.DataFrame, pd.DataFrame]:
    usecols = [
        "path_id", "stage", "site", "ordinary_demand_kg", "served_demand_kg",
        "shortage_kg", "htt_in_kg", "htt_out_kg", "ending_inventory_kg",
    ]
    frame = pd.read_csv(path, usecols=usecols)
    numeric_cols = [c for c in usecols if c not in {"path_id", "stage", "site"}]
    totals = frame.groupby("path_id", as_index=False)[numeric_cols[:-1]].sum()
    site_htt = frame.groupby(["path_id", "site"], as_index=False)[["htt_in_kg", "htt_out_kg"]].sum()
    return totals, site_htt


def load_hour(path: Path) -> tuple[pd.DataFrame, pd.DataFrame]:
    usecols = [
        "path_id", "global_hour", "H2_production_kg", "P_EL_kW",
        "ordinary_shortage_kg", "end_inventory_kg",
    ]
    frame = pd.read_csv(path, usecols=usecols)
    hourly = frame.groupby(["path_id", "global_hour"], as_index=False)[
        ["H2_production_kg", "P_EL_kW", "ordinary_shortage_kg", "end_inventory_kg"]
    ].sum()
    # Serialized hours are one-hour intervals, so sum(P_EL_kW * 1 h) is kWh.
    energy = hourly.groupby("path_id", as_index=False).agg(total_EL_energy_kWh=("P_EL_kW", "sum"))
    return hourly, energy


def distribution(series: pd.Series, prefix: str) -> dict[str, float]:
    return {
        f"{prefix}_mean": float(series.mean()),
        f"{prefix}_median": float(series.median()),
        f"{prefix}_q05": float(series.quantile(0.05)),
        f"{prefix}_q25": float(series.quantile(0.25)),
        f"{prefix}_q75": float(series.quantile(0.75)),
        f"{prefix}_q95": float(series.quantile(0.95)),
    }


def group_masks(groups: pd.Series) -> list[tuple[str, pd.Series]]:
    return [
        *[(name, groups.eq(name)) for name in PRIMARY_GROUPS],
        ("ALL_ZERO_TARGET_8877", ~groups.eq("TRUE_STAGE7_POSITIVE_TARGET")),
        ("ALL_PATH_10000", pd.Series(True, index=groups.index)),
    ]


def group_production_summary(paired: pd.DataFrame, groups: pd.Series) -> pd.DataFrame:
    rows: list[dict[str, object]] = []
    for name, mask in group_masks(groups):
        subset = paired.loc[mask].copy()
        base_prod = subset.total_H2_production_BASE
        candidate_prod = subset.total_H2_production_CANDIDATE
        delta = candidate_prod - base_prod
        row: dict[str, object] = {
            "group": name,
            "path_count": len(subset),
            "group_weight": len(subset) / 10000.0,
            **distribution(base_prod, "base_total_H2_production_kg_per_path"),
            **distribution(candidate_prod, "candidate_total_H2_production_kg_per_path"),
            "paired_mean_delta_kg_per_path": float(delta.mean()),
            "paired_median_delta_kg_per_path": float(delta.median()),
            "paired_q05_delta_kg_per_path": float(delta.quantile(0.05)),
            "paired_q95_delta_kg_per_path": float(delta.quantile(0.95)),
            "production_increase_count": int((delta > TOL).sum()),
            "production_decrease_count": int((delta < -TOL).sum()),
            "production_equal_count": int((delta.abs() <= TOL).sum()),
            "group_contribution_to_all_path_mean_delta_kg": float(len(subset) / 10000.0 * delta.mean()),
        }
        row["production_delta_pct"] = float(delta.mean() / base_prod.mean() * 100.0) if abs(base_prod.mean()) > TOL else np.nan
        for metric in [
            "total_EL_energy_kWh", "ordinary_demand_kg", "served_demand_kg", "shortage_kg",
            "terminal_inventory_total", "total_HTT",
        ]:
            base_col = f"{metric}_BASE"
            candidate_col = f"{metric}_CANDIDATE"
            row[f"base_mean_{metric}"] = float(subset[base_col].mean())
            row[f"candidate_mean_{metric}"] = float(subset[candidate_col].mean())
            row[f"paired_mean_delta_{metric}"] = float((subset[candidate_col] - subset[base_col]).mean())
        rows.append(row)
    result = pd.DataFrame(rows)
    primary = result[result.group.isin(PRIMARY_GROUPS)]
    full_delta = float(result.loc[result.group.eq("ALL_PATH_10000"), "paired_mean_delta_kg_per_path"].iloc[0])
    require(abs(primary.group_contribution_to_all_path_mean_delta_kg.sum() - full_delta) <= 1e-9, "contribution decomposition failed")
    return result


def stage_profile(path: Path, label: str, group_lookup: pd.Series) -> pd.DataFrame:
    usecols = ["path_id", "stage", "production_kg", "ordinary_shortage_kg", "ending_inventory_kg"]
    frame = pd.read_csv(path, usecols=usecols)
    frame["group"] = frame.path_id.map(group_lookup)
    out = frame.groupby(["group", "stage"], as_index=False).agg(
        active_path_count=("path_id", "nunique"),
        mean_H2_production_kg=("production_kg", "mean"),
        mean_ending_inventory_kg=("ending_inventory_kg", "mean"),
        mean_ordinary_shortage_kg=("ordinary_shortage_kg", "mean"),
    )
    full_index = pd.MultiIndex.from_product([PRIMARY_GROUPS, range(1, 7)], names=["group", "stage"])
    out = out.set_index(["group", "stage"]).reindex(full_index).reset_index()
    out["active_path_count"] = out.active_path_count.fillna(0).astype(int)
    out["arm"] = label
    return out


def combine_profiles(base: pd.DataFrame, candidate: pd.DataFrame, key: str) -> pd.DataFrame:
    b = base.drop(columns="arm").rename(columns={c: f"base_{c}" for c in base.columns if c not in {"group", key}})
    c = candidate.drop(columns="arm").rename(columns={c: f"candidate_{c}" for c in candidate.columns if c not in {"group", key}})
    out = b.merge(c, on=["group", key], how="outer", validate="one_to_one")
    for column in [c for c in b.columns if c.startswith("base_mean_")]:
        metric = column.removeprefix("base_")
        out[f"delta_{metric}"] = out[f"candidate_{metric}"] - out[column]
    return out.sort_values(["group", key])


def hourly_profile(hourly: pd.DataFrame, label: str, group_lookup: pd.Series) -> pd.DataFrame:
    frame = hourly.copy()
    frame["group"] = frame.path_id.map(group_lookup)
    out = frame.groupby(["group", "global_hour"], as_index=False).agg(
        active_path_count=("path_id", "nunique"),
        mean_P_EL_kW=("P_EL_kW", "mean"),
        mean_H2_production_kg=("H2_production_kg", "mean"),
        mean_ending_inventory_kg=("end_inventory_kg", "mean"),
        mean_ordinary_shortage_kg=("ordinary_shortage_kg", "mean"),
    )
    full_index = pd.MultiIndex.from_product([PRIMARY_GROUPS, range(1, 49)], names=["group", "global_hour"])
    out = out.set_index(["group", "global_hour"]).reindex(full_index).reset_index()
    out["active_path_count"] = out.active_path_count.fillna(0).astype(int)
    out["arm"] = label
    return out


def transition_matrix(paired: pd.DataFrame, positive: pd.Series) -> pd.DataFrame:
    subset = paired.loc[positive]
    rows = []
    for base_class in CLASSES:
        row_total = int(subset.classification_BASE.eq(base_class).sum())
        for candidate_class in CLASSES:
            count = int((subset.classification_BASE.eq(base_class) & subset.classification_CANDIDATE.eq(candidate_class)).sum())
            rows.append(
                {
                    "base_classification": base_class,
                    "candidate_classification": candidate_class,
                    "path_count": count,
                    "rate_of_positive_1123": count / len(subset),
                    "row_transition_rate": count / row_total if row_total else np.nan,
                }
            )
    result = pd.DataFrame(rows)
    require(result.path_count.sum() == 1123, "transition matrix total failed")
    return result


def add_site_htt(frame: pd.DataFrame, totals: pd.DataFrame, suffix: str) -> pd.DataFrame:
    wide = totals.pivot(index="path_id", columns="site", values=["htt_in_kg", "htt_out_kg"])
    wide.columns = [f"{metric}_site{int(site)}_{suffix}" for metric, site in wide.columns]
    return frame.merge(wide.reset_index(), on="path_id", how="left", validate="one_to_one")


def flipped_paths(paired: pd.DataFrame, positive: pd.Series, base_htt: pd.DataFrame, candidate_htt: pd.DataFrame) -> pd.DataFrame:
    failure_b = ~paired.classification_BASE.eq("ADEQUATE")
    failure_c = ~paired.classification_CANDIDATE.eq("ADEQUATE")
    recovered = positive & failure_b & ~failure_c
    new_failure = positive & ~failure_b & failure_c
    require(int(recovered.sum()) == 70 and int(new_failure.sum()) == 43, "113-path flip identity failed")
    subset = paired.loc[recovered | new_failure].copy()
    subset["migration"] = np.where(recovered[recovered | new_failure], "RECOVERED", "NEW_FAILURE")
    subset = add_site_htt(subset, base_htt, "BASE")
    subset = add_site_htt(subset, candidate_htt, "CANDIDATE")
    subset["road_accessibility_terminal_indicator"] = "NOT_AVAILABLE_IN_MODE_C_RAW_SCHEMA"
    preferred = [
        "path_id", "migration", "terminal_initial_state_BASE", "terminal_state_id_BASE",
        "terminal_a_BASE", "terminal_loc_BASE", "classification_BASE", "classification_CANDIDATE",
    ]
    for arm in ["BASE", "CANDIDATE"]:
        preferred += [f"target_site{i}_{arm}" for i in range(1, 5)] + [f"target_total_{arm}"]
    preferred += [f"target_site{i}_delta" for i in range(1, 5)] + ["target_total_delta"]
    for arm in ["BASE", "CANDIDATE"]:
        preferred += [f"inventory_site{i}_{arm}" for i in range(1, 5)]
    for arm in ["BASE", "CANDIDATE"]:
        preferred += [f"gap_site{i}_{arm}" for i in range(1, 5)] + [f"site_gap_calc_{arm}"]
    preferred += [
        "total_H2_production_BASE", "total_H2_production_CANDIDATE",
        "total_HTT_BASE", "total_HTT_CANDIDATE",
    ]
    for arm in ["BASE", "CANDIDATE"]:
        preferred += [f"htt_in_kg_site{i}_{arm}" for i in range(1, 5)]
        preferred += [f"htt_out_kg_site{i}_{arm}" for i in range(1, 5)]
    preferred += ["road_accessibility_terminal_indicator"]
    return subset[[c for c in preferred if c in subset.columns]].sort_values(["migration", "path_id"])


def persistent_summary(paired: pd.DataFrame, positive: pd.Series) -> pd.DataFrame:
    persistent = positive & ~paired.classification_BASE.eq("ADEQUATE") & ~paired.classification_CANDIDATE.eq("ADEQUATE")
    require(int(persistent.sum()) == 403, "persistent failure count failed")
    rows = []
    for name, mask in [
        ("ALL_PERSISTENT_FAILURE", persistent),
        *[(f"CANDIDATE_{cls}", persistent & paired.classification_CANDIDATE.eq(cls)) for cls in CLASSES[1:]],
    ]:
        subset = paired.loc[mask]
        row: dict[str, object] = {"cohort": name, "path_count": len(subset)}
        for metric in [
            "site_gap_calc", "quantity_gap_calc", "spatial_gap_calc", "target_total_calc",
            "total_H2_production", "terminal_inventory_total", "path_service_rate",
        ]:
            b = subset[f"{metric}_BASE"]
            c = subset[f"{metric}_CANDIDATE"]
            row[f"base_mean_{metric}"] = float(b.mean())
            row[f"candidate_mean_{metric}"] = float(c.mean())
            row[f"paired_mean_delta_{metric}"] = float((c - b).mean())
        base_target = subset.target_total_calc_BASE.sum()
        candidate_target = subset.target_total_calc_CANDIDATE.sum()
        row["base_mass_weighted_service_rate"] = float(subset.useful_terminal_kg_BASE.sum() / base_target) if base_target > TOL else np.nan
        row["candidate_mass_weighted_service_rate"] = float(subset.useful_terminal_kg_CANDIDATE.sum() / candidate_target) if candidate_target > TOL else np.nan
        row["mass_weighted_service_delta_pp"] = 100.0 * (row["candidate_mass_weighted_service_rate"] - row["base_mass_weighted_service_rate"])
        rows.append(row)
    return pd.DataFrame(rows)


def cohort_masks(paired: pd.DataFrame, positive: pd.Series) -> list[tuple[str, pd.Series]]:
    failure_b = ~paired.classification_BASE.eq("ADEQUATE")
    failure_c = ~paired.classification_CANDIDATE.eq("ADEQUATE")
    return [
        ("ALL_POSITIVE_TARGET_1123", positive),
        ("RECOVERED_70", positive & failure_b & ~failure_c),
        ("NEW_FAILURE_43", positive & ~failure_b & failure_c),
        ("PERSISTENT_FAILURE_403", positive & failure_b & failure_c),
    ]


def site_analysis(paired: pd.DataFrame, positive: pd.Series) -> pd.DataFrame:
    rows = []
    for cohort, mask in cohort_masks(paired, positive):
        subset = paired.loc[mask]
        for site in range(1, 5):
            row: dict[str, object] = {"cohort": cohort, "site": site, "cohort_path_count": len(subset)}
            for arm in ["BASE", "CANDIDATE"]:
                target = subset[f"target_site{site}_{arm}"]
                inventory = subset[f"inventory_site{site}_{arm}"]
                gap = np.maximum(target - inventory, 0.0)
                useful = np.minimum(np.maximum(inventory, 0.0), target)
                site_positive = target > TOL
                prefix = arm.lower()
                row[f"{prefix}_target_positive_path_count"] = int(site_positive.sum())
                row[f"{prefix}_total_service_mass_kg"] = float(useful[site_positive].sum())
                row[f"{prefix}_capped_service_rate"] = float(useful[site_positive].sum() / target[site_positive].sum()) if site_positive.any() else np.nan
                row[f"{prefix}_mean_target_kg"] = float(target[site_positive].mean()) if site_positive.any() else np.nan
                row[f"{prefix}_mean_terminal_inventory_kg"] = float(inventory[site_positive].mean()) if site_positive.any() else np.nan
                row[f"{prefix}_mean_gap_kg"] = float(gap[site_positive].mean()) if site_positive.any() else np.nan
                row[f"{prefix}_failure_count"] = int((site_positive & (gap > TOL)).sum())
            row["capped_service_delta_pp"] = 100.0 * (row["candidate_capped_service_rate"] - row["base_capped_service_rate"])
            rows.append(row)
    return pd.DataFrame(rows)


def state_analysis(paired: pd.DataFrame, state_table: pd.DataFrame) -> pd.DataFrame:
    state_map = state_table[["state", "intensity", "loc"]].drop_duplicates()
    require(len(state_map) == 35, "DRO state map is not 35 states")
    stage7 = paired.termination_type_BASE.eq("STAGE7_TERMINAL_CHECK")
    rows = []
    for state_row in state_map.sort_values("state").itertuples():
        mask = stage7 & paired.terminal_initial_state_BASE.eq(state_row.state)
        subset = paired.loc[mask]
        positive = subset.target_total_calc_BASE > TOL
        row: dict[str, object] = {
            "state": int(state_row.state), "intensity": int(state_row.intensity), "loc": int(state_row.loc),
            "focus_state": int(state_row.state) in {9, 11, 17, 23, 29, 30, 31, 32, 33},
            "path_count": len(subset), "positive_target_count": int(positive.sum()),
            "base_mean_H2_production_kg": float(subset.total_H2_production_BASE.mean()) if len(subset) else np.nan,
            "candidate_mean_H2_production_kg": float(subset.total_H2_production_CANDIDATE.mean()) if len(subset) else np.nan,
        }
        row["paired_mean_production_delta_kg"] = row["candidate_mean_H2_production_kg"] - row["base_mean_H2_production_kg"]
        for arm in ["BASE", "CANDIDATE"]:
            for site in range(1, 5):
                site_positive = subset[f"target_site{site}_{arm}"] > TOL
                failure = subset[f"inventory_site{site}_{arm}"] < subset[f"target_site{site}_{arm}"] - TOL
                row[f"{arm.lower()}_site{site}_failure_count"] = int((site_positive & failure).sum())
                row[f"{arm.lower()}_site{site}_failure_rate"] = float(failure[site_positive].mean()) if site_positive.any() else np.nan
            for cls in CLASSES[1:]:
                row[f"{arm.lower()}_{cls.lower()}_count"] = int((positive & subset[f"classification_{arm}"].eq(cls)).sum())
            target_total = subset.loc[positive, f"target_total_calc_{arm}"].sum()
            useful_total = subset.loc[positive, f"useful_terminal_kg_{arm}"].sum()
            row[f"{arm.lower()}_mass_weighted_service_rate"] = float(useful_total / target_total) if target_total > TOL else np.nan
        row["mass_weighted_service_delta_pp"] = 100.0 * (row["candidate_mass_weighted_service_rate"] - row["base_mass_weighted_service_rate"])
        rows.append(row)
    result = pd.DataFrame(rows)
    require(result.path_count.sum() == 6124, "35-state Stage7 path total failed")
    require(result.positive_target_count.sum() == 1123, "35-state positive path total failed")
    return result


def fmt(value: float, digits: int = 6) -> str:
    return f"{value:.{digits}f}"


def write_summary(
    path: Path,
    group_summary: pd.DataFrame,
    transitions: pd.DataFrame,
    persistent: pd.DataFrame,
    paired: pd.DataFrame,
    groups: pd.Series,
) -> None:
    lookup = group_summary.set_index("group")
    production_lines = []
    for label in [
        "PHYSICAL_DISSIPATION", "OTHER_ABSORPTION", "TRUE_STAGE7_ZERO_TARGET",
        "ALL_ZERO_TARGET_8877", "TRUE_STAGE7_POSITIVE_TARGET", "ALL_PATH_10000",
    ]:
        row = lookup.loc[label]
        production_lines.append(
            f"- {label}: {fmt(row.base_total_H2_production_kg_per_path_mean)} -> "
            f"{fmt(row.candidate_total_H2_production_kg_per_path_mean)} kg/path; "
            f"delta {fmt(row.paired_mean_delta_kg_per_path)} ({fmt(row.production_delta_pct)}%)."
        )

    contributions = []
    for label in PRIMARY_GROUPS:
        row = lookup.loc[label]
        contributions.append(
            f"- {label}: weight {row.group_weight:.4%} x group delta "
            f"{fmt(row.paired_mean_delta_kg_per_path)} = "
            f"{fmt(row.group_contribution_to_all_path_mean_delta_kg)} kg/path."
        )

    positive = groups.eq("TRUE_STAGE7_POSITIVE_TARGET")
    failure_b = ~paired.classification_BASE.eq("ADEQUATE")
    failure_c = ~paired.classification_CANDIDATE.eq("ADEQUATE")
    recovered = positive & failure_b & ~failure_c
    new_failure = positive & ~failure_b & failure_c
    persistent_mask = positive & failure_b & failure_c

    recovered_counts = paired.loc[recovered, "classification_BASE"].value_counts()
    new_counts = paired.loc[new_failure, "classification_CANDIDATE"].value_counts()

    quantity_b = positive & (paired.quantity_gap_calc_BASE > TOL)
    quantity_c = positive & (paired.quantity_gap_calc_CANDIDATE > TOL)
    quantity_recovered = int((quantity_b & ~quantity_c).sum())
    quantity_new = int((~quantity_b & quantity_c).sum())
    spatial_b = positive & (paired.spatial_gap_calc_BASE > TOL)
    spatial_c = positive & (paired.spatial_gap_calc_CANDIDATE > TOL)
    spatial_recovered = int((spatial_b & ~spatial_c).sum())
    spatial_new = int((~spatial_b & spatial_c).sum())

    all_zero = lookup.loc["ALL_ZERO_TARGET_8877"]
    shortage_delta = all_zero.paired_mean_delta_shortage_kg
    shortage_statement = (
        "未恶化（paired mean delta <= 0）" if shortage_delta <= TOL else "上升"
    )

    persistent_all = persistent.set_index("cohort").loc["ALL_PERSISTENT_FAILURE"]
    gap_pct = 100.0 * persistent_all.paired_mean_delta_site_gap_calc / persistent_all.base_mean_site_gap_calc

    matrix = transitions.pivot(
        index="base_classification", columns="candidate_classification", values="path_count"
    ).reindex(index=CLASSES, columns=CLASSES).astype(int)
    matrix_lines = [
        "| Base \\ Candidate | " + " | ".join(CLASSES) + " |",
        "|---|" + "|".join(["---:"] * len(CLASSES)) + "|",
    ]
    for base_class in CLASSES:
        matrix_lines.append(
            f"| {base_class} | " + " | ".join(str(matrix.loc[base_class, candidate_class]) for candidate_class in CLASSES) + " |"
        )
    matrix_text = "\n".join(matrix_lines)

    text = f"""# Temporal3p5 Mode-C Deep-Dive 只读分析

## 范围与机械 QA

- 只读取已完成 Base/Candidate Mode-C raw CSV；未训练、未重跑 OOS、未修改 checkpoint/candidate/Base。
- 10000 条 ordered equal-weight path 均按 `path_id` 一对一配对。
- 固定分组计数：3497 / 379 / 5001 / 1123；合计 10000。
- `P_EL` 能量来自 raw hourly `P_EL_kW`，按已序列化的 1h 小时记录积分；不是模型外估算。
- road/accessibility terminal indicator 不在 Mode-C raw schema 中，113-path 文件明确标记 `NOT_AVAILABLE_IN_MODE_C_RAW_SCHEMA`。
- Stage/hour profile 使用 active-path denominator，并保留每格 active path count，不把已终止路径伪填为零。

## A-D. 分组制氢

{chr(10).join(production_lines)}

## E. 全路径制氢下降贡献分解

{chr(10).join(contributions)}

四项贡献合计 {fmt(sum(lookup.loc[g].group_contribution_to_all_path_mean_delta_kg for g in PRIMARY_GROUPS))} kg/path，
与全路径 paired mean delta {fmt(lookup.loc['ALL_PATH_10000'].paired_mean_delta_kg_per_path)} kg/path 一致。

## F. Zero-target ordinary shortage

ALL_ZERO_TARGET_8877 ordinary shortage 为
{fmt(all_zero.base_mean_shortage_kg)} -> {fmt(all_zero.candidate_mean_shortage_kg)} kg/path，
paired delta {fmt(shortage_delta)} kg/path，结论：{shortage_statement}。
因此，zero-target 路径上的较少制氢与“较少的 anticipatory terminal preparation”一致；这是配对描述性证据，不是独立反事实因果证明。

## G-H. 113 条身份翻转

- 70 recovered 的 Base 来源：PURE_QUANTITY={int(recovered_counts.get('PURE_QUANTITY', 0))}, PURE_LOCATION={int(recovered_counts.get('PURE_LOCATION', 0))}, MIXED={int(recovered_counts.get('MIXED', 0))}。主要来源为 {recovered_counts.idxmax()}。
- 43 new failures 的 Candidate 去向：PURE_QUANTITY={int(new_counts.get('PURE_QUANTITY', 0))}, PURE_LOCATION={int(new_counts.get('PURE_LOCATION', 0))}, MIXED={int(new_counts.get('MIXED', 0))}。主要去向为 {new_counts.idxmax()}。

完整 4x4 transition matrix：

{matrix_text}

## I. 403 条 persistent failures

403 条 persistent failures 的 mean terminal site gap 为
{fmt(persistent_all.base_mean_site_gap_calc)} -> {fmt(persistent_all.candidate_mean_site_gap_calc)} kg，
paired delta {fmt(persistent_all.paired_mean_delta_site_gap_calc)} kg ({fmt(gap_pct)}%)；
mass-weighted capped service rate 为
{persistent_all.base_mass_weighted_service_rate:.6%} -> {persistent_all.candidate_mass_weighted_service_rate:.6%}
({persistent_all.mass_weighted_service_delta_pp:+.6f} pp)。
这回答的是缺口严重度变化，不把未跨过 fully-adequate threshold 的路径误记为恢复。

## J. Quantity 与 spatial-related incidence

- Quantity failure: {int(quantity_b.sum())} -> {int(quantity_c.sum())}，净减 {int(quantity_c.sum()-quantity_b.sum())}；paired 内部是 {quantity_recovered} 条解除、{quantity_new} 条新增，因此净变化 = {quantity_new} - {quantity_recovered} = {quantity_new-quantity_recovered}。
- Spatial-related failure: {int(spatial_b.sum())} -> {int(spatial_c.sum())}，净增 {int(spatial_c.sum()-spatial_b.sum())}；paired 内部是 {spatial_recovered} 条解除、{spatial_new} 条新增，因此净变化 = {spatial_new} - {spatial_recovered} = {spatial_new-spatial_recovered}。

所以 quantity incidence 下降而 spatial-related incidence 略升，并不矛盾：它们是两个不同的 paired failure component；Candidate 在总目标与逐站目标重新分配后，quantity component 的解除多于新增，但 spatial component 的新增略多于解除。这里的数值解释直接来自逐路径 component crossing，不是总体均值猜测。

## 文件导航

- `01_group_production_summary.csv`: 四组、8877 zero-target aggregate、全路径的制氢与运行 KPI。
- `02_group_stage_profile.csv`: 四组 Stage1-6 active-path profile。
- `03_group_hourly_profile.csv`: 四组 48h active-path profile。
- `04_positive_transition_matrix.csv`: 1123 条 positive-target 完整 4x4 迁移。
- `05_flipped_113_paths.csv`: 70 recovered + 43 new failure 的逐路径证据。
- `06_persistent_failure_summary.csv`: 403 条 persistent failure 及 Candidate class 分解。
- `07_site_analysis.csv`: Site1-4，按 all/recovered/new/persistent cohort。
- `08_state_analysis.csv`: 35 terminal W states；重点状态已标记 `focus_state`。
"""
    path.write_text(text, encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)

    files = load_manifest(args.manifest)
    base = load_path(files["base_path"])
    candidate = load_path(files["candidate_path"])
    groups = assign_groups(base, candidate)
    group_lookup = pd.Series(groups.to_numpy(), index=base.path_id.to_numpy())

    base_site, base_site_htt = load_site_totals(files["base_site"])
    candidate_site, candidate_site_htt = load_site_totals(files["candidate_site"])
    base_hour, base_energy = load_hour(files["base_hour_site"])
    candidate_hour, candidate_energy = load_hour(files["candidate_hour_site"])

    base = base.merge(base_site, on="path_id", how="left", validate="one_to_one").merge(base_energy, on="path_id", how="left", validate="one_to_one")
    candidate = candidate.merge(candidate_site, on="path_id", how="left", validate="one_to_one").merge(candidate_energy, on="path_id", how="left", validate="one_to_one")
    require(base[["ordinary_demand_kg", "served_demand_kg", "shortage_kg", "total_EL_energy_kWh"]].notna().all().all(), "Base path supplement missing")
    require(candidate[["ordinary_demand_kg", "served_demand_kg", "shortage_kg", "total_EL_energy_kWh"]].notna().all().all(), "Candidate path supplement missing")
    require(float((base.shortage_kg - base.ordinary_shortage_total).abs().max()) <= 1e-7, "Base shortage total mismatch")
    require(float((candidate.shortage_kg - candidate.ordinary_shortage_total).abs().max()) <= 1e-7, "Candidate shortage total mismatch")

    paired = base.merge(candidate, on="path_id", suffixes=("_BASE", "_CANDIDATE"), validate="one_to_one")
    for site in range(1, 5):
        paired[f"target_site{site}_delta"] = paired[f"target_site{site}_CANDIDATE"] - paired[f"target_site{site}_BASE"]
    paired["target_total_delta"] = paired.target_total_CANDIDATE - paired.target_total_BASE
    positive = paired.target_total_calc_BASE > TOL
    require(int(positive.sum()) == 1123, "positive-target count failed")

    group_summary = group_production_summary(paired, groups)
    group_summary.to_csv(args.output / "01_group_production_summary.csv", index=False)

    base_stage = stage_profile(files["base_stage"], "BASE", group_lookup)
    candidate_stage = stage_profile(files["candidate_stage"], "CANDIDATE", group_lookup)
    combine_profiles(base_stage, candidate_stage, "stage").to_csv(args.output / "02_group_stage_profile.csv", index=False)

    base_hour_profile = hourly_profile(base_hour, "BASE", group_lookup)
    candidate_hour_profile = hourly_profile(candidate_hour, "CANDIDATE", group_lookup)
    combine_profiles(base_hour_profile, candidate_hour_profile, "global_hour").to_csv(args.output / "03_group_hourly_profile.csv", index=False)

    transitions = transition_matrix(paired, positive)
    transitions.to_csv(args.output / "04_positive_transition_matrix.csv", index=False)

    flips = flipped_paths(paired, positive, base_site_htt, candidate_site_htt)
    require(len(flips) == 113, "flipped path output is not 113")
    flips.to_csv(args.output / "05_flipped_113_paths.csv", index=False)

    persistent = persistent_summary(paired, positive)
    persistent.to_csv(args.output / "06_persistent_failure_summary.csv", index=False)

    sites = site_analysis(paired, positive)
    sites.to_csv(args.output / "07_site_analysis.csv", index=False)

    state_table = pd.read_csv(STATE_TABLE)
    states = state_analysis(paired, state_table)
    states.to_csv(args.output / "08_state_analysis.csv", index=False)

    write_summary(args.output / "09_deep_dive_summary_zh.md", group_summary, transitions, persistent, paired, groups)
    print(f"Deep-dive extraction complete: {args.output}")


if __name__ == "__main__":
    main()
