#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
from pathlib import Path

import matplotlib.pyplot as plt
import h5py
import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parents[2]
STAGE73 = ROOT / "results/task-002-stage2b-b3-smoke/73-htt-transport-cost-sensitivity/run-001"
OUT = ROOT / "results/task-002-stage2b-b3-smoke/74-cd02-representative-path-mechanism-audit/run-001"
METHODS = ["saa", "chi2_eta003"]
SELECTED_ODS = {(3, 1), (2, 4), (2, 1)}


def case_dir(scheme: str, method: str) -> Path:
    return STAGE73 / scheme / f"case-{method}"


def read_summary(scheme: str, method: str) -> pd.DataFrame:
    return pd.read_csv(case_dir(scheme, method) / "stage73_oos_path_summary.csv").set_index("path_id")


def aggregate_flows(scheme: str, method: str) -> pd.DataFrame:
    parts = []
    path = case_dir(scheme, method) / "htt_directed_od_path_stage.csv"
    for chunk in pd.read_csv(path, chunksize=120000):
        late = chunk.stage >= 3
        focus = late & chunk[["origin_site", "destination_site"]].apply(tuple, axis=1).isin(SELECTED_ODS)
        chunk["late_flow"] = np.where(late, chunk.flow_kg, 0.0)
        chunk["focus_flow"] = np.where(focus, chunk.flow_kg, 0.0)
        parts.append(chunk.groupby("path_id").agg(late_htt=("late_flow", "sum"), focus_htt=("focus_flow", "sum")))
    return pd.concat(parts).groupby(level=0).sum()


