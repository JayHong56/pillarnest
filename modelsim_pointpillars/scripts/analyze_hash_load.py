import argparse
import os
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt


HASH_DEPTH = 256
CAM_DEPTH = 16


def read_hash_load_csv(path: str) -> pd.DataFrame:
    df = pd.read_csv(path)

    required_cols = {"Global_Timer", "Total_Load", "cam_load"}
    missing = required_cols - set(df.columns)
    if missing:
        raise ValueError(f"{path} missing columns: {missing}")

    df = df[["Global_Timer", "Total_Load", "cam_load"]].copy()

    for col in ["Global_Timer", "Total_Load", "cam_load"]:
        df[col] = pd.to_numeric(df[col], errors="coerce")

    df = df.dropna()
    df["Global_Timer"] = df["Global_Timer"].astype(np.int64)
    df["Total_Load"] = df["Total_Load"].astype(np.int64)
    df["cam_load"] = df["cam_load"].astype(np.int64)

    df = df.sort_values("Global_Timer").reset_index(drop=True)

    if (df["Total_Load"] < 0).any():
        print(f"[WARN] {path}: Total_Load contains negative values")

    if (df["Total_Load"] > HASH_DEPTH).any():
        print(f"[WARN] {path}: Total_Load exceeds HASH_DEPTH={HASH_DEPTH}")

    if (df["cam_load"] < 0).any():
        print(f"[WARN] {path}: cam_load contains negative values")

    if (df["cam_load"] > CAM_DEPTH).any():
        print(f"[WARN] {path}: cam_load exceeds CAM_DEPTH={CAM_DEPTH}")

    df["Hash_Load_Ratio"] = df["Total_Load"] / HASH_DEPTH
    df["CAM_Load_Ratio"] = df["cam_load"] / CAM_DEPTH

    return df


def summarize_one(df: pd.DataFrame, name: str) -> dict:
    load = df["Total_Load"].to_numpy()
    cam = df["cam_load"].to_numpy()

    load_diff = np.diff(load)
    cam_diff = np.diff(cam)

    summary = {
        "name": name,
        "samples": len(df),
        "timer_start": int(df["Global_Timer"].iloc[0]),
        "timer_end": int(df["Global_Timer"].iloc[-1]),

        # Hash table load
        "final_load": int(load[-1]),
        "max_load": int(load.max()),
        "min_load": int(load.min()),
        "mean_load": float(load.mean()),
        "std_load": float(load.std()),
        "max_load_ratio": float(load.max() / HASH_DEPTH),
        "mean_load_ratio": float(load.mean() / HASH_DEPTH),
        "cycles_hash_ge_50_percent": int((load >= HASH_DEPTH * 0.50).sum()),
        "cycles_hash_ge_70_percent": int((load >= HASH_DEPTH * 0.70).sum()),
        "cycles_hash_ge_80_percent": int((load >= HASH_DEPTH * 0.80).sum()),
        "cycles_hash_ge_90_percent": int((load >= HASH_DEPTH * 0.90).sum()),
        "cycles_hash_ge_95_percent": int((load >= HASH_DEPTH * 0.95).sum()),
        "cycles_hash_full": int((load >= HASH_DEPTH).sum()),
        "num_hash_load_increase": int((load_diff > 0).sum()),
        "num_hash_load_decrease": int((load_diff < 0).sum()),
        "max_hash_one_cycle_increase": int(load_diff.max()) if len(load_diff) else 0,
        "max_hash_one_cycle_decrease": int(load_diff.min()) if len(load_diff) else 0,

        # CAM load
        "final_cam_load": int(cam[-1]),
        "max_cam_load": int(cam.max()),
        "min_cam_load": int(cam.min()),
        "mean_cam_load": float(cam.mean()),
        "std_cam_load": float(cam.std()),
        "max_cam_load_ratio": float(cam.max() / CAM_DEPTH),
        "mean_cam_load_ratio": float(cam.mean() / CAM_DEPTH),
        "cycles_cam_nonzero": int((cam > 0).sum()),
        "cycles_cam_ge_25_percent": int((cam >= CAM_DEPTH * 0.25).sum()),
        "cycles_cam_ge_50_percent": int((cam >= CAM_DEPTH * 0.50).sum()),
        "cycles_cam_ge_75_percent": int((cam >= CAM_DEPTH * 0.75).sum()),
        "cycles_cam_ge_90_percent": int((cam >= CAM_DEPTH * 0.90).sum()),
        "cycles_cam_full": int((cam >= CAM_DEPTH).sum()),
        "num_cam_load_increase": int((cam_diff > 0).sum()),
        "num_cam_load_decrease": int((cam_diff < 0).sum()),
        "max_cam_one_cycle_increase": int(cam_diff.max()) if len(cam_diff) else 0,
        "max_cam_one_cycle_decrease": int(cam_diff.min()) if len(cam_diff) else 0,
    }

    return summary


