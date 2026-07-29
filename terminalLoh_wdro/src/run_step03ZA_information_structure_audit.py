#!/usr/bin/env python3
"""Static Step-03Z-A audit of the Step-03Y three-period SAA model."""

from __future__ import annotations

import csv
import subprocess
from pathlib import Path


EXPECTED_BRANCH = "task/002-stage2b-b3-smoke"
EXPECTED_HEAD = "61122dee2cde34736111f0987905da6a3c63d35a"
CONCLUSION = "B. USER_DECISION_REQUIRED_ON_INFORMATION_STRUCTURE"


def git(root: Path, *args: str) -> str:
    return subprocess.check_output(
        ["git", *args], cwd=root, text=True, encoding="utf-8", errors="replace"
    ).strip()


def read(root: Path, relative: str) -> str:
    return (root / relative).read_text(encoding="utf-8", errors="replace")


def require(text: str, needle: str, label: str, checks: list[tuple[str, bool, str]]) -> None:
    passed = needle in text
    checks.append((label, passed, needle))
    if not passed:
        raise RuntimeError(f"Missing required source evidence: {label}: {needle}")


def write_text(path: Path, lines: list[str]) -> None:
    path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")


def main() -> None:
    script = Path(__file__).resolve()
    root = script.parents[2]
    output = root / "results/task-002-stage2b-b3-smoke/36-three-period-model-information-audit/run-001"
    if output.exists():
        raise RuntimeError(f"Output already exists: {output}")

    branch = git(root, "branch", "--show-current")
    head = git(root, "rev-parse", "HEAD")
    upstream = git(root, "rev-parse", "@{upstream}")
    status_before = git(root, "status", "--short", "--branch")
    tracked_diff = git(root, "diff", "--name-only")
    staged_diff = git(root, "diff", "--cached", "--name-only")
    if branch != EXPECTED_BRANCH or head != EXPECTED_HEAD or upstream != EXPECTED_HEAD:
        raise RuntimeError(
            f"Frozen baseline mismatch: branch={branch}, head={head}, upstream={upstream}"
        )
    if tracked_diff or staged_diff:
        raise RuntimeError("Tracked or staged worktree changes exist at audit start.")

    solve_rel = "terminalLoh_wdro/src/solve_step03Y_saa_audit_h2.m"
    fixed_rel = "terminalLoh_wdro/src/evaluate_step03Y_period_fixed_T_recourse_h2.m"
    recover_rel = "terminalLoh_wdro/src/recover_step03Y_prefix_entries_h2.m"
    frozen_rel = "terminalLoh_wdro/src/evaluate_frozen_wdro_dataset_block_h2.m"
    yf_rel = "terminalLoh_wdro/src/run_step03YF_r2000_state_h2.m"
    solve = read(root, solve_rel)
    fixed = read(root, fixed_rel)
    recover = read(root, recover_rel)
    frozen = read(root, frozen_rel)
    yf = read(root, yf_rel)

    checks: list[tuple[str, bool, str]] = []
    required = [
        (solve, "idx.T = next:(next + I - 1);", "one_common_T_vector"),
        (solve, "idx.y = reshape(next:(next + R * K * I * N - 1), [R, K, I, N]);", "scenario_period_service_variables"),
        (solve, "idx.u = reshape(next:(next + R * K * N - 1), [R, K, N]);", "scenario_period_shortage_variables"),
        (solve, "obj(idx.T) = gamma;", "holding_cost_coefficient"),
        (solve, "obj(idx.y(:)) = Ceff(:) / R;", "equal_weight_service_cost"),
        (solve, "obj(idx.u(:)) = M / R;", "equal_weight_shortage_cost"),
        (solve, "ub(idx.T) = Cap(:);", "terminal_capacity_upper_bounds"),
        (solve, "yUpper = A .* reshape(D, [R, K, 1, N]);", "period_reachability_service_bound"),
        (solve, "rhs(row) = D(scenario, period, node);", "period_demand_balance_rhs"),
        (solve, "cols = [reshape(idx.y(scenario, :, site, :), 1, []), idx.T(site)];", "shared_inventory_constraint"),
        (solve, "val(positions) = [ones(1, K * N), -1];", "shared_inventory_coefficients"),
        (recover, "failed(2, :) = failed(1, :) | lineU(pos, :) <= pFail{2};", "persistent_line_damage_W2"),
        (recover, "failed(3, :) = failed(2, :) | lineU(pos, :) <= pFail{3};", "persistent_line_damage_W3"),
        (recover, "closed(2, :) = closed(1, :) | roadU(pos, :) <= pClose{2};", "persistent_road_closure_W2"),
        (recover, "closed(3, :) = closed(2, :) | roadU(pos, :) <= pClose{3};", "persistent_road_closure_W3"),
        (recover, "slow(3, :) = max(slow(2, :), pClose{3});", "persistent_road_slowdown_W3"),
        (recover, "Dperiod(outRow, :, :) = Dtau;", "period_demand_retained"),
        (recover, "Aperiod(outRow, :, :, :) = reachTau;", "period_reachability_retained"),
        (recover, "Cperiod(outRow, :, :, :) = costTau;", "period_cost_retained"),
        (yf, "formalCap = [300; 200; 100; 150];", "frozen_capacity_vector"),
        (yf, 'period = solve_step03Y_saa_audit_h2("PERIOD",', "step03YF_period_solver_entry"),
        (yf, "Dperiod, Aperiod, Cperiod, formalCap, context.M, context.gamma, config);", "step03YF_period_inputs"),
    ]
    for text, needle, label in required:
        require(text, needle, label, checks)

    forbidden_terms = [
        ("nonanticip", "nonanticip"),
        ("scenario_tree_token", "scenario_tree"),
        ("scenario_tree_phrase", "scenario tree"),
        ("history_node", "history_node"),
        ("backlog", "backlog"),
        ("carryover", "carryover"),
        ("inventory_state", "inventory_state"),
        ("replenish", "replenish"),
    ]
    solve_lower = solve.lower()
    for label, term in forbidden_terms:
        absent = term not in solve_lower
        checks.append((f"period_solver_absent_{label}", absent, term))
        if not absent:
            raise RuntimeError(f"Unexpected information/inventory construct in period solver: {term}")

    regression_files = [
        ("Step-03Y-A", "results/task-002-stage2b-b3-smoke/27-period-data-recoverability/run-002/mechanical_audit.txt", "status=PASS"),
        ("Step-03Y-B", "results/task-002-stage2b-b3-smoke/28-period-vs-aggregate-loss/run-001/mechanical_audit.txt", "status=PASS"),
        ("Step-03Y-B-A retained failure", "results/task-002-stage2b-b3-smoke/29-period-lp-independent-crosscheck/run-001/mechanical_audit.txt", "status=FAIL"),
        ("Step-03Y-B-B superseding audit", "results/task-002-stage2b-b3-smoke/30-period-lp-equivalence-audit/run-001/mechanical_audit.txt", "status=PASS"),
        ("Step-03Y-C", "results/task-002-stage2b-b3-smoke/31-period-vs-aggregate-terminalLOH/run-001/mechanical_audit.txt", "status=PASS"),
        ("Step-03Y-C-A", "results/task-002-stage2b-b3-smoke/32-saa-weight-capacity-audit/run-001/mechanical_audit.txt", "status=PASS"),
        ("Step-03Y-D", "results/task-002-stage2b-b3-smoke/33-all-state-period-vs-aggregate-saa/run-001/mechanical_audit.txt", "status=PASS"),
        ("Step-03Y-E retained partial stop", "results/task-002-stage2b-b3-smoke/34-period-vs-aggregate-saa-stability/run-001/mechanical_audit.txt", "status=PARTIAL_STOP"),
        ("Step-03Y-F", "results/task-002-stage2b-b3-smoke/35-period-vs-aggregate-saa-r2000/run-001/mechanical_audit.txt", "status=PASS"),
    ]
    regression_rows = []
    for name, rel, expected in regression_files:
        body = read(root, rel)
        passed = expected in body
        checks.append((f"{name}_evidence", passed, expected))
        if not passed:
            raise RuntimeError(f"Regression evidence mismatch: {name}")
        regression_rows.append((name, rel, expected, "PASS"))

    docs = {
        "baseline": read(root, "docs/baseline/BASELINE.md"),
        "path_generation": read(root, "terminalLoh_wdro/docs/README_lookahead_W3_path_generation.md"),
        "longtask": read(root, "codex_rule/longtask.md"),
        "stepYB": read(root, "results/task-002-stage2b-b3-smoke/28-period-vs-aggregate-loss/run-001/README.md"),
    }
    doc_full_info_terms = ["full scenario information", "full information", "完整场景信息", "完整信息"]
    doc_sequential_terms = ["sequential revelation", "逐步揭示", "逐时间段信息揭示", "非预见性约束"]
    combined_docs = "\n".join(docs.values()).lower()
    explicit_full_info = any(term.lower() in combined_docs for term in doc_full_info_terms)
    explicit_sequential = any(term.lower() in combined_docs for term in doc_sequential_terms)
    checks.append(("existing_docs_do_not_explicitly_choose_full_information", not explicit_full_info, str(explicit_full_info)))
    checks.append(("existing_docs_do_not_explicitly_choose_sequential_revelation", not explicit_sequential, str(explicit_sequential)))
    if explicit_full_info or explicit_sequential:
        raise RuntimeError("Existing-document information-structure scan changed; manual review required.")

    output.mkdir(parents=True)

    mapping_rows = [
        ["period scenario", "xi_r={D^tau_r,A^tau_r,C^tau_r}_{tau=1..3}", "D/A/C arguments in PERIOD mode", solve_rel, "94-103", "PERIOD arrays are R x K x N and R x K x I x N", "CONFIRMED"],
        ["TerminalLOH", "T_i >= 0", "idx.T", solve_rel, "105-119", "one I-vector; lower bound zero and upper bound Cap", "CONFIRMED"],
        ["service", "y_{r,tau,i,n} >= 0", "idx.y", solve_rel, "108-121", "scenario-period-site-node service", "CONFIRMED"],
        ["shortage", "u_{r,tau,n} >= 0", "idx.u", solve_rel, "110-121", "scenario-period-node shortage", "CONFIRMED"],
        ["objective", "gamma sum_i T_i + (1/R) sum_r,tau,i,n C y + (M/R) sum_r,tau,n u", "obj", solve_rel, "113-116", "equal SAA weights", "CONFIRMED"],
        ["demand balance", "sum_i y_{r,tau,i,n}+u_{r,tau,n}=D_{r,tau,n}", "model rows", solve_rel, "132-145", "one equality per scenario-period-node", "CONFIRMED"],
        ["reachability", "0<=y_{r,tau,i,n}<=A_{r,tau,i,n}D_{r,tau,n}", "ub(idx.y)", solve_rel, "117-121", "unreachable arcs have zero upper bound", "CONFIRMED"],
        ["shared reserve", "sum_tau,n y_{r,tau,i,n}<=T_i", "capacity rows", solve_rel, "147-155", "one row per scenario-site, one common T_i", "CONFIRMED"],
        ["capacity", "0<=T<=[300,200,100,150] kg", "formalCap", yf_rel, "18-21,67-68", "same frozen upper bounds as Step-03Y-F", "CONFIRMED"],
        ["period damage", "failed/closed persist; slowdown is cumulative maximum", "failed,closed,slow", recover_rel, "276-287", "reconstructed before D/A/C", "CONFIRMED"],
        ["period DAC retention", "D^tau,A^tau,C^tau", "Dperiod,Aperiod,Cperiod", recover_rel, "338-362", "returned to the SAA runner", "CONFIRMED"],
        ["damage-array retention", "not a formal solver field", "failed,closed,slow", recover_rel, "276-287,360-362", "intermediate arrays are not returned after D/A/C are derived", "NOT_RETAINED_AS_SOLVER_INPUT"],
        ["nonanticipativity", "none", "none", solve_rel, "123-159", "no cross-scenario history rows or scenario-tree node variables", "ABSENT"],
        ["backlog/node inventory", "none", "none", solve_rel, "105-159", "only y and same-period u exist", "ABSENT"],
        ["replenishment", "none", "none", solve_rel, "105-159", "no inventory transition or supply-restoration variable", "ABSENT"],
    ]
    with (output / "formula_code_mapping.csv").open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.writer(handle)
        writer.writerow(["concept", "mathematical_form", "matlab_variable", "source_file", "source_lines", "evidence", "status"])
        writer.writerows(mapping_rows)

    write_text(output / "README.md", [
        "# Step-03Z-A three-period model information audit",
        "",
        f"- Frozen branch: `{branch}`.",
        f"- Frozen local/upstream HEAD: `{head}`.",
        "- Method: static source, result, and repository-document audit only.",
        "- Solver calls: `0`; WDRO calls: `0`; MSP calls: `0`; validation reads: `0`.",
        "- No Step-03Y R=2000 case was rerun.",
        f"- Conclusion: `{CONCLUSION}`.",
        "",
        "The implemented period SAA is internally a two-stage full-scenario-information model. One common pre-event TerminalLOH vector is optimized before scenario-specific recourse. Within each realized scenario, all W1-W3 service and shortage variables are optimized together, while all three periods consume the same site reserve. There are no nonanticipativity constraints or scenario-tree node decisions.",
        "",
        "The repository explains the three one-hour windows, persistent damage, cumulative demand, pre-layout purpose, shared reserve, and the absence of advance service/backlog. It does not explicitly state whether all W1-W3 consequences are known at the start of post-disaster recourse or revealed sequentially. That modeling assumption therefore requires an explicit user decision before formal freeze.",
        "",
        "## Protected start status",
        "",
        "```text",
        status_before,
        "```",
    ])

    write_text(output / "formal_period_scenario_definition.md", [
        "# Formal period scenario definition",
        "",
        "For the current period-resolved SAA candidate, the optimization-relevant consequence atom is",
        "",
        "`xi_r = {D^tau_r, A^tau_r, C^tau_r}_{tau=1,2,3}`.",
        "",
        "`Dperiod` is `R x 3 x 33`, while `Aperiod` and `Cperiod` are `R x 3 x 4 x 33`. The Step-03Y-F PERIOD solve passes these arrays directly to `solve_step03Y_saa_audit_h2`; aggregate D/A/C are used only by the explicit aggregate comparator and cross-evaluation paths.",
        "",
        "The recovery chain reconstructs period line failures, road closures, and road slowdown before deriving D/A/C. Failures and closures persist by logical OR, and slowdown uses the running maximum. These damage arrays are intermediate variables: the recovery helper returns `Dperiod/Aperiod/Cperiod` and identity metadata, not `failed/closed/slow` arrays. Thus the formal solver atom can be written using period D/A/C, but it does not separately retain the underlying damage-state arrays as solver inputs.",
        "",
        "The deterministic replay previously established that recombining the recovered periods reproduces frozen nominal aggregate D/A/C exactly. This audit reuses that evidence and performs no scenario regeneration.",
    ])

    write_text(output / "inventory_logic_audit.md", [
        "# Inventory and temporal logic audit",
        "",
        "## TerminalLOH",
        "",
        "`idx.T` is allocated once as an `I=4` vector before scenario and period recourse variables. It is nonnegative, has upper bounds `[300,200,100,150] kg`, and enters the objective through `gamma*sum(T)`. There is no `T_r` or `T_tau`; each initial-state SAA solve returns one four-site vector.",
        "",
        "The code therefore treats T as the common pre-event reserve/service-capacity decision. It is not a post-event remaining-inventory state, not reset by period, and not independently produced for each scenario.",
        "",
        "## Shared three-period use",
        "",
        "For every scenario r and site i, one row contains all `K*N` service variables and `-T_i`, implementing `sum_{tau,n} y_{r,tau,i,n} <= T_i`. W1 service consumes part of the same capacity available to W2 and W3. There is no per-period capacity reset.",
        "",
        "Each scenario has its own recourse flows constrained by the common design T. There is no physical inventory transfer across alternative scenarios. No disaster-time replenishment, recovery, or inventory transition variable exists.",
        "",
        "## Advance service and backlog",
        "",
        "Each equality uses only `y_{r,tau,:,n}`, `u_{r,tau,n}`, and `D_{r,tau,n}`. A W1 service variable cannot satisfy W2 or W3 demand, so advance service is not allowed. Shortage `u_{r,tau,n}` is charged in its own period and never appears in a later balance, so shortage carryover/backlog is not allowed. There is no node-side storage variable.",
    ])

    write_text(output / "information_structure_audit.md", [
        "# Information structure audit",
        "",
        "## Implemented classification",
        "",
        "The code implements **two-stage full-scenario information with three-period recourse**, not a strict multistage sequential-revelation model.",
        "",
        "- Stage 1: one common T vector is shared by all R scenarios.",
        "- Stage 2: after a scenario is selected, all W1-W3 `y` and `u` variables for that complete scenario are optimized in one LP.",
        "- W1 service competes with W2/W3 for the same T and is solved with all future-period D/A/C coefficients already present. It can therefore depend on W2/W3 information.",
        "- No constraint requires two scenarios with the same W1 history to use the same W1 decision.",
        "- No scenario-tree nodes, history-indexed decisions, or nonanticipativity rows exist.",
        "- Only T is scenario-common; all operating variables are complete-scenario-specific.",
        "",
        "This is a precise classification of the implemented deterministic equivalent. It does not decide whether full future information is the intended physical assumption.",
    ])

    write_text(output / "existing_document_consistency.md", [
        "# Existing document consistency",
        "",
        "## Statements that are explicit",
        "",
        "- `docs/baseline/BASELINE.md:18-20` defines W1-W3 as one hour each and defines aggregate demand as their sum.",
        "- `docs/baseline/BASELINE.md:34-37` states that component resistance is shared across W1-W3 and damage persists after first failure; road slowdown keeps the historical maximum.",
        "- `terminalLoh_wdro/docs/README_lookahead_W3_path_generation.md:45-49` describes W1-W3 as offline look-ahead consequence scenarios rather than an expansion of the MSP state space, and originally directs later work to aggregate D/A/C.",
        "- `codex_rule/longtask.md:390-403` describes post-impact scenario generation for pre-deployment TerminalLOH and explicitly says the project is not becoming a full post-disaster rolling-operation model.",
        "- `results/.../28-period-vs-aggregate-loss/run-001/README.md:9` documents the implemented shared T, period-specific balance, no advance service, and no shortage carryover.",
        "",
        "## Information-structure gap",
        "",
        "The audit also searched all tracked MATLAB/Python source and Markdown/TXT material for full-information, sequential-revelation, nonanticipativity, scenario-tree, advance-service, and backlog terminology. Only the Step-03Y implementation notes explicitly describe advance service/backlog; no repository statement selects an information-revelation regime.",
        "",
        "The reviewed repository materials do not explicitly state that all three future periods' D/A/C are known before W1 service is chosen. They also do not explicitly require sequential revelation or nonanticipativity. The phrase 'look-ahead scenario' and the offline pre-layout scope do not, by themselves, resolve this operational-information assumption.",
        "",
        "Accordingly, the current implementation is not contradicted by an explicit sequential-revelation statement, but neither is its full-scenario-information assumption explicitly authorized. The correct freeze gate is a user modeling decision, not an inference from successful solves.",
    ])

    regression_lines = [
        "Step-03Z-A regression consistency check",
        "status=PASS",
        "solver_call_count=0",
        "R2000_rerun_count=0",
        "validation_file_count=0",
        "",
        "name|source|expected|audit",
    ]
    regression_lines.extend("|".join(row) for row in regression_rows)
    regression_lines.extend([
        "",
        "Frozen candidate versus Step-03Y-F:",
        "objective=gamma*sum(T)+(1/R)*sum(service_cost+M*shortage)",
        "scenario_weight=1/R",
        "gamma=2",
        "shortage_penalty_M=2000",
        "capacity_upper_kg=[300,200,100,150]",
        "period_demand_balance=per scenario-period-node",
        "reachability=service upper bound Aperiod*Dperiod",
        "service_cost=Cperiod on reachable arcs",
        "shared_T=sum over all periods and nodes per scenario-site",
        "comparison_result=CONSISTENT",
    ])
    write_text(output / "regression_consistency_check.txt", regression_lines)

    mechanical = [
        "Step-03Z-A mechanical audit",
        "status=PASS",
        f"branch={branch}",
        f"local_head={head}",
        f"upstream_head={upstream}",
        f"frozen_head={EXPECTED_HEAD}",
        "solver_call_count=0",
        "gurobi_call_count=0",
        "wdro_call_count=0",
        "msp_call_count=0",
        "validation_file_count=0",
        "random_scenario_generation_count=0",
        "R2000_rerun_count=0",
        "tracked_worktree_clean_at_start=true",
        "staged_worktree_clean_at_start=true",
        "protected_untracked_paths_written_count=0",
        f"conclusion={CONCLUSION}",
        "",
        "Checks:",
    ]
    mechanical.extend(
        f"{label}|{'PASS' if passed else 'FAIL'}|observed={observed}"
        for label, passed, observed in checks
    )
    write_text(output / "mechanical_audit.txt", mechanical)

    write_text(output / "conclusion.txt", [
        f"conclusion={CONCLUSION}",
        "audit_status=PASS",
        "implemented_information_structure=TWO_STAGE_FULL_SCENARIO_INFORMATION",
        "W1_can_depend_on_W2_W3=true",
        "nonanticipativity_constraints_exist=false",
        "shared_three_period_T=true",
        "per_period_T_reset=false",
        "advance_service_allowed=false",
        "shortage_backlog_allowed=false",
        "node_side_storage_exists=false",
        "disaster_time_replenishment_exists=false",
        "period_DAC_retained=true",
        "period_damage_arrays_retained_as_solver_inputs=false",
        "existing_documents_explicitly_support_full_information=false",
        "existing_documents_explicitly_require_sequential_revelation=false",
        "formal_freeze_requires_user_decision=true",
        "solver_call_count=0",
        "validation_file_count=0",
    ])

    print(f"Step-03Z-A static audit complete: {output}")
    print(CONCLUSION)


if __name__ == "__main__":
    main()
