from __future__ import annotations

import argparse
import hashlib
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd


ETA_DRO = 0.03
ELECTRICITY_PER_KG = 18.3315


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def safe_ratio(numerator: pd.Series, denominator: pd.Series, tolerance: float = 1e-10) -> pd.Series:
    out = pd.Series(np.nan, index=numerator.index, dtype=float)
    keep = denominator.abs() > tolerance
    out.loc[keep] = numerator.loc[keep] / denominator.loc[keep]
    return out


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while block := handle.read(1024 * 1024):
            digest.update(block)
    return digest.hexdigest()


def sha256_tree(path: Path) -> tuple[int, int, str]:
    files = sorted(item for item in path.rglob("*") if item.is_file())
    digest = hashlib.sha256()
    total_bytes = 0
    for item in files:
        relative = str(item.relative_to(path)).replace("\\", "/")
        file_hash = sha256_file(item)
        total_bytes += item.stat().st_size
        digest.update(relative.encode("utf-8"))
        digest.update(b"\0")
        digest.update(file_hash.encode("ascii"))
        digest.update(b"\n")
    return len(files), total_bytes, digest.hexdigest()


def load_case_tables(work_dir: Path) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    results, certificates, worst = [], [], []
    for case_id in range(1, 71):
        case_dir = work_dir / "optimization_cases" / f"case-{case_id:03d}"
        require((case_dir / "CASE_COMPLETE.txt").is_file(), f"Missing completion flag for case {case_id}")
        results.append(pd.read_csv(case_dir / "case_result.csv"))
        certificates.append(pd.read_csv(case_dir / "solver_certificate.csv"))
        worst.append(pd.read_csv(case_dir / "worst_probability_summary.csv"))
    return (
        pd.concat(results, ignore_index=True),
        pd.concat(certificates, ignore_index=True),
        pd.concat(worst, ignore_index=True),
    )


def state19_reproduction(work_dir: Path, results: pd.DataFrame, cert: pd.DataFrame) -> pd.DataFrame:
    repo = work_dir.parents[3]
    c5c = repo / "results/task-002-stage2b-b3-smoke/52-eta-response-saturation-audit/run-003"
    reference = pd.read_csv(c5c / "eta_optimization_results.csv")
    reference_cert = pd.read_csv(c5c / "solver_certificate.csv")
    rows = []
    for eta in (0.0, ETA_DRO):
        current = results[(results.state_id == 19) & np.isclose(results.eta, eta)].iloc[0]
        current_cert = cert[(cert.state_id == 19) & np.isclose(cert.eta, eta)].iloc[0]
        ref = reference[np.isclose(reference.eta, eta)].iloc[0]
        ref_cert = reference_cert[np.isclose(reference_cert.eta, eta)].iloc[0]
        t_diff = max(abs(float(current[f"T{i}_kg"]) - float(ref[f"T{i}_kg"])) for i in range(1, 5))
        row = {
            "state_id": 19,
            "eta": eta,
            "maximum_T_abs_difference_kg": t_diff,
            "total_inventory_abs_difference_kg": abs(current.TerminalLOH_total_kg - ref.TerminalLOH_total_kg),
            "mean_shortage_abs_difference_kg": abs(current.mean_shortage_kg - ref.nominal_mean_shortage_kg),
            "mean_EENS_abs_difference_kWh": abs(current.mean_EENS_kWh - ref.nominal_mean_EENS_kWh),
            "nominal_economic_cost_abs_difference_yuan": abs(
                current.nominal_total_economic_cost_yuan - ref.nominal_mean_economic_total_yuan
            ),
            "LB_abs_difference_yuan": abs(current_cert.LB_yuan - ref_cert.LB_yuan),
            "UB_abs_difference_yuan": abs(current_cert.UB_yuan - ref_cert.UB_yuan),
            "secondary_distance_abs_difference": abs(
                current.secondary_expected_service_distance - ref.secondary_expected_service_distance
            ),
        }
        row["reproduction_pass"] = (
            row["maximum_T_abs_difference_kg"] <= 1e-5
            and row["total_inventory_abs_difference_kg"] <= 1e-5
            and row["mean_shortage_abs_difference_kg"] <= 1e-7
            and row["mean_EENS_abs_difference_kWh"] <= 1e-6
            and row["nominal_economic_cost_abs_difference_yuan"] <= 1e-4
            and row["LB_abs_difference_yuan"] <= 1e-3
            and row["UB_abs_difference_yuan"] <= 1e-3
            and row["secondary_distance_abs_difference"] <= 1e-5
        )
        rows.append(row)
    audit = pd.DataFrame(rows)
    require(audit.reproduction_pass.all(), "State19 C5C reproduction failed")
    return audit


