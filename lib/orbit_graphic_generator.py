import numpy as np
import matplotlib.pyplot as plt
import os
import math

def generate_orbit(distance, output_file, mod_name):
    """Outputs an orbit sprite for a planet based on its distance, and prints a block of lua code that imports \
        the sprite with correct scaling and sprite size.
        
    The optimal scaling is at 0.25, a scaling that results in sprites that are crisp on all displays.

    If the generated image would be higher than what factorio can support (4096) then quality will be sacrificed for it by increasing the scale. 
    Orbits above 100 start to break, the tool can no longer generate with the default line thickness. 
    Above 200 it becomes a 1 pixel line, with nowhere to scale down anymore, so orbits will appear thicker than they should be.

    distance: The planet's distance from its parent body.
    output_file: The name of the resulting image file, with file format.
    mod_name: The internal name of your mod.

    Example: generate_orbit(1.6, "orbit-muluna.png","planet-muluna")

    """

    
    # No generated image should be larger than this.
    factorio_texture_size_limit=4096

    width=1
    thickness = 3

    
    resolution=512*distance+thickness*2

    radius=distance*64+thickness

    scale_modifier = 1 

    # IF we need orbits above 100 to be fully supported then this check needs to include a branch where it slices up the texture.
    if resolution > factorio_texture_size_limit:
        scale_modifier = factorio_texture_size_limit / resolution * 2
        
        resolution = factorio_texture_size_limit
        resolution_old=resolution
        thickness = thickness *scale_modifier    
    else:
        resolution_old=resolution
        resolution = resolution/2+thickness
    
    resolution=resolution/3.696


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
    ax.set_aspect('equal')
    # ax.fill(outer_x, outer_y, color='blue', label='Outer Boundary')
    # ax.fill(inner_x, inner_y, color='none', label='Inner Boundary')

    from matplotlib.patches import Polygon
    vertices = np.column_stack((np.append(outer_x, inner_x[::-1]), np.append(outer_y, inner_y[::-1])))
    ring = Polygon(vertices, closed=True, color='#191919', lw=thickness/2)
    ax.add_patch(ring)

    # Adjust plot limits and remove axes
    padding = 1*scale_modifier
    ax.set_xlim(-1*width*(radius + thickness  + padding), 1*width*(radius + thickness  + padding))
    ax.set_ylim(-(radius + thickness  + padding), radius + thickness  + padding)
    ax.axis('off')

    # Save to file
    plt.savefig(output_file, bbox_inches="tight",pad_inches=0, dpi=resolution,transparent=True)
    plt.close()

    with open(output_file + ".txt", "w") as orbitcode:
        orbitcode.write("""sprite = {{
            type = "sprite",
            filename = "__{}__/graphics/orbits/{}",
            size = {},
            scale = {},
        }}""".format(mod_name,output_file,math.floor(resolution_old*(1+width)/2), 0.25/scale_modifier))

    print(f"Orbit sprite saved to {os.path.abspath(output_file)}\n")
    print(f"Add this to the 'orbit' field of your planet definition:\n")
    print("""sprite = {{
        type = "sprite",
        filename = "__{}__/graphics/orbits/{}",
        size = {},
        scale = {},
      }}""".format(mod_name,output_file,math.floor(resolution_old*(1+width)/2), 0.25/scale_modifier))

