"""Extract LeRobot training metrics from a log and plot learning curves."""

from __future__ import annotations

import argparse
import csv
import re
from pathlib import Path

METRIC_RE = re.compile(
    r"INFO (?P<timestamp>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}).*?"
    r"step:(?P<display_step>\S+) smpl:(?P<samples>\S+) ep:(?P<episodes>\S+) "
    r"epch:(?P<epochs>[0-9.]+) loss:(?P<loss>[0-9.eE+-]+) "
    r"grdn:(?P<grad_norm>[0-9.eE+-]+) lr:(?P<lr>[0-9.eE+-]+) "
    r"updt_s:(?P<update_s>[0-9.eE+-]+) data_s:(?P<data_s>[0-9.eE+-]+)"
)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("log", type=Path)
    parser.add_argument("--step-interval", type=int, default=200)
    args = parser.parse_args()

    rows = []
    for line in args.log.read_text(encoding="utf-8", errors="replace").splitlines():
        match = METRIC_RE.search(line)
        if not match:
            continue
        row = match.groupdict()
        row["step"] = (len(rows) + 1) * args.step_interval
        rows.append(row)

    if not rows:
        raise SystemExit(f"No training metrics found in {args.log}")

    csv_path = args.log.with_name("training_metrics.csv")
    fields = [
        "timestamp",
        "step",
        "display_step",
        "samples",
        "episodes",
        "epochs",
        "loss",
        "grad_norm",
        "lr",
        "update_s",
        "data_s",
    ]
    with csv_path.open("w", newline="", encoding="utf-8") as file:
        writer = csv.DictWriter(file, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)

    steps = [int(row["step"]) for row in rows]
    losses = [float(row["loss"]) for row in rows]
    gradients = [float(row["grad_norm"]) for row in rows]
    plot_path = args.log.with_name("training_curves.png")
    try:
        import matplotlib.pyplot as plt

        figure, axes = plt.subplots(2, 1, figsize=(10, 8), sharex=True)
        axes[0].plot(steps, losses, linewidth=1.2)
        axes[0].set_ylabel("Loss")
        axes[0].set_yscale("log")
        axes[0].grid(alpha=0.3)
        axes[1].plot(steps, gradients, linewidth=1.2, color="tab:orange")
        axes[1].set_xlabel("Training step")
        axes[1].set_ylabel("Gradient norm")
        axes[1].set_yscale("log")
        axes[1].grid(alpha=0.3)
        figure.suptitle(args.log.stem)
        figure.tight_layout()
        figure.savefig(plot_path, dpi=160)
    except ModuleNotFoundError:
        from math import log10

        from PIL import Image, ImageDraw

        image = Image.new("RGB", (1600, 1200), "white")
        draw = ImageDraw.Draw(image)
        draw.text((50, 20), args.log.stem, fill="black")

        def draw_curve(values: list[float], top: int, label: str, color: str) -> None:
            left, right, bottom = 110, 1550, top + 470
            draw.rectangle((left, top, right, bottom), outline="black", width=2)
            logs = [log10(max(value, 1e-12)) for value in values]
            low, high = min(logs), max(logs)
            span = max(high - low, 1e-9)
            points = [
                (
                    left + int((step - steps[0]) / max(steps[-1] - steps[0], 1) * (right - left)),
                    bottom - int((value - low) / span * (bottom - top)),
                )
                for step, value in zip(steps, logs, strict=True)
            ]
            draw.line(points, fill=color, width=3)
            draw.text((20, top + 210), label, fill="black")
            draw.text((left, bottom + 8), str(steps[0]), fill="black")
            draw.text((right - 70, bottom + 8), str(steps[-1]), fill="black")
            draw.text((right - 160, top + 8), f"max={max(values):.4g}", fill="black")
            draw.text((right - 160, top + 28), f"min={min(values):.4g}", fill="black")

        draw_curve(losses, 70, "Loss (log)", "#1f77b4")
        draw_curve(gradients, 650, "Gradient norm (log)", "#ff7f0e")
        draw.text((720, 1170), "Training step", fill="black")
        image.save(plot_path)
    print(f"Wrote {len(rows)} metric rows to {csv_path}")
    print(f"Wrote training curves to {plot_path}")


if __name__ == "__main__":
    main()
