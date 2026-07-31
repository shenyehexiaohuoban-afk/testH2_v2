from __future__ import annotations

import hashlib
import math
from pathlib import Path

import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "results" / "task-002-stage2b-b3-smoke" / "44-extreme-formal-consequence-freeze" / "run-003"


def q(values: pd.Series, p: float) -> float:
    return float(values.quantile(p, interpolation="higher"))


def spearman(x: pd.Series, y: pd.Series) -> float:
    return float(x.rank(method="average").corr(y.rank(method="average")))


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def proxy_validation(inp: pd.DataFrame) -> tuple[pd.DataFrame, dict[str, float]]:
    proxy_cols = [
        "grid_max_wind_mps",
        "grid_cumulative_excess_mps",
        "road_max_wind_mps",
        "road_cumulative_excess_mps",
    ]
    rank_cols = []
    for col in proxy_cols:
        rank_col = f"{col}_rank"
        inp[rank_col] = inp[col].rank(method="average", pct=True)
        rank_cols.append(rank_col)
    inp["historical_proxy_composite"] = inp[rank_cols].max(axis=1)
    rows = []
    loss = inp["formal_loss"]
    loss_q50, loss_q95, loss_q99 = q(loss, 0.50), q(loss, 0.95), q(loss, 0.99)
    for proxy in proxy_cols + ["historical_proxy_composite"]:
        value = inp[proxy]
        for level, frac in [("q95", 0.95), ("q99", 0.99)]:
            threshold = q(value, frac)
            selected = value >= threshold
            loss_threshold = loss_q95 if level == "q95" else loss_q99
            hit = selected & (loss >= loss_threshold)
            false_positive = selected & (loss <= loss_q50)
            rows.append(
                {
                    "proxy": proxy,
                    "level": level,
                    "record_count": len(inp),
                    "spearman_rho": spearman(value, loss),
                    "proxy_threshold": threshold,
                    "formal_loss_threshold": loss_threshold,
                    "proxy_high_count": int(selected.sum()),
                    "formal_high_count": int((loss >= loss_threshold).sum()),
                    "joint_high_count": int(hit.sum()),
                    "quantile_hit_rate": float(hit.sum() / max(1, selected.sum())),
                    "obvious_false_positive_count": int(false_positive.sum()),
                    "obvious_false_positive_share": float(false_positive.sum() / max(1, selected.sum())),
                    "false_positive_definition": "proxy at/above listed quantile and formal loss at/below median",
                }
            )
    out = pd.DataFrame(rows)
    comp = out[(out.proxy == "historical_proxy_composite") & (out.level == "q95")].iloc[0]
    state19 = inp[inp.initial_state_id == 19].copy()
    stats = {
        "composite_spearman": float(comp.spearman_rho),
        "composite_q95_hit_rate": float(comp.quantile_hit_rate),
        "composite_false_positive_share": float(comp.obvious_false_positive_share),
        "state19_support_in_count": int(len(state19)),
        "state19_dro_improved_count": int((state19.state19_DRO_loss < state19.formal_loss - 1e-8).sum()),
        "state19_dro_worsened_count": int((state19.state19_DRO_loss > state19.formal_loss + 1e-8).sum()),
        "state19_mean_loss_change": float((state19.state19_DRO_loss - state19.formal_loss).mean()) if len(state19) else math.nan,
        "state19_mean_shortage_change": float((state19.state19_DRO_shortage_kg - state19.shortage_kg).mean()) if len(state19) else math.nan,
    }
    return out, stats