def print_summary(summary: dict):
    print("=" * 90)
    print(f"[SUMMARY] {summary['name']}")
    print("=" * 90)

    print(f"samples                    : {summary['samples']}")
    print(f"timer range                : {summary['timer_start']} -> {summary['timer_end']}")

    print("-" * 90)
    print("[HASH TABLE LOAD]")
    print(f"final load                 : {summary['final_load']} / {HASH_DEPTH}")
    print(f"max load                   : {summary['max_load']} / {HASH_DEPTH}")
    print(f"min load                   : {summary['min_load']} / {HASH_DEPTH}")
    print(f"mean load                  : {summary['mean_load']:.3f} / {HASH_DEPTH}")
    print(f"std load                   : {summary['std_load']:.3f}")
    print(f"max load ratio             : {summary['max_load_ratio'] * 100:.2f}%")
    print(f"mean load ratio            : {summary['mean_load_ratio'] * 100:.2f}%")
    print(f"cycles hash >= 50%         : {summary['cycles_hash_ge_50_percent']}")
    print(f"cycles hash >= 70%         : {summary['cycles_hash_ge_70_percent']}")
    print(f"cycles hash >= 80%         : {summary['cycles_hash_ge_80_percent']}")
    print(f"cycles hash >= 90%         : {summary['cycles_hash_ge_90_percent']}")
    print(f"cycles hash >= 95%         : {summary['cycles_hash_ge_95_percent']}")
    print(f"cycles hash full           : {summary['cycles_hash_full']}")
    print(f"hash load increase cycles  : {summary['num_hash_load_increase']}")
    print(f"hash load decrease cycles  : {summary['num_hash_load_decrease']}")
    print(f"max hash one-cycle increase: {summary['max_hash_one_cycle_increase']}")
    print(f"max hash one-cycle decrease: {summary['max_hash_one_cycle_decrease']}")

    print("-" * 90)
    print("[CAM LOAD]")
    print(f"final cam load             : {summary['final_cam_load']} / {CAM_DEPTH}")
    print(f"max cam load               : {summary['max_cam_load']} / {CAM_DEPTH}")
    print(f"min cam load               : {summary['min_cam_load']} / {CAM_DEPTH}")
    print(f"mean cam load              : {summary['mean_cam_load']:.3f} / {CAM_DEPTH}")
    print(f"std cam load               : {summary['std_cam_load']:.3f}")
    print(f"max cam load ratio         : {summary['max_cam_load_ratio'] * 100:.2f}%")
    print(f"mean cam load ratio        : {summary['mean_cam_load_ratio'] * 100:.2f}%")
    print(f"cycles cam nonzero         : {summary['cycles_cam_nonzero']}")
    print(f"cycles cam >= 25%          : {summary['cycles_cam_ge_25_percent']}")
    print(f"cycles cam >= 50%          : {summary['cycles_cam_ge_50_percent']}")
    print(f"cycles cam >= 75%          : {summary['cycles_cam_ge_75_percent']}")
    print(f"cycles cam >= 90%          : {summary['cycles_cam_ge_90_percent']}")
    print(f"cycles cam full            : {summary['cycles_cam_full']}")
    print(f"cam load increase cycles   : {summary['num_cam_load_increase']}")
    print(f"cam load decrease cycles   : {summary['num_cam_load_decrease']}")
    print(f"max cam one-cycle increase : {summary['max_cam_one_cycle_increase']}")
    print(f"max cam one-cycle decrease : {summary['max_cam_one_cycle_decrease']}")