def make_comparison(results: pd.DataFrame) -> pd.DataFrame:
    saa = results[np.isclose(results.eta, 0.0)].copy().set_index("state_id")
    dro = results[np.isclose(results.eta, ETA_DRO)].copy().set_index("state_id")
    require(list(saa.index) == list(range(1, 36)), "SAA state order mismatch")
    require(list(dro.index) == list(range(1, 36)), "DRO state order mismatch")
    out = saa[["state_label", "intensity", "loc", "lfw"]].reset_index()
    for site in range(1, 5):
        out[f"SAA_T{site}_kg"] = saa[f"T{site}_kg"].to_numpy()
        out[f"ETA003_T{site}_kg"] = dro[f"T{site}_kg"].to_numpy()
        out[f"delta_T{site}_kg"] = dro[f"T{site}_kg"].to_numpy() - saa[f"T{site}_kg"].to_numpy()
    out["SAA_total_T_kg"] = saa.TerminalLOH_total_kg.to_numpy()
    out["ETA003_total_T_kg"] = dro.TerminalLOH_total_kg.to_numpy()
    out["delta_total_T_kg"] = out.ETA003_total_T_kg - out.SAA_total_T_kg
    out["relative_delta_total_T_percent"] = 100 * safe_ratio(out.delta_total_T_kg, out.SAA_total_T_kg)
    metric_map = {
        "mean_shortage_kg": "mean_shortage_kg",
        "mean_EENS_kWh": "mean_EENS_kWh",
        "shortage_q95_kg": "q95_shortage_kg",
        "shortage_q99_kg": "q99_shortage_kg",
        "shortage_q99_5_kg": "q99_5_shortage_kg",
        "max_shortage_kg": "max_shortage_kg",
        "nominal_total_economic_cost_yuan": "nominal_economic_cost_yuan",
        "local_hydrogen_preparation_cost_yuan": "preparation_cost_yuan",
        "nominal_expected_outage_loss_yuan": "nominal_outage_loss_yuan",
        "probability_positive_shortage": "positive_shortage_probability",
        "service_rate": "service_rate",
    }
    for source, label in metric_map.items():
        out[f"SAA_{label}"] = saa[source].to_numpy()
        out[f"ETA003_{label}"] = dro[source].to_numpy()
        out[f"delta_{label}"] = dro[source].to_numpy() - saa[source].to_numpy()
    out["avoided_nominal_outage_loss_yuan"] = -out.delta_nominal_outage_loss_yuan
    out["net_safety_premium_yuan"] = out.delta_nominal_economic_cost_yuan
    out["mean_EENS_improvement_kWh"] = -out.delta_mean_EENS_kWh
    out["q95_shortage_improvement_kg"] = -out.delta_q95_shortage_kg
    out["q99_shortage_improvement_kg"] = -out.delta_q99_shortage_kg
    out["q99_5_shortage_improvement_kg"] = -out.delta_q99_5_shortage_kg
    out["maximum_shortage_improvement_kg"] = -out.delta_max_shortage_kg
    out["mean_EENS_improvement_per_added_kg"] = safe_ratio(
        out.mean_EENS_improvement_kWh, out.delta_total_T_kg
    )
    out["q95_improvement_per_added_kg"] = safe_ratio(
        out.q95_shortage_improvement_kg, out.delta_total_T_kg
    )
    out["net_cost_per_restored_kWh"] = safe_ratio(
        out.delta_nominal_economic_cost_yuan, out.mean_EENS_improvement_kWh
    )
    out["maximum_abs_station_change_kg"] = out[[f"delta_T{i}_kg" for i in range(1, 5)]].abs().max(axis=1)
    out["any_station_inventory_decrease"] = (
        out[[f"delta_T{i}_kg" for i in range(1, 5)]] < -1e-6
    ).any(axis=1)
    out["total_inventory_increase_with_station_decrease"] = (
        (out.delta_total_T_kg > 1e-6) & out.any_station_inventory_decrease
    )
    return out


def correlation_table(comparison: pd.DataFrame) -> pd.DataFrame:
    risks = [
        "SAA_mean_shortage_kg",
        "SAA_mean_EENS_kWh",
        "SAA_positive_shortage_probability",
        "SAA_q95_shortage_kg",
        "SAA_q99_5_shortage_kg",
        "SAA_max_shortage_kg",
    ]
    responses = [
        "delta_total_T_kg",
        "delta_T1_kg",
        "delta_T2_kg",
        "delta_T3_kg",
        "delta_T4_kg",
        "mean_EENS_improvement_kWh",
        "q95_shortage_improvement_kg",
        "delta_nominal_economic_cost_yuan",
    ]
    rows = []
    for risk in risks:
        for response in responses:
            x = comparison[risk].astype(float)
            y = comparison[response].astype(float)
            rows.append(
                {
                    "risk_metric": risk,
                    "response_metric": response,
                    "state_count": len(comparison),
                    "pearson_correlation": x.corr(y, method="pearson"),
                    "spearman_correlation": x.corr(y, method="spearman"),
                    "interpretation": "descriptive association only; not causal",
                }
            )
    return pd.DataFrame(rows)


