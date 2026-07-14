from __future__ import annotations

import math
from pathlib import Path

import numpy as np
import pandas as pd

import matplotlib

matplotlib.use("Agg")
import matplotlib.font_manager as font_manager
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle
from matplotlib.ticker import FuncFormatter


ROOT = Path(__file__).resolve().parents[1]
DETAILS_DIR = ROOT / "output_h2" / "details"
OUT_DIR = ROOT / "output_h2" / "figures" / "msp_results"

BLUE = "#1f4e79"
ORANGE = "#f28e2b"
GREEN = "#59a14f"
RED = "#c44e52"
GRAY = "#6f7782"
LIGHT_BLUE = "#9ecae1"
PALE_BLUE = "#eef4f8"

GENERATED: list[Path] = []
SKIPPED: list[str] = []


def has_chinese_font() -> bool:
    names = {f.name for f in font_manager.fontManager.ttflist}
    for name in ["Microsoft YaHei", "SimHei", "Noto Sans CJK SC"]:
        if name in names:
            plt.rcParams["font.family"] = name
            return True
    plt.rcParams["font.family"] = "DejaVu Sans"
    return False


CHINESE_FONT_OK = has_chinese_font()

plt.rcParams.update(
    {
        "figure.facecolor": "white",
        "axes.facecolor": "white",
        "axes.edgecolor": "#c7cdd4",
        "axes.labelcolor": "#25313c",
        "xtick.color": "#25313c",
        "ytick.color": "#25313c",
        "axes.titleweight": "bold",
        "axes.unicode_minus": False,
        "svg.fonttype": "none",
    }
)


def title(chinese: str, english: str) -> str:
    return chinese if CHINESE_FONT_OK else english


def new_fig(nrows: int = 1, ncols: int = 1, **kwargs):
    return plt.subplots(
        nrows,
        ncols,
        figsize=(13.333, 7.5),
        dpi=300,
        constrained_layout=True,
        **kwargs,
    )


def compact_number(value, _pos=None) -> str:
    if value is None or (isinstance(value, float) and not math.isfinite(value)):
        return ""
    value = float(value)
    sign = "-" if value < 0 else ""
    value = abs(value)
    if value >= 1_000_000:
        return f"{sign}{value / 1_000_000:.1f}M"
    if value >= 1_000:
        return f"{sign}{value / 1_000:.0f}k"
    if value >= 10:
        return f"{sign}{value:.0f}"
    if value >= 1:
        return f"{sign}{value:.1f}"
    return f"{sign}{value:.2f}"


def fmt_value(value, decimals: int = 1) -> str:
    if pd.isna(value):
        return "NA"
    value = float(value)
    if abs(value) >= 1000:
        return f"{value:,.0f}"
    return f"{value:,.{decimals}f}"


def load_csv(name: str, required_cols: list[str] | None = None) -> pd.DataFrame | None:
    path = DETAILS_DIR / name
    if not path.exists():
        SKIPPED.append(f"{name}: missing file")
        return None
    df = pd.read_csv(path)
    if required_cols:
        missing = [col for col in required_cols if col not in df.columns]
        if missing:
            SKIPPED.append(f"{name}: missing columns {missing}")
            return None
    return df


def save_current(stem: str) -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    png = OUT_DIR / f"{stem}.png"
    svg = OUT_DIR / f"{stem}.svg"
    plt.savefig(png, dpi=300)
    plt.savefig(svg)
    GENERATED.extend([png, svg])
    plt.close()


def add_metric_line(ax, value: float, label_text: str, color: str, ymax: float | None = None):
    if value is None or not np.isfinite(value):
        return
    ax.axvline(value, color=color, lw=2.2, ls="--", label=f"{label_text}: {fmt_value(value)}")
    if ymax is not None:
        ax.text(
            value,
            ymax * 0.94,
            label_text,
            rotation=90,
            va="top",
            ha="right",
            fontsize=9,
            color=color,
            fontweight="bold",
        )


def choose_representative_paths(summary: pd.DataFrame, timeseries: pd.DataFrame) -> list[int]:
    selected: list[int] = []
    if "path_type" in summary.columns:
        for path_type in ["high_shortage_path", "low_shortage_path", "no_loh_demand_path"]:
            rows = summary.loc[summary["path_type"].eq(path_type)]
            if not rows.empty:
                selected.append(int(rows.iloc[0]["path_id"]))
    if selected:
        return selected

    shortage_col = "terminal_reserve_shortage_total"
    if shortage_col in summary.columns:
        high = summary.sort_values(shortage_col, ascending=False).iloc[0]
        selected.append(int(high["path_id"]))
        low_candidates = summary.loc[summary[shortage_col].fillna(0).gt(0)].sort_values(shortage_col)
        if not low_candidates.empty:
            selected.append(int(low_candidates.iloc[0]["path_id"]))

    if "TerminalLOH_total" in timeseries.columns:
        demand_by_path = timeseries.groupby("path_id")["TerminalLOH_total"].max()
        no_demand = demand_by_path[demand_by_path.fillna(0).le(1e-9)]
        if not no_demand.empty:
            selected.append(int(no_demand.index[0]))

    deduped: list[int] = []
    for path_id in selected:
        if path_id not in deduped:
            deduped.append(path_id)
    return deduped[:3]


def path_label(summary: pd.DataFrame, path_id: int) -> str:
    row = summary.loc[summary["path_id"].eq(path_id)]
    if row.empty or "path_type" not in row.columns:
        return f"path {path_id}"
    item = row.iloc[0]
    path_type = str(item["path_type"])
    shortage = float(item.get("terminal_reserve_shortage_total", 0) or 0)
    demand = item.get("TerminalLOH_total_at_demand", np.nan)
    if path_type == "high_shortage_path":
        label = title("高短缺路径", "High-shortage path")
    elif path_type == "low_shortage_path" and shortage <= 1e-9:
        if pd.notna(demand):
            label = title("触发检查\n无短缺路径", "Check reached\nno shortage")
        else:
            label = title("低短缺路径", "Low-shortage path")
    elif path_type == "low_shortage_path":
        label = title("低短缺路径", "Low-shortage path")
    elif path_type == "no_loh_demand_path":
        label = title("未进入\nTerminalLOH检查", "No TerminalLOH\ncheck")
    elif path_type == "high_beta_path":
        label = title("高 beta 路径", "High-beta path")
    else:
        label = path_type.replace("_", "\n")
    return label + f"\n#{path_id}"


def plot_fig01() -> None:
    costs = load_csv("h2_oos_path_costs.csv", ["total_cost"])
    metrics = load_csv("oos_risk_metrics.csv")
    if costs is None:
        return
    series = pd.to_numeric(costs["total_cost"], errors="coerce").dropna()
    if series.empty:
        SKIPPED.append("fig01: total_cost has no numeric values")
        return

    fig, ax = new_fig()
    xmax = float(series.quantile(0.995))
    bins = np.linspace(0, xmax, 50)
    ax.hist(series[series <= xmax], bins=bins, color=LIGHT_BLUE, edgecolor="white", linewidth=0.5)
    ax.set_title(title("H2-MSP 样本外路径总成本分布", "H2-MSP OOS Path Total Cost Distribution"), color=BLUE, fontsize=22, pad=18)
    ax.set_xlabel(title("路径总成本 total_cost（元）", "Path total_cost (yuan)"), fontsize=12)
    ax.set_ylabel(title("路径数量", "Path count"), fontsize=12)
    ax.xaxis.set_major_formatter(FuncFormatter(compact_number))
    ax.yaxis.set_major_formatter(FuncFormatter(compact_number))
    ax.grid(axis="y", alpha=0.25)

    ymax = ax.get_ylim()[1]
    metric_row = metrics.iloc[0] if metrics is not None and not metrics.empty else {}
    add_metric_line(ax, float(metric_row.get("mean_cost", series.mean())), "mean", BLUE, ymax)
    if "VaR_95" in metric_row:
        add_metric_line(ax, float(metric_row["VaR_95"]), "VaR95", ORANGE, ymax)
    if "CVaR_95" in metric_row:
        add_metric_line(ax, float(metric_row["CVaR_95"]), "CVaR95", RED, ymax)
    ax.legend(loc="upper right", frameon=False, fontsize=10)
    ax.text(
        0.01,
        -0.13,
        title(
            f"注：横轴显示到 P99.5={fmt_value(xmax)}，最大值={fmt_value(series.max())}；统计来自现有 OOS CSV。",
            f"Note: x-axis shown to P99.5={fmt_value(xmax)}; max={fmt_value(series.max())}; metrics from existing OOS CSV.",
        ),
        transform=ax.transAxes,
        fontsize=9,
        color=GRAY,
    )
    save_current("fig01_oos_cost_distribution")


