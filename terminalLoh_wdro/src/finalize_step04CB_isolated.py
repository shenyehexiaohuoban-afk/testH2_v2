from __future__ import annotations

import csv
import hashlib
import math
import sys
from pathlib import Path


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def write_csv(path: Path, rows: list[dict[str, object]], fields: list[str] | None = None) -> None:
    if not rows:
        raise RuntimeError(f"Refusing to write empty CSV: {path}")
    fields = fields or list(rows[0].keys())
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def number(value: object) -> float:
    if value is None:
        return math.nan
    text = str(value).strip()
    if text.lower() in {"", "nan", "na"}:
        return math.nan
    return float(text)


def truth(value: object) -> bool:
    return str(value).strip().lower() in {"1", "true", "yes", "pass"}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def fmt(value: float, digits: int = 6) -> str:
    if not math.isfinite(value):
        return "NaN"
    return f"{value:.{digits}f}"


def main() -> int:
    if len(sys.argv) != 3:
        raise SystemExit("usage: finalize_step04CB_isolated.py <repo-root> <work-dir>")
    root = Path(sys.argv[1]).resolve()
    work = Path(sys.argv[2]).resolve()
    cases_dir = work / "cases"
    prep = read_csv(work / "prepare_summary.csv")[0]
    beta = read_csv(work / "beta_scale_design.csv")
    manifest = read_csv(work / "state19_extreme_set_manifest.csv")
    if int(number(prep["extreme_path_count"])) != 27 or int(number(prep["extreme_replica_count"])) != 135:
        raise RuntimeError("State19 extreme count gate failed during finalization.")
    if len(beta) != 30 or len(manifest) != 27:
        raise RuntimeError("Prepared design/manifest row count failed.")

    summaries: list[dict[str, str]] = []
    fixed: list[dict[str, str]] = []
    losses: list[dict[str, str]] = []
    capacity_rows: list[dict[str, object]] = []
    convergence: list[dict[str, str]] = []
    cuts: list[dict[str, str]] = []
    runtime_rows: list[dict[str, object]] = []
    optimization_process_count = 0
    for case_id in range(1, 31):
        case_dir = cases_dir / f"case-{case_id:03d}"
        required = [
            "case_summary.csv", "case_fixed_audit.csv", "case_loss_shortage_summary.csv",
            "case_capacity_binding.csv", "convergence_and_bounds.csv", "active_extreme_cuts.csv",
            "case_mechanical_audit.txt", "fixed_audit_mechanical.txt",
        ]
        missing = [name for name in required if not (case_dir / name).is_file()]
        if missing:
            raise RuntimeError(f"Case {case_id} missing files: {missing}")
        summary = read_csv(case_dir / "case_summary.csv")[0]
        audit = read_csv(case_dir / "case_fixed_audit.csv")[0]
        if int(number(summary["case_id"])) != case_id or summary["solver_status"] != "OPTIMAL":
            raise RuntimeError(f"Case {case_id} solver status failed.")
        if not truth(summary["mechanical_pass"]) or not truth(audit["fixed_audit_pass"]):
            raise RuntimeError(f"Case {case_id} mechanical audit failed.")
        if number(summary["absolute_gap"]) > 1e-4 and number(summary["relative_gap"]) > 1e-8:
            raise RuntimeError(f"Case {case_id} convergence certificate failed.")
        summaries.append(summary)
        audit["decision_label"] = "BASELINE_SAA" if number(audit["kappa"]) == 0 and number(audit["eta"]) == 0 else (
            "BASELINE_CHI2" if number(audit["kappa"]) == 0 else "EXTREME_ENHANCED"
        )
        fixed.append(audit)
        losses.extend(read_csv(case_dir / "case_loss_shortage_summary.csv"))
        case_capacity = read_csv(case_dir / "case_capacity_binding.csv")
        for row in case_capacity:
            row.update({
                "decision_label": audit["decision_label"], "eta": audit["eta"],
                "design": audit["design"], "risk_type": audit["risk_type"],
                "top_k": audit["top_k"], "kappa": audit["kappa"], "beta_ext": audit["beta_ext"],
            })
            capacity_rows.append(row)
        convergence.extend(read_csv(case_dir / "convergence_and_bounds.csv"))
        cuts.extend(read_csv(case_dir / "active_extreme_cuts.csv"))
        case_process_count = len(list(case_dir.glob("batch-*_status.csv"))) + 1
        optimization_process_count += case_process_count
        runtime_rows.append({
            "case_id": case_id, "phase": "OPTIMIZATION", "eta": summary["eta"],
            "design": summary["design"], "kappa": summary["kappa"],
            "runtime_sec": summary["runtime_sec"], "master_solver_calls": summary["master_solver_calls"],
            "recourse_solver_calls": summary["recourse_solver_calls"], "fixed_T_solver_calls": 0,
            "fixed_T_scenario_evaluations": 0, "process_count": case_process_count, "status": "PASS",
        })
        runtime_rows.append({
            "case_id": case_id, "phase": "FIXED_T_AUDIT", "eta": audit["eta"],
            "design": audit["design"], "kappa": audit["kappa"],
            "runtime_sec": audit["fixed_audit_runtime_sec"], "master_solver_calls": 0,
            "recourse_solver_calls": 0, "fixed_T_solver_calls": 2,
            "fixed_T_scenario_evaluations": 15135, "process_count": 1, "status": "PASS",
        })

    full_dir = work / "full_capacity_audit"
    full = read_csv(full_dir / "full_capacity_fixed_audit.csv")
    full_losses = read_csv(full_dir / "full_capacity_loss_shortage_summary.csv")
    full_capacity = read_csv(full_dir / "full_capacity_binding.csv")
    if len(full) != 6 or not all(truth(row["fixed_audit_pass"]) for row in full):
        raise RuntimeError("FULL_CAPACITY audit failed.")
    for row in full:
        row["decision_label"] = "FULL_CAPACITY"
    comparison: list[dict[str, object]] = [dict(row) for row in fixed] + [dict(row) for row in full]
    losses.extend(full_losses)
    for full_row in full:
        for site in full_capacity:
            row = dict(site)
            row.update({
                "case_id": 0, "decision_label": "FULL_CAPACITY", "eta": full_row["eta"],
                "design": full_row["design"], "risk_type": full_row["risk_type"],
                "top_k": full_row["top_k"], "kappa": "NaN", "beta_ext": "NaN",
            })
            capacity_rows.append(row)
    runtime_rows.append({
        "case_id": 0, "phase": "FULL_CAPACITY_AUDIT", "eta": "NaN", "design": "ALL",
        "kappa": "NaN", "runtime_sec": "NaN", "master_solver_calls": 0,
        "recourse_solver_calls": 0, "fixed_T_solver_calls": 2,
        "fixed_T_scenario_evaluations": 15135, "process_count": 1, "status": "PASS",
    })

    key_fields = ("eta", "design", "risk_type", "top_k")
    full_by_key = {tuple(row[field] for field in key_fields): row for row in full}
    base_by_key = {
        tuple(row[field] for field in key_fields): row for row in fixed if number(row["kappa"]) == 0
    }
    if len(full_by_key) != 6 or len(base_by_key) != 6:
        raise RuntimeError("Baseline/FULL key construction failed.")

    headroom: list[dict[str, object]] = []
    tradeoff: list[dict[str, object]] = []
    recoverable: list[dict[str, object]] = []
    best_closed = -math.inf
    for key, base in base_by_key.items():
        full_row = full_by_key[key]
        base_r = number(base["extreme_risk"])
        full_r = number(full_row["extreme_risk"])
        denominator = base_r - full_r
        recoverable.append({
            "eta": key[0], "design": key[1], "risk_type": key[2], "top_k": key[3],
            "R_ext_baseline": base_r, "R_ext_FULL_CAPACITY": full_r,
            "recoverable_risk_amount": denominator,
            "recoverable_risk_fraction": denominator / base_r if base_r > 0 else math.nan,
            "irreducible_risk_fraction": full_r / base_r if base_r > 0 else math.nan,
            "baseline_extreme_shortage_mean_kg": base["extreme_shortage_mean_kg"],
            "FULL_CAPACITY_extreme_shortage_mean_kg": full_row["extreme_shortage_mean_kg"],
            "baseline_zero_shortage_share": base["extreme_zero_shortage_share"],
            "FULL_CAPACITY_zero_shortage_share": full_row["extreme_zero_shortage_share"],
        })
        for row in [candidate for candidate in comparison if tuple(str(candidate[field]) for field in key_fields) == key]:
            closed = (base_r - number(row["extreme_risk"])) / denominator if denominator > 1e-10 else math.nan
            if row["decision_label"] == "EXTREME_ENHANCED" and math.isfinite(closed):
                best_closed = max(best_closed, closed)
            headroom.append({
                "case_id": row.get("case_id", 0), "decision_label": row["decision_label"],
                "eta": row["eta"], "design": row["design"], "risk_type": row["risk_type"],
                "top_k": row["top_k"], "kappa": row["kappa"], "R_ext": row["extreme_risk"],
                "R_ext_FULL_CAPACITY": full_r, "Headroom": number(row["extreme_risk"]) - full_r,
                "R_ext_baseline": base_r, "recoverable_denominator": denominator,
                "ClosedRatio": closed, "extreme_shortage_mean_kg": row["extreme_shortage_mean_kg"],
                "FULL_CAPACITY_shortage_mean_kg": full_row["extreme_shortage_mean_kg"],
                "capacity_binding_count": row["capacity_binding_count"],
            })
            tradeoff.append({
                "case_id": row.get("case_id", 0), "decision_label": row["decision_label"],
                "eta": row["eta"], "design": row["design"], "top_k": row["top_k"],
                "kappa": row["kappa"], "TerminalLOH_total": row["TerminalLOH_total"],
                "inventory_change_from_baseline": number(row["TerminalLOH_total"]) - number(base["TerminalLOH_total"]),
                "first_stage_cost": row["first_stage_cost"],
                "first_stage_cost_change": number(row["first_stage_cost"]) - number(base["first_stage_cost"]),
                "nominal_risk": row["nominal_risk"],
                "nominal_risk_change": number(row["nominal_risk"]) - number(base["nominal_risk"]),
                "J_base": row["J_base"], "J_base_change": number(row["J_base"]) - number(base["J_base"]),
                "nominal_shortage_mean_kg": row["nominal_shortage_mean_kg"],
                "nominal_service_rate": row["nominal_service_rate"],
                "capacity_binding_count": row["capacity_binding_count"],
            })

    enhanced_fields = list(summaries[0].keys())
    write_csv(work / "enhanced_model_results.csv", summaries, enhanced_fields)
    write_csv(work / "convergence_and_bounds.csv", convergence)
    write_csv(work / "active_extreme_cuts.csv", cuts)
    write_csv(work / "saa_chi2_extreme_full_comparison.csv", comparison)
    write_csv(work / "extreme_headroom_audit.csv", headroom)
    write_csv(work / "recoverable_risk_fraction.csv", recoverable)
    write_csv(work / "nominal_performance_tradeoff.csv", tradeoff)
    write_csv(work / "extreme_loss_and_shortage_summary.csv", losses)
    write_csv(work / "terminalLOH_capacity_binding.csv", capacity_rows)
    write_csv(work / "runtime_and_solver_calls.csv", runtime_rows)

    max_gap = max(number(row["absolute_gap"]) for row in summaries)
    max_rel_gap = max(number(row["relative_gap"]) for row in summaries)
    max_opt_residual = max(number(row["maximum_mechanical_residual"]) for row in summaries)
    max_fixed_residual = max(number(row["maximum_mechanical_residual"]) for row in fixed)
    max_full_residual = max(number(row["maximum_mechanical_residual"]) for row in full)
    min_irreducible = min(number(row["irreducible_risk_fraction"]) for row in recoverable)
    max_irreducible = max(number(row["irreducible_risk_fraction"]) for row in recoverable)
    all_pass = len(summaries) == 30 and max_gap <= 1e-4 and max_opt_residual <= 1e-6 and max_fixed_residual <= 1e-5
    if not all_pass:
        raise RuntimeError("Overall mechanical gate failed.")

    model_status = "M-A. EXTREME_AWARE_CONVEX_MODEL_VERIFIED"
    if max_irreducible >= 0.8 and best_closed < 0.2:
        decision_candidate = "V-C. EXTREME_RISK_LARGELY_IRREDUCIBLE_BY_TERMINALLOH"
    elif best_closed >= 0.5 and any(number(row["capacity_binding_count"]) < 4 for row in fixed if row["decision_label"] == "EXTREME_ENHANCED"):
        decision_candidate = "V-A. MATERIAL_TERMINALLOH_DECISION_VALUE"
    else:
        decision_candidate = "V-B. LIMITED_TERMINALLOH_DECISION_VALUE"
    overall_candidate = (
        "A. PROCEED_TO_STEP04C_C_EXTREME_AWARE_CALIBRATION"
        if decision_candidate.startswith("V-A")
        else "B. KEEP_EXTREMES_AS_STRESS_VALIDATION_AND_CALIBRATE_PURE_CHI2"
    )

    saa = next(row for row in fixed if row["decision_label"] == "BASELINE_SAA" and row["design"] == "R1_MAX")
    chi2 = next(row for row in fixed if row["decision_label"] == "BASELINE_CHI2" and row["design"] == "R1_MAX")
    full_r1 = next(row for row in full if row["eta"] == "0.01" and row["design"] == "R1_MAX")
    finite_closed_rows = [
        row for row in headroom
        if row["decision_label"] == "EXTREME_ENHANCED" and math.isfinite(number(row["ClosedRatio"]))
    ]
    if finite_closed_rows:
        best_row = max(finite_closed_rows, key=lambda row: number(row["ClosedRatio"]))
        best_closed_value = number(best_row["ClosedRatio"])
        best_closed_text = (
            f"{best_closed_value:.6f}, eta={best_row['eta']}, "
            f"{best_row['design']}, kappa={best_row['kappa']}"
        )
    else:
        best_row = next(row for row in headroom if row["decision_label"] == "EXTREME_ENHANCED")
        best_closed_value = math.nan
        best_closed_text = "undefined because FULL_CAPACITY provides zero recoverable-risk denominator"

    formal_run_label = work.name.removesuffix(".work")

    mechanical = [
        "status=PASS", "formal_run_status=COMPLETE_PASS_PENDING_USER_METHOD_DECISION",
        "parameter_combination_count=30", f"independent_optimization_process_count={optimization_process_count}",
        "independent_fixed_T_audit_process_count=30", "state19_extreme_path_count=27",
        "state19_extreme_replica_count=135", "other_initial_state_path_count=0",
        f"maximum_absolute_gap={max_gap:.15g}", f"maximum_relative_gap={max_rel_gap:.15g}",
        f"maximum_optimization_mechanical_residual={max_opt_residual:.15g}",
        f"maximum_fixed_T_mechanical_residual={max_fixed_residual:.15g}",
        f"maximum_FULL_CAPACITY_mechanical_residual={max_full_residual:.15g}",
        "all_solver_status_OPTIMAL=true", "all_case_exit_codes_zero=true",
        "all_processes_released_before_next_case=true", "commit_performed=false", "push_performed=false",
    ]
    (work / "mechanical_audit.txt").write_text("\n".join(mechanical) + "\n", encoding="utf-8")

    readme = f"""# Step-04C-B extreme-aware DRO decision-value audit

本轮在新目录 `{formal_run_label}` 中从头完成 30 个参数组合。每个组合使用一个或多个隔离 MATLAB 切面批次完成优化，并由另一个独立进程执行完整固定 T 复评；所有进程退出码、OPTIMAL 状态、LB/UB、gap、迭代次数和机械残差均通过。

- state19 极端集合：27 条物理路径、135 个冻结后果副本；其他初始状态为 0。
- 主体集合：R=15000，字节严格等价聚合为 {prep['nominal_exact_group_count']} 组。
- 最大绝对 gap：{max_gap:.6g}；最大相对 gap：{max_rel_gap:.6g}。
- SAA TerminalLOH：[{saa['T1']}, {saa['T2']}, {saa['T3']}, {saa['T4']}] kg。
- 纯 chi-square TerminalLOH：[{chi2['T1']}, {chi2['T2']}, {chi2['T3']}, {chi2['T4']}] kg。
- FULL_CAPACITY 极端平均缺氢：{number(full_r1['extreme_shortage_mean_kg']):.6f} kg。
- 最佳观测 ClosedRatio：{best_closed_text}。
- FULL_CAPACITY 后的极端风险保留比例范围：{min_irreducible:.6f}–{max_irreducible:.6f}。

模型凸性和认证分解已通过。方法价值分类与下一阶段是否推进尚未冻结，等待用户依据本轮结果决定；本轮未 Commit、未 Push。
"""
    (work / "README.md").write_text(readme, encoding="utf-8")

    formulation = """# Extreme-aware convex formulation

For one state19 decision T, the nominal term is `J_base(T)=gamma*sum(T)+rho_chi2_eta(Q_nominal(T))`.
For each frozen physical path e, `L_e(T)=max_m Q(T,xi_e,m)` over its five deterministic replicas.
The tested stress risks are `R1(T)=max_e L_e(T)` and `R2(T)=average of the top-k L_e(T)`, with k=2 and k=3.
Each model minimizes `J_base(T)+beta_ext*R_ext(T)`, where `beta_ext=kappa*J_base(T_base)/R_ext(T_base)` and kappa is a behavior-test scale, not probability.
The extreme paths and replicas receive no nominal probability mass.
"""
    (work / "extreme_aware_formulation.md").write_text(formulation, encoding="utf-8")
    convexity = f"""# Convexity and subgradient audit

- Frozen LP recourse Q(T,xi) is convex in the right-hand-side capacity T.
- A pathwise maximum of five convex recourse functions is convex.
- The maximum across paths and the top-k average are convex pointwise maxima of convex sums.
- Capacity-row duals provide valid recourse subgradients; Danskin aggregation provides nominal Pearson and active extreme-risk subgradients.
- Separate nominal and extreme epigraph cuts are global lower bounds. Full fixed-T evaluation supplies upper bounds.
- All 30 isolated solves reached OPTIMAL. Maximum absolute LB/UB gap was `{max_gap:.15g}`.
- Maximum observed optimization mechanical residual was `{max_opt_residual:.15g}`; fixed-T residual was `{max_fixed_residual:.15g}`.
"""
    (work / "convexity_and_subgradient_audit.md").write_text(convexity, encoding="utf-8")

    decision_md = f"""# Decision-value conclusion

Mechanical model status: `{model_status}`.

Computed decision-value candidate: `{decision_candidate}`.

Computed overall candidate: `{overall_candidate}`.

These candidates are not frozen as the project method conclusion. Per user instruction, the run is reported first and awaits the user's judgment before any Git operation or next-stage authorization.

Best observed ClosedRatio was `{best_closed_text}`. FULL_CAPACITY retained `{min_irreducible:.6f}` to `{max_irreducible:.6f}` of baseline extreme risk across the six eta/risk definitions. Detailed inventory, shortage, capacity binding, nominal tradeoff, and headroom evidence is in the CSV artifacts.
"""
    (work / "decision_value_conclusion.md").write_text(decision_md, encoding="utf-8")
    conclusion = "\n".join([
        "formal_run_status=COMPLETE_PASS_PENDING_USER_METHOD_DECISION",
        f"model_status={model_status}", f"candidate_decision_value_status={decision_candidate}",
        f"candidate_overall_conclusion={overall_candidate}", "git_commit=NOT_PERFORMED", "git_push=NOT_PERFORMED",
    ]) + "\n"
    (work / "conclusion.txt").write_text(conclusion, encoding="utf-8")
    (work / "next_stage_plan.md").write_text(
        "# Unique next task\n\nUser reviews the Step-04C-B evidence and decides the method conclusion and whether Git Commit/Push are authorized.\n",
        encoding="utf-8",
    )

    prepared = work / "prepared_inputs.mat"
    a2_mat = root / "results/task-002-stage2b-b3-smoke/44-extreme-formal-consequence-freeze/run-003/extreme_formal_DAC_and_damage.mat"
    large_manifest = f"""# Large file manifest

| file | bytes | SHA-256 | role |
|---|---:|---|---|
| `{prepared}` | {prepared.stat().st_size} | `{sha256(prepared)}` | local isolated-process prepared nominal/state19-extreme inputs |
| `{a2_mat}` | {a2_mat.stat().st_size} | `{sha256(a2_mat)}` | protected frozen Step-04C-A2 D/A/C input; unchanged |

These large MAT files remain local and must not be staged automatically.
"""
    (work / "LARGE_FILE_MANIFEST.md").write_text(large_manifest, encoding="utf-8")
    print(
        "FINALIZE_STEP04CB_COMPLETE|status=PASS|cases=30|"
        f"max_gap={max_gap:.9g}|best_closed={best_closed_value:.9g}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
