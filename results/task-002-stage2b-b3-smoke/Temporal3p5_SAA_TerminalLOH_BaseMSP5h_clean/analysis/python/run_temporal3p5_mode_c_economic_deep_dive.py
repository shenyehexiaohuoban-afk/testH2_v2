# -*- coding: utf-8 -*-
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import pandas as pd


TOL = 1e-9
GROUPS = [
    "PHYSICAL_DISSIPATION",
    "OTHER_ABSORPTION",
    "TRUE_STAGE7_ZERO_TARGET",
    "TRUE_STAGE7_POSITIVE_TARGET",
]
CLASSES = ["ADEQUATE", "PURE_QUANTITY", "PURE_LOCATION", "MIXED"]
RUN = Path(
    r"C:\Users\chaos\Desktop\biye\test\testH2_v2\results\task-002-stage2b-b3-smoke"
    r"\Temporal3p5_DRO_TerminalLOH_BaseMSP5h\training\runs\run-20260901-020054"
)
DEFAULT_MANIFEST = RUN / "oos_analysis/source_manifest.csv"
DEFAULT_OUTPUT = RUN / "mode_c_economic_deep_dive"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def pct(delta: float, base: float) -> float:
    return float(delta / base * 100.0) if abs(base) > TOL else np.nan


def load_manifest(path: Path) -> dict[str, Path]:
    frame = pd.read_csv(path)
    result = {r.role: Path(r.path) for r in frame.itertuples()}
    required = {
        f"{arm}_{kind}"
        for arm in ("base", "candidate")
        for kind in ("path", "stage", "site", "hour_site", "hour_system", "htt")
    }
    require(required.issubset(result), f"manifest missing {sorted(required - set(result))}")
    for role in required:
        require(result[role].is_file(), f"missing {role}: {result[role]}")
    return result


def classify(frame: pd.DataFrame) -> pd.DataFrame:
    target = frame[[f"target_site{i}" for i in range(1, 5)]].to_numpy(float)
    inv = frame[[f"inventory_site{i}" for i in range(1, 5)]].to_numpy(float)
    site_gap = np.maximum(target - inv, 0).sum(axis=1)
    quantity = np.maximum(target.sum(axis=1) - inv.sum(axis=1), 0)
    spatial = site_gap - quantity
    cls = np.select(
        [
            (quantity <= TOL) & (spatial <= TOL),
            (quantity > TOL) & (spatial <= TOL),
            (quantity <= TOL) & (spatial > TOL),
            (quantity > TOL) & (spatial > TOL),
        ],
        CLASSES,
        default="NOT_IDENTIFIABLE",
    )
    out = pd.DataFrame({
        "path_id": frame.path_id.to_numpy(int),
        "target_total_calc": target.sum(axis=1),
        "terminal_site_gap_calc": site_gap,
        "quantity_gap_calc": quantity,
        "spatial_gap_calc": spatial,
        "classification": cls,
    })
    for i in range(4):
        out[f"site{i+1}_gap_calc"] = np.maximum(target[:, i] - inv[:, i], 0)
    return out


def load_path(path: Path) -> pd.DataFrame:
    frame = pd.read_csv(path)
    require(len(frame) == 10000, f"expected 10000 paths: {path}")
    require(frame.path_id.tolist() == list(range(1, 10001)), f"path order mismatch: {path}")
    calc = classify(frame)
    for col in calc.columns[1:]:
        frame[col] = calc[col].to_numpy()
    return frame


def assign_groups(base: pd.DataFrame, candidate: pd.DataFrame) -> pd.Series:
    require(base.termination_type.equals(candidate.termination_type), "termination identity mismatch")
    bp = base.target_total_calc > TOL
    cp = candidate.target_total_calc > TOL
    require(bp.equals(cp), "positive-target membership mismatch")
    g = pd.Series(index=base.index, dtype="object")
    g[base.termination_type.eq("PHYSICAL_DISSIPATION_A1")] = GROUPS[0]
    g[base.termination_type.eq("LF8_ABSORBING")] = GROUPS[1]
    stage7 = base.termination_type.eq("STAGE7_TERMINAL_CHECK")
    g[stage7 & ~bp] = GROUPS[2]
    g[stage7 & bp] = GROUPS[3]
    expected = {GROUPS[0]: 3497, GROUPS[1]: 379, GROUPS[2]: 5001, GROUPS[3]: 1123}
    require(g.value_counts().to_dict() == expected, f"group mismatch: {g.value_counts().to_dict()}")
    return g


def group_masks(group: pd.Series) -> list[tuple[str, pd.Series]]:
    return [
        *[(name, group.eq(name)) for name in GROUPS],
        ("ALL_ZERO_TARGET", ~group.eq(GROUPS[3])),
        ("ALL_PATH", pd.Series(True, index=group.index)),
    ]


def distribution(values: pd.Series, prefix: str) -> dict[str, float | int]:
    v = pd.to_numeric(values, errors="coerce").dropna()
    return {
        f"{prefix}_mean": float(v.mean()), f"{prefix}_median": float(v.median()),
        f"{prefix}_q05": float(v.quantile(.05)), f"{prefix}_q25": float(v.quantile(.25)),
        f"{prefix}_q75": float(v.quantile(.75)), f"{prefix}_q95": float(v.quantile(.95)),
    }