def representative_states(comparison: pd.DataFrame) -> pd.DataFrame:
    groups: list[pd.DataFrame] = []

    def add(name: str, frame: pd.DataFrame) -> None:
        piece = frame.head(5).copy()
        piece.insert(0, "representative_category", name)
        piece.insert(1, "category_rank", range(1, len(piece) + 1))
        groups.append(piece)

    add("TOP5_SAA_MEAN_EENS", comparison.sort_values("SAA_mean_EENS_kWh", ascending=False))
    add("TOP5_SAA_Q95_SHORTAGE", comparison.sort_values("SAA_q95_shortage_kg", ascending=False))
    add("TOP5_EXTRA_INVENTORY", comparison.sort_values("delta_total_T_kg", ascending=False))
    add("TOP5_MEAN_EENS_IMPROVEMENT", comparison.sort_values("mean_EENS_improvement_kWh", ascending=False))
    add("TOP5_Q95_IMPROVEMENT", comparison.sort_values("q95_shortage_improvement_kg", ascending=False))
    weak = comparison[comparison.delta_total_T_kg > 1e-6].sort_values(
        ["mean_EENS_improvement_kWh", "delta_total_T_kg"], ascending=[True, False]
    )
    add("TOP5_EXTRA_INVENTORY_WEAKEST_EENS_GAIN", weak)
    add("TOP5_NEAR_IDENTICAL_DECISIONS", comparison.sort_values("maximum_abs_station_change_kg"))
    flat = comparison[
        (comparison.delta_q99_5_shortage_kg.abs() <= 1e-8)
        & (comparison.delta_max_shortage_kg.abs() <= 1e-8)
    ].sort_values("SAA_mean_EENS_kWh", ascending=False)
    add("HIGH_RISK_Q995_AND_MAX_UNCHANGED", flat)
    return pd.concat(groups, ignore_index=True)