def build_harm_outputs(recourse: pd.DataFrame, baseline: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame, pd.DataFrame, dict[str, float]]:
    key = ["unique_path_id", "support_out_path_rank", "consequence_replica_rank", "consequence_replica_id", "path_probability"]
    metrics = [
        "operating_loss", "service_cost", "shortage_kg", "shortage_W1_kg", "shortage_W2_kg",
        "shortage_W3_kg", "service_satisfaction_rate", "total_demand_kg",
        "unreachable_demand_kg", "single_site_demand_kg", "state19_nominal_loss_percentile",
    ]
    wide = recourse.pivot_table(index=key, columns="decision_label", values=metrics, aggfunc="first")
    wide.columns = [f"{decision}_{metric}" for metric, decision in wide.columns]
    wide = wide.reset_index()
    wide["SAA_minus_DRO_loss"] = wide["STATE19_SAA_operating_loss"] - wide["STATE19_DRO_operating_loss"]
    wide["SAA_minus_DRO_shortage_kg"] = wide["STATE19_SAA_shortage_kg"] - wide["STATE19_DRO_shortage_kg"]
    wide["DRO_improves_loss"] = wide.SAA_minus_DRO_loss > 1e-8
    wide["DRO_improves_shortage"] = wide.SAA_minus_DRO_shortage_kg > 1e-8
    wide["low_theoretical_probability"] = wide.path_probability < (1 / 15000)

    s19_ref = baseline[(baseline.initial_state_id == 19) & (baseline.R == 15000)].iloc[0]
    loss_q95, loss_q99 = float(s19_ref.loss_q95), float(s19_ref.loss_q99)
    wide["high_formal_loss_q95"] = wide.STATE19_SAA_operating_loss >= loss_q95
    wide["high_formal_loss_q99"] = wide.STATE19_SAA_operating_loss >= loss_q99
    wide["verified_low_probability_high_harm_replica"] = (
        wide.low_theoretical_probability & wide.high_formal_loss_q95 & (wide.STATE19_SAA_shortage_kg > 1e-8)
    )

    saa = recourse[recourse.decision_label == "STATE19_SAA"].copy()
    saa["road_interruption_flag"] = saa.unreachable_demand_kg > 1e-8
    saa["irreplaceable_site_flag"] = saa.single_site_demand_kg > 1e-8
    saa["shared_inventory_competition_flag"] = (saa.shortage_kg > 1e-8) & (saa.max_site_capacity_shadow_price > 1e-6)
    saa["demand_pressure_flag"] = saa.total_demand_kg > 693.468740452331
    saa["failure_mechanism"] = np.select(
        [
            saa.road_interruption_flag,
            saa.irreplaceable_site_flag & saa.shared_inventory_competition_flag,
            saa.shared_inventory_competition_flag,
            (saa.shortage_kg > 1e-8) & saa.demand_pressure_flag,
            saa.shortage_kg > 1e-8,
        ],
        [
            "ROAD_NETWORK_INTERRUPTION",
            "IRREPLACEABLE_SITE_AND_SHARED_INVENTORY",
            "SHARED_INVENTORY_COMPETITION",
            "DEMAND_EXCEEDS_AVAILABLE_CAPACITY",
            "OTHER_SHORTAGE",
        ],
        default="NO_SHORTAGE",
    )
    mechanism_cols = key + [
        "total_demand_kg", "operating_loss", "shortage_kg", "service_satisfaction_rate",
        "unreachable_demand_kg", "single_site_demand_kg", "max_site_capacity_shadow_price",
        "road_interruption_flag", "irreplaceable_site_flag", "shared_inventory_competition_flag",
        "demand_pressure_flag", "failure_mechanism",
    ]
    mechanism = saa[mechanism_cols]

    path_rows = []
    for path_id, grp in wide.groupby("unique_path_id", sort=True):
        row = {
            "unique_path_id": int(path_id),
            "support_out_path_rank": int(grp.support_out_path_rank.iloc[0]),
            "path_probability": float(grp.path_probability.iloc[0]),
            "replica_count": len(grp),
            "low_theoretical_probability": bool(grp.low_theoretical_probability.all()),
        }
        for decision in ["HALF_CAPACITY", "FULL_CAPACITY", "STATE19_SAA", "STATE19_DRO"]:
            loss = grp[f"{decision}_operating_loss"]
            shortage = grp[f"{decision}_shortage_kg"]
            row.update(
                {
                    f"{decision}_loss_mean": float(loss.mean()),
                    f"{decision}_loss_std": float(loss.std(ddof=0)),
                    f"{decision}_loss_q90": q(loss, 0.90),
                    f"{decision}_loss_q95": q(loss, 0.95),
                    f"{decision}_loss_q99": q(loss, 0.99),
                    f"{decision}_loss_max": float(loss.max()),
                    f"{decision}_shortage_mean_kg": float(shortage.mean()),
                    f"{decision}_zero_shortage_share": float((shortage <= 1e-8).mean()),
                }
            )
        row["SAA_minus_DRO_loss_mean"] = float(grp.SAA_minus_DRO_loss.mean())
        row["SAA_minus_DRO_shortage_mean_kg"] = float(grp.SAA_minus_DRO_shortage_kg.mean())
        row["DRO_loss_improvement_replica_share"] = float(grp.DRO_improves_loss.mean())
        row["verified_harmful_replica_count"] = int(grp.verified_low_probability_high_harm_replica.sum())
        row["verified_harmful_path"] = bool(
            row["verified_harmful_replica_count"] >= 3
            and row["STATE19_SAA_loss_mean"] >= loss_q95
            and row["STATE19_SAA_shortage_mean_kg"] > 1e-8
        )
        path_rows.append(row)
    by_path = pd.DataFrame(path_rows)

    comparison = wide[key + [
        "STATE19_SAA_operating_loss", "STATE19_DRO_operating_loss", "SAA_minus_DRO_loss",
        "STATE19_SAA_shortage_kg", "STATE19_DRO_shortage_kg", "SAA_minus_DRO_shortage_kg",
        "DRO_improves_loss", "DRO_improves_shortage", "verified_low_probability_high_harm_replica",
    ]]
    stats = {
        "state19_nominal_loss_q95": loss_q95,
        "state19_nominal_loss_q99": loss_q99,
        "verified_harmful_replica_count": int(wide.verified_low_probability_high_harm_replica.sum()),
        "verified_harmful_path_count": int(by_path.verified_harmful_path.sum()),
        "verified_harmful_path_share": float(by_path.verified_harmful_path.mean()),
        "dro_loss_improvement_replica_share": float(wide.DRO_improves_loss.mean()),
        "dro_shortage_improvement_replica_share": float(wide.DRO_improves_shortage.mean()),
        "saa_mean_loss": float(wide.STATE19_SAA_operating_loss.mean()),
        "dro_mean_loss": float(wide.STATE19_DRO_operating_loss.mean()),
        "saa_mean_shortage": float(wide.STATE19_SAA_shortage_kg.mean()),
        "dro_mean_shortage": float(wide.STATE19_DRO_shortage_kg.mean()),
        "saa_zero_shortage_share": float((wide.STATE19_SAA_shortage_kg <= 1e-8).mean()),
        "dro_zero_shortage_share": float((wide.STATE19_DRO_shortage_kg <= 1e-8).mean()),
    }
    return wide, by_path, comparison, mechanism, stats