def plot_one(df: pd.DataFrame, name: str, out_dir: str):
    os.makedirs(out_dir, exist_ok=True)

    # Hash total load curve
    plt.figure(figsize=(12, 5))
    plt.plot(df["Global_Timer"], df["Total_Load"], linewidth=1.2, label="Total_Load")
    plt.axhline(HASH_DEPTH * 0.50, linestyle="--", linewidth=0.8, label="Hash 50%")
    plt.axhline(HASH_DEPTH * 0.70, linestyle="--", linewidth=0.8, label="Hash 70%")
    plt.axhline(HASH_DEPTH * 0.80, linestyle="--", linewidth=0.8, label="Hash 80%")
    plt.axhline(HASH_DEPTH * 0.90, linestyle="--", linewidth=0.8, label="Hash 90%")
    plt.axhline(HASH_DEPTH, linestyle="--", linewidth=0.8, label="Hash Full")
    plt.xlabel("Global_Timer")
    plt.ylabel("Total_Load")
    plt.title(f"Hash Table Total Load: {name}")
    plt.grid(True, alpha=0.3)
    plt.legend()
    plt.tight_layout()

    out_path = os.path.join(out_dir, f"{name}_hash_load_curve.png")
    plt.savefig(out_path, dpi=200)
    plt.close()

    # CAM load curve
    plt.figure(figsize=(12, 5))
    plt.plot(df["Global_Timer"], df["cam_load"], linewidth=1.2, label="cam_load")
    plt.axhline(CAM_DEPTH * 0.25, linestyle="--", linewidth=0.8, label="CAM 25%")
    plt.axhline(CAM_DEPTH * 0.50, linestyle="--", linewidth=0.8, label="CAM 50%")
    plt.axhline(CAM_DEPTH * 0.75, linestyle="--", linewidth=0.8, label="CAM 75%")
    plt.axhline(CAM_DEPTH, linestyle="--", linewidth=0.8, label="CAM Full")
    plt.xlabel("Global_Timer")
    plt.ylabel("cam_load")
    plt.title(f"CAM Load: {name}")
    plt.grid(True, alpha=0.3)
    plt.legend()
    plt.tight_layout()

    out_path_cam = os.path.join(out_dir, f"{name}_cam_load_curve.png")
    plt.savefig(out_path_cam, dpi=200)
    plt.close()

    # Combined normalized load curve
    plt.figure(figsize=(12, 5))
    plt.plot(df["Global_Timer"], df["Hash_Load_Ratio"] * 100, linewidth=1.2, label="Hash Load Ratio (%)")
    plt.plot(df["Global_Timer"], df["CAM_Load_Ratio"] * 100, linewidth=1.2, label="CAM Load Ratio (%)")
    plt.axhline(100, linestyle="--", linewidth=0.8, label="Full")
    plt.xlabel("Global_Timer")
    plt.ylabel("Load Ratio (%)")
    plt.title(f"Normalized Hash/CAM Load: {name}")
    plt.grid(True, alpha=0.3)
    plt.legend()
    plt.tight_layout()

    out_path_norm = os.path.join(out_dir, f"{name}_normalized_load_curve.png")
    plt.savefig(out_path_norm, dpi=200)
    plt.close()

    # Histograms
    plt.figure(figsize=(8, 5))
    plt.hist(df["Total_Load"], bins=64)
    plt.xlabel("Total_Load")
    plt.ylabel("Count")
    plt.title(f"Hash Load Histogram: {name}")
    plt.grid(True, alpha=0.3)
    plt.tight_layout()

    out_path_hist = os.path.join(out_dir, f"{name}_hash_load_hist.png")
    plt.savefig(out_path_hist, dpi=200)
    plt.close()

    plt.figure(figsize=(8, 5))
    plt.hist(df["cam_load"], bins=range(0, CAM_DEPTH + 2), align="left")
    plt.xlabel("cam_load")
    plt.ylabel("Count")
    plt.title(f"CAM Load Histogram: {name}")
    plt.grid(True, alpha=0.3)
    plt.tight_layout()

    out_path_cam_hist = os.path.join(out_dir, f"{name}_cam_load_hist.png")
    plt.savefig(out_path_cam_hist, dpi=200)
    plt.close()

    print(f"[PLOT] saved: {out_path}")
    print(f"[PLOT] saved: {out_path_cam}")
    print(f"[PLOT] saved: {out_path_norm}")
    print(f"[PLOT] saved: {out_path_hist}")
    print(f"[PLOT] saved: {out_path_cam_hist}")