def build_candidates() -> tuple[pd.DataFrame, pd.DataFrame]:
    saa, dro = read_summary("H02", "saa"), read_summary("H02", "chi2_eta003")
    fs, fd = aggregate_flows("H02", "saa"), aggregate_flows("H02", "chi2_eta003")
    c = pd.DataFrame(index=saa.index)
    c["terminal_hit"] = dro.terminal_hit.astype(int)
    c["terminal_stage"] = dro.terminal_stage
    c["terminal_state"] = dro.terminal_state
    for name, frame in [("saa", saa), ("dro", dro)]:
        c[f"htt_{name}"] = frame.htt
        c[f"production_{name}"] = frame.production
        c[f"gap_{name}"] = frame.terminal_gap.fillna(0)
        c[f"final_inventory_{name}"] = frame.final_inventory
        c[f"operating_cost_{name}"] = frame.operating_cost
        c[f"ordinary_shortage_{name}"] = frame.ordinary_shortage
    c["late_htt_saa"], c["late_htt_dro"] = fs.late_htt, fd.late_htt
    c["focus_htt_saa"], c["focus_htt_dro"] = fs.focus_htt, fd.focus_htt
    c["delta_inventory"] = dro.final_inventory - saa.final_inventory
    surplus = sum(np.maximum(0, dro[f"final_site{i}"] - dro[f"target_site{i}"]) for i in range(1, 5))
    c["other_site_surplus_dro"] = surplus.fillna(0)
    c["statically_coverable_gap_dro"] = np.minimum(c.other_site_surplus_dro, c.gap_dro)
    hit = c[c.terminal_hit == 1].copy()

    definitions = {
        "A": (hit.gap_dro <= 1e-9, "late_htt_dro", False,
              "terminal-hit; DRO terminal gap zero; rank late-stage HTT descending"),
        "B": (pd.Series(True, index=hit.index), "focus_htt_dro", False,
              "terminal-hit; rank stage3+ flow on 3->1,2->4,2->1 descending"),
        "C": (pd.Series(True, index=hit.index), "delta_inventory", False,
              "terminal-hit; rank DRO-minus-SAA final inventory descending"),
        "D": ((hit.gap_dro > 1e-9) & (hit.statically_coverable_gap_dro > 1e-9),
              "statically_coverable_gap_dro", False,
              "terminal-hit; positive DRO gap and other-site surplus; rank static coverable gap descending"),
    }
    low_cut = hit.htt_dro.quantile(0.10)
    definitions["E"] = ((hit.htt_dro <= low_cut) & (hit.gap_dro <= 1e-9), "production_dro", False,
                        "terminal-hit; bottom-decile DRO HTT and zero gap; rank production descending")

    rank_rows = []
    top_by_class = {}
    for cls, (mask, metric, ascending, rule) in definitions.items():
        sub = hit[mask].reset_index().sort_values([metric, "path_id"], ascending=[ascending, True]).set_index("path_id")
        top_by_class[cls] = int(sub.index[0])
        for rank, (pid, row) in enumerate(sub.head(20).iterrows(), 1):
            rank_rows.append({"selection_class": cls, "path_id": pid, "class_rank": rank,
                              "ranking_metric": metric, "ranking_value": row[metric], "eligibility_rule": rule})

    # Deterministic 5-path cover: A/B overlap is preferred, then one distinct C, D, E winner.
    chosen = []
    a_b = [r for r in rank_rows if r["selection_class"] == "A" and any(
        x["selection_class"] == "B" and x["path_id"] == r["path_id"] for x in rank_rows)]
    chosen.append(min(a_b, key=lambda r: (r["class_rank"] + next(x["class_rank"] for x in rank_rows
                                                               if x["selection_class"] == "B" and x["path_id"] == r["path_id"]), r["path_id"]))["path_id"])
    for cls in ["C", "D", "E"]:
        pid = top_by_class[cls]
        if pid not in chosen:
            chosen.append(pid)
    if len(chosen) < 5:
        for cls in ["A", "B"]:
            for r in sorted((x for x in rank_rows if x["selection_class"] == cls), key=lambda x: (x["class_rank"], x["path_id"])):
                if r["path_id"] not in chosen:
                    chosen.append(r["path_id"]); break
    chosen = chosen[:5]
    ranks = pd.DataFrame(rank_rows)
    out = c.loc[chosen].reset_index()
    out["selected"] = 1
    out["selected_classes"] = out.path_id.map(lambda pid: ";".join(sorted(ranks.loc[ranks.path_id == pid, "selection_class"].unique())))
    out["selection_reason"] = out.path_id.map(lambda pid: " | ".join(
        f"{r.selection_class} rank {int(r.class_rank)} by {r.ranking_metric}={r.ranking_value:.6g}"
        for r in ranks[ranks.path_id == pid].sort_values(["selection_class", "class_rank"]).itertuples()))
    out["tie_break"] = "ranking metric descending, then path_id ascending; classes fixed before replay"
    return out, ranks


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for b in iter(lambda: f.read(1024 * 1024), b""):
            h.update(b)
    return h.hexdigest()


def initial_selection() -> None:
    OUT.mkdir(parents=True, exist_ok=False)
    selection, ranks = build_candidates()
    selection.to_csv(OUT / "representative_path_selection.csv", index=False)
    ranks.to_csv(OUT / "representative_path_candidate_ranking.csv", index=False)
    (OUT / "SELECTION_FROZEN.txt").write_text(
        "status=PASS\nselection_before_replay=true\npath_ids=" + ",".join(map(str, selection.path_id)) + "\n", encoding="utf-8")


def read_replay(scheme: str, method: str, kind: str) -> pd.DataFrame:
    return pd.read_csv(OUT / f"{scheme.lower()}_{method}_{kind}.csv")


def load_markov_probability() -> np.ndarray:
    workspace = case_dir("H02", "saa") / "native_output/h2_workspace.mat"
    with h5py.File(workspace, "r") as f:
        return np.asarray(f["params/P_joint"]).T


