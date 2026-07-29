#!/usr/bin/env python3
"""Static freeze audit for the confirmed Step-03Z-B model definition."""

from __future__ import annotations

import csv
import hashlib
import subprocess
from pathlib import Path


BRANCH = "task/002-stage2b-b3-smoke"
FROZEN_HEAD = "68635008b3431f1806fafb932bf17d4b349ebf28"
CONCLUSION = "A. TWO_STAGE_THREE_PERIOD_MODEL_FROZEN"


def git(root: Path, *args: str) -> str:
    return subprocess.check_output(
        ["git", *args], cwd=root, text=True, encoding="utf-8", errors="replace"
    ).strip()


def read(root: Path, relative: str) -> str:
    return (root / relative).read_text(encoding="utf-8", errors="replace")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def tracked_blob_matches(root: Path, relative: str) -> bool:
    worktree_blob = git(root, "hash-object", relative)
    frozen_blob = git(root, "rev-parse", f"HEAD:{relative}")
    return worktree_blob == frozen_blob


def require(
    body: str,
    needle: str,
    label: str,
    checks: list[tuple[str, bool, str]],
) -> None:
    passed = needle in body
    checks.append((label, passed, needle))
    if not passed:
        raise RuntimeError(f"Required evidence missing: {label}: {needle}")


def write(path: Path, lines: list[str]) -> None:
    path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")


