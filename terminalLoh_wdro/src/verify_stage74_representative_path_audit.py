#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[2]
S73 = ROOT / "results/task-002-stage2b-b3-smoke/73-htt-transport-cost-sensitivity/run-001"
OUT = ROOT / "results/task-002-stage2b-b3-smoke/74-cd02-representative-path-mechanism-audit/run-001"


def main() -> None:
    required = ["representative_path_selection.csv", "representative_path_stage_detail.csv",
                "saa_dro_path_comparison.csv", "cd08_vs_cd02_path_comparison.csv",
                "stage74_mechanism_judgment.txt", "README.md", "LARGE_FILE_MANIFEST.md",
                "source_manifest.csv", "SELECTED_PATH_REPLAY_DONE.txt"]
    missing = [x for x in required if not (OUT / x).is_file()]
    if missing:
        raise RuntimeError(f"missing outputs: {missing}")
    sel = pd.read_csv(OUT / "representative_path_selection.csv")
    if len(sel) != 5 or sel.path_id.tolist() != [5380, 986, 2017, 9114, 6826]:
        raise RuntimeError("fixed mechanical selection identity failed")
    detail = pd.read_csv(OUT / "representative_path_stage_detail.csv")
    if len(detail) != 5 * 4 * 6:
        raise RuntimeError(f"stage detail row count {len(detail)}")
    if detail.groupby(["path_id", "scheme", "terminal_mode"]).stage.nunique().min() != 6:
        raise RuntimeError("stage coverage failed")

    max_balance = 0.0
    max_htt = 0.0
    max_cost = 0.0
    max_summary = 0.0
    for scheme in ["H02", "Reference_08"]:
        for method in ["saa", "chi2_eta003"]:
            d = detail[(detail.scheme == scheme) & (detail.terminal_mode == method)]
            for site in range(1, 5):
                inflow = sum(d[f"f{j}{site}_kg"] for j in range(1, 5) if j != site)
                outflow = sum(d[f"f{site}{j}_kg"] for j in range(1, 5) if j != site)
                served = d[f"site{site}_ordinary_demand"] - d[f"site{site}_ordinary_shortage"]
                rebuilt = d[f"site{site}_inventory_start"] + d[f"site{site}_production"] + inflow - outflow - served
                normal = d.status == "normal"
                max_balance = max(max_balance, float(np.max(np.abs(rebuilt[normal] - d.loc[normal, f"site{site}_inventory_end"]))))
            rebuilt_htt = sum(d[c] for c in d.columns if c.startswith("f") and c.endswith("_kg"))
            max_htt = max(max_htt, float(np.max(np.abs(rebuilt_htt - d.htt_total_kg))))
            edge = pd.read_csv(OUT / f"{scheme.lower()}_{method}_transport_edges.csv")
            edge_cost = edge.groupby(["path_id", "t"]).edge_transport_cost.sum()
            for row in d.itertuples():
                max_cost = max(max_cost, abs(row.htt_cost_yuan - edge_cost.loc[(row.path_id, row.stage)]))

            original = pd.read_csv(S73 / scheme / f"case-{method}" / "stage73_oos_path_summary.csv").set_index("path_id")
            for pid in sel.path_id:
                x = d[d.path_id == pid]
                normal = x.status == "normal"
                final = sum(x.iloc[-1][f"site{i}_inventory_end"] for i in range(1, 5))
                values = {
                    "production": x.loc[normal, "production_total"].sum(),
                    "htt": x.loc[normal, "htt_total_kg"].sum(),
                    "ordinary_shortage": x.loc[normal, "ordinary_shortage_total"].sum(),
                    "final_inventory": final,
                }
                max_summary = max(max_summary, max(abs(values[k] - original.loc[pid, k]) for k in values))

    probs = detail.realized_transition_probability.dropna()
    if ((probs < -1e-12) | (probs > 1 + 1e-12)).any():
        raise RuntimeError("transition probability bounds failed")
    if max(max_balance, max_htt, max_cost, max_summary) > 1e-5:
        raise RuntimeError(f"closure failed balance={max_balance} htt={max_htt} cost={max_cost} summary={max_summary}")
    pngs = list(OUT.glob("path_*_mechanism.png"))
    if len(pngs) != 5 or min(p.stat().st_size for p in pngs) < 10000:
        raise RuntimeError("figure completeness failed")
    text = (OUT / "stage74_mechanism_judgment.txt").read_text(encoding="utf-8")
    for token in ["fixed saved policies", "no training/resampling/cuts", "do not prove"]:
        if token not in text:
            raise RuntimeError(f"interpretation boundary missing: {token}")
    audit = f"""Stage-74 mechanical verification
status=PASS
selected_path_ids={sel.path_id.tolist()}
selection_count={len(sel)}
detail_rows={len(detail)}
cases=4
stages_per_case_path=6
max_site_balance_error_kg={max_balance:.12g}
max_directed_htt_closure_error_kg={max_htt:.12g}
max_transport_cost_closure_error_yuan={max_cost:.12g}
max_replay_vs_stage73_summary_error={max_summary:.12g}
transition_probability_bounds=PASS
figure_count={len(pngs)}
training=false
resampling=false
new_cuts=false
causal_interpretation=NOT_ESTABLISHED
"""
    (OUT / "mechanical_verification.txt").write_text(audit, encoding="utf-8")
    print("STAGE74_VERIFY_PASS")


if __name__ == "__main__":
    main()