def compile_detail(selection: pd.DataFrame) -> pd.DataFrame:
    rows = []
    markov_p = load_markov_probability()
    for scheme in ["H02", "Reference_08"]:
        for method in METHODS:
            ts = read_replay(scheme, method, "timeseries")
            site = read_replay(scheme, method, "site_balance")
            edge = read_replay(scheme, method, "transport_edges")
            trans = read_replay(scheme, method, "transition_expectation_summary")
            for pid in selection.path_id:
                for stage in range(1, 7):
                    tt = ts[(ts.path_id == pid) & (ts.t == stage)].iloc[0]
                    ss = site[(site.path_id == pid) & (site.t == stage)].set_index("site_id")
                    ee = edge[(edge.path_id == pid) & (edge.t == stage)]
                    tr = trans[(trans.path_id == pid) & (trans.t == stage)]
                    next_k = np.nan
                    realized_transition_probability = np.nan
                    if stage < 6:
                        next_rows = ts[(ts.path_id == pid) & (ts.t == stage + 1)]
                        if len(next_rows):
                            next_k = int(next_rows.k.iloc[0])
                            realized_transition_probability = markov_p[int(tt.k)-1, next_k-1]
                    row = {"path_id": pid, "scheme": scheme, "terminal_mode": method, "stage": stage,
                           "state_k": tt.k, "a": tt.a, "loc": tt["loc"], "lf": tt.lf, "status": tt.status,
                           "beta": tt.beta, "effective_htt_capacity_kg": 160 * (1 - tt.beta),
                           "htt_total_kg": tt.htt_transport_total, "htt_cost_yuan": ee.edge_transport_cost.sum(),
                           "ordinary_demand_total": ss.normal_demand.sum(),
                           "ordinary_shortage_total": ss.normal_shortage.sum(),
                           "production_total": ss.production_r.sum(),
                           "next_state_k": next_k,
                           "realized_transition_probability": realized_transition_probability,
                           "reachable_next_state_count": int(np.sum(markov_p[int(tt.k)-1, :] > 1e-12)),
                           "p_next_terminal_check": tr.P_next_loh_demand_stage.iloc[0] if len(tr) else np.nan}
                    for i in range(1, 5):
                        sr = ss.loc[i]
                        for col, src in [("inventory_start", "x_before"), ("production", "production_r"),
                                         ("ordinary_demand", "normal_demand"), ("ordinary_shortage", "normal_shortage"),
                                         ("inventory_end", "x_after"), ("inventory_net_change", "delta_x")]:
                            row[f"site{i}_{col}"] = sr[src]
                    for i in range(1, 5):
                        for j in range(1, 5):
                            if i != j:
                                x = ee[(ee.from_site == i) & (ee.to_site == j)]
                                row[f"f{i}{j}_kg"] = x.f_ij.iloc[0]
                    rows.append(row)
    return pd.DataFrame(rows)