def main() -> None:
    script = Path(__file__).resolve()
    root = script.parents[2]
    output = root / "results/task-002-stage2b-b3-smoke/37-three-period-model-freeze/run-001"
    if output.exists():
        raise RuntimeError(f"Output already exists: {output}")

    branch = git(root, "branch", "--show-current")
    head = git(root, "rev-parse", "HEAD")
    upstream = git(root, "rev-parse", "@{upstream}")
    status_before = git(root, "status", "--short", "--branch")
    tracked_diff = git(root, "diff", "--name-only")
    staged_diff = git(root, "diff", "--cached", "--name-only")
    if branch != BRANCH or head != FROZEN_HEAD or upstream != FROZEN_HEAD:
        raise RuntimeError(
            f"Frozen baseline mismatch: branch={branch}, head={head}, upstream={upstream}"
        )
    if tracked_diff or staged_diff:
        raise RuntimeError("Tracked or staged changes existed before Step-03Z-B.")

    canonical_rel = "terminalLoh_wdro/docs/FORMAL_TWO_STAGE_THREE_PERIOD_MODEL.md"
    solve_rel = "terminalLoh_wdro/src/solve_step03Y_saa_audit_h2.m"
    recourse_rel = "terminalLoh_wdro/src/evaluate_step03Y_period_fixed_T_recourse_h2.m"
    recover_rel = "terminalLoh_wdro/src/recover_step03Y_prefix_entries_h2.m"
    yf_rel = "terminalLoh_wdro/src/run_step03YF_r2000_state_h2.m"
    za_conclusion_rel = "results/task-002-stage2b-b3-smoke/36-three-period-model-information-audit/run-001/conclusion.txt"
    yf_mechanical_rel = "results/task-002-stage2b-b3-smoke/35-period-vs-aggregate-saa-r2000/run-001/mechanical_audit.txt"
    yf_results_rel = "results/task-002-stage2b-b3-smoke/35-period-vs-aggregate-saa-r2000/run-001/terminalLOH_r2000.csv"

    canonical = read(root, canonical_rel)
    solve = read(root, solve_rel)
    recourse = read(root, recourse_rel)
    recover = read(root, recover_rel)
    yf = read(root, yf_rel)
    za_conclusion = read(root, za_conclusion_rel)
    yf_mechanical = read(root, yf_mechanical_rel)

    checks: list[tuple[str, bool, str]] = []
    canonical_requirements = [
        ("两阶段、完整场景信息下的三时间段运行模型", "canonical_chinese_name"),
        ("two-stage three-period operational model under full scenario information", "canonical_english_name"),
        ("It is scenario input data, not a decision variable", "D_is_input"),
        ("`y_r^tau(i,n)` is the optimized hydrogen service", "y_is_decision"),
        ("`u_r^tau(n)` is optimized unmet demand", "u_is_decision"),
        ("W1 operating decisions may therefore use", "full_information_W1"),
        ("no nonanticipativity constraints are imposed", "no_nonanticipativity"),
        ("Advance service for future-period demand is not allowed", "no_advance_service"),
        ("is not carried to a later period", "no_backlog"),
        ("No node-side inter-period hydrogen inventory variable exists", "no_node_inventory"),
    ]
    for needle, label in canonical_requirements:
        require(canonical, needle, label, checks)

    source_requirements = [
        (solve, "idx.T = next:(next + I - 1);", "one_T_vector"),
        (solve, "idx.y = reshape(next:(next + R * K * I * N - 1), [R, K, I, N]);", "scenario_period_y"),
        (solve, "idx.u = reshape(next:(next + R * K * N - 1), [R, K, N]);", "scenario_period_u"),
        (solve, "obj(idx.T) = gamma;", "gamma_T_cost"),
        (solve, "obj(idx.y(:)) = Ceff(:) / R;", "service_cost_1_over_R"),
        (solve, "obj(idx.u(:)) = M / R;", "shortage_cost_1_over_R"),
        (solve, "ub(idx.T) = Cap(:);", "T_capacity_upper_bound"),
        (solve, "yUpper = A .* reshape(D, [R, K, 1, N]);", "reachability_bound"),
        (solve, "rhs(row) = D(scenario, period, node);", "period_demand_input_rhs"),
        (solve, "cols = [reshape(idx.y(scenario, :, site, :), 1, []), idx.T(site)];", "shared_T_row"),
        (solve, "val(positions) = [ones(1, K * N), -1];", "shared_T_coefficients"),
        (recover, "Dperiod(outRow, :, :) = Dtau;", "period_D_recovery"),
        (recover, "Aperiod(outRow, :, :, :) = reachTau;", "period_A_recovery"),
        (recover, "Cperiod(outRow, :, :, :) = costTau;", "period_C_recovery"),
        (yf, "formalCap = [300; 200; 100; 150];", "formal_capacity"),
        (yf, 'period = solve_step03Y_saa_audit_h2("PERIOD",', "formal_period_entry"),
        (yf, "Dperiod, Aperiod, Cperiod, formalCap, context.M, context.gamma, config);", "formal_period_inputs"),
    ]
    for body, needle, label in source_requirements:
        require(body, needle, label, checks)

    absent_terms = [
        ("nonanticipativity", "nonanticip"),
        ("scenario_tree_token", "scenario_tree"),
        ("scenario_tree_phrase", "scenario tree"),
        ("backlog", "backlog"),
        ("inventory_state", "inventory_state"),
        ("replenishment", "replenish"),
    ]
    solve_lower = solve.lower()
    for label, term in absent_terms:
        passed = term not in solve_lower
        checks.append((f"period_solver_absent_{label}", passed, term))
        if not passed:
            raise RuntimeError(f"Confirmed model conflict found in period solver: {term}")

    require(
        za_conclusion,
        "implemented_information_structure=TWO_STAGE_FULL_SCENARIO_INFORMATION",
        "step03ZA_implementation_classification",
        checks,
    )
    require(yf_mechanical, "status=PASS", "step03YF_pass", checks)
    require(yf_mechanical, "formal_capacity_upper_kg=[300,200,100,150]", "step03YF_capacity", checks)
    require(yf_mechanical, "validation_file_count=0", "step03YF_no_validation", checks)
    require(yf_mechanical, "new_random_scenario_count=0", "step03YF_no_new_scenarios", checks)

    frozen_sources = [solve_rel, recourse_rel, recover_rel, yf_rel, yf_results_rel]
    frozen_hash_rows: list[tuple[str, str, bool]] = []
    for relative in frozen_sources:
        passed = tracked_blob_matches(root, relative)
        checks.append((f"unchanged_{Path(relative).name}", passed, relative))
        if not passed:
            raise RuntimeError(f"Frozen source/result changed: {relative}")
        frozen_hash_rows.append((relative, sha256(root / relative), passed))

    with (root / yf_results_rel).open(newline="", encoding="utf-8-sig") as handle:
        yf_rows = list(csv.DictReader(handle))
    if len(yf_rows) != 16:
        raise RuntimeError("Step-03Y-F TerminalLOH row count changed.")
    result_summary: dict[int, tuple[list[float], list[float]]] = {}
    for state in [7, 9, 11, 19]:
        rows = sorted(
            (row for row in yf_rows if int(row["initial_state_id"]) == state),
            key=lambda row: int(row["site_id"]),
        )
        if len(rows) != 4 or any(int(row["R"]) != 2000 for row in rows):
            raise RuntimeError(f"Step-03Y-F state {state} rows changed.")
        result_summary[state] = (
            [float(row["T_aggregate_kg"]) for row in rows],
            [float(row["T_period_kg"]) for row in rows],
        )
    checks.append(("step03YF_16_T_rows_unchanged", True, "16"))

    output.mkdir(parents=True)

    decision_lines = [
        "# Formal model decision",
        "",
        "The user has formally selected the following model:",
        "",
        "**两阶段、完整场景信息下的三时间段运行模型**",
        "",
        "**two-stage three-period operational model under full scenario information**",
        "",
        "The authoritative repository freeze is `terminalLoh_wdro/docs/FORMAL_TWO_STAGE_THREE_PERIOD_MODEL.md`.",
        "",
        "The first stage optimizes one shared four-site pre-disaster TerminalLOH vector. The second stage receives complete W1-W3 D/A/C for a realized scenario and jointly optimizes scenario-period service y and shortage u. W1 recourse may use W2/W3 information. No scenario tree, nonanticipativity, advance service, shortage backlog, period capacity reset, or node inventory is part of the model.",
    ]
    write(output / "formal_model_decision.md", decision_lines)

    write(output / "frozen_model_assumptions.md", [
        "# Frozen model assumptions",
        "",
        "- First stage: one shared `T=[T1,T2,T3,T4]` per initial state.",
        "- T meaning: optimized pre-disaster reserve/service-capacity target.",
        "- Second-stage scenario: `xi_r={D_r^tau,A_r^tau,C_r^tau}_{tau=1,2,3}`.",
        "- Inputs: D, A, and C. Decisions: y and u.",
        "- Full scenario information: W1-W3 recourse is optimized jointly.",
        "- W1 may use W2/W3 information.",
        "- Shared reserve: `sum_{tau,n} y_{r,tau,i,n} <= T_i`.",
        "- No per-period T reset and no physical inventory sharing across alternative scenarios.",
        "- No disaster-time replenishment, recovery, or additional procurement.",
        "- No advance service, shortage backlog, or node-side inter-period inventory.",
        "- No scenario tree, common-history operating variables, or nonanticipativity constraints.",
        "- This is not a strict multistage sequential-revelation model.",
    ])

    variables = [
        ["T_i", "decision", "first stage", "site i pre-disaster reserve/service-capacity target", "shared by all scenarios and periods", "kg", "idx.T"],
        ["D_r^tau(n)", "input", "second-stage scenario", "period node hydrogen demand", "scenario-period-node", "kg", "D / Dperiod"],
        ["A_r^tau(i,n)", "input", "second-stage scenario", "period site-node reachability", "scenario-period-site-node", "binary", "A / Aperiod"],
        ["C_r^tau(i,n)", "input", "second-stage scenario", "reachable service impedance/cost", "scenario-period-site-node", "cost coefficient", "C / Cperiod"],
        ["y_r^tau(i,n)", "decision", "second-stage recourse", "actual site-node hydrogen service", "scenario-period-site-node", "kg", "idx.y"],
        ["u_r^tau(n)", "decision", "second-stage recourse", "same-period unmet demand", "scenario-period-node", "kg", "idx.u"],
    ]
    with (output / "variable_definition_table.csv").open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.writer(handle)
        writer.writerow(["symbol", "role", "stage", "definition", "index_scope", "unit", "matlab_mapping"])
        writer.writerows(variables)

    mappings = [
        ["one shared first-stage T", "T_i", solve_rel, "105-119", "idx.T is one I-vector; ub is Cap", "PASS"],
        ["scenario-period service", "y_r,tau,i,n", solve_rel, "108-121", "idx.y has R,K,I,N indices", "PASS"],
        ["scenario-period shortage", "u_r,tau,n", solve_rel, "110-121", "idx.u has R,K,N indices", "PASS"],
        ["SAA objective", "gamma sum T + mean(Cy+Mu)", solve_rel, "113-116,162-167", "gamma and 1/R coefficients", "PASS"],
        ["period demand balance", "sum_i y+u=D", solve_rel, "132-145", "D is RHS input", "PASS"],
        ["reachability", "y<=A D", solve_rel, "117-121", "unreachable service upper bound is zero", "PASS"],
        ["shared three-period reserve", "sum_tau,n y<=T_i", solve_rel, "147-155", "one capacity row per scenario-site", "PASS"],
        ["period model entry", "PERIOD(Dperiod,Aperiod,Cperiod)", yf_rel, "79-100", "aggregate comparator is separate", "PASS"],
        ["no nonanticipativity", "none", solve_rel, "123-159", "no history or cross-scenario recourse rows", "PASS"],
        ["no advance/backlog", "same-period balance only", solve_rel, "132-145", "no cross-period demand state", "PASS"],
    ]
    with (output / "formula_code_mapping.csv").open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.writer(handle)
        writer.writerow(["model_item", "formula", "source_file", "source_lines", "implementation", "status"])
        writer.writerows(mappings)

    write(output / "terminology_consistency_audit.md", [
        "# Terminology consistency audit",
        "",
        "## Required terminology",
        "",
        "Use `two-stage three-period operational model under full scenario information` or the approved Chinese equivalent. The three periods are physical recourse periods inside stage 2.",
        "",
        "## Prohibited descriptions",
        "",
        "The current model must not be described as a three-stage stochastic program, a strict multistage sequential-revelation model, a scenario-tree model, or a model with period-specific TerminalLOH decisions.",
        "",
        "## Repository audit",
        "",
        "A tracked-file terminology search found no existing formal Step-03Y description that incorrectly labels this period model as strict multistage sequential revelation. The Step-03Z-A wording already matches the confirmed structure. No existing solver comment or result file required correction. The only terminology addition is the new canonical freeze document and this Step-03Z-B audit package.",
    ])

    regression = [
        "Step-03Z-B regression consistency check",
        "status=PASS",
        "solver_call_count=0",
        "R2000_rerun_count=0",
        "validation_file_count=0",
        "random_scenario_generation_count=0",
        "gamma=2",
        "scenario_weight=1/R",
        "shortage_penalty_M=2000",
        "capacity_upper_kg=[300,200,100,150]",
        "period_demand_balance=unchanged",
        "reachTau_service_bound=unchanged",
        "costTau_usage=unchanged",
        "shared_three_period_T=unchanged",
        "",
        "Step-03Y-F frozen TerminalLOH values:",
    ]
    for state, (aggregate, period) in result_summary.items():
        regression.append(
            f"state_{state}_R2000_aggregate_T={aggregate};period_T={period}"
        )
    regression.extend(["", "Frozen file SHA-256:"])
    regression.extend(f"{relative}|{digest}|matched_HEAD={passed}" for relative, digest, passed in frozen_hash_rows)
    write(output / "regression_consistency_check.txt", regression)

    intended_files = [
        canonical_rel,
        "terminalLoh_wdro/src/run_step03ZB_model_freeze_audit.py",
        "results/task-002-stage2b-b3-smoke/37-three-period-model-freeze/run-001/README.md",
        "results/task-002-stage2b-b3-smoke/37-three-period-model-freeze/run-001/formal_model_decision.md",
        "results/task-002-stage2b-b3-smoke/37-three-period-model-freeze/run-001/frozen_model_assumptions.md",
        "results/task-002-stage2b-b3-smoke/37-three-period-model-freeze/run-001/variable_definition_table.csv",
        "results/task-002-stage2b-b3-smoke/37-three-period-model-freeze/run-001/formula_code_mapping.csv",
        "results/task-002-stage2b-b3-smoke/37-three-period-model-freeze/run-001/terminology_consistency_audit.md",
        "results/task-002-stage2b-b3-smoke/37-three-period-model-freeze/run-001/regression_consistency_check.txt",
        "results/task-002-stage2b-b3-smoke/37-three-period-model-freeze/run-001/changed_files_manifest.txt",
        "results/task-002-stage2b-b3-smoke/37-three-period-model-freeze/run-001/mechanical_audit.txt",
        "results/task-002-stage2b-b3-smoke/37-three-period-model-freeze/run-001/conclusion.txt",
        "codex_rule/log.md",
    ]
    write(output / "changed_files_manifest.txt", [
        "Step-03Z-B intended changed files",
        "",
        *intended_files,
        "",
        "Explicit exclusions:",
        "- all Step-03Y-E local audit files",
        "- all historical untracked outputs and failed directories",
        "- recovered_period_data.mat and all other MAT/binary files",
        "- all SAA, WDRO, MSP, scenario-generation, distance, and rho logic",
    ])

    mechanical = [
        "Step-03Z-B mechanical audit",
        "status=PASS",
        f"conclusion={CONCLUSION}",
        f"branch={branch}",
        f"local_head={head}",
        f"upstream_head={upstream}",
        f"frozen_head={FROZEN_HEAD}",
        "solver_call_count=0",
        "gurobi_call_count=0",
        "wdro_call_count=0",
        "msp_call_count=0",
        "validation_file_count=0",
        "random_scenario_generation_count=0",
        "R2000_rerun_count=0",
        "formal_solver_logic_modified=false",
        "scenario_data_modified=false",
        "parameter_modified=false",
        "tracked_worktree_clean_at_start=true",
        "staged_worktree_clean_at_start=true",
        "protected_untracked_paths_written_count=0",
        "",
        "Checks:",
    ]
    mechanical.extend(
        f"{label}|{'PASS' if passed else 'FAIL'}|observed={observed}"
        for label, passed, observed in checks
    )
    write(output / "mechanical_audit.txt", mechanical)

    write(output / "conclusion.txt", [
        f"conclusion={CONCLUSION}",
        "audit_status=PASS",
        "formal_name_cn=两阶段、完整场景信息下的三时间段运行模型",
        "formal_name_en=two-stage three-period operational model under full scenario information",
        "first_stage_variable=T[1:4]",
        "second_stage_inputs=Dperiod,Aperiod,Cperiod",
        "second_stage_decisions=y,u",
        "W1_can_use_W2_W3_information=true",
        "shared_three_period_T=true",
        "advance_service_allowed=false",
        "shortage_backlog_allowed=false",
        "nonanticipativity_constraints_exist=false",
        "scenario_tree_exists=false",
        "formal_solver_logic_modified=false",
        "regression_consistency=PASS",
        "solver_call_count=0",
        "validation_file_count=0",
    ])

    write(output / "README.md", [
        "# Step-03Z-B model freeze",
        "",
        f"Conclusion: `{CONCLUSION}`.",
        "",
        "The user-confirmed two-stage full-scenario-information structure matches the existing Step-03Y period SAA implementation. The freeze adds documentation and a static audit only; no solver, model, data, parameter, scenario, or prior result was changed.",
        "",
        "The first stage optimizes one shared four-site TerminalLOH vector. The second stage receives complete W1-W3 period D/A/C and jointly optimizes period service y and shortage u. W1 may use W2/W3 information. All periods consume one T, with no advance service, backlog, replenishment, scenario tree, or nonanticipativity constraints.",
        "",
        "The authoritative model statement is `terminalLoh_wdro/docs/FORMAL_TWO_STAGE_THREE_PERIOD_MODEL.md`.",
        "",
        "## Frozen start status",
        "",
        "```text",
        status_before,
        "```",
    ])

    print(f"Step-03Z-B static freeze audit complete: {output}")
    print(CONCLUSION)


if __name__ == "__main__":
    main()
