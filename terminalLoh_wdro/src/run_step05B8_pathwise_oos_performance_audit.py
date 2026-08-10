"""Build the Step-05B-8 common-sample pathwise SAA/DRO performance audit."""

from __future__ import annotations

import argparse
import hashlib
import math
import re
from pathlib import Path

import numpy as np
import pandas as pd


TOL = 1.0e-8
Z_975 = 1.959963984540054
EXPECTED_OOS_SHA256 = "6e4ed488423e3cbb838c4a6f8b45019cf4ecf32a82850880399a08aafc7aff85"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def describe_delta(values: pd.Series) -> dict[str, float | int]:
    x = values.dropna().astype(float)
    require(len(x) > 0, "Cannot summarize an empty paired-difference vector.")
    higher = int((x > TOL).sum())
    equal = int((x.abs() <= TOL).sum())
    lower = int((x < -TOL).sum())
    require(higher + equal + lower == len(x), "Delta sign partition failed.")
    return {
        "n": int(len(x)),
        "mean_delta": float(x.mean()),
        "median_delta": float(x.median()),
        "q5_delta": float(x.quantile(0.05)),
        "q25_delta": float(x.quantile(0.25)),
        "q75_delta": float(x.quantile(0.75)),
        "q95_delta": float(x.quantile(0.95)),
        "min_delta": float(x.min()),
        "max_delta": float(x.max()),
        "dro_higher_count": higher,
        "dro_higher_share": higher / len(x),
        "equal_count": equal,
        "equal_share": equal / len(x),
        "dro_lower_count": lower,
        "dro_lower_share": lower / len(x),
    }


def paired_ci(values: pd.Series) -> dict[str, float | int]:
    x = values.dropna().astype(float)
    n = len(x)
    mean = float(x.mean())
    std = float(x.std(ddof=1))
    se = std / math.sqrt(n)
    return {
        "n": int(n),
        "mean_delta": mean,
        "sample_std": std,
        "standard_error": se,
        "critical_value": Z_975,
        "ci95_low": mean - Z_975 * se,
        "ci95_high": mean + Z_975 * se,
        "method": "paired mean difference, normal 1.959964 critical value",
    }


