import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
import numpy as np
from fractions import Fraction

df = pd.read_csv("../experiment_data_clean.csv")

PATTERNS_ORDER = [
    "Azure VM-based",
    "Azure Container-based",
    "Azure Serverless-based",
    "AWS VM-based",
    "AWS Container-based",
    "AWS Serverless-based",
]

AZURE_COLOR = "#0078D4"
AWS_COLOR   = "#FF9900"

PATTERN_LABELS = {
    "Azure VM-based":         "Azure\nVM-based",
    "Azure Container-based":  "Azure\nContainer-based",
    "Azure Serverless-based": "Azure\nServerless-based",
    "AWS VM-based":           "AWS\nVM-based",
    "AWS Container-based":    "AWS\nContainer-based",
    "AWS Serverless-based":   "AWS\nServerless-based",
}

CORRECTNESS_EXCLUDE = {"AWS Serverless-based"}  # Lambda→S3 values are null


def fraction_label(v):
    """Convert a float correctness score to a readable fraction string."""
    f = Fraction(v).limit_denominator(12)
    return str(f)


# 1. time_secs histogram, n=20 

fig, axes = plt.subplots(2, 3, figsize=(13, 7))
fig.suptitle("Completion Time (seconds)", fontsize=15, fontweight="bold", y=1.01)

for idx, pattern in enumerate(PATTERNS_ORDER):
    row, col_idx = divmod(idx, 3)
    ax = axes[row][col_idx]
    color  = AZURE_COLOR if pattern.startswith("Azure") else AWS_COLOR
    values = df.loc[df["pattern"] == pattern, "time_secs"].dropna()
    assert len(values) == 20, f"{pattern}: expected 20, got {len(values)}"

    n_bins = min(max(int(np.ceil(np.log2(len(values)) + 1)), 5), 10)
    ax.hist(values, bins=n_bins, color=color, edgecolor="white", linewidth=0.6)
    ax.set_title(PATTERN_LABELS[pattern], fontsize=10, pad=6)
    ax.set_xlabel("Time (s)", fontsize=9)
    ax.set_ylabel("Number of participants", fontsize=9)
    ax.yaxis.set_major_locator(mticker.MaxNLocator(integer=True))
    ax.tick_params(labelsize=8)
    ax.spines[["top", "right"]].set_visible(False)

plt.tight_layout()
plt.savefig("histogram_time_secs.png", dpi=150, bbox_inches="tight")
print("Saved histogram_time_secs.png")
plt.show()


# 2. component_correctness histogram, but exclude AWS Serverless-based

# Collect all discrete values across included patterns for a consistent x-axis
included_patterns = [p for p in PATTERNS_ORDER if p not in CORRECTNESS_EXCLUDE]
all_correctness_vals = sorted(
    df.loc[df["pattern"].isin(included_patterns), "component_correctness"]
    .dropna()
    .unique()
)
x_labels = [fraction_label(v) for v in all_correctness_vals]

fig, axes = plt.subplots(2, 3, figsize=(13, 7))
fig.suptitle("Component Correctness", fontsize=15, fontweight="bold", y=1.01)

for idx, pattern in enumerate(PATTERNS_ORDER):
    row, col_idx = divmod(idx, 3)
    ax = axes[row][col_idx]

    if pattern in CORRECTNESS_EXCLUDE:
        ax.set_visible(False)
        continue

    color  = AZURE_COLOR if pattern.startswith("Azure") else AWS_COLOR
    counts = (
        df.loc[df["pattern"] == pattern, "component_correctness"]
        .dropna()
        .value_counts()
        .reindex(all_correctness_vals, fill_value=0)
    )
    assert counts.sum() == 20, f"{pattern}: expected 20, got {counts.sum()}"

    ax.bar(x_labels, counts.values, color=color, edgecolor="white", linewidth=0.6)
    ax.set_title(PATTERN_LABELS[pattern], fontsize=10, pad=6)
    ax.set_xlabel("Correctness score", fontsize=9)
    ax.set_ylabel("Number of participants", fontsize=9)
    ax.yaxis.set_major_locator(mticker.MaxNLocator(integer=True))
    ax.tick_params(axis="x", labelsize=8)
    ax.tick_params(axis="y", labelsize=8)
    ax.spines[["top", "right"]].set_visible(False)

plt.tight_layout()
plt.savefig("histogram_component_correctness.png", dpi=150, bbox_inches="tight")
print("Saved histogram_component_correctness.png")
plt.show()


# 3. difficulty histogram, x-axis always 1–5, where 1 indicates very easy and 5 indicates very difficult

DIFFICULTY_LEVELS = [1, 2, 3, 4, 5]

fig, axes = plt.subplots(2, 3, figsize=(13, 7))
fig.suptitle("Perceived Difficulty", fontsize=15, fontweight="bold", y=1.01)

for idx, pattern in enumerate(PATTERNS_ORDER):
    row, col_idx = divmod(idx, 3)
    ax = axes[row][col_idx]
    color  = AZURE_COLOR if pattern.startswith("Azure") else AWS_COLOR
    counts = (
        df.loc[df["pattern"] == pattern, "difficulty"]
        .dropna()
        .value_counts()
        .reindex(DIFFICULTY_LEVELS, fill_value=0)
    )
    assert counts.sum() == 20, f"{pattern}: expected 20, got {counts.sum()}"

    ax.bar([str(v) for v in DIFFICULTY_LEVELS], counts.values,
           color=color, edgecolor="white", linewidth=0.6)
    ax.set_title(PATTERN_LABELS[pattern], fontsize=10, pad=6)
    ax.set_xlabel("Difficulty rating (1–5)", fontsize=9)
    ax.set_ylabel("Number of participants", fontsize=9)
    ax.yaxis.set_major_locator(mticker.MaxNLocator(integer=True))
    ax.tick_params(labelsize=8)
    ax.spines[["top", "right"]].set_visible(False)

plt.tight_layout()
plt.savefig("histogram_difficulty.png", dpi=150, bbox_inches="tight")
print("Saved histogram_difficulty.png")
plt.show()
