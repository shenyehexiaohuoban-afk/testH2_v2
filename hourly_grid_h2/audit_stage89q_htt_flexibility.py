#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Independent raw-based QA for the Stage89Q HTT flexibility audit."""

from __future__ import annotations

import ast
import hashlib
import os
from pathlib import Path

import numpy as np
import pandas as pd
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
RUN = ROOT / "results/task-002-stage2b-b3-smoke/stage89q-penalty1000-vs1500-long-training/run-003"
RAW = ROOT / "hourly_grid_h2/output/stage89q_penalty1000_vs1500_long_training/run-003/penalty1000"
OUT = RUN / "05_analysis/10_deep_penalty1000/16_htt_flexibility_audit"
FIG = RUN / "06_figures/10_penalty1000_htt_flexibility_audit"
EXPECTED = {
    "path_summary/oos_path_summary.csv": "99ec55faba4e60e88b25d757deb1a8146515faf666d52979fe69c64362047502",
    "path_summary/oos_stage_summary.csv": "969c373a9a2ff1b271cde6fda95a6fe8e64b10362518fe4b807c0dc86437c15d",
    "path_summary/oos_stage_site_summary.csv": "eab41bdf5d58fc971bc65af8c5745de3bd08cc25a0a4d44cc386aeba3f99c89e",
    "hourly_site/oos_hour_site.csv": "af3b3d5c4aa69e6d29b35a88008b4d82360c4b8391fc783141078f7ad68b0cda",
    "grid_hourly/oos_hour_system.csv": "b9eaa83ee3e8a720f3cb5afd5d54da050c2d3ef45c434efe74f8ba8b976b63c6",
    "htt_od/oos_positive_htt_flows.csv": "06a6586574a155eb4588cae691898b3ebda509a79e14e64c8453918b7262fe4a",
}
TOL = 1e-7


def io_path(path: Path) -> str:
    resolved = str(path.resolve())
    return f"\\\\?\\{resolved}" if os.name == "nt" and not resolved.startswith("\\\\?\\") else resolved


def dotted_name(node: ast.AST) -> str:
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        prefix = dotted_name(node.value)
        return f"{prefix}.{node.attr}" if prefix else node.attr
    return ""