def build_master(source: pd.DataFrame) -> pd.DataFrame:
    require(len(source) == 20000, "Expected 20000 method-path source rows.")
    require(source.path_id.nunique() == 10000, "Expected 10000 unique path IDs.")
    require(source.groupby("method").size().to_dict() == {"chi2_eta003": 10000, "saa": 10000},
            "Expected 10000 SAA and 10000 DRO rows.")
    require(not source.duplicated(["method", "path_id"]).any(), "Duplicate method/path rows found.")

    saa = source[source.method == "saa"].set_index("path_id").sort_index()
    dro = source[source.method == "chi2_eta003"].set_index("path_id").sort_index()
    require(saa.index.equals(dro.index), "SAA/DRO path IDs are not rowwise identical.")
    require(saa.index.to_list() == list(range(1, 10001)), "Path IDs are not exactly 1..10000.")

    for col in ["hit_terminal", "terminal_stage", "terminal_state", "a", "loc", "lf"]:
        require(np.array_equal(saa[col].to_numpy(), dro[col].to_numpy()),
                f"Common-sample identity failed for {col}.")

    out = pd.DataFrame(
        {
            "path_id": saa.index.astype(int),
            "terminal_hit": saa.hit_terminal.astype(int).to_numpy(),
            "terminal_stage": saa.terminal_stage.astype(int).to_numpy(),
            "terminal_state_k": saa.terminal_state.astype(int).to_numpy(),
            "a": saa.a.astype(int).to_numpy(),
            "loc": saa["loc"].astype(int).to_numpy(),
            "lf": saa.lf.astype(int).to_numpy(),
        }
    )
    out["terminal_state"] = (out.a - 2) * 7 + out["loc"]
    out.loc[out.terminal_hit == 0, ["terminal_stage", "terminal_state_k", "terminal_state", "a", "loc", "lf"]] = np.nan
    hit_states = out.loc[out.terminal_hit == 1, "terminal_state"]
    require(hit_states.between(1, 35).all(), "Mapped terminal-state IDs are outside 1..35.")

    simple = {
        "production_amount": "production",
        "htt_amount": "htt",
        "ordinary_shortage": "ordinary_shortage",
        "final_total": "final_inventory",
        "objective_without_terminal_gap": "operating_cost",
        "reported_objective": "reported_objective",
        "terminal_gap_penalty": "terminal_gap_penalty",
    }
    for source_col, name in simple.items():
        out[f"saa_{name}"] = saa[source_col].to_numpy(dtype=float)
        out[f"dro_{name}"] = dro[source_col].to_numpy(dtype=float)
        out[f"delta_{name}"] = out[f"dro_{name}"] - out[f"saa_{name}"]

    for site in range(1, 5):
        out[f"saa_final_site{site}"] = saa[f"final_site{site}"].to_numpy(dtype=float)
        out[f"dro_final_site{site}"] = dro[f"final_site{site}"].to_numpy(dtype=float)
        out[f"delta_final_site{site}"] = out[f"dro_final_site{site}"] - out[f"saa_final_site{site}"]

    hit = out.terminal_hit == 1
    terminal_fields = {
        "target_total": "terminal_loh_target",
        "gap_total": "terminal_gap",
    }
    for source_col, name in terminal_fields.items():
        out[f"saa_{name}"] = saa[source_col].to_numpy(dtype=float)
        out[f"dro_{name}"] = dro[source_col].to_numpy(dtype=float)
        out[f"delta_{name}"] = out[f"dro_{name}"] - out[f"saa_{name}"]
        out.loc[~hit, [f"saa_{name}", f"dro_{name}", f"delta_{name}"]] = np.nan

    require(int(hit.sum()) == 6053, "Terminal-hit count is not 6053.")
    require(float(np.max(np.abs(out.saa_final_inventory - sum(out[f"saa_final_site{i}"] for i in range(1, 5))))) < 1e-9,
            "SAA station-to-total inventory identity failed.")
    require(float(np.max(np.abs(out.dro_final_inventory - sum(out[f"dro_final_site{i}"] for i in range(1, 5))))) < 1e-9,
            "DRO station-to-total inventory identity failed.")
    require(float(np.max(np.abs(out.saa_operating_cost + out.saa_terminal_gap_penalty - out.saa_reported_objective))) < 1e-8,
            "SAA cost split identity failed.")
    require(float(np.max(np.abs(out.dro_operating_cost + out.dro_terminal_gap_penalty - out.dro_reported_objective))) < 1e-8,
            "DRO cost split identity failed.")
    return out


def build_performance_summary(master: pd.DataFrame) -> pd.DataFrame:
    specs = [
        ("production_kg", "all_10000", "saa_production", "dro_production", "delta_production", "DRO increase share"),
        ("htt_kg", "all_10000", "saa_htt", "dro_htt", "delta_htt", "DRO increase share"),
        ("ordinary_shortage_kg", "all_10000", "saa_ordinary_shortage", "dro_ordinary_shortage", "delta_ordinary_shortage", "DRO improvement share"),
        ("final_inventory_kg", "all_10000", "saa_final_inventory", "dro_final_inventory", "delta_final_inventory", "DRO increase share"),
        ("operating_cost_yuan", "all_10000", "saa_operating_cost", "dro_operating_cost", "delta_operating_cost", "DRO increase share"),
        ("reported_objective_yuan", "all_10000", "saa_reported_objective", "dro_reported_objective", "delta_reported_objective", "DRO increase share"),
        ("terminal_gap_kg", "terminal_hit_6053", "saa_terminal_gap", "dro_terminal_gap", "delta_terminal_gap", "DRO improvement share"),
    ]
    rows: list[dict[str, object]] = []
    for metric, scope, saa_col, dro_col, delta_col, direction in specs:
        valid = master[delta_col].notna()
        stats = describe_delta(master.loc[valid, delta_col])
        improve_or_increase_share = (
            stats["dro_lower_share"]
            if metric in {"ordinary_shortage_kg", "terminal_gap_kg"}
            else stats["dro_higher_share"]
        )
        rows.append(
            {
                "metric": metric,
                "scope": scope,
                "saa_mean": float(master.loc[valid, saa_col].mean()),
                "dro_mean": float(master.loc[valid, dro_col].mean()),
                **stats,
                "direction_label": direction,
                "dro_improvement_or_increase_share": improve_or_increase_share,
            }
        )
    return pd.DataFrame(rows)


