"""Finalize Step-05B-5 after prepared information and saved-cut audits pass."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path

import numpy as np
import pandas as pd


TOL = 1.0e-7
CLASSIFICATION = {
    12: "A_information_type",
    13: "A_information_type",
    14: "A_information_type",
    19: "C_mixed_type",
}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def node_level_cut_summary(cuts: pd.DataFrame) -> pd.DataFrame:
    rows = []
    keys = ["method", "state", "path_id", "decision_stage", "current_k", "current_lf", "history_node_id"]
    for key, group in cuts.groupby(keys, sort=True):
        meta = dict(zip(keys, key))
        top_marginal = int(group.loc[group["chosen_marginal_value_rank"].idxmin(), "site"])
        top_realized = int(group.loc[group["realized_target_rank"].idxmin(), "site"])
        top_node_mean = int(group.loc[group["node_conditional_mean_target_rank"].idxmin(), "site"])
        rows.append(
            {
                **meta,
                "top_marginal_value_site": top_marginal,
                "top_realized_target_site": top_realized,
                "top_node_conditional_mean_target_site": top_node_mean,
                "top_marginal_matches_realized_target": int(top_marginal == top_realized),
                "top_marginal_matches_node_mean_target": int(top_marginal == top_node_mean),
                "marginal_value_range": float(
                    group["chosen_marginal_value_of_1kg_inventory"].max()
                    - group["chosen_marginal_value_of_1kg_inventory"].min()
                ),
                "site1_marginal_value": float(
                    group.loc[group["site"] == 1, "chosen_marginal_value_of_1kg_inventory"].iloc[0]
                ),
                "active_cut_count": int(group["active_cut_count"].iloc[0]),
                "total_cut_count": int(group["total_cut_count"].iloc[0]),
                "realized_terminal_state_probability": float(
                    group["realized_terminal_state_probability"].iloc[0]
                ),
                "positive_target_modal_top_site_probability": float(
                    group["positive_target_modal_top_site_probability"].iloc[0]
                ),
                "conditional_max_site_target_range_kg": float(
                    group["conditional_max_site_target_range_kg"].iloc[0]
                ),
                "inventory_vs_realized_target_distribution_l1": float(
                    group["inventory_vs_realized_target_distribution_l1"].iloc[0]
                ),
            }
        )
    return pd.DataFrame(rows)


def first_divergence_stage(alignment: pd.DataFrame, state: int) -> int | float:
    grouped = alignment[alignment["state"] == state].groupby("decision_stage")[
        "mean_policy_inventory_absolute_difference_l1_kg"
    ].mean()
    candidates = grouped[grouped > 0.01]
    return int(candidates.index.min()) if not candidates.empty else np.nan


def latest_lf_row(stage_info: pd.DataFrame, state: int) -> pd.Series:
    scope = f"state{state}_physical_feasible_actual_unmet"
    rows = stage_info[stage_info["scope"] == scope].sort_values("lf")
    if rows.empty:
        raise RuntimeError(f"No stage information rows for state {state}.")
    return rows.iloc[-1]


def build_judgments(
    stage_info: pd.DataFrame,
    alignment: pd.DataFrame,
    trace: pd.DataFrame,
    cut_nodes: pd.DataFrame,
) -> pd.DataFrame:
    unique_paths = trace[trace["method"] == "chi2_eta003"].drop_duplicates(["state_id", "path_id"])
    rows = []
    rationale = {
        12: (
            "Full target vector remains highly dispersed through the latest pre-terminal information; "
            "policy inventories diverge from SAA before that information is resolved. All three representative "
            "DRO cut nodes rank the correct target station highest, so current evidence mainly supports a "
            "nonanticipative information explanation rather than a systematic cut-direction failure."
        ),
        13: (
            "The feasible-unmet sample is small, the exact terminal state remains weakly identified, and DRO "
            "inventory distribution is already close to the realized target. Two of three representative cuts "
            "rank the target direction correctly; one mismatch is retained but is insufficient to establish a "
            "systematic value-signal defect."
        ),
        14: (
            "Even at lf=6, the realized terminal state and full four-site vector remain uncertain. Inventory "
            "differences begin before information resolves, and all three representative DRO cuts rank the "
            "correct target station highest. The observed gap is therefore mainly consistent with a "
            "nonanticipative compromise, not a demonstrated physical or cut-direction failure."
        ),
        19: (
            "Early decisions are information-limited, but the positive-target top station becomes certain in "
            "the latest lf=6 observations while seven of eight feasible-unmet paths already have enough total "
            "inventory. One of three representative DRO cut nodes ranks another station above the realized/node "
            "target leader. This supports a mixed conclusion and a targeted, not global, cut/training audit."
        ),
    }
    for state in [12, 13, 14, 19]:
        paths = unique_paths[unique_paths["state_id"] == state]
        latest = latest_lf_row(stage_info, state)
        nodes = cut_nodes[(cut_nodes["method"] == "chi2_eta003") & (cut_nodes["state"] == state)]
        rows.append(
            {
                "state": state,
                "subset_definition": "Step05B4 class-C physical-feasible paths with actual terminal gap > 0",
                "subset_path_count": int(paths["path_id"].nunique()),
                "mean_actual_terminal_gap_kg": float(paths["actual_terminal_gap_kg"].mean()),
                "median_actual_terminal_gap_kg": float(paths["actual_terminal_gap_kg"].median()),
                "actual_total_inventory_sufficient_path_share": float(paths["actual_total_sufficient"].mean()),
                "first_material_saa_dro_inventory_divergence_decision_stage": first_divergence_stage(alignment, state),
                "latest_observed_lf": int(latest["lf"]),
                "latest_lf_path_stage_observation_count": int(latest["path_stage_observation_count"]),
                "latest_lf_mean_realized_terminal_state_probability": float(
                    latest["mean_realized_terminal_state_probability"]
                ),
                "latest_lf_exact_target_vector_observation_share": float(
                    latest["exact_target_vector_observation_share"]
                ),
                "latest_lf_positive_target_modal_top_site_probability": float(
                    latest["mean_positive_target_modal_top_site_probability"]
                ),
                "latest_lf_positive_target_top_site_certain_share": float(
                    latest["positive_target_top_site_certain_observation_share"]
                ),
                "latest_lf_mean_conditional_max_site_target_range_kg": float(
                    latest["mean_conditional_max_site_target_range_kg"]
                ),
                "latest_lf_mean_conditional_target_std_l2_kg": float(
                    latest["mean_conditional_target_std_l2_kg"]
                ),
                "representative_dro_cut_node_count": int(len(nodes)),
                "representative_cut_top_matches_realized_target_share": float(
                    nodes["top_marginal_matches_realized_target"].mean()
                ),
                "representative_cut_top_matches_node_mean_target_share": float(
                    nodes["top_marginal_matches_node_mean_target"].mean()
                ),
                "representative_cut_mean_marginal_value_range": float(nodes["marginal_value_range"].mean()),
                "final_classification": CLASSIFICATION[state],
                "classification_rationale": rationale[state],
            }
        )
    return pd.DataFrame(rows)


def build_manifest(out: Path) -> str:
    rows = []
    for path in sorted(out.iterdir(), key=lambda item: item.name.lower()):
        if not path.is_file() or path.name == "LARGE_FILE_MANIFEST.md":
            continue
        rows.append((path.name, path.stat().st_size, sha256_file(path)))
    lines = [
        "# LARGE_FILE_MANIFEST",
        "",
        "Files at or above 1,000,000 bytes are detailed local-only audit evidence.",
        "No MAT file, new OOS sample, cut library, training output, or prepared MSP input was created.",
        "",
        "| file | size_bytes | sha256 | disposition |",
        "|---|---:|---|---|",
    ]
    for name, size, digest in rows:
        disposition = "local_only_detailed_audit" if size >= 1_000_000 else "lightweight_audit_output"
        lines.append(f"| {name} | {size} | {digest} | {disposition} |")
    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-id", default="run-001")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    out = repo / "results/task-002-stage2b-b3-smoke/62-terminal-loh-information-revelation-audit" / args.run_id
    required = [
        "total_capacity_gap_summary.csv", "clairvoyant_lp_scope_audit.txt",
        "history_node_terminal_state_map.csv", "history_node_terminal_loh_dispersion.csv",
        "stage_information_revelation_summary.csv", "selected_path_inventory_trace.csv",
        "selected_node_policy_alignment.csv", "cut_audit_request.csv",
        "existing_cut_value_signal_audit.csv", "prepare_integrity_audit.txt",
        "cut_value_signal_integrity_audit.txt",
    ]
    for name in required:
        if not (out / name).is_file():
            raise FileNotFoundError(out / name)
    final_outputs = [
        "state12_13_14_judgment.csv", "state19_feasible_subset_judgment.csv",
        "step05b5_judgment.txt", "README.md", "LARGE_FILE_MANIFEST.md",
        "final_integrity_audit.txt",
    ]
    for name in final_outputs:
        if (out / name).exists():
            raise RuntimeError(f"Refusing to overwrite existing final output: {out / name}")
    if "Prepare PASS: 1" not in (out / "prepare_integrity_audit.txt").read_text(encoding="utf-8"):
        raise RuntimeError("Prepare audit did not pass.")
    if "Cut audit PASS: 1" not in (out / "cut_value_signal_integrity_audit.txt").read_text(encoding="utf-8"):
        raise RuntimeError("Saved-cut audit did not pass.")

    capacity = pd.read_csv(out / "total_capacity_gap_summary.csv")
    node_map = pd.read_csv(out / "history_node_terminal_state_map.csv")
    dispersion = pd.read_csv(out / "history_node_terminal_loh_dispersion.csv")
    stage_info = pd.read_csv(out / "stage_information_revelation_summary.csv")
    trace = pd.read_csv(out / "selected_path_inventory_trace.csv")
    alignment = pd.read_csv(out / "selected_node_policy_alignment.csv")
    request = pd.read_csv(out / "cut_audit_request.csv")
    cuts = pd.read_csv(out / "existing_cut_value_signal_audit.csv")
    physical = pd.read_csv(
        repo / "results/task-002-stage2b-b3-smoke/61-terminal-loh-system-feasibility-audit/run-001/physical_feasibility_path_audit.csv"
    )

    # Independent mechanical checks.
    frequency_sum = node_map.groupby(["decision_stage", "current_k"])["outcome_frequency"].sum()
    if not np.allclose(frequency_sum.to_numpy(), 1.0, atol=1e-12):
        raise RuntimeError("History-node descendant frequencies do not sum to one.")
    if len(dispersion) != 4 * 289:
        raise RuntimeError("Expected 289 nodes x 4 station dispersion rows.")
    if len(request) != 24 or len(cuts) != 96:
        raise RuntimeError("Representative cut request/output row count changed.")
    if not np.all(cuts["total_cut_count"] > 0):
        raise RuntimeError("A representative model has no saved cuts.")
    if cuts["active_rhs_reconstruction_residual"].max() > 1e-10:
        raise RuntimeError("Saved active-cut reconstruction residual failed.")
    if set(capacity["state"]) != {16, 17, 18, 19}:
        raise RuntimeError("Capacity-gap state set changed.")
    physical = physical[physical["state_id"].isin([16, 17, 18, 19])].copy()
    physical["gap"] = np.maximum(
        0.0, physical["T_total_dro_kg"] - physical["service_preserving_max_terminal_total_kg"]
    )
    recomputed = physical.groupby("state_id")["gap"].mean().reindex(capacity["state"]).to_numpy()
    if not np.allclose(recomputed, capacity["mean_gap_all_paths_kg"].to_numpy(), atol=1e-10):
        raise RuntimeError("Capacity-gap summary does not reproduce path-level evidence.")

    cut_nodes = node_level_cut_summary(cuts)
    judgments = build_judgments(stage_info, alignment, trace, cut_nodes)
    judgments[judgments["state"].isin([12, 13, 14])].to_csv(
        out / "state12_13_14_judgment.csv", index=False, float_format="%.15g"
    )
    judgments[judgments["state"] == 19].to_csv(
        out / "state19_feasible_subset_judgment.csv", index=False, float_format="%.15g"
    )

    cmap = capacity.set_index("state")
    jmap = judgments.set_index("state")
    cut_dro = cut_nodes[cut_nodes["method"] == "chi2_eta003"]
    cut_match = cut_dro.groupby("state")["top_marginal_matches_realized_target"].mean()
    judgment_text = f"""Step-05B-5 bounded judgment