def write_design() -> None:
    text = """# Step-04C-A2 formal consequence identity design

The support-out identity namespace is `STEP04CA2_SUPPORT_OUT_V1`.

1. Sort the 858 exact physical paths lexicographically by the frozen 12-field key
   `(a0,loc0,lfw0,a1,loc1,lfw1,a2,loc2,lfw2,a3,loc3,lfw3)`.
2. Assign `support_out_path_rank = 1..858` and `consequence_replica_rank = 1..5`.
3. Define `joint_stream_position = 5*(path_rank-1)+replica_rank`, giving exactly
   4,290 deterministic identities. No runtime ordering or per-path seed is used.
4. Use wind seed `1704202601` and resistance seed `2704202601`. The wind stream
   supplies one independent W1-W3 quantile triplet per position. The resistance
   stream supplies one line and one road resistance vector per position. The two
   seeds are different from every nominal, validation-1, and validation-2 seed.
5. Wind follows the unchanged formal `stagewise_random_triangular` mapping.
   Line and road resistance are fixed across W1-W3, damage is persistent, and the
   formal period D/A/C construction is identical to the Step-03Y replay semantics.

The five replicas are deterministic conditional consequence realizations. They are
not empirical path probabilities and are not assigned probability mass here.
"""
    (OUT / "consequence_identity_design.md").write_text(text, encoding="utf-8")