def build_paired_ci(master: pd.DataFrame) -> pd.DataFrame:
    specs = [
        ("production_kg", "delta_production"),
        ("htt_kg", "delta_htt"),
        ("ordinary_shortage_kg", "delta_ordinary_shortage"),
        ("final_inventory_kg", "delta_final_inventory"),
        ("operating_cost_yuan", "delta_operating_cost"),
        ("reported_objective_yuan", "delta_reported_objective"),
    ]
    return pd.DataFrame([{"metric": metric, **paired_ci(master[col])} for metric, col in specs])


def build_cost_decomposition(repo: Path, master: pd.DataFrame) -> pd.DataFrame:
    source = pd.read_csv(
        repo / "results/task-002-stage2b-b3-smoke/58-main-msp-terminal-gap-mechanism-audit/run-004/objective_component_difference.csv"
    )
    keep = [
        "ordinary_shortage_penalty",
        "production_electricity_and_om",
        "htt_transport_cost",
        "inventory_holding_cost",
        "unresolved_residual",
    ]
    out = source[source.component.isin(keep)][["component", "saa_mean", "eta_mean", "eta_minus_saa"]].copy()
    out = out.rename(columns={"eta_mean": "dro_mean", "eta_minus_saa": "dro_minus_saa"})
    operating_delta = float(master.delta_operating_cost.mean())
    out["share_of_operating_cost_delta"] = out.dro_minus_saa / operating_delta
    total = pd.DataFrame(
        [
            {
                "component": "operating_cost_total_excluding_terminal_gap_penalty",
                "saa_mean": float(master.saa_operating_cost.mean()),
                "dro_mean": float(master.dro_operating_cost.mean()),
                "dro_minus_saa": operating_delta,
                "share_of_operating_cost_delta": 1.0,
            }
        ]
    )
    out = pd.concat([out, total], ignore_index=True)
    require(abs(float(out.iloc[:-1].dro_minus_saa.sum()) - operating_delta) < 1e-8,
            "Operating-cost component deltas do not close.")
    require(abs(float(out.iloc[:-1].saa_mean.sum()) - master.saa_operating_cost.mean()) < 1e-8,
            "SAA operating-cost components do not close.")
    require(abs(float(out.iloc[:-1].dro_mean.sum()) - master.dro_operating_cost.mean()) < 1e-8,
            "DRO operating-cost components do not close.")
    return out