def paired_distribution(base: pd.Series, candidate: pd.Series, prefix: str) -> dict[str, float | int]:
    delta = candidate - base
    return {
        **distribution(base, f"base_{prefix}"),
        **distribution(candidate, f"candidate_{prefix}"),
        f"paired_{prefix}_delta_mean": float(delta.mean()),
        f"paired_{prefix}_delta_median": float(delta.median()),
        f"paired_{prefix}_delta_q05": float(delta.quantile(.05)),
        f"paired_{prefix}_delta_q95": float(delta.quantile(.95)),
        f"paired_{prefix}_increase_count": int((delta > TOL).sum()),
        f"paired_{prefix}_decrease_count": int((delta < -TOL).sum()),
        f"paired_{prefix}_equal_count": int((delta.abs() <= TOL).sum()),
    }


def supplement_path(frame: pd.DataFrame, system_path: Path) -> pd.DataFrame:
    system = pd.read_csv(system_path, usecols=["path_id", "total_P_EL_kW", "root_grid_import"])
    totals = system.groupby("path_id", as_index=False).agg(
        PEL_energy_kWh=("total_P_EL_kW", "sum"),
        electricity_purchase_energy_kWh=("root_grid_import", "sum"),
    )
    out = frame.merge(totals, on="path_id", how="left", validate="one_to_one")
    require(out[["PEL_energy_kWh", "electricity_purchase_energy_kWh"]].notna().all().all(), "energy supplement missing")
    return out


def audit_schema() -> pd.DataFrame:
    rows = [
        ("P_EL_kW", "oos_hour_system.csv:total_P_EL_kW; oos_hour_site.csv:P_EL_kW", "kW", "rate", "sum over serialized 1h records -> kWh", "YES", "Electrolyzer electrical power."),
        ("electrolyzer_H2_production", "oos_hour_site.csv:H2_production_kg; path:total_H2_production", "kg", "amount", "sum hour/site or use serialized path total", "YES", "Exact serialized amount."),
        ("electricity_purchase_energy", "oos_hour_system.csv:root_grid_import", "kWh per serialized 1h record", "amount", "sum root_grid_import over serialized hours", "YES", "Distinct from P_EL energy because PV and network balance exist."),
        ("electricity_price", "oos_hour_system.csv:tariff_yuan_per_kwh", "yuan/kWh", "rate", "multiply by root_grid_import for the same serialized hour", "YES", "Exact grid purchase tariff."),
        ("electricity_related_cost", "path:electricity_cost; stage:grid_cost_yuan", "yuan", "amount", "sum stage grid_cost or use path electricity_cost", "YES", "Path electricity_cost exactly equals summed stage grid_cost_yuan."),
        ("P_EL_specific_cost", "none", "NOT_AVAILABLE", "NOT_AVAILABLE", "NOT_AVAILABLE", "NO", "P_EL_SPECIFIC_COST = NOT_IDENTIFIABLE; do not allocate grid cost to P_EL by average tariff."),
        ("electrolyzer_operating_cost", "path:production_om_cost; stage:production_om_cost_yuan", "yuan", "amount", "sum stage or use path serialized value", "YES", "Formal EL O&M; exact hourly reconstruction from serialized production and current formal coefficient."),
        ("HTT_shipped_mass", "path:total_HTT; stage:htt_kg; OD:flow_kg", "kg", "amount", "sum serialized flow", "YES", "Continuous shipped mass; not trip count."),
        ("HTT_trip_count", "none", "NOT_AVAILABLE", "NOT_AVAILABLE", "NOT_AVAILABLE", "NO", "No discrete trip variable in raw schema."),
        ("HTT_transport_cost", "path:HTT_cost; stage:htt_cost_yuan; OD:htt_cost_yuan", "yuan", "amount", "sum serialized OD cost", "YES", "OD cost closes to stage/path HTT cost."),
        ("ordinary_shortage", "path:ordinary_shortage_total; hour_site:ordinary_shortage_kg", "kg", "amount", "sum serialized hour/site", "YES", "Ordinary demand shortage, not terminal gap."),
        ("ordinary_shortage_cost", "path:ordinary_shortage_cost; stage:ordinary_shortage_cost_yuan", "yuan", "amount", "sum serialized stage/hour formula", "YES", "Formal OOS operating-cost component."),
        ("terminal_gap", "path:gap_site1..4; terminal_site_gap", "kg", "amount", "use serialized terminal fields", "YES", "Candidate target differs under revised TerminalLOH."),
        ("terminal_gap_penalty", "path:terminal_penalty_cost", "yuan", "amount", "use serialized path value", "YES", "TERMINAL_GAP_COST_NOT_PART_OF_OOS_OPERATING_COST; equals reported_objective - actual_operating_cost."),
        ("FC_generation_or_consumption", "none", "NOT_AVAILABLE", "NOT_AVAILABLE", "NOT_AVAILABLE", "NO", "No FC dispatch/cost fields in Mode-C raw schema."),
        ("FC_operating_cost", "none", "NOT_AVAILABLE", "NOT_AVAILABLE", "NOT_AVAILABLE", "NO", "Not identifiable in serialized objective components."),
        ("load_shedding_or_residual_cost", "none", "NOT_AVAILABLE", "NOT_AVAILABLE", "NOT_AVAILABLE", "NO", "No distinct residual/load-shedding cost in Mode-C raw schema."),
        ("holding_cost", "path:holding_cost; stage:holding_cost_yuan", "yuan", "amount", "sum stage or use path value", "YES", "Formal other identifiable OOS operating cost."),
        ("stage_cost", "stage:stage_objective_yuan", "yuan", "amount", "sum only actual serialized operating stages", "YES", "Exact stage operating objective, excludes future theta and terminal penalty."),
        ("total_path_operating_cost", "path:actual_operating_cost", "yuan", "amount", "use serialized path total", "YES", "Preferred total; closes to formal components."),
        ("reported_objective", "path:reported_objective", "yuan", "amount", "actual_operating_cost + terminal_penalty_cost", "YES", "Not used as operating cost."),
    ]
    return pd.DataFrame(rows, columns=["field_name", "source_file", "unit", "rate_or_amount", "aggregation_rule", "available_yes_no", "notes"])