def plot_fig02() -> None:
    df = load_csv("h2_terminal_summary.csv", ["terminal_reserve_shortage"])
    if df is None:
        df = load_csv("h2_oos_summary_by_path.csv", ["terminal_reserve_shortage"])
    if df is None:
        return
    series = pd.to_numeric(df["terminal_reserve_shortage"], errors="coerce").dropna()
    if series.empty:
        SKIPPED.append("fig02: terminal_reserve_shortage has no numeric values")
        return

    fig, ax = new_fig()
    ax.hist(series, bins=45, color=GREEN, edgecolor="white", linewidth=0.5, alpha=0.82)
    ax.set_title(title("TerminalLOH 储备短缺分布", "TerminalLOH Reserve Shortage Distribution"), color=BLUE, fontsize=22, pad=18)
    ax.set_xlabel(title("terminal_reserve_shortage（kg）", "terminal_reserve_shortage (kg)"), fontsize=12)
    ax.set_ylabel(title("路径数量", "Path count"), fontsize=12)
    ax.grid(axis="y", alpha=0.25)
    ax.xaxis.set_major_formatter(FuncFormatter(compact_number))
    ax.yaxis.set_major_formatter(FuncFormatter(compact_number))
    ymax = ax.get_ylim()[1]
    add_metric_line(ax, float(series.mean()), "mean", BLUE, ymax)
    add_metric_line(ax, float(series.max()), "max", RED, ymax)
    ax.legend(loc="upper right", frameon=False, fontsize=10)
    save_current("fig02_terminal_shortage_distribution")


