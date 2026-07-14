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
from matplotlib.ticker import FuncFormatter, PercentFormatter


ROOT = Path(__file__).resolve().parents[1]
DETAILS_DIR = ROOT / "output_h2" / "details"
PRE_DIR = ROOT / "output_h2" / "figures" / "msp_results" / "pre"

BLUE = "#1f4e79"
ORANGE = "#f28e2b"
GREEN = "#59a14f"
RED = "#c44e52"
GRAY = "#6f7782"
LIGHT_BLUE = "#9ecae1"
PALE_BLUE = "#eef4f8"


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


def fmt_value(value: float, decimals: int = 1) -> str:
    if pd.isna(value):
        return "NA"
    value = float(value)
    if abs(value) >= 1000:
        return f"{value:,.0f}"
    return f"{value:,.{decimals}f}"


def load_required_csv(name: str, cols: list[str]) -> pd.DataFrame:
    path = DETAILS_DIR / name
    if not path.exists():
        raise FileNotFoundError(f"Missing required CSV: {path}")
    df = pd.read_csv(path)
    missing = [col for col in cols if col not in df.columns]
    if missing:
        raise ValueError(f"{name} missing columns: {missing}")
    return df


def add_metric_card(ax, x: float, y: float, w: float, h: float, label: str, value: str, color: str) -> None:
    ax.add_patch(Rectangle((x, y), w, h, transform=ax.transAxes, facecolor=PALE_BLUE, edgecolor="#d8e1e8", lw=0.9))
    ax.add_patch(Rectangle((x, y), 0.012, h, transform=ax.transAxes, facecolor=color, edgecolor=color, lw=0))
    ax.text(x + 0.028, y + h * 0.63, value, transform=ax.transAxes, fontsize=15, color=color, fontweight="bold", ha="left", va="center")
    ax.text(x + 0.028, y + h * 0.28, label, transform=ax.transAxes, fontsize=8.5, color=GRAY, ha="left", va="center")


