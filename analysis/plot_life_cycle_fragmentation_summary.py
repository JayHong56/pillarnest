from __future__ import annotations

import argparse
import csv
import re
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from PIL import Image

plt.rcParams.update(
    {
        "font.family": "Times New Roman",
        "font.size": 10,
        "mathtext.fontset": "custom",
        "mathtext.rm": "Times New Roman",
        "mathtext.it": "Times New Roman:italic",
        "mathtext.bf": "Times New Roman:bold",
        "xtick.direction": "in",
        "ytick.direction": "in",
        "xtick.major.size": 3.5,
        "ytick.major.size": 3.5,
        "legend.frameon": False,
        "svg.fonttype": "none",
        "pdf.fonttype": 42,
        "ps.fonttype": 42,
    }
)


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_INPUT_DIR = ROOT / "analysis" / "outputs"
DEFAULT_FIG_DIR = ROOT / "analysis"
DEFAULT_CROPPED_OUTPUT = ROOT / "analysis" / "life_cycle_fragmentation_summary_cropped.png"
TICK_LABEL_SIZE = 14
LEGEND_FONT_SIZE = 14

TARGET_METRICS = (
    "points_in_fragmented_logical_voxels",
)

DEFAULT_HASH_CAPACITY = 256


def read_metrics_file(path: Path) -> dict[str, str]:
    metrics: dict[str, str] = {}
    with path.open("r", newline="", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        for row in reader:
            metric = (row.get("metric") or "").strip()
            value = (row.get("value") or "").strip()
            if metric:
                metrics[metric] = value
    return metrics


def infer_life_cycle(path: Path, metrics: dict[str, str]) -> int:
    if "life_cycle" in metrics:
        return int(float(metrics["life_cycle"]))

    match = re.search(r"life(\d+)_fragmentation_metrics\.csv$", path.name)
    if match:
        return int(match.group(1))

    raise ValueError(f"Cannot infer life_cycle from {path}")


def find_hash_load_file(input_dir: Path, life_cycle: int) -> Path:
    matches = sorted(input_dir.glob(f"life{life_cycle}_hash_load*.csv"))
    if not matches:
        raise ValueError(f"No hash load CSV found for life_cycle={life_cycle}")
    return matches[0]


def read_average_hash_load(path: Path, hash_capacity: int) -> float:
    total = 0.0
    count = 0
    with path.open("r", newline="", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        if not reader.fieldnames:
            raise ValueError(f"Empty hash load CSV: {path}")

        normalized_fieldnames = {name.strip(): name for name in reader.fieldnames}
        hash_load_field = normalized_fieldnames.get("hash_load")
        total_load_field = normalized_fieldnames.get("Total_Load")

        if hash_load_field is None and total_load_field is None:
            raise ValueError(f"Missing hash_load or Total_Load column in {path}")

        for row in reader:
            if hash_load_field is not None:
                value = float((row.get(hash_load_field) or "0").strip())
            else:
                value = float((row.get(total_load_field) or "0").strip()) / hash_capacity
            total += value
            count += 1

    if count == 0:
        raise ValueError(f"No hash load rows found in {path}")
    return total / count


def collect_rows(input_dir: Path, hash_capacity: int) -> list[dict[str, int | float | str]]:
    rows: list[dict[str, int | float | str]] = []
    for path in sorted(input_dir.glob("*fragmentation_metrics.csv")):
        metrics = read_metrics_file(path)
        if not metrics:
            continue

        life_cycle = infer_life_cycle(path, metrics)
        hash_load_path = find_hash_load_file(input_dir, life_cycle)
        row: dict[str, int | float | str] = {
            "life_cycle": life_cycle,
            "source_file": str(path),
            "hash_load_source_file": str(hash_load_path),
            "avg_hash_load": read_average_hash_load(hash_load_path, hash_capacity),
        }
        for metric in TARGET_METRICS:
            if metric not in metrics:
                raise ValueError(f"Missing metric '{metric}' in {path}")
            row[metric] = int(float(metrics[metric]))
        rows.append(row)

    rows.sort(key=lambda r: int(r["life_cycle"]))
    return rows


def write_summary_csv(
    rows: list[dict[str, int | float | str]],
    output_path: Path,
    fallback_path: Path | None = None,
) -> Path:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    candidates = [output_path, output_path.with_name(f"{output_path.stem}_new{output_path.suffix}")]
    if fallback_path is not None:
        fallback_path.parent.mkdir(parents=True, exist_ok=True)
        candidates.append(fallback_path)

    f = None
    last_error: PermissionError | None = None
    for candidate in candidates:
        try:
            output_path = candidate
            f = output_path.open("w", newline="", encoding="utf-8")
            break
        except PermissionError as exc:
            last_error = exc

    if f is None:
        raise last_error or PermissionError(f"Cannot write summary CSV: {output_path}")

    with f:
        fieldnames = [
            "life_cycle",
            *TARGET_METRICS,
            "avg_hash_load",
            "source_file",
            "hash_load_source_file",
        ]
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)
    return output_path


def save_figure_with_fallback(fig, path: Path, fallback_dir: Path | None = None, **kwargs) -> Path:
    candidates = [path, path.with_name(f"{path.stem}_new{path.suffix}")]
    if fallback_dir is not None:
        fallback_dir.mkdir(parents=True, exist_ok=True)
        candidates.append(fallback_dir / path.name)
        candidates.append(fallback_dir / f"{path.stem}_new{path.suffix}")
    last_error: PermissionError | None = None
    for candidate in candidates:
        try:
            fig.savefig(candidate, **kwargs)
            return candidate
        except PermissionError as exc:
            last_error = exc
    raise last_error or PermissionError(f"Cannot write figure: {path}")


def find_nonwhite_box(path: Path, threshold: int = 250) -> tuple[int, int, int, int]:
    image = Image.open(path).convert("RGB")
    try:
        width, height = image.size
        min_x = width
        min_y = height
        max_x = 0
        max_y = 0
        pixels = image.load()

        for y in range(height):
            for x in range(width):
                r, g, b = pixels[x, y]
                if r < threshold or g < threshold or b < threshold:
                    min_x = min(min_x, x)
                    min_y = min(min_y, y)
                    max_x = max(max_x, x)
                    max_y = max(max_y, y)

        if min_x > max_x or min_y > max_y:
            raise ValueError(f"No non-white content found in {path}")
        return min_x, min_y, max_x, max_y
    finally:
        image.close()


def crop_by_own_content_box(
    input_path: Path,
    output_path: Path,
    padding: int,
    top_padding: int,
) -> Path:
    image = Image.open(input_path)
    try:
        width, height = image.size
    finally:
        image.close()

    left, top, right, bottom = find_nonwhite_box(input_path)
    crop_box = (
        max(0, left - padding),
        max(0, top - top_padding),
        min(width, right + padding + 1),
        min(height, bottom + padding + 1),
    )

    image = Image.open(input_path)
    try:
        cropped = image.crop(crop_box)
        try:
            output_path.parent.mkdir(parents=True, exist_ok=True)
            cropped.save(output_path)
        finally:
            cropped.close()
    finally:
        image.close()
    return output_path


def plot_summary(
    rows: list[dict[str, int | float | str]],
    fig_dir: Path,
    axes_linewidth: float,
) -> tuple[Path, Path, Path]:
    if not rows:
        raise ValueError("No fragmentation metrics files found.")

    fig_dir.mkdir(parents=True, exist_ok=True)

    life_cycles = [int(row["life_cycle"]) for row in rows]
    fragmented_points = [int(row["points_in_fragmented_logical_voxels"]) for row in rows]
    avg_hash_load = [float(row["avg_hash_load"]) for row in rows]

    x_positions = list(range(len(rows)))
    bar_w = 0.26

    fig, ax = plt.subplots(figsize=(6.28, 5.04))
    fig.subplots_adjust(left=0.17, right=0.82, bottom=0.16, top=0.91)
    ax_hash = ax.twinx()

    bars_points = ax.bar(
        [x - bar_w / 2 for x in x_positions],
        fragmented_points,
        width=bar_w,
        label="Fragmented Points",
        color="#F58518",
    )
    bars_hash = ax_hash.bar(
        [x + bar_w / 2 for x in x_positions],
        avg_hash_load,
        width=bar_w,
        label="Average Hash Load",
        color="#54A24B",
    )

    ax.set_xticks(x_positions)
    tick_font = {"fontname": "Times New Roman", "fontsize": TICK_LABEL_SIZE}
    ax.set_xticklabels([str(v) for v in life_cycles], **tick_font)
    label_font = {"fontname": "Times New Roman", "fontweight": "normal", "fontsize": 18}
    ax.set_xlabel(r"$L_{\mathrm{ret}}$", **label_font)
    ax.set_ylabel("Fragmented Points", **label_font)
    ax_hash.set_ylabel("Average Hash Load", **label_font)
    ax.grid(False)
    ax_hash.grid(False)

    handles = [bars_points, bars_hash]
    labels = [bar.get_label() for bar in handles]
    ax.tick_params(axis="both", labelsize=TICK_LABEL_SIZE, width=axes_linewidth)
    ax_hash.tick_params(axis="y", labelsize=TICK_LABEL_SIZE, width=axes_linewidth)
    for spine in ax.spines.values():
        spine.set_linewidth(axes_linewidth)
    for spine in ax_hash.spines.values():
        spine.set_linewidth(axes_linewidth)
    for label in ax.get_yticklabels() + ax.get_xticklabels():
        label.set_fontname("Times New Roman")
    for label in ax_hash.get_yticklabels():
        label.set_fontname("Times New Roman")
    legend = ax.legend(handles, labels, loc="upper right", frameon=True, fontsize=LEGEND_FONT_SIZE)
    for text in legend.get_texts():
        text.set_fontname("Times New Roman")

    max_value = max(fragmented_points)
    ax.set_ylim(0, max_value * 1.18 if max_value else 1)
    ax_hash.set_ylim(0, 0.55)

    png_path = fig_dir / "life_cycle_fragmentation_summary.png"
    svg_path = fig_dir / "life_cycle_fragmentation_summary.svg"
    pdf_path = fig_dir / "life_cycle_fragmentation_summary.pdf"
    fallback_dir = ROOT / "analysis"
    png_path = save_figure_with_fallback(fig, png_path, fallback_dir, dpi=300)
    svg_path = save_figure_with_fallback(fig, svg_path, fallback_dir)
    pdf_path = save_figure_with_fallback(fig, pdf_path, fallback_dir)
    plt.close(fig)
    return png_path, svg_path, pdf_path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-dir", type=Path, default=DEFAULT_INPUT_DIR)
    parser.add_argument("--fig-dir", type=Path, default=DEFAULT_FIG_DIR)
    parser.add_argument("--hash-capacity", type=int, default=DEFAULT_HASH_CAPACITY)
    parser.add_argument("--axes-linewidth", type=float, default=1.8)
    parser.add_argument("--cropped-output", type=Path, default=DEFAULT_CROPPED_OUTPUT)
    parser.add_argument("--crop-padding", type=int, default=10)
    parser.add_argument("--crop-top-padding", type=int, default=30)
    parser.add_argument("--no-crop", action="store_true")
    parser.add_argument(
        "--summary-csv",
        type=Path,
        default=ROOT / "analysis" / "life_cycle_fragmentation_summary.csv",
    )
    args = parser.parse_args()

    rows = collect_rows(args.input_dir, args.hash_capacity)
    fig_paths = plot_summary(rows, args.fig_dir, args.axes_linewidth)
    summary_csv = write_summary_csv(
        rows,
        args.summary_csv,
        ROOT / "analysis" / args.summary_csv.name,
    )

    print(f"metrics_files={len(rows)}")
    print(f"summary_csv={summary_csv}")
    print("figures=" + ", ".join(str(path) for path in fig_paths))
    if not args.no_crop:
        cropped_path = crop_by_own_content_box(
            fig_paths[0],
            args.cropped_output,
            args.crop_padding,
            args.crop_top_padding,
        )
        print(f"cropped_figure={cropped_path}")
    for row in rows:
        print(
            "life_cycle={life_cycle}, points_in_fragmented_logical_voxels="
            "{points_in_fragmented_logical_voxels}, avg_hash_load={avg_hash_load:.2f}".format(**row)
        )


if __name__ == "__main__":
    main()
