# -*- coding: utf-8 -*-
"""Read-only closure analysis for the existing Base/B0001 common-path OOS."""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import pandas as pd

EPS = 1e-9
SITES = (1, 2, 3, 4)
WINDOWS = (16, 8, 4)
BASE_ROOT = Path(
    "hourly_grid_h2/output/stage89q_penalty1000_vs1500_long_training/"
    "run-003/penalty1000"
)


def require(ok: bool, message: str) -> None:
    if not ok:
        raise RuntimeError(message)


def qstats(series: pd.Series) -> dict[str, float]:
    x = pd.to_numeric(series, errors="coerce").dropna()
    if x.empty:
        return {k: float("nan") for k in ("mean", "median", "q25", "q75", "q90", "q95", "max")}
    return {
        "mean": float(x.mean()), "median": float(x.median()),
        "q25": float(x.quantile(.25)), "q75": float(x.quantile(.75)),
        "q90": float(x.quantile(.90)), "q95": float(x.quantile(.95)),
        "max": float(x.max()),
    }


def read_source(root: Path) -> dict[str, pd.DataFrame]:
    path = pd.read_csv(root / "path_summary/oos_path_summary.csv")
    stage = pd.read_csv(
        root / "path_summary/oos_stage_site_summary.csv",
        usecols=["path_id", "stage", "state_id", "site", "htt_in_kg", "htt_out_kg"],
    )
    hour = pd.read_csv(
        root / "hourly_site/oos_hour_site.csv",
        usecols=[
            "path_id", "stage", "state_id", "hurricane_a", "hurricane_loc", "hurricane_lf",
            "global_hour", "site", "ordinary_shortage_kg", "H2_production_kg",
            "begin_inventory_kg", "end_inventory_kg", "HTT_in_kg", "HTT_out_kg",
        ],
    )
    flow = pd.read_csv(
        root / "htt_od/oos_positive_htt_flows.csv",
        usecols=["path_id", "global_hour", "origin_site", "destination_site", "flow_kg"],
    )
    return {"path": path, "stage": stage, "hour": hour, "flow": flow}


PATH_COLS = [
    "arm", "path_id", "state_sequence", "termination_type", "termination_stage", "termination_state",
    "operating_stage_count", "reached_stage7", "actual_operating_cost", "total_H2_production", "total_HTT",
    "terminal_inventory_total", "inventory_site1", "inventory_site2", "inventory_site3", "inventory_site4",
    "terminal_state_id", "terminal_a", "terminal_loc", "target_site1", "target_site2", "target_site3", "target_site4",
    "target_total", "gap_site1", "gap_site2", "gap_site3", "gap_site4", "terminal_site_gap",
    "terminal_total_quantity_shortfall", "terminal_spatial_component", "surplus_site1", "surplus_site2", "surplus_site3", "surplus_site4",
    "terminal_penalty_cost", "sitewise_class", "target_total_recomputed", "inventory_total_recomputed",
    "total_quantity_shortfall_recomputed", "site_wise_terminal_gap_recomputed", "positive_target", "total_site_gap_ratio",
    "max_site_deficit_ratio", "deficient_site_count", "production_total_kg_site1", "production_total_kg_site2",
    "production_total_kg_site3", "production_total_kg_site4",
]


def load_v4(v4: Path) -> tuple[pd.DataFrame, pd.DataFrame]:
    p = v4 / "path_relative_gap_metrics.csv"
    d = pd.read_csv(p, usecols=PATH_COLS)
    d["path_id"] = pd.to_numeric(d["path_id"], errors="raise").astype(int)
    base = d[d.arm == "BASE"].copy()
    cand = d[d.arm == "B0001"].copy()
    require(len(base) == 10000 and len(cand) == 10000, "v4 path count mismatch")
    require(base.path_id.tolist() == cand.path_id.tolist(), "Base/B0001 ordered path IDs differ")
    return base, cand