def forbidden_capability_references(path: Path) -> list[str]:
    tree = ast.parse(path.read_text(encoding="utf-8"))
    references = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            references.extend(alias.name for alias in node.names)
        elif isinstance(node, ast.ImportFrom):
            references.append(node.module or "")
        elif isinstance(node, ast.Call):
            references.append(dotted_name(node.func))
    prefixes = ("scipy.optimize", "gurobipy", "cvxpy", "pulp", "np.random", "numpy.random", "random.")
    return sorted({name for name in references if name == "random" or name.startswith(prefixes)})


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with open(io_path(path), "rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> None:
    before = {name: sha256(RAW / name) for name in EXPECTED}
    path = pd.read_csv(RAW / "path_summary/oos_path_summary.csv")
    hour = pd.read_csv(RAW / "hourly_site/oos_hour_site.csv")
    system = pd.read_csv(RAW / "grid_hourly/oos_hour_system.csv")
    flow = pd.read_csv(RAW / "htt_od/oos_positive_htt_flows.csv")
    physical = pd.read_csv(OUT / "02_physical_limits/htt_physical_limit_by_path_time.csv")
    upper = pd.read_csv(OUT / "03_capacity_upper_bound/current_vs_infinite_htt_upper_bound_summary.csv")
    sens = pd.read_csv(OUT / "04_cap_sensitivity/htt_cap_upper_bound_sensitivity.csv")
    alignment = pd.read_csv(OUT / "05_information_alignment/htt_alignment_expost_vs_information_proxy.csv")
    proxy = pd.read_csv(OUT / "05_information_alignment/information_state_terminal_target_proxy.csv")
    under = pd.read_csv(OUT / "06_underdispatch/underdispatch_reclassification.csv")
    under_summary = pd.read_csv(OUT / "06_underdispatch/underdispatch_summary.csv")
    od = pd.read_csv(OUT / "07_od_structure/htt_od_flow_summary.csv")
    flex = pd.read_csv(io_path(OUT / "08_temporal_vs_spatial_flexibility/flexibility_bottleneck_classification.csv"))
    util = pd.read_csv(OUT / "10_summary/htt_aggregate_utilization_summary.csv")
    util_rel = pd.read_csv(OUT / "10_summary/htt_aggregate_utilization_by_relative_hour.csv")
    visual = pd.read_csv(OUT / "11_qa/visual_audit.csv")
    readme = (OUT / "10_summary/README.md").read_text(encoding="utf-8")
    manifest = pd.read_csv(OUT / "10_summary/lightweight_manifest.csv")
    rows = []

    def check(name, observed, expected, passed, tolerance="exact"):
        rows.append({"check": name, "observed": observed, "expected": expected,
                     "tolerance": tolerance, "pass": bool(passed)})

    check("accepted_raw_hashes", before, EXPECTED, before == EXPECTED)
    s7 = path[path.reached_stage7.eq(1)]
    positive = s7[s7.target_total > TOL]
    failed = positive[positive.terminal_site_gap > TOL]
    check("path_count", len(path), 10000, len(path) == 10000)
    check("stage7_count", len(s7), 6124, len(s7) == 6124)
    check("positive_target_partition", f"{len(positive)-len(failed)}+{len(failed)}", "650+473",
          len(positive) == 1123 and len(failed) == 473)
    counts = failed.terminal_gap_class.value_counts().to_dict()
    check("shortfall_partition", counts, "118/203/152",
          counts.get("PURE_QUANTITY_SHORTFALL") == 118 and counts.get("PURE_SPATIAL_MISMATCH") == 203 and
          counts.get("MIXED_QUANTITY_AND_SPATIAL") == 152)
    pre = np.abs(hour.inventory_before_HTT_kg - hour.begin_inventory_kg - hour.H2_production_kg + hour.ordinary_served_kg).max()
    end = np.abs(hour.end_inventory_kg - hour.inventory_before_HTT_kg - hour.HTT_in_kg + hour.HTT_out_kg).max()
    check("hourly_pre_inventory_balance", pre, f"<={TOL}", pre <= TOL, TOL)
    check("hourly_end_inventory_balance", end, f"<={TOL}", end <= TOL, TOL)
    check("hourly_HTT_capacity", (system.total_HTT_kg-system.fleet_capacity_kg).max(), f"<={TOL}",
          (system.total_HTT_kg-system.fleet_capacity_kg).max() <= TOL, TOL)
    check("no_zero_padding", len(system), int((8*path.operating_stage_count).sum()),
          len(system) == int((8*path.operating_stage_count).sum()))
    all_util = util[util.group.eq("all_paths")].iloc[0]
    check("utilization_hour_count", int(all_util.real_hour_count), len(system), int(all_util.real_hour_count) == len(system))
    check("utilization_mean", all_util.mean_utilization, system.fleet_utilization.mean(),
          abs(all_util.mean_utilization-system.fleet_utilization.mean()) <= 1e-12, "1e-12")
    check("relative_hour_rows", len(util_rel), 10*6, len(util_rel) == 60)
    check("physical_row_count", len(physical), 355*3, len(physical) == 355*3)
    check("physical_path_types", set(physical.path_type), {"pure_location", "mixed"},
          set(physical.path_type) == {"pure_location", "mixed"})
    check("physical_valid_counts_explicit", physical.groupby("relative_hour").valid.sum().to_dict(), "reported",
          set(physical.relative_hour) == {-16, -8, -4})
    current = physical[physical.valid].groupby(["path_type", "relative_hour"]).optimistic_recoverable_flag.sum().astype(int)
    upper_current = upper.set_index(["path_type", "relative_hour"]).current_cap_potentially_recoverable_count.astype(int)
    check("upper_summary_current_recompute", current.to_dict(), upper_current.to_dict(), current.equals(upper_current))
    multiplier_order = [1.0, 1.25, 1.5, 2.0, float("inf")]
    sensitivity_monotone = sens.groupby(["path_type", "relative_hour"]).apply(
        lambda g: g.set_index("HTT_CAP_MULTIPLIER").reindex(multiplier_order).recoverable_count.is_monotonic_increasing).all()
    check("sensitivity_monotone", True, True,
          sensitivity_monotone)
    flow_rows = alignment[alignment.record_type.eq("FLOW")]
    pure_ids = set(path.loc[path.terminal_gap_class.eq("PURE_SPATIAL_MISMATCH"), "path_id"])
    pure_flow = flow_rows[flow_rows.path_id.isin(pure_ids)]
    ratio = pure_flow.ex_post_aligned_kg.sum()/pure_flow.flow_kg.sum()
    check("expost_alignment_29_50", ratio, 0.295032472656, abs(ratio-0.295032472656) <= 1e-12, "1e-12")
    check("proxy_probability_closure", (proxy.probability_sum-1).abs().max(), "<=1e-12",
          (proxy.probability_sum-1).abs().max() <= 1e-12, "1e-12")
    check("proxy_and_expost_columns_separate", True, True,
          {"ex_post_aligned_kg","information_proxy_aligned_kg"}.issubset(flow_rows.columns))
    check("underdispatch_98", len(under), 98, len(under) == 98 and under.path_id.nunique() == 98)
    check("underdispatch_partition", under_summary.path_count.sum(), 98, under_summary.path_count.sum() == 98)
    check("underdispatch_allowed_classes", under.reclassification.nunique(), "nine-class vocabulary",
          set(under.reclassification) <= set(under_summary.reclassification))
    check("od_12_rows", len(od), 12, len(od) == 12)
    check("od_total_flow", od.total_kg.sum(), flow.flow_kg.sum(), abs(od.total_kg.sum()-flow.flow_kg.sum()) <= TOL, TOL)
    check("flexibility_473", len(flex), 473, len(flex) == 473)
    check("readme_20_answers", sum(line.startswith("## ") for line in readme.splitlines()), 21,
          all(f"## {i}." in readme for i in range(1,21)))
    for token in ["HTT_AGGREGATE_CAPACITY_BOTTLENECK", "HTT_TIMING_BOTTLENECK",
                  "HTT_INFORMATION_LIMIT_SIGNAL", "HTT_SPATIAL_VALUE_SIGNAL", "RECOMMEND_HTT_CAPACITY_SENSITIVITY"]:
        check(f"readme_status_{token}", token in readme, True, token in readme)
    pngs = sorted(FIG.glob("*.png"))
    check("figure_count", len(pngs), 13, len(pngs) == 13)
    dimensions = []
    for image_path in pngs:
        with Image.open(image_path) as image:
            dimensions.append(image.width >= 700 and image.height >= 400)
    check("figure_dimensions", all(dimensions), True, all(dimensions))
    check("manual_visual_audit", visual.result.eq("PASS").all(), True,
          len(visual) == 13 and visual.result.eq("PASS").all())
    missing = []
    bad_hash = []
    for row in manifest.itertuples(index=False):
        path_item = Path(row.relative_path)
        if not path_item.is_absolute(): path_item = ROOT / path_item
        if not path_item.is_file(): missing.append(str(path_item))
        elif sha256(path_item) != row.sha256: bad_hash.append(str(path_item))
    check("manifest_paths_exist", len(missing), 0, not missing)
    check("manifest_hashes", len(bad_hash), 0, not bad_hash)
    check("lightweight_outputs", max(x.stat().st_size for x in OUT.rglob("*") if x.is_file()), "<25MiB",
          all(x.stat().st_size < 25*1024*1024 for x in OUT.rglob("*") if x.is_file()))
    forbidden = forbidden_capability_references(ROOT / "hourly_grid_h2/analyze_stage89q_htt_flexibility_audit.py")
    check("no_optimizer_or_random", forbidden, [], not forbidden)
    after = {name: sha256(RAW / name) for name in EXPECTED}
    check("raw_unchanged_during_independent_audit", after, before, after == before)
    qa = pd.DataFrame(rows)
    audit_path = OUT / "11_qa/independent_qa.csv"
    qa.to_csv(audit_path, index=False, encoding="utf-8-sig")
    if not qa["pass"].all():
        raise RuntimeError(qa.loc[~qa["pass"]].to_string(index=False))
    print(f"INDEPENDENT_STAGE89Q_HTT_FLEXIBILITY_AUDIT=PASS checks={len(qa)}")


if __name__ == "__main__":
    main()
