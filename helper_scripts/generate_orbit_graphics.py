# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy", "matplotlib"]
# ///
"""
Generate orbit sprites for planets in Factorio.

We recommend using uv (https://docs.astral.sh/uv/) to run this script.
uv automatically handles Python and dependency installation:

    uv run generate_orbit_graphics.py <distance> <planet_name> <mod_name>

Example:
    uv run generate_orbit_graphics.py 1.6 muluna planet-muluna

Arguments:
    distance     - Distance from the parent body (e.g., 1.6)
    planet_name  - Name of the planet (e.g., muluna)
    mod_name     - Internal name of your mod (e.g., planet-muluna)
"""

import argparse
import math
import os

import matplotlib.pyplot as plt
import numpy as np
from matplotlib.patches import Polygon


def generate_orbit(distance: float, output_file: str, mod_name: str) -> None:
    """Generate an orbit sprite for a planet based on its distance.

    Outputs an orbit sprite and prints Lua code that imports the sprite with
    correct scaling and sprite size.

    The optimal scaling is at 0.25, resulting in sprites that are crisp on all
    displays. If the generated image would exceed Factorio's 4096 texture limit,
    quality is sacrificed by increasing the scale.

    Orbits above 100 start to break (tool can no longer generate with default
    line thickness). Above 200 it becomes a 1 pixel line with no room to scale.

    Args:
        distance: The planet's distance from its parent body.
        output_file: The name of the resulting image file, with file format.
        mod_name: The internal name of your mod.
    """
    factorio_texture_size_limit = 4096

    width = 1
    thickness = 3

    resolution = 512 * distance + thickness * 2
    radius = distance * 64 + thickness

    scale_modifier = 1

    # If we need orbits above 100 to be fully supported then this check needs
    # to include a branch where it slices up the texture.
    if resolution > factorio_texture_size_limit:
        scale_modifier = factorio_texture_size_limit / resolution * 2
        resolution = factorio_texture_size_limit
        resolution_old = resolution
        thickness = thickness * scale_modifier
    else:
        resolution_old = resolution
        resolution = resolution / 2 + thickness

    resolution = resolution / 3.696

    if thickness <= 0 or radius <= 0:
        raise ValueError("Radius and thickness must be positive.")

    # Generate the outer and inner circles
    theta = np.linspace(0, 2 * np.pi, math.floor(resolution))
    outer_x = (radius + thickness / 2) * np.cos(theta) * width
    outer_y = (radius + thickness / 2) * np.sin(theta)
    inner_x = (radius - thickness / 2) * np.cos(theta) * width
    inner_y = (radius - thickness / 2) * np.sin(theta)

    # Create the figure and axis
    fig, ax = plt.subplots()
    ax.set_aspect("equal")

    vertices = np.column_stack(
        (np.append(outer_x, inner_x[::-1]), np.append(outer_y, inner_y[::-1]))
    )
    ring = Polygon(vertices, closed=True, color="#191919", lw=thickness / 2)
    ax.add_patch(ring)

    # Adjust plot limits and remove axes
    padding = 1 * scale_modifier
    ax.set_xlim(
        -1 * width * (radius + thickness + padding),
        1 * width * (radius + thickness + padding),
    )
    ax.set_ylim(-(radius + thickness + padding), radius + thickness + padding)
    ax.axis("off")

    # Save to file
    plt.savefig(output_file, bbox_inches="tight", pad_inches=0, dpi=resolution, transparent=True)
    plt.close()

    sprite_size = math.floor(resolution_old * (1 + width) / 2)
    scale = 0.25 / scale_modifier

    lua_code = f"""sprite = {{
    type = "sprite",
    filename = "__{mod_name}__/graphics/orbits/{output_file}",
    size = {sprite_size},
    scale = {scale},
}}"""

    with open(output_file + ".txt", "w") as orbitcode:
        orbitcode.write(lua_code)

    print(f"Orbit sprite saved to {os.path.abspath(output_file)}\n")
    print("Add this to the 'orbit' field of your planet definition:\n")
    print(lua_code)


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="generate_orbit_graphics",
        description="Generate orbit sprites for Factorio planets.",
    )
    parser.add_argument("distance", type=float, help="Distance from the parent body")
    parser.add_argument("planet_name", type=str, help="Name of the planet")
    parser.add_argument("mod_name", type=str, help="Internal name of your mod")

    args = parser.parse_args()

    output_file = f"orbit-{args.planet_name}.png"
    generate_orbit(args.distance, output_file, args.mod_name)


if __name__ == "__main__":
    main()