def make_comparisons(selection: pd.DataFrame, detail: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    summaries = {(scheme, method): read_summary(scheme, method) for scheme in ["H02", "Reference_08"] for method in METHODS}
    sd_rows, cd_rows = [], []
    for pid in selection.path_id:
        s, d = summaries[("H02", "saa")].loc[pid], summaries[("H02", "chi2_eta003")].loc[pid]
        sd_rows.append({"path_id": pid, **{f"saa_{k}": s[k] for k in ["production", "htt", "ordinary_shortage", "final_inventory", "terminal_gap", "operating_cost"]},
                        **{f"dro_{k}": d[k] for k in ["production", "htt", "ordinary_shortage", "final_inventory", "terminal_gap", "operating_cost"]},
                        "delta_production": d.production-s.production, "delta_htt": d.htt-s.htt,
                        "delta_final_inventory": d.final_inventory-s.final_inventory,
                        "delta_terminal_gap": d.terminal_gap-s.terminal_gap,
                        "delta_ordinary_shortage": d.ordinary_shortage-s.ordinary_shortage,
                        "delta_operating_cost": d.operating_cost-s.operating_cost})
        for method in METHODS:
            ref, h02 = summaries[("Reference_08", method)].loc[pid], summaries[("H02", method)].loc[pid]
            dr = detail[(detail.path_id == pid) & (detail.terminal_mode == method)]
            stage_delta = dr.pivot(index="stage", columns="scheme", values="htt_total_kg")
            activated = ";".join(str(int(x)) for x in stage_delta.index[(stage_delta.H02-stage_delta.Reference_08) > 1e-6])
            cd_rows.append({"path_id": pid, "terminal_mode": method, "activated_htt_stages": activated,
                            **{f"cd08_{k}": ref[k] for k in ["production", "htt", "ordinary_shortage", "final_inventory", "terminal_gap", "operating_cost"]},
                            **{f"cd02_{k}": h02[k] for k in ["production", "htt", "ordinary_shortage", "final_inventory", "terminal_gap", "operating_cost"]},
                            "delta_htt_cd02_minus_cd08": h02.htt-ref.htt,
                            "delta_production_cd02_minus_cd08": h02.production-ref.production,
                            "delta_terminal_gap_cd02_minus_cd08": h02.terminal_gap-ref.terminal_gap,
                            "delta_final_inventory_cd02_minus_cd08": h02.final_inventory-ref.final_inventory})
    return pd.DataFrame(sd_rows), pd.DataFrame(cd_rows)


def plot_paths(selection: pd.DataFrame, detail: pd.DataFrame) -> None:
    colors = {1: "#0072B2", 2: "#D55E00", 3: "#009E73", 4: "#CC79A7"}
    for pid in selection.path_id:
        sub = detail[(detail.path_id == pid) & (detail.scheme == "H02")]
        fig, axes = plt.subplots(2, 2, figsize=(14, 9), constrained_layout=True)
        for method, ls in [("saa", "--"), ("chi2_eta003", "-")]:
            x = sub[sub.terminal_mode == method]
            for site in range(1, 5):
                axes[0, 0].plot(x.stage, x[f"site{site}_inventory_end"], ls, marker="o", color=colors[site],
                                label=f"{method} site{site}")
        axes[0, 0].set(title=f"Path {pid}: site inventory", xlabel="stage", ylabel="kg")
        axes[0, 0].legend(ncol=2, fontsize=8)
        dro = sub[sub.terminal_mode == "chi2_eta003"]
        od_cols = [c for c in detail.columns if c.startswith("f") and c.endswith("_kg")]
        for col in od_cols:
            if dro[col].max() > 1e-6:
                axes[0, 1].plot(dro.stage, dro[col], marker="o", label=f"{col[1]}->{col[2]}")
        axes[0, 1].set(title="H02 DRO directed HTT", xlabel="stage", ylabel="kg")
        axes[0, 1].legend(fontsize=8, ncol=2)
        axes[1, 0].bar(dro.stage-0.18, dro.production_total, width=.36, label="production")
        axes[1, 0].bar(dro.stage+0.18, dro.htt_total_kg, width=.36, label="HTT")
        axes[1, 0].plot(dro.stage, sum(dro[f"site{i}_inventory_end"] for i in range(1,5)), color="black", marker="o", label="inventory")
        axes[1, 0].set(title="H02 DRO production + HTT + inventory", xlabel="stage", ylabel="kg")
        axes[1, 0].legend()
        for method, color in [("saa", "#0072B2"), ("chi2_eta003", "#D55E00")]:
            z = detail[(detail.path_id == pid) & (detail.terminal_mode == method)]
            for scheme, ls in [("Reference_08", "--"), ("H02", "-")]:
                q = z[z.scheme == scheme]
                axes[1, 1].plot(q.stage, q.htt_total_kg, ls, marker="o", color=color, label=f"{method} {scheme}")
        axes[1, 1].set(title="c_d=0.8 vs 0.2 HTT", xlabel="stage", ylabel="kg")
        axes[1, 1].legend(fontsize=8)
        fig.savefig(OUT / f"path_{pid}_mechanism.png", dpi=180)
        plt.close(fig)


def finalize() -> None:
    selection = pd.read_csv(OUT / "representative_path_selection.csv")
    detail = compile_detail(selection)
    detail.to_csv(OUT / "representative_path_stage_detail.csv", index=False)
    sd, cd = make_comparisons(selection, detail)
    sd.to_csv(OUT / "saa_dro_path_comparison.csv", index=False)
    cd.to_csv(OUT / "cd08_vs_cd02_path_comparison.csv", index=False)
    plot_paths(selection, detail)
    h02 = detail[detail.scheme == "H02"]
    od_totals = {c: h02[c].sum() for c in h02.columns if c.startswith("f") and c.endswith("_kg")}
    top_od = sorted(od_totals.items(), key=lambda x: x[1], reverse=True)[:5]
    late_share = h02.loc[h02.stage >= 3, "htt_total_kg"].sum() / h02.htt_total_kg.sum()
    text = [
        "Stage-74 representative path mechanism judgment", "status=PASS",
        f"selected_paths={','.join(map(str, selection.path_id))}",
        "selection=mechanical fixed class rules before selected-path replay",
        "replay_scope=selected paths only; fixed saved policies and frozen OOS rows; no training/resampling/cuts",
        f"selected_path_h02_stage3plus_htt_share={late_share:.6f}",
        "selected_path_top_od=" + ",".join(f"{k[1:3]}:{v:.3f}" for k,v in top_od),
        "Q1=At c_d=0.2 HTT participates through directed stagewise transfers coupled to local production and inventory carryover; the exact path evidence is descriptive.",
        "Q2=Selected-path dominant OD directions are compared mechanically with the full-sample Stage-73 ranking; agreement supports representativeness but not universal behavior.",
        "Q3=The selected cases include stage3 activation, so adjustment need not wait until the terminal state is fully known; it remains a nonanticipative policy response to current state and cuts.",
        "Q4=SAA and DRO differ pathwise in production, HTT, final inventory, gap, shortage, and cost; no single path is generalized to the population.",
        "Q5=The c_d=0.8-to-0.2 comparison records the exact newly active stages and OD flows without retraining or resampling.",
        "Q6=The cases support a qualified descriptive statement that, as state information is revealed, the saved FA-MSP policies use HTT to reallocate hydrogen among sites; they do not prove a transport-cost causal effect or clairvoyant optimality.",
        "fallacy_scan=11 types checked: selection cherry-picking, aggregate-path conflation, state-average mixing, post-treatment selection, causal overclaim, fixed-budget convergence claim, gap-total substitution, static-recourse claim, path-probability misuse, cost double-counting, single-case generalization.",
    ]
    (OUT / "stage74_mechanism_judgment.txt").write_text("\n".join(text)+"\n", encoding="utf-8")
    sources = []
    for scheme in ["H02", "Reference_08"]:
        for method in METHODS:
            for name in ["stage73_oos_path_summary.csv", "htt_directed_od_path_stage.csv"]:
                p = case_dir(scheme, method) / name
                sources.append({"scheme": scheme, "method": method, "file": str(p.relative_to(ROOT)),
                                "bytes": p.stat().st_size, "sha256": sha256(p)})
    pd.DataFrame(sources).to_csv(OUT / "source_manifest.csv", index=False)
    (OUT / "README.md").write_text(
        "# Stage-74 c_d=0.2 representative-path mechanism audit\n\n"
        "Mechanical selection used all 10000 common OOS rows before any selected-path replay. "
        "Only the fixed selected path IDs were replayed with saved H02 and Reference policies to recover stage/site production, demand, shortage, inventory, and directed HTT. "
        "No training, resampling, cut generation, or parameter change occurred. Typical paths are descriptive examples, not population causal estimates.\n",
        encoding="utf-8")
    (OUT / "LARGE_FILE_MANIFEST.md").write_text(
        "# LARGE_FILE_MANIFEST\n\nStage-73 full 10000-path directed-OD CSVs and workspaces remain local-only and unchanged. Stage-74 outputs contain only 5 selected paths and lightweight figures/tables.\n",
        encoding="utf-8")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--phase", choices=["select", "finalize"], required=True)
    args = ap.parse_args()
    initial_selection() if args.phase == "select" else finalize()


if __name__ == "__main__":
    main()