def plot_fig03() -> None:
    metrics = load_csv("oos_risk_metrics.csv")
    if metrics is None or metrics.empty:
        return
    row = metrics.iloc[0]
    required = [
        "mean_cost",
        "VaR_90",
        "CVaR_90",
        "VaR_95",
        "CVaR_95",
        "VaR_99",
        "CVaR_99",
        "mean_terminal_shortage",
        "max_terminal_shortage",
        "hit_loh_demand_ratio",
    ]
    missing = [col for col in required if col not in metrics.columns]
    if missing:
        SKIPPED.append(f"fig03: missing columns {missing}")
        return

    fig, ax = new_fig()
    ax.set_axis_off()
    fig.suptitle(
        title("OOS 成本与终端短缺风险指标", "OOS Cost and Terminal Shortage Risk Metrics"),
        color=BLUE,
        fontsize=22,
        fontweight="bold",
        y=0.94,
    )
    cards = [
        ("Mean cost", fmt_value(row["mean_cost"], 0), title("样本外平均成本", "OOS mean cost"), BLUE),
        ("VaR/CVaR 90", f"{fmt_value(row['VaR_90'], 0)} / {fmt_value(row['CVaR_90'], 0)}", "VaR90 / CVaR90", ORANGE),
        ("VaR/CVaR 95", f"{fmt_value(row['VaR_95'], 0)} / {fmt_value(row['CVaR_95'], 0)}", "VaR95 / CVaR95", RED),
        ("VaR/CVaR 99", f"{fmt_value(row['VaR_99'], 0)} / {fmt_value(row['CVaR_99'], 0)}", "VaR99 / CVaR99", RED),
        (
            "Terminal shortage",
            f"{fmt_value(row['mean_terminal_shortage'], 2)} / {fmt_value(row['max_terminal_shortage'], 1)}",
            title("终端短缺 mean / max（kg）", "Terminal shortage mean / max (kg)"),
            GREEN,
        ),
        (
            "LOH demand hit ratio",
            f"{100 * float(row['hit_loh_demand_ratio']):.1f}%",
            title("触发 TerminalLOH 检查路径占比", "Share of paths reaching TerminalLOH check"),
            BLUE,
        ),
    ]
    xs = [0.04, 0.36, 0.68]
    ys = [0.58, 0.22]
    width = 0.28
    height = 0.26
    for idx, (label, value, desc, color) in enumerate(cards):
        x = xs[idx % 3]
        y = ys[idx // 3]
        ax.add_patch(Rectangle((x, y), width, height, transform=ax.transAxes, facecolor=PALE_BLUE, edgecolor="#d8e1e8", lw=1.2))
        ax.add_patch(Rectangle((x, y + height - 0.025), width, 0.025, transform=ax.transAxes, facecolor=color, edgecolor=color, lw=0))
        ax.text(x + 0.02, y + height - 0.065, label, transform=ax.transAxes, fontsize=11, color=GRAY, fontweight="bold")
        ax.text(x + 0.02, y + 0.105, value, transform=ax.transAxes, fontsize=24, color=BLUE, fontweight="bold")
        ax.text(x + 0.02, y + 0.055, desc, transform=ax.transAxes, fontsize=10, color="#34495e")
    ax.text(
        0.04,
        0.08,
        title("注：成本单位为元；TerminalLOH 储备短缺单位为 kg；指标来自 oos_risk_metrics.csv。", "Note: cost unit is yuan; TerminalLOH shortage unit is kg; metrics from oos_risk_metrics.csv."),
        transform=ax.transAxes,
        fontsize=10,
        color=GRAY,
    )
    save_current("fig03_oos_risk_metrics")


def plot_fig04() -> None:
    summary = load_csv("selected_path_summary.csv", ["path_id"])
    ts = load_csv("selected_paths_timeseries.csv", ["path_id", "t", "x_total_after", "TerminalLOH_total", "terminal_shortage_total"])
    if summary is None or ts is None:
        return
    paths = choose_representative_paths(summary, ts)
    if not paths:
        SKIPPED.append("fig04: no representative path can be selected")
        return

    rows = []
    for path_id in paths:
        srow = summary.loc[summary["path_id"].eq(path_id)]
        path_ts = ts.loc[ts["path_id"].eq(path_id)].sort_values("t")
        if path_ts.empty:
            continue
        if not srow.empty and pd.notna(srow.iloc[0].get("x_total_before_demand", np.nan)):
            x_before = float(srow.iloc[0]["x_total_before_demand"])
            demand = float(srow.iloc[0].get("TerminalLOH_total_at_demand", 0) or 0)
            shortage = float(srow.iloc[0].get("shortage_total_at_demand", 0) or 0)
        else:
            last = path_ts.iloc[-1]
            x_before = float(last["x_total_after"])
            demand = float(last.get("TerminalLOH_total", 0) or 0)
            shortage = float(last.get("terminal_shortage_total", 0) or 0)
        rows.append((path_id, path_label(summary, path_id), x_before, demand, shortage))

    if not rows:
        SKIPPED.append("fig04: representative path rows are empty")
        return

    fig, ax = new_fig()
    x = np.arange(len(rows))
    width = 0.24
    values = np.array([[r[2], r[3], r[4]] for r in rows])
    labels = [r[1] for r in rows]
    ax.bar(x - width, values[:, 0], width, label=title("检查/结束时已储备量", "Stored amount at check/end"), color=BLUE)
    ax.bar(x, values[:, 1], width, label=title("终端要求储备量", "Required terminal reserve"), color=ORANGE)
    ax.bar(x + width, values[:, 2], width, label=title("终端储备缺口", "Terminal reserve gap"), color=RED)
    ax.set_title(title("代表路径下 LOH 库存与 TerminalLOH 检查", "LOH Inventory and TerminalLOH Check on Representative Paths"), color=BLUE, fontsize=22, pad=18)
    ax.set_ylabel(title("液态氢储备量（kg）", "LOH reserve amount (kg)"), fontsize=12)
    ax.set_xticks(x)
    ax.set_xticklabels(labels, fontsize=10)
    ax.yaxis.set_major_formatter(FuncFormatter(compact_number))
    ax.grid(axis="y", alpha=0.25)
    ax.legend(loc="upper right", frameon=False, fontsize=10)
    for idx, row in enumerate(values):
        for offset, val in zip([-width, 0, width], row):
            if val > 0:
                ax.text(idx + offset, val, fmt_value(val, 1), ha="center", va="bottom", fontsize=8, color="#25313c")
    save_current("fig04_representative_path_loh")


def plot_fig05() -> None:
    detail = load_csv(
        "selected_paths_loh_demand_detail.csv",
        ["path_id", "site_id", "x_before_demand", "TerminalLOH_site", "terminal_shortage_site", "terminal_shortage_total"],
    )
    if detail is None:
        return
    if detail.empty:
        SKIPPED.append("fig05: selected_paths_loh_demand_detail.csv is empty")
        return
    path_id = int(detail.sort_values("terminal_shortage_total", ascending=False).iloc[0]["path_id"])
    df = detail.loc[detail["path_id"].eq(path_id)].sort_values("site_id")
    if df.empty:
        SKIPPED.append("fig05: no site-level rows for high-shortage path")
        return

    fig, ax = new_fig()
    x = np.arange(len(df))
    width = 0.24
    ax.bar(x - width, df["x_before_demand"], width, label=title("本站已储备量", "Stored amount at site"), color=BLUE)
    ax.bar(x, df["TerminalLOH_site"], width, label=title("本站终端要求储备量", "Required reserve at site"), color=ORANGE)
    ax.bar(x + width, df["terminal_shortage_site"], width, label=title("本站储备缺口", "Reserve gap at site"), color=RED)
    ax.set_title(title("高短缺路径的站点级 TerminalLOH 储备检查", "Site-Level TerminalLOH Reserve Check on High-Shortage Path"), color=BLUE, fontsize=22, pad=18)
    ax.set_xlabel("site_id", fontsize=12)
    ax.set_ylabel(title("液态氢储备量（kg）", "LOH reserve amount (kg)"), fontsize=12)
    ax.set_xticks(x)
    ax.set_xticklabels([str(int(s)) for s in df["site_id"]])
    ax.grid(axis="y", alpha=0.25)
    ax.legend(loc="upper right", frameon=False, fontsize=10)
    ax.text(
        0.01,
        -0.13,
        title(f"注：path_id={path_id}。TerminalLOH 是站点级储备检查，四站总量不能替代站点分布检查。", f"Note: path_id={path_id}. TerminalLOH is checked by site, not only by four-site total."),
        transform=ax.transAxes,
        fontsize=10,
        color=GRAY,
    )
    save_current("fig05_site_terminal_check")


def plot_fig06() -> None:
    summary = load_csv("selected_path_summary.csv", ["path_id"])
    cost = load_csv(
        "selected_paths_cost_breakdown.csv",
        [
            "path_id",
            "t",
            "holding_cost",
            "production_electricity_cost",
            "electrolyzer_om_cost",
            "transport_cost",
            "normal_shortage_cost",
            "loh_demand_cost",
            "theta_value",
        ],
    )
    ts = load_csv("selected_paths_timeseries.csv", ["path_id", "t", "TerminalLOH_total", "x_total_after", "terminal_shortage_total"])
    if summary is None or cost is None or ts is None:
        return
    paths = choose_representative_paths(summary, ts)
    if not paths:
        SKIPPED.append("fig06: no representative path can be selected")
        return

    component_cols = [
        "holding_cost",
        "production_electricity_cost",
        "electrolyzer_om_cost",
        "transport_cost",
        "normal_shortage_cost",
        "loh_demand_cost",
    ]
    label_map = {
        "holding_cost": title("库存持有成本", "Holding cost"),
        "production_electricity_cost": title("制氢电费", "Production electricity"),
        "electrolyzer_om_cost": title("电解槽运维", "Electrolyzer O&M"),
        "transport_cost": title("HTT调拨成本", "HTT transport cost"),
        "normal_shortage_cost": title("正常供氢缺口罚", "Normal shortage penalty"),
        "loh_demand_cost": title("TerminalLOH缺口罚", "TerminalLOH shortage penalty"),
        "theta_value": title("未来成本近似 theta", "Future-cost approximation theta"),
    }
    colors = [GRAY, BLUE, LIGHT_BLUE, GREEN, RED, ORANGE]
    fig, axes = plt.subplots(1, len(paths), figsize=(13.333, 7.5), dpi=300, constrained_layout=False)
    fig.subplots_adjust(left=0.06, right=0.985, top=0.74, bottom=0.24, wspace=0.24)
    if len(paths) == 1:
        axes = [axes]
    for ax, path_id in zip(axes, paths):
        df = cost.loc[cost["path_id"].eq(path_id)].sort_values("t")
        bottom = np.zeros(len(df))
        x = df["t"].to_numpy()
        for col, color in zip(component_cols, colors):
            vals = pd.to_numeric(df[col], errors="coerce").fillna(0).to_numpy()
            ax.bar(x, vals, bottom=bottom, label=label_map[col], color=color, width=0.72, alpha=0.9)
            bottom += vals
        theta = pd.to_numeric(df["theta_value"], errors="coerce")
        if theta.notna().any():
            ax.plot(x, theta, color="#222222", lw=1.8, ls="--", marker="o", ms=3, label=label_map["theta_value"])
        ax.set_title(path_label(summary, path_id), color=BLUE, fontsize=12)
        ax.set_xlabel(title("MSP阶段 t", "MSP stage t"))
        ax.grid(axis="y", alpha=0.2)
        ax.yaxis.set_major_formatter(FuncFormatter(compact_number))
    axes[0].set_ylabel(title("阶段成本（元）", "Stage cost (yuan)"), fontsize=12)
    handles, labels = axes[-1].get_legend_handles_labels()
    fig.legend(handles, labels, loc="lower center", bbox_to_anchor=(0.5, 0.11), ncol=4, frameon=False, fontsize=8)
    fig.suptitle(title("代表路径阶段成本分解", "Representative Path Stage Cost Breakdown"), color=BLUE, fontsize=22, fontweight="bold", y=0.96)
    fig.text(
        0.02,
        0.02,
        title(
            "注：黑色虚线 theta 是训练模型里的未来成本近似，只作诊断；彩色柱才是本路径已经发生的阶段成本。",
            "Note: black dashed theta is a training future-cost approximation; colored bars are realized stage costs on this path.",
        ),
        color=GRAY,
        fontsize=9,
    )
    save_current("fig06_cost_breakdown")


def plot_fig07() -> None:
    edges = load_csv("selected_paths_transport_edges.csv", ["path_id", "t", "from_site", "to_site", "f_ij"])
    if edges is None:
        return
    edges["f_ij"] = pd.to_numeric(edges["f_ij"], errors="coerce").fillna(0)
    total_by_path = edges.groupby("path_id")["f_ij"].sum().sort_values(ascending=False)

    fig, ax = new_fig()
    if total_by_path.empty or float(total_by_path.iloc[0]) <= 1e-9:
        ax.set_axis_off()
        ax.text(
            0.5,
            0.55,
            title("该批代表路径中未发现非零 HTT 站间调拨量", "No nonzero HTT inter-site transport was found in selected paths"),
            ha="center",
            va="center",
            fontsize=20,
            color=BLUE,
            fontweight="bold",
            transform=ax.transAxes,
        )
        ax.text(
            0.5,
            0.44,
            title("脚本未伪造调拨量；请以 CSV 中 f_ij 字段为准。", "No transport values were fabricated; f_ij in the CSV remains the source of truth."),
            ha="center",
            va="center",
            fontsize=12,
            color=GRAY,
            transform=ax.transAxes,
        )
    else:
        path_id = int(total_by_path.index[0])
        df = edges.loc[edges["path_id"].eq(path_id)]
        by_t = df.groupby("t")["f_ij"].sum().reset_index()
        ax.plot(by_t["t"], by_t["f_ij"], color=GREEN, lw=2.6, marker="o", ms=7)
        ax.fill_between(by_t["t"], by_t["f_ij"], color=GREEN, alpha=0.12)
        ax.set_title(title("代表路径 HTT 站间调拨量变化", "Representative Path HTT Inter-Site Transport Over Time"), color=BLUE, fontsize=22, pad=18)
        ax.set_xlabel(title("MSP阶段 t", "MSP stage t"), fontsize=12)
        ax.set_ylabel(title("阶段总 HTT 调拨量（kg）", "Total HTT transport amount by stage (kg)"), fontsize=12)
        ax.grid(axis="y", alpha=0.25)
        ax.yaxis.set_major_formatter(FuncFormatter(compact_number))
        ax.text(
            0.01,
            -0.13,
            title(f"注：选择 f_ij 总量最大的代表路径 path_id={path_id}。", f"Note: selected representative path_id={path_id} with the largest total f_ij."),
            transform=ax.transAxes,
            fontsize=10,
            color=GRAY,
        )
    save_current("fig07_htt_transport")


def plot_fig08() -> None:
    summary = load_csv("selected_path_summary.csv", ["path_id"])
    mv = load_csv(
        "selected_paths_cut_marginal_value.csv",
        ["path_id", "t", "site_id", "marginal_value_of_1kg_LOH", "approx_future_value_gradient"],
    )
    if summary is None or mv is None:
        return
    if mv.empty:
        SKIPPED.append("fig08: selected_paths_cut_marginal_value.csv is empty")
        return
    if "path_type" in summary.columns and summary["path_type"].eq("high_shortage_path").any():
        path_id = int(summary.loc[summary["path_type"].eq("high_shortage_path")].iloc[0]["path_id"])
    else:
        path_id = int(mv.groupby("path_id")["marginal_value_of_1kg_LOH"].mean().sort_values(ascending=False).index[0])
    df = mv.loc[mv["path_id"].eq(path_id)].sort_values(["site_id", "t"])
    if df.empty:
        SKIPPED.append("fig08: no marginal value rows for selected path")
        return

    fig, ax = new_fig()
    palette = [BLUE, ORANGE, GREEN, RED]
    for idx, (site_id, g) in enumerate(df.groupby("site_id")):
        ax.plot(
            g["t"],
            g["marginal_value_of_1kg_LOH"],
            marker="o",
            lw=2.2,
            ms=5,
            color=palette[idx % len(palette)],
            label=f"site {int(site_id)}",
        )
    ax.set_title(title("LOH 库存边际未来价值诊断", "LOH Inventory Marginal Future Value Diagnostics"), color=BLUE, fontsize=22, pad=18)
    ax.set_xlabel(title("MSP阶段 t", "MSP stage t"), fontsize=12)
    ax.set_ylabel(title("每多 1 kg 液态氢的未来成本价值估计（元/kg）", "Estimated future-cost value of 1 kg LOH (yuan/kg)"), fontsize=12)
    ax.grid(axis="y", alpha=0.25)
    ax.yaxis.set_major_formatter(FuncFormatter(compact_number))
    ax.legend(loc="upper right", frameon=False, fontsize=10)
    ax.text(
        0.01,
        -0.13,
        title(
            f"注：path_id={path_id}；使用 CSV 字段 marginal_value_of_1kg_LOH，未把该诊断量解释为实际发生成本。",
            f"Note: path_id={path_id}; uses CSV field marginal_value_of_1kg_LOH and does not treat it as realized cost.",
        ),
        transform=ax.transAxes,
        fontsize=10,
        color=GRAY,
    )
    save_current("fig08_cut_marginal_value")


def plot_fig09() -> None:
    summary = load_csv("selected_path_summary.csv", ["path_id", "path_type"])
    ts = load_csv("selected_paths_timeseries.csv", ["path_id", "t", "k", "a", "loc", "lf", "status"])
    detail = load_csv(
        "selected_paths_loh_demand_detail.csv",
        ["path_id", "site_id", "x_before_demand", "TerminalLOH_site", "terminal_shortage_site"],
    )
    cost = load_csv(
        "selected_paths_cost_breakdown.csv",
        [
            "path_id",
            "t",
            "holding_cost",
            "production_electricity_cost",
            "electrolyzer_om_cost",
            "transport_cost",
            "normal_shortage_cost",
            "loh_demand_cost",
        ],
    )
    edges = load_csv("selected_paths_transport_edges.csv", ["path_id", "t", "f_ij"])
    mv = load_csv("selected_paths_cut_marginal_value.csv", ["path_id", "t", "site_id", "marginal_value_of_1kg_LOH"])
    if any(df is None for df in [summary, ts, detail, cost, edges, mv]):
        return

    high_rows = summary.loc[summary["path_type"].eq("high_shortage_path")]
    if high_rows.empty:
        SKIPPED.append("fig09: no high_shortage_path in selected_path_summary.csv")
        return
    path351 = 351 if summary["path_id"].eq(351).any() else int(high_rows.iloc[0]["path_id"])
    path3 = 3 if summary["path_id"].eq(3).any() else None

    ts351 = ts.loc[ts["path_id"].eq(path351)].sort_values("t")
    detail351 = detail.loc[detail["path_id"].eq(path351)].sort_values("site_id")
    if ts351.empty or detail351.empty:
        SKIPPED.append("fig09: missing path351 timeseries or site detail rows")
        return

    fig = plt.figure(figsize=(13.333, 7.5), dpi=300, constrained_layout=False)
    fig.subplots_adjust(left=0.055, right=0.985, top=0.88, bottom=0.08, hspace=0.74, wspace=0.42)
    gs = fig.add_gridspec(3, 4, height_ratios=[1.05, 1.25, 1.12], width_ratios=[1.18, 1.18, 1.05, 1.05])
    ax_timeline = fig.add_subplot(gs[0, 0:2])
    ax_key = fig.add_subplot(gs[0, 2:4])
    ax_site = fig.add_subplot(gs[1, 0:2])
    ax_cost = fig.add_subplot(gs[1, 2])
    ax_htt = fig.add_subplot(gs[1, 3])
    ax_mv = fig.add_subplot(gs[2, 0:2])
    ax_p3 = fig.add_subplot(gs[2, 2:4])

    fig.suptitle(
        title("path351 高终端短缺路径综合诊断", "Integrated Diagnostics for High Terminal-Shortage Path 351"),
        color=BLUE,
        fontsize=20,
        fontweight="bold",
        y=0.965,
    )
    fig.text(
        0.055,
        0.912,
        title(
            "核心口径：t=1~5 是普通准备阶段；t=6 到达 lf=7 后做 TerminalLOH 站点级检查；t=7~8 为 lf=8 吸收状态。",
            "Key reading: t=1-5 are normal preparation stages; t=6 is the lf=7 TerminalLOH site-level check; t=7-8 are lf=8 absorbing states.",
        ),
        color=GRAY,
        fontsize=9,
    )

    # A. State trajectory.
    ax_timeline.plot(ts351["t"], ts351["lf"], marker="o", lw=2.2, color=BLUE, label=f"path {path351}")
    ax_timeline.axvspan(5.75, 6.25, color=RED, alpha=0.12, lw=0)
    ax_timeline.axvspan(6.5, 8.5, color=GRAY, alpha=0.08, lw=0)
    for _, row in ts351.iterrows():
        t_val = float(row["t"])
        lf_val = float(row["lf"])
        if t_val in [1, 5, 6, 8]:
            ax_timeline.text(
                t_val,
                lf_val + 0.18,
                f"k={int(row['k'])}\na={int(row['a'])},loc={int(row['loc'])}",
                ha="center",
                va="bottom",
                fontsize=7,
                color="#25313c",
            )
    ax_timeline.text(6, 7.75, title("终端检查", "Terminal check"), ha="center", va="bottom", fontsize=9, color=RED, fontweight="bold")
    ax_timeline.text(7.35, 8.25, title("吸收状态", "Absorbing"), ha="center", va="bottom", fontsize=8, color=GRAY, fontweight="bold")
    ax_timeline.set_title(title("A. 路径状态推进", "A. Path state trajectory"), color=BLUE, fontsize=11, pad=8)
    ax_timeline.set_xlabel(title("MSP阶段 t", "MSP stage t"), fontsize=9)
    ax_timeline.set_ylabel("lf", fontsize=9)
    ax_timeline.set_xticks(ts351["t"].astype(int).to_list())
    ax_timeline.set_ylim(0.5, 8.8)
    ax_timeline.grid(axis="y", alpha=0.25)

    # B. Key numeric reading.
    row351 = summary.loc[summary["path_id"].eq(path351)].iloc[0]
    x_total = float(row351.get("x_total_before_demand", detail351["x_before_demand"].sum()))
    demand_total = float(row351.get("TerminalLOH_total_at_demand", detail351["TerminalLOH_site"].sum()))
    shortage_total = float(row351.get("shortage_total_at_demand", detail351["terminal_shortage_site"].sum()))
    surplus_site1 = float(detail351.loc[detail351["site_id"].eq(1), "x_before_demand"].iloc[0] - detail351.loc[detail351["site_id"].eq(1), "TerminalLOH_site"].iloc[0])
    shortage_234 = detail351.loc[detail351["site_id"].isin([2, 3, 4]), "terminal_shortage_site"].sum()
    ax_key.set_axis_off()
    key_lines = [
        (title("总库存", "Total reserve"), f"{x_total:.1f} kg", BLUE),
        (title("总目标", "Total TerminalLOH target"), f"{demand_total:.1f} kg", ORANGE),
        (title("站点级缺口", "Site-level shortage"), f"{shortage_total:.1f} kg", RED),
        (title("站1过剩", "Site 1 surplus"), f"{surplus_site1:.1f} kg", GREEN),
        (title("站2~4合计缺口", "Site 2-4 shortage"), f"{shortage_234:.1f} kg", RED),
    ]
    for idx, (lab, val, color) in enumerate(key_lines):
        y = 0.86 - idx * 0.17
        ax_key.add_patch(Rectangle((0.02, y - 0.07), 0.96, 0.11, transform=ax_key.transAxes, facecolor=PALE_BLUE, edgecolor="#d8e1e8", lw=0.8))
        ax_key.add_patch(Rectangle((0.02, y - 0.07), 0.018, 0.11, transform=ax_key.transAxes, facecolor=color, edgecolor=color, lw=0))
        ax_key.text(0.06, y, lab, transform=ax_key.transAxes, ha="left", va="center", fontsize=9, color=GRAY, fontweight="bold")
        ax_key.text(0.96, y, val, transform=ax_key.transAxes, ha="right", va="center", fontsize=13, color=BLUE, fontweight="bold")
    ax_key.text(
        0.02,
        0.02,
        title("读法：总量够不代表站点级满足；站1的过剩不能抵消站2/3/4的缺口。", "Reading: total reserve is enough, but site-level targets are not; site 1 surplus cannot offset site 2/3/4 shortages."),
        transform=ax_key.transAxes,
        ha="left",
        va="bottom",
        fontsize=8,
        color=RED,
        fontweight="bold",
    )
    ax_key.set_title(title("B. path351 关键结论", "B. Key reading for path351"), color=BLUE, fontsize=11, pad=8)

    # C. Site-level terminal check.
    x = np.arange(len(detail351))
    width = 0.24
    ax_site.bar(x - width, detail351["x_before_demand"], width, label=title("已储备", "Stored"), color=BLUE)
    ax_site.bar(x, detail351["TerminalLOH_site"], width, label=title("终端目标", "Target"), color=ORANGE)
    ax_site.bar(x + width, detail351["terminal_shortage_site"], width, label=title("缺口", "Shortage"), color=RED)
    ax_site.set_title(title("C. t=6 站点级 TerminalLOH 检查", "C. Site-level TerminalLOH check at t=6"), color=BLUE, fontsize=11, pad=8)
    ax_site.set_xlabel("site", fontsize=9)
    ax_site.set_ylabel("kg", fontsize=9)
    ax_site.set_xticks(x)
    ax_site.set_xticklabels([str(int(v)) for v in detail351["site_id"]], fontsize=8)
    ax_site.yaxis.set_major_formatter(FuncFormatter(compact_number))
    ax_site.grid(axis="y", alpha=0.25)
    ax_site.legend(loc="upper right", frameon=False, fontsize=8, ncol=3)

    # D. Realized cost composition.
    cost351 = cost.loc[cost["path_id"].eq(path351)].copy()
    ordinary_cols = ["holding_cost", "production_electricity_cost", "electrolyzer_om_cost", "transport_cost", "normal_shortage_cost"]
    ordinary_cost = float(cost351[ordinary_cols].apply(pd.to_numeric, errors="coerce").fillna(0).to_numpy().sum())
    terminal_penalty = float(pd.to_numeric(cost351["loh_demand_cost"], errors="coerce").fillna(0).sum())
    ax_cost.bar([0, 1], [ordinary_cost, terminal_penalty], color=[GREEN, RED], width=0.58)
    ax_cost.set_xticks([0, 1])
    ax_cost.set_xticklabels([title("普通成本", "Ordinary"), title("终端罚", "Terminal penalty")], fontsize=8)
    ax_cost.set_title(title("D. 成本为何被拉高", "D. Why total cost is high"), color=BLUE, fontsize=11, pad=8)
    ax_cost.set_ylabel(title("元", "yuan"), fontsize=9)
    ax_cost.yaxis.set_major_formatter(FuncFormatter(compact_number))
    ax_cost.grid(axis="y", alpha=0.25)
    for idx, val in enumerate([ordinary_cost, terminal_penalty]):
        ax_cost.text(idx, val, fmt_value(val, 0), ha="center", va="bottom", fontsize=8, color="#25313c")

    # E. HTT transport before terminal check.
    edges351 = edges.loc[edges["path_id"].eq(path351)].copy()
    edges351["f_ij"] = pd.to_numeric(edges351["f_ij"], errors="coerce").fillna(0)
    htt_by_t = edges351.groupby("t")["f_ij"].sum().reset_index()
    ax_htt.plot(htt_by_t["t"], htt_by_t["f_ij"], color=GREEN, lw=2.1, marker="o", ms=4)
    ax_htt.fill_between(htt_by_t["t"], htt_by_t["f_ij"], color=GREEN, alpha=0.14)
    ax_htt.axvline(6, color=RED, ls="--", lw=1.5)
    ax_htt.set_title(title("E. 终端前调拨", "E. Pre-terminal HTT"), color=BLUE, fontsize=11, pad=8)
    ax_htt.set_xlabel(title("阶段 t", "stage t"), fontsize=9)
    ax_htt.set_ylabel("kg", fontsize=9)
    ax_htt.yaxis.set_major_formatter(FuncFormatter(compact_number))
    ax_htt.grid(axis="y", alpha=0.25)
    ax_htt.text(0.02, 0.92, title("t=6为检查", "t=6 check"), transform=ax_htt.transAxes, fontsize=8, color=RED, fontweight="bold")

    # F. Cut marginal value, normal decision stages only.
    mv351 = mv.loc[mv["path_id"].eq(path351)].sort_values(["site_id", "t"])
    palette = [BLUE, ORANGE, GREEN, RED]
    for idx, (site_id, g) in enumerate(mv351.groupby("site_id")):
        ax_mv.plot(g["t"], g["marginal_value_of_1kg_LOH"], marker="o", lw=1.8, ms=4, color=palette[idx % 4], label=f"site {int(site_id)}")
    ax_mv.set_title(title("F. cut 边际未来价值只到 t=5", "F. Cut marginal value only before t=6"), color=BLUE, fontsize=11, pad=8)
    ax_mv.set_xlabel(title("MSP阶段 t", "MSP stage t"), fontsize=9)
    ax_mv.set_ylabel(title("元/kg", "yuan/kg"), fontsize=9)
    ax_mv.yaxis.set_major_formatter(FuncFormatter(compact_number))
    ax_mv.grid(axis="y", alpha=0.25)
    ax_mv.legend(loc="upper right", frameon=False, fontsize=7, ncol=4)

    # G. Optional path3 comparison.
    if path3 is not None:
        detail3 = detail.loc[detail["path_id"].eq(path3)].sort_values("site_id")
        if not detail3.empty:
            x3 = np.arange(len(detail3))
            ax_p3.bar(x3 - width / 2, detail3["x_before_demand"], width, label=title("已储备", "Stored"), color=BLUE, alpha=0.82)
            ax_p3.bar(x3 + width / 2, detail3["TerminalLOH_site"], width, label=title("终端目标", "Target"), color=ORANGE, alpha=0.9)
            ax_p3.plot(x3, detail3["terminal_shortage_site"], color=RED, marker="o", lw=1.6, label=title("缺口", "Shortage"))
            ax_p3.set_xticks(x3)
            ax_p3.set_xticklabels([str(int(v)) for v in detail3["site_id"]], fontsize=8)
            p3_x = float(detail3["x_before_demand"].sum())
            p3_target = float(detail3["TerminalLOH_site"].sum())
            p3_short = float(detail3["terminal_shortage_site"].sum())
            ax_p3.text(
                0.02,
                0.9,
                title(f"path3 对照：总库存 {p3_x:.1f} kg，目标 {p3_target:.1f} kg，缺口 {p3_short:.1f} kg", f"path3: reserve {p3_x:.1f} kg, target {p3_target:.1f} kg, shortage {p3_short:.1f} kg"),
                transform=ax_p3.transAxes,
                fontsize=8,
                color=GREEN,
                fontweight="bold",
            )
        else:
            ax_p3.set_axis_off()
            ax_p3.text(0.5, 0.5, title("path3 无站点级明细", "No site-level detail for path3"), ha="center", va="center", transform=ax_p3.transAxes)
    else:
        ax_p3.set_axis_off()
        ax_p3.text(0.5, 0.5, title("未找到 path3 对照", "Path3 comparison not found"), ha="center", va="center", transform=ax_p3.transAxes)
    ax_p3.set_title(title("G. path3：触发检查但无短缺", "G. path3: check reached, no shortage"), color=BLUE, fontsize=11, pad=8)
    ax_p3.set_xlabel("site", fontsize=9)
    ax_p3.set_ylabel("kg", fontsize=9)
    ax_p3.yaxis.set_major_formatter(FuncFormatter(compact_number))
    ax_p3.grid(axis="y", alpha=0.25)
    ax_p3.legend(loc="upper right", frameon=False, fontsize=7, ncol=3)

    save_current("fig09_path351_integrated_diagnostics")


def plot_fig10() -> None:
    summary = load_csv("selected_path_summary.csv", ["path_id", "path_type", "total_cost"])
    ts = load_csv("selected_paths_timeseries.csv", ["path_id", "t", "k", "a", "loc", "lf", "status"])
    detail = load_csv(
        "selected_paths_loh_demand_detail.csv",
        ["path_id", "site_id", "x_before_demand", "TerminalLOH_site", "terminal_shortage_site"],
    )
    if any(df is None for df in [summary, ts, detail]):
        return
    if not summary["path_id"].eq(351).any() or not summary["path_id"].eq(3).any():
        SKIPPED.append("fig10: path351 or path3 is missing in selected_path_summary.csv")
        return

    path_ids = [351, 3]
    path_names = {
        351: title("path351：高终端短缺", "path351: high terminal shortage"),
        3: title("path3：触发检查但无短缺", "path3: check reached, no shortage"),
    }
    path_colors = {351: RED, 3: GREEN}

    fig = plt.figure(figsize=(13.333, 7.5), dpi=300, constrained_layout=False)
    fig.subplots_adjust(left=0.055, right=0.985, top=0.86, bottom=0.09, hspace=0.48, wspace=0.32)
    gs = fig.add_gridspec(2, 3, height_ratios=[0.95, 1.3], width_ratios=[1.15, 1.15, 0.9])
    ax_traj = fig.add_subplot(gs[0, 0:2])
    ax_summary = fig.add_subplot(gs[0, 2])
    ax_351 = fig.add_subplot(gs[1, 0])
    ax_3 = fig.add_subplot(gs[1, 1])
    ax_cost = fig.add_subplot(gs[1, 2])

    fig.suptitle(
        title("path351 与 path3 的 TerminalLOH 检查对比", "TerminalLOH Check Comparison: path351 vs path3"),
        color=BLUE,
        fontsize=20,
        fontweight="bold",
        y=0.955,
    )
    fig.text(
        0.055,
        0.895,
        title(
            "path3 已单独画出：它也触发 lf=7 检查，但各站库存都高于本站目标，所以终端缺口为 0；path351 则是总量够但站点级错配。",
            "path3 is shown explicitly: it reaches the lf=7 check but all sites meet their targets, while path351 has enough total reserve but wrong site distribution.",
        ),
        fontsize=9,
        color=GRAY,
    )

    # Trajectory comparison.
    for pid in path_ids:
        path_ts = ts.loc[ts["path_id"].eq(pid)].sort_values("t")
        ax_traj.plot(
            path_ts["t"],
            path_ts["lf"],
            marker="o",
            lw=2.4,
            ms=5,
            color=path_colors[pid],
            label=path_names[pid],
        )
        demand_rows = path_ts.loc[path_ts["status"].eq("loh_demand_stage")]
        if not demand_rows.empty:
            demand = demand_rows.iloc[0]
            ax_traj.scatter([demand["t"]], [demand["lf"]], s=90, color=path_colors[pid], edgecolor="white", zorder=5)
            ax_traj.text(
                float(demand["t"]),
                float(demand["lf"]) + 0.25,
                title(f"检查 t={int(demand['t'])}\nk={int(demand['k'])}", f"check t={int(demand['t'])}\nk={int(demand['k'])}"),
                ha="center",
                va="bottom",
                fontsize=8,
                color=path_colors[pid],
                fontweight="bold",
            )
    ax_traj.axhline(7, color=GRAY, ls="--", lw=1.2, alpha=0.7)
    ax_traj.set_title(title("A. 两条路径的 lf 推进和检查时点", "A. lf trajectory and check timing"), color=BLUE, fontsize=12, pad=8)
    ax_traj.set_xlabel(title("MSP阶段 t", "MSP stage t"), fontsize=10)
    ax_traj.set_ylabel("lf", fontsize=10)
    ax_traj.set_xticks(range(1, 9))
    ax_traj.set_ylim(0.5, 8.8)
    ax_traj.grid(axis="y", alpha=0.25)
    ax_traj.legend(loc="upper left", frameon=False, fontsize=9)

    # Summary box.
    ax_summary.set_axis_off()
    rows = []
    for pid in path_ids:
        pdetail = detail.loc[detail["path_id"].eq(pid)]
        srow = summary.loc[summary["path_id"].eq(pid)].iloc[0]
        reserve = float(pdetail["x_before_demand"].sum())
        target = float(pdetail["TerminalLOH_site"].sum())
        shortage = float(pdetail["terminal_shortage_site"].sum())
        total_cost = float(srow["total_cost"])
        rows.append((pid, reserve, target, shortage, total_cost))
    y0 = 0.82
    for idx, (pid, reserve, target, shortage, total_cost) in enumerate(rows):
        y = y0 - idx * 0.43
        ax_summary.add_patch(Rectangle((0.02, y - 0.27), 0.96, 0.31, transform=ax_summary.transAxes, facecolor=PALE_BLUE, edgecolor="#d8e1e8", lw=0.9))
        ax_summary.add_patch(Rectangle((0.02, y - 0.27), 0.025, 0.31, transform=ax_summary.transAxes, facecolor=path_colors[pid], edgecolor=path_colors[pid], lw=0))
        ax_summary.text(0.07, y, path_names[pid], transform=ax_summary.transAxes, ha="left", va="center", fontsize=9, color=path_colors[pid], fontweight="bold")
        ax_summary.text(0.07, y - 0.08, title(f"库存/目标：{reserve:.1f}/{target:.1f} kg", f"reserve/target: {reserve:.1f}/{target:.1f} kg"), transform=ax_summary.transAxes, fontsize=8, color="#25313c")
        ax_summary.text(0.07, y - 0.16, title(f"终端缺口：{shortage:.1f} kg", f"shortage: {shortage:.1f} kg"), transform=ax_summary.transAxes, fontsize=8, color=RED if shortage > 0 else GREEN, fontweight="bold")
        ax_summary.text(0.07, y - 0.24, title(f"总成本：{fmt_value(total_cost, 0)} 元", f"total cost: {fmt_value(total_cost, 0)} yuan"), transform=ax_summary.transAxes, fontsize=8, color="#25313c")
    ax_summary.set_title(title("B. 关键数值", "B. Key numbers"), color=BLUE, fontsize=12, pad=8)

    def draw_site_check(ax, pid: int):
        pdetail = detail.loc[detail["path_id"].eq(pid)].sort_values("site_id")
        x = np.arange(len(pdetail))
        width = 0.24
        ax.bar(x - width, pdetail["x_before_demand"], width, label=title("已储备", "Stored"), color=BLUE)
        ax.bar(x, pdetail["TerminalLOH_site"], width, label=title("终端目标", "Target"), color=ORANGE)
        ax.bar(x + width, pdetail["terminal_shortage_site"], width, label=title("缺口", "Shortage"), color=RED)
        ax.set_title(path_names[pid], color=path_colors[pid], fontsize=12, pad=8)
        ax.set_xlabel("site", fontsize=10)
        ax.set_ylabel("kg", fontsize=10)
        ax.set_xticks(x)
        ax.set_xticklabels([str(int(v)) for v in pdetail["site_id"]])
        ax.yaxis.set_major_formatter(FuncFormatter(compact_number))
        ax.grid(axis="y", alpha=0.25)
        for xpos, value in zip(x + width, pdetail["terminal_shortage_site"]):
            value = float(value)
            if value > 1e-8:
                ax.text(xpos, value, fmt_value(value, 1), ha="center", va="bottom", fontsize=8, color=RED, fontweight="bold")
        reserve = float(pdetail["x_before_demand"].sum())
        target = float(pdetail["TerminalLOH_site"].sum())
        shortage = float(pdetail["terminal_shortage_site"].sum())
        ax.text(
            0.02,
            0.93,
            title(f"总库存 {reserve:.1f} kg；目标 {target:.1f} kg；缺口 {shortage:.1f} kg", f"reserve {reserve:.1f}; target {target:.1f}; shortage {shortage:.1f} kg"),
            transform=ax.transAxes,
            fontsize=8,
            color=RED if shortage > 0 else GREEN,
            fontweight="bold",
        )

    draw_site_check(ax_351, 351)
    draw_site_check(ax_3, 3)
    ax_3.legend(loc="upper right", frameon=False, fontsize=8, ncol=3)

    # Cost comparison.
    labels = [path_names[351].split("：")[0], path_names[3].split("：")[0]]
    total_costs = [float(summary.loc[summary["path_id"].eq(pid), "total_cost"].iloc[0]) for pid in path_ids]
    shortages = [float(detail.loc[detail["path_id"].eq(pid), "terminal_shortage_site"].sum()) for pid in path_ids]
    ax_cost.bar([0, 1], total_costs, color=[RED, GREEN], width=0.56)
    ax_cost.set_xticks([0, 1])
    ax_cost.set_xticklabels(labels, fontsize=9)
    ax_cost.set_title(title("E. 总成本对比", "E. Total cost comparison"), color=BLUE, fontsize=12, pad=8)
    ax_cost.set_ylabel(title("元", "yuan"), fontsize=10)
    ax_cost.yaxis.set_major_formatter(FuncFormatter(compact_number))
    ax_cost.grid(axis="y", alpha=0.25)
    for idx, (cost_val, shortage) in enumerate(zip(total_costs, shortages)):
        ax_cost.text(idx, cost_val, fmt_value(cost_val, 0), ha="center", va="bottom", fontsize=8, color="#25313c")
        ax_cost.text(
            idx,
            cost_val * 0.55,
            title(f"缺口\n{shortage:.1f} kg", f"shortage\n{shortage:.1f} kg"),
            ha="center",
            va="center",
            fontsize=9,
            color="white",
            fontweight="bold",
        )

    save_current("fig10_path351_vs_path3_terminal_check")


def plot_fig11() -> None:
    summary = load_csv("selected_path_summary.csv", ["path_id", "path_type"])
    ts = load_csv("selected_paths_timeseries.csv", ["path_id", "t", "lf", "status", "production_total", "theta_value"])
    site = load_csv("selected_paths_site_balance.csv", ["path_id", "t", "site_id", "production_r"])
    cost = load_csv(
        "selected_paths_cost_breakdown.csv",
        ["path_id", "t", "production_electricity_cost", "electrolyzer_om_cost"],
    )
    mv = load_csv("selected_paths_cut_marginal_value.csv", ["path_id", "t", "site_id", "marginal_value_of_1kg_LOH"])
    if any(df is None for df in [summary, ts, site, cost, mv]):
        return

    preferred = [1, 3, 351]
    available = set(summary["path_id"].astype(int).tolist())
    path_ids = [pid for pid in preferred if pid in available]
    if not path_ids:
        path_ids = choose_representative_paths(summary, ts)
    if not path_ids:
        SKIPPED.append("fig11: no representative path can be selected")
        return

    fig, axes = plt.subplots(1, len(path_ids), figsize=(13.333, 7.5), dpi=300, constrained_layout=False)
    fig.subplots_adjust(left=0.06, right=0.965, top=0.78, bottom=0.22, wspace=0.32)
    if len(path_ids) == 1:
        axes = [axes]

    fig.suptitle(title("B/C 与实际制氢量诊断", "B/C Value-Cost and Production Diagnostics"), color=BLUE, fontsize=21, fontweight="bold", y=0.965)
    fig.text(
        0.06,
        0.87,
        title(
            "B=marginal_value_of_1kg_LOH（多 1kg 库存可减少的未来成本估计）；C=本期单位制氢成本。B 与 C 才能解释“制 1kg 是否值得”，A=theta 是未来成本总额，不能直接和 C 比。",
            "B=marginal_value_of_1kg_LOH; C=current unit production cost. B/C explains whether one more kg is worthwhile; theta is a total future-cost level.",
        ),
        fontsize=9,
        color=GRAY,
    )

    legend_handles = []
    legend_labels = []
    for ax, path_id in zip(axes, path_ids):
        path_ts = ts.loc[ts["path_id"].eq(path_id)].sort_values("t").copy()
        path_cost = cost.loc[cost["path_id"].eq(path_id)].sort_values("t").copy()
        path_mv = mv.loc[mv["path_id"].eq(path_id)].copy()
        path_site = site.loc[site["path_id"].eq(path_id), ["t", "site_id", "production_r"]].copy()
        if path_ts.empty or path_cost.empty:
            continue

        if not path_mv.empty:
            mv_detail = path_mv.merge(path_site, on=["t", "site_id"], how="left")
            mv_detail["production_r"] = pd.to_numeric(mv_detail["production_r"], errors="coerce").fillna(0)
            mv_detail["weighted_B_piece"] = mv_detail["production_r"] * pd.to_numeric(mv_detail["marginal_value_of_1kg_LOH"], errors="coerce")
            mv_by_t = (
                mv_detail.groupby("t")
                .agg(
                    B_avg=("marginal_value_of_1kg_LOH", "mean"),
                    B_min=("marginal_value_of_1kg_LOH", "min"),
                    B_max=("marginal_value_of_1kg_LOH", "max"),
                    production_for_weight=("production_r", "sum"),
                    weighted_B_sum=("weighted_B_piece", "sum"),
                )
                .reset_index()
            )
            mv_by_t["B_prod_weighted"] = mv_by_t["weighted_B_sum"] / mv_by_t["production_for_weight"].where(mv_by_t["production_for_weight"].gt(1e-9))
            mv_by_t = mv_by_t[["t", "B_avg", "B_min", "B_max", "B_prod_weighted"]]
        else:
            mv_by_t = pd.DataFrame(columns=["t", "B_avg", "B_min", "B_max", "B_prod_weighted"])
        cost_cols = ["t", "production_electricity_cost", "electrolyzer_om_cost"]
        df = path_ts[["t", "lf", "status", "production_total", "theta_value"]].merge(path_cost[cost_cols], on="t", how="left").merge(mv_by_t, on="t", how="left")
        df["production_total"] = pd.to_numeric(df["production_total"], errors="coerce").fillna(0)
        prod_cost = pd.to_numeric(df["production_electricity_cost"], errors="coerce").fillna(0) + pd.to_numeric(df["electrolyzer_om_cost"], errors="coerce").fillna(0)
        df["C_unit_production_cost"] = prod_cost / df["production_total"].where(df["production_total"].gt(1e-9))

        x = pd.to_numeric(df["t"], errors="coerce").to_numpy()
        b_avg = pd.to_numeric(df["B_avg"], errors="coerce")
        b_min = pd.to_numeric(df["B_min"], errors="coerce")
        b_max = pd.to_numeric(df["B_max"], errors="coerce")
        b_weighted = pd.to_numeric(df["B_prod_weighted"], errors="coerce")
        c_unit = pd.to_numeric(df["C_unit_production_cost"], errors="coerce")
        prod = pd.to_numeric(df["production_total"], errors="coerce").fillna(0).to_numpy()

        ax_prod = ax.twinx()
        prod_bar = ax_prod.bar(x, prod, color=LIGHT_BLUE, alpha=0.28, width=0.55, label=title("实际制氢量", "Actual production"))
        ax_prod.set_ylim(0, max(100, float(np.nanmax(prod)) * 1.25 if len(prod) else 100))
        ax_prod.tick_params(axis="y", labelsize=8, colors=GRAY)
        if ax is axes[-1]:
            ax_prod.set_ylabel(title("制氢量（kg）", "Production (kg)"), fontsize=9, color=GRAY)

        band_mask = b_min.notna() & b_max.notna()
        if band_mask.any():
            ax.fill_between(x[band_mask.to_numpy()], b_min[band_mask], b_max[band_mask], color=BLUE, alpha=0.12, label=title("B四站范围", "B site range"))
        b_line = ax.plot(x, b_avg, color=BLUE, marker="o", lw=2.0, ms=4, label=title("B：四站平均", "B: site average"))[0]
        bw_line = ax.plot(x, b_weighted, color="#7b3294", marker="D", lw=1.8, ms=3.8, ls="--", label=title("B：按制氢量加权", "B: production-weighted"))[0]
        c_line = ax.plot(x, c_unit, color=ORANGE, marker="s", lw=2.0, ms=4, label=title("C：单位制氢成本", "C: unit production cost"))[0]

        decision_b = b_weighted.where(b_weighted.notna(), b_avg)
        profitable = decision_b.notna() & c_unit.notna() & decision_b.gt(c_unit)
        if profitable.any():
            ax.scatter(x[profitable.to_numpy()], decision_b[profitable], s=54, facecolor="white", edgecolor=GREEN, linewidth=1.6, zorder=5, label=title("B>C", "B>C"))

        check_rows = df.loc[df["status"].isin(["loh_demand_stage", "dissipated_absorb"]) | df["lf"].eq(7)]
        if not check_rows.empty:
            check_status = str(check_rows.iloc[0]["status"])
            check_label = title("吸收", "absorb") if check_status == "dissipated_absorb" else title("检查", "check")
            check_t = float(check_rows.iloc[0]["t"])
            ax.axvline(check_t, color=RED, ls="--", lw=1.4, alpha=0.75)
            ax.text(check_t, 0.96, check_label, transform=ax.get_xaxis_transform(), ha="center", va="top", fontsize=8, color=RED, fontweight="bold")

        ax.set_title(path_label(summary, path_id), color=BLUE, fontsize=12, pad=10)
        ax.set_xlabel(title("MSP阶段 t", "MSP stage t"), fontsize=10)
        if ax is axes[0]:
            ax.set_ylabel(title("元/kg", "yuan/kg"), fontsize=10)
        ax.set_xticks(range(1, 9))
        y_candidates = pd.concat([b_max, b_weighted, c_unit], ignore_index=True).dropna()
        if not y_candidates.empty:
            ax.set_ylim(0, max(10, float(y_candidates.max()) * 1.18))
        ax.yaxis.set_major_formatter(FuncFormatter(compact_number))
        ax.grid(axis="y", alpha=0.24)

        for t_val, b_val, c_val in zip(x, decision_b, c_unit):
            if pd.notna(b_val) and pd.notna(c_val):
                label = "B>C" if float(b_val) > float(c_val) else "B<C"
                color = GREEN if float(b_val) > float(c_val) else RED
                ax.text(t_val, max(float(b_val), float(c_val)) * 1.04, label, ha="center", va="bottom", fontsize=7, color=color, fontweight="bold")

        if not legend_handles:
            handles, labels = ax.get_legend_handles_labels()
            handles2, labels2 = ax_prod.get_legend_handles_labels()
            legend_handles = handles + [prod_bar] + handles2[1:]
            legend_labels = labels + [title("实际制氢量", "Actual production")] + labels2[1:]

    if legend_handles:
        fig.legend(legend_handles[:6], legend_labels[:6], loc="lower center", bbox_to_anchor=(0.5, 0.1), ncol=6, frameon=False, fontsize=8)
    fig.text(
        0.06,
        0.045,
        title(
            "注：蓝线是四站平均 B；紫色虚线是按实际制氢量加权的 B，更接近解释本期制氢落在哪些站。浅蓝带为四站最小-最大范围；该图是诊断图，不替代完整 MSP 目标函数。",
            "Note: blue is site-average B; purple is production-weighted B, which better explains where production occurs. The blue band is min-max across sites.",
        ),
        fontsize=8.5,
        color=GRAY,
    )
    save_current("fig11_value_cost_production_diagnostics")


def main() -> int:
    if not DETAILS_DIR.exists():
        raise FileNotFoundError(f"details directory not found: {DETAILS_DIR}")
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    plot_fig01()
    plot_fig02()
    plot_fig03()
    plot_fig04()
    plot_fig05()
    plot_fig06()
    plot_fig07()
    plot_fig08()
    plot_fig09()
    plot_fig10()
    plot_fig11()

    print("Generated files:")
    for path in GENERATED:
        print(path)
    if SKIPPED:
        print("\nSkipped or warnings:")
        for item in SKIPPED:
            print(item)
    else:
        print("\nSkipped or warnings: none")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
