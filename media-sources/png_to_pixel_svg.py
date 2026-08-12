#!/usr/bin/env python3
"""Convert a PNG into an SVG containing one square polygon per visible pixel."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image, UnidentifiedImageError


def png_to_pixel_svg(input_path: Path, output_path: Path) -> int:
    """Convert *input_path* to an SVG and return the polygon count.

    Fully transparent pixels are omitted. Partly transparent pixels retain
    their alpha value through SVG's ``fill-opacity`` attribute.
    """
    if input_path.resolve() == output_path.resolve():
        raise ValueError("The input and output paths must be different.")

    try:
        with Image.open(input_path) as source:
            if source.format != "PNG":
                raise ValueError(f"Not a PNG file: {input_path}")

            image = source.convert("RGBA")
            width, height = image.size
            pixels = image.load()

            output_path.parent.mkdir(parents=True, exist_ok=True)
            polygon_count = 0

            with output_path.open("w", encoding="utf-8", newline="\n") as svg:
                svg.write('<?xml version="1.0" encoding="UTF-8"?>\n')
                svg.write(
                    f'<svg xmlns="http://www.w3.org/2000/svg" '
                    f'width="{width}" height="{height}" '
                    f'viewBox="0 0 {width} {height}" '
                    f'preserveAspectRatio="xMidYMid meet" '
                    f'shape-rendering="crispEdges">\n'
                )
                svg.write('  <g stroke="none">\n')

                for y in range(height):
                    for x in range(width):
                        red, green, blue, alpha = pixels[x, y]

                        # Do not create geometry for fully transparent pixels.
                        if alpha == 0:
                            continue

                        fill = f"#{red:02X}{green:02X}{blue:02X}"
                        opacity = (
                            ""
                            if alpha == 255
                            else f' fill-opacity="{alpha / 255:.8g}"'
                        )
                        points = (
                            f"{x},{y} "
                            f"{x + 1},{y} "
                            f"{x + 1},{y + 1} "
                            f"{x},{y + 1}"
                        )

                        svg.write(
                            f'    <polygon points="{points}" '
                            f'fill="{fill}"{opacity}/>'
                            "\n"
                        )
                        polygon_count += 1

                svg.write("  </g>\n</svg>\n")

            image.close()
            return polygon_count

    except FileNotFoundError as exc:
        raise ValueError(f"Input file not found: {input_path}") from exc
    except UnidentifiedImageError as exc:
        raise ValueError(f"Could not read image: {input_path}") from exc


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Convert a PNG to an SVG containing one 1x1 square polygon "
            "for every nontransparent PNG pixel."
        )
    )
    parser.add_argument("input", type=Path, help="Input PNG file")
    parser.add_argument(
        "output",
        nargs="?",
        type=Path,
        help="Output SVG file; defaults to the input name with a .svg suffix",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    output_path = args.output or args.input.with_suffix(".svg")

    try:
        count = png_to_pixel_svg(args.input, output_path)
    except (OSError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    print(f"Wrote {output_path} ({count} polygons)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