def compare_two(df_a: pd.DataFrame, name_a: str, df_b: pd.DataFrame, name_b: str, out_dir: str):
    os.makedirs(out_dir, exist_ok=True)

    merged = pd.merge(
        df_a[["Global_Timer", "Total_Load", "cam_load"]],
        df_b[["Global_Timer", "Total_Load", "cam_load"]],
        on="Global_Timer",
        how="inner",
        suffixes=(f"_{name_a}", f"_{name_b}")
    )

    if merged.empty:
        raise ValueError("No overlapping Global_Timer between two CSV files.")

    hash_a = f"Total_Load_{name_a}"
    hash_b = f"Total_Load_{name_b}"
    cam_a = f"cam_load_{name_a}"
    cam_b = f"cam_load_{name_b}"

    hash_diff = merged[hash_b] - merged[hash_a]
    cam_diff = merged[cam_b] - merged[cam_a]

    def print_compare_metric(label: str, diff: pd.Series, col_a: str, col_b: str):
        abs_diff = diff.abs()
        mae = abs_diff.mean()
        rmse = np.sqrt((diff ** 2).mean())
        max_abs = abs_diff.max()
        max_abs_idx = abs_diff.idxmax()

        print("-" * 90)
        print(f"[COMPARE] {label}: {name_b} - {name_a}")
        print(f"mean diff                 : {diff.mean():.3f}")
        print(f"MAE                       : {mae:.3f}")
        print(f"RMSE                      : {rmse:.3f}")
        print(f"max abs diff              : {int(max_abs)}")
        print(f"max abs diff timer        : {int(merged.loc[max_abs_idx, 'Global_Timer'])}")
        print(f"{name_a} at maxdiff        : {int(merged.loc[max_abs_idx, col_a])}")
        print(f"{name_b} at maxdiff        : {int(merged.loc[max_abs_idx, col_b])}")

    print("=" * 90)
    print(f"[COMPARE] {name_a} vs {name_b}")
    print("=" * 90)
    print(f"overlap samples            : {len(merged)}")
    print(f"timer range                : {int(merged['Global_Timer'].iloc[0])} -> {int(merged['Global_Timer'].iloc[-1])}")

    print_compare_metric("Hash Total_Load", hash_diff, hash_a, hash_b)
    print_compare_metric("CAM cam_load", cam_diff, cam_a, cam_b)

    # Hash curve comparison
    plt.figure(figsize=(12, 5))
    plt.plot(merged["Global_Timer"], merged[hash_a], linewidth=1.2, label=f"{name_a} Total_Load")
    plt.plot(merged["Global_Timer"], merged[hash_b], linewidth=1.2, label=f"{name_b} Total_Load")
    plt.axhline(HASH_DEPTH, linestyle="--", linewidth=0.8, label="Hash Full")
    plt.xlabel("Global_Timer")
    plt.ylabel("Total_Load")
    plt.title(f"Hash Load Comparison: {name_a} vs {name_b}")
    plt.grid(True, alpha=0.3)
    plt.legend()
    plt.tight_layout()

    out_hash_curve = os.path.join(out_dir, f"compare_{name_a}_vs_{name_b}_hash_curve.png")
    plt.savefig(out_hash_curve, dpi=200)
    plt.close()

    # CAM curve comparison
    plt.figure(figsize=(12, 5))
    plt.plot(merged["Global_Timer"], merged[cam_a], linewidth=1.2, label=f"{name_a} cam_load")
    plt.plot(merged["Global_Timer"], merged[cam_b], linewidth=1.2, label=f"{name_b} cam_load")
    plt.axhline(CAM_DEPTH, linestyle="--", linewidth=0.8, label="CAM Full")
    plt.xlabel("Global_Timer")
    plt.ylabel("cam_load")
    plt.title(f"CAM Load Comparison: {name_a} vs {name_b}")
    plt.grid(True, alpha=0.3)
    plt.legend()
    plt.tight_layout()

    out_cam_curve = os.path.join(out_dir, f"compare_{name_a}_vs_{name_b}_cam_curve.png")
    plt.savefig(out_cam_curve, dpi=200)
    plt.close()

    # Hash difference
    plt.figure(figsize=(12, 5))
    plt.plot(merged["Global_Timer"], hash_diff, linewidth=1.0)
    plt.axhline(0, linestyle="--", linewidth=0.8)
    plt.xlabel("Global_Timer")
    plt.ylabel(f"{name_b} - {name_a}")
    plt.title(f"Hash Load Difference: {name_b} - {name_a}")
    plt.grid(True, alpha=0.3)
    plt.tight_layout()

    out_hash_diff = os.path.join(out_dir, f"compare_{name_a}_vs_{name_b}_hash_diff.png")
    plt.savefig(out_hash_diff, dpi=200)
    plt.close()

    # CAM difference
    plt.figure(figsize=(12, 5))
    plt.plot(merged["Global_Timer"], cam_diff, linewidth=1.0)
    plt.axhline(0, linestyle="--", linewidth=0.8)
    plt.xlabel("Global_Timer")
    plt.ylabel(f"{name_b} - {name_a}")
    plt.title(f"CAM Load Difference: {name_b} - {name_a}")
    plt.grid(True, alpha=0.3)
    plt.tight_layout()

    out_cam_diff = os.path.join(out_dir, f"compare_{name_a}_vs_{name_b}_cam_diff.png")
    plt.savefig(out_cam_diff, dpi=200)
    plt.close()

    print(f"[PLOT] saved: {out_hash_curve}")
    print(f"[PLOT] saved: {out_cam_curve}")
    print(f"[PLOT] saved: {out_hash_diff}")
    print(f"[PLOT] saved: {out_cam_diff}")

    return merged


