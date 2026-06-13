import pandas as pd
import numpy as np
from scipy import stats
from statsmodels.stats.multitest import multipletests

df = pd.read_csv("../experiment_data_clean.csv")

COMPARISONS = [
    ("VM-based",        "Azure VM-based",        "AWS VM-based"),
    ("Container-based", "Azure Container-based",  "AWS Container-based"),
    ("Serverless-based","Azure Serverless-based", "AWS Serverless-based"),
]

METRICS = ["time_secs", "component_correctness", "difficulty"]

# component_correctness is skipped for serverless (AWS Lambda→S3 all null)
SKIP = {("Serverless-based", "component_correctness")}


def cliffs_delta(azure_vals, aws_vals):
    """Cliff's delta = (2*U1)/(n1*n2) - 1, range [-1, 1]."""
    # two sided because there was no expectation at first
    u1, _ = stats.mannwhitneyu(azure_vals, aws_vals, alternative="two-sided")
    return (2 * u1) / (len(azure_vals) * len(aws_vals)) - 1

# from Romano et al. (2006)
def delta_label(d):
    a = abs(d)
    if a < 0.147:  return "negligible"
    if a < 0.330:  return "small"
    if a < 0.474:  return "medium"
    return "large"


# Collect raw results 
records = []

for model, azure_pattern, aws_pattern in COMPARISONS:
    for metric in METRICS:
        if (model, metric) in SKIP:
            continue

        azure_vals = df.loc[df["pattern"] == azure_pattern, metric].dropna().values
        aws_vals   = df.loc[df["pattern"] == aws_pattern,   metric].dropna().values

        # two sided because there was no expectation at first
        # U = 0-400, higher means azure value ranks higher than aws
        # p = below 0.05 means that the difference is statistically significant
        u_stat, p_val = stats.mannwhitneyu(azure_vals, aws_vals, alternative="two-sided")
        # cliff delta tells how large the difference in practice since n=20 per group sample is small
        # closer to +1: every Azure value is larger than every AWS value
        # closer to -1: every AWS value is larger than every Azure value
        # closer to 0: the two groups are perfectly overlapping
        delta = cliffs_delta(azure_vals, aws_vals)

        records.append({
            "Deployment model":  model,
            "Metric": metric,
            "Mean (Azure)": azure_vals.mean(),
            "Mean (AWS)": aws_vals.mean(),
            "Median (Azure)": np.median(azure_vals),
            "Median (AWS)": np.median(aws_vals),
            "IQR (Azure)": np.percentile(azure_vals, 75) - np.percentile(azure_vals, 25),
            "IQR (AWS)": np.percentile(aws_vals,   75) - np.percentile(aws_vals,   25),
            "U": u_stat,
            "p": p_val,
            "Cliff's delta": delta,
            "Effect size": delta_label(delta),
        })

results = pd.DataFrame(records)

# Holm-Bonferroni correction across all 8 tests 
# adjust the p values upwards so the false positive rates stay at 0.05
reject, p_adj, _, _ = multipletests(results["p"].values, method="holm")
results["p_adj (Holm)"] = p_adj
results["Significant"]  = reject

# Format and print 
display = results[[
    "Deployment model", "Metric",
    "Mean (Azure)", "Mean (AWS)",
    "Median (Azure)", "Median (AWS)",
    "IQR (Azure)", "IQR (AWS)",
    "U", "p", "p_adj (Holm)",
    "Cliff's delta", "Effect size", "Significant",
]].copy()

display["Mean (Azure)"]   = display["Mean (Azure)"].map(lambda x: f"{x:.3f}")
display["Mean (AWS)"]     = display["Mean (AWS)"].map(lambda x: f"{x:.3f}")
display["Median (Azure)"] = display["Median (Azure)"].map(lambda x: f"{x:.3f}")
display["Median (AWS)"]   = display["Median (AWS)"].map(lambda x: f"{x:.3f}")
display["IQR (Azure)"]    = display["IQR (Azure)"].map(lambda x: f"{x:.3f}")
display["IQR (AWS)"]      = display["IQR (AWS)"].map(lambda x: f"{x:.3f}")
display["U"]             = display["U"].map(lambda x: f"{x:.1f}")
display["p"]             = display["p"].map(lambda x: f"{x:.4f}")
display["p_adj (Holm)"]  = display["p_adj (Holm)"].map(lambda x: f"{x:.4f}")
display["Cliff's delta"] = display["Cliff's delta"].map(lambda x: f"{x:+.3f}")

print("\nMann-Whitney U tests: Azure vs AWS per deployment model (Holm-Bonferroni corrected)")
print(f"Total tests: {len(results)}  |  α = 0.05\n")
print(display.to_string(index=False))
print()

# Save to CSV 
results.to_csv("mann_whitney_results.csv", index=False, float_format="%.6f")
print("Saved mann_whitney_results.csv")
