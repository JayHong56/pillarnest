from __future__ import annotations

import argparse
import csv
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from PIL import Image

plt.rcParams.update(
    {
        "font.family": "Times New Roman",
        "font.size": 10,
        "axes.linewidth": 0.9,
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
DEFAULT_INPUT_CSV = ROOT / "modelsim_pointpillars_32" / "hash_load_over_time_mulhash.csv"
DEFAULT_FIG_DIR = ROOT / "analysis"
DEFAULT_CROP_REFERENCE = ROOT / "analysis" / "life_cycle_fragmentation_summary.png"
DEFAULT_CROPPED_OUTPUT = ROOT / "analysis" / "life200_hash_load_over_time_cropped.png"
DEFAULT_HASH_CAPACITY = 256
TICK_LABEL_SIZE = 14
LEGEND_FONT_SIZE = 14


def read_hash_load(path: Path, hash_capacity: int) -> tuple[list[int], list[float], list[int]]:
    timers: list[int] = []
    loads: list[float] = []
    collision_counts: list[int] = []
    with path.open("r", newline="", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        if not reader.fieldnames:
            raise ValueError(f"Empty CSV: {path}")

        fields = {name.strip(): name for name in reader.fieldnames}
        timer_field = fields.get("Global_Timer")
        hash_load_field = fields.get("hash_load")
        total_load_field = fields.get("Total_Load")
        collision_count_field = fields.get("collision_count")

        if timer_field is None:
            raise ValueError(f"Missing Global_Timer column in {path}")
        if hash_load_field is None and total_load_field is None:
            raise ValueError(f"Missing hash_load or Total_Load column in {path}")
        if collision_count_field is None:
            raise ValueError(f"Missing collision_count column in {path}")

        for row in reader:
            timer = int(float((row.get(timer_field) or "0").strip()))
            if timer <= 0:
                continue
            if hash_load_field is not None:
                load = float((row.get(hash_load_field) or "0").strip())
            else:
                load = float((row.get(total_load_field) or "0").strip()) / hash_capacity
            collision_count = int(float((row.get(collision_count_field) or "0").strip()))
            timers.append(timer)
            loads.append(load)
            collision_counts.append(collision_count)

    if not timers:
        raise ValueError(f"No rows found in {path}")
    return timers, loads, collision_counts


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


def crop_with_reference_box(
    input_path: Path,
    output_path: Path,
    reference_path: Path,
    padding: int,
    top_padding: int,
) -> Path:
    ref_image = Image.open(reference_path)
    try:
        ref_width, ref_height = ref_image.size
    finally:
        ref_image.close()

    left, top, right, bottom = find_nonwhite_box(reference_path)
    crop_box = (
        max(0, left - padding),
        max(0, top - top_padding),
        min(ref_width, right + padding + 1),
        min(ref_height, bottom + padding + 1),
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


def plot_hash_load(
    timers: list[int],
    loads: list[float],
    collision_counts: list[int],
    fig_dir: Path,
    output_stem: str,
    axes_linewidth: float,
) -> tuple[Path, Path, Path]:
    fig_dir.mkdir(parents=True, exist_ok=True)

    avg_load = sum(loads) / len(loads)
    max_load = max(loads)
    max_index = loads.index(max_load)

    fig, ax = plt.subplots(figsize=(6.28, 5.04))
    fig.subplots_adjust(left=0.17, right=0.82, bottom=0.16, top=0.91)
    ax_collision = ax.twinx()

    line_hash, = ax.plot(
        timers,
        loads,
        label="Hash Load",
        color="#54A24B",
        linewidth=1.8,
    )
    line_avg = ax.axhline(
        avg_load,
        label=f"Average Hash Load = {avg_load:.2f}",
        color="#F58518",
        linewidth=1.8,
        linestyle="--",
    )
    line_collision, = ax_collision.plot(
        timers,
        collision_counts,
        label="Collision Count",
        color="#4C78A8",
        linewidth=1.8,
    )

    label_font = {"fontname": "Times New Roman", "fontweight": "normal", "fontsize": 18}
    ax.set_xlabel("Input Point Index", **label_font)
    ax.set_ylabel("Hash Load", **label_font)
    ax_collision.set_ylabel("Collision Count", **label_font)
    ax.set_ylim(0, 1.0)
    max_collision = max(collision_counts)
    ax_collision.set_ylim(0, max_collision * 1.12 if max_collision else 1)
    x_min = min(timers)
    x_max = max(timers)
    x_margin = (x_max - x_min) * 0
    ax.set_xlim(x_min, x_max + x_margin)
    ax_collision.set_xlim(x_min, x_max + x_margin)
    ax.grid(False)
    ax_collision.grid(False)
    ax.tick_params(axis="both", labelsize=TICK_LABEL_SIZE, width=axes_linewidth)
    ax_collision.tick_params(axis="y", labelsize=TICK_LABEL_SIZE, width=axes_linewidth)
    for spine in ax.spines.values():
        spine.set_linewidth(axes_linewidth)
    for spine in ax_collision.spines.values():
        spine.set_linewidth(axes_linewidth)
    ax.legend(
        [line_hash, line_avg, line_collision],
        [line_hash.get_label(), line_avg.get_label(), line_collision.get_label()],
        loc="upper left",
        frameon=True,
        fontsize=LEGEND_FONT_SIZE,
    )

    ax.text(
        timers[max_index] + (x_max - x_min) * -0.005,
        max_load,
        f"Max {max_load:.2f}",
        va="bottom",
        ha="center",
        fontsize=9,
    )

    png_path = fig_dir / f"{output_stem}.png"
    svg_path = fig_dir / f"{output_stem}.svg"
    pdf_path = fig_dir / f"{output_stem}.pdf"
    fallback_dir = ROOT / "analysis"
    png_path = save_figure_with_fallback(fig, png_path, fallback_dir, dpi=300)
    svg_path = save_figure_with_fallback(fig, svg_path, fallback_dir)
    pdf_path = save_figure_with_fallback(fig, pdf_path, fallback_dir)
    plt.close(fig)
    return png_path, svg_path, pdf_path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-csv", type=Path, default=DEFAULT_INPUT_CSV)
    parser.add_argument("--fig-dir", type=Path, default=DEFAULT_FIG_DIR)
    parser.add_argument("--hash-capacity", type=int, default=DEFAULT_HASH_CAPACITY)
    parser.add_argument("--output-stem", default="life200_hash_load_over_time")
    parser.add_argument("--axes-linewidth", type=float, default=1.8)
    parser.add_argument("--crop-reference", type=Path, default=DEFAULT_CROP_REFERENCE)
    parser.add_argument("--cropped-output", type=Path, default=DEFAULT_CROPPED_OUTPUT)
    parser.add_argument("--crop-padding", type=int, default=10)
    parser.add_argument("--crop-top-padding", type=int, default=30)
    parser.add_argument("--no-crop", action="store_true")
    args = parser.parse_args()

    timers, loads, collision_counts = read_hash_load(args.input_csv, args.hash_capacity)
    fig_paths = plot_hash_load(
        timers,
        loads,
        collision_counts,
        args.fig_dir,
        args.output_stem,
        args.axes_linewidth,
    )

    print(f"input_csv={args.input_csv}")
    print(f"rows={len(loads)}")
    print(f"avg_hash_load={sum(loads) / len(loads):.2f}")
    print(f"max_hash_load={max(loads):.2f}")
    print(f"max_collision_count={max(collision_counts)}")
    print("figures=" + ", ".join(str(path) for path in fig_paths))
    if not args.no_crop:
        cropped_path = crop_with_reference_box(
            fig_paths[0],
            args.cropped_output,
            args.crop_reference,
            args.crop_padding,
            args.crop_top_padding,
        )
        print(f"cropped_figure={cropped_path}")


if __name__ == "__main__":
    main()