def plot_cost_shortage_summary() -> None:
    costs_df = load_required_csv("h2_oos_path_costs.csv", ["total_cost"])
    terminal_df = load_required_csv("h2_terminal_summary.csv", ["terminal_reserve_shortage"])
    metrics_df = load_required_csv("oos_risk_metrics.csv", ["mean_cost", "VaR_95", "CVaR_95", "mean_terminal_shortage", "max_terminal_shortage"])

    costs = pd.to_numeric(costs_df["total_cost"], errors="coerce").dropna().to_numpy(dtype=float)
    shortages = pd.to_numeric(terminal_df["terminal_reserve_shortage"], errors="coerce").fillna(0).to_numpy(dtype=float)
    metrics = metrics_df.iloc[0]
    if costs.size == 0 or shortages.size == 0:
        raise ValueError("Cost or terminal shortage series is empty.")

    zero_shortage_rate = float(np.mean(shortages <= 1e-9))
    positive_shortages = shortages[shortages > 1e-9]
    positive_rate = 1 - zero_shortage_rate

    c_sorted = np.sort(costs)
    ecdf = np.arange(1, len(c_sorted) + 1) / len(c_sorted)
    c_p50 = float(np.quantile(costs, 0.50))
    c_p90 = float(np.quantile(costs, 0.90))
    c_p95 = float(np.quantile(costs, 0.95))
    c_p99 = float(np.quantile(costs, 0.99))
    c_p995 = float(np.quantile(costs, 0.995))

    s_p50 = float(np.quantile(positive_shortages, 0.50)) if positive_shortages.size else 0.0
    s_p90 = float(np.quantile(positive_shortages, 0.90)) if positive_shortages.size else 0.0
    s_p95 = float(np.quantile(positive_shortages, 0.95)) if positive_shortages.size else 0.0
    s_max = float(np.max(shortages))

    fig = plt.figure(figsize=(13.333, 7.5), dpi=300, constrained_layout=False)
    fig.subplots_adjust(left=0.055, right=0.985, top=0.84, bottom=0.10, wspace=0.34, hspace=0.55)
    gs = fig.add_gridspec(2, 2, height_ratios=[1.05, 1.0], width_ratios=[1.28, 1.0])
    ax_cost = fig.add_subplot(gs[0, 0])
    ax_cards = fig.add_subplot(gs[0, 1])
    ax_short_split = fig.add_subplot(gs[1, 0])
    ax_short_tail = fig.add_subplot(gs[1, 1])

    fig.suptitle(title("OOS 路径成本与 TerminalLOH 要求满足情况统计汇总", "OOS Path Cost and TerminalLOH Requirement Satisfaction Summary"), color=BLUE, fontsize=21, fontweight="bold", y=0.955)

    ax_cost.plot(c_sorted, ecdf, color=BLUE, lw=2.4)
    ax_cost.fill_between(c_sorted, ecdf, 0, where=c_sorted >= c_p95, color=ORANGE, alpha=0.14)
    for val, label, color in [(c_p50, "P50", GREEN), (c_p90, "P90", ORANGE), (c_p95, "P95", RED), (c_p99, "P99", RED)]:
        ax_cost.axvline(val, color=color, ls="--", lw=1.4, alpha=0.75)
        ax_cost.text(val, 0.06, label, rotation=90, va="bottom", ha="right", fontsize=8, color=color, fontweight="bold")
    ax_cost.set_xlim(0, c_p995 * 1.05)
    ax_cost.set_ylim(0, 1.01)
    ax_cost.set_title(title("A. OOS 路径总成本累计分布", "A. Empirical CDF of OOS path total cost"), color=BLUE, fontsize=13, pad=10)
    ax_cost.set_xlabel(title("OOS 路径总成本 total_cost（元，显示至 P99.5）", "OOS path total_cost (yuan, up to P99.5)"), fontsize=10)
    ax_cost.set_ylabel(title("累计路径占比", "Cumulative path share"), fontsize=10)
    ax_cost.xaxis.set_major_formatter(FuncFormatter(compact_number))
    ax_cost.yaxis.set_major_formatter(PercentFormatter(1.0, decimals=0))
    ax_cost.grid(axis="both", alpha=0.22)
    ax_cost.text(
        0.03,
        0.87,
        title(
            f"均值 {fmt_value(metrics['mean_cost'], 0)} 元；CVaR95 {fmt_value(metrics['CVaR_95'], 0)} 元；最大值 {fmt_value(np.max(costs), 0)} 元",
            f"Mean {fmt_value(metrics['mean_cost'], 0)}; CVaR95 {fmt_value(metrics['CVaR_95'], 0)}; max {fmt_value(np.max(costs), 0)}",
        ),
        transform=ax_cost.transAxes,
        fontsize=8.5,
        color="#25313c",
        bbox=dict(facecolor="white", edgecolor="#d8e1e8", boxstyle="round,pad=0.28"),
    )

    ax_cards.set_axis_off()
    add_metric_card(ax_cards, 0.02, 0.62, 0.46, 0.26, title("平均成本", "Mean cost"), f"{fmt_value(metrics['mean_cost'], 0)} 元", BLUE)
    add_metric_card(ax_cards, 0.52, 0.62, 0.46, 0.26, "CVaR95", f"{fmt_value(metrics['CVaR_95'], 0)} 元", RED)
    add_metric_card(ax_cards, 0.02, 0.26, 0.46, 0.26, title("TerminalLOH 要求满足路径", "TerminalLOH satisfied paths"), f"{zero_shortage_rate * 100:.1f}%", GREEN)
    add_metric_card(ax_cards, 0.52, 0.26, 0.46, 0.26, title("最大 TerminalLOH 缺口", "Max TerminalLOH gap"), f"{fmt_value(s_max, 1)} kg", RED)

    ax_short_split.barh([0], [zero_shortage_rate], color=GREEN, height=0.42, label=title("TerminalLOH 要求满足", "TerminalLOH satisfied"))
    ax_short_split.barh([0], [positive_rate], left=[zero_shortage_rate], color=RED, height=0.42, label=title("TerminalLOH 要求未满足", "TerminalLOH not satisfied"))
    ax_short_split.text(zero_shortage_rate / 2, 0, f"{zero_shortage_rate * 100:.1f}%", ha="center", va="center", fontsize=13, color="white", fontweight="bold")
    if positive_rate > 0.025:
        ax_short_split.text(zero_shortage_rate + positive_rate / 2, 0, f"{positive_rate * 100:.1f}%", ha="center", va="center", fontsize=13, color="white", fontweight="bold")
    else:
        ax_short_split.text(min(0.98, zero_shortage_rate + positive_rate + 0.015), 0, f"{positive_rate * 100:.1f}%", ha="left", va="center", fontsize=10, color=RED, fontweight="bold")
    ax_short_split.set_xlim(0, 1)
    ax_short_split.set_yticks([])
    ax_short_split.set_xlabel(title("路径占比", "Path share"), fontsize=10)
    ax_short_split.xaxis.set_major_formatter(PercentFormatter(1.0, decimals=0))
    ax_short_split.set_title(title("B. TerminalLOH 要求满足路径占比", "B. Share of TerminalLOH satisfied paths"), color=BLUE, fontsize=13, pad=10)
    ax_short_split.grid(axis="x", alpha=0.22)
    ax_short_split.legend(loc="lower center", bbox_to_anchor=(0.5, -0.38), ncol=2, frameon=False, fontsize=9)

    if positive_shortages.size:
        bins = np.linspace(0, max(s_p95 * 1.1, 1), 18)
        clipped = positive_shortages[positive_shortages <= bins[-1]]
        ax_short_tail.hist(clipped, bins=bins, color=LIGHT_BLUE, edgecolor="white", linewidth=0.6)
        for val, label, color in [(s_p50, "P50", GREEN), (s_p90, "P90", ORANGE), (s_p95, "P95", RED)]:
            ax_short_tail.axvline(val, color=color, ls="--", lw=1.3)
            ax_short_tail.text(val, ax_short_tail.get_ylim()[1] * 0.92, label, rotation=90, va="top", ha="right", fontsize=8, color=color, fontweight="bold")
        ax_short_tail.text(
            0.98,
            0.88,
            title(f"最大 {fmt_value(s_max, 1)} kg", f"max {fmt_value(s_max, 1)} kg"),
            transform=ax_short_tail.transAxes,
            ha="right",
            fontsize=9,
            color=RED,
            fontweight="bold",
        )
    else:
        ax_short_tail.text(0.5, 0.5, title("所有路径均达到 TerminalLOH 要求", "All paths satisfy TerminalLOH requirement"), ha="center", va="center", transform=ax_short_tail.transAxes, color=GREEN, fontsize=12, fontweight="bold")
    ax_short_tail.set_title(title("C. TerminalLOH 要求未满足路径的缺口分布", "C. TerminalLOH gap distribution of unsatisfied paths"), color=BLUE, fontsize=13, pad=10)
    ax_short_tail.set_xlabel(title("TerminalLOH 缺口（kg，显示至未满足路径 P95）", "TerminalLOH gap (kg, up to unsatisfied-path P95)"), fontsize=10)
    ax_short_tail.set_ylabel(title("路径数量", "Path count"), fontsize=10)
    ax_short_tail.yaxis.set_major_formatter(FuncFormatter(compact_number))
    ax_short_tail.grid(axis="y", alpha=0.22)

    PRE_DIR.mkdir(parents=True, exist_ok=True)
    png = PRE_DIR / "pre_fig01_02_cost_shortage_summary.png"
    svg = PRE_DIR / "pre_fig01_02_cost_shortage_summary.svg"
    plt.savefig(png, dpi=300)
    plt.savefig(svg)
    plt.close(fig)
    print(png)
    print(svg)


def main() -> int:
    plot_cost_shortage_summary()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