def build_inventory_outputs(repo: Path, master: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    ordered = master.sort_values(["delta_final_inventory", "path_id"], ascending=[False, True]).copy()
    ordered["inventory_gain_rank"] = np.arange(1, len(ordered) + 1)
    ordered["inventory_gain_percentile_from_top"] = ordered.inventory_gain_rank / len(ordered)
    selected = ordered.head(1000).copy()
    selected["gain_band"] = np.select(
        [selected.inventory_gain_rank <= 100, selected.inventory_gain_rank <= 500],
        ["top_1_percent", "top_1_to_5_percent"],
        default="top_5_to_10_percent",
    )

    state_gap = pd.read_csv(
        repo / "results/task-002-stage2b-b3-smoke/64-terminal-loh-all-state-capacity-gap-audit/run-002/all_state_capacity_gap_summary.csv"
    )
    high_gap_states = set(
        state_gap.nlargest(7, "dro_conditional_mean_capacity_gap_kg").state.astype(int)
    )
    selected["high_gap_state_top7_flag"] = (
        selected.terminal_hit.eq(1) & selected.terminal_state.isin(high_gap_states)
    )
    high_cols = [
        "path_id", "inventory_gain_rank", "inventory_gain_percentile_from_top", "gain_band",
        "terminal_hit", "terminal_state", "terminal_state_k", "high_gap_state_top7_flag",
        "delta_final_inventory", "delta_production", "delta_htt", "delta_ordinary_shortage",
        "delta_operating_cost", "saa_ordinary_shortage", "dro_ordinary_shortage",
        "saa_terminal_loh_target", "dro_terminal_loh_target", "delta_terminal_loh_target",
        "saa_terminal_gap", "dro_terminal_gap", "delta_terminal_gap",
    ]
    high_paths = selected[high_cols].sort_values("inventory_gain_rank")

    rows: list[dict[str, object]] = []
    delta = master.delta_final_inventory
    positive = delta > TOL
    exact = delta.abs() <= TOL
    decreased = delta < -TOL
    rows.extend(
        [
            {"group": "all_paths", "path_count": len(master), "path_share": 1.0,
             "mean_delta_inventory_kg": float(delta.mean()), "median_delta_inventory_kg": float(delta.median())},
            {"group": "inventory_increased", "path_count": int(positive.sum()), "path_share": float(positive.mean()),
             "mean_delta_inventory_kg": float(delta[positive].mean()) if positive.any() else np.nan,
             "median_delta_inventory_kg": float(delta[positive].median()) if positive.any() else np.nan},
            {"group": "inventory_equal_solver_tolerance_1e-8", "path_count": int(exact.sum()), "path_share": float(exact.mean()),
             "mean_delta_inventory_kg": float(delta[exact].mean()) if exact.any() else np.nan,
             "median_delta_inventory_kg": float(delta[exact].median()) if exact.any() else np.nan},
            {"group": "inventory_decreased", "path_count": int(decreased.sum()), "path_share": float(decreased.mean()),
             "mean_delta_inventory_kg": float(delta[decreased].mean()) if decreased.any() else np.nan,
             "median_delta_inventory_kg": float(delta[decreased].median()) if decreased.any() else np.nan},
            {"group": "inventory_nearly_unchanged_abs_le_1kg", "path_count": int((delta.abs() <= 1.0).sum()),
             "path_share": float((delta.abs() <= 1.0).mean()),
             "mean_delta_inventory_kg": float(delta[delta.abs() <= 1.0].mean()),
             "median_delta_inventory_kg": float(delta[delta.abs() <= 1.0].median())},
        ]
    )
    total_positive_gain = float(delta[positive].sum())
    for pct, count in [(1, 100), (5, 500), (10, 1000)]:
        sub = ordered.head(count)
        hit_sub = sub[sub.terminal_hit == 1]
        rows.append(
            {
                "group": f"top_{pct}_percent_inventory_gain",
                "path_count": count,
                "path_share": count / len(master),
                "mean_delta_inventory_kg": float(sub.delta_final_inventory.mean()),
                "median_delta_inventory_kg": float(sub.delta_final_inventory.median()),
                "share_of_total_positive_inventory_gain": float(sub.delta_final_inventory.clip(lower=0).sum() / total_positive_gain),
                "terminal_hit_share": float(sub.terminal_hit.mean()),
                "mean_delta_terminal_loh_hit_only_kg": float(hit_sub.delta_terminal_loh_target.mean()) if len(hit_sub) else np.nan,
                "high_gap_state_top7_share_among_hits": float(hit_sub.terminal_state.isin(high_gap_states).mean()) if len(hit_sub) else np.nan,
                "mean_saa_ordinary_shortage_kg": float(sub.saa_ordinary_shortage.mean()),
                "mean_dro_ordinary_shortage_kg": float(sub.dro_ordinary_shortage.mean()),
            }
        )
    return pd.DataFrame(rows), high_paths


def build_terminal_delta(master: pd.DataFrame) -> pd.DataFrame:
    hit = master[master.terminal_hit == 1].copy()
    out = hit[
        [
            "path_id", "terminal_state", "terminal_state_k", "a", "loc", "lf",
            "saa_terminal_loh_target", "dro_terminal_loh_target", "delta_terminal_loh_target",
            "saa_final_inventory", "dro_final_inventory", "delta_final_inventory",
            "saa_terminal_gap", "dro_terminal_gap", "delta_terminal_gap",
            "delta_production", "delta_htt", "delta_ordinary_shortage", "delta_operating_cost",
        ]
    ].copy()
    out["input_output_difference_compression_kg"] = (
        out.delta_terminal_loh_target - out.delta_final_inventory
    )
    return out.sort_values("path_id")


def build_state_summary(master: pd.DataFrame) -> pd.DataFrame:
    working = master.copy()
    working["state_group"] = working.terminal_state.fillna(0).astype(int)
    rows: list[dict[str, object]] = []
    for state, group in working.groupby("state_group"):
        hit = state != 0
        rows.append(
            {
                "terminal_state": int(state),
                "state_label": "NO_TERMINAL_HIT" if state == 0 else f"state{state}",
                "path_count": int(len(group)),
                "path_share_all_10000": len(group) / 10000,
                "mean_delta_production_kg": float(group.delta_production.mean()),
                "mean_delta_htt_kg": float(group.delta_htt.mean()),
                "mean_delta_ordinary_shortage_kg": float(group.delta_ordinary_shortage.mean()),
                "ordinary_shortage_worse_path_count": int((group.delta_ordinary_shortage > TOL).sum()),
                "mean_delta_final_inventory_kg": float(group.delta_final_inventory.mean()),
                "mean_delta_operating_cost_yuan": float(group.delta_operating_cost.mean()),
                "mean_delta_reported_objective_yuan": float(group.delta_reported_objective.mean()),
                "mean_delta_terminal_loh_kg": float(group.delta_terminal_loh_target.mean()) if hit else np.nan,
                "mean_delta_terminal_gap_kg": float(group.delta_terminal_gap.mean()) if hit else np.nan,
                "global_mean_inventory_contribution_kg": float(group.delta_final_inventory.sum() / 10000),
                "global_mean_operating_cost_contribution_yuan": float(group.delta_operating_cost.sum() / 10000),
                "global_mean_shortage_contribution_kg": float(group.delta_ordinary_shortage.sum() / 10000),
            }
        )
    return pd.DataFrame(rows).sort_values("terminal_state")


def write_text_outputs(
    repo: Path,
    out: Path,
    master: pd.DataFrame,
    summary: pd.DataFrame,
    inventory_dist: pd.DataFrame,
    terminal_delta: pd.DataFrame,
    component: pd.DataFrame,
    source_file: Path,
) -> None:
    inv = summary[summary.metric == "final_inventory_kg"].iloc[0]
    prod = summary[summary.metric == "production_kg"].iloc[0]
    htt = summary[summary.metric == "htt_kg"].iloc[0]
    shortage = summary[summary.metric == "ordinary_shortage_kg"].iloc[0]
    op_cost = summary[summary.metric == "operating_cost_yuan"].iloc[0]
    reported = summary[summary.metric == "reported_objective_yuan"].iloc[0]
    terminal_gap = summary[summary.metric == "terminal_gap_kg"].iloc[0]
    positive_inv = inventory_dist[inventory_dist.group == "inventory_increased"].iloc[0]
    equal_inv = inventory_dist[inventory_dist.group == "inventory_equal_solver_tolerance_1e-8"].iloc[0]
    down_inv = inventory_dist[inventory_dist.group == "inventory_decreased"].iloc[0]
    near_inv = inventory_dist[inventory_dist.group == "inventory_nearly_unchanged_abs_le_1kg"].iloc[0]
    top1 = inventory_dist[inventory_dist.group == "top_1_percent_inventory_gain"].iloc[0]
    top5 = inventory_dist[inventory_dist.group == "top_5_percent_inventory_gain"].iloc[0]
    top10 = inventory_dist[inventory_dist.group == "top_10_percent_inventory_gain"].iloc[0]

    mean_delta_t = float(terminal_delta.delta_terminal_loh_target.mean())
    mean_delta_i_hit = float(terminal_delta.delta_final_inventory.mean())
    mean_compression = mean_delta_t - mean_delta_i_hit
    retained_share = mean_delta_i_hit / mean_delta_t if abs(mean_delta_t) > TOL else np.nan
    cost_per_inventory = float(op_cost.mean_delta / inv.mean_delta) if abs(inv.mean_delta) > TOL else np.nan
    top10_paths = master.nlargest(1000, "delta_final_inventory")
    top10_state_counts = top10_paths.loc[top10_paths.terminal_hit == 1, "terminal_state"].value_counts().head(7)
    top10_state_text = ", ".join(f"state{int(state)}={int(count)}" for state, count in top10_state_counts.items())

    common_lines = [
        "Step-05B-8 common OOS pairing audit",
        "",
        "SAA rows: 10000",
        "DRO rows: 10000",
        "Path IDs: exact rowwise identity 1..10000",
        "Terminal-hit identity: PASS (6053 common hits)",
        "Terminal-state/stage identity: PASS",
        "State mapping: terminal_state=(a-2)*7+loc in 1..35; internal MSP k retained separately",
        f"Frozen OOS SHA-256: {sha256_file(repo / 'output_h2/details/h2_OOS.csv')}",
        "eval_h2 random draw scan: no rand/randi/randn/randperm call",
        "Cost identity: reported objective = operating cost + 2000*terminal gap, PASS",
        "No training, resampling, cut generation, or policy solve occurred.",
        "Common-sample pairing PASS: 1",
    ]
    (out / "common_oos_pairing_audit.txt").write_text("\n".join(common_lines) + "\n", encoding="utf-8")

    judgment_lines = [
        "Step-05B-8 judgment",
        "",
        "Common-sample pathwise result",
        f"- Mean production delta DRO-SAA: {prod.mean_delta:+.9f} kg/path.",
        f"- Mean HTT delta: {htt.mean_delta:+.9f} kg/path.",
        f"- Mean final inventory delta: {inv.mean_delta:+.9f} kg/path.",
        f"- Inventory increased/equal/decreased paths: {int(positive_inv.path_count)}/{int(equal_inv.path_count)}/{int(down_inv.path_count)}.",
        f"- Mean increase conditional on inventory increasing: {positive_inv.mean_delta_inventory_kg:.9f} kg.",
        f"- Ordinary-shortage mean delta: {shortage.mean_delta:+.9f} kg/path; DRO lower/equal/higher counts are {int(shortage.dro_lower_count)}/{int(shortage.equal_count)}/{int(shortage.dro_higher_count)}.",
        f"- Mean operating-cost delta excluding terminal gap penalty: {op_cost.mean_delta:+.9f} yuan/path.",
        f"- Mean reported-objective delta: {reported.mean_delta:+.9f} yuan/path; terminal-gap penalty is kept separate.",
        f"- Descriptive mean operating-cost increase per mean additional final-inventory kg: {cost_per_inventory:.9f} yuan/kg.",
        "",
        "Distribution",
        f"- Paths within 1 kg of unchanged inventory: {int(near_inv.path_count)} ({near_inv.path_share:.6%}).",
        f"- Top 1%/5%/10% paths account for {top1.share_of_total_positive_inventory_gain:.6%}/{top5.share_of_total_positive_inventory_gain:.6%}/{top10.share_of_total_positive_inventory_gain:.6%} of positive inventory gain.",
        f"- Their mean inventory gains are {top1.mean_delta_inventory_kg:.9f}/{top5.mean_delta_inventory_kg:.9f}/{top10.mean_delta_inventory_kg:.9f} kg.",
        f"- The top 10% terminal-hit share is {top10.terminal_hit_share:.6%}, but only {top10.high_gap_state_top7_share_among_hits:.6%} of those hits are in the seven largest Step-05B-7 conditional-capacity-gap states.",
        f"- Dominant terminal states inside the top 10% are {top10_state_text}; {int((top10_paths.terminal_hit == 0).sum())} paths do not hit a terminal check.",
        "- This is descriptive association only; terminal-state membership is not a causal explanation.",
        "",
        "TerminalLOH input versus MSP output on 6053 terminal-hit paths",
        f"- Mean TerminalLOH input delta: {mean_delta_t:+.9f} kg.",
        f"- Mean final-inventory output delta: {mean_delta_i_hit:+.9f} kg.",
        f"- Mean input-output difference compression: {mean_compression:.9f} kg; the output difference is descriptively {retained_share:.6%} of the input difference.",
        "- This is not an increment-realization ratio. The compression is consistent with the previously audited combination of pre-existing SAA inventory surplus, production limits, ordinary-service competition, and sequential information.",
        "- Mechanism classification: C, both limited input differences outside terminal-hit paths and material compression within terminal-hit paths matter.",
        "",
        "Bounded paper interpretation",
        "- DRO behaves as a higher-reserve policy with a measurable operating-cost premium, not as a uniformly superior physical-service policy.",
        "- The reserve increase has a mixed distribution: a majority of paths increase, a large minority is essentially unchanged, and the top 10% is material but does not dominate total positive gain.",
        f"- Terminal-gap mean delta on terminal-hit paths is {terminal_gap.mean_delta:+.9f} kg, but terminal gap is a target shortfall rather than W-stage disaster shortage.",
        "- Reported objective cannot be called actual economic cost because it contains the historical 2000 yuan/kg soft TerminalLOH-gap penalty.",
        "- No evidence from this audit justifies changing 200 or 2000.",
    ]
    (out / "step05b8_judgment.txt").write_text("\n".join(judgment_lines) + "\n", encoding="utf-8")

    readme_lines = [
        "# Step-05B-8 pathwise SAA/DRO OOS performance audit",
        "",
        f"Accepted run: `{out.name}`.",
        "",
        "This read-only audit pairs the archived SAA and eta=0.03 DRO policies on the exact same 10000x8 OOS paths. It uses the mechanically verified Step-05B-1 path results; no MATLAB/Gurobi call, training, resampling, cut generation, TerminalLOH change, penalty change, or W-stage evaluation is performed.",
        "",
        "`operating_cost` is the existing reported objective minus `2000 * terminal_gap`. It contains production electricity/O&M, HTT cost, holding cost, and ordinary-shortage penalty. It is a diagnostic comparison of actual modeled operating terms, while the reported objective is retained separately.",
        "",
        "The full 10000-row master table is retained locally and recorded in `LARGE_FILE_MANIFEST.md` when it exceeds the lightweight Git threshold. Summary, confidence-interval, tail, terminal-hit, state-mechanism, and judgment outputs are reviewable results.",
    ]
    (out / "README.md").write_text("\n".join(readme_lines) + "\n", encoding="utf-8")

    manifest_rows = []
    for filename, role, policy in [
        ("pathwise_saa_dro_comparison.csv", "10000-row paired master table", "local-only if large"),
        ("terminal_hit_deltaT_deltaI.csv", "6053-row terminal-hit input/output table", "lightweight result"),
        ("high_inventory_gain_paths.csv", "top 10 percent inventory-gain paths", "lightweight result"),
    ]:
        path = out / filename
        rows = sum(1 for _ in path.open("r", encoding="utf-8")) - 1
        manifest_rows.append((role, filename, rows, path.stat().st_size, sha256_file(path), policy))
    manifest_lines = [
        "# LARGE_FILE_MANIFEST",
        "",
        "| role | file | data rows | bytes | SHA-256 | Git policy |",
        "|---|---|---:|---:|---|---|",
    ]
    manifest_lines.extend(
        f"| {role} | `{filename}` | {rows} | {size} | `{digest}` | {policy} |"
        for role, filename, rows, size, digest, policy in manifest_rows
    )
    manifest_lines.extend(
        [
            "",
            f"Frozen source: `{source_file}`; 20000 rows; {source_file.stat().st_size} bytes; SHA-256 `{sha256_file(source_file)}`; protected prior accepted result, not copied.",
            f"Frozen OOS: `output_h2/details/h2_OOS.csv`; SHA-256 `{EXPECTED_OOS_SHA256}`; protected input, not copied.",
            "No MAT, workspace, cache, new scenario data, or solver output was created.",
        ]
    )
    (out / "LARGE_FILE_MANIFEST.md").write_text("\n".join(manifest_lines) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    repo = Path(__file__).resolve().parents[2]
    out = (repo / args.output).resolve()
    require(not out.exists(), f"Output directory already exists: {out}")
    out.mkdir(parents=True)

    source_file = repo / "results/task-002-stage2b-b3-smoke/58-main-msp-terminal-gap-mechanism-audit/run-004/terminal_target_vs_final_inventory.csv"
    objective_pair_file = repo / "results/task-002-stage2b-b3-smoke/58-main-msp-terminal-gap-mechanism-audit/run-004/objective_without_terminal_gap_penalty.csv"
    oos_file = repo / "output_h2/details/h2_OOS.csv"
    require(sha256_file(oos_file) == EXPECTED_OOS_SHA256, "Frozen OOS SHA-256 changed.")

    eval_text = (repo / "fa_h2/eval_h2.m").read_text(encoding="utf-8", errors="ignore")
    random_calls = re.findall(r"\b(?:rand|randi|randn|randperm)\s*\(", eval_text, flags=re.IGNORECASE)
    require(not random_calls, "eval_h2 contains an unexpected random-number call.")

    source = pd.read_csv(source_file)
    master = build_master(source)
    objective_pair = pd.read_csv(objective_pair_file).sort_values("path_id")
    require(objective_pair.path_id.to_list() == master.path_id.to_list(),
            "Step-05B-1 paired objective path IDs differ.")
    objective_error = float(
        np.max(
            np.abs(
                objective_pair.without_terminal_gap_delta_eta_minus_saa.to_numpy()
                - master.delta_operating_cost.to_numpy()
            )
        )
    )
    require(objective_error < 1e-9, "Operating-cost delta does not reproduce Step-05B-1.")

    for method, prefix, folder in [
        ("saa", "saa", "case-saa"),
        ("chi2_eta003", "dro", "case-chi2_eta003"),
    ]:
        saved = pd.read_csv(
            repo
            / f"results/task-002-stage2b-b3-smoke/57-main-msp-converged-terminal-loh-ab/run-003/{folder}/native_output/details/h2_oos_summary_by_path.csv"
        ).sort_values("path_id")
        require(saved.path_id.to_list() == master.path_id.to_list(), f"{method} saved path IDs differ.")
        checks = {
            "production_amount": f"{prefix}_production",
            "transport_amount": f"{prefix}_htt",
            "normal_shortage": f"{prefix}_ordinary_shortage",
            "final_loh_total": f"{prefix}_final_inventory",
            "total_cost": f"{prefix}_reported_objective",
            "terminal_cost": f"{prefix}_terminal_gap_penalty",
        }
        for saved_col, master_col in checks.items():
            error = float(np.max(np.abs(saved[saved_col].to_numpy() - master[master_col].to_numpy())))
            require(error < 1e-9, f"{method} {saved_col} reproduction failed: {error}")

    performance = build_performance_summary(master)
    ci = build_paired_ci(master)
    component = build_cost_decomposition(repo, master)
    inventory_dist, high_paths = build_inventory_outputs(repo, master)
    terminal_delta = build_terminal_delta(master)
    state_summary = build_state_summary(master)

    master.to_csv(out / "pathwise_saa_dro_comparison.csv", index=False)
    performance.to_csv(out / "pathwise_performance_summary.csv", index=False)
    ci.to_csv(out / "paired_difference_ci.csv", index=False)
    component.to_csv(out / "operating_cost_decomposition.csv", index=False)
    inventory_dist.to_csv(out / "inventory_change_distribution.csv", index=False)
    high_paths.to_csv(out / "high_inventory_gain_paths.csv", index=False)
    terminal_delta.to_csv(out / "terminal_hit_deltaT_deltaI.csv", index=False)
    state_summary.to_csv(out / "state_mechanism_summary.csv", index=False)

    require(len(master) == 10000 and len(terminal_delta) == 6053 and len(high_paths) == 1000,
            "Final output row-count gate failed.")
    require(int((master.delta_ordinary_shortage > TOL).sum()) == 280,
            "The known 280 ordinary-shortage-worse paths were not reproduced.")

    write_text_outputs(repo, out, master, performance, inventory_dist, terminal_delta, component, source_file)
    print(f"Step-05B-8 pathwise audit PASS: {out}")


if __name__ == "__main__":
    main()