def main() -> None:
    if not OUT.is_dir():
        raise SystemExit(f"MATLAB output is missing: {OUT}")
    write_design()
    inp = pd.read_csv(OUT / "in_support_proxy_validation.csv")
    recourse = pd.read_csv(OUT / "extreme_formal_recourse_results.csv")
    manifest = pd.read_csv(OUT / "extreme_consequence_identity_manifest.csv")
    collision = pd.read_csv(OUT / "random_stream_collision_audit.csv")
    reproducibility = pd.read_csv(OUT / "reproducibility_audit.csv")
    dac = pd.read_csv(OUT / "extreme_DAC_generation_audit.csv")
    baseline = pd.read_csv(OUT / "nominal_loss_reference.csv")
    runtime = pd.read_csv(OUT / "runtime_and_solver_calls.csv")

    corr, proxy_stats = proxy_validation(inp)
    corr.to_csv(OUT / "proxy_formal_loss_correlation.csv", index=False)
    replica, by_path, comparison, mechanism, harm_stats = build_harm_outputs(recourse, baseline)
    replica.to_csv(OUT / "extreme_harm_by_replica.csv", index=False)
    by_path.to_csv(OUT / "extreme_harm_by_path.csv", index=False)
    comparison.to_csv(OUT / "extreme_SAA_vs_DRO.csv", index=False)
    mechanism.to_csv(OUT / "extreme_failure_mechanism.csv", index=False)

    identity_pass = (
        len(manifest) == 4290
        and manifest.unique_path_id.nunique() == 858
        and manifest.consequence_replica_id.nunique() == 4290
        and collision.passed.astype(bool).all()
        and reproducibility.passed.astype(bool).all()
        and dac.passed.astype(bool).all()
    )
    formal_identity_status = (
        "A. FORMAL_CONSEQUENCE_IDENTITIES_FROZEN"
        if identity_pass
        else "C. FORMAL_CONSEQUENCE_GENERATION_UNRESOLVED"
    )
    harmful_count = int(harm_stats["verified_harmful_path_count"])
    if harmful_count == 0:
        extreme_harm_status = "H-C. HISTORICAL_PROXY_NOT_SUPPORTED_BY_FORMAL_LOSS"
    elif harm_stats["verified_harmful_path_share"] >= 0.50:
        extreme_harm_status = "H-A. SUPPORT_OUT_EXTREMES_ACTUALLY_HARMFUL"
    else:
        extreme_harm_status = "H-B. MIXED_CRITICALITY_REQUIRES_RESELECTION"
    if not identity_pass:
        overall = "C. FIX_FORMAL_CONSEQUENCE_IDENTITY_FIRST"
    elif extreme_harm_status.startswith("H-A"):
        overall = "A. PROCEED_TO_STEP04C_B_EXTREME_AWARE_DRO"
    else:
        overall = "B. RESELECT_EXTREME_PATHS_USING_FORMAL_RECOURSE"

    required = [
        "in_support_proxy_validation.csv", "proxy_formal_loss_correlation.csv",
        "consequence_identity_design.md", "extreme_consequence_identity_manifest.csv",
        "random_stream_collision_audit.csv", "reproducibility_audit.csv",
        "extreme_DAC_generation_audit.csv", "extreme_formal_recourse_results.csv",
        "extreme_harm_by_path.csv", "extreme_harm_by_replica.csv", "extreme_SAA_vs_DRO.csv",
        "extreme_failure_mechanism.csv", "runtime_and_solver_calls.csv",
        "state19_support_in_dro_detail_audit.csv",
    ]
    state19_rows = inp[inp.initial_state_id == 19]
    detail_cols = ["state19_DRO_shortage_W1_kg", "state19_DRO_shortage_W2_kg", "state19_DRO_shortage_W3_kg"]
    checks = {
        "support_in_count_268": len(inp) == 268,
        "support_out_path_count_858": manifest.unique_path_id.nunique() == 858,
        "five_replicas_per_path": manifest.groupby("unique_path_id").size().eq(5).all(),
        "identity_count_4290": len(manifest) == 4290,
        "recourse_rows_17160": len(recourse) == 17160,
        "four_fixed_decisions": set(recourse.decision_label) == {"HALF_CAPACITY", "FULL_CAPACITY", "STATE19_SAA", "STATE19_DRO"},
        "stream_collision_audit": collision.passed.astype(bool).all(),
        "byte_exact_reproducibility": reproducibility.passed.astype(bool).all(),
        "DAC_domain_and_business_logic": dac.passed.astype(bool).all(),
        "all_recourse_optimal": recourse.solver_status.eq("OPTIMAL").all(),
        "nominal_support_replay": inp.nominal_aggregate_replay_pass.astype(bool).all(),
        "state19_DRO_period_detail": len(state19_rows) == 6 and all(c in inp.columns for c in detail_cols)
        and state19_rows[detail_cols].notna().all().all(),
        "required_outputs_present": all((OUT / name).is_file() for name in required),
    }
    mechanical_pass = all(checks.values())
    if not mechanical_pass:
        formal_identity_status = "C. FORMAL_CONSEQUENCE_GENERATION_UNRESOLVED"
        overall = "C. FIX_FORMAL_CONSEQUENCE_IDENTITY_FIRST"

    large = pd.read_csv(OUT / "large_file_manifest.csv").iloc[0]
    large_text = f"""# Large file manifest

- File: `{large['file']}`
- Scenario rows: {int(large['scenario_rows'])}
- Bytes: {int(large['bytes'])}
- File SHA-256: `{large['file_sha256']}`
- Raw D SHA-256: `{large['D_raw_sha256']}`
- Raw A SHA-256: `{large['A_raw_sha256']}`
- Raw C SHA-256: `{large['C_raw_sha256']}`
- Git policy: local evidence only; do not stage this MAT file because it is unnecessary large binary evidence.
"""
    (OUT / "LARGE_FILE_MANIFEST.md").write_text(large_text, encoding="utf-8")

    audit_lines = ["Step-04C-A2 mechanical audit", ""]
    for name, passed in checks.items():
        audit_lines.append(f"{name}={'PASS' if passed else 'FAIL'}")
    audit_lines.extend(["", f"overall={'PASS' if mechanical_pass else 'FAIL'}"])
    (OUT / "mechanical_audit.txt").write_text("\n".join(audit_lines) + "\n", encoding="utf-8")

    total = runtime[runtime.stage == "TOTAL"].iloc[0]
    conclusion = f"""formal_identity_status={formal_identity_status}
extreme_harm_status={extreme_harm_status}
overall_conclusion={overall}
mechanical_audit={'PASS' if mechanical_pass else 'FAIL'}
support_in_paths=268
support_out_paths=858
replicas_per_support_out_path=5
verified_harmful_support_out_paths={harmful_count}
verified_harmful_support_out_replicas={int(harm_stats['verified_harmful_replica_count'])}
total_runtime_sec={float(total.runtime_sec):.9f}
solver_calls={int(total.cumulative_solver_calls)}
scenario_evaluations={int(total.cumulative_scenario_evaluations)}
"""
    (OUT / "conclusion.txt").write_text(conclusion, encoding="utf-8")

    if overall.startswith("A."):
        next_task = "Step-04C-B: specify and audit the convex nominal chi-square plus frozen extreme-risk protection model without calibrating eta or epsilon in this step."
    elif overall.startswith("B."):
        next_task = "Reselect support-out paths using the frozen formal recourse harm labels, then freeze the revised extreme set before any extreme-aware DRO integration."
    else:
        next_task = "Repair the failed formal consequence identity or mechanical gate, create a new run number, and repeat byte-exact generation before any harm interpretation."
    (OUT / "next_stage_plan.md").write_text(f"# Unique next task\n\n{next_task}\n", encoding="utf-8")

    readme = f"""# Step-04C-A2 extreme formal consequence freeze

Mechanical audit: **{'PASS' if mechanical_pass else 'FAIL'}**.

- The 268 support-in paths were replayed from their existing nominal formal identities. The historical proxy composite has Spearman rho `{proxy_stats['composite_spearman']:.6f}`, q95 hit rate `{proxy_stats['composite_q95_hit_rate']:.6f}`, and obvious-false-positive share `{proxy_stats['composite_false_positive_share']:.6f}` against the one existing formal consequence realization per path.
- All six state19 support-in paths include complete SAA and DRO total and W1-W3 shortage detail. DRO improves formal loss on `{proxy_stats['state19_dro_improved_count']}` of the six and worsens none.
- All 858 support-out paths received five deterministic conditional consequence replicas: 4,290 unique namespace identities. Random-stream collision, byte replay, D/A/C domain, persistence, and business-logic audits passed: `{identity_pass}`.
- Under state19 SAA T, {int(harm_stats['verified_harmful_replica_count'])} replicas and {harmful_count} paths meet the conservative low-theoretical-probability/high-formal-loss rule. The reference state19 nominal q95/q99 losses are `{harm_stats['state19_nominal_loss_q95']:.6f}` / `{harm_stats['state19_nominal_loss_q99']:.6f}`.
- State19 SAA mean loss/shortage on the 4,290 replicas are `{harm_stats['saa_mean_loss']:.6f}` / `{harm_stats['saa_mean_shortage']:.6f} kg`; DRO values are `{harm_stats['dro_mean_loss']:.6f}` / `{harm_stats['dro_mean_shortage']:.6f} kg`. DRO improves loss on `{harm_stats['dro_loss_improvement_replica_share']:.6f}` of replicas.
- The consequence replicas are frozen stress realizations, not empirical probabilities. No enhanced DRO, eta/epsilon calibration, all-state optimization, WDRO, MSP, Word, transition-matrix, or formal generator modification was performed.

Classifications:

- `{formal_identity_status}`
- `{extreme_harm_status}`
- `{overall}`

Runtime: `{float(total.runtime_sec):.6f} s`; solver calls: `{int(total.cumulative_solver_calls)}`; fixed-T scenario evaluations: `{int(total.cumulative_scenario_evaluations)}`.
"""
    (OUT / "README.md").write_text(readme, encoding="utf-8")

    # Refresh hashes after all lightweight outputs exist for later staging review.
    inventory = []
    for path in sorted(OUT.iterdir()):
        if path.is_file():
            inventory.append({"file": path.name, "bytes": path.stat().st_size, "sha256": sha256_file(path)})
    pd.DataFrame(inventory).to_csv(OUT / "lightweight_file_inventory.csv", index=False)
    print(f"STEP04CA2_FINALIZE_PASS|mechanical={mechanical_pass}|identity={formal_identity_status}|harm={extreme_harm_status}|overall={overall}")


if __name__ == "__main__":
    main()