def make_plots(work_dir: Path, results: pd.DataFrame, comparison: pd.DataFrame) -> None:
    plt.rcParams.update({"figure.dpi": 140, "font.size": 8})
    states = comparison.state_id.to_numpy()
    saa = results[np.isclose(results.eta, 0)].sort_values("state_id")
    dro = results[np.isclose(results.eta, ETA_DRO)].sort_values("state_id")

    fig, ax = plt.subplots(figsize=(10, 4))
    ax.plot(states, comparison.SAA_total_T_kg, marker="o", ms=2.5, label="SAA")
    ax.plot(states, comparison.ETA003_total_T_kg, marker="o", ms=2.5, label="eta=0.03")
    ax.set(xlabel="Frozen state ID", ylabel="Total TerminalLOH (kg)")
    ax.grid(alpha=0.25); ax.legend(); fig.tight_layout()
    fig.savefig(work_dir / "saa_vs_eta003_total_terminal_loh_by_state.png"); plt.close(fig)

    def heatmap(frame: pd.DataFrame, name: str, title: str) -> None:
        data = frame[[f"T{i}_kg" for i in range(1, 5)]].to_numpy()
        fig, ax = plt.subplots(figsize=(7, 7))
        image = ax.imshow(data, aspect="auto", cmap="viridis")
        # Keep compatibility with the repository's older Matplotlib runtime,
        # where tick locations and labels must be assigned in separate calls.
        ax.set_xticks(range(4))
        ax.set_xticklabels(["T1", "T2", "T3", "T4"])
        ax.set_yticks(range(35))
        ax.set_yticklabels([str(i) for i in states])
        ax.set(xlabel="Station", ylabel="Frozen state ID", title=title)
        fig.colorbar(image, ax=ax, label="TerminalLOH (kg)")
        fig.tight_layout(); fig.savefig(work_dir / name); plt.close(fig)

    heatmap(saa, "terminal_loh_heatmap_saa.png", "SAA TerminalLOH")
    heatmap(dro, "terminal_loh_heatmap_eta003.png", "Pearson eta=0.03 TerminalLOH")

    plot_specs = [
        ("delta_total_T_kg", "eta003_inventory_increment_by_state.png", "Inventory increment (kg)", "eta=0.03 - SAA"),
        ("mean_EENS_improvement_kWh", "eta003_eens_improvement_by_state.png", "Mean EENS improvement (kWh)", "SAA - eta=0.03"),
        ("q95_shortage_improvement_kg", "eta003_q95_improvement_by_state.png", "q95 shortage improvement (kg)", "SAA - eta=0.03"),
        ("delta_nominal_economic_cost_yuan", "eta003_nominal_cost_change_by_state.png", "Nominal economic cost change (yuan)", "eta=0.03 - SAA"),
    ]
    for column, filename, ylabel, title in plot_specs:
        fig, ax = plt.subplots(figsize=(10, 4))
        ax.bar(states, comparison[column], color="#4472c4")
        ax.axhline(0, color="black", lw=0.8)
        ax.set(xlabel="Frozen state ID", ylabel=ylabel, title=title)
        ax.grid(axis="y", alpha=0.25); fig.tight_layout(); fig.savefig(work_dir / filename); plt.close(fig)

    fig, ax = plt.subplots(figsize=(10, 4))
    ax.plot(states, comparison.delta_q99_5_shortage_kg, marker="o", ms=2.5, label="q99.5 change")
    ax.plot(states, comparison.delta_max_shortage_kg, marker="s", ms=2.5, label="maximum change")
    ax.axhline(0, color="black", lw=0.8)
    ax.set(xlabel="Frozen state ID", ylabel="Shortage change (kg)", title="eta=0.03 - SAA")
    ax.grid(alpha=0.25); ax.legend(); fig.tight_layout()
    fig.savefig(work_dir / "eta003_q995_and_max_change_by_state.png"); plt.close(fig)

    fig, ax = plt.subplots(figsize=(6, 5))
    scatter = ax.scatter(
        comparison.SAA_mean_EENS_kWh,
        comparison.delta_total_T_kg,
        c=comparison.SAA_positive_shortage_probability,
        cmap="plasma",
    )
    for _, row in comparison.nlargest(5, "SAA_mean_EENS_kWh").iterrows():
        ax.annotate(str(int(row.state_id)), (row.SAA_mean_EENS_kWh, row.delta_total_T_kg), fontsize=7)
    ax.set(xlabel="SAA mean EENS (kWh)", ylabel="Extra TerminalLOH (kg)")
    ax.grid(alpha=0.25); fig.colorbar(scatter, ax=ax, label="SAA positive-shortage probability")
    fig.tight_layout(); fig.savefig(work_dir / "state_risk_vs_eta003_extra_inventory.png"); plt.close(fig)

    delta = comparison[[f"delta_T{i}_kg" for i in range(1, 5)]]
    fig, ax = plt.subplots(figsize=(7, 4))
    ax.boxplot([delta[column].to_numpy() for column in delta], labels=["T1", "T2", "T3", "T4"])
    ax.axhline(0, color="black", lw=0.8)
    ax.set(xlabel="Station", ylabel="eta=0.03 inventory change (kg)")
    ax.grid(axis="y", alpha=0.25); fig.tight_layout()
    fig.savefig(work_dir / "station_eta003_inventory_increment.png"); plt.close(fig)

    binding = pd.DataFrame(
        {
            "SAA": [int(saa[f"T{i}_capacity_binding"].sum()) for i in range(1, 5)],
            "eta=0.03": [int(dro[f"T{i}_capacity_binding"].sum()) for i in range(1, 5)],
        }, index=["T1", "T2", "T3", "T4"]
    )
    fig, ax = plt.subplots(figsize=(7, 4))
    binding.plot(kind="bar", ax=ax)
    ax.set(xlabel="Station", ylabel="Binding state count")
    ax.grid(axis="y", alpha=0.25); fig.tight_layout()
    fig.savefig(work_dir / "capacity_binding_summary.png"); plt.close(fig)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--work-dir", required=True)
    parser.add_argument("--judgment", choices=list("ABCDE"), required=True)
    args = parser.parse_args()
    work_dir = Path(args.work_dir).resolve()
    require(work_dir.is_dir(), "Work directory does not exist")
    require((work_dir / "BACKGROUND_CONTROLLER_COMPLETE.txt").is_file(), "Background controller did not complete")
    required_outputs = [
        "all_state_two_method_long_results.csv", "terminal_loh_table_saa.csv",
        "terminal_loh_table_eta_003.csv", "eta003_candidate_judgment.txt", "README.md",
    ]
    require(not any((work_dir / name).exists() for name in required_outputs), "Refusing to overwrite finalized C6 outputs")

    progress = pd.read_csv(work_dir / "solve_progress_manifest.csv")
    case_progress = progress[progress.process_label.astype(str).str.startswith("case-")].copy()
    require(len(case_progress) == 70, "Expected exactly 70 isolated case process rows")
    require(case_progress.process_label.nunique() == 70, "Case process labels are duplicated")
    require((case_progress.process_type == "PYTHON").all(), "Every optimization case must be a Python process")
    require((case_progress.exit_code == 0).all(), "A Python case process returned a nonzero exit code")
    require(
        case_progress["pass"].astype(str).str.lower().isin(["1", "true"]).all(),
        "A Python case process failed its process gate",
    )
    case_progress["started_timestamp"] = pd.to_datetime(case_progress.started_at, utc=True)
    case_progress["ended_timestamp"] = pd.to_datetime(case_progress.ended_at, utc=True)
    ordered_processes = case_progress.sort_values("started_timestamp").reset_index(drop=True)
    ordered_processes["previous_process_end_timestamp"] = ordered_processes.ended_timestamp.shift(1)
    ordered_processes["released_before_next_process"] = (
        ordered_processes.previous_process_end_timestamp.isna()
        | (ordered_processes.started_timestamp >= ordered_processes.previous_process_end_timestamp)
    )
    require(ordered_processes.released_before_next_process.all(), "Optimization case processes overlap")
    ordered_processes.to_csv(work_dir / "case_process_isolation_audit.csv", index=False)

    architecture = pd.read_csv(work_dir / "python_solver_architecture_audit.csv")
    require(len(architecture) == 1, "Python solver architecture audit must have one row")
    architecture_row = architecture.iloc[0]
    for column in [
        "one_isolated_process_per_case",
        "LP_calls_inside_case_process",
        "case_processes_sequential",
        "primal_solution_and_duals_audited",
        "case_process_released_before_next",
    ]:
        require(str(architecture_row[column]).lower() in {"1", "true"}, f"Architecture audit failed: {column}")
    require(int(architecture_row.MATLAB_Gurobi_MEX_used) == 0, "MATLAB Gurobi MEX entered C6 cases")

    results, cert, worst = load_case_tables(work_dir)
    results = results.sort_values("case_id").reset_index(drop=True)
    cert = cert.sort_values("case_id").reset_index(drop=True)
    worst = worst.sort_values("case_id").reset_index(drop=True)
    require(len(results) == len(cert) == len(worst) == 70, "Expected 70 result/certificate rows")
    require(results.case_id.tolist() == list(range(1, 71)), "Case IDs must be exactly 1:70")
    require(set(results.state_id) == set(range(1, 36)), "State IDs must be exactly 1:35")
    require(all(results.groupby("state_id").size() == 2), "Each state must have two methods")
    require(set(np.round(results.eta, 12)) == {0.0, ETA_DRO}, "Eta set must be exactly {0,0.03}")
    require(results.case_pass.astype(str).str.lower().isin(["1", "true"]).all(), "A case result failed")
    require(cert.certificate_pass.astype(str).str.lower().isin(["1", "true"]).all(), "A solver certificate failed")
    require((results.scenario_count == 15000).all(), "Every case must use 15000 scenarios")
    require((cert.C_y_in_primary_objective == 0).all() and (cert.C_y_in_Pearson_loss == 0).all(), "C*y scope failure")
    require((cert.constructed_R_by_R_matrix == 0).all(), "R-by-R matrix was constructed")
    identity_pairs = [
        ("mean_shortage_kg", "mean_EENS_kWh"),
        ("shortage_q95_kg", "EENS_q95_kWh"),
        ("shortage_q99_kg", "EENS_q99_kWh"),
        ("shortage_q99_5_kg", "EENS_q99_5_kWh"),
        ("shortage_CVaR95_kg", "EENS_CVaR95_kWh"),
        ("shortage_CVaR99_kg", "EENS_CVaR99_kWh"),
        ("shortage_CVaR99_5_kg", "EENS_CVaR99_5_kWh"),
        ("max_shortage_kg", "max_EENS_kWh"),
    ]
    for shortage_col, eens_col in identity_pairs:
        error = (results[eens_col] - results[shortage_col] * ELECTRICITY_PER_KG).abs().max()
        require(error <= 1e-8, f"EENS identity failed for {shortage_col}: {error}")

    reproduction = state19_reproduction(work_dir, results, cert)
    comparison = make_comparison(results)
    correlation = correlation_table(comparison)
    representatives = representative_states(comparison)

    results.to_csv(work_dir / "all_state_two_method_long_results.csv", index=False)
    saa_table = results[np.isclose(results.eta, 0)][
        ["state_id", "state_label", "intensity", "loc", "lfw", "eta", "T1_kg", "T2_kg", "T3_kg", "T4_kg", "TerminalLOH_total_kg"]
    ]
    dro_table = results[np.isclose(results.eta, ETA_DRO)][
        ["state_id", "state_label", "intensity", "loc", "lfw", "eta", "T1_kg", "T2_kg", "T3_kg", "T4_kg", "TerminalLOH_total_kg"]
    ]
    saa_table.to_csv(work_dir / "terminal_loh_table_saa.csv", index=False)
    dro_table.to_csv(work_dir / "terminal_loh_table_eta_003.csv", index=False)
    comparison.to_csv(work_dir / "terminal_loh_saa_vs_eta003_comparison.csv", index=False)

    resilience_columns = [
        "case_id", "state_id", "state_label", "intensity", "loc", "lfw", "method_label", "eta",
        "mean_shortage_kg", "mean_EENS_kWh", "service_rate", "aggregate_service_rate",
        "probability_positive_shortage", "shortage_q95_kg", "shortage_q99_kg", "shortage_q99_5_kg",
        "shortage_CVaR95_kg", "shortage_CVaR99_kg", "shortage_CVaR99_5_kg", "max_shortage_kg",
        "EENS_q95_kWh", "EENS_q99_kWh", "EENS_q99_5_kWh", "EENS_CVaR95_kWh",
        "EENS_CVaR99_kWh", "EENS_CVaR99_5_kWh", "max_EENS_kWh",
    ]
    economic_columns = [
        "case_id", "state_id", "state_label", "method_label", "eta", "TerminalLOH_total_kg",
        "local_hydrogen_preparation_cost_yuan", "nominal_expected_outage_loss_yuan",
        "nominal_total_economic_cost_yuan", "robust_training_objective_yuan",
        "worst_expected_outage_loss_yuan", "secondary_expected_service_distance",
    ]
    results[resilience_columns].to_csv(work_dir / "state_nominal_resilience_metrics.csv", index=False)
    results[economic_columns].to_csv(work_dir / "state_nominal_economic_metrics.csv", index=False)
    comparison.to_csv(work_dir / "state_eta003_increment_comparison.csv", index=False)
    comparison[[
        "state_id", "state_label", "delta_total_T_kg", "delta_preparation_cost_yuan",
        "mean_EENS_improvement_kWh", "q95_shortage_improvement_kg", "q99_shortage_improvement_kg",
        "q99_5_shortage_improvement_kg", "maximum_shortage_improvement_kg",
        "mean_EENS_improvement_per_added_kg", "q95_improvement_per_added_kg",
        "net_cost_per_restored_kWh",
    ]].to_csv(work_dir / "state_eta003_marginal_benefit.csv", index=False)
    worst[np.isclose(worst.eta, ETA_DRO)].to_csv(work_dir / "state_eta003_worst_probability_summary.csv", index=False)
    cert.to_csv(work_dir / "solver_certificate.csv", index=False)
    reproduction.to_csv(work_dir / "state19_reproduction_audit.csv", index=False)

    station_rows = []
    saa = results[np.isclose(results.eta, 0)].set_index("state_id")
    dro = results[np.isclose(results.eta, ETA_DRO)].set_index("state_id")
    for site in range(1, 5):
        delta = dro[f"T{site}_kg"] - saa[f"T{site}_kg"]
        station_rows.append({
            "station": f"T{site}", "SAA_mean_kg": saa[f"T{site}_kg"].mean(),
            "SAA_median_kg": saa[f"T{site}_kg"].median(), "SAA_min_kg": saa[f"T{site}_kg"].min(),
            "SAA_max_kg": saa[f"T{site}_kg"].max(), "ETA003_mean_kg": dro[f"T{site}_kg"].mean(),
            "ETA003_median_kg": dro[f"T{site}_kg"].median(), "ETA003_min_kg": dro[f"T{site}_kg"].min(),
            "ETA003_max_kg": dro[f"T{site}_kg"].max(), "delta_mean_kg": delta.mean(),
            "delta_median_kg": delta.median(), "delta_min_kg": delta.min(), "delta_max_kg": delta.max(),
            "positive_delta_state_count": int((delta > 1e-6).sum()),
            "negative_delta_state_count": int((delta < -1e-6).sum()),
            "near_zero_delta_state_count": int((delta.abs() <= 1e-6).sum()),
            "SAA_capacity_binding_state_count": int(saa[f"T{site}_capacity_binding"].sum()),
            "ETA003_capacity_binding_state_count": int(dro[f"T{site}_capacity_binding"].sum()),
            "largest_increment_state_id": int(delta.idxmax()),
        })
    pd.DataFrame(station_rows).to_csv(work_dir / "station_allocation_audit.csv", index=False)
    results[[
        "case_id", "state_id", "state_label", "method_label", "eta", "T1_capacity_binding",
        "T2_capacity_binding", "T3_capacity_binding", "T4_capacity_binding", "capacity_binding_count",
    ]].to_csv(work_dir / "capacity_binding_audit.csv", index=False)
    comparison[[
        "state_id", "state_label", "delta_total_T_kg", "delta_T1_kg", "delta_T2_kg", "delta_T3_kg",
        "delta_T4_kg", "maximum_abs_station_change_kg", "any_station_inventory_decrease",
        "total_inventory_increase_with_station_decrease",
    ]].to_csv(work_dir / "reallocation_and_nonmonotonicity_audit.csv", index=False)

    ranking = comparison.copy()
    ranking["SAA_mean_EENS_risk_rank"] = ranking.SAA_mean_EENS_kWh.rank(method="min", ascending=False).astype(int)
    ranking["SAA_q95_risk_rank"] = ranking.SAA_q95_shortage_kg.rank(method="min", ascending=False).astype(int)
    ranking["extra_inventory_rank"] = ranking.delta_total_T_kg.rank(method="min", ascending=False).astype(int)
    ranking["mean_EENS_improvement_rank"] = ranking.mean_EENS_improvement_kWh.rank(method="min", ascending=False).astype(int)
    ranking["q95_improvement_rank"] = ranking.q95_shortage_improvement_kg.rank(method="min", ascending=False).astype(int)
    ranking.to_csv(work_dir / "state_risk_ranking.csv", index=False)
    correlation.to_csv(work_dir / "risk_inventory_correlation.csv", index=False)
    representatives.to_csv(work_dir / "representative_state_comparison.csv", index=False)

    tolerance = 1e-8
    coverage = pd.DataFrame([{
        "state_count": 35,
        "eta003_means_eta": ETA_DRO,
        "inventory_increase_state_count": int((comparison.delta_total_T_kg > tolerance).sum()),
        "inventory_near_unchanged_state_count": int((comparison.delta_total_T_kg.abs() <= tolerance).sum()),
        "mean_EENS_improvement_state_count": int((comparison.mean_EENS_improvement_kWh > tolerance).sum()),
        "mean_EENS_near_unchanged_state_count": int((comparison.mean_EENS_improvement_kWh.abs() <= tolerance).sum()),
        "mean_EENS_worsening_state_count": int((comparison.mean_EENS_improvement_kWh < -tolerance).sum()),
        "q95_improvement_state_count": int((comparison.q95_shortage_improvement_kg > tolerance).sum()),
        "q95_near_unchanged_state_count": int((comparison.q95_shortage_improvement_kg.abs() <= tolerance).sum()),
        "q95_worsening_state_count": int((comparison.q95_shortage_improvement_kg < -tolerance).sum()),
        "q99_5_improvement_state_count": int((comparison.q99_5_shortage_improvement_kg > tolerance).sum()),
        "q99_5_near_unchanged_state_count": int((comparison.q99_5_shortage_improvement_kg.abs() <= tolerance).sum()),
        "q99_5_worsening_state_count": int((comparison.q99_5_shortage_improvement_kg < -tolerance).sum()),
        "maximum_shortage_improvement_state_count": int((comparison.maximum_shortage_improvement_kg > tolerance).sum()),
        "maximum_shortage_near_unchanged_state_count": int((comparison.maximum_shortage_improvement_kg.abs() <= tolerance).sum()),
        "maximum_shortage_worsening_state_count": int((comparison.maximum_shortage_improvement_kg < -tolerance).sum()),
        "nominal_economic_cost_decrease_state_count": int((comparison.delta_nominal_economic_cost_yuan < -tolerance).sum()),
        "nominal_safety_premium_state_count": int((comparison.delta_nominal_economic_cost_yuan > tolerance).sum()),
        "nominal_economic_cost_near_unchanged_state_count": int((comparison.delta_nominal_economic_cost_yuan.abs() <= tolerance).sum()),
        "station_decrease_with_total_increase_state_count": int(comparison.total_inventory_increase_with_station_decrease.sum()),
        "capacity_binding_case_count": int((results.capacity_binding_count > 0).sum()),
        "delta_inventory_equal_state_mean_kg": comparison.delta_total_T_kg.mean(),
        "delta_inventory_median_kg": comparison.delta_total_T_kg.median(),
        "delta_inventory_min_kg": comparison.delta_total_T_kg.min(),
        "delta_inventory_q25_kg": comparison.delta_total_T_kg.quantile(0.25),
        "delta_inventory_q75_kg": comparison.delta_total_T_kg.quantile(0.75),
        "delta_inventory_max_kg": comparison.delta_total_T_kg.max(),
        "mean_EENS_improvement_equal_state_mean_kWh": comparison.mean_EENS_improvement_kWh.mean(),
        "mean_EENS_improvement_median_kWh": comparison.mean_EENS_improvement_kWh.median(),
        "mean_EENS_improvement_min_kWh": comparison.mean_EENS_improvement_kWh.min(),
        "mean_EENS_improvement_q25_kWh": comparison.mean_EENS_improvement_kWh.quantile(0.25),
        "mean_EENS_improvement_q75_kWh": comparison.mean_EENS_improvement_kWh.quantile(0.75),
        "mean_EENS_improvement_max_kWh": comparison.mean_EENS_improvement_kWh.max(),
        "q95_improvement_equal_state_mean_kg": comparison.q95_shortage_improvement_kg.mean(),
        "q95_improvement_median_kg": comparison.q95_shortage_improvement_kg.median(),
        "q95_improvement_min_kg": comparison.q95_shortage_improvement_kg.min(),
        "q95_improvement_q25_kg": comparison.q95_shortage_improvement_kg.quantile(0.25),
        "q95_improvement_q75_kg": comparison.q95_shortage_improvement_kg.quantile(0.75),
        "q95_improvement_max_kg": comparison.q95_shortage_improvement_kg.max(),
        "nominal_cost_change_equal_state_mean_yuan": comparison.delta_nominal_economic_cost_yuan.mean(),
        "nominal_cost_change_median_yuan": comparison.delta_nominal_economic_cost_yuan.median(),
        "nominal_cost_change_min_yuan": comparison.delta_nominal_economic_cost_yuan.min(),
        "nominal_cost_change_q25_yuan": comparison.delta_nominal_economic_cost_yuan.quantile(0.25),
        "nominal_cost_change_q75_yuan": comparison.delta_nominal_economic_cost_yuan.quantile(0.75),
        "nominal_cost_change_max_yuan": comparison.delta_nominal_economic_cost_yuan.max(),
        "equal_state_summary_interpretation": "descriptive across 35 states; not an expectation",
    }])
    coverage.to_csv(work_dir / "eta003_coverage_summary.csv", index=False)

    make_plots(work_dir, results, comparison)

    descriptions = {
        "A": "eta=0.03 gives stable mean-EENS or q95 improvement across most relevant states and is suitable as the representative high-guarantee DRO table for MSP comparison.",
        "B": "eta=0.03 is concentrated in a smaller set of physically meaningful high-risk states but remains suitable as a high-risk-preference table for MSP comparison.",
        "C": "eta=0.03 adds inventory in many states with limited resilience value and should not be the formal 35-state DRO table without revisiting eta=0.01 or 0.003.",
        "D": "SAA and eta=0.03 are highly overlapping across states, so cross-state DRO incremental value is insufficient.",
        "E": "An anomaly or instability prevents a formal C6 conclusion.",
    }
    judgment_lines = [
        "Step-04C-C6 candidate judgment",
        "",
        f"Judgment: {args.judgment}",
        descriptions[args.judgment],
        "",
        f"inventory increase states: {int(coverage.inventory_increase_state_count.iloc[0])}/35",
        f"mean EENS improvement states: {int(coverage.mean_EENS_improvement_state_count.iloc[0])}/35",
        f"q95 improvement states: {int(coverage.q95_improvement_state_count.iloc[0])}/35",
        f"q99.5 improvement states: {int(coverage.q99_5_improvement_state_count.iloc[0])}/35",
        f"maximum shortage improvement states: {int(coverage.maximum_shortage_improvement_state_count.iloc[0])}/35",
        f"nominal economic cost decrease states: {int(coverage.nominal_economic_cost_decrease_state_count.iloc[0])}/35",
        f"safety premium states: {int(coverage.nominal_safety_premium_state_count.iloc[0])}/35",
        "",
        "eta003 in directory and file names means eta=0.03, not eta=0.003.",
        "Eta remains unfrozen and is not assigned a statistical confidence level.",
        "The 35-state equal-state summaries are descriptive and are not called expectations.",
        "This step does not prove eta=0.03 is superior in every state or scenario.",
        "TerminalLOH inventory cannot eliminate complete road inaccessibility.",
    ]
    (work_dir / "eta003_candidate_judgment.txt").write_text("\n".join(judgment_lines) + "\n", encoding="utf-8")

    local_files = []
    for pattern in [
        "prepared_inputs/*.mat",
        "optimization_cases/*/case_payload.mat",
        "optimization_cases/*/matlab_diary.txt",
        "process_logs/*.txt",
        "prepare_matlab_diary.txt",
    ]:
        for path in sorted(work_dir.glob(pattern)):
            local_files.append({
                "relative_path": str(path.relative_to(work_dir)).replace("\\", "/"),
                "bytes": path.stat().st_size,
                "sha256": sha256_file(path),
                "git_status": "LOCAL_ONLY_NOT_COMMITTED",
            })
    runtime_dir = work_dir.parents[3] / "terminalLoh_wdro/output/step04cc6_python_runtime/gurobipy-12.0.1"
    require(runtime_dir.is_dir(), "Local gurobipy 12.0.1 runtime directory is missing")
    runtime_file_count, runtime_bytes, runtime_hash = sha256_tree(runtime_dir)
    local_files.append({
        "relative_path": "terminalLoh_wdro/output/step04cc6_python_runtime/gurobipy-12.0.1/",
        "bytes": runtime_bytes,
        "sha256": runtime_hash,
        "git_status": f"LOCAL_ONLY_NOT_COMMITTED_TREE_{runtime_file_count}_FILES",
    })
    # Background launch logs use the established run023/run024 token without
    # the hyphen that is present in the result directory name.
    controller_run_token = work_dir.name.replace("-", "")
    for suffix in ("stdout", "stderr"):
        controller_log = work_dir.parents[3] / "terminalLoh_wdro/output" / (
            f"step04cc6_{controller_run_token}_controller_{suffix}.txt"
        )
        require(controller_log.is_file(), f"Missing background controller {suffix} log")
        local_files.append({
            "relative_path": str(controller_log.relative_to(work_dir.parents[3])).replace("\\", "/"),
            "bytes": controller_log.stat().st_size,
            "sha256": sha256_file(controller_log),
            "git_status": "LOCAL_ONLY_NOT_COMMITTED",
        })
    manifest_lines = [
        "# Step-04C-C6 large/local file manifest", "",
        "Prepared inputs, per-case payloads, diaries, process logs, the local gurobipy runtime, and full 15000-dimensional probability vectors remain local.",
        "They are not part of the lightweight accepted Git scope.", "",
        "| relative path | bytes | SHA-256 | Git status |", "|---|---:|---|---|",
    ]
    manifest_lines.extend(
        f"| `{row['relative_path']}` | {row['bytes']} | `{row['sha256']}` | {row['git_status']} |"
        for row in local_files
    )
    (work_dir / "LARGE_FILE_MANIFEST.md").write_text("\n".join(manifest_lines) + "\n", encoding="utf-8")

    readme = [
        "# Step-04C-C6 35-state SAA versus eta=0.03 TerminalLOH tables", "",
        "Status: **ACCEPTED**", f"Judgment: **{args.judgment}**", "",
        "The directory/file token `eta003` means `eta=0.03`; it does not mean eta=0.003.",
        "All 35 frozen initial states were solved independently on their own 15000 nominal scenarios for SAA and Pearson chi-square eta=0.03, giving 70 isolated optimization combinations and two complete 35x4 TerminalLOH tables.",
        "Every optimization combination ran in one isolated Python 3.9/gurobipy 12.0.1 process. SAA, DRO decomposition, independent fixed-T audit, and strict two-phase lexicographic replay ran inside that case process; the process exited and was released before the next case started. MATLAB Gurobi MEX was not used for the 70 optimization cases.",
        "Different states were not pooled, path_probability was not reused, and each state's nominal record weight is 1/15000.", "",
        "The primary objective is the frozen C5B/C5C yuan-consistent preparation plus shortage/VOLL objective. `C*y` is a strict lexicographic secondary tie-break and is neither currency nor transport cost.",
        "State19 SAA and eta=0.03 reproduce C5C within the frozen tolerances. Every optimization, probability, LB/UB, strong-duality, lexicographic, state mapping, and EENS audit passed.", "",
        "The 35-state equal-state means are descriptive, not probability-weighted expectations. No initial-state prior probability was constructed.",
        "C2 independent paths, C3 Markov shifts, and the fixed pressure set were not rerun; their state19 conclusions are referenced from C5B/C5C.", "",
        descriptions[args.judgment],
        "Eta remains unfrozen. Eta=0.03 is only a representative high-guarantee radius for comparison, and inventory cannot solve complete road inaccessibility.",
    ]
    (work_dir / "README.md").write_text("\n".join(readme) + "\n", encoding="utf-8")
    print(f"STEP04CC6_FINALIZE_COMPLETE|judgment={args.judgment}|states=35|cases=70")


if __name__ == "__main__":
    main()