1. Service-preserving system-total capacity gaps
- State16: {int(cmap.loc[16,'total_insufficient_path_count'])}/{int(cmap.loc[16,'path_count'])} paths insufficient ({cmap.loc[16,'total_insufficient_path_share']:.2%}); conditional mean/median/q95/max gaps are {cmap.loc[16,'mean_gap_insufficient_paths_kg']:.6f}/{cmap.loc[16,'median_gap_insufficient_paths_kg']:.6f}/{cmap.loc[16,'q95_gap_insufficient_paths_kg']:.6f}/{cmap.loc[16,'max_gap_insufficient_paths_kg']:.6f} kg.
- State17: {int(cmap.loc[17,'total_insufficient_path_count'])}/{int(cmap.loc[17,'path_count'])} paths insufficient ({cmap.loc[17,'total_insufficient_path_share']:.2%}); conditional mean/median/q95/max gaps are {cmap.loc[17,'mean_gap_insufficient_paths_kg']:.6f}/{cmap.loc[17,'median_gap_insufficient_paths_kg']:.6f}/{cmap.loc[17,'q95_gap_insufficient_paths_kg']:.6f}/{cmap.loc[17,'max_gap_insufficient_paths_kg']:.6f} kg.
- State18: {int(cmap.loc[18,'total_insufficient_path_count'])}/{int(cmap.loc[18,'path_count'])} paths insufficient ({cmap.loc[18,'total_insufficient_path_share']:.2%}); conditional mean/median/q95/max gaps are {cmap.loc[18,'mean_gap_insufficient_paths_kg']:.6f}/{cmap.loc[18,'median_gap_insufficient_paths_kg']:.6f}/{cmap.loc[18,'q95_gap_insufficient_paths_kg']:.6f}/{cmap.loc[18,'max_gap_insufficient_paths_kg']:.6f} kg.
- State19: {int(cmap.loc[19,'total_insufficient_path_count'])}/{int(cmap.loc[19,'path_count'])} paths insufficient ({cmap.loc[19,'total_insufficient_path_share']:.2%}); conditional mean/median/q95/max gaps are {cmap.loc[19,'mean_gap_insufficient_paths_kg']:.6f}/{cmap.loc[19,'median_gap_insufficient_paths_kg']:.6f}/{cmap.loc[19,'q95_gap_insufficient_paths_kg']:.6f}/{cmap.loc[19,'max_gap_insufficient_paths_kg']:.6f} kg.
- These state16/17/18 paths and the insufficient state19 subset are class E: system-total type. This is not an HTT spatial-physics conclusion.

