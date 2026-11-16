"""Turn the CSV exports in output/ into the three charts shown in the README."""

from __future__ import annotations

from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd
from matplotlib.colors import LinearSegmentedColormap

OUT = Path(__file__).resolve().parents[1] / "output"

BLUE, ORANGE = "#2a78d6", "#eb6834"
INK, MUTED, GRID, SURFACE = "#0b0b0b", "#898781", "#e1e0d9", "#fcfcfb"
SEQUENTIAL = LinearSegmentedColormap.from_list("blue", ["#cde2fb", "#86b6ef", "#2a78d6", "#0d366b"])

plt.rcParams.update(
    {
        "figure.facecolor": SURFACE,
        "axes.facecolor": SURFACE,
        "savefig.facecolor": SURFACE,
        "axes.edgecolor": "#c3c2b7",
        "axes.spines.top": False,
        "axes.spines.right": False,
        "axes.grid": True,
        "axes.grid.axis": "y",
        "grid.color": GRID,
        "grid.linewidth": 0.8,
        "axes.axisbelow": True,
        "axes.titlelocation": "left",
        "axes.titleweight": "bold",
        "axes.titlesize": 12,
        "text.color": INK,
        "axes.labelcolor": MUTED,
        "xtick.color": MUTED,
        "ytick.color": MUTED,
        "font.size": 10,
    }
)


def monthly_revenue() -> None:
    df = pd.read_csv(OUT / "monthly_revenue.csv", parse_dates=["order_month"])
    fig, ax = plt.subplots(figsize=(9, 4))
    ax.bar(
        df["order_month"], df["net_revenue"] / 1000, width=22, color="#9ec5f4", label="Monthly net revenue"
    )
    ax.plot(
        df["order_month"],
        df["revenue_3m_avg"] / 1000,
        color=BLUE,
        linewidth=2,
        label="3-month moving average",
    )
    ax.set_title("Net revenue per month (thousand EUR)")
    ax.legend(frameon=False, loc="upper left")
    fig.tight_layout()
    fig.savefig(OUT / "monthly_revenue.png", dpi=150)
    plt.close(fig)


def cohort_retention() -> None:
    df = pd.read_csv(OUT / "cohort_retention.csv", parse_dates=["cohort_month"])
    # Quarterly cohorts keep the heatmap readable; weight months by cohort size.
    df["cohort"] = df["cohort_month"].dt.to_period("Q").astype(str)
    df = df[df["months_since_first"].between(1, 12)]
    sizes = df.groupby(["cohort", "months_since_first"])[["active_customers", "cohort_size"]].sum()
    grid = (100 * sizes["active_customers"] / sizes["cohort_size"]).unstack()
    fig, ax = plt.subplots(figsize=(9, 4.6))
    image = ax.imshow(grid.to_numpy(), cmap=SEQUENTIAL, aspect="auto", vmin=0)
    ax.set_xticks(range(grid.shape[1]), grid.columns)
    ax.set_yticks(range(grid.shape[0]), grid.index)
    ax.set_xlabel("Months since first order")
    ax.set_title("Share of each cohort ordering again, by month (%)")
    ax.grid(False)
    threshold = grid.max().max() * 0.6
    for (row, col), value in pd.DataFrame(grid.to_numpy()).stack().dropna().items():
        ax.text(
            col,
            row,
            f"{value:.0f}",
            ha="center",
            va="center",
            fontsize=8,
            color="#ffffff" if value > threshold else INK,
        )
    fig.colorbar(image, ax=ax, shrink=0.8)
    fig.tight_layout()
    fig.savefig(OUT / "cohort_retention.png", dpi=150)
    plt.close(fig)


def rfm_segments() -> None:
    df = pd.read_csv(OUT / "03_rfm_segments.csv").sort_values("pct_of_revenue")
    fig, ax = plt.subplots(figsize=(9, 4))
    height = 0.38
    y = range(len(df))
    ax.barh(
        [i + height / 2 for i in y], df["pct_of_customers"], height, color=BLUE, label="Share of customers"
    )
    ax.barh([i - height / 2 for i in y], df["pct_of_revenue"], height, color=ORANGE, label="Share of revenue")
    for i, (customers, revenue) in enumerate(zip(df["pct_of_customers"], df["pct_of_revenue"], strict=True)):
        ax.text(customers + 0.5, i + height / 2, f"{customers:.0f}%", va="center", fontsize=8, color=INK)
        ax.text(revenue + 0.5, i - height / 2, f"{revenue:.0f}%", va="center", fontsize=8, color=INK)
    ax.set_yticks(list(y), df["segment"])
    ax.tick_params(axis="y", colors=INK)
    ax.grid(axis="y", visible=False)
    ax.grid(axis="x", visible=True)
    ax.set_title("RFM segments: share of customers vs. share of revenue")
    ax.legend(frameon=False, loc="lower right")
    fig.tight_layout()
    fig.savefig(OUT / "rfm_segments.png", dpi=150)
    plt.close(fig)


if __name__ == "__main__":
    monthly_revenue()
    cohort_retention()
    rfm_segments()
    print("   output/monthly_revenue.png, cohort_retention.png, rfm_segments.png")
