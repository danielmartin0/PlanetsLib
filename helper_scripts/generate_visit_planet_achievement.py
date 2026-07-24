# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow"]
# ///
"""
Generate visit planet achievement icons for Factorio.

We recommend using uv (https://docs.astral.sh/uv/) to run this script.
uv automatically handles Python and dependency installation:

    uv run generate_visit_planet_achievement.py <path_to_planet_icon>

Example:
    uv run generate_visit_planet_achievement.py planet-icon.png

The script uses resource files (background, overlay, frame masks) that are
bundled with PlanetsLib in the same directory as this script.
"""

import argparse
import os
import sys

from PIL import Image, ImageChops

SIZE = (128, 128)


def generate_achievement_icon(source: str) -> None:
    """Generate an achievement icon from a planet icon.

    Args:
        source: Path to the planet's icon image.
    """
    script_dir = os.path.dirname(os.path.abspath(__file__))

    background = Image.open(os.path.join(script_dir, "visit-planet-background.png"))
    foreground = Image.open(os.path.join(script_dir, "visit-planet-overlay.png"))
    alpha = Image.open(os.path.join(script_dir, "visit-planet-achievement-frame-alpha.png"))
    mask = Image.open(os.path.join(script_dir, "visit-planet-achievement-frame-mask.png"))

    path = os.path.abspath(source)
    outfile = os.path.splitext(path)[0] + "-visit-achievement.png"

    print(f"Source: {path}")
    print(f"Output: {outfile}")

    if path == outfile:
        print("Error: Source and output paths are the same.", file=sys.stderr)
        sys.exit(1)

    try:
        im = Image.open(path).resize(SIZE)
        im = ImageChops.offset(im, 25, 33)
        im = Image.composite(mask, im, alpha)
        back = Image.alpha_composite(background, im)
        Image.alpha_composite(back, foreground).save(outfile, "PNG")
        print(f"Achievement icon saved to {outfile}")
    except IOError as e:
        print(f"Cannot create achievement icon for '{path}': {e}", file=sys.stderr)
        sys.exit(1)


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="generate_visit_planet_achievement",
        description="Generate visit planet achievement icons for Factorio.",
    )
    parser.add_argument("path_to_planet_icon", type=str, help="Path to the planet's icon")

    args = parser.parse_args()
    generate_achievement_icon(args.path_to_planet_icon)


if __name__ == "__main__":
    main()