2. Information-scope correction
- Step-05B-4 is an ex-post perfect-information diagnostic: it reoptimizes every pre-terminal decision after the entire OOS path, terminal state, target vector, and realized ordinary-service quantities are known.
- It proves physical feasibility with clairvoyance, not policy attainability under sequential information. The true FA-MSP exogenous information node is (decision stage t, current Markov state k), with inventory x as the endogenous state.

3. Information revelation and policy timing
- For state12/13/14 feasible-unmet paths, the exact target-vector share remains zero through every observed lf=1..6 node. At their latest lf=6 observations, the realized terminal-state probabilities are only {jmap.loc[12,'latest_lf_mean_realized_terminal_state_probability']:.2%}, {jmap.loc[13,'latest_lf_mean_realized_terminal_state_probability']:.2%}, and {jmap.loc[14,'latest_lf_mean_realized_terminal_state_probability']:.2%}; mean maximum site-target ranges remain {jmap.loc[12,'latest_lf_mean_conditional_max_site_target_range_kg']:.3f}, {jmap.loc[13,'latest_lf_mean_conditional_max_site_target_range_kg']:.3f}, and {jmap.loc[14,'latest_lf_mean_conditional_max_site_target_range_kg']:.3f} kg.
- SAA/DRO station inventories begin materially diverging at decision stage 2 for all four states, before the final target vector is resolved. Much of the later difference is therefore compatible with nonanticipativity rather than evidence of an avoidable ex-post allocation mistake.
- State19 is different in degree: on the feasible-unmet subset, the positive-target top station is certain on all latest lf=6 observations, but the exact terminal state remains only {jmap.loc[19,'latest_lf_mean_realized_terminal_state_probability']:.2%} likely and secondary-site/magnitude dispersion remains material.