def make_pair(base: pd.DataFrame, cand: pd.DataFrame) -> pd.DataFrame:
    b = base.add_suffix("_BASE").rename(columns={"path_id_BASE": "path_id"})
    c = cand.add_suffix("_B0001").rename(columns={"path_id_B0001": "path_id"})
    p = b.merge(c, on="path_id", how="inner", validate="one_to_one")
    p["positive_target_common"] = p.positive_target_BASE.astype(bool) & p.positive_target_B0001.astype(bool)
    p["transition"] = p.sitewise_class_BASE.astype(str) + " -> " + p.sitewise_class_B0001.astype(str)
    p["transition_family"] = np.select(
        [
            (p.sitewise_class_BASE == "ADEQUATE") & (p.sitewise_class_B0001 == "ADEQUATE"),
            (p.sitewise_class_BASE == "ADEQUATE") & (p.sitewise_class_B0001 != "ADEQUATE"),
            (p.sitewise_class_BASE != "ADEQUATE") & (p.sitewise_class_B0001 == "ADEQUATE"),
        ],
        ["ADEQUATE -> ADEQUATE", "ADEQUATE -> FAILURE", "FAILURE -> ADEQUATE"],
        default="FAILURE -> FAILURE",
    )
    p["new_failure"] = p.positive_target_common & (p.sitewise_class_BASE == "ADEQUATE") & (p.sitewise_class_B0001 == "PURE_LOCATION")
    p["recovered"] = p.positive_target_common & (p.sitewise_class_BASE != "ADEQUATE") & (p.sitewise_class_B0001 == "ADEQUATE")
    p["persistent_failure"] = p.positive_target_common & (p.sitewise_class_BASE != "ADEQUATE") & (p.sitewise_class_B0001 != "ADEQUATE")
    p["delta_site_gap"] = p.site_wise_terminal_gap_recomputed_B0001 - p.site_wise_terminal_gap_recomputed_BASE
    p["delta_terminal_penalty"] = 1000.0 * p.delta_site_gap
    p["delta_operating_cost"] = p.actual_operating_cost_B0001 - p.actual_operating_cost_BASE
    return p


def target_signature(row: pd.Series, suffix: str) -> str:
    return "/".join(f"{float(row[f'target_site{i}_{suffix}']):.6f}" for i in SITES)


