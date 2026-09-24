---
sidebar_label: Orbit Graphics
---



# Orbit Graphics

## Moon orbit graphics

Before Factorio 2.1.20, it was not possible to render orbit lines that did not center on the main star. To get around this issue, PlanetsLib added features to enable placing sprites on the starmap, in addition to a Python script(`helper_scripts/generate_orbit_graphics.py`) to generate sprites ressembling orbits. With 2.1.20, this feature is largely obsolete, but it is still supported for developers that wish to create orbits with an appearance different from vanilla orbits.

#### Example

```lua
orbit = {
        orientation = 0.75, 
        distance = 2,
        parent = {
            type = "planet",
            name = parent_planet,
        },
        draw_orbit = true,
        -- OR
        sprite = {
				type = "sprite",
				filename = "__Cerys-Moon-of-Fulgora__/graphics/icons/orbit.png",
				size = 379,
				scale = 0.25,
		},
    },
```
![Muluna's moon orbit](/docs-images/muluna-orbit.png)
![Apia-Carnova's barycenter orbit sprite](/docs-images/Apia-Carnova.png)