4. Existing saved-cut value signals
- Existing workspaces were sufficient for a limited read-only audit. No solve or new cut was used. The representative SAA models contain 1112 saved cuts and the representative DRO models contain 1198 saved cuts.
- DRO top-marginal station agrees with the realized target leader in {cut_match.loc[12]:.0%} of state12, {cut_match.loc[13]:.0%} of state13, {cut_match.loc[14]:.0%} of state14, and {cut_match.loc[19]:.0%} of state19 representative nodes.
- State12 and state14 show no representative top-direction cut defect. State13 retains one mismatched representative node but has only 11 feasible-unmet paths and already-close inventory distribution. State19 retains one mismatched late representative node after the top-site direction becomes clear, which justifies targeted follow-up.

5. Final classifications
- State12: A information type.
- State13: A information type.
- State14: A information type.
- State19 physical-feasible/actual-unmet subset: C mixed type.
- State16/17/18 and the total-insufficient state19 subset: E system-total type.

6. Next step
- Do not globally retrain or change 200/2000 based on this audit.
- If further work is authorized, first perform a narrowly targeted state19 late-node cut/training-budget audit, especially the representative node where site2 marginal value exceeds site1 despite site1 leading the realized and node-mean targets.
- State12/13/14 do not presently justify a full retraining campaign; their ex-post gaps are mainly explained by unresolved target-vector information and the saved cuts generally point in the correct station direction.
"""
    (out / "step05b5_judgment.txt").write_text(judgment_text, encoding="utf-8")

    readme = f"""# Step-05B-5 TerminalLOH information-revelation audit