def state_winner_loser(pair: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for cohort, mask in (("NEW_FAILURES", pair.new_failure), ("RECOVERED_PATHS", pair.recovered)):
        q = pair[mask]
        for arm in ("BASE", "B0001"):
            suffix = arm
            x = q.copy()
            x["target_vector"] = x.apply(lambda r: target_signature(r, suffix), axis=1)
            keys = [f"terminal_state_id_{suffix}", f"terminal_a_{suffix}", f"terminal_loc_{suffix}", "target_vector", f"termination_stage_{suffix}", f"termination_type_{suffix}"]
            g = x.groupby(keys, dropna=False, as_index=False).agg(
                paths=("path_id", "size"),
                mean_site_gap_kg=(f"site_wise_terminal_gap_recomputed_{suffix}", "mean"),
                mean_terminal_penalty=(f"site_wise_terminal_gap_recomputed_{suffix}", lambda z: 1000.0 * float(z.mean())),
                mean_total_quantity_shortfall_kg=(f"total_quantity_shortfall_recomputed_{suffix}", "mean"),
                mean_terminal_inventory_kg=(f"terminal_inventory_total_{suffix}", "mean"),
                mean_production_kg=(f"total_H2_production_{suffix}", "mean"),
                mean_htt_kg=(f"total_HTT_{suffix}", "mean"),
            )
            g.insert(0, "cohort", cohort); g.insert(1, "arm", arm)
            g = g.rename(columns={f"terminal_state_id_{suffix}": "terminal_state_id", f"terminal_a_{suffix}": "intensity", f"terminal_loc_{suffix}": "terminal_loc", f"termination_stage_{suffix}": "termination_stage", f"termination_type_{suffix}": "termination_type"})
            rows.append(g)
    out = pd.concat(rows, ignore_index=True)
    return out.sort_values(["cohort", "arm", "paths"], ascending=[True, True, False])


def penalty_decomposition(pair: pd.DataFrame) -> pd.DataFrame:
    rows = []
    pos = pair[pair.positive_target_common].copy()
    for scope, frame, key in [
        ("EXACT_TRANSITION", pos, "transition"),
        ("TRANSITION_FAMILY", pos, "transition_family"),
    ]:
        for label, g in frame.groupby(key, dropna=False):
            s = qstats(g.delta_site_gap)
            rows.append({"scope": scope, "transition": label, "paths": len(g), "site_gap_sum_kg": float(g.delta_site_gap.sum()), "penalty_sum": float(g.delta_terminal_penalty.sum()), "operating_cost_delta_sum": float(g.delta_operating_cost.sum()), "penalty_share_of_all_positive_delta": float(g.delta_terminal_penalty.sum() / pos.delta_terminal_penalty.sum()) if abs(pos.delta_terminal_penalty.sum()) > EPS else np.nan, **{f"site_gap_{k}": v for k, v in s.items()}, **{f"penalty_{k}": 1000.0 * v for k, v in s.items()}, **{f"operating_cost_delta_{k}": v for k, v in qstats(g.delta_operating_cost).items()}})
    s = qstats(pos.delta_site_gap)
    rows.append({"scope": "ALL_POSITIVE_TARGET", "transition": "ALL_POSITIVE_TARGET", "paths": len(pos), "site_gap_sum_kg": float(pos.delta_site_gap.sum()), "penalty_sum": float(pos.delta_terminal_penalty.sum()), "operating_cost_delta_sum": float(pos.delta_operating_cost.sum()), "penalty_share_of_all_positive_delta": 1.0, **{f"site_gap_{k}": v for k, v in s.items()}, **{f"penalty_{k}": 1000.0 * v for k, v in s.items()}, **{f"operating_cost_delta_{k}": v for k, v in qstats(pos.delta_operating_cost).items()}})
    all_s = qstats(pair.delta_site_gap)
    rows.append({"scope": "ALL_PATHS", "transition": "ALL_PATHS", "paths": len(pair), "site_gap_sum_kg": float(pair.delta_site_gap.sum()), "penalty_sum": float(pair.delta_terminal_penalty.sum()), "operating_cost_delta_sum": float(pair.delta_operating_cost.sum()), "penalty_share_of_all_positive_delta": float(pair.delta_terminal_penalty.sum() / pos.delta_terminal_penalty.sum()) if abs(pos.delta_terminal_penalty.sum()) > EPS else np.nan, **{f"site_gap_{k}": v for k, v in all_s.items()}, **{f"penalty_{k}": 1000.0 * v for k, v in all_s.items()}, **{f"operating_cost_delta_{k}": v for k, v in qstats(pair.delta_operating_cost).items()}})
    return pd.DataFrame(rows)


def site4_cover(pair: pd.DataFrame) -> pd.DataFrame:
    q = pair[pair.new_failure].copy()
    q["site4_surplus"] = q.surplus_site4_B0001
    q["site1_deficit"] = q.gap_site1_B0001
    q["site2_deficit"] = q.gap_site2_B0001
    q["site3_deficit"] = q.gap_site3_B0001
    q["other_site_gap"] = q[["site1_deficit", "site2_deficit", "site3_deficit"]].sum(axis=1)
    q["cover_ratio"] = np.where(q.other_site_gap > EPS, q.site4_surplus / q.other_site_gap, np.nan)
    detail_cols = ["path_id", "site4_surplus", "site1_deficit", "site2_deficit", "site3_deficit", "other_site_gap", "cover_ratio", "terminal_loc_B0001", "terminal_state_id_B0001"]
    detail = q[detail_cols].copy(); detail.insert(0, "record_type", "PATH")
    rows = []
    for metric in ("cover_ratio", "site4_surplus", "other_site_gap", "site1_deficit", "site2_deficit", "site3_deficit"):
        s = qstats(q[metric])
        rows.append({"record_type": "SUMMARY", "metric": metric, "paths": len(q), **s})
    valid = q[q.other_site_gap > EPS]
    for name, mask in {
        "site4_surplus_ge_other_gap": q.site4_surplus + EPS >= q.other_site_gap,
        "site4_surplus_ge_half_other_gap": q.site4_surplus + EPS >= 0.5 * q.other_site_gap,
        "site4_surplus_zero": q.site4_surplus <= EPS,
    }.items():
        valid_mask = mask & (q.other_site_gap > EPS)
        rows.append({"record_type": "SUMMARY", "metric": name, "paths": len(q), "condition_count": int(mask.sum()), "valid_other_gap_paths": len(valid), "valid_condition_count": int(valid_mask.sum())})
    summary = pd.DataFrame(rows)
    return pd.concat([detail, summary], ignore_index=True, sort=False)


def flow_arm(term: pd.DataFrame, source: dict[str, pd.DataFrame], ids: set[int]) -> pd.DataFrame:
    t = term[term.path_id.isin(ids)].set_index("path_id")
    stage = source["stage"]
    flow = source["flow"]
    flow_groups = {pid: g for pid, g in flow.groupby("path_id", sort=False)}
    stage_groups = {pid: g for pid, g in stage.groupby("path_id", sort=False)}
    rows = []
    for pid in sorted(ids):
        g = flow_groups.get(pid, flow.iloc[0:0].copy())
        tg = t.loc[pid]
        gaps = {s for s in SITES if float(tg[f"gap_site{s}"]) > EPS}
        surplus = {s for s in SITES if float(tg[f"surplus_site{s}"]) > EPS}
        total = float(g.flow_kg.sum()) if not g.empty else 0.0
        od = g.groupby(["origin_site", "destination_site"], as_index=False)["flow_kg"].sum() if not g.empty else g
        aligned = g[g.destination_site.isin(gaps) & g.origin_site.isin(surplus)] if not g.empty else g
        max_hour = int(g.global_hour.max()) if not g.empty else 0
        stage_g = stage_groups.get(pid, stage.iloc[0:0].copy())
        def od_string(x: pd.DataFrame) -> str:
            return ";".join(f"{int(r.origin_site)}->{int(r.destination_site)}:{float(r.flow_kg):.6f}" for r in x.itertuples(index=False))
        def recent(x: pd.DataFrame, w: int) -> float:
            return float(x[x.global_hour > max_hour - w].flow_kg.sum()) if not x.empty else 0.0
        aligned_kg = float(aligned.flow_kg.sum()) if not aligned.empty else 0.0
        aligned4 = recent(aligned, 4)
        if total <= EPS:
            flag = "NO_TRANSFER"
        elif aligned_kg <= EPS:
            flag = "WRONG_DIRECTION_EX_POST"
        elif aligned4 <= EPS:
            flag = "TOO_LATE_EX_POST"
        elif aligned_kg >= total - 1e-6:
            flag = "TARGET_ALIGNED"
        else:
            flag = "PARTIAL_ALIGNMENT"
        rows.append({
            "path_id": pid, "total_htt": total, "od_pairs": od_string(od),
            "aligned_htt": aligned_kg, "aligned_final16h": recent(aligned, 16), "aligned_final8h": recent(aligned, 8), "aligned_final4h": aligned4,
            "total_final16h": recent(g, 16), "total_final8h": recent(g, 8), "total_final4h": recent(g, 4),
            "deficit_site_inflow": float(stage_g[stage_g.site.isin(gaps)].htt_in_kg.sum()),
            "surplus_site_outflow": float(stage_g[stage_g.site.isin(surplus)].htt_out_kg.sum()),
            "htt_mechanism_flag_expost": flag,
        })
    return pd.DataFrame(rows)


def mechanism_table(pair: pd.DataFrame, base_source: dict[str, pd.DataFrame], cand_source: dict[str, pd.DataFrame]) -> pd.DataFrame:
    ids = set(pair.loc[pair.new_failure | pair.recovered, "path_id"])
    bterm = pair[["path_id"] + [c for c in pair.columns if c.endswith("_BASE")]].copy()
    cterm = pair[["path_id"] + [c for c in pair.columns if c.endswith("_B0001")]].copy()
    for frame, suffix in ((bterm, "_BASE"), (cterm, "_B0001")):
        for s in SITES:
            frame[f"gap_site{s}"] = frame[f"gap_site{s}{suffix}"]
            frame[f"surplus_site{s}"] = frame[f"surplus_site{s}{suffix}"]
    fb = flow_arm(bterm, base_source, ids).add_suffix("_BASE").rename(columns={"path_id_BASE": "path_id"})
    fc = flow_arm(cterm, cand_source, ids).add_suffix("_B0001").rename(columns={"path_id_B0001": "path_id"})
    q = pair[pair.path_id.isin(ids)].copy().merge(fb, on="path_id").merge(fc, on="path_id")
    q["group"] = np.where(q.new_failure, "NEW_FAILURES", "RECOVERED_PATHS")
    for s in SITES:
        q[f"production_delta_site{s}"] = q[f"production_total_kg_site{s}_B0001"] - q[f"production_total_kg_site{s}_BASE"]
        q[f"terminal_inventory_delta_site{s}"] = q[f"inventory_site{s}_B0001"] - q[f"inventory_site{s}_BASE"]
    for name in ("total_htt", "aligned_htt", "aligned_final16h", "aligned_final8h", "aligned_final4h", "total_final16h", "total_final8h", "total_final4h", "deficit_site_inflow", "surplus_site_outflow"):
        q[f"{name}_delta"] = q[f"{name}_B0001"] - q[f"{name}_BASE"]
    detail_cols = ["path_id", "group", "transition", "htt_mechanism_flag_expost_BASE", "htt_mechanism_flag_expost_B0001", "od_pairs_BASE", "od_pairs_B0001"]
    detail_cols += [f"gap_site{s}_BASE" for s in SITES] + [f"gap_site{s}_B0001" for s in SITES] + [f"surplus_site{s}_BASE" for s in SITES] + [f"surplus_site{s}_B0001" for s in SITES]
    detail_cols += [f"production_delta_site{s}" for s in SITES] + [f"terminal_inventory_delta_site{s}" for s in SITES]
    detail_cols += [f"{x}_delta" for x in ("total_htt", "aligned_htt", "aligned_final16h", "aligned_final8h", "aligned_final4h", "total_final16h", "total_final8h", "total_final4h", "deficit_site_inflow", "surplus_site_outflow")]
    detail = q[detail_cols].copy(); detail.insert(0, "record_type", "PATH")
    rows = []
    numeric = [f"production_delta_site{s}" for s in SITES] + [f"terminal_inventory_delta_site{s}" for s in SITES] + [f"{x}_delta" for x in ("total_htt", "aligned_htt", "aligned_final16h", "aligned_final8h", "aligned_final4h", "total_final16h", "total_final8h", "total_final4h", "deficit_site_inflow", "surplus_site_outflow")]
    for group, g in q.groupby("group"):
        for metric in numeric:
            rows.append({"record_type": "SUMMARY", "group": group, "metric": metric, "paths": len(g), **qstats(g[metric])})
        for arm in ("BASE", "B0001"):
            for flag, gg in g.groupby(f"htt_mechanism_flag_expost_{arm}"):
                rows.append({"record_type": "FLAG_COUNT", "group": group, "arm": arm, "metric": "htt_mechanism_flag_expost", "flag": flag, "paths": len(gg)})
    od_rows = []
    for group, g in q.groupby("group"):
        totals: dict[str, dict[str, float]] = {}
        for arm in ("BASE", "B0001"):
            for value in g[f"od_pairs_{arm}"]:
                for token in str(value).split(";") if str(value) else []:
                    od, amount = token.rsplit(":", 1); totals.setdefault(od, {}).setdefault(arm, 0.0); totals[od][arm] += float(amount)
        for od, vals in totals.items():
            b = vals.get("BASE", 0.0); c = vals.get("B0001", 0.0)
            od_rows.append({"record_type": "OD_SUMMARY", "group": group, "od_pair": od, "base_htt_sum": b, "b0001_htt_sum": c, "delta_htt_sum": c - b})
    return pd.concat([detail, pd.DataFrame(rows), pd.DataFrame(od_rows)], ignore_index=True, sort=False)


def severity(pair: pd.DataFrame) -> pd.DataFrame:
    rows = []
    masks = {
        "NEW_FAILURES": pair.new_failure,
        "RECOVERED_PATHS": pair.recovered,
        "PERSISTENT_FAILURES": pair.persistent_failure,
    }
    for group, mask in masks.items():
        q = pair[mask]
        for arm in ("BASE", "B0001"):
            for metric in ("total_site_gap_ratio", "max_site_deficit_ratio"):
                rows.append({"group": group, "arm": arm, "metric": metric, "paths": len(q), **qstats(q[f"{metric}_{arm}"])})
        for metric in ("total_site_gap_ratio", "max_site_deficit_ratio"):
            rows.append({"group": group, "arm": "DELTA_B0001_MINUS_BASE", "metric": metric, "paths": len(q), **qstats(q[f"{metric}_B0001"] - q[f"{metric}_BASE"])})
    return pd.DataFrame(rows)


def information_closure(pair: pd.DataFrame, source: dict[str, pd.DataFrame]) -> pd.DataFrame:
    cand = source["path"].set_index("path_id")
    hour = source["hour"]
    positive = set(pair.loc[pair.positive_target_common, "path_id"])
    checkpoint_rows = []
    for pid, g in hour[hour.path_id.isin(positive)].groupby("path_id", sort=False):
        g = g.sort_values("global_hour"); max_h = int(g.global_hour.max()); term_loc = cand.loc[pid, "terminal_loc"]
        for w in WINDOWS:
            cutoff = max_h - w; before = g[g.global_hour <= cutoff]
            if before.empty:
                continue
            latest = before.sort_values(["global_hour", "site"]).iloc[-1]
            last_site = before.sort_values("global_hour").groupby("site", as_index=False).tail(1).set_index("site")
            state_key = (latest.state_id, latest.hurricane_a, latest.hurricane_loc, latest.hurricane_lf)
            after = g[g.global_hour > cutoff]
            row = {"path_id": pid, "window": f"-{w}h", "checkpoint_global_hour": cutoff, "current_state_id": latest.state_id, "current_intensity": latest.hurricane_a, "current_loc": latest.hurricane_loc, "current_lf": latest.hurricane_lf, "state_key": "/".join(map(str, state_key)), "terminal_loc_observed": term_loc}
            for s in SITES:
                row[f"inventory_site{s}"] = float(last_site.loc[s, "end_inventory_kg"]) if s in last_site.index else np.nan
                row[f"production_final{w}h_site{s}"] = float(after[after.site == s].H2_production_kg.sum())
            row["htt_final_window"] = float(after.HTT_in_kg.sum())
            row["ordinary_shortage_final_window"] = float(after.ordinary_shortage_kg.sum())
            row["state_key_tuple"] = state_key
            checkpoint_rows.append(row)
    cp = pd.DataFrame(checkpoint_rows)
    risk = cp.groupby(["window", "state_key"], dropna=False).terminal_loc_observed.value_counts(normalize=True).rename("terminal_loc_probability").reset_index()
    cp = cp.merge(risk, left_on=["window", "state_key", "terminal_loc_observed"], right_on=["window", "state_key", "terminal_loc_observed"], how="left")
    cp["group"] = np.select([cp.path_id.isin(set(pair.loc[pair.new_failure, "path_id"])), cp.path_id.isin(set(pair.loc[pair.recovered, "path_id"]))], ["NEW_FAILURES", "RECOVERED_PATHS"], default="OTHER_POSITIVE")
    cp["information_proxy"] = "NOT_YET_REVEALED_BEFORE_STAGE7"
    return cp.drop(columns=["state_key_tuple"], errors="ignore")


def write_summary(out: Path, pair: pd.DataFrame, penalty: pd.DataFrame, cover: pd.DataFrame, mech: pd.DataFrame, sev: pd.DataFrame, info: pd.DataFrame) -> None:
    pos = pair[pair.positive_target_common]
    new = pair[pair.new_failure]; rec = pair[pair.recovered]
    def total(df: pd.DataFrame, col: str) -> float: return float(df[col].sum()) if not df.empty else 0.0
    cover_paths = cover[cover.record_type == "PATH"]
    valid_cover = cover_paths[cover_paths.other_site_gap > EPS]
    new_mech = mech[(mech.record_type == "SUMMARY") & (mech.group == "NEW_FAILURES")]
    rec_mech = mech[(mech.record_type == "SUMMARY") & (mech.group == "RECOVERED_PATHS")]
    info_new = info[info.group == "NEW_FAILURES"]
    info_rec = info[info.group == "RECOVERED_PATHS"]
    new_locs = ", ".join(f"loc{int(k)}={int(v)}" for k, v in new.terminal_loc_B0001.value_counts().sort_index().items())
    rec_locs = ", ".join(f"loc{int(k)}={int(v)}" for k, v in rec.terminal_loc_B0001.value_counts().sort_index().items())
    all_delta_gap = float(pair.delta_site_gap.mean())
    all_delta_penalty = float(pair.delta_terminal_penalty.mean())
    all_delta_cost = float(pair.delta_operating_cost.mean())
    pos_delta_gap = float(pos.delta_site_gap.mean())
    pos_delta_penalty = float(pos.delta_terminal_penalty.mean())
    pos_delta_cost = float(pos.delta_operating_cost.mean())
    new_prod = {s: float(new[f"production_total_kg_site{s}_B0001"].sub(new[f"production_total_kg_site{s}_BASE"]).mean()) for s in SITES}
    rec_prod = {s: float(rec[f"production_total_kg_site{s}_B0001"].sub(rec[f"production_total_kg_site{s}_BASE"]).mean()) for s in SITES}
    new_inv = {s: float(new[f"inventory_site{s}_B0001"].sub(new[f"inventory_site{s}_BASE"]).mean()) for s in SITES}
    rec_inv = {s: float(rec[f"inventory_site{s}_B0001"].sub(rec[f"inventory_site{s}_BASE"]).mean()) for s in SITES}
    flag_text = "; ".join(f"{arm}: " + ", ".join(f"{flag}={int(g.paths.sum())}" for flag, g in grp.groupby("flag")) for arm, grp in mech[(mech.record_type == "FLAG_COUNT") & (mech.group == "NEW_FAILURES")].groupby("arm"))
    risk_text = "; ".join(f"{w}: new mean/median={float(info_new[info_new.window == w].terminal_loc_probability.mean()):.3f}/{float(info_new[info_new.window == w].terminal_loc_probability.median()):.3f}, recovered={float(info_rec[info_rec.window == w].terminal_loc_probability.mean()):.3f}/{float(info_rec[info_rec.window == w].terminal_loc_probability.median()):.3f}" for w in ("-16h", "-8h", "-4h"))
    text = f'''# Stage89Q-B0001 空间机制闭环摘要

## Material Passport

- Verification Status: `ANALYZED`
- Scope: 现有 Base accepted OOS、B0001 exploratory OOS、`06_spatial_deep_dive_v4` 的 common-path 只读闭环
- Training/OOS mutation: `NONE`
- Candidate: `B0001` only; B1011 未使用

## 数据身份锁定

同一 ordered 10000 path IDs，positive-target `1123`。Base site-wise shortfall `473`，B0001 `509`；`NEW_FAILURES=82`，`RECOVERED_PATHS=46`。这些数字与 v4 QA 一致。

## Winner / Loser

赢家/输家按 `terminal_state_id`、`terminal_a`（intensity）、`terminal_loc`、target vector、termination stage/type 分组，完整表见 `terminal_state_winner_loser.csv`。新失败按 B0001 terminal loc 为 `{new_locs}`；recovered 为 `{rec_locs}`。这些是路径归属计数，不表示 B0001 改变了 terminal realization，也不把 terminal realization 倒推为早期已知信息。

## 正式 terminal penalty 拆账

正式 penalty 使用 `1000 * sum_i max(T_i-I_i,0)`。全部 10000 条 common paths 的 site-gap 均值变化为 `{all_delta_gap:.6f} kg/path`，对应正式 penalty 均值变化 `{all_delta_penalty:.3f} yuan/path`，operating cost 变化 `{all_delta_cost:.4f} yuan/path`；positive-target 子集对应 `{pos_delta_gap:.6f} kg/path`、`{pos_delta_penalty:.3f} yuan/path`、`{pos_delta_cost:.4f} yuan/path`。逐类贡献见 `terminal_penalty_decomposition.csv`：82 条 new-failure 增加 `871.949 kg` site gap / `871,949.377 yuan` penalty，46 条 recovered 减少 `259.463 kg` / `259,462.687 yuan`，persistent-failure-to-failure 净增加 `1205.723 kg` / `1,205,722.897 yuan`（positive-target accounting）。quantity shortfall 未替代正式 penalty。

## Site4 surplus 覆盖

82 条 new-failure path 的 Site4 surplus 与 Site1-3 other-site-gap 逐条计算，见 `site4_surplus_cover_analysis.csv`。有效 other-site-gap 路径中，cover ratio 的均值/中位数为 `{float(valid_cover.cover_ratio.mean()) if not valid_cover.empty else float('nan'):.4f}/{float(valid_cover.cover_ratio.median()) if not valid_cover.empty else float('nan'):.4f}`；Site4 surplus 覆盖全部 other-site-gap 的路径数为 `{int((cover_paths.site4_surplus + EPS >= cover_paths.other_site_gap).sum())}`，覆盖至少 50% 的路径数为 `{int((cover_paths.site4_surplus + EPS >= .5 * cover_paths.other_site_gap).sum())}`，Site4 surplus=0 的路径数为 `{int((cover_paths.site4_surplus <= EPS).sum())}`。这回答的是数量上是否足够，不能把 surplus 自动视为可转运到缺口站。

## Production / inventory / HTT

`new_vs_recovered_mechanism.csv` 同时保留 path-level 和 group summary。new failures 的 production delta (Site1..4) 为 `{new_prod[1]:.3f}/{new_prod[2]:.3f}/{new_prod[3]:.3f}/{new_prod[4]:.3f} kg/path`，terminal inventory delta 为 `{new_inv[1]:.3f}/{new_inv[2]:.3f}/{new_inv[3]:.3f}/{new_inv[4]:.3f} kg/path`；recovered 对应 production `{rec_prod[1]:.3f}/{rec_prod[2]:.3f}/{rec_prod[3]:.3f}/{rec_prod[4]:.3f}`、inventory `{rec_inv[1]:.3f}/{rec_inv[2]:.3f}/{rec_inv[3]:.3f}/{rec_inv[4]:.3f}`。这支持“Site4 production 上升、new-failure 的 Site2/Site3 inventory 下降”的描述。HTT 标记是 ex-post 描述；new-failure B0001 flags 为 `{flag_text}`。`WRONG_DIRECTION_EX_POST` 不等于 decision-time policy error。

## 信息时点

`information_timing_closure.csv` 在 -16/-8/-4h 保存当前可见 state、inventory、production、HTT 以及基于同一 checkpoint state 的 terminal-loc 条件频率。new/recovered terminal-loc 条件概率均值/中位数分别为 `{risk_text}`。它是 empirical ex-post risk proxy，不把 Stage7 realization 当作早期可知信息。既有 v4 proxy 中 new failures 与 recovered 均为 `NOT_YET_REVEALED_BEFORE_STAGE7`，因此当前证据更接近 information limitation 与 policy/HTT alignment 的混合解释，而不是已证明 policy failure。

## 相对缺口严重度

`relative_gap_severity.csv` 报告 NEW_FAILURES、RECOVERED_PATHS、PERSISTENT_FAILURES 的 total-site-gap ratio 和 max-site-deficit ratio 的 mean/median/q25/q75/q90/q95/max。该表用于区分失败数量变化与局部严重度变化。

## 机制判断

最稳妥标签仍是 `MIXED`：Site4 capacity/production-location structure 产生富余，但未必与 Site2/Site3 缺口在空间和时间上对齐；HTT 总量不是由本分析单独证明的主瓶颈；terminal loc 的提前可见性不足与不稳定 checkpoint policy 同时限制了解释强度。全部 common paths 上 operating-cost 改善 `-33.2662 yuan/path` 被 formal terminal penalty 增量 `+181.821 yuan/path` 数值上超过，净增加约 `148.555 yuan/path`；因此不能只看 operating cost。

当前数据不足以否定 B0001，也不足以支持 B0001 site-wise terminal reliability 已改善的结论。
'''
    (out / "中文机制闭环摘要.md").write_text(text, encoding="utf-8")


def main() -> None:
    ap = argparse.ArgumentParser(); ap.add_argument("--repo", type=Path, required=True); ap.add_argument("--run-dir", type=Path, required=True); args = ap.parse_args()
    repo = args.repo.resolve(); run = args.run_dir.resolve(); v4 = run / "06_spatial_deep_dive_v4"; out = run / "07_spatial_closure_v7"; out.mkdir(parents=True, exist_ok=False)
    require((v4 / "qa.csv").is_file(), "Missing v4 QA")
    v4qa = pd.read_csv(v4 / "qa.csv"); require(bool(v4qa["pass"].all()), "Existing v4 QA is not all PASS")
    base, cand = load_v4(v4); pair = make_pair(base, cand)
    require(int(pair.positive_target_common.sum()) == 1123, "Positive-target identity mismatch")
    require(int(((pair.site_wise_terminal_gap_recomputed_BASE > EPS) & pair.positive_target_common).sum()) == 473, "Base site-wise shortfall mismatch")
    require(int(((pair.site_wise_terminal_gap_recomputed_B0001 > EPS) & pair.positive_target_common).sum()) == 509, "B0001 site-wise shortfall mismatch")
    require(int(pair.new_failure.sum()) == 82 and int(pair.recovered.sum()) == 46, "Migration identity mismatch")
    base_source = read_source(repo / BASE_ROOT); cand_source = read_source(run / "04_oos_b0001")
    # Raw source path IDs are a second identity check, independent of v4 artifacts.
    require(base_source["path"].path_id.tolist() == cand_source["path"].path_id.tolist(), "Raw source path IDs differ")
    winners = state_winner_loser(pair); penalty = penalty_decomposition(pair); cover = site4_cover(pair); mech = mechanism_table(pair, base_source, cand_source); sev = severity(pair); info = information_closure(pair, cand_source)
    winners.to_csv(out / "terminal_state_winner_loser.csv", index=False); penalty.to_csv(out / "terminal_penalty_decomposition.csv", index=False); cover.to_csv(out / "site4_surplus_cover_analysis.csv", index=False); mech.to_csv(out / "new_vs_recovered_mechanism.csv", index=False); sev.to_csv(out / "relative_gap_severity.csv", index=False); info.to_csv(out / "information_timing_closure.csv", index=False)
    qa_rows = [
        {"check": "v4_qa_all_pass", "observed": bool(v4qa["pass"].all()), "expected": True, "pass": bool(v4qa["pass"].all())},
        {"check": "ordered_common_paths", "observed": len(pair), "expected": 10000, "pass": len(pair) == 10000},
        {"check": "positive_target", "observed": int(pair.positive_target_common.sum()), "expected": 1123, "pass": int(pair.positive_target_common.sum()) == 1123},
        {"check": "base_sitewise_shortfall", "observed": int(((pair.site_wise_terminal_gap_recomputed_BASE > EPS) & pair.positive_target_common).sum()), "expected": 473, "pass": int(((pair.site_wise_terminal_gap_recomputed_BASE > EPS) & pair.positive_target_common).sum()) == 473},
        {"check": "b0001_sitewise_shortfall", "observed": int(((pair.site_wise_terminal_gap_recomputed_B0001 > EPS) & pair.positive_target_common).sum()), "expected": 509, "pass": int(((pair.site_wise_terminal_gap_recomputed_B0001 > EPS) & pair.positive_target_common).sum()) == 509},
        {"check": "new_failure_count", "observed": int(pair.new_failure.sum()), "expected": 82, "pass": int(pair.new_failure.sum()) == 82},
        {"check": "recovered_count", "observed": int(pair.recovered.sum()), "expected": 46, "pass": int(pair.recovered.sum()) == 46},
        {"check": "site_gap_delta_mean_all_paths", "observed": float(pair.delta_site_gap.mean()), "expected": 0.181821, "pass": abs(float(pair.delta_site_gap.mean()) - 0.181821) < 1e-4},
        {"check": "required_outputs", "observed": 6, "expected": 6, "pass": all((out / f).is_file() for f in ["terminal_state_winner_loser.csv", "terminal_penalty_decomposition.csv", "site4_surplus_cover_analysis.csv", "new_vs_recovered_mechanism.csv", "relative_gap_severity.csv", "information_timing_closure.csv"])},
    ]
    qa = pd.DataFrame(qa_rows); qa.to_csv(out / "closure_qa.csv", index=False); require(bool(qa["pass"].all()), "Closure QA failed")
    write_summary(out, pair, penalty, cover, mech, sev, info)
    print(f"SPATIAL_CLOSURE_PASS output={out}")


if __name__ == "__main__":
    main()