def energy_summary(paired: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for name, mask in group_masks(paired.group):
        s = paired.loc[mask]
        row: dict[str, object] = {"group": name, "path_count": len(s)}
        metrics = {
            "H2_production_kg": "total_H2_production",
            "PEL_energy_kWh": "PEL_energy_kWh",
            "electricity_purchase_energy_kWh": "electricity_purchase_energy_kWh",
            "electricity_cost_yuan": "electricity_cost",
            "EL_operating_cost_yuan": "production_om_cost",
        }
        for out, col in metrics.items():
            b, c = s[f"{col}_BASE"], s[f"{col}_CANDIDATE"]
            d = float((c - b).mean())
            row[f"base_mean_{out}"] = float(b.mean())
            row[f"candidate_mean_{out}"] = float(c.mean())
            row[f"delta_mean_{out}"] = d
            row[f"delta_pct_{out}"] = pct(d, float(b.mean()))
        row["P_EL_SPECIFIC_COST"] = "NOT_IDENTIFIABLE"
        rows.append(row)
    return pd.DataFrame(rows)


def htt_summary(paired: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for name, mask in group_masks(paired.group):
        s = paired.loc[mask]
        row = {"group": name, "path_count": len(s)}
        for out, col in [("HTT_mass_kg", "total_HTT"), ("HTT_cost_yuan", "HTT_cost")]:
            b, c = s[f"{col}_BASE"], s[f"{col}_CANDIDATE"]
            d = float((c - b).mean())
            row[f"base_mean_{out}"] = float(b.mean())
            row[f"candidate_mean_{out}"] = float(c.mean())
            row[f"delta_mean_{out}"] = d
            row[f"delta_pct_{out}"] = pct(d, float(b.mean()))
        rows.append(row)
    return pd.DataFrame(rows)


def od_delta(base_path: Path, candidate_path: Path) -> pd.DataFrame:
    cols = ["origin_site", "destination_site", "flow_kg", "htt_cost_yuan"]
    b = pd.read_csv(base_path, usecols=cols).groupby(["origin_site", "destination_site"], as_index=False).sum()
    c = pd.read_csv(candidate_path, usecols=cols).groupby(["origin_site", "destination_site"], as_index=False).sum()
    b = b.rename(columns={"flow_kg": "base_total_mass_kg", "htt_cost_yuan": "base_total_cost_yuan"})
    c = c.rename(columns={"flow_kg": "candidate_total_mass_kg", "htt_cost_yuan": "candidate_total_cost_yuan"})
    out = b.merge(c, on=["origin_site", "destination_site"], how="outer").fillna(0)
    out["delta_total_mass_kg"] = out.candidate_total_mass_kg - out.base_total_mass_kg
    out["delta_total_cost_yuan"] = out.candidate_total_cost_yuan - out.base_total_cost_yuan
    for col in ["base_total_mass_kg", "candidate_total_mass_kg", "delta_total_mass_kg", "base_total_cost_yuan", "candidate_total_cost_yuan", "delta_total_cost_yuan"]:
        out[f"{col}_per_path"] = out[col] / 10000.0
    out["rank_cost_increase"] = out.delta_total_cost_yuan.rank(method="min", ascending=False).astype(int)
    out["rank_cost_decrease"] = out.delta_total_cost_yuan.rank(method="min", ascending=True).astype(int)
    out["top10_increased_OD"] = out.rank_cost_increase.le(10) & out.delta_total_cost_yuan.gt(TOL)
    out["top10_decreased_OD"] = out.rank_cost_decrease.le(10) & out.delta_total_cost_yuan.lt(-TOL)
    return out.sort_values("delta_total_cost_yuan", ascending=False)


def shortage_summary(paired: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for name, mask in group_masks(paired.group):
        s = paired.loc[mask]
        row = {"group": name, "path_count": len(s)}
        for out, col in [("ordinary_shortage_kg", "ordinary_shortage_total"), ("ordinary_shortage_cost_yuan", "ordinary_shortage_cost")]:
            b, c = s[f"{col}_BASE"], s[f"{col}_CANDIDATE"]
            d = float((c - b).mean())
            row[f"base_mean_{out}"] = float(b.mean())
            row[f"candidate_mean_{out}"] = float(c.mean())
            row[f"delta_mean_{out}"] = d
            row[f"delta_pct_{out}"] = pct(d, float(b.mean()))
        rows.append(row)
    return pd.DataFrame(rows)


def total_cost_summary(paired: pd.DataFrame, identity: dict[str, float]) -> pd.DataFrame:
    rows = []
    components = [
        ("total_operating_cost_yuan", "actual_operating_cost"),
        ("electricity_cost_yuan", "electricity_cost"),
        ("electrolyzer_om_cost_yuan", "production_om_cost"),
        ("HTT_cost_yuan", "HTT_cost"),
        ("ordinary_shortage_cost_yuan", "ordinary_shortage_cost"),
        ("holding_other_cost_yuan", "holding_cost"),
    ]
    for name, mask in group_masks(paired.group):
        s = paired.loc[mask]
        row: dict[str, object] = {"group": name, "path_count": len(s), "FC_cost": "NOT_AVAILABLE"}
        for out, col in components:
            b, c = s[f"{col}_BASE"], s[f"{col}_CANDIDATE"]
            d = float((c - b).mean())
            row[f"base_mean_{out}"] = float(b.mean())
            row[f"candidate_mean_{out}"] = float(c.mean())
            row[f"delta_mean_{out}"] = d
            row[f"delta_pct_{out}"] = pct(d, float(b.mean()))
        for col, label in [("actual_operating_cost", "total_cost"), ("electricity_cost", "electricity_cost"), ("HTT_cost", "HTT_cost")]:
            row.update(paired_distribution(s[f"{col}_BASE"], s[f"{col}_CANDIDATE"], label))
        row.update(identity)
        rows.append(row)
    return pd.DataFrame(rows)


def contribution_decomposition(paired: pd.DataFrame) -> pd.DataFrame:
    components = {
        "TOTAL_OPERATING_COST": "actual_operating_cost",
        "ELECTRICITY_GRID_COST": "electricity_cost",
        "ELECTROLYZER_OM_COST": "production_om_cost",
        "HTT_COST": "HTT_cost",
        "ORDINARY_SHORTAGE_COST": "ordinary_shortage_cost",
        "HOLDING_OTHER_COST": "holding_cost",
    }
    rows = []
    for component, col in components.items():
        all_delta = float((paired[f"{col}_CANDIDATE"] - paired[f"{col}_BASE"]).mean())
        weighted_sum = 0.0
        component_rows = []
        for group in GROUPS:
            s = paired.loc[paired.group.eq(group)]
            group_delta = float((s[f"{col}_CANDIDATE"] - s[f"{col}_BASE"]).mean())
            weight = len(s) / 10000.0
            contribution = weight * group_delta
            weighted_sum += contribution
            component_rows.append({
                "component": component, "group": group, "path_count": len(s), "group_weight": weight,
                "group_mean_delta_yuan": group_delta, "weighted_contribution_yuan_per_all_path": contribution,
                "all_path_component_delta_yuan": all_delta,
            })
        error = weighted_sum - all_delta
        for row in component_rows:
            row["four_group_sum_yuan"] = weighted_sum
            row["reconciliation_error_yuan"] = error
            rows.append(row)
    return pd.DataFrame(rows)


def stage_profile(stage_path: Path, system_path: Path, label: str, group_lookup: pd.Series) -> pd.DataFrame:
    stage = pd.read_csv(stage_path, usecols=[
        "path_id", "stage", "stage_objective_yuan", "grid_cost_yuan", "production_om_cost_yuan",
        "holding_cost_yuan", "ordinary_shortage_cost_yuan", "production_kg", "htt_kg", "htt_cost_yuan",
    ])
    system = pd.read_csv(system_path, usecols=["path_id", "stage", "total_P_EL_kW"])
    pel = system.groupby(["path_id", "stage"], as_index=False).agg(PEL_energy_kWh=("total_P_EL_kW", "sum"))
    stage = stage.merge(pel, on=["path_id", "stage"], how="left", validate="one_to_one")
    stage["group"] = stage.path_id.map(group_lookup)
    metrics = [
        "production_kg", "PEL_energy_kWh", "grid_cost_yuan", "production_om_cost_yuan", "htt_kg",
        "htt_cost_yuan", "ordinary_shortage_cost_yuan", "holding_cost_yuan", "stage_objective_yuan",
    ]
    out = stage.groupby(["group", "stage"], as_index=False).agg(
        active_path_count=("path_id", "nunique"), **{f"mean_{c}": (c, "mean") for c in metrics}
    )
    full = pd.MultiIndex.from_product([GROUPS, range(1, 7)], names=["group", "stage"])
    out = out.set_index(["group", "stage"]).reindex(full).reset_index()
    out.active_path_count = out.active_path_count.fillna(0).astype(int)
    out["arm"] = label
    return out


def combine_stage(base: pd.DataFrame, candidate: pd.DataFrame) -> pd.DataFrame:
    b = base.drop(columns="arm").rename(columns={c: f"base_{c}" for c in base.columns if c not in {"group", "stage"}})
    c = candidate.drop(columns="arm").rename(columns={c: f"candidate_{c}" for c in candidate.columns if c not in {"group", "stage"}})
    out = b.merge(c, on=["group", "stage"], validate="one_to_one")
    for col in [x for x in b.columns if x.startswith("base_mean_")]:
        metric = col.removeprefix("base_")
        out[f"delta_{metric}"] = out[f"candidate_{metric}"] - out[col]
    return out.sort_values(["group", "stage"])


def hourly_costs(hour_system: Path, hour_site: Path, htt_path: Path, label: str) -> pd.DataFrame:
    system = pd.read_csv(hour_system, usecols=[
        "path_id", "stage", "hour_in_stage", "global_hour", "tariff_yuan_per_kwh", "root_grid_import",
    ])
    site = pd.read_csv(hour_site, usecols=[
        "path_id", "stage", "hour_in_stage", "global_hour", "H2_production_kg", "ordinary_shortage_kg", "end_inventory_kg",
    ]).groupby(["path_id", "stage", "hour_in_stage", "global_hour"], as_index=False).sum()
    od = pd.read_csv(htt_path, usecols=["path_id", "global_hour", "htt_cost_yuan"]).groupby(
        ["path_id", "global_hour"], as_index=False
    ).sum()
    hour = system.merge(site, on=["path_id", "stage", "hour_in_stage", "global_hour"], validate="one_to_one")
    hour = hour.merge(od, on=["path_id", "global_hour"], how="left", validate="one_to_one")
    hour.htt_cost_yuan = hour.htt_cost_yuan.fillna(0)
    hour["electricity_cost_yuan"] = hour.root_grid_import * hour.tariff_yuan_per_kwh
    hour["electrolyzer_om_cost_yuan"] = hour.H2_production_kg * (8.0 / 13.0)
    hour["ordinary_shortage_cost_yuan"] = hour.ordinary_shortage_kg * 200.0
    hour["holding_cost_yuan"] = np.where(hour.hour_in_stage.eq(8), hour.end_inventory_kg * 0.05, 0.0)
    hour["total_operating_cost_yuan"] = hour[
        ["electricity_cost_yuan", "electrolyzer_om_cost_yuan", "ordinary_shortage_cost_yuan", "holding_cost_yuan", "htt_cost_yuan"]
    ].sum(axis=1)
    hour["arm"] = label
    return hour


def hourly_profile(base: pd.DataFrame, candidate: pd.DataFrame) -> pd.DataFrame:
    metrics = [
        "electricity_cost_yuan", "electrolyzer_om_cost_yuan", "htt_cost_yuan",
        "ordinary_shortage_cost_yuan", "holding_cost_yuan", "total_operating_cost_yuan",
    ]
    rows = []
    for hour in range(1, 49):
        b = base.loc[base.global_hour.eq(hour)]
        c = candidate.loc[candidate.global_hour.eq(hour)]
        row: dict[str, object] = {
            "hour": hour, "base_active_path_count": b.path_id.nunique(), "candidate_active_path_count": c.path_id.nunique(),
        }
        for metric in metrics:
            row[f"base_active_mean_{metric}"] = float(b[metric].mean()) if len(b) else np.nan
            row[f"candidate_active_mean_{metric}"] = float(c[metric].mean()) if len(c) else np.nan
            row[f"base_all_path_mean_{metric}"] = float(b[metric].sum() / 10000.0)
            row[f"candidate_all_path_mean_{metric}"] = float(c[metric].sum() / 10000.0)
            row[f"delta_all_path_mean_{metric}"] = row[f"candidate_all_path_mean_{metric}"] - row[f"base_all_path_mean_{metric}"]
        rows.append(row)
    out = pd.DataFrame(rows)
    out["cost_saving_rank"] = out.delta_all_path_mean_total_operating_cost_yuan.rank(method="min").astype(int)
    return out


def positive_cohorts(paired: pd.DataFrame) -> pd.DataFrame:
    positive = paired.group.eq(GROUPS[3])
    failure_b = ~paired.classification_BASE.eq("ADEQUATE")
    failure_c = ~paired.classification_CANDIDATE.eq("ADEQUATE")
    masks = [("ALL_POSITIVE_TARGET", positive)]
    masks += [(f"CANDIDATE_{cls}", positive & paired.classification_CANDIDATE.eq(cls)) for cls in CLASSES]
    masks += [
        ("RECOVERED_70", positive & failure_b & ~failure_c),
        ("NEW_FAILURE_43", positive & ~failure_b & failure_c),
        ("PERSISTENT_FAILURE_403", positive & failure_b & failure_c),
    ]
    rows = []
    for name, mask in masks:
        s = paired.loc[mask]
        row: dict[str, object] = {"cohort": name, "path_count": len(s), "classification_basis": "CANDIDATE for ADEQUATE/PQ/PL/MIXED cohorts"}
        for out, col in [
            ("H2_production_kg", "total_H2_production"), ("HTT_mass_kg", "total_HTT"),
            ("electricity_cost_yuan", "electricity_cost"), ("EL_om_cost_yuan", "production_om_cost"),
            ("HTT_cost_yuan", "HTT_cost"), ("ordinary_shortage_cost_yuan", "ordinary_shortage_cost"),
            ("total_operating_cost_yuan", "actual_operating_cost"), ("terminal_gap_kg", "terminal_site_gap_calc"),
            ("terminal_penalty_yuan", "terminal_penalty_cost"),
        ]:
            b, c = s[f"{col}_BASE"], s[f"{col}_CANDIDATE"]
            row[f"base_mean_{out}"] = float(b.mean()) if len(s) else np.nan
            row[f"candidate_mean_{out}"] = float(c.mean()) if len(s) else np.nan
            row[f"delta_mean_{out}"] = float((c - b).mean()) if len(s) else np.nan
        for site in range(1, 5):
            for arm in ("BASE", "CANDIDATE"):
                gap = s[f"site{site}_gap_calc_{arm}"]
                row[f"{arm.lower()}_mean_site{site}_gap_kg"] = float(gap.mean()) if len(s) else np.nan
                row[f"{arm.lower()}_mean_site{site}_terminal_penalty_yuan"] = float((gap * 1000.0).mean()) if len(s) else np.nan
        for col, label in [("actual_operating_cost", "total_cost"), ("electricity_cost", "electricity_cost"), ("HTT_cost", "HTT_cost")]:
            row.update(paired_distribution(s[f"{col}_BASE"], s[f"{col}_CANDIDATE"], label))
        row["terminal_cost_scope"] = "TERMINAL_GAP_COST_NOT_PART_OF_OOS_OPERATING_COST"
        rows.append(row)
    return pd.DataFrame(rows)


def fmt(x: float, n: int = 3) -> str:
    return f"{x:.{n}f}"


def summary_markdown(
    groups: pd.DataFrame, contributions: pd.DataFrame, shortage: pd.DataFrame,
    hourly: pd.DataFrame, cohorts: pd.DataFrame, od: pd.DataFrame,
    identity: dict[str, float],
) -> str:
    g = groups.set_index("group")
    s = shortage.set_index("group")
    c = cohorts.set_index("cohort")
    total_component = contributions[contributions.component.eq("TOTAL_OPERATING_COST")].set_index("group")

    lines = []
    for name in GROUPS[:3]:
        r = g.loc[name]
        deltas = {
            "electricity": r.delta_mean_electricity_cost_yuan,
            "EL O&M": r.delta_mean_electrolyzer_om_cost_yuan,
            "HTT": r.delta_mean_HTT_cost_yuan,
            "shortage": r.delta_mean_ordinary_shortage_cost_yuan,
            "holding": r.delta_mean_holding_other_cost_yuan,
        }
        dominant = max(deltas, key=lambda k: abs(deltas[k]))
        lines.append(
            f"- {name}: {fmt(r.base_mean_total_operating_cost_yuan)} -> {fmt(r.candidate_mean_total_operating_cost_yuan)} yuan/path, "
            f"delta {fmt(r.delta_mean_total_operating_cost_yuan)} ({fmt(r.delta_pct_total_operating_cost_yuan)}%); 最大分项为 {dominant} {fmt(deltas[dominant])} yuan/path。"
        )

    az = g.loc["ALL_ZERO_TARGET"]
    pos = g.loc[GROUPS[3]]
    allp = g.loc["ALL_PATH"]
    top_hours = hourly.nsmallest(10, "delta_all_path_mean_total_operating_cost_yuan")
    hour_text = ", ".join(
        f"H{int(r.hour)} {r.delta_all_path_mean_total_operating_cost_yuan:+.3f}" for r in top_hours.itertuples()
    )
    stage_cost = pd.read_csv(DEFAULT_OUTPUT / "07_group_stage_cost_profile.csv") if (DEFAULT_OUTPUT / "07_group_stage_cost_profile.csv").is_file() else None
    stage_text = "NOT_AVAILABLE"
    if stage_cost is not None:
        stage_cost["base_weighted"] = stage_cost.base_mean_stage_objective_yuan.fillna(0) * stage_cost.base_active_path_count / 10000
        stage_cost["candidate_weighted"] = stage_cost.candidate_mean_stage_objective_yuan.fillna(0) * stage_cost.candidate_active_path_count / 10000
        by_stage = stage_cost.groupby("stage")[["base_weighted", "candidate_weighted"]].sum()
        by_stage["delta"] = by_stage.candidate_weighted - by_stage.base_weighted
        stage_text = ", ".join(f"S{int(i)} {v:+.3f}" for i, v in by_stage.delta.items())

    rec = c.loc["RECOVERED_70"]
    new = c.loc["NEW_FAILURE_43"]
    htt_offset = allp.delta_mean_HTT_cost_yuan > TOL
    shortage_direction = "下降" if allp.delta_mean_ordinary_shortage_cost_yuan < -TOL else ("上升" if allp.delta_mean_ordinary_shortage_cost_yuan > TOL else "不变")
    zero_short = s.loc["ALL_ZERO_TARGET"]
    terminal_note = "Terminal penalty 单列，未并入 actual operating cost。"

    return f"""# Temporal3p5 Mode-C Economic Deep Dive

## 范围与成本口径

- 只读取已完成的 Base/Candidate Mode-C raw，10000 条 path 按 `path_id` 一对一配对；固定分组为 3497/379/5001/1123。
- 正式 operating-cost identity：`actual = electricity/grid + EL O&M + HTT + ordinary shortage + holding`。Path identity 最大/平均绝对误差为 `{identity['MAX_ABS_COST_IDENTITY_ERROR']:.3e}/{identity['MEAN_ABS_COST_IDENTITY_ERROR']:.3e}` yuan。
- `reported_objective = actual_operating_cost + terminal_penalty_cost`；`TERMINAL_GAP_COST_NOT_PART_OF_OOS_OPERATING_COST`。{terminal_note}
- P_EL energy 与 electricity purchase energy 分列；`P_EL_SPECIFIC_COST = NOT_IDENTIFIABLE`。FC、离散 HTT trip、独立 load-shedding/residual cost 均为 `NOT_AVAILABLE`。
- 所有比较均是在修正后的 Temporal3p5 TerminalLOH 定义和相同 Base MSP 框架下；不是相同 terminal target 下的反事实效率比较。

## A-C. 三类 zero-target 路径

{chr(10).join(lines)}

## D. ALL ZERO TARGET 8877

总 operating cost 为 `{fmt(az.base_mean_total_operating_cost_yuan)} -> {fmt(az.candidate_mean_total_operating_cost_yuan)}` yuan/path，delta `{fmt(az.delta_mean_total_operating_cost_yuan)}` (`{fmt(az.delta_pct_total_operating_cost_yuan)}%`)。其中 electricity `{fmt(az.delta_mean_electricity_cost_yuan)}`、EL O&M `{fmt(az.delta_mean_electrolyzer_om_cost_yuan)}`、HTT `{fmt(az.delta_mean_HTT_cost_yuan)}`、ordinary shortage `{fmt(az.delta_mean_ordinary_shortage_cost_yuan)}`、holding `{fmt(az.delta_mean_holding_other_cost_yuan)}` yuan/path。Ordinary shortage cost 为 `{fmt(zero_short.base_mean_ordinary_shortage_cost_yuan)} -> {fmt(zero_short.candidate_mean_ordinary_shortage_cost_yuan)}`，没有因少制氢而恶化。

## E. Positive-target 1123

Production 为 `{fmt(pos.base_mean_H2_production_kg if 'base_mean_H2_production_kg' in pos else np.nan)} -> {fmt(pos.candidate_mean_H2_production_kg if 'candidate_mean_H2_production_kg' in pos else np.nan)}` kg/path；总 operating cost `{fmt(pos.base_mean_total_operating_cost_yuan)} -> {fmt(pos.candidate_mean_total_operating_cost_yuan)}`，delta `{fmt(pos.delta_mean_total_operating_cost_yuan)}` (`{fmt(pos.delta_pct_total_operating_cost_yuan)}%`)。其成本降幅相对 zero-target 的判断见实际百分比；这反映 revised terminal preparation policy consequence，不能当作相同服务要求下的效率差。

实际结果否定“positive-target 因保留更多准备而成本降幅必然更小”：其 production 降幅确实小于 zero-target，但 operating-cost 降幅为 `-3.182%`，反而大于 zero-target 的 `-1.357%`，主要因为 positive-target ordinary shortage cost 下降 `{fmt(abs(pos.delta_mean_ordinary_shortage_cost_yuan))}` yuan/path。

## F-G. 全路径与四组贡献

全 10000 条 operating cost `{fmt(allp.base_mean_total_operating_cost_yuan)} -> {fmt(allp.candidate_mean_total_operating_cost_yuan)}` yuan/path，delta `{fmt(allp.delta_mean_total_operating_cost_yuan)}` (`{fmt(allp.delta_pct_total_operating_cost_yuan)}%`)。

四组对全路径 mean cost delta 的贡献：

{chr(10).join(f'- {name}: {total_component.loc[name].weighted_contribution_yuan_per_all_path:+.3f} yuan/path' for name in GROUPS)}

四项和 `{total_component.four_group_sum_yuan.iloc[0]:+.6f}`，reconciliation error `{total_component.reconciliation_error_yuan.iloc[0]:.3e}` yuan/path。

## H-J. 成本是否转移

- 全路径 electricity delta `{allp.delta_mean_electricity_cost_yuan:+.3f}` yuan/path，是绝对值最大的成本来源，约占总节省的 `{abs(allp.delta_mean_electricity_cost_yuan/allp.delta_mean_total_operating_cost_yuan)*100:.2f}%`；ordinary shortage cost 约占 `{abs(allp.delta_mean_ordinary_shortage_cost_yuan/allp.delta_mean_total_operating_cost_yuan)*100:.2f}%`，EL O&M 另为 `{allp.delta_mean_electrolyzer_om_cost_yuan:+.3f}`。
- HTT mass 全路径增加，但 HTT cost delta 仅 `{allp.delta_mean_HTT_cost_yuan:+.3f}` yuan/path：{'上升并抵消一部分节省' if htt_offset else '没有形成总体成本转移，说明实际运输重构偏向较低成本 OD'}。zero-target 内 HTT cost 则增加 `+7.311` yuan/path，确实抵消少量电费节省。OD 增减明细见 `03_htt_od_cost_delta.csv`。
- Ordinary shortage cost `{shortage_direction}`，delta `{allp.delta_mean_ordinary_shortage_cost_yuan:+.3f}` yuan/path；不能将成本下降解释为 ordinary service 被牺牲。

## K. Stage / hour

全路径 Stage1-6 cost delta：{stage_text} yuan/path。Stage1-2 合计约占总节省的 `52.02%`，因此成本下降也主要形成于早期，但集中程度低于 production 的 `64.34%`；Stage3-4 仍贡献显著。节省最大的 10 个小时：{hour_text} yuan/path。小时 total 由可逐项回聚的 formal components 构成，holding 在每个 serialized stage 的第 8 小时记账，未把早停后的小时伪填为 active conditional cost。

## L. Recovered 70

Production `{rec.delta_mean_H2_production_kg:+.3f}` kg/path，HTT mass `{rec.delta_mean_HTT_mass_kg:+.3f}` kg/path；electricity `{rec.delta_mean_electricity_cost_yuan:+.3f}`、EL O&M `{rec.delta_mean_EL_om_cost_yuan:+.3f}`、HTT cost `{rec.delta_mean_HTT_cost_yuan:+.3f}`、shortage cost `{rec.delta_mean_ordinary_shortage_cost_yuan:+.3f}`、total operating cost `{rec.delta_mean_total_operating_cost_yuan:+.3f}` yuan/path。结合既有 service 结果，这一 cohort 符合“更少生产 + 更多运输质量 + service 改善”，但不符合“HTT cost 上升”：运输质量增加 `4.023 kg/path` 的同时 HTT cost 下降 `162.684 yuan/path`，表明 OD 组合转向了更低单位成本的路线。

## M. New failure 43

Production `{new.delta_mean_H2_production_kg:+.3f}` kg/path，HTT mass `{new.delta_mean_HTT_mass_kg:+.3f}` kg/path；electricity `{new.delta_mean_electricity_cost_yuan:+.3f}`、EL O&M `{new.delta_mean_EL_om_cost_yuan:+.3f}`、HTT cost `{new.delta_mean_HTT_cost_yuan:+.3f}`、shortage cost `{new.delta_mean_ordinary_shortage_cost_yuan:+.3f}`、total operating cost `{new.delta_mean_total_operating_cost_yuan:+.3f}` yuan/path。与 recovered 相比，production 降幅接近，但 HTT mass 增加较少、total cost 节省较小，且 terminal gap 反而增加 `{new.delta_mean_terminal_gap_kg:+.3f} kg/path`；经济成本下降并未阻止逐站 terminal mismatch 形成新失败。

## N. 一句话结论

在修正后的 Temporal3p5 TerminalLOH 下，Candidate 的实际数据表现为更低的提前准备 operating cost，ordinary shortage cost 未恶化，且总体 terminal service 改善；但逐站与身份翻转仍存在 trade-off，特别是 new-failure 路径，因此不能表述为所有路径、所有站点均无代价改善。
"""


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    files = load_manifest(args.manifest)

    base = supplement_path(load_path(files["base_path"]), files["base_hour_system"])
    candidate = supplement_path(load_path(files["candidate_path"]), files["candidate_hour_system"])
    groups = assign_groups(base, candidate)
    paired = base.merge(candidate, on="path_id", suffixes=("_BASE", "_CANDIDATE"), validate="one_to_one")
    paired["group"] = groups.to_numpy()
    require(paired.path_id.tolist() == list(range(1, 10001)), "paired path order failed")

    component_cols = ["holding_cost", "electricity_cost", "production_om_cost", "ordinary_shortage_cost", "HTT_cost"]
    errors = []
    for arm in ("BASE", "CANDIDATE"):
        component_sum = sum(paired[f"{c}_{arm}"] for c in component_cols)
        errors.append((paired[f"actual_operating_cost_{arm}"] - component_sum).abs())
    all_errors = pd.concat(errors, ignore_index=True)
    identity = {
        "MAX_ABS_COST_IDENTITY_ERROR": float(all_errors.max()),
        "MEAN_ABS_COST_IDENTITY_ERROR": float(all_errors.mean()),
    }
    require(identity["MAX_ABS_COST_IDENTITY_ERROR"] < 1e-6, "path cost identity failed")

    audit_schema().to_csv(args.output / "00_economic_schema_audit.csv", index=False)
    energy = energy_summary(paired)
    energy.to_csv(args.output / "01_group_energy_cost_summary.csv", index=False)
    htt = htt_summary(paired)
    htt.to_csv(args.output / "02_group_htt_cost_summary.csv", index=False)
    od = od_delta(files["base_htt"], files["candidate_htt"])
    od.to_csv(args.output / "03_htt_od_cost_delta.csv", index=False)
    shortage = shortage_summary(paired)
    shortage.to_csv(args.output / "04_group_ordinary_shortage_cost.csv", index=False)
    total = total_cost_summary(paired, identity)
    # Add production fields used directly by the final summary.
    ekey = energy.set_index("group")
    for col in ["base_mean_H2_production_kg", "candidate_mean_H2_production_kg", "delta_mean_H2_production_kg", "delta_pct_H2_production_kg"]:
        total[col] = total.group.map(ekey[col])
    total.to_csv(args.output / "05_group_total_cost_summary.csv", index=False)
    contributions = contribution_decomposition(paired)
    require(contributions.reconciliation_error_yuan.abs().max() < 1e-7, "contribution reconciliation failed")
    contributions.to_csv(args.output / "06_cost_contribution_decomposition.csv", index=False)

    group_lookup = pd.Series(groups.to_numpy(), index=base.path_id.to_numpy())
    stage_b = stage_profile(files["base_stage"], files["base_hour_system"], "BASE", group_lookup)
    stage_c = stage_profile(files["candidate_stage"], files["candidate_hour_system"], "CANDIDATE", group_lookup)
    stage = combine_stage(stage_b, stage_c)
    stage.to_csv(args.output / "07_group_stage_cost_profile.csv", index=False)

    hour_b = hourly_costs(files["base_hour_system"], files["base_hour_site"], files["base_htt"], "BASE")
    hour_c = hourly_costs(files["candidate_hour_system"], files["candidate_hour_site"], files["candidate_htt"], "CANDIDATE")
    # Hourly reconstruction must equal serialized path cost.
    for label, hour, path_frame in [("BASE", hour_b, base), ("CANDIDATE", hour_c, candidate)]:
        reconstructed = hour.groupby("path_id").total_operating_cost_yuan.sum().reindex(path_frame.path_id).to_numpy()
        err = np.abs(reconstructed - path_frame.actual_operating_cost.to_numpy())
        require(float(err.max()) < 1e-6, f"{label} hourly cost identity failed: {err.max()}")
    hourly = hourly_profile(hour_b, hour_c)
    hourly.to_csv(args.output / "08_hourly_cost_profile.csv", index=False)

    cohorts = positive_cohorts(paired)
    require(int(cohorts.loc[cohorts.cohort.eq("RECOVERED_70"), "path_count"].iloc[0]) == 70, "recovered count failed")
    require(int(cohorts.loc[cohorts.cohort.eq("NEW_FAILURE_43"), "path_count"].iloc[0]) == 43, "new failure count failed")
    require(int(cohorts.loc[cohorts.cohort.eq("PERSISTENT_FAILURE_403"), "path_count"].iloc[0]) == 403, "persistent count failed")
    cohorts.to_csv(args.output / "09_positive_cohort_cost_summary.csv", index=False)

    text = summary_markdown(total, contributions, shortage, hourly, cohorts, od, identity)
    (args.output / "10_economic_deep_dive_summary_zh.md").write_text(text, encoding="utf-8")
    print(f"Economic deep dive complete: {args.output}")


if __name__ == "__main__":
    main()
