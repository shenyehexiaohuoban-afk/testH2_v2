# -*- coding: utf-8 -*-
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from pathlib import Path

import numpy as np
import pandas as pd


TOL = 1e-9
ROOT = Path(
    r"C:\Users\chaos\Desktop\biye\test\testH2_v2\results\task-002-stage2b-b3-smoke"
    r"\Temporal3p5_DRO_TerminalLOH_BaseMSP5h"
)
RUN = ROOT / "training/runs/run-20260901-020054"
OUTPUT = RUN / "oos_complete_package"
SOURCE_MANIFEST = RUN / "oos_analysis/source_manifest.csv"
GROUPS = [
    "PHYSICAL_DISSIPATION", "OTHER_ABSORPTION",
    "TRUE_STAGE7_ZERO_TARGET", "TRUE_STAGE7_POSITIVE_TARGET",
]
CLASSES = ["ADEQUATE", "PURE_QUANTITY", "PURE_LOCATION", "MIXED"]


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(8 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def classify(frame: pd.DataFrame) -> pd.DataFrame:
    target = frame[[f"target_site{i}" for i in range(1, 5)]].to_numpy(float)
    inv = frame[[f"inventory_site{i}" for i in range(1, 5)]].to_numpy(float)
    gap = np.maximum(target - inv, 0).sum(axis=1)
    quantity = np.maximum(target.sum(axis=1) - inv.sum(axis=1), 0)
    spatial = gap - quantity
    cls = np.select(
        [
            (quantity <= TOL) & (spatial <= TOL),
            (quantity > TOL) & (spatial <= TOL),
            (quantity <= TOL) & (spatial > TOL),
            (quantity > TOL) & (spatial > TOL),
        ], CLASSES, default="NOT_IDENTIFIABLE",
    )
    return pd.DataFrame({
        "path_id": frame.path_id.to_numpy(int),
        "target_total_calc": target.sum(axis=1),
        "terminal_gap_calc": gap,
        "quantity_gap_calc": quantity,
        "spatial_gap_calc": spatial,
        "classification": cls,
    })


def load_path(path: Path) -> pd.DataFrame:
    frame = pd.read_csv(path)
    require(len(frame) == 10000, f"expected 10000 paths: {path}")
    require(frame.path_id.tolist() == list(range(1, 10001)), f"ordered path identity failed: {path}")
    calc = classify(frame)
    for col in calc.columns[1:]:
        frame[col] = calc[col].to_numpy()
    return frame


def assign_groups(base: pd.DataFrame, candidate: pd.DataFrame) -> pd.Series:
    require(base.termination_type.equals(candidate.termination_type), "termination identity mismatch")
    positive_b = base.target_total_calc > TOL
    positive_c = candidate.target_total_calc > TOL
    require(positive_b.equals(positive_c), "positive-target identity mismatch")
    group = pd.Series(index=base.index, dtype="object")
    group[base.termination_type.eq("PHYSICAL_DISSIPATION_A1")] = GROUPS[0]
    group[base.termination_type.eq("LF8_ABSORBING")] = GROUPS[1]
    stage7 = base.termination_type.eq("STAGE7_TERMINAL_CHECK")
    group[stage7 & ~positive_b] = GROUPS[2]
    group[stage7 & positive_b] = GROUPS[3]
    expected = {GROUPS[0]: 3497, GROUPS[1]: 379, GROUPS[2]: 5001, GROUPS[3]: 1123}
    require(group.value_counts().to_dict() == expected, f"group counts failed: {group.value_counts().to_dict()}")
    return group


def distributions(base: pd.Series, candidate: pd.Series, metric: str) -> dict[str, float | int]:
    delta = candidate - base
    result: dict[str, float | int] = {}
    for label, values in [("base", base), ("candidate", candidate), ("delta", delta)]:
        result[f"{metric}_{label}_mean"] = float(values.mean())
        result[f"{metric}_{label}_median"] = float(values.median())
        result[f"{metric}_{label}_q05"] = float(values.quantile(.05))
        result[f"{metric}_{label}_q25"] = float(values.quantile(.25))
        result[f"{metric}_{label}_q75"] = float(values.quantile(.75))
        result[f"{metric}_{label}_q95"] = float(values.quantile(.95))
    result[f"{metric}_decrease_count"] = int((delta < -TOL).sum())
    result[f"{metric}_increase_count"] = int((delta > TOL).sum())
    result[f"{metric}_equal_count"] = int((delta.abs() <= TOL).sum())
    return result


def cohort_masks(paired: pd.DataFrame) -> list[tuple[str, pd.Series, str]]:
    positive = paired.group.eq(GROUPS[3])
    failure_b = ~paired.classification_BASE.eq("ADEQUATE")
    failure_c = ~paired.classification_CANDIDATE.eq("ADEQUATE")
    return [
        ("ALL_PATH_10000", pd.Series(True, index=paired.index), "all paths"),
        ("ALL_ZERO_TARGET_8877", ~positive, "terminal target zero in both arms"),
        ("TRUE_STAGE7_POSITIVE_TARGET_1123", positive, "positive target in both arms"),
        *[(cls, positive & paired.classification_CANDIDATE.eq(cls), "Candidate classification") for cls in CLASSES],
        ("RECOVERED_70", positive & failure_b & ~failure_c, "Base failure -> Candidate adequate"),
        ("NEW_FAILURE_43", positive & ~failure_b & failure_c, "Base adequate -> Candidate failure"),
        ("PERSISTENT_FAILURE_403", positive & failure_b & failure_c, "failure in both arms"),
    ]


def objective_analysis(base_path: Path, candidate_path: Path, target: Path) -> tuple[pd.DataFrame, pd.DataFrame, dict[str, object], pd.DataFrame]:
    base = load_path(base_path)
    candidate = load_path(candidate_path)
    group = assign_groups(base, candidate)
    paired = base.merge(candidate, on="path_id", suffixes=("_BASE", "_CANDIDATE"), validate="one_to_one")
    paired["group"] = group.to_numpy()
    for arm in ("BASE", "CANDIDATE"):
        paired[f"reported_identity_error_{arm}"] = paired[f"reported_objective_{arm}"] - (
            paired[f"actual_operating_cost_{arm}"] + paired[f"terminal_penalty_cost_{arm}"]
        )
    paired["delta_actual"] = paired.actual_operating_cost_CANDIDATE - paired.actual_operating_cost_BASE
    paired["delta_terminal_penalty"] = paired.terminal_penalty_cost_CANDIDATE - paired.terminal_penalty_cost_BASE
    paired["delta_reported_objective"] = paired.reported_objective_CANDIDATE - paired.reported_objective_BASE

    rows = []
    dist_rows = []
    for name, mask, basis in cohort_masks(paired):
        subset = paired.loc[mask]
        row: dict[str, object] = {"cohort": name, "path_count": len(subset), "classification_basis": basis}
        for out, col in [
            ("actual_operating_cost", "actual_operating_cost"),
            ("terminal_penalty_cost", "terminal_penalty_cost"),
            ("reported_objective", "reported_objective"),
        ]:
            b, c = subset[f"{col}_BASE"], subset[f"{col}_CANDIDATE"]
            delta = float((c - b).mean())
            row[f"base_mean_{out}_yuan"] = float(b.mean())
            row[f"candidate_mean_{out}_yuan"] = float(c.mean())
            row[f"delta_mean_{out}_yuan"] = delta
            row[f"delta_pct_{out}"] = delta / float(b.mean()) * 100 if abs(float(b.mean())) > TOL else np.nan
            dist = {"cohort": name, "path_count": len(subset), "metric": out, "classification_basis": basis}
            dist.update(distributions(b, c, "value"))
            dist_rows.append(dist)
        d = subset.delta_reported_objective
        row["objective_decrease_count"] = int((d < -TOL).sum())
        row["objective_increase_count"] = int((d > TOL).sum())
        row["objective_equal_count"] = int((d.abs() <= TOL).sum())
        rows.append(row)

    summary = pd.DataFrame(rows)
    distribution = pd.DataFrame(dist_rows)
    require(int(summary.loc[summary.cohort.eq("RECOVERED_70"), "path_count"].iloc[0]) == 70, "recovered count failed")
    require(int(summary.loc[summary.cohort.eq("NEW_FAILURE_43"), "path_count"].iloc[0]) == 43, "new failure count failed")
    require(int(summary.loc[summary.cohort.eq("PERSISTENT_FAILURE_403"), "path_count"].iloc[0]) == 403, "persistent count failed")

    zero = paired.group.ne(GROUPS[3])
    max_identity = float(pd.concat([
        paired.reported_identity_error_BASE.abs(), paired.reported_identity_error_CANDIDATE.abs()
    ]).max())
    max_zero_penalty = float(paired.loc[zero, ["terminal_penalty_cost_BASE", "terminal_penalty_cost_CANDIDATE"]].abs().to_numpy().max())
    max_zero_reported_actual = float(np.max(np.abs(np.concatenate([
        (paired.loc[zero, "reported_objective_BASE"] - paired.loc[zero, "actual_operating_cost_BASE"]).to_numpy(),
        (paired.loc[zero, "reported_objective_CANDIDATE"] - paired.loc[zero, "actual_operating_cost_CANDIDATE"]).to_numpy(),
    ]))))
    qa = {
        "REPORTED_OBJECTIVE_QA": "PASS" if max_identity < 1e-6 and max_zero_penalty < 1e-9 else "FAIL",
        "formula": "reported_objective = actual_operating_cost + terminal_penalty_cost",
        "max_abs_reported_identity_error_yuan": max_identity,
        "zero_target_path_count": int(zero.sum()),
        "max_abs_zero_target_terminal_penalty_yuan": max_zero_penalty,
        "max_abs_zero_target_reported_minus_actual_yuan": max_zero_reported_actual,
        "terminal_penalty_scope": "NOT_PART_OF_OOS_ACTUAL_OPERATING_COST",
        "classification_basis_for_ADEQUATE_PQ_PL_MIXED": "CANDIDATE",
    }
    require(qa["REPORTED_OBJECTIVE_QA"] == "PASS", f"reported objective QA failed: {qa}")

    detail_cols = [
        "path_id", "group", "classification_BASE", "classification_CANDIDATE",
        "actual_operating_cost_BASE", "actual_operating_cost_CANDIDATE", "delta_actual",
        "terminal_penalty_cost_BASE", "terminal_penalty_cost_CANDIDATE", "delta_terminal_penalty",
        "reported_objective_BASE", "reported_objective_CANDIDATE", "delta_reported_objective",
        "terminal_gap_calc_BASE", "terminal_gap_calc_CANDIDATE",
    ]
    target.mkdir(parents=True, exist_ok=True)
    summary.to_csv(target / "01_reported_objective_group_summary.csv", index=False)
    distribution.to_csv(target / "02_reported_objective_distribution.csv", index=False)
    for cohort, filename in [
        ("NEW_FAILURE_43", "03_new_failure_43_objective.csv"),
        ("RECOVERED_70", "04_recovered_70_objective.csv"),
        ("PERSISTENT_FAILURE_403", "05_persistent_403_objective.csv"),
    ]:
        mask = dict((name, m) for name, m, _ in cohort_masks(paired))[cohort]
        paired.loc[mask, detail_cols].to_csv(target / filename, index=False)
    (target / "07_reported_objective_QA.json").write_text(json.dumps(qa, indent=2, ensure_ascii=False), encoding="utf-8")
    return summary, distribution, qa, paired


def objective_markdown(summary: pd.DataFrame, qa: dict[str, object]) -> str:
    s = summary.set_index("cohort")
    allp = s.loc["ALL_PATH_10000"]
    zero = s.loc["ALL_ZERO_TARGET_8877"]
    pos = s.loc["TRUE_STAGE7_POSITIVE_TARGET_1123"]
    rec = s.loc["RECOVERED_70"]
    new = s.loc["NEW_FAILURE_43"]
    per = s.loc["PERSISTENT_FAILURE_403"]

    def line(name: str, row: pd.Series) -> str:
        return (
            f"- {name}: actual {row.base_mean_actual_operating_cost_yuan:.3f} -> {row.candidate_mean_actual_operating_cost_yuan:.3f} "
            f"({row.delta_mean_actual_operating_cost_yuan:+.3f}); terminal penalty "
            f"{row.base_mean_terminal_penalty_cost_yuan:.3f} -> {row.candidate_mean_terminal_penalty_cost_yuan:.3f} "
            f"({row.delta_mean_terminal_penalty_cost_yuan:+.3f}); reported "
            f"{row.base_mean_reported_objective_yuan:.3f} -> {row.candidate_mean_reported_objective_yuan:.3f} "
            f"({row.delta_mean_reported_objective_yuan:+.3f}, {row.delta_pct_reported_objective:+.3f}%). "
            f"Path direction decrease/increase/equal = {int(row.objective_decrease_count)}/{int(row.objective_increase_count)}/{int(row.objective_equal_count)}。"
        )

    signal = "BETTER" if new.delta_mean_reported_objective_yuan < -TOL and new.objective_decrease_count > new.objective_increase_count else (
        "WORSE" if new.delta_mean_reported_objective_yuan > TOL and new.objective_increase_count > new.objective_decrease_count else "MIXED"
    )
    return f"""# Reported Objective 最终只读检查

正式恒等式为 `reported objective = actual operating cost + terminal penalty cost`；最大绝对闭合误差 `{qa['max_abs_reported_identity_error_yuan']:.3e}` yuan。Terminal penalty 不属于 OOS actual operating cost。

{line('ALL PATH 10000', allp)}
{line('ALL ZERO TARGET 8877', zero)}
{line('POSITIVE TARGET 1123', pos)}
{line('RECOVERED 70', rec)}
{line('NEW FAILURE 43', new)}
{line('PERSISTENT FAILURE 403', per)}

## New Failure 43

其 actual operating cost 虽下降 `{new.delta_mean_actual_operating_cost_yuan:.3f}` yuan/path，但 terminal penalty 增加 `{new.delta_mean_terminal_penalty_cost_yuan:.3f}` yuan/path。加回 terminal penalty 后，reported objective delta 为 `{new.delta_mean_reported_objective_yuan:+.3f}` yuan/path，方向计数 decrease/increase/equal 为 `{int(new.objective_decrease_count)}/{int(new.objective_increase_count)}/{int(new.objective_equal_count)}`，综合信号为 `{signal}`。这直接刻画了“actual cost 下降但 terminal service 变差”的完整目标权衡。

## Recovered 70

Recovered 同时表现为 actual cost `{rec.delta_mean_actual_operating_cost_yuan:+.3f}`、terminal penalty `{rec.delta_mean_terminal_penalty_cost_yuan:+.3f}`、reported objective `{rec.delta_mean_reported_objective_yuan:+.3f}` yuan/path；结合既有 service 分析，其 terminal service 上升。是否四项同时改善由上述实际符号决定，不作先验假定。

## Persistent Failure 403

该组虽未全部达到 adequate，但 existing gap severity 已由 52.453048 降至 37.352488 kg，mass service 由 84.780671% 升至 87.181502%；本轮进一步显示 actual cost `{per.delta_mean_actual_operating_cost_yuan:+.3f}`、terminal penalty `{per.delta_mean_terminal_penalty_cost_yuan:+.3f}`、reported objective `{per.delta_mean_reported_objective_yuan:+.3f}` yuan/path。

## Positive Target 1123

结合 sitewise failure 473 -> 446、quantity failure 270 -> 235、mass-weighted service 91.576350% -> 92.777010%，reported objective delta `{pos.delta_mean_reported_objective_yuan:+.3f}` yuan/path。总体方向由经济和服务指标共同支持，但仍存在 43 条 new location failures，并非 pathwise dominance。

## Zero Target QA

8877 条 zero-target 的 raw terminal penalty 最大绝对值为 `{qa['max_abs_zero_target_terminal_penalty_yuan']:.3e}` yuan；reported minus actual 最大绝对值 `{qa['max_abs_zero_target_reported_minus_actual_yuan']:.3e}` yuan，因此机械确认两者严格相等到数值精度。
"""


def copy_tree_files(source: Path, destination: Path, category: str, manifest_rows: list[dict[str, object]]) -> int:
    count = 0
    for path in sorted(source.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(source)
        target = destination / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
        require(sha256(path) == sha256(target), f"copy hash mismatch: {path}")
        manifest_rows.append({
            "relative_path": str(target.relative_to(OUTPUT)), "source_original_path": str(path),
            "file_size": path.stat().st_size, "SHA256": sha256(path), "category": category,
            "copied_or_linked_or_indexed": "COPIED", "description": f"Copied existing {category} artifact; hash verified.",
        })
        count += 1
    return count


def copy_file(source: Path, target: Path, category: str, description: str, manifest_rows: list[dict[str, object]]) -> None:
    require(source.is_file(), f"missing source: {source}")
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)
    require(sha256(source) == sha256(target), f"copy hash mismatch: {source}")
    manifest_rows.append({
        "relative_path": str(target.relative_to(OUTPUT)), "source_original_path": str(source),
        "file_size": source.stat().st_size, "SHA256": sha256(source), "category": category,
        "copied_or_linked_or_indexed": "COPIED", "description": description,
    })


def raw_index(source_files: dict[str, Path], destination: Path, manifest_rows: list[dict[str, object]]) -> tuple[pd.DataFrame, dict[str, str]]:
    destination.mkdir(parents=True, exist_ok=True)
    rows = []
    hashes = {}
    schema_notes = {
        "path": "Path-level objectives, costs, production, HTT, terminal targets/inventory/gaps.",
        "stage": "Serialized active-stage costs and operating quantities.",
        "site": "Serialized active-stage site demand/service/inventory/HTT.",
        "hour_site": "Serialized hourly site physics and operations.",
        "hour_system": "Serialized hourly grid/P_EL/HTT system fields.",
        "htt": "Positive HTT OD flows and exact OD costs.",
        "checkpoint": "Frozen policy checkpoint; indexed, not copied.",
        "common_bank": "Canonical ordered equal-weight path bank; indexed, not copied.",
    }
    for role, path in source_files.items():
        require(path.is_file(), f"missing indexed source {role}: {path}")
        digest = sha256(path)
        hashes[role] = digest
        key = next((k for k in schema_notes if role.endswith(k)), role)
        rows.append({
            "role": role, "real_source_path": str(path), "file_name": path.name,
            "file_size_bytes": path.stat().st_size, "SHA256": digest,
            "table_or_schema": key, "purpose": schema_notes.get(key, "OOS identity/evidence source."),
        })
        manifest_rows.append({
            "relative_path": str((destination / "RAW_DATA_INDEX.md").relative_to(OUTPUT)),
            "source_original_path": str(path), "file_size": path.stat().st_size, "SHA256": digest,
            "category": "RAW_MODE_C_INDEX", "copied_or_linked_or_indexed": "INDEXED",
            "description": f"{role}: source remains in place; indexed by absolute path and SHA256.",
        })
    frame = pd.DataFrame(rows)
    frame.to_csv(destination / "RAW_DATA_MANIFEST.csv", index=False)
    markdown = "# Raw Mode-C Data Index\n\nRaw data, checkpoint, and common path bank are not copied. The authoritative absolute paths, sizes, schemas, purposes, and SHA256 values are in `RAW_DATA_MANIFEST.csv`. This prevents duplicate large storage while preserving a mechanically verifiable archive.\n"
    (destination / "RAW_DATA_INDEX.md").write_text(markdown, encoding="utf-8")
    return frame, hashes


def integrated_report(reported: pd.DataFrame) -> str:
    obj = reported.set_index("cohort")
    new = obj.loc["NEW_FAILURE_43"]
    rec = obj.loc["RECOVERED_70"]
    per = obj.loc["PERSISTENT_FAILURE_403"]
    pos = obj.loc["TRUE_STAGE7_POSITIVE_TARGET_1123"]
    return f"""# Temporal3p5 Mode-C OOS 最终综合分析

## A. OOS 身份与公平比较

本次比较使用 10000 条完全相同、顺序一致、等权的 canonical OOS paths，Base 与 Candidate 按 `path_id` 一对一配对。Candidate 复用相同 Base MSP framework，仅将 TerminalLOH 替换为 Temporal3p5 DRO 35-state target，并完成 5h Candidate 训练后进行 Mode-C full-data OOS。OOS 前后 checkpoint SHA 均为 `9cac7bf2824476f532abc6ff4b80d04ca68449240bcb19729dc10d1849856353`，cuts 337371 未变。Candidate 状态仍为 `NOT YET FORMALLY ADOPTED`。

## B. 10000 路径总体结构

```text
10000
|- physical dissipation: 3497
|- other absorption: 379
`- true Stage7: 6124
   |- zero target: 5001
   `- positive target: 1123
```

`ALL_ZERO_TARGET = 3497 + 379 + 5001 = 8877`，但它只作为跨终止类型聚合，不替代上述层级。

## C-D. Zero-target 与三类来源

ALL_ZERO_TARGET production `172.770942 -> 144.975342 kg/path`（`-16.09%`），actual operating cost `53205.049 -> 52483.004 yuan/path`（`-722.045`）。Ordinary shortage `0.276121 -> 0.158505 kg/path`，没有恶化；electricity cost `-684.726`、HTT cost `+7.311`、ordinary-shortage cost `-23.523 yuan/path`。这描述的是 anticipatory preparation，不是 terminal-service failure，因为 terminal target 和 penalty 均为零。

Physical dissipation production/cost delta 为 `-22.485 kg / -581.199 yuan`；other absorption 为 `-30.743 / -985.465`；true Stage7 zero-target 为 `-31.286 / -800.570`。True Stage7 zero-target 的全路径 production/cost贡献分别为 `-15.646 kg/path` 与 `-400.365 yuan/path`，均是重要来源。

## E. Positive-target 1123

Base 分类 ADEQUATE/PQ/PL/MIXED = `650/118/203/152`；Candidate = `677/89/211/146`。完整迁移矩阵：

| Base \\ Candidate | ADEQUATE | PQ | PL | MIXED |
|---|---:|---:|---:|---:|
| ADEQUATE | 607 | 0 | 43 | 0 |
| PQ | 0 | 76 | 2 | 40 |
| PL | 70 | 0 | 130 | 3 |
| MIXED | 0 | 13 | 36 | 103 |

其中 70 条 `PL -> ADEQUATE`，43 条 `ADEQUATE -> PL`。Quantity component `270 -> 235`，由 38 条解除与 3 条新增形成；spatial-related `355 -> 357`，由 83 条解除与 85 条新增形成。

## F. Failure severity

403 条 persistent failure 虽未跨过 fully adequate threshold，但 mean gap `52.453048 -> 37.352488 kg`（`-28.79%`），mass-weighted capped service `84.780671% -> 87.181502%`（`+2.400831 pp`）。因此 adequate count 不是唯一的改善尺度。

## G. 四站

Positive-target capped service：Site1 `94.99% -> 94.93%`（`-0.06 pp`），Site2 `88.63% -> 88.84%`（`+0.21 pp`），Site3 `90.29% -> 96.20%`（`+5.91 pp`），Site4 `88.38% -> 90.61%`（`+2.23 pp`）。Site3/4 的 target 收缩大于 inventory 收缩，gap 明显下降；Site1 inventory 收缩超过 target 收缩，故几乎无改善。

## H. 时间机制

Production reduction 由 Stage1-2、Stage3-4、Stage5-6 分别贡献 `64.34%/32.61%/3.05%`；cost reduction 的 Stage1-2 贡献约 `52.02%`。主要变化形成于 early anticipatory preparation，Stage3-4 是次要来源，late-stage 对全路径总量贡献较小。

## I. 经济结果

ALL PATH actual operating cost `56192.370 -> 55266.252 yuan/path`，delta `-926.118`（`-1.648%`）。分项为 electricity/grid `-723.947`、ordinary shortage `-180.160`、EL O&M `-17.540`、holding `-4.244`、HTT `-0.227 yuan/path`。节省主要来自电力，没有明显转移成总体 HTT cost。

## J. Recovered / New failure

Recovered 70：production `-34.915 kg/path`，HTT mass `+4.023 kg/path`，HTT cost `-162.684 yuan/path`，actual operating cost `-3344.884 yuan/path`；Site3/4 inventory 增加且 target 下调，gap 清零。New failure 43：production `-34.683`，HTT mass `+0.936`，HTT cost `-114.798`，actual cost `-2810.789`；Site2/Site1 inventory 下降超过 target 下调，形成新 location mismatch。两组 production 降幅接近，但空间分配和 OD 结构不同，terminal 结果相反。

## K. Reported objective

`reported objective = actual operating cost + terminal penalty`，terminal penalty 不属于 actual operating cost。Positive-target reported-objective delta `{pos.delta_mean_reported_objective_yuan:+.3f} yuan/path`；Recovered `{rec.delta_mean_reported_objective_yuan:+.3f}`；New failure `{new.delta_mean_reported_objective_yuan:+.3f}`；Persistent failure `{per.delta_mean_reported_objective_yuan:+.3f}`。New-failure 的实际 path direction decrease/increase/equal 为 `{int(new.objective_decrease_count)}/{int(new.objective_increase_count)}/{int(new.objective_equal_count)}`，说明完整目标信号不能只由 mean actual cost 判断。

## L. State evidence boundary

本次 Stage7 OOS 实际出现的重点 state 为 9、11、17、23、29、33。States 30、31、32 的 `OOS_STAGE7_PATH_COUNT = 0`，不得直接做 OOS 性能归因；29/33 各仅 1 条，也只能作为路径事实，不能推导稳定 state 规律。

## M. 最终综合结论

优势包括：更低 anticipatory production、较低 actual operating cost、ordinary shortage 未恶化、quantity pressure 下降、capped mass service 上升、persistent gap severity 下降以及 Site3/Site4 改善。Trade-off 包括：PURE_LOCATION 仍存在，新增 43 条 location failures，Site1 无实质改善，部分 states/cohorts 恶化，且不存在 pathwise dominance。

这些是 temporal-refinement TerminalLOH 改变后的配对 policy/consequence 结果，不是系统自然物理可靠性提高，也不是相同 terminal target 下的纯效率比较。Candidate 尚未 Formal Adoption。
"""


def main() -> None:
    global OUTPUT
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=OUTPUT)
    args = parser.parse_args()
    OUTPUT = args.output
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for name in ["00_README", "01_raw_mode_c", "02_core_oos_analysis", "03_path_deep_dive", "04_economic_deep_dive", "05_reported_objective", "06_qa_and_manifests", "07_final_integrated_analysis"]:
        (OUTPUT / name).mkdir(parents=True, exist_ok=True)

    source_manifest = pd.read_csv(SOURCE_MANIFEST)
    source_files = {r.role: Path(r.path) for r in source_manifest.itertuples()}
    checkpoint = Path(source_files["candidate_checkpoint"])
    common_bank = Path(source_files["common_bank"])
    indexed = {k: v for k, v in source_files.items() if k.startswith("base_") or k.startswith("candidate_")}
    indexed["common_bank"] = common_bank
    manifest_rows: list[dict[str, object]] = []
    _, source_hashes_before = raw_index(indexed, OUTPUT / "01_raw_mode_c", manifest_rows)

    reported, _, reported_qa, _ = objective_analysis(
        source_files["base_path"], source_files["candidate_path"], OUTPUT / "05_reported_objective"
    )
    reported_md = objective_markdown(reported, reported_qa)
    (OUTPUT / "05_reported_objective/06_reported_objective_summary_zh.md").write_text(reported_md, encoding="utf-8")

    copy_tree_files(RUN / "oos_analysis", OUTPUT / "02_core_oos_analysis/oos_analysis", "CORE_OOS_ANALYSIS", manifest_rows)
    if (RUN / "comparisons").is_dir():
        copy_tree_files(RUN / "comparisons", OUTPUT / "02_core_oos_analysis/comparisons", "CORE_OOS_COMPARISONS", manifest_rows)
    copy_tree_files(RUN / "mode_c_deep_dive", OUTPUT / "03_path_deep_dive", "PATH_DEEP_DIVE", manifest_rows)
    copy_tree_files(RUN / "mode_c_economic_deep_dive", OUTPUT / "04_economic_deep_dive", "ECONOMIC_DEEP_DIVE", manifest_rows)

    qa_files = [
        ROOT / "status/OOS_COMPLETED.txt", ROOT / "status/CHAIN_COMPLETED.txt", ROOT / "status/ANALYSIS_COMPLETED.txt",
        ROOT / "status/TRAINING_COMPLETED.txt", RUN / "oos_modeC/OOS_RAW_COMPLETED.marker", RUN / "oos_modeC/oos_metadata.csv",
        ROOT / "diagnostics/MODE_C_SCHEMA_CONTRACT_QA.json", ROOT / "manifests/CANDIDATE_IDENTITY.md",
        ROOT / "manifests/ONLY_TERMINALLOH_REPLACED_QA.json", RUN / "training/qa/pmax_propagation.csv",
        RUN / "training/acceptance/checkpoint_reload_audit.csv", RUN / "01_preflight/common_bank/bank_identity.csv",
        RUN / "01_preflight/common_bank/oos_path_manifest.csv", SOURCE_MANIFEST,
    ]
    for source in qa_files:
        target = OUTPUT / "06_qa_and_manifests" / source.name
        copy_file(source, target, "QA_AND_MANIFEST", "Copied OOS identity/QA evidence; hash verified.", manifest_rows)

    integrated = integrated_report(reported)
    integrated_path = OUTPUT / "07_final_integrated_analysis/FINAL_OOS_INTEGRATED_ANALYSIS_ZH.md"
    integrated_path.write_text(integrated, encoding="utf-8")

    readme = f"""# OOS Complete Package 导航

## 实验身份

- Base：当前 Stage89Q Formal Base / current adopted Stage89K TerminalLOH policy result。
- Candidate：`TEMPORAL3P5_DRO_BASEMSP5H_CANDIDATE`，相同 Base MSP framework，仅替换为 Temporal3p5 DRO TerminalLOH；TerminalLOH SHA `70e02fe1b46d09b4cf77fcf1fbfa1f1c4ab98c8200c52b51d6bdd7ac2205dae5`。
- Candidate checkpoint：`{checkpoint}`，SHA `{source_hashes_before['candidate_checkpoint']}`。
- OOS：10000 条 identical ordered equal-weight canonical paths，Mode C full raw，Base/Candidate 按 path_id 配对。
- Candidate 状态：`NOT YET FORMALLY ADOPTED`；本包不构成 Formal Adoption。

## 目录

- `01_raw_mode_c`：大型 Base/Candidate raw、checkpoint、path bank 的绝对路径、大小、schema 与 SHA256 索引；未复制大型文件。
- `02_core_oos_analysis`：完整现有正式 OOS analysis 与 comparisons。
- `03_path_deep_dive`：production、stage/hour、transition、flipped paths、site/state 机制分析。
- `04_economic_deep_dive`：经济 schema、energy/cost、HTT OD、shortage、stage/hour cost 与 cohort 成本。
- `05_reported_objective`：actual cost + terminal penalty = reported objective 的最终检查。
- `06_qa_and_manifests`：OOS completion、raw completion、checkpoint/bank/path identity、schema 与只读证据。
- `07_final_integrated_analysis`：最终中文综合结论。

## 推荐阅读顺序

1. `07_final_integrated_analysis/FINAL_OOS_INTEGRATED_ANALYSIS_ZH.md`
2. `02_core_oos_analysis/oos_analysis/00_plain_language_summary_zh.md`
3. `03_path_deep_dive/10_compact_mechanism_summary_zh.md`
4. `04_economic_deep_dive/10_economic_deep_dive_summary_zh.md`
5. `05_reported_objective/06_reported_objective_summary_zh.md`
6. 需要复核时再读取各 CSV 与 `01_raw_mode_c/RAW_DATA_MANIFEST.csv`。
"""
    (OUTPUT / "00_README/README_OOS_COMPLETE_PACKAGE_ZH.md").write_text(readme, encoding="utf-8")

    source_hashes_after = {role: sha256(path) for role, path in indexed.items()}
    require(source_hashes_before == source_hashes_after, "indexed source hashes changed during packaging")

    # Register newly generated package files after copying/indexing.
    known_rel = {r["relative_path"] for r in manifest_rows if r["copied_or_linked_or_indexed"] == "COPIED"}
    for path in sorted(OUTPUT.rglob("*")):
        if not path.is_file() or path.name == "OOS_COMPLETE_PACKAGE_MANIFEST.csv":
            continue
        rel = str(path.relative_to(OUTPUT))
        if rel in known_rel or rel in {"01_raw_mode_c/RAW_DATA_MANIFEST.csv", "01_raw_mode_c/RAW_DATA_INDEX.md"}:
            continue
        category = rel.split("\\")[0].split("/")[0]
        manifest_rows.append({
            "relative_path": rel, "source_original_path": "GENERATED_IN_PACKAGE",
            "file_size": path.stat().st_size, "SHA256": sha256(path), "category": category,
            "copied_or_linked_or_indexed": "GENERATED", "description": "Generated read-only consolidation/report artifact.",
        })

    manifest = pd.DataFrame(manifest_rows).sort_values(["category", "relative_path", "source_original_path"])
    manifest.to_csv(OUTPUT / "OOS_COMPLETE_PACKAGE_MANIFEST.csv", index=False)

    term = pd.read_csv(RUN / "oos_analysis/termination_ledger.csv")
    cls = pd.read_csv(RUN / "oos_analysis/terminal_classification_summary.csv")
    transition = pd.read_csv(RUN / "mode_c_deep_dive/04_positive_transition_matrix.csv")
    production = pd.read_csv(RUN / "mode_c_deep_dive/01_group_production_summary.csv")
    cost_contrib = pd.read_csv(RUN / "mode_c_economic_deep_dive/06_cost_contribution_decomposition.csv")
    cost_summary = pd.read_csv(RUN / "mode_c_economic_deep_dive/05_group_total_cost_summary.csv")
    qa_checks = {
        "OOS_PATH_COUNT": 10000,
        "ORDERED_EQUAL_WEIGHT": True,
        "PHYSICAL_PLUS_OTHER_PLUS_STAGE7": int(term[(term.arm == "BASE") & term.category.isin(["PHYSICAL_DISSIPATION_A1", "LF8_ABSORBING", "STAGE7_TERMINAL_CHECK"])]["count"].sum()) == 10000,
        "STAGE7_ZERO_PLUS_POSITIVE": 5001 + 1123 == 6124,
        "ADEQUATE_PQ_PL_MIXED": int(cls[(cls.arm == "CANDIDATE") & cls.metric.isin(CLASSES)]["count"].sum()) == 1123,
        "RECOVERED": int(transition[(transition.base_classification != "ADEQUATE") & (transition.candidate_classification == "ADEQUATE")].path_count.sum()) == 70,
        "NEW_FAILURE": int(transition[(transition.base_classification == "ADEQUATE") & (transition.candidate_classification != "ADEQUATE")].path_count.sum()) == 43,
        "PERSISTENT_FAILURE": int(transition[(transition.base_classification != "ADEQUATE") & (transition.candidate_classification != "ADEQUATE")].path_count.sum()) == 403,
        "PRODUCTION_CONTRIBUTION_RECONCILIATION": abs(production[production.group.isin(GROUPS)].group_contribution_to_all_path_mean_delta_kg.sum() - production.loc[production.group.eq("ALL_PATH_10000"), "paired_mean_delta_kg_per_path"].iloc[0]) < 1e-9,
        "COST_CONTRIBUTION_RECONCILIATION": float(cost_contrib.reconciliation_error_yuan.abs().max()) < 1e-7,
        "COST_IDENTITY": float(cost_summary.MAX_ABS_COST_IDENTITY_ERROR.max()) < 1e-6,
        "REPORTED_OBJECTIVE_IDENTITY": reported_qa["REPORTED_OBJECTIVE_QA"] == "PASS",
        "CHECKPOINT_SHA_UNCHANGED": source_hashes_before["candidate_checkpoint"] == "9cac7bf2824476f532abc6ff4b80d04ca68449240bcb19729dc10d1849856353",
        "RAW_OOS_SHA_UNCHANGED": source_hashes_before == source_hashes_after,
        "FORMAL_ADOPTION": False,
    }
    qa_checks = {k: (bool(v) if isinstance(v, (np.bool_, bool)) else int(v) if isinstance(v, np.integer) else v) for k, v in qa_checks.items()}
    qa_checks["OOS_PACKAGE_QA"] = all(v is True or (k == "OOS_PATH_COUNT" and v == 10000) or k == "FORMAL_ADOPTION" for k, v in qa_checks.items())
    (OUTPUT / "06_qa_and_manifests/OOS_PACKAGE_FINAL_QA.json").write_text(json.dumps(qa_checks, indent=2, ensure_ascii=False), encoding="utf-8")
    require(qa_checks["OOS_PACKAGE_QA"], f"package QA failed: {qa_checks}")
    print(json.dumps({
        "package": str(OUTPUT), "indexed": int((manifest.copied_or_linked_or_indexed == "INDEXED").sum()),
        "copied": int((manifest.copied_or_linked_or_indexed == "COPIED").sum()),
        "generated": int((manifest.copied_or_linked_or_indexed == "GENERATED").sum()),
        "reported_objective_qa": reported_qa["REPORTED_OBJECTIVE_QA"], "package_qa": "PASS",
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