def main():
    parser = argparse.ArgumentParser(
        description="Visualize and compare hash table load and CAM load CSV files."
    )

    parser.add_argument(
        "--csv",
        required=True,
        help="First CSV file. Required columns: Global_Timer, Total_Load, cam_load."
    )

    parser.add_argument(
        "--csv2",
        default=None,
        help="Second CSV file for comparison."
    )

    parser.add_argument(
        "--name",
        default="hash_a",
        help="Name of first CSV, e.g. mult_hash."
    )

    parser.add_argument(
        "--name2",
        default="hash_b",
        help="Name of second CSV, e.g. h3_hash."
    )

    parser.add_argument(
        "--out",
        default="hash_load_result",
        help="Output directory for plots."
    )

    args = parser.parse_args()

    df_a = read_hash_load_csv(args.csv)
    summary_a = summarize_one(df_a, args.name)
    print_summary(summary_a)
    plot_one(df_a, args.name, args.out)

    if args.csv2 is not None:
        df_b = read_hash_load_csv(args.csv2)
        summary_b = summarize_one(df_b, args.name2)
        print_summary(summary_b)
        plot_one(df_b, args.name2, args.out)
        compare_two(df_a, args.name, df_b, args.name2, args.out)


if __name__ == "__main__":
    main()

"""
python E:\verilog\pillarnest\modelsim_pointpillars\scripts\analyze_hash_load.py ^
  --csv E:\verilog\pillarnest\modelsim_pointpillars_32\hash_load_over_time_mulhash.csv ^
  --name mult_hash ^
  --csv2 E:\verilog\pillarnest\modelsim_pointpillars\hash_load_over_time.csv ^
  --name2 h3_hash


"""
    