---
sidebar_label: Orbit Graphics
---



# Orbit Graphics

## Moon orbit graphics

Planetslib ships with a set of built in orbit sprites for moons under `__PlanetsLib__/graphics/orbits/moons`, made available as global table `PlanetsLib.constants.orbit_sprites`. Other mods can add new sprites to this table, with no care necessary for how they are sorted.

You can access the orbit settings you need for these sprites by calling `PlanetsLib.get_orbit_sprite(radius)`. The radii are fixed. : 1.39, 1.5, 1.8, 2.65, and 3.95. While not recommended, if a radius is passed to the function that a sprite is not available for, an orbit sprite most appropriate for the provided radius will be returned with scaling appropriate for the radius. Any radius between 66% and 150% of the listed radii will be accepted. 


NOT every possible distance will be available, the sprites need to be generated beforehand. This is added because in practice we know that you only need a default orbit that you can use to make the moon look nice. Clashes can be resolved later, and that works well enough when put into practice.

#### Example

```lua
--Actual code used in planet-muluna
orbit = {
        orientation = 0.75, 
        distance = orbit_radius*o_parent_planet.magnitude/(nauvis.magnitude),
        parent = {
            type = "planet",
            name = parent_planet,
        },
        sprite = PlanetsLib.get_orbit_sprite(orbit_radius*o_parent_planet.magnitude/(nauvis.magnitude))
    },
```
![Muluna's moon orbit sprite](/docs-images/muluna-orbit.png)