Accepted read-only audit on the frozen baseline `06f10864f36a6358eb671632ce3e032ddf0ae97e`.

## Scope

- No MSP training, resampling, forward/backward pass, new cut, TerminalLOH change, or 200/2000 change.
- Common OOS: 10000x8, SHA-256 `6e4ed488423e3cbb838c4a6f8b45019cf4ecf32a82850880399a08aafc7aff85`.
- Information nodes use the true recombining FA-MSP exogenous state `(decision stage t, current Markov state k)`. The complete path or future terminal state is never used to define a node.
- All descendant frequencies use every frozen OOS path reaching that node. No-terminal descendants are retained as outcome zero with zero TerminalLOH.

## Key distinction

Step-05B-4's physical LP is clairvoyant: it knows the realized full path and terminal target before jointly reoptimizing earlier hydrogen flows. Its feasibility result cannot be interpreted as proof that the sequential FA-MSP policy had the same information.

## Information metrics

- `outcome_frequency`: empirical probability of a particular future outcome at `(t,k)`.
- `conditional_terminal_target_range`: station target range across terminal-state descendants, including valid zero-Target TerminalLOH states.
- `positive_target_modal_top_site_probability`: among descendants with a positive TerminalLOH vector, probability of the modal highest-target station.
- Exact-vector and top-site-certainty shares require exact equality within numerical tolerance; no arbitrary confidence threshold is used.

## Saved-cut audit boundary

The existing saved affine cuts are evaluated directly at archived replay inventory points. The maximum existing cut RHS identifies the active face. When multiple cuts tie, the first is reported and min/max/mean marginal values across tied cuts are retained. The audit covers 12 representative information nodes and is not a global proof about every saved cut.

The representative SAA models contain 1112 saved cuts and the representative eta=0.03 DRO models contain 1198 saved cuts.

## Output guide

- `total_capacity_gap_summary.csv`: system-total gap distribution for states16-19.
- `clairvoyant_lp_scope_audit.txt`: exact information boundary of Step-05B-4.
- `history_node_terminal_state_map.csv`: 289 information nodes and empirical descendant outcomes.
- `history_node_terminal_loh_dispersion.csv`: site-level mean/min/max/std/range by node.
- `stage_information_revelation_summary.csv`: lf=1..6 information curves for all OOS and selected subsets.
- `selected_path_inventory_trace.csv`: paired SAA/DRO inventory, production, ordinary service, and station allocation with node information.
- `selected_node_policy_alignment.csv`: stage/node aggregation of information and inventory alignment.
- `existing_cut_value_signal_audit.csv`: existing active-cut marginal value evidence.
- `state12_13_14_judgment.csv` and `state19_feasible_subset_judgment.csv`: bounded A/B/C/D classifications.
- `step05b5_judgment.txt`: final interpretation and next-step recommendation.

Final classifications: state12/state13/state14 are A information type; the physically feasible but unmet state19 subset is C mixed type; system-total-insufficient state16/17/18/state19 paths are E system-total type.
"""
    (out / "README.md").write_text(readme, encoding="utf-8")

    integrity = f"""Step-05B-5 final integrity audit

History nodes: {node_map[['decision_stage','current_k']].drop_duplicates().shape[0]}
Node-outcome rows: {len(node_map)}
Node-site dispersion rows: {len(dispersion)}
Selected paired trace rows: {len(trace)}
Cut request rows: {len(request)}
Cut site rows: {len(cuts)}
Maximum node probability-sum error: {float(np.max(np.abs(frequency_sum.to_numpy()-1.0))):.12g}
Maximum active-cut RHS reconstruction residual: {cuts.active_rhs_reconstruction_residual.max():.12g}
Capacity-gap path-level reproduction maximum error: {float(np.max(np.abs(recomputed-capacity.mean_gap_all_paths_kg.to_numpy()))):.12g}
Core MSP was not called or modified.
Final PASS: 1
"""
    (out / "final_integrity_audit.txt").write_text(integrity, encoding="utf-8")
    (out / "LARGE_FILE_MANIFEST.md").write_text(build_manifest(out), encoding="utf-8")
    print(f"Step-05B-5 finalizer PASS: {out}")
    print(judgments[["state", "subset_path_count", "mean_actual_terminal_gap_kg", "final_classification"]].to_string(index=False))


if __name__ == "__main__":
    main()
